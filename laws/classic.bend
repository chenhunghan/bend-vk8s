import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/sync/classic.bend as K
import ../src/translate/services.bend as S
import ../src/translate/pods.bend as P
import ../src/guest/plan.bend as PL
import ../src/guest/coredns.bend as CD
import ../src/config/vcluster.bend as V
import ./coredns.bend as LCD

# Proposed: the rest of classic mode on the syncer runtime (pods, fake
# nodes, events, claims, fake volumes, CoreDNS). Expected values come from
# vcluster a8ab30e: chart/values.yaml, pkg/controllers/resources/
# register.go, pods/syncer.go and translate.go, nodes/fake_syncer.go,
# pkg/constants (KubeletPort, coredns.go) and pkg/coredns/template_test.go.
# Write order and the fake kubelet's LAN address are the architect's vk8s
# contract.

# chart/values.yaml: sync.toHost pods and persistentVolumeClaims and
# sync.fromHost.events are enabled; sync.fromHost.nodes and
# sync.toHost.persistentVolumes are not, so nodes.New and
# persistentvolumes.New (register.go, always registered) pick the fake
# syncers.
law classic.enabled_defaults:
  {K.Classic.enabled_ids(V.Config.defaults()) == ["services", "configmaps", "secrets", "pods", "nodes", "events",
    "persistentvolumeclaims", "persistentvolumes"] : +List<String>}

# sync.fromHost.nodes.enabled selects the real node syncer, which vk8s
# does not have: no fake nodes.
law classic.real_nodes_off:
  {K.Classic.on(J.Json.obj([J.KV{"sync", J.Json.obj([J.KV{"fromHost", J.Json.obj([J.KV{"nodes", J.Json.obj([
    J.KV{"enabled", J.JBool{True{}}}])}])}])}]), "nodes") == False{} : Bool}

# pods/translate.go findKubernetesDNSIP: VirtualToHostName(kube-dns,
# kube-system) in single-namespace mode (SafeConcatName(name, "x", ns,
# "x", suffix)).
law classic.dns_host_name:
  {K.Classic.dns_host_name("suffix") == "kube-dns-x-kube-system-x-suffix" : String}

# constants.KubeletPort: the fake nodes' kubelet endpoint and the fake
# kubelet's port.
law classic.kubelet_port:
  {K.Classic.kubelet_port() == 10250 : U32}

# vk8s: the fake kubelet runs in the guest, at the control plane's LAN
# address.
law classic.kubelet_ip:
  {K.KFlags.ip(K.Classic.kflags([])) == "10.10.0.2" : String}

law classic.kubelet_ip_flag:
  {K.KFlags.ip(K.Classic.kflags(["--kubelet-ip", "10.1.2.3"])) == "10.1.2.3" : String}

# Watch sources: the virtual pods stay at runtime.bend's index 8 (two per
# wired kind), and every source has a store.
law classic.vpods_source:
  {K.Classic.source(K.Classic.vpods()) == Some{K.Source{"pods", False{}, False{}}} : Maybe<&2, K.Source>}

law classic.hpods_source:
  {K.Classic.source(K.Classic.hpods()) == Some{K.Source{"pods", True{}, True{}}} : Maybe<&2, K.Source>}

law classic.vnodes_source:
  {K.Classic.source(K.Classic.vnodes()) == Some{K.Source{"nodes", False{}, False{}}} : Maybe<&2, K.Source>}

law classic.vpvcs_source:
  {K.Classic.source(K.Classic.vpvcs()) == Some{K.Source{"persistentvolumeclaims", False{}, False{}}} : Maybe<&2, K.Source>}

law classic.host_events_unlabeled:
  {K.Classic.source(11n) == Some{K.Source{"events", True{}, False{}}} : Maybe<&2, K.Source>}

law classic.sources_end:
  {K.Classic.source(15n) == None{} : Maybe<&2, K.Source>}

# Queue keys. A virtual pod queues itself and the node it runs on (nodes
# modifyController); its host pod queues the virtual key its annotations
# name, and the node.
def Laws.classic.cfg() -> S.Cfg:
  S.Cfg{"demo", "vcluster-demo", "vcluster-demo"}

def Laws.classic.vpod() -> J.Json:
  J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"nginx"}}, J.KV{"namespace", J.JStr{"default"}}])},
    J.KV{"spec", J.Json.obj([J.KV{"nodeName", J.JStr{"n1"}}])}])

def Laws.classic.hpod() -> J.Json:
  J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"nginx-x-default-x-demo"}}, J.KV{"namespace", J.JStr{"vcluster-demo"}},
    J.KV{"annotations", J.Json.obj([J.KV{"vcluster.loft.sh/object-name", J.JStr{"nginx"}},
      J.KV{"vcluster.loft.sh/object-namespace", J.JStr{"default"}}])}])},
    J.KV{"spec", J.Json.obj([J.KV{"nodeName", J.JStr{"n1"}}])}])

law classic.vpod_keys:
  {K.Classic.src_keys(K.Classic.vpods(), Laws.classic.cfg(), Laws.classic.vpod()) == ["pods|default/nginx", "nodes|/n1"] : List<&2, String>}

law classic.hpod_keys:
  {K.Classic.src_keys(K.Classic.hpods(), Laws.classic.cfg(), Laws.classic.hpod()) == ["pods|default/nginx", "nodes|/n1"] : List<&2, String>}

# A pod without a node needs none.
law classic.unscheduled_pod_keys:
  {K.Classic.src_keys(K.Classic.vpods(), Laws.classic.cfg(),
    J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"nginx"}}, J.KV{"namespace", J.JStr{"default"}}])}]))
    == ["pods|default/nginx"] : List<&2, String>}

law classic.event_keys:
  {K.Classic.src_keys(11n, Laws.classic.cfg(),
    J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"e1"}}, J.KV{"namespace", J.JStr{"vcluster-demo"}}])}]))
    == ["events|vcluster-demo/e1"] : List<&2, String>}

# A claim queues the fake volume it names (persistentvolumes fake syncer).
law classic.pvc_keys:
  {K.Classic.src_keys(K.Classic.vpvcs(), Laws.classic.cfg(),
    J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"c"}}, J.KV{"namespace", J.JStr{"default"}}])},
      J.KV{"spec", J.Json.obj([J.KV{"volumeName", J.JStr{"pv1"}}])}]))
    == ["persistentvolumeclaims|default/c", "persistentvolumes|/pv1"] : List<&2, String>}

# Call order: runtime.bend's, over calls (architect's contract).
law classic.empty_order:
  {K.Classic.order([]) == [] : List<&2, K.Op>}

law classic.host_before_virtual:
  for r: String
  for v: J.Json
  for h: J.Json
  {K.Classic.order([K.OUpdate{False{}, r, v}, K.OUpdate{True{}, r, h}])
    == [K.OUpdate{True{}, r, h}, K.OUpdate{False{}, r, v}] : List<&2, K.Op>}

law classic.host_delete_first:
  for r: String
  for ns: String
  for n: String
  for g: J.Json
  for u: String
  for h: J.Json
  {K.Classic.order([K.OCreate{True{}, r, h}, K.ODelete{True{}, r, ns, n, g, u}])
    == [K.ODelete{True{}, r, ns, n, g, u}, K.OCreate{True{}, r, h}] : List<&2, K.Op>}

law classic.virtual_delete_first:
  for r: String
  for ns: String
  for n: String
  for g: J.Json
  for u: String
  for v: J.Json
  {K.Classic.order([K.OSub{False{}, r, ns, n, "POST", "binding", "application/json", v}, K.ODelete{False{}, r, ns, n, g, u}])
    == [K.ODelete{False{}, r, ns, n, g, u}, K.OSub{False{}, r, ns, n, "POST", "binding", "application/json", v}] : List<&2, K.Op>}

# A create keeps its status write after it.
law classic.create_then_status:
  for r: String
  for o: J.Json
  {K.Classic.order([K.OCreate{False{}, r, o}, K.OStatus{False{}, r, o}])
    == [K.OCreate{False{}, r, o}, K.OStatus{False{}, r, o}] : List<&2, K.Op>}

# fake_syncer.go createFakeNode: Create, then Status().Patch.
law classic.fake_node_create:
  for o: J.Json
  {K.Classic.node_op(S.VirtualCreate{o}) == [K.OCreate{False{}, "nodes", o}, K.OStatus{False{}, "nodes", o}] : List<&2, K.Op>}

# fake_syncer.go FakeSync: updateIfNeeded's update is a status update.
law classic.fake_node_update:
  for o: J.Json
  {K.Classic.node_op(S.VirtualUpdate{o}) == [K.OStatus{False{}, "nodes", o}] : List<&2, K.Op>}

# pods/syncer.go assignNodeToPod: Pods(ns).Bind with a Binding named like
# the virtual pod, in its namespace, targeting the v1 Node.
law classic.bind:
  {K.Classic.pod_op("default", "nginx", "vcluster-demo", "nginx-x-default-x-demo", P.WBind{"n1"})
    == [K.OSub{False{}, "pods", "default", "nginx", "POST", "binding", "application/json",
      J.Json.obj([J.KV{"apiVersion", J.JStr{"v1"}}, J.KV{"kind", J.JStr{"Binding"}},
        J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"nginx"}}, J.KV{"namespace", J.JStr{"default"}}])},
        J.KV{"target", J.Json.obj([J.KV{"apiVersion", J.JStr{"v1"}}, J.KV{"kind", J.JStr{"Node"}}, J.KV{"name", J.JStr{"n1"}}])}])}]
    : List<&2, K.Op>}

# A host pod delete names the host pod, a virtual one the virtual pod.
law classic.pod_deletes:
  {K.Classic.pod_ops("default", "nginx", "vcluster-demo", "nginx-x-default-x-demo", [P.WDeleteHost{"30", "u1"}, P.WDeleteVirtual{"", ""}])
    == [K.ODelete{True{}, "pods", "vcluster-demo", "nginx-x-default-x-demo", J.JNum{"30"}, "u1"},
        K.ODelete{False{}, "pods", "default", "nginx", J.JNull{}, ""}] : List<&2, K.Op>}

# pods/syncer.go: a node the virtual cluster lacks requeues after 15 s;
# Requeue: true is now.
law classic.pod_requeue_after:
  {K.Classic.pod_rq([P.WEvent{"Warning", "SyncWarning", "m"}, P.WRequeue{15000}]) == S.RequeueAfter{15} : S.Requeue}

law classic.pod_requeue_now:
  {K.Classic.pod_rq([P.WBind{"n1"}, P.WRequeue{0}]) == S.RequeueNow{} : S.Requeue}

law classic.pod_no_requeue:
  {K.Classic.pod_rq([]) == S.NoRequeue{} : S.Requeue}

# translate.go findKubernetesDNSIP: "waiting for DNS service IP" is an
# error, so the pod retries.
law classic.pod_dns_error:
  {K.Classic.pod_err([P.WError{"waiting for DNS service IP"}]) == "waiting for DNS service IP" : String}

# A failed token request retries.
law classic.token_failed:
  {K.Classic.toks_ok([P.Tok{"abcdefgh", "t"}, P.Tok{"ijklmnop", ""}]) == False{} : Bool}

# CoreDNS in classic mode is vcluster's default manifest: its Service
# leaves clusterIP to the virtual API server (template_test.go "default").
law classic.coredns_service:
  {CD.Coredns.doc.service(CD.Coredns.vcluster_defaults(), CD.Coredns.classic_vars()) == LCD.coredns.fx.service() : String}

# constants/coredns.go: 1.36 pins coredns/coredns:1.14.2; without a
# default registry getManifestVariables prefixes docker.io/.
law classic.coredns_vars:
  {CD.Coredns.classic_vars() == CD.Vars{"docker.io/coredns/coredns:1.14.2", "1001", "1001", "/etc/resolv.conf"} : CD.Vars}

# Plan.classic writes the CoreDNS manifest and applies it.
def Laws.classic.applies(ss: +List<PL.Step>) -> Bool:
  match ss:
    case Nil{}:
      False{}
    case Con{PL.Run{prog, +args}, rest}:
      Bool.or(String.eq(String.join(args, " "), "--kubeconfig /var/lib/vcluster/pki/super-admin.conf apply -f /etc/vk8s/coredns.yaml"),
        Laws.classic.applies(rest))
    case Con{step, rest}:
      Laws.classic.applies(rest)

def Laws.classic.writes(ss: +List<PL.Step>) -> Bool:
  match ss:
    case Nil{}:
      False{}
    case Con{PL.Write{+path, text}, rest}:
      Bool.or(String.eq(path, "/etc/vk8s/coredns.yaml"), Laws.classic.writes(rest))
    case Con{step, rest}:
      Laws.classic.writes(rest)

law classic.plan_writes_coredns:
  {Laws.classic.writes(PL.Plan.classic(PL.Plan.default_cfg("demo", 6443, True{}), "/var/lib/vk8s-host/host-kubeconfig", "host-ns")) == True{} : Bool}

law classic.plan_applies_coredns:
  {Laws.classic.applies(PL.Plan.classic(PL.Plan.default_cfg("demo", 6443, True{}), "/var/lib/vk8s-host/host-kubeconfig", "host-ns")) == True{} : Bool}


# Proposed: the vcluster's own host Service. Its watch (by name) feeds
# the store after the source table, and an object it sees queues
# default/kubernetes (services/syncer.go ReconcileStart:
# specialservices.SyncKubernetesService).
law classic.kube_store_after_table:
  {K.Classic.source(U32.to_nat(K.Classic.kube_store())) == None{} : Maybe<&2, K.Source>}

law classic.kube_field:
  {K.Classic.kube_field("demo") == "metadata.name=demo" : String}

law classic.kube_keys:
  {K.Classic.store_keys(K.Classic.kube_store(), Laws.classic.cfg(),
    J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"demo"}}, J.KV{"namespace", J.JStr{"vcluster-demo"}},
      J.KV{"labels", J.Json.obj([J.KV{"app", J.JStr{"vcluster"}}, J.KV{"release", J.JStr{"demo"}}])}])}]))
    == ["services|default/kubernetes"] : List<&2, String>}

# The table's stores keep the table's keys.
law classic.store_keys_table:
  {K.Classic.store_keys(8, Laws.classic.cfg(), Laws.classic.vpod()) == ["pods|default/nginx", "nodes|/n1"] : List<&2, String>}

# pods/translate.go findKubernetesIP: SyncToHost fails while the
# vcluster's host Service is missing; a pod step then waits and makes no
# calls.
law classic.wait_none:
  {K.Classic.wait_reason(True{}, True{}) == "" : String}

law classic.wait_kube:
  {K.Classic.wait_reason(True{}, False{}) == "vcluster service not found" : String}

law classic.wait_tokens:
  for k: Bool
  {K.Classic.wait_reason(False{}, k) == "service account token request failed" : String}

law classic.hold_runs:
  for a: K.Act
  {K.Classic.hold("", a) == a : K.Act}

law classic.hold_waits:
  for a: K.Act
  {K.Classic.hold("vcluster service not found", a) == K.Act{[], S.NoRequeue{}, "vcluster service not found"} : K.Act}

# Proposed: fake_syncer.go createFakeNode ends by removing the taints
# (node.Spec.Taints = []corev1.Taint{}; Patch): the fake node's create is
# followed by an update of the untainted node.
law classic.fake_node_untaint:
  for o: J.Json
  {K.Classic.node_ops([S.VirtualCreate{o}])
    == [K.OCreate{False{}, "nodes", o}, K.OStatus{False{}, "nodes", o}, K.OUpdate{False{}, "nodes", o}] : List<&2, K.Op>}
