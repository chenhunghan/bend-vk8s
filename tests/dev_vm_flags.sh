#!/usr/bin/env bash
# scripts/dev/linux-vm.sh on fake inputs, no VM: a local image directory
# (Image, dev.cpio, a small rootfs.img and their SHA256SUMS), a fake vk8s
# that records its arguments, and a fake ssh key. It checks the bend-vmm
# flags of `linux-vm.sh up --dir DIR --dry-run` (docs/ref/
# explore-linux-hosts.md, phase 8: --kernel, --initrd, --disk, --share
# <repo>,quota=..., --forward 127.0.0.1:2222:22, --mem 4096, --cpus 4),
# the kernel command line with the ssh key hook, the copied and grown
# disk, and that a hash mismatch stops it before the VMM.
#
# Needs python3. Prints PASS/FAIL lines; exits 1 on any FAIL.
set -uo pipefail
cd "$(dirname "$0")/.."
repo=$PWD
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
check() { # check NAME CONDITION-COMMAND...
  local name=$1; shift
  if "$@"; then pass "$name"; else fail "$name"; fi
}

img=$tmp/img state=$tmp/state
mkdir -p "$img"
printf 'kernel\n' > "$img/Image"
printf 'cpio\n' > "$img/dev.cpio"
python3 -I -c 'import os, sys; f = open(sys.argv[1], "wb"); f.write(b"ext4"); f.truncate(1 << 20)' "$img/rootfs.img"
(cd "$img" && sha256sum Image dev.cpio rootfs.img > SHA256SUMS)
printf 'private\n' > "$tmp/key"
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFAKEFAKEFAKE dev@test\n' > "$tmp/key.pub"
cat > "$tmp/vk8s" <<'SH'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done > "$ARGS_OUT"
SH
chmod 755 "$tmp/vk8s"

run() { # run ARGS...: linux-vm.sh with the fakes
  ARGS_OUT=$tmp/args VK8S=$tmp/vk8s DEV_VM_STATE=$state DEV_VM_KEY=$tmp/key DEV_VM_DISK=64M \
    scripts/dev/linux-vm.sh "$@"
}

out=$(run up --dir "$img" --dry-run 2>&1); rc=$?
echo "$out" | sed 's/^/  | /'
check "up --dry-run succeeds" [ $rc = 0 ]
# the printed command, one word per line, as the fake vk8s would see it
printf '%s\n' "$out" | sed -n 's/^vmm-arg: //p' > "$tmp/words"
pair() { # pair FLAG VALUE: FLAG is followed by VALUE
  grep -qxF -- "$2" <(grep -A1 -xF -- "$1" "$tmp/words" | sed -n 2p)
}
check "the first word is vmm" [ "$(head -n1 "$tmp/words")" = vmm ]
check "--kernel is the image's Image" pair --kernel "$img/Image"
check "--initrd is dev.cpio" pair --initrd "$img/dev.cpio"
check "--disk is the state copy of rootfs.img" pair --disk "$state/disk.img"
check "--share is the repo with a quota" pair --share "$repo,quota=8G"
check "--forward is 127.0.0.1:2222:22" pair --forward 127.0.0.1:2222:22
check "--mem is 4096" pair --mem 4096
check "--cpus is 4" pair --cpus 4
cmd=$(grep -A1 -xF -- --cmdline "$tmp/words" | sed -n 2p)
key64=$(base64 -w0 < "$tmp/key.pub" 2>/dev/null || base64 < "$tmp/key.pub" | tr -d '\n')
case " $cmd " in *" console=ttyAMA0 "*) pass "the console is ttyAMA0";; *) fail "the console is ttyAMA0: $cmd";; esac
case " $cmd " in *" devvm.ssh_key=$key64 "*) pass "the ssh key hook gets the public key";; *) fail "the ssh key hook gets the public key: $cmd";; esac
check "cmdline prints the same command line" [ "$(scripts/dev/linux-vm.sh cmdline "$tmp/key.pub")" = "$cmd" ]
check "the disk is copied from rootfs.img" [ "$(head -c4 "$state/disk.img" 2>/dev/null)" = ext4 ]
check "the disk grows to DEV_VM_DISK" [ "$(wc -c < "$state/disk.img" 2>/dev/null | tr -d ' ')" = $((64 << 20)) ]
check "the image stays as it was" [ "$(wc -c < "$img/rootfs.img" | tr -d ' ')" = $((1 << 20)) ]
check "the ssh command is printed" grep -q "ssh .*-p 2222 .*dev@127.0.0.1" <<<"$out"
check "the dry run does not start the VMM" [ ! -e "$tmp/args" ]

# a real start, with the fake VMM (exits at once): the same words
rm -f "$tmp/args"
DEV_VM_WAIT=0 run up --dir "$img" >/dev/null 2>&1
sleep 1
check "up runs vk8s with the printed words" cmp -s "$tmp/args" "$tmp/words"

# a changed file stops it before the VMM
printf 'other\n' > "$img/dev.cpio"; rm -f "$tmp/args"
run up --dir "$img" --dry-run >/dev/null 2>&1; rc=$?
check "a SHA-256 mismatch fails" [ $rc != 0 ]
check "a SHA-256 mismatch does not start the VMM" [ ! -e "$tmp/args" ]

if [ $fails = 0 ]; then echo "all PASS"; else echo "$fails FAIL"; exit 1; fi
