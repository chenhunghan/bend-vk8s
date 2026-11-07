# vcluster.yaml subset

`src/config/vcluster.bend` exports `Config.parse(document)`. It returns
`Result<&2, &2, String, J.Json>`. Success contains the defaulted configuration
as `bend-kube-runtime@0.2.0.0` JSON. Failure contains an error message.
The caller supplies the file contents. This module does no IO and does not
change the CLI or guest boot plan.

The reference is loft-sh/vcluster `a8ab30eab6f27b183a80783f4e5854c1a2eb6ef5`.
Defaults come from `chart/values.yaml`. Validation comes from
`pkg/config/validation.go`. Strict decoding comes from `pkg/config/parse.go`
and `vendor/sigs.k8s.io/yaml/yaml.go`.

## Supported fields

- `controlPlane.distro.k8s`: `enabled`, `version`, and `enabled`/`extraArgs`
  under `apiServer`, `controllerManager`, and `scheduler`.
- `controlPlane.backingStore.database.embedded.enabled` and
  `controlPlane.backingStore.etcd.embedded.enabled`.
- `controlPlane.coredns.enabled` and
  `controlPlane.coredns.deployment.replicas`.
- `controlPlane.standalone.enabled` and
  `controlPlane.standalone.joinNode.enabled`.
- `networking.serviceCIDR`, `networking.podCIDR`, and
  `networking.advanced.clusterDomain`.
- `privateNodes.enabled`.
- All built-in `sync.toHost.<resource>.enabled` and
  `sync.fromHost.<resource>.enabled` flags in the chart, including the
  nested Gateway API flags, resource claims, and device classes.

`customResources` contains resource-specific configuration, not a built-in
resource enable flag. It is outside this subset. Mapping tables, selectors,
patches, integrations, and other chart settings are outside the subset too.
The strict decoder rejects fields outside the supported schema. This means
it also rejects valid upstream fields outside this projection. Pro flags
cause no Pro operation. No Pro binary is used.

## YAML syntax

`src/config/yaml.bend` reads block maps, block sequences (including map
items and indentless sequences), plain scalars, single-quoted strings with
doubled quotes, double-quoted JSON strings, comments, and JSON flow values.
A complete JSON document is accepted. JSON numbers are supported; YAML-only
numeric spellings are not converted. The reader rejects duplicate block
keys and invalid container indentation. Nesting uses input-sized fuel.

Anchors, aliases, tags, block scalars, non-JSON flow collections, and multiple
documents are outside the subset. Syntax and value-type diagnostics are
local subset errors. They do not reproduce libyaml's line/column messages
or Go's struct type names. Unknown-field and semantic validation messages
match `ParseConfigBytes`; `Config.UnmarshalYAMLStrict` adds `invalid config: `
upstream, which is not part of this API's message.

## Upstream behavior retained

- Chart flags for both backing stores default to false. `BackingStoreType`
  still selects SQLite. Embedded etcd wins when both flags are true.
- Kubernetes version defaults to the empty string. Runtime image-version
  selection is separate. The parser does not substitute an image tag.
- Service CIDR and standalone enabled are absent from the chart. Their Go
  zero values are the defaults. Pod CIDR is `10.244.0.0/16` and cluster
  domain is `cluster.local`.
- CoreDNS replicas live under `deployment`, not directly under `coredns`.
- CSI and host storage-class flags retain `auto`. Scheduler plus PVC sync
  turns the three CSI flags on. It turns host storage-class sync on only
  when virtual-to-host storage-class sync is off.
- A virtual scheduler requires real host-node sync.
- Storage-class and priority-class sync cannot run in both directions.
- Volume snapshots and volume snapshot contents must be enabled together.
- Host ConfigMap/Secret/Gateway import requires mappings. This subset
  cannot supply mappings, so enabling these modes returns the upstream
  empty-mappings error. Namespace sync has the same constraint.
- An empty reference-grant flag becomes `auto`. Values other than `auto`,
  `true`, or `false` are rejected.
- The parser does not infer private nodes from standalone settings.
  `ParseStandaloneConfigBytes` is a different upstream entry point.
- Empty input yields the chart projection. Null leaves retain defaults.
  False and empty lists replace defaults. Service-object canonicalization
  would discard these values and is therefore not used for configurations.

## Evidence and remaining verification

The first two commits added laws and tests before production code.
Expected values were transcribed from upstream source and tests. No expected
value was obtained from this Bend implementation. The factory rules prohibit
local builds and test runs, including Go tests, so Go execution was not used
to confirm the fixtures in this round.

There are 86 config laws and 17 YAML laws. Each has a proof body. The root
law and proof files import both modules. Executable tests print PASS/FAIL.
CI runs the normal gate and explicitly checks both new modules with
`--verdict`. There are no completion markers yet. Add them only after CI
reports that both modules prove and their verdicts pass.

The config test mapping is below. The remaining cases in
`config/config_test.go` test image parsing or Pro feature detection, not this
parser. Cases in `pkg/config/validation_test.go` that require mappings,
selectors, patches, admission hooks, integrations, auto-upgrade settings,
custom-resource definitions, or workload service accounts are outside the
parsed subset. Their inputs are not silently reduced to enable flags.
`TestConfig_Diff/Simple` supplies a decoder fixture; diff serialization is
outside this module. `TestValidateToHostNamespaceSyncMappings` calls a helper
directly; the parser law retains the public entry point's `namespace sync: `
error prefix.

| Upstream source or case | Law |
| --- | --- |
| chart/values.yaml: empty document overlays chart defaults | `vcluster_config.empty_defaults` |
| config/config_test.go TestConfig_Diff/Simple (parsed input; serialization is outside this module) | `vcluster_config.diff_simple` |
| config/config_test.go TestConfig_UnmarshalYAMLStrict/Invalid: yaml | `vcluster_config.unknown_yaml` |
| config/config_test.go TestConfig_UnmarshalYAMLStrict/Invalid: json | `vcluster_config.unknown_json` |
| config/config_test.go TestConfig_UnmarshalYAMLStrict/Invalid: Old values format | `vcluster_config.old_format` |
| config/config_test.go TestConfig_UnmarshalYAMLStrict/Success: New values format | `vcluster_config.new_yaml` |
| config/config_test.go TestConfig_UnmarshalYAMLStrict/Success: New values format (json) | `vcluster_config.new_json` |
| config/config.go K8S/apiServer.extraArgs | `vcluster_config.args_sequence` |
| chart/values.yaml CoreDNS.Deployment.Replicas | `vcluster_config.coredns_replicas` |
| config/config.go Networking | `vcluster_config.networking` |
| config/config.go Standalone; chart/values.yaml joinNode | `vcluster_config.standalone` |
| pkg/config/validation.go:130 | `vcluster_config.storage_both` |
| pkg/config/validation.go:134 | `vcluster_config.priority_both` |
| pkg/config/validation.go:139-145 | `vcluster_config.volumeSnapshots_alone` |
| pkg/config/validation.go:139-145 | `vcluster_config.volumeSnapshotContents_alone` |
| pkg/config/validation.go:125 | `vcluster_config.scheduler_needs_nodes` |
| pkg/config/validation.go validateFromHostSyncMappings: enabled, no mappings | `vcluster_config.configMaps_needs_mappings` |
| pkg/config/validation.go validateFromHostSyncMappings: enabled, no mappings | `vcluster_config.secrets_needs_mappings` |
| pkg/config/validation.go validateGatewayMappings | `vcluster_config.gateway_needs_mappings` |
| pkg/config/validation_test.go TestValidateToHostNamespaceSyncMappings/Sync enabled, no mappings (public entry-point prefix) | `vcluster_config.namespace_no_mappings` |
| pkg/config/validation_test.go TestValidateToHostNamespaceSyncMappings/Sync disabled | `vcluster_config.namespace_disabled` |
| pkg/config/validation.go validateGatewayAPIConfig | `vcluster_config.reference_grants_invalid` |
| pkg/config/validation.go:64-77 | `vcluster_config.auto_csi` |
| config/config.go BackingStoreType | `vcluster_config.sqlite_default` |
| config/config.go BackingStoreType | `vcluster_config.etcd` |
| config/config.go BackingStoreType | `vcluster_config.etcd_precedence` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_controlPlane_distro_k8s_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_controlPlane_distro_k8s_version` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_controlPlane_distro_k8s_apiServer_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_controlPlane_distro_k8s_apiServer_extraArgs` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_controlPlane_distro_k8s_controllerManager_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_controlPlane_distro_k8s_controllerManager_extraArgs` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_controlPlane_distro_k8s_scheduler_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_controlPlane_distro_k8s_scheduler_extraArgs` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_controlPlane_backingStore_database_embedded_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_controlPlane_backingStore_etcd_embedded_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_controlPlane_coredns_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_controlPlane_coredns_deployment_replicas` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_controlPlane_standalone_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_controlPlane_standalone_joinNode_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_networking_serviceCIDR` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_networking_podCIDR` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_networking_advanced_clusterDomain` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_privateNodes_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_toHost_services_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_toHost_endpoints_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_toHost_endpointSlices_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_toHost_persistentVolumeClaims_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_toHost_configMaps_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_toHost_secrets_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_toHost_pods_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_toHost_ingresses_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_toHost_priorityClasses_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_toHost_networkPolicies_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_toHost_volumeSnapshots_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_toHost_volumeSnapshotContents_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_toHost_podDisruptionBudgets_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_toHost_serviceAccounts_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_toHost_storageClasses_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_toHost_persistentVolumes_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_toHost_namespaces_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_toHost_resourceClaims_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_toHost_resourceClaimTemplates_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_toHost_gatewayApi_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_toHost_gatewayApi_gateways_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_toHost_gatewayApi_httpRoutes_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_toHost_gatewayApi_tlsRoutes_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_toHost_gatewayApi_backendTLSPolicies_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_toHost_gatewayApi_referenceGrants_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_fromHost_events_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_fromHost_configMaps_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_fromHost_csiDrivers_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_fromHost_csiNodes_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_fromHost_csiStorageCapacities_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_fromHost_storageClasses_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_fromHost_ingressClasses_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_fromHost_gatewayClasses_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_fromHost_gateways_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_fromHost_runtimeClasses_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_fromHost_priorityClasses_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_fromHost_nodes_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_fromHost_secrets_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_fromHost_volumeSnapshotClasses_enabled` |
| chart/values.yaml (absent serviceCIDR/standalone.enabled use Go zero values) | `vcluster_config.default_sync_fromHost_deviceClasses_enabled` |
Additional laws: `vcluster_config.unknown_field_general` quantifies over the
field name and decoded values; `vcluster_config.private_nodes` covers
`TestValidateAutoUpgradeSecurityContext/Valid: no security context configured`.
The YAML laws cover empty input, nested maps, sequences, indentless sequences,
scalar types, quoting, comments, empty collections, JSON, null entries,
duplicate keys, invalid indentation, multiple documents, unterminated quotes,
unsupported block scalars, quoted keys, and map entries in sequences.
