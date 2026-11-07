import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/translate/services.bend as S
import ../src/translate/configs.bend as C

# Tests for src/translate/configs.bend. The laws in laws/configs.bend
# transcribe vcluster's syncer and mapping tests; these cover the rest:
# kube-root-ca.crt, the force-sync annotation and the all switches, every
# pod and ingress reference kind, the secret type rules, data merges in both
# directions, SyncToVirtual and the service account syncer. Expected values
# follow vcluster's Go code (VClusterName "suffix", target namespace "test",
# as in its tests). Objects print in canonical form.

def cfg() -> S.Cfg:
  S.Cfg{"suffix", "test", "vcluster"}

def unwrap(r: Result<&2, &2, String, J.Json>) -> J.Json:
  match r:
    case Fail{e}:
      J.JStr{"parse error: " ++ e}
    case Done{x}:
      x

def js(s: String) -> J.Json:
  unwrap(J.Json.parse(s))

def show(j: J.Json) -> String:
  J.Json.show(S.Svc.canon(j))

def show_rq(r: S.Requeue) -> String:
  match r:
    case S.NoRequeue{}:
      "done"
    case S.RequeueNow{}:
      "requeue"
    case S.RequeueAfter{s}:
      "after " ++ U32.show(s)

def show_write(w: S.Write) -> String:
  match w:
    case S.HostCreate{o}:
      "host create"
    case S.HostUpdate{o}:
      "host update"
    case S.HostDelete{ns, n}:
      "host delete " ++ ns ++ "/" ++ n
    case S.VirtualCreate{o}:
      "virtual create"
    case S.VirtualUpdate{o}:
      "virtual update"
    case S.VirtualDelete{ns, n}:
      "virtual delete " ++ ns ++ "/" ++ n

def show_writes(ws: List<&2, S.Write>) -> String:
  match ws:
    case Nil{}:
      ""
    case Con{w, r}:
      show_write(w) ++ "; " ++ show_writes(r)

# The writes (kind and target) and the requeue of an outcome.
def show_out(o: S.Outcome) -> String:
  match o:
    case S.Outcome{ws, rq}:
      show_writes(ws) ++ show_rq(rq)

def show_start(s: S.Start) -> String:
  match s:
    case S.Start{True{}, ws, e}:
      "skip; " ++ show_writes(ws) ++ e
    case S.Start{False{}, ws, e}:
      "sync; " ++ show_writes(ws) ++ e

def write_obj(w: S.Write) -> J.Json:
  match w:
    case S.HostCreate{o}:
      o
    case S.HostUpdate{o}:
      o
    case S.HostDelete{ns, n}:
      J.JNull{}
    case S.VirtualCreate{o}:
      o
    case S.VirtualUpdate{o}:
      o
    case S.VirtualDelete{ns, n}:
      J.JNull{}

def first_of(ws: List<&2, S.Write>) -> J.Json:
  match ws:
    case Nil{}:
      J.JNull{}
    case Con{w, r}:
      write_obj(w)

# The object of the first write of an outcome.
def first(o: S.Outcome) -> J.Json:
  match o:
    case S.Outcome{ws, rq}:
      first_of(ws)

def last_of(ws: List<&2, S.Write>, acc: J.Json) -> J.Json:
  match ws:
    case Nil{}:
      acc
    case Con{w, r}:
      last_of(r, write_obj(w))

# The object of the last write of an outcome.
def last(o: S.Outcome) -> J.Json:
  match o:
    case S.Outcome{ws, rq}:
      last_of(ws, J.JNull{})

def show_bool(b: Bool) -> String:
  match b:
    case True{}:
      "true"
    case False{}:
      "false"

def at(+o: J.Json, path: List<&2, String>) -> String:
  show(J.Json.at(o, path))

def sp(a: String, b: String) -> String:
  a ++ " " ++ b

def report(name: String, got: String, want: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name ++ ": got " ++ got ++ ", want " ++ want)

def check(name: String, +got: String, +want: String) -> IO(Unit):
  report(name, got, want, String.eq(got, want))

def show_ref(r: C.Ref) -> String:
  match r:
    case C.Ref{ns, n}:
      ns ++ "/" ++ n

def show_refs(rs: List<&2, C.Ref>) -> String:
  match rs:
    case Nil{}:
      ""
    case Con{r, t}:
      show_ref(r) ++ " " ++ show_refs(t)

def show_pair(p: String & String) -> String:
  (a, b) = p
  a ++ "/" ++ b

def show_strs(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, t}:
      x ++ " " ++ show_strs(t)

def cm(name: String, extra: String) -> J.Json:
  js("{\"metadata\":{\"name\":\"" ++ name ++ "\",\"namespace\":\"test\"" ++ extra ++ "}}")

# The host copy the create step makes of a config map, secret or service
# account, with a host-side change of field k to value x.
def cm_host(v: J.Json, k: String, x: J.Json) -> J.Json:
  S.Svc.put(first(C.Configs.cm_sync_to_host(cfg(), True{}, [], None{}, v)), k, x)

def secret_host(v: J.Json, k: String, x: J.Json) -> J.Json:
  S.Svc.put(first(C.Configs.secret_sync_to_host(cfg(), True{}, [], None{}, v)), k, x)

def sa_host(v: J.Json, k: String, x: J.Json) -> J.Json:
  S.Svc.put(first(C.Configs.sa_sync_to_host(cfg(), None{}, v)), k, x)

def pod_ref(name: String) -> List<&2, C.Ref>:
  [C.Ref{"test", name}]

def main() -> IO(Unit):
  do IO<Unit>:
    check("defaults register config maps and secrets",
      sp(show_strs(C.Configs.syncers(C.Configs.defaults())), show_strs(C.Configs.syncers(C.Opts{True{}, False{}, True{}, False{}, True{}, False{}}))),
      "configmaps secrets  configmaps secrets serviceaccounts ")
    # kube-root-ca.crt (mappings/resources/configmaps.go:35-60): the host
    # name check never fires in single-namespace mode.
    check("kube-root-ca.crt syncs under its plain host name",
      show_pair(C.Configs.cm_host_ref(cfg(), "test", "kube-root-ca.crt")),
      "test/kube-root-ca.crt-x-test-x-suffix")
    check("host kube-root-ca.crt maps to nothing",
      show_pair(C.Configs.cm_virtual_ref(cfg(), js("{\"metadata\":{\"name\":\"kube-root-ca.crt\",\"namespace\":\"test\",\"annotations\":{\"vcluster.loft.sh/object-name\":\"a\",\"vcluster.loft.sh/object-namespace\":\"b\"}}}"))),
      "/")
    check("vcluster-kube-root-ca.crt-x-suffix maps to kube-root-ca.crt",
      show_pair(C.Configs.cm_virtual_ref(cfg(), js("{\"metadata\":{\"name\":\"vcluster-kube-root-ca.crt-x-suffix\",\"namespace\":\"test\",\"annotations\":{\"vcluster.loft.sh/object-name\":\"x\",\"vcluster.loft.sh/object-namespace\":\"ns1\"}}}"))),
      "ns1/kube-root-ca.crt")
    check("other host config maps map by their annotations",
      show_pair(C.Configs.cm_virtual_ref(cfg(), js("{\"metadata\":{\"name\":\"c-x-ns1-x-suffix\",\"namespace\":\"test\",\"annotations\":{\"vcluster.loft.sh/object-name\":\"c\",\"vcluster.loft.sh/object-namespace\":\"ns1\"}}}"))),
      "ns1/c")
    # isConfigMapUsed / isSecretUsed.
    check("force-sync makes a config map used",
      show_out(C.Configs.cm_sync_to_host(cfg(), False{}, [], None{}, cm("c", ",\"annotations\":{\"vcluster.loft.sh/force-sync\":\"true\"}"))),
      "host create; done")
    check("force-sync must be true",
      show_out(C.Configs.cm_sync_to_host(cfg(), False{}, [], None{}, cm("c", ",\"annotations\":{\"vcluster.loft.sh/force-sync\":\"yes\"}"))),
      "done")
    check("configMaps.all makes every config map used",
      show_out(C.Configs.cm_sync_to_host(cfg(), True{}, [], None{}, cm("c", ""))),
      "host create; done")
    check("a reference in another namespace does not count",
      show_out(C.Configs.secret_sync_to_host(cfg(), False{}, [C.Ref{"other", "c"}], None{}, cm("c", ""))),
      "done")
    check("used config map whose host copy went is deleted",
      show_out(C.Configs.cm_sync_to_host(cfg(), False{}, pod_ref("c"), Some{js("{}")}, cm("c", ""))),
      "virtual delete test/c; done")
    check("deleting used secret is deleted",
      show_out(C.Configs.secret_sync_to_host(cfg(), True{}, [], None{}, cm("s", ",\"deletionTimestamp\":\"2026-01-01T00:00:00Z\""))),
      "virtual delete test/s; done")
    check("create copies data, binaryData and immutable",
      show(J.Json.del(first(C.Configs.cm_sync_to_host(cfg(), True{}, [], None{}, js("{\"metadata\":{\"name\":\"c\",\"namespace\":\"test\"},\"data\":{\"a\":\"1\"},\"binaryData\":{\"b\":\"AAE=\"},\"immutable\":true}"))), "metadata")),
      "{\"binaryData\":{\"b\":\"AAE=\"},\"data\":{\"a\":\"1\"},\"immutable\":true}")
    # secrets/to_host_syncer.go:89-91.
    check("service account token secret becomes Opaque",
      at(first(C.Configs.secret_sync_to_host(cfg(), True{}, [], None{}, js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"test\"},\"type\":\"kubernetes.io/service-account-token\",\"data\":{\"token\":\"dA==\"}}"))), ["type"]),
      "\"Opaque\"")
    check("other secret types stay",
      at(first(C.Configs.secret_sync_to_host(cfg(), True{}, [], None{}, js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"test\"},\"type\":\"kubernetes.io/tls\"}"))), ["type"]),
      "\"kubernetes.io/tls\"")
    check("create copies stringData",
      at(first(C.Configs.secret_sync_to_host(cfg(), True{}, [], None{}, js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"test\"},\"stringData\":{\"k\":\"v\"}}"))), ["stringData"]),
      "{\"k\":\"v\"}")
    # Sync: data merges (patcher.MergeBidirectional).
    check("virtual data change merges into the host",
      at(first(C.Configs.cm_sync(cfg(), True{}, [],
        js("{\"data\":{\"a\":\"1\",\"b\":\"2\",\"c\":\"3\"}}"), js("{\"data\":{\"a\":\"1\",\"b\":\"2\",\"c\":\"3\"}}"),
        js("{\"metadata\":{\"name\":\"c\",\"namespace\":\"test\"},\"data\":{\"a\":\"1\",\"b\":\"2\"}}"), js("{\"metadata\":{\"name\":\"c\",\"namespace\":\"test\"},\"data\":{\"a\":\"9\"}}"))), ["data"]),
      "{\"a\":\"9\",\"c\":\"3\"}")
    check("host data change merges into the virtual",
      show_out(C.Configs.cm_sync(cfg(), True{}, [],
        cm_host(js("{\"metadata\":{\"name\":\"c\",\"namespace\":\"test\"},\"data\":{\"a\":\"1\",\"z\":\"0\"}}"), "data", js("{\"a\":\"1\"}")), cm_host(js("{\"metadata\":{\"name\":\"c\",\"namespace\":\"test\"},\"data\":{\"a\":\"1\",\"z\":\"0\"}}"), "data", js("{\"a\":\"1\",\"b\":\"2\"}")),
        js("{\"metadata\":{\"name\":\"c\",\"namespace\":\"test\"},\"data\":{\"a\":\"1\",\"z\":\"0\"}}"), js("{\"metadata\":{\"name\":\"c\",\"namespace\":\"test\"},\"data\":{\"a\":\"1\",\"z\":\"0\"}}"))),
      "virtual update; done")
    check("host data change merged value",
      at(last(C.Configs.cm_sync(cfg(), True{}, [],
        cm_host(js("{\"metadata\":{\"name\":\"c\",\"namespace\":\"test\"},\"data\":{\"a\":\"1\",\"z\":\"0\"}}"), "data", js("{\"a\":\"1\"}")), cm_host(js("{\"metadata\":{\"name\":\"c\",\"namespace\":\"test\"},\"data\":{\"a\":\"1\",\"z\":\"0\"}}"), "data", js("{\"a\":\"1\",\"b\":\"2\"}")),
        js("{\"metadata\":{\"name\":\"c\",\"namespace\":\"test\"},\"data\":{\"a\":\"1\",\"z\":\"0\"}}"), js("{\"metadata\":{\"name\":\"c\",\"namespace\":\"test\"},\"data\":{\"a\":\"1\",\"z\":\"0\"}}"))), ["data"]),
      "{\"a\":\"1\",\"b\":\"2\",\"z\":\"0\"}")
    check("binaryData merges into a host without it",
      at(first(C.Configs.cm_sync(cfg(), True{}, [], js("{}"), js("{}"),
        js("{\"metadata\":{\"name\":\"c\",\"namespace\":\"test\"}}"), js("{\"metadata\":{\"name\":\"c\",\"namespace\":\"test\"},\"binaryData\":{\"b\":\"AA==\"}}"))), ["binaryData"]),
      "{\"b\":\"AA==\"}")
    check("nothing changed writes nothing",
      show_out(C.Configs.cm_sync(cfg(), True{}, [], cm_host(js("{\"metadata\":{\"name\":\"c\",\"namespace\":\"test\"},\"data\":{\"a\":\"1\"}}"), "data", js("{\"a\":\"1\"}")), cm_host(js("{\"metadata\":{\"name\":\"c\",\"namespace\":\"test\"},\"data\":{\"a\":\"1\"}}"), "data", js("{\"a\":\"1\"}")),
        js("{\"metadata\":{\"name\":\"c\",\"namespace\":\"test\"},\"data\":{\"a\":\"1\"}}"), js("{\"metadata\":{\"name\":\"c\",\"namespace\":\"test\"},\"data\":{\"a\":\"1\"}}"))),
      "done")
    # Secret type (secrets/to_host_syncer.go:138-146).
    check("virtual type change goes to the host",
      at(first(C.Configs.secret_sync(cfg(), True{}, [], js("{\"type\":\"Opaque\"}"), js("{\"type\":\"Opaque\"}"),
        js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"test\"},\"type\":\"Opaque\"}"), js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"test\"},\"type\":\"kubernetes.io/tls\"}"))), ["type"]),
      "\"kubernetes.io/tls\"")
    check("host type change comes back",
      at(last(C.Configs.secret_sync(cfg(), True{}, [], js("{\"type\":\"Opaque\"}"), js("{\"type\":\"kubernetes.io/tls\"}"),
        js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"test\"},\"type\":\"Opaque\"}"), js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"test\"},\"type\":\"Opaque\"}"))), ["type"]),
      "\"kubernetes.io/tls\"")
    check("service account token type is not synced",
      show_out(C.Configs.secret_sync(cfg(), True{}, [], secret_host(js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"test\"},\"type\":\"kubernetes.io/service-account-token\"}"), "type", js("\"Opaque\"")), secret_host(js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"test\"},\"type\":\"kubernetes.io/service-account-token\"}"), "type", js("\"Opaque\"")),
        js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"test\"},\"type\":\"kubernetes.io/service-account-token\"}"), js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"test\"},\"type\":\"kubernetes.io/service-account-token\"}"))),
      "done")
    # SyncToVirtual.
    check("host config map of a deleted virtual one is deleted",
      show_out(C.Configs.cm_sync_to_virtual(cfg(), True{}, [], Some{js("{}")}, js("{\"metadata\":{\"name\":\"h\",\"namespace\":\"test\"}}"))),
      "host delete test/h; done")
    check("synced host secret is deleted",
      show_out(C.Configs.secret_sync_to_virtual(cfg(), True{}, [], None{}, js("{\"metadata\":{\"name\":\"s-x-ns1-x-suffix\",\"namespace\":\"test\",\"annotations\":{\"vcluster.loft.sh/object-kind\":\"/v1, Kind=Secret\",\"vcluster.loft.sh/object-name\":\"s\",\"vcluster.loft.sh/object-namespace\":\"ns1\",\"vcluster.loft.sh/object-host-name\":\"s-x-ns1-x-suffix\",\"vcluster.loft.sh/object-host-namespace\":\"test\"}}}"))),
      "host delete test/s-x-ns1-x-suffix; done")
    check("used host config map is copied back",
      at(first(C.Configs.cm_sync_to_virtual(cfg(), False{}, [C.Ref{"ns1", "c"}], None{}, js("{\"metadata\":{\"name\":\"h\",\"namespace\":\"test\",\"annotations\":{\"vcluster.loft.sh/object-name\":\"c\",\"vcluster.loft.sh/object-namespace\":\"ns1\"}},\"data\":{\"a\":\"1\"}}"))), []),
      "{\"data\":{\"a\":\"1\"},\"metadata\":{\"name\":\"c\",\"namespace\":\"ns1\"}}")
    check("unused host config map is not copied back",
      show_out(C.Configs.cm_sync_to_virtual(cfg(), False{}, [], None{}, js("{\"metadata\":{\"name\":\"h\",\"namespace\":\"test\",\"annotations\":{\"vcluster.loft.sh/object-name\":\"c\",\"vcluster.loft.sh/object-namespace\":\"ns1\"}}}"))),
      "done")
    # Pod references (mappings/resources/configmaps.go:107-161).
    check("config map references of a pod",
      show_refs(C.Configs.pod_config_maps(js("{\"metadata\":{\"name\":\"p\",\"namespace\":\"ns1\"},\"spec\":{\"containers\":[{\"env\":[{\"name\":\"e\",\"valueFrom\":{\"configMapKeyRef\":{\"name\":\"c1\"}}},{\"name\":\"f\",\"valueFrom\":{\"configMapKeyRef\":{\"name\":\"\"}}},{\"name\":\"g\",\"value\":\"x\"}],\"envFrom\":[{\"configMapRef\":{\"name\":\"c2\"}},{\"secretRef\":{\"name\":\"s\"}}]}],\"initContainers\":[{\"envFrom\":[{\"configMapRef\":{\"name\":\"c3\"}}]}],\"ephemeralContainers\":[{\"env\":[{\"name\":\"e\",\"valueFrom\":{\"configMapKeyRef\":{\"name\":\"c4\"}}}]}],\"volumes\":[{\"name\":\"v\",\"configMap\":{\"name\":\"c5\"}},{\"name\":\"w\",\"configMap\":{}},{\"name\":\"x\",\"projected\":{\"sources\":[{\"configMap\":{\"name\":\"c6\"}},{\"secret\":{\"name\":\"s\"}}]}}]}}"))),
      "ns1/c1 ns1/c2 ns1/c3 ns1/c4 ns1/c5 ns1/ ns1/c6 ")
    # Pod references (mappings/resources/secrets.go:176-256).
    check("secret references of a pod",
      show_refs(C.Configs.pod_secrets(cfg(), False{}, js("{\"metadata\":{\"name\":\"p\",\"namespace\":\"ns1\"},\"spec\":{\"containers\":[{\"env\":[{\"name\":\"e\",\"valueFrom\":{\"secretKeyRef\":{\"name\":\"e1\"}}}],\"envFrom\":[{\"secretRef\":{\"name\":\"ef1\"}}]}],\"initContainers\":[{\"env\":[{\"name\":\"e\",\"valueFrom\":{\"secretKeyRef\":{\"name\":\"i1\"}}}]}],\"ephemeralContainers\":[{\"envFrom\":[{\"secretRef\":{\"name\":\"x1\"}}]}],\"imagePullSecrets\":[{\"name\":\"pull\"}],\"volumes\":[{\"name\":\"a\",\"secret\":{\"secretName\":\"vs\"}},{\"name\":\"b\",\"projected\":{\"sources\":[{\"secret\":{\"name\":\"ps\"}},{\"serviceAccountToken\":{\"path\":\"t\"}}]}},{\"name\":\"c\",\"iscsi\":{\"secretRef\":{\"name\":\"is\"}}},{\"name\":\"d\",\"rbd\":{\"secretRef\":{\"name\":\"rb\"}}},{\"name\":\"e\",\"flexVolume\":{\"secretRef\":{\"name\":\"fl\"}}},{\"name\":\"f\",\"cinder\":{\"secretRef\":{\"name\":\"ci\"}}},{\"name\":\"g\",\"cephfs\":{\"secretRef\":{\"name\":\"ce\"}}},{\"name\":\"h\",\"azureFile\":{\"secretName\":\"az\"}},{\"name\":\"i\",\"azureFile\":{\"secretName\":\"\"}},{\"name\":\"j\",\"scaleIO\":{\"secretRef\":{\"name\":\"sc\"}}},{\"name\":\"k\",\"storageos\":{\"secretRef\":{\"name\":\"so\"}}},{\"name\":\"l\",\"csi\":{\"nodePublishSecretRef\":{\"name\":\"cs\"}}},{\"name\":\"m\",\"iscsi\":{}}]}}"))),
      "ns1/e1 ns1/ef1 ns1/i1 ns1/x1 ns1/pull ns1/vs ns1/ps ns1/is ns1/rb ns1/fl ns1/ci ns1/ce ns1/az ns1/sc ns1/so ns1/cs ")
    check("useSecretsForSATokens refers to the host token secret name",
      show_refs(C.Configs.pod_secrets(cfg(), True{}, js("{\"metadata\":{\"name\":\"p\",\"namespace\":\"ns1\"},\"spec\":{\"volumes\":[{\"name\":\"b\",\"projected\":{\"sources\":[{\"secret\":{\"name\":\"ps\"}},{\"serviceAccountToken\":{\"path\":\"t\"}}]}}]}}"))),
      "ns1/ps test/p-sa-token-x-ns1-x-suffix ")
    # Ingress references (mappings/resources/secrets.go:112-174).
    check("secret references of an ingress",
      show_refs(C.Configs.ingress_secrets(js("{\"metadata\":{\"name\":\"i\",\"namespace\":\"ns1\",\"annotations\":{\"nginx.ingress.kubernetes.io/proxy-ssl-secret\":\"a/b/c\",\"nginx.ingress.kubernetes.io/auth-tls-secret\":\"other/s2\",\"nginx.ingress.kubernetes.io/auth-secret\":\"s1\",\"x\":\"y\"}},\"spec\":{\"tls\":[{\"secretName\":\"t1\"},{\"hosts\":[\"h\"]}]}}"))),
      "ns1/s1 other/s2 ns1/t1 ")
    # Service accounts (serviceaccounts/syncer.go).
    check("host service account has no secrets and no token mount",
      show(J.Json.del(first(C.Configs.sa_sync_to_host(cfg(), None{}, js("{\"metadata\":{\"name\":\"sa\",\"namespace\":\"ns1\"},\"secrets\":[{\"name\":\"t\"}],\"imagePullSecrets\":[{\"name\":\"p\"}],\"automountServiceAccountToken\":true}"))), "metadata")),
      "{}")
    check("host service account mount is false, not absent",
      J.Json.show(J.Json.get(first(C.Configs.sa_sync_to_host(cfg(), None{}, js("{\"metadata\":{\"name\":\"sa\",\"namespace\":\"ns1\"}}"))), "automountServiceAccountToken")),
      "false")
    check("service account sync carries annotations to the host",
      at(first(C.Configs.sa_sync(cfg(), js("{\"metadata\":{\"name\":\"sa-x-ns1-x-suffix\"}}"), js("{\"metadata\":{\"name\":\"sa-x-ns1-x-suffix\"}}"),
        js("{\"metadata\":{\"name\":\"sa\",\"namespace\":\"ns1\"}}"), js("{\"metadata\":{\"name\":\"sa\",\"namespace\":\"ns1\",\"annotations\":{\"a\":\"b\"}}}"))), ["metadata", "annotations", "a"]),
      "\"b\"")
    check("service account sync leaves secrets alone",
      show_out(C.Configs.sa_sync(cfg(), sa_host(js("{\"metadata\":{\"name\":\"sa\",\"namespace\":\"ns1\"}}"), "secrets", js("[{\"name\":\"x\"}]")), sa_host(js("{\"metadata\":{\"name\":\"sa\",\"namespace\":\"ns1\"}}"), "secrets", js("[{\"name\":\"y\"}]")),
        js("{\"metadata\":{\"name\":\"sa\",\"namespace\":\"ns1\"}}"), js("{\"metadata\":{\"name\":\"sa\",\"namespace\":\"ns1\"},\"secrets\":[{\"name\":\"z\"}]}"))),
      "done")
    check("host service account of a deleted virtual one is deleted",
      show_out(C.Configs.sa_sync_to_virtual(cfg(), Some{js("{}")}, js("{\"metadata\":{\"name\":\"h\",\"namespace\":\"test\"}}"))),
      "host delete test/h; done")
