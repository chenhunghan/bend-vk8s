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
#   - the CNCF distribution registry (vk8s's image cache VM), checked against
#     its published .sha256
#   - gVisor (google/gvisor's GitHub release, checked against its
#     SHA256SUMS; docs/GOAL.md section 8): runsc, containerd-shim-runsc-v1
#     and the gvisor-bin/ helpers runsc runs from beside itself, for the
#     opt-in gvisor RuntimeClass. The .tar.bz2, not the .tar.zstd: every
#     tar reads bzip2 (macOS's too) without a zstd tool. Left out of
#     gvisor-bin/: checkpointgofer (runsc checkpoint only) and
#     runsc-metric-server (`runsc metric-server` only), 66 MB that no pod
#     start runs (gVisor runsc/sandbox/sandbox.go, runsc/cmd/metric_server.go).
# Preloaded add-on images (bin/images) come from scripts/guest/images.sh.
#
# One arch per run: ARCH (arm64/aarch64 or amd64/x86_64; default
# `uname -m`). arm64 writes out/assets/<ver>/bin, amd64
# out/assets/<ver>-amd64/bin, so both sets can sit side by side.
#
# Left out, since nothing in the guest runs them (docs/GOAL.md section 9,
# docs/ref/footprint-decisions.md A2): helm, crictl, vcluster-tunnel,
# pause-image.txt, the CNI plugins bandwidth and firewall (no CNI config of
# vk8s or flannel names them), and the kube-proxy binary (kube-proxy runs
# as kubeadm's DaemonSet from its preloaded image).
set -euo pipefail
cd "$(dirname "$0")/../.."
K8S=${K8S:-v1.36.6}
REG=3.1.2
GVISOR=20261109.0
case ${ARCH:-$(uname -m)} in
  arm64|aarch64)
    arch=arm64 sfx="" garch=aarch64
    # loft-sh/kubernetes v1.36.6 kubernetes-v1.36.6-arm64-full.tar.gz
    BUNDLE_SHA=e017844db66d6f55dd91b6ce71c4529470717eef7d756fe4b500939eaec6f40a
    # distribution v3.1.2 registry_3.1.2_linux_arm64.tar.gz.sha256
    REG_SHA=09d26f88d2c0f161bd1b8bfc6c123571cc3d291dcca8af5477b3cacc4ec95e73
    # gVisor release-20261109.0 SHA256SUMS, gvisor-aarch64.tar.bz2
    GVISOR_SHA=795f87ab171b7a228d8b0e7e2d422c41c29dc7e37792f21099589dc3527ab1f0 ;;
  amd64|x86_64)
    arch=amd64 sfx=-amd64 garch=x86_64
    # loft-sh/kubernetes v1.36.6 kubernetes-v1.36.6-amd64-full.tar.gz
    BUNDLE_SHA=22d989e057caa2231500cfbfea0fdb49a6ab62193a4a230bb25447236a687c69
    # distribution v3.1.2 registry_3.1.2_linux_amd64.tar.gz.sha256
    REG_SHA=40df2224d410f72ae425c3371873b078bbdbda3b8b612be9571f0e6751f3acc8
    # gVisor release-20261109.0 SHA256SUMS, gvisor-x86_64.tar.bz2
    GVISOR_SHA=0846228061b05eb936a96ed2ea205cbd8ddf6936c946f8a390b699cff3b5c138 ;;
  *) echo "fetch-assets: unknown arch ${ARCH:-$(uname -m)} (arm64 or amd64)" >&2; exit 2 ;;
esac
w=out/assets; mkdir -p "$w"; cd "$w"
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
sha256_ok() { # sum file
  if command -v shasum >/dev/null 2>&1; then echo "$1  $2" | shasum -a 256 -c -s; else echo "$1  $2" | sha256sum -c --status; fi
}
get() { # url file sha: downloads privately, then renames into place
  [ -f "$2" ] && sha256_ok "$3" "$2" && return 0
  curl -fL --retry 3 -o "$x/$2" "$1"
  sha256_ok "$3" "$x/$2" || { echo "SHA-256 mismatch: $2" >&2; exit 1; }
  mv -f "$x/$2" "$2"
}
get "https://github.com/loft-sh/kubernetes/releases/download/$K8S/kubernetes-$K8S-$arch-full.tar.gz" "full$sfx.tgz" "$BUNDLE_SHA"
get "https://github.com/distribution/distribution/releases/download/v$REG/registry_${REG}_linux_$arch.tar.gz" "reg$sfx.tgz" "$REG_SHA"
get "https://github.com/google/gvisor/releases/download/release-$GVISOR/gvisor-$garch.tar.bz2" "gvisor$sfx.tbz" "$GVISOR_SHA"
# Each archive is linked (or copied) into the private directory and
# checked again there: a same-arch run may have renamed a new file over
# it after this run's check, and a link keeps the file this run checks.
for f in "full$sfx.tgz:$BUNDLE_SHA" "reg$sfx.tgz:$REG_SHA" "gvisor$sfx.tbz:$GVISOR_SHA"; do
  a=${f%%:*}
  ln -f "$a" "$x/$a" 2>/dev/null || cp "$a" "$x/$a"
  sha256_ok "${f#*:}" "$x/$a" || { echo "SHA-256 mismatch: $a" >&2; exit 1; }
done
mkdir -p "$x/loft/node" "$x/reg" "$x/gvisor"
tar -xzf "$x/full$sfx.tgz" -C "$x/loft"
tar -xzf "$x/loft/release/kubernetes-$K8S-$arch.tar.gz" -C "$x/loft/node"
tar -xzf "$x/reg$sfx.tgz" -C "$x/reg"
tar -xjf "$x/gvisor$sfx.tbz" -C "$x/gvisor"
[ -d "$b/images" ] && mv "$b/images" "$x/images"
rm -rf "$b" && mkdir -p "$b"
cp "$x"/loft/release/{kine,etcd,etcdctl,etcdutl,kube-apiserver,kube-controller-manager,kube-scheduler,konnectivity-server} "$b/"
n=$x/loft/node/release
cp "$n"/{kubelet,kubeadm,kubectl,containerd,containerd-shim-runc-v2,runc,ctr,pause-image.tar} "$b/"
mkdir -p "$b/cni/bin" && cp "$n"/cni/bin/{bridge,host-local,loopback,portmap} "$b/cni/bin/"
cp "$x/reg/registry" "$b/" && chmod +x "$b/registry"
cp "$x/gvisor/runsc" "$x/gvisor/containerd-shim-runsc-v1" "$b/"
cp -R "$x/gvisor/gvisor-bin" "$b/" && rm -f "$b/gvisor-bin/checkpointgofer" "$b/gvisor-bin/runsc-metric-server"
if [ -d "$x/images" ]; then mv "$x/images" "$b/images"; fi
echo "assets in $w/$b:"; ls "$b"
