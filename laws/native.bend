import Base
import ../src/standalone/native.bend as N
import ../src/guest/plan.bend as P
import ../src/guest/supervise.bend as S

# Spec for src/standalone/native.bend: native mode on a Linux host
# (docs/GOAL.md section 8, docs/ref/explore-linux-hosts.md Phase 5, N1
# and N2). vcluster standalone keeps its data in /var/lib/vcluster and
# runs as one systemd unit that supervises its children; vk8s runs the
# same cluster layer as the VM's PID 1, relocated under a per-cluster data
# dir, without the machine layer (no mounts, modules, sysctls, network or
# disks), and stops only its own daemons. The values are vk8s design:
# vcluster's standalone runtime is closed source (pkg/pro/standalone.go).

# Proposed: native mode, N1 (the pure plan) and N2 (host-safe shutdown).

# The data dir alone gives every other path.
law native.env_defaults:
  {N.Native.env_of("/d", "", "", "", "", "") == N.Env{"/d", "/d/bin", "/d/share", "/d/etc", "/proc/self/exe", "/d/busybox"} : N.Env}

law native.env_given:
  {N.Native.env_of("/d", "/b", "/s", "/e", "/x", "/y") == N.Env{"/d", "/b", "/s", "/e", "/x", "/y"} : N.Env}

# Every path must be absolute, the data dir not /, and no path may hold a
# space or a quote (the plan puts them in shell words).
law native.env_ok:
  {N.Native.env_ok(N.Native.env_of("/srv/vk8s/demo", "", "", "", "", "")) == True{} : Bool}

law native.env_ok.empty:
  {N.Native.env_ok(N.Native.env_of("", "", "", "", "", "")) == False{} : Bool}

law native.env_ok.root:
  {N.Native.env_ok(N.Native.env_of("/", "", "", "", "", "")) == False{} : Bool}

law native.env_ok.relative:
  {N.Native.env_ok(N.Native.env_of("vk8s/demo", "", "", "", "", "")) == False{} : Bool}

law native.env_ok.space:
  {N.Native.env_ok(N.Native.env_of("/srv/vk8s demo", "", "", "", "", "")) == False{} : Bool}

law native.env_ok.quote:
  {N.Native.env_ok(N.Native.env_of("/srv/vk8s/demo", "", "", "", "", "/it's/busybox")) == False{} : Bool}

# The native cluster's settings: the default CIDRs and domain, the API on
# the host's own 6443 (no port forward), the host's address.
law native.cfg:
  {N.Native.cfg("demo", "192.168.1.5", True{}) ==
    P.Cfg{"demo", "192.168.1.5", "10.96.0.0/12", "10.244.0.0/16", "cluster.local", 6443, True{}} : P.Cfg}

# Relocation rewrites every VM path, wherever it stands in a word: the
# assets (bin), the data dir, the host share, /etc/vk8s, the guest binary
# (the running vk8s itself) and busybox. Other paths stay.
law native.relocate_paths:
  {N.Native.relocate.step(N.Native.env_of("/d", "", "", "", "", ""),
     P.Run{"/var/lib/vcluster/bin/kubeadm",
       [ "init",
         "/var/lib/vcluster/kubeadm.yaml",
         "--cert-dir=/var/lib/vcluster/pki",
         "unix:///var/lib/vcluster/kine.sock",
         "/var/lib/vk8s-host/logs/etcd.log",
         "/etc/vk8s/coredns.yaml",
         "/usr/bin/vk8s-guest",
         "cp /var/lib/vcluster/pki/ca.crt /var/lib/vk8s-host/ca.crt && /bin/busybox true",
         "/etc/kubernetes/manifests" ]}) ==
   P.Run{"/d/bin/kubeadm",
       [ "init",
         "/d/kubeadm.yaml",
         "--cert-dir=/d/pki",
         "unix:///d/kine.sock",
         "/d/share/logs/etcd.log",
         "/d/etc/coredns.yaml",
         "/proc/self/exe",
         "cp /d/pki/ca.crt /d/share/ca.crt && /d/busybox true",
         "/etc/kubernetes/manifests" ]} : P.Step}

# The assets dir is matched before the data dir that holds it.
law native.relocate_bin:
  {N.Native.relocate.step(N.Native.env_of("/d", "/opt/k8s", "", "", "", ""),
     P.Daemon{"etcd", "/var/lib/vcluster/bin/etcd", ["--data-dir=/var/lib/vcluster/etcd"]}) ==
   P.Daemon{"etcd", "/opt/k8s/etcd", ["--data-dir=/d/etcd"]} : P.Step}

# Written files move too, with their contents.
law native.relocate_write:
  {N.Native.relocate.step(N.Native.env_of("/d", "", "", "", "", ""),
     P.Write{"/var/lib/vcluster/kubeadm.yaml", "certificatesDir: /var/lib/vcluster/pki\n"}) ==
   P.Write{"/d/kubeadm.yaml", "certificatesDir: /d/pki\n"} : P.Step}

# Relocation keeps every step.
law native.relocate_length:
  for env: N.Env
  for ss: +List<P.Step>
  {List.length(&2, P.Step, N.Native.relocate(env, ss)) == List.length(&2, P.Step, ss) : Nat}

# Busybox helpers run the host's busybox, never the VM's /bin/busybox.
law native.busybox_path:
  {N.Native.relocate.step(N.Native.env_of("/d", "", "", "", "", "/usr/bin/busybox"),
     P.Plan.bb(["cp", "/var/lib/vcluster/pki/ca.crt", "/var/lib/vcluster/pki/client-ca.crt"])) ==
   P.Run{"/usr/bin/busybox", ["cp", "/d/pki/ca.crt", "/d/pki/client-ca.crt"]} : P.Step}

law native.no_vm_busybox:
  {S.Sup.member(N.Native.progs(N.Native.boot(N.Native.env_of("/d", "", "", "", "", ""), P.Plan.default_cfg("demo", 6443, False{}))),
     "/bin/busybox") == False{} : Bool}

# The VM's machine layer (Plan.boot before the PKI: the base system,
# modules, sysctls, network, disks and the 9p share) is all machine steps.
law native.strips_machine_layer:
  {N.Native.strip(List.append(&2, P.Step, P.Plan.system(),
     List.append(&2, P.Step, [P.Modules{"/etc/vk8s/modules"}],
     List.append(&2, P.Step, P.Plan.sysctls(),
     List.append(&2, P.Step, P.Plan.network(P.Plan.default_cfg("demo", 6443, False{})),
     List.append(&2, P.Step, P.Plan.disks(), [P.Mount{"9p", "share", P.Plan.host_dir(), "trans=virtio,version=9p2000.L"}]))))))
   == [] : +List<P.Step>}

# The native plans hold no machine step, whatever the data dir.
law native.no_machine_steps:
  for env: N.Env
  for c: P.Cfg
  {N.Native.machine_count(N.Native.boot(env, c)) == 0n : Nat}

law native.smoke_no_machine_steps:
  for env: N.Env
  for c: P.Cfg
  {N.Native.machine_count(N.Native.smoke(env, c)) == 0n : Nat}

# The PKI comes first, as in the VM, relocated.
law native.keeps_pki_steps:
  {List.take(&2, P.Step, N.Native.boot(N.Native.env_of("/d", "", "", "", "", ""), P.Plan.default_cfg("demo", 6443, False{})),
     List.length(&2, P.Step, P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{})))) ==
   N.Native.relocate(N.Native.env_of("/d", "", "", "", "", ""), P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{}))) : +List<P.Step>}

# A control plane only (D8 a): the store, the control plane and the join
# server; no containerd and no kubelet on the host.
law native.control_plane_only:
  {N.Native.daemon_names(N.Native.boot(N.Native.env_of("/d", "", "", "", "", ""), P.Plan.default_cfg("demo", 6443, False{}))) ==
    ["kine", "kube-apiserver", "kube-controller-manager", "kube-scheduler", "join-server"] : +List<String>}

law native.control_plane_only.etcd:
  {N.Native.daemon_names(N.Native.boot(N.Native.env_of("/d", "", "", "", "", ""), P.Plan.default_cfg("demo", 6443, True{}))) ==
    ["etcd", "kube-apiserver", "kube-controller-manager", "kube-scheduler", "join-server"] : +List<String>}

# The cluster layer after the control plane starts with what joining
# nodes read (kubeadm upload-config), as Plan.node does after its kubelet.
law native.cluster_layer:
  {List.take(&2, P.Step, N.Native.cluster(P.Plan.default_cfg("demo", 6443, False{})), 1n) ==
    [P.Run{"/var/lib/vcluster/bin/kubeadm", ["init", "phase", "upload-config", "all", "--config", "/var/lib/vcluster/kubeadm.yaml",
      "--kubeconfig", "/var/lib/vcluster/pki/super-admin.conf"]}] : +List<P.Step>}

# The join server runs the running vk8s and is told where the relocated
# PKI is and which endpoint joining nodes reach (the host's address).
law native.join_server:
  {N.Native.relocate.step(N.Native.env_of("/d", "", "", "", "", ""), N.Native.join_server(P.Plan.default_cfg("demo", 6443, False{}))) ==
    P.Daemon{"join-server", "/proc/self/exe",
      [ "join-server",
        "--cert=/d/pki/apiserver.crt",
        "--key=/d/pki/apiserver.key",
        "--ca=/d/pki/ca.crt",
        "--endpoint=10.10.0.2:6443",
        "--api-ca=/d/pki/ca.crt",
        "--api-cert=/d/pki/front-proxy-client.crt",
        "--api-key=/d/pki/front-proxy-client.key" ]} : P.Step}

# The Linux CI smoke plan: PKI, etcd, kube-apiserver, the join server.
law native.smoke_daemons:
  {N.Native.daemon_names(N.Native.smoke(N.Native.env_of("/d", "", "", "", "", ""), P.Plan.default_cfg("demo", 6443, True{}))) ==
    ["etcd", "kube-apiserver", "join-server"] : +List<String>}

law native.dirname:
  {N.Native.dirname("/d/pki/ca.crt") == "/d/pki" : String}

law native.dirname.top:
  {N.Native.dirname("/kubeadm.yaml") == "/" : String}

# Shutdown (N2): the native runner signals only its own running daemons,
# last started first; never 0 (its process group), 1 (init), -1 (every
# process, as the VM's PID 1 does) or another negative pid (a group).
law native.stop_pids:
  {N.Native.stop_pids([S.Svc{"etcd", "/e", [], "/l", 3, 0, 0n}, S.Svc{"a", "/a", [], "/l", 0, 1, 0n},
     S.Svc{"x", "/x", [], "/l", 4294967295, 0, 0n}, S.Svc{"y", "/y", [], "/l", 1, 0, 0n},
     S.Svc{"kubelet", "/k", [], "/l", 7, 0, 0n}]) == [7, 3] : List<&2, U32>}

law native.stop_names:
  {N.Native.stop_names([S.Svc{"etcd", "/e", [], "/l", 3, 0, 0n}, S.Svc{"a", "/a", [], "/l", 0, 1, 0n},
     S.Svc{"x", "/x", [], "/l", 4294967295, 0, 0n}, S.Svc{"y", "/y", [], "/l", 1, 0, 0n},
     S.Svc{"kubelet", "/k", [], "/l", 7, 0, 0n}]) == ["kubelet", "etcd"] : +List<String>}

law native.shutdown_no_global_kill:
  for svcs: +List<S.Svc>
  {N.Native.all_safe(N.Native.stop_pids(svcs)) == True{} : Bool}
