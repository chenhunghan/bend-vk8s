import Base
import ../host/syncer.bend as S
import ../src/sync/classic.bend as CL
import ../src/translate/services.bend as SV
import ../src/translate/pods.bend as P
import bend-kube-runtime@0.10.0.0/src/json.bend as J
import bend-kube-runtime@0.10.0.0/src/watcher.bend as W
import bend-kube-runtime@0.10.0.0/src/store.bend as St

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
def pod_n(+name: String, +cm: String, +phase: String) -> J.Json:
  jr(J.Json.parse(P.Pods.subst("{`metadata`:{`name`:`" ++ name ++ "`,`namespace`:`load`},`spec`:{`containers`:[{`name`:`c`}],"
    ++ "`volumes`:[{`name`:`v`,`configMap`:{`name`:`" ++ cm ++ "`}}]},`status`:{`phase`:`" ++ phase ++ "`}}", '`', '"')))

def pod(+cm: String, +phase: String) -> J.Json:
  pod_n("p", cm, phase)

def cfg() -> SV.Cfg:
  SV.Cfg{"load", "vcluster-load", "vcluster"}

def first(+x: J.Json) -> S.Folded:
  S.Sync.fold([W.OApply{x}], 8, cfg(), St.Store.new(), S.Refs.new(), [])

# Another output of the virtual pod source, after f.
def next(f: S.Folded, +o: W.Out) -> S.Folded:
  match f:
    case S.Folded{s, pr, ks}:
      S.Sync.fold([o], 8, cfg(), s, pr, [])

# The host pod of virtual pod load/name: the object-name and
# object-namespace annotations name its virtual pod (vcluster
# pkg/util/translate/types.go NameAnnotation, NamespaceAnnotation).
def hpod_n(+name: String) -> J.Json:
  jr(J.Json.parse(P.Pods.subst("{`metadata`:{`name`:`" ++ name ++ "-x-load-x-vcluster-load`,`namespace`:`vcluster-load`,"
    ++ "`annotations`:{`vcluster.loft.sh/object-name`:`" ++ name ++ "`,`vcluster.loft.sh/object-namespace`:`load`}},"
    ++ "`spec`:{`containers`:[{`name`:`c`}]}}", '`', '"')))

def keep_store(s: St.Store, h: S.Folded) -> S.Folded:
  match h:
    case S.Folded{hs, pr, ks}:
      S.Folded{s, pr, ks}

# Outputs of the host pod source (store 9, from an empty host store),
# after f. The virtual pod store of f stays.
def nexth(f: S.Folded, os: List<&2, W.Out>) -> S.Folded:
  match f:
    case S.Folded{s, pr, ks}:
      keep_store(s, S.Sync.fold(os, 9, cfg(), St.Store.new(), pr, []))

def keys(f: S.Folded) -> List<&2, String>:
  match f:
    case S.Folded{s, pr, ks}:
      ks

def refd(f: S.Folded, +k: String) -> Bool:
  match f:
    case S.Folded{s, pr, ks}:
      S.Refs.has(pr, k)

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
    +g1 : S.Folded = next(f1, W.OApply{pod_n("q", "cm-0", "Pending")})
    +g2 : S.Folded = next(g1, W.ODelete{pod("cm-0", "Pending")})
    check("a ConfigMap stays referenced while another pod refers to it", refd(g2, "configmaps|load/cm-0"))
    check("a ConfigMap is no longer referenced when its last pod goes",
      Bool.not(refd(next(g2, W.ODelete{pod_n("q", "cm-0", "Pending")}), "configmaps|load/cm-0")))
    # vcluster pkg/mappings/store/store.go: a pod mapping keeps its
    # references while objectExists (store.go:195-265: the virtual object
    # or the host object exists); garbageCollectMapping then removeMapping
    # (store.go:688-697) dispatches each reference's watch. store_test.go
    # TestGarbageCollectMappings: the references stay while the virtual pod
    # exists and go once neither object exists.
    +h1 : S.Folded = nexth(f1, [W.OApply{hpod_n("p")}])
    +h2 : S.Folded = next(h1, W.ODelete{pod("cm-0", "Pending")})
    check("a force-deleted virtual pod keeps its ConfigMap while its host pod exists", refd(h2, "configmaps|load/cm-0"))
    check("a force-deleted virtual pod with a host pod queues no ConfigMap", Bool.not(has(keys(h2), "configmaps|load/cm-0")))
    check("a force-deleted virtual pod with a host pod queues the pod", has(keys(h2), "pods|load/p"))
    +h3 : S.Folded = nexth(h2, [W.ODelete{hpod_n("p")}])
    check("the host pod's delete releases the held ConfigMap", Bool.not(refd(h3, "configmaps|load/cm-0")))
    check("the host pod's delete queues the held ConfigMap", has(keys(h3), "configmaps|load/cm-0"))
    +k2 : S.Folded = nexth(f1, [W.OApply{hpod_n("p")}, W.ODelete{hpod_n("p")}])
    check("a host pod's delete keeps the ConfigMap of a live virtual pod", refd(k2, "configmaps|load/cm-0"))
    check("a host pod's delete with a live virtual pod queues no ConfigMap", Bool.not(has(keys(k2), "configmaps|load/cm-0")))
    +k3 : S.Folded = next(k2, W.ODelete{pod("cm-0", "Running")})
    check("a virtual delete after its host pod's releases the ConfigMap", Bool.not(refd(k3, "configmaps|load/cm-0")))
    check("a virtual delete after its host pod's queues the ConfigMap", has(keys(k3), "configmaps|load/cm-0"))
    +r1 : S.Folded = next(h2, W.OApply{pod("cm-1", "Pending")})
    check("a recreated virtual pod's references replace the held ones",
      Bool.and(refd(r1, "configmaps|load/cm-1"), Bool.not(refd(r1, "configmaps|load/cm-0"))))
    check("a recreated virtual pod queues the held ConfigMap", has(keys(r1), "configmaps|load/cm-0"))
    check("the old host pod's delete keeps the recreated pod's ConfigMap",
      refd(nexth(r1, [W.ODelete{hpod_n("p")}]), "configmaps|load/cm-1"))
    +d2 : S.Folded = next(next(nexth(f1, [W.OApply{hpod_n("p")}]), W.OInit{}), W.OInitDone{})
    check("a relist that drops a virtual pod keeps its ConfigMap while its host pod exists", refd(d2, "configmaps|load/cm-0"))
    check("a relist that drops a virtual pod with a host pod queues no ConfigMap", Bool.not(has(keys(d2), "configmaps|load/cm-0")))
    +e2 : S.Folded = next(next(f1, W.OInit{}), W.OInitDone{})
    check("a relist that drops a virtual pod without a host pod releases its ConfigMap",
      Bool.and(Bool.not(refd(e2, "configmaps|load/cm-0")), has(keys(e2), "configmaps|load/cm-0")))
    +hd : S.Folded = nexth(h2, [W.OApply{hpod_n("p")}, W.OInit{}, W.OInitDone{}])
    check("a host relist that drops the host pod releases the held ConfigMap",
      Bool.and(Bool.not(refd(hd, "configmaps|load/cm-0")), has(keys(hd), "configmaps|load/cm-0")))
    # Review of #40, finding 2: a relist (OInitApply) with changed
    # references queues the old ones, as an update (OApply) does.
    +l1 : S.Folded = next(f1, W.OInitApply{pod("cm-1", "Running")})
    check("a relist with changed references queues the old ConfigMap", has(keys(l1), "configmaps|load/cm-0"))
    check("a relist with changed references queues the new ConfigMap", has(keys(l1), "configmaps|load/cm-1"))
    check("the index follows a relist's changed references",
      Bool.and(refd(l1, "configmaps|load/cm-1"), Bool.not(refd(l1, "configmaps|load/cm-0"))))
    check("a relist with the same references queues no ConfigMap",
      Bool.not(has(keys(next(f1, W.OInitApply{pod("cm-0", "Running")})), "configmaps|load/cm-0")))
