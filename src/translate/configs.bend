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

def Configs.defaults() -> Opts:
  ?TODO

def Configs.syncers(o: Opts) -> +List<String>:
  ?TODO

def Configs.ref_name(r: String & String) -> String:
  ?TODO

def Configs.pod_config_maps(+pod: J.Json) -> +List<Ref>:
  ?TODO

def Configs.pod_secrets(+c: S.Cfg, +tokens: Bool, +pod: J.Json) -> +List<Ref>:
  ?TODO

def Configs.ingress_secrets(+ing: J.Json) -> +List<Ref>:
  ?TODO

def Configs.used(all: Bool, refs: +List<Ref>, +v: J.Json) -> Bool:
  ?TODO

def Configs.cm_host_ref(+c: S.Cfg, +ns: String, +name: String) -> String & String:
  ?TODO

def Configs.secret_host_ref(+c: S.Cfg, +ns: String, +name: String) -> String & String:
  ?TODO

def Configs.sa_host_ref(+c: S.Cfg, +ns: String, +name: String) -> String & String:
  ?TODO

def Configs.cm_virtual_ref(+c: S.Cfg, +h: J.Json) -> String & String:
  ?TODO

def Configs.cm_to_host(+c: S.Cfg, +v: J.Json) -> J.Json:
  ?TODO

def Configs.cm_sync_to_host(+c: S.Cfg, all: Bool, refs: +List<Ref>, host_old: Maybe<&2, J.Json>, +v: J.Json) -> S.Outcome:
  ?TODO

def Configs.cm_sync_to_virtual(+c: S.Cfg, all: Bool, refs: +List<Ref>, virtual_old: Maybe<&2, J.Json>, +h: J.Json) -> S.Outcome:
  ?TODO

def Configs.cm_sync(+c: S.Cfg, all: Bool, refs: +List<Ref>, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> S.Outcome:
  ?TODO

def Configs.secret_to_host(+c: S.Cfg, +v: J.Json) -> J.Json:
  ?TODO

def Configs.secret_sync_to_host(+c: S.Cfg, all: Bool, refs: +List<Ref>, host_old: Maybe<&2, J.Json>, +v: J.Json) -> S.Outcome:
  ?TODO

def Configs.secret_sync_to_virtual(+c: S.Cfg, all: Bool, refs: +List<Ref>, virtual_old: Maybe<&2, J.Json>, +h: J.Json) -> S.Outcome:
  ?TODO

def Configs.secret_sync(+c: S.Cfg, all: Bool, refs: +List<Ref>, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> S.Outcome:
  ?TODO

def Configs.sa_to_host(+c: S.Cfg, +v: J.Json) -> J.Json:
  ?TODO

def Configs.sa_sync_to_host(+c: S.Cfg, host_old: Maybe<&2, J.Json>, +v: J.Json) -> S.Outcome:
  ?TODO

def Configs.sa_sync_to_virtual(+c: S.Cfg, virtual_old: Maybe<&2, J.Json>, +h: J.Json) -> S.Outcome:
  ?TODO

def Configs.sa_sync(+c: S.Cfg, +ho: J.Json, +h: J.Json, +vo: J.Json, +v: J.Json) -> S.Outcome:
  ?TODO
