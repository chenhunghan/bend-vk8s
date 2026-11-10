import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/sync/runtime.bend as R
import ../src/translate/services.bend as S
import ../src/guest/plan.bend as P
import ../src/sync/core.bend as C
import ./configs.bend as LC
import ./services.bend as LS
import ../src/config/vcluster.bend as V

# Proposed: runtime policy. Expected defaults and names come from vcluster
# a8ab30e chart/values.yaml, pkg/controllers/resources/register.go and
# pkg/util/translate/single_namespace.go. Ordering and the virtual Lease
# are the architect's explicit vk8s contract, not upstream defaults.

law runtime.defaults:
  {R.Runtime.defaults() == ["services", "endpoints", "endpointslices", "configmaps", "secrets", "pods",
    "fake-nodes", "events", "persistentvolumeclaims", "fake-persistentvolumes"] : +List<String>}

law runtime.host_name:
  {R.Runtime.host_name("suffix", "testns", "testservice") == "testservice-x-testns-x-suffix" : String}

law runtime.selector:
  {R.Runtime.selector("suffix") == "vcluster.loft.sh/managed-by=suffix" : String}

law runtime.virtual_key:
  {R.Runtime.virtual_key([J.KV{"vcluster.loft.sh/object-name", J.JStr{"testservice"}},
     J.KV{"vcluster.loft.sh/object-namespace", J.JStr{"testns"}}]) == ("testns", "testservice") : String & String}

law runtime.unannotated_key:
  {R.Runtime.virtual_key([]) == ("", "") : String & String}

law runtime.lease_name:
  {R.Runtime.lease_name("suffix") == "vcluster-suffix-controller" : String}

law runtime.no_requeue:
  {R.Runtime.delay(S.NoRequeue{}) == 0 : U32}

law runtime.requeue_now:
  {R.Runtime.delay(S.RequeueNow{}) == 0 : U32}

law runtime.one_second:
  {R.Runtime.delay(S.RequeueAfter{1}) == 1000 : U32}

law runtime.delay_saturates:
  {R.Runtime.delay(S.RequeueAfter{4294968}) == 4294967295 : U32}

law runtime.empty_order:
  {R.Runtime.order([]) == [] : List<&2, S.Write>}

# General invariants, quantified over arbitrary objects and keys.
law runtime.host_before_virtual:
  for v: J.Json
  for h: J.Json
  {R.Runtime.order([S.VirtualUpdate{v}, S.HostUpdate{h}])
    == [S.HostUpdate{h}, S.VirtualUpdate{v}] : List<&2, S.Write>}

law runtime.host_delete_before_create:
  for ns: String
  for name: String
  for h: J.Json
  {R.Runtime.order([S.HostCreate{h}, S.HostDelete{ns, name}])
    == [S.HostDelete{ns, name}, S.HostCreate{h}] : List<&2, S.Write>}

law runtime.virtual_delete_before_create:
  for ns: String
  for name: String
  for v: J.Json
  {R.Runtime.order([S.VirtualCreate{v}, S.VirtualDelete{ns, name}])
    == [S.VirtualDelete{ns, name}, S.VirtualCreate{v}] : List<&2, S.Write>}

law runtime.stable_host_updates:
  for a: J.Json
  for b: J.Json
  {R.Runtime.order([S.HostUpdate{a}, S.HostUpdate{b}])
    == [S.HostUpdate{a}, S.HostUpdate{b}] : List<&2, S.Write>}

law runtime.stable_virtual_updates:
  for a: J.Json
  for b: J.Json
  {R.Runtime.order([S.VirtualUpdate{a}, S.VirtualUpdate{b}])
    == [S.VirtualUpdate{a}, S.VirtualUpdate{b}] : List<&2, S.Write>}

law runtime.keeps_requeue:
  for ws: List<&2, S.Write>
  for rq: S.Requeue
  {R.Runtime.requeue(R.Runtime.ordered(S.Outcome{ws, rq})) == rq : S.Requeue}

# Proposed: normal Service dispatch through the merged generic framework.
# services/syncer.go SyncToHost deletes the virtual Service when HostOld
# exists and Host is absent. No old host means creation, not deletion.
# These are adapter regressions; upstream translator test mappings remain
# in laws/services.bend and framework mappings in laws/core.bend.
law runtime.service_host_deleted:
  {R.Runtime.services(S.Cfg{"suffix", "test", "vcluster"}, False{}, True{}, None{},
    Some{J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"s"}}, J.KV{"namespace", J.JStr{"ns"}}, J.KV{"resourceVersion", J.JStr{"2"}}])}])},
    Some{J.JNull{}}, None{}) == S.Outcome{[S.VirtualDelete{"ns", "s"}], S.NoRequeue{}} : S.Outcome}

law runtime.service_no_objects:
  for c: S.Cfg
  for young: Bool
  for managed: Bool
  for vo: Maybe<&2, J.Json>
  for ho: Maybe<&2, J.Json>
  {R.Runtime.services(c, young, managed, vo, None{}, ho, None{})
    == S.Outcome{[], S.NoRequeue{}} : S.Outcome}


# Proposed: classic mode has no local worker processes. Keep the existing
# standalone Cfg and Plan.boot contract fixed; use a separate Plan.classic.
def Laws.runtime.no_worker(ss: +List<P.Step>) -> Bool:
  match ss:
    case Nil{}:
      True{}
    case Con{P.Daemon{+name, prog, args}, rest}:
      Bool.and(Bool.not(Bool.or(String.eq(name, "kubelet"),
        Bool.or(String.eq(name, "containerd"), Bool.or(String.eq(name, "flannel"), String.eq(name, "kube-proxy"))))),
        Laws.runtime.no_worker(rest))
    case Con{step, rest}:
      Laws.runtime.no_worker(rest)

law runtime.classic_no_worker:
  {Laws.runtime.no_worker(P.Plan.classic(P.Plan.default_cfg("demo", 6443, True{}),
    "/var/lib/vk8s-host/host-kubeconfig", "host-ns")) == True{} : Bool}

law runtime.classic_syncer:
  {P.Plan.syncer(P.Plan.default_cfg("demo", 6443, True{}), "/var/lib/vk8s-host/host-kubeconfig", "host-ns")
    == P.Daemon{"syncer", "/usr/bin/vk8s-guest", ["syncer", "--host-kubeconfig", "/var/lib/vk8s-host/host-kubeconfig",
      "--host-namespace", "host-ns", "--name", "demo", "--service-cidr", "10.96.0.0/12"]} : P.Step}


# Proposed: services/syncer.go Options sets DisableUIDDeletion=true.
# Service replacement must retain its host allocation despite a new UID.
law runtime.service_options:
  {R.Runtime.service_cfg(S.Cfg{"suffix", "test", "vcluster"})
    == C.Cfg{"suffix", "test", "/v1, Kind=Service", "service", True{}, False{}, False{}} : C.Cfg}



# Proposed: dispatcher regressions using the existing upstream fixtures.
# configmaps/to_host_syncer_test.go: unused and used ConfigMap cases.
law runtime.configmap_unused:
  {R.Runtime.configs(R.ConfigMapResource{}, LC.Laws.configs.cfg(), False{}, [], True{},
    Some{LC.Laws.configs.base_cm()}, Some{LC.Laws.configs.base_cm()}, None{}, None{})
    == S.Outcome{[], S.NoRequeue{}} : S.Outcome}

law runtime.configmap_used:
  {S.Svc.canon_outcome(R.Runtime.configs(R.ConfigMapResource{}, LC.Laws.configs.cfg(), False{}, LC.Laws.configs.cm_refs(), True{},
    Some{LC.Laws.configs.base_cm()}, Some{LC.Laws.configs.base_cm()}, None{}, None{}))
    == LC.Laws.configs.out([S.HostCreate{LC.Laws.configs.created_cm()}]) : S.Outcome}

# secrets/to_host_syncer_test.go: unused Secret.
law runtime.secret_unused:
  {R.Runtime.configs(R.SecretResource{}, LC.Laws.configs.cfg(), False{}, [], True{},
    Some{LC.Laws.configs.base_secret()}, Some{LC.Laws.configs.base_secret()}, None{}, None{})
    == S.Outcome{[], S.NoRequeue{}} : S.Outcome}


# Proposed: the enable set. chart/values.yaml (a8ab30e) enables
# sync.toHost services, configMaps and secrets, and leaves serviceAccounts
# disabled; register.go registers a syncer only when its key is enabled.
law runtime.enabled_defaults:
  {R.Runtime.enabled_ids(V.Config.defaults()) == ["services", "configmaps", "secrets"] : +List<String>}


# Proposed: the special default/kubernetes Service in the runtime
# (services/syncer.go ReconcileStart calls
# specialservices.SyncKubernetesService for default/kubernetes with the
# vcluster's own Service in the current namespace).
def Laws.runtime.kcfg() -> S.Cfg:
  S.Cfg{"demo", "vcluster-demo", "vcluster-demo"}

def Laws.runtime.svc(+name: String, +ns: String) -> J.Json:
  J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{name}}, J.KV{"namespace", J.JStr{ns}}])}])

# A virtual default/kubernetes event queues its key (the special sync
# runs on it; the key was dropped before).
law runtime.kubernetes_virtual_key:
  {R.Runtime.obj_key(R.KServices{}, False{}, Laws.runtime.kcfg(), Laws.runtime.svc("kubernetes", "default"))
    == ["services|default/kubernetes"] : List<&2, String>}

# The vcluster's own host Service (no annotations) queues
# default/kubernetes (mappings/resources/services.go: the vcluster
# Service in the current namespace maps to default/kubernetes).
law runtime.kubernetes_host_key:
  {R.Runtime.obj_key(R.KServices{}, True{}, Laws.runtime.kcfg(), Laws.runtime.svc("demo", "vcluster-demo"))
    == ["services|default/kubernetes"] : List<&2, String>}

# The host key of default/kubernetes is the vcluster's Service.
law runtime.kubernetes_host_ref:
  {R.Runtime.host_ref(R.KServices{}, Laws.runtime.kcfg(), "default", "kubernetes")
    == ("vcluster-demo", "demo") : String & String}

# services/syncer_test.go "Sync kubernetes service with recreation",
# through the runtime step.
law runtime.kubernetes_step_recreate:
  {S.Svc.canon_outcome(R.Runtime.step(R.KServices{}, LS.Laws.services.cfg(), [], False{}, None{},
    Some{LS.Laws.services.kubernetes()}, None{}, Some{LS.Laws.services.kubernetes_ip()}))
    == LS.Laws.services.out([S.VirtualDelete{"default", "kubernetes"}, S.VirtualCreate{LS.Laws.services.kubernetes_ip()}]) : S.Outcome}

# services/syncer_test.go "Sync not existent physical kubernetes service",
# through the runtime step.
law runtime.kubernetes_step_no_host:
  {R.Runtime.step(R.KServices{}, LS.Laws.services.cfg(), [], False{}, None{},
    Some{LS.Laws.services.kubernetes()}, None{}, None{})
    == S.Outcome{[], S.NoRequeue{}} : S.Outcome}

law runtime.kubernetes_special:
  {R.Runtime.special(R.KServices{}, "default", "kubernetes") == True{} : Bool}

law runtime.kubernetes_not_special_config:
  for ns: String
  for name: String
  {R.Runtime.special(R.KConfigs{R.ConfigMapResource{}}, ns, name) == False{} : Bool}

# The special sync's log outcome.
law runtime.special_recreated:
  {R.Runtime.special_outcome(True{}, True{}, [S.VirtualDelete{"default", "kubernetes"}, S.VirtualCreate{J.JNull{}}])
    == "recreated" : String}

law runtime.special_updated:
  {R.Runtime.special_outcome(True{}, True{}, [S.VirtualUpdate{J.JNull{}}]) == "updated" : String}

law runtime.special_unchanged:
  {R.Runtime.special_outcome(True{}, True{}, []) == "unchanged" : String}

law runtime.special_no_host:
  for v: Bool
  for ws: List<&2, S.Write>
  {R.Runtime.special_outcome(False{}, v, ws) == "no host service" : String}

law runtime.special_no_virtual:
  for ws: List<&2, S.Write>
  {R.Runtime.special_outcome(True{}, False{}, ws) == "no virtual service" : String}

# Proposed: while the host Service has no cluster IP and the virtual one
# has an IP (ExternalName to ClusterIP, the virtual side first: vk8s has no
# proxy), the host is updated instead of the virtual one being recreated.
def Laws.runtime.xsvc(t: String, ip: String) -> J.Json:
  J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"s"}}, J.KV{"namespace", J.JStr{"test"}}])},
    J.KV{"spec", J.Json.obj([J.KV{"type", J.JStr{t}}, J.KV{"clusterIP", J.JStr{ip}}])}])

law runtime.svc_sync_host_first:
  {R.Runtime.svc_sync(S.Cfg{"suffix", "test", "vcluster"}, Laws.runtime.xsvc("ExternalName", ""), Laws.runtime.xsvc("ExternalName", ""),
      Laws.runtime.xsvc("ClusterIP", "10.96.7.7"), Laws.runtime.xsvc("ClusterIP", "10.96.7.7"))
    == S.Svc.sync.update(S.Cfg{"suffix", "test", "vcluster"}, Laws.runtime.xsvc("ExternalName", ""), Laws.runtime.xsvc("ExternalName", ""),
      Laws.runtime.xsvc("ClusterIP", "10.96.7.7"), Laws.runtime.xsvc("ClusterIP", "10.96.7.7")) : S.Outcome}

law runtime.svc_sync_both_ips:
  {R.Runtime.svc_sync(S.Cfg{"suffix", "test", "vcluster"}, Laws.runtime.xsvc("ClusterIP", "10.96.8.8"), Laws.runtime.xsvc("ClusterIP", "10.96.8.8"),
      Laws.runtime.xsvc("ClusterIP", "10.96.7.7"), Laws.runtime.xsvc("ClusterIP", "10.96.7.7"))
    == S.Svc.sync(S.Cfg{"suffix", "test", "vcluster"}, Laws.runtime.xsvc("ClusterIP", "10.96.8.8"), Laws.runtime.xsvc("ClusterIP", "10.96.8.8"),
      Laws.runtime.xsvc("ClusterIP", "10.96.7.7"), Laws.runtime.xsvc("ClusterIP", "10.96.7.7")) : S.Outcome}

