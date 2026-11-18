import Base
import ../src/guest/plan.bend as P
import ../src/guest/netpol.bend as NP
import ../src/standalone/native.bend as N
import ../src/standalone/native_host.bend as NH

# Proposed: the spec of src/guest/netpol.bend (docs/GOAL.md section 10,
# NetworkPolicy enforcement with kube-router's network policy controller
# only, option A of the explore-netpol-cni report, chosen by the user
# 2026-11-17). vcluster has no policy controller of its own, so the
# expected values come from kube-router v2.12.0 (pkg/options/options.go,
# pkg/controllers/netpol) and the user's brief.

# --- The asset and its flags

law netpol.version:
  {NP.Netpol.version() == "v2.12.0" : String}

law netpol.bin:
  {NP.Netpol.bin() == "/var/lib/vcluster/bin/kube-router" : String}

# The brief's flags: the firewall only, iptables/ipset; then default deny
# for new pods, the node's identity and name, the service CIDR, no health
# listener.
law netpol.args:
  {NP.Netpol.args("/etc/kubernetes/kubelet.conf", "w1", "10.96.0.0/12") ==
    [ "--run-firewall=true", "--run-router=false", "--run-service-proxy=false", "--run-loadbalancer=false",
      "--enable-cni=false", "--use-nftables-for-netpol=false", "--netpol-default-deny=true",
      "--kubeconfig=/etc/kubernetes/kubelet.conf", "--hostname-override=w1",
      "--service-cluster-ip-range=10.96.0.0/12", "--health-port=0" ] : +List<String>}

# kube-router takes the kubelet's kubeconfig and node name (not its
# --bootstrap-kubeconfig).
law netpol.daemon_from_kubelet:
  {NP.Netpol.daemon(["--config=/var/lib/kubelet/config.yaml", "--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf",
      "--kubeconfig=/etc/kubernetes/kubelet.conf", "--hostname-override=w1", "--node-ip=10.10.0.3"], "10.96.0.0/12") ==
    P.Daemon{"kube-router", "/var/lib/vcluster/bin/kube-router", NP.Netpol.args("/etc/kubernetes/kubelet.conf", "w1", "10.96.0.0/12")} : P.Step}

# --- The startup gate

law netpol.gate_rules:
  {NP.Netpol.gate_rules("10.244.0.0/16") ==
    "*mangle\n:VK8S-NETPOL-GATE - [0:0]\n-A VK8S-NETPOL-GATE -s 10.244.0.0/16 -j DROP\n-A VK8S-NETPOL-GATE -d 10.244.0.0/16 -j DROP\n-I FORWARD 1 -j VK8S-NETPOL-GATE\n-I INPUT 1 -j VK8S-NETPOL-GATE\nCOMMIT\n" : String}

law netpol.open_rules:
  {NP.Netpol.open_rules() == "*mangle\n:VK8S-NETPOL-GATE - [0:0]\nCOMMIT\n" : String}

law netpol.close:
  {NP.Netpol.close("10.244.0.0/16") ==
    [ P.Write{"/var/lib/vcluster/netpol/gate.rules", NP.Netpol.gate_rules("10.244.0.0/16")},
      P.Run{"/usr/sbin/iptables-restore", ["-w", "--noflush", "/var/lib/vcluster/netpol/gate.rules"]},
      P.Write{"/var/lib/vcluster/netpol/gate", "closed\n"} ] : +List<P.Step>}

law netpol.open_in:
  {NP.Netpol.open_in("/var/lib/vk8s/demo") ==
    [ P.Write{"/var/lib/vk8s/demo/netpol/open.rules", NP.Netpol.open_rules()},
      P.Run{"/usr/sbin/iptables-restore", ["-w", "--noflush", "/var/lib/vk8s/demo/netpol/open.rules"]},
      P.Write{"/var/lib/vk8s/demo/netpol/gate", "open\n"} ] : +List<P.Step>}

law netpol.pending_closed:
  {NP.Netpol.pending("closed\n") == True{} : Bool}

law netpol.pending_open:
  {NP.Netpol.pending("open\n") == False{} : Bool}

law netpol.pending_none:
  {NP.Netpol.pending("") == False{} : Bool}

law netpol.probe:
  {NP.Netpol.probe_args() == ["-w", "-S", "KUBE-ROUTER-FORWARD"] : +List<String>}

# After fullPolicySync's iptables-restore (npc_iptables.go
# ensureTailChainPosition, its comment verbatim).
law netpol.synced_after_full_sync:
  {NP.Netpol.synced("-N KUBE-ROUTER-FORWARD\n-A KUBE-ROUTER-FORWARD -m comment --comment \"rule to explicitly handle traffic for network policies ACCEPT/REJECT decision\" -j KUBE-NWPLCY-TAIL\n") == True{} : Bool}

# Run's set-up alone makes the chain, empty.
law netpol.not_synced_empty_chain:
  {NP.Netpol.synced("-N KUBE-ROUTER-FORWARD\n") == False{} : Bool}

law netpol.not_synced_no_chain:
  {NP.Netpol.synced("iptables: No chain/target/match by that name.\n") == False{} : Bool}

# A jump to the tail from another chain is not the sync.
law netpol.not_synced_other_chain:
  {NP.Netpol.synced("-A KUBE-ROUTER-INPUT -j KUBE-NWPLCY-TAIL\n") == False{} : Bool}

# --- Where it goes in a plan

# A worker: the gate closes before the kubelet, kube-router follows it,
# nothing else moves.
law netpol.worker_order:
  {NP.Netpol.with(False{}, "10.244.0.0/16", "10.96.0.0/12",
      [ P.Log{"a"}, P.Daemon{"kubelet", "/k", ["--kubeconfig=/etc/kubernetes/kubelet.conf", "--hostname-override=w1"]}, P.Log{"b"} ]) ==
    [ P.Log{"a"},
      P.Write{"/var/lib/vcluster/netpol/gate.rules", NP.Netpol.gate_rules("10.244.0.0/16")},
      P.Run{"/usr/sbin/iptables-restore", ["-w", "--noflush", "/var/lib/vcluster/netpol/gate.rules"]},
      P.Write{"/var/lib/vcluster/netpol/gate", "closed\n"},
      P.Daemon{"kubelet", "/k", ["--kubeconfig=/etc/kubernetes/kubelet.conf", "--hostname-override=w1"]},
      P.Daemon{"kube-router", "/var/lib/vcluster/bin/kube-router", NP.Netpol.args("/etc/kubernetes/kubelet.conf", "w1", "10.96.0.0/12")},
      P.Log{"b"} ] : +List<P.Step>}

# A control plane also grants every node's identity read access to what
# the controller watches (kube-router pkg/cmd/kube-router.go informers).
law netpol.cp_rbac:
  {NP.Netpol.with(True{}, "10.244.0.0/16", "10.96.0.0/12", [P.Daemon{"kubelet", "/k", ["--kubeconfig=/c", "--hostname-override=cp"]}]) ==
    List.append(&2, P.Step, NP.Netpol.close("10.244.0.0/16"),
      [ P.Daemon{"kubelet", "/k", ["--kubeconfig=/c", "--hostname-override=cp"]},
        P.Daemon{"kube-router", "/var/lib/vcluster/bin/kube-router", NP.Netpol.args("/c", "cp", "10.96.0.0/12")},
        P.Plan.kubectl_ensure(["create", "clusterrole", "vk8s:network-policy", "--verb=get,list,watch",
          "--resource=pods,namespaces,nodes,services,networkpolicies.networking.k8s.io,endpointslices.discovery.k8s.io"]),
        P.Plan.kubectl_ensure(["create", "clusterrolebinding", "vk8s:network-policy", "--clusterrole=vk8s:network-policy",
          "--group=system:nodes"]) ]) : +List<P.Step>}

law netpol.with_nil:
  for cp: Bool
  for pod: String
  for svc: String
  {NP.Netpol.with(cp, pod, svc, []) == [] : +List<P.Step>}

# Any other daemon stays as it is.
law netpol.other_daemon_kept:
  for cp: Bool
  for pod: String
  for svc: String
  for name: String
  for prog: String
  for args: +List<String>
  for ss: +List<P.Step>
  for h: {String.eq(name, "kubelet") == False{} : Bool}
  {NP.Netpol.with(cp, pod, svc, Con{P.Daemon{name, prog, args}, ss}) ==
    Con{P.Daemon{name, prog, args}, NP.Netpol.with(cp, pod, svc, ss)} : +List<P.Step>}

law netpol.run_kept:
  for cp: Bool
  for pod: String
  for svc: String
  for prog: String
  for args: +List<String>
  for ss: +List<P.Step>
  {NP.Netpol.with(cp, pod, svc, Con{P.Run{prog, args}, ss}) == Con{P.Run{prog, args}, NP.Netpol.with(cp, pod, svc, ss)} : +List<P.Step>}

law netpol.write_kept:
  for cp: Bool
  for pod: String
  for svc: String
  for path: String
  for text: String
  for ss: +List<P.Step>
  {NP.Netpol.with(cp, pod, svc, Con{P.Write{path, text}, ss}) == Con{P.Write{path, text}, NP.Netpol.with(cp, pod, svc, ss)} : +List<P.Step>}

# --- Certificate rotation restarts kube-router with the kubelet

law netpol.restarts:
  {NP.Netpol.restarts([P.Stop{["kubelet", "kube-scheduler"]}, P.Stop{["etcd"]}, P.Log{"x"}]) ==
    [P.Stop{["kubelet", "kube-scheduler", "kube-router"]}, P.Stop{["etcd"]}, P.Log{"x"}] : +List<P.Step>}

# --- Native mode without the host node: NH.NHost.boot's plan.
law netpol.native_no_node:
  for e: N.Env
  for o: NH.Opts
  for c: P.Cfg
  for h: {NH.NHost.node(o) == False{} : Bool}
  {NP.Netpol.native_boot(e, o, c) == NH.NHost.boot(e, o, c) : +List<P.Step>}

# --- Host prerequisites

law netpol.modules:
  {NP.Netpol.modules() == ["ip_set", "ip_set_hash_ip", "ip_set_hash_net", "xt_set", "xt_NFLOG", "xt_limit"] : +List<String>}

law netpol.ctr_modules:
  {NP.Netpol.ctr_modules() == ["overlay", "bridge", "br_netfilter", "veth", "vxlan", "nf_tables", "nf_conntrack", "af_packet",
    "ip_set", "ip_set_hash_ip", "ip_set_hash_net", "xt_set", "xt_NFLOG", "xt_limit"] : +List<String>}

law netpol.native_modules:
  {NP.Netpol.native_modules() == ["overlay", "br_netfilter", "ip_set", "ip_set_hash_ip", "ip_set_hash_net", "xt_set", "xt_NFLOG", "xt_limit"] : +List<String>}

law netpol.native_tools:
  {NP.Netpol.native_tools() == ["sudo", "systemctl", "unsquashfs", "cpio", "ip", "iptables-save", "iptables-restore", "kubectl", "perl", "ipset"] : +List<String>}

# --- Native delete

# The gate's chain and its jumps leave with kube-proxy's and
# kube-router's (KUBE-) rules; a table with none of them is not rewritten.
law netpol.ipt_clean:
  {NP.Netpol.ipt_clean("*mangle\n:PREROUTING ACCEPT [0:0]\n:VK8S-NETPOL-GATE - [0:0]\n-A FORWARD -j VK8S-NETPOL-GATE\n-A INPUT -j VK8S-NETPOL-GATE\n-A OUTPUT -j MINE\nCOMMIT\n*raw\n-A PREROUTING -j MINE\nCOMMIT\n") ==
    "*mangle\n:PREROUTING ACCEPT [0:0]\n-A OUTPUT -j MINE\nCOMMIT\n" : String}

# `ipset list -n`: kube-router's sets (KUBE-SRC-, KUBE-DST-,
# kube-router-local-pods) go, others stay.
law netpol.ipset_destroy:
  {NP.Netpol.ipset_destroy("KUBE-SRC-ABCDEF\ndocker-set\nkube-router-local-pods\nKUBE-DST-123456\n") ==
    [["sudo", "ipset", "destroy", "KUBE-SRC-ABCDEF"], ["sudo", "ipset", "destroy", "kube-router-local-pods"],
      ["sudo", "ipset", "destroy", "KUBE-DST-123456"]] : List<&2, List<&2, String>>}

# Proposed: native delete v2 by exact name (security review
# docs/ref/review-security-boundary-delta.md, F1), with
# iptables-restore --noflush. The gate's chain and its jumps leave; a
# table with no chain of vk8s's gives nothing.
law netpol.ipt_clean_v2:
  {NP.Netpol.ipt_clean.v2(False{}, "*mangle\n:PREROUTING ACCEPT [0:0]\n:VK8S-NETPOL-GATE - [0:0]\n-A FORWARD -j VK8S-NETPOL-GATE\n-A INPUT -j VK8S-NETPOL-GATE\n-A OUTPUT -j MINE\nCOMMIT\n*raw\n-A PREROUTING -j MINE\nCOMMIT\n") ==
    "*mangle\n-D FORWARD -j VK8S-NETPOL-GATE\n-D INPUT -j VK8S-NETPOL-GATE\n-F VK8S-NETPOL-GATE\n-X VK8S-NETPOL-GATE\nCOMMIT\n" : String}

# kube-router's chains (network_policy_controller.go:25-34 at v2.12.0;
# names.go: a prefix and 16 base32 characters) leave with the jumps
# kube-router puts in the built-in chains (npc_iptables.go:266-268).
law netpol.ipt_clean_v2_kube_router:
  {NP.Netpol.ipt_clean.v2(False{}, "*filter\n:FORWARD ACCEPT [0:0]\n:KUBE-ROUTER-FORWARD - [0:0]\n:KUBE-NWPLCY-TAIL - [0:0]\n"
     ++ ":KUBE-POD-FW-ABCDEFGHIJKLMNOP - [0:0]\n:KUBE-NWPLCY-ABCDEFGHIJKLMNOP - [0:0]\n"
     ++ "-A FORWARD -m comment --comment \"kube-router netpol - 4IA2OSFRMVNDXBVV\" -j KUBE-ROUTER-FORWARD\n"
     ++ "-A KUBE-ROUTER-FORWARD -d 10.244.0.5/32 -j KUBE-POD-FW-ABCDEFGHIJKLMNOP\n"
     ++ "-A KUBE-POD-FW-ABCDEFGHIJKLMNOP -j KUBE-NWPLCY-ABCDEFGHIJKLMNOP\n"
     ++ "-A KUBE-ROUTER-FORWARD -j KUBE-NWPLCY-TAIL\nCOMMIT\n") ==
    "*filter\n-D FORWARD -m comment --comment \"kube-router netpol - 4IA2OSFRMVNDXBVV\" -j KUBE-ROUTER-FORWARD\n"
    ++ "-F KUBE-ROUTER-FORWARD\n-F KUBE-NWPLCY-TAIL\n-F KUBE-POD-FW-ABCDEFGHIJKLMNOP\n-F KUBE-NWPLCY-ABCDEFGHIJKLMNOP\n"
    ++ "-X KUBE-ROUTER-FORWARD\n-X KUBE-NWPLCY-TAIL\n-X KUBE-POD-FW-ABCDEFGHIJKLMNOP\n-X KUBE-NWPLCY-ABCDEFGHIJKLMNOP\nCOMMIT\n" : String}

# While another kubelet runs (k3s), its kube-proxy, flannel and
# kube-router use the same chain names: only the gate leaves.
law netpol.ipt_clean_v2_shared:
  {NP.Netpol.ipt_clean.v2(True{}, "*filter\n:FORWARD ACCEPT [0:0]\n:KUBE-ROUTER-FORWARD - [0:0]\n:FLANNEL-FWD - [0:0]\n"
     ++ "-A FORWARD -j KUBE-ROUTER-FORWARD\n-A FORWARD -j FLANNEL-FWD\nCOMMIT\n"
     ++ "*mangle\n:FORWARD ACCEPT [0:0]\n:VK8S-NETPOL-GATE - [0:0]\n-A FORWARD -j VK8S-NETPOL-GATE\nCOMMIT\n") ==
    "*mangle\n-D FORWARD -j VK8S-NETPOL-GATE\n-F VK8S-NETPOL-GATE\n-X VK8S-NETPOL-GATE\nCOMMIT\n" : String}

# kube-router's ipsets by exact name: KUBE-SRC- or KUBE-DST- and 16
# base32 characters, and kube-router-local-pods; other sets, and other
# KUBE-SRC- names, stay.
law netpol.ipset_destroy_v2:
  {NP.Netpol.ipset_destroy.v2(False{}, "KUBE-SRC-ABCDEFGHIJKLMNOP\nKUBE-SRC-ABCDEF\ndocker-set\nkube-router-local-pods\nKUBE-DST-2345672345672345\n") ==
    [["sudo", "ipset", "destroy", "KUBE-SRC-ABCDEFGHIJKLMNOP"], ["sudo", "ipset", "destroy", "kube-router-local-pods"],
      ["sudo", "ipset", "destroy", "KUBE-DST-2345672345672345"]] : List<&2, List<&2, String>>}

law netpol.ipset_destroy_v2_shared:
  {NP.Netpol.ipset_destroy.v2(True{}, "KUBE-SRC-ABCDEFGHIJKLMNOP\nkube-router-local-pods\n") == [] : List<&2, List<&2, String>>}

# Native mode v2 without the host node: NH.NHost.boot's plan.
law netpol.native_v2_no_node:
  for e: N.Env
  for o: NH.Opts
  for c: P.Cfg
  for h: {NH.NHost.node(o) == False{} : Bool}
  {NP.Netpol.native_boot.v2(e, o, c) == NH.NHost.boot(e, o, c) : +List<P.Step>}
