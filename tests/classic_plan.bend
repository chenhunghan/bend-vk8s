import Base
import ../src/guest/plan.bend as P

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

def main() -> IO(Unit):
  do IO<Unit>:
    T.check("classic daemons have no local node or scheduler",
      String.eq(String.join(T.daemons(P.Plan.classic(P.Plan.default_cfg("demo", 6443, True{}),
        "/var/lib/vk8s-host/host-kubeconfig", "host-ns")), ","),
        "etcd,kube-apiserver,kube-controller-manager,syncer"))
    T.check("classic syncer runs /usr/bin/vk8s-guest syncer",
      String.eq(String.join(T.syncer(P.Plan.classic(P.Plan.default_cfg("demo", 6443, True{}),
        "/var/lib/vk8s-host/host-kubeconfig", "host-ns")), " "),
        "/usr/bin/vk8s-guest syncer --host-kubeconfig /var/lib/vk8s-host/host-kubeconfig --host-namespace host-ns --name demo --service-cidr 10.96.0.0/12"))
