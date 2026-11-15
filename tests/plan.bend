import Base
import ../src/guest/plan.bend as P

# The control-plane command lines of src/guest/plan.bend, run: vcluster's
# base flags (pkg/k8s/k8s.go) merged with vk8s's apiserver overrides.

def T.check(+name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name)

def T.same(xs: +List<String>, ys: +List<String>) -> Bool:
  String.eq(String.join(xs, "\n"), String.join(ys, "\n"))

def T.pki(+f: String) -> String:
  "/var/lib/vcluster/pki/" ++ f

# The apiserver's flags after the merge; etcd: the store's flags.
def T.apiserver(store: +List<String>) -> +List<String>:
  List.append(&2, String,
    [ "--service-cluster-ip-range=10.96.0.0/12",
      "--allow-privileged=true",
      "--authorization-mode=Node,RBAC",
      "--client-ca-file=" ++ T.pki("client-ca.crt"),
      "--enable-bootstrap-token-auth=true" ],
  List.append(&2, String, store,
    [ "--proxy-client-cert-file=" ++ T.pki("front-proxy-client.crt"),
      "--proxy-client-key-file=" ++ T.pki("front-proxy-client.key"),
      "--requestheader-allowed-names=front-proxy-client",
      "--requestheader-client-ca-file=" ++ T.pki("front-proxy-ca.crt"),
      "--requestheader-extra-headers-prefix=X-Remote-Extra-",
      "--requestheader-group-headers=X-Remote-Group",
      "--requestheader-username-headers=X-Remote-User",
      "--secure-port=6443",
      "--service-account-issuer=https://kubernetes.default.svc.cluster.local",
      "--service-account-key-file=" ++ T.pki("sa.pub"),
      "--service-account-signing-key-file=" ++ T.pki("sa.key"),
      "--tls-cert-file=" ++ T.pki("apiserver.crt"),
      "--tls-private-key-file=" ++ T.pki("apiserver.key"),
      "--profiling=false",
      "--kubelet-client-certificate=" ++ T.pki("apiserver-kubelet-client.crt"),
      "--kubelet-client-key=" ++ T.pki("apiserver-kubelet-client.key"),
      "--enable-admission-plugins=NodeRestriction",
      "--kubelet-preferred-address-types=InternalDNS,InternalIP,Hostname,ExternalDNS,ExternalIP",
      "--bind-address=0.0.0.0",
      "--advertise-address=10.10.0.2",
      "--endpoint-reconciler-type=lease" ]))

def T.cpu_is(c: P.Cpu, +busy: U32, +total: U32) -> Bool:
  match c:
    case P.Cpu{b, t}:
      Bool.and(U32.is_eq(b, busy), U32.is_eq(t, total))

# /proc/stat as the kernel's Documentation/filesystems/proc.rst shows it.
def T.proc_stat() -> String:
  "cpu  237902850 368826709 106375398 1873517540 1135548 0 14507935 0 0 0\n"
  ++ "cpu0 60045249 91891769 26331539 468411416 495718 0 5739640 0 0 0\n"
  ++ "cpu1 59944880 92179404 26614236 468362637 199929 0 3009183 0 0 0\n"
  ++ "intr 1462898 0 0 0 0 0 0 0 0 0\n"
  ++ "ctxt 1990473\nbtime 1062191376\nprocesses 2915\nprocs_running 1\nprocs_blocked 0\n"

# A sample /proc/meminfo of a 2 GiB guest.
def T.meminfo() -> String:
  "MemTotal:        2014604 kB\nMemFree:          912344 kB\nMemAvailable:    1489220 kB\n"
  ++ "Buffers:           10240 kB\nCached:           702516 kB\nSwapCached:            0 kB\n"
  ++ "Active:           301204 kB\nInactive:         573900 kB\n"
  ++ "Active(anon):     118300 kB\nInactive(anon):   212400 kB\n"
  ++ "Active(file):     182904 kB\nInactive(file):   361500 kB\n"
  ++ "Unevictable:           0 kB\nShmem:            211900 kB\n"

def main() -> IO(Unit):
  do IO<Unit>:
    T.check("add_sans on the real kubeadm config puts the SAN first",
      String.contains(P.Plan.add_sans(P.Plan.kubeadm_config(P.Plan.classic_cfg("vc", 12000, False{}, "10.96.0.0/12")), ["10.100.0.5"]),
        "certSANs:\n  - 10.100.0.5\n  - 127.0.0.1\n"))
    T.check("add_sans with no SANs leaves the real kubeadm config alone",
      String.eq(P.Plan.add_sans(P.Plan.kubeadm_config(P.Plan.default_cfg("demo", 12000, False{})), []), P.Plan.kubeadm_config(P.Plan.default_cfg("demo", 12000, False{}))))
    T.check("apiserver flags, kine",
      T.same(P.Plan.apiserver_args(P.Plan.default_cfg("demo", 6443, False{})),
        T.apiserver(["--etcd-servers=unix:///var/lib/vcluster/kine.sock"])))
    T.check("apiserver flags, etcd",
      T.same(P.Plan.apiserver_args(P.Plan.default_cfg("demo", 6443, True{})),
        T.apiserver([ "--etcd-servers=https://127.0.0.1:2379",
          "--etcd-cafile=" ++ T.pki("etcd/ca.crt"),
          "--etcd-certfile=" ++ T.pki("apiserver-etcd-client.crt"),
          "--etcd-keyfile=" ++ T.pki("apiserver-etcd-client.key") ])))
    T.check("controller-manager flags end with the private-nodes flags",
      T.same(List.drop(&2, String, P.Plan.controller_manager_args(P.Plan.default_cfg("demo", 6443, False{})), 12n),
        [ "--cluster-signing-cert-file=" ++ T.pki("server-ca.crt"),
          "--cluster-signing-key-file=" ++ T.pki("server-ca.key"),
          "--controllers=*,bootstrapsigner,tokencleaner",
          "--allocate-node-cidrs=true",
          "--cluster-cidr=10.244.0.0/16",
          "--cloud-provider=external" ]))
    T.check("scheduler flags",
      T.same(P.Plan.scheduler_args(),
        [ "--authentication-kubeconfig=" ++ T.pki("scheduler.conf"),
          "--authorization-kubeconfig=" ++ T.pki("scheduler.conf"),
          "--bind-address=127.0.0.1",
          "--kubeconfig=" ++ T.pki("scheduler.conf"),
          "--leader-elect=true" ]))
    T.check("kine flags",
      T.same(P.Plan.kine_args(),
        [ "--endpoint=sqlite:///var/lib/vcluster/state.db?_journal=WAL&cache=shared&_busy_timeout=30000&_txlock=immediate",
          "--metrics-bind-address=127.0.0.1:2381",
          "--listen-address=unix:///var/lib/vcluster/kine.sock" ]))
    T.check("sh_quote empty", String.eq(P.Plan.sh_quote(""), "''"))
    T.check("sh_quote plain", String.eq(P.Plan.sh_quote("abc"), "'abc'"))
    T.check("sh_quote single quote", String.eq(P.Plan.sh_quote("it's"), "'it'\\''s'"))
    T.check("cpu sample: the aggregate line of proc.rst's /proc/stat, last 8 digits",
      T.cpu_is(P.Plan.cpu(T.proc_stat()), 28748440, 2265980))
    T.check("cpu sample: no /proc/stat reads as zero", T.cpu_is(P.Plan.cpu(""), 0, 0))
    T.check("idle: 100 busy of 6000 ticks", P.Plan.idle(P.Cpu{1000, 50000}, P.Cpu{1100, 56000}))
    T.check("not idle: 2000 busy of 6000 ticks", Bool.not(P.Plan.idle(P.Cpu{1000, 50000}, P.Cpu{3000, 56000})))
    T.check("idle across the 10^8 wrap", P.Plan.idle(P.Cpu{99999900, 99999000}, P.Cpu{0, 5000}))
    T.check("reclaim: file cache above 64 MiB of a whole meminfo",
      U32.is_eq(P.Plan.reclaim_kb(T.meminfo()), 478868))
    T.check("give-back when idle writes memory.reclaim",
      Nat.is_eq(List.length(&2, P.Step, P.Plan.give_back(P.Cpu{1000, 50000}, P.Cpu{1100, 56000}, T.meminfo())), 1n))
    T.check("no give-back when busy",
      Nat.is_eq(List.length(&2, P.Step, P.Plan.give_back(P.Cpu{1000, 50000}, P.Cpu{3000, 56000}, T.meminfo())), 0n))
