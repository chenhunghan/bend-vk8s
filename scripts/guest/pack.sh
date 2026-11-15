#!/usr/bin/env bash
# Packs the guest's boot files from built inputs (scripts/guest/build.sh
# makes them; tests/guest_image.sh runs this on fakes):
#   vk8s.cpio   the initramfs, which stays in RAM in every VM: only what
#               stage 0 needs to mount the assets disk. Stage 0 (/init),
#               busybox, the virtio and ext4 modules (modules.early.txt),
#               small files under /etc/vk8s, and symlinks into /assets.
#   assets.img  the read-only assets disk (/dev/vda): the Kubernetes
#               binaries at its root (PID 1 mounts it at /var/lib/vcluster/bin)
#               and the guest root under guest/: vk8s-init (PID 1),
#               vk8s-guest, the Debian root (glibc, libssl, iptables,
#               conntrack), the other kernel modules and the CA roots.
#               Stage 0 mounts it at /assets, so /assets/guest/... is where
#               the initramfs links point.
#
# usage: pack.sh KERNEL_ROOT DEBROOT_TAR INIT GUEST_BIN BUSYBOX CACERT ASSETS_BIN OUT_CPIO OUT_IMG
# Needs python3, mkfs.ext4 and debugfs (e2fsprogs; $MKFS and $DEBUGFS
# override them).
set -euo pipefail
[ $# = 9 ] || { sed -n 's/^# usage: //p' "$0"; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
k=$1 deb=$2 init=$3 gbin=$4 bb=$5 ca=$6 a=$7 cpio=$8 img=$9
MKFS=${MKFS:-$(command -v mkfs.ext4 || echo /opt/homebrew/opt/e2fsprogs/sbin/mkfs.ext4)}
DEBUGFS=${DEBUGFS:-$(command -v debugfs || echo /opt/homebrew/opt/e2fsprogs/sbin/debugfs)}
mnt=/assets/guest
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
root=$w/root guest=$w/guest
mkdir -p "$root/etc/vk8s" "$guest/usr/sbin" "$guest/etc/ssl/certs"
# stage 0 loads these from the initramfs; PID 1 loads the rest (its
# Modules step, /etc/vk8s/modules) from the disk through /lib/modules
python3 "$here/modules.py" "$k" "$root/boot/modules" /boot/modules "$root/etc/vk8s/modules.early" \
  $(cat "$here/modules.early.txt")
python3 "$here/modules.py" "$k" "$guest/usr/lib/modules" /lib/modules "$root/etc/vk8s/modules" \
  --after "$root/etc/vk8s/modules.early" $(cat "$here/modules.txt")
# CA roots for image pulls
cp "$ca" "$guest/etc/ssl/certs/ca-certificates.crt"
for t in iptables iptables-save iptables-restore ip6tables ip6tables-save ip6tables-restore; do
  ln -sfn xtables-nft-multi "$guest/usr/sbin/$t"
done
python3 "$here/mkinitramfs.py" "$w/guest.tar" "$deb" "$guest" "$init:/sbin/vk8s-init" "$gbin:/usr/bin/vk8s-guest"
python3 "$here/links.py" "$w/guest.tar" "$root" "$mnt"
python3 "$here/mkinitramfs.py" "$cpio" "$root" "$here/stage0.sh:/init" "$here/flannel.yaml:/etc/vk8s/flannel.yaml" "$bb:/bin/busybox"
# the assets disk: the binaries, then the guest root under guest/
sz=$(( $(du -sm "$a" | cut -f1) + $(du -sm "$w/guest.tar" | cut -f1) + 64 ))
rm -f "$img"
"$MKFS" -q -F -L vk8s-assets -d "$a" "$img" "${sz}M"
python3 "$here/e2fill.py" "$DEBUGFS" "$img" "$w/guest.tar" "${mnt#/assets}"
ls -l "$cpio" "$img"
