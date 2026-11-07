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

def main() -> IO(Unit):
  do IO<Unit>:
    T.check("classic daemons have no local node or scheduler",
      String.eq(String.join(T.daemons(P.Plan.classic(P.Plan.default_cfg("demo", 6443, True{}),
        "/var/lib/vk8s-host/host-kubeconfig", "host-ns")), ","),
        "etcd,kube-apiserver,kube-controller-manager,syncer"))
