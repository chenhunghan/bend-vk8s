import Base
import bend-kube-runtime@0.10.0.0/src/json.bend as J
import ./plan.bend as P

# Container mode (docs/GOAL.md section 8, `--backend container`;
# docs/ref/explore-linux-hosts.md Phase 6, C1 and the pure part of C3).
# Each node is a container that vk8s makes itself with runc and an OCI
# runtime config.json (D9: runc is in the node bundle already), running
# the same node image and PID 1 as a VM. Pure: the host writes
# Container.json(spec) into the bundle and runs it; PID 1 runs
# Plan.boot_container instead of P.Plan.boot.
#
# The container is what the two references ask Docker for:
# - vcluster's docker driver (pkg/cli/create_docker.go:620-626 and
#   :681-687, main 3a0085b): `--tmpfs /run --tmpfs /tmp --privileged`
#   for the control plane and every worker;
# - kind (pkg/cluster/internal/providers/docker/provision.go, main
#   0750810): `--cgroupns=private` (:175), `--privileged` (:226),
#   `seccomp=unconfined` and `apparmor=unconfined` (:227-228),
#   `--tmpfs /tmp --tmpfs /run` (:230-231) and
#   `--volume /lib/modules:/lib/modules:ro` (:239).
# Docker's --privileged is, in OCI terms: every capability in the
# bounding, effective and permitted sets, no seccomp profile, no AppArmor
# profile, no masked or read-only paths, a read-write /sys and cgroup
# mount, and every device allowed by the devices controller. vk8s binds
# one host device, /dev/kmsg, which kubelet's OOM watcher reads; Docker's
# --privileged would expose all of them.

# What the host chooses for one node: the cluster and node names (the
# node's hostname; the cgroup is /vk8s/<cluster>/<node>), the bundle's
# root filesystem (the unpacked initramfs), the host directories that
# replace the VM's disks (the data dir, the share, the assets image's
# mount), and PID 1's environment (VK8S_NAME, VK8S_ROLE, ..., which the
# kernel command line carries in a VM).
type Spec is Data:
  Spec{cluster: String, node: String, rootfs: String, data: String, share: String, assets: String, env: +List<String>}

# OCI runtime-spec version (runc 1.1 and later run it).
def Container.version() -> String:
  "1.0.2"

# PID 1: the initramfs links /sbin/vk8s-init to /assets/guest (docs/DESIGN.md
# "Guest image"); stage 0 is not needed, since the runtime mounts /assets.
def Container.init() -> String:
  "/sbin/vk8s-init"

# Every Linux capability, CAP_CHOWN (0) to CAP_CHECKPOINT_RESTORE (40),
# in number order (include/uapi/linux/capability.h): Docker's --privileged
# grants all of them (kind provision.go:226, vcluster create_docker.go:625).
def Container.caps() -> +List<String>:
  [ "CAP_CHOWN", "CAP_DAC_OVERRIDE", "CAP_DAC_READ_SEARCH", "CAP_FOWNER", "CAP_FSETID",
    "CAP_KILL", "CAP_SETGID", "CAP_SETUID", "CAP_SETPCAP", "CAP_LINUX_IMMUTABLE",
    "CAP_NET_BIND_SERVICE", "CAP_NET_BROADCAST", "CAP_NET_ADMIN", "CAP_NET_RAW", "CAP_IPC_LOCK",
    "CAP_IPC_OWNER", "CAP_SYS_MODULE", "CAP_SYS_RAWIO", "CAP_SYS_CHROOT", "CAP_SYS_PTRACE",
    "CAP_SYS_PACCT", "CAP_SYS_ADMIN", "CAP_SYS_BOOT", "CAP_SYS_NICE", "CAP_SYS_RESOURCE",
    "CAP_SYS_TIME", "CAP_SYS_TTY_CONFIG", "CAP_MKNOD", "CAP_LEASE", "CAP_AUDIT_WRITE",
    "CAP_AUDIT_CONTROL", "CAP_SETFCAP", "CAP_MAC_OVERRIDE", "CAP_MAC_ADMIN", "CAP_SYSLOG",
    "CAP_WAKE_ALARM", "CAP_BLOCK_SUSPEND", "CAP_AUDIT_READ", "CAP_PERFMON", "CAP_BPF",
    "CAP_CHECKPOINT_RESTORE" ]

# gVisor in a node container (docs/GOAL.md section 8, the opt-in
# `gvisor` RuntimeClass; P.Plan.containerd_runsc). The capabilities runsc
# uses, in number order (gVisor bf5df9a, 2026-11-16):
# - the gofer's file capabilities: CAP_CHOWN, CAP_DAC_OVERRIDE,
#   CAP_DAC_READ_SEARCH, CAP_FOWNER, CAP_FSETID and CAP_SYS_CHROOT
#   (runsc/cmd/gofer.go `caps`), CAP_SETUID and CAP_SETGID (`udsOpenCaps`);
# - the sandbox, started as root: CAP_SETUID and CAP_SETGID for its new
#   user namespace, CAP_SYS_ADMIN and CAP_SYS_CHROOT for its empty chroot,
#   CAP_SETPCAP to clear its bounding set, and CAP_SYS_PTRACE for the
#   systrap platform (runsc/sandbox/sandbox.go, createSandboxProcess;
#   pkg/sentry/platform/platformdesc/platformdesc.go, systrap
#   RequiresCapSysPtrace);
# - the sandbox network: CAP_NET_ADMIN to take the pod veth's addresses
#   and routes, CAP_NET_RAW for its AF_PACKET socket
#   (runsc/sandbox/network.go, createSocket).
# The node container grants every capability (Container.caps), so runsc
# gets each of them. The rest of what runsc asks of its host is the
# container's too: no seccomp profile (systrap installs its own filters),
# no AppArmor profile, no masked or read-only path (the sandbox mounts a
# fresh /proc, which the kernel refuses under a masked one), runc's
# default /dev nodes (runsc opens /dev/urandom; /dev/cpu_dma_latency is
# optional, runsc/boot/loader.go), /tmp a tmpfs (its chroot), and the host
# kernel's af_packet (R.Ctr.modules.v2 loads it on a Linux host; the node
# host VM loads scripts/guest/modules.txt, which has it).
def Container.runsc_caps() -> +List<String>:
  [ "CAP_CHOWN", "CAP_DAC_OVERRIDE", "CAP_DAC_READ_SEARCH", "CAP_FOWNER", "CAP_FSETID",
    "CAP_SETGID", "CAP_SETUID", "CAP_SETPCAP", "CAP_NET_ADMIN", "CAP_NET_RAW",
    "CAP_SYS_CHROOT", "CAP_SYS_PTRACE", "CAP_SYS_ADMIN" ]

def Container.member(xs: +List<String>, +x: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{y, t}:
      String.eq(y, x) || Container.member(t, x)

def Container.lacks.add(have: Bool, +n: String, rest: +List<String>) -> +List<String>:
  match have:
    case True{}:
      rest
    case False{}:
      Con{n, rest}

# The names of need that have does not hold, in need's order.
def Container.lacks(+have: +List<String>, need: +List<String>) -> +List<String>:
  match need:
    case Nil{}:
      Nil{}
    case Con{+n, t}:
      Container.lacks.add(Container.member(have, n), n, Container.lacks(have, t))

def Container.strs(xs: +List<String>) -> List<&2, J.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      Con{J.JStr{x}, Container.strs(t)}

def Container.capabilities() -> J.Json:
  +cs = J.Json.arr(Container.strs(Container.caps()))
  J.Json.obj([J.KV{"bounding", cs}, J.KV{"effective", cs}, J.KV{"permitted", cs}])

# PID 1 runs as root with every capability. Its environment starts as the
# kernel's for init (init/main.c envp_init: HOME=/ and TERM=linux), then
# the host's variables.
def Container.process(env: +List<String>) -> J.Json:
  J.Json.obj([
    J.KV{"terminal", J.JBool{False{}}},
    J.KV{"user", J.Json.obj([J.KV{"uid", J.JNum{"0"}}, J.KV{"gid", J.JNum{"0"}}])},
    J.KV{"args", J.Json.arr([J.JStr{Container.init()}])},
    J.KV{"env", J.Json.arr(Container.strs(List.append(&2, String, ["HOME=/", "TERM=linux"], env)))},
    J.KV{"cwd", J.JStr{"/"}},
    J.KV{"capabilities", Container.capabilities()}])

def Container.mount(dst: String, ty: String, src: String, opts: +List<String>) -> J.Json:
  J.Json.obj([J.KV{"destination", J.JStr{dst}}, J.KV{"type", J.JStr{ty}}, J.KV{"source", J.JStr{src}},
    J.KV{"options", J.Json.arr(Container.strs(opts))}])

def Container.bind(src: String, dst: String, mode: String) -> J.Json:
  Container.mount(dst, "bind", src, ["rbind", mode])

# The mounts, in order (the runtime mounts them in this order):
# - /proc, /dev (runc's tmpfs, with its default device nodes), /dev/pts,
#   /dev/shm, /dev/mqueue: the options PID 1 gives them in a VM
#   (P.Plan.system); /dev is a tmpfs as Docker makes it, not the host's
#   devtmpfs.
# - /sys and the cgroup v2 file system at /sys/fs/cgroup, both read-write
#   (--privileged); with the private cgroup namespace the cgroup mount
#   shows the container's own cgroup as its root (kind provision.go:175).
# - tmpfs on /run and /tmp, PID 1's VM options (vcluster
#   create_docker.go:623-624, kind provision.go:230-231).
# - the host's /dev/kmsg, read-write.
# - the assets image's mount at /assets, read-only, as stage 0 mounts it;
#   before /lib/modules, which the initramfs links into /assets.
# - the host's /lib/modules, read-only (kind provision.go:239).
# - the data dir at the data dir, read-write, and the assets again at its
#   bin/, read-only: P.Plan.disks's two disks as bind mounts.
# - the share at the share's mount point, read-write: the VM's 9p share.
def Container.mounts(data: String, share: String, +assets: String) -> List<&2, J.Json>:
  [ Container.mount("/proc", "proc", "proc", ["nosuid", "noexec", "nodev"]),
    Container.mount("/dev", "tmpfs", "tmpfs", ["nosuid", "strictatime", "mode=755", "size=65536k"]),
    Container.mount("/dev/pts", "devpts", "devpts", ["mode=0620", "ptmxmode=0666"]),
    Container.mount("/dev/shm", "tmpfs", "shm", ["mode=1777", "nosuid", "nodev"]),
    Container.mount("/dev/mqueue", "mqueue", "mqueue", ["nosuid", "nodev", "noexec"]),
    Container.mount("/sys", "sysfs", "sysfs", ["nosuid", "noexec", "nodev"]),
    Container.mount("/sys/fs/cgroup", "cgroup", "cgroup", ["nosuid", "noexec", "nodev", "relatime"]),
    Container.mount("/run", "tmpfs", "tmpfs", ["mode=0755"]),
    Container.mount("/tmp", "tmpfs", "tmpfs", ["mode=1777"]),
    Container.bind("/dev/kmsg", "/dev/kmsg", "rw"),
    Container.bind(assets, "/assets", "ro"),
    Container.bind("/lib/modules", "/lib/modules", "ro"),
    Container.bind(data, P.Plan.data(), "rw"),
    Container.bind(assets, P.Plan.bin(), "ro"),
    Container.bind(share, P.Plan.host_dir(), "rw") ]

def Container.cgroup_path(cluster: String, node: String) -> String:
  "/vk8s/" ++ cluster ++ "/" ++ node

def Container.ns(t: String) -> J.Json:
  J.Json.obj([J.KV{"type", J.JStr{t}}])

# New pid, ipc, uts, mount, network and cgroup namespaces; no user
# namespace (root in the container is root, as with --privileged). The
# cgroup namespace is private (kind provision.go:175): the container's
# cgroup, /vk8s/<cluster>/<node> under the host's root, is the root of
# its cgroup tree, which PID 1 delegates (Container.cgroup_steps). The
# devices controller allows every device (--privileged). No seccomp
# section, no AppArmor profile, no masked or read-only paths: kind's
# seccomp=unconfined and apparmor=unconfined (provision.go:227-228).
def Container.linux(cluster: String, node: String) -> J.Json:
  J.Json.obj([
    J.KV{"namespaces", J.Json.arr([Container.ns("pid"), Container.ns("ipc"), Container.ns("uts"), Container.ns("mount"),
      Container.ns("network"), Container.ns("cgroup")])},
    J.KV{"cgroupsPath", J.JStr{Container.cgroup_path(cluster, node)}},
    J.KV{"resources", J.Json.obj([J.KV{"devices", J.Json.arr([J.Json.obj([J.KV{"allow", J.JBool{True{}}}, J.KV{"access", J.JStr{"rwm"}}])])}])}])

# The node's config.json, as a JSON value.
def Container.config(s: Spec) -> J.Json:
  match s:
    case Spec{cluster, +node, rootfs, data, share, +assets, env}:
      J.Json.obj([
        J.KV{"ociVersion", J.JStr{Container.version()}},
        J.KV{"process", Container.process(env)},
        J.KV{"root", J.Json.obj([J.KV{"path", J.JStr{rootfs}}, J.KV{"readonly", J.JBool{False{}}}])},
        J.KV{"hostname", J.JStr{node}},
        J.KV{"mounts", J.Json.arr(Container.mounts(data, share, assets))},
        J.KV{"linux", Container.linux(cluster, node)}])

# The node's config.json, as text.
def Container.json(s: Spec) -> String:
  J.Json.show(Container.config(s))

# --- PID 1 in a container (C3).

# What stays of P.Plan.system: busybox's applets. The runtime mounts the
# virtual file systems (Container.mounts). Then every mount becomes
# shared, so kubelet's mount propagation reaches pods (kind's entrypoint,
# images/base/files/usr/local/bin/entrypoint:192, `mount --make-rshared /`).
def Container.system() -> +List<P.Step>:
  [ P.Plan.bb(["mkdir", "-p", "/sbin", "/usr/bin", "/usr/sbin"]),
    P.Plan.bb(["--install", "-s"]),
    P.Plan.bb(["mount", "--make-rshared", "/"]) ]

# cgroup.subtree_control of the cgroup at dir gets every controller its
# cgroup.controllers lists: "cpu io memory" becomes "+cpu +io +memory".
# kind's ensure_subtree_control (images/base/files/kind/bin/
# create-kubelet-cgroup-v2.sh:33-38) does this with
# `sed -e 's/ / +/g' -e 's/^/+/' <controllers >subtree_control`; the plan
# has no shell redirection, so sed writes the line itself (`w`). A plan
# step cannot read a file, so the list cannot be built in Bend; a fixed
# list would fail on a host that lacks one controller, or leave one out
# that kubelet expects (kubelet wants every controller of the root, hugetlb
# included, in its own cgroup).
def Container.enable_controllers(+dir: String) -> P.Step:
  P.Plan.bb(["sed", "-n", "-e", "s/ / +/g", "-e", "s/^/+/", "-e", "w " ++ dir ++ "/cgroup.subtree_control", dir ++ "/cgroup.controllers"])

def Container.cgroup() -> String:
  "/sys/fs/cgroup"

# kubelet's cgroup root (kind pkg/cluster/internal/kubeadm/config.go:278,
# `cgroupRoot: /kubelet`).
def Container.kubelet_cgroup() -> String:
  "/kubelet"

# cgroup v2 delegation inside the container, as kind does it (entrypoint
# fix_cgroup, :252-270, and create-kubelet-cgroup-v2.sh): the root's
# cgroup.subtree_control takes no controller while the root holds a
# process ("no internal processes"), so PID 1 first moves itself to
# /init.scope (systemd does this in kind); then the root enables every
# controller for its children; then the kubelet cgroup is made and
# enables every controller for the pods' cgroups. Writing 1 to
# cgroup.procs moves PID 1 (the writer) with all its threads; the
# processes it starts later stay in /init.scope.
def Container.cgroup_steps() -> +List<P.Step>:
  +k = Container.cgroup() ++ Container.kubelet_cgroup()
  [ P.Write{Container.cgroup() ++ "/init.scope/cgroup.procs", "1"},
    Container.enable_controllers(Container.cgroup()),
    P.Plan.bb(["mkdir", "-p", k]),
    Container.enable_controllers(k) ]

# The sysctls of P.Plan.sysctls that belong to the container's network
# namespace: ip_forward and the bridge netfilter calls (per network
# namespace since Linux 5.3; br_netfilter must be loaded on the host).
# fs.inotify.max_user_watches is the host's (global) and the page
# reporting order is the guest kernel's: the host sets those or not.
def Container.sysctls() -> +List<P.Step>:
  List.take(&2, P.Step, P.Plan.sysctls(), 3n)

# The node's name resolves to its address, as P.Plan.net writes it. The
# runtime sets the hostname (config.json) and brings up lo; the host
# gives the network namespace its interface and resolv.conf.
def Container.hosts(+c: P.Cfg) -> +List<P.Step>:
  match c:
    case P.Cfg{+name, +ip, +svc, +pod, +dom, +port, +etcd}:
      [ P.Write{"/etc/hosts", "127.0.0.1 localhost\n" ++ ip ++ " " ++ name ++ "\n"} ]

# The runtime mounts the share already. PID 1 splits its plan at the
# share's mount (host/init.bend Init.boot_plan, src/guest/values.bend
# Values.split) to read the share's vcluster.yaml and restore marker
# before the rest, so the share keeps a step: a bind mount of the share
# onto itself, which changes nothing.
def Container.share() -> P.Step:
  P.Mount{"none", P.Plan.host_dir(), P.Plan.host_dir(), "bind"}

def Container.cgroup_root_flag() -> String:
  P.Plan.flag("cgroup-root", Container.kubelet_cgroup())

def Container.kubelet_root.daemon(hit: Bool, name: String, prog: String, args: +List<String>) -> P.Step:
  match hit:
    case True{}:
      P.Daemon{name, prog, List.append(&2, String, args, [Container.cgroup_root_flag()])}
    case False{}:
      P.Daemon{name, prog, args}

def Container.kubelet_root.step(s: P.Step) -> P.Step:
  match s:
    case P.Mount{fs, src, dst, opts}:
      P.Mount{fs, src, dst, opts}
    case P.Write{path, text}:
      P.Write{path, text}
    case P.Run{prog, args}:
      P.Run{prog, args}
    case P.Daemon{+name, prog, args}:
      Container.kubelet_root.daemon(String.eq(name, "kubelet"), name, prog, args)
    case P.Spawn{name, prog, args}:
      P.Spawn{name, prog, args}
    case P.WaitTcp{host, port, ms}:
      P.WaitTcp{host, port, ms}
    case P.Stop{names}:
      P.Stop{names}
    case P.WaitFile{path, ms}:
      P.WaitFile{path, ms}
    case P.Modules{path}:
      P.Modules{path}
    case P.Log{text}:
      P.Log{text}

# The kubelet daemon of a plan runs with --cgroup-root=/kubelet, under the
# cgroup Container.cgroup_steps delegates (kind config.go:278); the other
# steps stay as they are.
def Container.kubelet_root(ss: +List<P.Step>) -> +List<P.Step>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      Con{Container.kubelet_root.step(s), Container.kubelet_root(t)}

def Container.is_modules(s: P.Step) -> Bool:
  match s:
    case P.Modules{path}:
      True{}
    case _:
      False{}

# Whether a plan loads kernel modules (P.Modules).
def Container.has_modules(ss: +List<P.Step>) -> Bool:
  match ss:
    case Nil{}:
      False{}
    case Con{s, t}:
      Container.is_modules(s) || Container.has_modules(t)

# A standalone control plane's boot in a container: P.Plan.boot without
# the machine steps. No module loading (the guest's modules are built for
# the guest kernel; the host loads what it needs, as vcluster's docker
# driver does with modprobe, pkg/cli/docker_runtime.go:162-182), no
# virtual file system mounts (the runtime's), no disks (bind mounts), no
# NICs (the host's veth), no 9p share. Added: the cgroup v2 delegation,
# first, and kubelet's cgroup root.
def Plan.boot_container(+c: P.Cfg) -> +List<P.Step>:
  List.append(&2, P.Step, Container.system(),
  List.append(&2, P.Step, Container.cgroup_steps(),
  List.append(&2, P.Step, Container.sysctls(),
  List.append(&2, P.Step, Container.hosts(c),
  List.append(&2, P.Step, [Container.share()],
  List.append(&2, P.Step, P.Plan.pki_steps(c),
  List.append(&2, P.Step, P.Plan.control_plane(c),
  List.append(&2, P.Step, Container.kubelet_root(P.Plan.node(c)), P.Plan.publish(c)))))))))
