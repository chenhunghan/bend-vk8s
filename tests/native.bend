import Base
import ../src/standalone/native.bend as N
import ../src/guest/plan.bend as P
import ../src/guest/supervise.bend as S

# Tests for src/standalone/native.bend: the native plans, run. No VM path
# may survive relocation, no machine step may stay, and the cluster layer
# (PKI, kubeadm config, control plane, CoreDNS, the join server, the join
# material and the kubeconfig) must be there, under the data dir.

def T.check(+name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name)

def T.env() -> N.Env:
  N.Native.env_of("/srv/vk8s/demo", "", "", "", "", "")

# A step as one line with every field, for searches.
def T.step(s: P.Step) -> String:
  match s:
    case P.Mount{fs, src, dst, opts}:
      "mount " ++ fs ++ " " ++ src ++ " " ++ dst ++ " " ++ opts
    case P.Write{path, text}:
      "write " ++ path ++ " " ++ text
    case P.Run{prog, args}:
      "run " ++ prog ++ " " ++ String.join(args, " ")
    case P.Daemon{n, prog, args}:
      "daemon " ++ n ++ " " ++ prog ++ " " ++ String.join(args, " ")
    case P.Spawn{n, prog, args}:
      "spawn " ++ n ++ " " ++ prog ++ " " ++ String.join(args, " ")
    case P.WaitTcp{host, port, ms}:
      "waittcp " ++ host ++ ":" ++ U32.show(port)
    case P.Stop{names}:
      "stop " ++ String.join(names, " ")
    case P.WaitFile{path, ms}:
      "waitfile " ++ path
    case P.Modules{path}:
      "modules " ++ path
    case P.Log{t}:
      "log " ++ t

def T.steps(ss: +List<P.Step>) -> +List<String>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      Con{T.step(s), T.steps(t)}

def T.text(ss: +List<P.Step>) -> String:
  String.join(T.steps(ss), "\n")

def T.boot(etcd: Bool) -> String:
  T.text(N.Native.boot(T.env(), N.Native.cfg("demo", "192.168.1.5", etcd)))

def T.smoke() -> String:
  T.text(N.Native.smoke(T.env(), N.Native.cfg("demo", "127.0.0.1", True{})))

# No VM path left anywhere in the plan's text.
def T.no_vm_paths(+t: String) -> Bool:
  Bool.not(String.contains(t, "/var/lib/vcluster") || String.contains(t, "/var/lib/vk8s-host") || String.contains(t, "/bin/busybox")
    || String.contains(t, "/etc/vk8s") || String.contains(t, "/usr/bin/vk8s-guest"))

def T.pids(ps: List<&2, U32>) -> String:
  match ps:
    case Nil{}:
      ""
    case Con{p, t}:
      " " ++ U32.show(p) ++ T.pids(t)

def T.svcs() -> +List<S.Svc>:
  [ S.Svc{"etcd", "/e", [], "/l", 11, 0, 0n},
    S.Svc{"kube-apiserver", "/a", [], "/l", 12, 0, 0n},
    S.Svc{"kube-controller-manager", "/c", [], "/l", 0, 2, 0n},
    S.Svc{"join-server", "/j", [], "/l", 14, 0, 0n} ]

def main() -> IO(Unit):
  do IO<Unit>:
    T.check("native boot, kine: no VM path survives relocation", T.no_vm_paths(T.boot(False{})))
    T.check("native boot, etcd: no VM path survives relocation", T.no_vm_paths(T.boot(True{})))
    T.check("native smoke: no VM path survives relocation", T.no_vm_paths(T.smoke()))
    T.check("native boot: no machine step",
      Nat.is_eq(N.Native.machine_count(N.Native.boot(T.env(), N.Native.cfg("demo", "192.168.1.5", False{}))), 0n))
    T.check("native boot: nothing mounted, no module, no sysctl, no network",
      Bool.not(String.contains(T.boot(False{}), "\nmount ") || String.contains(T.boot(False{}), "\nmodules ")
        || String.contains(T.boot(False{}), "/proc/sys") || String.contains(T.boot(False{}), "hostname demo")))
    T.check("the VM boot has machine steps (the classifier sees them)",
      Bool.not(Nat.is_eq(N.Native.machine_count(P.Plan.boot(P.Plan.default_cfg("demo", 6443, False{}))), 0n)))
    T.check("native boot: the kubeadm config under the data dir, its PKI there",
      String.contains(T.boot(False{}), "write /srv/vk8s/demo/kubeadm.yaml ")
        && String.contains(T.boot(False{}), "certificatesDir: /srv/vk8s/demo/pki\n")
        && String.contains(T.boot(False{}), "advertiseAddress: 192.168.1.5\n"))
    T.check("native boot: kubeadm makes the PKI from the assets dir",
      String.contains(T.boot(False{}), "run /srv/vk8s/demo/bin/kubeadm init phase certs all --config /srv/vk8s/demo/kubeadm.yaml"))
    T.check("native boot: busybox helpers run the data dir's busybox",
      String.contains(T.boot(False{}), "run /srv/vk8s/demo/busybox cp /srv/vk8s/demo/pki/ca.crt /srv/vk8s/demo/pki/client-ca.crt"))
    T.check("native boot, kine: kine's socket in the data dir",
      String.contains(T.boot(False{}), "--etcd-servers=unix:///srv/vk8s/demo/kine.sock"))
    T.check("native boot, etcd: etcd's data in the data dir",
      String.contains(T.boot(True{}), "--data-dir=/srv/vk8s/demo/etcd"))
    T.check("native boot: the API server advertises the host's address",
      String.contains(T.boot(False{}), "--advertise-address=192.168.1.5"))
    T.check("native boot: the join server is the running vk8s, with the relocated PKI",
      String.contains(T.boot(False{}), "daemon join-server /proc/self/exe join-server --cert=/srv/vk8s/demo/pki/apiserver.crt"))
    T.check("native boot: joining nodes reach the host's address",
      String.contains(T.boot(False{}), "--endpoint=192.168.1.5:6443"))
    T.check("native boot: CoreDNS written under the data dir and applied",
      String.contains(T.boot(False{}), "write /srv/vk8s/demo/etc/coredns.yaml ")
        && String.contains(T.boot(False{}), "apply -f /srv/vk8s/demo/etc/coredns.yaml"))
    T.check("native boot: flannel applied from the data dir",
      String.contains(T.boot(False{}), "apply -f /srv/vk8s/demo/etc/flannel.yaml"))
    T.check("native boot: upload-config and the bootstrap token for joining nodes",
      String.contains(T.boot(False{}), "init phase upload-config all") && String.contains(T.boot(False{}), "init phase bootstrap-token"))
    T.check("native boot: the join token and the kubeconfig on the share",
      String.contains(T.boot(False{}), "> /srv/vk8s/demo/share/join-token")
        && String.contains(T.boot(False{}), "/srv/vk8s/demo/share/kubeconfig.yaml"))
    T.check("native boot: no containerd and no kubelet on the host",
      Bool.not(String.contains(T.boot(False{}), "daemon containerd") || String.contains(T.boot(False{}), "daemon kubelet")
        || String.contains(T.boot(False{}), "/etc/containerd")))
    T.check("native boot ends with the published kubeconfig",
      String.ends_with(T.boot(False{}), "log vk8s: kubeconfig published"))
    T.check("native smoke: etcd, kube-apiserver, the join server",
      String.eq(String.join(N.Native.daemon_names(N.Native.smoke(T.env(), N.Native.cfg("demo", "127.0.0.1", True{}))), " "),
        "etcd kube-apiserver join-server"))
    T.check("native smoke: waits for the API and the join server, publishes the kubeconfig",
      String.contains(T.smoke(), "waittcp 127.0.0.1:6443\ndaemon join-server ")
        && String.contains(T.smoke(), "\nwaittcp 127.0.0.1:8443\n")
        && String.ends_with(T.smoke(), "log vk8s: kubeconfig published\nlog vk8s: native smoke up"))
    T.check("native stop order: last started first, stopped daemons skipped",
      String.eq(String.join(N.Native.stop_names(T.svcs()), " "), "join-server kube-apiserver etcd"))
    T.check("native stop pids: last started first",
      String.eq(T.pids(N.Native.stop_pids(T.svcs())), " 14 12 11"))
    T.check("native stop pids are all safe", N.Native.all_safe(N.Native.stop_pids(T.svcs())))
    T.check("native stop pids skip -1, 0 and 1",
      List.is_empty(&2, U32, N.Native.stop_pids([S.Svc{"x", "/x", [], "/l", 4294967295, 0, 0n}, S.Svc{"y", "/y", [], "/l", 1, 0, 0n},
        S.Svc{"z", "/z", [], "/l", 2147483648, 0, 0n}])))
    T.check("dirname", String.eq(N.Native.dirname("/srv/vk8s/demo/pki/ca.crt"), "/srv/vk8s/demo/pki"))
