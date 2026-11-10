import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ./runtime.bend as RT
import ./core.bend as C
import ../translate/services.bend as S
import ../translate/meta.bend as M
import ../translate/pods.bend as P
import ../translate/nodes.bend as ND
import ../translate/storage.bend as SG
import ../config/vcluster.bend as V

# The rest of classic mode on top of the syncer runtime (runtime.bend):
# pods, fake nodes, events from the host, persistent volume claims and
# fake persistent volumes, each through its merged translator unchanged
# (src/translate/pods.bend, nodes.bend, storage.bend). Pure glue only:
# the watch sources and the queue keys their objects make, which kinds
# vcluster.yaml enables (pkg/controllers/resources/register.go), the
# translator inputs, and the API calls (Op) a step's writes become, in
# the runtime's write order (host before virtual, deletes first within a
# cluster, translator order kept inside a bucket).
#
# Services, ConfigMaps, Secrets and ServiceAccounts keep runtime.bend's
# path; Runtime.wired and Runtime.enabled_ids are unchanged.

# The kinds this module wires, by queue key id.
def Classic.ids() -> +List<String>:
  ["pods", "nodes", "events", "persistentvolumeclaims", "persistentvolumes", "storageclasses", "priorityclasses", "csinodes"]

# register.go: pods, events and persistentvolumeclaims run when their key
# is enabled; nodes.New and persistentvolumes.New always run and pick the
# fake syncers unless sync.fromHost.nodes or sync.toHost.persistentVolumes
# is enabled. vk8s has no real node or volume syncer, so those settings
# turn the kind off.
def Classic.on(+cfg: J.Json, id: String) -> Bool:
  match id:
    case "pods":
      V.Config.to_host(cfg, "pods")
    case "nodes":
      Bool.not(V.Config.from_host(cfg, "nodes"))
    case "events":
      V.Config.from_host(cfg, "events")
    case "persistentvolumeclaims":
      V.Config.to_host(cfg, "persistentVolumeClaims")
    case "persistentvolumes":
      Bool.not(V.Config.to_host(cfg, "persistentVolumes"))
    case "storageclasses":
      V.Config.to_host(cfg, "storageClasses")
    case "priorityclasses":
      V.Config.to_host(cfg, "priorityClasses")
    case "csinodes":
      V.Config.from_host(cfg, "csiNodes")
    case _:
      False{}

# sync.fromHost.nodes.enabled: nodes.New picks the real node syncer
# (nodes/syncer.go), which serves the "nodes" keys instead of the fake one.
def Classic.real_nodes(+cfg: J.Json) -> Bool:
  V.Config.from_host(cfg, "nodes")

# sync.toHost.persistentVolumes.enabled: persistentvolumes.New picks the
# real volume syncer, which serves the "persistentvolumes" keys.
def Classic.real_pvs(+cfg: J.Json) -> Bool:
  V.Config.to_host(cfg, "persistentVolumes")

def Classic.real_on(+cfg: J.Json, id: String) -> Bool:
  match id:
    case "nodes":
      Classic.real_nodes(cfg)
    case "persistentvolumes":
      Classic.real_pvs(cfg)
    case _:
      False{}

# Whether the keys of an id reconcile: its kind's flag, or the real
# syncer that serves the same keys.
def Classic.key_on(+cfg: J.Json, +id: String) -> Bool:
  Bool.or(Classic.on(cfg, id), Classic.real_on(cfg, id))

def Classic.on_ids(xs: +List<String>, +cfg: J.Json) -> +List<String>:
  match xs:
    case Nil{}:
      []
    case Con{+x, t}:
      RT.Runtime.enabled_ids.keep(Classic.key_on(cfg, x), x, Classic.on_ids(t, cfg))

# Every kind the syncer runs: runtime.bend's, then this module's.
def Classic.enabled_ids(+cfg: J.Json) -> +List<String>:
  List.append(&2, String, RT.Runtime.enabled_ids(cfg), Classic.on_ids(Classic.ids(), cfg))

# Watch sources
# -------------

# A watch: the kind's id, the cluster (host or virtual), and whether it
# filters on vcluster's managed-by label. Virtual watches cover every
# namespace (or the cluster); host watches cover the host namespace.
type Source is Data:
  Source{id: String, host: Bool, labeled: Bool}

# Source i owns store i. 0-7 are runtime.bend's (Runtime.wired, virtual
# then host), 8 the virtual pods (always watched: they hold the ConfigMap
# and Secret references and the nodes pods need), then this module's.
# Host events carry no vcluster label.
def Classic.sources() -> List<&2, Source>:
  [Source{"services", False{}, False{}}, Source{"services", True{}, True{}},
   Source{"configmaps", False{}, False{}}, Source{"configmaps", True{}, True{}},
   Source{"secrets", False{}, False{}}, Source{"secrets", True{}, True{}},
   Source{"serviceaccounts", False{}, False{}}, Source{"serviceaccounts", True{}, True{}},
   Source{"pods", False{}, False{}}, Source{"pods", True{}, True{}},
   Source{"nodes", False{}, False{}},
   Source{"events", True{}, False{}},
   Source{"persistentvolumeclaims", False{}, False{}}, Source{"persistentvolumeclaims", True{}, True{}},
   Source{"persistentvolumes", False{}, False{}}]

def Classic.vpods() -> Nat:
  8n

def Classic.hpods() -> Nat:
  9n

def Classic.vnodes() -> Nat:
  10n

def Classic.vpvcs() -> Nat:
  12n

def Classic.source.go(ss: List<&2, Source>, n: Nat) -> Maybe<&2, Source>:
  match ss n:
    case Nil{} m:
      None{}
    case Con{s, t} 0n:
      Some{s}
    case Con{s, t} 1n+m:
      Classic.source.go(t, m)

def Classic.source(n: Nat) -> Maybe<&2, Source>:
  Classic.source.go(Classic.sources(), n)

# The second table, from 15 on: host nodes (real nodes), storage classes
# and priority classes both ways, host volumes (real volumes), CSINodes
# both ways. Cluster-scoped host watches carry no label filter: vcluster
# marks them with the cluster marker, and real nodes, provisioned volumes
# and CSINodes carry none.
def Classic.more_sources() -> List<&2, Source>:
  [Source{"nodes", True{}, False{}},
   Source{"storageclasses", False{}, False{}}, Source{"storageclasses", True{}, False{}},
   Source{"priorityclasses", False{}, False{}}, Source{"priorityclasses", True{}, False{}},
   Source{"persistentvolumes", True{}, False{}},
   Source{"csinodes", False{}, False{}}, Source{"csinodes", True{}, False{}}]

# Every source: Classic.sources, then Classic.more_sources. Source i owns
# store i.
def Classic.all_sources() -> List<&2, Source>:
  List.append(&2, Source, Classic.sources(), Classic.more_sources())

def Classic.src(n: Nat) -> Maybe<&2, Source>:
  Classic.source.go(Classic.all_sources(), n)

def Classic.vpvs() -> Nat:
  14n

def Classic.hnodes() -> Nat:
  15n

def Classic.id_on.m(+cfg: J.Json, m: Maybe<&2, RT.Resource>, id: String) -> Bool:
  match m:
    case Some{k}:
      RT.Runtime.enabled(cfg, k)
    case None{}:
      Classic.key_on(cfg, id)

# Whether cfg enables the kind with this id (either module's).
def Classic.id_on(+cfg: J.Json, +id: String) -> Bool:
  Classic.id_on.m(cfg, RT.Runtime.kind_of(id), id)

def Classic.source_on.if(always: Bool, +cfg: J.Json, +id: String) -> Bool:
  match always:
    case True{}:
      True{}
    case False{}:
      Classic.id_on(cfg, id)

def Classic.has_real(id: String) -> Bool:
  match id:
    case "nodes":
      True{}
    case "persistentvolumes":
      True{}
    case _:
      False{}

# A kind with a real syncer: its host source only for the real one, its
# virtual source for either.
def Classic.real_src(host: Bool, fake: Bool, real: Bool) -> Bool:
  match host:
    case True{}:
      real
    case False{}:
      Bool.or(fake, real)

def Classic.source_on.of(real: Bool, +host: Bool, +cfg: J.Json, +id: String) -> Bool:
  match real:
    case True{}:
      Classic.real_src(host, Classic.on(cfg, id), Classic.real_on(cfg, id))
    case False{}:
      Classic.source_on.if(Bool.and(String.eq(id, "pods"), Bool.not(host)), cfg, id)

# Whether a source is watched; a source that is not starts ready and empty.
def Classic.source_on(+cfg: J.Json, s: Source) -> Bool:
  match s:
    case Source{+id, +host, l}:
      Classic.source_on.of(Classic.has_real(id), host, cfg, id)

# Queue keys
# ----------

def Classic.keys(empty: Bool, +id: String, +ns: String, +name: String) -> List<&2, String>:
  match empty:
    case True{}:
      []
    case False{}:
      [RT.Runtime.key(id, ns, name)]

# A key; none for an empty name.
def Classic.key(+id: String, +ns: String, +name: String) -> List<&2, String>:
  Classic.keys(String.is_empty(name), id, ns, name)

def Classic.self_key(+id: String, +o: J.Json) -> List<&2, String>:
  Classic.key(id, S.Svc.namespace(o), S.Svc.name(o))

# A host object's virtual key: its object-namespace and object-name
# annotations (translate/types.go).
def Classic.ann_key(+id: String, +o: J.Json) -> List<&2, String>:
  Classic.key(id, S.Svc.annotation(M.Meta.namespace_annotation(), o), S.Svc.annotation(M.Meta.name_annotation(), o))

# The fake node a pod needs (nodes modifyController: pod events of both
# clusters enqueue spec.nodeName).
def Classic.node_key(+o: J.Json) -> List<&2, String>:
  Classic.key("nodes", "", S.Svc.spec_str(o, "nodeName"))

# The fake volume a claim names (spec.volumeName).
def Classic.pv_key(+o: J.Json) -> List<&2, String>:
  Classic.key("persistentvolumes", "", S.Svc.spec_str(o, "volumeName"))

def Classic.pod_keys(host: Bool, +c: S.Cfg, +o: J.Json) -> List<&2, String>:
  match host:
    case True{}:
      List.append(&2, String, Classic.ann_key("pods", o), Classic.node_key(o))
    case False{}:
      List.append(&2, String, Classic.self_key("pods", o),
        List.append(&2, String, RT.Runtime.pod_keys(c, o), Classic.node_key(o)))

def Classic.pvc_keys(host: Bool, +o: J.Json) -> List<&2, String>:
  match host:
    case True{}:
      Classic.ann_key("persistentvolumeclaims", o)
    case False{}:
      List.append(&2, String, Classic.self_key("persistentvolumeclaims", o), Classic.pv_key(o))

# A cluster-scoped object to the host: a virtual object names itself, a
# host object the virtual object its object-name annotation names (none
# for an object vcluster did not make).
def Classic.cluster_keys(+id: String, host: Bool, +o: J.Json) -> List<&2, String>:
  match host:
    case True{}:
      Classic.key(id, "", S.Svc.annotation(M.Meta.name_annotation(), o))
    case False{}:
      Classic.key(id, "", S.Svc.name(o))

def Classic.or_name(empty: Bool, +ann: String, +name: String) -> String:
  match empty:
    case True{}:
      name
    case False{}:
      ann

# The virtual name of a host volume (persistentVolumeMapper.HostToVirtual):
# its object-name annotation, else its own name.
def Classic.pv_vname(+o: J.Json) -> String:
  +ann = S.Svc.annotation(M.Meta.name_annotation(), o)
  Classic.or_name(String.is_empty(ann), ann, S.Svc.name(o))

def Classic.pv_keys(host: Bool, +o: J.Json) -> List<&2, String>:
  match host:
    case True{}:
      Classic.key("persistentvolumes", "", Classic.pv_vname(o))
    case False{}:
      Classic.key("persistentvolumes", "", S.Svc.name(o))

def Classic.old_keys(m: Maybe<&2, RT.Resource>, host: Bool, +c: S.Cfg, +o: J.Json) -> List<&2, String>:
  match m:
    case None{}:
      []
    case Some{k}:
      RT.Runtime.obj_key(k, host, c, o)

def Classic.id_keys.go(id: String, old: Maybe<&2, RT.Resource>, host: Bool, +c: S.Cfg, +o: J.Json) -> List<&2, String>:
  match id:
    case "pods":
      Classic.pod_keys(host, c, o)
    case "nodes":
      Classic.self_key("nodes", o)
    case "events":
      Classic.self_key("events", o)
    case "persistentvolumeclaims":
      Classic.pvc_keys(host, o)
    case "persistentvolumes":
      Classic.pv_keys(host, o)
    case "storageclasses":
      Classic.cluster_keys("storageclasses", host, o)
    case "priorityclasses":
      Classic.cluster_keys("priorityclasses", host, o)
    case "csinodes":
      Classic.self_key("csinodes", o)
    case _:
      Classic.old_keys(old, host, c, o)

# The keys an object of a kind queues. Host events are keyed by the host
# event itself: their virtual name depends on the object they involve.
def Classic.id_keys(+id: String, host: Bool, +c: S.Cfg, +o: J.Json) -> List<&2, String>:
  Classic.id_keys.go(id, RT.Runtime.kind_of(id), host, c, o)

def Classic.src_keys.of(m: Maybe<&2, Source>, +c: S.Cfg, +o: J.Json) -> List<&2, String>:
  match m:
    case None{}:
      []
    case Some{Source{id, host, l}}:
      Classic.id_keys(id, host, c, o)

# The keys an object seen by source n queues.
def Classic.src_keys(n: Nat, +c: S.Cfg, +o: J.Json) -> List<&2, String>:
  Classic.src_keys.of(Classic.src(n), c, o)

# The vcluster's own host Service (vcluster: the Service named after the
# vcluster in its namespace) carries no managed-by label, so the labeled
# host services watch never sees it. A watch of its own, by field
# selector, feeds one more store after the source table: a change of that
# Service queues default/kubernetes (specialservices.SyncKubernetesService).
def Classic.kube_store() -> U32:
  23

def Classic.kube_field(+vc: String) -> String:
  "metadata.name=" ++ vc

def Classic.store_keys.if(kube: Bool, +src: U32, +c: S.Cfg, +o: J.Json) -> List<&2, String>:
  match kube:
    case True{}:
      RT.Runtime.obj_key(RT.KServices{}, True{}, c, o)
    case False{}:
      Classic.src_keys(U32.to_nat(src), c, o)

# The keys an object seen by the watch that feeds store src queues: the
# source table's, or the vcluster's host Service's.
def Classic.store_keys(+src: U32, +c: S.Cfg, +o: J.Json) -> List<&2, String>:
  Classic.store_keys.if(U32.is_eq(src, Classic.kube_store()), src, c, o)

# API calls
# ---------

# A call a step makes, on the host (True) or the virtual cluster, on a
# resource named by its plural (res):
#   OCreate, OUpdate: POST, PUT of the object (namespace and name from it)
#   OStatus: a merge patch of the status subresource with the object's
#     status (a create or an update drops the status)
#   ODelete: a delete with a grace period (JNull: the default) and a UID
#     precondition ("" for none)
#   OSub: a request on a subresource (binding, ephemeralcontainers, resize)
#   ONote: no call; a line in the syncer's log (a pod event)
type Op is Data:
  OCreate{host: Bool, res: String, obj: J.Json}
  OUpdate{host: Bool, res: String, obj: J.Json}
  OStatus{host: Bool, res: String, obj: J.Json}
  ODelete{host: Bool, res: String, namespace: String, name: String, grace: J.Json, uid: String}
  OSub{host: Bool, res: String, namespace: String, name: String, method: String, sub: String, ctype: String,
    body: J.Json}
  ONote{msg: String}

# The calls of one step, its requeue, and its error ("" for none: a step
# with an error retries with backoff, as a returned Go error does).
type Act is Data:
  Act{ops: List<&2, Op>, rq: S.Requeue, err: String}

def Classic.phase.of(host: Bool, del: Bool) -> U32:
  match host del:
    case True{} True{}:
      0
    case True{} False{}:
      1
    case False{} True{}:
      2
    case False{} False{}:
      3

# Runtime.phase's four buckets: host deletes, host writes, virtual
# deletes, virtual writes.
def Classic.phase(o: Op) -> U32:
  match o:
    case OCreate{host, r, x}:
      Classic.phase.of(host, False{})
    case OUpdate{host, r, x}:
      Classic.phase.of(host, False{})
    case OStatus{host, r, x}:
      Classic.phase.of(host, False{})
    case ODelete{host, r, ns, n, g, u}:
      Classic.phase.of(host, True{})
    case OSub{host, r, ns, n, m, s, ct, b}:
      Classic.phase.of(host, False{})
    case ONote{m}:
      3

def Classic.keep(yes: Bool, o: Op, rest: List<&2, Op>) -> List<&2, Op>:
  match yes:
    case True{}:
      o <> rest
    case False{}:
      rest

def Classic.bucket(os: List<&2, Op>, +phase: U32) -> List<&2, Op>:
  match os:
    case Nil{}:
      []
    case Con{+o, rest}:
      Classic.keep(U32.is_eq(Classic.phase(o), phase), o, Classic.bucket(rest, phase))

# Equal work in each parallel branch: two scans of the same call list.
def Classic.half(+os: List<&2, Op>, +phase: U32) -> List<&2, Op>:
  deletes writes = Classic.bucket(os, phase) Classic.bucket(os, (phase + 1 : U32))
  List.append(&2, Op, deletes, writes)

# Runtime.order over calls.
def Classic.order(+os: List<&2, Op>) -> List<&2, Op>:
  host virtual = Classic.half(os, 0) Classic.half(os, 2)
  List.append(&2, Op, host, virtual)

def Classic.ops(a: Act) -> List<&2, Op>:
  match a:
    case Act{os, rq, e}:
      os

def Classic.requeue(a: Act) -> S.Requeue:
  match a:
    case Act{os, rq, e}:
      rq

def Classic.err(a: Act) -> String:
  match a:
    case Act{os, rq, e}:
      e

# The body of an OStatus: the object's status alone.
def Classic.status_patch(+o: J.Json) -> J.Json:
  J.Json.obj([J.KV{"status", J.Json.get(o, "status")}])

# services.bend writes on resource res.
def Classic.of_write(+res: String, w: S.Write) -> List<&2, Op>:
  match w:
    case S.HostCreate{o}:
      [OCreate{True{}, res, o}]
    case S.HostUpdate{o}:
      [OUpdate{True{}, res, o}]
    case S.HostDelete{ns, n}:
      [ODelete{True{}, res, ns, n, J.JNull{}, ""}]
    case S.VirtualCreate{o}:
      [OCreate{False{}, res, o}]
    case S.VirtualUpdate{o}:
      [OUpdate{False{}, res, o}]
    case S.VirtualDelete{ns, n}:
      [ODelete{False{}, res, ns, n, J.JNull{}, ""}]

def Classic.of_writes(+res: String, ws: List<&2, S.Write>) -> List<&2, Op>:
  match ws:
    case Nil{}:
      []
    case Con{w, t}:
      List.append(&2, Op, Classic.of_write(res, w), Classic.of_writes(res, t))

def Classic.act(out: S.Outcome, +res: String) -> Act:
  match out:
    case S.Outcome{ws, rq}:
      Act{Classic.order(Classic.of_writes(res, ws)), rq, ""}

# Fake nodes: createFakeNode creates the node, then writes its status
# (Status().Patch); updateIfNeeded's update is a status update.
def Classic.node_op(w: S.Write) -> List<&2, Op>:
  match w:
    case S.VirtualCreate{+o}:
      [OCreate{False{}, "nodes", o}, OStatus{False{}, "nodes", o}]
    case S.VirtualUpdate{o}:
      [OStatus{False{}, "nodes", o}]
    case S.VirtualDelete{ns, n}:
      [ODelete{False{}, "nodes", ns, n, J.JNull{}, ""}]
    case S.HostCreate{o}:
      [OCreate{True{}, "nodes", o}]
    case S.HostUpdate{o}:
      [OUpdate{True{}, "nodes", o}]
    case S.HostDelete{ns, n}:
      [ODelete{True{}, "nodes", ns, n, J.JNull{}, ""}]

# createFakeNode then removes the taints (the API server's
# TaintNodesByCondition admission adds node.kubernetes.io/not-ready on
# create, and vcluster runs no node lifecycle controller to lift it): a
# patch to spec.taints []. Here an unconditional update of the fake node,
# which carries no taints (nodes allow updates without a resourceVersion).
def Classic.node_untaint(w: S.Write) -> List<&2, Op>:
  match w:
    case S.VirtualCreate{o}:
      [OUpdate{False{}, "nodes", o}]
    case _:
      []

def Classic.node_ops(ws: List<&2, S.Write>) -> List<&2, Op>:
  match ws:
    case Nil{}:
      []
    case Con{w, t}:
      +w = {w : S.Write}
      List.append(&2, Op, List.append(&2, Op, Classic.node_op(w), Classic.node_untaint(w)), Classic.node_ops(t))

def Classic.node_act(out: S.Outcome) -> Act:
  match out:
    case S.Outcome{ws, rq}:
      Act{Classic.order(Classic.node_ops(ws)), rq, ""}

# Real nodes: SyncToVirtual creates the node (and requeues); Sync's
# patcher.Patch writes the node, then its status.
def Classic.rnode_op(w: S.Write) -> List<&2, Op>:
  match w:
    case S.VirtualCreate{o}:
      [OCreate{False{}, "nodes", o}]
    case S.VirtualUpdate{+o}:
      [OUpdate{False{}, "nodes", o}, OStatus{False{}, "nodes", o}]
    case S.VirtualDelete{ns, n}:
      [ODelete{False{}, "nodes", ns, n, J.JNull{}, ""}]
    case S.HostCreate{o}:
      [OCreate{True{}, "nodes", o}]
    case S.HostUpdate{o}:
      [OUpdate{True{}, "nodes", o}]
    case S.HostDelete{ns, n}:
      [ODelete{True{}, "nodes", ns, n, J.JNull{}, ""}]

def Classic.rnode_ops(ws: List<&2, S.Write>) -> List<&2, Op>:
  match ws:
    case Nil{}:
      []
    case Con{w, t}:
      List.append(&2, Op, Classic.rnode_op(w), Classic.rnode_ops(t))

def Classic.rnode_act(out: S.Outcome) -> Act:
  match out:
    case S.Outcome{ws, rq}:
      Act{Classic.order(Classic.rnode_ops(ws)), rq, ""}

# Storage writes. An object's kind names its resource; a delete with no
# namespace is of a (cluster-scoped) volume.
def Classic.kind_res(k: String, dflt: String) -> String:
  match k:
    case "PersistentVolume":
      "persistentvolumes"
    case "PersistentVolumeClaim":
      "persistentvolumeclaims"
    case _:
      dflt

def Classic.st_res(+dflt: String, +o: J.Json) -> String:
  Classic.kind_res(S.Svc.str(J.Json.get(o, "kind")), dflt)

def Classic.ns_res(empty: Bool, dflt: String) -> String:
  match empty:
    case True{}:
      "persistentvolumes"
    case False{}:
      dflt

def Classic.status_if(none: Bool, host: Bool, res: String, o: J.Json) -> List<&2, Op>:
  match none:
    case True{}:
      []
    case False{}:
      [OStatus{host, res, o}]

# A virtual write, then its status when the object carries one (the bound
# fake volume; a claim's status from the host).
def Classic.with_status(host: Bool, +res: String, +o: J.Json, first: Op) -> List<&2, Op>:
  first <> Classic.status_if(J.Json.is_null(J.Json.get(o, "status")), host, res, o)

def Classic.st_op(+dflt: String, w: SG.Write) -> List<&2, Op>:
  match w:
    case SG.HostCreate{+o}:
      [OCreate{True{}, Classic.st_res(dflt, o), o}]
    case SG.HostUpdate{+o}:
      [OUpdate{True{}, Classic.st_res(dflt, o), o}]
    case SG.HostDelete{+ns, n, SG.Del{g, u}}:
      [ODelete{True{}, Classic.ns_res(String.is_empty(ns), dflt), ns, n, g, S.Svc.str(u)}]
    case SG.VirtualCreate{+o}:
      +r = Classic.st_res(dflt, o)
      Classic.with_status(False{}, r, o, OCreate{False{}, r, o})
    case SG.VirtualUpdate{+o}:
      +r = Classic.st_res(dflt, o)
      Classic.with_status(False{}, r, o, OUpdate{False{}, r, o})
    case SG.VirtualDelete{+ns, n, SG.Del{g, u}}:
      [ODelete{False{}, Classic.ns_res(String.is_empty(ns), dflt), ns, n, g, S.Svc.str(u)}]

def Classic.st_ops(+dflt: String, ws: List<&2, SG.Write>) -> List<&2, Op>:
  match ws:
    case Nil{}:
      []
    case Con{w, t}:
      List.append(&2, Op, Classic.st_op(dflt, w), Classic.st_ops(dflt, t))

def Classic.st_act(out: SG.Outcome, +dflt: String) -> Act:
  match out:
    case SG.Outcome{ws, rq, e}:
      Act{Classic.order(Classic.st_ops(dflt, ws)), rq, e}

# Writes of a cluster-scoped kind (storage classes, priority classes, real
# volumes, CSINodes): every call is on its resource res. A virtual write is
# followed by its status when the object carries one (a volume).
def Classic.cst_op(+res: String, w: SG.Write) -> List<&2, Op>:
  match w:
    case SG.HostCreate{o}:
      [OCreate{True{}, res, o}]
    case SG.HostUpdate{o}:
      [OUpdate{True{}, res, o}]
    case SG.HostDelete{ns, n, SG.Del{g, u}}:
      [ODelete{True{}, res, ns, n, g, S.Svc.str(u)}]
    case SG.VirtualCreate{+o}:
      Classic.with_status(False{}, res, o, OCreate{False{}, res, o})
    case SG.VirtualUpdate{+o}:
      Classic.with_status(False{}, res, o, OUpdate{False{}, res, o})
    case SG.VirtualDelete{ns, n, SG.Del{g, u}}:
      [ODelete{False{}, res, ns, n, g, S.Svc.str(u)}]

def Classic.cst_ops(+res: String, ws: List<&2, SG.Write>) -> List<&2, Op>:
  match ws:
    case Nil{}:
      []
    case Con{w, t}:
      List.append(&2, Op, Classic.cst_op(res, w), Classic.cst_ops(res, t))

def Classic.cst_act(out: SG.Outcome, +res: String) -> Act:
  match out:
    case SG.Outcome{ws, rq, e}:
      Act{Classic.order(Classic.cst_ops(res, ws)), rq, e}

# Pods
# ----

def Classic.grace.if(empty: Bool, g: String) -> J.Json:
  match empty:
    case True{}:
      J.JNull{}
    case False{}:
      J.JNum{g}

# A pod write's grace period ("" is the default).
def Classic.grace(+g: String) -> J.Json:
  Classic.grace.if(String.is_empty(g), g)

# The Binding assignNodeToPod posts to pods/<name>/binding.
def Classic.binding(+ns: String, +name: String, +node: String) -> J.Json:
  J.Json.obj([J.KV{"apiVersion", J.JStr{"v1"}}, J.KV{"kind", J.JStr{"Binding"}},
    J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{name}}, J.KV{"namespace", J.JStr{ns}}])},
    J.KV{"target", J.Json.obj([J.KV{"apiVersion", J.JStr{"v1"}}, J.KV{"kind", J.JStr{"Node"}}, J.KV{"name", J.JStr{node}}])}])

# The calls of one pod write. A patch (the patcher's object and status
# patches) is an update, then the status. vns/vname and hns/hname name the
# virtual and the host pod.
def Classic.pod_op(+vns: String, +vname: String, +hns: String, +hname: String, w: P.Write) -> List<&2, Op>:
  match w:
    case P.WCreateHost{o}:
      [OCreate{True{}, "pods", o}]
    case P.WCreateVirtual{o}:
      [OCreate{False{}, "pods", o}]
    case P.WPatchHost{+o}:
      [OUpdate{True{}, "pods", o}, OStatus{True{}, "pods", o}]
    case P.WPatchVirtual{+o}:
      [OUpdate{False{}, "pods", o}, OStatus{False{}, "pods", o}]
    case P.WVirtualStatus{o}:
      [OStatus{False{}, "pods", o}]
    case P.WDeleteHost{g, u}:
      [ODelete{True{}, "pods", hns, hname, Classic.grace(g), u}]
    case P.WDeleteVirtual{g, u}:
      [ODelete{False{}, "pods", vns, vname, Classic.grace(g), u}]
    case P.WBind{node}:
      [OSub{False{}, "pods", vns, vname, "POST", "binding", "application/json", Classic.binding(vns, vname, node)}]
    case P.WEphemeral{o}:
      [OSub{True{}, "pods", hns, hname, "PUT", "ephemeralcontainers", "application/json", o}]
    case P.WResize{p}:
      [OSub{True{}, "pods", hns, hname, "PATCH", "resize", "application/strategic-merge-patch+json", p}]
    case P.WSecret{o}:
      [OUpdate{True{}, "secrets", o}]
    case P.WEvent{k, r, m}:
      [ONote{k ++ " " ++ r ++ ": " ++ m}]
    case P.WRequeue{ms}:
      []
    case P.WError{m}:
      []

def Classic.pod_ops(+vns: String, +vname: String, +hns: String, +hname: String, ws: List<&2, P.Write>) -> List<&2, Op>:
  match ws:
    case Nil{}:
      []
    case Con{w, t}:
      List.append(&2, Op, Classic.pod_op(vns, vname, hns, hname, w), Classic.pod_ops(vns, vname, hns, hname, t))

def Classic.ms_rq.if(zero: Bool, +ms: U32) -> S.Requeue:
  match zero:
    case True{}:
      S.RequeueNow{}
    case False{}:
      S.RequeueAfter{RT.Runtime.seconds(ms)}

# A pod requeue in milliseconds, in the outcome's whole seconds (rounded up).
def Classic.ms_rq(+ms: U32) -> S.Requeue:
  Classic.ms_rq.if(U32.is_eq(ms, 0), ms)

# The first requeue of a pod step.
def Classic.pod_rq(ws: List<&2, P.Write>) -> S.Requeue:
  match ws:
    case Nil{}:
      S.NoRequeue{}
    case Con{P.WRequeue{ms}, t}:
      Classic.ms_rq(ms)
    case Con{w, t}:
      Classic.pod_rq(t)

# The first error of a pod step ("" for none).
def Classic.pod_err(ws: List<&2, P.Write>) -> String:
  match ws:
    case Nil{}:
      ""
    case Con{P.WError{m}, t}:
      m
    case Con{w, t}:
      Classic.pod_err(t)

def Classic.pods_act(+vns: String, +vname: String, +hns: String, +hname: String, +ws: List<&2, P.Write>) -> Act:
  Act{Classic.order(Classic.pod_ops(vns, vname, hns, hname, ws)), Classic.pod_rq(ws), Classic.pod_err(ws)}

# pods.Options: ObjectCaching, UID deletion on.
def Classic.pod_core(+c: S.Cfg) -> C.Cfg:
  C.Cfg{S.Svc.vc(c), S.Svc.target(c), P.Pods.kind(), "pod", True{}, True{}, False{}}

# IsManaged of a host object, by translate.Default with its expected name.
def Classic.managed(+core: C.Cfg, +hname: String, h: Maybe<&2, J.Json>) -> Bool:
  match h:
    case None{}:
      False{}
    case Some{+o}:
      C.Core.is_managed_to_host(core, False{}, Some{hname}, o)

def Classic.pods_dispatch(d: C.Decision, +pc: P.Cfg, +sin: P.SInp) -> List<&2, P.Write>:
  match d:
    case C.DSkip{}:
      []
    case C.DRequeue{}:
      [P.WRequeue{0}]
    case C.DRequeueAfter{ms}:
      [P.WRequeue{ms}]
    case C.DDeleteHost{h, reason}:
      [P.WDeleteHost{"", ""}]
    case C.DToHost{ho, v}:
      P.Pods.sync_to_host(pc, sin, ho, v)
    case C.DToVirtual{vo, h}:
      P.Pods.sync_to_virtual(pc, vo, h)
    case C.DSync{vo, +v, ho, +h}:
      P.Pods.sync_both(pc, sin, Maybe.default(&2, J.Json, ho, h), h, Maybe.default(&2, J.Json, vo, v), v)

# One pod reconcile: the generic framework's decision, then the pod
# syncer's SyncToHost, SyncToVirtual or Sync.
def Classic.pods_step(+pc: P.Cfg, +c: S.Cfg, +sin: P.SInp, +hname: String,
  vo: Maybe<&2, J.Json>, +v: Maybe<&2, J.Json>, ho: Maybe<&2, J.Json>, +h: Maybe<&2, J.Json>) -> List<&2, P.Write>:
  Classic.pods_dispatch(C.Core.decide(Classic.pod_core(c), Classic.managed(Classic.pod_core(c), hname, h), vo, v, ho, h), pc, sin)

def Classic.pods(+pc: P.Cfg, +c: S.Cfg, +sin: P.SInp, +vns: String, +vname: String, +hname: String,
  vo: Maybe<&2, J.Json>, +v: Maybe<&2, J.Json>, ho: Maybe<&2, J.Json>, +h: Maybe<&2, J.Json>) -> Act:
  Classic.pods_act(vns, vname, S.Svc.target(c), hname, Classic.pods_step(pc, c, sin, hname, vo, v, ho, h))

# vk8s: the virtual pod's status.observedGeneration counts virtual
# generations. vcluster copies the host's (DesiredVirtualStatus), which
# matches while both generations move together, but the two API servers
# bump them on different changes (a resize to equivalent quantities bumps
# the virtual pod and not the host's). The host's lag (generation minus
# observedGeneration) carries over instead: the virtual pod is observed up
# to its generation less that lag.
def Classic.or0(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{n}:
      n
    case None{}:
      0

def Classic.num(+j: J.Json) -> U32:
  Classic.or0(U32.read(J.Json.show(j)))

def Classic.gen(+o: J.Json) -> U32:
  Classic.num(J.Json.at(o, ["metadata", "generation"]))

def Classic.obs(+o: J.Json) -> U32:
  Classic.num(J.Json.at(o, ["status", "observedGeneration"]))

# The virtual observed generation, 0 when there is nothing to map (no host
# pod, or no observed generation on the host).
def Classic.obs_target.lag(less: Bool, +vg: U32, +lag: U32) -> U32:
  match less:
    case True{}:
      U32.sub(vg, lag)
    case False{}:
      1

def Classic.obs_target.seen(behind: Bool, +vg: U32, +hg: U32, +ho: U32) -> U32:
  match behind:
    case True{}:
      +lag = U32.sub(hg, ho)
      Classic.obs_target.lag(U32.is_lt(lag, vg), vg, lag)
    case False{}:
      vg

def Classic.obs_target.go(none: Bool, +vg: U32, +hg: U32, +ho: U32) -> U32:
  match none:
    case True{}:
      0
    case False{}:
      Classic.obs_target.seen(U32.is_le(ho, hg), vg, hg, ho)

def Classic.obs_target(v: Maybe<&2, J.Json>, h: Maybe<&2, J.Json>) -> U32:
  match v h:
    case Some{+x} Some{+y}:
      +ho = Classic.obs(y)
      Classic.obs_target.go(U32.is_zero(ho), Classic.gen(x), Classic.gen(y), ho)
    case a b:
      0

def Classic.is_null(j: J.Json) -> Bool:
  match j:
    case J.JNull{}:
      True{}
    case _:
      False{}

def Classic.gen_cond.if(absent: Bool, +t: J.Json, +c: J.Json) -> J.Json:
  match absent:
    case True{}:
      c
    case False{}:
      S.Svc.put(c, "observedGeneration", t)

def Classic.gen_cond(+t: J.Json, +c: J.Json) -> J.Json:
  Classic.gen_cond.if(Classic.is_null(J.Json.get(c, "observedGeneration")), t, c)

def Classic.gen_conds(+t: J.Json, cs: List<&2, J.Json>) -> List<&2, J.Json>:
  match cs:
    case Nil{}:
      []
    case Con{c, r}:
      Classic.gen_cond(t, c) <> Classic.gen_conds(t, r)

def Classic.gen_conds.put(absent: Bool, +t: J.Json, +st: J.Json) -> J.Json:
  match absent:
    case True{}:
      st
    case False{}:
      S.Svc.put(st, "conditions", J.Json.arr(Classic.gen_conds(t, J.Json.items(J.Json.get(st, "conditions")))))

def Classic.gen_status.if(absent: Bool, +t: J.Json, +st: J.Json) -> J.Json:
  match absent:
    case True{}:
      st
    case False{}:
      Classic.gen_conds.put(Classic.is_null(J.Json.get(st, "conditions")), t, S.Svc.put(st, "observedGeneration", t))

def Classic.gen_status(+t: J.Json, +st: J.Json) -> J.Json:
  Classic.gen_status.if(Classic.is_null(J.Json.get(st, "observedGeneration")), t, st)

def Classic.gen_obj(hit: Bool, +t: J.Json, +x: J.Json) -> J.Json:
  match hit:
    case True{}:
      S.Svc.put(x, "status", Classic.gen_status(t, J.Json.get(x, "status")))
    case False{}:
      x

def Classic.gen_op(+t: J.Json, o: Op) -> Op:
  match o:
    case OStatus{+h, +r, +x}:
      OStatus{h, r, Classic.gen_obj(Bool.and(Bool.not(h), String.eq(r, "pods")), t, x)}
    case other:
      other

def Classic.gen_ops(+t: J.Json, os: List<&2, Op>) -> List<&2, Op>:
  match os:
    case Nil{}:
      []
    case Con{o, r}:
      Classic.gen_op(t, o) <> Classic.gen_ops(t, r)

def Classic.gen_act.if(none: Bool, +t: U32, a: Act) -> Act:
  match none:
    case True{}:
      a
    case False{}:
      match a:
        case Act{os, rq, e}:
          Act{Classic.gen_ops(J.JNum{U32.show(t)}, os), rq, e}

def Classic.gen_act(+t: U32, a: Act) -> Act:
  Classic.gen_act.if(U32.is_zero(t), t, a)

def Classic.pods_g(+pc: P.Cfg, +c: S.Cfg, +sin: P.SInp, +vns: String, +vname: String, +hname: String,
  vo: Maybe<&2, J.Json>, +v: Maybe<&2, J.Json>, ho: Maybe<&2, J.Json>, +h: Maybe<&2, J.Json>) -> Act:
  Classic.gen_act(Classic.obs_target(v, h), Classic.pods(pc, c, sin, vns, vname, hname, vo, v, ho, h))

# The pod syncer's configuration: vcluster's chart defaults for this
# vcluster (Pods.cfg.default), sync.toHost.serviceAccounts.enabled, the
# virtual scheduler (pods/scheduling/config.go IsSchedulerFromVirtualCluster:
# host pods wait for a node and lose affinity, topology spread and node
# selector) and sync.toHost.priorityClasses.enabled (priority class names).
def Classic.pod_cfg(+c: S.Cfg, +on: J.Json) -> P.Cfg:
  p1 = P.Pods.cfg.set_sa_sync(P.Pods.cfg.default(S.Svc.vc(c), S.Svc.target(c), S.Svc.vc(c)), V.Config.to_host(on, "serviceAccounts"))
  p2 = P.Pods.cfg.set_virtual_scheduler(p1, V.Config.virtual_scheduler(on))
  P.Pods.cfg.set_pc_to_host(p2, V.Config.to_host(on, "priorityClasses"))

# vcluster's workload service account in the host namespace
# (controlPlane.advanced.workloadServiceAccount): host pods run as it when
# service accounts do not sync.
def Classic.workload_sa(+c: S.Cfg) -> J.Json:
  J.Json.obj([J.KV{"apiVersion", J.JStr{"v1"}}, J.KV{"kind", J.JStr{"ServiceAccount"}},
    J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{P.Pods.cfg.workload_sa(P.Pods.cfg.default(S.Svc.vc(c), S.Svc.target(c), S.Svc.vc(c)))}},
      J.KV{"namespace", J.JStr{S.Svc.target(c)}}])}])

# What the pod syncer reads besides the pods: the namespace's labels, its
# services, the DNS and API service IPs, the tokens, the virtual nodes.
# Pod security standards, class limits, token secrets and host path
# mapping are off (vcluster's defaults).
def Classic.pod_inp(+nsl: List<&2, M.KV>, svcs: List<&2, J.Json>, dns: String, kube: String, toks: List<&2, P.Tok>,
  nodes: List<&2, String>) -> P.SInp:
  P.SInp{P.Inp{nsl, svcs, dns, kube, toks, []}, P.DInp{nsl, []}, nodes, True{}, False{}, None{}}

# The host name of the virtual kube-dns service (pods translate.go
# findKubernetesDNSIP: VirtualToHostName of kube-system/kube-dns).
def Classic.dns_host_name(+vc: String) -> String:
  RT.Runtime.host_name(vc, "kube-system", "kube-dns")

# A service's cluster IP ("" when it is missing).
def Classic.cluster_ip(m: Maybe<&2, J.Json>) -> String:
  match m:
    case None{}:
      ""
    case Some{+s}:
      S.Svc.spec_str(s, "clusterIP")

# A namespace's labels ([] when it is missing).
def Classic.ns_labels(m: Maybe<&2, J.Json>) -> +List<M.KV>:
  match m:
    case None{}:
      []
    case Some{n}:
      P.Pods.map(J.Json.at(n, ["metadata", "labels"]))

def Classic.names(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{+x, t}:
      S.Svc.name(x) <> Classic.names(t)

# A TokenRequest answer's token ("" when it failed).
def Classic.token_of(+j: J.Json) -> String:
  S.Svc.str(J.Json.at(j, ["status", "token"]))

def Classic.toks_ok(ts: List<&2, P.Tok>) -> Bool:
  match ts:
    case Nil{}:
      True{}
    case Con{P.Tok{s, +t}, r}:
      Bool.and(Bool.not(String.is_empty(t)), Classic.toks_ok(r))

# A pod step whose token requests failed retries instead.
def Classic.guard(ok: Bool, a: Act) -> Act:
  match ok:
    case True{}:
      a
    case False{}:
      Act{[], S.NoRequeue{}, "service account token request failed"}

# Why a pod step must wait instead ("" when it may run): its token
# requests failed, or kube is False: the host pod is still to be created
# and the vcluster's host Service is missing (SyncToHost translates the
# pod; pods/translate.go findKubernetesIP returns the Get error, and the
# Service's cluster IP is KUBERNETES_SERVICE_HOST).
def Classic.wait_reason.kube(kube: Bool) -> String:
  match kube:
    case False{}:
      "vcluster service not found"
    case True{}:
      ""

def Classic.wait_reason(toks: Bool, kube: Bool) -> String:
  match toks:
    case False{}:
      "service account token request failed"
    case True{}:
      Classic.wait_reason.kube(kube)

# A virtual pod with no host pod that SyncToHost deletes instead of
# translating (pods/syncer.go: DeletionTimestamp or Status.StartTime set):
# its step needs no token and no host Service, so it never waits on them.
def Classic.pod_deletes(+v: J.Json) -> Bool:
  Bool.or(Bool.not(String.is_empty(S.Svc.str(J.Json.at(v, ["metadata", "deletionTimestamp"])))),
    Bool.not(String.is_empty(S.Svc.str(J.Json.at(v, ["status", "startTime"])))))

def Classic.hold.if(run: Bool, +why: String, a: Act) -> Act:
  match run:
    case True{}:
      a
    case False{}:
      Act{[], S.NoRequeue{}, why}

# A pod step with a wait reason retries with it and makes no calls.
def Classic.hold(+why: String, a: Act) -> Act:
  Classic.hold.if(String.is_empty(why), why, a)

def Classic.alnum.if(digit: Bool, +x: U32) -> Char:
  match digit:
    case True{}:
      Char.from_u32((x + 48 : U32))
    case False{}:
      Char.from_u32((x + 87 : U32))

# 0-9 then a-z.
def Classic.alnum(+x: U32) -> Char:
  Classic.alnum.if(U32.is_lt(x, 10), x)

def Classic.next(+x: U32) -> U32:
  (x * 1664525 + 1013904223 : U32)

# n characters of [0-9a-z] from a seed (random.String's alphabet, from a
# linear congruential generator).
def Classic.rand_str(n: Nat, +x: U32) -> String:
  match n:
    case 0n:
      ""
    case 1n+p:
      SCon{Classic.alnum(((x / 65536) % 36 : U32)), Classic.rand_str(p, Classic.next(x))}

# newGUID: "not a real guid ... it should just look right".
def Classic.guid(+x: U32) -> String:
  Classic.rand_str(8n, x) ++ "-" ++ Classic.rand_str(4n, (x + 1 : U32)) ++ "-" ++ Classic.rand_str(4n, (x + 2 : U32))
    ++ "-" ++ Classic.rand_str(4n, (x + 3 : U32)) ++ "-" ++ Classic.rand_str(12n, (x + 4 : U32))

# Nodes
# -----

# The fake node syncer's configuration: proxyKubelets byHostname and byIP
# (both on in chart/values.yaml), the guest's architecture, the time and
# three random IDs.
def Classic.fake(+now: String, +seed: U32) -> ND.Fake:
  ND.Fake{True{}, True{}, "arm64", now, Classic.guid(seed), Classic.guid((seed + 101 : U32)),
    Classic.guid((seed + 202 : U32))}

# The fake node syncer for node name: ip is the fake kubelet's address.
def Classic.nodes(+f: ND.Fake, +name: String, +ip: String, node: Maybe<&2, J.Json>, +vpods: List<&2, J.Json>,
  +hpods: List<&2, J.Json>) -> Act:
  Classic.node_act(ND.Node.fake_step(f, name, ip, node, vpods, hpods))

# Real nodes (nodes/syncer.go): sync.fromHost.nodes.selector (all, or the
# labels; none matches the nodes a pod needs), the virtual scheduler,
# clearImageStatus and enforceTolerations at their chart defaults (false,
# none), proxyKubelets, and NODE_NAME unset (the syncer runs in the guest,
# on no host node).
def Classic.selector(all: Bool, +labels: J.Json) -> ND.Selector:
  match all:
    case True{}:
      ND.SelAll{}
    case False{}:
      ND.SelLabels{S.Svc.map(labels)}

def Classic.node_opts(+on: J.Json) -> ND.Opts:
  ND.Opts{Classic.selector(V.Config.nodes_all(on), V.Config.nodes_labels(on)), V.Config.virtual_scheduler(on), False{},
    V.Config.proxy_by_hostname(on), V.Config.proxy_by_ip(on), [], "", False{}}

# The nodes syncer: no Options (no object caching), a mirror mapper.
def Classic.rnode_core(+c: S.Cfg) -> C.Cfg:
  C.Cfg{S.Svc.vc(c), S.Svc.target(c), "/v1, Kind=Node", "node", False{}, True{}, False{}}

def Classic.rnodes_dispatch(d: C.Decision, +c: S.Cfg, +o: ND.Opts, +ip: String, +vpods: List<&2, J.Json>,
  +hpods: List<&2, J.Json>, pods: List<&2, J.Json>) -> S.Outcome:
  match d:
    case C.DSkip{}:
      S.Svc.done([])
    case C.DRequeue{}:
      S.Outcome{[], S.RequeueNow{}}
    case C.DRequeueAfter{ms}:
      S.Outcome{[], S.RequeueAfter{RT.Runtime.seconds(ms)}}
    case C.DDeleteHost{h, reason}:
      S.Svc.done([])
    case C.DToHost{ho, v}:
      ND.Node.sync_to_host(c, ho, v)
    case C.DToVirtual{vo, h}:
      ND.Node.sync_to_virtual(o, h, vpods, hpods)
    case C.DSync{vo, v, ho, h}:
      ND.Node.sync(c, o, ip, h, v, vpods, hpods, pods)

# One real node reconcile: the virtual and the host node, the pods in the
# stores, and (with the virtual scheduler) the host pods on the node, whose
# requests come off its allocatable. Host nodes are always managed (the
# nodes mapper is a mirror mapper).
def Classic.rnodes(+c: S.Cfg, +on: J.Json, +ip: String, vo: Maybe<&2, J.Json>, +v: Maybe<&2, J.Json>,
  ho: Maybe<&2, J.Json>, +h: Maybe<&2, J.Json>, +vpods: List<&2, J.Json>, +hpods: List<&2, J.Json>,
  pods: List<&2, J.Json>) -> Act:
  Classic.rnode_act(Classic.rnodes_dispatch(C.Core.decide(Classic.rnode_core(c), Maybe.is_some(&2, J.Json, h), vo, v, ho, h),
    c, Classic.node_opts(on), ip, vpods, hpods, pods))


# vk8s: with proxyKubelets off (vcluster's conformance profile) real nodes
# keep the host's addresses, so NodePorts and node-to-pod traffic work as on
# the host; but the VM cannot reach host kubelets with its credentials (in
# vcluster the syncer serves pod logs and exec itself). The kubelet port of
# each virtual node becomes the NodePort of the vcluster's <vc>-kubelet
# Service, which leads from every host node to the fake kubelet; the API
# server's kubelet traffic gets there through the konnectivity agent.
def Classic.kubelet_service(+vc: String) -> String:
  vc ++ "-kubelet"

def Classic.first_json(xs: List<&2, J.Json>) -> J.Json:
  match xs:
    case Nil{}:
      J.JNull{}
    case Con{x, t}:
      x

# The Service's first nodePort ("null" without one).
def Classic.kubelet_node_port(+svc: J.Json) -> String:
  J.Json.show(J.Json.get(Classic.first_json(J.Json.items(J.Json.at(svc, ["spec", "ports"]))), "nodePort"))

def Classic.kport_if(hit: Bool, +port: String, +o: J.Json) -> J.Json:
  match hit:
    case True{}:
      S.Svc.put(o, "status", S.Svc.put(J.Json.get(o, "status"), "daemonEndpoints",
        J.Json.obj([J.KV{"kubeletEndpoint", J.Json.obj([J.KV{"Port", J.JNum{port}}])}])))
    case False{}:
      o

def Classic.kport_op(+port: String, o: Op) -> Op:
  match o:
    case OCreate{+h, +r, +x}:
      OCreate{h, r, Classic.kport_if(Bool.and(Bool.not(h), String.eq(r, "nodes")), port, x)}
    case OUpdate{+h, +r, +x}:
      OUpdate{h, r, Classic.kport_if(Bool.and(Bool.not(h), String.eq(r, "nodes")), port, x)}
    case OStatus{+h, +r, +x}:
      OStatus{h, r, Classic.kport_if(Bool.and(Bool.not(h), String.eq(r, "nodes")), port, x)}
    case other:
      other

def Classic.kport_ops(+port: String, os: List<&2, Op>) -> List<&2, Op>:
  match os:
    case Nil{}:
      []
    case Con{o, t}:
      Classic.kport_op(port, o) <> Classic.kport_ops(port, t)

def Classic.kport_act(on: Bool, +port: String, a: Act) -> Act:
  match on:
    case True{}:
      match a:
        case Act{os, rq, e}:
          Act{Classic.kport_ops(port, os), rq, e}
    case False{}:
      a

# Whether the kubelet port is rewritten: a NodePort is known and neither
# proxyKubelets mode rewrites the addresses.
def Classic.kport_on(+port: String, +on: J.Json) -> Bool:
  Bool.and(Bool.not(Bool.or(String.is_empty(port), String.eq(port, "null"))),
    Bool.not(Bool.or(V.Config.proxy_by_hostname(on), V.Config.proxy_by_ip(on))))

def Classic.rnodes_k(+c: S.Cfg, +on: J.Json, +ip: String, +kport: String, vo: Maybe<&2, J.Json>, +v: Maybe<&2, J.Json>,
  ho: Maybe<&2, J.Json>, +h: Maybe<&2, J.Json>, +vpods: List<&2, J.Json>, +hpods: List<&2, J.Json>,
  pods: List<&2, J.Json>) -> Act:
  Classic.kport_act(Classic.kport_on(kport, on), kport, Classic.rnodes(c, on, ip, vo, v, ho, h, vpods, hpods, pods))

# vk8s: vcluster creates a virtual Service's host Service first and gives
# the virtual one the host's cluster IP and ports, in its proxy in front of
# the API server (pkg/server/filters/service.go createService), so a client
# never sees the address change. vk8s has no such proxy, so it reaches the
# same end from the other side: both API servers allocate from the host's
# service CIDR, and the host Service asks for the virtual one's cluster IP
# and node ports. If the host refuses them (taken), the syncer creates the
# translated Service (vcluster's translate: address cleared, node ports
# stripped) and recreates the virtual one, as vcluster's syncer does.
def Classic.is_services(k: RT.Resource) -> Bool:
  match k:
    case RT.KServices{}:
      True{}
    case _:
      False{}

def Classic.svc_vns(+h: J.Json) -> String:
  S.Svc.str(J.Json.at(h, ["metadata", "annotations", M.Meta.namespace_annotation()]))

def Classic.svc_vname(+h: J.Json) -> String:
  S.Svc.str(J.Json.at(h, ["metadata", "annotations", M.Meta.name_annotation()]))

def Classic.svc_prefer(+h: J.Json, +v: J.Json) -> J.Json:
  +vs = J.Json.get(v, "spec")
  S.Svc.put(h, "spec", S.Svc.put(S.Svc.put(S.Svc.put(J.Json.get(h, "spec"),
    "clusterIP", J.Json.get(vs, "clusterIP")), "clusterIPs", J.Json.get(vs, "clusterIPs")), "ports", J.Json.get(vs, "ports")))

# An update of a host Service that leaves it without a cluster IP, as a
# change from ExternalName to ClusterIP does (vcluster: updateService in the
# same proxy filter), asks for the virtual one's too.
def Classic.svc_wants_ip(+h: J.Json) -> Bool:
  +ip = S.Svc.str(J.Json.at(h, ["spec", "clusterIP"]))
  Bool.and(String.is_empty(ip), Bool.not(String.eq(S.Svc.str(J.Json.at(h, ["spec", "type"])), "ExternalName")))

# Storage
# -------

# persistentvolumeclaims Options: DisableUIDDeletion, ObjectCaching.
def Classic.pvc_core(+c: S.Cfg) -> C.Cfg:
  C.Cfg{S.Svc.vc(c), S.Svc.target(c), SG.St.pvc_kind(), "persistentvolumeclaim", True{}, False{}, False{}}

# sync.toHost storageClasses and volumeSnapshots, and fake volumes unless
# sync.toHost.persistentVolumes is enabled.
def Classic.pvc_cfg(+on: J.Json) -> SG.PvcCfg:
  SG.PvcCfg{V.Config.to_host(on, "storageClasses"), V.Config.to_host(on, "volumeSnapshots"),
    Bool.not(V.Config.to_host(on, "persistentVolumes"))}

# What a claim sync reads: no class limits, the host class (only read with
# real volumes), the virtual volume the host claim names, no real volume
# name, the time.
def Classic.pvc_look(pv: Maybe<&2, J.Json>, now: String) -> SG.PvcLook:
  SG.PvcLook{False{}, True{}, pv, "", now}

def Classic.pvcs_dispatch(d: C.Decision, +c: S.Cfg, +p: SG.PvcCfg, +l: SG.PvcLook) -> SG.Outcome:
  match d:
    case C.DSkip{}:
      SG.St.done([])
    case C.DRequeue{}:
      SG.Outcome{[], S.RequeueNow{}, ""}
    case C.DRequeueAfter{ms}:
      SG.Outcome{[], S.RequeueAfter{RT.Runtime.seconds(ms)}, ""}
    case C.DDeleteHost{h, reason}:
      SG.St.done([SG.St.delete_host(h, SG.St.nodel())])
    case C.DToHost{ho, v}:
      SG.St.Pvc.to_host(c, p, l, ho, v)
    case C.DToVirtual{vo, h}:
      SG.St.Pvc.to_virtual(c, vo, h)
    case C.DSync{vo, +v, ho, +h}:
      SG.St.Pvc.sync(c, p, l, Maybe.default(&2, J.Json, ho, h), h, Maybe.default(&2, J.Json, vo, v), v)

# One claim reconcile.
def Classic.pvcs(+c: S.Cfg, +on: J.Json, +l: SG.PvcLook, +hname: String,
  vo: Maybe<&2, J.Json>, +v: Maybe<&2, J.Json>, ho: Maybe<&2, J.Json>, +h: Maybe<&2, J.Json>) -> Act:
  Classic.st_act(Classic.pvcs_dispatch(C.Core.decide(Classic.pvc_core(c), Classic.managed(Classic.pvc_core(c), hname, h), vo, v, ho, h),
    c, Classic.pvc_cfg(on), l), "persistentvolumeclaims")

# With real volumes, a claim sync reads the virtual volume named like the
# host claim's volume (pv_name: persistentVolumeMapper.HostToVirtual of it).
def Classic.pvc_look_real(pv: Maybe<&2, J.Json>, pv_name: String, now: String) -> SG.PvcLook:
  SG.PvcLook{False{}, True{}, pv, pv_name, now}

# The virtual name of the host volume hvol, from the host volume when it
# was read.
def Classic.pv_vname_of(+hvol: String, m: Maybe<&2, J.Json>) -> String:
  match m:
    case None{}:
      hvol
    case Some{+o}:
      Classic.pv_vname(o)

# Real volumes (persistentvolumes/syncer.go).

# The host name of virtual volume name (mappings/resources/
# persistentvolumes.go VirtualToHost): without a virtual volume the name
# itself; else its vcluster.loft.sh/host-pv annotation, or HostNameCluster.
def Classic.pv_host_name(+c: S.Cfg, +name: String, v: Maybe<&2, J.Json>) -> String:
  match v:
    case None{}:
      name
    case Some{+o}:
      +ann = S.Svc.annotation(SG.St.host_pv(), o)
      Classic.or_name(String.is_empty(ann), ann, SG.St.cluster_name(c, name))

def Classic.pv_claim.hit(hit: Bool, p: J.Json, rest: SG.Claim) -> SG.Claim:
  match hit:
    case True{}:
      SG.Found{p}
    case False{}:
      rest

def Classic.pv_claim.in(+c: S.Cfg, +name: String, ps: List<&2, J.Json>) -> SG.Claim:
  match ps:
    case Nil{}:
      SG.Missing{}
    case Con{+p, t}:
      Classic.pv_claim.hit(String.eq(RT.Runtime.host_name(S.Svc.vc(c), S.Svc.namespace(p), S.Svc.name(p)), name), p,
        Classic.pv_claim.in(c, name, t))

def Classic.pv_claim.find(targeted: Bool, +c: S.Cfg, +name: String, ps: List<&2, J.Json>) -> SG.Claim:
  match targeted:
    case True{}:
      Classic.pv_claim.in(c, name, ps)
    case False{}:
      SG.Unmapped{}

# The virtual claim of a host volume: the virtual claim whose host claim
# its claim ref names; Missing for a claim ref into the host namespace
# that no virtual claim maps to, Unmapped for any other.
def Classic.pv_claim(+c: S.Cfg, h: Maybe<&2, J.Json>, ps: List<&2, J.Json>) -> SG.Claim:
  match h:
    case None{}:
      SG.Unmapped{}
    case Some{+o}:
      Classic.pv_claim.find(String.eq(S.Svc.str(J.Json.at(o, ["spec", "claimRef", "namespace"])), S.Svc.target(c)), c,
        S.Svc.str(J.Json.at(o, ["spec", "claimRef", "name"])), ps)

# IsManaged of a host volume: vcluster made it (the cluster marker), or it
# is bound to a claim in the host namespace (vcluster's mapping store
# records the volumes of synced claims).
def Classic.pv_managed(+c: S.Cfg, h: Maybe<&2, J.Json>) -> Bool:
  match h:
    case None{}:
      False{}
    case Some{+o}:
      Bool.or(SG.St.Pv.managed(c, o), String.eq(S.Svc.str(J.Json.at(o, ["spec", "claimRef", "namespace"])), S.Svc.target(c)))

# persistentvolumes Options: DisableUIDDeletion, ObjectCaching.
def Classic.pv_core(+c: S.Cfg) -> C.Cfg:
  C.Cfg{S.Svc.vc(c), S.Svc.target(c), SG.St.pv_kind(), "persistentvolume", True{}, False{}, False{}}

# limited (applyLimitByClass) is false without a storage class selector;
# locked reads false (the lock annotation is not timed here).
def Classic.rpvs_dispatch(d: C.Decision, +c: S.Cfg, +classes: Bool, +claim: SG.Claim) -> SG.Outcome:
  match d:
    case C.DSkip{}:
      SG.St.done([])
    case C.DRequeue{}:
      SG.Outcome{[], S.RequeueNow{}, ""}
    case C.DRequeueAfter{ms}:
      SG.Outcome{[], S.RequeueAfter{RT.Runtime.seconds(ms)}, ""}
    case C.DDeleteHost{h, reason}:
      SG.St.done([SG.St.delete_host(h, SG.St.nodel())])
    case C.DToHost{ho, v}:
      SG.St.Pv.to_host(c, False{}, ho, v)
    case C.DToVirtual{vo, h}:
      SG.St.Pv.to_virtual(c, claim, h)
    case C.DSync{vo, +v, ho, +h}:
      SG.St.Pv.sync(c, classes, SG.PvLook{False{}, False{}, claim}, Maybe.default(&2, J.Json, ho, h), h,
        Maybe.default(&2, J.Json, vo, v), v)

# One real volume reconcile: both volumes and the virtual claims.
def Classic.rpvs(+c: S.Cfg, +on: J.Json, vo: Maybe<&2, J.Json>, +v: Maybe<&2, J.Json>, ho: Maybe<&2, J.Json>,
  +h: Maybe<&2, J.Json>, +vpvcs: List<&2, J.Json>) -> Act:
  Classic.cst_act(Classic.rpvs_dispatch(C.Core.decide(Classic.pv_core(c), Classic.pv_managed(c, h), vo, v, ho, h), c,
    V.Config.to_host(on, "storageClasses"), Classic.pv_claim(c, h, vpvcs)), "persistentvolumes")

# Storage and priority classes to the host (storageclasses/syncer.go,
# priorityclasses/syncer.go): the host object is named HostNameCluster.
def Classic.cluster_host_name(+c: S.Cfg, name: String) -> String:
  SG.St.cluster_name(c, name)

# storageclasses Options: ObjectCaching.
def Classic.sc_core(+c: S.Cfg) -> C.Cfg:
  C.Cfg{S.Svc.vc(c), S.Svc.target(c), SG.St.sc_kind(), "storageclass", True{}, True{}, False{}}

def Classic.scs_dispatch(d: C.Decision, +c: S.Cfg) -> SG.Outcome:
  match d:
    case C.DSkip{}:
      SG.St.done([])
    case C.DRequeue{}:
      SG.Outcome{[], S.RequeueNow{}, ""}
    case C.DRequeueAfter{ms}:
      SG.Outcome{[], S.RequeueAfter{RT.Runtime.seconds(ms)}, ""}
    case C.DDeleteHost{h, reason}:
      SG.St.done([SG.St.delete_host(h, SG.St.nodel())])
    case C.DToHost{ho, v}:
      SG.St.Sc.to_host(c, ho, v)
    case C.DToVirtual{vo, h}:
      SG.St.Sc.to_virtual(h)
    case C.DSync{vo, +v, ho, +h}:
      SG.St.Sc.sync(c, Maybe.default(&2, J.Json, ho, h), h, Maybe.default(&2, J.Json, vo, v), v)

def Classic.scs(+c: S.Cfg, +name: String, vo: Maybe<&2, J.Json>, +v: Maybe<&2, J.Json>, ho: Maybe<&2, J.Json>,
  +h: Maybe<&2, J.Json>) -> Act:
  Classic.cst_act(Classic.scs_dispatch(C.Core.decide(Classic.sc_core(c),
    Classic.managed(Classic.sc_core(c), Classic.cluster_host_name(c, name), h), vo, v, ho, h), c), "storageclasses")

# priorityclasses Options: ObjectCaching. Only toHost runs here.
def Classic.pc_core(+c: S.Cfg) -> C.Cfg:
  C.Cfg{S.Svc.vc(c), S.Svc.target(c), SG.St.pc_kind(), "priorityclass", True{}, True{}, False{}}

# sync.fromHost.priorityClasses.selector is outside the vcluster.yaml
# subset: the empty selector matches every class.
def Classic.pcs_dispatch(d: C.Decision, +c: S.Cfg, +f: SG.PcCfg) -> SG.Outcome:
  match d:
    case C.DSkip{}:
      SG.St.done([])
    case C.DRequeue{}:
      SG.Outcome{[], S.RequeueNow{}, ""}
    case C.DRequeueAfter{ms}:
      SG.Outcome{[], S.RequeueAfter{RT.Runtime.seconds(ms)}, ""}
    case C.DDeleteHost{h, reason}:
      SG.St.done([SG.St.delete_host(h, SG.St.nodel())])
    case C.DToHost{ho, v}:
      SG.St.Pc.to_host(c, f, ho, v)
    case C.DToVirtual{vo, h}:
      SG.St.Pc.to_virtual(c, f, True{}, vo, h)
    case C.DSync{vo, +v, ho, +h}:
      SG.St.Pc.sync(c, f, True{}, Maybe.default(&2, J.Json, ho, h), h, Maybe.default(&2, J.Json, vo, v), v)

def Classic.pcs(+c: S.Cfg, +on: J.Json, +name: String, vo: Maybe<&2, J.Json>, +v: Maybe<&2, J.Json>, ho: Maybe<&2, J.Json>,
  +h: Maybe<&2, J.Json>) -> Act:
  Classic.cst_act(Classic.pcs_dispatch(C.Core.decide(Classic.pc_core(c),
    Classic.managed(Classic.pc_core(c), Classic.cluster_host_name(c, name), h), vo, v, ho, h), c,
    SG.PcCfg{V.Config.to_host(on, "priorityClasses"), False{}}), "priorityclasses")

# The step of a storage or priority class key.
def Classic.class_step(id: String, +c: S.Cfg, +on: J.Json, +name: String, vo: Maybe<&2, J.Json>, +v: Maybe<&2, J.Json>,
  ho: Maybe<&2, J.Json>, +h: Maybe<&2, J.Json>) -> Act:
  match id:
    case "storageclasses":
      Classic.scs(c, name, vo, v, ho, h)
    case "priorityclasses":
      Classic.pcs(c, on, name, vo, v, ho, h)
    case _:
      Act{[], S.NoRequeue{}, ""}

# CSINodes from the host (csinodes/syncer.go): a mirror mapper, no Options.
# exists: the virtual cluster has the node of that name.
def Classic.csi_core(+c: S.Cfg) -> C.Cfg:
  C.Cfg{S.Svc.vc(c), S.Svc.target(c), "storage.k8s.io/v1, Kind=CSINode", "csinode", False{}, True{}, False{}}

def Classic.csis_dispatch(d: C.Decision, +c: S.Cfg, +exists: Bool) -> SG.Outcome:
  match d:
    case C.DSkip{}:
      SG.St.done([])
    case C.DRequeue{}:
      SG.Outcome{[], S.RequeueNow{}, ""}
    case C.DRequeueAfter{ms}:
      SG.Outcome{[], S.RequeueAfter{RT.Runtime.seconds(ms)}, ""}
    case C.DDeleteHost{h, reason}:
      SG.St.done([])
    case C.DToHost{ho, v}:
      SG.St.Csi.to_host(c, ho, v)
    case C.DToVirtual{vo, h}:
      SG.St.Csi.to_virtual(exists, h)
    case C.DSync{vo, v, ho, h}:
      SG.St.Csi.sync(c, exists, h, v)

def Classic.csinodes(+c: S.Cfg, exists: Bool, vo: Maybe<&2, J.Json>, +v: Maybe<&2, J.Json>, ho: Maybe<&2, J.Json>,
  +h: Maybe<&2, J.Json>) -> Act:
  Classic.cst_act(Classic.csis_dispatch(C.Core.decide(Classic.csi_core(c), Maybe.is_some(&2, J.Json, h), vo, v, ho, h), c, exists),
    "csinodes")

# The fake volume syncer for volume name: FakeSyncToVirtual when there is
# no virtual volume, else FakeSync.
def Classic.pvs(+name: String, pv: Maybe<&2, J.Json>, +pvcs: List<&2, J.Json>) -> Act:
  match pv:
    case None{}:
      Classic.st_act(SG.St.Fake.to_virtual(name, pvcs), "persistentvolumes")
    case Some{p}:
      Classic.st_act(SG.St.Fake.sync(p, pvcs), "persistentvolumes")

# Events
# ------

# The resource of an event's involved object, for the kinds the events
# mapper accepts ("" for the others, whose objects are never found).
def Classic.involved_res(k: String) -> String:
  match k:
    case "Pod":
      "pods"
    case "Service":
      "services"
    case "Secret":
      "secrets"
    case "ConfigMap":
      "configmaps"
    case _:
      ""

def Classic.live.if(terminating: Bool, ns: String) -> +List<String>:
  match terminating:
    case True{}:
      []
    case False{}:
      [ns]

# The live virtual namespaces among one: [ns] when it exists and is not
# terminating.
def Classic.live(+ns: String, m: Maybe<&2, J.Json>) -> +List<String>:
  match m:
    case None{}:
      []
    case Some{+n}:
      Classic.live.if(String.eq(S.Svc.str(J.Json.at(n, ["status", "phase"])), "Terminating"), ns)

# The namespace whose liveness an event needs: its virtual object's, or
# the forced events' namespace.
def Classic.event_ns(found: Maybe<&2, J.Json>) -> String:
  match found:
    case None{}:
      ND.Ev.force_namespace()
    case Some{+v}:
      S.Svc.namespace(v)

# eventSyncer: a host event without a virtual one is SyncToVirtual, with
# one Sync; a missing host event does nothing (SyncToHost).
def Classic.events_step(h: Maybe<&2, J.Json>, found: Maybe<&2, J.Json>, +live: +List<String>, ve: Maybe<&2, J.Json>) -> S.Outcome:
  match h ve:
    case None{} x:
      S.Svc.done([])
    case Some{e} None{}:
      ND.Ev.sync_to_virtual(e, found, live)
    case Some{e} Some{y}:
      ND.Ev.sync(e, found, y)

def Classic.events(h: Maybe<&2, J.Json>, found: Maybe<&2, J.Json>, +live: +List<String>, ve: Maybe<&2, J.Json>) -> Act:
  Classic.act(Classic.events_step(h, found, live, ve), "events")

# The volume a host claim names ("" when there is no claim).
def Classic.volume_of(m: Maybe<&2, J.Json>) -> String:
  match m:
    case None{}:
      ""
    case Some{+h}:
      S.Svc.spec_str(h, "volumeName")

# The resource of a host event's involved object.
def Classic.ev_res(+h: J.Json) -> String:
  Classic.involved_res(S.Svc.str(J.Json.at(h, ["involvedObject", "kind"])))

def Classic.ev_hname.if(none: Bool, +h: J.Json) -> String:
  match none:
    case True{}:
      ""
    case False{}:
      S.Svc.str(J.Json.at(h, ["involvedObject", "name"]))

# The host name of a host event's involved object ("" for a kind the
# events mapper does not accept).
def Classic.ev_hname(+h: J.Json) -> String:
  Classic.ev_hname.if(String.is_empty(Classic.ev_res(h)), h)

# The virtual namespace and name a host object's annotations give ("" when
# there is no object).
def Classic.obj_ns(m: Maybe<&2, J.Json>) -> String:
  match m:
    case None{}:
      ""
    case Some{+o}:
      S.Svc.annotation(M.Meta.namespace_annotation(), o)

def Classic.obj_name(m: Maybe<&2, J.Json>) -> String:
  match m:
    case None{}:
      ""
    case Some{+o}:
      S.Svc.annotation(M.Meta.name_annotation(), o)

# The virtual event of a host event (Ev.virtual_ref).
def Classic.event_ref(+h: J.Json, found: Maybe<&2, J.Json>) -> String & String:
  ND.Ev.virtual_ref(h, found)

def Classic.fst(p: String & String) -> String:
  match p:
    case (a, b):
      a

def Classic.snd(p: String & String) -> String:
  match p:
    case (a, b):
      b

# The namespace and the name of the virtual event, one at a time: the pair
# that Classic.event_ref gives is not Data, so a caller cannot reuse it.
def Classic.event_vns(+h: J.Json, found: Maybe<&2, J.Json>) -> String:
  Classic.fst(Classic.event_ref(h, found))

def Classic.event_vname(+h: J.Json, found: Maybe<&2, J.Json>) -> String:
  Classic.snd(Classic.event_ref(h, found))

# Syncer flags of the fake kubelet: its address on the guest's LAN (the
# fake nodes' InternalIP; vk8s's control plane is 10.10.0.2), its serving
# certificate and key, the CA of its clients' certificates, and the
# directory where inline kubeconfig credentials are written for it. It
# listens on vcluster's constants.KubeletPort, 10250.
type KFlags is Data:
  KFlags{ip: String, cert: String, key: String, ca: String, dir: String}

def Classic.kflags(+args: +List<String>) -> KFlags:
  KFlags{RT.Runtime.flag_or(args, "--kubelet-ip", "10.10.0.2"),
    RT.Runtime.flag_or(args, "--kubelet-cert", "/var/lib/vcluster/pki/kubelet-serving.crt"),
    RT.Runtime.flag_or(args, "--kubelet-key", "/var/lib/vcluster/pki/kubelet-serving.key"),
    RT.Runtime.flag_or(args, "--kubelet-client-ca", "/var/lib/vcluster/pki/ca.crt"),
    RT.Runtime.flag_or(args, "--kubelet-dir", "/var/lib/vcluster/pki")}

def Classic.kubelet_port() -> U32:
  10250

def KFlags.ip(k: KFlags) -> String:
  match k:
    case KFlags{i, c, y, a, d}:
      i

def KFlags.cert(k: KFlags) -> String:
  match k:
    case KFlags{i, c, y, a, d}:
      c

def KFlags.key(k: KFlags) -> String:
  match k:
    case KFlags{i, c, y, a, d}:
      y

def KFlags.ca(k: KFlags) -> String:
  match k:
    case KFlags{i, c, y, a, d}:
      a

def KFlags.dir(k: KFlags) -> String:
  match k:
    case KFlags{i, c, y, a, d}:
      d
