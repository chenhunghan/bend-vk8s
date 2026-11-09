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
# the same program as a dynamic glibc binary, /usr/bin/vk8s-guest: what
# needs OpenSSL through dlopen (bend-kube-runtime's TLS client, the TLS
# server effects) runs this one; PID 1 stays static
zig cc -target aarch64-linux-gnu.2.38 -O2 -w out/build/init.c -lm -ldl -lpthread -o out/build/vk8s-guest
root=out/build/root; rm -rf "$root"; mkdir -p "$root"
python3 scripts/guest/modules.py "$k" "$root" $(cat scripts/guest/modules.txt)
# glibc runtime (kubelet, containerd) and iptables/conntrack userland
deb=out/build/debroot.tar
[ -f "$deb" ] && [ "$deb" -nt scripts/guest/debs.txt ] || python3 scripts/guest/debs.py "$deb" $(cat scripts/guest/debs.txt)
mkdir -p "$root/usr/sbin" "$root/etc/ssl/certs"
# CA roots for image pulls (Mozilla's bundle, as curl.se publishes it)
[ -f out/build/cacert.pem ] || curl -fsSL -o out/build/cacert.pem https://curl.se/ca/cacert.pem
cp out/build/cacert.pem "$root/etc/ssl/certs/ca-certificates.crt"
ln -sfn usr/lib "$root/lib"
for t in iptables iptables-save iptables-restore ip6tables ip6tables-save ip6tables-restore; do
  ln -sfn xtables-nft-multi "$root/usr/sbin/$t"
done
python3 scripts/guest/mkinitramfs.py "$out/vk8s.cpio" "$deb" "$root" scripts/guest/stage0.sh:/init scripts/guest/flannel.yaml:/etc/vk8s/flannel.yaml out/build/init:/sbin/vk8s-init out/build/vk8s-guest:/usr/bin/vk8s-guest "$bb":/bin/busybox
# assets disk
a=out/assets/$K8S/bin
if [ ! -f "$out/assets-$K8S.img" ] || [ -n "$(find "$a" -newer "$out/assets-$K8S.img" | head -1)" ]; then
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
# unlink before copying: a running VM keeps the old files it has open
for f in Image vk8s.cpio data.img; do rm -f "$dst/$f"; cp -c "$out/$f" "$dst/$f"; done
rm -f "$dst/assets.img"; cp -c "$out/assets-$K8S.img" "$dst/assets.img"
echo "assets installed in $dst"
