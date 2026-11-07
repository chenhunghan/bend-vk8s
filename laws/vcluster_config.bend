import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/config/vcluster.bend as V

# Proposed: config subset at upstream a8ab30ea. Expectations are from
# the upstream source and tests, not from the Bend implementation.

# chart/values.yaml: empty document overlays chart defaults
law vcluster_config.empty_defaults:
  {V.Config.parse("") == Done{J.Json.obj([J.KV{"controlPlane", J.Json.obj([J.KV{"distro", J.Json.obj([J.KV{"k8s", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}, J.KV{"version", J.JStr{""}}, J.KV{"apiServer", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}, J.KV{"extraArgs", J.Json.arr([])}])}, J.KV{"controllerManager", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}, J.KV{"extraArgs", J.Json.arr([])}])}, J.KV{"scheduler", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}, J.KV{"extraArgs", J.Json.arr([])}])}])}])}, J.KV{"backingStore", J.Json.obj([J.KV{"database", J.Json.obj([J.KV{"embedded", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}])}, J.KV{"etcd", J.Json.obj([J.KV{"embedded", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}])}])}, J.KV{"coredns", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}, J.KV{"deployment", J.Json.obj([J.KV{"replicas", J.JNum{"1"}}])}])}, J.KV{"standalone", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}, J.KV{"joinNode", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}])}])}])}, J.KV{"networking", J.Json.obj([J.KV{"serviceCIDR", J.JStr{""}}, J.KV{"podCIDR", J.JStr{"10.244.0.0/16"}}, J.KV{"advanced", J.Json.obj([J.KV{"clusterDomain", J.JStr{"cluster.local"}}])}])}, J.KV{"privateNodes", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"sync", J.Json.obj([J.KV{"toHost", J.Json.obj([J.KV{"services", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}])}, J.KV{"endpoints", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}])}, J.KV{"endpointSlices", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}])}, J.KV{"persistentVolumeClaims", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}])}, J.KV{"configMaps", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}])}, J.KV{"secrets", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}])}, J.KV{"pods", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}])}, J.KV{"ingresses", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"priorityClasses", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"networkPolicies", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"volumeSnapshots", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"volumeSnapshotContents", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"podDisruptionBudgets", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"serviceAccounts", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"storageClasses", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"persistentVolumes", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"namespaces", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"resourceClaims", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"resourceClaimTemplates", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"gatewayApi", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}, J.KV{"gateways", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"httpRoutes", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"tlsRoutes", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"backendTLSPolicies", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"referenceGrants", J.Json.obj([J.KV{"enabled", J.JStr{"auto"}}])}])}])}, J.KV{"fromHost", J.Json.obj([J.KV{"events", J.Json.obj([J.KV{"enabled", J.JBool{True{}}}])}, J.KV{"configMaps", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"csiDrivers", J.Json.obj([J.KV{"enabled", J.JStr{"auto"}}])}, J.KV{"csiNodes", J.Json.obj([J.KV{"enabled", J.JStr{"auto"}}])}, J.KV{"csiStorageCapacities", J.Json.obj([J.KV{"enabled", J.JStr{"auto"}}])}, J.KV{"storageClasses", J.Json.obj([J.KV{"enabled", J.JStr{"auto"}}])}, J.KV{"ingressClasses", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"gatewayClasses", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"gateways", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"runtimeClasses", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"priorityClasses", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"nodes", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"secrets", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"volumeSnapshotClasses", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}, J.KV{"deviceClasses", J.Json.obj([J.KV{"enabled", J.JBool{False{}}}])}])}])}])} : Result<&2, &2, String, J.Json>}

# config/config_test.go TestConfig_Diff/Simple (parsed input; serialization is outside this module)
law vcluster_config.diff_simple:
  {V.Config.value("sync:\n  toHost:\n    services:\n      enabled: false\n", ["sync", "toHost", "services", "enabled"]) == J.JBool{False{}} : J.Json}

# config/config_test.go TestConfig_UnmarshalYAMLStrict/Invalid: yaml
law vcluster_config.unknown_yaml:
  {V.Config.error("foo:\n  bar: baz\n") == "error unmarshaling JSON: while decoding JSON: json: unknown field \"foo\"" : String}

# config/config_test.go TestConfig_UnmarshalYAMLStrict/Invalid: json
law vcluster_config.unknown_json:
  {V.Config.error("{\"foo\":{\"bar\":\"baz\"}}") == "error unmarshaling JSON: while decoding JSON: json: unknown field \"foo\"" : String}

# config/config_test.go TestConfig_UnmarshalYAMLStrict/Invalid: Old values format
law vcluster_config.old_format:
  {V.Config.error("api:\n  image: registry.k8s.io/kube-apiserver:v1.29.0\ncontroller:\n  image: registry.k8s.io/kube-controller-manager:v1.29.0\netcd:\n  image: registry.k8s.io/etcd:3.5.10-0\nscheduler:\n  image: registry.k8s.io/kube-scheduler:v1.29.0\nservice:\n  type: NodePort\nserviceCIDR: 10.96.0.0/16\nsync:\n  nodes:\n    enabled: true\ntelemetry:\n  disabled: false\n") == "error unmarshaling JSON: while decoding JSON: json: unknown field \"api\"" : String}

# config/config_test.go TestConfig_UnmarshalYAMLStrict/Success: New values format
law vcluster_config.new_yaml:
  {V.Config.value("controlPlane:\n  distro:\n    k8s:\n      enabled: true\n", ["controlPlane", "distro", "k8s", "enabled"]) == J.JBool{True{}} : J.Json}

# config/config_test.go TestConfig_UnmarshalYAMLStrict/Success: New values format (json)
law vcluster_config.new_json:
  {V.Config.value("{\"controlPlane\":{\"distro\":{\"k8s\":{\"enabled\":true}}}}", ["controlPlane", "distro", "k8s", "enabled"]) == J.JBool{True{}} : J.Json}

# config/config.go K8S/apiServer.extraArgs
law vcluster_config.args_sequence:
  {V.Config.value("controlPlane:\n  distro:\n    k8s:\n      apiServer:\n        extraArgs:\n          - --v=3\n          - \"--audit-log-path=/data/a # b\" # comment\n", ["controlPlane", "distro", "k8s", "apiServer", "extraArgs"]) == J.Json.arr([J.JStr{"--v=3"}, J.JStr{"--audit-log-path=/data/a # b"}]) : J.Json}

# chart/values.yaml CoreDNS.Deployment.Replicas
law vcluster_config.coredns_replicas:
  {V.Config.value("controlPlane:\n  coredns:\n    enabled: false\n    deployment:\n      replicas: 3\n", ["controlPlane", "coredns", "deployment", "replicas"]) == J.JNum{"3"} : J.Json}

# config/config.go Networking
law vcluster_config.networking:
  {V.Config.value("networking:\n  serviceCIDR: 10.96.0.0/12\n  podCIDR: 10.2.0.0/16\n  advanced:\n    clusterDomain: example.test\n", ["networking", "advanced", "clusterDomain"]) == J.JStr{"example.test"} : J.Json}

# config/config.go Standalone; chart/values.yaml joinNode
law vcluster_config.standalone:
  {V.Config.value("controlPlane:\n  standalone:\n    enabled: true\n    joinNode:\n      enabled: false\n", ["controlPlane", "standalone", "joinNode", "enabled"]) == J.JBool{False{}} : J.Json}

# pkg/config/validation.go:130
law vcluster_config.storage_both:
  {V.Config.error("sync:\n  toHost:\n    storageClasses:\n      enabled: true\n  fromHost:\n    storageClasses:\n      enabled: true\n") == "you cannot enable both sync.fromHost.storageClasses.enabled and sync.toHost.storageClasses.enabled at the same time. Choose only one of them" : String}

# pkg/config/validation.go:134
law vcluster_config.priority_both:
  {V.Config.error("sync:\n  toHost:\n    priorityClasses:\n      enabled: true\n  fromHost:\n    priorityClasses:\n      enabled: true\n") == "cannot sync priorityclasses to and from host at the same time" : String}

# pkg/config/validation.go:139-145
law vcluster_config.volumeSnapshots_alone:
  {V.Config.error("sync:\n  toHost:\n    volumeSnapshots:\n      enabled: true\n") == "when syncing volume snapshots to the host, one must set sync.toHost.volumeSnapshotContents.enabled to true" : String}

# pkg/config/validation.go:139-145
law vcluster_config.volumeSnapshotContents_alone:
  {V.Config.error("sync:\n  toHost:\n    volumeSnapshotContents:\n      enabled: true\n") == "when syncing volume snapshots contents to the host, one must set sync.toHost.volumeSnapshots.enabled to true" : String}

# pkg/config/validation.go:125
law vcluster_config.scheduler_needs_nodes:
  {V.Config.error("controlPlane:\n  distro:\n    k8s:\n      scheduler:\n        enabled: true\n") == "sync.fromHost.nodes.enabled is false, but required if using hybrid scheduling or virtual scheduler" : String}

# pkg/config/validation.go validateFromHostSyncMappings: enabled, no mappings
law vcluster_config.configMaps_needs_mappings:
  {V.Config.error("sync:\n  fromHost:\n    configMaps:\n      enabled: true\n") == "config.sync.fromHost.configMaps.mappings are empty" : String}

# pkg/config/validation.go validateFromHostSyncMappings: enabled, no mappings
law vcluster_config.secrets_needs_mappings:
  {V.Config.error("sync:\n  fromHost:\n    secrets:\n      enabled: true\n") == "config.sync.fromHost.secrets.mappings are empty" : String}

# pkg/config/validation.go validateGatewayMappings
law vcluster_config.gateway_needs_mappings:
  {V.Config.error("sync:\n  fromHost:\n    gateways:\n      enabled: true\n") == "sync.fromHost.gateways.mappings.byName are empty" : String}

# pkg/config/validation_test.go TestValidateToHostNamespaceSyncMappings/Sync enabled, no mappings (public entry-point prefix)
law vcluster_config.namespace_no_mappings:
  {V.Config.error("sync:\n  toHost:\n    namespaces:\n      enabled: true\n") == "namespace sync: config.sync.toHost.namespaces.mappings.byName are empty" : String}

# pkg/config/validation_test.go TestValidateToHostNamespaceSyncMappings/Sync disabled
law vcluster_config.namespace_disabled:
  {V.Config.error("sync:\n  toHost:\n    namespaces:\n      enabled: false\n") == "" : String}

# pkg/config/validation.go validateGatewayAPIConfig
law vcluster_config.reference_grants_invalid:
  {V.Config.error("sync:\n  toHost:\n    gatewayApi:\n      referenceGrants:\n        enabled: invalid\n") == "sync.toHost.gatewayApi.referenceGrants.enabled must be one of: auto, true, false" : String}

# pkg/config/validation.go:64-77
law vcluster_config.auto_csi:
  {V.Config.value("controlPlane:\n  distro:\n    k8s:\n      scheduler:\n        enabled: true\nsync:\n  fromHost:\n    nodes:\n      enabled: true\n", ["sync", "fromHost", "csiNodes", "enabled"]) == J.JStr{"true"} : J.Json}

# config/config.go BackingStoreType
law vcluster_config.sqlite_default:
  {V.Config.backing_store(V.Config.value("", [])) == "sqlite" : String}

# config/config.go BackingStoreType
law vcluster_config.etcd:
  {V.Config.backing_store(V.Config.value("controlPlane:\n  backingStore:\n    etcd:\n      embedded:\n        enabled: true\n", [])) == "etcd" : String}

# config/config.go BackingStoreType
law vcluster_config.etcd_precedence:
  {V.Config.backing_store(V.Config.value("controlPlane:\n  backingStore:\n    database:\n      embedded:\n        enabled: true\n    etcd:\n      embedded:\n        enabled: true\n", [])) == "etcd" : String}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_controlPlane_distro_k8s_enabled:
  {V.Config.value("", ["controlPlane", "distro", "k8s", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_controlPlane_distro_k8s_version:
  {V.Config.value("", ["controlPlane", "distro", "k8s", "version"]) == J.JStr{""} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_controlPlane_distro_k8s_apiServer_enabled:
  {V.Config.value("", ["controlPlane", "distro", "k8s", "apiServer", "enabled"]) == J.JBool{True{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_controlPlane_distro_k8s_apiServer_extraArgs:
  {V.Config.value("", ["controlPlane", "distro", "k8s", "apiServer", "extraArgs"]) == J.Json.arr([]) : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_controlPlane_distro_k8s_controllerManager_enabled:
  {V.Config.value("", ["controlPlane", "distro", "k8s", "controllerManager", "enabled"]) == J.JBool{True{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_controlPlane_distro_k8s_controllerManager_extraArgs:
  {V.Config.value("", ["controlPlane", "distro", "k8s", "controllerManager", "extraArgs"]) == J.Json.arr([]) : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_controlPlane_distro_k8s_scheduler_enabled:
  {V.Config.value("", ["controlPlane", "distro", "k8s", "scheduler", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_controlPlane_distro_k8s_scheduler_extraArgs:
  {V.Config.value("", ["controlPlane", "distro", "k8s", "scheduler", "extraArgs"]) == J.Json.arr([]) : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_controlPlane_backingStore_database_embedded_enabled:
  {V.Config.value("", ["controlPlane", "backingStore", "database", "embedded", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_controlPlane_backingStore_etcd_embedded_enabled:
  {V.Config.value("", ["controlPlane", "backingStore", "etcd", "embedded", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_controlPlane_coredns_enabled:
  {V.Config.value("", ["controlPlane", "coredns", "enabled"]) == J.JBool{True{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_controlPlane_coredns_deployment_replicas:
  {V.Config.value("", ["controlPlane", "coredns", "deployment", "replicas"]) == J.JNum{"1"} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_controlPlane_standalone_enabled:
  {V.Config.value("", ["controlPlane", "standalone", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_controlPlane_standalone_joinNode_enabled:
  {V.Config.value("", ["controlPlane", "standalone", "joinNode", "enabled"]) == J.JBool{True{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_networking_serviceCIDR:
  {V.Config.value("", ["networking", "serviceCIDR"]) == J.JStr{""} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_networking_podCIDR:
  {V.Config.value("", ["networking", "podCIDR"]) == J.JStr{"10.244.0.0/16"} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_networking_advanced_clusterDomain:
  {V.Config.value("", ["networking", "advanced", "clusterDomain"]) == J.JStr{"cluster.local"} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_privateNodes_enabled:
  {V.Config.value("", ["privateNodes", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_toHost_services_enabled:
  {V.Config.value("", ["sync", "toHost", "services", "enabled"]) == J.JBool{True{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_toHost_endpoints_enabled:
  {V.Config.value("", ["sync", "toHost", "endpoints", "enabled"]) == J.JBool{True{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_toHost_endpointSlices_enabled:
  {V.Config.value("", ["sync", "toHost", "endpointSlices", "enabled"]) == J.JBool{True{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_toHost_persistentVolumeClaims_enabled:
  {V.Config.value("", ["sync", "toHost", "persistentVolumeClaims", "enabled"]) == J.JBool{True{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_toHost_configMaps_enabled:
  {V.Config.value("", ["sync", "toHost", "configMaps", "enabled"]) == J.JBool{True{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_toHost_secrets_enabled:
  {V.Config.value("", ["sync", "toHost", "secrets", "enabled"]) == J.JBool{True{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_toHost_pods_enabled:
  {V.Config.value("", ["sync", "toHost", "pods", "enabled"]) == J.JBool{True{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_toHost_ingresses_enabled:
  {V.Config.value("", ["sync", "toHost", "ingresses", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_toHost_priorityClasses_enabled:
  {V.Config.value("", ["sync", "toHost", "priorityClasses", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_toHost_networkPolicies_enabled:
  {V.Config.value("", ["sync", "toHost", "networkPolicies", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_toHost_volumeSnapshots_enabled:
  {V.Config.value("", ["sync", "toHost", "volumeSnapshots", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_toHost_volumeSnapshotContents_enabled:
  {V.Config.value("", ["sync", "toHost", "volumeSnapshotContents", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_toHost_podDisruptionBudgets_enabled:
  {V.Config.value("", ["sync", "toHost", "podDisruptionBudgets", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_toHost_serviceAccounts_enabled:
  {V.Config.value("", ["sync", "toHost", "serviceAccounts", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_toHost_storageClasses_enabled:
  {V.Config.value("", ["sync", "toHost", "storageClasses", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_toHost_persistentVolumes_enabled:
  {V.Config.value("", ["sync", "toHost", "persistentVolumes", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_toHost_namespaces_enabled:
  {V.Config.value("", ["sync", "toHost", "namespaces", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_toHost_resourceClaims_enabled:
  {V.Config.value("", ["sync", "toHost", "resourceClaims", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_toHost_resourceClaimTemplates_enabled:
  {V.Config.value("", ["sync", "toHost", "resourceClaimTemplates", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_toHost_gatewayApi_enabled:
  {V.Config.value("", ["sync", "toHost", "gatewayApi", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_toHost_gatewayApi_gateways_enabled:
  {V.Config.value("", ["sync", "toHost", "gatewayApi", "gateways", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_toHost_gatewayApi_httpRoutes_enabled:
  {V.Config.value("", ["sync", "toHost", "gatewayApi", "httpRoutes", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_toHost_gatewayApi_tlsRoutes_enabled:
  {V.Config.value("", ["sync", "toHost", "gatewayApi", "tlsRoutes", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_toHost_gatewayApi_backendTLSPolicies_enabled:
  {V.Config.value("", ["sync", "toHost", "gatewayApi", "backendTLSPolicies", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_toHost_gatewayApi_referenceGrants_enabled:
  {V.Config.value("", ["sync", "toHost", "gatewayApi", "referenceGrants", "enabled"]) == J.JStr{"auto"} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_fromHost_events_enabled:
  {V.Config.value("", ["sync", "fromHost", "events", "enabled"]) == J.JBool{True{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_fromHost_configMaps_enabled:
  {V.Config.value("", ["sync", "fromHost", "configMaps", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_fromHost_csiDrivers_enabled:
  {V.Config.value("", ["sync", "fromHost", "csiDrivers", "enabled"]) == J.JStr{"auto"} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_fromHost_csiNodes_enabled:
  {V.Config.value("", ["sync", "fromHost", "csiNodes", "enabled"]) == J.JStr{"auto"} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_fromHost_csiStorageCapacities_enabled:
  {V.Config.value("", ["sync", "fromHost", "csiStorageCapacities", "enabled"]) == J.JStr{"auto"} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_fromHost_storageClasses_enabled:
  {V.Config.value("", ["sync", "fromHost", "storageClasses", "enabled"]) == J.JStr{"auto"} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_fromHost_ingressClasses_enabled:
  {V.Config.value("", ["sync", "fromHost", "ingressClasses", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_fromHost_gatewayClasses_enabled:
  {V.Config.value("", ["sync", "fromHost", "gatewayClasses", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_fromHost_gateways_enabled:
  {V.Config.value("", ["sync", "fromHost", "gateways", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_fromHost_runtimeClasses_enabled:
  {V.Config.value("", ["sync", "fromHost", "runtimeClasses", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_fromHost_priorityClasses_enabled:
  {V.Config.value("", ["sync", "fromHost", "priorityClasses", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_fromHost_nodes_enabled:
  {V.Config.value("", ["sync", "fromHost", "nodes", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_fromHost_secrets_enabled:
  {V.Config.value("", ["sync", "fromHost", "secrets", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_fromHost_volumeSnapshotClasses_enabled:
  {V.Config.value("", ["sync", "fromHost", "volumeSnapshotClasses", "enabled"]) == J.JBool{False{}} : J.Json}

# chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values)
law vcluster_config.default_sync_fromHost_deviceClasses_enabled:
  {V.Config.value("", ["sync", "fromHost", "deviceClasses", "enabled"]) == J.JBool{False{}} : J.Json}

# Proposed: the strict decoder rejects every unknown field, regardless of
# its value or the result of decoding the remaining fields.
law vcluster_config.unknown_field_general:
  for +key: String
  for value: Result<&2, &2, String, J.Json>
  for rest: Result<&2, &2, String, J.Json>
  {V.Config.member(key, value, rest, False{}) == Fail{"error unmarshaling JSON: while decoding JSON: json: unknown field " ++ J.Json.quote(key)} : Result<&2, &2, String, J.Json>}

# Proposed: private nodes alone do not require an endpoint or nonempty CIDR.
# pkg/config/validation.go validatePrivatedNodesMode with its other fields
# at zero values; validation_test.go "Valid: no security context configured".
law vcluster_config.private_nodes:
  {V.Config.error("privateNodes:\n  enabled: true\n") == "" : String}
