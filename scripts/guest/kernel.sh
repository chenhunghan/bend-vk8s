#!/usr/bin/env bash
# Builds the guest's arm64 kernel with 16 KiB pages (docs/ref/
# footprint-decisions.md M5): Linux 6.18.63, the version of Alpine's
# linux-virt that scripts/guest/build.sh takes by default, from Alpine's
# own config for it (aports main/linux-lts/virt.aarch64.config) with
# CONFIG_ARM64_16K_PAGES=y.
#
# Output in OUT (default out/build/kernel16k), the layout build.sh reads
# from Alpine's package:
#   Image             raw arm64 Image (what bend-vmm boots), uncompressed
#   lib/modules/<v>/  the modules (stripped, not compressed) and modules.dep
#   config            the final .config
#   SHA256SUMS        Image and every .ko, to compare two builds
#   build-time        seconds the make took
#
# Sources, each pinned by the hash in the aports APKBUILD at $APORTS (the
# same bytes Alpine built linux-virt 6.18.63 from):
#   https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.18.tar.xz
#   https://cdn.kernel.org/pub/linux/kernel/v6.x/patch-6.18.63.xz
#   aports $APORTS main/linux-lts/virt.aarch64.config
#
# The build runs in a pinned Debian container ($VK8S_DOCKER, default
# docker; the image by digest), natively on arm64 (the Mac, GitHub's
# ubuntu-24.04-arm) and with the aarch64-linux-gnu cross compiler
# elsewhere. VK8S_KERNEL_BUILD=host builds on this Linux host instead
# (needs gcc or aarch64-linux-gnu-gcc, make, bc, bison, flex, libssl-dev,
# libelf-dev, xz, patch, perl, python3, kmod).
#
# Reproducible: fixed KBUILD_BUILD_TIMESTAMP/USER/HOST/VERSION, fixed
# source and build paths in the container, no module signing (a random
# key per build; so no lockdown LSM, which selects it), no GCC plugins (latent_entropy seeds per build), no
# debug info.
#
# usage: kernel.sh [OUT]
set -euo pipefail
cd "$(dirname "$0")/../.."
KVER=6.18.63
KBASE=6.18
APORTS=aabe3e5ce3d1b3469580a931ce1746e05dc95c01
BASE_SHA512=88599ffdec96d150c1feb9b261ba93bb0301a9d0e1ad6bef7aeab1f5372cbfc57d8b43c7e902bd8f76921d1dbd8189663c142ea869e51d0e2b483b150ee00fe0
PATCH_SHA512=f22be4d6428719c3f9fbf290760555300be64d952e4747eac1c6249f727db1ef04ecc7ecd3dc2902464e91ae32036db274b170c5fc1e0d0071fb9f8bfc5a9d9a
CONFIG_SHA512=ffbe61069184a46baf90cbffeba5512df7e0d0b11c2404f629ad698bdfb6199269618013abdc2895a9bc960bb5e0425ee4f8a928fca08aae5b5ff97e49023e3f
CONFIG_SHA256=120ebd889badde4bcaf394325aae2fab73ce2ef3c18d30ad40f9443b3ba26b69
# debian:trixie-slim, the multi-arch index (docker-library/repo-info)
IMAGE=${VK8S_KERNEL_IMAGE:-debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2}
# the aports commit's time (main/linux-lts: upgrade to 6.18.63)
export KBUILD_BUILD_TIMESTAMP="Wed Nov 11 03:02:54 UTC 2026"
export KBUILD_BUILD_USER=vk8s KBUILD_BUILD_HOST=vk8s KBUILD_BUILD_VERSION=1
LOCALVERSION_STR=-0-virt16k

# --build SRC OUT: the build itself (in the container, or on the host)
if [ "${1:-}" = --build ]; then
  src=$2 out=$3
  w=${KBUILD_WORK:-/tmp/vk8s-kernel}
  rm -rf "$w"; mkdir -p "$w/build"
  tar -xJf "$src/linux-$KBASE.tar.xz" -C "$w"
  mv "$w/linux-$KBASE" "$w/linux"
  xz -dc "$src/patch-$KVER.xz" | patch -p1 -s -d "$w/linux"
  rm -f "$w"/linux/localversion*
  make_args=(-C "$w/linux" O="$w/build" ARCH=arm64 LOCALVERSION=)
  if [ "$(uname -m)" != aarch64 ] && [ "$(uname -m)" != arm64 ]; then
    make_args+=(CROSS_COMPILE=aarch64-linux-gnu-)
  fi
  cp "$src/virt.aarch64.config" "$w/build/.config"
  cfg() { "$w/linux/scripts/config" --file "$w/build/.config" "$@"; }
  # 16 KiB pages; 48-bit VA (4 levels with 16K), Alpine's choice
  cfg --disable ARM64_4K_PAGES --enable ARM64_16K_PAGES --disable ARM64_64K_PAGES \
      --enable ARM64_VA_BITS_48
  # the balloon and free page reporting, as with Alpine's kernel (M1)
  cfg --module VIRTIO_BALLOON --enable PAGE_REPORTING
  # reproducibility and build time. SECURITY_LOCKDOWN_LSM selects
  # MODULE_SIG (security/lockdown/Kconfig), so it goes too: without
  # signed modules, lockdown does not stop an unsigned module anyway.
  cfg --disable SECURITY_LOCKDOWN_LSM --disable SECURITY_LOCKDOWN_LSM_EARLY
  cfg --disable MODULE_SIG --disable MODULE_COMPRESS --disable GCC_PLUGINS \
      --disable GCC_PLUGIN_LATENT_ENTROPY \
      --disable DEBUG_INFO_BTF --disable DEBUG_INFO_DWARF5 --disable DEBUG_INFO_DWARF4 \
      --disable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT --enable DEBUG_INFO_NONE \
      --set-str LOCALVERSION "$LOCALVERSION_STR" --disable LOCALVERSION_AUTO
  make "${make_args[@]}" olddefconfig >/dev/null
  bad=0
  # Linux 6.10+ has no ARM64_PAGE_SHIFT: arm64 selects the generic
  # PAGE_SIZE_16KB, and arch/Kconfig derives PAGE_SHIFT from it.
  for want in CONFIG_ARM64_16K_PAGES=y '# CONFIG_ARM64_4K_PAGES is not set' CONFIG_PAGE_SIZE_16KB=y \
      CONFIG_PAGE_SHIFT=14 CONFIG_ARM64_VA_BITS=48 CONFIG_PGTABLE_LEVELS=4 CONFIG_VIRTIO_BALLOON=m \
      CONFIG_PAGE_REPORTING=y CONFIG_VIRTIO_MMIO=m CONFIG_VIRTIO_BLK=m CONFIG_EXT4_FS=m \
      "CONFIG_LOCALVERSION=\"$LOCALVERSION_STR\""; do
    grep -qxF "$want" "$w/build/.config" && continue
    opt=${want#\# }; opt=${opt%%[= ]*}
    echo "kernel.sh: .config lacks: $want (has: $(grep -E "^(# )?$opt[= ]" "$w/build/.config" || echo nothing))" >&2
    bad=1
  done
  # no module signing (a random key per build), however the option shows up
  for unwanted in CONFIG_MODULE_SIG=y CONFIG_MODULE_SIG_ALL=y CONFIG_GCC_PLUGIN_LATENT_ENTROPY=y \
      CONFIG_SECURITY_LOCKDOWN_LSM=y; do
    if grep -qxF "$unwanted" "$w/build/.config"; then
      echo "kernel.sh: .config has: $unwanted" >&2; bad=1
    fi
  done
  [ $bad = 0 ] || exit 1
  t0=$(date +%s)
  make "${make_args[@]}" -j"$(nproc)" Image modules
  t1=$(date +%s)
  rm -rf "$out"; mkdir -p "$out"
  make "${make_args[@]}" modules_install INSTALL_MOD_PATH="$out" INSTALL_MOD_STRIP=1 >/dev/null
  rm -f "$out"/lib/modules/*/build "$out"/lib/modules/*/source
  cp "$w/build/arch/arm64/boot/Image" "$out/Image"
  cp "$w/build/.config" "$out/config"
  echo $((t1 - t0)) > "$out/build-time"
  (cd "$out" && find Image lib -type f \( -name Image -o -name '*.ko' \) | LC_ALL=C sort | xargs sha256sum > SHA256SUMS)
  rm -rf "$w"
  echo "kernel $(ls "$out/lib/modules"):" \
    "Image $(stat -c %s "$out/Image") bytes, $(grep -c '\.ko$' "$out/SHA256SUMS") modules," \
    "make $((t1 - t0)) s, Image sha256 $(sha256sum "$out/Image" | cut -d' ' -f1)"
  exit 0
fi

out=${1:-out/build/kernel16k}
src=out/build/kernel-src
mkdir -p "$src"
sha() { # sha ALG FILE -> hex
  if command -v "sha$1sum" >/dev/null; then "sha$1sum" "$2" | cut -d' ' -f1; else shasum -a "$1" "$2" | cut -d' ' -f1; fi
}
get() { # get URL FILE ALG HASH
  [ -f "$src/$2" ] && [ "$(sha "$3" "$src/$2")" = "$4" ] && return 0
  curl -fL --retry 3 -o "$src/$2.part" "$1"
  local got; got=$(sha "$3" "$src/$2.part")
  [ "$got" = "$4" ] || { echo "kernel.sh: SHA-$3 mismatch for $2: $got" >&2; rm -f "$src/$2.part"; exit 1; }
  mv "$src/$2.part" "$src/$2"
}
get "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KBASE.tar.xz" "linux-$KBASE.tar.xz" 512 "$BASE_SHA512"
get "https://cdn.kernel.org/pub/linux/kernel/v6.x/patch-$KVER.xz" "patch-$KVER.xz" 512 "$PATCH_SHA512"
get "https://raw.githubusercontent.com/alpinelinux/aports/$APORTS/main/linux-lts/virt.aarch64.config" \
  virt.aarch64.config 512 "$CONFIG_SHA512"
[ "$(sha 256 "$src/virt.aarch64.config")" = "$CONFIG_SHA256" ] || { echo "kernel.sh: config SHA-256 mismatch" >&2; exit 1; }

if [ "${VK8S_KERNEL_BUILD:-container}" = host ]; then
  exec "$0" --build "$src" "$out"
fi
DOCKER=${VK8S_DOCKER:-docker}
pkgs="gcc libc6-dev make bc bison flex libssl-dev libelf-dev xz-utils patch perl python3 kmod cpio"
case "$(uname -m)" in aarch64|arm64) ;; *) pkgs="$pkgs gcc-aarch64-linux-gnu libc6-dev-arm64-cross" ;; esac
mkdir -p "$out"
"$DOCKER" run --rm -v "$PWD:/vk8s" -w /vk8s \
  -e KBUILD_BUILD_TIMESTAMP -e KBUILD_BUILD_USER -e KBUILD_BUILD_HOST -e KBUILD_BUILD_VERSION \
  "$IMAGE" bash -c "set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq && apt-get install -y -qq --no-install-recommends $pkgs >/dev/null
    gcc --version | head -1
    scripts/guest/kernel.sh --build '$src' /tmp/vk8s-out
    rm -rf '$out' && mkdir -p '$out' && cp -a /tmp/vk8s-out/. '$out/'
    chown -R $(id -u):$(id -g) '$out'"
echo "kernel in $out"
