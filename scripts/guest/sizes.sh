#!/usr/bin/env bash
# Reports the assets' sizes for docs/STATUS.md section 9: each asset
# uncompressed, then each role's set (docs/ref/footprint-decisions.md D1)
# and the whole bin/ as mksqfs.sh's squashfs and as that squashfs gzip'd
# (what release-assets.sh uploads). The guest root (vk8s-init, vk8s-guest,
# the Debian root, the modules) is not in ASSETS_BIN; pack.sh prints its
# size.
#
# usage: sizes.sh ASSETS_BIN
# Needs python3, gzip and sqfstar (squashfs-tools 4.6+).
set -euo pipefail
[ $# = 1 ] || { sed -n 's/^# usage: //p' "$0"; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
a=$1
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
echo "== per asset, KiB uncompressed"
(cd "$a" && du -sk -- * | sort -rn)
[ -d "$a/cni/bin" ] && (cd "$a/cni/bin" && du -sk -- * | sort -rn | sed 's|\t|\tcni/bin/|')
# The sets of D1. Names that are not in ASSETS_BIN are skipped.
node="kubelet kubeadm containerd containerd-shim-runc-v2 runc ctr cni pause-image.tar images"
cp="kube-apiserver kube-controller-manager kube-scheduler kubectl kine etcd etcdctl etcdutl"
classic="konnectivity-server"
cache="registry"
row() { # row NAME FILES...
  local name=$1; shift
  rm -rf "$w/set"; mkdir -p "$w/set"
  for f; do [ -e "$a/$f" ] && cp -R "$a/$f" "$w/set/"; done
  "$here/mksqfs.sh" "$w/img" "$w/set"
  printf '%-28s %8s %8s %8s\n' "$name" "$(du -sk "$w/set" | cut -f1)" \
    "$(( $(wc -c < "$w/img") / 1024 ))" "$(( $(gzip -9 -c "$w/img" | wc -c) / 1024 ))"
}
echo "== per role, KiB: uncompressed, squashfs (zstd), squashfs gzip'd"
row node $node
row control-plane $cp
row "classic (konnectivity)" $classic
row "image cache (registry)" $cache
row "standalone (node + cp)" $node $cp
row "all of bin/" $(cd "$a" && ls)
