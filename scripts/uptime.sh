#!/usr/bin/env bash
# macOS: one cluster left alone for a day (docs/RELEASE.md, "Gates": a
# 24-hour uptime run per major change of the guest or of a long-running
# process).
#   scripts/uptime.sh [HOURS=24] [OUT=out/uptime]
# A 2-node VM cluster with a 2-replica nginx Deployment and the default
# idle sleep (15 minutes without API traffic). Every 10 minutes a sample
# from the host only, so the cluster stays asleep: its state as `vk8s
# list` shows it, the VMM processes and their summed phys_footprint, the
# cluster folder's and the layer store's disk. Every 2 hours one check
# through the API, which wakes it: ms until `kubectl get nodes` answers,
# nodes Ready, the Deployment's available replicas, the restart counts
# of every container, and a new pod that must run to completion (the
# small workload). OUT/samples.csv and OUT/checks.csv; the last line of
# stdout is UPTIME OK or UPTIME FAIL with the reason.
set -uo pipefail
cd "$(dirname "$0")/.."
hours=${1:-24}; out=${2:-out/uptime}
v=${VK8S_BIN:-out/vk8s}; name=${UPTIME_NAME:-up24}
mkdir -p "$out"
k() { "$v" connect "$name" -- kubectl "$@"; }
now() { perl -MTime::HiRes=time -e 'printf "%d\n", time*1000'; }
pids() { pgrep -f " vmm .*/clusters/$name/" | tr '\n' ' '; }
fp_mib() {
  local s=0 p f
  for p in $(pids); do
    f=$(footprint "$p" 2>/dev/null | sed -n 's/.*phys_footprint: *\([0-9.]*\) *\([KMG]B\).*/\1 \2/p' | head -1)
    case $f in
      *GB) s=$(echo "$s + ${f% GB} * 1024" | bc) ;;
      *MB) s=$(echo "$s + ${f% MB}" | bc) ;;
      *KB) s=$(echo "$s + ${f% KB} / 1024" | bc) ;;
    esac
  done
  printf '%.0f' "$s"
}
du_mib() { du -sk "$1" 2>/dev/null | awk '{printf "%d", $1/1024}'; }
state() { "$v" list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk -v n="$name" '$1 == n {print $3}'; }
fails=0
bad() { echo "FAIL $*"; fails=$((fails + 1)); }

check() { # check N: one look through the API
  local n=$1 t0 wake ready avail restarts pod
  t0=$(now)
  until k get nodes >/dev/null 2>&1; do [ $(( $(now) - t0 )) -lt 180000 ] || break; sleep 1; done
  wake=$(( $(now) - t0 ))
  k wait --for=condition=Ready node --all --timeout=180s >/dev/null 2>&1
  ready=$(k get nodes --no-headers 2>/dev/null | grep -cw Ready)
  k rollout status deploy/web --timeout=180s >/dev/null 2>&1
  avail=$(k get deploy web -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
  restarts=$(k get pods -A -o jsonpath='{range .items[*]}{range .status.containerStatuses[*]}{.restartCount}{"\n"}{end}{end}' 2>/dev/null | awk '{s+=$1} END {print s+0}')
  k run "t$n" --image=docker.io/library/busybox:1.36 --restart=Never -- sh -c 'echo ok' >/dev/null 2>&1
  pod=no
  if k wait --for=jsonpath='{.status.phase}'=Succeeded "pod/t$n" --timeout=180s >/dev/null 2>&1; then pod=ok; fi
  k delete pod "t$n" --wait=false >/dev/null 2>&1
  echo "$(date +%F_%T),$n,$wake,$ready,${avail:-0},$restarts,$pod" >> "$out/checks.csv"
  [ "$ready" = 2 ] || bad "check $n: $ready of 2 nodes Ready"
  [ "${avail:-0}" = 2 ] || bad "check $n: ${avail:-0} of 2 web replicas available"
  [ "$pod" = ok ] || bad "check $n: the new pod did not finish"
}

"$v" create "$name" --nodes 1 --connect=false >/dev/null 2>&1 || { echo "UPTIME FAIL create"; exit 1; }
k wait --for=condition=Ready node --all --timeout=300s >/dev/null
k create deploy web --image=docker.io/library/nginx:1.27 --replicas=2 >/dev/null
k rollout status deploy/web --timeout=300s >/dev/null
echo "time,sample,state,vmms,footprint_mib,cluster_mib,layers_mib" > "$out/samples.csv"
echo "time,check,wake_ms,nodes_ready,web_available,restarts,new_pod" > "$out/checks.csv"
check 0
vmms0=$(pids | wc -w | tr -d ' ')
total=$((hours * 6)); i=1
while [ $i -le $total ]; do
  sleep 600
  n=$(pids | wc -w | tr -d ' ')
  echo "$(date +%F_%T),$i,$(state),$n,$(fp_mib),$(du_mib "$HOME/.vk8s/clusters/$name"),$(du_mib "$HOME/.vk8s/layers")" >> "$out/samples.csv"
  [ "$n" = "$vmms0" ] || bad "sample $i: $n VMM processes, $vmms0 at the start"
  [ $((i % 12)) != 0 ] || check $((i / 12))
  i=$((i + 1))
done
"$v" delete "$name" >/dev/null 2>&1
left=$(pids | wc -w | tr -d ' ')
[ "$left" = 0 ] || bad "$left VMM processes after delete"
if [ $fails = 0 ]; then echo "UPTIME OK"; else echo "UPTIME FAIL ($fails)"; fi
