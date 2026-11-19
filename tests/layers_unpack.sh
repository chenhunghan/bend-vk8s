#!/usr/bin/env bash
# The layer unpack pipeline (host/layers/unpack.bend over
# host/layers/fs.bend, OciBlob.hash and bend-kube's Unz.file) end to end.
# It builds tests/layer_unpack_echo.bend natively, writes image layers
# with Python's tarfile (USTAR and PAX: a directory, files, a symlink, a
# hard link, a char device, a FIFO, a whiteout, an opaque directory, a
# non-ASCII name and a long name), compresses them with gzip (and zstd
# when the zstd CLI is there), and checks what lands under ROOT/layers:
#
# - file data, symlink targets, hard links (one inode), devices, FIFOs
#   and whiteouts as empty files, hashed host names;
# - the .bend-meta files (types, modes, device numbers, the opaque
#   xattr) and the record under ROOT/layer-refs;
# - a second unpack of the same layer loses the publish race ("present")
#   and leaves no tmp entry;
# - a wrong diffID, a "../" name and truncated data are refused and leave
#   neither a layer nor a tmp entry;
# - a gzip bomb (64 MiB of zeros in about 64 KiB) passes the size cap
#   (Fill.unz.mib: 50 times the blob) and is refused, leaving no tmp
#   entry; a layer below the cap still publishes;
# - a hard link whose target is a symlink to a host file never links the
#   host file (its link count and data stay), and an entry under a
#   symlink to a host directory is refused and writes nothing there;
# - fills and gc with per-layer locks (v2, tests/layer_fill_echo.bend,
#   the clock faked): three fills of one layer at once publish it once;
#   gc skips a layer whose lock a fill holds, and a gc beside a fill
#   leaves the layer there; a killed fill leaves no layer, its lock
#   makes the next fill wait until it is 60 minutes old, then is taken
#   over; a stale store-wide layers.lock blocks neither fill nor gc.
#
# With LAYERS_BIG_GIB=N (N >= 5) it also unpacks an uncompressed layer
# with an N GiB file of zeros followed by a small file, so offsets pass
# 2^32 (it needs about 2N GiB of disk).
#
# Needs bend, clang, python3, sha256sum (or shasum). Prints PASS/FAIL
# lines; exits 1 on any FAIL.
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
inode() { stat -c %i "$1" 2>/dev/null || stat -f %i "$1"; }
size() { wc -c <"$1" | tr -d ' '; }

echo "== build"
if ! bend tests/layer_unpack_echo.bend -o "$tmp/echo" >"$tmp/build.log" 2>&1; then
  cat "$tmp/build.log"
  echo "FAIL build tests/layer_unpack_echo.bend"
  exit 1
fi
pass "build"
if ! bend tests/layer_fill_echo.bend -o "$tmp/fecho" >"$tmp/fbuild.log" 2>&1; then
  cat "$tmp/fbuild.log"
  echo "FAIL build tests/layer_fill_echo.bend"
  exit 1
fi
pass "build v2"

echo "== no arguments"
out=$("$tmp/echo" 2>&1)
check "native lane: LayerFs.make in a missing directory answers ENOENT" \
  grep -qx 'PASS layer_unpack_echo: LayerFs.make in a missing directory answers ENOENT (native lane)' <<<"$out"

echo "== layers"
mkdir -p "$tmp/gen"
python3 -I - "$tmp" <<'PY'
import io, sys, tarfile
tmp = sys.argv[1]

def add(t, name, kind, data=b"", **kw):
    i = tarfile.TarInfo(name)
    i.type = kind
    i.mtime = 1700000000
    i.mode = kw.get("mode", 0o644)
    i.uid = kw.get("uid", 0)
    i.gid = kw.get("gid", 0)
    i.linkname = kw.get("link", "")
    i.devmajor = kw.get("major", 0)
    i.devminor = kw.get("minor", 0)
    i.size = len(data) if kind == tarfile.REGTYPE else 0
    t.addfile(i, io.BytesIO(data) if kind == tarfile.REGTYPE else None)

with tarfile.open(f"{tmp}/gen/full.tar", "w", format=tarfile.PAX_FORMAT) as t:
    add(t, "etc", tarfile.DIRTYPE, mode=0o755)
    add(t, "etc/hosts", tarfile.REGTYPE, b"127.0.0.1 localhost\n")
    add(t, "etc/mtab", tarfile.SYMTYPE, link="/proc/mounts", mode=0o777)
    add(t, "etc/hosts2", tarfile.LNKTYPE, link="etc/hosts")
    add(t, "dev/null", tarfile.CHRTYPE, mode=0o666, major=1, minor=3)
    add(t, "run/initctl", tarfile.FIFOTYPE, mode=0o600)
    add(t, "usr/.wh.gone", tarfile.REGTYPE, b"")
    add(t, "opt", tarfile.DIRTYPE, mode=0o755)
    add(t, "opt/.wh..wh..opq", tarfile.REGTYPE, b"")
    add(t, "café", tarfile.REGTYPE, b"x")
    add(t, "d/" + "x" * 150, tarfile.REGTYPE, b"long")
    add(t, "bin/sh", tarfile.REGTYPE, b"#!" * 700, mode=0o4755, uid=7, gid=8)

with tarfile.open(f"{tmp}/gen/evil.tar", "w", format=tarfile.USTAR_FORMAT) as t:
    add(t, "../evil", tarfile.REGTYPE, b"no")
PY
gzip -9 -c "$tmp/gen/full.tar" >"$tmp/gen/full.tar.gz"
gzip -9 -c "$tmp/gen/evil.tar" >"$tmp/gen/evil.tar.gz"
diff="sha256:$(sha "$tmp/gen/full.tar")"
hex=${diff#sha256:}
gz=application/vnd.oci.image.layer.v1.tar+gzip
root="$tmp/root"
mkdir -p "$root"

echo "== gzip"
out=$("$tmp/echo" "$root" "$tmp/gen/full.tar.gz" "$gz" "$diff" "$(size "$tmp/gen/full.tar.gz")" 2>&1)
echo "$out"
check "published (below the size cap)" test "$out" = "published"
l="$root/layers/$hex"
check "file data" test "$(cat "$l/etc/hosts")" = "127.0.0.1 localhost"
check "symlink target" test "$(readlink "$l/etc/mtab")" = "/proc/mounts"
check "hard link shares the inode" test "$(inode "$l/etc/hosts")" = "$(inode "$l/etc/hosts2")"
check "a device is an empty file" test -f "$l/dev/null" -a ! -s "$l/dev/null"
check "a FIFO is an empty file" test -f "$l/run/initctl" -a ! -s "$l/run/initctl"
check "a whiteout is an empty file" test -f "$l/usr/gone" -a ! -s "$l/usr/gone"
check "a long PAX name" test "$(cat "$l/d/$(printf 'x%.0s' $(seq 150))")" = "long"
check "a non-ASCII name is hashed" test "$(ls -A "$l" | grep -c '^\.bend-[0-9a-f]\{32\}$')" = 1
check "the setuid file's data" test "$(size "$l/bin/sh")" = 1400
meta=$(cat "$l/.bend-meta" "$l/dev/.bend-meta" "$l/usr/.bend-meta" "$l/bin/.bend-meta" 2>/dev/null)
check ".bend-meta at the root" grep -q '^bend-meta 1$' "$l/.bend-meta"
check ".bend-meta: the device" grep -q 'name=null host=null type=c mode=666 uid=0 gid=0 rdev=1,3 ' <<<"$meta"
check ".bend-meta: the whiteout" grep -q 'name=gone host=gone type=c mode=0 uid=0 gid=0 rdev=0,0 ' <<<"$meta"
check ".bend-meta: the opaque directory" grep -q 'name=opt host=opt type=d .*xattr.trusted.overlay.opaque=79' "$l/.bend-meta"
check ".bend-meta: setuid and owner" grep -q 'name=sh host=sh type=f mode=4755 uid=7 gid=8 ' <<<"$meta"
check ".bend-meta: the hard links" test "$(grep -c 'nlink=2' "$l/etc/.bend-meta")" = 2
check "the record" grep -qx "chain $diff" "$root/layer-refs/$hex"
check "no tmp entry left" test -z "$(ls "$root/tmp")"

echo "== again"
out=$("$tmp/echo" "$root" "$tmp/gen/full.tar.gz" "$gz" "$diff" 2>&1)
echo "$out"
check "a second unpack finds it published" test "$out" = "present"
check "no tmp entry left after the lost race" test -z "$(ls "$root/tmp")"

echo "== refusals"
out=$("$tmp/echo" "$tmp/r2" "$tmp/gen/full.tar.gz" "$gz" "sha256:$(printf '0%.0s' $(seq 64))" 2>&1)
echo "$out"
check "a wrong diffID is refused" grep -q "not its diffID" <<<"$out"
check "nothing published for a wrong diffID" test -z "$(ls "$tmp/r2/layers" 2>/dev/null)"
check "no tmp entry left for a wrong diffID" test -z "$(ls "$tmp/r2/tmp" 2>/dev/null)"
ediff="sha256:$(sha "$tmp/gen/evil.tar")"
out=$("$tmp/echo" "$tmp/r3" "$tmp/gen/evil.tar.gz" "$gz" "$ediff" 2>&1)
echo "$out"
check "a ../ name is refused" grep -q "path traversal" <<<"$out"
check "nothing escapes the store" test ! -e "$tmp/evil" -a ! -e "$tmp/r3/evil"
check "no tmp entry left for a refused layer" test -z "$(ls "$tmp/r3/tmp" 2>/dev/null)"
head -c 1030 "$tmp/gen/full.tar" >"$tmp/gen/short.tar"
sdiff="sha256:$(sha "$tmp/gen/short.tar")"
out=$("$tmp/echo" "$tmp/r4" "$tmp/gen/short.tar" application/vnd.oci.image.layer.v1.tar "$sdiff" 2>&1)
echo "$out"
check "a truncated tar is refused" grep -q "^error " <<<"$out"
check "no tmp entry left for a truncated tar" test -z "$(ls "$tmp/r4/tmp" 2>/dev/null)"

echo "== unpack limits and links to the host"
mkdir -p "$tmp/host/dir"
printf 'host data\n' >"$tmp/host/file"
python3 -I - "$tmp" <<'PY'
import io, sys, tarfile
tmp = sys.argv[1]

def add(t, name, kind, data=b"", link=""):
    i = tarfile.TarInfo(name)
    i.type = kind
    i.mtime = 1700000000
    i.mode = 0o644
    i.linkname = link
    i.size = len(data) if kind == tarfile.REGTYPE else 0
    t.addfile(i, io.BytesIO(data) if kind == tarfile.REGTYPE else None)

class Zeros:
    def __init__(self, n): self.n = n
    def read(self, k=-1):
        k = self.n if k < 0 else min(k, self.n)
        self.n -= k
        return bytes(k)

with tarfile.open(f"{tmp}/gen/bomb.tar", "w", format=tarfile.PAX_FORMAT) as t:
    i = tarfile.TarInfo("zeros"); i.size = 64 << 20; i.mtime = 1700000000
    t.addfile(i, Zeros(i.size))

with tarfile.open(f"{tmp}/gen/hardsym.tar", "w", format=tarfile.PAX_FORMAT) as t:
    add(t, "lnk", tarfile.SYMTYPE, link=f"{tmp}/host/file")
    add(t, "hl", tarfile.LNKTYPE, link="lnk")

with tarfile.open(f"{tmp}/gen/undersym.tar", "w", format=tarfile.PAX_FORMAT) as t:
    add(t, "s", tarfile.SYMTYPE, link=f"{tmp}/host/dir")
    add(t, "s/x", tarfile.REGTYPE, b"escaped")
PY
nlink() { stat -c %h "$1" 2>/dev/null || stat -f %l "$1"; }
gzip -9 -c "$tmp/gen/bomb.tar" >"$tmp/gen/bomb.tar.gz"
bdiff="sha256:$(sha "$tmp/gen/bomb.tar")"
out=$("$tmp/echo" "$tmp/r7" "$tmp/gen/bomb.tar.gz" "$gz" "$bdiff" "$(size "$tmp/gen/bomb.tar.gz")" 2>&1)
echo "$out"
check "a gzip bomb passes the size cap and is refused" grep -q "past its limit" <<<"$out"
check "nothing published for a gzip bomb" test -z "$(ls "$tmp/r7/layers" 2>/dev/null)"
check "no tmp entry left for a gzip bomb" test -z "$(ls "$tmp/r7/tmp" 2>/dev/null)"
gzip -9 -c "$tmp/gen/hardsym.tar" >"$tmp/gen/hardsym.tar.gz"
hdiff="sha256:$(sha "$tmp/gen/hardsym.tar")"
out=$("$tmp/echo" "$tmp/r8" "$tmp/gen/hardsym.tar.gz" "$gz" "$hdiff" 2>&1)
echo "$out"
check "a hard link to a symlink leaves the host file's link count" test "$(nlink "$tmp/host/file")" = 1
check "a hard link to a symlink leaves the host file's data" test "$(cat "$tmp/host/file")" = "host data"
hl="$tmp/r8/layers/${hdiff#sha256:}/hl"
if [ "$out" = published ]; then
  check "the hard link is not the host file" test "$(inode "$hl")" != "$(inode "$tmp/host/file")"
  check "the hard link is the symlink itself" test "$(readlink "$hl")" = "$tmp/host/file"
else
  check "a refused hard link to a symlink leaves no tmp entry" test -z "$(ls "$tmp/r8/tmp" 2>/dev/null)"
fi
gzip -9 -c "$tmp/gen/undersym.tar" >"$tmp/gen/undersym.tar.gz"
udiff="sha256:$(sha "$tmp/gen/undersym.tar")"
out=$("$tmp/echo" "$tmp/r9" "$tmp/gen/undersym.tar.gz" "$gz" "$udiff" 2>&1)
echo "$out"
check "an entry under a symlink is refused" grep -q "under a non-directory or a symlink" <<<"$out"
check "nothing written through the symlink" test -z "$(ls -A "$tmp/host/dir")"
check "no tmp entry left for an entry under a symlink" test -z "$(ls "$tmp/r9/tmp" 2>/dev/null)"

if command -v zstd >/dev/null; then
  echo "== zstd"
  zstd -q -19 -c "$tmp/gen/full.tar" >"$tmp/gen/full.tar.zst"
  out=$("$tmp/echo" "$tmp/r5" "$tmp/gen/full.tar.zst" application/vnd.oci.image.layer.v1.tar+zstd "$diff" 2>&1)
  echo "$out"
  if grep -q "brew install zstd" <<<"$out"; then
    pass "no libzstd: the error names the fix"
  else
    check "zstd published" test "$out" = "published"
    check "zstd file data" test "$(cat "$tmp/r5/layers/$hex/etc/hosts")" = "127.0.0.1 localhost"
  fi
fi

echo "== v2: per-layer locks"
out=$("$tmp/fecho" 2>&1)
check "v2 native lane: a fill under a missing directory answers ENOENT" \
  grep -qx 'PASS layer_fill_echo: Lu.layer.v2 under a missing directory answers ENOENT (native lane)' <<<"$out"
now=1763337600
day=86400
gcage=$((3 * day + 10)) # past gc's 72 h
gzsize=$(size "$tmp/gen/full.tar.gz")
fill2() { # fill2 ROOT NOW: the full layer, filled under its lock at NOW
  "$tmp/fecho" fill "$1" "$tmp/gen/full.tar.gz" "$gz" "$diff" "$gzsize" "$2" 2>&1
}
gc2() { "$tmp/fecho" gc "$1" "$2" 2>&1; } # gc2 ROOT NOW
v="$tmp/v2"

echo "-- three fills of one layer at once"
for i in 1 2 3; do fill2 "$v" "$now" >"$tmp/v2.$i" & done
wait
cat "$tmp"/v2.[123]
check "three fills at once publish once" test "$(cat "$tmp"/v2.[123] | grep -cx published)" = 1
check "the two others find it present" test "$(cat "$tmp"/v2.[123] | grep -cx present)" = 2
check "the layer is whole" test "$(cat "$v/layers/$hex/etc/hosts")" = "127.0.0.1 localhost"
check "no layer lock left" test -z "$(ls -A "$v/layer-locks")"
check "no tmp entry left by three fills" test -z "$(ls -A "$v/tmp")"
check "the store-wide lock is not taken" test ! -e "$v/layers.lock"

echo "-- gc beside a fill"
t=$((now + gcage))
printf '%s\n' "$t" >"$v/layer-locks/$hex" # a fill in progress holds it
out=$(gc2 "$v" "$t")
echo "$out"
check "gc skips a layer whose lock a fill holds" grep -q "gc skipped $diff: a fill holds" <<<"$out"
check "gc ends well beside a fill" test "$(tail -n 1 <<<"$out")" = ok
check "gc removes nothing a fill holds" test -d "$v/layers/$hex" -a -f "$v/layer-refs/$hex" -a -f "$v/layers/$hex.rec"
check "gc leaves the fill's lock" test "$(cat "$v/layer-locks/$hex")" = "$t"
rm "$v/layer-locks/$hex"
out=$(gc2 "$v" "$t")
echo "$out"
check "without the lock gc removes the old layer" grep -q "removed $diff" <<<"$out"
check "the layer, its record and its copy go" test ! -e "$v/layers/$hex" -a ! -e "$v/layer-refs/$hex" -a ! -e "$v/layers/$hex.rec"
check "gc lets its lock go" test -z "$(ls -A "$v/layer-locks")"
# A fill and a gc at once, each time 72 h after the layer's last use:
# whichever takes the layer's lock first, the layer is there after both
# (the fill touched it and gc kept it, or gc removed it and the fill
# published it again).
t=$now
check "a fill before the races" test "$(fill2 "$v" "$t")" = published
ok=1
for i in 1 2 3 4 5; do
  t=$((t + gcage))
  fill2 "$v" "$t" >"$tmp/race.fill" &
  gc2 "$v" "$t" >"$tmp/race.gc"
  wait
  f=$(cat "$tmp/race.fill")
  echo "race $i: fill $f; gc $(tail -n 2 "$tmp/race.gc" | head -n 1)"
  if [ "$f" != present ] && [ "$f" != published ]; then ok=0; fi
  if [ "$(tail -n 1 "$tmp/race.gc")" != ok ]; then ok=0; fi
  if [ "$(cat "$v/layers/$hex/etc/hosts" 2>/dev/null)" != "127.0.0.1 localhost" ]; then ok=0; fi
  if ! grep -qx "last-use $t" "$v/layer-refs/$hex"; then ok=0; fi
done
check "a gc beside a fill never takes the layer from it" test "$ok" = 1
check "no layer lock left after the races" test -z "$(ls -A "$v/layer-locks")"

echo "-- a killed fill"
k="$tmp/v2k"
mkdir -p "$k/layer-locks" "$k/tmp/$hex.$now"
# What a fill killed while it unpacked leaves: its lock, its tmp
# directory with part of the layer, its tar.
printf '%s\n' "$now" >"$k/layer-locks/$hex"
printf 'part' >"$k/tmp/$hex.$now/half"
printf 'tar' >"$k/tmp/$hex.$now.tar"
check "a killed fill leaves no layer" test ! -e "$k/layers/$hex" -a ! -e "$k/layer-refs/$hex"
# Not through fill2: $! must be the fill itself, so the kill reaches it.
"$tmp/fecho" fill "$k" "$tmp/gen/full.tar.gz" "$gz" "$diff" "$gzsize" $((now + 3599)) >"$tmp/kill.out" 2>&1 &
pid=$!
sleep 3
if kill -0 "$pid" 2>/dev/null; then waited=1; kill -9 "$pid"; else waited=0; fi
wait "$pid" 2>/dev/null
cat "$tmp/kill.out"
check "a fill waits on a lock 59 minutes old" test "$waited" = 1
check "a fill killed while it waits leaves no layer" test ! -e "$k/layers/$hex"
check "a fill killed while it waits leaves the lock as it was" test "$(cat "$k/layer-locks/$hex")" = "$now"
out=$(fill2 "$k" $((now + 3600)))
echo "$out"
check "a lock 60 minutes old is taken over" test "$out" = published
check "the layer after the takeover" test "$(cat "$k/layers/$hex/etc/hosts")" = "127.0.0.1 localhost"
check "no layer lock left after the takeover" test -z "$(ls -A "$k/layer-locks")"
out=$(gc2 "$k" $((now + day)))
echo "$out"
check "gc removes the killed fill's tmp entries a day later" test -z "$(ls -A "$k/tmp")"
check "gc keeps the layer filled since" test -d "$k/layers/$hex"

echo "-- a stale layers.lock"
s="$tmp/v2s"
mkdir -p "$s"
printf '100\n' >"$s/layers.lock"
out=$(fill2 "$s" "$now")
echo "$out"
check "a stale layers.lock does not block a fill" test "$out" = published
out=$(gc2 "$s" $((now + gcage)))
echo "$out"
check "a stale layers.lock does not block gc" test "$(tail -n 1 <<<"$out")" = ok
check "gc v2 removes the unused layer" test ! -e "$s/layers/$hex"
check "layers.lock is left alone" test "$(cat "$s/layers.lock")" = 100

big=${LAYERS_BIG_GIB:-0}
if [ "$big" -ge 5 ]; then
  echo "== $big GiB"
  python3 -I - "$tmp" "$big" <<'PY'
import sys, tarfile
tmp, gib = sys.argv[1], int(sys.argv[2])
class Zeros:
    def __init__(self, n): self.n = n
    def read(self, k=-1):
        k = self.n if k < 0 else min(k, self.n)
        self.n -= k
        return bytes(k)
with tarfile.open(f"{tmp}/gen/big.tar", "w", format=tarfile.PAX_FORMAT) as t:
    i = tarfile.TarInfo("zeros"); i.size = gib << 30; t.addfile(i, Zeros(i.size))
    i = tarfile.TarInfo("after"); d = b"past four GiB\n"; i.size = len(d)
    import io; t.addfile(i, io.BytesIO(d))
PY
  bdiff="sha256:$(sha "$tmp/gen/big.tar")"
  out=$("$tmp/echo" "$tmp/r6" "$tmp/gen/big.tar" application/vnd.oci.image.layer.v1.tar "$bdiff" 2>&1)
  echo "$out"
  check "big layer published" test "$out" = "published"
  check "the big file's size" test "$(size "$tmp/r6/layers/${bdiff#sha256:}/zeros")" = $((big << 30))
  check "a file past 4 GiB in the tar" test "$(cat "$tmp/r6/layers/${bdiff#sha256:}/after")" = "past four GiB"
fi

echo "== $fails failed"
[ "$fails" = 0 ]
