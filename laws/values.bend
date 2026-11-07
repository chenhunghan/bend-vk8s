import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
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
