import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J

# The CoreDNS manifests vcluster deploys in the virtual cluster (vcluster
# pkg/coredns: template.go corednsCorefile and corednsManifests,
# coredns.go getManifestVariables, pkg/constants/coredns.go). Pure: the
# host writes Coredns.default_manifest() to disk and applies it.
#
# The two templates are rendered as vcluster's text/template renders them,
# from the same inputs: `values`, vcluster's config as JSON (the subtree
# the templates read: controlPlane.coredns, controlPlane.advanced,
# networking, policies), and Vars, the template variables IMAGE,
# RUN_AS_USER, RUN_AS_GROUP and HOST_CLUSTER_DNS. A Go template's `if`
# is Coredns.truthy, `{{ x }}` is Coredns.text, `toYaml` is
# Coredns.to_yaml and `indent` is Coredns.indent. Each output is trimmed
# and loses every "<no value>" (vcluster's TrimSpace and removeNoValue).
#
# vk8s calls it with Coredns.render(Cfg): vcluster's defaults
# (Coredns.vcluster_defaults) with the cluster domain, the kube-dns
# Service IP (service.spec.clusterIP), the replica count, and vk8s's
# choices: no kubelet proxy by hostname (no rewrite rule), no resources,
# no topology spread constraints and a pod security standard (seccomp
# RuntimeDefault), as scripts/guest/coredns.yaml was rendered.
#
# vcluster quirks, as encoded here:
# - the kubernetes plugin always serves cluster.local; another cluster
#   domain is served before it, not instead of it.
# - priorityClassName is always written, as "" when unset.
# - indent pads empty lines too: the Corefile's blank line becomes four
#   spaces in the ConfigMap.
# - a toYaml'd service.spec is written as is; its selector and ports
#   replace the defaults only when set (an empty spec prints `{}`).
# - "<no value>" is removed from the whole output, user text included.
# - overwriteManifests and overwriteConfig replace everything, trimmed.
# - getManifestVariables prefixes docker.io/ when no registry is set.
# Deviations: toYaml quotes some strings that yaml.v2 would print plain
# (anything outside letters, digits and -._/+=@:, and digit-led strings
# with ':' or '-'); the YAML means the same. Map keys sort in byte order
# (yaml.v2 sorts letters before other characters at a difference). A list
# inside a list prints in JSON flow form.

# HOST_CLUSTER_DNS is the first nameserver of /etc/resolv.conf in vcluster;
# "" in a field is a missing variable.
type Vars is Data:
  Vars{image: String, run_as_user: String, run_as_group: String, host_dns: String}

# What vk8s chooses: the cluster domain, the kube-dns Service IP (kubelet's
# clusterDNS), the CoreDNS image, replicas and the container's uid and gid.
type Cfg is Data:
  Cfg{cluster_domain: String, dns_service_ip: String, image: String, replicas: U32, run_as_user: U32,
    run_as_group: U32}

# One pinned image per Kubernetes minor.
type Pin is Data:
  Pin{version: String, image: String}

# Go strings.ReplaceAll(s, from, to), for a non-empty from.
def Coredns.replace(s: String, +from: String, +to: String) -> String:
  ?TODO

# vcluster's indent: pad, and pad after every newline (empty lines too).
def Coredns.indent(+pad: String, s: String) -> String:
  ?TODO

# A Go template's truth: false, 0, "", null, a missing key, [] and {} are
# false.
def Coredns.truthy(j: J.Json) -> Bool:
  ?TODO

# vcluster's toYaml: yaml.Marshal without its last newline.
def Coredns.to_yaml(j: J.Json) -> String:
  ?TODO

# Sets the value at a path, making the objects on the way.
def Coredns.put(path: List<&2, String>, +j: J.Json, v: J.Json) -> J.Json:
  ?TODO

# config.NewDefaultConfig(), the part the templates read.
def Coredns.vcluster_defaults() -> J.Json:
  ?TODO

def Coredns.label_key() -> String:
  ?TODO

def Coredns.label_value() -> String:
  ?TODO

def Coredns.default_image() -> String:
  ?TODO

# The image pinned for Kubernetes "MAJOR.MINOR", if any.
def Coredns.pinned(+v: String) -> Maybe<&2, String>:
  ?TODO

# getManifestVariables' IMAGE: the image pinned for the virtual
# Kubernetes version (else DefaultImage), under the default image
# registry (one trailing '/' trimmed), else under docker.io.
def Coredns.image(+major: String, +minor: String, +registry: String) -> String:
  ?TODO

# vcluster's ProcessCorefile.
def Coredns.corefile(+v: J.Json, vs: Vars) -> String:
  ?TODO

# vcluster's processManifests: the manifests as one YAML stream.
def Coredns.manifests(+v: J.Json, +vs: Vars) -> String:
  ?TODO

def Coredns.values(cfg: Cfg) -> J.Json:
  ?TODO

# HOST_CLUSTER_DNS is the file itself, vcluster's choice when
# /etc/resolv.conf has no nameserver; only fallbackHostCluster reads it.
def Coredns.vars(cfg: Cfg) -> Vars:
  ?TODO

def Coredns.render(+cfg: Cfg) -> String:
  ?TODO

# The kube-dns Service at kubelet's clusterDNS 10.96.0.10, cluster.local,
# the image vk8s preloads (scripts/guest/images.sh) and uid/gid 1001
# (vcluster's for a root process).
def Coredns.default_cfg() -> Cfg:
  ?TODO

# The manifest vk8s applies in the guest.
def Coredns.default_manifest() -> String:
  ?TODO
