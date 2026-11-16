#!/usr/bin/env bash
# Boots the Linux dev VM image (scripts/dev/rootfs.sh: Image, dev.cpio,
# rootfs.img) under qemu-system-aarch64 (-M virt -cpu max, TCG), as
# scripts/dev/linux-vm.sh boots it under bend-vmm on the Mac: a PL011
# console (ttyAMA0), the stage-0 initramfs, the root filesystem as the only
# virtio-blk disk (/dev/vda), a 9p share tagged "share", and the user-mode
# NAT bend-vmm also gives (guest 10.0.2.15, host 10.0.2.2, resolver
# 10.0.2.3) with 127.0.0.1:PORT forwarded to the guest's port 22. The
# kernel command line is linux-vm.sh's, with a fresh ssh key.
#
# It checks over ssh: systemd reached multi-user.target and runs with no
# failed unit, sshd is active, the dev user has passwordless sudo, the
# kernel is the image's, its modules load (nf_tables, overlay, br_netfilter)
# and iptables, nft and conntrack run, cgroup v2 is mounted, the share is at
# /repo, the root filesystem grew to the disk, and the VM powers off.
#
# usage: tests/dev_vm_boot.sh IMAGE_DIR
# Needs qemu-system-aarch64 (with 9p), ssh, ssh-keygen. Prints PASS/FAIL
# lines and the console log; exits 1 on any FAIL.
set -uo pipefail
cd "$(dirname "$0")/.."
[ $# = 1 ] || { sed -n 's/^# usage: //p' "$0"; exit 2; }
d=$1
PORT=${PORT:-2222}
tmp=$(mktemp -d)
qpid=
trap '[ -n "$qpid" ] && kill "$qpid" 2>/dev/null; rm -rf "$tmp"' EXIT
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

for f in Image dev.cpio rootfs.img; do [ -f "$d/$f" ] || { echo "FAIL $d/$f is missing"; exit 1; }; done
# the disk is a grown copy, as linux-vm.sh makes it
cp "$d/rootfs.img" "$tmp/disk.img"
img_bytes=$(stat -c %s "$d/rootfs.img")
truncate -s 6G "$tmp/disk.img"
mkdir "$tmp/share"; echo "devvm-share-ok" > "$tmp/share/marker"
ssh-keygen -q -t ed25519 -N '' -C devvm-test -f "$tmp/key"
cmdline=$(scripts/dev/linux-vm.sh cmdline "$tmp/key.pub") || { echo "FAIL linux-vm.sh cmdline"; exit 1; }
echo "cmdline: $cmdline"

# -cpu max under TCG: the stock Alpine kernel has 4 KiB pages (the
# 16 KiB kernel of tests/kernel16k_boot.sh needed neoverse-n1)
timeout 2400 qemu-system-aarch64 -M virt -cpu max -smp 4 -m 4096 -nographic -no-reboot \
  -kernel "$d/Image" -initrd "$d/dev.cpio" -append "$cmdline" \
  -drive if=none,id=root,file="$tmp/disk.img",format=raw \
  -device virtio-blk-device,drive=root \
  -netdev user,id=n0,net=10.0.2.0/24,host=10.0.2.2,dns=10.0.2.3,hostfwd=tcp:127.0.0.1:$PORT-:22 \
  -device virtio-net-device,netdev=n0 \
  -fsdev local,id=fs0,path="$tmp/share",security_model=none \
  -device virtio-9p-device,fsdev=fs0,mount_tag=share \
  </dev/null >"$tmp/boot.log" 2>&1 &
qpid=$!

S() { # S CMD: run CMD in the guest as dev
  ssh -i "$tmp/key" -p "$PORT" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 -o LogLevel=ERROR dev@127.0.0.1 "$@"
}
t0=$(date +%s) up=0
while kill -0 "$qpid" 2>/dev/null && [ $(( $(date +%s) - t0 )) -lt 1800 ]; do
  if S true 2>/dev/null; then up=1; break; fi
  sleep 5
done
echo "ssh after $(( $(date +%s) - t0 )) s (up=$up)"
log() { tr -d '\r' < "$tmp/boot.log" | sed 's/\x1b\[[0-9;]*m//g'; }  # no colors
has() { log | grep -qF -- "$1"; }
check() { if has "$2"; then pass "$1"; else fail "$1"; fi; }
check "kernel boots" "Linux version"
check "stage 0 switches root to /dev/vda" "devvm-stage0: switch_root /dev/vda"
check "systemd starts as PID 1" "systemd["
if [ $up = 1 ]; then pass "ssh as dev with the key from the command line"; else fail "ssh as dev with the key from the command line"; fi

if [ $up = 1 ]; then
  st=$(S 'timeout 600 systemctl is-system-running --wait' 2>&1)
  echo "is-system-running: $st"
  if [ "$st" = running ]; then pass "systemd is running with no failed unit"
  else fail "systemd is running with no failed unit"; S 'systemctl --failed --no-pager; journalctl -b -p warning --no-pager | tail -n 60'; fi
  g() { # g NAME WANT CMD: CMD's output is WANT
    local got; got=$(S "$3" 2>&1)
    if [ "$got" = "$2" ]; then pass "$1"; else fail "$1: want '$2', got '$got'"; fi
  }
  g "multi-user.target is active" active 'systemctl is-active multi-user.target'
  g "sshd is active" active 'systemctl is-active ssh'
  g "dev has passwordless sudo" 0 'sudo -n id -u'
  g "the kernel is the image's" "$(log | grep -m1 -o 'Linux version [^ ]*' | cut -d' ' -f3)" 'uname -r'
  g "cgroup v2 is mounted" cgroup2fs 'stat -fc %T /sys/fs/cgroup'
  g "modules load (nf_tables, overlay, br_netfilter)" ok 'sudo -n modprobe -a nf_tables overlay br_netfilter && echo ok'
  g "iptables runs on nf_tables" ok 'sudo -n iptables -t nat -A POSTROUTING -s 10.244.0.0/16 -j MASQUERADE && sudo -n iptables-save | grep -q 10.244.0.0/16 && echo ok'
  g "nft runs" ok 'sudo -n nft list ruleset >/dev/null && echo ok'
  g "conntrack runs" ok 'sudo -n conntrack -L >/dev/null 2>&1 && echo ok'
  g "the default route is 10.0.2.2" 10.0.2.2 "ip -4 route show default | cut -d' ' -f3"
  g "the share is mounted at /repo" devvm-share-ok 'cat /repo/marker'
  rootb=$(S 'df -B1 --output=size / | tail -n1 | tr -d " "' 2>/dev/null)
  echo "root filesystem: $rootb bytes (image $img_bytes)"
  if [ -n "$rootb" ] && [ "$rootb" -gt $((5 << 30)) ]; then pass "the root filesystem grows to the disk"
  else fail "the root filesystem grows to the disk"; fi
  S 'sudo -n systemctl poweroff' >/dev/null 2>&1
fi
i=0
while kill -0 "$qpid" 2>/dev/null && [ $i -lt 120 ]; do sleep 1; i=$((i + 1)); done
if kill -0 "$qpid" 2>/dev/null; then fail "the VM powers off"; kill "$qpid"; else pass "the VM powers off"; fi
qpid=
check "systemd reaches multi-user" "Reached target multi-user.target"
echo "--- console (stage 0, systemd targets, failures)"
log | grep -E 'devvm-stage0|Reached target|Failed|FAILED|Kernel panic|Linux version' | head -60
[ $fails = 0 ] || { echo "--- full console log"; log; }
if [ $fails = 0 ]; then echo "all PASS"; else echo "$fails FAIL"; exit 1; fi
