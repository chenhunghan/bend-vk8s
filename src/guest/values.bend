import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../lib/args.bend as A
import ./plan.bend as P
import ../config/vcluster.bend as V

# What vk8s takes from a vcluster.yaml (src/config/vcluster.bend parses
# and defaults it): the backing store, and each control plane component's
# extraArgs (controlPlane.distro.k8s.<component>.extraArgs, vcluster's
# --flag=value strings, merged over vk8s's flags as vcluster merges them).
# Settings vk8s cannot honor yet are refused by name, never ignored.

def Values.at.go(ks: List<&2, String>, j: J.Json) -> J.Json:
  match ks:
    case Nil{}:
      j
    case Con{+k, t}:
      Values.at.go(t, J.Json.get(j, k))

def Values.at(j: J.Json, ks: List<&2, String>) -> J.Json:
  Values.at.go(ks, j)

def Values.strs(xs: List<&2, J.Json>) -> +List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      Con{J.Json.str_or(x, ""), Values.strs(t)}

def Values.bool(j: J.Json) -> Bool:
  match j:
    case J.JBool{b}:
      b
    case _:
      False{}

def Values.extra_args(c: J.Json, +component: String) -> +List<String>:
  Values.strs(J.Json.items(Values.at(c, ["controlPlane", "distro", "k8s", component, "extraArgs"])))

# controlPlane.backingStore: embedded etcd wins when both are enabled.
def Values.etcd(c: J.Json) -> Bool:
  Values.bool(Values.at(c, ["controlPlane", "backingStore", "etcd", "embedded", "enabled"]))

def Values.version(c: J.Json) -> String:
  J.Json.str_or(Values.at(c, ["controlPlane", "distro", "k8s", "version"]), "")

def Values.check(+ok: Bool, +msg: String, rest: String) -> String:
  match ok:
    case True{}:
      rest
    case False{}:
      msg

# "" when vk8s can run this configuration; otherwise why not.
def Values.unsupported(+c: J.Json) -> String:
  +ver : String = Values.version(c)
  +svc : String = J.Json.str_or(Values.at(c, ["networking", "serviceCIDR"]), "")
  +pod : String = J.Json.str_or(Values.at(c, ["networking", "podCIDR"]), "")
  +dom : String = J.Json.str_or(Values.at(c, ["networking", "advanced", "clusterDomain"]), "")
  +rep : String = J.Json.show(Values.at(c, ["controlPlane", "coredns", "deployment", "replicas"]))
  Values.check(String.is_empty(ver) || String.eq(ver, "v1.36.6"),
    "vk8s ships Kubernetes v1.36.6; controlPlane.distro.k8s.version " ++ ver ++ " is not available",
  Values.check(String.is_empty(svc) || String.eq(svc, "10.96.0.0/12"), "vk8s does not support networking.serviceCIDR other than 10.96.0.0/12 yet",
  Values.check(String.eq(pod, "10.244.0.0/16"), "vk8s does not support networking.podCIDR other than 10.244.0.0/16 yet",
  Values.check(String.eq(dom, "cluster.local"), "vk8s does not support networking.advanced.clusterDomain other than cluster.local yet",
  Values.check(String.eq(rep, "1"), "vk8s does not support controlPlane.coredns.deployment.replicas other than 1 yet", "")))))

def Values.component.go(api: Bool, cm: Bool, sch: Bool) -> String:
  match api cm sch:
    case True{} _ _:
      "apiServer"
    case False{} True{} _:
      "controllerManager"
    case False{} False{} True{}:
      "scheduler"
    case _ _ _:
      ""

def Values.component(+name: String) -> String:
  Values.component.go(String.eq(name, "kube-apiserver"), String.eq(name, "kube-controller-manager"), String.eq(name, "kube-scheduler"))

def Values.step.args(none: Bool, +c: J.Json, +comp: String, +args: +List<String>) -> +List<String>:
  match none:
    case True{}:
      args
    case False{}:
      A.Args.merge(args, Values.extra_args(c, comp))

def Values.step.go(+comp: String, +c: J.Json, +name: String, +prog: String, +args: +List<String>) -> P.Step:
  P.Daemon{name, prog, Values.step.args(String.is_empty(comp), c, comp, args)}

def Values.step(+c: J.Json, s: P.Step) -> P.Step:
  match s:
    case P.Daemon{+name, +prog, +args}:
      Values.step.go(Values.component(name), c, name, prog, args)
    case other:
      other

# The boot plan with the configuration's extraArgs merged into the API
# server, controller manager and scheduler (later flags win).
def Values.with_extra(ss: +List<P.Step>, +c: J.Json) -> +List<P.Step>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      Con{Values.step(c, s), Values.with_extra(t, c)}

def Values.classic.sched(on: Bool, +c: P.Cfg, ss: +List<P.Step>) -> +List<P.Step>:
  match on:
    case True{}:
      P.Plan.virtual_scheduler(c, ss)
    case False{}:
      ss

def Values.classic.file(file: Bool, ss: +List<P.Step>) -> +List<P.Step>:
  match file:
    case True{}:
      P.Plan.syncer_config(P.Plan.host_dir() ++ "/vcluster.yaml", ss)
    case False{}:
      ss

# A classic plan with the share's vcluster.yaml (file: it exists): the
# syncer reads it (--config), and vcluster's virtual scheduler
# (IsVirtualSchedulerEnabled) adds kube-scheduler and the controller
# manager's virtual-scheduler flags.
def Values.classic(+cfg: J.Json, +c: P.Cfg, file: Bool, ss: +List<P.Step>) -> +List<P.Step>:
  Values.classic.sched(V.Config.virtual_scheduler(cfg), c, Values.classic.file(file, ss))

# The boot plan up to and including the mount of the host share, and the
# rest: PID 1 reads the share's vcluster.yaml in between.
type Split is Data:
  Split{pre: +List<P.Step>, post: +List<P.Step>}

def Values.is_share(s: P.Step) -> Bool:
  match s:
    case P.Mount{fs, src, +dst, o}:
      String.eq(dst, P.Plan.host_dir())
    case _:
      False{}

def Values.split.go(hit: Bool, +s: P.Step, +t: +List<P.Step>, rest: Split) -> Split:
  match hit:
    case True{}:
      Split{[s], t}
    case False{}:
      match rest:
        case Split{a, b}:
          Split{Con{s, a}, b}

def Values.split(ss: +List<P.Step>) -> Split:
  match ss:
    case Nil{}:
      Split{Nil{}, Nil{}}
    case Con{+s, +t}:
      Values.split.go(Values.is_share(s), s, t, Values.split(t))
