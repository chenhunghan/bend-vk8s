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
#   A second cluster, from another $HOME and created at the same time
#   (docs/ref/review-bend-vk8s-pr-49.md findings 1-2), takes another slot
#   of the host's registry (/run/vk8s/slots), cannot reach the first's
#   nodes nor they its own, and its delete leaves the first's bridge.
#   Create with assets that lack the sets stops at the sets check
#   (review-bend-vk8s-pr-48.md finding 1: create fetches its role sets).
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
name2=$name-b
home=$(mktemp -d)
home2=$(mktemp -d)
dir=$home/.vk8s/clusters/$name
dir2=$home2/.vk8s/clusters/$name2
kc=$dir/kubeconfig.yaml
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
t() { local n=$1; shift; if "$@"; then pass "$n"; else fail "$n"; fi; }
absent() { ! grep -q -- "$1" <<<"$2"; }
V() { sudo timeout 2400 env HOME="$home" KUBECONFIG="$home/.kube/config" VK8S_ASSETS="$assets" PATH="$PATH" "$vk8s" "$@"; }
V2() { sudo timeout 2400 env HOME="$home2" KUBECONFIG="$home2/.kube/config" VK8S_ASSETS="$assets" PATH="$PATH" "$vk8s" "$@"; }
k() { sudo "$kubectl" --kubeconfig "$kc" --request-timeout=30s "$@"; }
# slot DIR: the cluster's SLOT= from its cluster.env
slot() { sudo sed -n 's/^SLOT=//p' "$1/cluster.env"; }
# tcp NETNS IP PORT: a connection from the network namespace; 124 when it
# times out (dropped), 1 when it is refused, 0 when it opens
tcp() { sudo ip netns exec "$1" timeout 5 bash -c "exec 3<>/dev/tcp/$2/$3" 2>/dev/null; }
dropped() { local rc=0; tcp "$@" || rc=$?; [ $rc = 124 ]; }
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
  [ $done_ = 1 ] || { diag; V2 delete "$name2" >/dev/null 2>&1; V delete "$name" >/dev/null 2>&1; }
  sudo rm -rf "$home" "$home2"
}
trap cleanup EXIT

uname -a; runc --version | head -1; cat /sys/fs/cgroup/cgroup.controllers
echo "== create without the sets"
nosets=$(mktemp -d)
ln -s "$assets/vk8s.cpio" "$assets/base.img" "$nosets/"
out=$(sudo env HOME="$home" VK8S_ASSETS="$nosets" PATH="$PATH" "$vk8s" create nosets --backend container --connect=false 2>&1); echo "$out"
t "create checks the control plane's sets first" grep -q 'lack a set of node, control-plane' <<<"$out"
t "and changes nothing" sudo test ! -e "$home/.vk8s/clusters/nosets"
rm -rf "$nosets"

echo "== create (two clusters from two homes at once)"
t0=$(date +%s)
V2 create "$name2" --backend container --connect=false >"$home2.log" 2>&1 &
pid2=$!
if V create "$name" --backend container --nodes 1 --connect=false; then
  pass "create --backend container --nodes 1 ($(( $(date +%s) - t0 )) s)"
else
  fail "create --backend container --nodes 1"; wait $pid2; cat "$home2.log"; echo "$fails FAIL"; exit 1
fi
rc2=0; wait $pid2 || rc2=$?; cat "$home2.log"; rm -f "$home2.log"
t "a second cluster from another home, created at the same time ($(( $(date +%s) - t0 )) s)" test $rc2 = 0
k1=$(slot "$dir"); k2=$(slot "$dir2"); echo "slots: $name $k1, $name2 $k2"
t "the two clusters hold different slots" test -n "$k1" -a -n "$k2" -a "$k1" != "$k2"
t "the host's registry gives each slot to its cluster" \
  sh -c "[ \"\$(sudo cat /run/vk8s/slots/$k1/owner)\" = '$dir' ] && [ \"\$(sudo cat /run/vk8s/slots/$k2/owner)\" = '$dir2' ]"
t "the first cluster's bridge drops traffic to the other vk8s bridges" \
  sh -c "sudo iptables -t filter -S FORWARD | grep -- '-i vk8sbr$k1 -o vk8sbr+' | grep -q -- '-j DROP'"
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

echo "== isolation between the two clusters"
t "a worker reaches its own control plane's API" tcp "vk8s-$name-1" "10.10.$k1.2" 6443
t "the second cluster's node reaches its own API" tcp "vk8s-$name2-0" "10.10.$k2.2" 6443
t "the second cluster's node cannot reach the first's API (dropped)" dropped "vk8s-$name2-0" "10.10.$k1.2" 6443
t "the first cluster's worker cannot reach the second's API (dropped)" dropped "vk8s-$name-1" "10.10.$k2.2" 6443
t "delete of the second cluster" V2 delete "$name2"
t "its slot is free again" sudo test ! -e "/run/vk8s/slots/$k2"
t "its bridge is gone" sh -c "! ip link show dev vk8sbr$k2 >/dev/null 2>&1"
t "the first cluster's bridge stays" ip link show dev "vk8sbr$k1"
t "no rule of the second cluster is left" sh -c "! sudo iptables -t filter -S | grep -q -- 'vk8s:$name2[\" ]'"
t "the first cluster still serves" k get --raw /readyz

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
t "its slot is free again" sudo test ! -e "/run/vk8s/slots/$k1"
out=$(V list 2>&1)
t "list no longer shows it" absent "$name" "$out"
done_=1
if [ $fails = 0 ]; then echo "container_smoke: OK"; else echo "container_smoke: $fails FAIL"; exit 1; fi
