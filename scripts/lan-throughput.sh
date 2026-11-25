#!/usr/bin/env bash
# Pod-to-pod TCP throughput across two VM nodes on the bend-vmm LAN
# (flannel host-gw), for one or more vk8s binaries (docs/GOAL.md section
# 10; docs/STATUS.md section 10 records the numbers). For each binary:
#   1. vk8s create (control plane + 1 worker), every node Ready
#   2. an iperf3 server pod on the control plane, then RUNS client pods on
#      the worker, each TIME seconds: pod to pod (flannel host-gw), and
#      node to node (hostNetwork pods: the LAN alone)
#   3. vk8s delete
# The last binary is also checked for the LAN wire guard
# (src/cli/lan_wire.bend): its cluster.env records LAN_WIRE=2, and once
# that line is gone (a cluster of an older vk8s) `vk8s node add` refuses.
# Prints a table (also to $GITHUB_STEP_SUMMARY when set) and writes it
# to out/lan-throughput.md.
#
# usage: scripts/lan-throughput.sh LABEL=BINARY [LABEL=BINARY ...]
#   e.g. scripts/lan-throughput.sh before=out/vk8s-before after=out/vk8s
# LAN_RUNS (default 3) and LAN_TIME (default 15) set the client runs.
# Needs /dev/kvm, kubectl, nc; VK8S_ASSETS as for scripts/smoke-linux.sh.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
[ $# -ge 1 ] || { echo "usage: $0 LABEL=BINARY [LABEL=BINARY ...]"; exit 2; }
name=${LAN_NAME:-lanbench}
runs=${LAN_RUNS:-3}
secs=${LAN_TIME:-15}
img=docker.io/networkstatic/iperf3:latest
dir=$HOME/.vk8s/clusters/$name
out=out/lan-throughput.md
mkdir -p out
rows=""
v=
k() { "$v" connect "$name" -- kubectl "$@"; }

until_ok() {
  local end=$(( $(date +%s) + $1 )); shift
  until "$@" >/dev/null 2>&1; do
    [ "$(date +%s)" -lt "$end" ] || return 1
    sleep 2
  done
}
ready_nodes() { [ "$(k get nodes --no-headers 2>/dev/null | awk '$2 == "Ready"' | wc -l)" -ge 2 ]; }
phase_is() { [ "$(k get pod "$1" -o 'jsonpath={.status.phase}' 2>/dev/null)" = "$2" ]; }
dump() {
  k get pods -A -o wide 2>&1 || true
  for f in "$dir/console.log" "$dir"/nodes/*/console.log "$dir/vmm.log" "$dir"/nodes/*/vmm.log; do
    [ -f "$f" ] || continue
    echo "== $f (last 60 lines)"; tail -n 60 "$f"
  done
}
fail() {
  echo "FAIL lan-throughput: $*"
  dump
  "$v" delete "$name" >/dev/null 2>&1 || true
  exit 1
}
# pod NAME NODE HOSTNET ARGS...: a pod of the iperf3 image on NODE
pod() {
  local p=$1 node=$2 hn=$3; shift 3
  local restart=Never
  [ "$p" = srv-pod ] || [ "$p" = srv-node ] && restart=Always
  k run "$p" --image="$img" --restart="$restart" \
    --overrides="{\"apiVersion\":\"v1\",\"spec\":{\"nodeName\":\"$node\",\"hostNetwork\":$hn}}" -- "$@" >/dev/null
}
# MB/s of the receiver line of iperf3 -f M
rate() { awk '/receiver/ { for (i = 2; i <= NF; i++) if ($i == "MBytes/sec") print $(i-1) }' | tail -1; }
mean() { awk '{ s += $1; n++ } END { if (n) printf "%.1f", s / n; else print "n/a" }'; }

# measure LABEL KIND HOSTNET: RUNS client runs against the server of KIND
measure() {
  local label=$1 kind=$2 hn=$3 ip all="" r i
  pod "srv-$kind" "$cp" "$hn" -s || fail "$label: server pod ($kind)"
  until_ok 600 phase_is "srv-$kind" Running || fail "$label: server pod ($kind) not Running"
  ip=$(k get pod "srv-$kind" -o 'jsonpath={.status.podIP}')
  [ -n "$ip" ] || fail "$label: no server IP ($kind)"
  sleep 3
  for i in $(seq "$runs"); do
    pod "cli-$kind-$i" "$wk" "$hn" -c "$ip" -t "$secs" -f M || fail "$label: client pod ($kind $i)"
    until_ok $(( secs + 600 )) phase_is "cli-$kind-$i" Succeeded || { k logs "cli-$kind-$i" || true; fail "$label: client ($kind $i) did not succeed"; }
    r=$(k logs "cli-$kind-$i" | rate)
    echo "lan-throughput: $label $kind run $i: ${r:-n/a} MB/s"
    all="$all${r:-0}"$'\n'
    k delete pod "cli-$kind-$i" --wait=false >/dev/null 2>&1 || true
  done
  k delete pod "srv-$kind" --wait=false >/dev/null 2>&1 || true
  rows="$rows| $label | $kind | $(printf '%s' "$all" | tr '\n' ' ') | $(printf '%s' "$all" | mean) |"$'\n'
}

last=${!#}
for arg in "$@"; do
  label=${arg%%=*}; v=${arg#*=}
  [ -x "$v" ] || { echo "lan-throughput: no binary at $v"; exit 2; }
  echo "lan-throughput: $label: $("$v" version 2>&1 | head -1) ($v)"
  "$v" delete "$name" >/dev/null 2>&1 || true
  # VK8S_PACK=0: the "before" binary links an older bend-vmm that has no
  # --pack, and the pack is not what this compares
  VK8S_PACK=0 "$v" create "$name" --backend vm --nodes 1 --idle-sleep 0 --connect=false || fail "$label: create"
  until_ok 600 ready_nodes || fail "$label: nodes not Ready"
  cp=$(k get nodes -o name | sed 's|^node/||' | grep -v -- '-worker-' | head -1)
  wk=$(k get nodes -o name | sed 's|^node/||' | grep -- '-worker-' | head -1)
  [ -n "$cp" ] && [ -n "$wk" ] || fail "$label: nodes"
  k get nodes -o wide
  k get pods -A -o wide
  measure "$label" pod false
  measure "$label" node true
  if [ "$arg" = "$last" ]; then
    grep -qx 'LAN_WIRE=2' "$dir/cluster.env" || { cat "$dir/cluster.env"; fail "$label: cluster.env has no LAN_WIRE=2"; }
    sed -i '/^LAN_WIRE=/d' "$dir/cluster.env"
    if msg=$("$v" node add "$name" 2>&1); then fail "$label: node add started a VM on a version 1 cluster"; fi
    echo "$msg"
    grep -q 'LAN wire version 1, but this vk8s runs version 2' <<<"$msg" || fail "$label: node add did not name the LAN wire versions"
    [ ! -d "$dir/nodes/2" ] || fail "$label: node add made a worker directory"
    echo "lan-throughput: the LAN wire guard refused node add on a version 1 cluster"
  fi
  "$v" delete "$name" || fail "$label: delete"
done
"$v" cache stop >/dev/null 2>&1 || true

{
  echo "### Pod-to-pod TCP across two VM nodes (iperf3, $runs x $secs s, $(uname -m))"
  echo
  echo "| binary | path | MB/s per run | mean MB/s |"
  echo "|---|---|---|---|"
  printf '%s' "$rows"
  echo
  echo "pod: flannel host-gw between pod networks; node: hostNetwork pods (the LAN alone)."
} > "$out"
cat "$out"
[ -n "${GITHUB_STEP_SUMMARY:-}" ] && cat "$out" >> "$GITHUB_STEP_SUMMARY"
exit 0
