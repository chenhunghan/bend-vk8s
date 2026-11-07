import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/translate/services.bend as S
import ../src/translate/endpoint.bend as E

# Spec for src/translate/endpoint.bend (vcluster
# pkg/controllers/k8sdefaultendpoint and pkg/controllers/servicesync).
#
# The concrete laws transcribe every case of
# k8sdefaultendpoint/register_test.go, k8sdefaultendpoint/provider_test.go
# and servicesync/servicesync_test.go (vcluster a8ab30e). Where a test only
# asserts that no error happened, the law states the writes the Go code
# makes for the test's objects. Expected objects come from the tests, or
# from vcluster's code for the test's inputs (cited at each law). Objects
# are compared in canonical form (E.Ep.canon_outcome, S.Svc.canon): member
# order does not count, and null, false, 0, [] and {} count as absent.
#
# The standalone laws give the objects k8sdefaultendpoint keeps when the
# host Endpoints of the vcluster service hold the API server at one IP and
# port, its port named https (k8sdefaultendpoint.go:109-182,
# provider.go:21-99): the general laws say each carries exactly that
# address and one port named https.

# Fixtures.

def Laws.endpoint.str(k: String, v: String) -> J.KV:
  J.KV{k, J.JStr{v}}

def Laws.endpoint.num(k: String, v: String) -> J.KV:
  J.KV{k, J.JNum{v}}

def Laws.endpoint.obj(k: String, fs: List<&2, J.KV>) -> J.KV:
  J.KV{k, J.Json.obj(fs)}

def Laws.endpoint.arr(k: String, xs: List<&2, J.Json>) -> J.KV:
  J.KV{k, J.Json.arr(xs)}

def Laws.endpoint.cfg() -> S.Cfg:
  S.Cfg{"suffix", "test", "vcluster"}

def Laws.endpoint.out(ws: List<&2, E.Write>) -> E.Outcome:
  E.Ep.canon_outcome(E.Outcome{ws, ""})

# k8sdefaultendpoint/register_test.go TestShouldUseLegacy.

# A fake discovery client without resources: discovery.k8s.io/v1 is not
# found.
law endpoint.legacy_not_found:
  {E.Ep.should_use_legacy(None{}) == True{} : Bool}

# discovery.k8s.io/v1 with only the kind
# EndpointSliceIsNotAvailableButResourceDoes.
law endpoint.legacy_without_slice:
  {E.Ep.should_use_legacy(Some{["EndpointSliceIsNotAvailableButResourceDoes"]}) == True{} : Bool}

# discovery.k8s.io/v1 with the kind EndpointSlice.
law endpoint.legacy_with_slice:
  {E.Ep.should_use_legacy(Some{["EndpointSlice"]}) == False{} : Bool}

# k8sdefaultendpoint/provider_test.go TestCreateOrPatch.

# endpoints: test/test, resource version 1, one subset with address
# 127.0.0.1 and port {Name: "name", Port: 8081, Protocol: "https"}.
def Laws.endpoint.provider_endpoints() -> J.Json:
  J.Json.obj([Laws.endpoint.obj("metadata", [Laws.endpoint.str("name", "test"), Laws.endpoint.str("namespace", "test"), Laws.endpoint.str("resourceVersion", "1")]),
    Laws.endpoint.arr("subsets", [J.Json.obj([Laws.endpoint.arr("addresses", [J.Json.obj([Laws.endpoint.str("ip", "127.0.0.1")])]),
      Laws.endpoint.arr("ports", [J.Json.obj([Laws.endpoint.str("name", "name"), Laws.endpoint.num("port", "8081"), Laws.endpoint.str("protocol", "https")])])])])])

# The slice the provider creates in the empty fake client
# (provider.go:21-99): default/kubernetes, labelled with the endpoints name
# "test", IPv4, the port as Port/Name/Protocol, one ready endpoint.
def Laws.endpoint.provider_slice() -> J.Json:
  J.Json.obj([Laws.endpoint.obj("metadata", [Laws.endpoint.str("name", "kubernetes"), Laws.endpoint.str("namespace", "default"),
      Laws.endpoint.obj("labels", [Laws.endpoint.str("kubernetes.io/service-name", "test")])]),
    Laws.endpoint.str("addressType", "IPv4"),
    Laws.endpoint.arr("ports", [J.Json.obj([Laws.endpoint.str("name", "name"), Laws.endpoint.num("port", "8081"), Laws.endpoint.str("protocol", "https")])]),
    Laws.endpoint.arr("endpoints", [J.Json.obj([Laws.endpoint.arr("addresses", [J.JStr{"127.0.0.1"}]), Laws.endpoint.obj("conditions", [J.KV{"ready", J.JBool{True{}}}])])])])

# EndpointsV1Provider.CreateOrPatch(ctx, virtualClient, endpoints).
law endpoint.create_or_patch_v1:
  {E.Ep.canon_writes(E.Ep.slice_create_or_patch(False{}, Laws.endpoint.provider_endpoints(), None{}))
    == E.Ep.canon_writes([E.VirtualCreate{E.KEndpointSlice{}, Laws.endpoint.provider_slice()}]) : List<&2, E.Write>}

# EndpointsV1BetaProvider.CreateOrPatch(ctx, virtualClient, endpoints): the
# same object, as a discovery.k8s.io/v1beta1 EndpointSlice.
law endpoint.create_or_patch_v1beta1:
  {E.Ep.canon_writes(E.Ep.slice_create_or_patch(True{}, Laws.endpoint.provider_endpoints(), None{}))
    == E.Ep.canon_writes([E.VirtualCreate{E.KEndpointSliceV1Beta1{}, Laws.endpoint.provider_slice()}]) : List<&2, E.Write>}

# servicesync/servicesync_test.go fixtures.

# The FromHost syncer of the tests: virtual target, CreateNamespace and
# CreateEndpoints.
def Laws.endpoint.from_host() -> E.Rep:
  E.Rep{False{}, True{}, True{}}

# host-namespace/host-service -> virtual-namespace/virtual-service.
def Laws.endpoint.mapping() -> List<&2, E.Mapping>:
  [E.Mapping{"host-namespace", "host-service", "virtual-namespace", "virtual-service"}]

# The metadata of the target service: its name and the label
# vcluster.loft.sh/controlled-by: vcluster.
def Laws.endpoint.target_meta() -> J.KV:
  Laws.endpoint.obj("metadata", [Laws.endpoint.str("namespace", "virtual-namespace"), Laws.endpoint.str("name", "virtual-service"),
    Laws.endpoint.obj("labels", [Laws.endpoint.str("vcluster.loft.sh/controlled-by", "vcluster")])])

def Laws.endpoint.host_meta() -> J.KV:
  Laws.endpoint.obj("metadata", [Laws.endpoint.str("namespace", "host-namespace"), Laws.endpoint.str("name", "host-service")])

# "Sync host service to new virtual service": the host service.
def Laws.endpoint.host_service() -> J.Json:
  J.Json.obj([Laws.endpoint.host_meta(), Laws.endpoint.obj("spec", [Laws.endpoint.obj("selector", [Laws.endpoint.str("app", "host-app")]),
    Laws.endpoint.arr("ports", [J.Json.obj([Laws.endpoint.str("name", "http"), Laws.endpoint.num("port", "8080")])])])])

# Its ExpectedVirtualServices.
def Laws.endpoint.expected_virtual_service() -> J.Json:
  J.Json.obj([Laws.endpoint.target_meta(), Laws.endpoint.obj("spec", [Laws.endpoint.str("clusterIP", "None"),
    Laws.endpoint.arr("ports", [J.Json.obj([Laws.endpoint.str("name", "http"), Laws.endpoint.num("port", "8080")])])])])

# The port {Name: "http", Port: 8080, Protocol: TCP}.
def Laws.endpoint.tcp_port() -> J.Json:
  J.Json.obj([Laws.endpoint.str("name", "http"), Laws.endpoint.num("port", "8080"), Laws.endpoint.str("protocol", "TCP")])

# TestFromHostReconcileLoadBalancerCreatesEndpoints: hostService.
def Laws.endpoint.lb_host_service() -> J.Json:
  J.Json.obj([Laws.endpoint.host_meta(),
    Laws.endpoint.obj("spec", [Laws.endpoint.str("type", "LoadBalancer"), Laws.endpoint.str("clusterIP", "10.0.0.1"), Laws.endpoint.arr("ports", [Laws.endpoint.tcp_port()])]),
    Laws.endpoint.obj("status", [Laws.endpoint.obj("loadBalancer", [Laws.endpoint.arr("ingress", [J.Json.obj([Laws.endpoint.str("ip", "10.0.0.2")])])])])])

# virtualService.
def Laws.endpoint.lb_virtual_service() -> J.Json:
  J.Json.obj([Laws.endpoint.target_meta(), Laws.endpoint.obj("spec", [Laws.endpoint.str("clusterIP", "None"), Laws.endpoint.arr("ports", [Laws.endpoint.tcp_port()])])])

# The virtual endpoints the test reads: the target name, the
# controlled-by label (servicesync.go:281-292), and the wanted subsets.
def Laws.endpoint.lb_virtual_endpoints() -> J.Json:
  J.Json.obj([Laws.endpoint.target_meta(),
    Laws.endpoint.arr("subsets", [J.Json.obj([Laws.endpoint.arr("addresses", [J.Json.obj([Laws.endpoint.str("ip", "10.0.0.1")])]), Laws.endpoint.arr("ports", [Laws.endpoint.tcp_port()])])])])

# servicesync/servicesync_test.go.

# TestFromHostRegister: Register maps a change to the target
# virtual-namespace/virtual-service back to the request for its source.
law endpoint.register_reverse:
  {E.Ep.reverse("virtual-namespace", "virtual-service", Laws.endpoint.mapping()) == Some{("host-namespace", "host-service")} : Maybe<&2, String & String>}

# TestFromHostReconcile "Reconcile without errors when service is not
# synced": example-namespace/example-service is not mapped.
law endpoint.reconcile_not_synced:
  {E.Ep.canon_outcome(E.Ep.replicate(Laws.endpoint.cfg(), Laws.endpoint.from_host(), Laws.endpoint.mapping(), "example-namespace", "example-service", None{}, None{}, None{}, None{}, False{}))
    == Laws.endpoint.out([]) : E.Outcome}

# TestFromHostReconcile "Reconcile without errors when host and virtual
# services are not found": no target to delete.
law endpoint.reconcile_not_found:
  {E.Ep.canon_outcome(E.Ep.replicate(Laws.endpoint.cfg(), Laws.endpoint.from_host(), Laws.endpoint.mapping(), "host-namespace", "host-service", None{}, None{}, None{}, None{}, False{}))
    == Laws.endpoint.out([]) : E.Outcome}

# TestFromHostReconcile "Sync host service to new virtual service": the
# fake virtual client has no namespace, so virtual-namespace is created
# first (servicesync.go:190-209), then the headless service.
law endpoint.reconcile_new_virtual_service:
  {E.Ep.canon_outcome(E.Ep.replicate(Laws.endpoint.cfg(), Laws.endpoint.from_host(), Laws.endpoint.mapping(), "host-namespace", "host-service", Some{Laws.endpoint.host_service()}, None{}, None{}, None{}, False{}))
    == Laws.endpoint.out([E.VirtualCreate{E.KNamespace{}, J.Json.obj([Laws.endpoint.obj("metadata", [Laws.endpoint.str("name", "virtual-namespace")])])},
      E.VirtualCreate{E.KService{}, Laws.endpoint.expected_virtual_service()}]) : E.Outcome}

# TestFromHostReconcileLoadBalancerCreatesEndpoints: the virtual service is
# no LoadBalancer, so its status stays; the ports agree; the endpoints are
# created at the host cluster IP with the ports converted.
law endpoint.reconcile_load_balancer_endpoints:
  {E.Ep.canon_outcome(E.Ep.replicate(Laws.endpoint.cfg(), Laws.endpoint.from_host(), Laws.endpoint.mapping(), "host-namespace", "host-service", Some{Laws.endpoint.lb_host_service()}, None{}, Some{Laws.endpoint.lb_virtual_service()}, None{}, True{}))
    == Laws.endpoint.out([E.VirtualCreate{E.KEndpoints{}, Laws.endpoint.lb_virtual_endpoints()}]) : E.Outcome}

# Standalone fixtures: the objects k8sdefaultendpoint keeps when the host
# Endpoints hold one address ip and one port {https, port, TCP}.

def Laws.endpoint.default_meta(labels: List<&2, J.KV>) -> J.KV:
  Laws.endpoint.obj("metadata", [Laws.endpoint.str("name", "kubernetes"), Laws.endpoint.str("namespace", "default"), Laws.endpoint.obj("labels", labels)])

def Laws.endpoint.https(port: String) -> J.Json:
  J.Json.obj([Laws.endpoint.str("name", "https"), Laws.endpoint.num("port", port), Laws.endpoint.str("protocol", "TCP")])

# The virtual Endpoints: the skip-mirror label, the address, the port.
def Laws.endpoint.kubernetes_endpoints(ip: String, port: String) -> J.Json:
  J.Json.obj([Laws.endpoint.default_meta([Laws.endpoint.str("endpointslice.kubernetes.io/skip-mirror", "true")]),
    Laws.endpoint.arr("subsets", [J.Json.obj([Laws.endpoint.arr("addresses", [J.Json.obj([Laws.endpoint.str("ip", ip)])]), Laws.endpoint.arr("ports", [Laws.endpoint.https(port)])])])])

# The virtual EndpointSlice: the service-name label, the address type, the
# port, one ready endpoint.
def Laws.endpoint.kubernetes_slice(ip: String, port: String, family: String) -> J.Json:
  J.Json.obj([Laws.endpoint.default_meta([Laws.endpoint.str("kubernetes.io/service-name", "kubernetes")]),
    Laws.endpoint.str("addressType", family), Laws.endpoint.arr("ports", [Laws.endpoint.https(port)]),
    Laws.endpoint.arr("endpoints", [J.Json.obj([Laws.endpoint.arr("addresses", [J.JStr{ip}]), Laws.endpoint.obj("conditions", [J.KV{"ready", J.JBool{True{}}}])])])])

# Standalone laws.

# With neither virtual object, both are created: the Endpoints, then the
# EndpointSlice (k8sdefaultendpoint.go:128-180).
law endpoint.standalone_create_ipv4:
  {E.Ep.canon_outcome(E.Ep.standalone_sync("10.0.0.5", 6443, None{}, None{}))
    == Laws.endpoint.out([E.VirtualCreate{E.KEndpoints{}, Laws.endpoint.kubernetes_endpoints("10.0.0.5", "6443")},
      E.VirtualCreate{E.KEndpointSlice{}, Laws.endpoint.kubernetes_slice("10.0.0.5", "6443", "IPv4")}]) : E.Outcome}

# An IPv6 address gives an IPv6 slice (provider.go:59-61).
law endpoint.standalone_create_ipv6:
  {E.Ep.canon_outcome(E.Ep.standalone_sync("fd00::5", 8443, None{}, None{}))
    == Laws.endpoint.out([E.VirtualCreate{E.KEndpoints{}, Laws.endpoint.kubernetes_endpoints("fd00::5", "8443")},
      E.VirtualCreate{E.KEndpointSlice{}, Laws.endpoint.kubernetes_slice("fd00::5", "8443", "IPv6")}]) : E.Outcome}

# Once both are in place nothing is written.
law endpoint.standalone_steady:
  {E.Ep.canon_outcome(E.Ep.standalone_sync("10.0.0.5", 6443, Some{Laws.endpoint.kubernetes_endpoints("10.0.0.5", "6443")}, Some{Laws.endpoint.kubernetes_slice("10.0.0.5", "6443", "IPv4")}))
    == Laws.endpoint.out([]) : E.Outcome}

# A new address patches the Endpoints, then the slice.
law endpoint.standalone_moved:
  {E.Ep.canon_outcome(E.Ep.standalone_sync("10.0.0.6", 6443, Some{Laws.endpoint.kubernetes_endpoints("10.0.0.5", "6443")}, Some{Laws.endpoint.kubernetes_slice("10.0.0.5", "6443", "IPv4")}))
    == Laws.endpoint.out([E.VirtualUpdate{E.KEndpoints{}, Laws.endpoint.kubernetes_endpoints("10.0.0.6", "6443")},
      E.VirtualUpdate{E.KEndpointSlice{}, Laws.endpoint.kubernetes_slice("10.0.0.6", "6443", "IPv4")}]) : E.Outcome}

# The standalone Endpoints and EndpointSlice are the objects the step
# creates.
law endpoint.standalone_endpoints_object:
  {S.Svc.canon(E.Ep.standalone_endpoints("10.0.0.5", 6443)) == S.Svc.canon(Laws.endpoint.kubernetes_endpoints("10.0.0.5", "6443")) : J.Json}

law endpoint.standalone_slice_object:
  {S.Svc.canon(E.Ep.standalone_slice("fd00::5", 8443)) == S.Svc.canon(Laws.endpoint.kubernetes_slice("fd00::5", "8443", "IPv6")) : J.Json}

# General laws: the standalone objects carry exactly one address, the
# API server's, and one port, named https.

law endpoint.standalone_endpoints_one_address:
  for +ip: String
  for port: U32
  {E.Ep.ips(E.Ep.standalone_endpoints(ip, port)) == [ip] : List<&2, String>}

law endpoint.standalone_endpoints_one_https_port:
  for ip: String
  for port: U32
  {E.Ep.port_names(E.Ep.standalone_endpoints(ip, port)) == ["https"] : List<&2, String>}

law endpoint.standalone_slice_one_address:
  for +ip: String
  for port: U32
  {E.Ep.slice_ips(E.Ep.standalone_slice(ip, port)) == [ip] : List<&2, String>}

law endpoint.standalone_slice_one_https_port:
  for ip: String
  for port: U32
  {E.Ep.slice_port_names(E.Ep.standalone_slice(ip, port)) == ["https"] : List<&2, String>}
