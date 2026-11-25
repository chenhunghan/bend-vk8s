#!/usr/bin/env bash
# macOS: how many busybox processes a one-node VM cluster's guest starts
# (docs/GOAL.md section 11, "Fewer shell-outs": guest hot paths), and
# what a pod start and an idle guest cost.
#   VK8S_BIN=out/vk8s VK8S_ASSETS=DIR scripts/bench/guest-spawns.sh LABEL [IDLE_S=300] [RUNS=5]
# One run: create cluster gsp (--idle-sleep 0), wait until the node is
# Ready and every system pod runs, then
#   cold   one nginx pod, its image not on the node yet: kubectl run to Ready
#   warm   RUNS more nginx pods, one at a time, each deleted before the next
#   idle   IDLE_S seconds with one nginx pod running
#   pause  vk8s pause, 5 s, vk8s resume, the API answers
#   delete vk8s delete leaves no cluster folder
# For each phase it counts the lines PID 1 prints for a busybox step
# ("vk8s-init: run /bin/busybox", console.log), the lines the snapshotter
# prints for a busybox call ("vk8s-snapshotter: busybox",
# share/logs/snapshotter.log), and, for idle, the guest's fork count and
# busy CPU share from /proc/stat (read in the pod at both ends).
# PID 1's own direct calls (mkdir -p before a write, rm -f of a request)
# print no line; the fork count covers them.
# Prints key=value lines on stdout; progress on stderr.
set -uo pipefail
cd "$(dirname "$0")/../.."
label=${1:?label}; idle_s=${2:-300}; runs=${3:-5}
v=${VK8S_BIN:-out/vk8s}; export VK8S_IDLE_SLEEP=0
name=gsp
dir=$HOME/.vk8s/clusters/$name
img=docker.io/library/nginx@sha256:6784fb0834aa7dbbe12e3d7471e69c290df3e6ba810dc38b34ae33d3c1c05f7d
say() { echo "[$(date +%H:%M:%S)] $*" >&2; }
k() { "$v" connect "$name" -- kubectl "$@"; }
now() { perl -MTime::HiRes=time -e 'printf "%d\n", time*1000'; }
init_n() { grep -c 'vk8s-init: run /bin/busybox' "$dir/console.log" 2>/dev/null || true; }
snap_n() { grep -c 'vk8s-snapshotter: busybox' "$dir/share/logs/snapshotter.log" 2>/dev/null || true; }
snap_kinds() { # the busybox applets the snapshotter ran since line $1 of its log
  tail -n +"$(($1 + 1))" "$dir/share/logs/snapshotter.log" 2>/dev/null |
    sed -n 's/.*vk8s-snapshotter: busybox \([a-z]*\) .*/\1/p' | sort | uniq -c | awk '{printf "%s%s:%s", (NR>1?",":""), $2, $1}'
}
snap_lines() { wc -l < "$dir/share/logs/snapshotter.log" 2>/dev/null | tr -d ' '; }
pod_ms() { # pod_ms NAME: ms from kubectl run to Ready
  local t0 t1
  t0=$(now)
  k run "$1" --image="$img" --restart=Never >/dev/null 2>&1
  if k wait --for=condition=Ready "pod/$1" --timeout=300s >/dev/null 2>&1; then t1=$(now); echo $((t1 - t0)); else echo timeout; fi
}
pod_rm() { k delete pod "$1" --wait=true >/dev/null 2>&1; }
stat_of() { k exec idle0 -- cat /proc/stat 2>/dev/null; }

scripts/bench/guard.sh check >&2 || { say "the Mac is short of room"; exit 1; }
scripts/bench/guard.sh watch $$ >&2 &
guard=$!
trap 'kill $guard 2>/dev/null; "$v" delete "$name" >/dev/null 2>&1' EXIT

"$v" delete "$name" >/dev/null 2>&1
say "$label: create $name"
t0=$(now)
"$v" create "$name" --connect=false >/dev/null || { say "create failed"; exit 1; }
until [ "$(k get nodes --no-headers 2>/dev/null | grep -cw Ready)" = 1 ]; do sleep 1; done
until n=$(k get pods -A --no-headers 2>/dev/null) && [ -n "$n" ] && ! echo "$n" | grep -qv Running; do sleep 1; done
t1=$(now)
echo "label=$label"
echo "create_ms=$((t1 - t0))"
echo "boot_init_busybox=$(init_n)"
echo "boot_snap_busybox=$(snap_n)"
echo "boot_snap_kinds=$(snap_kinds 0)"

say "$label: cold pod"
i0=$(init_n); s0=$(snap_n); l0=$(snap_lines)
echo "cold_ms=$(pod_ms cold0)"
echo "cold_init_busybox=$(($(init_n) - i0))"
echo "cold_snap_busybox=$(($(snap_n) - s0))"
echo "cold_snap_kinds=$(snap_kinds "$l0")"
pod_rm cold0

say "$label: $runs warm pods"
i0=$(init_n); s0=$(snap_n); l0=$(snap_lines)
ms=""
for i in $(seq 1 "$runs"); do
  # the delete before ends on a kubelet sync, and the kubelet sees a
  # started container at its next relist (1 s apart): without a gap of
  # its own each run starts at the same point of that cycle, and the
  # times fall in two groups about 320 ms apart whatever the guest does
  perl -e 'select(undef, undef, undef, ($ARGV[0] * 137 % 1000) / 1000)' "$i"
  ms="$ms $(pod_ms "warm$i")"
  i1=$(init_n); s1=$(snap_n)
  [ "$i" = 1 ] && { echo "warm1_init_busybox=$((i1 - i0))"; echo "warm1_snap_busybox=$((s1 - s0))"; echo "warm1_snap_kinds=$(snap_kinds "$l0")"; }
  pod_rm "warm$i"
done
echo "warm_ms=$(echo $ms | tr ' ' ',')"
echo "warm_mean_ms=$(echo $ms | tr ' ' '\n' | awk '{s+=$1} END {printf "%d", s/NR}')"
echo "warm_median_ms=$(echo $ms | tr ' ' '\n' | sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}')"
echo "warm_cycles_init_busybox=$(($(init_n) - i0))"
echo "warm_cycles_snap_busybox=$(($(snap_n) - s0))"
echo "warm_cycles_snap_kinds=$(snap_kinds "$l0")"

say "$label: idle ${idle_s}s"
pod_ms idle0 >/dev/null
sleep 20
a=$(stat_of); i0=$(init_n); s0=$(snap_n); l0=$(snap_lines)
sleep "$idle_s"
b=$(stat_of)
echo "idle_s=$idle_s"
echo "idle_init_busybox=$(($(init_n) - i0))"
echo "idle_snap_busybox=$(($(snap_n) - s0))"
echo "idle_snap_kinds=$(snap_kinds "$l0")"
fa=$(awk '/^processes/ {print $2}' <<<"$a"); fb=$(awk '/^processes/ {print $2}' <<<"$b")
echo "idle_forks=$((fb - fa))"
# busy share of all vCPU time: 1 - (idle + iowait) / total, in 0.01%
cpu() { awk '/^cpu / {t=0; for (i=2; i<=9; i++) t+=$i; print t, $5+$6}' <<<"$1"; }
read -r ta ia <<<"$(cpu "$a")"; read -r tb ib <<<"$(cpu "$b")"
echo "idle_cpu_busy_pct=$(awk -v t=$((tb - ta)) -v i=$((ib - ia)) 'BEGIN {printf("%.2f", (t > 0) ? (100 * (t - i) / t) : 0)}')"
echo "idle_cpu_total_ticks=$((tb - ta))"
echo "idle_cpu_ticks=$((tb - ta - ib + ia))"

say "$label: pause and resume"
i0=$(init_n)
"$v" pause "$name" >/dev/null 2>&1; pr=$?
sleep 5
"$v" resume "$name" >/dev/null 2>&1; rr=$?
if k get nodes --no-headers 2>/dev/null | grep -qw Ready; then echo "pause_resume=ok (pause $pr, resume $rr)"; else echo "pause_resume=FAILED (pause $pr, resume $rr)"; fi
k get pod idle0 --no-headers 2>/dev/null | grep -qw Running && echo "pod_after_resume=Running" || echo "pod_after_resume=NOT RUNNING"
echo "pause_init_busybox=$(($(init_n) - i0))"

say "$label: delete"
cp "$dir/console.log" "out/guest-spawns-$label.console.log" 2>/dev/null
cp "$dir/share/logs/snapshotter.log" "out/guest-spawns-$label.snapshotter.log" 2>/dev/null
cp "$dir/share/logs/containerd.log" "out/guest-spawns-$label.containerd.log" 2>/dev/null
cp "$dir/share/logs/kubelet.log" "out/guest-spawns-$label.kubelet.log" 2>/dev/null
"$v" delete "$name" >/dev/null 2>&1; dr=$?
[ ! -e "$dir" ] && echo "delete=ok (exit $dr)" || echo "delete=FAILED (exit $dr, $dir stays)"
kill $guard 2>/dev/null
trap - EXIT
