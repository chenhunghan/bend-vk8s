#!/usr/bin/env bash
# Builds the Linux dev VM for the Mac (docs/ref/dev-vm.md; docs/ref/
# explore-linux-hosts.md phase 8 and D14 option b) in OUT (default
# out/dev-vm):
#   Image       Alpine's linux-virt arm64 kernel, the one the guest assets
#               use (scripts/guest/build.sh takes it the same way), unpacked
#               from its EFI zboot
#   dev.cpio    the initramfs: a stage-0 variant (scripts/dev/init) with
#               busybox and the virtio_mmio, virtio_blk and ext4 modules of
#               that kernel; it switch_roots to /dev/vda
#   rootfs.img  ext4: Debian trixie arm64 from debootstrap, with systemd,
#               iproute2, iptables, nftables, conntrack, kmod, curl,
#               ca-certificates, openssh-server and sudo; the kernel's
#               modules under /usr/lib/modules; a 'dev' user with
#               passwordless sudo; the ssh key hook; 10.0.2.15 on eth0
#               (bend-vmm's and qemu's user-mode NAT); the 9p share
#               tagged "share" at /repo; the root grows to the disk
#   KERNEL      where the kernel came from, and its version
#   SHA256SUMS  of Image, dev.cpio and rootfs.img
#
# usage: rootfs.sh [OUT]
# Runs on Linux arm64 (GitHub's ubuntu-24.04-arm; CI job dev-vm) and needs
# root through sudo for debootstrap, the chroot and mkfs.ext4 -d. Needs
# debootstrap, debian-archive-keyring, e2fsprogs, kmod (depmod), python3,
# curl, gzip.
# Environment: KERNEL_DIR (a kernel already unpacked as Image and
# lib/modules/<version>, such as out/build/kernel16k; default: fetch
# Alpine's linux-virt), ALPINE (the Alpine repository), MIRROR (the Debian
# mirror), DEV_VM_IMG_SIZE (rootfs.img, default 3G; linux-vm.sh grows its
# copy, and systemd grows the filesystem on boot).
set -euo pipefail
cd "$(dirname "$0")/../.."
out=${1:-out/dev-vm}
SUITE=trixie
MIRROR=${MIRROR:-http://deb.debian.org/debian}
ALPINE=${ALPINE:-https://dl-cdn.alpinelinux.org/alpine/latest-stable/main/aarch64}
SIZE=${DEV_VM_IMG_SIZE:-3G}
PKGS=systemd,systemd-sysv,udev,dbus,libpam-systemd,iproute2,iptables,nftables,conntrack,kmod,curl,ca-certificates,openssh-server,sudo,busybox-static,procps,iputils-ping,less,netbase
as_root() { if [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi; }
w=$(mktemp -d)
trap 'as_root rm -rf "$w"' EXIT
mkdir -p "$out"
rm -f "$out/Image" "$out/dev.cpio" "$out/rootfs.img" "$out/KERNEL" "$out/SHA256SUMS"

# --- the kernel
if [ -n "${KERNEL_DIR:-}" ]; then
  k=$KERNEL_DIR
  cp "$k/Image" "$out/Image"
  echo "kernel dir: $k" > "$out/KERNEL"
else
  k=$w/kernel; mkdir -p "$k"
  apk=$(curl -fsSL "$ALPINE/" | grep -o 'linux-virt-[0-9][^"]*\.apk' | head -1)
  [ -n "$apk" ] || { echo "rootfs.sh: no linux-virt package at $ALPINE" >&2; exit 1; }
  curl -fsSL --retry 3 -o "$w/k.apk" "$ALPINE/$apk"
  tar -xzf "$w/k.apk" -C "$k" 2>/dev/null || true
  python3 -I - "$k/boot/vmlinuz-virt" "$out/Image" <<'PY'
import sys, struct, gzip
b = open(sys.argv[1], "rb").read()
assert b[4:8] == b"zimg", "not an EFI zboot image"
off, size = struct.unpack("<II", b[8:16])
assert b[24:28] == b"gzip", b[24:32]
open(sys.argv[2], "wb").write(gzip.decompress(b[off:off + size]))
PY
  echo "alpine: $ALPINE/$apk sha256 $(sha256sum "$w/k.apk" | cut -d' ' -f1)" > "$out/KERNEL"
fi
kver=$(ls "$k/lib/modules")
[ "$(echo "$kver" | wc -l)" = 1 ] || { echo "rootfs.sh: want one kernel in $k/lib/modules, have: $kver" >&2; exit 1; }
echo "version: $kver" >> "$out/KERNEL"

# --- the root filesystem
root=$w/root
script=$SUITE
[ -e "/usr/share/debootstrap/scripts/$SUITE" ] || script=/usr/share/debootstrap/scripts/sid
as_root debootstrap --arch=arm64 --variant=minbase --include="$PKGS" \
  --keyring=/usr/share/keyrings/debian-archive-keyring.gpg "$SUITE" "$root" "$MIRROR" "$script"

put() { # put PATH MODE: stdin becomes the root's PATH
  as_root mkdir -p "$(dirname "$root/$1")"
  as_root tee "$root/$1" >/dev/null
  as_root chmod "$2" "$root/$1"
}
echo vk8s-dev | put /etc/hostname 644
printf '127.0.0.1\tlocalhost\n127.0.1.1\tvk8s-dev\n::1\tlocalhost ip6-localhost ip6-loopback\n' | put /etc/hosts 644
# the root grows to the disk (linux-vm.sh makes the disk larger than the
# image); the share (bend-vmm --share, qemu's virtio-9p) mounts on first
# use, so a VM without one does not fail a unit
put /etc/fstab 644 <<'F'
/dev/vda  /      ext4  rw,relatime,x-systemd.growfs                        0 0
share     /repo  9p    trans=virtio,version=9p2000.L,nofail,x-systemd.automount  0 0
F
as_root mkdir -p "$root/repo"
printf '9pnet_virtio\n9p\n' | put /etc/modules-load.d/devvm.conf 644
# bend-vmm's user-mode NAT, as the guest assets set it (src/guest/plan.bend
# Plan.net): 10.0.2.15/24, the host 10.0.2.2, the resolver 10.0.2.3; qemu's
# -netdev user gives the same
put /etc/systemd/network/10-eth0.network 644 <<'F'
[Match]
Name=eth0 en*

[Network]
Address=10.0.2.15/24
Gateway=10.0.2.2
DNS=10.0.2.3
F
as_root rm -f "$root/etc/resolv.conf"
echo 'nameserver 10.0.2.3' | put /etc/resolv.conf 644
put /etc/apt/sources.list 644 <<F
deb $MIRROR $SUITE main
deb $MIRROR $SUITE-updates main
deb http://security.debian.org/debian-security $SUITE-security main
F
# the dev user: passwordless sudo, no password (ssh keys only)
echo 'dev ALL=(ALL:ALL) NOPASSWD:ALL' | put /etc/sudoers.d/dev 440
put /etc/ssh/sshd_config.d/devvm.conf 644 <<'F'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
F
# every VM makes its own host keys on its first boot
put /etc/systemd/system/devvm-hostkeys.service 644 <<'F'
[Unit]
Description=Dev VM: make the ssh host keys
Before=ssh.service
ConditionPathExists=!/etc/ssh/ssh_host_ed25519_key

[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A

[Install]
WantedBy=multi-user.target
F
# the authorized_keys hook: devvm.ssh_key=<base64 of an authorized_keys
# line> on the kernel command line (scripts/dev/linux-vm.sh puts it there)
# goes into ~dev/.ssh/authorized_keys on every boot
put /usr/local/sbin/devvm-ssh-key 755 <<'F'
#!/bin/sh
set -eu
key=
for w in $(cat /proc/cmdline); do
  case "$w" in devvm.ssh_key=*) key=$(printf '%s' "${w#devvm.ssh_key=}" | base64 -d) ;; esac
done
[ -n "$key" ] || exit 0
d=/home/dev/.ssh
install -d -m 700 -o dev -g dev "$d"
touch "$d/authorized_keys"
grep -qxF -- "$key" "$d/authorized_keys" || printf '%s\n' "$key" >> "$d/authorized_keys"
chown dev:dev "$d/authorized_keys"
chmod 600 "$d/authorized_keys"
F
put /etc/systemd/system/devvm-ssh-key.service 644 <<'F'
[Unit]
Description=Dev VM: the ssh key from the kernel command line
After=local-fs.target
Before=ssh.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/devvm-ssh-key

[Install]
WantedBy=multi-user.target
F
as_root chroot "$root" /bin/sh -eu <<'C'
useradd -m -s /bin/bash -G sudo dev
usermod -p '*' dev
rm -f /etc/ssh/ssh_host_*
systemctl enable systemd-networkd devvm-hostkeys devvm-ssh-key ssh
# no first-boot prompts on the console
ln -sf /dev/null /etc/systemd/system/systemd-firstboot.service
# a new machine id on the first boot of each copy
: > /etc/machine-id
apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin /var/log/*.log
C

# --- the kernel's modules, uncompressed (any kmod reads them), and depmod
md=$root/usr/lib/modules
as_root mkdir -p "$md"
as_root cp -a "$k/lib/modules/$kver" "$md/"
as_root find "$md/$kver" -name '*.ko.gz' -exec gzip -d {} +
as_root find "$md/$kver" -name '*.ko.xz' -exec xz -d {} +
as_root find "$md/$kver" -name '*.ko.zst' -exec zstd -q -d --rm {} +
as_root depmod -b "$root" "$kver"

# --- the initramfs: stage 0, busybox, the early modules
ir=$w/initrd
mkdir -p "$ir/bin" "$ir/etc/dev"
cp "$root/usr/bin/busybox" "$ir/bin/busybox"
cp scripts/dev/init "$ir/init"
python3 -I scripts/guest/modules.py "$k" "$ir/boot/modules" /boot/modules "$ir/etc/dev/modules.early" \
  virtio_mmio virtio_blk ext4
python3 -I scripts/guest/mkinitramfs.py "$out/dev.cpio" "$ir"

# --- rootfs.img
as_root mkfs.ext4 -q -F -L vk8s-dev -d "$root" "$out/rootfs.img" "$SIZE"
as_root chown "$(id -u):$(id -g)" "$out/rootfs.img"
(cd "$out" && sha256sum Image dev.cpio rootfs.img > SHA256SUMS)
ls -l "$out"
cat "$out/KERNEL" "$out/SHA256SUMS"
