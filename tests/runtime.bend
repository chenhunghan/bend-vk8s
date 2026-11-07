import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/sync/runtime.bend as R
import ../src/translate/services.bend as S

# Expected names and defaults: vcluster a8ab30e chart/values.yaml,
# pkg/controllers/resources/register.go and pkg/util/translate.
# Ordering and Lease location are the vk8s architecture contract.
def T.check(+name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name)

def main() -> IO(Unit):
  do IO<Unit>:
    T.check("known host deletion deletes virtual service",
      R.Runtime.same_writes(R.Runtime.writes(R.Runtime.services(
        S.Cfg{"suffix", "test", "vcluster"}, False{}, True{}, None{},
        Some{J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"s"}}, J.KV{"namespace", J.JStr{"ns"}}, J.KV{"resourceVersion", J.JStr{"2"}}])}])},
        Some{J.JNull{}}, None{})), [S.VirtualDelete{"ns", "s"}]))
    T.check("classic default syncers", String.eq(String.join(R.Runtime.defaults(), ","),
      "services,endpoints,endpointslices,configmaps,secrets,pods,fake-nodes,events,persistentvolumeclaims,fake-persistentvolumes"))
    T.check("single namespace host name", String.eq(R.Runtime.host_name("suffix", "testns", "testservice"), "testservice-x-testns-x-suffix"))
    T.check("host selector", String.eq(R.Runtime.selector("suffix"), "vcluster.loft.sh/managed-by=suffix"))
    T.check("Lease name", String.eq(R.Runtime.lease_name("suffix"), "vcluster-syncer-suffix"))
    T.check("no requeue", U32.is_eq(R.Runtime.delay(S.NoRequeue{}), 0))
    T.check("seconds to milliseconds", U32.is_eq(R.Runtime.delay(S.RequeueAfter{1}), 1000))
    T.check("delay does not wrap", U32.is_eq(R.Runtime.delay(S.RequeueAfter{4294968}), 4294967295))
    T.check("host writes before virtual; replacement deletes first",
      R.Runtime.same_writes(R.Runtime.order([
        S.VirtualCreate{J.JNull{}}, S.HostCreate{J.JNull{}},
        S.VirtualDelete{"testns", "testservice"}, S.HostDelete{"test", "testservice-x-testns-x-suffix"}]),
        [S.HostDelete{"test", "testservice-x-testns-x-suffix"}, S.HostCreate{J.JNull{}},
         S.VirtualDelete{"testns", "testservice"}, S.VirtualCreate{J.JNull{}}]))
