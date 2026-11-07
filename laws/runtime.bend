import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/sync/runtime.bend as R
import ../src/translate/services.bend as S

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
  {R.Runtime.lease_name("suffix") == "vcluster-syncer-suffix" : String}

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

import ../src/guest/plan.bend as P

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
    == P.Daemon{"syncer", "/sbin/vk8s-init", ["syncer", "--host-kubeconfig", "/var/lib/vk8s-host/host-kubeconfig",
      "--host-namespace", "host-ns", "--name", "demo", "--service-cidr", "10.96.0.0/12"]} : P.Step}

import ../src/sync/core.bend as C

# Proposed: services/syncer.go Options sets DisableUIDDeletion=true.
# Service replacement must retain its host allocation despite a new UID.
law runtime.service_options:
  {R.Runtime.service_cfg(S.Cfg{"suffix", "test", "vcluster"})
    == C.Cfg{"suffix", "test", "/v1, Kind=Service", "service", True{}, False{}, False{}} : C.Cfg}


import ./configs.bend as LC

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
