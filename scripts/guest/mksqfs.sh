#!/usr/bin/env bash
# Makes the read-only assets disk: squashfs, zstd (level 19), 256 KiB
# blocks, from the tree of scripts/guest/disktar.py (BIN_DIR at the root,
# GUEST_TAR under guest/), owners root, times 0, and -reproducible (sqfstar
# writes blocks from several threads; without it two packs differ), so a rebuild from the
# same inputs is the same bytes (the release pins its SHA-256). The guest
# kernel (Alpine's linux-virt 6.18 and our 16 KiB build) has
# CONFIG_SQUASHFS=m with CONFIG_SQUASHFS_ZSTD (docs/ref/footprint-decisions.md A1).
#
# usage: mksqfs.sh OUT_IMG BIN_DIR [GUEST_TAR]
# Needs python3 and sqfstar (squashfs-tools 4.6+: brew install squashfs;
# apt-get install squashfs-tools); $SQFSTAR overrides it.
set -euo pipefail
[ $# = 2 ] || [ $# = 3 ] || { sed -n 's/^# usage: //p' "$0"; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
img=$1 bin=$2 g=${3:-}
SQFSTAR=${SQFSTAR:-$(command -v sqfstar || echo /opt/homebrew/bin/sqfstar)}
[ -x "$SQFSTAR" ] || { echo "mksqfs.sh: need sqfstar (squashfs-tools 4.6+: brew install squashfs, or apt-get install squashfs-tools)" >&2; exit 1; }
rm -f "$img"
python3 "$here/disktar.py" - "$bin" ${g:+"$g"} |
  "$SQFSTAR" -reproducible -comp zstd -Xcompression-level 19 -b 262144 -mkfs-time 0 -root-time 0 -root-mode 0755 -root-uid 0 -root-gid 0 -all-root -no-xattrs "$img" >/dev/null
