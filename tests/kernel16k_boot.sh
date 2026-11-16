#!/usr/bin/env bash
# Boots a guest kernel under qemu-system-aarch64 (-M virt -cpu neoverse-n1,
# TCG) with the guest's real boot path: pack.sh's initramfs (stage 0, the
# early modules from this kernel) and assets disk (squashfs, zstd: the
# Debian root of debs.txt, the module list of modules.txt, the Kubernetes
# binaries of fetch-assets.sh). The kernel is the 16 KiB-page build
# (scripts/guest/kernel.sh; the default) or, with PAGE_SIZE=4096, Alpine's
# linux-virt (scripts/guest/alpine-kernel.sh). A test PID 1 stands in for
# vk8s-init (which needs bend and zig): it reports the page size and how
# stage 0 mounted the assets disk, mounts it again where Plan.disks.v2
# does (/var/lib/vcluster/bin), loads every module of /etc/vk8s/modules
# (ext4, for the data disk, among them), runs iptables against nf_tables,
# runs each asset binary's version command from the second mount and
# starts etcd (bbolt sizes its pages from the system's) for a put and a
# get. It also checks that the tools docs/GOAL.md section 9 drops are not
# on the disk.
#
# usage: [PAGE_SIZE=16384|4096] tests/kernel16k_boot.sh KERNEL_DIR ASSETS_BIN
# Needs qemu-system-aarch64, python3, squashfs-tools 4.6+. Prints
# PASS/FAIL lines and the boot log; exits 1 on any FAIL.
set -uo pipefail
cd "$(dirname "$0")/.."
[ $# = 2 ] || { sed -n 's/^# usage: //p' "$0"; exit 2; }
k=$1 a=$2
page=${PAGE_SIZE:-16384}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

# Debian's static busybox for stage 0, the guest's Debian root plus
# getconf (libc-bin)
python3 -I scripts/guest/debs.py "$tmp/bb.tar" busybox-static >/dev/null || { echo "FAIL fetch busybox-static"; exit 1; }
python3 -I - "$tmp/bb.tar" "$tmp/busybox" <<'PY'
import sys, tarfile
t = tarfile.open(sys.argv[1])
m = next(t.getmember(n) for n in ("usr/bin/busybox", "bin/busybox") if n in t.getnames())
open(sys.argv[2], "wb").write(t.extractfile(m).read())
PY
chmod 755 "$tmp/busybox"
python3 -I scripts/guest/debs.py "$tmp/deb.tar" $(cat scripts/guest/debs.txt) libc-bin >/dev/null \
  || { echo "FAIL fetch the Debian root"; exit 1; }

cat > "$tmp/init" <<'EOF'
#!/bin/busybox sh
bb=/bin/busybox
$bb mount -t proc proc /proc
$bb mount -t sysfs sys /sys
$bb mount -t devtmpfs dev /dev
$bb mkdir -p /tmp /run
echo "vk8s-test: PID 1 started (pid $$)"
echo "vk8s-test: uname $($bb uname -r) $($bb uname -m)"
echo "vk8s-test: getconf PAGESIZE $(/usr/bin/getconf PAGESIZE)"
echo "vk8s-test: $($bb grep -m1 KernelPageSize /proc/self/smaps | $bb tr -s ' ')"
echo "vk8s-test: assets $($bb grep ' /assets ' /proc/mounts)"
$bb mkdir -p /var/lib/vcluster/bin
if $bb mount -t squashfs -o ro /dev/vda /var/lib/vcluster/bin 2>/tmp/err; then echo "vk8s-test: bin mount ok"
else echo "vk8s-test: bin mount failed: $($bb cat /tmp/err)"; fi
ok=0 bad=0
while read -r m; do
  [ -n "$m" ] || continue
  if $bb insmod "$m" 2>/tmp/err; then ok=$((ok + 1)); else bad=$((bad + 1)); echo "vk8s-test: insmod $m: $($bb cat /tmp/err)"; fi
done < /etc/vk8s/modules
echo "vk8s-test: modules loaded $ok failed $bad"
$bb grep -qw ext4 /proc/filesystems && echo "vk8s-test: ext4 registered"
echo "vk8s-test: page_reporting_order $($bb cat /sys/module/page_reporting/parameters/page_reporting_order 2>&1)"
echo "vk8s-test: balloon $($bb ls /sys/bus/virtio/drivers/virtio_balloon 2>/dev/null | $bb grep -c virtio) device(s) bound"
run() { # run NAME CMD...: one line, ok or the exit code
  n=$1; shift
  if out=$("$@" 2>&1 </dev/null); then echo "vk8s-test: run $n ok: $(echo "$out" | $bb head -n1)"
  else echo "vk8s-test: run $n rc=$?: $(echo "$out" | $bb tail -n2 | $bb tr '\n' ' ')"; fi
}
run iptables /usr/sbin/iptables -V
run iptables-nat /usr/sbin/iptables -t nat -A POSTROUTING -s 10.244.0.0/16 -j MASQUERADE
run iptables-list /usr/sbin/iptables-save
run conntrack /usr/sbin/conntrack -V
A=/var/lib/vcluster/bin
for b in etcd kine kube-apiserver kube-controller-manager kube-scheduler kubelet \
    konnectivity-server containerd runc registry; do
  [ -x $A/$b ] && run $b $A/$b --version
done
[ -x $A/etcdctl ] && run etcdctl $A/etcdctl version
[ -x $A/etcdutl ] && run etcdutl $A/etcdutl version
[ -x $A/kubeadm ] && run kubeadm $A/kubeadm version -o short
[ -x $A/kubectl ] && run kubectl $A/kubectl version --client
[ -x $A/ctr ] && run ctr $A/ctr --version
[ -x $A/containerd-shim-runc-v2 ] && run containerd-shim-runc-v2 $A/containerd-shim-runc-v2 -v
for b in $A/cni/bin/*; do [ -x "$b" ] && run "cni/${b##*/}" $bb env CNI_COMMAND=VERSION "$b"; done
if [ -x $A/etcd ]; then
  $bb ip link set lo up
  $A/etcd --data-dir /tmp/etcd --listen-client-urls http://127.0.0.1:2379 \
    --advertise-client-urls http://127.0.0.1:2379 --listen-peer-urls http://127.0.0.1:2380 >/tmp/etcd.log 2>&1 &
  i=0
  until $A/etcdctl endpoint health >/dev/null 2>&1 || [ $i -ge 120 ]; do $bb sleep 1; i=$((i + 1)); done
  run etcd-put $A/etcdctl put vk8s page16k
  run etcd-get $A/etcdctl get vk8s --print-value-only
  $bb kill $! 2>/dev/null
fi
echo "vk8s-test: done"
$bb sync
$bb poweroff -f
EOF
chmod 755 "$tmp/init"
printf 'not used\n' > "$tmp/vk8s-guest"; chmod 755 "$tmp/vk8s-guest"
printf 'not used\n' > "$tmp/cacert.pem"

# docs/GOAL.md section 9: no tool that nothing in the guest runs
for t in crictl helm kube-proxy vcluster-tunnel pause-image.txt cni/bin/bandwidth cni/bin/firewall; do
  if [ -e "$a/$t" ]; then fail "$t is not in the assets"; else pass "$t is not in the assets"; fi
done

if scripts/guest/pack.sh "$k" "$tmp/deb.tar" "$tmp/init" "$tmp/vk8s-guest" "$tmp/busybox" "$tmp/cacert.pem" \
    "$a" "$tmp/vk8s.cpio" "$tmp/assets.img" >"$tmp/pack.log" 2>&1; then
  pass "pack.sh resolves modules.early.txt and modules.txt against the kernel"
else
  fail "pack.sh resolves modules.early.txt and modules.txt against the kernel"; cat "$tmp/pack.log"; exit 1
fi
echo "--- sizes (KiB): the assets' binaries, the guest root, the squashfs disk"
du -sk "$a" | cut -f1
du -sk "$tmp/deb.tar" | cut -f1
du -k "$tmp/assets.img" | cut -f1

# The VM is close to bend-vmm's: a PL011 console (ttyAMA0), the
# initramfs, the assets disk as the only virtio-blk (/dev/vda), the
# balloon, no network. The CPU is a fixed model, not -cpu max: under TCG,
# max turns on SME, SVE, QARMA5 pointer authentication, WFxT and LPA2,
# which no Mac guest sees, and with it the boot stopped after "PM: genpd:
# Disabling unused power domains" (no /init, no hung-task or lockup
# report in 25 minutes) while the same kernel boots under bend-vmm.
# Neoverse-N1 (Armv8.2) has the 16 KiB translation granule.
timeout 1500 qemu-system-aarch64 -M virt -cpu neoverse-n1 -smp 2 -m 2048 -nographic -no-reboot -nic none \
  -kernel "$k/Image" -initrd "$tmp/vk8s.cpio" -append "console=ttyAMA0 panic=-1" \
  -drive if=none,id=assets,file="$tmp/assets.img",format=raw,readonly=on \
  -device virtio-blk-device,drive=assets \
  -device virtio-balloon-device,free-page-reporting=on \
  </dev/null >"$tmp/boot.log" 2>&1
echo "qemu exit $?"
tr -d '\r' < "$tmp/boot.log" > "$tmp/log"
echo "--- boot log (kernel lines)"
grep -E '^\[ *[0-9.]+\] (Booting Linux|Linux version|Memory:|Kernel command line|Run /init|Freeing unused|virtio_balloon|EXT4-fs|squashfs|SQUASHFS)' "$tmp/log" | head -40
grep -E 'stage0:' "$tmp/log"
grep -qE '\] Run /init as init process' "$tmp/log" || { echo "--- no /init; the last kernel lines"; grep -E '^\[ *[0-9.]+\]' "$tmp/log" | tail -5; }
echo "--- PID 1"
grep 'vk8s-test:' "$tmp/log"
echo "---"
has() { grep -qF -- "$1" "$tmp/log"; }
check() { if has "$2"; then pass "$1"; else fail "$1"; fi; }
check "kernel boots" "Linux version $(ls "$k/lib/modules")"
check "PID 1 starts" "vk8s-test: PID 1 started (pid 1)"
check "getconf PAGESIZE is $page" "vk8s-test: getconf PAGESIZE $page"
check "KernelPageSize is $((page / 1024)) kB" "vk8s-test: KernelPageSize: $((page / 1024)) kB"
check "stage 0 mounts the assets disk as squashfs, read-only, at /assets" "vk8s-test: assets /dev/vda /assets squashfs ro,"
check "PID 1 mounts it again at /var/lib/vcluster/bin (Plan.disks.v2)" "vk8s-test: bin mount ok"
if grep -q 'vk8s-test: modules loaded [1-9][0-9]* failed 0$' "$tmp/log"; then pass "every module of modules.txt loads"; else fail "every module of modules.txt loads"; fi
check "ext4 loads late, for the data disk" "vk8s-test: ext4 registered"
check "virtio_balloon binds the balloon" "vk8s-test: balloon 1 device(s) bound"
for n in iptables iptables-nat iptables-list conntrack etcd etcdctl etcdutl kine kube-apiserver kube-controller-manager \
    kube-scheduler kubelet kubeadm kubectl containerd containerd-shim-runc-v2 runc ctr registry \
    cni/bridge cni/host-local cni/loopback cni/portmap etcd-put; do
  check "$n runs" "vk8s-test: run $n ok"
done
check "etcd returns the value" "vk8s-test: run etcd-get ok: page16k"
# a page-size problem kills the process (SIGSEGV, SIGBUS, SIGABRT):
# no run may end on a signal (exit code 128 and above)
if grep -Eq 'vk8s-test: run [^ ]* rc=(12[89]|1[3-9][0-9]|2[0-9][0-9])' "$tmp/log"; then
  fail "no binary dies on a signal"; grep -E 'vk8s-test: run [^ ]* rc=(12[89]|1[3-9][0-9]|2[0-9][0-9])' "$tmp/log"
else pass "no binary dies on a signal"; fi
check "PID 1 finishes" "vk8s-test: done"
[ $fails = 0 ] || { echo "--- full boot log"; cat "$tmp/log"; }
if [ $fails = 0 ]; then echo "all PASS"; else echo "$fails FAIL"; exit 1; fi
