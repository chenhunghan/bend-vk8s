import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ./meta.bend as M
import ./names.bend as N
import ./services.bend as S

# Storage and scheduling syncers (vcluster pkg/controllers/resources:
# persistentvolumeclaims, persistentvolumes real and fake, storageclasses
# toHost, priorityclasses, csinodes), as pure functions of object snapshots.
#
# This follows src/translate/services.bend and reuses its helpers (S.Svc.*):
# objects are bend-kube JSON values, a sync step takes the snapshots that
# vcluster's generic syncer hands it and returns the writes to make, in
# order, with the requeue. Objects compare in canonical form (S.Svc.eq).
# The writes here also carry the delete options vcluster passes (grace
# period and UID precondition), and an outcome carries the error text of a
# step that fails ("" for none).
#
# What the syncers read from the API servers, the mapping store or the
# clock is a parameter: whether the host storage class exists, the result of
# the storage class selector, the claim a host volume names, the virtual
# volume of a claim, the time of a volume lock. Single-namespace mode only;
# Pro patches are no-ops.
#
# vcluster quirks kept as they are:
# - Priority values above 1000000000 are capped to 1000000000 on the host,
#   on create and on every update (priorityclasses/translate.go:15-17,
#   55-59); the host value always follows the virtual one.
# - The priority class selector is checked in Sync for toHost classes too,
#   and a class that fails it deletes the virtual class
#   (priorityclasses/syncer.go:80-89).
# - A claim's deprecated storage class annotation is removed after
#   HostAnnotations listed it in vcluster.loft.sh/managed-annotations, so the
#   host claim names a managed annotation it lacks (persistentvolumeclaims/
#   translate.go:17, 56-61).
# - translateUpdateBackwards of a claim writes "" into a virtual annotation
#   the host lacks when the virtual one is set (persistentvolumeclaims/
#   translate.go:94-111).
# - A claim whose host volume name differs is recreated in the virtual
#   cluster; with real volumes, a host claim that names the same volume as
#   the virtual claim is not checked further (persistentvolumeclaims/
#   syncer.go:213).
# - A deleting virtual volume never reaches the "virtual persistent volume
#   is being deleted" branch of the real volume Sync (persistentvolumes/
#   syncer.go:171-180): the earlier deletion check returns first.
# - The fake volume is created and then patched to phase Bound; here that is
#   one create of the bound volume. Likewise a claim whose volume name is
#   set by ensurePersistentVolume is one virtual update with the rest of
#   the sync.
# - The CSINode Sync sets the marker label on the virtual object to the
#   vcluster name (not the cluster marker), and copies host annotations and
#   labels verbatim (csinodes/syncer.go:96-108).

# Delete options: grace period seconds and UID precondition (JNull: unset).
type Del is Data:
  Del{grace: J.Json, uid: J.Json}

# A write to the host or the virtual cluster.
type Write is Data:
  HostCreate{obj: J.Json}
  HostUpdate{obj: J.Json}
  HostDelete{namespace: String, name: String, opts: Del}
  VirtualCreate{obj: J.Json}
  VirtualUpdate{obj: J.Json}
  VirtualDelete{namespace: String, name: String, opts: Del}

# The writes of one sync step, its requeue, and its error ("" for none).
type Outcome is Data:
  Outcome{writes: List<&2, Write>, requeue: S.Requeue, err: String}

# Priority class sync directions (sync.toHost.priorityClasses.enabled,
# sync.fromHost.priorityClasses.enabled).
type PcCfg is Data:
  PcCfg{to_host: Bool, from_host: Bool}

# Persistent volume claim syncer settings: sync.toHost.storageClasses,
# sync.toHost.volumeSnapshots, and fake volumes
# (!sync.toHost.persistentVolumes.enabled).
type PvcCfg is Data:
  PvcCfg{storage_classes: Bool, snapshots: Bool, fake: Bool}

# What a claim sync reads: limited (applyLimitByClass skips the claim),
# host_class (the host has the claim's storage class), pv (the virtual
# volume named like the host claim's volume), pv_name (the virtual name of
# the host claim's volume, "" when unmapped; real volumes only), now (the
# lock timestamp, metav1.Now() as text).
type PvcLook is Data:
  PvcLook{limited: Bool, host_class: Bool, pv: Maybe<&2, J.Json>, pv_name: String, now: String}

# The virtual claim of a host volume's claim ref: no mapping, a mapping
# whose claim is gone, or the claim.
type Claim is Data:
  Unmapped{}
  Missing{}
  Found{pvc: J.Json}

# What a real volume sync reads: limited (applyLimitByClass), locked (the
# lock annotation is less than a minute old), claim (the virtual claim of
# the host volume's claim ref).
type PvLook is Data:
  PvLook{limited: Bool, locked: Bool, claim: Claim}

# Outcomes and writes.

def St.nodel() -> Del:
  Del{J.JNull{}, J.JNull{}}

def St.from_svc(w: S.Write) -> Write:
  match w:
    case S.HostCreate{o}:
      HostCreate{o}
    case S.HostUpdate{o}:
      HostUpdate{o}
    case S.HostDelete{ns, n}:
      HostDelete{ns, n, St.nodel()}
    case S.VirtualCreate{o}:
      VirtualCreate{o}
    case S.VirtualUpdate{o}:
      VirtualUpdate{o}
    case S.VirtualDelete{ns, n}:
      VirtualDelete{ns, n, St.nodel()}

def St.from_svc_all(ws: List<&2, S.Write>) -> List<&2, Write>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{w, r}:
      St.from_svc(w) <> St.from_svc_all(r)

def St.done(ws: List<&2, Write>) -> Outcome:
  Outcome{ws, S.NoRequeue{}, ""}

def St.canon_write(w: Write) -> Write:
  match w:
    case HostCreate{o}:
      HostCreate{S.Svc.canon(o)}
    case HostUpdate{o}:
      HostUpdate{S.Svc.canon(o)}
    case HostDelete{ns, n, d}:
      HostDelete{ns, n, d}
    case VirtualCreate{o}:
      VirtualCreate{S.Svc.canon(o)}
    case VirtualUpdate{o}:
      VirtualUpdate{S.Svc.canon(o)}
    case VirtualDelete{ns, n, d}:
      VirtualDelete{ns, n, d}

def St.canon_writes(ws: List<&2, Write>) -> List<&2, Write>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{w, r}:
      St.canon_write(w) <> St.canon_writes(r)

# An outcome with every object in canonical form.
def St.canon_outcome(o: Outcome) -> Outcome:
  match o:
    case Outcome{ws, rq, e}:
      Outcome{St.canon_writes(ws), rq, e}

def St.nonempty(ws: List<&2, Write>) -> Bool:
  match ws:
    case Nil{}:
      False{}
    case Con{w, r}:
      True{}

# True when the outcome makes a write.
def St.has_writes(o: Outcome) -> Bool:
  match o:
    case Outcome{ws, rq, e}:
      St.nonempty(ws)

def St.delete_host(+o: J.Json, d: Del) -> Write:
  HostDelete{S.Svc.namespace(o), S.Svc.name(o), d}

def St.delete_virtual(+o: J.Json, d: Del) -> Write:
  VirtualDelete{S.Svc.namespace(o), S.Svc.name(o), d}

# The host update and the virtual update, each when the object changed.
def St.updates(h: J.Json, +h2: J.Json, v: J.Json, +v2: J.Json) -> List<&2, Write>:
  St.from_svc_all(S.Svc.updates(h, h2, v, v2))

# JSON.

def St.deleting(+o: J.Json) -> Bool:
  Bool.not(J.Json.is_null(J.Json.at(o, ["metadata", "deletionTimestamp"])))

def St.spec(+o: J.Json) -> J.Json:
  J.Json.get(o, "spec")

def St.members(j: J.Json) -> J.Json:
  match j:
    case J.JObj{ms}:
      ms
    case _:
      J.JNil{}

# j with member k = v first, and no other member k.
def St.first(j: J.Json, +k: String, v: J.Json) -> J.Json:
  J.JObj{J.JMem{k, v, J.Json.del_mem(St.members(j), k)}}

# o renamed: metadata.name is name, as the first member of the first member.
def St.named(+o: J.Json, name: String) -> J.Json:
  St.first(o, "metadata", St.first(J.Json.get(o, "metadata"), "name", J.JStr{name}))

def St.put_ann(+o: J.Json, +k: String, +v: J.Json) -> J.Json:
  S.Svc.put_in(o, "metadata", "annotations", S.Svc.put(J.Json.at(o, ["metadata", "annotations"]), k, v))

def St.finalizers(+o: J.Json) -> J.Json:
  J.Json.at(o, ["metadata", "finalizers"])

def St.has_finalizers(+o: J.Json) -> Bool:
  Bool.not(S.Svc.zero(St.finalizers(o)))

def St.unfinalized(+o: J.Json) -> J.Json:
  S.Svc.put_in(o, "metadata", "finalizers", J.JNull{})

def St.obj_or_empty(j: J.Json) -> J.Json:
  match j:
    case J.JObj{ms}:
      J.JObj{ms}
    case _:
      J.JObj{J.JNil{}}

def St.only.if(keep: Bool, k: String, v: J.Json, rest: J.Json) -> J.Json:
  match keep:
    case True{}:
      J.JMem{k, v, rest}
    case False{}:
      rest

# The members whose key is one of ks.
def St.only(ms: J.Json, +ks: +List<String>) -> J.Json:
  match ms:
    case J.JMem{+k, v, t}:
      St.only.if(M.Meta.elem(k, ks), k, v, St.only(t, ks))
    case _:
      J.JNil{}

# The members whose key is none of ks.
def St.drop(ms: J.Json, +ks: +List<String>) -> J.Json:
  match ms:
    case J.JMem{+k, v, t}:
      St.only.if(Bool.not(M.Meta.elem(k, ks)), k, v, St.drop(t, ks))
    case _:
      J.JNil{}

def St.chain_append(a: J.Json, b: J.Json) -> J.Json:
  match a:
    case J.JMem{k, v, t}:
      J.JMem{k, v, St.chain_append(t, b)}
    case _:
      b

# Strings of a JSON list.
def St.strs(xs: List<&2, J.Json>) -> +List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, r}:
      S.Svc.str(x) <> St.strs(r)

def St.str_items(xs: +List<String>) -> List<&2, J.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, r}:
      J.JStr{x} <> St.str_items(r)

# The cluster-scoped host name (translate.Default.HostNameCluster).
def St.cluster_name(+c: S.Cfg, name: String) -> String:
  N.Names.host_name_cluster(name, S.Svc.target(c), S.Svc.vc(c))

# Label selectors (metav1.LabelSelector as JSON).

def St.req(+r: J.Json) -> M.Req:
  M.Req{S.Svc.str(J.Json.get(r, "key")), S.Svc.str(J.Json.get(r, "operator")), St.strs(J.Json.items(J.Json.get(r, "values")))}

def St.reqs(xs: List<&2, J.Json>) -> +List<M.Req>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{r, t}:
      St.req(r) <> St.reqs(t)

def St.sel(+j: J.Json) -> M.Sel:
  M.Sel{S.Svc.mmap(J.Json.get(j, "matchLabels")), St.reqs(J.Json.items(J.Json.get(j, "matchExpressions")))}

def St.req_json(r: M.Req) -> J.Json:
  match r:
    case M.Req{k, op, vs}:
      J.Json.obj([J.KV{"key", J.JStr{k}}, J.KV{"operator", J.JStr{op}}, J.KV{"values", J.Json.arr(St.str_items(vs))}])

def St.reqs_json(rs: +List<M.Req>) -> List<&2, J.Json>:
  match rs:
    case Nil{}:
      Nil{}
    case Con{r, t}:
      St.req_json(r) <> St.reqs_json(t)

def St.sel_json(s: Maybe<&2, M.Sel>) -> J.Json:
  match s:
    case None{}:
      J.JNull{}
    case Some{M.Sel{ls, rs}}:
      J.Json.obj([J.KV{"matchLabels", S.Svc.mrender(ls)}, J.KV{"matchExpressions", J.Json.arr(St.reqs_json(rs))}])

# translate.HostLabelSelector of a JSON selector; null stays null.
def St.host_selector.if(isnull: Bool, +vc: String, j: J.Json) -> J.Json:
  match isnull:
    case True{}:
      J.JNull{}
    case False{}:
      St.sel_json(M.Meta.host_label_selector(vc, Some{St.sel(j)}))

def St.host_selector(+vc: String, +j: J.Json) -> J.Json:
  St.host_selector.if(J.Json.is_null(j), vc, j)

# Storage classes (storageclasses/syncer.go), toHost.

def St.sc_kind() -> String:
  "storage.k8s.io/v1, Kind=StorageClass"

# storageclasses.DefaultStorageClassAnnotation, excluded from sync.
def St.default_class() -> String:
  "storageclass.kubernetes.io/is-default-class"

# The host storage class of a virtual one: HostMetadata under the name
# HostNameCluster, without the default-class annotation.
def St.Sc.translate(+c: S.Cfg, +v: J.Json) -> J.Json:
  +n = St.cluster_name(c, S.Svc.name(v))
  St.named(S.Svc.host_metadata(c, St.sc_kind(), [St.default_class()], v, "", n), n)

def St.Sc.to_host.if(delete: Bool, +c: S.Cfg, +v: J.Json) -> Outcome:
  match delete:
    case True{}:
      St.done([St.delete_virtual(v, St.nodel())])
    case False{}:
      St.done([HostCreate{St.Sc.translate(c, v)}])

# storageclasses SyncToHost: the virtual class goes when its host class was
# seen (host_old) or it is deleting; else the host class is created.
def St.Sc.to_host(+c: S.Cfg, host_old: Maybe<&2, J.Json>, +v: J.Json) -> Outcome:
  St.Sc.to_host.if(Bool.or(Maybe.is_some(&2, J.Json, host_old), St.deleting(v)), c, v)

# The fields of patcher.CopyBidirectional in storageclasses Sync, in two
# halves.
def St.Sc.fields_a() -> +List<String>:
  ["provisioner", "parameters", "reclaimPolicy", "mountOptions"]

def St.Sc.fields_b() -> +List<String>:
  ["allowVolumeExpansion", "volumeBindingMode", "allowedTopologies"]

# Annotations and labels of an update, both ways, read from the objects as
# the step changed them so far (h1, v1); the writes compare against the
# objects the step got (h, v).
def St.meta_sync.fin(am: +List<M.KV> & +List<M.KV>, lm: +List<M.KV> & +List<M.KV>, +h: J.Json, +v: J.Json, +h1: J.Json, +v1: J.Json) -> List<&2, Write>:
  (nva, nha) = am
  (nvl, nhl) = lm
  St.updates(h, S.Svc.with_meta(h1, nha, nhl), v, S.Svc.with_meta(v1, nva, nvl))

def St.meta_sync(+c: S.Cfg, +kind: String, +excluded: +List<String>, +ho: J.Json, +vo: J.Json, +h: J.Json, +v: J.Json, +h1: J.Json, +v1: J.Json) -> List<&2, Write>:
  am lm = M.Meta.annotations_bidirectional_update(S.Svc.obj(kind, ho), S.Svc.obj(kind, h1), S.Svc.obj(kind, vo), S.Svc.obj(kind, v1), excluded) S.Svc.labels_bidi(S.Svc.vc(c), S.Svc.labels(vo), S.Svc.labels(v1), S.Svc.labels(ho), S.Svc.labels(h1))
  St.meta_sync.fin(am, lm, h, v, h1, v1)

def St.Sc.sync.fin(+c: S.Cfg, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json, picked: J.Json & J.Json) -> Outcome:
  (v1, h1) = picked
  St.done(St.meta_sync(c, St.sc_kind(), [St.default_class()], ho, vo, h, v, h1, v1))

# storageclasses Sync: annotations and labels both ways, and the seven class
# fields by CopyBidirectional.
def St.Sc.sync(+c: S.Cfg, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> Outcome:
  pa pb = S.Svc.picks(St.Sc.fields_a(), vo, v, ho, h) S.Svc.picks(St.Sc.fields_b(), vo, v, ho, h)
  St.Sc.sync.fin(c, ho, h, vo, v, S.Svc.apply_picks(List.append(&2, S.Pick, pa, pb), v, h))

# storageclasses SyncToVirtual: the host class goes.
def St.Sc.to_virtual(+h: J.Json) -> Outcome:
  St.done([St.delete_host(h, St.nodel())])

# Priority classes (priorityclasses/).

def St.pc_kind() -> String:
  "scheduling.k8s.io/v1, Kind=PriorityClass"

# The highest host priority value.
def St.cap_value() -> String:
  "1000000000"

# constants.SystemPriorityClassesAllowList.
def St.allow_list() -> +List<String>:
  ["system-node-critical", "system-cluster-critical"]

def St.negative(t: String) -> Bool:
  match t:
    case SNil{}:
      False{}
    case SCon{c, r}:
      Char.is_eq(c, '-')

# True when the integer text t (JSON, no leading zeros) is above 1000000000.
def St.exceeds(+t: String) -> Bool:
  +len = String.length(t)
  Bool.and(Bool.not(St.negative(t)),
    Bool.or(Nat.is_lt(10n, len), Bool.and(Nat.is_eq(len, 10n), Cmp.is_gt(String.order(t, St.cap_value())))))

def St.cap_text.if(over: Bool, t: String) -> String:
  match over:
    case True{}:
      St.cap_value()
    case False{}:
      t

# `if value > 1000000000 { value = 1000000000 }`.
def St.cap_text(+t: String) -> String:
  St.cap_text.if(St.exceeds(t), t)

# A priority value capped; anything but a number stays.
def St.cap(j: J.Json) -> J.Json:
  match j:
    case J.JNum{t}:
      J.JNum{St.cap_text(t)}
    case x:
      x

# True when a priority value is a number above the cap.
def St.exceeds_json(j: J.Json) -> Bool:
  match j:
    case J.JNum{t}:
      St.exceeds(t)
    case _:
      False{}

def St.Pc.to_host_on(f: PcCfg) -> Bool:
  match f:
    case PcCfg{t, h}:
      t

def St.Pc.from_host_on(f: PcCfg) -> Bool:
  match f:
    case PcCfg{t, h}:
      h

# priorityclasses translate: HostMetadata under HostNameCluster, globalDefault
# false, the value capped.
def St.Pc.translate(+c: S.Cfg, +v: J.Json) -> J.Json:
  +n = St.cluster_name(c, S.Svc.name(v))
  o1 = J.Json.del(S.Svc.host_metadata(c, St.pc_kind(), [], v, "", n), "globalDefault")
  St.first(St.named(o1, n), "value", St.cap(J.Json.get(v, "value")))

def St.Pc.vname.if(empty: Bool, ann: String, name: String) -> String:
  match empty:
    case True{}:
      name
    case False{}:
      ann

# priorityclasses translateFromHost: VirtualMetadata under the mirror name
# (the name annotation, else the host name).
def St.Pc.from_host(+c: S.Cfg, +h: J.Json) -> J.Json:
  +ann = S.Svc.annotation(M.Meta.name_annotation(), h)
  S.Svc.virtual_metadata(c, St.pc_kind(), [], h, "", St.Pc.vname.if(String.is_empty(ann), ann, S.Svc.name(h)))

def St.Pc.to_host.if(delete: Bool, +c: S.Cfg, +v: J.Json) -> Outcome:
  match delete:
    case True{}:
      St.done([St.delete_virtual(v, St.nodel())])
    case False{}:
      St.done([HostCreate{St.Pc.translate(c, v)}])

# priorityclasses SyncToHost: without toHost, or with fromHost once the host
# class was seen, the virtual class goes; else the host class is created.
def St.Pc.to_host(+c: S.Cfg, +f: PcCfg, host_old: Maybe<&2, J.Json>, +v: J.Json) -> Outcome:
  St.Pc.to_host.if(Bool.or(Bool.not(St.Pc.to_host_on(f)), Bool.and(St.Pc.from_host_on(f), Maybe.is_some(&2, J.Json, host_old))), c, v)

# True when the host class passes: on the allow list, or matched by
# sync.fromHost.priorityClasses.selector.
def St.Pc.passes(+h: J.Json, matches: Bool) -> Bool:
  Bool.or(M.Meta.elem(S.Svc.name(h), St.allow_list()), matches)

def St.Pc.fields() -> +List<String>:
  ["preemptionPolicy", "description"]

# translateUpdate with fromHost: the virtual class takes the host preemption
# policy, description, annotations and labels.
def St.Pc.from_host_update(+h: J.Json, +v: J.Json) -> J.Json:
  v1 = S.Svc.put(S.Svc.put(v, "preemptionPolicy", J.Json.get(h, "preemptionPolicy")), "description", J.Json.get(h, "description"))
  +hm = J.Json.get(h, "metadata")
  v2 = S.Svc.put_in(v1, "metadata", "annotations", J.Json.get(hm, "annotations"))
  S.Svc.put_in(v2, "metadata", "labels", J.Json.get(hm, "labels"))

def St.Pc.to_host_update.fin(+c: S.Cfg, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json, picked: J.Json & J.Json) -> Outcome:
  (v1, h1) = picked
  h2 = S.Svc.put(h1, "value", St.cap(J.Json.get(v, "value")))
  St.done(St.meta_sync(c, St.pc_kind(), [], ho, vo, h, v, h2, v1))

# translateUpdate with toHost: preemption policy and description both ways,
# annotations and labels both ways, the host value the capped virtual one.
def St.Pc.to_host_update(+c: S.Cfg, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> Outcome:
  St.Pc.to_host_update.fin(c, ho, h, vo, v, S.Svc.apply_picks(S.Svc.picks(St.Pc.fields(), vo, v, ho, h), v, h))

def St.Pc.sync.if(passes: Bool, from: Bool, to: Bool, +c: S.Cfg, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> Outcome:
  match passes:
    case False{}:
      St.done([St.delete_virtual(vo, St.nodel())])
    case True{}:
      match from:
        case True{}:
          St.done(St.updates(h, h, v, St.Pc.from_host_update(h, v)))
        case False{}:
          match to:
            case True{}:
              St.Pc.to_host_update(c, ho, h, vo, v)
            case False{}:
              St.done([])

# priorityclasses Sync. matches: the host class matches
# sync.fromHost.priorityClasses.selector.
def St.Pc.sync(+c: S.Cfg, +f: PcCfg, matches: Bool, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> Outcome:
  St.Pc.sync.if(St.Pc.passes(h, matches), St.Pc.from_host_on(f), St.Pc.to_host_on(f), c, ho, h, vo, v)

def St.Pc.to_virtual.if(passes: Bool, delete: Bool, +c: S.Cfg, +h: J.Json) -> Outcome:
  match passes:
    case False{}:
      St.done([])
    case True{}:
      match delete:
        case True{}:
          St.done([St.delete_host(h, St.nodel())])
        case False{}:
          St.done([VirtualCreate{St.Pc.from_host(c, h)}])

# priorityclasses SyncToVirtual: a class that fails the selector is left
# alone; without fromHost, or with toHost once the virtual class was seen,
# or when vcluster made it, the host class goes; else it is copied in.
def St.Pc.to_virtual(+c: S.Cfg, +f: PcCfg, matches: Bool, virtual_old: Maybe<&2, J.Json>, +h: J.Json) -> Outcome:
  delete = Bool.or(Bool.not(St.Pc.from_host_on(f)), Bool.or(Bool.and(Maybe.is_some(&2, J.Json, virtual_old), St.Pc.to_host_on(f)), M.Meta.should_delete_host_object(S.Svc.obj(St.pc_kind(), h))))
  St.Pc.to_virtual.if(St.Pc.passes(h, matches), delete, c, h)

# CSINodes (csinodes/syncer.go), fromHost.

# translate.CopyObjectWithName(h, {name, namespace}, false): the host object
# with its metadata reset, for a cluster-scoped object.
def St.copy_object(+h: J.Json) -> J.Json:
  md = S.Svc.del_all(S.Svc.reset_keys(), J.Json.get(h, "metadata"))
  J.Json.set(h, "metadata", md)

# csinodes SyncToVirtual: node_exists says the virtual cluster has the node
# of that name; only then is the CSINode copied in.
def St.Csi.to_virtual(node_exists: Bool, +h: J.Json) -> Outcome:
  match node_exists:
    case True{}:
      St.done([VirtualCreate{St.copy_object(h)}])
    case False{}:
      St.done([])

def St.Csi.updated(+vc: String, +h: J.Json, +v: J.Json) -> J.Json:
  +hm = J.Json.get(h, "metadata")
  v1 = S.Svc.put_in(v, "metadata", "annotations", J.Json.get(hm, "annotations"))
  v2 = S.Svc.put(v1, "spec", J.Json.get(h, "spec"))
  S.Svc.put_in(v2, "metadata", "labels", S.Svc.render(M.Meta.insert(M.Meta.marker_label(), vc, S.Svc.labels(h))))

# csinodes Sync: without the virtual node the virtual CSINode goes; else it
# takes the host annotations, labels and spec, and the marker label.
def St.Csi.sync(+c: S.Cfg, node_exists: Bool, +h: J.Json, +v: J.Json) -> Outcome:
  match node_exists:
    case False{}:
      St.done([St.delete_virtual(v, St.nodel())])
    case True{}:
      St.done(St.updates(h, h, v, St.Csi.updated(S.Svc.vc(c), h, v)))

def St.Csi.to_host.if(keep: Bool, +v: J.Json) -> Outcome:
  match keep:
    case True{}:
      St.done([])
    case False{}:
      St.done([St.delete_virtual(v, St.nodel())])

# csinodes SyncToHost: a virtual CSINode whose host one was never seen and
# that lacks the marker label is left alone; else it goes.
def St.Csi.to_host(+c: S.Cfg, host_old: Maybe<&2, J.Json>, +v: J.Json) -> Outcome:
  keep = Bool.and(Bool.not(Maybe.is_some(&2, J.Json, host_old)), Bool.not(String.eq(M.Meta.lookup(M.Meta.marker_label(), S.Svc.labels(v)), S.Svc.vc(c))))
  St.Csi.to_host.if(keep, v)

# Persistent volume claims (persistentvolumeclaims/).

# constants.HostClusterPersistentVolumeAnnotation.
def St.host_pv() -> String:
  "vcluster.loft.sh/host-pv"

# persistentvolumes.LockPersistentVolume.
def St.lock() -> String:
  "vcluster.loft.sh/lock"


def St.pvc_kind() -> String:
  "/v1, Kind=PersistentVolumeClaim"

def St.bind_completed() -> String:
  "pv.kubernetes.io/bind-completed"

def St.bound_by_controller() -> String:
  "pv.kubernetes.io/bound-by-controller"

def St.storage_provisioner() -> String:
  "volume.beta.kubernetes.io/storage-provisioner"

def St.pvc_excluded() -> +List<String>:
  [St.bind_completed(), St.bound_by_controller(), St.storage_provisioner()]

def St.deprecated_class() -> String:
  "volume.beta.kubernetes.io/storage-class"

# constants.SkipTranslationAnnotation.
def St.skip_translate() -> String:
  "vcluster.loft.sh/skip-translate"

def St.Pvc.classes_on(p: PvcCfg) -> Bool:
  match p:
    case PvcCfg{sc, vs, fake}:
      sc

def St.Pvc.snapshots_on(p: PvcCfg) -> Bool:
  match p:
    case PvcCfg{sc, vs, fake}:
      vs

def St.Pvc.fake_on(p: PvcCfg) -> Bool:
  match p:
    case PvcCfg{sc, vs, fake}:
      fake

def St.Pvc.class_name.if(set: Bool, s: String, ann: String) -> String:
  match set:
    case True{}:
      s
    case False{}:
      ann

# The claim's storage class: spec.storageClassName, else the deprecated
# annotation.
def St.Pvc.class_name(+o: J.Json) -> String:
  +s = S.Svc.spec_str(o, "storageClassName")
  St.Pvc.class_name.if(Bool.not(String.is_empty(s)), s, S.Svc.annotation(St.deprecated_class(), o))

# The claim with storage class sc and without the deprecated annotation.
def St.Pvc.set_class(+o: J.Json, sc: String) -> J.Json:
  S.Svc.put_in(St.put_ann(o, St.deprecated_class(), J.JNull{}), "spec", "storageClassName", J.JStr{sc})

def St.Pvc.set_class.if(set: Bool, +c: S.Cfg, +o: J.Json, +sc: String) -> J.Json:
  match set:
    case True{}:
      St.Pvc.set_class(o, St.cluster_name(c, sc))
    case False{}:
      o

def St.Pvc.real_class.if(dynamic: Bool, host_class: Bool) -> Bool:
  match dynamic:
    case True{}:
      Bool.not(host_class)
    case False{}:
      True{}

# translateSelector with real volumes: the selector through
# HostLabelSelector, the volume name through HostNameCluster, and, without
# synced storage classes, the class through HostNameCluster when the claim
# is not dynamic or the host lacks the class.
def St.Pvc.real(+c: S.Cfg, classes: Bool, host_class: Bool, +sc: String, +o: J.Json) -> J.Json:
  +s = St.spec(o)
  +sel = St.host_selector(S.Svc.vc(c), J.Json.get(s, "selector"))
  +vol = St.cluster_name(c, S.Svc.str(J.Json.get(s, "volumeName")))
  o1 = S.Svc.put_in(S.Svc.put_in(o, "spec", "selector", sel), "spec", "volumeName", S.Svc.sj(vol))
  dynamic = Bool.and(J.Json.is_null(sel), String.is_empty(vol))
  St.Pvc.set_class.if(Bool.and(Bool.not(classes), Bool.and(Bool.not(String.is_empty(sc)), St.Pvc.real_class.if(dynamic, host_class))), c, o1, sc)

def St.Pvc.real.if(go: Bool, +c: S.Cfg, classes: Bool, host_class: Bool, +sc: String, +o: J.Json) -> J.Json:
  match go:
    case True{}:
      St.Pvc.real(c, classes, host_class, sc, o)
    case False{}:
      o

# translateSelector on the host claim.
def St.Pvc.translate_selector(+c: S.Cfg, +p: PvcCfg, host_class: Bool, +o: J.Json) -> J.Json:
  +sc = St.Pvc.class_name(o)
  +classes = St.Pvc.classes_on(p)
  +o1 = St.Pvc.set_class.if(Bool.and(classes, Bool.not(String.is_empty(sc))), c, o, sc)
  go = Bool.and(Bool.not(St.Pvc.fake_on(p)), Bool.not(String.eq(S.Svc.annotation(St.skip_translate(), o1), "true")))
  St.Pvc.real.if(go, c, classes, host_class, sc, o1)

def St.Pvc.vs_name.if(on: Bool, +c: S.Cfg, name: String, ns: String) -> String:
  match on:
    case True{}:
      N.Names.host_name(name, ns, S.Svc.vc(c))
    case False{}:
      name

def St.Pvc.source_name.go(vs: Bool, pvc: Bool, +c: S.Cfg, +p: PvcCfg, +name: String, +ns: String) -> String:
  match vs:
    case True{}:
      St.Pvc.vs_name.if(St.Pvc.snapshots_on(p), c, name, ns)
    case False{}:
      match pvc:
        case True{}:
          N.Names.host_name(name, ns, S.Svc.vc(c))
        case False{}:
          name

# The host name of a data source (VolumeSnapshot or PersistentVolumeClaim)
# in namespace ns; other kinds keep theirs.
def St.Pvc.source_name(+c: S.Cfg, +p: PvcCfg, +kind: String, +name: String, +ns: String) -> String:
  St.Pvc.source_name.go(String.eq(kind, "VolumeSnapshot"), String.eq(kind, "PersistentVolumeClaim"), c, p, name, ns)

def St.Pvc.source.if(isnull: Bool, +c: S.Cfg, +p: PvcCfg, +ns: String, ds: J.Json) -> J.Json:
  match isnull:
    case True{}:
      J.JNull{}
    case False{}:
      +d = ds
      S.Svc.put(d, "name", S.Svc.sj(St.Pvc.source_name(c, p, S.Svc.str(J.Json.get(d, "kind")), S.Svc.str(J.Json.get(d, "name")), ns)))

def St.Pvc.ref_ns.if(isnull: Bool, ns: String, j: J.Json) -> String:
  match isnull:
    case True{}:
      ns
    case False{}:
      S.Svc.str(j)

def St.Pvc.sources(+c: S.Cfg, +p: PvcCfg, +vns: String, +o: J.Json) -> J.Json:
  +s = St.spec(o)
  +ds = J.Json.get(s, "dataSource")
  +dr = J.Json.get(s, "dataSourceRef")
  +rns = J.Json.get(dr, "namespace")
  a b = St.Pvc.source.if(J.Json.is_null(ds), c, p, vns, ds) St.Pvc.source.if(J.Json.is_null(dr), c, p, St.Pvc.ref_ns.if(J.Json.is_null(rns), vns, rns), dr)
  S.Svc.put_in(S.Svc.put_in(o, "spec", "dataSource", a), "spec", "dataSourceRef", b)

def St.Pvc.sources.if(go: Bool, +c: S.Cfg, +p: PvcCfg, +vns: String, +o: J.Json) -> J.Json:
  match go:
    case True{}:
      St.Pvc.sources(c, p, vns, o)
    case False{}:
      o

# The host (namespace, name) of a virtual claim (translate.Default.HostName).
def St.Pvc.host_ref(+c: S.Cfg, +v: J.Json) -> String & String:
  +name = S.Svc.name(v)
  S.Svc.plain_ref.if(String.is_empty(name), c, S.Svc.namespace(v), name)

# persistentvolumeclaims translate: HostMetadata without the three bind
# annotations, translateSelector, then the data sources unless the claim
# has vcluster.loft.sh/skip-translate: "true".
def St.Pvc.translate(+c: S.Cfg, +p: PvcCfg, host_class: Bool, +v: J.Json) -> J.Json:
  o1 = S.Svc.host_metadata.ref(c, St.pvc_kind(), St.pvc_excluded(), v, St.Pvc.host_ref(c, v))
  o2 = St.Pvc.translate_selector(c, p, host_class, o1)
  St.Pvc.sources.if(Bool.not(String.eq(S.Svc.annotation(St.skip_translate(), v), "true")), c, p, S.Svc.namespace(v), o2)

def St.zero_grace() -> Del:
  Del{J.JNum{"0"}, J.JNull{}}

def St.Pvc.to_host.if(limited: Bool, delete: Bool, +c: S.Cfg, +p: PvcCfg, host_class: Bool, +v: J.Json) -> Outcome:
  match limited:
    case True{}:
      St.done([])
    case False{}:
      match delete:
        case True{}:
          St.done([St.delete_virtual(v, St.zero_grace())])
        case False{}:
          St.done([HostCreate{St.Pvc.translate(c, p, host_class, v)}])

def St.Pvc.limited(l: PvcLook) -> Bool:
  match l:
    case PvcLook{limited, host_class, pv, pv_name, now}:
      limited

def St.Pvc.host_class(l: PvcLook) -> Bool:
  match l:
    case PvcLook{limited, host_class, pv, pv_name, now}:
      host_class

# persistentvolumeclaims SyncToHost: a claim the class selector limits is
# skipped; a claim whose host claim was seen, or that is deleting, goes with
# grace 0; else the host claim is created.
def St.Pvc.to_host(+c: S.Cfg, +p: PvcCfg, +l: PvcLook, host_old: Maybe<&2, J.Json>, +v: J.Json) -> Outcome:
  St.Pvc.to_host.if(St.Pvc.limited(l), Bool.or(Maybe.is_some(&2, J.Json, host_old), St.deleting(v)), c, p, St.Pvc.host_class(l), v)

def St.Pvc.back.if(same: Bool, +k: String, hv: String, +v: J.Json) -> J.Json:
  match same:
    case True{}:
      v
    case False{}:
      St.put_ann(v, k, J.JStr{hv})

# translateUpdateBackwards: each bind annotation that differs takes the
# host value.
def St.Pvc.back.one(+k: String, +h: J.Json, +v: J.Json) -> J.Json:
  +hv = S.Svc.annotation(k, h)
  St.Pvc.back.if(String.eq(S.Svc.annotation(k, v), hv), k, hv, v)

def St.Pvc.backwards(+h: J.Json, +v: J.Json) -> J.Json:
  St.Pvc.back.one(St.storage_provisioner(), h, St.Pvc.back.one(St.bound_by_controller(), h, St.Pvc.back.one(St.bind_completed(), h, v)))

# The rest of Sync: annotations back, the host status to virtual, the
# virtual storage requests to the host, annotations and labels both ways.
# v1 is the virtual claim after ensurePersistentVolume.
def St.Pvc.update(+c: S.Cfg, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json, +v1: J.Json) -> Outcome:
  v2 = S.Svc.put(St.Pvc.backwards(h, v1), "status", J.Json.get(h, "status"))
  h1 = S.Svc.put_in(h, "spec", "resources", S.Svc.put(J.Json.at(h, ["spec", "resources"]), "requests", J.Json.at(v1, ["spec", "resources", "requests"])))
  St.done(St.meta_sync(c, St.pvc_kind(), St.pvc_excluded(), ho, vo, h, v, h1, v2))

# The virtual volume locked (vcluster.loft.sh/lock = now) and unlocked
# around a recreate.
def St.Pvc.lock(pv: Maybe<&2, J.Json>, +now: String) -> List<&2, Write> & List<&2, Write>:
  match pv:
    case None{}:
      ([], [])
    case Some{+x}:
      ([VirtualUpdate{St.put_ann(x, St.lock(), J.JStr{now})}], [VirtualUpdate{St.put_ann(x, St.lock(), J.JNull{})}])

def St.Pvc.unfinalize.if(has: Bool, +v: J.Json) -> List<&2, Write>:
  match has:
    case True{}:
      [VirtualUpdate{St.unfinalized(v)}]
    case False{}:
      []

# The claim as recreatePersistentVolumeClaim creates it: no resource
# version, UID, deletion or generation, and the new volume name.
def St.Pvc.recreated(+v: J.Json, +name: String) -> J.Json:
  v1 = J.Json.set(v, "metadata", S.Svc.del_all(["resourceVersion", "uid", "deletionTimestamp", "generation", "finalizers"], J.Json.get(v, "metadata")))
  S.Svc.put_in(v1, "spec", "volumeName", J.JStr{name})

def St.Pvc.recreate.fin(locks: List<&2, Write> & List<&2, Write>, +v: J.Json, +name: String) -> Outcome:
  (lk, ul) = locks
  ws = List.append(&2, Write, St.Pvc.unfinalize.if(St.has_finalizers(v), v), [St.delete_virtual(v, St.nodel()), VirtualCreate{St.Pvc.recreated(v, name)}])
  Outcome{List.append(&2, Write, lk, List.append(&2, Write, ws, ul)), S.RequeueNow{}, ""}

# recreatePersistentVolumeClaim, then a requeue.
def St.Pvc.recreate(pv: Maybe<&2, J.Json>, +now: String, +v: J.Json, +name: String) -> Outcome:
  St.Pvc.recreate.fin(St.Pvc.lock(pv, now), v, name)

def St.Pvc.ensure.new(changed: Bool, had: Bool, +c: S.Cfg, pv: Maybe<&2, J.Json>, +now: String, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json, +name: String) -> Outcome:
  match changed:
    case False{}:
      St.Pvc.update(c, ho, h, vo, v, v)
    case True{}:
      match had:
        case True{}:
          St.Pvc.recreate(pv, now, v, name)
        case False{}:
          St.Pvc.update(c, ho, h, vo, v, S.Svc.put_in(v, "spec", "volumeName", J.JStr{name}))

def St.Pvc.ensure.named(unmapped: Bool, +c: S.Cfg, pv: Maybe<&2, J.Json>, +now: String, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json, +hvol: String, +name: String) -> Outcome:
  match unmapped:
    case True{}:
      Outcome{[], S.NoRequeue{}, "error retrieving virtual persistent volume " ++ hvol ++ ": not found"}
    case False{}:
      +vvol = S.Svc.spec_str(v, "volumeName")
      St.Pvc.ensure.new(Bool.not(String.eq(name, vvol)), Bool.not(String.is_empty(vvol)), c, pv, now, ho, h, vo, v, name)

def St.Pvc.ensure.fake.if(fake: Bool, +hvol: String, pv_name: String) -> String:
  match fake:
    case True{}:
      hvol
    case False{}:
      pv_name

def St.Pvc.ensure.go(differs: Bool, +c: S.Cfg, +p: PvcCfg, +l: PvcLook, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> Outcome:
  match differs:
    case False{}:
      St.Pvc.update(c, ho, h, vo, v, v)
    case True{}:
      match l:
        case PvcLook{limited, host_class, pv, pv_name, +now}:
          +hvol = S.Svc.spec_str(h, "volumeName")
          +name = St.Pvc.ensure.fake.if(St.Pvc.fake_on(p), hvol, pv_name)
          St.Pvc.ensure.named(String.is_empty(name), c, pv, now, ho, h, vo, v, hvol, name)

# ensurePersistentVolume, then the update: when the host claim names a
# volume other than the virtual claim's, the virtual claim takes the
# virtual name of that volume, or is recreated when it named another one.
def St.Pvc.ensure(+c: S.Cfg, +p: PvcCfg, +l: PvcLook, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> Outcome:
  +hvol = S.Svc.spec_str(h, "volumeName")
  differs = Bool.and(Bool.not(String.is_empty(hvol)), Bool.not(String.eq(S.Svc.spec_str(v, "volumeName"), hvol)))
  St.Pvc.ensure.go(differs, c, p, l, ho, h, vo, v)

def St.Pvc.grace(+o: J.Json) -> J.Json:
  J.Json.at(o, ["metadata", "deletionGracePeriodSeconds"])

def St.Pvc.uid(+o: J.Json) -> J.Json:
  J.JStr{S.Svc.str(J.Json.at(o, ["metadata", "uid"]))}

def St.Pvc.host_deleting.if(vdel: Bool, same: Bool, +h: J.Json, +v: J.Json) -> Outcome:
  match vdel:
    case False{}:
      St.done([St.delete_virtual(v, Del{J.JNum{"30"}, J.JNull{}})])
    case True{}:
      match same:
        case True{}:
          St.done([])
        case False{}:
          St.done([St.delete_virtual(v, Del{St.Pvc.grace(h), St.Pvc.uid(v)})])

def St.Pvc.sync.if(limited: Bool, hdel: Bool, vdel: Bool, +c: S.Cfg, +p: PvcCfg, +l: PvcLook, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> Outcome:
  match limited:
    case True{}:
      St.done([])
    case False{}:
      match hdel:
        case True{}:
          St.Pvc.host_deleting.if(vdel, S.Svc.eq(St.Pvc.grace(v), St.Pvc.grace(h)), h, v)
        case False{}:
          match vdel:
            case True{}:
              St.done([St.delete_host(h, Del{St.Pvc.grace(v), St.Pvc.uid(h)})])
            case False{}:
              St.Pvc.ensure(c, p, l, ho, h, vo, v)

# persistentvolumeclaims Sync. A deleting host claim deletes the virtual one
# (grace 30, or the host grace with a UID precondition when the graces
# differ); a deleting virtual claim deletes the host one with its grace and
# a UID precondition; else ensurePersistentVolume and the update.
def St.Pvc.sync(+c: S.Cfg, +p: PvcCfg, +l: PvcLook, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> Outcome:
  St.Pvc.sync.if(St.Pvc.limited(l), St.deleting(h), St.deleting(v), c, p, l, ho, h, vo, v)

def St.Pvc.to_virtual.if(delete: Bool, +c: S.Cfg, +h: J.Json) -> Outcome:
  match delete:
    case True{}:
      St.done([St.delete_host(h, St.nodel())])
    case False{}:
      St.done([VirtualCreate{S.Svc.virtual_metadata.ref(c, St.pvc_kind(), St.pvc_excluded(), h, (S.Svc.annotation(M.Meta.namespace_annotation(), h), S.Svc.annotation(M.Meta.name_annotation(), h)))}])

# persistentvolumeclaims SyncToVirtual: the host claim goes when its virtual
# claim was seen or vcluster made it; else it is copied in under the name
# its annotations give.
def St.Pvc.to_virtual(+c: S.Cfg, virtual_old: Maybe<&2, J.Json>, +h: J.Json) -> Outcome:
  St.Pvc.to_virtual.if(Bool.or(Maybe.is_some(&2, J.Json, virtual_old), M.Meta.should_delete_host_object(S.Svc.obj(St.pvc_kind(), h))), c, h)

# Persistent volumes, real (persistentvolumes/syncer.go, translate.go).

def St.pv_kind() -> String:
  "/v1, Kind=PersistentVolume"

# The members of PersistentVolumeSource, inlined in the volume spec.
def St.Pv.source_keys() -> +List<String>:
  ["gcePersistentDisk", "awsElasticBlockStore", "hostPath", "glusterfs", "nfs", "rbd", "iscsi", "cinder",
   "cephfs", "fc", "flocker", "flexVolume", "azureFile", "vsphereVolume", "quobyte", "azureDisk",
   "photonPersistentDisk", "portworxVolume", "scaleIO", "local", "storageos", "csi"]

def St.Pv.source(+spec: J.Json) -> J.Json:
  J.JObj{St.only(St.members(spec), St.Pv.source_keys())}

def St.Pv.with_source(+spec: J.Json, +src: J.Json) -> J.Json:
  J.JObj{St.chain_append(St.drop(St.members(spec), St.Pv.source_keys()), St.members(src))}

# translate.Default.IsManaged of a host volume (cluster-scoped: the
# cluster marker label).
def St.Pv.managed(+c: S.Cfg, +h: J.Json) -> Bool:
  M.Meta.is_managed(S.Svc.vc(c), S.Svc.target(c), None{}, S.Svc.obj(St.pv_kind(), h))

# persistentvolumes translate: HostMetadata under HostNameCluster without
# the host-pv annotation, no claim ref, the storage class through
# HostNameCluster.
def St.Pv.translate(+c: S.Cfg, +v: J.Json) -> J.Json:
  +n = St.cluster_name(c, S.Svc.name(v))
  o1 = S.Svc.host_metadata(c, St.pv_kind(), [St.host_pv()], v, "", n)
  o2 = S.Svc.put_in(o1, "spec", "claimRef", J.JNull{})
  o3 = S.Svc.put_in(o2, "spec", "storageClassName", S.Svc.sj(St.cluster_name(c, S.Svc.spec_str(v, "storageClassName"))))
  St.named(o3, n)

def St.Pv.unfinalize_or_delete(has: Bool, +v: J.Json) -> Outcome:
  match has:
    case True{}:
      St.done([VirtualUpdate{St.unfinalized(v)}])
    case False{}:
      St.done([St.delete_virtual(v, St.nodel())])

def St.Pv.to_host.if(limited: Bool, delete: Bool, +c: S.Cfg, +v: J.Json) -> Outcome:
  match limited:
    case True{}:
      St.done([])
    case False{}:
      match delete:
        case True{}:
          St.Pv.unfinalize_or_delete(St.has_finalizers(v), v)
        case False{}:
          St.done([HostCreate{St.Pv.translate(c, v)}])

# persistentvolumes SyncToHost: a volume the class selector limits is
# skipped; a volume whose host volume was seen, that is deleting, or that
# came from the host (host-pv) loses its finalizers first, then goes; else
# the host volume is created.
def St.Pv.to_host(+c: S.Cfg, limited: Bool, host_old: Maybe<&2, J.Json>, +v: J.Json) -> Outcome:
  delete = Bool.or(Maybe.is_some(&2, J.Json, host_old), Bool.or(St.deleting(v), Bool.not(String.is_empty(S.Svc.annotation(St.host_pv(), v)))))
  St.Pv.to_host.if(limited, delete, c, v)

def St.Pv.claim_ref(+ref: J.Json, +pvc: J.Json) -> J.Json:
  +md = J.Json.get(pvc, "metadata")
  r1 = S.Svc.put(St.obj_or_empty(ref), "resourceVersion", S.Svc.sj(S.Svc.str(J.Json.get(md, "resourceVersion"))))
  r2 = S.Svc.put(r1, "uid", S.Svc.sj(S.Svc.str(J.Json.get(md, "uid"))))
  r3 = S.Svc.put(r2, "name", S.Svc.sj(S.Svc.str(J.Json.get(md, "name"))))
  S.Svc.put(r3, "namespace", S.Svc.sj(S.Svc.str(J.Json.get(md, "namespace"))))

def St.Pv.class_of.if(isnull: Bool, +spec: J.Json, sc: J.Json) -> J.Json:
  match isnull:
    case True{}:
      spec
    case False{}:
      S.Svc.put(spec, "storageClassName", S.Svc.sj(S.Svc.str(sc)))

# The host spec with the claim ref and storage class of the virtual claim.
def St.Pv.with_claim(+spec: J.Json, pvc: Maybe<&2, J.Json>) -> J.Json:
  match pvc:
    case None{}:
      spec
    case Some{+x}:
      +sc = J.Json.at(x, ["spec", "storageClassName"])
      St.Pv.class_of.if(J.Json.is_null(sc), S.Svc.put(spec, "claimRef", St.Pv.claim_ref(J.Json.get(spec, "claimRef"), x)), sc)

def St.Pv.claim_host.if(pv: Bool, +c: S.Cfg, +ns: String, +name: String) -> String & String:
  match pv:
    case True{}:
      ("", name)
    case False{}:
      S.Svc.plain_ref.if(String.is_empty(name), c, ns, name)

def St.Pv.pair_is(p: String & String, +ns: String, +name: String) -> Bool:
  (a, b) = p
  Bool.and(String.eq(a, ns), String.eq(b, name))

# True when the virtual claim ref maps to the translated one: the claim was
# made in the virtual cluster.
def St.Pv.claim_made(+c: S.Cfg, +vref: J.Json, +tref: J.Json) -> Bool:
  +name = S.Svc.str(J.Json.get(vref, "name"))
  +ns = S.Svc.str(J.Json.get(vref, "namespace"))
  hit = St.Pv.pair_is(St.Pv.claim_host.if(String.eq(S.Svc.str(J.Json.get(vref, "kind")), "PersistentVolume"), c, ns, name), S.Svc.str(J.Json.get(tref, "namespace")), S.Svc.str(J.Json.get(tref, "name")))
  Bool.and(Bool.not(J.Json.is_null(vref)), Bool.and(Bool.not(J.Json.is_null(tref)), hit))

def St.Pv.made.if(none: Bool, x: Bool) -> Bool:
  match none:
    case True{}:
      x
    case False{}:
      False{}

def St.put_if(set: Bool, +o: J.Json, +k: String, +v: J.Json) -> J.Json:
  match set:
    case True{}:
      S.Svc.put(o, k, v)
    case False{}:
      o

# translateUpdateBackwards on the virtual spec vs, from the host spec hs.
def St.Pv.backwards(+c: S.Cfg, classes: Bool, managed: Bool, +pvc: Maybe<&2, J.Json>, +hs: J.Json, +vs: J.Json) -> J.Json:
  +none = Bool.not(Maybe.is_some(&2, J.Json, pvc))
  +ts = St.Pv.with_claim(hs, pvc)
  +vsc = S.Svc.str(J.Json.get(vs, "storageClassName"))
  +tsc = J.Json.get(ts, "storageClassName")
  sc_made = St.Pv.made.if(none, Bool.and(classes, Bool.not(String.eq(vsc, St.cluster_name(c, vsc)))))
  +vref = J.Json.get(vs, "claimRef")
  +tref = J.Json.get(ts, "claimRef")
  ref_made = St.Pv.made.if(none, St.Pv.claim_made(c, vref, tref))
  vs1 = St.put_if(Bool.and(Bool.not(managed), Bool.and(Bool.not(String.eq(vsc, S.Svc.str(tsc))), Bool.not(sc_made))), vs, "storageClassName", tsc)
  St.put_if(Bool.and(Bool.not(S.Svc.eq(vref, tref)), Bool.not(ref_made)), vs1, "claimRef", tref)

# The fields of patcher.CopyBidirectional in the volume Sync, besides the
# volume source, in two halves.
def St.Pv.fields_a() -> +List<String>:
  ["capacity", "accessModes", "persistentVolumeReclaimPolicy"]

def St.Pv.fields_b() -> +List<String>:
  ["nodeAffinity", "volumeMode", "mountOptions"]

def St.Pv.source_pick(+vos: J.Json, +vs: J.Json, +hos: J.Json, +hs: J.Json) -> S.Pick:
  +a = St.Pv.source(vs)
  +b = St.Pv.source(hs)
  S.Svc.pick.if(S.Svc.eq(St.Pv.source(vos), a), S.Svc.eq(St.Pv.source(hos), b), "", a, b)

def St.Pv.apply_source(p: S.Pick, picked: J.Json & J.Json) -> J.Json & J.Json:
  match p:
    case S.Pick{k, a, b}:
      (vs, hs) = picked
      (St.Pv.with_source(vs, a), St.Pv.with_source(hs, b))

def St.Pv.host_class.if(set: Bool, +c: S.Cfg, +h: J.Json, +v: J.Json) -> J.Json:
  match set:
    case True{}:
      S.Svc.put_in(h, "spec", "storageClassName", S.Svc.sj(St.cluster_name(c, S.Svc.spec_str(v, "storageClassName"))))
    case False{}:
      h

def St.Pv.update.fin(+c: S.Cfg, classes: Bool, pvc: Maybe<&2, J.Json>, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json, picked: J.Json & J.Json) -> Outcome:
  (+vs1, +hs1) = picked
  +h1 = J.Json.set(h, "spec", hs1)
  vs2 = St.Pv.backwards(c, classes, St.Pv.managed(c, h1), pvc, hs1, vs1)
  +v1 = S.Svc.put(J.Json.set(v, "spec", vs2), "status", J.Json.get(h1, "status"))
  h2 = St.Pv.host_class.if(String.is_empty(S.Svc.annotation(St.host_pv(), v1)), c, h1, v1)
  St.done(St.meta_sync(c, St.pv_kind(), [St.host_pv()], ho, vo, h, v, h2, v1))

# The update of the volume Sync: the spec fields both ways, the claim ref
# and storage class back, the host status to virtual, the host storage
# class from virtual unless the volume came from the host, annotations and
# labels both ways.
def St.Pv.update(+c: S.Cfg, classes: Bool, pvc: Maybe<&2, J.Json>, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> Outcome:
  +vos = St.spec(vo)
  +vs = St.spec(v)
  +hos = St.spec(ho)
  +hs = St.spec(h)
  pa pb = S.Svc.picks(St.Pv.fields_a(), vos, vs, hos, hs) S.Svc.picks(St.Pv.fields_b(), vos, vs, hos, hs)
  picked = S.Svc.apply_picks(List.append(&2, S.Pick, pa, pb), vs, hs)
  St.Pv.update.fin(c, classes, pvc, ho, h, vo, v, St.Pv.apply_source(St.Pv.source_pick(vos, vs, hos, hs), picked))

# shouldSync of a host volume: None when it does not sync, else Some of the
# virtual claim it belongs to (None when there is none).
def St.Pv.should.bool(b: Bool) -> Maybe<&2, Maybe<&2, J.Json>>:
  match b:
    case True{}:
      Some{None{}}
    case False{}:
      None{}

def St.Pv.should.unmapped(managed: Bool, targeted: Bool, retain: Bool) -> Maybe<&2, Maybe<&2, J.Json>>:
  St.Pv.should.bool(Bool.or(managed, Bool.and(targeted, retain)))

def St.Pv.should.claim.go(claim: Claim, managed: Bool, +targeted: Bool, retain: Bool, released: Bool) -> Maybe<&2, Maybe<&2, J.Json>>:
  match claim:
    case Unmapped{}:
      St.Pv.should.unmapped(managed, targeted, retain)
    case Missing{}:
      St.Pv.should.bool(Bool.or(managed, Bool.or(Bool.and(targeted, released), Bool.and(targeted, retain))))
    case Found{x}:
      Some{Some{x}}

def St.Pv.should.claim(+c: S.Cfg, claim: Claim, +h: J.Json) -> Maybe<&2, Maybe<&2, J.Json>>:
  managed = St.Pv.managed(c, h)
  targeted = String.eq(S.Svc.str(J.Json.at(h, ["spec", "claimRef", "namespace"])), S.Svc.target(c))
  retain = String.eq(S.Svc.spec_str(h, "persistentVolumeReclaimPolicy"), "Retain")
  released = String.eq(S.Svc.str(J.Json.at(h, ["status", "phase"])), "Released")
  St.Pv.should.claim.go(claim, managed, targeted, retain, released)

def St.Pv.should.if(noref: Bool, +c: S.Cfg, claim: Claim, +h: J.Json) -> Maybe<&2, Maybe<&2, J.Json>>:
  match noref:
    case True{}:
      St.Pv.should.bool(St.Pv.managed(c, h))
    case False{}:
      St.Pv.should.claim(c, claim, h)

def St.Pv.should(+c: S.Cfg, claim: Claim, +h: J.Json) -> Maybe<&2, Maybe<&2, J.Json>>:
  St.Pv.should.if(J.Json.is_null(J.Json.at(h, ["spec", "claimRef"])), c, claim, h)

def St.Pv.sync.should(s: Maybe<&2, Maybe<&2, J.Json>>, +c: S.Cfg, classes: Bool, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> Outcome:
  match s:
    case None{}:
      St.done([St.delete_virtual(v, St.nodel())])
    case Some{pvc}:
      St.Pv.update(c, classes, pvc, ho, h, vo, v)

def St.Pv.deleting.if(del: Bool, +h: J.Json) -> List<&2, Write>:
  match del:
    case True{}:
      [St.delete_host(h, St.nodel())]
    case False{}:
      []

def St.Pv.sync.go(limited: Bool, locked: Bool, vdel: Bool, +c: S.Cfg, classes: Bool, claim: Claim, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> Outcome:
  match limited:
    case True{}:
      St.done([])
    case False{}:
      match locked:
        case True{}:
          Outcome{[], S.RequeueAfter{1}, ""}
        case False{}:
          match vdel:
            case True{}:
              del = Bool.and(Bool.not(St.deleting(h)), Bool.or(J.Json.is_null(J.Json.at(v, ["spec", "claimRef"])), Bool.not(String.eq(S.Svc.spec_str(v, "persistentVolumeReclaimPolicy"), "Delete"))))
              Outcome{St.Pv.deleting.if(del, h), S.RequeueAfter{1}, ""}
            case False{}:
              St.Pv.sync.should(St.Pv.should(c, claim, h), c, classes, ho, h, vo, v)

# persistentvolumes Sync. classes: sync.toHost.storageClasses.enabled. A
# limited volume is skipped, a locked one waits a second; a deleting
# virtual volume deletes the host one unless it is a bound volume with
# reclaim policy Delete, and waits a second; a host volume that should not
# sync deletes the virtual one; else the update.
def St.Pv.sync(+c: S.Cfg, classes: Bool, l: PvLook, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> Outcome:
  match l:
    case PvLook{limited, locked, claim}:
      St.Pv.sync.go(limited, locked, St.deleting(v), c, classes, claim, ho, h, vo, v)

# persistentvolumes translateBackwards: the host volume with its metadata
# reset and without the host-pv annotation, the claim ref and storage class
# of the virtual claim, and host-pv set to the host name.
def St.Pv.backward(+h: J.Json, pvc: Maybe<&2, J.Json>) -> J.Json:
  o1 = St.copy_object(St.put_ann(h, St.host_pv(), J.JNull{}))
  o2 = J.Json.set(o1, "spec", St.Pv.with_claim(St.spec(h), pvc))
  St.put_ann(o2, St.host_pv(), J.JStr{S.Svc.name(h)})

def St.Pv.to_virtual.should(s: Maybe<&2, Maybe<&2, J.Json>>, +h: J.Json) -> Outcome:
  match s:
    case None{}:
      St.done([])
    case Some{pvc}:
      St.done([VirtualCreate{St.Pv.backward(h, pvc)}])

def St.Pv.to_virtual.if(managed: Bool, +c: S.Cfg, claim: Claim, +h: J.Json) -> Outcome:
  match managed:
    case True{}:
      St.done([St.delete_host(h, St.nodel())])
    case False{}:
      St.Pv.to_virtual.should(St.Pv.should(c, claim, h), h)

# persistentvolumes SyncToVirtual: a host volume vcluster made goes; one
# that should sync is copied in; else nothing.
def St.Pv.to_virtual(+c: S.Cfg, claim: Claim, +h: J.Json) -> Outcome:
  St.Pv.to_virtual.if(St.Pv.managed(c, h), c, claim, h)

# Persistent volumes, fake (persistentvolumes/fake_syncer.go).

def St.Fake.first.if(hit: Bool, +p: J.Json, rec: Maybe<&2, J.Json>) -> Maybe<&2, J.Json>:
  match hit:
    case True{}:
      Some{p}
    case False{}:
      rec

# The first virtual claim whose volume name is name (the IndexByAssigned
# list, in order).
def St.Fake.first(+name: String, pvcs: List<&2, J.Json>) -> Maybe<&2, J.Json>:
  match pvcs:
    case Nil{}:
      None{}
    case Con{+p, r}:
      St.Fake.first.if(String.eq(S.Svc.spec_str(p, "volumeName"), name), p, St.Fake.first(name, r))

# pvNeeded: some virtual claim names the volume.
def St.Fake.needed(+name: String, pvcs: List<&2, J.Json>) -> Bool:
  Maybe.is_some(&2, J.Json, St.Fake.first(name, pvcs))

def St.Fake.kv(k: String, v: String) -> J.KV:
  J.KV{k, J.JStr{v}}

# CreateFakePersistentVolume, with its status patch: a bound flex volume of
# driver "fake" for the claim.
def St.Fake.pv(+name: String, +pvc: J.Json) -> J.Json:
  +ps = J.Json.get(pvc, "spec")
  +md = J.Json.get(pvc, "metadata")
  meta = J.Json.obj([St.Fake.kv("name", name),
    J.KV{"labels", J.Json.obj([St.Fake.kv("vcluster.loft.sh/fake-pv", "true")])},
    J.KV{"annotations", J.Json.obj([St.Fake.kv("kubernetes.io/createdby", "fake-pv-provisioner"), St.Fake.kv("pv.kubernetes.io/bound-by-controller", "true"), St.Fake.kv("pv.kubernetes.io/provisioned-by", "fake-pv-provisioner")])}])
  ref = J.Json.obj([St.Fake.kv("kind", "PersistentVolumeClaim"), J.KV{"namespace", S.Svc.sj(S.Svc.str(J.Json.get(md, "namespace")))},
    J.KV{"name", S.Svc.sj(S.Svc.str(J.Json.get(md, "name")))}, J.KV{"uid", S.Svc.sj(S.Svc.str(J.Json.get(md, "uid")))},
    St.Fake.kv("apiVersion", "v1"), J.KV{"resourceVersion", S.Svc.sj(S.Svc.str(J.Json.get(md, "resourceVersion")))}])
  spec = J.Json.obj([J.KV{"flexVolume", J.Json.obj([St.Fake.kv("driver", "fake")])}, J.KV{"capacity", J.Json.at(ps, ["resources", "requests"])},
    J.KV{"accessModes", J.Json.get(ps, "accessModes")}, J.KV{"claimRef", ref}, St.Fake.kv("persistentVolumeReclaimPolicy", "Delete"),
    J.KV{"storageClassName", S.Svc.sj(S.Svc.str(J.Json.get(ps, "storageClassName")))}, J.KV{"volumeMode", J.Json.get(ps, "volumeMode")}])
  J.Json.obj([J.KV{"metadata", meta}, J.KV{"spec", spec}, J.KV{"status", J.Json.obj([St.Fake.kv("phase", "Bound")])}])

def St.Fake.to_virtual.m(+name: String, m: Maybe<&2, J.Json>) -> Outcome:
  match m:
    case None{}:
      St.done([])
    case Some{p}:
      St.done([VirtualCreate{St.Fake.pv(name, p)}])

# FakeSyncToVirtual for volume name: pvcs is the virtual claim list. A
# volume some claim names is created for the first such claim.
def St.Fake.to_virtual(+name: String, pvcs: List<&2, J.Json>) -> Outcome:
  St.Fake.to_virtual.m(name, St.Fake.first(name, pvcs))

# The fake volume deleted, then its finalizers removed.
def St.Fake.delete(+pv: J.Json) -> List<&2, Write>:
  St.delete_virtual(pv, St.nodel()) <> St.Pvc.unfinalize.if(St.has_finalizers(pv), pv)

def St.Fake.sync.if(needed: Bool, +pv: J.Json) -> Outcome:
  match needed:
    case True{}:
      St.done([])
    case False{}:
      St.done(St.Fake.delete(pv))

# FakeSync of a virtual volume: a volume no claim names goes.
def St.Fake.sync(+pv: J.Json, pvcs: List<&2, J.Json>) -> Outcome:
  St.Fake.sync.if(St.Fake.needed(S.Svc.name(pv), pvcs), pv)
