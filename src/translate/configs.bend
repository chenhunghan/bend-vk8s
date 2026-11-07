import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ./meta.bend as M
import ./names.bend as N
import ./services.bend as S

# ConfigMaps, Secrets and ServiceAccounts toHost (vcluster
# pkg/controllers/resources/configmaps/to_host_syncer.go,
# secrets/to_host_syncer.go, serviceaccounts/syncer.go) and the reference
# scans that decide which config maps and secrets are used
# (pkg/mappings/resources/configmaps.go, secrets.go), as pure functions of
# object snapshots.
#
# Objects, writes, outcomes and the configuration (S.Cfg) are those of
# services.bend: a sync step takes the snapshots vcluster's generic syncer
# hands it and returns the writes to make, host writes before virtual ones.
#
# A config map or a secret is synced only when it is used
# (isConfigMapUsed, isSecretUsed): its annotation vcluster.loft.sh/force-sync
# is "true", or sync.toHost.<kind>.all is set, or a virtual object refers to
# it. vcluster reads the references from its mapping store, which the pod
# and ingress syncers fill; here the caller passes them in, as a list of
# Refs that Configs.pod_config_maps, Configs.pod_secrets and
# Configs.ingress_secrets compute from the virtual pods and ingresses.
#
# Single-namespace mode only. Translate patches (Pro) and the Pro importer
# are not supported. The name mapping is the pure one of names.bend:
# vcluster's mapping store is not modelled, so a host object maps back to
# its virtual object through its name and namespace annotations.
#
# vcluster quirks kept as they are:
# - kube-root-ca.crt: the config maps mapper renames a host name that IS
#   "kube-root-ca.crt" to vcluster-kube-root-ca.crt-x-<vc>
#   (mappings/resources/configmaps.go:35-40). In single-namespace mode the
#   host name it checks is already <name>-x-<ns>-x-<vc>, so the rename never
#   fires: a virtual kube-root-ca.crt syncs as kube-root-ca.crt-x-<ns>-x-<vc>.
#   Back from the host, kube-root-ca.crt maps to no virtual object and
#   vcluster-kube-root-ca.crt-x-<vc> maps to kube-root-ca.crt (45-60).
# - A configMap or secret volume (or projected source) counts as a
#   reference even with an empty name; env and envFrom refs need a name;
#   every image pull secret counts (configmaps.go:139-150,
#   secrets.go:176-221).
# - With sync.toHost.pods.useSecretsForSATokens, a projected service account
#   token refers to the HOST name of the secret <pod>-sa-token in the host
#   namespace (token.SecretNameFromPodName is mappings.VirtualToHost).
# - The ingress annotations nginx.ingress.kubernetes.io/auth-secret,
#   auth-tls-secret and proxy-ssl-secret name "secret" or "namespace/secret"
#   (secrets.go:112-150). Go walks the annotation map in random order; here
#   the keys go in sorted order.
# - Create copies the whole virtual object, so data, binaryData,
#   stringData and immutable go to the host as they are; a secret of type
#   kubernetes.io/service-account-token becomes Opaque on the host
#   (secrets/to_host_syncer.go:89-91). Sync then merges only data and
#   binaryData (config maps) or data and type (secrets), never immutable.
# - A secret's type is synced only when the two types differ and neither is
#   kubernetes.io/service-account-token (secrets/to_host_syncer.go:138-146).
# - A service account on the host has no secrets, no image pull secrets and
#   automountServiceAccountToken false; Sync touches only its metadata.

# The toHost configuration: sync.toHost.configMaps.{enabled,all},
# sync.toHost.secrets.{enabled,all}, sync.toHost.serviceAccounts.enabled and
# sync.toHost.pods.useSecretsForSATokens.
type Opts is Data:
  Opts{config_maps: Bool, config_maps_all: Bool, secrets: Bool, secrets_all: Bool, service_accounts: Bool, sa_tokens: Bool}

# A namespaced name (types.NamespacedName).
type Ref is Data:
  Ref{namespace: String, name: String}

def Configs.cat(a: +List<Ref>, b: +List<Ref>) -> +List<Ref>:
  List.append(&2, Ref, a, b)

# Configuration.

# chart/values.yaml: config maps and secrets on, only the used ones; service
# accounts off; no secrets for service account tokens.
def Configs.defaults() -> Opts:
  Opts{True{}, False{}, True{}, False{}, False{}, False{}}

def Configs.when(on: Bool, x: String, rest: +List<String>) -> +List<String>:
  match on:
    case True{}:
      x <> rest
    case False{}:
      rest

# The toHost syncers of this module that the configuration registers
# (pkg/controllers/register.go).
def Configs.syncers(o: Opts) -> +List<String>:
  match o:
    case Opts{cm, cm_all, sec, sec_all, sa, tokens}:
      Configs.when(cm, "configmaps", Configs.when(sec, "secrets", Configs.when(sa, "serviceaccounts", [])))

def Configs.config_maps_all(o: Opts) -> Bool:
  match o:
    case Opts{cm, cm_all, sec, sec_all, sa, tokens}:
      cm_all

def Configs.secrets_all(o: Opts) -> Bool:
  match o:
    case Opts{cm, cm_all, sec, sec_all, sa, tokens}:
      sec_all

def Configs.sa_tokens(o: Opts) -> Bool:
  match o:
    case Opts{cm, cm_all, sec, sec_all, sa, tokens}:
      tokens

# Constants.

def Configs.cm_kind() -> String:
  "/v1, Kind=ConfigMap"

def Configs.secret_kind() -> String:
  "/v1, Kind=Secret"

def Configs.sa_kind() -> String:
  "/v1, Kind=ServiceAccount"

# constants.SyncResourceAnnotation.
def Configs.force_sync() -> String:
  "vcluster.loft.sh/force-sync"

def Configs.root_ca() -> String:
  "kube-root-ca.crt"

# corev1.SecretTypeServiceAccountToken.
def Configs.sa_token_type() -> String:
  "kubernetes.io/service-account-token"

# corev1.SecretTypeOpaque.
def Configs.opaque() -> String:
  "Opaque"

# secrets.TranslateAnnotations.
def Configs.ingress_annotations() -> +List<String>:
  ["nginx.ingress.kubernetes.io/auth-secret", "nginx.ingress.kubernetes.io/auth-tls-secret", "nginx.ingress.kubernetes.io/proxy-ssl-secret"]

# References.

def Configs.ref_namespace(r: String & String) -> String:
  (ns, name) = r
  ns

def Configs.ref_name(r: String & String) -> String:
  (ns, name) = r
  name

def Configs.str_at(+o: J.Json, path: List<&2, String>) -> String:
  S.Svc.str(J.Json.at(o, path))

def Configs.named.if(empty: Bool, ns: String, name: String, rest: +List<Ref>) -> +List<Ref>:
  match empty:
    case True{}:
      rest
    case False{}:
      Ref{ns, name} <> rest

# A reference by a name that must not be empty.
def Configs.named(+ns: String, +name: String, rest: +List<Ref>) -> +List<Ref>:
  Configs.named.if(String.is_empty(name), ns, name, rest)

def Configs.present.if(absent: Bool, ns: String, name: String, rest: +List<Ref>) -> +List<Ref>:
  match absent:
    case True{}:
      rest
    case False{}:
      Ref{ns, name} <> rest

# A reference by the name field k of the object j, when j is there (a Go
# pointer that is not nil), even with an empty name.
def Configs.present(+ns: String, +j: J.Json, +k: String, rest: +List<Ref>) -> +List<Ref>:
  Configs.present.if(J.Json.is_null(j), ns, S.Svc.str(J.Json.get(j, k)), rest)

# Each list walker below goes over the items of a JSON list in order.

def Configs.env(+ns: String, +ref: String, xs: List<&2, J.Json>) -> +List<Ref>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+e, r}:
      Configs.named(ns, Configs.str_at(e, ["valueFrom", ref, "name"]), Configs.env(ns, ref, r))

def Configs.env_from(+ns: String, +from: String, xs: List<&2, J.Json>) -> +List<Ref>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+f, r}:
      Configs.named(ns, Configs.str_at(f, [from, "name"]), Configs.env_from(ns, from, r))

# The env refs and the envFrom refs of a container: env[].valueFrom.<ref>.name
# and envFrom[].<from>.name, each when not empty.
def Configs.container(+ns: String, +ref: String, +from: String, +c: J.Json) -> +List<Ref>:
  Configs.cat(Configs.env(ns, ref, J.Json.items(J.Json.get(c, "env"))), Configs.env_from(ns, from, J.Json.items(J.Json.get(c, "envFrom"))))

def Configs.each_container(+ns: String, +ref: String, +from: String, xs: List<&2, J.Json>) -> +List<Ref>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, r}:
      Configs.cat(Configs.container(ns, ref, from, x), Configs.each_container(ns, ref, from, r))

# The container refs of containers, initContainers and ephemeralContainers.
def Configs.containers(+ns: String, +ref: String, +from: String, +spec: J.Json) -> +List<Ref>:
  Configs.cat(Configs.each_container(ns, ref, from, J.Json.items(J.Json.get(spec, "containers"))),
    Configs.cat(Configs.each_container(ns, ref, from, J.Json.items(J.Json.get(spec, "initContainers"))),
      Configs.each_container(ns, ref, from, J.Json.items(J.Json.get(spec, "ephemeralContainers")))))

# The <k>.<field> reference of each item, when there.
def Configs.each_present(+ns: String, +k: String, +field: String, xs: List<&2, J.Json>) -> +List<Ref>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, r}:
      Configs.present(ns, J.Json.get(x, k), field, Configs.each_present(ns, k, field, r))

# The config map of a volume and of its projected sources.
def Configs.cm_volume(+ns: String, +v: J.Json) -> +List<Ref>:
  Configs.present(ns, J.Json.get(v, "configMap"), "name", Configs.each_present(ns, "configMap", "name", J.Json.items(J.Json.at(v, ["projected", "sources"]))))

def Configs.cm_volumes(+ns: String, xs: List<&2, J.Json>) -> +List<Ref>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, r}:
      Configs.cat(Configs.cm_volume(ns, x), Configs.cm_volumes(ns, r))

# configMapsFromPod: the config maps a pod refers to, in vcluster's order
# (containers, init containers, ephemeral containers, volumes). The
# container half and the volume half are scanned in parallel.
def Configs.pod_config_maps(+pod: J.Json) -> +List<Ref>:
  +ns = S.Svc.namespace(pod)
  +spec = J.Json.get(pod, "spec")
  cs vs = Configs.containers(ns, "configMapKeyRef", "configMapRef", spec) Configs.cm_volumes(ns, J.Json.items(J.Json.get(spec, "volumes")))
  Configs.cat(cs, vs)

def Configs.sa_token.if(on: Bool, +c: S.Cfg, +ns: String, +pod: String, +s: J.Json) -> +List<Ref>:
  match on:
    case True{}:
      Configs.present.if(J.Json.is_null(J.Json.get(s, "serviceAccountToken")), S.Svc.host_namespace(c, ns), N.Names.host_name(pod ++ "-sa-token", ns, S.Svc.vc(c)), [])
    case False{}:
      []

# Projected sources: each secret, then (with useSecretsForSATokens) the
# token secret of the pod.
def Configs.secret_sources(+c: S.Cfg, +tokens: Bool, +ns: String, +pod: String, xs: List<&2, J.Json>) -> +List<Ref>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+s, r}:
      Configs.cat(Configs.present(ns, J.Json.get(s, "secret"), "name", []), Configs.cat(Configs.sa_token.if(tokens, c, ns, pod, s), Configs.secret_sources(c, tokens, ns, pod, r)))

# <kind>.<field>.name when <kind>.<field> is there.
def Configs.legacy(+ns: String, +v: J.Json, kind: String, field: String, rest: +List<Ref>) -> +List<Ref>:
  Configs.present(ns, J.Json.at(v, [kind, field]), "name", rest)

# The secrets of a volume (secretNamesFromVolumes): secret, projected
# sources, iscsi, rbd, flexVolume, cinder, cephfs, azureFile (a non-empty
# secretName), scaleIO, storageos and csi.nodePublishSecretRef.
def Configs.secret_volume(+c: S.Cfg, +tokens: Bool, +ns: String, +pod: String, +v: J.Json) -> +List<Ref>:
  Configs.cat(Configs.present(ns, J.Json.get(v, "secret"), "secretName", []), Configs.cat(
    Configs.secret_sources(c, tokens, ns, pod, J.Json.items(J.Json.at(v, ["projected", "sources"]))),
    Configs.legacy(ns, v, "iscsi", "secretRef", Configs.legacy(ns, v, "rbd", "secretRef", Configs.legacy(ns, v, "flexVolume", "secretRef",
         Configs.legacy(ns, v, "cinder", "secretRef", Configs.legacy(ns, v, "cephfs", "secretRef",
         Configs.named(ns, Configs.str_at(v, ["azureFile", "secretName"]),
         Configs.legacy(ns, v, "scaleIO", "secretRef", Configs.legacy(ns, v, "storageos", "secretRef",
         Configs.legacy(ns, v, "csi", "nodePublishSecretRef", [])))))))))))

def Configs.secret_volumes(+c: S.Cfg, +tokens: Bool, +ns: String, +pod: String, xs: List<&2, J.Json>) -> +List<Ref>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, r}:
      Configs.cat(Configs.secret_volume(c, tokens, ns, pod, x), Configs.secret_volumes(c, tokens, ns, pod, r))

# Every image pull secret, even with an empty name.
def Configs.pull_secrets(+ns: String, xs: List<&2, J.Json>) -> +List<Ref>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, r}:
      Ref{ns, S.Svc.str(J.Json.get(x, "name"))} <> Configs.pull_secrets(ns, r)

# secretNamesFromPod: the secrets a pod refers to, in vcluster's order
# (containers, init containers, ephemeral containers, image pull secrets,
# volumes). tokens is sync.toHost.pods.useSecretsForSATokens. The
# container half and the rest are scanned in parallel.
def Configs.pod_secrets(+c: S.Cfg, +tokens: Bool, +pod: J.Json) -> +List<Ref>:
  +ns = S.Svc.namespace(pod)
  +spec = J.Json.get(pod, "spec")
  cs ps = Configs.containers(ns, "secretKeyRef", "secretRef", spec) Configs.cat(Configs.pull_secrets(ns, J.Json.items(J.Json.get(spec, "imagePullSecrets"))),
    Configs.secret_volumes(c, tokens, ns, S.Svc.name(pod), J.Json.items(J.Json.get(spec, "volumes"))))
  Configs.cat(cs, ps)

def Configs.split_ref.two(+ns: String, x: String, rest: List<&2, String>) -> +List<Ref>:
  match rest:
    case Nil{}:
      [Ref{ns, x}]
    case Con{y, more}:
      match more:
        case Nil{}:
          [Ref{x, y}]
        case Con{z, zs}:
          []

# strings.Split(value, "/"): "secret" is in the ingress namespace,
# "namespace/secret" names its namespace, anything else names nothing.
def Configs.split_ref(+ns: String, parts: List<&2, String>) -> +List<Ref>:
  match parts:
    case Nil{}:
      []
    case Con{x, rest}:
      Configs.split_ref.two(ns, x, rest)

def Configs.ann_ref.if(hit: Bool, +ns: String, v: String) -> +List<Ref>:
  match hit:
    case True{}:
      Configs.split_ref(ns, String.split(v, '/'))
    case False{}:
      []

# TranslateIngressAnnotations: the secrets the nginx annotations name.
def Configs.ann_refs(+ns: String, m: +List<M.KV>) -> +List<Ref>:
  match m:
    case Nil{}:
      Nil{}
    case Con{M.KV{+k, v}, r}:
      Configs.cat(Configs.ann_ref.if(M.Meta.elem(k, Configs.ingress_annotations()), ns, v), Configs.ann_refs(ns, r))

def Configs.tls(+ns: String, xs: List<&2, J.Json>) -> +List<Ref>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+t, r}:
      Configs.named(ns, S.Svc.str(J.Json.get(t, "secretName")), Configs.tls(ns, r))

# secretNamesFromIngress: the secrets of the annotations, then each
# non-empty TLS secretName.
def Configs.ingress_secrets(+ing: J.Json) -> +List<Ref>:
  +ns = S.Svc.namespace(ing)
  Configs.cat(Configs.ann_refs(ns, S.Svc.annotations(ing)), Configs.tls(ns, J.Json.items(J.Json.at(ing, ["spec", "tls"]))))

def Configs.ref_eq(a: Ref, b: Ref) -> Bool:
  match a b:
    case Ref{n1, m1} Ref{n2, m2}:
      Bool.and(String.eq(n1, n2), String.eq(m1, m2))

# True when refs holds ns/name.
def Configs.refers(refs: +List<Ref>, +r: Ref) -> Bool:
  match refs:
    case Nil{}:
      False{}
    case Con{x, t}:
      Bool.or(Configs.ref_eq(x, r), Configs.refers(t, r))

# isConfigMapUsed / isSecretUsed: the force-sync annotation is "true", or
# all is set, or a reference names the object.
def Configs.used(all: Bool, refs: +List<Ref>, +v: J.Json) -> Bool:
  Bool.or(String.eq(S.Svc.annotation(Configs.force_sync(), v), "true"), Bool.or(all, Configs.refers(refs, Ref{S.Svc.namespace(v), S.Svc.name(v)})))

# Names.

# singleNamespace.HostName: (namespace, name), empty for an empty name.
def Configs.plain_ref(+c: S.Cfg, +ns: String, +name: String) -> String & String:
  S.Svc.plain_ref.if(String.is_empty(name), c, ns, name)

def Configs.root_ca_ref.if(hit: Bool, +c: S.Cfg, r: String & String) -> String & String:
  match hit:
    case True{}:
      (Configs.ref_namespace(r), N.Names.safe_concat(["vcluster", Configs.root_ca(), "x", S.Svc.vc(c)]))
    case False{}:
      r

# configMapsMapper.VirtualToHost: the plain host name, but a host name
# "kube-root-ca.crt" becomes vcluster-kube-root-ca.crt-x-<vc>.
def Configs.cm_host_ref(+c: S.Cfg, +ns: String, +name: String) -> String & String:
  Configs.root_ca_ref.if(String.eq(Configs.ref_name(Configs.plain_ref(c, ns, name)), Configs.root_ca()), c, Configs.plain_ref(c, ns, name))

# The host (namespace, name) of a virtual secret.
def Configs.secret_host_ref(+c: S.Cfg, +ns: String, +name: String) -> String & String:
  Configs.plain_ref(c, ns, name)

# The host (namespace, name) of a virtual service account.
def Configs.sa_host_ref(+c: S.Cfg, +ns: String, +name: String) -> String & String:
  Configs.plain_ref(c, ns, name)

# The virtual (namespace, name) of a host object: its name and namespace
# annotations.
def Configs.virtual_ref(+h: J.Json) -> String & String:
  S.Svc.virtual_ref.if(False{}, S.Svc.annotations(h))

def Configs.cm_virtual_ref.if(ignored: Bool, special: Bool, r: String & String) -> String & String:
  match ignored:
    case True{}:
      ("", "")
    case False{}:
      match special:
        case True{}:
          (Configs.ref_namespace(r), Configs.root_ca())
        case False{}:
          r

# configMapsMapper.HostToVirtual: the host kube-root-ca.crt maps to nothing;
# vcluster-kube-root-ca.crt-x-<vc> maps to kube-root-ca.crt.
def Configs.cm_virtual_ref(+c: S.Cfg, +h: J.Json) -> String & String:
  +name = S.Svc.name(h)
  Configs.cm_virtual_ref.if(String.eq(name, Configs.root_ca()), String.eq(name, N.Names.safe_concat(["vcluster", Configs.root_ca(), "x", S.Svc.vc(c)])), Configs.virtual_ref(h))

# Steps shared by the three syncers.

def Configs.to_host.if(delete: Bool, +h: J.Json, +v: J.Json) -> S.Outcome:
  match delete:
    case True{}:
      S.Svc.done([S.Svc.delete_virtual(v)])
    case False{}:
      S.Svc.done([S.HostCreate{h}])

# SyncToHost once the object is to be synced: when the host object was
# there (host_old) or the virtual one is deleting, the virtual one goes;
# else h, the host object, is created.
def Configs.to_host(host_old: Maybe<&2, J.Json>, +h: J.Json, +v: J.Json) -> S.Outcome:
  Configs.to_host.if(Bool.or(Maybe.is_some(&2, J.Json, host_old), Bool.not(J.Json.is_null(J.Json.at(v, ["metadata", "deletionTimestamp"])))), h, v)

def Configs.gate(on: Bool, o: S.Outcome) -> S.Outcome:
  match on:
    case True{}:
      o
    case False{}:
      S.Svc.done([])

def Configs.to_virtual.if(delete: Bool, +h: J.Json, o: S.Outcome) -> S.Outcome:
  match delete:
    case True{}:
      S.Svc.done([S.Svc.delete_host(h)])
    case False{}:
      o

# SyncToVirtual: a host object whose virtual one was seen (virtual_old) or
# that vcluster made (ShouldDeleteHostObject) is deleted; else o.
def Configs.to_virtual(+kind: String, virtual_old: Maybe<&2, J.Json>, +h: J.Json, o: S.Outcome) -> S.Outcome:
  Configs.to_virtual.if(Bool.or(Maybe.is_some(&2, J.Json, virtual_old), M.Meta.should_delete_host_object(S.Svc.obj(kind, h))), h, o)

def Configs.used_or_delete(used: Bool, +h: J.Json, o: S.Outcome) -> S.Outcome:
  match used:
    case True{}:
      o
    case False{}:
      S.Svc.done([S.Svc.delete_host(h)])

# True when the map value a is v.
def Configs.is_value(a: Maybe<&2, String>, +v: String) -> Bool:
  match a:
    case None{}:
      False{}
    case Some{x}:
      String.eq(x, v)

def Configs.patch_put.if(same: Bool, k: String, v: String, out: +List<M.KV>) -> +List<M.KV>:
  match same:
    case True{}:
      out
    case False{}:
      M.Meta.insert(k, v, out)

# patcher.MergeChangesInto for string maps: the JSON merge patch from old to
# new applied to out. A key whose value new adds or changes is set, a key
# new drops is deleted; a nil out takes new as it is.
def Configs.patch_put(+old: +List<M.KV>, n: +List<M.KV>, out: +List<M.KV>) -> +List<M.KV>:
  match n:
    case Nil{}:
      out
    case Con{M.KV{+k, +v}, r}:
      Configs.patch_put(old, r, Configs.patch_put.if(Configs.is_value(M.Meta.get(k, old), v), k, v, out))

def Configs.patch_del.if(gone: Bool, k: String, out: +List<M.KV>) -> +List<M.KV>:
  match gone:
    case True{}:
      M.Meta.delete(k, out)
    case False{}:
      out

def Configs.patch_del(old: +List<M.KV>, +n: +List<M.KV>, out: +List<M.KV>) -> +List<M.KV>:
  match old:
    case Nil{}:
      out
    case Con{M.KV{+k, v}, r}:
      Configs.patch_del(r, n, Configs.patch_del.if(Bool.not(M.Meta.has(k, n)), k, out))

def Configs.merge_into.if(nil: Bool, +old: J.Json, +n: J.Json, +out: J.Json) -> J.Json:
  match nil:
    case True{}:
      n
    case False{}:
      S.Svc.render(Configs.patch_put(S.Svc.map(old), S.Svc.map(n), Configs.patch_del(S.Svc.map(old), S.Svc.map(n), S.Svc.map(out))))

def Configs.merge_into(+old: J.Json, +n: J.Json, +out: J.Json) -> J.Json:
  Configs.merge_into.if(J.Json.is_null(out), old, n, out)

def Configs.merge.if(vchanged: Bool, hchanged: Bool, +vo: J.Json, +v: J.Json, +ho: J.Json, +h: J.Json) -> J.Json & J.Json:
  match vchanged:
    case True{}:
      (v, Configs.merge_into(vo, v, h))
    case False{}:
      match hchanged:
        case True{}:
          (Configs.merge_into(ho, h, v), h)
        case False{}:
          (v, h)

# patcher.MergeBidirectional of a string map field: (new virtual, new host).
# A virtual change is merged into the host; else a host change into the
# virtual.
def Configs.merge(+vo: J.Json, +v: J.Json, +ho: J.Json, +h: J.Json) -> J.Json & J.Json:
  Configs.merge.if(Bool.not(S.Svc.eq(vo, v)), Bool.not(S.Svc.eq(ho, h)), vo, v, ho, h)

# merge for the field k of the four objects.
def Configs.merge_field(+k: String, +vo: J.Json, +v: J.Json, +ho: J.Json, +h: J.Json) -> J.Json & J.Json:
  Configs.merge(J.Json.get(vo, k), J.Json.get(v, k), J.Json.get(ho, k), J.Json.get(h, k))

# The metadata translate.HostMetadata gives the host copy of v, with the
# host (namespace, name) r.
def Configs.host_meta(+c: S.Cfg, +kind: String, +v: J.Json, r: String & String) -> J.Json:
  J.Json.get(S.Svc.host_metadata.ref(c, kind, [], v, r), "metadata")

# translate.HostMetadata: v with only its metadata replaced, so every other
# field (data, binaryData, stringData, immutable, type) is copied as it is.
def Configs.host_copy(+c: S.Cfg, +kind: String, +v: J.Json, r: String & String) -> J.Json:
  J.Json.set(v, "metadata", Configs.host_meta(c, kind, v, r))

# Config maps.

# configmaps translate (vObj -> host config map): HostMetadata with the
# config map name mapping; data and binaryData stay as they are.
def Configs.cm_to_host(+c: S.Cfg, +v: J.Json) -> J.Json:
  Configs.host_copy(c, Configs.cm_kind(), v, Configs.cm_host_ref(c, S.Svc.namespace(v), S.Svc.name(v)))

# configmaps SyncToHost: nothing unless the config map is used.
def Configs.cm_sync_to_host(+c: S.Cfg, all: Bool, refs: +List<Ref>, host_old: Maybe<&2, J.Json>, +v: J.Json) -> S.Outcome:
  Configs.gate(Configs.used(all, refs, v), Configs.to_host(host_old, Configs.cm_to_host(c, v), v))

# configmaps SyncToVirtual: the host config map goes when its virtual one
# went; else the virtual copy is created when it is used. As in vcluster's
# generic syncer, the caller skips a host object whose virtual name
# (Configs.cm_virtual_ref) is empty, such as the host kube-root-ca.crt.
def Configs.cm_sync_to_virtual(+c: S.Cfg, all: Bool, refs: +List<Ref>, virtual_old: Maybe<&2, J.Json>, +h: J.Json) -> S.Outcome:
  +nv = S.Svc.virtual_metadata.ref(c, Configs.cm_kind(), [], h, Configs.cm_virtual_ref(c, h))
  Configs.to_virtual(Configs.cm_kind(), virtual_old, h, Configs.gate(Configs.used(all, refs, nv), S.Svc.done([S.VirtualCreate{nv}])))

def Configs.cm_sync.fin(+c: S.Cfg, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json, d: J.Json & J.Json, b: J.Json & J.Json) -> S.Outcome:
  (dv, dh) = d
  (bv, bh) = b
  S.Svc.meta_sync(c, Configs.cm_kind(), [], [], ho, h, vo, v, S.Svc.put(S.Svc.put(h, "data", dh), "binaryData", bh), S.Svc.put(S.Svc.put(v, "data", dv), "binaryData", bv))

# configmaps Sync: an unused config map loses its host copy; else
# annotations and labels both ways, and data and binaryData merged both ways
# (the two fields in parallel).
def Configs.cm_sync.used(+c: S.Cfg, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> S.Outcome:
  d b = Configs.merge_field("data", vo, v, ho, h) Configs.merge_field("binaryData", vo, v, ho, h)
  Configs.cm_sync.fin(c, ho, h, vo, v, d, b)

def Configs.cm_sync(+c: S.Cfg, all: Bool, refs: +List<Ref>, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> S.Outcome:
  Configs.used_or_delete(Configs.used(all, refs, v), h, Configs.cm_sync.used(c, ho, h, vo, v))

# Secrets.

def Configs.opaque.if(token: Bool, o: J.Json) -> J.Json:
  match token:
    case True{}:
      J.Json.set(o, "type", J.JStr{Configs.opaque()})
    case False{}:
      o

# secrets translate (vObj -> host secret): HostMetadata; a service account
# token secret becomes Opaque.
def Configs.secret_to_host(+c: S.Cfg, +v: J.Json) -> J.Json:
  Configs.opaque.if(String.eq(Configs.str_at(v, ["type"]), Configs.sa_token_type()), Configs.host_copy(c, Configs.secret_kind(), v, Configs.secret_host_ref(c, S.Svc.namespace(v), S.Svc.name(v))))

# secrets SyncToHost: nothing unless the secret is used.
def Configs.secret_sync_to_host(+c: S.Cfg, all: Bool, refs: +List<Ref>, host_old: Maybe<&2, J.Json>, +v: J.Json) -> S.Outcome:
  Configs.gate(Configs.used(all, refs, v), Configs.to_host(host_old, Configs.secret_to_host(c, v), v))

# secrets SyncToVirtual, as for config maps.
def Configs.secret_sync_to_virtual(+c: S.Cfg, all: Bool, refs: +List<Ref>, virtual_old: Maybe<&2, J.Json>, +h: J.Json) -> S.Outcome:
  +nv = S.Svc.virtual_metadata.ref(c, Configs.secret_kind(), [], h, Configs.virtual_ref(h))
  Configs.to_virtual(Configs.secret_kind(), virtual_old, h, Configs.gate(Configs.used(all, refs, nv), S.Svc.done([S.VirtualCreate{nv}])))

def Configs.type_pick.if(vchanged: Bool, hchanged: Bool, +v: String, +h: String) -> String & String:
  match vchanged:
    case True{}:
      (v, v)
    case False{}:
      match hchanged:
        case True{}:
          (h, h)
        case False{}:
          (v, h)

def Configs.type_sync.if(go: Bool, +vo: String, +v: String, +ho: String, +h: String) -> String & String:
  match go:
    case True{}:
      Configs.type_pick.if(Bool.not(String.eq(vo, v)), Bool.not(String.eq(ho, h)), v, h)
    case False{}:
      (v, h)

# The secret type step: when the types differ and neither is the service
# account token type, patcher.CopyBidirectional.
def Configs.type_sync(+vo: String, +v: String, +ho: String, +h: String) -> String & String:
  +sa = Configs.sa_token_type()
  Configs.type_sync.if(Bool.and(Bool.not(String.eq(v, h)), Bool.and(Bool.not(String.eq(v, sa)), Bool.not(String.eq(h, sa)))), vo, v, ho, h)

def Configs.type_json(t: String & String) -> J.Json & J.Json:
  (v, h) = t
  (S.Svc.sj(v), S.Svc.sj(h))

def Configs.secret_sync.fin(+c: S.Cfg, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json, d: J.Json & J.Json, t: J.Json & J.Json) -> S.Outcome:
  (dv, dh) = d
  (tv, th) = t
  S.Svc.meta_sync(c, Configs.secret_kind(), [], [], ho, h, vo, v, S.Svc.put(S.Svc.put(h, "data", dh), "type", th), S.Svc.put(S.Svc.put(v, "data", dv), "type", tv))

def Configs.secret_sync.used(+c: S.Cfg, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> S.Outcome:
  d t = Configs.merge_field("data", vo, v, ho, h) Configs.type_json(Configs.type_sync(Configs.str_at(vo, ["type"]), Configs.str_at(v, ["type"]), Configs.str_at(ho, ["type"]), Configs.str_at(h, ["type"])))
  Configs.secret_sync.fin(c, ho, h, vo, v, d, t)

# secrets Sync: an unused secret loses its host copy; else data merged both
# ways, the type step, and annotations and labels both ways (data and type
# in parallel).
def Configs.secret_sync(+c: S.Cfg, all: Bool, refs: +List<Ref>, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> S.Outcome:
  Configs.used_or_delete(Configs.used(all, refs, v), h, Configs.secret_sync.used(c, ho, h, vo, v))

# Service accounts (sync.toHost.serviceAccounts.enabled, off by default).

# serviceaccounts SyncToHost translation: HostMetadata, no secrets, no
# image pull secrets, automountServiceAccountToken false.
def Configs.sa_to_host(+c: S.Cfg, +v: J.Json) -> J.Json:
  o = Configs.host_copy(c, Configs.sa_kind(), v, Configs.sa_host_ref(c, S.Svc.namespace(v), S.Svc.name(v)))
  J.Json.set(S.Svc.del_all(["secrets", "imagePullSecrets"], o), "automountServiceAccountToken", J.JBool{False{}})

# serviceaccounts SyncToHost.
def Configs.sa_sync_to_host(+c: S.Cfg, host_old: Maybe<&2, J.Json>, +v: J.Json) -> S.Outcome:
  Configs.to_host(host_old, Configs.sa_to_host(c, v), v)

# serviceaccounts SyncToVirtual: delete as for config maps, else create the
# virtual copy.
def Configs.sa_sync_to_virtual(+c: S.Cfg, virtual_old: Maybe<&2, J.Json>, +h: J.Json) -> S.Outcome:
  Configs.to_virtual(Configs.sa_kind(), virtual_old, h, S.Svc.done([S.VirtualCreate{S.Svc.virtual_metadata.ref(c, Configs.sa_kind(), [], h, Configs.virtual_ref(h))}]))

# serviceaccounts Sync: annotations and labels both ways.
def Configs.sa_sync(+c: S.Cfg, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> S.Outcome:
  S.Svc.meta_sync(c, Configs.sa_kind(), [], [], ho, h, vo, v, h, v)
