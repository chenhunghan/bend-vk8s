#!/usr/bin/env bash
# Runs the CNCF Kubernetes conformance suite (sonobuoy) against a vk8s
# cluster: the integration gate behind the laws (docs/DESIGN.md).
#   scripts/conformance.sh [quick|non-disruptive-conformance|certified-conformance] [cluster]
# vcluster labels CoreDNS k8s-app=vcluster-kube-dns; sonobuoy's preflight is
# told so. Results land in out/conformance/.
set -euo pipefail
cd "$(dirname "$0")/.."
mode=${1:-certified-conformance}; name=${2:-conf}
export KUBECONFIG=$HOME/.vk8s/clusters/$name/share/kubeconfig.yaml
sono=${SONOBUOY:-out/tools/sonobuoy}
mkdir -p out/conformance
kubectl -n kube-system wait --for=condition=available deploy/coredns --timeout=300s
"$sono" delete --wait >/dev/null 2>&1 || true
"$sono" run --mode "$mode" --plugin e2e --wait --kubernetes-version "$(kubectl version -o json | python3 -c 'import sys,json;print(json.load(sys.stdin)["serverVersion"]["gitVersion"])')" \
  --dns-pod-labels k8s-app=vcluster-kube-dns
f=$("$sono" retrieve out/conformance)
"$sono" results "$f"
"$sono" results "$f" --mode detailed | python3 -c '
import sys, json
for l in sys.stdin:
    try: d = json.loads(l)
    except Exception: continue
    if d.get("status") == "failed": print("FAILED:", d.get("name"))'
