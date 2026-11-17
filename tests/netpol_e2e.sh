#!/usr/bin/env bash
# NetworkPolicy enforcement end to end (docs/GOAL.md section 10;
# src/guest/netpol.bend: kube-router's network policy controller beside
# flannel and kube-proxy, supervised by each node's PID 1):
#   1. in a fresh namespace, a busybox httpd pod (app=web) on SERVER_NODE
#      and a client pod (role=client) on CLIENT_NODE; the client fetches
#      the server's page by pod IP
#   2. a deny-all ingress policy (podSelector {}, policyTypes [Ingress]):
#      the fetch fails, and keeps failing
#   3. a policy that allows ingress to app=web from role=client on TCP
#      8080: the fetch works again
#   4. with NETPOL_MEASURE=1, a hostPID busybox pod on SERVER_NODE reads
#      kube-router's resident memory and its CPU time over 60 idle
#      seconds from /proc (the node's: a VM's, a node container's or the
#      host's), and prints a MEASURE line (also to $GITHUB_STEP_SUMMARY)
#   5. the namespace is deleted
# Shared by the container smoke (tests/container_smoke.sh) and the KVM
# smoke (scripts/smoke-linux.sh). The pods use NETPOL_IMAGE (default
# docker.io/library/busybox:1.36, the image the gVisor checks pull).
#
# usage: tests/netpol_e2e.sh SERVER_NODE CLIENT_NODE -- KUBECTL...
#   KUBECTL...  the command that runs kubectl for the cluster, such as
#               `sudo kubectl --kubeconfig K` or `vk8s connect NAME -- kubectl`
# Prints PASS/FAIL lines; exits 1 on any FAIL.
set -uo pipefail
[ $# -ge 4 ] && [ "$3" = -- ] || { sed -n 's/^# usage: //p' "$0"; exit 2; }
srv_node=$1 cli_node=$2
shift 3
kc=("$@")
ns=vk8s-netpol
img=${NETPOL_IMAGE:-docker.io/library/busybox:1.36}
fails=0
pass() { echo "PASS netpol: $*"; }
fail() { echo "FAIL netpol: $*"; fails=$((fails + 1)); }
k() { "${kc[@]}" "$@"; }
# until_ok SECONDS CMD...: CMD every 2 s until it succeeds
until_ok() { local end=$(( $(date +%s) + $1 )); shift; until "$@"; do [ "$(date +%s)" -lt "$end" ] || return 1; sleep 2; done; }
t() { local n=$1; shift; if "$@"; then pass "$n"; else fail "$n"; fi; }
# pod NAME NODE LABELS COMMAND...: a busybox pod on NODE
pod() {
  local n=$1 node=$2 labels=$3; shift 3
  local cmd; cmd=$(printf '"%s",' "$@"); cmd=${cmd%,}
  k -n "$ns" run "$n" --image="$img" --restart=Never --labels="$labels" \
    --overrides="{\"apiVersion\":\"v1\",\"spec\":{\"nodeName\":\"$node\",\"terminationGracePeriodSeconds\":1,\"containers\":[{\"name\":\"$n\",\"image\":\"$img\",\"command\":[$cmd]}]}}" >/dev/null
}
running() { [ "$(k -n "$ns" get pod "$1" -o 'jsonpath={.status.phase}' 2>/dev/null)" = Running ]; }
ip=""
reach() { k -n "$ns" exec client -- wget -q -T 3 -O - "http://$ip:8080/" 2>/dev/null | grep -q vk8s-netpol-ok; }
unreachable() { ! reach; }
# blocked SECONDS: no fetch gets through for that long (one every 2 s)
blocked() { local end=$(( $(date +%s) + $1 )); while [ "$(date +%s)" -lt "$end" ]; do reach && return 1; sleep 2; done; }
diag() {
  echo "--- netpol diagnostics"
  k -n "$ns" get pods,networkpolicies -o wide 2>&1
  k -n "$ns" describe pods 2>&1 | tail -n 40
}

k delete namespace "$ns" --ignore-not-found --wait=true >/dev/null 2>&1
t "namespace created" k create namespace "$ns"
pod web "$srv_node" app=web sh -c 'mkdir -p /w && echo vk8s-netpol-ok > /w/index.html && exec httpd -f -p 8080 -h /w'
pod client "$cli_node" role=client sleep 3600
t "the server pod runs on $srv_node" until_ok 600 running web
t "the client pod runs on $cli_node" until_ok 600 running client
ip=$(k -n "$ns" get pod web -o 'jsonpath={.status.podIP}')
echo "netpol: server at $ip"

# 1. no policy: reachable (the startup gate is open once kube-router synced)
t "no policy: the client reaches the server" until_ok 180 reach

# 2. deny all ingress in the namespace
k apply -f - >/dev/null <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
  namespace: $ns
spec:
  podSelector: {}
  policyTypes: [Ingress]
EOF
t "deny-all ingress: the server becomes unreachable" until_ok 60 unreachable
t "deny-all ingress: it stays unreachable (20 s)" blocked 20

# 3. allow the client in
k apply -f - >/dev/null <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-client
  namespace: $ns
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: client
    ports:
    - protocol: TCP
      port: 8080
EOF
t "allow policy: the client reaches the server again" until_ok 60 reach

# 4. kube-router's footprint on the server's node (USER_HZ is 100)
if [ "${NETPOL_MEASURE:-0}" = 1 ]; then
  k -n "$ns" run measure --image="$img" --restart=Never \
    --overrides="{\"apiVersion\":\"v1\",\"spec\":{\"nodeName\":\"$srv_node\",\"hostPID\":true,\"terminationGracePeriodSeconds\":1,\"containers\":[{\"name\":\"measure\",\"image\":\"$img\",\"command\":[\"sleep\",\"600\"]}]}}" >/dev/null
  # shellcheck disable=SC2016 # expanded by the pod's shell
  script='pid=""
for p in /proc/[0-9]*; do [ "$(cat "$p/comm" 2>/dev/null)" = kube-router ] && pid=${p#/proc/}; done
[ -n "$pid" ] || { echo "no kube-router process"; exit 1; }
rss=$(awk "/^VmRSS/ {print \$2}" "/proc/$pid/status")
t0=$(awk "{print \$14 + \$15}" "/proc/$pid/stat")
sleep 60
t1=$(awk "{print \$14 + \$15}" "/proc/$pid/stat")
awk -v r="$rss" -v d="$((t1 - t0))" "BEGIN { printf \"rss_mib=%.1f cpu_percent_of_one_core=%.2f (60 s idle)\\n\", r / 1024, d / 60 }"'
  if t "the measurement pod runs" until_ok 300 running measure; then
    m=$(k -n "$ns" exec measure -- sh -c "$script" 2>&1 | tail -n 1)
    echo "MEASURE kube-router on $srv_node: $m"
    [ -z "${GITHUB_STEP_SUMMARY:-}" ] || echo "MEASURE kube-router on $srv_node: $m" >> "$GITHUB_STEP_SUMMARY"
    t "kube-router runs on $srv_node" grep -q 'rss_mib=[0-9]' <<<"$m"
  fi
fi

[ $fails = 0 ] || diag
k delete namespace "$ns" --wait=false >/dev/null 2>&1
if [ $fails = 0 ]; then echo "netpol_e2e: OK"; else echo "netpol_e2e: $fails FAIL"; exit 1; fi
