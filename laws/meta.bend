import Base
import ../src/translate/meta.bend as M

# Spec for src/translate/meta.bend (vcluster pkg/util/translate: translate.go,
# labels.go, single_namespace.go, types.go).
#
# The concrete laws transcribe every case of translate_test.go and
# labels_test.go (vcluster a8ab30e). Expected values are the Go tests'
# literals; maps are written in canonical (byte-sorted) key order. vcluster's
# tests run with VClusterName "suffix" and the default translator, whose
# target namespace is "". Kinds are Go gvk.String() of the test objects.

# Test fixtures.

def Laws.meta.obj(kind: String, annotations: +List<M.KV>) -> M.Obj:
  M.Obj{"", "", "", kind, False{}, [], annotations}

def Laws.meta.unwrap(m: Maybe<&2, List<&2, M.KV>>) -> +List<M.KV>:
  match m:
    case None{}:
      []
    case Some{x}:
      x

# TestRecursiveLabelsMap: vMaps[i], where vMaps[0] = {NamespaceLabel: "test"}
# and vMaps[i+1] = HostLabelsMap(vMaps[i], nil, "test-<i>", false).
def Laws.meta.rec(n: Nat) -> +List<M.KV>:
  match n:
    case 0n:
      [M.KV{"vcluster.loft.sh/namespace", "test"}]
    case 1n+i:
      +j = i
      Laws.meta.unwrap(M.Meta.host_labels_map("suffix", "", Some{Laws.meta.rec(j)}, None{}, "test-" ++ Nat.show(j), False{}))

# TestVirtualLabels

law meta.virtual_labels_nil:
  {M.Meta.virtual_labels_map("suffix", None{}, [], []) == None{} : Maybe<&2, List<&2, M.KV>>}

law meta.virtual_labels:
  {M.Meta.virtual_labels_map("suffix", Some{[M.KV{"test", "test"}, M.KV{"test123", "test123"}, M.KV{"vcluster.loft.sh/label-suffix-x-a4d451ec23", "vcluster"}]}, [], [])
    == Some{[M.KV{"release", "vcluster"}, M.KV{"test", "test"}, M.KV{"test123", "test123"}]} : Maybe<&2, List<&2, M.KV>>}

# TestNotRewritingLabels

law meta.not_rewriting_host:
  {M.Meta.host_labels_map("suffix", "", Some{[M.KV{"abc", "abc"}, M.KV{"app", "my-app"}, M.KV{"def", "def"}, M.KV{"hij", "hij"}]}, Some{[M.KV{"abc", "abc"}, M.KV{"app", "my-app"}, M.KV{"def", "def"}, M.KV{"hij", "hij"}]}, "test", False{})
    == Some{[M.KV{"abc", "abc"}, M.KV{"app", "my-app"}, M.KV{"def", "def"}, M.KV{"hij", "hij"}]} : Maybe<&2, List<&2, M.KV>>}

law meta.not_rewriting_virtual:
  {M.Meta.virtual_labels_map("suffix", Some{[M.KV{"abc", "abc"}, M.KV{"app", "my-app"}, M.KV{"def", "def"}, M.KV{"hij", "hij"}]}, [M.KV{"abc", "abc"}, M.KV{"app", "my-app"}, M.KV{"def", "def"}, M.KV{"hij", "hij"}], [])
    == Some{[M.KV{"abc", "abc"}, M.KV{"app", "my-app"}, M.KV{"def", "def"}, M.KV{"hij", "hij"}]} : Maybe<&2, List<&2, M.KV>>}

law meta.not_rewriting_host_metadata:
  {M.Meta.host_labels_map("suffix", "", Some{[M.KV{"abc", "abc"}, M.KV{"app", "my-app"}, M.KV{"def", "def"}, M.KV{"hij", "hij"}]}, Some{[M.KV{"abc", "abc"}, M.KV{"app", "my-app"}, M.KV{"def", "def"}, M.KV{"hij", "hij"}]}, "test", True{})
    == Some{[M.KV{"abc", "abc"}, M.KV{"app", "my-app"}, M.KV{"def", "def"}, M.KV{"hij", "hij"}, M.KV{"vcluster.loft.sh/managed-by", "suffix"}, M.KV{"vcluster.loft.sh/namespace", "test"}]} : Maybe<&2, List<&2, M.KV>>}

# TestAnnotations

law meta.annotations_host:
  {M.Meta.host_annotations(Laws.meta.obj("/v1, Kind=Secret", [M.KV{"test", "test"}]), Some{Laws.meta.obj("/v1, Kind=Secret", [M.KV{"test", "test"}])}, [])
    == [M.KV{"test", "test"}, M.KV{"vcluster.loft.sh/managed-annotations", "test"}, M.KV{"vcluster.loft.sh/object-host-name", ""}, M.KV{"vcluster.loft.sh/object-kind", "/v1, Kind=Secret"}, M.KV{"vcluster.loft.sh/object-name", ""}, M.KV{"vcluster.loft.sh/object-uid", ""}] : +List<M.KV>}

law meta.annotations_virtual:
  {M.Meta.virtual_annotations(Laws.meta.obj("/v1, Kind=Secret", [M.KV{"other", "other"}, M.KV{"test", "test"}, M.KV{"vcluster.loft.sh/managed-annotations", "test"}, M.KV{"vcluster.loft.sh/object-host-name", ""}, M.KV{"vcluster.loft.sh/object-kind", "/v1, Kind=Secret"}, M.KV{"vcluster.loft.sh/object-name", ""}, M.KV{"vcluster.loft.sh/object-uid", ""}]), Some{Laws.meta.obj("/v1, Kind=Secret", [M.KV{"test", "test"}])}, [])
    == [M.KV{"other", "other"}, M.KV{"test", "test"}] : +List<M.KV>}

law meta.annotations_host_again:
  {M.Meta.host_annotations(Laws.meta.obj("/v1, Kind=Secret", [M.KV{"other", "other"}, M.KV{"test", "test"}]), Some{Laws.meta.obj("/v1, Kind=Secret", [M.KV{"other", "other"}, M.KV{"test", "test"}, M.KV{"vcluster.loft.sh/managed-annotations", "test"}, M.KV{"vcluster.loft.sh/object-host-name", ""}, M.KV{"vcluster.loft.sh/object-kind", "/v1, Kind=Secret"}, M.KV{"vcluster.loft.sh/object-name", ""}, M.KV{"vcluster.loft.sh/object-uid", ""}])}, [])
    == [M.KV{"other", "other"}, M.KV{"test", "test"}, M.KV{"vcluster.loft.sh/managed-annotations", "other\ntest"}, M.KV{"vcluster.loft.sh/object-host-name", ""}, M.KV{"vcluster.loft.sh/object-kind", "/v1, Kind=Secret"}, M.KV{"vcluster.loft.sh/object-name", ""}, M.KV{"vcluster.loft.sh/object-uid", ""}] : +List<M.KV>}

# TestRecursiveLabelsMap

law meta.recursive_forward:
  {Laws.meta.rec(11n) == [M.KV{"vcluster.loft.sh/label-suffix-x-101dcd4e86", "test-9"}, M.KV{"vcluster.loft.sh/label-suffix-x-e5f1b28ab2", "suffix"}, M.KV{"vcluster.loft.sh/managed-by", "suffix"}, M.KV{"vcluster.loft.sh/namespace", "test-10"}] : +List<M.KV>}

law meta.recursive_back_10:
  {M.Meta.virtual_labels_map("suffix", Some{Laws.meta.rec(11n)}, Laws.meta.rec(10n), [])
    == Some{Laws.meta.rec(10n)} : Maybe<&2, List<&2, M.KV>>}

law meta.recursive_back_9:
  {M.Meta.virtual_labels_map("suffix", Some{Laws.meta.rec(10n)}, Laws.meta.rec(9n), [])
    == Some{Laws.meta.rec(9n)} : Maybe<&2, List<&2, M.KV>>}

law meta.recursive_back_8:
  {M.Meta.virtual_labels_map("suffix", Some{Laws.meta.rec(9n)}, Laws.meta.rec(8n), [])
    == Some{Laws.meta.rec(8n)} : Maybe<&2, List<&2, M.KV>>}

law meta.recursive_back_7:
  {M.Meta.virtual_labels_map("suffix", Some{Laws.meta.rec(8n)}, Laws.meta.rec(7n), [])
    == Some{Laws.meta.rec(7n)} : Maybe<&2, List<&2, M.KV>>}

law meta.recursive_back_6:
  {M.Meta.virtual_labels_map("suffix", Some{Laws.meta.rec(7n)}, Laws.meta.rec(6n), [])
    == Some{Laws.meta.rec(6n)} : Maybe<&2, List<&2, M.KV>>}

law meta.recursive_back_5:
  {M.Meta.virtual_labels_map("suffix", Some{Laws.meta.rec(6n)}, Laws.meta.rec(5n), [])
    == Some{Laws.meta.rec(5n)} : Maybe<&2, List<&2, M.KV>>}

law meta.recursive_back_4:
  {M.Meta.virtual_labels_map("suffix", Some{Laws.meta.rec(5n)}, Laws.meta.rec(4n), [])
    == Some{Laws.meta.rec(4n)} : Maybe<&2, List<&2, M.KV>>}

law meta.recursive_back_3:
  {M.Meta.virtual_labels_map("suffix", Some{Laws.meta.rec(4n)}, Laws.meta.rec(3n), [])
    == Some{Laws.meta.rec(3n)} : Maybe<&2, List<&2, M.KV>>}

law meta.recursive_back_2:
  {M.Meta.virtual_labels_map("suffix", Some{Laws.meta.rec(3n)}, Laws.meta.rec(2n), [])
    == Some{Laws.meta.rec(2n)} : Maybe<&2, List<&2, M.KV>>}

law meta.recursive_back_1:
  {M.Meta.virtual_labels_map("suffix", Some{Laws.meta.rec(2n)}, Laws.meta.rec(1n), [])
    == Some{Laws.meta.rec(1n)} : Maybe<&2, List<&2, M.KV>>}

law meta.recursive_back_0:
  {M.Meta.virtual_labels_map("suffix", Some{Laws.meta.rec(1n)}, Laws.meta.rec(0n), [])
    == Some{Laws.meta.rec(0n)} : Maybe<&2, List<&2, M.KV>>}

# TestLabelsMap

law meta.labels_map_host:
  {M.Meta.host_labels_map("suffix", "", Some{[M.KV{"release", "vcluster"}, M.KV{"test", "test"}, M.KV{"test123", "test123"}, M.KV{"vcluster.loft.sh/label-suffix-x-a4d451ec23", "vcluster123"}]}, None{}, "test", False{})
    == Some{[M.KV{"test", "test"}, M.KV{"test123", "test123"}, M.KV{"vcluster.loft.sh/label-suffix-x-a4d451ec23", "vcluster"}, M.KV{"vcluster.loft.sh/managed-by", "suffix"}, M.KV{"vcluster.loft.sh/namespace", "test"}]} : Maybe<&2, List<&2, M.KV>>}

law meta.labels_map_virtual:
  {M.Meta.virtual_labels_map("suffix", Some{[M.KV{"other", "other"}, M.KV{"test", "test"}, M.KV{"test123", "test123"}, M.KV{"vcluster.loft.sh/label-suffix-x-a4d451ec23", "vcluster"}, M.KV{"vcluster.loft.sh/managed-by", "suffix"}, M.KV{"vcluster.loft.sh/namespace", "test"}]}, [M.KV{"release", "vcluster"}, M.KV{"test", "test"}, M.KV{"test123", "test123"}, M.KV{"vcluster.loft.sh/label-suffix-x-a4d451ec23", "vcluster123"}], [])
    == Some{[M.KV{"other", "other"}, M.KV{"release", "vcluster"}, M.KV{"test", "test"}, M.KV{"test123", "test123"}, M.KV{"vcluster.loft.sh/label-suffix-x-a4d451ec23", "vcluster123"}]} : Maybe<&2, List<&2, M.KV>>}

law meta.labels_map_host_again:
  {M.Meta.host_labels_map("suffix", "", Some{[M.KV{"other", "other"}, M.KV{"release", "vcluster"}, M.KV{"test", "test"}, M.KV{"test123", "test123"}, M.KV{"vcluster.loft.sh/label-suffix-x-a4d451ec23", "vcluster123"}]}, Some{[M.KV{"other", "other"}, M.KV{"test", "test"}, M.KV{"test123", "test123"}, M.KV{"vcluster.loft.sh/label-suffix-x-a4d451ec23", "vcluster"}, M.KV{"vcluster.loft.sh/managed-by", "suffix"}, M.KV{"vcluster.loft.sh/namespace", "test"}]}, "test", False{})
    == Some{[M.KV{"other", "other"}, M.KV{"test", "test"}, M.KV{"test123", "test123"}, M.KV{"vcluster.loft.sh/label-suffix-x-a4d451ec23", "vcluster"}, M.KV{"vcluster.loft.sh/managed-by", "suffix"}, M.KV{"vcluster.loft.sh/namespace", "test"}]} : Maybe<&2, List<&2, M.KV>>}

law meta.labels_map_host_deleted:
  {M.Meta.host_labels_map("suffix", "", Some{[M.KV{"release", "vcluster"}, M.KV{"test", "test"}, M.KV{"test123", "test123"}, M.KV{"vcluster.loft.sh/label-suffix-x-a4d451ec23", "vcluster123"}]}, Some{[M.KV{"other", "other"}, M.KV{"test", "test"}, M.KV{"test123", "test123"}, M.KV{"vcluster.loft.sh/label-suffix-x-a4d451ec23", "vcluster"}, M.KV{"vcluster.loft.sh/managed-by", "suffix"}, M.KV{"vcluster.loft.sh/namespace", "test"}]}, "test", False{})
    == Some{[M.KV{"test", "test"}, M.KV{"test123", "test123"}, M.KV{"vcluster.loft.sh/label-suffix-x-a4d451ec23", "vcluster"}, M.KV{"vcluster.loft.sh/managed-by", "suffix"}, M.KV{"vcluster.loft.sh/namespace", "test"}]} : Maybe<&2, List<&2, M.KV>>}

# TestLabelSelector

law meta.label_selector_host:
  {M.Meta.host_label_selector("suffix", Some{M.Sel{Some{[M.KV{"release", "vcluster"}, M.KV{"test", "test"}, M.KV{"test123", "test123"}]}, []}})
    == Some{M.Sel{Some{[M.KV{"test", "test"}, M.KV{"test123", "test123"}, M.KV{"vcluster.loft.sh/label-suffix-x-a4d451ec23", "vcluster"}]}, []}} : Maybe<&2, M.Sel>}

law meta.label_selector_virtual:
  {M.Meta.virtual_label_selector("suffix", Some{M.Sel{Some{[M.KV{"test", "test"}, M.KV{"test123", "test123"}, M.KV{"vcluster.loft.sh/label-suffix-x-a4d451ec23", "vcluster"}]}, []}})
    == Some{M.Sel{Some{[M.KV{"release", "vcluster"}, M.KV{"test", "test"}, M.KV{"test123", "test123"}]}, []}} : Maybe<&2, M.Sel>}

law meta.label_selector_host_again:
  {M.Meta.host_label_selector("suffix", Some{M.Sel{Some{[M.KV{"release", "vcluster"}, M.KV{"test", "test"}, M.KV{"test123", "test123"}]}, []}})
    == Some{M.Sel{Some{[M.KV{"test", "test"}, M.KV{"test123", "test123"}, M.KV{"vcluster.loft.sh/label-suffix-x-a4d451ec23", "vcluster"}]}, []}} : Maybe<&2, M.Sel>}

# TestAnnotationsSync

law meta.annotations_sync_excluded:
  {M.Meta.annotations_bidirectional_update(Laws.meta.obj("storage.k8s.io/v1, Kind=StorageClass", [M.KV{"storageclass.kubernetes.io/is-default-class", "my-default"}]), Laws.meta.obj("storage.k8s.io/v1, Kind=StorageClass", [M.KV{"storageclass.kubernetes.io/is-default-class", "my-other"}]), Laws.meta.obj("storage.k8s.io/v1, Kind=StorageClass", [M.KV{"storageclass.kubernetes.io/is-default-class", "my-default"}]), Laws.meta.obj("storage.k8s.io/v1, Kind=StorageClass", [M.KV{"storageclass.kubernetes.io/is-default-class", "my-default"}]), ["storageclass.kubernetes.io/is-default-class"])
    == ([M.KV{"storageclass.kubernetes.io/is-default-class", "my-default"}], [M.KV{"storageclass.kubernetes.io/is-default-class", "my-other"}, M.KV{"vcluster.loft.sh/object-host-name", ""}, M.KV{"vcluster.loft.sh/object-kind", "storage.k8s.io/v1, Kind=StorageClass"}, M.KV{"vcluster.loft.sh/object-name", ""}, M.KV{"vcluster.loft.sh/object-uid", ""}]) : +List<M.KV> & +List<M.KV>}

law meta.annotations_sync:
  {M.Meta.annotations_bidirectional_update(Laws.meta.obj("storage.k8s.io/v1, Kind=StorageClass", [M.KV{"storageclass.kubernetes.io/is-default-class", "my-default"}]), Laws.meta.obj("storage.k8s.io/v1, Kind=StorageClass", [M.KV{"storageclass.kubernetes.io/is-default-class", "my-other"}]), Laws.meta.obj("storage.k8s.io/v1, Kind=StorageClass", [M.KV{"storageclass.kubernetes.io/is-default-class", "my-default"}]), Laws.meta.obj("storage.k8s.io/v1, Kind=StorageClass", [M.KV{"storageclass.kubernetes.io/is-default-class", "my-default"}]), [])
    == ([M.KV{"storageclass.kubernetes.io/is-default-class", "my-other"}], [M.KV{"storageclass.kubernetes.io/is-default-class", "my-other"}, M.KV{"vcluster.loft.sh/object-host-name", ""}, M.KV{"vcluster.loft.sh/object-kind", "storage.k8s.io/v1, Kind=StorageClass"}, M.KV{"vcluster.loft.sh/object-name", ""}, M.KV{"vcluster.loft.sh/object-uid", ""}]) : +List<M.KV> & +List<M.KV>}

law meta.annotations_sync_create_virtual:
  {M.Meta.virtual_annotations(Laws.meta.obj("storage.k8s.io/v1, Kind=StorageClass", [M.KV{"not-excluded", "true"}, M.KV{"storageclass.kubernetes.io/is-default-class", "my-default"}]),
    Some{M.Meta.copy_object(Laws.meta.obj("storage.k8s.io/v1, Kind=StorageClass", [M.KV{"not-excluded", "true"}, M.KV{"storageclass.kubernetes.io/is-default-class", "my-default"}]), "", "", ["storageclass.kubernetes.io/is-default-class"])}, ["storageclass.kubernetes.io/is-default-class"])
    == [M.KV{"not-excluded", "true"}] : +List<M.KV>}

law meta.annotations_sync_create_host:
  {M.Meta.host_annotations(Laws.meta.obj("storage.k8s.io/v1, Kind=StorageClass", [M.KV{"not-excluded", "true"}, M.KV{"storageclass.kubernetes.io/is-default-class", "my-default"}]),
    Some{M.Meta.copy_object(Laws.meta.obj("storage.k8s.io/v1, Kind=StorageClass", [M.KV{"not-excluded", "true"}, M.KV{"storageclass.kubernetes.io/is-default-class", "my-default"}]), "", "", ["storageclass.kubernetes.io/is-default-class"])}, ["storageclass.kubernetes.io/is-default-class"])
    == [M.KV{"not-excluded", "true"}, M.KV{"vcluster.loft.sh/managed-annotations", "not-excluded"}, M.KV{"vcluster.loft.sh/object-host-name", ""}, M.KV{"vcluster.loft.sh/object-kind", "storage.k8s.io/v1, Kind=StorageClass"}, M.KV{"vcluster.loft.sh/object-name", ""}, M.KV{"vcluster.loft.sh/object-uid", ""}] : +List<M.KV>}

# General laws.

# Maps: insert, delete, from_list and union keep the canonical form.

law meta.insert_canon:
  for +k: String
  for +v: String
  for +m: +List<M.KV>
  for +h: {M.Meta.canon(m) == True{} : Bool}
  {M.Meta.canon(M.Meta.insert(k, v, m)) == True{} : Bool}

law meta.delete_canon:
  for +k: String
  for +m: +List<M.KV>
  for +h: {M.Meta.canon(m) == True{} : Bool}
  {M.Meta.canon(M.Meta.delete(k, m)) == True{} : Bool}

law meta.from_list_canon:
  for +xs: +List<M.KV>
  {M.Meta.canon(M.Meta.from_list(xs)) == True{} : Bool}

law meta.union_canon:
  for +a: +List<M.KV>
  for +b: +List<M.KV>
  for +h: {M.Meta.canon(b) == True{} : Bool}
  {M.Meta.canon(M.Meta.union(a, b)) == True{} : Bool}

# Maps: get after insert and delete.

law meta.get_insert_same:
  for +k: String
  for +v: String
  for +m: +List<M.KV>
  {M.Meta.get(k, M.Meta.insert(k, v, m)) == Some{v} : Maybe<&2, String>}

law meta.get_insert_other:
  for +q: String
  for +k: String
  for +v: String
  for +m: +List<M.KV>
  for +h: {String.eq(q, k) == False{} : Bool}
  {M.Meta.get(q, M.Meta.insert(k, v, m)) == M.Meta.get(q, m) : Maybe<&2, String>}

law meta.get_delete_same:
  for +k: String
  for +m: +List<M.KV>
  {M.Meta.get(k, M.Meta.delete(k, m)) == None{} : Maybe<&2, String>}

law meta.get_delete_other:
  for +q: String
  for +k: String
  for +m: +List<M.KV>
  for +h: {String.eq(q, k) == False{} : Bool}
  {M.Meta.get(q, M.Meta.delete(k, m)) == M.Meta.get(q, m) : Maybe<&2, String>}

# Two canonical maps that agree on every key of either are the same list.
law meta.ext:
  for +a: +List<M.KV>
  for +b: +List<M.KV>
  for +ha: {M.Meta.canon(a) == True{} : Bool}
  for +hb: {M.Meta.canon(b) == True{} : Bool}
  for +he: {M.Meta.agree(a, b) == True{} : Bool}
  {a == b : +List<M.KV>}

# ApplyMaps.

# The result is canonical when the target map is.
law meta.apply_maps_canon:
  for +from: +List<M.KV>
  for +to: +List<M.KV>
  for +managed: +List<String>
  for +exclude: +List<String>
  for +h: {M.Meta.canon(to) == True{} : Bool}
  {M.Meta.canon(Pair.fst(List<&2, M.KV>, String, M.Meta.apply_maps(from, to, managed, exclude))) == True{} : Bool}

# An excluded key never comes from the source: its value is the target's.
law meta.apply_maps_excluded:
  for +k: String
  for +from: +List<M.KV>
  for +to: +List<M.KV>
  for +managed: +List<String>
  for +exclude: +List<String>
  for +h: {M.Meta.elem(k, exclude) == True{} : Bool}
  {M.Meta.get(k, Pair.fst(List<&2, M.KV>, String, M.Meta.apply_maps(from, to, managed, exclude))) == M.Meta.get(k, to) : Maybe<&2, String>}

# The managed-keys string joins the managed keys with "\n" ...
law meta.apply_maps_managed_string:
  for +from: +List<M.KV>
  for +to: +List<M.KV>
  for +managed: +List<String>
  for +exclude: +List<String>
  {Pair.snd(List<&2, M.KV>, String, M.Meta.apply_maps(from, to, managed, exclude)) == String.join(M.Meta.managed_keys(from, exclude), "\n") : String}

# ... and those keys are strictly sorted.
law meta.apply_maps_managed_sorted:
  for +from: +List<M.KV>
  for +exclude: +List<String>
  for +h: {M.Meta.canon(from) == True{} : Bool}
  {M.Meta.sorted(M.Meta.managed_keys(from, exclude)) == True{} : Bool}

# Labels: a virtual map without vcluster.loft.sh/ keys survives the trip to
# the host and back, whether the virtual object is new or already has them.
law meta.labels_round_trip:
  for +vc: String
  for +target: String
  for +ns: String
  for +m: +List<M.KV>
  for +hc: {M.Meta.canon(m) == True{} : Bool}
  for +hk: {M.Meta.no_vc_keys(m) == True{} : Bool}
  {M.Meta.virtual_labels_map(vc, M.Meta.host_labels_map(vc, target, Some{m}, None{}, ns, False{}), [], []) == Some{m} : Maybe<&2, List<&2, M.KV>>}

law meta.labels_round_trip_sync:
  for +vc: String
  for +target: String
  for +ns: String
  for +m: +List<M.KV>
  for +hc: {M.Meta.canon(m) == True{} : Bool}
  for +hk: {M.Meta.no_vc_keys(m) == True{} : Bool}
  {M.Meta.virtual_labels_map(vc, M.Meta.host_labels_map(vc, target, Some{m}, None{}, ns, False{}), m, []) == Some{m} : Maybe<&2, List<&2, M.KV>>}

# A host object that is being deleted is always deleted.
law meta.should_delete_deleting:
  for +name: String
  for +namespace: String
  for +uid: String
  for +kind: String
  for +labels: +List<M.KV>
  for +annotations: +List<M.KV>
  {M.Meta.should_delete_host_object(M.Obj{name, namespace, uid, kind, True{}, labels, annotations}) == True{} : Bool}

# The translated keys are vcluster's convertLabelKeyWithPrefix(LabelPrefix, k)
# for each label k that single-namespace mode translates.
law meta.tkeys_convert:
  for +vc: String
  {M.Meta.tkeys(vc) == [M.KV{"release", M.Meta.convert("vcluster.loft.sh/label", vc, "release")},
    M.KV{"vcluster.loft.sh/namespace", M.Meta.convert("vcluster.loft.sh/label", vc, "vcluster.loft.sh/namespace")},
    M.KV{"vcluster.loft.sh/managed-by", M.Meta.convert("vcluster.loft.sh/label", vc, "vcluster.loft.sh/managed-by")},
    M.KV{"vcluster.loft.sh/controlled-by", M.Meta.convert("vcluster.loft.sh/label", vc, "vcluster.loft.sh/controlled-by")}] : +List<M.KV>}

