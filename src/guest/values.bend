import Base
import bend-kube-runtime@0.10.0.0/src/json.bend as J
import ../lib/args.bend as A
import ./plan.bend as P
import ../config/vcluster.bend as V

# What vk8s takes from a vcluster.yaml (src/config/vcluster.bend parses
# and defaults it): the backing store, each control plane component's
# extraArgs (controlPlane.distro.k8s.<component>.extraArgs, vcluster's
# --flag=value strings, merged over vk8s's flags as vcluster merges them;
# feature gates and API groups go there as --feature-gates and
# --runtime-config), the kubelet configuration of every node
# (privateNodes.kubelet.config), and vk8s's own node sysctls
# (vk8s.nodes.proxyArp). Settings vk8s cannot honor yet are refused by
# name, never ignored.

def Values.at.go(ks: List<&2, String>, j: J.Json) -> J.Json:
  match ks:
    case Nil{}:
      j
    case Con{+k, t}:
      Values.at.go(t, J.Json.get(j, k))

def Values.at(j: J.Json, ks: List<&2, String>) -> J.Json:
  Values.at.go(ks, j)

def Values.strs(xs: List<&2, J.Json>) -> +List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      Con{J.Json.str_or(x, ""), Values.strs(t)}

def Values.bool(j: J.Json) -> Bool:
  match j:
    case J.JBool{b}:
      b
    case _:
      False{}

def Values.extra_args(c: J.Json, +component: String) -> +List<String>:
  Values.strs(J.Json.items(Values.at(c, ["controlPlane", "distro", "k8s", component, "extraArgs"])))

# controlPlane.backingStore: embedded etcd wins when both are enabled.
def Values.etcd(c: J.Json) -> Bool:
  Values.bool(Values.at(c, ["controlPlane", "backingStore", "etcd", "embedded", "enabled"]))

def Values.version(c: J.Json) -> String:
  J.Json.str_or(Values.at(c, ["controlPlane", "distro", "k8s", "version"]), "")

def Values.check(+ok: Bool, +msg: String, rest: String) -> String:
  match ok:
    case True{}:
      rest
    case False{}:
      msg

# "" when vk8s can run this configuration; otherwise why not.
def Values.unsupported(+c: J.Json) -> String:
  +ver : String = Values.version(c)
  +svc : String = J.Json.str_or(Values.at(c, ["networking", "serviceCIDR"]), "")
  +pod : String = J.Json.str_or(Values.at(c, ["networking", "podCIDR"]), "")
  +dom : String = J.Json.str_or(Values.at(c, ["networking", "advanced", "clusterDomain"]), "")
  +rep : String = J.Json.show(Values.at(c, ["controlPlane", "coredns", "deployment", "replicas"]))
  Values.check(String.is_empty(ver) || String.eq(ver, "v1.36.6"),
    "vk8s ships Kubernetes v1.36.6; controlPlane.distro.k8s.version " ++ ver ++ " is not available",
  Values.check(String.is_empty(svc) || String.eq(svc, "10.96.0.0/12"), "vk8s does not support networking.serviceCIDR other than 10.96.0.0/12 yet",
  Values.check(String.eq(pod, "10.244.0.0/16"), "vk8s does not support networking.podCIDR other than 10.244.0.0/16 yet",
  Values.check(String.eq(dom, "cluster.local"), "vk8s does not support networking.advanced.clusterDomain other than cluster.local yet",
  Values.check(String.eq(rep, "1"), "vk8s does not support controlPlane.coredns.deployment.replicas other than 1 yet", "")))))

def Values.component.go(api: Bool, cm: Bool, sch: Bool) -> String:
  match api cm sch:
    case True{} _ _:
      "apiServer"
    case False{} True{} _:
      "controllerManager"
    case False{} False{} True{}:
      "scheduler"
    case _ _ _:
      ""

def Values.component(+name: String) -> String:
  Values.component.go(String.eq(name, "kube-apiserver"), String.eq(name, "kube-controller-manager"), String.eq(name, "kube-scheduler"))

def Values.step.args(none: Bool, +c: J.Json, +comp: String, +args: +List<String>) -> +List<String>:
  match none:
    case True{}:
      args
    case False{}:
      A.Args.merge(args, Values.extra_args(c, comp))

def Values.step.go(+comp: String, +c: J.Json, +name: String, +prog: String, +args: +List<String>) -> P.Step:
  P.Daemon{name, prog, Values.step.args(String.is_empty(comp), c, comp, args)}

def Values.step(+c: J.Json, s: P.Step) -> P.Step:
  match s:
    case P.Daemon{+name, +prog, +args}:
      Values.step.go(Values.component(name), c, name, prog, args)
    case other:
      other

# The boot plan with the configuration's extraArgs merged into the API
# server, controller manager and scheduler (later flags win).
def Values.with_extra(ss: +List<P.Step>, +c: J.Json) -> +List<P.Step>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      Con{Values.step(c, s), Values.with_extra(t, c)}

def Values.classic.sched(on: Bool, +c: P.Cfg, ss: +List<P.Step>) -> +List<P.Step>:
  match on:
    case True{}:
      P.Plan.virtual_scheduler(c, ss)
    case False{}:
      ss

def Values.classic.file(file: Bool, ss: +List<P.Step>) -> +List<P.Step>:
  match file:
    case True{}:
      P.Plan.syncer_config(P.Plan.host_dir() ++ "/vcluster.yaml", ss)
    case False{}:
      ss

# A classic plan with the share's vcluster.yaml (file: it exists): the
# syncer reads it (--config), and vcluster's virtual scheduler
# (IsVirtualSchedulerEnabled) adds kube-scheduler and the controller
# manager's virtual-scheduler flags.
def Values.classic(+cfg: J.Json, +c: P.Cfg, file: Bool, ss: +List<P.Step>) -> +List<P.Step>:
  Values.classic.sched(V.Config.virtual_scheduler(cfg), c, Values.classic.file(file, ss))

# The boot plan up to and including the mount of the host share, and the
# rest: PID 1 reads the share's vcluster.yaml in between.
type Split is Data:
  Split{pre: +List<P.Step>, post: +List<P.Step>}

def Values.is_share(s: P.Step) -> Bool:
  match s:
    case P.Mount{fs, src, +dst, o}:
      String.eq(dst, P.Plan.host_dir())
    case _:
      False{}

def Values.split.go(hit: Bool, +s: P.Step, +t: +List<P.Step>, rest: Split) -> Split:
  match hit:
    case True{}:
      Split{[s], t}
    case False{}:
      match rest:
        case Split{a, b}:
          Split{Con{s, a}, b}

def Values.split(ss: +List<P.Step>) -> Split:
  match ss:
    case Nil{}:
      Split{Nil{}, Nil{}}
    case Con{+s, +t}:
      Values.split.go(Values.is_share(s), s, t, Values.split(t))

# --- Flags and kubelet keys vk8s owns (vk8s design: vcluster merges
# every extraArg, but vk8s's ports, listen addresses, certificates,
# kubeconfigs and data paths are fixed by its plan, its port forwards and
# its PKI; a changed one breaks the cluster in ways that are hard to see).

def Values.member(xs: +List<String>, +s: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{+x, t}:
      String.eq(x, s) || Values.member(t, s)

def Values.owned.go(api: Bool, cm: Bool) -> +List<String>:
  match api cm:
    case True{} _:
      [ "--secure-port", "--bind-address", "--advertise-address", "--cert-dir", "--etcd-servers", "--etcd-cafile",
        "--etcd-certfile", "--etcd-keyfile", "--client-ca-file", "--tls-cert-file", "--tls-private-key-file",
        "--kubelet-client-certificate", "--kubelet-client-key", "--proxy-client-cert-file", "--proxy-client-key-file",
        "--requestheader-client-ca-file", "--service-account-key-file", "--service-account-signing-key-file",
        "--service-cluster-ip-range", "--egress-selector-config-file" ]
    case False{} True{}:
      [ "--secure-port", "--bind-address", "--cert-dir", "--kubeconfig", "--authentication-kubeconfig",
        "--authorization-kubeconfig", "--client-ca-file", "--requestheader-client-ca-file", "--root-ca-file",
        "--service-account-private-key-file", "--cluster-signing-cert-file", "--cluster-signing-key-file",
        "--service-cluster-ip-range", "--cluster-cidr" ]
    case False{} False{}:
      [ "--secure-port", "--bind-address", "--cert-dir", "--kubeconfig", "--authentication-kubeconfig",
        "--authorization-kubeconfig" ]

# The flags of a component (apiServer, controllerManager, scheduler) that
# vk8s sets itself.
def Values.owned(+comp: String) -> +List<String>:
  Values.owned.go(String.eq(comp, "apiServer"), String.eq(comp, "controllerManager"))

def Values.owned_flag.pick(hit: Bool, +key: String, rest: String) -> String:
  match hit:
    case True{}:
      key
    case False{}:
      rest

# The first flag of args that owned names ("" when none); a flag is
# named by its key (--flag of --flag=value), as MergeArgs matches it.
def Values.owned_flag(args: +List<String>, +owned: +List<String>) -> String:
  match args:
    case Nil{}:
      ""
    case Con{+a, t}:
      Values.owned_flag.pick(A.Args.is_flag(a) && Values.member(owned, A.Args.key(a)), A.Args.key(a), Values.owned_flag(t, owned))

def Values.args_refused.go(+flag: String, +comp: String) -> String:
  Values.check(String.is_empty(flag), "vk8s sets " ++ flag ++ " itself (its ports, addresses, certificates, kubeconfigs and data paths); "
    ++ "remove it from controlPlane.distro.k8s." ++ comp ++ ".extraArgs", "")

# "" unless the component's extraArgs set a flag vk8s owns.
def Values.args_refused(+c: J.Json, +comp: String) -> String:
  Values.args_refused.go(Values.owned_flag(Values.extra_args(c, comp), Values.owned(comp)), comp)

# The KubeletConfiguration keys vk8s writes (P.Plan.kubelet_config,
# P.Plan.kubeadm_config, and podLogsDir on a native host node). The
# kubelet decodes its config strictly, so a second copy of one of them
# would stop it.
def Values.kubelet_owned() -> +List<String>:
  [ "apiVersion", "kind", "authentication", "authorization", "cgroupDriver", "clusterDNS", "clusterDomain",
    "containerRuntimeEndpoint", "failSwapOn", "resolvConf", "staticPodPath", "imageMaximumGCAge", "podLogsDir" ]

# privateNodes.kubelet.config (vcluster config/config.go Kubelet.Config:
# merged into the default kubelet config of every node).
def Values.kubelet_config(+c: J.Json) -> J.Json:
  Values.at(c, ["privateNodes", "kubelet", "config"])

def Values.owned_key(ms: J.Json, +owned: +List<String>) -> String:
  match ms:
    case J.JObj{m}:
      Values.owned_key(m, owned)
    case J.JMem{+k, v, t}:
      Values.owned_flag.pick(Values.member(owned, k), k, Values.owned_key(t, owned))
    case _:
      ""

def Values.kubelet_refused.go(+key: String) -> String:
  Values.check(String.is_empty(key), "vk8s sets privateNodes.kubelet.config." ++ key ++ " itself; remove it from the vcluster.yaml", "")

# "" unless privateNodes.kubelet.config sets a key vk8s writes.
def Values.kubelet_refused(+c: J.Json) -> String:
  Values.kubelet_refused.go(Values.owned_key(Values.kubelet_config(c), Values.kubelet_owned()))

# Values.unsupported, then the owned flags of each component and the
# owned kubelet keys: "" when vk8s can run this configuration.
def Values.unsupported.v2(+c: J.Json) -> String:
  V.Config.first([Values.unsupported(c), Values.args_refused(c, "apiServer"), Values.args_refused(c, "controllerManager"),
    Values.args_refused(c, "scheduler"), Values.kubelet_refused(c)])

# --- The kubelet configuration

# A value as YAML flow text: JSON with a space after each ':' and ','.
def Values.yaml(j: J.Json) -> String:
  match j:
    case J.JObj{ms}:
      "{" ++ Values.yaml(ms) ++ "}"
    case J.JArr{xs}:
      "[" ++ Values.yaml(xs) ++ "]"
    case J.JMem{k, v, J.JNil{}}:
      J.Json.quote(k) ++ ": " ++ Values.yaml(v)
    case J.JMem{k, v, t}:
      J.Json.quote(k) ++ ": " ++ Values.yaml(v) ++ ", " ++ Values.yaml(t)
    case J.JCons{h, J.JNil{}}:
      Values.yaml(h)
    case J.JCons{h, t}:
      Values.yaml(h) ++ ", " ++ Values.yaml(t)
    case J.JNil{}:
      ""
    case x:
      J.Json.show(x)

def Values.kubelet_lines.go(ms: J.Json) -> String:
  match ms:
    case J.JObj{m}:
      Values.kubelet_lines.go(m)
    case J.JMem{k, v, t}:
      J.Json.quote(k) ++ ": " ++ Values.yaml(v) ++ "\n" ++ Values.kubelet_lines.go(t)
    case _:
      ""

# privateNodes.kubelet.config as KubeletConfiguration lines, one per key,
# in the document's order ("" when it has none).
def Values.kubelet_lines(+c: J.Json) -> String:
  Values.kubelet_lines.go(Values.kubelet_config(c))

def Values.marker() -> String:
  "kind: KubeletConfiguration\n"

def Values.insert.at(hit: Bool, +c: Char, +t: String, +ins: String, rest: String) -> String:
  match hit:
    case True{}:
      Values.marker() ++ ins ++ String.drop(t, 26n)
    case False{}:
      SCon{c, rest}

# text with ins after its first "kind: KubeletConfiguration" line: the
# keys join that document wherever it is (kubeadm.yaml has more documents
# after it in container mode).
def Values.insert(text: String, +ins: String) -> String:
  match text:
    case SNil{}:
      SNil{}
    case SCon{+c, +t}:
      Values.insert.at(String.starts_with(SCon{c, t}, Values.marker()), c, t, ins, Values.insert(t, ins))

# The files that hold a KubeletConfiguration: the control plane node's
# kubelet-config.yaml, and kubeadm.yaml, whose KubeletConfiguration
# `kubeadm init phase upload-config` puts in the kubelet-config ConfigMap
# that joining nodes (worker VMs and containers) download.
def Values.kubelet_file(+path: String) -> Bool:
  String.ends_with(path, "/kubelet-config.yaml") || String.ends_with(path, "/kubeadm.yaml")

def Values.kubelet.write(hit: Bool, +path: String, +text: String, +ins: String) -> P.Step:
  match hit:
    case True{}:
      P.Write{path, Values.insert(text, ins)}
    case False{}:
      P.Write{path, text}

def Values.kubelet.step(+ins: String, s: P.Step) -> P.Step:
  match s:
    case P.Write{+path, +text}:
      Values.kubelet.write(Values.kubelet_file(path), path, text, ins)
    case other:
      other

def Values.with_kubelet.go(ss: +List<P.Step>, +ins: String) -> +List<P.Step>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      Con{Values.kubelet.step(ins, s), Values.with_kubelet.go(t, ins)}

# The plan with privateNodes.kubelet.config in its KubeletConfigurations.
def Values.with_kubelet(ss: +List<P.Step>, +c: J.Json) -> +List<P.Step>:
  Values.with_kubelet.go(ss, Values.kubelet_lines(c))

# --- Node sysctls (vk8s extension; vcluster has no such key)
#
# vk8s.nodes.proxyArp: true sets net.ipv4.conf.all.proxy_arp=1 and, when
# the kernel has IPv6, net.ipv6.conf.all.proxy_ndp=1 on every node, as
# agent-substrate's hack/create-kind-cluster.sh does on its kind nodes
# (`sysctl net.ipv4.conf.all.proxy_arp=1`, `sysctl -e
# net.ipv6.conf.all.proxy_ndp=1`). Default off. It lives in the
# vcluster.yaml under a key named vk8s, not a create flag, because the
# file travels with the cluster: every node's PID 1 reads it from its
# share at each boot (restarts, restores, workers added later), and one
# key serves the VM, container and native backends.

def Values.proxy_arp(+c: J.Json) -> Bool:
  V.Config.bool_or(Values.at(c, ["vk8s", "nodes", "proxyArp"]), False{})

def Values.sysctls.go(on: Bool, v6: Bool) -> +List<P.Step>:
  match on v6:
    case True{} True{}:
      [P.Write{"/proc/sys/net/ipv4/conf/all/proxy_arp", "1"}, P.Write{"/proc/sys/net/ipv6/conf/all/proxy_ndp", "1"}]
    case True{} False{}:
      [P.Write{"/proc/sys/net/ipv4/conf/all/proxy_arp", "1"}]
    case False{} _:
      []

# A guest node's sysctl steps (v6: the kernel has IPv6, so
# /proc/sys/net/ipv6 exists).
def Values.sysctls(+c: J.Json, v6: Bool) -> +List<P.Step>:
  Values.sysctls.go(Values.proxy_arp(c), v6)

# --- All of it

# A plan with the vcluster.yaml's extraArgs and kubelet configuration (a
# native host, whose sysctls the preflight asks for).
def Values.with_values(ss: +List<P.Step>, +c: J.Json) -> +List<P.Step>:
  Values.with_kubelet(Values.with_extra(ss, c), c)

# A guest's plan after its share's mount: the node sysctls first, then
# Values.with_values.
def Values.with_node(ss: +List<P.Step>, +c: J.Json, v6: Bool) -> +List<P.Step>:
  List.append(&2, P.Step, Values.sysctls(c, v6), Values.with_values(ss, c))

# Control-plane-only nodes (v2, GOAL section 11): vcluster's
# controlPlane.standalone.joinNode.enabled (config/config.go: "If false,
# only the control plane binaries will be executed and no node will show
# up in the actual cluster"; chart/values.yaml default true). With it
# false, a standalone control plane's boot keeps every cluster step (the
# API server, controllers, kube-proxy and flannel addons, CoreDNS, RBAC,
# join tokens) and drops the node's own daemons (containerd, the kubelet,
# the layer snapshotter and kube-router) and the steps that need
# containerd: the waits for its and the snapshotter's sockets and the
# `ctr` image imports.
# Absent or true: the plan as it is.

def Values.false_set(j: J.Json) -> Bool:
  match j:
    case J.JBool{b}:
      Bool.not(b)
    case _:
      False{}

def Values.join_off(+c: J.Json) -> Bool:
  Values.false_set(Values.at(c, ["controlPlane", "standalone", "joinNode", "enabled"]))

def Values.node_daemon(+name: String) -> Bool:
  String.eq(name, "containerd") || String.eq(name, "kubelet") || String.eq(name, "snapshotter") || String.eq(name, "kube-router")

def Values.containerd_sock() -> String:
  "/run/containerd/containerd.sock"

# An argument list that names containerd's socket (a `ctr` shell loop).
def Values.names_sock(args: +List<String>) -> Bool:
  match args:
    case Nil{}:
      False{}
    case Con{a, t}:
      String.contains(a, Values.containerd_sock()) || Values.names_sock(t)

def Values.keep.v2(s: P.Step) -> Bool:
  match s:
    case P.Daemon{n, p, a}:
      Bool.not(Values.node_daemon(n))
    case P.WaitFile{+path, ms}:
      Bool.not(String.eq(path, Values.containerd_sock()) || String.eq(path, "/run/vk8s/snapshotter.sock"))
    case P.Run{prog, args}:
      Bool.not(String.ends_with(prog, "/ctr") || Values.names_sock(args))
    case _:
      True{}

def Values.without_node.put(keep: Bool, s: P.Step, rest: +List<P.Step>) -> +List<P.Step>:
  match keep:
    case True{}:
      Con{s, rest}
    case False{}:
      rest

# The steps without the node's own daemons.
def Values.without_node.v2(ss: +List<P.Step>) -> +List<P.Step>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{+s, t}:
      Values.without_node.put(Values.keep.v2(s), s, Values.without_node.v2(t))

def Values.join_node.go(off: Bool, ss: +List<P.Step>) -> +List<P.Step>:
  match off:
    case True{}:
      Values.without_node.v2(ss)
    case False{}:
      ss

# A boot's steps under vcluster.yaml c: on a standalone control plane
# (cp) with joinNode.enabled false, without the node's daemons.
def Values.join_node.v2(cp: Bool, +c: J.Json, ss: +List<P.Step>) -> +List<P.Step>:
  Values.join_node.go(cp && Values.join_off(c), ss)
