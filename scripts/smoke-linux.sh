#!/usr/bin/env bash
# Smoke test of the VM backend on a Linux KVM host (docs/GOAL.md section 8,
# docs/ref/explore-linux-hosts.md Phase 3), arm64 or x86_64:
#   1. vk8s create (one worker), every node Ready, a pod Running
#   1b. a pod with runtimeClassName: gvisor on the worker (docs/GOAL.md
#      section 8): it runs dmesg, whose log must show "Starting gVisor"
#      (runsc's own boot log, not the guest kernel's); then it is deleted
#   1b'. NetworkPolicy across the nodes (tests/netpol_e2e.sh): a deny-all
#      ingress policy makes the worker's pod unreachable from the control
#      plane's, an allow policy restores it; kube-router's idle memory
#      and CPU on the worker are measured
#   1c. vk8s cache status shows docker.io's size (the gVisor image came
#      through the cache); vk8s cache prune docker.io empties it, prints
#      what it freed, and the registry answers again
#   2. vk8s snapshot create (VM format), vk8s delete
#   3. vk8s restore from the snapshot: the nodes Ready again and the pod
#      Running again (it was on the control plane, whose disk the snapshot
#      holds). The restore cold-boots that disk, so the pod restarts only
#      with restartPolicy Always: for a Never pod with exited containers
#      kubelet makes no new sandbox, and the pod stays terminated
#   4. vk8s delete, then check that nothing remains: no cluster directory,
#      no VMM process, no control socket, no list entry; then the image
#      cache stops and no VMM process of vk8s is left at all
# SMOKE_MINIMAL=1 (the emulated arm64 job: docs/GOAL.md section 8 asks
# only for create, pods Running, and delete leaves nothing) runs steps 1
# and 4 alone: one control-plane node of SMOKE_CPUS vCPUs (default 2), no
# worker, no image cache VM (VK8S_CACHE=off), the pod on the preloaded
# sandbox image, and no gVisor, snapshot or restore (the real-KVM amd64
# job keeps those).
# Prints each step's time and a table at the end (also to
# $GITHUB_STEP_SUMMARY when set). Exits non-zero on the first failure,
# after printing the guests' console logs.
#
# usage: scripts/smoke-linux.sh
# VK8S_BIN (default out/vk8s) is the binary; VK8S_ASSETS a local asset
# build (scripts/guest/build.sh), needed while this host's arch has no
# pinned release. SMOKE_SLOW (a whole number, default 1) multiplies the
# smoke's own waits; on an emulated KVM host (scripts/smoke-emulated-kvm.sh)
# set it with VK8S_WAIT_SCALE, which scales vk8s's waits.
# Needs /dev/kvm (read and write), kubectl, nc, curl.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
v=${VK8S_BIN:-out/vk8s}
name=${SMOKE_NAME:-smoke}
nodes=2   # the control plane and one worker
slow=${SMOKE_SLOW:-1}
case $slow in ''|*[!0-9]*|0) slow=1 ;; esac
pod_image=registry.k8s.io/pause:3.10.1
minimal=${SMOKE_MINIMAL:-0}
cpus=${SMOKE_CPUS:-2}
case $cpus in ''|*[!0-9]*|0) cpus=2 ;; esac
if [ "$minimal" = 1 ]; then
  nodes=1   # the control plane alone
  pod_image=registry.k8s.io/pause:3.10.2   # the sandbox image, preloaded
  export VK8S_CACHE=off   # no image cache VM: one VM boots, not two
fi
gvisor_image=docker.io/library/busybox:1.36
dir=$HOME/.vk8s/clusters/$name
w=$(mktemp -d)
rows=""
now() { date +%s%3N; }
secs() { awk -v ms="$1" 'BEGIN { printf "%.1f", ms / 1000 }'; }
row() { rows="$rows| $1 | $(secs "$2") |"$'\n'; echo "smoke: $1: $(secs "$2") s"; }
k() { "$v" connect "$name" -- kubectl "$@"; }

dump() {
  echo "== vk8s list"; "$v" list 2>&1 || true
  echo "== pods"; k get pods -A -o wide 2>&1 || true
  echo "== pod smoke"; k describe pod smoke 2>&1 | tail -n 40 || true
  echo "== pod gvisor"; k describe pod gvisor 2>&1 | tail -n 40 || true
  echo "== runtimeclass"; k get runtimeclass -o wide 2>&1 || true
  for f in "$dir/console.log" "$dir"/nodes/*/console.log "$dir/vmm.log" "$dir"/nodes/*/vmm.log "$HOME/.vk8s/cache/console.log"; do
    [ -f "$f" ] || continue
    echo "== $f (boot steps and failures)"
    grep -E 'vk8s: |vk8s-init: (start|spawn|stop|FAILED|timed out)|[Pp]anic' "$f" | head -n 120 || true
    echo "== $f (last 80 lines)"; tail -n 80 "$f"
  done
  for f in "$dir"/share/logs/*.log; do
    [ -f "$f" ] || continue
    echo "== $f (why it exited: fatal lines, first 40)"
    grep -E '^F[0-9]{4} |PostStartHook|[Pp]anic|[Ff]atal|level=fatal' "$f" | head -n 40 || true
    echo "== $f (last 20 lines)"; tail -n 20 "$f"
  done
}
cleanup() {
  "$v" delete "$name" >/dev/null 2>&1 || true
  "$v" cache stop >/dev/null 2>&1 || true
  rm -rf "$w"
}
fail() {
  echo "FAIL smoke: $*"
  dump
  summary "FAIL: $*"
  cleanup
  exit 1
}
summary() {
  local head
  head="### vk8s smoke on $(uname -m) ($1)"
  local table="| step | seconds |"$'\n'"|---|---|"$'\n'"$rows"
  echo "$head"; printf '%s' "$table"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then printf '%s\n\n%s\n' "$head" "$table" >> "$GITHUB_STEP_SUMMARY"; fi
}
# timed NAME CMD...: runs CMD, records its time, fails the smoke on error
timed() {
  local label=$1; shift
  local t0; t0=$(now)
  "$@" > "$w/out" 2>&1 || { cat "$w/out"; fail "$label"; }
  row "$label" $(( $(now) - t0 ))
}
# until_ok SECONDS CMD...: retries CMD every 2 s until it succeeds, for
# SECONDS times SMOKE_SLOW
until_ok() {
  local limit=$(( $1 * slow )); shift
  local end=$(( $(date +%s) + limit ))
  until "$@" >/dev/null 2>&1; do
    [ "$(date +%s)" -lt "$end" ] || return 1
    sleep 2
  done
}
ready_nodes() { [ "$(k get nodes --no-headers 2>/dev/null | awk '$2 == "Ready"' | wc -l)" -ge "$nodes" ]; }
pod_running() { [ "$(k get pod smoke -o 'jsonpath={.status.phase}' 2>/dev/null)" = Running ]; }
gvisor_done() { [ "$(k get pod gvisor -o 'jsonpath={.status.phase}' 2>/dev/null)" = Succeeded ]; }
gvisor_log() { k logs gvisor 2>/dev/null | grep -q 'Starting gVisor'; }
# VMM processes ([v]: pgrep's pattern never matches the shell running it)
vmms() { pgrep -f -- "[v]mm .*--control $1" | wc -l; }
no_vmm() { ! pgrep -f -- '[v]k8s vmm' >/dev/null; }

[ -x "$v" ] || { echo "smoke: no vk8s binary at $v (scripts/build-linux.sh)"; exit 2; }
[ -r /dev/kvm ] && [ -w /dev/kvm ] || { echo "smoke: /dev/kvm is missing or not read-write for $(id -un)"; exit 2; }
echo "smoke: $("$v" version 2>&1 | head -1) on $(uname -srm), assets ${VK8S_ASSETS:-pinned}, waits x$slow (vk8s x${VK8S_WAIT_SCALE:-1})"
[ "$minimal" = 1 ] && echo "smoke: minimal: one control-plane node, $cpus vCPUs, no worker, no cache, no gVisor, snapshot or restore"
"$v" delete "$name" >/dev/null 2>&1 || true
t_all=$(now)

# 1. create, nodes Ready, a pod Running
if [ "$minimal" = 1 ]; then
  timed "create (control plane, $cpus vCPUs)" "$v" create "$name" --nodes 0 --cpus "$cpus" --connect=false
else
  timed "create (control plane + 1 worker)" "$v" create "$name" --nodes 1 --connect=false
fi
timed "nodes Ready ($nodes)" until_ok 600 ready_nodes
cp=$(k get nodes -o name 2>/dev/null | sed 's|^node/||' | grep -v -- '-worker-' | head -1)
[ -n "$cp" ] || fail "no control-plane node"
k get nodes -o wide
timed "pod created" k run smoke --image="$pod_image" --restart=Always \
  --overrides="{\"apiVersion\":\"v1\",\"spec\":{\"nodeName\":\"$cp\"}}"
timed "pod Running" until_ok 600 pod_running

if [ "$minimal" != 1 ]; then
  # 1b. a pod on gVisor (the opt-in gvisor RuntimeClass, handler runsc)
  wk=$(k get nodes -o name 2>/dev/null | sed 's|^node/||' | grep -- '-worker-' | head -1)
  [ -n "$wk" ] || fail "no worker node"
  timed "RuntimeClass gvisor" until_ok 300 k get runtimeclass gvisor
  timed "gVisor pod created" k run gvisor --image="$gvisor_image" --restart=Never \
    --overrides="{\"apiVersion\":\"v1\",\"spec\":{\"nodeName\":\"$wk\",\"runtimeClassName\":\"gvisor\",\"containers\":[{\"name\":\"gvisor\",\"image\":\"$gvisor_image\",\"command\":[\"dmesg\"]}]}}"
  timed "gVisor pod Succeeded" until_ok 600 gvisor_done
  k logs gvisor 2>&1 | head -n 5
  timed "gVisor pod log shows Starting gVisor" gvisor_log
  timed "gVisor pod deleted" k delete pod gvisor --wait=true

  # 1b'. NetworkPolicy: kube-router's policy controller on each node
  timed "NetworkPolicy deny-all and allow (tests/netpol_e2e.sh)" \
    env NETPOL_MEASURE=1 tests/netpol_e2e.sh "$wk" "$cp" -- "$v" connect "$name" -- kubectl
  grep -E '^(PASS|MEASURE)' "$w/out"

  # 1c. the image cache's upkeep: the gVisor pod pulled busybox through
  # the cache's docker.io registry; status shows it, prune docker.io
  # empties it and the registry answers again
  timed "cache status" "$v" cache status
  cat "$w/out"
  grep -q '^image cache: running' "$w/out" || fail "cache status does not say running"
  grep -q '^  docker.io: [0-9.]* MiB' "$w/out" || fail "cache status shows no MiB cached for docker.io"
  grep -q '^  data.img on the host: ' "$w/out" || fail "cache status shows no data.img size"
  timed "cache prune docker.io" "$v" cache prune docker.io
  cat "$w/out"
  grep -q '^pruned docker.io (' "$w/out" || fail "cache prune printed no pruned line"
  grep -q '^freed ' "$w/out" || fail "cache prune printed no freed line"
  timed "cache status after prune" "$v" cache status
  cat "$w/out"
  grep -q '^  docker.io: [0-9]* KiB' "$w/out" || fail "docker.io still holds MiB after the prune"
  timed "docker.io registry answers after prune" until_ok 60 curl -sf -o /dev/null http://127.0.0.1:15001/v2/

  # 2. snapshot (VM format), delete
  timed "snapshot create" "$v" snapshot create "$name" "$w/snap.tgz"
  ls -l "$w/snap.tgz"
  timed "delete" "$v" delete "$name"
  [ -e "$dir" ] && fail "the cluster directory remains after delete"

  # 3. restore
  timed "restore" "$v" restore "$name" "$w/snap.tgz"
  timed "nodes Ready after restore" until_ok 600 ready_nodes
  timed "pod Running after restore" until_ok 600 pod_running
  k get pods -A -o wide
fi

# 4. delete, nothing remains
if [ "$minimal" = 1 ]; then last="delete"; else last="delete after restore"; fi
timed "$last" "$v" delete "$name"
[ -e "$dir" ] && fail "the cluster directory remains"
[ "$(vmms "$dir")" = 0 ] || { pgrep -af '[v]mm'; fail "a VMM process of $name remains"; }
if command -v ss >/dev/null 2>&1 && ss -xl 2>/dev/null | grep -q -- "$dir/"; then fail "a control socket of $name remains"; fi
"$v" list 2>/dev/null | grep -qw -- "$name" && fail "vk8s list still shows $name"
timed "cache stop" "$v" cache stop
until_ok 60 no_vmm || { pgrep -af '[v]mm'; fail "a VMM process remains after cache stop"; }
row "total" $(( $(now) - t_all ))
echo "PASS smoke"
summary "PASS"
cleanup
