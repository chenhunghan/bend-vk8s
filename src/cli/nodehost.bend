import Base
import ../guest/plan.bend as P
import ../guest/container.bend as C
import ./ctr.bend as R
import ./cli.bend as CL

# Container mode on macOS (docs/GOAL.md section 8; docs/ref/
# explore-linux-hosts.md Phase 6 C4 and D11 a), pure: every name, port,
# flag, step and message of the shared bend-vmm "node host" VM.
#
# macOS has no Linux kernel, so `vk8s create --backend container` there
# starts (or reuses) one bend-vmm VM, the node host, and the Linux
# container driver runs inside it: its PID 1 (role node-host,
# host/init.bend) runs the steps below, which src/cli/ctr.bend's names,
# addresses and argument lists make, as host/vk8s.bend's Vk8s.ctr.* runs
# them on a Linux host. One guest kernel and page cache serve every node
# of every container cluster.
#
# - The Mac talks to the node host's PID 1 through the VM's share
#   (~/.vk8s/nodehost/share, /var/lib/vk8s-host in the VM) with the
#   request channel the cluster VMs use (P.Plan.requests_dir): the Mac
#   writes "ID ACTION ARGS" to requests/request, PID 1 runs the action
#   and answers "ID done" or "ID failed" in requests/response.
# - Each node's share is on the VM's share too (clusters/<cluster>[/nodes/
#   worker-<i>]/share), so the Mac reads the kubeconfig, the join token
#   and the joined marker where it reads them from a VM node. Its root
#   file system and data dir are on the VM's ext4 data disk (containerd's
#   overlayfs snapshotter needs ext4 or xfs).
# - bend-vmm's forwards are fixed at start and at most 16
#   (bend-vmm README: "repeatable, at most 16"), so the node host
#   forwards 16 ports, 127.0.0.1:16401..16416 on the Mac to the same
#   ports in the VM, at start (D11 a). Cluster k (slot 1..16) has port
#   16400 + k; a DNAT rule in the VM, tagged like the cluster's other
#   rules, sends it to its control plane's 10.10.k.2:6443. So at most 16
#   container clusters run on a Mac at once.
# - Delete stops the cluster's containers, then the node host when no
#   container cluster is left on the Mac, and then removes the node
#   host's directory, its data disk with it (Nh.stop_due, Nh.reclaim).
# - PID 1 answers a request once runc's list on the share shows its
#   effect (Nh.settled), so `vk8s list` is right when the command returns.

# --- Where and when

# Whether `--backend container` runs in the node-host VM: on macOS, and
# on Linux when VK8S_NODE_HOST=vm asks for it (to test the macOS path on
# a Linux host with KVM).
def Nh.use_vm(+os: String, +env: String) -> Bool:
  String.eq(os, "Darwin") || String.eq(env, "vm")

def Nh.dir(+home: String) -> String:
  home ++ "/.vk8s/nodehost"

# The most container clusters a node host runs: one forward each.
def Nh.max() -> U32:
  16

# Cluster k's API port, on the Mac's loopback and in the VM.
def Nh.port(+k: U32) -> U32:
  (16400 + k : U32)

def Nh.slot.go(n: Nat, +k: U32, +used: List<&2, U32>) -> U32:
  match n:
    case 0n:
      0
    case 1n+p:
      R.Ctr.slot.pick(R.Ctr.has(used, k), k, Nh.slot.go(p, (k + 1 : U32), used))

# The lowest slot (1..16) no container cluster holds; 0 when every slot
# is taken.
def Nh.slot(+used: List<&2, U32>) -> U32:
  Nh.slot.go(16n, 1, used)

def Nh.forward(+k: U32) -> String:
  "127.0.0.1:" ++ U32.show(Nh.port(k)) ++ ":" ++ U32.show(Nh.port(k))

def Nh.forwards.go(n: Nat, +k: U32) -> String:
  match n:
    case 0n:
      ""
    case 1n+p:
      "," ++ Nh.forward(k) ++ Nh.forwards.go(p, (k + 1 : U32))

# bend-vmm's --forward value: every slot's port.
def Nh.forwards() -> String:
  Nh.forward(1) ++ Nh.forwards.go(15n, 2)

# The node host's memory (MiB) and vCPUs: every node of every container
# cluster shares them; bend-vmm's balloon gives free pages back. Sized
# for one cluster no heavier than VM mode (laws nodehost.defaults): 2
# vCPUs (each idle vCPU costs host CPU to wake and park; one guest kernel
# serves every node), and 6144 MiB, the RAM a 2-worker cluster gets in VM
# mode. bend-vmm's auto balloon keeps max(256 MiB, RAM/10) free and holds
# at most half of RAM (docs/ref/footprint-decisions.md M1), so the 8192
# MiB of before let the guest keep 4 GiB. The node host is sized when it
# starts, with the first container cluster: for many clusters set
# VK8S_NODE_HOST_MEMORY and VK8S_NODE_HOST_CPUS before that.
def Nh.mem() -> U32:
  6144

def Nh.cpus() -> U32:
  2

# bend-vmm flags for the node host (~/.vk8s/nodehost), before the asset
# sets and the arch go in (CL.Cli.role_flags, CL.Cli.arch_flags), as for
# the image cache VM (CL.Cli.cache_flags).
def Nh.flags(+dir: String, +assets: String, +mem: U32, +cpus: U32) -> +List<String>:
  List.append(&2, String,
  [ "--kernel", assets ++ "/Image",
    "--initrd", assets ++ "/vk8s.cpio",
    "--disk", assets ++ "/assets.img:ro:nocache," ++ dir ++ "/data.img",
    "--share", dir ++ "/share,quota=" ++ CL.Cli.share_quota(),
    "--console-log", dir ++ "/console.log,max=64M,keep=2",
    "--mem", U32.show(mem),
    "--cpus", U32.show(cpus),
    "--forward", Nh.forwards(),
    "--control", dir ++ "/ctl.sock",
    "--cmdline", "console=ttyAMA0 quiet panic=5 VK8S_ROLE=node-host VK8S_NAME=vk8s-nodehost" ],
    CL.Cli.balloon_flags())

# The sets the node host attaches: those of a container cluster on a
# Linux host (R.Ctr.sets: node and control-plane, and the add-on images
# when the assets have them; the node containers do not use the image
# cache, C.Container drops its mirrors).
def Nh.sets(images: Bool) -> +List<String>:
  R.Ctr.sets(images)

# --- Paths

# A node's directory relative to a clusters root: the cluster's for the
# control plane, nodes/worker-<i> for worker i (R.Ctr.node_dir).
def Nh.rel(+name: String, +i: U32) -> String:
  R.Ctr.node_dir("/clusters/" ++ name, i)

# Node i's share on the Mac (under the node host's share) and in the VM.
def Nh.share(+dir: String, +name: String, +i: U32) -> String:
  dir ++ "/share" ++ Nh.rel(name, i) ++ "/share"

def Nh.vm_share(+name: String, +i: U32) -> String:
  P.Plan.host_dir() ++ Nh.rel(name, i) ++ "/share"

# The Mac's directory that holds node i's share (where Vk8s.join_token
# and Vk8s.wait_file look, as for a VM node's directory).
def Nh.node_dir(+dir: String, +name: String, +i: U32) -> String:
  dir ++ "/share" ++ Nh.rel(name, i)

# The VM's directories: its data disk holds every cluster's nodes.
def Nh.root() -> String:
  P.Plan.data() ++ "/nodehost"

def Nh.vm_dir(+name: String, +i: U32) -> String:
  Nh.root() ++ Nh.rel(name, i)

# The assets the node containers bind (C.Container.mounts): the VM's sets
# and its base disk (stage 0's /assets) joined in one read-only overlay,
# the layout of the single assets.img, as R.Ctr.mount_overlay joins them
# on a Linux host.
def Nh.assets() -> String:
  "/nodehost/assets"

def Nh.lowers(sets: +List<String>) -> +List<String>:
  match sets:
    case Nil{}:
      ["/assets"]
    case Con{+s, t}:
      Con{P.Plan.set_dir(s), Nh.lowers(t)}

# The initramfs the nodes unpack as their root, which the Mac copies onto
# the share before the VM starts.
def Nh.cpio() -> String:
  P.Plan.host_dir() ++ "/vk8s.cpio"

# What PID 1 writes on the share: ready once it serves requests, and
# runc's container list (for `vk8s list`; Nh.list_due).
def Nh.ready() -> String:
  P.Plan.host_dir() ++ "/ready"

def Nh.list_file() -> String:
  P.Plan.host_dir() ++ "/runc-list"

# --- The node host's boot plan (PID 1, role node-host)

# The machine layer of a cluster VM (P.Plan.system, the modules, the
# NAT network as the cache VM has it, the sysctls), the data disk and the
# sets (P.Plan.disks.v3), the share, the nodes' assets overlay, then the
# ready marker. No daemon: the node containers are runc's.
def Nh.boot(+sets: +List<String>) -> +List<P.Step>:
  List.append(&2, P.Step, P.Plan.system(),
  List.append(&2, P.Step, [P.Modules{"/etc/vk8s/modules"}],
  List.append(&2, P.Step, [ P.Plan.bb(["hostname", "vk8s-nodehost"]),
      P.Plan.bb(["ip", "link", "set", "lo", "up"]),
      P.Plan.bb(["ip", "link", "set", "eth0", "up"]),
      P.Plan.bb(["ip", "addr", "add", "10.0.2.15/24", "dev", "eth0"]),
      P.Plan.bb(["ip", "route", "add", "default", "via", "10.0.2.2"]),
      P.Write{"/etc/resolv.conf", "nameserver 10.0.2.3\n"},
      P.Write{"/etc/hosts", "127.0.0.1 localhost vk8s-nodehost\n"} ],
  List.append(&2, P.Step, P.Plan.sysctls(),
  List.append(&2, P.Step, P.Plan.disks.v3(sets),
  List.append(&2, P.Step, [P.Mount{"9p", "share", P.Plan.host_dir(), "trans=virtio,version=9p2000.L"}],
    [ P.Mount{"overlay", "overlay", Nh.assets(), "ro,lowerdir=" ++ String.join(Nh.lowers(sets), ":")},
      P.Plan.bb(["mkdir", "-p", Nh.root(), "/run/vk8s"]),
      P.Write{Nh.ready(), "ok\n"},
      P.Log{"vk8s: node host ready"} ]))))))

# --- The node host's periodic chores (laws nodehost.chores_*)

def Nh.chore(due: Bool, s: P.Step, rest: +List<P.Step>) -> +List<P.Step>:
  match due:
    case True{}:
      Con{s, rest}
    case False{}:
      rest

def Nh.every(+tick: U32, +n: U32) -> Bool:
  U32.is_eq((tick % n : U32), 0)

# The steps PID 1 runs at second `tick`: those of a cluster VM's PID 1
# (host/init.bend Init.supervise), same periods, same order. The node
# containers run none of them (CH.Container.machine_maintenance), so the
# node host does it for all of them: it trims the share's logs (each
# node's runc output is there), sets the clock from the RTC (the
# containers share the VM's clock, which stops while the Mac sleeps),
# trims the data disk (every node's root and data), and gives memory
# back when idle (page cache, then compaction), as cluster VMs do.
def Nh.chores(+tick: U32) -> +List<P.Step>:
  Nh.chore(Nh.every(tick, P.Plan.trim_every_ticks()), P.Plan.trim_logs(),
  Nh.chore(Nh.every(tick, P.Plan.clock_every_ticks()), P.Plan.clock_sync(),
  Nh.chore(P.Plan.fstrim_due(tick), P.Plan.fstrim(),
  Nh.chore(Nh.every(tick, P.Plan.reclaim_every_ticks()), P.Plan.idle_reclaim(),
  Nh.chore(Nh.every(tick, P.Plan.compact_every_ticks()), P.Plan.idle_compact(), [])))))

# The steps of Nh.chores without the memory chores (laws
# nodehost.chores_v2_*): PID 1 now decides idle reclaim and compaction in
# Bend (P.Plan.reclaim_turn, P.Plan.compact_turn) and writes the kernel
# files in the background, as a cluster VM's PID 1 does (host/init.bend
# Init.mem).
def Nh.chores.v2(+tick: U32) -> +List<P.Step>:
  Nh.chore(Nh.every(tick, P.Plan.trim_every_ticks()), P.Plan.trim_logs(),
  Nh.chore(Nh.every(tick, P.Plan.clock_every_ticks()), P.Plan.clock_sync(),
  Nh.chore(P.Plan.fstrim_due(tick), P.Plan.fstrim(), [])))

# The steps of Nh.chores.v2 without the log trim (docs/GOAL.md section
# 11, "Fewer shell-outs"): PID 1 trims the logs itself at the same tick
# (host/init.bend Nhi.trim, host/gsys.bend Gs.trim_logs), with no shell.
# The two steps left are command lines PID 1 runs itself too
# (src/guest/sysop.bend Sysop.of).
def Nh.chores.v3(+tick: U32) -> +List<P.Step>:
  Nh.chore(Nh.every(tick, P.Plan.clock_every_ticks()), P.Plan.clock_sync(),
  Nh.chore(P.Plan.fstrim_due(tick), P.Plan.fstrim(), []))

# runc's list goes to the share every 30 s (host/init.bend Nhi.serve) and
# before each request's answer (Nhi.settled, Nh.settled below); a runc
# process every 5 s cost CPU for nothing.
def Nh.list_every_ticks() -> U32:
  30

def Nh.list_due(+tick: U32) -> Bool:
  Nh.every(tick, Nh.list_every_ticks())

# --- Requests

# The programs the steps run: posix_spawn takes a path, not a name. ip
# and cpio are Debian's (iproute2's ip has netns and veth; GNU cpio has
# -D), found by PID 1 at boot (Nh.candidates); iptables and runc have
# fixed places.
type Tools is Data:
  Tools{ip: String, cpio: String, iptables: String, runc: String}

def Nh.candidates(+prog: String) -> +List<String>:
  ["/usr/bin/" ++ prog, "/usr/sbin/" ++ prog, "/bin/" ++ prog, "/sbin/" ++ prog]

def Nh.iptables() -> String:
  "/usr/sbin/iptables"

def Nh.runc() -> String:
  P.Plan.bin() ++ "/runc"

type Op is Data:
  # the cluster's network, cgroups and control-plane container
  Up{name: String, k: U32, etcd: Bool}
  # worker i's container, joining with token
  Join{name: String, k: U32, i: U32, token: String}
  # stop and remove every node (workers ws, then the control plane) and
  # the cluster's network, rules and cgroups
  Down{name: String, k: U32, ws: List<&2, U32>}
  # runc pause or resume of every node (verb)
  Freeze{verb: String, name: String, ws: List<&2, U32>}
  Bad{}

def Nh.store(+s: String) -> Bool:
  String.eq(s, "etcd")

# A request's list of workers, one word: "1,2,4", or "-" for none.
def Nh.ws(+s: String) -> List<&2, U32>:
  CL.Cli.workers.parse(String.split(s, ','))

def Nh.ws_show.go(ws: List<&2, U32>) -> String:
  match ws:
    case Nil{}:
      ""
    case Con{i, Nil{}}:
      U32.show(i)
    case Con{i, t}:
      U32.show(i) ++ "," ++ Nh.ws_show.go(t)

def Nh.ws_show(ws: List<&2, U32>) -> String:
  match ws:
    case Nil{}:
      "-"
    case Con{i, t}:
      Nh.ws_show.go(Con{i, t})

def Nh.k(+s: String) -> U32:
  CL.Cli.num(U32.read(s), 0)

def Nh.k_ok(+k: U32) -> Bool:
  U32.is_ge(k, 1) && U32.is_le(k, Nh.max())

def Nh.parse.ok(ok: Bool, op: Op) -> Op:
  match ok:
    case True{}:
      op
    case False{}:
      Bad{}

# The request's words: the action's words in the order Nh.req_* writes
# them. A word too few or too many, or a slot outside 1..16, is Bad.
def Nh.parse.up(+name: String, +k: U32, +store: String) -> Op:
  Nh.parse.ok(Nh.k_ok(k) && CL.Cli.valid_name(name), Up{name, k, Nh.store(store)})

def Nh.parse.verb(+v: String, +name: String, +ws: String) -> Op:
  Nh.parse.ok((String.eq(v, "pause") || String.eq(v, "resume")) && CL.Cli.valid_name(name), Freeze{v, name, Nh.ws(ws)})

def Nh.parse.go(up: Bool, join: Bool, down: Bool, ws: +List<String>) -> Op:
  match up join down:
    case True{} _ _:
      match ws:
        case Con{a, Con{+name, Con{+k, Con{+store, Nil{}}}}}:
          Nh.parse.up(name, Nh.k(k), store)
        case _:
          Bad{}
    case False{} True{} _:
      match ws:
        case Con{a, Con{+name, Con{+k, Con{+i, Con{+token, Nil{}}}}}}:
          Nh.parse.ok(Nh.k_ok(Nh.k(k)) && CL.Cli.valid_name(name) && U32.is_ge(Nh.k(i), 1) && CL.Cli.token_ok(token),
            Join{name, Nh.k(k), Nh.k(i), token})
        case _:
          Bad{}
    case False{} False{} True{}:
      match ws:
        case Con{a, Con{+name, Con{+k, Con{+w, Nil{}}}}}:
          Nh.parse.ok(Nh.k_ok(Nh.k(k)) && CL.Cli.valid_name(name), Down{name, Nh.k(k), Nh.ws(w)})
        case _:
          Bad{}
    case False{} False{} False{}:
      match ws:
        case Con{+v, Con{+name, Con{+w, Nil{}}}}:
          Nh.parse.verb(v, name, w)
        case _:
          Bad{}

def Nh.first(ws: +List<String>) -> String:
  match ws:
    case Nil{}:
      ""
    case Con{w, t}:
      w

# An action's words (without the request's ID) as an Op.
def Nh.parse(+ws: +List<String>) -> Op:
  +v = Nh.first(ws)
  Nh.parse.go(String.eq(v, "up"), String.eq(v, "join"), String.eq(v, "down"), ws)

# The actions the Mac sends (Vk8s.request writes "ID ACTION").
def Nh.req_up(+name: String, +k: U32, etcd: Bool) -> String:
  "up " ++ name ++ " " ++ U32.show(k) ++ " " ++ CL.Cli.store_name(etcd)

def Nh.req_join(+name: String, +k: U32, +i: U32, +token: String) -> String:
  "join " ++ name ++ " " ++ U32.show(k) ++ " " ++ U32.show(i) ++ " " ++ token

def Nh.req_down(+name: String, +k: U32, ws: List<&2, U32>) -> String:
  "down " ++ name ++ " " ++ U32.show(k) ++ " " ++ Nh.ws_show(ws)

def Nh.req_freeze(+verb: String, +name: String, ws: List<&2, U32>) -> String:
  verb ++ " " ++ name ++ " " ++ Nh.ws_show(ws)

# --- The steps of each request

def Nh.runs(+prog: String, cs: +List<+List<String>>) -> +List<P.Step>:
  match cs:
    case Nil{}:
      Nil{}
    case Con{c, t}:
      Con{P.Run{prog, c}, Nh.runs(prog, t)}

# Cluster k's API port, sent to its control plane: the forward from the
# Mac arrives on eth0 (bend-vmm's NAT), tagged as the cluster's rules.
def Nh.dnat(+name: String, +k: U32) -> +List<String>:
  ["-t", "nat", "-A", "PREROUTING", "-i", "eth0", "-p", "tcp", "--dport", U32.show(Nh.port(k)), "-m", "comment", "--comment",
    R.Ctr.tag(name), "-j", "DNAT", "--to-destination", R.Ctr.node_ip(k, 0) ++ ":6443"]

# The cluster's host rules (R.Ctr.rules) and its DNAT rule.
def Nh.rules(+name: String, +k: U32) -> +List<+List<String>>:
  Con{Nh.dnat(name, k), R.Ctr.rules(name, k)}

def Nh.undo.word(hit: Bool, +w: String) -> String:
  match hit:
    case True{}:
      "-D"
    case False{}:
      w

def Nh.undo.words(ws: +List<String>) -> +List<String>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{+w, t}:
      Con{Nh.undo.word(String.eq(w, "-A") || String.eq(w, "-I"), w), Nh.undo.words(t)}

def Nh.undo(cs: +List<+List<String>>) -> +List<+List<String>>:
  match cs:
    case Nil{}:
      Nil{}
    case Con{c, t}:
      Con{Nh.undo.words(c), Nh.undo(t)}

# The same rules deleted (-A and -I become -D): the node host's PID 1
# made them all, so delete names them instead of listing the tables.
def Nh.unrules(+name: String, +k: U32) -> +List<+List<String>>:
  Nh.undo(Nh.rules(name, k))

# Nh.rules and the bridge's isolation from the other clusters' bridges
# (R.Ctr.isolate; docs/ref/review-bend-vk8s-pr-49.md finding 2). No -w:
# the node host's PID 1 is the only iptables user in its VM.
def Nh.rules.v2(+name: String, +k: U32) -> +List<+List<String>>:
  List.append(&2, List<&2, String>, Nh.rules(name, k), R.Ctr.isolate(name, k))

def Nh.unrules.v2(+name: String, +k: U32) -> +List<+List<String>>:
  Nh.undo(Nh.rules.v2(name, k))

def Nh.cgroups(ds: +List<String>) -> +List<P.Step>:
  match ds:
    case Nil{}:
      Nil{}
    case Con{+d, t}:
      Con{P.Plan.bb(["mkdir", "-p", d]), Con{C.Container.enable_controllers(d), Nh.cgroups(t)}}

# Node i's container, as Vk8s.ctr.node makes it: its root file system
# (the initramfs), data dir and share, its resolv.conf (the VM's
# resolver) and config.json, its network namespace on the bridge, then
# runc run -d, its output in the share's logs/vk8s-<cluster>-<i>.log.
def Nh.node(t: Tools, +name: String, +k: U32, +i: U32, +arch: String, env: +List<String>) -> +List<P.Step>:
  match t:
    case Tools{+ip, +cpio, +iptables, +runc}:
      +nd = Nh.vm_dir(name, i)
      +bundle = nd ++ "/bundle"
      +rootfs = bundle ++ "/rootfs"
      +share = Nh.vm_share(name, i)
      List.append(&2, P.Step,
        [ P.Plan.bb(["rm", "-rf", nd]),
          P.Plan.bb(["mkdir", "-p", rootfs, nd ++ "/data", share]),
          P.Run{cpio, R.Ctr.unpack(Nh.cpio(), rootfs)},
          P.Write{rootfs ++ "/etc/resolv.conf", R.Ctr.resolv("", "nameserver 10.0.2.3\n")},
          P.Write{bundle ++ "/config.json", R.Ctr.json(C.Spec{name, R.Ctr.node(name, i), rootfs, nd ++ "/data", share, Nh.assets(),
            R.Ctr.arch_env(arch, env)}, R.Ctr.netns_path(name, i))} ],
      List.append(&2, P.Step, Nh.runs(ip, R.Ctr.ip_node(name, k, i)),
        [P.Spawn{R.Ctr.id(name, i), runc, R.Ctr.runc_run(bundle, R.Ctr.id(name, i))}]))

# up: the bridge, the rules (with the isolation), the cgroups, then the
# control plane.
def Nh.up(t: Tools, +name: String, +k: U32, etcd: Bool, +arch: String) -> +List<P.Step>:
  match t:
    case Tools{+ip, +cpio, +iptables, +runc}:
      List.append(&2, P.Step, [P.Log{"vk8s: node host: cluster " ++ name ++ " on " ++ R.Ctr.bridge(k)}],
      List.append(&2, P.Step, Nh.runs(ip, R.Ctr.ip_bridge(k)),
      List.append(&2, P.Step, Nh.runs(iptables, Nh.rules.v2(name, k)),
      List.append(&2, P.Step, Nh.cgroups(R.Ctr.cgroup_dirs(name)),
        Nh.node(Tools{ip, cpio, iptables, runc}, name, k, 0, arch, R.Ctr.env_cp(name, k, 6443, etcd))))))

def Nh.join(t: Tools, +name: String, +k: U32, +i: U32, +token: String, +arch: String) -> +List<P.Step>:
  Nh.node(t, name, k, i, arch, R.Ctr.env_worker(name, k, i, token))

# down, per node: wake it if paused and ask its PID 1 to stop (on its
# share, as Vk8s.ctr.stop does); the node host's PID 1 then waits until
# the node's cgroup is empty (Nh.events) for Nh.delete_ms, kills what is
# left (Nh.kill, then up to Nh.kill_ms for the cgroup to empty), then the
# rest. Only delete sends a down request (pause and resume freeze and
# thaw, Nh.freeze), so no node's data outlives it.
def Nh.stop_pre(+runc: String, +name: String, +i: U32) -> +List<P.Step>:
  [ P.Run{runc, R.Ctr.runc(["resume", R.Ctr.id(name, i)])},
    P.Write{Nh.vm_share(name, i) ++ "/stop", "stop\n"} ]

def Nh.stop_post(+ip: String, +runc: String, +name: String, +i: U32) -> +List<P.Step>:
  [ P.Run{runc, R.Ctr.runc(["kill", R.Ctr.id(name, i), "KILL"])},
    P.Run{runc, R.Ctr.runc(["delete", "-f", R.Ctr.id(name, i)])},
    P.Run{ip, R.Ctr.ip_node_del(name, i)},
    P.Plan.bb(["rm", "-rf", Nh.vm_dir(name, i)]) ]

# The grace of a node on delete: vcluster's `docker stop -t=1`
# (R.Ctr.delete_ms).
def Nh.delete_ms() -> U32:
  R.Ctr.delete_ms()

# The node's PID 1 killed: every process of the node goes with its PID
# namespace.
def Nh.kill(+runc: String, +name: String, +i: U32) -> +List<P.Step>:
  [P.Run{runc, R.Ctr.runc(["kill", R.Ctr.id(name, i), "KILL"])}]

def Nh.kill_ms() -> U32:
  R.Ctr.kill_ms()

# The node's cgroup.events (populated 0 once every process is gone).
def Nh.events(+name: String, +i: U32) -> String:
  "/sys/fs/cgroup" ++ C.Container.cgroup_path(name, R.Ctr.node(name, i)) ++ "/cgroup.events"

def Nh.populated.lines(ls: List<&2, String>) -> Bool:
  match ls:
    case Nil{}:
      False{}
    case Con{+l, t}:
      String.eq(String.trim(l), "populated 1") || Nh.populated.lines(t)

# Whether a cgroup.events text says the cgroup still holds a process (a
# cgroup that is gone reads as empty text: not populated).
def Nh.populated(text: String) -> Bool:
  Nh.populated.lines(String.lines(text))

# down, once every node is gone: the rules, the bridge, the cgroups and
# the cluster's directories in the VM and on the share.
def Nh.down(+ip: String, +iptables: String, +name: String, +k: U32) -> +List<P.Step>:
  List.append(&2, P.Step, Nh.runs(iptables, Nh.unrules.v2(name, k)),
    [ P.Run{ip, R.Ctr.ip_bridge_del(k)},
      P.Plan.bb(["find", "/sys/fs/cgroup/vk8s/" ++ name, "-depth", "-type", "d", "-delete"]),
      P.Plan.bb(["rm", "-rf", Nh.vm_dir(name, 0), P.Plan.host_dir() ++ "/clusters/" ++ name]),
      P.Log{"vk8s: node host: cluster " ++ name ++ " removed"} ])

# down, once every node is killed and removed: their veth pairs deleted
# by name (R.Ctr.ip_veths_del; a pair that went with its namespace
# already fails, which is fine).
def Nh.unlink(+ip: String, +k: U32, ws: List<&2, U32>) -> +List<P.Step>:
  Nh.runs(ip, R.Ctr.ip_veths_del(k, List.append(&2, U32, ws, [0])))

def Nh.freeze(+runc: String, +verb: String, +name: String, ws: List<&2, U32>) -> +List<P.Step>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{+i, t}:
      Con{P.Run{runc, R.Ctr.runc([verb, R.Ctr.id(name, i)])}, Nh.freeze(runc, verb, name, t)}

# The nodes of a cluster with workers ws: the workers, then the control
# plane (0), as delete stops them; pause takes the control plane first.
def Nh.nodes(ws: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, ws, [0])

# --- On the Mac

def Nh.left.lines(ls: List<&2, String>) -> Bool:
  match ls:
    case Nil{}:
      False{}
    case Con{+l, t}:
      String.eq(String.trim(l), "NODEHOST=1") || Nh.left.lines(t)

# Whether any cluster still runs in the node host, from the NODEHOST=
# lines of every cluster.env (text).
def Nh.left(text: String) -> Bool:
  Nh.left.lines(String.lines(text))

def Nh.words.keep(empty: Bool, +w: String, rest: List<&2, String>) -> List<&2, String>:
  match empty:
    case True{}:
      rest
    case False{}:
      Con{w, rest}

def Nh.words.go(ws: List<&2, String>) -> List<&2, String>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{+w, t}:
      Nh.words.keep(String.is_empty(w), w, Nh.words.go(t))

# A line's words, split at spaces (runs of them count as one).
def Nh.words(+l: String) -> List<&2, String>:
  Nh.words.go(String.split(l, ' '))

def Nh.status.hit(hit: Bool, +st: String) -> Maybe<&2, String>:
  match hit:
    case True{}:
      Some{st}
    case False{}:
      None{}

def Nh.status.row(ws: List<&2, String>, +id: String) -> Maybe<&2, String>:
  match ws:
    case Con{+x, Con{p, Con{+st, t}}}:
      Nh.status.hit(String.eq(x, id), st)
    case _:
      None{}

def Nh.status.pick(m: Maybe<&2, String>, more: String) -> String:
  match m:
    case Some{s}:
      s
    case None{}:
      more

def Nh.status.lines(ls: List<&2, String>, +id: String) -> String:
  match ls:
    case Nil{}:
      "stopped"
    case Con{l, t}:
      Nh.status.pick(Nh.status.row(Nh.words(l), id), Nh.status.lines(t, id))

# A container's status in `runc list`'s table (ID PID STATUS BUNDLE
# CREATED OWNER, runc's list.go): created, running, paused or stopped;
# stopped when the table has no such row.
def Nh.status(text: String, +id: String) -> String:
  Nh.status.lines(String.lines(text), id)

def Nh.env(+name: String, +k: U32, +etcd: Bool, +nodes: U32, +now: String) -> String:
  "NAME=" ++ name ++ "\nGUEST=" ++ name ++ "\nPORT=" ++ U32.show(Nh.port(k)) ++ "\nCPUS=0\nMEMORY=0\nSTORE=" ++ CL.Cli.store_name(etcd)
    ++ "\nNODES=" ++ U32.show(nodes) ++ "\nWORKERS=" ++ CL.Cli.workers_show(CL.Cli.workers_upto(nodes))
    ++ "\nKUBERNETES=v1.36.6\nBACKEND=container\nSLOT=" ++ U32.show(k) ++ "\nNODEHOST=1\nAPI=https://127.0.0.1:" ++ U32.show(Nh.port(k))
    ++ "\nCREATED=" ++ String.trim(now) ++ "\n"

def Nh.full_message() -> String:
  "every node-host slot is taken (16 container clusters at most: bend-vmm forwards 16 ports); delete one first"

# Idle sleep (GOAL section 11): the marker a sleeping node-host cluster
# has in its folder on the Mac; when every node-host cluster has one, the
# node host VM hibernates.
def Nh.asleep_file() -> String:
  "asleep"

# Optional sets on demand (docs/GOAL.md section 11): the node host is one
# VM for every container cluster of a home, so it attaches gvisor and etcd
# when the assets dir holds them (a create that asks for one fetches it
# before the node host starts, and stops when a running node host lacks
# it). Every node container then sees runsc in bin/: on a shared node
# host, gVisor is the node host's, not one cluster's.
def Nh.sets.v2(images: Bool, gvisor: Bool, etcd: Bool) -> +List<String>:
  R.Ctr.sets.v2(images, gvisor, etcd)

# The file in the node host's directory that names the sets it booted with.
def Nh.sets_file() -> String:
  "sets"

# --- A request's answer follows the list (laws nodehost.want,
# nodehost.settled*)

# The row of runc's list that shows a request took effect: a container's
# ID and the status `vk8s list` must then read for it (Nh.status).
type Want is Data:
  Want{id: String, state: String}

def Nh.frozen(pause: Bool) -> String:
  match pause:
    case True{}:
      "paused"
    case False{}:
      "running"

# up: the control plane's container runs. join: the worker's container
# runs. down: the control plane's row is gone (its workers go first,
# Nh.nodes). pause, resume: the control plane is paused, running: the
# row `vk8s list` reads (host/vk8s.bend Vk8s.ctr.entry). A bad request
# changes nothing, and its container "" has no row.
def Nh.want(op: Op) -> Want:
  match op:
    case Up{+name, k, etcd}:
      Want{R.Ctr.id(name, 0), "running"}
    case Join{+name, k, +i, token}:
      Want{R.Ctr.id(name, i), "running"}
    case Down{+name, k, ws}:
      Want{R.Ctr.id(name, 0), "stopped"}
    case Freeze{+verb, +name, ws}:
      Want{R.Ctr.id(name, 0), Nh.frozen(String.eq(verb, "pause"))}
    case Bad{}:
      Want{"", "stopped"}

# Whether runc's list (text) shows the row.
def Nh.shown(w: Want, text: String) -> Bool:
  match w:
    case Want{+id, +state}:
      String.eq(Nh.status(text, id), state)

# Whether runc's list shows that the request took effect. The node host's
# PID 1 answers a request only after it wrote a list on the share for
# which this holds (host/init.bend Nhi.settle), so `vk8s list` is right
# as soon as the command that changed the state returns; when no list
# shows it within Nh.settle_ms, the request fails.
def Nh.settled(op: Op, text: String) -> Bool:
  Nh.shown(Nh.want(op), text)

# How long PID 1 waits for the list to show a request's effect: `runc
# run -d` is spawned and not waited for, and registers its container
# within a second.
def Nh.settle_ms() -> U32:
  30000

# --- The node host's directory goes with the last container cluster
# (laws nodehost.stop_due, nodehost.reclaim*)

# Whether delete stops the node host's VMM: no container cluster is left
# and the VMM serves requests or its process lives (one that never got
# ready too).
def Nh.stop_due(left: Bool, running: Bool, alive: Bool) -> Bool:
  Bool.not(left) && (running || alive)

# Whether delete removes the node host's directory (its data disk, the
# VM's containerd store, and its share): no container cluster is left,
# read again after the VMM stopped (a create reserves with its
# cluster.env before it starts the node host), and no VMM process holds
# the disk.
def Nh.reclaim(left: Bool, alive: Bool) -> Bool:
  Bool.not(left) && Bool.not(alive)

# Whether another container cluster runs in the node host besides the
# one being deleted: at least two NODEHOST=1 lines among every
# cluster.env (the deleted cluster's own is one of them).
def Nh.others.lines(ls: List<&2, String>, +seen: Bool) -> Bool:
  match ls:
    case Nil{}:
      False{}
    case Con{+l, t}:
      +hit : Bool = String.eq(String.trim(l), "NODEHOST=1")
      (hit && seen) || Nh.others.lines(t, seen || hit)

def Nh.others(text: String) -> Bool:
  Nh.others.lines(String.lines(text), False{})

# Whether delete asks the node host to take the cluster's containers
# down before its directories go: only when another cluster stays. The
# last cluster's containers end with the VM (Nh.stop_due), which gets
# the same one-second grace, so the cluster is not given it twice.
def Nh.down_first(others: Bool, running: Bool) -> Bool:
  running && others

# Whether delete asks after all: it skipped the request (no other
# cluster was there) and the VM is not stopped, because a create
# reserved the node host meanwhile.
def Nh.down_late(others: Bool, running: Bool, stop: Bool) -> Bool:
  running && Bool.not(others) && Bool.not(stop)

# Where the directory is renamed before it is removed, so a create never
# finds a half-removed node host.
def Nh.gone_dir(+home: String) -> String:
  Nh.dir(home) ++ ".gone"
