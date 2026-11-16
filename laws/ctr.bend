import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
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
