#!/usr/bin/env bash
# Fetches Alpine's linux-virt arm64 kernel (the guest's default kernel)
# into DIR: DIR/Image, the raw arm64 Image unpacked from the package's EFI
# zboot (bend-vmm and qemu boot it as is), and DIR/lib/modules/<version>,
# the modules that pack.sh resolves modules.early.txt and modules.txt
# against. scripts/guest/build.sh and CI's assets-disk boot test use it.
#
# usage: alpine-kernel.sh DIR
# Needs curl and python3. $ALPINE overrides the package mirror.
set -euo pipefail
[ $# = 1 ] || { sed -n 's/^# usage: //p' "$0"; exit 2; }
k=$1
ALPINE=${ALPINE:-https://dl-cdn.alpinelinux.org/alpine/latest-stable/main/aarch64}
rm -rf "$k"; mkdir -p "$k"
apk=$(curl -fsSL "$ALPINE/" | grep -o 'linux-virt-[0-9][^"]*\.apk' | head -1)
curl -fsSL -o "$k/k.apk" "$ALPINE/$apk"
tar -xzf "$k/k.apk" -C "$k" 2>/dev/null || true
python3 - "$k/boot/vmlinuz-virt" "$k/Image" <<'PY'
import sys, struct, gzip
b = open(sys.argv[1], "rb").read()
assert b[4:8] == b"zimg", "not an EFI zboot image"
off, size = struct.unpack("<II", b[8:16])
assert b[24:28] == b"gzip", b[24:32]
open(sys.argv[2], "wb").write(gzip.decompress(b[off:off + size]))
PY
echo "$apk: $k/Image, $(ls "$k/lib/modules")"
