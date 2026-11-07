import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/translate/names.bend as N
import ../src/translate/services.bend as S
import ../src/translate/configs.bend as C

# Spec for src/translate/configs.bend (vcluster
# pkg/controllers/resources/configmaps, secrets and serviceaccounts toHost,
# and the reference scans of pkg/mappings/resources/configmaps.go and
# secrets.go).
#
# The concrete laws transcribe every case of configmaps/to_host_syncer_test.go,
# secrets/to_host_syncer_test.go, serviceaccounts/syncer_test.go,
# mappings/resources/configmaps_test.go and secrets_test.go (vcluster
# a8ab30e), and the toHost defaults of chart/values.yaml. vcluster's tests
# run with VClusterName "suffix" and target namespace "test".
#
# A config map or secret syncs only when it is used: the force-sync
# annotation, sync.toHost.<kind>.all, or a reference from a virtual pod. The
# syncer tests get the reference from the pod basePod through the mapping
# store; here the references are the scan of that pod (C.Configs.pod_config_maps,
# C.Configs.pod_secrets), passed to the sync step.
#
# Objects are compared in canonical form (S.Svc.canon_outcome), as in
# laws/services.bend. The test harness strips the vcluster.loft.sh/managed-by
# label before it compares (pkg/syncer/testing/testing.go:228-231); the
# laws keep it on created host objects, as HostLabelsMap writes it.

# Test fixtures.

def Laws.configs.cfg() -> S.Cfg:
  S.Cfg{"suffix", "test", "vcluster"}

def Laws.configs.str(k: String, v: String) -> J.KV:
  J.KV{k, J.JStr{v}}

def Laws.configs.obj(k: String, fs: List<&2, J.KV>) -> J.KV:
  J.KV{k, J.Json.obj(fs)}

def Laws.configs.arr(k: String, xs: List<&2, J.Json>) -> J.KV:
  J.KV{k, J.Json.arr(xs)}

# metav1.ObjectMeta{Name, Namespace, Labels, Annotations}.
def Laws.configs.meta(name: String, ns: String, labels: List<&2, J.KV>, annotations: List<&2, J.KV>) -> J.KV:
  Laws.configs.obj("metadata", [Laws.configs.str("name", name), Laws.configs.str("namespace", ns), Laws.configs.obj("labels", labels), Laws.configs.obj("annotations", annotations)])

# The bookkeeping annotations of a host object in target namespace "test".
def Laws.configs.ann(name: String, ns: String, kind: String, host: String) -> List<&2, J.KV>:
  [Laws.configs.str("vcluster.loft.sh/object-name", name),
   Laws.configs.str("vcluster.loft.sh/object-namespace", ns),
   Laws.configs.str("vcluster.loft.sh/object-uid", ""),
   Laws.configs.str("vcluster.loft.sh/object-kind", kind),
   Laws.configs.str("vcluster.loft.sh/object-host-namespace", "test"),
   Laws.configs.str("vcluster.loft.sh/object-host-name", host)]

def Laws.configs.out(ws: List<&2, S.Write>) -> S.Outcome:
  S.Svc.canon_outcome(S.Outcome{ws, S.NoRequeue{}})

def Laws.configs.ns_label() -> J.KV:
  Laws.configs.str("vcluster.loft.sh/namespace", "test")

def Laws.configs.marker() -> J.KV:
  Laws.configs.str("vcluster.loft.sh/managed-by", "suffix")

# chart/values.yaml.

# sync.toHost.configMaps {enabled: true, all: false} (values.yaml:22-25),
# sync.toHost.secrets {enabled: true, all: false} (27-30),
# sync.toHost.serviceAccounts.enabled false (131-133) and
# sync.toHost.pods.useSecretsForSATokens false (48).
law configs.defaults:
  {C.Configs.defaults() == C.Opts{True{}, False{}, True{}, False{}, False{}, False{}} : C.Opts}

# configmaps/to_host_syncer_test.go fixtures.

def Laws.configs.cm_kind() -> String:
  "/v1, Kind=ConfigMap"

def Laws.configs.cm_host() -> String:
  "test-configmap-x-test-x-suffix"

# baseConfigMap
def Laws.configs.base_cm() -> J.Json:
  J.Json.obj([Laws.configs.meta("test-configmap", "test", [], [])])

# updatedConfigMap
def Laws.configs.updated_cm() -> J.Json:
  J.Json.obj([Laws.configs.meta("test-configmap", "test", [], []), Laws.configs.obj("data", [Laws.configs.str("test", "test")])])

def Laws.configs.cm_meta(labels: List<&2, J.KV>) -> J.KV:
  Laws.configs.meta(Laws.configs.cm_host(), "test", labels,
    Laws.configs.ann("test-configmap", "test", Laws.configs.cm_kind(), Laws.configs.cm_host()))

# syncedConfigMap
def Laws.configs.synced_cm() -> J.Json:
  J.Json.obj([Laws.configs.cm_meta([Laws.configs.ns_label()])])

# syncedConfigMap as the create makes it (with the marker label).
def Laws.configs.created_cm() -> J.Json:
  J.Json.obj([Laws.configs.cm_meta([Laws.configs.ns_label(), Laws.configs.marker()])])

# updatedSyncedConfigMap
def Laws.configs.updated_synced_cm() -> J.Json:
  J.Json.obj([Laws.configs.cm_meta([Laws.configs.ns_label()]), Laws.configs.obj("data", [Laws.configs.str("test", "test")])])

# basePod: a volume {name: test, configMap: {name: test-configmap}}.
def Laws.configs.cm_pod() -> J.Json:
  J.Json.obj([Laws.configs.meta("test", "test", [], []),
    Laws.configs.obj("spec", [Laws.configs.arr("volumes", [J.Json.obj([Laws.configs.str("name", "test"),
      Laws.configs.obj("configMap", [Laws.configs.str("name", "test-configmap")])])])])])

def Laws.configs.cm_refs() -> List<&2, C.Ref>:
  C.Configs.pod_config_maps(Laws.configs.cm_pod())

# configmaps/to_host_syncer_test.go TestSync.

# "Unused config map": SyncToHost(baseConfigMap) with no pod writes nothing.
law configs.cm_unused:
  {S.Svc.canon_outcome(C.Configs.cm_sync_to_host(Laws.configs.cfg(), False{}, [], None{}, Laws.configs.base_cm()))
    == Laws.configs.out([]) : S.Outcome}

# "Used config map": SyncToHost(baseConfigMap) with basePod creates
# syncedConfigMap.
law configs.cm_used:
  {S.Svc.canon_outcome(C.Configs.cm_sync_to_host(Laws.configs.cfg(), False{}, Laws.configs.cm_refs(), None{}, Laws.configs.base_cm()))
    == Laws.configs.out([S.HostCreate{Laws.configs.created_cm()}]) : S.Outcome}

# "Update used config map":
# Sync(NewSyncEventWithOld(syncedConfigMap, syncedConfigMap, baseConfigMap, updatedConfigMap)).
law configs.cm_update_used:
  {S.Svc.canon_outcome(C.Configs.cm_sync(Laws.configs.cfg(), False{}, Laws.configs.cm_refs(), Laws.configs.synced_cm(), Laws.configs.synced_cm(), Laws.configs.base_cm(), Laws.configs.updated_cm()))
    == Laws.configs.out([S.HostUpdate{Laws.configs.updated_synced_cm()}]) : S.Outcome}

# "Remove unused config map":
# Sync(NewSyncEventWithOld(syncedConfigMap, syncedConfigMap, updatedConfigMap, updatedConfigMap))
# with no pod deletes the host config map.
law configs.cm_remove_unused:
  {S.Svc.canon_outcome(C.Configs.cm_sync(Laws.configs.cfg(), False{}, [], Laws.configs.synced_cm(), Laws.configs.synced_cm(), Laws.configs.updated_cm(), Laws.configs.updated_cm()))
    == Laws.configs.out([S.HostDelete{"test", Laws.configs.cm_host()}]) : S.Outcome}

# secrets/to_host_syncer_test.go fixtures.

def Laws.configs.secret_kind() -> String:
  "/v1, Kind=Secret"

def Laws.configs.secret_host() -> String:
  "test-secret-x-test-x-suffix"

def Laws.configs.test_label() -> J.KV:
  Laws.configs.str("test-label", "label-value")

# Data {"test": []byte("test")}: base64 "dGVzdA==" in JSON.
def Laws.configs.secret_data() -> J.KV:
  Laws.configs.obj("data", [Laws.configs.str("test", "dGVzdA==")])

# baseSecret
def Laws.configs.base_secret() -> J.Json:
  J.Json.obj([Laws.configs.meta("test-secret", "test", [Laws.configs.test_label()], [])])

# updatedSecret
def Laws.configs.updated_secret() -> J.Json:
  J.Json.obj([Laws.configs.meta("test-secret", "test", [Laws.configs.test_label()], []), Laws.configs.secret_data()])

def Laws.configs.secret_meta(labels: List<&2, J.KV>) -> J.KV:
  Laws.configs.meta(Laws.configs.secret_host(), "test", labels,
    Laws.configs.ann("test-secret", "test", Laws.configs.secret_kind(), Laws.configs.secret_host()))

# syncedSecret
def Laws.configs.synced_secret() -> J.Json:
  J.Json.obj([Laws.configs.secret_meta([Laws.configs.ns_label(), Laws.configs.test_label()])])

# syncedSecret as the create makes it (with the marker label).
def Laws.configs.created_secret() -> J.Json:
  J.Json.obj([Laws.configs.secret_meta([Laws.configs.ns_label(), Laws.configs.test_label(), Laws.configs.marker()])])

# updatedSyncedSecret
def Laws.configs.updated_synced_secret() -> J.Json:
  J.Json.obj([Laws.configs.secret_meta([Laws.configs.ns_label(), Laws.configs.test_label()]), Laws.configs.secret_data()])

# basePod: a volume {name: test, secret: {secretName: test-secret}}.
def Laws.configs.secret_pod() -> J.Json:
  J.Json.obj([Laws.configs.meta("test", "test", [], []),
    Laws.configs.obj("spec", [Laws.configs.arr("volumes", [J.Json.obj([Laws.configs.str("name", "test"),
      Laws.configs.obj("secret", [Laws.configs.str("secretName", "test-secret")])])])])])

def Laws.configs.secret_refs() -> List<&2, C.Ref>:
  C.Configs.pod_secrets(Laws.configs.cfg(), False{}, Laws.configs.secret_pod())

# secrets/to_host_syncer_test.go TestSync.

# "Unused secret": SyncToHost(baseSecret) with no pod writes nothing.
law configs.secret_unused:
  {S.Svc.canon_outcome(C.Configs.secret_sync_to_host(Laws.configs.cfg(), False{}, [], None{}, Laws.configs.base_secret()))
    == Laws.configs.out([]) : S.Outcome}

# "Used secret": SyncToHost(baseSecret) with basePod creates syncedSecret.
law configs.secret_used:
  {S.Svc.canon_outcome(C.Configs.secret_sync_to_host(Laws.configs.cfg(), False{}, Laws.configs.secret_refs(), None{}, Laws.configs.base_secret()))
    == Laws.configs.out([S.HostCreate{Laws.configs.created_secret()}]) : S.Outcome}

# "Update used secret":
# Sync(NewSyncEventWithOld(syncedSecret, syncedSecret, baseSecret, updatedSecret)).
law configs.secret_update_used:
  {S.Svc.canon_outcome(C.Configs.secret_sync(Laws.configs.cfg(), False{}, Laws.configs.secret_refs(), Laws.configs.synced_secret(), Laws.configs.synced_secret(), Laws.configs.base_secret(), Laws.configs.updated_secret()))
    == Laws.configs.out([S.HostUpdate{Laws.configs.updated_synced_secret()}]) : S.Outcome}

# "Remove unused secret": Sync(NewSyncEvent(syncedSecret, updatedSecret))
# with no pod deletes the host secret.
law configs.secret_remove_unused:
  {S.Svc.canon_outcome(C.Configs.secret_sync(Laws.configs.cfg(), False{}, [], Laws.configs.synced_secret(), Laws.configs.synced_secret(), Laws.configs.updated_secret(), Laws.configs.updated_secret()))
    == Laws.configs.out([S.HostDelete{"test", Laws.configs.secret_host()}]) : S.Outcome}

# serviceaccounts/syncer_test.go fixtures.

def Laws.configs.sa_host() -> String:
  "test-serviceaccount-x-test-x-suffix"

# vSA
def Laws.configs.v_sa() -> J.Json:
  J.Json.obj([Laws.configs.meta("test-serviceaccount", "test", [], [Laws.configs.str("test", "test")]),
    Laws.configs.arr("secrets", [J.Json.obj([Laws.configs.str("kind", "Test")])]),
    Laws.configs.arr("imagePullSecrets", [J.Json.obj([Laws.configs.str("name", "test")])])])

# pSA (with the marker label).
def Laws.configs.p_sa() -> J.Json:
  J.Json.obj([Laws.configs.meta(Laws.configs.sa_host(), "test", [Laws.configs.ns_label(), Laws.configs.marker()],
      List.append(&2, J.KV, [Laws.configs.str("test", "test"), Laws.configs.str("vcluster.loft.sh/managed-annotations", "test")],
        Laws.configs.ann("test-serviceaccount", "test", "/v1, Kind=ServiceAccount", Laws.configs.sa_host()))),
    J.KV{"automountServiceAccountToken", J.JBool{False{}}}])

# serviceaccounts/syncer_test.go TestSync "ServiceAccount sync":
# SyncToHost(vSA) creates pSA.
law configs.sa_sync:
  {S.Svc.canon_outcome(C.Configs.sa_sync_to_host(Laws.configs.cfg(), None{}, Laws.configs.v_sa()))
    == Laws.configs.out([S.HostCreate{Laws.configs.p_sa()}]) : S.Outcome}

# mappings/resources/configmaps_test.go TestConfigMapsMapping: a container
# env configMapKeyRef "a" and a configMap volume "b".
def Laws.configs.mapping_cm_pod() -> J.Json:
  J.Json.obj([Laws.configs.meta("test", "test", [], []),
    Laws.configs.obj("spec", [
      Laws.configs.arr("containers", [J.Json.obj([Laws.configs.str("name", "test"),
        Laws.configs.arr("env", [J.Json.obj([Laws.configs.str("name", "test"),
          Laws.configs.obj("valueFrom", [Laws.configs.obj("configMapKeyRef", [Laws.configs.str("name", "a")])])])])])]),
      Laws.configs.arr("volumes", [J.Json.obj([Laws.configs.str("name", "test"),
        Laws.configs.obj("configMap", [Laws.configs.str("name", "b")])])])])])

law configs.mapping_config_maps:
  {C.Configs.pod_config_maps(Laws.configs.mapping_cm_pod()) == [C.Ref{"test", "a"}, C.Ref{"test", "b"}] : List<&2, C.Ref>}

# mappings/resources/secrets_test.go TestSecretMappings: an ingress with TLS
# secrets "a" and "b" ...
def Laws.configs.mapping_ingress() -> J.Json:
  J.Json.obj([Laws.configs.meta("test", "test", [], []),
    Laws.configs.obj("spec", [Laws.configs.arr("tls", [J.Json.obj([Laws.configs.str("secretName", "a")]), J.Json.obj([Laws.configs.str("secretName", "b")])])])])

law configs.mapping_ingress_secrets:
  {C.Configs.ingress_secrets(Laws.configs.mapping_ingress()) == [C.Ref{"test", "a"}, C.Ref{"test", "b"}] : List<&2, C.Ref>}

# ... and a pod with a container env secretKeyRef "a" and a secret volume "b".
def Laws.configs.mapping_secret_pod() -> J.Json:
  J.Json.obj([Laws.configs.meta("test", "test", [], []),
    Laws.configs.obj("spec", [
      Laws.configs.arr("containers", [J.Json.obj([Laws.configs.str("name", "test"),
        Laws.configs.arr("env", [J.Json.obj([Laws.configs.str("name", "test"),
          Laws.configs.obj("valueFrom", [Laws.configs.obj("secretKeyRef", [Laws.configs.str("name", "a")])])])])])]),
      Laws.configs.arr("volumes", [J.Json.obj([Laws.configs.str("name", "test"),
        Laws.configs.obj("secret", [Laws.configs.str("secretName", "b")])])])])])

law configs.mapping_pod_secrets:
  {C.Configs.pod_secrets(Laws.configs.cfg(), False{}, Laws.configs.mapping_secret_pod()) == [C.Ref{"test", "a"}, C.Ref{"test", "b"}] : List<&2, C.Ref>}

# General laws.

# A host config map keeps the data and binaryData of the virtual one byte
# for byte ...
law configs.cm_keeps_data:
  for +c: S.Cfg
  for +v: J.Json
  {J.Json.get(C.Configs.cm_to_host(c, v), "data") == J.Json.get(v, "data") : J.Json}

law configs.cm_keeps_binary_data:
  for +c: S.Cfg
  for +v: J.Json
  {J.Json.get(C.Configs.cm_to_host(c, v), "binaryData") == J.Json.get(v, "binaryData") : J.Json}

# ... and so does a host secret.
law configs.secret_keeps_data:
  for +c: S.Cfg
  for +v: J.Json
  {J.Json.get(C.Configs.secret_to_host(c, v), "data") == J.Json.get(v, "data") : J.Json}

# The host name of a secret or a service account is Names.host_name of its
# virtual name ...
law configs.secret_host_name:
  for +c: S.Cfg
  for +ns: String
  for +name: String
  {C.Configs.ref_name(C.Configs.secret_host_ref(c, ns, name)) == N.Names.host_name(name, ns, S.Svc.vc(c)) : String}

law configs.sa_host_name:
  for +c: S.Cfg
  for +ns: String
  for +name: String
  {C.Configs.ref_name(C.Configs.sa_host_ref(c, ns, name)) == N.Names.host_name(name, ns, S.Svc.vc(c)) : String}

# ... and so is the host name of a config map, unless that name is
# kube-root-ca.crt (configmaps.go:35-40).
law configs.cm_host_name:
  for +c: S.Cfg
  for +ns: String
  for +name: String
  for h: {String.eq(N.Names.host_name(name, ns, S.Svc.vc(c)), "kube-root-ca.crt") == False{} : Bool}
  {C.Configs.ref_name(C.Configs.cm_host_ref(c, ns, name)) == N.Names.host_name(name, ns, S.Svc.vc(c)) : String}
