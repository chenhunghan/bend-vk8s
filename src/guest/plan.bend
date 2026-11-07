import Base
import ../lib/args.bend as A

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

def Plan.sysctls() -> +List<Step>:
  [ Write{"/proc/sys/net/ipv4/ip_forward", "1"},
    Write{"/proc/sys/net/bridge/bridge-nf-call-iptables", "1"},
    Write{"/proc/sys/net/bridge/bridge-nf-call-ip6tables", "1"},
    Write{"/proc/sys/fs/inotify/max_user_watches", "524288"} ]

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
      ++ "cgroupDriver: cgroupfs\nfailSwapOn: false\nresolvConf: /etc/resolv.conf\n"

def Plan.pki_steps(+c: Cfg) -> +List<Step>:
  +kubeadm = Plan.bin() ++ "/kubeadm"
  +conf = Plan.data() ++ "/kubeadm.yaml"
  [ Write{conf, Plan.kubeadm_config(c)},
    Run{kubeadm, ["init", "phase", "certs", "all", "--config", conf]},
    Run{kubeadm, ["init", "phase", "kubeconfig", "admin", "--config", conf, "--kubeconfig-dir", Plan.pki()]},
    Run{kubeadm, ["init", "phase", "kubeconfig", "super-admin", "--config", conf, "--kubeconfig-dir", Plan.pki()]},
    Run{kubeadm, ["init", "phase", "kubeconfig", "controller-manager", "--config", conf, "--kubeconfig-dir", Plan.pki()]},
    Run{kubeadm, ["init", "phase", "kubeconfig", "scheduler", "--config", conf, "--kubeconfig-dir", Plan.pki()]},
    Plan.bb(["cp", Plan.p("ca.crt"), Plan.p("client-ca.crt")]),
    Plan.bb(["cp", Plan.p("ca.crt"), Plan.p("server-ca.crt")]),
    Plan.bb(["cp", Plan.p("ca.key"), Plan.p("server-ca.key")]) ]

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

def Plan.control_plane.k8s(+c: Cfg) -> +List<Step>:
  [ Daemon{"kube-apiserver", Plan.bin() ++ "/kube-apiserver", Plan.apiserver_args(c)},
    WaitTcp{"127.0.0.1", 6443, 120000},
    Daemon{"kube-controller-manager", Plan.bin() ++ "/kube-controller-manager", Plan.controller_manager_args(c)},
    Daemon{"kube-scheduler", Plan.bin() ++ "/kube-scheduler", Plan.scheduler_args()},
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
  ++ "failSwapOn: false\nresolvConf: /etc/resolv.conf\nstaticPodPath: /etc/kubernetes/manifests\n"

def Plan.kubelet_args(+c: Cfg) -> +List<String>:
  match c:
    case Cfg{+name, +ip, +svc, +pod, +dom, +port, +etcd}:
      [ Plan.flag("config", Plan.data() ++ "/kubelet-config.yaml"),
        Plan.flag("kubeconfig", Plan.p("kubelet.conf")),
        Plan.flag("root-dir", Plan.data() ++ "/kubelet"),
        Plan.flag("hostname-override", name),
        Plan.flag("node-ip", ip) ]

def Plan.kube_proxy_args(+c: Cfg) -> +List<String>:
  match c:
    case Cfg{+name, +ip, +svc, +pod, +dom, +port, +etcd}:
      [ Plan.flag("kubeconfig", Plan.p("kube-proxy.conf")),
        Plan.flag("cluster-cidr", pod),
        Plan.flag("hostname-override", name),
        Plan.flag("proxy-mode", "iptables") ]

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
  List.append(&2, Step, Plan.disks(),
  List.append(&2, Step, [Mount{"9p", "share", Plan.host_dir(), "trans=virtio,version=9p2000.L"}],
  List.append(&2, Step, Plan.registry_steps(Plan.mirrors()),
    [ WaitTcp{"127.0.0.1", 15004, 30000},
      Plan.bb(["sh", "-c", "echo ok > " ++ Plan.host_dir() ++ "/ready"]),
      Log{"vk8s: image cache ready"} ]))))))

def Plan.runtime() -> +List<Step>:
  List.append(&2, Step, Plan.mirror_steps(Plan.mirrors()),
  [ Write{"/etc/containerd/config.toml", Plan.containerd_config()},
    Plan.bb(["sh", "-c", "mkdir -p /opt/cni/bin /etc/cni/net.d /var/lib/cni /etc/kubernetes/manifests && cp /var/lib/vcluster/bin/cni/bin/* /opt/cni/bin/"]),
    Daemon{"containerd", Plan.bin() ++ "/containerd", ["--config", "/etc/containerd/config.toml"]},
    WaitFile{"/run/containerd/containerd.sock", 30000},
    Run{Plan.bin() ++ "/ctr", ["--address", "/run/containerd/containerd.sock", "-n", "k8s.io", "images", "import", Plan.bin() ++ "/pause-image.tar"]},
    # images preloaded on the assets disk (scripts/guest/images.sh): the
    # cluster's own add-ons start without a pull
    Plan.bb(["sh", "-c", "for f in " ++ Plan.bin() ++ "/images/*.tar; do [ -f \"$f\" ] || continue; " ++ Plan.bin()
      ++ "/ctr --address /run/containerd/containerd.sock -n k8s.io images import --platform linux/arm64 \"$f\" >/dev/null || exit 1; done"]) ])

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
        Daemon{"kubelet", Plan.bin() ++ "/kubelet", Plan.kubelet_args(Cfg{name, ip, svc, pod, dom, port, etcd})},
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
        Plan.kubectl(["apply", "-f", "/etc/vk8s/flannel.yaml"]),
        Plan.kubectl(["apply", "-f", "/etc/vk8s/coredns.yaml"]),
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
  List.append(&2, Step, Plan.disks(),
  List.append(&2, Step, [Mount{"9p", "share", Plan.host_dir(), "trans=virtio,version=9p2000.L"}],
  List.append(&2, Step, Plan.pki_steps(c),
  List.append(&2, Step, Plan.control_plane(c),
  List.append(&2, Step, Plan.node(c), Plan.publish(c))))))))))

# etcd: vcluster's embedded etcd instead of kine on SQLite (the standalone
# default; vcluster's conformance configuration uses etcd).
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
      List.append(&2, Step, Plan.disks(),
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
        Daemon{"kubelet", Plan.bin() ++ "/kubelet", [
          Plan.flag("config", "/var/lib/kubelet/config.yaml"),
          Plan.flag("bootstrap-kubeconfig", "/etc/kubernetes/bootstrap-kubelet.conf"),
          Plan.flag("kubeconfig", "/etc/kubernetes/kubelet.conf"),
          Plan.flag("container-runtime-endpoint", "unix:///run/containerd/containerd.sock"),
          Plan.flag("hostname-override", name),
          Plan.flag("node-ip", ip) ]},
        WaitFile{"/etc/kubernetes/kubelet.conf", 180000},
        Plan.bb(["sh", "-c", "echo ok > " ++ Plan.host_dir() ++ "/joined"]),
        Log{"vk8s: node joined"} ])))))))

# Classic mode is a separate plan so the standalone contract stays fixed.
# The guest image installs host/init.bend twice: /sbin/vk8s-init (PID 1,
# static musl) and /usr/bin/vk8s-guest (dynamic glibc, with libssl.so.3
# and libcrypto.so.3 for bend-kube-runtime's dlopen'd TLS client). The
# syncer needs TLS, so it runs the second one.
def Plan.guest_bin() -> String:
  "/usr/bin/vk8s-guest"

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
    Daemon{"kube-controller-manager", Plan.bin() ++ "/kube-controller-manager", Plan.controller_manager_args(c)},
    Log{"vk8s: classic control plane up"} ]

def Plan.classic_control_plane(+c: Cfg) -> +List<Step>:
  match c:
    case Cfg{+name, +ip, +svc, +pod, +dom, +port, +etcd}:
      List.append(&2, Step, Plan.store(etcd, name), Plan.classic_control_plane.k8s(Cfg{name, ip, svc, pod, dom, port, etcd}))

def Plan.classic(+c: Cfg, host_kubeconfig: String, host_namespace: String) -> +List<Step>:
  List.append(&2, Step, Plan.system(),
  List.append(&2, Step, [Modules{"/etc/vk8s/modules"}],
  List.append(&2, Step, Plan.sysctls(),
  List.append(&2, Step, Plan.network(c),
  List.append(&2, Step, Plan.disks(),
  List.append(&2, Step, [Mount{"9p", "share", Plan.host_dir(), "trans=virtio,version=9p2000.L"}],
  List.append(&2, Step, Plan.pki_steps(c),
  List.append(&2, Step, Plan.classic_control_plane(c),
  List.append(&2, Step, Plan.publish(c), [Plan.syncer(c, host_kubeconfig, host_namespace)])))))))))

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

def Plan.request.go(rot: Bool, chk: Bool, +action: String, +c: Cfg, +out: String) -> +List<Step>:
  match rot chk:
    case True{} _:
      Plan.certs_rotate(c)
    case False{} True{}:
      Plan.certs_check(out)
    case False{} False{}:
      Plan.request.ca(String.eq(action, "certs-rotate-ca"), String.eq(action, "certs-ca-finish"), c)

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

def Plan.request(+action: String, +c: Cfg, +out: String) -> +List<Step>:
  Plan.request.more(String.starts_with(action, "image-load:"), action, c, out)

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

def Plan.trim_every_ticks() -> U32:
  240
