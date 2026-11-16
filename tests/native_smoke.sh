#!/usr/bin/env bash
# Native mode end to end on a Linux host with systemd (docs/ref/native-host.md,
# docs/ref/explore-linux-hosts.md Phase 5, N3 to N5), as a normal user with
# passwordless sudo (GitHub's ubuntu-latest):
#   1. the preflight: with IPv4 forwarding off, create fails and names the
#      exact command; the test runs the printed commands
#   2. vk8s create demo --backend native: the unit vk8s-demo.service, the
#      API answers, the node (the control plane is also a node) is Ready, a
#      pod runs on it, vk8s list shows it running
#   3. several clusters per host: a second cluster (control plane only,
#      since demo owns this host's node) answers on its own port
#   4. vk8s token create: the join server answers the installing join
#      script (N5). A second node is not joined: this runner is demo's
#      node already (its kubelet ports, cni0, kube-proxy's rules), and a
#      job's runners cannot reach each other
#   5. vk8s delete, then nothing remains: no unit, no data dir, no cluster
#      dir, no process, no mount, no cgroup, no iptables rule, no link
# Prints each step's time and a table (also to $GITHUB_STEP_SUMMARY).
#
# usage: tests/native_smoke.sh
# VK8S_BIN (default out/vk8s); VK8S_ASSETS: a dir with vk8s.cpio, node.img
# and control-plane.img (the CI job makes it from scripts/guest's packers).
# Needs kubectl, curl, sudo, systemd, iptables.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
v=${VK8S_BIN:-out/vk8s}
v=$(cd "$(dirname "$v")" && pwd)/$(basename "$v")
name=demo
other=second
pod_image=registry.k8s.io/pause:3.10.1
dir=$HOME/.vk8s/clusters/$name
data=/var/lib/vk8s/$name
w=$(mktemp -d)
rows=""
fails=0
now() { date +%s%3N; }
secs() { awk -v ms="$1" 'BEGIN { printf "%.1f", ms / 1000 }'; }
row() { rows="$rows| $1 | $(secs "$2") |"$'\n'; echo "native: $1: $(secs "$2") s"; }
pass() { echo "PASS $*"; }
bad() { echo "FAIL $*"; fails=$((fails + 1)); }
check() { local n=$1; shift; if "$@"; then pass "$n"; else bad "$n"; fi; }
k() { "$v" connect "$1" -- kubectl --request-timeout=30s "${@:2}"; }

dump() {
  echo "== vk8s list"; "$v" list 2>&1 || true
  echo "== systemctl status"; systemctl status --no-pager "vk8s-$name.service" 2>&1 | tail -n 20 || true
  echo "== journal"; sudo journalctl -u "vk8s-$name.service" --no-pager 2>&1 | tail -n 80 || true
  echo "== nodes and pods"; k "$name" get nodes,pods -A -o wide 2>&1 || true
  echo "== pod smoke"; k "$name" describe pod smoke 2>&1 | tail -n 30 || true
  for f in "$dir"/share/logs/*.log; do
    [ -f "$f" ] || continue
    echo "== $f (last 30 lines)"; tail -n 30 "$f"
  done
}
summary() {
  local head="### vk8s native mode on $(uname -m) ($1)"
  local table="| step | seconds |"$'\n'"|---|---|"$'\n'"$rows"
  echo "$head"; printf '%s' "$table"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then printf '%s\n\n%s\n' "$head" "$table" >> "$GITHUB_STEP_SUMMARY"; fi
}
cleanup() {
  "$v" delete "$other" >/dev/null 2>&1 || true
  "$v" delete "$name" >/dev/null 2>&1 || true
  rm -rf "$w"
}
die() {
  echo "FAIL $*"
  dump
  summary "FAIL: $*"
  cleanup
  exit 1
}
timed() { # timed LABEL CMD...: runs CMD, records its time, stops on error
  local label=$1; shift
  local t0; t0=$(now)
  "$@" > "$w/out" 2>&1 || { cat "$w/out"; die "$label"; }
  cat "$w/out"
  row "$label" $(( $(now) - t0 ))
}
until_ok() { # until_ok SECONDS CMD...
  local limit=$1; shift
  local end=$(( $(date +%s) + limit ))
  until "$@" >/dev/null 2>&1; do
    [ "$(date +%s)" -lt "$end" ] || return 1
    sleep 2
  done
}
readyz() { [ "$(k "$1" get --raw /readyz 2>/dev/null)" = ok ]; }
node_ready() { [ "$(k "$name" get node "$name" -o 'jsonpath={.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = True ]; }
pod_running() { [ "$(k "$name" get pod smoke -o 'jsonpath={.status.phase}' 2>/dev/null)" = Running ]; }
rules() { { sudo iptables-save; sudo ip6tables-save; sudo iptables-legacy-save; sudo ip6tables-legacy-save; } 2>/dev/null | grep -E 'KUBE-|FLANNEL-|CNI-' || true; }

[ -x "$v" ] || { echo "native: no vk8s binary at $v (scripts/build-linux.sh)"; exit 2; }
[ -n "${VK8S_ASSETS:-}" ] || { echo "native: set VK8S_ASSETS"; exit 2; }
echo "native: $("$v" version 2>&1 | head -1) on $(uname -srm), assets $VK8S_ASSETS"
cleanup_before() { "$v" delete "$other" >/dev/null 2>&1; "$v" delete "$name" >/dev/null 2>&1; true; }
cleanup_before
veths0=$(ip -o link show type veth 2>/dev/null | wc -l)
rules0=$(rules | wc -l)
t_all=$(now)

# 1. the preflight names the exact command to run
fwd=$(cat /proc/sys/net/ipv4/ip_forward)
sudo sysctl -q -w net.ipv4.ip_forward=0
out=$("$v" create "$name" --backend native --connect=false 2>&1); rc=$?
sudo sysctl -q -w net.ipv4.ip_forward="$fwd"
echo "$out"
check "preflight: create refuses" [ "$rc" != 0 ]
check "preflight: names the sysctl to set" grep -q -- '- run: sudo sysctl -w net.ipv4.ip_forward=1' <<<"$out"
check "preflight: changed nothing" test ! -e "$dir" -a ! -e "$data"
# what else it asks for, as it printed it
grep -- '- run: sudo ' <<<"$out" | sed 's/^- run: //' | while read -r cmd; do echo "+ $cmd"; $cmd; done

# 2. create; the API, the node and a pod
timed "create (control plane and host node)" "$v" create "$name" --backend native --connect=false
check "every sudo step was printed first" grep -q '^+ sudo systemctl enable --now vk8s-demo.service$' "$w/out"
check "the unit is active" systemctl is-active --quiet "vk8s-$name.service"
check "the unit file is installed" test -f "/etc/systemd/system/vk8s-$name.service"
grep -E '^(Restart|RestartSec|KillMode|Delegate|ExecStart)=' "/etc/systemd/system/vk8s-$name.service"
timed "API answers /readyz" until_ok 120 readyz "$name"
timed "node Ready" until_ok 600 node_ready
k "$name" get nodes -o wide
timed "pod created" k "$name" run smoke --image="$pod_image" --restart=Always
timed "pod Running" until_ok 600 pod_running
k "$name" get pods -A -o wide
"$v" list
check "list shows demo running" bash -c "\"$v\" list | grep -w $name | grep -qw running"
port=$(sed -n 's/^PORT=//p' "$dir/cluster.env")
check "the API is on the cluster's port, not 6443" bash -c "[ -n '$port' ] && [ '$port' != 6443 ]"

# 3. a second cluster on the same host
timed "create a second cluster (control plane only)" "$v" create "$other" --backend native --connect=false
check "the second cluster runs no node" grep -qx 'HOST_NODE=0' "$HOME/.vk8s/clusters/$other/cluster.env"
timed "the second API answers /readyz" until_ok 120 readyz "$other"
port2=$(sed -n 's/^PORT=//p' "$HOME/.vk8s/clusters/$other/cluster.env")
check "the clusters' ports differ" [ "$port" != "$port2" ]
check "the first cluster still answers" readyz "$name"
timed "delete the second cluster" "$v" delete "$other"
check "the second cluster's unit and data are gone" test ! -e "/etc/systemd/system/vk8s-$other.service" -a ! -e "/var/lib/vk8s/$other"
check "the first cluster still answers after" readyz "$name"

# 4. token create: the installing join script
timed "token create" "$v" token create "$name"
url=$(grep -o 'https://[^" ]*/node/join?token=[^" ]*' "$w/out" | head -1)
check "the join command names this host's join server" bash -c "[ -n '$url' ]"
if [ -n "$url" ] && curl -fsSk -o "$w/join.sh" "$url"; then
  pass "the join server answers the token"
  check "the join script is valid sh" sh -n "$w/join.sh"
  check "the join script installs the node bundle" grep -q 'kubernetes-v1.36.6-$arch-full.tar.gz' "$w/join.sh"
  check "the join script installs the kubelet unit" grep -q '/etc/systemd/system/kubelet.service' "$w/join.sh"
  check "the join script no longer execs a preinstalled kubeadm" bash -c "! grep -q 'exec kubeadm' '$w/join.sh'"
else
  bad "the join server answers the token"
fi
echo "NOTE a second node is not joined on this runner: it is demo's node already"

# 5. delete leaves nothing
pids_before=$(pgrep -fc "$data/" || true)
echo "native: $pids_before processes name $data before delete"
timed "delete" "$v" delete "$name"
check "no unit file" test ! -e "/etc/systemd/system/vk8s-$name.service"
check "systemd no longer knows the unit" bash -c "! systemctl list-unit-files 'vk8s-$name.service' --no-legend | grep -q ."
check "no data dir" test ! -e "$data"
check "no cluster dir" test ! -e "$dir"
check "no vk8s CNI dirs or flannel state" test ! -e /opt/vk8s -a ! -e /run/flannel -a ! -e /var/lib/cni/flannel
left=$(pgrep -fa "/var/lib/vk8s/" || true)
if [ -z "$left" ]; then pass "no process of the cluster"; else bad "no process of the cluster: $left"; fi
check "no pod process (pause)" bash -c "! pgrep -x pause >/dev/null"
check "no kubepods cgroup" test ! -e /sys/fs/cgroup/kubepods
check "no mount under /var/lib/vk8s" bash -c "! grep -q ' /var/lib/vk8s/' /proc/self/mountinfo"
rl=$(rules)
if [ "$(printf '%s' "$rl" | grep -c .)" -le "$rules0" ]; then pass "no KUBE-, FLANNEL- or CNI- rule"; else bad "rules left: $rl"; fi
check "no cni0 link" bash -c "! ip link show cni0 >/dev/null 2>&1"
check "no veth left" [ "$(ip -o link show type veth 2>/dev/null | wc -l)" -le "$veths0" ]
check "list no longer shows demo" bash -c "! \"$v\" list | grep -qw $name"
row "total" $(( $(now) - t_all ))

if [ "$fails" != 0 ]; then die "$fails checks"; fi
echo "PASS native smoke"
summary "PASS"
cleanup
