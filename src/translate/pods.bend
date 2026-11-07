import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ./meta.bend as M
import ./names.bend as N

# Pod translation (vcluster pkg/controllers/resources/pods: translate/
# translator.go, diff.go, hosts.go, hostpath.go, envvars.go,
# image_translator.go, token/sa_token_secret.go and the pod parts of
# syncer.go), as pure functions over bend-kube JSON values.
#
# Single-namespace mode only. The vcluster name (Go's global VClusterName)
# and the target namespace are configuration (Cfg), not globals. Every value
# vcluster reads through a client (the virtual namespace's labels, the
# services of the pod's namespace, the DNS and API service IPs, the
# requested service account tokens, the random token annotation suffixes,
# pod UIDs, virtual nodes, the pod security verdict, ...) is an input record.
# Mapping-store lookups are not modelled: mappings.VirtualToHostName is the
# single-namespace host name (Names.host_name).
#
# Objects are JSON values. A Go zero value (nil, "", an empty slice) is an
# absent member; Pods.norm puts a value in a canonical form (members sorted
# by key, null members and empty arrays dropped) and Pods.same compares two
# values in that form, which is what apiequality.Semantic.DeepEqual compares.
# The functions build objects with Pods.with, which puts the member first:
# objects are unordered, and that keeps the members the general laws read
# one step away.

# A Kubernetes version (major, minor, patch).
type Ver is Data:
  Ver{major: U32, minor: U32, patch: U32}

# translate.Owner: the object (the vcluster's service or statefulset) that
# owns host objects. Only used when every field is set (GetOwnerReference).
type Owner is Data:
  Owner{api_version: String, kind: String, name: String, uid: String}

# The pod syncer's configuration (vcluster.yaml and startup values).
#   vc: translate.VClusterName           target: the host namespace
#   domain: networking.advanced.clusterDomain
#   workload_sa: controlPlane.advanced.workloadServiceAccount.name
#   sa_sync: sync.toHost.serviceAccounts.enabled
#   pc_to_host / pc_from_host: sync.toHost/fromHost.priorityClasses.enabled
#   pod_pc / runtime_class: sync.toHost.pods.priorityClassName / runtimeClassName
#   rewrite_hosts: sync.toHost.pods.rewriteHosts.enabled
#   hosts_image / hosts_res: the rewrite-hosts init container's image
#     (Pods.image_ref) and resources; hosts_uid / hosts_gid: its user and
#     group (coredns.GetUserID / GetGroupID: the syncer's ids, 1001 for root)
#   sa_secrets: sync.toHost.pods.useSecretsForSATokens
#   virtual_scheduler: controlPlane.advanced.virtualScheduler.enabled
#   host_paths: controlPlane.hostPathMapper.enabled && !central
#   vpath: VirtualPathTemplate, "/tmp/vcluster/<current namespace>/<name>"
#   host_version / virtual_version: the discovered versions (None: unknown)
#   images: sync.toHost.pods.translateImage
#   enforced: sync.toHost.pods.enforceTolerations, parsed
#   node_selector: sync.fromHost.nodes.selector.labels
#   claims / claim_templates: sync.toHost.resourceClaims(.Templates).enabled
#   owner: translate.Owner
type Cfg is Data:
  Cfg{vc: String, target: String, domain: String, workload_sa: String, sa_sync: Bool,
      pc_to_host: Bool, pc_from_host: Bool, pod_pc: String, runtime_class: String, rewrite_hosts: Bool,
      hosts_image: String, hosts_res: J.Json, hosts_uid: String, hosts_gid: String, sa_secrets: Bool,
      virtual_scheduler: Bool, host_paths: Bool, vpath: String, host_version: Maybe<&2, Ver>,
      virtual_version: Maybe<&2, Ver>, images: List<&2, M.KV>, enforced: List<&2, J.Json>,
      node_selector: List<&2, M.KV>, claims: Bool, claim_templates: Bool, owner: Maybe<&2, Owner>}

# A requested service account token: the random suffix of its annotation
# key (random.String(8)) and the token the virtual API server returned.
type Tok is Data:
  Tok{suffix: String, token: String}

# What Translate reads through clients:
#   ns_labels: the labels of the pod's virtual namespace
#   services: the virtual services of the pod's namespace
#   dns_ip: the ClusterIP of the host kube-dns service ("" when missing)
#   kube_ip: the ClusterIP of the vcluster's own service
#   tokens: one per serviceAccountToken projection, in volume order
#     (Pods.token_requests lists the requests)
#   uids: virtual pod UID -> host pod UID, for kubelet sub-path host paths
type Inp is Data:
  Inp{ns_labels: List<&2, M.KV>, services: List<&2, J.Json>, dns_ip: String, kube_ip: String,
      tokens: List<&2, Tok>, uids: List<&2, M.KV>}

# What Diff reads through clients:
#   ns_labels: the labels of the pod's virtual namespace
#   claims_back: host ResourceClaim name -> virtual name, for the claims that
#     exist on the host and map back to a non-empty name
type DInp is Data:
  DInp{ns_labels: List<&2, M.KV>, claims_back: List<&2, M.KV>}

# What the syncer reads besides Translate's and Diff's inputs:
#   nodes: the names of the virtual nodes
#   psa_ok: the pod passes policies.podSecurityStandard (True when unset)
#   blocked: applyLimitByClasses holds (the pod's priority or runtime class
#     fails the fromHost selector)
#   secret: the host service account token secret, when it exists
type SInp is Data:
  SInp{inp: Inp, din: DInp, nodes: List<&2, String>, psa_ok: Bool, blocked: Bool, secret: Maybe<&2, J.Json>}

# A write the syncer makes. Grace periods are decimal seconds ("" for the
# default), uid is a UID precondition ("" for none).
type Write is Data:
  WCreateHost{obj: J.Json}
  WCreateVirtual{obj: J.Json}
  WPatchHost{obj: J.Json}
  WPatchVirtual{obj: J.Json}
  WVirtualStatus{obj: J.Json}
  WDeleteHost{grace: String, uid: String}
  WDeleteVirtual{grace: String, uid: String}
  WBind{node: String}
  WEphemeral{obj: J.Json}
  WResize{patch: J.Json}
  WSecret{obj: J.Json}
  WEvent{kind: String, reason: String, message: String}
  WRequeue{ms: U32}
  WError{message: String}

# The per-container context of Translate.
#   env: the service environment (ServicesToEnvironmentVariables)
#   hosts: the /etc/hosts rewrite applies
#   pv: the pod has volumes (ensureMountPropagation runs)
#   vols: the virtual pod's volumes (for the host path mapper)
type CCtx is Data:
  CCtx{vc: String, ns: String, env: List<&2, M.KV>, images: List<&2, M.KV>, hosts: Bool, pv: Bool,
       host_paths: Bool, vpath: String, vols: List<&2, J.Json>}

# Which container list a container is in.
type CKind is Data:
  CMain{}
  CInit{}
  CEph{}

# The host path kinds (pod logs, kubelet pods, logs) a volume or a
# container already has.
type Reg is Data:
  Reg{pl: Bool, ku: Bool, lg: Bool}

type HK is Data:
  HPL{}
  HKU{}
  HLG{}

# The volume context: names, the token mode, the host path mapper.
type VX is Data:
  VX{vc: String, ns: String, pod: String, secrets: Bool, vpath: String, uids: List<&2, M.KV>}

# Volume translation state: the translated items so far, the token
# annotations, the token secret data, the tokens left.
type Acc is Data:
  Acc{out: List<&2, J.Json>, anns: List<&2, M.KV>, secs: List<&2, M.KV>, toks: List<&2, Tok>}

# Record accessors and setters.

def Pods.cfg.vc(c: Cfg) -> String:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      vc

def Pods.cfg.target(c: Cfg) -> String:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      target

def Pods.cfg.domain(c: Cfg) -> String:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      domain

def Pods.cfg.workload_sa(c: Cfg) -> String:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      workload_sa

def Pods.cfg.sa_sync(c: Cfg) -> Bool:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      sa_sync

def Pods.cfg.pc_to_host(c: Cfg) -> Bool:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      pc_to_host

def Pods.cfg.pc_from_host(c: Cfg) -> Bool:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      pc_from_host

def Pods.cfg.pod_pc(c: Cfg) -> String:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      pod_pc

def Pods.cfg.runtime_class(c: Cfg) -> String:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      runtime_class

def Pods.cfg.rewrite_hosts(c: Cfg) -> Bool:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      rewrite_hosts

def Pods.cfg.hosts_image(c: Cfg) -> String:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      hosts_image

def Pods.cfg.hosts_res(c: Cfg) -> J.Json:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      hosts_res

def Pods.cfg.hosts_uid(c: Cfg) -> String:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      hosts_uid

def Pods.cfg.hosts_gid(c: Cfg) -> String:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      hosts_gid

def Pods.cfg.sa_secrets(c: Cfg) -> Bool:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      sa_secrets

def Pods.cfg.virtual_scheduler(c: Cfg) -> Bool:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      virtual_scheduler

def Pods.cfg.host_paths(c: Cfg) -> Bool:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      host_paths

def Pods.cfg.vpath(c: Cfg) -> String:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      vpath

def Pods.cfg.host_version(c: Cfg) -> Maybe<&2, Ver>:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      host_version

def Pods.cfg.virtual_version(c: Cfg) -> Maybe<&2, Ver>:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      virtual_version

def Pods.cfg.images(c: Cfg) -> List<&2, M.KV>:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      images

def Pods.cfg.enforced(c: Cfg) -> List<&2, J.Json>:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      enforced

def Pods.cfg.node_selector(c: Cfg) -> List<&2, M.KV>:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      node_selector

def Pods.cfg.claims(c: Cfg) -> Bool:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      claims

def Pods.cfg.claim_templates(c: Cfg) -> Bool:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      claim_templates

def Pods.cfg.owner(c: Cfg) -> Maybe<&2, Owner>:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      owner

def Pods.cfg.set_vc(c: Cfg, x: String) -> Cfg:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      Cfg{x, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}

def Pods.cfg.set_target(c: Cfg, x: String) -> Cfg:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      Cfg{vc, x, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}

def Pods.cfg.set_domain(c: Cfg, x: String) -> Cfg:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      Cfg{vc, target, x, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}

def Pods.cfg.set_workload_sa(c: Cfg, x: String) -> Cfg:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      Cfg{vc, target, domain, x, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}

def Pods.cfg.set_sa_sync(c: Cfg, x: Bool) -> Cfg:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      Cfg{vc, target, domain, workload_sa, x, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}

def Pods.cfg.set_pc_to_host(c: Cfg, x: Bool) -> Cfg:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      Cfg{vc, target, domain, workload_sa, sa_sync, x, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}

def Pods.cfg.set_pc_from_host(c: Cfg, x: Bool) -> Cfg:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, x, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}

def Pods.cfg.set_pod_pc(c: Cfg, x: String) -> Cfg:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, x, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}

def Pods.cfg.set_runtime_class(c: Cfg, x: String) -> Cfg:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, x, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}

def Pods.cfg.set_rewrite_hosts(c: Cfg, x: Bool) -> Cfg:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, x, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}

def Pods.cfg.set_hosts_image(c: Cfg, x: String) -> Cfg:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, x, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}

def Pods.cfg.set_hosts_res(c: Cfg, x: J.Json) -> Cfg:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, x, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}

def Pods.cfg.set_hosts_uid(c: Cfg, x: String) -> Cfg:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, x, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}

def Pods.cfg.set_hosts_gid(c: Cfg, x: String) -> Cfg:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, x, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}

def Pods.cfg.set_sa_secrets(c: Cfg, x: Bool) -> Cfg:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, x, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}

def Pods.cfg.set_virtual_scheduler(c: Cfg, x: Bool) -> Cfg:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, x, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}

def Pods.cfg.set_host_paths(c: Cfg, x: Bool) -> Cfg:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, x, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}

def Pods.cfg.set_vpath(c: Cfg, x: String) -> Cfg:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, x, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}

def Pods.cfg.set_host_version(c: Cfg, x: Maybe<&2, Ver>) -> Cfg:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, x, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}

def Pods.cfg.set_virtual_version(c: Cfg, x: Maybe<&2, Ver>) -> Cfg:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, x, images, enforced, node_selector, claims, claim_templates, owner}

def Pods.cfg.set_images(c: Cfg, x: List<&2, M.KV>) -> Cfg:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, x, enforced, node_selector, claims, claim_templates, owner}

def Pods.cfg.set_enforced(c: Cfg, x: List<&2, J.Json>) -> Cfg:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, x, node_selector, claims, claim_templates, owner}

def Pods.cfg.set_node_selector(c: Cfg, x: List<&2, M.KV>) -> Cfg:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, x, claims, claim_templates, owner}

def Pods.cfg.set_claims(c: Cfg, x: Bool) -> Cfg:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, x, claim_templates, owner}

def Pods.cfg.set_claim_templates(c: Cfg, x: Bool) -> Cfg:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, x, owner}

def Pods.cfg.set_owner(c: Cfg, x: Maybe<&2, Owner>) -> Cfg:
  match c:
    case Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, owner}:
      Cfg{vc, target, domain, workload_sa, sa_sync, pc_to_host, pc_from_host, pod_pc, runtime_class, rewrite_hosts, hosts_image, hosts_res, hosts_uid, hosts_gid, sa_secrets, virtual_scheduler, host_paths, vpath, host_version, virtual_version, images, enforced, node_selector, claims, claim_templates, x}

def Pods.inp.ns_labels(c: Inp) -> List<&2, M.KV>:
  match c:
    case Inp{ns_labels, services, dns_ip, kube_ip, tokens, uids}:
      ns_labels

def Pods.inp.services(c: Inp) -> List<&2, J.Json>:
  match c:
    case Inp{ns_labels, services, dns_ip, kube_ip, tokens, uids}:
      services

def Pods.inp.dns_ip(c: Inp) -> String:
  match c:
    case Inp{ns_labels, services, dns_ip, kube_ip, tokens, uids}:
      dns_ip

def Pods.inp.kube_ip(c: Inp) -> String:
  match c:
    case Inp{ns_labels, services, dns_ip, kube_ip, tokens, uids}:
      kube_ip

def Pods.inp.tokens(c: Inp) -> List<&2, Tok>:
  match c:
    case Inp{ns_labels, services, dns_ip, kube_ip, tokens, uids}:
      tokens

def Pods.inp.uids(c: Inp) -> List<&2, M.KV>:
  match c:
    case Inp{ns_labels, services, dns_ip, kube_ip, tokens, uids}:
      uids

def Pods.inp.set_ns_labels(c: Inp, x: List<&2, M.KV>) -> Inp:
  match c:
    case Inp{ns_labels, services, dns_ip, kube_ip, tokens, uids}:
      Inp{x, services, dns_ip, kube_ip, tokens, uids}

def Pods.inp.set_services(c: Inp, x: List<&2, J.Json>) -> Inp:
  match c:
    case Inp{ns_labels, services, dns_ip, kube_ip, tokens, uids}:
      Inp{ns_labels, x, dns_ip, kube_ip, tokens, uids}

def Pods.inp.set_dns_ip(c: Inp, x: String) -> Inp:
  match c:
    case Inp{ns_labels, services, dns_ip, kube_ip, tokens, uids}:
      Inp{ns_labels, services, x, kube_ip, tokens, uids}

def Pods.inp.set_kube_ip(c: Inp, x: String) -> Inp:
  match c:
    case Inp{ns_labels, services, dns_ip, kube_ip, tokens, uids}:
      Inp{ns_labels, services, dns_ip, x, tokens, uids}

def Pods.inp.set_tokens(c: Inp, x: List<&2, Tok>) -> Inp:
  match c:
    case Inp{ns_labels, services, dns_ip, kube_ip, tokens, uids}:
      Inp{ns_labels, services, dns_ip, kube_ip, x, uids}

def Pods.inp.set_uids(c: Inp, x: List<&2, M.KV>) -> Inp:
  match c:
    case Inp{ns_labels, services, dns_ip, kube_ip, tokens, uids}:
      Inp{ns_labels, services, dns_ip, kube_ip, tokens, x}

def Pods.dinp.ns_labels(c: DInp) -> List<&2, M.KV>:
  match c:
    case DInp{ns_labels, claims_back}:
      ns_labels

def Pods.dinp.claims_back(c: DInp) -> List<&2, M.KV>:
  match c:
    case DInp{ns_labels, claims_back}:
      claims_back

def Pods.dinp.set_ns_labels(c: DInp, x: List<&2, M.KV>) -> DInp:
  match c:
    case DInp{ns_labels, claims_back}:
      DInp{x, claims_back}

def Pods.dinp.set_claims_back(c: DInp, x: List<&2, M.KV>) -> DInp:
  match c:
    case DInp{ns_labels, claims_back}:
      DInp{ns_labels, x}

def Pods.sinp.inp(c: SInp) -> Inp:
  match c:
    case SInp{inp, din, nodes, psa_ok, blocked, secret}:
      inp

def Pods.sinp.din(c: SInp) -> DInp:
  match c:
    case SInp{inp, din, nodes, psa_ok, blocked, secret}:
      din

def Pods.sinp.nodes(c: SInp) -> List<&2, String>:
  match c:
    case SInp{inp, din, nodes, psa_ok, blocked, secret}:
      nodes

def Pods.sinp.psa_ok(c: SInp) -> Bool:
  match c:
    case SInp{inp, din, nodes, psa_ok, blocked, secret}:
      psa_ok

def Pods.sinp.blocked(c: SInp) -> Bool:
  match c:
    case SInp{inp, din, nodes, psa_ok, blocked, secret}:
      blocked

def Pods.sinp.secret(c: SInp) -> Maybe<&2, J.Json>:
  match c:
    case SInp{inp, din, nodes, psa_ok, blocked, secret}:
      secret

def Pods.sinp.set_inp(c: SInp, x: Inp) -> SInp:
  match c:
    case SInp{inp, din, nodes, psa_ok, blocked, secret}:
      SInp{x, din, nodes, psa_ok, blocked, secret}

def Pods.sinp.set_din(c: SInp, x: DInp) -> SInp:
  match c:
    case SInp{inp, din, nodes, psa_ok, blocked, secret}:
      SInp{inp, x, nodes, psa_ok, blocked, secret}

def Pods.sinp.set_nodes(c: SInp, x: List<&2, String>) -> SInp:
  match c:
    case SInp{inp, din, nodes, psa_ok, blocked, secret}:
      SInp{inp, din, x, psa_ok, blocked, secret}

def Pods.sinp.set_psa_ok(c: SInp, x: Bool) -> SInp:
  match c:
    case SInp{inp, din, nodes, psa_ok, blocked, secret}:
      SInp{inp, din, nodes, x, blocked, secret}

def Pods.sinp.set_blocked(c: SInp, x: Bool) -> SInp:
  match c:
    case SInp{inp, din, nodes, psa_ok, blocked, secret}:
      SInp{inp, din, nodes, psa_ok, x, secret}

def Pods.sinp.set_secret(c: SInp, x: Maybe<&2, J.Json>) -> SInp:
  match c:
    case SInp{inp, din, nodes, psa_ok, blocked, secret}:
      SInp{inp, din, nodes, psa_ok, blocked, x}

# Defaults: vcluster's chart values for the vcluster named `name`, whose
# translate.VClusterName is vc and whose host namespace is target.
def Pods.cfg.default(vc: String, target: String, +name: String) -> Cfg:
  ?TODO

# A string member, "" when absent or not a string.
def Pods.str(j: J.Json, +k: String) -> String:
  ?TODO

# The object of a string map.
def Pods.obj_of(m: +List<M.KV>) -> J.Json:
  ?TODO

def Pods.jstrs(xs: List<&2, String>) -> List<&2, J.Json>:
  ?TODO

# The "name" member of each item.
def Pods.names(xs: List<&2, J.Json>) -> List<&2, String>:
  ?TODO

# The canonical form of a value: members sorted by key, null members and
# empty arrays dropped, at every depth.
def Pods.norm(j: J.Json) -> J.Json:
  ?TODO

# Every `from` replaced by `to`.
def Pods.subst(s: String, +from: Char, +to: Char) -> String:
  ?TODO

def Pods.name_of(v: J.Json) -> String:
  ?TODO

def Pods.ns_of(v: J.Json) -> String:
  ?TODO

# The rewrite-hosts image (NewTranslator): the registry is the first set of
# controlPlane.advanced.defaultImageRegistry, the image's registry and
# "docker.io".
def Pods.hosts_image(default_registry: String, registry: String, repo: String, tag: String) -> String:
  ?TODO

# translateImage.
def Pods.image(images: +List<M.KV>, +img: String) -> String:
  ?TODO

# LabelsAnnotation: the sorted lines k=<JSON of v>, joined by "\n".
def Pods.labels_text(m: +List<M.KV>) -> String:
  ?TODO

# ServicesToEnvironmentVariables(enableServiceLinks, services, kubeIP): the
# services' variables when service links are on (a later service wins a
# clash; Go's map order is random there), then the KUBERNETES_* ones.
def Pods.services_env(links: Bool, ss: List<&2, J.Json>, kube_ip: String) -> +List<M.KV>:
  ?TODO

# The host field path of a virtual field path.
def Pods.field_path(vc: String, +p: String) -> String:
  ?TODO

def Pods.tr_env_froms(+vc: String, +ns: String, es: List<&2, J.Json>) -> List<&2, J.Json>:
  ?TODO

# The service variables first, then the container's own, translated.
def Pods.env_list(+vc: String, +ns: String, env: +List<M.KV>, +es: List<&2, J.Json>) -> List<&2, J.Json>:
  ?TODO

def Pods.tr_containers(+ctx: CCtx, +kind: CKind, cs: List<&2, J.Json>) -> List<&2, J.Json>:
  ?TODO

# The rewrite-hosts init container (rewritePodHostnameFQDN).
def Pods.hosts_container(+cfg: Cfg, from: String, to: String, fqdn: String) -> J.Json:
  ?TODO

# The TokenRequests Translate makes in the virtual cluster, one per
# serviceAccountToken projection in volume order: the service account
# (spec.serviceAccountName, else serviceAccount, else "default"), its
# namespace and the request (audiences, bound to the pod, ten years).
def Pods.token_requests(+cfg: Cfg, +v: J.Json) -> List<&2, J.Json>:
  ?TODO

# The host secret holding the pod's tokens (SATokenSecret), when
# useSecretsForSATokens is on and the pod projects a token. vcluster deletes
# an existing one first.
def Pods.token_secret(+cfg: Cfg, +inp: Inp, +v: J.Json) -> Maybe<&2, J.Json>:
  ?TODO

# translatePodAffinityTerm for a pod in namespace ns: only labelSelector and
# topologyKey stay; the selector is translated, restricted to the
# namespaces the term names and to this vcluster's pods.
def Pods.aff_term(+vc: String, +ns: String, +term: J.Json) -> J.Json:
  ?TODO

# The events translatePodAffinityTerm records ("<type> <reason> <message>",
# as the fake recorder prints them).
def Pods.aff_term_events(+term: J.Json) -> List<&2, String>:
  ?TODO

# The pod name cut to 63 characters, "." replaced by "-", one trailing "-"
# trimmed.
def Pods.hostname_of(name: String) -> String:
  ?TODO

def Pods.claims(+cl: Bool, +tpl: Bool, +vc: String, +ns: String, cs: List<&2, J.Json>) -> List<&2, J.Json>:
  ?TODO

# The per-container context.
def Pods.ctx(+cfg: Cfg, +inp: Inp, +v: J.Json) -> CCtx:
  ?TODO

# Translate: the host pod of virtual pod v. Its status is reset.
def Pods.translate(+cfg: Cfg, +inp: Inp, +v: J.Json) -> J.Json:
  ?TODO

# The error Translate returns for a pod it cannot translate (a kubelet
# sub-path host path without a pod UID), if any.
def Pods.check(+cfg: Cfg, +v: J.Json) -> Maybe<&2, String>:
  ?TODO

# The virtual API server drops ObservedGeneration: virtual K8s below 1.34
# (virtualClusterStripsObservedGeneration).
def Pods.strips(+cfg: Cfg) -> Bool:
  ?TODO

def Pods.desired.if(strip: Bool, +h: J.Json, +vs: J.Json) -> J.Json:
  ?TODO

# DesiredVirtualStatus(hostStatus, virtualStatus): the host status with the
# virtual QOS class; when the virtual API server drops ObservedGeneration,
# the virtual one and conditions without it. (A null member is an absent one.)
def Pods.desired_status(+cfg: Cfg, h: J.Json, vs: J.Json) -> J.Json:
  ?TODO

# conditionsCopyBidirectional(virtualOld, virtual, hostOld, host): (new
# virtual, new host) conditions.
def Pods.conditions_copy(+cfg: Cfg, vo: J.Json, +v: J.Json, ho: J.Json, +h: J.Json) -> J.Json & J.Json:
  ?TODO

# Diff(event) with event = NewSyncEventWithOld(hostOld, host, virtualOld,
# virtual): (new virtual pod, new host pod).
def Pods.diff(+cfg: Cfg, +din: DInp, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> J.Json & J.Json:
  ?TODO

# buildHostPodContainersResourcesResizePatch(vPod, pPod): the patch of the
# containers whose resources differ, None when none does. (Resources
# compare as JSON: quantities with the same value and another spelling
# differ here.)
def Pods.resize_patch(+v: J.Json, +h: J.Json) -> Maybe<&2, J.Json>:
  ?TODO

# The in-place resize patch: host K8s 1.35 or later only.
def Pods.resize(+cfg: Cfg, +v: J.Json, +h: J.Json) -> Maybe<&2, J.Json>:
  ?TODO

# One reconcile of the pod syncer, a pure function of the snapshots
# (hostOld, host, virtualOld, virtual): the writes to make, in order.
def Pods.sync(+cfg: Cfg, +sin: SInp, ho: Maybe<&2, J.Json>, h: Maybe<&2, J.Json>, vo: Maybe<&2, J.Json>, v: Maybe<&2, J.Json>) -> List<&2, Write>:
  ?TODO

