#!/usr/bin/env bash
# Preloads the cluster add-on images into the assets disk: boots a
# throwaway vk8s cluster, lets it pull flannel, CoreDNS and kube-proxy,
# exports them from the node's containerd to the host share, and stores
# them in out/assets/<ver>/bin/images/ (scripts/guest/build.sh then puts
# them on the assets disk, and every node imports them at boot).
set -euo pipefail
cd "$(dirname "$0")/../.."
K8S=${K8S:-v1.36.6}
images=(
  ghcr.io/flannel-io/flannel:v0.28.10
  ghcr.io/flannel-io/flannel-cni-plugin:v1.9.1-flannel3
  docker.io/coredns/coredns:1.14.2
  registry.k8s.io/kube-proxy:$K8S
)
name=vk8s-images-$$
dst=out/assets/$K8S/bin/images
mkdir -p "$dst"
out/vk8s create "$name" >/dev/null
trap 'out/vk8s delete "$name" >/dev/null 2>&1 || true' EXIT
export KUBECONFIG=$HOME/.vk8s/clusters/$name/share/kubeconfig.yaml
kubectl wait --for=condition=Ready node --all --timeout=900s >/dev/null
kubectl -n kube-system wait --for=condition=available deploy/coredns --timeout=900s >/dev/null
kubectl -n kube-flannel wait --for=condition=Ready pod --all --timeout=900s >/dev/null
kubectl -n kube-system wait --for=condition=Ready pod -l k8s-app=kube-proxy --timeout=900s >/dev/null
kubectl -n kube-system run nsenter --image=busybox:1.36 --restart=Never --overrides='{"spec":{"hostPID":true,"containers":[{"name":"nsenter","image":"busybox:1.36","command":["sleep","3600"],"securityContext":{"privileged":true}}]}}' >/dev/null
kubectl -n kube-system wait --for=condition=Ready pod/nsenter --timeout=600s >/dev/null
for img in "${images[@]}"; do
  f=$(echo "$img" | tr '/:' '__').tar
  # export onto the node's disk, then copy over the share (ctr writing
  # straight onto the 9p share loses the file's tail)
  kubectl -n kube-system exec nsenter -- nsenter -t 1 -m -- sh -c "/var/lib/vcluster/bin/ctr --address /run/containerd/containerd.sock \
    -n k8s.io images export --platform linux/arm64 /var/lib/vcluster/$f '$img' && cp /var/lib/vcluster/$f /var/lib/vk8s-host/$f && rm /var/lib/vcluster/$f"
  cp "$HOME/.vk8s/clusters/$name/share/$f" "$dst/$f.part"
  python3 -c 'import sys,tarfile; tarfile.open(sys.argv[1]).getmembers()' "$dst/$f.part"
  mv "$dst/$f.part" "$dst/$f"
  echo "preloaded $img ($(du -h "$dst/$f" | cut -f1))"
done
