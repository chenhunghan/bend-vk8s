#!/usr/bin/env bash
# Assembles out/assets/<ver>/bin, the Kubernetes binaries of the assets disk,
# from public sources only, each pinned by SHA-256:
#   - loft-sh/kubernetes's release bundle (the layout vind's
#     ghcr.io/loft-sh/kubernetes:<ver>-full image carries): control plane
#     (kube-apiserver, kube-controller-manager, kube-scheduler, etcd, kine,
#     konnectivity-server, helm) and the node bundle (kubelet, kubeadm,
#     kubectl, containerd, runc, crictl, CNI plugins, pause image)
#   - kube-proxy from dl.k8s.io (checked against its published .sha256)
#   - the CNCF distribution registry (vk8s's image cache VM), checked against
#     its published .sha256
# Preloaded add-on images (bin/images) come from scripts/guest/images.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
K8S=${K8S:-v1.36.6}
BUNDLE_SHA=e017844db66d6f55dd91b6ce71c4529470717eef7d756fe4b500939eaec6f40a
REG=3.1.2
REG_SHA=09d26f88d2c0f161bd1b8bfc6c123571cc3d291dcca8af5477b3cacc4ec95e73
KP_SHA=f939429db4b2461807c7407f7644d38468ab3968ad8cb14ebe42c6adebeb559d
w=out/assets; mkdir -p "$w"; cd "$w"
get() { # url file sha
  [ -f "$2" ] && echo "$3  $2" | shasum -a 256 -c -s && return 0
  curl -fL --retry 3 -o "$2" "$1"
  echo "$3  $2" | shasum -a 256 -c -s || { echo "SHA-256 mismatch: $2" >&2; rm -f "$2"; exit 1; }
}
get "https://github.com/loft-sh/kubernetes/releases/download/$K8S/kubernetes-$K8S-arm64-full.tar.gz" full.tgz "$BUNDLE_SHA"
get "https://github.com/distribution/distribution/releases/download/v$REG/registry_${REG}_linux_arm64.tar.gz" reg.tgz "$REG_SHA"
get "https://dl.k8s.io/release/$K8S/bin/linux/arm64/kube-proxy" kube-proxy "$KP_SHA"
rm -rf loft reg && mkdir -p loft/node reg
tar -xzf full.tgz -C loft
tar -xzf "loft/release/kubernetes-$K8S-arm64.tar.gz" -C loft/node
tar -xzf reg.tgz -C reg
b=$K8S/bin
images=""; [ -d "$b/images" ] && { mv "$b/images" images.keep; images=1; }
rm -rf "$b" && mkdir -p "$b"
cp loft/release/{kine,etcd,etcdctl,etcdutl,kube-apiserver,kube-controller-manager,kube-scheduler,helm,konnectivity-server} "$b/"
cp -R loft/node/release/* "$b/"
cp kube-proxy reg/registry "$b/" && chmod +x "$b/kube-proxy" "$b/registry"
[ -n "$images" ] && mv images.keep "$b/images"
echo "assets in $w/$b:"; ls "$b"
