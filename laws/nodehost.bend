import Base
import ../src/cli/nodehost.bend as N
import ../src/guest/plan.bend as P
import ../src/guest/container.bend as C
import ../src/cli/ctr.bend as R
import ../src/layers/ask.bend as LA

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

# Proposed (docs/ref/review-bend-vk8s-pr-49.md finding 2): the clusters
# in the node host are isolated from each other as on a Linux host
# (R.Ctr.isolate after the cluster's rules), and delete names those
# rules too. Without -w: the node host's PID 1 is the only iptables user
# in its VM. Nh.rules and Nh.unrules stay as they were.
law nodehost.rules.v2:
  {N.Nh.rules.v2("demo", 1) ==
    [ ["-t", "nat", "-A", "PREROUTING", "-i", "eth0", "-p", "tcp", "--dport", "16401", "-m", "comment", "--comment", "vk8s:demo",
        "-j", "DNAT", "--to-destination", "10.10.1.2:6443"],
      ["-t", "nat", "-A", "POSTROUTING", "-s", "10.10.1.0/24", "!", "-o", "vk8sbr1", "-m", "comment", "--comment", "vk8s:demo", "-j", "MASQUERADE"],
      ["-t", "filter", "-I", "FORWARD", "-i", "vk8sbr1", "-m", "comment", "--comment", "vk8s:demo", "-j", "ACCEPT"],
      ["-t", "filter", "-I", "FORWARD", "-o", "vk8sbr1", "-m", "comment", "--comment", "vk8s:demo", "-j", "ACCEPT"],
      ["-t", "filter", "-I", "FORWARD", "-i", "vk8sbr+", "-o", "vk8sbr1", "-m", "comment", "--comment", "vk8s:demo", "-j", "DROP"],
      ["-t", "filter", "-I", "FORWARD", "-i", "vk8sbr1", "-o", "vk8sbr+", "-m", "comment", "--comment", "vk8s:demo", "-j", "DROP"],
      ["-t", "filter", "-I", "FORWARD", "-i", "vk8sbr1", "-o", "vk8sbr1", "-m", "comment", "--comment", "vk8s:demo", "-j", "ACCEPT"] ] : +List<+List<String>>}

law nodehost.unrules.v2:
  {N.Nh.unrules.v2("demo", 1) ==
    [ ["-t", "nat", "-D", "PREROUTING", "-i", "eth0", "-p", "tcp", "--dport", "16401", "-m", "comment", "--comment", "vk8s:demo",
        "-j", "DNAT", "--to-destination", "10.10.1.2:6443"],
      ["-t", "nat", "-D", "POSTROUTING", "-s", "10.10.1.0/24", "!", "-o", "vk8sbr1", "-m", "comment", "--comment", "vk8s:demo", "-j", "MASQUERADE"],
      ["-t", "filter", "-D", "FORWARD", "-i", "vk8sbr1", "-m", "comment", "--comment", "vk8s:demo", "-j", "ACCEPT"],
      ["-t", "filter", "-D", "FORWARD", "-o", "vk8sbr1", "-m", "comment", "--comment", "vk8s:demo", "-j", "ACCEPT"],
      ["-t", "filter", "-D", "FORWARD", "-i", "vk8sbr+", "-o", "vk8sbr1", "-m", "comment", "--comment", "vk8s:demo", "-j", "DROP"],
      ["-t", "filter", "-D", "FORWARD", "-i", "vk8sbr1", "-o", "vk8sbr+", "-m", "comment", "--comment", "vk8s:demo", "-j", "DROP"],
      ["-t", "filter", "-D", "FORWARD", "-i", "vk8sbr1", "-o", "vk8sbr1", "-m", "comment", "--comment", "vk8s:demo", "-j", "ACCEPT"] ] : +List<+List<String>>}

# Proposed: the node host's PID 1 runs the step chores of Nh.chores.v2
# (log trim, clock, fstrim) and the memory chores in Bend, as a cluster
# VM's PID 1 does (laws plan.reclaim_turn.*, plan.compact_turn.*,
# plan.reclaim_due, plan.compact_due): Nh.chores keeps its laws, and PID 1
# no longer runs the reclaim and compaction scripts it lists
# (docs/ref/review-direct-commits-main.md F1-F3).
law nodehost.chores_v2_none:
  {N.Nh.chores.v2(15) == [] : +List<P.Step>}

law nodehost.chores_v2_clock:
  {N.Nh.chores.v2(30) == [P.Plan.clock_sync()] : +List<P.Step>}

law nodehost.chores_v2_all:
  {N.Nh.chores.v2(600) == [P.Plan.trim_logs(), P.Plan.clock_sync(), P.Plan.fstrim()] : +List<P.Step>}

# Proposed: idle sleep of the node host (GOAL section 11); vk8s's design.
law nodehost.asleep_file:
  {N.Nh.asleep_file() == "asleep" : String}

# Proposed: optional sets on demand (docs/GOAL.md section 11; vk8s
# design). The node host attaches the optional sets the assets dir holds,
# beside a Linux container cluster's sets, and records what it booted
# with in its directory's file "sets".
law nodehost.sets.v2:
  {[N.Nh.sets.v2(False{}, False{}, False{}), N.Nh.sets.v2(False{}, True{}, True{})]
   == [["node", "control-plane"], ["node", "control-plane", "etcd", "gvisor"]] : List<&2, +List<String>>}
law nodehost.sets_file:
  {N.Nh.sets_file() == "sets" : String}

# Proposed: a request's answer follows the list (vk8s's design; the
# statuses are runc's: created, running, paused, stopped, libcontainer
# Status.String, and `runc list` has no row for a container that is
# gone). `vk8s list` takes a node-host cluster's state from the list the
# node host's PID 1 writes on the share (nodehost.status), and `up` ends
# with `runc run -d` spawned, not waited for: a list written at once has
# no row for the new cluster yet, so a Ready cluster listed as stopped
# until the next periodic list (nodehost.list_due: up to 30 s). PID 1 now
# writes the list before the answer, again until the list shows the row
# the request must leave (Nh.want; Nh.settled), and answers failed when
# none does within Nh.settle_ms. So the state `vk8s list` prints is right
# as soon as create, pause, resume or delete returns.
law nodehost.want:
  {[ N.Nh.want(N.Up{"demo", 1, False{}}), N.Nh.want(N.Join{"demo", 1, 2, "abcdef.0123456789abcdef"}),
     N.Nh.want(N.Down{"demo", 1, [1, 2]}), N.Nh.want(N.Freeze{"pause", "demo", [1]}),
     N.Nh.want(N.Freeze{"resume", "demo", [1]}), N.Nh.want(N.Bad{}) ]
   == [ N.Want{"vk8s-demo-0", "running"}, N.Want{"vk8s-demo-2", "running"}, N.Want{"vk8s-demo-0", "stopped"},
        N.Want{"vk8s-demo-0", "paused"}, N.Want{"vk8s-demo-0", "running"}, N.Want{"", "stopped"} ] : List<&2, N.Want>}

# up: not while the new cluster has no row (the race), nor while runc
# has only created the container; once it runs.
law nodehost.settled_up:
  {[ N.Nh.settled(N.Up{"demo", 1, False{}}, "ID              PID   STATUS    BUNDLE   CREATED   OWNER\nvk8s-other-0    700   running   /a       2026      root\n"),
     N.Nh.settled(N.Up{"demo", 1, False{}}, "ID              PID   STATUS    BUNDLE   CREATED   OWNER\nvk8s-demo-0     812   created   /b       2026      root\n"),
     N.Nh.settled(N.Up{"demo", 1, False{}}, "ID              PID   STATUS    BUNDLE   CREATED   OWNER\nvk8s-other-0    700   running   /a       2026      root\nvk8s-demo-0     812   running   /b       2026      root\n"),
     N.Nh.settled(N.Up{"demo", 1, False{}}, "") ]
   == [False{}, False{}, True{}, False{}] : List<&2, Bool>}

# join: the worker's own row, not the control plane's.
law nodehost.settled_join:
  {[ N.Nh.settled(N.Join{"demo", 1, 1, "abcdef.0123456789abcdef"}, "ID              PID   STATUS    BUNDLE   CREATED   OWNER\nvk8s-demo-0     812   running   /b       2026      root\n"),
     N.Nh.settled(N.Join{"demo", 1, 1, "abcdef.0123456789abcdef"}, "ID              PID   STATUS    BUNDLE   CREATED   OWNER\nvk8s-demo-0     812   running   /b       2026      root\nvk8s-demo-1     900   running   /c       2026      root\n") ]
   == [False{}, True{}] : List<&2, Bool>}

# down: once the control plane's row is gone (or runc calls it stopped).
law nodehost.settled_down:
  {[ N.Nh.settled(N.Down{"demo", 1, []}, "ID              PID   STATUS    BUNDLE   CREATED   OWNER\nvk8s-demo-0     812   running   /b       2026      root\n"),
     N.Nh.settled(N.Down{"demo", 1, []}, "ID              PID   STATUS    BUNDLE   CREATED   OWNER\nvk8s-demo-0     0     stopped   /b       2026      root\n"),
     N.Nh.settled(N.Down{"demo", 1, []}, "ID              PID   STATUS    BUNDLE   CREATED   OWNER\nvk8s-other-0    700   running   /a       2026      root\n") ]
   == [False{}, True{}, True{}] : List<&2, Bool>}

# pause and resume: the control plane's row says so.
law nodehost.settled_freeze:
  {[ N.Nh.settled(N.Freeze{"pause", "demo", []}, "ID              PID   STATUS    BUNDLE   CREATED   OWNER\nvk8s-demo-0     812   running   /b       2026      root\n"),
     N.Nh.settled(N.Freeze{"pause", "demo", []}, "ID              PID   STATUS    BUNDLE   CREATED   OWNER\nvk8s-demo-0     812   paused    /b       2026      root\n"),
     N.Nh.settled(N.Freeze{"resume", "demo", []}, "ID              PID   STATUS    BUNDLE   CREATED   OWNER\nvk8s-demo-0     812   paused    /b       2026      root\n"),
     N.Nh.settled(N.Freeze{"resume", "demo", []}, "ID              PID   STATUS    BUNDLE   CREATED   OWNER\nvk8s-demo-0     812   running   /b       2026      root\n") ]
   == [False{}, True{}, False{}, True{}] : List<&2, Bool>}

law nodehost.settle_ms:
  {N.Nh.settle_ms() == 30000 : U32}

# Proposed: the node host's directory goes with the last container
# cluster, as vcluster's docker driver removes a cluster's container and
# its volumes (pkg/cli/delete_docker.go, deleteDocker.delete:
# stopContainer, removeContainer, then removeVolume, `docker volume rm`,
# of each of the control plane's and the workers' volumes). The node host's data disk is the VM's
# containerd store; nothing else gives it back. Delete stops the VMM
# when no container cluster is left and it serves or its process lives
# (left, running, alive):
law nodehost.stop_due:
  {[ N.Nh.stop_due(False{}, True{}, True{}), N.Nh.stop_due(False{}, False{}, True{}), N.Nh.stop_due(False{}, False{}, False{}),
     N.Nh.stop_due(True{}, True{}, True{}), N.Nh.stop_due(True{}, False{}, False{}) ]
   == [True{}, True{}, False{}, False{}, False{}] : List<&2, Bool>}

# and removes the directory only when none is left (read again once the
# VMM stopped) and no VMM process lives:
law nodehost.reclaim:
  {N.Nh.reclaim(False{}, False{}) == True{} : Bool}

# never under a live VMM (one that did not stop keeps its disk),
law nodehost.reclaim_live:
  for left: Bool
  {N.Nh.reclaim(left, True{}) == False{} : Bool}

# never while a container cluster is left (another, or a create's
# reservation).
law nodehost.reclaim_left:
  for alive: Bool
  {N.Nh.reclaim(True{}, alive) == False{} : Bool}

# The directory is renamed beside itself first (one rename), then removed.
law nodehost.gone_dir:
  {N.Nh.gone_dir("/Users/me") == "/Users/me/.vk8s/nodehost.gone" : String}

# Proposed: a down request is a cluster's delete, so the node host gives
# each node the grace vcluster's docker driver gives a container it
# deletes (pkg/cli/delete_docker.go, stopContainer:
# `args := []string{"stop", "-t=1", containerName}`): one second after
# the stop request (Nh.stop_pre), then the kill.
law nodehost.delete_ms:
  {N.Nh.delete_ms() == 1000 : U32}

law nodehost.kill_steps:
  {N.Nh.kill("/r", "demo", 1) ==
    [P.Run{"/r", ["--root", "/run/vk8s/runc", "kill", "vk8s-demo-1", "KILL"]}] : +List<P.Step>}


# Proposed: the last container cluster's delete does not ask the node
# host to take its containers down first: the VM stops next and takes
# them with it, with the same grace (docs/ref/bench-round1.md: the
# request and the stop each waited, 4.8 s for a delete). Another cluster
# there (two NODEHOST=1 lines, the deleted one's and another's) keeps
# the request:
law nodehost.others:
  {[ N.Nh.others("NODEHOST=1\n"), N.Nh.others("NODEHOST=1\nNODEHOST=1\n"), N.Nh.others(""),
     N.Nh.others("NODEHOST=1\nNODEHOST=0\n") ]
   == [False{}, True{}, False{}, False{}] : List<&2, Bool>}

# (others, running):
law nodehost.down_first:
  {[ N.Nh.down_first(True{}, True{}), N.Nh.down_first(False{}, True{}), N.Nh.down_first(True{}, False{}) ]
   == [True{}, False{}, False{}] : List<&2, Bool>}

# and a create that reserved the node host meanwhile keeps the VM, so
# the request goes then (others, running, stop):
law nodehost.down_late:
  {[ N.Nh.down_late(False{}, True{}, False{}), N.Nh.down_late(False{}, True{}, True{}),
     N.Nh.down_late(True{}, True{}, False{}), N.Nh.down_late(False{}, False{}, False{}) ]
   == [True{}, False{}, False{}, False{}] : List<&2, Bool>}

# Proposed: the node host's chores without the log trim (docs/GOAL.md
# section 11, "Fewer shell-outs": PID 1 trims the logs itself, with no
# shell). The periods are those of nodehost.chores_v2_*: the clock every
# 10 ticks, fstrim every 600; the trim's tick (60) leaves only the clock.
law nodehost.chores_v3_none:
  {N.Nh.chores.v3(15) == [] : +List<P.Step>}

law nodehost.chores_v3_clock:
  {N.Nh.chores.v3(30) == [P.Plan.clock_sync()] : +List<P.Step>}

law nodehost.chores_v3_trim_tick:
  {N.Nh.chores.v3(60) == [P.Plan.clock_sync()] : +List<P.Step>}

law nodehost.chores_v3_all:
  {N.Nh.chores.v3(600) == [P.Plan.clock_sync(), P.Plan.fstrim()] : +List<P.Step>}

# Proposed: the shared layer store in the node host (docs/STATUS.md,
# "Shared assets and layers off the VM", the macOS node host; vk8s's own
# design, nothing of vcluster's). Facts from outside, cited where used:
# bend-vmm's NAT gives a guest the host's loopback at 10.0.2.2 (bend-vmm
# README; layers_ask.host_v2); the kernel lists a block device in
# /proc/partitions only while it has sectors (block/genhd.c,
# show_partition: `if (!bdev_nr_sectors(part)) continue;`), and a loop
# device has none until a file backs it; /proc/mounts is "device mount
# point type options dump pass" (proc(5)).
#
# A create asks for the store unless VK8S_LAYERS=0, as for a node
# container on a Linux host (ctr.layers_on_v2):
law nodehost.layers_on:
  {[N.Nh.layers_on(""), N.Nh.layers_on("1"), N.Nh.layers_on("0"), N.Nh.layers_on("yes")] == [True{}, True{}, False{}, True{}] : List<&2, Bool>}

# and its nodes use it only when the running node host mounted the
# store, which its PID 1 says in a file on its share before it says
# ready (a PID 1 from guest assets older than the store writes no such
# file, and would refuse the request's new word):
law nodehost.layers_mark:
  {[N.Nh.layers_file(), N.Nh.layers_ack(), N.Nh.layers_mark(True{}), N.Nh.layers_mark(False{})] ==
    ["layers", "/var/lib/vk8s-host/layers", "1\n", "0\n"] : +List<String>}

# PID 1 mounts the store between the two parts of its boot plan, which
# together are the plan of before (nodehost.boot): the ready marker
# still comes last, now after the store's file.
law nodehost.boot_parts:
  {List.append(&2, P.Step, N.Nh.boot_head(["node", "control-plane"]), N.Nh.boot_tail()) == N.Nh.boot(["node", "control-plane"]) : +List<P.Step>}

law nodehost.boot_tail:
  {N.Nh.boot_tail() == [P.Write{"/var/lib/vk8s-host/ready", "ok\n"}, P.Log{"vk8s: node host ready"}] : +List<P.Step>}

law nodehost.layers_use:
  {[ N.Nh.layers_use("", "1\n"), N.Nh.layers_use("1", "1\n"), N.Nh.layers_use("0", "1\n"), N.Nh.layers_use("", "0\n"),
     N.Nh.layers_use("", ""), N.Nh.layers_use("1", "") ]
   == [True{}, True{}, False{}, False{}, False{}, False{}] : List<&2, Bool>}

law nodehost.layers_use_mark:
  for on: Bool
  {N.Nh.layers_use("", N.Nh.layers_mark(on)) == on : Bool}

# Create says where the store is, or that the node host that runs
# already has none (its shares are fixed when it starts), and nothing
# when it does not ask for the store.
law nodehost.layers_say:
  {[ N.Nh.layers_say("", "1\n", "/h/.vk8s/layers"), N.Nh.layers_say("", "0\n", "/h/.vk8s/layers"), N.Nh.layers_say("0", "1\n", "/h/.vk8s/layers") ] ==
    [ "Shared layer store: /h/.vk8s/layers (VK8S_LAYERS=0 turns it off), shared read-only into the node host VM and bound into every node container",
      "The node host VM runs without the shared layer store (it started without one, or from older guest assets); these nodes unpack their layers themselves. "
        ++ "It starts with the store once the other container clusters are deleted (the node host stops with the last)",
      "" ] : +List<String>}

# Proposed: the store is shared into the VM once, at its start: the share
# a VM node gets (cli.with_layers: after the VM's own share, tagged
# layers, read-only, with bend-vmm's meta mode) and VK8S_LAYERS=1 on the
# kernel command line.
law nodehost.flags_v2_on:
  {N.Nh.flags.v2(True{}, "/h/.vk8s/layers", N.Nh.flags("/h/.vk8s/nodehost", "/a", 6144, 2)) ==
    [ "--kernel", "/a/Image",
      "--initrd", "/a/vk8s.cpio",
      "--disk", "/a/assets.img:ro:nocache,/h/.vk8s/nodehost/data.img",
      "--share", "/h/.vk8s/nodehost/share,quota=1G",
      "--share", "/h/.vk8s/layers,tag=layers,meta,ro",
      "--console-log", "/h/.vk8s/nodehost/console.log,max=64M,keep=2",
      "--mem", "6144",
      "--cpus", "2",
      "--forward", N.Nh.forwards(),
      "--control", "/h/.vk8s/nodehost/ctl.sock",
      "--cmdline", "console=ttyAMA0 quiet panic=5 VK8S_ROLE=node-host VK8S_NAME=vk8s-nodehost VK8S_LAYERS=1",
      "--balloon", "auto" ] : +List<String>}

# Off (VK8S_LAYERS=0 when the node host starts), the flags are the ones
# before.
law nodehost.flags_v2_off:
  for +store: String
  for flags: +List<String>
  {N.Nh.flags.v2(False{}, store, flags) == flags : +List<String>}

# PID 1 mounts it where a VM node mounts its own, read-only and nosuid
# (plan.layers_store_mount_v4), and nothing without the share.
law nodehost.layers_mount:
  {[N.Nh.layers_mount(True{}), N.Nh.layers_mount(False{})] ==
    [[P.Mount{"9p", "layers", "/mnt/layers-store", "trans=virtio,version=9p2000.L,msize=524288,ro,nosuid"}], []] : List<&2, +List<P.Step>>}

law nodehost.layers_store:
  {N.Nh.layers_store() == "/mnt/layers-store" : String}

# Proposed: a node on the store gets its switch and the filler's address:
# the Mac's loopback as every guest of bend-vmm reaches it, which the
# node's default route (the bridge, then the VM's NAT, through the
# masquerade of nodehost.rules.v2) leads to. Naming the address is what
# makes the node not wait for a fill (layers_ask.nowait_v4).
law nodehost.layers_env_on:
  {N.Nh.layers_env(True{}, ["VK8S_NAME=demo"]) == ["VK8S_NAME=demo", "VK8S_LAYERS=1", "VK8S_LAYERS_ASK=10.0.2.2"] : +List<String>}

law nodehost.layers_env_off:
  for env: +List<String>
  {N.Nh.layers_env(False{}, env) == env : +List<String>}

law nodehost.layers_env_nowait:
  {[LA.Ask.host.v3("10.0.2.2"), LA.Ask.host.v2()] == ["10.0.2.2", "10.0.2.2"] : +List<String>}

law nodehost.layers_env_nowait_on:
  {LA.Ask.nowait.v4("10.0.2.2") == True{} : Bool}

# Proposed: without the store a node's steps, and so a cluster's, are
# the ones before (VM-mode clusters never run them; a container cluster
# made with VK8S_LAYERS=0, or in a node host without the share, runs
# these).
law nodehost.node_v2_off:
  {N.Nh.node.v2(N.Tools{"/ip", "/cpio", "/ipt", "/runc"}, "demo", 3, 1, "amd64", ["A=1"], False{}) ==
    N.Nh.node(N.Tools{"/ip", "/cpio", "/ipt", "/runc"}, "demo", 3, 1, "amd64", ["A=1"]) : +List<P.Step>}

law nodehost.up_v2_off:
  {N.Nh.up.v2(N.Tools{"/ip", "/cpio", "/ipt", "/runc"}, "demo", 3, True{}, "arm64", False{}) ==
    N.Nh.up(N.Tools{"/ip", "/cpio", "/ipt", "/runc"}, "demo", 3, True{}, "arm64") : +List<P.Step>}

law nodehost.join_v2_off:
  {N.Nh.join.v2(N.Tools{"/ip", "/cpio", "/ipt", "/runc"}, "demo", 3, 2, "abcdef.0123456789abcdef", "arm64", False{}) ==
    N.Nh.join(N.Tools{"/ip", "/cpio", "/ipt", "/runc"}, "demo", 3, 2, "abcdef.0123456789abcdef", "arm64") : +List<P.Step>}

# Proposed: with the store, only the node's config.json differs (the
# fifth step of a node): it binds the VM's mount of the store and the
# VM's /dev, as a node container on a Linux host binds the host's
# (ctr.json_v2_on, container.layers_mounts), and PID 1's environment
# has nodehost.layers_env_on after the arch.
law nodehost.node_v2_on_config:
  {List.get(&2, P.Step, N.Nh.node.v2(N.Tools{"/ip", "/cpio", "/ipt", "/runc"}, "demo", 3, 1, "amd64", ["A=1"], True{}), 4n) ==
    Some{P.Write{"/var/lib/vcluster/nodehost/clusters/demo/nodes/worker-1/bundle/config.json",
      R.Ctr.json.v2(C.Spec{"demo", "demo-worker-1", "/var/lib/vcluster/nodehost/clusters/demo/nodes/worker-1/bundle/rootfs",
        "/var/lib/vcluster/nodehost/clusters/demo/nodes/worker-1/data", "/var/lib/vk8s-host/clusters/demo/nodes/worker-1/share",
        "/nodehost/assets", ["A=1", "VK8S_ARCH=amd64", "VK8S_LAYERS=1", "VK8S_LAYERS_ASK=10.0.2.2"]},
        "/run/netns/vk8s-demo-1", True{}, "/mnt/layers-store")}} : Maybe<&2, P.Step>}

law nodehost.node_v2_on_before:
  {List.take(&2, P.Step, N.Nh.node.v2(N.Tools{"/ip", "/cpio", "/ipt", "/runc"}, "demo", 3, 1, "amd64", ["A=1"], True{}), 4n) ==
    List.take(&2, P.Step, N.Nh.node(N.Tools{"/ip", "/cpio", "/ipt", "/runc"}, "demo", 3, 1, "amd64", ["A=1"]), 4n) : +List<P.Step>}

law nodehost.node_v2_on_after:
  {List.drop(&2, P.Step, N.Nh.node.v2(N.Tools{"/ip", "/cpio", "/ipt", "/runc"}, "demo", 3, 1, "amd64", ["A=1"], True{}), 5n) ==
    List.drop(&2, P.Step, N.Nh.node(N.Tools{"/ip", "/cpio", "/ipt", "/runc"}, "demo", 3, 1, "amd64", ["A=1"]), 5n) : +List<P.Step>}

# Proposed: the store adds no rule and no step before the control
# plane's node: a cluster's first 17 steps (the log line, the bridge's 3,
# the 7 rules of nodehost.rules.v2, the cgroups' 6) are the same with
# and without it, so delete (nodehost.unrules.v2, unchanged) still names
# every rule up made. On a Linux host the store needs three rules
# (ctr.layers_rules_on), because the filler listens on a loopback no
# container routes to; here the Mac's loopback has an address.
law nodehost.up_v2_on_rules:
  {List.take(&2, P.Step, N.Nh.up.v2(N.Tools{"/ip", "/cpio", "/ipt", "/runc"}, "demo", 3, False{}, "arm64", True{}), 17n) ==
    List.take(&2, P.Step, N.Nh.up(N.Tools{"/ip", "/cpio", "/ipt", "/runc"}, "demo", 3, False{}, "arm64"), 17n) : +List<P.Step>}

law nodehost.up_v2_on_node:
  {List.drop(&2, P.Step, N.Nh.up.v2(N.Tools{"/ip", "/cpio", "/ipt", "/runc"}, "demo", 3, False{}, "arm64", True{}), 17n) ==
    N.Nh.node.v2(N.Tools{"/ip", "/cpio", "/ipt", "/runc"}, "demo", 3, 0, "arm64",
      ["PATH=" ++ P.Plan.path(), "VK8S_BACKEND=container", "VK8S_NAME=demo", "VK8S_PORT=6443", "VK8S_STORE=sqlite", "VK8S_NODE_IP=10.10.3.2"],
      True{}) : +List<P.Step>}

# Proposed: the store is a cluster's own choice, carried by its up and
# join requests as a last word; without it the request is the one before
# (nodehost.requests).
law nodehost.requests_v2:
  {[ N.Nh.req_up.v2("demo", 3, False{}, True{}), N.Nh.req_up.v2("demo", 3, True{}, False{}),
     N.Nh.req_join.v2("demo", 3, 2, "abcdef.0123456789abcdef", True{}), N.Nh.req_join.v2("demo", 3, 2, "abcdef.0123456789abcdef", False{}) ] ==
    [ "up demo 3 sqlite layers", "up demo 3 etcd", "join demo 3 2 abcdef.0123456789abcdef layers",
      "join demo 3 2 abcdef.0123456789abcdef" ] : +List<String>}

law nodehost.parse_v2_layers:
  {[ N.Nh.parse.v2(["up", "demo", "3", "etcd", "layers"]), N.Nh.parse.v2(["join", "demo", "3", "2", "abcdef.0123456789abcdef", "layers"]) ] ==
    [ N.Req{True{}, N.Up{"demo", 3, True{}}}, N.Req{True{}, N.Join{"demo", 3, 2, "abcdef.0123456789abcdef"}} ] : List<&2, N.Req>}

# Without the word, every request reads as before.
law nodehost.parse_v2_plain:
  {[ N.Nh.parse.v2(["up", "demo", "3", "sqlite"]), N.Nh.parse.v2(["join", "demo", "3", "2", "abcdef.0123456789abcdef"]),
     N.Nh.parse.v2(["down", "demo", "3", "1,2"]), N.Nh.parse.v2(["pause", "demo", "1"]), N.Nh.parse.v2(["up", "layers", "3", "sqlite"]) ] ==
    [ N.Req{False{}, N.Up{"demo", 3, False{}}}, N.Req{False{}, N.Join{"demo", 3, 2, "abcdef.0123456789abcdef"}},
      N.Req{False{}, N.Down{"demo", 3, [1, 2]}}, N.Req{False{}, N.Freeze{"pause", "demo", [1]}},
      N.Req{False{}, N.Up{"layers", 3, False{}}} ] : List<&2, N.Req>}

# Only up and join take the word; the word on anything else, on a bad
# request, twice, or alone is refused.
law nodehost.parse_v2_bad:
  {[ N.Nh.parse.v2(["down", "demo", "3", "-", "layers"]), N.Nh.parse.v2(["pause", "demo", "-", "layers"]),
     N.Nh.parse.v2(["up", "demo", "17", "etcd", "layers"]), N.Nh.parse.v2(["up", "demo", "3", "etcd", "layers", "layers"]),
     N.Nh.parse.v2(["layers"]), N.Nh.parse.v2([]) ] ==
    [ N.Req{False{}, N.Bad{}}, N.Req{False{}, N.Bad{}}, N.Req{False{}, N.Bad{}}, N.Req{False{}, N.Bad{}},
      N.Req{False{}, N.Bad{}}, N.Req{False{}, N.Bad{}} ] : List<&2, N.Req>}

# The request's answer follows the same row of runc's list
# (nodehost.want), and its nodes use the store only when the VM mounted
# the share.
law nodehost.req_op:
  {N.Nh.want(N.Nh.req_op(N.Nh.parse.v2(["up", "demo", "3", "etcd", "layers"]))) == N.Want{"vk8s-demo-0", "running"} : N.Want}

law nodehost.req_on:
  {[ N.Nh.req_on(N.Req{True{}, N.Up{"demo", 3, True{}}}, True{}), N.Nh.req_on(N.Req{True{}, N.Up{"demo", 3, True{}}}, False{}),
     N.Nh.req_on(N.Req{False{}, N.Up{"demo", 3, True{}}}, True{}) ] == [True{}, False{}, False{}] : List<&2, Bool>}

# Proposed: the filler's gc reads what the node host's nodes hold where
# the Mac reads their shares (nodehost.paths): a node's layers.held is
# on its share.
law nodehost.held_root:
  {[ N.Nh.held_root("/h/.vk8s") ++ "/demo/share", N.Nh.held_root("/h/.vk8s") ++ "/demo/nodes/worker-2/share" ] ==
    [ N.Nh.share(N.Nh.dir("/h"), "demo", 0), N.Nh.share(N.Nh.dir("/h"), "demo", 2) ] : +List<String>}

# Proposed: what a cluster's delete left in the VM, which PID 1 says
# after each down request. A node's layer mounts are in its container's
# mount namespace, so they are not in the VM's /proc/mounts at all; what
# could stay there is a node's network namespace (ip netns add mounts
# it at /run/netns/<name>) or a mount under the cluster's directories.
# Cluster a's are a's only: "vk8s-a-b-0" is cluster a-b's namespace.
law nodehost.mounts_left:
  {N.Nh.mounts_left("rootfs / tmpfs rw 0 0\nlayers /mnt/layers-store 9p ro,nosuid 0 0\nnsfs /run/netns/vk8s-a-0 nsfs rw 0 0\n"
      ++ "nsfs /run/netns/vk8s-a-b-0 nsfs rw 0 0\nnsfs /run/netns/vk8s-a-12 nsfs rw 0 0\n"
      ++ "overlay /var/lib/vcluster/nodehost/clusters/a/bundle/rootfs overlay rw 0 0\n"
      ++ "overlay /var/lib/vcluster/nodehost/clusters/ab/bundle/rootfs overlay rw 0 0\n", "a") ==
    ["/run/netns/vk8s-a-0", "/run/netns/vk8s-a-12", "/var/lib/vcluster/nodehost/clusters/a/bundle/rootfs"] : +List<String>}

law nodehost.mounts_left_none:
  {N.Nh.mounts_left("rootfs / tmpfs rw 0 0\nlayers /mnt/layers-store 9p ro,nosuid 0 0\nnsfs /run/netns/vk8s-b-0 nsfs rw 0 0\n", "a") == [] : +List<String>}

# Its rules are the ones tagged with its name, in both tables
# (ctr.undo reads the tag as a whole word: vk8s:a is not vk8s:ab).
law nodehost.rules_left:
  {[ N.Nh.rules_left("a", "-P PREROUTING ACCEPT\n-A PREROUTING -i eth0 -p tcp -m tcp --dport 16401 -m comment --comment vk8s:a -j DNAT --to-destination 10.10.1.2:6443\n-A POSTROUTING -s 10.10.2.0/24 ! -o vk8sbr2 -m comment --comment vk8s:ab -j MASQUERADE\n",
       "-P FORWARD ACCEPT\n-A FORWARD -i vk8sbr1 -m comment --comment vk8s:a -j ACCEPT\n-A FORWARD -o vk8sbr1 -m comment --comment vk8s:a -j ACCEPT\n"),
     N.Nh.rules_left("a", "-P PREROUTING ACCEPT\n-A POSTROUTING -s 10.10.2.0/24 ! -o vk8sbr2 -m comment --comment vk8s:ab -j MASQUERADE\n", "-P FORWARD ACCEPT\n") ]
   == [3, 0] : List<&2, U32>}

law nodehost.list_rules:
  {N.Nh.list_rules("nat") == ["-t", "nat", "-S"] : +List<String>}

# The loop devices in use in the whole VM: each layer a node has mounted
# from the store holds one, so the count falls by a deleted cluster's.
law nodehost.loops:
  {[ N.Nh.loops("major minor  #blocks  name\n\n 254        0     262144 vda\n   7        0      21504 loop0\n   7        3        512 loop3\n 254       16   16777216 vdb\n"),
     N.Nh.loops("major minor  #blocks  name\n\n 254        0     262144 vda\n"), N.Nh.loops("") ] == [2, 0, 0] : List<&2, U32>}

law nodehost.after:
  {[ N.Nh.after("a", [], 0, 7), N.Nh.after("a", ["/run/netns/vk8s-a-0", "/x"], 2, 0) ] ==
    [ "node host: after a: no mount and 0 rules of it left, 7 loop devices in use",
      "node host: after a: mounts /run/netns/vk8s-a-0 /x and 2 rules of it left, 0 loop devices in use" ] : +List<String>}
