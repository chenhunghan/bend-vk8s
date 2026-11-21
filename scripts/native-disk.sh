#!/usr/bin/env bash
# Disk used by native clusters (docs/GOAL.md section 11, "Shared assets
# and layers off the VM", measured as in section 10): du of each
# cluster's data dir and of the shared binaries its bin/ links to, now
# (one copy per asset version, NHost.prepare_cmds.v2) and before (an
# unsquashfs of the same sets in each data dir, NHost.prepare_cmds; the
# per-cluster copy is measured by unpacking the sets once more into a
# scratch dir with the commands v1 ran).
#
# usage: scripts/native-disk.sh NAME...   (needs sudo, du, unsquashfs)
# VK8S_ASSETS: the assets dir the clusters were made from. Prints a table
# (also to $GITHUB_STEP_SUMMARY) and the line
#   native-disk: clusters=N data_kib=D shared_kib=S copy_kib=C before_kib=B after_kib=A
set -uo pipefail
[ $# -ge 1 ] || { echo "usage: $0 NAME..." >&2; exit 2; }
[ -n "${VK8S_ASSETS:-}" ] || { echo "native-disk: set VK8S_ASSETS" >&2; exit 2; }
kib() { sudo du -sk "$1" 2>/dev/null | cut -f1; }
rows=""
data_kib=0
targets=""
for n in "$@"; do
  d=/var/lib/vk8s/$n
  k=$(kib "$d"); k=${k:-0}
  t=$(sudo readlink "$d/bin" || true)
  rows="$rows| $n | $k | ${t:-(own bin dir)} |"$'\n'
  data_kib=$((data_kib + k))
  [ -n "$t" ] && targets="$targets${t%/bin}"$'\n'
done
shared_kib=0
shared=$(printf '%s' "$targets" | sort -u | grep . || true)
for s in $shared; do
  k=$(kib "$s"); shared_kib=$((shared_kib + ${k:-0}))
done
# The per-cluster copy v1 made: the same sets, unpacked as v1 did.
scratch=$(sudo mktemp -d /var/tmp/vk8s-disk.XXXXXX)
# (images only when the clusters' copy holds the images set's entry)
sets="node control-plane"
first=$(printf '%s\n' "$shared" | head -n 1)
[ -n "$first" ] && sudo test -e "$first/bin/images" && sets="$sets images"
for set in $sets; do
  sudo unsquashfs -f -n -d "$scratch/bin" "$VK8S_ASSETS/$set.img" >/dev/null
done
copy_kib=$(kib "$scratch/bin"); copy_kib=${copy_kib:-0}
sudo rm -rf --one-file-system "$scratch"
before=$((data_kib + $# * copy_kib))
after=$((data_kib + shared_kib))
mib() { awk -v k="$1" 'BEGIN { printf "%.1f", k / 1024 }'; }
head="### Disk of $# native clusters (du -sk)"
table="| cluster | data dir KiB (without bin/) | bin/ links to |"$'\n'"|---|---|---|"$'\n'"$rows"
table="$table"$'\n'"| | MiB |"$'\n'"|---|---|"$'\n'
table="$table| data dirs | $(mib "$data_kib") |"$'\n'
table="$table| shared copies ($(printf '%s\n' "$shared" | grep -c .)) | $(mib "$shared_kib") |"$'\n'
table="$table| one unsquashfs of the sets (v1, per cluster) | $(mib "$copy_kib") |"$'\n'
table="$table| before: data dirs + $# unsquashfs | $(mib "$before") |"$'\n'
table="$table| after: data dirs + shared | $(mib "$after") |"$'\n'
echo "$head"; printf '%s' "$table"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then printf '%s\n\n%s\n' "$head" "$table" >> "$GITHUB_STEP_SUMMARY"; fi
echo "native-disk: clusters=$# data_kib=$data_kib shared_kib=$shared_kib copy_kib=$copy_kib before_kib=$before after_kib=$after"
