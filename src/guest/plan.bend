import Base

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
  # wait until a TCP port accepts connections, up to ms
  WaitTcp{host: String, port: U32, ms: U32}
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

# bend-vmm's user-mode NAT: the guest is 10.0.2.15/24, the host 10.0.2.2,
# its resolver 10.0.2.3.
def Plan.network(+c: Cfg) -> +List<Step>:
  match c:
    case Cfg{+name, +ip, +svc, +pod, +dom, +port, +etcd}:
      [ Plan.bb(["hostname", name]),
        Plan.bb(["ip", "link", "set", "lo", "up"]),
        Plan.bb(["ip", "link", "set", "eth0", "up"]),
        Plan.bb(["ip", "addr", "add", ip ++ "/24", "dev", "eth0"]),
        Plan.bb(["ip", "route", "add", "default", "via", "10.0.2.2"]),
        Write{"/etc/resolv.conf", "nameserver 10.0.2.3\n"},
        Write{"/etc/hosts", "127.0.0.1 localhost\n" ++ ip ++ " " ++ name ++ "\n"} ]

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
      ++ "apiServer:\n  certSANs:\n  - 127.0.0.1\n  - localhost\n  - " ++ name ++ "\n"

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

# vcluster pkg/k8s/k8s.go startKine: SQLite through kine.
def Plan.kine_args() -> +List<String>:
  [ Plan.flag("endpoint", "sqlite://" ++ Plan.data() ++ "/state.db?_journal=WAL&cache=shared&_busy_timeout=30000&_txlock=immediate"),
    Plan.flag("listen-address", Plan.kine_sock()),
    Plan.flag("metrics-bind-address", "127.0.0.1:2381") ]

def Plan.store(etcd: Bool, +name: String) -> +List<Step>:
  match etcd:
    case True{}:
      [ Daemon{"etcd", Plan.bin() ++ "/etcd", Plan.etcd_args(name)},
        WaitTcp{"127.0.0.1", 2379, 60000} ]
    case False{}:
      [ Daemon{"kine", Plan.bin() ++ "/kine", Plan.kine_args()},
        WaitFile{Plan.data() ++ "/kine.sock", 30000} ]

# vcluster pkg/k8s/k8s.go StartAPIServer, standalone with private nodes.
# Differences, because the API is reached through bend-vmm's port forward
# rather than vcluster's 8443 proxy: it binds every address and advertises
# the node IP.
def Plan.apiserver_args.base(+c: Cfg) -> +List<String>:
  match c:
    case Cfg{+name, +ip, +svc, +pod, +dom, +port, +etcd}:
      [ Plan.flag("service-cluster-ip-range", svc),
        Plan.flag("bind-address", "0.0.0.0"),
        Plan.flag("secure-port", "6443"),
        Plan.flag("advertise-address", ip),
        Plan.flag("allow-privileged", "true"),
        Plan.flag("authorization-mode", "Node,RBAC"),
        Plan.flag("client-ca-file", Plan.p("client-ca.crt")),
        Plan.flag("enable-bootstrap-token-auth", "true"),
        Plan.flag("etcd-servers", Plan.etcd_servers(etcd)),
        Plan.flag("proxy-client-cert-file", Plan.p("front-proxy-client.crt")),
        Plan.flag("proxy-client-key-file", Plan.p("front-proxy-client.key")),
        Plan.flag("requestheader-allowed-names", "front-proxy-client"),
        Plan.flag("requestheader-client-ca-file", Plan.p("front-proxy-ca.crt")),
        Plan.flag("requestheader-extra-headers-prefix", "X-Remote-Extra-"),
        Plan.flag("requestheader-group-headers", "X-Remote-Group"),
        Plan.flag("requestheader-username-headers", "X-Remote-User"),
        Plan.flag("service-account-issuer", "https://kubernetes.default.svc." ++ dom),
        Plan.flag("service-account-key-file", Plan.p("sa.pub")),
        Plan.flag("service-account-signing-key-file", Plan.p("sa.key")),
        Plan.flag("tls-cert-file", Plan.p("apiserver.crt")),
        Plan.flag("tls-private-key-file", Plan.p("apiserver.key")),
        Plan.flag("profiling", "false"),
        # vcluster passes --endpoint-reconciler-type=none and its
        # k8sdefaultendpoint controller keeps default/kubernetes; until that
        # controller is ported, the apiserver's lease reconciler does it.
        Plan.flag("endpoint-reconciler-type", "lease"),
        Plan.flag("kubelet-client-certificate", Plan.p("apiserver-kubelet-client.crt")),
        Plan.flag("kubelet-client-key", Plan.p("apiserver-kubelet-client.key")),
        Plan.flag("enable-admission-plugins", "NodeRestriction"),
        Plan.flag("kubelet-preferred-address-types", "InternalDNS,InternalIP,Hostname,ExternalDNS,ExternalIP") ]

# vcluster pkg/k8s/k8s.go StartControllerManager, private nodes.
# The etcd client certificates go only with etcd (kine listens on a unix
# socket without TLS), as vcluster does.
def Plan.etcd_client(etcd: Bool) -> +List<String>:
  match etcd:
    case True{}:
      [ Plan.flag("etcd-cafile", Plan.p("etcd/ca.crt")),
        Plan.flag("etcd-certfile", Plan.p("apiserver-etcd-client.crt")),
        Plan.flag("etcd-keyfile", Plan.p("apiserver-etcd-client.key")) ]
    case False{}:
      []

def Plan.apiserver_args(+c: Cfg) -> +List<String>:
  match c:
    case Cfg{+name, +ip, +svc, +pod, +dom, +port, +etcd}:
      List.append(&2, String, Plan.apiserver_args.base(Cfg{name, ip, svc, pod, dom, port, etcd}), Plan.etcd_client(etcd))

def Plan.controller_manager_args(+c: Cfg) -> +List<String>:
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

# vcluster pkg/k8s/k8s.go StartScheduler.
def Plan.scheduler_args() -> +List<String>:
  +kc = Plan.p("scheduler.conf")
  [ Plan.flag("authentication-kubeconfig", kc),
    Plan.flag("authorization-kubeconfig", kc),
    Plan.flag("bind-address", "127.0.0.1"),
    Plan.flag("kubeconfig", kc),
    Plan.flag("leader-elect", "true") ]

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
  ++ "[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc]\n  runtime_type = \"io.containerd.runc.v2\"\n"
  ++ "  [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]\n    SystemdCgroup = false\n    BinaryName = \"/var/lib/vcluster/bin/runc\"\n"
  ++ "[plugins.'io.containerd.cri.v1.runtime'.cni]\n  bin_dirs = [\"/var/lib/vcluster/bin/cni/bin\"]\n  conf_dir = \"/etc/cni/net.d\"\n"

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

def Plan.node(+c: Cfg) -> +List<Step>:
  match c:
    case Cfg{+name, +ip, +svc, +pod, +dom, +port, +etcd}:
      +kubeadm = Plan.bin() ++ "/kubeadm"
      +conf = Plan.data() ++ "/kubeadm.yaml"
      [ Write{"/etc/containerd/config.toml", Plan.containerd_config()},
        Write{"/etc/cni/net.d/10-vk8s.conflist", Plan.cni_config()},
        Write{Plan.data() ++ "/kubelet-config.yaml", Plan.kubelet_config(dom)},
        Plan.bb(["mkdir", "-p", "/etc/kubernetes/manifests", "/var/lib/cni"]),
        Daemon{"containerd", Plan.bin() ++ "/containerd", ["--config", "/etc/containerd/config.toml"]},
        WaitFile{"/run/containerd/containerd.sock", 30000},
        Run{Plan.bin() ++ "/ctr", ["--address", "/run/containerd/containerd.sock", "-n", "k8s.io", "images", "import", Plan.bin() ++ "/pause-image.tar"]},
        Run{kubeadm, ["init", "phase", "kubeconfig", "kubelet", "--config", conf, "--kubeconfig-dir", Plan.pki()]},
        Daemon{"kubelet", Plan.bin() ++ "/kubelet", Plan.kubelet_args(Cfg{name, ip, svc, pod, dom, port, etcd})},
        Plan.bb(["sh", "-c", Plan.sh_quote(kubeadm) ++ " kubeconfig user --client-name=system:kube-proxy --config "
          ++ Plan.sh_quote(conf) ++ " > " ++ Plan.p("kube-proxy.conf")]),
        Daemon{"kube-proxy", Plan.bin() ++ "/kube-proxy", Plan.kube_proxy_args(Cfg{name, ip, svc, pod, dom, port, etcd})},
        Run{Plan.bin() ++ "/kubectl", ["--kubeconfig", Plan.p("super-admin.conf"), "create", "clusterrolebinding",
          "kube-apiserver-kubelet-client", "--clusterrole=system:kubelet-api-admin", "--user=kube-apiserver-kubelet-client"]},
        Run{Plan.bin() ++ "/kubectl", ["--kubeconfig", Plan.p("super-admin.conf"), "create", "clusterrolebinding",
          "kubeadm:cluster-admins", "--clusterrole=cluster-admin", "--group=kubeadm:cluster-admins"]},
        Run{Plan.bin() ++ "/kubectl", ["--kubeconfig", Plan.p("super-admin.conf"), "create", "clusterrole",
          "vk8s:kube-proxy-nodes", "--verb=get,list,watch", "--resource=nodes"]},
        Run{Plan.bin() ++ "/kubectl", ["--kubeconfig", Plan.p("super-admin.conf"), "create", "clusterrolebinding",
          "vk8s:kube-proxy-nodes", "--clusterrole=vk8s:kube-proxy-nodes", "--user=system:kube-proxy"]},
        Run{Plan.bin() ++ "/kubectl", ["--kubeconfig", Plan.p("super-admin.conf"), "apply", "-f", "/etc/vk8s/coredns.yaml"]},
        Log{"vk8s: node started"} ]

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
  Cfg{name, "10.0.2.15", "10.96.0.0/12", "10.244.0.0/16", "cluster.local", port, etcd}

def Plan.sh_words(xs: +List<String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, t}:
      " " ++ Plan.sh_quote(x) ++ Plan.sh_words(t)

# The shell command that starts a daemon in its own session, its output
# appended to /var/log/<name>.log.
def Plan.path() -> String:
  "/var/lib/vcluster/bin:/var/lib/vcluster/bin/cni/bin:/usr/sbin:/usr/bin:/sbin:/bin"

def Plan.daemon_cmd(+name: String, prog: String, args: +List<String>) -> String:
  "PATH=" ++ Plan.path() ++ " setsid " ++ Plan.sh_quote(prog) ++ Plan.sh_words(args) ++ " >>" ++ Plan.host_dir() ++ "/logs/" ++ name ++ ".log 2>&1 </dev/null &"
