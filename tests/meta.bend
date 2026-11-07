import Base
import ../src/translate/meta.bend as M

# Tests for src/translate/meta.bend. The laws in laws/meta.bend transcribe
# vcluster's own tests; these cover the rest of pkg/util/translate's
# metadata logic (ShouldDeleteHostObject, IsManaged, match expressions,
# ApplyMaps edge cases, long names). Expected values follow vcluster's Go code
# (VClusterName "suffix" as in its tests); the long-name key was computed with
# Go's SafeConcatName algorithm outside Bend.

def show_kvs(m: +List<M.KV>) -> String:
  match m:
    case Nil{}:
      ""
    case Con{M.KV{k, v}, r}:
      k ++ "=" ++ v ++ ";" ++ show_kvs(r)

def show_map(m: +List<M.KV>) -> String:
  "{" ++ show_kvs(m) ++ "}"

def show_maybe(m: Maybe<&2, List<&2, M.KV>>) -> String:
  match m:
    case None{}:
      "nil"
    case Some{x}:
      show_map(x)

def show_mstr(m: Maybe<&2, String>) -> String:
  match m:
    case None{}:
      "nil"
    case Some{x}:
      x

def show_bool(b: Bool) -> String:
  match b:
    case True{}:
      "true"
    case False{}:
      "false"

def show_strs(xs: +List<String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, r}:
      x ++ "," ++ show_strs(r)

def show_reqs(rs: +List<M.Req>) -> String:
  match rs:
    case Nil{}:
      ""
    case Con{M.Req{key, op, values}, r}:
      key ++ " " ++ op ++ " [" ++ show_strs(values) ++ "];" ++ show_reqs(r)

def show_sel(s: Maybe<&2, M.Sel>) -> String:
  match s:
    case None{}:
      "nil"
    case Some{M.Sel{ml, ex}}:
      show_maybe(ml) ++ " " ++ show_reqs(ex)

def show_pair(p: +List<M.KV> & +List<M.KV>) -> String:
  (a, b) = p
  show_map(a) ++ " " ++ show_map(b)

def show_apply(p: +List<M.KV> & String) -> String:
  (a, b) = p
  show_map(a) ++ " " ++ b

def report(name: String, got: String, want: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name ++ ": got " ++ got ++ ", want " ++ want)

def check(name: String, +got: String, +want: String) -> IO(Unit):
  report(name, got, want, String.eq(got, want))

def obj(name: String, ns: String, kind: String, labels: +List<M.KV>, ann: +List<M.KV>) -> M.Obj:
  M.Obj{name, ns, "", kind, False{}, labels, ann}

def main() -> IO(Unit):
  do IO<Unit>:
    # Maps.
    check("insert keeps order", show_map(M.Meta.insert("b", "2", [M.KV{"a", "1"}, M.KV{"c", "3"}])), "{a=1;b=2;c=3;}")
    check("insert overwrites", show_map(M.Meta.insert("a", "9", [M.KV{"a", "1"}, M.KV{"c", "3"}])), "{a=9;c=3;}")
    check("delete", show_map(M.Meta.delete("a", [M.KV{"a", "1"}, M.KV{"c", "3"}])), "{c=3;}")
    check("delete absent", show_map(M.Meta.delete("b", [M.KV{"a", "1"}, M.KV{"c", "3"}])), "{a=1;c=3;}")
    check("from_list first wins", show_map(M.Meta.from_list([M.KV{"c", "3"}, M.KV{"a", "1"}, M.KV{"c", "9"}])), "{a=1;c=3;}")
    check("lookup absent is empty", M.Meta.lookup("x", [M.KV{"a", "1"}]), "")
    check("byte order", show_map(M.Meta.from_list([M.KV{"b", ""}, M.KV{"B", ""}, M.KV{"a-b", ""}, M.KV{"a", ""}])), "{B=;a=;a-b=;b=;}")
    # ApplyMaps.
    check("apply maps",
      show_apply(M.Meta.apply_maps([M.KV{"a", "1"}, M.KV{"b", "2"}, M.KV{"x", "9"}],
        [M.KV{"b", "20"}, M.KV{"c", "30"}, M.KV{"d", "40"}, M.KV{"x", "90"}], ["c"], ["x"])),
      "{a=1;b=2;d=40;x=90;} a\nb")
    check("apply annotations drops managed",
      show_map(M.Meta.apply_annotations([], [M.KV{"keep", "k"}, M.KV{"old", "v"}, M.KV{"vcluster.loft.sh/managed-annotations", "old"}], [])),
      "{keep=k;}")
    check("apply labels",
      show_pair(M.Meta.apply_labels([M.KV{"app", "web"}], [M.KV{"app", "old"}, M.KV{"legacy", "x"}, M.KV{"tier", "t"}],
        [M.KV{"vcluster.loft.sh/managed-labels", "legacy"}])),
      "{app=web;tier=t;} {vcluster.loft.sh/managed-labels=app;}")
    check("apply metadata",
      show_pair(M.Meta.apply_metadata([M.KV{"a", "1"}], [], [M.KV{"l", "2"}], [], [])),
      "{l=2;} {a=1;vcluster.loft.sh/managed-annotations=a;vcluster.loft.sh/managed-labels=l;}")
    # Annotations.
    check("virtual annotations without virtual object",
      show_map(M.Meta.virtual_annotations(obj("n", "", "", [], [M.KV{"a", "1"}, M.KV{"vcluster.loft.sh/object-name", "n"}]), None{}, [])),
      "{a=1;}")
    check("host annotations without host object",
      show_map(M.Meta.host_annotations(M.Obj{"n", "ns1", "u", "K", False{}, [], [M.KV{"a", "1"}]}, None{}, [])),
      "{a=1;vcluster.loft.sh/managed-annotations=a;vcluster.loft.sh/object-kind=K;vcluster.loft.sh/object-name=n;vcluster.loft.sh/object-namespace=ns1;vcluster.loft.sh/object-uid=u;}")
    check("host annotations host namespace",
      show_map(M.Meta.host_annotations(obj("n", "ns1", "", [], []), Some{obj("h", "tns", "", [], [])}, [])),
      "{vcluster.loft.sh/object-host-name=h;vcluster.loft.sh/object-host-namespace=tns;vcluster.loft.sh/object-name=n;vcluster.loft.sh/object-namespace=ns1;vcluster.loft.sh/object-uid=;}")
    check("bidirectional virtual change",
      show_pair(M.Meta.annotations_bidirectional_update(obj("", "", "", [], [M.KV{"a", "1"}, M.KV{"b", "2"}, M.KV{"h", "9"}]),
        obj("", "", "", [], [M.KV{"a", "1"}, M.KV{"b", "2"}, M.KV{"h", "9"}]),
        obj("", "", "", [], [M.KV{"a", "1"}, M.KV{"b", "2"}]),
        obj("", "", "", [], [M.KV{"a", "1"}, M.KV{"c", "3"}]), [])),
      "{a=1;c=3;} {a=1;c=3;h=9;vcluster.loft.sh/object-host-name=;vcluster.loft.sh/object-name=;vcluster.loft.sh/object-uid=;}")
    check("bidirectional no change",
      show_pair(M.Meta.annotations_bidirectional_update(obj("", "", "", [], [M.KV{"h", "1"}]), obj("", "", "", [], [M.KV{"h", "1"}]),
        obj("", "", "", [], [M.KV{"v", "1"}]), obj("", "", "", [], [M.KV{"v", "1"}]), [])),
      "{v=1;} {h=1;vcluster.loft.sh/object-host-name=;vcluster.loft.sh/object-name=;vcluster.loft.sh/object-uid=;}")
    # Labels.
    check("host label", M.Meta.host_label("suffix", "release"), "vcluster.loft.sh/label-suffix-x-a4d451ec23")
    check("host label plain", M.Meta.host_label("suffix", "app"), "app")
    check("host label controller", M.Meta.host_label("suffix", "vcluster.loft.sh/controlled-by"), "vcluster.loft.sh/label-suffix-x-2080cec00f")
    check("long vcluster name", M.Meta.host_label("a-rather-long-virtual-cluster-name-for-testing-keys", "release"),
      "vcluster.loft.sh/label-a-rather-long-virtual-cluster-de6a064325")
    check("virtual label of release", show_mstr(M.Meta.virtual_label("suffix", "release")), "nil")
    check("virtual label of translated key",
      show_mstr(M.Meta.virtual_label("suffix", "vcluster.loft.sh/label-suffix-x-101dcd4e86")),
      "vcluster.loft.sh/namespace")
    check("host labels map nil", show_maybe(M.Meta.host_labels_map("suffix", "", None{}, None{}, "ns", True{})), "nil")
    check("host labels map cluster scoped",
      show_maybe(M.Meta.host_labels_map("suffix", "", Some{[M.KV{"app", "a"}]}, None{}, "", False{})),
      "{app=a;vcluster.loft.sh/managed-by=-x-suffix;}")
    check("host labels map cluster scoped target",
      show_maybe(M.Meta.host_labels_map("suffix", "tns", Some{[M.KV{"app", "a"}]}, None{}, "", False{})),
      "{app=a;vcluster.loft.sh/managed-by=tns-x-suffix;}")
    check("host labels map keeps controller",
      show_maybe(M.Meta.host_labels_map("suffix", "", Some{[M.KV{"app", "a"}]}, Some{[M.KV{"vcluster.loft.sh/controlled-by", "c1"}]}, "", False{})),
      "{app=a;vcluster.loft.sh/controlled-by=c1;}")
    check("virtual labels map excluded",
      show_maybe(M.Meta.virtual_labels_map("suffix", Some{[M.KV{"a", "1"}, M.KV{"b", "2"}]}, [M.KV{"b", "5"}], ["b"])),
      "{a=1;b=5;}")
    check("virtual labels map namespace labels",
      show_maybe(M.Meta.virtual_labels_map("suffix", Some{[M.KV{"a", "1"}, M.KV{"vcluster.loft.sh/ns-label-suffix-x-0123456789", "y"}]}, [], [])),
      "{a=1;}")
    check("virtual labels map drops markers",
      show_maybe(M.Meta.virtual_labels_map("suffix", Some{[M.KV{"a", "1"}, M.KV{"vcluster.loft.sh/controlled-by", "c"}, M.KV{"vcluster.loft.sh/managed-by", "suffix"}]}, [], [])),
      "{a=1;}")
    # Selectors.
    check("host selector nil", show_sel(M.Meta.host_label_selector("suffix", None{})), "nil")
    check("host selector expressions",
      show_sel(M.Meta.host_label_selector("suffix", Some{M.Sel{None{}, [M.Req{"release", "In", ["a", "b"]}, M.Req{"app", "Exists", []}]}})),
      "nil vcluster.loft.sh/label-suffix-x-a4d451ec23 In [a,b,];app Exists [];")
    check("virtual selector expressions",
      show_sel(M.Meta.virtual_label_selector("suffix", Some{M.Sel{None{}, [M.Req{"vcluster.loft.sh/label-suffix-x-a4d451ec23", "NotIn", ["x"]}, M.Req{"release", "Exists", []}]}})),
      "nil release NotIn [x,];release Exists [];")
    check("host selector empty match labels",
      show_sel(M.Meta.host_label_selector("suffix", Some{M.Sel{Some{[]}, []}})), "{} ")
    # ShouldDeleteHostObject.
    check("delete when deleting",
      show_bool(M.Meta.should_delete_host_object(M.Obj{"h", "", "", "K", True{}, [], []})), "true")
    check("delete synced cluster object",
      show_bool(M.Meta.should_delete_host_object(obj("h", "", "K", [],
        [M.KV{"vcluster.loft.sh/object-host-name", "h"}, M.KV{"vcluster.loft.sh/object-kind", "K"}, M.KV{"vcluster.loft.sh/object-name", "v"}]))), "true")
    check("keep on kind mismatch",
      show_bool(M.Meta.should_delete_host_object(obj("h", "", "K2", [],
        [M.KV{"vcluster.loft.sh/object-host-name", "h"}, M.KV{"vcluster.loft.sh/object-kind", "K"}, M.KV{"vcluster.loft.sh/object-name", "v"}]))), "false")
    check("keep on unknown kind",
      show_bool(M.Meta.should_delete_host_object(obj("h", "", "", [],
        [M.KV{"vcluster.loft.sh/object-host-name", "h"}, M.KV{"vcluster.loft.sh/object-kind", "K"}, M.KV{"vcluster.loft.sh/object-name", "v"}]))), "false")
    check("keep on host name mismatch",
      show_bool(M.Meta.should_delete_host_object(obj("h2", "", "K", [],
        [M.KV{"vcluster.loft.sh/object-host-name", "h"}, M.KV{"vcluster.loft.sh/object-kind", "K"}, M.KV{"vcluster.loft.sh/object-name", "v"}]))), "false")
    check("keep namespaced without namespace annotation",
      show_bool(M.Meta.should_delete_host_object(obj("h", "tns", "K", [],
        [M.KV{"vcluster.loft.sh/object-host-name", "h"}, M.KV{"vcluster.loft.sh/object-host-namespace", "tns"}, M.KV{"vcluster.loft.sh/object-kind", "K"}, M.KV{"vcluster.loft.sh/object-name", "v"}]))), "false")
    check("delete synced namespaced object",
      show_bool(M.Meta.should_delete_host_object(obj("h", "tns", "K", [],
        [M.KV{"vcluster.loft.sh/object-host-name", "h"}, M.KV{"vcluster.loft.sh/object-host-namespace", "tns"}, M.KV{"vcluster.loft.sh/object-kind", "K"}, M.KV{"vcluster.loft.sh/object-name", "v"}, M.KV{"vcluster.loft.sh/object-namespace", "default"}]))), "true")
    # IsManaged.
    check("managed cluster object",
      show_bool(M.Meta.is_managed("suffix", "", None{}, obj("h", "", "K", [M.KV{"vcluster.loft.sh/managed-by", "-x-suffix"}], []))), "true")
    check("unmanaged cluster object",
      show_bool(M.Meta.is_managed("suffix", "", None{}, obj("h", "", "K", [M.KV{"vcluster.loft.sh/managed-by", "suffix"}], []))), "false")
    check("managed namespaced object",
      show_bool(M.Meta.is_managed("suffix", "tns", None{}, obj("h", "tns", "K", [M.KV{"vcluster.loft.sh/managed-by", "suffix"}], [M.KV{"vcluster.loft.sh/object-name", "v"}]))), "true")
    check("other namespace",
      show_bool(M.Meta.is_managed("suffix", "tns", None{}, obj("h", "other", "K", [M.KV{"vcluster.loft.sh/managed-by", "suffix"}], [M.KV{"vcluster.loft.sh/object-name", "v"}]))), "false")
    check("no marker",
      show_bool(M.Meta.is_managed("suffix", "tns", None{}, obj("h", "tns", "K", [], [M.KV{"vcluster.loft.sh/object-name", "v"}]))), "false")
    check("no name annotation",
      show_bool(M.Meta.is_managed("suffix", "tns", None{}, obj("h", "tns", "K", [M.KV{"vcluster.loft.sh/managed-by", "suffix"}], []))), "false")
    check("unknown kind needs no name annotation",
      show_bool(M.Meta.is_managed("suffix", "tns", None{}, obj("h", "tns", "", [M.KV{"vcluster.loft.sh/managed-by", "suffix"}], []))), "true")
    check("expected host name differs",
      show_bool(M.Meta.is_managed("suffix", "tns", Some{"other"}, obj("h", "tns", "K", [M.KV{"vcluster.loft.sh/managed-by", "suffix"}], [M.KV{"vcluster.loft.sh/object-name", "v"}]))), "false")
    check("expected host name matches",
      show_bool(M.Meta.is_managed("suffix", "tns", Some{"h"}, obj("h", "tns", "K", [M.KV{"vcluster.loft.sh/managed-by", "suffix"}], [M.KV{"vcluster.loft.sh/object-name", "v"}]))), "true")
    check("kind annotation differs",
      show_bool(M.Meta.is_managed("suffix", "tns", None{}, obj("h", "tns", "K", [M.KV{"vcluster.loft.sh/managed-by", "suffix"}], [M.KV{"vcluster.loft.sh/object-kind", "K2"}, M.KV{"vcluster.loft.sh/object-name", "v"}]))), "false")
    check("host name annotation differs",
      show_bool(M.Meta.is_managed("suffix", "tns", None{}, obj("h", "tns", "K", [M.KV{"vcluster.loft.sh/managed-by", "suffix"}], [M.KV{"vcluster.loft.sh/object-host-name", "h2"}, M.KV{"vcluster.loft.sh/object-name", "v"}]))), "false")
    check("host namespace annotation differs",
      show_bool(M.Meta.is_managed("suffix", "tns", None{}, obj("h", "tns", "K", [M.KV{"vcluster.loft.sh/managed-by", "suffix"}], [M.KV{"vcluster.loft.sh/object-host-namespace", "x"}, M.KV{"vcluster.loft.sh/object-name", "v"}]))), "false")
