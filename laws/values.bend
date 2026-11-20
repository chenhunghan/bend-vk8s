import Base
import bend-kube-runtime@0.10.0.0/src/json.bend as J
import ../src/config/vcluster.bend as C
import ../src/guest/plan.bend as P
import ../src/guest/values.bend as V

# Spec for src/guest/values.bend: what vk8s applies from a vcluster.yaml.

def Laws.values.of(r: Result<&2, &2, String, J.Json>) -> J.Json:
  match r:
    case Done{j}:
      j
    case Fail{e}:
      J.JNil{}

def Laws.values.doc(+s: String) -> J.Json:
  Laws.values.of(C.Config.parse(s))

# vcluster's extraArgs list for the API server.
law values.extra_args:
  {V.Values.extra_args(Laws.values.doc("controlPlane:\n  distro:\n    k8s:\n      apiServer:\n        extraArgs:\n        - --v=4\n        - --audit-log-maxage=7\n"), "apiServer")
   == ["--v=4", "--audit-log-maxage=7"] : +List<String>}

# Embedded etcd from controlPlane.backingStore.
law values.etcd:
  {V.Values.etcd(Laws.values.doc("controlPlane:\n  backingStore:\n    etcd:\n      embedded:\n        enabled: true\n")) == True{} : Bool}

law values.default_sqlite:
  {V.Values.etcd(Laws.values.doc("")) == False{} : Bool}

# The chart defaults are all runnable.
law values.defaults_supported:
  {V.Values.unsupported(Laws.values.doc("")) == "" : String}

law values.version_refused:
  {V.Values.unsupported(Laws.values.doc("controlPlane:\n  distro:\n    k8s:\n      version: v1.33.1\n"))
   == "vk8s ships Kubernetes v1.36.6; controlPlane.distro.k8s.version v1.33.1 is not available" : String}

law values.service_cidr_refused:
  {V.Values.unsupported(Laws.values.doc("networking:\n  serviceCIDR: 10.43.0.0/16\n"))
   == "vk8s does not support networking.serviceCIDR other than 10.96.0.0/12 yet" : String}

# extraArgs reach the API server's daemon, after vk8s's own flags (later wins).
law values.with_extra_apiserver:
  {V.Values.with_extra([P.Daemon{"kube-apiserver", "/k", ["--v=2"]}, P.Daemon{"containerd", "/c", ["--v=2"]}],
     Laws.values.doc("controlPlane:\n  distro:\n    k8s:\n      apiServer:\n        extraArgs:\n        - --v=4\n"))
   == [P.Daemon{"kube-apiserver", "/k", ["--v=4"]}, P.Daemon{"containerd", "/c", ["--v=2"]}] : +List<P.Step>}

# The split puts the share's mount last in the first part.
law values.split_at_share:
  {V.Values.split([P.Log{"a"}, P.Mount{"9p", "share", P.Plan.host_dir(), "o"}, P.Log{"b"}])
   == V.Split{[P.Log{"a"}, P.Mount{"9p", "share", P.Plan.host_dir(), "o"}], [P.Log{"b"}]} : V.Split}

# Proposed: what agent-substrate needs (its hack/create-kind-cluster.sh
# sets kind featureGates ClusterTrustBundle, ClusterTrustBundleProjection
# and PodCertificateRequest, runtimeConfig certificates.k8s.io/v1beta1,
# kubelet serializeImagePulls: false and maxParallelImagePulls: 4, and the
# nodes' proxy_arp/proxy_ndp sysctls), given as vcluster gives them:
# --feature-gates and --runtime-config in controlPlane.distro.k8s.
# <component>.extraArgs (merged by pkg/util/command MergeArgs: the base
# flags vk8s keeps, then the extra ones), the kubelet's keys in
# privateNodes.kubelet.config (config/config.go Kubelet.Config, merged
# into every node's kubelet config), and the sysctls under vk8s's own key
# vk8s.nodes.proxyArp (vcluster has none).

def Laws.values.substrate() -> String:
  "controlPlane:\n  distro:\n    k8s:\n      apiServer:\n        extraArgs:\n"
  ++ "        - --feature-gates=ClusterTrustBundle=true,ClusterTrustBundleProjection=true,PodCertificateRequest=true\n"
  ++ "        - --runtime-config=certificates.k8s.io/v1beta1=true\n"
  ++ "      controllerManager:\n        extraArgs:\n        - --feature-gates=ClusterTrustBundle=true,PodCertificateRequest=true\n"
  ++ "privateNodes:\n  kubelet:\n    config:\n      featureGates:\n        ClusterTrustBundle: true\n"
  ++ "        ClusterTrustBundleProjection: true\n        PodCertificateRequest: true\n"
  ++ "      serializeImagePulls: false\n      maxParallelImagePulls: 4\n"
  ++ "vk8s:\n  nodes:\n    proxyArp: true\n"

# Each field of the substrate document is supported, one law per field
# (the whole document at once runs the verdict kernel out of fuel; each
# check of Values.unsupported.v2 reads only its own path).
def Laws.values.k8s(+comp: String, +arg: String) -> String:
  "controlPlane:\n  distro:\n    k8s:\n      " ++ comp ++ ":\n        extraArgs:\n        - " ++ arg ++ "\n"

def Laws.values.kubelet(+lines: String) -> String:
  "privateNodes:\n  kubelet:\n    config:\n" ++ lines

law values.substrate_apiserver_feature_gates:
  {V.Values.unsupported.v2(Laws.values.doc(Laws.values.k8s("apiServer",
     "--feature-gates=ClusterTrustBundle=true,ClusterTrustBundleProjection=true,PodCertificateRequest=true"))) == "" : String}

law values.substrate_apiserver_runtime_config:
  {V.Values.unsupported.v2(Laws.values.doc(Laws.values.k8s("apiServer", "--runtime-config=certificates.k8s.io/v1beta1=true"))) == "" : String}

law values.substrate_controller_manager_feature_gates:
  {V.Values.unsupported.v2(Laws.values.doc(Laws.values.k8s("controllerManager",
     "--feature-gates=ClusterTrustBundle=true,PodCertificateRequest=true"))) == "" : String}

law values.substrate_kubelet_feature_gates:
  {V.Values.unsupported.v2(Laws.values.doc(Laws.values.kubelet("      featureGates:\n        ClusterTrustBundle: true\n"
     ++ "        ClusterTrustBundleProjection: true\n        PodCertificateRequest: true\n"))) == "" : String}

law values.substrate_kubelet_serialize_image_pulls:
  {V.Values.unsupported.v2(Laws.values.doc(Laws.values.kubelet("      serializeImagePulls: false\n"))) == "" : String}

law values.substrate_kubelet_max_parallel_image_pulls:
  {V.Values.unsupported.v2(Laws.values.doc(Laws.values.kubelet("      maxParallelImagePulls: 4\n"))) == "" : String}

law values.substrate_proxy_arp:
  {V.Values.unsupported.v2(Laws.values.doc("vk8s:\n  nodes:\n    proxyArp: true\n")) == "" : String}

# The feature gates and the API group reach the API server and the
# controller manager after vk8s's own flags.
law values.feature_gates:
  {V.Values.with_extra([P.Daemon{"kube-apiserver", "/k", ["--secure-port=6443", "--profiling=false"]},
     P.Daemon{"kube-controller-manager", "/c", ["--leader-elect=true"]}], Laws.values.doc(Laws.values.substrate()))
   == [P.Daemon{"kube-apiserver", "/k", ["--secure-port=6443", "--profiling=false",
         "--feature-gates=ClusterTrustBundle=true,ClusterTrustBundleProjection=true,PodCertificateRequest=true",
         "--runtime-config=certificates.k8s.io/v1beta1=true"]},
       P.Daemon{"kube-controller-manager", "/c", ["--leader-elect=true", "--feature-gates=ClusterTrustBundle=true,PodCertificateRequest=true"]}]
   : +List<P.Step>}

# The kubelet's keys, one KubeletConfiguration line each, in order.
law values.kubelet_lines:
  {V.Values.kubelet_lines(Laws.values.doc(Laws.values.substrate()))
   == "\"featureGates\": {\"ClusterTrustBundle\": true, \"ClusterTrustBundleProjection\": true, \"PodCertificateRequest\": true}\n"
      ++ "\"serializeImagePulls\": false\n\"maxParallelImagePulls\": 4\n" : String}

law values.kubelet_lines_none:
  {V.Values.kubelet_lines(Laws.values.doc("")) == "" : String}

# They join the KubeletConfiguration document of kubelet-config.yaml and of
# kubeadm.yaml (whose kubelet-config ConfigMap joining nodes read), also
# when another document follows it; other files stay as they are.
law values.with_kubelet:
  {V.Values.with_kubelet([P.Write{"/var/lib/vcluster/kubelet-config.yaml", "apiVersion: kubelet.config.k8s.io/v1beta1\nkind: KubeletConfiguration\nfailSwapOn: false\n"},
       P.Write{"/var/lib/vcluster/kubeadm.yaml", "kind: ClusterConfiguration\n---\nkind: KubeletConfiguration\ncgroupDriver: cgroupfs\n---\nkind: KubeProxyConfiguration\n"},
       P.Write{"/etc/vk8s/other.yaml", "kind: KubeletConfiguration\n"}, P.Log{"a"}],
     Laws.values.doc("privateNodes:\n  kubelet:\n    config:\n      maxParallelImagePulls: 4\n"))
   == [P.Write{"/var/lib/vcluster/kubelet-config.yaml", "apiVersion: kubelet.config.k8s.io/v1beta1\nkind: KubeletConfiguration\n\"maxParallelImagePulls\": 4\nfailSwapOn: false\n"},
       P.Write{"/var/lib/vcluster/kubeadm.yaml", "kind: ClusterConfiguration\n---\nkind: KubeletConfiguration\n\"maxParallelImagePulls\": 4\ncgroupDriver: cgroupfs\n---\nkind: KubeProxyConfiguration\n"},
       P.Write{"/etc/vk8s/other.yaml", "kind: KubeletConfiguration\n"}, P.Log{"a"}] : +List<P.Step>}

law values.with_kubelet_none:
  {V.Values.with_values([P.Write{"/var/lib/vcluster/kubelet-config.yaml", "kind: KubeletConfiguration\nfailSwapOn: false\n"}], Laws.values.doc(""))
   == [P.Write{"/var/lib/vcluster/kubelet-config.yaml", "kind: KubeletConfiguration\nfailSwapOn: false\n"}] : +List<P.Step>}

# vk8s design: flags that set its ports, addresses, certificates,
# kubeconfigs or data paths are refused, by name.
law values.owned_apiserver:
  {V.Values.unsupported.v2(Laws.values.doc("controlPlane:\n  distro:\n    k8s:\n      apiServer:\n        extraArgs:\n        - --v=4\n        - --secure-port=7443\n"))
   == "vk8s sets --secure-port itself (its ports, addresses, certificates, kubeconfigs and data paths); remove it from controlPlane.distro.k8s.apiServer.extraArgs" : String}

law values.owned_controller_manager:
  {V.Values.unsupported.v2(Laws.values.doc("controlPlane:\n  distro:\n    k8s:\n      controllerManager:\n        extraArgs:\n        - --cluster-signing-cert-file=/tmp/ca.crt\n"))
   == "vk8s sets --cluster-signing-cert-file itself (its ports, addresses, certificates, kubeconfigs and data paths); remove it from controlPlane.distro.k8s.controllerManager.extraArgs" : String}

law values.owned_scheduler:
  {V.Values.unsupported.v2(Laws.values.doc("controlPlane:\n  distro:\n    k8s:\n      scheduler:\n        extraArgs:\n        - --kubeconfig=/tmp/s.conf\n"))
   == "vk8s sets --kubeconfig itself (its ports, addresses, certificates, kubeconfigs and data paths); remove it from controlPlane.distro.k8s.scheduler.extraArgs" : String}

law values.owned_kubelet:
  {V.Values.unsupported.v2(Laws.values.doc("privateNodes:\n  kubelet:\n    config:\n      clusterDomain: example.org\n"))
   == "vk8s sets privateNodes.kubelet.config.clusterDomain itself; remove it from the vcluster.yaml" : String}

# Values.unsupported's refusals come first.
law values.unsupported_v2_first:
  {V.Values.unsupported.v2(Laws.values.doc("controlPlane:\n  distro:\n    k8s:\n      version: v1.33.1\n      apiServer:\n        extraArgs:\n        - --secure-port=7443\n"))
   == "vk8s ships Kubernetes v1.36.6; controlPlane.distro.k8s.version v1.33.1 is not available" : String}

# vk8s.nodes.proxyArp: off by default; on, both sysctls, or only the IPv4
# one on a kernel without IPv6; first among a node's steps after its
# share's mount.
law values.proxy_arp_default:
  {V.Values.sysctls(Laws.values.doc(""), True{}) == [] : +List<P.Step>}

law values.proxy_arp:
  {V.Values.sysctls(Laws.values.doc(Laws.values.substrate()), True{})
   == [P.Write{"/proc/sys/net/ipv4/conf/all/proxy_arp", "1"}, P.Write{"/proc/sys/net/ipv6/conf/all/proxy_ndp", "1"}] : +List<P.Step>}

law values.proxy_arp_no_ipv6:
  {V.Values.sysctls(Laws.values.doc("vk8s:\n  nodes:\n    proxyArp: true\n"), False{})
   == [P.Write{"/proc/sys/net/ipv4/conf/all/proxy_arp", "1"}] : +List<P.Step>}

law values.with_node:
  {V.Values.with_node([P.Log{"a"}], Laws.values.doc("vk8s:\n  nodes:\n    proxyArp: true\n"), False{})
   == [P.Write{"/proc/sys/net/ipv4/conf/all/proxy_arp", "1"}, P.Log{"a"}] : +List<P.Step>}

# Proposed: control-plane-only nodes (v2, GOAL section 11).
# vcluster config/config.go (StandaloneJoinNode.Enabled): "If false, only
# the control plane binaries will be executed and no node will show up in
# the actual cluster"; chart/values.yaml: controlPlane.standalone.joinNode
# .enabled: true.
def Laws.values.boot() -> +List<P.Step>:
  [P.Daemon{"kube-apiserver", "/a", []}, P.Daemon{"containerd", "/c", []}, P.Write{"/k", "x"},
   P.Daemon{"kubelet", "/k", []}, P.Daemon{"snapshotter", "/s", []}, P.Daemon{"kube-router", "/r", []},
   P.Run{"/kubectl", ["apply"]}, P.Daemon{"join-server", "/j", []}]

law values.join_node.off:
  {V.Values.join_node.v2(True{}, Laws.values.doc("controlPlane:\n  standalone:\n    joinNode:\n      enabled: false\n"), Laws.values.boot())
   == [P.Daemon{"kube-apiserver", "/a", []}, P.Write{"/k", "x"}, P.Run{"/kubectl", ["apply"]}, P.Daemon{"join-server", "/j", []}] : +List<P.Step>}
law values.join_node.on:
  {V.Values.join_node.v2(True{}, Laws.values.doc("controlPlane:\n  standalone:\n    joinNode:\n      enabled: true\n"), Laws.values.boot())
   == Laws.values.boot() : +List<P.Step>}
law values.join_node.absent:
  {V.Values.join_node.v2(True{}, Laws.values.doc("controlPlane:\n  coredns:\n    enabled: true\n"), Laws.values.boot())
   == Laws.values.boot() : +List<P.Step>}
law values.join_node.not_cp:
  {V.Values.join_node.v2(False{}, Laws.values.doc("controlPlane:\n  standalone:\n    joinNode:\n      enabled: false\n"), Laws.values.boot())
   == Laws.values.boot() : +List<P.Step>}
