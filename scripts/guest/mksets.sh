#!/usr/bin/env bash
# Makes one read-only disk per role set (docs/ref/footprint-decisions.md
# D1) from ASSETS_BIN as scripts/guest/sets.txt lists the sets:
# OUT_DIR/<set>.img, squashfs (zstd) by mksqfs.sh, so a rebuild from the
# same inputs is the same bytes. A set none of whose entries ASSETS_BIN
# holds (images, before scripts/guest/images.sh ran) is skipped, and its
# old image removed. Every entry of ASSETS_BIN must be in exactly one set,
# so a new asset cannot go missing from every VM.
#
# usage: mksets.sh ASSETS_BIN OUT_DIR
# Needs python3 and sqfstar (squashfs-tools 4.6+).
set -euo pipefail
[ $# = 2 ] || { sed -n 's/^# usage: //p' "$0"; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
a=$1 out=$2
sets=$here/sets.txt
mkdir -p "$out"
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
for e in $(cd "$a" && ls); do
  n=$(awk -v e="$e" '!/^#/ { for (i = 2; i <= NF; i++) if ($i == e) c++ } END { print c + 0 }' "$sets")
  [ "$n" = 1 ] || { echo "mksets.sh: $a/$e is in $n sets of $sets (want 1)" >&2; exit 1; }
done
awk '!/^#/ && NF' "$sets" > "$w/sets"
while read -r s files <&3; do
  rm -rf "$w/set" "$out/$s.img"; mkdir -p "$w/set"
  any=""
  for f in $files; do
    if [ -e "$a/$f" ]; then cp -R "$a/$f" "$w/set/"; any=1; fi
  done
  if [ -z "$any" ]; then echo "set $s: none of its entries in $a; skipped"; continue; fi
  "$here/mksqfs.sh" "$out/$s.img" "$w/set"
  echo "set $s: $(du -sk "$w/set" | cut -f1) KiB in $(( $(wc -c < "$out/$s.img") / 1024 )) KiB of squashfs"
done 3< "$w/sets"
