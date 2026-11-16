#!/usr/bin/env bash
# Native mode on a Linux host (docs/ref/explore-linux-hosts.md Phase 5, N1
# and N2), end to end, as a normal user. It builds host/init.bend and runs
# `vk8s-init native smoke`: the reduced native plan (Native.smoke in
# src/standalone/native.bend): kubeadm's PKI, etcd, kube-apiserver and
# the join server, relocated under a scratch data dir, with no machine
# step. Then it sends the runner SIGTERM and checks the native shutdown:
#
# - the runner logs the stop order, last started first, and exits;
# - no process of the cluster remains (none names the scratch dir);
# - an unrelated process of the same user, started before, still runs
#   (the VM's PID 1 sends kill(-1), which would end it);
# - nothing appeared in the VM's paths (/var/lib/vcluster, /var/lib/vk8s-host).
#
# Needs bend, clang, curl, sha256sum, sha512sum and busybox (installed
# with apt-get when missing); downloads envtest 1.36.2 (etcd,
# kube-apiserver, kubectl) unless KUBEBUILDER_ASSETS names a directory
# with them, and kubeadm from dl.k8s.io (checked against its published
# .sha256). Uses ports 2379-2381, 6443 and 8443. Prints PASS/FAIL lines;
# exits 1 on any FAIL.
set -uo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
runner=""
sentinel=""
cleanup() {
  # Only what this script started: the runner, the sentinel, and (after a
  # failed shutdown) the cluster's processes, found by the scratch dir.
  [ -n "$runner" ] && kill "$runner" 2>/dev/null
  [ -n "$sentinel" ] && kill "$sentinel" 2>/dev/null
  pkill -KILL -f "$tmp/" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
check() { # check NAME CONDITION-COMMAND...
  local name=$1; shift
  if "$@"; then pass "$name"; else fail "$name"; fi
}
dump() { # dump FILE...: show logs after a failure
  for f in "$@"; do echo "--- $f"; tail -n 40 "$f" 2>/dev/null; done
}
wait_for() { # wait_for SECONDS COMMAND...
  local n=$(($1 * 10)); shift
  for _ in $(seq "$n"); do
    "$@" >/dev/null 2>&1 && return 0
    sleep 0.1
  done
  return 1
}

case "$(uname -m)" in
  x86_64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) echo "FAIL unknown architecture $(uname -m)"; exit 1 ;;
esac

echo "== envtest binaries"
assets=${KUBEBUILDER_ASSETS:-}
if [ -z "$assets" ]; then
  ver=1.36.2
  name="envtest-v$ver-linux-$arch.tar.gz"
  url="https://github.com/kubernetes-sigs/controller-tools/releases/download/envtest-v$ver/$name"
  if ! curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 -o "$tmp/$name" "$url" || ! curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 -o "$tmp/$name.sha512" "$url.sha512"; then
    echo "FAIL envtest download"; exit 1
  fi
  want=$(awk '{print $1}' "$tmp/$name.sha512")
  [ "$arch" = amd64 ] && want=ea743186c8a799f5cf8faf16969f86189d003cb7d130e0ac4b58789f1e5748dcf30ebe91c837a10d5ac415383da3e10b9e64d65785c938c23e739781cfb76f08
  got=$(sha512sum "$tmp/$name" | awk '{print $1}')
  if [ "$want" != "$got" ]; then echo "FAIL envtest checksum"; exit 1; fi
  mkdir -p "$tmp/envtest"
  tar -xzf "$tmp/$name" -C "$tmp/envtest"
  assets="$tmp/envtest/controller-tools/envtest"
fi
bin="$tmp/bin"
mkdir -p "$bin"
for b in etcd kube-apiserver kubectl; do
  [ -x "$assets/$b" ] || { echo "FAIL envtest: no $assets/$b"; exit 1; }
  ln -s "$assets/$b" "$bin/$b"
done
pass "envtest binaries"

echo "== kubeadm"
k8s=v1.36.6
kurl="https://dl.k8s.io/release/$k8s/bin/linux/$arch/kubeadm"
if ! curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 -o "$bin/kubeadm" "$kurl" \
  || ! ksha=$(curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 "$kurl.sha256"); then
  echo "FAIL kubeadm download"; exit 1
fi
if [ "$(sha256sum "$bin/kubeadm" | awk '{print $1}')" != "$(awk '{print $1}' <<<"$ksha")" ]; then
  echo "FAIL kubeadm checksum"; exit 1
fi
chmod +x "$bin/kubeadm"
pass "kubeadm $k8s"

echo "== busybox"
bb=$(command -v busybox || true)
if [ -z "$bb" ]; then
  sudo apt-get update -qq >/dev/null && sudo apt-get install -y -qq busybox-static >/dev/null
  bb=$(command -v busybox || true)
fi
[ -n "$bb" ] || { echo "FAIL no busybox"; exit 1; }
pass "busybox $bb"

echo "== build"
if ! bend host/init.bend -o "$tmp/vk8s" >"$tmp/build.log" 2>&1; then
  cat "$tmp/build.log"
  echo "FAIL build host/init.bend"
  exit 1
fi
pass "build"

echo "== the native runner refuses a data dir that is not absolute"
out=$(VK8S_DATA=relative/dir "$tmp/vk8s" native smoke 2>&1)
code=$?
check "relative VK8S_DATA: exit 1" [ "$code" = 1 ]
check "relative VK8S_DATA: says why" grep -q 'native: VK8S_DATA must be an absolute directory' <<<"$out"
check "relative VK8S_DATA: nothing made" [ ! -e relative ]
# Review of #46, point 3: the plans put paths in shell words, unquoted.
out=$(VK8S_DATA="$tmp/demo\$1" "$tmp/vk8s" native smoke 2>&1)
code=$?
check "VK8S_DATA with \$: exit 1" [ "$code" = 1 ]
check "VK8S_DATA with \$: says why" grep -q 'native: VK8S_DATA must be an absolute directory' <<<"$out"
check "VK8S_DATA with \$: nothing made" [ ! -e "$tmp/demo\$1" ]

echo "== native smoke plan"
# An unrelated process of the same user: kill(-1) would end it, the
# native shutdown must not.
sleep 900 </dev/null >/dev/null 2>&1 &
sentinel=$!
data="$tmp/data"
log="$tmp/native.log"
# kubeadm will not advertise a loopback address: for 127.0.0.1 it looks
# for the host's default-route interface (apimachinery
# ResolveBindAddress), and on a runner without one it falls back to lo
# and fails ("unable to select an IP from lo network interface"). Give
# it the runner's own address; the published kubeconfig still names
# 127.0.0.1 (Plan.publish rewrites the server).
node_ip=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+(\.[0-9]+){3}$' | grep -v '^127\.' | head -n 1)
[ -n "$node_ip" ] || { echo "FAIL no non-loopback IPv4 on this host"; exit 1; }
echo "node IP $node_ip"
echo "node IP $node_ip"

echo "== SIGTERM interrupts the native boot"
# Review of #46, points 4 and 5: a SIGTERM during boot ends the runner
# at once, also while a boot command runs or a wait loops; the command
# is killed and reaped, the daemons stop, and nothing of it remains.
exited() { ! kill -0 "$1" 2>/dev/null || [ "$(awk '{print $3}' "/proc/$1/stat" 2>/dev/null)" = Z ]; }
stall() { # stall NAME FAKE SECONDS: FAKE never ends; SIGTERM once it runs
  local name=$1 fake=$2 secs=$3 sb="$tmp/$1" sd="$tmp/$1-data" slog="$tmp/$1.log" pid
  mkdir -p "$sb"
  for b in etcd kube-apiserver kubectl kubeadm; do ln -s "$bin/$b" "$sb/$b"; done
  rm -f "$sb/$fake"
  printf '#!/bin/sh\nwhile :; do sleep 1; done\n' >"$sb/$fake"
  chmod +x "$sb/$fake"
  VK8S_DATA="$sd" VK8S_BIN="$sb" VK8S_SELF="$tmp/vk8s" VK8S_BUSYBOX="$bb" \
    VK8S_NAME=demo VK8S_STORE=etcd VK8S_NODE_IP="$node_ip" \
    "$tmp/vk8s" native smoke >"$slog" 2>&1 &
  pid=$!
  runner=$pid
  if ! wait_for 120 pgrep -f "$sb/$fake"; then
    fail "$name: $fake runs"; kill -KILL "$pid" 2>/dev/null; dump "$slog"
  else
    kill -TERM "$pid"
    if wait_for "$secs" exited "$pid"; then
      pass "$name: the runner exits within $secs s of SIGTERM"
    else
      fail "$name: the runner exits within $secs s of SIGTERM"; kill -KILL "$pid" 2>/dev/null; dump "$slog"
    fi
  fi
  wait "$pid" 2>/dev/null
  runner=""
  check "$name: the runner says boot was interrupted" grep -q 'native: SIGTERM or SIGINT during boot' "$slog"
  sleep 2
  left=$(pgrep -fa "$sb/|$sd/" || true)
  if [ -z "$left" ]; then pass "$name: no process remains"; else fail "$name: no process remains: $left"; fi
  pkill -KILL -f "$sb/|$sd/" 2>/dev/null
}
# A boot command that never ends: kubeadm, the PKI's first command.
stall stall-run kubeadm 15
# A wait that never ends: kube-apiserver never opens 6443 (120 s wait).
stall stall-wait kube-apiserver 40
VK8S_DATA="$data" VK8S_BIN="$bin" VK8S_SELF="$tmp/vk8s" VK8S_BUSYBOX="$bb" \
  VK8S_NAME=demo VK8S_STORE=etcd VK8S_NODE_IP="$node_ip" \
  "$tmp/vk8s" native smoke >"$log" 2>&1 &
runner=$!
# The runner's console may be buffered while it runs: readiness is read
# from what the plan makes, its log only after it exits.
up() {
  [ -s "$data/share/kubeconfig.yaml" ] && [ "$(curl -sk -o /dev/null -w '%{http_code}' https://127.0.0.1:8443/elsewhere)" = 404 ]
}
if wait_for 240 up; then
  pass "the smoke plan ran to the end"
else
  kill -TERM "$runner"; sleep 5
  dump "$log" "$data/share/logs/etcd.log" "$data/share/logs/kube-apiserver.log" "$data/share/logs/join-server.log"
  echo "FAIL the smoke plan ran to the end"; exit 1
fi
check "the PKI is in the data dir" test -s "$data/pki/ca.crt" -a -s "$data/pki/apiserver.crt" -a -s "$data/pki/etcd/server.crt"
check "etcd keeps its data in the data dir" test -d "$data/etcd/member"
check "the daemons log to the share" test -s "$data/share/logs/kube-apiserver.log"
check "the kubeconfig is published on the share" grep -q 'server: https://127.0.0.1:6443' "$data/share/kubeconfig.yaml"
# Review of #46, point 2: the published kubeconfig holds the
# super-admin's key; no other local user may read it (umask 022 here).
check "the data dir is private (0700)" [ "$(stat -c %a "$data")" = 700 ]
check "the share is private (0700)" [ "$(stat -c %a "$data/share")" = 700 ]
check "the published kubeconfig is 0600" [ "$(stat -c %a "$data/share/kubeconfig.yaml")" = 600 ]
check "the published kubeconfig belongs to the share's owner" [ "$(stat -c %u "$data/share/kubeconfig.yaml")" = "$(stat -c %u "$data/share")" ]
kc() { "$bin/kubectl" --kubeconfig "$data/share/kubeconfig.yaml" --request-timeout=30s "$@"; }
readyz() { [ "$(kc get --raw /readyz 2>/dev/null)" = ok ]; }
context() { [ "$(kc config current-context 2>/dev/null)" = vk8s_demo ]; }
check "kube-apiserver answers /readyz with the published kubeconfig" wait_for 60 readyz
check "the context is vk8s_demo" context
pass "the join server answers (404 for another path)"
running=$(pgrep -f "$data/" | wc -l)
check "etcd, kube-apiserver and the join server run (3 processes name the data dir)" [ "$running" = 3 ]

echo "== native shutdown"
kill -TERM "$runner"
gone() { # exited: no such process, or a zombie this shell has not reaped
  ! kill -0 "$runner" 2>/dev/null || [ "$(awk '{print $3}' "/proc/$runner/stat" 2>/dev/null)" = Z ]
}
if wait_for 90 gone; then pass "the runner exits after SIGTERM"; else fail "the runner exits after SIGTERM"; fi
wait "$runner" 2>/dev/null
rc=$?
check "the runner exits 0" [ "$rc" = 0 ]
runner=""
check "boot finished" grep -q 'vk8s-init: boot finished; supervising' "$log"
check "the plan logged its end" grep -q 'vk8s: native smoke up' "$log"
check "no machine step was refused" bash -c "! grep -q 'refusing a step' \"\$1\"" _ "$log"
check "stop order: last started first" grep -q 'vk8s-init: native: stop order: join-server kube-apiserver etcd$' "$log"
check "every daemon stopped" grep -q 'vk8s-init: native: stopped; still running:$' "$log"
left=$(pgrep -fa "$tmp/" | grep -v "sleep 900" || true)
if [ -z "$left" ]; then pass "no stray process"; else fail "no stray process: $left"; fi
check "the unrelated process still runs (no kill(-1))" kill -0 "$sentinel"
check "nothing in the VM's data dir" test ! -e /var/lib/vcluster
check "nothing in the VM's share" test ! -e /var/lib/vk8s-host
if [ "$fails" != 0 ]; then dump "$log"; fi

echo "== $fails failures"
[ "$fails" = 0 ]
