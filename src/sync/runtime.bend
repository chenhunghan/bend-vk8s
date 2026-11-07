import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../translate/names.bend as N
import ../translate/meta.bend as M
import ../translate/services.bend as S
import ./core.bend as C
import ../translate/configs.bend as F

# Shared pure policy for the classic syncer. IO must preserve snapshots
# until all ordered writes succeed. A failed GET is not a missing object:
# only a 404 supplies None to a translator.
#
# Keep the existing translators' JSON and Outcome types. Their contracts
# use 0.2.0.0; the eventual IO adapter must bridge the 0.3.0.0 client at
# the boundary, without changing the architect-owned laws.

# Default enabled resources, in the architect's conformance-first order.
# Source: a8ab30e chart/values.yaml and resources/register.go. PV and node
# constructors always register, but select fake syncers by default.
# These are resource identifiers, not the upstream log/controller names.
# This list does not claim that every translator is implemented.
def Runtime.defaults() -> +List<String>:
  ["services", "endpoints", "endpointslices", "configmaps", "secrets", "pods",
   "fake-nodes", "events", "persistentvolumeclaims", "fake-persistentvolumes"]

# Generic namespaced mapping. The services adapter must use Svc.host_ref
# for the special default/kubernetes service; cluster resources have their
# own mapping and must not use this function.
def Runtime.host_name(vc: String, ns: String, name: String) -> String:
  N.Names.host_name(name, ns, vc)

# Only for translated, namespaced host resources. Real host nodes and
# events are not tagged by vk8s and require their own watch filters.
def Runtime.selector(vc: String) -> String:
  M.Meta.marker_label() ++ "=" ++ vc

# Annotations, not splitting the translated name, recover the virtual key.
# An empty name is unmapped; the IO adapter must not GET an empty key.
def Runtime.virtual_key(annotations: List<&2, J.KV>) -> String & String:
  +ann = S.Svc.map(J.Json.obj(annotations))
  ns name = M.Meta.lookup(M.Meta.namespace_annotation(), ann) M.Meta.lookup(M.Meta.name_annotation(), ann)
  (ns, name)

# vk8s architecture: Lease in the virtual cluster's kube-system.
# Upstream uses SafeConcatName("vcluster", vc, "controller") on the host.
def Runtime.lease_name(vc: String) -> String:
  "vcluster-syncer-" ++ vc

# delay is used only for RequeueAfter. NoRequeue and RequeueNow both have
# zero delay, but remain distinct constructors in the returned Outcome.
def Runtime.milliseconds.if(large: Bool, seconds: U32) -> U32:
  match large:
    case True{}:
      4294967295
    case False{}:
      (seconds * 1000 : U32)

def Runtime.delay(rq: S.Requeue) -> U32:
  match rq:
    case S.NoRequeue{}:
      0
    case S.RequeueNow{}:
      0
    case S.RequeueAfter{+seconds}:
      Runtime.milliseconds.if(U32.is_gt(seconds, 4294967), seconds)

# Four stable buckets. Preserve translator order inside each bucket.
# Host writes precede virtual writes; deletes precede replacement writes
# within each cluster. These writes belong to one reconcile, not a batch
# of unrelated resource kinds.
def Runtime.phase(w: S.Write) -> U32:
  match w:
    case S.HostDelete{ns, name}:
      0
    case S.HostCreate{o}:
      1
    case S.HostUpdate{o}:
      1
    case S.VirtualDelete{ns, name}:
      2
    case S.VirtualCreate{o}:
      3
    case S.VirtualUpdate{o}:
      3

def Runtime.keep(yes: Bool, w: S.Write, rest: List<&2, S.Write>) -> List<&2, S.Write>:
  match yes:
    case True{}:
      w <> rest
    case False{}:
      rest

def Runtime.bucket(ws: List<&2, S.Write>, +phase: U32) -> List<&2, S.Write>:
  match ws:
    case Nil{}:
      []
    case Con{+w, rest}:
      Runtime.keep(U32.is_eq(Runtime.phase(w), phase), w, Runtime.bucket(rest, phase))

# Equal work in each parallel branch: two scans of the same write list.
def Runtime.half(+ws: List<&2, S.Write>, +phase: U32) -> List<&2, S.Write>:
  deletes writes = Runtime.bucket(ws, phase) Runtime.bucket(ws, (phase + 1 : U32))
  List.append(&2, S.Write, deletes, writes)

def Runtime.order(+ws: List<&2, S.Write>) -> List<&2, S.Write>:
  host virtual = Runtime.half(ws, 0) Runtime.half(ws, 2)
  List.append(&2, S.Write, host, virtual)

def Runtime.ordered(out: S.Outcome) -> S.Outcome:
  match out:
    case S.Outcome{ws, rq}:
      S.Outcome{Runtime.order(ws), rq}

def Runtime.requeue(out: S.Outcome) -> S.Requeue:
  match out:
    case S.Outcome{ws, rq}:
      rq

# Comparison for the executable tests: use the translators' canonical
# comparison, never JSON text or object member order.
def Runtime.same_write(a: S.Write, b: S.Write) -> Bool:
  match a b:
    case S.HostCreate{x} S.HostCreate{y}:
      S.Svc.eq(x, y)
    case S.HostUpdate{x} S.HostUpdate{y}:
      S.Svc.eq(x, y)
    case S.VirtualCreate{x} S.VirtualCreate{y}:
      S.Svc.eq(x, y)
    case S.VirtualUpdate{x} S.VirtualUpdate{y}:
      S.Svc.eq(x, y)
    case S.HostDelete{ns, n} S.HostDelete{ms, m}:
      Bool.and(String.eq(ns, ms), String.eq(n, m))
    case S.VirtualDelete{ns, n} S.VirtualDelete{ms, m}:
      Bool.and(String.eq(ns, ms), String.eq(n, m))
    case _ _:
      False{}

def Runtime.same_writes(xs: List<&2, S.Write>, ys: List<&2, S.Write>) -> Bool:
  match xs ys:
    case Nil{} Nil{}:
      True{}
    case Con{x, xt} Con{y, yt}:
      Bool.and(Runtime.same_write(x, y), Runtime.same_writes(xt, yt))
    case _ _:
      False{}

# Services are the first wired translator. Core.decide preserves cached
# old objects and rejects stale reads before the
# service-specific step runs. The host adapter must obtain managed from
# Core.is_managed_to_host and the mappings store, not from mere existence.
# services.Options: ObjectCaching=true, DisableUIDDeletion=true.
def Runtime.service_cfg(+c: S.Cfg) -> C.Cfg:
  C.Cfg{S.Svc.vc(c), S.Svc.target(c), S.Svc.kind(), "service", True{}, False{}, False{}}

def Runtime.round_up(nonzero: Bool) -> U32:
  match nonzero:
    case True{}:
      1
    case False{}:
      0

# Core's current UID-deletion wait is 1000 ms. Round up if more waits are
# added, because the shared translator Outcome expresses whole seconds.
def Runtime.seconds(+ms: U32) -> U32:
  ((ms / 1000) + Runtime.round_up(Bool.not(U32.is_eq((ms % 1000 : U32), 0))) : U32)

def Runtime.service_dispatch(d: C.Decision, +c: S.Cfg, young: Bool) -> S.Outcome:
  match d:
    case C.DSkip{}:
      S.Outcome{[], S.NoRequeue{}}
    case C.DRequeue{}:
      S.Outcome{[], S.RequeueNow{}}
    case C.DRequeueAfter{ms}:
      S.Outcome{[], S.RequeueAfter{Runtime.seconds(ms)}}
    case C.DDeleteHost{h, reason}:
      S.Svc.done([S.Svc.delete_host(h)])
    case C.DToHost{ho, v}:
      S.Svc.sync_to_host(c, ho, v)
    case C.DToVirtual{vo, h}:
      S.Svc.sync_to_virtual(c, young, vo, h)
    case C.DSync{vo, +v, ho, +h}:
      S.Svc.sync(c, Maybe.default(&2, J.Json, ho, h), h, Maybe.default(&2, J.Json, vo, v), v)

def Runtime.special_virtual(v: Maybe<&2, J.Json>) -> Bool:
  match v:
    case None{}:
      False{}
    case Some{+o}:
      S.Svc.is_kubernetes(S.Svc.namespace(o), S.Svc.name(o))

def Runtime.special_host(+c: S.Cfg, h: Maybe<&2, J.Json>) -> Bool:
  match h:
    case None{}:
      False{}
    case Some{+o}:
      Bool.and(String.eq(S.Svc.namespace(o), S.Svc.current(c)), String.eq(S.Svc.name(o), S.Svc.vc(c)))

def Runtime.services.if(special: Bool, +c: S.Cfg, young: Bool, managed: Bool,
  vo: Maybe<&2, J.Json>, v: Maybe<&2, J.Json>, ho: Maybe<&2, J.Json>, h: Maybe<&2, J.Json>) -> S.Outcome:
  match special:
    case True{}:
      S.Svc.sync_kubernetes(h, v)
    case False{}:
      Runtime.service_dispatch(C.Core.decide(Runtime.service_cfg(c), managed, vo, v, ho, h), c, young)

# Snapshots: virtual old/new, host old/new. A cold cache is None; it must
# never be fabricated by passing the current snapshot as the old snapshot.
# The special service uses the existing specialservices implementation.
def Runtime.services(+c: S.Cfg, young: Bool, managed: Bool,
  vo: Maybe<&2, J.Json>, +v: Maybe<&2, J.Json>, ho: Maybe<&2, J.Json>, +h: Maybe<&2, J.Json>) -> S.Outcome:
  Runtime.ordered(Runtime.services.if(Bool.or(Runtime.special_virtual(v), Runtime.special_host(c, h)), c, young, managed, vo, v, ho, h))

def Runtime.writes(out: S.Outcome) -> List<&2, S.Write>:
  match out:
    case S.Outcome{ws, rq}:
      ws


# Config resources share the framework but keep separate field rules.
# ServiceAccounts remain disabled by default; dispatch does not enable one.
type ConfigResource is Data:
  ConfigMapResource{}
  SecretResource{}
  ServiceAccountResource{}

def Runtime.config_kind(r: ConfigResource) -> String:
  match r:
    case ConfigMapResource{}:
      F.Configs.cm_kind()
    case SecretResource{}:
      F.Configs.secret_kind()
    case ServiceAccountResource{}:
      F.Configs.sa_kind()

def Runtime.config_name(r: ConfigResource) -> String:
  match r:
    case ConfigMapResource{}:
      "configmap"
    case SecretResource{}:
      "secret"
    case ServiceAccountResource{}:
      "serviceaccount"

def Runtime.config_cfg(+r: ConfigResource, +c: S.Cfg) -> C.Cfg:
  C.Cfg{S.Svc.vc(c), S.Svc.target(c), Runtime.config_kind(r), Runtime.config_name(r), True{}, True{}, False{}}

def Runtime.config_to_host(r: ConfigResource, c: S.Cfg, all: Bool, refs: +List<F.Ref>, ho: Maybe<&2, J.Json>, v: J.Json) -> S.Outcome:
  match r:
    case ConfigMapResource{}:
      F.Configs.cm_sync_to_host(c, all, refs, ho, v)
    case SecretResource{}:
      F.Configs.secret_sync_to_host(c, all, refs, ho, v)
    case ServiceAccountResource{}:
      F.Configs.sa_sync_to_host(c, ho, v)

def Runtime.config_to_virtual(r: ConfigResource, c: S.Cfg, all: Bool, refs: +List<F.Ref>, vo: Maybe<&2, J.Json>, h: J.Json) -> S.Outcome:
  match r:
    case ConfigMapResource{}:
      F.Configs.cm_sync_to_virtual(c, all, refs, vo, h)
    case SecretResource{}:
      F.Configs.secret_sync_to_virtual(c, all, refs, vo, h)
    case ServiceAccountResource{}:
      F.Configs.sa_sync_to_virtual(c, vo, h)

def Runtime.config_sync(r: ConfigResource, c: S.Cfg, all: Bool, refs: +List<F.Ref>, ho: J.Json, h: J.Json, vo: J.Json, v: J.Json) -> S.Outcome:
  match r:
    case ConfigMapResource{}:
      F.Configs.cm_sync(c, all, refs, ho, h, vo, v)
    case SecretResource{}:
      F.Configs.secret_sync(c, all, refs, ho, h, vo, v)
    case ServiceAccountResource{}:
      F.Configs.sa_sync(c, ho, h, vo, v)

def Runtime.config_dispatch(d: C.Decision, r: ConfigResource, c: S.Cfg, all: Bool, refs: +List<F.Ref>) -> S.Outcome:
  match d:
    case C.DSkip{}:
      S.Svc.done([])
    case C.DRequeue{}:
      S.Outcome{[], S.RequeueNow{}}
    case C.DRequeueAfter{ms}:
      S.Outcome{[], S.RequeueAfter{Runtime.seconds(ms)}}
    case C.DDeleteHost{h, reason}:
      S.Svc.done([S.Svc.delete_host(h)])
    case C.DToHost{ho, v}:
      Runtime.config_to_host(r, c, all, refs, ho, v)
    case C.DToVirtual{vo, h}:
      Runtime.config_to_virtual(r, c, all, refs, vo, h)
    case C.DSync{vo, +v, ho, +h}:
      Runtime.config_sync(r, c, all, refs, Maybe.default(&2, J.Json, ho, h), h, Maybe.default(&2, J.Json, vo, v), v)

# refs is computed from the actual pod/ingress snapshots through Configs.
# The default all=false must not be overridden merely to copy every object.
# The caller must skip unmapped host keys, including host kube-root-ca.crt.
def Runtime.configs(+r: ConfigResource, +c: S.Cfg, all: Bool, refs: +List<F.Ref>, managed: Bool,
  vo: Maybe<&2, J.Json>, v: Maybe<&2, J.Json>, ho: Maybe<&2, J.Json>, h: Maybe<&2, J.Json>) -> S.Outcome:
  Runtime.ordered(Runtime.config_dispatch(C.Core.decide(Runtime.config_cfg(r, c), managed, vo, v, ho, h), r, c, all, refs))

# The IO adapter's resource table (host/syncer.bend). These are the kinds
# whose translators are merged and wired; the rest of Runtime.defaults
# waits for its translator. Index i owns watch sources 2i (virtual) and
# 2i+1 (host); source 2 * length is the virtual pods watch, which only
# supplies ConfigMap and Secret references.
type Kind is Data:
  KServices{}
  KConfigs{r: ConfigResource}

def Runtime.wired() -> List<&2, Kind>:
  [KServices{}, KConfigs{ConfigMapResource{}}, KConfigs{SecretResource{}}]

def Runtime.kind_nth.go(ks: List<&2, Kind>, n: Nat) -> Maybe<&2, Kind>:
  match ks n:
    case Nil{} m:
      None{}
    case Con{k, t} 0n:
      Some{k}
    case Con{k, t} 1n+m:
      Runtime.kind_nth.go(t, m)

def Runtime.kind_nth(n: Nat) -> Maybe<&2, Kind>:
  Runtime.kind_nth.go(Runtime.wired(), n)

def Runtime.config_id(r: ConfigResource) -> String:
  match r:
    case ConfigMapResource{}:
      "configmaps"
    case SecretResource{}:
      "secrets"
    case ServiceAccountResource{}:
      "serviceaccounts"

def Runtime.kind_id(k: Kind) -> String:
  match k:
    case KServices{}:
      "services"
    case KConfigs{r}:
      Runtime.config_id(r)

def Runtime.config_index(r: ConfigResource) -> U32:
  match r:
    case ConfigMapResource{}:
      1
    case SecretResource{}:
      2
    case ServiceAccountResource{}:
      3

# The kind's position in Runtime.wired.
def Runtime.kind_index(k: Kind) -> U32:
  match k:
    case KServices{}:
      0
    case KConfigs{r}:
      Runtime.config_index(r)

def Runtime.kind_of(id: String) -> Maybe<&2, Kind>:
  match id:
    case "services":
      Some{KServices{}}
    case "configmaps":
      Some{KConfigs{ConfigMapResource{}}}
    case "secrets":
      Some{KConfigs{SecretResource{}}}
    case _:
      None{}

# A queue key names the virtual object: "<kind id>|<namespace>/<name>".
def Runtime.key(+id: String, +ns: String, +name: String) -> String:
  id ++ "|" ++ ns ++ "/" ++ name

type Key is Data:
  Key{id: String, namespace: String, name: String}

def Runtime.parse_key.ns(+id: String, parts: List<&2, String>) -> Maybe<&2, Key>:
  match parts:
    case Con{ns, Con{name, Nil{}}}:
      Some{Key{id, ns, name}}
    case _:
      None{}

def Runtime.parse_key.go(parts: List<&2, String>) -> Maybe<&2, Key>:
  match parts:
    case Con{id, Con{rest, Nil{}}}:
      Runtime.parse_key.ns(id, String.split(rest, '/'))
    case _:
      None{}

def Runtime.parse_key(s: String) -> Maybe<&2, Key>:
  Runtime.parse_key.go(String.split(s, '|'))

def Runtime.config_host_ref(r: ConfigResource, +c: S.Cfg, +ns: String, +name: String) -> String & String:
  match r:
    case ConfigMapResource{}:
      F.Configs.cm_host_ref(c, ns, name)
    case SecretResource{}:
      F.Configs.secret_host_ref(c, ns, name)
    case ServiceAccountResource{}:
      F.Configs.sa_host_ref(c, ns, name)

# The host (namespace, name) of a virtual object of kind k.
def Runtime.host_ref(k: Kind, +c: S.Cfg, +ns: String, +name: String) -> String & String:
  match k:
    case KServices{}:
      S.Svc.host_ref(c, ns, name)
    case KConfigs{r}:
      Runtime.config_host_ref(r, c, ns, name)

def Runtime.config_virtual_ref(r: ConfigResource, +c: S.Cfg, +h: J.Json) -> String & String:
  match r:
    case ConfigMapResource{}:
      F.Configs.cm_virtual_ref(c, h)
    case SecretResource{}:
      F.Configs.virtual_ref(h)
    case ServiceAccountResource{}:
      F.Configs.virtual_ref(h)

# The virtual (namespace, name) of a host object of kind k: its
# object-name and object-namespace annotations.
def Runtime.virtual_ref(k: Kind, +c: S.Cfg, +h: J.Json) -> String & String:
  match k:
    case KServices{}:
      S.Svc.virtual_ref(c, h)
    case KConfigs{r}:
      Runtime.config_virtual_ref(r, c, h)

# default/kubernetes is vcluster's special service: it mirrors the host
# service of the vcluster itself, which a vk8s microVM does not have.
def Runtime.skip(k: Kind, +ns: String, +name: String) -> Bool:
  match k:
    case KServices{}:
      S.Svc.is_kubernetes(ns, name)
    case KConfigs{r}:
      False{}

def Runtime.key_list(skip: Bool, +id: String, +ns: String, +name: String) -> List<&2, String>:
  match skip:
    case True{}:
      []
    case False{}:
      [Runtime.key(id, ns, name)]

def Runtime.ref_key.go(+k: Kind, +ns: String, +name: String) -> List<&2, String>:
  Runtime.key_list(Bool.or(String.is_empty(name), Runtime.skip(k, ns, name)), Runtime.kind_id(k), ns, name)

def Runtime.ref_key(+k: Kind, r: String & String) -> List<&2, String>:
  match r:
    case (ns, name):
      Runtime.ref_key.go(k, ns, name)

# The queue key an event on object o queues: a virtual object names
# itself, a host object names its virtual object (no key if unmapped).
def Runtime.obj_key(+k: Kind, host: Bool, +c: S.Cfg, +o: J.Json) -> List<&2, String>:
  match host:
    case True{}:
      Runtime.ref_key(k, Runtime.virtual_ref(k, c, o))
    case False{}:
      Runtime.ref_key(k, (S.Svc.namespace(o), S.Svc.name(o)))

def Runtime.ref_keys(+id: String, refs: +List<F.Ref>) -> List<&2, String>:
  match refs:
    case Nil{}:
      []
    case Con{F.Ref{ns, name}, t}:
      Runtime.key(id, ns, name) <> Runtime.ref_keys(id, t)

# A change to a virtual pod queues the ConfigMaps and Secrets it refers
# to (useSecretsForSATokens is false by default).
def Runtime.pod_keys(+c: S.Cfg, +pod: J.Json) -> List<&2, String>:
  List.append(&2, String, Runtime.ref_keys("configmaps", F.Configs.pod_config_maps(pod)),
    Runtime.ref_keys("secrets", F.Configs.pod_secrets(c, False{}, pod)))

def Runtime.config_refs(r: ConfigResource, +c: S.Cfg, +pod: J.Json) -> +List<F.Ref>:
  match r:
    case ConfigMapResource{}:
      F.Configs.pod_config_maps(pod)
    case SecretResource{}:
      F.Configs.pod_secrets(c, False{}, pod)
    case ServiceAccountResource{}:
      []

def Runtime.refs_of(+r: ConfigResource, +c: S.Cfg, pods: List<&2, J.Json>) -> +List<F.Ref>:
  match pods:
    case Nil{}:
      []
    case Con{p, t}:
      F.Configs.cat(Runtime.config_refs(r, c, p), Runtime.refs_of(r, c, t))

# The references every virtual pod makes to objects of kind k.
def Runtime.refs(k: Kind, +c: S.Cfg, pods: List<&2, J.Json>) -> +List<F.Ref>:
  match k:
    case KServices{}:
      []
    case KConfigs{r}:
      Runtime.refs_of(r, c, pods)

def Runtime.core_cfg(k: Kind, +c: S.Cfg) -> C.Cfg:
  match k:
    case KServices{}:
      Runtime.service_cfg(c)
    case KConfigs{r}:
      Runtime.config_cfg(r, c)

def Runtime.managed.of(+k: Kind, +c: S.Cfg, r: String & String, +h: J.Json) -> Bool:
  C.Core.is_managed_to_host(Runtime.core_cfg(k, c), False{}, Some{F.Configs.ref_name(r)}, h)

# IsManaged of the host object: no mappings store entry in classic
# single-namespace mode, so the translate.Default rule with the expected
# host name.
def Runtime.managed(+k: Kind, +c: S.Cfg, +ns: String, +name: String, h: Maybe<&2, J.Json>) -> Bool:
  match h:
    case None{}:
      False{}
    case Some{+o}:
      Runtime.managed.of(k, c, Runtime.host_ref(k, c, ns, name), o)

# One sync step of kind k from the snapshots (ordered writes).
def Runtime.step(k: Kind, +c: S.Cfg, refs: +List<F.Ref>, managed: Bool,
  vo: Maybe<&2, J.Json>, v: Maybe<&2, J.Json>, ho: Maybe<&2, J.Json>, h: Maybe<&2, J.Json>) -> S.Outcome:
  match k:
    case KServices{}:
      Runtime.services(c, False{}, managed, vo, v, ho, h)
    case KConfigs{r}:
      Runtime.configs(r, c, False{}, refs, managed, vo, v, ho, h)

# The API call a write makes, on the host (True) or the virtual cluster.
type Call is Data:
  CCreate{host: Bool, namespace: String, obj: J.Json}
  CUpdate{host: Bool, namespace: String, name: String, obj: J.Json}
  CDelete{host: Bool, namespace: String, name: String}

def Runtime.call(w: S.Write) -> Call:
  match w:
    case S.HostCreate{+o}:
      CCreate{True{}, S.Svc.namespace(o), o}
    case S.HostUpdate{+o}:
      CUpdate{True{}, S.Svc.namespace(o), S.Svc.name(o), o}
    case S.HostDelete{ns, name}:
      CDelete{True{}, ns, name}
    case S.VirtualCreate{+o}:
      CCreate{False{}, S.Svc.namespace(o), o}
    case S.VirtualUpdate{+o}:
      CUpdate{False{}, S.Svc.namespace(o), S.Svc.name(o), o}
    case S.VirtualDelete{ns, name}:
      CDelete{False{}, ns, name}

# Syncer flags: vk8s-init syncer --host-kubeconfig F --host-namespace NS
# --name VC --service-cidr CIDR [--kubeconfig VIRTUAL]. The virtual
# kubeconfig defaults to the guest's admin.conf, the host one to the
# share, the host namespace to vcluster-<name> (vk8s create's default).
type Flags is Data:
  Flags{kubeconfig: String, host_kubeconfig: String, host_namespace: String, name: String, service_cidr: String}

def Runtime.flag.go(hit: Bool, +v: String, rest: Maybe<&2, String>) -> Maybe<&2, String>:
  match hit:
    case True{}:
      Some{v}
    case False{}:
      rest

def Runtime.flag(xs: +List<String>, +f: String) -> Maybe<&2, String>:
  match xs:
    case Nil{}:
      None{}
    case Con{+x, +t}:
      match t:
        case Nil{}:
          None{}
        case Con{+v, t2}:
          Runtime.flag.go(String.eq(x, f), v, Runtime.flag(t, f))

def Runtime.flag_or(+xs: +List<String>, +f: String, +d: String) -> String:
  Maybe.default(&2, String, Runtime.flag(xs, f), d)

def Runtime.flags(+args: +List<String>) -> Flags:
  +name = Runtime.flag_or(args, "--name", "vk8s")
  Flags{Runtime.flag_or(args, "--kubeconfig", "/var/lib/vcluster/pki/admin.conf"),
    Runtime.flag_or(args, "--host-kubeconfig", "/var/lib/vk8s-host/host-kubeconfig"),
    Runtime.flag_or(args, "--host-namespace", "vcluster-" ++ name),
    name,
    Runtime.flag_or(args, "--service-cidr", "10.96.0.0/12")}

def Flags.kubeconfig(f: Flags) -> String:
  match f:
    case Flags{k, h, ns, n, s}:
      k

def Flags.host_kubeconfig(f: Flags) -> String:
  match f:
    case Flags{k, h, ns, n, s}:
      h

def Flags.host_namespace(f: Flags) -> String:
  match f:
    case Flags{k, h, ns, n, s}:
      ns

def Flags.name(f: Flags) -> String:
  match f:
    case Flags{k, h, ns, n, s}:
      n

# Single-namespace mode: the target and current namespaces are both the
# host namespace (vk8s runs no syncer pod on the host).
def Flags.cfg(f: Flags) -> S.Cfg:
  match f:
    case Flags{k, h, +ns, n, s}:
      S.Cfg{n, ns, ns}
