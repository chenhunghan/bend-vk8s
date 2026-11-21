# Pinned guest build inputs (docs/ref/review-bend-vk8s-pr-48.md #2),
# sourced by alpine-kernel.sh, build.sh and images.sh. Each download is
# checked against its SHA-256 here before use, so a changed mirror, CDN or
# "latest" never reaches the guest, and two builds of one commit read the
# same bytes (mksqfs.sh -reproducible then makes the same disks).
#
# Bumping: a pin is only data. Change it with its source in one commit.
#   Alpine:  Alpine keeps only the newest build of a package in a branch,
#            so a pinned .apk 404s after Alpine updates it. Take the new
#            name from https://dl-cdn.alpinelinux.org/alpine/$ALPINE_BRANCH/main/<arch>/
#            and its sha256sum. The linux-virt version must stay the one
#            scripts/guest/kernel.sh builds (KVER).
#   CA:      https://curl.se/docs/caextract.html lists the dated bundles;
#            curl.se/ca/cacert-<date>.pem.sha256 publishes their SHA-256.
#   Debian:  scripts/guest/debs.lock (scripts/guest/debs.py --lock).
#   Images:  the index digest of each tag (docker buildx imagetools
#            inspect <ref>, or crane digest <ref>).
# The Kubernetes binaries, the registry and gVisor are pinned in
# fetch-assets.sh, the 16 KiB kernel in kernel.sh.

ALPINE_BRANCH=v3.24
# alpine_pin ARCH PACKAGE: "<file>.apk <sha256>" for aarch64/x86_64 and
# linux-virt/busybox-static
alpine_pin() {
  case $1/$2 in
    aarch64/linux-virt) echo "linux-virt-6.18.64-r0.apk cf171f51ab44d637a7758dd5a2f6a4ecd7ddbea18d61b9e37a6d39357d2fb1d5" ;;
    x86_64/linux-virt) echo "linux-virt-6.18.64-r0.apk cdcff66a46c4c512accff5c569efa2ae44e6006d97286c0dd44775ea1d54901b" ;;
    aarch64/busybox-static) echo "busybox-static-1.37.0-r31.apk 965777e06b94bf11981d5f4ecdfcd577879f4b0dda544294d1dd3f72b217bc75" ;;
    x86_64/busybox-static) echo "busybox-static-1.37.0-r31.apk b0d6cfc585d7fdd12df359cc5d38d5e45894e9e9e78c4059eb41577d022ec734" ;;
    *) echo "pins.sh: no Alpine pin for $1/$2" >&2; return 1 ;;
  esac
}

# Mozilla's CA roots as curl.se publishes them, by date
CACERT_FILE=cacert-2026-11-05.pem
CACERT_SHA256=427c064216761a1e72a8b30f0d954d08cb6e4435a82091fb865afd20c8497285

# The add-on images of the images set (images.sh), each by its multi-arch
# index digest; the tag stays, so the nodes import them under the names
# their manifests use. kube-proxy's is per Kubernetes version.
image_pins() { # K8S version
  echo "ghcr.io/flannel-io/flannel:v0.28.10@sha256:f26b2403273cbbce2bdc262c62e7a6e74c0031b139df247fa0fd5801cb9f639d"
  echo "ghcr.io/flannel-io/flannel-cni-plugin:v1.9.1-flannel3@sha256:9fccdf677e6e26e76a4aa60da2113bab9852e8317287ba51b2c29778d2351345"
  echo "docker.io/coredns/coredns:1.14.2@sha256:e7e6440cfd1e919280958f5b5a6ab2b184d385bba774c12ad2a9e1e4183f90d9"
  case $1 in
    v1.36.6) echo "registry.k8s.io/kube-proxy:v1.36.6@sha256:70871b645aecbca013bfb8254ce29f49143822054b743b78485db1f5f0d5de2c" ;;
    *) echo "pins.sh: no kube-proxy pin for $1" >&2; return 1 ;;
  esac
}
# the throwaway helper pod images.sh exports through (not in the guest)
BUSYBOX_IMAGE=docker.io/library/busybox:1.36@sha256:73aaf090f3d85aa34ee199857f03fa3a95c8ede2ffd4cc2cdb5b94e566b11662

# pin_ok SHA256 FILE: whether FILE has this SHA-256
pin_ok() {
  if command -v shasum >/dev/null 2>&1; then echo "$1  $2" | shasum -a 256 -c -s; else echo "$1  $2" | sha256sum -c --status; fi
}

# pin_get URL FILE SHA256: FILE, downloaded unless it already has the
# SHA-256; a download with another one is removed and fails the build
pin_get() {
  [ -f "$2" ] && pin_ok "$3" "$2" && return 0
  rm -f "$2" "$2.part"
  curl -fsSL --retry 3 -o "$2.part" "$1"
  pin_ok "$3" "$2.part" || { echo "SHA-256 mismatch: $1 (want $3)" >&2; rm -f "$2.part"; return 1; }
  mv "$2.part" "$2"
}
