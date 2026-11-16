#!/usr/bin/env bash
# Packs one arch's guest assets for a GitHub release and pins them in the
# binary (docs/ref/explore-linux-hosts.md D2 a: one manifest per arch, one
# release tag per arch):
#   scripts/release-assets.sh [assets dir] [arch]
# arch is arm64/aarch64 or amd64/x86_64 (default: $ARCH, else uname -m);
# the assets dir defaults to ~/.vk8s/assets/v1.36.6 (arm64) or
# ~/.vk8s/assets/v1.36.6-amd64 (amd64), where scripts/guest/build.sh
# installs them.
# Writes out/release/<arch>/<file>.tgz (sparse-aware tar, so the 16 GiB
# data.img template stays small), out/release/<arch>/SHA256SUMS and
# src/cli/manifest_<arch>.bend: the version, file names and SHA-256 of each
# archive, which vk8s verifies before use on a host of that arch
# (src/cli/manifest.bend, Manifest.for_arch). The other arch's manifest
# stays as it is.
#   <Arch>.files()  the files every VM boots: Image, vk8s.cpio, base.img
#                   (the guest root), data.img
#   <Arch>.sets()   one archive per role set (docs/ref/footprint-
#                   decisions.md D1): node, control-plane, classic, cache
#                   and images (when the dir has it); a host fetches only
#                   the sets its VMs mount
# It also writes out/release/<arch>/VERSION (the version, the release tag).
#
# Then, from a tree that holds the new manifest_<arch>.bend (the binary
# pins it at build time), add each host binary built for that arch:
#   scripts/release-assets.sh --binary OS FILE [arch]
# OS is darwin or linux (darwin only for arm64). It checks that FILE is an
# executable of that OS and arch (ELF or Mach-O header), that the tree's
# manifest_<arch>.bend names the version in out/release/<arch>/VERSION,
# copies FILE to out/release/<arch>/vk8s-<os>-<arch> and puts its SHA-256
# in SHA256SUMS. arm64: vk8s-darwin-arm64 and vk8s-linux-arm64 share one
# release and its role sets; amd64: vk8s-linux-amd64 on the amd64 release.
# Uploading out/release/<arch>/* to the release named by the version is a
# manual, user-approved step (docs/RELEASE.md); this script publishes
# nothing.
set -euo pipefail
cd "$(dirname "$0")/.."
K8S=v1.36.6
sha256() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$@"; else sha256sum "$@"; fi; }
norm_arch() {
  case $1 in
    arm64|aarch64) echo arm64 ;;
    amd64|x86_64) echo amd64 ;;
    *) echo "release-assets: unknown arch $1 (arm64 or amd64)" >&2; return 2 ;;
  esac
}
# the hex bytes of FILE from offset OFF, N of them
bytes() { od -An -tx1 -j "$2" -N "$3" "$1" | tr -d ' \n'; }

if [ "${1:-}" = --binary ]; then
  [ $# = 3 ] || [ $# = 4 ] || { echo "usage: scripts/release-assets.sh --binary darwin|linux FILE [arch]" >&2; exit 2; }
  os=$2 file=$3
  arch=$(norm_arch "${4:-${ARCH:-$(uname -m)}}")
  out=out/release/$arch
  [ -f "$out/VERSION" ] && [ -f "$out/SHA256SUMS" ] || { echo "release-assets: no $out/VERSION; pack the $arch assets first (scripts/release-assets.sh DIR $arch)" >&2; exit 1; }
  ver=$(cat "$out/VERSION")
  grep -q "^  \"$ver\"\$" "src/cli/manifest_$arch.bend" || { echo "release-assets: src/cli/manifest_$arch.bend does not pin $ver; build the binary from a tree that holds the manifest this script wrote" >&2; exit 1; }
  [ -f "$file" ] && [ -x "$file" ] || { echo "release-assets: $file is not an executable file" >&2; exit 1; }
  magic=$(bytes "$file" 0 4)
  case $os-$arch in
    # ELF, 64-bit little endian; e_machine 183 (AArch64) or 62 (x86-64)
    linux-arm64) want="7f454c46 0201 b700" got="$magic $(bytes "$file" 4 2) $(bytes "$file" 18 2)" ;;
    linux-amd64) want="7f454c46 0201 3e00" got="$magic $(bytes "$file" 4 2) $(bytes "$file" 18 2)" ;;
    # Mach-O 64-bit, CPU_TYPE_ARM64 (0x0100000c)
    darwin-arm64) want="cffaedfe 0c000001" got="$magic $(bytes "$file" 4 4)" ;;
    *) echo "release-assets: no vk8s-$os-$arch release binary (darwin-arm64, linux-arm64, linux-amd64)" >&2; exit 2 ;;
  esac
  [ "$got" = "$want" ] || { echo "release-assets: $file is not a $os-$arch executable (header $got, want $want)" >&2; exit 1; }
  name=vk8s-$os-$arch
  cp "$file" "$out/$name"
  chmod 755 "$out/$name"
  line=$(cd "$out" && sha256 "$name")
  { grep -v "  $name\$" "$out/SHA256SUMS" || true; echo "$line"; } > "$out/SHA256SUMS.new"
  mv "$out/SHA256SUMS.new" "$out/SHA256SUMS"
  echo "release $ver ($arch): $line"
  exit 0
fi

arch=$(norm_arch "${2:-${ARCH:-$(uname -m)}}")
case $arch in
  arm64) def=ManifestArm64 sfx="" ;;
  amd64) def=ManifestAmd64 sfx=-amd64 ;;
esac
src=${1:-$HOME/.vk8s/assets/$K8S$sfx}
out=out/release/$arch
rm -rf "$out"; mkdir -p "$out"
files="Image vk8s.cpio base.img data.img"
sets=""
for s in $(awk '!/^#/ && NF { print $1 }' scripts/guest/sets.txt); do
  [ -f "$src/$s.img" ] && sets="$sets $s"
done
for f in $files; do tar -C "$src" -czSf "$out/$f.tgz" "$f"; done
for s in $sets; do tar -C "$src" -czSf "$out/$s.img.tgz" "$s.img"; done
sum=$(cd "$out" && for f in $files; do sha256 "$f.tgz"; done)
setsum=$(cd "$out" && for s in $sets; do sha256 "$s.img.tgz"; done)
ver="$K8S-$(printf '%s\n%s' "$sum" "$setsum" | sha256 | cut -c1-8)"
{
  echo "import Base"
  echo "import ./assets.bend as A"
  echo
  echo "# GENERATED by scripts/release-assets.sh: the $arch guest assets this vk8s"
  echo "# build runs, as published on the GitHub release named by the version."
  echo
  echo "def $def.version() -> String:"
  echo "  \"$ver\""
  echo
  echo "# (archive name, SHA-256 of the archive)"
  echo "def $def.files() -> List<&2, A.AssetFile>:"
  printf '  ['
  first=1
  while read -r h n; do
    [ $first = 1 ] || printf ',\n   '
    printf 'A.AssetFile{"%s", "%s"}' "$n" "$h"; first=0
  done <<<"$sum"
  echo "]"
  echo
  echo "# (set, archive name, SHA-256 of the archive): the role sets"
  echo "# (docs/ref/footprint-decisions.md D1)."
  echo "def $def.sets() -> List<&2, A.SetFile>:"
  printf '  ['
  first=1
  while read -r h n; do
    [ -n "$n" ] || continue
    [ $first = 1 ] || printf ',\n   '
    printf 'A.SetFile{"%s", A.AssetFile{"%s", "%s"}}' "${n%.img.tgz}" "$n" "$h"; first=0
  done <<<"$setsum"
  echo "]"
} > "src/cli/manifest_$arch.bend"
printf '%s\n%s\n' "$sum" "$setsum" | grep . > "$out/SHA256SUMS"
echo "$ver" > "$out/VERSION"
echo "release $ver ($arch) in $out:"; ls -lh "$out"
echo "next: commit src/cli/manifest_$arch.bend, build the $arch binaries from that tree, then"
echo "  scripts/release-assets.sh --binary OS FILE $arch   (docs/RELEASE.md)"
