#!/usr/bin/env bash
# The shared layer store in node containers on a Linux host (docs/GOAL.md
# section 11, "Shared assets and layers off the VM", the container half;
# src/guest/plan.bend Plan.with_layers.v5, src/cli/ctr.bend Ctr.layers_*).
#
# The same workload twice, each in a fresh $HOME: a cluster of two node
# containers (vk8s create --backend container --nodes 1), then one pod
# of IMAGE on the control plane's node (cold: nothing has the image) and
# one on the worker (warm: the other node has pulled it):
#   off  VK8S_LAYERS=0: each node pulls and unpacks the image itself;
#   on   VK8S_LAYERS unset (the default): create binds ~/.vk8s/layers
#        into each node and starts the filler. A node does not wait for
#        the fill of a layer the store lacks (the no-wait mode,
#        src/layers/ask.bend Ask.nowait.v4): the first node unpacks the
#        image itself, as with the store off, and keeps that copy; the
#        filler fills the store once the node's pull is over, and the
#        next node loop-mounts the store's layer images.
# With the store on it checks:
#   (a) the first node's pod stands on the node's own directories; every
#       lowerdir of the second node's pod is /mnt/layers/<hex>, and in
#       that node's mount namespace that is a squashfs on a loop device
#       whose backing file is the store's <hex>.sqfs (same inode);
#   (b) each layer is in the store once, the second node holds no
#       unpacked copy of the image's files and the first holds one, and
#       the second node's share/layers.held names its layers;
#   (m) a chain that is not all in the store, with MIXED (IMAGE and one
#       layer more): on the second node the lower layers are the
#       store's and the top one is unpacked there; then, the store
#       filled, on the first node the top layer is the store's over the
#       lower ones the node unpacked itself. Both pods run and read the
#       same files;
#   (d) the next cluster on the same store: its pods stand on the
#       store's images, no image is written for it, and its nodes take
#       a fraction of the disk;
#   (c) after vk8s delete: no loop device backed by a store image, no
#       mount of /mnt/layers or of the store, no layers.held left.
# It prints MEASURE lines (the evidence docs/STATUS.md needs): host disk
# of each node's dir and of the store (du -skx, KiB) after both pods are
# Ready, and the time from `kubectl run` to pod Ready, cold and warm,
# for off and on. A start is timed only when no fill runs (settle).
#
# usage: tests/container_layers.sh VK8S ASSETS_DIR KUBECTL
# Needs sudo, runc, cpio, iproute2, iptables, util-linux (losetup).
# Prints PASS/FAIL lines; exits 1 on any FAIL.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
[ $# = 3 ] || { sed -n 's/^# usage: //p' "$0"; exit 2; }
vk8s=$(realpath "$1") assets=$(realpath "$2") kubectl=$(realpath "$3")
image=${IMAGE:-docker.io/library/nginx:1.27}
# IMAGE's layers and one more on top (nginx's own FROM nginx:1.27 build)
mixed=${MIXED:-docker.io/library/nginx:1.27-otel}
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
    sudo timeout 2400 env -u VK8S_LAYERS HOME="$home" VK8S_ASSETS="$assets" PATH="$PATH" "$vk8s" "$@"
  else
    sudo timeout 2400 env HOME="$home" VK8S_ASSETS="$assets" VK8S_LAYERS=0 PATH="$PATH" "$vk8s" "$@"
  fi
}
k() { sudo "$kubectl" --kubeconfig "$home/.vk8s/clusters/$name/kubeconfig.yaml" --request-timeout=30s "$@"; }
node_pid() { sudo runc --root /run/vk8s/runc state "vk8s-$name-$1" 2>/dev/null | sed -n 's/^ *"pid": *\([0-9]*\).*/\1/p'; }
filler_stop() { sudo pkill -f "$vk8s layers serve" 2>/dev/null; sleep 1; }
# every node's snapshotter log (the cluster's directory is root's, so the glob is expanded as root)
snap_logs() { sudo sh -c 'cat "$1"/share/logs/snapshotter.log "$1"/nodes/*/share/logs/snapshotter.log 2>/dev/null' sh "$home/.vk8s/clusters/$name"; }
add() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.2f", a + b }'; }
# pulled POD: the seconds the kubelet says the pod's image pull took (its
# Pulled event: "Successfully pulled image ... in 2.315s" or "in 722ms");
# 0 when there is none. The pull alone, without the kubelet's and the
# API's delays between the run and Ready.
pulled() {
  k get events --field-selector "involvedObject.name=$1,reason=Pulled" -o 'jsonpath={.items[*].message}' 2>/dev/null \
    | sed -n 's/.*Successfully pulled image [^ ]* in \([0-9.]*\)\(m\{0,1\}s\) .*/\1 \2/p' \
    | awk '{ if ($2 == "ms") printf "%.2f", $1 / 1000; else printf "%.2f", $1; found = 1 } END { if (!found) printf "0" }'
}
# settle: every ask a node of the cluster kept for later is answered, so
# the store holds what the nodes pulled and no fill runs (store on; at
# most 300 s). A node sends its asks 3 s after its last pull activity.
settle() {
  [ "$mode" = on ] || return 0
  local end=$(( $(date +%s) + 300 )) kept ans
  while :; do
    kept=$(snap_logs | grep -c 'is not in the store: unpacked on this node')
    ans=$(snap_logs | grep -c 'ask, not waited for: ')
    [ "$kept" = "$ans" ] && return 0
    [ "$(date +%s)" -lt "$end" ] || { echo "settle: $kept asks kept, $ans answered"; return 1; }
    sleep 1
  done
}
# lowers POD: the lowerdirs of the pod's root overlay, nearest first, one a line
lowers() {
  k exec "$1" -- cat /proc/self/mountinfo 2>&1 | awk '$5 == "/"' | tail -1 | sed -n 's/.*[ ,]lowerdir=\([^, ]*\).*/\1/p' | tr ':' '\n'
}
# in_store NODE_INDEX HEX...: how many of the layers are not, in that
# node, a squashfs on a loop device backed by the store's image
not_in_store() {
  local i=$1 npid bad=0 h line fstype dev ino back bf; shift
  npid=$(node_pid "$i")
  [ -n "$npid" ] || { echo 999; return; }
  for h in "$@"; do
    line=$(sudo awk -v m="/mnt/layers/$h" '$5 == m' "/proc/$npid/mountinfo" | tail -1)
    fstype=$(sed -n 's/.* - \([^ ]*\) \([^ ]*\) .*/\1/p' <<<"$line")
    dev=$(sed -n 's/.* - \([^ ]*\) \([^ ]*\) .*/\2/p' <<<"$line")
    ino=$(sudo stat -c %i "$home/.vk8s/layers/$h.sqfs" 2>/dev/null)
    back=$(sudo losetup -n -O BACK-INO -l "$dev" 2>/dev/null | tr -d ' ')
    bf=$(sudo cat "/sys/block/$(basename "$dev")/loop/backing_file" 2>/dev/null)
    if [ "$fstype" != squashfs ] || [ -z "$ino" ] || [ "$back" != "$ino" ]; then
      bad=$((bad + 1)); echo "layer $h in node $i: '$line' dev=$dev store inode=$ino loop inode=$back backing=$bf" >&2
    fi
  done
  echo $bad
}
diag() {
  local d=$home/.vk8s/clusters/$name
  echo "--- diagnostics ($mode)"
  for f in $(sudo sh -c 'ls "$1"/console.log "$1"/nodes/*/console.log "$1"/share/logs/snapshotter.log "$1"/nodes/*/share/logs/snapshotter.log \
    "$1"/share/logs/containerd.log "$1"/nodes/*/share/logs/containerd.log "$2" 2>/dev/null' sh "$d" "$home/.vk8s/layers-serve.log"); do
    echo "--- $f"; sudo tail -n 40 "$f"
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
  snap_logs \
    | grep -E 'ask for |ask, not waited|the pull is over|layer .* (mounted|read|not|is not in the store)' | tail -n 120 | cut -c1-300
}

# extras: more cold and warm samples, one pair per image of EXTRA (after
# the disk measure, which stays IMAGE alone); MEASURE lines only
extras() {
  local img n=0 c w cp
  for img in ${EXTRA-docker.io/library/httpd:2.4 docker.io/library/redis:7 docker.io/library/memcached:1.6 docker.io/library/caddy:2 docker.io/library/registry:2}; do
    n=$((n + 1))
    image=$img
    c=$(pod "x$n-cold" "$name" 420)
    settle
    w=$(pod "x$n-warm" "$name-worker-1" 420)
    cp=$(pulled "x$n-cold")
    echo "MEASURE container-layers-extra store=$mode image=$img cold_ready_s=$c cold_pull_s=$cp warm_ready_s=$w warm_pull_s=$(pulled "x$n-warm")"
    if [ "$c" != fail ] && [ "$w" != fail ]; then
      if [ "$mode" = on ]; then
        x_on_cold=$(add "${x_on_cold:-0}" "$c"); x_on_warm=$(add "${x_on_warm:-0}" "$w"); x_on_pull=$(add "${x_on_pull:-0}" "$cp"); x_on_n=$((${x_on_n:-0} + 1))
      else
        x_off_cold=$(add "${x_off_cold:-0}" "$c"); x_off_warm=$(add "${x_off_warm:-0}" "$w"); x_off_pull=$(add "${x_off_pull:-0}" "$cp"); x_off_n=$((${x_off_n:-0} + 1))
      fi
    fi
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
  # the add-ons' own pulls are over before a start is timed (the kubelet
  # pulls one image at a time: a pod's pull waited up to 2 s for them)
  t "store $mode: every add-on pod is Ready" k wait --for=condition=Ready pod --all -A --timeout=600s
  # and with the store on, the fills of what the nodes pulled for them
  t "store $mode: no fill runs before the cold start" settle
  cold=$(pod lay-cold "$name")
  t "store $mode: the store has what the first node pulled before the warm start" settle
  warm=$(pod lay-warm "$name-worker-1")
  t "store $mode: the pod on the control plane's node is Ready (cold, $cold s)" test "$cold" != fail
  t "store $mode: the pod on the worker is Ready (warm, $warm s)" test "$warm" != fail
  local v=$home/.vk8s
  nodes_kib=$(sudo du -skx "$v/clusters/$name" | cut -f1)
  node1_kib=$(sudo du -skx "$v/clusters/$name/nodes/worker-1" | cut -f1)
  node0_kib=$((nodes_kib - node1_kib))
  store_kib=0
  sudo test -d "$v/layers" && store_kib=$(sudo du -skx "$v/layers" | cut -f1)
  total_kib=$(sudo du -skx "$v" | cut -f1)
  copies=$(sudo find "$v/clusters/$name" -type f -path '*/usr/sbin/nginx' 2>/dev/null | wc -l)
  copies1=$(sudo find "$v/clusters/$name/nodes/worker-1" -type f -path '*/usr/sbin/nginx' 2>/dev/null | wc -l)
  cold_pull=$(pulled lay-cold)
  eval "m_${mode}_pull=$cold_pull"
  echo "MEASURE container-layers store=$mode image=$image create_s=$create_s cold_ready_s=$cold cold_pull_s=$cold_pull warm_ready_s=$warm warm_pull_s=$(pulled lay-warm) nodes_kib=$nodes_kib first_node_kib=$node0_kib second_node_kib=$node1_kib store_kib=$store_kib vk8s_dir_kib=$total_kib unpacked_copies=$copies on_the_second_node=$copies1"
  eval "m_${mode}_nodes=$nodes_kib m_${mode}_node0=$node0_kib m_${mode}_node1=$node1_kib m_${mode}_store=$store_kib m_${mode}_cold=$cold m_${mode}_warm=$warm m_${mode}_copies=$copies m_${mode}_copies1=$copies1"
  timing lay-cold lay-warm
  extras
}

cleanup() {
  local m
  for m in on off; do
    local h; [ $m = on ] && h=$cur_home_on || h=$cur_home_off
    [ -n "$h" ] || continue
    sudo test -d "$h/.vk8s/clusters/lay-$m" && { mode=$m home=$h name=lay-$m; V delete "lay-$m" >/dev/null 2>&1; }
    sudo test -d "$h/.vk8s/clusters/lay-next" && { mode=$m home=$h name=lay-next; V delete lay-next >/dev/null 2>&1; }
    sudo rm -rf "$h"
  done
  filler_stop
}
trap cleanup EXIT

uname -r
# a filler another test's create left serves that test's store
filler_stop
loops_before=$(sudo losetup -l -n 2>/dev/null | wc -l)

# --- off: each node unpacks for itself
if phase off; then
  t "store off: no store under its home" sudo test ! -e "$home/.vk8s/layers"
  t "store off: each node holds its own unpacked copy ($m_off_copies)" test "$m_off_copies" -ge 2
  t "store off: delete" V delete "$name"
fi

# --- on: the first node unpacks for itself, the next one stands on the store
if phase on; then
  v=$home/.vk8s
  store=$v/layers
  echo "== (a) the second node's pod stands on the store's images, the first node's on its own unpack"
  cold_lowers=$(lowers lay-cold)
  warm_lowers=$(lowers lay-warm)
  echo "lay-cold lowerdirs: $(tr '\n' ' ' <<<"$cold_lowers")"
  echo "lay-warm lowerdirs: $(tr '\n' ' ' <<<"$warm_lowers")"
  shared_cold=$(grep -Ec "^/mnt/layers/$hexre\$" <<<"$cold_lowers")
  others=$(grep -Evc "^/mnt/layers/$hexre\$" <<<"$warm_lowers")
  t "(a) the first node did not wait for the store: no lowerdir of lay-cold is a store image ($shared_cold)" test -n "$cold_lowers" -a "$shared_cold" = 0
  t "(a) every lowerdir of lay-warm's root is /mnt/layers/<hex> ($others others)" test -n "$warm_lowers" -a "$others" = 0
  hex_warm=$(sed -n "s|^/mnt/layers/||p" <<<"$warm_lowers")
  nlayers=$(wc -w <<<"$hex_warm")
  t "(a) both pods stand on as many layers ($(wc -l <<<"$cold_lowers"), $nlayers)" test "$(wc -l <<<"$cold_lowers")" = "$nlayers" -a "$nlayers" -gt 0
  bad=$(not_in_store 1 $hex_warm)
  t "(a) in the second node, each of the $nlayers layers is a squashfs on a loop device backed by the store's image ($bad not)" test "$bad" = 0
  sum_cold=$(k exec lay-cold -- sha256sum /usr/sbin/nginx 2>/dev/null | cut -d' ' -f1)
  sum_warm=$(k exec lay-warm -- sha256sum /usr/sbin/nginx 2>/dev/null | cut -d' ' -f1)
  t "(a) both pods read the same nginx ($sum_warm)" test -n "$sum_cold" -a "$sum_cold" = "$sum_warm"
  echo "== (b) each layer is in the store once; only the first node keeps a copy"
  bad=0
  for h in $hex_warm; do
    c=$(sudo find "$home" -name "$h.sqfs" 2>/dev/null | wc -l)
    [ "$c" = 1 ] || { bad=$((bad + 1)); echo "$h.sqfs: $c copies"; }
  done
  t "(b) one image per layer under \$HOME ($bad not)" test "$bad" = 0
  t "(b) the second node holds no unpacked copy of the image ($m_on_copies1)" test "$m_on_copies1" = 0
  t "(b) the first node keeps the copy it unpacked ($m_on_copies in the cluster)" test "$m_on_copies" = 1
  held1=$(sudo cat "$v/clusters/$name/nodes/worker-1/share/layers.held" 2>/dev/null)
  miss=0
  for h in $hex_warm; do grep -q "sha256:$h " <<<"$held1" || miss=$((miss + 1)); done
  t "(b) the second node's layers.held names every layer of its pod, so gc keeps them ($miss missing)" test "$miss" = 0
  kept=$(snap_logs | grep -c 'is not in the store: unpacked on this node')
  answered=$(snap_logs | grep -c 'ask, not waited for: .*: ok ')
  waited=$(snap_logs | grep -c 'ask for .*: ok ')
  echo "MEASURE container-layers store=on asks_not_waited_for=$kept answered_ok=$answered asks_waited_for_ok=$waited"

  echo "== (m) a chain that is not all in the store ($mixed)"
  images_m0=$(sudo find "$store" -maxdepth 1 -name '*.sqfs' | wc -l)
  save=$image; image=$mixed
  mix1=$(pod lay-mix1 "$name-worker-1" 420)
  t "(m) the pod on the second node is Ready ($mix1 s): lower layers from the store, the top one unpacked there" test "$mix1" != fail
  l1=$(lowers lay-mix1)
  echo "lay-mix1 lowerdirs: $(tr '\n' ' ' <<<"$l1")"
  top1=$(head -n 1 <<<"$l1")
  t "(m) its top layer is the node's own directory ($top1)" test -n "$top1" -a "${top1#/mnt/layers/}" = "$top1"
  t "(m) its lower layers are the $nlayers store images lay-warm stands on" test "$(tail -n +2 <<<"$l1" | sed -n 's|^/mnt/layers/||p')" = "$hex_warm"
  t "(m) the filler filled the top layer once that pull was over" settle
  images_m1=$(sudo find "$store" -maxdepth 1 -name '*.sqfs' | wc -l)
  t "(m) one more image in the store ($images_m0, $images_m1)" test "$images_m1" = "$((images_m0 + 1))"
  mix0=$(pod lay-mix0 "$name" 420)
  t "(m) the pod on the first node is Ready ($mix0 s): the top layer from the store, over the layers the node unpacked" test "$mix0" != fail
  l0=$(lowers lay-mix0)
  echo "lay-mix0 lowerdirs: $(tr '\n' ' ' <<<"$l0")"
  top0=$(head -n 1 <<<"$l0" | sed -n "s|^/mnt/layers/||p")
  t "(m) its top layer is a store image ($top0)" grep -Eqx "$hexre" <<<"$top0"
  t "(m) its lower layers are the directories lay-cold stands on" test "$(tail -n +2 <<<"$l0")" = "$cold_lowers"
  bad=$(not_in_store 0 $top0)
  t "(m) in the first node that layer is a squashfs on a loop device backed by the store's image ($bad not)" test "$bad" = 0
  held0=$(sudo cat "$v/clusters/$name/share/layers.held" 2>/dev/null)
  t "(m) the first node's layers.held names it" grep -q "sha256:$top0 " <<<"$held0"
  files='find / -xdev -type f \( -name "*otel*" -o -path /usr/sbin/nginx \) | sort | xargs sha256sum | sha256sum'
  f1=$(k exec lay-mix1 -- sh -c "$files" 2>/dev/null | cut -d' ' -f1)
  f0=$(k exec lay-mix0 -- sh -c "$files" 2>/dev/null | cut -d' ' -f1)
  t "(m) both pods read the same files of the top and the lower layers ($f0)" test -n "$f1" -a "$f1" = "$f0"
  echo "MEASURE container-layers-mixed image=$mixed top_unpacked_ready_s=$mix1 top_from_store_ready_s=$mix0"
  image=$save
  [ $fails = 0 ] || diag

  echo "== (d) the next cluster on the same store"
  first=$name
  name=lay-next
  images_d0=$(sudo find "$store" -maxdepth 1 -name '*.sqfs' | wc -l)
  t0=$(now)
  if V create "$name" --backend container --nodes 1 --connect=false; then
    next_create=$(secs "$t0" "$(now)")
    pass "(d) create $name ($next_create s)"
    t "(d) its two nodes are Ready" k wait --for=condition=Ready node --all --timeout=900s
    t "(d) every add-on pod is Ready" k wait --for=condition=Ready pod --all -A --timeout=600s
    t "(d) no fill runs" settle
    n0=$(pod lay-cold "$name")
    n1=$(pod lay-warm "$name-worker-1")
    t "(d) its pods are Ready ($n0 s, $n1 s)" test "$n0" != fail -a "$n1" != fail
    for p in lay-cold lay-warm; do
      ls=$(lowers "$p")
      t "(d) $p stands on the first cluster's store images" test "$(sed -n 's|^/mnt/layers/||p' <<<"$ls")" = "$hex_warm"
    done
    next_kib=$(sudo du -skx "$v/clusters/$name" | cut -f1)
    next_copies=$(sudo find "$v/clusters/$name" -type f -path '*/usr/sbin/nginx' 2>/dev/null | wc -l)
    images_d1=$(sudo find "$store" -maxdepth 1 -name '*.sqfs' | wc -l)
    t "(d) no layer image was written for it ($images_d0, $images_d1)" test "$images_d0" = "$images_d1"
    t "(d) it holds no unpacked copy of the image ($next_copies)" test "$next_copies" = 0
    echo "MEASURE container-layers next_cluster create_s=$next_create first_pod_ready_s=$n0 second_pod_ready_s=$n1 nodes_kib=$next_kib asks_not_waited_for=$(snap_logs | grep -c 'is not in the store: unpacked on this node')"
    m_next_nodes=$next_kib m_next_cold=$n0
    [ $fails = 0 ] || diag
    t "(d) delete $name" V delete "$name"
  else
    fail "(d) create $name"; diag; V delete "$name" >/dev/null 2>&1
  fi
  name=$first
  loops_run=$(sudo losetup -l -n -O BACK-FILE 2>/dev/null | grep -c '\.sqfs')
  echo "MEASURE container-layers store=on loop_devices_on_layer_images=$loops_run layer_images=$(sudo find "$store" -maxdepth 1 -name '*.sqfs' | wc -l)"
  echo "--- filler log (tail)"; sudo tail -n 15 "$v/layers-serve.log" 2>/dev/null

  echo "== (c) delete leaves nothing"
  inos=$(sudo find "$store" -maxdepth 1 -name '*.sqfs' -exec stat -c %i {} + 2>/dev/null | sort -u)
  t "store on: delete" V delete "$name"
  sleep 2
  left=0
  for b in $(sudo losetup -l -n -O BACK-INO 2>/dev/null | tr -d ' '); do grep -qx "$b" <<<"$inos" && left=$((left + 1)); done
  t "(c) no loop device is backed by a store image ($left)" test "$left" = 0
  t "(c) no mount of /mnt/layers or of the store is left" sh -c "! sudo grep -q -e '/mnt/layers' -e '$store' /proc/self/mountinfo"
  t "(c) no layers.held is left under the home" test -z "$(sudo find "$v" -name layers.held 2>/dev/null)"
  t "(c) no runc container of the clusters is left" sh -c "! sudo runc --root /run/vk8s/runc list -q 2>/dev/null | grep -q -e 'vk8s-$name-' -e 'vk8s-lay-next-'"
  t "(c) no rule tagged vk8s:$name or vk8s:lay-next is left (nat, filter)" sh -c "! sudo iptables -t nat -S | grep -q -e 'vk8s:$name' -e 'vk8s:lay-next' && ! sudo iptables -t filter -S | grep -q -e 'vk8s:$name' -e 'vk8s:lay-next'"
  t "(c) the store stays (a cache, which vk8s layers gc trims)" sudo test -d "$store"
  loops_after=$(sudo losetup -l -n 2>/dev/null | wc -l)
  echo "MEASURE container-layers loop_devices_before=$loops_before after_delete=$loops_after"
  filler_stop
fi

if [ -n "${m_on_nodes:-}" ] && [ -n "${m_off_nodes:-}" ]; then
  on_sum=$((m_on_nodes + m_on_store)); off_sum=$((m_off_nodes + m_off_store))
  echo "MEASURE container-layers disk_kib off=$off_sum (nodes $m_off_nodes, store $m_off_store) on=$on_sum (nodes $m_on_nodes, store $m_on_store) ratio_on_off=$(awk -v a=$on_sum -v b=$off_sum 'BEGIN { printf "%.2f", a / b }')"
  echo "MEASURE container-layers second_node_kib off=$m_off_node1 on=$m_on_node1 ratio_on_off=$(awk -v a=$m_on_node1 -v b=$m_off_node1 'BEGIN { printf "%.2f", a / b }') next_cluster_kib=${m_next_nodes:-} ratio_next_off=$(awk -v a=${m_next_nodes:-0} -v b=$m_off_nodes 'BEGIN { printf "%.2f", a / b }')"
  if [ "${x_off_n:-0}" = "${x_on_n:-x}" ]; then
    echo "MEASURE container-layers-extra samples=$x_on_n cold_sum_s off=$x_off_cold on=$x_on_cold ratio_on_off=$(awk -v a=$x_on_cold -v b=$x_off_cold 'BEGIN { if (b > 0) printf "%.2f", a / b }') cold_pull_sum_s off=$x_off_pull on=$x_on_pull ratio_on_off=$(awk -v a=$x_on_pull -v b=$x_off_pull 'BEGIN { if (b > 0) printf "%.2f", a / b }') warm_sum_s off=$x_off_warm on=$x_on_warm"
    all_off=$(add "$x_off_cold" "$m_off_cold"); all_on=$(add "$x_on_cold" "$m_on_cold")
    echo "MEASURE container-layers cold_ready_sum_s images=$((x_on_n + 1)) off=$all_off on=$all_on ratio_on_off=$(awk -v a=$all_on -v b=$all_off 'BEGIN { if (b > 0) printf "%.2f", a / b }') cold_pull_sum_s off=$(add "$x_off_pull" "$m_off_pull") on=$(add "$x_on_pull" "$m_on_pull")"
  fi
  echo "MEASURE container-layers ready_s cold off=$m_off_cold on=$m_on_cold ratio_on_off=$(awk -v a=$m_on_cold -v b=$m_off_cold 'BEGIN { if (b > 0) printf "%.2f", a / b }') warm off=$m_off_warm on=$m_on_warm next_cluster=${m_next_cold:-}"
fi
if [ $fails = 0 ]; then echo "container_layers: OK"; else echo "container_layers: $fails FAIL"; exit 1; fi
