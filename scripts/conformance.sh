#!/usr/bin/env bash
# Runs the CNCF Kubernetes conformance suite (sonobuoy) against a vk8s
# cluster: the integration gate behind the laws (docs/DESIGN.md).
#   scripts/conformance.sh [quick|non-disruptive-conformance|certified-conformance] [cluster]
# vcluster labels CoreDNS k8s-app=vcluster-kube-dns; sonobuoy's preflight is
# told so. Results land in out/conformance/.
# E2E_SKIP, when set, is a Ginkgo regex of tests to skip (each such skip
# is a parity gap in docs/STATUS.md, and a run with one is not a valid
# certification submission). SONOBUOY_WAIT is the
# run's limit in minutes (default 1440). E2E_FOCUS, when set, is a
# Ginkgo regex that replaces the mode's selection (a debugging run, never
# a certification; E2E_SKIP still applies). When GITHUB_STEP_SUMMARY is set,
# the status and the passed, failed and skipped counts go there too.
# Exits non-zero unless the status is "passed" with 0 failed tests.
# Runs on macOS (bash 3.2) and Linux.
set -euo pipefail
cd "$(dirname "$0")/.."
mode=${1:-certified-conformance}; name=${2:-conf}
d=$HOME/.vk8s/clusters/$name; export KUBECONFIG=$d/kubeconfig.yaml; [ -f "$KUBECONFIG" ] || KUBECONFIG=$d/share/kubeconfig.yaml
# Sleep when idle must be off: the e2e pods talk to the API inside the
# cluster, not through the host forward, so the cluster would pause under
# them. Create the cluster with --idle-sleep 0 (or VK8S_IDLE_SLEEP=0).
export VK8S_IDLE_SLEEP=0
idle=$(sed -n 's/^IDLE_SLEEP=//p' "$d/cluster.env" 2>/dev/null | tail -n 1)
case ${idle:-0s} in
  0|0s) ;;
  *) echo "conformance: $name sleeps after ${idle} idle; create it with --idle-sleep 0"; exit 2 ;;
esac
sono=${SONOBUOY:-out/tools/sonobuoy}
mkdir -p out/conformance
kubectl -n kube-system wait --for=condition=available deploy/coredns --timeout=300s
# coredns has maxUnavailable 1, so the Deployment is Available before any
# pod exists; sonobuoy's preflight needs a CoreDNS pod
end=$(( $(date +%s) + 600 ))
until [ -n "$(kubectl -n kube-system get pods -l k8s-app=vcluster-kube-dns -o name 2>/dev/null)" ]; do
  [ "$(date +%s)" -lt "$end" ] || { echo "conformance: no CoreDNS pod after 10 min"; exit 1; }
  sleep 5
done
kubectl -n kube-system wait --for=condition=Ready pod -l k8s-app=vcluster-kube-dns --timeout=600s
"$sono" delete --wait >/dev/null 2>&1 || true
# sonobuoy refuses --mode together with --e2e-focus/--e2e-skip, so with
# E2E_SKIP the mode becomes its own focus and skip regexes (sonobuoy
# v0.57.5 cmd/sonobuoy/app/modes.go) and E2E_SKIP joins the skip.
sel=(--mode "$mode")
if [ -n "${E2E_SKIP:-}" ]; then
  case $mode in
    quick) focus='Pods should be submitted and removed'; mskip= ;;
    non-disruptive-conformance) focus='\[Conformance\]'; mskip='\[Disruptive\]|NoExecuteTaintManager' ;;
    certified-conformance) focus='\[Conformance\]'; mskip= ;;
    *) echo "conformance: E2E_SKIP does not support mode $mode"; exit 1 ;;
  esac
  sel=(--e2e-focus "$focus" --e2e-skip "${mskip:+$mskip|}$E2E_SKIP")
fi
if [ -n "${E2E_FOCUS:-}" ]; then
  sel=(--e2e-focus "$E2E_FOCUS")
  [ -z "${E2E_SKIP:-}" ] || sel+=(--e2e-skip "$E2E_SKIP")
  mode="focus"
fi
t0=$(date +%s)
"$sono" run "${sel[@]}" --plugin e2e --wait="${SONOBUOY_WAIT:-1440}" \
  --kubernetes-version "$(kubectl version -o json | python3 -c 'import sys,json;print(json.load(sys.stdin)["serverVersion"]["gitVersion"])')" \
  --dns-pod-labels k8s-app=vcluster-kube-dns
took=$(( ($(date +%s) - t0) / 60 ))
f=$("$sono" retrieve out/conformance | tail -1)
[ -f "$f" ] || { echo "conformance: no archive: $f"; exit 1; }
"$sono" results "$f" | tee out/conformance/results.txt
failed_names=$("$sono" results "$f" --mode detailed | python3 -c '
import sys, json
for l in sys.stdin:
    try: d = json.loads(l)
    except Exception: continue
    if d.get("status") == "failed": print("FAILED:", d.get("name"))')
[ -z "$failed_names" ] || echo "$failed_names"
field() { awk -F': *' -v k="$1" '$1 == k { print $2; exit }' out/conformance/results.txt; }
status=$(field Status); passed=$(field Passed); failed=$(field Failed); skipped=$(field Skipped)
verdict=FAIL
[ "$status" = passed ] && [ "${failed:-1}" = 0 ] && [ "${passed:-0}" -gt 0 ] && verdict=PASS
head="### vk8s $mode on $name ($(uname -sm)): $verdict"
body="| status | passed | failed | skipped | minutes | archive |"$'\n'"|---|---|---|---|---|---|"$'\n'"| ${status:-?} | ${passed:-?} | ${failed:-?} | ${skipped:-?} | $took | $(basename "$f") |"
echo "$head"; echo "$body"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    printf '%s\n\n%s\n' "$head" "$body"
    [ -z "${E2E_SKIP:-}" ] || printf '\nSkipped by E2E_SKIP: `%s`\n' "$E2E_SKIP"
    [ -z "$failed_names" ] || printf '\n```\n%s\n```\n' "$failed_names"
  } >> "$GITHUB_STEP_SUMMARY"
fi
[ "$verdict" = PASS ]
