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
    T.check("native: kubectl's cache is in the data dir, not the user's ~/.kube/cache",
      String.eq(N.Native.cache_dir(T.env()), "/srv/vk8s/demo/kube-cache"))
    T.check("native boot goes on while every step succeeds and no SIGTERM came", N.Native.go_on(True{}, 0))
    T.check("native boot stops at a SIGTERM or SIGINT", Bool.not(N.Native.go_on(True{}, 1)) && Bool.not(N.Native.go_on(True{}, 3)))
    T.check("native boot stops at a failed step", Bool.not(N.Native.go_on(False{}, 0)))
    T.check("native run: a command that did not exit in time is killed and reaped",
      String.eq(T.pids(N.Native.orphan(None{}, 42)), " 42"))
    T.check("native run: a command that exited is left alone",
      List.is_empty(&2, U32, N.Native.orphan(Some{0}, 42)) && List.is_empty(&2, U32, N.Native.orphan(Some{1}, 42)))
    T.check("native run: a command that never started kills nothing",
      List.is_empty(&2, U32, N.Native.orphan(None{}, 0)) && List.is_empty(&2, U32, N.Native.orphan(None{}, 4294967295)))
    T.check("native env v2: a plain data dir is accepted", N.Native.env_ok.v2(T.env()))
    T.check("native env v2: $ in a path is refused (rm -rf /tmp/demo$1/... would expand)",
      Bool.not(N.Native.env_ok.v2(N.Native.env_of("/tmp/demo$1", "", "", "", "", ""))))
    T.check("native env v2: a backtick, ; | & * or a newline is refused",
      Bool.not(N.Native.env_ok.v2(N.Native.env_of("/tmp/`id`", "", "", "", "", "")))
        && Bool.not(N.Native.env_ok.v2(N.Native.env_of("/tmp/a;b", "", "", "", "", "")))
        && Bool.not(N.Native.env_ok.v2(N.Native.env_of("/tmp/a", "/tmp/a|b", "", "", "", "")))
        && Bool.not(N.Native.env_ok.v2(N.Native.env_of("/tmp/a", "", "/tmp/a&", "", "", "")))
        && Bool.not(N.Native.env_ok.v2(N.Native.env_of("/tmp/a", "", "", "/tmp/*", "", "")))
        && Bool.not(N.Native.env_ok.v2(N.Native.env_of("/tmp/a", "", "", "", "/tmp/a\nb", ""))))
    T.check("native env v2: what env_ok refuses stays refused",
      Bool.not(N.Native.env_ok.v2(N.Native.env_of("", "", "", "", "", "")))
        && Bool.not(N.Native.env_ok.v2(N.Native.env_of("/", "", "", "", "", "")))
        && Bool.not(N.Native.env_ok.v2(N.Native.env_of("vk8s/demo", "", "", "", "", "")))
        && Bool.not(N.Native.env_ok.v2(N.Native.env_of("/srv/vk8s demo", "", "", "", "", "")))
        && Bool.not(N.Native.env_ok.v2(N.Native.env_of("/srv/vk8s/demo", "", "", "", "", "/it's/busybox"))))
    T.check("native env v2: letters, digits and / . _ - + @ , : = are accepted",
      N.Native.env_ok.v2(N.Native.env_of("/home/Ann_B-2/.vk8s/a+b@c,d:e=f", "", "", "", "", "")))
    T.check("native: the data dir and the share are made first",
      String.eq(String.join(N.Native.private_mkdir(T.env()), " "), "mkdir -p /srv/vk8s/demo /srv/vk8s/demo/share"))
    T.check("native: the data dir and the share are private (0700)",
      String.eq(String.join(N.Native.private_chmod(T.env()), " "), "chmod 0700 /srv/vk8s/demo /srv/vk8s/demo/share"))
    T.check("native boot: the kubeconfig is written under umask 077",
      String.contains(T.text(N.Native.lock(T.env(), N.Native.boot(T.env(), N.Native.cfg("demo", "192.168.1.5", False{})))),
        "sh -c umask 077; sed "))
    T.check("native boot: the kubeconfig goes to the share's owner before it is moved in place",
      String.contains(T.text(N.Native.lock(T.env(), N.Native.boot(T.env(), N.Native.cfg("demo", "192.168.1.5", False{})))),
        " > /srv/vk8s/demo/share/kubeconfig.yaml.tmp && chown \"$(stat -c %u:%g /srv/vk8s/demo/share)\" /srv/vk8s/demo/share/kubeconfig.yaml.tmp && mv /srv/vk8s/demo/share/kubeconfig.yaml.tmp /srv/vk8s/demo/share/kubeconfig.yaml"))
    T.check("native smoke: the kubeconfig is written under umask 077",
      String.contains(T.text(N.Native.lock(T.env(), N.Native.smoke(T.env(), N.Native.cfg("demo", "127.0.0.1", True{})))),
        "sh -c umask 077; sed "))
    T.check("native boot: lock changes only the publish step",
      Nat.is_eq(List.length(&2, P.Step, N.Native.lock(T.env(), N.Native.boot(T.env(), N.Native.cfg("demo", "192.168.1.5", False{})))),
        List.length(&2, P.Step, N.Native.boot(T.env(), N.Native.cfg("demo", "192.168.1.5", False{}))))
        && String.eq(T.text(N.Native.lock(T.env(), [P.Plan.bb(["sh", "-c", "a > b && mv b c"])])), "run /bin/busybox sh -c a > b && mv b c"))
    T.check("native shutdown: a reaped daemon's pid is not signalled (the host may have reused it)",
      List.is_empty(&2, U32, N.Native.signal_now(S.Sup.exited(T.svcs(), 11, 5n), 11)))
    T.check("native shutdown: a running daemon's pid is signalled", String.eq(T.pids(N.Native.signal_now(T.svcs(), 12)), " 12"))
    T.check("native shutdown: a pid the table does not hold is not signalled", List.is_empty(&2, U32, N.Native.signal_now(T.svcs(), 99)))
    T.check("native shutdown: a stopped daemon (pid 0) is not signalled", List.is_empty(&2, U32, N.Native.signal_now(T.svcs(), 0)))
