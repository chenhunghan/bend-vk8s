#!/usr/bin/env bash
# The Linux dev VM on the Mac (docs/ref/dev-vm.md): boots the image of
# scripts/dev/rootfs.sh (Image, dev.cpio, rootfs.img; CI job dev-vm) under
# vk8s's embedded bend-vmm, with this repository shared at /repo and the
# guest's sshd on 127.0.0.1:2222, then prints the ssh command. Use it to
# run vk8s-linux-arm64 (container, native, gVisor) on a Mac, which has no
# nested KVM (docs/GOAL.md section 8).
#
# usage: linux-vm.sh [up] [--dir DIR | --run ID] [--dry-run]
#        linux-vm.sh stop | status | ssh [CMD...] | cmdline KEY.pub
#   up        fetch the image (the dev-vm artifact of CI run ID, PIN_RUN
#             below, or the newest green run on main; needs gh) or take it
#             from DIR, check its SHA-256s, copy rootfs.img to the state
#             directory once (the VM's disk, grown to DEV_VM_DISK), start
#             `vk8s vmm` in the background and wait for ssh. --dry-run
#             prepares the same and prints the vmm words (vmm-arg: lines)
#             without starting it.
#   stop      press the power button (systemd powers off), then quit
#   status    running or stopped
#   ssh       ssh into the VM as dev
#   cmdline   the kernel command line for a public key (tests use it)
# Environment: VK8S (default: vk8s on PATH, else out/vk8s), DEV_VM_STATE
# (~/.vk8s/dev-vm), DEV_VM_KEY (an ssh private key with KEY.pub; default
# a key made in the state directory), DEV_VM_PORT (2222), DEV_VM_MEM
# (4096), DEV_VM_CPUS (4), DEV_VM_DISK (32G), DEV_VM_SHARE_QUOTA (8G),
# DEV_VM_WAIT (seconds to wait for ssh, 300).
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
GH_REPO=chenhunghan/bend-vk8s

# Pins (docs/ref/dev-vm.md, "Pinning"): the CI run whose dev-vm artifact
# `up` fetches by default, and that artifact's SHA256SUMS as the job
# printed it ("The image" step). Empty: the newest green run on main,
# checked against its own SHA256SUMS only.
PIN_RUN=
PIN_SUMS=''

state=${DEV_VM_STATE:-$HOME/.vk8s/dev-vm}
port=${DEV_VM_PORT:-2222}
mem=${DEV_VM_MEM:-4096}
cpus=${DEV_VM_CPUS:-4}
disk_size=${DEV_VM_DISK:-32G}
quota=${DEV_VM_SHARE_QUOTA:-8G}
wait_s=${DEV_VM_WAIT:-300}
key=${DEV_VM_KEY:-$state/id_ed25519}

die() { echo "linux-vm.sh: $*" >&2; exit 1; }
b64() { base64 < "$1" | tr -d '\n'; }
# The kernel command line: the PL011 console, eth0 by that name (the
# root's networkd file), no first-boot prompts, and the public key for the
# root's authorized_keys hook (devvm-ssh-key.service).
cmdline_of() { echo "console=ttyAMA0 net.ifnames=0 systemd.firstboot=0 devvm.ssh_key=$(b64 "$1")"; }
sha() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
bytes() { # 32G, 512M, 4096K or bytes -> bytes
  local n=${1%[KkMmGgTt]}
  case "$1" in *[Kk]) echo $((n << 10)) ;; *[Mm]) echo $((n << 20)) ;; *[Gg]) echo $((n << 30)) ;; *[Tt]) echo $((n << 40)) ;; *) echo "$n" ;; esac
}
size_of() { wc -c < "$1" | tr -d ' '; }
ssh_args() { echo "-i $key -p $port -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$state/known_hosts dev@127.0.0.1"; }
running() { [ -f "$state/vmm.pid" ] && kill -0 "$(cat "$state/vmm.pid")" 2>/dev/null; }

# check DIR SUMS-FILE: Image, dev.cpio and rootfs.img match
check() {
  local f want got
  for f in Image dev.cpio rootfs.img; do
    [ -f "$1/$f" ] || die "$1/$f is missing"
    want=$(awk -v n="$f" '$2 == n || $2 == "*" n { print $1 }' "$2")
    [ -n "$want" ] || die "$2 has no line for $f"
    got=$(sha "$1/$f")
    [ "$got" = "$want" ] || die "SHA-256 mismatch for $1/$f: $got, want $want"
  done
}

# fetch RUN: the dev-vm artifact of CI run RUN in $state/image-RUN
fetch() {
  local run=$1 d
  command -v gh >/dev/null || die "fetching the image needs gh (or pass --dir DIR)"
  if [ -z "$run" ]; then
    run=$(gh run list -R "$GH_REPO" -w check -b main -s success -L 1 --json databaseId -q '.[0].databaseId')
    [ -n "$run" ] || die "no green CI run on main; pass --run ID or --dir DIR"
  fi
  d=$state/image-$run
  if [ ! -f "$d/SHA256SUMS" ]; then
    echo "Fetching the dev-vm artifact of run $run..." >&2
    rm -rf "$d.part"
    gh run download "$run" -R "$GH_REPO" -n dev-vm -D "$d.part" >&2
    mv "$d.part" "$d"
  fi
  echo "$run"
}

up() {
  local dir= run=${DEV_VM_RUN:-$PIN_RUN} dry=0 sums
  while [ $# -gt 0 ]; do
    case "$1" in
      --dir) dir=$2; shift 2 ;;
      --run) run=$2; shift 2 ;;
      --dry-run) dry=1; shift ;;
      *) die "unknown option $1" ;;
    esac
  done
  mkdir -p "$state"
  if [ $dry = 0 ] && running; then
    echo "The dev VM runs (pid $(cat "$state/vmm.pid")). ssh $(ssh_args)"
    return 0
  fi
  if [ -n "$dir" ]; then
    dir=$(cd "$dir" && pwd)
    if [ -f "$dir/SHA256SUMS" ]; then check "$dir" "$dir/SHA256SUMS"
    else echo "linux-vm.sh: $dir has no SHA256SUMS; not checked" >&2; fi
  else
    run=$(fetch "$run")
    dir=$state/image-$run
    if [ -n "$PIN_SUMS" ] && [ "$run" = "$PIN_RUN" ]; then
      sums=$state/pinned.sums
      printf '%s\n' "$PIN_SUMS" > "$sums"
    else
      sums=$dir/SHA256SUMS
      echo "linux-vm.sh: run $run is not pinned; checked against its own SHA256SUMS. To pin it, set in $0:" >&2
      echo "  PIN_RUN=$run" >&2
      echo "  PIN_SUMS='$(cat "$sums")'" >&2
    fi
    check "$dir" "$sums"
  fi
  # the ssh key
  if [ ! -f "$key" ]; then
    [ -z "${DEV_VM_KEY:-}" ] || die "DEV_VM_KEY=$key does not exist"
    ssh-keygen -q -t ed25519 -N '' -C vk8s-dev -f "$key"
  fi
  [ -f "$key.pub" ] || die "$key.pub is missing"
  # the disk: a copy of rootfs.img (a clone on APFS), kept across boots;
  # systemd grows the filesystem to it (x-systemd.growfs)
  local disk=$state/disk.img want
  if [ ! -f "$disk" ]; then
    cp -c "$dir/rootfs.img" "$disk.part" 2>/dev/null || cp "$dir/rootfs.img" "$disk.part"
    mv "$disk.part" "$disk"
    rm -f "$state/known_hosts"   # a new root makes new host keys
  else
    echo "Reusing $disk (delete it for a fresh root)." >&2
  fi
  want=$(bytes "$disk_size")
  if [ "$(size_of "$disk")" -lt "$want" ]; then
    if command -v truncate >/dev/null; then truncate -s "$want" "$disk"
    else dd if=/dev/null of="$disk" bs=1 seek="$want" 2>/dev/null; fi
  fi
  local vk8s=${VK8S:-$(command -v vk8s || echo "$repo/out/vk8s")}
  local words=(vmm
    --kernel "$dir/Image"
    --initrd "$dir/dev.cpio"
    --disk "$disk"
    --share "$repo,quota=$quota"
    --forward "127.0.0.1:$port:22"
    --mem "$mem"
    --cpus "$cpus"
    --console-log "$state/console.log,max=16M,keep=2"
    --control "$state/ctl.sock"
    --cmdline "$(cmdline_of "$key.pub")")
  if [ $dry = 1 ]; then
    printf 'vmm-arg: %s\n' "${words[@]}"
    echo "ssh $(ssh_args)"
    return 0
  fi
  [ -x "$vk8s" ] || die "no vk8s at $vk8s (set VK8S, or build it with scripts/build-mac.sh)"
  rm -f "$state/ctl.sock"
  (cd "$state" && { nohup "$vk8s" "${words[@]}" </dev/null >vmm.log 2>&1 & echo $! > vmm.pid; })
  echo "Started the dev VM (pid $(cat "$state/vmm.pid"); console: $state/console.log)."
  local t=0
  while [ "$t" -lt "$wait_s" ]; do
    running || { tail -n 20 "$state/vmm.log" "$state/console.log" 2>/dev/null >&2; die "the VMM exited"; }
    # shellcheck disable=SC2046
    ssh $(ssh_args) -o BatchMode=yes -o ConnectTimeout=5 -o LogLevel=ERROR true 2>/dev/null && break
    sleep 2; t=$((t + 2))
  done
  echo "ssh $(ssh_args)"
}

stop() {
  running || { echo stopped; return 0; }
  local pid i=0
  pid=$(cat "$state/vmm.pid")
  printf 'powerdown\n' | nc -U -w 2 "$state/ctl.sock" >/dev/null 2>&1 || true
  while kill -0 "$pid" 2>/dev/null && [ $i -lt 120 ]; do sleep 0.5; i=$((i + 1)); done
  kill -0 "$pid" 2>/dev/null && { printf 'quit\n' | nc -U -w 2 "$state/ctl.sock" >/dev/null 2>&1 || true; }
  i=0
  while kill -0 "$pid" 2>/dev/null && [ $i -lt 10 ]; do sleep 0.5; i=$((i + 1)); done
  kill -9 "$pid" 2>/dev/null || true
  echo stopped
}

cmd=${1:-up}
case "$cmd" in
  -*) up "$@" ;;
  up) shift; up "$@" ;;
  stop) stop ;;
  status) if running; then echo "running (pid $(cat "$state/vmm.pid"))"; else echo stopped; fi ;;
  # shellcheck disable=SC2046
  ssh) shift; exec ssh $(ssh_args) "$@" ;;
  cmdline) [ $# = 2 ] || die "usage: linux-vm.sh cmdline KEY.pub"; cmdline_of "$2" ;;
  *) sed -n 's/^# usage: //p; s/^#        /  /p' "$0"; exit 2 ;;
esac
