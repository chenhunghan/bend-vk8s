#!/usr/bin/env bash
# Container mode through the node-host VM (docs/ref/explore-linux-hosts.md
# Phase 6 C4; src/cli/nodehost.bend, host/init.bend role node-host,
# host/vk8s.bend Vk8s.nh.*), the macOS path, run on a Linux host with KVM
# (VK8S_NODE_HOST=vm): no root, no runc on the host.
#   vk8s create a --backend container --nodes 1 --gvisor: the node host
#   starts with the gvisor set (docs/GOAL.md section 11),
#   both nodes Ready, CoreDNS available, a pod Running on the worker, the
#   API on 127.0.0.1:16401; on the worker a pod with runtimeClassName
#   gvisor runs busybox's dmesg, whose log must show "Starting gVisor"
#   (docs/GOAL.md section 8), and a runc pod (the default) runs; vk8s create b --backend container: the same
#   node host, API on 127.0.0.1:16402; list shows both running as soon
#   as create returns; pause and resume a, which list shows at once;
#   delete a: the node host keeps running for b; delete b: the node host
#   stops and its directory (its data disk and share) is gone, and no
#   cluster directory or node share is left.
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
# cluster.env's PORT is the node host's forward; the port file holds the
# idle proxy's port in front of it, which the kubeconfig names. On a
# mismatch, print what the cluster recorded.
api_port() {
  local c=$1 want=$2 d="$home/.vk8s/clusters/$1"
  local p; p=$(cat "$d/port" 2>/dev/null)
  grep -qx "PORT=$want" "$d/cluster.env" 2>/dev/null && [ -n "$p" ] \
    && grep -Eq "\"?server\"?: *\"?https://127.0.0.1:$p\b" "$d/kubeconfig.yaml" 2>/dev/null && return 0
  echo "--- $c: port file: $(cat "$d/port" 2>&1 | head -2 | tr '\n' ' ')"
  echo "--- $c: kubeconfig server: $(grep -o '"*server"*: *"*[^",]*' "$d/kubeconfig.yaml" 2>&1 | head -2 | tr '\n' ' ')"
  echo "--- $c: cluster.env:"; cat "$d/cluster.env" 2>&1; ls -la "$d" 2>&1
  return 1
}
# listed NAME STATE: `vk8s list` shows the cluster in that state; the
# table stays in $out. `vk8s list` reads runc's container list, which the
# node host's PID 1 writes to its share before it answers a request, and
# again until the list shows the request's effect (src/cli/nodehost.bend
# Nh.settled, host/init.bend Nhi.settled): the state is right as soon as
# the command that changed it returns. The checks allow 5 s (not the 30 s
# of the periodic list, Nh.list_due, which a missing row had to wait for).
listed() { out=$(V list 2>&1); grep -Eq "(^|[ |])$1[ |]+$2" <<<"$out"; }
# list_shows NAME STATE: listed within 5 s; prints the table, and on a
# failure the list the node host wrote.
list_shows() {
  if until_ok 5 listed "$1" "$2"; then echo "$out"; return 0; fi
  echo "$out"; echo "--- $nh/share/runc-list:"; cat "$nh/share/runc-list" 2>&1
  return 1
}
until_ok() { local end=$(( $(date +%s) + $1 )); shift; until "$@"; do [ "$(date +%s)" -lt "$end" ] || return 1; sleep 2; done; }
# now: seconds with a fraction (perl: macOS date has no %N)
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }
# since T: seconds (one decimal) since `now` gave T
since() { awk -v a="$1" -v b="$(now)" 'BEGIN { printf "%.1f", b - a }'; }
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
  for p in gvisor runc; do echo "--- pod $p"; k a describe pod $p 2>&1 | tail -n 30; k a logs $p 2>&1 | tail -n 10; done
}
done_=0
cleanup() {
  [ $done_ = 1 ] || { diag; V delete a >/dev/null 2>&1; V delete b >/dev/null 2>&1; }
  vmm_alive && kill -9 "$(cat "$nh/vmm.pid")" 2>/dev/null
  # the layer filler create started serves this home's store, which goes now
  pkill -f "$vk8s layers serve" 2>/dev/null
  rm -rf "$home"
}
trap cleanup EXIT

echo "== create a (one worker)"
t0=$(date +%s)
if V create a --backend container --nodes 1 --gvisor --connect=false; then
  pass "create a --backend container --nodes 1 in the node host ($(( $(date +%s) - t0 )) s)"
else
  fail "create a --backend container --nodes 1 in the node host"; echo "$fails FAIL"; exit 1
fi
t "the node host VM runs" vmm_alive
t "a's API is on 127.0.0.1:16401 (the node host's forward, behind the idle proxy the kubeconfig names)" api_port a 16401
t "a records the node host" grep -qx 'NODEHOST=1' "$home/.vk8s/clusters/a/cluster.env"
t "a records gVisor on" grep -qx 'GVISOR=1' "$home/.vk8s/clusters/a/cluster.env"
t "the node host booted with the gvisor set" grep -q 'gvisor' "$nh/sets"
t "two nodes are Ready" k a wait --for=condition=Ready node --all --timeout=900s
t "two nodes" sh -c "[ \"\$('$kubectl' --kubeconfig '$home/.vk8s/clusters/a/kubeconfig.yaml' get nodes --no-headers | wc -l | tr -d ' ')\" = 2 ]"
t "flannel is Ready on both nodes" k a -n kube-flannel rollout status daemonset/kube-flannel-ds --timeout=600s
t "CoreDNS is available" k a -n kube-system wait --for=condition=available deploy/coredns --timeout=900s
k a run smoke --image=registry.k8s.io/pause:3.10.2 --image-pull-policy=IfNotPresent --restart=Never \
  --overrides='{"apiVersion":"v1","spec":{"nodeName":"a-worker-1"}}' >/dev/null
t "a pod is Running on the worker" k a wait --for=jsonpath='{.status.phase}'=Running pod/smoke --timeout=600s
# the shared layer store is the default (tests/nodehost_layers.sh has the
# rest): the up and the join request both carried it
t "the node host's PID 1 wrote that it mounted the layer store" grep -qx 1 "$nh/share/layers"
t "both nodes run the layer snapshotter" test -s "$nh/share/clusters/a/share/logs/snapshotter.log" -a -s "$nh/share/clusters/a/nodes/worker-1/share/logs/snapshotter.log"

echo "== gVisor in a node container of the node host"
gvisor_image=docker.io/library/busybox:1.36
handler() { [ "$(k a get runtimeclass gvisor -o 'jsonpath={.handler}' 2>/dev/null)" = runsc ]; }
t "the gvisor RuntimeClass exists, handler runsc" until_ok 300 handler
k a run gvisor --image="$gvisor_image" --restart=Never \
  --overrides="{\"apiVersion\":\"v1\",\"spec\":{\"nodeName\":\"a-worker-1\",\"runtimeClassName\":\"gvisor\",\"containers\":[{\"name\":\"gvisor\",\"image\":\"$gvisor_image\",\"command\":[\"dmesg\"]}]}}" >/dev/null
k a run runc --image="$gvisor_image" --restart=Never \
  --overrides="{\"apiVersion\":\"v1\",\"spec\":{\"nodeName\":\"a-worker-1\",\"containers\":[{\"name\":\"runc\",\"image\":\"$gvisor_image\",\"command\":[\"uname\",\"-r\"]}]}}" >/dev/null
t "the gVisor pod Succeeded" k a wait --for=jsonpath='{.status.phase}'=Succeeded pod/gvisor --timeout=600s
glog=$(k a logs gvisor 2>&1); echo "$glog" | head -n 5
t "the gVisor pod's dmesg shows Starting gVisor" grep -q 'Starting gVisor' <<<"$glog"
t "the runc pod Succeeded" k a wait --for=jsonpath='{.status.phase}'=Succeeded pod/runc --timeout=600s
echo "runc pod: $(k a logs runc 2>&1)"
t "runc stays the default: the pod names no RuntimeClass" test -z "$(k a get pod runc -o 'jsonpath={.spec.runtimeClassName}' 2>&1)"

echo "== create b (no worker), in the same node host"
pid0=$(cat "$nh/vmm.pid" 2>/dev/null)
t "create b" V create b --backend container --connect=false
t "list shows b running as soon as create returns" list_shows b running
t "list shows a running" list_shows a running
t "b reuses the node host" test "$(cat "$nh/vmm.pid" 2>/dev/null)" = "$pid0"
t "b's API is on 127.0.0.1:16402 (the node host's forward, behind the idle proxy the kubeconfig names)" api_port b 16402
t "b's node is Ready" k b wait --for=condition=Ready node --all --timeout=900s

echo "== pause and resume a"
t "pause a" V pause a
t "list shows a paused" list_shows a paused
t "resume a" V resume a
t "list shows a running again" list_shows a running
t "a answers again" k a get --raw /readyz

[ $fails = 0 ] || diag

echo "== delete"
td0=$(now)
t "delete a" V delete a
echo "MEASURE nodehost-smoke delete_s=$(since "$td0") nodes=2 (a; the node host stays)"
t "a's directory is gone" test ! -e "$home/.vk8s/clusters/a"
t "a's node shares are gone" test ! -e "$nh/share/clusters/a"
t "the node host still runs for b" vmm_alive
t "b still answers" k b get --raw /readyz
td0=$(now)
t "delete b" V delete b
echo "MEASURE nodehost-smoke delete_s=$(since "$td0") nodes=1 (b; the node host VM stops and its directory goes)"
vmm_gone() { ! { [ -n "$pid0" ] && kill -0 "$pid0" 2>/dev/null; }; }
t "the node host stopped with the last container cluster" vmm_gone
ls -la "$home/.vk8s"
t "the node host's directory (its data disk and share) is gone" test ! -e "$nh" -a ! -e "$nh.gone"
t "no cluster directory is left" sh -c "[ -z \"\$(ls -A '$home/.vk8s/clusters' 2>/dev/null)\" ]"
done_=1
if [ $fails = 0 ]; then echo "nodehost_smoke: OK"; else echo "nodehost_smoke: $fails FAIL"; exit 1; fi
