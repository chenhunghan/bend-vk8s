#!/usr/bin/env bash
# Two nodes pulling the same image, with the shared layer store off and
# on (docs/GOAL.md section 11, "Shared assets and layers off the VM",
# measured as in section 10): the time from `kubectl run` to a Running
# pod on each node, one after the other, and the host disk the two pulls
# add (du -skx of the cluster's files and the store, before and after).
#
#   scripts/layers-bench.sh container VK8S ASSETS_DIR KUBECTL
#     one cluster with a worker (vk8s create --backend container
#     --nodes 1): the control plane's node pulls first, then the worker
#   scripts/layers-bench.sh native VK8S KUBECTL      (VK8S_ASSETS set)
#     a native host node, one per host: cluster A pulls, is deleted, then
#     cluster B pulls the same image on the same host
#
# Each run (off, then on) has its own $HOME, so its store starts empty:
# the first node's pull is a cold store, the second's a warm one. Any
# running layer filler is stopped first (it is one per host and fills
# the store of the $HOME that started it), and the run's own is stopped
# after. IMAGE (default registry.k8s.io/e2e-test-images/agnhost:2.56,
# run as `agnhost pause`) must be one no other run on the host pulled
# into this $HOME. Prints a table (also to $GITHUB_STEP_SUMMARY) and one
# line per run:
#   layers-bench: backend=B store=off|on first_ms=T1 second_ms=T2 disk_kib=D store_kib=S images=N
# Exits 1 when a pod does not run, or when the store is on and holds no
# layer image after the pulls (the nodes did not use it).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
backend=${1:?usage: scripts/layers-bench.sh container|native VK8S [ASSETS_DIR] KUBECTL}
vk8s=$(realpath "${2:?vk8s binary}")
case $backend in
  container) assets=$(realpath "${3:?assets dir}"); kubectl=$(realpath "${4:?kubectl}") ;;
  native) assets=${VK8S_ASSETS:?set VK8S_ASSETS}; kubectl=$(realpath "${3:?kubectl}") ;;
  *) echo "layers-bench: unknown backend $backend (container, native)" >&2; exit 2 ;;
esac
image=${IMAGE:-registry.k8s.io/e2e-test-images/agnhost:2.56}
fails=0
rows=""
now() { date +%s%3N; }
secs() { awk -v ms="$1" 'BEGIN { printf "%.1f", ms / 1000 }'; }
mib() { awk -v k="$1" 'BEGIN { printf "%.1f", k / 1024 }'; }
kib() { sudo du -skx "$@" 2>/dev/null | awk '{ s += $1 } END { print s + 0 }'; }
stop_fillers() { sudo pkill -f -- '[ ]layers serve$' >/dev/null 2>&1; sleep 1; }

# V MODE HOME ARGS...: vk8s with the store off (VK8S_LAYERS=0) or on (unset)
V() {
  local lay=$1 h=$2; shift 2
  local env=(HOME="$h" KUBECONFIG="$h/.kube/config" VK8S_ASSETS="$assets" PATH="$PATH" VK8S_IDLE_SLEEP=0)
  [ "$lay" = off ] && env+=(VK8S_LAYERS=0)
  if [ "$backend" = container ]; then sudo timeout 2400 env "${env[@]}" "$vk8s" "$@"
  else timeout 2400 env "${env[@]}" "$vk8s" "$@"; fi
}
k() { local kc=$1; shift; sudo "$kubectl" --kubeconfig "$kc" --request-timeout=30s "$@"; }

# pull KC NODE POD: ms from kubectl run to Running, or empty
pull() {
  local kc=$1 node=$2 pod=$3 t0
  t0=$(now)
  k "$kc" run "$pod" --image="$image" --restart=Never \
    --overrides="{\"apiVersion\":\"v1\",\"spec\":{\"nodeName\":\"$node\",\"containers\":[{\"name\":\"p\",\"image\":\"$image\",\"args\":[\"pause\"]}]}}" >/dev/null || return 1
  k "$kc" wait --for=jsonpath='{.status.phase}'=Running "pod/$pod" --timeout=900s >/dev/null || { k "$kc" describe pod "$pod" | tail -n 20; return 1; }
  echo $(( $(now) - t0 ))
}

# The files a cluster's pulls write to: the cluster dirs, and for a
# native cluster its data dir under /var/lib/vk8s.
files() { local h=$1; shift; echo "$h/.vk8s"; for c in "$@"; do [ -d "/var/lib/vk8s/$c" ] && echo "/var/lib/vk8s/$c"; done; }

# A cluster up, its nodes Ready: the kubeconfig path
up() {
  local lay=$1 h=$2 c=$3; shift 3
  V "$lay" "$h" create "$c" --backend "$backend" --connect=false "$@" >"$h.create.log" 2>&1 || { cat "$h.create.log"; return 1; }
  local kc=$h/.vk8s/clusters/$c/kubeconfig.yaml
  k "$kc" wait --for=condition=Ready node --all --timeout=900s >/dev/null || return 1
  echo "$kc"
}

run_container() {
  local lay=$1 h c=lb-$1 kc d0 d1 t1 t2
  h=$(mktemp -d)
  kc=$(up "$lay" "$h" "$c" --nodes 1) || { echo "layers-bench: create $c failed"; fails=$((fails + 1)); sudo rm -rf "$h"; return; }
  d0=$(kib $(files "$h"))
  t1=$(pull "$kc" "$c" first) || t1=""
  t2=$(pull "$kc" "$c-worker-1" second) || t2=""
  d1=$(kib $(files "$h"))
  report "$lay" "$h" "$t1" "$t2" $((d1 - d0))
  V "$lay" "$h" delete "$c" >/dev/null 2>&1 || { echo "layers-bench: delete $c failed"; fails=$((fails + 1)); }
  if sudo losetup -a | grep -q "$h/.vk8s/layers/"; then echo "layers-bench: a loop device still holds a layer image of $h"; fails=$((fails + 1)); fi
  stop_fillers; sudo rm -rf "$h" "$h.create.log"
}

run_native() {
  local lay=$1 h a=lba-$1 b=lbb-$1 kc d0 d1 t1 t2 dd=0
  h=$(mktemp -d)
  kc=$(up "$lay" "$h" "$a") || { echo "layers-bench: create $a failed"; fails=$((fails + 1)); rm -rf "$h"; return; }
  d0=$(kib $(files "$h" "$a"))
  t1=$(pull "$kc" "$(k "$kc" get nodes -o name | head -1 | sed 's|^node/||')" first) || t1=""
  d1=$(kib $(files "$h" "$a"))
  dd=$((d1 - d0))
  V "$lay" "$h" delete "$a" >/dev/null 2>&1 || { echo "layers-bench: delete $a failed"; fails=$((fails + 1)); }
  kc=$(up "$lay" "$h" "$b") || { echo "layers-bench: create $b failed"; fails=$((fails + 1)); rm -rf "$h"; return; }
  d0=$(kib $(files "$h" "$b"))
  t2=$(pull "$kc" "$(k "$kc" get nodes -o name | head -1 | sed 's|^node/||')" second) || t2=""
  d1=$(kib $(files "$h" "$b"))
  report "$lay" "$h" "$t1" "$t2" $((dd + d1 - d0))
  V "$lay" "$h" delete "$b" >/dev/null 2>&1 || { echo "layers-bench: delete $b failed"; fails=$((fails + 1)); }
  if sudo losetup -a | grep -q "$h/.vk8s/layers/"; then echo "layers-bench: a loop device still holds a layer image of $h"; fails=$((fails + 1)); fi
  stop_fillers; sudo rm -rf "$h" "$h.create.log"
}

report() {
  local lay=$1 h=$2 t1=$3 t2=$4 disk=$5 store n
  store=$(kib "$h/.vk8s/layers")
  n=$(sudo find "$h/.vk8s/layers" -maxdepth 1 -name '*.sqfs' 2>/dev/null | wc -l)
  [ -n "$t1" ] && [ -n "$t2" ] || { echo "layers-bench: a pod did not run (store $lay)"; fails=$((fails + 1)); }
  if [ "$lay" = on ] && [ "$n" = 0 ]; then echo "layers-bench: the store is on but holds no layer image"; fails=$((fails + 1)); fi
  rows="$rows| $lay | $(secs "${t1:-0}") | $(secs "${t2:-0}") | $(mib "$disk") | $(mib "$store") | $n |"$'\n'
  echo "layers-bench: backend=$backend store=$lay first_ms=${t1:-} second_ms=${t2:-} disk_kib=$disk store_kib=$store images=$n"
}

stop_fillers
for lay in off on; do "run_$backend" "$lay"; done
head="### Two nodes pulling $image ($backend backend, $(uname -m))"
table="| store | first pod s | second pod s | disk added MiB | of it the store MiB | layer images |"$'\n'"|---|---|---|---|---|---|"$'\n'"$rows"
echo "$head"; printf '%s' "$table"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then printf '%s\n\n%s\n' "$head" "$table" >> "$GITHUB_STEP_SUMMARY"; fi
[ $fails = 0 ] || { echo "layers-bench: $fails FAIL"; exit 1; }
