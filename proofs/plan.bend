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

def L.plan.page_reporting_order():
  {==}

def L.plan.sysctls.page_reporting():
  {==}
