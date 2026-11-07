#!/usr/bin/env bash
# Soak test (docs/GOAL.md section 6): create/delete cycles, then a long workload
# with pause/resume, checking that nothing leaks: VMM processes, sockets,
# cluster directories, disk.
#   scripts/soak.sh [cycles=10] [minutes=60]
# Uses out/vk8s and $VK8S_ASSETS (default ~/.vk8s/assets/dev). Writes a
# log to out/soak/<timestamp>.log and exits non-zero on any leak or failure.
set -uo pipefail
cd "$(dirname "$0")/.."
cycles=${1:-10}; minutes=${2:-60}
export VK8S_ASSETS=${VK8S_ASSETS:-$HOME/.vk8s/assets/dev}
v=${VK8S_BIN:-out/vk8s}
mkdir -p out/soak
log=out/soak/$(date +%Y%m%d-%H%M%S).log
exec > >(tee "$log") 2>&1
fail=0
bad() { echo "FAIL: $*"; [ -s "$errf" ] && sed 's/^/  | /' "$errf" | tail -3; fail=1; }
errf=$(mktemp)
vmms() { pgrep -f "vk8s vmm" | while read -r p; do ps -o command= -p "$p"; done | grep -c -- "--control $HOME/.vk8s/clusters/soak" ; }
socks() { lsof -U 2>/dev/null | grep -c "$HOME/.vk8s/clusters/soak" ; }
k() { "$v" connect soak -- kubectl "$@" 2>"$errf"; }

echo "== baseline"
base_vmm=$(vmms); base_sock=$(socks)
base_disk=$(df -k "$HOME" | awk 'NR==2{print $3}')
echo "vmm=$base_vmm sock=$base_sock used_kb=$base_disk"

echo "== $cycles create/delete cycles (1 worker each)"
for i in $(seq 1 "$cycles"); do
  t0=$(date +%s)
  "$v" create soak --nodes 1 --connect=false >/dev/null 2>"$errf" || bad "cycle $i: create"
  k run p --image=registry.k8s.io/pause:3.10.1 >/dev/null 2>&1 || bad "cycle $i: run"
  k wait --for=condition=Ready pod/p --timeout=180s >/dev/null 2>&1 || bad "cycle $i: pod not ready"
  t1=$(date +%s)
  "$v" delete soak >/dev/null 2>&1 || bad "cycle $i: delete"
  t2=$(date +%s)
  [ -e "$HOME/.vk8s/clusters/soak" ] && bad "cycle $i: cluster dir left behind"
  n=$(vmms); [ "$n" -gt "$base_vmm" ] && bad "cycle $i: $n VMM processes left"
  echo "cycle $i: create+pod $((t1 - t0))s, delete $((t2 - t1))s"
done

echo "== ${minutes}-minute workload with pause/resume"
"$v" create soak --nodes 1 --connect=false >/dev/null 2>"$errf" || bad "workload create"
k create deployment web --image=registry.k8s.io/pause:3.10.1 --replicas=4 >/dev/null 2>&1
k create configmap tick --from-literal=n=0 >/dev/null 2>&1
end=$(( $(date +%s) + minutes * 60 )); n=0
while [ "$(date +%s)" -lt "$end" ]; do
  n=$((n + 1))
  k create configmap "c$n" --from-literal=n="$n" >/dev/null || bad "write $n ($(date -u +%H:%M:%S))"
  [ $((n % 2)) = 0 ] && k delete configmap "c$((n - 1))" >/dev/null 2>&1
  if [ $((n % 10)) = 0 ]; then
    "$v" pause soak >/dev/null 2>&1 || bad "pause $n"; sleep 5
    "$v" resume soak >/dev/null 2>&1 || bad "resume $n"
    k wait --for=condition=Available deploy/web --timeout=120s >/dev/null 2>&1 || bad "web unavailable after resume $n"
  fi
  sleep 20
done
ready=$(k get deploy web -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[ "$ready" = 4 ] || bad "web has $ready/4 ready at the end"
echo "workload: $n rounds, web ready $ready/4, apiserver restarts: $(grep -c 'start kube-apiserver (restart' "$HOME/.vk8s/clusters/soak/console.log")"
"$v" delete soak >/dev/null 2>&1 || bad "final delete"

echo "== leaks"
n=$(vmms); s=$(socks); used=$(df -k "$HOME" | awk 'NR==2{print $3}')
echo "vmm=$n sock=$s used_kb=$used (delta $(( (used - base_disk) / 1024 )) MiB)"
[ "$n" -gt "$base_vmm" ] && bad "VMM processes leaked"
[ "$s" -gt "$base_sock" ] && bad "sockets leaked"
[ -e "$HOME/.vk8s/clusters/soak" ] && bad "cluster dir leaked"
[ $(( (used - base_disk) / 1024 )) -gt 512 ] && bad "disk grew by more than 512 MiB"
[ $fail = 0 ] && echo "SOAK OK" || echo "SOAK FAILED"
exit $fail
