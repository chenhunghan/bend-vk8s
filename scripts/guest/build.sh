#!/usr/bin/env bash
# Builds the control-plane VM's boot files under out/guest:
#   Image        Alpine's linux-virt arm64 kernel, unpacked from its EFI zboot
#   vk8s.cpio    initramfs: busybox, kernel modules, vk8s (host/init.bend) as /init
#   assets.img   ext4, read-only: the Kubernetes binaries (out/assets/<ver>/bin)
# Needs: bend, zig, python3, curl, e2fsprogs (brew install e2fsprogs).
set -euo pipefail
cd "$(dirname "$0")/../.."
K8S=${K8S:-v1.36.6}
ALPINE=${ALPINE:-https://dl-cdn.alpinelinux.org/alpine/latest-stable/main/aarch64}
BUSYBOX=${BUSYBOX:-https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox}
MKFS=$(command -v mkfs.ext4 || echo /opt/homebrew/opt/e2fsprogs/sbin/mkfs.ext4)
out=out/guest; mkdir -p "$out" out/build
k=out/build/kernel
if [ ! -f "$out/Image" ] || [ ! -d "$k/lib/modules" ]; then
  rm -rf "$k"; mkdir -p "$k"
  apk=$(curl -fsSL "$ALPINE/" | grep -o 'linux-virt-[0-9][^"]*\.apk' | head -1)
  curl -fsSL -o "$k/k.apk" "$ALPINE/$apk"
  tar -xzf "$k/k.apk" -C "$k" 2>/dev/null || true
  python3 - "$k/boot/vmlinuz-virt" "$out/Image" <<'PY'
import sys, struct, gzip
b = open(sys.argv[1], "rb").read()
assert b[4:8] == b"zimg", "not an EFI zboot image"
off, size = struct.unpack("<II", b[8:16])
assert b[24:28] == b"gzip", b[24:32]
open(sys.argv[2], "wb").write(gzip.decompress(b[off:off + size]))
PY
fi
# busybox: static arm64 (bend-vmm's guest assets build one)
bb=${BUSYBOX_BIN:-$HOME/bend-vmm/out/guest/busybox}
[ -x "$bb" ] || { echo "need a static arm64 busybox at \$BUSYBOX_BIN"; exit 1; }
# vk8s init: Bend -> C -> static musl arm64
bend host/init.bend -o out/build/init.c
zig cc -target aarch64-linux-musl -O2 -static -w -include host/musl_shim.h out/build/init.c -lm -o out/build/init
root=out/build/root; rm -rf "$root"; mkdir -p "$root"
python3 scripts/guest/modules.py "$k" "$root" $(cat scripts/guest/modules.txt)
python3 scripts/guest/mkinitramfs.py "$root" "$out/vk8s.cpio" out/build/init:/init "$bb":/bin/busybox
# assets disk
a=out/assets/$K8S/bin
if [ ! -f "$out/assets-$K8S.img" ] || [ "$a" -nt "$out/assets-$K8S.img" ]; then
  sz=$(( $(du -sm "$a" | cut -f1) + 64 ))
  rm -f "$out/assets-$K8S.img"
  "$MKFS" -q -F -L vk8s-assets -d "$a" "$out/assets-$K8S.img" "${sz}M"
fi
ls -la "$out"
# data disk template: sparse ext4, cloned per cluster (cp -c)
if [ ! -f "$out/data.img" ]; then
  "$MKFS" -q -F -L vk8s-data -E lazy_itable_init=1,lazy_journal_init=1 "$out/data.img" 16G
fi
# install for the CLI (VK8S_ASSETS defaults to ~/.vk8s/assets/<ver>)
dst=${VK8S_ASSETS:-$HOME/.vk8s/assets/$K8S}
mkdir -p "$dst"
for f in Image vk8s.cpio data.img; do cp -c "$out/$f" "$dst/$f"; done
cp -c "$out/assets-$K8S.img" "$dst/assets.img"
echo "assets installed in $dst"
