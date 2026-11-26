#!/usr/bin/env bash
# The shared layer store on a native host node (docs/GOAL.md section 11,
# "Shared assets and layers off the VM", the native half;
# src/standalone/native_host.bend NHost.with_layers, src/layers/place.bend).
# As a normal user with passwordless sudo, on a host with systemd.
#
# The same workload twice: a native cluster that runs the host's node,
# then one pod of IMAGE (cold: nothing has the image) and a second one
# (warm: the node has it):
#   off  VK8S_LAYERS unset: the node pulls and unpacks the image itself;
#   on   VK8S_LAYERS=1: the unit names the host's store, the node's
#        snapshotter asks the host's filler for the layers and loop-mounts
#        the layer images under the cluster's data dir.
# With the store on it checks:
#   (a) every lowerdir of each pod's root overlay is
#       /var/lib/vk8s/<name>/node/layers/<hex>, a squashfs on a loop
#       device whose backing file is the store's <hex>.sqfs (same inode);
#   (b) each layer is on the host once, the node holds no unpacked copy,
#       and the cluster's layers.held names every layer (the host's gc
#       keeps them);
#   (c) a crash (every process of the unit killed, its mounts left
#       behind) and the unit's restart: the pod runs again on the same
#       layers, and no mount or loop device is left twice;
#   (d) a second cluster on the same layers. Only one native cluster
#       runs a host's node, so the second is
#         - with CTR_ASSETS (the full guest assets): a node container
#           (vk8s create --backend container) on the same store at the
#           same time: its pod stands on the same images through loop
#           devices of its own; deleting the native cluster leaves no
#           mount under /var/lib/vk8s and takes only its own loop
#           devices, and the container's pod keeps running and reads its
#           files again from the image; deleting the container cluster
#           then leaves no loop device on a store image;
#         - without: the next native cluster, after the first's delete
#           (which leaves no mount and no loop device): its pod starts
#           from the store with no fill.
#   (e) after the last delete: no mount under /var/lib/vk8s or of a
#       store image, no loop device on a store image; the store stays.
# It prints MEASURE lines (the evidence docs/STATUS.md needs): host disk
# of the data dir and of the store (du -skx, KiB) after both pods are
# Ready, and the time from `kubectl run` to pod Ready, cold and warm,
# for off and on.
#
# usage: tests/native_layers.sh
# VK8S_BIN (default out/vk8s); VK8S_ASSETS (the native assets);
# CTR_ASSETS (optional, see (d)). Needs kubectl, sudo, systemd, iptables,
# util-linux (losetup); with CTR_ASSETS also runc and cpio.
# Prints PASS/FAIL lines; exits 1 on any FAIL.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
v=${VK8S_BIN:-out/vk8s}
v=$(cd "$(dirname "$v")" && pwd)/$(basename "$v")
[ -x "$v" ] || { echo "native_layers: no vk8s binary at $v"; exit 2; }
[ -n "${VK8S_ASSETS:-}" ] || { echo "native_layers: set VK8S_ASSETS"; exit 2; }
image=${IMAGE:-docker.io/library/nginx:1.27}
store=$HOME/.vk8s/layers
hexre='[0-9a-f]{64}'
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
t() { local n=$1; shift; if "$@"; then pass "$n"; else fail "$n"; fi; }
now() { date +%s.%N; }
secs() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f", b - a }'; }
k() { "$v" connect "$1" -- kubectl --request-timeout=30s "${@:2}"; }
until_ok() { # until_ok SECONDS CMD...
  local limit=$1; shift
  local end=$(( $(date +%s) + limit ))
  until "$@" >/dev/null 2>&1; do
    [ "$(date +%s)" -lt "$end" ] || return 1
    sleep 2
  done
}
readyz() { [ "$(k "$1" get --raw /readyz 2>/dev/null)" = ok ]; }
node_ready() { [ "$(k "$1" get node "$1" -o 'jsonpath={.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = True ]; }
pod_ready() { [ "$(k "$1" get pod "$2" -o 'jsonpath={.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = True ]; }
restarted() { [ "$(k "$1" get pod "$2" -o 'jsonpath={.status.containerStatuses[0].restartCount}' 2>/dev/null)" -ge 1 ] 2>/dev/null; }
# the loop devices whose backing file is a store image, one "DEV INODE" a line
store_loops() {
  local inos; inos=$(sudo find "$store" -maxdepth 1 -name '*.sqfs' -exec stat -c %i {} + 2>/dev/null | sort -u)
  sudo losetup -l -n -O NAME,BACK-INO 2>/dev/null | while read -r dev ino; do grep -qx "$ino" <<<"$inos" && echo "$dev $ino"; done
}
# the mount points under DIR in this (the host's) mount namespace
mounts_under() { awk -v d="$1/" 'index($5, d) == 1 { print $5 }' /proc/self/mountinfo; }
diag() {
  local n=$1 d=$HOME/.vk8s/clusters/$1
  echo "--- diagnostics ($n)"
  systemctl status --no-pager "vk8s-$n.service" 2>&1 | tail -n 15
  sudo journalctl -u "vk8s-$n.service" --no-pager 2>&1 | tail -n 60
  for f in "$d"/share/logs/snapshotter.log "$d"/share/logs/containerd.log "$d"/share/logs/kubelet.log "$HOME/.vk8s/layers-serve.log"; do
    sudo test -f "$f" || continue; echo "--- $f"; sudo tail -n 40 "$f"
  done
  k "$n" get pods -A -o wide 2>&1; k "$n" describe pod lay-cold lay-warm 2>&1 | tail -n 40
  sudo losetup -l 2>&1 | head -n 40
  grep -e /var/lib/vk8s -e "$store" /proc/self/mountinfo | head -n 40
}
# where a pod's start went (as tests/container_layers.sh)
timing() {
  local n=$1 p d=$HOME/.vk8s/clusters/$1; shift
  for p in "$@"; do
    echo "--- TIMING $n events of $p"
    k "$n" get events --field-selector "involvedObject.name=$p" --sort-by=.lastTimestamp \
      -o 'custom-columns=AT:.lastTimestamp,REASON:.reason,MESSAGE:.message' --no-headers 2>&1 | cut -c1-260
  done
  sudo test -f "$d/share/logs/snapshotter.log" || return 0
  echo "--- TIMING $n filler lines"
  grep -E ' ms' "$HOME/.vk8s/layers-serve.log" 2>/dev/null | tail -n 40 | cut -c1-400
  echo "--- TIMING $n snapshotter asks, mounts and reads"
  sudo grep -E 'ask for |layer .* (mounted|read|not)|native host node' "$d/share/logs/snapshotter.log" 2>/dev/null | tail -n 60 | cut -c1-300
}
# create NAME [ENV=VALUE...]: vk8s create --backend native; the preflight's
# printed commands are run once and the create tried again
create() {
  local n=$1 out rc; shift
  out=$(env "$@" "$v" create "$n" --backend native --connect=false 2>&1); rc=$?
  if [ $rc != 0 ] && grep -q -- '- run: sudo ' <<<"$out"; then
    grep -- '- run: sudo ' <<<"$out" | sed 's/^- run: //' | while read -r cmd; do echo "+ $cmd"; $cmd; done
    out=$(env "$@" "$v" create "$n" --backend native --connect=false 2>&1); rc=$?
  fi
  echo "$out" | tail -n 25
  create_out=$out
  return $rc
}
# pod CLUSTER NAME: IMAGE on the host node; prints the seconds from the
# run to Ready, or "fail"
pod() {
  local t0 t1
  t0=$(now)
  k "$1" run "$2" --image="$image" --restart=Always >/dev/null 2>&1
  if k "$1" wait --for=condition=Ready "pod/$2" --timeout=900s >/dev/null 2>&1; then t1=$(now); secs "$t0" "$t1"; else echo fail; fi
}
# up NAME: the API answers and the host node is Ready
up() {
  t "$1: the API answers /readyz" until_ok 180 readyz "$1"
  t "$1: the host node is Ready" until_ok 600 node_ready "$1"
  # the add-ons' own pulls are over before a start is timed
  t "$1: every add-on pod is Ready" until_ok 600 k "$1" wait --for=condition=Ready pod --all -A --timeout=30s
}
# phase MODE NAME [ENV...]: create, the two pods, measure; leaves the cluster up
phase() {
  local mode=$1 n=$2 t0 t1; shift 2
  echo "== store $mode: create $n (native, the host's node)"
  t0=$(now)
  if ! create "$n" "$@"; then fail "store $mode: create"; diag "$n"; return 1; fi
  t1=$(now); create_s=$(secs "$t0" "$t1"); pass "store $mode: create ($create_s s)"
  t "store $mode: $n runs the host's node" grep -qx 'HOST_NODE=1' "$HOME/.vk8s/clusters/$n/cluster.env"
  up "$n"
  cold=$(pod "$n" lay-cold)
  warm=$(pod "$n" lay-warm)
  t "store $mode: the first pod is Ready (cold, $cold s)" test "$cold" != fail
  t "store $mode: the second pod is Ready (warm, $warm s)" test "$warm" != fail
  data_kib=$(sudo du -skx "/var/lib/vk8s/$n" | cut -f1)
  store_kib=0
  [ -d "$store" ] && store_kib=$(sudo du -skx "$store" | cut -f1)
  copies=$(sudo find "/var/lib/vk8s/$n" -xdev -type f -path '*/usr/sbin/nginx' 2>/dev/null | wc -l)
  echo "MEASURE native-layers store=$mode image=$image create_s=$create_s cold_ready_s=$cold warm_ready_s=$warm data_kib=$data_kib store_kib=$store_kib unpacked_copies=$copies"
  eval "m_${mode}_data=$data_kib m_${mode}_store=$store_kib m_${mode}_cold=$cold m_${mode}_warm=$warm m_${mode}_copies=$copies"
  timing "$n" lay-cold lay-warm
}
# lowers CLUSTER POD: the lowerdirs of the pod's root overlay, one a line
lowers() {
  local mi root
  mi=$(k "$1" exec "$2" -- cat /proc/self/mountinfo 2>&1)
  root=$(awk '$5 == "/"' <<<"$mi" | tail -1)
  sed -n 's/.*[ ,]lowerdir=\([^, ]*\).*/\1/p' <<<"$root" | tr ':' '\n'
}
# on_layers NAME POD: check (a) for one pod; sets hexes
on_layers() {
  local n=$1 p=$2 ls others bad=0 cnt=0 h line fstype dev ino back
  ls=$(lowers "$n" "$p")
  echo "$p lowerdirs: $(tr '\n' ' ' <<<"$ls")"
  others=$(grep -Evc "^/var/lib/vk8s/$n/node/layers/$hexre\$" <<<"$ls")
  t "(a) every lowerdir of $p's root is /var/lib/vk8s/$n/node/layers/<hex> ($others others)" test -n "$ls" -a "$others" = 0
  hexes=$(sed -n "s|^/var/lib/vk8s/$n/node/layers/||p" <<<"$ls" | sort)
  for h in $hexes; do
    cnt=$((cnt + 1))
    line=$(awk -v m="/var/lib/vk8s/$n/node/layers/$h" '$5 == m' /proc/self/mountinfo | tail -1)
    fstype=$(sed -n 's/.* - \([^ ]*\) \([^ ]*\) .*/\1/p' <<<"$line")
    dev=$(sed -n 's/.* - \([^ ]*\) \([^ ]*\) .*/\2/p' <<<"$line")
    ino=$(sudo stat -c %i "$store/$h.sqfs" 2>/dev/null)
    back=$(sudo losetup -n -O BACK-INO -l "$dev" 2>/dev/null | tr -d ' ')
    if [ "$fstype" != squashfs ] || [ -z "$ino" ] || [ "$back" != "$ino" ]; then
      bad=$((bad + 1)); echo "layer $h: '$line' dev=$dev store inode=$ino loop inode=$back"
    fi
  done
  t "(a) each of $p's $cnt layers is a squashfs on a loop device backed by the store's image ($bad not)" test "$bad" = 0 -a "$cnt" -gt 0
}
# once NAME: no image is mounted twice under the data dir and each mount
# has one loop device (after a restart nothing is left from before)
once() {
  local n=$1 m l
  m=$(mounts_under "/var/lib/vk8s/$n/node/layers" | wc -l)
  l=$(store_loops | wc -l)
  echo "$n: $m layer mounts, $l loop devices on store images"
  t "(c) each layer mount of $n has one loop device ($m mounts, $l loop devices)" test "$m" -gt 0 -a "$m" = "$l"
  t "(c) no layer is mounted twice" test -z "$(mounts_under "/var/lib/vk8s/$n/node/layers" | sort | uniq -d)"
}
gone() { # gone WHAT: (e) nothing of the store is mounted or held by a loop device
  t "(e) $1: no mount under /var/lib/vk8s" test -z "$(mounts_under /var/lib/vk8s)"
  t "(e) $1: no loop device on a store image ($(store_loops | wc -l))" test -z "$(store_loops)"
  t "(e) $1: the store stays (a cache, which vk8s layers gc trims)" test -d "$store"
}
cleanup() {
  [ -n "${ctr:-}" ] && sudo env HOME="$HOME" VK8S_ASSETS="$CTR_ASSETS" PATH="$PATH" "$v" delete "$ctr" >/dev/null 2>&1
  for n in nl-off nl-on nl-next; do "$v" delete "$n" >/dev/null 2>&1; done
  pkill -f "$v layers serve" 2>/dev/null
  true
}
trap cleanup EXIT

uname -r
cleanup
loops0=$(sudo losetup -l -n 2>/dev/null | wc -l)

# --- off: the node unpacks for itself
if phase off nl-off -u VK8S_LAYERS; then
  t "store off: the node holds its own unpacked copy ($m_off_copies)" test "$m_off_copies" -ge 1
  t "store off: no layer mount under the data dir" test -z "$(mounts_under /var/lib/vk8s/nl-off/node/layers)"
  t "store off: delete" "$v" delete nl-off
fi
# the off phase must leave no store behind for the on phase's cold start
t "no store image before the on phase" test -z "$(sudo find "$store" -maxdepth 1 -name '*.sqfs' 2>/dev/null)"

# --- on: the node stands on the store's layer images
if phase on nl-on VK8S_LAYERS=1; then
  n=nl-on
  t "create said where the layers mount" grep -q "^Shared layer store: $store (VK8S_LAYERS=1), its layers mounted under /var/lib/vk8s/$n/node/layers" <<<"$create_out"
  t "the unit names the store" grep -qx "Environment=VK8S_LAYERS_STORE=$store" "/etc/systemd/system/vk8s-$n.service"
  echo "== (a) the pods' root overlays are the store's images"
  on_layers "$n" lay-cold; hex_cold=$hexes
  on_layers "$n" lay-warm; hex_warm=$hexes
  t "(a) both pods stand on the same layers" test -n "$hex_cold" -a "$hex_cold" = "$hex_warm"
  echo "== (b) each layer is on the host once"
  bad=0
  for h in $hex_cold; do
    c=$(sudo find "$HOME/.vk8s" /var/lib/vk8s -xdev -name "$h.sqfs" 2>/dev/null | wc -l)
    [ "$c" = 1 ] || { bad=$((bad + 1)); echo "$h.sqfs: $c copies"; }
  done
  t "(b) one image per layer ($bad not)" test "$bad" = 0
  t "(b) the node holds no unpacked copy of the image ($m_on_copies)" test "$m_on_copies" = 0
  held=$(sudo cat "$HOME/.vk8s/clusters/$n/share/layers.held" 2>/dev/null)
  miss=0
  for h in $hex_cold; do grep -q "sha256:$h " <<<"$held" || miss=$((miss + 1)); done
  t "(b) the cluster's layers.held names every layer of the pod, so gc keeps them ($miss missing)" test "$miss" = 0
  echo "MEASURE native-layers store=on layer_images=$(sudo find "$store" -maxdepth 1 -name '*.sqfs' | wc -l) layer_mounts=$(mounts_under "/var/lib/vk8s/$n/node/layers" | wc -l) loop_devices_on_layer_images=$(store_loops | wc -l)"
  once "$n"

  echo "== (c) a crash and the unit's restart"
  sum0=$(k "$n" exec lay-cold -- sha256sum /usr/sbin/nginx 2>/dev/null | cut -d' ' -f1)
  before=$(mounts_under "/var/lib/vk8s/$n/node/layers" | wc -l)
  sudo systemctl kill -s KILL "vk8s-$n.service"
  left=$(mounts_under "/var/lib/vk8s/$n/node/layers" | wc -l)
  echo "after the kill: $left of $before layer mounts are still there (nothing unmounted them)"
  # systemd starts the unit again after RestartSec=5s
  t "(c) the unit runs again" until_ok 120 systemctl is-active --quiet "vk8s-$n.service"
  up "$n"
  # the API still shows the pods Ready from before the kill until the
  # node's kubelet is back: wait for each container's restart
  t "(c) the first pod's container was started again" until_ok 600 restarted "$n" lay-cold
  t "(c) the second pod's container was started again" until_ok 600 restarted "$n" lay-warm
  t "(c) the first pod is Ready again" until_ok 600 pod_ready "$n" lay-cold
  t "(c) the second pod is Ready again" until_ok 600 pod_ready "$n" lay-warm
  t "(c) the first pod answers an exec" until_ok 120 k "$n" exec lay-cold -- true
  on_layers "$n" lay-cold
  t "(c) the pod stands on the same layers as before" test "$hexes" = "$hex_cold"
  sum1=$(k "$n" exec lay-cold -- sha256sum /usr/sbin/nginx 2>/dev/null | cut -d' ' -f1)
  t "(c) the pod reads the same nginx from its layers ($sum1)" test -n "$sum0" -a "$sum0" = "$sum1"
  once "$n"
  [ $fails = 0 ] || diag "$n"

  if [ -n "${CTR_ASSETS:-}" ]; then
    echo "== (d) a node container on the same layers, at the same time"
    ctr=nl-ctr
    C() { sudo timeout 2400 env HOME="$HOME" VK8S_ASSETS="$CTR_ASSETS" VK8S_LAYERS=1 PATH="$PATH" "$v" "$@"; }
    kc() { sudo "$(command -v kubectl)" --kubeconfig "$HOME/.vk8s/clusters/$ctr/kubeconfig.yaml" --request-timeout=30s "$@"; }
    images0=$(sudo find "$store" -maxdepth 1 -name '*.sqfs' | wc -l)
    if C create "$ctr" --backend container --connect=false; then
      pass "(d) create $ctr (one node container)"
      t "(d) its node is Ready" kc wait --for=condition=Ready node --all --timeout=900s
      t0=$(now)
      kc run lay-ctr --image="$image" --restart=Always >/dev/null 2>&1
      if kc wait --for=condition=Ready pod/lay-ctr --timeout=900s >/dev/null 2>&1; then c2=$(secs "$t0" "$(now)"); else c2=fail; fi
      t "(d) its pod is Ready (the store has the image, $c2 s)" test "$c2" != fail
      echo "MEASURE native-layers second_cluster=container ready_s=$c2"
      cl=$(kc exec lay-ctr -- cat /proc/self/mountinfo 2>&1 | awk '$5 == "/"' | tail -1 | sed -n 's/.*[ ,]lowerdir=\([^, ]*\).*/\1/p' | tr ':' '\n')
      chex=$(sed -n 's|^/mnt/layers/||p' <<<"$cl" | sort)
      t "(d) the container's pod stands on the same layers as the native pod" test -n "$chex" -a "$chex" = "$hex_cold"
      both=0
      for h in $hex_cold; do
        ino=$(sudo stat -c %i "$store/$h.sqfs")
        [ "$(store_loops | awk -v i="$ino" '$2 == i' | wc -l)" -ge 2 ] && both=$((both + 1))
      done
      t "(d) each of those images has a loop device of each cluster ($both of $(wc -w <<<"$hex_cold"))" test "$both" = "$(wc -w <<<"$hex_cold")"
      csum0=$(kc exec lay-ctr -- sha256sum /usr/sbin/nginx 2>/dev/null | cut -d' ' -f1)
      native_mounts=$(mounts_under "/var/lib/vk8s/$n/node/layers" | wc -l)
      loops_both=$(store_loops | wc -l)
      t "store on: delete $n (the native cluster) while $ctr runs" "$v" delete "$n"
      t "(d) no mount under /var/lib/vk8s after the native delete" test -z "$(mounts_under /var/lib/vk8s)"
      loops_ctr=$(store_loops | wc -l)
      t "(d) the native delete took its own loop devices only ($loops_both before, $native_mounts its own, $loops_ctr after)" test "$loops_ctr" = "$((loops_both - native_mounts))" -a "$loops_ctr" -gt 0
      # the container's pod reads its program again from the image, not from the page cache
      sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'
      csum1=$(kc exec lay-ctr -- sha256sum /usr/sbin/nginx 2>/dev/null | cut -d' ' -f1)
      t "(d) the container's pod still runs and reads the same nginx from its layers ($csum1)" test -n "$csum0" -a "$csum0" = "$csum1" -a "$csum0" = "$sum0"
      t "(d) the container's pod is still Ready" test "$(kc get pod lay-ctr -o 'jsonpath={.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = True
      kc run lay-ctr2 --image="$image" --restart=Always >/dev/null 2>&1
      t "(d) a new pod of the image starts in the container cluster after the native delete" kc wait --for=condition=Ready pod/lay-ctr2 --timeout=300s
      t "(d) no layer image was added for the second cluster ($images0, $(sudo find "$store" -maxdepth 1 -name '*.sqfs' | wc -l) now)" \
        test "$(sudo find "$store" -maxdepth 1 -name '*.sqfs' | wc -l)" -ge "$images0"
      t "store on: delete $ctr (the last cluster)" C delete "$ctr"
    else
      fail "(d) create $ctr"
      sudo tail -n 40 "$HOME/.vk8s/clusters/$ctr/console.log" 2>/dev/null
      C delete "$ctr" >/dev/null 2>&1
      "$v" delete "$n" >/dev/null 2>&1
    fi
    ctr=
    gone "after the last delete"
  else
    echo "== (d) the next native cluster on the same layers"
    t "store on: delete $n" "$v" delete "$n"
    gone "after the first delete"
    fills0=$(grep -c ' layers in ' "$HOME/.vk8s/layers-serve.log" 2>/dev/null)
    images0=$(sudo find "$store" -maxdepth 1 -name '*.sqfs' | wc -l)
    n=nl-next
    if create "$n" VK8S_LAYERS=1; then
      pass "(d) create $n"
      up "$n"
      c2=$(pod "$n" lay-cold)
      t "(d) its pod is Ready (the store has the image, $c2 s)" test "$c2" != fail
      echo "MEASURE native-layers second_cluster=native ready_s=$c2"
      on_layers "$n" lay-cold
      t "(d) the pod stands on the first cluster's layers" test "$hexes" = "$hex_cold"
      t "(d) no layer image was written for it ($images0 before, $(sudo find "$store" -maxdepth 1 -name '*.sqfs' | wc -l) now)" \
        test "$(sudo find "$store" -maxdepth 1 -name '*.sqfs' | wc -l)" = "$images0"
      timing "$n" lay-cold
      [ $fails = 0 ] || diag "$n"
      t "store on: delete $n (the last cluster)" "$v" delete "$n"
    else
      fail "(d) create $n"; diag "$n"; "$v" delete "$n" >/dev/null 2>&1
    fi
    gone "after the last delete"
  fi
  loops1=$(sudo losetup -l -n 2>/dev/null | wc -l)
  echo "MEASURE native-layers loop_devices_before=$loops0 after_the_last_delete=$loops1"
  t "(e) as many loop devices as before the test ($loops0, $loops1)" test "$loops1" -le "$loops0"
fi

if [ -n "${m_on_data:-}" ] && [ -n "${m_off_data:-}" ]; then
  on_sum=$((m_on_data + m_on_store)); off_sum=$((m_off_data + m_off_store))
  echo "MEASURE native-layers disk_kib off=$off_sum (data $m_off_data, store $m_off_store) on=$on_sum (data $m_on_data, store $m_on_store) ratio_on_off=$(awk -v a=$on_sum -v b=$off_sum 'BEGIN { printf "%.2f", a / b }')"
  echo "MEASURE native-layers ready_s cold off=$m_off_cold on=$m_on_cold warm off=$m_off_warm on=$m_on_warm"
fi
if [ $fails = 0 ]; then echo "native_layers: OK"; else echo "native_layers: $fails FAIL"; exit 1; fi
