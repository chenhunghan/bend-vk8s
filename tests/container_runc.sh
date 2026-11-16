#!/usr/bin/env bash
# The runc smoke of src/guest/container.bend (Phase 6 C1/C3; Linux only,
# needs root through sudo). runc is the test's harness, not vk8s's
# runtime here. It renders a node's config.json with
# tests/container_runc.bend, starts it with runc over a busybox root
# filesystem whose /sbin/vk8s-init is the script below, and checks from
# inside: PID 1, the hostname, every capability, no seccomp, the private
# cgroup namespace, each mount and its mode; then it runs PID 1's first
# container steps as rendered (busybox applets, shared mounts, the cgroup
# v2 delegation, the network namespace's sysctls) and checks the cgroups
# they leave: PID 1 in /init.scope, every controller enabled at the root
# and in /kubelet, a pod cgroup under /kubelet that takes a process and
# a memory limit. From outside: the data dir and the share took the
# container's writes, the assets did not.
#
# Needs bend, clang, runc and a static busybox (busybox-static on
# Debian and Ubuntu). Prints PASS/FAIL lines; exits 1 on any FAIL.
set -uo pipefail
cd "$(dirname "$0")/.."

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

tmp=$(mktemp -d)
name="vk8s-smoke-$$"
state="$tmp/runc-state"
cleanup() {
  sudo runc --root "$state" delete -f "$name" >/dev/null 2>&1
  for g in node-1/init.scope node-1/kubelet/pod node-1/kubelet node-1 ""; do
    sudo rmdir "/sys/fs/cgroup/vk8s/smoke/$g" 2>/dev/null
  done
  sudo rmdir /sys/fs/cgroup/vk8s 2>/dev/null
  sudo rm -rf "$tmp"
}
trap cleanup EXIT

for t in runc busybox; do
  command -v "$t" >/dev/null || { echo "FAIL $t not found"; exit 1; }
done
bb=$(command -v busybox)
if ! file -L "$bb" | grep -q 'statically linked'; then echo "FAIL $bb is not static"; exit 1; fi
runc --version | head -1

echo "== render"
if ! bend tests/container_runc.bend -o "$tmp/render" >"$tmp/build.log" 2>&1; then
  cat "$tmp/build.log"; echo "FAIL build tests/container_runc.bend"; exit 1
fi
bundle="$tmp/bundle"; rootfs="$bundle/rootfs"
data="$tmp/data"; share="$tmp/share"; assets="$tmp/assets"
mkdir -p "$rootfs/bin" "$rootfs/sbin" "$data" "$share" "$assets"
cp "$bb" "$rootfs/bin/busybox"
echo marker >"$assets/marker"
"$tmp/render" config smoke node-1 "$rootfs" "$data" "$share" "$assets" VK8S_SMOKE=1 >"$bundle/config.json"
"$tmp/render" steps >"$rootfs/steps.sh"
if command -v jq >/dev/null; then jq . "$bundle/config.json" >/dev/null && pass "config.json is JSON" || fail "config.json is JSON"; fi
grep -q "init.scope/cgroup.procs" "$rootfs/steps.sh" && pass "steps rendered" || fail "steps rendered"

cat >"$rootfs/sbin/vk8s-init" <<'INIT'
#!/bin/busybox sh
/bin/busybox --install -s /bin
export PATH=/bin
t() { n=$1; shift; if "$@"; then echo "PASS $n"; else echo "FAIL $n"; fi; }
ro() { ! touch "$1/.vk8s-ro" 2>/dev/null; }
rw() { touch "$1/.vk8s-rw"; }
fstype() { awk -v d="$1" '$2 == d { t = $3 } END { print t }' /proc/mounts; }
opts() { awk -v d="$1" '$2 == d { o = $4 } END { print o }' /proc/mounts; }
status() { sed -n "s/^$1:[[:space:]]*//p" /proc/self/status; }
shared() { awk '$5 == "/"' /proc/self/mountinfo | grep -q ' shared:'; }

echo "== inside the container"
t "PID 1 is the image's vk8s-init" [ $$ = 1 ]
t "the hostname is the node's" [ "$(hostname)" = node-1 ]
t "PID 1's environment: the kernel's for init, then the host's" [ "$HOME:$TERM:$VK8S_SMOKE" = "/:linux:1" ]
all=$(printf '%016x' $(( (1 << ($(cat /proc/sys/kernel/cap_last_cap) + 1)) - 1 )))
t "every capability is effective ($all)" [ "$(status CapEff)" = "$all" ]
t "every capability is bounding" [ "$(status CapBnd)" = "$all" ]
t "no seccomp filter" [ "$(status Seccomp)" = 0 ]
t "a private cgroup namespace" [ "$(cat /proc/self/cgroup)" = "0::/" ]
t "/run is a tmpfs" [ "$(fstype /run)" = tmpfs ]
t "/tmp is a tmpfs" [ "$(fstype /tmp)" = tmpfs ]
t "/dev is a tmpfs" [ "$(fstype /dev)" = tmpfs ]
t "/proc is procfs" [ "$(fstype /proc)" = proc ]
t "/sys is sysfs, read-write" [ "$(fstype /sys):$(opts /sys | cut -d, -f1)" = sysfs:rw ]
t "/sys/fs/cgroup is cgroup2, read-write" [ "$(fstype /sys/fs/cgroup):$(opts /sys/fs/cgroup | cut -d, -f1)" = cgroup2:rw ]
t "/dev/kmsg is the host's" [ -c /dev/kmsg ]
t "/dev/null works" sh -c 'echo x > /dev/null'
t "/assets holds the assets" [ -f /assets/marker ]
t "/assets is read-only" ro /assets
t "the data dir's bin/ is the assets" [ -f /var/lib/vcluster/bin/marker ]
t "the data dir's bin/ is read-only" ro /var/lib/vcluster/bin
t "/lib/modules is read-only" ro /lib/modules
t "the data dir is writable" rw /var/lib/vcluster
t "the share is writable" rw /var/lib/vk8s-host

echo "== PID 1's first container steps"
. /steps.sh

echo "== after the steps"
t "the root mount is shared" shared
t "PID 1 left the root cgroup for /init.scope" [ "$(cat /proc/self/cgroup)" = "0::/init.scope" ]
t "the root cgroup holds no process" [ -z "$(cat /sys/fs/cgroup/cgroup.procs)" ]
t "the root enables every controller it has" [ "$(cat /sys/fs/cgroup/cgroup.subtree_control)" = "$(cat /sys/fs/cgroup/cgroup.controllers)" ]
t "the root has controllers" [ -n "$(cat /sys/fs/cgroup/cgroup.controllers)" ]
t "/kubelet has every controller of the root" [ "$(cat /sys/fs/cgroup/kubelet/cgroup.controllers)" = "$(cat /sys/fs/cgroup/cgroup.controllers)" ]
t "/kubelet enables every controller it has" [ "$(cat /sys/fs/cgroup/kubelet/cgroup.subtree_control)" = "$(cat /sys/fs/cgroup/kubelet/cgroup.controllers)" ]
t "/kubelet delegates cpu, memory and pids" sh -c 'for c in cpu memory pids; do grep -qw $c /sys/fs/cgroup/kubelet/cgroup.subtree_control || exit 1; done'
mkdir /sys/fs/cgroup/kubelet/pod
t "a pod cgroup under /kubelet takes a memory limit" sh -c 'echo 67108864 > /sys/fs/cgroup/kubelet/pod/memory.max'
t "a pod cgroup under /kubelet takes a process" sh -c 'echo $$ > /sys/fs/cgroup/kubelet/pod/cgroup.procs && grep -qx "0::/kubelet/pod" /proc/self/cgroup'
rmdir /sys/fs/cgroup/kubelet/pod
t "ip_forward in the network namespace" [ "$(cat /proc/sys/net/ipv4/ip_forward)" = 1 ]
t "bridge-nf-call-iptables in the network namespace" [ "$(cat /proc/sys/net/bridge/bridge-nf-call-iptables)" = 1 ]
echo done
INIT
chmod 0755 "$rootfs/sbin/vk8s-init"

echo "== run"
# The bridge netfilter sysctls exist only with br_netfilter loaded (the
# host's job in container mode, as vcluster's docker driver does it).
sudo modprobe br_netfilter || true
out=$(sudo runc --root "$state" run --bundle "$bundle" "$name" 2>&1 </dev/null)
code=$?
echo "$out" | grep '^PASS\|^FAIL'
[ "$code" = 0 ] && pass "runc ran the container to its end" || { fail "runc exit $code"; echo "$out" | tail -20; }
grep -qx done <<<"$out" && pass "PID 1 ran to the end" || fail "PID 1 ran to the end"
fails=$((fails + $(grep -c '^FAIL' <<<"$out")))
[ "$(grep -c '^PASS step:' <<<"$out")" -ge 10 ] && pass "every rendered step ran" || fail "every rendered step ran"

echo "== outside"
[ -f "$data/.vk8s-rw" ] && pass "the host's data dir has the container's write" || fail "the host's data dir has the container's write"
[ -f "$share/.vk8s-rw" ] && pass "the host's share has the container's write" || fail "the host's share has the container's write"
[ ! -e "$assets/.vk8s-ro" ] && pass "the host's assets are unchanged" || fail "the host's assets are unchanged"

if [ "$fails" = 0 ]; then echo "container_runc: OK"; else echo "container_runc: $fails FAIL"; exit 1; fi
