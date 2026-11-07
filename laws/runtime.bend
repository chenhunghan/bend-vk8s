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
