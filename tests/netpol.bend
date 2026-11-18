import Base
import ../src/guest/plan.bend as P
import ../src/guest/netpol.bend as NP
import ../src/guest/container.bend as C
import ../src/guest/container_host.bend as CH
import ../src/standalone/native_host.bend as NH
import ../src/standalone/native.bend as N

# Tests for src/guest/netpol.bend on whole boot plans: in each mode (a VM,
# a node container, a native host node) the gate closes before the
# kubelet starts and kube-router starts right after it, with the kubelet's
# own kubeconfig and node name; a control plane grants the RBAC, a worker
# does not; plans without a kubelet (the image cache, classic mode, a
# native control plane alone) do not change.

def T.check(+name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name)

def T.step(s: P.Step) -> String:
  match s:
    case P.Mount{fs, src, dst, opts}:
      "mount " ++ fs ++ " " ++ src ++ " " ++ dst
    case P.Write{path, text}:
      "write " ++ path
    case P.Run{prog, args}:
      "run " ++ prog ++ " " ++ String.join(args, " ")
    case P.Daemon{n, prog, args}:
      "daemon " ++ n ++ " " ++ prog ++ " " ++ String.join(args, " ")
    case P.Spawn{n, prog, args}:
      "spawn " ++ n
    case P.WaitTcp{host, port, ms}:
      "waittcp " ++ host ++ ":" ++ U32.show(port)
    case P.Stop{names}:
      "stop " ++ String.join(names, " ")
    case P.WaitFile{path, ms}:
      "waitfile " ++ path
    case P.Modules{path}:
      "modules " ++ path
    case P.Log{t}:
      "log " ++ t

def T.lines(ss: +List<P.Step>) -> +List<String>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      Con{T.step(s), T.lines(t)}

# The index of the first line that starts with p (the length when none).
def T.at.go(hit: Bool, +rest: Nat) -> Nat:
  match hit:
    case True{}:
      0n
    case False{}:
      1n+rest

def T.at(ls: +List<String>, +p: String) -> Nat:
  match ls:
    case Nil{}:
      0n
    case Con{+l, t}:
      T.at.go(String.starts_with(l, p), T.at(t, p))

def T.count.one(hit: Bool) -> Nat:
  match hit:
    case True{}:
      1n
    case False{}:
      0n

def T.count(ls: +List<String>, +p: String) -> Nat:
  match ls:
    case Nil{}:
      0n
    case Con{+l, t}:
      Nat.add(T.count.one(String.starts_with(l, p)), T.count(t, p))

def T.has(+ls: +List<String>, +p: String) -> Bool:
  Nat.is_lt(T.at(ls, p), List.length(&2, String, ls))

# gate, then kubelet, then kube-router, each once
def T.ordered(+ls: +List<String>) -> Bool:
  +g = T.at(ls, "run /usr/sbin/iptables-restore -w --noflush ")
  +k = T.at(ls, "daemon kubelet ")
  +r = T.at(ls, "daemon kube-router ")
  Nat.is_lt(g, k) && Nat.is_eq(Nat.add(k, 1n), r) && Nat.is_lt(r, List.length(&2, String, ls))
    && Nat.is_eq(T.count(ls, "daemon kube-router "), 1n)

# native v2: the stale-rule clean runs once, right after the node's
# reset, and before the gate closes
def T.cleaned(+ls: +List<String>) -> Bool:
  +r = T.at(ls, "run /var/lib/vk8s/demo/busybox sh -c k=/sys/fs/cgroup/kubepods")
  +x = T.at(ls, "run /var/lib/vk8s/demo/busybox sh -c i=/usr/sbin/iptables; ")
  +g = T.at(ls, "run /usr/sbin/iptables-restore -w --noflush ")
  Nat.is_eq(Nat.add(r, 1n), x) && Nat.is_lt(x, g)
    && Nat.is_eq(T.count(ls, "run /var/lib/vk8s/demo/busybox sh -c i=/usr/sbin/iptables; "), 1n)

def T.kr.pick(hit: Bool, +l: String, +rest: String) -> String:
  match hit:
    case True{}:
      l
    case False{}:
      rest

def T.kr.go(ls: +List<String>) -> String:
  match ls:
    case Nil{}:
      ""
    case Con{+l, t}:
      T.kr.pick(String.starts_with(l, "daemon kube-router "), l, T.kr.go(t))

def T.kr(+ls: +List<String>) -> String:
  T.kr.go(ls)

def T.cfg() -> P.Cfg:
  P.Plan.default_cfg("vk8s", 6443, False{})

def T.env() -> N.Env:
  N.Native.env_of("/var/lib/vk8s/demo", "", "/home/u/.vk8s/clusters/demo/share", "", "", "")

def T.opts(node: Bool) -> NH.Opts:
  NH.Opts{11000, node, "amd64", "/run/systemd/resolve/resolv.conf"}

def main() -> IO(Unit):
  do IO<Unit>:
    # a VM: the standalone control plane and a worker
    +cp : +List<String> = T.lines(NP.Netpol.with_cfg(True{}, T.cfg(), P.Plan.boot(T.cfg())))
    T.check("vm cp: gate, kubelet, kube-router in order", T.ordered(cp))
    T.check("vm cp: kube-router uses the kubelet's kubeconfig", String.contains(T.kr(cp), "--kubeconfig=/var/lib/vcluster/pki/kubelet.conf"))
    T.check("vm cp: kube-router's node is the kubelet's", String.contains(T.kr(cp), "--hostname-override=vk8s "))
    T.check("vm cp: the service CIDR", String.contains(T.kr(cp), "--service-cluster-ip-range=10.96.0.0/12"))
    T.check("vm cp: the RBAC follows kube-router", T.has(cp, "run /bin/busybox sh -c set -o pipefail; '/var/lib/vcluster/bin/kubectl' --kubeconfig '/var/lib/vcluster/pki/super-admin.conf' 'create' 'clusterrolebinding' 'vk8s:network-policy'"))
    +wk : +List<String> = T.lines(NP.Netpol.with_cfg(False{}, T.cfg(), P.Plan.worker(P.WCfg{"vk8s-worker-1", "10.10.0.3", "abc.def"})))
    T.check("vm worker: gate, kubelet, kube-router in order", T.ordered(wk))
    T.check("vm worker: kube-router uses the joined kubelet's kubeconfig", String.contains(T.kr(wk), "--kubeconfig=/etc/kubernetes/kubelet.conf "))
    T.check("vm worker: no RBAC (no admin credentials there)", Bool.not(T.has(wk, "run /bin/busybox sh -c set -o pipefail; '/var/lib/vcluster/bin/kubectl' --kubeconfig '/var/lib/vcluster/pki/super-admin.conf' 'create' 'clusterrole' 'vk8s:network-policy'")))
    # node containers (Linux, and the macOS node host's)
    +ccp : +List<String> = T.lines(NP.Netpol.with_cfg(True{}, T.cfg(), CH.Container.adapt(True{}, C.Plan.boot_container(CH.Container.cfg(True{}, "10.10.1.2", T.cfg())))))
    T.check("container cp: gate, kubelet, kube-router in order", T.ordered(ccp))
    +cwk : +List<String> = T.lines(NP.Netpol.with_cfg(False{}, T.cfg(), CH.Container.adapt(True{}, CH.Container.worker(P.WCfg{"c-worker-1", "10.10.1.3", "abc.def"}))))
    T.check("container worker: gate, kubelet, kube-router in order", T.ordered(cwk))
    T.check("container worker: kube-router's node", String.contains(T.kr(cwk), "--hostname-override=c-worker-1 "))
    # a native host node: relocated with the kubelet
    +nat : +List<String> = T.lines(NP.Netpol.native_boot(T.env(), T.opts(True{}), NH.NHost.cfg("demo", "10.1.0.4", 11000, False{})))
    T.check("native: gate, kubelet, kube-router in order", T.ordered(nat))
    T.check("native: kube-router from the data dir's bin", String.starts_with(T.kr(nat), "daemon kube-router /var/lib/vk8s/demo/bin/kube-router "))
    T.check("native: kube-router uses the relocated kubelet kubeconfig", String.contains(T.kr(nat), "--kubeconfig=/var/lib/vk8s/demo/pki/kubelet.conf "))
    T.check("native: the gate's files under the data dir", T.has(nat, "write /var/lib/vk8s/demo/netpol/gate.rules"))
    T.check("native: no VM path left in kube-router's line", Bool.not(String.contains(T.kr(nat), "/var/lib/vcluster")))
    T.check("native: the RBAC", T.has(nat, "run /var/lib/vk8s/demo/busybox sh -c set -o pipefail; '/var/lib/vk8s/demo/bin/kubectl' --kubeconfig '/var/lib/vk8s/demo/pki/super-admin.conf' 'create' 'clusterrole' 'vk8s:network-policy'"))
    +nn : +List<String> = T.lines(NP.Netpol.native_boot(T.env(), T.opts(False{}), NH.NHost.cfg("demo", "10.1.0.4", 11000, False{})))
    T.check("native without the host node: no kube-router", Bool.not(T.has(nn, "daemon kube-router ")))
    # native v2 (review F8): stale rules cleaned before the gate closes
    +nv2 : +List<String> = T.lines(NP.Netpol.native_boot.v2(T.env(), T.opts(True{}), NH.NHost.cfg("demo", "10.1.0.4", 11000, False{})))
    T.check("native v2: gate, kubelet, kube-router in order", T.ordered(nv2))
    T.check("native v2: the stale rules are cleaned after the reset, before the gate closes", T.cleaned(nv2))
    T.check("native v2: one step more than v1", Nat.is_eq(List.length(&2, String, nv2), Nat.add(List.length(&2, String, nat), 1n)))
    +nn2 : +List<String> = T.lines(NP.Netpol.native_boot.v2(T.env(), T.opts(False{}), NH.NHost.cfg("demo", "10.1.0.4", 11000, False{})))
    T.check("native v2 without the host node: no clean, no kube-router", Bool.not(T.has(nn2, "daemon kube-router ")) && Nat.is_eq(List.length(&2, String, nn2), List.length(&2, String, nn)))
    # plans without a kubelet stay as they are
    T.check("the image cache's plan is unchanged",
      Nat.is_eq(List.length(&2, P.Step, NP.Netpol.with(True{}, "10.244.0.0/16", "10.96.0.0/12", P.Plan.cache())), List.length(&2, P.Step, P.Plan.cache())))
    T.check("classic mode's plan is unchanged",
      Nat.is_eq(List.length(&2, P.Step, NP.Netpol.with(True{}, "10.244.0.0/16", "10.96.0.0/12", P.Plan.classic(T.cfg(), "/h", "ns"))),
        List.length(&2, P.Step, P.Plan.classic(T.cfg(), "/h", "ns"))))
    # certificate rotation restarts kube-router with the kubelet
    T.check("certs rotate stops kube-router too", T.has(T.lines(NP.Netpol.restarts(P.Plan.certs_rotate(T.cfg()))), "stop kubelet kube-scheduler kube-controller-manager kube-apiserver etcd kube-router"))
    T.check("certs rotate-ca stops kube-router too", T.has(T.lines(NP.Netpol.restarts(P.Plan.certs_rotate_ca(T.cfg()))), "stop kubelet kube-scheduler kube-controller-manager kube-apiserver etcd kube-router"))
