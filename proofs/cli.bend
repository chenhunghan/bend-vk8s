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

def L.cli.host_mac.darwin():
  {==}

def L.cli.host_mac.linux():
  {==}

def L.cli.tls_absent.not_found():
  {==}

def L.cli.tls_absent.symbol():
  {==}

def L.cli.tls_absent.loaded():
  {==}

def L.cli.tls_absent.socket():
  {==}

def L.cli.tls_needed.mac():
  {==}

def L.cli.tls_needed.linux():
  {==}

def L.cli.tls_degraded.both():
  {==}

def L.cli.tls_degraded.cache():
  {==}

def L.cli.tls_degraded.layers():
  {==}

def L.cli.tls_degraded.loaded(c, l, m, w):
  {==}

def L.cli.tls_degraded.none_on(a, m, w):
  match a:
    case True{}:
      {==}
    case False{}:
      {==}

def L.cli.tls_env.release():
  {==}

def L.cli.tls_env.own_certs():
  {==}

def L.cli.tls_env.absent(s, c, f, d, dir):
  {==}

def L.cli.tls_env.user_ssl():
  {==}

def L.cli.tls_env.user_crypto():
  {==}

def L.cli.snapshot_meta():
  {==}

def L.cli.snapshot_meta.restored():
  {==}

def L.cli.env_workers():
  {==}

def L.cli.env_workers.unended():
  {==}

def L.cli.env_workers.empty():
  {==}

def L.cli.ca_data():
  {==}

def L.cli.ca_data.none():
  {==}

def L.cli.cleanup.services():
  {==}

def L.cli.cleanup.lease():
  {==}

def L.cli.cleanup.selector():
  {==}

def L.cli.cleanup.ns_kinds():
  {==}

def L.cli.cleanup.cluster_kinds():
  {==}

def L.cli.cleanup.drop_ns.created():
  {==}

def L.cli.cleanup.drop_ns.other():
  {==}

def L.cli.cleanup.drop_ns.user():
  {==}

def L.cli.cleanup.ns_done():
  {==}

def L.cli.gvisor.env_name():
  {==}

def L.cli.gvisor.has_flag():
  {==}

def L.cli.gvisor.value():
  {==}

def L.cli.gvisor.drop():
  {==}

def L.cli.gvisor.drop_after_dash():
  {==}

def L.cli.gvisor.on.setting_yes():
  {==}

def L.cli.gvisor.on.setting_no():
  {==}

def L.cli.gvisor.on.record():
  {==}

def L.cli.gvisor.env_line():
  {==}

def L.cli.gvisor.with_record():
  {==}

def L.cli.gvisor.keep():
  {==}

def L.cli.gvisor_flags.on():
  {==}

def L.cli.gvisor_flags.off(xs):
  {==}

def L.cli.optional_off():
  {==}

def L.cli.machine.arm64():
  {==}

def L.cli.machine.x86_64():
  {==}

def L.cli.machine.other():
  {==}

def L.cli.os_of.darwin():
  {==}

def L.cli.os_of.linux():
  {==}

def L.cli.os_of.other():
  {==}

def L.cli.port_in.self():
  {==}

def L.cli.port_in.other():
  {==}

def L.cli.port_in.prefix():
  {==}

def L.cli.port_in.none():
  {==}

def L.cli.port_in.whole_line():
  {==}

def L.cli.port_in.no_newline():
  {==}

def L.cli.port_in.empty():
  {==}

def L.cli.dirname.trailing():
  {==}

def L.cli.dirname.bare():
  {==}

def L.cli.dirname.root():
  {==}

def L.cli.dirname.top():
  {==}

def L.cli.dirname.doubled():
  {==}

def L.cli.dirname.empty():
  {==}

def L.cli.basename.trailing():
  {==}

def L.cli.basename.root():
  {==}

def L.cli.abs_path.dots():
  {==}

def L.cli.abs_path.link():
  {==}

def L.cli.abs_path.link_up():
  {==}

def L.cli.abs_path.slashes():
  {==}

def L.cli.abs_path.relative():
  {==}

def L.cli.abs_path.relative_up():
  {==}

def L.cli.abs_path.dot():
  {==}

def L.cli.abs_path.at_root():
  {==}

def L.cli.abs_path.no_pwd():
  {==}

def L.cli.nodes_stale.new_name():
  {==}

def L.cli.nodes_stale.all_found():
  {==}

def L.cli.nodes_stale.order():
  {==}

def L.cli.nodes_stale.nil(live):
  {==}

def L.cli.nodes_stale.none_live(store):
  match store:
    case Nil{}:
      {==}
    case Con{n, t}:
      %L.cli.nodes_stale.none_live(t) : {Con{n, C.Cli.nodes_stale(t, [])} == Con{n, _} : List<&2, String>}
      {==}

def L.cli.nodes_stale.found(n, t, live, h):
  %Equal.sym(Bool, C.Cli.name_in(live, n), True{}, h) : {C.Cli.nodes_stale.keep(_, n, C.Cli.nodes_stale(t, live)) == C.Cli.nodes_stale(t, live) : List<&2, String>}
  {==}

def L.cli.nodes_stale.not_found(n, t, live, h):
  %Equal.sym(Bool, C.Cli.name_in(live, n), False{}, h) : {C.Cli.nodes_stale.keep(_, n, C.Cli.nodes_stale(t, live)) == Con{n, C.Cli.nodes_stale(t, live)} : List<&2, String>}
  {==}

def L.cli.nodes_live.sparse():
  {==}

def L.cli.nodes_live.alone():
  {==}

# String.eq is reflexive (as proofs/oci_auth.bend shows it).

law Cn.bool_refl:
  for a: Bool
  {Bool.cmp(a, a) == EQ{} : Cmp}

def Cn.bool_refl(a):
  match a:
    case False{}:
      {==}
    case True{}:
      {==}

law Cn.word_refl:
  for +n: Nat
  for +a: Word(n)
  {Word.cmp(n, a, a) == EQ{} : Cmp}

def Cn.word_refl(n, a):
  match n:
    case 0n:
      {==}
    case 1n+p:
      match a:
        case WCon{ab, at}:
          %Equal.sym(Cmp, Word.cmp(p, at, at), EQ{}, Cn.word_refl(p, at)) : {Word.cmp.fin(ab, ab, _) == EQ{} : Cmp}
          Cn.bool_refl(ab)

law Cn.u32_refl:
  for a: U32
  {U32.cmp(a, a) == EQ{} : Cmp}

def Cn.u32_refl(a):
  match a:
    case U32{x}:
      Cn.word_refl(32n, x)

law Cn.str_refl:
  for +a: String
  {String.order(a, a) == EQ{} : Cmp}

def Cn.str_refl(a):
  match a:
    case SNil{}:
      {==}
    case SCon{Chr{x}, t}:
      %Equal.sym(Cmp, U32.cmp(x, x), EQ{}, Cn.u32_refl(x)) : {String.order.go(t, t, _) == EQ{} : Cmp}
      Cn.str_refl(t)

law Cn.str_eq_refl:
  for +a: String
  {String.eq(a, a) == True{} : Bool}

def Cn.str_eq_refl(a):
  %Equal.sym(Cmp, String.order(a, a), EQ{}, Cn.str_refl(a)) : {Cmp.is_eq(_) == True{} : Bool}
  {==}

def L.cli.nodes_live.control_plane(g, ws):
  %Equal.sym(Bool, String.eq(g, g), True{}, Cn.str_eq_refl(g)) : {Bool.or(_, C.Cli.name_in(C.Cli.nodes_live.workers(g, ws), g)) == True{} : Bool}
  {==}

def L.cli.node_own.worker():
  {==}

def L.cli.node_own.control_plane():
  {==}

def L.cli.node_own.other_cluster():
  {==}

def L.cli.node_own.no_number():
  {==}

def L.cli.node_own.not_a_number():
  {==}

def L.cli.restore_stale.open():
  {==}

def L.cli.restore_stale.open_early():
  {==}

def L.cli.restore_stale.vm_same():
  {==}

def L.cli.restore_stale.vm_gone():
  {==}

def L.cli.restore_stale.control_plane(open, t, g, ws):
  match open:
    case True{}:
      L.cli.nodes_stale.found(g, t, C.Cli.nodes_live(g, ws), L.cli.nodes_live.control_plane(g, ws))
    case False{}:
      %Equal.sym(List<&2, String>, C.Cli.nodes_stale(Con{g, t}, C.Cli.nodes_live(g, ws)), C.Cli.nodes_stale(t, C.Cli.nodes_live(g, ws)),
        L.cli.nodes_stale.found(g, t, C.Cli.nodes_live(g, ws), L.cli.nodes_live.control_plane(g, ws))) :
        {C.Cli.nodes_own(_, g) == C.Cli.nodes_own(C.Cli.nodes_stale(t, C.Cli.nodes_live(g, ws)), g) : List<&2, String>}
      {==}

def L.cli.removing_node():
  {==}

def L.cli.tls_named.crypto():
  {==}

def L.cli.tls_named.ssl():
  {==}

def L.cli.tls_named.both():
  {==}

def L.cli.tls_named.neither():
  {==}

def L.cli.tls_fix.v2.crypto_mac():
  {==}

def L.cli.tls_fix.v2.both_linux():
  {==}

def L.cli.tls_fix.v2.unset(m):
  {==}

def L.cli.tls_needed.v2.restore():
  {==}

def L.cli.tls_needed.v2.unset(what, m, w):
  {==}

def L.cli.tls_degraded.v2.both():
  {==}

def L.cli.tls_degraded.v2.unset(a, c, l, m, w):
  match a c l:
    case False{} _ _:
      {==}
    case True{} True{} True{}:
      {==}
    case True{} True{} False{}:
      {==}
    case True{} False{} True{}:
      {==}
    case True{} False{} False{}:
      {==}

def L.cli.tls_degraded.v2.loaded(c, l, m, w, s, k):
  {==}

def L.cli.tls_degraded.v2.none_on(a, m, w, s, k):
  match a:
    case True{}:
      {==}
    case False{}:
      {==}
