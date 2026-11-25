#!/usr/bin/env bash
# A layer's squashfs image (src/layers/sqfs.bend, host/layers/image.bend,
# docs/ref/layers-sqfs.md) end to end on Linux, no VM: tests/layer_image.bend
# writes the images of layer tars, and the oracles read them:
# squashfs-tools' unsquashfs, then the kernel (a loop mount, as a node
# mounts /mnt/layers/<hex>.sqfs) and overlayfs (two layer images stacked,
# whiteouts and an opaque directory applied). Last, a real image layer
# (alpine from Docker Hub) compared file by file with tar.
# Needs: bend, python3, unsquashfs, sudo (mount), getfattr (attr), curl.
set -uo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
mounts=()
cleanup() {
  for m in "${mounts[@]}"; do sudo umount "$m" 2>/dev/null; done
  sudo rm -rf "$tmp"
}
trap cleanup EXIT
fails=0
check() { # check NAME CONDITION-COMMAND...
  local name=$1; shift
  if "$@" >"$tmp/check.out" 2>&1; then echo "PASS $name"; else echo "FAIL $name"; head -20 "$tmp/check.out"; fails=$((fails + 1)); fi
}
eq() { [ "$1" = "$2" ] || { echo "  got: $1" >&2; echo "  want: $2" >&2; return 1; }; }

if ! bend tests/layer_image.bend -o "$tmp/limg" >"$tmp/build.log" 2>&1; then
  cat "$tmp/build.log"; echo "FAIL build tests/layer_image.bend"; exit 1
fi

python3 - "$tmp" <<'EOF'
import tarfile, io, sys
d = sys.argv[1]
def tarf(path, items):
    t = tarfile.open(path, 'w', format=tarfile.PAX_FORMAT)
    for (name, typ, data, mode, link, uid, gid, dev, pax) in items:
        i = tarfile.TarInfo(name); i.type = typ; i.mode = mode; i.uid = uid; i.gid = gid
        i.mtime = 1700000000; i.uname = ''; i.gname = ''; i.size = len(data); i.linkname = link
        i.devmajor, i.devminor = dev
        if pax: i.pax_headers = pax
        t.addfile(i, io.BytesIO(data) if data else None)
    t.close()
def e(name, typ, data=b'', mode=0o644, link='', uid=0, gid=0, dev=(0, 0), pax=None):
    return (name, typ, data, mode, link, uid, gid, dev, pax)
cap = '\x01\x00\x00\x02\x00\x20\x00\x00' + '\x00' * 12
upper = [e('etc/', tarfile.DIRTYPE, mode=0o755), e('etc/hostname', tarfile.REGTYPE, b'box\n'),
  e('etc/shadow', tarfile.REGTYPE, b'root:*:1::::::\n', mode=0o640, gid=42),
  e('bin/', tarfile.DIRTYPE, mode=0o755),
  e('bin/tool', tarfile.REGTYPE, bytes((i * 13) % 256 for i in range(400000)), mode=0o4755),
  e('bin/hard', tarfile.LNKTYPE, link='bin/tool', mode=0o4755), e('bin/sym', tarfile.SYMTYPE, link='tool', mode=0o777),
  e('bin/ping', tarfile.REGTYPE, b'\x7fELF..', mode=0o755, pax={'SCHILY.xattr.security.capability': cap}),
  e('dev/', tarfile.DIRTYPE, mode=0o755), e('dev/null', tarfile.CHRTYPE, mode=0o666, dev=(1, 3)),
  e('dev/fifo', tarfile.FIFOTYPE, mode=0o600),
  e('var/lib/', tarfile.DIRTYPE, mode=0o755), e('var/lib/.wh.oldpkg', tarfile.REGTYPE),
  e('opt/', tarfile.DIRTYPE, mode=0o755), e('opt/.wh..wh..opq', tarfile.REGTYPE), e('opt/new', tarfile.REGTYPE, b'new\n'),
  e('home/u/', tarfile.DIRTYPE, mode=0o700, uid=1000, gid=1000), e('home/u/f', tarfile.REGTYPE, b'user file\n', uid=1000, gid=1000)]
upper += [e('many/f%03d' % i, tarfile.REGTYPE, ('n%d\n' % i).encode()) for i in range(300)]
tarf(d + '/upper.tar', upper)
tarf(d + '/lower.tar', [e('etc/', tarfile.DIRTYPE, mode=0o755), e('etc/keep', tarfile.REGTYPE, b'keep\n'),
  e('var/lib/', tarfile.DIRTYPE, mode=0o755), e('var/lib/oldpkg', tarfile.REGTYPE, b'old\n'),
  e('opt/', tarfile.DIRTYPE, mode=0o755), e('opt/old', tarfile.REGTYPE, b'old\n')])
# data that does not shrink (stored raw, block by block), an empty file
# before and after it, and text that does
import hashlib
noise = b''.join(hashlib.sha256(b'%d' % i).digest() for i in range(9375))
tarf(d + '/mix.tar', [e('a-empty', tarfile.REGTYPE), e('b-noise', tarfile.REGTYPE, noise), e('c-empty', tarfile.REGTYPE),
  e('d-text', tarfile.REGTYPE, b'the same line again\n' * 20000), e('e-short', tarfile.REGTYPE, b'x')])
open(d + '/noise', 'wb').write(noise)
EOF

echo "== images"
check "the upper layer's image" eq "$("$tmp/limg" "$tmp/upper.tar" "$tmp/upper.sqfs")" "OK 401429 320"
check "the lower layer's image" eq "$("$tmp/limg" "$tmp/lower.tar" "$tmp/lower.sqfs")" "OK 13 8"
check "an image is a multiple of 4096 bytes" test $(( $(stat -c %s "$tmp/upper.sqfs") % 4096 )) = 0
check "a second image at the same path is refused (O_EXCL)" grep -q '^FAIL' <("$tmp/limg" "$tmp/lower.tar" "$tmp/lower.sqfs")

echo "== unsquashfs"
unsquashfs -lln "$tmp/upper.sqfs" > "$tmp/upper.list" 2>&1
check "unsquashfs lists 320 inodes and the hard link" test "$(grep -c squashfs-root "$tmp/upper.list")" = 321
check "unsquashfs: the whiteout" grep -q '^crw-r--r-- 0/0 *0, *0 .*var/lib/oldpkg$' "$tmp/upper.list"
check "unsquashfs: setuid, owners" grep -q '^-rwsr-xr-x 0/0 *400000 .*bin/tool$' "$tmp/upper.list"
check "unsquashfs: a group" grep -q '^-rw-r----- 0/42 .*etc/shadow$' "$tmp/upper.list"

echo "== the kernel"
m1=$tmp/m1 m0=$tmp/m0 mo=$tmp/mo w=$tmp/w
mkdir -p "$m1" "$m0" "$mo"
if sudo mount -t squashfs -o loop,ro "$tmp/upper.sqfs" "$m1"; then mounts+=("$m1"); fi
check "the kernel mounts the image" mountpoint -q "$m1"
want=$(python3 -c "import hashlib;print(hashlib.sha256(bytes((i*13)%256 for i in range(400000))).hexdigest())")
check "a 4-block file reads back" eq "$(sha256sum < "$m1/bin/tool" | cut -d' ' -f1)" "$want"
check "a hard link is the same inode, 2 links" eq "$(stat -c '%i %h' "$m1/bin/hard")" "$(stat -c '%i' "$m1/bin/tool") 2"
check "owner, group and mode" eq "$(stat -c '%u:%g %a' "$m1/etc/shadow") $(stat -c '%u:%g %a' "$m1/bin/tool")" "0:42 640 0:0 4755"
check "a user's directory" eq "$(stat -c '%u:%g %a' "$m1/home/u")" "1000:1000 700"
check "a symbolic link" eq "$(readlink "$m1/bin/sym")" "tool"
check "a character device" eq "$(stat -c '%F %t,%T' "$m1/dev/null")" "character special file 1,3"
check "a fifo" eq "$(stat -c '%F' "$m1/dev/fifo")" "fifo"
check "a whiteout is a 0,0 character device" eq "$(stat -c '%F %t,%T' "$m1/var/lib/oldpkg")" "character special file 0,0"
check "security.capability" eq "$(sudo getfattr --only-values -n security.capability "$m1/bin/ping" | od -An -tx1 | tr -d ' \n')" \
  "0100000200200000000000000000000000000000"
check "an opaque directory" eq "$(sudo getfattr --only-values -n trusted.overlay.opaque "$m1/opt")" "y"
check "300 files in one directory" test "$(ls "$m1/many" | wc -l)" = 300
check "every name (the hard link too)" test "$(sudo find "$m1" | wc -l)" = 321

echo "== lz4 blocks"
check "the image names lz4" grep -q 'Compression lz4' <(unsquashfs -s "$tmp/upper.sqfs")
check "data that repeats is stored smaller (400000 bytes in under 100000)" test "$(stat -c %s "$tmp/upper.sqfs")" -lt 100000
check "the mixed layer's image" eq "$("$tmp/limg" "$tmp/mix.tar" "$tmp/mix.sqfs")" "OK 700001 6"
mx=$tmp/mx; mkdir -p "$mx"
if sudo mount -t squashfs -o loop,ro "$tmp/mix.sqfs" "$mx"; then mounts+=("$mx"); fi
check "the kernel mounts the mixed image" mountpoint -q "$mx"
check "data that does not shrink reads back (raw blocks)" cmp "$mx/b-noise" "$tmp/noise"
check "text reads back (lz4 blocks)" eq "$(sha256sum < "$mx/d-text" | cut -d' ' -f1)" \
  "$(python3 -c "import hashlib;print(hashlib.sha256(b'the same line again\n' * 20000).hexdigest())")"
check "empty files beside data are empty, a 1-byte file reads back" eq "$(stat -c %s "$mx/a-empty" "$mx/c-empty" | tr '\n' ' ')$(cat "$mx/e-short")" "0 0 x"
check "the mixed image holds the noise raw and the text small" test "$(stat -c %s "$tmp/mix.sqfs")" -lt 320000
check "unsquashfs reads the mixed image" unsquashfs -d "$tmp/mixout" "$tmp/mix.sqfs"
check "unsquashfs: the same noise" cmp "$tmp/mixout/b-noise" "$tmp/noise"

echo "== overlayfs (as a node stacks its layers)"
if sudo mount -t squashfs -o loop,ro "$tmp/lower.sqfs" "$m0"; then mounts+=("$m0"); fi
if sudo mount -t overlay overlay -o "lowerdir=$m1:$m0" "$mo"; then mounts=("$mo" "${mounts[@]}"); fi
check "the layers stack" mountpoint -q "$mo"
check "the whiteout hides the lower file" test ! -e "$mo/var/lib/oldpkg"
check "the opaque directory hides the lower directory's files" test ! -e "$mo/opt/old" -a -f "$mo/opt/new"
check "a lower file shows through" eq "$(cat "$mo/etc/keep")" "keep"
check "an upper file wins" eq "$(cat "$mo/etc/hostname")" "box"

echo "== a real layer (alpine 3.20 from Docker Hub)"
repo=library/alpine
retry="--retry 5 --retry-all-errors --retry-delay 5"
tok=$(curl -fsSL $retry "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$repo:pull" | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
idx=$(curl -fsSL $retry -H "Authorization: Bearer $tok" -H 'Accept: application/vnd.oci.image.index.v1+json' -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' \
  "https://registry-1.docker.io/v2/$repo/manifests/3.20")
man=$(echo "$idx" | python3 -c 'import sys,json;print([m["digest"] for m in json.load(sys.stdin)["manifests"] if m["platform"]["architecture"]=="amd64"][0])')
layer=$(curl -fsSL $retry -H "Authorization: Bearer $tok" -H 'Accept: application/vnd.oci.image.manifest.v1+json' -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
  "https://registry-1.docker.io/v2/$repo/manifests/$man" | python3 -c 'import sys,json;print(json.load(sys.stdin)["layers"][0]["digest"])')
# to a file first: a retry into a pipe would send the blob's start twice
if curl -fsSL $retry -o "$tmp/alpine.tar.gz" -H "Authorization: Bearer $tok" "https://registry-1.docker.io/v2/$repo/blobs/$layer" \
  && gzip -dc "$tmp/alpine.tar.gz" > "$tmp/alpine.tar"; then
  t0=$(date +%s%N)
  out=$("$tmp/limg" "$tmp/alpine.tar" "$tmp/alpine.sqfs")
  t1=$(date +%s%N)
  echo "alpine: $out in $(( (t1 - t0) / 1000000 )) ms, image $(stat -c %s "$tmp/alpine.sqfs") bytes, tar $(stat -c %s "$tmp/alpine.tar") bytes"
  check "alpine's image" grep -q '^OK' <<<"$out"
  ents=$(tar -tf "$tmp/alpine.tar" | wc -l)
  dirs=$(tar -tvf "$tmp/alpine.tar" | grep -c '^d')
  echo "alpine: the image is 1 host file; the directory store made $ents entries and $dirs .bend-meta files for this layer"
  ma=$tmp/ma; mkdir -p "$ma"
  if sudo mount -t squashfs -o loop,ro "$tmp/alpine.sqfs" "$ma"; then mounts=("$ma" "${mounts[@]}"); fi
  ex=$tmp/ex; mkdir -p "$ex"; sudo tar -xpf "$tmp/alpine.tar" -C "$ex"
  check "alpine: the same tree as tar extracts (names, types, modes, owners, links)" \
    diff <(cd "$ex" && sudo find . -mindepth 1 -printf '%p %y %m %U:%G %l\n' | sort) <(cd "$ma" && sudo find . -mindepth 1 -printf '%p %y %m %U:%G %l\n' | sort)
  check "alpine: the same file contents" \
    diff <(cd "$ex" && sudo find . -type f -exec sha256sum {} + | sort -k2) <(cd "$ma" && sudo find . -type f -exec sha256sum {} + | sort -k2)
else
  echo "FAIL fetching alpine's layer"; fails=$((fails + 1))
fi

echo "== $fails failed"
[ "$fails" = 0 ]
