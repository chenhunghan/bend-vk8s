# vCluster sync rules for the Bend rewrite: explorer report

Repo: `/home/node/task`, branch main. Line numbers are per file. Quotes are at most three lines. Anything I did not read is marked "not verified".

## Findings

### F0. What is and is not in this repo

- The multi-namespace translator and namespace mapper are Pro stubs. I can only report their hooks.
  - `pkg/pro/namespace_sync.go:10` is `var GetNamespaceMapper = func(...)`, and its body returns `NewFeatureError(licenseapi.SyncNamespacesTohost)`.
  - `pkg/pro/namespace_sync.go:14` is `GetWithSyncedNamespacesTranslator`, with the same error.
- `translate.Default` is chosen at `pkg/setup/config/config.go:78`. It is `pro.GetWithSyncedNamespacesTranslator(...)` when `Sync.ToHost.Namespaces.Enabled` is true. Otherwise it is `translate.NewSingleNamespaceTranslator(vConfig.HostNamespace)`.
- The OSS importer is a no-op.
  - `pkg/pro/import.go:15`: `func (n *noopImporter) Import(...) (bool, error) { return false, nil }`.
  - `IgnoreHostObject` returns false at `pkg/pro/import.go:19`.
- Translate patches are Pro. Any non-empty patch list fails (`pkg/pro/patches.go:10-24`). The error text is:
  - `you are trying to use a vCluster pro feature '%s' (%s) that is not available in the open source vcluster or disabled in your license. ...` (`pkg/pro/error.go:14`).
- Hybrid scheduling is Pro. `pkg/controllers/resources/pods/scheduling/config.go:16` returns `pro.NewFeatureError(licenseapi.HybridScheduling)` when enabled.
- Istio patches are a no-op (`pkg/pro/istio.go:8`).
- ResourceClaim, ResourceClaimTemplate and DeviceClass have mappers but no syncer.
  - Mappers: `pkg/mappings/resources/register.go:42-44`.
  - The syncer list `pkg/controllers/resources/register.go:53-87` has no entry for them.
  - Only pod translation uses them: `pods/translate/translator.go:912-932` and `diff.go:241-273`.
  - `ExtraControllers` at `pkg/controllers/resources/register.go:45` could add one. Not verified.

### F1. Host name and namespace translation (question 2)

- Defaults and constants (all in `pkg/util/translate/types.go`):
  - `VClusterName = "suffix"` (line 29). It is set at startup by `pkg/setup/config/config.go:92`.
  - `K8sServiceNameLabel = "kubernetes.io/service-name"` (line 34).
- `SafeConcatName` is at `pkg/util/translate/translate.go:211-218`:
  ```
  fullPath := strings.Join(name, "-")
  if len(fullPath) > 63 {
  	return strings.ReplaceAll(fullPath[0:52]+"-"+hex.EncodeToString(digest[0:])[0:10], ".-", "-")
  ```
  - The result is 52 chars, then "-", then the first 10 hex chars of sha256 of the full joined string. That is exactly 63 chars.
  - A name of exactly 63 chars is untouched. The `.-` replacement runs only on the truncated form.
  - I computed one example by re-implementing the rule in python, not from a Go test. `"x"*64` gives `"x"*52 + "-7ce100971f"`.
- Namespaced `HostName` is `SingleNamespaceHostName(name, namespace, suffix)` = `SafeConcatName(name, "x", namespace, "x", suffix)`.
  - It lives in the target namespace (`single_namespace.go:35-44` and `59-64`).
  - Empty `vName` gives an empty `NamespacedName`.
  - Example from a test: `testservice-x-test-x-suffix` at `ingresses/syncer_test.go:431`.
- `HostNamespace(vNs)` is `""` for an empty input, otherwise the target namespace (`single_namespace.go:150-156`).
- `HostNameCluster(name)` is `SafeConcatName("vcluster", name, "x", s.targetNamespace, "x", VClusterName)` (`single_namespace.go:66-71`).
  - Test example: `"vcluster-high-priority-x-test-x-vcluster"` at `pods/syncer_test.go:628`.
- `MarkerLabelCluster()` is `SafeConcatName(s.targetNamespace, "x", VClusterName)` (`single_namespace.go:73-75`).
- `HostNameShort` (`single_namespace.go:46-57`):
  - Digest input is `strings.Join([]string{vName, "x", vNamespace, "x", VClusterName}, "-")`.
  - The result is `"v" + base36(sha256)[0:13]`.
  - It is used only by the ResourceClaim and ResourceClaimTemplate mappers.
- Label key translation:
  - Prefix constants are `LabelPrefix = "vcluster.loft.sh/label"` and `NamespaceLabelPrefix = "vcluster.loft.sh/ns-label"` (`types.go:25-26`).
  - The key is `SafeConcatName(prefix, VClusterName, "x", hex(sha256(key))[0:10])` (`single_namespace.go:168-171`).
  - I confirmed these hashes against the tests with python:
    - `release` gives `a4d451ec23`, as in `translate_test.go:28`.
    - `vcluster.loft.sh/namespace` gives `101dcd4e86`.
    - `vcluster.loft.sh/managed-by` gives `e5f1b28ab2`, as in `translate_test.go:129-130`.
    - `vcluster.loft.sh/controlled-by` gives `2080cec00f`.
- Translated label set is exactly four keys: `release`, `NamespaceLabel`, `MarkerLabel`, `ControllerLabel` (`single_namespace.go:138-148`).
- Mapper behaviour by resource:

| Resource | VirtualToHost | HostToVirtual |
|---|---|---|
| Most namespaced kinds | `translate.Default.HostName` (`pods.go:11`, `ingresses.go`, `networkpolicies.go`, `serviceaccounts.go`, `persistentvolumeclaims.go`) | recorder: store, then annotations, then name heuristics |
| `default/kubernetes` Service, Endpoints, EndpointSlice | `{Name: VClusterName, Namespace: ctx.CurrentNamespace}` (`services.go:74-82`, `endpoints.go:28-36`, `endpointslices.go:27-35`) | the reverse (`services.go:85`) |
| ConfigMap `kube-root-ca.crt` | `SafeConcatName("vcluster","kube-root-ca.crt","x",VClusterName)` (`configmaps.go:35-40`) | the host `kube-root-ca.crt` is ignored and the special name is translated back (`configmaps.go:45-60`) |
| PriorityClass, StorageClass | `HostNameCluster` (`priorityclasses.go:18`, `storageclasses.go:17`) | store, annotations, name |
| PV, VolumeSnapshotContent | `HostNameCluster`, unless the annotation `vcluster.loft.sh/host-pv` or `vcluster.loft.sh/host-volumesnapshotcontent` is set (`persistentvolumes.go:24-28`, `volumesnapshotcontents.go:35-39`, `constants/annotation.go:10-12`) | falls back to `{Name: req.Name}` (`persistentvolumes.go:43`, `volumesnapshotcontents.go:54`) |
| Node, IngressClass-style from-host kinds, VolumeSnapshotClass, DeviceClass | mirror mapper: same name, namespace translated only if non-empty (`generic/mirror.go:38-48`) | annotation name if set, otherwise same name with empty namespace (`generic/mirror.go:50-65`) |
| Namespace in single mode | `{Name: translate.Default.HostNamespace(...)}` (`namespaces.go:35-37`) | empty (`namespaces.go:39`) |
| Event | empty (`events.go:44`) | involved object's virtual namespace, plus name with involved-object prefix swapped (`mappings/resources/events.go:49-76`, `82-88`) |
| CSIStorageCapacity | `NameAnnotation` and `NamespaceAnnotation` of the virtual object, else empty (`csistoragecapacities/mapper.go:63-76`) | `{Name: SafeConcatName(req.Name,"x",req.Namespace), Namespace: "kube-system"}` (`mapper.go:59-61`) |

- Mapper lookup is not pure.
  - `recorder.VirtualToHost` checks the store first (`generic/recorder.go:180-183`), then the translate function.
  - It also records references when a mapping owner is in context (`recorder.go:232-257`).
- `HostToVirtual` order in the generic mapper (`generic/mapper.go:84-98`):
  1. `verify.CheckHostObject`.
  2. `TryToTranslateBackByAnnotations`.
  3. `TryToTranslateBackByName`.
- The annotation path rejects the object when any of these hold:
  - the marker label is set and differs from `VClusterName`;
  - the kind annotation differs;
  - the host name annotation differs;
  - the host namespace annotation differs.
- `TryToTranslateBackByName` is not pure either.
  - It uses `HostNameShort` matching and mapping store lookups (`generic/mapper.go:151-290`).
  - In multi-namespace mode it uses the namespace mapper (`mapper.go:157-181`).
- `verify.CheckHostObject` (`mappings/store/verify/verify.go:16-28`) rejects any host object outside the targeted namespace.
- Gateway mapper (`mappings/resources/gateways.go`, imported mapper):
  - Order: `Mappings.ByName` exact key `"<ns>/<name>"`, then `"<ns>/*"`, then `HostName` if Gateway sync is enabled, then identity.
  - `ParseGatewayNamespacedName` expects exactly `ns/name`, and `*` means the same name.

### F2. Metadata rules (question 3)

Bookkeeping keys, quoted from `types.go:10-16`, `types.go:20-26`, `types.go:31-32`:

```
NamespaceAnnotation "vcluster.loft.sh/object-namespace"   NameAnnotation "vcluster.loft.sh/object-name"
UIDAnnotation "vcluster.loft.sh/object-uid"               KindAnnotation "vcluster.loft.sh/object-kind"
HostNameAnnotation "vcluster.loft.sh/object-host-name"    HostNamespaceAnnotation "vcluster.loft.sh/object-host-namespace"
ImportedMarkerAnnotation "vcluster.loft.sh/object-imported"
MarkerLabel "vcluster.loft.sh/managed-by"  NamespaceLabel "vcluster.loft.sh/namespace"  ControllerLabel "vcluster.loft.sh/controlled-by"  VClusterReleaseLabel "release"
ManagedAnnotationsAnnotation "vcluster.loft.sh/managed-annotations"  ManagedLabelsAnnotation "vcluster.loft.sh/managed-labels"
```

Other constants:
- `SkipBackSyncInMultiNamespaceMode = "vcluster.loft.sh/skip-backsync"` (`translate.go:34`).
- `SyncResourceAnnotation = "vcluster.loft.sh/force-sync"` and `SkipTranslationAnnotation = "vcluster.loft.sh/skip-translate"` (`constants/annotation.go:4-5`).
- Pod-local keys, `pods/translate/translator.go:38-47`:
  - `OwnerReferences = "vcluster.loft.sh/owner-references"`
  - `OwnerSetKind = "vcluster.loft.sh/owner-set-kind"`
  - `NamespaceAnnotation = "vcluster.loft.sh/namespace"`
  - `NameAnnotation = "vcluster.loft.sh/name"`
  - `VClusterLabelsAnnotation = "vcluster.loft.sh/labels"`
  - `UIDAnnotation = "vcluster.loft.sh/uid"`
  - `ServiceAccountNameAnnotation = "vcluster.loft.sh/service-account-name"`
  - `ServiceAccountTokenAnnotation = "vcluster.loft.sh/token-"`
  - Cluster autoscaler keys: `cluster-autoscaler.kubernetes.io/safe-to-evict` and `cluster-autoscaler.kubernetes.io/daemonset-pod`.

Create path, virtual to host (`translate.go:58-64`):
- `HostMetadata` = `CopyObjectWithName(setOwner=true)`.
  - `ResetObjectMetadata` clears generateName, selfLink, UID, resourceVersion, generation, creationTimestamp, deletionTimestamp, deletionGracePeriod, ownerReferences, finalizers and managedFields (`translate.go:243-255`).
  - Name and, for namespaced objects, namespace are set.
  - Owner references are set only for namespaced objects and only when `translate.Owner != nil` (`translate.go:44-52`).
- `HostAnnotations` (`translate.go:117-152`):
  - Copies the virtual annotations minus the excluded set and minus the six bookkeeping keys.
  - Writes `NameAnnotation` = virtual name and `UIDAnnotation` = virtual UID.
  - Writes `HostNameAnnotation` and `HostNamespaceAnnotation`. The second is written only if the host namespace is non-empty.
  - Writes `NamespaceAnnotation` = virtual namespace, or deletes the key for cluster-scoped objects.
  - Writes `KindAnnotation` = `gvk.String()`.
- Managed annotations (`translate.go:262-280`, `309-335`):
  - `ManagedAnnotationsAnnotation` is the sorted copied keys joined by `"\n"`. The key is removed when the set is empty.
  - Host-only extra keys survive, unless they are in the managed set recorded on the host.
- `HostLabels` (`labels.go:193-207`):
  - Always adds the markers, because `isMetadata` is true.
  - Namespaced objects get `MarkerLabel=VClusterName` and `NamespaceLabel=<vNamespace>`.
  - Cluster-scoped objects get `MarkerLabel=MarkerLabelCluster()` and no namespace label.
- `HostLabelsMap` (`labels.go:43-73`):
  - Skips virtual keys that already look like translated keys.
  - Translates the four reserved keys.
  - Adds markers only if `isMetadata`, or `pLabels == nil`, or the host already has a marker label.
  - Preserves the host `ControllerLabel`.
- `VirtualAnnotations` (`translate.go:83-93`) excludes eight keys from the host side: Name, Namespace, HostName, HostNamespace, UID, Kind, ManagedAnnotations, ManagedLabels. It keeps those keys from the virtual object when present.
- `VirtualLabelsMap` (`labels.go:75-103`):
  - Drops the markers, the controlled-by label and every key with the `ns-label` prefix.
  - Maps translated keys back.
  - Preserves the virtual value for a key that exists on both sides.

Update path, bidirectional (`labels.go:228-260`, `274-302`, `328-381`):
- The change is computed with `mergeMaps(before, after, target)`:
  - A key is deleted when it is absent from `after`.
  - A key is set when it is added or changed.
- Annotations:
  - If virtualOld differs from virtual, the diff is applied to host.
  - Otherwise, if hostOld differs from host, the diff is applied to virtual.
  - Eight keys are never merged: Host/Name/Namespace/UID/Kind and ManagedAnnotations/ManagedLabels (`labels.go:229`).
  - After the merge, `addHostAnnotations(newHost, event.Virtual, event.Host)` re-writes the bookkeeping keys (`labels.go:258`).
- Labels use the same rule with the key translated through `HostLabel` or `VirtualLabel`.
- The managed-annotations key is not written by the bidirectional path.
  - Test: `services/syncer_test.go:80-96` expects host annotations to carry `a: b` plus the six bookkeeping keys and no managed-annotations key.
- `ApplyMetadata` is the only writer of `ManagedLabelsAnnotation`, and only nodes use it (`nodes/translate.go:30`).
  - Test: `nodes/translate_test.go:60-64` expects `ManagedAnnotationsAnnotation: "test"` and `ManagedLabelsAnnotation: "test"`.

Examples from tests:
- `translate_test.go:72-115` (`TestAnnotations`):
  - After `HostAnnotations(vObj, pObj)` on a Secret with annotation `test`, the host map is `test:"test"`, `ManagedAnnotationsAnnotation:"test"`, `KindAnnotation: "/v1, Kind=Secret"` and empty Name/HostName/UID.
  - After adding the host-only key `other`, the managed value becomes `"other\ntest"`.
  - I did not verify the exact `GroupVersionKind.String()` text. The test builds it with `corev1.SchemeGroupVersion.WithKind("Secret").String()`.
- `translate_test.go:37-70`:
  - `HostLabelsMap(pMap, pMap, "test", false)` is an identity on non-reserved labels.
  - With `isMetadata=true` it adds `NamespaceLabel:"test"` and `MarkerLabel: VClusterName`.
- `labels_test.go:13-81` (`TestAnnotationsSync`):
  - The excluded `storageclass.kubernetes.io/is-default-class` is not copied to virtual.
  - Host gets `"my-other"`, because virtual changed and the host side is not blocked in the other direction.
- `translate_test.go:117-141` shows 11 nested `HostLabelsMap` rounds. The final host map is `{...101dcd4e86: "test-9", ...e5f1b28ab2: "suffix", MarkerLabel: VClusterName, NamespaceLabel: "test-10"}`. Reverse translation restores each earlier map exactly.

Selectors:
- `HostLabelSelector` translates the four reserved keys in `MatchLabels` and `MatchExpressions`.
- `HostLabelSelectorNamespace` maps keys to `ns-label` keys.
- `MergeLabelSelectors` unions `MatchLabels` and appends `MatchExpressions` (`labels.go:209-226`).

### F3. Sync framework and deletion rules (question 5)

Reconcile (`pkg/syncer/syncer.go`):
- A conflict error requeues after one second and returns no error (lines 129-134).
- A host object older than the cached version requeues (183-189).
- Dispatch:
  - virtual and host both exist: `Sync` (206-232).
  - only virtual exists: `SyncToHost` (233-243).
  - only host exists: `SyncToVirtual` (244-262).
  - Host objects carrying `vcluster.loft.sh/skip-backsync: "true"` are skipped (246-249).
- UID guard (209-218):
  - If the host has `UIDAnnotation` that differs from the virtual UID, and the kind annotation is empty or equals this syncer's GVK, the host object is deleted.
  - The delete reason is `"virtual object uid is different"`.
  - If the host is already deleting, it requeues after 1s.
  - Syncers with `DisableUIDDeletion: true` skip the guard. These are services, PVCs, PVs and namespaces.
- Exclusion: a host or virtual object with a non-empty `ControllerLabel` label is skipped (390-392, 406-408), unless the syncer implements `ObjectExcluder`.
- First-run cache seeding (293-305): `vObjOld` is a copy of `vObj` with labels nil and RV `"1"`. This forces a one-time label resync from virtual to host.
- Event argument order is `NewSyncEventWithOld(pObjOld, pObj, vObjOld, vObj)` (`synccontext/events.go:31`).
- `ObjectCaching` is on for most syncers, so Old objects exist. Nodes, ingressclass, runtimeclass, CSI, volumesnapshotclass and gatewayclass syncers do not enable it. Their `HostOld` and `VirtualOld` are nil.

`ShouldDeleteHostObject` (`translate.go:154-183`) is true when any of these holds:
- the host object has a deletion timestamp; or
- all of the following hold:
  - `KindAnnotation` is non-empty and equals the object's GVK string;
  - `NameAnnotation` and `HostNameAnnotation` are non-empty and `HostNameAnnotation == pObj.GetName()`;
  - for namespaced objects, `NamespaceAnnotation` and `HostNamespaceAnnotation` are non-empty and the host namespace matches.

`IsManaged`, namespaced (`single_namespace.go:77-132`):
- The host namespace equals the target namespace.
- `MarkerLabel == VClusterName`.
- `NameAnnotation` is non-empty.
- When a mapper exists for the GVK, `pObj.GetName()` equals `mappings.VirtualToHostName(name annotation, namespace annotation)`.
- When `KindAnnotation` is non-empty, it equals the GVK string.
- When the host name or host namespace annotation is non-empty, it equals the actual one.

`IsManaged`, cluster-scoped: `MarkerLabel == MarkerLabelCluster()`.

Common deletion shapes:

| Case | Rule |
|---|---|
| Virtual gone, host present (`SyncToVirtual`) | `patcher.DeleteHostObject` when `event.VirtualOld != nil` or `ShouldDeleteHostObject(Host)`. Used by pods, services, configmaps, secrets, SA, PVC, ingress, endpoints (always), eps (always), netpol, PDB, VS, storageclass. |
| Host gone, virtual present (`SyncToHost`) | If `event.HostOld != nil` or virtual is deleting, `DeleteVirtualObject`. Otherwise create. |
| From-host kinds | `SyncToHost` always deletes the virtual object (`ctx.VirtualClient.Delete`): ingressclass, runtimeclass, csidriver, csinode, csistoragecapacity, volumesnapshotclass, storageclass host, gatewayclass. For nodes and csinodes, deletion is skipped when `HostOld == nil` and the virtual lacks `MarkerLabel == VClusterName` (`nodes/syncer.go:278-286`). |

Delete options:
- Pods: `GracePeriodSeconds: &zero` when a virtual pod must go because the host pod is gone or the virtual pod has started (`pods/syncer.go:188-193`).
- Host pod deleting: the virtual pod is deleted with the virtual `TerminationGracePeriodSeconds` or 30s (`pods/syncer.go:282-298`).
- Virtual deleting: the host pod is deleted with the virtual grace period and a UID precondition (`syncer.go:319-324`).
- PVC and VS use the same pattern.

Mapping store GC:
- `GarbageCollectionInterval = 3 * time.Minute` (`store.go:24`).
- A mapping is dropped when `objectExists` is false (`store.go:106-149`).
- Name conflicts are rejected with `"there is already another name mapping %s -> %s that conflicts with %s -> %s"` (`store.go:650-661`).
- References: `ReferencesTo` excludes the owner mapping itself (`store.go:546-572`).

### F4. Per-syncer: direction, key, default, registration

Defaults are from `chart/values.yaml`. Registration is from `pkg/controllers/resources/register.go:53-87`, mapper registration from `pkg/mappings/resources/register.go:16-45`.

| Syncer | Direction | Config key and default | Registered when |
|---|---|---|---|
| pods | toHost, plus status, labels, annotations, tolerations, conditions back | `sync.toHost.pods.enabled` true (values:32-34) | `ToHost.Pods.Enabled` (reg:60) |
| services | toHost, plus ports, type, externalIPs, status etc. both ways | `sync.toHost.services.enabled` true (6-8) | reg:53 |
| endpoints | toHost, only for selector-less services | `sync.toHost.endpoints.enabled` true (10-12) | reg:58 |
| endpointslices | toHost, same | `sync.toHost.endpointSlices.enabled` true (14-16) | reg:59 |
| configmaps | toHost, `data` and `binaryData` bidirectional, only when used | `sync.toHost.configMaps.enabled` true, `.all` false (22-25) | reg:54 |
| configmaps from host | fromHost | `sync.fromHost.configMaps.enabled` false (164-166) | reg:55 |
| secrets | toHost, `data` and `type` bidirectional, only when used | `sync.toHost.secrets.enabled` true, `.all` false (27-30) | reg:57 |
| secrets from host | fromHost | `sync.fromHost.secrets.enabled` false (273-275) | reg:56 |
| serviceaccounts | toHost, metadata bidirectional | `sync.toHost.serviceAccounts.enabled` false (131-133) | reg:80 |
| persistentvolumeclaims | toHost, status and selected annotations back | `sync.toHost.persistentVolumeClaims.enabled` true (18-20) | reg:62 |
| persistentvolumes real | bidirectional | `sync.toHost.persistentVolumes.enabled` false (139-141) | `persistentvolumes.New` always (reg:86), real when enabled (`persistentvolumes/register.go:9-13`) |
| persistentvolumes fake | virtual only, created from bound PVCs | same key false | same |
| storageclasses | toHost | `sync.toHost.storageClasses.enabled` false (135-137) | reg:73 |
| storageclasses from host | fromHost | `sync.fromHost.storageClasses.enabled` "auto" (200-202) | only when `== "true"` (reg:74) |
| ingresses | toHost, status back | `sync.toHost.ingresses.enabled` false (81-83) | reg:63 |
| ingressclasses | fromHost | `sync.fromHost.ingressClasses.enabled` false (204-206) | reg:70 |
| networkpolicies | toHost | `sync.toHost.networkPolicies.enabled` false (115-117) | reg:77 |
| poddisruptionbudgets | toHost | `sync.toHost.podDisruptionBudgets.enabled` false (127-129) | reg:76 |
| priorityclasses | toHost or fromHost, never both | toHost false (111-113), fromHost false (256-258) | reg:75 |
| namespaces | toHost, Pro mapper | `sync.toHost.namespaces.enabled` false, `mappingsOnly` false (143-147) | reg:85 |
| nodes real | fromHost | `sync.fromHost.nodes.enabled` false (260-262), `selector.all` false (270) | `nodes.New` always (reg:87), real when enabled |
| nodes fake | virtual only, created when pods reference a node | same key false | same |
| events | fromHost | `sync.fromHost.events.enabled` true (160-162) | reg:61 |
| csidrivers, csinodes, csistoragecapacities | fromHost | each "auto" (188-198) | only when `== "true"` (reg:81-83) |
| runtimeclasses | fromHost | `sync.fromHost.runtimeClasses.enabled` false (252-254) | reg:72 |
| volumesnapshots | toHost | `sync.toHost.volumeSnapshots.enabled` false (119-121) | reg:78 |
| volumesnapshotcontents | toHost, PV-style | `sync.toHost.volumeSnapshotContents.enabled` false (123-125) | reg:79 |
| volumesnapshotclasses | fromHost | `sync.fromHost.volumeSnapshotClasses.enabled` false (297-299) | reg:84 |
| gateway classes | fromHost | `sync.fromHost.gatewayClasses.enabled` false (208-210) | reg:71 via `GatewayClassesImportEnabled` |
| gateways imported | fromHost | `sync.fromHost.gateways.enabled` false (212-214) | reg:64 |
| gateways tenant | toHost | `sync.toHost.gatewayApi.gateways.enabled` false (94-96), or `gatewayApi.enabled` false (86-88) | reg:65 |
| httproutes | toHost | `httpRoutes.enabled` false (90-92) or umbrella | reg:66 |
| tlsroutes, backendtlspolicies | toHost | `tlsRoutes`, `backendTLSPolicies` false (98-104), no umbrella | reg:67-68 |
| referencegrants | toHost | `referenceGrants.enabled` "auto" (107-109) | `ReferenceGrantSyncEnabled`: `"true"`, or `"auto"` with a route kind and namespaces sync (`util/gatewayapi/enabled.go:42-52`) |

Validation couplings:
- Validation errors:
  - Both `fromHost.storageClasses` "true" and `toHost.storageClasses`: `"you cannot enable both sync.fromHost.storageClasses.enabled and sync.toHost.storageClasses.enabled at the same time. Choose only one of them"` (`validation.go:130-131`).
  - Both priority class directions: `"cannot sync priorityclasses to and from host at the same time"` (`validation.go:135`).
  - Virtual scheduler without nodes sync: `"sync.fromHost.nodes.enabled is false, but required if using hybrid scheduling or virtual scheduler"` (`validation.go:126`).
  - VolumeSnapshotContents without VolumeSnapshots: `"when syncing volume snapshots contents to the host, one must set sync.toHost.volumeSnapshots.enabled to true"` (`validation.go:140`).
- Scheduler and storage: with a virtual scheduler and PVC sync, CSINodes, CSIStorageCapacities and CSIDrivers "auto" become "true". FromHost StorageClasses becomes "true" only when toHost storage classes are off (`validation.go:63-77`).
- Namespaces sync forces `Secrets.All` and `ConfigMaps.All` true (`validation.go:185-188`).
- Workload service account default name is `"vc-workload-" + vConfig.Name` (`validation.go:191-193`). Tests show `vc-workload-vcluster`.

Registry note: PDB and CSIStorageCapacity are not in the mappings registry list. The PDB syncer builds its own mapper (`poddisruptionbudgets/syncer.go:21`). The CSIStorageCapacity syncer builds its own (`csistoragecapacities/syncer.go:27`).

### F5. Field-by-field rules per syncer

#### Pods (`pods/translate/translator.go` unless noted)

Create (`Translate`, lines 207-454):
- Metadata: `translate.HostMetadata(...)` with the pod mapper name. Then `Status = PodStatus{}`.
- Service account:
  - `Spec.DeprecatedServiceAccount = ""`.
  - `ServiceAccountName = t.serviceAccount`. This is the workload SA name (221).
  - If `sync.toHost.serviceAccounts.enabled`, it is `VirtualToHostName(vName, vNs, ServiceAccounts)` (222-230).
- `AutomountServiceAccountToken = &False` and `EnableServiceLinks = &False` (232-233).
- Priority class (235-257):
  - If toHost priority classes are on and the name is set, the name becomes `HostNameCluster`, and priority is capped to 1000000000.
  - If both toHost and fromHost are off, `PriorityClassName` is cleared and `Priority = nil`.
  - If `sync.toHost.pods.priorityClassName` is set and the pod has none, it is set and `Priority = nil`.
- Annotations (259-311):
  - Copies `vcluster.loft.sh/namespace`, `/name`, `/uid`, `/service-account-name`, `/labels` from virtual annotations when present.
  - Otherwise the fallbacks are: namespace, name, UID, `Spec.ServiceAccountName`, and `LabelsAnnotation(vPod)`.
  - `LabelsAnnotation` is sorted `k=<json value>` pairs joined by `"\n"` (460-474).
  - `cluster-autoscaler.kubernetes.io/safe-to-evict` is `strconv.FormatBool(controller != nil)`.
  - For a DaemonSet controller it also sets `cluster-autoscaler.kubernetes.io/daemonset-pod: "true"`.
  - Owner references are JSON-encoded into `vcluster.loft.sh/owner-references`. `owner-set-kind` is the first apps/v1 owner with Kind DaemonSet, Job, ReplicaSet or StatefulSet.
- Labels: each virtual namespace label `k` is added as `HostLabelNamespace(k)` (313-321).
- Env:
  - Service env vars are built from the virtual services in the namespace (`ServicesToEnvironmentVariables`, 949-994).
  - The 8 Kubernetes vars are quoted at 980-989 with `IP` replaced by the host service ClusterIP:
    ```
    "KUBERNETES_PORT=tcp://IP:443", "KUBERNETES_PORT_443_TCP=tcp://IP:443",
    "KUBERNETES_SERVICE_HOST=IP", "KUBERNETES_SERVICE_PORT=443", "KUBERNETES_SERVICE_PORT_HTTPS=443",
    ```
  - Plus `KUBERNETES_PORT_443_TCP_ADDR`, `..._PORT`, `..._PROTO`.
  - The other service vars are included only if the pod's `EnableServiceLinks` is true and the service has a ClusterIP other than empty or `None` (958-965).
  - `TranslateContainerEnv` (699-741):
    - Prepends the synthesized vars, sorted by name, only when the name is not user-defined.
    - Translates `ConfigMapKeyRef`, `SecretKeyRef`, `envFrom` and field refs.
  - `kubeIP` is the ClusterIP of the host service named `ctx.Config.Name` in `ctx.CurrentNamespace` (`pods/translate.go:56-67`).
- Field refs (`translateFieldRef`, 673-697):
  - `metadata.labels['k']` becomes `metadata.labels['<HostLabel(k)>']`.
  - `metadata.labels` becomes `metadata.annotations['vcluster.loft.sh/labels']`.
  - `metadata.name`, `metadata.namespace`, `metadata.uid` and `spec.serviceAccountName` map to the pod-local annotation keys.
- Host aliases (326-335) append:
  ```
  corev1.HostAlias{IP: kubeIP, Hostnames: kubernetesSvcAliases}
  ```
  - Aliases are `["kubernetes","kubernetes.default","kubernetes.default.svc"]`.
  - When `clusterDomain != ""`, `"kubernetes.default.svc." + clusterDomain` is prepended.
  - Default cluster domain is `"cluster.local"` (`values.yaml:1191`).
  - Test (`pods/syncer_test.go:209-211`): `Hostnames: []string{"kubernetes.default.svc.cluster.local", "kubernetes", "kubernetes.default", "kubernetes.default.svc"}`.
- DNS (753-803):
  - `None` stays as is.
  - `ClusterFirst` without `HostNetwork`, and `ClusterFirstWithHostNet`, are rewritten when `nameServer != ""`.
  - Rewritten config: policy `None`, nameserver = host kube-dns service ClusterIP, option `ndots=5`.
  - Searches are `<ns>.svc.<domain>`, `svc.<domain>`, `<domain>`.
  - Existing nameservers and searches are appended, deduplicated.
  - A missing DNS IP blocks the pod with the error `waiting for DNS service IP` (`pods/translate.go:85-87`).
- Hostname (340-353): empty `Spec.Hostname` becomes the pod name truncated to 63, with `.` replaced by `-` and a trailing `-` trimmed.
- Subdomain (355-364): if set and `sync.toHost.pods.rewriteHosts.enabled` (default true, values:56-58), an init container rewrites `/etc/hosts`, then `Subdomain = ""`.
  - Constants: `HostsRewriteContainerName = "vcluster-rewrite-hosts"`, `HostsVolumeName = "vcluster-rewrite-hosts"`, annotation `vcluster.loft.sh/hosts-rewritten`, `vcluster.loft.sh/disable-subdomain-rewrite` (`hosts.go:8-13`).
  - Default init image is `mirror.gcr.io/library/alpine:3.20` (`values.yaml:62-69`).
  - Test (`translator_test.go:401`): `sed -E -e 's/^(\d+.\d+.\d+.\d+\s+)pod-name$/\1 pod-name.subdomain.test-ns.cluster.local pod-name/' /etc/hosts > /hosts/hosts`.
  - Registry precedence test: `my-registry/library/alpine:3.20` (`translator_test.go:425`).
- Resources (366-370): `Spec.Resources = nil` when the host version is known and below 1.34.0. Tests at `translator_test.go:476-583`.
- Containers, init containers, ephemeral containers (372-403): env translated, image through `translateImage` map (`image_translator.go:17-24`).
- ImagePullSecrets (405-408): `VirtualToHostName(..., Secrets)`.
- Volumes (476-555):
  - ConfigMap, Secret and PVC names are translated.
  - `Ephemeral` volumes become a PVC reference named `ephemeral.VolumeClaimName(vPod, volume)` translated through `HostName`.
    - Test: `translator_test.go:216` expects `translate.Default.HostName(nil, "pod-name-eph-vol", "test-ns").Name`.
  - Projected volumes: secret and configmap sources are translated.
  - DownwardAPI field refs are translated.
  - Legacy secret refs on iscsi, rbd, flexVolume, cinder, cephfs, azureFile, scaleIO, storageOS and CSI are translated.
  - `Glusterfs.EndpointsName` maps through the Endpoints mapper.
- Projected ServiceAccountToken (577-667):
  - A token is requested in the virtual cluster for the pod's SA, default `"default"`, bound to the pod.
  - Audiences are `["https://kubernetes.default.svc."+clusterDomain, "https://kubernetes.default.svc", "https://kubernetes.default"]`, or the single configured audience (591-594).
  - Expiry is `int64(10 * 365 * 24 * 60 * 60)` seconds (596).
  - With `useSecretsForSATokens` (default false, values:48):
    - The source becomes a Secret projection.
    - The secret is named by `SecretNameFromPodName` = `VirtualToHost("<pod>-sa-token", ns, Secrets)` (`token/sa_token_secret.go:26-28`).
    - The key is the volume name, path is the token path, mode 0644 (616-634).
    - The secret is created with `translate.SkipBackSyncInMultiNamespaceMode: "true"` (`sa_token_secret.go:79-81`).
    - It is owned by the vCluster service when `translate.Owner != nil`.
    - The pod syncer later replaces that owner with the pod (`pods/syncer.go:453-470`, `sa_token_secret.go:99-129`).
  - Otherwise the token goes into a pod annotation `"vcluster.loft.sh/token-" + random.String(8)` and the source becomes a DownwardAPI item `metadata.annotations['<key>']` with mode 0644 (635-664).
- Host paths (554, `hostpath.go`): rewritten only when `ControlPlane.HostPathMapper.Enabled && !Central`. Constants are in `hostpath.go:13-24` and the expectation in `pods/syncer_test.go:529-593`. Details of rewriting beyond line 80 not verified.
- Runtime class: `sync.toHost.pods.runtimeClassName` overrides when non-empty (418-421).
- Scheduling (423-444):
  - If the pod's scheduler is a virtual one, `TopologySpreadConstraints`, `Affinity` and `NodeSelector` are cleared.
  - Otherwise, when the target is single-namespace, topology constraints are translated (934-947).
    - They get `NamespaceLabel` and `MarkerLabel` in `MatchLabels`.
  - Pod affinity terms are translated (821-910):
    - `Namespaces` and `NamespaceSelector` are dropped.
    - The label selector is translated and gets `MarkerLabel=VClusterName`.
    - The namespace restriction depends on the term:
      - A null or empty `namespaces` with a null `namespaceSelector` adds `NamespaceLabel=<pod ns>`.
      - A selector only is translated to `ns-label` keys.
      - A `namespaces` list adds a `MatchExpressions In` on `NamespaceLabel`.
    - Both `namespaces` and `namespaceSelector` produce the Warning event `Inter-pod affinity rule(s) that use both .namespaces and .namespaceSelector fields in the same term are not supported by vcluster yet. The .namespaceSelector fields of the unsupported affinity entries will be ignored.` (test `translator_test.go:103`).
  - Virtual `NodeSelector` entries are copied.
- Tolerations (446-451): enforced tolerations are appended if not already present, by full equality.

Create gate (`pods/syncer.go:180-263`):
- Skipped when the pod's priority class or runtime class does not match the configured selector (606-719).
  - The event reason is `SyncWarning`.
  - Message example: `did not sync pod %q to host because the priority class %q in the host does not match the selector under 'sync.fromHost.priorityClasses.selector'`.
- If `HostOld != nil`, or the virtual pod is deleting, or `Status.StartTime != nil`, the virtual pod is deleted with a zero grace period.
- If `policies.podSecurityStandard` is set, the pod must pass the pod security check (`validate_pod_security.go:42-66`).
  - Failure message: `Pod %s is forbidden: %s`.
- If `sync.fromHost.nodes.selector.labels` is set:
  - A pod without `NodeName` gets those labels merged into its `NodeSelector`, and they override same-key entries.
  - A pod with `NodeName` requires that node in the virtual cluster, else it requeues after 15s with the event `Given nodeName %s does not exist in virtual cluster`.
- When the pod's scheduler is a virtual one, the pod is created on the host only once it has a `NodeName` (245-250).
- Test (`pods/syncer_test.go:127-145`): initial selector `{labelA:valueA, labelB:valueB}` plus option `{labelB:enforcedB, otherLabel:abc}` gives `{labelA:valueA, labelB:enforcedB, otherLabel:abc}`.

Update (`Sync`, lines 265-411, and `diff.go:23-181`):
- Node: if the host has `NodeName`, the virtual node must exist, and the virtual pod is bound with a `Binding` to it (522-604). A mismatch deletes the virtual pod.
- Ephemeral containers: virtual ones not in the host are added with translated env through `UpdateEphemeralContainers` (`ephemeral_containers.go:14-79`).
  - A 404 yields `ephemeral containers are disabled for this cluster (error from server: %w)`.
  - Host to virtual ephemeral sync does not exist (comment at line 43).
- In-place resize: when the host version is at least 1.35.0, a strategic merge patch to the `resize` subresource carries container resources that differ (`pods/syncer.go:413-430`, `485-516`).
- `Diff`:
  - Conditions are merged by `CopyBidirectional`, with an `ObservedGeneration`-ignoring comparison when the virtual version is below 1.34 (`diff.go:26-31`, `285-310`).
  - Virtual status becomes `DesiredVirtualStatus(host, virtual)`: host status with the virtual `QOSClass` kept (`diff.go:315-323`). On virtual K8s below 1.34 it also keeps the virtual `ObservedGeneration` and zeroes condition `ObservedGeneration`.
  - Container statuses on virtual are filtered to containers that exist in the virtual spec, so injected sidecars are hidden (`diff.go:214-239`).
  - ResourceClaim names in status are mapped back when `resourceClaims` is on.
  - Annotations: bidirectional, excluding `ClusterAutoScalerAnnotation`, `OwnerReferences`, `OwnerSetKind`, `NamespaceAnnotation`, `NameAnnotation`, `UIDAnnotation`, `ServiceAccountNameAnnotation`, `HostsRewrittenAnnotation`, `VClusterLabelsAnnotation`, and any `vcluster.loft.sh/token-*` annotation referenced by a projected downward item (`diff.go:106-131`).
  - Labels are bidirectional excluding `ns-label` keys. Namespace labels are then rebuilt from the virtual namespace (`diff.go:63-85`).
  - Host annotations `vcluster.loft.sh/labels`, `owner-references` and `owner-set-kind` are refreshed from virtual (`diff.go:87-101`).
  - Spec (`calcSpecDiff`, 140-181):
    - `ActiveDeadlineSeconds` and `SchedulingGates` are copied from virtual.
    - Container and init container images are updated through the image map. The rewrite-hosts init container is skipped.
    - Tolerations are the virtual list, plus host-only ones, plus enforced ones, never removing a host toleration.
    - Tests: `diff_test.go:62-115`. For example, virtual `[initial,new]` with host `[initial,enforced,admission]` gives host `[initial,new,enforced,admission]`.
- Host deleting: the status keeps being propagated to virtual, so controllers can finish (`pods/syncer.go:300-318`).
- Deleting a pod whose virtual and host `NodeName` differ: virtual is deleted with 30s grace (`pods/syncer.go:334-337`).
- Virtual-only create from host (`SyncToVirtual`, 432-451):
  - Virtual metadata is built with `VirtualMetadata`.
  - `NodeName` is cleared.
  - SA names are cleared when SA sync is off.
- Pods namespace watch: namespace label changes requeue all pods in that namespace (`pods/syncer.go:147-172`).

Test expectations for a created host pod (`pods/syncer_test.go:370-404`):
- Annotations include `ClusterAutoScalerAnnotation: "false"`, `VClusterLabelsAnnotation: ""`, both pod-local and object-* name and namespace keys, `KindAnnotation: "/v1, Kind=Pod"` built from `corev1.SchemeGroupVersion.WithKind("Pod").String()`, and `HostNamespaceAnnotation: "test"`.
- Labels are `{NamespaceLabel: "testns", MarkerLabel: VClusterName}`.
- Spec has `AutomountServiceAccountToken` false, `EnableServiceLinks` false, the hostAlias above, `ServiceAccountName: "vc-workload-vcluster"` and `Hostname: "testpod"`.
- Priority class tests: `pods/syncer_test.go:648-695`.

#### Services (`services/syncer.go`, `translate.go`)

- Create: `HostMetadata` plus `HostLabelsMap(vSelector, nil, vNs, false)`.
  - `ClusterIP` is cleared unless it is `"None"`.
  - `ClusterIPs`, `IPFamilies`, `IPFamilyPolicy` are cleared.
  - All `NodePort`s are zeroed.
  - Excluded annotation: `field.cattle.io/publicEndpoints` (`syncer.go:28`, `44-46`).
- Update:
  - Bidirectional via `CopyBidirectional` on `Type`, `ExternalIPs`, `ExternalName`, `LoadBalancerIP`, `Ports`, `PublishNotReadyAddresses`, `ExternalTrafficPolicy`, `SessionAffinity`, `SessionAffinityConfig`, `LoadBalancerSourceRanges`, `HealthCheckNodePort` (132-199).
  - `ensureLoadBalancerStatus` clears `LoadBalancerIP` and `Status.LoadBalancer.Ingress` when the type is not LoadBalancer (312-324).
  - Virtual status is host status.
  - Selector: translated forward if virtual changed or host unchanged, else translated back (215-219).
  - Annotation `vcluster.loft.sh/block-deletion` is removed from host (210).
  - If `Virtual.Spec.ClusterIP != Host.Spec.ClusterIP`, the virtual service is deleted and recreated with the host ClusterIP and `Requeue: true` (95-108).
  - Switching to ExternalName waits 3s (90-92, 224-226).
- Test "Update backward spec no recreation": `services/syncer_test.go:547-575`. "with recreation": 576-604 (ClusterIP `"123:123:123:123"`).
- Special service `default/kubernetes` is synced by `specialservices.SyncKubernetesService`.
  - Ports go through `TranslateServicePorts`: drop the port named `kubelet` and keep only Name, Protocol, AppProtocol, Port, TargetPort (`syncer.go:292-310`).
  - Cluster IP changes delete and recreate (`specialservices/service_syncer.go:58-91`).
- Host-only service with annotation `vcluster.loft.sh/block-deletion: "true"` younger than 2 minutes is not deleted (`syncer.go:232-234`).

#### Endpoints and EndpointSlices

- Only reconciled for services without a selector (`endpoints/syncer.go:148-212`).
  - For a selector service, a host Endpoints object that carries `NameAnnotation` is deleted so Kubernetes can manage it.
  - For a selector-less service, a host object without `NameAnnotation` is deleted so vCluster can manage it.
- `translateSpec` rewrites `TargetRef` for Kind `Pod` to the host pod name and namespace and clears UID and ResourceVersion (`endpoints/translate.go:20-46`).
- The excluded annotation is `control-plane.alpha.kubernetes.io/leader`.
- Endpoint slices: `TargetRef` for Pod is translated. The host `kubernetes.io/service-name` label is set to `virtualSvcName + "-x-" + namespace + "-x-" + vcName` with no `SafeConcatName` (`endpointslices/translate.go:17-25`, `47-49`).
- A virtual EndpointSlice missing in virtual deletes the host one (`endpointslices/syncer.go:133-146`).
- A missing `kubernetes.io/service-name` label gives the error `unable to retrieve label 'kubernetes.io/service-name'` (`endpointslices/syncer.go:155`).
- Tests: `endpoints/syncer_test.go:103`, `endpointslices/syncer_test.go:101`. Their expected host labels contain `NamespaceLabel` but not `MarkerLabel` (`endpoints/syncer_test.go:86-89`). Why is not verified.

#### ConfigMaps and Secrets

- ToHost create happens only when the object is used. "Used" means:
  - the force-sync annotation is `"true"`; or
  - `All` is true; or
  - `ReferencesTo(...)` in the mapping store is non-empty (`configmaps/to_host_syncer.go:154-171`, `secrets/to_host_syncer.go:177-199`).
- When no longer used, the host object is deleted (`to_host_syncer.go:108-113`, `secrets/to_host_syncer.go:101-107`).
- What counts as a reference comes from the pod and ingress scans in `mappings/resources/configmaps.go:107-206` and `secrets.go:176-462`.
  - Pods: env, envFrom, volumes and projected sources, image pull secrets, many legacy secret volume kinds, and `UseSecretsForSATokens` projection.
  - Ingresses: TLS secrets and the annotations `nginx.ingress.kubernetes.io/auth-secret`, `auth-tls-secret`, `proxy-ssl-secret` (`secrets.go:112-116`).
- Secret create: a `kubernetes.io/service-account-token` type becomes `Opaque` on host (`secrets/to_host_syncer.go:89-91`).
- Update: `Data` (and `BinaryData` for configmaps) via `MergeBidirectional`, which JSON-merge-patches the changed side into the other. Secret `Type` is synced only when neither side is the SA token type (`secrets/to_host_syncer.go:138-146`). Annotations and labels use the bidirectional helpers.
- From host: copy annotations, labels and `Data` into the virtual object (`configmaps/from_host_syncer.go:36-42`).
  - Name mapping comes from `sync.fromHost.configMaps.mappings.byName`; matching is in `translator/from_config_translator.go:113-224`.
    - Exact `ns/name` first.
    - Then `ns/*`.
    - Then `"/name"` for the vCluster host namespace.
    - Then `""` (special character `constants.VClusterNamespaceInHostMappingSpecialCharacter = ""`).
  - `kube-root-ca.crt` is skipped (`from_host_syncer.go:30-32`).
  - A host object carrying a `MarkerLabel` is excluded (`genericFromHostSyncer.ExcludePhysical`, `syncer/from_host_syncer.go:150-153`).
  - Test cases: `from_config_translator_test.go:24-148`. Example: mapping `"": "my-ns"` with host `vcluster/my-cm` gives virtual `my-ns/my-cm`.
  - Creating a missing virtual namespace requeues (`from_host_syncer.go:110-126`).

#### ServiceAccounts
- Create: `Secrets = nil`, `ImagePullSecrets = nil`, `AutomountServiceAccountToken = false` (`serviceaccounts/syncer.go:61-64`).
- Update: only annotations and labels, bidirectional.

#### PersistentVolumeClaims (`persistentvolumeclaims/translate.go`, `syncer.go`)
- Storage class:
  - Name from `Spec.StorageClassName`, else the annotation `volume.beta.kubernetes.io/storage-class` (14, 49-54).
  - If `sync.toHost.storageClasses.enabled`: translated through `HostNameCluster`, and the deprecated annotation is removed (57-61).
- With real PVs (`!useFakePersistentVolumes`) and no `skip-translate` annotation:
  - Selector goes through `HostLabelSelector` and `VolumeName` through `HostNameCluster` (64-71).
  - With storage classes off and a class name set: the class is translated only if the host lacks that class when the claim is dynamic, or always when selector or volume name is set (73-87).
- Data sources `VolumeSnapshot` and `PersistentVolumeClaim` are translated, `DataSourceRef` with its own namespace (20-43).
- Excluded annotations: `pv.kubernetes.io/bind-completed`, `pv.kubernetes.io/bound-by-controller`, `volume.beta.kubernetes.io/storage-provisioner` (`syncer.go:39-41`, `54`). They are copied back to virtual by `translateUpdateBackwards`.
- Update: virtual `Status` is host status. `Host.Spec.Resources.Requests = Virtual.Spec.Resources.Requests`, so size can grow (`syncer.go:177-181`).
- If the host `VolumeName` differs, the virtual volume name is set or the PVC is recreated, with a PV lock annotation (`vcluster.loft.sh/lock`, `persistentvolumes/syncer.go:35`) (`syncer.go:205-323`).
- PVC is skipped when the class selector under `sync.fromHost.storageClasses.selector` does not match (325-379).
- Tests: `persistentvolumeclaims/syncer_test.go:146-330`.

#### PersistentVolumes
- Real (`syncer.go`):
  - Host is created from virtual only if the PV has no annotation `host-pv`; the host `ClaimRef` is cleared and the storage class goes through `HostNameCluster` (`translate.go:13-23`).
  - Host to virtual: a host PV is imported when `shouldSync` is true (285-320).
    - That is when its claim maps to a virtual PVC, or it is managed, or it is Retain or Released in the target namespace.
  - Virtual PV gets annotation `vcluster.loft.sh/host-pv=<host name>` and a `ClaimRef` to the virtual PVC (`translate.go:25-46`).
  - Bidirectional fields: `PersistentVolumeSource`, `Capacity`, `AccessModes`, `PersistentVolumeReclaimPolicy`, `NodeAffinity`, `VolumeMode`, `MountOptions` (196-237).
  - Status goes host to virtual (246).
  - A lock annotation younger than one minute requeues after 1s (137-146).
- Fake (`fake_syncer.go`):
  - A virtual PV is created for a virtual PVC whose `Spec.VolumeName` is set, but only if no virtual PV exists.
  - Shape (`CreateFakePersistentVolume`, 134-184):
    ```
    Labels: {"vcluster.loft.sh/fake-pv": "true"}
    Annotations: "kubernetes.io/createdby": "fake-pv-provisioner", "pv.kubernetes.io/bound-by-controller": "true", "pv.kubernetes.io/provisioned-by": "fake-pv-provisioner"
    ```
  - Source is `FlexVolume{Driver: "fake"}`, reclaim policy `Delete`, status phase `Bound`.
  - It is deleted when no PVC references it.
  - Tests: `persistentvolumes/fake_syncer_test.go:88-127`.

#### StorageClasses
- ToHost: name `HostNameCluster`. Bidirectional fields: `Provisioner`, `Parameters`, `ReclaimPolicy`, `MountOptions`, `AllowVolumeExpansion`, `VolumeBindingMode`, `AllowedTopologies`. Annotation `storageclass.kubernetes.io/is-default-class` is excluded (`storageclasses/syncer.go:21`, `73-134`).
- FromHost (`host_syncer.go`):
  - Same name; host metadata copied verbatim, with no marker.
  - A selector mismatch skips creation and deletes an existing virtual copy.
  - Tests: `host_syncer_test.go:64-100`.

#### Ingresses and IngressClasses
- Spec translation (`ingresses/translate.go:94-125`):
  - Service backend names go through the Services mapper.
  - `Resource` backends go through `HostName`.
  - TLS `SecretName` goes through the Secrets mapper.
  - `IngressClassName` is bidirectional (`ingresses/syncer.go:114-119`).
  - Status is host to virtual (120).
- Annotation translation (190-199):
  - The three nginx secret annotations are rewritten, as `secret` or `ns/secret` (`mappings/resources/secrets.go:118-150`).
  - ALB `alb.ingress.kubernetes.io/actions.<name>` and `alb.ingress.kubernetes.io/conditions.<name>` have the name suffix rewritten to `HostName(name, ns)`, unless the key already contains `x-<ns>-x`. Action JSON `serviceName`s are rewritten too (147-188).
  - Test (`ingresses/syncer_test.go:431`): key `alb.ingress.kubernetes.io/actions.testservice-x-test-x-suffix` with `"serviceName":"nginx-service-x-test-x-suffix"`.
  - `loft.sh/ingress-mirror`, `nginx.ingress.kubernetes.io/mirror-target` and `mirror-request-body` are not back-synced when the host owns sleep mode (83-92).
- IngressClasses: a selector gates creation, and existing virtual copies are deleted on mismatch (`ingressclasses/syncer.go:51-98`). Controller and parameters are copied from the host.
- Ingress creation is skipped when the class selector does not match (`ingresses/syncer.go:140-194`).

#### NetworkPolicies (`networkpolicies/translate.go`)
- Pod selector: host label selector, plus `NamespaceLabel=<vNs>` and `MarkerLabel=VClusterName` (57-66).
- Peers:
  - `NamespaceSelector` is dropped.
  - A peer with an `IPBlock` is copied as is.
  - Otherwise the pod selector is merged with the namespace selector translated to `ns-label` keys, `MarkerLabel` is added, and `NamespaceLabel=<vNs>` is added only when the peer's namespace selector is nil (72-99).
- Not supported in multi-namespace mode: it logs and exits. The text is `Multi-Namespace Mode not supported for network policies yet!` (52-54).
- Test: `networkpolicies/syncer_test.go:22-175`.

#### PodDisruptionBudgets
- `MaxUnavailable`, `MinAvailable` and `Selector` (host-translated) are copied virtual to host (`poddisruptionbudgets/translate.go:16-20`). Test: `poddisruptionbudgets/syncer_test.go:85-120`.

#### PriorityClasses (`priorityclasses/translate.go`)
- ToHost: `GlobalDefault = false`, `Value` capped at 1000000000. Bidirectional `PreemptionPolicy` and `Description`.
  - Host `Value` is the capped virtual `Value` (55-59).
- FromHost: virtual copies `PreemptionPolicy`, `Description`, annotations, labels.
  - The selector matches everything in `constants.SystemPriorityClassesAllowList`. That list is not read beyond its first entry, which is `"system-node-critical"` (`constants/constants.go:63-64`).

#### Namespaces (`namespaces/`)
- Syncer code is OSS but the mapper is Pro.
- `excludedAnnotations` are `scheduler.alpha.kubernetes.io/node-selector` and `scheduler.alpha.kubernetes.io/defaultTolerations` (`syncer.go:25-28`).
- Host labels: `ExtraLabels` plus `vcluster.loft.sh/vcluster-name` and `vcluster.loft.sh/vcluster-namespace`. On update also `kubernetes.io/metadata.name = <host name>` (`translate.go:32-47`).
- `EnsureWorkloadServiceAccount` is done in each host namespace (`syncer.go:142-155`).
- Imported host namespaces get annotation `vcluster.loft.sh/object-imported: "true"` and are never deleted when the virtual object is gone (`syncer.go:108-140`).

#### Nodes
- Real (`nodes/syncer.go`, `translate.go`):
  - `shouldSync` is true if the node matches `selector.all` or the selector labels. Otherwise it is true only if a pod needs it (357-395).
  - `isNodeNeededByPod` excludes pods owned by DaemonSets.
  - Virtual node is created with host labels and annotations, then requeued (325-355).
  - Status: host status, unless `useFakeKubelets`.
    - Then `DaemonEndpoints.KubeletEndpoint.Port = constants.KubeletPort` (`int32(10250)`).
    - Addresses become `GetNodeHost(name)` (`<name with . replaced by ->.nodes.vcluster.com`), plus an IP if `byIP`.
  - With a virtual scheduler, allocatable is host allocatable minus requests of non-vCluster pods, and `pods` minus the count (166-257).
  - `clearImageStatus` blanks images.
  - Labels and annotations are merged with the managed-keys logic (`ApplyMetadata`). `vcluster.loft.sh/original-taints`, `management.cattle.io/pod-requests` and `pod-limits` are excluded.
  - Taints are merged, and the virtual-only `node.kubernetes.io/not-ready` is dropped unless the host has it (26-118).
  - A node whose name equals `$NODE_NAME` gets `cluster-autoscaler.kubernetes.io/scale-down-disabled: "true"` (110-112).
  - The syncer always sets `MarkerLabel=VClusterName` on the virtual node (`syncer.go:317-320`).
  - Tests: `translate_test.go:24-260`, `syncer_test.go:66-290`.
- Fake (`fake_syncer.go`):
  - A fake node is created for a node a pod references. It is deleted when not needed.
  - Constants:
    - `FakeNodesVersion = "v1.19.1"` (line 29).
    - Labels include `"vcluster.loft.sh/fake-node": "true"` and `kubernetes.io/hostname = SafeConcatName("fake", name)` (160-166).
    - Capacity and allocatable: cpu 16, memory 32Gi, ephemeral-storage 100Gi, pods 110, hugepages 0 (181-197).
    - Four conditions: MemoryPressure False, DiskPressure False, PIDPressure False, Ready True.
    - `OSImage: "Fake Kubernetes Image"`.
  - Tests: `fake_syncer_test.go:147-186`.

#### Events (`events/`)
- FromHost only. `SyncToHost` is a no-op (`syncer.go:58-61`).
- Create: virtual copy with metadata reset, the involved object translated, name rewritten, and the message string replaced (`events/translate.go:14-49`).
  - `involvedObject` namespace, name, UID and RV come from the virtual object.
  - Message replacement: `ns/name` first, then bare `name`.
- Accepted kinds (`mappings/resources/events.go:22-28`) are Pod, Service, `"Endpoint"` (not "Endpoints"), Secret and ConfigMap.
- Force-sync: annotation `vcluster.loft.sh/force-sync: "true"` on an unmatched event creates it in virtual namespace `default`, with an empty involved object apart from the namespace (`translate.go:60-75`, `events.go:20`).
- Creation is skipped if the virtual namespace is missing or terminating (`syncer.go:99-110`).
- Tests: `events/syncer_test.go:79-123`.

#### CSI
- CSIDriver: name identity, `Spec` copied from host (`csidrivers/syncer.go:49-78`).
- CSINode: only synced if a virtual node of that name exists. Spec copied, marker set (`csinodes/syncer.go:53-110`).
- CSIStorageCapacity:
  - Virtual name is `SafeConcatName(name, "x", ns)` in `kube-system`.
  - Skipped when the storage class has no virtual mapping, or no synced node matches the topology.
  - Virtual annotations and labels are produced with `HostAnnotations(pObj, vObj)` and `HostLabels(pObj, vObj)`. The roles are reversed here (`csistoragecapacities/translate.go:62-88`).
  - Watches all host namespaces through a separate cache (`syncer.go:111-143`).

#### RuntimeClasses
- Selector-gated import. The virtual object copies `Handler`, `Overhead`, `Scheduling` and uses `VirtualAnnotations`/`VirtualLabels` (`runtimeclasses/syncer.go:51-98`).

#### VolumeSnapshots
- VS: `Spec.Source.PersistentVolumeClaimName` is translated, and `VolumeSnapshotContentName` is mapped through the VSC mapper (needs the virtual VSC to exist). The `skip-translate` annotation copies `Source` unchanged. `VolumeSnapshotClassName` is copied (`volumesnapshots/translate.go:15-43`).
- VS update copies host finalizers and status to virtual. `Spec.VolumeSnapshotClassName` goes virtual to host (`volumesnapshots/syncer.go:162-173`).
- VSC: `VolumeSnapshotRef` is translated to the host VS name and namespace (`volumesnapshotcontents/translate.go:14-22`).
  - Backward creation sets annotation `vcluster.loft.sh/host-volumesnapshotcontent`.
  - Finalizer `vcluster.loft.sh/physical-volumesnapshotcontent-gc` (`volumesnapshotcontents/syncer.go:27`).
  - A virtual VSC with the host annotation is never created on host. It is deleted (`syncer.go:83-92`).
- VSClass: fromHost copy of `Driver`, `Parameters`, `DeletionPolicy` (`volumesnapshotclasses/syncer.go:86-91`).

#### Gateway API
- Imported Gateways (`gateways/syncer.go`):
  - A host Gateway is imported when `mappings.byName` has an exact key, or a `ns/*` key and the selector matches (334-350).
  - The mirror has label `vcluster.loft.sh/imported-gateway: "true"`, annotation `vcluster.loft.sh/managed-by: "vcluster"`, and optionally `vcluster.loft.sh/source-gateway` (25-28, 256-277).
  - `Infrastructure` is cleared when `sanitize.infrastructure` is on (default true).
  - Listener `certificateRefs` are cleared when `sanitize.certificateRefs` is on (default true). A `Terminate` listener then gets TLS option `vcluster.loft.sh/certificate-refs-sanitized: "true"` (279-302).
  - Status addresses are dropped unless `status.exposeAddresses` (304-310).
- Tenant Gateways (`NewToHost`):
  - Sync requires the GatewayClass to exist in the virtual cluster, and the name not to be reserved by or colliding with an imported or unmanaged host Gateway (154-191).
  - In single-namespace mode, `allowedRoutes.namespaces.from` of `All` or `Selector` becomes `Same` and the selector is nil (`gateways/translate.go:54-68`).
  - Certificate refs are authorized, then translated (26-48).
- Routes (`httproutes`, `tlsroutes`, `gatewayroutes/translate/translate.go`):
  - `ParentRefs`, `BackendRefs`, filters (`RequestMirror`, `ExternalAuth`) and policy target refs are authorized (`gatewayapi/authz`) and then translated.
  - Host objects must exist and be managed (`ensureManagedHostObject`, 293-327).
  - Annotations `vcluster.loft.sh/preserve-host-rule` and `vcluster.loft.sh/preserve-request-mirror-filters` keep host-added rules or mirror filters (`httproutes/translate.go:137-196`; `constants/annotation.go:14-18`).
- Warning events for denied refs: reason `RefNotPermitted` with `Gateway API reference not permitted: %v`; reason `UnsupportedReference` with `Gateway API reference kind is not supported and will not be synced to the host: %v` (`gatewaysync.go:149-158`).
- ReferenceGrant: `from[].namespace` goes through `HostNamespace`, `to[].name` through the matching mapper (`referencegrants/translate.go:32-47`).
- BackendTLSPolicy: `TargetRefs` and `CACertificateRefs` are translated; status ancestors are mapped back (`backendtlspolicies/translate.go:25-59`).
- GatewayClass: fromHost, selector-gated, `ParametersRef = nil` (`gatewayclasses/syncer.go:135-141`).
- Not read in depth: `gatewayapi/authz/authz.go` beyond signatures, `gatewayroutes/translate/policy.go`, `errors.go`, `translate_test.go`, `gateways/syncer_test.go`, `httproutes/policy_test.go`.

### F6. Test-derived concrete examples
Already quoted inline above. Index of table-driven suites an implementer should lift into laws:
- Names and labels: `pkg/util/translate/translate_test.go:23-225`, `labels_test.go:13-81`.
- Mapper: `pkg/mappings/generic/mapper_test.go:23-359`, `pkg/mappings/resources/configmaps_test.go:10-53`, `secrets_test.go:11-76`.
- From-host name matching: `pkg/syncer/translator/from_config_translator_test.go:11-185`.
- Pods: `pods/syncer_test.go:51-300`, `302-697`, `699-923`; `pods/syncer_conflict_test.go`; `pods/translate/translator_test.go:29-1046`; `pods/translate/diff_test.go:23-537`; `pods/translate/hostpath_test.go`. Bodies of `syncer_conflict_test.go`, `hostpath_test.go` and the resize and ObservedGeneration tests in `diff_test.go` were not read.
- Other syncers: `services/syncer_test.go`, `endpoints/syncer_test.go`, `endpointslices/syncer_test.go`, `persistentvolumeclaims/syncer_test.go`, `persistentvolumes/syncer_test.go` and `fake_syncer_test.go`, `storageclasses/*_test.go`, `ingresses/syncer_test.go`, `networkpolicies/syncer_test.go`, `poddisruptionbudgets/syncer_test.go`, `events/syncer_test.go`, `nodes/*_test.go`.
- Not read: `configmaps/to_host_syncer_test.go`, `secrets/to_host_syncer_test.go`, `priorityclasses/syncer_test.go`, `serviceaccounts/syncer_test.go`, `csi*/syncer_test.go`, `runtimeclasses/syncer_test.go`, `ingressclasses/syncer_test.go`, `gatewayclasses/syncer_test.go`, `pkg/syncer/syncer_test.go`, `pkg/syncer/from_host_syncer_test.go`, `pkg/mappings/store/store_test.go`.
- Test harness constants: target namespace `test`, current namespace `vcluster`, vCluster name `vcluster`, service name `vcluster` (`pkg/util/testing/config.go:13-16`). `FakeClientResourceVersion = "999"` (`pkg/syncer/testing/testing.go:23`). Many suites do not set `translate.VClusterName`, so they run with `"suffix"`.

### F7. Conformance profile (`test/conformanceValues.yaml`)

How it is used:
- `devspace.yaml:137-147`, profile `test-conformance`, adds only `${CONFORMANCE_VALUES}` as a Helm values file.
  - It does not add `test/commonValues.yaml`. So `useSecretsForSATokens` stays at the chart default false in this profile.
  - `commonValues.yaml:2-4` sets it true, but only the `test-k8s` and `test-pro` profiles load it (`devspace.yaml:118-135`).
- Running the suite is `just run-conformance`, which calls `sonobuoy run --mode={{mode}} --level=debug` (`Justfile:170-175`).
  - `Justfile:173` references `./conformance/v1.31/vcluster.yaml`, which does not exist in the repo (`ls conformance` fails).
  - The test list that sonobuoy executes is not in the repo. Which upstream tests exercise which syncer is not verified.

Settings and their effect:
- `controlPlane.advanced.virtualScheduler.enabled: true` (lines 2-4):
  - `IsVirtualSchedulerEnabled` is true (`config/config.go:1060-1062`).
  - Pod syncer: pods without `NodeName` are not created on host (`pods/syncer.go:245-250`).
  - Affinity, topology spread and node selector are cleared on host pods (`translator.go:424-427`).
  - Node allocatable is recalculated (`nodes/translate.go:165-257`).
  - Nodes sync becomes mandatory (`validation.go:125-127`).
  - CSINodes "auto" becomes "true", since PVC sync is on (`validation.go:63-77`).
- `sync.fromHost.nodes.enabled: true` and `selector.all: true` (43-46): real node syncer, all nodes synced.
- `networking.advanced.proxyKubelets.byHostname: false` and `byIP: false` (31-35): node addresses and kubelet endpoint are not rewritten.
- `sync.toHost.persistentVolumes.enabled: true` (48-49): real PV syncer, not the fake one.
- `sync.toHost.priorityClasses.enabled: true` (50-51): priority class names become `HostNameCluster`, priority capped.
- `sync.toHost.storageClasses.enabled: true` (52-53): PVC storage class names become `HostNameCluster`. FromHost storage classes stay "auto", so the host storage class syncer is not created (`register.go:74`).
- `sync.fromHost.csiDrivers` and `csiStorageCapacities` are false (39-42).
- The K8s distro is `v1.33.1`, with `--service-account-jwks-uri=https://kubernetes.default.svc.cluster.local/openid/v1/jwks` (13-19). Embedded etcd 3.6.4-0 (6-11). `DEBUG=true` (27-28).

Conformance critical path, derived from the profile plus chart defaults, with registration at `register.go:53-87`:
- Active syncers:
  1. pods
  2. services
  3. endpoints
  4. endpointslices
  5. configmaps toHost
  6. secrets toHost
  7. persistentvolumeclaims
  8. persistentvolumes real
  9. storageclasses toHost
  10. priorityclasses toHost
  11. nodes real
  12. events fromHost
  13. csinodes
- Active mappers beyond those: namespaces in single-namespace mode, and the `default/kubernetes` special-service sync.
- Not active: ingresses, ingressclasses, networkpolicies, PDBs, serviceaccounts, volumesnapshot*, gateway API, csidrivers, csistoragecapacities, runtimeclasses, fromHost configmaps, secrets and priorityclasses.
- Of the four network and storage helpers, `endpoints`, `endpointslices` and `services` rely on the `default/kubernetes` special-casing in mappers and syncers.

## Contradictions

1. `pkg/mappings/resources/events.go:25` lists `corev1.SchemeGroupVersion.WithKind("Endpoint")`. The real kind is `Endpoints`. Events for Endpoints objects can never match `AcceptedKinds`.
2. `endpointslices/translate.go:47-49` builds the service-name label by plain concatenation. `SafeConcatName` is not used, so names over 63 chars are not truncated. Every other host name uses `SafeConcatName`.
3. `chart/values.yaml:296` says volumeSnapshotClasses "created within the virtual cluster should get synced to the host cluster". The code is from-host only (`volumesnapshotclasses/syncer.go:63-73`, mapper at `mappings/resources/volumesnapshotclasses.go:20-22`).
4. `chart/values.yaml:263` describes `syncBackChanges` as syncing node labels and taints to host. The nodes syncer always merges virtual labels and taints into the virtual node with `translate.ApplyMetadata` (`nodes/translate.go:30`). The flag only gates an HTTP filter at `pkg/server/server.go:160`. What that filter does is not verified.
5. `gateways/syncer.go:26` defines an annotation `ManagedByAnnotation = "vcluster.loft.sh/managed-by"`. That is the same string as the label `MarkerLabel` (`types.go:22`).
6. Pod host annotation keys come in two families: `vcluster.loft.sh/name`, `/namespace`, `/uid` from `pods/translate/translator.go:40-43`, and `vcluster.loft.sh/object-*` from `types.go`. Both are written on every host pod (`pods/syncer_test.go:70-79`). The first set is for downward API field refs only.
7. `Justfile:173` points at a nonexistent file, `conformance/v1.31/vcluster.yaml`.
8. CSIStorageCapacity writes `HostAnnotations(pObj, vObj)` and `HostLabels(pObj, vObj)` onto the virtual object (`csistoragecapacities/translate.go:81-82`). The virtual object therefore carries host-direction bookkeeping annotations. That is the opposite of other from-host syncers.
9. `nodes.go` and `persistentvolumes.go` registration is unconditional (`register.go:86-87`). The chart key for nodes says "If this is disabled, vCluster will create fake nodes instead" (`values.yaml:261`). Consistent, but PV has no such text.
10. `pods/syncer.go:293` dereferences `*event.Virtual.DeletionGracePeriodSeconds` and `*event.Host.DeletionGracePeriodSeconds` with no nil check. Same pattern in `persistentvolumeclaims/syncer.go:129` and `volumesnapshots/syncer.go:94`.

## Decisions

| ID | Choice | What it changes | Recommendation |
|---|---|---|---|
| D1 Namespace mode | A: single-namespace only. B: also model multi-namespace as an abstract translator with no laws. C: obtain the Pro source | A is fully specifiable from this repo. B adds interface surface but no testable rules. C needs access outside this repo | A. Keep the translator as a parameter so B can be added later |
| D2 Name translation | A: pure functions only. B: also the mapping store with references and GC | ConfigMap and Secret create and delete depend on store references (`to_host_syncer.go:154-171`). Without B they cannot be specified | B, built on A |
| D3 Update model | A: `Sync` as a pure function of four snapshots, with the old-object cache. B: state-only laws | Many rules diff old against new (`CopyBidirectional`, `mergeMaps`, `MergeBidirectional`) | A |
| D4 Pro features | A: no-op, error on non-empty patches. B: omit | The error text is user visible | A |
| D5 Order of work | A: conformance path first. B: all syncers equally | F7 lists 13 syncers. Gateway API and snapshots are large | A |
| D6 Oddities | A: encode as-is. B: fix | Contradictions 1, 2, 8, 10 | A, flagged as known quirks |
| D7 Conformance list | A: derive from values only. B: fetch the upstream sonobuoy list | The repo has no list | A now |
| D8 Fake nodes and PVs | A: model the fake syncers, which are the defaults. B: skip | Defaults are `nodes.enabled=false` and `persistentVolumes.enabled=false` | A |

## Unchanged

Not read or not touched by the rules above:
- `pkg/server` filters, including `WithNodeChanges` and the fake kubelet.
- `pkg/coredns` and the CoreDNS controller, and `k8sdefaultendpoint`.
- `networking.replicateServices`, `servicesync` and the pod security controller (`pkg/controllers/register.go:106-200`).
- `pkg/mappings/store/backend_etcd.go`, snapshot and restore controllers.
- Plugin hooks and `pkg/util/pluginhookclient`.
- Custom resource syncing: `sync.toHost.customResources` and `sync.fromHost.customResources`.
- `pkg/patcher/apply.go:166-511`, the Apply and patch-logging paths.
- Private nodes mode. `pkg/controllers/register.go:57-59` returns before any syncer is registered.
- Pro namespace sync, importer, translate patches, hybrid scheduling and Istio internals.

## Candidate work items

Code locations the Bend rewrite must mirror, grouped by decision, with nearby tests. Where I name no test, I did not find one.

Shared base, needed for every option:
- `pkg/util/translate/translate.go:154-218`, `262-335`. Tests: `translate_test.go`, `labels_test.go`.
- `pkg/util/translate/labels.go:14-103`, `193-207`, `228-381`. Tests: `translate_test.go:23-225`.
- `pkg/util/translate/single_namespace.go:35-171`. Tests: `mapper_test.go:313-359`.
- `pkg/util/translate/types.go:10-37`.
- `pkg/syncer/syncer.go:128-265`. Test: `pkg/syncer/syncer_test.go`, not read.
- `pkg/patcher/sync.go:14-91`. Test: `pkg/patcher/patcher_test.go`, `apply_test.go`, not read.

D1 A:
- `pkg/mappings/resources/namespaces.go:13-45`.
- `pkg/controllers/resources/namespaces/syncer.go`, optional.

D2 B:
- `pkg/mappings/generic/recorder.go:170-257`. Tests: `recorder_test.go`, not read.
- `pkg/mappings/generic/mapper.go:84-290`. Tests: `mapper_test.go:23-359`.
- `pkg/mappings/store/store.go:100-198`, `372-572`, `650-661`. Test: `store_test.go`, not read.
- `pkg/mappings/resources/configmaps.go:107-206`, `secrets.go:176-462`. Tests: `configmaps_test.go`, `secrets_test.go`.

D3 A:
- `pkg/syncer/synccontext/events.go:31`.
- `pkg/patcher/patcher.go:44-228`. Test: `pkg/patcher/patcher_test.go`.

D5 A, conformance path syncers:
- Pods: `pods/syncer.go:180-451`, `translate/translator.go:207-994`, `translate/diff.go`, `translate/hosts.go`, `token/sa_token_secret.go`. Tests: `pods/syncer_test.go`, `translator_test.go`, `diff_test.go`.
- Services, endpoints, endpointslices: `services/syncer.go`, `translate.go`, `specialservices/service_syncer.go`, `endpoints/*`, `endpointslices/*`. Tests: `services/syncer_test.go`, `endpoints/syncer_test.go`, `endpointslices/syncer_test.go`.
- ConfigMaps and Secrets to host: `configmaps/to_host_syncer.go`, `secrets/to_host_syncer.go`. Tests: `configmaps/to_host_syncer_test.go`, `secrets/to_host_syncer_test.go`, not read.
- PVC, PV: `persistentvolumeclaims/*`, `persistentvolumes/syncer.go`, `translate.go`. Tests: `persistentvolumeclaims/syncer_test.go`, `persistentvolumes/syncer_test.go`.
- StorageClasses and PriorityClasses to host: `storageclasses/syncer.go`, `priorityclasses/*`. Tests: `storageclasses/syncer_test.go`, `priorityclasses/syncer_test.go`.
- Nodes real: `nodes/syncer.go`, `translate.go`. Tests: `nodes/translate_test.go`, `nodes/syncer_test.go`.
- Events: `events/*`, `mappings/resources/events.go`. Test: `events/syncer_test.go`.
- CSINodes: `csinodes/syncer.go`. Test: `csinodes/syncer_test.go`, not read.
- Config validation: `pkg/config/validation.go:44-140`.

D5 A, later tiers:
- Everything else in F4: ingress, ingressclass, netpol, PDB, serviceaccounts, volumesnapshots, runtimeclasses, CSI drivers and capacities, gateway API.

D6 A, quirks to encode:
- `mappings/resources/events.go:22-28`.
- `endpointslices/translate.go:47-49`.
- `csistoragecapacities/translate.go:81-82`.
- `pods/syncer.go:293`, `persistentvolumeclaims/syncer.go:129`, `volumesnapshots/syncer.go:94`.

D8 A:
- `persistentvolumes/fake_syncer.go:66-184`. Tests: `fake_syncer_test.go:88-127`.
- `nodes/fake_syncer.go:68-286`. Tests: `fake_syncer_test.go:147-186`.

## Links

Local sources only. No external sites or GitHub issues were used.
- `/home/node/task/CLAUDE.md`
- `/home/node/task/chart/values.yaml`
- `/home/node/task/test/conformanceValues.yaml`
- `/home/node/task/test/commonValues.yaml`
- `/home/node/task/devspace.yaml`
- `/home/node/task/Justfile`
- `/home/node/task/pkg/util/translate/`
- `/home/node/task/pkg/mappings/`
- `/home/node/task/pkg/syncer/`
- `/home/node/task/pkg/patcher/`
- `/home/node/task/pkg/controllers/resources/`
- `/home/node/task/pkg/pro/`
- `/home/node/task/pkg/config/validation.go`
- `/home/node/task/pkg/specialservices/`
- `/home/node/task/pkg/constants/`