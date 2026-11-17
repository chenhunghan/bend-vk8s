import Base
import ../src/cli/nodehost.bend as N
import ../src/guest/plan.bend as P

# Spec for src/cli/nodehost.bend: container mode on macOS, the shared
# bend-vmm node-host VM (docs/ref/explore-linux-hosts.md Phase 6 C4, D11 a).
#
# Proposed: every law in this file. The names, ports, slots and request
# words are vk8s's own choices, not vcluster's: vcluster's docker driver
# asks Docker Desktop's VM for containers, and vk8s runs its own. Facts
# from outside, cited where used: bend-vmm takes at most 16 --forward
# entries ("repeatable, at most 16", bend-vmm README); `runc list` prints
# the columns ID PID STATUS BUNDLE CREATED OWNER (runc list.go); a cgroup
# v2 cgroup.events file has the line "populated 0" or "populated 1"
# (Documentation/admin-guide/cgroup-v2.rst); iptables -D takes the spec
# that -A or -I took (iptables(8)).

# Proposed: where container mode runs.
law nodehost.use_vm:
  {[N.Nh.use_vm("Darwin", ""), N.Nh.use_vm("Linux", ""), N.Nh.use_vm("Linux", "vm")] == [True{}, False{}, True{}] : List<&2, Bool>}

# Proposed: one forward per cluster, 16 at most (bend-vmm's cap).
law nodehost.ports:
  {[N.Nh.port(1), N.Nh.port(16), N.Nh.max()] == [16401, 16416, 16] : List<&2, U32>}

law nodehost.slot:
  {[N.Nh.slot([1, 2, 4]), N.Nh.slot([]), N.Nh.slot([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16])] == [3, 1, 0] : List<&2, U32>}

law nodehost.forwards:
  {N.Nh.forwards() ==
    "127.0.0.1:16401:16401,127.0.0.1:16402:16402,127.0.0.1:16403:16403,127.0.0.1:16404:16404,"
    ++ "127.0.0.1:16405:16405,127.0.0.1:16406:16406,127.0.0.1:16407:16407,127.0.0.1:16408:16408,"
    ++ "127.0.0.1:16409:16409,127.0.0.1:16410:16410,127.0.0.1:16411:16411,127.0.0.1:16412:16412,"
    ++ "127.0.0.1:16413:16413,127.0.0.1:16414:16414,127.0.0.1:16415:16415,127.0.0.1:16416:16416" : String}

law nodehost.flags:
  {N.Nh.flags("/h/.vk8s/nodehost", "/a", 8192, 4) ==
    [ "--kernel", "/a/Image",
      "--initrd", "/a/vk8s.cpio",
      "--disk", "/a/assets.img:ro:nocache,/h/.vk8s/nodehost/data.img",
      "--share", "/h/.vk8s/nodehost/share,quota=1G",
      "--console-log", "/h/.vk8s/nodehost/console.log,max=64M,keep=2",
      "--mem", "8192",
      "--cpus", "4",
      "--forward", N.Nh.forwards(),
      "--control", "/h/.vk8s/nodehost/ctl.sock",
      "--cmdline", "console=ttyAMA0 quiet panic=5 VK8S_ROLE=node-host VK8S_NAME=vk8s-nodehost",
      "--balloon", "auto" ] : +List<String>}

law nodehost.sets:
  {[N.Nh.sets(True{}), N.Nh.sets(False{})] == [["node", "control-plane", "images"], ["node", "control-plane"]] : +List<+List<String>>}

# Proposed: a node's share is on the node host's share (the Mac reads it
# as it reads a VM node's); its root and data are on the VM's data disk.
law nodehost.paths:
  {[N.Nh.share("/n", "demo", 0), N.Nh.share("/n", "demo", 2), N.Nh.vm_share("demo", 0), N.Nh.vm_share("demo", 1),
    N.Nh.vm_dir("demo", 0), N.Nh.vm_dir("demo", 1), N.Nh.node_dir("/n", "demo", 0), N.Nh.node_dir("/n", "demo", 1)] ==
    [ "/n/share/clusters/demo/share", "/n/share/clusters/demo/nodes/worker-2/share",
      "/var/lib/vk8s-host/clusters/demo/share", "/var/lib/vk8s-host/clusters/demo/nodes/worker-1/share",
      "/var/lib/vcluster/nodehost/clusters/demo", "/var/lib/vcluster/nodehost/clusters/demo/nodes/worker-1",
      "/n/share/clusters/demo", "/n/share/clusters/demo/nodes/worker-1" ] : +List<String>}

law nodehost.lowers:
  {N.Nh.lowers(["node", "control-plane"]) == ["/sets/node", "/sets/control-plane", "/assets"] : +List<String>}

# Proposed: the request words, both ways.
law nodehost.requests:
  {[N.Nh.req_up("demo", 3, False{}), N.Nh.req_up("demo", 3, True{}), N.Nh.req_join("demo", 3, 2, "abcdef.0123456789abcdef"),
    N.Nh.req_down("demo", 3, [1, 2]), N.Nh.req_down("demo", 3, []), N.Nh.req_freeze("pause", "demo", [1])] ==
    [ "up demo 3 sqlite", "up demo 3 etcd", "join demo 3 2 abcdef.0123456789abcdef",
      "down demo 3 1,2", "down demo 3 -", "pause demo 1" ] : +List<String>}

law nodehost.parse_up:
  {N.Nh.parse(["up", "demo", "3", "etcd"]) == N.Up{"demo", 3, True{}} : N.Op}

law nodehost.parse_up_kine:
  {N.Nh.parse(["up", "demo", "3", "sqlite"]) == N.Up{"demo", 3, False{}} : N.Op}

law nodehost.parse_join:
  {N.Nh.parse(["join", "demo", "3", "2", "abcdef.0123456789abcdef"]) == N.Join{"demo", 3, 2, "abcdef.0123456789abcdef"} : N.Op}

law nodehost.parse_down:
  {[N.Nh.parse(["down", "demo", "3", "1,2"]), N.Nh.parse(["down", "demo", "3", "-"])] ==
    [N.Down{"demo", 3, [1, 2]}, N.Down{"demo", 3, []}] : List<&2, N.Op>}

law nodehost.parse_freeze:
  {[N.Nh.parse(["pause", "demo", "1"]), N.Nh.parse(["resume", "demo", "-"])] ==
    [N.Freeze{"pause", "demo", [1]}, N.Freeze{"resume", "demo", []}] : List<&2, N.Op>}

# A slot outside 1..16, a bad name or token, a missing or extra word, or
# an unknown verb is refused.
law nodehost.parse_bad:
  {[N.Nh.parse(["up", "demo", "17", "etcd"]), N.Nh.parse(["up", "demo", "0", "etcd"]), N.Nh.parse(["up", "Demo", "3", "etcd"]),
    N.Nh.parse(["up", "demo", "3"]), N.Nh.parse(["down", "demo", "3", "-", "x"]), N.Nh.parse(["join", "demo", "3", "2", "nope"]),
    N.Nh.parse(["join", "demo", "3", "0", "abcdef.0123456789abcdef"]), N.Nh.parse(["reboot", "demo", "-"]), N.Nh.parse([])] ==
    [N.Bad{}, N.Bad{}, N.Bad{}, N.Bad{}, N.Bad{}, N.Bad{}, N.Bad{}, N.Bad{}, N.Bad{}] : List<&2, N.Op>}

# Proposed: the cluster's API port reaches its control plane.
law nodehost.dnat:
  {N.Nh.dnat("demo", 3) ==
    ["-t", "nat", "-A", "PREROUTING", "-i", "eth0", "-p", "tcp", "--dport", "16403", "-m", "comment", "--comment", "vk8s:demo",
      "-j", "DNAT", "--to-destination", "10.10.3.2:6443"] : +List<String>}

# Delete names every rule up made, with -D.
law nodehost.unrules:
  {N.Nh.unrules("demo", 1) ==
    [ ["-t", "nat", "-D", "PREROUTING", "-i", "eth0", "-p", "tcp", "--dport", "16401", "-m", "comment", "--comment", "vk8s:demo",
        "-j", "DNAT", "--to-destination", "10.10.1.2:6443"],
      ["-t", "nat", "-D", "POSTROUTING", "-s", "10.10.1.0/24", "!", "-o", "vk8sbr1", "-m", "comment", "--comment", "vk8s:demo", "-j", "MASQUERADE"],
      ["-t", "filter", "-D", "FORWARD", "-i", "vk8sbr1", "-m", "comment", "--comment", "vk8s:demo", "-j", "ACCEPT"],
      ["-t", "filter", "-D", "FORWARD", "-o", "vk8sbr1", "-m", "comment", "--comment", "vk8s:demo", "-j", "ACCEPT"] ] : +List<+List<String>>}

# Proposed: stopping a node waits for its cgroup to empty.
law nodehost.events:
  {[N.Nh.events("demo", 0), N.Nh.events("demo", 2)] ==
    ["/sys/fs/cgroup/vk8s/demo/demo/cgroup.events", "/sys/fs/cgroup/vk8s/demo/demo-worker-2/cgroup.events"] : +List<String>}

law nodehost.populated:
  {[N.Nh.populated("populated 1\nfrozen 0\n"), N.Nh.populated("populated 0\nfrozen 0\n"), N.Nh.populated("")] ==
    [True{}, False{}, False{}] : List<&2, Bool>}

law nodehost.stop_steps:
  {N.Nh.stop_pre("/r", "demo", 1) ==
    [ P.Run{"/r", ["--root", "/run/vk8s/runc", "resume", "vk8s-demo-1"]},
      P.Write{"/var/lib/vk8s-host/clusters/demo/nodes/worker-1/share/stop", "stop\n"} ] : +List<P.Step>}

law nodehost.nodes:
  {N.Nh.nodes([1, 2]) == [1, 2, 0] : List<&2, U32>}

# Proposed: on the Mac, list and the node host's lifetime.
law nodehost.status:
  {[N.Nh.status("ID              PID   STATUS    BUNDLE   CREATED   OWNER\nvk8s-demo-0     812   running   /b       2026      root\nvk8s-demo-1     0     paused    /c       2026      root\n", "vk8s-demo-1"),
    N.Nh.status("ID   PID   STATUS   BUNDLE   CREATED   OWNER\n", "vk8s-demo-0")] == ["paused", "stopped"] : +List<String>}

law nodehost.left:
  {[N.Nh.left("NODEHOST=1\n"), N.Nh.left("BACKEND=container\nSLOT=1\n"), N.Nh.left("")] == [True{}, False{}, False{}] : List<&2, Bool>}

law nodehost.env:
  {N.Nh.env("demo", 2, True{}, 1, "1700000000\n") ==
    "NAME=demo\nGUEST=demo\nPORT=16402\nCPUS=0\nMEMORY=0\nSTORE=etcd\nNODES=1\nWORKERS=1\nKUBERNETES=v1.36.6\nBACKEND=container\nSLOT=2\nNODEHOST=1\nAPI=https://127.0.0.1:16402\nCREATED=1700000000\n" : String}

# Proposed: the node host's footprint (docs/GOAL.md sections 7 and 8;
# STATUS: settled at 3.3 GB and 19.6% idle host CPU for one cluster, vs
# ~1.8 GB and 8-11% in VM mode). vk8s's own choices, not vcluster's.
# Defaults: 2 vCPUs (fewer vCPUs to wake and park; a 1-worker cluster in
# VM mode is 2 VMs of 2 vCPUs, and one guest kernel serves both nodes
# here) and 6144 MiB, the RAM of a 2-worker cluster in VM mode (3 x 2048).
# bend-vmm's auto balloon keeps max(256 MiB, RAM/10) free and holds at
# most half of RAM, so a smaller RAM lowers both the free floor and the
# most the guest can keep. VK8S_NODE_HOST_CPUS and VK8S_NODE_HOST_MEMORY
# override them; the node host is sized when it starts (with the first
# container cluster).
law nodehost.defaults:
  {[N.Nh.mem(), N.Nh.cpus()] == [6144, 2] : List<&2, U32>}

# Proposed: the node host's PID 1 runs the periodic chores a cluster VM's
# PID 1 runs (host/init.bend Init.supervise, same periods and order):
# log trim (60 s; the nodes' runc output is on the share), clock sync
# from the RTC (10 s; the node containers share the VM's clock and sync
# none), fstrim of the data disk (10 min; the nodes' roots and data are
# on it), the guarded idle page-cache reclaim (30 s) and idle compaction
# (10 min). The node containers run none of them
# (container_host.no_machine_maintenance).
law nodehost.chores_none:
  {N.Nh.chores(1) == [] : +List<P.Step>}

law nodehost.chores_clock:
  {N.Nh.chores(10) == [P.Plan.clock_sync()] : +List<P.Step>}

law nodehost.chores_reclaim:
  {N.Nh.chores(30) == [P.Plan.clock_sync(), P.Plan.idle_reclaim()] : +List<P.Step>}

law nodehost.chores_trim:
  {N.Nh.chores(60) == [P.Plan.trim_logs(), P.Plan.clock_sync(), P.Plan.idle_reclaim()] : +List<P.Step>}

law nodehost.chores_all:
  {N.Nh.chores(600) ==
    [P.Plan.trim_logs(), P.Plan.clock_sync(), P.Plan.fstrim(), P.Plan.idle_reclaim(), P.Plan.idle_compact()] : +List<P.Step>}

# Proposed: runc's container list goes to the share every 30 s (was
# every 5 s: a runc process each time) and after every request, so a
# pause, resume, up or down shows at once.
law nodehost.list_due:
  {[N.Nh.list_due(0), N.Nh.list_due(5), N.Nh.list_due(29), N.Nh.list_due(30), N.Nh.list_due(60)] ==
    [True{}, False{}, False{}, True{}, True{}] : List<&2, Bool>}
