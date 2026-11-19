#!/usr/bin/env bash
# macOS: keeps a long test run (bench, certified run, soak) from wearing the
# Mac down. The Mac this runs on has an endpoint security agent that
# records every file event; on 2026-11-19 a run that churned files hung it
# twice (docs/STATUS.md, docs/ref/layers-sqfs.md).
#   scripts/bench/guard.sh check          exit 1 when the Mac is short of room
#   scripts/bench/guard.sh watch PID      every 30 s; after 3 bad checks in a
#                                         row, stop PID (and its children) and
#                                         delete every vk8s cluster
# Short of room: free disk under 15 GiB, system-wide memory free under 20%,
# or a 1-minute load average over 16. The agent's own CPU is not visible
# without root, so load and memory stand for it.
set -uo pipefail
cd "$(dirname "$0")/../.."
v=${VK8S_BIN:-out/vk8s}
min_disk=${GUARD_DISK_GIB:-15} min_free=${GUARD_FREE_PCT:-20} max_load=${GUARD_LOAD:-16}

state() {
  local disk free load
  disk=$(df -g / | awk 'NR==2 {print $4}')
  free=$(memory_pressure 2>/dev/null | awk -F': ' '/free percentage/ {gsub("%","",$2); print $2}')
  load=$(sysctl -n vm.loadavg | awk '{print int($2)}')
  echo "disk=${disk}GiB free=${free:-?}% load=$load"
  [ "${disk:-0}" -ge "$min_disk" ] && [ "${free:-100}" -ge "$min_free" ] && [ "$load" -le "$max_load" ]
}

stop() {
  local pid=$1
  pkill -TERM -P "$pid" 2>/dev/null; kill -TERM "$pid" 2>/dev/null
  sleep 5
  "$v" list --output json 2>/dev/null | python3 -c 'import sys,json
for c in json.load(sys.stdin): print(c.get("Name") or c.get("name"))' 2>/dev/null |
    while read -r c; do [ -n "$c" ] && "$v" delete "$c" >/dev/null 2>&1; done
}

case ${1:-} in
  check)
    s=$(state); ok=$?; echo "guard: $s"; exit $ok ;;
  watch)
    pid=${2:?pid}; bad=0
    while kill -0 "$pid" 2>/dev/null; do
      if s=$(state); then bad=0; else bad=$((bad + 1)); echo "guard: short of room ($s), $bad of 3" >&2; fi
      if [ "$bad" -ge 3 ]; then echo "guard: stopping $pid and deleting the clusters ($s)" >&2; stop "$pid"; exit 1; fi
      sleep 30
    done ;;
  *)
    echo "usage: guard.sh check | watch PID" >&2; exit 2 ;;
esac
