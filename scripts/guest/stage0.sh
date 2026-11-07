#!/bin/busybox sh
# Stage 0: move the initramfs into a tmpfs and switch_root into it, so the
# real root is a mount (runc's pivot_root refuses the initramfs rootfs).
# Then vk8s (host/init.bend) runs as PID 1.
/bin/busybox mkdir -p /proc /newroot
/bin/busybox mount -t proc proc /proc
/bin/busybox mount -t tmpfs -o mode=0755 tmpfs /newroot
for f in /*; do
  case "$f" in /proc|/newroot|/dev|/sys) ;; *) /bin/busybox cp -a "$f" /newroot/ ;; esac
done
/bin/busybox mkdir -p /newroot/proc /newroot/dev /newroot/sys
/bin/busybox umount /proc
exec /bin/busybox switch_root /newroot /sbin/vk8s-init
