import Base
import bend-kube-runtime@0.10.0.0/src/json.bend as J
import ../src/guest/plan.bend as P
import ../src/guest/container.bend as C

# Spec for src/guest/container.bend: the OCI config.json of a node
# container and PID 1's boot plan in it (docs/ref/explore-linux-hosts.md
# Phase 6, C1 and C3).
#
# Expected values come from what vcluster's docker driver and kind ask
# Docker for, in OCI terms:
# - vcluster pkg/cli/create_docker.go:620-626 and :681-687 (main
#   3a0085b): --tmpfs /run, --tmpfs /tmp, --privileged;
# - kind pkg/cluster/internal/providers/docker/provision.go (main
#   0750810): --cgroupns=private (:175), --privileged (:226),
#   seccomp=unconfined and apparmor=unconfined (:227-228), --tmpfs /tmp
#   and /run (:230-231), /lib/modules:/lib/modules:ro (:239);
# - kind's entrypoint (images/base/files/usr/local/bin/entrypoint:192,
#   :252-270), create-kubelet-cgroup-v2.sh (:33-49) and kubelet config
#   (pkg/cluster/internal/kubeadm/config.go:278, cgroupRoot: /kubelet).
# Paths inside the container are vk8s's VM paths (docs/DESIGN.md "Guest
# image"; P.Plan.data, P.Plan.bin, P.Plan.host_dir).

def Laws.container.all_caps() -> J.Json:
  J.Json.arr([ J.JStr{"CAP_CHOWN"}, J.JStr{"CAP_DAC_OVERRIDE"}, J.JStr{"CAP_DAC_READ_SEARCH"}, J.JStr{"CAP_FOWNER"},
    J.JStr{"CAP_FSETID"}, J.JStr{"CAP_KILL"}, J.JStr{"CAP_SETGID"}, J.JStr{"CAP_SETUID"},
    J.JStr{"CAP_SETPCAP"}, J.JStr{"CAP_LINUX_IMMUTABLE"}, J.JStr{"CAP_NET_BIND_SERVICE"}, J.JStr{"CAP_NET_BROADCAST"},
    J.JStr{"CAP_NET_ADMIN"}, J.JStr{"CAP_NET_RAW"}, J.JStr{"CAP_IPC_LOCK"}, J.JStr{"CAP_IPC_OWNER"},
    J.JStr{"CAP_SYS_MODULE"}, J.JStr{"CAP_SYS_RAWIO"}, J.JStr{"CAP_SYS_CHROOT"}, J.JStr{"CAP_SYS_PTRACE"},
    J.JStr{"CAP_SYS_PACCT"}, J.JStr{"CAP_SYS_ADMIN"}, J.JStr{"CAP_SYS_BOOT"}, J.JStr{"CAP_SYS_NICE"},
    J.JStr{"CAP_SYS_RESOURCE"}, J.JStr{"CAP_SYS_TIME"}, J.JStr{"CAP_SYS_TTY_CONFIG"}, J.JStr{"CAP_MKNOD"},
    J.JStr{"CAP_LEASE"}, J.JStr{"CAP_AUDIT_WRITE"}, J.JStr{"CAP_AUDIT_CONTROL"}, J.JStr{"CAP_SETFCAP"},
    J.JStr{"CAP_MAC_OVERRIDE"}, J.JStr{"CAP_MAC_ADMIN"}, J.JStr{"CAP_SYSLOG"}, J.JStr{"CAP_WAKE_ALARM"},
    J.JStr{"CAP_BLOCK_SUSPEND"}, J.JStr{"CAP_AUDIT_READ"}, J.JStr{"CAP_PERFMON"}, J.JStr{"CAP_BPF"},
    J.JStr{"CAP_CHECKPOINT_RESTORE"} ])

def Laws.container.mount(dst: String, ty: String, src: String, opts: List<&2, J.Json>) -> J.Json:
  J.Json.obj([J.KV{"destination", J.JStr{dst}}, J.KV{"type", J.JStr{ty}}, J.KV{"source", J.JStr{src}},
    J.KV{"options", J.Json.arr(opts)}])

def Laws.container.ns(t: String) -> J.Json:
  J.Json.obj([J.KV{"type", J.JStr{t}}])

def Laws.container.spec() -> C.Spec:
  C.Spec{"demo", "demo", "/r", "/d", "/s", "/a", ["VK8S_NAME=demo"]}

# Proposed: the container's privileges (Phase 6 C1).

# Docker's --privileged grants every capability: Linux's 41,
# CAP_CHOWN (0) to CAP_CHECKPOINT_RESTORE (40), in number order
# (include/uapi/linux/capability.h).
law container.caps:
  {C.Container.caps() ==
    [ "CAP_CHOWN", "CAP_DAC_OVERRIDE", "CAP_DAC_READ_SEARCH", "CAP_FOWNER", "CAP_FSETID",
    "CAP_KILL", "CAP_SETGID", "CAP_SETUID", "CAP_SETPCAP", "CAP_LINUX_IMMUTABLE",
    "CAP_NET_BIND_SERVICE", "CAP_NET_BROADCAST", "CAP_NET_ADMIN", "CAP_NET_RAW", "CAP_IPC_LOCK",
    "CAP_IPC_OWNER", "CAP_SYS_MODULE", "CAP_SYS_RAWIO", "CAP_SYS_CHROOT", "CAP_SYS_PTRACE",
    "CAP_SYS_PACCT", "CAP_SYS_ADMIN", "CAP_SYS_BOOT", "CAP_SYS_NICE", "CAP_SYS_RESOURCE",
    "CAP_SYS_TIME", "CAP_SYS_TTY_CONFIG", "CAP_MKNOD", "CAP_LEASE", "CAP_AUDIT_WRITE",
    "CAP_AUDIT_CONTROL", "CAP_SETFCAP", "CAP_MAC_OVERRIDE", "CAP_MAC_ADMIN", "CAP_SYSLOG",
    "CAP_WAKE_ALARM", "CAP_BLOCK_SUSPEND", "CAP_AUDIT_READ", "CAP_PERFMON", "CAP_BPF",
    "CAP_CHECKPOINT_RESTORE" ] : +List<String>}

# PID 1 runs as root with every capability bounding, effective and
# permitted (--privileged), and no noNewPrivileges, from the image's
# /sbin/vk8s-init, in the kernel's environment for init (HOME=/,
# TERM=linux; init/main.c) and the host's variables.
law container.config_privileged:
  {C.Container.process(["VK8S_NAME=demo"]) ==
    J.Json.obj([
      J.KV{"terminal", J.JBool{False{}}},
      J.KV{"user", J.Json.obj([J.KV{"uid", J.JNum{"0"}}, J.KV{"gid", J.JNum{"0"}}])},
      J.KV{"args", J.Json.arr([J.JStr{"/sbin/vk8s-init"}])},
      J.KV{"env", J.Json.arr([J.JStr{"HOME=/"}, J.JStr{"TERM=linux"}, J.JStr{"VK8S_NAME=demo"}])},
      J.KV{"cwd", J.JStr{"/"}},
      J.KV{"capabilities", J.Json.obj([J.KV{"bounding", Laws.container.all_caps()},
        J.KV{"effective", Laws.container.all_caps()}, J.KV{"permitted", Laws.container.all_caps()}])}]) : J.Json}

# A private cgroup namespace (kind --cgroupns=private) over the node's own
# cgroup, /vk8s/<cluster>/<node>; new pid, ipc, uts, mount and network
# namespaces and no user namespace; every device allowed (--privileged);
# no seccomp, AppArmor, masked or read-only paths (kind seccomp=unconfined,
# apparmor=unconfined).
law container.cgroup_delegation:
  {C.Container.linux("demo", "worker-1") ==
    J.Json.obj([
      J.KV{"namespaces", J.Json.arr([Laws.container.ns("pid"), Laws.container.ns("ipc"), Laws.container.ns("uts"),
        Laws.container.ns("mount"), Laws.container.ns("network"), Laws.container.ns("cgroup")])},
      J.KV{"cgroupsPath", J.JStr{"/vk8s/demo/worker-1"}},
      J.KV{"resources", J.Json.obj([J.KV{"devices", J.Json.arr([J.Json.obj([J.KV{"allow", J.JBool{True{}}},
        J.KV{"access", J.JStr{"rwm"}}])])}])}]) : J.Json}

# The mounts, in order: the virtual file systems with PID 1's VM options
# (P.Plan.system), /dev a tmpfs as Docker makes it; /sys and the cgroup
# file system read-write (--privileged); tmpfs on /run and /tmp (vcluster
# and kind --tmpfs); the host's /dev/kmsg; the assets read-only at /assets
# (stage 0's mount) before /lib/modules, the host's, read-only (kind);
# the data dir and the assets at its bin/ (the VM's two disks); the share.
law container.mounts:
  {C.Container.mounts("/d", "/s", "/a") ==
    [ Laws.container.mount("/proc", "proc", "proc", [J.JStr{"nosuid"}, J.JStr{"noexec"}, J.JStr{"nodev"}]),
      Laws.container.mount("/dev", "tmpfs", "tmpfs", [J.JStr{"nosuid"}, J.JStr{"strictatime"}, J.JStr{"mode=755"}, J.JStr{"size=65536k"}]),
      Laws.container.mount("/dev/pts", "devpts", "devpts", [J.JStr{"mode=0620"}, J.JStr{"ptmxmode=0666"}]),
      Laws.container.mount("/dev/shm", "tmpfs", "shm", [J.JStr{"mode=1777"}, J.JStr{"nosuid"}, J.JStr{"nodev"}]),
      Laws.container.mount("/dev/mqueue", "mqueue", "mqueue", [J.JStr{"nosuid"}, J.JStr{"nodev"}, J.JStr{"noexec"}]),
      Laws.container.mount("/sys", "sysfs", "sysfs", [J.JStr{"nosuid"}, J.JStr{"noexec"}, J.JStr{"nodev"}]),
      Laws.container.mount("/sys/fs/cgroup", "cgroup", "cgroup", [J.JStr{"nosuid"}, J.JStr{"noexec"}, J.JStr{"nodev"}, J.JStr{"relatime"}]),
      Laws.container.mount("/run", "tmpfs", "tmpfs", [J.JStr{"mode=0755"}]),
      Laws.container.mount("/tmp", "tmpfs", "tmpfs", [J.JStr{"mode=1777"}]),
      Laws.container.mount("/dev/kmsg", "bind", "/dev/kmsg", [J.JStr{"rbind"}, J.JStr{"rw"}]),
      Laws.container.mount("/assets", "bind", "/a", [J.JStr{"rbind"}, J.JStr{"ro"}]),
      Laws.container.mount("/lib/modules", "bind", "/lib/modules", [J.JStr{"rbind"}, J.JStr{"ro"}]),
      Laws.container.mount("/var/lib/vcluster", "bind", "/d", [J.JStr{"rbind"}, J.JStr{"rw"}]),
      Laws.container.mount("/var/lib/vcluster/bin", "bind", "/a", [J.JStr{"rbind"}, J.JStr{"ro"}]),
      Laws.container.mount("/var/lib/vk8s-host", "bind", "/s", [J.JStr{"rbind"}, J.JStr{"rw"}]) ] : +List<J.Json>}

# The whole config: OCI 1.0.2, the process, the bundle's root filesystem
# read-write, the node's hostname, the mounts and the linux section.
law container.config:
  {C.Container.config(Laws.container.spec()) ==
    J.Json.obj([
      J.KV{"ociVersion", J.JStr{"1.0.2"}},
      J.KV{"process", C.Container.process(["VK8S_NAME=demo"])},
      J.KV{"root", J.Json.obj([J.KV{"path", J.JStr{"/r"}}, J.KV{"readonly", J.JBool{False{}}}])},
      J.KV{"hostname", J.JStr{"demo"}},
      J.KV{"mounts", J.Json.arr(C.Container.mounts("/d", "/s", "/a"))},
      J.KV{"linux", C.Container.linux("demo", "demo")}]) : J.Json}

# Proposed: PID 1's boot in a container (Phase 6 C1 and C3).

# cgroup v2 delegation (kind's entrypoint :252-270 and
# create-kubelet-cgroup-v2.sh): PID 1 leaves the root cgroup for
# /init.scope, the root enables every controller it has for its children
# (ensure_subtree_control /: `sed -e 's/ / +/g' -e 's/^/+/'` of
# cgroup.controllers into cgroup.subtree_control), then /kubelet is made
# and does the same (ensure_subtree_control /kubelet).
law container.cgroup_steps:
  {C.Container.cgroup_steps() ==
    [ P.Write{"/sys/fs/cgroup/init.scope/cgroup.procs", "1"},
      P.Run{"/bin/busybox", ["sed", "-n", "-e", "s/ / +/g", "-e", "s/^/+/", "-e", "w /sys/fs/cgroup/cgroup.subtree_control", "/sys/fs/cgroup/cgroup.controllers"]},
      P.Run{"/bin/busybox", ["mkdir", "-p", "/sys/fs/cgroup/kubelet"]},
      P.Run{"/bin/busybox", ["sed", "-n", "-e", "s/ / +/g", "-e", "s/^/+/", "-e", "w /sys/fs/cgroup/kubelet/cgroup.subtree_control", "/sys/fs/cgroup/kubelet/cgroup.controllers"]} ] : +List<P.Step>}

# The boot starts with busybox's applets, every mount shared (kind's
# entrypoint :192, mount --make-rshared /), then the cgroup delegation,
# before any process but PID 1 lives.
law container.boot.head:
  {List.take(&2, P.Step, C.Plan.boot_container(P.Plan.default_cfg("demo", 6443, False{})), 7n) ==
    [ P.Run{"/bin/busybox", ["mkdir", "-p", "/sbin", "/usr/bin", "/usr/sbin"]},
      P.Run{"/bin/busybox", ["--install", "-s"]},
      P.Run{"/bin/busybox", ["mount", "--make-rshared", "/"]},
      P.Write{"/sys/fs/cgroup/init.scope/cgroup.procs", "1"},
      P.Run{"/bin/busybox", ["sed", "-n", "-e", "s/ / +/g", "-e", "s/^/+/", "-e", "w /sys/fs/cgroup/cgroup.subtree_control", "/sys/fs/cgroup/cgroup.controllers"]},
      P.Run{"/bin/busybox", ["mkdir", "-p", "/sys/fs/cgroup/kubelet"]},
      P.Run{"/bin/busybox", ["sed", "-n", "-e", "s/ / +/g", "-e", "s/^/+/", "-e", "w /sys/fs/cgroup/kubelet/cgroup.subtree_control", "/sys/fs/cgroup/kubelet/cgroup.controllers"]} ] : +List<P.Step>}

# No module loading in a container: the guest's modules are built for the
# guest kernel; the host loads what it needs (vcluster
# pkg/cli/docker_runtime.go:162-182, modprobe overlay, bridge,
# br_netfilter). The VM's boot does load them.
law container.no_modules_step.kine:
  {C.Container.has_modules(C.Plan.boot_container(P.Plan.default_cfg("demo", 6443, False{}))) == False{} : Bool}
law container.no_modules_step.etcd:
  {C.Container.has_modules(C.Plan.boot_container(P.Plan.default_cfg("demo", 6443, True{}))) == False{} : Bool}
law container.vm_boot_loads_modules:
  {C.Container.has_modules(P.Plan.boot(P.Plan.default_cfg("demo", 6443, False{}))) == True{} : Bool}

# kubelet runs under the delegated /kubelet cgroup (kind config.go:278,
# cgroupRoot: /kubelet); other daemons keep their flags.
law container.kubelet_cgroup_root:
  {C.Container.kubelet_root([P.Daemon{"kubelet", "/k", ["--a=b"]}, P.Daemon{"containerd", "/c", ["--x"]}, P.Log{"kubelet"}]) ==
    [P.Daemon{"kubelet", "/k", ["--a=b", "--cgroup-root=/kubelet"]}, P.Daemon{"containerd", "/c", ["--x"]}, P.Log{"kubelet"}] : +List<P.Step>}

# The sysctls of the container's network namespace (P.Plan.sysctls's
# first three); the global inotify limit and the guest kernel's page
# reporting order are not the container's to set.
law container.sysctls:
  {C.Container.sysctls() ==
    [ P.Write{"/proc/sys/net/ipv4/ip_forward", "1"},
      P.Write{"/proc/sys/net/bridge/bridge-nf-call-iptables", "1"},
      P.Write{"/proc/sys/net/bridge/bridge-nf-call-ip6tables", "1"} ] : +List<P.Step>}

# The share keeps a step for PID 1's split at the share (Values.split): a
# bind mount of the runtime's share mount onto itself.
law container.share:
  {C.Container.share() == P.Mount{"none", "/var/lib/vk8s-host", "/var/lib/vk8s-host", "bind"} : P.Step}

# Proposed: gVisor in a node container (docs/GOAL.md section 8, the
# opt-in `gvisor` RuntimeClass). The capabilities runsc uses, from gVisor
# (bf5df9a, 2026-11-16), in number order: the gofer's (runsc/cmd/gofer.go
# `caps` and `udsOpenCaps`); the sandbox's as root, CAP_SETUID and
# CAP_SETGID for its user namespace, CAP_SYS_ADMIN and CAP_SYS_CHROOT for
# its chroot, CAP_SETPCAP for its bounding set, CAP_SYS_PTRACE for the
# systrap platform (runsc/sandbox/sandbox.go; platformdesc.go); the
# sandbox network's CAP_NET_ADMIN and CAP_NET_RAW (AF_PACKET,
# runsc/sandbox/network.go).
law container.runsc_caps:
  {C.Container.runsc_caps() ==
    [ "CAP_CHOWN", "CAP_DAC_OVERRIDE", "CAP_DAC_READ_SEARCH", "CAP_FOWNER", "CAP_FSETID",
      "CAP_SETGID", "CAP_SETUID", "CAP_SETPCAP", "CAP_NET_ADMIN", "CAP_NET_RAW",
      "CAP_SYS_CHROOT", "CAP_SYS_PTRACE", "CAP_SYS_ADMIN" ] : +List<String>}

# The node container holds every one of them (kind's --privileged node
# does too), so runsc runs in it as in a VM node.
law container.runsc_caps_held:
  {C.Container.lacks(C.Container.caps(), C.Container.runsc_caps()) == [] : +List<String>}

law container.lacks:
  {C.Container.lacks(["CAP_CHOWN", "CAP_SYS_ADMIN"], ["CAP_SYS_ADMIN", "CAP_SYS_PTRACE", "CAP_CHOWN", "CAP_NET_RAW"]) ==
    ["CAP_SYS_PTRACE", "CAP_NET_RAW"] : +List<String>}

# Proposed: the shared layer store in a node container (docs/GOAL.md
# section 11, the container half; vk8s's design). The host's store
# directory read-only, nosuid and nodev at /mnt/layers-store (where a VM
# node mounts its 9p share, P.Plan.layers_store.v4); the host's /dev as
# a plain bind (devtmpfs only, none of its submounts), read-only, nosuid
# and noexec but not nodev (a loop device opens through it), at
# /run/vk8s/hostdev, after the /run tmpfs. Off, the mounts are as before.
law container.layers_mounts:
  {C.Container.layers_mounts.v2("/h/.vk8s/layers") ==
    [ Laws.container.mount("/mnt/layers-store", "bind", "/h/.vk8s/layers", [J.JStr{"rbind"}, J.JStr{"ro"}, J.JStr{"nosuid"}, J.JStr{"nodev"}]),
      Laws.container.mount("/run/vk8s/hostdev", "bind", "/dev", [J.JStr{"bind"}, J.JStr{"ro"}, J.JStr{"nosuid"}, J.JStr{"noexec"}]) ] : +List<J.Json>}
law container.mounts_v2_on:
  {C.Container.mounts.v2("/d", "/s", "/a", True{}, "/h/.vk8s/layers") ==
    List.append(&2, J.Json, C.Container.mounts("/d", "/s", "/a"), C.Container.layers_mounts.v2("/h/.vk8s/layers")) : +List<J.Json>}
law container.mounts_v2_off:
  for d: String
  for s: String
  for +a: String
  for x: String
  {C.Container.mounts.v2(d, s, a, False{}, x) == C.Container.mounts(d, s, a) : +List<J.Json>}
