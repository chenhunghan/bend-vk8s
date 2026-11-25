import Base
import bend-kube-runtime@0.11.0.0/src/json.bend as J
import ../src/cli/ctr.bend as R
import ../src/guest/container.bend as C

# Spec for src/cli/ctr.bend: the host side of container mode
# (docs/ref/explore-linux-hosts.md Phase 6 C2; D9 a, D10 a).
#
# Proposed: every law in this file. Most values are vk8s's own choices
# (names, slots, addresses), not vcluster's: vcluster's docker driver asks
# Docker for a network and for containers, and vk8s makes them itself.
# The facts from outside are cited where they are used: iptables -S
# prints a rule as "-A CHAIN SPEC" and -D takes the same SPEC
# (iptables(8)); `runc state` prints the container's state as indented
# JSON with a "status" field (runc's state.go, json.MarshalIndent with
# two spaces); vcluster's docker driver loads overlay, bridge and
# br_netfilter (pkg/cli/docker_runtime.go:162-182).

def Laws.ctr.drop_text() -> String:
  "-P POSTROUTING ACCEPT\n"
  ++ "-A POSTROUTING -s 10.10.1.0/24 ! -o vk8sbr1 -m comment --comment vk8s:demo -j MASQUERADE\n"
  ++ "-A POSTROUTING -s 10.10.2.0/24 ! -o vk8sbr2 -m comment --comment vk8s:demo2 -j MASQUERADE\n"
  ++ "-A POSTROUTING -s 172.17.0.0/16 ! -o docker0 -j MASQUERADE\n"

# Proposed: slots, addresses and names.
law ctr.addresses:
  {[R.Ctr.subnet(3), R.Ctr.gateway(3), R.Ctr.node_ip(3, 0), R.Ctr.node_ip(3, 2)] ==
    ["10.10.3.0/24", "10.10.3.1", "10.10.3.2", "10.10.3.4"] : +List<String>}

law ctr.names:
  {[R.Ctr.bridge(3), R.Ctr.veth(3, 1), R.Ctr.peer(3, 1), R.Ctr.netns("demo", 1), R.Ctr.netns_path("demo", 0), R.Ctr.id("demo", 0),
    R.Ctr.tag("demo"), R.Ctr.node("demo", 0), R.Ctr.node("demo", 2)] ==
    ["vk8sbr3", "vk8s3n1", "vk8s3p1", "vk8s-demo-1", "/run/netns/vk8s-demo-0", "vk8s-demo-0",
    "vk8s:demo", "demo", "demo-worker-2"] : +List<String>}

law ctr.node_dir:
  {[R.Ctr.node_dir("/h/c", 0), R.Ctr.node_dir("/h/c", 2)] == ["/h/c", "/h/c/nodes/worker-2"] : +List<String>}

law ctr.slot.free:
  {R.Ctr.slot([1, 2, 4]) == 3 : U32}

law ctr.slot.first:
  {R.Ctr.slot([]) == 1 : U32}

law ctr.slots:
  {R.Ctr.slots("NAME=a\nSLOT=2\nNAME=b\nBACKEND=container\nSLOT=5\n") == [2, 5] : List<&2, U32>}

law ctr.setting:
  {[R.Ctr.setting("NAME=a\nSLOT=2\nWORKERS=1 2\n", "WORKERS"), R.Ctr.setting("NAME=a\n", "SLOT")] == ["1 2", ""] : +List<String>}

# Proposed: the host network.
law ctr.ip_bridge:
  {R.Ctr.ip_bridge(1) ==
    [ ["link", "add", "vk8sbr1", "type", "bridge"],
      ["addr", "add", "10.10.1.1/24", "dev", "vk8sbr1"],
      ["link", "set", "vk8sbr1", "up"] ] : +List<+List<String>>}

law ctr.ip_node:
  {R.Ctr.ip_node("demo", 1, 1) ==
    [ ["netns", "add", "vk8s-demo-1"],
      ["link", "add", "vk8s1n1", "type", "veth", "peer", "name", "vk8s1p1"],
      ["link", "set", "vk8s1p1", "netns", "vk8s-demo-1"],
      ["link", "set", "vk8s1n1", "master", "vk8sbr1"],
      ["link", "set", "vk8s1n1", "up"],
      ["-n", "vk8s-demo-1", "link", "set", "vk8s1p1", "name", "eth0"],
      ["-n", "vk8s-demo-1", "addr", "add", "10.10.1.3/24", "dev", "eth0"],
      ["-n", "vk8s-demo-1", "link", "set", "eth0", "up"],
      ["-n", "vk8s-demo-1", "link", "set", "lo", "up"],
      ["-n", "vk8s-demo-1", "route", "add", "default", "via", "10.10.1.1"] ] : +List<+List<String>>}

law ctr.rules:
  {R.Ctr.rules("demo", 1) ==
    [ ["-t", "nat", "-A", "POSTROUTING", "-s", "10.10.1.0/24", "!", "-o", "vk8sbr1", "-m", "comment", "--comment", "vk8s:demo", "-j", "MASQUERADE"],
      ["-t", "filter", "-I", "FORWARD", "-i", "vk8sbr1", "-m", "comment", "--comment", "vk8s:demo", "-j", "ACCEPT"],
      ["-t", "filter", "-I", "FORWARD", "-o", "vk8sbr1", "-m", "comment", "--comment", "vk8s:demo", "-j", "ACCEPT"] ] : +List<+List<String>>}

# Delete removes the cluster's tagged rules and no other: not another
# cluster's whose tag starts the same, not Docker's.
law ctr.net_cleanup:
  {R.Ctr.undo("nat", "vk8s:demo", Laws.ctr.drop_text()) ==
    [ ["-t", "nat", "-D", "POSTROUTING", "-s", "10.10.1.0/24", "!", "-o", "vk8sbr1", "-m", "comment", "--comment", "vk8s:demo", "-j", "MASQUERADE"] ] : +List<+List<String>>}

# iptables quotes a comment that needs it; -D takes it unquoted.
law ctr.net_cleanup.quoted:
  {R.Ctr.undo("filter", "vk8s:demo", "-P FORWARD DROP\n-A FORWARD -o vk8sbr1 -m comment --comment \"vk8s:demo\" -j ACCEPT\n-A FORWARD -j DOCKER-USER\n") ==
    [ ["-t", "filter", "-D", "FORWARD", "-o", "vk8sbr1", "-m", "comment", "--comment", "vk8s:demo", "-j", "ACCEPT"] ] : +List<+List<String>>}

law ctr.ip_del:
  {[R.Ctr.ip_node_del("demo", 1), R.Ctr.ip_bridge_del(1)] == [["netns", "del", "vk8s-demo-1"], ["link", "del", "vk8sbr1"]] : +List<+List<String>>}

# Proposed: host cgroup delegation and preflight.
law ctr.cgroup_dirs:
  {R.Ctr.cgroup_dirs("demo") == ["/sys/fs/cgroup", "/sys/fs/cgroup/vk8s", "/sys/fs/cgroup/vk8s/demo"] : +List<String>}

law ctr.enables:
  {R.Ctr.enables("cpuset cpu io memory hugetlb pids\n") == ["+cpuset", "+cpu", "+io", "+memory", "+hugetlb", "+pids"] : +List<String>}

law ctr.missing_controllers:
  {R.Ctr.missing_controllers("cpuset cpu io pids\n") == ["memory"] : +List<String>}

law ctr.root:
  {[R.Ctr.root("Name:\tvk8s\nUid:\t0\t0\t0\t0\n"), R.Ctr.root("Name:\tvk8s\nUid:\t1000\t1000\t1000\t1000\n")] == [True{}, False{}] : List<&2, Bool>}

law ctr.preflight_message:
  {R.Ctr.preflight_message(False{}, True{}, ["runc"], ["vxlan"], ["memory"]) ==
    "vk8s: --backend container needs root (run it with sudo)\n"
    ++ "vk8s: missing on this host: runc\n"
    ++ "vk8s: kernel modules that do not load: vxlan (modprobe vxlan)\n"
    ++ "vk8s: cgroup v2 controllers missing at /sys/fs/cgroup: memory\n" : String}

law ctr.preflight_no_cgroup2:
  {R.Ctr.preflight_message(True{}, False{}, [], [], ["cpu", "memory", "pids"]) ==
    "vk8s: cgroup v2 is not mounted at /sys/fs/cgroup (boot with systemd.unified_cgroup_hierarchy=1)\n" : String}

law ctr.preflight_ok:
  {R.Ctr.preflight_message(True{}, True{}, [], [], []) == "" : String}

law ctr.modules:
  {R.Ctr.modules() == ["overlay", "bridge", "br_netfilter", "veth", "vxlan", "nf_tables", "nf_conntrack"] : +List<String>}

# Proposed: DNS for the nodes. systemd-resolved's stub (127.0.0.53) is
# the host's loopback; its upstreams are in /run/systemd/resolve/resolv.conf.
law ctr.resolv.upstream:
  {R.Ctr.resolv("nameserver 168.63.129.16\nsearch x.internal\n", "nameserver 127.0.0.53\n") == "nameserver 168.63.129.16\n" : String}

law ctr.resolv.host:
  {R.Ctr.resolv("", "nameserver 127.0.0.53\nnameserver 10.0.0.2\n") == "nameserver 10.0.0.2\n" : String}

law ctr.resolv.fallback:
  {R.Ctr.resolv("", "nameserver 127.0.0.53\n") == "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" : String}

# Proposed: the node containers.
law ctr.env_cp:
  {R.Ctr.env_cp("demo", 1, 6443, False{}) ==
    [ "PATH=/var/lib/vcluster/bin:/var/lib/vcluster/bin/cni/bin:/usr/sbin:/usr/bin:/sbin:/bin", "VK8S_BACKEND=container",
      "VK8S_NAME=demo", "VK8S_PORT=6443", "VK8S_STORE=sqlite", "VK8S_NODE_IP=10.10.1.2" ] : +List<String>}

law ctr.env_worker:
  {R.Ctr.env_worker("demo", 1, 1, "abcdef.0123456789abcdef") ==
    [ "PATH=/var/lib/vcluster/bin:/var/lib/vcluster/bin/cni/bin:/usr/sbin:/usr/bin:/sbin:/bin", "VK8S_BACKEND=container",
      "VK8S_ROLE=worker", "VK8S_NAME=demo-worker-1", "VK8S_NODE_IP=10.10.1.3", "VK8S_TOKEN=abcdef.0123456789abcdef" ] : +List<String>}

law ctr.linux:
  {R.Ctr.linux("demo", "demo", "/run/netns/vk8s-demo-0") ==
    J.Json.obj([
      J.KV{"namespaces", J.Json.arr([C.Container.ns("pid"), C.Container.ns("ipc"), C.Container.ns("uts"), C.Container.ns("mount"),
        J.Json.obj([J.KV{"type", J.JStr{"network"}}, J.KV{"path", J.JStr{"/run/netns/vk8s-demo-0"}}]), C.Container.ns("cgroup")])},
      J.KV{"cgroupsPath", J.JStr{"/vk8s/demo/demo"}},
      J.KV{"resources", J.Json.obj([J.KV{"devices", J.Json.arr([J.Json.obj([J.KV{"allow", J.JBool{True{}}},
        J.KV{"access", J.JStr{"rwm"}}])])}])}]) : J.Json}

# The config differs from C.Container.config in the network namespace only.
law ctr.config:
  {R.Ctr.config(C.Spec{"demo", "demo", "/r", "/d", "/s", "/a", ["VK8S_NAME=demo"]}, "/run/netns/vk8s-demo-0") ==
    J.Json.obj([
      J.KV{"ociVersion", J.JStr{"1.0.2"}},
      J.KV{"process", C.Container.process(["VK8S_NAME=demo"])},
      J.KV{"root", J.Json.obj([J.KV{"path", J.JStr{"/r"}}, J.KV{"readonly", J.JBool{False{}}}])},
      J.KV{"hostname", J.JStr{"demo"}},
      J.KV{"mounts", J.Json.arr(C.Container.mounts("/d", "/s", "/a"))},
      J.KV{"linux", R.Ctr.linux("demo", "demo", "/run/netns/vk8s-demo-0")}]) : J.Json}

law ctr.commands:
  {[R.Ctr.unpack("/a/vk8s.cpio", "/c/bundle/rootfs"), R.Ctr.mount_assets("/a/assets.img", "/c/assets"), R.Ctr.runc_run("/c/bundle", "vk8s-demo-0")] ==
    [ ["-idmu", "--quiet", "--no-absolute-filenames", "-D", "/c/bundle/rootfs", "-F", "/a/vk8s.cpio"],
      ["-t", "squashfs", "-o", "loop,ro", "/a/assets.img", "/c/assets"],
      ["--root", "/run/vk8s/runc", "run", "-d", "--bundle", "/c/bundle", "vk8s-demo-0"] ] : +List<+List<String>>}

law ctr.status.running:
  {R.Ctr.status("{\n  \"ociVersion\": \"1.0.2\",\n  \"id\": \"vk8s-demo-0\",\n  \"pid\": 4242,\n  \"status\": \"running\",\n  \"bundle\": \"/c/bundle\"\n}\n") == "running" : String}

law ctr.status.gone:
  {R.Ctr.status("") == "stopped" : String}

# Proposed: a node container names an amd64 host's arch as the VM's
# kernel command line does (Cli.arch_flags); arm64 names none.
law ctr.arch_env.amd64:
  {R.Ctr.arch_env("amd64", ["VK8S_NAME=demo"]) == ["VK8S_NAME=demo", "VK8S_ARCH=amd64"] : +List<String>}

law ctr.arch_env.other:
  for env: +List<String>
  {R.Ctr.arch_env("arm64", env) == env : +List<String>}

# Proposed: the host loads af_packet too (docs/GOAL.md section 8): gVisor's
# sandbox network opens an AF_PACKET raw socket on the pod's veth (gVisor
# runsc/sandbox/network.go, createSocket), and a node container runs on
# the host's kernel. Ctr.modules stays as it was, then af_packet.
law ctr.modules.v2:
  {R.Ctr.modules.v2() == ["overlay", "bridge", "br_netfilter", "veth", "vxlan", "nf_tables", "nf_conntrack", "af_packet"] : +List<String>}

# Proposed (docs/ref/review-bend-vk8s-pr-49.md findings 1-3): a slot is
# reserved per host, atomically, and delete takes down only what its
# cluster owns; the clusters' bridges do not forward to each other; every
# iptables call waits for the xtables lock; delete names what it could
# not remove. Ctr.rules, Ctr.undo and Ctr.slot stay as they were. The
# values are vk8s's own, except -w, which iptables(8) defines: "Wait for
# the xtables lock ... wait (indefinitely or for optional seconds)".

# The per-host slot registry is under /run (root's, one per host kernel,
# like the bridges; both are gone after a reboot). `mkdir` of a slot's
# directory fails when it exists, so two creates never hold one slot.
law ctr.slot_registry:
  {[R.Ctr.slots_dir(), R.Ctr.slot_dir(3), R.Ctr.slot_owner(3), R.Ctr.owner_text("/h/.vk8s/clusters/demo")] ==
    ["/run/vk8s/slots", "/run/vk8s/slots/3", "/run/vk8s/slots/3/owner", "/h/.vk8s/clusters/demo\n"] : +List<String>}

law ctr.slot_commands:
  {[R.Ctr.reserve(3), R.Ctr.release(3), R.Ctr.bridge_show(3)] ==
    [["/run/vk8s/slots/3"], ["-rf", "/run/vk8s/slots/3"], ["link", "show", "dev", "vk8sbr3"]] : +List<+List<String>>}

# The slots create tries, in order: every slot no cluster of this home
# records (the clusters made before the registry hold no reservation).
law ctr.free:
  {R.Ctr.free.go(6n, 1, [1, 2, 4]) == [3, 5, 6] : List<&2, U32>}

law ctr.free.first:
  {R.Ctr.free.go(2n, 1, []) == [1, 2] : List<&2, U32>}

# A cluster owns its slot when the reservation names its directory; a
# reservation of another home or none (a reboot, an older vk8s) is not
# its own.
law ctr.owns:
  {[R.Ctr.owns("/h/.vk8s/clusters/demo\n", "/h/.vk8s/clusters/demo"), R.Ctr.owns("/root/.vk8s/clusters/demo\n", "/h/.vk8s/clusters/demo"),
    R.Ctr.owns("", "/h/.vk8s/clusters/demo")] == [True{}, False{}, False{}] : List<&2, Bool>}

# Isolation: a cluster's bridge forwards within itself and to the uplink,
# never to another vk8s bridge, in either direction. Each rule is
# inserted at the top of FORWARD, so the last is first: same bridge
# accepted, then the drops, then Ctr.rules' accepts below them.
law ctr.isolate:
  {R.Ctr.isolate("demo", 1) ==
    [ ["-t", "filter", "-I", "FORWARD", "-i", "vk8sbr+", "-o", "vk8sbr1", "-m", "comment", "--comment", "vk8s:demo", "-j", "DROP"],
      ["-t", "filter", "-I", "FORWARD", "-i", "vk8sbr1", "-o", "vk8sbr+", "-m", "comment", "--comment", "vk8s:demo", "-j", "DROP"],
      ["-t", "filter", "-I", "FORWARD", "-i", "vk8sbr1", "-o", "vk8sbr1", "-m", "comment", "--comment", "vk8s:demo", "-j", "ACCEPT"] ] : +List<+List<String>>}

law ctr.ipt:
  {R.Ctr.ipt(["-t", "nat", "-S"]) == ["-w", "30", "-t", "nat", "-S"] : +List<String>}

law ctr.rules.v2:
  {R.Ctr.rules.v2("demo", 1) ==
    [ ["-w", "30", "-t", "nat", "-A", "POSTROUTING", "-s", "10.10.1.0/24", "!", "-o", "vk8sbr1", "-m", "comment", "--comment", "vk8s:demo", "-j", "MASQUERADE"],
      ["-w", "30", "-t", "filter", "-I", "FORWARD", "-i", "vk8sbr1", "-m", "comment", "--comment", "vk8s:demo", "-j", "ACCEPT"],
      ["-w", "30", "-t", "filter", "-I", "FORWARD", "-o", "vk8sbr1", "-m", "comment", "--comment", "vk8s:demo", "-j", "ACCEPT"],
      ["-w", "30", "-t", "filter", "-I", "FORWARD", "-i", "vk8sbr+", "-o", "vk8sbr1", "-m", "comment", "--comment", "vk8s:demo", "-j", "DROP"],
      ["-w", "30", "-t", "filter", "-I", "FORWARD", "-i", "vk8sbr1", "-o", "vk8sbr+", "-m", "comment", "--comment", "vk8s:demo", "-j", "DROP"],
      ["-w", "30", "-t", "filter", "-I", "FORWARD", "-i", "vk8sbr1", "-o", "vk8sbr1", "-m", "comment", "--comment", "vk8s:demo", "-j", "ACCEPT"] ] : +List<+List<String>>}

law ctr.list_rules:
  {R.Ctr.list_rules("filter") == ["-w", "30", "-t", "filter", "-S"] : +List<String>}

law ctr.net_cleanup.v2:
  {R.Ctr.undo.v2("nat", "vk8s:demo", Laws.ctr.drop_text()) ==
    [ ["-w", "30", "-t", "nat", "-D", "POSTROUTING", "-s", "10.10.1.0/24", "!", "-o", "vk8sbr1", "-m", "comment", "--comment", "vk8s:demo", "-j", "MASQUERADE"] ] : +List<+List<String>>}

# Delete is done with the rules once a fresh listing holds none tagged.
law ctr.rules_gone:
  {[R.Ctr.rules_gone("nat", "vk8s:demo", Laws.ctr.drop_text()), R.Ctr.rules_gone("nat", "vk8s:demo3", Laws.ctr.drop_text())] ==
    [False{}, True{}] : List<&2, Bool>}

# What delete checks after it ran: runc's state directory of each node
# and its network namespace, then the cgroup.
law ctr.delete_paths:
  {[R.Ctr.state_dir("vk8s-demo-0"), R.Ctr.cgroup("demo")] == ["/run/vk8s/runc/vk8s-demo-0", "/sys/fs/cgroup/vk8s/demo"] : +List<String>}

law ctr.leftovers:
  {R.Ctr.leftovers("demo", 1, R.Ctr.left_node(True{}, True{}, "demo", 1, R.Ctr.left_node(False{}, False{}, "demo", 0, [])),
    False{}, False{}, True{}, R.Ctr.left_mount(True{}, "/h/c/assets", R.Ctr.left_mount(False{}, "/h/c/base", []))) ==
    [ "container vk8s-demo-1", "network namespace vk8s-demo-1", "iptables rules tagged vk8s:demo", "bridge vk8sbr1",
      "mount /h/c/assets" ] : +List<String>}

law ctr.leftovers.none:
  {R.Ctr.leftovers("demo", 1, [], True{}, True{}, True{}, []) == [] : +List<String>}

law ctr.delete_failed:
  {R.Ctr.delete_failed("demo", "/h/c", ["bridge vk8sbr1", "cgroup /sys/fs/cgroup/vk8s/demo"]) ==
    "vk8s: could not remove from this host: bridge vk8sbr1, cgroup /sys/fs/cgroup/vk8s/demo; /h/c/cluster.env is kept, run vk8s delete demo again" : String}

law ctr.unowned_message:
  {R.Ctr.unowned_message(2) ==
    "warning: vk8sbr2 is not recorded as this cluster's in /run/vk8s/slots/2/owner, so it stays (ip link del vk8sbr2 removes it)" : String}

# Create fetches the control plane's sets (review-bend-vk8s-pr-48.md
# finding 1): images too when it is in the assets dir, or when the dir is
# the pinned release's and the release pins it.
law ctr.want_images:
  {[R.Ctr.want_images(True{}, False{}, False{}), R.Ctr.want_images(False{}, True{}, True{}), R.Ctr.want_images(False{}, False{}, True{}),
    R.Ctr.want_images(False{}, True{}, False{})] == [True{}, True{}, False{}, False{}] : List<&2, Bool>}

# Proposed: the shared layer store in node containers (docs/GOAL.md
# section 11, the container half; vk8s's design). Opt-in: only
# VK8S_LAYERS=1 turns it on (VM nodes default to on, Cli.layers_on.v2;
# containers keep their own unpack until measured). The store is the VM
# share's directory; PID 1 learns of it and of the filler's address on
# the bridge (the gateway) from its environment; the host forwards that
# address's filler port (Ask.port.v2, 32000) to the filler on its
# loopback, accepts it ahead of an INPUT policy, and drops anything else
# from the bridge to 127.0.0.0/8 that was not translated (kube-proxy's
# rule for CVE-2020-8558, which route_localnet would let through). Every
# rule carries the cluster's tag, so delete's Ctr.undo takes it away.
law ctr.layers_on:
  {[R.Ctr.layers_on("1"), R.Ctr.layers_on(""), R.Ctr.layers_on("0"), R.Ctr.layers_on("yes")] ==
    [True{}, False{}, False{}, False{}] : List<&2, Bool>}
law ctr.store:
  {R.Ctr.store("/h/.vk8s") == "/h/.vk8s/layers" : String}
law ctr.layers_env_on:
  {R.Ctr.layers_env(True{}, 3, ["VK8S_NAME=demo"]) == ["VK8S_NAME=demo", "VK8S_LAYERS=1", "VK8S_LAYERS_ASK=10.10.3.1"] : +List<String>}
law ctr.layers_env_off:
  for +k: U32
  for env: +List<String>
  {R.Ctr.layers_env(False{}, k, env) == env : +List<String>}
law ctr.route_localnet:
  {R.Ctr.route_localnet(3) == "/proc/sys/net/ipv4/conf/vk8sbr3/route_localnet" : String}
law ctr.layers_rules_on:
  {R.Ctr.layers_rules(True{}, "demo", 3) ==
    [ ["-w", "30", "-t", "nat", "-A", "PREROUTING", "-i", "vk8sbr3", "-d", "10.10.3.1/32", "-p", "tcp", "--dport", "32000",
        "-m", "comment", "--comment", "vk8s:demo", "-j", "DNAT", "--to-destination", "127.0.0.1:32000"],
      ["-w", "30", "-t", "filter", "-I", "INPUT", "-i", "vk8sbr3", "-d", "127.0.0.0/8", "-m", "conntrack", "!", "--ctstate", "DNAT",
        "-m", "comment", "--comment", "vk8s:demo", "-j", "DROP"],
      ["-w", "30", "-t", "filter", "-I", "INPUT", "-i", "vk8sbr3", "-d", "127.0.0.1/32", "-p", "tcp", "--dport", "32000",
        "-m", "conntrack", "--ctstate", "DNAT", "-m", "comment", "--comment", "vk8s:demo", "-j", "ACCEPT"] ] : +List<+List<String>>}
law ctr.layers_rules_off:
  for +c: String
  for +k: U32
  {R.Ctr.layers_rules(False{}, c, k) == [] : +List<+List<String>>}
# Delete finds them by their tag in `iptables -t nat -S` (which prints a
# rule's matches in its own order) and deletes each as listed.
law ctr.layers_rules_undo:
  {R.Ctr.undo("nat", "vk8s:demo",
    "-P PREROUTING ACCEPT\n-A PREROUTING -d 10.10.3.1/32 -i vk8sbr3 -p tcp -m tcp --dport 32000 -m comment --comment vk8s:demo -j DNAT --to-destination 127.0.0.1:32000\n") ==
    [ ["-t", "nat", "-D", "PREROUTING", "-d", "10.10.3.1/32", "-i", "vk8sbr3", "-p", "tcp", "-m", "tcp", "--dport", "32000", "-m", "comment",
        "--comment", "vk8s:demo", "-j", "DNAT", "--to-destination", "127.0.0.1:32000"] ] : +List<+List<String>>}
law ctr.layers_modules:
  {R.Ctr.layers_modules() == ["loop", "squashfs"] : +List<String>}
# Off, a node's config.json is the one before, byte for byte.
law ctr.json_v2_off:
  for +s: C.Spec
  for +n: String
  for x: String
  {R.Ctr.json.v2(s, n, False{}, x) == R.Ctr.json(s, n) : String}

# Proposed: optional sets on demand (docs/GOAL.md section 11; vk8s
# design). The cluster's assets mount adds etcd with the etcd backing
# store and gvisor with --gvisor; without them it is Ctr.sets's. Delete
# unmounts every set a cluster may have.
law ctr.sets.v2.plain:
  for images: Bool
  {R.Ctr.sets.v2(images, False{}, False{}) == R.Ctr.sets(images) : +List<String>}
law ctr.sets.v2.both:
  {R.Ctr.sets.v2(True{}, True{}, True{}) == ["node", "control-plane", "images", "etcd", "gvisor"] : +List<String>}
law ctr.sets.v2.gvisor:
  {R.Ctr.sets.v2(False{}, True{}, False{}) == ["node", "control-plane", "gvisor"] : +List<String>}
law ctr.asset_mounts.v2:
  {R.Ctr.asset_mounts.v2("/c") == ["/c/assets", "/c/sets/node", "/c/sets/control-plane", "/c/sets/images", "/c/sets/etcd",
     "/c/sets/gvisor", "/c/base"] : +List<String>}
