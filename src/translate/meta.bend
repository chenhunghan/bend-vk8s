import Base
import ../lib/sha256.bend as H
import ./names.bend as N

# Metadata translation (vcluster pkg/util/translate: translate.go, labels.go,
# single_namespace.go, types.go), as pure functions over string maps.
#
# A string map (Go map[string]string) is a key-sorted, duplicate-free list of
# KV pairs, sorted by String.order (code-point order, which is Go's byte order
# on UTF-8). Meta.canon states that form; insert, delete, from_list and union
# keep it. A Go map that may be nil is a Maybe of a map; where vcluster treats
# nil and empty alike, the map is plain.
#
# vcluster reads the vcluster name from the global VClusterName and the
# target namespace from the default translator; here both are arguments
# (vc, target).

type KV is Data:
  KV{k: String, v: String}

# The metadata of an object, as far as this module reads it. `kind` is the
# object's GroupVersionKind string (Go gvk.String(), e.g. "/v1, Kind=Secret"),
# or "" when the scheme does not know the object. `deleting` is
# DeletionTimestamp != nil.
type Obj is Data:
  Obj{name: String, namespace: String, uid: String, kind: String, deleting: Bool, labels: List<&2, KV>, annotations: List<&2, KV>}

# metav1.LabelSelectorRequirement.
type Req is Data:
  Req{key: String, op: String, values: List<&2, String>}

# metav1.LabelSelector. MatchLabels may be nil (None).
type Sel is Data:
  Sel{labels: Maybe<&2, List<&2, KV>>, exprs: List<&2, Req>}

# Constants (vcluster types.go).

def Meta.namespace_annotation() -> String:
  "vcluster.loft.sh/object-namespace"

def Meta.name_annotation() -> String:
  "vcluster.loft.sh/object-name"

def Meta.uid_annotation() -> String:
  "vcluster.loft.sh/object-uid"

def Meta.kind_annotation() -> String:
  "vcluster.loft.sh/object-kind"

def Meta.host_name_annotation() -> String:
  "vcluster.loft.sh/object-host-name"

def Meta.host_namespace_annotation() -> String:
  "vcluster.loft.sh/object-host-namespace"

def Meta.managed_annotations_annotation() -> String:
  "vcluster.loft.sh/managed-annotations"

def Meta.managed_labels_annotation() -> String:
  "vcluster.loft.sh/managed-labels"

def Meta.release_label() -> String:
  "release"

def Meta.namespace_label() -> String:
  "vcluster.loft.sh/namespace"

def Meta.marker_label() -> String:
  "vcluster.loft.sh/managed-by"

def Meta.controller_label() -> String:
  "vcluster.loft.sh/controlled-by"

def Meta.label_prefix() -> String:
  "vcluster.loft.sh/label"

def Meta.namespace_label_prefix() -> String:
  "vcluster.loft.sh/ns-label"

# String lists.

def Meta.elem(+k: String, xs: +List<String>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{x, r}:
      Bool.or(String.eq(k, x), Meta.elem(k, r))

def Meta.any_prefix(+k: String, ps: +List<String>) -> Bool:
  match ps:
    case Nil{}:
      False{}
    case Con{p, r}:
      Bool.or(String.starts_with(k, p), Meta.any_prefix(k, r))

def Meta.cat(xs: +List<String>, ys: +List<String>) -> +List<String>:
  match xs:
    case Nil{}:
      ys
    case Con{x, r}:
      x <> Meta.cat(r, ys)

# Maps.

def Meta.get.if(c: Cmp, v: String, rec: Maybe<&2, String>) -> Maybe<&2, String>:
  match c:
    case LT{}:
      rec
    case EQ{}:
      Some{v}
    case GT{}:
      rec

# The value of key k (the first entry with that key).
def Meta.get(+k: String, m: +List<KV>) -> Maybe<&2, String>:
  match m:
    case Nil{}:
      None{}
    case Con{KV{kk, vv}, r}:
      Meta.get.if(String.order(k, kk), vv, Meta.get(k, r))

# Go m[k]: the value, or "" when absent.
def Meta.lookup(k: String, m: +List<KV>) -> String:
  Maybe.default(&2, String, Meta.get(k, m), "")

def Meta.has(k: String, m: +List<KV>) -> Bool:
  Maybe.is_some(&2, String, Meta.get(k, m))

def Meta.insert.if(c: Cmp, kk: String, vv: String, k: String, v: String, r: +List<KV>, rec: +List<KV>) -> +List<KV>:
  match c:
    case LT{}:
      KV{k, v} <> KV{kk, vv} <> r
    case EQ{}:
      KV{kk, v} <> r
    case GT{}:
      KV{kk, vv} <> rec

# Go m[k] = v.
def Meta.insert(+k: String, +v: String, m: +List<KV>) -> +List<KV>:
  match m:
    case Nil{}:
      [KV{k, v}]
    case Con{KV{+kk, vv}, +r}:
      Meta.insert.if(String.order(k, kk), kk, vv, k, v, r, Meta.insert(k, v, r))

def Meta.delete.if(c: Cmp, x: KV, rec: +List<KV>) -> +List<KV>:
  match c:
    case LT{}:
      x <> rec
    case EQ{}:
      rec
    case GT{}:
      x <> rec

# Go delete(m, k).
def Meta.delete(+k: String, m: +List<KV>) -> +List<KV>:
  match m:
    case Nil{}:
      Nil{}
    case Con{KV{+kk, vv}, r}:
      Meta.delete.if(String.order(k, kk), KV{kk, vv}, Meta.delete(k, r))

# The map of a list of pairs; the first pair of a key wins.
def Meta.from_list(xs: +List<KV>) -> +List<KV>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{KV{k, v}, r}:
      Meta.insert(k, v, Meta.from_list(r))

# Every entry of a, and the entries of b whose key a lacks.
def Meta.union(a: +List<KV>, b: +List<KV>) -> +List<KV>:
  match a:
    case Nil{}:
      b
    case Con{KV{k, v}, r}:
      Meta.insert(k, v, Meta.union(r, b))

def Meta.keys(m: +List<KV>) -> +List<String>:
  match m:
    case Nil{}:
      Nil{}
    case Con{KV{k, v}, r}:
      k <> Meta.keys(r)

# True when every key of m is greater than k.
def Meta.above(+k: String, m: +List<KV>) -> Bool:
  match m:
    case Nil{}:
      True{}
    case Con{KV{kk, vv}, r}:
      Bool.and(Cmp.is_lt(String.order(k, kk)), Meta.above(k, r))

# The canonical form: keys strictly increasing.
def Meta.canon(m: +List<KV>) -> Bool:
  match m:
    case Nil{}:
      True{}
    case Con{KV{kk, vv}, +r}:
      Bool.and(Meta.above(kk, r), Meta.canon(r))

# Strictly increasing strings.
def Meta.str_above(+k: String, xs: +List<String>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{x, r}:
      Bool.and(Cmp.is_lt(String.order(k, x)), Meta.str_above(k, r))

def Meta.sorted(xs: +List<String>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{x, +r}:
      Bool.and(Meta.str_above(x, r), Meta.sorted(r))

# Equality of two optional values.
def Meta.opt_eq(a: Maybe<&2, String>, b: Maybe<&2, String>) -> Bool:
  match a b:
    case None{} None{}:
      True{}
    case Some{x} Some{y}:
      String.eq(x, y)
    case _ _:
      False{}

# True when a and b give the same value for every key in ks.
def Meta.agree_on(ks: +List<String>, +a: +List<KV>, +b: +List<KV>) -> Bool:
  match ks:
    case Nil{}:
      True{}
    case Con{q, r}:
      +qq = q
      Bool.and(Meta.opt_eq(Meta.get(qq, a), Meta.get(qq, b)), Meta.agree_on(r, a, b))

# True when a and b give the same value for every key of either.
def Meta.agree(+a: +List<KV>, +b: +List<KV>) -> Bool:
  Bool.and(Meta.agree_on(Meta.keys(a), a, b), Meta.agree_on(Meta.keys(b), a, b))

# Go maps.Equal.
def Meta.map_eq(a: +List<KV>, b: +List<KV>) -> Bool:
  match a b:
    case Nil{} Nil{}:
      True{}
    case Con{KV{k1, v1}, r1} Con{KV{k2, v2}, r2}:
      Bool.and(Bool.and(String.eq(k1, k2), String.eq(v1, v2)), Meta.map_eq(r1, r2))
    case _ _:
      False{}

# Filters.

# A key is excluded when it is one of xs or starts with one of ps.
def Meta.excluded(+k: String, xs: +List<String>, ps: +List<String>) -> Bool:
  Bool.or(Meta.elem(k, xs), Meta.any_prefix(k, ps))

def Meta.keep.if(drop: Bool, x: KV, rec: +List<KV>) -> +List<KV>:
  match drop:
    case True{}:
      rec
    case False{}:
      x <> rec

# The entries whose key is not excluded.
def Meta.keep_out(m: +List<KV>, +xs: +List<String>, +ps: +List<String>) -> +List<KV>:
  match m:
    case Nil{}:
      Nil{}
    case Con{KV{+k, v}, r}:
      Meta.keep.if(Meta.excluded(k, xs, ps), KV{k, v}, Meta.keep_out(r, xs, ps))

# The entries whose key is excluded.
def Meta.keep_in(m: +List<KV>, +xs: +List<String>, +ps: +List<String>) -> +List<KV>:
  match m:
    case Nil{}:
      Nil{}
    case Con{KV{+k, v}, r}:
      Meta.keep.if(Bool.not(Meta.excluded(k, xs, ps)), KV{k, v}, Meta.keep_in(r, xs, ps))

# vcluster copyMaps: the entries of `from` whose key is not excluded, and the
# entries of `to` whose key is. The two filters are independent.
def Meta.copy_maps(from: +List<KV>, to: +List<KV>, +xs: +List<String>, +ps: +List<String>) -> +List<KV>:
  a b = Meta.keep_out(from, xs, ps) Meta.keep_in(to, xs, ps)
  Meta.union(a, b)

# ApplyMaps.

# A key of `to` survives when it is excluded, or when `from` does not set it
# and the previous managed list does not name it.
def Meta.to_keep(+k: String, from: +List<KV>, managed: +List<String>, +exclude: +List<String>) -> Bool:
  Bool.or(Meta.elem(k, exclude), Bool.and(Bool.not(Meta.has(k, from)), Bool.not(Meta.elem(k, managed))))

def Meta.to_part(to: +List<KV>, +from: +List<KV>, +managed: +List<String>, +exclude: +List<String>) -> +List<KV>:
  match to:
    case Nil{}:
      Nil{}
    case Con{KV{+k, v}, r}:
      Meta.keep.if(Bool.not(Meta.to_keep(k, from, managed, exclude)), KV{k, v}, Meta.to_part(r, from, managed, exclude))

# The keys ApplyMaps manages: the keys of `from` that are not excluded, sorted.
def Meta.managed_keys(from: +List<KV>, exclude: +List<String>) -> +List<String>:
  Meta.keys(Meta.keep_out(from, exclude, []))

# vcluster ApplyMaps(fromMap, toMap, {ManagedKeys, ExcludeKeys}): the merged
# map and the managed keys joined by "\n". The `from` and `to` parts are
# independent.
def Meta.apply_maps(+from: +List<KV>, to: +List<KV>, managed: +List<String>, +exclude: +List<String>) -> +List<KV> & String:
  f t = Meta.keep_out(from, exclude, []) Meta.to_part(to, from, managed, exclude)
  +fm = f
  (Meta.union(fm, t), String.join(Meta.keys(fm), "\n"))

def Meta.set_or_delete.if(empty: Bool, k: String, s: String, m: +List<KV>) -> +List<KV>:
  match empty:
    case True{}:
      Meta.delete(k, m)
    case False{}:
      Meta.insert(k, s, m)

# m[k] = s, or delete(m, k) when s is "".
def Meta.set_or_delete(k: String, +s: String, m: +List<KV>) -> +List<KV>:
  Meta.set_or_delete.if(String.is_empty(s), k, s, m)

def Meta.set_nonempty.if(empty: Bool, k: String, s: String, m: +List<KV>) -> +List<KV>:
  match empty:
    case True{}:
      m
    case False{}:
      Meta.insert(k, s, m)

# m[k] = s unless s is "".
def Meta.set_nonempty(k: String, +s: String, m: +List<KV>) -> +List<KV>:
  Meta.set_nonempty.if(String.is_empty(s), k, s, m)

def Meta.apply_annotations.fin(r: +List<KV> & String) -> +List<KV>:
  (m, s) = r
  Meta.set_or_delete(Meta.managed_annotations_annotation(), s, m)

# vcluster applyAnnotations.
def Meta.apply_annotations(from: +List<KV>, +to: +List<KV>, exclude: +List<String>) -> +List<KV>:
  Meta.apply_annotations.fin(Meta.apply_maps(from, to,
    String.split(Meta.lookup(Meta.managed_annotations_annotation(), to), '\n'),
    Meta.managed_annotations_annotation() <> Meta.managed_labels_annotation() <> exclude))

def Meta.apply_labels.fin(r: +List<KV> & String, to_annotations: +List<KV>) -> +List<KV> & +List<KV>:
  (m, s) = r
  (m, Meta.set_or_delete(Meta.managed_labels_annotation(), s, to_annotations))

# vcluster applyLabels: the merged labels and the updated annotations.
def Meta.apply_labels(from: +List<KV>, to: +List<KV>, +to_annotations: +List<KV>) -> +List<KV> & +List<KV>:
  Meta.apply_labels.fin(Meta.apply_maps(from, to,
    String.split(Meta.lookup(Meta.managed_labels_annotation(), to_annotations), '\n'),
    [Meta.managed_annotations_annotation(), Meta.managed_labels_annotation()]), to_annotations)

# vcluster ApplyMetadata: (labels, annotations).
def Meta.apply_metadata(from_annotations: +List<KV>, to_annotations: +List<KV>, from_labels: +List<KV>, to_labels: +List<KV>, exclude: +List<String>) -> +List<KV> & +List<KV>:
  Meta.apply_labels(from_labels, to_labels, Meta.apply_annotations(from_annotations, to_annotations, exclude))

# Annotations.

def Meta.add_host.p(m: +List<KV>, p: Maybe<&2, Obj>) -> +List<KV>:
  match p:
    case None{}:
      m
    case Some{Obj{name, namespace, uid, kind, deleting, labels, annotations}}:
      Meta.set_nonempty(Meta.host_namespace_annotation(), namespace, Meta.insert(Meta.host_name_annotation(), name, m))

# vcluster addHostAnnotations.
def Meta.add_host(m: +List<KV>, v: Obj, p: Maybe<&2, Obj>) -> +List<KV>:
  match v:
    case Obj{name, namespace, uid, kind, deleting, labels, annotations}:
      m1 = Meta.insert(Meta.uid_annotation(), uid, Meta.insert(Meta.name_annotation(), name, m))
      m2 = Meta.add_host.p(m1, p)
      m3 = Meta.set_or_delete(Meta.namespace_annotation(), namespace, m2)
      Meta.set_nonempty(Meta.kind_annotation(), kind, m3)

def Meta.annotations_of(o: Obj) -> +List<KV>:
  match o:
    case Obj{name, namespace, uid, kind, deleting, labels, annotations}:
      annotations

def Meta.labels_of(o: Obj) -> +List<KV>:
  match o:
    case Obj{name, namespace, uid, kind, deleting, labels, annotations}:
      labels

def Meta.maybe_annotations(o: Maybe<&2, Obj>) -> +List<KV>:
  match o:
    case None{}:
      Nil{}
    case Some{x}:
      Meta.annotations_of(x)

def Meta.copy_namespace.if(cluster: Bool, ns: String) -> String:
  match cluster:
    case True{}:
      ""
    case False{}:
      ns

# vcluster CopyObjectWithName(obj, {name, namespace}, _, excluded...), as far
# as the metadata goes: the uid and deletion are reset, the name is set, the
# namespace is set for a namespaced object, and the excluded annotations are
# stripped. Owner references are not modelled.
def Meta.copy_object(o: Obj, name: String, namespace: String, excluded: +List<String>) -> Obj:
  match o:
    case Obj{oname, onamespace, uid, kind, deleting, labels, annotations}:
      Obj{name, Meta.copy_namespace.if(String.is_empty(onamespace), namespace), "", kind, False{}, labels, Meta.keep_out(annotations, excluded, [])}

# vcluster HostAnnotations(vObj, pObj, excluded...).
def Meta.host_annotations(+v: Obj, +p: Maybe<&2, Obj>, excluded: +List<String>) -> +List<KV>:
  excl = Meta.cat(excluded, [Meta.name_annotation(), Meta.host_name_annotation(), Meta.host_namespace_annotation(),
    Meta.uid_annotation(), Meta.kind_annotation(), Meta.namespace_annotation()])
  m = Meta.apply_annotations(Meta.annotations_of(v), Meta.maybe_annotations(p), excl)
  Meta.add_host(m, v, p)

# vcluster VirtualAnnotations(pObj, vObj, excluded...).
def Meta.virtual_annotations(p: Obj, v: Maybe<&2, Obj>, excluded: +List<String>) -> +List<KV>:
  excl = Meta.cat(excluded, [Meta.namespace_annotation(), Meta.name_annotation(), Meta.host_name_annotation(),
    Meta.host_namespace_annotation(), Meta.uid_annotation(), Meta.kind_annotation(),
    Meta.managed_annotations_annotation(), Meta.managed_labels_annotation()])
  Meta.copy_maps(Meta.annotations_of(p), Meta.maybe_annotations(v), excl, [])

# Labels.

def Meta.vc_prefix() -> String:
  "vcluster.loft.sh/"

# True when no key of m starts with "vcluster.loft.sh/".
def Meta.no_vc_keys(m: +List<KV>) -> Bool:
  match m:
    case Nil{}:
      True{}
    case Con{KV{k, v}, r}:
      Bool.and(Bool.not(String.starts_with(k, Meta.vc_prefix())), Meta.no_vc_keys(r))

# vcluster convertLabelKeyWithPrefix(prefix, key), given h, the first 10 hex
# digits of the SHA-256 of key.
def Meta.convert.h(prefix: String, vc: String, h: String) -> String:
  N.Names.safe_concat([prefix, vc, "x", h])

# vcluster convertLabelKeyWithPrefix(prefix, key).
def Meta.convert(prefix: String, vc: String, key: String) -> String:
  Meta.convert.h(prefix, vc, String.take(H.Sha256.hex_of(key), 10n))

# singleNamespace.LabelsToTranslate, each with its translated key, release
# first. The hashes of the four fixed keys are constants (law
# meta.tkeys_convert checks them against Sha256), so a translation hashes
# nothing unless the key is longer than 63 characters.
def Meta.tkeys(+vc: String) -> +List<KV>:
  [KV{Meta.release_label(), Meta.convert.h(Meta.label_prefix(), vc, "a4d451ec23")},
   KV{Meta.namespace_label(), Meta.convert.h(Meta.label_prefix(), vc, "101dcd4e86")},
   KV{Meta.marker_label(), Meta.convert.h(Meta.label_prefix(), vc, "e5f1b28ab2")},
   KV{Meta.controller_label(), Meta.convert.h(Meta.label_prefix(), vc, "2080cec00f")}]

def Meta.is_translated.if(hit: Bool, o: String, rec: Maybe<&2, String>) -> Maybe<&2, String>:
  match hit:
    case True{}:
      Some{o}
    case False{}:
      rec

# The label whose translated key is k, in the order of tk.
def Meta.is_translated.t(tk: +List<KV>, +k: String) -> Maybe<&2, String>:
  match tk:
    case Nil{}:
      None{}
    case Con{KV{o, c}, r}:
      Meta.is_translated.if(String.eq(c, k), o, Meta.is_translated.t(r, k))

def Meta.host_label.t(tk: +List<KV>, +k: String) -> String:
  Maybe.default(&2, String, Meta.get(k, tk), k)

def Meta.virtual_label.if(set: Bool, tk: +List<KV>, k: String) -> Maybe<&2, String>:
  match set:
    case True{}:
      None{}
    case False{}:
      +kk = k
      Maybe.or(&2, String, Meta.is_translated.t(tk, kk), Some{kk})

def Meta.virtual_label.t(+tk: +List<KV>, +k: String) -> Maybe<&2, String>:
  Meta.virtual_label.if(Meta.has(k, tk), tk, k)

# vcluster IsTranslatedLabel.
def Meta.is_translated(vc: String, k: String) -> Maybe<&2, String>:
  Meta.is_translated.t(Meta.tkeys(vc), k)

# vcluster HostLabel.
def Meta.host_label(vc: String, k: String) -> String:
  Meta.host_label.t(Meta.tkeys(vc), k)

# vcluster VirtualLabel: None where Go answers ok == false.
def Meta.virtual_label(vc: String, k: String) -> Maybe<&2, String>:
  Meta.virtual_label.t(Meta.tkeys(vc), k)

def Meta.host_keys.if(translated: Bool, hk: String, v: String, rec: +List<KV>) -> +List<KV>:
  match translated:
    case True{}:
      rec
    case False{}:
      Meta.insert(hk, v, rec)

# The labels of m that are not translated keys, under their host keys.
def Meta.host_keys(+tk: +List<KV>, m: +List<KV>) -> +List<KV>:
  match m:
    case Nil{}:
      Nil{}
    case Con{KV{+k, v}, r}:
      Meta.host_keys.if(Maybe.is_some(&2, String, Meta.is_translated.t(tk, k)), Meta.host_label.t(tk, k), v, Meta.host_keys(tk, r))

def Meta.add_marker.if(cluster: Bool, vc: String, target: String, ns: String, m: +List<KV>) -> +List<KV>:
  match cluster:
    case True{}:
      Meta.insert(Meta.marker_label(), N.Names.marker_cluster(target, vc), m)
    case False{}:
      Meta.insert(Meta.namespace_label(), ns, Meta.insert(Meta.marker_label(), vc, m))

def Meta.add_marker(add: Bool, vc: String, target: String, +ns: String, m: +List<KV>) -> +List<KV>:
  match add:
    case True{}:
      Meta.add_marker.if(String.is_empty(ns), vc, target, ns, m)
    case False{}:
      m

def Meta.maybe_map(m: Maybe<&2, List<&2, KV>>) -> +List<KV>:
  match m:
    case None{}:
      Nil{}
    case Some{x}:
      x

# vcluster HostLabelsMap(vLabels, pLabels, vNamespace, isMetadata).
def Meta.host_labels_map(+vc: String, target: String, v: Maybe<&2, List<&2, KV>>, +p: Maybe<&2, List<&2, KV>>, ns: String, is_meta: Bool) -> Maybe<&2, List<&2, KV>>:
  match v:
    case None{}:
      None{}
    case Some{vl}:
      +pl = Meta.maybe_map(p)
      nl = Meta.host_keys(Meta.tkeys(vc), vl)
      add = Bool.or(is_meta, Bool.or(Maybe.is_none(&2, List<&2, KV>, p), Bool.not(String.is_empty(Meta.lookup(Meta.marker_label(), pl)))))
      nl2 = Meta.add_marker(add, vc, target, ns, nl)
      Some{Meta.set_nonempty(Meta.controller_label(), Meta.lookup(Meta.controller_label(), pl), nl2)}

def Meta.back.if(vk: Maybe<&2, String>, val: String, rec: +List<KV>) -> +List<KV>:
  match vk:
    case None{}:
      rec
    case Some{k}:
      KV{k, val} <> rec

# The entries of r whose key translates back, under their virtual keys.
def Meta.back(+tk: +List<KV>, r: +List<KV>) -> +List<KV>:
  match r:
    case Nil{}:
      Nil{}
    case Con{KV{k, val}, rest}:
      Meta.back.if(Meta.virtual_label.t(tk, k), val, Meta.back(tk, rest))

def Meta.restrict.if(vv: Maybe<&2, String>, k: String, rec: +List<KV>) -> +List<KV>:
  match vv:
    case None{}:
      rec
    case Some{x}:
      KV{k, x} <> rec

# The keys of r that v has, with v's values.
def Meta.restrict(r: +List<KV>, +v: +List<KV>) -> +List<KV>:
  match r:
    case Nil{}:
      Nil{}
    case Con{KV{+k, val}, rest}:
      Meta.restrict.if(Meta.get(k, v), k, Meta.restrict(rest, v))

# vcluster VirtualLabelsMap(pLabels, vLabels, excluded...).
#
# Go rewrites retLabels while it ranges over it. This follows the reading
# that TestVirtualLabels needs: each entry present when the loop starts is
# visited once, and a key that an entry translates back to wins over the
# value the loop kept for that key (Go's order is random there; it only
# matters when a host map holds a translated key and its original at once).
def Meta.virtual_labels_map(vc: String, p: Maybe<&2, List<&2, KV>>, +v: +List<KV>, excluded: +List<String>) -> Maybe<&2, List<&2, KV>>:
  match p:
    case None{}:
      None{}
    case Some{pl}:
      +r = Meta.copy_maps(pl, v, Meta.cat(excluded, [Meta.marker_label(), Meta.namespace_label(), Meta.controller_label()]), [Meta.namespace_label_prefix()])
      b a = Meta.from_list(Meta.back(Meta.tkeys(vc), r)) Meta.restrict(r, v)
      Some{Meta.union(b, a)}

# Label selectors.

def Meta.host_pairs(+tk: +List<KV>, m: +List<KV>) -> +List<KV>:
  match m:
    case Nil{}:
      Nil{}
    case Con{KV{k, v}, r}:
      KV{Meta.host_label.t(tk, k), v} <> Meta.host_pairs(tk, r)

def Meta.host_reqs(+tk: +List<KV>, rs: +List<Req>) -> +List<Req>:
  match rs:
    case Nil{}:
      Nil{}
    case Con{Req{key, op, values}, r}:
      Req{Meta.host_label.t(tk, key), op, values} <> Meta.host_reqs(tk, r)

def Meta.virtual_key(+tk: +List<KV>, +k: String) -> String:
  Maybe.default(&2, String, Meta.virtual_label.t(tk, k), k)

def Meta.virtual_pairs(+tk: +List<KV>, m: +List<KV>) -> +List<KV>:
  match m:
    case Nil{}:
      Nil{}
    case Con{KV{k, v}, r}:
      KV{Meta.virtual_key(tk, k), v} <> Meta.virtual_pairs(tk, r)

def Meta.virtual_reqs(+tk: +List<KV>, rs: +List<Req>) -> +List<Req>:
  match rs:
    case Nil{}:
      Nil{}
    case Con{Req{key, op, values}, r}:
      Req{Meta.virtual_key(tk, key), op, values} <> Meta.virtual_reqs(tk, r)

def Meta.host_match_labels(tk: +List<KV>, ml: Maybe<&2, List<&2, KV>>) -> Maybe<&2, List<&2, KV>>:
  match ml:
    case None{}:
      None{}
    case Some{m}:
      Some{Meta.from_list(Meta.host_pairs(tk, m))}

def Meta.virtual_match_labels(tk: +List<KV>, ml: Maybe<&2, List<&2, KV>>) -> Maybe<&2, List<&2, KV>>:
  match ml:
    case None{}:
      None{}
    case Some{m}:
      Some{Meta.from_list(Meta.virtual_pairs(tk, m))}

# vcluster HostLabelSelector. When two keys meet on one host key, the first
# (smallest) virtual key wins; Go's choice there is random.
def Meta.host_label_selector(vc: String, s: Maybe<&2, Sel>) -> Maybe<&2, Sel>:
  match s:
    case None{}:
      None{}
    case Some{Sel{ml, ex}}:
      +tk = Meta.tkeys(vc)
      Some{Sel{Meta.host_match_labels(tk, ml), Meta.host_reqs(tk, ex)}}

# vcluster VirtualLabelSelector.
def Meta.virtual_label_selector(vc: String, s: Maybe<&2, Sel>) -> Maybe<&2, Sel>:
  match s:
    case None{}:
      None{}
    case Some{Sel{ml, ex}}:
      +tk = Meta.tkeys(vc)
      Some{Sel{Meta.virtual_match_labels(tk, ml), Meta.virtual_reqs(tk, ex)}}

# Predicates.

# a != "" && a != b, as Go writes `a != "" && a != b`.
def Meta.set_and_differs(+a: String, b: String) -> Bool:
  Bool.and(Bool.not(String.is_empty(a)), Bool.not(String.eq(a, b)))

# a == "" || a != b.
def Meta.unset_or_differs(+a: String, b: String) -> Bool:
  Bool.or(String.is_empty(a), Bool.not(String.eq(a, b)))

def Meta.should_delete.if(deleting: Bool, name: String, +namespace: String, kind: String, +ann: +List<KV>) -> Bool:
  match deleting:
    case True{}:
      True{}
    case False{}:
      kind_ok = Bool.not(Meta.unset_or_differs(Meta.lookup(Meta.kind_annotation(), ann), kind))
      name_ok = Bool.and(Bool.not(String.is_empty(Meta.lookup(Meta.name_annotation(), ann))),
        Bool.not(Meta.unset_or_differs(Meta.lookup(Meta.host_name_annotation(), ann), name)))
      ns_ok = Bool.or(String.is_empty(namespace),
        Bool.and(Bool.not(String.is_empty(Meta.lookup(Meta.namespace_annotation(), ann))),
          Bool.not(Meta.unset_or_differs(Meta.lookup(Meta.host_namespace_annotation(), ann), namespace))))
      Bool.and(kind_ok, Bool.and(name_ok, ns_ok))

# vcluster ShouldDeleteHostObject.
def Meta.should_delete_host_object(p: Obj) -> Bool:
  match p:
    case Obj{name, namespace, uid, kind, deleting, labels, annotations}:
      Meta.should_delete.if(deleting, name, namespace, kind, annotations)

def Meta.expected_differs(expected: Maybe<&2, String>, name: String) -> Bool:
  match expected:
    case None{}:
      False{}
    case Some{e}:
      Bool.not(String.eq(name, e))

# The checks of IsManaged that need the object's kind.
def Meta.kind_checks.if(unknown: Bool, +name: String, kind: String, expected: Maybe<&2, String>, +ann: +List<KV>) -> Bool:
  match unknown:
    case True{}:
      True{}
    case False{}:
      Bool.and(Bool.not(String.is_empty(Meta.lookup(Meta.name_annotation(), ann))),
        Bool.and(Bool.not(Meta.expected_differs(expected, name)),
          Bool.not(Meta.set_and_differs(Meta.lookup(Meta.kind_annotation(), ann), kind))))

def Meta.is_managed.if(cluster: Bool, vc: String, target: String, expected: Maybe<&2, String>, +name: String, +namespace: String, +kind: String, +labels: +List<KV>, +ann: +List<KV>) -> Bool:
  match cluster:
    case True{}:
      String.eq(Meta.lookup(Meta.marker_label(), labels), N.Names.marker_cluster(target, vc))
    case False{}:
      Bool.and(String.eq(namespace, target),
        Bool.and(String.eq(Meta.lookup(Meta.marker_label(), labels), vc),
          Bool.and(Meta.kind_checks.if(String.is_empty(kind), name, kind, expected, ann),
            Bool.and(Bool.not(Meta.set_and_differs(Meta.lookup(Meta.host_name_annotation(), ann), name)),
              Bool.not(Meta.set_and_differs(Meta.lookup(Meta.host_namespace_annotation(), ann), namespace))))))

# vcluster singleNamespace.IsManaged. `expected` is the host name that the
# mappings store gives the object's name and namespace annotations
# (mappings.VirtualToHostName), or None when there is no mapping for the
# kind (ctx.Mappings nil or without the GVK).
def Meta.is_managed(vc: String, target: String, expected: Maybe<&2, String>, p: Obj) -> Bool:
  match p:
    case Obj{name, +namespace, uid, kind, deleting, labels, annotations}:
      Meta.is_managed.if(String.is_empty(namespace), vc, target, expected, name, namespace, kind, labels, annotations)

# Bidirectional annotation sync.

def Meta.sets.if(same: Bool, x: KV, rec: +List<KV>) -> +List<KV>:
  match same:
    case True{}:
      rec
    case False{}:
      x <> rec

def Meta.maybe_is(m: Maybe<&2, String>, v: String) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{x}:
      String.eq(x, v)

# The entries of `after` that `before` lacks or holds with another value,
# and whose key is not dropped.
def Meta.diff_sets(after: +List<KV>, +before: +List<KV>, +drop: +List<String>) -> +List<KV>:
  match after:
    case Nil{}:
      Nil{}
    case Con{KV{+k, +v}, r}:
      same = Bool.or(Meta.elem(k, drop), Meta.maybe_is(Meta.get(k, before), v))
      Meta.sets.if(same, KV{k, v}, Meta.diff_sets(r, before, drop))

def Meta.diff_dels.if(skip: Bool, k: String, rec: +List<String>) -> +List<String>:
  match skip:
    case True{}:
      rec
    case False{}:
      k <> rec

# The keys of `before` that `after` lacks, without the dropped keys.
def Meta.diff_dels(before: +List<KV>, +after: +List<KV>, +drop: +List<String>) -> +List<String>:
  match before:
    case Nil{}:
      Nil{}
    case Con{KV{+k, v}, r}:
      Meta.diff_dels.if(Bool.or(Meta.elem(k, drop), Meta.has(k, after)), k, Meta.diff_dels(r, after, drop))

def Meta.delete_all(ks: +List<String>, m: +List<KV>) -> +List<KV>:
  match ks:
    case Nil{}:
      m
    case Con{k, r}:
      Meta.delete(k, Meta.delete_all(r, m))

# vcluster mergeMaps with a transform that drops the keys in `drop`.
def Meta.merge_maps(+before: +List<KV>, +after: +List<KV>, target: +List<KV>, +drop: +List<String>) -> +List<KV>:
  Meta.union(Meta.diff_sets(after, before, drop), Meta.delete_all(Meta.diff_dels(before, after, drop), target))

def Meta.bidi.if(virtual_changed: Bool, host_changed: Bool, before_v: +List<KV>, +after_v: +List<KV>, before_h: +List<KV>, +after_h: +List<KV>, drop: +List<String>) -> +List<KV> & +List<KV>:
  match virtual_changed:
    case True{}:
      (after_v, Meta.merge_maps(before_v, after_v, after_h, drop))
    case False{}:
      match host_changed:
        case True{}:
          (Meta.merge_maps(before_h, after_h, after_v, drop), after_h)
        case False{}:
          (after_v, after_h)

def Meta.bidi.fin(r: +List<KV> & +List<KV>, virtual: Obj, host: Obj) -> +List<KV> & +List<KV>:
  (nv, nh) = r
  (nv, Meta.add_host(nh, virtual, Some{host}))

# vcluster AnnotationsBidirectionalUpdate(event, excluded...), with the event
# NewSyncEventWithOld(hostOld, host, virtualOld, virtual). The result is
# (new virtual annotations, new host annotations).
def Meta.annotations_bidirectional_update(host_old: Obj, +host: Obj, virtual_old: Obj, +virtual: Obj, excluded: +List<String>) -> +List<KV> & +List<KV>:
  drop = Meta.cat([Meta.host_name_annotation(), Meta.host_namespace_annotation(), Meta.name_annotation(),
    Meta.uid_annotation(), Meta.kind_annotation(), Meta.namespace_annotation(),
    Meta.managed_annotations_annotation(), Meta.managed_labels_annotation()], excluded)
  +bv = Meta.annotations_of(virtual_old)
  +av = Meta.annotations_of(virtual)
  +bh = Meta.annotations_of(host_old)
  +ah = Meta.annotations_of(host)
  Meta.bidi.fin(Meta.bidi.if(Bool.not(Meta.map_eq(bv, av)), Bool.not(Meta.map_eq(bh, ah)), bv, av, bh, ah, drop), virtual, host)
