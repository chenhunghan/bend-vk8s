#!/usr/bin/env bash
# macOS: one single-node cluster per tool, clean install, same steps
# (docs/GOAL.md section 10, "Measure against lima"; docs/ref/bench-plan.md
# product lane, scenarios 1, 2, 3 and 8).
#   scripts/bench/lightest.sh TOOL [SETTLE_MIN=10] [MEASURE_MIN=10]
#   TOOL: vk8s | vk8s-container | lima-k3s (lima's own template, the
#   shipped default) | lima-k3s-tuned (scripts/bench/lima-k3s-tuned.yaml)
#   | kiac-k3s
#   CPUS, MEM_MIB (env): node size for the matched-capacity profile; unset
#   is the tool's shipped default.
# Steps: reset (no cluster, no image cached by the tool; installed
# assets and lima's downloaded guest image stay), create (timed to node Ready and to CoreDNS Available), settle,
# measure idle over MEASURE_MIN, first nginx pod (timed to Available;
# then deleted and created again on the warm node), measure, delete (timed), then what is left: processes and disk.
# A measurement: summed phys_footprint and RSS of the tool's process set
# (found by executable, see procs), its CPU time over the window, and the
# allocated disk of its state dirs. vk8s runs with sleep when idle off
# (a sleeping cluster is reported apart, never ranked against serving
# ones). Run one tool at a time: lima's VM lives in a
# com.apple.Virtualization.VirtualMachine process that any other
# Virtualization.framework VM would share a name with.
# Prints a CSV header and one line on stdout; progress on stderr.
set -uo pipefail
cd "$(dirname "$0")/../.."
tool=${1:?tool}; settle=${2:-10}; window=${3:-10}
# SKIP (env or the file out/bench/skip): a regex of tools a driver leaves out
skip=${SKIP:-$(cat out/bench/skip 2>/dev/null)}
if [ -n "$skip" ] && echo "$tool" | grep -Eq "^($skip)$"; then echo "lightest.sh: $tool skipped" >&2; exit 0; fi
v=${VK8S_BIN:-$PWD/out/vk8s}; export VK8S_IDLE_SLEEP=0
name=bl
nginx=docker.io/library/nginx@sha256:6784fb0834aa7dbbe12e3d7471e69c290df3e6ba810dc38b34ae33d3c1c05f7d
say() { echo "[$(date +%H:%M:%S)] $*" >&2; }
now() { perl -MTime::HiRes=time -e 'printf "%d\n", time*1000'; }
secs() { echo "scale=1; ($2 - $1) / 1000" | bc; }

case $tool in
  vk8s|vk8s-container)
    exe="^$v\$"
    dirs=("$HOME/.vk8s")
    k() { "$v" connect "$name" -- kubectl "$@"; }
    create() {
      local f=
      [ "$tool" = vk8s-container ] && f="--backend container"
      "$v" create "$name" --connect=false $f ${CPUS:+--cpus $CPUS} ${MEM_MIB:+--memory $MEM_MIB}
    }
    delete() { "$v" delete "$name"; }
    # nothing cached anywhere but the installed assets (cold-pull.sh state 3)
    reset() {
      local V=$HOME/.vk8s
      "$v" delete "$name" >/dev/null 2>&1; "$v" cache stop >/dev/null 2>&1
      pkill -f "$v layers serve" 2>/dev/null; pkill -f "$v cache serve" 2>/dev/null; sleep 1
      rm -rf "$V/layers" "$V/layer-refs" "$V/layer-locks" "$V/oci" "$V/cache/store"
      rm -f "$V/layers-serve.log"
    } ;;
  lima-k3s|lima-k3s-tuned)
    tpl=template:k3s; [ "$tool" = lima-k3s-tuned ] && tpl=$PWD/scripts/bench/lima-k3s-tuned.yaml
    exe='/limactl$|/com\.apple\.Virtualization\.VirtualMachine$'
    dirs=("$HOME/.lima" "$HOME/Library/Caches/lima")
    k() { KUBECONFIG=$HOME/.lima/$name/copied-from-guest/kubeconfig.yaml kubectl "$@"; }
    create() {
      limactl start --name="$name" --tty=false ${CPUS:+--cpus $CPUS} \
        ${MEM_MIB:+--memory $(echo "scale=2; $MEM_MIB / 1024" | bc)} "$tpl"
    }
    delete() { limactl delete -f "$name"; }
    # the tuned template installs k3s from a host copy (not timed)
    seed() {
      local d=$HOME/Library/Caches/vk8s-bench/k3s rel=https://github.com/k3s-io/k3s/releases/download/v1.37.2%2Bk3s1
      [ -s "$d/k3s-arm64" ] && [ -s "$d/install.sh" ] && return
      mkdir -p "$d" && ( cd "$d" && curl -fsSLO "$rel/k3s-arm64" && curl -fsSLO "$rel/sha256sum-arm64.txt" &&
        grep ' k3s-arm64$' sha256sum-arm64.txt | shasum -a 256 -c >/dev/null && curl -fsSL -o install.sh https://get.k3s.io )
    }
    reset() { limactl delete -f "$name" >/dev/null 2>&1; [ "$tool" = lima-k3s ] || seed; } ;;
  kiac-k3s)
    # k3s on Apple's container runtime, one VM per node (kiac, from
    # github.com/saiyam1814/kiac releases, in KIAC or the bench cache).
    # Tuned like lima-k3s-tuned: no LoadBalancer, no metrics-server.
    # kubectl runs in the node: on this Mac vmnet gave the host no route
    # to the node's address. apple/container's own daemons run before and
    # after and are counted in the process set.
    kiac=${KIAC:-$HOME/Library/Caches/vk8s-bench/kiac/kiac}
    exe='/kiac$|/container-(apiserver|network-vmnet|core-images|runtime-linux)$|/cluster-hoststore$|/machine-apiserver$|/com\.apple\.Virtualization\.VirtualMachine$'
    dirs=("$HOME/Library/Application Support/com.apple.container")
    k() { container exec "kiac-$name-control-plane" kubectl "$@"; }
    create() {
      "$kiac" create cluster --name "$name" --distro k3s --no-lb --no-metrics \
        ${CPUS:+--cpus $CPUS} ${MEM_MIB:+--cp-memory ${MEM_MIB}M}
    }
    delete() { "$kiac" delete cluster --name "$name"; }
    reset() { "$kiac" delete cluster --name "$name" >/dev/null 2>&1; }
    vms() { ps -axo comm= | grep -c '/com\.apple\.Virtualization\.VirtualMachine$'; } ;;
  *) echo "lightest.sh: unknown tool $tool" >&2; exit 2 ;;
esac

# PIDs whose executable is the tool's (ps comm is the full path on macOS)
procs() { ps -axo pid=,comm= | awk -v re="$exe" '{p=$1; $1=""; sub(/^ /,""); if ($0 ~ re) print p}'; }
# phys_footprint and RSS in MiB, summed over the PIDs given
mem() {
  local fp=0 rss=0 p f r
  for p in "$@"; do
    f=$(footprint "$p" 2>/dev/null | sed -n 's/.*phys_footprint: *\([0-9.]*\) *\([KMG]B\).*/\1 \2/p' | head -1)
    case $f in
      *GB) fp=$(echo "$fp + ${f% GB} * 1024" | bc) ;;
      *MB) fp=$(echo "$fp + ${f% MB}" | bc) ;;
      *KB) fp=$(echo "$fp + ${f% KB} / 1024" | bc) ;;
    esac
    r=$(ps -o rss= -p "$p" 2>/dev/null); rss=$((rss + ${r:-0} / 1024))
  done
  printf '%.0f,%d' "$fp" "$rss"
}
# CPU seconds (user+sys) summed over the PIDs given
cpus() {
  local p
  for p in "$@"; do ps -o time= -p "$p" 2>/dev/null; done |
    awk -F: '{ s = 0; for (i = 1; i <= NF; i++) s = s * 60 + $i; t += s } END { printf "%.2f\n", t + 0 }'
}
disk() { du -sk "${dirs[@]}" 2>/dev/null | awk '{s+=$1} END {printf "%d\n", s / 1024}'; }
# footprint_mib,rss_mib,cpu_pct_of_one_core over MIN minutes
measure() {
  local min=$1 p c0 c1
  p=$(procs | tr '\n' ' ')
  c0=$(cpus $p); sleep $((min * 60)); c1=$(cpus $p)
  echo "$(mem $p),$(echo "scale=2; ($c1 - $c0) * 100 / ($min * 60)" | bc)"
}

reset; sync
# before a run, no process of the tool runs (kiac: no VM; the daemons stay)
if [ "$tool" = kiac-k3s ]; then busy=$(vms); else busy=$(procs | wc -l | tr -d ' '); fi
if [ "$busy" != 0 ]; then say "processes of $tool already run: $(procs | tr '\n' ' ')"; exit 1; fi
disk0=$(disk)
say "create ($tool, cpus ${CPUS:-default}, memory ${MEM_MIB:-default})"
t0=$(now)
create >&2 || {
  # keep what explains it (lima's logs go with the instance), then leave
  # nothing behind that would block the next tool
  f=out/bench/fail-$tool-$(date +%H%M%S); mkdir -p "$f"
  cp "$HOME/.lima/$name"/*.log "$f"/ 2>/dev/null
  say "create failed (logs in $f)"; reset; exit 1
}
until [ "$(k get nodes --no-headers 2>/dev/null | grep -cw Ready)" -ge 1 ]; do sleep 1; done
t1=$(now)
until [ "$(k -n kube-system get deploy coredns -o jsonpath='{.status.availableReplicas}' 2>/dev/null)" = 1 ]; do sleep 1; done
t2=$(now)
say "node Ready $(secs $t0 $t1) s, CoreDNS $(secs $t0 $t2) s; settle $settle min"
ver=$(k version -o json 2>/dev/null | jq -r .serverVersion.gitVersion)
sleep $((settle * 60))
idle=$(measure "$window"); disk1=$(disk)
say "idle: $idle (footprint MiB, RSS MiB, CPU %); first pod"
t3=$(now)
k create deployment web --image="$nginx" >/dev/null
until [ "$(k get deploy web -o jsonpath='{.status.availableReplicas}' 2>/dev/null)" = 1 ]; do sleep 0.5; done
t4=$(now)
disk3=$(disk)
# where the first start went: the kubelet's own account of the pull, and
# the pod's timestamps
say "first pod: $(k get events --field-selector reason=Pulled -o jsonpath='{.items[*].message}' 2>/dev/null)"
say "first pod: $(k get pods -l app=web -o jsonpath='{range .items[*]}created {.metadata.creationTimestamp}{range .status.conditions[*]} {.type} {.lastTransitionTime}{end}{end}' 2>/dev/null)"
# the same image again, on the node that holds it: five times, timed by a
# watch (a 0.5 s poll cannot tell 0.6 s from 1 s), the median reported.
# The kubelet's own wait before the sandbox varies by 0.3 s steps.
agains=
for _ in 1 2 3 4 5; do
  k delete deployment web --wait=true >/dev/null
  until [ -z "$(k get pods -l app=web --no-headers 2>/dev/null)" ]; do sleep 0.3; done
  t7=$(now)
  k create deployment web --image="$nginx" >/dev/null
  k rollout status deploy/web --timeout=120s >/dev/null
  t8=$(now)
  agains="$agains $(secs $t7 $t8)"
done
again=$(printf '%s\n' $agains | sort -n | sed -n 3p)
say "nginx Available $(secs $t3 $t4) s, again$agains s (median $again)"
sleep 60
pod=$(mem $(procs))
t5=$(now)
delete >&2
t6=$(now)
sleep 10
left=$(procs | wc -l | tr -d ' '); disk2=$(disk)
echo "tool,cpus,mem_mib,server,ready_s,dns_s,idle_fp_mib,idle_rss_mib,idle_cpu_pct,disk_before_mib,disk_idle_mib,nginx_s,nginx_again_s,disk_pod_mib,pod_fp_mib,pod_rss_mib,delete_s,left_procs,disk_after_mib"
echo "$tool,${CPUS:-default},${MEM_MIB:-default},$ver,$(secs $t0 $t1),$(secs $t0 $t2),$idle,$disk0,$disk1,$(secs $t3 $t4),$again,$disk3,$pod,$(secs $t5 $t6),$left,$disk2"
