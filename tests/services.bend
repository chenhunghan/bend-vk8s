import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/translate/meta.bend as M
import ../src/translate/services.bend as S

# Tests for src/translate/services.bend. The laws in laws/services.bend
# transcribe vcluster's syncer tests; these cover the rest of the services,
# endpoints, endpointslices and special-services logic: headless services,
# excluded annotations, Pod target refs, the long service-name label, the
# ExternalName switch, block-deletion, deletes, ReconcileStart branches,
# TranslateServicePorts and label translation. Expected values follow
# vcluster's Go code (VClusterName "suffix", target namespace "test",
# current namespace "vcluster", as in its tests). Objects print in
# canonical form: keys sorted by byte, zero values left out.

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

def show_start(s: S.Start) -> String:
  match s:
    case S.Start{True{}, ws, e}:
      "skip; " ++ show_writes(ws) ++ e
    case S.Start{False{}, ws, e}:
      "sync; " ++ show_writes(ws) ++ e

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

def last_of(ws: List<&2, S.Write>, acc: J.Json) -> J.Json:
  match ws:
    case Nil{}:
      acc
    case Con{w, r}:
      last_of(r, write_obj(w))

# The object of the last write of an outcome.
def last(o: S.Outcome) -> J.Json:
  match o:
    case S.Outcome{ws, rq}:
      last_of(ws, J.JNull{})

def show_bool(b: Bool) -> String:
  match b:
    case True{}:
      "true"
    case False{}:
      "false"

def at(+o: J.Json, path: List<&2, String>) -> String:
  show(J.Json.at(o, path))

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
    # translate: ClusterIP "None" stays; clusterIPs, ipFamilies, ipFamilyPolicy
    # and node ports go (services/translate.go:10-30).
    check("create keeps a headless cluster IP",
      at(first(S.Svc.sync_to_host(cfg(), None{}, js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"ns1\"},\"spec\":{\"type\":\"ClusterIP\",\"clusterIP\":\"None\",\"clusterIPs\":[\"None\"],\"ipFamilies\":[\"IPv4\"],\"ipFamilyPolicy\":\"SingleStack\",\"ports\":[{\"name\":\"a\",\"port\":80,\"nodePort\":30000}]}}"))), ["spec"]),
      "{\"clusterIP\":\"None\",\"ports\":[{\"name\":\"a\",\"port\":80}],\"type\":\"ClusterIP\"}")
    check("create clears a cluster IP",
      at(first(S.Svc.sync_to_host(cfg(), None{}, js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"ns1\"},\"spec\":{\"type\":\"ClusterIP\",\"clusterIP\":\"10.0.0.1\",\"clusterIPs\":[\"10.0.0.1\"]}}"))), ["spec"]),
      "{\"type\":\"ClusterIP\"}")
    check("create names the host service",
      sp(at(first(S.Svc.sync_to_host(cfg(), None{}, js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"ns1\",\"uid\":\"u\",\"resourceVersion\":\"7\"}}"))), ["metadata", "name"]),
        sp(at(first(S.Svc.sync_to_host(cfg(), None{}, js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"ns1\",\"uid\":\"u\",\"resourceVersion\":\"7\"}}"))), ["metadata", "namespace"]),
          at(first(S.Svc.sync_to_host(cfg(), None{}, js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"ns1\",\"uid\":\"u\",\"resourceVersion\":\"7\"}}"))), ["metadata", "resourceVersion"]))),
      "\"s-x-ns1-x-suffix\" \"test\" null")
    # field.cattle.io/publicEndpoints is excluded (services/syncer.go:28, 44-46).
    check("create drops the Rancher annotation",
      at(first(S.Svc.sync_to_host(cfg(), None{}, js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"ns1\",\"uid\":\"u1\",\"annotations\":{\"field.cattle.io/publicEndpoints\":\"x\",\"keep\":\"y\"}}}"))), ["metadata", "annotations"]),
      "{\"keep\":\"y\",\"vcluster.loft.sh/managed-annotations\":\"keep\",\"vcluster.loft.sh/object-host-name\":\"s-x-ns1-x-suffix\",\"vcluster.loft.sh/object-host-namespace\":\"test\",\"vcluster.loft.sh/object-kind\":\"/v1, Kind=Service\",\"vcluster.loft.sh/object-name\":\"s\",\"vcluster.loft.sh/object-namespace\":\"ns1\",\"vcluster.loft.sh/object-uid\":\"u1\"}")
    # HostLabelsMap(vSelector, nil, ns, false) translates release and adds the markers.
    check("create translates the selector",
      at(first(S.Svc.sync_to_host(cfg(), None{}, js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"ns1\"},\"spec\":{\"selector\":{\"release\":\"r\",\"app\":\"a\"}}}"))), ["spec", "selector"]),
      "{\"app\":\"a\",\"vcluster.loft.sh/label-suffix-x-a4d451ec23\":\"r\",\"vcluster.loft.sh/managed-by\":\"suffix\",\"vcluster.loft.sh/namespace\":\"ns1\"}")
    check("create keeps an empty selector non-nil",
      at(first(S.Svc.sync_to_host(cfg(), None{}, js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"ns1\"},\"spec\":{\"selector\":{}}}"))), ["spec", "selector"]),
      "{\"vcluster.loft.sh/managed-by\":\"suffix\",\"vcluster.loft.sh/namespace\":\"ns1\"}")
    # SyncToHost: a cached host object or a deleting virtual one deletes the virtual service.
    check("host gone deletes the virtual service",
      show_out(S.Svc.sync_to_host(cfg(), Some{js("{}")}, js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"ns1\"}}"))),
      "virtual delete ns1/s; done")
    check("deleting virtual service is deleted",
      show_out(S.Svc.sync_to_host(cfg(), None{}, js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"ns1\",\"deletionTimestamp\":\"2026-01-01T00:00:00Z\"}}"))),
      "virtual delete ns1/s; done")
    # Sync: switching to ExternalName waits 3s (services/syncer.go:90-92).
    check("switch to ExternalName waits",
      show_out(S.Svc.sync(cfg(), js("{\"spec\":{\"type\":\"ClusterIP\",\"clusterIP\":\"10.0.0.1\"}}"), js("{\"spec\":{\"type\":\"ClusterIP\",\"clusterIP\":\"10.0.0.1\"}}"),
        js("{\"spec\":{\"type\":\"ClusterIP\"}}"), js("{\"spec\":{\"type\":\"ExternalName\",\"externalName\":\"x.com\"}}"))),
      "after 3")
    # SyncToVirtual (services/syncer.go:228-249).
    check("young block-deletion host service waits",
      show_out(S.Svc.sync_to_virtual(cfg(), True{}, None{}, js("{\"metadata\":{\"name\":\"h\",\"namespace\":\"test\",\"annotations\":{\"vcluster.loft.sh/block-deletion\":\"true\"}}}"))),
      "after 10")
    check("old block-deletion host service is copied back",
      show_out(S.Svc.sync_to_virtual(cfg(), False{}, None{}, js("{\"metadata\":{\"name\":\"h\",\"namespace\":\"test\",\"annotations\":{\"vcluster.loft.sh/block-deletion\":\"true\",\"vcluster.loft.sh/object-name\":\"s\",\"vcluster.loft.sh/object-namespace\":\"ns1\"}}}"))),
      "virtual create; done")
    check("host service of a deleted virtual one is deleted",
      show_out(S.Svc.sync_to_virtual(cfg(), False{}, Some{js("{}")}, js("{\"metadata\":{\"name\":\"h\",\"namespace\":\"test\"}}"))),
      "host delete test/h; done")
    check("synced host service is deleted",
      show_out(S.Svc.sync_to_virtual(cfg(), False{}, None{}, js("{\"metadata\":{\"name\":\"s-x-ns1-x-suffix\",\"namespace\":\"test\",\"annotations\":{\"vcluster.loft.sh/object-kind\":\"/v1, Kind=Service\",\"vcluster.loft.sh/object-name\":\"s\",\"vcluster.loft.sh/object-namespace\":\"ns1\",\"vcluster.loft.sh/object-host-name\":\"s-x-ns1-x-suffix\",\"vcluster.loft.sh/object-host-namespace\":\"test\"}}}"))),
      "host delete test/s-x-ns1-x-suffix; done")
    check("copied back service gets its virtual name",
      at(first(S.Svc.sync_to_virtual(cfg(), False{}, None{}, js("{\"metadata\":{\"name\":\"h\",\"namespace\":\"test\",\"annotations\":{\"vcluster.loft.sh/object-name\":\"s\",\"vcluster.loft.sh/object-namespace\":\"ns1\"},\"labels\":{\"vcluster.loft.sh/managed-by\":\"suffix\",\"app\":\"a\"}},\"spec\":{\"ipFamilies\":[\"IPv4\"],\"selector\":{\"vcluster.loft.sh/label-suffix-x-a4d451ec23\":\"r\"}}}"))), []),
      "{\"metadata\":{\"labels\":{\"app\":\"a\"},\"name\":\"s\",\"namespace\":\"ns1\"},\"spec\":{\"selector\":{\"release\":\"r\"}}}")
    # Sync: a host label change comes back without vcluster's own labels.
    check("host label change comes back",
      at(last(S.Svc.sync(cfg(), js("{\"metadata\":{\"labels\":{\"vcluster.loft.sh/managed-by\":\"suffix\"}}}"), js("{\"metadata\":{\"labels\":{\"vcluster.loft.sh/managed-by\":\"suffix\",\"app\":\"x\"}}}"),
        js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"ns1\"}}"), js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"ns1\"}}"))), ["metadata", "labels"]),
      "{\"app\":\"x\"}")
    check("virtual label change goes to the host",
      at(first(S.Svc.sync(cfg(), js("{\"metadata\":{\"labels\":{\"vcluster.loft.sh/managed-by\":\"suffix\"}}}"), js("{\"metadata\":{\"labels\":{\"vcluster.loft.sh/managed-by\":\"suffix\"}}}"),
        js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"ns1\"}}"), js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"ns1\",\"labels\":{\"release\":\"r\"}}}"))), ["metadata", "labels"]),
      "{\"vcluster.loft.sh/label-suffix-x-a4d451ec23\":\"r\",\"vcluster.loft.sh/managed-by\":\"suffix\"}")
    # Sync: a host selector change, with the virtual one unchanged, comes back.
    check("host selector change comes back",
      at(last(S.Svc.sync(cfg(), js("{\"spec\":{\"selector\":{\"app\":\"a\"}}}"), js("{\"spec\":{\"selector\":{\"app\":\"b\"}}}"),
        js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"ns1\"},\"spec\":{\"selector\":{\"app\":\"a\"}}}"), js("{\"metadata\":{\"name\":\"s\",\"namespace\":\"ns1\"},\"spec\":{\"selector\":{\"app\":\"a\"}}}"))), ["spec", "selector"]),
      "{\"app\":\"b\"}")
    # TranslateServicePorts (services/syncer.go:292-310).
    check("translate ports drops kubelet and node ports",
      show(S.Svc.ports_json(S.Svc.translate_ports(S.Svc.ports(js("[{\"name\":\"kubelet\",\"port\":10250},{\"name\":\"https\",\"port\":443,\"nodePort\":31000,\"protocol\":\"TCP\",\"targetPort\":6443}]"))))),
      "[{\"name\":\"https\",\"port\":443,\"protocol\":\"TCP\",\"targetPort\":6443}]")
    check("kubernetes service in sync",
      show_out(S.Svc.sync_kubernetes(Some{js("{\"spec\":{\"clusterIP\":\"10.0.0.1\",\"clusterIPs\":[\"10.0.0.1\"],\"ports\":[{\"name\":\"https\",\"port\":443,\"nodePort\":31000},{\"name\":\"kubelet\",\"port\":10250}]}}")},
        Some{js("{\"metadata\":{\"name\":\"kubernetes\",\"namespace\":\"default\"},\"spec\":{\"clusterIP\":\"10.0.0.1\",\"clusterIPs\":[\"10.0.0.1\"],\"ports\":[{\"name\":\"https\",\"port\":443}]}}")})),
      "done")
    check("kubernetes service with new cluster IPs is recreated",
      show_out(S.Svc.sync_kubernetes(Some{js("{\"spec\":{\"clusterIP\":\"10.0.0.1\",\"clusterIPs\":[\"10.0.0.1\",\"fd00::1\"]}}")},
        Some{js("{\"metadata\":{\"name\":\"kubernetes\",\"namespace\":\"default\"},\"spec\":{\"clusterIP\":\"10.0.0.1\",\"clusterIPs\":[\"10.0.0.1\"]}}")})),
      "virtual delete default/kubernetes; virtual create; done")
    check("services start for default/kubernetes",
      sp(show_start(S.Start{S.Svc.services_start("default", "kubernetes"), [], ""}), show_start(S.Start{S.Svc.services_start("default", "web"), [], ""})),
      "skip;  sync; ")
    # endpoints translateSpec: Pod target refs point at the host pod, UID and
    # resource version cleared (endpoints/translate.go:20-46).
    check("endpoints translate pod target refs",
      at(first(S.Svc.endpoints_sync_to_host(cfg(), None{}, js("{\"metadata\":{\"name\":\"ep\",\"namespace\":\"test\"},\"subsets\":[{\"addresses\":[{\"ip\":\"1.1.1.1\",\"targetRef\":{\"kind\":\"Pod\",\"name\":\"p\",\"namespace\":\"test\",\"uid\":\"u1\",\"resourceVersion\":\"5\"}}],\"notReadyAddresses\":[{\"ip\":\"2.2.2.2\",\"targetRef\":{\"kind\":\"Pod\",\"name\":\"q\",\"namespace\":\"other\"}}]}]}"))), ["subsets"]),
      "[{\"addresses\":[{\"ip\":\"1.1.1.1\",\"targetRef\":{\"kind\":\"Pod\",\"name\":\"p-x-test-x-suffix\",\"namespace\":\"test\"}}],\"notReadyAddresses\":[{\"ip\":\"2.2.2.2\",\"targetRef\":{\"kind\":\"Pod\",\"name\":\"q-x-other-x-suffix\",\"namespace\":\"test\"}}]}]")
    check("endpoints keep other target refs",
      at(first(S.Svc.endpoints_sync_to_host(cfg(), None{}, js("{\"metadata\":{\"name\":\"ep\",\"namespace\":\"test\"},\"subsets\":[{\"addresses\":[{\"ip\":\"1.1.1.1\",\"targetRef\":{\"kind\":\"Node\",\"name\":\"n1\",\"uid\":\"u\"}}]}]}"))), ["subsets"]),
      "[{\"addresses\":[{\"ip\":\"1.1.1.1\",\"targetRef\":{\"kind\":\"Node\",\"name\":\"n1\",\"uid\":\"u\"}}]}]")
    check("endpoints drop the leader annotation",
      at(first(S.Svc.endpoints_sync_to_host(cfg(), None{}, js("{\"metadata\":{\"name\":\"ep\",\"namespace\":\"test\",\"annotations\":{\"control-plane.alpha.kubernetes.io/leader\":\"x\"}}}"))), ["metadata", "annotations", "control-plane.alpha.kubernetes.io/leader"]),
      "null")
    check("host endpoints gone deletes the virtual ones",
      show_out(S.Svc.endpoints_sync_to_host(cfg(), Some{js("{}")}, js("{\"metadata\":{\"name\":\"ep\",\"namespace\":\"test\"}}"))),
      "virtual delete test/ep; done")
    check("virtual endpoints gone deletes the host ones",
      show_out(S.Svc.endpoints_sync_to_virtual(js("{\"metadata\":{\"name\":\"ep-x-test-x-suffix\",\"namespace\":\"test\"}}"))),
      "host delete test/ep-x-test-x-suffix; done")
    # endpoints ReconcileStart (endpoints/syncer.go:148-212).
    check("endpoints of a missing service are skipped",
      show_start(S.Svc.endpoints_start("test", "ep", None{}, Some{js("{\"metadata\":{\"name\":\"ep-x-test-x-suffix\",\"namespace\":\"test\"}}")})),
      "skip; ")
    check("managed endpoints of a selector service are deleted",
      show_start(S.Svc.endpoints_start("test", "ep", Some{js("{\"spec\":{\"selector\":{\"app\":\"a\"}}}")},
        Some{js("{\"metadata\":{\"name\":\"ep-x-test-x-suffix\",\"namespace\":\"test\",\"annotations\":{\"vcluster.loft.sh/object-name\":\"ep\"}}}")})),
      "skip; host delete test/ep-x-test-x-suffix; ")
    check("unmanaged endpoints of a selector service stay",
      show_start(S.Svc.endpoints_start("test", "ep", Some{js("{\"spec\":{\"selector\":{\"app\":\"a\"}}}")},
        Some{js("{\"metadata\":{\"name\":\"ep-x-test-x-suffix\",\"namespace\":\"test\"}}")})),
      "skip; ")
    check("managed endpoints of a selector-less service stay",
      show_start(S.Svc.endpoints_start("test", "ep", Some{js("{\"spec\":{}}")},
        Some{js("{\"metadata\":{\"name\":\"ep-x-test-x-suffix\",\"namespace\":\"test\",\"annotations\":{\"vcluster.loft.sh/object-name\":\"ep\"}}}")})),
      "sync; ")
    # endpointslices translate: the service-name label is a plain
    # concatenation, even past 63 characters (endpointslices/translate.go:47-49).
    check("slice service-name label is not shortened",
      at(first(S.Svc.slice_sync_to_host(cfg(), None{}, js("{\"metadata\":{\"name\":\"eps\",\"namespace\":\"test\",\"labels\":{\"kubernetes.io/service-name\":\"a-very-long-service-name-for-the-endpoint-slice-label-quirk\"}}}"))), ["metadata", "labels", "kubernetes.io/service-name"]),
      "\"a-very-long-service-name-for-the-endpoint-slice-label-quirk-x-test-x-suffix\"")
    check("slice without service-name label gets one",
      at(first(S.Svc.slice_sync_to_host(cfg(), None{}, js("{\"metadata\":{\"name\":\"eps\",\"namespace\":\"test\"}}"))), ["metadata", "labels", "kubernetes.io/service-name"]),
      "\"-x-test-x-suffix\"")
    check("slice keeps pod target ref UIDs",
      at(first(S.Svc.slice_sync_to_host(cfg(), None{}, js("{\"metadata\":{\"name\":\"eps\",\"namespace\":\"test\",\"labels\":{\"kubernetes.io/service-name\":\"s\"}},\"endpoints\":[{\"addresses\":[\"1.1.1.1\"],\"targetRef\":{\"kind\":\"Pod\",\"name\":\"p\",\"namespace\":\"test\",\"uid\":\"u1\"}}]}"))), ["endpoints"]),
      "[{\"addresses\":[\"1.1.1.1\"],\"targetRef\":{\"kind\":\"Pod\",\"name\":\"p-x-test-x-suffix\",\"namespace\":\"test\",\"uid\":\"u1\"}}]")
    # endpointslices ReconcileStart (endpointslices/syncer.go:116-209).
    check("gone virtual slice deletes the host one",
      show_start(S.Svc.slice_start("test", "eps", None{}, None{}, Some{js("{\"metadata\":{\"name\":\"eps-x-test-x-suffix\",\"namespace\":\"test\"}}")})),
      "skip; host delete test/eps-x-test-x-suffix; ")
    check("slice without service-name label is an error",
      show_start(S.Svc.slice_start("test", "eps", Some{js("{\"metadata\":{\"name\":\"eps\",\"namespace\":\"test\"}}")}, None{}, None{})),
      "skip; unable to retrieve label 'kubernetes.io/service-name'")
    check("managed slice of a selector service is deleted",
      show_start(S.Svc.slice_start("test", "eps", Some{js("{\"metadata\":{\"name\":\"eps\",\"namespace\":\"test\",\"labels\":{\"kubernetes.io/service-name\":\"s\"}}}")},
        Some{js("{\"spec\":{\"selector\":{\"app\":\"a\"}}}")},
        Some{js("{\"metadata\":{\"name\":\"eps-x-test-x-suffix\",\"namespace\":\"test\",\"annotations\":{\"vcluster.loft.sh/object-name\":\"eps\"}}}")})),
      "skip; host delete test/eps-x-test-x-suffix; ")
    check("slice of a missing service is skipped",
      show_start(S.Svc.slice_start("test", "eps", Some{js("{\"metadata\":{\"name\":\"eps\",\"namespace\":\"test\",\"labels\":{\"kubernetes.io/service-name\":\"s\"}}}")}, None{}, None{})),
      "skip; ")
    check("default/kubernetes slice is skipped",
      show_start(S.Svc.slice_start("default", "kubernetes", None{}, None{}, Some{js("{\"metadata\":{\"name\":\"suffix\",\"namespace\":\"vcluster\"}}")})),
      "skip; ")
    # Mapping of default/kubernetes (mappings/resources/services.go:74-82).
    check("default/kubernetes maps to the vcluster service",
      sp(at(first(S.Svc.endpoints_sync_to_host(cfg(), None{}, js("{\"metadata\":{\"name\":\"kubernetes\",\"namespace\":\"default\"}}"))), ["metadata", "namespace"]),
        at(first(S.Svc.endpoints_sync_to_host(cfg(), None{}, js("{\"metadata\":{\"name\":\"kubernetes\",\"namespace\":\"default\"}}"))), ["metadata", "name"])),
      "\"vcluster\" \"suffix\"")
    # Svc.eq: omitempty and nil slices.
    check("equality ignores member order and zero values",
      sp(show_bool(S.Svc.eq(js("{\"a\":1,\"b\":{\"c\":[],\"d\":false},\"e\":\"\"}"), js("{\"e\":\"\",\"a\":1}"))),
        sp(show_bool(S.Svc.eq(js("[]"), J.JNull{})),
          sp(show_bool(S.Svc.eq(js("{}"), J.JNull{})), show_bool(S.Svc.eq(js("{\"e\":\"\"}"), js("{}")))))),
      "true true false false")
