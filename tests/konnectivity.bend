import Base
import ../src/guest/plan.bend as P
import ../src/cli/cli.bend as C

# Classic mode with the host Services' IPs (konnectivity): the server runs
# beside the API server, the API server's egress goes through it, the
# syncer advertises the vcluster Service's IP as its nodes' kubelet
# address, and the agent dials the konnectivity Service's IP.

def T.check(+name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name)

# Return the named daemons in boot order; this also detects unexpected
# additions such as a local scheduler or any worker process.
def T.daemons(ss: +List<P.Step>) -> +List<String>:
  match ss:
    case Nil{}:
      []
    case Con{P.Daemon{name, prog, args}, rest}:
      name <> T.daemons(rest)
    case Con{step, rest}:
      T.daemons(rest)

# The syncer daemon's command line: the dynamic glibc build of the guest
# program (/usr/bin/vk8s-guest), since bend-kube-runtime loads OpenSSL
# with dlopen and /sbin/vk8s-init is static musl.
def T.syncer.if(hit: Bool, +prog: String, +args: +List<String>, +rest: +List<String>) -> +List<String>:
  match hit:
    case True{}:
      prog <> args
    case False{}:
      rest

def T.syncer(ss: +List<P.Step>) -> +List<String>:
  match ss:
    case Nil{}:
      []
    case Con{P.Daemon{name, prog, args}, rest}:
      T.syncer.if(String.eq(name, "syncer"), prog, args, T.syncer(rest))
    case Con{step, rest}:
      T.syncer(rest)

def T.has(+x: String, xs: +List<String>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{y, t}:
      Bool.or(String.eq(x, y), T.has(x, t))

def T.writes.if(hit: Bool, +text: String, +rest: String) -> String:
  match hit:
    case True{}:
      text
    case False{}:
      rest

def T.writes(+path: String, ss: +List<P.Step>) -> String:
  match ss:
    case Nil{}:
      ""
    case Con{P.Write{p, text}, rest}:
      +path = {path : String}
      T.writes.if(String.eq(p, path), text, T.writes(path, rest))
    case Con{step, rest}:
      T.writes(path, rest)

def T.konn() -> +List<P.Step>:
  P.Plan.classic_x(P.Plan.default_cfg("demo", 6443, True{}), "/var/lib/vk8s-host/host-kubeconfig", "host-ns", ["10.100.0.5", "10.100.0.9"])

def main() -> IO(Unit):
  do IO<Unit>:
    T.check("classic with host Services runs konnectivity-server before the API server",
      String.eq(String.join(T.daemons(T.konn()), ","), "etcd,konnectivity-server,kube-apiserver,kube-controller-manager,syncer"))
    T.check("classic syncer advertises the vcluster Service IP for kubelets",
      String.eq(String.join(T.syncer(T.konn()), " "),
        "/usr/bin/vk8s-guest syncer --host-kubeconfig /var/lib/vk8s-host/host-kubeconfig --host-namespace host-ns --name demo --service-cidr 10.96.0.0/12 --kubelet-ip 10.100.0.5"))
    T.check("the egress selector config is written",
      String.eq(T.writes(P.Plan.egress_config_path(), T.konn()), P.Plan.egress_config()))
    T.check("the agent dials the konnectivity Service IP",
      String.contains(T.writes("/etc/vk8s/konnectivity-agent.yaml", T.konn()), "--proxy-server-host=10.100.0.9\n"))
    T.check("both host Service IPs join the API server's SANs",
      String.contains(T.writes("/var/lib/vcluster/kubeadm.yaml", T.konn()), "certSANs:\n  - 10.100.0.5\n  - 10.100.0.9\n"))
    T.check("the classic VM forwards konnectivity and the fake kubelet",
      T.has("127.0.0.1:10001:6443,127.0.0.1:14001:8132,127.0.0.1:17001:10250",
        C.Cli.vmm_flags_x("/d", "/a", "vc", 10001, 2, 2048, False{}, " VK8S_MODE=classic VK8S_HOST_NAMESPACE=ns")))
    T.check("a standalone VM forwards the API alone",
      T.has("127.0.0.1:10001:6443", C.Cli.vmm_flags_x("/d", "/a", "vc", 10001, 2, 2048, False{}, "")))
