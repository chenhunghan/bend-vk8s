import Base
import ../lib/sha256.bend as H
import ../translate/names.bend as N
import bend-kube-runtime@0.2.0.0/src/json.bend as J

# The name-mapping store of vcluster's syncer (decision D2-B), as a pure value:
# pkg/mappings/store/store.go (the in-memory semantics, not the etcd
# backend), pkg/mappings/generic/recorder.go and mapper.go, and the configmap,
# secret and namespace mappers of pkg/mappings/resources (single-namespace
# mode).
#
# A store is the list of its mappings in insertion order. Each mapping is a
# name mapping (kind, virtual name, host name) and the name mappings it
# references (a pod references the configmaps and secrets it uses). vcluster
# keeps two lookup maps beside the mappings (hostToVirtualName and
# virtualToHostName); here they are derived: a lookup scans the mappings in
# order, the mapping's own name before its references, and answers the first
# hit. AddReference refuses any name that conflicts with an existing lookup,
# so every hit for one key answers the same name, as vcluster's first-inserted
# entry does.
#
# Where vcluster reads globals (translate.VClusterName, translate.Default,
# ctx.Config), the values are parameters: the target namespace and the
# vcluster name travel in a Ctx. A kind is Go gvk.String(), such as
# "/v1, Kind=Secret".

# types.NamespacedName.
type NN is Data:
  NN{ns: String, name: String}

# synccontext.Object: a kind and a name.
type Obj is Data:
  Obj{gvk: String, nn: NN}

# synccontext.NameMapping.
type NM is Data:
  NM{gvk: String, virt: NN, host: NN}

# store.Mapping: a name mapping and the name mappings it references.
type Mapping is Data:
  Mapping{nm: NM, refs: List<&2, NM>}

# The store. `verify` is the target namespace when the store checks host
# names (verify.NewVerifyMapping, as vcluster's syncer builds it), or None
# (store.NewStore, as vcluster's tests build it).
type Store is Data:
  Store{verify: Maybe<&2, String>, ms: List<&2, Mapping>}

# The result of AddReference: the new store, or vcluster's error text.
type Res is Data:
  Ok{store: Store}
  Err{msg: String}

# The side a lookup starts from.
type Dir is Data:
  V2H{}
  H2V{}

# A backend watch event (store.handleEvent). Del carries the name mapping of
# a Delete event, or the kind and virtual name of a DeleteReconstructed one.
type MEvent is Data:
  Upd{m: Mapping}
  Del{nm: NM}

# The sync context, as far as name translation reads it. `owner` is the name
# mapping of the object being synced (synccontext.MappingFrom). `reg` is the
# kinds of the registered mappers, or None when the context has no mappings
# registry (then the store is neither read nor written). `multi` is
# sync.toHost.namespaces.enabled, a Pro feature; `ns_mirror` says a mirror
# namespace mapper is registered (only vcluster's tests do that).
type Ctx is Data:
  Ctx{target: String, vc: String, owner: Maybe<&2, NM>, reg: Maybe<&2, List<&2, String>>, multi: Bool, ns_mirror: Bool}

# The mapper behind a recorder: the generic one (secrets, pods and most
# kinds) or the configmap one (kube-root-ca.crt special name).
type MKind is Data:
  KGeneric{}
  KConfigMap{}

# Pairs used by the string and base-36 loops.
type BQ is Data:
  BQ{q: List<&2, Bool>, r: Nat}

type SP is Data:
  SP{a: String, b: String}

type LP is Data:
  LP{a: List<&2, String>, b: String}

# Constants.

def Mappings.pods() -> String:
  "/v1, Kind=Pod"

def Mappings.secrets() -> String:
  "/v1, Kind=Secret"

def Mappings.configmaps() -> String:
  "/v1, Kind=ConfigMap"

def Mappings.namespaces() -> String:
  "/v1, Kind=Namespace"

def Mappings.name_annotation() -> String:
  "vcluster.loft.sh/object-name"

def Mappings.namespace_annotation() -> String:
  "vcluster.loft.sh/object-namespace"

def Mappings.kind_annotation() -> String:
  "vcluster.loft.sh/object-kind"

def Mappings.host_name_annotation() -> String:
  "vcluster.loft.sh/object-host-name"

def Mappings.host_namespace_annotation() -> String:
  "vcluster.loft.sh/object-host-namespace"

def Mappings.marker_label() -> String:
  "vcluster.loft.sh/managed-by"

def Mappings.force_sync_annotation() -> String:
  "vcluster.loft.sh/force-sync"

def Mappings.root_ca() -> String:
  "kube-root-ca.crt"

def NN.empty() -> NN:
  NN{"", ""}

# Names.

def NN.eq(a: NN, b: NN) -> Bool:
  match a b:
    case NN{an, am} NN{bn, bm}:
      Bool.and(String.eq(an, bn), String.eq(am, bm))

# Object.Empty: the name is empty.
def NN.is_empty(n: NN) -> Bool:
  match n:
    case NN{ns, name}:
      String.is_empty(name)

def NN.name(n: NN) -> String:
  match n:
    case NN{ns, name}:
      name

def NN.ns(n: NN) -> String:
  match n:
    case NN{ns, name}:
      ns

# NamespacedName.String.
def NN.show(n: NN) -> String:
  match n:
    case NN{ns, name}:
      ns ++ "/" ++ name

# Object.String.
def Obj.show(g: String, n: NN) -> String:
  g ++ ";" ++ NN.show(n)

# Struct equality of name mappings (a Go map key; also NameMapping.Equals,
# which compares both objects with their kinds).
def NM.same(a: NM, b: NM) -> Bool:
  match a b:
    case NM{ag, av, ah} NM{bg, bv, bh}:
      Bool.and(String.eq(ag, bg), Bool.and(NN.eq(av, bv), NN.eq(ah, bh)))

def NM.key(m: Mapping) -> NM:
  match m:
    case Mapping{x, rs}:
      x

# Lookups.

def Dir.key(d: Dir, v: NN, h: NN) -> NN:
  match d:
    case V2H{}:
      v
    case H2V{}:
      h

def Dir.val(d: Dir, v: NN, h: NN) -> NN:
  match d:
    case V2H{}:
      h
    case H2V{}:
      v

def Look.or(a: Maybe<&2, NN>, b: Maybe<&2, NN>) -> Maybe<&2, NN>:
  match a:
    case None{}:
      b
    case Some{x}:
      Some{x}

def Look.when(hit: Bool, x: NN) -> Maybe<&2, NN>:
  match hit:
    case True{}:
      Some{x}
    case False{}:
      None{}

# The other side of x when x's `d` side is the object (g, n).
def Look.nm(+d: Dir, x: NM, +g: String, +n: NN) -> Maybe<&2, NN>:
  match x:
    case NM{xg, +xv, +xh}:
      Look.when(Bool.and(String.eq(xg, g), NN.eq(Dir.key(d, xv, xh), n)), Dir.val(d, xv, xh))

def Look.refs(+d: Dir, rs: List<&2, NM>, +g: String, +n: NN) -> Maybe<&2, NN>:
  match rs:
    case Nil{}:
      None{}
    case Con{r, t}:
      Look.or(Look.nm(d, r, g, n), Look.refs(d, t, g, n))

def Look.mapping(+d: Dir, m: Mapping, +g: String, +n: NN) -> Maybe<&2, NN>:
  match m:
    case Mapping{x, rs}:
      Look.or(Look.nm(d, x, g, n), Look.refs(d, rs, g, n))

def Look.ms(+d: Dir, ms: List<&2, Mapping>, +g: String, +n: NN) -> Maybe<&2, NN>:
  match ms:
    case Nil{}:
      None{}
    case Con{m, t}:
      Look.or(Look.mapping(d, m, g, n), Look.ms(d, t, g, n))

# Store.VirtualToHostName.
def Store.virtual_to_host(s: Store, g: String, n: NN) -> Maybe<&2, NN>:
  match s:
    case Store{vf, ms}:
      Look.ms(V2H{}, ms, g, n)

# Store.HostToVirtualName.
def Store.host_to_virtual(s: Store, g: String, n: NN) -> Maybe<&2, NN>:
  match s:
    case Store{vf, ms}:
      Look.ms(H2V{}, ms, g, n)

def Store.mappings(s: Store) -> List<&2, Mapping>:
  match s:
    case Store{vf, ms}:
      ms

def Obj.gvk(o: Obj) -> String:
  match o:
    case Obj{g, n}:
      g

def Obj.nn(o: Obj) -> NN:
  match o:
    case Obj{g, n}:
      n

# The number of keys of a lookup map (len(hostToVirtualName) for H2V).
def Keys.elem(+o: Obj, xs: List<&2, Obj>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{Obj{g, n}, t}:
      Bool.or(Bool.and(String.eq(g, Obj.gvk(o)), NN.eq(n, Obj.nn(o))), Keys.elem(o, t))

def Keys.add.if(seen: Bool, o: Obj, acc: List<&2, Obj>) -> List<&2, Obj>:
  match seen:
    case True{}:
      acc
    case False{}:
      o <> acc

def Keys.add(+o: Obj, +acc: List<&2, Obj>) -> List<&2, Obj>:
  Keys.add.if(Keys.elem(o, acc), o, acc)

def Keys.of_nm(+d: Dir, x: NM, acc: List<&2, Obj>) -> List<&2, Obj>:
  match x:
    case NM{g, v, h}:
      Keys.add(Obj{g, Dir.key(d, v, h)}, acc)

def Keys.of_refs(+d: Dir, rs: List<&2, NM>, acc: List<&2, Obj>) -> List<&2, Obj>:
  match rs:
    case Nil{}:
      acc
    case Con{r, t}:
      Keys.of_refs(d, t, Keys.of_nm(d, r, acc))

def Keys.of_ms(+d: Dir, ms: List<&2, Mapping>, acc: List<&2, Obj>) -> List<&2, Obj>:
  match ms:
    case Nil{}:
      acc
    case Con{Mapping{x, rs}, t}:
      Keys.of_ms(d, t, Keys.of_refs(d, rs, Keys.of_nm(d, x, acc)))

def Store.keys(d: Dir, s: Store) -> Nat:
  List.length(&2, Obj, Keys.of_ms(d, Store.mappings(s), []))

def Store.size(s: Store) -> Nat:
  List.length(&2, Mapping, Store.mappings(s))

def Store.refs_of.if(hit: Bool, rs: List<&2, NM>, rest: List<&2, NM>) -> List<&2, NM>:
  match hit:
    case True{}:
      rs
    case False{}:
      rest

# The references a mapping holds (store.mappings[nm].References), or [] when
# the store has no mapping with that key.
def Store.refs_of.go(ms: List<&2, Mapping>, +k: NM) -> List<&2, NM>:
  match ms:
    case Nil{}:
      []
    case Con{Mapping{+x, rs}, t}:
      Store.refs_of.if(NM.same(x, k), rs, Store.refs_of.go(t, k))

def Store.refs_of(s: Store, k: NM) -> List<&2, NM>:
  Store.refs_of.go(Store.mappings(s), k)

# checkNameConflict: the host name must not map to another virtual name, and
# the virtual name must not map to another host name.

def Check.msg(a: String, b: String, c: String, d: String) -> String:
  "there is already another name mapping " ++ a ++ " -> " ++ b ++ " that conflicts with " ++ c ++ " -> " ++ d

def Check.side.if(ok: Bool, msg: String, rest: Maybe<&2, String>) -> Maybe<&2, String>:
  match ok:
    case True{}:
      rest
    case False{}:
      Some{msg}

def Check.side(found: Maybe<&2, NN>, +g: String, +key: NN, +want: NN, rest: Maybe<&2, String>) -> Maybe<&2, String>:
  match found:
    case None{}:
      rest
    case Some{+x}:
      Check.side.if(NN.eq(x, want), Check.msg(Obj.show(g, key), Obj.show(g, x), Obj.show(g, key), Obj.show(g, want)), rest)

def Check.conflict(+ms: List<&2, Mapping>, nm: NM) -> Maybe<&2, String>:
  match nm:
    case NM{+g, +v, +h}:
      Check.side(Look.ms(H2V{}, ms, g, h), g, h, v, Check.side(Look.ms(V2H{}, ms, g, v), g, v, h, None{}))

# verify.CheckHostObject: a host object must sit in the target namespace,
# and a host Namespace must be the target namespace.
def Verify.host(+target: String, +g: String, h: NN) -> Bool:
  match h:
    case NN{+ns, name}:
      Bool.and(Bool.or(String.is_empty(ns), String.eq(ns, target)), Bool.or(Bool.not(String.eq(g, Mappings.namespaces())), String.eq(name, target)))

def Verify.nm(vf: Maybe<&2, String>, nm: NM) -> Bool:
  match vf:
    case None{}:
      True{}
    case Some{t}:
      match nm:
        case NM{g, v, h}:
          Verify.host(t, g, h)

# findMapping: complete a half name mapping through the lookup maps, then
# find the mapping with that exact key.

def Find.if(hit: Bool, m: Mapping, rest: Maybe<&2, Mapping>) -> Maybe<&2, Mapping>:
  match hit:
    case True{}:
      Some{m}
    case False{}:
      rest

def Find.go(ms: List<&2, Mapping>, +k: NM) -> Maybe<&2, Mapping>:
  match ms:
    case Nil{}:
      None{}
    case Con{Mapping{+x, +rs}, t}:
      Find.if(NM.same(x, k), Mapping{x, rs}, Find.go(t, k))

def Resolve.by(found: Maybe<&2, NN>, g: String, d: Dir, n: NN) -> Maybe<&2, NM>:
  match found:
    case None{}:
      None{}
    case Some{x}:
      match d:
        case V2H{}:
          Some{NM{g, n, x}}
        case H2V{}:
          Some{NM{g, x, n}}

def Resolve.go(ve: Bool, he: Bool, +ms: List<&2, Mapping>, b: NM) -> Maybe<&2, NM>:
  match ve he:
    case True{} True{}:
      None{}
    case True{} False{}:
      match b:
        case NM{+g, v, +h}:
          Resolve.by(Look.ms(H2V{}, ms, g, h), g, H2V{}, h)
    case False{} True{}:
      match b:
        case NM{+g, +v, h}:
          Resolve.by(Look.ms(V2H{}, ms, g, v), g, V2H{}, v)
    case False{} False{}:
      Some{b}

def Resolve.key(+ms: List<&2, Mapping>, +b: NM) -> Maybe<&2, NM>:
  match b:
    case NM{g, +v, +h}:
      Resolve.go(NN.is_empty(v), NN.is_empty(h), ms, b)

def Store.find.k(ms: List<&2, Mapping>, k: Maybe<&2, NM>) -> Maybe<&2, Mapping>:
  match k:
    case None{}:
      None{}
    case Some{x}:
      Find.go(ms, x)

def Store.find(+ms: List<&2, Mapping>, b: NM) -> Maybe<&2, Mapping>:
  Store.find.k(ms, Resolve.key(ms, b))

# Whether the store holds a mapping with exactly this key (store.mappings[nm]).
def Store.has_mapping(s: Store, nm: NM) -> Bool:
  Maybe.is_some(&2, Mapping, Find.go(Store.mappings(s), nm))

# Mapping updates by key (keys are unique in a store).

def Upd.add.if(hit: Bool, x: NM, rs: List<&2, NM>, +r: NM) -> Mapping:
  match hit:
    case True{}:
      Mapping{x, List.append(&2, NM, rs, [r])}
    case False{}:
      Mapping{x, rs}

def Upd.add(ms: List<&2, Mapping>, +k: NM, +r: NM) -> List<&2, Mapping>:
  match ms:
    case Nil{}:
      []
    case Con{Mapping{+x, rs}, t}:
      Upd.add.if(NM.same(x, k), x, rs, r) <> Upd.add(t, k, r)

def Upd.drop_ref.if(same: Bool, r: NM, rest: List<&2, NM>) -> List<&2, NM>:
  match same:
    case True{}:
      rest
    case False{}:
      r <> rest

def Upd.drop_ref(rs: List<&2, NM>, +r: NM) -> List<&2, NM>:
  match rs:
    case Nil{}:
      []
    case Con{+x, t}:
      Upd.drop_ref.if(NM.same(x, r), x, Upd.drop_ref(t, r))

def Upd.del.if(hit: Bool, x: NM, rs: List<&2, NM>, +r: NM) -> Mapping:
  match hit:
    case True{}:
      Mapping{x, Upd.drop_ref(rs, r)}
    case False{}:
      Mapping{x, rs}

def Upd.del(ms: List<&2, Mapping>, +k: NM, +r: NM) -> List<&2, Mapping>:
  match ms:
    case Nil{}:
      []
    case Con{Mapping{+x, rs}, t}:
      Upd.del.if(NM.same(x, k), x, rs, r) <> Upd.del(t, k, r)

def Upd.remove.if(hit: Bool, m: Mapping, rest: List<&2, Mapping>) -> List<&2, Mapping>:
  match hit:
    case True{}:
      rest
    case False{}:
      m <> rest

def Upd.remove(ms: List<&2, Mapping>, +k: NM) -> List<&2, Mapping>:
  match ms:
    case Nil{}:
      []
    case Con{Mapping{+x, rs}, t}:
      Upd.remove.if(NM.same(x, k), Mapping{x, rs}, Upd.remove(t, k))

def Upd.has(rs: List<&2, NM>, +r: NM) -> Bool:
  match rs:
    case Nil{}:
      False{}
    case Con{x, t}:
      Bool.or(NM.same(x, r), Upd.has(t, r))

# AddReference.

def NM.complete(nm: NM) -> Bool:
  match nm:
    case NM{g, v, h}:
      Bool.and(Bool.not(NN.is_empty(v)), Bool.not(NN.is_empty(h)))

def Create.when(ok: Bool, x: NM) -> Maybe<&2, NM>:
  match ok:
    case True{}:
      Some{x}
    case False{}:
      None{}

# createMapping: a complete owner becomes a mapping with no references (the
# referenced name is NOT added to it); a half owner of the same kind is
# completed from the referenced name when their known sides agree.
def Create.half(ve: Bool, he: Bool, +nm: NM, b: NM) -> Maybe<&2, NM>:
  match ve he:
    case True{} True{}:
      None{}
    case True{} False{}:
      match nm b:
        case NM{+g, nv, nh} NM{+bg, bv, +bh}:
          Create.when(Bool.and(String.eq(g, bg), NN.eq(bh, nh)), NM{bg, nv, bh})
    case False{} True{}:
      match nm b:
        case NM{+g, nv, nh} NM{+bg, +bv, bh}:
          Create.when(Bool.and(String.eq(g, bg), NN.eq(bv, nv)), NM{bg, bv, nh})
    case False{} False{}:
      Some{b}

def Create.key(+nm: NM, +b: NM) -> Maybe<&2, NM>:
  match b:
    case NM{g, +v, +h}:
      Create.half(NN.is_empty(v), NN.is_empty(h), nm, b)

def Add.create(vf: Maybe<&2, String>, ms: List<&2, Mapping>, k: Maybe<&2, NM>) -> Res:
  match k:
    case None{}:
      Ok{Store{vf, ms}}
    case Some{x}:
      Ok{Store{vf, List.append(&2, Mapping, ms, [Mapping{x, []}])}}

def Add.found.if(skip: Bool, vf: Maybe<&2, String>, ms: List<&2, Mapping>, k: NM, nm: NM) -> Res:
  match skip:
    case True{}:
      Ok{Store{vf, ms}}
    case False{}:
      Ok{Store{vf, Upd.add(ms, k, nm)}}

def Add.found(found: Maybe<&2, Mapping>, vf: Maybe<&2, String>, +ms: List<&2, Mapping>, +nm: NM, b: NM) -> Res:
  match found:
    case None{}:
      Add.create(vf, ms, Create.key(nm, b))
    case Some{Mapping{+x, rs}}:
      Add.found.if(Bool.or(NM.same(x, nm), Upd.has(rs, nm)), vf, ms, x, nm)

def Add.verified(ok: Bool, vf: Maybe<&2, String>, +ms: List<&2, Mapping>, +nm: NM, +b: NM) -> Res:
  match ok:
    case True{}:
      Add.found(Store.find(ms, b), vf, ms, nm, b)
    case False{}:
      Ok{Store{vf, ms}}

def Add.checked(c: Maybe<&2, String>, +vf: Maybe<&2, String>, ms: List<&2, Mapping>, +nm: NM, b: NM) -> Res:
  match c:
    case Some{e}:
      Err{e}
    case None{}:
      Add.verified(Verify.nm(vf, nm), vf, ms, nm, b)

def Add.go(complete: Bool, vf: Maybe<&2, String>, +ms: List<&2, Mapping>, +nm: NM, b: NM) -> Res:
  match complete:
    case False{}:
      Ok{Store{vf, ms}}
    case True{}:
      Add.checked(Check.conflict(ms, nm), vf, ms, nm, b)

# Store.AddReference (and AddReferenceAndSave: saving changes no lookup).
def Store.add_reference(s: Store, +nm: NM, b: NM) -> Res:
  match s:
    case Store{vf, ms}:
      Add.go(NM.complete(nm), vf, ms, nm, b)

def Del.key(k: Maybe<&2, NM>, vf: Maybe<&2, String>, ms: List<&2, Mapping>, nm: NM) -> Store:
  match k:
    case None{}:
      Store{vf, ms}
    case Some{x}:
      Store{vf, Upd.del(ms, x, nm)}

# Store.DeleteReference (and DeleteReferenceAndSave).
def Del.go(complete: Bool, vf: Maybe<&2, String>, +ms: List<&2, Mapping>, nm: NM, b: NM) -> Store:
  match complete:
    case False{}:
      Store{vf, ms}
    case True{}:
      Del.key(Resolve.key(ms, b), vf, ms, nm)

def Store.delete_reference(s: Store, +nm: NM, b: NM) -> Store:
  match s:
    case Store{vf, ms}:
      Del.go(NM.complete(nm), vf, ms, nm, b)

# Store.DeleteMapping: the mapping goes, with its references.
def Store.delete_mapping.k(k: Maybe<&2, NM>, vf: Maybe<&2, String>, ms: List<&2, Mapping>) -> Store:
  match k:
    case None{}:
      Store{vf, ms}
    case Some{x}:
      Store{vf, Upd.remove(ms, x)}

def Store.delete_mapping(s: Store, nm: NM) -> Store:
  match s:
    case Store{vf, +ms}:
      Store.delete_mapping.k(Resolve.key(ms, nm), vf, ms)

# Store.ReferencesTo: the name mappings of the mappings that hold the virtual
# object (g, n), less the object's own mapping.

def Refs.to.if(hit: Bool, x: NM, rest: List<&2, NM>) -> List<&2, NM>:
  match hit:
    case True{}:
      x <> rest
    case False{}:
      rest

def Refs.to.go(ms: List<&2, Mapping>, +g: String, +n: NN, +own: NM) -> List<&2, NM>:
  match ms:
    case Nil{}:
      []
    case Con{Mapping{+x, +rs}, t}:
      Refs.to.if(Bool.and(Maybe.is_some(&2, NN, Look.mapping(V2H{}, Mapping{x, rs}, g, n)), Bool.not(NM.same(x, own))), x, Refs.to.go(t, g, n, own))

def Refs.to.found(found: Maybe<&2, NN>, ms: List<&2, Mapping>, +g: String, +n: NN) -> List<&2, NM>:
  match found:
    case None{}:
      []
    case Some{h}:
      Refs.to.go(ms, g, n, NM{g, n, h})

def Refs.to.named(empty: Bool, +ms: List<&2, Mapping>, +g: String, +n: NN) -> List<&2, NM>:
  match empty:
    case True{}:
      []
    case False{}:
      Refs.to.found(Look.ms(V2H{}, ms, g, n), ms, g, n)

def Store.references_to(s: Store, g: String, +n: NN) -> List<&2, NM>:
  Refs.to.named(NN.is_empty(n), Store.mappings(s), g, n)

# Garbage collection (garbageCollectMappings): a mapping goes when neither
# its virtual nor its host object exists, and its references go with it.
# `live_v` and `live_h` are the objects that exist in the virtual and the
# host cluster.

def Store.live(+live_v: List<&2, Obj>, +live_h: List<&2, Obj>, x: NM) -> Bool:
  match x:
    case NM{+g, v, h}:
      Bool.or(Keys.elem(Obj{g, v}, live_v), Keys.elem(Obj{g, h}, live_h))

def GC.keep(keep: Bool, m: Mapping, rest: List<&2, Mapping>) -> List<&2, Mapping>:
  match keep:
    case True{}:
      m <> rest
    case False{}:
      rest

def GC.go(ms: List<&2, Mapping>, +live_v: List<&2, Obj>, +live_h: List<&2, Obj>) -> List<&2, Mapping>:
  match ms:
    case Nil{}:
      []
    case Con{Mapping{+x, rs}, t}:
      GC.keep(Store.live(live_v, live_h, x), Mapping{x, rs}, GC.go(t, live_v, live_h))

def Store.collect(s: Store, live_v: List<&2, Obj>, live_h: List<&2, Obj>) -> Store:
  match s:
    case Store{vf, ms}:
      Store{vf, GC.go(ms, live_v, live_h)}

def Event.append(k: Maybe<&2, NM>, vf: Maybe<&2, String>, ms: List<&2, Mapping>, m: Mapping) -> Store:
  match k:
    case None{}:
      Store{vf, List.append(&2, Mapping, ms, [m])}
    case Some{x}:
      Store{vf, List.append(&2, Mapping, Upd.remove(ms, x), [m])}

# Backend events and the initial load (store.start, store.handleEvent): an
# update that fails verification is ignored; otherwise the old mapping goes
# and an update appends the new one.

def Event.upd(ok: Bool, vf: Maybe<&2, String>, +ms: List<&2, Mapping>, m: Mapping) -> Store:
  match ok:
    case False{}:
      Store{vf, ms}
    case True{}:
      match m:
        case Mapping{+x, rs}:
          Event.append(Resolve.key(ms, x), vf, ms, Mapping{x, rs})

def Store.apply(s: Store, ev: MEvent) -> Store:
  match s:
    case Store{+vf, +ms}:
      match ev:
        case Upd{m}:
          match m:
            case Mapping{+x, rs}:
              Event.upd(Verify.nm(vf, x), vf, ms, Mapping{x, rs})
        case Del{nm}:
          Store.delete_mapping(Store{vf, ms}, nm)

# store.start: the backend's mappings, applied as updates.
def Store.load(ms: List<&2, Mapping>, s: Store) -> Store:
  match ms:
    case Nil{}:
      s
    case Con{m, t}:
      Store.load(t, Store.apply(s, Upd{m}))

def Store.new(vf: Maybe<&2, String>) -> Store:
  Store{vf, []}

# Single-namespace name translation (translate/single_namespace.go).

def Tr.host_ns.if(empty: Bool, target: String) -> String:
  match empty:
    case True{}:
      ""
    case False{}:
      target

# HostNamespace: "" for a cluster-scoped name, else the target namespace.
def Tr.host_ns(target: String, +ns: String) -> String:
  Tr.host_ns.if(String.is_empty(ns), target)

def Tr.host_name.if(empty: Bool, target: String, vc: String, ns: String, name: String) -> NN:
  match empty:
    case True{}:
      NN.empty()
    case False{}:
      +s = ns
      NN{Tr.host_ns(target, s), N.Names.host_name(name, s, vc)}

# HostName.
def Tr.host_name(target: String, vc: String, n: NN) -> NN:
  match n:
    case NN{ns, +name}:
      Tr.host_name.if(String.is_empty(name), target, vc, ns, name)

# base36.EncodeBytes: the big-endian number as base-36 digits, after one "0"
# per leading zero byte.
#
# The number is long-divided by 36 one bit at a time, with the remainder as
# a Nat below 72. The BendTT kernel (--verdict) runs U32 as a bit vector, so
# a U32 multiply, divide or modulo per byte and pass costs more fuel than a
# law can spend; doubling and comparing a small Nat is cheap there.

def B36.digit(+d: U32) -> Char:
  Chr{(48 + d + 39 * Bool.to_u32(U32.is_gt(d, 9)) : U32)}

def B36.sel(c: Bool, x: U32, y: U32) -> U32:
  match c:
    case True{}:
      x
    case False{}:
      y

# The bits of a byte, most significant first, for the weights 128 .. 1.
def B36.byte_bits(ws: List<&2, U32>, +b: U32) -> List<&2, Bool>:
  match ws:
    case Nil{}:
      []
    case Con{+w, t}:
      +hi = U32.is_ge(b, w)
      hi <> B36.byte_bits(t, B36.sel(hi, (b - w : U32), b))

# The bits of a big-endian byte string, most significant first.
def B36.bits(bs: List<&2, U32>) -> List<&2, Bool>:
  match bs:
    case Nil{}:
      []
    case Con{b, t}:
      List.append(&2, Bool, B36.byte_bits([128, 64, 32, 16, 8, 4, 2, 1], b), B36.bits(t))

# The bits without their leading zeros.
def B36.strip(bs: List<&2, Bool>) -> List<&2, Bool>:
  match bs:
    case Nil{}:
      []
    case Con{b, t}:
      match b:
        case True{}:
          True{} <> t
        case False{}:
          B36.strip(t)

# 2r + bit.
def B36.step(r: Nat, bit: Bool) -> Nat:
  match bit:
    case True{}:
      1n+Nat.double(r)
    case False{}:
      Nat.double(r)

def B36.nsel(c: Bool, x: Nat, y: Nat) -> Nat:
  match c:
    case True{}:
      x
    case False{}:
      y

def B36.cons(q: Bool, p: BQ) -> BQ:
  match p:
    case BQ{qs, r}:
      BQ{q <> qs, r}

# The quotient bits and the remainder of (r, then bs) divided by 36.
def B36.divmod(bs: List<&2, Bool>, +r: Nat) -> BQ:
  match bs:
    case Nil{}:
      BQ{[], r}
    case Con{b, t}:
      +x = B36.step(r, b)
      +ge = Nat.is_ge(x, 36n)
      B36.cons(ge, B36.divmod(t, B36.nsel(ge, Nat.sub(x, 36n), x)))

def B36.fst(p: BQ) -> List<&2, Bool>:
  match p:
    case BQ{q, r}:
      q

def B36.snd(p: BQ) -> Nat:
  match p:
    case BQ{q, r}:
      r

# The digits of a stripped number, least significant first onto acc.
def B36.go(fuel: Nat, bs: List<&2, Bool>, acc: String) -> String:
  match fuel bs:
    case 0n _:
      acc
    case 1n+f Nil{}:
      acc
    case 1n+f Con{b, t}:
      +p = B36.divmod(b <> t, 0n)
      B36.go(f, B36.strip(B36.fst(p)), SCon{B36.digit(U32.from_nat(B36.snd(p))), acc})

def B36.zeros.if(zero: Bool, rec: String) -> String:
  match zero:
    case True{}:
      SCon{'0', rec}
    case False{}:
      ""

def B36.zeros(bs: List<&2, U32>) -> String:
  match bs:
    case Nil{}:
      ""
    case Con{+b, t}:
      B36.zeros.if(U32.is_eq(b, 0), B36.zeros(t))

def B36.encode(+bs: List<&2, U32>) -> String:
  B36.zeros(bs) ++ B36.go(64n, B36.strip(B36.bits(bs)), "")

def Tr.host_name_short.if(empty: Bool, target: String, vc: String, ns: String, name: String) -> NN:
  match empty:
    case True{}:
      NN.empty()
    case False{}:
      +s = ns
      NN{Tr.host_ns(target, s), SCon{'v', String.take(B36.encode(H.Sha256.digest(H.Sha256.utf8(String.join([name, "x", s, "x", vc], "-")))), 13n)}}

# HostNameShort: "v" and 13 base-36 digits of the SHA-256 of
# "<name>-x-<namespace>-x-<vcluster>".
def Tr.host_name_short(target: String, vc: String, n: NN) -> NN:
  match n:
    case NN{ns, +name}:
      Tr.host_name_short.if(String.is_empty(name), target, vc, ns, name)

# Strings.

# strings.ReplaceAll(s, old, new) for a non-empty old; an empty old leaves s
# as it is (vcluster only replaces with an empty new then).
# What a match of old (or the next character) becomes, and the rest.
def Str.replace.cut(hit: Bool, s: String, +old: String, +new: String) -> SP:
  match hit:
    case True{}:
      SP{new, String.drop(s, String.length(old))}
    case False{}:
      match s:
        case SNil{}:
          SP{"", ""}
        case SCon{c, t}:
          SP{SCon{c, SNil{}}, t}

def Str.fst(p: SP) -> String:
  match p:
    case SP{a, b}:
      a

def Str.snd(p: SP) -> String:
  match p:
    case SP{a, b}:
      b

def Str.replace.go(fuel: Nat, +s: String, +old: String, +new: String) -> String:
  match fuel:
    case 0n:
      s
    case 1n+f:
      +p = Str.replace.cut(Bool.and(Bool.not(String.is_empty(old)), String.starts_with(s, old)), s, old, new)
      Str.fst(p) ++ Str.replace.go(f, Str.snd(p), old, new)

def Str.replace(+s: String, old: String, new: String) -> String:
  Str.replace.go(1n+String.length(s), s, old, new)

def Str.elem(+k: String, xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{x, t}:
      Bool.or(String.eq(x, k), Str.elem(k, t))

# [a-z0-9]
def Str.alnum(c: Char) -> Bool:
  match c:
    case Chr{+x}:
      Bool.or(Bool.and(U32.is_ge(x, 97), U32.is_le(x, 122)), Bool.and(U32.is_ge(x, 48), U32.is_le(x, 57)))

def Str.all_alnum(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      Bool.and(Str.alnum(c), Str.all_alnum(t))

# Whether a match of v[a-z0-9]{13} starts here.
def Short.at(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{c, +t}:
      +w = String.take(t, 13n)
      Bool.and(Char.is_eq(c, 'v'), Bool.and(Nat.is_eq(String.length(w), 13n), Str.all_alnum(w)))

# The match that starts here (if any), and the string after it (or the tail).
def Short.cut(hit: Bool, s: String) -> LP:
  match hit:
    case True{}:
      +x = s
      LP{[String.take(x, 14n)], String.drop(x, 14n)}
    case False{}:
      match s:
        case SNil{}:
          LP{[], ""}
        case SCon{c, t}:
          LP{[], t}

def Short.fst(p: LP) -> List<&2, String>:
  match p:
    case LP{a, b}:
      a

def Short.snd(p: LP) -> String:
  match p:
    case LP{a, b}:
      b

def Short.go(fuel: Nat, +s: String) -> List<&2, String>:
  match fuel:
    case 0n:
      []
    case 1n+f:
      +p = Short.cut(Short.at(s), s)
      List.append(&2, String, Short.fst(p), Short.go(f, Short.snd(p)))

# shortNameMatcher.FindAllString(s, -1): the leftmost non-overlapping matches
# of v[a-z0-9]{13}.
def Short.all(+s: String) -> List<&2, String>:
  Short.go(1n+String.length(s), s)

# Object JSON.

def Js.str(j: J.Json) -> String:
  J.Json.str_or(j, "")

def Js.opt(j: J.Json) -> Maybe<&2, String>:
  match j:
    case J.JNull{}:
      None{}
    case J.JStr{s}:
      Some{s}
    case _:
      Some{""}

def Js.name(+o: J.Json) -> String:
  Js.str(J.Json.at(o, ["metadata", "name"]))

def Js.namespace(+o: J.Json) -> String:
  Js.str(J.Json.at(o, ["metadata", "namespace"]))

def Js.nn(+o: J.Json) -> NN:
  NN{Js.namespace(o), Js.name(o)}

# An annotation; None when absent.
def Js.annotation(+o: J.Json, k: String) -> Maybe<&2, String>:
  Js.opt(J.Json.get(J.Json.at(o, ["metadata", "annotations"]), k))

# A label; "" when absent.
def Js.label(+o: J.Json, k: String) -> String:
  Js.str(J.Json.get(J.Json.at(o, ["metadata", "labels"]), k))

def Js.ann(+o: J.Json, k: String) -> String:
  Maybe.default(&2, String, Js.annotation(o, k), "")

# Present and not null (a Go pointer that is not nil).
def Js.has(j: J.Json) -> Bool:
  Bool.not(J.Json.is_null(j))

# A present annotation must equal the expected value.
def Js.agrees(a: Maybe<&2, String>, want: String) -> Bool:
  match a:
    case None{}:
      True{}
    case Some{x}:
      String.eq(x, want)

# The mapper (generic/mapper.go).

def Mapper.when(ok: Bool, n: NN) -> NN:
  match ok:
    case True{}:
      n
    case False{}:
      NN.empty()

def Mapper.marker_ok(+marker: String, +ns: String, vc: String, cluster: String) -> Bool:
  Bool.or(String.is_empty(marker), Bool.and(Bool.or(String.is_empty(ns), String.eq(marker, vc)), Bool.or(Bool.not(String.is_empty(ns)), String.eq(marker, cluster))))

# TryToTranslateBackByAnnotations: the name and namespace annotations of a
# host object, when its marker label, kind and host name annotations agree.
def Mapper.by_annotations(+target: String, +vc: String, +g: String, p: Maybe<&2, J.Json>) -> NN:
  match p:
    case None{}:
      NN.empty()
    case Some{+o}:
      +name = Js.ann(o, Mappings.name_annotation())
      Mapper.when(Bool.and(Bool.not(String.is_empty(name)), Bool.and(Mapper.marker_ok(Js.label(o, Mappings.marker_label()), Js.namespace(o), vc, N.Names.marker_cluster(target, vc)), Bool.and(Js.agrees(Js.annotation(o, Mappings.kind_annotation()), g), Bool.and(Js.agrees(Js.annotation(o, Mappings.host_name_annotation()), Js.name(o)), Js.agrees(Js.annotation(o, Mappings.host_namespace_annotation()), Js.namespace(o)))))), NN{Js.ann(o, Mappings.namespace_annotation()), name})

def Mapper.or.if(empty: Bool, a: NN, b: NN) -> NN:
  match empty:
    case True{}:
      b
    case False{}:
      a

def Mapper.or(a: NN, b: NN) -> NN:
  match a:
    case NN{ns, +name}:
      Mapper.or.if(String.is_empty(name), NN{ns, name}, b)

# tryToMatchHostNameShort: an owner translated with HostNameShort whose short
# name occurs in the host name gives the owner's namespace and the host name
# with the short name replaced by the owner's name.
def Mapper.match_short(+target: String, +vc: String, owner: Maybe<&2, NM>, +req: NN) -> NN:
  match owner:
    case None{}:
      NN.empty()
    case Some{NM{g, +v, +h}}:
      Mapper.when(Bool.and(Bool.not(String.is_empty(NN.ns(v))), Bool.and(String.eq(NN.show(Tr.host_name_short(target, vc, v)), NN.show(h)), String.contains(NN.name(req), NN.name(h)))), NN{NN.ns(v), Str.replace(NN.name(req), NN.name(h), NN.name(v))})

def Mapper.found_ok(found: Maybe<&2, NN>) -> Bool:
  match found:
    case None{}:
      False{}
    case Some{NN{ns, name}}:
      Bool.and(Bool.not(String.is_empty(ns)), Bool.not(String.is_empty(name)))

def Mapper.found(found: Maybe<&2, NN>) -> NN:
  Maybe.default(&2, NN, found, NN.empty())

def Mapper.short_kinds.if(ok: Bool, +v: NN, +req: NN, +mt: String, rest: NN) -> NN:
  match ok:
    case True{}:
      NN{NN.ns(v), Str.replace(NN.name(req), mt, NN.name(v))}
    case False{}:
      rest

def Mapper.short_kinds(gs: List<&2, String>, +target: String, +vc: String, +ms: List<&2, Mapping>, +req: NN, +mt: String) -> NN:
  match gs:
    case Nil{}:
      NN.empty()
    case Con{g, t}:
      +found = Look.ms(H2V{}, ms, g, NN{NN.ns(req), mt})
      +v = Mapper.found(found)
      Mapper.short_kinds.if(Bool.and(Mapper.found_ok(found), String.eq(mt, NN.name(Tr.host_name_short(target, vc, v)))), v, req, mt, Mapper.short_kinds(t, target, vc, ms, req, mt))

def Mapper.short_matches(xs: List<&2, String>, +gs: List<&2, String>, +target: String, +vc: String, +ms: List<&2, Mapping>, +req: NN) -> NN:
  match xs:
    case Nil{}:
      NN.empty()
    case Con{x, t}:
      Mapper.or(Mapper.short_kinds(gs, target, vc, ms, req, x), Mapper.short_matches(t, gs, target, vc, ms, req))

# tryToFindHostNameShortInStore.
def Mapper.short_in_store(+gs: List<&2, String>, +target: String, +vc: String, +ms: List<&2, Mapping>, +req: NN) -> NN:
  Mapper.short_matches(Short.all(NN.name(req)), gs, target, vc, ms, req)

def Mapper.name_kinds.if(ok: Bool, v: NN, rest: NN) -> NN:
  match ok:
    case True{}:
      v
    case False{}:
      rest

# tryToFindHostNameInStore.
def Mapper.name_in_store(gs: List<&2, String>, +target: String, +vc: String, +ms: List<&2, Mapping>, +req: NN) -> NN:
  match gs:
    case Nil{}:
      NN.empty()
    case Con{g, t}:
      +found = Look.ms(H2V{}, ms, g, req)
      +v = Mapper.found(found)
      Mapper.name_kinds.if(Bool.and(Mapper.found_ok(found), String.eq(NN.show(req), NN.show(Tr.host_name(target, vc, v)))), v, Mapper.name_in_store(t, target, vc, ms, req))

def Mapper.by_name.multi(+g: String, mirror: Bool, req: NN) -> NN:
  match mirror:
    case False{}:
      NN.empty()
    case True{}:
      match req:
        case NN{+ns, name}:
          Mapper.when(Bool.and(Bool.not(String.eq(g, Mappings.namespaces())), Bool.not(String.is_empty(ns))), NN{ns, name})

def Mapper.by_name.single(+target: String, +vc: String, owner: Maybe<&2, NM>, +gs: List<&2, String>, +ms: List<&2, Mapping>, +req: NN) -> NN:
  Mapper.or(Mapper.match_short(target, vc, owner, req), Mapper.or(Mapper.short_in_store(gs, target, vc, ms, req), Mapper.name_in_store(gs, target, vc, ms, req)))

def Mapper.by_name.reg(reg: Maybe<&2, List<&2, String>>, multi: Bool, mirror: Bool, target: String, vc: String, owner: Maybe<&2, NM>, ms: List<&2, Mapping>, req: NN, g: String) -> NN:
  match reg:
    case None{}:
      NN.empty()
    case Some{gs}:
      match multi:
        case True{}:
          Mapper.by_name.multi(g, mirror, req)
        case False{}:
          Mapper.by_name.single(target, vc, owner, gs, ms, req)

# TryToTranslateBackByName.
def Mapper.by_name(c: Ctx, s: Store, req: NN, g: String) -> NN:
  match c:
    case Ctx{target, vc, owner, reg, multi, mirror}:
      Mapper.by_name.reg(reg, multi, mirror, target, vc, owner, Store.mappings(s), req, g)

def Ctx.target(c: Ctx) -> String:
  match c:
    case Ctx{target, vc, owner, reg, multi, mirror}:
      target

def Ctx.vc(c: Ctx) -> String:
  match c:
    case Ctx{target, vc, owner, reg, multi, mirror}:
      vc

def Ctx.owner(c: Ctx) -> Maybe<&2, NM>:
  match c:
    case Ctx{target, vc, owner, reg, multi, mirror}:
      owner

def Ctx.reg(c: Ctx) -> Maybe<&2, List<&2, String>>:
  match c:
    case Ctx{target, vc, owner, reg, multi, mirror}:
      reg

# The context with no mappings registry (Migrate sets ctx.Mappings = nil).
def Ctx.no_reg(c: Ctx) -> Ctx:
  match c:
    case Ctx{target, vc, owner, reg, multi, mirror}:
      Ctx{target, vc, owner, None{}, multi, mirror}

def Mapper.back(+c: Ctx, s: Store, +g: String, +req: NN, p: Maybe<&2, J.Json>) -> NN:
  Mapper.or(Mapper.by_annotations(Ctx.target(c), Ctx.vc(c), g, p), Mapper.by_name(c, s, req, g))

# mapper.HostToVirtual: host objects outside the target namespace have no
# virtual name; else annotations, then name heuristics.
def Mapper.host_to_virtual(+c: Ctx, s: Store, +g: String, +req: NN, p: Maybe<&2, J.Json>) -> NN:
  Mapper.when(Verify.host(Ctx.target(c), g, req), Mapper.back(c, s, g, req, p))

# mapper.VirtualToHost of the generic mapper: HostName.
def Mapper.virtual_to_host(c: Ctx, n: NN) -> NN:
  +cc = c
  Tr.host_name(Ctx.target(cc), Ctx.vc(cc), n)

def Mapper.expected_name.if(has: Bool, +g: String, ms: List<&2, Mapping>, +target: String, +vc: String, +v: NN) -> Maybe<&2, String>:
  match has:
    case False{}:
      None{}
    case True{}:
      Some{NN.name(Maybe.default(&2, NN, Look.ms(V2H{}, ms, g, v), Tr.host_name(target, vc, v)))}

def Mapper.expected_name.go(gs: List<&2, String>, +g: String, ms: List<&2, Mapping>, +target: String, +vc: String, +v: NN) -> Maybe<&2, String>:
  Mapper.expected_name.if(Str.elem(g, gs), g, ms, target, vc, v)

def Mapper.name_ok.cmp(e: Maybe<&2, String>, name: String) -> Bool:
  match e:
    case None{}:
      True{}
    case Some{x}:
      String.eq(name, x)

def Mapper.name_ok(reg: Maybe<&2, List<&2, String>>, +g: String, ms: List<&2, Mapping>, +target: String, +vc: String, v: NN, name: String) -> Bool:
  match reg:
    case None{}:
      True{}
    case Some{gs}:
      Mapper.name_ok.cmp(Mapper.expected_name.go(gs, g, ms, target, vc, v), name)

# singleNamespace.IsManaged. With a registry that maps the kind, the host
# name must be the virtual-to-host name of the name annotations (the store's
# answer, else HostName).
def Mapper.managed_ns(+target: String, +vc: String, +g: String, reg: Maybe<&2, List<&2, String>>, +ms: List<&2, Mapping>, +o: J.Json) -> Bool:
  +name = Js.ann(o, Mappings.name_annotation())
  +kind = Js.ann(o, Mappings.kind_annotation())
  +hn = Js.ann(o, Mappings.host_name_annotation())
  +hns = Js.ann(o, Mappings.host_namespace_annotation())
  Bool.and(String.eq(Js.namespace(o), target), Bool.and(String.eq(Js.label(o, Mappings.marker_label()), vc), Bool.and(Bool.not(String.is_empty(name)), Bool.and(Mapper.name_ok(reg, g, ms, target, vc, NN{Js.ann(o, Mappings.namespace_annotation()), name}, Js.name(o)), Bool.and(Bool.or(String.is_empty(kind), String.eq(g, kind)), Bool.and(Bool.or(String.is_empty(hn), String.eq(hn, Js.name(o))), Bool.or(String.is_empty(hns), String.eq(hns, Js.namespace(o)))))))))

def Mapper.is_managed.if(cluster: Bool, +target: String, +vc: String, +g: String, reg: Maybe<&2, List<&2, String>>, +ms: List<&2, Mapping>, +o: J.Json) -> Bool:
  match cluster:
    case True{}:
      String.eq(Js.label(o, Mappings.marker_label()), N.Names.marker_cluster(target, vc))
    case False{}:
      Mapper.managed_ns(target, vc, g, reg, ms, o)

# mapper.IsManaged.
def Mapper.is_managed(+c: Ctx, s: Store, +g: String, +o: J.Json) -> Bool:
  +target = Ctx.target(c)
  Bool.and(Verify.host(target, g, Js.nn(o)), Mapper.is_managed.if(String.is_empty(Js.namespace(o)), target, Ctx.vc(c), g, Ctx.reg(c), Store.mappings(s), o))

# The recorder (generic/recorder.go).

def Rec.found(reg: Maybe<&2, List<&2, String>>, found: Maybe<&2, NN>, inner: NN) -> NN:
  match reg:
    case None{}:
      inner
    case Some{gs}:
      Maybe.default(&2, NN, found, inner)

def Rec.added(r: Res, s: Store, ret: NN) -> NN & Store:
  match r:
    case Ok{s2}:
      (ret, s2)
    case Err{e}:
      (NN.empty(), s)

def Rec.owned(owner: Maybe<&2, NM>, +s: Store, +g: String, p: NN, v: NN, ret: NN) -> NN & Store:
  match owner:
    case None{}:
      (ret, s)
    case Some{b}:
      Rec.added(Store.add_reference(s, NM{g, v, p}, b), s, ret)

def Rec.reg(reg: Maybe<&2, List<&2, String>>, owner: Maybe<&2, NM>, s: Store, g: String, p: NN, v: NN, ret: NN) -> NN & Store:
  match reg:
    case None{}:
      (ret, s)
    case Some{gs}:
      Rec.owned(owner, s, g, p, v, ret)

def Rec.record.if(skip: Bool, c: Ctx, s: Store, g: String, p: NN, v: NN, ret: NN) -> NN & Store:
  match skip:
    case True{}:
      (ret, s)
    case False{}:
      match c:
        case Ctx{target, vc, owner, reg, multi, mirror}:
          Rec.reg(reg, owner, s, g, p, v, ret)

# RecordMapping: with an owner in the context, add p <-> v as its reference;
# an error empties the answer.
def Rec.record(c: Ctx, s: Store, g: String, +p: NN, +v: NN, ret: NN) -> NN & Store:
  Rec.record.if(Bool.or(NN.is_empty(p), NN.is_empty(v)), c, s, g, p, v, ret)

# recorder.VirtualToHost: the store first, else the inner mapper's name
# (`inner`), then record.
def Rec.virtual_to_host(+c: Ctx, +s: Store, +g: String, +req: NN, inner: NN) -> NN & Store:
  +p = Rec.found(Ctx.reg(c), Store.virtual_to_host(s, g, req), inner)
  Rec.record(c, s, g, p, req, p)

# recorder.HostToVirtual.
def Rec.host_to_virtual(+c: Ctx, +s: Store, +g: String, +req: NN, inner: NN) -> NN & Store:
  +v = Rec.found(Ctx.reg(c), Store.host_to_virtual(s, g, req), inner)
  Rec.record(c, s, g, req, v, v)

def Rec.is_managed.reg(reg: Maybe<&2, List<&2, String>>, s: Store, +g: String, req: NN, inner: Bool) -> Bool:
  match reg:
    case None{}:
      inner
    case Some{gs}:
      Bool.or(Maybe.is_some(&2, NN, Store.host_to_virtual(s, g, req)), inner)

# recorder.IsManaged: a host name the store knows is managed; else the inner
# mapper decides (`inner`).
def Rec.is_managed(c: Ctx, s: Store, +g: String, req: NN, inner: Bool) -> Bool:
  Rec.is_managed.reg(Ctx.reg(c), s, g, req, inner)

# The configmap mapper (resources/configmaps.go).

# SafeConcatName("vcluster", "kube-root-ca.crt", "x", VClusterName).
def ConfigMaps.root_ca_host(vc: String) -> String:
  N.Names.safe_concat(["vcluster", Mappings.root_ca(), "x", vc])

def ConfigMaps.v2h.if(root: Bool, vc: String, p: NN) -> NN:
  match root:
    case True{}:
      NN{NN.ns(p), ConfigMaps.root_ca_host(vc)}
    case False{}:
      p

# configMapsMapper.VirtualToHost: HostName, with kube-root-ca.crt renamed.
def ConfigMaps.virtual_to_host(+c: Ctx, n: NN) -> NN:
  +p = Mapper.virtual_to_host(c, n)
  ConfigMaps.v2h.if(String.eq(NN.name(p), Mappings.root_ca()), Ctx.vc(c), p)

def ConfigMaps.h2v.if(host_root: Bool, special: Bool, inner: NN) -> NN:
  match host_root special:
    case True{} _:
      NN.empty()
    case False{} True{}:
      NN{NN.ns(inner), Mappings.root_ca()}
    case False{} False{}:
      inner

# configMapsMapper.HostToVirtual: the host kube-root-ca.crt has no virtual
# name, and the special name translates back to kube-root-ca.crt.
def ConfigMaps.host_to_virtual(+c: Ctx, s: Store, +req: NN, p: Maybe<&2, J.Json>) -> NN:
  +name = NN.name(req)
  ConfigMaps.h2v.if(String.eq(name, Mappings.root_ca()), String.eq(name, ConfigMaps.root_ca_host(Ctx.vc(c))), Mapper.host_to_virtual(c, s, Mappings.configmaps(), req, p))

def MKind.virtual_to_host(k: MKind, c: Ctx, n: NN) -> NN:
  match k:
    case KGeneric{}:
      Mapper.virtual_to_host(c, n)
    case KConfigMap{}:
      ConfigMaps.virtual_to_host(c, n)

def MKind.host_to_virtual(k: MKind, +c: Ctx, s: Store, +g: String, +req: NN, p: Maybe<&2, J.Json>) -> NN:
  match k:
    case KGeneric{}:
      Mapper.host_to_virtual(c, s, g, req, p)
    case KConfigMap{}:
      ConfigMaps.host_to_virtual(c, s, req, p)

# A recorder over a kind's mapper.
def MKind.rec_virtual_to_host(+k: MKind, +c: Ctx, +s: Store, +g: String, +req: NN) -> NN & Store:
  Rec.virtual_to_host(c, s, g, req, MKind.virtual_to_host(k, c, req))

def MKind.rec_host_to_virtual(+k: MKind, +c: Ctx, +s: Store, +g: String, +req: NN, p: Maybe<&2, J.Json>) -> NN & Store:
  Rec.host_to_virtual(c, s, g, req, MKind.host_to_virtual(k, c, s, g, req, p))

def Migrate.res(r: Res, s: Store) -> Store:
  match r:
    case Ok{s2}:
      s2
    case Err{e}:
      s

# recorder.Migrate. Host objects first: each managed host object the store
# does not know is recorded with its virtual name (the context has no
# registry: annotations only). Then each virtual object the store does not
# know is recorded with the inner mapper's host name. Errors are skipped.

def Migrate.record.if(ok: Bool, s: Store, x: NM) -> Store:
  match ok:
    case False{}:
      s
    case True{}:
      +sx = s
      +xx = x
      Migrate.res(Store.add_reference(sx, xx, xx), sx)

def Migrate.host_one(+k: MKind, +c: Ctx, +s: Store, +g: String, +o: J.Json) -> Store:
  +cn = Ctx.no_reg(c)
  +p = Js.nn(o)
  +v = MKind.host_to_virtual(k, cn, s, g, p, Some{o})
  Migrate.record.if(Bool.and(Mapper.is_managed(cn, s, g, o), Bool.and(Bool.not(Maybe.is_some(&2, NN, Store.host_to_virtual(s, g, p))), Bool.not(NN.is_empty(v)))), s, NM{g, v, p})

def Migrate.hosts(os: List<&2, J.Json>, +k: MKind, +c: Ctx, s: Store, +g: String) -> Store:
  match os:
    case Nil{}:
      s
    case Con{o, t}:
      Migrate.hosts(t, k, c, Migrate.host_one(k, c, s, g, o), g)

def Migrate.virtual_one(+k: MKind, +c: Ctx, +s: Store, +g: String, +v: NN) -> Store:
  +p = MKind.virtual_to_host(k, c, v)
  Migrate.record.if(Bool.and(Bool.not(Maybe.is_some(&2, NN, Store.virtual_to_host(s, g, v))), Bool.not(NN.is_empty(p))), s, NM{g, v, p})

def Migrate.virtuals(vs: List<&2, NN>, +k: MKind, +c: Ctx, s: Store, +g: String) -> Store:
  match vs:
    case Nil{}:
      s
    case Con{v, t}:
      Migrate.virtuals(t, k, c, Migrate.virtual_one(k, c, s, g, v), g)

def Rec.migrate(+k: MKind, +c: Ctx, s: Store, +g: String, hosts: List<&2, J.Json>, virtuals: List<&2, NN>) -> Store:
  Migrate.virtuals(virtuals, k, c, Migrate.hosts(hosts, k, c, s, g), g)

# References from pods and ingresses (configmaps.go, secrets.go).

def Js.items(+o: J.Json, path: List<&2, String>) -> List<&2, J.Json>:
  J.Json.items(J.Json.at(o, path))

def Pod.name_if(ok: Bool, +ns: String, name: String, rest: List<&2, NN>) -> List<&2, NN>:
  match ok:
    case True{}:
      NN{ns, name} <> rest
    case False{}:
      rest

# A non-empty name at `path` under j.
def Pod.ref(+j: J.Json, path: List<&2, String>, +ns: String, rest: List<&2, NN>) -> List<&2, NN>:
  +name = Js.str(J.Json.at(j, path))
  Pod.name_if(Bool.not(String.is_empty(name)), ns, name, rest)

# The name at `path` under j when the object at `obj` is present (Go: a
# non-nil pointer, whatever its name).
def Pod.present(+j: J.Json, obj: List<&2, String>, field: String, +ns: String, rest: List<&2, NN>) -> List<&2, NN>:
  +x = J.Json.at(j, obj)
  Pod.name_if(Js.has(x), ns, Js.str(J.Json.get(x, field)), rest)

def Pod.env(es: List<&2, J.Json>, +ref: String, +ns: String) -> List<&2, NN>:
  match es:
    case Nil{}:
      []
    case Con{+e, t}:
      Pod.ref(e, ["valueFrom", ref, "name"], ns, Pod.env(t, ref, ns))

def Pod.env_from(es: List<&2, J.Json>, +ref: String, +ns: String) -> List<&2, NN>:
  match es:
    case Nil{}:
      []
    case Con{+e, t}:
      Pod.ref(e, [ref, "name"], ns, Pod.env_from(t, ref, ns))

# configNamesFromContainer / secretNamesFromContainer: env key refs, then
# envFrom refs. `key` is configMapKeyRef or secretKeyRef, `from` configMapRef
# or secretRef.
def Pod.container(+c: J.Json, +key: String, +from: String, +ns: String) -> List<&2, NN>:
  List.append(&2, NN, Pod.env(Js.items(c, ["env"]), key, ns), Pod.env_from(Js.items(c, ["envFrom"]), from, ns))

def Pod.containers(cs: List<&2, J.Json>, +key: String, +from: String, +ns: String) -> List<&2, NN>:
  match cs:
    case Nil{}:
      []
    case Con{c, t}:
      List.append(&2, NN, Pod.container(c, key, from, ns), Pod.containers(t, key, from, ns))

# Containers, then init containers, then ephemeral containers.
def Pod.all_containers(+pod: J.Json, +key: String, +from: String, +ns: String) -> List<&2, NN>:
  List.append(&2, NN, Pod.containers(Js.items(pod, ["spec", "containers"]), key, from, ns), List.append(&2, NN, Pod.containers(Js.items(pod, ["spec", "initContainers"]), key, from, ns), Pod.containers(Js.items(pod, ["spec", "ephemeralContainers"]), key, from, ns)))

def Pod.cm_sources(ss: List<&2, J.Json>, +ns: String) -> List<&2, NN>:
  match ss:
    case Nil{}:
      []
    case Con{+s, t}:
      Pod.present(s, ["configMap"], "name", ns, Pod.cm_sources(t, ns))

def Pod.cm_volumes(vs: List<&2, J.Json>, +ns: String) -> List<&2, NN>:
  match vs:
    case Nil{}:
      []
    case Con{+v, t}:
      Pod.present(v, ["configMap"], "name", ns, List.append(&2, NN, Pod.cm_sources(Js.items(v, ["projected", "sources"]), ns), Pod.cm_volumes(t, ns)))

# configMapsFromPod: container refs, then volume and projected sources. The
# containers and the volumes are independent, so they are scanned in
# parallel.
def ConfigMaps.from_pod(+pod: J.Json) -> List<&2, NN>:
  +ns = Js.namespace(pod)
  a b = Pod.all_containers(pod, "configMapKeyRef", "configMapRef", ns) Pod.cm_volumes(Js.items(pod, ["spec", "volumes"]), ns)
  List.append(&2, NN, a, b)

def Pod.sa_if(ok: Bool, sa: Maybe<&2, NN>, rest: List<&2, NN>) -> List<&2, NN>:
  match ok:
    case False{}:
      rest
    case True{}:
      match sa:
        case None{}:
          rest
        case Some{n}:
          n <> rest

def Pod.secret_sources(ss: List<&2, J.Json>, +sa: Maybe<&2, NN>, +ns: String) -> List<&2, NN>:
  match ss:
    case Nil{}:
      []
    case Con{+s, t}:
      Pod.present(s, ["secret"], "name", ns, Pod.sa_if(Js.has(J.Json.get(s, "serviceAccountToken")), sa, Pod.secret_sources(t, sa, ns)))

# The secret refs of one volume, in secretNamesFromVolumes order.
def Pod.secret_volume(+v: J.Json, +sa: Maybe<&2, NN>, +ns: String, rest: List<&2, NN>) -> List<&2, NN>:
  Pod.present(v, ["secret"], "secretName", ns,
    List.append(&2, NN, Pod.secret_sources(Js.items(v, ["projected", "sources"]), sa, ns),
    Pod.present(v, ["iscsi", "secretRef"], "name", ns,
    Pod.present(v, ["rbd", "secretRef"], "name", ns,
    Pod.present(v, ["flexVolume", "secretRef"], "name", ns,
    Pod.present(v, ["cinder", "secretRef"], "name", ns,
    Pod.present(v, ["cephfs", "secretRef"], "name", ns,
    Pod.ref(v, ["azureFile", "secretName"], ns,
    Pod.present(v, ["scaleIO", "secretRef"], "name", ns,
    Pod.present(v, ["storageos", "secretRef"], "name", ns,
    Pod.present(v, ["csi", "nodePublishSecretRef"], "name", ns, rest)))))))))))

def Pod.secret_volumes(vs: List<&2, J.Json>, +sa: Maybe<&2, NN>, +ns: String) -> List<&2, NN>:
  match vs:
    case Nil{}:
      []
    case Con{v, t}:
      Pod.secret_volume(v, sa, ns, Pod.secret_volumes(t, sa, ns))

def Pod.pull_secrets(xs: List<&2, J.Json>, +ns: String) -> List<&2, NN>:
  match xs:
    case Nil{}:
      []
    case Con{x, t}:
      NN{ns, Js.str(J.Json.get(x, "name"))} <> Pod.pull_secrets(t, ns)

# The virtual name of a pod's service-account token secret ("<pod>-sa-token");
# with sync.toHost.pods.useSecretsForSATokens, secretNamesFromPod lists its
# virtual-to-host name (token.SecretNameFromPodName) for every projected
# service account token.
def Secrets.sa_token_name(+pod: J.Json) -> NN:
  NN{Js.namespace(pod), Js.name(pod) ++ "-sa-token"}

# secretNamesFromPod: container refs, image pull secrets, then volumes.
# `sa` is the SA token secret name, or None without useSecretsForSATokens.
# The containers and the volumes are independent, so they are scanned in
# parallel.
def Secrets.from_pod(+sa: Maybe<&2, NN>, +pod: J.Json) -> List<&2, NN>:
  +ns = Js.namespace(pod)
  a b = Pod.all_containers(pod, "secretKeyRef", "secretRef", ns) Pod.secret_volumes(Js.items(pod, ["spec", "volumes"]), sa, ns)
  List.append(&2, NN, a, List.append(&2, NN, Pod.pull_secrets(Js.items(pod, ["spec", "imagePullSecrets"]), ns), b))

# The nginx annotations that name secrets (TranslateAnnotations).
def Secrets.annotated(k: String) -> Bool:
  Str.elem(k, ["nginx.ingress.kubernetes.io/auth-secret", "nginx.ingress.kubernetes.io/auth-tls-secret", "nginx.ingress.kubernetes.io/proxy-ssl-secret"])

def Secrets.split(parts: List<&2, String>, +ns: String, rest: List<&2, NN>) -> List<&2, NN>:
  match parts:
    case Con{a, Nil{}}:
      NN{ns, a} <> rest
    case Con{a, Con{b, Nil{}}}:
      NN{a, b} <> rest
    case _:
      rest

def Secrets.annotation_if(hit: Bool, v: J.Json, +ns: String, rest: List<&2, NN>) -> List<&2, NN>:
  match hit:
    case False{}:
      rest
    case True{}:
      Secrets.split(String.split(Js.str(v), '/'), ns, rest)

def Secrets.annotations(ms: J.Json, +ns: String) -> List<&2, NN>:
  match ms:
    case J.JMem{+k, v, t}:
      Secrets.annotation_if(Secrets.annotated(k), v, ns, Secrets.annotations(t, ns))
    case _:
      []

def Secrets.tls(xs: List<&2, J.Json>, +ns: String) -> List<&2, NN>:
  match xs:
    case Nil{}:
      []
    case Con{+x, t}:
      Pod.ref(x, ["secretName"], ns, Secrets.tls(t, ns))

def Js.members(j: J.Json) -> J.Json:
  match j:
    case J.JObj{ms}:
      ms
    case _:
      J.JNil{}

# secretNamesFromIngress: the secrets the nginx annotations name ("secret" in
# the ingress namespace or "namespace/secret"; vcluster walks a Go map, so its
# order is random; here it is the annotations' order), then the TLS secrets.
def Secrets.from_ingress(+ing: J.Json) -> List<&2, NN>:
  +ns = Js.namespace(ing)
  List.append(&2, NN, Secrets.annotations(Js.members(J.Json.at(ing, ["metadata", "annotations"])), ns), Secrets.tls(Js.items(ing, ["spec", "tls"]), ns))

# Whether a configmap or secret syncs to the host (isConfigMapUsed,
# isSecretUsed): the force-sync annotation is "true", or sync.toHost.*.all
# is on, or some mapping references it. When it is not used, the syncer
# deletes its host copy.
def Sync.used(force: Bool, all: Bool, s: Store, +g: String, n: NN) -> Bool:
  Bool.or(force, Bool.or(all, Bool.not(List.is_empty(&2, NM, Store.references_to(s, g, n)))))

def Sync.force(+o: J.Json) -> Bool:
  String.eq(Js.ann(o, Mappings.force_sync_annotation()), "true")

def ConfigMaps.used(+o: J.Json, all: Bool, s: Store) -> Bool:
  Sync.used(Sync.force(o), all, s, Mappings.configmaps(), Js.nn(o))

def Secrets.used(+o: J.Json, all: Bool, s: Store) -> Bool:
  Sync.used(Sync.force(o), all, s, Mappings.secrets(), Js.nn(o))

def Migrate.ref_if(ok: Bool, s: Store, x: NM, owner: NM) -> Store:
  match ok:
    case False{}:
      s
    case True{}:
      +sx = s
      Migrate.res(Store.add_reference(sx, x, owner), sx)

# The configmap and secret migrations (configMapsMapper.Migrate,
# secretsMapper.Migrate): each name a virtual pod uses is translated by the
# kind's recorder (no owner in the context: nothing recorded there) and, when
# it has a host name, recorded as a reference of the pod (owner: the pod's
# kind and virtual name). With ingress sync on, secrets also record the
# ingresses' secrets, with the owner's kind set to Pod (vcluster quirk).

def Migrate.ref_one(+k: MKind, +c: Ctx, +s: Store, +g: String, +n: NN, +owner: NM) -> Store:
  +p = MKind.virtual_to_host(k, c, n)
  +pn = Rec.found(Ctx.reg(c), Store.virtual_to_host(s, g, n), p)
  Migrate.ref_if(Bool.not(NN.is_empty(pn)), s, NM{g, n, pn}, owner)

def Migrate.refs(ns: List<&2, NN>, +k: MKind, +c: Ctx, s: Store, +g: String, +owner: NM) -> Store:
  match ns:
    case Nil{}:
      s
    case Con{n, t}:
      Migrate.refs(t, k, c, Migrate.ref_one(k, c, s, g, n, owner), g, owner)

def Migrate.owner(+o: J.Json) -> NM:
  NM{Mappings.pods(), Js.nn(o), NN.empty()}

def Migrate.cm_pods(ps: List<&2, J.Json>, +c: Ctx, s: Store) -> Store:
  match ps:
    case Nil{}:
      s
    case Con{+p, t}:
      Migrate.cm_pods(t, c, Migrate.refs(ConfigMaps.from_pod(p), KConfigMap{}, c, s, Mappings.configmaps(), Migrate.owner(p)))

def ConfigMaps.migrate(pods: List<&2, J.Json>, c: Ctx, s: Store) -> Store:
  Migrate.cm_pods(pods, c, s)

# The SA token secret's host name, through the secrets recorder (no owner:
# nothing recorded).
def Secrets.sa(on: Bool, +c: Ctx, +s: Store, +pod: J.Json) -> Maybe<&2, NN>:
  match on:
    case False{}:
      None{}
    case True{}:
      +n = Secrets.sa_token_name(pod)
      Some{Rec.found(Ctx.reg(c), Store.virtual_to_host(s, Mappings.secrets(), n), Mapper.virtual_to_host(c, n))}

def Migrate.secret_pods(ps: List<&2, J.Json>, +sa: Bool, +c: Ctx, s: Store) -> Store:
  match ps:
    case Nil{}:
      s
    case Con{+p, t}:
      +s1 = s
      Migrate.secret_pods(t, sa, c, Migrate.refs(Secrets.from_pod(Secrets.sa(sa, c, s1, p), p), KGeneric{}, c, s1, Mappings.secrets(), Migrate.owner(p)))

def Migrate.secret_ingresses(xs: List<&2, J.Json>, +c: Ctx, s: Store) -> Store:
  match xs:
    case Nil{}:
      s
    case Con{+i, t}:
      Migrate.secret_ingresses(t, c, Migrate.refs(Secrets.from_ingress(i), KGeneric{}, c, s, Mappings.secrets(), Migrate.owner(i)))

def Secrets.migrate.ing(on: Bool, ingresses: List<&2, J.Json>, +c: Ctx, s: Store) -> Store:
  match on:
    case False{}:
      s
    case True{}:
      Migrate.secret_ingresses(ingresses, c, s)

def Secrets.migrate(pods: List<&2, J.Json>, sa: Bool, ingresses_on: Bool, ingresses: List<&2, J.Json>, +c: Ctx, s: Store) -> Store:
  Secrets.migrate.ing(ingresses_on, ingresses, c, Migrate.secret_pods(pods, sa, c, s))

# The namespace mapper in single-namespace mode (resources/namespaces.go):
# every virtual namespace maps to the target namespace; no host namespace has
# a virtual name, and none is managed. With sync.toHost.namespaces (Pro) the
# mapper is a no-op.

def Namespaces.virtual_to_host(target: String, n: NN) -> NN:
  NN{"", Tr.host_ns(target, NN.name(n))}

def Namespaces.host_to_virtual(n: NN) -> NN:
  NN.empty()

def Namespaces.is_managed(o: J.Json) -> Bool:
  False{}
