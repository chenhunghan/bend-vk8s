#!/usr/bin/env bash
# Builds the vk8s host binary (host/vk8s.bend) for macOS and signs it with
# the Hypervisor.framework entitlement (it embeds bend-vmm).
#   scripts/build-mac.sh [out/vk8s]
# Command Line Tools clang 17 cannot link against the macOS 27 SDK, so when
# the default SDK fails this retries with the newest installed SDK that links.
set -euo pipefail
cd "$(dirname "$0")/.."
src=host/vk8s.bend
out=${1:-out/vk8s}
mkdir -p "$(dirname "$out")"
# build beside the target, then rename: running vk8s processes (VMMs)
# keep the file they mapped
tmp="$out.new"
build() { bend "$src" -o "$tmp" > "$out.log" 2>&1; }
if ! build; then
  ok=0
  for sdk in $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX2[0-9].*.sdk /Library/Developer/CommandLineTools/SDKs/MacOSX1[5-9]*.sdk 2>/dev/null | sort -rV); do
    if SDKROOT=$sdk build; then ok=1; break; fi
  done
  if [ $ok = 0 ]; then cat "$out.log" >&2; exit 1; fi
fi
codesign -s - --entitlements host/hv.entitlements -f "$tmp" 2>/dev/null
mv -f "$tmp" "$out"
rm -f "$out.log"
echo "$out"
