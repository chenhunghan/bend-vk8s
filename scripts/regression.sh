#!/usr/bin/env bash
# The focused conformance regression subset (~40 min) on a fresh standalone
# etcd cluster (st, 2 workers) and in classic mode (vc on host cluster hc,
# 2 workers), both at once by default. Use it while iterating; keep
# scripts/conformance.sh for certification.
#   VK8S=out/vk8s VK8S_ASSETS=... scripts/regression.sh
#   MODES=standalone scripts/regression.sh   (or classic; default both)
#   VK8S_BACKEND=container MODES=standalone scripts/regression.sh
#   VK8S_BACKEND=native MODES=standalone scripts/regression.sh
# VK8S_BACKEND picks the backend of the clusters it creates: vm (the
# default), container (`vk8s create --backend container`) or native
# (one host node, no worker VMs: `--nodes N` is refused, so st gets no
# --nodes; standalone only). Container
# mode supports standalone only (no --host-kubeconfig, no -f), so classic
# is refused there. On Linux container mode runs vk8s as root: the script
# starts itself again under sudo, with the variables it reads and HOME
# kept; on macOS (and with VK8S_NODE_HOST=vm) the nodes run in the
# node-host VM and need no root.
# Runs on macOS (bash 3.2) and Linux. SONOBUOY is the sonobuoy binary
# (default out/tools/sonobuoy). FOCUS_FILE is the focus list: one Ginkgo
# regex per line, # comments; default out/conformance/regression-focus.txt
# when it exists, else scripts/regression-focus.txt (whose lines get
# .*\[Conformance\] added).
# Logs: out/reg-st.log, out/reg-vc.log. Results archives land in out/.
# Prints a table of timings and results (also to $GITHUB_STEP_SUMMARY when
# set). Exits non-zero when a mode fails to start, or its run is not
# "passed" with 0 failed tests.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
# Sleep when idle stays off: the suite's traffic runs inside the cluster,
# not through the host API forward (docs/GOAL.md section 10).
export VK8S_IDLE_SLEEP=0
B=${VK8S:-out/vk8s}
sono=${SONOBUOY:-out/tools/sonobuoy}
MODES=${MODES:-standalone classic}
backend=${VK8S_BACKEND:-vm}
case $backend in
  vm) bargs="--backend vm" ;;
  container) bargs="--backend container" ;;
  native) bargs="--backend native" ;;
  *) echo "regression: unknown VK8S_BACKEND $backend (vm, container, native)"; exit 2 ;;
esac
if [ "$backend" = container ] && [ "$(uname -s)" = Linux ] && [ "${VK8S_NODE_HOST:-}" != vm ] && [ "$(id -u)" != 0 ]; then
  # sudo on GitHub's runners refuses --preserve-env, so pass the
  # variables the script reads by name
  keep=("PATH=$PATH" "HOME=$HOME" "MODES=$MODES" "VK8S_BACKEND=$backend" "VK8S_IDLE_SLEEP=0")
  for v in VK8S VK8S_ASSETS SONOBUOY FOCUS_FILE GITHUB_STEP_SUMMARY; do
    [ -n "${!v:-}" ] && keep+=("$v=${!v}")
  done
  exec sudo env "${keep[@]}" bash "$0" "$@"
fi
clusters=$HOME/.vk8s/clusters
focus=${FOCUS_FILE:-}
if [ -z "$focus" ]; then
  if [ -f out/conformance/regression-focus.txt ]; then focus=out/conformance/regression-focus.txt
  else focus=scripts/regression-focus.txt; fi
fi
[ -f "$focus" ] || { echo "regression: no focus list at $focus"; exit 2; }
[ -x "$sono" ] || { echo "regression: no sonobuoy at $sono (set SONOBUOY)"; exit 2; }
command -v kubectl >/dev/null || { echo "regression: no kubectl on PATH"; exit 2; }
suffix=
case $focus in scripts/*) suffix='.*\[Conformance\]' ;; esac
F=$(grep -v -e '^#' -e '^[[:space:]]*$' "$focus" | while IFS= read -r l; do printf '%s%s\n' "$l" "$suffix"; done | paste -s -d '|' -)
st=false; cl=false
for m in $MODES; do
  case $m in
    standalone) st=true ;;
    classic) cl=true
      [ "$backend" = vm ] || { echo "regression: classic mode needs the vm backend (--backend $backend has no --host-kubeconfig)"; exit 2; } ;;
    *) echo "regression: unknown mode $m (standalone, classic)"; exit 2 ;;
  esac
done
st_args="--nodes 2 --backing-store etcd"
skip='\[Disruptive\]'
# native: one node, so skip the focused test that needs two ("Conformance
# test suite needs a cluster with at least 2 nodes", daemon_set.go:451)
if [ "$backend" = native ]; then
  st_args="--backing-store etcd"
  skip="$skip|should rollback without unnecessary restarts"
fi
mkdir -p out
echo "regression: modes: $MODES; backend: $backend; focus: $focus ($(grep -c -v -e '^#' -e '^[[:space:]]*$' "$focus") lines); $("$B" version 2>&1 | head -1) on $(uname -sm)"

secs() { echo $(( $(date +%s) - $1 )); }
mins() { awk -v s="$1" 'BEGIN { printf "%.1f", s / 60 }'; }
# each mode writes its table rows to out/reg-<cluster>.sum
row() { printf '| %s | %s | %s |\n' "$1" "$2" "$3" >> "out/reg-$c.sum"; echo "== $c: $2: $3"; }
# create CLUSTER ARGS...: vk8s create, timed; fails on error
create() {
  local c=$1; shift
  local t; t=$(date +%s)
  # shellcheck disable=SC2086 # bargs is empty or two words
  "$B" create "$c" "$@" $bargs --connect=false > "out/reg-$c-create.log" 2>&1
  local rc=$?
  grep -E "Success|rror" "out/reg-$c-create.log"
  row "$c" "create" "$(mins "$(secs "$t")") min"
  [ $rc = 0 ] || { tail -n 40 "out/reg-$c-create.log"; echo "== $c: create failed ($rc)"; return 1; }
}
dump() {
  echo "== $c: pods"; kubectl get pods -A -o wide 2>&1 | tail -n 60
  echo "== vk8s list"; "$B" list 2>&1
}
run() {
  c=$1; export KUBECONFIG=$clusters/$c/kubeconfig.yaml
  # coredns has maxUnavailable 1, so the Deployment is Available before
  # any pod exists; sonobuoy's preflight needs a CoreDNS pod
  local end=$(( $(date +%s) + 600 ))
  until [ -n "$(kubectl -n kube-system get pods -l k8s-app=vcluster-kube-dns -o name 2>/dev/null)" ]; do
    [ "$(date +%s)" -lt "$end" ] || { echo "== $c: no CoreDNS pod after 10 min"; dump; return 1; }
    sleep 5
  done
  kubectl -n kube-system wait --for=condition=Ready pod -l k8s-app=vcluster-kube-dns --timeout=600s || { dump; return 1; }
  local s; s=$(date +%s)
  "$sono" run --namespace "sono-$c" --plugin e2e --e2e-focus "$F" --e2e-skip "$skip" \
    --dns-pod-labels k8s-app=vcluster-kube-dns --kubernetes-version v1.36.6 --wait=120 --wait-output silent
  local took; took=$(secs "$s")
  echo "== $c took $(( took / 60 )) min"
  row "$c" "sonobuoy run" "$(mins "$took") min"
  local r; r=$("$sono" retrieve --namespace "sono-$c" out/ 2>&1 | tail -1); echo "archive $r"
  [ -f "$r" ] || { row "$c" "result" "no archive: $r"; dump; return 1; }
  "$sono" results "$r" > "out/reg-$c.results" 2>&1
  grep -E "Status|Passed|Failed" "out/reg-$c.results"
  "$sono" results "$r" --mode detailed | python3 -c '
import sys, json
for l in sys.stdin:
    try: d = json.loads(l)
    except Exception: continue
    if d.get("status") == "failed": print("FAILED:", d.get("name"))'
  local status passed failed
  status=$(awk -F': *' '$1 == "Status" { print $2; exit }' "out/reg-$c.results")
  passed=$(awk -F': *' '$1 == "Passed" { print $2; exit }' "out/reg-$c.results")
  failed=$(awk -F': *' '$1 == "Failed" { print $2; exit }' "out/reg-$c.results")
  row "$c" "result" "${status:-?}, ${passed:-?} passed, ${failed:-?} failed ($(basename "$r"))"
  [ "$status" = passed ] && [ "${failed:-1}" = 0 ] && [ "${passed:-0}" -gt 0 ] || { dump; return 1; }
}
classic() {
  local t; t=$(date +%s)
  c=vc
  "$B" create vc --backend vm --host-kubeconfig "$clusters/hc/kubeconfig.yaml" -f docs/examples/conformance-classic.yaml --connect=false > out/reg-vc-create.log 2>&1
  local rc=$?
  grep -E "Success|rror" out/reg-vc-create.log
  [ $rc = 0 ] || { tail -n 40 out/reg-vc-create.log; row vc "create" "failed ($rc)"; return 1; }
  local end=$(( $(date +%s) + 900 ))
  until KUBECONFIG=$clusters/vc/kubeconfig.yaml kubectl get sa default >/dev/null 2>&1; do
    [ "$(date +%s)" -lt "$end" ] || { row vc "create" "no default ServiceAccount after 15 min"; return 1; }
    sleep 5
  done
  row vc "create (until the default ServiceAccount)" "$(mins "$(secs "$t")") min"
  run vc
}

t0=$(date +%s)
del=; $st && del="st"; $cl && del="$del vc hc"
for c in $del; do "$B" delete "$c" >/dev/null 2>&1; done
rm -f out/reg-st.sum out/reg-vc.sum out/reg-hc.sum out/reg-st.log out/reg-vc.log
fail=0
st_ok=false; hc_ok=false
# shellcheck disable=SC2086 # st_args splits into flags
if $st; then c=st; create st $st_args && st_ok=true; fi
if $cl; then c=hc; create hc --nodes 2 && hc_ok=true; fi
pid_st=; pid_vc=
if $st_ok; then ( run st ) > out/reg-st.log 2>&1 & pid_st=$!; elif $st; then fail=1; fi
if $hc_ok; then ( classic ) > out/reg-vc.log 2>&1 & pid_vc=$!; elif $cl; then fail=1; fi
[ -z "$pid_st" ] || wait "$pid_st" || fail=1
[ -z "$pid_vc" ] || wait "$pid_vc" || fail=1
for f in out/reg-st.log out/reg-vc.log; do [ -f "$f" ] && cat "$f"; done

verdict=PASS; [ $fail = 0 ] || verdict=FAIL
head="### vk8s regression subset on $(uname -m), $backend backend: $verdict ($MODES, $(mins "$(secs "$t0")") min in all)"
table="| cluster | step | result |"$'\n'"|---|---|---|"$'\n'"$(cat out/reg-st.sum out/reg-hc.sum out/reg-vc.sum 2>/dev/null)"
echo "$head"; echo "$table"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then printf '%s\n\n%s\n' "$head" "$table" >> "$GITHUB_STEP_SUMMARY"; fi
exit $fail
