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
  ?TODO

def Core.uid_reason() -> String:
  ?TODO

# Lists.

def Core.cat(xs: List<&2, Write>, ys: List<&2, Write>) -> List<&2, Write>:
  ?TODO

def Core.str_in(+k: String, xs: +List<String>) -> Bool:
  ?TODO

# JSON equality: structural, as Go's DeepEqual on decoded JSON (member order
# counts here; see Core.json_same for an order-free comparison).

def Core.bool_eq(a: Bool, b: Bool) -> Bool:
  ?TODO

def Core.json_eq(a: J.Json, b: J.Json) -> Bool:
  ?TODO

# Member chains.

def Core.find.if(hit: Bool, v: J.Json, rec: Maybe<&2, J.Json>) -> Maybe<&2, J.Json>:
  ?TODO

# The value of key in a member chain (the first member with that key).
def Core.find(ms: J.Json, +key: String) -> Maybe<&2, J.Json>:
  ?TODO

def Core.has(ms: J.Json, +key: String) -> Bool:
  ?TODO

def Core.or_nil(m: Maybe<&2, J.Json>) -> J.Json:
  ?TODO

# The member chain of an object; JNil for anything else.
def Core.members(j: J.Json) -> J.Json:
  ?TODO

def Core.members_of(m: Maybe<&2, J.Json>) -> J.Json:
  ?TODO

# Order-free JSON comparison, for laws and tests: objects are equal when
# they have the same keys with equal values. In a member chain a JNil ends
# the chain (every member was found); JNil also stands for an absent value.
def Core.keys_in(ys: J.Json, +xs: J.Json) -> Bool:
  ?TODO

def Core.json_same(+a: J.Json, +b: J.Json) -> Bool:
  ?TODO

def Core.json_same.obj(mems: Bool, b: J.Json, +x: J.Json) -> Bool:
  ?TODO

def Core.json_same.arr(x: J.Json, b: J.Json) -> Bool:
  ?TODO

def Core.json_same.head(b: J.Json) -> J.Json:
  ?TODO

def Core.json_same.tail(b: J.Json) -> J.Json:
  ?TODO

def Core.json_same.cons(h: Bool, t: Bool, b: J.Json) -> Bool:
  ?TODO

def Core.json_same.nil(b: J.Json) -> Bool:
  ?TODO

# An array chain against another: same length, elementwise json_same.
def Core.json_same.chain(x: J.Json, +y: J.Json) -> Bool:
  ?TODO

def Core.json_same.end(y: J.Json) -> Bool:
  ?TODO

def Core.side_eq(a: Side, b: Side) -> Bool:
  ?TODO

def Core.write_same(a: Write, b: Write) -> Bool:
  ?TODO

def Core.writes_same(xs: List<&2, Write>, ys: List<&2, Write>) -> Bool:
  ?TODO

def Core.again_eq(a: Again, b: Again) -> Bool:
  ?TODO

# Whether an outcome has these writes (order-free JSON) and this requeue.
def Core.out_same(o: Out, ys: List<&2, Write>, a: Again) -> Bool:
  ?TODO

# Object access.

def Core.meta(o: J.Json) -> J.Json:
  ?TODO

def Core.mstr(+o: J.Json, key: String) -> String:
  ?TODO

def Core.name(+o: J.Json) -> String:
  ?TODO

def Core.namespace(+o: J.Json) -> String:
  ?TODO

def Core.uid(+o: J.Json) -> String:
  ?TODO

def Core.rv(+o: J.Json) -> String:
  ?TODO

# DeletionTimestamp != nil.
def Core.deleting(+o: J.Json) -> Bool:
  ?TODO

# The member chain of metadata.<field> (labels or annotations).
def Core.mmap(+o: J.Json, field: String) -> J.Json:
  ?TODO

def Core.str_of(m: Maybe<&2, J.Json>) -> String:
  ?TODO

# Go obj.GetLabels()[key] / GetAnnotations()[key]: "" when absent.
def Core.label(+o: J.Json, key: String) -> String:
  ?TODO

def Core.annotation(+o: J.Json, key: String) -> String:
  ?TODO

# A member chain of strings as a canonical string map (non-strings skipped).
def Core.kvs(ms: J.Json) -> +List<M.KV>:
  ?TODO

def Core.map_of(+o: J.Json, field: String) -> +List<M.KV>:
  ?TODO

# A map that Go may hold as nil: None when the field is absent or null.
def Core.maybe_map.if(present: Bool, +o: J.Json, field: String) -> Maybe<&2, List<&2, M.KV>>:
  ?TODO

def Core.maybe_map(+o: J.Json, +field: String) -> Maybe<&2, List<&2, M.KV>>:
  ?TODO

# The object's metadata as meta.bend sees it, with kind = the syncer's gvk.
def Core.obj(gvk: String, +o: J.Json) -> M.Obj:
  ?TODO

def Core.json_kvs(m: +List<M.KV>) -> J.Json:
  ?TODO

# Sets a top-level member; a null value removes it (Go's omitempty).
def Core.put.if(null: Bool, o: J.Json, +key: String, v: J.Json) -> J.Json:
  ?TODO

def Core.put(o: J.Json, key: String, +v: J.Json) -> J.Json:
  ?TODO

def Core.set_meta(+o: J.Json, key: String, v: J.Json) -> J.Json:
  ?TODO

# Go SetLabels / SetAnnotations: an empty map is omitted.
def Core.map_json.if(empty: Bool, m: +List<M.KV>) -> J.Json:
  ?TODO

def Core.map_json(+m: +List<M.KV>) -> J.Json:
  ?TODO

def Core.maybe_map_json(m: Maybe<&2, List<&2, M.KV>>) -> J.Json:
  ?TODO

def Core.set_map(+o: J.Json, field: String, +m: +List<M.KV>) -> J.Json:
  ?TODO

# ResetObjectMetadata.
def Core.reset_keys() -> +List<String>:
  ?TODO

def Core.drop_keys(ms: J.Json, +ks: +List<String>) -> J.Json:
  ?TODO

def Core.drop_keys.if(drop: Bool, k: String, v: J.Json, rest: J.Json) -> J.Json:
  ?TODO

def Core.keep_keys(ms: J.Json, +ks: +List<String>) -> J.Json:
  ?TODO

# CopyObjectWithName(obj, {name, namespace}): metadata reset, name set, and
# the namespace set when the object is namespaced. Owner references are not
# modelled (translate.Owner is nil outside a vcluster pod).
def Core.copy_ns.if(cluster: Bool, o: J.Json, ns: String) -> J.Json:
  ?TODO

def Core.copy_with_name(+o: J.Json, name: String, ns: String) -> J.Json:
  ?TODO

# Host names (translate.Default, single namespace).
def Core.host_name.if(cluster: Bool, name: String, ns: String, target: String, vc: String) -> String:
  ?TODO

def Core.host_name(+cfg: Cfg, +v: J.Json) -> String:
  ?TODO

# HostLabels(vObj, pObj): HostLabelsMap(vLabels or {}, pLabels, vNamespace,
# true), nil when empty.
def Core.host_labels(vc: String, target: String, +v: J.Json, p: Maybe<&2, List<&2, M.KV>>) -> J.Json:
  ?TODO

def Core.maybe_labels(p: Maybe<&2, J.Json>) -> Maybe<&2, List<&2, M.KV>>:
  ?TODO

# HostMetadata(vObj, {name, target}): the copy carries HostAnnotations(vObj,
# copy) and HostLabels(vObj, nil).
def Core.host_metadata(+cfg: Cfg, +v: J.Json) -> J.Json:
  ?TODO

# VirtualMetadata(pObj, {name, namespace}): the copy carries
# VirtualAnnotations(pObj, nil) and VirtualLabels(pObj, nil).
def Core.virtual_metadata(+cfg: Cfg, +p: J.Json, name: String, ns: String) -> J.Json:
  ?TODO

# A virtual namespace (corev1.Namespace{Name: ns}).
def Core.namespace_object(ns: String) -> J.Json:
  ?TODO

# IsManaged and the importer.

# A to-host syncer's IsManaged: the mapping store knows the host object
# (recorder.IsManaged), or translate.Default.IsManaged holds. `expected` is
# mappings.VirtualToHostName of the name annotations (None without mapper).
def Core.is_managed.single(+cfg: Cfg, expected: Maybe<&2, String>, +p: J.Json) -> Bool:
  ?TODO

def Core.is_managed_to_host(+cfg: Cfg, mapped: Bool, expected: Maybe<&2, String>, +p: J.Json) -> Bool:
  ?TODO

# fromHostTranslate.IsManaged: no marker label, and the host name matches
# the configured mappings (`matched`, from_config_translator.go).
def Core.is_managed_from_host(matched: Bool, +p: J.Json) -> Bool:
  ?TODO

# enqueuePhysical: a host event enqueues a reconcile when the object maps to
# a virtual name and is managed, or the importer imports it; the importer is
# asked only for non-delete events on objects that are not deleting. The OSS
# importer imports nothing (pkg/pro/import.go).
def Core.enqueue_host(named: Bool, managed: Bool, imported: Bool, is_delete: Bool, +p: J.Json) -> Bool:
  ?TODO

# Exclusion (excludeVirtual, excludePhysical).

# A controller label, or a controller annotation naming another syncer.
def Core.controlled(+name: String, +o: J.Json) -> Bool:
  ?TODO

def Core.exclude_virtual(+cfg: Cfg, +v: J.Json) -> Bool:
  ?TODO

# For a managed host object: the from-host syncer excludes objects with a
# marker label; the others exclude controlled objects.
def Core.exclude_physical(+cfg: Cfg, +p: J.Json) -> Bool:
  ?TODO

def Core.exclude_physical.if(from_host: Bool, +name: String, +p: J.Json) -> Bool:
  ?TODO

def Core.exclude_p(+cfg: Cfg, managed: Bool, p: Maybe<&2, J.Json>) -> Bool:
  ?TODO

def Core.exclude_v(+cfg: Cfg, v: Maybe<&2, J.Json>) -> Bool:
  ?TODO

# Old objects (getObjects): without caching there are none. A missing
# virtual entry is seeded with the object, labels nil and resourceVersion
# "1" (the pre-0.21 label resync); a missing host entry is the object.
def Core.seed(+v: J.Json) -> J.Json:
  ?TODO

def Core.vold_eff(caching: Bool, vold: Maybe<&2, J.Json>, v: Maybe<&2, J.Json>) -> Maybe<&2, J.Json>:
  ?TODO

def Core.pold_eff(caching: Bool, pold: Maybe<&2, J.Json>, p: Maybe<&2, J.Json>) -> Maybe<&2, J.Json>:
  ?TODO

def Core.Cfg.caching(+cfg: Cfg) -> Bool:
  ?TODO

# Resource versions (newerResourceVersion with strconv.Atoi; not a number
# is 0, here "").
def Core.digits(s: String) -> Bool:
  ?TODO

def Core.atoi.if(ok: Bool, s: String) -> String:
  ?TODO

def Core.atoi(+s: String) -> String:
  ?TODO

def Core.num_gt.if(c: Cmp, +a: String, +b: String) -> Bool:
  ?TODO

def Core.num_gt(+a: String, +b: String) -> Bool:
  ?TODO

# The cache entry is newer than the object read: old RV > new RV.
def Core.outdated(new: Maybe<&2, J.Json>, old: Maybe<&2, J.Json>) -> Bool:
  ?TODO

# The UID guard: the host object names another virtual uid, and its kind
# annotation is empty or this syncer's kind.
def Core.uid_clash(+cfg: Cfg, +v: J.Json, +p: J.Json) -> Bool:
  ?TODO

def Core.skip_backsync(+p: J.Json) -> Bool:
  ?TODO

def Core.decide.both(clash: Bool, deleting: Bool, vold: Maybe<&2, J.Json>, v: J.Json, pold: Maybe<&2, J.Json>, p: J.Json) -> Decision:
  ?TODO

def Core.decide.back(skip: Bool, vold: Maybe<&2, J.Json>, p: J.Json) -> Decision:
  ?TODO

def Core.decide.d(+cfg: Cfg, vold: Maybe<&2, J.Json>, v: Maybe<&2, J.Json>, pold: Maybe<&2, J.Json>, p: Maybe<&2, J.Json>) -> Decision:
  ?TODO

def Core.decide.rv(stale: Bool, +cfg: Cfg, vold: Maybe<&2, J.Json>, v: Maybe<&2, J.Json>, pold: Maybe<&2, J.Json>, p: Maybe<&2, J.Json>) -> Decision:
  ?TODO

def Core.decide.c(+cfg: Cfg, +vold: Maybe<&2, J.Json>, +v: Maybe<&2, J.Json>, +pold: Maybe<&2, J.Json>, +p: Maybe<&2, J.Json>) -> Decision:
  ?TODO

def Core.decide.x(excluded: Bool, +cfg: Cfg, vold: Maybe<&2, J.Json>, +v: Maybe<&2, J.Json>, pold: Maybe<&2, J.Json>, +p: Maybe<&2, J.Json>) -> Decision:
  ?TODO

# SyncController.Reconcile. vold and pold are the object cache entries,
# v and p the objects read (None: not found); managed is IsManaged(p).
# An excluded object (getObjects) ends the reconcile. The OSS importer
# ignores no host object (IgnoreHostObject is false), and translate patches
# are a Pro feature, so neither appears.
def Core.decide(+cfg: Cfg, managed: Bool, vold: Maybe<&2, J.Json>, +v: Maybe<&2, J.Json>, pold: Maybe<&2, J.Json>, +p: Maybe<&2, J.Json>) -> Decision:
  ?TODO

# JSON merge patches (evanphx/json-patch CreateMergePatch and MergePatch).

def Core.dels.if(present: Bool, k: String, rest: J.Json) -> J.Json:
  ?TODO

# The members of old whose key the new chain lacks, as nulls.
def Core.dels(old: J.Json, +full: J.Json) -> J.Json:
  ?TODO

def Core.diff.sub(k: String, sub: J.Json, rest: J.Json) -> J.Json:
  ?TODO

# A changed object member: absent before, or not an object before, means
# the whole new value; else the nested diff, when not empty.
def Core.diff.obj(k: String, nms: J.Json, found: Maybe<&2, J.Json>, sub: J.Json, rest: J.Json) -> J.Json:
  ?TODO

def Core.diff.val.if(same: Bool, k: String, x: J.Json, rest: J.Json) -> J.Json:
  ?TODO

def Core.diff.val(k: String, +x: J.Json, found: Maybe<&2, J.Json>, rest: J.Json) -> J.Json:
  ?TODO

# getDiff(old, new) on member chains: walks new (`full` is the whole new
# chain), then appends the deleted keys.
def Core.diff(+new: J.Json, +old: J.Json, +full: J.Json) -> J.Json:
  ?TODO

# CreateMergePatch(before, after): the merge patch that turns before into
# after.
def Core.merge_patch(+before: J.Json, +after: J.Json) -> J.Json:
  ?TODO

# pruneNulls: null members go, recursively (null array items stay).
def Core.prune(j: J.Json) -> J.Json:
  ?TODO

def Core.is_obj(m: Maybe<&2, J.Json>) -> Bool:
  ?TODO

# merge(cur, patch) for an object patch value: into an object, member-wise;
# else the pruned patch value.
def Core.merge.obj(cur_obj: Bool, pms: J.Json, merged: J.Json) -> J.Json:
  ?TODO

# A non-object patch value replaces; it is pruned unless the current value
# is an object.
def Core.merge.val(cur_obj: Bool, v: J.Json) -> J.Json:
  ?TODO

# mergeDocs(doc, patch) on member chains.
def Core.merge_into(+patch: J.Json, +doc: J.Json) -> J.Json:
  ?TODO

# MergePatch(doc, patch).
def Core.apply_patch(+doc: J.Json, +patch: J.Json) -> J.Json:
  ?TODO

# Patch.DeleteAllExcept("metadata", keep...): an object under metadata keeps
# only the named members.
def Core.keep_meta.if(meta: Bool, k: String, v: J.Json, rest: J.Json) -> J.Json:
  ?TODO

def Core.keep_meta.v(+k: String, v: J.Json, rest: J.Json) -> J.Json:
  ?TODO

def Core.keep_meta.ms(ms: J.Json) -> J.Json:
  ?TODO

def Core.keep_meta.ms.top(p: J.Json) -> J.Json:
  ?TODO

# CalculateMergePatch(before, after).
def Core.calc_patch(+before: J.Json, +after: J.Json) -> J.Json:
  ?TODO

def Core.patch_empty(p: J.Json) -> Bool:
  ?TODO

# Patch.Delete("status") and DeleteAllExcept("", "status").
def Core.without_status(p: J.Json) -> J.Json:
  ?TODO

def Core.only_status(p: J.Json) -> J.Json:
  ?TODO

# applyObjectWithPatch on an existing object: an empty patch, or one that
# leaves the object as it is, writes nothing.
def Core.step.eq(same: Bool, side: Side, status: Bool, obj: J.Json, obj2: J.Json, patch: J.Json) -> List<&2, Write> & J.Json:
  ?TODO

def Core.step.if(empty: Bool, side: Side, status: Bool, +obj: J.Json, +patch: J.Json) -> List<&2, Write> & J.Json:
  ?TODO

def Core.step(side: Side, status: Bool, +obj: J.Json, +patch: J.Json) -> List<&2, Write> & J.Json:
  ?TODO

def Core.apply_object.status(+side: Side, +p: J.Json, r: List<&2, Write> & J.Json) -> List<&2, Write>:
  ?TODO

def Core.apply_object.first(r: List<&2, Write> & J.Json) -> List<&2, Write>:
  ?TODO

def Core.apply_object.split(has_status: Bool, +side: Side, +before: J.Json, +p: J.Json) -> List<&2, Write>:
  ?TODO

def Core.apply_object.if(same: Bool, +side: Side, +before: J.Json, +after: J.Json, has_status: Bool) -> List<&2, Write>:
  ?TODO

# ApplyObject(before, after, direction, hasStatus) for an object that
# exists: the merge patch, without status then status only when the kind has
# a status subresource.
def Core.apply_object(+side: Side, +before: J.Json, +after: J.Json, has_status: Bool) -> List<&2, Write>:
  ?TODO

def Core.patch_host(skip: Bool, +before: J.Json, +after: J.Json, has_status: Bool) -> List<&2, Write>:
  ?TODO

# SyncerPatcher.Patch: the virtual object, then the host object (skipped
# with SkipHostPatch).
def Core.patch_writes(+vbefore: J.Json, +vafter: J.Json, +pbefore: J.Json, +pafter: J.Json, skip_host: Bool, +has_status: Bool) -> List<&2, Write>:
  ?TODO

# CopyBidirectional and MergeBidirectional.

def Core.cb.if(vsame: Bool, hsame: Bool, +v: J.Json, +h: J.Json) -> J.Json & J.Json:
  ?TODO

# CopyBidirectional(virtualOld, virtual, hostOld, host) = (virtual', host').
def Core.copy_bidirectional(+vo: J.Json, +v: J.Json, +ho: J.Json, +h: J.Json) -> J.Json & J.Json:
  ?TODO

# MergeChangesInto(old, new, out): a nil out takes new; else the merge
# patch from old to new applied to out.
def Core.merge_changes_into(+old: J.Json, +new: J.Json, out: J.Json) -> J.Json:
  ?TODO

def Core.mb.if(vsame: Bool, hsame: Bool, +vo: J.Json, +v: J.Json, +ho: J.Json, +h: J.Json) -> J.Json & J.Json:
  ?TODO

# MergeBidirectional(virtualOld, virtual, hostOld, host) = (virtual', host').
def Core.merge_bidirectional(+vo: J.Json, +v: J.Json, +ho: J.Json, +h: J.Json) -> J.Json & J.Json:
  ?TODO

# Copies each named top-level field bidirectionally (as the to-host secret
# and configmap syncers do for .data). A missing old object means no change
# on that side.
def Core.or_same(m: Maybe<&2, J.Json>, +x: J.Json) -> J.Json:
  ?TODO

def Core.copy_field.fin(+f: String, r: J.Json & J.Json, v: J.Json, h: J.Json) -> J.Json & J.Json:
  ?TODO

def Core.copy_fields(fs: +List<String>, +vo: J.Json, +ho: J.Json, vh: J.Json & J.Json) -> J.Json & J.Json:
  ?TODO

# Generic outcomes of a decision.

def Core.none() -> Out:
  ?TODO

def Core.just(w: Write) -> Out:
  ?TODO

# The generic to-host syncer (the secrets and configmaps shape).

# SyncToHost: a host object that was synced before (HostOld) or a deleting
# virtual object deletes the virtual object; else the host object is
# created from HostMetadata.
def Core.to_host.create.if(gone: Bool, +cfg: Cfg, +v: J.Json) -> Out:
  ?TODO

def Core.to_host.create(+cfg: Cfg, hold: Maybe<&2, J.Json>, +v: J.Json) -> Out:
  ?TODO

# SyncToVirtual: the host object is deleted when the virtual object existed
# (VirtualOld) or ShouldDeleteHostObject holds.
def Core.to_host.back.if(del: Bool, p: J.Json) -> Out:
  ?TODO

def Core.to_host.back(+cfg: Cfg, vold: Maybe<&2, J.Json>, +p: J.Json) -> Out:
  ?TODO

# Sync: the host takes HostAnnotations(v, p) and HostLabels(v, p), the
# fields are copied bidirectionally, and both sides are patched (with a
# status subresource).
def Core.to_host.sync(+cfg: Cfg, +fields: +List<String>, vold: Maybe<&2, J.Json>, +v: J.Json, pold: Maybe<&2, J.Json>, +p: J.Json) -> Out:
  ?TODO

# The generic outcomes, then the syncer's.
def Core.to_host.run(+cfg: Cfg, +fields: +List<String>, d: Decision) -> Out:
  ?TODO

def Core.reconcile_to_host(+cfg: Cfg, +fields: +List<String>, managed: Bool, vold: Maybe<&2, J.Json>, v: Maybe<&2, J.Json>, pold: Maybe<&2, J.Json>, p: Maybe<&2, J.Json>) -> Out:
  ?TODO

# The generic from-host syncer (genericFromHostSyncer).

# SyncToHost: the host object is gone; the virtual object is deleted when
# the host object was seen before (HostOld).
def Core.from_host.to_host(hold: Maybe<&2, J.Json>, v: J.Json) -> Out:
  ?TODO

# SyncToVirtual: a deleting host object deletes the old virtual object;
# else the virtual namespace must exist (created, then requeue; a
# terminating one requeues after 5s), then VirtualMetadata is created.
def Core.from_host.create(+cfg: Cfg, +p: J.Json, vname: String, +vns: String, ns: NsState) -> Out:
  ?TODO

def Core.from_host.to_virtual.if(gone: Bool, +cfg: Cfg, vold: Maybe<&2, J.Json>, +p: J.Json, vname: String, vns: String, ns: NsState) -> Out:
  ?TODO

def Core.from_host.to_virtual(+cfg: Cfg, +vold: Maybe<&2, J.Json>, +p: J.Json, vname: String, vns: String, ns: NsState) -> Out:
  ?TODO

# CopyHostObjectToVirtual of the configmap and secret from-host syncers:
# annotations and labels as the host has them, and the named fields.
def Core.from_host.fields(fs: +List<String>, +v: J.Json, +p: J.Json) -> J.Json:
  ?TODO

def Core.from_host.copy(+fields: +List<String>, +v: J.Json, +p: J.Json) -> J.Json:
  ?TODO

# Sync: the virtual object takes the host's state; the host is never
# patched (SkipHostPatch).
def Core.from_host.sync(+fields: +List<String>, +v: J.Json, +p: J.Json) -> Out:
  ?TODO

def Core.from_host.run(+cfg: Cfg, +fields: +List<String>, vname: String, vns: String, ns: NsState, d: Decision) -> Out:
  ?TODO

# vname/vns: HostToVirtual of the host object; ns: the virtual namespace.
def Core.reconcile_from_host(+cfg: Cfg, +fields: +List<String>, managed: Bool, vold: Maybe<&2, J.Json>, v: Maybe<&2, J.Json>, pold: Maybe<&2, J.Json>, p: Maybe<&2, J.Json>, vname: String, vns: String, ns: NsState) -> Out:
  ?TODO

# The object cache after a failed sync (patcher.go cacheRebase.apply):
# nothing written keeps the entry; a write with no entry before drops it;
# else the old entry plus what the syncer wrote (CalculateMergePatch from
# the object read to the object written), at the written resource version.
def Core.cache_rebase.c(cached: Maybe<&2, J.Json>, +before: J.Json, +w: J.Json) -> Maybe<&2, J.Json>:
  ?TODO

def Core.cache_rebase(cached: Maybe<&2, J.Json>, +before: J.Json, written: Maybe<&2, J.Json>) -> Maybe<&2, J.Json>:
  ?TODO

# sanitizePatchForLog (apply.go): for a Secret, the values of data and
# stringData and the data inside the kubectl last-applied annotation become
# "[REDACTED]"; anything that does not parse becomes "[REDACTED]".
# Differences: members keep their order (Go sorts keys) and Go's HTML
# escaping of <, > and & is not applied.

def Core.redacted() -> String:
  ?TODO

def Core.redact_keys(ms: J.Json) -> J.Json:
  ?TODO

# One data field's value: null stays, an object keeps its keys, anything
# else becomes "[REDACTED]".
def Core.redact_value(v: J.Json) -> J.Json:
  ?TODO

def Core.redact_fields.if(hit: Bool, k: String, v: J.Json, rest: J.Json) -> J.Json:
  ?TODO

# redactSecretDataFields on a member chain.
def Core.redact_fields(ms: J.Json) -> J.Json:
  ?TODO

def Core.last_applied_key() -> String:
  ?TODO

def Core.sanitize.manifest(r: Result<&2, &2, String, J.Json>) -> J.Json:
  ?TODO

# sanitizeLastAppliedAnnotationValue.
def Core.sanitize.annotation(raw: J.Json) -> J.Json:
  ?TODO

def Core.sanitize.anns(found: Maybe<&2, J.Json>, +ams: J.Json) -> J.Json:
  ?TODO

def Core.sanitize.meta_ms(+mms: J.Json, found: Maybe<&2, J.Json>) -> J.Json:
  ?TODO

def Core.sanitize.meta(+ms: J.Json, found: Maybe<&2, J.Json>) -> J.Json:
  ?TODO

# redactLastAppliedAnnotation on the top member chain.
def Core.sanitize.last_applied(+ms: J.Json) -> J.Json:
  ?TODO

def Core.sanitize.parsed(r: Result<&2, &2, String, J.Json>) -> String:
  ?TODO

def Core.sanitize(is_secret: Bool, patch: String) -> String:
  ?TODO
