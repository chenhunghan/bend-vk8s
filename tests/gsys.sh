#!/usr/bin/env bash
# The guest system call effects (host/effs/gsys.c, host/gsys.bend) end to
# end, against the tools they replace. It builds tests/gsys_echo.bend
# natively, prepares one scratch directory (a few dozen files and two
# logs of 33 MiB and 1 MiB), runs the program on it, and compares:
# mkdir -p (through a link to a directory, under a file, again), test -d
# and test -f (through links), mountpoint, ls, the Usage walk with
# `du -sk` and `find | wc -l` (hard links once), rm -f, mv -f, rmdir,
# rm -rf (a link in the tree is removed, its target kept), and the log
# trim with `tail -c 8388608`. It never mounts, trims a disk or sets the
# clock (those need root and a VM: scripts/bench/guest-spawns.sh).
#
# Needs bend and clang. Prints PASS/FAIL lines; exits 1 on any FAIL.
set -uo pipefail
cd "$(dirname "$0")/.."

mkdir -p out
tmp=$(mktemp -d out/gsys-test.XXXXXX)
trap 'rm -rf "$tmp"' EXIT

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
check() { local name=$1; shift; if "$@"; then pass "$name"; else fail "$name"; fi; }
line() { grep "^$1 " "$tmp/out.txt" | head -1 | cut -d' ' -f2-; }
is() { # is NAME KEY EXPECTED
  local got; got=$(line "$2")
  if [ "$got" = "$3" ]; then pass "$1"; else fail "$1: got '$got', want '$3'"; fi
}

echo "== build"
if ! bend tests/gsys_echo.bend -o "$tmp/echo" >"$tmp/build.log" 2>&1; then
  cat "$tmp/build.log"; fail "build"; exit 1
fi
pass "build"

d=$tmp/d
mkdir -p "$d/real" "$d/tree/sub/deep" "$d/empty" "$d/doomed/in" "$d/kept" "$d/logs"
ln -s real "$d/link"
echo x > "$d/file"; ln -s file "$d/filelink"
echo a > "$d/gone1"; echo b > "$d/gone2"
echo new > "$d/state.tmp"; echo old > "$d/state"
# the tree: files of several sizes, a hard link, a link, a hidden name
head -c 5000 /dev/zero | tr '\0' 'a' > "$d/tree/five"
head -c 70000 /dev/zero | tr '\0' 'b' > "$d/tree/sub/seventy"
: > "$d/tree/sub/deep/empty"
ln "$d/tree/five" "$d/tree/sub/five-again"
ln -s five "$d/tree/to-five"
echo h > "$d/tree/.hidden"
# rm -rf: a link out of the tree keeps its target
echo keep > "$d/kept/file"; ln -s ../kept "$d/doomed/out"; echo z > "$d/doomed/in/z"
# the logs: one past 32 MiB, one small, one that is no *.log, a hidden one
perl -e 'for my $i (0 .. 33) { print chr(65 + $i % 26) x 1048576 }' > "$d/logs/big.log"
head -c 1048576 /dev/zero > "$d/logs/small.log"
perl -e 'print "x" x 34603008' > "$d/logs/big.txt"
perl -e 'print "y" x 34603008' > "$d/logs/.hidden.log"
echo stale > "$d/logs/big.log.1"
tail -c 8388608 "$d/logs/big.log" > "$tmp/want.1"
want_kib=$(du -sk "$d/tree" | cut -f1)
want_n=$(find "$d/tree" | wc -l | tr -d ' ')
want_ls=$(ls -1a "$d/tree" | grep -vx '\.' | grep -vx '\.\.' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')

echo "== run"
"$tmp/echo" "$d" > "$tmp/out.txt" 2>&1
check "the program ends" grep -qx done "$tmp/out.txt"

is "mkdir -p makes every path, one through a link to a directory" mkdirs yes
check "mkdir -p made a/b" test -d "$d/made/a/b"
check "mkdir -p made c past doubled and trailing slashes" test -d "$d/made/c"
check "mkdir -p went through the link" test -d "$d/real/under"
is "mkdir -p under a regular file fails" mkdir_under_file no
is "mkdir -p of a directory already there is fine" mkdir_again yes
is "test -d: a link to a directory, a file, nothing" is_dir "yes no no"
is "test -f: a file, a link to one, a directory" is_file "yes yes no"
is "mountpoint: /, a plain directory, a file" mountpoint "yes no no"
got_ls=$(line ls | tr ' ' '\n' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
check "ls: every name but . and .. (got '$got_ls')" test "$got_ls" = "$want_ls"
is "ls of a missing directory" ls_missing none
is "usage: du -sk and find | wc -l" usage "$want_kib $want_n"
is "usage of a missing path" usage_missing none
is "warm reads every file" warm yes
is "rm -f: files and a missing path; a directory fails" unlinks "yes no"
check "rm -f removed the files" test ! -e "$d/gone1" -a ! -e "$d/gone2"
check "rm -f left the directory" test -d "$d/made"
is "mv -f onto a file; from a missing path" rename "yes no"
check "mv -f replaced the file" test "$(cat "$d/state")" = new
check "mv -f left no .tmp" test ! -e "$d/state.tmp"
is "rmdir: an empty directory; one with entries" rmdir "yes no"
is "rm -rf" rm_rf yes
check "rm -rf removed the tree" test ! -e "$d/doomed"
check "rm -rf kept the link's target" test -f "$d/kept/file"
check "trim: the big log is emptied in place" test ! -s "$d/logs/big.log"
check "trim: its last 8 MiB are big.log.1" cmp -s "$d/logs/big.log.1" "$tmp/want.1"
check "trim: the small log is untouched" test "$(wc -c < "$d/logs/small.log" | tr -d ' ')" = 1048576
check "trim: a name that is no *.log is untouched" test "$(wc -c < "$d/logs/big.txt" | tr -d ' ')" = 34603008
check "trim: a hidden log is untouched" test "$(wc -c < "$d/logs/.hidden.log" | tr -d ' ')" = 34603008
check "trim: no small.log.1" test ! -e "$d/logs/small.log.1"

[ $fails = 0 ] || { echo "--- program output"; cat "$tmp/out.txt"; }
exit $((fails > 0))
