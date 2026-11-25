import Base
import bend-kube-runtime@0.11.0.0/src/json.bend as J
import ../guest/plan.bend as P
import ../guest/container.bend as C
import ./cli.bend as CL
import ../layers/ask.bend as LA

import ./assets.bend as A

# The host side of container mode (`vk8s create --backend container`,
# docs/ref/explore-linux-hosts.md Phase 6 C2), pure: every name, address,
# argument list and message the host executor (host/vk8s.bend, Vk8s.ctr.*)
# uses. The executor runs each argv list as it is, with no shell.
#
# A cluster takes a slot k (1..250) on the host:
# - its LAN 10.10.k.0/24 on a Linux bridge vk8sbr<k> whose address,
#   10.10.k.1, is the nodes' default route (D10 a);
# - node i (0: the control plane, i: worker i) at 10.10.k.(2+i), in the
#   named network namespace vk8s-<cluster>-<i>, linked to the bridge by a
#   veth pair (host side vk8s<k>n<i>; the peer becomes eth0);
# - the runc container vk8s-<cluster>-<i> (D9 a), whose config.json is
#   C.Container.config with the network namespace at that path;
# - MASQUERADE for the LAN and FORWARD accepts for the bridge, every rule
#   tagged with the comment vk8s:<cluster>, so delete finds them all.
# In a VM the LAN is bend-vmm's and private to the cluster, so every VM
# cluster uses 10.10.0.0/24 (CL.Cli.lan_ip); on one host kernel the
# clusters need distinct subnets, hence the slots.

# --- Slots and names

def Ctr.prefix(+k: U32) -> String:
  "10.10." ++ U32.show(k) ++ "."

def Ctr.subnet(+k: U32) -> String:
  Ctr.prefix(k) ++ "0/24"

def Ctr.gateway(+k: U32) -> String:
  Ctr.prefix(k) ++ "1"

def Ctr.node_ip(+k: U32, +i: U32) -> String:
  Ctr.prefix(k) ++ U32.show((i + 2 : U32))

# Interface names (at most 15 bytes, IFNAMSIZ - 1).
def Ctr.bridge(+k: U32) -> String:
  "vk8sbr" ++ U32.show(k)

def Ctr.veth(+k: U32, +i: U32) -> String:
  "vk8s" ++ U32.show(k) ++ "n" ++ U32.show(i)

def Ctr.peer(+k: U32, +i: U32) -> String:
  "vk8s" ++ U32.show(k) ++ "p" ++ U32.show(i)

def Ctr.netns(+cluster: String, +i: U32) -> String:
  "vk8s-" ++ cluster ++ "-" ++ U32.show(i)

# Where `ip netns add` puts a named network namespace.
def Ctr.netns_path(+cluster: String, +i: U32) -> String:
  "/run/netns/" ++ Ctr.netns(cluster, i)

# The runc container of node i.
def Ctr.id(+cluster: String, +i: U32) -> String:
  Ctr.netns(cluster, i)

# runc's state directory for every vk8s container (runc --root).
def Ctr.runc_root() -> String:
  "/run/vk8s/runc"

# The comment on every host rule of a cluster.
def Ctr.tag(+cluster: String) -> String:
  "vk8s:" ++ cluster

def Ctr.pick(cp: Bool, +a: String, +b: String) -> String:
  match cp:
    case True{}:
      a
    case False{}:
      b

# The node's name: the cluster's for the control plane, as in a VM.
def Ctr.node(+cluster: String, +i: U32) -> String:
  Ctr.pick(U32.is_eq(i, 0), cluster, CL.Cli.worker_name(cluster, i))

# The node's directory: the cluster's for the control plane (its share and
# kubeconfig where the VM backend keeps them), nodes/worker-<i> otherwise.
def Ctr.node_dir(+dir: String, +i: U32) -> String:
  Ctr.pick(U32.is_eq(i, 0), dir, CL.Cli.node_dir(dir, i))

def Ctr.has(xs: List<&2, U32>, +k: U32) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{x, t}:
      U32.is_eq(x, k) || Ctr.has(t, k)

def Ctr.slot.pick(taken: Bool, +k: U32, next: U32) -> U32:
  match taken:
    case True{}:
      next
    case False{}:
      k

def Ctr.slot.go(n: Nat, +k: U32, +used: List<&2, U32>) -> U32:
  match n:
    case 0n:
      0
    case 1n+p:
      Ctr.slot.pick(Ctr.has(used, k), k, Ctr.slot.go(p, (k + 1 : U32), used))

# The lowest slot (1..250) no cluster holds; 0 when every slot is taken.
def Ctr.slot(+used: List<&2, U32>) -> U32:
  Ctr.slot.go(250n, 1, used)

def Ctr.slots.add(hit: Bool, +l: String, rest: List<&2, U32>) -> List<&2, U32>:
  match hit:
    case True{}:
      CL.Cli.workers.keep(U32.read(String.trim(String.drop(l, 5n))), rest)
    case False{}:
      rest

def Ctr.slots.lines(ls: List<&2, String>) -> List<&2, U32>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{+l, t}:
      Ctr.slots.add(String.starts_with(l, "SLOT="), l, Ctr.slots.lines(t))

# The slots held, from the SLOT= lines of every cluster.env.
def Ctr.slots(text: String) -> List<&2, U32>:
  Ctr.slots.lines(String.lines(text))

def Ctr.setting.pick(hit: Bool, +l: String, +n: Nat, more: String) -> String:
  match hit:
    case True{}:
      String.drop(l, n)
    case False{}:
      more

def Ctr.setting.lines(ls: List<&2, String>, +key: String) -> String:
  match ls:
    case Nil{}:
      ""
    case Con{+l, t}:
      Ctr.setting.pick(String.starts_with(l, key ++ "="), l, Nat.add(String.length(key), 1n), Ctr.setting.lines(t, key))

# KEY's value in a cluster.env text ("" when absent).
def Ctr.setting(text: String, +key: String) -> String:
  String.trim(Ctr.setting.lines(String.lines(text), key))

# --- The host network (argument lists for ip(8) and iptables(8))

# The cluster's bridge, with the nodes' gateway address.
def Ctr.ip_bridge(+k: U32) -> +List<+List<String>>:
  +br = Ctr.bridge(k)
  [ ["link", "add", br, "type", "bridge"],
    ["addr", "add", Ctr.gateway(k) ++ "/24", "dev", br],
    ["link", "set", br, "up"] ]

# Node i's network namespace: a veth pair, the host side on the bridge,
# the peer moved into the namespace as eth0 with the node's address and
# the default route through the bridge.
def Ctr.ip_node(+cluster: String, +k: U32, +i: U32) -> +List<+List<String>>:
  +ns = Ctr.netns(cluster, i)
  +veth = Ctr.veth(k, i)
  +peer = Ctr.peer(k, i)
  [ ["netns", "add", ns],
    ["link", "add", veth, "type", "veth", "peer", "name", peer],
    ["link", "set", peer, "netns", ns],
    ["link", "set", veth, "master", Ctr.bridge(k)],
    ["link", "set", veth, "up"],
    ["-n", ns, "link", "set", peer, "name", "eth0"],
    ["-n", ns, "addr", "add", Ctr.node_ip(k, i) ++ "/24", "dev", "eth0"],
    ["-n", ns, "link", "set", "eth0", "up"],
    ["-n", ns, "link", "set", "lo", "up"],
    ["-n", ns, "route", "add", "default", "via", Ctr.gateway(k)] ]

# Deleting a namespace deletes the veth pair with it.
def Ctr.ip_node_del(+cluster: String, +i: U32) -> +List<String>:
  ["netns", "del", Ctr.netns(cluster, i)]

def Ctr.ip_bridge_del(+k: U32) -> +List<String>:
  ["link", "del", Ctr.bridge(k)]

# The cluster's host rules: its LAN masqueraded when it leaves through
# another interface, and the bridge's traffic accepted in FORWARD ahead of
# any DROP policy (Docker sets one), each tagged with Ctr.tag.
def Ctr.rules(+cluster: String, +k: U32) -> +List<+List<String>>:
  +tag = Ctr.tag(cluster)
  +br = Ctr.bridge(k)
  [ ["-t", "nat", "-A", "POSTROUTING", "-s", Ctr.subnet(k), "!", "-o", br, "-m", "comment", "--comment", tag, "-j", "MASQUERADE"],
    ["-t", "filter", "-I", "FORWARD", "-i", br, "-m", "comment", "--comment", tag, "-j", "ACCEPT"],
    ["-t", "filter", "-I", "FORWARD", "-o", br, "-m", "comment", "--comment", tag, "-j", "ACCEPT"] ]

# The tables Ctr.rules writes to, which delete lists (iptables -t T -S).
def Ctr.tables() -> +List<String>:
  ["nat", "filter"]

def Ctr.unq.go(q: Bool, +s: String) -> String:
  match q:
    case True{}:
      String.take(String.drop(s, 1n), Nat.sub(String.length(s), 2n))
    case False{}:
      s

# A word of `iptables -S` without the double quotes iptables puts around
# a comment that needs them.
def Ctr.unq(+s: String) -> String:
  Ctr.unq.go(Nat.is_ge(String.length(s), 2n) && String.starts_with(s, "\"") && String.ends_with(s, "\""), s)

def Ctr.unqs(ts: +List<String>) -> +List<String>:
  match ts:
    case Nil{}:
      Nil{}
    case Con{t, rest}:
      Con{Ctr.unq(t), Ctr.unqs(rest)}

def Ctr.first_is(ts: +List<String>, +w: String) -> Bool:
  match ts:
    case Nil{}:
      False{}
    case Con{x, t}:
      String.eq(x, w)

def Ctr.tagged.at(hit: Bool, ts: +List<String>, +tag: String) -> Bool:
  match hit:
    case True{}:
      Ctr.first_is(ts, tag)
    case False{}:
      False{}

# Whether the words hold `--comment TAG`.
def Ctr.tagged(ts: +List<String>, +tag: String) -> Bool:
  match ts:
    case Nil{}:
      False{}
    case Con{+x, +t}:
      Ctr.tagged.at(String.eq(x, "--comment"), t, tag) || Ctr.tagged(t, tag)

def Ctr.undo.line(hit: Bool, +table: String, ts: +List<String>, rest: +List<+List<String>>) -> +List<+List<String>>:
  match hit:
    case True{}:
      Con{List.append(&2, String, ["-t", table, "-D"], List.drop(&2, String, ts, 1n)), rest}
    case False{}:
      rest

def Ctr.undo.lines(ls: List<&2, String>, +table: String, +tag: String) -> +List<+List<String>>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{+l, t}:
      +ts = Ctr.unqs(String.split(l, ' '))
      Ctr.undo.line(String.starts_with(l, "-A ") && Ctr.tagged(ts, tag), table, ts, Ctr.undo.lines(t, table, tag))

# The iptables argument lists that delete every rule of `iptables -t
# TABLE -S` (text) tagged TAG: "-A CHAIN SPEC" becomes "-t TABLE -D CHAIN
# SPEC". Rules of other clusters and untagged rules stay.
def Ctr.undo(+table: String, +tag: String, text: String) -> +List<+List<String>>:
  Ctr.undo.lines(String.lines(text), table, tag)

# --- Host cgroup delegation

# The host cgroups above a node's (C.Container.cgroup_path: /vk8s/<cluster>/
# <node>), from the root down; each enables its controllers for its
# children, so the node's cgroup has every controller the host has.
def Ctr.cgroup_dirs(+cluster: String) -> +List<String>:
  ["/sys/fs/cgroup", "/sys/fs/cgroup/vk8s", "/sys/fs/cgroup/vk8s/" ++ cluster]

def Ctr.enables.add(empty: Bool, +w: String, rest: +List<String>) -> +List<String>:
  match empty:
    case True{}:
      rest
    case False{}:
      Con{"+" ++ w, rest}

def Ctr.enables.go(ws: List<&2, String>) -> +List<String>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{+w, t}:
      Ctr.enables.add(String.is_empty(w), w, Ctr.enables.go(t))

# What a cgroup writes to cgroup.subtree_control, one controller at a
# time, for the controllers its cgroup.controllers lists.
def Ctr.enables(text: String) -> +List<String>:
  Ctr.enables.go(String.split(String.trim(text), ' '))

# --- Preflight

# The host tools the executor runs.
def Ctr.tools() -> +List<String>:
  ["runc", "ip", "iptables", "modprobe", "mount", "umount", "cpio"]

# The kernel modules the nodes need from the host kernel: overlay, bridge
# and br_netfilter as vcluster's docker driver loads them
# (pkg/cli/docker_runtime.go:162-182), veth and vxlan for the nodes' links
# and flannel, nf_tables and nf_conntrack for kube-proxy and the
# MASQUERADE rules.
def Ctr.modules() -> +List<String>:
  ["overlay", "bridge", "br_netfilter", "veth", "vxlan", "nf_tables", "nf_conntrack"]

# Ctr.modules and af_packet: gVisor's sandbox network opens an AF_PACKET
# raw socket on the pod's veth (gVisor runsc/sandbox/network.go,
# createSocket), for pods of the opt-in `gvisor` RuntimeClass
# (docs/GOAL.md section 8). A VM node loads it from
# scripts/guest/modules.txt; a node container shares the host's kernel,
# so the host loads it. modprobe succeeds for a built-in module too.
def Ctr.modules.v2() -> +List<String>:
  List.append(&2, String, Ctr.modules(), ["af_packet"])

# The cgroup v2 controllers kubelet needs in the node's cgroup.
def Ctr.controllers() -> +List<String>:
  ["cpu", "memory", "pids"]

def Ctr.lacks.add(have: Bool, +n: String, rest: +List<String>) -> +List<String>:
  match have:
    case True{}:
      rest
    case False{}:
      Con{n, rest}

def Ctr.member(xs: +List<String>, +x: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{y, t}:
      String.eq(y, x) || Ctr.member(t, x)

# The names of need that have does not hold, in need's order.
def Ctr.lacks(+have: +List<String>, need: +List<String>) -> +List<String>:
  match need:
    case Nil{}:
      Nil{}
    case Con{+n, t}:
      Ctr.lacks.add(Ctr.member(have, n), n, Ctr.lacks(have, t))

# The controllers of Ctr.controllers that a cgroup.controllers text lacks.
def Ctr.missing_controllers(text: String) -> +List<String>:
  Ctr.lacks(String.split(String.trim(text), ' '), Ctr.controllers())

def Ctr.root.uid(ws: List<&2, String>) -> Bool:
  match ws:
    case Con{tag, Con{real, Con{eff, rest}}}:
      String.eq(String.trim(eff), "0")
    case _:
      False{}

def Ctr.root.pick(hit: Bool, +l: String, more: Bool) -> Bool:
  match hit:
    case True{}:
      Ctr.root.uid(String.split(l, '\t'))
    case False{}:
      more

def Ctr.root.lines(ls: List<&2, String>) -> Bool:
  match ls:
    case Nil{}:
      False{}
    case Con{+l, t}:
      Ctr.root.pick(String.starts_with(l, "Uid:"), l, Ctr.root.lines(t))

# Whether /proc/self/status (text) is a process with effective UID 0.
def Ctr.root(text: String) -> Bool:
  Ctr.root.lines(String.lines(text))

def Ctr.when(ok: Bool, +s: String) -> String:
  match ok:
    case True{}:
      s
    case False{}:
      ""

def Ctr.some(+xs: +List<String>) -> Bool:
  Bool.not(List.is_empty(&2, String, xs))

# What stops a container create before it changes the host ("" when
# nothing does): not root, missing tools, kernel modules that do not load,
# no cgroup v2 at /sys/fs/cgroup or missing controllers there. Each line
# says what to do.
def Ctr.preflight_message(root: Bool, +cgroup2: Bool, +tools: +List<String>, +mods: +List<String>, +ctrls: +List<String>) -> String:
  Ctr.when(Bool.not(root), "vk8s: --backend container needs root (run it with sudo)\n")
  ++ Ctr.when(Ctr.some(tools), "vk8s: missing on this host: " ++ String.join(tools, ", ") ++ "\n")
  ++ Ctr.when(Ctr.some(mods), "vk8s: kernel modules that do not load: " ++ String.join(mods, ", ") ++ " (modprobe " ++ String.join(mods, " ") ++ ")\n")
  ++ Ctr.when(Bool.not(cgroup2), "vk8s: cgroup v2 is not mounted at /sys/fs/cgroup (boot with systemd.unified_cgroup_hierarchy=1)\n")
  ++ Ctr.when(cgroup2 && Ctr.some(ctrls), "vk8s: cgroup v2 controllers missing at /sys/fs/cgroup: " ++ String.join(ctrls, ", ") ++ "\n")

# --- DNS

def Ctr.resolv.keep(+l: String) -> Bool:
  String.starts_with(l, "nameserver ") && Bool.not(String.starts_with(String.trim(String.drop(l, 11n)), "127."))
    && Bool.not(String.eq(String.trim(String.drop(l, 11n)), "::1"))

def Ctr.resolv.add(keep: Bool, +l: String, rest: String) -> String:
  match keep:
    case True{}:
      String.trim(l) ++ "\n" ++ rest
    case False{}:
      rest

def Ctr.resolv.lines(ls: List<&2, String>) -> String:
  match ls:
    case Nil{}:
      ""
    case Con{+l, t}:
      Ctr.resolv.add(Ctr.resolv.keep(l), l, Ctr.resolv.lines(t))

# A resolv.conf's nameservers that a node can reach: a loopback resolver
# (systemd-resolved's 127.0.0.53) is the host's, not the node's.
def Ctr.nameservers(text: String) -> String:
  Ctr.resolv.lines(String.lines(text))

def Ctr.resolv.or(empty: Bool, +s: String, next: String) -> String:
  match empty:
    case True{}:
      next
    case False{}:
      s

# The nodes' /etc/resolv.conf: the upstream servers of systemd-resolved
# (/run/systemd/resolve/resolv.conf, text a), else the host's
# /etc/resolv.conf (text b) without loopback servers, else public ones.
def Ctr.resolv(a: String, b: String) -> String:
  +x = Ctr.nameservers(a)
  +y = Ctr.nameservers(b)
  Ctr.resolv.or(String.is_empty(x), x, Ctr.resolv.or(String.is_empty(y), y, "nameserver 1.1.1.1\nnameserver 8.8.8.8\n"))

# --- The node containers

# PID 1's environment, which the kernel command line carries in a VM
# (CL.Cli.vmm_flags_x, CL.Cli.worker_flags), with stage 0's PATH and
# VK8S_BACKEND=container; the node's address is its eth0's.
def Ctr.env_cp(+cluster: String, +k: U32, +port: U32, etcd: Bool) -> +List<String>:
  [ "PATH=" ++ P.Plan.path(), "VK8S_BACKEND=container", "VK8S_NAME=" ++ cluster, "VK8S_PORT=" ++ U32.show(port),
    "VK8S_STORE=" ++ CL.Cli.store_name(etcd), "VK8S_NODE_IP=" ++ Ctr.node_ip(k, 0) ]

def Ctr.env_worker(+cluster: String, +k: U32, +i: U32, +token: String) -> +List<String>:
  [ "PATH=" ++ P.Plan.path(), "VK8S_BACKEND=container", "VK8S_ROLE=worker", "VK8S_NAME=" ++ CL.Cli.worker_name(cluster, i),
    "VK8S_NODE_IP=" ++ Ctr.node_ip(k, i), "VK8S_TOKEN=" ++ token ]

def Ctr.arch_env.go(amd64: Bool, env: +List<String>) -> +List<String>:
  match amd64:
    case True{}:
      List.append(&2, String, env, ["VK8S_ARCH=amd64"])
    case False{}:
      env

# PID 1's environment on this host's arch: VK8S_ARCH=amd64 on amd64, as
# the VM's kernel command line ends (CL.Cli.arch_flags), which PID 1 reads
# for its image import platform (P.Plan.arch_args); arm64 names none.
def Ctr.arch_env(+arch: String, env: +List<String>) -> +List<String>:
  Ctr.arch_env.go(String.eq(arch, "amd64"), env)

def Ctr.ns_at(+t: String, +path: String) -> J.Json:
  J.Json.obj([J.KV{"type", J.JStr{t}}, J.KV{"path", J.JStr{path}}])

# C.Container.linux with the network namespace the host made (runc joins
# a namespace given by path instead of making one).
def Ctr.linux(+cluster: String, +node: String, +netns: String) -> J.Json:
  J.Json.obj([
    J.KV{"namespaces", J.Json.arr([C.Container.ns("pid"), C.Container.ns("ipc"), C.Container.ns("uts"), C.Container.ns("mount"),
      Ctr.ns_at("network", netns), C.Container.ns("cgroup")])},
    J.KV{"cgroupsPath", J.JStr{C.Container.cgroup_path(cluster, node)}},
    J.KV{"resources", J.Json.obj([J.KV{"devices", J.Json.arr([J.Json.obj([J.KV{"allow", J.JBool{True{}}}, J.KV{"access", J.JStr{"rwm"}}])])}])}])

# A node's config.json: C.Container.config with Ctr.linux.
def Ctr.config(s: C.Spec, +netns: String) -> J.Json:
  match s:
    case C.Spec{+cluster, +node, rootfs, data, share, +assets, env}:
      J.Json.obj([
        J.KV{"ociVersion", J.JStr{C.Container.version()}},
        J.KV{"process", C.Container.process(env)},
        J.KV{"root", J.Json.obj([J.KV{"path", J.JStr{rootfs}}, J.KV{"readonly", J.JBool{False{}}}])},
        J.KV{"hostname", J.JStr{node}},
        J.KV{"mounts", J.Json.arr(C.Container.mounts(data, share, assets))},
        J.KV{"linux", Ctr.linux(cluster, node, netns)}])

def Ctr.json(s: C.Spec, +netns: String) -> String:
  J.Json.show(Ctr.config(s, netns))

# The node's root filesystem: the initramfs (vk8s.cpio) unpacked, as stage 0
# copies it into its tmpfs; GNU cpio, which makes /dev/console as root.
def Ctr.unpack(+cpio: String, +rootfs: String) -> +List<String>:
  ["-idmu", "--quiet", "--no-absolute-filenames", "-D", rootfs, "-F", cpio]

# The assets image's squashfs, read-only through a loop device, where the
# nodes bind it (/assets and the data dir's bin/).
def Ctr.mount_assets(+img: String, +mnt: String) -> +List<String>:
  ["-t", "squashfs", "-o", "loop,ro", img, mnt]

# Per-role assets (docs/ref/footprint-decisions.md D1): base.img (the
# guest root under guest/) and one squashfs disk per set (the Kubernetes
# binaries). The host mounts base.img at <dir>/base, each set at
# <dir>/sets/<set>, and joins them in a read-only overlay at
# <dir>/assets: the layout of the single assets.img, which the nodes
# bind as before. Every node of a cluster shares the one mount, so it
# holds the control plane's sets: node and control-plane, and images
# when the build made it (the add-on tars; else containerd pulls them).
def Ctr.sets(images: Bool) -> +List<String>:
  match images:
    case True{}:
      ["node", "control-plane", "images"]
    case False{}:
      ["node", "control-plane"]

def Ctr.base_dir(+dir: String) -> String:
  dir ++ "/base"

def Ctr.set_dir(+dir: String, +s: String) -> String:
  dir ++ "/sets/" ++ s

# The overlay's lower directories, top first: the sets, then the base.
def Ctr.lowers(+dir: String, sets: +List<String>) -> +List<String>:
  match sets:
    case Nil{}:
      [Ctr.base_dir(dir)]
    case Con{+s, t}:
      Con{Ctr.set_dir(dir, s), Ctr.lowers(dir, t)}

# An overlay of lower directories only is read-only.
def Ctr.mount_overlay(+lowers: +List<String>, +mnt: String) -> +List<String>:
  ["-t", "overlay", "-o", "ro,lowerdir=" ++ String.join(lowers, ":"), "overlay", mnt]

# What delete unmounts, in order: the overlay, every set, the base.
def Ctr.asset_mounts(+dir: String) -> +List<String>:
  Con{dir ++ "/assets", Ctr.lowers(dir, Ctr.sets(True{}))}

# runc's arguments, under vk8s's state directory.
def Ctr.runc(args: +List<String>) -> +List<String>:
  List.append(&2, String, ["--root", Ctr.runc_root()], args)

def Ctr.runc_run(+bundle: String, +id: String) -> +List<String>:
  Ctr.runc(["run", "-d", "--bundle", bundle, id])

def Ctr.status.value(+v: String) -> String:
  Ctr.unq(Ctr.pick(String.ends_with(v, ","), String.take(v, Nat.sub(String.length(v), 1n)), v))

def Ctr.status.pick(hit: Bool, +l: String, more: String) -> String:
  match hit:
    case True{}:
      Ctr.status.value(String.trim(String.drop(l, 9n)))
    case False{}:
      more

def Ctr.status.lines(ls: List<&2, String>) -> String:
  match ls:
    case Nil{}:
      "stopped"
    case Con{l, t}:
      +x = String.trim(l)
      Ctr.status.pick(String.starts_with(x, "\"status\":"), x, Ctr.status.lines(t))

# A container's status from `runc state` (runc's JSON, indented by two
# spaces: ociVersion, id, pid, status, ...): created, running, paused or
# stopped; stopped when runc knows no such container (no output).
def Ctr.status(text: String) -> String:
  Ctr.status.lines(String.lines(text))

# --- v2: per-host slots, bridge isolation, iptables -w and delete checks
# (docs/ref/review-bend-vk8s-pr-49.md findings 1-3). Ctr.slot, Ctr.rules
# and Ctr.undo stay for their laws; the executor uses these.

# The per-host slot registry. Bridges, veths and rules are per host, so
# the registry is too: under /run (root's, one per host kernel, gone with
# the bridges at a reboot), not under a $HOME. Slot k is held while
# Ctr.slot_owner(k) exists. Create makes that file with O_CREAT|O_EXCL
# (Base's File.open mode "x"), which fails when it exists, so two
# creates, from one home or two, never hold one slot. (The exit status of
# `mkdir` without -p is not a lock: on Ubuntu 26.04 two creates both got
# one slot.) The owner file names the cluster's directory, so delete
# takes down only its own.
def Ctr.slots_dir() -> String:
  "/run/vk8s/slots"

def Ctr.slot_dir(+k: U32) -> String:
  Ctr.slots_dir() ++ "/" ++ U32.show(k)

def Ctr.slot_owner(+k: U32) -> String:
  Ctr.slot_dir(k) ++ "/owner"

def Ctr.owner_text(+dir: String) -> String:
  dir ++ "\n"

# Whether an owner file's text names this cluster's directory.
def Ctr.owns(text: String, +dir: String) -> Bool:
  String.eq(String.trim(text), dir)

# mkdir's argument list for slot k's directory (Ctr.slot_owner is the lock).
def Ctr.reserve(+k: U32) -> +List<String>:
  [Ctr.slot_dir(k)]

# rm's argument list that frees slot k.
def Ctr.release(+k: U32) -> +List<String>:
  ["-rf", Ctr.slot_dir(k)]

# ip's argument list that succeeds when slot k's bridge exists.
def Ctr.bridge_show(+k: U32) -> +List<String>:
  ["link", "show", "dev", Ctr.bridge(k)]

def Ctr.free.add(taken: Bool, +k: U32, rest: List<&2, U32>) -> List<&2, U32>:
  match taken:
    case True{}:
      rest
    case False{}:
      Con{k, rest}

def Ctr.free.go(n: Nat, +k: U32, +used: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Ctr.free.add(Ctr.has(used, k), k, Ctr.free.go(p, (k + 1 : U32), used))

# The slots (1..250) create tries in order: every one no cluster.env of
# this home records (a cluster from before the registry holds none).
def Ctr.free(+used: List<&2, U32>) -> List<&2, U32>:
  Ctr.free.go(250n, 1, used)

def Ctr.no_slot_message() -> String:
  "every container network slot of this host is held (" ++ Ctr.slots_dir() ++ ", 250 at most)"

# Isolation: the bridge forwards within itself and to the uplink, never
# to or from another vk8s bridge (vk8sbr+, any cluster's, of any home).
# Each rule goes to the top of FORWARD, so the last is first: the
# bridge's own traffic (br_netfilter shows bridged frames to FORWARD),
# then the drops, then Ctr.rules' accepts below them. Another cluster's
# accepts can land between them, but each cluster's drops sit above its
# own accepts, so traffic between two bridges meets a drop first.
def Ctr.isolate(+cluster: String, +k: U32) -> +List<+List<String>>:
  +tag = Ctr.tag(cluster)
  +br = Ctr.bridge(k)
  [ ["-t", "filter", "-I", "FORWARD", "-i", "vk8sbr+", "-o", br, "-m", "comment", "--comment", tag, "-j", "DROP"],
    ["-t", "filter", "-I", "FORWARD", "-i", br, "-o", "vk8sbr+", "-m", "comment", "--comment", tag, "-j", "DROP"],
    ["-t", "filter", "-I", "FORWARD", "-i", br, "-o", br, "-m", "comment", "--comment", tag, "-j", "ACCEPT"] ]

# iptables waits up to 30 s for the xtables lock (iptables(8) -w)
# instead of exiting when Docker or firewalld holds it.
def Ctr.ipt(args: +List<String>) -> +List<String>:
  List.append(&2, String, ["-w", "30"], args)

def Ctr.ipts(cs: +List<+List<String>>) -> +List<+List<String>>:
  match cs:
    case Nil{}:
      Nil{}
    case Con{c, t}:
      Con{Ctr.ipt(c), Ctr.ipts(t)}

# The cluster's host rules: Ctr.rules, then Ctr.isolate, each with -w.
def Ctr.rules.v2(+cluster: String, +k: U32) -> +List<+List<String>>:
  Ctr.ipts(List.append(&2, List<&2, String>, Ctr.rules(cluster, k), Ctr.isolate(cluster, k)))

# iptables' argument list that lists TABLE's rules.
def Ctr.list_rules(+table: String) -> +List<String>:
  Ctr.ipt(["-t", table, "-S"])

# Ctr.undo with -w.
def Ctr.undo.v2(+table: String, +tag: String, text: String) -> +List<+List<String>>:
  Ctr.ipts(Ctr.undo(table, tag, text))

def Ctr.none(cs: +List<+List<String>>) -> Bool:
  match cs:
    case Nil{}:
      True{}
    case Con{c, t}:
      False{}

# Whether a listing of TABLE (text) holds no rule tagged TAG.
def Ctr.rules_gone(+table: String, +tag: String, text: String) -> Bool:
  Ctr.none(Ctr.undo(table, tag, text))

# What delete checks after it ran. runc keeps a container's state in
# <root>/<id> until `runc delete`.
def Ctr.state_dir(+id: String) -> String:
  Ctr.runc_root() ++ "/" ++ id

def Ctr.cgroup(+cluster: String) -> String:
  "/sys/fs/cgroup/vk8s/" ++ cluster

# Node i's leftovers before rest: its container and its network
# namespace when they are still there.
def Ctr.left_node(container: Bool, netns: Bool, +cluster: String, +i: U32, rest: +List<String>) -> +List<String>:
  Ctr.lacks.add(Bool.not(container), "container " ++ Ctr.id(cluster, i),
    Ctr.lacks.add(Bool.not(netns), "network namespace " ++ Ctr.netns(cluster, i), rest))

# A mount point that is still mounted, before rest.
def Ctr.left_mount(mounted: Bool, +m: String, rest: +List<String>) -> +List<String>:
  Ctr.lacks.add(Bool.not(mounted), "mount " ++ m, rest)

# Everything delete could not remove: the nodes' leftovers, the tagged
# rules, the bridge and the cgroup unless each is gone, then the mounts.
def Ctr.leftovers(+cluster: String, +k: U32, nodes: +List<String>, rules: Bool, bridge: Bool, cgroup: Bool, mounts: +List<String>) -> +List<String>:
  List.append(&2, String, nodes,
    Ctr.lacks.add(rules, "iptables rules tagged " ++ Ctr.tag(cluster),
      Ctr.lacks.add(bridge, "bridge " ++ Ctr.bridge(k),
        Ctr.lacks.add(cgroup, "cgroup " ++ Ctr.cgroup(cluster), mounts))))

# Delete stops with this when anything is left; the cluster.env (and
# with it SLOT=) stays, so a second delete finds the same slot.
def Ctr.delete_failed(+cluster: String, +dir: String, +left: +List<String>) -> String:
  "vk8s: could not remove from this host: " ++ String.join(left, ", ") ++ "; " ++ dir ++ "/cluster.env is kept, run vk8s delete "
    ++ cluster ++ " again"

# A bridge of the cluster's slot that the registry does not give to it
# (a cluster from an older vk8s, or another's) is left in place.
def Ctr.unowned_message(+k: U32) -> String:
  "warning: " ++ Ctr.bridge(k) ++ " is not recorded as this cluster's in " ++ Ctr.slot_owner(k) ++ ", so it stays (ip link del "
    ++ Ctr.bridge(k) ++ " removes it)"

# Whether create asks for the images set (docs/ref/review-bend-vk8s-pr-48.md
# finding 1): when the assets dir holds it, or when the dir is the
# pinned release's and the release pins it (then it is fetched).
def Ctr.want_images(present: Bool, release: Bool, pinned: Bool) -> Bool:
  present || (release && pinned)

# --- The shared layer store in node containers (docs/GOAL.md section 11,
# the container half; P.Plan.with_layers.v5). Opt-in: only the host's
# VK8S_LAYERS=1 turns it on for container nodes (VM nodes have it on by
# default, CL.Cli.layers_on.v2; containers keep their own unpack until
# measured). When on, each node container binds the host's store
# (Ctr.store) and /dev (C.Container.layers_mounts.v2), PID 1 gets
# VK8S_LAYERS=1 and the filler's address on the bridge
# (VK8S_LAYERS_ASK, the gateway: Ctr.layers_env), and the host forwards
# that address's filler port to the filler on its loopback
# (Ctr.layers_rules). Off, every value is the one before (Ctr.json.v2 is
# Ctr.json, Ctr.layers_env adds nothing, Ctr.layers_rules is empty).

def Ctr.layers_on(+env: String) -> Bool:
  String.eq(env, "1")

# The host's store directory under a home's ~/.vk8s (the VM share's,
# CL.Cli.layers_dir): its images are <store>/<hex>.sqfs.
def Ctr.store(+vk8s: String) -> String:
  CL.Cli.layers_dir(vk8s)

# The filler's port (src/layers/ask.bend Ask.port.v2; one per host).
def Ctr.filler_port() -> U32:
  LA.Ask.port.v2()

def Ctr.layers_env(on: Bool, +k: U32, env: +List<String>) -> +List<String>:
  match on:
    case True{}:
      List.append(&2, String, env, ["VK8S_LAYERS=1", "VK8S_LAYERS_ASK=" ++ Ctr.gateway(k)])
    case False{}:
      env

# A node's config.json, with the store's mounts when on.
def Ctr.config.v2(s: C.Spec, +netns: String, on: Bool, store: String) -> J.Json:
  match s:
    case C.Spec{+cluster, +node, rootfs, data, share, +assets, env}:
      J.Json.obj([
        J.KV{"ociVersion", J.JStr{C.Container.version()}},
        J.KV{"process", C.Container.process(env)},
        J.KV{"root", J.Json.obj([J.KV{"path", J.JStr{rootfs}}, J.KV{"readonly", J.JBool{False{}}}])},
        J.KV{"hostname", J.JStr{node}},
        J.KV{"mounts", J.Json.arr(C.Container.mounts.v2(data, share, assets, on, store))},
        J.KV{"linux", Ctr.linux(cluster, node, netns)}])

def Ctr.json.v2(s: C.Spec, +netns: String, on: Bool, store: String) -> String:
  J.Json.show(Ctr.config.v2(s, netns, on, store))

# The bridge's route_localnet, so that a packet to the gateway may be
# sent on to the host's loopback (ip-sysctl.txt, route_localnet). It
# goes with the bridge.
def Ctr.route_localnet(+k: U32) -> String:
  "/proc/sys/net/ipv4/conf/" ++ Ctr.bridge(k) ++ "/route_localnet"

# The host rules for the filler (iptables, each tagged, with -w): a
# connection from the bridge to the gateway's filler port goes to the
# filler on 127.0.0.1 (DNAT; the filler listens on the loopback only);
# such a connection is accepted ahead of any INPUT policy; and anything
# else from the bridge to 127.0.0.0/8 that was not translated is
# dropped, which route_localnet would let through otherwise (kube-proxy's
# fix for CVE-2020-8558, the same rule). None when off.
def Ctr.layers_rules(on: Bool, +cluster: String, +k: U32) -> +List<+List<String>>:
  match on:
    case True{}:
      +tag = Ctr.tag(cluster)
      +br = Ctr.bridge(k)
      +port = U32.show(Ctr.filler_port())
      Ctr.ipts([
        ["-t", "nat", "-A", "PREROUTING", "-i", br, "-d", Ctr.gateway(k) ++ "/32", "-p", "tcp", "--dport", port,
          "-m", "comment", "--comment", tag, "-j", "DNAT", "--to-destination", "127.0.0.1:" ++ port],
        ["-t", "filter", "-I", "INPUT", "-i", br, "-d", "127.0.0.0/8", "-m", "conntrack", "!", "--ctstate", "DNAT",
          "-m", "comment", "--comment", tag, "-j", "DROP"],
        ["-t", "filter", "-I", "INPUT", "-i", br, "-d", "127.0.0.1/32", "-p", "tcp", "--dport", port,
          "-m", "conntrack", "--ctstate", "DNAT", "-m", "comment", "--comment", tag, "-j", "ACCEPT"] ])
    case False{}:
      []

# The host's kernel modules for the store: loop devices and squashfs.
def Ctr.layers_modules() -> +List<String>:
  ["loop", "squashfs"]

# Optional sets on demand (docs/GOAL.md section 11): the cluster's one
# assets mount holds its control plane's sets (Ctr.sets), and etcd with the
# etcd backing store, gvisor with --gvisor (A.Assets.extra_sets of a
# standalone control plane, a node too). A node container finds runsc in
# bin/ only then, and PID 1 writes the runsc runtime and the gvisor
# RuntimeClass only then (P.Plan.gvisor_on, P.Plan.with_gvisor).
def Ctr.sets.v2(images: Bool, gvisor: Bool, etcd: Bool) -> +List<String>:
  A.Assets.add_sets(Ctr.sets(images), A.Assets.extra_sets(gvisor, etcd, "standalone"))

# What delete unmounts, v2: the overlay, every set a cluster may mount (an
# absent one is skipped), the base.
def Ctr.asset_mounts.v2(+dir: String) -> +List<String>:
  Con{dir ++ "/assets", Ctr.lowers(dir, Ctr.sets.v2(True{}, True{}, True{}))}

# delete: a node gets the grace vcluster gives a container it deletes
# (pkg/cli/delete_docker.go, stopContainer: `docker stop -t=1`, one
# second between the stop request and the kill), not a full stop: its
# data goes next.
def Ctr.delete_ms() -> U32:
  1000

# delete: how long the killed node's processes get to be gone (they go
# with the node's PID namespace) before its container, namespace and
# directory are removed.
def Ctr.kill_ms() -> U32:
  10000

# delete: ip's argument lists that delete the nodes' veth pairs by their
# bridge ends. A killed node's network namespace is freed only once its
# last process is gone, and the pair with it, a moment after delete
# returned: a create that reuses the slot then finds the names taken.
def Ctr.ip_veths_del(+k: U32, ws: List<&2, U32>) -> +List<+List<String>>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{+i, t}:
      Con{["link", "del", Ctr.veth(k, i)], Ctr.ip_veths_del(k, t)}

# The tries of a wait of ms milliseconds, each ms apart.
def Ctr.tries(ms: U32, each: U32) -> Nat:
  U32.to_nat((ms / each : U32))
