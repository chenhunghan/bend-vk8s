#!/usr/bin/env bash
# NetworkPolicy enforcement end to end (docs/GOAL.md section 10;
# src/guest/netpol.bend: kube-router's network policy controller beside
# flannel and kube-proxy, supervised by each node's PID 1):
#   1. in a fresh namespace, a busybox httpd pod (app=web) on SERVER_NODE
#      behind a Service `web` (port 80 to 8080), and three clients:
#      `client` (role=client) on CLIENT_NODE, `local` (role=client) on
#      SERVER_NODE, `other` (no role) on CLIENT_NODE. Four paths reach
#      the page: client to the pod IP (across the nodes, routed in on the
#      server node's LAN interface), client to the Service (kube-proxy's
#      DNAT on the client's node first), local to the pod IP (the same
#      bridge, through br_netfilter), other to the pod IP
#   2. a privileged hostNetwork probe pod on each node looks at the
#      node itself (its root at /host, its processes): kube-router runs;
#      on the server node, FORWARD jumps to KUBE-ROUTER-FORWARD first,
#      KUBE-ROUTER-FORWARD sends the server's IP to its KUBE-POD-FW
#      chain, the IP is in the kube-router-local-pods ipset, and PID 1
#      opened the startup gate
#   3. a deny-all ingress policy (podSelector {}, policyTypes [Ingress]):
#      every path fails, and keeps failing
#   4. a policy that allows ingress to app=web from role=client on TCP
#      8080: client (pod IP and Service) and local get through again,
#      other stays blocked
#   5. with NETPOL_MEASURE=1, the server node's probe reads kube-router's
#      resident memory and its CPU time over 60 idle seconds from /proc
#      (the node's: a VM's, a node container's or the host's), and prints
#      a MEASURE line (also to $GITHUB_STEP_SUMMARY)
#   6. on any FAIL, each node's netfilter state, ipsets, gate marker and
#      kube-router log; then the namespace is deleted
# SERVER_NODE and CLIENT_NODE may be the same node (a single-node
# cluster). Shared by the container smoke (tests/container_smoke.sh) and
# the KVM smoke (scripts/smoke-linux.sh). The pods use NETPOL_IMAGE
# (default docker.io/library/busybox:1.36, the image the gVisor checks
# pull).
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
# probe NAME NODE: the node's own view (root at /host, its PIDs, its network)
probe() {
  k -n "$ns" run "$1" --image="$img" --restart=Never --labels=role=probe \
    --overrides="{\"apiVersion\":\"v1\",\"spec\":{\"nodeName\":\"$2\",\"hostNetwork\":true,\"hostPID\":true,\"terminationGracePeriodSeconds\":1,\"tolerations\":[{\"operator\":\"Exists\"}],\"volumes\":[{\"name\":\"root\",\"hostPath\":{\"path\":\"/\"}}],\"containers\":[{\"name\":\"probe\",\"image\":\"$img\",\"command\":[\"sleep\",\"3600\"],\"securityContext\":{\"privileged\":true},\"volumeMounts\":[{\"name\":\"root\",\"mountPath\":\"/host\"}]}]}}" >/dev/null
}
running() { [ "$(k -n "$ns" get pod "$1" -o 'jsonpath={.status.phase}' 2>/dev/null)" = Running ]; }
ip=""
# get FROM URL: FROM fetches the page
get() { k -n "$ns" exec "$1" -- wget -q -T 3 -O - "$2" 2>/dev/null | grep -q vk8s-netpol-ok; }
# the four paths, as "FROM URL" (ip is known once the server runs)
paths() { printf '%s\n' "client http://$ip:8080/" "client http://web/" "local http://$ip:8080/" "other http://$ip:8080/"; }
path_name() { case "$1 $2" in "client http://web/") echo "client to the Service (DNAT on $cli_node)" ;;
  client*) echo "client to the pod IP ($cli_node to $srv_node)" ;;
  local*) echo "local to the pod IP (on $srv_node)" ;;
  other*) echo "other (no role) to the pod IP ($cli_node to $srv_node)" ;; esac; }
reach() { get "$1" "$2"; }
unreachable() { ! get "$1" "$2"; }
# blocked SECONDS FROM URL...: no fetch gets through for that long
blocked() {
  local end=$(( $(date +%s) + $1 )); shift
  while [ "$(date +%s)" -lt "$end" ]; do
    local i=1
    while [ $i -lt $# ]; do
      local from=${!i}; local j=$((i + 1)); local url=${!j}
      get "$from" "$url" && { echo "netpol: $from got $url"; return 1; }
      i=$((i + 2))
    done
    sleep 2
  done
}

# --- What runs in a probe pod (busybox, privileged, hostPID, the node's
# root at /host). x CMD ARGS: the node's own CMD (iptables-save, ipset),
# run in the node's root.
# shellcheck disable=SC2016 # expanded by the probe's shell
node_lib='x() { c=$1; shift; for d in /usr/sbin /sbin /usr/bin /bin; do
  [ -x "/host$d/$c" ] && { chroot /host "$d/$c" "$@"; return; }; done; echo "no $c on the node"; return 127; }
krpid() { for p in /proc/[0-9]*; do [ "$(cat "$p/comm" 2>/dev/null)" = kube-router ] && echo "${p#/proc/}"; done; }'
nsh() { k -n "$ns" exec "$1" -- sh -c "$node_lib
$2" 2>&1; }
probe_of() { if [ "$1" = "$srv_node" ]; then echo probe-srv; else echo probe-cli; fi; }
kr_runs() { [ -n "$(nsh "$(probe_of "$1")" 'krpid')" ]; }
# FORWARD (filter) jumps to KUBE-ROUTER-FORWARD, and no rule before the
# jump accepts (or hands to flannel's FLANNEL-FWD, which accepts the pod
# CIDR): pod traffic meets kube-router's chains first
fwd_first() { nsh probe-srv 'x iptables-save -t filter' | awk '/^-A FORWARD / {
  if ($0 ~ /-j KUBE-ROUTER-FORWARD/) { ok = 1; exit } if ($0 ~ /-j (ACCEPT|FLANNEL-FWD)/) exit }
  END { exit !ok }'; }
fwd_pod() { nsh probe-srv 'x iptables-save -t filter' | grep '^-A KUBE-ROUTER-FORWARD ' | grep -v physdev | grep -q -- "-d $ip/32 .*-j KUBE-POD-FW-"; }
in_ipset() { nsh probe-srv 'x ipset list kube-router-local-pods' | grep -qx "$ip\( timeout 0\)\?"; }
gate_open() { nsh probe-srv 'cat /host/var/lib/vcluster/netpol/gate 2>/dev/null || echo "no gate marker (native: the data dir differs)"' | grep -qE '^open$|no gate marker'; }

# diag: on any FAIL, every node's own state, with no manual step. A
# probe that does not run is described (and its node), not skipped.
diag() {
  echo "--- netpol diagnostics"
  k get nodes -o wide 2>&1
  k -n "$ns" get pods,services,endpointslices,networkpolicies -o wide 2>&1
  local p node
  for p in probe-srv probe-cli; do
    if [ "$p" = probe-srv ]; then node=$srv_node; else node=$cli_node; fi
    [ "$p" = probe-cli ] && [ "$cli_node" = "$srv_node" ] && continue
    if ! running "$p"; then
      echo "--- $p on $node does not run: no view of the node's netfilter"
      k -n "$ns" describe pod "$p" 2>&1 | tail -n 30
      k describe node "$node" 2>&1 | sed -n '/^Conditions:/,/^Addresses:/p'
      continue
    fi
    echo "--- $p on $node: the node's netfilter, ipsets, gate and kube-router"
    nsh "$p" 'echo "== kube-router pids: $(krpid | tr "\n" " ")"
echo "== filter FORWARD, KUBE-ROUTER-FORWARD (packet counts)"
x iptables -w -L FORWARD -n -v --line-numbers
x iptables -w -L KUBE-ROUTER-FORWARD -n -v --line-numbers
echo "== filter: pod chains and policy chains"
x iptables-save -t filter | grep -E "^(:|-A )(KUBE-POD-FW|KUBE-NWPLCY|KUBE-ROUTER)" | head -n 120
echo "== mangle (the startup gate)"
x iptables-save -t mangle | grep -E "VK8S|^\*|^:FORWARD|^:INPUT"
echo "== gate marker: $(cat /host/var/lib/vcluster/netpol/gate 2>/dev/null)"
echo "== ipsets"; x ipset list -n
x ipset list kube-router-local-pods
echo "== routes"; ip route 2>/dev/null
for pid in $(krpid); do echo "== kube-router $pid: $(tr "\0" " " < /proc/$pid/cmdline)"
  [ -f /proc/$pid/fd/2 ] && tail -n 40 /proc/$pid/fd/2; done
echo "== kube-router log (PID 1 appends it; it stays when kube-router exited)"
l=/host/var/log/kube-router.log
if [ -f $l ]; then tail -n 60 $l; else echo "no $l (native: the logs dir differs)"; fi'
  done
}

k delete namespace "$ns" --ignore-not-found --wait=true >/dev/null 2>&1
t "namespace created" k create namespace "$ns"
k label namespace "$ns" pod-security.kubernetes.io/enforce=privileged >/dev/null 2>&1
pod web "$srv_node" app=web sh -c 'mkdir -p /w && echo vk8s-netpol-ok > /w/index.html && exec httpd -f -p 8080 -h /w'
pod client "$cli_node" role=client sleep 3600
pod local "$srv_node" role=client sleep 3600
pod other "$cli_node" role=other sleep 3600
probe probe-srv "$srv_node"
[ "$cli_node" = "$srv_node" ] || probe probe-cli "$cli_node"
k -n "$ns" expose pod web --name=web --port=80 --target-port=8080 >/dev/null
t "the server pod runs on $srv_node" until_ok 600 running web
for p in client other; do t "pod $p runs on $cli_node" until_ok 600 running "$p"; done
t "pod local runs on $srv_node" until_ok 600 running local
t "the probe runs on $srv_node" until_ok 300 running probe-srv
[ "$cli_node" = "$srv_node" ] || t "the probe runs on $cli_node" until_ok 300 running probe-cli
ip=$(k -n "$ns" get pod web -o 'jsonpath={.status.podIP}')
echo "netpol: server at $ip"
mapfile -t all < <(paths)

# 1. no policy: every path gets through (the startup gate is open once
#    kube-router synced)
for pth in "${all[@]}"; do
  read -r from url <<<"$pth"
  t "no policy: $(path_name "$from" "$url") gets through" until_ok 180 reach "$from" "$url"
done

# 2. the nodes themselves
t "kube-router runs on $srv_node" kr_runs "$srv_node"
[ "$cli_node" = "$srv_node" ] || t "kube-router runs on $cli_node" kr_runs "$cli_node"
t "$srv_node: FORWARD jumps to KUBE-ROUTER-FORWARD before any ACCEPT" until_ok 60 fwd_first
t "$srv_node: KUBE-ROUTER-FORWARD sends $ip to its pod chain" until_ok 60 fwd_pod
t "$srv_node: $ip is in the kube-router-local-pods ipset" until_ok 60 in_ipset
t "$srv_node: PID 1 opened the startup gate" gate_open

# 3. deny all ingress in the namespace
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
for pth in "${all[@]}"; do
  read -r from url <<<"$pth"
  t "deny-all ingress: $(path_name "$from" "$url") is blocked" until_ok 60 unreachable "$from" "$url"
done
# shellcheck disable=SC2086 # the paths split into FROM URL pairs
t "deny-all ingress: every path stays blocked (20 s)" blocked 20 ${all[*]}

# 4. allow role=client in
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
for pth in "${all[@]}"; do
  read -r from url <<<"$pth"
  [ "$from" = other ] && continue
  t "allow policy: $(path_name "$from" "$url") gets through again" until_ok 60 reach "$from" "$url"
done
t "allow policy: other (no role=client) stays blocked (10 s)" blocked 10 other "http://$ip:8080/"

# 5. kube-router's footprint on the server's node (USER_HZ is 100)
if [ "${NETPOL_MEASURE:-0}" = 1 ]; then
  # shellcheck disable=SC2016 # expanded by the probe's shell
  script='pid=$(krpid | head -n 1)
[ -n "$pid" ] || { echo "no kube-router process"; exit 1; }
rss=$(awk "/^VmRSS/ {print \$2}" "/proc/$pid/status")
t0=$(awk "{print \$14 + \$15}" "/proc/$pid/stat")
sleep 60
t1=$(awk "{print \$14 + \$15}" "/proc/$pid/stat")
awk -v r="$rss" -v d="$((t1 - t0))" "BEGIN { printf \"rss_mib=%.1f cpu_percent_of_one_core=%.2f (60 s idle)\\n\", r / 1024, d / 60 }"'
  m=$(nsh probe-srv "$script" | tail -n 1)
  echo "MEASURE kube-router on $srv_node: $m"
  [ -z "${GITHUB_STEP_SUMMARY:-}" ] || echo "MEASURE kube-router on $srv_node: $m" >> "$GITHUB_STEP_SUMMARY"
  t "kube-router's footprint measured on $srv_node" grep -q 'rss_mib=[0-9]' <<<"$m"
fi

[ $fails = 0 ] || diag
k delete namespace "$ns" --wait=false >/dev/null 2>&1
if [ $fails = 0 ]; then echo "netpol_e2e: OK"; else echo "netpol_e2e: $fails FAIL"; exit 1; fi
