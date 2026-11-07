import Base
import ../src/translate/names.bend as N

# Tests for src/translate/names.bend. Expected values follow vcluster
# pkg/util/translate SafeConcatName and single_namespace.go.

def report(name: String, got: String, want: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name ++ ": got " ++ got ++ ", want " ++ want)

def check(name: String, +got: String, +want: String) -> IO(Unit):
  report(name, got, want, String.eq(got, want))

def main() -> IO(Unit):
  do IO<Unit>:
    check("short joins", N.Names.host_name("nginx", "default", "my-vcluster"),
      "nginx-x-default-x-my-vcluster")
    check("empty name stays empty", N.Names.host_name("", "default", "my-vcluster"), "")
    check("long name is hashed",
      N.Names.host_name("a-very-long-deployment-name-0123456789-abcdef", "some-long-namespace-name", "vcluster"),
      "a-very-long-deployment-name-0123456789-abcdef-x-some-9eb53ab8ff")
    check("dot dash collapses",
      N.Names.safe_concat(["name.with.dots.and.it.is.quite.long.for.a.label.yes.long.enough-x"]),
      "name.with.dots.and.it.is.quite.long.for.a.label.yes-8f49fc3eb7")
    check("cluster scoped", N.Names.host_name_cluster("standard", "vcluster-ns", "vcluster"),
      "vcluster-standard-x-vcluster-ns-x-vcluster")
    check("cluster scoped empty", N.Names.host_name_cluster("", "vcluster-ns", "vcluster"), "")
    check("marker cluster", N.Names.marker_cluster("vcluster-ns", "vcluster"),
      "vcluster-ns-x-vcluster")
    check("root ca", N.Names.safe_concat(["vcluster", "kube-root-ca.crt", "x", "vcluster"]),
      "vcluster-kube-root-ca.crt-x-vcluster")
    check("63 chars kept", N.Names.safe_concat([String.repeat("a", 63n)]),
      String.repeat("a", 63n))
    check("64 chars hashed", N.Names.safe_concat([String.repeat("a", 64n)]),
      String.repeat("a", 52n) ++ "-ffe054fe7a")
    check("dot at cut point",
      N.Names.safe_concat(["abcdefghijabcdefghijabcdefghijabcdefghijabcdefghija.", "bbbbbbbbbbbbbbbbbbbb"]),
      "abcdefghijabcdefghijabcdefghijabcdefghijabcdefghija-3534513d01")
    check("replace is one pass",
      N.Names.safe_concat([String.repeat("x..-y", 20n)]),
      "x.-yx.-yx.-yx.-yx.-yx.-yx.-yx.-yx.-yx.-yx-9db02455b1")
    check("no parts", N.Names.safe_concat([]), "")
    check("one empty part", N.Names.safe_concat([""]), "")
