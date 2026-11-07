import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/translate/meta.bend as M
import ../src/translate/services.bend as S
import ../src/translate/nodes.bend as ND

# Tests for src/translate/nodes.bend. The laws in laws/nodes.bend transcribe
# vcluster's node and event syncer tests; these cover the rest: the virtual
# scheduler's allocatable (quantities, init and sidecar containers, pod-level
# requests, overhead), proxyKubelets byHostname and byIP, enforced
# tolerations, NODE_NAME, SyncToHost, the selector modes, DaemonSet pods,
# fake node addresses, and event kinds, force-sync, names and messages.
# Expected values follow vcluster's Go code and the Kubernetes resource
# package it calls (VClusterName "suffix", target namespace "test", as in
# vcluster's tests). Objects print in canonical form: keys sorted by byte,
# zero values left out.

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

# The value at a path of the canonical object.
def at(o: J.Json, path: List<&2, String>) -> String:
  show(J.Json.at(S.Svc.canon(o), path))

# The string at a path, as it is.
def raw(o: J.Json, path: List<&2, String>) -> String:
  S.Svc.str(J.Json.at(o, path))

def sp(a: String, b: String) -> String:
  a ++ " " ++ b

def pair(p: String & String) -> String:
  (a, b) = p
  a ++ "/" ++ b

def report(name: String, got: String, want: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name ++ ": got " ++ got ++ ", want " ++ want)

def check(name: String, +got: String, +want: String) -> IO(Unit):
  report(name, got, want, String.eq(got, want))

# Configurations.

# Every node syncs; proxy kubelets off; virtual scheduler on.
def sched() -> ND.Opts:
  ND.Opts{ND.SelAll{}, True{}, False{}, False{}, False{}, [], "", False{}}

# Every node syncs; proxy kubelets as given; these tolerations; NODE_NAME.
def opts(bh: Bool, bi: Bool, tols: List<&2, String>, env: String, on: Bool) -> ND.Opts:
  ND.Opts{ND.SelAll{}, False{}, False{}, bh, bi, tols, env, on}

def plain(tols: List<&2, String>) -> ND.Opts:
  opts(False{}, False{}, tols, "", False{})

def by_sel(sel: ND.Selector) -> ND.Opts:
  ND.Opts{sel, False{}, False{}, False{}, False{}, [], "", False{}}

def fake(bh: Bool, bi: Bool) -> ND.Fake:
  ND.Fake{bh, bi, "arm64", "2026-11-07T00:00:00Z", "b", "m", "s"}

def vnode() -> J.Json:
  js("{\"metadata\":{\"name\":\"n1\"}}")

# A node n1 with this status.
def node_status(st: String) -> J.Json:
  js("{\"metadata\":{\"name\":\"n1\"},\"status\":" ++ st ++ "}")

# Allocatable after a scheduler sync of host node n1 with this status.
def alloc(st: String, pods: List<&2, J.Json>) -> String:
  at(first(ND.Node.sync(cfg(), sched(), "", node_status(st), vnode(), [], [], pods)), ["status", "allocatable"])

def tainted() -> J.Json:
  js("{\"metadata\":{\"name\":\"n1\"},\"spec\":{\"taints\":[{\"key\":\"key1\",\"value\":\"value1\",\"effect\":\"NoSchedule\"},{\"key\":\"key2\",\"effect\":\"NoExecute\"}]}}")

def taints_with(tols: List<&2, String>) -> String:
  at(first(ND.Node.sync(cfg(), plain(tols), "", tainted(), vnode(), [], [], [])), ["spec", "taints"])

def vpod(node: String) -> J.Json:
  js("{\"metadata\":{\"name\":\"p\",\"namespace\":\"default\"},\"spec\":{\"nodeName\":\"" ++ node ++ "\"}}")

def qv(s: String, milli: Bool) -> String:
  ND.Qty.show(ND.Qty.value(s, milli))

def event(kind: String, name: String, message: String) -> J.Json:
  js("{\"metadata\":{\"name\":\"" ++ name ++ "\",\"namespace\":\"test\"},\"message\":\"" ++ message ++ "\",\"involvedObject\":{\"apiVersion\":\"v1\",\"kind\":\"" ++ kind ++ "\",\"name\":\"test-pod-x-test-x-suffix\",\"namespace\":\"test\"}}")

def vobj() -> J.Json:
  js("{\"metadata\":{\"name\":\"test-pod\",\"namespace\":\"test\",\"uid\":\"u1\",\"resourceVersion\":\"5\"}}")

def forced() -> J.Json:
  js("{\"metadata\":{\"name\":\"e1\",\"namespace\":\"test\",\"annotations\":{\"vcluster.loft.sh/force-sync\":\"true\"}},\"message\":\"m\",\"involvedObject\":{\"apiVersion\":\"apps/v1\",\"kind\":\"Deployment\",\"name\":\"d\",\"namespace\":\"test\"}}")

def main() -> IO(Unit):
  do IO<Unit>:
    # Quantities (k8s.io/apimachinery resource: Value and MilliValue round
    # up; String is the canonical form).
    check("milli value of 1.5", qv("1.5", True{}), "1500")
    check("value of 100m rounds up", qv("100m", False{}), "1")
    check("value of 1.1 rounds up", qv("1.1", False{}), "2")
    check("value of 1e3", qv("1e3", False{}), "1000")
    check("value of 2Ki", qv("2Ki", False{}), "2048")
    check("value of 0.5Gi", qv("0.5Gi", False{}), "536870912")
    check("value of 32Gi", qv("32Gi", False{}), "34359738368")
    check("value of empty", qv("", False{}), "0")
    check("DecimalSI 16000", ND.Qty.fmt_dec(ND.Qty.value("16000", False{})), "16k")
    check("DecimalSI 1500", ND.Qty.fmt_dec(ND.Qty.value("1500", False{})), "1500")
    check("milli 1500", ND.Qty.fmt_milli(ND.Qty.value("1500", False{})), "1500m")
    check("milli 16000", ND.Qty.fmt_milli(ND.Qty.value("16000", False{})), "16")
    check("milli 2000000", ND.Qty.fmt_milli(ND.Qty.value("2000000", False{})), "2k")
    check("BinarySI 1Mi", ND.Qty.fmt_bin(ND.Qty.value("1048576", False{})), "1Mi")
    check("BinarySI 32Gi", ND.Qty.fmt_bin(ND.Qty.value("34359738368", False{})), "32Gi")
    check("BinarySI 1500", ND.Qty.fmt_bin(ND.Qty.value("1500", False{})), "1500")
    check("BinarySI below 1024 is DecimalSI", ND.Qty.fmt_bin(ND.Qty.value("1000", False{})), "1k")
    # Virtual scheduler allocatable (nodes/translate.go:166-260).
    check("allocatable less non-vcluster running pods on the node",
      alloc("{\"capacity\":{\"cpu\":\"4\",\"memory\":\"8Gi\",\"ephemeral-storage\":\"100Gi\",\"pods\":\"110\"},\"allocatable\":{\"cpu\":\"4\",\"memory\":\"8Gi\",\"ephemeral-storage\":\"100Gi\",\"pods\":\"110\"}}",
        [js("{\"metadata\":{\"name\":\"a\"},\"spec\":{\"nodeName\":\"n1\",\"containers\":[{\"resources\":{\"requests\":{\"cpu\":\"500m\",\"memory\":\"1Gi\"}}}]},\"status\":{\"phase\":\"Running\"}}"),
         js("{\"metadata\":{\"name\":\"b\",\"labels\":{\"vcluster.loft.sh/managed-by\":\"suffix\"}},\"spec\":{\"nodeName\":\"n1\",\"containers\":[{\"resources\":{\"requests\":{\"cpu\":\"1\"}}}]}}"),
         js("{\"metadata\":{\"name\":\"c\"},\"spec\":{\"nodeName\":\"n1\",\"containers\":[{\"resources\":{\"requests\":{\"cpu\":\"1\"}}}]},\"status\":{\"phase\":\"Succeeded\"}}"),
         js("{\"metadata\":{\"name\":\"d\"},\"spec\":{\"nodeName\":\"n2\",\"containers\":[{\"resources\":{\"requests\":{\"cpu\":\"1\"}}}]}}")]),
      "{\"cpu\":\"3500m\",\"ephemeral-storage\":\"100Gi\",\"memory\":\"7Gi\",\"pods\":\"110\"}")
    check("allocatable takes the larger init container",
      alloc("{\"capacity\":{\"cpu\":\"2\",\"memory\":\"1000Mi\",\"ephemeral-storage\":\"2000\",\"pods\":\"110\"},\"allocatable\":{\"cpu\":\"2\",\"memory\":\"1000Mi\",\"ephemeral-storage\":\"2000\",\"pods\":\"110\"}}",
        [js("{\"metadata\":{\"name\":\"a\"},\"spec\":{\"nodeName\":\"n1\",\"containers\":[{\"resources\":{\"requests\":{\"cpu\":\"100m\",\"memory\":\"100M\",\"ephemeral-storage\":\"1000\"}}}],\"initContainers\":[{\"resources\":{\"requests\":{\"cpu\":\"1\"}}}]}}")]),
      "{\"cpu\":\"1\",\"ephemeral-storage\":\"1k\",\"memory\":\"948576000\",\"pods\":\"110\"}")
    check("allocatable counts sidecars and overhead, merges virtual capacity",
      at(first(ND.Node.sync(cfg(), sched(), "", node_status("{\"capacity\":{\"cpu\":\"1\"},\"allocatable\":{\"cpu\":\"1\"}}"),
          js("{\"metadata\":{\"name\":\"n1\"},\"status\":{\"capacity\":{\"nvidia.com/gpu\":\"1\"}}}"), [], [],
          [js("{\"metadata\":{\"name\":\"a\"},\"spec\":{\"nodeName\":\"n1\",\"overhead\":{\"cpu\":\"100m\"},\"containers\":[{\"resources\":{\"requests\":{\"cpu\":\"200m\"}}}],\"initContainers\":[{\"restartPolicy\":\"Always\",\"resources\":{\"requests\":{\"cpu\":\"300m\"}}},{\"resources\":{\"requests\":{\"cpu\":\"500m\"}}}]}}")])), ["status"]),
      "{\"allocatable\":{\"cpu\":\"100m\",\"nvidia.com/gpu\":\"1\"},\"capacity\":{\"cpu\":\"1\",\"nvidia.com/gpu\":\"1\"}}")
    check("allocatable stays when requests exceed it",
      alloc("{\"capacity\":{\"cpu\":\"1\"},\"allocatable\":{\"cpu\":\"1\"}}",
        [js("{\"metadata\":{\"name\":\"a\"},\"spec\":{\"nodeName\":\"n1\",\"containers\":[{\"resources\":{\"requests\":{\"cpu\":\"2\"}}}]}}")]),
      "{\"cpu\":\"1\"}")
    check("pod-level requests replace the containers'",
      alloc("{\"capacity\":{\"cpu\":\"1\"},\"allocatable\":{\"cpu\":\"1\"}}",
        [js("{\"metadata\":{\"name\":\"a\"},\"spec\":{\"nodeName\":\"n1\",\"resources\":{\"requests\":{\"cpu\":\"300m\"}},\"containers\":[{\"resources\":{\"requests\":{\"cpu\":\"1\"}}}]}}")]),
      "{\"cpu\":\"700m\"}")
    # proxyKubelets (nodes/translate.go:125-163).
    check("byHostname and byIP rewrite addresses and the kubelet port",
      at(first(ND.Node.sync(cfg(), opts(True{}, True{}, [], "", False{}), "10.0.0.5",
          js("{\"metadata\":{\"name\":\"node.example.com\"},\"status\":{\"addresses\":[{\"type\":\"InternalIP\",\"address\":\"192.168.1.2\"},{\"type\":\"ExternalIP\",\"address\":\"1.2.3.4\"},{\"type\":\"Hostname\",\"address\":\"h\"}],\"daemonEndpoints\":{\"kubeletEndpoint\":{\"Port\":12345}}}}"),
          js("{\"metadata\":{\"name\":\"node.example.com\"}}"), [], [], [])), ["status"]),
      "{\"addresses\":[{\"address\":\"node-example-com.nodes.vcluster.com\",\"type\":\"Hostname\"},{\"address\":\"10.0.0.5\",\"type\":\"InternalIP\"},{\"address\":\"1.2.3.4\",\"type\":\"ExternalIP\"}],\"daemonEndpoints\":{\"kubeletEndpoint\":{\"Port\":10250}}}")
    check("without proxy kubelets the status stays",
      at(first(ND.Node.sync(cfg(), plain([]), "10.0.0.5",
          node_status("{\"addresses\":[{\"type\":\"InternalIP\",\"address\":\"192.168.1.2\"}],\"daemonEndpoints\":{\"kubeletEndpoint\":{\"Port\":12345}}}"), vnode(), [], [], [])), ["status"]),
      "{\"addresses\":[{\"address\":\"192.168.1.2\",\"type\":\"InternalIP\"}],\"daemonEndpoints\":{\"kubeletEndpoint\":{\"Port\":12345}}}")
    # Enforced tolerations (nodes/translate.go:104-107, 298-324).
    check("no tolerations keep every taint", taints_with([]),
      "[{\"effect\":\"NoSchedule\",\"key\":\"key1\",\"value\":\"value1\"},{\"effect\":\"NoExecute\",\"key\":\"key2\"}]")
    check("an Equal toleration drops its taint", taints_with(["key1=value1:NoSchedule"]),
      "[{\"effect\":\"NoExecute\",\"key\":\"key2\"}]")
    check("an Exists toleration drops its taint", taints_with(["key1:NoSchedule"]),
      "[{\"effect\":\"NoExecute\",\"key\":\"key2\"}]")
    check("a toleration without effect has no operator", taints_with(["key1=value1"]),
      "[{\"effect\":\"NoSchedule\",\"key\":\"key1\",\"value\":\"value1\"},{\"effect\":\"NoExecute\",\"key\":\"key2\"}]")
    check("another value does not tolerate", taints_with(["key1=value2:NoSchedule"]),
      "[{\"effect\":\"NoSchedule\",\"key\":\"key1\",\"value\":\"value1\"},{\"effect\":\"NoExecute\",\"key\":\"key2\"}]")
    check("another effect does not tolerate", taints_with(["key1=value1:NoExecute"]),
      "[{\"effect\":\"NoSchedule\",\"key\":\"key1\",\"value\":\"value1\"},{\"effect\":\"NoExecute\",\"key\":\"key2\"}]")
    check("an invalid toleration is skipped", taints_with(["key1=v@l:NoSchedule"]),
      "[{\"effect\":\"NoSchedule\",\"key\":\"key1\",\"value\":\"value1\"},{\"effect\":\"NoExecute\",\"key\":\"key2\"}]")
    check("* tolerates everything", taints_with(["*"]), "null")
    check("original-taints keeps the host taints as Go JSON",
      raw(first(ND.Node.sync(cfg(), plain([]), "", tainted(), vnode(), [], [], [])), ["metadata", "annotations", "vcluster.loft.sh/original-taints"]),
      "[\"{\\\"key\\\":\\\"key1\\\",\\\"value\\\":\\\"value1\\\",\\\"effect\\\":\\\"NoSchedule\\\"}\",\"{\\\"key\\\":\\\"key2\\\",\\\"effect\\\":\\\"NoExecute\\\"}\"]")
    # NODE_NAME (nodes/translate.go:108-112).
    check("NODE_NAME on this node disables scale down",
      at(first(ND.Node.sync(cfg(), opts(False{}, False{}, [], "n1", True{}), "", vnode(), vnode(), [], [], [])), ["metadata", "annotations"]),
      "{\"cluster-autoscaler.kubernetes.io/scale-down-disabled\":\"true\"}")
    check("NODE_NAME on another node does not",
      at(first(ND.Node.sync(cfg(), opts(False{}, False{}, [], "n2", True{}), "", vnode(), vnode(), [], [], [])), ["metadata", "annotations"]),
      "null")
    check("sync sets the managed-by label",
      at(first(ND.Node.sync(cfg(), plain([]), "", vnode(), vnode(), [], [], [])), ["metadata", "labels"]),
      "{\"vcluster.loft.sh/managed-by\":\"suffix\"}")
    # SyncToHost (nodes/syncer.go:278-286).
    check("SyncToHost deletes a node vcluster made",
      show_out(ND.Node.sync_to_host(cfg(), None{}, js("{\"metadata\":{\"name\":\"n1\",\"labels\":{\"vcluster.loft.sh/managed-by\":\"suffix\"}}}"))),
      "virtual delete /n1; done")
    check("SyncToHost keeps a node vcluster did not make",
      show_out(ND.Node.sync_to_host(cfg(), None{}, vnode())), "done")
    check("SyncToHost deletes a node whose host node went",
      show_out(ND.Node.sync_to_host(cfg(), Some{vnode()}, vnode())), "virtual delete /n1; done")
    # Selector modes (nodes/syncer.go:38-44, 357-373).
    check("selector all syncs a node no pod needs",
      show_out(ND.Node.sync(cfg(), by_sel(ND.SelAll{}), "", vnode(), vnode(), [], [], [])), "virtual update; done")
    check("empty selector labels act as no selector",
      show_out(ND.Node.sync(cfg(), by_sel(ND.SelLabels{[]}), "", vnode(), vnode(), [], [], [])), "virtual delete /n1; done")
    check("a managed host pod needs the node",
      show_out(ND.Node.sync_to_virtual(by_sel(ND.SelNone{}), vnode(), [], [vpod("n1")])), "virtual create; requeue")
    check("a virtual DaemonSet pod does not need the node",
      show_out(ND.Node.sync_to_virtual(by_sel(ND.SelNone{}), vnode(),
        [js("{\"metadata\":{\"name\":\"p\",\"ownerReferences\":[{\"apiVersion\":\"apps/v1\",\"kind\":\"DaemonSet\",\"name\":\"ds\"}]},\"spec\":{\"nodeName\":\"n1\"}}")], [])),
      "done")
    check("a virtual ReplicaSet pod needs the node",
      show_out(ND.Node.sync_to_virtual(by_sel(ND.SelNone{}), vnode(),
        [js("{\"metadata\":{\"name\":\"p\",\"ownerReferences\":[{\"apiVersion\":\"apps/v1\",\"kind\":\"ReplicaSet\",\"name\":\"rs\"}]},\"spec\":{\"nodeName\":\"n1\"}}")], [])),
      "virtual create; requeue")
    check("a host DaemonSet pod does not need the node",
      show_out(ND.Node.sync_to_virtual(by_sel(ND.SelNone{}), vnode(), [],
        [js("{\"metadata\":{\"name\":\"p\",\"annotations\":{\"vcluster.loft.sh/owner-set-kind\":\"DaemonSet\"}},\"spec\":{\"nodeName\":\"n1\"}}")])),
      "done")
    check("a pod on another node does not need the node",
      show_out(ND.Node.sync_to_virtual(by_sel(ND.SelNone{}), vnode(), [vpod("n2")], [])), "done")
    # Fake nodes (nodes/fake_syncer.go).
    check("fake node with byIP has both addresses",
      at(first(ND.Node.fake_sync_to_virtual(fake(True{}, True{}), "n1", "10.0.0.5", [vpod("n1")], [])), ["status", "addresses"]),
      "[{\"address\":\"n1.nodes.vcluster.com\",\"type\":\"Hostname\"},{\"address\":\"10.0.0.5\",\"type\":\"InternalIP\"}]")
    check("fake node without proxy kubelets has no addresses",
      at(first(ND.Node.fake_sync_to_virtual(fake(False{}, False{}), "n1", "10.0.0.5", [vpod("n1")], [])), ["status", "addresses"]),
      "null")
    check("fake node labels carry the arch and hostname",
      at(first(ND.Node.fake_sync_to_virtual(fake(True{}, False{}), "n1", "", [vpod("n1")], [])), ["metadata", "labels"]),
      "{\"beta.kubernetes.io/arch\":\"arm64\",\"beta.kubernetes.io/os\":\"linux\",\"kubernetes.io/arch\":\"arm64\",\"kubernetes.io/hostname\":\"fake-n1\",\"kubernetes.io/os\":\"linux\",\"vcluster.loft.sh/fake-node\":\"true\"}")
    check("fake node nodeInfo architecture is always amd64",
      at(first(ND.Node.fake_sync_to_virtual(fake(True{}, False{}), "n1", "", [vpod("n1")], [])), ["status", "nodeInfo", "architecture"]),
      "\"amd64\"")
    check("fake node update always sets the hostname",
      at(first(ND.Node.fake_sync(fake(False{}, False{}), "", vnode(), [vpod("n1")], [])), ["status", "addresses"]),
      "[{\"address\":\"n1.nodes.vcluster.com\",\"type\":\"Hostname\"}]")
    check("fake node with its addresses is not updated",
      show_out(ND.Node.fake_sync(fake(True{}, False{}), "", node_status("{\"addresses\":[{\"type\":\"Hostname\",\"address\":\"n1.nodes.vcluster.com\"}]}"), [vpod("n1")], [])),
      "done")
    check("no fake node for a DaemonSet pod",
      show_out(ND.Node.fake_sync_to_virtual(fake(True{}, False{}), "n1", "", [],
        [js("{\"metadata\":{\"name\":\"p\",\"annotations\":{\"vcluster.loft.sh/owner-set-kind\":\"DaemonSet\"}},\"spec\":{\"nodeName\":\"n1\"}}")])),
      "done")
    # Events (events/translate.go, mappings/resources/events.go).
    check("events of Endpoints are not synced (the kind is Endpoint)",
      show_out(ND.Ev.sync_to_virtual(event("Endpoints", "e1", ""), Some{vobj()}, ["test"])), "done")
    check("events of kind Endpoint are synced",
      show_out(ND.Ev.sync_to_virtual(event("Endpoint", "e1", ""), Some{vobj()}, ["test"])), "virtual create; done")
    check("events in a missing namespace are not created",
      show_out(ND.Ev.sync_to_virtual(event("Pod", "e1", ""), Some{vobj()}, ["other"])), "done")
    check("event name and message point at the virtual pod",
      sp(raw(first(ND.Ev.sync_to_virtual(event("Pod", "test-pod-x-test-x-suffix.17a8b", "Successfully assigned test/test-pod-x-test-x-suffix to node1"), Some{vobj()}, ["test"])), ["metadata", "name"]),
        raw(first(ND.Ev.sync_to_virtual(event("Pod", "test-pod-x-test-x-suffix.17a8b", "Successfully assigned test/test-pod-x-test-x-suffix to node1"), Some{vobj()}, ["test"])), ["message"])),
      "test-pod.17a8b Successfully assigned test/test-pod to node1")
    check("event message names are replaced",
      raw(first(ND.Ev.sync_to_virtual(event("Pod", "e1", "pod test-pod-x-test-x-suffix failed"), Some{vobj()}, ["test"])), ["message"]),
      "pod test-pod failed")
    check("event involved object takes the virtual UID and version",
      at(first(ND.Ev.sync_to_virtual(event("Pod", "e1", ""), Some{vobj()}, ["test"])), ["involvedObject"]),
      "{\"apiVersion\":\"v1\",\"kind\":\"Pod\",\"name\":\"test-pod\",\"namespace\":\"test\",\"resourceVersion\":\"5\",\"uid\":\"u1\"}")
    check("force-synced event goes to default",
      sp(at(first(ND.Ev.sync_to_virtual(forced(), None{}, ["default"])), ["involvedObject"]),
        at(first(ND.Ev.sync_to_virtual(forced(), None{}, ["default"])), ["metadata"])),
      "{\"namespace\":\"default\"} {\"name\":\"e1\",\"namespace\":\"default\"}")
    check("force-synced event needs namespace default",
      show_out(ND.Ev.sync_to_virtual(forced(), None{}, ["test"])), "done")
    check("unmatched event without force-sync is skipped",
      show_out(ND.Ev.sync_to_virtual(event("Pod", "e1", ""), None{}, ["test"])), "done")
    check("event mapping",
      sp(pair(ND.Ev.virtual_ref(event("Pod", "test-pod-x-test-x-suffix.1", ""), Some{vobj()})),
        sp(pair(ND.Ev.virtual_ref(forced(), None{})), pair(ND.Ev.virtual_ref(event("Pod", "e1", ""), None{})))),
      "test/test-pod.1 default/e1 /")
    check("event in sync is not updated",
      show_out(ND.Ev.sync(event("Pod", "e1", ""), Some{vobj()},
        js("{\"metadata\":{\"name\":\"e1\",\"namespace\":\"test\"},\"involvedObject\":{\"apiVersion\":\"v1\",\"kind\":\"Pod\",\"name\":\"test-pod\",\"namespace\":\"test\",\"uid\":\"u1\",\"resourceVersion\":\"5\"}}"))),
      "done")
    check("events are never synced to the host", show_out(ND.Ev.sync_to_host()), "done")
    check("ReplaceAll with an empty old string", ND.Ev.replace_all("ab", "", "X"), "XaXbX")
    check("ReplaceAll does not overlap", ND.Ev.replace_all("aaa", "aa", "b"), "ba")
