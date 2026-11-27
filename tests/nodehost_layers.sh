#!/usr/bin/env bash
# The shared layer store in the node-host VM, the macOS path of container
# mode (docs/STATUS.md, "Shared assets and layers off the VM", the macOS
# node host; src/cli/nodehost.bend Nh.layers_*, Nh.node.v2, Nh.parse.v2;
# host/init.bend Nhi.layers, Nhi.after), run on a Linux host with KVM
# (VK8S_NODE_HOST=vm): no root, no runc on the host.
#
# The same workload twice, each in a fresh $HOME and a fresh node host:
# two clusters of one node container each (vk8s create --backend
# container), a pod of IMAGE in the first (cold: nothing has the image),
# then one in the second; then EXTRA the other way round (cold in the
# second cluster, then in the first); then each image of MORE as IMAGE,
# for a sum of cold starts:
#   off  VK8S_LAYERS=0: the node host starts without the store, each node
#        pulls and unpacks every image itself;
#   on   VK8S_LAYERS unset (the default): the store ($HOME/.vk8s/layers)
#        is shared into the node host VM once, read-only, and bound into
#        each node container; the filler runs on this host. A node does
#        not wait for the fill of a layer the store lacks (no-wait,
#        src/layers/ask.bend Ask.nowait.v4): the first cluster's node
#        unpacks the image itself and the filler fills the store once
#        that pull is over; the second cluster's node loop-mounts the
#        store's layer images.
# With the store off it checks that nothing of the store exists. With it
# on it checks:
#   (a) the first cluster's pod stands on its node's own directories;
#       every lowerdir of the second cluster's pod is /mnt/layers/<hex>,
#       in that node a squashfs on a loop device backed by <hex>.sqfs,
#       which is in the host's store; no image is written and no layer
#       unpacked for it; both pods read the same file; the node's
#       layers.held is where the filler's gc reads it;
#   (b) the other way round with EXTRA, so both nodes hold store layers:
#       the loop devices in use in the VM are the two nodes' layer mounts;
#   (c) after vk8s delete of the first cluster: the node host says no
#       mount and no rule of it is left, the loop devices in use are the
#       second node's alone, the second cluster's pod reads its file
#       again with the page cache dropped and a new pod starts from the
#       store;
#   (d) after the last delete: the node host stopped and its directory
#       is gone; the store stays.
# It prints MEASURE lines (the evidence docs/STATUS.md needs): run to
# Ready of each pod and the kubelet's own pull time, off against on, and
# the disk (the node host's data disk, allocated KiB, and the store). A
# start is timed only when no fill runs (settle).
#
# usage: tests/nodehost_layers.sh VK8S ASSETS_DIR KUBECTL
#   VK8S        the host binary (scripts/build-linux.sh)
#   ASSETS_DIR  the guest assets with base.img and the sets (scripts/guest/build.sh)
#   KUBECTL     a kubectl for this host
# Needs /dev/kvm. Prints PASS/FAIL lines; exits 1 on any FAIL.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
[ $# = 3 ] || { sed -n 's/^# usage: //p' "$0"; exit 2; }
vk8s=$(realpath "$1") assets=$(realpath "$2") kubectl=$(realpath "$3")
image=${IMAGE:-docker.io/library/nginx:1.27}
extra=${EXTRA:-docker.io/library/httpd:2.4}
more=${MORE-docker.io/library/redis:7 docker.io/library/memcached:1.6 docker.io/library/caddy:2 docker.io/library/registry:2}
peek_image=docker.io/library/busybox:1.36
hexre='[0-9a-f]{64}'
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
t() { local n=$1; shift; if "$@"; then pass "$n"; else fail "$n"; fi; }
# perl, not `date +%s.%N`: macOS date has no %N
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }
secs() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f", b - a }'; }
add() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.2f", a + b }'; }
until_ok() { local end=$(( $(date +%s) + $1 )); shift; until "$@"; do [ "$(date +%s)" -lt "$end" ] || return 1; sleep 2; done; }

home= mode= nh=
homes=
V() {
  if [ "$mode" = on ]; then
    timeout 2400 env -u VK8S_LAYERS HOME="$home" KUBECONFIG="$home/.kube/config" VK8S_ASSETS="$assets" VK8S_NODE_HOST=vm "$vk8s" "$@"
  else
    timeout 2400 env HOME="$home" KUBECONFIG="$home/.kube/config" VK8S_ASSETS="$assets" VK8S_NODE_HOST=vm VK8S_LAYERS=0 "$vk8s" "$@"
  fi
}
k() { local c=$1; shift; "$kubectl" --kubeconfig "$home/.vk8s/clusters/$c/kubeconfig.yaml" --request-timeout=30s "$@"; }
filler_stop() { pkill -f "$vk8s layers serve" 2>/dev/null; sleep 1; }
vmm_alive() { local p; p=$(cat "$nh/vmm.pid" 2>/dev/null) && [ -n "$p" ] && kill -0 "$p" 2>/dev/null; }
snap_log() { cat "$nh/share/clusters/$1/share/logs/snapshotter.log" 2>/dev/null; }
kept() { snap_log "$1" | grep -c 'is not in the store: unpacked on this node'; }
# settle CLUSTER...: every ask a node kept for later is answered, so the
# store holds what the nodes pulled and no fill runs (store on; at most
# 300 s). A node sends its asks 3 s after its last pull activity.
settle() {
  [ "$mode" = on ] || return 0
  local end=$(( $(date +%s) + 300 )) c n a
  while :; do
    n=0 a=0
    for c in "$@"; do
      n=$((n + $(kept "$c"))); a=$((a + $(snap_log "$c" | grep -c 'ask, not waited for: ')))
    done
    [ "$n" = "$a" ] && return 0
    [ "$(date +%s)" -lt "$end" ] || { echo "settle: $n asks kept, $a answered"; return 1; }
    sleep 1
  done
}
# pulled CLUSTER POD: the seconds the kubelet says the pod's image pull
# took (its Pulled event); 0 when there is none
pulled() {
  k "$1" get events --field-selector "involvedObject.name=$2,reason=Pulled" -o 'jsonpath={.items[*].message}' 2>/dev/null \
    | sed -n 's/.*Successfully pulled image [^ ]* in \([0-9.]*\)\(m\{0,1\}s\) .*/\1 \2/p' \
    | awk '{ if ($2 == "ms") printf "%.2f", $1 / 1000; else printf "%.2f", $1; found = 1 } END { if (!found) printf "0" }'
}
# pod CLUSTER NAME IMAGE: a pod on the cluster's node; prints the seconds
# from the run to Ready, or "fail"
pod() {
  local t0 t1
  t0=$(now)
  k "$1" run "$2" --image="$3" --restart=Never --overrides="{\"apiVersion\":\"v1\",\"spec\":{\"nodeName\":\"$1\"}}" >/dev/null 2>&1
  if k "$1" wait --for=condition=Ready "pod/$2" --timeout=600s >/dev/null 2>&1; then t1=$(now); secs "$t0" "$t1"; else echo fail; fi
}
# lowers CLUSTER POD: the lowerdirs of the pod's root overlay, nearest first, one a line
lowers() {
  k "$1" exec "$2" -- cat /proc/self/mountinfo 2>&1 | awk '$5 == "/"' | tail -1 | sed -n 's/.*[ ,]lowerdir=\([^, ]*\).*/\1/p' | tr ':' '\n'
}
# peek CLUSTER: a privileged pod in the node's PID namespace, to read the
# node's mount table (/proc/1/mountinfo), the VM's loop devices
# (/proc/partitions, /sys/block) and to drop the VM's page cache
peek() {
  k "$1" run peek --image="$peek_image" --restart=Never --overrides="{\"apiVersion\":\"v1\",\"spec\":{\"nodeName\":\"$1\",\"hostPID\":true,\"containers\":[{\"name\":\"peek\",\"image\":\"$peek_image\",\"command\":[\"sleep\",\"36000\"],\"securityContext\":{\"privileged\":true}}]}}" >/dev/null 2>&1
  k "$1" wait --for=condition=Ready pod/peek --timeout=600s >/dev/null 2>&1
}
# layer_mounts CLUSTER: how many layer images the cluster's node has mounted
layer_mounts() { k "$1" exec peek -- cat /proc/1/mountinfo 2>/dev/null | grep -Ec " /mnt/layers/$hexre "; }
# vm_loops CLUSTER: the loop devices in use in the whole node-host VM
# (a block device is in /proc/partitions only while it has a size)
vm_loops() { k "$1" exec peek -- cat /proc/partitions 2>/dev/null | grep -Ec ' loop[0-9]+$'; }
# not_in_store CLUSTER HEX...: how many of the layers are not, in that
# node, a squashfs on a loop device backed by <hex>.sqfs that the host's
# store holds
not_in_store() {
  local c=$1 bad=0 h line fstype dev bf minfo; shift
  minfo=$(k "$c" exec peek -- cat /proc/1/mountinfo 2>/dev/null)
  for h in "$@"; do
    line=$(grep " /mnt/layers/$h " <<<"$minfo" | tail -1)
    fstype=$(sed -n 's/.* - \([^ ]*\) \([^ ]*\) .*/\1/p' <<<"$line")
    dev=$(sed -n 's/.* - \([^ ]*\) \([^ ]*\) .*/\2/p' <<<"$line")
    bf=$(k "$c" exec peek -- cat "/sys/block/$(basename "${dev:-none}")/loop/backing_file" 2>/dev/null)
    if [ "$fstype" != squashfs ] || [ "${bf%"$h.sqfs"}" = "$bf" ] || [ ! -s "$home/.vk8s/layers/$h.sqfs" ]; then
      bad=$((bad + 1)); echo "layer $h in $c: '$line' dev=$dev backing=$bf store: $(ls -l "$home/.vk8s/layers/$h.sqfs" 2>&1)" >&2
    fi
  done
  echo $bad
}
data_kib() { du -sk "$nh/data.img" 2>/dev/null | cut -f1; }
diag() {
  echo "--- diagnostics ($mode)"
  tail -n 80 "$nh/console.log" 2>/dev/null
  tail -n 20 "$nh/vmm.log" 2>/dev/null
  for f in "$nh"/share/logs/*.log "$nh"/share/clusters/*/share/logs/snapshotter.log "$nh"/share/clusters/*/share/logs/containerd.log "$home/.vk8s/layers-serve.log"; do
    [ -f "$f" ] || continue; echo "--- $f"; tail -n 40 "$f"
  done
  cat "$nh/share/runc-list" 2>/dev/null
  local c
  for c in "$mode"1 "$mode"2; do
    [ -f "$home/.vk8s/clusters/$c/kubeconfig.yaml" ] || continue
    k "$c" get pods -A -o wide 2>&1
    k "$c" get events -A --sort-by=.lastTimestamp 2>&1 | tail -n 30
  done
}
cleanup() {
  local h m
  for m in off on; do
    for h in $homes; do
      mode=$m home=$h nh=$h/.vk8s/nodehost
      [ -d "$h/.vk8s/clusters/${m}1" ] && V delete "${m}1" >/dev/null 2>&1
      [ -d "$h/.vk8s/clusters/${m}2" ] && V delete "${m}2" >/dev/null 2>&1
    done
  done
  for h in $homes; do
    nh=$h/.vk8s/nodehost
    vmm_alive && kill -9 "$(cat "$nh/vmm.pid")" 2>/dev/null
    rm -rf "$h"
  done
  filler_stop
}
trap cleanup EXIT

# up CLUSTER: create it, its node Ready, every add-on pod Ready, no fill running
up() {
  local c=$1 t0
  t0=$(now)
  if ! V create "$c" --backend container --connect=false; then fail "store $mode: create $c"; diag; return 1; fi
  eval "create_$c=$(secs "$t0" "$(now)")"
  pass "store $mode: create $c in the node host ($(secs "$t0" "$(now)") s)"
  t "store $mode: $c's node is Ready" k "$c" wait --for=condition=Ready node --all --timeout=900s
  # the add-ons' own pulls are over before a start is timed
  t "store $mode: every add-on pod of $c is Ready" k "$c" wait --for=condition=Ready pod --all -A --timeout=900s
  t "store $mode: no fill runs" settle "$c"
}

# phase MODE: a fresh home and node host, two clusters, the pods; leaves
# both clusters up
phase() {
  mode=$1
  home=$(mktemp -d)
  homes="$homes $home"
  nh=$home/.vk8s/nodehost
  local a=${mode}1 b=${mode}2
  echo "== store $mode: two clusters in one node host, home $home"
  up "$a" || return 1
  cold=$(pod "$a" lay-cold "$image")
  t "store $mode: the first cluster's pod is Ready (cold, $cold s)" test "$cold" != fail
  t "store $mode: the store has what the first node pulled" settle "$a"
  k "$a" exec lay-cold -- sync >/dev/null 2>&1
  d1=$(data_kib)
  up "$b" || return 1
  # one kernel serves every node: a sync in any pod writes the data disk
  k "$a" exec lay-cold -- sync >/dev/null 2>&1
  d1b=$(data_kib)
  kept_b0=$(kept "$b")
  images0=$(find "$home/.vk8s/layers" -maxdepth 1 -name '*.sqfs' 2>/dev/null | wc -l)
  warm=$(pod "$b" lay-warm "$image")
  t "store $mode: the second cluster's pod is Ready ($warm s)" test "$warm" != fail
  kept_b1=$(kept "$b")
  images1=$(find "$home/.vk8s/layers" -maxdepth 1 -name '*.sqfs' 2>/dev/null | wc -l)
  cold_pull=$(pulled "$a" lay-cold); warm_pull=$(pulled "$b" lay-warm)
  k "$b" exec lay-warm -- sync >/dev/null 2>&1
  d2=$(data_kib)
  # the other way round: EXTRA cold in the second cluster, then in the first
  t "store $mode: no fill runs" settle "$a" "$b"
  xcold=$(pod "$b" x-cold "$extra")
  t "store $mode: the store has what the second node pulled" settle "$a" "$b"
  xwarm=$(pod "$a" x-warm "$extra")
  t "store $mode: the $extra pods are Ready ($xcold s in the second cluster, then $xwarm s in the first)" test "$xcold" != fail -a "$xwarm" != fail
  xcold_pull=$(pulled "$b" x-cold); xwarm_pull=$(pulled "$a" x-warm)
  k "$a" exec lay-cold -- sync >/dev/null 2>&1
  d3=$(data_kib)
  store_kib=0
  [ -d "$home/.vk8s/layers" ] && store_kib=$(du -sk "$home/.vk8s/layers" | cut -f1)
  echo "MEASURE nodehost-layers store=$mode image=$image create_first_s=$(eval echo \$create_$a) create_second_s=$(eval echo \$create_$b) cold_ready_s=$cold cold_pull_s=$cold_pull second_cluster_ready_s=$warm second_cluster_pull_s=$warm_pull"
  echo "MEASURE nodehost-layers store=$mode image=$extra cold_ready_s=$xcold cold_pull_s=$xcold_pull other_cluster_ready_s=$xwarm other_cluster_pull_s=$xwarm_pull"
  echo "MEASURE nodehost-layers store=$mode data_disk_kib after_first_cluster_pod=$d1 after_second_create=$d1b after_second_cluster_pod=$d2 after_all=$d3 store_kib=$store_kib second_pod_cost_kib=$((d2 - d1b))"
  eval "m_${mode}_cold=$cold m_${mode}_warm=$warm m_${mode}_xcold=$xcold m_${mode}_xwarm=$xwarm m_${mode}_d1=$d1 m_${mode}_d1b=$d1b m_${mode}_d2=$d2 m_${mode}_d3=$d3 m_${mode}_store=$store_kib m_${mode}_cold_pull=$cold_pull m_${mode}_warm_pull=$warm_pull m_${mode}_xcold_pull=$xcold_pull"
  echo "--- TIMING store=$mode events"
  k "$a" get events --field-selector involvedObject.name=lay-cold --sort-by=.lastTimestamp -o 'custom-columns=AT:.lastTimestamp,REASON:.reason,MESSAGE:.message' --no-headers 2>&1 | cut -c1-200
  k "$b" get events --field-selector involvedObject.name=lay-warm --sort-by=.lastTimestamp -o 'custom-columns=AT:.lastTimestamp,REASON:.reason,MESSAGE:.message' --no-headers 2>&1 | cut -c1-200
  # more cold starts, for a sum (a single pull is a download: its time
  # varies by seconds on a runner): each of MORE cold in the first
  # cluster, then in the second; after the disk measure, which stays the
  # four pods above
  local n=0 img c w cp wp sc=0 sw=0 sp=0 ok=1
  for img in $more; do
    n=$((n + 1))
    settle "$a" "$b"
    c=$(pod "$a" "m$n-cold" "$img")
    settle "$a" "$b"
    w=$(pod "$b" "m$n-warm" "$img")
    cp=$(pulled "$a" "m$n-cold"); wp=$(pulled "$b" "m$n-warm")
    echo "MEASURE nodehost-layers-more store=$mode image=$img cold_ready_s=$c cold_pull_s=$cp second_cluster_ready_s=$w second_cluster_pull_s=$wp"
    if [ "$c" != fail ] && [ "$w" != fail ]; then sc=$(add "$sc" "$c"); sw=$(add "$sw" "$w"); sp=$(add "$sp" "$cp"); else ok=0; fi
  done
  t "store $mode: the pods of $n more images are Ready in both clusters" test "$ok" = 1
  eval "m_${mode}_more_n=$n m_${mode}_more_cold=$sc m_${mode}_more_warm=$sw m_${mode}_more_pull=$sp m_${mode}_more_ok=$ok"
  [ "$mode" = on ] || return 0
  echo "--- TIMING store=on the filler's fills, and the first node's asks"
  grep -E ' layers in [0-9]+ ms' "$home/.vk8s/layers-serve.log" 2>/dev/null | cut -c1-220
  snap_log "$a" | grep -E 'the pull is over|ask, not waited for' | sed 's/sha256:[0-9a-f]*//g' | cut -c1-160 | tail -n 60
}

# finish MODE: the last delete; the node host stops and its directory goes
finish() {
  local b=${1}2 pid0
  pid0=$(cat "$nh/vmm.pid" 2>/dev/null)
  t "store $mode: delete $b (the last cluster)" V delete "$b"
  t "store $mode: the node host stopped with the last cluster" sh -c "! { [ -n '$pid0' ] && kill -0 '$pid0' 2>/dev/null; }"
  t "store $mode: the node host's directory is gone" test ! -e "$nh" -a ! -e "$nh.gone"
  t "store $mode: no cluster directory is left" sh -c "[ -z \"\$(ls -A '$home/.vk8s/clusters' 2>/dev/null)\" ]"
}

uname -r
# a filler another test's create left serves that test's store
filler_stop

# --- off: no store anywhere
if phase off; then
  t "store off: the node host's PID 1 wrote that it has no store" grep -qx 0 "$nh/share/layers"
  t "store off: its PID 1 says so" grep -q 'node host: no shared layer store' "$nh/console.log"
  t "store off: no store under the home" test ! -e "$home/.vk8s/layers"
  t "store off: no filler was started" test ! -e "$home/.vk8s/layers-serve.log"
  t "store off: no node runs the snapshotter" sh -c "! ls '$nh'/share/clusters/*/share/logs/snapshotter.log >/dev/null 2>&1"
  off_lowers=$(lowers off2 lay-warm)
  own_dirs() { [ -n "$1" ] && ! grep -q '^/mnt/layers/' <<<"$1"; }
  t "store off: the second cluster's pod stands on its node's own directories" own_dirs "$off_lowers"
  [ $fails = 0 ] || diag
  t "store off: delete off1" V delete off1
  t "store off: the node host still runs for off2" vmm_alive
  finish off
else
  diag
fi

# --- on: the first cluster's node unpacks for itself, the second stands on the store
if phase on; then
  store=$home/.vk8s/layers
  t "store on: the node host's PID 1 wrote that it mounted the store" grep -qx 1 "$nh/share/layers"
  t "store on: its PID 1 mounted it" grep -q 'node host: shared layer store at /mnt/layers-store' "$nh/console.log"
  filler_up() { pgrep -f "$vk8s layers serve" >/dev/null; }
  t "store on: the filler runs on this host" filler_up
  echo "== (a) the second cluster's pod stands on the store's images, the first's on its node's own unpack"
  cold_lowers=$(lowers on1 lay-cold)
  warm_lowers=$(lowers on2 lay-warm)
  echo "lay-cold lowerdirs: $(tr '\n' ' ' <<<"$cold_lowers")"
  echo "lay-warm lowerdirs: $(tr '\n' ' ' <<<"$warm_lowers")"
  shared_cold=$(grep -Ec "^/mnt/layers/$hexre\$" <<<"$cold_lowers")
  others=$(grep -Evc "^/mnt/layers/$hexre\$" <<<"$warm_lowers")
  t "(a) the first node did not wait for the store: no lowerdir of lay-cold is a store image ($shared_cold)" test -n "$cold_lowers" -a "$shared_cold" = 0
  t "(a) every lowerdir of lay-warm's root is /mnt/layers/<hex> ($others others)" test -n "$warm_lowers" -a "$others" = 0
  hex_warm=$(sed -n "s|^/mnt/layers/||p" <<<"$warm_lowers")
  nlayers=$(wc -w <<<"$hex_warm")
  t "(a) both pods stand on as many layers ($(wc -l <<<"$cold_lowers"), $nlayers)" test "$(wc -l <<<"$cold_lowers")" = "$nlayers" -a "$nlayers" -gt 0
  t "(a) no layer image was written for the second cluster's pod ($images0, $images1)" test "$images0" = "$images1" -a "$images1" -gt 0
  t "(a) its node unpacked no layer for it ($kept_b0 asks kept before, $kept_b1 after)" test "$kept_b0" = "$kept_b1"
  peek on1; p1=$?; peek on2; p2=$?
  t "(a) a privileged pod runs in each node (to read its mounts)" test "$p1" = 0 -a "$p2" = 0
  bad=$(not_in_store on2 $hex_warm)
  t "(a) in the second node each of the $nlayers layers is a squashfs on a loop device backed by the store's image ($bad not)" test "$bad" = 0
  sum_cold=$(k on1 exec lay-cold -- sha256sum /usr/sbin/nginx 2>/dev/null | cut -d' ' -f1)
  sum_warm=$(k on2 exec lay-warm -- sha256sum /usr/sbin/nginx 2>/dev/null | cut -d' ' -f1)
  t "(a) both pods read the same nginx ($sum_warm)" test -n "$sum_cold" -a "$sum_cold" = "$sum_warm"
  held=$(cat "$nh/share/clusters/on2/share/layers.held" 2>/dev/null)
  miss=0
  for h in $hex_warm; do grep -q "sha256:$h " <<<"$held" || miss=$((miss + 1)); done
  t "(a) the second node's layers.held, where the filler's gc reads it, names every layer of its pod ($miss missing)" test "$miss" = 0
  echo "MEASURE nodehost-layers store=on asks_not_waited_for first=$(kept on1) second=$(kept on2) asks_waited_for_ok first=$(snap_log on1 | grep -c 'ask for .*: ok ') second=$(snap_log on2 | grep -c 'ask for .*: ok ') layer_images=$(find "$store" -maxdepth 1 -name '*.sqfs' | wc -l)"

  echo "== (b) the other way round: the first cluster's node on the store's images of $extra"
  x_lowers=$(lowers on1 x-warm)
  xothers=$(grep -Evc "^/mnt/layers/$hexre\$" <<<"$x_lowers")
  t "(b) every lowerdir of x-warm's root in the first cluster is /mnt/layers/<hex> ($xothers others)" test -n "$x_lowers" -a "$xothers" = 0
  bad=$(not_in_store on1 $(sed -n "s|^/mnt/layers/||p" <<<"$x_lowers"))
  t "(b) in the first node each is a squashfs on a loop device backed by the store's image ($bad not)" test "$bad" = 0
  m1=$(layer_mounts on1); m2=$(layer_mounts on2); loops=$(vm_loops on2)
  echo "layer mounts: first node $m1, second node $m2; loop devices in use in the VM: $loops"
  t "(b) both nodes hold layer mounts ($m1, $m2)" test "$m1" -gt 0 -a "$m2" -gt 0
  t "(b) the loop devices in use in the VM are the two nodes' layer mounts ($loops = $m1 + $m2)" test "$loops" = "$((m1 + m2))"
  [ $fails = 0 ] || diag

  echo "== (c) delete the first cluster: nothing of it is left in the node host"
  td0=$(now)
  t "(c) delete on1" V delete on1
  echo "MEASURE nodehost-layers delete_s=$(secs "$td0" "$(now)") (on1; the node host stays)"
  t "(c) the node host still runs for on2" vmm_alive
  after=$(grep 'node host: after on1: ' "$nh/console.log" | tail -1)
  echo "$after"
  t "(c) the node host says no mount and no rule of on1 is left" grep -q 'after on1: no mount and 0 rules of it left' <<<"$after"
  loops_are() { [ "$(vm_loops on2)" = "$1" ]; }
  t "(c) the loop devices in use are the second node's $m2 layer mounts" until_ok 30 loops_are "$m2"
  echo "loop devices in use in the VM after the delete: $(vm_loops on2)"
  t "(c) on1's node shares are gone" test ! -e "$nh/share/clusters/on1"
  k on2 exec peek -- sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches' >/dev/null 2>&1
  sum_again=$(k on2 exec lay-warm -- sha256sum /usr/sbin/nginx 2>/dev/null | cut -d' ' -f1)
  t "(c) the second cluster's pod reads the same nginx with the page cache dropped" test -n "$sum_again" -a "$sum_again" = "$sum_warm"
  again=$(pod on2 lay-again "$image")
  t "(c) a new pod of the second cluster starts from the store ($again s)" test "$again" != fail
  [ $fails = 0 ] || diag

  echo "== (d) the last delete"
  finish on
  t "(d) the store stays (a cache, which vk8s layers gc trims)" test -d "$store"
  echo "--- filler log (tail)"; tail -n 12 "$home/.vk8s/layers-serve.log" 2>/dev/null
  filler_stop
else
  diag
fi

ratio() { awk -v a="$1" -v b="$2" 'BEGIN { if (b > 0) printf "%.2f", a / b }'; }
if [ -n "${m_on_cold:-}" ] && [ -n "${m_off_cold:-}" ]; then
  echo "MEASURE nodehost-layers ready_s cold off=$m_off_cold on=$m_on_cold ratio_on_off=$(ratio "$m_on_cold" "$m_off_cold") second_cluster off=$m_off_warm on=$m_on_warm ratio_on_off=$(ratio "$m_on_warm" "$m_off_warm")"
  echo "MEASURE nodehost-layers pull_s cold off=$m_off_cold_pull on=$m_on_cold_pull second_cluster off=$m_off_warm_pull on=$m_on_warm_pull"
  echo "MEASURE nodehost-layers ready_s $extra cold off=$m_off_xcold on=$m_on_xcold other_cluster off=$m_off_xwarm on=$m_on_xwarm"
  echo "MEASURE nodehost-layers disk_kib data_disk off=$m_off_d3 on=$m_on_d3 store on=$m_on_store sum off=$m_off_d3 on=$((m_on_d3 + m_on_store)) ratio_on_off=$(ratio "$((m_on_d3 + m_on_store))" "$m_off_d3")"
  echo "MEASURE nodehost-layers second_cluster_pod_disk_kib off=$((m_off_d2 - m_off_d1b)) on=$((m_on_d2 - m_on_d1b))"
  if [ "${m_off_more_ok:-0}" = 1 ] && [ "${m_on_more_ok:-0}" = 1 ] && [ "$m_off_xcold" != fail ] && [ "$m_on_xcold" != fail ]; then
    # every cold start: IMAGE, EXTRA and MORE
    c_off=$(add "$(add "$m_off_cold" "$m_off_xcold")" "$m_off_more_cold"); c_on=$(add "$(add "$m_on_cold" "$m_on_xcold")" "$m_on_more_cold")
    p_off=$(add "$(add "$m_off_cold_pull" "$m_off_xcold_pull")" "$m_off_more_pull"); p_on=$(add "$(add "$m_on_cold_pull" "$m_on_xcold_pull")" "$m_on_more_pull")
    w_off=$(add "$(add "$m_off_warm" "$m_off_xwarm")" "$m_off_more_warm"); w_on=$(add "$(add "$m_on_warm" "$m_on_xwarm")" "$m_on_more_warm")
    echo "MEASURE nodehost-layers cold_ready_sum_s images=$((m_on_more_n + 2)) off=$c_off on=$c_on ratio_on_off=$(ratio "$c_on" "$c_off") cold_pull_sum_s off=$p_off on=$p_on ratio_on_off=$(ratio "$p_on" "$p_off") other_cluster_ready_sum_s off=$w_off on=$w_on ratio_on_off=$(ratio "$w_on" "$w_off")"
  fi
fi
if [ $fails = 0 ]; then echo "nodehost_layers: OK"; else echo "nodehost_layers: $fails FAIL"; exit 1; fi
