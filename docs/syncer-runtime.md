# Classic syncer runtime: implementation boundary

This branch adds pure runtime policy and snapshot dispatch. It does not
start a working guest syncer. `host/syncer.bend`, argument dispatch in
`host/init.bend`, and `tests/syncer_envtest.sh` are still required.

## Implemented

`src/sync/runtime.bend` uses the merged translators' `Outcome` and `Write`
types. It supplies:

- The default enabled resource set, in conformance-first order. These are
  resource IDs, not upstream controller log names. This is not a parser
  for config overrides, nor a list of implemented IO controllers.
- Generic namespaced host names, the managed-by selector, and virtual keys
  read from annotations. Special and cluster-scoped resources retain
  their existing translator mappings.
- Stable write ordering: host deletes, other host writes, virtual deletes,
  other virtual writes. Two balanced parallel scans build each half.
- Requeue conversion with overflow protection. `NoRequeue` and
  `RequeueNow` remain distinct in `Outcome` even though both delays are 0.
- Service dispatch through `Core.decide`, including the special Kubernetes
  Service. ConfigMap, Secret, and ServiceAccount dispatch preserves the
  reference gates and the generic framework's cache and UID rules.

`Plan.classic` is separate from `Plan.boot`. It starts the backing store,
API server, controller manager, and then the syncer daemon. It omits
kubelet, containerd, flannel, kube-proxy, and the local scheduler. The
existing entry point does not select this plan yet: starting the daemon
before command dispatch exists would restart guest initialization.

## Required integration decision

The requested two `Kube.control_with` calls per resource cannot by
themselves supply the required lifecycle with bend-kube v0.3.0:

1. Primary deletes remove the cached object and put its key in the forget
   list, not the reconcile list. Relists also forget missing primaries.
   A queued key with no cached object is discarded without calling the
   callback. See
   [control.bend:254-267](https://github.com/chenhunghan/bend-kube/blob/v0.3.0/src/control.bend#L254)
   and
   [runtime.bend:665-671](https://github.com/chenhunghan/bend-kube/blob/v0.3.0/src/runtime.bend#L665).
   A host deletion could therefore leave its virtual copy unchanged.
   Periodic checks alone also lose the last copy's annotations and the
   distinction between an old deletion and a first observation.
2. Each facade call owns an election and a signal handler. Its election
   uses that call's cluster config; its drain covers only that call's
   managers. The host loop would elect on the host cluster, contrary to
   the required single virtual Lease. Giving each loop a random identity
   would make loops compete with each other. Giving them one identity
   would still leave separate drains and Lease releases. See
   [kube.bend](https://github.com/chenhunghan/bend-kube/blob/v0.3.0/src/kube.bend),
   `Kube.start`, `Kube.elect`, and `Kube.on_signal`.
3. `X.Ctx` holds current caches, not the old snapshots needed for
   bidirectional conflict decisions. A shared per-key cache must retain
   both old objects and update them from successful API responses.

Choose either a bend-kube facade that supports this lifecycle, or a
vk8s adapter over its lower-level watcher and manager APIs. The latter
must use one elector on the virtual config, one drain for all loops, a
serialized per-key snapshot cache, and explicit deletion delivery. It
must stop all writes before releasing the Lease. No change to the sibling
repository was made.

Two watch rules also need resource-specific treatment:

- Real nodes are cluster-scoped and do not carry vk8s's managed-by label.
  Host Events refer to translated objects but need not carry that label
  either. Applying the requested namespace/label filter to every host
  primary would hide both resources.
- The special `default/kubernetes` Service maps to the vcluster's Service
  in the current namespace, which can differ from the target namespace.
  It cannot rely on the generic managed-by watch alone.

The merged pure contracts use `bend-kube-runtime@0.2.0.0` JSON. This branch
keeps those contracts intact. An IO implementation using 0.3.0.0 needs an
explicit JSON boundary conversion or an agreed package migration. The
required IO pin remains 0.3.0.0, hash
`0xd9b268abd125fd306c83ea43554e4f2c`.

## Upstream evidence and law mapping

The reference clone is `loft-sh/vcluster` at `a8ab30ea`. Expected values
come from its source and test fixtures, not from running the Bend code.
No Go build or test ran: the factory instructions prohibit local builds
and tests in this sandbox.

| Source or case | Runtime law |
| --- | --- |
| `chart/values.yaml`; `resources/register.go`; fake node/PV constructors | `runtime.defaults` |
| `services/syncer_test.go`, `testservice` in `testns`, vcluster `suffix` | `runtime.host_name` |
| `translate/types.go`, `single_namespace.go` annotation/label constants | `runtime.selector`, `runtime.virtual_key`, `runtime.unannotated_key` |
| `services/syncer.go`, `Options` | `runtime.service_options` |
| `services/syncer.go`, `SyncToHost`, cached host deleted | `runtime.service_host_deleted` |
| `configmaps/to_host_syncer_test.go`, `Unused config map` | `runtime.configmap_unused` |
| Same file, `Used config map` | `runtime.configmap_used` |
| `secrets/to_host_syncer_test.go`, `Unused secret` | `runtime.secret_unused` |
| Architect's virtual Lease name | `runtime.lease_name` |
| Architect's write order, stable updates | `runtime.host_before_virtual`, both `*_delete_before_create`, both `stable_*_updates`, `empty_order` |
| Requeue representation and ms conversion | `runtime.no_requeue`, `requeue_now`, `one_second`, `delay_saturates`, `keeps_requeue` |
| Empty snapshots | `runtime.service_no_objects` |
| Architect's classic boot contract | `runtime.classic_no_worker`, `runtime.classic_syncer` |

Existing complete upstream case mappings remain in `laws/core.bend`,
`laws/services.bend`, and `laws/configs.bend`. The new adapter laws reuse
their fixtures; they do not replace those specifications. All new laws
are proposals. No law present on main was edited.

Quirks retained: fake nodes and PVs are enabled by default; ConfigMaps and
Secrets copy only when referenced unless `all` is enabled; Services disable
UID deletion; a known host deletion deletes the virtual Service; special
Kubernetes Service handling differs from ordinary Services. The virtual
Lease location and conformance-first startup order are deliberate vk8s
architecture choices, not upstream defaults. Pro behavior stays in the
existing no-op paths.

## Verification and remaining acceptance work

`bend guide` ran with Bend 2.0.40 for Linux ARM64. `git diff --check` passed.
Tests were committed before production code. Local builds, tests and
proof checking did not run under the factory instructions.

CI discovers `tests/runtime.bend` and `tests/classic_plan.bend` through
`scripts/check.sh`. The verdict job also checks `proofs/runtime.bend`
explicitly. No `laws/done/runtime` marker is claimed before both proof
checks pass.

After the IO decision, the remaining work is:

1. Wire both configs, watch loops, snapshot cache, ordered writes and status
   subresource updates under one virtual Lease. Only 404 means absent;
   other GET errors must retry. Stop a write sequence on its first error.
2. Add the four requested flags and `argv[1] == "syncer"` dispatch. Select
   `Plan.classic` only for classic mode.
3. Wire the node/event translators and merged endpoint and Pod work. Keep
   unsupported enabled resources visible as an error, not a silent no-op.
4. Add `tests/syncer_envtest.sh` and a separate CI job. It must provision
   two TLS control planes, run the native syncer, check literal upstream
   names and fields, patch host Pod status, delete from both sides, and
   prove that a second replica does not write while it is a follower.
   ConfigMaps and Secrets in the scenario must be referenced by the Pod,
   because `.all` defaults to false. Also check leader handover and a
   deletion while a watch is disconnected.

There is no runnable envtest command on this branch yet. Do not mark
classic mode complete or use this draft to claim conformance.
