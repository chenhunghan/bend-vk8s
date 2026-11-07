import Base
import ../src/sync/mappings.bend as M
import bend-kube-runtime@0.2.0.0/src/json.bend as J

# Tests for src/sync/mappings.bend. The laws in laws/mappings.bend transcribe
# vcluster's own tests; these cover the rest of pkg/mappings: the configmap
# mapper's kube-root-ca.crt names, the single-namespace namespace mapper, the
# secret and configmap scans of pods and ingresses, isConfigMapUsed /
# isSecretUsed, store verification, createMapping, backend events, the
# configmap and secret migrations, and the string helpers. Expected values
# follow vcluster's Go code (VClusterName "suffix"); the HostNameShort value
# was computed with Go's algorithm (SHA-256, base36.EncodeBytes) outside Bend.

def report(name: String, got: String, want: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name ++ ": got " ++ got ++ ", want " ++ want)

def check(name: String, +got: String, +want: String) -> IO(Unit):
  report(name, got, want, String.eq(got, want))

def show_bool(b: Bool) -> String:
  match b:
    case True{}:
      "true"
    case False{}:
      "false"

def show_nns(xs: List<&2, M.NN>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, t}:
      M.NN.show(x) ++ "," ++ show_nns(t)

def show_strs(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, t}:
      x ++ "," ++ show_strs(t)

def show_maybe(m: Maybe<&2, M.NN>) -> String:
  match m:
    case None{}:
      "none"
    case Some{x}:
      M.NN.show(x)

def show_res(r: M.Res) -> String:
  match r:
    case M.Ok{s}:
      "ok " ++ Nat.show(M.Store.size(s))
    case M.Err{e}:
      "err " ++ e

def json(s: String) -> J.Json:
  Result.default(&2, &2, String, J.Json, J.Json.parse(s), J.JNull{})

def store(r: M.Res) -> M.Store:
  match r:
    case M.Ok{s}:
      s
    case M.Err{e}:
      M.Store.new(None{})

def ctx(target: String) -> M.Ctx:
  M.Ctx{target, "suffix", None{}, Some{[]}, False{}, False{}}

def fst(p: M.NN & M.Store) -> M.NN:
  (n, s) = p
  n

def snd(p: M.NN & M.Store) -> M.Store:
  (n, s) = p
  s

def secret() -> String:
  "/v1, Kind=Secret"

def pod() -> String:
  "/v1, Kind=Pod"

def cm() -> String:
  "/v1, Kind=ConfigMap"

# The pod default/p synced to host-ns, recorded as its own mapping.
def pod_store() -> M.Store:
  +p = {M.NM{pod(), M.NN{"default", "p"}, M.NN{"host-ns", "p-x-default-x-suffix"}} : M.NM}
  store(M.Store.add_reference(M.Store.new(None{}), p, p))

def pod_json() -> J.Json:
  json("{\"metadata\":{\"name\":\"p\",\"namespace\":\"default\"},\"spec\":{\"containers\":[{\"name\":\"c\",\"envFrom\":[{\"configMapRef\":{\"name\":\"cfg\"}}]}]}}")

def big_pod() -> J.Json:
  json("{\"metadata\":{\"name\":\"pod\",\"namespace\":\"test\"},\"spec\":{\"containers\":[{\"name\":\"c\",\"env\":[{\"name\":\"a\",\"valueFrom\":{\"secretKeyRef\":{\"name\":\"\"}}},{\"name\":\"b\",\"valueFrom\":{\"configMapKeyRef\":{\"name\":\"c1\"}}}]}],\"initContainers\":[{\"name\":\"i\",\"envFrom\":[{\"secretRef\":{\"name\":\"e1\"}},{\"configMapRef\":{\"name\":\"c2\"}}]}],\"ephemeralContainers\":[{\"name\":\"e\",\"env\":[{\"name\":\"x\",\"valueFrom\":{\"secretKeyRef\":{\"name\":\"e2\"}}}]}],\"imagePullSecrets\":[{\"name\":\"pull\"}],\"volumes\":[{\"name\":\"v0\",\"secret\":{}},{\"name\":\"v1\",\"projected\":{\"sources\":[{\"secret\":{\"name\":\"ps\"}},{\"serviceAccountToken\":{\"path\":\"t\"}},{\"configMap\":{\"name\":\"c3\"}}]}},{\"name\":\"v2\",\"iscsi\":{\"secretRef\":{\"name\":\"is\"}}},{\"name\":\"v3\",\"azureFile\":{\"secretName\":\"\"}},{\"name\":\"v4\",\"csi\":{\"nodePublishSecretRef\":{\"name\":\"csi\"}}},{\"name\":\"v5\",\"configMap\":{\"name\":\"c4\"}}]}}")

def main() -> IO(Unit):
  do IO<Unit>:
    # HostName, HostNameShort (single_namespace.go).
    check("host name short", M.NN.show(M.Tr.host_name_short("test", "suffix", M.NN{"test", "test"})), "test/v2po30bbi7atc1")
    check("host name short of empty name", M.NN.show(M.Tr.host_name_short("test", "suffix", M.NN{"test", ""})), "/")
    check("host name of a cluster-scoped name", M.NN.show(M.Tr.host_name("test", "suffix", M.NN{"", "n"})), "/n-x--x-suffix")
    check("base36 of 256", M.B36.encode([1, 0]), "74")
    check("base36 keeps leading zero bytes", M.B36.encode([0, 0, 1]), "001")
    check("base36 of zero", M.B36.encode([0]), "0")
    # Strings.
    check("short names", show_strs(M.Short.all("x-v0123456789abcd-y-vABCDEFGHIJKLM")), "v0123456789abc,")
    check("replace all", M.Str.replace("aXbXc", "X", "--"), "a--b--c")
    check("replace empty", M.Str.replace("abc", "", ""), "abc")
    # configMapsMapper (configmaps.go).
    check("kube-root-ca.crt host name", M.ConfigMaps.root_ca_host("suffix"), "vcluster-kube-root-ca.crt-x-suffix")
    check("virtual kube-root-ca.crt gets HostName", M.NN.show(M.ConfigMaps.virtual_to_host(ctx("test"), M.NN{"default", "kube-root-ca.crt"})), "test/kube-root-ca.crt-x-default-x-suffix")
    check("host kube-root-ca.crt is ignored", M.NN.show(M.ConfigMaps.host_to_virtual(ctx("test"), M.Store.new(None{}), M.NN{"test", "kube-root-ca.crt"}, None{})), "/")
    check("special name translates back",
      M.NN.show(M.ConfigMaps.host_to_virtual(ctx("test"), M.Store.new(None{}), M.NN{"test", "vcluster-kube-root-ca.crt-x-suffix"},
        Some{json("{\"metadata\":{\"name\":\"vcluster-kube-root-ca.crt-x-suffix\",\"namespace\":\"test\",\"annotations\":{\"vcluster.loft.sh/object-name\":\"kube-root-ca.crt\",\"vcluster.loft.sh/object-namespace\":\"default\"}}}")})),
      "default/kube-root-ca.crt")
    check("host object outside the target namespace", M.NN.show(M.ConfigMaps.host_to_virtual(ctx("test"), M.Store.new(None{}), M.NN{"other", "x"},
        Some{json("{\"metadata\":{\"name\":\"x\",\"namespace\":\"other\",\"annotations\":{\"vcluster.loft.sh/object-name\":\"a\",\"vcluster.loft.sh/object-namespace\":\"default\"}}}")})), "/")
    # singleNamespaceModeMapper (namespaces.go).
    check("namespace maps to the target", M.NN.show(M.Namespaces.virtual_to_host("test", M.NN{"", "default"})), "/test")
    check("empty namespace", M.NN.show(M.Namespaces.virtual_to_host("test", M.NN{"", ""})), "/")
    check("host namespace has no virtual name", M.NN.show(M.Namespaces.host_to_virtual(M.NN{"", "test"})), "/")
    check("host namespace not managed", show_bool(M.Namespaces.is_managed(json("{}"))), "false")
    # TryToTranslateBackByAnnotations: marker labels.
    check("marker of another vcluster", M.NN.show(M.Mapper.by_annotations("test", "suffix", secret(),
      Some{json("{\"metadata\":{\"name\":\"h\",\"namespace\":\"test\",\"labels\":{\"vcluster.loft.sh/managed-by\":\"other\"},\"annotations\":{\"vcluster.loft.sh/object-name\":\"a\",\"vcluster.loft.sh/object-namespace\":\"b\"}}}")})), "/")
    check("cluster-scoped marker", M.NN.show(M.Mapper.by_annotations("test", "suffix", "storage.k8s.io/v1, Kind=StorageClass",
      Some{json("{\"metadata\":{\"name\":\"h\",\"labels\":{\"vcluster.loft.sh/managed-by\":\"test-x-suffix\"},\"annotations\":{\"vcluster.loft.sh/object-name\":\"a\"}}}")})), "/a")
    # IsManaged with a registry: the host name must match the name annotations.
    check("managed with matching name", show_bool(M.Mapper.is_managed(M.Ctx{"test", "suffix", None{}, Some{[secret()]}, False{}, False{}}, M.Store.new(None{}), secret(),
      json("{\"metadata\":{\"name\":\"a-x-default-x-suffix\",\"namespace\":\"test\",\"labels\":{\"vcluster.loft.sh/managed-by\":\"suffix\"},\"annotations\":{\"vcluster.loft.sh/object-name\":\"a\",\"vcluster.loft.sh/object-namespace\":\"default\"}}}"))), "true")
    check("not managed with another name", show_bool(M.Mapper.is_managed(M.Ctx{"test", "suffix", None{}, Some{[secret()]}, False{}, False{}}, M.Store.new(None{}), secret(),
      json("{\"metadata\":{\"name\":\"other\",\"namespace\":\"test\",\"labels\":{\"vcluster.loft.sh/managed-by\":\"suffix\"},\"annotations\":{\"vcluster.loft.sh/object-name\":\"a\",\"vcluster.loft.sh/object-namespace\":\"default\"}}}"))), "false")
    # secretNamesFromPod / configMapsFromPod over every source.
    check("secrets from pod", show_nns(M.Secrets.from_pod(Some{M.NN{"test", "pod-sa-token-host"}}, big_pod())), "test/e1,test/e2,test/pull,test/,test/ps,test/pod-sa-token-host,test/is,test/csi,")
    check("secrets from pod without SA token secrets", show_nns(M.Secrets.from_pod(None{}, big_pod())), "test/e1,test/e2,test/pull,test/,test/ps,test/is,test/csi,")
    check("configmaps from pod", show_nns(M.ConfigMaps.from_pod(big_pod())), "test/c1,test/c2,test/c3,test/c4,")
    check("SA token secret name", M.NN.show(M.Secrets.sa_token_name(big_pod())), "test/pod-sa-token")
    check("secrets from ingress annotations", show_nns(M.Secrets.from_ingress(json("{\"metadata\":{\"name\":\"i\",\"namespace\":\"test\",\"annotations\":{\"nginx.ingress.kubernetes.io/auth-secret\":\"s1\",\"x\":\"y\",\"nginx.ingress.kubernetes.io/auth-tls-secret\":\"other/s2\",\"nginx.ingress.kubernetes.io/proxy-ssl-secret\":\"a/b/c\"}},\"spec\":{\"tls\":[{\"secretName\":\"c\"},{\"hosts\":[\"h\"]}]}}"))), "test/s1,other/s2,test/c,")
    # isConfigMapUsed / isSecretUsed.
    check("forced configmap is used", show_bool(M.ConfigMaps.used(json("{\"metadata\":{\"name\":\"c\",\"namespace\":\"default\",\"annotations\":{\"vcluster.loft.sh/force-sync\":\"true\"}}}"), False{}, M.Store.new(None{}))), "true")
    check("all configmaps are used", show_bool(M.ConfigMaps.used(json("{\"metadata\":{\"name\":\"c\",\"namespace\":\"default\"}}"), True{}, M.Store.new(None{}))), "true")
    check("unreferenced secret is unused", show_bool(M.Secrets.used(json("{\"metadata\":{\"name\":\"s\",\"namespace\":\"default\"}}"), False{}, M.Store.new(None{}))), "false")
    check("referenced configmap is used", show_bool(M.ConfigMaps.used(json("{\"metadata\":{\"name\":\"cfg\",\"namespace\":\"default\"}}"), False{}, M.ConfigMaps.migrate([pod_json()], ctx("host-ns"), pod_store()))), "true")
    # The configmap migration records pod references.
    check("migrated configmap host name", show_maybe(M.Store.virtual_to_host(M.ConfigMaps.migrate([pod_json()], ctx("host-ns"), pod_store()), cm(), M.NN{"default", "cfg"})), "host-ns/cfg-x-default-x-suffix")
    check("no pod mapping, no reference", show_maybe(M.Store.virtual_to_host(M.ConfigMaps.migrate([pod_json()], ctx("host-ns"), M.Store.new(None{})), cm(), M.NN{"default", "cfg"})), "none")
    # Ingress secrets record under a Pod-kind owner of the ingress's name.
    check("ingress secret with a pod of that name", Nat.show(List.length(&2, M.NM, M.Store.references_to(M.Secrets.migrate([], False{}, True{}, [json("{\"metadata\":{\"name\":\"p\",\"namespace\":\"default\"},\"spec\":{\"tls\":[{\"secretName\":\"t\"}]}}")], ctx("host-ns"), pod_store()), secret(), M.NN{"default", "t"}))), "1")
    check("ingress secrets off", Nat.show(List.length(&2, M.NM, M.Store.references_to(M.Secrets.migrate([], False{}, False{}, [json("{\"metadata\":{\"name\":\"p\",\"namespace\":\"default\"},\"spec\":{\"tls\":[{\"secretName\":\"t\"}]}}")], ctx("host-ns"), pod_store()), secret(), M.NN{"default", "t"}))), "0")
    # Verification (verify.NewVerifyMapping) with target namespace "test".
    check("host outside the target is not recorded", show_res(M.Store.add_reference(M.Store.new(Some{"test"}), M.NM{secret(), M.NN{"default", "a"}, M.NN{"other", "a"}}, M.NM{secret(), M.NN{"default", "a"}, M.NN{"other", "a"}})), "ok 0")
    check("host in the target is recorded", show_res(M.Store.add_reference(M.Store.new(Some{"test"}), M.NM{secret(), M.NN{"default", "a"}, M.NN{"test", "a"}}, M.NM{secret(), M.NN{"default", "a"}, M.NN{"test", "a"}})), "ok 1")
    check("host namespace must be the target", show_res(M.Store.add_reference(M.Store.new(Some{"test"}), M.NM{"/v1, Kind=Namespace", M.NN{"", "default"}, M.NN{"", "other"}}, M.NM{"/v1, Kind=Namespace", M.NN{"", "default"}, M.NN{"", "other"}})), "ok 0")
    check("unverified event is ignored", Nat.show(M.Store.size(M.Store.apply(M.Store.new(Some{"test"}), M.Upd{M.Mapping{M.NM{secret(), M.NN{"default", "a"}, M.NN{"other", "a"}}, []}}))), "0")
    # createMapping: an owner missing from the store becomes a mapping without
    # the reference; the next record adds it.
    check("owner created without the reference", Nat.show(List.length(&2, M.NM, M.Store.references_to(store(M.Store.add_reference(M.Store.new(None{}), M.NM{secret(), M.NN{"default", "s"}, M.NN{"test", "s"}}, M.NM{pod(), M.NN{"default", "p"}, M.NN{"test", "p"}})), secret(), M.NN{"default", "s"}))), "0")
    check("second record adds the reference", Nat.show(List.length(&2, M.NM, M.Store.references_to(store(M.Store.add_reference(store(M.Store.add_reference(M.Store.new(None{}), M.NM{secret(), M.NN{"default", "s"}, M.NN{"test", "s"}}, M.NM{pod(), M.NN{"default", "p"}, M.NN{"test", "p"}})), M.NM{secret(), M.NN{"default", "s"}, M.NN{"test", "s"}}, M.NM{pod(), M.NN{"default", "p"}, M.NN{"test", "p"}})), secret(), M.NN{"default", "s"}))), "1")
    check("incomplete name is not recorded", show_res(M.Store.add_reference(M.Store.new(None{}), M.NM{secret(), M.NN{"default", "s"}, M.NN{"test", ""}}, M.NM{secret(), M.NN{"default", "s"}, M.NN{"test", ""}})), "ok 0")
    # The recorder records under the owner in the context.
    check("recorded reference",
      show_maybe(M.Store.virtual_to_host(snd(M.MKind.rec_virtual_to_host(M.KGeneric{}, M.Ctx{"host-ns", "suffix", Some{M.NM{pod(), M.NN{"default", "p"}, M.NN.empty()}}, Some{[]}, False{}, False{}}, pod_store(), secret(), M.NN{"default", "s"})), secret(), M.NN{"default", "s"})),
      "host-ns/s-x-default-x-suffix")
    check("recorder answer",
      M.NN.show(fst(M.MKind.rec_virtual_to_host(M.KGeneric{}, M.Ctx{"host-ns", "suffix", Some{M.NM{pod(), M.NN{"default", "p"}, M.NN.empty()}}, Some{[]}, False{}, False{}}, pod_store(), secret(), M.NN{"default", "s"}))),
      "host-ns/s-x-default-x-suffix")
    check("no registry, no store", show_maybe(M.Store.virtual_to_host(snd(M.MKind.rec_virtual_to_host(M.KGeneric{}, M.Ctx{"host-ns", "suffix", Some{M.NM{pod(), M.NN{"default", "p"}, M.NN.empty()}}, None{}, False{}, False{}}, pod_store(), secret(), M.NN{"default", "s"})), secret(), M.NN{"default", "s"})), "none")
    # DeleteReference drops the lookup.
    check("deleted reference", show_maybe(M.Store.virtual_to_host(M.Store.delete_reference(snd(M.MKind.rec_virtual_to_host(M.KGeneric{}, M.Ctx{"host-ns", "suffix", Some{M.NM{pod(), M.NN{"default", "p"}, M.NN.empty()}}, Some{[]}, False{}, False{}}, pod_store(), secret(), M.NN{"default", "s"})), M.NM{secret(), M.NN{"default", "s"}, M.NN{"host-ns", "s-x-default-x-suffix"}}, M.NM{pod(), M.NN{"default", "p"}, M.NN.empty()}), secret(), M.NN{"default", "s"})), "none")
    # Virtual objects migrate with the mapper's host name.
    check("virtual migration", show_maybe(M.Store.host_to_virtual(M.Rec.migrate(M.KGeneric{}, ctx("host-ns"), M.Store.new(None{}), secret(), [], [M.NN{"default", "s"}]), secret(), M.NN{"host-ns", "s-x-default-x-suffix"})), "default/s")
