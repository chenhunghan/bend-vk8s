#!/usr/bin/env zsh
# The focused conformance regression subset (out/conformance/regression-focus.txt,
# ~40 min) on a fresh standalone etcd cluster (st, 2 workers) and in classic
# mode (vc on host cluster hc, 2 workers), both at once. Use it while
# iterating; keep scripts/conformance.sh for certification.
#   VK8S=out/vk8s VK8S_ASSETS=... scripts/regression.sh
# Logs: out/reg-st.log, out/reg-vc.log. Results archives land in out/.
cd "$(dirname "$0")/.."
B=${VK8S:-out/vk8s}
F="$(cat out/conformance/regression-focus.txt)"
sono=${SONOBUOY:-out/tools/sonobuoy}
for c in vc hc st; do $B delete $c >/dev/null 2>&1; done
run() {
  c=$1; export KUBECONFIG=$HOME/.vk8s/clusters/$c/kubeconfig.yaml
  kubectl -n kube-system wait --for=condition=available deploy/coredns --timeout=600s
  s=$(date +%s)
  $sono run --namespace sono-$c --plugin e2e --e2e-focus "$F" --e2e-skip '\[Disruptive\]' \
    --dns-pod-labels k8s-app=vcluster-kube-dns --kubernetes-version v1.36.6 --wait=120 --wait-output silent
  echo "== $c took $(( ($(date +%s) - s) / 60 )) min"
  r=$($sono retrieve --namespace sono-$c out/ 2>&1 | tail -1); echo "archive $r"
  $sono results "$r" | grep -E "Status|Passed|Failed"
  $sono results "$r" --mode detailed | python3 -c '
import sys, json
for l in sys.stdin:
    try: d = json.loads(l)
    except Exception: continue
    if d.get("status") == "failed": print("FAILED:", d.get("name"))'
}
$B create st --nodes 2 --backing-store etcd --connect=false 2>&1 | grep -E "Success|rror"
$B create hc --nodes 2 --connect=false 2>&1 | grep -E "Success|rror"
( run st ) > out/reg-st.log 2>&1 &
( $B create vc --host-kubeconfig $HOME/.vk8s/clusters/hc/kubeconfig.yaml -f docs/examples/conformance-classic.yaml --connect=false 2>&1 | grep -E "Success|rror"
  until KUBECONFIG=$HOME/.vk8s/clusters/vc/kubeconfig.yaml kubectl get sa default >/dev/null 2>&1; do sleep 5; done
  run vc ) > out/reg-vc.log 2>&1 &
wait
cat out/reg-st.log out/reg-vc.log
