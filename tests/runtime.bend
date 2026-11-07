import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/sync/runtime.bend as R
import ../src/translate/services.bend as S
import ../src/config/vcluster.bend as V

# Expected names and defaults: vcluster a8ab30e chart/values.yaml,
# pkg/controllers/resources/register.go and pkg/util/translate.
# Ordering and Lease location are the vk8s architecture contract.
def T.check(+name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name)

# mappings/resources/configmaps.go: the kube-root-ca.crt rename checks the
# translated host name, so in single-namespace mode it never fires and a
# virtual kube-root-ca.crt syncs under its plain host name
# (src/translate/configs.bend, quirk kept as vcluster has it).
def T.ref_name(r: String & String) -> String:
  match r:
    case (ns, name):
      name

def T.key_is(m: Maybe<&2, R.SyncKey>, +id: String, +ns: String, +name: String) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{R.SyncKey{a, b, c}}:
      Bool.and(String.eq(a, id), Bool.and(String.eq(b, ns), String.eq(c, name)))

def T.config(r: Result<&2, &2, String, J.Json>) -> J.Json:
  match r:
    case Done{c}:
      c
    case Fail{e}:
      J.JNull{}

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
    T.check("adapter host ref of kube-root-ca.crt", String.eq(T.ref_name(R.Runtime.host_ref(R.KConfigs{R.ConfigMapResource{}},
      S.Cfg{"suffix", "test", "test"}, "testns", "kube-root-ca.crt")), "kube-root-ca.crt-x-testns-x-suffix"))
    T.check("adapter host ref of a service", String.eq(T.ref_name(R.Runtime.host_ref(R.KServices{},
      S.Cfg{"suffix", "test", "test"}, "testns", "testservice")), "testservice-x-testns-x-suffix"))
    T.check("adapter queue key round trip", T.key_is(R.Runtime.parse_key(R.Runtime.key("secrets", "testns", "a")), "secrets", "testns", "a"))
    T.check("syncer flags", String.eq(R.Flags.host_namespace(R.Runtime.flags(["vk8s-init", "syncer", "--name", "demo"])), "vcluster-demo"))
    # chart/values.yaml: services, configMaps and secrets sync to the host
    # by default; serviceAccounts.enabled is false.
    T.check("default enabled resources", String.eq(String.join(R.Runtime.enabled_ids(T.config(V.Config.parse(""))), ","),
      "services,configmaps,secrets"))
    T.check("sync.toHost.serviceAccounts.enabled wires service accounts",
      String.eq(String.join(R.Runtime.enabled_ids(T.config(V.Config.parse("sync:\n  toHost:\n    serviceAccounts:\n      enabled: true\n"))), ","),
      "services,configmaps,secrets,serviceaccounts"))
    T.check("sync.toHost.secrets.enabled false unwires secrets",
      String.eq(String.join(R.Runtime.enabled_ids(T.config(V.Config.parse("sync:\n  toHost:\n    secrets:\n      enabled: false\n"))), ","),
      "services,configmaps"))
    # serviceaccounts/syncer_test.go: translate.Default.HostName of
    # test/test-serviceaccount.
    T.check("adapter host ref of a service account", String.eq(T.ref_name(R.Runtime.host_ref(R.KConfigs{R.ServiceAccountResource{}},
      S.Cfg{"suffix", "test", "test"}, "test", "test-serviceaccount")), "test-serviceaccount-x-test-x-suffix"))
    T.check("service accounts key", T.key_is(R.Runtime.parse_key(R.Runtime.key("serviceaccounts", "test", "a")), "serviceaccounts", "test", "a"))
    T.check("syncer flags config", String.eq(R.Flags.config(R.Runtime.flags(["vk8s-guest", "syncer", "--config", "/etc/vk8s/vcluster.yaml"])), "/etc/vk8s/vcluster.yaml"))
    T.check("syncer flags config default", String.eq(R.Flags.config(R.Runtime.flags(["vk8s-guest", "syncer"])), ""))
