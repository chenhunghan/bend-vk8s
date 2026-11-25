#!/usr/bin/env bash
# The shared layer store in node containers on a Linux host (docs/GOAL.md
# section 11, "Shared assets and layers off the VM", the container half;
# src/guest/plan.bend Plan.with_layers.v5, src/cli/ctr.bend Ctr.layers_*).
#
# The same workload twice, each in a fresh $HOME: a cluster of two node
# containers (vk8s create --backend container --nodes 1), then one pod
# of IMAGE on the control plane's node (cold: nothing has the image) and
# one on the worker (warm: the other node has pulled it):
#   off  VK8S_LAYERS unset: each node pulls and unpacks the image itself
#        (container nodes keep their own unpack by default);
#   on   VK8S_LAYERS=1: create binds ~/.vk8s/layers into each node and
#        starts the filler; each node's snapshotter asks it for the
#        layers and loop-mounts the layer images.
# With the store on it checks:
#   (a) every lowerdir of each pod's root overlay is /mnt/layers/<hex>,
#       and in the node's mount namespace that is a squashfs on a loop
#       device whose backing file is the store's <hex>.sqfs (same inode);
#   (b) each layer is on the host once: one <hex>.sqfs under $HOME, no
#       unpacked copy of the image's files in a node's data dir, and both
#       nodes hold the same layers (share/layers.held);
#   (c) after vk8s delete: no loop device backed by a store image, no
#       mount of /mnt/layers or of the store, no layers.held left.
# It prints MEASURE lines (the evidence docs/STATUS.md needs): host disk
# of the node dirs and of the store (du -skx, KiB) after both pods are
# Ready, and the time from `kubectl run` to pod Ready, cold and warm,
# for off and on.
#
# usage: tests/container_layers.sh VK8S ASSETS_DIR KUBECTL
# Needs sudo, runc, cpio, iproute2, iptables, util-linux (losetup).
# Prints PASS/FAIL lines; exits 1 on any FAIL.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
[ $# = 3 ] || { sed -n 's/^# usage: //p' "$0"; exit 2; }
vk8s=$(realpath "$1") assets=$(realpath "$2") kubectl=$(realpath "$3")
image=${IMAGE:-docker.io/library/nginx:1.27}
hexre='[0-9a-f]{64}'
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
t() { local n=$1; shift; if "$@"; then pass "$n"; else fail "$n"; fi; }
now() { date +%s.%N; }
secs() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f", b - a }'; }

home=
name=
cur_home_off=
cur_home_on=
V() {
  if [ "$mode" = on ]; then
    sudo timeout 2400 env HOME="$home" VK8S_ASSETS="$assets" VK8S_LAYERS=1 PATH="$PATH" "$vk8s" "$@"
  else
    sudo timeout 2400 env -u VK8S_LAYERS HOME="$home" VK8S_ASSETS="$assets" PATH="$PATH" "$vk8s" "$@"
  fi
}
k() { sudo "$kubectl" --kubeconfig "$home/.vk8s/clusters/$name/kubeconfig.yaml" --request-timeout=30s "$@"; }
node_pid() { sudo runc --root /run/vk8s/runc state "vk8s-$name-$1" 2>/dev/null | sed -n 's/^ *"pid": *\([0-9]*\).*/\1/p'; }
filler_stop() { sudo pkill -f "$vk8s layers serve" 2>/dev/null; sleep 1; }
diag() {
  local d=$home/.vk8s/clusters/$name
  echo "--- diagnostics ($mode)"
  for f in "$d"/console.log "$d"/nodes/*/console.log "$d"/share/logs/snapshotter.log "$d"/nodes/*/share/logs/snapshotter.log \
    "$d"/share/logs/containerd.log "$d"/nodes/*/share/logs/containerd.log "$home/.vk8s/layers-serve.log"; do
    sudo test -f "$f" || continue; echo "--- $f"; sudo tail -n 40 "$f"
  done
  k get pods -A -o wide 2>&1; k describe pod lay-cold lay-warm 2>&1 | tail -n 40
  sudo losetup -l 2>&1 | head -n 40
  echo "--- the filler's forward"; sudo iptables -t nat -S PREROUTING 2>&1 | grep -- 'vk8s:' ; sudo iptables -t filter -S INPUT 2>&1 | grep -- 'vk8s:'
  sudo ss -ltnp 2>&1 | grep ':32000 '
}

# pod NAME NODE: IMAGE on that node; prints the seconds from the run to
# Ready, or "fail"
pod() {
  local t0 t1
  t0=$(now)
  k run "$1" --image="$image" --restart=Never --overrides="{\"apiVersion\":\"v1\",\"spec\":{\"nodeName\":\"$2\"}}" >/dev/null 2>&1
  if k wait --for=condition=Ready "pod/$1" --timeout="${3:-900}s" >/dev/null 2>&1; then t1=$(now); secs "$t0" "$t1"; else echo fail; fi
}

# where a pod's start went: the kubelet's events of the pod (the pull's
# own time is in the Pulled event), and with the store on the filler's
# lines (per-phase times of each fill) and the snapshotters' asks
timing() {
  local p d=$home/.vk8s/clusters/$name
  for p in "$@"; do
    echo "--- TIMING store=$mode events of $p"
    k get events --field-selector "involvedObject.name=$p" --sort-by=.lastTimestamp \
      -o 'custom-columns=AT:.lastTimestamp,REASON:.reason,MESSAGE:.message' --no-headers 2>&1 | cut -c1-260
  done
  [ "$mode" = on ] || return 0
  echo "--- TIMING store=on filler lines"
  sudo grep -E ' ms' "$home/.vk8s/layers-serve.log" 2>/dev/null | tail -n 80 | cut -c1-400
  echo "--- TIMING store=on snapshotter asks, mounts and reads"
  sudo cat "$d"/share/logs/snapshotter.log "$d"/nodes/*/share/logs/snapshotter.log 2>/dev/null \
    | grep -E 'ask for |layer .* (mounted|read|not)' | tail -n 80 | cut -c1-300
}

# extras: more cold and warm samples, one pair per image of EXTRA (after
# the disk measure, which stays IMAGE alone); MEASURE lines only
extras() {
  local img n=0 c w
  for img in ${EXTRA-docker.io/library/httpd:2.4 docker.io/library/redis:7}; do
    n=$((n + 1))
    image=$img
    c=$(pod "x$n-cold" "$name" 420)
    w=$(pod "x$n-warm" "$name-worker-1" 420)
    echo "MEASURE container-layers-extra store=$mode image=$img cold_ready_s=$c warm_ready_s=$w"
    timing "x$n-cold"
  done
  image=${IMAGE:-docker.io/library/nginx:1.27}
}

# phase MODE: create, the two pods, measure; leaves the cluster up
phase() {
  mode=$1
  home=$(mktemp -d)
  name=lay-$mode
  [ "$mode" = on ] && cur_home_on=$home || cur_home_off=$home
  echo "== store $mode: create $name (2 node containers) in $home"
  local t0 t1
  t0=$(now)
  if ! V create "$name" --backend container --nodes 1 --connect=false; then
    fail "store $mode: create"; diag; return 1
  fi
  t1=$(now); pass "store $mode: create ($(secs "$t0" "$t1") s)"
  create_s=$(secs "$t0" "$t1")
  t "store $mode: two nodes are Ready" k wait --for=condition=Ready node --all --timeout=900s
  t "store $mode: flannel is Ready on both nodes" k -n kube-flannel rollout status daemonset/kube-flannel-ds --timeout=600s
  cold=$(pod lay-cold "$name")
  warm=$(pod lay-warm "$name-worker-1")
  t "store $mode: the pod on the control plane's node is Ready (cold, $cold s)" test "$cold" != fail
  t "store $mode: the pod on the worker is Ready (warm, $warm s)" test "$warm" != fail
  local v=$home/.vk8s
  nodes_kib=$(sudo du -skx "$v/clusters/$name" | cut -f1)
  store_kib=0
  sudo test -d "$v/layers" && store_kib=$(sudo du -skx "$v/layers" | cut -f1)
  total_kib=$(sudo du -skx "$v" | cut -f1)
  copies=$(sudo find "$v/clusters/$name" -type f -path '*/usr/sbin/nginx' 2>/dev/null | wc -l)
  echo "MEASURE container-layers store=$mode image=$image create_s=$create_s cold_ready_s=$cold warm_ready_s=$warm nodes_kib=$nodes_kib store_kib=$store_kib vk8s_dir_kib=$total_kib unpacked_copies=$copies"
  eval "m_${mode}_nodes=$nodes_kib m_${mode}_store=$store_kib m_${mode}_cold=$cold m_${mode}_warm=$warm m_${mode}_copies=$copies"
  timing lay-cold lay-warm
  extras
}

cleanup() {
  local m
  for m in on off; do
    local h; [ $m = on ] && h=$cur_home_on || h=$cur_home_off
    [ -n "$h" ] || continue
    sudo test -d "$h/.vk8s/clusters/lay-$m" && { mode=$m home=$h name=lay-$m; V delete "lay-$m" >/dev/null 2>&1; }
    sudo rm -rf "$h"
  done
  filler_stop
}
trap cleanup EXIT

uname -r
loops_before=$(sudo losetup -l -n 2>/dev/null | wc -l)

# --- off: each node unpacks for itself
if phase off; then
  t "store off: no store under its home" sudo test ! -e "$home/.vk8s/layers"
  t "store off: each node holds its own unpacked copy ($m_off_copies)" test "$m_off_copies" -ge 2
  t "store off: delete" V delete "$name"
fi

# --- on: the nodes share the store's layer images
if phase on; then
  v=$home/.vk8s
  store=$v/layers
  echo "== (a) the pods' root overlays are the store's images"
  allhex=
  for p in lay-cold lay-warm; do
    mi=$(k exec "$p" -- cat /proc/self/mountinfo 2>&1)
    root=$(awk '$5 == "/"' <<<"$mi" | tail -1)
    lower=$(sed -n 's/.*[ ,]lowerdir=\([^, ]*\).*/\1/p' <<<"$root")
    echo "$p lowerdir: $lower"
    others=$(tr ':' '\n' <<<"$lower" | grep -Evc "^/mnt/layers/$hexre\$")
    t "(a) every lowerdir of $p's root is /mnt/layers/<hex> ($others others)" test -n "$lower" -a "$others" = 0
    hs=$(tr ':' '\n' <<<"$lower" | sed -n "s|^/mnt/layers/||p" | sort)
    eval "hex_$(tr - _ <<<"$p")=\"\$hs\""
    allhex="$allhex $hs"
  done
  t "(b) both nodes run the pod on the same layers" test -n "$hex_lay_cold" -a "$hex_lay_cold" = "$hex_lay_warm"
  for i in 0 1; do
    npid=$(node_pid $i)
    t "node $i's PID 1 is known ($npid)" test -n "$npid"
    [ -n "$npid" ] || continue
    bad=0; n=0
    for h in $hex_lay_cold; do
      n=$((n + 1))
      line=$(sudo awk -v m="/mnt/layers/$h" '$5 == m' "/proc/$npid/mountinfo" | tail -1)
      fstype=$(sed -n 's/.* - \([^ ]*\) \([^ ]*\) .*/\1/p' <<<"$line")
      dev=$(sed -n 's/.* - \([^ ]*\) \([^ ]*\) .*/\2/p' <<<"$line")
      ino=$(sudo stat -c %i "$store/$h.sqfs" 2>/dev/null)
      back=$(sudo losetup -n -O BACK-INO -l "$dev" 2>/dev/null | tr -d ' ')
      bf=$(sudo cat "/sys/block/$(basename "$dev")/loop/backing_file" 2>/dev/null)
      if [ "$fstype" != squashfs ] || [ -z "$ino" ] || [ "$back" != "$ino" ]; then
        bad=$((bad + 1)); echo "layer $h in node $i: '$line' dev=$dev store inode=$ino loop inode=$back backing=$bf"
      fi
    done
    t "(a) in node $i, each of the $n layers is a squashfs on a loop device backed by the store's image ($bad not)" test "$bad" = 0 -a "$n" -gt 0
  done
  echo "== (b) each layer is on the host once"
  bad=0
  for h in $hex_lay_cold; do
    c=$(sudo find "$home" -name "$h.sqfs" 2>/dev/null | wc -l)
    [ "$c" = 1 ] || { bad=$((bad + 1)); echo "$h.sqfs: $c copies"; }
  done
  t "(b) one image per layer under \$HOME ($bad not)" test "$bad" = 0
  t "(b) no node holds an unpacked copy of the image ($m_on_copies)" test "$m_on_copies" = 0
  held0=$(sudo cat "$v/clusters/$name/share/layers.held" 2>/dev/null)
  held1=$(sudo cat "$v/clusters/$name/nodes/worker-1/share/layers.held" 2>/dev/null)
  miss=0
  for h in $hex_lay_cold; do
    grep -q "sha256:$h " <<<"$held0" || miss=$((miss + 1))
    grep -q "sha256:$h " <<<"$held1" || miss=$((miss + 1))
  done
  t "(b) both nodes' layers.held name every layer of the pod, so gc keeps them ($miss missing)" test "$miss" = 0
  loops_run=$(sudo losetup -l -n -O BACK-FILE 2>/dev/null | grep -c '\.sqfs')
  echo "MEASURE container-layers store=on loop_devices_on_layer_images=$loops_run layer_images=$(sudo find "$store" -maxdepth 1 -name '*.sqfs' | wc -l)"
  echo "--- filler log (tail)"; sudo tail -n 15 "$v/layers-serve.log" 2>/dev/null
  asks=$(sudo cat "$v"/clusters/$name/share/logs/snapshotter.log "$v"/clusters/$name/nodes/*/share/logs/snapshotter.log 2>/dev/null | grep -c 'ask for .*: ok ')
  echo "MEASURE container-layers store=on asks_ok=$asks"
  [ $fails = 0 ] || diag

  echo "== (c) delete leaves nothing"
  inos=$(sudo find "$store" -maxdepth 1 -name '*.sqfs' -exec stat -c %i {} + 2>/dev/null | sort -u)
  t "store on: delete" V delete "$name"
  sleep 2
  left=0
  for b in $(sudo losetup -l -n -O BACK-INO 2>/dev/null | tr -d ' '); do grep -qx "$b" <<<"$inos" && left=$((left + 1)); done
  t "(c) no loop device is backed by a store image ($left)" test "$left" = 0
  t "(c) no mount of /mnt/layers or of the store is left" sh -c "! sudo grep -q -e '/mnt/layers' -e '$store' /proc/self/mountinfo"
  t "(c) no layers.held is left under the home" test -z "$(sudo find "$v" -name layers.held 2>/dev/null)"
  t "(c) no runc container of the cluster is left" sh -c "! sudo runc --root /run/vk8s/runc list -q 2>/dev/null | grep -q 'vk8s-$name-'"
  t "(c) no rule tagged vk8s:$name is left (nat, filter)" sh -c "! sudo iptables -t nat -S | grep -q -- 'vk8s:$name' && ! sudo iptables -t filter -S | grep -q -- 'vk8s:$name'"
  t "(c) the store stays (a cache, which vk8s layers gc trims)" sudo test -d "$store"
  loops_after=$(sudo losetup -l -n 2>/dev/null | wc -l)
  echo "MEASURE container-layers loop_devices_before=$loops_before after_delete=$loops_after"
  filler_stop
fi

if [ -n "${m_on_nodes:-}" ] && [ -n "${m_off_nodes:-}" ]; then
  on_sum=$((m_on_nodes + m_on_store)); off_sum=$((m_off_nodes + m_off_store))
  echo "MEASURE container-layers disk_kib off=$off_sum (nodes $m_off_nodes, store $m_off_store) on=$on_sum (nodes $m_on_nodes, store $m_on_store) ratio_on_off=$(awk -v a=$on_sum -v b=$off_sum 'BEGIN { printf "%.2f", a / b }')"
  echo "MEASURE container-layers ready_s cold off=$m_off_cold on=$m_on_cold warm off=$m_off_warm on=$m_on_warm"
fi
if [ $fails = 0 ]; then echo "container_layers: OK"; else echo "container_layers: $fails FAIL"; exit 1; fi
