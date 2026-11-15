# Minimal host footprint: vk8s decisions

docs/GOAL.md section 7 asks that every VM give back the host memory it
does not use. vcluster has no counterpart: vind runs containers, which
share the host kernel's page allocator. These entries are vk8s design.
Concrete laws in laws/plan.bend (under `# Proposed:`) take their values
from this file.

## M1. The guest loads virtio_balloon

bend-vmm is adding a virtio-balloon device with free page reporting
(VIRTIO_BALLOON_F_REPORTING in the virtio spec; the bend-vmm flag name
is not chosen yet). The guest side is ready before the device:

- scripts/guest/modules.txt lists `virtio_balloon`. modules.py resolves
  its dependencies from Alpine linux-virt 6.18's modules.dep, and PID 1
  insmods it with the other modules.
- Loading it without the device does nothing: the module only registers
  a virtio driver for device ID 5. The driver probes only when a VM
  offers that device, so today's bend-vmm VMs are not affected.
- Free page reporting needs CONFIG_PAGE_REPORTING=y. Linux v6.18
  drivers/virtio/Kconfig: `config VIRTIO_BALLOON ... select
  MEMORY_BALLOON, select PAGE_REPORTING`. Alpine 3.23's linux-lts 6.18.63
  virt.aarch64.config sets CONFIG_VIRTIO_BALLOON=m, so the built kernel
  has CONFIG_PAGE_REPORTING=y. (The aports file is minimized and does not
  list the selected symbol.) scripts/guest/build.sh checks the package's
  boot/config, when the package has one, and stops the build if either
  symbol is missing.

## M2. PID 1 reclaims the page cache when the node is idle

Free page reporting returns only free pages. Page cache is not free:
after image pulls and pod churn it keeps what the pods freed, and the
host keeps the memory under it. PID 1 (host/init.bend) runs
`Plan.give_back` (src/guest/plan.bend) every 120 ticks (30 s):

- Idle window: two /proc/stat samples, 30 s apart. Busy time is user,
  nice, system, iowait, irq and softirq; total time adds idle and steal.
  The window is idle when total time passed and busy time is under a
  fifth of it. On 2 vCPUs that is under 0.4 CPU on average. A node under
  load is never touched, so kubelet and containerd keep their cache.
- Counters: each /proc/stat counter keeps its last 8 digits (Bend has
  U32 only), and a window's difference is taken modulo 10^8. With 2
  vCPUs at USER_HZ 100 the counters wrap after about 5.8 days; a window
  is 6000 ticks.
- Amount: the clean file cache, Active(file) + Inactive(file) from
  /proc/meminfo, above a floor of 65536 kB (64 MiB). The floor keeps the
  hot daemon binaries in the cache.
- Action: `echo <kB>K > /sys/fs/cgroup/memory.reclaim` on the root cgroup
  (cgroup v2; the file is on every cgroup, root included, since 5.19:
  mm/memcontrol.c registers `reclaim` without CFTYPE_NOT_ON_ROOT), then
  `echo 1 > /proc/sys/vm/compact_memory`. Errors are ignored: EAGAIN only
  says that less was reclaimable.

Why memory.reclaim:

- It reclaims in LRU order (coldest first) and stops at the amount
  asked. The guest has no swap, so it never touches anonymous memory.
  It shrinks reclaimable slab too.
- Not `vm.drop_caches`: it drops all unmapped clean cache at once, with
  no LRU order and no bound, and it logs to the console each time.
- Not `vm.vfs_cache_pressure`: it only weighs dentries and inodes
  against page cache under memory pressure, and an idle guest has none.
- Compaction after reclaim joins the freed pages into large free blocks.
  Page reporting reports only free blocks of `page_reporting_order` or
  larger (the pageblock order, 2 MiB, by default). vk8s does not change
  that order: the balloon driver and the device decide it.

## M3. The bend-vmm flag

`Cli.vmm_flags_x`, `Cli.worker_flags` and `Cli.cache_flags`
(src/cli/cli.bend) carry a `TODO(bend-vmm balloon)` comment where the
flag goes. vk8s does not pass a flag until bend-vmm names it.
