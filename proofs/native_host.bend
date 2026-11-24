import Base
import ../laws/native_host.bend as L
import ../src/standalone/native_host.bend as NH

# Proofs of laws/native_host.bend: `def L.<law>` for each law. Every law
# is concrete and computes.

def L.native.unit_name():
  {==}

def L.native.unit_path():
  {==}

def L.native.data_dir():
  {==}

def L.native.unit_text():
  {==}

def L.native.unit_restart():
  {==}

def L.native.unit_kill_mode():
  {==}

def L.native.unit_delegate():
  {==}

def L.native.unit_exec():
  {==}

def L.native.install_cmds():
  {==}

def L.native.show():
  {==}

def L.native.show_quotes():
  {==}

def L.native.prepare_cmds():
  {==}

def L.native.flannel():
  {==}

def L.native.preflight_ok():
  {==}

def L.native.preflight_commands():
  {==}

def L.native.preflight_host():
  {==}

def L.native.sysctls_control_plane():
  {==}

def L.native.ports():
  {==}

def L.native.wait_ports():
  {==}

def L.native.join_server_port():
  {==}

def L.native.no_fixed_cm_port():
  {==}

def L.native.no_fixed_scheduler_port():
  {==}

def L.native.kube_apiserver_args_kept():
  {==}

def L.native.node_paths():
  {==}

def L.native.kubelet_text():
  {==}

def L.native.cfg_port():
  {==}

def L.native.env_text():
  {==}

def L.native.delete_leaves_nothing():
  {==}

def L.native.delete_leaves_nothing.control_plane():
  {==}

def L.native.delete_stops_first():
  {==}

def L.native.leftover():
  {==}

def L.native.mounts_under():
  {==}

def L.native.umount_cmds():
  {==}

def L.native.ipt_clean():
  {==}

def L.native.ipt_clean_none():
  {==}

def L.native.route_src():
  {==}

def L.native.ip_ok():
  {==}

def L.native.ip_ok.not_an_address():
  {==}

def L.native.runsc_text():
  {==}

def L.native.extra_runsc():
  {==}

def L.native.runsc_root():
  {==}

def L.native.proxy_sysctls():
  {==}

def L.native.proxy_sysctls_no_ipv6():
  {==}

def L.native.proxy_sysctls_set():
  {==}

def L.native.proxy_sysctls_off():
  {==}

def L.native.proxy_sysctls_control_plane():
  {==}

def L.native.preflight_proxy():
  {==}

def L.native.extra_containerd_images():
  {==}

def L.native.cgroup_root():
  {==}

def L.native.cgroup_dir():
  {==}

def L.native.env_cgroup():
  {==}

def L.native.kubelet_cgroup_root():
  {==}

def L.native.reset_v2_own_cgroup():
  {==}

def L.native.reset_v2_script():
  {==}

def L.native.reset_v2_step():
  {==}

def L.native.foreign_kubelets():
  {==}

def L.native.vk8s_kubelets():
  {==}

def L.native.no_kubelets():
  {==}

def L.native.kill_dir():
  {==}

def L.native.kill_dir_shared():
  {==}

def L.native.kill_dir_legacy():
  {==}

def L.native.kill_dir_legacy_shared():
  {==}

def L.native.ipt_delete():
  {==}

def L.native.ipt_delete_cni():
  {==}

def L.native.ipt_delete_filter():
  {==}

def L.native.ipt_delete_none():
  {==}

def L.native.ipt_delete_by_name():
  {==}

def L.native.hashed_ok():
  {==}

def L.native.hashed_short():
  {==}

def L.native.hashed_not_base32():
  {==}

def L.native.ipt_restore_cmd():
  {==}

def L.native.root_ctl():
  {==}

def L.native.reset_v3_script(d, n):
  {==}

def L.native.assets_root():
  {==}

def L.native.shared_bin():
  {==}

def L.native.sum_cmd():
  {==}

def L.native.asset_key():
  {==}

def L.native.asset_key_paths():
  {==}

def L.native.asset_key_sets():
  {==}

def L.native.unpack_cmds():
  {==}

def L.native.publish_cmd():
  {==}

def L.native.unstage_cmd():
  {==}

def L.native.has_cmd():
  {==}

def L.native.prepare_cmds_v2():
  {==}

def L.native.link_cmd():
  {==}

def L.native.users_cmd():
  {==}

def L.native.shared_key():
  {==}

def L.native.shared_key_other():
  {==}

def L.native.shared_key_dots():
  {==}

def L.native.shared_key_none():
  {==}

def L.native.release_last():
  {==}

def L.native.release_kept():
  {==}

def L.native.release_before_v2():
  {==}

def L.native.delete_leaves_nothing_v2():
  {==}

def L.native.sets.v2():
  {==}
