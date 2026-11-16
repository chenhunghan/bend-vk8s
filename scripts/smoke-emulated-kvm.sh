#!/usr/bin/env bash
# The Linux arm64 KVM smoke (scripts/smoke-linux.sh) on a host with no
# /dev/kvm, such as a GitHub-hosted arm64 runner (docs/GOAL.md section 8:
# arm64 KVM is tested under emulation, and recorded as such). QEMU emulates
# an arm64 CPU with EL2 (TCG, -machine virt,virtualization=on -cpu max);
# an Ubuntu arm64 kernel boots in it with KVM (the L1); the L1 mounts this
# host's root read-only over 9p and runs the smoke in a chroot of it, so
# this host's tools (kubectl, nc, curl, perl, libX11) run unchanged. This
# is bend-vmm's scripts/ci/emulated-kvm.sh, with the smoke in place of its
# check-host.sh. The cluster's VMs (the L2) run on the L1's KVM.
#
# The L1 gets a work disk (ext4, as bend-vmm wants for VM images) that
# holds HOME, TMPDIR, the vk8s binary and the guest assets, copied in on
# this host with mke2fs -d so the sparse disks stay sparse.
#
# Every guest instruction is emulated: the smoke takes hours. Its waits
# and vk8s's are scaled (SMOKE_SLOW, VK8S_WAIT_SCALE).
#
# usage: scripts/smoke-emulated-kvm.sh
# VK8S_BIN (default out/vk8s): the binary (scripts/build-linux.sh).
# VK8S_ASSETS: the arm64 guest assets (scripts/guest/build.sh).
# L1_MEM (MiB, default 10240), L1_CPUS (default nproc), L1_TIMEOUT
# (seconds, default 17400), L1_DISK (GiB, default 64), SMOKE_SLOW
# (default 6), VK8S_WAIT_SCALE (default 20).
# Needs Linux on arm64, qemu-system-aarch64, apt-get (Ubuntu: the L1's
# kernel and busybox come from this host's archive), mke2fs, zstd, cpio,
# python3 and kubectl. Prints EMULATED-KVM SMOKE OK or FAILED.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(uname -s)-$(uname -m)" = Linux-aarch64 ] || { echo "smoke-emulated-kvm: needs Linux on arm64"; exit 2; }
repo=$(pwd)
bin=$(realpath "${VK8S_BIN:-out/vk8s}")
[ -x "$bin" ] || { echo "smoke-emulated-kvm: no vk8s binary at $bin (scripts/build-linux.sh)"; exit 2; }
assets=${VK8S_ASSETS:-}
[ -n "$assets" ] && [ -f "$assets/Image" ] || { echo "smoke-emulated-kvm: VK8S_ASSETS must name an arm64 asset build (scripts/guest/build.sh)"; exit 2; }
kubectl=$(command -v kubectl) || { echo "smoke-emulated-kvm: no kubectl on PATH"; exit 2; }
slow=${SMOKE_SLOW:-6}
scale=${VK8S_WAIT_SCALE:-20}

# A runner that has KVM runs the smoke on it directly.
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
  echo "== /dev/kvm is here: the smoke runs on it"
  exec scripts/smoke-linux.sh
fi
echo "== no usable /dev/kvm ($(ls -l /dev/kvm 2>&1)): emulating EL2"
mem=${L1_MEM:-10240}
cpus=${L1_CPUS:-$(nproc)}
l1=$repo/out/l1
rm -rf "$l1" && mkdir -p "$l1/root" "$l1/deb" "$l1/mods" "$l1/stage"

echo "== the L1 kernel (this host's Ubuntu archive)"
# linux-image-generic names the archive's current generic kernel
kver=$(apt-cache depends linux-image-generic | sed -n 's/^ *Depends: linux-image-\([0-9][^ ]*-generic\)$/\1/p' | head -1)
[ -n "$kver" ] || { echo "smoke-emulated-kvm: no generic kernel in apt-cache (run apt-get update)"; exit 1; }
(cd "$l1/deb" && apt-get download "linux-image-unsigned-$kver" "linux-modules-$kver" "linux-modules-extra-$kver" busybox-static >/dev/null)
for d in "$l1"/deb/*.deb; do dpkg-deb -x "$d" "$l1/deb/x"; done
python3 - "$l1/deb/x/boot/vmlinuz-$kver" "$l1/Image" <<'PY'
import sys, struct, gzip, zlib
b = open(sys.argv[1], "rb").read()
if b[:2] == b"\x1f\x8b":
    b = gzip.decompress(b)
elif b[4:8] == b"zimg":
    # EFI zboot: the payload's offset and size, then its compression
    off, size = struct.unpack("<II", b[8:16])
    assert b[24:28] == b"gzip", b[24:32]
    b = gzip.decompress(b[off:off + size])
assert b[56:60] == b"ARM\x64", "not an arm64 Image"
open(sys.argv[2], "wb").write(b)
PY
# 9p (the host's root), the PL031 RTC (the wall clock: TLS certificates
# need it), virtio-blk (the work disk) when the kernel builds it as a module
mods="netfs 9pnet 9pnet_virtio 9p rtc-pl031 virtio_blk"
for m in $mods; do
  f=$(find "$l1/deb/x/lib/modules/$kver" -name "$m.ko*" | head -1)
  case $f in
    "") echo "  $m: built in or absent" ;;
    *.zst) zstd -dqf "$f" -o "$l1/mods/$m.ko" ;;
    *) cp "$f" "$l1/mods/$m.ko" ;;
  esac
done
[ -f "$l1/mods/9p.ko" ] || grep -q '^CONFIG_9P_FS=y' "$l1/deb/x/boot/config-$kver" 2>/dev/null || { echo "smoke-emulated-kvm: $kver has no 9p"; exit 1; }
grep -E '^CONFIG_(KVM|VIRTIO_BLK|VIRTIO_MMIO|VIRTIO_NET|EXT4_FS)=' "$l1/deb/x/boot/config-$kver" 2>/dev/null || true
echo "  $kver: $l1/Image"

echo "== the work disk (HOME, TMPDIR, vk8s and the assets)"
s=$l1/stage
mkdir -p "$s/home/.vk8s/assets" "$s/tmp"
cp --sparse=always -a "$assets" "$s/home/.vk8s/assets/dev"
cp "$bin" "$s/vk8s"
du -sh --apparent-size "$s"; du -sh "$s"
truncate -s "${L1_DISK:-64}G" "$l1/work.img"
mke2fs -q -t ext4 -F -E root_owner=0:0 -d "$s" "$l1/work.img"
rm -rf "$s"

echo "== the L1's init"
envs="HOME=/tmp/w/home TMPDIR=/tmp/w/tmp PATH=$(dirname "$kubectl"):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
envs="$envs VK8S_BIN=/tmp/w/vk8s VK8S_ASSETS=/tmp/w/home/.vk8s/assets/dev SMOKE_SLOW=$slow VK8S_WAIT_SCALE=$scale"
cat > "$l1/root/init" <<EOF
#!/bin/busybox sh
/bin/busybox --install -s /bin
mount -t proc proc /proc; mount -t sysfs sys /sys; mount -t devtmpfs dev /dev
for m in $mods; do [ -f /lib/modules/\$m.ko ] && insmod /lib/modules/\$m.ko; done
# the wall clock, from QEMU's PL031
hwclock -s || echo 'L1: no RTC'
mkdir -p /host
mount -t 9p -o trans=virtio,version=9p2000.L,ro,msize=1048576,cache=loose host /host
mount -t tmpfs -o size=1g tmp /host/tmp
mount -t tmpfs run /host/run
mkdir -p /host/tmp/w /host/run/systemd/resolve
mount -t ext4 /dev/vda /host/tmp/w || echo 'L1: cannot mount the work disk'
echo "nameserver 10.0.2.3" > /host/run/systemd/resolve/stub-resolv.conf
cp /host/run/systemd/resolve/stub-resolv.conf /host/run/resolv.conf
mount --bind /host/run/resolv.conf /host/etc/resolv.conf 2>/dev/null
mount --rbind /dev /host/dev || echo 'L1: cannot bind /dev'
mkdir -p /host/dev/shm && mount -t tmpfs -o mode=1777 shm /host/dev/shm
mount -t proc proc /host/proc || echo 'L1: cannot mount /host/proc'
mount -t sysfs sys /host/sys || echo 'L1: cannot mount /host/sys'
mount -t cgroup2 cgroup2 /host/sys/fs/cgroup 2>/dev/null
ip link set lo up; ip link set eth0 up
ip addr add 10.0.2.15/24 dev eth0; ip route add default via 10.0.2.2
echo "L1: \$(uname -r), \$(date -u), kvm: \$(ls -l /dev/kvm 2>&1)"
df -h /host/tmp/w
chroot /host /usr/bin/env -i $envs /bin/bash -c 'cd $repo && scripts/smoke-linux.sh'
echo "L1-EXIT \$?"
sync
poweroff -f
EOF
chmod 755 "$l1/root/init"
mkdir -p "$l1/root/bin" "$l1/root/lib/modules" "$l1/root/proc" "$l1/root/sys" "$l1/root/dev"
cp "$l1/deb/x/bin/busybox" "$l1/root/bin/busybox"
cp "$l1"/mods/*.ko "$l1/root/lib/modules/" 2>/dev/null || true
(cd "$l1/root" && find . | cpio -o -H newc -R 0:0 --quiet) > "$l1/initrd.cpio"
rm -rf "$l1/deb" "$l1/mods"

echo "== the L1 (QEMU TCG with EL2, $cpus vCPUs, $mem MiB): the smoke, waits x$slow, vk8s waits x$scale"
log=$l1/console.log
timeout "${L1_TIMEOUT:-17400}" qemu-system-aarch64 \
  -machine virt,virtualization=on,gic-version=3 -accel tcg,thread=multi,tb-size=1024 \
  -cpu max,pauth-impdef=on -smp "$cpus" -m "$mem" -nographic -no-reboot \
  -kernel "$l1/Image" -initrd "$l1/initrd.cpio" -append "console=ttyAMA0 rdinit=/init quiet" \
  -fsdev local,id=root,path=/,security_model=none,readonly=on \
  -device virtio-9p-device,fsdev=root,mount_tag=host \
  -drive if=none,id=work,file="$l1/work.img",format=raw,cache=unsafe \
  -device virtio-blk-device,drive=work \
  -netdev user,id=n0 -device virtio-net-device,netdev=n0 \
  < /dev/null 2>&1 | tee "$log" || true
code=$(sed -n 's/^L1-EXIT \([0-9]*\).*/\1/p' "$log" | tail -1)
# the smoke's table, for the job summary
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  { echo "### vk8s smoke on emulated KVM (QEMU TCG with EL2, L1 $kver)"; echo
    tr -d '\r' < "$log" | grep '^|' || echo "no table: see the job log"; } >> "$GITHUB_STEP_SUMMARY"
fi
rm -f "$l1/work.img"
[ "${code:-1}" = 0 ] && echo "EMULATED-KVM SMOKE OK" || { echo "EMULATED-KVM SMOKE FAILED (${code:-no exit code})"; exit 1; }
