import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ./yaml.bend as Y

# vcluster.yaml projection at loft-sh/vcluster a8ab30ea. This is a pure
# config reader, not a sync step: it returns a JSON configuration or an
# error, and makes no writes. False/zero/empty values are significant here;
# the service translator's omitempty canonicalization must NOT be used.
# Known keys outside this projection are rejected as unsupported fields.
# No Pro implementation is called. Standalone normalization is a runtime
# operation and is not inferred from the presence of standalone settings.

def Config.defaults() -> J.Json:
  J.Json.obj([J.KV{"controlPlane", J.Json.obj([J.KV{"distro", J.Json.obj([J.KV{"k8s", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}, J.KV{"version", J.JStr{""}}, J.KV{"apiServer", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}, J.KV{"extraArgs", J.Json.arr([])}])}, J.KV{"controllerManager", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}, J.KV{"extraArgs", J.Json.arr([])}])}, J.KV{"scheduler", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}, J.KV{"extraArgs", J.Json.arr([])}])}])}])}, J.KV{"backingStore", J.Json.obj([J.KV{"database", J.Json.obj([J.KV{"embedded", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}])}, J.KV{"etcd", J.Json.obj([J.KV{"embedded", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}])}])}, J.KV{"coredns", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}, J.KV{"deployment", J.Json.obj([J.KV{"replicas", J.JNum{"1"}}])}])}, J.KV{"standalone", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}, J.KV{"joinNode", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}])}])}])}, J.KV{"networking", J.Json.obj([J.KV{"serviceCIDR", J.JStr{""}}, J.KV{"podCIDR", J.JStr{"10.244.0.0/16"}}, J.KV{"advanced", J.Json.obj([J.KV{"clusterDomain", J.JStr{"cluster.local"}}])}])}, J.KV{"privateNodes", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"sync", J.Json.obj([J.KV{"toHost", J.Json.obj([J.KV{"services", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}])}, J.KV{"endpoints", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}])}, J.KV{"endpointSlices", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}])}, J.KV{"persistentVolumeClaims", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}])}, J.KV{"configMaps", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}])}, J.KV{"secrets", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}])}, J.KV{"pods", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}])}, J.KV{"ingresses", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"priorityClasses", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"networkPolicies", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"volumeSnapshots", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"volumeSnapshotContents", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"podDisruptionBudgets", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"serviceAccounts", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"storageClasses", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"persistentVolumes", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"namespaces", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"resourceClaims", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"resourceClaimTemplates", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"gatewayApi", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}, J.KV{"gateways", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"httpRoutes", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"tlsRoutes", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"backendTLSPolicies", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"referenceGrants", J.Json.obj([J.KV{"enabled", J.JStr{"auto"}}])}])}])}, J.KV{"fromHost", J.Json.obj([J.KV{"events", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}])}, J.KV{"configMaps", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"csiDrivers", J.Json.obj([J.KV{"enabled", J.JStr{"auto"}}])}, J.KV{"csiNodes", J.Json.obj([J.KV{"enabled", J.JStr{"auto"}}])}, J.KV{"csiStorageCapacities", J.Json.obj([J.KV{"enabled", J.JStr{"auto"}}])}, J.KV{"storageClasses", J.Json.obj([J.KV{"enabled", J.JStr{"auto"}}])}, J.KV{"ingressClasses", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"gatewayClasses", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"gateways", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"runtimeClasses", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"priorityClasses", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"nodes", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"secrets", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"volumeSnapshotClasses", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"deviceClasses", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}])}])}])

# A schema member "*" accepts every key, its value checked against the
# member's schema (a map[string]string such as selector labels).
def Config.any_map() -> J.Json:
  J.Json.obj([J.KV{"*", J.JStr{""}}])

# The strict decoder's schema: the chart projection (Config.defaults) and
# the keys a document may set without a default in the projection:
# controlPlane.advanced.virtualScheduler, networking.advanced.proxyKubelets
# and sync.fromHost.nodes.selector (chart/values.yaml values). Config.parse
# grafts them only when the document has them, so the projection of an
# empty document stays Config.defaults(); the accessors below give their
# chart defaults.
def Config.schema() -> J.Json:
  J.Json.obj([J.KV{"controlPlane", J.Json.obj([J.KV{"distro", J.Json.obj([J.KV{"k8s", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}, J.KV{"version", J.JStr{""}}, J.KV{"apiServer", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}, J.KV{"extraArgs", J.Json.arr([])}])}, J.KV{"controllerManager", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}, J.KV{"extraArgs", J.Json.arr([])}])}, J.KV{"scheduler", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}, J.KV{"extraArgs", J.Json.arr([])}])}])}])}, J.KV{"backingStore", J.Json.obj([J.KV{"database", J.Json.obj([J.KV{"embedded", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}])}, J.KV{"etcd", J.Json.obj([J.KV{"embedded", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}])}])}, J.KV{"coredns", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}, J.KV{"deployment", J.Json.obj([J.KV{"replicas", J.JNum{"1"}}])}])}, J.KV{"standalone", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}, J.KV{"joinNode", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}])}])}, J.KV{"advanced", J.Json.obj([J.KV{"virtualScheduler", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}])}])}, J.KV{"networking", J.Json.obj([J.KV{"serviceCIDR", J.JStr{""}}, J.KV{"podCIDR", J.JStr{"10.244.0.0/16"}}, J.KV{"advanced", J.Json.obj([J.KV{"clusterDomain", J.JStr{"cluster.local"}}, J.KV{"proxyKubelets", J.Json.obj([J.KV{"byHostname", J.JBool{True{}}}, J.KV{"byIP", J.JBool{True{}}}])}])}])}, J.KV{"privateNodes", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"sync", J.Json.obj([J.KV{"toHost", J.Json.obj([J.KV{"services", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}])}, J.KV{"endpoints", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}])}, J.KV{"endpointSlices", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}])}, J.KV{"persistentVolumeClaims", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}])}, J.KV{"configMaps", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}])}, J.KV{"secrets", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}])}, J.KV{"pods", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}])}, J.KV{"ingresses", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"priorityClasses", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"networkPolicies", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"volumeSnapshots", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"volumeSnapshotContents", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"podDisruptionBudgets", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"serviceAccounts", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"storageClasses", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"persistentVolumes", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"namespaces", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"resourceClaims", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"resourceClaimTemplates", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"gatewayApi", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}, J.KV{"gateways", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"httpRoutes", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"tlsRoutes", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"backendTLSPolicies", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"referenceGrants", J.Json.obj([J.KV{"enabled", J.JStr{"auto"}}])}])}])}, J.KV{"fromHost", J.Json.obj([J.KV{"events", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}])}, J.KV{"configMaps", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"csiDrivers", J.Json.obj([J.KV{"enabled", J.JStr{"auto"}}])}, J.KV{"csiNodes", J.Json.obj([J.KV{"enabled", J.JStr{"auto"}}])}, J.KV{"csiStorageCapacities", J.Json.obj([J.KV{"enabled", J.JStr{"auto"}}])}, J.KV{"storageClasses", J.Json.obj([J.KV{"enabled", J.JStr{"auto"}}])}, J.KV{"ingressClasses", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"gatewayClasses", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"gateways", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"runtimeClasses", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"priorityClasses", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"nodes", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}, J.KV{"selector", J.Json.obj([J.KV{"all", J.JBool{False{}}}, J.KV{"labels", Config.any_map()}])}])}, J.KV{"secrets", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"volumeSnapshotClasses", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"deviceClasses", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}])}])}])

def Config.unknown(+key: String) -> String:
  "error unmarshaling JSON: while decoding JSON: json: unknown field " ++ J.Json.quote(key)

def Config.has(ms: J.Json, +key: String) -> Bool:
  match ms:
    case J.JObj{m}:
      Config.has(m, key)
    case J.JMem{+k, v, t}:
      Bool.or(Bool.or(String.eq(k, key), String.eq(k, "*")), Config.has(t, key))
    case _:
      False{}

def Config.type_error(path: String) -> Result<&2, &2, String, J.Json>:
  Fail{"config: invalid value type at " ++ path}

# sigs.k8s.io/yaml converts boolean/numeric scalars to strings when the Go
# destination is string. StrBool also accepts booleans, preserving auto.
def Config.scalar(v: J.Json, schema: J.Json, path: String) -> Result<&2, &2, String, J.Json>:
  match v schema:
    case J.JNull{} s:
      Done{s}
    case J.JBool{b} J.JBool{s}:
      Done{J.JBool{b}}
    case J.JNum{n} J.JNum{s}:
      Done{J.JNum{n}}
    case J.JStr{v} J.JStr{s}:
      Done{J.JStr{v}}
    case J.JBool{b} J.JStr{s}:
      Done{J.JStr{J.Json.show(J.JBool{b})}}
    case J.JNum{n} J.JStr{s}:
      Done{J.JStr{n}}
    case v J.JNull{}:
      Done{v}
    case _ _:
      Config.type_error(path)

def Config.object(v: J.Json, schema: J.Json, path: String) -> Result<&2, &2, String, J.Json>:
  match schema:
    case J.JObj{s}:
      Done{J.JObj{v}}
    case J.JNull{}:
      Done{J.JObj{v}}
    case _:
      Config.type_error(path)

def Config.array(v: J.Json, schema: J.Json, path: String) -> Result<&2, &2, String, J.Json>:
  match schema:
    case J.JArr{s}:
      Done{J.JArr{v}}
    case J.JNull{}:
      Done{J.JArr{v}}
    case _:
      Config.type_error(path)

def Config.member(+k: String, v: Result<&2, &2, String, J.Json>, t: Result<&2, &2, String, J.Json>, known: Bool) -> Result<&2, &2, String, J.Json>:
  match known:
    case False{}:
      Fail{Config.unknown(k)}
    case True{}:
      do Result<&2, &2, String, J.Json>:
        h : J.Json <- v
        rest : J.Json <- t
        return J.JMem{k, h, rest}

def Config.sub.or(v: J.Json, +schema: J.Json) -> J.Json:
  match v:
    case J.JNull{}:
      J.Json.get(schema, "*")
    case x:
      x

# The schema of a member: its own, else the "*" member's (Config.any_map).
def Config.sub(+schema: J.Json, +k: String) -> J.Json:
  Config.sub.or(J.Json.get(schema, k), schema)

# Recursive validation keeps the shape and order of the input. The schema
# is the default projection; presence, not truthiness, recognizes a key.
def Config.check(v: J.Json, +schema: J.Json, +path: String) -> Result<&2, &2, String, J.Json>:
  match v:
    case J.JObj{m}:
      do Result<&2, &2, String, J.Json>:
        ms : J.Json <- Config.check(m, schema, path)
        Config.object(ms, schema, path)
    case J.JMem{+k, h, t}:
      Config.member(k, Config.check(h, Config.sub(schema, k), path ++ "." ++ k),
        Config.check(t, schema, path), Config.has(schema, k))
    case J.JArr{xs}:
      do Result<&2, &2, String, J.Json>:
        items : J.Json <- Config.check(xs, J.JStr{""}, path)
        Config.array(items, schema, path)
    case J.JCons{h, t}:
      do Result<&2, &2, String, J.Json>:
        v : J.Json <- Config.check(h, schema, path)
        rest : J.Json <- Config.check(t, schema, path)
        return J.JCons{v, rest}
    case J.JNil{}:
      Done{J.JNil{}}
    case x:
      Config.scalar(x, schema, path)

# Overlay only the finite schema. It gives a stable field order and retains
# explicit false values and empty lists. Null leaves retain chart defaults.
def Config.pick(fallback: J.Json, v: J.Json) -> J.Json:
  match v:
    case J.JNull{}:
      fallback
    case x:
      x

def Config.overlay(schema: J.Json, +v: J.Json) -> J.Json:
  match schema:
    case J.JObj{ms}:
      J.JObj{Config.overlay(ms, v)}
    case J.JMem{+k, d, t}:
      J.JMem{k, Config.overlay(d, J.Json.get(v, k)), Config.overlay(t, v)}
    case J.JNil{}:
      J.JNil{}
    case x:
      Config.pick(x, v)

def Config.bool(v: J.Json) -> Bool:
  match v:
    case J.JBool{b}:
      b
    case J.JStr{"true"}:
      True{}
    case _:
      False{}

def Config.enabled(c: J.Json, path: List<&2, String>) -> Bool:
  Config.bool(J.Json.at(c, path))

def Config.to_host(+c: J.Json, k: String) -> Bool:
  Config.enabled(c, ["sync", "toHost", k, "enabled"])

def Config.from_host(+c: J.Json, k: String) -> Bool:
  Config.enabled(c, ["sync", "fromHost", k, "enabled"])

def Config.bool_or(v: J.Json, d: Bool) -> Bool:
  match v:
    case J.JNull{}:
      d
    case x:
      Config.bool(x)

def Config.obj_or_empty(v: J.Json) -> J.Json:
  match v:
    case J.JNull{}:
      J.Json.obj([])
    case x:
      x

def Config.no_members(j: J.Json) -> Bool:
  match j:
    case J.JObj{J.JMem{k, v, t}}:
      False{}
    case _:
      True{}

# config/config.go IsVirtualSchedulerEnabled: controlPlane.distro.k8s.
# scheduler or controlPlane.advanced.virtualScheduler (chart default false).
def Config.virtual_scheduler(+c: J.Json) -> Bool:
  Bool.or(Config.enabled(c, ["controlPlane", "distro", "k8s", "scheduler", "enabled"]),
    Config.enabled(c, ["controlPlane", "advanced", "virtualScheduler", "enabled"]))

# networking.advanced.proxyKubelets (chart: both true).
def Config.proxy_by_hostname(+c: J.Json) -> Bool:
  Config.bool_or(J.Json.at(c, ["networking", "advanced", "proxyKubelets", "byHostname"]), True{})

def Config.proxy_by_ip(+c: J.Json) -> Bool:
  Config.bool_or(J.Json.at(c, ["networking", "advanced", "proxyKubelets", "byIP"]), True{})

# sync.fromHost.nodes.selector (chart: all false, labels {}).
def Config.nodes_all(+c: J.Json) -> Bool:
  Config.bool_or(J.Json.at(c, ["sync", "fromHost", "nodes", "selector", "all"]), False{})

def Config.nodes_labels(+c: J.Json) -> J.Json:
  Config.obj_or_empty(J.Json.at(c, ["sync", "fromHost", "nodes", "selector", "labels"]))

# pkg/config/config.go SchedulingInVirtualClusterEnabled (hybrid scheduling
# is outside the subset).
def Config.scheduler(+c: J.Json) -> Bool:
  Config.virtual_scheduler(c)

def Config.set(path: List<&2, String>, +c: J.Json, v: J.Json) -> J.Json:
  match path:
    case Nil{}:
      v
    case Con{+k, t}:
      J.Json.set(c, k, Config.set(t, J.Json.get(c, k), v))

def Config.select_all.if(go: Bool, +c: J.Json) -> J.Json:
  match go:
    case True{}:
      Config.set(["sync", "fromHost", "nodes", "selector", "all"], c, J.JBool{True{}})
    case False{}:
      c

# pkg/config/validation.go:58-61: scheduling in the virtual cluster without
# a node selector syncs every node.
def Config.select_all(+c: J.Json) -> J.Json:
  Config.select_all.if(Bool.and(Config.scheduler(c), Bool.and(Bool.not(Config.nodes_all(c)), Config.no_members(Config.nodes_labels(c)))), c)

def Config.graft.if(none: Bool, +path: List<&2, String>, +v: J.Json, +c: J.Json) -> J.Json:
  match none:
    case True{}:
      c
    case False{}:
      Config.set(path, c, J.Json.at(v, path))

# The document's value at path, when it has one.
def Config.graft(+path: List<&2, String>, +v: J.Json, +c: J.Json) -> J.Json:
  Config.graft.if(J.Json.is_null(J.Json.at(v, path)), path, v, c)

# The schema's keys outside the chart projection, as the document has them.
def Config.extras(+v: J.Json, +c: J.Json) -> J.Json:
  Config.graft(["sync", "fromHost", "nodes", "selector"], v,
    Config.graft(["networking", "advanced", "proxyKubelets"], v,
      Config.graft(["controlPlane", "advanced"], v, c)))

def Config.auto(v: J.Json, enabled: Bool) -> J.Json:
  match v enabled:
    case J.JStr{"auto"} True{}:
      J.JStr{"true"}
    case x _:
      x

def Config.auto_field(+c: J.Json, +k: String, enabled: Bool) -> J.Json:
  Config.set([k, "enabled"], c, Config.auto(J.Json.at(c, [k, "enabled"]), enabled))

# These four independent fields have the same work. Keep each side of
# the parallel call balanced, rather than forking a head against a tail.
def Config.autos(+fh: J.Json, +storage: Bool, +sc: Bool) -> J.Json:
  a b = Config.auto(J.Json.at(fh, ["csiDrivers", "enabled"]), storage) Config.auto(J.Json.at(fh, ["csiNodes", "enabled"]), storage)
  c d = Config.auto(J.Json.at(fh, ["csiStorageCapacities", "enabled"]), storage) Config.auto(J.Json.at(fh, ["storageClasses", "enabled"]), sc)
  Config.set(["storageClasses", "enabled"], Config.set(["csiStorageCapacities", "enabled"],
    Config.set(["csiNodes", "enabled"], Config.set(["csiDrivers", "enabled"], fh, a), b), c), d)

def Config.grants(v: J.Json) -> J.Json:
  match v:
    case J.JStr{""}:
      J.JStr{"auto"}
    case x:
      x

def Config.normalize(+c: J.Json) -> J.Json:
  Config.set(["sync", "toHost", "gatewayApi", "referenceGrants", "enabled"],
    Config.set(["sync", "fromHost"], c,
      Config.autos(J.Json.at(c, ["sync", "fromHost"]), Bool.and(Config.scheduler(c), Config.to_host(c, "persistentVolumeClaims")),
        Bool.and(Bool.and(Config.scheduler(c), Config.to_host(c, "persistentVolumeClaims")), Bool.not(Config.to_host(c, "storageClasses"))))),
    Config.grants(J.Json.at(c, ["sync", "toHost", "gatewayApi", "referenceGrants", "enabled"])))

def Config.when(b: Bool, msg: String) -> String:
  match b:
    case True{}:
      msg
    case False{}:
      ""

def Config.first(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{SNil{}, t}:
      Config.first(t)
    case Con{s, t}:
      s

def Config.valid_grants(v: J.Json) -> Bool:
  match v:
    case J.JStr{"auto"}:
      True{}
    case J.JStr{"true"}:
      True{}
    case J.JStr{"false"}:
      True{}
    case _:
      False{}

# ValidateConfigAndSetDefaults order, restricted to parsed keys. There are
# no CIDR, version, replica-range or backing-store-exclusivity checks in
# upstream validation.go for these fields. Do not invent such constraints.
# Mapping-bearing modes cannot be enabled without mappings; this subset
# intentionally does not accept their mapping configuration.
def Config.validate(+c: J.Json) -> String:
  Config.first([
    Config.when(Bool.not(Config.valid_grants(J.Json.at(c, ["sync", "toHost", "gatewayApi", "referenceGrants", "enabled"]))), "sync.toHost.gatewayApi.referenceGrants.enabled must be one of: auto, true, false"),
    Config.when(Config.from_host(c, "gateways"), "sync.fromHost.gateways.mappings.byName are empty"),
    Config.when(Bool.and(Config.scheduler(c), Bool.not(Config.from_host(c, "nodes"))), "sync.fromHost.nodes.enabled is false, but required if using hybrid scheduling or virtual scheduler"),
    Config.when(Bool.and(Config.from_host(c, "storageClasses"), Config.to_host(c, "storageClasses")), "you cannot enable both sync.fromHost.storageClasses.enabled and sync.toHost.storageClasses.enabled at the same time. Choose only one of them"),
    Config.when(Bool.and(Config.from_host(c, "priorityClasses"), Config.to_host(c, "priorityClasses")), "cannot sync priorityclasses to and from host at the same time"),
    Config.when(Bool.and(Config.to_host(c, "volumeSnapshotContents"), Bool.not(Config.to_host(c, "volumeSnapshots"))), "when syncing volume snapshots contents to the host, one must set sync.toHost.volumeSnapshots.enabled to true"),
    Config.when(Bool.and(Config.to_host(c, "volumeSnapshots"), Bool.not(Config.to_host(c, "volumeSnapshotContents"))), "when syncing volume snapshots to the host, one must set sync.toHost.volumeSnapshotContents.enabled to true"),
    Config.when(Config.from_host(c, "configMaps"), "config.sync.fromHost.configMaps.mappings are empty"),
    Config.when(Config.from_host(c, "secrets"), "config.sync.fromHost.secrets.mappings are empty"),
    Config.when(Config.to_host(c, "namespaces"), "namespace sync: config.sync.toHost.namespaces.mappings.byName are empty")])

def Config.validated(c: J.Json, err: String) -> Result<&2, &2, String, J.Json>:
  match err:
    case SNil{}:
      Done{c}
    case e:
      Fail{e}

def Config.document(v: J.Json) -> Result<&2, &2, String, J.Json>:
  match v:
    case J.JNull{}:
      Done{Config.defaults()}
    case J.JObj{m}:
      Config.check(J.JObj{m}, Config.schema(), "")
    case _:
      Fail{"config: expected a mapping document"}

def Config.parse(s: String) -> Result<&2, &2, String, J.Json>:
  do Result<&2, &2, String, J.Json>:
    raw : J.Json <- Y.Yaml.parse(String.trim(s))
    +checked : J.Json <- Config.document(raw)
    +c : J.Json = Config.normalize(Config.select_all(Config.extras(checked, Config.overlay(Config.defaults(), checked))))
    Config.validated(c, Config.validate(c))

def Config.value_result(r: Result<&2, &2, String, J.Json>, path: List<&2, String>) -> J.Json:
  match r:
    case Done{c}:
      J.Json.at(c, path)
    case Fail{e}:
      J.JNull{}

# Convenience queries for callers/tests. Production callers should first
# use parse, so that a parse failure cannot be confused with an absent key.
def Config.value(s: String, path: List<&2, String>) -> J.Json:
  Config.value_result(Config.parse(s), path)

def Config.error_result(r: Result<&2, &2, String, J.Json>) -> String:
  match r:
    case Done{c}:
      ""
    case Fail{e}:
      e

def Config.error(s: String) -> String:
  Config.error_result(Config.parse(s))

def Config.store(etcd: Bool) -> String:
  match etcd:
    case True{}:
      "etcd"
    case False{}:
      "sqlite"

def Config.backing_store(c: J.Json) -> String:
  Config.store(Config.enabled(c, ["controlPlane", "backingStore", "etcd", "embedded", "enabled"]))
