import Base
import ../guest/plan.bend as P
import ../guest/container.bend as C
import ./ctr.bend as R
import ./cli.bend as CL
import ../layers/ask.bend as LA

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

# --- The shared layer store in the node host (docs/STATUS.md, "Shared
# assets and layers off the VM", the macOS node host). vk8s's own design;
# nothing here mirrors vcluster.
#
# - The Mac shares its store (~/.vk8s/layers) into the node host VM once,
#   when the VM starts: the second share a VM node gets (CL.Cli.with_layers:
#   tag layers, read-only, bend-vmm's meta mode; VK8S_LAYERS=1 on the
#   kernel command line), which PID 1 mounts at P.Plan.layers_store.v4.
#   PID 1 says on its share whether it did (Nh.layers_ack), so a create
#   knows whether the running VM has the store.
# - A node container binds that mount and the VM's /dev as a node
#   container on a Linux host binds the host's store and /dev
#   (R.Ctr.json.v2), and its snapshotter loop-mounts the layer images in
#   the container's own mount namespace: the mounts and their loop
#   devices end with the container, so a cluster's delete has nothing of
#   the store to undo in the VM.
# - The filler runs on the Mac. A node container reaches the Mac's
#   loopback where a VM node does, at bend-vmm's NAT gateway
#   (LA.Ask.host.v2), through the cluster's bridge and the masquerade it
#   has already (R.Ctr.rules): no rule is added for the store, where a
#   Linux host needs three (R.Ctr.layers_rules: its filler listens on a
#   loopback no container can route to). PID 1's environment names that
#   address (VK8S_LAYERS_ASK), so the node does not wait for a fill
#   (LA.Ask.nowait.v4), as a node container on a Linux host.
# - The store is per cluster: a request's last word "layers" asks for it
#   (Nh.parse.v2), from the Mac's VK8S_LAYERS at create (Nh.layers_use).
#   Without the word a request is the one before, word for word.

# Whether a create asks for the store: unless VK8S_LAYERS=0, as a node
# container on a Linux host (R.Ctr.layers_on.v2).
def Nh.layers_on(+env: String) -> Bool:
  R.Ctr.layers_on.v2(env)

# The file on the node host's share in which its PID 1 says, before it
# says ready, whether it mounted the store ("1") or not ("0"): the Mac
# reads <node host>/share/layers, PID 1 writes Nh.layers_ack. A PID 1
# from guest assets older than the store writes none, and would refuse
# a request with the word.
def Nh.layers_file() -> String:
  "layers"

def Nh.layers_ack() -> String:
  P.Plan.host_dir() ++ "/" ++ Nh.layers_file()

def Nh.layers_mark(on: Bool) -> String:
  match on:
    case True{}:
      "1\n"
    case False{}:
      "0\n"

# Whether a cluster's nodes use the store: the create asks for it and the
# running node host mounted the store (mark: Nh.layers_file's text; none
# from older guest assets, "0" from a node host that started with
# VK8S_LAYERS=0 or whose mount failed).
def Nh.layers_use(+env: String, mark: String) -> Bool:
  Nh.layers_on(env) && String.eq(String.trim(mark), "1")

# Nh.boot in two parts, so that PID 1 mounts the store and writes
# Nh.layers_ack between them: everything up to the nodes' directories,
# then the ready marker. The Mac reads the store's file once it has seen
# ready.
def Nh.boot_head(+sets: +List<String>) -> +List<P.Step>:
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
      P.Plan.bb(["mkdir", "-p", Nh.root(), "/run/vk8s"]) ]))))))

def Nh.boot_tail() -> +List<P.Step>:
  [ P.Write{Nh.ready(), "ok\n"},
    P.Log{"vk8s: node host ready"} ]

# What create says of the store: where it is, or that the node host
# that runs already started without it (it is one VM for every container
# cluster, and its shares are fixed when it starts).
def Nh.layers_note(+store: String) -> String:
  "Shared layer store: " ++ store ++ " (VK8S_LAYERS=0 turns it off), shared read-only into the node host VM and bound into every node container"

def Nh.layers_none_note() -> String:
  "The node host VM runs without the shared layer store (it started without one, or from older guest assets); these nodes unpack their layers themselves. "
    ++ "It starts with the store once the other container clusters are deleted (the node host stops with the last)"

# What create says: nothing when it does not ask for the store.
def Nh.layers_say(+env: String, mark: String, +store: String) -> String:
  Bool.pick(String, Nh.layers_on(env),
    Bool.pick(String, String.eq(String.trim(mark), "1"), Nh.layers_note(store), Nh.layers_none_note()), "")

# The node host's bend-vmm flags with the store's share (on), or as they
# are.
def Nh.flags.v2(on: Bool, +store: String, flags: +List<String>) -> +List<String>:
  CL.Cli.with_layers(on, store, flags)

# The store in the VM, where the node containers bind it from.
def Nh.layers_store() -> String:
  P.Plan.layers_store.v4()

# PID 1's steps for the store, between Nh.boot_head and Nh.boot_tail:
# the share's mount, read-only and nosuid, as a VM node mounts it. None
# when the VM has no such share. A mount that fails does not stop the
# boot: PID 1 writes "0" and the nodes unpack their layers themselves.
def Nh.layers_mount(on: Bool) -> +List<P.Step>:
  match on:
    case True{}:
      [P.Plan.layers_store_mount.v4()]
    case False{}:
      []

# PID 1's environment of a node on the store: the node's own switch, and
# the filler's address, the Mac's loopback as a guest reaches it.
def Nh.layers_env(on: Bool, env: +List<String>) -> +List<String>:
  match on:
    case True{}:
      List.append(&2, String, env, ["VK8S_LAYERS=1", "VK8S_LAYERS_ASK=" ++ LA.Ask.host.v2()])
    case False{}:
      env

# Nh.node with the store (on): the container's config binds Nh.layers_store and
# the VM's /dev, and PID 1 gets Nh.layers_env. Off, the steps of Nh.node.
def Nh.node.v2(t: Tools, +name: String, +k: U32, +i: U32, +arch: String, env: +List<String>, +on: Bool) -> +List<P.Step>:
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
          P.Write{bundle ++ "/config.json", R.Ctr.json.v2(C.Spec{name, R.Ctr.node(name, i), rootfs, nd ++ "/data", share, Nh.assets(),
            Nh.layers_env(on, R.Ctr.arch_env(arch, env))}, R.Ctr.netns_path(name, i), on, Nh.layers_store())} ],
      List.append(&2, P.Step, Nh.runs(ip, R.Ctr.ip_node(name, k, i)),
        [P.Spawn{R.Ctr.id(name, i), runc, R.Ctr.runc_run(bundle, R.Ctr.id(name, i))}]))

# Nh.up with Nh.node.v2: the bridge, the rules, the cgroups (all as
# before: the store adds no rule), then the control plane.
def Nh.up.v2(t: Tools, +name: String, +k: U32, etcd: Bool, +arch: String, +on: Bool) -> +List<P.Step>:
  match t:
    case Tools{+ip, +cpio, +iptables, +runc}:
      List.append(&2, P.Step, [P.Log{"vk8s: node host: cluster " ++ name ++ " on " ++ R.Ctr.bridge(k)}],
      List.append(&2, P.Step, Nh.runs(ip, R.Ctr.ip_bridge(k)),
      List.append(&2, P.Step, Nh.runs(iptables, Nh.rules.v2(name, k)),
      List.append(&2, P.Step, Nh.cgroups(R.Ctr.cgroup_dirs(name)),
        Nh.node.v2(Tools{ip, cpio, iptables, runc}, name, k, 0, arch, R.Ctr.env_cp(name, k, 6443, etcd), on)))))

def Nh.join.v2(t: Tools, +name: String, +k: U32, +i: U32, +token: String, +arch: String, +on: Bool) -> +List<P.Step>:
  Nh.node.v2(t, name, k, i, arch, R.Ctr.env_worker(name, k, i, token), on)

# A request with the store: Nh.parse's Op and whether its nodes use the
# store.
type Req is Data:
  Req{layers: Bool, op: Op}

def Nh.layers_word() -> String:
  "layers"

def Nh.req_layers(on: Bool, +s: String) -> String:
  match on:
    case True{}:
      s ++ " " ++ Nh.layers_word()
    case False{}:
      s

# The up and join requests the Mac sends, with the word when the
# cluster's nodes use the store.
def Nh.req_up.v2(+name: String, +k: U32, etcd: Bool, layers: Bool) -> String:
  Nh.req_layers(layers, Nh.req_up(name, k, etcd))

def Nh.req_join.v2(+name: String, +k: U32, +i: U32, +token: String, layers: Bool) -> String:
  Nh.req_layers(layers, Nh.req_join(name, k, i, token))

def Nh.last_is(ws: +List<String>, +w: String) -> Bool:
  match ws:
    case Nil{}:
      False{}
    case Con{x, Nil{}}:
      String.eq(x, w)
    case Con{x, t}:
      Nh.last_is(t, w)

# Every word but the last.
def Nh.init(ws: +List<String>) -> +List<String>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{x, Nil{}}:
      Nil{}
    case Con{x, t}:
      Con{x, Nh.init(t)}

# Only up and join take the word: any other request that ends in it is
# refused.
def Nh.req_keep(op: Op) -> Req:
  match op:
    case Up{name, k, etcd}:
      Req{True{}, Up{name, k, etcd}}
    case Join{name, k, i, token}:
      Req{True{}, Join{name, k, i, token}}
    case Down{name, k, ws}:
      Req{False{}, Bad{}}
    case Freeze{verb, name, ws}:
      Req{False{}, Bad{}}
    case Bad{}:
      Req{False{}, Bad{}}

def Nh.parse.v2.go(hit: Bool, +ws: +List<String>) -> Req:
  match hit:
    case True{}:
      Nh.req_keep(Nh.parse(Nh.init(ws)))
    case False{}:
      Req{False{}, Nh.parse(ws)}

# An action's words as a Req: Nh.parse of the words, without a last word
# "layers" (no request of Nh.parse ends in it: a store's name, a token, a
# list of workers).
def Nh.parse.v2(+ws: +List<String>) -> Req:
  Nh.parse.v2.go(Nh.last_is(ws, Nh.layers_word()), ws)

def Nh.req_op(r: Req) -> Op:
  match r:
    case Req{layers, op}:
      op

# Whether the request's nodes use the store: it asks for it and the VM
# mounted the share (have).
def Nh.req_on(r: Req, have: Bool) -> Bool:
  match r:
    case Req{layers, op}:
      layers && have

# Where the filler's gc finds what the node host's nodes hold (root:
# ~/.vk8s): the clusters under the node host's share, laid out as
# ~/.vk8s/clusters (Nh.share: <cluster>/share and <cluster>/nodes/
# worker-<i>/share), each node's layers.held on its share.
def Nh.held_root(+root: String) -> String:
  root ++ "/nodehost/share/clusters"

# --- What a down request left in the VM (PID 1 says it on the console
# after each): the cluster's mounts in the VM's own mount namespace, its
# rules, and the loop devices in use in the whole VM (a node's layer
# mounts are in its container's mount namespace and end with it; each
# held a loop device).

def Nh.digit(c: Char) -> Bool:
  match c:
    case Chr{+x}:
      U32.is_ge(x, 48) && U32.is_le(x, 57)

def Nh.digits(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      Nh.digit(c) && Nh.digits(t)

# Whether mount point p is the cluster's: under its directory on the
# data disk or on the share, or the network namespace of one of its
# nodes (R.Ctr.netns_path; "vk8s-a-1" is cluster a's, "vk8s-a-b-1" is not).
def Nh.mount_of(+name: String, +p: String) -> Bool:
  +ns = "/run/netns/vk8s-" ++ name ++ "-"
  +rest = String.drop(p, String.length(ns))
  String.eq(p, Nh.vm_dir(name, 0)) || String.starts_with(p, Nh.vm_dir(name, 0) ++ "/")
    || String.starts_with(p, P.Plan.host_dir() ++ "/clusters/" ++ name ++ "/")
    || (String.starts_with(p, ns) && Bool.not(String.is_empty(rest)) && Nh.digits(rest))

def Nh.mounts_left.line(ws: List<&2, String>, +name: String, rest: +List<String>) -> +List<String>:
  match ws:
    case Con{src, Con{+p, t}}:
      R.Ctr.lacks.add(Bool.not(Nh.mount_of(name, p)), p, rest)
    case _:
      rest

def Nh.mounts_left.lines(ls: List<&2, String>, +name: String) -> +List<String>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{l, t}:
      Nh.mounts_left.line(Nh.words(l), name, Nh.mounts_left.lines(t, name))

# The cluster's mount points in a /proc/mounts text (device, mount
# point, type, options: proc(5)).
def Nh.mounts_left(text: String, +name: String) -> +List<String>:
  Nh.mounts_left.lines(String.lines(text), name)

def Nh.count(cs: +List<+List<String>>) -> U32:
  match cs:
    case Nil{}:
      0
    case Con{c, t}:
      (1 + Nh.count(t) : U32)

# The rules tagged as the cluster's in `iptables -t nat -S` and
# `iptables -t filter -S` (R.Ctr.undo reads the tag as a whole word).
def Nh.rules_left(+name: String, nat: String, filter: String) -> U32:
  (Nh.count(R.Ctr.undo("nat", R.Ctr.tag(name), nat)) + Nh.count(R.Ctr.undo("filter", R.Ctr.tag(name), filter)) : U32)

def Nh.loops.row(ws: List<&2, String>) -> U32:
  match ws:
    case Con{a, Con{b, Con{c, Con{+n, t}}}}:
      Bool.to_u32(String.starts_with(n, "loop"))
    case _:
      0

def Nh.loops.lines(ls: List<&2, String>) -> U32:
  match ls:
    case Nil{}:
      0
    case Con{l, t}:
      (Nh.loops.row(Nh.words(l)) + Nh.loops.lines(t) : U32)

# The loop devices in use, from /proc/partitions (major, minor, blocks,
# name: proc(5)): the kernel lists a block device there only while it
# has a size, and a loop device has one only while a file backs it.
def Nh.loops(text: String) -> U32:
  Nh.loops.lines(String.lines(text))

def Nh.after.mounts(ms: +List<String>) -> String:
  match ms:
    case Nil{}:
      "no mount"
    case Con{m, t}:
      "mounts " ++ String.join(Con{m, t}, " ")

# What PID 1 says after a down request.
def Nh.after(+name: String, mounts: +List<String>, +rules: U32, +loops: U32) -> String:
  "node host: after " ++ name ++ ": " ++ Nh.after.mounts(mounts) ++ " and " ++ U32.show(rules) ++ " rules of it left, "
    ++ U32.show(loops) ++ " loop devices in use"

# iptables' argument list that lists a table's rules.
def Nh.list_rules(+table: String) -> +List<String>:
  ["-t", table, "-S"]
