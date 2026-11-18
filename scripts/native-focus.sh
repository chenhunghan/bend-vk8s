#!/usr/bin/env bash
# The fast loop for a failure of native-certified: runs only the e2e
# tests of one Ginkgo focus, REPEAT times, on a native cluster with a
# joined node (scripts/native-worker.sh), and keeps the evidence of the
# network path of each gRPC probe (CI job native-focus).
#
#   E2E_FOCUS=REGEX [REPEAT=10] [STALE_NEIGH=1] scripts/native-focus.sh CLUSTER NODE
#
# CLUSTER is the native cluster (its host node has the same name), NODE
# the joined node's container. For each run i, out/focus/ gets:
#   i-conformance.txt  scripts/conformance.sh's output (E2E_FOCUS)
#   i-sonobuoy.tar.gz  the run's archive
#   i-tcpdump-N.txt    ARP, ICMP and TCP port 5000 on every interface of
#                      node N (cni0 and each pod's veth), with MACs
#   i-watch.txt        once a second, for each pod with a gRPC probe: its
#                      node's neighbour entry for the pod IP (ip -s neigh),
#                      the bridge port of that MAC, the port's rp_filter,
#                      and conntrack -L for the pod IP
#   i-kubelet-NODE.log NODE's kubelet journal (at -v=4 the prober's lines)
#   i-unit-CLUSTER.log the cluster unit's journal (the host node's kubelet)
#   i-iptables-N.txt   iptables-save -c of node N after the run
# and env.txt once: rp_filter, forwarding, br_netfilter and neighbour
# sysctls, addresses, routes, rules, iptables and nft rules of both
# nodes, ufw, and the proxy variables of both kubelets.
# STALE_NEIGH=1 first gives every free pod IP of each node a STALE
# neighbour entry on cni0 with a MAC no pod has, as the entries of
# deleted pods stay after a long run (each such entry is listed in
# i-seed.txt).
# Writes the counts to GITHUB_STEP_SUMMARY when set; exits non-zero when
# a run fails. Linux only (sudo, nsenter, tcpdump, conntrack, jq).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
name=${1:?usage: scripts/native-focus.sh CLUSTER NODE}
node=${2:?usage: scripts/native-focus.sh CLUSTER NODE}
focus=${E2E_FOCUS:?E2E_FOCUS is required}
n=${REPEAT:-10}
o=out/focus
mkdir -p "$o"
export KUBECONFIG=$HOME/.vk8s/clusters/$name/kubeconfig.yaml
wpid=$(docker inspect -f '{{.State.Pid}}' "$node")
[ -n "$wpid" ] || { echo "native-focus: no container $node"; exit 1; }

# a command in the network namespace of a node: NODE's container, else
# the runner's own (the host node)
nsx() {
  local where=$1; shift
  if [ "$where" = "$node" ]; then sudo nsenter -t "$wpid" -n "$@"; else sudo "$@"; fi
}

env_dump() {
  local w p
  for w in "$name" "$node"; do
    echo "=== $w: sysctls"
    nsx "$w" sysctl -a 2>/dev/null | grep -E 'rp_filter|ip_forward|bridge-nf|\.arp_|neigh\.(default|cni0)\.'
    echo "=== $w: addresses, routes, rules"
    nsx "$w" ip -br addr; nsx "$w" ip route; nsx "$w" ip rule
    echo "=== $w: bridge ports"
    nsx "$w" ip -d link show master cni0 2>/dev/null | grep -E '^[0-9]|hairpin' || true
    echo "=== $w: iptables-save -c"
    nsx "$w" iptables-save -c
    echo "=== $w: nft list ruleset (first 400 lines)"
    nsx "$w" nft list ruleset 2>/dev/null | head -n 400
  done
  echo "=== ufw"
  sudo ufw status verbose 2>&1 || true
  echo "=== the kubelets and their proxy variables"
  for p in $(pgrep -x kubelet); do
    echo "pid $p: $(sudo cat "/proc/$p/cmdline" | tr '\0' ' ' | cut -c1-300)"
    sudo cat "/proc/$p/environ" | tr '\0' '\n' | grep -i proxy || echo "  no proxy variable"
  done
}

seed_stale() {
  local w wi cidr pre live h ip
  wi=0
  for w in "$name" "$node"; do
    wi=$((wi + 1))
    nsx "$w" ip link show cni0 >/dev/null 2>&1 || { echo "$w: no cni0"; continue; }
    cidr=$(kubectl get node "$w" -o jsonpath='{.spec.podCIDR}')
    pre=${cidr%.*}
    live=$({ kubectl get pods -A -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}'
             nsx "$w" ip neigh show dev cni0 | awk '!/FAILED|INCOMPLETE/ { print $1 }'; } | sort -u)
    for h in $(seq 2 254); do
      ip=$pre.$h
      grep -qxF "$ip" <<<"$live" && continue
      printf 'neigh replace %s lladdr 02:5e:00:00:%02x:%02x dev cni0 nud stale\n' "$ip" "$wi" "$h"
    done | nsx "$w" ip -batch -
    echo "$w: STALE entries for the free IPs of $cidr"
    nsx "$w" ip neigh show dev cni0 | grep -c ' 02:5e:00:00:' || true
  done
}

watch_pods() {
  local ts ns pod nd ip started rc mac dev
  while :; do
    ts=$(date -u +%H:%M:%S.%3N)
    kubectl get pods -A -o json 2>/dev/null | jq -r '.items[]
      | select(any(.spec.containers[]; .livenessProbe.grpc != null or .readinessProbe.grpc != null))
      | [.metadata.namespace, .metadata.name, (.spec.nodeName // "-"), (.status.podIP // "-"),
         (.status.containerStatuses[0].state.running.startedAt // "-"),
         ((.status.containerStatuses[0].restartCount // 0) | tostring)] | @tsv' |
    while IFS=$'\t' read -r ns pod nd ip started rc; do
      [ "$ip" != - ] && [ "$nd" != - ] || continue
      echo "--- $ts $ns/$pod node=$nd ip=$ip started=$started restarts=$rc"
      nsx "$nd" ip -s neigh show to "$ip"
      mac=$(nsx "$nd" ip neigh show to "$ip" | awk '{ for (k = 1; k < NF; k++) if ($k == "lladdr") print $(k + 1) }')
      if [ -n "$mac" ]; then
        dev=$(nsx "$nd" bridge fdb show br cni0 | awk -v m="$mac" '$1 == m { print $3; exit }')
        echo "fdb $mac: ${dev:-none}${dev:+ rp_filter=$(nsx "$nd" cat "/proc/sys/net/ipv4/conf/$dev/rp_filter" 2>/dev/null)}"
      fi
      nsx "$nd" conntrack -L -d "$ip" 2>/dev/null
    done
    sleep 1
  done
}

{ echo "focus: $focus"; echo "repeat: $n"; echo "stale neighbours: ${STALE_NEIGH:-no}"; env_dump; } > "$o/env.txt" 2>&1
grep -A3 'proxy variables' "$o/env.txt" || true

pass=0 fail=0 lines=""
for i in $(seq 1 "$n"); do
  echo "::group::native-focus run $i of $n"
  [ -z "${STALE_NEIGH:-}" ] || seed_stale 2>&1 | tee "$o/$i-seed.txt"
  since=$(date -u '+%Y-%m-%d %H:%M:%S')
  tpids=()
  for w in "$name" "$node"; do
    nsx "$w" tcpdump -l -i any -nn -e -tttt 'arp or icmp or tcp port 5000' > "$o/$i-tcpdump-$w.txt" 2>&1 &
    tpids+=($!)
  done
  watch_pods > "$o/$i-watch.txt" 2>&1 &
  wp=$!
  rm -f out/conformance/*_sonobuoy_*.tar.gz
  if E2E_FOCUS="$focus" scripts/conformance.sh certified-conformance "$name" > "$o/$i-conformance.txt" 2>&1; then
    r=PASS; pass=$((pass + 1))
  else
    r=FAIL; fail=$((fail + 1))
  fi
  kill "$wp" 2>/dev/null; wait "$wp" 2>/dev/null
  sleep 2
  sudo pkill -x tcpdump 2>/dev/null
  for p in "${tpids[@]}"; do wait "$p" 2>/dev/null; done
  mv out/conformance/*_sonobuoy_*.tar.gz "$o/$i-sonobuoy.tar.gz" 2>/dev/null
  docker exec "$node" journalctl -u kubelet --since "$since" --no-pager > "$o/$i-kubelet-$node.log" 2>&1
  sudo journalctl -u "vk8s-$name" --since "$since" --no-pager 2>&1 | cat > "$o/$i-unit-$name.log"
  for w in "$name" "$node"; do nsx "$w" iptables-save -c > "$o/$i-iptables-$w.txt" 2>&1; done
  nodes=$(grep -o 'node=[^ ]*' "$o/$i-watch.txt" | sort | uniq -c | tr -s ' ' | tr '\n' ';')
  probes=$(grep -E 'test-grpc' "$o/$i-kubelet-$node.log" | grep -ciE 'probe')
  echo "native-focus run $i: $r (watch samples by node: ${nodes:-none}; $node kubelet probe lines: $probes)"
  tail -n 12 "$o/$i-conformance.txt"
  if [ "$r" = FAIL ]; then
    echo "== $node kubelet: probe lines"
    grep -E 'test-grpc' "$o/$i-kubelet-$node.log" | grep -iE 'probe' | tail -n 60
    echo "== watch (last 80 lines)"
    tail -n 80 "$o/$i-watch.txt"
    for w in "$name" "$node"; do
      echo "== tcpdump on $w (first 120 lines)"
      head -n 120 "$o/$i-tcpdump-$w.txt"
    done
  fi
  echo "::endgroup::"
  lines+="| $i | $r | ${nodes:-none} |"$'\n'
done

head="### native-focus on $name and $node: $pass of $n passed"
echo "$head"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf '%s\n\nFocus: `%s`; stale neighbours seeded: %s\n\n| run | result | gRPC pod samples by node |\n|---|---|---|\n%s' \
    "$head" "$focus" "${STALE_NEIGH:-no}" "$lines" >> "$GITHUB_STEP_SUMMARY"
fi
[ "$fail" = 0 ]
