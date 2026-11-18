import Base
import ../guest/plan.bend as P
import ../guest/supervise.bend as S
import ../cli/cli.bend as C
import ./native.bend as N

# Native mode on a Linux host, the host side (docs/ref/explore-linux-hosts.md
# Phase 5, N3 and N4; docs/ref/native-host.md): `vk8s create NAME --backend
# native` installs one systemd unit per cluster that runs `vk8s native` (the
# supervisor of host/init.bend, NInit) over the cluster's data dir, as
# vcluster standalone installs vcluster.service. Every decision is here, as
# data: the unit's text, the argument lists the host runs (each sudo step
# printed first), the per-cluster ports, the paths a host node uses, the
# preflight message, and what delete removes. host/vk8s.bend only runs them.
# vcluster's standalone runtime is closed source (pkg/pro/standalone.go);
# the values are vk8s design unless a comment names their source.

# --- Names and places

# One unit per cluster (vcluster standalone has one, vcluster.service, so
# one cluster per host).
def NHost.unit_name(+name: String) -> String:
  "vk8s-" ++ name ++ ".service"

def NHost.unit_path(+name: String) -> String:
  "/etc/systemd/system/" ++ NHost.unit_name(name)

# The cluster's data dir: the VM's /var/lib/vcluster (vcluster standalone's
# DATA_DIR), one per cluster under /var/lib/vk8s, owned by root.
def NHost.data_dir(+name: String) -> String:
  "/var/lib/vk8s/" ++ name

# The CNI plugins and their config on a host node and on nodes that join
# with the installing script: vk8s's own dirs, not the distribution's
# /opt/cni/bin and /etc/cni/net.d, so delete removes only what vk8s made.
def NHost.cni_bin() -> String:
  "/opt/vk8s/cni/bin"

def NHost.cni_conf() -> String:
  "/opt/vk8s/cni/net.d"

# --- Ports: what the laws pin and how native moves it
#
# The plan pins the VM's ports (laws/plan.bend): the API server on 6443,
# the join server on 8443, etcd on 2379-2381, kine's metrics on 2381. A
# host runs several clusters, so each native cluster takes the API port
# the port picker chose (Vk8s.free_port, 10000..12999) and moves the rest
# by the same offset, as C.Cli.join_port does for a VM's forwards.

def NHost.join_port(+port: U32) -> U32:
  C.Cli.join_port(port)

def NHost.etcd_port(+port: U32) -> U32:
  (22000 + (port % 3000 : U32) : U32)

def NHost.peer_port(+port: U32) -> U32:
  (25000 + (port % 3000 : U32) : U32)

def NHost.metrics_port(+port: U32) -> U32:
  (28000 + (port % 3000 : U32) : U32)

# What a native cluster's runner needs beyond N.Env: the API port, whether
# it runs the host node (containerd, kubelet; the control plane is then
# also a node, as vcluster standalone's default), the host's arch for the
# image imports, and the resolv.conf the kubelet gives pods.
type Opts is Data:
  Opts{port: U32, node: Bool, arch: String, resolv: String}

def NHost.port(o: Opts) -> U32:
  match o:
    case Opts{p, n, a, r}:
      p

def NHost.node(o: Opts) -> Bool:
  match o:
    case Opts{p, n, a, r}:
      n

def NHost.arch(o: Opts) -> String:
  match o:
    case Opts{p, n, a, r}:
      a

def NHost.resolv(o: Opts) -> String:
  match o:
    case Opts{p, n, a, r}:
      r

# The native cluster's settings: vk8s's defaults, the host's address and
# the cluster's API port (the published kubeconfig names it).
def NHost.cfg(+name: String, +ip: String, +port: U32, +etcd: Bool) -> P.Cfg:
  P.Cfg{name, ip, "10.96.0.0/12", "10.244.0.0/16", "cluster.local", port, etcd}

def NHost.port_rules(+port: U32) -> +List<N.Rule>:
  +p = U32.show(port)
  [ N.Rule{"--secure-port=6443", "--secure-port=" ++ p},
    N.Rule{"bindPort: 6443", "bindPort: " ++ p},
    N.Rule{"\"port\":6443", "\"port\":" ++ p},
    N.Rule{":6443", ":" ++ p},
    N.Rule{"127.0.0.1:2379", "127.0.0.1:" ++ U32.show(NHost.etcd_port(port))},
    N.Rule{"127.0.0.1:2380", "127.0.0.1:" ++ U32.show(NHost.peer_port(port))},
    N.Rule{"127.0.0.1:2381", "127.0.0.1:" ++ U32.show(NHost.metrics_port(port))} ]

# The host node's paths: containerd's socket, state and config and the
# static pod dir under the data dir, the CNI dirs vk8s owns, and the image
# cache at the host's loopback (the cache VM's forwards) instead of the VM
# NAT's 10.0.2.2. The API server's certificate drops the VM NAT's
# addresses (Plan.kubeadm_config's certSANs 10.0.2.15 and 10.0.2.2): a
# host has neither.
def NHost.node_rules(+d: String) -> +List<N.Rule>:
  [ N.Rule{"  - 10.0.2.15\n  - 10.0.2.2\n", ""},
    N.Rule{"/run/containerd", d ++ "/node/run/containerd"},
    N.Rule{"/etc/containerd", d ++ "/node/containerd"},
    N.Rule{"/etc/kubernetes", d ++ "/node/kubernetes"},
    N.Rule{"/opt/cni/bin", NHost.cni_bin()},
    N.Rule{"/etc/cni/net.d", NHost.cni_conf()},
    N.Rule{"http://10.0.2.2:", "http://127.0.0.1:"} ]

def NHost.rules(+e: N.Env, +o: Opts) -> +List<N.Rule>:
  List.append(&2, N.Rule, NHost.port_rules(NHost.port(o)),
    List.append(&2, N.Rule, NHost.node_rules(N.Native.data(e)), N.Native.rules(e)))

# Every rule applied to s, left to right (N.Native.sub).
def NHost.str(+rs: +List<N.Rule>, +s: String) -> String:
  N.Native.sub(String.length(s), rs, s)

def NHost.strs(+rs: +List<N.Rule>, xs: +List<String>) -> +List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      Con{NHost.str(rs, x), NHost.strs(rs, t)}

def NHost.relocate.step(+rs: +List<N.Rule>, s: P.Step) -> P.Step:
  match s:
    case P.Mount{fs, src, dst, opts}:
      P.Mount{fs, NHost.str(rs, src), NHost.str(rs, dst), opts}
    case P.Write{path, text}:
      P.Write{NHost.str(rs, path), NHost.str(rs, text)}
    case P.Run{prog, args}:
      P.Run{NHost.str(rs, prog), NHost.strs(rs, args)}
    case P.Daemon{name, prog, args}:
      P.Daemon{name, NHost.str(rs, prog), NHost.strs(rs, args)}
    case P.Spawn{name, prog, args}:
      P.Spawn{name, NHost.str(rs, prog), NHost.strs(rs, args)}
    case P.WaitTcp{host, port, ms}:
      P.WaitTcp{host, port, ms}
    case P.Stop{names}:
      P.Stop{names}
    case P.WaitFile{path, ms}:
      P.WaitFile{NHost.str(rs, path), ms}
    case P.Modules{path}:
      P.Modules{NHost.str(rs, path)}
    case P.Log{text}:
      P.Log{text}

def NHost.relocate(+rs: +List<N.Rule>, ss: +List<P.Step>) -> +List<P.Step>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      Con{NHost.relocate.step(rs, s), NHost.relocate(rs, t)}

# --- What a host changes in the VM's steps

# The join server listens on the cluster's join port and reaches its own
# API server; the controller manager and the scheduler serve no HTTPS
# port, so a second cluster's do not collide on 10257 and 10259.
def NHost.extra_args.go(js: Bool, cs: Bool, +port: U32) -> +List<String>:
  match js cs:
    case True{} _:
      ["--port=" ++ U32.show(NHost.join_port(port)), "--api-port=" ++ U32.show(port)]
    case False{} True{}:
      ["--secure-port=0"]
    case False{} False{}:
      []

def NHost.extra_args(+port: U32, +name: String) -> +List<String>:
  NHost.extra_args.go(String.eq(name, "join-server"),
    Bool.or(String.eq(name, "kube-controller-manager"), String.eq(name, "kube-scheduler")), port)

# containerd on a host: the pod network namespaces under its state dir (so
# delete finds them with the data dir's mounts), no AppArmor profile, and
# no NRI socket in the host's /var/run/nri. The profile containerd loads
# on an AppArmor host (Ubuntu) denies a pod's signal to itself: dig's
# kill(getpid()) fails with EACCES and the DNS conformance tests fail.
# The container backend runs its nodes with apparmor=unconfined too.
def NHost.containerd_extra() -> String:
  "[plugins.'io.containerd.cri.v1.runtime']\n  netns_mounts_under_state_dir = true\n  disable_apparmor = true\n"
  ++ "[plugins.'io.containerd.nri.v1.nri']\n  disable = true\n"

# The host node's kubelet: the host's resolver file (systemd-resolved's
# upstream list, not its 127.0.0.53 stub, which pods cannot reach) and the
# pod logs under the data dir instead of /var/log/pods.
def NHost.kubelet_text(+resolv: String, +text: String) -> String:
  NHost.str([N.Rule{"resolvConf: /etc/resolv.conf\n", "resolvConf: " ++ resolv ++ "\n"}], text)
  ++ "podLogsDir: " ++ P.Plan.data() ++ "/pod-logs\n"

# containerd's runc runtime names its shim: containerd looks a shim up on
# PATH first and only then beside itself, and a host may have another
# containerd's shim on PATH (Docker's, in /usr/bin), another version
# ("bootstrap parameters do not match command-line arguments").
def NHost.containerd_text(+text: String) -> String:
  NHost.str([N.Rule{"  runtime_type = \"io.containerd.runc.v2\"\n",
    "  runtime_type = \"io.containerd.runc.v2\"\n  runtime_path = \"" ++ P.Plan.bin() ++ "/containerd-shim-runc-v2\"\n"}], text)
  ++ NHost.containerd_extra()

def NHost.extra.write(kl: Bool, cd: Bool, +resolv: String, +path: String, +text: String) -> P.Step:
  match kl cd:
    case True{} _:
      P.Write{path, NHost.kubelet_text(resolv, text)}
    case False{} True{}:
      P.Write{path, NHost.containerd_text(text)}
    case False{} False{}:
      P.Write{path, text}

# gVisor on a host node (docs/GOAL.md section 8): the VM's runsc runtime
# (P.Plan.containerd_runsc, its shim and runsc from the node set, which
# NHost.sets extracts into the data dir) and its RuntimeClass come with
# P.Plan.node. runsc keeps its state under the shim's root, by default
# the host's /run/containerd/runsc (gVisor pkg/shim/v1/proc/proc.go
# RunscRoot), where the host's own containerd keeps its: runsc.toml names
# that root (the shim's `root` option, pkg/shim/v1/runsc/options.go), and
# NHost.node_rules moves it under the data dir with containerd's state,
# so the node reset (NHost.reset) and delete remove it.
def NHost.runsc_text(+text: String) -> String:
  "root = \"/run/containerd/runsc\"\n" ++ text

def NHost.extra.write.v2(rs: Bool, kl: Bool, cd: Bool, +resolv: String, +path: String, +text: String) -> P.Step:
  match rs:
    case True{}:
      P.Write{path, NHost.runsc_text(text)}
    case False{}:
      NHost.extra.write(kl, cd, resolv, path, text)

def NHost.extra.step(+o: Opts, s: P.Step) -> P.Step:
  match s:
    case P.Daemon{+name, +prog, +args}:
      P.Daemon{name, prog, List.append(&2, String, args, NHost.extra_args(NHost.port(o), name))}
    case P.Write{+path, +text}:
      NHost.extra.write.v2(String.eq(path, "/etc/containerd/runsc.toml"),
        String.eq(path, P.Plan.data() ++ "/kubelet-config.yaml"), String.eq(path, "/etc/containerd/config.toml"),
        NHost.resolv(o), path, text)
    case other:
      other

def NHost.extra(+o: Opts, ss: +List<P.Step>) -> +List<P.Step>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      Con{NHost.extra.step(o, s), NHost.extra(o, t)}

def NHost.wait_port.etcd(et: Bool, +port: U32, +w: U32) -> U32:
  match et:
    case True{}:
      NHost.etcd_port(port)
    case False{}:
      w

def NHost.wait_port.join(js: Bool, +port: U32, +w: U32) -> U32:
  match js:
    case True{}:
      NHost.join_port(port)
    case False{}:
      NHost.wait_port.etcd(U32.is_eq(w, 2379), port, w)

def NHost.wait_port.api(api: Bool, +port: U32, +w: U32) -> U32:
  match api:
    case True{}:
      port
    case False{}:
      NHost.wait_port.join(U32.is_eq(w, 8443), port, w)

# A port the plan waits for, moved as its listener moved.
def NHost.wait_port(+port: U32, +w: U32) -> U32:
  NHost.wait_port.api(U32.is_eq(w, 6443), port, w)

# After relocation: the waits follow the ports, and the image imports name
# the host's platform (P.Plan.arch_args, as PID 1 does from VK8S_ARCH).
def NHost.post.step(+o: Opts, s: P.Step) -> P.Step:
  match s:
    case P.WaitTcp{+host, +w, +ms}:
      P.WaitTcp{host, NHost.wait_port(NHost.port(o), w), ms}
    case P.Run{+prog, +args}:
      P.Run{prog, P.Plan.arch_args(NHost.arch(o), args)}
    case other:
      other

def NHost.post(+o: Opts, ss: +List<P.Step>) -> +List<P.Step>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      Con{NHost.post.step(o, s), NHost.post(o, t)}

# VM steps as the host runs them: changed for the host, relocated (paths
# and ports), without a machine step, waits and imports adjusted.
def NHost.finish(+e: N.Env, +o: Opts, ss: +List<P.Step>) -> +List<P.Step>:
  NHost.post(o, N.Native.strip(NHost.relocate(NHost.rules(e, o), NHost.extra(o, ss))))

# Before the host node starts (a first start, or a restart of the unit,
# whose control-group kill left the pods' processes in kubelet's cgroups
# and their mounts behind): end the pods, unmount what they left under the
# data dir and start containerd and the kubelet afresh, as a VM's reboot
# does (the pods are made again).
def NHost.reset_script(+d: String) -> String:
  "k=/sys/fs/cgroup/kubepods; if [ -e $k/cgroup.kill ]; then echo 1 > $k/cgroup.kill; sleep 2; fi; "
  ++ "awk -v d=" ++ P.Plan.sh_quote(d ++ "/") ++ " 'index($5, d) == 1 { print $5 }' /proc/self/mountinfo | sort -r | "
  ++ "while read -r m; do umount -l \"$m\" || true; done; "
  ++ "rm -rf " ++ P.Plan.sh_quote(d ++ "/kubelet") ++ " " ++ P.Plan.sh_quote(d ++ "/node/run") ++ "; "
  ++ "if [ -d $k ]; then find $k -depth -type d -exec rmdir {} + 2>/dev/null; fi; true"

def NHost.reset(+e: N.Env) -> P.Step:
  P.Run{N.Native.busybox(e), ["sh", "-c", NHost.reset_script(N.Native.data(e))]}

def NHost.plan.cp(+c: P.Cfg) -> +List<P.Step>:
  List.append(&2, P.Step, P.Plan.pki_steps(c), N.Native.with_join_args(c, P.Plan.control_plane(c)))

def NHost.boot.go(node: Bool, +e: N.Env, +o: Opts, +c: P.Cfg) -> +List<P.Step>:
  match node:
    case True{}:
      List.append(&2, P.Step, NHost.finish(e, o, NHost.plan.cp(c)),
        Con{NHost.reset(e), NHost.finish(e, o, List.append(&2, P.Step, P.Plan.node(c), P.Plan.publish(c)))})
    case False{}:
      NHost.finish(e, o, N.Native.plan(c))

# The native boot plan of a cluster on a host. With the host node: the PKI
# and the control plane, the node reset, then the VM's Plan.node
# (containerd, the kubelet, kube-proxy, flannel, CoreDNS, the join
# material) and the kubeconfig. Without: N.Native.plan, a control plane
# only (a second cluster on a host whose node another cluster runs).
def NHost.boot(+e: N.Env, +o: Opts, +c: P.Cfg) -> +List<P.Step>:
  NHost.boot.go(NHost.node(o), e, o, c)

# --- The unit (N3)

# A cluster as the host installs it.
type Inst is Data:
  Inst{name: String, data: String, share: String, ip: String, port: U32, etcd: Bool, node: Bool, arch: String, resolv: String}

def NHost.flag(b: Bool) -> String:
  match b:
    case True{}:
      "1"
    case False{}:
      "0"

# The unit: the installed vk8s in native supervisor mode over the data
# dir, restarted 5 s after it exits (vcluster's install-standalone.sh:
# Restart=always, RestartSec=5s, Delegate=yes). KillMode=control-group,
# not vcluster's process: stopping the unit ends every process it started
# (the daemons, containerd's shims), so delete leaves none. The
# environment is what NInit.main reads.
def NHost.unit(i: Inst) -> String:
  match i:
    case Inst{+name, +data, +share, +ip, +port, +etcd, +node, +arch, +resolv}:
      "[Unit]\nDescription=vk8s native cluster " ++ name ++ "\n"
      ++ "Wants=network-online.target\nAfter=network-online.target\n"
      ++ "\n[Service]\nType=simple\n"
      ++ "Environment=VK8S_DATA=" ++ data ++ "\n"
      ++ "Environment=VK8S_SHARE=" ++ share ++ "\n"
      ++ "Environment=VK8S_NAME=" ++ name ++ "\n"
      ++ "Environment=VK8S_STORE=" ++ C.Cli.store_name(etcd) ++ "\n"
      ++ "Environment=VK8S_NODE_IP=" ++ ip ++ "\n"
      ++ "Environment=VK8S_PORT=" ++ U32.show(port) ++ "\n"
      ++ "Environment=VK8S_HOST_NODE=" ++ NHost.flag(node) ++ "\n"
      ++ "Environment=VK8S_ARCH=" ++ arch ++ "\n"
      ++ "Environment=VK8S_RESOLV=" ++ resolv ++ "\n"
      ++ "Environment=VK8S_JOIN_INSTALL=1\n"
      ++ "ExecStart=" ++ data ++ "/vk8s native\n"
      ++ "Restart=always\nRestartSec=5s\n"
      ++ "KillMode=control-group\nDelegate=yes\n"
      ++ "TimeoutStopSec=90\nLimitNOFILE=1048576\nTasksMax=infinity\n"
      ++ "\n[Install]\nWantedBy=multi-user.target\n"

# --- What the host runs, as argument lists (no shell)

# A word as a shell would need it to read back the same: bare when every
# character is safe (letters, digits, / : - _ . = , @ % +), else quoted.
def NHost.in_u32(xs: List<&2, U32>, +c: U32) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{x, t}:
      Bool.or(U32.is_eq(x, c), NHost.in_u32(t, c))

def NHost.safe_chr(+c: U32) -> Bool:
  Bool.or(Bool.or(Bool.and(U32.is_ge(c, 97), U32.is_le(c, 122)), Bool.and(U32.is_ge(c, 65), U32.is_le(c, 90))),
    Bool.or(Bool.and(U32.is_ge(c, 47), U32.is_le(c, 58)), NHost.in_u32([45, 95, 46, 61, 44, 64, 37, 43], c)))

def NHost.safe_all(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{Chr{+c}, t}:
      Bool.and(NHost.safe_chr(c), NHost.safe_all(t))

def NHost.word.go(bare: Bool, +w: String) -> String:
  match bare:
    case True{}:
      w
    case False{}:
      P.Plan.sh_quote(w)

def NHost.word(+w: String) -> String:
  NHost.word.go(Bool.and(Bool.not(String.is_empty(w)), NHost.safe_all(w)), w)

def NHost.words(ws: +List<String>) -> String:
  match ws:
    case Nil{}:
      ""
    case Con{w, t}:
      " " ++ NHost.word(w) ++ NHost.words(t)

# The line printed before a command runs.
def NHost.show(ws: +List<String>) -> String:
  "+" ++ NHost.words(ws)

# The role sets the native cluster runs from (scripts/guest/sets.txt):
# the node set (kubelet, kubeadm, containerd, runc, the CNI plugins, the
# pause image, gVisor's runsc and its containerd shim) and the
# control-plane set.
def NHost.sets() -> +List<String>:
  ["node", "control-plane"]

def NHost.set_cmds(sets: +List<String>, +assets: String, +bin: String) -> List<&2, List<&2, String>>:
  match sets:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      Con{["sudo", "unsquashfs", "-f", "-n", "-d", bin, assets ++ "/" ++ s ++ ".img"], NHost.set_cmds(t, assets, bin)}

# N4: the data dir, the vk8s binary installed in it (the unit runs that
# copy), busybox and flannel's manifest from the initramfs (GNU cpio), and
# the role sets extracted once into its bin dir (unsquashfs): no loop
# device or mount to restore after a reboot or to leak on delete; the cost
# is the sets' unpacked size per cluster (docs/ref/native-host.md).
def NHost.prepare_cmds(+data: String, +assets: String, +self: String, sets: +List<String>) -> List<&2, List<&2, String>>:
  List.append(&2, List<&2, String>,
    [ ["sudo", "mkdir", "-p", "-m", "0700", data],
      ["sudo", "install", "-m", "0755", self, data ++ "/vk8s"],
      ["sudo", "mkdir", "-p", data ++ "/initramfs"],
      ["sudo", "cpio", "-i", "-d", "--quiet", "--no-absolute-filenames", "-D", data ++ "/initramfs", "-F", assets ++ "/vk8s.cpio",
        "bin/busybox", "etc/vk8s/flannel.yaml"],
      ["sudo", "install", "-m", "0755", data ++ "/initramfs/bin/busybox", data ++ "/busybox"] ],
    NHost.set_cmds(sets, assets, data ++ "/bin"))

# flannel's manifest (scripts/guest/flannel.yaml) for a host node: no
# --iface=eth1 (the VM's LAN NIC; flanneld then takes the host's default
# route interface), and vk8s's CNI dirs for the plugin and its config.
def NHost.flannel(+text: String) -> String:
  NHost.str([ N.Rule{"        - --iface=eth1\n", ""},
              N.Rule{"/opt/cni/bin", NHost.cni_bin()},
              N.Rule{"/etc/cni/net.d", NHost.cni_conf()} ], text)

# Install and start the unit (tmp: the unit's text, written by the user).
def NHost.install_cmds(+name: String, +tmp: String) -> List<&2, List<&2, String>>:
  [ ["sudo", "install", "-m", "0644", tmp, NHost.unit_path(name)],
    ["sudo", "systemctl", "daemon-reload"],
    ["sudo", "systemctl", "enable", "--now", NHost.unit_name(name)] ]

# --- Delete (N3)

# First: stop the unit (KillMode=control-group ends every process it
# started) and keep it from starting at boot.
def NHost.stop_cmds(+name: String) -> List<&2, List<&2, String>>:
  [["sudo", "systemctl", "disable", "--now", NHost.unit_name(name)]]

# What a host node leaves outside the data dir: the bridge (flannel's
# host-gw backend has no flannel.1, a vxlan backend would), flannel's
# subnet file, the CNI plugins' state, vk8s's CNI dirs and the kubelet's
# links to the pod logs.
def NHost.node_remove_cmds(+data: String) -> List<&2, List<&2, String>>:
  [ ["sudo", "ip", "link", "delete", "cni0"],
    ["sudo", "ip", "link", "delete", "flannel.1"],
    ["sudo", "rm", "-rf", "--one-file-system", "/run/flannel", "/var/lib/cni/flannel", "/var/lib/cni/networks/cbr0", "/opt/vk8s"],
    ["sudo", "find", "/var/lib/cni/results", "-maxdepth", "1", "-name", "cbr0-*", "-delete"],
    ["sudo", "find", "/var/log/containers", "-maxdepth", "1", "-lname", data ++ "/*", "-delete"],
    ["sudo", "rmdir", "--ignore-fail-on-non-empty", "/var/lib/cni/networks", "/var/lib/cni/results", "/var/lib/cni"] ]

def NHost.node_remove.go(node: Bool, +data: String) -> List<&2, List<&2, String>>:
  match node:
    case True{}:
      NHost.node_remove_cmds(data)
    case False{}:
      []

# Then, once the pods' processes are gone and their mounts unmounted
# (NHost.umount_cmds), the iptables rules cleaned (NHost.ipt_clean): the
# data dir (never across a mount: --one-file-system), the unit file, the
# host node's leftovers and the user's cluster dir (the unit wrote its
# share).
def NHost.remove_cmds(+name: String, +dir: String, node: Bool) -> List<&2, List<&2, String>>:
  +data = NHost.data_dir(name)
  List.append(&2, List<&2, String>, NHost.node_remove.go(node, data),
    [ ["sudo", "rm", "-rf", "--one-file-system", data],
      ["sudo", "rmdir", "--ignore-fail-on-non-empty", "/var/lib/vk8s"],
      ["sudo", "rm", "-f", NHost.unit_path(name)],
      ["sudo", "systemctl", "daemon-reload"],
      ["sudo", "rm", "-rf", "--one-file-system", dir] ])

def NHost.delete_cmds(+name: String, +dir: String, node: Bool) -> List<&2, List<&2, String>>:
  List.append(&2, List<&2, String>, NHost.stop_cmds(name), NHost.remove_cmds(name, dir, node))

# What create makes: the unit (enabled), its file, the data dir, the
# cluster dir; with the host node, the bridge, flannel's files and vk8s's
# CNI dirs. (Pods' cgroups, mounts and iptables rules come and go with the
# pods; delete ends them by NHost.umount_cmds and NHost.ipt_clean.)
def NHost.made.node(node: Bool) -> +List<String>:
  match node:
    case True{}:
      ["link:cni0", "/run/flannel", "/var/lib/cni/flannel", "/var/lib/cni/networks/cbr0", "/opt/vk8s"]
    case False{}:
      []

def NHost.made(+name: String, +dir: String, node: Bool) -> +List<String>:
  List.append(&2, String, ["unit:" ++ NHost.unit_name(name), NHost.unit_path(name), NHost.data_dir(name), dir], NHost.made.node(node))

def NHost.at(xs: +List<String>, n: Nat) -> String:
  match xs n:
    case Nil{} _:
      ""
    case Con{x, t} 0n:
      x
    case Con{x, t} 1n+p:
      NHost.at(t, p)

def NHost.last.go(empty: Bool, +x: String, +rest: String) -> String:
  match empty:
    case True{}:
      x
    case False{}:
      rest

def NHost.last(xs: +List<String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+x, +t}:
      NHost.last.go(List.is_empty(&2, String, t), x, NHost.last(t))

def NHost.keep.go(ok: Bool, +x: String, rest: +List<String>) -> +List<String>:
  match ok:
    case True{}:
      Con{x, rest}
    case False{}:
      rest

def NHost.paths(xs: +List<String>) -> +List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, t}:
      NHost.keep.go(String.starts_with(x, "/"), x, NHost.paths(t))

def NHost.target.rm(rm: Bool, +ws: +List<String>) -> +List<String>:
  match rm:
    case True{}:
      NHost.paths(ws)
    case False{}:
      []

def NHost.target.ip(ip: Bool, rm: Bool, +ws: +List<String>) -> +List<String>:
  match ip:
    case True{}:
      ["link:" ++ NHost.at(ws, 4n)]
    case False{}:
      NHost.target.rm(rm, ws)

def NHost.target.go(unit: Bool, ip: Bool, rm: Bool, +ws: +List<String>) -> +List<String>:
  match unit:
    case True{}:
      ["unit:" ++ NHost.last(ws)]
    case False{}:
      NHost.target.ip(ip, rm, ws)

# What one command removes: the unit it disables, the link it deletes,
# the paths rm or rmdir removes.
def NHost.target(+ws: +List<String>) -> +List<String>:
  NHost.target.go(Bool.and(String.eq(NHost.at(ws, 1n), "systemctl"), String.eq(NHost.at(ws, 2n), "disable")),
    String.eq(NHost.at(ws, 1n), "ip"), Bool.or(String.eq(NHost.at(ws, 1n), "rm"), String.eq(NHost.at(ws, 1n), "rmdir")), ws)

def NHost.removes(cs: List<&2, List<&2, String>>) -> +List<String>:
  match cs:
    case Nil{}:
      Nil{}
    case Con{c, t}:
      List.append(&2, String, NHost.target(c), NHost.removes(t))

def NHost.left.go(gone: Bool, +x: String, rest: +List<String>) -> +List<String>:
  match gone:
    case True{}:
      rest
    case False{}:
      Con{x, rest}

# What of `made` no command of `removed` takes away.
def NHost.leftover(made: +List<String>, +removed: +List<String>) -> +List<String>:
  match made:
    case Nil{}:
      Nil{}
    case Con{+x, t}:
      NHost.left.go(S.Sup.member(removed, x), x, NHost.leftover(t, removed))

# --- Mounts: /proc/self/mountinfo's fifth field is the mount point.

def NHost.mount_point(+line: String) -> String:
  NHost.at(String.split(line, ' '), 4n)

def NHost.under(+p: String, +d: String) -> Bool:
  Bool.or(String.eq(p, d), String.starts_with(p, d ++ "/"))

def NHost.mounts.go(ls: +List<String>, +d: String) -> +List<String>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{+l, t}:
      NHost.keep.go(NHost.under(NHost.mount_point(l), d), NHost.mount_point(l), NHost.mounts.go(t, d))

# The mount points under the data dir, the last mounted first (an inner
# mount before the one that holds it).
def NHost.mounts_under(+text: String, +d: String) -> +List<String>:
  List.reverse(&2, String, NHost.mounts.go(String.lines(text), d))

def NHost.umount_cmds(ms: +List<String>) -> List<&2, List<&2, String>>:
  match ms:
    case Nil{}:
      Nil{}
    case Con{m, t}:
      Con{["sudo", "umount", "-l", m], NHost.umount_cmds(t)}

# --- iptables: the rules and chains of kube-proxy (KUBE-), flannel
# (FLANNEL-) and the CNI plugins (CNI-) leave; every other rule stays.
# A save (iptables-save) is cut into its tables; only a table that held
# such a line is given back to iptables-restore, cleaned, so tables vk8s
# never touched are not rewritten.

def NHost.ipt_marks() -> +List<String>:
  ["KUBE-", "FLANNEL-", "CNI-"]

def NHost.ipt_ours(ms: +List<String>, +l: String) -> Bool:
  match ms:
    case Nil{}:
      False{}
    case Con{m, t}:
      Bool.or(String.contains(l, m), NHost.ipt_ours(t, l))

def NHost.ipt_keep(ls: +List<String>) -> +List<String>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{+l, t}:
      NHost.keep.go(Bool.not(NHost.ipt_ours(NHost.ipt_marks(), l)), l, NHost.ipt_keep(t))

def NHost.ipt_add.line(+l: String, gs: List<&2, List<&2, String>>) -> List<&2, List<&2, String>>:
  match gs:
    case Nil{}:
      [[l]]
    case Con{g, t}:
      Con{Con{l, g}, t}

def NHost.ipt_add(head: Bool, +l: String, gs: List<&2, List<&2, String>>) -> List<&2, List<&2, String>>:
  match head:
    case True{}:
      Con{[], NHost.ipt_add.line(l, gs)}
    case False{}:
      NHost.ipt_add.line(l, gs)

# The save's lines in groups, each starting at a table's "*name" line
# (the first group holds what comes before the first table).
def NHost.ipt_tables(ls: +List<String>) -> List<&2, List<&2, String>>:
  match ls:
    case Nil{}:
      [[]]
    case Con{+l, t}:
      NHost.ipt_add(String.starts_with(l, "*"), l, NHost.ipt_tables(t))

def NHost.ipt_pick(changed: Bool, kept: +List<String>) -> +List<String>:
  match changed:
    case True{}:
      kept
    case False{}:
      []

def NHost.ipt_table(+g: +List<String>) -> +List<String>:
  NHost.ipt_pick(Bool.not(Nat.is_eq(List.length(&2, String, NHost.ipt_keep(g)), List.length(&2, String, g))), NHost.ipt_keep(g))

def NHost.ipt_changed(gs: List<&2, List<&2, String>>) -> +List<String>:
  match gs:
    case Nil{}:
      Nil{}
    case Con{+g, t}:
      List.append(&2, String, NHost.ipt_table(g), NHost.ipt_changed(t))

def NHost.ipt_line(empty: Bool, +l: String) -> String:
  match empty:
    case True{}:
      ""
    case False{}:
      l ++ "\n"

def NHost.ipt_text(ls: +List<String>) -> String:
  match ls:
    case Nil{}:
      ""
    case Con{+l, t}:
      NHost.ipt_line(String.is_empty(l), l) ++ NHost.ipt_text(t)

# The input for iptables-restore, "" when nothing is vk8s's.
def NHost.ipt_clean(+text: String) -> String:
  NHost.ipt_text(NHost.ipt_changed(NHost.ipt_tables(String.lines(text))))

# The iptables programs delete reads and writes, by stem (`<stem>-save`
# and `<stem>-restore`): IPv4 and IPv6, the nf_tables and the legacy
# back ends (kube-proxy's and flannel's images pick one by what the host
# already uses).
def NHost.ipt_tools() -> +List<String>:
  [ "iptables", "ip6tables", "iptables-legacy", "ip6tables-legacy" ]

# --- The host's address: `ip -4 -o route get 1.1.1.1` names the source
# address of the default route after "src".

def NHost.after_src.go(hit: Bool, +next: String, +rest: String) -> String:
  match hit:
    case True{}:
      next
    case False{}:
      rest

def NHost.after_src(ws: +List<String>) -> String:
  match ws:
    case Nil{}:
      ""
    case Con{+w, +t}:
      NHost.after_src.go(String.eq(w, "src"), NHost.at(t, 0n), NHost.after_src(t))

def NHost.route_src(+text: String) -> String:
  NHost.after_src(String.split(String.trim(text), ' '))

def NHost.ip_chr(+c: U32) -> Bool:
  Bool.or(U32.is_eq(c, 46), Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57)))

def NHost.ip_all(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{Chr{+c}, t}:
      Bool.and(NHost.ip_chr(c), NHost.ip_all(t))

# A dotted IPv4 address (digits and dots, three dots).
def NHost.ip_ok(+ip: String) -> Bool:
  Bool.and(NHost.ip_all(ip), Nat.is_eq(List.length(&2, String, String.split(ip, '.')), 4n))

# --- Preflight (N4)

# The host tools native mode runs.
def NHost.tools() -> +List<String>:
  ["sudo", "systemctl", "unsquashfs", "cpio", "ip", "iptables-save", "iptables-restore", "kubectl", "perl"]

# The kernel modules a host node needs: overlay (containerd's overlayfs
# snapshotter) and br_netfilter (bridged pod traffic through kube-proxy's
# rules), as vcluster's docker driver loads them (docker_runtime.go).
def NHost.modules() -> +List<String>:
  ["overlay", "br_netfilter"]

def NHost.sysctl_if(need: Bool, +kv: String) -> +List<String>:
  match need:
    case True{}:
      [kv]
    case False{}:
      []

# The sysctls a host node needs, from their current values (the files'
# text; "" when the file is missing): IPv4 forwarding and bridged traffic
# through iptables.
def NHost.sysctls_needed(node: Bool, +fwd: String, +bnf: String) -> +List<String>:
  match node:
    case True{}:
      List.append(&2, String, NHost.sysctl_if(Bool.not(String.eq(String.trim(fwd), "1")), "net.ipv4.ip_forward=1"),
        NHost.sysctl_if(Bool.not(String.eq(String.trim(bnf), "1")), "net.bridge.bridge-nf-call-iptables=1"))
    case False{}:
      []

def NHost.proxy_sysctls.go(on: Bool, node: Bool, +arp: String, +ndp: String) -> +List<String>:
  match on node:
    case True{} True{}:
      List.append(&2, String, NHost.sysctl_if(Bool.not(String.eq(String.trim(arp), "1")), "net.ipv4.conf.all.proxy_arp=1"),
        NHost.sysctl_if(Bool.not(String.is_empty(ndp)) && Bool.not(String.eq(String.trim(ndp), "1")), "net.ipv6.conf.all.proxy_ndp=1"))
    case _ _:
      []

# vk8s.nodes.proxyArp (on; src/guest/values.bend) on a host node: the
# proxy sysctls that are not 1 yet, from the files' text (arp:
# net/ipv4/conf/all/proxy_arp; ndp: net/ipv6/conf/all/proxy_ndp, "" when
# missing: a host without IPv6 skips it). They are host-wide: the
# preflight asks for them with sudo, as for the others.
def NHost.proxy_sysctls_needed(on: Bool, node: Bool, +arp: String, +ndp: String) -> +List<String>:
  NHost.proxy_sysctls.go(on, node, arp, ndp)

def NHost.line_if(need: Bool, +line: String) -> String:
  match need:
    case True{}:
      line
    case False{}:
      ""

def NHost.preflight.go(+body: String) -> String:
  NHost.line_if(Bool.not(String.is_empty(body)), "vk8s: --backend native needs this first:\n" ++ body)

# The preflight message, "" when the host is ready: each missing piece,
# and for modules and sysctls the exact command to run.
def NHost.preflight(+tools: +List<String>, systemd: Bool, cgroup2: Bool, +mods: +List<String>, +sysctls: +List<String>) -> String:
  NHost.preflight.go(
    NHost.line_if(Bool.not(List.is_empty(&2, String, tools)), "- install: " ++ String.join(tools, " ") ++ "\n")
    ++ NHost.line_if(Bool.not(systemd), "- systemd as the init system (/run/systemd/system)\n")
    ++ NHost.line_if(Bool.not(cgroup2), "- the unified cgroup v2 hierarchy at /sys/fs/cgroup\n")
    ++ NHost.line_if(Bool.not(List.is_empty(&2, String, mods)), "- run: sudo modprobe -a " ++ String.join(mods, " ") ++ "\n")
    ++ NHost.line_if(Bool.not(List.is_empty(&2, String, sysctls)), "- run: sudo sysctl -w " ++ String.join(sysctls, " ") ++ "\n"))

# --nodes N with --backend native: nodes join by token (N5).
def NHost.nodes_msg(+name: String) -> String:
  "vk8s: --backend native does not start worker VMs; join nodes with `vk8s token create " ++ name
  ++ "` and run the printed command on each node (docs/ref/native-host.md)"

# The cluster's settings (cluster.env), as a VM's (Vk8s.env_file) plus the
# native backend's.
def NHost.env_text(+name: String, +port: U32, +etcd: Bool, +ip: String, node: Bool) -> String:
  "NAME=" ++ name ++ "\nGUEST=" ++ name ++ "\nPORT=" ++ U32.show(port) ++ "\nCPUS=0\nMEMORY=0\nSTORE=" ++ C.Cli.store_name(etcd)
  ++ "\nNODES=0\nWORKERS=\nKUBERNETES=v1.36.6\nBACKEND=native\nNODE_IP=" ++ ip ++ "\nHOST_NODE=" ++ NHost.flag(node)
  ++ "\nDATA=" ++ NHost.data_dir(name) ++ "\nUNIT=" ++ NHost.unit_name(name)
  ++ "\nAPI_ENDPOINT=" ++ ip ++ ":" ++ U32.show(port) ++ "\nJOIN_ENDPOINT=" ++ ip ++ ":" ++ U32.show(NHost.join_port(port)) ++ "\n"

def NHost.or(+v: String, +d: String) -> String:
  N.Native.or(v, d)

# --- v2: native mode touches only what is the cluster's own (security
# review docs/ref/review-security-boundary-delta.md, F1). The v1 defs
# above stay as their laws pin them; the host runs these.

# The host node's kubelet runs its pods under a cgroup root of the
# cluster's own (kubelet --cgroup-root, as container mode's
# Container.kubelet_root), not the host's shared /kubepods, so the node
# reset and delete end only this cluster's pods.
def NHost.cgroup_root(+name: String) -> String:
  "/vk8s-" ++ name

def NHost.cgroup_dir(+name: String) -> String:
  "/sys/fs/cgroup" ++ NHost.cgroup_root(name)

# The line create adds to cluster.env: a cluster without it was made
# before v2 and runs its pods under /kubepods.
def NHost.env_cgroup(+name: String) -> String:
  "CGROUP=" ++ NHost.cgroup_root(name) ++ "\n"

def NHost.cfg_name(c: P.Cfg) -> String:
  match c:
    case P.Cfg{name, ip, svc, pod, dom, port, etcd}:
      name

def NHost.kubelet_root.daemon(hit: Bool, +root: String, +name: String, +prog: String, +args: +List<String>) -> P.Step:
  match hit:
    case True{}:
      P.Daemon{name, prog, List.append(&2, String, args, [P.Plan.flag("cgroup-root", root)])}
    case False{}:
      P.Daemon{name, prog, args}

def NHost.kubelet_root.step(+root: String, s: P.Step) -> P.Step:
  match s:
    case P.Daemon{+name, +prog, +args}:
      NHost.kubelet_root.daemon(String.eq(name, "kubelet"), root, name, prog, args)
    case other:
      other

# The kubelet daemon of a plan with the cluster's cgroup root; every
# other step stays.
def NHost.kubelet_root(+root: String, ss: +List<P.Step>) -> +List<P.Step>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      Con{NHost.kubelet_root.step(root, s), NHost.kubelet_root(root, t)}

# The processes that run a node: a kubelet, k3s (its server and agent
# name themselves k3s-server and k3s-agent) and MicroK8s's kubelite.
def NHost.kubelet_names() -> +List<String>:
  ["kubelet", "k3s", "k3s-server", "k3s-agent", "kubelite"]

# A shell script (root, so it reads every process's links) that prints
# "<pid> <name> <exe>" for each such process in the host's network
# namespace, the one native mode's rules and pods share. A node in its own
# namespace (container mode, kind) does not count.
def NHost.kubelets_script() -> String:
  "n=$(readlink /proc/1/ns/net); for p in /proc/[0-9]*; do c=$(cat $p/comm 2>/dev/null) || continue; case $c in ("
  ++ String.join(NHost.kubelet_names(), "|")
  ++ ") if [ \"$(readlink $p/ns/net)\" = \"$n\" ]; then echo \"${p#/proc/} $c $(readlink $p/exe)\"; fi;; esac; done; true"

# A kubelet of a vk8s native cluster runs from its data dir.
def NHost.vk8s_exe(+l: String) -> Bool:
  String.starts_with(NHost.at(String.split(l, ' '), 2n), "/var/lib/vk8s/")

def NHost.kubelets.want(ours: Bool, +l: String) -> Bool:
  match ours:
    case True{}:
      NHost.vk8s_exe(l)
    case False{}:
      Bool.not(NHost.vk8s_exe(l))

def NHost.kubelets.go(+ours: Bool, ls: +List<String>) -> +List<String>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{+l, t}:
      NHost.keep.go(Bool.and(Bool.not(String.is_empty(String.trim(l))), NHost.kubelets.want(ours, String.trim(l))),
        String.trim(l), NHost.kubelets.go(ours, t))

# From the script's output: the kubelets that are not vk8s's (k3s, a
# kubeadm node), and those that are (another native cluster's host node).
def NHost.foreign_kubelets(+text: String) -> +List<String>:
  NHost.kubelets.go(False{}, String.lines(text))

def NHost.vk8s_kubelets(+text: String) -> +List<String>:
  NHost.kubelets.go(True{}, String.lines(text))

# Create refuses while another kubelet runs on the host: its pods, its
# kube-proxy and its CNI share the host's iptables chains and cgroups.
def NHost.foreign_msg(+ks: +List<String>) -> String:
  "vk8s: --backend native: another kubelet runs on this host (" ++ String.join(ks, ", ")
  ++ "); a native cluster would share the host's iptables chains and cgroups with it. Stop it, or use another --backend"

# What delete says when another kubelet runs on the host (the script's
# lines): what it leaves.
def NHost.shared_note(+text: String) -> String:
  "  (another kubelet runs on this host: " ++ String.join(String.lines(String.trim(text)), ", ")
  ++ "; its kube-proxy, flannel and kube-router share these chain and ipset names, so delete leaves them and removes only vk8s's gate chain)"

# The v2 reset's kill: the cluster's own cgroup root only ($c, used again
# below), never the host's /kubepods.
def NHost.reset_kill.v2(+name: String) -> String:
  "c=" ++ NHost.cgroup_dir(name) ++ "; if [ -e $c/cgroup.kill ]; then echo 1 > $c/cgroup.kill; sleep 2; fi; "

# Before the host node starts, as NHost.reset_script, with two changes:
# it refuses (exits 1, which stops the boot before containerd and the
# kubelet) while another kubelet runs on the host (this unit's own ended
# with its last start) or while the host's /sys/fs/cgroup/kubepods holds
# a process (pods that are not this cluster's); and it ends, removes and
# makes again only the cluster's own cgroup root.
def NHost.reset_script.v2(+d: String, +name: String) -> String:
  "o=$(" ++ NHost.kubelets_script() ++ "); if [ -n \"$o\" ]; then echo \"vk8s: another kubelet runs on this host ($o); the host node does not start\"; exit 1; fi; "
  ++ "k=/sys/fs/cgroup/kubepods; if [ -d $k ] && find $k -name cgroup.procs -exec cat {} + 2>/dev/null | grep -q .; then "
  ++ "echo \"vk8s: $k holds pods that are not this cluster's; the host node does not start\"; exit 1; fi; "
  ++ NHost.reset_kill.v2(name)
  ++ "awk -v d=" ++ P.Plan.sh_quote(d ++ "/") ++ " 'index($5, d) == 1 { print $5 }' /proc/self/mountinfo | sort -r | "
  ++ "while read -r m; do umount -l \"$m\" || true; done; "
  ++ "rm -rf " ++ P.Plan.sh_quote(d ++ "/kubelet") ++ " " ++ P.Plan.sh_quote(d ++ "/node/run") ++ "; "
  ++ "if [ -d $c ]; then find $c -mindepth 1 -depth -type d -exec rmdir {} + 2>/dev/null; fi; "
  ++ "mkdir -p $c && { sed -e 's/ / +/g' -e 's/^/+/' $c/cgroup.controllers > $c/cgroup.subtree_control || true; }"

def NHost.reset.v2(+e: N.Env, +name: String) -> P.Step:
  P.Run{N.Native.busybox(e), ["sh", "-c", NHost.reset_script.v2(N.Native.data(e), name)]}

# v3 of the node reset: v2, and before the cluster's cgroup is made, the
# root cgroup passes each of its controllers down (cgroup v2
# cgroup.subtree_control). The kubelet refuses a --cgroup-root that lacks
# a controller it needs ("cgroup [\"vk8s-demo\"] has some missing
# controllers: hugetlb"); the default root "/" has them all. A
# controller the kernel refuses to enable is skipped.
def NHost.root_ctl() -> String:
  "r=/sys/fs/cgroup; for x in $(cat $r/cgroup.controllers); do echo +$x > $r/cgroup.subtree_control 2>/dev/null || true; done; "

def NHost.reset_script.v3(+d: String, +name: String) -> String:
  NHost.root_ctl() ++ NHost.reset_script.v2(d, name)

def NHost.reset.v3(+e: N.Env, +name: String) -> P.Step:
  P.Run{N.Native.busybox(e), ["sh", "-c", NHost.reset_script.v3(N.Native.data(e), name)]}

def NHost.boot.v2.go(node: Bool, +e: N.Env, +o: Opts, +c: P.Cfg) -> +List<P.Step>:
  match node:
    case True{}:
      List.append(&2, P.Step, NHost.finish(e, o, NHost.plan.cp(c)),
        Con{NHost.reset.v2(e, NHost.cfg_name(c)), NHost.kubelet_root(NHost.cgroup_root(NHost.cfg_name(c)),
          NHost.finish(e, o, List.append(&2, P.Step, P.Plan.node(c), P.Plan.publish(c))))})
    case False{}:
      NHost.finish(e, o, N.Native.plan(c))

# NHost.boot with the v2 node reset and the kubelet under the cluster's
# cgroup root.
def NHost.boot.v2(+e: N.Env, +o: Opts, +c: P.Cfg) -> +List<P.Step>:
  NHost.boot.v2.go(NHost.node(o), e, o, c)

# Which cgroup delete ends and removes: the cluster's own; for a cluster
# made before v2 (no CGROUP in cluster.env), /kubepods, and nothing when
# another kubelet runs (its pods are there too).
def NHost.kill_dir.go(legacy: Bool, shared: Bool, +name: String) -> String:
  match legacy shared:
    case True{} True{}:
      ""
    case True{} False{}:
      "/sys/fs/cgroup/kubepods"
    case False{} _:
      NHost.cgroup_dir(name)

def NHost.kill_dir(+cgroup: String, shared: Bool, +name: String) -> String:
  NHost.kill_dir.go(String.is_empty(cgroup), shared, name)

# --- v2 iptables: delete only vk8s's chains and the rules that jump to
# them, by exact name, with iptables-restore --noflush (every other chain
# and rule stays; no table is replaced). A chain is vk8s's when it is a
# user chain (policy "-") of the save and its name is one of the fixed
# names, or a hashed name (one of the prefixes and exactly 16 characters
# of base32, as kube-proxy's and kube-router's are), or the target of a
# rule tagged with the network's name (the CNI plugins' comment).

# kubelet (pkg/kubelet/kubelet_network_linux.go: KUBE-IPTABLES-HINT,
# KUBE-FIREWALL, KUBE-KUBELET-CANARY), kube-proxy's iptables mode
# (pkg/proxy/iptables/proxier.go:56-82) and flannel
# (pkg/trafficmngr/iptables/iptables.go: FLANNEL-POSTRTG, FLANNEL-FWD).
def NHost.ipt_names() -> +List<String>:
  [ "KUBE-IPTABLES-HINT", "KUBE-FIREWALL", "KUBE-KUBELET-CANARY",
    "KUBE-SERVICES", "KUBE-EXTERNAL-SERVICES", "KUBE-NODEPORTS", "KUBE-POSTROUTING", "KUBE-MARK-MASQ",
    "KUBE-FORWARD", "KUBE-PROXY-FIREWALL", "KUBE-PROXY-CANARY",
    "FLANNEL-POSTRTG", "FLANNEL-FWD" ]

# kube-proxy's per-service chains (proxier.go:540-544, then
# base32.StdEncoding of a sha256, cut to 16).
def NHost.ipt_hashed() -> +List<String>:
  ["KUBE-SVC-", "KUBE-SVL-", "KUBE-FW-", "KUBE-EXT-", "KUBE-SEP-"]

# The CNI plugins' comment for the network flannel's config names
# (cbr0; containernetworking/plugins pkg/utils FormatComment, `name: %q`,
# and portmap's `dnat name: "%s" id: "%s"`), as iptables-save prints it
# (a quote inside a quoted string escaped with a backslash).
def NHost.ipt_tag() -> String:
  "name: \\\"cbr0\\\""

def NHost.b32_chr(+c: U32) -> Bool:
  Bool.or(Bool.and(U32.is_ge(c, 65), U32.is_le(c, 90)), Bool.and(U32.is_ge(c, 50), U32.is_le(c, 55)))

def NHost.b32_all(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{Chr{+c}, t}:
      Bool.and(NHost.b32_chr(c), NHost.b32_all(t))

def NHost.hex_chr(+c: U32) -> Bool:
  Bool.or(Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57)), Bool.and(U32.is_ge(c, 97), U32.is_le(c, 102)))

def NHost.hex_all(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{Chr{+c}, t}:
      Bool.and(NHost.hex_chr(c), NHost.hex_all(t))

def NHost.hash_one(+p: String, +n: String) -> Bool:
  String.starts_with(n, p) && Nat.is_eq(String.length(n), Nat.add(String.length(p), 16n)) && NHost.b32_all(String.drop(n, String.length(p)))

# Whether n is one of the prefixes and 16 base32 characters.
def NHost.hashed_ok(ps: +List<String>, +n: String) -> Bool:
  match ps:
    case Nil{}:
      False{}
    case Con{p, t}:
      Bool.or(NHost.hash_one(p, n), NHost.hashed_ok(t, n))

# A CNI plugin's per-container chain (pkg/utils MustFormatHashWithPrefix:
# "CNI-", then "DN-" or "SN-" for portmap, then hex, 28 characters).
def NHost.cni_tail(+n: String) -> Bool:
  Bool.or(NHost.hex_all(String.drop(n, 4n)),
    Bool.and(Bool.or(String.starts_with(n, "CNI-DN-"), String.starts_with(n, "CNI-SN-")), NHost.hex_all(String.drop(n, 7n))))

def NHost.cni_chain(+n: String) -> Bool:
  Bool.and(Bool.and(Nat.is_eq(String.length(n), 28n), String.starts_with(n, "CNI-")), NHost.cni_tail(n))

def NHost.ipt_target.go(hit: Bool, +next: String, +rest: String) -> String:
  match hit:
    case True{}:
      NHost.last.go(String.is_empty(rest), next, rest)
    case False{}:
      rest

# A rule's target: the word after its last -j or -g ("" when none).
def NHost.ipt_target(ws: +List<String>) -> String:
  match ws:
    case Nil{}:
      ""
    case Con{+w, +t}:
      NHost.ipt_target.go(Bool.or(String.eq(w, "-j"), String.eq(w, "-g")), NHost.at(t, 0n), NHost.ipt_target(t))

def NHost.ipt_rule_target(+l: String) -> String:
  NHost.ipt_target(String.split(l, ' '))

# The chain of a rule ("-A <chain> ...").
def NHost.ipt_chain(+l: String) -> String:
  NHost.at(String.split(l, ' '), 1n)

# The name of a chain line (":<name> <policy> [p:b]").
def NHost.ipt_decl_name(+l: String) -> String:
  String.drop(NHost.at(String.split(l, ' '), 0n), 1n)

def NHost.ipt_claims(ls: +List<String>) -> +List<String>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{+l, t}:
      NHost.keep.go(String.starts_with(l, "-A ") && String.contains(l, NHost.ipt_tag()) && NHost.cni_chain(NHost.ipt_rule_target(l)),
        NHost.ipt_rule_target(l), NHost.ipt_claims(t))

# The CNI chains the tagged rules of a table jump to (none unless claim).
def NHost.ipt_claimed(claim: Bool, +g: +List<String>) -> +List<String>:
  match claim:
    case True{}:
      NHost.ipt_claims(g)
    case False{}:
      []

def NHost.ipt_name_ours(+names: +List<String>, +hashed: +List<String>, +claimed: +List<String>, +n: String) -> Bool:
  S.Sup.member(names, n) || NHost.hashed_ok(hashed, n) || S.Sup.member(claimed, n)

def NHost.ipt_decl_ours(+names: +List<String>, +hashed: +List<String>, +claimed: +List<String>, +l: String) -> Bool:
  Bool.and(Bool.and(String.starts_with(l, ":"), String.eq(NHost.at(String.split(l, ' '), 1n), "-")),
    NHost.ipt_name_ours(names, hashed, claimed, NHost.ipt_decl_name(l)))

# vk8s's user chains of a table, in the save's order.
def NHost.ipt_owned(+names: +List<String>, +hashed: +List<String>, +claimed: +List<String>, ls: +List<String>) -> +List<String>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{+l, t}:
      NHost.keep.go(NHost.ipt_decl_ours(names, hashed, claimed, l), NHost.ipt_decl_name(l), NHost.ipt_owned(names, hashed, claimed, t))

# A rule in a chain that is not vk8s's (a built-in one, or another
# tool's) that jumps to one of vk8s's.
def NHost.ipt_jump_ours(+owned: +List<String>, +l: String) -> Bool:
  String.starts_with(l, "-A ") && Bool.not(S.Sup.member(owned, NHost.ipt_chain(l))) && S.Sup.member(owned, NHost.ipt_rule_target(l))

def NHost.ipt_del.line(hit: Bool, +l: String) -> String:
  match hit:
    case True{}:
      "-D " ++ String.drop(l, 3n) ++ "\n"
    case False{}:
      ""

# Those rules, deleted by their exact text (iptables-save prints a rule
# as iptables -A takes it, so -D takes it back).
def NHost.ipt_dels(+owned: +List<String>, ls: +List<String>) -> String:
  match ls:
    case Nil{}:
      ""
    case Con{+l, t}:
      NHost.ipt_del.line(NHost.ipt_jump_ours(owned, l), l) ++ NHost.ipt_dels(owned, t)

def NHost.ipt_each(+op: String, xs: +List<String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, t}:
      op ++ x ++ "\n" ++ NHost.ipt_each(op, t)

def NHost.ipt_del.emit(none: Bool, +head: String, +owned: +List<String>, +g: +List<String>) -> String:
  match none:
    case True{}:
      ""
    case False{}:
      head ++ "\n" ++ NHost.ipt_dels(owned, g) ++ NHost.ipt_each("-F ", owned) ++ NHost.ipt_each("-X ", owned) ++ "COMMIT\n"

# One table of the save (its "*name" line first): the jumps into vk8s's
# chains deleted, then every one of them flushed (rules between them
# go), then deleted; "" when the table has none.
def NHost.ipt_del.table(+names: +List<String>, +hashed: +List<String>, claim: Bool, +g: +List<String>) -> String:
  +owned = NHost.ipt_owned(names, hashed, NHost.ipt_claimed(claim, g), g)
  NHost.ipt_del.emit(List.is_empty(&2, String, owned), NHost.at(g, 0n), owned, g)

def NHost.ipt_del.tables(+names: +List<String>, +hashed: +List<String>, +claim: Bool, gs: List<&2, List<&2, String>>) -> String:
  match gs:
    case Nil{}:
      ""
    case Con{+g, t}:
      NHost.ipt_del.table(names, hashed, claim, g) ++ NHost.ipt_del.tables(names, hashed, claim, t)

# The input for `<stem>-restore --noflush`, "" when nothing is vk8s's:
# names (exact), hashed (prefixes of 16 base32 characters), claim
# (whether the chains of the CNI rules tagged cbr0 are vk8s's).
def NHost.ipt_delete(+names: +List<String>, +hashed: +List<String>, claim: Bool, +text: String) -> String:
  NHost.ipt_del.tables(names, hashed, claim, NHost.ipt_tables(String.lines(text)))

# The restore that applies it: into the tables as they are.
def NHost.ipt_restore_cmd(+stem: String) -> +List<String>:
  ["sudo", stem ++ "-restore", "--noflush"]
