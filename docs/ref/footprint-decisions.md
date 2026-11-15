# Minimal host footprint: vk8s decisions

GOAL.md section 7 is vk8s-only behavior: vcluster runs in Docker and has
no counterpart. Each entry records what vk8s does and why. Concrete laws
on these items take their expected values from this file.

## M1. bend-vmm's balloon on every VM (src/cli/cli.bend)

bend-vmm e4b1bdf (pinned as 0x5d8f2af4bacb57815fa6a96a49bd679a) adds a
virtio-balloon device: virtio-mmio id 5, VIRTIO_F_VERSION_1 and
VIRTIO_BALLOON_F_FREE_PAGE_REPORTING (bit 5), queues 0 inflate, 1
deflate, 2 reporting. It goes last in the device list. It is off by
default, and the flag `--balloon free-page-reporting` turns it on. Freed
ranges read back as zeros. Only whole 64 KiB blocks are released. Linux
reports free blocks of 2 MiB and larger.

vk8s passes `--balloon free-page-reporting` to every VM: the control
plane (`Cli.vmm_flags_x`), the workers (`Cli.worker_flags`) and the image
cache (`Cli.cache_flags`). The flag comes last, after the other flags
(`Cli.balloon_flags`).

The guest loads `virtio_balloon` (scripts/guest/modules.txt) with its
dependencies from Alpine's linux-virt 6.18 (3.24-stable, linux-lts
6.18.63). Its virt.aarch64.config has `CONFIG_VIRTIO_BALLOON=m`, and in
Linux 6.18 `VIRTIO_BALLOON` selects the bool `PAGE_REPORTING`, so
`CONFIG_PAGE_REPORTING=y`. The module's init only registers a virtio
driver (`module_virtio_driver`). It binds to device id 5 only, so it is
harmless on a VMM without the device. With 4 KiB pages the driver leaves
the reporting order at pageblock order (2 MiB).

Amended 2026-11-15 (user approved; bend-vmm 0xe9825c44, ea30ce3): every
VM gets `--balloon auto`, bend-vmm's default. Besides free page reporting,
bend-vmm polls the balloon's stats queue every 2 s from 30 s after boot,
inflates until the guest has max(256 MiB, RAM/10) free (holding at most
half of RAM) and deflates at once below that floor. It catches memory the
guest frees and reuses, which free page reporting never reports again.

## M2. PID 1 reclaims page cache when the node is idle (src/guest/plan.bend)

Free page reporting returns free pages only. The page cache is in use:
after an image pull or a pod burst it holds hundreds of MiB that the host
never gets back. PID 1 runs `Plan.idle_reclaim` every 120 supervisor
ticks (30 s) on every VM:

1. Idle check. It reads the `cpu` line of /proc/stat (user, nice,
   system, idle, iowait, irq, softirq, steal) and keeps the last total
   and idle counters in /run/vk8s-cpu. The window is the time since the
   last run. The node is idle when less than 10% of all vCPU time in the
   window was busy. Iowait counts as busy, so an image pull blocked on
   disk is not idle. The first run after boot only records the counters.
2. Amount. The file cache, Active(file) + Inactive(file) from
   /proc/meminfo, above a floor of 64 MiB (65536 KiB). When that is less
   than 16 MiB (16384 KiB), it does nothing.
3. Reclaim. It writes `<amount>K swappiness=0` to the root cgroup's
   /sys/fs/cgroup/memory.reclaim. It ignores errors (EAGAIN when less
   could be reclaimed) and exits 0.

The step, as `Plan.idle_reclaim()` makes it:

```
/bin/busybox sh -c 'set -- $(head -n 1 /proc/stat); t=$(($2+$3+$4+$5+$6+$7+$8+$9)); i=$5; { read pt pi < /run/vk8s-cpu; } 2>/dev/null || { pt=0; pi=0; }; echo "$t $i" > /run/vk8s-cpu; dt=$((t-pt)); b=$((dt-i+pi)); [ $pt -gt 0 ] && [ $dt -gt 0 ] && [ $((b*100)) -lt $((dt*10)) ] || exit 0; k=$(awk '\''/^(Active|Inactive)\(file\):/ { s += $2 } END { print s - 65536 }'\'' /proc/meminfo); [ "$k" -ge 16384 ] || exit 0; { echo "${k}K swappiness=0" > /sys/fs/cgroup/memory.reclaim; } 2>/dev/null; true'
```

Why memory.reclaim, and not the other knobs:

- `memory.reclaim` (Linux 5.19 and later; the root cgroup has it, and
  6.18 accepts `swappiness=`) reclaims a given amount the way kswapd
  does, in LRU order, coldest pages first. It stops at the amount, and
  it never triggers the OOM killer. `swappiness=0` limits it to the page
  cache and slab, so anonymous memory stays where it is even if a swap
  device is added later. The 64 MiB floor keeps the hottest pages, such
  as the text of kubelet, containerd and the control plane, resident.
- `echo 1 > /proc/sys/vm/drop_caches` drops all clean, unmapped cache at
  once. It cannot keep a floor, and it is the fallback only if
  memory.reclaim goes away.
- `vm.vfs_cache_pressure` only shifts the balance between slab and page
  cache when the kernel is already under memory pressure. An idle guest
  with free memory has no pressure, so the knob reclaims nothing.
- `memory.high` on a slice is a limit, not a reclaim. vk8s runs its
  daemons with the cgroupfs driver in the root cgroup, and a limit would
  throttle kubelet and containerd under load, which GOAL section 7 must
  not do.
- `page_reporting.page_reporting_order` decides which free blocks are
  reported, not how much memory is free. The default (2 MiB with 4 KiB
  pages) avoids splitting huge pages and keeps the reports few. Lower it
  only if a measurement shows free memory too fragmented to report:
  M3 below did.

Load is never hurt: under load the window is busy and nothing happens.
A reclaim on an idle node costs a fraction of a second of one vCPU.

The thresholds (30 s, 10%, 64 MiB, 16 MiB) are a first choice. The Mac
measurement against GOAL section 7's target (a worker VMM within 256 MiB
of the guest's used memory after a 30-pod burst and 2 min idle) decides
whether they change.

## M3. Free page reporting at order 4 (2026-11-15)

Measured on the Mac (bend-vmm 852acb5, a 2 GiB worker after a 30-pod
burst, 2 min idle, drop_caches and compact_memory): the guest had 1.68 GB
free, but about 270 MB of it sat in blocks under 2 MiB, which order 9
never reports. 555 releases of 2 MiB; phys_footprint 1.1 GB. With
`page_reporting_order` 4 (64 KiB, bend-vmm's release unit) the same
guest made 1363 releases (64 KiB to 4 MiB) and phys_footprint fell to
778 MB. PID 1 sets it with the other sysctls (Plan.sysctls). The cost is
more, smaller reports: each is one virtqueue round trip and one unmap and
map in bend-vmm, a few microseconds, only after memory is freed.

## M4. Idle memory compaction (src/guest/plan.bend Plan.idle_compact)

bend-vmm (0xe9825c44) returns a ballooned or reported range to macOS only
in whole 64 KiB blocks, i.e. when all 16 guest pages of a block are free.
After a pod burst guest memory is fragmented, so most balloon pages sit in
blocks with in-use neighbours and stay charged (bend-vmm measured balloon
841 MiB with 1.3 GB phys_footprint). Every 10 min PID 1 compacts memory
(`/proc/sys/vm/compact_memory`) when the node was idle (under 10% busy)
over that window, with its own /proc/stat state so the 30 s reclaim
window is untouched. Measured 2026-11-15, 2 GiB worker, 30-pod burst:
phys_footprint 777 MB at 4.5 min idle, 741 MB at 12.5 min (after one
compaction), for 265 MB of real guest use. A small gain; the real fix is
bend-vmm releasing at the 16 KiB host page size (asked).

## M5. The guest kernel with 16 KiB pages (2026-11-15, opt-in)

macOS on Apple Silicon maps memory in 16 KiB pages. bend-vmm can give a
guest page back to macOS only as a whole host page. With Alpine's
linux-virt (4 KiB pages), a free 4 KiB guest page beside a used one
stays resident: about 400 MB per VM that free page reporting and the
balloon can never return. With 16 KiB guest pages every free guest page
is a whole host page. Apple's CPUs support the 4 KiB and 16 KiB
translation granules but not 64 KiB, so 16 KiB is the only larger choice.

`scripts/guest/kernel.sh` builds the kernel. `VK8S_KERNEL=16k
scripts/guest/build.sh` uses it, from `VK8S_KERNEL_DIR` (default
out/build/kernel16k) when that holds a build, for example CI's
`kernel16k` artifact. Alpine's package stays the default until the
maintainer boots the 16K kernel on the Mac.

What is pinned:

- Linux 6.18.63, the version of Alpine's linux-virt in 3.24-stable:
  kernel.org's `linux-6.18.tar.xz` and `patch-6.18.63.xz`, each checked
  against the SHA-512 in aports' APKBUILD at commit
  aabe3e5ce3d1b3469580a931ce1746e05dc95c01 ("main/linux-lts: upgrade to
  6.18.63"). These are the bytes Alpine built its package from. The
  sandbox that wrote the script could not reach kernel.org, so it pins
  Alpine's SHA-512 values, not kernel.org's SHA-256 list. Alpine's own
  patches (powerpc, x86, objtool, sophgo, and the
  `kexec_load_disabled` boot option) are not applied: none changes an
  arm64 virt guest that vk8s boots.
- The config: aports `main/linux-lts/virt.aarch64.config` at the same
  commit (SHA-512 from the APKBUILD, SHA-256
  120ebd889badde4bcaf394325aae2fab73ce2ef3c18d30ad40f9443b3ba26b69),
  run through `olddefconfig` with these changes:
  - `CONFIG_ARM64_16K_PAGES=y`, `CONFIG_ARM64_4K_PAGES` unset. The VA
    size stays Alpine's 48 bits: `CONFIG_ARM64_VA_BITS=48`, and 16 KiB
    pages with 48-bit VA give `CONFIG_PGTABLE_LEVELS=4`
    (`CONFIG_PAGE_SIZE_16KB=y`, `CONFIG_PAGE_SHIFT=14`; Linux 6.10+
    has no `ARM64_PAGE_SHIFT`). The script stops if the final
    config differs.
  - `CONFIG_VIRTIO_BALLOON=m` and `CONFIG_PAGE_REPORTING=y`, as in M1.
  - `CONFIG_LOCALVERSION="-0-virt16k"` (uname -r 6.18.63-0-virt16k).
  - For a reproducible build: no module signing (`CONFIG_MODULE_SIG`
    makes a new key per build; so no `CONFIG_SECURITY_LOCKDOWN_LSM`,
    which selects it, and lockdown without signed modules lets any
    module load anyway), no GCC plugins (`latent_entropy` seeds
    each build), no debug info and so no BTF (nothing in the guest uses
    BTF; flannel needs no BPF CO-RE), no module compression (modules.py
    reads plain `.ko`).
- The toolchain: the `debian:trixie-slim` image by digest
  (sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2),
  trixie's gcc. The build runs natively on arm64 (the Mac, GitHub's
  ubuntu-24.04-arm) and with the aarch64-linux-gnu cross compiler
  elsewhere. `KBUILD_BUILD_TIMESTAMP` is the aports commit's time,
  `KBUILD_BUILD_USER`, `KBUILD_BUILD_HOST` are `vk8s`, and
  `KBUILD_BUILD_VERSION` is 1. The packages that apt installs in the
  image are trixie's current ones, not a snapshot. Two builds on arm64
  compare by the `SHA256SUMS` file the script writes.

Output: a raw arm64 `Image` (bend-vmm boots it as is; no EFI zboot) and
`lib/modules/6.18.63-0-virt16k` with the modules, stripped, and
`modules.dep`. build.sh hands this tree to pack.sh as it does Alpine's,
so modules.early.txt and modules.txt resolve through modules.py.

CI (`kernel16k` job) builds the kernel on ubuntu-24.04-arm, caches it on
kernel.sh's hash, and boots it under `qemu-system-aarch64 -M virt -cpu
max` (TCG) with the real stage 0 and assets disk (tests/kernel16k_boot.sh).
A test PID 1 checks `getconf PAGESIZE` 16384, loads every module of
modules.txt, runs iptables against nf_tables and each asset binary's
version command, and starts etcd for a put and a get.

### Userspace on 16 KiB pages

A program fails on a 16 KiB kernel when it was built for a fixed 4 KiB
page: jemalloc built with `--with-lg-page=12` (it aborts with
"Unsupported system page size"), some JIT and garbage collectors with a
hard-coded page size, and ELF files whose `PT_LOAD` segments are aligned
to less than 16 KiB (the kernel then cannot map them). Go aligns arm64
segments to 64 KiB and reads the page size at run time; glibc, musl and
the arm64 GNU linker default (`max-page-size` 64 KiB) do too.

| Asset (where it comes from) | Language, libc | 16 KiB pages |
|---|---|---|
| kube-apiserver, kube-controller-manager, kube-scheduler, kubelet, kubeadm, kubectl, kube-proxy (loft-sh bundle, dl.k8s.io) | Go, static | No known issue |
| etcd, etcdctl, etcdutl (bundle) | Go, static | bbolt takes its page size from the system when it creates a database: a new member's db has 16 KiB pages. bbolt reads the size from the file's meta page, so a db made on 4 KiB opens on 16 KiB and the reverse; snapshots (docs/SNAPSHOT.md) stay portable |
| kine (bundle) | Go, SQLite through cgo | SQLite's page size is its own (4096 by default), not the system's: no issue |
| konnectivity-server, helm (bundle) | Go | No known issue |
| containerd, containerd-shim-runc-v2, crictl (bundle) | Go | No known issue |
| runc (bundle) | Go with a C part (nsexec), static | No known issue; runc runs on 16K and 64K arm64 distributions |
| CNI plugins (bundle, cni/bin) | Go | No known issue |
| registry (CNCF distribution) | Go | No known issue |
| pause image (bundle) | C, static | No known issue |
| vk8s-init (host/init.bend through zig cc, musl, static) | C, musl | musl reads the page size from the auxiliary vector on arm64: no issue |
| vk8s-guest (zig cc, glibc 2.38, dynamic) | C, glibc | No known issue; zig cc links with LLD, whose arm64 default `max-page-size` is 64 KiB |
| busybox (static, bend-vmm's build) | C | Not checked in CI (the qemu test uses Debian's busybox-static); the Mac boot test runs it |
| Debian trixie arm64 (debs.txt): libc6, libssl3t64, libzstd1, zlib1g, iptables, libxtables12, libip4tc2, libip6tc2, libnftnl11, libmnl0, libnetfilter-conntrack3, libnfnetlink0, conntrack | C, glibc | Debian builds arm64 for any page size up to 64 KiB (Asahi runs 16 KiB): no issue |
| flannel, coredns images (flannel.yaml, coredns.yaml) | Go | No known issue |

None of the assets links jemalloc. Workloads that users run in their
pods can: an image with jemalloc built for 4 KiB pages (some Redis,
MariaDB or Rust builds made for x86-first defaults) aborts at start on
any 16 KiB arm64 host, Asahi Linux and Apple's own VMs alike. Debian
and most official images build arm64 jemalloc with a 64 KiB page.

### Open

- `Plan.page_reporting_order` is "4" (M3, a law in laws/plan.bend). With
  4 KiB pages that is 64 KiB, bend-vmm's release unit; with 16 KiB pages
  order 4 is 256 KiB, and order 2 would be 64 KiB. The order must follow
  the page size before the 16K kernel becomes the default; the law
  belongs to the architect.
- The Mac boot test: bend-vmm must load an Image whose header says 16 KiB
  pages (header flags bits 1-2 = 2) and the guest must see 16 KiB
  granule support in ID_AA64MMFR0_EL1 under Hypervisor.framework.
