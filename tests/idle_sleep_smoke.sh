#!/usr/bin/env bash
# Sleep when idle end to end, in container mode on a Linux host
# (docs/GOAL.md section 10; src/cli/idle.bend, host/idle_proxy.bend):
#   vk8s create --backend container --idle-sleep 45s; the kubeconfig names
#   the idle proxy on 127.0.0.1; a pod Running; then no API traffic: the
#   nodes pause (runc state paused, the cgroup freezer); kubectl through
#   the forward resumes them and answers; the pod is still Running, the
#   same pod with no restart, the node Ready, and no new eviction event
#   (none that was not there before the first sleep), also
#   a minute after the wake (past the node monitor grace period); a second
#   sleep, then `vk8s resume`; `vk8s delete` stops the proxy.
#
# usage: tests/idle_sleep_smoke.sh VK8S ASSETS_DIR KUBECTL
# Needs sudo, runc, cpio, iproute2, iptables. Prints PASS/FAIL lines;
# exits 1 on any FAIL.
set -uo pipefail
cd "$(dirname "$0")/.."
[ $# = 3 ] || { sed -n 's/^# usage: //p' "$0"; exit 2; }
vk8s=$(realpath "$1") assets=$(realpath "$2") kubectl=$(realpath "$3")
name=${NAME:-idle-smoke}
home=$(mktemp -d)
dir=$home/.vk8s/clusters/$name
kc=$dir/kubeconfig.yaml
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
t() { local n=$1; shift; if "$@"; then pass "$n"; else fail "$n"; fi; }
V() { sudo timeout 2400 env HOME="$home" KUBECONFIG="$home/.kube/config" VK8S_ASSETS="$assets" PATH="$PATH" "$vk8s" "$@"; }
k() { sudo "$kubectl" --kubeconfig "$kc" --request-timeout=180s "$@"; }
state() { sudo runc --root /run/vk8s/runc state "vk8s-$name-0" 2>/dev/null | sed -n 's/.*"status": "\([a-z]*\)".*/\1/p'; }
# wait_state S SECONDS: the control plane container reaches state S
wait_state() { local end=$(( $(date +%s) + $2 )); until [ "$(state)" = "$1" ]; do [ "$(date +%s)" -lt "$end" ] || return 1; sleep 2; done; }
diag() {
  echo "--- idle.log"; sudo cat "$dir/idle.log" 2>/dev/null | tail -n 40
  for f in "$dir"/share/logs/*.log; do sudo test -f "$f" || continue; echo "--- $f"; sudo tail -n 30 "$f"; done
  k get nodes -o wide 2>&1; k get pods -A -o wide 2>&1; k get events -A --sort-by=.lastTimestamp 2>&1 | tail -n 40
}
done_=0
cleanup() {
  [ $done_ = 1 ] || { diag; V delete "$name" >/dev/null 2>&1; }
  # the layer filler create started serves this home's store: not the next test's
  sudo pkill -f "$vk8s layers serve" 2>/dev/null
  sudo rm -rf "$home"
}
trap cleanup EXIT

echo "== create (--idle-sleep 45s)"
if V create "$name" --backend container --idle-sleep 45s --connect=false; then pass "create --idle-sleep 45s"; else
  fail "create --idle-sleep 45s"; echo "$fails FAIL"; exit 1; fi
t "cluster.env records IDLE_SLEEP=45s" sudo grep -qx 'IDLE_SLEEP=45s' "$dir/cluster.env"
port=$(sudo cat "$dir/port")
t "the kubeconfig names the idle proxy on 127.0.0.1" sudo grep -q "server: https://127.0.0.1:$port" "$kc"
pid=$(sudo cat "$dir/idle.pid")
t "the idle proxy runs" sudo kill -0 "$pid"
t "the node is Ready" k wait --for=condition=Ready node --all --timeout=900s
k run idle-pod --image=registry.k8s.io/pause:3.10.2 --image-pull-policy=IfNotPresent --restart=Never >/dev/null
t "a pod is Running" k wait --for=jsonpath='{.status.phase}'=Running pod/idle-pod --timeout=600s
uid=$(k get pod idle-pod -o 'jsonpath={.metadata.uid}')
# The events that name an eviction (a pod Evicted, TaintManagerEviction,
# the kubelet's EvictionThresholdMet), one line each, led by the time the
# event happened (not the time it was written: main's run 45773243229
# failed on two "Cancelling deletion" events of the boot, the not-ready
# taint leaving the new node, that were written a moment after the list
# of events before the sleep was read). The check after each wake fails
# on an event that happened after the mark below, an object made now
# whose creation time is the API server's clock.
evicts() {
  k get events -A -o 'jsonpath={range .items[*]}{.firstTimestamp}{.eventTime} {.metadata.namespace}/{.metadata.name} x{.count} {.reason} {.involvedObject.kind}/{.involvedObject.name}: {.message}{"\n"}{end}' 2>/dev/null | grep -i 'evict'
}
k create configmap idle-mark >/dev/null
mark=$(k get configmap idle-mark -o 'jsonpath={.metadata.creationTimestamp}')
t "the mark has the API server's time" test -n "$mark"
evict0=$(evicts)
[ -z "$evict0" ] || printf '%s\n' "$evict0" | sed 's/^/info: before the sleep: /'

echo "== sleep: no API traffic for 45 s"
t "the control plane container is paused (cgroup freezer)" wait_state paused 240
out=$(V list 2>&1); echo "$out"
t "the proxy logged the pause" sudo grep -q 'pausing' "$dir/idle.log"

echo "== wake: kubectl through the forward"
t0=$(date +%s)
t "kubectl answers through the sleeping cluster's forward" k get pods -o wide
echo "first request after sleep: $(( $(date +%s) - t0 )) s"
t "the control plane container runs again" test "$(state)" = running
t "the proxy logged the resume" sudo grep -q 'resuming' "$dir/idle.log"
check_pod() {
  t "$1: the pod is Running" test "$(k get pod idle-pod -o 'jsonpath={.status.phase}')" = Running
  t "$1: the same pod" test "$(k get pod idle-pod -o 'jsonpath={.metadata.uid}')" = "$uid"
  t "$1: no restart" test "$(k get pod idle-pod -o 'jsonpath={.status.containerStatuses[0].restartCount}')" = 0
  t "$1: the node is Ready" k wait --for=condition=Ready node --all --timeout=120s
  local now new_
  now=$(evicts)
  new_=$(printf '%s\n' "$now" | awk -v m="$mark" 'NF && $1 > m')
  t "$1: no eviction" test -z "$new_"
  [ -z "$new_" ] || printf '%s\n' "$new_" | sed "s/^/  $1: new event: /"
  t "$1: no NoExecute taint" test -z "$(k get nodes -o 'jsonpath={.items[*].spec.taints[?(@.effect=="NoExecute")].key}')"
}
check_pod "after the wake"
# keep a watch open, so the cluster stays awake past the node monitor's
# grace period (kube-controller-manager restarted on wake)
k get pods -w --request-timeout=75s >/dev/null 2>&1
check_pod "a minute after the wake"

echo "== a second sleep, then vk8s resume"
t "the cluster sleeps again" wait_state paused 240
t "vk8s resume" V resume "$name"
t "the control plane container runs" test "$(state)" = running
check_pod "after vk8s resume"

# the logs and events go with the cluster: show them before the delete
[ $fails = 0 ] || { echo "== diagnostics"; diag; }

echo "== delete"
t "delete" V delete "$name"
t "the idle proxy stopped" sh -c "! sudo kill -0 $pid 2>/dev/null"
t "nothing listens on the forward" sh -c "! (exec 3<>/dev/tcp/127.0.0.1/$port) 2>/dev/null"
done_=1
if [ $fails = 0 ]; then echo "idle_sleep_smoke: OK"; else echo "idle_sleep_smoke: $fails FAIL"; exit 1; fi
