#!/usr/bin/env bash
# The shared layer store after scripts/regression.sh with VK8S_LAYERS=1
# (CI job kvm-regression, layers "1"; W7 of
# docs/ref/explore-layers-autofill.md). Nothing ran `vk8s layers fill`:
# `vk8s create` started the filler (`vk8s layers serve`) and the nodes'
# snapshotters asked it for each layer they prepared. It checks:
#
# - a pod's root overlay on cluster CLUSTER (default st) has only
#   /mnt/layers/<hex> lowerdirs (the probe pod runs busybox, so its
#   layer is asked for too);
# - the filler's log (~/.vk8s/layers-serve.log) has asks answered
#   "ok published" (and counts "ok present"), no ask answered "no ...",
#   no line refused, and a phase-times line (fetch, decompress, unpack,
#   fsync, rename) for the layers it published, and a diffID line that
#   says a layer was hashed while it was decompressed (Srv.diff.line);
# - ~/.vk8s/layers holds layers, one squashfs image each (<hex>.sqfs,
#   docs/ref/layers-sqfs.md), and no layer directory;
# - the nodes' snapshotters read layer images after mounting them (a
#   "layer sha256:<hex> read ms=N" line in a node's snapshotter.log).
#
# Writes out/layers-serve.log, out/layers-store.txt,
# out/layers-probe.txt and out/layers-snapshotter.log (the CI job
# uploads them). Prints PASS/FAIL lines;
# exits 1 on any FAIL.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
home=$HOME/.vk8s
log=$home/layers-serve.log
store=$home/layers
c=${CLUSTER:-st}
probe_image=${PROBE_IMAGE:-docker.io/library/busybox:1.36}
mkdir -p out

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
check() { # check NAME CONDITION-COMMAND...
  local name=$1; shift
  if "$@"; then pass "$name"; else fail "$name"; fi
}
hex='[0-9a-f]{64}'

echo "== a pod's root overlay on $c"
export KUBECONFIG=$home/clusters/$c/kubeconfig.yaml
kubectl delete pod layers-probe --ignore-not-found --wait=true >/dev/null 2>&1
kubectl run layers-probe --image="$probe_image" --restart=Never --command -- sleep 900
if kubectl wait --for=condition=Ready pod/layers-probe --timeout=300s; then
  kubectl exec layers-probe -- cat /proc/self/mountinfo >out/layers-probe.txt 2>&1
  kubectl get pod layers-probe -o wide >>out/layers-probe.txt 2>&1
else
  kubectl describe pod layers-probe >out/layers-probe.txt 2>&1
fi
# mountinfo: field 5 is the mount point; the super options follow " - "
rootline=$(awk '$5 == "/"' out/layers-probe.txt | tail -1)
echo "root: $rootline"
lower=$(sed -n 's/.*[ ,]lowerdir=\([^, ]*\).*/\1/p' <<<"$rootline")
echo "lowerdir: $lower"
check "the probe pod's root is an overlay with lowerdirs" test -n "$lower"
others=$(tr ':' '\n' <<<"$lower" | grep -Evc "^/mnt/layers/$hex\$")
check "every lowerdir of the pod's root is /mnt/layers/<hex> ($others others)" test -n "$lower" -a "$others" = 0

echo "== the filler's log"
cp "$log" out/layers-serve.log 2>/dev/null || : >out/layers-serve.log
check "the filler logged to $log" test -s "$log"
ans="^vk8s layers serve: sha256:$hex of [^ ]+: "
pub=$(grep -Ec "${ans}ok published\$" out/layers-serve.log)
pres=$(grep -Ec "${ans}ok present\$" out/layers-serve.log)
no=$(grep -Ec "${ans}no " out/layers-serve.log)
bad=$(grep -c 'refused a line that is not an ask' out/layers-serve.log)
echo "asks: $pub ok published, $pres ok present, $no no, $bad refused"
check "asks answered ok published ($pub)" test "$pub" -gt 0
check "no ask answered no ($no)" test "$no" = 0
[ "$no" = 0 ] || grep -E "${ans}no " out/layers-serve.log | head -20
check "no line refused ($bad)" test "$bad" = 0
ph='fetch [0-9]+ ms, decompress [0-9]+ ms, unpack [0-9]+ ms, fsync [0-9]+ ms, rename [0-9]+ ms'
timed=$(grep -Ec "^vk8s layers: sha256:$hex published in [0-9]+ ms: $ph\$" out/layers-serve.log)
check "the filler logged the phases of the layers it published ($timed)" test "$timed" -gt 0
# One read per layer (Srv.diff.line): a compressed layer's diffID comes
# from the decompress pass; only an uncompressed layer's tar is read for it.
once=$(grep -Ec "^vk8s layers: sha256:$hex diffID checked in [0-9]+ ms: hashed while decompressing, no second read of the tar\$" out/layers-serve.log)
again=$(grep -Ec "^vk8s layers: sha256:$hex diffID checked in [0-9]+ ms: hashed by reading the tar\$" out/layers-serve.log)
check "the filler hashed diffIDs while decompressing ($once layers; $again uncompressed, hashed by a read)" test "$once" -gt 0
echo "-- image fills"
grep -E "^vk8s layers serve: .*: [0-9]+ layers in [0-9]+ ms; summed over its layers: " out/layers-serve.log | sed 's/^vk8s layers serve: //'

echo "== the store"
n=$(find "$store" -mindepth 1 -maxdepth 1 -type f -name '*.sqfs' 2>/dev/null | grep -Ec "/$hex\\.sqfs\$")
dirs=$(find "$store" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
files=$(find "$home/layers" "$home/layer-refs" "$home/tmp" -type f 2>/dev/null | wc -l)
{
  echo "layers: $n"
  du -sk "$store" 2>&1
  ls -la "$store" 2>&1
} >out/layers-store.txt
head -2 out/layers-store.txt
check "~/.vk8s/layers holds layer images without a manual fill ($n)" test "$n" -gt 0
check "no layer directory in the store ($dirs)" test "$dirs" = 0
echo "host files under ~/.vk8s/layers, layer-refs and tmp: $files ($n layers)"

echo "== the nodes read the layer images they mounted"
# host/snapshotter.bend Snapd.warm (src/layers/pb.bend Spb.warm.v6): a
# node reads a layer image once after it mounts it, a small one before
# the Prepare is answered, so a container's first exec does not wait for
# the store's share after the kubelet said Running. One line per read in
# each node's snapshotter.log, on its share.
: >out/layers-snapshotter.log
for f in "$home/clusters/$c"/share/logs/snapshotter.log "$home/clusters/$c"/nodes/*/share/logs/snapshotter.log; do
  [ -f "$f" ] || continue
  echo "== $f" >>out/layers-snapshotter.log
  grep -E "^vk8s-snapshotter: (layer |ask for |call Prepare )" "$f" >>out/layers-snapshotter.log
done
readre="^vk8s-snapshotter: layer sha256:$hex read ms=[0-9]+\$"
reads=$(grep -Ec "$readre" out/layers-snapshotter.log)
notread=$(grep -Ec "^vk8s-snapshotter: layer sha256:$hex not read" out/layers-snapshotter.log)
check "the nodes read layer images after mounting them ($reads)" test "$reads" -gt 0
# a read that failed (tar could not read a file) leaves the layer to its
# first reads, as before: shown, not a failure of the store
echo "reads that failed: $notread"
grep -E "^vk8s-snapshotter: layer sha256:$hex not read" out/layers-snapshotter.log | head -5
grep -E "$readre" out/layers-snapshotter.log | sed 's/.* ms=//' | sort -n |
  awk '{ a[NR] = $1; s += $1 } END { if (NR) printf "layer reads: %d, %d ms in all, median %d ms, longest %d ms\n", NR, s, a[int((NR + 1) / 2)], a[NR] }'

kubectl delete pod layers-probe --ignore-not-found --wait=false >/dev/null 2>&1
line="### the shared layer store on $c: $n layer images, $files host files; asks: $pub ok published, $pres ok present, $no no; $timed layers timed; $reads layer images read by the nodes after their mount; $fails failed"
echo "$line"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then printf '%s\n' "$line" >>"$GITHUB_STEP_SUMMARY"; fi
echo "== $fails failed"
[ "$fails" = 0 ]
