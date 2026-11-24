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

# Proposed: PID 1 sets the guest clock from bend-vmm's RTC (the host's
# clock) every 10 s, since the guest clock stops while the Mac sleeps.
# Amended 2026-11-15 with the user's approval (idle CPU, GOAL section 7):
# PID 1's tick is 1 s instead of 250 ms, so every tick count below (clock,
# fstrim, reclaim, compaction) is a quarter of its old value; the periods
# in seconds are unchanged.
law plan.clock_sync:
  {P.Plan.clock_sync() == P.Run{"/bin/busybox", ["hwclock", "-s", "-u"]} : P.Step}
law plan.clock_every_ticks:
  {P.Plan.clock_every_ticks() == 10 : U32}


# Proposed: the standalone /node/join server (vk8s design,
# docs/ref/standalone-decisions.md J1; vcluster's handler is closed
# source). The glibc guest binary serves it on 8443 (OpenSSL is dlopened),
# started once the API server answers. It reads token Secrets through the
# front-proxy client certificate as its own user, with no groups, which a
# Role lets get Secrets in kube-system and nothing else.
law plan.join_server.user:
  {P.Plan.join_server_user() == "vk8s:join-server" : String}
law plan.join_server.daemon:
  {P.Plan.join_server() == P.Daemon{"join-server", "/usr/bin/vk8s-guest", ["join-server"]} : P.Step}
law plan.join_server.guest_bin:
  {P.Plan.join_server() == P.Daemon{"join-server", P.Plan.guest_bin(), ["join-server"]} : P.Step}
law plan.join_server.role:
  {P.Plan.join_server_role() ==
    P.Plan.kubectl_ensure(["create", "role", "vk8s:join-server", "--namespace=kube-system", "--verb=get", "--resource=secrets"]) : P.Step}
law plan.join_server.binding:
  {P.Plan.join_server_binding() ==
    P.Plan.kubectl_ensure(["create", "rolebinding", "vk8s:join-server", "--namespace=kube-system", "--role=vk8s:join-server",
      "--user=vk8s:join-server"]) : P.Step}
law plan.control_plane.join_server:
  for c: P.Cfg
  {List.drop(&2, P.Step, P.Plan.control_plane.k8s(c), 5n) ==
    [P.Daemon{"join-server", "/usr/bin/vk8s-guest", ["join-server"]}, P.Log{"vk8s: control plane up"}] : +List<P.Step>}

# Proposed: the opt-in open-format snapshot (docs/ref/snapshot-decisions.md
# D9-D13; command lines from tests/snapshot_store_spike.sh and vcluster
# restoreclient.go). The share's snapshot dir is
# /var/lib/vk8s-host/snapshot.
#
# The request snapshot-export dumps the store into snapshot/export
# (written to export.tmp, then renamed). Embedded etcd: etcdctl snapshot
# save with the apiserver's etcd client pair.
law plan.request.snapshot_export.etcd:
  {P.Plan.request("snapshot-export", P.Plan.default_cfg("demo", 12000, True{}), "/o") ==
    [ P.Run{"/bin/busybox", ["rm", "-rf", "/var/lib/vk8s-host/snapshot/export", "/var/lib/vk8s-host/snapshot/export.tmp"]},
      P.Run{"/bin/busybox", ["mkdir", "-p", "/var/lib/vk8s-host/snapshot/export.tmp"]},
      P.Run{"/var/lib/vcluster/bin/etcdctl", ["--endpoints", "https://127.0.0.1:2379",
        "--cacert", "/var/lib/vcluster/pki/etcd/ca.crt",
        "--cert", "/var/lib/vcluster/pki/apiserver-etcd-client.crt",
        "--key", "/var/lib/vcluster/pki/apiserver-etcd-client.key",
        "snapshot", "save", "/var/lib/vk8s-host/snapshot/export.tmp/db"]},
      P.Run{"/bin/busybox", ["mv", "/var/lib/vk8s-host/snapshot/export.tmp", "/var/lib/vk8s-host/snapshot/export"]} ] : +List<P.Step>}

# kine on SQLite: the count-only get gives the archive's revision
# (vcluster currentRevision), then pages of 1000 at one revision
# (vcluster listStream), each page's -w json output in its own file.
law plan.request.snapshot_export.kine:
  {P.Plan.request("snapshot-export", P.Plan.default_cfg("demo", 12000, False{}), "/o") ==
    [ P.Run{"/bin/busybox", ["rm", "-rf", "/var/lib/vk8s-host/snapshot/export", "/var/lib/vk8s-host/snapshot/export.tmp"]},
      P.Run{"/bin/busybox", ["mkdir", "-p", "/var/lib/vk8s-host/snapshot/export.tmp"]},
      P.Run{"/bin/busybox", ["sh", "-c", P.Plan.kine_dump_script()]},
      P.Run{"/bin/busybox", ["mv", "/var/lib/vk8s-host/snapshot/export.tmp", "/var/lib/vk8s-host/snapshot/export"]} ] : +List<P.Step>}

law plan.kine_dump_script:
  {P.Plan.kine_dump_script() ==
    "set -e; d=/var/lib/vk8s-host/snapshot/export.tmp; c() { /var/lib/vcluster/bin/etcdctl --endpoints unix:///var/lib/vcluster/kine.sock \"$@\"; }; rv() { sed -n 's/.*\"revision\":\\([0-9]*\\).*/\\1/p' \"$1\"; }; c get / --prefix --count-only -w json > $d/count.json; rv $d/count.json > $d/revision; [ -s $d/revision ]; n=1; c get / 0 --limit 1000 -w json > $d/page-1.json; r=$(rv $d/page-1.json); [ -n \"$r\" ]; while grep -q '\"more\":true' $d/page-$n.json; do k=$(grep -o '\"key\":\"[^\"]*\"' $d/page-$n.json | tail -n 1 | cut -d '\"' -f 4 | base64 -d); n=$((n+1)); c get \"$k\" 0 --limit 1000 --rev \"$r\" -w json > $d/page-$n.json; done; echo $n > $d/pages" : String}

# Only the exact action name has steps (plan.request.unknown stays).
law plan.request.snapshot_export.unsafe:
  {List.length(&2, P.Step, P.Plan.request("snapshot-export; rm -rf /", P.Plan.default_cfg("demo", 12000, False{}), "/o")) == 0n : Nat}

# Classic mode has no open-format snapshot (D4): its snapshot actions
# have no steps; standalone requests are Plan.request's.
law plan.request_mode.classic_snapshot:
  {List.length(&2, P.Step, P.Plan.request_mode(True{}, "snapshot-export", P.Plan.default_cfg("demo", 12000, False{}), "/o")) == 0n : Nat}
law plan.request_mode.classic_other:
  {List.length(&2, P.Step, P.Plan.request_mode(True{}, "certs-check", P.Plan.default_cfg("demo", 12000, False{}), "/o")) == 2n : Nat}
law plan.request_mode.standalone:
  for a: String
  for c: P.Cfg
  for o: String
  {P.Plan.request_mode(False{}, a, c, o) == P.Plan.request(a, c, o) : +List<P.Step>}

# A boot without the restore marker (share/snapshot/restore) is the boot.
law plan.boot_restore.none:
  for c: P.Cfg
  {P.Plan.boot_restore(c, False{}) == P.Plan.boot(c) : +List<P.Step>}

# With the marker, embedded etcd: etcdutl snapshot restore into the new
# data dir before etcd starts (vcluster restoreclient.go: InitialClusterToken
# vcluster, RevisionBump snapshotRestoreBumpRevision(0, snapshot, 1000) =
# 1000, MarkCompacted; the member name and loopback peer of Plan.etcd_args),
# then the marker and the database leave the share.
law plan.restore_store.etcd:
  for k8s: +List<P.Step>
  {P.Plan.restore_store(True{}, "demo2", k8s) ==
    Con{P.Log{"vk8s: restoring etcd from the snapshot"},
    Con{P.Run{"/var/lib/vcluster/bin/etcdutl", ["snapshot", "restore", "/var/lib/vk8s-host/snapshot/db",
      "--name", "demo2", "--data-dir", "/var/lib/vcluster/etcd",
      "--initial-cluster", "demo2=https://127.0.0.1:2380",
      "--initial-cluster-token", "vcluster",
      "--initial-advertise-peer-urls", "https://127.0.0.1:2380",
      "--bump-revision", "1000", "--mark-compacted"]},
    Con{P.Run{"/bin/busybox", ["rm", "-f", "/var/lib/vk8s-host/snapshot/restore", "/var/lib/vk8s-host/snapshot/db"]},
    List.append(&2, P.Step, P.Plan.store(True{}, "demo2"), k8s)}}} : +List<P.Step>}

# kine: after kine starts and before the API server, each put of
# share/snapshot/puts through vcluster's txn create (mod = 0, put), then
# a compaction at the last put's revision (restoreKeyValueSnapshot).
law plan.restore_store.kine:
  for k8s: +List<P.Step>
  {P.Plan.restore_store(False{}, "demo2", k8s) ==
    Con{P.Daemon{"kine", "/var/lib/vcluster/bin/kine", P.Plan.kine_args()},
    Con{P.WaitFile{"/var/lib/vcluster/kine.sock", 30000},
    Con{P.Log{"vk8s: restoring kine from the snapshot"},
    Con{P.Run{"/bin/busybox", ["sh", "-c", P.Plan.kine_puts_script()]},
    Con{P.Run{"/bin/busybox", ["rm", "-f", "/var/lib/vk8s-host/snapshot/restore", "/var/lib/vk8s-host/snapshot/puts"]},
    k8s}}}}} : +List<P.Step>}

law plan.kine_puts_script:
  {P.Plan.kine_puts_script() ==
    "set -e; c() { /var/lib/vcluster/bin/etcdctl --endpoints unix:///var/lib/vcluster/kine.sock \"$@\"; }; r=; while IFS= read -r k && IFS= read -r v; do printf 'mod(\"%s\") = \"0\"\\n\\nput %s %s\\n\\n\\n' \"$k\" \"$k\" \"$v\" | c txn -w json > /tmp/vk8s-put.json; grep -q '\"succeeded\":true' /tmp/vk8s-put.json || { echo \"vk8s: restore: create of $k failed\" >&2; cat /tmp/vk8s-put.json >&2; exit 1; }; r=$(sed -n 's/.*\"revision\":\\([0-9]*\\).*/\\1/p' /tmp/vk8s-put.json); done < /var/lib/vk8s-host/snapshot/puts; [ -z \"$r\" ] || c compaction \"$r\" || echo \"vk8s: restore: the store refused compaction at revision $r\"" : String}

# Proposed: disk give-back (vk8s design, docs/STATUS.md section 7; vcluster
# leaves trimming to the host it runs on). bend-vmm punches holes in a
# disk image for what the guest discards. PID 1 trims the data disk with
# busybox fstrim every 10 min (600 ticks of 1 s), in the background,
# on every VM (control plane, worker, image cache); the data disk mounts
# without -o discard, so a delete costs no discard of its own.
law plan.fstrim:
  {P.Plan.fstrim() == P.Spawn{"fstrim", "/bin/busybox", ["fstrim", "-v", "/var/lib/vcluster"]} : P.Step}
law plan.fstrim_every_ticks:
  {P.Plan.fstrim_every_ticks() == 600 : U32}
law plan.fstrim_due.period:
  {P.Plan.fstrim_due(600) == True{} : Bool}
law plan.fstrim_due.twice:
  {P.Plan.fstrim_due(1200) == True{} : Bool}
law plan.fstrim_due.between:
  {P.Plan.fstrim_due(599) == False{} : Bool}
law plan.fstrim_due.first_tick:
  {P.Plan.fstrim_due(1) == False{} : Bool}
law plan.disks.no_online_discard:
  {P.Plan.disks() == [P.Mount{"ext4", "/dev/vdb", "/var/lib/vcluster", "rw"}, P.Mount{"ext4", "/dev/vda", "/var/lib/vcluster/bin", "ro"}] : +List<P.Step>}

# Proposed: kubelet removes an image that no container used for 1 h
# (KubeletConfiguration imageMaximumGCAge; vk8s design, docs/STATUS.md
# section 7). vcluster keeps kubelet's defaults, which remove images only
# above 85 % disk use, and a 16 GiB sparse data disk seldom gets there.
law plan.image_gc:
  {P.Plan.image_gc() == "imageMaximumGCAge: 1h\n" : String}
# Proposed: the disks every role mounts (vk8s design, docs/DESIGN.md
# "Guest image"). Stage 0 (scripts/guest/stage0.sh) mounts /dev/vda, the
# assets disk, read-only at /assets before PID 1 starts, since PID 1, glibc
# and the late kernel modules live on it. PID 1 mounts the same disk
# read-only again at the data dir's bin/; both mounts are read-only, so
# they share one superblock.
law plan.disks:
  {P.Plan.disks() ==
    [ P.Mount{"ext4", "/dev/vdb", "/var/lib/vcluster", "rw"},
      P.Mount{"ext4", "/dev/vda", "/var/lib/vcluster/bin", "ro"} ] : +List<P.Step>}
# Proposed: memory give-back (vk8s design, docs/ref/footprint-decisions.md
# M2). Every 30 ticks (30 s) PID 1 reclaims page cache through the root
# cgroup's memory.reclaim (file pages only, swappiness=0), only when less
# than 10% of the vCPU time in that window was busy (iowait is busy), down
# to a 64 MiB floor, and not for less than 16 MiB.
# Amended 2026-11-15 (idle CPU trim the user approved): only inactive file
# pages count (was Active + Inactive). Reclaiming hot file pages made an
# idle control plane re-read ~3,500 pages a second (workingset_refault_file)
# and cost it ~3 points of host CPU, a worker ~0.75. A refault guard backs
# off for 20 runs (10 min) after a run that saw over 2560 refaulted file
# pages (10 MiB) since the last one. Amended again 2026-11-16: with the
# guard in place, active file pages count too (Active + Inactive): an idle
# worker held 311 MB of active file cache it never re-read (preloaded
# image tars read at boot) while refaulting only 571 pages. The back-off is
# 120 runs (1 h): the first reclaim evicts the cold cache, and a later one
# only drops a hot set that is read straight back (20 runs cost a worker
# ~1 point of host CPU).
law plan.reclaim_every_ticks:
  {P.Plan.reclaim_every_ticks() == 30 : U32}
law plan.idle_busy_percent:
  {P.Plan.idle_busy_percent() == 10 : U32}
law plan.cache_keep_kib:
  {P.Plan.cache_keep_kib() == 65536 : U32}
law plan.reclaim_min_kib:
  {P.Plan.reclaim_min_kib() == 16384 : U32}
law plan.idle_reclaim:
  {P.Plan.idle_reclaim() == P.Run{"/bin/busybox", ["sh", "-c",
    "set -- $(head -n 1 /proc/stat); t=$(($2+$3+$4+$5+$6+$7+$8+$9)); i=$5; { read pt pi < /run/vk8s-cpu; } 2>/dev/null || { pt=0; pi=0; }; echo \"$t $i\" > /run/vk8s-cpu; dt=$((t-pt)); b=$((dt-i+pi)); [ $pt -gt 0 ] && [ $dt -gt 0 ] && [ $((b*100)) -lt $((dt*10)) ] || exit 0; r=$(awk '/^workingset_refault_file / { print $2 }' /proc/vmstat); { read pr pc < /run/vk8s-reclaim; } 2>/dev/null || { pr=$r; pc=0; }; [ $((r-pr)) -gt 2560 ] && pc=120; if [ $pc -gt 0 ]; then echo \"$r $((pc-1))\" > /run/vk8s-reclaim; exit 0; fi; echo \"$r 0\" > /run/vk8s-reclaim; k=$(awk '/^(Active|Inactive)\\(file\\):/ { s += $2 } END { print s - 65536 }' /proc/meminfo); [ \"$k\" -ge 16384 ] || exit 0; { echo \"${k}K swappiness=0\" > /sys/fs/cgroup/memory.reclaim; } 2>/dev/null; true"]} : P.Step}
# Proposed: the request snapshot-dump supersedes snapshot-export
# (docs/ref/snapshot-decisions.md D16). etcdctl 3.5 refuses
# --count-only unless the output is -w fields ("--count-only is only for
# `--write-out=fields`"), so the kine_dump_script above exits at its
# first get and leaves no revision. snapshot-dump keeps vcluster's
# count-only read of the current revision (pkg/etcd/client.go
# currentRevision: Get "/" WithPrefix WithCountOnly, the header's
# revision) through -w fields, whose header line is "Revision" : N; the
# pages stay those of snapshot-export. snapshot-export keeps its steps.
law plan.request.snapshot_dump.etcd:
  {P.Plan.request("snapshot-dump", P.Plan.default_cfg("demo", 12000, True{}), "/o") ==
    [ P.Run{"/bin/busybox", ["rm", "-rf", "/var/lib/vk8s-host/snapshot/export", "/var/lib/vk8s-host/snapshot/export.tmp"]},
      P.Run{"/bin/busybox", ["mkdir", "-p", "/var/lib/vk8s-host/snapshot/export.tmp"]},
      P.Run{"/var/lib/vcluster/bin/etcdctl", ["--endpoints", "https://127.0.0.1:2379",
        "--cacert", "/var/lib/vcluster/pki/etcd/ca.crt",
        "--cert", "/var/lib/vcluster/pki/apiserver-etcd-client.crt",
        "--key", "/var/lib/vcluster/pki/apiserver-etcd-client.key",
        "snapshot", "save", "/var/lib/vk8s-host/snapshot/export.tmp/db"]},
      P.Run{"/bin/busybox", ["mv", "/var/lib/vk8s-host/snapshot/export.tmp", "/var/lib/vk8s-host/snapshot/export"]} ] : +List<P.Step>}
law plan.request.snapshot_dump.kine:
  {P.Plan.request("snapshot-dump", P.Plan.default_cfg("demo", 12000, False{}), "/o") ==
    [ P.Run{"/bin/busybox", ["rm", "-rf", "/var/lib/vk8s-host/snapshot/export", "/var/lib/vk8s-host/snapshot/export.tmp"]},
      P.Run{"/bin/busybox", ["mkdir", "-p", "/var/lib/vk8s-host/snapshot/export.tmp"]},
      P.Run{"/bin/busybox", ["sh", "-c", P.Plan.kine_dump_script.v2()]},
      P.Run{"/bin/busybox", ["mv", "/var/lib/vk8s-host/snapshot/export.tmp", "/var/lib/vk8s-host/snapshot/export"]} ] : +List<P.Step>}
law plan.kine_dump_script.v2:
  {P.Plan.kine_dump_script.v2() ==
    "set -e; d=/var/lib/vk8s-host/snapshot/export.tmp; c() { /var/lib/vcluster/bin/etcdctl --endpoints unix:///var/lib/vcluster/kine.sock \"$@\"; }; rv() { sed -n 's/.*\"revision\":\\([0-9]*\\).*/\\1/p' \"$1\"; }; c get / --prefix --count-only -w fields > $d/count.txt; sed -n 's/^\"Revision\" : \\([0-9]*\\).*/\\1/p' $d/count.txt > $d/revision; [ -s $d/revision ]; n=1; c get / 0 --limit 1000 -w json > $d/page-1.json; r=$(rv $d/page-1.json); [ -n \"$r\" ]; while grep -q '\"more\":true' $d/page-$n.json; do k=$(grep -o '\"key\":\"[^\"]*\"' $d/page-$n.json | tail -n 1 | cut -d '\"' -f 4 | base64 -d); n=$((n+1)); c get \"$k\" 0 --limit 1000 --rev \"$r\" -w json > $d/page-$n.json; done; echo $n > $d/pages" : String}
law plan.request.snapshot_dump.unsafe:
  {List.length(&2, P.Step, P.Plan.request("snapshot-dump; rm -rf /", P.Plan.default_cfg("demo", 12000, False{}), "/o")) == 0n : Nat}
law plan.request_mode.classic_snapshot_dump:
  {List.length(&2, P.Step, P.Plan.request_mode(True{}, "snapshot-dump", P.Plan.default_cfg("demo", 12000, False{}), "/o")) == 0n : Nat}

# Proposed: free page reporting at 16 KiB blocks, the Mac's page size
# (vk8s design, docs/ref/footprint-decisions.md M3; GOAL section 7 memory
# give-back). Amended 2026-11-15 with the user's approval (was "4", 64 KiB)
# when bend-vmm 3aa445a began releasing 16 KiB blocks.
law plan.page_reporting_order:
  {P.Plan.page_reporting_order() == "2" : String}
law plan.sysctls.page_reporting:
  {List.drop(&2, P.Step, P.Plan.sysctls(), 4n) ==
    [P.Write{"/sys/module/page_reporting/parameters/page_reporting_order", "2"}] : +List<P.Step>}

# Proposed: idle memory compaction (vk8s design, docs/ref/footprint-decisions.md
# M4; bend-vmm releases only whole 64 KiB blocks). Every 600 ticks (10 min)
# PID 1 compacts memory when the node was idle over that window.
law plan.compact_every_ticks:
  {P.Plan.compact_every_ticks() == 600 : U32}
law plan.idle_compact:
  {P.Plan.idle_compact() == P.Run{"/bin/busybox", ["sh", "-c",
    "set -- $(head -n 1 /proc/stat); t=$(($2+$3+$4+$5+$6+$7+$8+$9)); i=$5; { read pt pi < /run/vk8s-cpu-compact; } 2>/dev/null || { pt=0; pi=0; }; echo \"$t $i\" > /run/vk8s-cpu-compact; dt=$((t-pt)); b=$((dt-i+pi)); [ $pt -gt 0 ] && [ $dt -gt 0 ] && [ $((b*100)) -lt $((dt*10)) ] || exit 0; { echo 1 > /proc/sys/vm/compact_memory; } 2>/dev/null; true"]} : P.Step}

# Proposed: the read-only assets disk is squashfs (zstd), not ext4 (vk8s
# design, docs/GOAL.md section 9; docs/ref/footprint-decisions.md A1).
# plan.disks pins "ext4" for /dev/vda and stays as written, so the boot
# plans mount the disks of Plan.disks.v2: the same data disk, and the
# assets disk as squashfs, read-only, at the data dir's bin/ (stage 0
# mounts it at /assets first; both mounts share one superblock). The data
# disk stays ext4, without -o discard (plan.disks.no_online_discard).
law plan.disks.v2:
  {P.Plan.disks.v2() ==
    [ P.Mount{"ext4", "/dev/vdb", "/var/lib/vcluster", "rw"},
      P.Mount{"squashfs", "/dev/vda", "/var/lib/vcluster/bin", "ro"} ] : +List<P.Step>}
# The image cache VM mounts them right after its base system (11 steps),
# its modules and its network (7 steps).
law plan.cache.disks_v2:
  {List.take(&2, P.Step, List.drop(&2, P.Step, P.Plan.cache(), 19n), 2n) == P.Plan.disks.v2() : +List<P.Step>}

# Proposed: per-role asset sets (vk8s design, docs/GOAL.md section 9;
# docs/ref/footprint-decisions.md D1). /dev/vda stays the base disk that
# stage 0 mounts at /assets (PID 1, glibc, the modules); /dev/vdb stays
# the data disk; /dev/vdc onward are the role's sets in the order the host
# attached them (VK8S_SETS). PID 1 mounts each read-only at /sets/<set>
# (the root is stage 0's tmpfs; /assets is read-only) and joins them at
# the data dir's bin/ with a read-only overlay of lower directories only,
# so every path under bin/ stays as it was. One set needs no overlay: its
# disk is mounted again at bin/ (both read-only mounts share a superblock).
law plan.disks.v3.standalone:
  {P.Plan.disks.v3(["node", "control-plane", "images"]) ==
    [ P.Mount{"ext4", "/dev/vdb", "/var/lib/vcluster", "rw"},
      P.Mount{"squashfs", "/dev/vdc", "/sets/node", "ro"},
      P.Mount{"squashfs", "/dev/vdd", "/sets/control-plane", "ro"},
      P.Mount{"squashfs", "/dev/vde", "/sets/images", "ro"},
      P.Mount{"overlay", "overlay", "/var/lib/vcluster/bin", "ro,lowerdir=/sets/node:/sets/control-plane:/sets/images"} ] : +List<P.Step>}
law plan.disks.v3.one_set:
  {P.Plan.disks.v3(["cache"]) ==
    [ P.Mount{"ext4", "/dev/vdb", "/var/lib/vcluster", "rw"},
      P.Mount{"squashfs", "/dev/vdc", "/sets/cache", "ro"},
      P.Mount{"squashfs", "/dev/vdc", "/var/lib/vcluster/bin", "ro"} ] : +List<P.Step>}
# The boot plans keep Plan.disks.v2 (their laws pin it); PID 1 swaps the
# assets disk's bin/ mount for the sets' mounts when the host names sets,
# and boots the plan as it is when it names none (an older, single
# assets.img).
law plan.with_sets.none:
  for p: +List<P.Step>
  {P.Plan.with_sets([], p) == p : +List<P.Step>}
law plan.with_sets.cache:
  {P.Plan.with_sets(["cache"], P.Plan.cache()) ==
    List.append(&2, P.Step, List.take(&2, P.Step, P.Plan.cache(), 19n),
      List.append(&2, P.Step, P.Plan.disks.v3(["cache"]), List.drop(&2, P.Step, P.Plan.cache(), 21n))) : +List<P.Step>}
law plan.with_sets.worker_disks:
  {List.take(&2, P.Step, List.drop(&2, P.Step, P.Plan.with_sets(["node"], P.Plan.worker(P.WCfg{"w1", "10.10.0.3", "t"})), 26n), 3n)
    == P.Plan.disks.v3(["node"]) : +List<P.Step>}

# Proposed: the platform of `ctr images import` per arch (containerd's
# platform strings: os/arch with Go's GOARCH, linux/arm64 and
# linux/amd64). The preload and node load-image steps name linux/arm64.
# PID 1 passes each Run's arguments through Plan.arch_args with its arch
# (VK8S_ARCH on the kernel command line, laws/cli.bend cli.arch_flags.*),
# so an amd64 guest imports linux/amd64. Without VK8S_ARCH (arm64 hosts)
# nothing changes.
law plan.platform.amd64:
  {P.Plan.platform("amd64") == "linux/amd64" : String}
law plan.platform.arm64:
  {P.Plan.platform("arm64") == "linux/arm64" : String}
law plan.platform.unset:
  {P.Plan.platform("") == "linux/arm64" : String}
law plan.arch_args.amd64:
  {P.Plan.arch_args("amd64", ["sh", "-c", "ctr -n k8s.io images import --platform linux/arm64 -; r=$?"])
    == ["sh", "-c", "ctr -n k8s.io images import --platform linux/amd64 -; r=$?"] : +List<String>}
law plan.arch_args.arm64:
  {P.Plan.arch_args("arm64", ["sh", "-c", "ctr images import --platform linux/arm64 -"])
    == ["sh", "-c", "ctr images import --platform linux/arm64 -"] : +List<String>}
law plan.arch_args.unset:
  {P.Plan.arch_args("", ["sh", "-c", "ctr images import --platform linux/arm64 -"])
    == ["sh", "-c", "ctr images import --platform linux/arm64 -"] : +List<String>}
# Proposed: the request sync flushes the guest's page cache to its disks.
# vk8s snapshot (VM format) sends it before it pauses the VMs and copies
# the data disk: kine's SQLite runs in WAL mode, where go-sqlite3's
# default synchronous=NORMAL does not fsync a commit, so without it the
# copy can miss the last writes (vind's docker pause needs no flush: the
# container's volume is the host's file system).
law plan.request.sync:
  {P.Plan.request("sync", P.Plan.default_cfg("demo", 12000, False{}), "/o")
    == [P.Run{"/bin/busybox", ["sync"]}] : +List<P.Step>}
# Proposed: an opt-in gVisor RuntimeClass (vk8s design, docs/GOAL.md
# section 8; docs/ref/explore-linux-hosts.md Phase 7). vcluster has no
# gVisor; the values come from containerd's and gVisor's docs. containerd
# 2.x config v3 (containerd docs/cri/config.md, "Runtime classes"):
# runtime_type io.containerd.runsc.v1 under
# plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.<handler>,
# runtime_path the shim's absolute path ("containerd will ignore runtime
# name field when resolving shim location"), and the generic
# runtimeoptions/v1 options TypeUrl and ConfigPath (gVisor
# g3doc/user_guide/containerd/configuration.md). The shim's file names
# runsc (binary_name, gVisor pkg/shim/v1/runsc/options.go) and passes
# [runsc_config] as runsc flags: the systrap platform
# (g3doc/user_guide/platforms.md), which needs no nested virtualization.
law plan.containerd_runsc:
  {P.Plan.containerd_runsc() ==
    "[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runsc]\n"
    ++ "  runtime_type = \"io.containerd.runsc.v1\"\n"
    ++ "  runtime_path = \"/var/lib/vcluster/bin/containerd-shim-runsc-v1\"\n"
    ++ "  [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runsc.options]\n"
    ++ "    TypeUrl = \"io.containerd.runsc.v1.options\"\n"
    ++ "    ConfigPath = \"/etc/containerd/runsc.toml\"\n" : String}
law plan.containerd_runsc.toml:
  {P.Plan.runsc_toml() ==
    "binary_name = \"/var/lib/vcluster/bin/runsc\"\n[runsc_config]\n  platform = \"systrap\"\n" : String}
# The node's containerd config is the runc one with the runsc runtime
# added. It names no default_runtime_name, so runc stays the default and
# gVisor is opt-in per pod. String.contains over the whole config runs
# the verdict kernel out of fuel, so tests/gvisor_boot.bend checks that
# part.
law plan.containerd_runsc.config:
  {P.Plan.containerd_config.v2() == P.Plan.containerd_config() ++ P.Plan.containerd_runsc() : String}
# Every node writes both files before containerd starts, after the
# mirrors' hosts.toml (4).
law plan.runtime.runsc:
  {List.take(&2, P.Step, List.drop(&2, P.Step, P.Plan.runtime(), 4n), 2n) ==
    [ P.Write{"/etc/containerd/config.toml", P.Plan.containerd_config.v2()},
      P.Write{"/etc/containerd/runsc.toml", P.Plan.runsc_toml()} ] : +List<P.Step>}
# The RuntimeClass (gVisor g3doc/user_guide/containerd/quick_start.md,
# "Set up the Kubernetes RuntimeClass"): pods that name runtimeClassName
# gvisor run on the handler runsc.
law plan.runtimeclass_gvisor:
  {P.Plan.runtimeclass_gvisor() ==
    "apiVersion: node.k8s.io/v1\nkind: RuntimeClass\nmetadata:\n  name: gvisor\nhandler: runsc\n" : String}
# The control-plane node applies it at boot, after CoreDNS (runtime 11
# steps, then 16 of the node's).
law plan.node.runtimeclass_gvisor:
  {List.take(&2, P.Step, List.drop(&2, P.Step, P.Plan.node(P.Plan.default_cfg("demo", 6443, False{})), 27n), 2n) ==
    [ P.Write{"/etc/vk8s/runtimeclass-gvisor.yaml", P.Plan.runtimeclass_gvisor()},
      P.Plan.kubectl(["apply", "-f", "/etc/vk8s/runtimeclass-gvisor.yaml"]) ] : +List<P.Step>}

# Proposed: PID 1's chores, v2 (vk8s design; vcluster has no PID 1;
# docs/ref/review-direct-commits-main.md F1-F3, F9, F11). The laws
# plan.idle_reclaim and plan.idle_compact above keep pinning the old
# scripts; PID 1 runs these defs instead.
#
# The tick is 1 s, and every period in ticks is pinned in milliseconds
# through it (F9): the clock every 10 s, log trim every 60 s, reclaim
# every 30 s, fstrim and compaction every 10 min.
law plan.tick_ms:
  {P.Plan.tick_ms() == 1000 : U32}
law plan.tick_periods:
  {[ U32.mul(P.Plan.clock_every_ticks(), P.Plan.tick_ms()),
     U32.mul(P.Plan.trim_every_ticks(), P.Plan.tick_ms()),
     U32.mul(P.Plan.reclaim_every_ticks(), P.Plan.tick_ms()),
     U32.mul(P.Plan.fstrim_every_ticks(), P.Plan.tick_ms()),
     U32.mul(P.Plan.compact_every_ticks(), P.Plan.tick_ms()) ] == [10000, 60000, 30000, 600000, 600000] : List<&2, U32>}
# Reclaim is due on tick 15 of every 30 and compaction on tick 300 of
# every 600, never on fstrim's tick (0 of 600) nor on each other's (F3).
# PID 1 counts ticks from 1, so the first compaction is 5 min after boot
# (F11; it was 20 min: the old script only took its baseline at 10 min).
law plan.reclaim_due:
  {[P.Plan.reclaim_due(0), P.Plan.reclaim_due(15), P.Plan.reclaim_due(30), P.Plan.reclaim_due(45), P.Plan.reclaim_due(600), P.Plan.reclaim_due(615)]
    == [False{}, True{}, False{}, True{}, False{}, True{}] : List<&2, Bool>}
law plan.compact_due:
  {[P.Plan.compact_due(0), P.Plan.compact_due(300), P.Plan.compact_due(600), P.Plan.compact_due(900), P.Plan.compact_due(1200)]
    == [False{}, True{}, False{}, True{}, False{}] : List<&2, Bool>}
law plan.compact_due.first:
  {[P.Plan.compact_due(1), P.Plan.compact_due(299), P.Plan.compact_due(301)] == [False{}, False{}, False{}] : List<&2, Bool>}
# /proc/stat's first line: the total of user..steal and idle (the old
# scripts' $2..$9 and $5).
law plan.gauge:
  {P.Plan.gauge("cpu  10 20 30 400 50 6 7 8 9 10\ncpu0 1 2 3 4 5 6 7 8 0 0\n") == P.Gauge{True{}, 531, 400} : P.Gauge}
law plan.gauge.garbled:
  {P.Plan.gauge("cpu 1 2 x 4 5 6 7 8\n") == P.Gauge{False{}, 0, 0} : P.Gauge}
law plan.gauge.short:
  {P.Plan.gauge("cpu 1 2 3 4\n") == P.Gauge{False{}, 0, 0} : P.Gauge}
# Idle: less than 10% of the window busy (iowait is busy), as the script's
# [ $((b*100)) -lt $((dt*10)) ]; a window without two samples is not idle.
law plan.idle_between.idle:
  {P.Plan.idle_between(P.Gauge{True{}, 1000, 900}, P.Gauge{True{}, 4000, 3800}) == True{} : Bool}
law plan.idle_between.busy:
  {P.Plan.idle_between(P.Gauge{True{}, 1000, 900}, P.Gauge{True{}, 4000, 3000}) == False{} : Bool}
law plan.idle_between.edge:
  {P.Plan.idle_between(P.Gauge{True{}, 1000, 900}, P.Gauge{True{}, 4000, 3600}) == False{} : Bool}
law plan.idle_between.unseen:
  {P.Plan.idle_between(P.Gauge{False{}, 0, 0}, P.Gauge{True{}, 4000, 3800}) == False{} : Bool}
law plan.idle_between.wrap:
  {P.Plan.idle_between(P.Gauge{True{}, 4294967000, 4294966900}, P.Gauge{True{}, 2704, 2504}) == True{} : Bool}
law plan.refaults:
  {P.Plan.refaults("workingset_refault_anon 5\nworkingset_refault_file 2600\n") == Some{2600} : Maybe<&2, U32>}
law plan.refaults.missing:
  {P.Plan.refaults("pgfault 9\n") == None{} : Maybe<&2, U32>}
law plan.refaults.garbled:
  {P.Plan.refaults("workingset_refault_file x\n") == None{} : Maybe<&2, U32>}
law plan.file_kib:
  {P.Plan.file_kib("Active(file):     100000 kB\nInactive(file):    50000 kB\n") == Some{150000} : Maybe<&2, U32>}
law plan.file_kib.missing:
  {P.Plan.file_kib("Active(file):     100000 kB\n") == None{} : Maybe<&2, U32>}
# A reclaim run: idle, a refault baseline, no back-off, refaults under
# 2560 pages: Active(file) + Inactive(file) above the 64 MiB floor goes,
# written to the root cgroup's memory.reclaim in the background.
law plan.reclaim_turn.reclaim:
  {P.Plan.reclaim_turn(P.Guard{P.Gauge{True{}, 1000, 900}, True{}, 9000, 0, False{}}, P.Gauge{True{}, 4000, 3800}, Some{9100}, Some{200000})
    == P.Turn{P.Guard{P.Gauge{True{}, 4000, 3800}, True{}, 9100, 0, False{}},
         P.Poke{"/sys/fs/cgroup/memory.reclaim", "134464K swappiness=0"}} : P.Turn}
# F1: a busy run moves the refault baseline and counts the back-off down.
law plan.reclaim_turn.busy_counts:
  {P.Plan.reclaim_turn(P.Guard{P.Gauge{True{}, 1000, 900}, True{}, 9000, 5, False{}}, P.Gauge{True{}, 4000, 3000}, Some{9100}, Some{200000})
    == P.Turn{P.Guard{P.Gauge{True{}, 4000, 3000}, True{}, 9100, 4, False{}}, P.Rest{}} : P.Turn}
# F1: refaults over 2560 pages in a busy window start the back-off then,
# and the next idle run is measured from the new baseline.
law plan.reclaim_turn.busy_spike:
  {P.Plan.reclaim_turn(P.Guard{P.Gauge{True{}, 1000, 900}, True{}, 9000, 0, False{}}, P.Gauge{True{}, 4000, 3000}, Some{99000}, Some{200000})
    == P.Turn{P.Guard{P.Gauge{True{}, 4000, 3000}, True{}, 99000, 120, False{}}, P.Rest{}} : P.Turn}
law plan.reclaim_turn.idle_spike:
  {P.Plan.reclaim_turn(P.Guard{P.Gauge{True{}, 1000, 900}, True{}, 9000, 0, False{}}, P.Gauge{True{}, 4000, 3800}, Some{11561}, Some{200000})
    == P.Turn{P.Guard{P.Gauge{True{}, 4000, 3800}, True{}, 11561, 120, False{}}, P.Rest{}} : P.Turn}
law plan.reclaim_turn.under_spike:
  {P.Plan.reclaim_turn(P.Guard{P.Gauge{True{}, 1000, 900}, True{}, 9000, 0, False{}}, P.Gauge{True{}, 4000, 3800}, Some{11560}, Some{200000})
    == P.Turn{P.Guard{P.Gauge{True{}, 4000, 3800}, True{}, 11560, 0, False{}},
         P.Poke{"/sys/fs/cgroup/memory.reclaim", "134464K swappiness=0"}} : P.Turn}
# The last run of a back-off reclaims again (120 runs held back).
law plan.reclaim_turn.backoff_ends:
  {P.Plan.reclaim_turn(P.Guard{P.Gauge{True{}, 1000, 900}, True{}, 9000, 1, False{}}, P.Gauge{True{}, 4000, 3800}, Some{9100}, Some{200000})
    == P.Turn{P.Guard{P.Gauge{True{}, 4000, 3800}, True{}, 9100, 0, False{}},
         P.Poke{"/sys/fs/cgroup/memory.reclaim", "134464K swappiness=0"}} : P.Turn}
law plan.reclaim_turn.backoff_holds:
  {P.Plan.reclaim_turn(P.Guard{P.Gauge{True{}, 1000, 900}, True{}, 9000, 2, False{}}, P.Gauge{True{}, 4000, 3800}, Some{9100}, Some{200000})
    == P.Turn{P.Guard{P.Gauge{True{}, 4000, 3800}, True{}, 9100, 1, False{}}, P.Rest{}} : P.Turn}
# No refault baseline yet (the first run after boot): no reclaim.
law plan.reclaim_turn.first:
  {P.Plan.reclaim_turn(P.Plan.guard.init(), P.Gauge{True{}, 4000, 3800}, Some{9100}, Some{200000})
    == P.Turn{P.Guard{P.Gauge{True{}, 4000, 3800}, True{}, 9100, 0, False{}}, P.Rest{}} : P.Turn}
# F2: without workingset_refault_file nothing is reclaimed, the baseline
# is dropped, and PID 1 says why once.
law plan.reclaim_turn.blind:
  {P.Plan.reclaim_turn(P.Guard{P.Gauge{True{}, 1000, 900}, True{}, 9000, 3, False{}}, P.Gauge{True{}, 4000, 3800}, None{}, Some{200000})
    == P.Turn{P.Guard{P.Gauge{True{}, 4000, 3800}, False{}, 0, 3, True{}}, P.Note{P.Plan.reclaim_blind_note()}} : P.Turn}
law plan.reclaim_turn.blind_again:
  {P.Plan.reclaim_turn(P.Guard{P.Gauge{True{}, 1000, 900}, False{}, 0, 3, True{}}, P.Gauge{True{}, 4000, 3800}, None{}, Some{200000})
    == P.Turn{P.Guard{P.Gauge{True{}, 4000, 3800}, False{}, 0, 3, True{}}, P.Rest{}} : P.Turn}
# Under 16 MiB above the floor, or no /proc/meminfo figure: nothing.
law plan.reclaim_turn.small:
  {P.Plan.reclaim_turn(P.Guard{P.Gauge{True{}, 1000, 900}, True{}, 9000, 0, False{}}, P.Gauge{True{}, 4000, 3800}, Some{9100}, Some{81919})
    == P.Turn{P.Guard{P.Gauge{True{}, 4000, 3800}, True{}, 9100, 0, False{}}, P.Rest{}} : P.Turn}
law plan.reclaim_turn.min:
  {P.Plan.reclaim_turn(P.Guard{P.Gauge{True{}, 1000, 900}, True{}, 9000, 0, False{}}, P.Gauge{True{}, 4000, 3800}, Some{9100}, Some{81920})
    == P.Turn{P.Guard{P.Gauge{True{}, 4000, 3800}, True{}, 9100, 0, False{}},
         P.Poke{"/sys/fs/cgroup/memory.reclaim", "16384K swappiness=0"}} : P.Turn}
law plan.reclaim_turn.no_meminfo:
  {P.Plan.reclaim_turn(P.Guard{P.Gauge{True{}, 1000, 900}, True{}, 9000, 0, False{}}, P.Gauge{True{}, 4000, 3800}, Some{9100}, None{})
    == P.Turn{P.Guard{P.Gauge{True{}, 4000, 3800}, True{}, 9100, 0, False{}}, P.Rest{}} : P.Turn}
# The same run from the texts of the three /proc files.
law plan.reclaim_step:
  {P.Plan.reclaim_step(P.Guard{P.Gauge{True{}, 1000, 900}, True{}, 9000, 0, False{}}, "cpu  100 0 100 5800 0 0 0 0 0 0\n",
      "workingset_refault_file 9100\n", "Active(file): 150000 kB\nInactive(file): 50000 kB\n")
    == P.Turn{P.Guard{P.Gauge{True{}, 6000, 5800}, True{}, 9100, 0, False{}},
         P.Poke{"/sys/fs/cgroup/memory.reclaim", "134464K swappiness=0"}} : P.Turn}
# Compaction: writes 1 to compact_memory when the window was idle.
law plan.compact_turn.idle:
  {P.Plan.compact_turn(P.Gauge{True{}, 1000, 900}, P.Gauge{True{}, 4000, 3800}) == P.Poke{"/proc/sys/vm/compact_memory", "1"} : P.Chore}
law plan.compact_turn.busy:
  {P.Plan.compact_turn(P.Gauge{True{}, 1000, 900}, P.Gauge{True{}, 4000, 3000}) == P.Rest{} : P.Chore}
# The compaction window starts at boot; the reclaim guard starts empty.
law plan.mem_init:
  {P.Plan.mem_init("cpu  10 20 30 400 50 6 7 8 9 10\n") == P.Mem{P.Plan.guard.init(), P.Gauge{True{}, 531, 400}} : P.Mem}

# Proposed: idle tuning of the standalone control plane (vk8s design,
# docs/GOAL.md section 10; the upstream defaults each value changes are
# cited at Plan.controller_manager_idle, Plan.kubelet_idle and
# Plan.go_envs). vcluster runs with leader election and Go's defaults;
# these laid over its base lists as vcluster lays extraArgs
# (command.MergeArgs), so its base laws above stay.
# One control plane: leader election off for the controller manager and
# the scheduler; the TTL controller off (as vcluster's classic sets).
law plan.controller_manager_idle:
  {P.Plan.controller_manager_idle() ==
    ["--leader-elect=false", "--controllers=*,bootstrapsigner,tokencleaner,-ttl"] : +List<String>}
law plan.controller_manager.v2_merge:
  for c: P.Cfg
  {P.Plan.controller_manager_args.v2(c) ==
    A.Args.merge(P.Plan.controller_manager_args.base(c), P.Plan.controller_manager_idle()) : +List<String>}
law plan.controller_manager.v2:
  {P.Plan.controller_manager_args.v2(P.Plan.default_cfg("demo", 6443, False{})) ==
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
      "--cluster-signing-cert-file=/var/lib/vcluster/pki/server-ca.crt",
      "--cluster-signing-key-file=/var/lib/vcluster/pki/server-ca.key",
      "--allocate-node-cidrs=true",
      "--cluster-cidr=10.244.0.0/16",
      "--cloud-provider=external",
      "--leader-elect=false",
      "--controllers=*,bootstrapsigner,tokencleaner,-ttl" ] : +List<String>}
law plan.scheduler.v2:
  {P.Plan.scheduler_args.v2() ==
    [ "--authentication-kubeconfig=/var/lib/vcluster/pki/scheduler.conf",
      "--authorization-kubeconfig=/var/lib/vcluster/pki/scheduler.conf",
      "--bind-address=127.0.0.1",
      "--kubeconfig=/var/lib/vcluster/pki/scheduler.conf",
      "--leader-elect=false" ] : +List<String>}
# The standalone control plane runs them (Plan.boot and the restore boot
# share Plan.control_plane.k8s).
law plan.control_plane.idle:
  for c: P.Cfg
  {List.take(&2, P.Step, List.drop(&2, P.Step, P.Plan.control_plane.k8s(c), 3n), 2n) ==
    [ P.Daemon{"kube-controller-manager", "/var/lib/vcluster/bin/kube-controller-manager", P.Plan.controller_manager_args.v2(c)},
      P.Daemon{"kube-scheduler", "/var/lib/vcluster/bin/kube-scheduler", P.Plan.scheduler_args.v2()} ] : +List<P.Step>}
# The kubelet's cAdvisor housekeeping every 30 s instead of 10 s; sync,
# GC, node status and lease periods stay upstream's.
law plan.kubelet_idle:
  {P.Plan.kubelet_idle() == ["--housekeeping-interval=30s"] : +List<String>}
law plan.kubelet_args.v2:
  for c: P.Cfg
  {P.Plan.kubelet_args.v2(c) == List.append(&2, String, P.Plan.kubelet_args(c), P.Plan.kubelet_idle()) : +List<String>}
# Go runtime settings by daemon name; none for any other daemon.
law plan.go_env.apiserver:
  {P.Plan.go_env("kube-apiserver") == ["GOGC=50", "GOMEMLIMIT=640MiB"] : +List<String>}
law plan.go_env.controller_manager:
  {P.Plan.go_env("kube-controller-manager") == ["GOGC=50", "GOMEMLIMIT=256MiB"] : +List<String>}
law plan.go_env.scheduler:
  {P.Plan.go_env("kube-scheduler") == ["GOGC=50", "GOMEMLIMIT=128MiB"] : +List<String>}
law plan.go_env.kubelet:
  {P.Plan.go_env("kubelet") == ["GOGC=50", "GOMEMLIMIT=192MiB"] : +List<String>}
law plan.go_env.containerd:
  {P.Plan.go_env("containerd") == ["GOGC=50", "GOMEMLIMIT=128MiB"] : +List<String>}
law plan.go_env.kine:
  {P.Plan.go_env("kine") == ["GOGC=50", "GOMEMLIMIT=128MiB"] : +List<String>}
law plan.go_env.etcd:
  {P.Plan.go_env("etcd") == ["GOGC=50", "GOMEMLIMIT=256MiB"] : +List<String>}
law plan.go_env.other:
  {P.Plan.go_env("join-server") == [] : +List<String>}
# PID 1 starts a daemon with settings as `busybox env WORD... PROG ARGS...`
# and any other daemon as it is.
law plan.env_prog.none:
  for bb: String
  for prog: String
  {P.Plan.env_prog([], bb, prog) == prog : String}
law plan.env_prog.some:
  {P.Plan.env_prog(["GOGC=50"], "/bin/busybox", "/var/lib/vcluster/bin/kubelet") == "/bin/busybox" : String}
law plan.env_args.none:
  for prog: String
  for args: +List<String>
  {P.Plan.env_args([], prog, args) == args : +List<String>}
law plan.env_args.some:
  {P.Plan.env_args(["GOGC=50", "GOMEMLIMIT=192MiB"], "/var/lib/vcluster/bin/kubelet", ["--config=/c"]) ==
    ["env", "GOGC=50", "GOMEMLIMIT=192MiB", "/var/lib/vcluster/bin/kubelet", "--config=/c"] : +List<String>}
# Proposed: layer blobs discarded once unpacked (vk8s design, docs/GOAL.md
# section 10, interim step of shared image layers). The key and its
# table come from containerd v2.2.3 (the node set's containerd, loft-sh/
# kubernetes v1.36.6): internal/cri/config/config.go ImageConfig
# `toml:"discard_unpacked_layers"` and `toml:"use_local_image_pull"`,
# under plugins.'io.containerd.cri.v1.images' (docs/cri/config.md, config
# version 3). docs/cri/config.md: discard_unpacked_layers is not
# supported by the transfer service, and containerd 2.1+ falls back to
# the local pull when it is set, so the config names that pull.
law plan.containerd_images:
  {P.Plan.containerd_images() ==
    "[plugins.'io.containerd.cri.v1.images']\n  snapshotter = \"overlayfs\"\n"
    ++ "  discard_unpacked_layers = true\n  use_local_image_pull = true\n"
    ++ "  [plugins.'io.containerd.cri.v1.images'.pinned_images]\n    sandbox = \"registry.k8s.io/pause:3.10.2\"\n"
    ++ "  [plugins.'io.containerd.cri.v1.images'.registry]\n    config_path = \"/etc/containerd/certs.d\"\n" : String}
# Every node's containerd config (Plan.runtime writes it on the VM node,
# the container node and the host node: plan.runtime.runsc) carries that
# image section, after the root, state and socket.
law plan.containerd_config.images:
  {P.Plan.containerd_config() ==
    "version = 3\nroot = \"/var/lib/vcluster/containerd\"\nstate = \"/run/containerd\"\n"
    ++ "[grpc]\n  address = \"/run/containerd/containerd.sock\"\n"
    ++ P.Plan.containerd_images()
    ++ "[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc]\n  runtime_type = \"io.containerd.runc.v2\"\n"
    ++ "  [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]\n    SystemdCgroup = false\n    BinaryName = \"/var/lib/vcluster/bin/runc\"\n"
    ++ "[plugins.'io.containerd.cri.v1.runtime'.cni]\n  bin_dirs = [\"/opt/cni/bin\"]\n  conf_dir = \"/etc/cni/net.d\"\n" : String}
# Proposed: images that ctr imports (pause, the preloaded add-ons, node
# load-image) also drop their layer blobs once unpacked. containerd
# v2.2.3 cmd/ctr/commands/images/import.go: --discard-unpacked-layers
# ("Allow the garbage collector to clean layers up from the content
# store after unpacking") returns `"--discard-unpacked-layers" requires
# "--local" flag` without --local, so both flags come together.
law plan.imports.v2:
  {P.Plan.imports.v2() ==
    [ P.Run{"/var/lib/vcluster/bin/ctr", ["--address", "/run/containerd/containerd.sock", "-n", "k8s.io", "images", "import",
        "--local", "--discard-unpacked-layers", "/var/lib/vcluster/bin/pause-image.tar"]},
      P.Plan.bb(["sh", "-c", "for f in /var/lib/vcluster/bin/images/*.tar; do [ -f \"$f\" ] || continue; "
        ++ "/var/lib/vcluster/bin/ctr --address /run/containerd/containerd.sock -n k8s.io images import --local --discard-unpacked-layers --platform linux/arm64 \"$f\" >/dev/null || exit 1; done"]) ] : +List<P.Step>}
# Plan.runtime.v2 is Plan.runtime (4 mirror steps, 5 runtime steps, 2
# imports) with those two imports.
law plan.runtime.v2:
  {P.Plan.runtime.v2() == List.append(&2, P.Step, List.take(&2, P.Step, P.Plan.runtime(), 9n), P.Plan.imports.v2()) : +List<P.Step>}
law plan.image_load.v2:
  {P.Plan.image_load.go.v2(True{}, "img.tar") ==
    [ P.Plan.bb(["sh", "-c", "set -o pipefail; case '/var/lib/vk8s-host/images/img.tar' in *.gz) gunzip -c ;; *) cat ;; esac < '/var/lib/vk8s-host/images/img.tar'"
        ++ " | '/var/lib/vcluster/bin/ctr' --address /run/containerd/containerd.sock -n k8s.io images import --local --discard-unpacked-layers --platform linux/arm64 -; r=$?; rm -f '/var/lib/vk8s-host/images/img.tar'; exit $r"]) ] : +List<P.Step>}
law plan.request.image_load.v2:
  {P.Plan.request("image-load:img.tar", P.Plan.default_cfg("demo", 12000, False{}), "/o") == P.Plan.image_load.go.v2(True{}, "img.tar") : +List<P.Step>}
# Proposed: sleep when idle (src/cli/idle.bend; vk8s design, docs/GOAL.md
# section 10). Before the pause, kube-controller-manager is stopped
# (SIGSTOP), so it never acts on a lease that went stale while paused.
law plan.request.idle_sleep:
  {P.Plan.request("idle-sleep", P.Plan.default_cfg("demo", 6443, False{}), "") ==
    [ P.Log{"vk8s: idle; the controllers stop until the cluster wakes"},
      P.Run{"/bin/busybox", ["killall", "-STOP", "kube-controller-manager"]} ] : +List<P.Step>}
# After the resume, a VM sets its clock from the RTC (Plan.clock_sync)
# before kube-controller-manager is killed and the supervisor starts a
# fresh one, whose node lifecycle controller starts the grace period anew.
law plan.request.idle_wake_clock:
  {P.Plan.request("idle-wake-clock", P.Plan.default_cfg("demo", 6443, False{}), "") ==
    [ P.Log{"vk8s: awake; the clock is set and the controllers start again"},
      P.Plan.clock_sync(),
      P.Run{"/bin/busybox", ["killall", "-KILL", "kube-controller-manager"]} ] : +List<P.Step>}
# A container node shares the host's clock: no RTC step.
law plan.request.idle_wake:
  {P.Plan.request("idle-wake", P.Plan.default_cfg("demo", 6443, False{}), "") ==
    [ P.Log{"vk8s: awake; the controllers start again"},
      P.Run{"/bin/busybox", ["killall", "-KILL", "kube-controller-manager"]} ] : +List<P.Step>}
# The other requests are unchanged.
law plan.request.idle_sync:
  {P.Plan.request("sync", P.Plan.default_cfg("demo", 6443, False{}), "") == [P.Run{"/bin/busybox", ["sync"]}] : +List<P.Step>}
# Proposed: the image cache's upkeep (vk8s cache status|prune; vk8s
# design, vcluster has no image cache). User decision 2026-11-17: no size
# cap; the user prunes. The request cache-usage: du -sk of each
# registry's storage, written to the cache VM's share.
law plan.request.cache_usage:
  {P.Plan.request("cache-usage", P.Plan.default_cfg("demo", 12000, False{}), "/o") ==
    [ P.Run{"/bin/busybox", ["mkdir", "-p", "/var/lib/vcluster/cache/docker.io", "/var/lib/vcluster/cache/registry.k8s.io",
        "/var/lib/vcluster/cache/ghcr.io", "/var/lib/vcluster/cache/quay.io"]},
      P.Run{"/bin/busybox", ["sh", "-c",
        "cd '/var/lib/vcluster/cache' && du -sk 'docker.io' 'registry.k8s.io' 'ghcr.io' 'quay.io' > '/var/lib/vk8s-host/usage'"]} ] : +List<P.Step>}
# The request cache-prune:R: stop R's registry (the supervisor starts it
# again after the request; containerd falls back to the upstream
# meanwhile), rename its storage aside and remove it, give the blocks back
# to the host now with fstrim, then measure again.
law plan.request.cache_prune:
  {P.Plan.request("cache-prune:ghcr.io", P.Plan.default_cfg("demo", 12000, False{}), "/o") ==
    List.append(&2, P.Step,
      [ P.Stop{["registry-ghcr.io"]},
        P.Run{"/bin/busybox", ["sleep", "2"]},
        P.Run{"/bin/busybox", ["mkdir", "-p", "/var/lib/vcluster/cache/ghcr.io"]},
        P.Run{"/bin/busybox", ["rm", "-rf", "/var/lib/vcluster/cache/ghcr.io.pruning"]},
        P.Run{"/bin/busybox", ["mv", "/var/lib/vcluster/cache/ghcr.io", "/var/lib/vcluster/cache/ghcr.io.pruning"]},
        P.Run{"/bin/busybox", ["rm", "-rf", "/var/lib/vcluster/cache/ghcr.io.pruning"]},
        P.Run{"/bin/busybox", ["sync"]},
        P.Run{"/bin/busybox", ["fstrim", "-v", "/var/lib/vcluster"]} ],
      P.Plan.cache_usage()) : +List<P.Step>}
# Several registries: one stop of them all, four steps each, then the
# same sync, fstrim and measurement.
law plan.request.cache_prune.two:
  {List.length(&2, P.Step, P.Plan.request("cache-prune:docker.io,quay.io", P.Plan.default_cfg("demo", 12000, False{}), "/o")) == 14n : Nat}
# Only registries the cache serves: anything else has no steps (fails).
law plan.request.cache_prune.unknown:
  {List.length(&2, P.Step, P.Plan.request("cache-prune:docker.io,gcr.io", P.Plan.default_cfg("demo", 12000, False{}), "/o")) == 0n : Nat}
law plan.request.cache_prune.empty:
  {List.length(&2, P.Step, P.Plan.request("cache-prune:", P.Plan.default_cfg("demo", 12000, False{}), "/o")) == 0n : Nat}
law plan.request.cache_prune.path:
  {List.length(&2, P.Step, P.Plan.request("cache-prune:../pki", P.Plan.default_cfg("demo", 12000, False{}), "/o")) == 0n : Nat}
# Proposed: the API server healthy before kube-controller-manager starts
# (vk8s design, docs/GOAL.md section 10; the upstream code is cited at
# Plan.apiserver_healthy). Without leader election kube-controller-manager
# waits only 10 s for /healthz (kubernetes v1.36.0 controllermanager.go
# CreateControllerContext, WaitForAPIServer(versionedClient,
# 10*time.Second)), then exits. The plan waits for /healthz first, up to
# 120 s times VK8S_WAIT_SCALE, and never fails on it.
law plan.apiserver_healthy.script:
  {P.Plan.apiserver_healthy.script() ==
    "k='/var/lib/vcluster/bin/kubectl'; a='/var/lib/vcluster/pki/super-admin.conf'; w=${VK8S_WAIT_SCALE:-1}; case $w in *[!0-9]*) w=1;; esac; n=$((120 * w)); i=0; until $k --kubeconfig $a get --raw=/healthz >/dev/null 2>&1; do [ $i -ge $n ] && break; sleep 1; i=$((i + 1)); done" : String}
law plan.apiserver_healthy:
  {P.Plan.apiserver_healthy() == P.Run{"/bin/busybox", ["sh", "-c", P.Plan.apiserver_healthy.script()]} : P.Step}
# The default endpoints step is its script, unchanged; v2 runs the
# /healthz wait first.
law plan.default_endpoints.script:
  for c: P.Cfg
  {P.Plan.default_endpoints(c) == P.Run{"/bin/busybox", ["sh", "-c", P.Plan.default_endpoints.script(c)]} : P.Step}
law plan.default_endpoints.v2:
  for c: P.Cfg
  {P.Plan.default_endpoints.v2(c) ==
    P.Run{"/bin/busybox", ["sh", "-c", P.Plan.apiserver_healthy.script() ++ "; " ++ P.Plan.default_endpoints.script(c)]} : P.Step}
# The standalone control plane runs it right before kube-controller-manager.
law plan.control_plane.healthy:
  for c: P.Cfg
  {List.take(&2, P.Step, List.drop(&2, P.Step, P.Plan.control_plane.k8s(c), 2n), 2n) ==
    [ P.Plan.default_endpoints.v2(c),
      P.Daemon{"kube-controller-manager", "/var/lib/vcluster/bin/kube-controller-manager", P.Plan.controller_manager_args.v2(c)} ] : +List<P.Step>}
# Proposed: the wake, v2 (docs/GOAL.md section 10: resume refreshes the
# node lease before controllers act). PID 1 waits until every Lease in
# kube-node-lease was renewed at or after the wake (up to 20 s times
# VK8S_WAIT_SCALE; the kubelet renews every 10 s, upstream
# nodeLeaseDurationSeconds 40 / 4), and only then kills the stopped
# kube-controller-manager, so the supervisor starts the new one against
# fresh leases. A VM sets its clock first.
law plan.node_leases_renewed.script:
  {P.Plan.node_leases_renewed.script() ==
    "k='/var/lib/vcluster/bin/kubectl'; a='/var/lib/vcluster/pki/super-admin.conf'; w=${VK8S_WAIT_SCALE:-1}; case $w in *[!0-9]*) w=1;; esac; n=$((20 * w)); i=0; t=$(date -u +%Y-%m-%dT%H:%M:%S); until $k --kubeconfig $a get leases -n kube-node-lease -o 'jsonpath={range .items[*]}{.spec.renewTime}{\"\\n\"}{end}' 2>/dev/null | awk -v t=\"$t\" 'NF { n++; if ($1 < t) old = 1 } END { exit !(n > 0 && !old) }'; do [ $i -ge $n ] && break; sleep 1; i=$((i + 1)); done; true" : String}
law plan.node_leases_renewed:
  {P.Plan.node_leases_renewed() == P.Run{"/bin/busybox", ["sh", "-c", P.Plan.node_leases_renewed.script()]} : P.Step}
law plan.request.idle_wake.v2:
  {P.Plan.request.v2("idle-wake", P.Plan.default_cfg("demo", 6443, False{}), "") ==
    [ P.Log{"vk8s: awake; the controllers start again once the node leases are renewed"},
      P.Plan.node_leases_renewed(),
      P.Run{"/bin/busybox", ["killall", "-KILL", "kube-controller-manager"]} ] : +List<P.Step>}
law plan.request.idle_wake_clock.v2:
  {P.Plan.request.v2("idle-wake-clock", P.Plan.default_cfg("demo", 6443, False{}), "") ==
    [ P.Log{"vk8s: awake; the clock is set, and the controllers start again once the node leases are renewed"},
      P.Plan.clock_sync(),
      P.Plan.node_leases_renewed(),
      P.Run{"/bin/busybox", ["killall", "-KILL", "kube-controller-manager"]} ] : +List<P.Step>}
# Every other request is Plan.request's.
law plan.request.v2.idle_sleep:
  {P.Plan.request.v2("idle-sleep", P.Plan.default_cfg("demo", 6443, False{}), "") ==
    P.Plan.request("idle-sleep", P.Plan.default_cfg("demo", 6443, False{}), "") : +List<P.Step>}
law plan.request.v2.sync:
  {P.Plan.request.v2("sync", P.Plan.default_cfg("demo", 6443, False{}), "") ==
    P.Plan.request("sync", P.Plan.default_cfg("demo", 6443, False{}), "") : +List<P.Step>}
law plan.request.v2.cache_usage:
  {P.Plan.request.v2("cache-usage", P.Plan.default_cfg("demo", 12000, False{}), "/o") ==
    P.Plan.request("cache-usage", P.Plan.default_cfg("demo", 12000, False{}), "/o") : +List<P.Step>}
# PID 1 runs Plan.request_mode.v2: a standalone request is Plan.request.v2;
# classic mode wakes the same way and still refuses the snapshot actions.
law plan.request_mode.v2.standalone:
  for action: String
  for c: P.Cfg
  for out: String
  {P.Plan.request_mode.v2(False{}, action, c, out) == P.Plan.request.v2(action, c, out) : +List<P.Step>}
law plan.request_mode.v2.classic_wake:
  {P.Plan.request_mode.v2(True{}, "idle-wake", P.Plan.default_cfg("demo", 6443, False{}), "") ==
    P.Plan.request.v2("idle-wake", P.Plan.default_cfg("demo", 6443, False{}), "") : +List<P.Step>}
law plan.request_mode.v2.classic_snapshot:
  {P.Plan.request_mode.v2(True{}, "snapshot-dump", P.Plan.default_cfg("demo", 12000, False{}), "/o") == [] : +List<P.Step>}

# Proposed: the shared read-only layer store in a VM node (docs/GOAL.md
# section 10, shared image layers; vk8s design). The mount is the one the
# design names (`mount -t 9p -o trans=virtio,version=9p2000.L,
# msize=524288 layers /mnt/layers`); the proxy plugin is
# containerd's docs/PLUGINS.md "Proxy Plugins" (type "snapshot", address
# the socket), and the CRI's snapshotter names it; ctr's default
# snapshotter is the environment variable CONTAINERD_SNAPSHOTTER
# (containerd cmd/ctr/commands/commands.go). Without the share the plan
# stays as it is.
law plan.layers_mount:
  {P.Plan.layers_mount() == P.Mount{"9p", "layers", "/mnt/layers", "trans=virtio,version=9p2000.L,msize=524288"} : P.Step}
law plan.snapshotter:
  {P.Plan.snapshotter() == P.Daemon{"snapshotter", "/usr/bin/vk8s-guest", ["snapshotter", "/run/vk8s/snapshotter.sock",
    "/var/lib/vcluster/containerd/io.containerd.snapshotter.v1.bend", "/var/lib/vk8s-host/layers.held"]} : P.Step}
law plan.proxy_plugins:
  {P.Plan.proxy_plugins() == "[proxy_plugins]\n  [proxy_plugins.bend]\n    type = \"snapshot\"\n    address = \"/run/vk8s/snapshotter.sock\"\n" : String}
law plan.containerd_layers.sample:
  {P.Plan.containerd_layers("[plugins.'io.containerd.cri.v1.images']\n  snapshotter = \"overlayfs\"\n  discard_unpacked_layers = true\n") ==
    "[plugins.'io.containerd.cri.v1.images']\n  snapshotter = \"bend\"\n  discard_unpacked_layers = true\n[proxy_plugins]\n  [proxy_plugins.bend]\n    type = \"snapshot\"\n    address = \"/run/vk8s/snapshotter.sock\"\n" : String}
law plan.with_layers.off:
  for ss: +List<P.Step>
  {P.Plan.with_layers(False{}, ss) == ss : +List<P.Step>}
# The config's write becomes the mount, the snapshotter and its socket,
# then the config; the snapshotter starts before containerd.
law plan.with_layers.on:
  {P.Plan.with_layers(True{}, [ P.Mount{"9p", "share", "/var/lib/vk8s-host", "trans=virtio,version=9p2000.L"},
      P.Write{"/etc/containerd/config.toml", "  snapshotter = \"overlayfs\"\n"},
      P.Daemon{"containerd", "/var/lib/vcluster/bin/containerd", ["--config", "/etc/containerd/config.toml"]} ]) ==
    [ P.Mount{"9p", "share", "/var/lib/vk8s-host", "trans=virtio,version=9p2000.L"},
      P.Mount{"9p", "layers", "/mnt/layers", "trans=virtio,version=9p2000.L,msize=524288"},
      P.Run{"/bin/busybox", ["mkdir", "-p", "/run/vk8s", "/var/lib/vcluster/containerd/io.containerd.snapshotter.v1.bend"]},
      P.Daemon{"snapshotter", "/usr/bin/vk8s-guest", ["snapshotter", "/run/vk8s/snapshotter.sock",
        "/var/lib/vcluster/containerd/io.containerd.snapshotter.v1.bend", "/var/lib/vk8s-host/layers.held"]},
      P.WaitFile{"/run/vk8s/snapshotter.sock", 30000},
      P.Write{"/etc/containerd/config.toml", "  snapshotter = \"bend\"\n[proxy_plugins]\n  [proxy_plugins.bend]\n    type = \"snapshot\"\n    address = \"/run/vk8s/snapshotter.sock\"\n"},
      P.Daemon{"containerd", "/var/lib/vcluster/bin/containerd", ["--config", "/etc/containerd/config.toml"]} ] : +List<P.Step>}
law plan.with_layers.no_config:
  {P.Plan.with_layers(True{}, [P.Write{"/etc/hosts", "x"}, P.Log{"y"}]) == [P.Write{"/etc/hosts", "x"}, P.Log{"y"}] : +List<P.Step>}
law plan.layers_on.vm:
  {P.Plan.layers_on(False{}, "worker", "1") == True{} : Bool}
law plan.layers_on.control_plane:
  {P.Plan.layers_on(False{}, "", "1") == True{} : Bool}
law plan.layers_on.unset:
  {P.Plan.layers_on(False{}, "", "") == False{} : Bool}
law plan.layers_on.container:
  {P.Plan.layers_on(True{}, "worker", "1") == False{} : Bool}
law plan.layers_on.cache:
  {P.Plan.layers_on(False{}, "cache", "1") == False{} : Bool}
law plan.layers_env_name:
  {P.Plan.layers_env_name() == "CONTAINERD_SNAPSHOTTER" : String}

# Proposed: an rshared / on VM nodes (Plan.with_rshared), as kind's node
# entrypoint (`mount --make-rshared /`) and vk8s's container mode do.
law plan.rshared_step:
  {P.Plan.rshared_step() == P.Run{"/bin/busybox", ["mount", "--make-rshared", "/"]} : P.Step}
law plan.with_rshared.off:
  for ss: +List<P.Step>
  {P.Plan.with_rshared(False{}, ss) == ss : +List<P.Step>}
law plan.with_rshared.on:
  {P.Plan.with_rshared(True{}, [ P.Mount{"proc", "proc", "/proc", "nosuid,noexec,nodev"},
      P.Mount{"cgroup2", "cgroup2", "/sys/fs/cgroup", "nsdelegate"},
      P.Write{"/etc/hostname", "n"} ]) ==
    [ P.Mount{"proc", "proc", "/proc", "nosuid,noexec,nodev"},
      P.Mount{"cgroup2", "cgroup2", "/sys/fs/cgroup", "nsdelegate"},
      P.Run{"/bin/busybox", ["mount", "--make-rshared", "/"]},
      P.Write{"/etc/hostname", "n"} ] : +List<P.Step>}

# Proposed: the shared layer store's mount read-only and nosuid in the
# guest too (docs/ref/review-security-boundary-delta.md F7, decision D6
# A). Plan.layers_mount and Plan.with_layers stay as pinned above; PID 1
# uses the v2 defs.
law plan.layers_mount.v2:
  {P.Plan.layers_mount.v2() == P.Mount{"9p", "layers", "/mnt/layers", "trans=virtio,version=9p2000.L,msize=524288,ro,nosuid"} : P.Step}
law plan.with_layers.v2.off:
  for ss: +List<P.Step>
  {P.Plan.with_layers.v2(False{}, ss) == ss : +List<P.Step>}
law plan.with_layers.v2.on:
  {P.Plan.with_layers.v2(True{}, [ P.Mount{"9p", "share", "/var/lib/vk8s-host", "trans=virtio,version=9p2000.L"},
      P.Write{"/etc/containerd/config.toml", "  snapshotter = \"overlayfs\"\n"},
      P.Daemon{"containerd", "/var/lib/vcluster/bin/containerd", ["--config", "/etc/containerd/config.toml"]} ]) ==
    [ P.Mount{"9p", "share", "/var/lib/vk8s-host", "trans=virtio,version=9p2000.L"},
      P.Mount{"9p", "layers", "/mnt/layers", "trans=virtio,version=9p2000.L,msize=524288,ro,nosuid"},
      P.Run{"/bin/busybox", ["mkdir", "-p", "/run/vk8s", "/var/lib/vcluster/containerd/io.containerd.snapshotter.v1.bend"]},
      P.Daemon{"snapshotter", "/usr/bin/vk8s-guest", ["snapshotter", "/run/vk8s/snapshotter.sock",
        "/var/lib/vcluster/containerd/io.containerd.snapshotter.v1.bend", "/var/lib/vk8s-host/layers.held"]},
      P.WaitFile{"/run/vk8s/snapshotter.sock", 30000},
      P.Write{"/etc/containerd/config.toml", "  snapshotter = \"bend\"\n[proxy_plugins]\n  [proxy_plugins.bend]\n    type = \"snapshot\"\n    address = \"/run/vk8s/snapshotter.sock\"\n"},
      P.Daemon{"containerd", "/var/lib/vcluster/bin/containerd", ["--config", "/etc/containerd/config.toml"]} ] : +List<P.Step>}
law plan.with_layers.v2.no_config:
  {P.Plan.with_layers.v2(True{}, [P.Write{"/etc/hosts", "x"}, P.Log{"y"}]) == [P.Write{"/etc/hosts", "x"}, P.Log{"y"}] : +List<P.Step>}

# Proposed: no IPv6 on VM and container nodes (docs/ref/review-security-
# boundary-delta.md F2, decision D2 A; the cluster is IPv4 only): IPv6
# off on the node's interfaces, now and later, and no forwarded IPv6
# (bridged pod to pod over fe80:: included), first after the share's
# mount, when the kernel has IPv6.
law plan.ip6tables:
  {P.Plan.ip6tables() == "/usr/sbin/ip6tables" : String}
law plan.ipv6_off:
  {P.Plan.ipv6_off() ==
    [ P.Write{"/proc/sys/net/ipv6/conf/all/disable_ipv6", "1"},
      P.Write{"/proc/sys/net/ipv6/conf/default/disable_ipv6", "1"},
      P.Run{"/usr/sbin/ip6tables", ["-w", "-P", "FORWARD", "DROP"]} ] : +List<P.Step>}
law plan.with_ipv6_off.off:
  for ss: +List<P.Step>
  {P.Plan.with_ipv6_off(False{}, ss) == ss : +List<P.Step>}
law plan.with_ipv6_off.on:
  {P.Plan.with_ipv6_off(True{}, [P.Write{"/etc/hosts", "x"}, P.Log{"y"}]) ==
    [ P.Write{"/proc/sys/net/ipv6/conf/all/disable_ipv6", "1"},
      P.Write{"/proc/sys/net/ipv6/conf/default/disable_ipv6", "1"},
      P.Run{"/usr/sbin/ip6tables", ["-w", "-P", "FORWARD", "DROP"]},
      P.Write{"/etc/hosts", "x"}, P.Log{"y"} ] : +List<P.Step>}

# Proposed: containerd's snapshot annotations on the shared layer store
# (docs/GOAL.md section 10, "the store fills itself"; work item W6 of
# docs/ref/explore-layers-autofill.md), so a Prepare carries the image
# the snapshotter's ask names (src/layers/ask.bend Ask.of_labels.v2).
# The key and its place: containerd v2.2.3 internal/cri/config/
# config.go:291, ImageConfig.DisableSnapshotAnnotations
# `toml:"disable_snapshot_annotations"`, in the CRI images plugin
# ('io.containerd.cri.v1.images'); its default is true
# (internal/cri/config/config_unix.go:33), and the CRI adds the
# annotations only when it is false
# (internal/cri/server/images/image_pull.go:267). It goes on the line
# after `snapshotter = "bend"`, not at the end of the file.
law plan.containerd_layers_annotations_v2:
  {P.Plan.containerd_layers.v2("[plugins.'io.containerd.cri.v1.images']\n  snapshotter = \"overlayfs\"\n  discard_unpacked_layers = true\n") ==
    "[plugins.'io.containerd.cri.v1.images']\n  snapshotter = \"bend\"\n  disable_snapshot_annotations = false\n  discard_unpacked_layers = true\n[proxy_plugins]\n  [proxy_plugins.bend]\n    type = \"snapshot\"\n    address = \"/run/vk8s/snapshotter.sock\"\n" : String}
law plan.snapshot_annotations:
  {P.Plan.snapshot_annotations() == "disable_snapshot_annotations = false" : String}
law plan.with_layers.v3.on:
  {P.Plan.with_layers.v3(True{}, [ P.Mount{"9p", "share", "/var/lib/vk8s-host", "trans=virtio,version=9p2000.L"},
      P.Write{"/etc/containerd/config.toml", "  snapshotter = \"overlayfs\"\n"},
      P.Daemon{"containerd", "/var/lib/vcluster/bin/containerd", ["--config", "/etc/containerd/config.toml"]} ]) ==
    [ P.Mount{"9p", "share", "/var/lib/vk8s-host", "trans=virtio,version=9p2000.L"},
      P.Mount{"9p", "layers", "/mnt/layers", "trans=virtio,version=9p2000.L,msize=524288,ro,nosuid"},
      P.Run{"/bin/busybox", ["mkdir", "-p", "/run/vk8s", "/var/lib/vcluster/containerd/io.containerd.snapshotter.v1.bend"]},
      P.Daemon{"snapshotter", "/usr/bin/vk8s-guest", ["snapshotter", "/run/vk8s/snapshotter.sock",
        "/var/lib/vcluster/containerd/io.containerd.snapshotter.v1.bend", "/var/lib/vk8s-host/layers.held"]},
      P.WaitFile{"/run/vk8s/snapshotter.sock", 30000},
      P.Write{"/etc/containerd/config.toml", "  snapshotter = \"bend\"\n  disable_snapshot_annotations = false\n[proxy_plugins]\n  [proxy_plugins.bend]\n    type = \"snapshot\"\n    address = \"/run/vk8s/snapshotter.sock\"\n"},
      P.Daemon{"containerd", "/var/lib/vcluster/bin/containerd", ["--config", "/etc/containerd/config.toml"]} ] : +List<P.Step>}
law plan.with_layers.v3.no_config:
  {P.Plan.with_layers.v3(True{}, [P.Write{"/etc/hosts", "x"}, P.Log{"y"}]) == [P.Write{"/etc/hosts", "x"}, P.Log{"y"}] : +List<P.Step>}
# Without the store the config stays byte for byte: a VM without
# VK8S_LAYERS=1 keeps every step (its containerd config write included),
# and a container-mode node, the image cache and the node host never
# turn the store on. Native and join nodes write
# Join.install.containerd, which law join.install.containerd pins byte
# for byte (laws/join.bend), with no disable_snapshot_annotations, so
# containerd's default (true) holds there.
law plan.containerd_config_unchanged_when_off:
  for ss: +List<P.Step>
  {P.Plan.with_layers.v3(False{}, ss) == ss : +List<P.Step>}
law plan.containerd_config_unchanged_when_off.container:
  for +r: String
  for +w: String
  {P.Plan.layers_on(True{}, r, w) == False{} : Bool}
law plan.containerd_config_unchanged_when_off.node_host:
  {P.Plan.layers_on(False{}, "node-host", "1") == False{} : Bool}
law plan.containerd_config_unchanged_when_off.vm_config:
  {P.Plan.with_layers.v3(False{}, [P.Write{"/etc/containerd/config.toml", P.Plan.containerd_config.v2()}]) ==
    [P.Write{"/etc/containerd/config.toml", P.Plan.containerd_config.v2()}] : +List<P.Step>}

# Proposed: one squashfs image per layer (v4, feat/layers-sqfs,
# docs/ref/layers-sqfs.md; vk8s's design): the store's share at
# /mnt/layers-store, a tmpfs at /mnt/layers for the snapshotter's layer
# mounts; the rest as v3.
law plan.with_layers.v4.on:
  {P.Plan.with_layers.v4(True{}, [ P.Mount{"9p", "share", "/var/lib/vk8s-host", "trans=virtio,version=9p2000.L"},
      P.Write{"/etc/containerd/config.toml", "  snapshotter = \"overlayfs\"\n"},
      P.Daemon{"containerd", "/var/lib/vcluster/bin/containerd", ["--config", "/etc/containerd/config.toml"]} ]) ==
    [ P.Mount{"9p", "share", "/var/lib/vk8s-host", "trans=virtio,version=9p2000.L"},
      P.Mount{"9p", "layers", "/mnt/layers-store", "trans=virtio,version=9p2000.L,msize=524288,ro,nosuid"},
      P.Mount{"tmpfs", "tmpfs", "/mnt/layers", "mode=0755,nosuid"},
      P.Run{"/bin/busybox", ["mkdir", "-p", "/run/vk8s", "/var/lib/vcluster/containerd/io.containerd.snapshotter.v1.bend"]},
      P.Daemon{"snapshotter", "/usr/bin/vk8s-guest", ["snapshotter", "/run/vk8s/snapshotter.sock",
        "/var/lib/vcluster/containerd/io.containerd.snapshotter.v1.bend", "/var/lib/vk8s-host/layers.held"]},
      P.WaitFile{"/run/vk8s/snapshotter.sock", 30000},
      P.Write{"/etc/containerd/config.toml", "  snapshotter = \"bend\"\n  disable_snapshot_annotations = false\n[proxy_plugins]\n  [proxy_plugins.bend]\n    type = \"snapshot\"\n    address = \"/run/vk8s/snapshotter.sock\"\n"},
      P.Daemon{"containerd", "/var/lib/vcluster/bin/containerd", ["--config", "/etc/containerd/config.toml"]} ] : +List<P.Step>}
law plan.with_layers.v4.off:
  for ss: +List<P.Step>
  {P.Plan.with_layers.v4(False{}, ss) == ss : +List<P.Step>}

# Proposed: optional sets on demand (docs/GOAL.md section 11; vk8s design,
# vcluster has no gVisor). A node runs gVisor when VK8S_GVISOR (a VM's
# kernel command line) says 1, not when it says 0, and otherwise when
# runsc is in bin/ as PID 1 starts (a container node, a native cluster).
law plan.gvisor_on:
  {[P.Plan.gvisor_on("1", False{}), P.Plan.gvisor_on("0", True{}), P.Plan.gvisor_on("", True{}), P.Plan.gvisor_on("", False{})]
   == [True{}, False{}, True{}, False{}] : List<&2, Bool>}
# With gVisor the plan is as it was (plan.runtime.runsc,
# plan.node.runtimeclass_gvisor).
law plan.with_gvisor.on:
  for ss: +List<P.Step>
  {P.Plan.with_gvisor(True{}, ss) == ss : +List<P.Step>}
# Without the gvisor set: no runsc.toml, no RuntimeClass manifest and no
# apply of it (by file name, so a native cluster's relocated paths go
# too); every other step stays.
law plan.with_gvisor.off_steps:
  {P.Plan.with_gvisor(False{},
     [ P.Write{"/etc/containerd/runsc.toml", "binary_name = \"/r\"\n"},
       P.Write{"/var/lib/vk8s/demo/node/containerd/runsc.toml", "root = \"/r\"\n"},
       P.Write{"/etc/vk8s/runtimeclass-gvisor.yaml", "kind: RuntimeClass\n"},
       P.Plan.kubectl(["apply", "-f", "/etc/vk8s/runtimeclass-gvisor.yaml"]),
       P.Write{"/etc/hosts", "127.0.0.1 localhost\n"},
       P.Log{"vk8s: node started"} ])
   == [P.Write{"/etc/hosts", "127.0.0.1 localhost\n"}, P.Log{"vk8s: node started"}] : +List<P.Step>}
# ... and no runsc runtime in the containerd config: its table goes up to
# the next top-level table, the rest stays.
law plan.with_gvisor.off_config:
  {P.Plan.with_gvisor(False{}, [P.Write{"/etc/containerd/config.toml", "version = 3\n" ++ P.Plan.containerd_runsc() ++ "[x]\n  y = 1\n"}])
   == [P.Write{"/etc/containerd/config.toml", "version = 3\n[x]\n  y = 1\n"}] : +List<P.Step>}
# The kine store runs no binary of the etcd set (etcd, etcdutl), so a
# control plane without the etcd backing store needs no etcd set; the etcd
# store and its restore do.
law plan.uses_bin.kine:
  {[P.Plan.uses_bin(P.Plan.store(False{}, "demo"), "etcd"), P.Plan.uses_bin(P.Plan.store(True{}, "demo"), "etcd"),
    P.Plan.uses_bin(P.Plan.restore_store(False{}, "demo", []), "etcdutl"),
    P.Plan.uses_bin(P.Plan.restore_store(False{}, "demo", []), "etcd"),
    P.Plan.uses_bin(P.Plan.restore_store(True{}, "demo", []), "etcdutl")]
   == [False{}, True{}, False{}, False{}, True{}] : List<&2, Bool>}

