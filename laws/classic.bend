import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/sync/classic.bend as K
import ../src/translate/services.bend as S
import ../src/translate/pods.bend as P
import ../src/guest/plan.bend as PL
import ../src/guest/coredns.bend as CD
import ../src/config/vcluster.bend as V
import ./coredns.bend as LCD
import ../src/translate/nodes.bend as ND
import ../src/translate/storage.bend as SG
import ../src/sync/runtime.bend as RT

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

# Proposed: pods/syncer.go SyncToHost deletes a virtual pod that has a
# DeletionTimestamp or a Status.StartTime (and no host pod) before it
# translates it, so such a step requests no token.
law classic.pod_deletes_terminating:
  {K.Classic.pod_deletes(J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"p"}},
    J.KV{"deletionTimestamp", J.JStr{"2026-11-09T19:53:11Z"}}])}])) == True{} : Bool}
law classic.pod_deletes_started:
  {K.Classic.pod_deletes(J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"p"}}])},
    J.KV{"status", J.Json.obj([J.KV{"startTime", J.JStr{"2026-11-09T19:51:16Z"}}])}])) == True{} : Bool}
law classic.pod_deletes_new:
  {K.Classic.pod_deletes(J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"p"}}])},
    J.KV{"status", J.Json.obj([J.KV{"phase", J.JStr{"Pending"}}])}])) == False{} : Bool}

# Proposed: vcluster's conformance profile in the classic syncer
# (test/conformanceValues.yaml at a8ab30e): the virtual scheduler, real
# nodes with selector.all, proxyKubelets off, and persistentVolumes,
# priorityClasses and storageClasses synced to the host. Expected values
# come from pkg/controllers/resources/register.go, nodes/syncer.go,
# pods/scheduling/config.go, persistentvolumes (mappings/resources/
# persistentvolumes.go, syncer.go), pkg/util/translate/single_namespace.go
# and pkg/config/validation.go. The second source table (Classic.src from
# 15 on) and the API calls are the architect's vk8s contract.

def Laws.classic.conf_yaml() -> String:
  "controlPlane:\n  advanced:\n    virtualScheduler:\n      enabled: true\nnetworking:\n  advanced:\n    proxyKubelets:\n      byHostname: false\n      byIP: false\nsync:\n  fromHost:\n    csiDrivers:\n      enabled: false\n    csiStorageCapacities:\n      enabled: false\n    nodes:\n      enabled: true\n      selector:\n        all: true\n  toHost:\n    persistentVolumes:\n      enabled: true\n    priorityClasses:\n      enabled: true\n    storageClasses:\n      enabled: true\n"

def Laws.classic.conf() -> J.Json:
  V.Config.value(Laws.classic.conf_yaml(), [])

# register.go getSyncers with the profile: storageclasses.New,
# priorityclasses.New and csinodes.New (CSINodes "auto" turns "true" with
# the virtual scheduler and claims, validation.go:64-77) run beside the
# defaults; nodes.New and persistentvolumes.New pick the real syncers, which
# serve the nodes and persistentvolumes keys.
#
# The BendTT kernel runs out of fuel on the id list of the whole parsed
# profile; tests/classic_plan.bend checks that list. This law states it on
# the profile's sync flags as the parsed profile holds them (chart
# defaults for the keys it leaves out, csiNodes "auto" resolved to
# "true"), and the classic.conformance_on_* laws read each id's flags from
# the parsed profile.
def Laws.classic.flag(k: String, on: J.Json) -> J.KV:
  J.KV{k, J.Json.obj([J.KV{"enabled", on}])}

def Laws.classic.to_host() -> J.Json:
  J.Json.obj([Laws.classic.flag("services", J.JBool{True{}}),
    Laws.classic.flag("configMaps", J.JBool{True{}}), Laws.classic.flag("secrets", J.JBool{True{}}),
    Laws.classic.flag("serviceAccounts", J.JBool{False{}}), Laws.classic.flag("pods", J.JBool{True{}}),
    Laws.classic.flag("persistentVolumeClaims", J.JBool{True{}}), Laws.classic.flag("persistentVolumes", J.JBool{True{}}),
    Laws.classic.flag("storageClasses", J.JBool{True{}}), Laws.classic.flag("priorityClasses", J.JBool{True{}})])

def Laws.classic.from_host() -> J.Json:
  J.Json.obj([Laws.classic.flag("events", J.JBool{True{}}),
    Laws.classic.flag("nodes", J.JBool{True{}}), Laws.classic.flag("csiNodes", J.JStr{"true"})])

def Laws.classic.conf_sync() -> J.Json:
  J.Json.obj([J.KV{"sync", J.Json.obj([J.KV{"toHost", Laws.classic.to_host()}, J.KV{"fromHost", Laws.classic.from_host()}])}])

law classic.conformance_ids:
  {K.Classic.enabled_ids(Laws.classic.conf_sync()) == ["services", "configmaps", "secrets", "pods", "nodes", "events",
    "persistentvolumeclaims", "persistentvolumes", "storageclasses", "priorityclasses", "csinodes"] : +List<String>}

# Each id of this module on the parsed profile: its keys reconcile.
law classic.conformance_on_pods:
  {K.Classic.key_on(Laws.classic.conf(), "pods") == True{} : Bool}

law classic.conformance_on_nodes:
  {K.Classic.key_on(Laws.classic.conf(), "nodes") == True{} : Bool}

law classic.conformance_on_events:
  {K.Classic.key_on(Laws.classic.conf(), "events") == True{} : Bool}

law classic.conformance_on_pvcs:
  {K.Classic.key_on(Laws.classic.conf(), "persistentvolumeclaims") == True{} : Bool}

law classic.conformance_on_pvs:
  {K.Classic.key_on(Laws.classic.conf(), "persistentvolumes") == True{} : Bool}

law classic.conformance_on_storageclasses:
  {K.Classic.key_on(Laws.classic.conf(), "storageclasses") == True{} : Bool}

law classic.conformance_on_priorityclasses:
  {K.Classic.key_on(Laws.classic.conf(), "priorityclasses") == True{} : Bool}

law classic.conformance_on_csinodes:
  {K.Classic.key_on(Laws.classic.conf(), "csinodes") == True{} : Bool}

law classic.real_nodes_on:
  {K.Classic.real_nodes(Laws.classic.conf()) == True{} : Bool}

law classic.real_pvs_on:
  {K.Classic.real_pvs(Laws.classic.conf()) == True{} : Bool}

law classic.real_nodes_default:
  {K.Classic.real_nodes(V.Config.defaults()) == False{} : Bool}

# nodes/syncer.go NewSyncer: selector.all, the virtual scheduler
# (enableScheduler), proxyKubelets byHostname and byIP off.
law classic.node_selector_all:
  {ND.Node.selector(K.Classic.node_opts(Laws.classic.conf())) == ND.SelAll{} : ND.Selector}

law classic.node_scheduler:
  {ND.Node.scheduler(K.Classic.node_opts(Laws.classic.conf())) == True{} : Bool}

law classic.node_by_hostname:
  {ND.Node.by_hostname(K.Classic.node_opts(Laws.classic.conf())) == False{} : Bool}

law classic.node_by_ip:
  {ND.Node.by_ip(K.Classic.node_opts(Laws.classic.conf())) == False{} : Bool}

# chart/values.yaml: no selector, no scheduler, clearImageStatus false,
# both proxies on, no enforced tolerations, NODE_NAME unset.
law classic.node_defaults:
  {K.Classic.node_opts(V.Config.defaults()) == ND.Opts{ND.SelLabels{[]}, False{}, False{}, True{}, True{}, [], "", False{}} : ND.Opts}

# pods/scheduling/config.go IsSchedulerFromVirtualCluster is the virtual
# scheduler flag (pods/syncer.go:245-250, translate.go:424-427); the pod
# translator renames priority classes when they sync to the host.
law classic.pod_virtual_scheduler:
  {P.Pods.cfg.virtual_scheduler(K.Classic.pod_cfg(Laws.classic.cfg(), Laws.classic.conf())) == True{} : Bool}

law classic.pod_host_scheduler:
  {P.Pods.cfg.virtual_scheduler(K.Classic.pod_cfg(Laws.classic.cfg(), V.Config.defaults())) == False{} : Bool}

law classic.pod_priority_classes:
  {P.Pods.cfg.pc_to_host(K.Classic.pod_cfg(Laws.classic.cfg(), Laws.classic.conf())) == True{} : Bool}

# The second source table: host nodes, storage and priority classes both
# ways, host volumes, CSINodes both ways. Host watches of cluster-scoped
# kinds carry no label filter (vcluster's marker is the cluster marker).
law classic.hnodes_source:
  {K.Classic.src(15n) == Some{K.Source{"nodes", True{}, False{}}} : Maybe<&2, K.Source>}

law classic.hpvs_source:
  {K.Classic.src(20n) == Some{K.Source{"persistentvolumes", True{}, False{}}} : Maybe<&2, K.Source>}

law classic.first_sources_kept:
  {K.Classic.src(10n) == K.Classic.source(10n) : Maybe<&2, K.Source>}

law classic.all_sources_end:
  {K.Classic.src(23n) == None{} : Maybe<&2, K.Source>}

# A host node queues its own name (the nodes mapper is a mirror mapper).
law classic.hnode_keys:
  {K.Classic.src_keys(15n, Laws.classic.cfg(), J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"n1"}}])}]))
    == ["nodes|/n1"] : List<&2, String>}

# A host storage class queues the virtual class its annotations name.
law classic.hsc_keys:
  {K.Classic.src_keys(17n, Laws.classic.cfg(), J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"vcluster-fast-x-vcluster-demo-x-demo"}},
    J.KV{"annotations", J.Json.obj([J.KV{"vcluster.loft.sh/object-name", J.JStr{"fast"}}])}])}]))
    == ["storageclasses|/fast"] : List<&2, String>}

law classic.vsc_keys:
  {K.Classic.src_keys(16n, Laws.classic.cfg(), J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"fast"}}])}]))
    == ["storageclasses|/fast"] : List<&2, String>}

# An unmanaged host class queues nothing.
law classic.hsc_unmanaged_keys:
  {K.Classic.src_keys(17n, Laws.classic.cfg(), J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"standard"}}])}]))
    == [] : List<&2, String>}

law classic.hpc_keys:
  {K.Classic.src_keys(19n, Laws.classic.cfg(), J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"vcluster-high-x-vcluster-demo-x-demo"}},
    J.KV{"annotations", J.Json.obj([J.KV{"vcluster.loft.sh/object-name", J.JStr{"high"}}])}])}]))
    == ["priorityclasses|/high"] : List<&2, String>}

# persistentVolumeMapper.HostToVirtual: the mapped name, else the host
# name (a volume the host provisioned for a synced claim).
law classic.hpv_keys_provisioned:
  {K.Classic.src_keys(20n, Laws.classic.cfg(), J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"pvc-1234"}}])}]))
    == ["persistentvolumes|/pvc-1234"] : List<&2, String>}

law classic.hpv_keys_synced:
  {K.Classic.src_keys(20n, Laws.classic.cfg(), J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"vcluster-pv1-x-vcluster-demo-x-demo"}},
    J.KV{"annotations", J.Json.obj([J.KV{"vcluster.loft.sh/object-name", J.JStr{"pv1"}}])}])}]))
    == ["persistentvolumes|/pv1"] : List<&2, String>}

law classic.csinode_keys:
  {K.Classic.src_keys(22n, Laws.classic.cfg(), J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"n1"}}])}]))
    == ["csinodes|/n1"] : List<&2, String>}

# single_namespace.go HostNameCluster: SafeConcatName("vcluster", name,
# "x", target namespace, "x", vcluster name).
law classic.cluster_host_name:
  {K.Classic.cluster_host_name(Laws.classic.cfg(), "fast") == "vcluster-fast-x-vcluster-demo-x-demo" : String}

# mappings/resources/persistentvolumes.go VirtualToHost: no virtual
# volume keeps the name; a virtual volume maps through HostNameCluster,
# or names its host volume in vcluster.loft.sh/host-pv.
law classic.pv_host_name_none:
  {K.Classic.pv_host_name(Laws.classic.cfg(), "pvc-1234", None{}) == "pvc-1234" : String}

law classic.pv_host_name_virtual:
  {K.Classic.pv_host_name(Laws.classic.cfg(), "pv1", Some{J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"pv1"}}])}])})
    == "vcluster-pv1-x-vcluster-demo-x-demo" : String}

law classic.pv_host_name_host_pv:
  {K.Classic.pv_host_name(Laws.classic.cfg(), "pvc-1234", Some{J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"pvc-1234"}},
    J.KV{"annotations", J.Json.obj([J.KV{"vcluster.loft.sh/host-pv", J.JStr{"pvc-1234"}}])}])}])})
    == "pvc-1234" : String}

# The virtual claim of a host volume: its claim ref names the host claim
# of a virtual claim (SafeConcatName(name, "x", namespace, "x", vc)).
def Laws.classic.vpvc() -> J.Json:
  J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"data"}}, J.KV{"namespace", J.JStr{"default"}}])}])

def Laws.classic.hpv(ns: String, name: String) -> J.Json:
  J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"pvc-1234"}}])},
    J.KV{"spec", J.Json.obj([J.KV{"claimRef", J.Json.obj([J.KV{"name", J.JStr{name}}, J.KV{"namespace", J.JStr{ns}}])}])}])

law classic.pv_claim_found:
  {K.Classic.pv_claim(Laws.classic.cfg(), Some{Laws.classic.hpv("vcluster-demo", "data-x-default-x-demo")}, [Laws.classic.vpvc()])
    == SG.Found{Laws.classic.vpvc()} : SG.Claim}

law classic.pv_claim_missing:
  {K.Classic.pv_claim(Laws.classic.cfg(), Some{Laws.classic.hpv("vcluster-demo", "gone-x-default-x-demo")}, [Laws.classic.vpvc()])
    == SG.Missing{} : SG.Claim}

law classic.pv_claim_unmapped:
  {K.Classic.pv_claim(Laws.classic.cfg(), Some{Laws.classic.hpv("other", "data")}, [Laws.classic.vpvc()])
    == SG.Unmapped{} : SG.Claim}

# nodes/syncer.go Sync: patcher.Patch writes the node, then its status;
# SyncToVirtual creates the node and requeues.
law classic.real_node_update:
  for o: J.Json
  {K.Classic.rnode_op(S.VirtualUpdate{o}) == [K.OUpdate{False{}, "nodes", o}, K.OStatus{False{}, "nodes", o}] : List<&2, K.Op>}

law classic.real_node_create:
  for o: J.Json
  {K.Classic.rnode_op(S.VirtualCreate{o}) == [K.OCreate{False{}, "nodes", o}] : List<&2, K.Op>}

# A cluster-scoped kind's writes name its own resource.
law classic.cluster_host_create:
  for o: J.Json
  {K.Classic.cst_op("storageclasses", SG.HostCreate{o}) == [K.OCreate{True{}, "storageclasses", o}] : List<&2, K.Op>}

law classic.cluster_host_delete:
  for n: String
  {K.Classic.cst_op("priorityclasses", SG.HostDelete{"", n, SG.Del{J.JNull{}, J.JNull{}}})
    == [K.ODelete{True{}, "priorityclasses", "", n, J.JNull{}, ""}] : List<&2, K.Op>}

# Proposed: with proxyKubelets off, real nodes keep the host's addresses
# and get the vcluster Service's IP as their first address, InternalDNS
# (vk8s design: the VM cannot reach host kubelets with its credentials).
law classic.kaddr_op_node:
  {K.Classic.kaddr_op("10.96.0.9", K.OStatus{False{}, "nodes", J.Json.obj([J.KV{"status", J.Json.obj([J.KV{"addresses", J.Json.arr([
    J.Json.obj([J.KV{"type", J.JStr{"InternalIP"}}, J.KV{"address", J.JStr{"10.10.0.3"}}])])}])}])})
    == K.OStatus{False{}, "nodes", J.Json.obj([J.KV{"status", J.Json.obj([J.KV{"addresses", J.Json.arr([
      J.Json.obj([J.KV{"type", J.JStr{"InternalDNS"}}, J.KV{"address", J.JStr{"10.96.0.9"}}]),
      J.Json.obj([J.KV{"type", J.JStr{"InternalIP"}}, J.KV{"address", J.JStr{"10.10.0.3"}}])])}])}])} : K.Op}
law classic.kaddr_op_host:
  for o: J.Json
  {K.Classic.kaddr_op("10.96.0.9", K.OCreate{True{}, "nodes", o}) == K.OCreate{True{}, "nodes", o} : K.Op}
law classic.kaddr_op_pods:
  for o: J.Json
  {K.Classic.kaddr_op("10.96.0.9", K.OUpdate{False{}, "pods", o}) == K.OUpdate{False{}, "pods", o} : K.Op}

# Proposed: a host Service asks for the virtual Service's cluster IP and
# ports (vk8s's way to vcluster's createService end state, without its
# proxy; the translated Service is the fallback).
law classic.is_services:
  {K.Classic.is_services(RT.KServices{}) == True{} : Bool}
law classic.is_services_configs:
  for r: RT.ConfigResource
  {K.Classic.is_services(RT.KConfigs{r}) == False{} : Bool}
law classic.svc_vref:
  {K.Classic.svc_vname(J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"annotations", J.Json.obj([
    J.KV{"vcluster.loft.sh/object-name", J.JStr{"web"}}, J.KV{"vcluster.loft.sh/object-namespace", J.JStr{"default"}}])}])}]))
    == "web" : String}
law classic.svc_prefer:
  {K.Classic.svc_prefer(
    J.Json.obj([J.KV{"spec", J.Json.obj([J.KV{"type", J.JStr{"NodePort"}}, J.KV{"ports", J.Json.arr([J.Json.obj([J.KV{"port", J.JNum{"80"}}])])}])}]),
    J.Json.obj([J.KV{"spec", J.Json.obj([J.KV{"clusterIP", J.JStr{"10.96.7.7"}}, J.KV{"clusterIPs", J.Json.arr([J.JStr{"10.96.7.7"}])},
      J.KV{"ports", J.Json.arr([J.Json.obj([J.KV{"port", J.JNum{"80"}}, J.KV{"nodePort", J.JNum{"30080"}}])])}])}]))
    == J.Json.obj([J.KV{"spec", J.Json.obj([J.KV{"type", J.JStr{"NodePort"}},
      J.KV{"ports", J.Json.arr([J.Json.obj([J.KV{"port", J.JNum{"80"}}, J.KV{"nodePort", J.JNum{"30080"}}])])},
      J.KV{"clusterIP", J.JStr{"10.96.7.7"}}, J.KV{"clusterIPs", J.Json.arr([J.JStr{"10.96.7.7"}])}])}]) : J.Json}

# Proposed: the virtual pod is observed up to its generation less the host
# pod's lag (vk8s: the two API servers bump generations on different
# changes; e2e pod_resize waits for observedGeneration to reach the
# virtual generation).
def Laws.classic.gpod(g: String, o: String) -> J.Json:
  J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"generation", J.JNum{g}}])}, J.KV{"status", J.Json.obj([J.KV{"observedGeneration", J.JNum{o}}])}])

law classic.obs_target_equivalent_resize:
  {K.Classic.obs_target(Some{Laws.classic.gpod("2", "1")}, Some{Laws.classic.gpod("1", "1")}) == 2 : U32}
law classic.obs_target_host_lagging:
  {K.Classic.obs_target(Some{Laws.classic.gpod("3", "2")}, Some{Laws.classic.gpod("3", "2")}) == 2 : U32}
law classic.obs_target_no_host:
  {K.Classic.obs_target(Some{Laws.classic.gpod("2", "1")}, None{}) == 0 : U32}
law classic.gen_op_host:
  for o: J.Json
  {K.Classic.gen_op(J.JNum{"2"}, K.OStatus{True{}, "pods", o}) == K.OStatus{True{}, "pods", o} : K.Op}
law classic.gen_op_virtual:
  {K.Classic.gen_op(J.JNum{"2"}, K.OStatus{False{}, "pods", J.Json.obj([J.KV{"status", J.Json.obj([J.KV{"observedGeneration", J.JNum{"1"}}])}])})
    == K.OStatus{False{}, "pods", J.Json.obj([J.KV{"status", J.Json.obj([J.KV{"observedGeneration", J.JNum{"2"}}])}])} : K.Op}
law classic.svc_wants_ip_external_to_cluster:
  {K.Classic.svc_wants_ip(J.Json.obj([J.KV{"spec", J.Json.obj([J.KV{"type", J.JStr{"ClusterIP"}}, J.KV{"clusterIP", J.JStr{""}}])}])) == True{} : Bool}
law classic.svc_wants_ip_has_ip:
  {K.Classic.svc_wants_ip(J.Json.obj([J.KV{"spec", J.Json.obj([J.KV{"type", J.JStr{"ClusterIP"}}, J.KV{"clusterIP", J.JStr{"10.96.7.7"}}])}])) == False{} : Bool}
law classic.svc_wants_ip_external:
  {K.Classic.svc_wants_ip(J.Json.obj([J.KV{"spec", J.Json.obj([J.KV{"type", J.JStr{"ExternalName"}}])}])) == False{} : Bool}


# Proposed: Endpoints and EndpointSlices to the host (vcluster a8ab30e
# pkg/controllers/resources/endpoints and endpointslices, register.go,
# chart/values.yaml). Their watches form a third table after the vcluster
# Service's store; the first two tables and Classic.enabled_ids are
# unchanged.

# chart/values.yaml: sync.toHost.endpoints and endpointSlices are enabled.
law classic.sync_ids_defaults:
  {K.Classic.sync_ids(V.Config.defaults()) == ["services", "configmaps", "secrets", "pods", "nodes", "events",
    "persistentvolumeclaims", "persistentvolumes", "endpoints", "endpointslices"] : +List<String>}

# register.go: isEnabled(ctx.Config.Sync.ToHost.EndpointSlices.Enabled, endpointslices.New).
law classic.eps_off:
  {K.Classic.eps_on(J.Json.obj([J.KV{"sync", J.Json.obj([J.KV{"toHost", J.Json.obj([J.KV{"endpointSlices", J.Json.obj([
    J.KV{"enabled", J.JBool{False{}}}])}])}])}]), "endpointslices") == False{} : Bool}

law classic.eps_any_on:
  {K.Classic.any_on(V.Config.defaults(), "endpoints") == True{} : Bool}

# The third table starts after the vcluster Service's store.
law classic.eps_base_after_kube:
  {K.Classic.eps_base() == 24 : U32}

law classic.eps_virtual_source:
  {K.Classic.eps_src(0n) == Some{K.Source{"endpoints", False{}, False{}}} : Maybe<&2, K.Source>}

law classic.eps_host_slices_source:
  {K.Classic.eps_src(3n) == Some{K.Source{"endpointslices", True{}, True{}}} : Maybe<&2, K.Source>}

law classic.eps_sources_end:
  {K.Classic.eps_src(4n) == None{} : Maybe<&2, K.Source>}

# A virtual object queues itself; a host object the virtual object its
# annotations name.
law classic.eps_virtual_keys:
  {K.Classic.watch_keys(24, Laws.classic.cfg(), Laws.classic.vpod()) == ["endpoints|default/nginx"] : List<&2, String>}

law classic.eps_host_keys:
  {K.Classic.watch_keys(27, Laws.classic.cfg(), Laws.classic.hpod()) == ["endpointslices|default/nginx"] : List<&2, String>}

# endpoints ModifyController: a virtual Service queues its Endpoints.
law classic.svc_queues_endpoints:
  {K.Classic.watch_keys(0, Laws.classic.cfg(), Laws.classic.vpod()) == ["services|default/nginx", "endpoints|default/nginx"]
    : List<&2, String>}

# The first table's keys are Classic.store_keys's.
law classic.watch_keys_table:
  {K.Classic.watch_keys(8, Laws.classic.cfg(), Laws.classic.vpod()) == ["pods|default/nginx", "nodes|/n1"] : List<&2, String>}

# The virtual Service of an EndpointSlice is its kubernetes.io/service-name
# label (endpointslices ReconcileStart).
law classic.eps_svc_name_slice:
  {K.Classic.eps_svc_name(True{}, "web-abc", Some{J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"labels", J.Json.obj([
    J.KV{"kubernetes.io/service-name", J.JStr{"web"}}])}])}])}) == "web" : String}

law classic.eps_svc_name_endpoints:
  for v: Maybe<&2, J.Json>
  {K.Classic.eps_svc_name(False{}, "web", v) == "web" : String}

# endpoints/syncer_test.go TestSync "Don't sync default/kubernetes
# endpoint": ReconcileStart skips, nothing is written.
law classic.eps_skip_kubernetes:
  {K.Classic.eps(False{}, K.Classic.eps_begin(False{}, "default", "kubernetes", None{}, None{}, None{}), Laws.classic.cfg(),
    "kubernetes-x-default-x-demo", None{}, None{}, None{}, None{}) == K.Act{[], S.NoRequeue{}, ""} : K.Act}

# endpointslices/syncer_test.go TestSync "Don't sync default/kubernetes
# endpointSlice".
law classic.slices_skip_kubernetes:
  {K.Classic.eps(True{}, K.Classic.eps_begin(True{}, "default", "kubernetes", None{}, None{}, None{}), Laws.classic.cfg(),
    "kubernetes-x-default-x-demo", None{}, None{}, None{}, None{}) == K.Act{[], S.NoRequeue{}, ""} : K.Act}

# endpoints ReconcileStart: a Service with a selector skips the sync and
# deletes the host Endpoints vcluster made (object-name annotation), so
# that Kubernetes maintains them.
def Laws.classic.selector_svc() -> J.Json:
  J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"nginx"}}, J.KV{"namespace", J.JStr{"default"}}])},
    J.KV{"spec", J.Json.obj([J.KV{"selector", J.Json.obj([J.KV{"app", J.JStr{"nginx"}}])}])}])

law classic.eps_selector_deletes_managed:
  {K.Classic.eps(False{}, K.Classic.eps_begin(False{}, "default", "nginx", Some{Laws.classic.vpod()}, Some{Laws.classic.selector_svc()},
    Some{Laws.classic.hpod()}), Laws.classic.cfg(), "nginx-x-default-x-demo", None{}, Some{Laws.classic.vpod()}, None{},
    Some{Laws.classic.hpod()})
    == K.Act{[K.ODelete{True{}, "endpoints", "vcluster-demo", "nginx-x-default-x-demo", J.JNull{}, ""}], S.NoRequeue{}, ""} : K.Act}

# endpointslices ReconcileStart: a gone virtual slice deletes the host
# slice.
law classic.slice_gone_deletes_host:
  {K.Classic.eps(True{}, K.Classic.eps_begin(True{}, "default", "nginx", None{}, None{}, Some{Laws.classic.hpod()}), Laws.classic.cfg(),
    "nginx-x-default-x-demo", None{}, None{}, None{}, Some{Laws.classic.hpod()})
    == K.Act{[K.ODelete{True{}, "endpointslices", "vcluster-demo", "nginx-x-default-x-demo", J.JNull{}, ""}], S.NoRequeue{}, ""} : K.Act}

# Without the virtual Service, ReconcileStart skips and writes nothing.
law classic.eps_no_service:
  {K.Classic.eps(False{}, K.Classic.eps_begin(False{}, "default", "nginx", Some{Laws.classic.vpod()}, None{}, None{}), Laws.classic.cfg(),
    "nginx-x-default-x-demo", None{}, Some{Laws.classic.vpod()}, None{}, None{}) == K.Act{[], S.NoRequeue{}, ""} : K.Act}

# A skipping ReconcileStart returns before getObjects: the object cache
# does not change.
law classic.eps_skip_keeps_cache:
  for ws: List<&2, S.Write>
  for e: String
  {K.Classic.eps_cache(S.Start{True{}, ws, e}) == False{} : Bool}

# A ReconcileStart that deleted the host object goes on with none.
law classic.eps_host_after_delete:
  for h: Maybe<&2, J.Json>
  {K.Classic.eps_host([S.HostDelete{"vcluster-demo", "nginx-x-default-x-demo"}], h) == None{} : Maybe<&2, J.Json>}

law classic.eps_host_untouched:
  for h: Maybe<&2, J.Json>
  {K.Classic.eps_host([], h) == h : Maybe<&2, J.Json>}

# Proposed: the host's gitVersion feeds the pod syncer's host version
# (vcluster discovers it; in-place resize needs host 1.35 or later).
law classic.parse_ver:
  {K.Classic.parse_ver("v1.36.6") == Some{P.Ver{1, 36, 6}} : Maybe<&2, P.Ver>}
law classic.parse_ver_pre:
  {K.Classic.parse_ver("v1.35.0-rc.1") == Some{P.Ver{1, 35, 0}} : Maybe<&2, P.Ver>}
law classic.parse_ver_none:
  {K.Classic.parse_ver("") == None{} : Maybe<&2, P.Ver>}
law classic.with_rv:
  {K.Classic.with_rv(J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"p"}}, J.KV{"resourceVersion", J.JStr{"5"}}])}]), J.JStr{"9"})
    == J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"p"}}, J.KV{"resourceVersion", J.JStr{"9"}}])}]) : J.Json}

# Proposed: the 30 s resync requeues virtual pods whose host pod is missing.
def Laws.classic.pmeta(ns: String, n: String) -> J.Json:
  J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{n}}, J.KV{"namespace", J.JStr{ns}}])}])

law classic.unsynced_pods:
  {K.Classic.unsynced_pods("vc", [Laws.classic.pmeta("default", "a"), Laws.classic.pmeta("default", "b")],
    [Laws.classic.pmeta("vcluster-vc", "a-x-default-x-vc")]) == ["pods|default/b"] : List<&2, String>}

# Proposed: a user's change of a real node's capacity in the virtual
# cluster goes to the host node's status (vcluster: the nodechanges proxy
# filter), a removed resource as null.
def Laws.classic.capnode(caps: List<&2, J.KV>) -> J.Json:
  J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{"hc"}}])}, J.KV{"status", J.Json.obj([J.KV{"capacity", J.Json.obj(caps)}])}])

law classic.cap_ops_added:
  {K.Classic.cap_ops(Some{Laws.classic.capnode([J.KV{"cpu", J.JStr{"2"}}])},
    Some{Laws.classic.capnode([J.KV{"cpu", J.JStr{"2"}}, J.KV{"scheduling.k8s.io/foo", J.JStr{"5"}}])})
    == [K.OStatus{True{}, "nodes", Laws.classic.capnode([J.KV{"scheduling.k8s.io/foo", J.JStr{"5"}}])}] : List<&2, K.Op>}
law classic.cap_ops_removed:
  {K.Classic.cap_ops(Some{Laws.classic.capnode([J.KV{"cpu", J.JStr{"2"}}, J.KV{"scheduling.k8s.io/foo", J.JStr{"5"}}])},
    Some{Laws.classic.capnode([J.KV{"cpu", J.JStr{"2"}}])})
    == [K.OStatus{True{}, "nodes", Laws.classic.capnode([J.KV{"scheduling.k8s.io/foo", J.JNull{}}])}] : List<&2, K.Op>}
law classic.cap_ops_same:
  {K.Classic.cap_ops(Some{Laws.classic.capnode([J.KV{"cpu", J.JStr{"2"}}])}, Some{Laws.classic.capnode([J.KV{"cpu", J.JStr{"2"}}])})
    == [] : List<&2, K.Op>}
law classic.cap_ops_first:
  {K.Classic.cap_ops(None{}, Some{Laws.classic.capnode([J.KV{"cpu", J.JStr{"2"}}])}) == [] : List<&2, K.Op>}

# Proposed: a step's last snapshot of a side is the object it wrote there
# (vcluster's informer holds its own last write as the old object).
law classic.written_virtual:
  {K.Classic.written(False{}, [K.OUpdate{True{}, "pods", Laws.classic.pmeta("h", "p")}, K.OStatus{False{}, "pods", Laws.classic.gpod("2", "2")}],
    Laws.classic.gpod("2", "1")) == Laws.classic.gpod("2", "2") : J.Json}
law classic.written_none:
  for d: J.Json
  {K.Classic.written(False{}, [], d) == d : J.Json}

