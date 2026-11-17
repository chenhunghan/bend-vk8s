#!/usr/bin/env bash
# Preloads the cluster add-on images into the assets disk: boots a
# throwaway vk8s cluster, lets it pull flannel, CoreDNS and kube-proxy,
# exports them from the node's containerd to the host share, and stores
# them in out/assets/<ver>/bin/images/ (scripts/guest/build.sh then puts
# them on the assets disk, and every node imports them at boot).
# The images are this host's arch (the cluster's): ARCH (arm64 or amd64,
# default uname -m) picks the platform and out/assets/<ver>[-amd64].
# Each image is pinned by its index digest (scripts/guest/pins.sh,
# image_pins): the node pulls it by tag, as its manifests name it, and an
# image whose digest is not the pin fails the build before it is exported.
set -euo pipefail
cd "$(dirname "$0")/../.."
. scripts/guest/pins.sh
K8S=${K8S:-v1.36.6}
case ${ARCH:-$(uname -m)} in
  arm64|aarch64) arch=arm64 sfx="" ;;
  amd64|x86_64) arch=amd64 sfx=-amd64 ;;
  *) echo "images.sh: unknown arch ${ARCH:-$(uname -m)} (arm64 or amd64)" >&2; exit 2 ;;
esac
pins=$(image_pins "$K8S")
name=vk8s-images-$$
dst=out/assets/$K8S$sfx/bin/images
mkdir -p "$dst"
out/vk8s create "$name" >/dev/null
trap 'out/vk8s delete "$name" >/dev/null 2>&1 || true' EXIT
export KUBECONFIG=$HOME/.vk8s/clusters/$name/share/kubeconfig.yaml
kubectl wait --for=condition=Ready node --all --timeout=900s >/dev/null
kubectl -n kube-system wait --for=condition=available deploy/coredns --timeout=900s >/dev/null
kubectl -n kube-flannel wait --for=condition=Ready pod --all --timeout=900s >/dev/null
kubectl -n kube-system wait --for=condition=Ready pod -l k8s-app=kube-proxy --timeout=900s >/dev/null
kubectl -n kube-system run nsenter --image="$BUSYBOX_IMAGE" --restart=Never --overrides='{"spec":{"hostPID":true,"containers":[{"name":"nsenter","image":"'"$BUSYBOX_IMAGE"'","command":["sleep","3600"],"securityContext":{"privileged":true}}]}}' >/dev/null
kubectl -n kube-system wait --for=condition=Ready pod/nsenter --timeout=600s >/dev/null
ctr='/var/lib/vcluster/bin/ctr --address /run/containerd/containerd.sock -n k8s.io'
for pin in $pins; do
  img=${pin%@*} want=${pin#*@}
  got=$(kubectl -n kube-system exec nsenter -- nsenter -t 1 -m -- sh -c "$ctr images ls name=='$img'" | awk 'NR > 1 { print $3 }')
  [ "$got" = "$want" ] || { echo "images.sh: $img is ${got:-not on the node}, not the pinned $want" >&2; exit 1; }
  f=$(echo "$img" | tr '/:' '__').tar
  # fetch the layer blobs again (the node's containerd discards them once
  # unpacked: discard_unpacked_layers, Plan.containerd_images), export
  # onto the node's disk, then copy over the share (ctr writing straight
  # onto the 9p share loses the file's tail)
  kubectl -n kube-system exec nsenter -- nsenter -t 1 -m -- sh -c "$ctr images pull --hosts-dir /etc/containerd/certs.d --platform linux/$arch '$img' >/dev/null && $ctr images export --platform linux/$arch /var/lib/vcluster/$f '$img' && cp /var/lib/vcluster/$f /var/lib/vk8s-host/$f && rm /var/lib/vcluster/$f"
  cp "$HOME/.vk8s/clusters/$name/share/$f" "$dst/$f.part"
  python3 -c 'import sys,tarfile; tarfile.open(sys.argv[1]).getmembers()' "$dst/$f.part"
  mv "$dst/$f.part" "$dst/$f"
  echo "preloaded $img@$want ($(du -h "$dst/$f" | cut -f1))"
done
