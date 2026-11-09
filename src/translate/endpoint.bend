import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ./meta.bend as M
import ./services.bend as S

# The endpoints of the vcluster API (vcluster
# pkg/controllers/k8sdefaultendpoint) and service replication
# (pkg/controllers/servicesync, networking.replicateServices), as pure
# functions of object snapshots.
#
# Objects are bend-kube JSON values (J.Json), as the API server sends them.
# A step takes the snapshots the controller reads and returns the writes to
# make, in the order vcluster makes them, as services.bend does. Each write
# names the kind of its object, as these controllers write services,
# endpoints, endpoint slices and namespaces. Equality of objects is
# S.Svc.eq (Kubernetes equality up to Go's omitempty). An update is returned
# only when the object changes; a step that Go ends with an error returns
# the error text and no writes.
#
# k8sdefaultendpoint keeps the virtual default/kubernetes Endpoints and
# EndpointSlice pointing at the vcluster API: the addresses of the host
# Endpoints of the vcluster service (the API server behind port 443 of the
# service, at its target port) and only their port named https. The
# standalone defs at the end give the same objects for vk8s, where the
# virtual cluster's API server listens at a node IP and port and no host
# cluster exists, so the guest can drop kube-apiserver's lease reconciler.
#
# vcluster quirks kept as they are:
# - The endpoint slice is written only when the Endpoints were created or
#   changed (k8sdefaultendpoint.go:177): a slice that drifts alone is not
#   repaired until the Endpoints change.
# - The slice labels are replaced, not merged, by
#   {kubernetes.io/service-name: <endpoints name>} (provider.go:31): the
#   slice has no endpointslice.kubernetes.io/managed-by label, and any label
#   on it goes. The Endpoints carry
#   endpointslice.kubernetes.io/skip-mirror: "true", so the endpoint slice
#   mirroring controller leaves the pair alone.
# - Only the first subset reaches the slice; its ports keep name, port and
#   protocol, each set even when empty (provider.go:51-58).
# - The v1 and v1beta1 providers write the same fields; only the kind
#   differs (EndpointSlice or EndpointSliceV1Beta1).
# - servicesync deletes the target service of a gone source even when a
#   user made the target (servicesync.go:103); it leaves an existing target
#   without vcluster.loft.sh/controlled-by: vcluster alone otherwise.
# - servicesync with endpoints creates the namespace and the service in one
#   step, and the endpoints only on the next one (servicesync.go:190-235).
#
# Not modelled: owner references (translate.GetOwnerReference, nil in
# tests), and IP parsing: an address is IPv6 when it holds a ':'
# (utilnet.IsIPv6String also rejects malformed text and IPv4-mapped
# addresses, which the API server does not store in Endpoints).

# The kind of a written object.
type ObjKind is Data:
  KService{}
  KEndpoints{}
  KEndpointSlice{}
  KEndpointSliceV1Beta1{}
  KNamespace{}

# A write to the host or the virtual cluster. A status write is
# Status().Update.
type Write is Data:
  HostCreate{kind: ObjKind, obj: J.Json}
  HostUpdate{kind: ObjKind, obj: J.Json}
  HostStatus{kind: ObjKind, obj: J.Json}
  HostDelete{kind: ObjKind, namespace: String, name: String}
  VirtualCreate{kind: ObjKind, obj: J.Json}
  VirtualUpdate{kind: ObjKind, obj: J.Json}
  VirtualStatus{kind: ObjKind, obj: J.Json}
  VirtualDelete{kind: ObjKind, namespace: String, name: String}

# The writes of one step, and its error text ("" for none). These
# controllers never ask for a requeue; an error requeues with backoff.
type Outcome is Data:
  Outcome{writes: List<&2, Write>, err: String}

# One entry of a servicesync mapping: the source service
# from_namespace/from_name and its target to_namespace/to_name.
type Mapping is Data:
  Mapping{from_namespace: String, from_name: String, to_namespace: String, to_name: String}

# A namespace/name reference that Maybe can hold: Maybe takes Data, and
# the pair String & String is Type.
type Ref is Data:
  Ref{namespace: String, name: String}

# A servicesync controller: to_host is IsVirtualToHostSyncer (the source is
# virtual and the target on the host); create_namespace and
# create_endpoints as in servicesync.ServiceSyncer.
type Rep is Data:
  Rep{to_host: Bool, create_namespace: Bool, create_endpoints: Bool}

# Constants.

# discoveryv1.LabelSkipMirror.
def Ep.skip_mirror() -> String:
  "endpointslice.kubernetes.io/skip-mirror"

# discoveryv1.LabelServiceName.
def Ep.service_name_label() -> String:
  "kubernetes.io/service-name"

# Outcomes.

def Ep.done(ws: List<&2, Write>) -> Outcome:
  Outcome{ws, ""}

def Ep.canon_write(w: Write) -> Write:
  match w:
    case HostCreate{k, o}:
      HostCreate{k, S.Svc.canon(o)}
    case HostUpdate{k, o}:
      HostUpdate{k, S.Svc.canon(o)}
    case HostStatus{k, o}:
      HostStatus{k, S.Svc.canon(o)}
    case HostDelete{k, ns, n}:
      HostDelete{k, ns, n}
    case VirtualCreate{k, o}:
      VirtualCreate{k, S.Svc.canon(o)}
    case VirtualUpdate{k, o}:
      VirtualUpdate{k, S.Svc.canon(o)}
    case VirtualStatus{k, o}:
      VirtualStatus{k, S.Svc.canon(o)}
    case VirtualDelete{k, ns, n}:
      VirtualDelete{k, ns, n}

def Ep.canon_writes(ws: List<&2, Write>) -> List<&2, Write>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{w, r}:
      Ep.canon_write(w) <> Ep.canon_writes(r)

# An outcome with every object in canonical form.
def Ep.canon_outcome(o: Outcome) -> Outcome:
  match o:
    case Outcome{ws, e}:
      Outcome{Ep.canon_writes(ws), e}

# Writes on one side: the host when to_host, else the virtual cluster.
def Ep.create(to_host: Bool, k: ObjKind, o: J.Json) -> Write:
  match to_host:
    case True{}:
      HostCreate{k, o}
    case False{}:
      VirtualCreate{k, o}

def Ep.update(to_host: Bool, k: ObjKind, o: J.Json) -> Write:
  match to_host:
    case True{}:
      HostUpdate{k, o}
    case False{}:
      VirtualUpdate{k, o}

def Ep.status(to_host: Bool, k: ObjKind, o: J.Json) -> Write:
  match to_host:
    case True{}:
      HostStatus{k, o}
    case False{}:
      VirtualStatus{k, o}

def Ep.delete(to_host: Bool, k: ObjKind, ns: String, name: String) -> Write:
  match to_host:
    case True{}:
      HostDelete{k, ns, name}
    case False{}:
      VirtualDelete{k, ns, name}

# The update, when the object changed.
def Ep.update_if(changed: Bool, to_host: Bool, k: ObjKind, o: J.Json) -> List<&2, Write>:
  match changed:
    case True{}:
      [Ep.update(to_host, k, o)]
    case False{}:
      []

# JSON.

# The item chain of an array; JNil for anything else.
def Ep.chain(j: J.Json) -> J.Json:
  match j:
    case J.JArr{xs}:
      xs
    case _:
      J.JNil{}

def Ep.append(a: J.Json, b: J.Json) -> J.Json:
  match a:
    case J.JCons{h, t}:
      J.JCons{h, Ep.append(t, b)}
    case _:
      b

def Ep.is_cons(j: J.Json) -> Bool:
  match j:
    case J.JCons{h, t}:
      True{}
    case _:
      False{}

# A string as JSON, "" included (a Go *string that is set).
def Ep.str_ptr(+j: J.Json) -> J.Json:
  J.JStr{S.Svc.str(j)}

def Ep.num.go(j: J.Json) -> J.Json:
  match j:
    case J.JNum{t}:
      J.JNum{t}
    case _:
      J.JNum{"0"}

# A number as JSON, 0 when absent (a Go *int32 that is set).
def Ep.num_ptr(j: J.Json) -> J.Json:
  Ep.num.go(j)

# struct equality up to omitempty: a and b as members of an object, so an
# empty struct and an absent one are equal.
def Ep.struct_eq(a: J.Json, b: J.Json) -> Bool:
  S.Svc.eq(J.Json.obj([J.KV{"x", a}]), J.Json.obj([J.KV{"x", b}]))

# k8sdefaultendpoint.

def Ep.has_kind(ks: +List<String>) -> Bool:
  match ks:
    case Nil{}:
      False{}
    case Con{k, r}:
      Bool.or(String.eq(k, "EndpointSlice"), Ep.has_kind(r))

# ShouldUseLegacy (register.go:31-50): kinds lists the kinds of the
# discovery.k8s.io/v1 resources of the virtual cluster, None when the group
# version is not found. Legacy (the v1beta1 provider) unless one is
# EndpointSlice.
def Ep.should_use_legacy(kinds: Maybe<&2, List<&2, String>>) -> Bool:
  match kinds:
    case None{}:
      True{}
    case Some{ks}:
      Bool.not(Ep.has_kind(ks))

# The kind of the endpoint slice a provider writes.
def Ep.slice_kind(legacy: Bool) -> ObjKind:
  match legacy:
    case True{}:
      KEndpointSliceV1Beta1{}
    case False{}:
      KEndpointSlice{}

# An address with Hostname "", NodeName nil and TargetRef nil.
def Ep.clear_address(a: J.Json) -> J.Json:
  S.Svc.del_all(["hostname", "nodeName", "targetRef"], a)

def Ep.clear_chain(xs: J.Json) -> J.Json:
  match xs:
    case J.JCons{a, r}:
      J.JCons{Ep.clear_address(a), Ep.clear_chain(r)}
    case _:
      J.JNil{}

# The addresses of a list, each cleared; null for none.
def Ep.clear_addresses(j: J.Json) -> J.Json:
  match j:
    case J.JArr{xs}:
      J.JArr{Ep.clear_chain(xs)}
    case _:
      J.JNull{}

def Ep.keep.if(keep: Bool, x: J.Json, rec: J.Json) -> J.Json:
  match keep:
    case True{}:
      J.JCons{x, rec}
    case False{}:
      rec

def Ep.is_https(+p: J.Json) -> Bool:
  String.eq(S.Svc.str(J.Json.get(p, "name")), "https")

def Ep.https_chain(xs: J.Json) -> J.Json:
  match xs:
    case J.JCons{+p, r}:
      Ep.keep.if(Ep.is_https(p), p, Ep.https_chain(r))
    case _:
      J.JNil{}

# The ports of a list named https; null for none.
def Ep.https_ports(j: J.Json) -> J.Json:
  match j:
    case J.JArr{xs}:
      J.JArr{Ep.https_chain(xs)}
    case _:
      J.JNull{}

# One subset of the virtual Endpoints (k8sdefaultendpoint.go:137-166): the
# ports named https, and the addresses and not-ready addresses cleared.
def Ep.default_subset(+s: J.Json) -> J.Json:
  a n = Ep.clear_addresses(J.Json.get(s, "addresses")) Ep.clear_addresses(J.Json.get(s, "notReadyAddresses"))
  J.JObj{S.Svc.mem("addresses", a, S.Svc.mem("notReadyAddresses", n, S.Svc.mem("ports", Ep.https_ports(J.Json.get(s, "ports")), J.JNil{})))}

def Ep.default_subsets.chain(xs: J.Json) -> J.Json:
  match xs:
    case J.JCons{s, r}:
      J.JCons{Ep.default_subset(s), Ep.default_subsets.chain(r)}
    case _:
      J.JNil{}

# The subsets of the virtual Endpoints from the host subsets; null for none.
def Ep.default_subsets(j: J.Json) -> J.Json:
  match j:
    case J.JArr{xs}:
      J.JArr{Ep.default_subsets.chain(xs)}
    case _:
      J.JNull{}

# The default/kubernetes object CreateOrPatch starts from when it is missing.
def Ep.kubernetes_meta() -> J.Json:
  J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"kubernetes"}}, J.KV{"namespace", J.JStr{"default"}}])}])

# The virtual default/kubernetes Endpoints v after the mutate of
# syncKubernetesServiceEndpoints, from the host Endpoints h: the skip-mirror
# label set, the subsets rebuilt.
def Ep.default_endpoints(h: J.Json, +v: J.Json) -> J.Json:
  v1 = S.Svc.put_in(v, "metadata", "labels", S.Svc.render(M.Meta.insert(Ep.skip_mirror(), "true", S.Svc.labels(v))))
  S.Svc.put(v1, "subsets", Ep.default_subsets(J.Json.get(h, "subsets")))

# An address is IPv6 when its IP holds a ':'.
def Ep.has_colon(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{Chr{x}, t}:
      Bool.or(U32.is_eq(x, 58), Ep.has_colon(t))

def Ep.is_v6(+a: J.Json) -> Bool:
  Ep.has_colon(S.Svc.str(J.Json.get(a, "ip")))

def Ep.all_v6.chain(xs: J.Json) -> Bool:
  match xs:
    case J.JCons{a, r}:
      Bool.and(Ep.is_v6(a), Ep.all_v6.chain(r))
    case _:
      True{}

# allAddressesIPv6: false for no addresses.
def Ep.all_v6(+xs: J.Json) -> Bool:
  Bool.and(Ep.is_cons(xs), Ep.all_v6.chain(xs))

def Ep.address_type.if(v6: Bool) -> String:
  match v6:
    case True{}:
      "IPv6"
    case False{}:
      "IPv4"

# endpointFromAddress: one endpoint of the address, ready or not.
def Ep.endpoint(ready: Bool, +a: J.Json) -> J.Json:
  e = J.Json.obj([J.KV{"addresses", J.Json.arr([Ep.str_ptr(J.Json.get(a, "ip"))])}, J.KV{"conditions", J.Json.obj([J.KV{"ready", J.JBool{ready}}])}])
  S.Svc.put(S.Svc.put(e, "targetRef", J.Json.get(a, "targetRef")), "nodeName", J.Json.get(a, "nodeName"))

# getEndpointsFromAddresses: the endpoints of the addresses whose family is
# the slice's.
def Ep.endpoints.chain(+v6: Bool, +ready: Bool, xs: J.Json) -> J.Json:
  match xs:
    case J.JCons{+a, r}:
      Ep.keep.if(S.Svc.bool_eq(Ep.is_v6(a), v6), Ep.endpoint(ready, a), Ep.endpoints.chain(v6, ready, r))
    case _:
      J.JNil{}

# An endpoint slice port: Port, Name and Protocol, each a set pointer.
def Ep.slice_port(+p: J.Json) -> J.Json:
  J.Json.obj([J.KV{"name", Ep.str_ptr(J.Json.get(p, "name"))}, J.KV{"port", Ep.num_ptr(J.Json.get(p, "port"))}, J.KV{"protocol", Ep.str_ptr(J.Json.get(p, "protocol"))}])

def Ep.slice_ports.chain(xs: J.Json) -> J.Json:
  match xs:
    case J.JCons{p, r}:
      J.JCons{Ep.slice_port(p), Ep.slice_ports.chain(r)}
    case _:
      J.JNil{}

# The slice ports of a subset's ports; null for none.
def Ep.slice_ports(j: J.Json) -> J.Json:
  match j:
    case J.JArr{xs}:
      J.JArr{Ep.slice_ports.chain(xs)}
    case _:
      J.JNull{}

def Ep.slice_subset.fin(+v6: Bool, +s: J.Json) -> J.Json:
  ready notready = Ep.endpoints.chain(v6, True{}, Ep.chain(J.Json.get(s, "addresses"))) Ep.endpoints.chain(v6, False{}, Ep.chain(J.Json.get(s, "notReadyAddresses")))
  J.JObj{S.Svc.mem("addressType", J.JStr{Ep.address_type.if(v6)}, S.Svc.mem("ports", Ep.slice_ports(J.Json.get(s, "ports")), S.Svc.mem("endpoints", J.JArr{Ep.append(ready, notready)}, J.JNil{})))}

# endpointSliceFromEndpoints for the first subset s: {addressType, ports,
# endpoints}.
def Ep.slice_subset(+s: J.Json) -> J.Json:
  Ep.slice_subset.fin(Ep.all_v6(Ep.append(Ep.chain(J.Json.get(s, "addresses")), Ep.chain(J.Json.get(s, "notReadyAddresses")))), s)

def Ep.slice_body.chain(xs: J.Json) -> J.Json:
  match xs:
    case J.JCons{s, r}:
      Ep.slice_subset(s)
    case _:
      J.Json.obj([J.KV{"addressType", J.JStr{"IPv4"}}])

# endpointSliceFromEndpoints of subsets j, but for name and labels:
# {addressType, ports, endpoints}, IPv4 and nothing else without subsets.
def Ep.slice_body(j: J.Json) -> J.Json:
  match j:
    case J.JArr{xs}:
      Ep.slice_body.chain(xs)
    case _:
      J.Json.obj([J.KV{"addressType", J.JStr{"IPv4"}}])

# The virtual default/kubernetes EndpointSlice v after a provider's
# CreateOrPatch mutate (provider.go:29-35) with the virtual Endpoints e:
# labels, address type, endpoints and ports of endpointSliceFromEndpoints(e).
def Ep.default_slice(+e: J.Json, v: J.Json) -> J.Json:
  +b = Ep.slice_body(J.Json.get(e, "subsets"))
  v1 = S.Svc.put_in(v, "metadata", "labels", S.Svc.render([M.KV{Ep.service_name_label(), S.Svc.name(e)}]))
  v2 = S.Svc.put(v1, "addressType", J.Json.get(b, "addressType"))
  v3 = S.Svc.put(v2, "endpoints", J.Json.get(b, "endpoints"))
  S.Svc.put(v3, "ports", J.Json.get(b, "ports"))

# A provider's CreateOrPatch of the virtual default/kubernetes EndpointSlice
# vs with the virtual Endpoints e.
def Ep.slice_create_or_patch(legacy: Bool, +e: J.Json, vs: Maybe<&2, J.Json>) -> List<&2, Write>:
  match vs:
    case None{}:
      [VirtualCreate{Ep.slice_kind(legacy), Ep.default_slice(e, Ep.kubernetes_meta())}]
    case Some{+s}:
      +n = Ep.default_slice(e, s)
      Ep.update_if(Bool.not(S.Svc.eq(s, n)), False{}, Ep.slice_kind(legacy), n)

def Ep.endpoints_patched(changed: Bool, legacy: Bool, +n: J.Json, vs: Maybe<&2, J.Json>) -> List<&2, Write>:
  match changed:
    case True{}:
      VirtualUpdate{KEndpoints{}, n} <> Ep.slice_create_or_patch(legacy, n, vs)
    case False{}:
      []

def Ep.sync_default.eps(legacy: Bool, h: J.Json, ve: Maybe<&2, J.Json>, vs: Maybe<&2, J.Json>) -> Outcome:
  match ve:
    case None{}:
      +n = Ep.default_endpoints(h, Ep.kubernetes_meta())
      Ep.done(VirtualCreate{KEndpoints{}, n} <> Ep.slice_create_or_patch(legacy, n, vs))
    case Some{+e}:
      +n = Ep.default_endpoints(h, e)
      Ep.done(Ep.endpoints_patched(Bool.not(S.Svc.eq(e, n)), legacy, n, vs))

# kubernetes_default_endpoint Reconcile (syncKubernetesServiceEndpoints):
# host is the host Endpoints of the vcluster service, ve and vs the virtual
# default/kubernetes Endpoints and EndpointSlice; legacy picks the v1beta1
# provider. Without host Endpoints nothing happens. The virtual Endpoints
# are created or patched; when that wrote them, so is the slice.
def Ep.sync_default(legacy: Bool, host: Maybe<&2, J.Json>, ve: Maybe<&2, J.Json>, vs: Maybe<&2, J.Json>) -> Outcome:
  match host:
    case None{}:
      Ep.done([])
    case Some{h}:
      Ep.sync_default.eps(legacy, h, ve, vs)

# Reading endpoint objects.

def Ep.addr_ips(xs: J.Json) -> List<&2, String>:
  match xs:
    case J.JCons{a, r}:
      S.Svc.str(J.Json.get(a, "ip")) <> Ep.addr_ips(r)
    case _:
      []

def Ep.subset_ips(+s: J.Json) -> List<&2, String>:
  List.append(&2, String, Ep.addr_ips(Ep.chain(J.Json.get(s, "addresses"))), Ep.addr_ips(Ep.chain(J.Json.get(s, "notReadyAddresses"))))

def Ep.subsets_ips(xs: J.Json) -> List<&2, String>:
  match xs:
    case J.JCons{s, r}:
      List.append(&2, String, Ep.subset_ips(s), Ep.subsets_ips(r))
    case _:
      []

# The IPs of the addresses (ready or not) of an Endpoints object.
def Ep.ips(o: J.Json) -> List<&2, String>:
  Ep.subsets_ips(Ep.chain(J.Json.get(o, "subsets")))

def Ep.names(xs: J.Json) -> List<&2, String>:
  match xs:
    case J.JCons{p, r}:
      S.Svc.str(J.Json.get(p, "name")) <> Ep.names(r)
    case _:
      []

def Ep.subsets_port_names(xs: J.Json) -> List<&2, String>:
  match xs:
    case J.JCons{s, r}:
      List.append(&2, String, Ep.names(Ep.chain(J.Json.get(s, "ports"))), Ep.subsets_port_names(r))
    case _:
      []

# The port names of an Endpoints object.
def Ep.port_names(o: J.Json) -> List<&2, String>:
  Ep.subsets_port_names(Ep.chain(J.Json.get(o, "subsets")))

def Ep.strs(xs: J.Json) -> List<&2, String>:
  match xs:
    case J.JCons{a, r}:
      S.Svc.str(a) <> Ep.strs(r)
    case _:
      []

def Ep.slice_ips.chain(xs: J.Json) -> List<&2, String>:
  match xs:
    case J.JCons{e, r}:
      List.append(&2, String, Ep.strs(Ep.chain(J.Json.get(e, "addresses"))), Ep.slice_ips.chain(r))
    case _:
      []

# The addresses of the endpoints of an EndpointSlice.
def Ep.slice_ips(o: J.Json) -> List<&2, String>:
  Ep.slice_ips.chain(Ep.chain(J.Json.get(o, "endpoints")))

# The port names of an EndpointSlice.
def Ep.slice_port_names(o: J.Json) -> List<&2, String>:
  Ep.names(Ep.chain(J.Json.get(o, "ports")))

# Standalone (vk8s): the virtual cluster's API server at ip:port, no host
# cluster.

# The port named https at port, as kube-apiserver publishes it.
def Ep.https_port(port: U32) -> J.Json:
  J.Json.obj([J.KV{"name", J.JStr{"https"}}, J.KV{"port", J.Json.u32(port)}, J.KV{"protocol", J.JStr{"TCP"}}])

# The Endpoints of the API server at ip:port, in place of the host
# Endpoints of the vcluster service.
def Ep.standalone_host(ip: String, port: U32) -> J.Json:
  J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"kubernetes"}}, J.KV{"namespace", J.JStr{"default"}}])},
    J.KV{"subsets", J.Json.arr([J.Json.obj([J.KV{"addresses", J.Json.arr([J.Json.obj([J.KV{"ip", J.JStr{ip}}])])}, J.KV{"ports", J.Json.arr([Ep.https_port(port)])}])])}])

# The default/kubernetes Endpoints vcluster keeps for the API server at
# ip:port: one address, one port named https.
def Ep.standalone_endpoints(ip: String, port: U32) -> J.Json:
  J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"kubernetes"}}, J.KV{"namespace", J.JStr{"default"}}, J.KV{"labels", J.Json.obj([J.KV{Ep.skip_mirror(), J.JStr{"true"}}])}])},
    J.KV{"subsets", J.Json.arr([J.Json.obj([J.KV{"addresses", J.Json.arr([J.Json.obj([J.KV{"ip", J.JStr{ip}}])])}, J.KV{"ports", J.Json.arr([Ep.https_port(port)])}])])}])

# The default/kubernetes EndpointSlice (discovery.k8s.io/v1) vcluster keeps
# for the API server at ip:port: one ready endpoint, one port named https.
def Ep.standalone_slice(+ip: String, port: U32) -> J.Json:
  J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"kubernetes"}}, J.KV{"namespace", J.JStr{"default"}}, J.KV{"labels", J.Json.obj([J.KV{Ep.service_name_label(), J.JStr{"kubernetes"}}])}])},
    J.KV{"addressType", J.JStr{Ep.address_type.if(Ep.has_colon(ip))}},
    J.KV{"ports", J.Json.arr([Ep.https_port(port)])},
    J.KV{"endpoints", J.Json.arr([J.Json.obj([J.KV{"addresses", J.Json.arr([J.JStr{ip}])}, J.KV{"conditions", J.Json.obj([J.KV{"ready", J.JBool{True{}}}])}])])}])

# The k8sdefaultendpoint step for the API server at ip:port, with the
# virtual default/kubernetes Endpoints ve and EndpointSlice vs (v1).
def Ep.standalone_sync(ip: String, port: U32, ve: Maybe<&2, J.Json>, vs: Maybe<&2, J.Json>) -> Outcome:
  Ep.sync_default(False{}, Some{Ep.standalone_host(ip, port)}, ve, vs)

# servicesync.

def Ep.to_host(r: Rep) -> Bool:
  match r:
    case Rep{t, n, e}:
      t

def Ep.create_namespace(r: Rep) -> Bool:
  match r:
    case Rep{t, n, e}:
      n

def Ep.create_endpoints(r: Rep) -> Bool:
  match r:
    case Rep{t, n, e}:
      e

def Ep.lookup.if(hit: Bool, ns: String, name: String, rec: Maybe<&2, Ref>) -> Maybe<&2, Ref>:
  match hit:
    case True{}:
      Some{Ref{ns, name}}
    case False{}:
      rec

# The target of source ns/name (SyncServices[ns/name]); None when unmapped.
def Ep.lookup(+ns: String, +name: String, ms: List<&2, Mapping>) -> Maybe<&2, Ref>:
  match ms:
    case Nil{}:
      None{}
    case Con{Mapping{fns, fname, tns, tname}, r}:
      Ep.lookup.if(Bool.and(String.eq(fns, ns), String.eq(fname, name)), tns, tname, Ep.lookup(ns, name, r))

# The source of target ns/name (Register's reverse mapping): the request a
# change to the target service enqueues; None when unmapped.
def Ep.reverse(+ns: String, +name: String, ms: List<&2, Mapping>) -> Maybe<&2, Ref>:
  match ms:
    case Nil{}:
      None{}
    case Con{Mapping{fns, fname, tns, tname}, r}:
      Ep.lookup.if(Bool.and(String.eq(tns, ns), String.eq(tname, name)), fns, fname, Ep.reverse(ns, name, r))

def Ep.strip_chain(xs: J.Json) -> J.Json:
  match xs:
    case J.JCons{p, r}:
      J.JCons{J.Json.del(p, "nodePort"), Ep.strip_chain(r)}
    case x:
      x

def Ep.strip_ports(j: J.Json) -> J.Json:
  match j:
    case J.JArr{xs}:
      J.JArr{Ep.strip_chain(xs)}
    case x:
      x

# services.StripNodePorts on the source service.
def Ep.strip(+f: J.Json) -> J.Json:
  S.Svc.put_in(f, "spec", "ports", Ep.strip_ports(J.Json.at(f, ["spec", "ports"])))

# The target carries vcluster.loft.sh/controlled-by: vcluster.
def Ep.labelled(+t: J.Json) -> Bool:
  String.eq(M.Meta.lookup(M.Meta.controller_label(), S.Svc.labels(t)), "vcluster")

def Ep.headless(+f: J.Json) -> Bool:
  String.eq(S.Svc.spec_str(f, "clusterIP"), "None")

# The metadata of a new target ns/name.
def Ep.target_meta(ref: Ref) -> J.KV:
  match ref:
    case Ref{ns, name}:
      J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{name}}, J.KV{"namespace", J.JStr{ns}}, J.KV{"labels", J.Json.obj([J.KV{M.Meta.controller_label(), J.JStr{"vcluster"}}])}])}

# The delete of target ns/name. A helper def, because a match on `to`
# cannot be followed by a match on the earlier binder `ref`.
def Ep.delete_one(to_host: Bool, ref: Ref) -> List<&2, Write>:
  match ref:
    case Ref{ns, name}:
      [Ep.delete(to_host, KService{}, ns, name)]

def Ep.delete_target(to_host: Bool, ref: Ref, to: Maybe<&2, J.Json>) -> List<&2, Write>:
  match to:
    case None{}:
      []
    case Some{x}:
      Ep.delete_one(to_host, ref)

# The selector path.

# The new target of source f (servicesync.go:134-158): the source ports,
# "None" for a headless source, and the translated selector.
def Ep.selector_new(+c: S.Cfg, +f: J.Json, ref: Ref) -> J.Json:
  +spec = J.Json.get(f, "spec")
  sel = M.Meta.host_labels_map(S.Svc.vc(c), S.Svc.target(c), S.Svc.mmap(J.Json.get(spec, "selector")), None{}, S.Svc.namespace(f), False{})
  s : J.Json = J.JObj{S.Svc.mem("ports", J.Json.get(spec, "ports"), S.Svc.mem("clusterIP", S.Svc.headless.if(Ep.headless(f)), S.Svc.mem("selector", S.Svc.mrender(sel), J.JNil{})))}
  J.Json.obj([Ep.target_meta(ref), J.KV{"spec", s}])

# The existing target t with the source ports and the translated selector
# (servicesync.go:170-180).
def Ep.selector_existing(+c: S.Cfg, +f: J.Json, +t: J.Json) -> J.Json:
  sel = M.Meta.host_labels_map(S.Svc.vc(c), S.Svc.target(c), S.Svc.mmap(J.Json.at(f, ["spec", "selector"])), S.Svc.mmap(J.Json.at(t, ["spec", "selector"])), S.Svc.namespace(f), False{})
  t1 = S.Svc.put_in(t, "spec", "ports", J.Json.at(f, ["spec", "ports"]))
  S.Svc.put_in(t1, "spec", "selector", S.Svc.mrender(sel))

def Ep.with_selector.some(labelled: Bool, +c: S.Cfg, +r: Rep, +f: J.Json, +t: J.Json) -> Outcome:
  match labelled:
    case False{}:
      Ep.done([])
    case True{}:
      +n = Ep.selector_existing(c, f, t)
      Ep.done(Ep.update_if(Bool.not(S.Svc.eq(t, n)), Ep.to_host(r), KService{}, n))

# syncServiceWithSelector.
def Ep.with_selector(+c: S.Cfg, +r: Rep, ref: Ref, +f: J.Json, to: Maybe<&2, J.Json>) -> Outcome:
  match to:
    case None{}:
      Ep.done([Ep.create(Ep.to_host(r), KService{}, Ep.selector_new(c, f, ref))])
    case Some{+t}:
      Ep.with_selector.some(Ep.labelled(t), c, r, f, t)

# The endpoints path.

# The create of the namespace of target ref. A helper def, because a
# match on `create` cannot be followed by a match on the binder `ref`.
def Ep.namespace_one(to_host: Bool, ref: Ref) -> List<&2, Write>:
  match ref:
    case Ref{ns, name}:
      [Ep.create(to_host, KNamespace{}, J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{ns}}])}]))]

def Ep.namespace_writes(create: Bool, to_host: Bool, ref: Ref) -> List<&2, Write>:
  match create:
    case False{}:
      []
    case True{}:
      Ep.namespace_one(to_host, ref)

# The new headless target of source f (servicesync.go:216-226).
def Ep.headless_new(+f: J.Json, ref: Ref) -> J.Json:
  J.Json.obj([Ep.target_meta(ref), J.KV{"spec", J.JObj{S.Svc.mem("ports", J.Json.at(f, ["spec", "ports"]), J.JMem{"clusterIP", J.JStr{"None"}, J.JNil{}})}}])

# convertPorts: name, port, protocol and appProtocol of each service port.
def Ep.convert_port(+p: J.Json) -> J.Json:
  J.JObj{S.Svc.mem("name", J.Json.get(p, "name"), S.Svc.mem("port", J.Json.get(p, "port"), S.Svc.mem("protocol", J.Json.get(p, "protocol"), S.Svc.mem("appProtocol", J.Json.get(p, "appProtocol"), J.JNil{}))))}

def Ep.convert_chain(xs: J.Json) -> J.Json:
  match xs:
    case J.JCons{p, r}:
      J.JCons{Ep.convert_port(p), Ep.convert_chain(r)}
    case _:
      J.JNil{}

def Ep.convert_ports(j: J.Json) -> J.Json:
  match j:
    case J.JArr{xs}:
      J.JArr{Ep.convert_chain(xs)}
    case _:
      J.JNull{}

def Ep.subsets_of(e: Maybe<&2, J.Json>) -> Maybe<&2, J.Json>:
  match e:
    case None{}:
      None{}
    case Some{x}:
      Some{J.Json.get(x, "subsets")}

# The subsets the target endpoints should have: those of the source
# endpoints for a headless source (None when they are missing), else one
# subset at the source cluster IP with the target's ports.
def Ep.expected_subsets(headless: Bool, +f: J.Json, +t: J.Json, from_eps: Maybe<&2, J.Json>) -> Maybe<&2, J.Json>:
  match headless:
    case True{}:
      Ep.subsets_of(from_eps)
    case False{}:
      Some{J.Json.arr([J.JObj{J.JMem{"addresses", J.Json.arr([J.Json.obj([J.KV{"ip", J.JStr{S.Svc.spec_str(f, "clusterIP")}}])]), S.Svc.mem("ports", Ep.convert_ports(J.Json.at(t, ["spec", "ports"])), J.JNil{})}}])}

# The error of a Get of missing source endpoints.
def Ep.not_found(+f: J.Json) -> String:
  "endpoints \"" ++ S.Svc.name(f) ++ "\" not found"

def Ep.with_endpoints.write(+r: Rep, ref: Ref, +s: J.Json, to_eps: Maybe<&2, J.Json>) -> Outcome:
  match to_eps:
    case None{}:
      Ep.done([Ep.create(Ep.to_host(r), KEndpoints{}, S.Svc.put(J.Json.obj([Ep.target_meta(ref)]), "subsets", s))])
    case Some{+e}:
      Ep.done(Ep.update_if(Bool.not(S.Svc.eq(J.Json.get(e, "subsets"), s)), Ep.to_host(r), KEndpoints{}, S.Svc.put(e, "subsets", s)))

def Ep.with_endpoints.exp(exp: Maybe<&2, J.Json>, +r: Rep, ref: Ref, +f: J.Json, to_eps: Maybe<&2, J.Json>) -> Outcome:
  match exp:
    case None{}:
      Outcome{[], Ep.not_found(f)}
    case Some{s}:
      Ep.with_endpoints.write(r, ref, s, to_eps)

def Ep.with_endpoints.ports(differ: Bool, +r: Rep, ref: Ref, +f: J.Json, from_eps: Maybe<&2, J.Json>, +t: J.Json, to_eps: Maybe<&2, J.Json>) -> Outcome:
  match differ:
    case True{}:
      Ep.done([Ep.update(Ep.to_host(r), KService{}, S.Svc.put_in(t, "spec", "ports", J.Json.at(f, ["spec", "ports"])))])
    case False{}:
      Ep.with_endpoints.exp(Ep.expected_subsets(Ep.headless(f), f, t, from_eps), r, ref, f, to_eps)

def Ep.lb_changed(+f: J.Json, +t: J.Json) -> Bool:
  Bool.and(String.eq(S.Svc.spec_str(f, "type"), "LoadBalancer"), Bool.and(String.eq(S.Svc.spec_str(t, "type"), "LoadBalancer"), Bool.not(Ep.struct_eq(J.Json.at(f, ["status", "loadBalancer"]), J.Json.at(t, ["status", "loadBalancer"])))))

def Ep.with_endpoints.lb(changed: Bool, +r: Rep, ref: Ref, +f: J.Json, from_eps: Maybe<&2, J.Json>, +t: J.Json, to_eps: Maybe<&2, J.Json>) -> Outcome:
  match changed:
    case True{}:
      Ep.done([Ep.status(Ep.to_host(r), KService{}, S.Svc.put_in(t, "status", "loadBalancer", J.Json.at(f, ["status", "loadBalancer"])))])
    case False{}:
      Ep.with_endpoints.ports(Bool.not(S.Svc.eq(J.Json.at(t, ["spec", "ports"]), J.Json.at(f, ["spec", "ports"]))), r, ref, f, from_eps, t, to_eps)

def Ep.with_endpoints.some(labelled: Bool, +r: Rep, ref: Ref, +f: J.Json, from_eps: Maybe<&2, J.Json>, +t: J.Json, to_eps: Maybe<&2, J.Json>) -> Outcome:
  match labelled:
    case False{}:
      Ep.done([])
    case True{}:
      Ep.with_endpoints.lb(Ep.lb_changed(f, t), r, ref, f, from_eps, t, to_eps)

# syncServiceAndEndpoints: a missing target is created headless (after its
# namespace, when create_namespace and the namespace is missing); a
# vcluster-made target gets the source load balancer status, then the
# source ports, then its endpoints.
def Ep.with_endpoints(+r: Rep, +ref: Ref, +f: J.Json, from_eps: Maybe<&2, J.Json>, to: Maybe<&2, J.Json>, to_eps: Maybe<&2, J.Json>, ns_exists: Bool) -> Outcome:
  match to:
    case None{}:
      Ep.done(List.append(&2, Write, Ep.namespace_writes(Bool.and(Ep.create_namespace(r), Bool.not(ns_exists)), Ep.to_host(r), ref), [Ep.create(Ep.to_host(r), KService{}, Ep.headless_new(f, ref))]))
    case Some{+t}:
      Ep.with_endpoints.some(Ep.labelled(t), r, ref, f, from_eps, t, to_eps)

def Ep.replicate.sync(eps: Bool, +c: S.Cfg, +r: Rep, +ref: Ref, +f: J.Json, from_eps: Maybe<&2, J.Json>, to: Maybe<&2, J.Json>, to_eps: Maybe<&2, J.Json>, ns_exists: Bool) -> Outcome:
  match eps:
    case True{}:
      Ep.with_endpoints(r, ref, f, from_eps, to, to_eps, ns_exists)
    case False{}:
      Ep.with_selector(c, r, ref, f, to)

def Ep.replicate.from(+c: S.Cfg, +r: Rep, +ref: Ref, from: Maybe<&2, J.Json>, from_eps: Maybe<&2, J.Json>, to: Maybe<&2, J.Json>, to_eps: Maybe<&2, J.Json>, ns_exists: Bool) -> Outcome:
  match from:
    case None{}:
      Ep.done(Ep.delete_target(Ep.to_host(r), ref, to))
    case Some{f}:
      Ep.replicate.sync(Ep.create_endpoints(r), c, r, ref, Ep.strip(f), from_eps, to, to_eps, ns_exists)

def Ep.replicate.to(+c: S.Cfg, +r: Rep, target: Maybe<&2, Ref>, from: Maybe<&2, J.Json>, from_eps: Maybe<&2, J.Json>, to: Maybe<&2, J.Json>, to_eps: Maybe<&2, J.Json>, ns_exists: Bool) -> Outcome:
  match target:
    case None{}:
      Ep.done([])
    case Some{ref}:
      Ep.replicate.from(c, r, ref, from, from_eps, to, to_eps, ns_exists)

# ServiceSyncer Reconcile for source ns/name with mapping ms: from and
# from_eps are the source service and endpoints, to and to_eps the target
# service and endpoints, ns_exists whether the target namespace exists. An
# unmapped request does nothing; a gone source deletes its target; else the
# source, without node ports, is synced by the endpoints path
# (create_endpoints) or the selector path. c gives the vcluster name and
# target namespace for the selector translation.
def Ep.replicate(+c: S.Cfg, +r: Rep, ms: List<&2, Mapping>, +ns: String, +name: String, from: Maybe<&2, J.Json>, from_eps: Maybe<&2, J.Json>, to: Maybe<&2, J.Json>, to_eps: Maybe<&2, J.Json>, ns_exists: Bool) -> Outcome:
  Ep.replicate.to(c, r, Ep.lookup(ns, name, ms), from, from_eps, to, to_eps, ns_exists)
