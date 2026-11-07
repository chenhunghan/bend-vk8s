import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../translate/meta.bend as M
import ../translate/names.bend as N

# The generic sync framework (vcluster pkg/syncer/syncer.go,
# from_host_syncer.go, pkg/patcher: sync.go, patcher.go, apply.go) as pure
# functions over bend-kube JSON values.
#
# Sync is a pure function of snapshots. The caller reads the virtual and the
# host object (None when absent), and the object cache entries for both (the
# "old" objects); it passes whether the host object is managed (IsManaged,
# which may consult the mapping store). Core.decide returns the reconcile
# decision of SyncController.Reconcile; the generic syncers below turn a
# decision into the writes to make (create, patch, delete on the host or the
# virtual cluster) and when to look again.
#
# Patches are JSON merge patches (RFC 7386) computed as vcluster does:
# client.MergeFrom(before).Data(after), then CalculateMergePatch keeps only
# metadata.annotations, labels and finalizers under metadata. An update whose
# patch does not change the object writes nothing (applyObjectWithPatch's
# DeepEqual check).
#
# Representation: object members keep their order. A patch lists the changed
# members in the order of the new object, then the removed members (null) in
# the order of the old object; Go marshals map keys sorted, so compare
# patches with Core.json_same, which ignores member order.
#
# Known differences, by design: numbers compare by their text (Go compares
# float64); resource versions compare as decimal digit strings (no sign, no
# leading zeros); duplicate keys in an object are not merged.

# Which cluster a write goes to.
type Side is Data:
  Host{}
  Virtual{}

# A write. Patch is a JSON merge patch on the object; status says it goes to
# the status subresource. Delete carries vcluster's log reason ("" when the
# Go code gives none).
type Write is Data:
  Create{side: Side, obj: J.Json}
  Patch{side: Side, status: Bool, patch: J.Json}
  Delete{side: Side, obj: J.Json, reason: String}

# When to reconcile again: never (until the next event), now, or after ms.
type Again is Data:
  Settled{}
  AgainNow{}
  AgainAfter{ms: U32}

type Out is Data:
  Out{writes: List<&2, Write>, again: Again}

# A syncer's configuration.
#   vc: the vcluster name (translate.VClusterName)
#   target: the host namespace (single-namespace mode)
#   gvk: the synced kind as Go gvk.String(), e.g. "/v1, Kind=Secret"
#   name: the syncer's name (r.syncer.Name())
#   caching: Options.ObjectCaching
#   uid_deletion: !Options.DisableUIDDeletion
#   from_host: the syncer is a genericFromHostSyncer (its ObjectExcluder)
type Cfg is Data:
  Cfg{vc: String, target: String, gvk: String, name: String, caching: Bool, uid_deletion: Bool, from_host: Bool}

# The decision of SyncController.Reconcile.
#   DSkip: nothing to do (excluded, skip-backsync, or no object)
#   DRequeue: a cache entry is newer than the object read (Requeue: true)
#   DRequeueAfter: the host object must go but is already deleting
#   DDeleteHost: the host object belongs to another virtual object (uid)
#   DSync, DToHost, DToVirtual: the syncer's Sync, SyncToHost, SyncToVirtual
type Decision is Data:
  DSkip{}
  DRequeue{}
  DRequeueAfter{ms: U32}
  DDeleteHost{host: J.Json, reason: String}
  DSync{vold: Maybe<&2, J.Json>, virtual: J.Json, hold: Maybe<&2, J.Json>, host: J.Json}
  DToHost{hold: Maybe<&2, J.Json>, virtual: J.Json}
  DToVirtual{vold: Maybe<&2, J.Json>, host: J.Json}

# The virtual namespace a from-host object goes to.
type NsState is Data:
  NsMissing{}
  NsTerminating{}
  NsReady{}

# Constants (vcluster translate/types.go, translate.go).

def Core.skip_backsync_annotation() -> String:
  "vcluster.loft.sh/skip-backsync"

def Core.uid_reason() -> String:
  "virtual object uid is different"

# Lists.

def Core.cat(xs: List<&2, Write>, ys: List<&2, Write>) -> List<&2, Write>:
  match xs:
    case Nil{}:
      ys
    case Con{x, r}:
      x <> Core.cat(r, ys)

def Core.str_in(+k: String, xs: +List<String>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{x, r}:
      Bool.or(String.eq(k, x), Core.str_in(k, r))

# JSON equality: structural, as Go's DeepEqual on decoded JSON (member order
# counts here; see Core.json_same for an order-free comparison).

def Core.bool_eq(a: Bool, b: Bool) -> Bool:
  match a:
    case True{}:
      b
    case False{}:
      Bool.not(b)

def Core.json_eq(a: J.Json, b: J.Json) -> Bool:
  match a b:
    case J.JNull{} J.JNull{}:
      True{}
    case J.JBool{x} J.JBool{y}:
      Core.bool_eq(x, y)
    case J.JNum{x} J.JNum{y}:
      String.eq(x, y)
    case J.JStr{x} J.JStr{y}:
      String.eq(x, y)
    case J.JArr{x} J.JArr{y}:
      Core.json_eq(x, y)
    case J.JObj{x} J.JObj{y}:
      Core.json_eq(x, y)
    case J.JNil{} J.JNil{}:
      True{}
    case J.JCons{h1, t1} J.JCons{h2, t2}:
      Bool.and(Core.json_eq(h1, h2), Core.json_eq(t1, t2))
    case J.JMem{k1, v1, t1} J.JMem{k2, v2, t2}:
      Bool.and(String.eq(k1, k2), Bool.and(Core.json_eq(v1, v2), Core.json_eq(t1, t2)))
    case _ _:
      False{}

# Member chains.

def Core.find.if(hit: Bool, v: J.Json, rec: Maybe<&2, J.Json>) -> Maybe<&2, J.Json>:
  match hit:
    case True{}:
      Some{v}
    case False{}:
      rec

# The value of key in a member chain (the first member with that key).
def Core.find(ms: J.Json, +key: String) -> Maybe<&2, J.Json>:
  match ms:
    case J.JMem{k, v, t}:
      Core.find.if(String.eq(k, key), v, Core.find(t, key))
    case _:
      None{}

def Core.has(ms: J.Json, +key: String) -> Bool:
  match ms:
    case J.JMem{k, v, t}:
      Bool.or(String.eq(k, key), Core.has(t, key))
    case _:
      False{}

def Core.or_nil(m: Maybe<&2, J.Json>) -> J.Json:
  match m:
    case None{}:
      J.JNil{}
    case Some{x}:
      x

# The member chain of an object; JNil for anything else.
def Core.members(j: J.Json) -> J.Json:
  match j:
    case J.JObj{ms}:
      ms
    case _:
      J.JNil{}

def Core.members_of(m: Maybe<&2, J.Json>) -> J.Json:
  match m:
    case None{}:
      J.JNil{}
    case Some{x}:
      Core.members(x)

# Order-free JSON comparison, for laws and tests: objects are equal when
# they have the same keys with equal values. In a member chain a JNil ends
# the chain (every member was found); JNil also stands for an absent value.
def Core.keys_in(ys: J.Json, +xs: J.Json) -> Bool:
  match ys:
    case J.JMem{k, v, t}:
      Bool.and(Core.has(xs, k), Core.keys_in(t, xs))
    case _:
      True{}

def Core.json_same(+a: J.Json, +b: J.Json) -> Bool:
  match a:
    case J.JObj{x}:
      Core.json_same.obj(Core.json_same(x, Core.members(b)), b, x)
    case J.JArr{x}:
      Core.json_same.arr(x, b)
    case J.JMem{k, v, t}:
      Bool.and(Core.json_same(v, Core.or_nil(Core.find(b, k))), Core.json_same(t, b))
    case J.JCons{h, t}:
      Core.json_same.cons(Core.json_same(h, Core.json_same.head(b)), Core.json_same(t, Core.json_same.tail(b)), b)
    case J.JNil{}:
      Core.json_same.nil(b)
    case x:
      Core.json_eq(x, b)

def Core.json_same.obj(mems: Bool, b: J.Json, +x: J.Json) -> Bool:
  match b:
    case J.JObj{y}:
      Bool.and(mems, Core.keys_in(y, x))
    case _:
      False{}

def Core.json_same.arr(x: J.Json, b: J.Json) -> Bool:
  match b:
    case J.JArr{y}:
      Core.json_same.chain(x, y)
    case _:
      False{}

def Core.json_same.head(b: J.Json) -> J.Json:
  match b:
    case J.JCons{h, t}:
      h
    case _:
      J.JNil{}

def Core.json_same.tail(b: J.Json) -> J.Json:
  match b:
    case J.JCons{h, t}:
      t
    case _:
      J.JNull{}

def Core.json_same.cons(h: Bool, t: Bool, b: J.Json) -> Bool:
  match b:
    case J.JCons{bh, bt}:
      Bool.and(h, t)
    case _:
      False{}

def Core.json_same.nil(b: J.Json) -> Bool:
  match b:
    case J.JCons{h, t}:
      False{}
    case J.JNull{}:
      False{}
    case _:
      True{}

# An array chain against another: same length, elementwise json_same.
def Core.json_same.chain(x: J.Json, +y: J.Json) -> Bool:
  match x:
    case J.JCons{h, t}:
      Core.json_same.cons(Core.json_same(h, Core.json_same.head(y)), Core.json_same.chain(t, Core.json_same.tail(y)), y)
    case _:
      Core.json_same.end(y)

def Core.json_same.end(y: J.Json) -> Bool:
  match y:
    case J.JNil{}:
      True{}
    case _:
      False{}

def Core.side_eq(a: Side, b: Side) -> Bool:
  match a b:
    case Host{} Host{}:
      True{}
    case Virtual{} Virtual{}:
      True{}
    case _ _:
      False{}

def Core.write_same(a: Write, b: Write) -> Bool:
  match a b:
    case Create{s1, o1} Create{s2, o2}:
      Bool.and(Core.side_eq(s1, s2), Core.json_same(o1, o2))
    case Patch{s1, st1, p1} Patch{s2, st2, p2}:
      Bool.and(Core.side_eq(s1, s2), Bool.and(Core.bool_eq(st1, st2), Core.json_same(p1, p2)))
    case Delete{s1, o1, r1} Delete{s2, o2, r2}:
      Bool.and(Core.side_eq(s1, s2), Bool.and(Core.json_same(o1, o2), String.eq(r1, r2)))
    case _ _:
      False{}

def Core.writes_same(xs: List<&2, Write>, ys: List<&2, Write>) -> Bool:
  match xs ys:
    case Nil{} Nil{}:
      True{}
    case Con{x, xr} Con{y, yr}:
      Bool.and(Core.write_same(x, y), Core.writes_same(xr, yr))
    case _ _:
      False{}

def Core.again_eq(a: Again, b: Again) -> Bool:
  match a b:
    case Settled{} Settled{}:
      True{}
    case AgainNow{} AgainNow{}:
      True{}
    case AgainAfter{x} AgainAfter{y}:
      U32.is_eq(x, y)
    case _ _:
      False{}

# Whether an outcome has these writes (order-free JSON) and this requeue.
def Core.out_same(o: Out, ys: List<&2, Write>, a: Again) -> Bool:
  match o:
    case Out{ws, again}:
      Bool.and(Core.writes_same(ws, ys), Core.again_eq(again, a))

# Object access.

def Core.meta(o: J.Json) -> J.Json:
  J.Json.get(o, "metadata")

def Core.mstr(+o: J.Json, key: String) -> String:
  J.Json.str_or(J.Json.get(Core.meta(o), key), "")

def Core.name(+o: J.Json) -> String:
  Core.mstr(o, "name")

def Core.namespace(+o: J.Json) -> String:
  Core.mstr(o, "namespace")

def Core.uid(+o: J.Json) -> String:
  Core.mstr(o, "uid")

def Core.rv(+o: J.Json) -> String:
  Core.mstr(o, "resourceVersion")

# DeletionTimestamp != nil.
def Core.deleting(+o: J.Json) -> Bool:
  Bool.not(J.Json.is_null(J.Json.get(Core.meta(o), "deletionTimestamp")))

# The member chain of metadata.<field> (labels or annotations).
def Core.mmap(+o: J.Json, field: String) -> J.Json:
  Core.members(J.Json.get(Core.meta(o), field))

def Core.str_of(m: Maybe<&2, J.Json>) -> String:
  match m:
    case None{}:
      ""
    case Some{x}:
      J.Json.str_or(x, "")

# Go obj.GetLabels()[key] / GetAnnotations()[key]: "" when absent.
def Core.label(+o: J.Json, key: String) -> String:
  Core.str_of(Core.find(Core.mmap(o, "labels"), key))

def Core.annotation(+o: J.Json, key: String) -> String:
  Core.str_of(Core.find(Core.mmap(o, "annotations"), key))

# A member chain of strings as a canonical string map (non-strings skipped).
def Core.kvs(ms: J.Json) -> +List<M.KV>:
  match ms:
    case J.JMem{k, J.JStr{v}, t}:
      M.KV{k, v} <> Core.kvs(t)
    case J.JMem{k, v, t}:
      Core.kvs(t)
    case _:
      Nil{}

def Core.map_of(+o: J.Json, field: String) -> +List<M.KV>:
  M.Meta.from_list(Core.kvs(Core.mmap(o, field)))

# A map that Go may hold as nil: None when the field is absent or null.
def Core.maybe_map.if(present: Bool, +o: J.Json, field: String) -> Maybe<&2, List<&2, M.KV>>:
  match present:
    case True{}:
      Some{Core.map_of(o, field)}
    case False{}:
      None{}

def Core.maybe_map(+o: J.Json, +field: String) -> Maybe<&2, List<&2, M.KV>>:
  Core.maybe_map.if(Bool.not(J.Json.is_null(J.Json.get(Core.meta(o), field))), o, field)

# The object's metadata as meta.bend sees it, with kind = the syncer's gvk.
def Core.obj(gvk: String, +o: J.Json) -> M.Obj:
  M.Obj{Core.name(o), Core.namespace(o), Core.uid(o), gvk, Core.deleting(o), Core.map_of(o, "labels"), Core.map_of(o, "annotations")}

def Core.json_kvs(m: +List<M.KV>) -> J.Json:
  match m:
    case Nil{}:
      J.JNil{}
    case Con{M.KV{k, v}, r}:
      J.JMem{k, J.JStr{v}, Core.json_kvs(r)}

# Sets a top-level member; a null value removes it (Go's omitempty).
def Core.put.if(null: Bool, o: J.Json, +key: String, v: J.Json) -> J.Json:
  match null:
    case True{}:
      J.Json.del(o, key)
    case False{}:
      J.Json.set(o, key, v)

def Core.put(o: J.Json, key: String, +v: J.Json) -> J.Json:
  Core.put.if(J.Json.is_null(v), o, key, v)

def Core.set_meta(+o: J.Json, key: String, v: J.Json) -> J.Json:
  J.Json.set(o, "metadata", Core.put(Core.meta(o), key, v))

# Go SetLabels / SetAnnotations: an empty map is omitted.
def Core.map_json.if(empty: Bool, m: +List<M.KV>) -> J.Json:
  match empty:
    case True{}:
      J.JNull{}
    case False{}:
      J.JObj{Core.json_kvs(m)}

def Core.map_json(+m: +List<M.KV>) -> J.Json:
  Core.map_json.if(List.is_empty(&2, M.KV, m), m)

def Core.maybe_map_json(m: Maybe<&2, List<&2, M.KV>>) -> J.Json:
  match m:
    case None{}:
      J.JNull{}
    case Some{x}:
      Core.map_json(x)

def Core.set_map(+o: J.Json, field: String, +m: +List<M.KV>) -> J.Json:
  Core.set_meta(o, field, Core.map_json(m))

# ResetObjectMetadata.
def Core.reset_keys() -> +List<String>:
  ["generateName", "selfLink", "uid", "resourceVersion", "generation", "creationTimestamp",
    "deletionTimestamp", "deletionGracePeriodSeconds", "ownerReferences", "finalizers", "managedFields"]

def Core.drop_keys(ms: J.Json, +ks: +List<String>) -> J.Json:
  match ms:
    case J.JMem{+k, v, t}:
      Core.drop_keys.if(Core.str_in(k, ks), k, v, Core.drop_keys(t, ks))
    case _:
      J.JNil{}

def Core.drop_keys.if(drop: Bool, k: String, v: J.Json, rest: J.Json) -> J.Json:
  match drop:
    case True{}:
      rest
    case False{}:
      J.JMem{k, v, rest}

def Core.keep_keys(ms: J.Json, +ks: +List<String>) -> J.Json:
  match ms:
    case J.JMem{+k, v, t}:
      Core.drop_keys.if(Bool.not(Core.str_in(k, ks)), k, v, Core.keep_keys(t, ks))
    case _:
      J.JNil{}

# CopyObjectWithName(obj, {name, namespace}): metadata reset, name set, and
# the namespace set when the object is namespaced. Owner references are not
# modelled (translate.Owner is nil outside a vcluster pod).
def Core.copy_ns.if(cluster: Bool, o: J.Json, ns: String) -> J.Json:
  match cluster:
    case True{}:
      o
    case False{}:
      Core.set_meta(o, "namespace", J.JStr{ns})

def Core.copy_with_name(+o: J.Json, name: String, ns: String) -> J.Json:
  +reset = J.Json.set(o, "metadata", J.JObj{Core.drop_keys(Core.members(Core.meta(o)), Core.reset_keys())})
  Core.copy_ns.if(String.is_empty(Core.namespace(o)), Core.set_meta(reset, "name", J.JStr{name}), ns)

# Host names (translate.Default, single namespace).
def Core.host_name.if(cluster: Bool, name: String, ns: String, target: String, vc: String) -> String:
  match cluster:
    case True{}:
      N.Names.host_name_cluster(name, target, vc)
    case False{}:
      N.Names.host_name(name, ns, vc)

def Core.host_name(+cfg: Cfg, +v: J.Json) -> String:
  match cfg:
    case Cfg{vc, target, gvk, name, caching, uid_deletion, from_host}:
      Core.host_name.if(String.is_empty(Core.namespace(v)), Core.name(v), Core.namespace(v), target, vc)

# HostLabels(vObj, pObj): HostLabelsMap(vLabels or {}, pLabels, vNamespace,
# true), nil when empty.
def Core.host_labels(vc: String, target: String, +v: J.Json, p: Maybe<&2, List<&2, M.KV>>) -> J.Json:
  Core.maybe_map_json(M.Meta.host_labels_map(vc, target, Some{Core.map_of(v, "labels")}, p, Core.namespace(v), True{}))

def Core.maybe_labels(p: Maybe<&2, J.Json>) -> Maybe<&2, List<&2, M.KV>>:
  match p:
    case None{}:
      None{}
    case Some{x}:
      Core.maybe_map(x, "labels")

# HostMetadata(vObj, {name, target}): the copy carries HostAnnotations(vObj,
# copy) and HostLabels(vObj, nil).
def Core.host_metadata(+cfg: Cfg, +v: J.Json) -> J.Json:
  match cfg:
    case Cfg{+vc, +target, +gvk, name, caching, uid_deletion, from_host}:
      +hname = Core.host_name(Cfg{vc, target, gvk, name, caching, uid_deletion, from_host}, v)
      +copy = Core.copy_with_name(v, hname, target)
      +ann = M.Meta.host_annotations(Core.obj(gvk, v), Some{Core.obj(gvk, copy)}, [])
      +withann = Core.set_map(copy, "annotations", ann)
      Core.set_meta(withann, "labels", Core.host_labels(vc, target, v, None{}))

# VirtualMetadata(pObj, {name, namespace}): the copy carries
# VirtualAnnotations(pObj, nil) and VirtualLabels(pObj, nil).
def Core.virtual_metadata(+cfg: Cfg, +p: J.Json, name: String, ns: String) -> J.Json:
  match cfg:
    case Cfg{+vc, target, +gvk, cname, caching, uid_deletion, from_host}:
      +copy = Core.copy_with_name(p, name, ns)
      +ann = M.Meta.virtual_annotations(Core.obj(gvk, p), None{}, [])
      +withann = Core.set_map(copy, "annotations", ann)
      Core.set_meta(withann, "labels", Core.maybe_map_json(M.Meta.virtual_labels_map(vc, Some{Core.map_of(p, "labels")}, [], [])))

# A virtual namespace (corev1.Namespace{Name: ns}).
def Core.namespace_object(ns: String) -> J.Json:
  J.Json.obj([J.KV{"apiVersion", J.JStr{"v1"}}, J.KV{"kind", J.JStr{"Namespace"}},
    J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{ns}}])}])

# IsManaged and the importer.

# A to-host syncer's IsManaged: the mapping store knows the host object
# (recorder.IsManaged), or translate.Default.IsManaged holds. `expected` is
# mappings.VirtualToHostName of the name annotations (None without mapper).
def Core.is_managed.single(+cfg: Cfg, expected: Maybe<&2, String>, +p: J.Json) -> Bool:
  match cfg:
    case Cfg{vc, target, gvk, name, caching, uid_deletion, from_host}:
      M.Meta.is_managed(vc, target, expected, Core.obj(gvk, p))

def Core.is_managed_to_host(+cfg: Cfg, mapped: Bool, expected: Maybe<&2, String>, +p: J.Json) -> Bool:
  Bool.or(mapped, Core.is_managed.single(cfg, expected, p))

# fromHostTranslate.IsManaged: no marker label, and the host name matches
# the configured mappings (`matched`, from_config_translator.go).
def Core.is_managed_from_host(matched: Bool, +p: J.Json) -> Bool:
  Bool.and(Bool.not(Core.has(Core.mmap(p, "labels"), M.Meta.marker_label())), matched)

# enqueuePhysical: a host event enqueues a reconcile when the object maps to
# a virtual name and is managed, or the importer imports it; the importer is
# asked only for non-delete events on objects that are not deleting. The OSS
# importer imports nothing (pkg/pro/import.go).
def Core.enqueue_host(named: Bool, managed: Bool, imported: Bool, is_delete: Bool, +p: J.Json) -> Bool:
  Bool.and(Bool.or(managed, Bool.and(imported, Bool.and(Bool.not(is_delete), Bool.not(Core.deleting(p))))), named)

# Exclusion (excludeVirtual, excludePhysical).

# A controller label, or a controller annotation naming another syncer.
def Core.controlled(+name: String, +o: J.Json) -> Bool:
  Bool.or(Bool.not(String.is_empty(Core.label(o, M.Meta.controller_label()))),
    M.Meta.set_and_differs(Core.annotation(o, M.Meta.controller_label()), name))

def Core.exclude_virtual(+cfg: Cfg, +v: J.Json) -> Bool:
  match cfg:
    case Cfg{vc, target, gvk, name, caching, uid_deletion, from_host}:
      Bool.and(Bool.not(from_host), Core.controlled(name, v))

# For a managed host object: the from-host syncer excludes objects with a
# marker label; the others exclude controlled objects.
def Core.exclude_physical(+cfg: Cfg, +p: J.Json) -> Bool:
  match cfg:
    case Cfg{vc, target, gvk, name, caching, uid_deletion, from_host}:
      Core.exclude_physical.if(from_host, name, p)

def Core.exclude_physical.if(from_host: Bool, +name: String, +p: J.Json) -> Bool:
  match from_host:
    case True{}:
      Core.has(Core.mmap(p, "labels"), M.Meta.marker_label())
    case False{}:
      Core.controlled(name, p)

def Core.exclude_p(+cfg: Cfg, managed: Bool, p: Maybe<&2, J.Json>) -> Bool:
  match p:
    case None{}:
      False{}
    case Some{x}:
      Bool.or(Bool.not(managed), Core.exclude_physical(cfg, x))

def Core.exclude_v(+cfg: Cfg, v: Maybe<&2, J.Json>) -> Bool:
  match v:
    case None{}:
      False{}
    case Some{x}:
      Core.exclude_virtual(cfg, x)

# Old objects (getObjects): without caching there are none. A missing
# virtual entry is seeded with the object, labels nil and resourceVersion
# "1" (the pre-0.21 label resync); a missing host entry is the object.
def Core.seed(+v: J.Json) -> J.Json:
  Core.set_meta(Core.set_meta(v, "labels", J.JNull{}), "resourceVersion", J.JStr{"1"})

def Core.vold_eff(caching: Bool, vold: Maybe<&2, J.Json>, v: Maybe<&2, J.Json>) -> Maybe<&2, J.Json>:
  match caching:
    case False{}:
      None{}
    case True{}:
      match vold:
        case Some{x}:
          Some{x}
        case None{}:
          match v:
            case None{}:
              None{}
            case Some{x}:
              Some{Core.seed(x)}

def Core.pold_eff(caching: Bool, pold: Maybe<&2, J.Json>, p: Maybe<&2, J.Json>) -> Maybe<&2, J.Json>:
  match caching:
    case False{}:
      None{}
    case True{}:
      match pold:
        case Some{x}:
          Some{x}
        case None{}:
          p

def Core.Cfg.caching(+cfg: Cfg) -> Bool:
  match cfg:
    case Cfg{vc, target, gvk, name, caching, uid_deletion, from_host}:
      caching

# Resource versions (newerResourceVersion with strconv.Atoi; not a number
# is 0, here "").
def Core.digits(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{Chr{+x}, t}:
      Bool.and(Bool.and(U32.is_ge(x, 48), U32.is_le(x, 57)), Core.digits(t))

def Core.atoi.if(ok: Bool, s: String) -> String:
  match ok:
    case True{}:
      s
    case False{}:
      ""

def Core.atoi(+s: String) -> String:
  Core.atoi.if(Core.digits(s), s)

def Core.num_gt.if(c: Cmp, +a: String, +b: String) -> Bool:
  match c:
    case GT{}:
      True{}
    case LT{}:
      False{}
    case EQ{}:
      Cmp.is_gt(String.order(a, b))

def Core.num_gt(+a: String, +b: String) -> Bool:
  Core.num_gt.if(Nat.cmp(String.length(a), String.length(b)), a, b)

# The cache entry is newer than the object read: old RV > new RV.
def Core.outdated(new: Maybe<&2, J.Json>, old: Maybe<&2, J.Json>) -> Bool:
  match new:
    case None{}:
      False{}
    case Some{n}:
      match old:
        case None{}:
          False{}
        case Some{o}:
          Core.num_gt(Core.atoi(Core.rv(o)), Core.atoi(Core.rv(n)))

# The UID guard: the host object names another virtual uid, and its kind
# annotation is empty or this syncer's kind.
def Core.uid_clash(+cfg: Cfg, +v: J.Json, +p: J.Json) -> Bool:
  match cfg:
    case Cfg{vc, target, +gvk, name, caching, uid_deletion, from_host}:
      +pu = Core.annotation(p, M.Meta.uid_annotation())
      +pk = Core.annotation(p, M.Meta.kind_annotation())
      Bool.and(uid_deletion, Bool.and(M.Meta.set_and_differs(pu, Core.uid(v)),
        Bool.or(String.is_empty(pk), String.eq(pk, gvk))))

def Core.skip_backsync(+p: J.Json) -> Bool:
  String.eq(Core.annotation(p, Core.skip_backsync_annotation()), "true")

def Core.decide.both(clash: Bool, deleting: Bool, vold: Maybe<&2, J.Json>, v: J.Json, pold: Maybe<&2, J.Json>, p: J.Json) -> Decision:
  match clash:
    case True{}:
      match deleting:
        case True{}:
          DRequeueAfter{1000}
        case False{}:
          DDeleteHost{p, Core.uid_reason()}
    case False{}:
      DSync{vold, v, pold, p}

def Core.decide.back(skip: Bool, vold: Maybe<&2, J.Json>, p: J.Json) -> Decision:
  match skip:
    case True{}:
      DSkip{}
    case False{}:
      DToVirtual{vold, p}

def Core.decide.d(+cfg: Cfg, vold: Maybe<&2, J.Json>, v: Maybe<&2, J.Json>, pold: Maybe<&2, J.Json>, p: Maybe<&2, J.Json>) -> Decision:
  match v p:
    case Some{+x} Some{+y}:
      Core.decide.both(Core.uid_clash(cfg, x, y), Core.deleting(y), vold, x, pold, y)
    case Some{x} None{}:
      DToHost{pold, x}
    case None{} Some{+y}:
      Core.decide.back(Core.skip_backsync(y), vold, y)
    case None{} None{}:
      DSkip{}

def Core.decide.rv(stale: Bool, +cfg: Cfg, vold: Maybe<&2, J.Json>, v: Maybe<&2, J.Json>, pold: Maybe<&2, J.Json>, p: Maybe<&2, J.Json>) -> Decision:
  match stale:
    case True{}:
      DRequeue{}
    case False{}:
      Core.decide.d(cfg, vold, v, pold, p)

def Core.decide.c(+cfg: Cfg, +vold: Maybe<&2, J.Json>, +v: Maybe<&2, J.Json>, +pold: Maybe<&2, J.Json>, +p: Maybe<&2, J.Json>) -> Decision:
  Core.decide.rv(Bool.or(Core.outdated(p, pold), Core.outdated(v, vold)), cfg, vold, v, pold, p)

def Core.decide.x(excluded: Bool, +cfg: Cfg, vold: Maybe<&2, J.Json>, +v: Maybe<&2, J.Json>, pold: Maybe<&2, J.Json>, +p: Maybe<&2, J.Json>) -> Decision:
  match excluded:
    case True{}:
      DSkip{}
    case False{}:
      Core.decide.c(cfg, Core.vold_eff(Core.Cfg.caching(cfg), vold, v), v, Core.pold_eff(Core.Cfg.caching(cfg), pold, p), p)

# SyncController.Reconcile. vold and pold are the object cache entries,
# v and p the objects read (None: not found); managed is IsManaged(p).
# An excluded object (getObjects) ends the reconcile. The OSS importer
# ignores no host object (IgnoreHostObject is false), and translate patches
# are a Pro feature, so neither appears.
def Core.decide(+cfg: Cfg, managed: Bool, vold: Maybe<&2, J.Json>, +v: Maybe<&2, J.Json>, pold: Maybe<&2, J.Json>, +p: Maybe<&2, J.Json>) -> Decision:
  Core.decide.x(Bool.or(Core.exclude_p(cfg, managed, p), Core.exclude_v(cfg, v)), cfg, vold, v, pold, p)

# JSON merge patches (evanphx/json-patch CreateMergePatch and MergePatch).

def Core.dels.if(present: Bool, k: String, rest: J.Json) -> J.Json:
  match present:
    case True{}:
      rest
    case False{}:
      J.JMem{k, J.JNull{}, rest}

# The members of old whose key the new chain lacks, as nulls.
def Core.dels(old: J.Json, +full: J.Json) -> J.Json:
  match old:
    case J.JMem{+k, v, t}:
      Core.dels.if(Core.has(full, k), k, Core.dels(t, full))
    case _:
      J.JNil{}

def Core.diff.sub(k: String, sub: J.Json, rest: J.Json) -> J.Json:
  match sub:
    case J.JNil{}:
      rest
    case s:
      J.JMem{k, J.JObj{s}, rest}

# A changed object member: absent before, or not an object before, means
# the whole new value; else the nested diff, when not empty.
def Core.diff.obj(k: String, nms: J.Json, found: Maybe<&2, J.Json>, sub: J.Json, rest: J.Json) -> J.Json:
  match found:
    case None{}:
      J.JMem{k, J.JObj{nms}, rest}
    case Some{J.JObj{o}}:
      Core.diff.sub(k, sub, rest)
    case Some{o}:
      J.JMem{k, J.JObj{nms}, rest}

def Core.diff.val.if(same: Bool, k: String, x: J.Json, rest: J.Json) -> J.Json:
  match same:
    case True{}:
      rest
    case False{}:
      J.JMem{k, x, rest}

def Core.diff.val(k: String, +x: J.Json, found: Maybe<&2, J.Json>, rest: J.Json) -> J.Json:
  match found:
    case None{}:
      J.JMem{k, x, rest}
    case Some{o}:
      Core.diff.val.if(Core.json_eq(o, x), k, x, rest)

# getDiff(old, new) on member chains: walks new (`full` is the whole new
# chain), then appends the deleted keys.
def Core.diff(+new: J.Json, +old: J.Json, +full: J.Json) -> J.Json:
  match new:
    case J.JMem{+k, J.JObj{+nms}, t}:
      Core.diff.obj(k, nms, Core.find(old, k), Core.diff(nms, Core.members_of(Core.find(old, k)), nms), Core.diff(t, old, full))
    case J.JMem{+k, +x, t}:
      Core.diff.val(k, x, Core.find(old, k), Core.diff(t, old, full))
    case _:
      Core.dels(old, full)

# CreateMergePatch(before, after): the merge patch that turns before into
# after.
def Core.merge_patch(+before: J.Json, +after: J.Json) -> J.Json:
  match after:
    case J.JObj{+ams}:
      J.JObj{Core.diff(ams, Core.members(before), ams)}
    case x:
      x

# pruneNulls: null members go, recursively (null array items stay).
def Core.prune(j: J.Json) -> J.Json:
  match j:
    case J.JObj{ms}:
      J.JObj{Core.prune(ms)}
    case J.JArr{xs}:
      J.JArr{Core.prune(xs)}
    case J.JCons{h, t}:
      J.JCons{Core.prune(h), Core.prune(t)}
    case J.JMem{k, J.JNull{}, t}:
      Core.prune(t)
    case J.JMem{k, v, t}:
      J.JMem{k, Core.prune(v), Core.prune(t)}
    case x:
      x

def Core.is_obj(m: Maybe<&2, J.Json>) -> Bool:
  match m:
    case Some{J.JObj{o}}:
      True{}
    case _:
      False{}

# merge(cur, patch) for an object patch value: into an object, member-wise;
# else the pruned patch value.
def Core.merge.obj(cur_obj: Bool, pms: J.Json, merged: J.Json) -> J.Json:
  match cur_obj:
    case True{}:
      J.JObj{merged}
    case False{}:
      Core.prune(J.JObj{pms})

# A non-object patch value replaces; it is pruned unless the current value
# is an object.
def Core.merge.val(cur_obj: Bool, v: J.Json) -> J.Json:
  match cur_obj:
    case True{}:
      v
    case False{}:
      Core.prune(v)

# mergeDocs(doc, patch) on member chains.
def Core.merge_into(+patch: J.Json, +doc: J.Json) -> J.Json:
  match patch:
    case J.JMem{+k, J.JNull{}, t}:
      Core.merge_into(t, J.Json.del_mem(doc, k))
    case J.JMem{+k, J.JObj{+pms}, t}:
      +cur = Core.find(doc, k)
      Core.merge_into(t, J.Json.put_mem(doc, k, Core.merge.obj(Core.is_obj(cur), pms, Core.merge_into(pms, Core.members_of(cur)))))
    case J.JMem{+k, v, t}:
      Core.merge_into(t, J.Json.put_mem(doc, k, Core.merge.val(Core.is_obj(Core.find(doc, k)), v)))
    case _:
      doc

# MergePatch(doc, patch).
def Core.apply_patch(+doc: J.Json, +patch: J.Json) -> J.Json:
  match patch:
    case J.JObj{pms}:
      J.JObj{Core.merge_into(pms, Core.members(doc))}
    case x:
      x

# Patch.DeleteAllExcept("metadata", keep...): an object under metadata keeps
# only the named members.
def Core.keep_meta.if(meta: Bool, k: String, v: J.Json, rest: J.Json) -> J.Json:
  match meta:
    case True{}:
      J.JMem{k, J.JObj{Core.keep_keys(Core.members(v), ["annotations", "labels", "finalizers"])}, rest}
    case False{}:
      J.JMem{k, v, rest}

def Core.keep_meta.v(+k: String, v: J.Json, rest: J.Json) -> J.Json:
  match v:
    case J.JObj{ms}:
      Core.keep_meta.if(String.eq(k, "metadata"), k, J.JObj{ms}, rest)
    case x:
      J.JMem{k, x, rest}

def Core.keep_meta.ms(ms: J.Json) -> J.Json:
  match ms:
    case J.JMem{k, v, t}:
      Core.keep_meta.v(k, v, Core.keep_meta.ms(t))
    case _:
      J.JNil{}

def Core.keep_meta.ms.top(p: J.Json) -> J.Json:
  match p:
    case J.JObj{ms}:
      J.JObj{Core.keep_meta.ms(ms)}
    case x:
      x

# CalculateMergePatch(before, after).
def Core.calc_patch(+before: J.Json, +after: J.Json) -> J.Json:
  Core.keep_meta.ms.top(Core.merge_patch(before, after))

def Core.patch_empty(p: J.Json) -> Bool:
  match p:
    case J.JObj{J.JNil{}}:
      True{}
    case _:
      False{}

# Patch.Delete("status") and DeleteAllExcept("", "status").
def Core.without_status(p: J.Json) -> J.Json:
  match p:
    case J.JObj{ms}:
      J.JObj{Core.drop_keys(ms, ["status"])}
    case x:
      x

def Core.only_status(p: J.Json) -> J.Json:
  match p:
    case J.JObj{ms}:
      J.JObj{Core.keep_keys(ms, ["status"])}
    case x:
      x

# applyObjectWithPatch on an existing object: an empty patch, or one that
# leaves the object as it is, writes nothing.
def Core.step.eq(same: Bool, side: Side, status: Bool, obj: J.Json, obj2: J.Json, patch: J.Json) -> List<&2, Write> & J.Json:
  match same:
    case True{}:
      (Nil{}, obj)
    case False{}:
      ([Patch{side, status, patch}], obj2)

def Core.step.if(empty: Bool, side: Side, status: Bool, +obj: J.Json, +patch: J.Json) -> List<&2, Write> & J.Json:
  match empty:
    case True{}:
      (Nil{}, obj)
    case False{}:
      +obj2 = Core.apply_patch(obj, patch)
      Core.step.eq(Core.json_eq(obj, obj2), side, status, obj, obj2, patch)

def Core.step(side: Side, status: Bool, +obj: J.Json, +patch: J.Json) -> List<&2, Write> & J.Json:
  Core.step.if(Core.patch_empty(patch), side, status, obj, patch)

def Core.apply_object.status(+side: Side, +p: J.Json, r: List<&2, Write> & J.Json) -> List<&2, Write>:
  (w1, o1) = r
  (w2, o2) = Core.step(side, True{}, o1, Core.only_status(p))
  Core.cat(w1, w2)

def Core.apply_object.first(r: List<&2, Write> & J.Json) -> List<&2, Write>:
  (w, o) = r
  w

def Core.apply_object.split(has_status: Bool, +side: Side, +before: J.Json, +p: J.Json) -> List<&2, Write>:
  match has_status:
    case False{}:
      Core.apply_object.first(Core.step(side, False{}, before, p))
    case True{}:
      Core.apply_object.status(side, p, Core.step(side, False{}, before, Core.without_status(p)))

def Core.apply_object.if(same: Bool, +side: Side, +before: J.Json, +after: J.Json, has_status: Bool) -> List<&2, Write>:
  match same:
    case True{}:
      Nil{}
    case False{}:
      Core.apply_object.split(has_status, side, before, Core.calc_patch(before, after))

# ApplyObject(before, after, direction, hasStatus) for an object that
# exists: the merge patch, without status then status only when the kind has
# a status subresource.
def Core.apply_object(+side: Side, +before: J.Json, +after: J.Json, has_status: Bool) -> List<&2, Write>:
  Core.apply_object.if(Core.json_eq(before, after), side, before, after, has_status)

def Core.patch_host(skip: Bool, +before: J.Json, +after: J.Json, has_status: Bool) -> List<&2, Write>:
  match skip:
    case True{}:
      Nil{}
    case False{}:
      Core.apply_object(Host{}, before, after, has_status)

# SyncerPatcher.Patch: the virtual object, then the host object (skipped
# with SkipHostPatch).
def Core.patch_writes(+vbefore: J.Json, +vafter: J.Json, +pbefore: J.Json, +pafter: J.Json, skip_host: Bool, +has_status: Bool) -> List<&2, Write>:
  Core.cat(Core.apply_object(Virtual{}, vbefore, vafter, has_status), Core.patch_host(skip_host, pbefore, pafter, has_status))

# CopyBidirectional and MergeBidirectional.

def Core.cb.if(vsame: Bool, hsame: Bool, +v: J.Json, +h: J.Json) -> J.Json & J.Json:
  match vsame:
    case False{}:
      (v, v)
    case True{}:
      match hsame:
        case False{}:
          (h, h)
        case True{}:
          (v, h)

# CopyBidirectional(virtualOld, virtual, hostOld, host) = (virtual', host').
def Core.copy_bidirectional(+vo: J.Json, +v: J.Json, +ho: J.Json, +h: J.Json) -> J.Json & J.Json:
  Core.cb.if(Core.json_eq(vo, v), Core.json_eq(ho, h), v, h)

# MergeChangesInto(old, new, out): a nil out takes new; else the merge
# patch from old to new applied to out.
def Core.merge_changes_into(+old: J.Json, +new: J.Json, out: J.Json) -> J.Json:
  match out:
    case J.JNull{}:
      new
    case o:
      Core.apply_patch(o, Core.merge_patch(old, new))

def Core.mb.if(vsame: Bool, hsame: Bool, +vo: J.Json, +v: J.Json, +ho: J.Json, +h: J.Json) -> J.Json & J.Json:
  match vsame:
    case False{}:
      (v, Core.merge_changes_into(vo, v, h))
    case True{}:
      match hsame:
        case False{}:
          (Core.merge_changes_into(ho, h, v), h)
        case True{}:
          (v, h)

# MergeBidirectional(virtualOld, virtual, hostOld, host) = (virtual', host').
def Core.merge_bidirectional(+vo: J.Json, +v: J.Json, +ho: J.Json, +h: J.Json) -> J.Json & J.Json:
  Core.mb.if(Core.json_eq(vo, v), Core.json_eq(ho, h), vo, v, ho, h)

# Copies each named top-level field bidirectionally (as the to-host secret
# and configmap syncers do for .data). A missing old object means no change
# on that side.
def Core.or_same(m: Maybe<&2, J.Json>, +x: J.Json) -> J.Json:
  match m:
    case None{}:
      x
    case Some{o}:
      o

def Core.copy_field.fin(+f: String, r: J.Json & J.Json, v: J.Json, h: J.Json) -> J.Json & J.Json:
  (nv, nh) = r
  (Core.put(v, f, nv), Core.put(h, f, nh))

def Core.copy_fields(fs: +List<String>, +vo: J.Json, +ho: J.Json, vh: J.Json & J.Json) -> J.Json & J.Json:
  match fs:
    case Nil{}:
      vh
    case Con{+f, r}:
      (v0, h0) = vh
      +v = v0
      +h = h0
      Core.copy_fields(r, vo, ho, Core.copy_field.fin(f, Core.copy_bidirectional(J.Json.get(vo, f), J.Json.get(v, f), J.Json.get(ho, f), J.Json.get(h, f)), v, h))

# Generic outcomes of a decision.

def Core.none() -> Out:
  Out{Nil{}, Settled{}}

def Core.just(w: Write) -> Out:
  Out{[w], Settled{}}

# The generic to-host syncer (the secrets and configmaps shape).

# SyncToHost: a host object that was synced before (HostOld) or a deleting
# virtual object deletes the virtual object; else the host object is
# created from HostMetadata.
def Core.to_host.create.if(gone: Bool, +cfg: Cfg, +v: J.Json) -> Out:
  match gone:
    case True{}:
      Core.just(Delete{Virtual{}, v, "host object was deleted"})
    case False{}:
      Core.just(Create{Host{}, Core.host_metadata(cfg, v)})

def Core.to_host.create(+cfg: Cfg, hold: Maybe<&2, J.Json>, +v: J.Json) -> Out:
  Core.to_host.create.if(Bool.or(Maybe.is_some(&2, J.Json, hold), Core.deleting(v)), cfg, v)

# SyncToVirtual: the host object is deleted when the virtual object existed
# (VirtualOld) or ShouldDeleteHostObject holds.
def Core.to_host.back.if(del: Bool, p: J.Json) -> Out:
  match del:
    case True{}:
      Core.just(Delete{Host{}, p, "virtual object was deleted"})
    case False{}:
      Core.none()

def Core.to_host.back(+cfg: Cfg, vold: Maybe<&2, J.Json>, +p: J.Json) -> Out:
  match cfg:
    case Cfg{vc, target, gvk, name, caching, uid_deletion, from_host}:
      Core.to_host.back.if(Bool.or(Maybe.is_some(&2, J.Json, vold), M.Meta.should_delete_host_object(Core.obj(gvk, p))), p)

# Sync: the host takes HostAnnotations(v, p) and HostLabels(v, p), the
# fields are copied bidirectionally, and both sides are patched (with a
# status subresource).
def Core.to_host.sync(+cfg: Cfg, +fields: +List<String>, vold: Maybe<&2, J.Json>, +v: J.Json, pold: Maybe<&2, J.Json>, +p: J.Json) -> Out:
  match cfg:
    case Cfg{+vc, +target, +gvk, name, caching, uid_deletion, from_host}:
      +ann = M.Meta.host_annotations(Core.obj(gvk, v), Some{Core.obj(gvk, p)}, [])
      +p1 = Core.set_meta(Core.set_map(p, "annotations", ann), "labels", Core.host_labels(vc, target, v, Core.maybe_map(p, "labels")))
      (v2, p2) = Core.copy_fields(fields, Core.or_same(vold, v), Core.or_same(pold, p), (v, p1))
      Out{Core.patch_writes(v, v2, p, p2, False{}, True{}), Settled{}}

# The generic outcomes, then the syncer's.
def Core.to_host.run(+cfg: Cfg, +fields: +List<String>, d: Decision) -> Out:
  match d:
    case DSkip{}:
      Core.none()
    case DRequeue{}:
      Out{Nil{}, AgainNow{}}
    case DRequeueAfter{ms}:
      Out{Nil{}, AgainAfter{ms}}
    case DDeleteHost{h, r}:
      Core.just(Delete{Host{}, h, r})
    case DSync{vo, x, po, y}:
      Core.to_host.sync(cfg, fields, vo, x, po, y)
    case DToHost{ho, x}:
      Core.to_host.create(cfg, ho, x)
    case DToVirtual{vo, y}:
      Core.to_host.back(cfg, vo, y)

def Core.reconcile_to_host(+cfg: Cfg, +fields: +List<String>, managed: Bool, vold: Maybe<&2, J.Json>, v: Maybe<&2, J.Json>, pold: Maybe<&2, J.Json>, p: Maybe<&2, J.Json>) -> Out:
  Core.to_host.run(cfg, fields, Core.decide(cfg, managed, vold, v, pold, p))

# The generic from-host syncer (genericFromHostSyncer).

# SyncToHost: the host object is gone; the virtual object is deleted when
# the host object was seen before (HostOld).
def Core.from_host.to_host(hold: Maybe<&2, J.Json>, v: J.Json) -> Out:
  match hold:
    case None{}:
      Core.none()
    case Some{h}:
      Core.just(Delete{Virtual{}, v, ""})

# SyncToVirtual: a deleting host object deletes the old virtual object;
# else the virtual namespace must exist (created, then requeue; a
# terminating one requeues after 5s), then VirtualMetadata is created.
def Core.from_host.create(+cfg: Cfg, +p: J.Json, vname: String, +vns: String, ns: NsState) -> Out:
  match ns:
    case NsMissing{}:
      Out{[Create{Virtual{}, Core.namespace_object(vns)}], AgainNow{}}
    case NsTerminating{}:
      Out{Nil{}, AgainAfter{5000}}
    case NsReady{}:
      Core.just(Create{Virtual{}, Core.virtual_metadata(cfg, p, vname, vns)})

def Core.from_host.to_virtual.if(gone: Bool, +cfg: Cfg, vold: Maybe<&2, J.Json>, +p: J.Json, vname: String, vns: String, ns: NsState) -> Out:
  match gone:
    case True{}:
      Core.just(Delete{Virtual{}, Core.or_same(vold, p), "host object was deleted"})
    case False{}:
      Core.from_host.create(cfg, p, vname, vns, ns)

def Core.from_host.to_virtual(+cfg: Cfg, +vold: Maybe<&2, J.Json>, +p: J.Json, vname: String, vns: String, ns: NsState) -> Out:
  Core.from_host.to_virtual.if(Bool.and(Maybe.is_some(&2, J.Json, vold), Core.deleting(p)), cfg, vold, p, vname, vns, ns)

# CopyHostObjectToVirtual of the configmap and secret from-host syncers:
# annotations and labels as the host has them, and the named fields.
def Core.from_host.fields(fs: +List<String>, +v: J.Json, +p: J.Json) -> J.Json:
  match fs:
    case Nil{}:
      v
    case Con{+f, r}:
      Core.from_host.fields(r, Core.put(v, f, J.Json.get(p, f)), p)

def Core.from_host.copy(+fields: +List<String>, +v: J.Json, +p: J.Json) -> J.Json:
  +v1 = Core.set_meta(Core.set_meta(v, "annotations", J.Json.get(Core.meta(p), "annotations")), "labels", J.Json.get(Core.meta(p), "labels"))
  Core.from_host.fields(fields, v1, p)

# Sync: the virtual object takes the host's state; the host is never
# patched (SkipHostPatch).
def Core.from_host.sync(+fields: +List<String>, +v: J.Json, +p: J.Json) -> Out:
  Out{Core.patch_writes(v, Core.from_host.copy(fields, v, p), p, p, True{}, True{}), Settled{}}

def Core.from_host.run(+cfg: Cfg, +fields: +List<String>, vname: String, vns: String, ns: NsState, d: Decision) -> Out:
  match d:
    case DSkip{}:
      Core.none()
    case DRequeue{}:
      Out{Nil{}, AgainNow{}}
    case DRequeueAfter{ms}:
      Out{Nil{}, AgainAfter{ms}}
    case DDeleteHost{h, r}:
      Core.just(Delete{Host{}, h, r})
    case DSync{vo, x, po, y}:
      Core.from_host.sync(fields, x, y)
    case DToHost{ho, x}:
      Core.from_host.to_host(ho, x)
    case DToVirtual{vo, y}:
      Core.from_host.to_virtual(cfg, vo, y, vname, vns, ns)

# vname/vns: HostToVirtual of the host object; ns: the virtual namespace.
def Core.reconcile_from_host(+cfg: Cfg, +fields: +List<String>, managed: Bool, vold: Maybe<&2, J.Json>, v: Maybe<&2, J.Json>, pold: Maybe<&2, J.Json>, p: Maybe<&2, J.Json>, vname: String, vns: String, ns: NsState) -> Out:
  Core.from_host.run(cfg, fields, vname, vns, ns, Core.decide(cfg, managed, vold, v, pold, p))

# The object cache after a failed sync (patcher.go cacheRebase.apply):
# nothing written keeps the entry; a write with no entry before drops it;
# else the old entry plus what the syncer wrote (CalculateMergePatch from
# the object read to the object written), at the written resource version.
def Core.cache_rebase.c(cached: Maybe<&2, J.Json>, +before: J.Json, +w: J.Json) -> Maybe<&2, J.Json>:
  match cached:
    case None{}:
      None{}
    case Some{c}:
      Some{Core.set_meta(Core.apply_patch(c, Core.calc_patch(before, w)), "resourceVersion", J.JStr{Core.rv(w)})}

def Core.cache_rebase(cached: Maybe<&2, J.Json>, +before: J.Json, written: Maybe<&2, J.Json>) -> Maybe<&2, J.Json>:
  match written:
    case None{}:
      cached
    case Some{w}:
      Core.cache_rebase.c(cached, before, w)

# sanitizePatchForLog (apply.go): for a Secret, the values of data and
# stringData and the data inside the kubectl last-applied annotation become
# "[REDACTED]"; anything that does not parse becomes "[REDACTED]".
# Differences: members keep their order (Go sorts keys) and Go's HTML
# escaping of <, > and & is not applied.

def Core.redacted() -> String:
  "[REDACTED]"

def Core.redact_keys(ms: J.Json) -> J.Json:
  match ms:
    case J.JMem{k, v, t}:
      J.JMem{k, J.JStr{Core.redacted()}, Core.redact_keys(t)}
    case _:
      J.JNil{}

# One data field's value: null stays, an object keeps its keys, anything
# else becomes "[REDACTED]".
def Core.redact_value(v: J.Json) -> J.Json:
  match v:
    case J.JNull{}:
      J.JNull{}
    case J.JObj{ms}:
      J.JObj{Core.redact_keys(ms)}
    case _:
      J.JStr{Core.redacted()}

def Core.redact_fields.if(hit: Bool, k: String, v: J.Json, rest: J.Json) -> J.Json:
  match hit:
    case True{}:
      J.JMem{k, Core.redact_value(v), rest}
    case False{}:
      J.JMem{k, v, rest}

# redactSecretDataFields on a member chain.
def Core.redact_fields(ms: J.Json) -> J.Json:
  match ms:
    case J.JMem{+k, v, t}:
      Core.redact_fields.if(Bool.or(String.eq(k, "data"), String.eq(k, "stringData")), k, v, Core.redact_fields(t))
    case _:
      J.JNil{}

def Core.last_applied_key() -> String:
  "kubectl.kubernetes.io/last-applied-configuration"

def Core.sanitize.manifest(r: Result<&2, &2, String, J.Json>) -> J.Json:
  match r:
    case Fail{e}:
      J.JStr{Core.redacted()}
    case Done{J.JObj{ms}}:
      J.JStr{J.Json.show(J.JObj{Core.redact_fields(ms)})}
    case Done{J.JNull{}}:
      J.JStr{"null"}
    case Done{x}:
      J.JStr{Core.redacted()}

# sanitizeLastAppliedAnnotationValue.
def Core.sanitize.annotation(raw: J.Json) -> J.Json:
  match raw:
    case J.JStr{s}:
      Core.sanitize.manifest(J.Json.parse(s))
    case _:
      J.JStr{Core.redacted()}

def Core.sanitize.anns(found: Maybe<&2, J.Json>, +ams: J.Json) -> J.Json:
  match found:
    case None{}:
      ams
    case Some{raw}:
      J.Json.put_mem(ams, Core.last_applied_key(), Core.sanitize.annotation(raw))

def Core.sanitize.meta_ms(+mms: J.Json, found: Maybe<&2, J.Json>) -> J.Json:
  match found:
    case Some{J.JObj{+ams}}:
      J.Json.put_mem(mms, "annotations", J.JObj{Core.sanitize.anns(Core.find(ams, Core.last_applied_key()), ams)})
    case _:
      mms

def Core.sanitize.meta(+ms: J.Json, found: Maybe<&2, J.Json>) -> J.Json:
  match found:
    case Some{J.JObj{+mms}}:
      J.Json.put_mem(ms, "metadata", J.JObj{Core.sanitize.meta_ms(mms, Core.find(mms, "annotations"))})
    case _:
      ms

# redactLastAppliedAnnotation on the top member chain.
def Core.sanitize.last_applied(+ms: J.Json) -> J.Json:
  Core.sanitize.meta(ms, Core.find(ms, "metadata"))

def Core.sanitize.parsed(r: Result<&2, &2, String, J.Json>) -> String:
  match r:
    case Fail{e}:
      Core.redacted()
    case Done{J.JObj{ms}}:
      J.Json.show(J.JObj{Core.sanitize.last_applied(Core.redact_fields(ms))})
    case Done{J.JNull{}}:
      "null"
    case Done{x}:
      Core.redacted()

def Core.sanitize(is_secret: Bool, patch: String) -> String:
  match is_secret:
    case False{}:
      patch
    case True{}:
      Core.sanitize.parsed(J.Json.parse(patch))
