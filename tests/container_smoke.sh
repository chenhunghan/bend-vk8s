#!/usr/bin/env bash
# Container mode end to end on a Linux host (docs/ref/explore-linux-hosts.md
# Phase 6 C2; src/cli/ctr.bend, host/vk8s.bend Vk8s.ctr.*):
#   vk8s create --backend container with one worker; both nodes Ready,
#   CoreDNS available, a pod Running on the worker; on the worker, a pod
#   with runtimeClassName gvisor runs busybox's dmesg, whose log must show
#   "Starting gVisor" (runsc's own boot log; docs/GOAL.md section 8), and
#   a runc pod (the default) prints the host's kernel release; `vk8s list`
#   shows the cluster running; then `vk8s delete`, after which the host holds none
#   of it: no runc container, network namespace, bridge or veth, tagged
#   iptables rule, cgroup, assets mount, loop device or cluster directory.
#
# usage: tests/container_smoke.sh VK8S ASSETS_DIR KUBECTL
#   VK8S        the Linux host binary (scripts/build-linux.sh)
#   ASSETS_DIR  the guest assets (vk8s.cpio, base.img, <set>.img; scripts/guest/build.sh)
#   KUBECTL     a kubectl for this host
# Needs sudo (vk8s runs as root), runc, cpio, iproute2, iptables. Prints
# PASS/FAIL lines; exits 1 on any FAIL.
set -uo pipefail
cd "$(dirname "$0")/.."
[ $# = 3 ] || { sed -n 's/^# usage: //p' "$0"; exit 2; }
vk8s=$(realpath "$1") assets=$(realpath "$2") kubectl=$(realpath "$3")
name=${NAME:-ctr-smoke}
home=$(mktemp -d)
dir=$home/.vk8s/clusters/$name
kc=$dir/kubeconfig.yaml
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
t() { local n=$1; shift; if "$@"; then pass "$n"; else fail "$n"; fi; }
absent() { ! grep -q -- "$1" <<<"$2"; }
V() { sudo timeout 2400 env HOME="$home" KUBECONFIG="$home/.kube/config" VK8S_ASSETS="$assets" PATH="$PATH" "$vk8s" "$@"; }
k() { sudo "$kubectl" --kubeconfig "$kc" --request-timeout=30s "$@"; }
diag() {
  echo "--- diagnostics"
  sudo tail -n 60 "$dir/console.log" 2>/dev/null
  for f in "$dir"/share/logs/*.log "$dir"/nodes/*/share/logs/*.log "$dir"/nodes/*/console.log; do
    sudo test -f "$f" || continue; echo "--- $f"; sudo tail -n 30 "$f"
  done
  k get nodes -o wide 2>&1; k get pods -A -o wide 2>&1; k get events -A --sort-by=.lastTimestamp 2>&1 | tail -n 40
  echo "--- flannel"; k -n kube-flannel logs -l app=flannel --all-containers --tail=30 --prefix 2>&1
  k -n kube-flannel logs -l app=flannel --tail=30 --prefix --previous 2>&1
  echo "--- pod smoke"; k describe pod smoke 2>&1 | tail -n 30
  for p in gvisor runc; do echo "--- pod $p"; k describe pod $p 2>&1 | tail -n 30; k logs $p 2>&1 | tail -n 10; done
  k get runtimeclass -o wide 2>&1
  sudo runc --root /run/vk8s/runc list 2>&1; ip -br link 2>&1; sudo ip netns list 2>&1
}
done_=0
cleanup() {
  [ $done_ = 1 ] || { diag; V delete "$name" >/dev/null 2>&1; }
  sudo rm -rf "$home"
}
trap cleanup EXIT

uname -a; runc --version | head -1; cat /sys/fs/cgroup/cgroup.controllers
echo "== create"
t0=$(date +%s)
if V create "$name" --backend container --nodes 1 --connect=false; then
  pass "create --backend container --nodes 1 ($(( $(date +%s) - t0 )) s)"
else
  fail "create --backend container --nodes 1"; echo "$fails FAIL"; exit 1
fi
t "the control plane is a running runc container" sh -c "sudo runc --root /run/vk8s/runc state vk8s-$name-0 | grep -q '\"status\": \"running\"'"
t "the worker is a running runc container" sh -c "sudo runc --root /run/vk8s/runc state vk8s-$name-1 | grep -q '\"status\": \"running\"'"
t "the nodes' network namespaces exist" sh -c "sudo ip netns list | grep -q 'vk8s-$name-0' && sudo ip netns list | grep -q 'vk8s-$name-1'"
# iptables -S quotes a comment with a colon: --comment "vk8s:NAME"
t "the cluster's MASQUERADE rule is tagged" sh -c "sudo iptables -t nat -S POSTROUTING | grep -- '-j MASQUERADE' | grep -q -- '--comment \"\\?vk8s:$name\"\\?'"
# the per-role sets: base.img and each set squashfs read-only, joined in a
# read-only overlay at <dir>/assets (Ctr.mount_overlay)
t "the assets are mounted read-only" sh -c "grep -q ' $dir/assets overlay ro[, ]' /proc/mounts && grep -q ' $dir/base squashfs ro[, ]' /proc/mounts"

echo "== nodes and pods"
t "two nodes are Ready" k wait --for=condition=Ready node --all --timeout=900s
t "two nodes" sh -c "[ \"\$(sudo '$kubectl' --kubeconfig '$kc' get nodes --no-headers | wc -l)\" = 2 ]"
t "flannel is Ready on both nodes" k -n kube-flannel rollout status daemonset/kube-flannel-ds --timeout=600s
t "CoreDNS is available" k -n kube-system wait --for=condition=available deploy/coredns --timeout=900s
k run smoke --image=registry.k8s.io/pause:3.10.2 --image-pull-policy=IfNotPresent --restart=Never \
  --overrides="{\"apiVersion\":\"v1\",\"spec\":{\"nodeName\":\"$name-worker-1\"}}" >/dev/null
t "a pod is Running on the worker" k wait --for=jsonpath='{.status.phase}'=Running pod/smoke --timeout=600s

echo "== gVisor (the opt-in gvisor RuntimeClass, handler runsc)"
gvisor_image=docker.io/library/busybox:1.36
handler() { [ "$(k get runtimeclass gvisor -o 'jsonpath={.handler}' 2>/dev/null)" = runsc ]; }
until_ok() { local end=$(( $(date +%s) + $1 )); shift; until "$@"; do [ "$(date +%s)" -lt "$end" ] || return 1; sleep 2; done; }
t "the gvisor RuntimeClass exists, handler runsc" until_ok 300 handler
# pod NAME RUNTIMECLASS COMMAND...: a busybox pod on the worker, run once
pod() {
  local n=$1 rc=$2; shift 2
  local cmd; cmd=$(printf '"%s",' "$@"); cmd=${cmd%,}
  k run "$n" --image="$gvisor_image" --restart=Never --overrides="{\"apiVersion\":\"v1\",\"spec\":{\"nodeName\":\"$name-worker-1\",$rc\"containers\":[{\"name\":\"$n\",\"image\":\"$gvisor_image\",\"command\":[$cmd]}]}}" >/dev/null
}
pod gvisor '"runtimeClassName":"gvisor",' dmesg
pod runc '' uname -r
t "the gVisor pod Succeeded" k wait --for=jsonpath='{.status.phase}'=Succeeded pod/gvisor --timeout=600s
glog=$(k logs gvisor 2>&1); echo "$glog" | head -n 5
t "the gVisor pod's dmesg shows Starting gVisor" grep -q 'Starting gVisor' <<<"$glog"
t "the runc pod Succeeded" k wait --for=jsonpath='{.status.phase}'=Succeeded pod/runc --timeout=600s
rlog=$(k logs runc 2>&1); echo "runc pod: $rlog, host: $(uname -r)"
t "runc stays the default: the pod names no RuntimeClass" test -z "$(k get pod runc -o 'jsonpath={.spec.runtimeClassName}' 2>&1)"
t "the runc pod runs on the host's kernel, not gVisor's" test "$rlog" = "$(uname -r)"
t "the first pod still runs" k wait --for=jsonpath='{.status.phase}'=Running pod/smoke --timeout=60s
out=$(V list 2>&1); echo "$out"
t "list shows the cluster running" grep -q "$name.*running" <<<"$out"
k get nodes -o wide; k get pods -A -o wide
# before delete, while the logs are there
[ $fails = 0 ] || diag

echo "== delete"
t "delete" V delete "$name"
t "no runc container is left" sh -c "! sudo runc --root /run/vk8s/runc list -q 2>/dev/null | grep -q 'vk8s-$name-'"
t "no network namespace is left" sh -c "! sudo ip netns list | grep -q 'vk8s-$name-'"
t "no vk8s link is left" sh -c "! ip -o link | grep -q ' vk8s'"
t "no tagged nat rule is left" sh -c "! sudo iptables -t nat -S | grep -q -- 'vk8s:$name'"
t "no tagged filter rule is left" sh -c "! sudo iptables -t filter -S | grep -q -- 'vk8s:$name'"
t "no cgroup is left" test ! -e "/sys/fs/cgroup/vk8s/$name"
t "no mount is left" sh -c "! grep -q '$dir' /proc/mounts"
t "no loop device holds the assets" sh -c "! sudo losetup -a | grep -q '$assets/'"
t "the cluster's directory is gone" sudo test ! -e "$dir"
out=$(V list 2>&1)
t "list no longer shows it" absent "$name" "$out"
done_=1
if [ $fails = 0 ]; then echo "container_smoke: OK"; else echo "container_smoke: $fails FAIL"; exit 1; fi
