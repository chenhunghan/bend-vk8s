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
type Kind is Data:
  KService{}
  KEndpoints{}
  KEndpointSlice{}
  KEndpointSliceV1Beta1{}
  KNamespace{}

# A write to the host or the virtual cluster. A status write is
# Status().Update.
type Write is Data:
  HostCreate{kind: Kind, obj: J.Json}
  HostUpdate{kind: Kind, obj: J.Json}
  HostStatus{kind: Kind, obj: J.Json}
  HostDelete{kind: Kind, namespace: String, name: String}
  VirtualCreate{kind: Kind, obj: J.Json}
  VirtualUpdate{kind: Kind, obj: J.Json}
  VirtualStatus{kind: Kind, obj: J.Json}
  VirtualDelete{kind: Kind, namespace: String, name: String}

# The writes of one step, and its error text ("" for none). These
# controllers never ask for a requeue; an error requeues with backoff.
type Outcome is Data:
  Outcome{writes: List<&2, Write>, err: String}

# One entry of a servicesync mapping: the source service
# from_namespace/from_name and its target to_namespace/to_name.
type Mapping is Data:
  Mapping{from_namespace: String, from_name: String, to_namespace: String, to_name: String}

# A servicesync controller: to_host is IsVirtualToHostSyncer (the source is
# virtual and the target on the host); create_namespace and
# create_endpoints as in servicesync.ServiceSyncer.
type Rep is Data:
  Rep{to_host: Bool, create_namespace: Bool, create_endpoints: Bool}

def Ep.canon_writes(ws: List<&2, Write>) -> List<&2, Write>:
  ?TODO

def Ep.canon_outcome(o: Outcome) -> Outcome:
  ?TODO

def Ep.should_use_legacy(kinds: Maybe<&2, List<&2, String>>) -> Bool:
  ?TODO

def Ep.slice_create_or_patch(legacy: Bool, +e: J.Json, vs: Maybe<&2, J.Json>) -> List<&2, Write>:
  ?TODO

def Ep.sync_default(legacy: Bool, host: Maybe<&2, J.Json>, ve: Maybe<&2, J.Json>, vs: Maybe<&2, J.Json>) -> Outcome:
  ?TODO

def Ep.ips(o: J.Json) -> List<&2, String>:
  ?TODO

def Ep.port_names(o: J.Json) -> List<&2, String>:
  ?TODO

def Ep.slice_ips(o: J.Json) -> List<&2, String>:
  ?TODO

def Ep.slice_port_names(o: J.Json) -> List<&2, String>:
  ?TODO

def Ep.standalone_endpoints(ip: String, port: U32) -> J.Json:
  ?TODO

def Ep.standalone_slice(+ip: String, port: U32) -> J.Json:
  ?TODO

def Ep.standalone_sync(ip: String, port: U32, ve: Maybe<&2, J.Json>, vs: Maybe<&2, J.Json>) -> Outcome:
  ?TODO

def Ep.reverse(+ns: String, +name: String, ms: List<&2, Mapping>) -> Maybe<&2, String & String>:
  ?TODO

def Ep.replicate(+c: S.Cfg, +r: Rep, ms: List<&2, Mapping>, +ns: String, +name: String, from: Maybe<&2, J.Json>, from_eps: Maybe<&2, J.Json>, to: Maybe<&2, J.Json>, to_eps: Maybe<&2, J.Json>, ns_exists: Bool) -> Outcome:
  ?TODO
