import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/translate/meta.bend as M
import ../src/translate/services.bend as S
import ../src/translate/nodes.bend as ND

# Spec for src/translate/nodes.bend (vcluster
# pkg/controllers/resources/nodes and pkg/controllers/resources/events).
#
# The concrete laws transcribe every case of nodes/translate_test.go,
# nodes/syncer_test.go, nodes/fake_syncer_test.go and events/syncer_test.go
# (vcluster a8ab30e). vcluster's tests run with VClusterName "suffix",
# target namespace "test" and current namespace "vcluster", and with the
# default config: proxyKubelets.byHostname true; the node tests set byIP
# false.
#
# Objects compare in canonical form (S.Svc.canon_outcome): member order does
# not count, and null, false, 0, [] and {} count as absent. The test harness
# strips the vcluster.loft.sh/managed-by label before it compares
# (pkg/syncer/testing/testing.go:228-231); the laws keep it, as the node
# syncer writes it. A step that changes the virtual node is a VirtualUpdate
# of the whole node.

# Test fixtures.

def Laws.nodes.cfg() -> S.Cfg:
  S.Cfg{"suffix", "test", "vcluster"}

def Laws.nodes.str(k: String, v: String) -> J.KV:
  J.KV{k, J.JStr{v}}

def Laws.nodes.num(k: String, v: String) -> J.KV:
  J.KV{k, J.JNum{v}}

def Laws.nodes.obj(k: String, fs: List<&2, J.KV>) -> J.KV:
  J.KV{k, J.Json.obj(fs)}

def Laws.nodes.arr(k: String, xs: List<&2, J.Json>) -> J.KV:
  J.KV{k, J.Json.arr(xs)}

def Laws.nodes.out(ws: List<&2, S.Write>) -> S.Outcome:
  S.Svc.canon_outcome(S.Outcome{ws, S.NoRequeue{}})

# The node syncer of the syncer tests: the given selector, clearImageStatus
# and enforced tolerations; no virtual scheduler, byHostname on, byIP off,
# NODE_NAME unset.
def Laws.nodes.opts(sel: ND.Selector, clear: Bool, tols: List<&2, String>) -> ND.Opts:
  ND.Opts{sel, False{}, clear, True{}, False{}, tols, "", False{}}

# The zero nodeSyncer of translate_test.go.
def Laws.nodes.bare() -> ND.Opts:
  ND.Opts{ND.SelNone{}, False{}, False{}, False{}, False{}, [], "", False{}}

def Laws.nodes.taint(k: String, v: String, e: String) -> J.Json:
  J.Json.obj([Laws.nodes.str("key", k), Laws.nodes.str("value", v), Laws.nodes.str("effect", e)])

# {Key: node.kubernetes.io/not-ready, Value: true, Effect: NoSchedule}
def Laws.nodes.not_ready() -> J.Json:
  Laws.nodes.taint("node.kubernetes.io/not-ready", "true", "NoSchedule")

# {Key: custom-taint, Value: true, Effect: NoExecute}
def Laws.nodes.custom() -> J.Json:
  Laws.nodes.taint("custom-taint", "true", "NoExecute")

# {Key: key1, Value: value1, Effect: NoSchedule}
def Laws.nodes.key1() -> J.Json:
  Laws.nodes.taint("key1", "value1", "NoSchedule")

def Laws.nodes.taints_annotation() -> String:
  "vcluster.loft.sh/original-taints"

# mustMarshal([]string{mustMarshal(&notReady)})
def Laws.nodes.not_ready_ann() -> J.KV:
  Laws.nodes.str(Laws.nodes.taints_annotation(), "[\"{\\\"key\\\":\\\"node.kubernetes.io/not-ready\\\",\\\"value\\\":\\\"true\\\",\\\"effect\\\":\\\"NoSchedule\\\"}\"]")

# mustMarshal([]string{mustMarshal(&customTaint)})
def Laws.nodes.custom_ann() -> J.KV:
  Laws.nodes.str(Laws.nodes.taints_annotation(), "[\"{\\\"key\\\":\\\"custom-taint\\\",\\\"value\\\":\\\"true\\\",\\\"effect\\\":\\\"NoExecute\\\"}\"]")

# The TaintsAnnotation value of syncer_test.go's taint cases.
def Laws.nodes.key1_ann() -> J.KV:
  Laws.nodes.str(Laws.nodes.taints_annotation(), "[\"{\\\"key\\\":\\\"key1\\\",\\\"value\\\":\\\"value1\\\",\\\"effect\\\":\\\"NoSchedule\\\"}\"]")

# A node with this metadata, spec and status.
def Laws.nodes.node(meta: List<&2, J.KV>, spec: List<&2, J.KV>, status: List<&2, J.KV>) -> J.Json:
  J.Json.obj([Laws.nodes.obj("metadata", meta), Laws.nodes.obj("spec", spec), Laws.nodes.obj("status", status)])

# A node with these annotations, labels and taints, as translate_test.go
# compares it.
def Laws.nodes.tb(annotations: List<&2, J.KV>, labels: List<&2, J.KV>, taints: List<&2, J.Json>) -> J.Json:
  Laws.nodes.node([Laws.nodes.obj("annotations", annotations), Laws.nodes.obj("labels", labels)], [Laws.nodes.arr("taints", taints)], [])

# What translate_test.go asserts of a node: annotations, labels, taints.
def Laws.nodes.view(+n: J.Json) -> J.Json:
  S.Svc.canon(J.Json.obj([J.KV{"annotations", J.Json.at(n, ["metadata", "annotations"])}, J.KV{"labels", J.Json.at(n, ["metadata", "labels"])},
    J.KV{"taints", J.Json.at(n, ["spec", "taints"])}]))

# nodes/translate_test.go TestTranslateBackwards: translateUpdateBackwards(pNode, vNode).

# "simple"
law nodes.backwards_simple:
  {Laws.nodes.view(ND.Node.backwards(Laws.nodes.bare(),
      Laws.nodes.tb([Laws.nodes.str("test", "test")], [Laws.nodes.str("test", "test")], []),
      Laws.nodes.tb([], [Laws.nodes.str("test", "test")], [Laws.nodes.taint("test", "true", "NoSchedule")])))
    == Laws.nodes.view(Laws.nodes.tb([Laws.nodes.str("test", "test"), Laws.nodes.str("vcluster.loft.sh/managed-annotations", "test"),
      Laws.nodes.str("vcluster.loft.sh/managed-labels", "test")], [Laws.nodes.str("test", "test")], [Laws.nodes.taint("test", "true", "NoSchedule")])) : J.Json}

# "not-ready-1"
law nodes.backwards_not_ready_1:
  {Laws.nodes.view(ND.Node.backwards(Laws.nodes.bare(), Laws.nodes.tb([], [], [Laws.nodes.not_ready()]), Laws.nodes.tb([], [], [])))
    == Laws.nodes.view(Laws.nodes.tb([Laws.nodes.not_ready_ann()], [], [Laws.nodes.not_ready()])) : J.Json}

# "not-ready-2"
law nodes.backwards_not_ready_2:
  {Laws.nodes.view(ND.Node.backwards(Laws.nodes.bare(), Laws.nodes.tb([], [], []), Laws.nodes.tb([Laws.nodes.not_ready_ann()], [], [Laws.nodes.not_ready()])))
    == Laws.nodes.view(Laws.nodes.tb([], [], [])) : J.Json}

# "not-ready-3"
law nodes.backwards_not_ready_3:
  {Laws.nodes.view(ND.Node.backwards(Laws.nodes.bare(), Laws.nodes.tb([], [], []), Laws.nodes.tb([], [], [Laws.nodes.not_ready()])))
    == Laws.nodes.view(Laws.nodes.tb([], [], [])) : J.Json}

# "custom-taint-1"
law nodes.backwards_custom_taint_1:
  {Laws.nodes.view(ND.Node.backwards(Laws.nodes.bare(), Laws.nodes.tb([], [], [Laws.nodes.custom()]), Laws.nodes.tb([], [], [])))
    == Laws.nodes.view(Laws.nodes.tb([Laws.nodes.custom_ann()], [], [Laws.nodes.custom()])) : J.Json}

# "custom-taint-2"
law nodes.backwards_custom_taint_2:
  {Laws.nodes.view(ND.Node.backwards(Laws.nodes.bare(), Laws.nodes.tb([], [], []), Laws.nodes.tb([Laws.nodes.custom_ann()], [], [Laws.nodes.custom()])))
    == Laws.nodes.view(Laws.nodes.tb([], [], [])) : J.Json}

# "custom-taint-3"
law nodes.backwards_custom_taint_3:
  {Laws.nodes.view(ND.Node.backwards(Laws.nodes.bare(), Laws.nodes.tb([], [], []), Laws.nodes.tb([], [], [Laws.nodes.custom()])))
    == Laws.nodes.view(Laws.nodes.tb([], [], [Laws.nodes.custom()])) : J.Json}

# nodes/syncer_test.go fixtures.

# basePod
def Laws.nodes.pod() -> J.Json:
  J.Json.obj([Laws.nodes.obj("metadata", [Laws.nodes.str("name", "mypod")]), Laws.nodes.obj("spec", [Laws.nodes.str("nodeName", "mynode")])])

# {Address: GetNodeHost("mynode"), Type: NodeHostName}
def Laws.nodes.host_address() -> J.Json:
  J.Json.obj([Laws.nodes.str("address", "mynode.nodes.vcluster.com"), Laws.nodes.str("type", "Hostname")])

def Laws.nodes.endpoints(port: String) -> J.KV:
  Laws.nodes.obj("daemonEndpoints", [Laws.nodes.obj("kubeletEndpoint", [Laws.nodes.num("Port", port)])])

def Laws.nodes.marker() -> J.KV:
  Laws.nodes.str("vcluster.loft.sh/managed-by", "suffix")

# baseNode with the test case's host labels, images and taints.
def Laws.nodes.pnode(labels: List<&2, J.KV>, taints: List<&2, J.Json>, images: List<&2, J.Json>) -> J.Json:
  Laws.nodes.node([Laws.nodes.str("name", "mynode"), Laws.nodes.obj("labels", labels)], [Laws.nodes.arr("taints", taints)],
    [Laws.nodes.endpoints("0"), Laws.nodes.arr("images", images)])

# baseNode
def Laws.nodes.base_node() -> J.Json:
  Laws.nodes.pnode([], [], [])

# baseVNode with these labels, annotations, taints and images.
def Laws.nodes.vnode(labels: List<&2, J.KV>, annotations: List<&2, J.KV>, taints: List<&2, J.Json>, images: List<&2, J.Json>) -> J.Json:
  Laws.nodes.node([Laws.nodes.str("name", "mynode"), Laws.nodes.obj("labels", labels), Laws.nodes.obj("annotations", annotations)],
    [Laws.nodes.arr("taints", taints)],
    [Laws.nodes.arr("addresses", [Laws.nodes.host_address()]), Laws.nodes.endpoints("10250"), Laws.nodes.arr("images", images)])

# baseVNode
def Laws.nodes.base_vnode() -> J.Json:
  Laws.nodes.vnode([], [], [], [])

# editedNode with these labels.
def Laws.nodes.edited(labels: List<&2, J.KV>) -> J.Json:
  Laws.nodes.node([Laws.nodes.str("name", "mynode"), Laws.nodes.obj("labels", labels),
      Laws.nodes.obj("annotations", [Laws.nodes.str("test", "true"), Laws.nodes.str("vcluster.loft.sh/managed-annotations", "test"),
        Laws.nodes.str("vcluster.loft.sh/managed-labels", "test")])], [],
    [Laws.nodes.arr("addresses", [Laws.nodes.host_address()]), Laws.nodes.endpoints("10250"), Laws.nodes.obj("nodeInfo", [Laws.nodes.str("architecture", "amd64")])])

# imagesPhysicalNode
def Laws.nodes.images() -> List<&2, J.Json>:
  [J.Json.obj([Laws.nodes.arr("names", [J.JStr{"ghcr.io/jetpack/calico"}])])]

def Laws.nodes.none() -> ND.Opts:
  Laws.nodes.opts(ND.SelNone{}, False{}, [])

def Laws.nodes.labeled() -> ND.Opts:
  Laws.nodes.opts(ND.SelLabels{[M.KV{"test", "true"}]}, False{}, [])

def Laws.nodes.update(n: J.Json) -> S.Outcome:
  Laws.nodes.out([S.VirtualUpdate{n}])

def Laws.nodes.delete() -> S.Outcome:
  Laws.nodes.out([S.VirtualDelete{"", "mynode"}])

# nodes/syncer_test.go TestSyncToVirtual: SyncToVirtual(baseNode).

# "Create backward": a virtual pod needs the node.
law nodes.create_backward:
  {S.Svc.canon_outcome(ND.Node.sync_to_virtual(Laws.nodes.none(), Laws.nodes.base_node(), [Laws.nodes.pod()], []))
    == S.Svc.canon_outcome(S.Outcome{[S.VirtualCreate{Laws.nodes.node([Laws.nodes.str("name", "mynode")], [], [])}], S.RequeueNow{}}) : S.Outcome}

# "Create backward not needed".
law nodes.create_backward_not_needed:
  {S.Svc.canon_outcome(ND.Node.sync_to_virtual(Laws.nodes.none(), Laws.nodes.base_node(), [], []))
    == Laws.nodes.out([]) : S.Outcome}

# nodes/syncer_test.go TestSyncBothExist: Sync(NewSyncEvent(physical,
# initialVNode)). The test sets physicalAnnotations on no object, so the
# host node has no annotations in any case.

# "Update backward no change"
law nodes.update_backward_no_change:
  {S.Svc.canon_outcome(ND.Node.sync(Laws.nodes.cfg(), Laws.nodes.none(), "", Laws.nodes.base_node(), Laws.nodes.base_vnode(), [Laws.nodes.pod()], [], []))
    == Laws.nodes.update(Laws.nodes.vnode([Laws.nodes.marker()], [], [], [])) : S.Outcome}

# "Update backward": the host node is editedNode.
law nodes.update_backward:
  {S.Svc.canon_outcome(ND.Node.sync(Laws.nodes.cfg(), Laws.nodes.none(), "", Laws.nodes.edited([Laws.nodes.str("test", "true")]), Laws.nodes.base_vnode(), [Laws.nodes.pod()], [], []))
    == Laws.nodes.update(Laws.nodes.edited([Laws.nodes.str("test", "true"), Laws.nodes.marker()])) : S.Outcome}

# "Delete backward": no pod needs the node.
law nodes.delete_backward:
  {S.Svc.canon_outcome(ND.Node.sync(Laws.nodes.cfg(), Laws.nodes.none(), "", Laws.nodes.base_node(), Laws.nodes.base_vnode(), [], [], []))
    == Laws.nodes.delete() : S.Outcome}

# "Label Matched and enforceNodeSelector false - expect node to be synced
# from NodeSelector"
law nodes.label_matched:
  {S.Svc.canon_outcome(ND.Node.sync(Laws.nodes.cfg(), Laws.nodes.labeled(), "", Laws.nodes.pnode([Laws.nodes.str("test", "true")], [], []), Laws.nodes.base_vnode(), [], [], []))
    == Laws.nodes.update(Laws.nodes.vnode([Laws.nodes.str("test", "true"), Laws.nodes.marker()], [Laws.nodes.str("vcluster.loft.sh/managed-labels", "test")], [], [])) : S.Outcome}

# "Label Not Matched and enforceNodeSelector true - expect node not to be
# synced"
law nodes.label_not_matched:
  {S.Svc.canon_outcome(ND.Node.sync(Laws.nodes.cfg(), Laws.nodes.labeled(), "", Laws.nodes.base_node(), Laws.nodes.base_vnode(), [], [], []))
    == Laws.nodes.delete() : S.Outcome}

# "Clear Nodes"
law nodes.clear_nodes:
  {S.Svc.canon_outcome(ND.Node.sync(Laws.nodes.cfg(), Laws.nodes.opts(ND.SelNone{}, True{}, []), "", Laws.nodes.pnode([], [], Laws.nodes.images()), Laws.nodes.base_vnode(), [Laws.nodes.pod()], [], []))
    == Laws.nodes.update(Laws.nodes.vnode([Laws.nodes.marker()], [], [], [])) : S.Outcome}

# "Don't Clear Nodes"
law nodes.dont_clear_nodes:
  {S.Svc.canon_outcome(ND.Node.sync(Laws.nodes.cfg(), Laws.nodes.none(), "", Laws.nodes.pnode([], [], Laws.nodes.images()), Laws.nodes.base_vnode(), [Laws.nodes.pod()], [], []))
    == Laws.nodes.update(Laws.nodes.vnode([Laws.nodes.marker()], [], [], Laws.nodes.images())) : S.Outcome}

# "Matching taints"
law nodes.matching_taints:
  {S.Svc.canon_outcome(ND.Node.sync(Laws.nodes.cfg(), Laws.nodes.opts(ND.SelNone{}, False{}, [":NoSchedule op=Exists"]), "", Laws.nodes.pnode([], [Laws.nodes.key1()], []), Laws.nodes.base_vnode(), [Laws.nodes.pod()], [], []))
    == Laws.nodes.update(Laws.nodes.vnode([Laws.nodes.marker()], [Laws.nodes.key1_ann()], [], [])) : S.Outcome}

# "Not Matching taints"
law nodes.not_matching_taints:
  {S.Svc.canon_outcome(ND.Node.sync(Laws.nodes.cfg(), Laws.nodes.opts(ND.SelNone{}, False{}, ["key2=value2:NoSchedule"]), "", Laws.nodes.pnode([], [Laws.nodes.key1()], []), Laws.nodes.base_vnode(), [Laws.nodes.pod()], [], []))
    == Laws.nodes.update(Laws.nodes.vnode([Laws.nodes.marker()], [Laws.nodes.key1_ann()], [Laws.nodes.key1()], [])) : S.Outcome}

# "Taint matching Enforced Toleration - special case of empty key with
# Exists operator"
law nodes.toleration_empty_key_exists:
  {S.Svc.canon_outcome(ND.Node.sync(Laws.nodes.cfg(), Laws.nodes.opts(ND.SelNone{}, False{}, [":NoSchedule op=Exists"]), "", Laws.nodes.pnode([], [Laws.nodes.key1()], []), Laws.nodes.base_vnode(), [Laws.nodes.pod()], [], []))
    == Laws.nodes.update(Laws.nodes.vnode([Laws.nodes.marker()], [Laws.nodes.key1_ann()], [], [])) : S.Outcome}

# "Nodes syncing enabled -- Ignore updates to Rancher managed annotations"
law nodes.rancher_annotations:
  {S.Svc.canon_outcome(ND.Node.sync(Laws.nodes.cfg(), Laws.nodes.none(), "", Laws.nodes.base_node(),
      Laws.nodes.vnode([], [Laws.nodes.str("management.cattle.io/pod-requests", "{\"pods\":\"1\"}"), Laws.nodes.str("management.cattle.io/pod-limits", "{\"pods\":\"5\"}")], [], []),
      [Laws.nodes.pod()], [], []))
    == Laws.nodes.update(Laws.nodes.vnode([Laws.nodes.marker()],
      [Laws.nodes.str("management.cattle.io/pod-requests", "{\"pods\":\"1\"}"), Laws.nodes.str("management.cattle.io/pod-limits", "{\"pods\":\"5\"}")], [], [])) : S.Outcome}

# nodes/fake_syncer_test.go fixtures. The test overwrites the condition
# times, the IDs and the versions before it compares; the laws take the time
# and IDs as parameters and the versions from fake_syncer.go
# (FakeNodesVersion v1.19.1, kernel 4.19.76-fakelinux).

def Laws.nodes.fake() -> ND.Fake:
  ND.Fake{True{}, False{}, "amd64", "2026-11-07T00:00:00Z", "boot-id", "machine-id", "system-uuid"}

def Laws.nodes.condition(t: String, status: String, reason: String, message: String) -> J.Json:
  J.Json.obj([Laws.nodes.str("type", t), Laws.nodes.str("status", status), Laws.nodes.str("lastHeartbeatTime", "2026-11-07T00:00:00Z"),
    Laws.nodes.str("lastTransitionTime", "2026-11-07T00:00:00Z"), Laws.nodes.str("reason", reason), Laws.nodes.str("message", message)])

def Laws.nodes.resources() -> List<&2, J.KV>:
  [Laws.nodes.str("cpu", "16"), Laws.nodes.str("memory", "32Gi"), Laws.nodes.str("ephemeral-storage", "100Gi"),
   Laws.nodes.str("hugepages-1Gi", "0"), Laws.nodes.str("hugepages-2Mi", "0"), Laws.nodes.str("pods", "110")]

# baseNode of fake_syncer_test.go.
def Laws.nodes.fake_node() -> J.Json:
  Laws.nodes.node([Laws.nodes.str("name", "mynode"),
      Laws.nodes.obj("labels", [Laws.nodes.str("vcluster.loft.sh/fake-node", "true"), Laws.nodes.str("beta.kubernetes.io/arch", "amd64"),
        Laws.nodes.str("beta.kubernetes.io/os", "linux"), Laws.nodes.str("kubernetes.io/arch", "amd64"),
        Laws.nodes.str("kubernetes.io/hostname", "fake-mynode"), Laws.nodes.str("kubernetes.io/os", "linux")]),
      Laws.nodes.obj("annotations", [Laws.nodes.str("node.alpha.kubernetes.io/ttl", "0"), Laws.nodes.str("volumes.kubernetes.io/controller-managed-attach-detach", "false")])],
    [],
    [Laws.nodes.obj("capacity", Laws.nodes.resources()), Laws.nodes.obj("allocatable", Laws.nodes.resources()),
     Laws.nodes.arr("conditions", [Laws.nodes.condition("MemoryPressure", "False", "KubeletHasSufficientMemory", "kubelet has sufficient memory available"),
       Laws.nodes.condition("DiskPressure", "False", "KubeletHasNoDiskPressure", "kubelet has no disk pressure"),
       Laws.nodes.condition("PIDPressure", "False", "KubeletHasSufficientPID", "kubelet has sufficient PID available"),
       Laws.nodes.condition("Ready", "True", "KubeletReady", "kubelet is posting ready status")]),
     Laws.nodes.arr("addresses", [Laws.nodes.host_address()]), Laws.nodes.endpoints("10250"),
     Laws.nodes.obj("nodeInfo", [Laws.nodes.str("architecture", "amd64"), Laws.nodes.str("bootID", "boot-id"),
       Laws.nodes.str("containerRuntimeVersion", "docker://19.3.12"), Laws.nodes.str("kernelVersion", "4.19.76-fakelinux"),
       Laws.nodes.str("kubeProxyVersion", "v1.19.1"), Laws.nodes.str("kubeletVersion", "v1.19.1"),
       Laws.nodes.str("machineID", "machine-id"), Laws.nodes.str("systemUUID", "system-uuid"),
       Laws.nodes.str("operatingSystem", "linux"), Laws.nodes.str("osImage", "Fake Kubernetes Image")])])

# nodes/fake_syncer_test.go TestFakeSync.

# "Create test": FakeSyncToVirtual(mynode) with basePod.
law nodes.fake_create:
  {S.Svc.canon_outcome(ND.Node.fake_sync_to_virtual(Laws.nodes.fake(), "mynode", "127.0.0.1", [Laws.nodes.pod()], []))
    == Laws.nodes.out([S.VirtualCreate{Laws.nodes.fake_node()}]) : S.Outcome}

# "Delete test": FakeSync(baseNode) with no pods.
law nodes.fake_delete:
  {S.Svc.canon_outcome(ND.Node.fake_sync(Laws.nodes.fake(), "127.0.0.1", Laws.nodes.fake_node(), [], []))
    == Laws.nodes.delete() : S.Outcome}

# events/syncer_test.go fixtures.

def Laws.nodes.meta(name: String, ns: String) -> J.KV:
  Laws.nodes.obj("metadata", [Laws.nodes.str("name", name), Laws.nodes.str("namespace", ns)])

def Laws.nodes.involved(name: String) -> J.KV:
  Laws.nodes.obj("involvedObject", [Laws.nodes.str("apiVersion", "v1"), Laws.nodes.str("kind", "Pod"), Laws.nodes.str("name", name),
    Laws.nodes.str("namespace", "test"), Laws.nodes.str("resourceVersion", "999")])

# vPod as the fake client returns it (resource version 999).
def Laws.nodes.vpod() -> J.Json:
  J.Json.obj([Laws.nodes.obj("metadata", [Laws.nodes.str("name", "test-pod"), Laws.nodes.str("namespace", "test"), Laws.nodes.str("resourceVersion", "999")])])

# pEvent
def Laws.nodes.p_event() -> J.Json:
  J.Json.obj([Laws.nodes.meta("test-event", "test"), Laws.nodes.involved("test-pod-x-test-x-suffix")])

# vEvent
def Laws.nodes.v_event() -> J.Json:
  J.Json.obj([Laws.nodes.meta("test-event", "test"), Laws.nodes.involved("test-pod")])

# pEventUpdated
def Laws.nodes.p_event_updated() -> J.Json:
  J.Json.obj([Laws.nodes.meta("test-event", "test"), Laws.nodes.num("count", "2"), Laws.nodes.involved("test-pod-x-test-x-suffix")])

# vEventUpdated
def Laws.nodes.v_event_updated() -> J.Json:
  J.Json.obj([Laws.nodes.meta("test-event", "test"), Laws.nodes.num("count", "2"), Laws.nodes.involved("test-pod")])

# events/syncer_test.go TestSync.

# "Create new event": SyncToVirtual(pEvent); vPod and namespace test exist.
law nodes.event_create:
  {S.Svc.canon_outcome(ND.Ev.sync_to_virtual(Laws.nodes.p_event(), Some{Laws.nodes.vpod()}, ["test"]))
    == Laws.nodes.out([S.VirtualCreate{Laws.nodes.v_event()}]) : S.Outcome}

# "Update event": Sync(NewSyncEvent(pEventUpdated, vEvent)).
law nodes.event_update:
  {S.Svc.canon_outcome(ND.Ev.sync(Laws.nodes.p_event_updated(), Some{Laws.nodes.vpod()}, Laws.nodes.v_event()))
    == Laws.nodes.out([S.VirtualUpdate{Laws.nodes.v_event_updated()}]) : S.Outcome}

# General laws.

# The fake node set is the set of node names of the synced pods: after the
# fake node syncer's step for node `name`, the virtual node exists exactly
# when a virtual pod or a managed host pod on that node counts (not a
# DaemonSet pod).
law nodes.fake_set:
  for +f: ND.Fake
  for +name: String
  for +ip: String
  for +node: Maybe<&2, J.Json>
  for +vpods: List<&2, J.Json>
  for +hpods: List<&2, J.Json>
  {ND.Node.exists_after(name, node, ND.Node.fake_step(f, name, ip, node, vpods, hpods)) == M.Meta.elem(name, ND.Node.pod_nodes(vpods, hpods)) : Bool}

# Every event SyncToVirtual creates for an accepted involved object refers
# to the virtual object it maps to.
law nodes.event_create_refers:
  for +h: J.Json
  for +v: J.Json
  for +live: +List<String>
  for ha: {ND.Ev.accepted(h) == True{} : Bool}
  {ND.Ev.refers(ND.Ev.sync_to_virtual(h, Some{v}, live), v) == True{} : Bool}

# Every event Sync writes for an accepted involved object refers to the
# virtual object it maps to.
law nodes.event_update_refers:
  for +h: J.Json
  for +v: J.Json
  for +ve: J.Json
  for ha: {ND.Ev.accepted(h) == True{} : Bool}
  {ND.Ev.refers(ND.Ev.sync(h, Some{v}, ve), v) == True{} : Bool}
