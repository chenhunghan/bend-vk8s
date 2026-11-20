#!/usr/bin/env bash
# Fetches Alpine's linux-virt kernel (the guest's default kernel) for one
# arch into DIR: DIR/Image, the kernel bend-vmm and qemu boot as is, and
# DIR/lib/modules/<version>, the modules that pack.sh resolves
# modules.early.txt and modules.txt against. scripts/guest/build.sh and
# CI's assets-disk boot test use it.
#   arm64:  the package's EFI zboot vmlinuz-virt (a zimg header and a
#           gzip payload), unchanged: about 10 MB instead of the 36 MB raw
#           Image. bend-vmm 0x9f122a1b (24c676f) and qemu 8.1 or later
#           boot it as is (GOAL section 11).
#   amd64:  the package's bzImage (vmlinuz-virt), unchanged: bend-vmm
#           boots it with the 64-bit boot protocol (2.12 or later)
# The file is DIR/Image for both, so the asset names stay the same.
#
# The package is pinned by name and SHA-256 (scripts/guest/pins.sh), so
# the kernel is the same bytes on every build; DIR/apk records the pin.
#
# usage: alpine-kernel.sh DIR [ARCH]
# ARCH is arm64/aarch64 or amd64/x86_64 (default: $ARCH, else uname -m).
# Needs curl and python3. $ALPINE overrides the package mirror (the
# directory that holds the .apk files of this arch).
set -euo pipefail
[ $# = 1 ] || [ $# = 2 ] || { sed -n 's/^# usage: //p' "$0"; exit 2; }
. "$(dirname "$0")/pins.sh"
k=$1
case ${2:-${ARCH:-$(uname -m)}} in
  arm64|aarch64) apk_arch=aarch64 ;;
  amd64|x86_64) apk_arch=x86_64 ;;
  *) echo "alpine-kernel: unknown arch ${2:-${ARCH:-$(uname -m)}} (arm64 or amd64)" >&2; exit 2 ;;
esac
ALPINE=${ALPINE:-https://dl-cdn.alpinelinux.org/alpine/$ALPINE_BRANCH/main/$apk_arch}
read -r apk sum <<<"$(alpine_pin "$apk_arch" linux-virt)"
rm -rf "$k"; mkdir -p "$k"
pin_get "$ALPINE/$apk" "$k/k.apk" "$sum"
tar -xzf "$k/k.apk" -C "$k" 2>/dev/null || true
python3 - "$k/boot/vmlinuz-virt" "$k/Image" "$apk_arch" <<'PY'
import sys, struct, gzip
b = open(sys.argv[1], "rb").read()
if sys.argv[3] == "x86_64":
    # Linux boot protocol: "HdrS" at 0x202, the version at 0x206
    assert b[0x202:0x206] == b"HdrS", "not a bzImage"
    v = struct.unpack("<H", b[0x206:0x208])[0]
    assert v >= 0x020c, "boot protocol %x < 2.12" % v
    open(sys.argv[2], "wb").write(b)
else:
    assert b[4:8] == b"zimg", "not an EFI zboot image"
    off, size = struct.unpack("<II", b[8:16])
    assert b[24:28] == b"gzip", b[24:32]
    # the payload must inflate to an arm64 Image ("ARM\x64" at 56)
    assert gzip.decompress(b[off:off + size])[56:60] == b"ARM\x64", "the payload is no arm64 Image"
    open(sys.argv[2], "wb").write(b)
PY
rm -f "$k/k.apk"; echo "$apk $sum" > "$k/apk"
echo "$apk: $k/Image, $(ls "$k/lib/modules")"
