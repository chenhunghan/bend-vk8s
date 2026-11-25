#!/usr/bin/env bash
# macOS (or a Linux KVM host): a VM node's layer images read from the pack
# disk against the layers share (docs/STATUS.md, "The pack disk";
# src/layers/pack.bend).
#   scripts/bench/pack-read.sh PAIRS
# One pair is one cluster with the pack and one with VK8S_PACK=0 (the
# share); the order alternates (pack,share then share,pack). A run:
# create a one-node VM cluster, wait for the node and CoreDNS, start a
# privileged pod (to drop the node's caches and list its loop devices),
# then time three nginx pods from `kubectl run` to Ready (the first
# mounts the image's layers; the others repeat), then three cold reads
# of the first pod's root file system (the node's page cache dropped
# before each; `tar` of / to a pipe, about 200 MB) and one warm read,
# then delete. Nothing is wiped: the image cache and the layer store
# keep the image after the first run, so the runs compare the node's
# read path, not a pull.
# Prints one CSV line per run on stdout; progress on stderr. A run
# whose loop devices do not read from where its mode says prints
# "wrong" in the backing column.
# It runs in the HOME it is given: with another HOME (a short path:
# macOS limits a Unix socket path to 103 bytes) nothing of ~/.vk8s is
# touched, but the image cache (ports 15001-15004) and the layer filler
# (port 32000) are one per machine: stop those of another vk8s first.
set -uo pipefail
cd "$(dirname "$0")/../.."
pairs=${1:?pairs}
v=$(cd "$(dirname "${VK8S_BIN:-out/vk8s}")" && pwd)/$(basename "${VK8S_BIN:-out/vk8s}")
export VK8S_IDLE_SLEEP=0
name=pk
image=docker.io/library/nginx@sha256:6784fb0834aa7dbbe12e3d7471e69c290df3e6ba810dc38b34ae33d3c1c05f7d
say() { echo "[$(date +%H:%M:%S)] $*" >&2; }
k() { "$v" connect "$name" -- kubectl "$@"; }
now() { perl -MTime::HiRes=time -e 'printf "%d\n", time*1000'; }

peek='{"apiVersion":"v1","kind":"Pod","metadata":{"name":"peek"},"spec":{"hostPID":true,"restartPolicy":"Never","terminationGracePeriodSeconds":0,
"containers":[{"name":"peek","image":"docker.io/library/busybox:1.36","command":["sleep","100000"],"securityContext":{"privileged":true}}]}}'

# pod NAME: ms from `kubectl run` to Ready
pod() {
  local t0; t0=$(now)
  k run "$1" --image="$image" --restart=Never >/dev/null
  k wait --for=condition=Ready "pod/$1" --timeout=300s >/dev/null
  echo $(( $(now) - t0 ))
}
# ms one read of pod a1's root file system takes, measured in the pod
read_ms() {
  k exec a1 -- sh -c 's=$(date +%s%N); tar -cf - --one-file-system / 2>/dev/null | cat >/dev/null; e=$(date +%s%N); echo $(( (e - s) / 1000000 ))'
}

run() { # run MODE
  local mode=$1 off="" t0 up first r2 r3 back c1 c2 c3 warm want
  [ "$mode" = share ] && off=0
  scripts/bench/guard.sh check >&2 || { say "short of room: stopping"; exit 1; }
  say "$mode: create"
  t0=$(now)
  VK8S_PACK=${off:-${VK8S_PACK:-}} "$v" create "$name" --connect=false >/dev/null 2>&1 || { say "create failed"; "$v" delete "$name" >/dev/null 2>&1; return 1; }
  k wait --for=condition=Ready node --all --timeout=300s >/dev/null
  until k -n kube-system wait --for=condition=Ready pod -l k8s-app=vcluster-kube-dns --timeout=300s >/dev/null 2>&1; do
    [ $(( $(now) - t0 )) -lt 300000 ] || break; sleep 0.5
  done
  up=$(( $(now) - t0 ))
  echo "$peek" | k apply -f - >/dev/null
  k wait --for=condition=Ready pod/peek --timeout=300s >/dev/null
  first=$(pod a1); r2=$(pod a2); r3=$(pod a3)
  back=$(k exec peek -- sh -c 'for l in /sys/block/loop*/loop; do cat $l/backing_file; done 2>/dev/null | sed "s/[0-9a-f]\{64\}/H/" | sort -u | tr "\n" " "')
  want=/dev/vd; [ "$mode" = share ] && want=/mnt/layers-store/
  case $back in "$want"*) ;; *) back="wrong:$back" ;; esac
  for i in 1 2 3; do
    k exec peek -- nsenter -t 1 -m -- /bin/busybox sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'
    eval "c$i=\$(read_ms)"
  done
  warm=$(read_ms)
  echo "$mode,$up,$first,$r2,$r3,$c1,$c2,$c3,$warm,${back% }"
  "$v" delete "$name" >/dev/null 2>&1
}

echo "mode,ready_ms,first_pod_ms,repeat_pod_ms,repeat_pod_ms,cold_read_ms,cold_read_ms,cold_read_ms,warm_read_ms,loop_backing"
for p in $(seq 0 $((pairs - 1))); do
  if [ $((p % 2)) = 0 ]; then run pack; run share; else run share; run pack; fi
done
