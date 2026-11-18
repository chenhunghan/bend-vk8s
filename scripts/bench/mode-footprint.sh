#!/usr/bin/env bash
# macOS: settled host footprint of one cluster in VM mode against container
# mode (one shared node-host VM), docs/GOAL.md section 8's condition for
# making container the macOS default.
#   scripts/bench/mode-footprint.sh MODE NODES [SETTLE_MIN=10] [AFTER_MIN=15]
#   MODE: vm | container; NODES: 1 (control plane only) or 3 (1 + 2 workers)
# Steps: create (sleep when idle off), every node Ready, settle; measure;
# a burst of 30 pods, deleted; AFTER_MIN idle; measure; delete.
# A measurement: summed phys_footprint and RSS of the cluster's VMMs
# (container mode: the node host's), the image cache VMM separately, CPU
# time over a 5-minute window, and allocated disk of the cluster's dirs.
# Prints one CSV line per measurement on stdout; progress on stderr.
set -uo pipefail
cd "$(dirname "$0")/../.."
mode=${1:?mode}; nodes=${2:?nodes}; settle=${3:-10}; after=${4:-15}
v=${VK8S_BIN:-out/vk8s}; export VK8S_IDLE_SLEEP=0
name=fp$mode$nodes
say() { echo "[$(date +%H:%M:%S)] $*" >&2; }
k() { "$v" connect "$name" -- kubectl "$@"; }

# PIDs of the VMMs that carry the cluster: in VM mode, those whose args
# name its cluster dir; in container mode, the node host's.
pids() {
  case $mode in
    vm) pgrep -f "vk8s vmm .*$HOME/.vk8s/clusters/$name/" ;;
    container) pgrep -f "vk8s vmm .*$HOME/.vk8s/nodehost/" ;;
  esac
}
cache_pids() { pgrep -f "vk8s vmm .*$HOME/.vk8s/cache/"; }
# phys_footprint and RSS in MiB, summed over the PIDs given
mem() {
  local fp=0 rss=0 p f r
  for p in "$@"; do
    f=$(footprint "$p" 2>/dev/null | sed -n 's/.*phys_footprint: *\([0-9.]*\) *\([KMG]B\).*/\1 \2/p' | head -1)
    case $f in
      *GB) fp=$(echo "$fp + ${f% GB} * 1024" | bc) ;;
      *MB) fp=$(echo "$fp + ${f% MB}" | bc) ;;
      *KB) fp=$(echo "$fp + ${f% KB} / 1024" | bc) ;;
    esac
    r=$(ps -o rss= -p "$p" 2>/dev/null); rss=$((rss + ${r:-0} / 1024))
  done
  printf '%.0f %d' "$fp" "$rss"
}
# CPU seconds (user+sys) summed over the PIDs given
cpus() {
  local t=0 p s
  for p in "$@"; do
    s=$(ps -o time= -p "$p" 2>/dev/null | awk -F'[:.]' '{ if (NF==4) print $1*3600+$2*60+$3; else print $1*60+$2 }')
    t=$((t + ${s:-0}))
  done
  echo "$t"
}
disk() {
  case $mode in
    vm) du -sk "$HOME/.vk8s/clusters/$name" | cut -f1 ;;
    container) du -sk "$HOME/.vk8s/nodehost" "$HOME/.vk8s/clusters/$name" | awk '{s+=$1} END {print s}' ;;
  esac
}
measure() {
  local phase=$1 p c0 c1 m cm
  p=$(pids | tr '\n' ' '); cp=$(cache_pids | tr '\n' ' ')
  c0=$(cpus $p); sleep 300; c1=$(cpus $p)
  m=$(mem $p); cm=$(mem $cp)
  # mode,nodes,phase,footprint_mib,rss_mib,cpu_pct_of_one_core,disk_mib,cache_footprint_mib,vmms
  echo "$mode,$nodes,$phase,${m% *},${m#* },$(echo "scale=2; ($c1 - $c0) * 100 / 300" | bc),$(( $(disk) / 1024 )),${cm% *},$(echo $p | wc -w | tr -d ' ')"
}

flag=; [ "$mode" = container ] && flag="--backend container"
say "create $name ($mode, $nodes nodes)"
t0=$(date +%s)
"$v" create "$name" --nodes $((nodes - 1)) $flag --connect=false >/dev/null || { say "create failed"; exit 1; }
until [ "$(k get nodes --no-headers 2>/dev/null | grep -cw Ready)" = "$nodes" ]; do sleep 5; done
say "all $nodes Ready in $(( $(date +%s) - t0 )) s; settle ${settle} min"
sleep $((settle * 60))
measure settled
say "burst: 30 pods"
k create deployment burst --image=registry.k8s.io/pause:3.10.1 --replicas=30 >/dev/null
k wait --for=condition=Available deploy/burst --timeout=600s >/dev/null || say "burst not available"
k delete deployment burst --wait=true >/dev/null
say "after the burst: ${after} min idle"
sleep $((after * 60))
measure after_burst
"$v" delete "$name" >/dev/null
say "deleted"
