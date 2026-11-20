#!/usr/bin/env bash
# macOS: cold and warm pulls with the shared layer store on against off
# (docs/GOAL.md section 10, "Shared image layers on by default";
# docs/ref/bench-plan.md scenario 10; W7 of
# docs/ref/explore-layers-autofill.md).
#   scripts/bench/cold-pull.sh PAIRS [NODES=3] [STATE=3]
# PAIR0 (env, default 0) numbers the first pair, so a run cut short
# (a reboot) goes on where it stopped and keeps the alternating order;
# NOHEADER=1 leaves out the CSV header line.
# One pair is one run with VK8S_LAYERS=1 and one without; the order
# alternates (on,off then off,on). STATE 3: the image cache, the layer
# store, its refs and the host OCI blobs are emptied before every run
# (nothing cached anywhere). STATE 4: the image cache stays warm (one
# unmeasured warm-up run fills it), the store and the nodes are cold.
# A run: create a cluster of NODES nodes (1 control plane + NODES-1
# workers, VM mode), time it until every node is Ready and every system
# pod (coredns, flannel, kube-proxy) runs, then for each workload image
# a Deployment of NODES replicas spread over the nodes, timed from apply
# to Available. Then host disk of the store, the blobs, the cache and
# the cluster, the summed phys_footprint of the cluster's VMMs, and a
# delete.
# Prints one CSV line per run on stdout; progress on stderr.
# The gate (GOAL): per image, the median over pairs of on/off is at most
# 1.10. Noise margin, declared before the runs: 10% (the paired spread
# of create time in VM mode measured for scripts/bench/mode-footprint.sh).
set -uo pipefail
cd "$(dirname "$0")/../.."
pairs=${1:?pairs}; nodes=${2:-3}; state=${3:-3}
v=${VK8S_BIN:-out/vk8s}; export VK8S_IDLE_SLEEP=0
V=$HOME/.vk8s
name=cp$nodes
say() { echo "[$(date +%H:%M:%S)] $*" >&2; }
k() { "$v" connect "$name" -- kubectl "$@"; }
now() { python3 -c 'import time;print(int(time.monotonic()*1000))'; }

# Pinned by index digest (resolved 2026-11-19).
images="busybox=docker.io/library/busybox@sha256:73aaf090f3d85aa34ee199857f03fa3a95c8ede2ffd4cc2cdb5b94e566b11662
nginx=docker.io/library/nginx@sha256:6784fb0834aa7dbbe12e3d7471e69c290df3e6ba810dc38b34ae33d3c1c05f7d
redis=docker.io/library/redis@sha256:7f7d30b7fdd09467bac58198a1f166dd69789d348d4fe859cccb20e0cf287fbe"

filler_stop() { pkill -f "layers serve" 2>/dev/null; sleep 1; }
store_empty() { rm -rf "$V/layers" "$V/layer-refs" "$V/layer-locks" "$V/oci"; rm -f "$V/layers-serve.log"; }
cache_empty() { "$v" cache stop >/dev/null 2>&1; rm -f "$V/cache/data.img"; }

reset() {
  "$v" delete "$name" >/dev/null 2>&1
  filler_stop; store_empty
  [ "$state" = 3 ] && cache_empty
  sync
}

# any vk8s binary name (out/vk8s, a test build): match its vmm subcommand
pids() { pgrep -f " vmm .*$V/clusters/$name/" | tr '\n' ' '; }
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
du_mib() { local d; for d in "$@"; do [ -e "$d" ] && du -sk "$d"; done | awk '{s+=$1} END {printf "%d", s/1024}'; }

# Deployment of NODES replicas, one per node, ms from apply to Available
deploy_ms() {
  local short=$1 ref=$2 t0 t1
  t0=$(now)
  cat <<EOF | k apply -f - >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata: {name: $short}
spec:
  replicas: $nodes
  selector: {matchLabels: {app: $short}}
  template:
    metadata: {labels: {app: $short}}
    spec:
      topologySpreadConstraints:
      - {maxSkew: 1, topologyKey: kubernetes.io/hostname, whenUnsatisfiable: DoNotSchedule, labelSelector: {matchLabels: {app: $short}}}
      containers:
      - name: c
        image: $ref
        command: $( [ "$short" = busybox ] && echo '["sleep", "3600"]' || echo '[]' )
EOF
  if k wait --for=condition=Available "deploy/$short" --timeout=600s >/dev/null 2>&1; then
    t1=$(now); echo $((t1 - t0))
  else
    echo timeout
  fi
}

run() {
  local mode=$1 t0 t1 create row img short ref
  reset
  if [ "$mode" = on ]; then export VK8S_LAYERS=1; else export VK8S_LAYERS=0; fi
  say "run $mode: create $name ($nodes nodes, state $state)"
  t0=$(now)
  "$v" create "$name" --nodes $((nodes - 1)) --backend vm --connect=false >/dev/null || { say "create failed"; echo "$mode,$nodes,$state,create_failed"; return; }
  until [ "$(k get nodes --no-headers 2>/dev/null | grep -cw Ready)" = "$nodes" ]; do sleep 1; done
  until n=$(k get pods -A --no-headers 2>/dev/null) && [ -n "$n" ] && ! echo "$n" | grep -qv Running; do sleep 1; done
  t1=$(now); create=$((t1 - t0))
  say "run $mode: ready in $create ms"
  row="$mode,$nodes,$state,$create"
  while IFS== read -r short ref; do
    row="$row,$(deploy_ms "$short" "$ref")"
    say "run $mode: $short done"
  done <<<"$images"
  row="$row,$(fp_mib),$(du_mib "$V/layers"),$(du_mib "$V/oci"),$(du_mib "$V/cache"),$(du_mib "$V/clusters/$name")"
  pub=$(grep -c 'ok published' "$V/layers-serve.log" 2>/dev/null); no=$(grep -c ': no ' "$V/layers-serve.log" 2>/dev/null)
  row="$row,${pub:-0},${no:-0}"
  echo "$row"
  "$v" delete "$name" >/dev/null 2>&1
  unset VK8S_LAYERS
}

if [ "$state" = 4 ]; then
  say "state 4: warm the image cache (unmeasured)"
  state=3 run off >/dev/null
fi
[ -n "${NOHEADER:-}" ] || echo "mode,nodes,state,ready_ms,busybox_ms,nginx_ms,redis_ms,footprint_mib,layers_mib,oci_mib,cache_mib,cluster_mib,published,refused"
i=${PAIR0:-0}; end=$((i + pairs))
while [ $i -lt "$end" ]; do
  if [ $((i % 2)) = 0 ]; then run on; run off; else run off; run on; fi
  i=$((i + 1))
done
reset
