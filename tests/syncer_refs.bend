import Base
import ../host/syncer.bend as S
import ../src/sync/classic.bend as CL
import ../src/translate/services.bend as SV
import ../src/translate/pods.bend as P
import bend-kube-runtime@0.8.1.0/src/json.bend as J
import bend-kube-runtime@0.8.1.0/src/watcher.bend as W
import bend-kube-runtime@0.8.1.0/src/store.bend as St

# The syncer's ConfigMap and Secret reference index. vcluster queues a
# ConfigMap or Secret only when a reference to it is added or removed
# (pkg/mappings/store/store.go: AddReference and DeleteReference dispatch
# to the kind's watches, which configmaps/to_host_syncer.go
# ModifyController registers), and decides whether it is used from the
# store's references (isConfigMapUsed: ReferencesTo), not from every pod.

def check(name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name)

def has(ks: List<&2, String>, +k: String) -> Bool:
  match ks:
    case Nil{}:
      False{}
    case Con{x, t}:
      Bool.or(String.eq(x, k), has(t, k))

def jr(r: Result<&2, &2, String, J.Json>) -> J.Json:
  match r:
    case Done{x}:
      x
    case Fail{e}:
      J.JNull{}

# A virtual pod in namespace load that mounts ConfigMap cm, with a phase.
def pod(+cm: String, +phase: String) -> J.Json:
  jr(J.Json.parse(P.Pods.subst("{`metadata`:{`name`:`p`,`namespace`:`load`},`spec`:{`containers`:[{`name`:`c`}],"
    ++ "`volumes`:[{`name`:`v`,`configMap`:{`name`:`" ++ cm ++ "`}}]},`status`:{`phase`:`" ++ phase ++ "`}}", '`', '"')))

def cfg() -> SV.Cfg:
  SV.Cfg{"load", "vcluster-load", "vcluster"}

def first(+x: J.Json) -> S.Folded:
  S.Sync.fold([W.OApply{x}], 8, cfg(), St.Store.new(), Map.new(&2, String), [])

# Another output of the virtual pod source, after f.
def next(f: S.Folded, +o: W.Out) -> S.Folded:
  match f:
    case S.Folded{s, pr, ks}:
      S.Sync.fold([o], 8, cfg(), s, pr, [])

def keys(f: S.Folded) -> List<&2, String>:
  match f:
    case S.Folded{s, pr, ks}:
      ks

def refd(f: S.Folded, +k: String) -> Bool:
  match f:
    case S.Folded{s, pr, ks}:
      CL.Classic.sigs_have(S.Sync.pr_sigs(pr), k)

def main() -> IO(Unit):
  do IO<Unit>:
    check("ref_sig keeps only ConfigMap and Secret keys",
      String.eq(CL.Classic.ref_sig(["pods|load/p", "configmaps|load/cm-0", "secrets|load/s", "nodes|/n"]),
        ",configmaps|load/cm-0,secrets|load/s,"))
    check("ref_sig of a pod without references", String.eq(CL.Classic.ref_sig(["pods|load/p"]), ","))
    check("sig_has matches whole keys only",
      Bool.and(CL.Classic.sig_has(",configmaps|load/cm-1,", "configmaps|load/cm-1"),
        Bool.not(CL.Classic.sig_has(",configmaps|load/cm-10,", "configmaps|load/cm-1"))))
    check("an update with the same references queues no ConfigMap or Secret key",
      String.eq(String.join(CL.Classic.pod_event_keys(",configmaps|load/cm-0,", ",configmaps|load/cm-0,",
        ["pods|load/p", "configmaps|load/cm-0", "nodes|/n"]), " "), "pods|load/p nodes|/n"))
    check("a new pod queues its references",
      String.eq(String.join(CL.Classic.pod_event_keys("", ",configmaps|load/cm-0,", ["pods|load/p", "configmaps|load/cm-0"]), " "),
        "pods|load/p configmaps|load/cm-0"))
    check("changed references queue the old and the new references",
      String.eq(String.join(CL.Classic.pod_event_keys(",configmaps|load/cm-0,", ",configmaps|load/cm-1,",
        ["pods|load/p", "configmaps|load/cm-1"]), " "), "configmaps|load/cm-0 pods|load/p configmaps|load/cm-1"))
    +f1 : S.Folded = first(pod("cm-0", "Pending"))
    check("a new virtual pod queues its ConfigMap", has(keys(f1), "configmaps|load/cm-0"))
    check("the index holds the new pod's ConfigMap", refd(f1, "configmaps|load/cm-0"))
    check("the index does not hold another ConfigMap", Bool.not(refd(f1, "configmaps|load/cm")))
    +f2 : S.Folded = next(f1, W.OApply{pod("cm-0", "Running")})
    check("a status update queues the pod", has(keys(f2), "pods|load/p"))
    check("a status update queues no ConfigMap", Bool.not(has(keys(f2), "configmaps|load/cm-0")))
    check("the index still holds the ConfigMap", refd(f2, "configmaps|load/cm-0"))
    +f3 : S.Folded = next(f2, W.ODelete{pod("cm-0", "Running")})
    check("a deleted pod queues its ConfigMap", has(keys(f3), "configmaps|load/cm-0"))
    check("the index drops a deleted pod's ConfigMap", Bool.not(refd(f3, "configmaps|load/cm-0")))
    +f4 : S.Folded = next(f2, W.OApply{pod("cm-1", "Running")})
    check("changed references queue the new ConfigMap", has(keys(f4), "configmaps|load/cm-1"))
    check("changed references queue the old ConfigMap", has(keys(f4), "configmaps|load/cm-0"))
    check("the index follows changed references",
      Bool.and(refd(f4, "configmaps|load/cm-1"), Bool.not(refd(f4, "configmaps|load/cm-0"))))
