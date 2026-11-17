#!/usr/bin/env bash
# Builds the control-plane VM's boot files for one arch under out/guest
# (arm64) or out/guest-amd64 (amd64):
#   Image        Alpine's linux-virt kernel: on arm64 the raw Image unpacked
#                from its EFI zboot, on amd64 its bzImage; with
#                VK8S_KERNEL=16k (arm64 only), our own build of the same
#                version with 16 KiB pages (scripts/guest/kernel.sh,
#                footprint M5), from VK8S_KERNEL_DIR (default
#                out/build/kernel16k) when it holds one, for example the
#                kernel16k artifact of CI (unpack it with unzip -n on
#                macOS; see footprint M5)
#   vk8s.cpio    initramfs (stays in RAM): stage 0, busybox, the virtio and
#                squashfs modules, symlinks into the base disk (pack.sh)
#   base.img     squashfs (zstd), read-only, every VM's /dev/vda: under
#                guest/, vk8s (host/init.bend, PID 1), vk8s-guest, glibc,
#                libssl, iptables, the other modules, the CA roots
#   <set>.img    one squashfs disk per role set of the Kubernetes binaries
#                (out/assets/<ver>/bin, or <ver>-amd64; scripts/guest/
#                sets.txt, mksets.sh): node, control-plane, classic, cache,
#                images (docs/ref/footprint-decisions.md D1)
#   data.img     the data disk template, sparse ext4
# ARCH picks the arch: arm64/aarch64 or amd64/x86_64 (default uname -m).
# scripts/guest/fetch-assets.sh with the same ARCH fetches the binaries.
# Needs: bend, zig, python3, curl, squashfs-tools 4.6+ (brew install
# squashfs: sqfstar) and e2fsprogs for the data disk (brew install e2fsprogs).
# Every downloaded input is pinned by SHA-256 (scripts/guest/pins.sh,
# scripts/guest/debs.lock; docs/ref/review-bend-vk8s-pr-48.md #2), and a
# cached one whose pin changed is fetched again.
set -euo pipefail
cd "$(dirname "$0")/../.."
. scripts/guest/pins.sh
K8S=${K8S:-v1.36.6}
case ${ARCH:-$(uname -m)} in
  arm64|aarch64) arch=arm64 zarch=aarch64 sfx="" ;;
  amd64|x86_64) arch=amd64 zarch=x86_64 sfx=-amd64 ;;
  *) echo "build.sh: unknown arch ${ARCH:-$(uname -m)} (arm64 or amd64)" >&2; exit 2 ;;
esac
export ARCH=$arch
MKFS=$(command -v mkfs.ext4 || echo /opt/homebrew/opt/e2fsprogs/sbin/mkfs.ext4)
out=out/guest$sfx; mkdir -p "$out" out/build
k=out/build/kernel$sfx
if [ "${VK8S_KERNEL:-alpine}" = 16k ]; then
  [ "$arch" = arm64 ] || { echo "build.sh: VK8S_KERNEL=16k is arm64 only" >&2; exit 2; }
  k=${VK8S_KERNEL_DIR:-out/build/kernel16k}
  [ -f "$k/Image" ] && [ -d "$k/lib/modules" ] || scripts/guest/kernel.sh "$k"
  rm -f "$out/Image"; cp "$k/Image" "$out/Image"; echo 16k > "$out/kernel"
elif [ ! -f "$out/Image" ] || [ ! -d "$k/lib/modules" ] || [ "$(cat "$out/kernel" 2>/dev/null)" = 16k ] \
  || [ "$(cat "$k/apk" 2>/dev/null)" != "$(alpine_pin "$zarch" linux-virt)" ]; then
  rm -f "$out/kernel"
  scripts/guest/alpine-kernel.sh "$k" "$arch"
  rm -f "$out/Image"; cp "$k/Image" "$out/Image"
fi
# busybox, static: $BUSYBOX_BIN, else bend-vmm's (arm64), else Alpine's
# busybox-static package for this arch (the one bend-vmm's guest uses),
# pinned in pins.sh; $bb.apk records the pin it came from
bb=${BUSYBOX_BIN:-}
if [ -z "$bb" ] && [ "$arch" = arm64 ] && [ -x "$HOME/bend-vmm/out/guest/busybox" ]; then bb=$HOME/bend-vmm/out/guest/busybox; fi
if [ -z "$bb" ]; then
  bb=out/build/busybox$sfx
  pin=$(alpine_pin "$zarch" busybox-static)
  if [ ! -x "$bb" ] || [ "$(cat "$bb.apk" 2>/dev/null)" != "$pin" ]; then
    read -r apk sum <<<"$pin"
    m=${ALPINE:-https://dl-cdn.alpinelinux.org/alpine/$ALPINE_BRANCH/main/$zarch}
    t=$(mktemp -d)
    pin_get "$m/$apk" "$t/bb.apk" "$sum"
    tar -xzf "$t/bb.apk" -C "$t" 2>/dev/null || true
    cp "$t/bin/busybox.static" "$bb.new" && chmod 755 "$bb.new" && mv "$bb.new" "$bb"
    echo "$pin" > "$bb.apk"
    rm -rf "$t"
    echo "busybox: $apk"
  fi
fi
[ -x "$bb" ] || { echo "need a static $arch busybox at \$BUSYBOX_BIN"; exit 1; }
# vk8s init: Bend -> C -> static musl
bend host/init.bend -o out/build/init.c
zig cc -target "$zarch-linux-musl" -O2 -static -w -s -include host/musl_shim.h out/build/init.c -lm -o "out/build/init$sfx"
# the same program as a dynamic glibc binary, /usr/bin/vk8s-guest: what
# needs OpenSSL through dlopen (bend-kube-runtime's TLS client, the TLS
# server effects) runs this one; PID 1 stays static
zig cc -target "$zarch-linux-gnu.2.38" -O2 -w -s out/build/init.c -lm -ldl -lpthread -o "out/build/vk8s-guest$sfx"
# glibc runtime (vk8s-guest's libssl) and the iptables/conntrack userland,
# each .deb pinned by scripts/guest/debs.lock
deb=out/build/debroot$sfx.tar
[ -f "$deb" ] && [ "$deb" -nt scripts/guest/debs.txt ] && [ "$deb" -nt scripts/guest/debs.lock ] \
  || DEB_ARCH=$arch python3 scripts/guest/debs.py "$deb" $(cat scripts/guest/debs.txt)
# CA roots for image pulls (Mozilla's bundle, as curl.se publishes it),
# the dated file of pins.sh
pin_get "https://curl.se/ca/$CACERT_FILE" out/build/cacert.pem "$CACERT_SHA256"
# the initramfs (only what mounts the base disk) and the base disk (the
# guest root under guest/, no Kubernetes binaries): pack.sh; then one disk
# per role set of the Kubernetes binaries: mksets.sh
a=out/assets/$K8S$sfx/bin
empty=out/build/empty-bin; rm -rf "$empty"; mkdir -p "$empty"
scripts/guest/pack.sh "$k" "$deb" "out/build/init$sfx" "out/build/vk8s-guest$sfx" "$bb" \
  out/build/cacert.pem "$empty" "$out/vk8s.cpio" "$out/base-$K8S.img"
scripts/guest/mksets.sh "$a" "$out/sets-$K8S"
ls -la "$out" "$out/sets-$K8S"
# data disk template: sparse ext4, cloned per cluster
if [ ! -f "$out/data.img" ]; then
  "$MKFS" -q -F -L vk8s-data -E lazy_itable_init=1,lazy_journal_init=1 "$out/data.img" 16G
fi
# install for the CLI (VK8S_ASSETS defaults to ~/.vk8s/assets/<ver>, or
# <ver>-amd64)
dst=${VK8S_ASSETS:-$HOME/.vk8s/assets/$K8S$sfx}
mkdir -p "$dst"
# a copy-on-write copy where the file system can: APFS clone (cp -c) on
# macOS, reflink (else a sparse copy) with GNU cp
clone() { cp -c "$1" "$2" 2>/dev/null || cp --reflink=auto --sparse=always "$1" "$2"; }
# unlink before copying: a running VM keeps the old files it has open
for f in Image vk8s.cpio data.img; do rm -f "$dst/$f"; clone "$out/$f" "$dst/$f"; done
rm -f "$dst/base.img"; clone "$out/base-$K8S.img" "$dst/base.img"
for s in $(awk '!/^#/ && NF { print $1 }' scripts/guest/sets.txt); do
  rm -f "$dst/$s.img"
  if [ -f "$out/sets-$K8S/$s.img" ]; then clone "$out/sets-$K8S/$s.img" "$dst/$s.img"; fi
done
# the single assets disk of earlier builds: a dir with base.img is per-role
rm -f "$dst/assets.img"
echo "assets installed in $dst"; ls -l "$dst"
