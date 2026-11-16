#!/usr/bin/env bash
# Container mode through the node-host VM (docs/ref/explore-linux-hosts.md
# Phase 6 C4; src/cli/nodehost.bend, host/init.bend role node-host,
# host/vk8s.bend Vk8s.nh.*), the macOS path, run on a Linux host with KVM
# (VK8S_NODE_HOST=vm): no root, no runc on the host.
#   vk8s create a --backend container --nodes 1: the node host starts,
#   both nodes Ready, CoreDNS available, a pod Running on the worker, the
#   API on 127.0.0.1:16401; vk8s create b --backend container: the same
#   node host, API on 127.0.0.1:16402; list shows both running; pause and
#   resume a; delete a: the node host keeps running for b; delete b: the
#   node host stops, and no cluster directory or node share is left.
#
# usage: tests/nodehost_smoke.sh VK8S ASSETS_DIR KUBECTL
#   VK8S        the host binary (scripts/build-linux.sh)
#   ASSETS_DIR  the guest assets with base.img and the sets (scripts/guest/build.sh)
#   KUBECTL     a kubectl for this host
# Needs /dev/kvm and nc (netcat-openbsd). Prints PASS/FAIL lines; exits 1
# on any FAIL.
set -uo pipefail
cd "$(dirname "$0")/.."
[ $# = 3 ] || { sed -n 's/^# usage: //p' "$0"; exit 2; }
vk8s=$(realpath "$1") assets=$(realpath "$2") kubectl=$(realpath "$3")
home=$(mktemp -d)
nh=$home/.vk8s/nodehost
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
t() { local n=$1; shift; if "$@"; then pass "$n"; else fail "$n"; fi; }
V() { timeout 2400 env HOME="$home" KUBECONFIG="$home/.kube/config" VK8S_ASSETS="$assets" VK8S_NODE_HOST=vm "$vk8s" "$@"; }
k() { local c=$1; shift; "$kubectl" --kubeconfig "$home/.vk8s/clusters/$c/kubeconfig.yaml" --request-timeout=30s "$@"; }
vmm_alive() { local p; p=$(cat "$nh/vmm.pid" 2>/dev/null) && [ -n "$p" ] && kill -0 "$p" 2>/dev/null; }
diag() {
  echo "--- diagnostics"
  tail -n 120 "$nh/console.log" 2>/dev/null
  tail -n 20 "$nh/vmm.log" 2>/dev/null
  for f in "$nh"/share/logs/*.log "$nh"/share/clusters/*/share/logs/*.log "$nh"/share/clusters/*/nodes/*/share/logs/*.log; do
    [ -f "$f" ] || continue; echo "--- $f"; tail -n 30 "$f"
  done
  cat "$nh/share/runc-list" 2>/dev/null
  for c in a b; do
    [ -f "$home/.vk8s/clusters/$c/kubeconfig.yaml" ] || continue
    k "$c" get nodes -o wide 2>&1; k "$c" get pods -A -o wide 2>&1
    k "$c" get events -A --sort-by=.lastTimestamp 2>&1 | tail -n 30
  done
}
done_=0
cleanup() {
  [ $done_ = 1 ] || { diag; V delete a >/dev/null 2>&1; V delete b >/dev/null 2>&1; }
  vmm_alive && kill -9 "$(cat "$nh/vmm.pid")" 2>/dev/null
  rm -rf "$home"
}
trap cleanup EXIT

echo "== create a (one worker)"
t0=$(date +%s)
if V create a --backend container --nodes 1 --connect=false; then
  pass "create a --backend container --nodes 1 in the node host ($(( $(date +%s) - t0 )) s)"
else
  fail "create a --backend container --nodes 1 in the node host"; echo "$fails FAIL"; exit 1
fi
t "the node host VM runs" vmm_alive
t "a's API is on 127.0.0.1:16401" grep -q 'server: https://127.0.0.1:16401' "$home/.vk8s/clusters/a/kubeconfig.yaml"
t "a records the node host" grep -qx 'NODEHOST=1' "$home/.vk8s/clusters/a/cluster.env"
t "two nodes are Ready" k a wait --for=condition=Ready node --all --timeout=900s
t "two nodes" sh -c "[ \"\$('$kubectl' --kubeconfig '$home/.vk8s/clusters/a/kubeconfig.yaml' get nodes --no-headers | wc -l)\" = 2 ]"
t "flannel is Ready on both nodes" k a -n kube-flannel rollout status daemonset/kube-flannel-ds --timeout=600s
t "CoreDNS is available" k a -n kube-system wait --for=condition=available deploy/coredns --timeout=900s
k a run smoke --image=registry.k8s.io/pause:3.10.2 --image-pull-policy=IfNotPresent --restart=Never \
  --overrides='{"apiVersion":"v1","spec":{"nodeName":"a-worker-1"}}' >/dev/null
t "a pod is Running on the worker" k a wait --for=jsonpath='{.status.phase}'=Running pod/smoke --timeout=600s

echo "== create b (no worker), in the same node host"
pid0=$(cat "$nh/vmm.pid" 2>/dev/null)
t "create b" V create b --backend container --connect=false
t "b reuses the node host" test "$(cat "$nh/vmm.pid" 2>/dev/null)" = "$pid0"
t "b's API is on 127.0.0.1:16402" grep -q 'server: https://127.0.0.1:16402' "$home/.vk8s/clusters/b/kubeconfig.yaml"
t "b's node is Ready" k b wait --for=condition=Ready node --all --timeout=900s
sleep 6
out=$(V list 2>&1); echo "$out"
t "list shows a running" grep -Eq "(^|[ |])a[ |]+running" <<<"$out"
t "list shows b running" grep -Eq "(^|[ |])b[ |]+running" <<<"$out"

echo "== pause and resume a"
t "pause a" V pause a
sleep 6
out=$(V list 2>&1); echo "$out"
t "list shows a paused" grep -Eq "(^|[ |])a[ |]+paused" <<<"$out"
t "resume a" V resume a
t "a answers again" k a get --raw /readyz

[ $fails = 0 ] || diag

echo "== delete"
t "delete a" V delete a
t "a's directory is gone" test ! -e "$home/.vk8s/clusters/a"
t "a's node shares are gone" test ! -e "$nh/share/clusters/a"
t "the node host still runs for b" vmm_alive
t "b still answers" k b get --raw /readyz
t "delete b" V delete b
sleep 2
t "the node host stopped with the last container cluster" sh -c "! { p=\$(cat '$nh/vmm.pid' 2>/dev/null) && [ -n \"\$p\" ] && kill -0 \"\$p\" 2>/dev/null; }"
t "no cluster directory is left" sh -c "[ -z \"\$(ls -A '$home/.vk8s/clusters' 2>/dev/null)\" ]"
done_=1
if [ $fails = 0 ]; then echo "nodehost_smoke: OK"; else echo "nodehost_smoke: $fails FAIL"; exit 1; fi
