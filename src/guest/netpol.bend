import Base
import ./plan.bend as P
import ../standalone/native.bend as N
import ../standalone/native_host.bend as NH
import ../cli/ctr.bend as R

# NetworkPolicy enforcement (docs/GOAL.md section 10; option A of the
# explore-netpol-cni report, chosen by the user 2026-11-17): kube-router's
# network policy controller alone, next to flannel and kube-proxy, as k3s
# embeds it (k3s pkg/agent/netpol). It is a node asset (the node set's
# kube-router, pinned per arch in scripts/guest/fetch-assets.sh), started
# and supervised by PID 1 like the kubelet, not a DaemonSet: one Go process
# per node, no pod, no image. vcluster deploys no policy controller of its
# own (its private nodes take whatever CNI the user installs), so the
# values here come from kube-router v2.12.0 (pkg/options/options.go,
# pkg/controllers/netpol) and the user's brief, never from our own code.
#
# Every decision is here, as data: kube-router's flags, where it starts in
# a boot plan, its credentials (the node's own kubelet kubeconfig, which a
# ClusterRole lets read what the controller watches), the startup gate,
# how PID 1 sees the first full sync, and what native delete removes.

# --- The asset

def Netpol.version() -> String:
  "v2.12.0"

def Netpol.name() -> String:
  "kube-router"

# On the node set (scripts/guest/sets.txt), joined at P.Plan.bin().
def Netpol.bin() -> String:
  P.Plan.bin() ++ "/kube-router"

# --- Flags (kube-router pkg/options/options.go)
#
# The firewall (the network policy controller) only: no BGP routing (flannel
# routes), no service proxy (kube-proxy proxies), no load balancer
# allocator, no CNI config (flannel writes it), and the iptables/ipset
# back end, not nftables. --netpol-default-deny makes kube-router REJECT a
# local pod's traffic until its own KUBE-POD-FW chain is in place (kube-
# router docs/user-guide.md "NetworkPolicy Default-Deny"; it reads the
# node's spec.podCIDRs, which kube-controller-manager's
# --allocate-node-cidrs fills, P.Plan.controller_manager_args.base). The
# node is the kubelet's (--hostname-override) and so are the credentials
# (--kubeconfig). The service CIDR is the cluster's (kube-router's
# KUBE-ROUTER-INPUT lets pods reach it). --health-port=0: no health
# listener (nothing probes it, and a host runs several clusters' nodes in
# native mode); metrics stay off (--metrics-port defaults to 0).
def Netpol.args(+kubeconfig: String, +node: String, +svc: String) -> +List<String>:
  [ P.Plan.flag("run-firewall", "true"),
    P.Plan.flag("run-router", "false"),
    P.Plan.flag("run-service-proxy", "false"),
    P.Plan.flag("run-loadbalancer", "false"),
    P.Plan.flag("enable-cni", "false"),
    P.Plan.flag("use-nftables-for-netpol", "false"),
    P.Plan.flag("netpol-default-deny", "true"),
    P.Plan.flag("kubeconfig", kubeconfig),
    P.Plan.flag("hostname-override", node),
    P.Plan.flag("service-cluster-ip-range", svc),
    P.Plan.flag("health-port", "0") ]

def Netpol.value.go(hit: Bool, +x: String, +p: String, +rest: String) -> String:
  match hit:
    case True{}:
      String.drop(x, String.length(p))
    case False{}:
      rest

# The value of --key=value in an argument list ("" when absent).
def Netpol.value(xs: +List<String>, +key: String) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+x, t}:
      +p = "--" ++ key ++ "="
      Netpol.value.go(String.starts_with(x, p), x, p, Netpol.value(t, key))

# kube-router beside a kubelet started with these arguments: the same
# kubeconfig (the node's own credentials: P.Plan.kubelet_args's
# pki/kubelet.conf on a control plane, kubeadm join's
# /etc/kubernetes/kubelet.conf on a worker, each relocated with the
# kubelet's in native mode) and node name.
def Netpol.daemon(+kubelet_args: +List<String>, +svc: String) -> P.Step:
  P.Daemon{Netpol.name(), Netpol.bin(),
    Netpol.args(Netpol.value(kubelet_args, "kubeconfig"), Netpol.value(kubelet_args, "hostname-override"), svc)}

# --- Credentials: what the controller lists and watches (kube-router
# pkg/cmd/kube-router.go: one informer each for services, endpointslices,
# pods, nodes, namespaces and networkpolicies), granted to every node's
# own identity (the group system:nodes; the Node authorizer alone allows
# none of namespaces or networkpolicies). Read-only: the firewall writes
# nothing to the API (kube-router daemonset/kube-router-firewall-
# daemonset.yaml grants more for its other controllers).

def Netpol.role() -> String:
  "vk8s:network-policy"

def Netpol.resources() -> String:
  "pods,namespaces,nodes,services,networkpolicies.networking.k8s.io,endpointslices.discovery.k8s.io"

def Netpol.rbac.go(cp: Bool) -> +List<P.Step>:
  match cp:
    case True{}:
      [ P.Plan.kubectl_ensure(["create", "clusterrole", Netpol.role(), "--verb=get,list,watch", "--resource=" ++ Netpol.resources()]),
        P.Plan.kubectl_ensure(["create", "clusterrolebinding", Netpol.role(), "--clusterrole=" ++ Netpol.role(), "--group=system:nodes"]) ]
    case False{}:
      []

# --- The startup gate: no workload traffic before the controller's first
# full sync. Before the kubelet starts, PID 1 drops every packet from or to
# the pod CIDR that crosses the node (mangle FORWARD: pod to pod, bridged
# through br_netfilter, and pod to the world) or enters it from a pod
# (mangle INPUT), in a chain of its own. mangle runs before every filter
# chain, so neither kube-proxy's nor flannel's ACCEPTs (filter FORWARD) let
# a packet past it, and kube-router never touches mangle. Once kube-router
# has synced, PID 1 empties the chain (the jumps stay, and do nothing).
# Pod traffic is then kube-router's: --netpol-default-deny covers each new
# pod until its own chain exists, and after a kube-router restart its last
# rules stay in force (it removes nothing when it stops).

def Netpol.chain() -> String:
  "VK8S-NETPOL-GATE"

# Where the gate's files are: the data dir's netpol/ (relocated with it in
# native mode).
def Netpol.dir_in(+data: String) -> String:
  data ++ "/netpol"

def Netpol.marker_in(+data: String) -> String:
  Netpol.dir_in(data) ++ "/gate"

def Netpol.gate_file() -> String:
  Netpol.dir_in(P.Plan.data()) ++ "/gate.rules"

def Netpol.open_file_in(+data: String) -> String:
  Netpol.dir_in(data) ++ "/open.rules"

# The guest's (pack.sh links xtables-nft-multi there) and a host's
# (Debian, Ubuntu, Fedora; /usr/sbin is /usr/bin on Arch).
def Netpol.restore() -> String:
  "/usr/sbin/iptables-restore"

def Netpol.iptables() -> String:
  "/usr/sbin/iptables"

# iptables-restore --noflush input: the chain (made, or emptied when it
# exists) with a DROP for each direction, and the jumps first in FORWARD
# and INPUT.
def Netpol.gate_rules(+pod: String) -> String:
  "*mangle\n:" ++ Netpol.chain() ++ " - [0:0]\n"
  ++ "-A " ++ Netpol.chain() ++ " -s " ++ pod ++ " -j DROP\n"
  ++ "-A " ++ Netpol.chain() ++ " -d " ++ pod ++ " -j DROP\n"
  ++ "-I FORWARD 1 -j " ++ Netpol.chain() ++ "\n"
  ++ "-I INPUT 1 -j " ++ Netpol.chain() ++ "\n"
  ++ "COMMIT\n"

# The chain emptied: the gate open.
def Netpol.open_rules() -> String:
  "*mangle\n:" ++ Netpol.chain() ++ " - [0:0]\nCOMMIT\n"

def Netpol.restore_args(+file: String) -> +List<String>:
  ["-w", "--noflush", file]

# Close the gate (boot, before the kubelet), and note it for PID 1.
def Netpol.close(+pod: String) -> +List<P.Step>:
  [ P.Write{Netpol.gate_file(), Netpol.gate_rules(pod)},
    P.Run{Netpol.restore(), Netpol.restore_args(Netpol.gate_file())},
    P.Write{Netpol.marker_in(P.Plan.data()), "closed\n"} ]

# Open it (PID 1, once synced), under the data dir it runs with.
def Netpol.open_in(+data: String) -> +List<P.Step>:
  [ P.Write{Netpol.open_file_in(data), Netpol.open_rules()},
    P.Run{Netpol.restore(), Netpol.restore_args(Netpol.open_file_in(data))},
    P.Write{Netpol.marker_in(data), "open\n"} ]

# Whether the gate waits to be opened (the marker's text).
def Netpol.pending(+text: String) -> Bool:
  String.eq(String.trim(text), "closed")

# What PID 1 runs to look: Netpol.iptables() with these arguments (the
# filter table's KUBE-ROUTER-FORWARD chain alone, in iptables-save's
# form; "No chain" before kube-router has made it).
def Netpol.probe_args() -> +List<String>:
  ["-w", "-S", "KUBE-ROUTER-FORWARD"]

# Where PID 1 writes what it saw (under the data dir it runs with).
def Netpol.probe_file_in(+data: String) -> String:
  Netpol.dir_in(data) ++ "/forward.rules"

def Netpol.sync_line(+l: String) -> Bool:
  String.starts_with(l, "-A KUBE-ROUTER-FORWARD ") && String.contains(l, "-j KUBE-NWPLCY-TAIL")

def Netpol.any_sync_line(ls: +List<String>) -> Bool:
  match ls:
    case Nil{}:
      False{}
    case Con{+l, t}:
      Netpol.sync_line(l) || Netpol.any_sync_line(t)

# Whether kube-router has finished a full sync, from `iptables -S
# KUBE-ROUTER-FORWARD` (or `iptables-save -t filter`): only fullPolicySync's iptables-restore puts the jump to
# KUBE-NWPLCY-TAIL in KUBE-ROUTER-FORWARD (npc_iptables.go
# ensureTailChainPosition); Run's set-up before it makes the top-level
# chains alone.
def Netpol.synced(+text: String) -> Bool:
  Netpol.any_sync_line(String.lines(text))

# --- Where kube-router goes in a boot plan: the gate closes before the
# kubelet starts, kube-router starts right after it (it exits until the
# kubelet's Node exists, has its pod CIDR and, on a worker, its
# credentials; the supervisor restarts it 5 s later), and a control plane
# grants the nodes' identity its read access. Every other step stays.

def Netpol.kubelet(hit: Bool, cp: Bool, +pod: String, +svc: String, +name: String, +prog: String, +args: +List<String>) -> +List<P.Step>:
  match hit:
    case True{}:
      List.append(&2, P.Step, Netpol.close(pod),
        Con{P.Daemon{name, prog, args}, Con{Netpol.daemon(args, svc), Netpol.rbac.go(cp)}})
    case False{}:
      [P.Daemon{name, prog, args}]

def Netpol.at(cp: Bool, +pod: String, +svc: String, s: P.Step) -> +List<P.Step>:
  match s:
    case P.Mount{fs, src, dst, opts}:
      [P.Mount{fs, src, dst, opts}]
    case P.Write{path, text}:
      [P.Write{path, text}]
    case P.Run{prog, args}:
      [P.Run{prog, args}]
    case P.Daemon{+name, +prog, +args}:
      Netpol.kubelet(String.eq(name, "kubelet"), cp, pod, svc, name, prog, args)
    case P.Spawn{name, prog, args}:
      [P.Spawn{name, prog, args}]
    case P.WaitTcp{host, port, ms}:
      [P.WaitTcp{host, port, ms}]
    case P.Stop{names}:
      [P.Stop{names}]
    case P.WaitFile{path, ms}:
      [P.WaitFile{path, ms}]
    case P.Modules{path}:
      [P.Modules{path}]
    case P.Log{text}:
      [P.Log{text}]

# A boot plan with network policy enforcement (cp: a standalone control
# plane, which also grants the RBAC; pod and svc: the cluster's CIDRs).
def Netpol.with(+cp: Bool, +pod: String, +svc: String, ss: +List<P.Step>) -> +List<P.Step>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      List.append(&2, P.Step, Netpol.at(cp, pod, svc, s), Netpol.with(cp, pod, svc, t))

# The same with the cluster's settings.
def Netpol.with_cfg(cp: Bool, +c: P.Cfg, ss: +List<P.Step>) -> +List<P.Step>:
  match c:
    case P.Cfg{name, ip, +svc, +pod, dom, port, etcd}:
      Netpol.with(cp, pod, svc, ss)

# --- Certificate rotation: a Stop of the kubelet (Plan.certs_rotate and
# certs_rotate_ca restart the daemons that load the PKI) stops kube-router
# too, so it reloads the control plane's kubeconfig and CA with them.

def Netpol.stop_names(has: Bool, +names: +List<String>) -> +List<String>:
  match has:
    case True{}:
      List.append(&2, String, names, [Netpol.name()])
    case False{}:
      names

def Netpol.has_kubelet(xs: +List<String>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{+x, t}:
      String.eq(x, "kubelet") || Netpol.has_kubelet(t)

def Netpol.restart.step(s: P.Step) -> P.Step:
  match s:
    case P.Mount{fs, src, dst, opts}:
      P.Mount{fs, src, dst, opts}
    case P.Write{path, text}:
      P.Write{path, text}
    case P.Run{prog, args}:
      P.Run{prog, args}
    case P.Daemon{name, prog, args}:
      P.Daemon{name, prog, args}
    case P.Spawn{name, prog, args}:
      P.Spawn{name, prog, args}
    case P.WaitTcp{host, port, ms}:
      P.WaitTcp{host, port, ms}
    case P.Stop{+names}:
      P.Stop{Netpol.stop_names(Netpol.has_kubelet(names), names)}
    case P.WaitFile{path, ms}:
      P.WaitFile{path, ms}
    case P.Modules{path}:
      P.Modules{path}
    case P.Log{text}:
      P.Log{text}

def Netpol.restarts(ss: +List<P.Step>) -> +List<P.Step>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      Con{Netpol.restart.step(s), Netpol.restarts(t)}

# --- Native mode: NH.NHost.boot with kube-router beside the host node's
# kubelet (a control plane, so it grants the RBAC), before the native
# relocation, which moves its paths with the kubelet's. Without the host
# node there is no kubelet, and the plan is NH.NHost.boot's.
def Netpol.native_boot.go(node: Bool, +e: N.Env, +o: NH.Opts, +c: P.Cfg) -> +List<P.Step>:
  match node:
    case True{}:
      List.append(&2, P.Step, NH.NHost.finish(e, o, NH.NHost.plan.cp(c)),
        Con{NH.NHost.reset(e), NH.NHost.finish(e, o, Netpol.with_cfg(True{}, c, List.append(&2, P.Step, P.Plan.node(c), P.Plan.publish(c))))})
    case False{}:
      NH.NHost.boot.go(False{}, e, o, c)

def Netpol.native_boot(+e: N.Env, +o: NH.Opts, +c: P.Cfg) -> +List<P.Step>:
  Netpol.native_boot.go(NH.NHost.node(o), e, o, c)

# --- Native mode, v2 (docs/ref/review-security-boundary-delta.md F8): a
# host keeps its iptables rules across a restart of the unit (kube-router
# removes nothing when it stops, and NH.NHost.reset cleans no rules). So
# the old KUBE-ROUTER-FORWARD can still hold its jump to KUBE-NWPLCY-TAIL
# when PID 1 first looks (Netpol.synced), and PID 1 would open the gate
# before the new kube-router synced. And each close inserted one more
# jump to the gate in mangle FORWARD and INPUT. So, after the node's
# reset and before the gate closes: every jump to the gate leaves mangle
# FORWARD and INPUT (the close inserts one each again), and every
# KUBE-ROUTER-* chain of the filter table is emptied (kube-router fills
# them again at its start and its first full sync; until then the closed
# gate drops the pods' traffic). The chains stay, as the jumps to them
# from FORWARD, INPUT and OUTPUT do. Nothing else of the host changes.

def Netpol.native_clean_script() -> String:
  "i=" ++ Netpol.iptables() ++ "; "
  ++ "for h in FORWARD INPUT; do while $i -w -t mangle -D $h -j " ++ Netpol.chain() ++ " 2>/dev/null; do :; done; done; "
  ++ "for c in $($i-save -t filter | awk '/^:KUBE-ROUTER-/ { print substr($1, 2) }'); do $i -w -t filter -F \"$c\"; done; true"

def Netpol.native_clean(+e: N.Env) -> P.Step:
  P.Run{N.Native.busybox(e), ["sh", "-c", Netpol.native_clean_script()]}

def Netpol.native_boot.v2.go(node: Bool, +e: N.Env, +o: NH.Opts, +c: P.Cfg) -> +List<P.Step>:
  match node:
    case True{}:
      List.append(&2, P.Step, NH.NHost.finish(e, o, NH.NHost.plan.cp(c)),
        Con{NH.NHost.reset(e), Con{Netpol.native_clean(e),
          NH.NHost.finish(e, o, Netpol.with_cfg(True{}, c, List.append(&2, P.Step, P.Plan.node(c), P.Plan.publish(c))))}})
    case False{}:
      NH.NHost.boot.go(False{}, e, o, c)

# Netpol.native_boot with the stale rules cleaned before the gate closes.
# Without the host node there is no kube-router and no gate: the plan is
# NH.NHost.boot's, as before.
def Netpol.native_boot.v2(+e: N.Env, +o: NH.Opts, +c: P.Cfg) -> +List<P.Step>:
  Netpol.native_boot.v2.go(NH.NHost.node(o), e, o, c)

# --- Host prerequisites

# The kernel modules kube-router's rules need beyond kube-proxy's and
# flannel's: ipset and its hash:ip and hash:net types (the policy sets,
# pkg/controllers/netpol), xt_set (-m set), xt_NFLOG with nfnetlink_log
# and xt_limit (the rate-limited NFLOG of denied packets, pod.go). The
# guest loads them from scripts/guest/modules.txt; a Linux host that runs
# node containers or a native node loads them. The guest's iptables-nft
# (1.8.11) writes -j NFLOG and -m limit as native nft log and limit
# expressions, so the guest also loads nft_log and nft_limit (a host's
# kernel loads those on demand; a guest has no modprobe to do so).
def Netpol.modules() -> +List<String>:
  ["ip_set", "ip_set_hash_ip", "ip_set_hash_net", "xt_set", "xt_NFLOG", "xt_limit"]

# Container mode on Linux: R.Ctr.modules.v2 and these.
def Netpol.ctr_modules() -> +List<String>:
  List.append(&2, String, R.Ctr.modules.v2(), Netpol.modules())

# Native mode: a host node also needs these, and the ipset tool
# (kube-router runs `ipset`, pkg/utils/ipset.go).
def Netpol.native_modules() -> +List<String>:
  List.append(&2, String, NH.NHost.modules(), Netpol.modules())

def Netpol.native_tools() -> +List<String>:
  List.append(&2, String, NH.NHost.tools(), ["ipset"])

# --- Native delete: the gate's chain and jumps leave with kube-proxy's,
# flannel's and the CNI plugins' rules (kube-router's own chains are KUBE-
# ones, which NH.NHost.ipt_clean removes already), then kube-router's ipsets.

def Netpol.ipt_marks() -> +List<String>:
  List.append(&2, String, NH.NHost.ipt_marks(), [Netpol.chain()])

def Netpol.ipt_keep(ls: +List<String>) -> +List<String>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{+l, t}:
      NH.NHost.keep.go(Bool.not(NH.NHost.ipt_ours(Netpol.ipt_marks(), l)), l, Netpol.ipt_keep(t))

def Netpol.ipt_table(+g: +List<String>) -> +List<String>:
  NH.NHost.ipt_pick(Bool.not(Nat.is_eq(List.length(&2, String, Netpol.ipt_keep(g)), List.length(&2, String, g))), Netpol.ipt_keep(g))

def Netpol.ipt_changed(gs: List<&2, List<&2, String>>) -> +List<String>:
  match gs:
    case Nil{}:
      Nil{}
    case Con{+g, t}:
      List.append(&2, String, Netpol.ipt_table(g), Netpol.ipt_changed(t))

# NH.NHost.ipt_clean with the gate's lines too: the input for
# iptables-restore, "" when nothing is vk8s's.
def Netpol.ipt_clean(+text: String) -> String:
  NH.NHost.ipt_text(Netpol.ipt_changed(NH.NHost.ipt_tables(String.lines(text))))

# kube-router's ipsets (pkg/controllers/netpol/network_policy_controller.go:
# the KUBE-SRC- and KUBE-DST- prefixes and kube-router-local-pods).
def Netpol.ipset_ours(+n: String) -> Bool:
  String.starts_with(n, "KUBE-SRC-") || String.starts_with(n, "KUBE-DST-") || String.eq(n, "kube-router-local-pods")

def Netpol.ipsets.go(ours: Bool, +n: String, rest: List<&2, List<&2, String>>) -> List<&2, List<&2, String>>:
  match ours:
    case True{}:
      Con{["sudo", "ipset", "destroy", n], rest}
    case False{}:
      rest

def Netpol.ipsets.of(ls: +List<String>) -> List<&2, List<&2, String>>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{+l, t}:
      +n = String.trim(l)
      Netpol.ipsets.go(Netpol.ipset_ours(n), n, Netpol.ipsets.of(t))

# The commands that destroy them, from `ipset list -n` (once the iptables
# rules that use them are gone).
def Netpol.ipset_destroy(+text: String) -> List<&2, List<&2, String>>:
  Netpol.ipsets.of(String.lines(text))

# --- v2 (security review docs/ref/review-security-boundary-delta.md,
# F1): the native boot with the v2 node reset and the kubelet under the
# cluster's own cgroup root (NH.NHost.boot.v2), and a delete that takes
# only vk8s's chains and sets, by exact name.

# Native mode, v3: v2's clean step (F8) with the per-cluster node reset and
# kubelet cgroup root (review F1).
def Netpol.native_boot.v3.go(node: Bool, +e: N.Env, +o: NH.Opts, +c: P.Cfg) -> +List<P.Step>:
  match node:
    case True{}:
      List.append(&2, P.Step, NH.NHost.finish(e, o, NH.NHost.plan.cp(c)),
        Con{NH.NHost.reset.v2(e, NH.NHost.cfg_name(c)), Con{Netpol.native_clean(e), NH.NHost.kubelet_root(NH.NHost.cgroup_root(NH.NHost.cfg_name(c)),
          NH.NHost.finish(e, o, Netpol.with_cfg(True{}, c, List.append(&2, P.Step, P.Plan.node(c), P.Plan.publish(c)))))}})
    case False{}:
      NH.NHost.boot.v2.go(False{}, e, o, c)

def Netpol.native_boot.v3(+e: N.Env, +o: NH.Opts, +c: P.Cfg) -> +List<P.Step>:
  Netpol.native_boot.v3.go(NH.NHost.node(o), e, o, c)

# kube-router's fixed chains (pkg/controllers/netpol/
# network_policy_controller.go:29-34 at v2.12.0).
def Netpol.ipt_names() -> +List<String>:
  [ "KUBE-ROUTER-INPUT", "KUBE-ROUTER-FORWARD", "KUBE-ROUTER-OUTPUT",
    "KUBE-NWPLCY-DEFAULT", "KUBE-NWPLCY-COMMON", "KUBE-NWPLCY-TAIL" ]

# kube-router's per-pod and per-policy chains (:25-26; names.go
# hashedName: the prefix and base32 of a sha256, cut to 16).
def Netpol.ipt_hashed() -> +List<String>:
  ["KUBE-POD-FW-", "KUBE-NWPLCY-"]

def Netpol.ipt_clean.v2.go(shared: Bool, +text: String) -> String:
  match shared:
    case True{}:
      NH.NHost.ipt_delete([Netpol.chain()], [], False{}, text)
    case False{}:
      NH.NHost.ipt_delete(List.append(&2, String, NH.NHost.ipt_names(), List.append(&2, String, Netpol.ipt_names(), [Netpol.chain()])),
        List.append(&2, String, NH.NHost.ipt_hashed(), Netpol.ipt_hashed()), True{}, text)

# The input for `<stem>-restore --noflush` from `<stem>-save`, "" when
# nothing is vk8s's: the chains of the kubelet, kube-proxy, flannel, the
# CNI plugins (network cbr0) and kube-router, the gate, and the rules
# that jump to them. shared: another kubelet runs on the host, whose
# kube-proxy, flannel and kube-router use the same names; then only the
# gate, whose name is vk8s's alone, goes.
def Netpol.ipt_clean.v2(shared: Bool, +text: String) -> String:
  Netpol.ipt_clean.v2.go(shared, text)

# kube-router's ipsets by exact name: KUBE-SRC- or KUBE-DST- and 16
# base32 characters (network_policy_controller.go:27-28, names.go), and
# kube-router-local-pods (:37).
def Netpol.ipset_ours.v2(+n: String) -> Bool:
  Bool.or(NH.NHost.hashed_ok(["KUBE-SRC-", "KUBE-DST-"], n), String.eq(n, "kube-router-local-pods"))

def Netpol.ipsets.v2.of(ls: +List<String>) -> List<&2, List<&2, String>>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{+l, t}:
      +n = String.trim(l)
      Netpol.ipsets.go(Netpol.ipset_ours.v2(n), n, Netpol.ipsets.v2.of(t))

def Netpol.ipset_destroy.v2.go(shared: Bool, +text: String) -> List<&2, List<&2, String>>:
  match shared:
    case True{}:
      []
    case False{}:
      Netpol.ipsets.v2.of(String.lines(text))

# The commands that destroy them, from `ipset list -n`; none while
# another kubelet runs (its kube-router's sets have the same names).
def Netpol.ipset_destroy.v2(shared: Bool, +text: String) -> List<&2, List<&2, String>>:
  Netpol.ipset_destroy.v2.go(shared, text)
