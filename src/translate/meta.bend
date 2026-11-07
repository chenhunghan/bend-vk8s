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

type Obj is Data:
  Obj{name: String, namespace: String, uid: String, kind: String, deleting: Bool, labels: List<&2, KV>, annotations: List<&2, KV>}
# The metadata of an object, as far as this module reads it. `kind` is the
# object's GroupVersionKind string (Go gvk.String(), e.g. "/v1, Kind=Secret"),
# or "" when the scheme does not know the object. `deleting` is
# DeletionTimestamp != nil.

type Req is Data:
  Req{key: String, op: String, values: List<&2, String>}
# metav1.LabelSelectorRequirement.

type Sel is Data:
  Sel{labels: Maybe<&2, List<&2, KV>>, exprs: List<&2, Req>}
# metav1.LabelSelector. MatchLabels may be nil (None).

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
  ?TODO

# Maps.

# The value of key k (the first entry with that key).
def Meta.get(+k: String, m: +List<KV>) -> Maybe<&2, String>:
  ?TODO

# Go m[k]: the value, or "" when absent.
def Meta.lookup(k: String, m: +List<KV>) -> String:
  ?TODO

# Go m[k] = v.
def Meta.insert(+k: String, +v: String, m: +List<KV>) -> +List<KV>:
  ?TODO

# Go delete(m, k).
def Meta.delete(+k: String, m: +List<KV>) -> +List<KV>:
  ?TODO

# The map of a list of pairs; the first pair of a key wins.
def Meta.from_list(xs: +List<KV>) -> +List<KV>:
  ?TODO

# Every entry of a, and the entries of b whose key a lacks.
def Meta.union(a: +List<KV>, b: +List<KV>) -> +List<KV>:
  ?TODO

# The canonical form: keys strictly increasing.
def Meta.canon(m: +List<KV>) -> Bool:
  ?TODO

def Meta.sorted(xs: +List<String>) -> Bool:
  ?TODO

# True when a and b give the same value for every key of either.
def Meta.agree(+a: +List<KV>, +b: +List<KV>) -> Bool:
  ?TODO

# Filters.

# ApplyMaps.

# The keys ApplyMaps manages: the keys of `from` that are not excluded, sorted.
def Meta.managed_keys(from: +List<KV>, exclude: +List<String>) -> +List<String>:
  ?TODO

# vcluster ApplyMaps(fromMap, toMap, {ManagedKeys, ExcludeKeys}): the merged
# map and the managed keys joined by "\n". The `from` and `to` parts are
# independent.
def Meta.apply_maps(+from: +List<KV>, to: +List<KV>, managed: +List<String>, +exclude: +List<String>) -> +List<KV> & String:
  ?TODO

# vcluster applyAnnotations.
def Meta.apply_annotations(from: +List<KV>, +to: +List<KV>, exclude: +List<String>) -> +List<KV>:
  ?TODO

# vcluster applyLabels: the merged labels and the updated annotations.
def Meta.apply_labels(from: +List<KV>, to: +List<KV>, +to_annotations: +List<KV>) -> +List<KV> & +List<KV>:
  ?TODO

# vcluster ApplyMetadata: (labels, annotations).
def Meta.apply_metadata(from_annotations: +List<KV>, to_annotations: +List<KV>, from_labels: +List<KV>, to_labels: +List<KV>, exclude: +List<String>) -> +List<KV> & +List<KV>:
  ?TODO

# Annotations.

# vcluster CopyObjectWithName(obj, {name, namespace}, _, excluded...), as far
# as the metadata goes: the uid and deletion are reset, the name is set, the
# namespace is set for a namespaced object, and the excluded annotations are
# stripped. Owner references are not modelled.
def Meta.copy_object(o: Obj, name: String, namespace: String, excluded: +List<String>) -> Obj:
  ?TODO

# vcluster HostAnnotations(vObj, pObj, excluded...).
def Meta.host_annotations(+v: Obj, +p: Maybe<&2, Obj>, excluded: +List<String>) -> +List<KV>:
  ?TODO

# vcluster VirtualAnnotations(pObj, vObj, excluded...).
def Meta.virtual_annotations(p: Obj, v: Maybe<&2, Obj>, excluded: +List<String>) -> +List<KV>:
  ?TODO

# Labels.

def Meta.vc_prefix() -> String:
  "vcluster.loft.sh/"

# True when no key of m starts with "vcluster.loft.sh/".
def Meta.no_vc_keys(m: +List<KV>) -> Bool:
  ?TODO

# vcluster convertLabelKeyWithPrefix(prefix, key).
def Meta.convert(prefix: String, vc: String, key: String) -> String:
  ?TODO

# singleNamespace.LabelsToTranslate, each with its translated key, release
# first. The hashes of the four fixed keys are constants (law
# meta.tkeys_convert checks them against Sha256), so a translation hashes
# nothing unless the key is longer than 63 characters.
def Meta.tkeys(+vc: String) -> +List<KV>:
  ?TODO

# vcluster HostLabel.
def Meta.host_label(vc: String, k: String) -> String:
  ?TODO

# vcluster VirtualLabel: None where Go answers ok == false.
def Meta.virtual_label(vc: String, k: String) -> Maybe<&2, String>:
  ?TODO

# vcluster HostLabelsMap(vLabels, pLabels, vNamespace, isMetadata).
def Meta.host_labels_map(+vc: String, target: String, v: Maybe<&2, List<&2, KV>>, +p: Maybe<&2, List<&2, KV>>, ns: String, is_meta: Bool) -> Maybe<&2, List<&2, KV>>:
  ?TODO

# vcluster VirtualLabelsMap(pLabels, vLabels, excluded...).
#
# Go rewrites retLabels while it ranges over it. This follows the reading
# that TestVirtualLabels needs: each entry present when the loop starts is
# visited once, and a key that an entry translates back to wins over the
# value the loop kept for that key (Go's order is random there; it only
# matters when a host map holds a translated key and its original at once).
def Meta.virtual_labels_map(vc: String, p: Maybe<&2, List<&2, KV>>, +v: +List<KV>, excluded: +List<String>) -> Maybe<&2, List<&2, KV>>:
  ?TODO

# Label selectors.

# vcluster HostLabelSelector. When two keys meet on one host key, the first
# (smallest) virtual key wins; Go's choice there is random.
def Meta.host_label_selector(vc: String, s: Maybe<&2, Sel>) -> Maybe<&2, Sel>:
  ?TODO

# vcluster VirtualLabelSelector.
def Meta.virtual_label_selector(vc: String, s: Maybe<&2, Sel>) -> Maybe<&2, Sel>:
  ?TODO

# Predicates.

# vcluster ShouldDeleteHostObject.
def Meta.should_delete_host_object(p: Obj) -> Bool:
  ?TODO

# vcluster singleNamespace.IsManaged. `expected` is the host name that the
# mappings store gives the object's name and namespace annotations
# (mappings.VirtualToHostName), or None when there is no mapping for the
# kind (ctx.Mappings nil or without the GVK).
def Meta.is_managed(vc: String, target: String, expected: Maybe<&2, String>, p: Obj) -> Bool:
  ?TODO

# Bidirectional annotation sync.

# vcluster AnnotationsBidirectionalUpdate(event, excluded...), with the event
# NewSyncEventWithOld(hostOld, host, virtualOld, virtual). The result is
# (new virtual annotations, new host annotations).
def Meta.annotations_bidirectional_update(host_old: Obj, +host: Obj, virtual_old: Obj, +virtual: Obj, excluded: +List<String>) -> +List<KV> & +List<KV>:
  ?TODO
