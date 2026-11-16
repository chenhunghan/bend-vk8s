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
# Preloaded add-on images (bin/images) come from scripts/guest/images.sh.
#
# Left out, since nothing in the guest runs them (docs/GOAL.md section 9,
# docs/ref/footprint-decisions.md A2): helm, crictl, vcluster-tunnel,
# pause-image.txt, the CNI plugins bandwidth and firewall (no CNI config of
# vk8s or flannel names them), and the kube-proxy binary (kube-proxy runs
# as kubeadm's DaemonSet from its preloaded image).
set -euo pipefail
cd "$(dirname "$0")/../.."
K8S=${K8S:-v1.36.6}
BUNDLE_SHA=e017844db66d6f55dd91b6ce71c4529470717eef7d756fe4b500939eaec6f40a
REG=3.1.2
REG_SHA=09d26f88d2c0f161bd1b8bfc6c123571cc3d291dcca8af5477b3cacc4ec95e73
w=out/assets; mkdir -p "$w"; cd "$w"
get() { # url file sha
  [ -f "$2" ] && echo "$3  $2" | shasum -a 256 -c -s && return 0
  curl -fL --retry 3 -o "$2" "$1"
  echo "$3  $2" | shasum -a 256 -c -s || { echo "SHA-256 mismatch: $2" >&2; rm -f "$2"; exit 1; }
}
get "https://github.com/loft-sh/kubernetes/releases/download/$K8S/kubernetes-$K8S-arm64-full.tar.gz" full.tgz "$BUNDLE_SHA"
get "https://github.com/distribution/distribution/releases/download/v$REG/registry_${REG}_linux_arm64.tar.gz" reg.tgz "$REG_SHA"
rm -rf loft reg && mkdir -p loft/node reg
tar -xzf full.tgz -C loft
tar -xzf "loft/release/kubernetes-$K8S-arm64.tar.gz" -C loft/node
tar -xzf reg.tgz -C reg
b=$K8S/bin
images=""; [ -d "$b/images" ] && { mv "$b/images" images.keep; images=1; }
rm -rf "$b" && mkdir -p "$b"
cp loft/release/{kine,etcd,etcdctl,etcdutl,kube-apiserver,kube-controller-manager,kube-scheduler,konnectivity-server} "$b/"
n=loft/node/release
cp "$n"/{kubelet,kubeadm,kubectl,containerd,containerd-shim-runc-v2,runc,ctr,pause-image.tar} "$b/"
mkdir -p "$b/cni/bin" && cp "$n"/cni/bin/{bridge,host-local,loopback,portmap} "$b/cni/bin/"
cp reg/registry "$b/" && chmod +x "$b/registry"
[ -n "$images" ] && mv images.keep "$b/images"
echo "assets in $w/$b:"; ls "$b"
