#!/usr/bin/env bash
# The guest image split (scripts/guest/pack.sh) on fake inputs: a fake
# linux-virt module tree, a Debian root tar with names that differ only in
# case, and fake vk8s binaries. It checks that the initramfs keeps only
# what stage 0 needs to mount the assets disk (busybox, the virtio and
# squashfs modules, small files, symlinks into /assets), and that the assets
# disk (squashfs, zstd) holds the rest under guest/, with modes, owners,
# symlinks and both case variants, built the same byte for byte twice.
#
# Needs python3 and squashfs-tools 4.6+ (sqfstar, unsquashfs). Prints
# PASS/FAIL lines; exits 1 on any FAIL.
set -uo pipefail
cd "$(dirname "$0")/.."
here=$PWD

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
check() { # check NAME CONDITION-COMMAND...
  local name=$1; shift
  if "$@"; then pass "$name"; else fail "$name"; fi
}
UNSQUASHFS=${UNSQUASHFS:-$(command -v unsquashfs || echo /usr/bin/unsquashfs)}

# --- fake inputs
k=$tmp/kernel; kd=$k/lib/modules/6.18.0-virt
mkdir -p "$kd/kernel" "$tmp/bin"
python3 -I - "$kd" $(cat scripts/guest/modules.early.txt scripts/guest/modules.txt) <<'PY'
import gzip, os, sys
kd, names = sys.argv[1], sys.argv[2:]
deps = {"ext4": ["jbd2", "mbcache", "crc16"], "jbd2": [], "mbcache": [], "crc16": [],
        "bridge": ["stp", "llc"], "stp": ["llc"], "llc": [], "br_netfilter": ["bridge"],
        "9p": ["9pnet", "netfs"], "9pnet_virtio": ["9pnet"], "9pnet": [], "netfs": []}
for n in names: deps.setdefault(n, [])
p = lambda n: "kernel/" + n + ".ko.gz"
with open(os.path.join(kd, "modules.dep"), "w") as f:
    for n, ds in deps.items():
        f.write(p(n) + ": " + " ".join(p(d) for d in ds) + "\n")
        with gzip.open(os.path.join(kd, p(n)), "wb") as g: g.write(("module " + n + "\n").encode())
open(os.path.join(kd, "modules.builtin"), "w").write("kernel/lib/crc32c.ko\n")
PY
head -c 3000000 /dev/urandom > "$tmp/init"; chmod 755 "$tmp/init"
head -c 3000000 /dev/urandom > "$tmp/vk8s-guest"; chmod 755 "$tmp/vk8s-guest"
printf 'busybox\n' > "$tmp/busybox"; chmod 755 "$tmp/busybox"
printf 'roots\n' > "$tmp/cacert.pem"
printf 'kubelet\n' > "$tmp/bin/kubelet"; chmod 755 "$tmp/bin/kubelet"
python3 -I - "$tmp/debroot.tar" <<'PY'
import io, sys, tarfile
t = tarfile.open(sys.argv[1], "w")
def f(name, data, mode=0o644):
    m = tarfile.TarInfo(name); m.size = len(data); m.mode = mode; t.addfile(m, io.BytesIO(data))
def l(name, target):
    m = tarfile.TarInfo(name); m.type = tarfile.SYMTYPE; m.linkname = target; t.addfile(m)
f("usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1", b"ld.so", 0o755)
f("usr/lib/aarch64-linux-gnu/libssl.so.3", b"libssl")
f("usr/lib/aarch64-linux-gnu/xtables/libxt_MARK.so", b"MARK target")
f("usr/lib/aarch64-linux-gnu/xtables/libxt_mark.so", b"mark match")
l("usr/lib/ld-linux-aarch64.so.1", "aarch64-linux-gnu/ld-linux-aarch64.so.1")
f("usr/sbin/xtables-nft-multi", b"xtables", 0o755)
f("usr/sbin/conntrack", b"conntrack", 0o755)
f("usr/share/iptables/iptables.xslt", b"xslt")
f("etc/ld.so.conf.d/aarch64-linux-gnu.conf", b"/usr/lib/aarch64-linux-gnu\n")
t.close()
PY

# --- pack
out=$tmp/out; mkdir -p "$out"
if scripts/guest/pack.sh "$k" "$tmp/debroot.tar" "$tmp/init" "$tmp/vk8s-guest" "$tmp/busybox" "$tmp/cacert.pem" \
    "$tmp/bin" "$out/vk8s.cpio" "$out/assets.img" >"$tmp/pack.log" 2>&1; then
  pass "pack.sh runs"
else
  fail "pack.sh runs"; cat "$tmp/pack.log"; echo "1 or more FAIL"; exit 1
fi

# The cpio as "TYPE PATH SIZE [TARGET]" lines (newc).
python3 -I - "$out/vk8s.cpio" > "$tmp/cpio.txt" <<'PY'
import sys
b = open(sys.argv[1], "rb").read(); i = 0
while True:
    h = b[i:i + 110]; assert h[:6] == b"070701", "not newc"
    f = [int(h[6 + 8 * k:14 + 8 * k], 16) for k in range(13)]
    mode, size, nlen = f[1], f[6], f[11]
    name = b[i + 110:i + 109 + nlen].decode()
    j = i + 110 + nlen; j += -j % 4
    if name == "TRAILER!!!": break
    kind = {0o040000: "d", 0o100000: "f", 0o120000: "l", 0o020000: "c"}[mode & 0o170000]
    extra = b[j:j + size].decode() if kind == "l" else ""
    print(kind, name, size, "%o" % (mode & 0o7777), extra)
    i = j + size; i += -i % 4
PY
has() { grep -q "^$1 $2 " "$tmp/cpio.txt"; }
link_to() { grep -q "^l $1 [0-9]* [0-7]* $2\$" "$tmp/cpio.txt"; }

check "cpio: stage 0 is /init, executable" grep -q '^f init [0-9]* 755 ' "$tmp/cpio.txt"
check "cpio: busybox" has f bin/busybox
check "cpio: flannel manifest" has f etc/vk8s/flannel.yaml
check "cpio: no file over 1 MiB (vk8s-init and vk8s-guest stay out)" \
  awk '$1 == "f" && $3 > 1048576 { exit 1 }' "$tmp/cpio.txt"
check "cpio: PID 1 is a link into the assets disk" link_to sbin/vk8s-init /assets/guest/sbin/vk8s-init
check "cpio: vk8s-guest is a link into the assets disk" link_to usr/bin/vk8s-guest /assets/guest/usr/bin/vk8s-guest
check "cpio: /lib is usr/lib" link_to lib usr/lib
check "cpio: /usr/lib is the disk's (ld.so, libssl, late modules)" link_to usr/lib /assets/guest/usr/lib
check "cpio: /usr/share is the disk's" link_to usr/share /assets/guest/usr/share
check "cpio: iptables is the disk's" link_to usr/sbin/iptables /assets/guest/usr/sbin/iptables
check "cpio: conntrack is the disk's" link_to usr/sbin/conntrack /assets/guest/usr/sbin/conntrack
check "cpio: /etc/ssl is the disk's (CA roots)" link_to etc/ssl /assets/guest/etc/ssl
check "cpio: /etc/vk8s stays a directory" has d etc/vk8s
check "cpio: squashfs in the boot modules" has f boot/modules/squashfs.ko
check "cpio: virtio_blk in the boot modules" has f boot/modules/virtio_blk.ko
check "cpio: no ext4 in the boot modules (the data disk is PID 1's)" bash -c "! grep -q '^f boot/modules/ext4.ko ' '$tmp/cpio.txt'"
check "cpio: no late module in the boot modules" bash -c "! grep -q '^f boot/modules/bridge.ko ' '$tmp/cpio.txt'"

# Stage 0's list: dependencies first, paths in the cpio.
early=$(python3 -I - "$out/vk8s.cpio" etc/vk8s/modules.early <<'PY'
import sys
b = open(sys.argv[1], "rb").read(); i = 0
while True:
    h = b[i:i + 110]; f = [int(h[6 + 8 * k:14 + 8 * k], 16) for k in range(13)]
    size, nlen = f[6], f[11]; name = b[i + 110:i + 109 + nlen].decode()
    j = i + 110 + nlen; j += -j % 4
    if name == sys.argv[2]: sys.stdout.write(b[j:j + size].decode()); break
    if name == "TRAILER!!!": break
    i = j + size; i += -i % 4
PY
)
late=$(python3 -I - "$out/vk8s.cpio" etc/vk8s/modules <<'PY'
import sys
b = open(sys.argv[1], "rb").read(); i = 0
while True:
    h = b[i:i + 110]; f = [int(h[6 + 8 * k:14 + 8 * k], 16) for k in range(13)]
    size, nlen = f[6], f[11]; name = b[i + 110:i + 109 + nlen].decode()
    j = i + 110 + nlen; j += -j % 4
    if name == sys.argv[2]: sys.stdout.write(b[j:j + size].decode()); break
    if name == "TRAILER!!!": break
    i = j + size; i += -i % 4
PY
)
check "early list: virtio_mmio, virtio_blk, squashfs" \
  test "$(printf '%s\n' "$early" | sort | tr '\n' ' ')" = "/boot/modules/squashfs.ko /boot/modules/virtio_blk.ko /boot/modules/virtio_mmio.ko "
check "late list: ext4 after jbd2 (PID 1 mounts the data disk)" \
  test "$(printf '%s\n' "$late" | grep -n '/jbd2.ko\|/ext4.ko' | cut -d: -f2 | tr '\n' ' ')" = "/lib/modules/jbd2.ko /lib/modules/ext4.ko "
check "late list: on /lib/modules" bash -c "printf '%s\n' '$late' | grep -qx /lib/modules/br_netfilter.ko"
check "late list: bridge before br_netfilter" \
  test "$(printf '%s\n' "$late" | grep -n '/bridge.ko\|br_netfilter' | cut -d: -f2 | tr '\n' ' ')" = "/lib/modules/bridge.ko /lib/modules/br_netfilter.ko "
check "late list: nothing stage 0 loaded" bash -c "! printf '%s\n' '$late' | grep -q 'squashfs\|virtio_blk\|virtio_mmio'"
check "late list: 9p and virtio_net load late" bash -c "printf '%s\n' '$late' | grep -qx /lib/modules/9p.ko && printf '%s\n' '$late' | grep -qx /lib/modules/virtio_net.ko"

# The assets disk: squashfs, zstd, extracted on this (case-sensitive) host.
x=$tmp/x
"$UNSQUASHFS" -n -d "$x" "$out/assets.img" >"$tmp/unsquashfs.log" 2>&1 || { cat "$tmp/unsquashfs.log"; }
same() { cmp -s "$x$1" "$2"; } # same IMAGE-PATH HOST-FILE
mode_of() { stat -c %a "$x$1"; }
# unsquashfs -lln: "MODE UID/GID SIZE DATE TIME squashfs-root/PATH[ -> TARGET]"
owner_of() { "$UNSQUASHFS" -lln "$out/assets.img" 2>/dev/null | awk -v p="squashfs-root$1" '$6 == p { print $2 }'; }
check "disk: squashfs" bash -c "'$UNSQUASHFS' -s '$out/assets.img' 2>/dev/null | grep -q 'SQUASHFS 4:0'"
check "disk: zstd" bash -c "'$UNSQUASHFS' -s '$out/assets.img' 2>/dev/null | grep -q '^Compression zstd'"
check "disk: 256 KiB blocks" bash -c "'$UNSQUASHFS' -s '$out/assets.img' 2>/dev/null | grep -q '^Block size 262144'"
check "disk: the Kubernetes binaries stay at its root" same /kubelet "$tmp/bin/kubelet"
check "disk: kubelet is 0755" test "$(mode_of /kubelet)" = 755
check "disk: guest/sbin/vk8s-init" same /guest/sbin/vk8s-init "$tmp/init"
check "disk: vk8s-init is 0755" test "$(mode_of /guest/sbin/vk8s-init)" = 755
check "disk: vk8s-init is root's" test "$(owner_of /guest/sbin/vk8s-init)" = 0/0
check "disk: kubelet is root's" test "$(owner_of /kubelet)" = 0/0
check "disk: guest/usr/bin/vk8s-guest" same /guest/usr/bin/vk8s-guest "$tmp/vk8s-guest"
check "disk: libssl is 0644" test "$(mode_of /guest/usr/lib/aarch64-linux-gnu/libssl.so.3)" = 644
printf 'MARK target' > "$tmp/MARK"; printf 'mark match' > "$tmp/mark"
check "disk: libxt_MARK.so" same /guest/usr/lib/aarch64-linux-gnu/xtables/libxt_MARK.so "$tmp/MARK"
check "disk: libxt_mark.so (differs only in case)" same /guest/usr/lib/aarch64-linux-gnu/xtables/libxt_mark.so "$tmp/mark"
check "disk: ld.so link" test "$(readlink "$x/guest/usr/lib/ld-linux-aarch64.so.1")" = aarch64-linux-gnu/ld-linux-aarch64.so.1
check "disk: iptables -> xtables-nft-multi" test "$(readlink "$x/guest/usr/sbin/iptables")" = xtables-nft-multi
check "disk: CA roots" same /guest/etc/ssl/certs/ca-certificates.crt "$tmp/cacert.pem"
printf 'module bridge\n' > "$tmp/bridge.ko"
check "disk: late modules, decompressed" same /guest/usr/lib/modules/bridge.ko "$tmp/bridge.ko"
check "disk: no ext4 superblock left (not an ext4 image)" bash -c "! od -An -tx1 -j1080 -N2 '$out/assets.img' | grep -q '53 ef'"
# The release pins the archive's SHA-256: a second pack makes the same disk.
out2=$tmp/out2; mkdir -p "$out2"
scripts/guest/pack.sh "$k" "$tmp/debroot.tar" "$tmp/init" "$tmp/vk8s-guest" "$tmp/busybox" "$tmp/cacert.pem" \
  "$tmp/bin" "$out2/vk8s.cpio" "$out2/assets.img" >"$tmp/pack2.log" 2>&1
check "disk: reproducible (a second pack is the same bytes)" cmp -s "$out/assets.img" "$out2/assets.img"

# amd64 (ARCH=amd64): the x86 module list on top, an optional module the
# kernel lacks is skipped, and /lib64 (the x86-64 glibc loader's
# directory) reaches the disk's usr/lib64.
k64=$tmp/kernel64; kd64=$k64/lib/modules/6.18.0-virt
mkdir -p "$kd64/kernel"
python3 -I - "$kd64" $(cat scripts/guest/modules.early.txt scripts/guest/modules.txt scripts/guest/modules.amd64.txt | tr -d '?' | tr ' ' '\n' | grep -vx fscache) <<'PY'
import gzip, os, sys
kd, names = sys.argv[1], [n.replace("-", "_") for n in sys.argv[2:] if n]
deps = {"virtio_net": ["net_failover"], "net_failover": ["failover"], "failover": [],
        "9p": ["9pnet", "netfs"], "9pnet_virtio": ["9pnet"], "9pnet": [], "netfs": [],
        "vmw_vsock_virtio_transport": ["vmw_vsock_virtio_transport_common", "vsock"],
        "vmw_vsock_virtio_transport_common": ["vsock"], "vsock": [], "virtio_rng": ["rng_core"], "rng_core": []}
for n in names: deps.setdefault(n, [])
p = lambda n: "kernel/" + n + ".ko.gz"
with open(os.path.join(kd, "modules.dep"), "w") as f:
    for n, ds in deps.items():
        f.write(p(n) + ": " + " ".join(p(d) for d in ds) + "\n")
        with gzip.open(os.path.join(kd, p(n)), "wb") as g: g.write(("module " + n + "\n").encode())
open(os.path.join(kd, "modules.builtin"), "w").write("kernel/drivers/virtio/virtio_mmio.ko\n")
PY
python3 -I - "$tmp/debroot64.tar" <<'PY'
import io, sys, tarfile
t = tarfile.open(sys.argv[1], "w")
def f(name, data, mode=0o644):
    m = tarfile.TarInfo(name); m.size = len(data); m.mode = mode; t.addfile(m, io.BytesIO(data))
def l(name, target):
    m = tarfile.TarInfo(name); m.type = tarfile.SYMTYPE; m.linkname = target; t.addfile(m)
f("usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2", b"ld.so", 0o755)
f("usr/lib/x86_64-linux-gnu/libssl.so.3", b"libssl")
l("usr/lib64/ld-linux-x86-64.so.2", "../lib/x86_64-linux-gnu/ld-linux-x86-64.so.2")
f("usr/sbin/xtables-nft-multi", b"xtables", 0o755)
t.close()
PY
out64=$tmp/out64; mkdir -p "$out64"
if ARCH=amd64 scripts/guest/pack.sh "$k64" "$tmp/debroot64.tar" "$tmp/init" "$tmp/vk8s-guest" "$tmp/busybox" "$tmp/cacert.pem" \
    "$tmp/bin" "$out64/vk8s.cpio" "$out64/assets.img" >"$tmp/pack64.log" 2>&1; then
  pass "amd64: pack.sh runs (fscache, optional, is not in this kernel)"
else
  fail "amd64: pack.sh runs (fscache, optional, is not in this kernel)"; cat "$tmp/pack64.log"
fi
cpio_file() { # cpio_file CPIO PATH: the file's text
python3 -I - "$1" "$2" <<'PY'
import sys
b = open(sys.argv[1], "rb").read(); i = 0
while True:
    h = b[i:i + 110]; f = [int(h[6 + 8 * k:14 + 8 * k], 16) for k in range(13)]
    size, nlen = f[6], f[11]; name = b[i + 110:i + 109 + nlen].decode()
    j = i + 110 + nlen; j += -j % 4
    if name == sys.argv[2]: sys.stdout.write(b[j:j + size].decode()); break
    if name == "TRAILER!!!": break
    i = j + size; i += -i % 4
PY
}
cpio_links() { # cpio_links CPIO: "PATH TARGET" per symlink
python3 -I - "$1" <<'PY'
import sys
b = open(sys.argv[1], "rb").read(); i = 0
while True:
    h = b[i:i + 110]; f = [int(h[6 + 8 * k:14 + 8 * k], 16) for k in range(13)]
    mode, size, nlen = f[1], f[6], f[11]; name = b[i + 110:i + 109 + nlen].decode()
    j = i + 110 + nlen; j += -j % 4
    if name == "TRAILER!!!": break
    if mode & 0o170000 == 0o120000: print(name, b[j:j + size].decode())
    i = j + size; i += -i % 4
PY
}
late64=$(cpio_file "$out64/vk8s.cpio" etc/vk8s/modules)
early64=$(cpio_file "$out64/vk8s.cpio" etc/vk8s/modules.early)
links64=$(cpio_links "$out64/vk8s.cpio")
check "amd64: virtio_mmio is built in, so stage 0 loads virtio_blk and squashfs" \
  test "$(printf '%s\n' "$early64" | sort | tr '\n' ' ')" = "/boot/modules/squashfs.ko /boot/modules/virtio_blk.ko "
for m in af_packet evdev rng_core virtio_rng failover net_failover virtio_net virtio_balloon virtio_input netfs 9pnet 9pnet_virtio 9p vsock \
    vmw_vsock_virtio_transport_common vmw_vsock_virtio_transport; do
  check "amd64: late list loads $m" bash -c "printf '%s\n' '$late64' | grep -qx /lib/modules/$m.ko"
done
check "amd64: no ACPI button module" bash -c "! printf '%s\n' '$late64' | grep -q '/button.ko'"
check "amd64: netfs before 9p, vsock before its transport" \
  test "$(printf '%s\n' "$late64" | grep -n '/netfs.ko\|/9p.ko\|/vsock.ko\|/vmw_vsock_virtio_transport.ko' | cut -d: -f2 | tr '\n' ' ')" \
    = "/lib/modules/netfs.ko /lib/modules/9p.ko /lib/modules/vsock.ko /lib/modules/vmw_vsock_virtio_transport.ko "
check "amd64: /lib64 is usr/lib64 (the loader /lib64/ld-linux-x86-64.so.2)" \
  bash -c "printf '%s\n' '$links64' | grep -qx 'lib64 usr/lib64'"
check "amd64: /usr/lib64 is the disk's" bash -c "printf '%s\n' '$links64' | grep -qx 'usr/lib64 /assets/guest/usr/lib64'"
check "arm64: no /lib64 link" bash -c "! grep -q '^l lib64 ' '$tmp/cpio.txt'"

# Stage 0 mounts the assets disk where the links point, then runs PID 1.
check "stage 0 loads the early list" grep -q '/etc/vk8s/modules.early' scripts/guest/stage0.sh
check "stage 0 mounts /dev/vda read-only at /assets" grep -q 'mount -t squashfs -o ro /dev/vda /newroot/assets' scripts/guest/stage0.sh
check "stage 0 runs /sbin/vk8s-init" grep -q 'switch_root /newroot /sbin/vk8s-init' scripts/guest/stage0.sh

if [ $fails = 0 ]; then echo "all PASS"; else echo "$fails FAIL"; exit 1; fi
