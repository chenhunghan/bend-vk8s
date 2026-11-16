#!/usr/bin/env bash
# Boots a guest kernel under qemu-system-aarch64 (-M virt -cpu neoverse-n1,
# TCG) with the guest's real boot path, once per VM role
# (docs/ref/footprint-decisions.md D1): pack.sh's initramfs (stage 0, the
# early modules from this kernel) and base disk (squashfs, zstd: the
# Debian root of debs.txt, the module list of modules.txt; no Kubernetes
# binaries) as /dev/vda, a data disk (ext4) as /dev/vdb, and the role's
# set disks (mksets.sh, from the Kubernetes binaries of fetch-assets.sh)
# from /dev/vdc on. The kernel is the 16 KiB-page build
# (scripts/guest/kernel.sh; the default) or, with PAGE_SIZE=4096, Alpine's
# linux-virt (scripts/guest/alpine-kernel.sh). A test PID 1 stands in for
# vk8s-init (which needs bend and zig): it reports the page size, how
# stage 0 mounted the base disk and which disk is which, loads every
# module of /etc/vk8s/modules (ext4 and overlay among them), mounts the
# disks as Plan.disks.v3 does (the data disk at /var/lib/vcluster, each
# set at /sets/<set>, and the sets at /var/lib/vcluster/bin: an overlay,
# or the one set's disk again), runs iptables against nf_tables, runs the
# version command of each asset binary the role has and lists the ones
# it must not have, and, where etcd is, starts it (bbolt sizes its pages
# from the system's) for a put and a get. It also checks that the tools
# docs/GOAL.md section 9 drops are not in the assets, and prints each
# set's and each role's size.
#
# Roles (ROLES, default all of them; CI's assets have no preloaded
# images, so no images set, as when the image cache runs):
#   standalone  node control-plane
#   classic     node control-plane classic
#   worker      node
#   cache       cache
#
# usage: [PAGE_SIZE=16384|4096] [ROLES="standalone ..."] tests/kernel16k_boot.sh KERNEL_DIR ASSETS_BIN
# Needs qemu-system-aarch64, python3, squashfs-tools 4.6+, mkfs.ext4.
# Prints PASS/FAIL lines and, for a role with a FAIL, its boot log; exits
# 1 on any FAIL.
set -uo pipefail
cd "$(dirname "$0")/.."
[ $# = 2 ] || { sed -n 's/^# usage: //p' "$0"; exit 2; }
k=$1 a=$2
page=${PAGE_SIZE:-16384}
roles=${ROLES:-standalone classic worker cache}
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

cat > "$tmp/init" <<'INIT'
#!/bin/busybox sh
bb=/bin/busybox
$bb mount -t proc proc /proc
$bb mount -t sysfs sys /sys
$bb mount -t devtmpfs dev /dev
$bb mkdir -p /tmp /run
echo "vk8s-test: PID 1 started (pid $$)"
echo "vk8s-test: role $VK8S_ROLE sets $VK8S_SETS"
echo "vk8s-test: uname $($bb uname -r) $($bb uname -m)"
echo "vk8s-test: getconf PAGESIZE $(/usr/bin/getconf PAGESIZE)"
echo "vk8s-test: $($bb grep -m1 KernelPageSize /proc/self/smaps | $bb tr -s ' ')"
echo "vk8s-test: assets $($bb grep ' /assets ' /proc/mounts)"
for d in /sys/block/vd*; do echo "vk8s-test: disk ${d##*/} $($bb cat "$d/serial" 2>/dev/null)"; done
ok=0 bad=0
while read -r m; do
  [ -n "$m" ] || continue
  if $bb insmod "$m" 2>/tmp/err; then ok=$((ok + 1)); else bad=$((bad + 1)); echo "vk8s-test: insmod $m: $($bb cat /tmp/err)"; fi
done < /etc/vk8s/modules
echo "vk8s-test: modules loaded $ok failed $bad"
$bb grep -qw ext4 /proc/filesystems && echo "vk8s-test: ext4 registered"
$bb grep -qw overlay /proc/filesystems && echo "vk8s-test: overlay registered"
# the mounts of Plan.disks.v3
mnt() { # mnt FSTYPE SRC DST OPTS
  $bb mkdir -p "$3"
  if $bb mount -t "$1" -o "$4" "$2" "$3" 2>/tmp/err; then echo "vk8s-test: mount $3 ok"
  else echo "vk8s-test: mount $3 failed: $($bb cat /tmp/err)"; fi
}
mnt ext4 /dev/vdb /var/lib/vcluster rw
A=/var/lib/vcluster/bin
n=0 low=""
for s in $(echo "$VK8S_SETS" | $bb tr ',' ' '); do
  l=$(echo cdefghij | $bb cut -c$((n + 1)))
  mnt squashfs "/dev/vd$l" "/sets/$s" ro
  low="$low${low:+:}/sets/$s"; n=$((n + 1))
done
if [ $n = 1 ]; then mnt squashfs /dev/vdc $A ro; else mnt overlay overlay $A "ro,lowerdir=$low"; fi
echo "vk8s-test: bin $($bb grep " $A " /proc/mounts)"
if $bb touch $A/x 2>/dev/null; then echo "vk8s-test: bin is writable"; else echo "vk8s-test: bin is read-only"; fi
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
for b in $($bb ls $A); do echo "vk8s-test: present $b"; done
for b in etcd kine kube-apiserver kube-controller-manager kube-scheduler kubelet \
    containerd runc registry; do
  [ -x $A/$b ] && run $b $A/$b --version
done
# konnectivity-server has no --version flag (unknown flag, rc=1); its
# cobra command prints the usage and exits 0 on --help
[ -x $A/konnectivity-server ] && run konnectivity-server $A/konnectivity-server --help
[ -x $A/etcdctl ] && run etcdctl $A/etcdctl version
[ -x $A/etcdutl ] && run etcdutl $A/etcdutl version
[ -x $A/kubeadm ] && run kubeadm $A/kubeadm version -o short
[ -x $A/kubectl ] && run kubectl $A/kubectl version --client
[ -x $A/ctr ] && run ctr $A/ctr --version
[ -x $A/containerd-shim-runc-v2 ] && run containerd-shim-runc-v2 $A/containerd-shim-runc-v2 -v
for b in $A/cni/bin/*; do [ -x "$b" ] && run "cni/${b##*/}" $bb env CNI_COMMAND=VERSION "$b"; done
if [ -x $A/etcd ]; then
  $bb ip link set lo up
  $A/etcd --data-dir /var/lib/vcluster/etcd --listen-client-urls http://127.0.0.1:2379 \
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
INIT
chmod 755 "$tmp/init"
printf 'not used\n' > "$tmp/vk8s-guest"; chmod 755 "$tmp/vk8s-guest"
printf 'not used\n' > "$tmp/cacert.pem"

# docs/GOAL.md section 9: no tool that nothing in the guest runs
for t in crictl helm kube-proxy vcluster-tunnel pause-image.txt cni/bin/bandwidth cni/bin/firewall; do
  if [ -e "$a/$t" ]; then fail "$t is not in the assets"; else pass "$t is not in the assets"; fi
done

# the base disk: pack.sh with no Kubernetes binaries (as build.sh makes it)
mkdir -p "$tmp/empty-bin"
if scripts/guest/pack.sh "$k" "$tmp/deb.tar" "$tmp/init" "$tmp/vk8s-guest" "$tmp/busybox" "$tmp/cacert.pem" \
    "$tmp/empty-bin" "$tmp/vk8s.cpio" "$tmp/base.img" >"$tmp/pack.log" 2>&1; then
  pass "pack.sh resolves modules.early.txt and modules.txt against the kernel"
else
  fail "pack.sh resolves modules.early.txt and modules.txt against the kernel"; cat "$tmp/pack.log"; exit 1
fi
if scripts/guest/mksets.sh "$a" "$tmp/sets" >"$tmp/sets.log" 2>&1; then
  pass "mksets.sh puts every asset in one role set"; cat "$tmp/sets.log"
else
  fail "mksets.sh puts every asset in one role set"; cat "$tmp/sets.log"; exit 1
fi
MKFS=$(command -v mkfs.ext4 || echo /sbin/mkfs.ext4)
truncate -s 256M "$tmp/data.img"
"$MKFS" -q -F -L vk8s-data "$tmp/data.img" || { echo "FAIL mkfs.ext4 for the data disk"; exit 1; }

# A set's entries (scripts/guest/sets.txt), and a role's sets
# (Assets.role_sets with the image cache running: CI has no images set).
entries() { awk -v s="$1" '!/^#/ && $1 == s { $1 = ""; print }' scripts/guest/sets.txt; }
role_sets() {
  case $1 in
    standalone) echo "node control-plane" ;;
    classic) echo "node control-plane classic" ;;
    worker) echo "node" ;;
    cache) echo "cache" ;;
    *) echo "tests/kernel16k_boot.sh: unknown role $1" >&2; exit 2 ;;
  esac
}
kib() { echo $(( $(wc -c < "$1") / 1024 )); }

echo "--- sizes (KiB): the binaries and the guest root uncompressed; the disks"
echo "binaries $(du -sk "$a" | cut -f1)"
echo "guest root $(du -sk "$tmp/deb.tar" | cut -f1)"
echo "base.img $(kib "$tmp/base.img")"
for i in "$tmp"/sets/*.img; do echo "${i##*/} $(kib "$i")"; done
echo "--- per role (KiB of squashfs a host stores and a VM attaches: base.img + its sets)"
for r in $roles; do
  t=$(kib "$tmp/base.img") line="base $(kib "$tmp/base.img")"
  for s in $(role_sets "$r"); do t=$((t + $(kib "$tmp/sets/$s.img"))); line="$line + $s $(kib "$tmp/sets/$s.img")"; done
  echo "$r: $line = $t"
done

# One boot. The VM is close to bend-vmm's: a PL011 console (ttyAMA0), the
# initramfs, the base disk, the data disk and the set disks (virtio-blk,
# each with its name as serial), the balloon, no network.
# qemu's virt board puts each -device on the next free virtio-mmio
# transport from the highest address down, and Linux names the disks from
# the lowest address up (hw/arm/virt.c, create_virtio_devices), so the
# disks go on the line last first: base becomes /dev/vda, data /dev/vdb
# and the first set /dev/vdc, the order of bend-vmm's --disk list. The
# test checks the serials.
# The CPU is a fixed model, not -cpu max: under TCG, max turns on SME,
# SVE, QARMA5 pointer authentication, WFxT and LPA2, which no Mac guest
# sees, and with it the boot stopped after "PM: genpd: Disabling unused
# power domains" (no /init, no hung-task or lockup report in 25 minutes)
# while the same kernel boots under bend-vmm. Neoverse-N1 (Armv8.2) has
# the 16 KiB translation granule.
boot() { # boot ROLE: the boot log in $tmp/log-ROLE
  local r=$1 sets s i=0 disks=()
  sets=$(role_sets "$r")
  cp --sparse=always "$tmp/data.img" "$tmp/data-$r.img"
  # wanted order: base, data, the sets; each disk is a -drive and a -device
  local want=("base:$tmp/base.img:ro" "data:$tmp/data-$r.img:rw")
  for s in $sets; do want+=("$s:$tmp/sets/$s.img:ro"); done
  for ((i = ${#want[@]} - 1; i >= 0; i--)); do
    local name=${want[i]%%:*} rest=${want[i]#*:}
    local file=${rest%:*} mode=${rest##*:} ro=""
    [ "$mode" = ro ] && ro=",readonly=on"
    disks+=(-drive "if=none,id=$name,file=$file,format=raw$ro" -device "virtio-blk-device,drive=$name,serial=$name")
  done
  timeout 1500 qemu-system-aarch64 -M virt -cpu neoverse-n1 -smp 2 -m 2048 -nographic -no-reboot -nic none \
    -kernel "$k/Image" -initrd "$tmp/vk8s.cpio" \
    -append "console=ttyAMA0 panic=-1 VK8S_ROLE=$r VK8S_SETS=$(echo $sets | tr ' ' ',')" \
    "${disks[@]}" -device virtio-balloon-device,free-page-reporting=on \
    </dev/null >"$tmp/boot.log" 2>&1
  echo "qemu exit $?"
  tr -d '\r' < "$tmp/boot.log" > "$tmp/log-$r"
  rm -f "$tmp/data-$r.img"
}

for r in $roles; do
  echo "=== role $r: sets $(role_sets "$r")"
  boot "$r"
  log=$tmp/log-$r
  echo "--- boot log (kernel lines)"
  grep -E '^\[ *[0-9.]+\] (Booting Linux|Linux version|Memory:|Kernel command line|Run /init|Freeing unused|virtio_balloon|EXT4-fs|squashfs|SQUASHFS|overlayfs)' "$log" | head -40
  grep -E 'stage0:' "$log"
  grep -qE '\] Run /init as init process' "$log" || { echo "--- no /init; the last kernel lines"; grep -E '^\[ *[0-9.]+\]' "$log" | tail -5; }
  echo "--- PID 1"
  grep 'vk8s-test:' "$log"
  echo "---"
  f0=$fails
  has() { grep -qF -- "$1" "$log"; }
  check() { if has "$2"; then pass "$r: $1"; else fail "$r: $1"; fi; }
  check "kernel boots" "Linux version $(ls "$k/lib/modules")"
  check "PID 1 starts" "vk8s-test: PID 1 started (pid 1)"
  check "getconf PAGESIZE is $page" "vk8s-test: getconf PAGESIZE $page"
  check "KernelPageSize is $((page / 1024)) kB" "vk8s-test: KernelPageSize: $((page / 1024)) kB"
  check "/dev/vda is the base disk" "vk8s-test: disk vda base"
  check "/dev/vdb is the data disk" "vk8s-test: disk vdb data"
  i=0
  for s in $(role_sets "$r"); do
    l=$(echo cdefghij | cut -c$((i + 1)))
    check "/dev/vd$l is the $s set" "vk8s-test: disk vd$l $s"
    check "PID 1 mounts the $s set at /sets/$s" "vk8s-test: mount /sets/$s ok"
    i=$((i + 1))
  done
  check "stage 0 mounts the base disk as squashfs, read-only, at /assets" "vk8s-test: assets /dev/vda /assets squashfs ro,"
  if grep -q 'vk8s-test: modules loaded [1-9][0-9]* failed 0$' "$log"; then pass "$r: every module of modules.txt loads"; else fail "$r: every module of modules.txt loads"; fi
  check "ext4 loads late, for the data disk" "vk8s-test: ext4 registered"
  check "overlay loads before the disks" "vk8s-test: overlay registered"
  check "PID 1 mounts the data disk (Plan.disks.v3)" "vk8s-test: mount /var/lib/vcluster ok"
  check "PID 1 mounts the sets at /var/lib/vcluster/bin (Plan.disks.v3)" "vk8s-test: mount /var/lib/vcluster/bin ok"
  if [ "$(role_sets "$r" | wc -w)" -gt 1 ]; then
    check "bin/ is an overlay of the sets" "vk8s-test: bin overlay /var/lib/vcluster/bin overlay ro,"
  else
    check "bin/ is the one set's squashfs" "vk8s-test: bin /dev/vdc /var/lib/vcluster/bin squashfs ro,"
  fi
  check "bin/ is read-only" "vk8s-test: bin is read-only"
  check "virtio_balloon binds the balloon" "vk8s-test: balloon 1 device(s) bound"
  for n in iptables iptables-nat iptables-list conntrack; do check "$n runs" "vk8s-test: run $n ok"; done
  # what the role's sets hold is in bin/; what they do not is not
  mine=""; for s in $(role_sets "$r"); do mine="$mine $(entries "$s")"; done
  for s in $(awk '!/^#/ && NF { print $1 }' scripts/guest/sets.txt); do
    for e in $(entries "$s"); do
      [ -e "$a/$e" ] || continue
      case " $mine " in
        *" $e "*) if grep -qx "vk8s-test: present $e" "$log"; then pass "$r: has $e (set $s)"; else fail "$r: has $e (set $s)"; fi ;;
        *) if grep -qx "vk8s-test: present $e" "$log"; then fail "$r: lacks $e (set $s)"; else pass "$r: lacks $e (set $s)"; fi ;;
      esac
    done
  done
  for n in etcd etcdctl etcdutl kine kube-apiserver kube-controller-manager kube-scheduler kubelet kubeadm kubectl \
      konnectivity-server containerd containerd-shim-runc-v2 runc ctr registry; do
    case " $mine " in *" $n "*) [ -x "$a/$n" ] && check "$n runs" "vk8s-test: run $n ok" ;; esac
  done
  case " $mine " in *" cni "*)
    for b in "$a"/cni/bin/*; do check "cni/${b##*/} runs" "vk8s-test: run cni/${b##*/} ok"; done ;;
  esac
  case " $mine " in *" etcd "*)
    check "etcd-put runs" "vk8s-test: run etcd-put ok"
    check "etcd returns the value" "vk8s-test: run etcd-get ok: page16k" ;;
  esac
  # a page-size problem kills the process (SIGSEGV, SIGBUS, SIGABRT):
  # no run may end on a signal (exit code 128 and above)
  if grep -Eq 'vk8s-test: run [^ ]* rc=(12[89]|1[3-9][0-9]|2[0-9][0-9])' "$log"; then
    fail "$r: no binary dies on a signal"; grep -E 'vk8s-test: run [^ ]* rc=(12[89]|1[3-9][0-9]|2[0-9][0-9])' "$log"
  else pass "$r: no binary dies on a signal"; fi
  check "PID 1 finishes" "vk8s-test: done"
  [ "$fails" = "$f0" ] || { echo "--- full boot log of $r"; cat "$log"; }
done
if [ $fails = 0 ]; then echo "all PASS"; else echo "$fails FAIL"; exit 1; fi
