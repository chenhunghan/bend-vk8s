import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/translate/meta.bend as M
import ../src/translate/services.bend as S

# Spec for src/translate/services.bend (vcluster
# pkg/controllers/resources/services, endpoints, endpointslices and
# pkg/specialservices).
#
# The concrete laws transcribe every case of services/syncer_test.go,
# endpoints/syncer_test.go and endpointslices/syncer_test.go (vcluster
# a8ab30e); vcluster has no tests in pkg/specialservices, and the
# default/kubernetes cases live in services/syncer_test.go. Inputs are the
# tests' objects and events; expected objects are the tests' expected
# states. vcluster's tests run with VClusterName "suffix", target namespace
# "test" and current namespace "vcluster".
#
# Objects are compared in canonical form (S.Svc.canon_outcome), as the
# tests compare YAML: member order does not count, and null, false, 0, []
# and {} count as absent. The test harness strips the
# vcluster.loft.sh/managed-by label before it compares
# (pkg/syncer/testing/testing.go:228-231), so the endpoints and endpoint
# slice tests leave it out; the laws keep it, as vcluster's HostLabelsMap
# writes it. Where a test calls the syncer twice, each call is a law.

# Test fixtures.

def Laws.services.cfg() -> S.Cfg:
  S.Cfg{"suffix", "test", "vcluster"}

def Laws.services.str(k: String, v: String) -> J.KV:
  J.KV{k, J.JStr{v}}

def Laws.services.num(k: String, v: String) -> J.KV:
  J.KV{k, J.JNum{v}}

def Laws.services.obj(k: String, fs: List<&2, J.KV>) -> J.KV:
  J.KV{k, J.Json.obj(fs)}

def Laws.services.arr(k: String, xs: List<&2, J.Json>) -> J.KV:
  J.KV{k, J.Json.arr(xs)}

# metav1.ObjectMeta{Name, Namespace, Labels, Annotations}.
def Laws.services.meta(name: String, ns: String, labels: List<&2, J.KV>, annotations: List<&2, J.KV>) -> J.KV:
  Laws.services.obj("metadata", [Laws.services.str("name", name), Laws.services.str("namespace", ns), Laws.services.obj("labels", labels), Laws.services.obj("annotations", annotations)])

# The bookkeeping annotations of a host object in target namespace "test".
def Laws.services.ann(name: String, ns: String, kind: String, host: String) -> List<&2, J.KV>:
  [Laws.services.str("vcluster.loft.sh/object-name", name),
   Laws.services.str("vcluster.loft.sh/object-namespace", ns),
   Laws.services.str("vcluster.loft.sh/object-uid", ""),
   Laws.services.str("vcluster.loft.sh/object-kind", kind),
   Laws.services.str("vcluster.loft.sh/object-host-namespace", "test"),
   Laws.services.str("vcluster.loft.sh/object-host-name", host)]

# The marker labels of a host object from virtual namespace ns.
def Laws.services.markers(ns: String) -> List<&2, J.KV>:
  [Laws.services.str("vcluster.loft.sh/namespace", ns), Laws.services.str("vcluster.loft.sh/managed-by", "suffix")]

def Laws.services.svc(meta: J.KV, spec: List<&2, J.KV>) -> J.Json:
  J.Json.obj([meta, Laws.services.obj("spec", spec)])

def Laws.services.svc_status(meta: J.KV, spec: List<&2, J.KV>, status: List<&2, J.KV>) -> J.Json:
  J.Json.obj([meta, Laws.services.obj("spec", spec), Laws.services.obj("status", status)])

def Laws.services.out(ws: List<&2, S.Write>) -> S.Outcome:
  S.Svc.canon_outcome(S.Outcome{ws, S.NoRequeue{}})

# services/syncer_test.go fixtures.

def Laws.services.pname() -> String:
  "testservice-x-testns-x-suffix"

def Laws.services.vmeta() -> J.KV:
  Laws.services.meta("testservice", "testns", [], [])

def Laws.services.pann() -> List<&2, J.KV>:
  Laws.services.ann("testservice", "testns", "/v1, Kind=Service", Laws.services.pname())

def Laws.services.pmeta() -> J.KV:
  Laws.services.meta(Laws.services.pname(), "test", Laws.services.markers("testns"), Laws.services.pann())

def Laws.services.kmeta() -> J.KV:
  Laws.services.meta("kubernetes", "default", [], [])

# baseService
def Laws.services.base() -> J.Json:
  Laws.services.svc(Laws.services.vmeta(), [])

# createdService
def Laws.services.created() -> J.Json:
  Laws.services.svc(Laws.services.pmeta(), [])

# createdByServerService
def Laws.services.created_by_server() -> J.Json:
  Laws.services.svc(Laws.services.meta(Laws.services.pname(), "test", Laws.services.markers("testns"),
    List.append(&2, J.KV, Laws.services.pann(), [Laws.services.str("vcluster.loft.sh/block-deletion", "true")])), [])

# updateForwardSpec
def Laws.services.forward_spec() -> List<&2, J.KV>:
  [Laws.services.arr("ports", [J.Json.obj([Laws.services.str("name", "somePort"), Laws.services.num("port", "123")])]),
   J.KV{"publishNotReadyAddresses", J.JBool{True{}}},
   Laws.services.str("type", "NodePort"),
   Laws.services.str("externalTrafficPolicy", "Local"),
   Laws.services.str("sessionAffinity", "ClientIP"),
   Laws.services.obj("sessionAffinityConfig", [Laws.services.obj("clientIP", [])]),
   Laws.services.num("healthCheckNodePort", "112")]

# updateForwardService
def Laws.services.update_forward() -> J.Json:
  Laws.services.svc(Laws.services.meta("testservice", "testns", [], [Laws.services.str("a", "b")]), Laws.services.forward_spec())

# updatedForwardService
def Laws.services.updated_forward() -> J.Json:
  Laws.services.svc(Laws.services.meta(Laws.services.pname(), "test", Laws.services.markers("testns"),
    List.append(&2, J.KV, Laws.services.pann(), [Laws.services.str("a", "b")])), Laws.services.forward_spec())

# updateBackwardSpecService
def Laws.services.backward_spec() -> J.Json:
  Laws.services.svc(Laws.services.pmeta(), [Laws.services.str("type", "ExternalName"), Laws.services.str("externalName", "backwardExternal")])

# updatedBackwardSpecService
def Laws.services.updated_backward_spec() -> J.Json:
  Laws.services.svc(Laws.services.vmeta(), [Laws.services.str("type", "ExternalName"), Laws.services.str("externalName", "backwardExternal")])

# updateBackwardSpecRecreateService
def Laws.services.backward_recreate() -> J.Json:
  Laws.services.svc(Laws.services.pmeta(), [Laws.services.str("clusterIP", "123:123:123:123"), Laws.services.str("externalName", "backwardExternal"),
    Laws.services.arr("externalIPs", [J.JStr{"123:221:123:221"}]), Laws.services.str("loadBalancerIP", "123:213:123:213")])

# updateBackwardSpecRecreateServiceExpected
def Laws.services.backward_recreate_expected() -> J.Json:
  Laws.services.svc(Laws.services.pmeta(), [Laws.services.str("clusterIP", "123:123:123:123"), Laws.services.str("externalName", "backwardExternal"),
    Laws.services.arr("externalIPs", [J.JStr{"123:221:123:221"}])])

# baseService after the first Sync of "Update backward spec with
# recreation": recreateService gives it the host cluster IP.
def Laws.services.recreated() -> J.Json:
  Laws.services.svc(Laws.services.vmeta(), [Laws.services.str("clusterIP", "123:123:123:123")])

# updatedBackwardSpecRecreateService
def Laws.services.updated_backward_recreate() -> J.Json:
  Laws.services.svc(Laws.services.vmeta(), [Laws.services.str("externalName", "backwardExternal"), Laws.services.str("clusterIP", "123:123:123:123"),
    Laws.services.arr("externalIPs", [J.JStr{"123:221:123:221"}]), Laws.services.str("loadBalancerIP", "123:213:123:213")])

# updateBackwardStatusService
def Laws.services.backward_status() -> J.Json:
  Laws.services.svc_status(Laws.services.pmeta(), [], [Laws.services.obj("loadBalancer", [Laws.services.arr("ingress",
    [J.Json.obj([Laws.services.str("ip", "121:121:121:121"), Laws.services.str("hostname", "ingresshost")])])])])

# updateBackwardStatusServiceExpected
def Laws.services.backward_status_expected() -> J.Json:
  Laws.services.svc_status(Laws.services.pmeta(), [], [Laws.services.obj("loadBalancer", [])])

# kubernetesService
def Laws.services.kubernetes() -> J.Json:
  Laws.services.svc(Laws.services.kmeta(), [])

# kubernetesWithClusterIPService
def Laws.services.kubernetes_ip() -> J.Json:
  Laws.services.svc(Laws.services.kmeta(), [Laws.services.str("clusterIP", "121:212:121:212")])

# kubernetesWithPortsService
def Laws.services.kubernetes_ports() -> J.Json:
  Laws.services.svc(Laws.services.kmeta(), [Laws.services.arr("ports", [J.Json.obj([Laws.services.str("name", "k8port"), Laws.services.num("port", "4321")])])])

# A port {Name, Port, NodePort, TargetPort: intstr.FromInt(10)}.
def Laws.services.port(name: String, node: String) -> J.Json:
  J.Json.obj([Laws.services.str("name", name), Laws.services.num("port", "123"), Laws.services.num("nodePort", node), Laws.services.num("targetPort", "10")])

# vServicePorts1
def Laws.services.vports1() -> J.Json:
  Laws.services.svc(Laws.services.vmeta(), [Laws.services.arr("ports", [Laws.services.port("test", "567")])])

# vServicePorts1Synced
def Laws.services.vports1_synced() -> J.Json:
  Laws.services.svc(Laws.services.vmeta(), [Laws.services.arr("ports", [Laws.services.port("test", "456")])])

# pServicePorts1
def Laws.services.pports1() -> J.Json:
  Laws.services.svc(Laws.services.pmeta(), [Laws.services.arr("ports", [Laws.services.port("test", "456")])])

# pServicePorts2
def Laws.services.pports2() -> J.Json:
  Laws.services.svc(Laws.services.pmeta(), [Laws.services.arr("ports", [Laws.services.port("test123", "456")])])

# pServicePorts2Synced
def Laws.services.pports2_synced() -> J.Json:
  Laws.services.svc(Laws.services.pmeta(), [Laws.services.arr("ports", [Laws.services.port("test", "567")])])

# A port {Name: "http", Port: port}.
def Laws.services.http(port: String) -> J.Json:
  J.Json.obj([Laws.services.str("name", "http"), Laws.services.num("port", port)])

# The virtual selector {test: test-key}.
def Laws.services.vsel() -> J.KV:
  Laws.services.obj("selector", [Laws.services.str("test", "test-key")])

# The host selector {HostLabel("test"): test-key, NamespaceLabel: testns,
# MarkerLabel: VClusterName}; "test" is not a translated label.
def Laws.services.psel() -> J.KV:
  Laws.services.obj("selector", List.append(&2, J.KV, [Laws.services.str("test", "test-key")], Laws.services.markers("testns")))

# vServiceClusterIPFromExternal
def Laws.services.v_cluster_ip_from_external() -> J.Json:
  Laws.services.svc(Laws.services.vmeta(), [Laws.services.str("type", "ClusterIP"), Laws.services.arr("ports", [Laws.services.http("80")])])

# pServiceExternal
def Laws.services.p_external() -> J.Json:
  Laws.services.svc(Laws.services.pmeta(), [Laws.services.str("externalName", "test.com"), Laws.services.str("type", "ExternalName")])

# pServiceClusterIPFromExternal
def Laws.services.p_cluster_ip_from_external() -> J.Json:
  Laws.services.svc(Laws.services.pmeta(), [Laws.services.str("type", "ClusterIP"), Laws.services.arr("ports", [Laws.services.http("80")])])

# vServiceNodePortFromExternalBefore
def Laws.services.v_node_port_from_external_before() -> J.Json:
  Laws.services.svc(Laws.services.vmeta(), [Laws.services.str("externalName", "test.com")])

# vServiceNodePortFromExternal
def Laws.services.v_node_port_from_external() -> J.Json:
  Laws.services.svc(Laws.services.vmeta(), [Laws.services.vsel(), Laws.services.str("type", "NodePort"), Laws.services.arr("ports", [Laws.services.http("80")])])

# pServiceNodePortFromExternal
def Laws.services.p_node_port_from_external() -> J.Json:
  Laws.services.svc(Laws.services.pmeta(), [Laws.services.psel(), Laws.services.str("type", "NodePort"), Laws.services.arr("ports", [Laws.services.http("80")])])

# The status {LoadBalancer: {Ingress: [{IP: 1.2.3.4}]}}.
def Laws.services.lb_status() -> List<&2, J.KV>:
  [Laws.services.obj("loadBalancer", [Laws.services.arr("ingress", [J.Json.obj([Laws.services.str("ip", "1.2.3.4")])])])]

# vServiceNodePortFromLoadBalancer
def Laws.services.v_node_port_from_lb() -> J.Json:
  Laws.services.svc(Laws.services.vmeta(), [Laws.services.vsel(), Laws.services.str("type", "NodePort"), Laws.services.arr("ports", [Laws.services.http("8080")])])

# vServiceNodePortFromLoadBalancerBefore
def Laws.services.v_node_port_from_lb_before() -> J.Json:
  Laws.services.svc_status(Laws.services.vmeta(), [Laws.services.vsel(), Laws.services.str("type", "LoadBalancer"), Laws.services.arr("ports", [Laws.services.http("8080")])], Laws.services.lb_status())

# pServiceLoadBalancer
def Laws.services.p_lb() -> J.Json:
  Laws.services.svc(Laws.services.pmeta(), [Laws.services.psel(), Laws.services.str("type", "ClusterIP"), Laws.services.arr("ports", [Laws.services.http("8080")])])

# pServiceNodePortFromLoadBalancer
def Laws.services.p_node_port_from_lb() -> J.Json:
  Laws.services.svc(Laws.services.pmeta(), [Laws.services.psel(), Laws.services.str("type", "NodePort"), Laws.services.arr("ports", [Laws.services.http("8080")])])

# vServiceClusterIPFromLoadBalancer
def Laws.services.v_cluster_ip_from_lb() -> J.Json:
  Laws.services.svc(Laws.services.vmeta(), [Laws.services.vsel(), Laws.services.str("type", "ClusterIP"), Laws.services.arr("ports", [Laws.services.http("8080")])])

# vServiceClusterIPFromLoadBalancerBefore
def Laws.services.v_cluster_ip_from_lb_before() -> J.Json:
  Laws.services.svc_status(Laws.services.vmeta(), [Laws.services.vsel(), Laws.services.str("type", "LoadBalancer"), Laws.services.arr("ports", [Laws.services.http("8080")])], Laws.services.lb_status())

# pServiceClusterIPFromLoadBalancer
def Laws.services.p_cluster_ip_from_lb() -> J.Json:
  Laws.services.svc(Laws.services.pmeta(), [Laws.services.str("type", "ClusterIP"), Laws.services.psel(), Laws.services.arr("ports", [Laws.services.http("8080")])])

# services/syncer_test.go TestSync.

# "Create Forward": SyncToHost(baseService).
law services.create_forward:
  {S.Svc.canon_outcome(S.Svc.sync_to_host(Laws.services.cfg(), None{}, Laws.services.base()))
    == Laws.services.out([S.HostCreate{Laws.services.created()}]) : S.Outcome}

# "Sync node ports physical -> virtual":
# Sync(NewSyncEventWithOld(baseService, pServicePorts1, vServicePorts1, vServicePorts1)).
law services.node_ports_backward:
  {S.Svc.canon_outcome(S.Svc.sync(Laws.services.cfg(), Laws.services.base(), Laws.services.pports1(), Laws.services.vports1(), Laws.services.vports1()))
    == Laws.services.out([S.VirtualUpdate{Laws.services.vports1_synced()}]) : S.Outcome}

# "Sync ports virtual -> physical":
# Sync(NewSyncEventWithOld(pServicePorts2, pServicePorts2, baseService, vServicePorts1)).
law services.ports_forward:
  {S.Svc.canon_outcome(S.Svc.sync(Laws.services.cfg(), Laws.services.pports2(), Laws.services.pports2(), Laws.services.base(), Laws.services.vports1()))
    == Laws.services.out([S.HostUpdate{Laws.services.pports2_synced()}]) : S.Outcome}

# "Update forward":
# Sync(NewSyncEventWithOld(createdByServerService, createdByServerService, createdService, updateForwardService)).
law services.update_forward:
  {S.Svc.canon_outcome(S.Svc.sync(Laws.services.cfg(), Laws.services.created_by_server(), Laws.services.created_by_server(), Laws.services.created(), Laws.services.update_forward()))
    == Laws.services.out([S.HostUpdate{Laws.services.updated_forward()}]) : S.Outcome}

# "Update forward not needed":
# Sync(NewSyncEventWithOld(createdService, createdService, baseService, baseService)).
law services.update_forward_not_needed:
  {S.Svc.canon_outcome(S.Svc.sync(Laws.services.cfg(), Laws.services.created(), Laws.services.created(), Laws.services.base(), Laws.services.base()))
    == Laws.services.out([]) : S.Outcome}

# "Update backward spec no recreation", first Sync:
# NewSyncEventWithOld(baseService, updateBackwardSpecService, baseService, baseService).
law services.backward_spec:
  {S.Svc.canon_outcome(S.Svc.sync(Laws.services.cfg(), Laws.services.base(), Laws.services.backward_spec(), Laws.services.base(), Laws.services.base()))
    == Laws.services.out([S.VirtualUpdate{Laws.services.updated_backward_spec()}]) : S.Outcome}

# "Update backward spec no recreation", second Sync, with the virtual
# service as the first Sync left it.
law services.backward_spec_settled:
  {S.Svc.canon_outcome(S.Svc.sync(Laws.services.cfg(), Laws.services.backward_spec(), Laws.services.backward_spec(), Laws.services.updated_backward_spec(), Laws.services.updated_backward_spec()))
    == Laws.services.out([]) : S.Outcome}

# "Update backward spec with recreation", first Sync:
# NewSyncEventWithOld(baseService, updateBackwardSpecRecreateService, baseService, baseService)
# recreates the virtual service and requeues.
law services.backward_spec_recreate:
  {S.Svc.canon_outcome(S.Svc.sync(Laws.services.cfg(), Laws.services.base(), Laws.services.backward_recreate(), Laws.services.base(), Laws.services.base()))
    == S.Svc.canon_outcome(S.Outcome{[S.VirtualDelete{"testns", "testservice"}, S.VirtualCreate{Laws.services.recreated()}], S.RequeueNow{}}) : S.Outcome}

# "Update backward spec with recreation", second Sync:
# NewSyncEventWithOld(baseService, pObj, vObj, vObj) with the recreated
# virtual service.
law services.backward_spec_recreated:
  {S.Svc.canon_outcome(S.Svc.sync(Laws.services.cfg(), Laws.services.base(), Laws.services.backward_recreate(), Laws.services.recreated(), Laws.services.recreated()))
    == Laws.services.out([S.HostUpdate{Laws.services.backward_recreate_expected()}, S.VirtualUpdate{Laws.services.updated_backward_recreate()}]) : S.Outcome}

# "Update backward status":
# Sync(NewSyncEventWithOld(updateBackwardSpecService, updateBackwardStatusService, baseService, baseService)).
law services.backward_status:
  {S.Svc.canon_outcome(S.Svc.sync(Laws.services.cfg(), Laws.services.backward_spec(), Laws.services.backward_status(), Laws.services.base(), Laws.services.base()))
    == Laws.services.out([S.HostUpdate{Laws.services.backward_status_expected()}]) : S.Outcome}

# "Update backward not needed":
# Sync(NewSyncEventWithOld(createdService, createdService, baseService, baseService)).
law services.backward_not_needed:
  {S.Svc.canon_outcome(S.Svc.sync(Laws.services.cfg(), Laws.services.created(), Laws.services.created(), Laws.services.base(), Laws.services.base()))
    == Laws.services.out([]) : S.Outcome}

# "Sync not existent physical kubernetes service".
law services.kubernetes_no_host:
  {S.Svc.canon_outcome(S.Svc.sync_kubernetes(None{}, Some{Laws.services.kubernetes()}))
    == Laws.services.out([]) : S.Outcome}

# "Sync not existent virtual kubernetes service".
law services.kubernetes_no_virtual:
  {S.Svc.canon_outcome(S.Svc.sync_kubernetes(Some{Laws.services.kubernetes()}, None{}))
    == Laws.services.out([]) : S.Outcome}

# "Sync kubernetes service with recreation".
law services.kubernetes_recreate:
  {S.Svc.canon_outcome(S.Svc.sync_kubernetes(Some{Laws.services.kubernetes_ip()}, Some{Laws.services.kubernetes()}))
    == Laws.services.out([S.VirtualDelete{"default", "kubernetes"}, S.VirtualCreate{Laws.services.kubernetes_ip()}]) : S.Outcome}

# "Sync kubernetes service without recreation".
law services.kubernetes_update:
  {S.Svc.canon_outcome(S.Svc.sync_kubernetes(Some{Laws.services.kubernetes_ports()}, Some{Laws.services.kubernetes()}))
    == Laws.services.out([S.VirtualUpdate{Laws.services.kubernetes_ports()}]) : S.Outcome}

# "Sync kubernetes service change type ExternalName to ClusterIP":
# Sync(NewSyncEventWithOld(pServiceExternal, pServiceExternal, vServiceNodePortFromExternalBefore, vServiceClusterIPFromExternal)).
law services.external_name_to_cluster_ip:
  {S.Svc.canon_outcome(S.Svc.sync(Laws.services.cfg(), Laws.services.p_external(), Laws.services.p_external(), Laws.services.v_node_port_from_external_before(), Laws.services.v_cluster_ip_from_external()))
    == Laws.services.out([S.HostUpdate{Laws.services.p_cluster_ip_from_external()}]) : S.Outcome}

# "Sync kubernetes service change type ExternalName to NodePort".
law services.external_name_to_node_port:
  {S.Svc.canon_outcome(S.Svc.sync(Laws.services.cfg(), Laws.services.p_external(), Laws.services.p_external(), Laws.services.v_node_port_from_external_before(), Laws.services.v_node_port_from_external()))
    == Laws.services.out([S.HostUpdate{Laws.services.p_node_port_from_external()}]) : S.Outcome}

# "Sync kubernetes service change type LoadBalancer to NodePort".
law services.load_balancer_to_node_port:
  {S.Svc.canon_outcome(S.Svc.sync(Laws.services.cfg(), Laws.services.p_lb(), Laws.services.p_lb(), Laws.services.v_node_port_from_lb_before(), Laws.services.v_node_port_from_lb()))
    == Laws.services.out([S.HostUpdate{Laws.services.p_node_port_from_lb()}]) : S.Outcome}

# "Sync kubernetes service change type LoadBalancer to ClusterIP": the host
# service already is pServiceClusterIPFromLoadBalancer, so nothing is written.
law services.load_balancer_to_cluster_ip:
  {S.Svc.canon_outcome(S.Svc.sync(Laws.services.cfg(), Laws.services.p_lb(), Laws.services.p_lb(), Laws.services.v_cluster_ip_from_lb_before(), Laws.services.v_cluster_ip_from_lb()))
    == Laws.services.out([]) : S.Outcome}

# endpoints/syncer_test.go fixtures.

def Laws.services.ep_name() -> String:
  "test-endpoints-x-test-x-suffix"

# Subsets [{Addresses: [{IP: ip}]}].
def Laws.services.subsets(ip: String) -> J.KV:
  Laws.services.arr("subsets", [J.Json.obj([Laws.services.arr("addresses", [J.Json.obj([Laws.services.str("ip", ip)])])])])

# vEndpoints
def Laws.services.v_endpoints() -> J.Json:
  J.Json.obj([Laws.services.obj("metadata", [Laws.services.str("name", "test-endpoints"), Laws.services.str("namespace", "test"), Laws.services.str("resourceVersion", "999")]),
    Laws.services.subsets("1.1.1.1")])

# vService (no selector)
def Laws.services.v_endpoints_service() -> J.Json:
  J.Json.obj([Laws.services.meta("test-endpoints", "test", [], [])])

# pEndpoints
def Laws.services.p_endpoints() -> J.Json:
  J.Json.obj([Laws.services.meta(Laws.services.ep_name(), "test", [], [])])

# expectedEndpoints
def Laws.services.expected_endpoints() -> J.Json:
  J.Json.obj([Laws.services.meta(Laws.services.ep_name(), "test", Laws.services.markers("test"),
    Laws.services.ann("test-endpoints", "test", "/v1, Kind=Endpoints", Laws.services.ep_name())), Laws.services.subsets("1.1.1.1")])

# baseEndpoints
def Laws.services.base_endpoints() -> J.Json:
  J.Json.obj([Laws.services.meta("test-secret", "test", [], [])])

# updatedEndpoints
def Laws.services.updated_endpoints() -> J.Json:
  J.Json.obj([Laws.services.obj("metadata", [Laws.services.str("name", "test-secret"), Laws.services.str("namespace", "test"), Laws.services.str("resourceVersion", "1")]),
    Laws.services.subsets("127.0.0.1")])

def Laws.services.synced_endpoints_meta() -> J.KV:
  Laws.services.obj("metadata", [Laws.services.str("resourceVersion", "999"), Laws.services.str("name", "test-secret-x-test-x-suffix"), Laws.services.str("namespace", "test"),
    Laws.services.obj("annotations", Laws.services.ann("test-secret", "test", "/v1, Kind=Endpoints", "test-secret-x-test-x-suffix")),
    Laws.services.obj("labels", Laws.services.markers("test"))])

# syncedEndpoints (the resource version is the fake client's; the harness
# strips it when it compares, and a create sets none).
def Laws.services.synced_endpoints() -> J.Json:
  J.Json.obj([Laws.services.synced_endpoints_meta()])

def Laws.services.created_endpoints() -> J.Json:
  J.Json.obj([Laws.services.meta("test-secret-x-test-x-suffix", "test", Laws.services.markers("test"),
    Laws.services.ann("test-secret", "test", "/v1, Kind=Endpoints", "test-secret-x-test-x-suffix"))])

# syncedUpdatedEndpoints
def Laws.services.synced_updated_endpoints() -> J.Json:
  J.Json.obj([Laws.services.synced_endpoints_meta(), Laws.services.subsets("127.0.0.1")])

# endpoints/syncer_test.go.

# TestExistingEndpoints "Override endpoints even if they are not managed":
# ReconcileStart deletes the unmanaged host endpoints of the selector-less
# service and goes on ...
law services.endpoints_override_start:
  {S.Svc.canon_start(S.Svc.endpoints_start("test", "test-endpoints", Some{Laws.services.v_endpoints_service()}, Some{Laws.services.p_endpoints()}))
    == S.Start{False{}, [S.HostDelete{"test", "test-endpoints-x-test-x-suffix"}], ""} : S.Start}

# ... and SyncToHost creates them anew.
law services.endpoints_override_create:
  {S.Svc.canon_outcome(S.Svc.endpoints_sync_to_host(Laws.services.cfg(), None{}, Laws.services.v_endpoints()))
    == Laws.services.out([S.HostCreate{Laws.services.expected_endpoints()}]) : S.Outcome}

# TestSync "Forward create": SyncToHost(baseEndpoints).
law services.endpoints_forward_create:
  {S.Svc.canon_outcome(S.Svc.endpoints_sync_to_host(Laws.services.cfg(), None{}, Laws.services.base_endpoints()))
    == Laws.services.out([S.HostCreate{Laws.services.created_endpoints()}]) : S.Outcome}

# TestSync "Forward update":
# Sync(NewSyncEventWithOld(syncedEndpoints, syncedEndpoints, baseEndpoints, updatedEndpoints)).
law services.endpoints_forward_update:
  {S.Svc.canon_outcome(S.Svc.endpoints_sync(Laws.services.cfg(), Laws.services.synced_endpoints(), Laws.services.synced_endpoints(), Laws.services.base_endpoints(), Laws.services.updated_endpoints()))
    == Laws.services.out([S.HostUpdate{Laws.services.synced_updated_endpoints()}]) : S.Outcome}

# TestSync "Don't sync default/kubernetes endpoint": ReconcileStart skips.
law services.endpoints_skip_kubernetes:
  {S.Svc.canon_start(S.Svc.endpoints_start("default", "kubernetes", None{}, None{}))
    == S.Start{True{}, [], ""} : S.Start}

# endpointslices/syncer_test.go fixtures.

def Laws.services.eps_name() -> String:
  "test-endpoint-slices-x-test-x-suffix"

# Endpoints [{Addresses: [ip]}].
def Laws.services.endpoints(ip: String) -> J.KV:
  Laws.services.arr("endpoints", [J.Json.obj([Laws.services.arr("addresses", [J.JStr{ip}])])])

# vEndpointSlice
def Laws.services.v_slice() -> J.Json:
  J.Json.obj([Laws.services.obj("metadata", [Laws.services.str("name", "test-endpoint-slices"), Laws.services.str("namespace", "test"), Laws.services.str("resourceVersion", "999"),
      Laws.services.obj("labels", [Laws.services.str("kubernetes.io/service-name", "test-endpoint-slices")])]),
    Laws.services.str("addressType", "IPv4"), Laws.services.endpoints("1.1.1.1")])

# vService (no selector)
def Laws.services.v_slice_service() -> J.Json:
  J.Json.obj([Laws.services.meta("test-endpoint-slices", "test", [], [])])

# pEndpointSlice
def Laws.services.p_slice() -> J.Json:
  J.Json.obj([Laws.services.meta(Laws.services.eps_name(), "test", [], [])])

# expectedEndpointSlice
def Laws.services.expected_slice() -> J.Json:
  J.Json.obj([Laws.services.meta(Laws.services.eps_name(), "test",
      List.append(&2, J.KV, [Laws.services.str("kubernetes.io/service-name", Laws.services.eps_name())], Laws.services.markers("test")),
      Laws.services.ann("test-endpoint-slices", "test", "discovery.k8s.io/v1, Kind=EndpointSlice", Laws.services.eps_name())),
    Laws.services.str("addressType", "IPv4"), Laws.services.endpoints("1.1.1.1")])

# baseEndpointSlice
def Laws.services.base_slice() -> J.Json:
  J.Json.obj([Laws.services.meta("test-eps", "test", [Laws.services.str("kubernetes.io/service-name", "test-svc")], [])])

# updatedEndpointSlice
def Laws.services.updated_slice() -> J.Json:
  J.Json.obj([Laws.services.obj("metadata", [Laws.services.str("name", "test-eps"), Laws.services.str("namespace", "test"), Laws.services.str("resourceVersion", "1"),
      Laws.services.obj("labels", [Laws.services.str("kubernetes.io/service-name", "test-svc")])]),
    Laws.services.endpoints("127.0.0.1,")])

def Laws.services.synced_slice_meta(rv: List<&2, J.KV>) -> J.KV:
  Laws.services.obj("metadata", List.append(&2, J.KV, rv, [Laws.services.str("name", "test-eps-x-test-x-suffix"), Laws.services.str("namespace", "test"),
    Laws.services.obj("annotations", Laws.services.ann("test-eps", "test", "discovery.k8s.io/v1, Kind=EndpointSlice", "test-eps-x-test-x-suffix")),
    Laws.services.obj("labels", List.append(&2, J.KV, Laws.services.markers("test"), [Laws.services.str("kubernetes.io/service-name", "test-svc-x-test-x-suffix")]))]))

# syncedEndpointSlice
def Laws.services.synced_slice() -> J.Json:
  J.Json.obj([Laws.services.synced_slice_meta([Laws.services.str("resourceVersion", "999")])])

# syncedEndpointSlice as a create makes it (no resource version yet).
def Laws.services.created_slice() -> J.Json:
  J.Json.obj([Laws.services.synced_slice_meta([])])

# syncedUpdatedEndpointSlice
def Laws.services.synced_updated_slice() -> J.Json:
  J.Json.obj([Laws.services.synced_slice_meta([Laws.services.str("resourceVersion", "999")]), Laws.services.endpoints("127.0.0.1,")])

# endpointslices/syncer_test.go.

# TestExistingEndpointSlices "Override endpointSlices even if they are not
# managed": ReconcileStart deletes the unmanaged host slice of the
# selector-less service and goes on ...
law services.slices_override_start:
  {S.Svc.canon_start(S.Svc.slice_start("test", "test-endpoint-slices", Some{Laws.services.v_slice()}, Some{Laws.services.v_slice_service()}, Some{Laws.services.p_slice()}))
    == S.Start{False{}, [S.HostDelete{"test", "test-endpoint-slices-x-test-x-suffix"}], ""} : S.Start}

# ... and SyncToHost creates it anew.
law services.slices_override_create:
  {S.Svc.canon_outcome(S.Svc.slice_sync_to_host(Laws.services.cfg(), None{}, Laws.services.v_slice()))
    == Laws.services.out([S.HostCreate{Laws.services.expected_slice()}]) : S.Outcome}

# TestSync "Forward create": SyncToHost(baseEndpointSlice).
law services.slices_forward_create:
  {S.Svc.canon_outcome(S.Svc.slice_sync_to_host(Laws.services.cfg(), None{}, Laws.services.base_slice()))
    == Laws.services.out([S.HostCreate{Laws.services.created_slice()}]) : S.Outcome}

# TestSync "Forward update":
# Sync(NewSyncEventWithOld(syncedEndpointSlice, syncedEndpointSlice, baseEndpointSlice, updatedEndpointSlice)).
law services.slices_forward_update:
  {S.Svc.canon_outcome(S.Svc.slice_sync(Laws.services.cfg(), Laws.services.synced_slice(), Laws.services.synced_slice(), Laws.services.base_slice(), Laws.services.updated_slice()))
    == Laws.services.out([S.HostUpdate{Laws.services.synced_updated_slice()}]) : S.Outcome}

# TestSync "Don't sync default/kubernetes endpointSlice": ReconcileStart skips.
law services.slices_skip_kubernetes:
  {S.Svc.canon_start(S.Svc.slice_start("default", "kubernetes", None{}, None{}, None{}))
    == S.Start{True{}, [], ""} : S.Start}

# General laws.

# A new host service selects only by translated keys and the two markers:
# every key of its selector is the host key of a virtual selector key, or
# vcluster.loft.sh/managed-by, or vcluster.loft.sh/namespace.
law services.selector_keys:
  for +vc: String
  for +target: String
  for +ns: String
  for +sel: +List<M.KV>
  {S.Svc.keys_in(M.Meta.maybe_map(S.Svc.host_selector(vc, target, ns, Some{sel})), S.Svc.selector_allowed(vc, sel)) == True{} : Bool}

# The ports of a new host service keep their number ...
law services.ports_keep_length:
  for +ps: +List<S.Port>
  {List.length(&2, S.Port, S.Svc.strip_node_ports(ps)) == List.length(&2, S.Port, ps) : Nat}

# ... and their order, each port the same but for its node port.
law services.ports_keep_order:
  for +ps: +List<S.Port>
  {S.Svc.port_ids(S.Svc.strip_node_ports(ps)) == S.Svc.port_ids(ps) : List<&2, J.Json>}
