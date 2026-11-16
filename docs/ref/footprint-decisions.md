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
`kernel16k` artifact. Decision (PR #41): the 16K kernel is an opt-in
build; Alpine's package stays the default.

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
neoverse-n1` (TCG) with the real stage 0 and assets disk
(tests/kernel16k_boot.sh). The test does not use `-cpu max`: under TCG
it turns on SME, SVE, QARMA5 pointer authentication, WFxT and LPA2, and
the boot stopped after "PM: genpd: Disabling unused power domains", while
the same kernel booted under bend-vmm on the Mac (both nodes Ready,
`getconf PAGESIZE` 16384).

The `kernel16k` artifact holds the script's output (Image, config,
SHA256SUMS, lib/modules), and the boot test boots that tree. The module
tree has names that differ only in case (`xt_dscp.ko` and `xt_DSCP.ko`,
`xt_tcpmss.ko` and `xt_TCPMSS.ko`), which macOS's case-insensitive APFS
cannot hold side by side. On the Mac, unpack the artifact with
`unzip -n` (it skips the second name of each pair; modules.early.txt and
modules.txt list no module of a pair).
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
- A change of the default kernel. The maintainer booted the 16K kernel
  under bend-vmm on the Mac (a 1-worker cluster, both nodes Ready,
  `getconf PAGESIZE` 16384); making it the default is a separate
  decision, together with the order above.

## A1. The assets disk is squashfs, zstd (GOAL section 9, 2026-11-16)

assets.img was a raw ext4 image of about 1.0-1.2 GB that the host
unpacked from a 355 MB download and kept uncompressed. It is now a
squashfs image that stays compressed on the host and in the guest:
the download (its .tgz) and the file on disk are about the same size.

- `scripts/guest/mksqfs.sh` makes it: `scripts/guest/disktar.py` streams
  one tar (the Kubernetes binaries at the root, the guest root under
  guest/; owners root, times 0) into `sqfstar -comp zstd
  -Xcompression-level 19 -b 262144 -mkfs-time 0 -all-root -no-xattrs`.
  Nothing is unpacked on the host, so the Debian root's names that
  differ only in case survive on macOS, as with debugfs before. A second
  build from the same inputs is the same bytes (tests/guest_image.sh),
  which the release's SHA-256 pin needs.
- Stage 0 loads `squashfs` (modules.early.txt) instead of ext4 and runs
  `mount -t squashfs -o ro /dev/vda /newroot/assets`. ext4 moves to the
  late list (modules.txt already named it): only PID 1's data disk
  needs it, so jbd2, mbcache, crc16 and ext4 leave the initramfs, which
  stays in RAM in every VM.
- PID 1 mounts the disk again at /var/lib/vcluster/bin through
  `Plan.disks.v2` (proposed laws `plan.disks.v2`, `plan.cache.disks_v2`).
  `Plan.disks` and its laws `plan.disks` and
  `plan.disks.no_online_discard` pin `"ext4"` for /dev/vda; laws are
  append-only, so `Plan.disks` stays as written and unused by the boot
  plans. The architect may retire it.
- 256 KiB blocks: a page fault decompresses at most one block, and since
  Linux 5.18 squashfs fills the block's other pages into the page cache
  too, so sequential reads of a binary cost one decompression per block.
  zstd decompresses at about 1 GB/s per core; the level only changes
  build time and size.
- Tools: `brew install squashfs` (4.7.5, built with zstd, ships
  sqfstar); Debian and Ubuntu `squashfs-tools` 4.6+. e2fsprogs is still
  needed for the data disk template (mkfs.ext4), not for debugfs.

Why squashfs and not erofs, which GOAL section 9 allowed and the brief
preferred: erofs needs zstd from mkfs.erofs to reach the size target,
and neither host has it. Homebrew's erofs-utils (1.9.4) configures only
lz4 and lzma (`--enable-lz4 --enable-lzma`), and Ubuntu 24.04 (the CI
runners) ships erofs-utils 1.7.1, which predates zstd. lz4hc reads
fastest but compresses Go binaries about a third worse than zstd, and
erofs's MicroLZMA decompresses slowly enough to show in the boot time
(every VM pages in kube-apiserver, kubelet and containerd at start).
erofs with zstd stays a one-script change (mksqfs.sh, stage0.sh,
modules.early.txt, a `Plan.disks.v3`) if a zstd-capable mkfs.erofs
reaches both hosts.

## A2. Tools no guest runs are dropped (GOAL section 9, 2026-11-16)

Every use in src/ and host/ was checked:

| Asset | Size (KiB) | Use | Decision |
|---|---|---|---|
| helm | 56196 | none: only comments name vcluster's `*_helm.go` files (src/cli/kubeconfig.bend:7, src/standalone/snapshot.bend:5) | dropped |
| crictl | 36760 | none | dropped |
| kube-proxy (binary, dl.k8s.io) | about 40000 | none: `Plan.kube_proxy_args` (src/guest/plan.bend) is defined but never used; kube-proxy runs as kubeadm's DaemonSet (`kubeadm init phase addon kube-proxy`, src/guest/plan.bend) from the preloaded image | dropped; the image stays |
| vcluster-tunnel | 25476 | none | dropped |
| cni/bin/bandwidth, cni/bin/firewall | 4792, 5436 | none: vk8s's conflist (`Plan.cni_config`) chains bridge and portmap, flannel's (scripts/guest/flannel.yaml) flannel and portmap, and flannel delegates to bridge and host-local | dropped |
| pause-image.txt | 4 | none | dropped |
| ctr | 22980 | image import (`Plan.runtime`, `Plan.image_load.go`, scripts/guest/images.sh) | kept |
| etcdutl | 16516 | embedded etcd restore (`Plan.restore_store`, law plan.restore_store) | kept |
| etcdctl | 16388 | snapshots and kine restore (`Plan.etcdctl`) | kept |
| konnectivity-server | 69444 | classic mode (`Plan.konnectivity_args`) | kept (D1 moves it to the classic set) |
| registry | 51076 | the image cache VM (`Plan.registry_steps`) | kept (D1 moves it to the cache set) |

scripts/guest/fetch-assets.sh copies only the kept files by name, and
tests/kernel16k_boot.sh fails if a dropped one comes back.

## A3. Preloaded images stay on the assets disk (GOAL section 9)

GOAL section 9 asks that coredns, flannel and kube-proxy be pulled
through the image cache where it runs, and preloaded only where it does
not. Not done yet, because with one assets archive it saves nothing:

- The tars (83 MB, already gzip'd layers, so squashfs does not shrink
  them) are part of assets.img, which every host downloads whole
  (`manifest.four_archives`). Skipping their import when the cache runs
  saves neither download nor host disk.
- A pull stores the same content and snapshots on the data disk as an
  import does, so the guest saves nothing either.
- `vk8s cache` is optional and starts on its own; a cluster that boots
  without it must still start its add-ons offline, so the tars must be
  on hand anyway.

It pays off once the images are their own archive that only a host
without the cache downloads: D1 below.

Done with D1 (2026-11-16): the tars are the images set. A host attaches
it, and fetches it, only to a VM that boots while the image cache does
not run (`Assets.role_sets`). Without it, the import loop of
`Plan.runtime` finds no tar under bin/images and imports nothing, and
kubelet pulls flannel, CoreDNS and kube-proxy through containerd's
mirrors (`Plan.mirror_steps`), the cache first, at first use. The pause
image stays in the node set: it is pinned as the sandbox image and
imported at every boot.

## D1. Per-role asset sets (GOAL section 9, 2026-11-16)

The assets disk splits into a base disk and one read-only squashfs disk
per role set. The laws that fix the single disk stay as written (laws
are append-only); v2 and v3 defs with their own proposed laws sit beside
them:

- `manifest.four_archives`: `Manifest.files()` stays four archives, the
  ones every VM boots: Image, vk8s.cpio, base.img (was assets.img) and
  data.img. `Manifest.sets()` pins one archive per set,
  `<set>.img.tgz` (laws `manifest.sets_pinned`, `manifest.sets_named`).
  scripts/release-assets.sh writes both. The release pinned today
  (v1.36.6-42a05fb8) predates squashfs and the sets, so its
  `Manifest.sets()` is empty, and vk8s on main needs the next release
  or VK8S_ASSETS.
- `plan.disks` / `plan.disks.v2`: the boot plans keep `Plan.disks.v2`
  (`plan.cache.disks_v2` pins the cache plan's steps). PID 1 swaps its
  bin/ mount for `Plan.disks.v3`'s set mounts with `Plan.with_sets`,
  when the kernel command line names sets (VK8S_SETS). With no
  VK8S_SETS (an assets dir with one assets.img, no base.img) the plan
  boots as before.
- `cli.*_flags.balloon` pin the flag count before `--balloon`; the set
  disks join the one `--disk` value and VK8S_SETS the one `--cmdline`
  value (`Cli.role_flags`), so the counts stay.

### The sets

scripts/guest/sets.txt lists them; scripts/guest/mksets.sh makes one
disk per set and fails on an asset that is in no set. Sizes from the
loft-sh v1.36.6 arm64 bundle and registry 3.1.2, after A2 (KiB; the
squashfs sizes from CI's assets-disk job, run 43834400562):

| Set | Contents | Uncompressed | squashfs |
|---|---|---|---|
| base (base.img, /dev/vda) | guest/: vk8s-init, vk8s-guest, the Debian root, the late modules, CA roots | from the Mac build | |
| node | kubelet, kubeadm, containerd, containerd-shim-runc-v2, runc, ctr, cni/bin (bridge, host-local, loopback, portmap), pause-image.tar | 226944 | 62268 |
| control-plane | kube-apiserver, kube-controller-manager, kube-scheduler, kubectl, kine, etcd, etcdctl, etcdutl | 342896 | 86808 |
| classic | konnectivity-server | 69448 | 24964 |
| cache | registry | 51080 | 11820 |
| images | flannel, flannel-cni-plugin, coredns, kube-proxy tars | about 83000 | about 83000 |

kubeadm is in node, not control-plane: workers run `kubeadm join`, and
the control planes, which mount node too, make their PKI with it.

Who mounts what (`Assets.role_sets(role, cached)`; cached: the image
cache runs when the VM starts; laws `assets.role_sets.*`):

| VM | Sets (disk order) |
|---|---|
| standalone control plane (a node too) | node, control-plane, images unless cached |
| classic control plane (its pods run on the host cluster; kubeadm makes its PKI) | node, control-plane, classic |
| worker | node, images unless cached |
| image cache | cache |

### Disks

- /dev/vda stays the base disk: stage 0 mounts it at /assets, since
  PID 1 and glibc live on it. /dev/vdb stays the data disk.
- /dev/vdc onward: the role's sets in the order above
  (`Cli.disks_v3`: `<assets>/base.img:ro:nocache,<data>,<assets>/<set>.img:ro:nocache,...`),
  named on the kernel command line in the same order
  (`VK8S_SETS=node,control-plane`).
- PID 1 mounts each at /sets/<set> (stage 0's tmpfs root; /assets is
  read-only squashfs, so no mount point can be made under it) and joins
  them at /var/lib/vcluster/bin with a read-only overlay of lower
  directories only (`ro,lowerdir=/sets/node:/sets/control-plane`), so
  `Plan.bin()` and every path under it stay as they are. One set (a
  cached worker, the cache VM) needs no overlay: its disk is mounted
  again at bin/ (`Plan.disks.v3`, laws `plan.disks.v3.*`,
  `plan.with_sets.*`). overlay is in modules.txt, which PID 1 loads
  before the disks.

### Download

- `vk8s create` fetches the base files of the pinned release (as
  before), then, before each VM starts, the sets of its role that the
  assets dir lacks (`Assets.set_files`, `Assets.fetch_into_sh`: each
  archive checked against its pin, into a private staging dir inside
  the assets dir, then moved into place unless another run placed it
  first). A worker-only host fetches base and node; a host whose image
  cache runs never fetches images. A local VK8S_ASSETS dir must hold
  the sets already (scripts/guest/build.sh installs them).
- An assets dir is per-role when it has base.img. A dir with one
  assets.img (an earlier build) boots as before: same flags, no
  VK8S_SETS, `Plan.disks.v2`.

### Evidence

CI (assets-disk with Alpine's 4 KiB kernel, kernel16k with the 16 KiB
build) boots each role under qemu with base, data and its set disks
(tests/kernel16k_boot.sh): the disks get the expected names (serials),
PID 1 mounts them as `Plan.disks.v3` does, the role's binaries run, and
the other sets' binaries are absent. The Mac regression subset (standalone
and classic, scripts/regression.sh) runs after the merge.
