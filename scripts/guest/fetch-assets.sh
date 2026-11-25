#!/usr/bin/env bash
# Assembles out/assets/<ver>/bin, the Kubernetes binaries of the assets disk,
# from public sources only, each pinned by SHA-256:
#   - loft-sh/kubernetes's release bundle (the layout vind's
#     ghcr.io/loft-sh/kubernetes:<ver>-full image carries): control plane
#     (kube-apiserver, kube-controller-manager, kube-scheduler, etcd,
#     etcdctl, etcdutl, kine, konnectivity-server) and the node bundle
#     (kubelet, kubeadm, kubectl, containerd, containerd-shim-runc-v2, runc,
#     ctr, the CNI plugins bridge, host-local, loopback and portmap, the
#     pause image)
#   - gVisor (google/gvisor's GitHub release, checked against its
#     SHA256SUMS; docs/GOAL.md section 8): runsc, containerd-shim-runsc-v1
#     and the gvisor-bin/ helpers runsc runs from beside itself, for the
#     opt-in gvisor RuntimeClass. The .tar.bz2, not the .tar.zstd: every
#     tar reads bzip2 (macOS's too) without a zstd tool. Left out of
#     gvisor-bin/: checkpointgofer (runsc checkpoint only) and
#     runsc-metric-server (`runsc metric-server` only), 66 MB that no pod
#     start runs (gVisor runsc/sandbox/sandbox.go, runsc/cmd/metric_server.go).
#   - kube-router (cloudnativelabs/kube-router's GitHub release, checked
#     against its checksums.txt; docs/GOAL.md section 10): the network
#     policy controller each node's PID 1 runs (src/guest/netpol.bend), the
#     release's static binary alone (not its LICENSE and README).
# Preloaded add-on images (bin/images) come from scripts/guest/images.sh.
#
# One arch per run: ARCH (arm64/aarch64 or amd64/x86_64; default
# `uname -m`). arm64 writes out/assets/<ver>/bin, amd64
# out/assets/<ver>-amd64/bin, so both sets can sit side by side.
#
# Each archive comes from its GitHub release ($ASSETS_UPSTREAM, default
# https://github.com), else from our mirror release (pins.sh,
# $INPUTS_MIRROR; scripts/guest/mirror-inputs.sh uploads them there), and
# only with the SHA-256 pinned here (pin_get). After a pin bump, run
# scripts/guest/mirror-inputs.sh.
#
# usage: fetch-assets.sh [--download | --pins]
#   --download  fetch and check the archives of ARCH, unpack nothing
#   --pins      print "<mirror name> <sha256> <file> <url>" of each
#               archive of ARCH; fetch nothing
#
# Left out, since nothing in the guest runs them (docs/GOAL.md section 9,
# docs/ref/footprint-decisions.md A2): helm, crictl, vcluster-tunnel,
# pause-image.txt, the CNI plugins bandwidth and firewall (no CNI config of
# vk8s or flannel names them), and the kube-proxy binary (kube-proxy runs
# as kubeadm's DaemonSet from its preloaded image).
set -euo pipefail
cd "$(dirname "$0")/../.."
. scripts/guest/pins.sh
case ${1:-} in
  ""|--download|--pins) mode=${1:-} ;;
  *) sed -n 's/^# usage: //p' "$0"; exit 2 ;;
esac
K8S=${K8S:-v1.36.6}
GVISOR=20261109.0
KROUTER=2.12.0
case ${ARCH:-$(uname -m)} in
  arm64|aarch64)
    arch=arm64 sfx="" garch=aarch64
    # loft-sh/kubernetes v1.36.6 kubernetes-v1.36.6-arm64-full.tar.gz
    BUNDLE_SHA=e017844db66d6f55dd91b6ce71c4529470717eef7d756fe4b500939eaec6f40a
    # gVisor release-20261109.0 SHA256SUMS, gvisor-aarch64.tar.bz2
    GVISOR_SHA=795f87ab171b7a228d8b0e7e2d422c41c29dc7e37792f21099589dc3527ab1f0
    # kube-router v2.12.0 checksums.txt, kube-router_2.12.0_linux_arm64.tar.gz
    KROUTER_SHA=9606914ac019bd28cd2f4b1adec03d70d15b0162705445a80327598ce0a4518a ;;
  amd64|x86_64)
    arch=amd64 sfx=-amd64 garch=x86_64
    # loft-sh/kubernetes v1.36.6 kubernetes-v1.36.6-amd64-full.tar.gz
    BUNDLE_SHA=22d989e057caa2231500cfbfea0fdb49a6ab62193a4a230bb25447236a687c69
    # gVisor release-20261109.0 SHA256SUMS, gvisor-x86_64.tar.bz2
    GVISOR_SHA=0846228061b05eb936a96ed2ea205cbd8ddf6936c946f8a390b699cff3b5c138
    # kube-router v2.12.0 checksums.txt, kube-router_2.12.0_linux_amd64.tar.gz
    KROUTER_SHA=3d7e2f741f28b75ecae4dc1f7761a6f62fb908664ec06bfb6bde743d933a700e ;;
  *) echo "fetch-assets: unknown arch ${ARCH:-$(uname -m)} (arm64 or amd64)" >&2; exit 2 ;;
esac
up=${ASSETS_UPSTREAM:-https://github.com}
# file, SHA-256, URL and name in the mirror release (it says the version
# and the arch) of each archive
pins="full$sfx.tgz $BUNDLE_SHA $up/loft-sh/kubernetes/releases/download/$K8S/kubernetes-$K8S-$arch-full.tar.gz kubernetes-$K8S-$arch-full.tar.gz
gvisor$sfx.tbz $GVISOR_SHA $up/google/gvisor/releases/download/release-$GVISOR/gvisor-$garch.tar.bz2 gvisor-$GVISOR-$garch.tar.bz2
krouter$sfx.tgz $KROUTER_SHA $up/cloudnativelabs/kube-router/releases/download/v$KROUTER/kube-router_${KROUTER}_linux_$arch.tar.gz kube-router_${KROUTER}_linux_$arch.tar.gz"
w=out/assets
if [ "$mode" = --pins ]; then
  while read -r f sum url name; do echo "$name $sum $w/$f $url"; done <<<"$pins"
  exit 0
fi
mkdir -p "$w"; cd "$w"
b=$K8S$sfx/bin
# Each run unpacks into its own private directory (review pr-47 P2): two
# runs at once (ARCH=arm64 and ARCH=amd64) never share an extraction or
# download path, so one never copies the other's binaries. The kept
# images wait there too and go back into $b even when the run fails.
x=$(mktemp -d "$PWD/.fetch-$arch.XXXXXX")
cleanup() {
  if [ -d "$x/images" ] && [ ! -e "$b/images" ]; then mkdir -p "$b" && mv "$x/images" "$b/images"; fi
  rm -rf "$x"
}
trap cleanup EXIT
get() { # file sha url mirror-name: downloads privately, then renames into place
  [ -f "$1" ] && pin_ok "$2" "$1" && return 0
  pin_get "$3" "$x/$1" "$2" "$INPUTS_MIRROR/$4"
  mv -f "$x/$1" "$1"
}
while read -r f sum url name; do get "$f" "$sum" "$url" "$name"; done <<<"$pins"
if [ "$mode" = --download ]; then
  while read -r f sum url name; do echo "$w/$f: sha256 $sum"; done <<<"$pins"
  exit 0
fi
# Each archive is linked (or copied) into the private directory and
# checked again there: a same-arch run may have renamed a new file over
# it after this run's check, and a link keeps the file this run checks.
while read -r f sum url name; do
  ln -f "$f" "$x/$f" 2>/dev/null || cp "$f" "$x/$f"
  pin_ok "$sum" "$x/$f" || { echo "SHA-256 mismatch: $f" >&2; exit 1; }
done <<<"$pins"
mkdir -p "$x/loft/node" "$x/gvisor" "$x/krouter"
tar -xzf "$x/full$sfx.tgz" -C "$x/loft"
tar -xzf "$x/loft/release/kubernetes-$K8S-$arch.tar.gz" -C "$x/loft/node"
tar -xjf "$x/gvisor$sfx.tbz" -C "$x/gvisor"
tar -xzf "$x/krouter$sfx.tgz" -C "$x/krouter" kube-router
[ -d "$b/images" ] && mv "$b/images" "$x/images"
rm -rf "$b" && mkdir -p "$b"
cp "$x"/loft/release/{kine,etcd,etcdctl,etcdutl,kube-apiserver,kube-controller-manager,kube-scheduler,konnectivity-server} "$b/"
n=$x/loft/node/release
cp "$n"/{kubelet,kubeadm,kubectl,containerd,containerd-shim-runc-v2,runc,ctr,pause-image.tar} "$b/"
mkdir -p "$b/cni/bin" && cp "$n"/cni/bin/{bridge,host-local,loopback,portmap} "$b/cni/bin/"
cp "$x/gvisor/runsc" "$x/gvisor/containerd-shim-runsc-v1" "$b/"
cp -R "$x/gvisor/gvisor-bin" "$b/" && rm -f "$b/gvisor-bin/checkpointgofer" "$b/gvisor-bin/runsc-metric-server"
cp "$x/krouter/kube-router" "$b/" && chmod +x "$b/kube-router"
if [ -d "$x/images" ]; then mv "$x/images" "$b/images"; fi
echo "assets in $w/$b:"; ls "$b"
