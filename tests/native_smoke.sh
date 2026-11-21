#!/usr/bin/env bash
# Native mode end to end on a Linux host with systemd (docs/ref/native-host.md,
# docs/ref/explore-linux-hosts.md Phase 5, N3 to N5), as a normal user with
# passwordless sudo (GitHub's ubuntu-latest):
#   1. the preflight: with IPv4 forwarding off, create fails and names the
#      exact command; the test runs the printed commands
#   2. vk8s create demo --backend native: the unit vk8s-demo.service, the
#      API answers, the node (the control plane is also a node) is Ready, a
#      pod runs on it, vk8s list shows it running
#   2b. gVisor (docs/GOAL.md section 8): the gvisor RuntimeClass (handler
#      runsc); a pod with runtimeClassName gvisor runs busybox's dmesg,
#      whose log must show "Starting gVisor"; a runc pod (the default)
#      prints the host's kernel release
#   2c. the shared layer store (docs/GOAL.md section 11): the host node's
#      snapshotter asks the user's layer filler, which fills the store, and
#      mounts the layer image read-only under the data dir
#   3. several clusters per host: a second cluster (control plane only,
#      since demo owns this host's node) answers on its own port
#   3b. both clusters' bin/ link to one shared read-only copy of the
#      binaries (docs/GOAL.md section 11); scripts/native-disk.sh prints
#      their disk use; the second unit restarts with nothing to restore;
#      deleting it keeps the copy the first one uses
#   4. vk8s token create: the join server answers the installing join
#      script (N5). A second node is not joined: this runner is demo's
#      node already (its kubelet ports, cni0, kube-proxy's rules), and a
#      job's runners cannot reach each other
#   5. vk8s delete, then nothing remains: no unit, no data dir, no cluster
#      dir, no process (no gVisor sandbox), no runsc state in the host's
#      /run/containerd, no mount, no cgroup, no iptables rule (the network
#      policy gate's and kube-router's too), no kube-router ipset, no link
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
gvisor_image=docker.io/library/busybox:1.36
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
  echo "== flannel"; k "$name" -n kube-flannel logs ds/kube-flannel-ds --all-containers --tail=40 2>&1 || true
  k "$name" -n kube-flannel logs ds/kube-flannel-ds --all-containers --previous --tail=40 2>&1 || true
  echo "== node podCIDR"; k "$name" get nodes -o jsonpath='{range .items[*]}{.metadata.name} {.spec.podCIDR}{"\n"}{end}' 2>&1 || true
  for p in gvisor runc; do echo "== pod $p"; k "$name" describe pod $p 2>&1 | tail -n 30; k "$name" logs $p 2>&1 | tail -n 10; done
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
handler_runsc() { [ "$(k "$name" get runtimeclass gvisor -o 'jsonpath={.handler}' 2>/dev/null)" = runsc ]; }
pod_ended() { case "$(k "$name" get pod "$1" -o 'jsonpath={.status.phase}' 2>/dev/null)" in Succeeded|Failed) true ;; *) false ;; esac; }
pod_phase() { k "$name" get pod "$1" -o 'jsonpath={.status.phase}' 2>/dev/null; }
# busybox POD RUNTIMECLASS COMMAND...: a busybox pod, run once
busybox_pod() {
  local n=$1 rc=$2; shift 2
  local cmd; cmd=$(printf '"%s",' "$@"); cmd=${cmd%,}
  k "$name" run "$n" --image="$gvisor_image" --restart=Never \
    --overrides="{\"apiVersion\":\"v1\",\"spec\":{$rc\"containers\":[{\"name\":\"$n\",\"image\":\"$gvisor_image\",\"command\":[$cmd]}]}}"
}
rules() { { sudo iptables-save; sudo ip6tables-save; sudo iptables-legacy-save; sudo ip6tables-legacy-save; } 2>/dev/null | grep -E 'KUBE-|FLANNEL-|CNI-|VK8S-NETPOL-' || true; }
# kube-router's ipsets (src/guest/netpol.bend Netpol.ipset_ours)
ipsets() { sudo ipset list -n 2>/dev/null | grep -E '^(KUBE-SRC-|KUBE-DST-|kube-router-local-pods$)' || true; }

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

# 2b. gVisor: the opt-in RuntimeClass on the host node; runc the default
timed "RuntimeClass gvisor (handler runsc)" until_ok 300 handler_runsc
timed "gVisor pod created" busybox_pod gvisor '"runtimeClassName":"gvisor",' dmesg
timed "runc pod created" busybox_pod runc '' uname -r
timed "gVisor pod ended" until_ok 600 pod_ended gvisor
k "$name" logs gvisor > "$w/gvisor.log" 2>&1; head -n 5 "$w/gvisor.log"
check "the gVisor pod Succeeded" [ "$(pod_phase gvisor)" = Succeeded ]
check "the gVisor pod's dmesg shows Starting gVisor" grep -q 'Starting gVisor' "$w/gvisor.log"
timed "runc pod ended" until_ok 600 pod_ended runc
rlog=$(k "$name" logs runc 2>&1); echo "runc pod: $rlog, host: $(uname -r)"
check "the runc pod Succeeded" [ "$(pod_phase runc)" = Succeeded ]
check "runc stays the default: the pod names no RuntimeClass" test -z "$(k "$name" get pod runc -o 'jsonpath={.spec.runtimeClassName}' 2>&1)"
check "the runc pod runs on the host's kernel, not gVisor's" test "$rlog" = "$(uname -r)"
check "runsc keeps its state under the data dir" sudo test -d "$data/node/run/containerd/runsc/k8s.io"
# 2c. the shared layer store (docs/GOAL.md section 11): busybox's pull
# asked the user's filler through the store's socket, the store holds its
# layer image, and the host node loop-mounts it read-only under its data
# dir through /mnt/layers
sudo grep 'ask for' "$dir/share/logs/snapshotter.log" | tail -n 3
check "the host node's snapshotter asked the filler" sudo grep -q 'ask for .*: ok \(published\|present\)' "$dir/share/logs/snapshotter.log"
check "the store holds layer images" bash -c "find '$HOME/.vk8s/layers' -maxdepth 1 -name '*.sqfs' | grep -q ."
check "/mnt/layers links to the data dir" test "$(readlink /mnt/layers)" = "$data/layers"
check "a layer image is mounted read-only under the data dir" bash -c "grep ' $data/layers/[0-9a-f]* ' /proc/self/mountinfo | grep -q ' squashfs '"
check "the first pod still runs" pod_running
port=$(sed -n 's/^PORT=//p' "$dir/cluster.env")
check "the API is on the cluster's port, not 6443" bash -c "[ -n '$port' ] && [ '$port' != 6443 ]"
# Review of #46, point 6: the runner's children get KUBECACHEDIR, so the
# boot plan's kubectl (apply, create) caches in the data dir, not in a
# home directory.
cache_env() {
  local p
  p=$(pgrep -f "kube-apiserver.*$data/" | head -n 1)
  [ -n "$p" ] && sudo cat "/proc/$p/environ" | tr '\0' '\n' | grep -qx "KUBECACHEDIR=$data/kube-cache"
}
check "the daemons get KUBECACHEDIR in the data dir" cache_env
check "kubectl's discovery cache is in the data dir" sudo test -d "$data/kube-cache/discovery"

# 3. a second cluster on the same host
timed "create a second cluster (control plane only)" "$v" create "$other" --backend native --connect=false
check "the second cluster runs no node" grep -qx 'HOST_NODE=0' "$HOME/.vk8s/clusters/$other/cluster.env"
timed "the second API answers /readyz" until_ok 120 readyz "$other"
port2=$(sed -n 's/^PORT=//p' "$HOME/.vk8s/clusters/$other/cluster.env")
check "the clusters' ports differ" [ "$port" != "$port2" ]
check "the first cluster still answers" readyz "$name"
# 3b. one shared read-only copy of the binaries (docs/GOAL.md section 11)
link1=$(sudo readlink "$data/bin" || true)
link2=$(sudo readlink "/var/lib/vk8s/$other/bin" || true)
shared=${link1%/bin}
echo "native: bin links: $name -> $link1, $other -> $link2"
check "the first cluster's bin links to the shared copy" bash -c "[[ '$link1' == /var/lib/vk8s/.assets/*/bin ]]"
check "both clusters link to one shared copy" test -n "$link1" -a "$link1" = "$link2"
check "one shared copy on the host" [ "$(sudo find /var/lib/vk8s/.assets -mindepth 1 -maxdepth 1 | wc -l)" = 1 ]
check "the shared copy has no write bit (symlinks aside)" [ -z "$(sudo find "$link1/" ! -type l -perm /222 -print -quit)" ]
check "the shared copy is root's" [ "$(sudo stat -c %U "$shared/bin")" = root ]
check "no mount under the shared copy" bash -c "! grep -q ' /var/lib/vk8s/.assets' /proc/self/mountinfo"
scripts/native-disk.sh "$name" "$other" || bad "native-disk.sh"
# A restart of the unit (as after a reboot) needs nothing restored.
timed "restart the second cluster's unit" sudo systemctl restart "vk8s-$other.service"
timed "the second API answers /readyz after the restart" until_ok 180 readyz "$other"
timed "delete the second cluster" "$v" delete "$other"
check "the second cluster's unit and data are gone" test ! -e "/etc/systemd/system/vk8s-$other.service" -a ! -e "/var/lib/vk8s/$other"
check "the shared copy stays while the first cluster links to it" sudo test -x "$link1/kubelet"
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
check "no shared copy (the last cluster took it)" sudo test ! -e /var/lib/vk8s/.assets
check "no cluster dir" test ! -e "$dir"
check "no vk8s CNI dirs or flannel state" test ! -e /opt/vk8s -a ! -e /run/flannel -a ! -e /var/lib/cni/flannel
left=$(pgrep -fa "/var/lib/vk8s/" || true)
if [ -z "$left" ]; then pass "no process of the cluster"; else bad "no process of the cluster: $left"; fi
check "no pod process (pause)" bash -c "! pgrep -x pause >/dev/null"
check "no gVisor sandbox or gofer process" bash -c "! pgrep -f '^runsc-(sandbox|gofer)' >/dev/null"
check "no runsc state in the host's /run/containerd" sudo test ! -e /run/containerd/runsc/k8s.io
check "no kubepods cgroup" test ! -e /sys/fs/cgroup/kubepods
check "no mount under /var/lib/vk8s" bash -c "! grep -q ' /var/lib/vk8s/' /proc/self/mountinfo"
check "no /mnt/layers or /mnt/layers-store link" test ! -L /mnt/layers -a ! -L /mnt/layers-store
check "no loop device holds a layer image" bash -c "! sudo losetup -a | grep -q '$HOME/.vk8s/layers/'"
rl=$(rules)
if [ "$(printf '%s' "$rl" | grep -c .)" -le "$rules0" ]; then pass "no KUBE-, FLANNEL-, CNI- or VK8S-NETPOL- rule"; else bad "rules left: $rl"; fi
sl=$(ipsets)
if [ -z "$sl" ]; then pass "no kube-router ipset"; else bad "ipsets left: $sl"; fi
check "no cni0 link" bash -c "! ip link show cni0 >/dev/null 2>&1"
check "no veth left" [ "$(ip -o link show type veth 2>/dev/null | wc -l)" -le "$veths0" ]
check "list no longer shows demo" bash -c "! \"$v\" list | grep -qw $name"
row "total" $(( $(now) - t_all ))

if [ "$fails" != 0 ]; then die "$fails checks"; fi
echo "PASS native smoke"
summary "PASS"
cleanup
