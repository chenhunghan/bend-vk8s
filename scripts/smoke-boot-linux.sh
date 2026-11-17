#!/usr/bin/env bash
# Boot smoke of the VM backend on a Linux KVM host, for an emulated KVM
# host (scripts/smoke-emulated-kvm.sh): there Kubernetes does not finish
# its bootstrap (nested TCG, docs/STATUS.md "Linux arm64 on KVM"), so this
# checks only what emulation can show:
#   1. vk8s create (one control-plane VM, no worker, no image cache VM)
#      starts bend-vmm (the `vk8s vmm` process), and that process holds
#      /dev/kvm or a KVM VM (anon_inode:kvm-vm) open
#   2. the guest kernel boots and runs vk8s-init as PID 1
#      ("vk8s-init: starting" on the console)
#   3. vk8s-init runs its boot plan up to starting kine and kube-apiserver
#      ("vk8s-init: start kine", "vk8s-init: start kube-apiserver")
#   4. vk8s list shows the cluster, running
#   5. vk8s delete, then nothing remains: no cluster directory, no vmm or
#      vk8s process, no control socket, no list entry, no new tap device
# create blocks until the node publishes its kubeconfig, which under
# emulation may take long or not happen: the smoke runs it in the
# background and checks the boot while it runs. The full smoke (nodes Ready, pods, gVisor,
# snapshot, restore) is scripts/smoke-linux.sh, for a real KVM host.
# Prints each step's time and a table at the end (also to
# $GITHUB_STEP_SUMMARY when set). Exits non-zero on the first failure,
# after printing the guest's console log.
#
# usage: scripts/smoke-boot-linux.sh
# VK8S_BIN (default out/vk8s), VK8S_ASSETS (a local asset build),
# SMOKE_CPUS (the control plane's vCPUs, default 2), BOOT_WAIT (seconds
# for each wait, default 3600).
# Needs /dev/kvm (read and write).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
v=${VK8S_BIN:-out/vk8s}
name=${SMOKE_NAME:-boot}
cpus=${SMOKE_CPUS:-2}
case $cpus in ''|*[!0-9]*|0) cpus=2 ;; esac
limit=${BOOT_WAIT:-3600}
case $limit in ''|*[!0-9]*|0) limit=3600 ;; esac
export VK8S_CACHE=off   # no image cache VM: one VM boots, not two
dir=$HOME/.vk8s/clusters/$name
con=$dir/console.log
w=$(mktemp -d)
rows=""
create_pid=
t_all=$(date +%s%3N)
now() { date +%s%3N; }
secs() { awk -v ms="$1" 'BEGIN { printf "%.1f", ms / 1000 }'; }
row() { rows="$rows| $1 | $(secs "$2") |"$'\n'; echo "boot-smoke: $1: $(secs "$2") s"; }
taps() { ls /sys/class/net 2>/dev/null | while read -r i; do [ -e "/sys/class/net/$i/tun_flags" ] && echo "$i"; done | sort; }
# procs PATTERN: "pid cmdline" of each process whose command line has
# PATTERN (a fixed string), this shell and its children aside. A scan of
# /proc, not pgrep: in the emulated L1's chroot pgrep found no process.
procs() {
  local f p c
  for f in /proc/[0-9]*/cmdline; do
    p=${f#/proc/}; p=${p%/cmdline}
    [ "$p" = $$ ] || [ "$p" = "$BASHPID" ] && continue
    c=$(tr '\0' ' ' < "$f" 2>/dev/null) || continue
    case $c in *"$1"*) echo "$p $c" ;; esac
  done
}
# the VMM processes of the cluster: their --control is in its directory
# (or the one in vmm.pid, which vk8s itself checks, when it runs)
vmm_pids() {
  { procs "--control $dir/" | grep -F ' vmm ' | cut -d' ' -f1
    p=$(cat "$dir/vmm.pid" 2>/dev/null) && [ -n "$p" ] && kill -0 "$p" 2>/dev/null && echo "$p"; } | sort -u
}

summary() {
  local head="### vk8s boot smoke on $(uname -m) ($1)"
  local table="| step | seconds since create |"$'\n'"|---|---|"$'\n'"$rows"
  echo "$head"; printf '%s' "$table"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then printf '%s\n\n%s\n' "$head" "$table" >> "$GITHUB_STEP_SUMMARY"; fi
}
dump() {
  echo "== vk8s list"; "$v" list 2>&1 || true
  echo "== create's output"; cat "$w/create" 2>/dev/null || true
  echo "== processes"; procs vk8s | cut -c1-300
  for f in "$con" "$dir/vmm.log"; do
    [ -f "$f" ] || continue
    echo "== $f (boot steps and failures)"
    grep -E 'vk8s: |vk8s-init: (start|spawn|stop|FAILED|timed out)|[Pp]anic' "$f" | head -n 120 || true
    echo "== $f (last 80 lines)"; tail -n 80 "$f"
  done
}
cleanup() {
  "$v" delete "$name" >/dev/null 2>&1 || true
  [ -n "$create_pid" ] && kill "$create_pid" 2>/dev/null
  rm -rf "$w"
}
fail() {
  echo "FAIL boot-smoke: $*"
  dump
  summary "FAIL: $*"
  cleanup
  exit 1
}
# seen LABEL PATTERN: waits until the console shows PATTERN (fixed
# string, at a line's start), then records the time since create
seen() {
  local end=$(( $(date +%s) + limit ))
  until grep -qsF -- "$2" "$con"; do
    [ -n "$create_pid" ] && ! kill -0 "$create_pid" 2>/dev/null && ! grep -qsF -- "$2" "$con" && fail "$1: vk8s create exited first"
    [ "$(date +%s)" -lt "$end" ] || fail "$1: not on the console after $limit s"
    sleep 2
  done
  row "$1" $(( $(now) - t_all ))
}

[ -x "$v" ] || { echo "boot-smoke: no vk8s binary at $v (scripts/build-linux.sh)"; exit 2; }
[ -r /dev/kvm ] && [ -w /dev/kvm ] || { echo "boot-smoke: /dev/kvm is missing or not read-write for $(id -un)"; exit 2; }
echo "boot-smoke: $("$v" version 2>&1 | head -1) on $(uname -srm), assets ${VK8S_ASSETS:-pinned}, $cpus vCPUs, each wait up to $limit s (vk8s waits x${VK8S_WAIT_SCALE:-1})"
"$v" delete "$name" >/dev/null 2>&1 || true
taps > "$w/taps.before"

# 1. create starts bend-vmm on /dev/kvm
t_all=$(now)
"$v" create "$name" --nodes 0 --cpus "$cpus" --connect=false > "$w/create" 2>&1 &
create_pid=$!
end=$(( $(date +%s) + limit ))
pids=
until [ -n "$pids" ]; do
  pids=$(vmm_pids)
  [ -n "$pids" ] && break
  kill -0 "$create_pid" 2>/dev/null || fail "no VMM process of $name, and vk8s create has exited"
  [ "$(date +%s)" -lt "$end" ] || fail "no VMM process of $name after $limit s"
  sleep 1
done
echo "boot-smoke: VMM pids $(echo $pids), vmm.pid $(cat "$dir/vmm.pid" 2>/dev/null)"
for p in $pids; do echo "boot-smoke: pid $p: $(tr '\0' ' ' < "/proc/$p/cmdline" 2>&1 | cut -c1-300)"; done
row "bend-vmm started (vk8s vmm)" $(( $(now) - t_all ))
kvm=
end=$(( $(date +%s) + limit ))
until [ -n "$kvm" ]; do
  for p in $pids; do
    ls -l "/proc/$p/fd" 2>/dev/null | grep -qE ' -> (/dev/kvm|anon_inode:kvm-vm)$' && kvm=$p
  done
  [ -n "$kvm" ] && break
  [ "$(date +%s)" -lt "$end" ] || { for p in $pids; do ls -l "/proc/$p/fd" 2>&1 | head -n 40; done; fail "no VMM process of $name holds /dev/kvm or a KVM VM"; }
  sleep 1
  pids=$(vmm_pids)
done
echo "boot-smoke: VMM pid $kvm holds KVM ($(ls -l "/proc/$kvm/fd" 2>/dev/null | grep -oE '(/dev/kvm|anon_inode:kvm-vm)$' | sort -u | tr '\n' ' ')): $(tr '\0' ' ' < "/proc/$kvm/cmdline" | cut -c1-200)"
row "bend-vmm on KVM (/dev/kvm)" $(( $(now) - t_all ))

# 2. the guest kernel boots and runs vk8s-init (PID 1)
seen "guest kernel booted, vk8s-init (PID 1) starting" "vk8s-init: starting"

# 3. the boot plan reaches kine and kube-apiserver
seen "vk8s-init: start kine" "vk8s-init: start kine"
seen "vk8s-init: start kube-apiserver" "vk8s-init: start kube-apiserver"
grep -E 'vk8s-init: (starting|start |run |FAILED)' "$con" | head -n 40

# 4. vk8s list shows it, running
"$v" list > "$w/list" 2>&1 || { cat "$w/list"; fail "vk8s list failed"; }
cat "$w/list"
grep -w -- "$name" "$w/list" | grep -qi running || fail "vk8s list does not show $name running"
row "vk8s list shows $name running" $(( $(now) - t_all ))

# 5. delete, nothing remains
t0=$(now)
"$v" delete "$name" > "$w/out" 2>&1 || { cat "$w/out"; fail "vk8s delete failed"; }
cat "$w/out"
row "delete (took $(secs $(( $(now) - t0 ))) s)" $(( $(now) - t_all ))
# create (when it still waits) sees the VMM gone and exits
end=$(( $(date +%s) + 120 ))
while kill -0 "$create_pid" 2>/dev/null && ! grep -qs '^State:.*Z' "/proc/$create_pid/status"; do
  [ "$(date +%s)" -lt "$end" ] || fail "vk8s create still runs 120 s after delete"
  sleep 1
done
create_pid=
[ -e "$dir" ] && fail "the cluster directory $dir remains"
for p in $pids; do kill -0 "$p" 2>/dev/null && fail "VMM process $p of $name remains"; done
[ -z "$(vmm_pids)" ] || { procs vk8s; fail "a VMM process of $name remains"; }
[ -z "$(procs "vk8s vmm"; procs "vk8s create")" ] || { procs vk8s; fail "a vk8s process remains"; }
if command -v ss >/dev/null 2>&1 && ss -xl 2>/dev/null | grep -q -- "$dir/"; then fail "a control socket of $name remains"; fi
"$v" list 2>/dev/null | grep -qw -- "$name" && fail "vk8s list still shows $name"
taps > "$w/taps.after"
diff "$w/taps.before" "$w/taps.after" >/dev/null || { diff "$w/taps.before" "$w/taps.after"; fail "a tap device remains"; }
row "nothing left (process, file, socket, tap)" $(( $(now) - t_all ))
echo "PASS boot-smoke"
summary "PASS"
cleanup
