import Base
import ../src/guest/plan.bend as P
import ../src/guest/values.bend as VL
import ../src/guest/container.bend as C

# src/guest/container.bend, run: a node container's config.json as text,
# and PID 1's boot plan in a container next to the VM's.

def T.check(+name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name)

# A step as one line, for comparisons.
def T.step(s: P.Step) -> String:
  match s:
    case P.Mount{fs, src, dst, opts}:
      "mount " ++ fs ++ " " ++ src ++ " " ++ dst ++ " " ++ opts
    case P.Write{path, text}:
      "write " ++ path ++ " " ++ text
    case P.Run{prog, args}:
      "run " ++ prog ++ " " ++ String.join(args, " ")
    case P.Daemon{n, prog, args}:
      "daemon " ++ n ++ " " ++ prog ++ " " ++ String.join(args, " ")
    case P.Spawn{n, prog, args}:
      "spawn " ++ n ++ " " ++ prog ++ " " ++ String.join(args, " ")
    case P.Modules{path}:
      "modules " ++ path
    case P.Log{t}:
      "log " ++ t
    case _:
      "other"

def T.steps(ss: +List<P.Step>) -> +List<String>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      Con{T.step(s), T.steps(t)}

def T.lines(ss: +List<P.Step>) -> String:
  String.join(T.steps(ss), "\n")

def T.post_len(sp: VL.Split) -> Nat:
  match sp:
    case VL.Split{pre, post}:
      List.length(&2, P.Step, post)

def T.spec() -> C.Spec:
  C.Spec{"demo", "worker-1", "/b/rootfs", "/c/data", "/c/share", "/x/assets", ["VK8S_NAME=demo", "VK8S_ROLE=worker"]}

def main() -> IO(Unit):
  do IO<Unit>:
    +json : String = C.Container.json(T.spec())
    +kine : String = T.lines(C.Plan.boot_container(P.Plan.default_cfg("demo", 6443, False{})))
    +etcd : String = T.lines(C.Plan.boot_container(P.Plan.default_cfg("demo", 6443, True{})))
    T.check("config.json opens with the OCI version", String.starts_with(json, "{\"ociVersion\":\"1.0.2\",\"process\":{\"terminal\":false,"))
    T.check("PID 1 is the image's vk8s-init, as root",
      String.contains(json, "\"user\":{\"uid\":0,\"gid\":0},\"args\":[\"/sbin/vk8s-init\"],"))
    T.check("PID 1's environment: the kernel's for init, then the host's",
      String.contains(json, "\"env\":[\"HOME=/\",\"TERM=linux\",\"VK8S_NAME=demo\",\"VK8S_ROLE=worker\"],\"cwd\":\"/\","))
    T.check("every capability, bounding first",
      String.contains(json, "\"capabilities\":{\"bounding\":[\"CAP_CHOWN\",\"CAP_DAC_OVERRIDE\","))
    T.check("the last capability is CAP_CHECKPOINT_RESTORE in all three sets",
      String.contains(json, "\"CAP_BPF\",\"CAP_CHECKPOINT_RESTORE\"]}},\"root\":"))
    T.check("the root filesystem is the bundle's, read-write",
      String.contains(json, "\"root\":{\"path\":\"/b/rootfs\",\"readonly\":false},\"hostname\":\"worker-1\","))
    T.check("tmpfs on /run and /tmp",
      String.contains(json, "{\"destination\":\"/run\",\"type\":\"tmpfs\",\"source\":\"tmpfs\",\"options\":[\"mode=0755\"]},{\"destination\":\"/tmp\",\"type\":\"tmpfs\",\"source\":\"tmpfs\",\"options\":[\"mode=1777\"]}"))
    T.check("the cgroup file system, read-write",
      String.contains(json, "{\"destination\":\"/sys/fs/cgroup\",\"type\":\"cgroup\",\"source\":\"cgroup\",\"options\":[\"nosuid\",\"noexec\",\"nodev\",\"relatime\"]}"))
    T.check("the assets, read-only at /assets",
      String.contains(json, "{\"destination\":\"/assets\",\"type\":\"bind\",\"source\":\"/x/assets\",\"options\":[\"rbind\",\"ro\"]}"))
    T.check("the host's /lib/modules, read-only",
      String.contains(json, "{\"destination\":\"/lib/modules\",\"type\":\"bind\",\"source\":\"/lib/modules\",\"options\":[\"rbind\",\"ro\"]}"))
    T.check("the host's /dev/kmsg",
      String.contains(json, "{\"destination\":\"/dev/kmsg\",\"type\":\"bind\",\"source\":\"/dev/kmsg\",\"options\":[\"rbind\",\"rw\"]}"))
    T.check("the data dir, then the assets at its bin/, then the share",
      String.contains(json, "{\"destination\":\"/var/lib/vcluster\",\"type\":\"bind\",\"source\":\"/c/data\",\"options\":[\"rbind\",\"rw\"]},"
        ++ "{\"destination\":\"/var/lib/vcluster/bin\",\"type\":\"bind\",\"source\":\"/x/assets\",\"options\":[\"rbind\",\"ro\"]},"
        ++ "{\"destination\":\"/var/lib/vk8s-host\",\"type\":\"bind\",\"source\":\"/c/share\",\"options\":[\"rbind\",\"rw\"]}]"))
    T.check("a private cgroup namespace and the node's cgroup",
      String.contains(json, "{\"type\":\"network\"},{\"type\":\"cgroup\"}],\"cgroupsPath\":\"/vk8s/demo/worker-1\","))
    T.check("every device allowed, and the config ends there",
      String.ends_with(json, "\"resources\":{\"devices\":[{\"allow\":true,\"access\":\"rwm\"}]}}}"))
    T.check("no seccomp, AppArmor, masked or read-only paths",
      Bool.not(String.contains(json, "seccomp") || String.contains(json, "apparmor") || String.contains(json, "maskedPaths")
        || String.contains(json, "readonlyPaths") || String.contains(json, "noNewPrivileges")))
    T.check("no user namespace", Bool.not(String.contains(json, "{\"type\":\"user\"}")))
    T.check("container boot, kine: no module loading", Bool.not(String.contains(kine, "modules ")))
    T.check("container boot, etcd: no module loading", Bool.not(String.contains(etcd, "modules ")))
    T.check("container boot: no disk, 9p, virtual file system or NIC step",
      Bool.not(String.contains(kine, "/dev/vd") || String.contains(kine, "9p") || String.contains(kine, "mount proc")
        || String.contains(kine, "mount devtmpfs") || String.contains(kine, "mount cgroup2") || String.contains(kine, "eth0")
        || String.contains(kine, "eth1") || String.contains(kine, "10.0.2.3")))
    T.check("container boot: no page reporting or global inotify write",
      Bool.not(String.contains(kine, "page_reporting") || String.contains(kine, "inotify")))
    T.check("container boot: the cgroup delegation comes first",
      String.starts_with(kine, "run /bin/busybox mkdir -p /sbin /usr/bin /usr/sbin\nrun /bin/busybox --install -s\n"
        ++ "run /bin/busybox mount --make-rshared /\nwrite /sys/fs/cgroup/init.scope/cgroup.procs 1\n"
        ++ "run /bin/busybox sed -n -e s/ / +/g -e s/^/+/ -e w /sys/fs/cgroup/cgroup.subtree_control /sys/fs/cgroup/cgroup.controllers\n"
        ++ "run /bin/busybox mkdir -p /sys/fs/cgroup/kubelet\n"
        ++ "run /bin/busybox sed -n -e s/ / +/g -e s/^/+/ -e w /sys/fs/cgroup/kubelet/cgroup.subtree_control /sys/fs/cgroup/kubelet/cgroup.controllers\n"))
    T.check("container boot: kubelet under the /kubelet cgroup",
      String.contains(kine, "daemon kubelet /var/lib/vcluster/bin/kubelet --config=/var/lib/vcluster/kubelet-config.yaml")
        && String.contains(kine, " --cgroup-root=/kubelet"))
    T.check("container boot: only kubelet gets the cgroup root",
      Bool.not(String.contains(kine, "daemon containerd /var/lib/vcluster/bin/containerd --config /etc/containerd/config.toml --cgroup-root")))
    T.check("container boot: the store, the API server and the node start as in a VM",
      String.contains(kine, "daemon kine ") && String.contains(etcd, "daemon etcd ") && String.contains(kine, "daemon kube-apiserver ")
        && String.contains(kine, "daemon containerd "))
    T.check("container boot: the kubeconfig is published",
      String.ends_with(kine, "log vk8s: kubeconfig published"))
    T.check("container boot: the node's name resolves to its LAN address",
      String.contains(kine, "write /etc/hosts 127.0.0.1 localhost\n10.10.0.2 demo\n"))
    T.check("container boot: PID 1 still splits at the share (vcluster.yaml, restore marker)",
      Bool.not(Nat.is_eq(T.post_len(VL.Values.split(C.Plan.boot_container(P.Plan.default_cfg("demo", 6443, False{})))), 0n)))
    T.check("container boot: the steps after the share are the VM's PKI steps on",
      String.starts_with(T.lines(List.drop(&2, P.Step, C.Plan.boot_container(P.Plan.default_cfg("demo", 6443, False{})), 12n)),
        "write /var/lib/vcluster/kubeadm.yaml "))
    T.check("the VM boot still loads modules", C.Container.has_modules(P.Plan.boot(P.Plan.default_cfg("demo", 6443, False{}))))
