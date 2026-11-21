import Base
import ../laws/cli.bend as L
import ../src/cli/cli.bend as C

# Proofs of laws/cli.bend: `def L.<law>` for each law.

def L.cli.parse.create():
  {==}

def L.cli.parse.create_nodes_etcd():
  {==}

def L.cli.parse.create_bad_name():
  {==}

def L.cli.parse.vmm():
  {==}

def L.cli.parse.list():
  {==}

def L.cli.valid_name.plain():
  {==}

def L.cli.valid_name.one_char():
  {==}

def L.cli.valid_name.dashes_digits():
  {==}

def L.cli.valid_name.leading_digit():
  {==}

def L.cli.valid_name.empty():
  {==}

def L.cli.valid_name.upper_underscore():
  {==}

def L.cli.valid_name.leading_dash():
  {==}

def L.cli.valid_name.trailing_dash():
  {==}

def L.cli.valid_name.dot():
  {==}

def L.cli.valid_name.len_52():
  {==}

def L.cli.valid_name.len_53():
  {==}

def L.cli.lan_ip.control_plane():
  {==}

def L.cli.lan_ip.worker_1():
  {==}

def L.cli.lan_ip.worker_2():
  {==}

def L.cli.worker_name.first():
  {==}

def L.cli.worker_name.tenth():
  {==}

def L.cli.list.json():
  {==}

def L.cli.list.table():
  {==}

def L.cli.describe.plain():
  {==}

def L.cli.describe.config_only():
  {==}

def L.cli.describe.json():
  {==}

def L.cli.connect.exec():
  {==}

def L.cli.snapshot.file_url():
  {==}

def L.cli.restore.path():
  {==}

def L.cli.logs.component():
  {==}

def L.cli.list_json.one():
  {==}

def L.cli.list_json.empty():
  {==}

def L.cli.list_table.age():
  {==}

def L.cli.paths_fit.home():
  {==}

def L.cli.paths_fit.edge():
  {==}

def L.cli.paths_fit.too_long():
  {==}

def L.cli.node_dir():
  {==}

def L.cli.cache.start():
  {==}

def L.cli.cache.bad():
  {==}

def L.cli.cache_forwards():
  {==}

def L.cli.create.upgrade():
  {==}

def L.cli.node.add_default():
  {==}

def L.cli.node.add_count():
  {==}

def L.cli.node.delete():
  {==}

def L.cli.node.delete_no_drain():
  {==}

def L.cli.workers.next():
  {==}

def L.cli.workers.drop():
  {==}

def L.cli.workers.upto():
  {==}

def L.cli.worker_index():
  {==}

def L.cli.worker_index.other():
  {==}

def L.cli.token_ok.valid():
  {==}

def L.cli.token_ok.shell():
  {==}

def L.cli.token_ok.short():
  {==}

def L.cli.token_secret():
  {==}

def L.cli.create.no_connect():
  {==}

def L.cli.create.connect_default():
  {==}

def L.cli.create.restore():
  {==}

def L.cli.create.classic_default_ns():
  {==}

def L.cli.create.classic_ns():
  {==}

def L.cli.certs.rotate():
  {==}

def L.cli.certs.bad():
  {==}

def L.cli.node.load_archive():
  {==}

def L.cli.certs.rotate_ca():
  {==}

def L.cli.token.create_default():
  {==}

def L.cli.token.create_flags():
  {==}

def L.cli.token.list_json():
  {==}

def L.cli.token.delete():
  {==}

def L.cli.create.values():
  {==}

def L.cli.konn_port():
  {==}

def L.cli.kubelet_port():
  {==}

def L.cli.classic_forwards.on():
  {==}

def L.cli.classic_forwards.off(p):
  {==}

def L.cli.konn_name():
  {==}

def L.cli.join_port():
  {==}

def L.cli.join_port.low():
  {==}

def L.cli.join_port.high():
  {==}

def L.cli.forwards.standalone():
  {==}

def L.cli.forwards.classic():
  {==}

def L.cli.join_endpoint():
  {==}

def L.cli.api_endpoint():
  {==}

def L.cli.snapshot.open():
  {==}

def L.cli.snapshot.open_eq():
  {==}

def L.cli.snapshot.vm():
  {==}

def L.cli.snapshot.bad_format():
  {==}

def L.cli.snapshot.format_no_value():
  {==}

def L.cli.snapshot.unknown_option():
  {==}

def L.cli.snapshot.s3():
  {==}

def L.cli.snapshot.oci():
  {==}

def L.cli.snapshot.https():
  {==}

def L.cli.snapshot.container():
  {==}

def L.cli.restore.file_url():
  {==}

def L.cli.restore.s3():
  {==}

def L.cli.assets.prune():
  {==}

def L.cli.assets.prune_dry_run():
  {==}

def L.cli.assets.bad():
  {==}

def L.cli.assets_prune.superseded():
  {==}

def L.cli.assets_prune.in_use():
  {==}

def L.cli.assets_prune.override():
  {==}

def L.cli.assets_prune.pinned_only():
  {==}

def L.cli.assets_prune.local_build():
  {==}

def L.cli.balloon_flags():
  {==}

def L.cli.vmm_flags.balloon():
  {==}

def L.cli.worker_flags.balloon():
  {==}

def L.cli.cache_flags.balloon():
  {==}

def L.cli.create.restore_backing_store():
  {==}

def L.cli.create.backing_store_restore():
  {==}

def L.cli.restore.backing_store():
  {==}

def L.cli.clone_gnu.args():
  {==}

def L.cli.clone_bsd.args():
  {==}

def L.cli.rfc3339_in_one_hour():
  {==}

def L.cli.created_text():
  {==}

def L.cli.created_text.utc():
  {==}

def L.cli.created_rfc3339():
  {==}

def L.cli.created_rfc3339.utc():
  {==}

def L.cli.created_sh.gnu_first():
  {==}

def L.cli.preflight.names_missing():
  {==}

def L.cli.preflight.none():
  {==}

def L.cli.preflight_tools():
  {==}

def L.cli.path_candidates():
  {==}

def L.cli.kvm_needed.linux():
  {==}

def L.cli.kvm_needed.macos():
  {==}

def L.cli.kvm_needed.no_vm():
  {==}

def L.cli.disks_v3():
  {==}

def L.cli.sets_word():
  {==}

def L.cli.role_flags.worker_disk():
  {==}

def L.cli.role_flags.worker_cmdline():
  {==}

def L.cli.role_flags.cache():
  {==}

def L.cli.role_flags.vmm_balloon():
  {==}

def L.cli.cp_role.classic():
  {==}

def L.cli.cp_role.standalone():
  {==}

def L.cli.role_flags.off(f, a, d, s):
  {==}

def L.cli.arch_flags.amd64():
  {==}

def L.cli.arch_flags.arm64():
  {==}

def L.cli.arch_flags.unknown():
  {==}

def L.cli.arch_flags.vmm_balloon_last():
  {==}

def L.cli.arch_flags.worker_balloon_last():
  {==}

def L.cli.role_flags.amd64_cache_cmdline():
  {==}

def L.cli.role_flags.amd64_cache_disk():
  {==}

def L.cli.wait_scale.unset():
  {==}

def L.cli.wait_scale.eight():
  {==}

def L.cli.wait_scale.max():
  {==}

def L.cli.wait_scale.zero():
  {==}

def L.cli.wait_scale.too_big():
  {==}

def L.cli.wait_scale.word():
  {==}

def L.cli.wait_tries.unset():
  {==}

def L.cli.wait_tries.scaled():
  {==}

def L.cli.scale_flags.unset():
  {==}

def L.cli.scale_flags.scaled():
  {==}

def L.cli.scale_flags.word():
  {==}

def L.cli.scale_flags.amd64():
  {==}

def L.cli.cache.prune.all():
  {==}

def L.cli.cache.prune.one():
  {==}

def L.cli.cache.prune.unknown():
  {==}

def L.cli.cache.prune.two():
  {==}

def L.cli.cache.status():
  {==}

def L.cli.cache.prune.action():
  {==}

def L.cli.size_kib.kib():
  {==}

def L.cli.size_kib.mib():
  {==}

def L.cli.size_kib.gib():
  {==}

def L.cli.du_kib():
  {==}

def L.cli.du_kib.none():
  {==}

def L.cli.minus.under():
  {==}

def L.cli.cache_status.unmeasured():
  {==}

def L.cli.root_path():
  {==}

def L.cli.port_from.range():
  {==}

def L.cli.host_ports.low():
  {==}

def L.cli.host_ports.high():
  {==}

def L.cli.host_ports.zero():
  {==}

def L.cli.fallback_seed():
  {==}

def L.cli.recorded_elsewhere.self():
  {==}

def L.cli.recorded_elsewhere.other():
  {==}

def L.cli.recorded_elsewhere.prefix():
  {==}

def L.cli.recorded_elsewhere.none():
  {==}

def L.cli.layers_dir():
  {==}

def L.cli.with_layers.on():
  {==}

def L.cli.with_layers.off(d, xs):
  {==}

def L.cli.layers_on.worker():
  {==}

def L.cli.layers_on.cache():
  {==}

def L.cli.layers_on.unset():
  {==}

def L.cli.layers_on.zero():
  {==}

def L.cli.share_quota.v2():
  {==}

def L.cli.layers_on.v2.unset():
  {==}

def L.cli.layers_on.v2.one():
  {==}

def L.cli.layers_on.v2.zero():
  {==}

def L.cli.layers_on.v2.cache():
  {==}

def L.cli.cache_status.v2.running():
  {==}

def L.cli.cache_status.v2.old_disk():
  {==}

def L.cli.cache_pruned.v2():
  {==}
