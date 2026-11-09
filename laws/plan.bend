import Base
import ../src/lib/args.bend as A
import ../src/guest/plan.bend as P

# Spec for the control-plane command lines of src/guest/plan.bend. Each
# base list is vcluster pkg/k8s/k8s.go (main a8ab30e) transcribed by hand:
# the flags StartK8S appends, in its order and with its values, for
# PrivateNodes.Enabled, Konnectivity off and ResourceClaimTemplates sync
# off; vcluster's /data/pki is vk8s's /var/lib/vcluster/pki and /data is
# /var/lib/vcluster. Plan.default_cfg gives service CIDR 10.96.0.0/12,
# pod CIDR 10.244.0.0/16, cluster domain cluster.local, node IP 10.10.0.2.

# kube-apiserver, kine (StartBackingStore, EmbeddedDatabase: the endpoint
# is K8sKineEndpoint and there are no etcd certificates).
law plan.apiserver.sqlite.base:
  {P.Plan.apiserver_args.base(P.Plan.default_cfg("demo", 6443, False{})) ==
    [ "--service-cluster-ip-range=10.96.0.0/12",
      "--bind-address=127.0.0.1",
      "--allow-privileged=true",
      "--authorization-mode=Node,RBAC",
      "--client-ca-file=/var/lib/vcluster/pki/client-ca.crt",
      "--enable-bootstrap-token-auth=true",
      "--etcd-servers=unix:///var/lib/vcluster/kine.sock",
      "--proxy-client-cert-file=/var/lib/vcluster/pki/front-proxy-client.crt",
      "--proxy-client-key-file=/var/lib/vcluster/pki/front-proxy-client.key",
      "--requestheader-allowed-names=front-proxy-client",
      "--requestheader-client-ca-file=/var/lib/vcluster/pki/front-proxy-ca.crt",
      "--requestheader-extra-headers-prefix=X-Remote-Extra-",
      "--requestheader-group-headers=X-Remote-Group",
      "--requestheader-username-headers=X-Remote-User",
      "--secure-port=6443",
      "--service-account-issuer=https://kubernetes.default.svc.cluster.local",
      "--service-account-key-file=/var/lib/vcluster/pki/sa.pub",
      "--service-account-signing-key-file=/var/lib/vcluster/pki/sa.key",
      "--tls-cert-file=/var/lib/vcluster/pki/apiserver.crt",
      "--tls-private-key-file=/var/lib/vcluster/pki/apiserver.key",
      "--profiling=false",
      "--advertise-address=127.0.0.1",
      "--endpoint-reconciler-type=none",
      "--kubelet-client-certificate=/var/lib/vcluster/pki/apiserver-kubelet-client.crt",
      "--kubelet-client-key=/var/lib/vcluster/pki/apiserver-kubelet-client.key",
      "--enable-admission-plugins=NodeRestriction",
      "--endpoint-reconciler-type=none",
      "--kubelet-preferred-address-types=InternalDNS,InternalIP,Hostname,ExternalDNS,ExternalIP" ] : +List<String>}

# vk8s's overrides are its apiServer.extraArgs.
law plan.apiserver.overrides:
  {P.Plan.apiserver_overrides("10.10.0.2") ==
    [ "--bind-address=0.0.0.0",
      "--advertise-address=10.10.0.2",
      "--endpoint-reconciler-type=lease" ] : +List<String>}

# The merge (vcluster: args = command.MergeArgs(args, apiServer.ExtraArgs)).
law plan.apiserver.sqlite.merge:
  {P.Plan.apiserver_args(P.Plan.default_cfg("demo", 6443, False{})) ==
    A.Args.merge(P.Plan.apiserver_args.base(P.Plan.default_cfg("demo", 6443, False{})),
      P.Plan.apiserver_overrides("10.10.0.2")) : +List<String>}

# Its result: --bind-address, --advertise-address and both
# --endpoint-reconciler-type leave the base list; the overrides close it.
law plan.apiserver.sqlite:
  {P.Plan.apiserver_args(P.Plan.default_cfg("demo", 6443, False{})) ==
    [ "--service-cluster-ip-range=10.96.0.0/12",
      "--allow-privileged=true",
      "--authorization-mode=Node,RBAC",
      "--client-ca-file=/var/lib/vcluster/pki/client-ca.crt",
      "--enable-bootstrap-token-auth=true",
      "--etcd-servers=unix:///var/lib/vcluster/kine.sock",
      "--proxy-client-cert-file=/var/lib/vcluster/pki/front-proxy-client.crt",
      "--proxy-client-key-file=/var/lib/vcluster/pki/front-proxy-client.key",
      "--requestheader-allowed-names=front-proxy-client",
      "--requestheader-client-ca-file=/var/lib/vcluster/pki/front-proxy-ca.crt",
      "--requestheader-extra-headers-prefix=X-Remote-Extra-",
      "--requestheader-group-headers=X-Remote-Group",
      "--requestheader-username-headers=X-Remote-User",
      "--secure-port=6443",
      "--service-account-issuer=https://kubernetes.default.svc.cluster.local",
      "--service-account-key-file=/var/lib/vcluster/pki/sa.pub",
      "--service-account-signing-key-file=/var/lib/vcluster/pki/sa.key",
      "--tls-cert-file=/var/lib/vcluster/pki/apiserver.crt",
      "--tls-private-key-file=/var/lib/vcluster/pki/apiserver.key",
      "--profiling=false",
      "--kubelet-client-certificate=/var/lib/vcluster/pki/apiserver-kubelet-client.crt",
      "--kubelet-client-key=/var/lib/vcluster/pki/apiserver-kubelet-client.key",
      "--enable-admission-plugins=NodeRestriction",
      "--kubelet-preferred-address-types=InternalDNS,InternalIP,Hostname,ExternalDNS,ExternalIP",
      "--bind-address=0.0.0.0",
      "--advertise-address=10.10.0.2",
      "--endpoint-reconciler-type=lease" ] : +List<String>}

# kube-apiserver, embedded etcd (StartBackingStore: endpoint
# https://127.0.0.1:2379, certificates PKIDir/etcd/ca.crt and
# PKIDir/apiserver-etcd-client.{crt,key}, right after --etcd-servers).
law plan.apiserver.etcd.base:
  {P.Plan.apiserver_args.base(P.Plan.default_cfg("demo", 6443, True{})) ==
    [ "--service-cluster-ip-range=10.96.0.0/12",
      "--bind-address=127.0.0.1",
      "--allow-privileged=true",
      "--authorization-mode=Node,RBAC",
      "--client-ca-file=/var/lib/vcluster/pki/client-ca.crt",
      "--enable-bootstrap-token-auth=true",
      "--etcd-servers=https://127.0.0.1:2379",
      "--etcd-cafile=/var/lib/vcluster/pki/etcd/ca.crt",
      "--etcd-certfile=/var/lib/vcluster/pki/apiserver-etcd-client.crt",
      "--etcd-keyfile=/var/lib/vcluster/pki/apiserver-etcd-client.key",
      "--proxy-client-cert-file=/var/lib/vcluster/pki/front-proxy-client.crt",
      "--proxy-client-key-file=/var/lib/vcluster/pki/front-proxy-client.key",
      "--requestheader-allowed-names=front-proxy-client",
      "--requestheader-client-ca-file=/var/lib/vcluster/pki/front-proxy-ca.crt",
      "--requestheader-extra-headers-prefix=X-Remote-Extra-",
      "--requestheader-group-headers=X-Remote-Group",
      "--requestheader-username-headers=X-Remote-User",
      "--secure-port=6443",
      "--service-account-issuer=https://kubernetes.default.svc.cluster.local",
      "--service-account-key-file=/var/lib/vcluster/pki/sa.pub",
      "--service-account-signing-key-file=/var/lib/vcluster/pki/sa.key",
      "--tls-cert-file=/var/lib/vcluster/pki/apiserver.crt",
      "--tls-private-key-file=/var/lib/vcluster/pki/apiserver.key",
      "--profiling=false",
      "--advertise-address=127.0.0.1",
      "--endpoint-reconciler-type=none",
      "--kubelet-client-certificate=/var/lib/vcluster/pki/apiserver-kubelet-client.crt",
      "--kubelet-client-key=/var/lib/vcluster/pki/apiserver-kubelet-client.key",
      "--enable-admission-plugins=NodeRestriction",
      "--endpoint-reconciler-type=none",
      "--kubelet-preferred-address-types=InternalDNS,InternalIP,Hostname,ExternalDNS,ExternalIP" ] : +List<String>}

law plan.apiserver.etcd.merge:
  {P.Plan.apiserver_args(P.Plan.default_cfg("demo", 6443, True{})) ==
    A.Args.merge(P.Plan.apiserver_args.base(P.Plan.default_cfg("demo", 6443, True{})),
      P.Plan.apiserver_overrides("10.10.0.2")) : +List<String>}

law plan.apiserver.etcd:
  {P.Plan.apiserver_args(P.Plan.default_cfg("demo", 6443, True{})) ==
    [ "--service-cluster-ip-range=10.96.0.0/12",
      "--allow-privileged=true",
      "--authorization-mode=Node,RBAC",
      "--client-ca-file=/var/lib/vcluster/pki/client-ca.crt",
      "--enable-bootstrap-token-auth=true",
      "--etcd-servers=https://127.0.0.1:2379",
      "--etcd-cafile=/var/lib/vcluster/pki/etcd/ca.crt",
      "--etcd-certfile=/var/lib/vcluster/pki/apiserver-etcd-client.crt",
      "--etcd-keyfile=/var/lib/vcluster/pki/apiserver-etcd-client.key",
      "--proxy-client-cert-file=/var/lib/vcluster/pki/front-proxy-client.crt",
      "--proxy-client-key-file=/var/lib/vcluster/pki/front-proxy-client.key",
      "--requestheader-allowed-names=front-proxy-client",
      "--requestheader-client-ca-file=/var/lib/vcluster/pki/front-proxy-ca.crt",
      "--requestheader-extra-headers-prefix=X-Remote-Extra-",
      "--requestheader-group-headers=X-Remote-Group",
      "--requestheader-username-headers=X-Remote-User",
      "--secure-port=6443",
      "--service-account-issuer=https://kubernetes.default.svc.cluster.local",
      "--service-account-key-file=/var/lib/vcluster/pki/sa.pub",
      "--service-account-signing-key-file=/var/lib/vcluster/pki/sa.key",
      "--tls-cert-file=/var/lib/vcluster/pki/apiserver.crt",
      "--tls-private-key-file=/var/lib/vcluster/pki/apiserver.key",
      "--profiling=false",
      "--kubelet-client-certificate=/var/lib/vcluster/pki/apiserver-kubelet-client.crt",
      "--kubelet-client-key=/var/lib/vcluster/pki/apiserver-kubelet-client.key",
      "--enable-admission-plugins=NodeRestriction",
      "--kubelet-preferred-address-types=InternalDNS,InternalIP,Hostname,ExternalDNS,ExternalIP",
      "--bind-address=0.0.0.0",
      "--advertise-address=10.10.0.2",
      "--endpoint-reconciler-type=lease" ] : +List<String>}

# kube-controller-manager: appendClusterSigningArgs without a split CA
# (server-ca.crt and client-ca.crt are both kubeadm's ca.crt), then the
# private-nodes flags. No extraArgs, so the merge keeps the list.
law plan.controller_manager:
  {P.Plan.controller_manager_args(P.Plan.default_cfg("demo", 6443, False{})) ==
    [ "--service-cluster-ip-range=10.96.0.0/12",
      "--authentication-kubeconfig=/var/lib/vcluster/pki/controller-manager.conf",
      "--authorization-kubeconfig=/var/lib/vcluster/pki/controller-manager.conf",
      "--bind-address=127.0.0.1",
      "--client-ca-file=/var/lib/vcluster/pki/client-ca.crt",
      "--cluster-name=kubernetes",
      "--kubeconfig=/var/lib/vcluster/pki/controller-manager.conf",
      "--requestheader-client-ca-file=/var/lib/vcluster/pki/front-proxy-ca.crt",
      "--root-ca-file=/var/lib/vcluster/pki/server-ca.crt",
      "--service-account-private-key-file=/var/lib/vcluster/pki/sa.key",
      "--use-service-account-credentials=true",
      "--leader-elect=true",
      "--cluster-signing-cert-file=/var/lib/vcluster/pki/server-ca.crt",
      "--cluster-signing-key-file=/var/lib/vcluster/pki/server-ca.key",
      "--controllers=*,bootstrapsigner,tokencleaner",
      "--allocate-node-cidrs=true",
      "--cluster-cidr=10.244.0.0/16",
      "--cloud-provider=external" ] : +List<String>}

# kube-scheduler (it runs because PrivateNodes.Enabled).
law plan.scheduler:
  {P.Plan.scheduler_args() ==
    [ "--authentication-kubeconfig=/var/lib/vcluster/pki/scheduler.conf",
      "--authorization-kubeconfig=/var/lib/vcluster/pki/scheduler.conf",
      "--bind-address=127.0.0.1",
      "--kubeconfig=/var/lib/vcluster/pki/scheduler.conf",
      "--leader-elect=true" ] : +List<String>}

# kine (StartKineWithDone): the default SQLite data source
# sqlite://<K8sSqliteDatabase><SQLiteParams>, no TLS flags (the embedded
# CaFile, KeyFile and CertFile are empty), LocalBackingStoreMetricsHost,
# then K8sKineEndpoint.
law plan.kine:
  {P.Plan.kine_args() ==
    [ "--endpoint=sqlite:///var/lib/vcluster/state.db?_journal=WAL&cache=shared&_busy_timeout=30000&_txlock=immediate",
      "--metrics-bind-address=127.0.0.1:2381",
      "--listen-address=unix:///var/lib/vcluster/kine.sock" ] : +List<String>}

# Plan.sh_quote: a POSIX shell single-quoted word.

law plan.sh_quote.empty:
  {P.Plan.sh_quote("") == "''" : String}

law plan.sh_quote.plain:
  {P.Plan.sh_quote("/var/lib/vcluster/bin/kubeadm") == "'/var/lib/vcluster/bin/kubeadm'" : String}

# ' closes the quote, adds an escaped quote and reopens: 'it'\''s'.
law plan.sh_quote.single_quote:
  {P.Plan.sh_quote("it's") == "'it'\\''s'" : String}

# The image cache. containerd's registry host configuration
# (docs/hosts.md): `server` is the upstream, each [host."URL"] a mirror
# tried first, with the capabilities it serves.

law plan.hosts_toml.docker:
  {P.Plan.hosts_toml(P.Mirror{"docker.io", "https://registry-1.docker.io", 15001})
   == "server = \"https://registry-1.docker.io\"\n\n[host.\"http://10.0.2.2:15001\"]\n  capabilities = [\"pull\", \"resolve\"]\n" : String}

# The cache gets `pull` only (security review F5): tags resolve upstream.
law plan.hosts_toml_pull.docker:
  {P.Plan.hosts_toml_pull(P.Mirror{"docker.io", "https://registry-1.docker.io", 15001})
   == "server = \"https://registry-1.docker.io\"\n\n[host.\"http://10.0.2.2:15001\"]\n  capabilities = [\"pull\"]\n" : String}

# Host requests: only known actions have steps.
law plan.request.unknown:
  {List.length(&2, P.Step, P.Plan.request("rm -rf /", P.Plan.default_cfg("demo", 12000, False{}), "/o")) == 0n : Nat}

law plan.request.check:
  {List.length(&2, P.Step, P.Plan.request("certs-check", P.Plan.default_cfg("demo", 12000, False{}), "/o")) == 2n : Nat}

# image-load takes a plain file name under share/images only.
law plan.request.image_load:
  {List.length(&2, P.Step, P.Plan.request("image-load:app-1.0.tar.gz", P.Plan.default_cfg("demo", 12000, False{}), "/o")) == 1n : Nat}

law plan.request.image_load_traversal:
  {List.length(&2, P.Step, P.Plan.request("image-load:../../etc/shadow", P.Plan.default_cfg("demo", 12000, False{}), "/o")) == 0n : Nat}

# Automatic renewal: vcluster renews when a leaf certificate is within 90
# days of expiry (pkg/certs/watcher.go), checking every 24 h.
law plan.certs_expiring.fresh:
  {P.Plan.certs_expiring(["364d", "364d", "9y"]) == False{} : Bool}

law plan.certs_expiring.within_90:
  {P.Plan.certs_expiring(["364d", "89d"]) == True{} : Bool}

law plan.certs_expiring.at_90:
  {P.Plan.certs_expiring(["90d"]) == False{} : Bool}

law plan.certs_expiring.hours:
  {P.Plan.certs_expiring(["23h"]) == True{} : Bool}

law plan.certs_expiring.expired:
  {P.Plan.certs_expiring(["<invalid>"]) == True{} : Bool}

law plan.certs_expiring.none:
  {P.Plan.certs_expiring([]) == False{} : Bool}

law plan.cert_check_daily:
  {P.Plan.cert_check_ms() == 86400000n : Nat}

# Since the k8sdefaultendpoint port: vcluster's --endpoint-reconciler-type=none
# stays (no override), and PID 1 writes default/kubernetes.
law plan.apiserver.overrides_ep:
  {P.Plan.apiserver_overrides_ep("10.10.0.2") == ["--bind-address=0.0.0.0", "--advertise-address=10.10.0.2"] : +List<String>}

law plan.apiserver.ep_merge:
  {P.Plan.apiserver_args_ep(P.Plan.default_cfg("demo", 6443, False{})) ==
    A.Args.merge(P.Plan.apiserver_args.base(P.Plan.default_cfg("demo", 6443, False{})), P.Plan.apiserver_overrides_ep("10.10.0.2")) : +List<String>}

# Classic mode: the vcluster host Service's IP joins the API server's SANs
# (vcluster adds its service IP to the certificate). Stated on a short
# certSANs block: the whole kubeadm config is too much for the verdict
# kernel's fuel, and tests/plan.bend checks the real config.
law plan.add_sans.inserts:
  {P.Plan.add_sans("apiServer:\n  certSANs:\n  - 127.0.0.1\n", ["10.100.0.5"])
   == "apiServer:\n  certSANs:\n  - 10.100.0.5\n  - 127.0.0.1\n" : String}

law plan.add_sans.none:
  {P.Plan.add_sans("apiServer:\n  certSANs:\n  - 127.0.0.1\n", []) == "apiServer:\n  certSANs:\n  - 127.0.0.1\n" : String}

# Classic mode's controller manager (vcluster pkg/k8s/k8s.go, the branch
# without private nodes or the virtual scheduler): the shared flags, then
# these.
law plan.controller_manager.classic_tail:
  {List.drop(&2, String, P.Plan.controller_manager_args_classic(P.Plan.classic_cfg("vc", 12000, False{}, "10.96.0.0/12")), 14n) ==
    [ "--controllers=*,-nodeipam,-nodelifecycle,-persistentvolume-binder,-attachdetach,-persistentvolume-expander,-cloud-node-lifecycle,-ttl",
      "--node-monitor-grace-period=180s",
      "--node-monitor-period=30s",
      "--pvclaimbinder-sync-period=60s",
      "--horizontal-pod-autoscaler-sync-period=60s" ] : +List<String>}

law plan.controller_manager.classic_shared:
  {List.take(&2, String, P.Plan.controller_manager_args_classic(P.Plan.classic_cfg("vc", 12000, False{}, "10.96.0.0/12")), 14n) ==
    List.take(&2, String, P.Plan.controller_manager_args.base(P.Plan.classic_cfg("vc", 12000, False{}, "10.96.0.0/12")), 14n) : +List<String>}

# Proposed: classic mode's konnectivity (vk8s design: the VM is outside the
# host network). The syncer advertises the vcluster Service's IP as its
# nodes' kubelet address; the agent's host is the second SAN, else the first.
law plan.syncer_kip:
  {P.Plan.syncer_kip(P.Plan.default_cfg("demo", 6443, True{}), "/var/lib/vk8s-host/host-kubeconfig", "host-ns", "10.100.0.5")
    == P.Daemon{"syncer", "/usr/bin/vk8s-guest", ["syncer", "--host-kubeconfig", "/var/lib/vk8s-host/host-kubeconfig",
      "--host-namespace", "host-ns", "--name", "demo", "--service-cidr", "10.96.0.0/12", "--kubelet-ip", "10.100.0.5"]} : P.Step}
law plan.first_or.some:
  {P.Plan.first_or(["10.100.0.9"], "10.100.0.5") == "10.100.0.9" : String}
law plan.first_or.none:
  {P.Plan.first_or([], "10.100.0.5") == "10.100.0.5" : String}

# Proposed: classic mode with vcluster's virtual scheduler
# (controlPlane.advanced.virtualScheduler or distro.k8s.scheduler). The
# controller manager takes vcluster pkg/k8s/k8s.go's
# IsVirtualSchedulerEnabled branch (no private nodes, ResourceClaimTemplates
# sync off): the shared flags, then these.
law plan.controller_manager.vsched_tail:
  {List.drop(&2, String, P.Plan.controller_manager_args_vsched(P.Plan.classic_cfg("vc", 12000, False{}, "10.96.0.0/12")), 14n) ==
    [ "--controllers=*,-nodeipam,-persistentvolume-binder,-attachdetach,-persistentvolume-expander,-cloud-node-lifecycle,-ttl",
      "--node-monitor-grace-period=1h",
      "--node-monitor-period=1h",
      "--pvclaimbinder-sync-period=60s",
      "--horizontal-pod-autoscaler-sync-period=60s" ] : +List<String>}

law plan.controller_manager.vsched_shared:
  {List.take(&2, String, P.Plan.controller_manager_args_vsched(P.Plan.classic_cfg("vc", 12000, False{}, "10.96.0.0/12")), 14n) ==
    List.take(&2, String, P.Plan.controller_manager_args.base(P.Plan.classic_cfg("vc", 12000, False{}, "10.96.0.0/12")), 14n) : +List<String>}

# k8s.go StartK8S starts kube-scheduler when IsVirtualSchedulerEnabled;
# vk8s starts it right after the controller manager, which takes the
# virtual-scheduler flags.
law plan.virtual_scheduler.daemon:
  for c: P.Cfg
  for prog: String
  for args: +List<String>
  {P.Plan.virtual_scheduler(c, [P.Daemon{"kube-controller-manager", prog, args}]) ==
    [P.Daemon{"kube-controller-manager", prog, P.Plan.controller_manager_args_vsched(c)},
     P.Daemon{"kube-scheduler", "/var/lib/vcluster/bin/kube-scheduler", P.Plan.scheduler_args()}] : +List<P.Step>}

# Other steps stay as they are.
law plan.virtual_scheduler.syncer:
  for c: P.Cfg
  for prog: String
  for args: +List<String>
  {P.Plan.virtual_scheduler(c, [P.Daemon{"syncer", prog, args}]) == [P.Daemon{"syncer", prog, args}] : +List<P.Step>}

# vk8s: the syncer reads the vcluster.yaml that vk8s create -f put on the
# share.
law plan.syncer_config:
  for prog: String
  for args: +List<String>
  {P.Plan.syncer_config("/var/lib/vk8s-host/vcluster.yaml", [P.Daemon{"syncer", prog, args}]) ==
    [P.Daemon{"syncer", prog, List.append(&2, String, args, ["--config", "/var/lib/vk8s-host/vcluster.yaml"])}] : +List<P.Step>}

law plan.syncer_config.other:
  for prog: String
  for args: +List<String>
  {P.Plan.syncer_config("/var/lib/vk8s-host/vcluster.yaml", [P.Daemon{"kube-apiserver", prog, args}]) ==
    [P.Daemon{"kube-apiserver", prog, args}] : +List<P.Step>}
