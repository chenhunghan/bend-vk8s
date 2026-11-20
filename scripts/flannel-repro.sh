#!/usr/bin/env bash
# Temporary (feat/flannel-crash): create the container regression's st
# cluster (--backend container --nodes 2 --backing-store etcd) N times
# and check that every flannel pod gets Ready. On the first failure,
# print flannel's logs, describe output and the node logs, and exit 1.
#   sudo env PATH=$PATH HOME=$HOME VK8S_ASSETS=... scripts/flannel-repro.sh N
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
export VK8S_IDLE_SLEEP=0
B=${VK8S:-out/vk8s}
n=${1:-6}
clusters=$HOME/.vk8s/clusters
c=st
export KUBECONFIG=$clusters/$c/kubeconfig.yaml
dump() {
  kubectl get pods -A -o wide 2>&1
  kubectl get nodes -o wide 2>&1
  kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" podCIDR="}{.spec.podCIDR}{" annotations="}{.metadata.annotations}{"\n"}{end}' 2>&1
  local p
  for p in $(kubectl -n kube-flannel get pods -o name 2>/dev/null); do
    echo "== kubectl describe -n kube-flannel $p"; kubectl -n kube-flannel describe "$p" 2>&1 | tail -n 60
    echo "== kubectl logs -n kube-flannel --previous $p"; kubectl -n kube-flannel logs --previous -c kube-flannel "$p" 2>&1 | tail -n 100
    echo "== kubectl logs -n kube-flannel $p"; kubectl -n kube-flannel logs --all-containers "$p" 2>&1 | tail -n 100
  done
  for p in $(kubectl -n kube-system get pods -o name 2>/dev/null); do
    case $p in *kube-proxy*) ;; *) continue ;; esac
    echo "== kubectl logs -n kube-system $p"; kubectl -n kube-system logs "$p" 2>&1 | tail -n 40
  done
  # every flannel container's log file on the nodes, the crashed ones too
  find "$clusters/$c" -path '*/pods/kube-flannel_kube-flannel-ds-*/kube-flannel/*.log' 2>/dev/null | while IFS= read -r f; do
    echo "== $f (last 60 lines)"; tail -n 60 "$f"
  done
  kubectl get events -A --sort-by=.lastTimestamp 2>&1 | tail -n 60
  # each node's view of the API's Service IP: kube-proxy's rules and the
  # tracked flows to it (an un-NATed SYN_SENT flow pins flanneld's dial)
  local ns
  for ns in $(ip netns list 2>/dev/null | awk '{print $1}' | grep "^vk8s-$c-"); do
    echo "== $ns: iptables-save -t nat"; ip netns exec "$ns" iptables-save -t nat 2>&1 | grep -v '^#'
    echo "== $ns: iptables-save -t filter"; ip netns exec "$ns" iptables-save -t filter 2>&1 | grep -v '^#'
    echo "== $ns: conntrack -L -d 10.96.0.1"; ip netns exec "$ns" conntrack -L -d 10.96.0.1 2>&1
    echo "== $ns: conntrack -L -p tcp --dport 6443"; ip netns exec "$ns" conntrack -L -p tcp --dport 6443 2>&1 | head -n 20
  done
  local f
  for f in "$clusters/$c"/console.log "$clusters/$c"/nodes/*/console.log "$clusters/$c"/share/logs/*.log "$clusters/$c"/nodes/*/share/logs/*.log; do
    [ -f "$f" ] || continue
    echo "== $f (last 120 lines)"; tail -n 120 "$f"
  done
}
for i in $(seq "$n"); do
  "$B" delete "$c" >/dev/null 2>&1
  t=$(date +%s)
  "$B" create "$c" --nodes 2 --backing-store etcd --backend container --connect=false > /tmp/repro-create.log 2>&1 || { tail -n 40 /tmp/repro-create.log; echo "== try $i: create failed"; exit 1; }
  ok=false
  end=$(( $(date +%s) + 300 ))
  while [ "$(date +%s)" -lt "$end" ]; do
    ready=$(kubectl -n kube-flannel get pods -o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready}{"\n"}{end}' 2>/dev/null | grep -c true)
    rs=$(kubectl -n kube-flannel get pods -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{"\n"}{end}' 2>/dev/null | awk '{s+=$1} END {print s+0}')
    if [ "$ready" = 3 ]; then ok=true; break; fi
    sleep 5
  done
  echo "== try $i: flannel ready=$ok after $(( $(date +%s) - t )) s, restarts $rs"
  if ! $ok; then dump; exit 1; fi
  # keep the cluster, as the regression does, and watch for a later crash
  end=$(( $(date +%s) + ${WATCH:-480} ))
  while [ "$(date +%s)" -lt "$end" ]; do
    rs=$(kubectl -n kube-flannel get pods -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{"\n"}{end}' 2>/dev/null | awk '{s+=$1} END {print s+0}')
    [ "${rs:-0}" = 0 ] || break
    sleep 10
  done
  echo "== try $i: flannel restarts $rs after $(( $(date +%s) - t )) s"
  # how long flanneld's init container waited for kube-proxy's rule
  for p in $(kubectl -n kube-flannel get pods -o name 2>/dev/null); do
    kubectl -n kube-flannel logs -c wait-kube-proxy "$p" 2>&1 | sed "s|^|== try $i: $p: |"
  done
  # the race itself: kube-proxy's sync that lost its chains
  for p in $(kubectl -n kube-system get pods -o name 2>/dev/null | grep kube-proxy); do
    kubectl -n kube-system logs "$p" 2>/dev/null | grep -A1 "Failed to ensure chain jumps" | sed "s|^|== try $i: $p: |"
  done
  if [ "${rs:-0}" != 0 ]; then echo "== try $i: flannel restarted"; sleep 30; dump; exit 1; fi
done
"$B" delete "$c" >/dev/null 2>&1
echo "== $n tries: flannel ready every time"
