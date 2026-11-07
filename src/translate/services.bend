import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ./meta.bend as M
import ./names.bend as N

# Services, endpoints and endpoint slices (vcluster
# pkg/controllers/resources/services, endpoints, endpointslices and
# pkg/specialservices), as pure functions of object snapshots.
#
# Objects are bend-kube JSON values (J.Json), as the API server sends them.
# Each syncer step takes the snapshots vcluster's generic syncer hands it
# (host old/new, virtual old/new, or the subset a step reads) and returns
# the writes to make, in a fixed order: host writes before virtual writes,
# a delete before the create that replaces it. A write carries the whole new
# object; an update is returned only when the object changes.
#
# Equality of objects (Svc.eq) is Kubernetes equality up to Go's omitempty:
# object members are compared by key, and a member whose value is null,
# false, 0, [] or {} counts as absent (Svc.canon). Strings are kept, because
# label and annotation values may be "".
#
# Single-namespace mode only. The vcluster name, the target (host) namespace
# and the namespace vcluster runs in are parameters (Cfg), not globals.
# Translate patches (Pro) are not supported and owner references
# (translate.Owner) are not modelled. Name mapping uses the pure name
# translation (names.bend); vcluster's mapping store is not modelled.
#
# vcluster quirks kept as they are:
# - The host kubernetes.io/service-name label of an endpoint slice is the
#   plain concatenation <service>-x-<namespace>-x-<vcluster> (no
#   SafeConcatName, so it may pass 63 characters), read from the host
#   labels after translation (endpointslices/translate.go:17-25, 47-49).
# - Endpoints clear the UID and resource version of a Pod target ref; endpoint
#   slices keep them (endpoints/translate.go:20-46,
#   endpointslices/translate.go:28-37).
# - A selector-less service is the only one whose endpoints and endpoint
#   slices are synced; a host object that vcluster did not make is deleted
#   first, and for a selector service a host object that vcluster made is
#   deleted so that Kubernetes takes it over.
# - On update, the node ports of the virtual service go to the host as they
#   are; only creation strips them (services/translate.go:28).
# - The special default/kubernetes service recreates the virtual service
#   keeping its UID and clearing only the resource version
#   (specialservices/service_syncer.go:76).

# The vcluster name (translate.VClusterName), the target namespace of host
# objects, and the namespace vcluster runs in (ctx.CurrentNamespace).
type Cfg is Data:
  Cfg{vc: String, target: String, current: String}

# corev1.ServicePort. Each field is the JSON value (JNull when absent).
type Port is Data:
  Port{name: J.Json, protocol: J.Json, app_protocol: J.Json, port: J.Json, target_port: J.Json, node_port: J.Json}

# A write to the host or the virtual cluster.
type Write is Data:
  HostCreate{obj: J.Json}
  HostUpdate{obj: J.Json}
  HostDelete{namespace: String, name: String}
  VirtualCreate{obj: J.Json}
  VirtualUpdate{obj: J.Json}
  VirtualDelete{namespace: String, name: String}

# ctrl.Result: no requeue, Requeue: true, or RequeueAfter seconds.
type Requeue is Data:
  NoRequeue{}
  RequeueNow{}
  RequeueAfter{seconds: U32}

# The writes of one sync step and its requeue.
type Outcome is Data:
  Outcome{writes: List<&2, Write>, requeue: Requeue}

# The result of a syncer's ReconcileStart: skip says the generic sync does
# not run; err is the error text, "" for none.
type Start is Data:
  Start{skip: Bool, writes: List<&2, Write>, err: String}

# One spec field after patcher.CopyBidirectional: its new virtual and host
# values.
type Pick is Data:
  Pick{key: String, virtual: J.Json, host: J.Json}

# Configuration.

def Svc.vc(c: Cfg) -> String:
  match c:
    case Cfg{vc, target, current}:
      vc

def Svc.target(c: Cfg) -> String:
  match c:
    case Cfg{vc, target, current}:
      target

def Svc.current(c: Cfg) -> String:
  match c:
    case Cfg{vc, target, current}:
      current

# Constants.

def Svc.kind() -> String:
  "/v1, Kind=Service"

def Svc.endpoints_kind() -> String:
  "/v1, Kind=Endpoints"

def Svc.slice_kind() -> String:
  "discovery.k8s.io/v1, Kind=EndpointSlice"

# services.ServiceBlockDeletion.
def Svc.block_deletion() -> String:
  "vcluster.loft.sh/block-deletion"

# services.RancherPublicEndpointsAnnotation, excluded from service sync.
def Svc.rancher() -> String:
  "field.cattle.io/publicEndpoints"

# Excluded from endpoints and endpoint slice sync.
def Svc.leader() -> String:
  "control-plane.alpha.kubernetes.io/leader"

# translate.K8sServiceNameLabel.
def Svc.service_name_label() -> String:
  "kubernetes.io/service-name"

# The metadata fields translate.ResetObjectMetadata clears.
def Svc.reset_keys() -> +List<String>:
  ["generateName", "selfLink", "uid", "resourceVersion", "generation", "creationTimestamp",
   "deletionTimestamp", "deletionGracePeriodSeconds", "ownerReferences", "finalizers", "managedFields"]

# JSON.

def Svc.str(j: J.Json) -> String:
  J.Json.str_or(j, "")

def Svc.sj.if(empty: Bool, s: String) -> J.Json:
  match empty:
    case True{}:
      J.JNull{}
    case False{}:
      J.JStr{s}

# A string field: null for "".
def Svc.sj(+s: String) -> J.Json:
  Svc.sj.if(String.is_empty(s), s)

def Svc.put.if(isnull: Bool, j: J.Json, k: String, v: J.Json) -> J.Json:
  match isnull:
    case True{}:
      J.Json.del(j, k)
    case False{}:
      J.Json.set(j, k, v)

# j[k] = v, or delete(j, k) when v is null.
def Svc.put(j: J.Json, +k: String, +v: J.Json) -> J.Json:
  Svc.put.if(J.Json.is_null(v), j, k, v)

# o[outer][k] = v, as Svc.put.
def Svc.put_in(+o: J.Json, +outer: String, +k: String, +v: J.Json) -> J.Json:
  Svc.put(o, outer, Svc.put(J.Json.get(o, outer), k, v))

def Svc.del_all(ks: +List<String>, j: J.Json) -> J.Json:
  match ks:
    case Nil{}:
      j
    case Con{k, r}:
      Svc.del_all(r, J.Json.del(j, k))

def Svc.name(+o: J.Json) -> String:
  Svc.str(J.Json.at(o, ["metadata", "name"]))

def Svc.namespace(+o: J.Json) -> String:
  Svc.str(J.Json.at(o, ["metadata", "namespace"]))

def Svc.spec_str(+o: J.Json, +k: String) -> String:
  Svc.str(J.Json.at(o, ["spec", k]))

# Canonical form and equality.

def Svc.is_nil(j: J.Json) -> Bool:
  match j:
    case J.JNil{}:
      True{}
    case _:
      False{}

# A value omitempty leaves out: null, false, 0, [] or {}.
def Svc.zero(j: J.Json) -> Bool:
  match j:
    case J.JNull{}:
      True{}
    case J.JBool{b}:
      Bool.not(b)
    case J.JNum{t}:
      String.eq(t, "0")
    case J.JArr{xs}:
      Svc.is_nil(xs)
    case J.JObj{ms}:
      Svc.is_nil(ms)
    case _:
      False{}

def Svc.insert.if(c: Cmp, k: String, v: J.Json, kk: String, vv: J.Json, t: J.Json, rec: J.Json) -> J.Json:
  match c:
    case LT{}:
      J.JMem{k, v, J.JMem{kk, vv, t}}
    case EQ{}:
      J.JMem{k, v, t}
    case GT{}:
      J.JMem{kk, vv, rec}

# Puts member k into a member chain sorted by key.
def Svc.insert(+k: String, +v: J.Json, ms: J.Json) -> J.Json:
  match ms:
    case J.JMem{+kk, vv, +t}:
      Svc.insert.if(String.order(k, kk), k, v, kk, vv, t, Svc.insert(k, v, t))
    case _:
      J.JMem{k, v, J.JNil{}}

def Svc.canon.put.if(z: Bool, k: String, v: J.Json, rest: J.Json) -> J.Json:
  match z:
    case True{}:
      rest
    case False{}:
      Svc.insert(k, v, rest)

def Svc.canon.put(k: String, +v: J.Json, rest: J.Json) -> J.Json:
  Svc.canon.put.if(Svc.zero(v), k, v, rest)

# The canonical form: object members sorted by key, members whose value is
# zero (after their own members are made canonical) dropped; array items
# keep their order.
def Svc.canon(j: J.Json) -> J.Json:
  match j:
    case J.JArr{xs}:
      J.JArr{Svc.canon(xs)}
    case J.JObj{ms}:
      J.JObj{Svc.canon(ms)}
    case J.JCons{h, t}:
      J.JCons{Svc.canon(h), Svc.canon(t)}
    case J.JMem{k, v, t}:
      Svc.canon.put(k, Svc.canon(v), Svc.canon(t))
    case x:
      x

def Svc.bool_eq(a: Bool, b: Bool) -> Bool:
  match a:
    case True{}:
      b
    case False{}:
      Bool.not(b)

# Structural equality of two JSON values.
def Svc.same(a: J.Json, b: J.Json) -> Bool:
  match a b:
    case J.JNull{} J.JNull{}:
      True{}
    case J.JBool{x} J.JBool{y}:
      Svc.bool_eq(x, y)
    case J.JNum{x} J.JNum{y}:
      String.eq(x, y)
    case J.JStr{x} J.JStr{y}:
      String.eq(x, y)
    case J.JArr{x} J.JArr{y}:
      Svc.same(x, y)
    case J.JObj{x} J.JObj{y}:
      Svc.same(x, y)
    case J.JNil{} J.JNil{}:
      True{}
    case J.JCons{h1, t1} J.JCons{h2, t2}:
      Bool.and(Svc.same(h1, h2), Svc.same(t1, t2))
    case J.JMem{k1, v1, t1} J.JMem{k2, v2, t2}:
      Bool.and(String.eq(k1, k2), Bool.and(Svc.same(v1, v2), Svc.same(t1, t2)))
    case _ _:
      False{}

def Svc.top.if(zero: Bool, j: J.Json) -> J.Json:
  match zero:
    case True{}:
      J.JNull{}
    case False{}:
      j

def Svc.is_obj(j: J.Json) -> Bool:
  match j:
    case J.JObj{ms}:
      True{}
    case _:
      False{}

# A canonical value compared as a whole: null, false, 0 and [] are absent
# (Go's semantic DeepEqual holds a nil slice equal to an empty one); {} is
# kept, as a pointer to an empty struct is not nil.
def Svc.top(+j: J.Json) -> J.Json:
  Svc.top.if(Bool.and(Svc.zero(j), Bool.not(Svc.is_obj(j))), j)

# apiequality.Semantic.DeepEqual of two values, up to omitempty.
def Svc.eq(a: J.Json, b: J.Json) -> Bool:
  Svc.same(Svc.top(Svc.canon(a)), Svc.top(Svc.canon(b)))

def Svc.canon_write(w: Write) -> Write:
  match w:
    case HostCreate{o}:
      HostCreate{Svc.canon(o)}
    case HostUpdate{o}:
      HostUpdate{Svc.canon(o)}
    case HostDelete{ns, n}:
      HostDelete{ns, n}
    case VirtualCreate{o}:
      VirtualCreate{Svc.canon(o)}
    case VirtualUpdate{o}:
      VirtualUpdate{Svc.canon(o)}
    case VirtualDelete{ns, n}:
      VirtualDelete{ns, n}

def Svc.canon_writes(ws: List<&2, Write>) -> List<&2, Write>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{w, r}:
      Svc.canon_write(w) <> Svc.canon_writes(r)

# An outcome with every object in canonical form.
def Svc.canon_outcome(o: Outcome) -> Outcome:
  match o:
    case Outcome{ws, rq}:
      Outcome{Svc.canon_writes(ws), rq}

# A start with every object in canonical form.
def Svc.canon_start(s: Start) -> Start:
  match s:
    case Start{skip, ws, e}:
      Start{skip, Svc.canon_writes(ws), e}

# String maps.

def Svc.kvs.put(k: String, v: J.Json, rec: +List<M.KV>) -> +List<M.KV>:
  match v:
    case J.JStr{s}:
      M.Meta.insert(k, s, rec)
    case _:
      rec

def Svc.kvs(ms: J.Json) -> +List<M.KV>:
  match ms:
    case J.JMem{k, v, t}:
      Svc.kvs.put(k, v, Svc.kvs(t))
    case _:
      Nil{}

# A JSON string map as a canonical map; None when it is absent (Go nil).
def Svc.mmap(j: J.Json) -> Maybe<&2, List<&2, M.KV>>:
  match j:
    case J.JObj{ms}:
      Some{Svc.kvs(ms)}
    case _:
      None{}

# A JSON string map, nil read as empty.
def Svc.map(j: J.Json) -> +List<M.KV>:
  M.Meta.maybe_map(Svc.mmap(j))

def Svc.mems(m: +List<M.KV>) -> J.Json:
  match m:
    case Nil{}:
      J.JNil{}
    case Con{M.KV{k, v}, r}:
      J.JMem{k, J.JStr{v}, Svc.mems(r)}

def Svc.render(m: +List<M.KV>) -> J.Json:
  J.JObj{Svc.mems(m)}

def Svc.mrender(m: Maybe<&2, List<&2, M.KV>>) -> J.Json:
  match m:
    case None{}:
      J.JNull{}
    case Some{x}:
      Svc.render(x)

# A map as JSON, null when empty.
def Svc.render_nonempty(m: +List<M.KV>) -> J.Json:
  match m:
    case Nil{}:
      J.JNull{}
    case Con{x, r}:
      Svc.render(x <> r)

def Svc.labels(+o: J.Json) -> +List<M.KV>:
  Svc.map(J.Json.at(o, ["metadata", "labels"]))

def Svc.annotations(+o: J.Json) -> +List<M.KV>:
  Svc.map(J.Json.at(o, ["metadata", "annotations"]))

def Svc.annotation(k: String, +o: J.Json) -> String:
  M.Meta.lookup(k, Svc.annotations(o))

def Svc.has_label(k: String, +o: J.Json) -> Bool:
  M.Meta.has(k, Svc.labels(o))

# The metadata of o as meta.bend reads it; kind is the syncer's GVK string.
def Svc.obj(kind: String, o: J.Json) -> M.Obj:
  +md = J.Json.get(o, "metadata")
  M.Obj{Svc.str(J.Json.get(md, "name")), Svc.str(J.Json.get(md, "namespace")), Svc.str(J.Json.get(md, "uid")), kind, Bool.not(J.Json.is_null(J.Json.get(md, "deletionTimestamp"))), Svc.map(J.Json.get(md, "labels")), Svc.map(J.Json.get(md, "annotations"))}

def Svc.obj_namespace(o: M.Obj) -> String:
  match o:
    case M.Obj{name, namespace, uid, kind, deleting, labels, annotations}:
      namespace

# o with these annotations and labels (an empty map drops the field).
def Svc.with_meta(+o: J.Json, ann: +List<M.KV>, lab: +List<M.KV>) -> J.Json:
  +o1 = Svc.put_in(o, "metadata", "annotations", Svc.render_nonempty(ann))
  Svc.put_in(o1, "metadata", "labels", Svc.render_nonempty(lab))

# Names.

# default/kubernetes, whose service, endpoints and endpoint slice map to the
# vcluster's own service.
def Svc.is_kubernetes(+ns: String, +name: String) -> Bool:
  Bool.and(String.eq(ns, "default"), String.eq(name, "kubernetes"))

def Svc.host_namespace.if(empty: Bool, target: String) -> String:
  match empty:
    case True{}:
      ""
    case False{}:
      target

# singleNamespace.HostNamespace.
def Svc.host_namespace(+c: Cfg, +ns: String) -> String:
  Svc.host_namespace.if(String.is_empty(ns), Svc.target(c))

# singleNamespace.HostName: (namespace, name), empty for an empty name.
def Svc.plain_ref.if(empty: Bool, +c: Cfg, +ns: String, name: String) -> String & String:
  match empty:
    case True{}:
      ("", "")
    case False{}:
      (Svc.host_namespace(c, ns), N.Names.host_name(name, ns, Svc.vc(c)))

def Svc.host_ref.if(special: Bool, +c: Cfg, +ns: String, +name: String) -> String & String:
  match special:
    case True{}:
      (Svc.current(c), Svc.vc(c))
    case False{}:
      Svc.plain_ref.if(String.is_empty(name), c, ns, name)

# The host (namespace, name) of a virtual service, endpoints or endpoint
# slice (mappings/resources/services.go:74-82, endpoints.go,
# endpointslices.go): default/kubernetes is the vcluster service in the
# current namespace.
def Svc.host_ref(+c: Cfg, +ns: String, +name: String) -> String & String:
  Svc.host_ref.if(Svc.is_kubernetes(ns, name), c, ns, name)

def Svc.virtual_ref.if(special: Bool, +ann: +List<M.KV>) -> String & String:
  match special:
    case True{}:
      ("default", "kubernetes")
    case False{}:
      (M.Meta.lookup(M.Meta.namespace_annotation(), ann), M.Meta.lookup(M.Meta.name_annotation(), ann))

# The virtual (namespace, name) of a host service: the vcluster service is
# default/kubernetes; any other service names its virtual object in its
# annotations.
def Svc.virtual_ref(+c: Cfg, +h: J.Json) -> String & String:
  Svc.virtual_ref.if(Bool.and(String.eq(Svc.namespace(h), Svc.current(c)), String.eq(Svc.name(h), Svc.vc(c))), Svc.annotations(h))

# Metadata.

# translate.HostMetadata(vObj, {namespace, name}, excluded...): v with its
# metadata reset and renamed, the host annotations and the host labels.
def Svc.host_metadata(+c: Cfg, +kind: String, +excluded: +List<String>, +v: J.Json, +namespace: String, +name: String) -> J.Json:
  +vo = Svc.obj(kind, v)
  +po = M.Meta.copy_object(vo, name, namespace, excluded)
  ann = M.Meta.host_annotations(vo, Some{po}, excluded)
  lab = M.Meta.host_labels_map(Svc.vc(c), Svc.target(c), Some{M.Meta.labels_of(vo)}, None{}, Svc.namespace(v), True{})
  md0 = Svc.del_all(Svc.reset_keys(), J.Json.get(v, "metadata"))
  md1 = J.Json.set(md0, "name", J.JStr{name})
  md2 = Svc.put(md1, "namespace", Svc.sj(Svc.obj_namespace(po)))
  md3 = Svc.put(md2, "annotations", Svc.render_nonempty(ann))
  md4 = Svc.put(md3, "labels", Svc.render_nonempty(M.Meta.maybe_map(lab)))
  J.Json.set(v, "metadata", md4)

# translate.VirtualMetadata(pObj, {namespace, name}, excluded...).
def Svc.virtual_metadata(+c: Cfg, +kind: String, +excluded: +List<String>, +h: J.Json, +namespace: String, +name: String) -> J.Json:
  +ho = Svc.obj(kind, h)
  ann = M.Meta.virtual_annotations(ho, None{}, excluded)
  lab = M.Meta.virtual_labels_map(Svc.vc(c), Some{M.Meta.labels_of(ho)}, [], [])
  md0 = Svc.del_all(Svc.reset_keys(), J.Json.get(h, "metadata"))
  md1 = J.Json.set(md0, "name", J.JStr{name})
  md2 = Svc.put(md1, "namespace", Svc.sj(Svc.host_namespace.if(String.is_empty(Svc.namespace(h)), namespace)))
  md3 = Svc.put(md2, "annotations", Svc.render_nonempty(ann))
  md4 = Svc.put(md3, "labels", Svc.render_nonempty(M.Meta.maybe_map(lab)))
  J.Json.set(h, "metadata", md4)

# Writes.

def Svc.update.if(same: Bool, w: Write, rest: List<&2, Write>) -> List<&2, Write>:
  match same:
    case True{}:
      rest
    case False{}:
      w <> rest

# The host update and the virtual update, each when the object changed.
def Svc.updates(h: J.Json, +h2: J.Json, v: J.Json, +v2: J.Json) -> List<&2, Write>:
  Svc.update.if(Svc.eq(h, h2), HostUpdate{h2}, Svc.update.if(Svc.eq(v, v2), VirtualUpdate{v2}, []))

def Svc.delete_host(+o: J.Json) -> Write:
  HostDelete{Svc.namespace(o), Svc.name(o)}

def Svc.delete_virtual(+o: J.Json) -> Write:
  VirtualDelete{Svc.namespace(o), Svc.name(o)}

def Svc.done(ws: List<&2, Write>) -> Outcome:
  Outcome{ws, NoRequeue{}}

# Labels.

def Svc.host_kvs(+vc: String, m: +List<M.KV>) -> +List<M.KV>:
  match m:
    case Nil{}:
      Nil{}
    case Con{M.KV{k, v}, r}:
      M.Meta.insert(M.Meta.host_label(vc, k), v, Svc.host_kvs(vc, r))

# The host label key of each key (translate.HostLabel).
def Svc.hl_keys(+vc: String, ks: +List<String>) -> +List<String>:
  match ks:
    case Nil{}:
      Nil{}
    case Con{k, r}:
      M.Meta.host_label(vc, k) <> Svc.hl_keys(vc, r)

def Svc.virtual_kvs.if(k: Maybe<&2, String>, v: String, rec: +List<M.KV>) -> +List<M.KV>:
  match k:
    case None{}:
      rec
    case Some{x}:
      M.Meta.insert(x, v, rec)

def Svc.virtual_kvs(+vc: String, m: +List<M.KV>) -> +List<M.KV>:
  match m:
    case Nil{}:
      Nil{}
    case Con{M.KV{k, v}, r}:
      Svc.virtual_kvs.if(M.Meta.virtual_label(vc, k), v, Svc.virtual_kvs(vc, r))

def Svc.virtual_keys.if(k: Maybe<&2, String>, rec: +List<String>) -> +List<String>:
  match k:
    case None{}:
      rec
    case Some{x}:
      x <> rec

def Svc.virtual_keys(+vc: String, ks: +List<String>) -> +List<String>:
  match ks:
    case Nil{}:
      Nil{}
    case Con{k, r}:
      Svc.virtual_keys.if(M.Meta.virtual_label(vc, k), Svc.virtual_keys(vc, r))

# mergeMaps after the key transform: the deleted keys go, the set entries win.
def Svc.merge(sets: +List<M.KV>, dels: +List<String>, target: +List<M.KV>) -> +List<M.KV>:
  M.Meta.union(sets, M.Meta.delete_all(dels, target))

def Svc.labels_bidi.if(vchanged: Bool, hchanged: Bool, +vc: String, +vo: +List<M.KV>, +v: +List<M.KV>, +ho: +List<M.KV>, +h: +List<M.KV>) -> +List<M.KV> & +List<M.KV>:
  match vchanged:
    case True{}:
      (v, Svc.merge(Svc.host_kvs(vc, M.Meta.diff_sets(v, vo, [])), Svc.hl_keys(vc, M.Meta.diff_dels(vo, v, [])), h))
    case False{}:
      match hchanged:
        case True{}:
          (Svc.merge(Svc.virtual_kvs(vc, M.Meta.diff_sets(h, ho, [])), Svc.virtual_keys(vc, M.Meta.diff_dels(ho, h, [])), v), h)
        case False{}:
          (v, h)

# translate.LabelsBidirectionalUpdate(event): (new virtual labels, new host
# labels). A virtual change goes to the host under translated keys; else a
# host change comes back under virtual keys, without vcluster's own labels.
def Svc.labels_bidi(+vc: String, +vo: +List<M.KV>, +v: +List<M.KV>, +ho: +List<M.KV>, +h: +List<M.KV>) -> +List<M.KV> & +List<M.KV>:
  Svc.labels_bidi.if(Bool.not(M.Meta.map_eq(vo, v)), Bool.not(M.Meta.map_eq(ho, h)), vc, vo, v, ho, h)

# Annotations and labels of an update, both ways (AnnotationsBidirectionalUpdate
# and LabelsBidirectionalUpdate); `drop` lists host annotations removed
# afterwards. h1 and v1 are the host and virtual objects with their other
# changes made.
# The pairs come in as parameters: a match cannot scrutinize a local binder.
def Svc.meta_sync.fin(am: +List<M.KV> & +List<M.KV>, lm: +List<M.KV> & +List<M.KV>, +drop: +List<String>, +h: J.Json, +v: J.Json, +h1: J.Json, +v1: J.Json) -> Outcome:
  (nva, nha) = am
  (nvl, nhl) = lm
  Outcome{Svc.updates(h, Svc.with_meta(h1, M.Meta.delete_all(drop, nha), nhl), v, Svc.with_meta(v1, nva, nvl)), NoRequeue{}}

def Svc.meta_sync(+c: Cfg, +kind: String, +excluded: +List<String>, +drop: +List<String>, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json, +h1: J.Json, +v1: J.Json) -> Outcome:
  am lm = M.Meta.annotations_bidirectional_update(Svc.obj(kind, ho), Svc.obj(kind, h), Svc.obj(kind, vo), Svc.obj(kind, v), excluded) Svc.labels_bidi(Svc.vc(c), Svc.labels(vo), Svc.labels(v), Svc.labels(ho), Svc.labels(h))
  Svc.meta_sync.fin(am, lm, drop, h, v, h1, v1)

# Ports.

def Svc.port(+p: J.Json) -> Port:
  Port{J.Json.get(p, "name"), J.Json.get(p, "protocol"), J.Json.get(p, "appProtocol"), J.Json.get(p, "port"), J.Json.get(p, "targetPort"), J.Json.get(p, "nodePort")}

def Svc.ports.go(xs: List<&2, J.Json>) -> +List<Port>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{p, r}:
      Svc.port(p) <> Svc.ports.go(r)

# The ports of a JSON port list.
def Svc.ports(j: J.Json) -> +List<Port>:
  Svc.ports.go(J.Json.items(j))

def Svc.mem.if(isnull: Bool, k: String, v: J.Json, rest: J.Json) -> J.Json:
  match isnull:
    case True{}:
      rest
    case False{}:
      J.JMem{k, v, rest}

def Svc.mem(k: String, +v: J.Json, rest: J.Json) -> J.Json:
  Svc.mem.if(J.Json.is_null(v), k, v, rest)

def Svc.port_json(p: Port) -> J.Json:
  match p:
    case Port{name, protocol, app, num, target, node}:
      J.JObj{Svc.mem("name", name, Svc.mem("protocol", protocol, Svc.mem("appProtocol", app, Svc.mem("port", num, Svc.mem("targetPort", target, Svc.mem("nodePort", node, J.JNil{}))))))}

def Svc.ports_json.go(ps: +List<Port>) -> J.Json:
  match ps:
    case Nil{}:
      J.JNil{}
    case Con{p, r}:
      J.JCons{Svc.port_json(p), Svc.ports_json.go(r)}

# A port list as JSON; null when empty.
def Svc.ports_json(ps: +List<Port>) -> J.Json:
  match ps:
    case Nil{}:
      J.JNull{}
    case Con{p, r}:
      J.JArr{Svc.ports_json.go(p <> r)}

def Svc.strip_port(p: Port) -> Port:
  match p:
    case Port{name, protocol, app, num, target, node}:
      Port{name, protocol, app, num, target, J.JNull{}}

# services.StripNodePorts: every nodePort cleared.
def Svc.strip_node_ports(ps: +List<Port>) -> +List<Port>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{p, r}:
      Svc.strip_port(p) <> Svc.strip_node_ports(r)

def Svc.is_kubelet(p: Port) -> Bool:
  match p:
    case Port{name, protocol, app, num, target, node}:
      String.eq(Svc.str(name), "kubelet")

def Svc.translate_ports.if(kubelet: Bool, p: Port, rec: +List<Port>) -> +List<Port>:
  match kubelet:
    case True{}:
      rec
    case False{}:
      Svc.strip_port(p) <> rec

# services.TranslateServicePorts: the port named "kubelet" dropped; each
# other port keeps only name, protocol, appProtocol, port and targetPort.
def Svc.translate_ports(ps: +List<Port>) -> +List<Port>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{+p, r}:
      Svc.translate_ports.if(Svc.is_kubelet(p), p, Svc.translate_ports(r))

# What a port is apart from its node port: [name, protocol, appProtocol,
# port, targetPort].
def Svc.port_id(p: Port) -> J.Json:
  match p:
    case Port{name, protocol, app, num, target, node}:
      J.Json.arr([name, protocol, app, num, target])

def Svc.port_ids(ps: +List<Port>) -> List<&2, J.Json>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{p, r}:
      Svc.port_id(p) <> Svc.port_ids(r)

# Services.

# The host selector of a new host service: translate.HostLabelsMap(vSelector,
# nil, vNamespace, false), so the markers are always added.
def Svc.host_selector(vc: String, target: String, ns: String, sel: Maybe<&2, List<&2, M.KV>>) -> Maybe<&2, List<&2, M.KV>>:
  M.Meta.host_labels_map(vc, target, sel, None{}, ns, False{})

# The keys a host selector may use for a virtual selector: the two markers,
# and the host key of each virtual key.
def Svc.selector_allowed(vc: String, sel: +List<M.KV>) -> +List<String>:
  M.Meta.marker_label() <> M.Meta.namespace_label() <> Svc.hl_keys(vc, M.Meta.keys(sel))

# True when every key of m is one of a.
def Svc.keys_in(m: +List<M.KV>, +a: +List<String>) -> Bool:
  match m:
    case Nil{}:
      True{}
    case Con{M.KV{k, v}, r}:
      Bool.and(M.Meta.elem(k, a), Svc.keys_in(r, a))

def Svc.headless.if(headless: Bool) -> J.Json:
  match headless:
    case True{}:
      J.JStr{"None"}
    case False{}:
      J.JNull{}

# The cluster IP of a new host service: "None" stays, any other is cleared.
def Svc.keep_headless(j: J.Json) -> J.Json:
  Svc.headless.if(String.eq(Svc.str(j), "None"))

# services translate (vObj -> host service) for SyncToHost.
def Svc.to_host(+c: Cfg, +v: J.Json) -> J.Json:
  +ns = Svc.namespace(v)
  (hns, hname) = Svc.host_ref(c, ns, Svc.name(v))
  o1 = Svc.host_metadata(c, Svc.kind(), [Svc.rancher()], v, hns, hname)
  +spec = J.Json.get(v, "spec")
  sel = Svc.host_selector(Svc.vc(c), Svc.target(c), ns, Svc.mmap(J.Json.get(spec, "selector")))
  s1 = Svc.put(spec, "selector", Svc.mrender(sel))
  s2 = Svc.put(s1, "clusterIP", Svc.keep_headless(J.Json.get(spec, "clusterIP")))
  s3 = Svc.del_all(["clusterIPs", "ipFamilies", "ipFamilyPolicy"], s2)
  s4 = Svc.put(s3, "ports", Svc.ports_json(Svc.strip_node_ports(Svc.ports(J.Json.get(spec, "ports")))))
  Svc.put(o1, "spec", s4)

# services translateToVirtual (host service -> vObj) for SyncToVirtual.
def Svc.to_virtual(+c: Cfg, +h: J.Json) -> J.Json:
  (vns, vname) = Svc.virtual_ref(c, h)
  o1 = Svc.virtual_metadata(c, Svc.kind(), [Svc.rancher()], h, vns, vname)
  +spec = J.Json.get(h, "spec")
  sel = M.Meta.virtual_labels_map(Svc.vc(c), Svc.mmap(J.Json.get(spec, "selector")), [], [])
  s1 = Svc.put(spec, "selector", Svc.mrender(sel))
  s2 = Svc.del_all(["ipFamilies", "ipFamilyPolicy"], s1)
  Svc.put(o1, "spec", s2)

def Svc.sync_to_host.if(delete: Bool, +c: Cfg, +v: J.Json) -> Outcome:
  match delete:
    case True{}:
      Svc.done([Svc.delete_virtual(v)])
    case False{}:
      Svc.done([HostCreate{Svc.to_host(c, v)}])

# services SyncToHost: the virtual service exists, the host one does not.
# host_old is the cached host object: when it was there, the host service
# was deleted, and so is the virtual one.
def Svc.sync_to_host(+c: Cfg, host_old: Maybe<&2, J.Json>, +v: J.Json) -> Outcome:
  Svc.sync_to_host.if(Bool.or(Maybe.is_some(&2, J.Json, host_old), Bool.not(J.Json.is_null(J.Json.at(v, ["metadata", "deletionTimestamp"])))), c, v)

def Svc.sync_to_virtual.if(blocked: Bool, delete: Bool, +c: Cfg, +h: J.Json) -> Outcome:
  match blocked:
    case True{}:
      Outcome{[], RequeueAfter{10}}
    case False{}:
      match delete:
        case True{}:
          Svc.done([Svc.delete_host(h)])
        case False{}:
          Svc.done([VirtualCreate{Svc.to_virtual(c, h)}])

# services SyncToVirtual: the host service exists, the virtual one does not.
# young: the host service is less than two minutes old. A young host service
# with vcluster.loft.sh/block-deletion: "true" waits 10 seconds; a host
# service whose virtual one was seen (virtual_old) or that vcluster made
# (translate.ShouldDeleteHostObject) is deleted; any other is copied back.
def Svc.sync_to_virtual(+c: Cfg, young: Bool, virtual_old: Maybe<&2, J.Json>, +h: J.Json) -> Outcome:
  blocked = Bool.and(String.eq(Svc.annotation(Svc.block_deletion(), h), "true"), young)
  delete = Bool.or(Maybe.is_some(&2, J.Json, virtual_old), M.Meta.should_delete_host_object(Svc.obj(Svc.kind(), h)))
  Svc.sync_to_virtual.if(blocked, delete, c, h)

# The fields of patcher.CopyBidirectional in services Sync, in two halves.
def Svc.fields_a() -> +List<String>:
  ["type", "externalIPs", "externalName", "loadBalancerIP", "ports", "publishNotReadyAddresses"]

def Svc.fields_b() -> +List<String>:
  ["externalTrafficPolicy", "sessionAffinity", "sessionAffinityConfig", "loadBalancerSourceRanges", "healthCheckNodePort"]

def Svc.pick.if(vsame: Bool, hsame: Bool, k: String, +v: J.Json, +h: J.Json) -> Pick:
  match vsame:
    case False{}:
      Pick{k, v, v}
    case True{}:
      match hsame:
        case False{}:
          Pick{k, h, h}
        case True{}:
          Pick{k, v, h}

# patcher.CopyBidirectional for field k of the specs: a virtual change wins,
# else a host change, else both stay.
def Svc.pick(+k: String, +vo: J.Json, +v: J.Json, +ho: J.Json, +h: J.Json) -> Pick:
  +a = J.Json.get(v, k)
  +b = J.Json.get(h, k)
  Svc.pick.if(Svc.eq(J.Json.get(vo, k), a), Svc.eq(J.Json.get(ho, k), b), k, a, b)

def Svc.picks(fs: +List<String>, +vo: J.Json, +v: J.Json, +ho: J.Json, +h: J.Json) -> List<&2, Pick>:
  match fs:
    case Nil{}:
      Nil{}
    case Con{f, r}:
      Svc.pick(f, vo, v, ho, h) <> Svc.picks(r, vo, v, ho, h)

def Svc.apply_picks(ps: List<&2, Pick>, vs: J.Json, hs: J.Json) -> J.Json & J.Json:
  match ps:
    case Nil{}:
      (vs, hs)
    case Con{Pick{+k, a, b}, r}:
      Svc.apply_picks(r, Svc.put(vs, k, a), Svc.put(hs, k, b))

def Svc.lb.if(lb: Bool, h: J.Json) -> J.Json:
  match lb:
    case True{}:
      h
    case False{}:
      +h1 = Svc.put_in(h, "spec", "loadBalancerIP", J.JNull{})
      J.Json.set(h1, "status", Svc.put(J.Json.get(h1, "status"), "loadBalancer", Svc.put(J.Json.at(h1, ["status", "loadBalancer"]), "ingress", J.Json.arr([]))))

# services ensureLoadBalancerStatus: a host service that is not a
# LoadBalancer loses its loadBalancerIP and its load balancer ingress.
def Svc.ensure_lb(+h: J.Json) -> J.Json:
  Svc.lb.if(String.eq(Svc.spec_str(h, "type"), "LoadBalancer"), h)

def Svc.sel_eq(a: Maybe<&2, List<&2, M.KV>>, b: Maybe<&2, List<&2, M.KV>>) -> Bool:
  M.Meta.map_eq(M.Meta.maybe_map(a), M.Meta.maybe_map(b))

def Svc.selector.if(forward: Bool, +vc: String, +target: String, +ns: String, +vsel: Maybe<&2, List<&2, M.KV>>, +hsel: Maybe<&2, List<&2, M.KV>>) -> Maybe<&2, List<&2, M.KV>> & Maybe<&2, List<&2, M.KV>>:
  match forward:
    case True{}:
      (vsel, M.Meta.host_labels_map(vc, target, vsel, hsel, ns, False{}))
    case False{}:
      (M.Meta.virtual_labels_map(vc, hsel, M.Meta.maybe_map(vsel), []), hsel)

# True when the virtual service turns into an ExternalName service while
# the host one still has a cluster IP.
def Svc.switching(+h: J.Json, +v: J.Json) -> Bool:
  +vt = Svc.spec_str(v, "type")
  Bool.and(String.eq(vt, "ExternalName"), Bool.and(Bool.not(String.eq(Svc.spec_str(h, "type"), vt)), Bool.not(String.is_empty(Svc.spec_str(h, "clusterIP")))))

# services recreateService: the virtual service with the host cluster IP, no
# cluster IPs, and no resource version, UID, deletion or generation.
def Svc.recreated(+h: J.Json, +v: J.Json) -> J.Json:
  +v1 = Svc.put_in(v, "spec", "clusterIPs", J.JNull{})
  +v2 = Svc.put_in(v1, "spec", "clusterIP", J.Json.at(h, ["spec", "clusterIP"]))
  J.Json.set(v2, "metadata", Svc.del_all(["resourceVersion", "uid", "deletionTimestamp", "generation"], J.Json.get(v2, "metadata")))

# services Sync after the two checks: the spec fields both ways, the load
# balancer status, the status back to virtual, annotations and labels both
# ways, and the selector.
def Svc.sync.update(+c: Cfg, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> Outcome:
  +vos = J.Json.get(vo, "spec")
  +vs = J.Json.get(v, "spec")
  +hos = J.Json.get(ho, "spec")
  +hs = J.Json.get(h, "spec")
  pa pb = Svc.picks(Svc.fields_a(), vos, vs, hos, hs) Svc.picks(Svc.fields_b(), vos, vs, hos, hs)
  (vs1, hs1) = Svc.apply_picks(List.append(&2, Pick, pa, pb), vs, hs)
  +vsel = Svc.mmap(J.Json.get(vs, "selector"))
  +hsel = Svc.mmap(J.Json.get(hs, "selector"))
  fwd = Bool.or(Bool.not(Svc.sel_eq(Svc.mmap(J.Json.get(vos, "selector")), vsel)), Svc.sel_eq(Svc.mmap(J.Json.get(hos, "selector")), hsel))
  (nvsel, nhsel) = Svc.selector.if(fwd, Svc.vc(c), Svc.target(c), Svc.namespace(v), vsel, hsel)
  +h2 = Svc.ensure_lb(J.Json.set(h, "spec", Svc.put(hs1, "selector", Svc.mrender(nhsel))))
  v1 = J.Json.set(v, "spec", Svc.put(vs1, "selector", Svc.mrender(nvsel)))
  v2 = Svc.put(v1, "status", J.Json.get(h2, "status"))
  Svc.meta_sync(c, Svc.kind(), [Svc.rancher()], [Svc.block_deletion()], ho, h, vo, v, h2, v2)

def Svc.sync.if(switching: Bool, differs: Bool, +c: Cfg, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> Outcome:
  match switching:
    case True{}:
      Outcome{[], RequeueAfter{3}}
    case False{}:
      match differs:
        case True{}:
          Outcome{[Svc.delete_virtual(v), VirtualCreate{Svc.recreated(h, v)}], RequeueNow{}}
        case False{}:
          Svc.sync.update(c, ho, h, vo, v)

# services Sync: both services exist. While the virtual service turns into
# an ExternalName service the step waits 3 seconds; when the cluster IPs
# differ the virtual service is recreated with the host one and the step
# requeues; else the two services are synced.
def Svc.sync(+c: Cfg, +host_old: J.Json, +host: J.Json, +virtual_old: J.Json, +virtual: J.Json) -> Outcome:
  differs = Bool.not(String.eq(Svc.spec_str(virtual, "clusterIP"), Svc.spec_str(host, "clusterIP")))
  Svc.sync.if(Svc.switching(host, virtual), differs, c, host_old, host, virtual_old, virtual)

# services ReconcileStart: true for the special services (default/kubernetes),
# which Svc.sync_kubernetes syncs instead of the generic sync.
def Svc.services_start(+ns: String, +name: String) -> Bool:
  Svc.is_kubernetes(ns, name)

# The virtual default/kubernetes service as SyncKubernetesService makes it:
# the host cluster IPs, IP families and policy, and the translated ports.
def Svc.kubernetes_new(+h: J.Json, +v: J.Json, +ports: J.Json) -> J.Json:
  +hs = J.Json.get(h, "spec")
  s1 = Svc.put(J.Json.get(v, "spec"), "clusterIP", J.Json.get(hs, "clusterIP"))
  s2 = Svc.put(s1, "clusterIPs", J.Json.get(hs, "clusterIPs"))
  s3 = Svc.put(s2, "ipFamilies", J.Json.get(hs, "ipFamilies"))
  s4 = Svc.put(s3, "ipFamilyPolicy", J.Json.get(hs, "ipFamilyPolicy"))
  Svc.put(v, "spec", Svc.put(s4, "ports", ports))

def Svc.kubernetes.if(changed: Bool, same_ports: Bool, +nv: J.Json, ns: String, name: String) -> Outcome:
  match changed:
    case True{}:
      Svc.done([VirtualDelete{ns, name}, VirtualCreate{J.Json.set(nv, "metadata", J.Json.del(J.Json.get(nv, "metadata"), "resourceVersion"))}])
    case False{}:
      match same_ports:
        case True{}:
          Svc.done([])
        case False{}:
          Svc.done([VirtualUpdate{nv}])

def Svc.kubernetes.both(+h: J.Json, +v: J.Json) -> Outcome:
  changed = Bool.or(Bool.not(String.eq(Svc.spec_str(v, "clusterIP"), Svc.spec_str(h, "clusterIP"))), Bool.not(Svc.eq(J.Json.at(v, ["spec", "clusterIPs"]), J.Json.at(h, ["spec", "clusterIPs"]))))
  +ports = Svc.ports_json(Svc.translate_ports(Svc.ports(J.Json.at(h, ["spec", "ports"]))))
  same_ports = Svc.eq(J.Json.at(v, ["spec", "ports"]), ports)
  Svc.kubernetes.if(changed, same_ports, Svc.kubernetes_new(h, v, ports), Svc.namespace(v), Svc.name(v))

def Svc.kubernetes.v(+h: J.Json, virtual: Maybe<&2, J.Json>) -> Outcome:
  match virtual:
    case None{}:
      Svc.done([])
    case Some{v}:
      Svc.kubernetes.both(h, v)

# specialservices.SyncKubernetesService: host is the vcluster's own service,
# virtual the virtual default/kubernetes service. When the cluster IPs
# differ the virtual service is recreated; when only the translated ports
# differ it is updated.
def Svc.sync_kubernetes(host: Maybe<&2, J.Json>, virtual: Maybe<&2, J.Json>) -> Outcome:
  match host:
    case None{}:
      Svc.done([])
    case Some{h}:
      Svc.kubernetes.v(h, virtual)

# Endpoints and endpoint slices.

def Svc.clear_uid.if(clear: Bool, r: J.Json) -> J.Json:
  match clear:
    case True{}:
      Svc.del_all(["uid", "resourceVersion"], r)
    case False{}:
      r

def Svc.pod_ref.if(pod: Bool, +c: Cfg, clear: Bool, +ref: J.Json) -> J.Json:
  match pod:
    case False{}:
      ref
    case True{}:
      +rname = Svc.str(J.Json.get(ref, "name"))
      (hns, hname) = Svc.plain_ref.if(String.is_empty(rname), c, Svc.str(J.Json.get(ref, "namespace")), rname)
      Svc.clear_uid.if(clear, Svc.put(Svc.put(ref, "name", Svc.sj(hname)), "namespace", Svc.sj(hns)))

# A target ref of kind Pod points at the host pod; clear also drops its UID
# and resource version.
def Svc.pod_ref(+c: Cfg, clear: Bool, +ref: J.Json) -> J.Json:
  Svc.pod_ref.if(String.eq(Svc.str(J.Json.get(ref, "kind")), "Pod"), c, clear, ref)

def Svc.addr(+c: Cfg, clear: Bool, +a: J.Json) -> J.Json:
  Svc.put(a, "targetRef", Svc.pod_ref(c, clear, J.Json.get(a, "targetRef")))

def Svc.addrs.chain(+c: Cfg, +clear: Bool, xs: J.Json) -> J.Json:
  match xs:
    case J.JCons{a, r}:
      J.JCons{Svc.addr(c, clear, a), Svc.addrs.chain(c, clear, r)}
    case x:
      x

# Each address (or endpoint) of a list with its target ref translated.
def Svc.addrs(+c: Cfg, +clear: Bool, j: J.Json) -> J.Json:
  match j:
    case J.JArr{xs}:
      J.JArr{Svc.addrs.chain(c, clear, xs)}
    case x:
      x

def Svc.subset(+c: Cfg, +s: J.Json) -> J.Json:
  a n = Svc.addrs(c, True{}, J.Json.get(s, "addresses")) Svc.addrs(c, True{}, J.Json.get(s, "notReadyAddresses"))
  Svc.put(Svc.put(s, "addresses", a), "notReadyAddresses", n)

def Svc.subsets.chain(+c: Cfg, xs: J.Json) -> J.Json:
  match xs:
    case J.JCons{s, r}:
      J.JCons{Svc.subset(c, s), Svc.subsets.chain(c, r)}
    case x:
      x

# endpoints translateSpec: the subsets with Pod target refs translated.
def Svc.subsets(+c: Cfg, j: J.Json) -> J.Json:
  match j:
    case J.JArr{xs}:
      J.JArr{Svc.subsets.chain(c, xs)}
    case x:
      x

# endpoints translate (vObj -> host endpoints).
def Svc.endpoints_to_host(+c: Cfg, +v: J.Json) -> J.Json:
  (hns, hname) = Svc.host_ref(c, Svc.namespace(v), Svc.name(v))
  o1 = Svc.host_metadata(c, Svc.endpoints_kind(), [Svc.leader()], v, hns, hname)
  Svc.put(o1, "subsets", Svc.subsets(c, J.Json.get(v, "subsets")))

# endpoints SyncToHost: delete the virtual endpoints when the host ones were
# deleted (host_old), else create the host endpoints.
def Svc.endpoints_sync_to_host(+c: Cfg, host_old: Maybe<&2, J.Json>, +v: J.Json) -> Outcome:
  match host_old:
    case None{}:
      Svc.done([HostCreate{Svc.endpoints_to_host(c, v)}])
    case Some{x}:
      Svc.done([Svc.delete_virtual(v)])

# endpoints Sync: the host subsets are the translated virtual ones; then
# annotations and labels both ways.
def Svc.endpoints_sync(+c: Cfg, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> Outcome:
  h1 = Svc.put(h, "subsets", Svc.subsets(c, J.Json.get(v, "subsets")))
  Svc.meta_sync(c, Svc.endpoints_kind(), [Svc.leader()], [], ho, h, vo, v, h1, v)

# endpoints and endpoint slices SyncToVirtual: the host object goes.
def Svc.endpoints_sync_to_virtual(+h: J.Json) -> Outcome:
  Svc.done([Svc.delete_host(h)])

# True when vcluster made the host object (it has the object-name annotation).
def Svc.managed(+o: J.Json) -> Bool:
  Bool.not(String.is_empty(Svc.annotation(M.Meta.name_annotation(), o)))

def Svc.delete_if(del: Bool, +h: J.Json) -> List<&2, Write>:
  match del:
    case True{}:
      [Svc.delete_host(h)]
    case False{}:
      []

def Svc.start.selector(host: Maybe<&2, J.Json>) -> Start:
  match host:
    case None{}:
      Start{True{}, [], ""}
    case Some{+h}:
      Start{True{}, Svc.delete_if(Svc.managed(h), h), ""}

def Svc.start.plain(host: Maybe<&2, J.Json>) -> Start:
  match host:
    case None{}:
      Start{False{}, [], ""}
    case Some{+h}:
      Start{False{}, Svc.delete_if(Bool.not(Svc.managed(h)), h), ""}

def Svc.start.sel(sel: Bool, host: Maybe<&2, J.Json>) -> Start:
  match sel:
    case True{}:
      Svc.start.selector(host)
    case False{}:
      Svc.start.plain(host)

def Svc.has_selector(+s: J.Json) -> Bool:
  Maybe.is_some(&2, List<&2, M.KV>, Svc.mmap(J.Json.at(s, ["spec", "selector"])))

# The service part of ReconcileStart. Without the service the step is
# skipped. A selector service skips the sync and deletes a host object that
# vcluster made; a selector-less service deletes a host object vcluster did
# not make and goes on to the sync.
def Svc.start.svc(svc: Maybe<&2, J.Json>, host: Maybe<&2, J.Json>) -> Start:
  match svc:
    case None{}:
      Start{True{}, [], ""}
    case Some{s}:
      Svc.start.sel(Svc.has_selector(s), host)

def Svc.endpoints_start.if(special: Bool, svc: Maybe<&2, J.Json>, host: Maybe<&2, J.Json>) -> Start:
  match special:
    case True{}:
      Start{True{}, [], ""}
    case False{}:
      Svc.start.svc(svc, host)

# endpoints ReconcileStart for request ns/name: svc is the virtual service
# ns/name, host the host endpoints of the request. default/kubernetes is
# skipped.
def Svc.endpoints_start(+ns: String, +name: String, svc: Maybe<&2, J.Json>, host: Maybe<&2, J.Json>) -> Start:
  Svc.endpoints_start.if(Svc.is_kubernetes(ns, name), svc, host)

# endpointslices translateSvcName: plain concatenation, no SafeConcatName.
def Svc.slice_service_name(svc: String, ns: String, vc: String) -> String:
  svc ++ "-x-" ++ ns ++ "-x-" ++ vc

# endpointslices translate (vObj -> host endpoint slice): the
# kubernetes.io/service-name label is rebuilt from the host labels.
def Svc.slice_to_host(+c: Cfg, +v: J.Json) -> J.Json:
  (hns, hname) = Svc.host_ref(c, Svc.namespace(v), Svc.name(v))
  +o1 = Svc.host_metadata(c, Svc.slice_kind(), [Svc.leader()], v, hns, hname)
  +labs = Svc.labels(o1)
  sn = Svc.slice_service_name(M.Meta.lookup(Svc.service_name_label(), labs), M.Meta.lookup(M.Meta.namespace_label(), labs), M.Meta.lookup(M.Meta.marker_label(), labs))
  o2 = Svc.put_in(o1, "metadata", "labels", Svc.render(M.Meta.insert(Svc.service_name_label(), sn, labs)))
  Svc.put(o2, "endpoints", Svc.addrs(c, False{}, J.Json.get(v, "endpoints")))

# endpointslices SyncToHost.
def Svc.slice_sync_to_host(+c: Cfg, host_old: Maybe<&2, J.Json>, +v: J.Json) -> Outcome:
  match host_old:
    case None{}:
      Svc.done([HostCreate{Svc.slice_to_host(c, v)}])
    case Some{x}:
      Svc.done([Svc.delete_virtual(v)])

# endpointslices Sync: the host endpoints are the translated virtual ones;
# then annotations and labels both ways.
def Svc.slice_sync(+c: Cfg, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> Outcome:
  h1 = Svc.put(h, "endpoints", Svc.addrs(c, False{}, J.Json.get(v, "endpoints")))
  Svc.meta_sync(c, Svc.slice_kind(), [Svc.leader()], [], ho, h, vo, v, h1, v)

def Svc.slice_start.gone(host: Maybe<&2, J.Json>) -> Start:
  match host:
    case None{}:
      Start{True{}, [], ""}
    case Some{+h}:
      Start{True{}, [Svc.delete_host(h)], ""}

def Svc.slice_start.label(has: Bool, svc: Maybe<&2, J.Json>, host: Maybe<&2, J.Json>) -> Start:
  match has:
    case True{}:
      Svc.start.svc(svc, host)
    case False{}:
      Start{True{}, [], "unable to retrieve label 'kubernetes.io/service-name'"}

def Svc.slice_start.eps(eps: Maybe<&2, J.Json>, svc: Maybe<&2, J.Json>, host: Maybe<&2, J.Json>) -> Start:
  match eps:
    case None{}:
      Svc.slice_start.gone(host)
    case Some{+e}:
      Svc.slice_start.label(Svc.has_label(Svc.service_name_label(), e), svc, host)

def Svc.slice_start.if(special: Bool, eps: Maybe<&2, J.Json>, svc: Maybe<&2, J.Json>, host: Maybe<&2, J.Json>) -> Start:
  match special:
    case True{}:
      Start{True{}, [], ""}
    case False{}:
      Svc.slice_start.eps(eps, svc, host)

# endpointslices ReconcileStart for request ns/name: eps is the virtual
# endpoint slice ns/name, svc the virtual service its
# kubernetes.io/service-name label names (unused without the label), host
# the host endpoint slice of the request. default/kubernetes is skipped; a
# gone virtual slice deletes the host one.
def Svc.slice_start(+ns: String, +name: String, eps: Maybe<&2, J.Json>, svc: Maybe<&2, J.Json>, host: Maybe<&2, J.Json>) -> Start:
  Svc.slice_start.if(Svc.is_kubernetes(ns, name), eps, svc, host)
