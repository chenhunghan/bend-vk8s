import Base
import ../laws/plan.bend as L
import ../src/lib/args.bend as A
import ../src/guest/plan.bend as P

# Proofs of laws/plan.bend: `def L.<law>` for each law.

def L.plan.apiserver.sqlite.base():
  {==}

def L.plan.apiserver.overrides():
  {==}

def L.plan.apiserver.sqlite.merge():
  {==}

def L.plan.apiserver.sqlite():
  {==}

def L.plan.apiserver.etcd.base():
  {==}

def L.plan.apiserver.etcd.merge():
  {==}

def L.plan.apiserver.etcd():
  {==}

def L.plan.controller_manager():
  {==}

def L.plan.scheduler():
  {==}

def L.plan.kine():
  {==}

def L.plan.sh_quote.empty():
  {==}

def L.plan.sh_quote.plain():
  {==}

def L.plan.sh_quote.single_quote():
  {==}

def L.plan.hosts_toml.docker():
  {==}

def L.plan.hosts_toml_pull.docker():
  {==}

def L.plan.request.unknown():
  {==}

def L.plan.request.check():
  {==}

def L.plan.request.image_load():
  {==}

def L.plan.request.image_load_traversal():
  {==}

def L.plan.certs_expiring.fresh():
  {==}

def L.plan.certs_expiring.within_90():
  {==}

def L.plan.certs_expiring.at_90():
  {==}

def L.plan.certs_expiring.hours():
  {==}

def L.plan.certs_expiring.expired():
  {==}

def L.plan.certs_expiring.none():
  {==}

def L.plan.cert_check_daily():
  {==}

def L.plan.apiserver.overrides_ep():
  {==}

def L.plan.apiserver.ep_merge():
  {==}

def L.plan.add_sans.inserts():
  {==}

def L.plan.add_sans.none():
  {==}

def L.plan.controller_manager.classic_tail():
  {==}

def L.plan.controller_manager.classic_shared():
  {==}

def L.plan.syncer_kip():
  {==}

def L.plan.first_or.some():
  {==}

def L.plan.first_or.none():
  {==}

def L.plan.controller_manager.vsched_tail():
  {==}

def L.plan.controller_manager.vsched_shared():
  {==}

def L.plan.virtual_scheduler.daemon(c, prog, args):
  {==}

def L.plan.virtual_scheduler.syncer(c, prog, args):
  {==}

def L.plan.syncer_config(prog, args):
  {==}

def L.plan.syncer_config.other(prog, args):
  {==}

def L.plan.clock_sync():
  {==}

def L.plan.clock_every_ticks():
  {==}

def L.plan.join_server.user():
  {==}

def L.plan.join_server.daemon():
  {==}

def L.plan.join_server.guest_bin():
  {==}

def L.plan.join_server.role():
  {==}

def L.plan.join_server.binding():
  {==}

def L.plan.control_plane.join_server(c):
  {==}

def L.plan.request.snapshot_export.etcd():
  {==}

def L.plan.request.snapshot_export.kine():
  {==}

def L.plan.kine_dump_script():
  {==}

def L.plan.request.snapshot_export.unsafe():
  {==}

def L.plan.request_mode.classic_snapshot():
  {==}

def L.plan.request_mode.classic_other():
  {==}

def L.plan.request_mode.standalone(a, c, o):
  {==}

def L.plan.boot_restore.none(c):
  {==}

def L.plan.restore_store.etcd(k8s):
  {==}

def L.plan.restore_store.kine(k8s):
  {==}

def L.plan.kine_puts_script():
  {==}

def L.plan.fstrim():
  {==}

def L.plan.fstrim_every_ticks():
  {==}

def L.plan.fstrim_due.period():
  {==}

def L.plan.fstrim_due.twice():
  {==}

def L.plan.fstrim_due.between():
  {==}

def L.plan.fstrim_due.first_tick():
  {==}

def L.plan.disks.no_online_discard():
  {==}

def L.plan.image_gc():
  {==}

def L.plan.disks():
  {==}

def L.plan.reclaim_every_ticks():
  {==}

def L.plan.idle_busy_percent():
  {==}

def L.plan.cache_keep_kib():
  {==}

def L.plan.reclaim_min_kib():
  {==}

def L.plan.idle_reclaim():
  {==}

def L.plan.request.snapshot_dump.etcd():
  {==}

def L.plan.request.snapshot_dump.kine():
  {==}

def L.plan.kine_dump_script.v2():
  {==}

def L.plan.request.snapshot_dump.unsafe():
  {==}

def L.plan.request_mode.classic_snapshot_dump():
  {==}

def L.plan.page_reporting_order():
  {==}

def L.plan.sysctls.page_reporting():
  {==}

def L.plan.compact_every_ticks():
  {==}

def L.plan.idle_compact():
  {==}

def L.plan.disks.v2():
  {==}

def L.plan.cache.disks_v2():
  {==}

def L.plan.disks.v3.standalone():
  {==}

def L.plan.disks.v3.one_set():
  {==}

def L.plan.with_sets.cache():
  {==}

def L.plan.with_sets.worker_disks():
  {==}

def L.plan.with_sets.none(p):
  {==}

def L.plan.platform.amd64():
  {==}

def L.plan.platform.arm64():
  {==}

def L.plan.platform.unset():
  {==}

def L.plan.arch_args.amd64():
  {==}

def L.plan.arch_args.arm64():
  {==}

def L.plan.arch_args.unset():
  {==}

def L.plan.request.sync():
  {==}

def L.plan.containerd_runsc():
  {==}

def L.plan.containerd_runsc.toml():
  {==}

def L.plan.containerd_runsc.config():
  {==}

def L.plan.runtime.runsc():
  {==}

def L.plan.runtimeclass_gvisor():
  {==}

def L.plan.node.runtimeclass_gvisor():
  {==}


def L.plan.tick_ms():
  {==}

def L.plan.tick_periods():
  {==}

def L.plan.reclaim_due():
  {==}

def L.plan.compact_due():
  {==}

def L.plan.compact_due.first():
  {==}

def L.plan.gauge():
  {==}

def L.plan.gauge.garbled():
  {==}

def L.plan.gauge.short():
  {==}

def L.plan.idle_between.idle():
  {==}

def L.plan.idle_between.busy():
  {==}

def L.plan.idle_between.edge():
  {==}

def L.plan.idle_between.unseen():
  {==}

def L.plan.idle_between.wrap():
  {==}

def L.plan.refaults():
  {==}

def L.plan.refaults.missing():
  {==}

def L.plan.refaults.garbled():
  {==}

def L.plan.file_kib():
  {==}

def L.plan.file_kib.missing():
  {==}

def L.plan.reclaim_turn.reclaim():
  {==}

def L.plan.reclaim_turn.busy_counts():
  {==}

def L.plan.reclaim_turn.busy_spike():
  {==}

def L.plan.reclaim_turn.idle_spike():
  {==}

def L.plan.reclaim_turn.under_spike():
  {==}

def L.plan.reclaim_turn.backoff_ends():
  {==}

def L.plan.reclaim_turn.backoff_holds():
  {==}

def L.plan.reclaim_turn.first():
  {==}

def L.plan.reclaim_turn.blind():
  {==}

def L.plan.reclaim_turn.blind_again():
  {==}

def L.plan.reclaim_turn.small():
  {==}

def L.plan.reclaim_turn.min():
  {==}

def L.plan.reclaim_turn.no_meminfo():
  {==}

def L.plan.reclaim_step():
  {==}

def L.plan.compact_turn.idle():
  {==}

def L.plan.compact_turn.busy():
  {==}

def L.plan.mem_init():
  {==}

def L.plan.controller_manager_idle():
  {==}

def L.plan.controller_manager.v2_merge(c):
  {==}

def L.plan.controller_manager.v2():
  {==}

def L.plan.scheduler.v2():
  {==}

def L.plan.control_plane.idle(c):
  {==}

def L.plan.kubelet_idle():
  {==}

def L.plan.kubelet_args.v2(c):
  {==}

def L.plan.go_env.apiserver():
  {==}

def L.plan.go_env.controller_manager():
  {==}

def L.plan.go_env.scheduler():
  {==}

def L.plan.go_env.kubelet():
  {==}

def L.plan.go_env.containerd():
  {==}

def L.plan.go_env.kine():
  {==}

def L.plan.go_env.etcd():
  {==}

def L.plan.go_env.other():
  {==}

def L.plan.env_prog.none(bb, prog):
  {==}

def L.plan.env_prog.some():
  {==}

def L.plan.env_args.none(prog, args):
  {==}

def L.plan.env_args.some():
  {==}

def L.plan.containerd_images():
  {==}

def L.plan.containerd_config.images():
  {==}

def L.plan.imports.v2():
  {==}

def L.plan.runtime.v2():
  {==}

def L.plan.image_load.v2():
  {==}

def L.plan.request.image_load.v2():
  {==}

def L.plan.request.idle_sleep():
  {==}

def L.plan.request.idle_wake_clock():
  {==}

def L.plan.request.idle_wake():
  {==}

def L.plan.request.idle_sync():
  {==}

def L.plan.request.cache_usage():
  {==}

def L.plan.request.cache_prune():
  {==}

def L.plan.request.cache_prune.two():
  {==}

def L.plan.request.cache_prune.unknown():
  {==}

def L.plan.request.cache_prune.empty():
  {==}

def L.plan.request.cache_prune.path():
  {==}

def L.plan.apiserver_healthy.script():
  {==}

def L.plan.apiserver_healthy():
  {==}

def L.plan.default_endpoints.script(c):
  {==}

def L.plan.default_endpoints.v2(c):
  {==}

def L.plan.control_plane.healthy(c):
  {==}

def L.plan.node_leases_renewed.script():
  {==}

def L.plan.node_leases_renewed():
  {==}

def L.plan.request.idle_wake.v2():
  {==}

def L.plan.request.idle_wake_clock.v2():
  {==}

def L.plan.request.v2.idle_sleep():
  {==}

def L.plan.request.v2.sync():
  {==}

def L.plan.request.v2.cache_usage():
  {==}

def L.plan.request_mode.v2.standalone(action, c, out):
  {==}

def L.plan.request_mode.v2.classic_wake():
  {==}

def L.plan.request_mode.v2.classic_snapshot():
  {==}

def L.plan.layers_mount():
  {==}

def L.plan.snapshotter():
  {==}

def L.plan.proxy_plugins():
  {==}

def L.plan.containerd_layers.sample():
  {==}

def L.plan.with_layers.off(ss):
  {==}

def L.plan.with_layers.on():
  {==}

def L.plan.with_layers.no_config():
  {==}

def L.plan.layers_on.vm():
  {==}

def L.plan.layers_on.control_plane():
  {==}

def L.plan.layers_on.unset():
  {==}

def L.plan.layers_on.container():
  {==}

def L.plan.layers_on.cache():
  {==}

def L.plan.layers_env_name():
  {==}

def L.plan.rshared_step():
  {==}

def L.plan.with_rshared.off(ss):
  {==}

def L.plan.with_rshared.on():
  {==}

def L.plan.layers_mount.v2():
  {==}

def L.plan.with_layers.v2.off(ss):
  {==}

def L.plan.with_layers.v2.on():
  {==}

def L.plan.with_layers.v2.no_config():
  {==}

def L.plan.ip6tables():
  {==}

def L.plan.ipv6_off():
  {==}

def L.plan.with_ipv6_off.off(ss):
  {==}

def L.plan.with_ipv6_off.on():
  {==}

def L.plan.containerd_layers_annotations_v2():
  {==}

def L.plan.snapshot_annotations():
  {==}

def L.plan.with_layers.v3.on():
  {==}

def L.plan.with_layers.v3.no_config():
  {==}

def L.plan.containerd_config_unchanged_when_off(ss):
  {==}

def L.plan.containerd_config_unchanged_when_off.container(r, w):
  {==}

def L.plan.containerd_config_unchanged_when_off.node_host():
  {==}

def L.plan.containerd_config_unchanged_when_off.vm_config():
  {==}

def L.plan.with_layers.v4.on():
  {==}
def L.plan.with_layers.v4.off(ss):
  {==}

def L.plan.layers_on_v2.container():
  {==}

def L.plan.layers_on_v2.vm():
  {==}

def L.plan.layers_on_v2.unset(c, r):
  {==}

def L.plan.layers_on_v2.cache():
  {==}

def L.plan.layers_on_v2.node_host():
  {==}

def L.plan.with_layers.v5.off(c, ss):
  {==}

def L.plan.with_layers.v5.vm(ss):
  {==}

def L.plan.with_layers.v5.container():
  {==}
