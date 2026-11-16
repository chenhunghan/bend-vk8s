#!/usr/bin/env bash
# Builds the vk8s host binary (host/vk8s.bend) for Linux, the recipe of
# docs/ref/explore-linux-hosts.md D1 b: Bend emits C, then zig cc links it
# against glibc 2.34, the floor that Process.run needs
# (posix_spawn_file_actions_addclosefrom_np, host/effs/proc.c). One recipe
# serves CI, the Mac (for a Linux dev VM) and both arches, as
# scripts/guest/build.sh links vk8s-guest.
# When zig is missing or fails (for example without linux/kvm.h for the
# target), and the target is this machine's arch, it falls back to the
# native clang (D1 a); the glibc floor is then the build host's.
# The last line on stderr says which toolchain built the binary.
#   scripts/build-linux.sh [out/vk8s] [aarch64|x86_64]
#   VK8S_CC=zig or VK8S_CC=clang forces one; VK8S_GLIBC sets the floor.
set -euo pipefail
cd "$(dirname "$0")/.."
src=host/vk8s.bend
out=${1:-out/vk8s}
norm() { case $1 in aarch64|arm64) echo aarch64 ;; x86_64|amd64) echo x86_64 ;; *) echo "$1" ;; esac; }
arch=$(norm "${2:-$(uname -m)}")
here=$(norm "$(uname -m)")
case $arch in aarch64|x86_64) ;; *) echo "build-linux: unknown arch $arch (aarch64 or x86_64)" >&2; exit 2 ;; esac
glibc=${VK8S_GLIBC:-2.34}
want=${VK8S_CC:-}
mkdir -p "$(dirname "$out")"
c="$out.c"
log="$out.log"
# build beside the target, then rename: running vk8s processes (VMMs)
# keep the file they mapped
tmp="$out.new"
bend "$src" -o "$c" > "$log" 2>&1 || { cat "$log" >&2; exit 1; }
[ -s "$c" ] || { echo "build-linux: bend wrote no C to $c" >&2; cat "$log" >&2; exit 1; }
libs=(-lm -ldl -lpthread)
how=
if [ "$want" != clang ]; then
  if ! command -v zig >/dev/null 2>&1; then
    echo "build-linux: zig not found" >&2
  elif zig cc -target "$arch-linux-gnu.$glibc" -O2 -w "$c" "${libs[@]}" -o "$tmp" > "$log" 2>&1; then
    how="zig cc -target $arch-linux-gnu.$glibc"
  else
    echo "build-linux: zig cc -target $arch-linux-gnu.$glibc failed:" >&2
    head -40 "$log" >&2
  fi
fi
if [ -z "$how" ] && [ "$want" != zig ]; then
  if [ "$arch" != "$here" ]; then
    echo "build-linux: no native fallback for $arch on $here" >&2
  elif clang -O2 -w "$c" "${libs[@]}" -o "$tmp" > "$log" 2>&1; then
    how="native clang ($(clang --version | head -1); glibc floor of this host)"
  else
    echo "build-linux: native clang failed:" >&2
    head -40 "$log" >&2
  fi
fi
[ -n "$how" ] || exit 1
mv -f "$tmp" "$out"
rm -f "$log"
echo "build-linux: $out ($arch) built with $how" >&2
echo "$out"
