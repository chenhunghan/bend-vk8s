import Base
import ../lib/args.bend as A
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../translate/endpoint.bend as E
import ./coredns.bend as CD

# The control-plane VM's boot plan: everything vk8s does as PID 1, as data.
# host/init.bend runs it. The process flags follow vcluster pkg/k8s/k8s.go
# (standalone, private nodes, kine on SQLite); paths follow vcluster's
# standalone data dir (/var/lib/vcluster).

type Cfg is Data:
  Cfg{name: String, node_ip: String, service_cidr: String, pod_cidr: String, domain: String, port: U32, etcd: Bool}

type Step is Data:
  # mount -t fstype -o opts src dst (mkdir -p dst first)
  Mount{fstype: String, src: String, dst: String, opts: String}
  # write a file (parents created)
  Write{path: String, text: String}
  # run to completion; a non-zero exit stops the boot
  Run{prog: String, args: +List<String>}
  # start in the background, output appended to /var/log/<name>.log
  Daemon{name: String, prog: String, args: +List<String>}
  # start in the background once, not supervised (output to the log)
  Spawn{name: String, prog: String, args: +List<String>}
  # wait until a TCP port accepts connections, up to ms
  WaitTcp{host: String, port: U32, ms: U32}
  # stop these supervised daemons (SIGTERM); the supervisor restarts them
  Stop{names: +List<String>}
  # wait until a file exists, up to ms
  WaitFile{path: String, ms: U32}
  # insmod every module listed (one path per line) in this file
  Modules{path: String}
  Log{text: String}

def Plan.data() -> String:
  "/var/lib/vcluster"

def Plan.pki() -> String:
  "/var/lib/vcluster/pki"

def Plan.bin() -> String:
  "/var/lib/vcluster/bin"

def Plan.busybox() -> String:
  "/bin/busybox"

def Plan.bb(args: +List<String>) -> Step:
  Run{Plan.busybox(), args}

def Plan.p(+name: String) -> String:
  Plan.pki() ++ "/" ++ name

def Plan.flag(+k: String, +v: String) -> String:
  "--" ++ k ++ "=" ++ v

# kubelet's image garbage collection (KubeletConfiguration, every node):
# an image no container used for 1 h goes, whatever the disk use. kubelet's
# defaults remove images only above 85 % use of the image file system, and
# the 16 GiB sparse data disk seldom gets there, so pulled images kept host
# disk for ever. kubelet checks every 5 min; containerd's garbage collector
# then frees the content and snapshots, and Plan.fstrim gives the blocks
# back. The pause image is pinned and add-ons stay in use. A pod that
# needs a removed image pulls it again, from the image cache VM when it
# runs. (vk8s design: vcluster keeps kubelet's defaults.)
def Plan.image_gc() -> String:
  "imageMaximumGCAge: 1h\n"

# The base system: virtual filesystems, cgroup v2, sysctls for pod networking.
def Plan.system() -> +List<Step>:
  [ Plan.bb(["mkdir", "-p", "/sbin", "/usr/bin", "/usr/sbin"]),
    Plan.bb(["--install", "-s"]),
    Mount{"proc", "proc", "/proc", "nosuid,noexec,nodev"},
    Mount{"sysfs", "sys", "/sys", "nosuid,noexec,nodev"},
    Mount{"devtmpfs", "dev", "/dev", "mode=0755"},
    Mount{"devpts", "devpts", "/dev/pts", "mode=0620,ptmxmode=0666"},
    Mount{"tmpfs", "shm", "/dev/shm", "mode=1777,nosuid,nodev"},
    Mount{"mqueue", "mqueue", "/dev/mqueue", "nosuid,nodev,noexec"},
    Mount{"tmpfs", "tmpfs", "/run", "mode=0755"},
    Mount{"tmpfs", "tmpfs", "/tmp", "mode=1777"},
    Mount{"cgroup2", "cgroup2", "/sys/fs/cgroup", "nsdelegate"} ]

# Free page reporting at order 2 (16 KiB: the Mac's page size and, since
# bend-vmm 3aa445a, its release unit) instead of the default 9 (2 MiB):
# after a pod burst a worker's free memory held about 270 MB in blocks
# under 2 MiB that were never reported. Measured on the Mac
# (docs/ref/footprint-decisions.md M3): phys_footprint 1.1 GB at order 9,
# 778 MB at order 4 (64 KiB, bend-vmm's earlier release unit).
def Plan.page_reporting_order() -> String:
  "2"

def Plan.sysctls() -> +List<Step>:
  [ Write{"/proc/sys/net/ipv4/ip_forward", "1"},
    Write{"/proc/sys/net/bridge/bridge-nf-call-iptables", "1"},
    Write{"/proc/sys/net/bridge/bridge-nf-call-ip6tables", "1"},
    Write{"/proc/sys/fs/inotify/max_user_watches", "524288"},
    Write{"/sys/module/page_reporting/parameters/page_reporting_order", Plan.page_reporting_order()} ]

# bend-vmm's NICs: eth0 behind its user-mode NAT (10.0.2.15/24, the host
# 10.0.2.2, its resolver 10.0.2.3), the default route; eth1 on the
# cluster's LAN (bend-vmm --lan), the node's address.
def Plan.net(+name: String, +ip: String) -> +List<Step>:
  [ Plan.bb(["hostname", name]),
    Plan.bb(["ip", "link", "set", "lo", "up"]),
    Plan.bb(["ip", "link", "set", "eth0", "up"]),
    Plan.bb(["ip", "addr", "add", "10.0.2.15/24", "dev", "eth0"]),
    Plan.bb(["ip", "route", "add", "default", "via", "10.0.2.2"]),
    Plan.bb(["ip", "link", "set", "eth1", "up"]),
    Plan.bb(["ip", "addr", "add", ip ++ "/24", "dev", "eth1"]),
    Write{"/etc/resolv.conf", "nameserver 10.0.2.3\n"},
    Write{"/etc/hosts", "127.0.0.1 localhost\n" ++ ip ++ " " ++ name ++ "\n"} ]

# bend-vmm's user-mode NAT: the guest is 10.0.2.15/24, the host 10.0.2.2,
# its resolver 10.0.2.3.
def Plan.network(+c: Cfg) -> +List<Step>:
  match c:
    case Cfg{+name, +ip, +svc, +pod, +dom, +port, +etcd}:
      Plan.net(name, ip)

# /dev/vdb: this cluster's data disk (ext4, made by the host), at the data dir;
# /dev/vda: the read-only assets disk (Kubernetes binaries), at its bin/.
def Plan.disks() -> +List<Step>:
  [ Mount{"ext4", "/dev/vdb", Plan.data(), "rw"},
    Mount{"ext4", "/dev/vda", Plan.bin(), "ro"} ]

# The disks every boot plan mounts. The assets disk became squashfs (zstd)
# for docs/GOAL.md section 9 (docs/ref/footprint-decisions.md A1); stage 0
# mounts it at /assets first, and both read-only mounts share one
# superblock. Plan.disks above stays as its laws pin it (ext4).
def Plan.disks.v2() -> +List<Step>:
  [ Mount{"ext4", "/dev/vdb", Plan.data(), "rw"},
    Mount{"squashfs", "/dev/vda", Plan.bin(), "ro"} ]

# --- Per-role asset sets (docs/ref/footprint-decisions.md D1). /dev/vda
# is the base disk (stage 0's /assets), /dev/vdb the data disk, and
# /dev/vdc onward the role's sets in the order of VK8S_SETS, each mounted
# read-only at /sets/<set> (in stage 0's tmpfs root: /assets is read-only)
# and joined at bin/ by a read-only overlay of lower directories only.
def Plan.set_letters() -> +List<String>:
  ["c", "d", "e", "f", "g", "h", "i", "j"]

def Plan.set_dir(+s: String) -> String:
  "/sets/" ++ s

def Plan.set_mounts.go(sets: +List<String>, ls: +List<String>) -> +List<Step>:
  match sets:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      match ls:
        case Nil{}:
          Nil{}
        case Con{l, lt}:
          Con{Mount{"squashfs", "/dev/vd" ++ l, Plan.set_dir(s), "ro"}, Plan.set_mounts.go(t, lt)}

def Plan.lowerdir.rest(sets: +List<String>) -> String:
  match sets:
    case Nil{}:
      ""
    case Con{s, t}:
      ":" ++ Plan.set_dir(s) ++ Plan.lowerdir.rest(t)

# bin/: one set's disk mounted again (no overlay needs a single lower
# directory), or an overlay of every set's directory.
def Plan.bin_mount(sets: +List<String>) -> +List<Step>:
  match sets:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      match t:
        case Nil{}:
          [Mount{"squashfs", "/dev/vdc", Plan.bin(), "ro"}]
        case Con{s2, t2}:
          [Mount{"overlay", "overlay", Plan.bin(), "ro,lowerdir=" ++ Plan.set_dir(s) ++ ":" ++ Plan.set_dir(s2) ++ Plan.lowerdir.rest(t2)}]

def Plan.set_mounts(+sets: +List<String>) -> +List<Step>:
  List.append(&2, Step, Plan.set_mounts.go(sets, Plan.set_letters()), Plan.bin_mount(sets))

def Plan.disks.v3(+sets: +List<String>) -> +List<Step>:
  Con{Mount{"ext4", "/dev/vdb", Plan.data(), "rw"}, Plan.set_mounts(sets)}

# The assets disk's mount at bin/ (Plan.disks.v2).
def Plan.is_assets_mount(st: Step) -> Bool:
  match st:
    case Mount{fs, src, dst, opts}:
      String.eq(src, "/dev/vda") && String.eq(dst, Plan.bin())
    case _:
      False{}

def Plan.with_sets.swap(hit: Bool, +st: Step, +sets: +List<String>, +rest: +List<Step>) -> +List<Step>:
  match hit:
    case True{}:
      List.append(&2, Step, Plan.set_mounts(sets), rest)
    case False{}:
      Con{st, rest}

def Plan.with_sets.go(+sets: +List<String>, steps: +List<Step>) -> +List<Step>:
  match steps:
    case Nil{}:
      Nil{}
    case Con{+st, rest}:
      Plan.with_sets.swap(Plan.is_assets_mount(st), st, sets, Plan.with_sets.go(sets, rest))

# A boot plan with the host's sets (VK8S_SETS): the assets disk's bin/
# mount becomes the sets' mounts; with no sets (an older, single
# assets.img) the plan stays as it is.
def Plan.with_sets(sets: +List<String>, steps: +List<Step>) -> +List<Step>:
  match sets:
    case Nil{}:
      steps
    case Con{+s, +t}:
      Plan.with_sets.go(Con{s, t}, steps)

# kubeadm's view of the cluster, for its certs and kubeconfig phases
# (vcluster pkg/kubeadm/config.go).
def Plan.kubeadm_config(+c: Cfg) -> String:
  match c:
    case Cfg{+name, +ip, +svc, +pod, +dom, +port, +etcd}:
      "apiVersion: kubeadm.k8s.io/v1beta4\nkind: InitConfiguration\n"
      ++ "localAPIEndpoint:\n  advertiseAddress: " ++ ip ++ "\n  bindPort: 6443\n"
      ++ "nodeRegistration:\n  name: " ++ name ++ "\n"
      ++ "---\napiVersion: kubeadm.k8s.io/v1beta4\nkind: ClusterConfiguration\n"
      ++ "clusterName: " ++ name ++ "\n"
      ++ "kubernetesVersion: v1.36.6\n"
      ++ "controlPlaneEndpoint: " ++ ip ++ ":6443\n"
      ++ "certificatesDir: " ++ Plan.pki() ++ "\n"
      ++ "networking:\n  serviceSubnet: " ++ svc ++ "\n  podSubnet: " ++ pod ++ "\n  dnsDomain: " ++ dom ++ "\n"
      ++ "apiServer:\n  certSANs:\n  - 127.0.0.1\n  - localhost\n  - 10.0.2.15\n  - 10.0.2.2\n  - " ++ name ++ "\n"
      ++ "---\napiVersion: kubelet.config.k8s.io/v1beta1\nkind: KubeletConfiguration\n"
      ++ "cgroupDriver: cgroupfs\nfailSwapOn: false\nresolvConf: /etc/resolv.conf\n" ++ Plan.image_gc()

# The fake kubelet's serving certificate (host/kubelet_proxy.bend, on
# :10250): CN the node name, SANs the node name, the node IP, localhost
# and 127.0.0.1, signed by the cluster CA. kubeadm makes no kubelet
# serving certificate, but its etcd-server certificate has exactly this
# shape (CN nodeRegistration.name; SANs localhost, 127.0.0.1, ::1, the
# node name and the advertise address; server and client auth), so it
# is made in a scratch certificates dir whose etcd CA is the cluster CA,
# then moved to kubelet-serving.crt/.key. It is made anew at every boot.
def Plan.kubelet_serving_dir() -> String:
  Plan.pki() ++ "/kubelet-serving"

def Plan.kubelet_serving_config(+name: String, +ip: String) -> String:
  "apiVersion: kubeadm.k8s.io/v1beta4\nkind: InitConfiguration\n"
  ++ "localAPIEndpoint:\n  advertiseAddress: " ++ ip ++ "\n  bindPort: 6443\n"
  ++ "nodeRegistration:\n  name: " ++ name ++ "\n"
  ++ "---\napiVersion: kubeadm.k8s.io/v1beta4\nkind: ClusterConfiguration\n"
  ++ "kubernetesVersion: v1.36.6\n"
  ++ "certificatesDir: " ++ Plan.kubelet_serving_dir() ++ "\n"

def Plan.kubelet_serving(+c: Cfg) -> +List<Step>:
  match c:
    case Cfg{+name, +ip, +svc, +pod, +dom, +port, +etcd}:
      +dir = Plan.kubelet_serving_dir()
      +conf = Plan.data() ++ "/kubelet-serving.yaml"
      [ Plan.bb(["sh", "-c", "set -e; rm -rf " ++ dir ++ "; mkdir -p " ++ dir ++ "/etcd; cp " ++ Plan.p("ca.crt") ++ " " ++ dir ++ "/etcd/ca.crt; cp "
          ++ Plan.p("ca.key") ++ " " ++ dir ++ "/etcd/ca.key"]),
        Write{conf, Plan.kubelet_serving_config(name, ip)},
        Run{Plan.bin() ++ "/kubeadm", ["init", "phase", "certs", "etcd-server", "--config", conf]},
        Plan.bb(["sh", "-c", "set -e; mv " ++ dir ++ "/etcd/server.crt " ++ Plan.p("kubelet-serving.crt") ++ "; mv " ++ dir ++ "/etcd/server.key "
          ++ Plan.p("kubelet-serving.key") ++ "; rm -rf " ++ dir]) ]

def Plan.pki_steps(+c: Cfg) -> +List<Step>:
  +kubeadm = Plan.bin() ++ "/kubeadm"
  +conf = Plan.data() ++ "/kubeadm.yaml"
  List.append(&2, Step, [ Write{conf, Plan.kubeadm_config(c)},
    Run{kubeadm, ["init", "phase", "certs", "all", "--config", conf]},
    Run{kubeadm, ["init", "phase", "kubeconfig", "admin", "--config", conf, "--kubeconfig-dir", Plan.pki()]},
    Run{kubeadm, ["init", "phase", "kubeconfig", "super-admin", "--config", conf, "--kubeconfig-dir", Plan.pki()]},
    Run{kubeadm, ["init", "phase", "kubeconfig", "controller-manager", "--config", conf, "--kubeconfig-dir", Plan.pki()]},
    Run{kubeadm, ["init", "phase", "kubeconfig", "scheduler", "--config", conf, "--kubeconfig-dir", Plan.pki()]},
    Plan.bb(["cp", Plan.p("ca.crt"), Plan.p("client-ca.crt")]),
    Plan.bb(["cp", Plan.p("ca.crt"), Plan.p("server-ca.crt")]),
    Plan.bb(["cp", Plan.p("ca.key"), Plan.p("server-ca.key")]) ], Plan.kubelet_serving(c))

def Plan.kine_sock() -> String:
  "unix://" ++ Plan.data() ++ "/kine.sock"

def Plan.etcd_servers(etcd: Bool) -> String:
  match etcd:
    case True{}:
      "https://127.0.0.1:2379"
    case False{}:
      Plan.kine_sock()

# Embedded etcd, single member (vcluster's embedded etcd flags, with the
# peer on loopback: one control-plane VM).
def Plan.etcd_args(+name: String) -> +List<String>:
  [ Plan.flag("name", name),
    Plan.flag("data-dir", Plan.data() ++ "/etcd"),
    Plan.flag("listen-client-urls", "https://127.0.0.1:2379"),
    Plan.flag("advertise-client-urls", "https://127.0.0.1:2379"),
    Plan.flag("listen-peer-urls", "https://127.0.0.1:2380"),
    Plan.flag("initial-advertise-peer-urls", "https://127.0.0.1:2380"),
    Plan.flag("initial-cluster", name ++ "=https://127.0.0.1:2380"),
    Plan.flag("initial-cluster-token", "vcluster"),
    Plan.flag("initial-cluster-state", "new"),
    Plan.flag("listen-metrics-urls", "http://127.0.0.1:2381"),
    Plan.flag("heartbeat-interval", "500"),
    Plan.flag("election-timeout", "5000"),
    Plan.flag("snapshot-count", "10000"),
    Plan.flag("client-cert-auth", "true"),
    Plan.flag("cert-file", Plan.p("etcd/server.crt")),
    Plan.flag("key-file", Plan.p("etcd/server.key")),
    Plan.flag("trusted-ca-file", Plan.p("etcd/ca.crt")),
    Plan.flag("peer-client-cert-auth", "true"),
    Plan.flag("peer-cert-file", Plan.p("etcd/peer.crt")),
    Plan.flag("peer-key-file", Plan.p("etcd/peer.key")),
    Plan.flag("peer-trusted-ca-file", Plan.p("etcd/ca.crt")) ]

# vcluster pkg/k8s/k8s.go StartKineWithDone, as StartBackingStore calls it
# for the embedded database: SQLite (SQLiteParams), no TLS (the embedded
# CaFile, KeyFile and CertFile are empty), the metrics on 2381, the unix
# socket. vcluster merges backingStore.database.embedded.extraArgs over
# it; vk8s has none.
def Plan.kine_args.base() -> +List<String>:
  [ Plan.flag("endpoint", "sqlite://" ++ Plan.data() ++ "/state.db?_journal=WAL&cache=shared&_busy_timeout=30000&_txlock=immediate"),
    Plan.flag("metrics-bind-address", "127.0.0.1:2381"),
    Plan.flag("listen-address", Plan.kine_sock()) ]

def Plan.kine_args() -> +List<String>:
  A.Args.merge(Plan.kine_args.base(), [])

def Plan.store(etcd: Bool, +name: String) -> +List<Step>:
  match etcd:
    case True{}:
      [ Daemon{"etcd", Plan.bin() ++ "/etcd", Plan.etcd_args(name)},
        WaitTcp{"127.0.0.1", 2379, 60000} ]
    case False{}:
      [ Daemon{"kine", Plan.bin() ++ "/kine", Plan.kine_args()},
        WaitFile{Plan.data() ++ "/kine.sock", 30000} ]

# The etcd client certificates go only with etcd (kine listens on a unix
# socket without TLS), as vcluster's StartBackingStore hands them out:
# kubeadm's etcd CA and apiserver-etcd-client pair.
def Plan.etcd_client(etcd: Bool) -> +List<String>:
  match etcd:
    case True{}:
      [ Plan.flag("etcd-cafile", Plan.p("etcd/ca.crt")),
        Plan.flag("etcd-certfile", Plan.p("apiserver-etcd-client.crt")),
        Plan.flag("etcd-keyfile", Plan.p("apiserver-etcd-client.key")) ]
    case False{}:
      []

# vcluster pkg/k8s/k8s.go StartK8S, the apiserver's base flags with
# PrivateNodes.Enabled (and Konnectivity off), in vcluster's order and with
# vcluster's values; vk8s's paths. It passes --endpoint-reconciler-type=none
# twice, as vcluster does.
def Plan.apiserver_args.base(+c: Cfg) -> +List<String>:
  match c:
    case Cfg{+name, +ip, +svc, +pod, +dom, +port, +etcd}:
      List.append(&2, String,
        [ Plan.flag("service-cluster-ip-range", svc),
          Plan.flag("bind-address", "127.0.0.1"),
          Plan.flag("allow-privileged", "true"),
          Plan.flag("authorization-mode", "Node,RBAC"),
          Plan.flag("client-ca-file", Plan.p("client-ca.crt")),
          Plan.flag("enable-bootstrap-token-auth", "true"),
          Plan.flag("etcd-servers", Plan.etcd_servers(etcd)) ],
      List.append(&2, String, Plan.etcd_client(etcd),
        [ Plan.flag("proxy-client-cert-file", Plan.p("front-proxy-client.crt")),
          Plan.flag("proxy-client-key-file", Plan.p("front-proxy-client.key")),
          Plan.flag("requestheader-allowed-names", "front-proxy-client"),
          Plan.flag("requestheader-client-ca-file", Plan.p("front-proxy-ca.crt")),
          Plan.flag("requestheader-extra-headers-prefix", "X-Remote-Extra-"),
          Plan.flag("requestheader-group-headers", "X-Remote-Group"),
          Plan.flag("requestheader-username-headers", "X-Remote-User"),
          Plan.flag("secure-port", "6443"),
          Plan.flag("service-account-issuer", "https://kubernetes.default.svc." ++ dom),
          Plan.flag("service-account-key-file", Plan.p("sa.pub")),
          Plan.flag("service-account-signing-key-file", Plan.p("sa.key")),
          Plan.flag("tls-cert-file", Plan.p("apiserver.crt")),
          Plan.flag("tls-private-key-file", Plan.p("apiserver.key")),
          Plan.flag("profiling", "false"),
          Plan.flag("advertise-address", "127.0.0.1"),
          Plan.flag("endpoint-reconciler-type", "none"),
          Plan.flag("kubelet-client-certificate", Plan.p("apiserver-kubelet-client.crt")),
          Plan.flag("kubelet-client-key", Plan.p("apiserver-kubelet-client.key")),
          Plan.flag("enable-admission-plugins", "NodeRestriction"),
          Plan.flag("endpoint-reconciler-type", "none"),
          Plan.flag("kubelet-preferred-address-types", "InternalDNS,InternalIP,Hostname,ExternalDNS,ExternalIP") ]))

# vk8s's apiServer.extraArgs: merged over the base list as vcluster merges
# them (command.MergeArgs), so each replaces vcluster's flag of that name.
# - --bind-address=0.0.0.0: vcluster binds 127.0.0.1 and serves the API
#   through its own proxy; vk8s's API is reached through bend-vmm's port
#   forward to the guest's 6443 and, from worker VMs, over the VM LAN, so
#   it binds every address.
# - --advertise-address=<node ip>: for the same reason it advertises the
#   node's address on the VM LAN, which workers reach, not 127.0.0.1.
# - --endpoint-reconciler-type=lease: vcluster passes none and its
#   k8sdefaultendpoint controller keeps default/kubernetes; until that
#   controller is ported, the apiserver's lease reconciler keeps it.
def Plan.apiserver_overrides(+ip: String) -> +List<String>:
  [ Plan.flag("bind-address", "0.0.0.0"),
    Plan.flag("advertise-address", ip),
    Plan.flag("endpoint-reconciler-type", "lease") ]

# Since the k8sdefaultendpoint port (src/translate/endpoint.bend): vcluster's
# --endpoint-reconciler-type=none stays, and PID 1 writes default/kubernetes
# (Plan.default_endpoints). The plan uses these; apiserver_overrides and
# apiserver_args above keep the lease reconciler, as their laws state.
def Plan.apiserver_overrides_ep(+ip: String) -> +List<String>:
  [ Plan.flag("bind-address", "0.0.0.0"),
    Plan.flag("advertise-address", ip) ]

def Plan.apiserver_args_ep(+c: Cfg) -> +List<String>:
  match c:
    case Cfg{+name, +ip, +svc, +pod, +dom, +port, +etcd}:
      A.Args.merge(Plan.apiserver_args.base(Cfg{name, ip, svc, pod, dom, port, etcd}), Plan.apiserver_overrides_ep(ip))

def Plan.apiserver_args(+c: Cfg) -> +List<String>:
  match c:
    case Cfg{+name, +ip, +svc, +pod, +dom, +port, +etcd}:
      A.Args.merge(Plan.apiserver_args.base(Cfg{name, ip, svc, pod, dom, port, etcd}), Plan.apiserver_overrides(ip))

# vcluster pkg/k8s/k8s.go StartK8S, the controller manager's base flags with
# PrivateNodes.Enabled. The cluster signing pair is the server CA's
# (appendClusterSigningArgs without a split CA: vk8s copies kubeadm's ca.crt
# to both client-ca.crt and server-ca.crt). Sync.ToHost.
# ResourceClaimTemplates is off, so the controllers list has no suffix.
def Plan.controller_manager_args.base(+c: Cfg) -> +List<String>:
  match c:
    case Cfg{+name, +ip, +svc, +pod, +dom, +port, +etcd}:
      +kc = Plan.p("controller-manager.conf")
      [ Plan.flag("service-cluster-ip-range", svc),
        Plan.flag("authentication-kubeconfig", kc),
        Plan.flag("authorization-kubeconfig", kc),
        Plan.flag("bind-address", "127.0.0.1"),
        Plan.flag("client-ca-file", Plan.p("client-ca.crt")),
        Plan.flag("cluster-name", "kubernetes"),
        Plan.flag("kubeconfig", kc),
        Plan.flag("requestheader-client-ca-file", Plan.p("front-proxy-ca.crt")),
        Plan.flag("root-ca-file", Plan.p("server-ca.crt")),
        Plan.flag("service-account-private-key-file", Plan.p("sa.key")),
        Plan.flag("use-service-account-credentials", "true"),
        Plan.flag("leader-elect", "true"),
        Plan.flag("cluster-signing-cert-file", Plan.p("server-ca.crt")),
        Plan.flag("cluster-signing-key-file", Plan.p("server-ca.key")),
        Plan.flag("controllers", "*,bootstrapsigner,tokencleaner"),
        Plan.flag("allocate-node-cidrs", "true"),
        Plan.flag("cluster-cidr", pod),
        Plan.flag("cloud-provider", "external") ]

# vcluster pkg/k8s/k8s.go, classic mode without the virtual scheduler
# (the default): the shared flags, then its controller set and periods
# instead of the private-nodes ones (no node lifecycle: the syncer keeps
# the fake nodes' status).
def Plan.controller_manager_classic_flags() -> +List<String>:
  [ Plan.flag("controllers", "*,-nodeipam,-nodelifecycle,-persistentvolume-binder,-attachdetach,-persistentvolume-expander,-cloud-node-lifecycle,-ttl"),
    Plan.flag("node-monitor-grace-period", "180s"),
    Plan.flag("node-monitor-period", "30s"),
    Plan.flag("pvclaimbinder-sync-period", "60s"),
    Plan.flag("horizontal-pod-autoscaler-sync-period", "60s") ]

def Plan.controller_manager_args_classic(+c: Cfg) -> +List<String>:
  List.append(&2, String, List.take(&2, String, Plan.controller_manager_args.base(c), 14n), Plan.controller_manager_classic_flags())

# vk8s has no controllerManager.extraArgs.
def Plan.controller_manager_args(+c: Cfg) -> +List<String>:
  A.Args.merge(Plan.controller_manager_args.base(c), [])

# vcluster pkg/k8s/k8s.go StartK8S, the scheduler's base flags (it runs
# with PrivateNodes.Enabled).
def Plan.scheduler_args.base() -> +List<String>:
  +kc = Plan.p("scheduler.conf")
  [ Plan.flag("authentication-kubeconfig", kc),
    Plan.flag("authorization-kubeconfig", kc),
    Plan.flag("bind-address", "127.0.0.1"),
    Plan.flag("kubeconfig", kc),
    Plan.flag("leader-elect", "true") ]

# vk8s has no scheduler.extraArgs.
def Plan.scheduler_args() -> +List<String>:
  A.Args.merge(Plan.scheduler_args.base(), [])

# --- Idle tuning of the standalone control plane (vk8s design, docs/GOAL.md
# section 10). Laid over vcluster's base lists as vcluster lays extraArgs
# (command.MergeArgs), so the base lists and their laws stay vcluster's.
#
# - --leader-elect=false: a vk8s cluster has one control plane (no
#   control-plane join). Upstream defaults to true with a 15 s lease, a
#   10 s renew deadline and a 2 s retry period (component-base
#   config/v1alpha1 RecommendedDefaultLeaderElectionConfiguration), so each
#   component writes its Lease every 2 s, and the API server and the store
#   serve each write, for ever. No conformance test reads those Leases.
# - -ttl: the TTL controller annotates nodes with
#   node.alpha.kubernetes.io/ttl for the kubelet's TTL-based Secret and
#   ConfigMap cache; the kubelet's default change detection is Watch, which
#   ignores it. No test of the conformance list (test/conformance/testdata/
#   conformance.yaml, v1.36.0) names TTL, the e2e framework reads a missing
#   annotation as 0 (GetPodSecretUpdateTimeout), and vcluster turns it off
#   in both its classic controller sets. Every other default controller
#   stays: conformance exercises it (persistentvolume-binder, the PV and
#   PVC lifecycle), the cluster needs it (nodeipam for flannel,
#   bootstrapsigner for token joins), or it has no idle work to save.
def Plan.controller_manager_idle() -> +List<String>:
  [ Plan.flag("leader-elect", "false"),
    Plan.flag("controllers", "*,bootstrapsigner,tokencleaner,-ttl") ]

def Plan.controller_manager_args.v2(+c: Cfg) -> +List<String>:
  A.Args.merge(Plan.controller_manager_args.base(c), Plan.controller_manager_idle())

def Plan.scheduler_idle() -> +List<String>:
  [ Plan.flag("leader-elect", "false") ]

def Plan.scheduler_args.v2() -> +List<String>:
  A.Args.merge(Plan.scheduler_args.base(), Plan.scheduler_idle())

# vcluster pkg/k8s/k8s.go, classic mode with the virtual scheduler
# (IsVirtualSchedulerEnabled): the node lifecycle controller runs, with
# hour-long node monitor periods (the syncer keeps the real nodes' status).
def Plan.controller_manager_vsched_flags() -> +List<String>:
  [ Plan.flag("controllers", "*,-nodeipam,-persistentvolume-binder,-attachdetach,-persistentvolume-expander,-cloud-node-lifecycle,-ttl"),
    Plan.flag("node-monitor-grace-period", "1h"),
    Plan.flag("node-monitor-period", "1h"),
    Plan.flag("pvclaimbinder-sync-period", "60s"),
    Plan.flag("horizontal-pod-autoscaler-sync-period", "60s") ]

def Plan.controller_manager_args_vsched(+c: Cfg) -> +List<String>:
  List.append(&2, String, List.take(&2, String, Plan.controller_manager_args.base(c), 14n), Plan.controller_manager_vsched_flags())

def Plan.vsched.daemon(cm: Bool, +c: Cfg, +name: String, +prog: String, +args: +List<String>) -> +List<Step>:
  match cm:
    case True{}:
      [Daemon{name, prog, Plan.controller_manager_args_vsched(c)},
       Daemon{"kube-scheduler", Plan.bin() ++ "/kube-scheduler", Plan.scheduler_args()}]
    case False{}:
      [Daemon{name, prog, args}]

def Plan.vsched.step(+c: Cfg, s: Step) -> +List<Step>:
  match s:
    case Daemon{+name, +prog, +args}:
      Plan.vsched.daemon(String.eq(name, "kube-controller-manager"), c, name, prog, args)
    case other:
      [other]

# A classic plan with vcluster's virtual scheduler: the controller manager
# takes the virtual-scheduler flags and kube-scheduler starts after it
# (k8s.go StartK8S runs the scheduler when IsVirtualSchedulerEnabled).
def Plan.virtual_scheduler(+c: Cfg, ss: +List<Step>) -> +List<Step>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      List.append(&2, Step, Plan.vsched.step(c, s), Plan.virtual_scheduler(c, t))

def Plan.syncer_config.daemon(hit: Bool, +path: String, +name: String, +prog: String, +args: +List<String>) -> Step:
  match hit:
    case True{}:
      Daemon{name, prog, List.append(&2, String, args, ["--config", path])}
    case False{}:
      Daemon{name, prog, args}

def Plan.syncer_config.step(+path: String, s: Step) -> Step:
  match s:
    case Daemon{+name, +prog, +args}:
      Plan.syncer_config.daemon(String.eq(name, "syncer"), path, name, prog, args)
    case other:
      other

# The syncer reads the vcluster.yaml at path (vk8s create -f puts it on
# the share).
def Plan.syncer_config(+path: String, ss: +List<Step>) -> +List<Step>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      Con{Plan.syncer_config.step(path, s), Plan.syncer_config(path, t)}

# A POSIX shell single-quoted word: ' becomes '\''.
def Plan.sh_quote.char(q: Bool, c: U32, rest: String) -> String:
  match q:
    case True{}:
      "'\\''" ++ rest
    case False{}:
      SCon{Chr{c}, rest}

def Plan.sh_quote.go(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{Chr{+c}, t}:
      Plan.sh_quote.char(U32.is_eq(c, 39), c, Plan.sh_quote.go(t))

def Plan.sh_quote(s: String) -> String:
  "'" ++ Plan.sh_quote.go(s) ++ "'"

# vcluster's k8sdefaultendpoint for vk8s (src/translate/endpoint.bend,
# standalone): default/kubernetes Endpoints and EndpointSlice at the node's
# address and 6443, applied once the API server answers (its address never
# changes, and with the reconciler off the API server leaves them alone).
# It waits up to 10 s for the default namespace, times VK8S_WAIT_SCALE
# (PID 1's environment, from the kernel command line).
def Plan.default_endpoints(+c: Cfg) -> Step:
  match c:
    case Cfg{name, +ip, svc, pod, dom, port, etcd}:
      +ep = "{\"apiVersion\":\"v1\",\"kind\":\"Endpoints\"," ++ String.drop(J.Json.show(E.Ep.standalone_endpoints(ip, 6443)), 1n)
      +sl = "{\"apiVersion\":\"discovery.k8s.io/v1\",\"kind\":\"EndpointSlice\"," ++ String.drop(J.Json.show(E.Ep.standalone_slice(ip, 6443)), 1n)
      Plan.bb(["sh", "-c", "set -e; k=" ++ Plan.sh_quote(Plan.bin() ++ "/kubectl") ++ "; a=" ++ Plan.sh_quote(Plan.p("super-admin.conf"))
        ++ "; w=${VK8S_WAIT_SCALE:-1}; case $w in *[!0-9]*) w=1;; esac; n=$((10 * w)); i=0; while [ $i -lt $n ]; do"
        ++ " $k --kubeconfig $a get ns default >/dev/null 2>&1 && break; sleep 1; i=$((i + 1)); done; printf %s "
        ++ Plan.sh_quote(ep) ++ " | $k --kubeconfig $a apply -f - && printf %s " ++ Plan.sh_quote(sl) ++ " | $k --kubeconfig $a apply -f -"])

# The guest image installs host/init.bend twice: /sbin/vk8s-init (PID 1,
# static musl) and /usr/bin/vk8s-guest (dynamic glibc, with libssl.so.3
# and libcrypto.so.3 for bend-kube-runtime's dlopen'd TLS client). The
# programs that need TLS (the syncer, the join server) run the second one.
def Plan.guest_bin() -> String:
  "/usr/bin/vk8s-guest"

# The standalone /node/join server (host/join_server.bend; vk8s design,
# docs/ref/standalone-decisions.md J1: vcluster's handler is closed
# source). It listens on 8443 with the API server's serving certificate,
# and reads token Secrets from the API server as Plan.join_server_user().
def Plan.join_server() -> Step:
  Daemon{"join-server", Plan.guest_bin(), ["join-server"]}

# The join server's user at the API server: the front-proxy client
# certificate with this X-Remote-User and no groups (not system:masters).
def Plan.join_server_user() -> String:
  "vk8s:join-server"

def Plan.control_plane.k8s(+c: Cfg) -> +List<Step>:
  [ Daemon{"kube-apiserver", Plan.bin() ++ "/kube-apiserver", Plan.apiserver_args_ep(c)},
    WaitTcp{"127.0.0.1", 6443, 120000},
    Plan.default_endpoints(c),
    Daemon{"kube-controller-manager", Plan.bin() ++ "/kube-controller-manager", Plan.controller_manager_args.v2(c)},
    Daemon{"kube-scheduler", Plan.bin() ++ "/kube-scheduler", Plan.scheduler_args.v2()},
    Plan.join_server(),
    Log{"vk8s: control plane up"} ]

def Plan.control_plane(+c: Cfg) -> +List<Step>:
  match c:
    case Cfg{+name, +ip, +svc, +pod, +dom, +port, +etcd}:
      List.append(&2, Step, Plan.store(etcd, name), Plan.control_plane.k8s(Cfg{name, ip, svc, pod, dom, port, etcd}))

# The host's state dir for this cluster, shared over virtio-9p (bend-vmm --share).
def Plan.host_dir() -> String:
  "/var/lib/vk8s-host"

# The admin kubeconfig as the host reaches the API: through bend-vmm's
# forward of 127.0.0.1:<port> to the guest's 6443, with the context named
# vk8s_<name> (vcluster's docker driver names it vcluster-docker_<name>).
def Plan.publish(+c: Cfg) -> +List<Step>:
  match c:
    case Cfg{+name, +ip, +svc, +pod, +dom, +port, +etcd}:
      +ctx = "vk8s_" ++ name
      [ Plan.bb(["sh", "-c",
          "sed -e 's#https://" ++ ip ++ ":6443#https://127.0.0.1:" ++ U32.show(port) ++ "#'"
          ++ " -e 's#kubernetes-super-admin@" ++ name ++ "#" ++ ctx ++ "#g'"
          ++ " " ++ Plan.p("super-admin.conf") ++ " > " ++ Plan.host_dir() ++ "/kubeconfig.yaml.tmp"
          ++ " && mv " ++ Plan.host_dir() ++ "/kubeconfig.yaml.tmp " ++ Plan.host_dir() ++ "/kubeconfig.yaml"]),
        Log{"vk8s: kubeconfig published"} ]

# --- The control-plane VM as a node (vcluster joinNode.enabled, the
# default): containerd, kubelet and kube-proxy run beside the control plane.

def Plan.containerd_config() -> String:
  "version = 3\nroot = \"/var/lib/vcluster/containerd\"\nstate = \"/run/containerd\"\n"
  ++ "[grpc]\n  address = \"/run/containerd/containerd.sock\"\n"
  ++ "[plugins.'io.containerd.cri.v1.images']\n  snapshotter = \"overlayfs\"\n"
  ++ "  [plugins.'io.containerd.cri.v1.images'.pinned_images]\n    sandbox = \"registry.k8s.io/pause:3.10.2\"\n"
  ++ "  [plugins.'io.containerd.cri.v1.images'.registry]\n    config_path = \"/etc/containerd/certs.d\"\n"
  ++ "[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc]\n  runtime_type = \"io.containerd.runc.v2\"\n"
  ++ "  [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]\n    SystemdCgroup = false\n    BinaryName = \"/var/lib/vcluster/bin/runc\"\n"
  ++ "[plugins.'io.containerd.cri.v1.runtime'.cni]\n  bin_dirs = [\"/opt/cni/bin\"]\n  conf_dir = \"/etc/cni/net.d\"\n"

# gVisor (docs/GOAL.md section 8): an opt-in runtime for pods that name
# the RuntimeClass gvisor. containerd 2.x config v3 keys (containerd
# docs/cri/config.md, "Runtime classes"); runtime_path is the shim on the
# node set, so no PATH lookup; the generic runtimeoptions/v1 options hand
# the shim its own file (gVisor g3doc/user_guide/containerd/
# configuration.md). No default_runtime_name: runc stays the default.
def Plan.containerd_runsc() -> String:
  "[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runsc]\n"
  ++ "  runtime_type = \"io.containerd.runsc.v1\"\n"
  ++ "  runtime_path = \"" ++ Plan.bin() ++ "/containerd-shim-runsc-v1\"\n"
  ++ "  [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runsc.options]\n"
  ++ "    TypeUrl = \"io.containerd.runsc.v1.options\"\n"
  ++ "    ConfigPath = \"/etc/containerd/runsc.toml\"\n"

# The shim's options (gVisor pkg/shim/v1/runsc/options.go): runsc from the
# node set (it finds its gvisor-bin/ beside itself), and the systrap
# platform (seccomp traps, no nested virtualization; runsc's default,
# named so a later default does not change it).
def Plan.runsc_toml() -> String:
  "binary_name = \"" ++ Plan.bin() ++ "/runsc\"\n[runsc_config]\n  platform = \"systrap\"\n"

def Plan.containerd_config.v2() -> String:
  Plan.containerd_config() ++ Plan.containerd_runsc()

# The RuntimeClass (gVisor g3doc/user_guide/containerd/quick_start.md).
def Plan.runtimeclass_gvisor() -> String:
  "apiVersion: node.k8s.io/v1\nkind: RuntimeClass\nmetadata:\n  name: gvisor\nhandler: runsc\n"

def Plan.runtimeclass_path() -> String:
  "/etc/vk8s/runtimeclass-gvisor.yaml"

# One node: a bridge with this node's /24 of the pod CIDR (the first /24
# is what kube-controller-manager allocates to the first node).
def Plan.cni_config() -> String:
  "{\"cniVersion\":\"1.0.0\",\"name\":\"vk8s\",\"plugins\":["
  ++ "{\"type\":\"bridge\",\"bridge\":\"cni0\",\"isGateway\":true,\"ipMasq\":true,\"hairpinMode\":true,"
  ++ "\"ipam\":{\"type\":\"host-local\",\"ranges\":[[{\"subnet\":\"10.244.0.0/24\"}]],\"routes\":[{\"dst\":\"0.0.0.0/0\"}]}},"
  ++ "{\"type\":\"portmap\",\"capabilities\":{\"portMappings\":true}}]}\n"

def Plan.kubelet_config(+dom: String) -> String:
  "apiVersion: kubelet.config.k8s.io/v1beta1\nkind: KubeletConfiguration\n"
  ++ "authentication:\n  anonymous:\n    enabled: false\n  webhook:\n    enabled: true\n  x509:\n    clientCAFile: " ++ Plan.p("ca.crt") ++ "\n"
  ++ "authorization:\n  mode: Webhook\n"
  ++ "cgroupDriver: cgroupfs\n"
  ++ "clusterDNS:\n- 10.96.0.10\nclusterDomain: " ++ dom ++ "\n"
  ++ "containerRuntimeEndpoint: unix:///run/containerd/containerd.sock\n"
  ++ "failSwapOn: false\nresolvConf: /etc/resolv.conf\nstaticPodPath: /etc/kubernetes/manifests\n" ++ Plan.image_gc()

def Plan.kubelet_args(+c: Cfg) -> +List<String>:
  match c:
    case Cfg{+name, +ip, +svc, +pod, +dom, +port, +etcd}:
      [ Plan.flag("config", Plan.data() ++ "/kubelet-config.yaml"),
        Plan.flag("kubeconfig", Plan.p("kubelet.conf")),
        Plan.flag("root-dir", Plan.data() ++ "/kubelet"),
        Plan.flag("hostname-override", name),
        Plan.flag("node-ip", ip) ]

# The kubelet's idle tuning on every node (vk8s design, docs/GOAL.md
# section 10):
# - --housekeeping-interval=30s: cAdvisor's per-container stats period.
#   The kubelet's default is 10 s, and dynamic housekeeping backs an
#   unchanged container off to at most 15 s (pkg/kubelet/cadvisor/
#   cadvisor_linux.go, v1.36.0: defaultHousekeepingInterval,
#   maxHousekeepingInterval); a base at or above that maximum stays the
#   period (cadvisor v0.56.2 manager/container.go
#   nextHousekeepingInterval). The eviction manager asks for fresh root
#   stats on demand (MaxAge 0), so it does not wait for this period.
# Kept at upstream defaults, on purpose:
# - syncFrequency (1m, pkg/kubelet/apis/config/v1beta1/defaults.go): it
#   bounds how late a ConfigMap or Secret update reaches a volume, and the
#   conformance tests wait 240 s for that, "based on default Kubelet sync
#   period (1 minute)" (test/e2e/framework/pod/resource.go
#   GetPodSecretUpdateTimeout); the per-pod resync jitters up to 1.5 times.
# - The image and container GC periods are constants (pkg/kubelet/
#   kubelet.go: ImageGCPeriod 5 min, ContainerGCPeriod 1 min), not
#   settings; Plan.image_gc already sets the image age.
# - nodeStatusUpdateFrequency, nodeStatusReportFrequency and the node
#   lease: node health, which docs/GOAL.md section 10 keeps.
def Plan.kubelet_idle() -> +List<String>:
  [ Plan.flag("housekeeping-interval", "30s") ]

def Plan.kubelet_args.v2(+c: Cfg) -> +List<String>:
  List.append(&2, String, Plan.kubelet_args(c), Plan.kubelet_idle())

# --- Go runtime settings per daemon (vk8s design, docs/GOAL.md section 10).
# Upstream runs every component with Go's defaults: GOGC=100 (the heap
# grows to twice the live heap before a collection) and no GOMEMLIMIT.
# GOGC=50 lets each heap grow to 1.5 times its live data, so an idle
# component holds about a quarter less heap, at the price of collecting
# twice as often under load. GOMEMLIMIT is a soft limit near which the
# runtime collects and returns memory sooner; it never kills a process.
# Each limit sits well above what the component holds in a busy
# single-node cluster (conformance), so it bounds spikes without making
# the collector run all the time. PID 1 starts a daemon that has
# settings under `busybox env` (Plan.env_prog, Plan.env_args); the boot
# plans and their laws keep the daemons' own programs.
type GoEnv is Data:
  GoEnv{name: String, gogc: String, limit: String}

def Plan.go_envs() -> +List<GoEnv>:
  [ GoEnv{"kube-apiserver", "50", "640MiB"},
    GoEnv{"kube-controller-manager", "50", "256MiB"},
    GoEnv{"kube-scheduler", "50", "128MiB"},
    GoEnv{"kubelet", "50", "192MiB"},
    GoEnv{"containerd", "50", "128MiB"},
    GoEnv{"kine", "50", "128MiB"},
    GoEnv{"etcd", "50", "256MiB"} ]

def Plan.go_env.name(e: GoEnv) -> String:
  match e:
    case GoEnv{n, g, l}:
      n

def Plan.go_env.words(e: GoEnv) -> +List<String>:
  match e:
    case GoEnv{n, +g, +l}:
      ["GOGC=" ++ g, "GOMEMLIMIT=" ++ l]

def Plan.go_env.pick(hit: Bool, +e: GoEnv, later: +List<String>) -> +List<String>:
  match hit:
    case True{}:
      Plan.go_env.words(e)
    case False{}:
      later

def Plan.go_env.find(es: +List<GoEnv>, +name: String) -> +List<String>:
  match es:
    case Nil{}:
      []
    case Con{+e, t}:
      Plan.go_env.pick(String.eq(name, Plan.go_env.name(e)), e, Plan.go_env.find(t, name))

# The environment words of a daemon, by its name; none for the others.
def Plan.go_env(+name: String) -> +List<String>:
  Plan.go_env.find(Plan.go_envs(), name)

# What PID 1 starts for a daemon with environment words env: the program
# itself when there are none, else busybox (bb) running
# `env WORD... PROG ARGS...`.
def Plan.env_prog(env: +List<String>, +bb: String, +prog: String) -> String:
  match env:
    case Nil{}:
      prog
    case Con{e, t}:
      bb

def Plan.env_args(env: +List<String>, +prog: String, +args: +List<String>) -> +List<String>:
  match env:
    case Nil{}:
      args
    case Con{+e, +t}:
      Con{"env", Con{e, List.append(&2, String, t, Con{prog, args})}}

def Plan.kube_proxy_args(+c: Cfg) -> +List<String>:
  match c:
    case Cfg{+name, +ip, +svc, +pod, +dom, +port, +etcd}:
      [ Plan.flag("kubeconfig", Plan.p("kube-proxy.conf")),
        Plan.flag("cluster-cidr", pod),
        Plan.flag("hostname-override", name),
        Plan.flag("proxy-mode", "iptables") ]

# containerd and the CNI plugins (copied to /opt/cni/bin, where flannel
# adds its own), the same on every node.
# vk8s's image cache: a pull-through registry per upstream, in the cache VM
# (Plan.cache), reached from every cluster at the host (10.0.2.2) on these
# ports. (vind's analogue is experimental.docker.registryProxy, which reads
# the host Docker's image store.)
type Mirror is Data:
  Mirror{registry: String, upstream: String, port: U32}

def Plan.mirrors() -> +List<Mirror>:
  [ Mirror{"docker.io", "https://registry-1.docker.io", 15001},
    Mirror{"registry.k8s.io", "https://registry.k8s.io", 15002},
    Mirror{"ghcr.io", "https://ghcr.io", 15003},
    Mirror{"quay.io", "https://quay.io", 15004} ]

# containerd's hosts.toml for one registry: the cache first; containerd
# falls back to the upstream server when the cache does not answer.
def Plan.hosts_toml(m: Mirror) -> String:
  match m:
    case Mirror{r, +up, +port}:
      "server = \"" ++ up ++ "\"\n\n[host.\"http://10.0.2.2:" ++ U32.show(port) ++ "\"]\n  capabilities = [\"pull\", \"resolve\"]\n"

def Plan.mirror_name(m: Mirror) -> String:
  match m:
    case Mirror{r, up, port}:
      r

# The cache with `pull` only (security review F5): containerd resolves a
# tag to a digest at the upstream and fetches content by digest from the
# cache, so a cache never chooses what a tag means (containerd docs/hosts.md:
# resolving "must be considered a trusted operation").
def Plan.hosts_toml_pull(m: Mirror) -> String:
  match m:
    case Mirror{r, +up, +port}:
      "server = \"" ++ up ++ "\"\n\n[host.\"http://10.0.2.2:" ++ U32.show(port) ++ "\"]\n  capabilities = [\"pull\"]\n"

def Plan.mirror_steps(ms: +List<Mirror>) -> +List<Step>:
  match ms:
    case Nil{}:
      Nil{}
    case Con{+m, rest}:
      Con{Write{"/etc/containerd/certs.d/" ++ Plan.mirror_name(m) ++ "/hosts.toml", Plan.hosts_toml_pull(m)}, Plan.mirror_steps(rest)}

# The cache VM's registry config for one upstream (distribution v3).
def Plan.registry_config(m: Mirror) -> String:
  match m:
    case Mirror{+r, +up, +port}:
      "version: 0.1\nlog:\n  level: warn\nstorage:\n  filesystem:\n    rootdirectory: " ++ Plan.data() ++ "/cache/" ++ r
        ++ "\n  delete:\n    enabled: true\nhttp:\n  addr: :" ++ U32.show(port) ++ "\nproxy:\n  remoteurl: " ++ up ++ "\n  ttl: 168h\n"

def Plan.registry_steps(ms: +List<Mirror>) -> +List<Step>:
  match ms:
    case Nil{}:
      Nil{}
    case Con{+m, rest}:
      +cfg = "/etc/registry/" ++ Plan.mirror_name(m) ++ ".yml"
      Con{Write{cfg, Plan.registry_config(m)},
        Con{Daemon{"registry-" ++ Plan.mirror_name(m), "/bin/sh", ["-c", "OTEL_TRACES_EXPORTER=none exec " ++ Plan.sh_quote(Plan.bin() ++ "/registry")
          ++ " serve " ++ Plan.sh_quote(cfg)]}, Plan.registry_steps(rest)}}

# The cache VM: NAT only, its data disk holds the cached blobs.
def Plan.cache() -> +List<Step>:
  List.append(&2, Step, Plan.system(),
  List.append(&2, Step, [Modules{"/etc/vk8s/modules"}],
  List.append(&2, Step, [ Plan.bb(["hostname", "vk8s-cache"]),
      Plan.bb(["ip", "link", "set", "lo", "up"]),
      Plan.bb(["ip", "link", "set", "eth0", "up"]),
      Plan.bb(["ip", "addr", "add", "10.0.2.15/24", "dev", "eth0"]),
      Plan.bb(["ip", "route", "add", "default", "via", "10.0.2.2"]),
      Write{"/etc/resolv.conf", "nameserver 10.0.2.3\n"},
      Write{"/etc/hosts", "127.0.0.1 localhost vk8s-cache\n"} ],
  List.append(&2, Step, Plan.disks.v2(),
  List.append(&2, Step, [Mount{"9p", "share", Plan.host_dir(), "trans=virtio,version=9p2000.L"}],
  List.append(&2, Step, Plan.registry_steps(Plan.mirrors()),
    [ WaitTcp{"127.0.0.1", 15004, 30000},
      Plan.bb(["sh", "-c", "echo ok > " ++ Plan.host_dir() ++ "/ready"]),
      Log{"vk8s: image cache ready"} ]))))))

def Plan.runtime() -> +List<Step>:
  List.append(&2, Step, Plan.mirror_steps(Plan.mirrors()),
  [ Write{"/etc/containerd/config.toml", Plan.containerd_config.v2()},
    Write{"/etc/containerd/runsc.toml", Plan.runsc_toml()},
    Plan.bb(["sh", "-c", "mkdir -p /opt/cni/bin /etc/cni/net.d /var/lib/cni /etc/kubernetes/manifests && cp /var/lib/vcluster/bin/cni/bin/* /opt/cni/bin/"]),
    Daemon{"containerd", Plan.bin() ++ "/containerd", ["--config", "/etc/containerd/config.toml"]},
    WaitFile{"/run/containerd/containerd.sock", 30000},
    Run{Plan.bin() ++ "/ctr", ["--address", "/run/containerd/containerd.sock", "-n", "k8s.io", "images", "import", Plan.bin() ++ "/pause-image.tar"]},
    # images preloaded on the assets disk (scripts/guest/images.sh): the
    # cluster's own add-ons start without a pull
    Plan.bb(["sh", "-c", "for f in " ++ Plan.bin() ++ "/images/*.tar; do [ -f \"$f\" ] || continue; " ++ Plan.bin()
      ++ "/ctr --address /run/containerd/containerd.sock -n k8s.io images import --platform linux/arm64 \"$f\" >/dev/null || exit 1; done"]) ])

# The platform of `ctr images import` on a guest of this arch (Go's
# GOARCH: linux/amd64 on amd64; linux/arm64 otherwise, also when the host
# names no arch, as arm64 hosts do not).
def Plan.platform.go(amd64: Bool) -> String:
  match amd64:
    case True{}:
      "linux/amd64"
    case False{}:
      "linux/arm64"

def Plan.platform(+arch: String) -> String:
  Plan.platform.go(String.eq(arch, "amd64"))

def Plan.arch_word.go(hit: Bool, +w: String) -> String:
  match hit:
    case True{}:
      "linux/amd64"
    case False{}:
      w

def Plan.arch_word(+w: String) -> String:
  Plan.arch_word.go(String.eq(w, "linux/arm64"), w)

def Plan.arch_words(ws: +List<String>) -> +List<String>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{+w, rest}:
      Con{Plan.arch_word(w), Plan.arch_words(rest)}

# One argument on amd64: each space-separated word linux/arm64 (the
# import steps' --platform, Plan.runtime and Plan.image_load) becomes
# linux/amd64; the spaces stay as they were.
def Plan.arch_arg(+a: String) -> String:
  String.join(Plan.arch_words(String.split(a, ' ')), " ")

def Plan.arch_list(xs: +List<String>) -> +List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      Con{Plan.arch_arg(x), Plan.arch_list(rest)}

def Plan.arch_args.go(amd64: Bool, args: +List<String>) -> +List<String>:
  match amd64:
    case True{}:
      Plan.arch_list(args)
    case False{}:
      args

# A Run's arguments as PID 1 runs them on a guest of this arch (VK8S_ARCH
# from the kernel command line, src/cli/cli.bend Cli.arch_flags): the
# image import platform becomes Plan.platform(arch). Unchanged on arm64.
def Plan.arch_args(+arch: String, args: +List<String>) -> +List<String>:
  Plan.arch_args.go(String.eq(arch, "amd64"), args)

def Plan.kubectl(args: +List<String>) -> Step:
  Run{Plan.bin() ++ "/kubectl", List.append(&2, String, ["--kubeconfig", Plan.p("super-admin.conf")], args)}

def Plan.sh_words(xs: +List<String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, t}:
      " " ++ Plan.sh_quote(x) ++ Plan.sh_words(t)

# An idempotent `kubectl create`: rendered client-side and applied, so a
# reboot or a restore on an existing data disk finds it already there.
def Plan.kubectl_ensure(args: +List<String>) -> Step:
  +k = Plan.sh_quote(Plan.bin() ++ "/kubectl") ++ " --kubeconfig " ++ Plan.sh_quote(Plan.p("super-admin.conf"))
  Plan.bb(["sh", "-c", "set -o pipefail; " ++ k ++ Plan.sh_words(args) ++ " --dry-run=client -o yaml | " ++ k ++ " apply -f -"])

# What the join server may read: Secrets in kube-system, by name (a
# token's Secret name is known only per request, so no resourceNames).
def Plan.join_server_role() -> Step:
  Plan.kubectl_ensure(["create", "role", "vk8s:join-server", "--namespace=kube-system", "--verb=get", "--resource=secrets"])

def Plan.join_server_binding() -> Step:
  Plan.kubectl_ensure(["create", "rolebinding", "vk8s:join-server", "--namespace=kube-system", "--role=vk8s:join-server",
    "--user=" ++ Plan.join_server_user()])

def Plan.node(+c: Cfg) -> +List<Step>:
  match c:
    case Cfg{+name, +ip, +svc, +pod, +dom, +port, +etcd}:
      +kubeadm = Plan.bin() ++ "/kubeadm"
      +conf = Plan.data() ++ "/kubeadm.yaml"
      +admin = Plan.p("super-admin.conf")
      List.append(&2, Step, Plan.runtime(),
      [ Write{Plan.data() ++ "/kubelet-config.yaml", Plan.kubelet_config(dom)},
        Run{kubeadm, ["init", "phase", "kubeconfig", "kubelet", "--config", conf, "--kubeconfig-dir", Plan.pki()]},
        # containerd keeps its state in memory; after a reboot or a restore the
        # kubelet starts afresh too, and re-creates the node's pods
        Plan.bb(["sh", "-c", "rm -rf " ++ Plan.data() ++ "/kubelet/*"]),
        Daemon{"kubelet", Plan.bin() ++ "/kubelet", Plan.kubelet_args.v2(Cfg{name, ip, svc, pod, dom, port, etcd})},
        # what joining nodes read (kubeadm-config, kubelet-config, cluster-info)
        # and the bootstrap-token RBAC, as vcluster private nodes expect
        Run{kubeadm, ["init", "phase", "upload-config", "all", "--config", conf, "--kubeconfig", admin]},
        Run{kubeadm, ["init", "phase", "bootstrap-token", "--config", conf, "--kubeconfig", admin]},
        Run{kubeadm, ["init", "phase", "addon", "kube-proxy", "--config", conf, "--kubeconfig", admin]},
        Plan.kubectl_ensure(["create", "clusterrolebinding", "kube-apiserver-kubelet-client",
          "--clusterrole=system:kubelet-api-admin", "--user=kube-apiserver-kubelet-client"]),
        Plan.kubectl_ensure(["create", "clusterrolebinding", "kubeadm:cluster-admins", "--clusterrole=cluster-admin",
          "--group=kubeadm:cluster-admins"]),
        Plan.kubectl_ensure(["create", "clusterrole", "vk8s:kube-proxy-nodes", "--verb=get,list,watch", "--resource=nodes"]),
        Plan.kubectl_ensure(["create", "clusterrolebinding", "vk8s:kube-proxy-nodes", "--clusterrole=vk8s:kube-proxy-nodes",
          "--serviceaccount=kube-system:kube-proxy"]),
        # the join server reads bootstrap token Secrets as its own user
        Plan.join_server_role(),
        Plan.join_server_binding(),
        Plan.kubectl(["apply", "-f", "/etc/vk8s/flannel.yaml"]),
        # vcluster's CoreDNS manifests, generated in Bend (src/guest/coredns.bend)
        Write{"/etc/vk8s/coredns.yaml", CD.Coredns.default_manifest()},
        Plan.kubectl(["apply", "-f", "/etc/vk8s/coredns.yaml"]),
        # the opt-in gVisor RuntimeClass (Plan.containerd_runsc)
        Write{Plan.runtimeclass_path(), Plan.runtimeclass_gvisor()},
        Plan.kubectl(["apply", "-f", Plan.runtimeclass_path()]),
        # the join material for worker VMs, on the host share
        Plan.bb(["sh", "-c", Plan.sh_quote(kubeadm) ++ " token create --ttl 1h --kubeconfig " ++ admin
          ++ " > " ++ Plan.host_dir() ++ "/join-token"]),
        Plan.bb(["sh", "-c", "K=" ++ Plan.host_dir() ++ "/discovery.conf; " ++ Plan.sh_quote(Plan.bin() ++ "/kubectl")
          ++ " config set-cluster kubernetes --server=https://" ++ ip ++ ":6443 --certificate-authority=" ++ Plan.p("ca.crt")
          ++ " --embed-certs --kubeconfig=$K >/dev/null && " ++ Plan.sh_quote(Plan.bin() ++ "/kubectl")
          ++ " config set-credentials default --kubeconfig=$K >/dev/null && " ++ Plan.sh_quote(Plan.bin() ++ "/kubectl")
          ++ " config set-context default --cluster=kubernetes --user=default --kubeconfig=$K >/dev/null && "
          ++ Plan.sh_quote(Plan.bin() ++ "/kubectl") ++ " config use-context default --kubeconfig=$K >/dev/null"]),
        Log{"vk8s: node started"} ])

def Plan.boot(+c: Cfg) -> +List<Step>:
  List.append(&2, Step, Plan.system(),
  List.append(&2, Step, [Modules{"/etc/vk8s/modules"}],
  List.append(&2, Step, Plan.sysctls(),
  List.append(&2, Step, Plan.network(c),
  List.append(&2, Step, Plan.disks.v2(),
  List.append(&2, Step, [Mount{"9p", "share", Plan.host_dir(), "trans=virtio,version=9p2000.L"}],
  List.append(&2, Step, Plan.pki_steps(c),
  List.append(&2, Step, Plan.control_plane(c),
  List.append(&2, Step, Plan.node(c), Plan.publish(c))))))))))

# --- The opt-in open-format snapshot (docs/ref/snapshot-decisions.md;
# command lines proven by tests/snapshot_store_spike.sh). Standalone only:
# classic mode has no open-format snapshot (Plan.request_mode; D4), and
# the restore boot exists for Plan.boot only.

# Files the host and the guest exchange on the share.
def Plan.snapshot_dir() -> String:
  Plan.host_dir() ++ "/snapshot"

def Plan.snapshot_export_dir() -> String:
  Plan.snapshot_dir() ++ "/export"

def Plan.snapshot_export_tmp() -> String:
  Plan.snapshot_dir() ++ "/export.tmp"

# The marker: when it exists at boot, the boot restores the store first.
def Plan.restore_marker() -> String:
  Plan.snapshot_dir() ++ "/restore"

# The etcd database to restore (an etcd archive's /vcluster/snapshot/db).
def Plan.restore_db() -> String:
  Plan.snapshot_dir() ++ "/db"

# The puts to apply to kine: two lines each, the key, then the value as a
# Go double-quoted string (strconv.Quote), which etcdctl txn unquotes.
def Plan.restore_puts() -> String:
  Plan.snapshot_dir() ++ "/puts"

def Plan.etcdctl() -> String:
  Plan.bin() ++ "/etcdctl"

# A shell function c: etcdctl on kine's unix socket (no TLS).
def Plan.kine_ctl() -> String:
  "c() { " ++ Plan.etcdctl() ++ " --endpoints " ++ Plan.kine_sock() ++ " \"$@\"; }; "

# The header revision of one line of etcdctl -w json output.
def Plan.json_revision() -> String:
  "sed -n 's/.*\"revision\":\\([0-9]*\\).*/\\1/p'"

# Embedded etcd: etcdctl snapshot save, with the etcd client pair the API
# server uses (Plan.etcd_client), into the export dir.
def Plan.etcd_snapshot_save() -> Step:
  Run{Plan.etcdctl(), [ "--endpoints", "https://127.0.0.1:2379",
    "--cacert", Plan.p("etcd/ca.crt"),
    "--cert", Plan.p("apiserver-etcd-client.crt"),
    "--key", Plan.p("apiserver-etcd-client.key"),
    "snapshot", "save", Plan.snapshot_export_tmp() ++ "/db" ]}

# kine: vcluster's writeKeyValueSnapshot. A count-only get pins the
# archive's revision (file revision); then listStream's pages of 1000:
# page 1 from "/" at the current revision, the next ones from the last
# key at page 1's revision (files page-N.json, raw -w json; the host
# drops the first key of every page after the first, since argv cannot
# carry vcluster's last-key-plus-NUL start). File pages: the page count.
def Plan.kine_dump_script() -> String:
  "set -e; d=" ++ Plan.snapshot_export_tmp() ++ "; " ++ Plan.kine_ctl()
  ++ "rv() { " ++ Plan.json_revision() ++ " \"$1\"; }; "
  ++ "c get / --prefix --count-only -w json > $d/count.json; rv $d/count.json > $d/revision; [ -s $d/revision ]; "
  ++ "n=1; c get / 0 --limit 1000 -w json > $d/page-1.json; r=$(rv $d/page-1.json); [ -n \"$r\" ]; "
  ++ "while grep -q '\"more\":true' $d/page-$n.json; do "
  ++ "k=$(grep -o '\"key\":\"[^\"]*\"' $d/page-$n.json | tail -n 1 | cut -d '\"' -f 4 | base64 -d); n=$((n+1)); "
  ++ "c get \"$k\" 0 --limit 1000 --rev \"$r\" -w json > $d/page-$n.json; done; echo $n > $d/pages"

def Plan.snapshot_dump(etcd: Bool) -> Step:
  match etcd:
    case True{}:
      Plan.etcd_snapshot_save()
    case False{}:
      Plan.bb(["sh", "-c", Plan.kine_dump_script()])

# The request snapshot-export: the store's dump in share/snapshot/export,
# written aside and renamed, so the host never reads half a dump. The
# cluster keeps running (D6).
# Superseded by snapshot-dump (D16): its kine script fails against
# etcdctl 3.5. It stays defined so its laws keep proving; the host
# sends snapshot-dump.
def Plan.snapshot_export(+c: Cfg) -> +List<Step>:
  match c:
    case Cfg{+name, +ip, +svc, +pod, +dom, +port, +etcd}:
      [ Plan.bb(["rm", "-rf", Plan.snapshot_export_dir(), Plan.snapshot_export_tmp()]),
        Plan.bb(["mkdir", "-p", Plan.snapshot_export_tmp()]),
        Plan.snapshot_dump(etcd),
        Plan.bb(["mv", Plan.snapshot_export_tmp(), Plan.snapshot_export_dir()]) ]

# The header revision of etcdctl -w fields output: the line
# "Revision" : N.
def Plan.fields_revision() -> String:
  "sed -n 's/^\"Revision\" : \\([0-9]*\\).*/\\1/p'"

# kine, v2 (D16): vcluster's currentRevision is a count-only get of "/"
# (the header's revision, no key data), and etcdctl 3.5 prints a
# count-only get only with -w fields. The pages are kine_dump_script's.
def Plan.kine_dump_script.v2() -> String:
  "set -e; d=" ++ Plan.snapshot_export_tmp() ++ "; " ++ Plan.kine_ctl()
  ++ "rv() { " ++ Plan.json_revision() ++ " \"$1\"; }; "
  ++ "c get / --prefix --count-only -w fields > $d/count.txt; " ++ Plan.fields_revision() ++ " $d/count.txt > $d/revision; [ -s $d/revision ]; "
  ++ "n=1; c get / 0 --limit 1000 -w json > $d/page-1.json; r=$(rv $d/page-1.json); [ -n \"$r\" ]; "
  ++ "while grep -q '\"more\":true' $d/page-$n.json; do "
  ++ "k=$(grep -o '\"key\":\"[^\"]*\"' $d/page-$n.json | tail -n 1 | cut -d '\"' -f 4 | base64 -d); n=$((n+1)); "
  ++ "c get \"$k\" 0 --limit 1000 --rev \"$r\" -w json > $d/page-$n.json; done; echo $n > $d/pages"

def Plan.snapshot_dump.v2(etcd: Bool) -> Step:
  match etcd:
    case True{}:
      Plan.etcd_snapshot_save()
    case False{}:
      Plan.bb(["sh", "-c", Plan.kine_dump_script.v2()])

# The request snapshot-dump: snapshot-export's steps with the v2 kine
# script (D16).
def Plan.snapshot_dump_steps(+c: Cfg) -> +List<Step>:
  match c:
    case Cfg{+name, +ip, +svc, +pod, +dom, +port, +etcd}:
      [ Plan.bb(["rm", "-rf", Plan.snapshot_export_dir(), Plan.snapshot_export_tmp()]),
        Plan.bb(["mkdir", "-p", Plan.snapshot_export_tmp()]),
        Plan.snapshot_dump.v2(etcd),
        Plan.bb(["mv", Plan.snapshot_export_tmp(), Plan.snapshot_export_dir()]) ]

# Embedded etcd restore (vcluster restoreclient.go: etcdutl's Restore with
# InitialClusterToken vcluster, RevisionBump 1000 for a new data dir,
# MarkCompacted), as the member that Plan.etcd_args starts. etcdutl makes
# the data dir and refuses one that exists.
def Plan.etcd_restore(+name: String) -> Step:
  Run{Plan.bin() ++ "/etcdutl", [ "snapshot", "restore", Plan.restore_db(),
    "--name", name, "--data-dir", Plan.data() ++ "/etcd",
    "--initial-cluster", name ++ "=https://127.0.0.1:2380",
    "--initial-cluster-token", "vcluster",
    "--initial-advertise-peer-urls", "https://127.0.0.1:2380",
    "--bump-revision", "1000", "--mark-compacted" ]}

# kine restore: vcluster's restoreKeyValueSnapshot into a new database.
# Each put is client.Create's txn (mod = 0, then put; kine accepts no
# other create shape) and must succeed; then a compaction at the last
# put's revision, when there was a put. A refused compaction does not
# stop the boot (the spike did not run it on kine).
def Plan.kine_puts_script() -> String:
  "set -e; " ++ Plan.kine_ctl() ++ "r=; while IFS= read -r k && IFS= read -r v; do "
  ++ "printf 'mod(\"%s\") = \"0\"\\n\\nput %s %s\\n\\n\\n' \"$k\" \"$k\" \"$v\" | c txn -w json > /tmp/vk8s-put.json; "
  ++ "grep -q '\"succeeded\":true' /tmp/vk8s-put.json || { echo \"vk8s: restore: create of $k failed\" >&2; cat /tmp/vk8s-put.json >&2; exit 1; }; "
  ++ "r=$(" ++ Plan.json_revision() ++ " /tmp/vk8s-put.json); done < " ++ Plan.restore_puts()
  ++ "; [ -z \"$r\" ] || c compaction \"$r\" || echo \"vk8s: restore: the store refused compaction at revision $r\""

# The store of a restore boot, then k8s (the API server on): etcd restores
# before etcd starts; kine takes the puts once it listens, before the API
# server starts. The marker and the input then leave the share, so a
# reboot boots normally.
def Plan.restore_store(etcd: Bool, +name: String, +k8s: +List<Step>) -> +List<Step>:
  match etcd:
    case True{}:
      List.append(&2, Step,
        [ Log{"vk8s: restoring etcd from the snapshot"},
          Plan.etcd_restore(name),
          Plan.bb(["rm", "-f", Plan.restore_marker(), Plan.restore_db()]) ],
        List.append(&2, Step, Plan.store(True{}, name), k8s))
    case False{}:
      List.append(&2, Step, Plan.store(False{}, name),
        List.append(&2, Step,
          [ Log{"vk8s: restoring kine from the snapshot"},
            Plan.bb(["sh", "-c", Plan.kine_puts_script()]),
            Plan.bb(["rm", "-f", Plan.restore_marker(), Plan.restore_puts()]) ],
          k8s))

def Plan.control_plane_restore(+c: Cfg) -> +List<Step>:
  match c:
    case Cfg{+name, +ip, +svc, +pod, +dom, +port, +etcd}:
      Plan.restore_store(etcd, name, Plan.control_plane.k8s(Cfg{name, ip, svc, pod, dom, port, etcd}))

# The boot; with restore (PID 1 found Plan.restore_marker), the store is
# restored from the share first (vcluster's --new-vcluster restore, D5).
def Plan.boot_restore(+c: Cfg, restore: Bool) -> +List<Step>:
  match restore:
    case False{}:
      Plan.boot(c)
    case True{}:
      List.append(&2, Step, Plan.system(),
      List.append(&2, Step, [Modules{"/etc/vk8s/modules"}],
      List.append(&2, Step, Plan.sysctls(),
      List.append(&2, Step, Plan.network(c),
      List.append(&2, Step, Plan.disks.v2(),
      List.append(&2, Step, [Mount{"9p", "share", Plan.host_dir(), "trans=virtio,version=9p2000.L"}],
      List.append(&2, Step, Plan.pki_steps(c),
      List.append(&2, Step, Plan.control_plane_restore(c),
      List.append(&2, Step, Plan.node(c), Plan.publish(c))))))))))

# etcd: vcluster's embedded etcd instead of kine on SQLite (the standalone
# default; vcluster's conformance configuration uses etcd).
# A classic-mode control plane: the host cluster's service CIDR, as
# vcluster gives its virtual API server (pkg/util/servicecidr).
def Plan.classic_cfg(+name: String, +port: U32, +etcd: Bool, +svc: String) -> Cfg:
  Cfg{name, "10.10.0.2", svc, "10.244.0.0/16", "cluster.local", port, etcd}

def Plan.default_cfg(+name: String, +port: U32, +etcd: Bool) -> Cfg:
  Cfg{name, "10.10.0.2", "10.96.0.0/12", "10.244.0.0/16", "cluster.local", port, etcd}

# The shell command that starts a daemon in its own session, its output
# appended to /var/log/<name>.log.
def Plan.path() -> String:
  "/var/lib/vcluster/bin:/var/lib/vcluster/bin/cni/bin:/usr/sbin:/usr/bin:/sbin:/bin"

def Plan.daemon_cmd(+name: String, prog: String, args: +List<String>) -> String:
  "PATH=" ++ Plan.path() ++ " setsid " ++ Plan.sh_quote(prog) ++ Plan.sh_words(args) ++ " >>" ++ Plan.host_dir() ++ "/logs/" ++ name ++ ".log 2>&1 </dev/null &"

# --- A worker VM (vcluster private node): the same image, joined with a
# kubeadm bootstrap token and the control plane's discovery kubeconfig,
# both from its host share.

type WCfg is Data:
  WCfg{name: String, ip: String, token: String}

def Plan.worker(+w: WCfg) -> +List<Step>:
  match w:
    case WCfg{+name, +ip, +token}:
      +kubeadm = Plan.bin() ++ "/kubeadm"
      List.append(&2, Step, Plan.system(),
      List.append(&2, Step, [Modules{"/etc/vk8s/modules"}],
      List.append(&2, Step, Plan.sysctls(),
      List.append(&2, Step, Plan.net(name, ip),
      List.append(&2, Step, Plan.disks.v2(),
      List.append(&2, Step, [Mount{"9p", "share", Plan.host_dir(), "trans=virtio,version=9p2000.L"},
        Plan.bb(["sh", "-c", "mkdir -p " ++ Plan.data() ++ "/kubelet /var/lib && ln -sfn " ++ Plan.data() ++ "/kubelet /var/lib/kubelet"])],
      List.append(&2, Step, Plan.runtime(),
      # A worker always joins afresh (its kubelet state is wiped), and retries:
      # after a restart or a restore, kubeadm refuses while the old Node
      # object still reads Ready, until the node lifecycle controller's grace.
      [ Spawn{"kubeadm-join", "/bin/sh", ["-c", "rm -rf " ++ Plan.data() ++ "/kubelet/*; until " ++ Plan.sh_quote(kubeadm)
          ++ Plan.sh_words(["join", "--discovery-file", Plan.host_dir() ++ "/discovery.conf",
          "--tls-bootstrap-token", token, "--node-name", name,
          "--cri-socket", "unix:///run/containerd/containerd.sock", "--ignore-preflight-errors=all"])
          ++ "; do echo 'vk8s: join failed, retrying in 10s'; sleep 10; done"]},
        WaitFile{"/var/lib/kubelet/config.yaml", 120000},
        # the cluster CA where the cluster's kubelet-config names it
        Plan.bb(["sh", "-c", "mkdir -p " ++ Plan.pki() ++ " && sed -n 's/^ *certificate-authority-data: *//p' "
          ++ Plan.host_dir() ++ "/discovery.conf | base64 -d > " ++ Plan.p("ca.crt")]),
        Daemon{"kubelet", Plan.bin() ++ "/kubelet", List.append(&2, String, [
          Plan.flag("config", "/var/lib/kubelet/config.yaml"),
          Plan.flag("bootstrap-kubeconfig", "/etc/kubernetes/bootstrap-kubelet.conf"),
          Plan.flag("kubeconfig", "/etc/kubernetes/kubelet.conf"),
          Plan.flag("container-runtime-endpoint", "unix:///run/containerd/containerd.sock"),
          Plan.flag("hostname-override", name),
          Plan.flag("node-ip", ip) ], Plan.kubelet_idle())},
        WaitFile{"/etc/kubernetes/kubelet.conf", 180000},
        Plan.bb(["sh", "-c", "echo ok > " ++ Plan.host_dir() ++ "/joined"]),
        Log{"vk8s: node joined"} ])))))))

# Classic mode is a separate plan so the standalone contract stays fixed.
# The syncer needs TLS, so it runs Plan.guest_bin().

def Plan.syncer(c: Cfg, host_kubeconfig: String, host_namespace: String) -> Step:
  match c:
    case Cfg{name, ip, svc, pod, dom, port, etcd}:
      Daemon{"syncer", Plan.guest_bin(), ["syncer", "--host-kubeconfig", host_kubeconfig,
        "--host-namespace", host_namespace, "--name", name, "--service-cidr", svc]}

# Classic vcluster uses the host scheduler by default. It has no local
# kubelet, containerd, flannel, kube-proxy, or kube-scheduler.
def Plan.classic_control_plane.k8s(+c: Cfg) -> +List<Step>:
  [ Daemon{"kube-apiserver", Plan.bin() ++ "/kube-apiserver", Plan.apiserver_args(c)},
    WaitTcp{"127.0.0.1", 6443, 120000},
    Daemon{"kube-controller-manager", Plan.bin() ++ "/kube-controller-manager", Plan.controller_manager_args_classic(c)},
    Log{"vk8s: classic control plane up"} ]

def Plan.classic_control_plane(+c: Cfg) -> +List<Step>:
  match c:
    case Cfg{+name, +ip, +svc, +pod, +dom, +port, +etcd}:
      List.append(&2, Step, Plan.store(etcd, name), Plan.classic_control_plane.k8s(Cfg{name, ip, svc, pod, dom, port, etcd}))

# The kubeadm config with extra API server SANs after "certSANs:" (classic
# mode: the IP of the vcluster's host Service, as vcluster adds it).
def Plan.add_sans.lines(ss: +List<String>) -> String:
  match ss:
    case Nil{}:
      ""
    case Con{x, t}:
      "  - " ++ x ++ "\n" ++ Plan.add_sans.lines(t)

def Plan.add_sans.at(hit: Bool, +c: Char, +t: String, +ins: String, rest: String) -> String:
  match hit:
    case True{}:
      "certSANs:\n" ++ ins ++ String.drop(t, 9n)
    case False{}:
      SCon{c, rest}

def Plan.add_sans.in(text: String, +ins: String) -> String:
  match text:
    case SNil{}:
      SNil{}
    case SCon{+c, +t}:
      Plan.add_sans.at(String.starts_with(SCon{c, t}, "certSANs:\n"), c, t, ins, Plan.add_sans.in(t, ins))

def Plan.add_sans(+text: String, +sans: +List<String>) -> String:
  Plan.add_sans.in(text, Plan.add_sans.lines(sans))

def Plan.pki_steps_sans.go(ss: +List<Step>, +sans: +List<String>) -> +List<Step>:
  match ss:
    case Con{Write{+p, +t}, rest}:
      Con{Write{p, Plan.add_sans(t, sans)}, rest}
    case other:
      other

def Plan.pki_steps_sans(+c: Cfg, +sans: +List<String>) -> +List<Step>:
  Plan.pki_steps_sans.go(Plan.pki_steps(c), sans)

# --- Konnectivity (classic mode). The virtual API server runs in a VM, not
# in the host cluster, so its "cluster" egress (admission and conversion
# webhooks, aggregated APIs, the service and pod proxy, kubelets) cannot
# reach host Service and pod IPs. It goes through konnectivity instead (the
# upstream EgressSelectorConfiguration): konnectivity-server runs in the VM
# behind a socket, and its agent, a Deployment of the virtual kube-system
# that the syncer places on the host like any pod, dials it through the
# vcluster's host Service (port 8132) and makes the connections from inside
# the host network. Agents authenticate with a virtual service account
# token (audience system:konnectivity-server) that the server reviews; they
# trust the API server's serving certificate, which holds the host
# Service's IP.
def Plan.konnectivity_uds() -> String:
  "/run/konnectivity/server.sock"

def Plan.egress_config_path() -> String:
  Plan.data() ++ "/egress-selector.yaml"

def Plan.egress_config() -> String:
  "apiVersion: apiserver.k8s.io/v1beta1\nkind: EgressSelectorConfiguration\negressSelections:\n- name: cluster\n"
  ++ "  connection:\n    proxyProtocol: GRPC\n    transport:\n      uds:\n        udsName: " ++ Plan.konnectivity_uds() ++ "\n"

def Plan.konnectivity_args() -> +List<String>:
  [ "--uds-name=" ++ Plan.konnectivity_uds(), "--delete-existing-uds-file", "--mode=grpc", "--server-port=0",
    "--agent-port=8132", "--admin-bind-address=127.0.0.1", "--admin-port=8133",
    "--health-bind-address=127.0.0.1", "--health-port=8134",
    "--agent-namespace=kube-system", "--agent-service-account=konnectivity-agent",
    "--authentication-audience=system:konnectivity-server",
    "--kubeconfig=" ++ Plan.p("admin.conf"),
    "--cluster-cert=" ++ Plan.p("apiserver.crt"), "--cluster-key=" ++ Plan.p("apiserver.key"),
    "--server-count=1", "--keepalive-time=30s" ]

# kas-network-proxy v0.34.0, the release of the bundled konnectivity-server.
def Plan.konnectivity_agent_image() -> String:
  "registry.k8s.io/kas-network-proxy/proxy-agent:v0.34.0@sha256:8cc86d24691c4145d1c364eb0846e8865f98b5beab1e6e21b96ceb4dff6fce54"

# The agent's objects in the virtual cluster; host is the vcluster's host
# Service IP.
def Plan.konnectivity_agent_manifest(+host: String) -> String:
  "apiVersion: v1\nkind: ServiceAccount\nmetadata:\n  name: konnectivity-agent\n  namespace: kube-system\n---\n"
  ++ "apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: konnectivity-agent\n  namespace: kube-system\n"
  ++ "  labels:\n    k8s-app: konnectivity-agent\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      k8s-app: konnectivity-agent\n"
  ++ "  template:\n    metadata:\n      labels:\n        k8s-app: konnectivity-agent\n    spec:\n"
  ++ "      serviceAccountName: konnectivity-agent\n      tolerations:\n      - operator: Exists\n"
  ++ "      containers:\n      - name: konnectivity-agent\n        image: " ++ Plan.konnectivity_agent_image() ++ "\n"
  ++ "        command: [\"/proxy-agent\"]\n        args:\n        - --logtostderr=true\n"
  ++ "        - --ca-cert=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt\n"
  ++ "        - --proxy-server-host=" ++ host ++ "\n        - --proxy-server-port=8132\n"
  ++ "        - --admin-server-port=8133\n        - --health-server-port=8134\n"
  ++ "        - --service-account-token-path=/var/run/secrets/tokens/konnectivity-agent-token\n"
  ++ "        livenessProbe:\n          httpGet:\n            port: 8134\n            path: /healthz\n          initialDelaySeconds: 15\n          timeoutSeconds: 15\n"
  ++ "        volumeMounts:\n        - name: konnectivity-agent-token\n          mountPath: /var/run/secrets/tokens\n"
  ++ "      volumes:\n      - name: konnectivity-agent-token\n        projected:\n          sources:\n"
  ++ "          - serviceAccountToken:\n              path: konnectivity-agent-token\n              audience: system:konnectivity-server\n"

# The classic control plane with konnectivity: the API server's egress goes
# through the server's socket.
def Plan.classic_control_plane_konn.k8s(+c: Cfg) -> +List<Step>:
  [ Write{Plan.egress_config_path(), Plan.egress_config()},
    Plan.bb(["mkdir", "-p", "/run/konnectivity"]),
    Daemon{"konnectivity-server", Plan.bin() ++ "/konnectivity-server", Plan.konnectivity_args()},
    Daemon{"kube-apiserver", Plan.bin() ++ "/kube-apiserver",
      List.append(&2, String, Plan.apiserver_args(c), [Plan.flag("egress-selector-config-file", Plan.egress_config_path())])},
    WaitTcp{"127.0.0.1", 6443, 120000},
    Daemon{"kube-controller-manager", Plan.bin() ++ "/kube-controller-manager", Plan.controller_manager_args_classic(c)},
    Log{"vk8s: classic control plane up"} ]

def Plan.classic_control_plane_konn(+c: Cfg) -> +List<Step>:
  match c:
    case Cfg{+name, +ip, +svc, +pod, +dom, +port, +etcd}:
      List.append(&2, Step, Plan.store(etcd, name), Plan.classic_control_plane_konn.k8s(Cfg{name, ip, svc, pod, dom, port, etcd}))

# The syncer with the fake kubelet's address for nodes: the host Service IP,
# which the agents reach (its kubelet port leads to the VM's :10250).
def Plan.syncer_kip(c: Cfg, host_kubeconfig: String, host_namespace: String, kip: String) -> Step:
  match c:
    case Cfg{name, ip, svc, pod, dom, port, etcd}:
      Daemon{"syncer", Plan.guest_bin(), ["syncer", "--host-kubeconfig", host_kubeconfig,
        "--host-namespace", host_namespace, "--name", name, "--service-cidr", svc, "--kubelet-ip", kip]}

def Plan.classic_x.body(+c: Cfg, +sans: +List<String>, +cp: +List<Step>, +tail: +List<Step>) -> +List<Step>:
  List.append(&2, Step, Plan.system(),
  List.append(&2, Step, [Modules{"/etc/vk8s/modules"}],
  List.append(&2, Step, Plan.sysctls(),
  List.append(&2, Step, Plan.network(c),
  List.append(&2, Step, Plan.disks.v2(),
  List.append(&2, Step, [Mount{"9p", "share", Plan.host_dir(), "trans=virtio,version=9p2000.L"}],
  List.append(&2, Step, Plan.pki_steps_sans(c, sans),
  List.append(&2, Step, cp,
  # admin.conf's user is in kubeadm:cluster-admins (kubeadm >= 1.29): the
  # syncer runs with it, so the group must be bound as the node plan binds it
  # vcluster's CoreDNS in the virtual cluster (src/guest/coredns.bend,
  # classic: no pinned clusterIP); the syncer copies it to the host
  List.append(&2, Step, [Plan.kubectl_ensure(["create", "clusterrolebinding", "kubeadm:cluster-admins", "--clusterrole=cluster-admin",
      "--group=kubeadm:cluster-admins"]),
    Write{"/etc/vk8s/coredns.yaml", CD.Coredns.classic_manifest()},
    Plan.kubectl(["apply", "-f", "/etc/vk8s/coredns.yaml"])],
  List.append(&2, Step, Plan.publish(c), tail))))))))))

# Classic mode. With the host Service's IP (the first SAN, from the host
# CLI): konnectivity, its agent and the syncer's kubelet address; without
# one (Plan.classic), none of them.
def Plan.first_or(+xs: +List<String>, +d: String) -> String:
  match xs:
    case Nil{}:
      d
    case Con{x, t}:
      x

def Plan.classic_x(+c: Cfg, host_kubeconfig: String, host_namespace: String, +sans: +List<String>) -> +List<Step>:
  match sans:
    case Nil{}:
      Plan.classic_x.body(c, [], Plan.classic_control_plane(c), [Plan.syncer(c, host_kubeconfig, host_namespace)])
    case Con{+ip, +rest}:
      Plan.classic_x.body(c, Con{ip, rest}, Plan.classic_control_plane_konn(c),
        [ Plan.syncer_kip(c, host_kubeconfig, host_namespace, ip),
          Write{"/etc/vk8s/konnectivity-agent.yaml", Plan.konnectivity_agent_manifest(Plan.first_or(rest, ip))},
          Plan.kubectl(["apply", "-f", "/etc/vk8s/konnectivity-agent.yaml"]) ])

def Plan.classic(+c: Cfg, host_kubeconfig: String, host_namespace: String) -> +List<Step>:
  Plan.classic_x(c, host_kubeconfig, host_namespace, [])

# --- Requests from the host (vk8s certs rotate|check): the host writes
# "ID ACTION" to share/requests/request; PID 1 runs the action's steps and
# answers "ID done" or "ID failed" in share/requests/response. Unknown
# actions have no steps (and fail).

def Plan.requests_dir() -> String:
  Plan.host_dir() ++ "/requests"

# kubeadm's certs commands look for kubeconfigs in /etc/kubernetes (they
# take no --kubeconfig-dir); vk8s keeps them with the PKI, as vcluster
# does. Links let kubeadm read and renew them in place.
def Plan.link_kubeconfigs() -> Step:
  Plan.bb(["sh", "-c", "mkdir -p /etc/kubernetes && for f in " ++ Plan.pki() ++ "/*.conf; do ln -sf \"$f\" /etc/kubernetes/; done"])

# The daemons that load the PKI at start (kube-apiserver reloads its
# serving and client CA files by itself, but restarts too).
def Plan.cp_daemons() -> +List<String>:
  ["kubelet", "kube-scheduler", "kube-controller-manager", "kube-apiserver", "etcd"]

# kubeadm certs renew all renews every certificate kubeadm made (and the
# client certificates in its kubeconfigs) with the CA kept; the supervisor
# restarts the control plane daemons it is told to stop, which then load
# them; the kubeconfig is published again for the host.
def Plan.certs_rotate(+c: Cfg) -> +List<Step>:
  List.append(&2, Step,
    [ Log{"vk8s: rotating certificates"},
      Plan.link_kubeconfigs(),
      Run{Plan.bin() ++ "/kubeadm", ["certs", "renew", "all", "--config", Plan.data() ++ "/kubeadm.yaml"]},
      Stop{Plan.cp_daemons()} ],
    Plan.publish(c))

def Plan.certs_check(+out: String) -> +List<Step>:
  [ Plan.link_kubeconfigs(),
    Plan.bb(["sh", "-c", Plan.sh_quote(Plan.bin() ++ "/kubeadm") ++ " certs check-expiration --config " ++ Plan.data() ++ "/kubeadm.yaml > " ++ Plan.sh_quote(out) ++ " 2>&1"]) ]

# vcluster certs rotate-ca (pkg/certs/rotate.go, withCA): back up the PKI
# to pki.bak/<time>, remove every file but the service account keys
# (sa.key, sa.pub: tokens stay valid), make the whole PKI anew, and restart
# the control plane on it. The steps that need the API run afterwards
# (Plan.certs_ca_finish), once the supervisor has restarted it.
def Plan.certs_rotate_ca(+c: Cfg) -> +List<Step>:
  +conf = Plan.data() ++ "/kubeadm.yaml"
  List.append(&2, Step,
    [ Log{"vk8s: rotating the certificate authority"},
      Plan.bb(["sh", "-c", "set -e; b=" ++ Plan.data() ++ "/pki.bak/$(date +%Y%m%d-%H%M%S); mkdir -p \"$b\"; cp -a " ++ Plan.pki() ++ "/. \"$b/\"; "
        ++ "find " ++ Plan.pki() ++ " -type f ! -name sa.key ! -name sa.pub -delete"]) ],
  List.append(&2, Step, Plan.pki_steps(c),
    [ Run{Plan.bin() ++ "/kubeadm", ["init", "phase", "kubeconfig", "kubelet", "--config", conf, "--kubeconfig-dir", Plan.pki()]},
      Stop{Plan.cp_daemons()} ]))

# After rotate-ca, with the API back: the cluster-info CA joining nodes
# read, a fresh join token and discovery file, and the kubeconfig.
def Plan.certs_ca_finish(+c: Cfg) -> +List<Step>:
  match c:
    case Cfg{+name, +ip, +svc, +pod, +dom, +port, +etcd}:
      +kubeadm = Plan.bin() ++ "/kubeadm"
      +conf = Plan.data() ++ "/kubeadm.yaml"
      +admin = Plan.p("super-admin.conf")
      List.append(&2, Step,
        [ Run{kubeadm, ["init", "phase", "upload-config", "all", "--config", conf, "--kubeconfig", admin]},
          Run{kubeadm, ["init", "phase", "bootstrap-token", "--config", conf, "--kubeconfig", admin]},
          Plan.bb(["sh", "-c", Plan.sh_quote(kubeadm) ++ " token create --ttl 1h --kubeconfig " ++ admin ++ " > " ++ Plan.host_dir() ++ "/join-token"]),
          # in-cluster clients keep the CA they started with: restart the
          # add-ons (workloads that call the API need the same)
          Plan.kubectl(["-n", "kube-system", "rollout", "restart", "deployment/coredns", "daemonset/kube-proxy"]),
          Plan.kubectl(["-n", "kube-flannel", "rollout", "restart", "daemonset/kube-flannel-ds"]) ],
        Plan.publish(Cfg{name, ip, svc, pod, dom, port, etcd}))

def Plan.request.ca(rot: Bool, fin: Bool, +c: Cfg) -> +List<Step>:
  match rot fin:
    case True{} _:
      Plan.certs_rotate_ca(c)
    case False{} True{}:
      Plan.certs_ca_finish(c)
    case False{} False{}:
      Nil{}

def Plan.request.dump(dump: Bool, +action: String, +c: Cfg) -> +List<Step>:
  match dump:
    case True{}:
      Plan.snapshot_dump_steps(c)
    case False{}:
      Plan.request.ca(String.eq(action, "certs-rotate-ca"), String.eq(action, "certs-ca-finish"), c)

def Plan.request.snap(exp: Bool, +action: String, +c: Cfg) -> +List<Step>:
  match exp:
    case True{}:
      Plan.snapshot_export(c)
    case False{}:
      Plan.request.dump(String.eq(action, "snapshot-dump"), action, c)

def Plan.request.go(rot: Bool, chk: Bool, +action: String, +c: Cfg, +out: String) -> +List<Step>:
  match rot chk:
    case True{} _:
      Plan.certs_rotate(c)
    case False{} True{}:
      Plan.certs_check(out)
    case False{} False{}:
      Plan.request.snap(String.eq(action, "snapshot-export"), action, c)

def Plan.safe_chr(c: Char) -> Bool:
  match c:
    case Chr{+u}:
      (U32.is_ge(u, 97) && U32.is_le(u, 122)) || (U32.is_ge(u, 48) && U32.is_le(u, 57)) || U32.is_eq(u, 46) || U32.is_eq(u, 45)

def Plan.safe_all(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      Bool.and(Plan.safe_chr(c), Plan.safe_all(t))

# A file name the host chose under share/images: [a-z0-9.-]+, not "." or "..".
def Plan.safe_name(+f: String) -> Bool:
  Bool.not(String.is_empty(f)) && Plan.safe_all(f) && Bool.not(String.starts_with(f, "."))

# vcluster node load-image --archive: import an image archive the host put
# on this VM's share (tar, or tar.gz), then remove it.
def Plan.image_load.go(ok: Bool, +f: String) -> +List<Step>:
  match ok:
    case True{}:
      +path = Plan.host_dir() ++ "/images/" ++ f
      [ Plan.bb(["sh", "-c", "set -o pipefail; case " ++ Plan.sh_quote(path) ++ " in *.gz) gunzip -c ;; *) cat ;; esac < " ++ Plan.sh_quote(path)
          ++ " | " ++ Plan.sh_quote(Plan.bin() ++ "/ctr") ++ " --address /run/containerd/containerd.sock -n k8s.io images import --platform linux/arm64 -; r=$?; rm -f "
          ++ Plan.sh_quote(path) ++ "; exit $r"]) ]
    case False{}:
      Nil{}

def Plan.request.more(load: Bool, +action: String, +c: Cfg, +out: String) -> +List<Step>:
  match load:
    case True{}:
      +f = String.drop(action, 11n)
      Plan.image_load.go(Plan.safe_name(f), f)
    case False{}:
      Plan.request.go(String.eq(action, "certs-rotate"), String.eq(action, "certs-check"), action, c, out)

# sync: flush the page cache to the disks (vk8s snapshot sends it before
# it pauses the VMs and copies the data disk).
def Plan.request.sync(sync: Bool, +action: String, +c: Cfg, +out: String) -> +List<Step>:
  match sync:
    case True{}:
      [Plan.bb(["sync"])]
    case False{}:
      Plan.request.more(String.starts_with(action, "image-load:"), action, c, out)

def Plan.request(+action: String, +c: Cfg, +out: String) -> +List<Step>:
  Plan.request.sync(String.eq(action, "sync"), action, c, out)

def Plan.request_mode.go(snap: Bool, +action: String, +c: Cfg, +out: String) -> +List<Step>:
  match snap:
    case True{}:
      Nil{}
    case False{}:
      Plan.request(action, c, out)

# A request in either mode: classic mode refuses the open-format snapshot
# (docs/ref/snapshot-decisions.md D4), so its snapshot actions have no
# steps (and fail); standalone requests are Plan.request's.
def Plan.request_mode(classic: Bool, +action: String, +c: Cfg, +out: String) -> +List<Step>:
  match classic:
    case True{}:
      Plan.request_mode.go(String.starts_with(action, "snapshot-"), action, c, out)
    case False{}:
      Plan.request(action, c, out)

# --- Automatic renewal (vcluster pkg/certs watcher.go): every 24 h, when a
# leaf certificate is within 90 days of expiry, rotate them all.

def Plan.cert_check_ms() -> Nat:
  86400000n

def Plan.cert_renew_days() -> U32:
  90

# The residual times of kubeadm's leaf certificate table, one per line
# (kubeadm certs check-expiration: "364d", "89d", "23h", "<invalid>").
def Plan.residuals_file() -> String:
  "/run/vk8s-cert-residuals"

def Plan.certs_residuals() -> Step:
  Plan.bb(["sh", "-c", Plan.sh_quote(Plan.bin() ++ "/kubeadm") ++ " certs check-expiration --config " ++ Plan.data()
    ++ "/kubeadm.yaml 2>/dev/null | awk 'NR == 1 { next } /^$/ { exit } /^CERTIFICATE AUTHORITY/ { exit } { for (i = 2; i <= NF; i++) if ($i ~ /^([0-9]+[ydhms]|<invalid>)$/) { print $i; break } }' > "
    ++ Plan.residuals_file()])

def Plan.residual_days.go(m: Maybe<&2, U32>) -> Bool:
  match m:
    case Some{+d}:
      U32.is_lt(d, Plan.cert_renew_days())
    case None{}:
      True{}

def Plan.residual_expiring.go(years: Bool, days: Bool, +r: String) -> Bool:
  match years days:
    case True{} _:
      False{}
    case False{} True{}:
      Plan.residual_days.go(U32.read(String.take(r, Nat.sub(String.length(r), 1n))))
    case False{} False{}:
      True{}

# One residual time: expiring when it is under 90 days (hours, minutes,
# seconds, or "<invalid>" for an expired certificate). Years never are.
def Plan.residual_expiring(+r: String) -> Bool:
  Plan.residual_expiring.go(String.ends_with(r, "y"), String.ends_with(r, "d"), r)

def Plan.certs_expiring(rs: List<&2, String>) -> Bool:
  match rs:
    case Nil{}:
      False{}
    case Con{+r, t}:
      Bool.or(Bool.and(Bool.not(String.is_empty(String.trim(r))), Plan.residual_expiring(String.trim(r))), Plan.certs_expiring(t))

# The daemons' logs live on the share, which has a quota (bend-vmm). PID 1
# trims them about once a minute: a log past 32 MiB keeps its last 8 MiB
# as NAME.log.1 and is truncated in place (daemons append with O_APPEND,
# so they keep writing at the new end).
def Plan.trim_logs() -> Step:
  Plan.bb(["sh", "-c", "for f in " ++ Plan.host_dir() ++ "/logs/*.log; do [ -f \"$f\" ] || continue; "
    ++ "[ $(wc -c < \"$f\") -gt 33554432 ] || continue; tail -c 8388608 \"$f\" > \"$f.1\" && : > \"$f\"; done; true"])

# The guest's clock stops while the Mac sleeps (the virtual timer does not
# count then), so a guest falls behind the host and TLS between clusters
# fails ("certificate is not yet valid"). bend-vmm's PL031 RTC reads the
# host's clock: PID 1 sets the system time from it every 10 ticks (10 s).
def Plan.clock_sync() -> Step:
  Plan.bb(["hwclock", "-s", "-u"])

def Plan.clock_every_ticks() -> U32:
  10

def Plan.trim_every_ticks() -> U32:
  60

# Disk give-back (docs/GOAL.md section 7). bend-vmm offers virtio-blk
# DISCARD on writable disks and punches holes in the raw image for every
# range the guest discards. The data disk (/dev/vdb at the data dir: etcd
# or kine, containerd's images and snapshots, the cache VM's registry
# blobs) is trimmed by a periodic fstrim from PID 1, not mounted with
# -o discard: online discard sends a discard with every delete, and
# containerd removes many small files while etcd and kine compact often,
# so each delete would wait on the host's hole punch. fstrim batches what
# was freed since the last run (ext4 skips block groups it trimmed and
# that freed nothing since), every 10 min; kubelet's image GC runs every
# 5 min, so a removed image goes back to the host within about 15 min.
# busybox has fstrim (Alpine busybox-static, CONFIG_FSTRIM=y). It runs in
# the background, so PID 1 keeps reaping and serving requests; -v writes
# what each run gave back to share/logs/fstrim.log. Every VM runs it: the
# control plane, workers and the image cache share PID 1's loop.
def Plan.fstrim() -> Step:
  Spawn{"fstrim", Plan.busybox(), ["fstrim", "-v", Plan.data()]}

# 600 ticks of 1 s: 10 min.
def Plan.fstrim_every_ticks() -> U32:
  600

def Plan.fstrim_due(+tick: U32) -> Bool:
  U32.is_eq((tick % Plan.fstrim_every_ticks() : U32), 0)
# --- Memory give-back (GOAL section 7; docs/ref/footprint-decisions.md M2).
# bend-vmm's virtio-balloon returns the pages the guest reports free
# (virtio_balloon is in the modules list), but the page cache counts as in
# use: after an image pull or a pod burst it holds hundreds of MiB that the
# host never gets back. So PID 1 reclaims page cache, only when the node
# is idle.
#
# Why memory.reclaim on the root cgroup: it reclaims a given amount the way
# kswapd does (coldest pages first), stops at it, and never OOM-kills;
# swappiness=0 limits it to page cache and slab. drop_caches cannot keep a
# floor of hot pages (the text of kubelet and containerd); vfs_cache_pressure
# acts only under memory pressure, which an idle guest does not have;
# memory.high is a limit that would throttle kubelet and containerd under
# load; page_reporting_order (default 2 MiB) chooses which free blocks are
# reported, not how much memory is free, so it stays at the default.
#
# Idle: less than 10% of all vCPU time busy since the last run, 30 s ago
# (/proc/stat; iowait counts as busy, so a pull blocked on disk is not
# idle) and not backing off after refaults (Plan.reclaim_state). Amount:
# Active(file) + Inactive(file) above a 64 MiB floor (the refault guard
# keeps a hot working set from being reclaimed again and again), and
# nothing when that is under 16 MiB. Errors (EAGAIN when less could be
# reclaimed) are ignored: the step always succeeds.
def Plan.reclaim_every_ticks() -> U32:
  30

def Plan.idle_busy_percent() -> U32:
  10

def Plan.cache_keep_kib() -> U32:
  65536

def Plan.reclaim_min_kib() -> U32:
  16384

# The last total and idle CPU counters, from one run to the next.
def Plan.cpu_state() -> String:
  "/run/vk8s-cpu"

# Refault guard: when the node re-read more than 2560 file pages (10 MiB)
# since the last run (workingset_refault_file), the cache it holds is in
# use, so reclaim backs off for 120 runs (1 h).
def Plan.reclaim_state() -> String:
  "/run/vk8s-reclaim"

def Plan.refault_max_pages() -> U32:
  2560

def Plan.reclaim_backoff_runs() -> U32:
  120

def Plan.idle_reclaim_script() -> String:
  +s = Plan.cpu_state()
  "set -- $(head -n 1 /proc/stat); t=$(($2+$3+$4+$5+$6+$7+$8+$9)); i=$5; { read pt pi < " ++ s
    ++ "; } 2>/dev/null || { pt=0; pi=0; }; echo \"$t $i\" > " ++ s
    ++ "; dt=$((t-pt)); b=$((dt-i+pi)); [ $pt -gt 0 ] && [ $dt -gt 0 ] && [ $((b*100)) -lt $((dt*" ++ U32.show(Plan.idle_busy_percent())
    ++ ")) ] || exit 0; r=$(awk '/^workingset_refault_file / { print $2 }' /proc/vmstat); { read pr pc < " ++ Plan.reclaim_state()
    ++ "; } 2>/dev/null || { pr=$r; pc=0; }; [ $((r-pr)) -gt " ++ U32.show(Plan.refault_max_pages())
    ++ " ] && pc=" ++ U32.show(Plan.reclaim_backoff_runs())
    ++ "; if [ $pc -gt 0 ]; then echo \"$r $((pc-1))\" > " ++ Plan.reclaim_state() ++ "; exit 0; fi; echo \"$r 0\" > " ++ Plan.reclaim_state()
    ++ "; k=$(awk '/^(Active|Inactive)\\(file\\):/ { s += $2 } END { print s - " ++ U32.show(Plan.cache_keep_kib())
    ++ " }' /proc/meminfo); [ \"$k\" -ge " ++ U32.show(Plan.reclaim_min_kib())
    ++ " ] || exit 0; { echo \"${k}K swappiness=0\" > /sys/fs/cgroup/memory.reclaim; } 2>/dev/null; true"

def Plan.idle_reclaim() -> Step:
  Plan.bb(["sh", "-c", Plan.idle_reclaim_script()])

# bend-vmm returns a ballooned or reported range only in whole 64 KiB
# blocks (16 guest pages), so on fragmented guest memory most freed pages
# stay charged to the host. Every 600 ticks (10 min), when the node was
# idle over that window (its own /proc/stat state, so the 30 s reclaim
# window is untouched), PID 1 compacts memory: free pages gather into
# whole blocks that free page reporting and the balloon can return.
def Plan.compact_every_ticks() -> U32:
  600

def Plan.compact_state() -> String:
  "/run/vk8s-cpu-compact"

def Plan.idle_compact_script() -> String:
  +s = Plan.compact_state()
  "set -- $(head -n 1 /proc/stat); t=$(($2+$3+$4+$5+$6+$7+$8+$9)); i=$5; { read pt pi < " ++ s
    ++ "; } 2>/dev/null || { pt=0; pi=0; }; echo \"$t $i\" > " ++ s
    ++ "; dt=$((t-pt)); b=$((dt-i+pi)); [ $pt -gt 0 ] && [ $dt -gt 0 ] && [ $((b*100)) -lt $((dt*" ++ U32.show(Plan.idle_busy_percent())
    ++ ")) ] || exit 0; { echo 1 > /proc/sys/vm/compact_memory; } 2>/dev/null; true"

def Plan.idle_compact() -> Step:
  Plan.bb(["sh", "-c", Plan.idle_compact_script()])
