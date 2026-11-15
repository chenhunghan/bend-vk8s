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
