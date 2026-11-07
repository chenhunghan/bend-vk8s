import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/translate/services.bend as S
import ../src/translate/endpoint.bend as E

# Tests for src/translate/endpoint.bend. The laws in laws/endpoint.bend
# transcribe vcluster's tests; these cover the rest of k8sdefaultendpoint
# and servicesync: the https port filter, cleared addresses, not-ready
# endpoints, address families, label replacement on the slice, the
# Created/Updated gate of the slice, the v1beta1 kind, the selector path
# (to host), user-made targets, deletes, load balancer status, headless
# sources and endpoint updates. Expected values follow vcluster's Go code
# (VClusterName "suffix", target namespace "test", as in its tests).
# Objects print in canonical form: keys sorted by byte, zero values left
# out.

def cfg() -> S.Cfg:
  S.Cfg{"suffix", "test", "vcluster"}

# networking.replicateServices.toHost without namespace sync.
def to_host() -> E.Rep:
  E.Rep{True{}, False{}, False{}}

# networking.replicateServices.fromHost.
def from_host() -> E.Rep:
  E.Rep{False{}, True{}, True{}}

def tmap() -> List<&2, E.Mapping>:
  [E.Mapping{"ns1", "s", "test", "hs"}]

def fmap() -> List<&2, E.Mapping>:
  [E.Mapping{"hns", "h", "vns", "v"}]

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

def show_kind(k: E.ObjKind) -> String:
  match k:
    case E.KService{}:
      "Service"
    case E.KEndpoints{}:
      "Endpoints"
    case E.KEndpointSlice{}:
      "EndpointSlice"
    case E.KEndpointSliceV1Beta1{}:
      "EndpointSliceV1Beta1"
    case E.KNamespace{}:
      "Namespace"

def show_write(w: E.Write) -> String:
  match w:
    case E.HostCreate{k, o}:
      "host create " ++ show_kind(k)
    case E.HostUpdate{k, o}:
      "host update " ++ show_kind(k)
    case E.HostStatus{k, o}:
      "host status " ++ show_kind(k)
    case E.HostDelete{k, ns, n}:
      "host delete " ++ show_kind(k) ++ " " ++ ns ++ "/" ++ n
    case E.VirtualCreate{k, o}:
      "virtual create " ++ show_kind(k)
    case E.VirtualUpdate{k, o}:
      "virtual update " ++ show_kind(k)
    case E.VirtualStatus{k, o}:
      "virtual status " ++ show_kind(k)
    case E.VirtualDelete{k, ns, n}:
      "virtual delete " ++ show_kind(k) ++ " " ++ ns ++ "/" ++ n

def show_writes(ws: List<&2, E.Write>) -> String:
  match ws:
    case Nil{}:
      ""
    case Con{w, r}:
      show_write(w) ++ "; " ++ show_writes(r)

def show_err.if(empty: Bool, e: String) -> String:
  match empty:
    case True{}:
      ""
    case False{}:
      "error " ++ e

def show_err(+e: String) -> String:
  show_err.if(String.is_empty(e), e)

# The writes (kind and target) and the error of an outcome.
def show_out(o: E.Outcome) -> String:
  match o:
    case E.Outcome{ws, e}:
      show_writes(ws) ++ show_err(e)

def write_obj(w: E.Write) -> J.Json:
  match w:
    case E.HostCreate{k, o}:
      o
    case E.HostUpdate{k, o}:
      o
    case E.HostStatus{k, o}:
      o
    case E.HostDelete{k, ns, n}:
      J.JNull{}
    case E.VirtualCreate{k, o}:
      o
    case E.VirtualUpdate{k, o}:
      o
    case E.VirtualStatus{k, o}:
      o
    case E.VirtualDelete{k, ns, n}:
      J.JNull{}

def first_of(ws: List<&2, E.Write>) -> J.Json:
  match ws:
    case Nil{}:
      J.JNull{}
    case Con{w, r}:
      write_obj(w)

# The object of the first write of an outcome.
def first(o: E.Outcome) -> J.Json:
  match o:
    case E.Outcome{ws, e}:
      first_of(ws)

def last_of(ws: List<&2, E.Write>, acc: J.Json) -> J.Json:
  match ws:
    case Nil{}:
      acc
    case Con{w, r}:
      last_of(r, write_obj(w))

# The object of the last write of an outcome.
def last(o: E.Outcome) -> J.Json:
  match o:
    case E.Outcome{ws, e}:
      last_of(ws, J.JNull{})

def show_bool(b: Bool) -> String:
  match b:
    case True{}:
      "true"
    case False{}:
      "false"

def show_ref(r: Maybe<&2, E.Ref>) -> String:
  match r:
    case None{}:
      "nil"
    case Some{E.Ref{ns, n}}:
      ns ++ "/" ++ n

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

def main() -> IO(Unit):
  do IO<Unit>:
    check("endpoints keep the https port and clear the addresses",
      first(E.Ep.sync_default(False{}, Some{js("{\"metadata\":{\"name\":\"vc\",\"namespace\":\"vcns\"},\"subsets\":[{\"addresses\":[{\"ip\":\"10.0.0.1\",\"hostname\":\"h\",\"nodeName\":\"n\",\"targetRef\":{\"kind\":\"Pod\",\"name\":\"p\"}}],\"notReadyAddresses\":[{\"ip\":\"10.0.0.2\"}],\"ports\":[{\"name\":\"https\",\"port\":8443,\"protocol\":\"TCP\"},{\"name\":\"kubelet\",\"port\":10250,\"protocol\":\"TCP\"}]}]}")}, None{}, None{})),
      "{\"metadata\":{\"labels\":{\"endpointslice.kubernetes.io/skip-mirror\":\"true\"},\"name\":\"kubernetes\",\"namespace\":\"default\"},\"subsets\":[{\"addresses\":[{\"ip\":\"10.0.0.1\"}],\"notReadyAddresses\":[{\"ip\":\"10.0.0.2\"}],\"ports\":[{\"name\":\"https\",\"port\":8443,\"protocol\":\"TCP\"}]}]}")
    check("slice from the endpoints",
      last(E.Ep.sync_default(False{}, Some{js("{\"metadata\":{\"name\":\"vc\",\"namespace\":\"vcns\"},\"subsets\":[{\"addresses\":[{\"ip\":\"10.0.0.1\",\"hostname\":\"h\",\"nodeName\":\"n\",\"targetRef\":{\"kind\":\"Pod\",\"name\":\"p\"}}],\"notReadyAddresses\":[{\"ip\":\"10.0.0.2\"}],\"ports\":[{\"name\":\"https\",\"port\":8443,\"protocol\":\"TCP\"},{\"name\":\"kubelet\",\"port\":10250,\"protocol\":\"TCP\"}]}]}")}, None{}, None{})),
      "{\"addressType\":\"IPv4\",\"endpoints\":[{\"addresses\":[\"10.0.0.1\"],\"conditions\":{\"ready\":true}},{\"addresses\":[\"10.0.0.2\"]}],\"metadata\":{\"labels\":{\"kubernetes.io/service-name\":\"kubernetes\"},\"name\":\"kubernetes\",\"namespace\":\"default\"},\"ports\":[{\"name\":\"https\",\"port\":8443,\"protocol\":\"TCP\"}]}")
    check("create writes endpoints then slice",
      show_out(E.Ep.sync_default(False{}, Some{js("{\"metadata\":{\"name\":\"vc\",\"namespace\":\"vcns\"},\"subsets\":[{\"addresses\":[{\"ip\":\"10.0.0.1\",\"hostname\":\"h\",\"nodeName\":\"n\",\"targetRef\":{\"kind\":\"Pod\",\"name\":\"p\"}}],\"notReadyAddresses\":[{\"ip\":\"10.0.0.2\"}],\"ports\":[{\"name\":\"https\",\"port\":8443,\"protocol\":\"TCP\"},{\"name\":\"kubelet\",\"port\":10250,\"protocol\":\"TCP\"}]}]}")}, None{}, None{})),
      "virtual create Endpoints; virtual create EndpointSlice; ")
    check("legacy writes a v1beta1 slice",
      show_out(E.Ep.sync_default(True{}, Some{js("{\"metadata\":{\"name\":\"vc\",\"namespace\":\"vcns\"},\"subsets\":[{\"addresses\":[{\"ip\":\"10.0.0.1\",\"hostname\":\"h\",\"nodeName\":\"n\",\"targetRef\":{\"kind\":\"Pod\",\"name\":\"p\"}}],\"notReadyAddresses\":[{\"ip\":\"10.0.0.2\"}],\"ports\":[{\"name\":\"https\",\"port\":8443,\"protocol\":\"TCP\"},{\"name\":\"kubelet\",\"port\":10250,\"protocol\":\"TCP\"}]}]}")}, None{}, None{})),
      "virtual create Endpoints; virtual create EndpointSliceV1Beta1; ")
    check("no host endpoints writes nothing",
      show_out(E.Ep.sync_default(False{}, None{}, None{}, None{})),
      "")
    check("unchanged endpoints leave a missing slice",
      show_out(E.Ep.sync_default(False{}, Some{js("{\"metadata\":{\"name\":\"vc\",\"namespace\":\"vcns\"},\"subsets\":[{\"addresses\":[{\"ip\":\"10.0.0.1\",\"hostname\":\"h\",\"nodeName\":\"n\",\"targetRef\":{\"kind\":\"Pod\",\"name\":\"p\"}}],\"notReadyAddresses\":[{\"ip\":\"10.0.0.2\"}],\"ports\":[{\"name\":\"https\",\"port\":8443,\"protocol\":\"TCP\"},{\"name\":\"kubelet\",\"port\":10250,\"protocol\":\"TCP\"}]}]}")}, Some{js("{\"metadata\":{\"labels\":{\"endpointslice.kubernetes.io/skip-mirror\":\"true\"},\"name\":\"kubernetes\",\"namespace\":\"default\"},\"subsets\":[{\"addresses\":[{\"ip\":\"10.0.0.1\"}],\"notReadyAddresses\":[{\"ip\":\"10.0.0.2\"}],\"ports\":[{\"name\":\"https\",\"port\":8443,\"protocol\":\"TCP\"}]}]}")}, None{})),
      "")
    check("unchanged endpoints and slice write nothing",
      show_out(E.Ep.sync_default(False{}, Some{js("{\"metadata\":{\"name\":\"vc\",\"namespace\":\"vcns\"},\"subsets\":[{\"addresses\":[{\"ip\":\"10.0.0.1\",\"hostname\":\"h\",\"nodeName\":\"n\",\"targetRef\":{\"kind\":\"Pod\",\"name\":\"p\"}}],\"notReadyAddresses\":[{\"ip\":\"10.0.0.2\"}],\"ports\":[{\"name\":\"https\",\"port\":8443,\"protocol\":\"TCP\"},{\"name\":\"kubelet\",\"port\":10250,\"protocol\":\"TCP\"}]}]}")}, Some{js("{\"metadata\":{\"labels\":{\"endpointslice.kubernetes.io/skip-mirror\":\"true\"},\"name\":\"kubernetes\",\"namespace\":\"default\"},\"subsets\":[{\"addresses\":[{\"ip\":\"10.0.0.1\"}],\"notReadyAddresses\":[{\"ip\":\"10.0.0.2\"}],\"ports\":[{\"name\":\"https\",\"port\":8443,\"protocol\":\"TCP\"}]}]}")}, Some{js("{\"metadata\":{\"labels\":{\"kubernetes.io/service-name\":\"kubernetes\"},\"name\":\"kubernetes\",\"namespace\":\"default\"},\"addressType\":\"IPv4\",\"ports\":[{\"name\":\"https\",\"port\":8443,\"protocol\":\"TCP\"}],\"endpoints\":[{\"addresses\":[\"10.0.0.1\"],\"conditions\":{\"ready\":true}},{\"addresses\":[\"10.0.0.2\"],\"conditions\":{\"ready\":false}}]}")})),
      "")
    check("patch keeps the endpoints labels",
      first(E.Ep.sync_default(False{}, Some{js("{\"metadata\":{\"name\":\"vc\",\"namespace\":\"vcns\"},\"subsets\":[{\"addresses\":[{\"ip\":\"10.0.0.1\",\"hostname\":\"h\",\"nodeName\":\"n\",\"targetRef\":{\"kind\":\"Pod\",\"name\":\"p\"}}],\"notReadyAddresses\":[{\"ip\":\"10.0.0.2\"}],\"ports\":[{\"name\":\"https\",\"port\":8443,\"protocol\":\"TCP\"},{\"name\":\"kubelet\",\"port\":10250,\"protocol\":\"TCP\"}]}]}")}, Some{js("{\"metadata\":{\"name\":\"kubernetes\",\"namespace\":\"default\",\"labels\":{\"keep\":\"me\"}},\"subsets\":[{\"addresses\":[{\"ip\":\"10.0.0.9\"}]}]}")}, Some{js("{\"metadata\":{\"name\":\"kubernetes\",\"namespace\":\"default\",\"labels\":{\"endpointslice.kubernetes.io/managed-by\":\"endpointslice-controller.k8s.io\",\"kubernetes.io/service-name\":\"kubernetes\"}},\"addressType\":\"IPv4\",\"endpoints\":[{\"addresses\":[\"10.9.9.9\"],\"conditions\":{\"ready\":true}}]}")})),
      "{\"metadata\":{\"labels\":{\"endpointslice.kubernetes.io/skip-mirror\":\"true\",\"keep\":\"me\"},\"name\":\"kubernetes\",\"namespace\":\"default\"},\"subsets\":[{\"addresses\":[{\"ip\":\"10.0.0.1\"}],\"notReadyAddresses\":[{\"ip\":\"10.0.0.2\"}],\"ports\":[{\"name\":\"https\",\"port\":8443,\"protocol\":\"TCP\"}]}]}")
    check("patch replaces the slice labels",
      last(E.Ep.sync_default(False{}, Some{js("{\"metadata\":{\"name\":\"vc\",\"namespace\":\"vcns\"},\"subsets\":[{\"addresses\":[{\"ip\":\"10.0.0.1\",\"hostname\":\"h\",\"nodeName\":\"n\",\"targetRef\":{\"kind\":\"Pod\",\"name\":\"p\"}}],\"notReadyAddresses\":[{\"ip\":\"10.0.0.2\"}],\"ports\":[{\"name\":\"https\",\"port\":8443,\"protocol\":\"TCP\"},{\"name\":\"kubelet\",\"port\":10250,\"protocol\":\"TCP\"}]}]}")}, Some{js("{\"metadata\":{\"name\":\"kubernetes\",\"namespace\":\"default\",\"labels\":{\"keep\":\"me\"}},\"subsets\":[{\"addresses\":[{\"ip\":\"10.0.0.9\"}]}]}")}, Some{js("{\"metadata\":{\"name\":\"kubernetes\",\"namespace\":\"default\",\"labels\":{\"endpointslice.kubernetes.io/managed-by\":\"endpointslice-controller.k8s.io\",\"kubernetes.io/service-name\":\"kubernetes\"}},\"addressType\":\"IPv4\",\"endpoints\":[{\"addresses\":[\"10.9.9.9\"],\"conditions\":{\"ready\":true}}]}")})),
      "{\"addressType\":\"IPv4\",\"endpoints\":[{\"addresses\":[\"10.0.0.1\"],\"conditions\":{\"ready\":true}},{\"addresses\":[\"10.0.0.2\"]}],\"metadata\":{\"labels\":{\"kubernetes.io/service-name\":\"kubernetes\"},\"name\":\"kubernetes\",\"namespace\":\"default\"},\"ports\":[{\"name\":\"https\",\"port\":8443,\"protocol\":\"TCP\"}]}")
    check("patch updates both",
      show_out(E.Ep.sync_default(False{}, Some{js("{\"metadata\":{\"name\":\"vc\",\"namespace\":\"vcns\"},\"subsets\":[{\"addresses\":[{\"ip\":\"10.0.0.1\",\"hostname\":\"h\",\"nodeName\":\"n\",\"targetRef\":{\"kind\":\"Pod\",\"name\":\"p\"}}],\"notReadyAddresses\":[{\"ip\":\"10.0.0.2\"}],\"ports\":[{\"name\":\"https\",\"port\":8443,\"protocol\":\"TCP\"},{\"name\":\"kubelet\",\"port\":10250,\"protocol\":\"TCP\"}]}]}")}, Some{js("{\"metadata\":{\"name\":\"kubernetes\",\"namespace\":\"default\",\"labels\":{\"keep\":\"me\"}},\"subsets\":[{\"addresses\":[{\"ip\":\"10.0.0.9\"}]}]}")}, Some{js("{\"metadata\":{\"name\":\"kubernetes\",\"namespace\":\"default\",\"labels\":{\"endpointslice.kubernetes.io/managed-by\":\"endpointslice-controller.k8s.io\",\"kubernetes.io/service-name\":\"kubernetes\"}},\"addressType\":\"IPv4\",\"endpoints\":[{\"addresses\":[\"10.9.9.9\"],\"conditions\":{\"ready\":true}}]}")})),
      "virtual update Endpoints; virtual update EndpointSlice; ")
    check("mixed families keep the IPv4 addresses",
      last(E.Ep.sync_default(False{}, Some{js("{\"subsets\":[{\"addresses\":[{\"ip\":\"10.0.0.1\"},{\"ip\":\"fd00::1\"}],\"ports\":[{\"name\":\"https\",\"port\":443,\"protocol\":\"TCP\"}]}]}")}, None{}, None{})),
      "{\"addressType\":\"IPv4\",\"endpoints\":[{\"addresses\":[\"10.0.0.1\"],\"conditions\":{\"ready\":true}}],\"metadata\":{\"labels\":{\"kubernetes.io/service-name\":\"kubernetes\"},\"name\":\"kubernetes\",\"namespace\":\"default\"},\"ports\":[{\"name\":\"https\",\"port\":443,\"protocol\":\"TCP\"}]}")
    check("all IPv6 gives an IPv6 slice without node names",
      last(E.Ep.sync_default(False{}, Some{js("{\"subsets\":[{\"addresses\":[{\"ip\":\"fd00::1\"}],\"notReadyAddresses\":[{\"ip\":\"fd00::2\",\"nodeName\":\"n2\"}],\"ports\":[{\"name\":\"https\",\"port\":443,\"protocol\":\"TCP\"}]}]}")}, None{}, None{})),
      "{\"addressType\":\"IPv6\",\"endpoints\":[{\"addresses\":[\"fd00::1\"],\"conditions\":{\"ready\":true}},{\"addresses\":[\"fd00::2\"]}],\"metadata\":{\"labels\":{\"kubernetes.io/service-name\":\"kubernetes\"},\"name\":\"kubernetes\",\"namespace\":\"default\"},\"ports\":[{\"name\":\"https\",\"port\":443,\"protocol\":\"TCP\"}]}")
    check("no subsets gives an empty IPv4 slice",
      last(E.Ep.sync_default(False{}, Some{js("{\"metadata\":{\"name\":\"vc\"}}")}, None{}, None{})),
      "{\"addressType\":\"IPv4\",\"metadata\":{\"labels\":{\"kubernetes.io/service-name\":\"kubernetes\"},\"name\":\"kubernetes\",\"namespace\":\"default\"}}")
    check("legacy without discovery v1",
      show_bool(E.Ep.should_use_legacy(None{})),
      "true")
    check("no legacy with EndpointSlice among kinds",
      show_bool(E.Ep.should_use_legacy(Some{["Other", "EndpointSlice"]})),
      "false")
    check("standalone sync matches the standalone objects",
      sp(show(E.Ep.standalone_endpoints("10.1.2.3", 6443)), show(E.Ep.standalone_slice("10.1.2.3", 6443))),
      "{\"metadata\":{\"labels\":{\"endpointslice.kubernetes.io/skip-mirror\":\"true\"},\"name\":\"kubernetes\",\"namespace\":\"default\"},\"subsets\":[{\"addresses\":[{\"ip\":\"10.1.2.3\"}],\"ports\":[{\"name\":\"https\",\"port\":6443,\"protocol\":\"TCP\"}]}]} {\"addressType\":\"IPv4\",\"endpoints\":[{\"addresses\":[\"10.1.2.3\"],\"conditions\":{\"ready\":true}}],\"metadata\":{\"labels\":{\"kubernetes.io/service-name\":\"kubernetes\"},\"name\":\"kubernetes\",\"namespace\":\"default\"},\"ports\":[{\"name\":\"https\",\"port\":6443,\"protocol\":\"TCP\"}]}")
    check("standalone step creates those objects",
      sp(show(first(E.Ep.standalone_sync("10.1.2.3", 6443, None{}, None{}))), show(last(E.Ep.standalone_sync("10.1.2.3", 6443, None{}, None{})))),
      "{\"metadata\":{\"labels\":{\"endpointslice.kubernetes.io/skip-mirror\":\"true\"},\"name\":\"kubernetes\",\"namespace\":\"default\"},\"subsets\":[{\"addresses\":[{\"ip\":\"10.1.2.3\"}],\"ports\":[{\"name\":\"https\",\"port\":6443,\"protocol\":\"TCP\"}]}]} {\"addressType\":\"IPv4\",\"endpoints\":[{\"addresses\":[\"10.1.2.3\"],\"conditions\":{\"ready\":true}}],\"metadata\":{\"labels\":{\"kubernetes.io/service-name\":\"kubernetes\"},\"name\":\"kubernetes\",\"namespace\":\"default\"},\"ports\":[{\"name\":\"https\",\"port\":6443,\"protocol\":\"TCP\"}]}")
    check("to host creates a selector service",
      first(E.Ep.replicate(cfg(), to_host(), tmap(), "ns1", "s", Some{js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"ns1\"},\"spec\":{\"selector\":{\"app\":\"a\"},\"clusterIP\":\"None\",\"ports\":[{\"name\":\"p\",\"port\":80,\"targetPort\":8080,\"nodePort\":30000}]}}")}, None{}, None{}, None{}, True{})),
      "{\"metadata\":{\"labels\":{\"vcluster.loft.sh/controlled-by\":\"vcluster\"},\"name\":\"hs\",\"namespace\":\"test\"},\"spec\":{\"clusterIP\":\"None\",\"ports\":[{\"name\":\"p\",\"port\":80,\"targetPort\":8080}],\"selector\":{\"app\":\"a\",\"vcluster.loft.sh/managed-by\":\"suffix\",\"vcluster.loft.sh/namespace\":\"ns1\"}}}")
    check("to host create is a host write",
      show_out(E.Ep.replicate(cfg(), to_host(), tmap(), "ns1", "s", Some{js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"ns1\"},\"spec\":{\"selector\":{\"app\":\"a\"},\"clusterIP\":\"None\",\"ports\":[{\"name\":\"p\",\"port\":80,\"targetPort\":8080,\"nodePort\":30000}]}}")}, None{}, None{}, None{}, True{})),
      "host create Service; ")
    check("a user-made target is left alone",
      show_out(E.Ep.replicate(cfg(), to_host(), tmap(), "ns1", "s", Some{js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"ns1\"},\"spec\":{\"selector\":{\"app\":\"a\"},\"clusterIP\":\"None\",\"ports\":[{\"name\":\"p\",\"port\":80,\"targetPort\":8080,\"nodePort\":30000}]}}")}, None{}, Some{js("{\"metadata\":{\"name\":\"hs\",\"namespace\":\"test\"},\"spec\":{\"ports\":[{\"name\":\"q\",\"port\":1}]}}")}, None{}, True{})),
      "")
    check("a vcluster-made target gets the source ports",
      first(E.Ep.replicate(cfg(), to_host(), tmap(), "ns1", "s", Some{js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"ns1\"},\"spec\":{\"selector\":{\"app\":\"a\"},\"clusterIP\":\"None\",\"ports\":[{\"name\":\"p\",\"port\":80,\"targetPort\":8080,\"nodePort\":30000}]}}")}, None{}, Some{js("{\"metadata\":{\"name\":\"hs\",\"namespace\":\"test\",\"labels\":{\"vcluster.loft.sh/controlled-by\":\"vcluster\"}},\"spec\":{\"clusterIP\":\"10.96.0.7\",\"ports\":[{\"name\":\"q\",\"port\":1}],\"selector\":{\"app\":\"a\",\"vcluster.loft.sh/managed-by\":\"suffix\",\"vcluster.loft.sh/namespace\":\"ns1\"}}}")}, None{}, True{})),
      "{\"metadata\":{\"labels\":{\"vcluster.loft.sh/controlled-by\":\"vcluster\"},\"name\":\"hs\",\"namespace\":\"test\"},\"spec\":{\"clusterIP\":\"10.96.0.7\",\"ports\":[{\"name\":\"p\",\"port\":80,\"targetPort\":8080}],\"selector\":{\"app\":\"a\",\"vcluster.loft.sh/managed-by\":\"suffix\",\"vcluster.loft.sh/namespace\":\"ns1\"}}}")
    check("an up-to-date target is not written",
      show_out(E.Ep.replicate(cfg(), to_host(), tmap(), "ns1", "s", Some{js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"ns1\"},\"spec\":{\"selector\":{\"app\":\"a\"},\"clusterIP\":\"None\",\"ports\":[{\"name\":\"p\",\"port\":80,\"targetPort\":8080,\"nodePort\":30000}]}}")}, None{}, Some{js("{\"metadata\":{\"name\":\"hs\",\"namespace\":\"test\",\"labels\":{\"vcluster.loft.sh/controlled-by\":\"vcluster\"}},\"spec\":{\"clusterIP\":\"10.96.0.7\",\"ports\":[{\"name\":\"p\",\"port\":80,\"targetPort\":8080}],\"selector\":{\"app\":\"a\",\"vcluster.loft.sh/managed-by\":\"suffix\",\"vcluster.loft.sh/namespace\":\"ns1\"}}}")}, None{}, True{})),
      "")
    check("a gone source deletes even a user-made target",
      show_out(E.Ep.replicate(cfg(), to_host(), tmap(), "ns1", "s", None{}, None{}, Some{js("{\"metadata\":{\"name\":\"hs\",\"namespace\":\"test\"},\"spec\":{\"ports\":[{\"name\":\"q\",\"port\":1}]}}")}, None{}, True{})),
      "host delete Service test/hs; ")
    check("an unmapped request does nothing",
      show_out(E.Ep.replicate(cfg(), to_host(), tmap(), "ns1", "other", Some{js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"ns1\"},\"spec\":{\"selector\":{\"app\":\"a\"},\"clusterIP\":\"None\",\"ports\":[{\"name\":\"p\",\"port\":80,\"targetPort\":8080,\"nodePort\":30000}]}}")}, None{}, None{}, None{}, True{})),
      "")
    check("reverse of an unmapped target",
      show_ref(E.Ep.reverse("test", "other", tmap())),
      "nil")
    check("reverse of a target",
      show_ref(E.Ep.reverse("test", "hs", tmap())),
      "ns1/s")
    check("namespace exists: only the service is created",
      show_out(E.Ep.replicate(cfg(), from_host(), fmap(), "hns", "h", Some{js("{\"metadata\":{\"name\":\"h\",\"namespace\":\"hns\"},\"spec\":{\"type\":\"LoadBalancer\",\"clusterIP\":\"10.0.0.1\",\"ports\":[{\"name\":\"http\",\"port\":80,\"protocol\":\"TCP\",\"appProtocol\":\"http\",\"nodePort\":31000}]},\"status\":{\"loadBalancer\":{\"ingress\":[{\"ip\":\"1.2.3.4\"}]}}}")}, None{}, None{}, None{}, True{})),
      "virtual create Service; ")
    check("load balancer status goes to the target",
      last(E.Ep.replicate(cfg(), from_host(), fmap(), "hns", "h", Some{js("{\"metadata\":{\"name\":\"h\",\"namespace\":\"hns\"},\"spec\":{\"type\":\"LoadBalancer\",\"clusterIP\":\"10.0.0.1\",\"ports\":[{\"name\":\"http\",\"port\":80,\"protocol\":\"TCP\",\"appProtocol\":\"http\",\"nodePort\":31000}]},\"status\":{\"loadBalancer\":{\"ingress\":[{\"ip\":\"1.2.3.4\"}]}}}")}, None{}, Some{js("{\"metadata\":{\"name\":\"v\",\"namespace\":\"vns\",\"labels\":{\"vcluster.loft.sh/controlled-by\":\"vcluster\"}},\"spec\":{\"type\":\"LoadBalancer\",\"clusterIP\":\"None\",\"ports\":[{\"name\":\"http\",\"port\":80,\"protocol\":\"TCP\",\"appProtocol\":\"http\"}]}}")}, None{}, True{})),
      "{\"metadata\":{\"labels\":{\"vcluster.loft.sh/controlled-by\":\"vcluster\"},\"name\":\"v\",\"namespace\":\"vns\"},\"spec\":{\"clusterIP\":\"None\",\"ports\":[{\"appProtocol\":\"http\",\"name\":\"http\",\"port\":80,\"protocol\":\"TCP\"}],\"type\":\"LoadBalancer\"},\"status\":{\"loadBalancer\":{\"ingress\":[{\"ip\":\"1.2.3.4\"}]}}}")
    check("load balancer status is a status write",
      show_out(E.Ep.replicate(cfg(), from_host(), fmap(), "hns", "h", Some{js("{\"metadata\":{\"name\":\"h\",\"namespace\":\"hns\"},\"spec\":{\"type\":\"LoadBalancer\",\"clusterIP\":\"10.0.0.1\",\"ports\":[{\"name\":\"http\",\"port\":80,\"protocol\":\"TCP\",\"appProtocol\":\"http\",\"nodePort\":31000}]},\"status\":{\"loadBalancer\":{\"ingress\":[{\"ip\":\"1.2.3.4\"}]}}}")}, None{}, Some{js("{\"metadata\":{\"name\":\"v\",\"namespace\":\"vns\",\"labels\":{\"vcluster.loft.sh/controlled-by\":\"vcluster\"}},\"spec\":{\"type\":\"LoadBalancer\",\"clusterIP\":\"None\",\"ports\":[{\"name\":\"http\",\"port\":80,\"protocol\":\"TCP\",\"appProtocol\":\"http\"}]}}")}, None{}, True{})),
      "virtual status Service; ")
    check("endpoints at the cluster IP keep the app protocol",
      last(E.Ep.replicate(cfg(), from_host(), fmap(), "hns", "h", Some{js("{\"metadata\":{\"name\":\"h\",\"namespace\":\"hns\"},\"spec\":{\"type\":\"LoadBalancer\",\"clusterIP\":\"10.0.0.1\",\"ports\":[{\"name\":\"http\",\"port\":80,\"protocol\":\"TCP\",\"appProtocol\":\"http\",\"nodePort\":31000}]},\"status\":{\"loadBalancer\":{\"ingress\":[{\"ip\":\"1.2.3.4\"}]}}}")}, None{}, Some{js("{\"metadata\":{\"name\":\"v\",\"namespace\":\"vns\",\"labels\":{\"vcluster.loft.sh/controlled-by\":\"vcluster\"}},\"spec\":{\"type\":\"LoadBalancer\",\"clusterIP\":\"None\",\"ports\":[{\"name\":\"http\",\"port\":80,\"protocol\":\"TCP\",\"appProtocol\":\"http\"}]},\"status\":{\"loadBalancer\":{\"ingress\":[{\"ip\":\"1.2.3.4\"}]}}}")}, None{}, True{})),
      "{\"metadata\":{\"labels\":{\"vcluster.loft.sh/controlled-by\":\"vcluster\"},\"name\":\"v\",\"namespace\":\"vns\"},\"subsets\":[{\"addresses\":[{\"ip\":\"10.0.0.1\"}],\"ports\":[{\"appProtocol\":\"http\",\"name\":\"http\",\"port\":80,\"protocol\":\"TCP\"}]}]}")
    check("up-to-date endpoints are not written",
      show_out(E.Ep.replicate(cfg(), from_host(), fmap(), "hns", "h", Some{js("{\"metadata\":{\"name\":\"h\",\"namespace\":\"hns\"},\"spec\":{\"type\":\"LoadBalancer\",\"clusterIP\":\"10.0.0.1\",\"ports\":[{\"name\":\"http\",\"port\":80,\"protocol\":\"TCP\",\"appProtocol\":\"http\",\"nodePort\":31000}]},\"status\":{\"loadBalancer\":{\"ingress\":[{\"ip\":\"1.2.3.4\"}]}}}")}, None{}, Some{js("{\"metadata\":{\"name\":\"v\",\"namespace\":\"vns\",\"labels\":{\"vcluster.loft.sh/controlled-by\":\"vcluster\"}},\"spec\":{\"type\":\"LoadBalancer\",\"clusterIP\":\"None\",\"ports\":[{\"name\":\"http\",\"port\":80,\"protocol\":\"TCP\",\"appProtocol\":\"http\"}]},\"status\":{\"loadBalancer\":{\"ingress\":[{\"ip\":\"1.2.3.4\"}]}}}")}, Some{js("{\"metadata\":{\"name\":\"v\",\"namespace\":\"vns\",\"labels\":{\"vcluster.loft.sh/controlled-by\":\"vcluster\"}},\"subsets\":[{\"addresses\":[{\"ip\":\"10.0.0.1\"}],\"ports\":[{\"name\":\"http\",\"port\":80,\"protocol\":\"TCP\",\"appProtocol\":\"http\"}]}]}")}, True{})),
      "")
    check("a headless source without endpoints fails",
      show_out(E.Ep.replicate(cfg(), from_host(), fmap(), "hns", "h", Some{js("{\"metadata\":{\"name\":\"h\",\"namespace\":\"hns\"},\"spec\":{\"clusterIP\":\"None\",\"ports\":[{\"name\":\"http\",\"port\":80}]}}")}, None{}, Some{js("{\"metadata\":{\"name\":\"v\",\"namespace\":\"vns\",\"labels\":{\"vcluster.loft.sh/controlled-by\":\"vcluster\"}},\"spec\":{\"clusterIP\":\"None\",\"ports\":[{\"name\":\"http\",\"port\":80}]}}")}, None{}, True{})),
      "error endpoints \"h\" not found")
    check("a headless source copies its endpoints",
      last(E.Ep.replicate(cfg(), from_host(), fmap(), "hns", "h", Some{js("{\"metadata\":{\"name\":\"h\",\"namespace\":\"hns\"},\"spec\":{\"clusterIP\":\"None\",\"ports\":[{\"name\":\"http\",\"port\":80}]}}")}, Some{js("{\"metadata\":{\"name\":\"h\",\"namespace\":\"hns\"},\"subsets\":[{\"addresses\":[{\"ip\":\"10.1.0.5\",\"hostname\":\"pod-0\"}],\"ports\":[{\"name\":\"http\",\"port\":80}]}]}")}, Some{js("{\"metadata\":{\"name\":\"v\",\"namespace\":\"vns\",\"labels\":{\"vcluster.loft.sh/controlled-by\":\"vcluster\"}},\"spec\":{\"clusterIP\":\"None\",\"ports\":[{\"name\":\"http\",\"port\":80}]}}")}, None{}, True{})),
      "{\"metadata\":{\"labels\":{\"vcluster.loft.sh/controlled-by\":\"vcluster\"},\"name\":\"v\",\"namespace\":\"vns\"},\"subsets\":[{\"addresses\":[{\"hostname\":\"pod-0\",\"ip\":\"10.1.0.5\"}],\"ports\":[{\"name\":\"http\",\"port\":80}]}]}")
    check("changed endpoints are updated",
      show_out(E.Ep.replicate(cfg(), from_host(), fmap(), "hns", "h", Some{js("{\"metadata\":{\"name\":\"h\",\"namespace\":\"hns\"},\"spec\":{\"clusterIP\":\"None\",\"ports\":[{\"name\":\"http\",\"port\":80}]}}")}, Some{js("{\"metadata\":{\"name\":\"h\",\"namespace\":\"hns\"},\"subsets\":[{\"addresses\":[{\"ip\":\"10.1.0.5\",\"hostname\":\"pod-0\"}],\"ports\":[{\"name\":\"http\",\"port\":80}]}]}")}, Some{js("{\"metadata\":{\"name\":\"v\",\"namespace\":\"vns\",\"labels\":{\"vcluster.loft.sh/controlled-by\":\"vcluster\"}},\"spec\":{\"clusterIP\":\"None\",\"ports\":[{\"name\":\"http\",\"port\":80}]}}")}, Some{js("{\"metadata\":{\"name\":\"v\",\"namespace\":\"vns\",\"resourceVersion\":\"5\"},\"subsets\":[{\"addresses\":[{\"ip\":\"10.1.0.4\"}]}]}")}, True{})),
      "virtual update Endpoints; ")
