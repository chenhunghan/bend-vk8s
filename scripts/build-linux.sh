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
#   VK8S_HEADLESS=1 (release builds) links no libX11: Bend's window runtime
#   (bend-vmm's --display) links Xlib directly, so a binary built with it
#   does not start on a server without libX11. Headless marks every X
#   function the C uses weak and drops -lX11 (they resolve to NULL; only
#   `vmm --display` calls them), skips `bend -o` (which links X11) and
#   checks the result has no libX11 dependency. Stopgap until Bend loads
#   Xlib with dlopen, as it already does Xrender and RandR.
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
libs=(-lm -ldl -lpthread -lX11)
how=
if [ "${VK8S_HEADLESS:-}" = 1 ]; then
  syms=$(grep -oE '\bX[A-Z][A-Za-z0-9]+\(' "$c" | tr -d '(' | sort -u)
  { echo; echo '#if defined(__linux__)'; for x in $syms; do echo "#pragma weak $x"; done; echo '#endif'; } >> "$c"
  libs=(-lm -ldl -lpthread)
  [ -n "$want" ] || want=zig
  # zig's glibc target sees no system headers: give it only X11's
  # (declarations only; nothing links against them)
  xinc=$(dirname "$out")/x11-include
  if [ -d /usr/include/X11 ]; then mkdir -p "$xinc"; ln -sfn /usr/include/X11 "$xinc/X11"; libs=(-I"$xinc" "${libs[@]}"); fi
fi
# Native first, as bend-vmm builds on Linux (its scripts/build.sh): `bend -o`
# compiles and links with Bend's own flags (X11 for --display included).
# The glibc floor is then the build host's (2.39 on Ubuntu 24.04).
if [ -z "$want" ] && [ "$arch" = "$here" ]; then
  if bend "$src" -o "$tmp" > "$log" 2>&1; then
    how="bend -o (native; glibc floor of this host)"
  else
    echo "build-linux: bend -o failed:" >&2
    head -40 "$log" >&2
  fi
fi
if [ -z "$how" ] && [ "$want" != clang ]; then
  # zig with a 2.34 floor lacks arc4random_buf (glibc 2.36); use 2.36 unless set
  glibc=${VK8S_GLIBC:-2.36}
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
if [ "${VK8S_HEADLESS:-}" = 1 ]; then
  if readelf -d "$tmp" 2>/dev/null | grep -q 'libX11'; then
    echo "build-linux: headless build still needs libX11" >&2; exit 1
  fi
  how="$how, headless (no libX11)"
fi
mv -f "$tmp" "$out"
rm -f "$log"
echo "build-linux: $out ($arch) built with $how" >&2
echo "$out"
