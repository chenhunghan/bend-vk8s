#!/usr/bin/env bash
# Fetches Alpine's linux-virt kernel (the guest's default kernel) for one
# arch into DIR: DIR/Image, the kernel bend-vmm and qemu boot as is, and
# DIR/lib/modules/<version>, the modules that pack.sh resolves
# modules.early.txt and modules.txt against. scripts/guest/build.sh and
# CI's assets-disk boot test use it.
#   arm64:  the raw arm64 Image, unpacked from the package's EFI zboot
#   amd64:  the package's bzImage (vmlinuz-virt), unchanged: bend-vmm
#           boots it with the 64-bit boot protocol (2.12 or later)
# The file is DIR/Image for both, so the asset names stay the same.
#
# usage: alpine-kernel.sh DIR [ARCH]
# ARCH is arm64/aarch64 or amd64/x86_64 (default: $ARCH, else uname -m).
# Needs curl and python3. $ALPINE overrides the package mirror.
set -euo pipefail
[ $# = 1 ] || [ $# = 2 ] || { sed -n 's/^# usage: //p' "$0"; exit 2; }
k=$1
case ${2:-${ARCH:-$(uname -m)}} in
  arm64|aarch64) apk_arch=aarch64 ;;
  amd64|x86_64) apk_arch=x86_64 ;;
  *) echo "alpine-kernel: unknown arch ${2:-${ARCH:-$(uname -m)}} (arm64 or amd64)" >&2; exit 2 ;;
esac
ALPINE=${ALPINE:-https://dl-cdn.alpinelinux.org/alpine/latest-stable/main/$apk_arch}
rm -rf "$k"; mkdir -p "$k"
apk=$(curl -fsSL --retry 3 "$ALPINE/" | grep -o 'linux-virt-[0-9][^"]*\.apk' | head -1)
curl -fsSL --retry 3 -o "$k/k.apk" "$ALPINE/$apk"
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
    open(sys.argv[2], "wb").write(gzip.decompress(b[off:off + size]))
PY
echo "$apk: $k/Image, $(ls "$k/lib/modules")"
