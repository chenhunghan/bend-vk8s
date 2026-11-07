import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/sync/core.bend as C

# Spec for src/sync/core.bend (vcluster pkg/syncer/syncer.go,
# from_host_syncer.go, pkg/patcher).
#
# The concrete laws transcribe every case of pkg/syncer/syncer_test.go,
# from_host_syncer_test.go, pkg/patcher/patcher_test.go and apply_test.go
# (vcluster a8ab30e). Expected objects are the Go tests' expected states;
# vcluster's CompareObjs strips resourceVersion, uid and the managed-by
# label, so those are written as vcluster's code sets them (VClusterName is
# "suffix" in pkg/syncer's tests, the target namespace "test"). Objects and
# patches are compared with C.Core.json_same, which ignores member order (Go
# maps have none).

# Fixtures.

def Laws.core.kv(k: String, v: String) -> J.KV:
  J.KV{k, J.JStr{v}}

def Laws.core.obj(fs: List<&2, J.KV>) -> J.Json:
  J.Json.obj(fs)

# The mock syncer of syncer_test.go is a to-host secrets syncer whose Sync
# copies .data bidirectionally; TestReconcile gives it an object cache and
# the default options (UID deletion on).
def Laws.core.cfg() -> C.Cfg:
  C.Cfg{"suffix", "test", "/v1, Kind=Secret", "secrets", True{}, True{}, False{}}

# The from-host configmap syncer of from_host_syncer_test.go.
def Laws.core.cfg_fh() -> C.Cfg:
  C.Cfg{"suffix", "test", "/v1, Kind=ConfigMap", "from-host-configmap", True{}, True{}, True{}}

def Laws.core.secret(meta: List<&2, J.KV>, rest: List<&2, J.KV>) -> J.Json:
  Laws.core.obj(Laws.core.kv("apiVersion", "v1") <> Laws.core.kv("kind", "Secret") <> J.KV{"metadata", Laws.core.obj(meta)} <> rest)

def Laws.core.data1() -> List<&2, J.KV>:
  [J.KV{"data", Laws.core.obj([Laws.core.kv("datakey1", "ZGF0YXZhbHVlMQ==")])}]

# Virtual secret default/a, uid 123. The fake client gives every object
# resourceVersion "999" (FakeClientResourceVersion).
def Laws.core.secret_a(rest: List<&2, J.KV>) -> J.Json:
  Laws.core.secret([Laws.core.kv("name", "a"), Laws.core.kv("namespace", "default"), Laws.core.kv("uid", "123"), Laws.core.kv("resourceVersion", "999")], rest)

# The annotations vcluster puts on the host object of default/a.
def Laws.core.host_annotations_a() -> List<&2, J.KV>:
  [Laws.core.kv("vcluster.loft.sh/object-name", "a"),
    Laws.core.kv("vcluster.loft.sh/object-namespace", "default"),
    Laws.core.kv("vcluster.loft.sh/object-uid", "123"),
    Laws.core.kv("vcluster.loft.sh/object-kind", "/v1, Kind=Secret"),
    Laws.core.kv("vcluster.loft.sh/object-host-name", "a-x-default-x-suffix"),
    Laws.core.kv("vcluster.loft.sh/object-host-namespace", "test")]

def Laws.core.host_labels_a() -> List<&2, J.KV>:
  [Laws.core.kv("vcluster.loft.sh/managed-by", "suffix"), Laws.core.kv("vcluster.loft.sh/namespace", "default")]

# "should sync down": the host secret created for default/a.
def Laws.core.host_a() -> J.Json:
  Laws.core.secret([Laws.core.kv("name", "a-x-default-x-suffix"), Laws.core.kv("namespace", "test"),
    J.KV{"annotations", Laws.core.obj(Laws.core.host_annotations_a())},
    J.KV{"labels", Laws.core.obj(Laws.core.host_labels_a())}], [])

# "should adopt object of desired name when already exists": the host
# secret before and after.
def Laws.core.host_existing() -> J.Json:
  Laws.core.secret([Laws.core.kv("name", "a-x-default-x-suffix"), Laws.core.kv("namespace", "test"), Laws.core.kv("resourceVersion", "999"),
    J.KV{"annotations", Laws.core.obj([Laws.core.kv("app", "existing")])},
    J.KV{"labels", Laws.core.obj([Laws.core.kv("app", "existing")])}], Laws.core.data1())

def Laws.core.host_adopted() -> J.Json:
  Laws.core.secret([Laws.core.kv("name", "a-x-default-x-suffix"), Laws.core.kv("namespace", "test"), Laws.core.kv("resourceVersion", "999"),
    J.KV{"annotations", Laws.core.obj(Laws.core.kv("app", "existing") <> Laws.core.host_annotations_a())},
    J.KV{"labels", Laws.core.obj(Laws.core.host_labels_a())}], Laws.core.data1())

# The merge patch from host_existing to host_adopted.
def Laws.core.adopt_patch() -> J.Json:
  Laws.core.obj([J.KV{"metadata", Laws.core.obj([
    J.KV{"annotations", Laws.core.obj(Laws.core.host_annotations_a())},
    J.KV{"labels", Laws.core.obj(J.KV{"app", J.JNull{}} <> Laws.core.host_labels_a())}])}])

# from_host_syncer_test.go objects (ConfigMap test-namespace/test-name).
def Laws.core.cm(meta: List<&2, J.KV>, labels: List<&2, J.KV>, annotations: List<&2, J.KV>) -> J.Json:
  Laws.core.obj([Laws.core.kv("apiVersion", "v1"), Laws.core.kv("kind", "ConfigMap"),
    J.KV{"metadata", Laws.core.obj(Laws.core.kv("name", "test-name") <> Laws.core.kv("namespace", "test-namespace") <> List.append(&2, J.KV, meta,
      [J.KV{"labels", Laws.core.obj(labels)}, J.KV{"annotations", Laws.core.obj(annotations)}]))},
    J.KV{"data", Laws.core.obj([Laws.core.kv("hello", "test")])}])

def Laws.core.labels0() -> List<&2, J.KV>:
  [Laws.core.kv("example.com/label-a", "test-1"), Laws.core.kv("example.com/label-b", "test-2")]

def Laws.core.annotations0() -> List<&2, J.KV>:
  [Laws.core.kv("example.com/annotation-a", "test-1"), Laws.core.kv("example.com/annotation-b", "test-2")]

def Laws.core.labels1() -> List<&2, J.KV>:
  [Laws.core.kv("example.com/label-a", "test-1"), Laws.core.kv("example.com/label-b", "updated-test-2"), Laws.core.kv("example.com/label-c", "new-test-3")]

def Laws.core.annotations1() -> List<&2, J.KV>:
  [Laws.core.kv("example.com/annotation-a", "updated-test-1"), Laws.core.kv("example.com/annotation-b", "test-2"), Laws.core.kv("example.com/annotation-c", "new-test-3")]

def Laws.core.rv999() -> List<&2, J.KV>:
  [Laws.core.kv("resourceVersion", "999")]

# pObject, vObject, pObjectUpdated, vObjectUpdated (FakeClientResourceVersion
# "999").
def Laws.core.p_object() -> J.Json:
  Laws.core.cm(Laws.core.rv999(), Laws.core.labels0(), Laws.core.annotations0())

def Laws.core.v_object() -> J.Json:
  Laws.core.cm(Laws.core.rv999(), Laws.core.labels0(), Laws.core.annotations0())

def Laws.core.p_updated() -> J.Json:
  Laws.core.cm(Laws.core.rv999(), Laws.core.labels1(), Laws.core.annotations1())

def Laws.core.v_updated() -> J.Json:
  Laws.core.cm(Laws.core.rv999(), Laws.core.labels1(), Laws.core.annotations1())

# The virtual object as created (the fake client then sets resourceVersion).
def Laws.core.v_created() -> J.Json:
  Laws.core.cm([], Laws.core.labels0(), Laws.core.annotations0())

def Laws.core.update_patch() -> J.Json:
  Laws.core.obj([J.KV{"metadata", Laws.core.obj([
    J.KV{"annotations", Laws.core.obj([Laws.core.kv("example.com/annotation-a", "updated-test-1"), Laws.core.kv("example.com/annotation-c", "new-test-3")])},
    J.KV{"labels", Laws.core.obj([Laws.core.kv("example.com/label-b", "updated-test-2"), Laws.core.kv("example.com/label-c", "new-test-3")])}])}])

def Laws.core.namespace_test_namespace() -> J.Json:
  Laws.core.obj([Laws.core.kv("apiVersion", "v1"), Laws.core.kv("kind", "Namespace"),
    J.KV{"metadata", Laws.core.obj([Laws.core.kv("name", "test-namespace")])}])

# patcher_test.go TestCacheRebase: configMap(resourceVersion, data).
def Laws.core.cache_cm(rv: String, data: List<&2, J.KV>) -> J.Json:
  Laws.core.obj([J.KV{"metadata", Laws.core.obj([Laws.core.kv("name", "cm"), Laws.core.kv("namespace", "ns"), Laws.core.kv("resourceVersion", rv)])},
    J.KV{"data", Laws.core.obj(data)}])

def Laws.core.cached() -> J.Json:
  Laws.core.cache_cm("1", [Laws.core.kv("a", "1")])

def Laws.core.before() -> J.Json:
  Laws.core.cache_cm("2", [Laws.core.kv("a", "1"), Laws.core.kv("own", "x")])

def Laws.core.written() -> J.Json:
  Laws.core.cache_cm("3", [Laws.core.kv("a", "1"), Laws.core.kv("own", "x"), Laws.core.kv("copied", "y")])

def Laws.core.entry_rv(m: Maybe<&2, J.Json>) -> String:
  match m:
    case None{}:
      ""
    case Some{x}:
      C.Core.rv(x)

def Laws.core.entry_data(m: Maybe<&2, J.Json>) -> J.Json:
  match m:
    case None{}:
      J.JNull{}
    case Some{x}:
      J.Json.get(x, "data")

# apply_test.go: the string at a path of the sanitized JSON, as the test's
# checks read it (None when it does not parse).
def Laws.core.at_str.r(r: Result<&2, &2, String, J.Json>, path: List<&2, String>) -> Maybe<&2, String>:
  match r:
    case Fail{e}:
      None{}
    case Done{j}:
      J.Json.as_str(J.Json.at(j, path))

def Laws.core.at_str(s: String, path: List<&2, String>) -> Maybe<&2, String>:
  Laws.core.at_str.r(J.Json.parse(s), path)

def Laws.core.manifest_str.m(m: Maybe<&2, String>, path: List<&2, String>) -> Maybe<&2, String>:
  match m:
    case None{}:
      None{}
    case Some{s}:
      Laws.core.at_str(s, path)

# A string inside the manifest held by the last-applied annotation.
def Laws.core.manifest_str(s: String, path: List<&2, String>) -> Maybe<&2, String>:
  Laws.core.manifest_str.m(Laws.core.at_str(s, ["metadata", "annotations", "kubectl.kubernetes.io/last-applied-configuration"]), path)

def Laws.core.last_applied_patch() -> String:
  "{\"data\":{\"username\":\"[REDACTED]\"},\"metadata\":{\"annotations\":{\"kubectl.kubernetes.io/last-applied-configuration\":\"{\\\"apiVersion\\\":\\\"v1\\\",\\\"data\\\":{\\\"password\\\":\\\"c2VjcmV0\\\",\\\"username\\\":\\\"YWRtaW4=\\\"},\\\"kind\\\":\\\"Secret\\\",\\\"metadata\\\":{\\\"name\\\":\\\"my-secret\\\",\\\"namespace\\\":\\\"default\\\"},\\\"type\\\":\\\"Opaque\\\"}\"}}}"

# TestController "should sync down": virtual default/a, no host object at
# its host name a-x-default-x-suffix (test/a is another object): SyncToHost
# creates the host secret.

law core.controller_sync_down:
  {C.Core.out_same(C.Core.reconcile_to_host(Laws.core.cfg(), ["data"], True{}, None{}, Some{Laws.core.secret_a([])}, None{}, None{}),
    [C.Create{C.Host{}, Laws.core.host_a()}], C.Settled{}) == True{} : Bool}

# TestReconcile "should sync down".

law core.reconcile_sync_down:
  {C.Core.out_same(C.Core.reconcile_to_host(Laws.core.cfg(), ["data"], True{}, None{}, Some{Laws.core.secret_a([])}, None{}, None{}),
    [C.Create{C.Host{}, Laws.core.host_a()}], C.Settled{}) == True{} : Bool}

# TestReconcile "should adopt object of desired name when already exists":
# VirtualToHost records the name mapping, so the host object is managed
# (recorder.IsManaged); the cache is empty; Sync patches the host only.

law core.reconcile_adopt_writes:
  {C.Core.out_same(C.Core.reconcile_to_host(Laws.core.cfg(), ["data"], True{}, None{}, Some{Laws.core.secret_a(Laws.core.data1())}, None{}, Some{Laws.core.host_existing()}),
    [C.Patch{C.Host{}, False{}, Laws.core.adopt_patch()}], C.Settled{}) == True{} : Bool}

law core.reconcile_adopt_state:
  {C.Core.json_same(C.Core.apply_patch(Laws.core.host_existing(), Laws.core.adopt_patch()), Laws.core.host_adopted()) == True{} : Bool}

# TestReconcile "should not adopt virtual object": the request test/abc
# names no virtual object and no host object (abc-x-test-x-suffix).

law core.reconcile_not_adopt:
  {C.Core.reconcile_to_host(Laws.core.cfg(), ["data"], False{}, None{}, None{}, None{}, None{}) == C.Out{[], C.Settled{}} : C.Out}

# TestFromHostSyncer "Sync new host resource to virtual": the first call
# creates the missing namespace and requeues, the second creates the
# virtual object.

law core.from_host_new_namespace:
  {C.Core.out_same(C.Core.from_host.to_virtual(Laws.core.cfg_fh(), None{}, Laws.core.p_object(), "test-name", "test-namespace", C.NsMissing{}),
    [C.Create{C.Virtual{}, Laws.core.namespace_test_namespace()}], C.AgainNow{}) == True{} : Bool}

law core.from_host_new_create:
  {C.Core.out_same(C.Core.from_host.to_virtual(Laws.core.cfg_fh(), None{}, Laws.core.p_object(), "test-name", "test-namespace", C.NsReady{}),
    [C.Create{C.Virtual{}, Laws.core.v_created()}], C.Settled{}) == True{} : Bool}

# "Sync updated host resource to virtual": the fake CopyHostObjectToVirtual
# copies annotations and labels (no fields); only the virtual object is
# patched.

law core.from_host_update_writes:
  {C.Core.out_same(C.Core.from_host.sync([], Laws.core.v_object(), Laws.core.p_updated()),
    [C.Patch{C.Virtual{}, False{}, Laws.core.update_patch()}], C.Settled{}) == True{} : Bool}

law core.from_host_update_state:
  {C.Core.json_same(C.Core.apply_patch(Laws.core.v_object(), Laws.core.update_patch()), Laws.core.v_updated()) == True{} : Bool}

# "Delete virtual resources after host resource has been deleted": the
# event has no HostOld, so SyncToHost returns without a delete (the test's
# empty expected state checks nothing).

law core.from_host_delete:
  {C.Core.from_host.to_host(None{}, Laws.core.v_object()) == C.Out{[], C.Settled{}} : C.Out}

# TestCacheRebase.

# "keeps own changes unsynced and adopts what the syncer wrote"
law core.cache_rebase_written_rv:
  {Laws.core.entry_rv(C.Core.cache_rebase(Some{Laws.core.cached()}, Laws.core.before(), Some{Laws.core.written()})) == "3" : String}

law core.cache_rebase_written_data:
  {C.Core.json_same(Laws.core.entry_data(C.Core.cache_rebase(Some{Laws.core.cached()}, Laws.core.before(), Some{Laws.core.written()})),
    Laws.core.obj([Laws.core.kv("a", "1"), Laws.core.kv("copied", "y")])) == True{} : Bool}

# "leaves the cache entry alone if nothing was written"
law core.cache_rebase_nothing:
  {C.Core.cache_rebase(Some{Laws.core.cached()}, Laws.core.before(), None{}) == Some{Laws.core.cached()} : Maybe<&2, J.Json>}

# "removes the cache entry if there was none before"
law core.cache_rebase_none:
  {C.Core.cache_rebase(None{}, Laws.core.before(), Some{Laws.core.written()}) == None{} : Maybe<&2, J.Json>}

# TestSanitizePatchForLog.

law core.sanitize_configmap:
  {C.Core.sanitize(False{}, "{\"data\":{\"key\":\"value\"}}") == "{\"data\":{\"key\":\"value\"}}" : String}

law core.sanitize_data_username:
  {Laws.core.at_str(C.Core.sanitize(True{}, "{\"data\":{\"username\":\"c2VjcmV0LW5ldw==\",\"password\":\"c2VjcmV0\"}}"), ["data", "username"]) == Some{"[REDACTED]"} : Maybe<&2, String>}

law core.sanitize_data_password:
  {Laws.core.at_str(C.Core.sanitize(True{}, "{\"data\":{\"username\":\"c2VjcmV0LW5ldw==\",\"password\":\"c2VjcmV0\"}}"), ["data", "password"]) == Some{"[REDACTED]"} : Maybe<&2, String>}

law core.sanitize_string_data:
  {Laws.core.at_str(C.Core.sanitize(True{}, "{\"stringData\":{\"api-key\":\"plaintext-secret\"}}"), ["stringData", "api-key"]) == Some{"[REDACTED]"} : Maybe<&2, String>}

law core.sanitize_both_data:
  {Laws.core.at_str(C.Core.sanitize(True{}, "{\"data\":{\"token\":\"dG9rZW4=\"},\"stringData\":{\"extra\":\"plain\"}}"), ["data", "token"]) == Some{"[REDACTED]"} : Maybe<&2, String>}

law core.sanitize_both_string_data:
  {Laws.core.at_str(C.Core.sanitize(True{}, "{\"data\":{\"token\":\"dG9rZW4=\"},\"stringData\":{\"extra\":\"plain\"}}"), ["stringData", "extra"]) == Some{"[REDACTED]"} : Maybe<&2, String>}

law core.sanitize_no_data:
  {C.Core.sanitize(True{}, "{\"metadata\":{\"labels\":{\"app\":\"test\"}}}") == "{\"metadata\":{\"labels\":{\"app\":\"test\"}}}" : String}

law core.sanitize_data_null:
  {C.Core.sanitize(True{}, "{\"data\":null}") == "{\"data\":null}" : String}

law core.sanitize_malformed:
  {C.Core.sanitize(True{}, "not-valid-json") == "[REDACTED]" : String}

law core.sanitize_last_applied_kind:
  {Laws.core.manifest_str(C.Core.sanitize(True{}, Laws.core.last_applied_patch()), ["kind"]) == Some{"Secret"} : Maybe<&2, String>}

law core.sanitize_last_applied_api_version:
  {Laws.core.manifest_str(C.Core.sanitize(True{}, Laws.core.last_applied_patch()), ["apiVersion"]) == Some{"v1"} : Maybe<&2, String>}

law core.sanitize_last_applied_password:
  {Laws.core.manifest_str(C.Core.sanitize(True{}, Laws.core.last_applied_patch()), ["data", "password"]) == Some{"[REDACTED]"} : Maybe<&2, String>}

law core.sanitize_last_applied_username:
  {Laws.core.manifest_str(C.Core.sanitize(True{}, Laws.core.last_applied_patch()), ["data", "username"]) == Some{"[REDACTED]"} : Maybe<&2, String>}

# General laws.

# A host object that is not managed is never deleted or updated: the
# reconcile skips it whatever the virtual side and the cache hold.
law core.unmanaged_skip:
  for +cfg: C.Cfg
  for +vold: Maybe<&2, J.Json>
  for +v: Maybe<&2, J.Json>
  for +pold: Maybe<&2, J.Json>
  for +p: J.Json
  {C.Core.decide(cfg, False{}, vold, v, pold, Some{p}) == C.DSkip{} : C.Decision}

law core.unmanaged_to_host:
  for +cfg: C.Cfg
  for +fields: +List<String>
  for +mapped: Bool
  for +expected: Maybe<&2, String>
  for +vold: Maybe<&2, J.Json>
  for +v: Maybe<&2, J.Json>
  for +pold: Maybe<&2, J.Json>
  for +p: J.Json
  for +h: {C.Core.is_managed_to_host(cfg, mapped, expected, p) == False{} : Bool}
  {C.Core.reconcile_to_host(cfg, fields, C.Core.is_managed_to_host(cfg, mapped, expected, p), vold, v, pold, Some{p}) == C.Out{[], C.Settled{}} : C.Out}

law core.unmanaged_from_host:
  for +cfg: C.Cfg
  for +fields: +List<String>
  for +matched: Bool
  for +vold: Maybe<&2, J.Json>
  for +v: Maybe<&2, J.Json>
  for +pold: Maybe<&2, J.Json>
  for +p: J.Json
  for +vname: String
  for +vns: String
  for +ns: C.NsState
  for +h: {C.Core.is_managed_from_host(matched, p) == False{} : Bool}
  {C.Core.reconcile_from_host(cfg, fields, C.Core.is_managed_from_host(matched, p), vold, v, pold, Some{p}, vname, vns, ns) == C.Out{[], C.Settled{}} : C.Out}

# The importer: an unmanaged host object that is not imported is never
# enqueued.
law core.unmanaged_not_enqueued:
  for +named: Bool
  for +is_delete: Bool
  for +p: J.Json
  {C.Core.enqueue_host(named, False{}, False{}, is_delete, p) == False{} : Bool}

# Syncing an already-in-sync pair yields no writes.
law core.apply_object_same:
  for +s: C.Side
  for +x: J.Json
  for +hs: Bool
  {C.Core.apply_object(s, x, x, hs) == [] : List<&2, C.Write>}

law core.in_sync_no_writes:
  for +v: J.Json
  for +p: J.Json
  for +skip: Bool
  for +hs: Bool
  {C.Core.patch_writes(v, v, p, p, skip, hs) == [] : List<&2, C.Write>}

law core.copy_bidirectional_in_sync:
  for +v: J.Json
  for +h: J.Json
  {C.Core.copy_bidirectional(v, v, h, h) == (v, h) : J.Json & J.Json}

law core.merge_bidirectional_in_sync:
  for +v: J.Json
  for +h: J.Json
  {C.Core.merge_bidirectional(v, v, h, h) == (v, h) : J.Json & J.Json}

law core.from_host_in_sync:
  for +fields: +List<String>
  for +v: J.Json
  for +p: J.Json
  for +h: {C.Core.from_host.copy(fields, v, p) == v : J.Json}
  {C.Core.from_host.sync(fields, v, p) == C.Out{[], C.Settled{}} : C.Out}

# The decision is total: every state yields one decision, and only one.
law core.decide_total:
  for +cfg: C.Cfg
  for +managed: Bool
  for +vold: Maybe<&2, J.Json>
  for +v: Maybe<&2, J.Json>
  for +pold: Maybe<&2, J.Json>
  for +p: Maybe<&2, J.Json>
  exs d: C.Decision
  {C.Core.decide(cfg, managed, vold, v, pold, p) == d : C.Decision}

law core.decide_unique:
  for +cfg: C.Cfg
  for +managed: Bool
  for +vold: Maybe<&2, J.Json>
  for +v: Maybe<&2, J.Json>
  for +pold: Maybe<&2, J.Json>
  for +p: Maybe<&2, J.Json>
  for +d1: C.Decision
  for +d2: C.Decision
  for +h1: {C.Core.decide(cfg, managed, vold, v, pold, p) == d1 : C.Decision}
  for +h2: {C.Core.decide(cfg, managed, vold, v, pold, p) == d2 : C.Decision}
  {d1 == d2 : C.Decision}

# With neither object there is nothing to do.
law core.decide_nothing:
  for +cfg: C.Cfg
  for +managed: Bool
  for +vold: Maybe<&2, J.Json>
  for +pold: Maybe<&2, J.Json>
  {C.Core.decide(cfg, managed, vold, None{}, pold, None{}) == C.DSkip{} : C.Decision}
