import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/guest/plan.bend as P
import ../src/guest/values.bend as VL
import ../src/config/vcluster.bend as V

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

# The parsed conformance profile's virtual scheduler.
def T.vsched() -> J.Json:
  V.Config.value("controlPlane:\n  advanced:\n    virtualScheduler:\n      enabled: true\nsync:\n  fromHost:\n    nodes:\n      enabled: true\n", [])

def T.args_of.if(hit: Bool, +args: +List<String>, +rest: +List<String>) -> +List<String>:
  match hit:
    case True{}:
      args
    case False{}:
      rest

# The arguments of the named daemon.
def T.args_of(+want: String, ss: +List<P.Step>) -> +List<String>:
  match ss:
    case Nil{}:
      []
    case Con{P.Daemon{name, prog, args}, rest}:
      T.args_of.if(String.eq(name, want), args, T.args_of(want, rest))
    case Con{step, rest}:
      T.args_of(want, rest)

# vcluster pkg/k8s/k8s.go's IsVirtualSchedulerEnabled controller manager flags.
def T.vsched_cm(+s: String) -> Bool:
  Bool.and(String.contains(s, "--controllers=*,-nodeipam,-persistentvolume-binder,-attachdetach,-persistentvolume-expander,-cloud-node-lifecycle,-ttl"),
    Bool.and(String.contains(s, "--node-monitor-grace-period=1h"), String.contains(s, "--node-monitor-period=1h")))

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
    # vcluster's conformance profile (controlPlane.advanced.virtualScheduler):
    # kube-scheduler runs after the controller manager (pkg/k8s/k8s.go), and
    # the syncer reads the share's vcluster.yaml.
    T.check("classic plan with the virtual scheduler runs kube-scheduler",
      String.eq(String.join(T.daemons(VL.Values.classic(T.vsched(), P.Plan.default_cfg("demo", 6443, True{}), True{},
        P.Plan.classic(P.Plan.default_cfg("demo", 6443, True{}), "/var/lib/vk8s-host/host-kubeconfig", "host-ns"))), ","),
        "etcd,kube-apiserver,kube-controller-manager,kube-scheduler,syncer"))
    T.check("classic syncer reads the share's vcluster.yaml",
      String.eq(String.join(T.syncer(VL.Values.classic(T.vsched(), P.Plan.default_cfg("demo", 6443, True{}), True{},
        P.Plan.classic(P.Plan.default_cfg("demo", 6443, True{}), "/var/lib/vk8s-host/host-kubeconfig", "host-ns"))), " "),
        "/usr/bin/vk8s-guest syncer --host-kubeconfig /var/lib/vk8s-host/host-kubeconfig --host-namespace host-ns --name demo --service-cidr 10.96.0.0/12 --config /var/lib/vk8s-host/vcluster.yaml"))
    T.check("classic plan without a vcluster.yaml is unchanged",
      String.eq(String.join(T.daemons(VL.Values.classic(V.Config.defaults(), P.Plan.default_cfg("demo", 6443, True{}), False{},
        P.Plan.classic(P.Plan.default_cfg("demo", 6443, True{}), "/var/lib/vk8s-host/host-kubeconfig", "host-ns"))), ","),
        "etcd,kube-apiserver,kube-controller-manager,syncer"))
    T.check("virtual-scheduler controller manager: node lifecycle on, 1h monitor periods",
      T.vsched_cm(String.join(T.args_of("kube-controller-manager", VL.Values.classic(T.vsched(), P.Plan.default_cfg("demo", 6443, True{}), True{},
        P.Plan.classic(P.Plan.default_cfg("demo", 6443, True{}), "/var/lib/vk8s-host/host-kubeconfig", "host-ns"))), " ")))
