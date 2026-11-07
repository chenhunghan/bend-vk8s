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

# Constants (translator.go, hosts.go, hostpath.go).

def Pods.owner_references_annotation() -> String:
  "vcluster.loft.sh/owner-references"

def Pods.owner_set_kind_annotation() -> String:
  "vcluster.loft.sh/owner-set-kind"

def Pods.namespace_annotation() -> String:
  "vcluster.loft.sh/namespace"

def Pods.name_annotation() -> String:
  "vcluster.loft.sh/name"

def Pods.labels_annotation() -> String:
  "vcluster.loft.sh/labels"

def Pods.uid_annotation() -> String:
  "vcluster.loft.sh/uid"

def Pods.autoscaler_annotation() -> String:
  "cluster-autoscaler.kubernetes.io/safe-to-evict"

def Pods.autoscaler_daemonset_annotation() -> String:
  "cluster-autoscaler.kubernetes.io/daemonset-pod"

def Pods.sa_name_annotation() -> String:
  "vcluster.loft.sh/service-account-name"

def Pods.token_annotation() -> String:
  "vcluster.loft.sh/token-"

def Pods.disable_subdomain_rewrite_annotation() -> String:
  "vcluster.loft.sh/disable-subdomain-rewrite"

def Pods.hosts_rewritten_annotation() -> String:
  "vcluster.loft.sh/hosts-rewritten"

def Pods.hosts_name() -> String:
  "vcluster-rewrite-hosts"

def Pods.skip_backsync_annotation() -> String:
  "vcluster.loft.sh/skip-backsync"

def Pods.kind() -> String:
  "/v1, Kind=Pod"

def Pods.affinity_warning() -> String:
  "Inter-pod affinity rule(s) that use both .namespaces and .namespaceSelector fields in the same term are not supported by vcluster yet. The .namespaceSelector fields of the unsupported affinity entries will be ignored."

def Pods.hosts_res_default() -> J.Json:
  J.Json.obj([J.KV{"limits", J.Json.obj([J.KV{"cpu", J.JStr{"30m"}}, J.KV{"memory", J.JStr{"64Mi"}}])},
    J.KV{"requests", J.Json.obj([J.KV{"cpu", J.JStr{"30m"}}, J.KV{"memory", J.JStr{"64Mi"}}])}])

# Defaults: vcluster's chart values for the vcluster named `name`, whose
# translate.VClusterName is vc and whose host namespace is target.
def Pods.cfg.default(vc: String, target: String, +name: String) -> Cfg:
  Cfg{vc, target, "cluster.local", "vc-workload-" ++ name, False{}, False{}, False{}, "", "", True{},
    "mirror.gcr.io/library/alpine:3.20", Pods.hosts_res_default(), "1001", "1001", False{}, False{}, False{},
    "/tmp/vcluster/" ++ name ++ "/" ++ name, None{}, None{}, [], [], [], False{}, False{}, None{}}

# JSON access.

# The member chain of an object; JNil for anything else.
def Pods.mems(j: J.Json) -> J.Json:
  match j:
    case J.JObj{ms}:
      ms
    case _:
      J.JNil{}

def Pods.get(j: J.Json, +k: String) -> J.Json:
  J.Json.get(j, k)

# A string member, "" when absent or not a string.
def Pods.str(j: J.Json, +k: String) -> String:
  J.Json.str_or(J.Json.get(j, k), "")

def Pods.has(j: J.Json, +k: String) -> Bool:
  Bool.not(J.Json.is_null(J.Json.get(j, k)))

def Pods.items(j: J.Json) -> List<&2, J.Json>:
  J.Json.items(j)

def Pods.arr(xs: List<&2, J.Json>) -> J.Json:
  J.Json.arr(xs)

# The text of a number, "" for anything else.
def Pods.num(j: J.Json) -> String:
  match j:
    case J.JNum{t}:
      t
    case _:
      ""

def Pods.is_true(j: J.Json) -> Bool:
  match j:
    case J.JBool{b}:
      b
    case _:
      False{}

# The object j with member k set to v, first. Anything that is not an
# object counts as the empty object.
def Pods.with(+k: String, v: J.Json, j: J.Json) -> J.Json:
  J.JObj{J.JMem{k, v, J.Json.del_mem(Pods.mems(j), k)}}

def Pods.without(+k: String, j: J.Json) -> J.Json:
  J.JObj{J.Json.del_mem(Pods.mems(j), k)}

def Pods.with_str.if(empty: Bool, k: String, s: String, j: J.Json) -> J.Json:
  match empty:
    case True{}:
      Pods.without(k, j)
    case False{}:
      Pods.with(k, J.JStr{s}, j)

# Sets a string member; "" removes it (Go omitempty).
def Pods.with_str(k: String, +s: String, j: J.Json) -> J.Json:
  Pods.with_str.if(String.is_empty(s), k, s, j)

def Pods.with_opt.if(isnull: Bool, k: String, v: J.Json, j: J.Json) -> J.Json:
  match isnull:
    case True{}:
      Pods.without(k, j)
    case False{}:
      Pods.with(k, v, j)

# Sets a member; null removes it.
def Pods.with_opt(k: String, +v: J.Json, j: J.Json) -> J.Json:
  Pods.with_opt.if(J.Json.is_null(v), k, v, j)

def Pods.obj_of.go(m: +List<M.KV>) -> J.Json:
  match m:
    case Nil{}:
      J.JNil{}
    case Con{M.KV{k, v}, r}:
      J.JMem{k, J.JStr{v}, Pods.obj_of.go(r)}

# The object of a string map.
def Pods.obj_of(m: +List<M.KV>) -> J.Json:
  J.JObj{Pods.obj_of.go(m)}

def Pods.with_map.if(empty: Bool, k: String, m: +List<M.KV>, j: J.Json) -> J.Json:
  match empty:
    case True{}:
      Pods.without(k, j)
    case False{}:
      Pods.with(k, Pods.obj_of(m), j)

# Sets a string map member; the empty map removes it (a nil Go map).
def Pods.with_map(k: String, +m: +List<M.KV>, j: J.Json) -> J.Json:
  Pods.with_map.if(List.is_empty(&2, M.KV, m), k, m, j)

def Pods.when.if(isnull: Bool, j: J.Json, x: J.Json) -> J.Json:
  match isnull:
    case True{}:
      j
    case False{}:
      x

# x, unless j is null.
def Pods.when(+j: J.Json, x: J.Json) -> J.Json:
  Pods.when.if(J.Json.is_null(j), j, x)

def Pods.or_obj(j: J.Json) -> J.Json:
  match j:
    case J.JNull{}:
      J.JObj{J.JNil{}}
    case x:
      x

def Pods.jstrs(xs: List<&2, String>) -> List<&2, J.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, r}:
      J.JStr{x} <> Pods.jstrs(r)

def Pods.strs.go(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, r}:
      J.Json.str_or(x, "") <> Pods.strs.go(r)

# The strings of an array.
def Pods.strs(j: J.Json) -> List<&2, String>:
  Pods.strs.go(J.Json.items(j))

# The "name" member of each item.
def Pods.names(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, r}:
      Pods.str(x, "name") <> Pods.names(r)

# String maps.

def Pods.map.put(k: String, v: J.Json, rec: +List<M.KV>) -> +List<M.KV>:
  match v:
    case J.JStr{s}:
      M.Meta.insert(k, s, rec)
    case _:
      rec

def Pods.map.go(ms: J.Json) -> +List<M.KV>:
  match ms:
    case J.JMem{k, v, t}:
      Pods.map.put(k, v, Pods.map.go(t))
    case _:
      Nil{}

# The string map of an object (Go map[string]string); other members drop.
def Pods.map(j: J.Json) -> +List<M.KV>:
  Pods.map.go(Pods.mems(j))

# Go m[k] = v for each pair in order: a later pair wins.
def Pods.put_all(xs: +List<M.KV>, m: +List<M.KV>) -> +List<M.KV>:
  match xs:
    case Nil{}:
      m
    case Con{M.KV{k, v}, r}:
      Pods.put_all(r, M.Meta.insert(k, v, m))

# Canonical form and semantic equality.

def Pods.norm.ins.if(c: Cmp, k: String, v: J.Json, kk: String, vv: J.Json, t: J.Json, rec: J.Json) -> J.Json:
  match c:
    case LT{}:
      J.JMem{k, v, J.JMem{kk, vv, t}}
    case EQ{}:
      J.JMem{k, v, J.JMem{kk, vv, t}}
    case GT{}:
      J.JMem{kk, vv, rec}

# Inserts a member into a key-sorted member chain.
def Pods.norm.ins(+k: String, +v: J.Json, ms: J.Json) -> J.Json:
  match ms:
    case J.JMem{+kk, vv, +t}:
      Pods.norm.ins.if(String.order(k, kk), k, v, kk, vv, t, Pods.norm.ins(k, v, t))
    case _:
      J.JMem{k, v, J.JNil{}}

def Pods.norm.obj(sem: Bool, k: String, rest: J.Json) -> J.Json:
  match sem:
    case True{}:
      rest
    case False{}:
      Pods.norm.ins(k, J.JObj{J.JNil{}}, rest)

# Drops null members and empty arrays (Go nil and omitempty), and with sem
# empty objects too (a Go struct's zero value).
def Pods.norm.put(sem: Bool, k: String, v: J.Json, rest: J.Json) -> J.Json:
  match v:
    case J.JNull{}:
      rest
    case J.JArr{J.JNil{}}:
      rest
    case J.JObj{J.JNil{}}:
      Pods.norm.obj(sem, k, rest)
    case x:
      Pods.norm.ins(k, x, rest)

def Pods.norm.go(+sem: Bool, j: J.Json) -> J.Json:
  match j:
    case J.JArr{xs}:
      J.JArr{Pods.norm.go(sem, xs)}
    case J.JObj{ms}:
      J.JObj{Pods.norm.go(sem, ms)}
    case J.JCons{h, t}:
      J.JCons{Pods.norm.go(sem, h), Pods.norm.go(sem, t)}
    case J.JMem{k, v, t}:
      Pods.norm.put(sem, k, Pods.norm.go(sem, v), Pods.norm.go(sem, t))
    case x:
      x

# The canonical form of a value: members sorted by key, null members and
# empty arrays dropped, at every depth.
def Pods.norm(j: J.Json) -> J.Json:
  Pods.norm.go(False{}, j)

# The canonical form for comparisons: empty objects drop too.
def Pods.snorm(j: J.Json) -> J.Json:
  Pods.norm.go(True{}, j)

def Pods.beq(a: Bool, b: Bool) -> Bool:
  match a b:
    case True{} True{}:
      True{}
    case False{} False{}:
      True{}
    case _ _:
      False{}

# Structural equality.
def Pods.eq(a: J.Json, b: J.Json) -> Bool:
  match a b:
    case J.JNull{} J.JNull{}:
      True{}
    case J.JBool{x} J.JBool{y}:
      Pods.beq(x, y)
    case J.JNum{x} J.JNum{y}:
      String.eq(x, y)
    case J.JStr{x} J.JStr{y}:
      String.eq(x, y)
    case J.JArr{x} J.JArr{y}:
      Pods.eq(x, y)
    case J.JObj{x} J.JObj{y}:
      Pods.eq(x, y)
    case J.JNil{} J.JNil{}:
      True{}
    case J.JCons{h, t} J.JCons{g, u}:
      Bool.and(Pods.eq(h, g), Pods.eq(t, u))
    case J.JMem{k, v, t} J.JMem{l, w, u}:
      Bool.and(String.eq(k, l), Bool.and(Pods.eq(v, w), Pods.eq(t, u)))
    case _ _:
      False{}

# apiequality.Semantic.DeepEqual on the JSON form: nil, empty and zero
# values are equal.
def Pods.same(a: J.Json, b: J.Json) -> Bool:
  Pods.eq(Pods.snorm(J.Json.obj([J.KV{"f", a}])), Pods.snorm(J.Json.obj([J.KV{"f", b}])))

def Pods.same_f(a: J.Json, b: J.Json) -> Bool:
  Pods.same(a, b)

def Pods.has_same(xs: List<&2, J.Json>, +x: J.Json) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{y, r}:
      Bool.or(Pods.same(y, x), Pods.has_same(r, x))

def Pods.add_new.if(dup: Bool, x: J.Json, xs: List<&2, J.Json>) -> List<&2, J.Json>:
  match dup:
    case True{}:
      xs
    case False{}:
      List.append(&2, J.Json, xs, [x])

def Pods.add_new.go(ys: List<&2, J.Json>, +xs: List<&2, J.Json>) -> List<&2, J.Json>:
  match ys:
    case Nil{}:
      xs
    case Con{+y, r}:
      Pods.add_new.go(r, Pods.add_new.if(Pods.has_same(xs, y), y, xs))

# xs, then each y not already in it (hasToleration-style full equality).
def Pods.add_new(xs: List<&2, J.Json>, ys: List<&2, J.Json>) -> List<&2, J.Json>:
  Pods.add_new.go(ys, xs)

# Strings.

def Pods.or_str.if(empty: Bool, a: String, b: String) -> String:
  match empty:
    case True{}:
      b
    case False{}:
      a

# a, or b when a is "".
def Pods.or_str(+a: String, b: String) -> String:
  Pods.or_str.if(String.is_empty(a), a, b)

def Pods.trim1.if(hit: Bool, s: String) -> String:
  match hit:
    case True{}:
      +t = s
      String.take(t, Nat.sub(String.length(t), 1n))
    case False{}:
      s

# strings.TrimSuffix(s, suffix) for a one-character suffix.
def Pods.trim1(+s: String, suffix: String) -> String:
  Pods.trim1.if(String.ends_with(s, suffix), s)

def Pods.subst.c(hit: Bool, c: Char, to: Char) -> Char:
  match hit:
    case True{}:
      to
    case False{}:
      c

# Every `from` replaced by `to`.
def Pods.subst(s: String, +from: Char, +to: Char) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+c, t}:
      SCon{Pods.subst.c(Char.is_eq(c, from), c, to), Pods.subst(t, from, to)}

def Pods.replace1.if(hit: Bool, s: String, old: String, nw: String, rec: String) -> String:
  match hit:
    case True{}:
      nw ++ String.drop(s, String.length(old))
    case False{}:
      rec

# strings.Replace(s, old, new, 1), for a non-empty old.
def Pods.replace1(s: String, +old: String, +nw: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+c, +t}:
      Pods.replace1.if(String.starts_with(SCon{c, t}, old), SCon{c, t}, old, nw, SCon{c, Pods.replace1(t, old, nw)})

def Pods.until_slash.if(hit: Bool, c: Char, rec: String) -> String:
  match hit:
    case True{}:
      SNil{}
    case False{}:
      SCon{c, rec}

def Pods.until_slash(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+c, t}:
      Pods.until_slash.if(Char.is_eq(c, '/'), c, Pods.until_slash(t))

def Pods.sins.if(c: Cmp, x: String, y: String, r: List<&2, String>, rec: List<&2, String>) -> List<&2, String>:
  match c:
    case LT{}:
      x <> y <> r
    case EQ{}:
      x <> y <> r
    case GT{}:
      y <> rec

def Pods.sins(+x: String, xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      [x]
    case Con{+y, +r}:
      Pods.sins.if(String.order(x, y), x, y, r, Pods.sins(x, r))

# sort.Strings (byte order).
def Pods.sort(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, r}:
      Pods.sins(x, Pods.sort(r))

def Pods.dedup.if(seen: Bool, x: String, rec: List<&2, String>) -> List<&2, String>:
  match seen:
    case True{}:
      rec
    case False{}:
      x <> rec

# deleteDuplicates: the first of each string, in order.
def Pods.dedup.go(xs: List<&2, String>, +seen: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, r}:
      Pods.dedup.if(M.Meta.elem(x, seen), x, Pods.dedup.go(r, x <> seen))

def Pods.dedup(xs: List<&2, String>) -> List<&2, String>:
  Pods.dedup.go(xs, [])

# Versions.

# v < a.b.c
def Pods.ver_lt(v: Ver, +a: U32, +b: U32, c: U32) -> Bool:
  match v:
    case Ver{+x, +y, z}:
      Bool.or(U32.is_lt(x, a), Bool.and(U32.is_eq(x, a),
        Bool.or(U32.is_lt(y, b), Bool.and(U32.is_eq(y, b), U32.is_lt(z, c)))))

# A known version below a.b.c.
def Pods.below(m: Maybe<&2, Ver>, a: U32, b: U32, c: U32) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{v}:
      Pods.ver_lt(v, a, b, c)

# A known version at or above a.b.c.
def Pods.at_least(m: Maybe<&2, Ver>, a: U32, b: U32, c: U32) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{v}:
      Bool.not(Pods.ver_lt(v, a, b, c))

# The pod's fields.

def Pods.meta(v: J.Json) -> J.Json:
  J.Json.get(v, "metadata")

def Pods.spec(v: J.Json) -> J.Json:
  J.Json.get(v, "spec")

def Pods.status(v: J.Json) -> J.Json:
  J.Json.get(v, "status")

def Pods.name_of(v: J.Json) -> String:
  Pods.str(J.Json.get(v, "metadata"), "name")

def Pods.ns_of(v: J.Json) -> String:
  Pods.str(J.Json.get(v, "metadata"), "namespace")

def Pods.uid_of(v: J.Json) -> String:
  Pods.str(J.Json.get(v, "metadata"), "uid")

def Pods.labels_of(v: J.Json) -> +List<M.KV>:
  Pods.map(J.Json.get(J.Json.get(v, "metadata"), "labels"))

def Pods.annotations_of(v: J.Json) -> +List<M.KV>:
  Pods.map(J.Json.get(J.Json.get(v, "metadata"), "annotations"))

def Pods.deleting(v: J.Json) -> Bool:
  Pods.has(J.Json.get(v, "metadata"), "deletionTimestamp")

def Pods.node_of(v: J.Json) -> String:
  Pods.str(J.Json.get(v, "spec"), "nodeName")

# The metadata record meta.bend reads.
def Pods.obj(+v: J.Json) -> M.Obj:
  M.Obj{Pods.name_of(v), Pods.ns_of(v), Pods.uid_of(v), Pods.kind(), Pods.deleting(v), Pods.labels_of(v), Pods.annotations_of(v)}


def Pods.pick(c: Bool, a: String, b: String) -> String:
  match c:
    case True{}:
      a
    case False{}:
      b

# Host names (mappings.VirtualToHostName in single-namespace mode).

# The host name of the pod.
def Pods.host_name(+cfg: Cfg, +v: J.Json) -> String:
  N.Names.host_name(Pods.name_of(v), Pods.ns_of(v), Pods.cfg.vc(cfg))

def Pods.endpoints_name.if(special: Bool, vc: String, name: String, ns: String) -> String:
  match special:
    case True{}:
      vc
    case False{}:
      N.Names.host_name(name, ns, vc)

# The Endpoints mapper: default/kubernetes is the vcluster's own service.
def Pods.endpoints_name(+vc: String, +name: String, +ns: String) -> String:
  Pods.endpoints_name.if(Bool.and(String.eq(name, "kubernetes"), String.eq(ns, "default")), vc, name, ns)

# Image references.

# vcluster config Image.String().
def Pods.image_ref(+registry: String, +repo: String, +tag: String) -> String:
  +r = Bool.not(String.is_empty(registry))
  a = Pods.pick(r, registry ++ "/", "")
  b = Pods.pick(Bool.and(r, Bool.and(Bool.not(String.is_empty(repo)), Bool.not(String.contains(repo, "/")))), "library/", "")
  c = Pods.pick(Bool.not(String.is_empty(tag)), ":" ++ tag, "")
  a ++ b ++ repo ++ c

# The rewrite-hosts image (NewTranslator): the registry is the first set of
# controlPlane.advanced.defaultImageRegistry, the image's registry and
# "docker.io".
def Pods.hosts_image(default_registry: String, registry: String, repo: String, tag: String) -> String:
  Pods.image_ref(Pods.or_str(default_registry, Pods.or_str(registry, "docker.io")), repo, tag)

# translateImage.
def Pods.image(images: +List<M.KV>, +img: String) -> String:
  Maybe.default(&2, String, M.Meta.get(img, images), img)

# Labels.

# translate.HostLabelNamespace.
def Pods.ns_label_key(vc: String, k: String) -> String:
  M.Meta.convert(M.Meta.namespace_label_prefix(), vc, k)

# The namespace labels, under their host keys, over m.
def Pods.ns_labels(+vc: String, nl: +List<M.KV>, m: +List<M.KV>) -> +List<M.KV>:
  match nl:
    case Nil{}:
      m
    case Con{M.KV{k, v}, r}:
      Pods.ns_labels(vc, r, M.Meta.insert(Pods.ns_label_key(vc, k), v, m))

# HostLabels(vPod, nil) plus the namespace labels.
def Pods.host_labels(+cfg: Cfg, nl: +List<M.KV>, +v: J.Json) -> +List<M.KV>:
  Pods.ns_labels(Pods.cfg.vc(cfg), nl, Maybe.default(&2, List<&2, M.KV>,
    M.Meta.host_labels_map(Pods.cfg.vc(cfg), Pods.cfg.target(cfg), Some{Pods.labels_of(v)}, None{}, Pods.ns_of(v), True{}), []))

# The host labels as an object, the marker labels first.
def Pods.host_labels_json(+cfg: Cfg, nl: +List<M.KV>, +v: J.Json) -> J.Json:
  Pods.with(M.Meta.marker_label(), J.JStr{Pods.cfg.vc(cfg)},
    Pods.with(M.Meta.namespace_label(), J.JStr{Pods.ns_of(v)},
      Pods.obj_of(M.Meta.delete(M.Meta.marker_label(), M.Meta.delete(M.Meta.namespace_label(), Pods.host_labels(cfg, nl, v))))))

# Annotations.

def Pods.label_lines(m: +List<M.KV>) -> List<&2, String>:
  match m:
    case Nil{}:
      Nil{}
    case Con{M.KV{k, v}, r}:
      (k ++ "=" ++ J.Json.quote(v)) <> Pods.label_lines(r)

# LabelsAnnotation: the sorted lines k=<JSON of v>, joined by "\n".
def Pods.labels_text(m: +List<M.KV>) -> String:
  String.join(Pods.sort(Pods.label_lines(m)), "\n")

def Pods.refs(v: J.Json) -> List<&2, J.Json>:
  J.Json.items(J.Json.get(J.Json.get(v, "metadata"), "ownerReferences"))

def Pods.controller.if(hit: Bool, r: J.Json, rec: Maybe<&2, J.Json>) -> Maybe<&2, J.Json>:
  match hit:
    case True{}:
      Some{r}
    case False{}:
      rec

# metav1.GetControllerOf: the first owner reference with controller true.
def Pods.controller(rs: List<&2, J.Json>) -> Maybe<&2, J.Json>:
  match rs:
    case Nil{}:
      None{}
    case Con{+r, t}:
      Pods.controller.if(Pods.is_true(Pods.get(r, "controller")), r, Pods.controller(t))

def Pods.set_kind_ok(+k: String) -> Bool:
  Bool.or(String.eq(k, "DaemonSet"), Bool.or(String.eq(k, "Job"), Bool.or(String.eq(k, "ReplicaSet"), String.eq(k, "StatefulSet"))))

def Pods.owner_set_kind.if(hit: Bool, k: String, rec: Maybe<&2, String>) -> Maybe<&2, String>:
  match hit:
    case True{}:
      Some{k}
    case False{}:
      rec

# The kind of the first apps/v1 DaemonSet, Job, ReplicaSet or StatefulSet owner.
def Pods.owner_set_kind(rs: List<&2, J.Json>) -> Maybe<&2, String>:
  match rs:
    case Nil{}:
      None{}
    case Con{+r, t}:
      Pods.owner_set_kind.if(Bool.and(String.eq(Pods.str(r, "apiVersion"), "apps/v1"), Pods.set_kind_ok(Pods.str(r, "kind"))),
        Pods.str(r, "kind"), Pods.owner_set_kind(t))

def Pods.opt_mem.if(isnull: Bool, k: String, v: J.Json, t: J.Json) -> J.Json:
  match isnull:
    case True{}:
      t
    case False{}:
      J.JMem{k, v, t}

def Pods.opt_mem(k: String, +v: J.Json, t: J.Json) -> J.Json:
  Pods.opt_mem.if(J.Json.is_null(v), k, v, t)

# An owner reference with its members in Go's field order.
def Pods.ref_go(+r: J.Json) -> J.Json:
  J.JObj{J.JMem{"apiVersion", J.JStr{Pods.str(r, "apiVersion")}, J.JMem{"kind", J.JStr{Pods.str(r, "kind")},
    J.JMem{"name", J.JStr{Pods.str(r, "name")}, J.JMem{"uid", J.JStr{Pods.str(r, "uid")},
      Pods.opt_mem("controller", Pods.get(r, "controller"), Pods.opt_mem("blockOwnerDeletion", Pods.get(r, "blockOwnerDeletion"), J.JNil{}))}}}}}

def Pods.refs_go(rs: List<&2, J.Json>) -> List<&2, J.Json>:
  match rs:
    case Nil{}:
      Nil{}
    case Con{r, t}:
      Pods.ref_go(r) <> Pods.refs_go(t)

# json.Marshal(vPod.OwnerReferences).
def Pods.refs_text(rs: List<&2, J.Json>) -> String:
  J.Json.show(J.Json.arr(Pods.refs_go(rs)))

def Pods.ann.labels.if(has: Bool, +v: J.Json, a: +List<M.KV>) -> +List<M.KV>:
  match has:
    case True{}:
      a
    case False{}:
      M.Meta.insert(Pods.labels_annotation(), Pods.labels_text(Pods.labels_of(v)), a)

def Pods.ann.labels(+v: J.Json, +a: +List<M.KV>) -> +List<M.KV>:
  Pods.ann.labels.if(M.Meta.has(Pods.labels_annotation(), a), v, a)

def Pods.ann.ds(hit: Bool, a: +List<M.KV>) -> +List<M.KV>:
  match hit:
    case True{}:
      M.Meta.insert(Pods.autoscaler_daemonset_annotation(), "true", a)
    case False{}:
      a

def Pods.ann.autoscaler.c(c: Maybe<&2, J.Json>, a: +List<M.KV>) -> +List<M.KV>:
  match c:
    case None{}:
      M.Meta.insert(Pods.autoscaler_annotation(), "false", a)
    case Some{r}:
      Pods.ann.ds(String.eq(Pods.str(r, "kind"), "DaemonSet"), M.Meta.insert(Pods.autoscaler_annotation(), "true", a))

def Pods.ann.autoscaler.if(has: Bool, rs: List<&2, J.Json>, a: +List<M.KV>) -> +List<M.KV>:
  match has:
    case True{}:
      a
    case False{}:
      Pods.ann.autoscaler.c(Pods.controller(rs), a)

def Pods.ann.autoscaler(rs: List<&2, J.Json>, +a: +List<M.KV>) -> +List<M.KV>:
  Pods.ann.autoscaler.if(M.Meta.has(Pods.autoscaler_annotation(), a), rs, a)

def Pods.ann.set_kind(k: Maybe<&2, String>, a: +List<M.KV>) -> +List<M.KV>:
  match k:
    case None{}:
      a
    case Some{x}:
      M.Meta.insert(Pods.owner_set_kind_annotation(), x, a)

def Pods.ann.owners.if(skip: Bool, +rs: List<&2, J.Json>, a: +List<M.KV>) -> +List<M.KV>:
  match skip:
    case True{}:
      a
    case False{}:
      Pods.ann.set_kind(Pods.owner_set_kind(rs), M.Meta.insert(Pods.owner_references_annotation(), Pods.refs_text(rs), a))

def Pods.ann.owners(+rs: List<&2, J.Json>, +a: +List<M.KV>) -> +List<M.KV>:
  Pods.ann.owners.if(Bool.or(M.Meta.has(Pods.owner_references_annotation(), a), List.is_empty(&2, J.Json, rs)), rs, a)

def Pods.ann.hosts(on: Bool, a: +List<M.KV>) -> +List<M.KV>:
  match on:
    case True{}:
      M.Meta.insert(Pods.hosts_rewritten_annotation(), "true", a)
    case False{}:
      a

# The pod-local annotations (vcluster.loft.sh/namespace, name, uid,
# service-account-name, labels), the autoscaler and owner annotations.
def Pods.ann.local(+v: J.Json, a0: +List<M.KV>) -> +List<M.KV>:
  +va = Pods.annotations_of(v)
  a1 = M.Meta.insert(Pods.namespace_annotation(), Pods.or_str(M.Meta.lookup(Pods.namespace_annotation(), va), Pods.ns_of(v)), a0)
  a2 = M.Meta.insert(Pods.name_annotation(), Pods.or_str(M.Meta.lookup(Pods.name_annotation(), va), Pods.name_of(v)), a1)
  a3 = M.Meta.insert(Pods.uid_annotation(), Pods.or_str(M.Meta.lookup(Pods.uid_annotation(), va), Pods.uid_of(v)), a2)
  a4 = M.Meta.insert(Pods.sa_name_annotation(), Pods.or_str(M.Meta.lookup(Pods.sa_name_annotation(), va), Pods.str(Pods.spec(v), "serviceAccountName")), a3)
  Pods.ann.owners(Pods.refs(v), Pods.ann.autoscaler(Pods.refs(v), Pods.ann.labels(v, a4)))

# HostAnnotations(vPod, copy of vPod): the copied annotations, the managed
# annotations list and the object-* keys.
def Pods.ann.base(+cfg: Cfg, +v: J.Json) -> +List<M.KV>:
  M.Meta.host_annotations(Pods.obj(v), Some{M.Obj{Pods.host_name(cfg, v), Pods.cfg.target(cfg), "", Pods.kind(), False{},
    Pods.labels_of(v), Pods.annotations_of(v)}}, [])

# Environment variables (ServicesToEnvironmentVariables, envvars.go).

def Pods.env_name(s: String) -> String:
  String.to_upper(Pods.subst(s, '-', '_'))

def Pods.has_ip(+ip: String) -> Bool:
  Bool.and(Bool.not(String.is_empty(ip)), Bool.not(String.eq(ip, "None")))

# net.JoinHostPort.
def Pods.host_port(+ip: String, +port: String) -> String:
  Pods.pick(String.contains(ip, ":"), "[" ++ ip ++ "]:" ++ port, ip ++ ":" ++ port)

def Pods.link_first(first: Bool, k: String, v: String) -> List<&2, M.KV>:
  match first:
    case True{}:
      [M.KV{k, v}]
    case False{}:
      []

# makeLinkVariables for one port.
def Pods.link_vars(+prefix: String, +ip: String, first: Bool, +p: J.Json) -> List<&2, M.KV>:
  +port = Pods.num(Pods.get(p, "port"))
  +proto = Pods.or_str(Pods.str(p, "protocol"), "TCP")
  +lower = String.to_lower(proto)
  +hp = Pods.host_port(ip, port)
  +pp = prefix ++ "_PORT_" ++ port ++ "_" ++ String.to_upper(proto)
  List.append(&2, M.KV, Pods.link_first(first, prefix ++ "_PORT", lower ++ "://" ++ hp),
    [M.KV{pp, lower ++ "://" ++ hp}, M.KV{pp ++ "_PROTO", lower}, M.KV{pp ++ "_PORT", port}, M.KV{pp ++ "_ADDR", ip}])

def Pods.port_vars(+prefix: String, +ip: String, ps: List<&2, J.Json>, first: Bool) -> List<&2, M.KV>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{p, r}:
      List.append(&2, M.KV, Pods.link_vars(prefix, ip, first, p), Pods.port_vars(prefix, ip, r, False{}))

def Pods.named_port.if(unnamed: Bool, base: String, +p: J.Json, rec: List<&2, M.KV>) -> List<&2, M.KV>:
  match unnamed:
    case True{}:
      rec
    case False{}:
      M.KV{base ++ "_" ++ Pods.env_name(Pods.str(p, "name")), Pods.num(Pods.get(p, "port"))} <> rec

def Pods.named_ports(+base: String, ps: List<&2, J.Json>) -> List<&2, M.KV>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{+p, r}:
      Pods.named_port.if(String.is_empty(Pods.str(p, "name")), base, p, Pods.named_ports(base, r))

# buildEnvironmentVariables for one service with ports (a service without
# ports panics in Go; it adds nothing here).
def Pods.service_vars.if(empty: Bool, +name: String, +ip: String, +ps: List<&2, J.Json>) -> List<&2, M.KV>:
  match empty:
    case True{}:
      Nil{}
    case False{}:
      +prefix = Pods.env_name(name)
      +p0 = Pods.num(Pods.get(Maybe.default(&2, J.Json, List.head(&2, J.Json, ps), J.JNull{}), "port"))
      List.append(&2, M.KV, [M.KV{prefix ++ "_SERVICE_HOST", ip}, M.KV{prefix ++ "_SERVICE_PORT", p0}],
        List.append(&2, M.KV, Pods.named_ports(prefix ++ "_SERVICE_PORT", ps), Pods.port_vars(prefix, ip, ps, True{})))

def Pods.service_env1.if(on: Bool, +s: J.Json) -> List<&2, M.KV>:
  match on:
    case True{}:
      +ps = Pods.items(Pods.get(Pods.spec(s), "ports"))
      Pods.service_vars.if(List.is_empty(&2, J.Json, ps), Pods.name_of(s), Pods.str(Pods.spec(s), "clusterIP"), ps)
    case False{}:
      Nil{}

def Pods.service_env1(+s: J.Json) -> List<&2, M.KV>:
  Pods.service_env1.if(Pods.has_ip(Pods.str(Pods.spec(s), "clusterIP")), s)

def Pods.services_env.go(ss: List<&2, J.Json>) -> List<&2, M.KV>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, r}:
      List.append(&2, M.KV, Pods.service_env1(s), Pods.services_env.go(r))

def Pods.services_env.links(links: Bool, ss: List<&2, J.Json>) -> List<&2, M.KV>:
  match links:
    case True{}:
      Pods.services_env.go(ss)
    case False{}:
      Nil{}

# The eight KUBERNETES_* variables, IP being the vcluster service's IP.
def Pods.kube_env(+ip: String) -> List<&2, M.KV>:
  [M.KV{"KUBERNETES_PORT", "tcp://" ++ ip ++ ":443"}, M.KV{"KUBERNETES_PORT_443_TCP", "tcp://" ++ ip ++ ":443"},
   M.KV{"KUBERNETES_PORT_443_TCP_ADDR", ip}, M.KV{"KUBERNETES_PORT_443_TCP_PORT", "443"},
   M.KV{"KUBERNETES_PORT_443_TCP_PROTO", "tcp"}, M.KV{"KUBERNETES_SERVICE_HOST", ip},
   M.KV{"KUBERNETES_SERVICE_PORT", "443"}, M.KV{"KUBERNETES_SERVICE_PORT_HTTPS", "443"}]

# ServicesToEnvironmentVariables(enableServiceLinks, services, kubeIP): the
# services' variables when service links are on (a later service wins a
# clash; Go's map order is random there), then the KUBERNETES_* ones.
def Pods.services_env(links: Bool, ss: List<&2, J.Json>, kube_ip: String) -> +List<M.KV>:
  Pods.put_all(Pods.kube_env(kube_ip), Pods.put_all(Pods.services_env.links(links, ss), []))

# Field references (translateFieldRef).

def Pods.is_label_ref(+p: String) -> Bool:
  Bool.and(String.starts_with(p, "metadata.labels['"), Bool.and(String.ends_with(p, "']"), Nat.is_ge(String.length(p), 20n)))

def Pods.label_ref_key(+p: String) -> String:
  String.take(String.drop(p, 17n), Nat.sub(String.length(p), 19n))

def Pods.ann_ref(k: String) -> String:
  "metadata.annotations['" ++ k ++ "']"

def Pods.fixed_paths() -> +List<M.KV>:
  [M.KV{"metadata.labels", Pods.ann_ref(Pods.labels_annotation())},
   M.KV{"metadata.name", Pods.ann_ref(Pods.name_annotation())},
   M.KV{"metadata.namespace", Pods.ann_ref(Pods.namespace_annotation())},
   M.KV{"metadata.uid", Pods.ann_ref(Pods.uid_annotation())},
   M.KV{"spec.serviceAccountName", Pods.ann_ref(Pods.sa_name_annotation())}]

def Pods.field_path.if(lab: Bool, vc: String, +p: String) -> String:
  match lab:
    case True{}:
      "metadata.labels['" ++ M.Meta.host_label(vc, Pods.label_ref_key(p)) ++ "']"
    case False{}:
      Maybe.default(&2, String, M.Meta.get(p, Pods.fixed_paths()), p)

# The host field path of a virtual field path.
def Pods.field_path(vc: String, +p: String) -> String:
  Pods.field_path.if(Pods.is_label_ref(p), vc, p)

def Pods.tr_fr.if(has: Bool, vc: String, +j: J.Json) -> J.Json:
  match has:
    case True{}:
      Pods.with("fieldRef", Pods.with("fieldPath", J.JStr{Pods.field_path(vc, Pods.str(Pods.get(j, "fieldRef"), "fieldPath"))},
        Pods.get(j, "fieldRef")), j)
    case False{}:
      j

# Translates the fieldRef of j, if any.
def Pods.tr_fr(vc: String, +j: J.Json) -> J.Json:
  Pods.tr_fr.if(Pods.has(j, "fieldRef"), vc, j)

def Pods.tr_frs(+vc: String, xs: List<&2, J.Json>) -> List<&2, J.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, r}:
      Pods.tr_fr(vc, x) <> Pods.tr_frs(vc, r)

# Container environment (TranslateContainerEnv).

def Pods.tr_ref.if(empty: Bool, +k: String, vc: String, ns: String, +j: J.Json) -> J.Json:
  match empty:
    case True{}:
      j
    case False{}:
      Pods.with(k, Pods.with("name", J.JStr{N.Names.host_name(Pods.str(Pods.get(j, k), "name"), ns, vc)}, Pods.get(j, k)), j)

# The name under member k of j, translated when it is set.
def Pods.tr_ref(+k: String, vc: String, ns: String, +j: J.Json) -> J.Json:
  Pods.tr_ref.if(String.is_empty(Pods.str(Pods.get(j, k), "name")), k, vc, ns, j)

def Pods.tr_value_from(+vc: String, +ns: String, vf: J.Json) -> J.Json:
  Pods.tr_ref("secretKeyRef", vc, ns, Pods.tr_ref("configMapKeyRef", vc, ns, Pods.tr_fr(vc, vf)))

def Pods.tr_env(+vc: String, +ns: String, +e: J.Json) -> J.Json:
  Pods.with_opt("valueFrom", Pods.when(Pods.get(e, "valueFrom"), Pods.tr_value_from(vc, ns, Pods.get(e, "valueFrom"))), e)

def Pods.tr_envs(+vc: String, +ns: String, es: List<&2, J.Json>) -> List<&2, J.Json>:
  match es:
    case Nil{}:
      Nil{}
    case Con{e, r}:
      Pods.tr_env(vc, ns, e) <> Pods.tr_envs(vc, ns, r)

def Pods.tr_env_from(+vc: String, +ns: String, e: J.Json) -> J.Json:
  Pods.tr_ref("secretRef", vc, ns, Pods.tr_ref("configMapRef", vc, ns, e))

def Pods.tr_env_froms(+vc: String, +ns: String, es: List<&2, J.Json>) -> List<&2, J.Json>:
  match es:
    case Nil{}:
      Nil{}
    case Con{e, r}:
      Pods.tr_env_from(vc, ns, e) <> Pods.tr_env_froms(vc, ns, r)

def Pods.extra_env.if(skip: Bool, k: String, v: String, rec: List<&2, J.Json>) -> List<&2, J.Json>:
  match skip:
    case True{}:
      rec
    case False{}:
      J.Json.obj([J.KV{"name", J.JStr{k}}, J.KV{"value", J.JStr{v}}]) <> rec

# The service variables the container does not define, sorted by name.
def Pods.extra_env(m: +List<M.KV>, +names: List<&2, String>) -> List<&2, J.Json>:
  match m:
    case Nil{}:
      Nil{}
    case Con{M.KV{+k, v}, r}:
      Pods.extra_env.if(M.Meta.elem(k, names), k, v, Pods.extra_env(r, names))

# The service variables first, then the container's own, translated.
def Pods.env_list(+vc: String, +ns: String, env: +List<M.KV>, +es: List<&2, J.Json>) -> List<&2, J.Json>:
  a b = Pods.extra_env(env, Pods.names(es)) Pods.tr_envs(vc, ns, es)
  List.append(&2, J.Json, a, b)

# Volume mounts.

def Pods.hosts_mount() -> J.Json:
  J.Json.obj([J.KV{"mountPath", J.JStr{"/etc/hosts"}}, J.KV{"name", J.JStr{Pods.hosts_name()}}, J.KV{"subPath", J.JStr{"hosts"}}])

def Pods.hosts_for(kind: CKind, hosts: Bool, +cname: String) -> Bool:
  match kind:
    case CMain{}:
      hosts
    case CInit{}:
      Bool.and(hosts, Bool.not(String.eq(cname, Pods.hosts_name())))
    case CEph{}:
      hosts

def Pods.mounts.hosts(on: Bool, ms: List<&2, J.Json>) -> List<&2, J.Json>:
  match on:
    case True{}:
      List.append(&2, J.Json, ms, [Pods.hosts_mount()])
    case False{}:
      ms

def Pods.is_phys(+name: String) -> Bool:
  String.ends_with(name, "vcluster-physical")

def Pods.hp.pl(+name: String, +p: String) -> Bool:
  Bool.and(String.eq(Pods.trim1(p, "/"), "/var/log/pods"), Bool.not(Pods.is_phys(name)))

def Pods.hp.p1(pl: Bool, +vpath: String, p: String) -> String:
  Pods.pick(pl, vpath ++ "/log/pods", p)

def Pods.hp.ku(+name: String, +p1: String) -> Bool:
  Bool.and(Bool.not(Pods.is_phys(name)), String.eq(Pods.trim1(p1, "/"), "/var/lib/kubelet/pods"))

def Pods.hp.sub(+name: String, +p1: String) -> Bool:
  Bool.and(Bool.not(Pods.is_phys(name)), String.starts_with(p1, "/var/lib/kubelet/pods/"))

def Pods.sub_path.x(empty: Bool, x: String, +uid: String, +p: String) -> String:
  match empty:
    case True{}:
      p
    case False{}:
      Pods.replace1(p, uid, x)

def Pods.sub_path.h(h: Maybe<&2, String>, +uid: String, +p: String) -> String:
  match h:
    case None{}:
      p
    case Some{+x}:
      Pods.sub_path.x(String.is_empty(x), x, uid, p)

def Pods.sub_path.if(empty: Bool, h: Maybe<&2, String>, +uid: String, +p: String) -> String:
  match empty:
    case True{}:
      p
    case False{}:
      Pods.sub_path.h(h, uid, p)

# translateKubeletSubPath: the virtual pod UID in
# /var/lib/kubelet/pods/<uid>/... replaced by its host pod's UID.
def Pods.sub_path(+uids: +List<M.KV>, +p: String) -> String:
  +uid = Pods.until_slash(String.drop(p, 22n))
  Pods.sub_path.if(String.is_empty(uid), M.Meta.get(uid, uids), uid, p)

def Pods.hp.p2(ku: Bool, sub: Bool, +vpath: String, +uids: +List<M.KV>, +p1: String) -> String:
  match ku:
    case True{}:
      vpath ++ "/kubelet/pods"
    case False{}:
      match sub:
        case True{}:
          Pods.sub_path(uids, p1)
        case False{}:
          p1

def Pods.hp.lg(+p2: String) -> Bool:
  String.eq(Pods.trim1(p2, "/"), "/var/log")

# The host path kinds of a volume, in rewriteHostPaths' order: each test
# sees the path the previous one rewrote.
def Pods.hp.kinds.if(on: Bool, +vpath: String, +name: String, +p0: String) -> Reg:
  match on:
    case False{}:
      Reg{False{}, False{}, False{}}
    case True{}:
      +pl = Pods.hp.pl(name, p0)
      +p1 = Pods.hp.p1(pl, vpath, p0)
      +ku = Pods.hp.ku(name, p1)
      Reg{pl, ku, Pods.hp.lg(Pods.hp.p2(ku, False{}, vpath, [], p1))}

def Pods.hp.kinds(+vpath: String, +vol: J.Json) -> Reg:
  Pods.hp.kinds.if(Pods.has(vol, "hostPath"), vpath, Pods.str(vol, "name"), Pods.str(Pods.get(vol, "hostPath"), "path"))

# The rewritten host path of a hostPath volume.
def Pods.hp.path(+vpath: String, +uids: +List<M.KV>, +name: String, +p0: String) -> String:
  +pl = Pods.hp.pl(name, p0)
  +p1 = Pods.hp.p1(pl, vpath, p0)
  +ku = Pods.hp.ku(name, p1)
  +p2 = Pods.hp.p2(ku, Pods.hp.sub(name, p1), vpath, uids, p1)
  Pods.pick(Pods.hp.lg(p2), vpath ++ "/log", p2)

def Pods.reg.get(k: HK, r: Reg) -> Bool:
  match k:
    case HPL{}:
      match r:
        case Reg{pl, ku, lg}:
          pl
    case HKU{}:
      match r:
        case Reg{pl, ku, lg}:
          ku
    case HLG{}:
      match r:
        case Reg{pl, ku, lg}:
          lg

def Pods.reg.set(k: HK, r: Reg) -> Reg:
  match k:
    case HPL{}:
      match r:
        case Reg{pl, ku, lg}:
          Reg{True{}, ku, lg}
    case HKU{}:
      match r:
        case Reg{pl, ku, lg}:
          Reg{pl, True{}, lg}
    case HLG{}:
      match r:
        case Reg{pl, ku, lg}:
          Reg{pl, ku, True{}}

# The physical mount path of a kind (PhysicalPodLogVolumeMountPath, ...).
def Pods.hk.mount(k: HK) -> String:
  match k:
    case HPL{}:
      "/var/vcluster/physical/log/pods"
    case HKU{}:
      "/var/vcluster/physical/kubelet/pods"
    case HLG{}:
      "/var/vcluster/physical/log"

# The original host path of a kind.
def Pods.hk.host(k: HK) -> String:
  match k:
    case HPL{}:
      "/var/log/pods"
    case HKU{}:
      "/var/lib/kubelet/pods"
    case HLG{}:
      "/var/log"

def Pods.phys_copy.if(hit: Bool, m: J.Json, +vname: String, +mp: String, rec: List<&2, J.Json>) -> List<&2, J.Json>:
  match hit:
    case True{}:
      Pods.with("name", J.JStr{vname ++ "-vcluster-physical"}, Pods.with("mountPath", J.JStr{mp}, m)) <> rec
    case False{}:
      rec

# A physical copy of each mount of volume vname.
def Pods.phys_copies(ms: List<&2, J.Json>, +vname: String, +mp: String) -> List<&2, J.Json>:
  match ms:
    case Nil{}:
      Nil{}
    case Con{+m, r}:
      Pods.phys_copy.if(String.eq(Pods.str(m, "name"), vname), m, vname, mp, Pods.phys_copies(r, vname, mp))

def Pods.pm.fin(none: Bool, k: HK, reg: Reg, ms: List<&2, J.Json>, nw: List<&2, J.Json>) -> Reg & List<&2, J.Json>:
  match none:
    case True{}:
      (reg, ms)
    case False{}:
      (Pods.reg.set(k, reg), List.append(&2, J.Json, ms, nw))

def Pods.pm.go(+k: HK, +vname: String, reg: Reg, +ms: List<&2, J.Json>) -> Reg & List<&2, J.Json>:
  +nw = Pods.phys_copies(ms, vname, Pods.hk.mount(k))
  Pods.pm.fin(List.is_empty(&2, J.Json, nw), k, reg, ms, nw)

def Pods.pm.add.if(skip: Bool, +k: HK, +vname: String, +reg: Reg, +ms: List<&2, J.Json>) -> Reg & List<&2, J.Json>:
  match skip:
    case True{}:
      (reg, ms)
    case False{}:
      Pods.pm.go(k, vname, reg, ms)

# addPhysicalPathToVolumesAndCorrectContainers for one container.
def Pods.pm.add(on: Bool, +k: HK, +vname: String, +reg: Reg, +ms: List<&2, J.Json>) -> Reg & List<&2, J.Json>:
  match on:
    case False{}:
      (reg, ms)
    case True{}:
      Pods.pm.add.if(Bool.or(Pods.reg.get(k, reg), List.is_empty(&2, J.Json, ms)), k, vname, reg, ms)

# A match cannot take a computed pair, so each step gets the pair as a
# parameter.
def Pods.pm.lg(lg: Bool, +vname: String, st: Reg & List<&2, J.Json>) -> Reg & List<&2, J.Json>:
  (r, m) = st
  Pods.pm.add(lg, HLG{}, vname, r, m)

def Pods.pm.ku(ku: Bool, lg: Bool, +vname: String, st: Reg & List<&2, J.Json>) -> Reg & List<&2, J.Json>:
  (r, m) = st
  Pods.pm.lg(lg, vname, Pods.pm.add(ku, HKU{}, vname, r, m))

def Pods.pm.kinds(k: Reg, +vname: String, st: Reg & List<&2, J.Json>) -> Reg & List<&2, J.Json>:
  match k:
    case Reg{pl, ku, lg}:
      (r1, m1) = st
      Pods.pm.ku(ku, lg, vname, Pods.pm.add(pl, HPL{}, vname, r1, m1))

def Pods.pm.vols(vols: List<&2, J.Json>, +vpath: String, st: Reg & List<&2, J.Json>) -> Reg & List<&2, J.Json>:
  match vols:
    case Nil{}:
      st
    case Con{+vol, r}:
      Pods.pm.vols(r, vpath, Pods.pm.kinds(Pods.hp.kinds(vpath, vol), Pods.str(vol, "name"), st))

def Pods.pm.mounts(st: Reg & List<&2, J.Json>) -> List<&2, J.Json>:
  (r, m) = st
  m

# The physical mounts the host path mapper adds to a container.
def Pods.phys.if(on: Bool, +vpath: String, vols: List<&2, J.Json>, ms: List<&2, J.Json>) -> List<&2, J.Json>:
  match on:
    case False{}:
      ms
    case True{}:
      Pods.pm.mounts(Pods.pm.vols(vols, vpath, (Reg{False{}, False{}, False{}}, ms)))

def Pods.is_hp_mount(+p: String) -> Bool:
  +t = Pods.trim1(p, "/")
  Bool.or(String.eq(t, "/var/log/pods"), Bool.or(String.eq(t, "/var/lib/kubelet/pods"), String.eq(t, "/var/log")))

def Pods.prop1.if(hit: Bool, m: J.Json) -> J.Json:
  match hit:
    case True{}:
      Pods.with("mountPropagation", J.JStr{"HostToContainer"}, m)
    case False{}:
      m

def Pods.prop(ms: List<&2, J.Json>) -> List<&2, J.Json>:
  match ms:
    case Nil{}:
      Nil{}
    case Con{+m, r}:
      Pods.prop1.if(Pods.is_hp_mount(Pods.str(m, "mountPath")), m) <> Pods.prop(r)

# ensureMountPropagation (it runs when the pod has volumes).
def Pods.prop.if(on: Bool, ms: List<&2, J.Json>) -> List<&2, J.Json>:
  match on:
    case True{}:
      Pods.prop(ms)
    case False{}:
      ms

def Pods.mounts.main(kind: CKind, pv: Bool, hp: Bool, +vpath: String, vols: List<&2, J.Json>, ms: List<&2, J.Json>) -> List<&2, J.Json>:
  match kind:
    case CMain{}:
      Pods.prop.if(pv, Pods.phys.if(hp, vpath, vols, ms))
    case CInit{}:
      ms
    case CEph{}:
      ms

# A container's mounts: the /etc/hosts mount, then (regular containers) the
# host path mapper's physical mounts and the mount propagation.
def Pods.mounts(+kind: CKind, hosts: Bool, pv: Bool, hp: Bool, vpath: String, vols: List<&2, J.Json>, cname: String, ms: List<&2, J.Json>) -> List<&2, J.Json>:
  Pods.mounts.main(kind, pv, hp, vpath, vols, Pods.mounts.hosts(Pods.hosts_for(kind, hosts, cname), ms))

# Containers.

def Pods.tr_container.rest(ctx: CCtx, +kind: CKind, +c: J.Json) -> J.Json:
  match ctx:
    case CCtx{+vc, +ns, env, images, hosts, pv, hp, vpath, vols}:
      Pods.with("env", Pods.arr(Pods.env_list(vc, ns, env, Pods.items(Pods.get(c, "env")))),
        Pods.with("envFrom", Pods.arr(Pods.tr_env_froms(vc, ns, Pods.items(Pods.get(c, "envFrom")))),
          Pods.with_str("image", Pods.image(images, Pods.str(c, "image")),
            Pods.with("volumeMounts", Pods.arr(Pods.mounts(kind, hosts, pv, hp, vpath, vols, Pods.str(c, "name"),
              Pods.items(Pods.get(c, "volumeMounts")))), c))))

# One container: its name first, then env, envFrom, image and mounts.
def Pods.tr_container(+ctx: CCtx, +kind: CKind, +c: J.Json) -> J.Json:
  Pods.with("name", Pods.get(c, "name"), Pods.tr_container.rest(ctx, kind, c))

def Pods.tr_containers(+ctx: CCtx, +kind: CKind, cs: List<&2, J.Json>) -> List<&2, J.Json>:
  match cs:
    case Nil{}:
      Nil{}
    case Con{c, r}:
      Pods.tr_container(ctx, kind, c) <> Pods.tr_containers(ctx, kind, r)

# The rewrite-hosts init container (rewritePodHostnameFQDN).
def Pods.hosts_container(+cfg: Cfg, from: String, to: String, fqdn: String) -> J.Json:
  J.Json.obj([J.KV{"name", J.JStr{Pods.hosts_name()}}, J.KV{"image", J.JStr{Pods.cfg.hosts_image(cfg)}},
    J.KV{"command", Pods.arr([J.JStr{"sh"}])},
    J.KV{"args", Pods.arr([J.JStr{"-c"}, J.JStr{"sed -E -e 's/^(\\d+.\\d+.\\d+.\\d+\\s+)" ++ from ++ "$/\\1 " ++ fqdn ++ " " ++ to ++ "/' /etc/hosts > /hosts/hosts"}])},
    J.KV{"securityContext", J.Json.obj([J.KV{"runAsUser", J.JNum{Pods.cfg.hosts_uid(cfg)}},
      J.KV{"runAsGroup", J.JNum{Pods.cfg.hosts_gid(cfg)}}, J.KV{"runAsNonRoot", J.JBool{True{}}},
      J.KV{"capabilities", J.Json.obj([J.KV{"drop", Pods.arr([J.JStr{"ALL"}])}])},
      J.KV{"allowPrivilegeEscalation", J.JBool{False{}}},
      J.KV{"seccompProfile", J.Json.obj([J.KV{"type", J.JStr{"RuntimeDefault"}}])}])},
    J.KV{"resources", Pods.cfg.hosts_res(cfg)},
    J.KV{"volumeMounts", Pods.arr([J.Json.obj([J.KV{"mountPath", J.JStr{"/hosts"}}, J.KV{"name", J.JStr{Pods.hosts_name()}}])])}])


# Volumes (translateVolumes, translateProjectedVolume, rewriteHostPaths).

def Pods.vx(+cfg: Cfg, +inp: Inp, +v: J.Json) -> VX:
  VX{Pods.cfg.vc(cfg), Pods.ns_of(v), Pods.name_of(v), Pods.cfg.sa_secrets(cfg), Pods.cfg.vpath(cfg), Pods.inp.uids(inp)}

def Pods.vx.vc(x: VX) -> String:
  match x:
    case VX{vc, ns, pod, secrets, vpath, uids}:
      vc

def Pods.vx.ns(x: VX) -> String:
  match x:
    case VX{vc, ns, pod, secrets, vpath, uids}:
      ns

def Pods.ren_at.if(has: Bool, +k: String, +f: String, vc: String, ns: String, +j: J.Json) -> J.Json:
  match has:
    case True{}:
      Pods.with(k, Pods.with_str(f, N.Names.host_name(Pods.str(Pods.get(j, k), f), ns, vc), Pods.get(j, k)), j)
    case False{}:
      j

# The name member f of member k of j, translated when k is set.
def Pods.ren_at(+k: String, +f: String, vc: String, ns: String, +j: J.Json) -> J.Json:
  Pods.ren_at.if(Pods.has(j, k), k, f, vc, ns, j)

def Pods.ren_in.if(has: Bool, +k: String, +r: String, vc: String, ns: String, +j: J.Json) -> J.Json:
  match has:
    case True{}:
      Pods.with(k, Pods.ren_at(r, "name", vc, ns, Pods.get(j, k)), j)
    case False{}:
      j

# The name of reference r inside member k of j, translated when both are set.
def Pods.ren_in(+k: String, +r: String, vc: String, ns: String, +j: J.Json) -> J.Json:
  Pods.ren_in.if(Pods.has(j, k), k, r, vc, ns, j)

def Pods.gluster.if(has: Bool, +vc: String, +ns: String, +j: J.Json) -> J.Json:
  match has:
    case True{}:
      Pods.with("glusterfs", Pods.with("endpoints", J.JStr{Pods.endpoints_name(vc, Pods.str(Pods.get(j, "glusterfs"), "endpoints"), ns)},
        Pods.get(j, "glusterfs")), j)
    case False{}:
      j

def Pods.gluster(+vc: String, +ns: String, +j: J.Json) -> J.Json:
  Pods.gluster.if(Bool.not(String.is_empty(Pods.str(Pods.get(j, "glusterfs"), "endpoints"))), vc, ns, j)

def Pods.eph.if(has: Bool, vc: String, ns: String, pod: String, +j: J.Json) -> J.Json:
  match has:
    case True{}:
      Pods.with("persistentVolumeClaim", J.Json.obj([J.KV{"claimName", J.JStr{N.Names.host_name(pod ++ "-" ++ Pods.str(j, "name"), ns, vc)}}]),
        Pods.without("ephemeral", j))
    case False{}:
      j

# An ephemeral volume becomes a reference to the PVC the ephemeral volume
# controller makes, "<pod>-<volume>" (ephemeral.VolumeClaimName).
def Pods.eph(vc: String, ns: String, pod: String, +j: J.Json) -> J.Json:
  Pods.eph.if(Pods.has(j, "ephemeral"), vc, ns, pod, j)

def Pods.dapi.if(has: Bool, +vc: String, +j: J.Json) -> J.Json:
  match has:
    case True{}:
      Pods.with("downwardAPI", Pods.with("items", Pods.arr(Pods.tr_frs(vc, Pods.items(Pods.get(Pods.get(j, "downwardAPI"), "items")))),
        Pods.get(j, "downwardAPI")), j)
    case False{}:
      j

# The field references of a downwardAPI member.
def Pods.dapi(+vc: String, +j: J.Json) -> J.Json:
  Pods.dapi.if(Pods.has(j, "downwardAPI"), vc, j)

def Pods.vol.hostpath.if(has: Bool, +vpath: String, +uids: +List<M.KV>, +j: J.Json) -> J.Json:
  match has:
    case True{}:
      Pods.with("hostPath", Pods.with("path", J.JStr{Pods.hp.path(vpath, uids, Pods.str(j, "name"), Pods.str(Pods.get(j, "hostPath"), "path"))},
        Pods.get(j, "hostPath")), j)
    case False{}:
      j

# The names a volume refers to, and its host path.
def Pods.vol.simple(+x: VX, v: J.Json) -> J.Json:
  match x:
    case VX{+vc, +ns, pod, secrets, vpath, uids}:
      v1 = Pods.ren_at("configMap", "name", vc, ns, v)
      v2 = Pods.ren_at("secret", "secretName", vc, ns, v1)
      v3 = Pods.ren_at("persistentVolumeClaim", "claimName", vc, ns, v2)
      v4 = Pods.eph(vc, ns, pod, v3)
      v5 = Pods.dapi(vc, v4)
      v6 = Pods.ren_in("iscsi", "secretRef", vc, ns, v5)
      v7 = Pods.ren_in("rbd", "secretRef", vc, ns, v6)
      v8 = Pods.ren_in("flexVolume", "secretRef", vc, ns, v7)
      v9 = Pods.ren_in("cinder", "secretRef", vc, ns, v8)
      v10 = Pods.ren_in("cephfs", "secretRef", vc, ns, v9)
      v11 = Pods.ren_at("azureFile", "secretName", vc, ns, v10)
      v12 = Pods.ren_in("scaleIO", "secretRef", vc, ns, v11)
      v13 = Pods.ren_in("storageos", "secretRef", vc, ns, v12)
      v14 = Pods.ren_in("csi", "nodePublishSecretRef", vc, ns, v13)
      +v15 = Pods.gluster(vc, ns, v14)
      Pods.vol.hostpath.if(Pods.has(v15, "hostPath"), vpath, uids, v15)

def Pods.src.simple(+vc: String, +ns: String, s: J.Json) -> J.Json:
  Pods.dapi(vc, Pods.ren_at("configMap", "name", vc, ns, Pods.ren_at("secret", "name", vc, ns, s)))

def Pods.acc.add(s: J.Json, ann: +List<M.KV>, sec: +List<M.KV>, acc: Acc) -> Acc:
  match acc:
    case Acc{out, anns, secs, toks}:
      Acc{List.append(&2, J.Json, out, [s]), Pods.put_all(ann, anns), Pods.put_all(sec, secs), toks}

def Pods.acc.set_toks(toks: List<&2, Tok>, acc: Acc) -> Acc:
  match acc:
    case Acc{out, anns, secs, t}:
      Acc{out, anns, secs, toks}

def Pods.acc.empty_out(acc: Acc) -> Acc:
  match acc:
    case Acc{out, anns, secs, toks}:
      Acc{[], anns, secs, toks}

def Pods.acc.out(acc: Acc) -> List<&2, J.Json>:
  match acc:
    case Acc{out, anns, secs, toks}:
      out

def Pods.acc.anns(acc: Acc) -> +List<M.KV>:
  match acc:
    case Acc{out, anns, secs, toks}:
      anns

def Pods.acc.secs(acc: Acc) -> +List<M.KV>:
  match acc:
    case Acc{out, anns, secs, toks}:
      secs

def Pods.sat_path(s: J.Json) -> String:
  Pods.str(Pods.get(s, "serviceAccountToken"), "path")

# The token source as a secret projection (useSecretsForSATokens).
def Pods.src.secret(secret_name: String, vname: String, +s: J.Json) -> J.Json:
  Pods.without("serviceAccountToken", Pods.with("secret", J.Json.obj([J.KV{"name", J.JStr{secret_name}},
    J.KV{"items", Pods.arr([J.Json.obj([J.KV{"key", J.JStr{vname}}, J.KV{"path", J.JStr{Pods.sat_path(s)}}, J.KV{"mode", J.JNum{"420"}}])])}]), s))

# The token source as a downward API item reading annotation key.
def Pods.src.dapi_tok(key: String, +s: J.Json) -> J.Json:
  Pods.without("serviceAccountToken", Pods.with("downwardAPI", J.Json.obj([J.KV{"items", Pods.arr([J.Json.obj([
    J.KV{"path", J.JStr{Pods.sat_path(s)}},
    J.KV{"fieldRef", J.Json.obj([J.KV{"apiVersion", J.JStr{"v1"}}, J.KV{"fieldPath", J.JStr{Pods.ann_ref(key)}}])},
    J.KV{"mode", J.JNum{"420"}}])])}]), s))

def Pods.src.tok.mode(secrets: Bool, secret_name: String, +vname: String, +s: J.Json, +suffix: String, token: String, acc: Acc) -> Acc:
  match secrets:
    case True{}:
      Pods.acc.add(Pods.src.secret(secret_name, vname, s), [], [M.KV{vname, token}], acc)
    case False{}:
      Pods.acc.add(Pods.src.dapi_tok(Pods.token_annotation() ++ suffix, s), [M.KV{Pods.token_annotation() ++ suffix, token}], [], acc)

def Pods.vx.secret_name(x: VX) -> String:
  match x:
    case VX{vc, ns, pod, secrets, vpath, uids}:
      N.Names.host_name(pod ++ "-sa-token", ns, vc)

def Pods.vx.secrets(x: VX) -> Bool:
  match x:
    case VX{vc, ns, pod, secrets, vpath, uids}:
      secrets

def Pods.src.tok.k(+x: VX, +vname: String, +s: J.Json, toks: List<&2, Tok>, acc: Acc) -> Acc:
  match toks:
    case Nil{}:
      Pods.acc.add(s, [], [], acc)
    case Con{Tok{suffix, token}, rest}:
      Pods.acc.set_toks(rest, Pods.src.tok.mode(Pods.vx.secrets(x), Pods.vx.secret_name(x), vname, s, suffix, token, acc))

def Pods.src.tok.t(+x: VX, +vname: String, +s: J.Json, acc: Acc) -> Acc:
  match acc:
    case Acc{out, anns, secs, toks}:
      Pods.src.tok.k(x, vname, s, toks, Acc{out, anns, secs, []})

def Pods.src.tok.if(has: Bool, +x: VX, +vname: String, +s: J.Json, acc: Acc) -> Acc:
  match has:
    case True{}:
      Pods.src.tok.t(x, vname, s, acc)
    case False{}:
      Pods.acc.add(s, [], [], acc)

# A projected source: its names, its field references, and a
# serviceAccountToken source replaced by the next requested token. Without
# a token left the source stays.
def Pods.src(+x: VX, +vname: String, s: J.Json, acc: Acc) -> Acc:
  +s1 = Pods.src.simple(Pods.vx.vc(x), Pods.vx.ns(x), s)
  Pods.src.tok.if(Pods.has(s1, "serviceAccountToken"), x, vname, s1, acc)

def Pods.srcs.go(ss: List<&2, J.Json>, +x: VX, +vname: String, acc: Acc) -> Acc:
  match ss:
    case Nil{}:
      acc
    case Con{s, r}:
      Pods.srcs.go(r, x, vname, Pods.src(x, vname, s, acc))

def Pods.vol.proj.fin(+v: J.Json, inner: Acc, outer: Acc) -> Acc:
  match inner:
    case Acc{srcs, anns, secs, toks}:
      match outer:
        case Acc{out, a2, s2, t2}:
          Acc{List.append(&2, J.Json, out, [Pods.with("projected", Pods.with("sources", Pods.arr(srcs), Pods.get(v, "projected")), v)]), anns, secs, toks}

def Pods.vol.proj.if(has: Bool, +x: VX, +v: J.Json, +acc: Acc) -> Acc:
  match has:
    case True{}:
      Pods.vol.proj.fin(v, Pods.srcs.go(Pods.items(Pods.get(Pods.get(v, "projected"), "sources")), x, Pods.str(v, "name"), Pods.acc.empty_out(acc)), acc)
    case False{}:
      Pods.acc.add(v, [], [], acc)

def Pods.vol(+x: VX, v: J.Json, acc: Acc) -> Acc:
  +v1 = Pods.vol.simple(x, v)
  Pods.vol.proj.if(Pods.has(v1, "projected"), x, v1, acc)

def Pods.vols.go(vs: List<&2, J.Json>, +x: VX, acc: Acc) -> Acc:
  match vs:
    case Nil{}:
      acc
    case Con{v, r}:
      Pods.vols.go(r, x, Pods.vol(x, v, acc))

# The translated volumes, the token annotations and the token secret data.
def Pods.vols(+cfg: Cfg, +inp: Inp, +v: J.Json) -> Acc:
  Pods.vols.go(Pods.items(Pods.get(Pods.spec(v), "volumes")), Pods.vx(cfg, inp, v), Acc{[], [], [], Pods.inp.tokens(inp)})

def Pods.phys_vol(k: HK, vname: String, hp: J.Json) -> J.Json:
  J.Json.obj([J.KV{"name", J.JStr{vname ++ "-vcluster-physical"}},
    J.KV{"hostPath", Pods.with_opt("type", Pods.get(hp, "type"), J.Json.obj([J.KV{"path", J.JStr{Pods.hk.host(k)}}]))}])

def Pods.phys_on(on: Bool, k: HK, vname: String, hp: J.Json) -> List<&2, J.Json>:
  match on:
    case True{}:
      [Pods.phys_vol(k, vname, hp)]
    case False{}:
      []

def Pods.phys_vols1(k: Reg, +vname: String, +hp: J.Json) -> List<&2, J.Json>:
  match k:
    case Reg{pl, ku, lg}:
      List.append(&2, J.Json, Pods.phys_on(pl, HPL{}, vname, hp),
        List.append(&2, J.Json, Pods.phys_on(ku, HKU{}, vname, hp), Pods.phys_on(lg, HLG{}, vname, hp)))

def Pods.phys_vols(+vpath: String, vs: List<&2, J.Json>) -> List<&2, J.Json>:
  match vs:
    case Nil{}:
      Nil{}
    case Con{+vol, r}:
      List.append(&2, J.Json, Pods.phys_vols1(Pods.hp.kinds(vpath, vol), Pods.str(vol, "name"), Pods.get(vol, "hostPath")),
        Pods.phys_vols(vpath, r))

# The physical host path volumes of the host path mapper.
def Pods.phys_vols.if(on: Bool, +vpath: String, vs: List<&2, J.Json>) -> List<&2, J.Json>:
  match on:
    case True{}:
      Pods.phys_vols(vpath, vs)
    case False{}:
      Nil{}

def Pods.hosts_vols(on: Bool) -> List<&2, J.Json>:
  match on:
    case True{}:
      [J.Json.obj([J.KV{"name", J.JStr{Pods.hosts_name()}}, J.KV{"emptyDir", J.JObj{J.JNil{}}}])]
    case False{}:
      []

# The /etc/hosts rewrite applies: a subdomain, rewriteHosts on, and not
# both disable-subdomain-rewrite and hosts-rewritten set to "true".
def Pods.hosts_on(+cfg: Cfg, +v: J.Json) -> Bool:
  +va = Pods.annotations_of(v)
  Bool.and(Bool.not(String.is_empty(Pods.str(Pods.spec(v), "subdomain"))),
    Bool.and(Pods.cfg.rewrite_hosts(cfg),
      Bool.not(Bool.and(String.eq(M.Meta.lookup(Pods.disable_subdomain_rewrite_annotation(), va), "true"),
        String.eq(M.Meta.lookup(Pods.hosts_rewritten_annotation(), va), "true")))))

# The host pod's volumes: the translated ones, the hosts volume, the
# physical host path volumes.
def Pods.host_volumes(+cfg: Cfg, +inp: Inp, +v: J.Json) -> List<&2, J.Json>:
  List.append(&2, J.Json, Pods.acc.out(Pods.vols(cfg, inp, v)),
    List.append(&2, J.Json, Pods.hosts_vols(Pods.hosts_on(cfg, v)),
      Pods.phys_vols.if(Pods.cfg.host_paths(cfg), Pods.cfg.vpath(cfg), Pods.items(Pods.get(Pods.spec(v), "volumes")))))

# Service account tokens.

def Pods.audiences.if(set: Bool, +aud: String, domain: String) -> List<&2, J.Json>:
  match set:
    case True{}:
      [J.JStr{aud}]
    case False{}:
      [J.JStr{"https://kubernetes.default.svc." ++ domain}, J.JStr{"https://kubernetes.default.svc"}, J.JStr{"https://kubernetes.default"}]

def Pods.token_request(+cfg: Cfg, +v: J.Json, +sat: J.Json) -> J.Json:
  J.Json.obj([J.KV{"serviceAccountName", J.JStr{Pods.or_str(Pods.str(Pods.spec(v), "serviceAccountName"), Pods.or_str(Pods.str(Pods.spec(v), "serviceAccount"), "default"))}},
    J.KV{"namespace", J.JStr{Pods.ns_of(v)}},
    J.KV{"request", J.Json.obj([J.KV{"apiVersion", J.JStr{"authentication.k8s.io/v1"}}, J.KV{"kind", J.JStr{"TokenRequest"}},
      J.KV{"spec", J.Json.obj([
        J.KV{"audiences", Pods.arr(Pods.audiences.if(Bool.not(String.is_empty(Pods.str(sat, "audience"))), Pods.str(sat, "audience"), Pods.cfg.domain(cfg)))},
        J.KV{"boundObjectRef", J.Json.obj([J.KV{"apiVersion", J.JStr{"v1"}}, J.KV{"kind", J.JStr{"Pod"}},
          J.KV{"name", J.JStr{Pods.name_of(v)}}, J.KV{"uid", J.JStr{Pods.uid_of(v)}}])},
        J.KV{"expirationSeconds", J.JNum{"315360000"}}])}])}])

def Pods.token_reqs.if(has: Bool, +cfg: Cfg, +v: J.Json, +s: J.Json, rec: List<&2, J.Json>) -> List<&2, J.Json>:
  match has:
    case True{}:
      Pods.token_request(cfg, v, Pods.get(s, "serviceAccountToken")) <> rec
    case False{}:
      rec

def Pods.token_reqs.srcs(+cfg: Cfg, +v: J.Json, ss: List<&2, J.Json>) -> List<&2, J.Json>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{+s, r}:
      Pods.token_reqs.if(Pods.has(s, "serviceAccountToken"), cfg, v, s, Pods.token_reqs.srcs(cfg, v, r))

def Pods.token_reqs.vols(+cfg: Cfg, +v: J.Json, vs: List<&2, J.Json>) -> List<&2, J.Json>:
  match vs:
    case Nil{}:
      Nil{}
    case Con{vol, r}:
      List.append(&2, J.Json, Pods.token_reqs.srcs(cfg, v, Pods.items(Pods.get(Pods.get(vol, "projected"), "sources"))),
        Pods.token_reqs.vols(cfg, v, r))

# The TokenRequests Translate makes in the virtual cluster, one per
# serviceAccountToken projection in volume order: the service account
# (spec.serviceAccountName, else serviceAccount, else "default"), its
# namespace and the request (audiences, bound to the pod, ten years).
def Pods.token_requests(+cfg: Cfg, +v: J.Json) -> List<&2, J.Json>:
  Pods.token_reqs.vols(cfg, v, Pods.items(Pods.get(Pods.spec(v), "volumes")))

def Pods.owner_ref.if(ok: Bool, av: String, k: String, n: String, u: String, ctrl: Bool, m: J.Json) -> J.Json:
  match ok:
    case True{}:
      Pods.with("ownerReferences", Pods.arr([J.Json.obj([J.KV{"apiVersion", J.JStr{av}}, J.KV{"kind", J.JStr{k}},
        J.KV{"name", J.JStr{n}}, J.KV{"uid", J.JStr{u}}, J.KV{"controller", J.JBool{ctrl}}])]), m)
    case False{}:
      m

# translate.GetOwnerReference: the owner, when all its fields are set.
def Pods.owner_ref(o: Maybe<&2, Owner>, ctrl: Bool, m: J.Json) -> J.Json:
  match o:
    case None{}:
      m
    case Some{Owner{+av, +k, +n, +u}}:
      Pods.owner_ref.if(Bool.and(Bool.not(String.is_empty(av)), Bool.and(Bool.not(String.is_empty(k)),
        Bool.and(Bool.not(String.is_empty(n)), Bool.not(String.is_empty(u))))), av, k, n, u, ctrl, m)

def Pods.token_secret.if(on: Bool, +cfg: Cfg, +v: J.Json, secs: +List<M.KV>) -> Maybe<&2, J.Json>:
  match on:
    case True{}:
      Some{J.Json.obj([J.KV{"apiVersion", J.JStr{"v1"}}, J.KV{"kind", J.JStr{"Secret"}},
        J.KV{"metadata", Pods.owner_ref(Pods.cfg.owner(cfg), False{}, J.Json.obj([
          J.KV{"name", J.JStr{N.Names.host_name(Pods.name_of(v) ++ "-sa-token", Pods.ns_of(v), Pods.cfg.vc(cfg))}},
          J.KV{"namespace", J.JStr{Pods.cfg.target(cfg)}},
          J.KV{"annotations", J.Json.obj([J.KV{Pods.skip_backsync_annotation(), J.JStr{"true"}}])}]))},
        J.KV{"type", J.JStr{"Opaque"}}, J.KV{"stringData", Pods.obj_of(secs)}])}
    case False{}:
      None{}

# The host secret holding the pod's tokens (SATokenSecret), when
# useSecretsForSATokens is on and the pod projects a token. vcluster deletes
# an existing one first.
def Pods.token_secret(+cfg: Cfg, +inp: Inp, +v: J.Json) -> Maybe<&2, J.Json>:
  +secs = Pods.acc.secs(Pods.vols(cfg, inp, v))
  Pods.token_secret.if(Bool.and(Pods.cfg.sa_secrets(cfg), Bool.not(List.is_empty(&2, M.KV, secs))), cfg, v, secs)


# Label selectors.

def Pods.reqs_in(xs: List<&2, J.Json>) -> List<&2, M.Req>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, r}:
      M.Req{Pods.str(x, "key"), Pods.str(x, "operator"), Pods.strs(Pods.get(x, "values"))} <> Pods.reqs_in(r)

def Pods.ml_in.if(has: Bool, j: J.Json) -> Maybe<&2, List<&2, M.KV>>:
  match has:
    case True{}:
      Some{Pods.map(j)}
    case False{}:
      None{}

def Pods.sel_in.if(isnull: Bool, +j: J.Json) -> Maybe<&2, M.Sel>:
  match isnull:
    case True{}:
      None{}
    case False{}:
      Some{M.Sel{Pods.ml_in.if(Pods.has(j, "matchLabels"), Pods.get(j, "matchLabels")), Pods.reqs_in(Pods.items(Pods.get(j, "matchExpressions")))}}

# A label selector, None for null.
def Pods.sel_in(+j: J.Json) -> Maybe<&2, M.Sel>:
  Pods.sel_in.if(J.Json.is_null(j), j)

def Pods.reqs_out(rs: List<&2, M.Req>) -> List<&2, J.Json>:
  match rs:
    case Nil{}:
      Nil{}
    case Con{M.Req{k, op, vs}, r}:
      J.Json.obj([J.KV{"key", J.JStr{k}}, J.KV{"operator", J.JStr{op}}, J.KV{"values", Pods.arr(Pods.jstrs(vs))}]) <> Pods.reqs_out(r)

def Pods.ml_out(ml: Maybe<&2, List<&2, M.KV>>, j: J.Json) -> J.Json:
  match ml:
    case None{}:
      j
    case Some{m}:
      Pods.with_map("matchLabels", m, j)

def Pods.sel_out(s: Maybe<&2, M.Sel>) -> J.Json:
  match s:
    case None{}:
      J.JNull{}
    case Some{M.Sel{ml, ex}}:
      Pods.ml_out(ml, J.Json.obj([J.KV{"matchExpressions", Pods.arr(Pods.reqs_out(ex))}]))

# matchLabels[k] = v.
def Pods.sel.label(+k: String, +v: String, s: M.Sel) -> M.Sel:
  match s:
    case M.Sel{ml, ex}:
      M.Sel{Some{M.Meta.insert(k, v, Maybe.default(&2, List<&2, M.KV>, ml, []))}, ex}

def Pods.sel.expr(r: M.Req, s: M.Sel) -> M.Sel:
  match s:
    case M.Sel{ml, ex}:
      M.Sel{ml, List.append(&2, M.Req, ex, [r])}

def Pods.ns_pairs(+vc: String, m: +List<M.KV>) -> +List<M.KV>:
  match m:
    case Nil{}:
      Nil{}
    case Con{M.KV{k, v}, r}:
      M.KV{Pods.ns_label_key(vc, k), v} <> Pods.ns_pairs(vc, r)

def Pods.ns_reqs(+vc: String, rs: List<&2, M.Req>) -> List<&2, M.Req>:
  match rs:
    case Nil{}:
      Nil{}
    case Con{M.Req{k, op, vs}, r}:
      M.Req{Pods.ns_label_key(vc, k), op, vs} <> Pods.ns_reqs(vc, r)

def Pods.ns_ml(+vc: String, ml: Maybe<&2, List<&2, M.KV>>) -> Maybe<&2, List<&2, M.KV>>:
  match ml:
    case None{}:
      None{}
    case Some{m}:
      Some{M.Meta.from_list(Pods.ns_pairs(vc, m))}

# HostLabelSelectorNamespace.
def Pods.ns_sel(+vc: String, s: Maybe<&2, M.Sel>) -> Maybe<&2, M.Sel>:
  match s:
    case None{}:
      None{}
    case Some{M.Sel{ml, ex}}:
      Some{M.Sel{Pods.ns_ml(vc, ml), Pods.ns_reqs(vc, ex)}}

def Pods.ml_of(s: Maybe<&2, M.Sel>) -> +List<M.KV>:
  match s:
    case None{}:
      []
    case Some{M.Sel{ml, ex}}:
      Maybe.default(&2, List<&2, M.KV>, ml, [])

def Pods.ex_of(s: Maybe<&2, M.Sel>) -> List<&2, M.Req>:
  match s:
    case None{}:
      []
    case Some{M.Sel{ml, ex}}:
      ex

def Pods.ml_some.if(empty: Bool, m: +List<M.KV>) -> Maybe<&2, List<&2, M.KV>>:
  match empty:
    case True{}:
      None{}
    case False{}:
      Some{m}

# MergeLabelSelectors(a, b): b's labels win, the expressions append.
def Pods.merge_sel(+a: Maybe<&2, M.Sel>, +b: Maybe<&2, M.Sel>) -> M.Sel:
  +m = M.Meta.union(Pods.ml_of(b), Pods.ml_of(a))
  M.Sel{Pods.ml_some.if(List.is_empty(&2, M.KV, m), m), List.append(&2, M.Req, Pods.ex_of(a), Pods.ex_of(b))}

# Affinity (translatePodAffinityTerm, translatePodAffinity) and topology
# spread constraints.

def Pods.nsel_nonempty(+nsel: J.Json) -> Bool:
  Bool.or(Bool.not(List.is_empty(&2, M.KV, Pods.map(Pods.get(nsel, "matchLabels")))),
    Bool.not(List.is_empty(&2, J.Json, Pods.items(Pods.get(nsel, "matchExpressions")))))

def Pods.aff_term.in(on: Bool, nss: List<&2, String>, hs: M.Sel) -> M.Sel:
  match on:
    case True{}:
      Pods.sel.expr(M.Req{M.Meta.namespace_label(), "In", nss}, hs)
    case False{}:
      hs

def Pods.aff_term.case(has_nss: Bool, nsel_null: Bool, nsel_ne: Bool, +vc: String, +ns: String, nss: List<&2, String>, nsel: J.Json, hs: M.Sel) -> M.Sel:
  match has_nss:
    case True{}:
      Pods.aff_term.in(Bool.or(nsel_null, nsel_ne), nss, hs)
    case False{}:
      match nsel_null:
        case False{}:
          Pods.merge_sel(Some{hs}, Pods.ns_sel(vc, Pods.sel_in(nsel)))
        case True{}:
          Pods.sel.label(M.Meta.namespace_label(), ns, hs)

def Pods.aff_term.ns(+vc: String, +ns: String, +term: J.Json, hs: M.Sel) -> M.Sel:
  +nss = Pods.strs(Pods.get(term, "namespaces"))
  +nsel = Pods.get(term, "namespaceSelector")
  Pods.aff_term.case(Bool.not(List.is_empty(&2, String, nss)), J.Json.is_null(nsel), Pods.nsel_nonempty(nsel), vc, ns, nss, nsel, hs)

def Pods.aff_term.sel(+vc: String, +ns: String, +term: J.Json, s: Maybe<&2, M.Sel>) -> Maybe<&2, M.Sel>:
  match s:
    case None{}:
      None{}
    case Some{hs}:
      Some{Pods.sel.label(M.Meta.marker_label(), vc, Pods.aff_term.ns(vc, ns, term, hs))}

# translatePodAffinityTerm for a pod in namespace ns: only labelSelector and
# topologyKey stay; the selector is translated, restricted to the
# namespaces the term names and to this vcluster's pods.
def Pods.aff_term(+vc: String, +ns: String, +term: J.Json) -> J.Json:
  Pods.with_opt("labelSelector",
    Pods.sel_out(Pods.aff_term.sel(vc, ns, term, M.Meta.host_label_selector(vc, Pods.sel_in(Pods.get(term, "labelSelector"))))),
    Pods.with_str("topologyKey", Pods.str(term, "topologyKey"), J.JObj{J.JNil{}}))

def Pods.aff_term_events.if(warn: Bool) -> List<&2, String>:
  match warn:
    case True{}:
      ["Warning SyncWarning " ++ Pods.affinity_warning()]
    case False{}:
      []

# The events translatePodAffinityTerm records ("<type> <reason> <message>",
# as the fake recorder prints them).
def Pods.aff_term_events(+term: J.Json) -> List<&2, String>:
  +nsel = Pods.get(term, "namespaceSelector")
  Pods.aff_term_events.if(Bool.and(Pods.has(term, "labelSelector"), Bool.and(Bool.not(List.is_empty(&2, String, Pods.strs(Pods.get(term, "namespaces")))),
    Bool.and(Bool.not(J.Json.is_null(nsel)), Pods.nsel_nonempty(nsel)))))

def Pods.aff_terms(+vc: String, +ns: String, ts: List<&2, J.Json>) -> List<&2, J.Json>:
  match ts:
    case Nil{}:
      Nil{}
    case Con{t, r}:
      Pods.aff_term(vc, ns, t) <> Pods.aff_terms(vc, ns, r)

def Pods.aff_prefs(+vc: String, +ns: String, ts: List<&2, J.Json>) -> List<&2, J.Json>:
  match ts:
    case Nil{}:
      Nil{}
    case Con{+t, r}:
      Pods.with("podAffinityTerm", Pods.aff_term(vc, ns, Pods.get(t, "podAffinityTerm")), t) <> Pods.aff_prefs(vc, ns, r)

def Pods.aff_kind(+vc: String, +ns: String, +a: J.Json) -> J.Json:
  Pods.with("requiredDuringSchedulingIgnoredDuringExecution",
    Pods.arr(Pods.aff_terms(vc, ns, Pods.items(Pods.get(a, "requiredDuringSchedulingIgnoredDuringExecution")))),
    Pods.with("preferredDuringSchedulingIgnoredDuringExecution",
      Pods.arr(Pods.aff_prefs(vc, ns, Pods.items(Pods.get(a, "preferredDuringSchedulingIgnoredDuringExecution")))), a))

def Pods.aff_at.if(has: Bool, +k: String, vc: String, ns: String, +j: J.Json) -> J.Json:
  match has:
    case True{}:
      Pods.with(k, Pods.aff_kind(vc, ns, Pods.get(j, k)), j)
    case False{}:
      j

def Pods.aff_at(+k: String, vc: String, ns: String, +j: J.Json) -> J.Json:
  Pods.aff_at.if(Pods.has(j, k), k, vc, ns, j)

def Pods.aff.if(has: Bool, +vc: String, +ns: String, +s: J.Json) -> J.Json:
  match has:
    case True{}:
      Pods.with("affinity", Pods.aff_at("podAntiAffinity", vc, ns, Pods.aff_at("podAffinity", vc, ns, Pods.get(s, "affinity"))), s)
    case False{}:
      s

def Pods.aff(+vc: String, +ns: String, +s: J.Json) -> J.Json:
  Pods.aff.if(Pods.has(s, "affinity"), vc, ns, s)

def Pods.tsc.sel(+vc: String, +ns: String, s: Maybe<&2, M.Sel>) -> Maybe<&2, M.Sel>:
  match s:
    case None{}:
      None{}
    case Some{x}:
      Some{Pods.sel.label(M.Meta.marker_label(), vc, Pods.sel.label(M.Meta.namespace_label(), ns, x))}

def Pods.tsc1(+vc: String, +ns: String, +c: J.Json) -> J.Json:
  Pods.with_opt("labelSelector", Pods.sel_out(Pods.tsc.sel(vc, ns, M.Meta.host_label_selector(vc, Pods.sel_in(Pods.get(c, "labelSelector"))))), c)

def Pods.tscs(+vc: String, +ns: String, cs: List<&2, J.Json>) -> List<&2, J.Json>:
  match cs:
    case Nil{}:
      Nil{}
    case Con{c, r}:
      Pods.tsc1(vc, ns, c) <> Pods.tscs(vc, ns, r)

def Pods.spec.sched.if(virt: Bool, +vc: String, +ns: String, +s: J.Json) -> J.Json:
  match virt:
    case True{}:
      Pods.without("topologySpreadConstraints", Pods.without("affinity", Pods.without("nodeSelector", s)))
    case False{}:
      Pods.aff(vc, ns, Pods.with("topologySpreadConstraints", Pods.arr(Pods.tscs(vc, ns, Pods.items(Pods.get(s, "topologySpreadConstraints")))), s))

# The spec (Translate, in its order).

def Pods.spec.sa.if(sync: Bool, ws: String, +vsa: String, vc: String, ns: String) -> String:
  match sync:
    case False{}:
      ws
    case True{}:
      Pods.pick(String.is_empty(vsa), ws, N.Names.host_name(vsa, ns, vc))

# The workload service account, or with serviceAccounts sync the pod's own
# service account translated.
def Pods.spec.sa(+cfg: Cfg, +v: J.Json, s: J.Json) -> J.Json:
  Pods.with_str("serviceAccountName",
    Pods.spec.sa.if(Pods.cfg.sa_sync(cfg), Pods.cfg.workload_sa(cfg),
      Pods.or_str(Pods.str(Pods.spec(v), "serviceAccountName"), Pods.str(Pods.spec(v), "serviceAccount")), Pods.cfg.vc(cfg), Pods.ns_of(v)),
    Pods.without("serviceAccount", s))

# A priority above 1000000000 (maxPriority).
def Pods.over_max(+t: String) -> Bool:
  Bool.and(Bool.not(String.starts_with(t, "-")), Bool.or(Nat.is_gt(String.length(t), 10n),
    Bool.and(Nat.is_eq(String.length(t), 10n), Cmp.is_gt(String.order(t, "1000000000")))))

def Pods.cap.if(over: Bool, s: J.Json) -> J.Json:
  match over:
    case True{}:
      Pods.with("priority", J.JNum{"1000000000"}, s)
    case False{}:
      s

def Pods.cap(+s: J.Json) -> J.Json:
  Pods.cap.if(Pods.over_max(Pods.num(Pods.get(s, "priority"))), s)

def Pods.prio.a(to: Bool, off: Bool, +cfg: Cfg, +s: J.Json) -> J.Json:
  match to:
    case True{}:
      Pods.with_str("priorityClassName", N.Names.host_name_cluster(Pods.str(s, "priorityClassName"), Pods.cfg.target(cfg), Pods.cfg.vc(cfg)), Pods.cap(s))
    case False{}:
      match off:
        case True{}:
          Pods.without("priorityClassName", Pods.without("priority", s))
        case False{}:
          s

def Pods.prio.b(on: Bool, pc: String, s: J.Json) -> J.Json:
  match on:
    case True{}:
      Pods.with_str("priorityClassName", pc, Pods.without("priority", s))
    case False{}:
      s

def Pods.spec.prio(+cfg: Cfg, +s: J.Json) -> J.Json:
  +s1 = Pods.prio.a(Bool.and(Pods.cfg.pc_to_host(cfg), Bool.not(String.is_empty(Pods.str(s, "priorityClassName")))),
    Bool.and(Bool.not(Pods.cfg.pc_to_host(cfg)), Bool.not(Pods.cfg.pc_from_host(cfg))), cfg, s)
  Pods.prio.b(Bool.and(Bool.not(String.is_empty(Pods.cfg.pod_pc(cfg))), String.is_empty(Pods.str(s1, "priorityClassName"))), Pods.cfg.pod_pc(cfg), s1)

def Pods.aliases.if(empty: Bool, domain: String) -> List<&2, String>:
  match empty:
    case True{}:
      ["kubernetes", "kubernetes.default", "kubernetes.default.svc"]
    case False{}:
      ["kubernetes.default.svc." ++ domain, "kubernetes", "kubernetes.default", "kubernetes.default.svc"]

def Pods.spec.aliases(+domain: String, ip: String, +s: J.Json) -> J.Json:
  Pods.with("hostAliases", Pods.arr(List.append(&2, J.Json, Pods.items(Pods.get(s, "hostAliases")),
    [J.Json.obj([J.KV{"ip", J.JStr{ip}}, J.KV{"hostnames", Pods.arr(Pods.jstrs(Pods.aliases.if(String.is_empty(domain), domain)))}])])), s)

def Pods.searches.if(empty: Bool, +domain: String, ns: String) -> List<&2, String>:
  match empty:
    case True{}:
      []
    case False{}:
      [ns ++ ".svc." ++ domain, "svc." ++ domain, domain]

def Pods.dns.if(on: Bool, +domain: String, ns: String, ip: String, +s: J.Json) -> J.Json:
  match on:
    case False{}:
      s
    case True{}:
      +ex = Pods.get(s, "dnsConfig")
      Pods.with("dnsPolicy", J.JStr{"None"}, Pods.with("dnsConfig", J.Json.obj([
        J.KV{"nameservers", Pods.arr(Pods.jstrs(Pods.dedup(ip <> Pods.strs(Pods.get(ex, "nameservers")))))},
        J.KV{"options", Pods.arr([J.Json.obj([J.KV{"name", J.JStr{"ndots"}}, J.KV{"value", J.JStr{"5"}}])])},
        J.KV{"searches", Pods.arr(Pods.jstrs(Pods.dedup(List.append(&2, String, Pods.searches.if(String.is_empty(domain), domain, ns),
          Pods.strs(Pods.get(ex, "searches"))))))}]), s))

# translateDNSConfig: ClusterFirst (without hostNetwork) and
# ClusterFirstWithHostNet become None with the vcluster's DNS server.
def Pods.spec.dns(domain: String, ns: String, +ip: String, +s: J.Json) -> J.Json:
  +policy = Pods.str(s, "dnsPolicy")
  Pods.dns.if(Bool.and(Bool.not(String.is_empty(ip)), Bool.or(String.eq(policy, "ClusterFirstWithHostNet"),
    Bool.and(String.eq(policy, "ClusterFirst"), Bool.not(Pods.is_true(Pods.get(s, "hostNetwork")))))), domain, ns, ip, s)

# The pod name cut to 63 characters, "." replaced by "-", one trailing "-"
# trimmed.
def Pods.hostname_of(name: String) -> String:
  Pods.trim1(Pods.subst(String.take(name, 63n), '.', '-'), "-")

def Pods.hostname.if(empty: Bool, name: String, s: J.Json) -> J.Json:
  match empty:
    case True{}:
      Pods.with_str("hostname", Pods.hostname_of(name), s)
    case False{}:
      s

def Pods.spec.hostname(name: String, +s: J.Json) -> J.Json:
  Pods.hostname.if(String.is_empty(Pods.str(s, "hostname")), name, s)

# The pod's hostname on the host.
def Pods.eff_hostname(+v: J.Json) -> String:
  Pods.or_str(Pods.str(Pods.spec(v), "hostname"), Pods.hostname_of(Pods.name_of(v)))

def Pods.old_resources.if(old: Bool, s: J.Json) -> J.Json:
  match old:
    case True{}:
      Pods.without("resources", s)
    case False{}:
      s

def Pods.pull_secrets(+vc: String, +ns: String, xs: List<&2, J.Json>) -> List<&2, J.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, r}:
      Pods.with_str("name", N.Names.host_name(Pods.str(x, "name"), ns, vc), x) <> Pods.pull_secrets(vc, ns, r)

def Pods.claim.one(on: Bool, +k: String, vc: String, ns: String, +c: J.Json) -> J.Json:
  match on:
    case True{}:
      Pods.with(k, J.JStr{N.Names.host_name(Pods.str(c, k), ns, vc)}, c)
    case False{}:
      c

# translateResourceClaims for one claim.
def Pods.claim(cl: Bool, tpl: Bool, +vc: String, +ns: String, +c: J.Json) -> J.Json:
  +c1 = Pods.claim.one(Bool.and(cl, Pods.has(c, "resourceClaimName")), "resourceClaimName", vc, ns, c)
  Pods.claim.one(Bool.and(tpl, Pods.has(c1, "resourceClaimTemplateName")), "resourceClaimTemplateName", vc, ns, c1)

def Pods.claims(+cl: Bool, +tpl: Bool, +vc: String, +ns: String, cs: List<&2, J.Json>) -> List<&2, J.Json>:
  match cs:
    case Nil{}:
      Nil{}
    case Con{c, r}:
      Pods.claim(cl, tpl, vc, ns, c) <> Pods.claims(cl, tpl, vc, ns, r)

def Pods.runtime.if(empty: Bool, rc: String, s: J.Json) -> J.Json:
  match empty:
    case True{}:
      s
    case False{}:
      Pods.with("runtimeClassName", J.JStr{rc}, s)

# The spec without the container lists.
def Pods.spec_rest(+cfg: Cfg, +inp: Inp, +v: J.Json) -> J.Json:
  +vc = Pods.cfg.vc(cfg)
  +ns = Pods.ns_of(v)
  +s1 = Pods.spec.sa(cfg, v, Pods.spec(v))
  +s2 = Pods.with("automountServiceAccountToken", J.JBool{False{}}, Pods.with("enableServiceLinks", J.JBool{False{}}, s1))
  +s3 = Pods.spec.prio(cfg, s2)
  +s4 = Pods.spec.aliases(Pods.cfg.domain(cfg), Pods.inp.kube_ip(inp), s3)
  +s5 = Pods.spec.dns(Pods.cfg.domain(cfg), ns, Pods.inp.dns_ip(inp), s4)
  +s6 = Pods.without("subdomain", Pods.spec.hostname(Pods.name_of(v), s5))
  +s7 = Pods.old_resources.if(Pods.below(Pods.cfg.host_version(cfg), 1, 34, 0), s6)
  +s8 = Pods.with("imagePullSecrets", Pods.arr(Pods.pull_secrets(vc, ns, Pods.items(Pods.get(s7, "imagePullSecrets")))), s7)
  +s9 = Pods.with("volumes", Pods.arr(Pods.host_volumes(cfg, inp, v)), s8)
  +s10 = Pods.with("resourceClaims", Pods.arr(Pods.claims(Pods.cfg.claims(cfg), Pods.cfg.claim_templates(cfg), vc, ns,
    Pods.items(Pods.get(s9, "resourceClaims")))), s9)
  +s11 = Pods.runtime.if(String.is_empty(Pods.cfg.runtime_class(cfg)), Pods.cfg.runtime_class(cfg), s10)
  +s12 = Pods.spec.sched.if(Pods.cfg.virtual_scheduler(cfg), vc, ns, s11)
  Pods.with("tolerations", Pods.arr(Pods.add_new(Pods.items(Pods.get(s12, "tolerations")), Pods.cfg.enforced(cfg))), s12)

# The per-container context.
def Pods.ctx(+cfg: Cfg, +inp: Inp, +v: J.Json) -> CCtx:
  +vols = Pods.items(Pods.get(Pods.spec(v), "volumes"))
  +hosts = Pods.hosts_on(cfg, v)
  CCtx{Pods.cfg.vc(cfg), Pods.ns_of(v),
    Pods.services_env(Pods.is_true(Pods.get(Pods.spec(v), "enableServiceLinks")), Pods.inp.services(inp), Pods.inp.kube_ip(inp)),
    Pods.cfg.images(cfg), hosts, Bool.or(hosts, Bool.not(List.is_empty(&2, J.Json, vols))), Pods.cfg.host_paths(cfg), Pods.cfg.vpath(cfg), vols}

def Pods.hosts_init(on: Bool, +cfg: Cfg, +v: J.Json) -> List<&2, J.Json>:
  match on:
    case True{}:
      +hn = Pods.eff_hostname(v)
      [Pods.hosts_container(cfg, hn, hn, hn ++ "." ++ Pods.str(Pods.spec(v), "subdomain") ++ "." ++ Pods.ns_of(v) ++ ".svc." ++ Pods.cfg.domain(cfg))]
    case False{}:
      []

# The host pod's containers.
def Pods.host_containers(+cfg: Cfg, +inp: Inp, +v: J.Json) -> J.Json:
  Pods.arr(Pods.tr_containers(Pods.ctx(cfg, inp, v), CMain{}, J.Json.items(J.Json.get(J.Json.get(v, "spec"), "containers"))))

# The host pod's init containers: the rewrite-hosts one first.
def Pods.host_inits(+cfg: Cfg, +inp: Inp, +v: J.Json) -> J.Json:
  Pods.arr(Pods.tr_containers(Pods.ctx(cfg, inp, v), CInit{},
    List.append(&2, J.Json, Pods.hosts_init(Pods.hosts_on(cfg, v), cfg, v), Pods.items(Pods.get(Pods.spec(v), "initContainers")))))

# The host pod's ephemeral containers.
def Pods.host_ephemerals(+cfg: Cfg, +inp: Inp, +v: J.Json) -> J.Json:
  Pods.arr(Pods.tr_containers(Pods.ctx(cfg, inp, v), CEph{}, Pods.items(Pods.get(Pods.spec(v), "ephemeralContainers"))))

# The host spec: the container lists first.
def Pods.host_spec(+cfg: Cfg, +inp: Inp, +v: J.Json) -> J.Json:
  Pods.with("containers", Pods.host_containers(cfg, inp, v), Pods.with("initContainers", Pods.host_inits(cfg, inp, v), Pods.with("ephemeralContainers", Pods.host_ephemerals(cfg, inp, v),
    Pods.spec_rest(cfg, inp, v))))

# The metadata.

def Pods.reset(m: J.Json) -> J.Json:
  Pods.without("generateName", Pods.without("selfLink", Pods.without("uid", Pods.without("resourceVersion",
    Pods.without("generation", Pods.without("creationTimestamp", Pods.without("deletionTimestamp",
      Pods.without("deletionGracePeriodSeconds", Pods.without("ownerReferences", Pods.without("finalizers",
        Pods.without("managedFields", m)))))))))))

def Pods.host_meta_rest(+cfg: Cfg, +v: J.Json) -> J.Json:
  Pods.with("name", J.JStr{Pods.host_name(cfg, v)}, Pods.with("namespace", J.JStr{Pods.cfg.target(cfg)},
    Pods.owner_ref(Pods.cfg.owner(cfg), Maybe.is_some(&2, J.Json, Pods.controller(Pods.refs(v))), Pods.reset(Pods.meta(v)))))

# The host pod's annotations, as a map.
def Pods.host_annotations(+cfg: Cfg, +inp: Inp, +v: J.Json) -> +List<M.KV>:
  Pods.ann.hosts(Pods.hosts_on(cfg, v), Pods.put_all(Pods.acc.anns(Pods.vols(cfg, inp, v)), Pods.ann.local(v, Pods.ann.base(cfg, v))))

# The host pod's annotations as an object, the object name and namespace
# first.
def Pods.host_annotations_json(+cfg: Cfg, +inp: Inp, +v: J.Json) -> J.Json:
  Pods.with(M.Meta.name_annotation(), J.JStr{Pods.name_of(v)}, Pods.with(M.Meta.namespace_annotation(), J.JStr{Pods.ns_of(v)},
    Pods.obj_of(M.Meta.delete(M.Meta.name_annotation(), M.Meta.delete(M.Meta.namespace_annotation(), Pods.host_annotations(cfg, inp, v))))))

def Pods.host_meta(+cfg: Cfg, +inp: Inp, +v: J.Json) -> J.Json:
  Pods.with("labels", Pods.host_labels_json(cfg, Pods.inp.ns_labels(inp), v),
    Pods.with("annotations", Pods.host_annotations_json(cfg, inp, v), Pods.host_meta_rest(cfg, v)))

# Translate: the host pod of virtual pod v. Its status is reset.
def Pods.translate(+cfg: Cfg, +inp: Inp, +v: J.Json) -> J.Json:
  Pods.with("metadata", Pods.host_meta(cfg, inp, v), Pods.with("spec", Pods.host_spec(cfg, inp, v), Pods.without("status", v)))

def Pods.check.if(bad: Bool, pod: String, p: String) -> Maybe<&2, String>:
  match bad:
    case True{}:
      Some{"failed to translate kubelet sub-path for pPod " ++ pod ++ ": no virtual UID found in hostPath " ++ p}
    case False{}:
      None{}

def Pods.check.vol(+cfg: Cfg, +v: J.Json, +vol: J.Json) -> Maybe<&2, String>:
  +name = Pods.str(vol, "name")
  +p0 = Pods.str(Pods.get(vol, "hostPath"), "path")
  +pl = Pods.hp.pl(name, p0)
  +p1 = Pods.hp.p1(pl, Pods.cfg.vpath(cfg), p0)
  Pods.check.if(Bool.and(Pods.has(vol, "hostPath"), Bool.and(Bool.not(Pods.hp.ku(name, p1)),
    Bool.and(Pods.hp.sub(name, p1), String.is_empty(Pods.until_slash(String.drop(p1, 22n)))))), Pods.host_name(cfg, v), p1)

def Pods.check.go(+cfg: Cfg, +v: J.Json, vs: List<&2, J.Json>) -> Maybe<&2, String>:
  match vs:
    case Nil{}:
      None{}
    case Con{vol, r}:
      Maybe.or(&2, String, Pods.check.vol(cfg, v, vol), Pods.check.go(cfg, v, r))

# The error Translate returns for a pod it cannot translate (a kubelet
# sub-path host path without a pod UID), if any.
def Pods.check(+cfg: Cfg, +v: J.Json) -> Maybe<&2, String>:
  Pods.check.go(cfg, v, Pods.items(Pods.get(Pods.spec(v), "volumes")))


# Back-sync and update (diff.go).

def Pods.conds(v: J.Json) -> J.Json:
  J.Json.get(J.Json.get(v, "status"), "conditions")

def Pods.strip_gen(cs: List<&2, J.Json>) -> List<&2, J.Json>:
  match cs:
    case Nil{}:
      Nil{}
    case Con{c, r}:
      Pods.without("observedGeneration", c) <> Pods.strip_gen(r)

# stripConditionObservedGenerations (null stays null).
def Pods.strip(+j: J.Json) -> J.Json:
  Pods.when(j, Pods.arr(Pods.strip_gen(J.Json.items(j))))

# The virtual API server drops ObservedGeneration: virtual K8s below 1.34
# (virtualClusterStripsObservedGeneration).
def Pods.strips(+cfg: Cfg) -> Bool:
  Pods.below(Pods.cfg.virtual_version(cfg), 1, 34, 0)

def Pods.desired.if(strip: Bool, +h: J.Json, +vs: J.Json) -> J.Json:
  match strip:
    case False{}:
      Pods.with("qosClass", J.Json.get(vs, "qosClass"), h)
    case True{}:
      Pods.with("qosClass", J.Json.get(vs, "qosClass"), Pods.with("observedGeneration", J.Json.get(vs, "observedGeneration"),
        Pods.with("conditions", Pods.strip(J.Json.get(h, "conditions")), h)))

# DesiredVirtualStatus(hostStatus, virtualStatus): the host status with the
# virtual QOS class; when the virtual API server drops ObservedGeneration,
# the virtual one and conditions without it. (A null member is an absent one.)
def Pods.desired_status(+cfg: Cfg, h: J.Json, vs: J.Json) -> J.Json:
  Pods.desired.if(Pods.strips(cfg), h, vs)

def Pods.cond_eq(strip: Bool, +a: J.Json, +b: J.Json) -> Bool:
  match strip:
    case True{}:
      Pods.same_f(Pods.strip(a), Pods.strip(b))
    case False{}:
      Pods.same_f(a, b)

def Pods.copy_bidi.if(vchanged: Bool, hchanged: Bool, +v: J.Json, +h: J.Json) -> J.Json & J.Json:
  match vchanged:
    case True{}:
      (v, v)
    case False{}:
      match hchanged:
        case True{}:
          (h, h)
        case False{}:
          (v, h)

# conditionsCopyBidirectional(virtualOld, virtual, hostOld, host): (new
# virtual, new host) conditions.
def Pods.conditions_copy(+cfg: Cfg, vo: J.Json, +v: J.Json, ho: J.Json, +h: J.Json) -> J.Json & J.Json:
  Pods.copy_bidi.if(Bool.not(Pods.cond_eq(Pods.strips(cfg), vo, v)), Bool.not(Pods.cond_eq(Pods.strips(cfg), ho, h)), v, h)

def Pods.keep_named.if(keep: Bool, x: J.Json, rec: List<&2, J.Json>) -> List<&2, J.Json>:
  match keep:
    case True{}:
      x <> rec
    case False{}:
      rec

def Pods.keep_named(+names: List<&2, String>, xs: List<&2, J.Json>) -> List<&2, J.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, r}:
      Pods.keep_named.if(M.Meta.elem(Pods.str(x, "name"), names), x, Pods.keep_named(names, r))

# stripInjectedSidecarContainers: the host container statuses of the
# containers the virtual spec has.
def Pods.strip_sidecars(+v: J.Json, +hs: J.Json, vs: J.Json) -> J.Json:
  Pods.with("initContainerStatuses", Pods.arr(Pods.keep_named(Pods.names(Pods.items(Pods.get(Pods.spec(v), "initContainers"))),
      Pods.items(Pods.get(hs, "initContainerStatuses")))),
    Pods.with("containerStatuses", Pods.arr(Pods.keep_named(Pods.names(Pods.items(Pods.get(Pods.spec(v), "containers"))),
      Pods.items(Pods.get(hs, "containerStatuses")))), vs))

def Pods.claim_back.m(m: Maybe<&2, String>, c: J.Json) -> J.Json:
  match m:
    case None{}:
      c
    case Some{n}:
      Pods.with("resourceClaimName", J.JStr{n}, c)

def Pods.claims_back(+back: +List<M.KV>, cs: List<&2, J.Json>) -> List<&2, J.Json>:
  match cs:
    case Nil{}:
      Nil{}
    case Con{+c, r}:
      Pods.claim_back.m(M.Meta.get(Pods.str(c, "resourceClaimName"), back), c) <> Pods.claims_back(back, r)

# convertResourceClaimStatuses: host claim names mapped back to virtual ones.
def Pods.claims_status(on: Bool, back: +List<M.KV>, +s: J.Json) -> J.Json:
  match on:
    case True{}:
      Pods.with("resourceClaimStatuses", Pods.arr(Pods.claims_back(back, Pods.items(Pods.get(s, "resourceClaimStatuses")))), s)
    case False{}:
      s

def Pods.find_named.if(hit: Bool, c: J.Json, rec: Maybe<&2, J.Json>) -> Maybe<&2, J.Json>:
  match hit:
    case True{}:
      Some{c}
    case False{}:
      rec

# The first item with that name.
def Pods.find_named(cs: List<&2, J.Json>, +name: String) -> Maybe<&2, J.Json>:
  match cs:
    case Nil{}:
      None{}
    case Con{+c, r}:
      Pods.find_named.if(String.eq(Pods.str(c, "name"), name), c, Pods.find_named(r, name))

def Pods.idiff.cmp(same: Bool, +p: J.Json, img: String, rs: List<&2, J.Json>, ch: Bool) -> List<&2, J.Json> & Bool:
  match same:
    case True{}:
      (p <> rs, ch)
    case False{}:
      (Pods.with_str("image", img, p) <> rs, True{})

def Pods.idiff.one(found: Maybe<&2, J.Json>, +images: +List<M.KV>, +p: J.Json, rec: List<&2, J.Json> & Bool) -> List<&2, J.Json> & Bool:
  match found:
    case None{}:
      rec
    case Some{vc}:
      (rs, ch) = rec
      +img = Pods.image(images, Pods.str(vc, "image"))
      Pods.idiff.cmp(String.eq(Pods.str(p, "image"), img), p, img, rs, ch)

def Pods.idiff.skip(skip: Bool, +p: J.Json, found: Maybe<&2, J.Json>, +images: +List<M.KV>, rec: List<&2, J.Json> & Bool) -> List<&2, J.Json> & Bool:
  match skip:
    case True{}:
      (rs, ch) = rec
      (p <> rs, ch)
    case False{}:
      Pods.idiff.one(found, images, p, rec)

def Pods.idiff.go(ps: List<&2, J.Json>, +vs: List<&2, J.Json>, +images: +List<M.KV>, +skip: List<&2, String>) -> List<&2, J.Json> & Bool:
  match ps:
    case Nil{}:
      (Nil{}, False{})
    case Con{+p, r}:
      Pods.idiff.skip(M.Meta.elem(Pods.str(p, "name"), skip), p, Pods.find_named(vs, Pods.str(p, "name")), images,
        Pods.idiff.go(r, vs, images, skip))

def Pods.idiff.fin2(ch: Bool, xs: List<&2, J.Json>) -> Maybe<&2, List<&2, J.Json>>:
  match ch:
    case True{}:
      Some{xs}
    case False{}:
      None{}

def Pods.idiff.fin(r: List<&2, J.Json> & Bool) -> Maybe<&2, List<&2, J.Json>>:
  (xs, ch) = r
  Pods.idiff.fin2(ch, xs)

# calcContainerImageDiff: None when no image changed; otherwise the host
# containers with the virtual images (host containers without a virtual
# one are dropped, as in Go).
def Pods.idiff(ps: List<&2, J.Json>, vs: List<&2, J.Json>, images: +List<M.KV>, skip: List<&2, String>) -> Maybe<&2, List<&2, J.Json>>:
  Pods.idiff.fin(Pods.idiff.go(ps, vs, images, skip))

def Pods.idiff.apply(+k: String, m: Maybe<&2, List<&2, J.Json>>, s: J.Json) -> J.Json:
  match m:
    case None{}:
      s
    case Some{xs}:
      Pods.with(k, Pods.arr(xs), s)

def Pods.skip_hosts(on: Bool) -> List<&2, String>:
  match on:
    case True{}:
      [Pods.hosts_name()]
    case False{}:
      []

# calcSpecDiff: the host pod after the spec update.
def Pods.spec_diff(+cfg: Cfg, +h: J.Json, +v: J.Json) -> J.Json:
  +hs = Pods.spec(h)
  +vs = Pods.spec(v)
  +hs1 = Pods.with_opt("activeDeadlineSeconds", Pods.get(vs, "activeDeadlineSeconds"), hs)
  +hs2 = Pods.idiff.apply("containers", Pods.idiff(Pods.items(Pods.get(hs, "containers")), Pods.items(Pods.get(vs, "containers")), Pods.cfg.images(cfg), []), hs1)
  +skip = Pods.skip_hosts(String.eq(M.Meta.lookup(Pods.hosts_rewritten_annotation(), Pods.annotations_of(h)), "true"))
  +hs3 = Pods.idiff.apply("initContainers", Pods.idiff(Pods.items(Pods.get(hs, "initContainers")), Pods.items(Pods.get(vs, "initContainers")), Pods.cfg.images(cfg), skip), hs2)
  +hs4 = Pods.with_opt("schedulingGates", Pods.get(vs, "schedulingGates"), hs3)
  +tols = Pods.add_new(Pods.add_new(Pods.items(Pods.get(vs, "tolerations")), Pods.items(Pods.get(hs, "tolerations"))), Pods.cfg.enforced(cfg))
  Pods.with("spec", Pods.with("tolerations", Pods.arr(tols), hs4), h)

def Pods.is_ann_ref(+p: String) -> Bool:
  Bool.and(String.starts_with(p, "metadata.annotations['"), Bool.and(String.ends_with(p, "']"), Nat.is_ge(String.length(p), 25n)))

def Pods.ann_ref_key(+p: String) -> String:
  String.take(String.drop(p, 22n), Nat.sub(String.length(p), 24n))

def Pods.tok_key.k(hit: Bool, k: String, rec: List<&2, String>) -> List<&2, String>:
  match hit:
    case True{}:
      k <> rec
    case False{}:
      rec

def Pods.tok_key.if(hit: Bool, +p: String, rec: List<&2, String>) -> List<&2, String>:
  match hit:
    case True{}:
      +k = Pods.ann_ref_key(p)
      Pods.tok_key.k(String.starts_with(k, Pods.token_annotation()), k, rec)
    case False{}:
      rec

def Pods.tok_keys.items(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, r}:
      Pods.tok_key.if(Bool.and(Pods.has(x, "fieldRef"), Pods.is_ann_ref(Pods.str(Pods.get(x, "fieldRef"), "fieldPath"))),
        Pods.str(Pods.get(x, "fieldRef"), "fieldPath"), Pods.tok_keys.items(r))

def Pods.tok_keys.srcs(ss: List<&2, J.Json>) -> List<&2, String>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, r}:
      List.append(&2, String, Pods.tok_keys.items(Pods.items(Pods.get(Pods.get(s, "downwardAPI"), "items"))), Pods.tok_keys.srcs(r))

def Pods.tok_keys.vols(vs: List<&2, J.Json>) -> List<&2, String>:
  match vs:
    case Nil{}:
      Nil{}
    case Con{v, r}:
      List.append(&2, String, Pods.tok_keys.srcs(Pods.items(Pods.get(Pods.get(v, "projected"), "sources"))), Pods.tok_keys.vols(r))

# GetExcludedAnnotations(pPod): the pod-local keys and the token annotations
# the host pod's projected volumes read.
def Pods.excluded(h: J.Json) -> List<&2, String>:
  List.append(&2, String, [Pods.autoscaler_annotation(), Pods.owner_references_annotation(), Pods.owner_set_kind_annotation(),
    Pods.namespace_annotation(), Pods.name_annotation(), Pods.uid_annotation(), Pods.sa_name_annotation(),
    Pods.hosts_rewritten_annotation(), Pods.labels_annotation()],
    Pods.tok_keys.vols(Pods.items(Pods.get(Pods.spec(h), "volumes"))))

def Pods.drop_ns.if(hit: Bool, k: String) -> String:
  match hit:
    case True{}:
      ""
    case False{}:
      k

# The label key exclusion of Diff: namespace label keys drop ("").
def Pods.drop_ns(+k: String) -> String:
  Pods.drop_ns.if(String.starts_with(k, M.Meta.namespace_label_prefix()), k)

# mergeMaps' key transform toward the host (HostLabel) or the virtual
# object (VirtualLabel, "" when it has none).
def Pods.tkey(to_host: Bool, vc: String, +k: String) -> String:
  match to_host:
    case True{}:
      Pods.drop_ns(M.Meta.host_label(vc, k))
    case False{}:
      Pods.drop_ns(Maybe.default(&2, String, M.Meta.virtual_label(vc, k), ""))

def Pods.merge.set1.if(empty: Bool, k: String, v: String, m: +List<M.KV>) -> +List<M.KV>:
  match empty:
    case True{}:
      m
    case False{}:
      M.Meta.insert(k, v, m)

def Pods.merge.sets(+to_host: Bool, +vc: String, xs: +List<M.KV>, m: +List<M.KV>) -> +List<M.KV>:
  match xs:
    case Nil{}:
      m
    case Con{M.KV{k, v}, r}:
      +tk = Pods.tkey(to_host, vc, k)
      Pods.merge.sets(to_host, vc, r, Pods.merge.set1.if(String.is_empty(tk), tk, v, m))

def Pods.merge.del1.if(empty: Bool, k: String, m: +List<M.KV>) -> +List<M.KV>:
  match empty:
    case True{}:
      m
    case False{}:
      M.Meta.delete(k, m)

def Pods.merge.dels(+to_host: Bool, +vc: String, ks: +List<String>, m: +List<M.KV>) -> +List<M.KV>:
  match ks:
    case Nil{}:
      m
    case Con{k, r}:
      +tk = Pods.tkey(to_host, vc, k)
      Pods.merge.dels(to_host, vc, r, Pods.merge.del1.if(String.is_empty(tk), tk, m))

# mergeMaps(before, after, target) with the label key transform. Deletes
# apply before sets (Go's order is random when two keys meet).
def Pods.merge(+to_host: Bool, +vc: String, +before: +List<M.KV>, +after: +List<M.KV>, target: +List<M.KV>) -> +List<M.KV>:
  Pods.merge.sets(to_host, vc, M.Meta.diff_sets(after, before, []), Pods.merge.dels(to_host, vc, M.Meta.diff_dels(before, after, []), target))

def Pods.labels_bidi.if(vchanged: Bool, hchanged: Bool, +vc: String, +vo: +List<M.KV>, +v: +List<M.KV>, +ho: +List<M.KV>, +h: +List<M.KV>) -> +List<M.KV> & +List<M.KV>:
  match vchanged:
    case True{}:
      (v, Pods.merge(True{}, vc, vo, v, h))
    case False{}:
      match hchanged:
        case True{}:
          (Pods.merge(False{}, vc, ho, h, v), h)
        case False{}:
          (v, h)

# LabelsBidirectionalUpdateFunction with Diff's namespace label exclusion:
# (new virtual labels, new host labels).
def Pods.labels_bidi(+vc: String, +vo: +List<M.KV>, +v: +List<M.KV>, +ho: +List<M.KV>, +h: +List<M.KV>) -> +List<M.KV> & +List<M.KV>:
  Pods.labels_bidi.if(Bool.not(M.Meta.map_eq(vo, v)), Bool.not(M.Meta.map_eq(ho, h)), vc, vo, v, ho, h)

def Pods.diff.owners(none: Bool, +rs: List<&2, J.Json>, a: +List<M.KV>) -> +List<M.KV>:
  match none:
    case True{}:
      M.Meta.delete(Pods.owner_references_annotation(), M.Meta.delete(Pods.owner_set_kind_annotation(), a))
    case False{}:
      Pods.ann.set_kind(Pods.owner_set_kind(rs), M.Meta.insert(Pods.owner_references_annotation(), Pods.refs_text(rs), a))

# The host annotations Diff refreshes from the virtual pod.
def Pods.diff.anns(+v: J.Json, ha: +List<M.KV>) -> +List<M.KV>:
  +rs = Pods.refs(v)
  Pods.diff.owners(List.is_empty(&2, J.Json, rs), rs, M.Meta.insert(Pods.labels_annotation(), Pods.labels_text(Pods.labels_of(v)), ha))

def Pods.with_meta(anns: +List<M.KV>, labels: +List<M.KV>, +x: J.Json) -> J.Json:
  Pods.with("metadata", Pods.with_map("labels", labels, Pods.with_map("annotations", anns, Pods.meta(x))), x)

# A match cannot take a local binder, so the computed pairs come in as
# parameters.
def Pods.diff.meta.go(+cfg: Cfg, +din: DInp, +h2: J.Json, +v1: J.Json, ab: +List<M.KV> & +List<M.KV>, lb: +List<M.KV> & +List<M.KV>) -> J.Json & J.Json:
  (va, ha) = ab
  (vl, hl) = lb
  +v2 = Pods.with_meta(va, vl, v1)
  (v2, Pods.with_meta(Pods.diff.anns(v2, ha), Pods.ns_labels(Pods.cfg.vc(cfg), Pods.dinp.ns_labels(din),
    M.Meta.keep_out(hl, [], [M.Meta.namespace_label_prefix()])), h2))

def Pods.diff.meta(+cfg: Cfg, +din: DInp, +ho: J.Json, +h2: J.Json, +vo: J.Json, +v1: J.Json) -> J.Json & J.Json:
  ab lb = M.Meta.annotations_bidirectional_update(Pods.obj(ho), Pods.obj(h2), Pods.obj(vo), Pods.obj(v1), Pods.excluded(h2)) Pods.labels_bidi(Pods.cfg.vc(cfg), Pods.labels_of(vo), Pods.labels_of(v1), Pods.labels_of(ho), Pods.labels_of(h2))
  Pods.diff.meta.go(cfg, din, h2, v1, ab, lb)

def Pods.diff.go(+cfg: Cfg, +din: DInp, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json, hc: J.Json) -> J.Json & J.Json:
  +h1 = Pods.with("status", Pods.with_opt("conditions", hc, Pods.status(h)), h)
  +vs1 = Pods.desired_status(cfg, Pods.status(h1), Pods.status(v))
  +vs2 = Pods.claims_status(Pods.cfg.claims(cfg), Pods.dinp.claims_back(din), vs1)
  +v1 = Pods.with("status", Pods.strip_sidecars(v, Pods.status(h1), vs2), v)
  Pods.diff.meta(cfg, din, ho, Pods.spec_diff(cfg, h1, v1), vo, v1)

# Diff(event) with event = NewSyncEventWithOld(hostOld, host, virtualOld,
# virtual): (new virtual pod, new host pod).
def Pods.diff.cc(+cfg: Cfg, +din: DInp, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json, cc: J.Json & J.Json) -> J.Json & J.Json:
  (cv, hc) = cc
  Pods.diff.go(cfg, din, ho, h, vo, v, hc)

def Pods.diff(+cfg: Cfg, +din: DInp, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> J.Json & J.Json:
  Pods.diff.cc(cfg, din, ho, h, vo, v, Pods.conditions_copy(cfg, Pods.conds(vo), Pods.conds(v), Pods.conds(ho), Pods.conds(h)))

# The syncer (syncer.go).

def Pods.patch_w(same: Bool, w: Write) -> List<&2, Write>:
  match same:
    case True{}:
      []
    case False{}:
      [w]

def Pods.maybe_w.k(resize: Bool, x: J.Json) -> List<&2, Write>:
  match resize:
    case True{}:
      [WResize{x}]
    case False{}:
      [WSecret{x}]

def Pods.maybe_w(m: Maybe<&2, J.Json>, +resize: Bool) -> List<&2, Write>:
  match m:
    case None{}:
      []
    case Some{x}:
      Pods.maybe_w.k(resize, x)

def Pods.resize.one.if(same: Bool, +c: J.Json, rec: List<&2, J.Json>) -> List<&2, J.Json>:
  match same:
    case True{}:
      rec
    case False{}:
      J.Json.obj([J.KV{"name", Pods.get(c, "name")}, J.KV{"resources", Pods.or_obj(Pods.get(c, "resources"))}]) <> rec

def Pods.resize.one(found: Maybe<&2, J.Json>, +c: J.Json, rec: List<&2, J.Json>) -> List<&2, J.Json>:
  match found:
    case None{}:
      rec
    case Some{p}:
      Pods.resize.one.if(Pods.same(Pods.or_obj(Pods.get(p, "resources")), Pods.or_obj(Pods.get(c, "resources"))), c, rec)

def Pods.resize.cs(vs: List<&2, J.Json>, +hs: List<&2, J.Json>) -> List<&2, J.Json>:
  match vs:
    case Nil{}:
      Nil{}
    case Con{+c, r}:
      Pods.resize.one(Pods.find_named(hs, Pods.str(c, "name")), c, Pods.resize.cs(r, hs))

def Pods.resize.fin(none: Bool, cs: List<&2, J.Json>) -> Maybe<&2, J.Json>:
  match none:
    case True{}:
      None{}
    case False{}:
      Some{J.Json.obj([J.KV{"spec", J.Json.obj([J.KV{"containers", Pods.arr(cs)}])}])}

# buildHostPodContainersResourcesResizePatch(vPod, pPod): the patch of the
# containers whose resources differ, None when none does. (Resources
# compare as JSON: quantities with the same value and another spelling
# differ here.)
def Pods.resize_patch(+v: J.Json, +h: J.Json) -> Maybe<&2, J.Json>:
  +cs = Pods.resize.cs(Pods.items(Pods.get(Pods.spec(v), "containers")),
    List.reverse(&2, J.Json, Pods.items(Pods.get(Pods.spec(h), "containers"))))
  Pods.resize.fin(List.is_empty(&2, J.Json, cs), cs)

def Pods.resize.if(on: Bool, +v: J.Json, +h: J.Json) -> Maybe<&2, J.Json>:
  match on:
    case True{}:
      Pods.resize_patch(v, h)
    case False{}:
      None{}

# The in-place resize patch: host K8s 1.35 or later only.
def Pods.resize(+cfg: Cfg, +v: J.Json, +h: J.Json) -> Maybe<&2, J.Json>:
  Pods.resize.if(Pods.at_least(Pods.cfg.host_version(cfg), 1, 35, 0), v, h)

def Pods.replace_owner.if(hit: Bool, r: J.Json, t: List<&2, J.Json>, pr: J.Json, rec: List<&2, J.Json>) -> List<&2, J.Json>:
  match hit:
    case True{}:
      pr <> t
    case False{}:
      r <> rec

def Pods.replace_owner(rs: List<&2, J.Json>, +uid: String, +pr: J.Json) -> List<&2, J.Json>:
  match rs:
    case Nil{}:
      Nil{}
    case Con{+r, +t}:
      Pods.replace_owner.if(String.eq(Pods.str(r, "uid"), uid), r, t, pr, Pods.replace_owner(t, uid, pr))

def Pods.with_refs(rs: List<&2, J.Json>, +s: J.Json) -> J.Json:
  Pods.with("metadata", Pods.with("ownerReferences", Pods.arr(rs), Pods.meta(s)), s)

def Pods.owner_add.if(has: Bool, +rs: List<&2, J.Json>, pr: J.Json, +s: J.Json) -> Maybe<&2, J.Json>:
  match has:
    case True{}:
      None{}
    case False{}:
      Some{Pods.with_refs(List.append(&2, J.Json, rs, [pr]), s)}

def Pods.set_pod_as_owner.o(o: Maybe<&2, Owner>, +rs: List<&2, J.Json>, +pr: J.Json, +s: J.Json) -> Maybe<&2, J.Json>:
  match o:
    case Some{Owner{av, k, n, u}}:
      Some{Pods.with_refs(Pods.replace_owner(rs, u, pr), s)}
    case None{}:
      Pods.owner_add.if(Pods.has_same(rs, pr), rs, pr, s)

# SetPodAsOwner(pPod, secret): the updated secret, None when no update is
# made.
def Pods.set_pod_as_owner(o: Maybe<&2, Owner>, +h: J.Json, +s: J.Json) -> Maybe<&2, J.Json>:
  +pr = J.Json.obj([J.KV{"apiVersion", J.JStr{"v1"}}, J.KV{"kind", J.JStr{"Pod"}}, J.KV{"name", J.JStr{Pods.name_of(h)}}, J.KV{"uid", J.JStr{Pods.uid_of(h)}}])
  +rs = Pods.refs(s)
  Pods.set_pod_as_owner.o(o, rs, pr, s)

def Pods.dgps(v: J.Json) -> String:
  Pods.num(J.Json.get(J.Json.get(v, "metadata"), "deletionGracePeriodSeconds"))

def Pods.sync.secret.if(on: Bool, s: Maybe<&2, J.Json>, +cfg: Cfg, +h: J.Json) -> List<&2, Write>:
  match on:
    case False{}:
      []
    case True{}:
      match s:
        case None{}:
          []
        case Some{sec}:
          Pods.maybe_w(Pods.set_pod_as_owner(Pods.cfg.owner(cfg), h, sec), False{})

def Pods.sync.patches(+nv: J.Json, +nh: J.Json, +v: J.Json, +h: J.Json) -> List<&2, Write>:
  List.append(&2, Write, Pods.patch_w(Pods.same(nv, v), WPatchVirtual{Pods.norm(nv)}), Pods.patch_w(Pods.same(nh, h), WPatchHost{Pods.norm(nh)}))

def Pods.sync.go(+cfg: Cfg, +sin: SInp, +h: J.Json, +v: J.Json, d: J.Json & J.Json) -> List<&2, Write>:
  (nv, nh) = d
  List.append(&2, Write, Pods.sync.secret.if(Pods.cfg.sa_secrets(cfg), Pods.sinp.secret(sin), cfg, h),
    List.append(&2, Write, Pods.maybe_w(Pods.resize(cfg, v, h), True{}), Pods.sync.patches(nv, nh, v, h)))

def Pods.sync.main(+cfg: Cfg, +sin: SInp, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> List<&2, Write>:
  Pods.sync.go(cfg, sin, h, v, Pods.diff(cfg, Pods.sinp.din(sin), ho, h, vo, v))

def Pods.new_ephs.if(has: Bool, c: J.Json, rec: List<&2, J.Json>) -> List<&2, J.Json>:
  match has:
    case True{}:
      rec
    case False{}:
      c <> rec

# The virtual ephemeral containers the host pod lacks (by name).
def Pods.new_ephs(cs: List<&2, J.Json>, +names: List<&2, String>) -> List<&2, J.Json>:
  match cs:
    case Nil{}:
      Nil{}
    case Con{+c, r}:
      Pods.new_ephs.if(M.Meta.elem(Pods.str(c, "name"), names), c, Pods.new_ephs(r, names))

def Pods.env_only(+vc: String, +ns: String, +env: +List<M.KV>, cs: List<&2, J.Json>) -> List<&2, J.Json>:
  match cs:
    case Nil{}:
      Nil{}
    case Con{+c, r}:
      Pods.with("env", Pods.arr(Pods.env_list(vc, ns, env, Pods.items(Pods.get(c, "env")))),
        Pods.with("envFrom", Pods.arr(Pods.tr_env_froms(vc, ns, Pods.items(Pods.get(c, "envFrom")))), c)) <> Pods.env_only(vc, ns, env, r)

def Pods.sync.eph.dns(missing: Bool, nw: List<&2, J.Json>, +cfg: Cfg, +sin: SInp, +h: J.Json, +v: J.Json) -> List<&2, Write>:
  match missing:
    case True{}:
      [WError{"waiting for DNS service IP"}]
    case False{}:
      +env = Pods.services_env(Pods.is_true(Pods.get(Pods.spec(v), "enableServiceLinks")), Pods.inp.services(Pods.sinp.inp(sin)), Pods.inp.kube_ip(Pods.sinp.inp(sin)))
      [WEphemeral{Pods.norm(Pods.with("spec", Pods.with("ephemeralContainers", Pods.arr(List.append(&2, J.Json, Pods.items(Pods.get(Pods.spec(h), "ephemeralContainers")),
        Pods.env_only(Pods.cfg.vc(cfg), Pods.ns_of(v), env, nw))), Pods.spec(h)), h))}, WRequeue{0}]

def Pods.sync.eph.if(none: Bool, nw: List<&2, J.Json>, +cfg: Cfg, +sin: SInp, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> List<&2, Write>:
  match none:
    case True{}:
      Pods.sync.main(cfg, sin, ho, h, vo, v)
    case False{}:
      Pods.sync.eph.dns(String.is_empty(Pods.inp.dns_ip(Pods.sinp.inp(sin))), nw, cfg, sin, h, v)

# syncEphemeralContainers: new virtual ephemeral containers go to the host
# (env translated only) and the reconcile requeues.
def Pods.sync.eph(+cfg: Cfg, +sin: SInp, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> List<&2, Write>:
  +nw = Pods.new_ephs(Pods.items(Pods.get(Pods.spec(v), "ephemeralContainers")), Pods.names(Pods.items(Pods.get(Pods.spec(h), "ephemeralContainers"))))
  Pods.sync.eph.if(List.is_empty(&2, J.Json, nw), nw, cfg, sin, ho, h, vo, v)

def Pods.sync.psa(ok: Bool, +cfg: Cfg, +sin: SInp, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> List<&2, Write>:
  match ok:
    case False{}:
      []
    case True{}:
      Pods.sync.eph(cfg, sin, ho, h, vo, v)

def Pods.sync.node.if(hempty: Bool, differ: Bool, exists: Bool, same: Bool, nh: String, +cfg: Cfg, +sin: SInp, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> List<&2, Write>:
  match hempty:
    case True{}:
      match differ:
        case True{}:
          [WDeleteVirtual{"30", ""}]
        case False{}:
          Pods.sync.psa(Pods.sinp.psa_ok(sin), cfg, sin, ho, h, vo, v)
    case False{}:
      match differ:
        case True{}:
          [WDeleteVirtual{"", ""}, WRequeue{0}]
        case False{}:
          match exists:
            case False{}:
              [WRequeue{0}]
            case True{}:
              match same:
                case False{}:
                  [WBind{nh}, WRequeue{0}]
                case True{}:
                  Pods.sync.psa(Pods.sinp.psa_ok(sin), cfg, sin, ho, h, vo, v)

# The node checks (ensureNode, and a virtual node name the host lacks).
def Pods.sync.node(+cfg: Cfg, +sin: SInp, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> List<&2, Write>:
  +nh = Pods.node_of(h)
  +nv = Pods.node_of(v)
  Pods.sync.node.if(String.is_empty(nh), Bool.and(Bool.not(String.eq(nv, nh)), Bool.not(String.is_empty(nv))),
    M.Meta.elem(nh, Pods.sinp.nodes(sin)), String.eq(nv, nh), nh, cfg, sin, ho, h, vo, v)

def Pods.sync.vdel(vd: Bool, +cfg: Cfg, +sin: SInp, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> List<&2, Write>:
  match vd:
    case True{}:
      [WDeleteHost{Pods.dgps(v), Pods.uid_of(h)}]
    case False{}:
      Pods.sync.node(cfg, sin, ho, h, vo, v)

def Pods.sync.hdel.w(vd: Bool, +h: J.Json, +v: J.Json) -> List<&2, Write>:
  match vd:
    case False{}:
      [WDeleteVirtual{Pods.or_str(Pods.num(Pods.get(Pods.spec(v), "terminationGracePeriodSeconds")), "30"), ""}]
    case True{}:
      Pods.patch_w(String.eq(Pods.dgps(v), Pods.dgps(h)), WDeleteVirtual{Pods.dgps(h), Pods.uid_of(v)})

# While the host pod is deleting, its status keeps reaching the virtual pod.
def Pods.sync.status_w(+cfg: Cfg, +h: J.Json, +v: J.Json) -> List<&2, Write>:
  +d = Pods.desired_status(cfg, Pods.status(h), Pods.status(v))
  Pods.patch_w(Pods.same(Pods.status(v), d), WVirtualStatus{Pods.norm(Pods.with("status", d, v))})

def Pods.sync.hdel(hd: Bool, +cfg: Cfg, +sin: SInp, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> List<&2, Write>:
  match hd:
    case True{}:
      List.append(&2, Write, Pods.sync.hdel.w(Pods.deleting(v), h, v), Pods.sync.status_w(cfg, h, v))
    case False{}:
      Pods.sync.vdel(Pods.deleting(v), cfg, sin, ho, h, vo, v)

def Pods.sync.blocked(b: Bool, +cfg: Cfg, +sin: SInp, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> List<&2, Write>:
  match b:
    case True{}:
      []
    case False{}:
      Pods.sync.hdel(Pods.deleting(h), cfg, sin, ho, h, vo, v)

# Sync: both pods exist.
def Pods.sync_both(+cfg: Cfg, +sin: SInp, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> List<&2, Write>:
  Pods.sync.blocked(Pods.sinp.blocked(sin), cfg, sin, ho, h, vo, v)

def Pods.sth.sched(+cfg: Cfg, +p: J.Json) -> List<&2, Write>:
  Pods.patch_w(Bool.and(Pods.cfg.virtual_scheduler(cfg), String.is_empty(Pods.node_of(p))), WCreateHost{Pods.norm(p)})

def Pods.sth.node.if(nosel: Bool, nonode: Bool, exists: Bool, sel: +List<M.KV>, +p: J.Json, +cfg: Cfg) -> List<&2, Write>:
  match nosel:
    case True{}:
      Pods.sth.sched(cfg, p)
    case False{}:
      match nonode:
        case True{}:
          Pods.sth.sched(cfg, Pods.with("spec", Pods.with("nodeSelector", Pods.obj_of(Pods.put_all(sel, Pods.map(Pods.get(Pods.spec(p), "nodeSelector")))), Pods.spec(p)), p))
        case False{}:
          match exists:
            case True{}:
              Pods.sth.sched(cfg, p)
            case False{}:
              [WEvent{"Warning", "SyncWarning", "Given nodeName " ++ Pods.node_of(p) ++ " does not exist in virtual cluster"}, WRequeue{15000}]

def Pods.sth.node(+p: J.Json, +cfg: Cfg, +sin: SInp) -> List<&2, Write>:
  +sel = Pods.cfg.node_selector(cfg)
  Pods.sth.node.if(List.is_empty(&2, M.KV, sel), String.is_empty(Pods.node_of(p)), M.Meta.elem(Pods.node_of(p), Pods.sinp.nodes(sin)), sel, p, cfg)

def Pods.sth.check(e: Maybe<&2, String>, +cfg: Cfg, +sin: SInp, +v: J.Json) -> List<&2, Write>:
  match e:
    case Some{m}:
      [WError{m}]
    case None{}:
      Pods.sth.node(Pods.translate(cfg, Pods.sinp.inp(sin), v), cfg, sin)

def Pods.sth.dns(missing: Bool, +cfg: Cfg, +sin: SInp, +v: J.Json) -> List<&2, Write>:
  match missing:
    case True{}:
      [WError{"waiting for DNS service IP"}]
    case False{}:
      Pods.sth.check(Pods.check(cfg, v), cfg, sin, v)

def Pods.sth.psa(ok: Bool, +cfg: Cfg, +sin: SInp, +v: J.Json) -> List<&2, Write>:
  match ok:
    case False{}:
      []
    case True{}:
      Pods.sth.dns(String.is_empty(Pods.inp.dns_ip(Pods.sinp.inp(sin))), cfg, sin, v)

def Pods.sth.if(b: Bool, gone: Bool, +cfg: Cfg, +sin: SInp, +v: J.Json) -> List<&2, Write>:
  match b:
    case True{}:
      []
    case False{}:
      match gone:
        case True{}:
          [WDeleteVirtual{"0", ""}]
        case False{}:
          Pods.sth.psa(Pods.sinp.psa_ok(sin), cfg, sin, v)

# SyncToHost: only the virtual pod exists.
def Pods.sync_to_host(+cfg: Cfg, +sin: SInp, ho: Maybe<&2, J.Json>, +v: J.Json) -> List<&2, Write>:
  Pods.sth.if(Pods.sinp.blocked(sin), Bool.or(Maybe.is_some(&2, J.Json, ho), Bool.or(Pods.deleting(v), Pods.has(Pods.status(v), "startTime"))), cfg, sin, v)

def Pods.sa_clear(sync: Bool, s: J.Json) -> J.Json:
  match sync:
    case True{}:
      s
    case False{}:
      Pods.without("serviceAccountName", Pods.without("serviceAccount", s))

# VirtualMetadata(pPod, name) and the pod fields SyncToVirtual resets.
def Pods.virtual_pod(+cfg: Cfg, name: String, ns: String, +h: J.Json) -> J.Json:
  +m = Pods.with("name", J.JStr{name}, Pods.with("namespace", J.JStr{ns}, Pods.reset(Pods.meta(h))))
  Pods.with("metadata", Pods.with_map("annotations", M.Meta.virtual_annotations(Pods.obj(h), None{}, []),
      Pods.with_map("labels", Maybe.default(&2, List<&2, M.KV>, M.Meta.virtual_labels_map(Pods.cfg.vc(cfg), Some{Pods.labels_of(h)}, [], []), []), m)),
    Pods.with("spec", Pods.without("nodeName", Pods.sa_clear(Pods.cfg.sa_sync(cfg), Pods.spec(h))), h))

def Pods.stv.name(empty: Bool, +name: String, +ns: String, +cfg: Cfg, +h: J.Json) -> List<&2, Write>:
  match empty:
    case True{}:
      []
    case False{}:
      [WCreateVirtual{Pods.norm(Pods.virtual_pod(cfg, name, ns, h))}]

def Pods.stv.if(del: Bool, +cfg: Cfg, +h: J.Json) -> List<&2, Write>:
  match del:
    case True{}:
      [WDeleteHost{"", ""}]
    case False{}:
      +name = M.Meta.lookup(M.Meta.name_annotation(), Pods.annotations_of(h))
      Pods.stv.name(String.is_empty(name), name, M.Meta.lookup(M.Meta.namespace_annotation(), Pods.annotations_of(h)), cfg, h)

# SyncToVirtual: only the host pod exists. The virtual name comes from the
# object-name and object-namespace annotations (the mapper's annotation
# path); a host pod without them is left alone.
def Pods.sync_to_virtual(+cfg: Cfg, vo: Maybe<&2, J.Json>, +h: J.Json) -> List<&2, Write>:
  Pods.stv.if(Bool.or(Maybe.is_some(&2, J.Json, vo), M.Meta.should_delete_host_object(Pods.obj(h))), cfg, h)

# One reconcile of the pod syncer, a pure function of the snapshots
# (hostOld, host, virtualOld, virtual): the writes to make, in order.
def Pods.sync(+cfg: Cfg, +sin: SInp, ho: Maybe<&2, J.Json>, h: Maybe<&2, J.Json>, vo: Maybe<&2, J.Json>, v: Maybe<&2, J.Json>) -> List<&2, Write>:
  match h v:
    case None{} None{}:
      []
    case None{} Some{x}:
      Pods.sync_to_host(cfg, sin, ho, x)
    case Some{y} None{}:
      Pods.sync_to_virtual(cfg, vo, y)
    case Some{+y} Some{+x}:
      Pods.sync_both(cfg, sin, Maybe.default(&2, J.Json, ho, y), y, Maybe.default(&2, J.Json, vo, x), x)
