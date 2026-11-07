import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ./meta.bend as M
import ./names.bend as N

# Services, endpoints and endpoint slices (vcluster
# pkg/controllers/resources/services, endpoints, endpointslices and
# pkg/specialservices), as pure functions of object snapshots.
#
# Objects are bend-kube JSON values (J.Json), as the API server sends them.
# Each syncer step takes the snapshots vcluster's generic syncer hands it
# (host old/new, virtual old/new, or the subset a step reads) and returns
# the writes to make, in a fixed order: host writes before virtual writes,
# a delete before the create that replaces it. A write carries the whole new
# object; an update is returned only when the object changes.
#
# Equality of objects (Svc.eq) is Kubernetes equality up to Go's omitempty:
# object members are compared by key, and a member whose value is null,
# false, 0, [] or {} counts as absent (Svc.canon). Strings are kept, because
# label and annotation values may be "".
#
# Single-namespace mode only. The vcluster name, the target (host) namespace
# and the namespace vcluster runs in are parameters (Cfg), not globals.
# Translate patches (Pro) are not supported and owner references
# (translate.Owner) are not modelled. Name mapping uses the pure name
# translation (names.bend); vcluster's mapping store is not modelled.
#
# vcluster quirks kept as they are:
# - The host kubernetes.io/service-name label of an endpoint slice is the
#   plain concatenation <service>-x-<namespace>-x-<vcluster> (no
#   SafeConcatName, so it may pass 63 characters), read from the host
#   labels after translation (endpointslices/translate.go:17-25, 47-49).
# - Endpoints clear the UID and resource version of a Pod target ref; endpoint
#   slices keep them (endpoints/translate.go:20-46,
#   endpointslices/translate.go:28-37).
# - A selector-less service is the only one whose endpoints and endpoint
#   slices are synced; a host object that vcluster did not make is deleted
#   first, and for a selector service a host object that vcluster made is
#   deleted so that Kubernetes takes it over.
# - On update, the node ports of the virtual service go to the host as they
#   are; only creation strips them (services/translate.go:28).
# - The special default/kubernetes service recreates the virtual service
#   keeping its UID and clearing only the resource version
#   (specialservices/service_syncer.go:76).

# The vcluster name (translate.VClusterName), the target namespace of host
# objects, and the namespace vcluster runs in (ctx.CurrentNamespace).
type Cfg is Data:
  Cfg{vc: String, target: String, current: String}

# corev1.ServicePort. Each field is the JSON value (JNull when absent).
type Port is Data:
  Port{name: J.Json, protocol: J.Json, app_protocol: J.Json, port: J.Json, target_port: J.Json, node_port: J.Json}

# A write to the host or the virtual cluster.
type Write is Data:
  HostCreate{obj: J.Json}
  HostUpdate{obj: J.Json}
  HostDelete{namespace: String, name: String}
  VirtualCreate{obj: J.Json}
  VirtualUpdate{obj: J.Json}
  VirtualDelete{namespace: String, name: String}

# ctrl.Result: no requeue, Requeue: true, or RequeueAfter seconds.
type Requeue is Data:
  NoRequeue{}
  RequeueNow{}
  RequeueAfter{seconds: U32}

# The writes of one sync step and its requeue.
type Outcome is Data:
  Outcome{writes: List<&2, Write>, requeue: Requeue}

# The result of a syncer's ReconcileStart: skip says the generic sync does
# not run; err is the error text, "" for none.
type Start is Data:
  Start{skip: Bool, writes: List<&2, Write>, err: String}

# One spec field after patcher.CopyBidirectional: its new virtual and host
# values.
type Pick is Data:
  Pick{key: String, virtual: J.Json, host: J.Json}

# The canonical form: object members sorted by key, members whose value is
# zero (after their own members are made canonical) dropped; array items
# keep their order.
def Svc.canon(j: J.Json) -> J.Json:
  ?TODO

# apiequality.Semantic.DeepEqual of two values, up to omitempty.
def Svc.eq(a: J.Json, b: J.Json) -> Bool:
  ?TODO

# An outcome with every object in canonical form.
def Svc.canon_outcome(o: Outcome) -> Outcome:
  ?TODO

# A start with every object in canonical form.
def Svc.canon_start(s: Start) -> Start:
  ?TODO

# The host label key of each key (translate.HostLabel).
def Svc.hl_keys(+vc: String, ks: +List<String>) -> +List<String>:
  ?TODO

# The ports of a JSON port list.
def Svc.ports(j: J.Json) -> +List<Port>:
  ?TODO

# A port list as JSON; null when empty.
def Svc.ports_json(ps: +List<Port>) -> J.Json:
  ?TODO

# services.StripNodePorts: every nodePort cleared.
def Svc.strip_node_ports(ps: +List<Port>) -> +List<Port>:
  ?TODO

# services.TranslateServicePorts: the port named "kubelet" dropped; each
# other port keeps only name, protocol, appProtocol, port and targetPort.
def Svc.translate_ports(ps: +List<Port>) -> +List<Port>:
  ?TODO

# What a port is apart from its node port: [name, protocol, appProtocol,
# port, targetPort].
def Svc.port_id(p: Port) -> J.Json:
  ?TODO

def Svc.port_ids(ps: +List<Port>) -> List<&2, J.Json>:
  ?TODO

# The host selector of a new host service: translate.HostLabelsMap(vSelector,
# nil, vNamespace, false), so the markers are always added.
def Svc.host_selector(vc: String, target: String, ns: String, sel: Maybe<&2, List<&2, M.KV>>) -> Maybe<&2, List<&2, M.KV>>:
  ?TODO

# The keys a host selector may use for a virtual selector: the two markers,
# and the host key of each virtual key.
def Svc.selector_allowed(vc: String, sel: +List<M.KV>) -> +List<String>:
  ?TODO

# True when every key of m is one of a.
def Svc.keys_in(m: +List<M.KV>, +a: +List<String>) -> Bool:
  ?TODO

# services SyncToHost: the virtual service exists, the host one does not.
# host_old is the cached host object: when it was there, the host service
# was deleted, and so is the virtual one.
def Svc.sync_to_host(+c: Cfg, host_old: Maybe<&2, J.Json>, +v: J.Json) -> Outcome:
  ?TODO

# services SyncToVirtual: the host service exists, the virtual one does not.
# young: the host service is less than two minutes old. A young host service
# with vcluster.loft.sh/block-deletion: "true" waits 10 seconds; a host
# service whose virtual one was seen (virtual_old) or that vcluster made
# (translate.ShouldDeleteHostObject) is deleted; any other is copied back.
def Svc.sync_to_virtual(+c: Cfg, young: Bool, virtual_old: Maybe<&2, J.Json>, +h: J.Json) -> Outcome:
  ?TODO

# services Sync: both services exist. While the virtual service turns into
# an ExternalName service the step waits 3 seconds; when the cluster IPs
# differ the virtual service is recreated with the host one and the step
# requeues; else the two services are synced.
def Svc.sync(+c: Cfg, +host_old: J.Json, +host: J.Json, +virtual_old: J.Json, +virtual: J.Json) -> Outcome:
  ?TODO

# services ReconcileStart: true for the special services (default/kubernetes),
# which Svc.sync_kubernetes syncs instead of the generic sync.
def Svc.services_start(+ns: String, +name: String) -> Bool:
  ?TODO

# specialservices.SyncKubernetesService: host is the vcluster's own service,
# virtual the virtual default/kubernetes service. When the cluster IPs
# differ the virtual service is recreated; when only the translated ports
# differ it is updated.
def Svc.sync_kubernetes(host: Maybe<&2, J.Json>, virtual: Maybe<&2, J.Json>) -> Outcome:
  ?TODO

# endpoints SyncToHost: delete the virtual endpoints when the host ones were
# deleted (host_old), else create the host endpoints.
def Svc.endpoints_sync_to_host(+c: Cfg, host_old: Maybe<&2, J.Json>, +v: J.Json) -> Outcome:
  ?TODO

# endpoints Sync: the host subsets are the translated virtual ones; then
# annotations and labels both ways.
def Svc.endpoints_sync(+c: Cfg, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> Outcome:
  ?TODO

# endpoints and endpoint slices SyncToVirtual: the host object goes.
def Svc.endpoints_sync_to_virtual(+h: J.Json) -> Outcome:
  ?TODO

# endpoints ReconcileStart for request ns/name: svc is the virtual service
# ns/name, host the host endpoints of the request. default/kubernetes is
# skipped.
def Svc.endpoints_start(+ns: String, +name: String, svc: Maybe<&2, J.Json>, host: Maybe<&2, J.Json>) -> Start:
  ?TODO

# endpointslices SyncToHost.
def Svc.slice_sync_to_host(+c: Cfg, host_old: Maybe<&2, J.Json>, +v: J.Json) -> Outcome:
  ?TODO

# endpointslices Sync: the host endpoints are the translated virtual ones;
# then annotations and labels both ways.
def Svc.slice_sync(+c: Cfg, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> Outcome:
  ?TODO

# endpointslices ReconcileStart for request ns/name: eps is the virtual
# endpoint slice ns/name, svc the virtual service its
# kubernetes.io/service-name label names (unused without the label), host
# the host endpoint slice of the request. default/kubernetes is skipped; a
# gone virtual slice deletes the host one.
def Svc.slice_start(+ns: String, +name: String, eps: Maybe<&2, J.Json>, svc: Maybe<&2, J.Json>, host: Maybe<&2, J.Json>) -> Start:
  ?TODO
