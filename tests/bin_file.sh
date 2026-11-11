#!/usr/bin/env bash
# The binary file effects (host/effs/bin_file.c) end to end. It builds
# tests/bin_file_echo.bend natively and runs it on a scratch directory
# under umask 000: the program writes every byte value 0..255, a 3 MiB
# file and a short file over an existing longer one, reads them back by
# range, copies two of them with BinFile.read_all and BinFile.write, and
# checks the error answers. This script compares the files with what perl
# writes, with cmp and sha256sum, and checks that every file the program
# created has mode 0600.
#
# Needs bend, clang, perl, sha256sum (or shasum). Prints PASS/FAIL lines;
# exits 1 on any FAIL.
set -uo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
check() { # check NAME CONDITION-COMMAND...
  local name=$1; shift
  if "$@"; then pass "$name"; else fail "$name"; fi
}
sha() { # sha FILE: its SHA-256, in hex
  if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}
mode() { # mode FILE: its permission bits, in octal
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
}
size() { # size FILE: its size in bytes
  wc -c <"$1" | tr -d ' '
}

echo "== build"
if ! bend tests/bin_file_echo.bend -o "$tmp/echo" >"$tmp/build.log" 2>&1; then
  cat "$tmp/build.log"
  echo "FAIL build tests/bin_file_echo.bend"
  exit 1
fi
pass "build"

echo "== no arguments"
out=$("$tmp/echo" 2>&1)
check "native lane: BinFile.open of a missing file answers ENOENT" \
  grep -qx 'PASS bin_file_echo: BinFile.open answers ENOENT (native lane)' <<<"$out"

echo "== run"
d="$tmp/d"
mkdir "$d"
printf 'old content, longer than three bytes\n' >"$d/pre.bin"
chmod 0644 "$d/pre.bin"
out=$(umask 000 && "$tmp/echo" "$d" 2>&1)
echo "$out" | grep '^PASS\|^FAIL'
n_fail=$(grep -c '^FAIL' <<<"$out")
fails=$((fails + n_fail))
check "the program ran to the end" grep -qx 'done' <<<"$out"
if ! grep -qx 'done' <<<"$out"; then echo "$out" | tail -20; fi

echo "== bytes"
perl -e 'binmode STDOUT; print map { chr } 0..255' >"$tmp/all256.want"
perl -e 'binmode STDOUT; for my $c (0..47) { print join "", map { chr($_ % 251) } ($c * 65536)..($c * 65536 + 65535) }' >"$tmp/big.want"
printf '\001\002\003' >"$tmp/pre.want"
check "all256.bin holds every byte value 0..255" cmp -s "$d/all256.bin" "$tmp/all256.want"
check "all256.copy matches" cmp -s "$d/all256.copy" "$tmp/all256.want"
check "big.bin is 3145728 bytes" test "$(size "$d/big.bin")" = 3145728
check "big.bin matches" cmp -s "$d/big.bin" "$tmp/big.want"
want=$(sha "$tmp/big.want")
check "big.bin sha256 matches" test "$(sha "$d/big.bin")" = "$want"
check "big.copy sha256 matches" test "$(sha "$d/big.copy")" = "$want"
check "pre.bin truncated to 1 2 3" cmp -s "$d/pre.bin" "$tmp/pre.want"
check "bad.bin is empty after a refused append" test "$(size "$d/bad.bin")" = 0

echo "== modes (umask 000)"
for f in all256.bin big.bin pre.bin all256.copy big.copy bad.bin; do
  check "$f has mode 600 (got $(mode "$d/$f"))" test "$(mode "$d/$f")" = 600
done

if [ "$fails" -ne 0 ]; then
  echo "$fails FAILED"
  exit 1
fi
echo "ALL PASS"
