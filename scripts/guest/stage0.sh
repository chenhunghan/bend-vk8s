#!/bin/busybox sh
# Stage 0. The initramfs holds only this script, busybox, the virtio and
# ext4 modules and symlinks into /assets (scripts/guest/pack.sh), since it
# stays in RAM. Load the modules, then move the initramfs into a tmpfs
# (runc's pivot_root refuses the initramfs rootfs), mount the read-only
# assets disk at /assets in it, and switch_root: vk8s (host/init.bend, on
# the disk at /assets/guest/sbin/vk8s-init) runs as PID 1, and its pages
# are the disk's page cache, not the VM's RAM.
bb=/bin/busybox
$bb mkdir -p /proc /dev /newroot
$bb mount -t proc proc /proc
$bb mount -t devtmpfs dev /dev
while read -r m; do
  [ -n "$m" ] && { $bb insmod "$m" || echo "stage0: insmod $m failed"; }
done < /etc/vk8s/modules.early
i=0
while [ ! -b /dev/vda ] && [ $i -lt 100 ]; do $bb usleep 50000 || $bb sleep 1; i=$((i + 1)); done
$bb mount -t tmpfs -o mode=0755 tmpfs /newroot
for f in /*; do
  case "$f" in /proc|/newroot|/dev|/sys|/boot) ;; *) $bb cp -a "$f" /newroot/ ;; esac
done
$bb mkdir -p /newroot/proc /newroot/dev /newroot/sys /newroot/assets
$bb mount -t ext4 -o ro /dev/vda /newroot/assets || echo "stage0: cannot mount the assets disk /dev/vda"
$bb umount /dev
$bb umount /proc
export PATH=/var/lib/vcluster/bin:/var/lib/vcluster/bin/cni/bin:/usr/sbin:/usr/bin:/sbin:/bin
exec $bb switch_root /newroot /sbin/vk8s-init
