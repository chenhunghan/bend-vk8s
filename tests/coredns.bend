import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/guest/coredns.bend as C

# Scenario tests for src/guest/coredns.bend: the template branches the
# vcluster tests do not reach, the vk8s config record, and toYaml.
# Each line prints PASS or FAIL.

def T.line(+name: String, ok: Bool) -> String:
  match ok:
    case True{}:
      "PASS " ++ name
    case False{}:
      "FAIL " ++ name

def T.has(+name: String, +out: String, +part: String) -> String:
  T.line(name, String.contains(out, part))

def T.lacks(+name: String, +out: String, +part: String) -> String:
  T.line(name, Bool.not(String.contains(out, part)))

def T.eq(+name: String, +got: String, +want: String) -> String:
  T.line(name, String.eq(got, want))

def T.with(path: List<&2, String>, v: J.Json) -> J.Json:
  C.Coredns.put(path, C.Coredns.vcluster_defaults(), v)

def T.no_vars() -> C.Vars:
  C.Vars{"", "", "", ""}

def T.yaml(+name: String, +s: String, +want: String) -> String:
  T.eq(name, C.Coredns.to_yaml(J.JStr{s}), want)

def main() -> IO(Unit):
  do IO<Unit>:
    +dm : String = C.Coredns.default_manifest()
    +custom : String = C.Coredns.render(C.Cfg{"corp.example", "10.43.0.10", "registry.local/coredns:1.14.2", 3, 65532, 65532})
    +fallback : String = C.Coredns.corefile(T.with(["networking", "advanced", "fallbackHostCluster"], J.JBool{True{}}),
      C.Vars{"", "", "", "10.0.0.2"})
    +netpol : String = C.Coredns.corefile(T.with(["policies", "networkPolicy", "enabled"], J.JBool{True{}}), T.no_vars())
    +resolve : String = C.Coredns.corefile(C.Coredns.put(["networking", "resolveDNS"],
      T.with(["controlPlane", "coredns", "embedded"], J.JBool{True{}}),
      J.Json.arr([J.Json.obj([J.KV{"hostname", J.JStr{"a"}}])])), T.no_vars())
    +registry : String = C.Coredns.manifests(C.Coredns.put(["controlPlane", "advanced", "defaultImageRegistry"],
      T.with(["controlPlane", "coredns", "deployment", "image"], J.JStr{"coredns/coredns:x"}), J.JStr{"my.reg"}),
      C.Vars{"ignored", "1", "1", ""})
    +selector : String = C.Coredns.manifests(T.with(["controlPlane", "coredns", "service", "spec"],
      J.Json.obj([J.KV{"type", J.JStr{"ClusterIP"}}, J.KV{"selector", J.Json.obj([J.KV{"app", J.JStr{"x"}}])}])),
      T.no_vars())
    IO.print(T.lacks("default: no rewrite rule", dm, "rewrite name regex"))
    IO.print(T.has("default: seccomp from the pod security standard", dm, "seccompProfile:\n          type: RuntimeDefault"))
    IO.print(T.has("default: kube-dns at 10.96.0.10", dm, "spec:\n  clusterIP: 10.96.0.10\n  selector:\n"))
    IO.print(T.has("default: NodeHosts in the hosts plugin", dm, "hosts /etc/coredns/NodeHosts {\n            ttl 60\n"))
    IO.print(T.has("custom: domain before cluster.local", custom, "kubernetes corp.example cluster.local in-addr.arpa ip6.arpa {"))
    IO.print(T.has("custom: replicas", custom, "  replicas: 3\n"))
    IO.print(T.has("custom: image", custom, "          image: registry.local/coredns:1.14.2\n"))
    IO.print(T.has("custom: uid", custom, "            runAsUser: 65532\n"))
    IO.print(T.has("custom: service IP", custom, "spec:\n  clusterIP: 10.43.0.10\n  selector:\n    k8s-app: vcluster-kube-dns\n  ports:\n"))
    IO.print(T.has("fallbackHostCluster forwards to the host DNS", fallback, "    forward . 10.0.0.2\n"))
    IO.print(T.has("fallbackHostCluster falls through cluster.local", fallback, "fallthrough cluster.local in-addr.arpa ip6.arpa"))
    IO.print(T.has("network policy adds the fallback DNS", netpol,
      "    forward . /etc/resolv.conf 8.8.8.8 {\n        policy sequential\n    }\n    cache 30"))
    IO.print(T.has("embedded with resolveDNS adds the vcluster plugin", resolve, "    ready\n    vcluster\n    rewrite"))
    IO.print(T.lacks("embedded drops reload", resolve, "    reload\n"))
    IO.print(T.eq("<no value> removed, output trimmed",
      C.Coredns.manifests(C.Coredns.put(["controlPlane", "coredns", "overwriteManifests"], J.JObj{J.JNil{}},
        J.JStr{"  a<no value>b\n"}), T.no_vars()), "ab"))
    IO.print(T.has("deployment.image under the registry", registry, "          image: my.reg/coredns/coredns:x\n"))
    IO.print(T.has("a spec selector replaces the default", selector, "spec:\n  selector:\n    app: x\n  type: ClusterIP\n  ports:\n"))
    IO.print(T.eq("image for 1.36", C.Coredns.image("1", "36", ""), "docker.io/coredns/coredns:1.14.2"))
    IO.print(T.eq("replace all", C.Coredns.replace("a<no value>b<no value>", "<no value>", ""), "ab"))
    IO.print(T.eq("replace adjacent", C.Coredns.replace("xxxx", "xx", "y"), "yy"))
    IO.print(T.eq("indent pads empty lines", C.Coredns.indent("  ", "a\n\nb"), "  a\n  \n  b"))
    IO.print(T.line("0 is false", Bool.not(C.Coredns.truthy(J.JNum{"0"}))))
    IO.print(T.line("0.0 is false", Bool.not(C.Coredns.truthy(J.JNum{"0.0"}))))
    IO.print(T.line("2 is true", C.Coredns.truthy(J.JNum{"2"})))
    IO.print(T.line("{} is false", Bool.not(C.Coredns.truthy(J.JObj{J.JNil{}}))))
    IO.print(T.yaml("yaml bool word quoted", "true", "\"true\""))
    IO.print(T.yaml("yaml empty quoted", "", "\"\""))
    IO.print(T.yaml("yaml float quoted", "1.5", "\"1.5\""))
    IO.print(T.yaml("yaml IP plain", "10.96.0.10", "10.96.0.10"))
    IO.print(T.yaml("yaml date quoted", "2001-12-14", "\"2001-12-14\""))
    IO.print(T.yaml("yaml quantity plain", "1000m", "1000m"))
    IO.print(T.yaml("yaml hex quoted", "0x1F", "\"0x1F\""))
    IO.print(T.yaml("yaml dash quoted", "-", "\"-\""))
    IO.print(T.eq("yaml sorted keys, lists at the key's indentation",
      C.Coredns.to_yaml(J.Json.obj([J.KV{"b", J.JNum{"1"}}, J.KV{"a", J.Json.arr([J.JStr{"x"},
        J.Json.obj([J.KV{"k", J.JStr{"v"}}, J.KV{"c", J.JBool{False{}}}])])}])),
      "a:\n- x\n- c: false\n  k: v\nb: 1"))
    IO.print(T.eq("yaml empty map", C.Coredns.to_yaml(J.JObj{J.JNil{}}), "{}"))
