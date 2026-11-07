# Classic syncer runtime

`host/syncer.bend` is vcluster's syncer pod for classic mode. The guest
binary runs it as `vk8s-init syncer --host-kubeconfig F --host-namespace NS
--name VC --service-cidr CIDR [--kubeconfig VIRTUAL]` (`host/init.bend`
dispatches on `argv[1]`). `Plan.classic` starts it as a daemon when the
kernel command line carries `VK8S_MODE=classic`. `Plan.boot` is unchanged.

## How it runs (architect decisions 1 and 2)

- It uses bend-kube-runtime@0.4.0.0 (hash
  `0xd9e5cff93d88385a2d6e80af4f4859e0`) through its lower-level modules.
  It does not use `Kube.control`. Each resource has one watcher driver
  per cluster (`R.Ctl.watch.subs`), and all drivers feed one inbox:
  - virtual: all namespaces;
  - host: the host namespace, label `vcluster.loft.sh/managed-by=<vc>`;
  - virtual pods: only for the ConfigMap and Secret references.
- The loop owns one `St.Store` per watch and one `Q.Queue` of virtual
  keys (`<kind>|<namespace>/<name>`).
  - A host object queues the key that its `object-name` and
    `object-namespace` annotations name.
  - Deletions queue their key.
  - At a relist's `InitDone`, the objects about to drop queue their
    keys. They are read from the store before the swap.
  - A pod event queues the ConfigMaps and Secrets that the pod refers to.
- No reconcile starts before every store has listed.
- Reconciles run one at a time. Each reconcile:
  1. reads both stores and the key's snapshots from its last successful
     reconcile (the old objects);
  2. calls `Runtime.step`;
  3. makes the ordered writes (host deletes, host writes, virtual
     deletes, virtual writes) and stops at the first error. A 404 on a
     delete counts as done.
  The queue's backoff and timers handle `Retry` and requeues.
- One Lease, `kube-system/vcluster-syncer-<vc>` in the virtual cluster,
  gates all of this. Only the leader starts the watches. Losing the Lease
  exits the process, which stops both clusters' drivers. SIGTERM releases
  the Lease and exits.
- On start, the leader creates the host namespace if it is missing.
- The pure translators keep bend-kube-runtime@0.2.0.0 JSON. Objects cross
  that boundary as JSON text (`Sync.to2`, `Sync.to4`).

Wired kinds (`Runtime.wired`): Services, ConfigMaps and Secrets. Pods
(#9) and endpoints (#10) are not merged yet. Their entries in
`Runtime.defaults` stay unwired until they merge. Nodes, events and
storage are merged, but their adapters are not wired yet.

Known limits of this version:

- `default/kubernetes` is skipped. vcluster's special Service mirrors the
  host Service of the vcluster pod, and a vk8s microVM has none.
- `young` (block-deletion within two minutes) is always false.
- Updates use `replace` without the status subresource. Status writes
  come with the pod adapter.
- The drain on SIGTERM does not wait for a running write before it
  releases the Lease.

## Guest packaging gap

The guest's `/sbin/vk8s-init` is a static musl binary
(`scripts/guest/build.sh`). bend-kube loads OpenSSL with `dlopen`, which a
static musl binary cannot do. Thus the syncer runs natively (envtest),
but not yet in the guest. The image needs a dynamic glibc build of the
syncer and the `libssl3` package. This change does not change the image.

## Envtest

`tests/syncer_envtest.sh` (CI job `syncer-envtest`) downloads etcd and the
official `kube-apiserver` and `kubectl` for the machine's architecture. It
starts a virtual and a host control plane (no kubelets) and builds
`host/init.bend` natively. Then it runs two syncer replicas and checks:

- the Lease holder, and that the second replica stays passive;
- that the syncer creates the host namespace;
- the Service, the referenced ConfigMap and the referenced Secret under
  `name-x-namespace-x-vc`, with the managed-by label and the object
  annotations;
- that an unreferenced ConfigMap stays virtual;
- that deletes propagate both ways;
- that the standby takes over after SIGTERM to the leader.

The Pod checks print SKIP until #9 merges. Run it on Linux with bend,
clang, openssl and curl:

    tests/syncer_envtest.sh            # KEEP=1 keeps logs; K8S, ETCD pick versions

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

## Verification and remaining work

The factory sandbox forbids local builds, so CI is the oracle. It runs
`scripts/check.sh` (typing, tests, and the host programs, which now
include `host/syncer.bend` through `host/init.bend`), the runtime
verdict, and `syncer-envtest`. No `laws/done/runtime` marker is claimed
yet.

Remaining work:

1. Wire the Pod adapter (status back to the virtual Pod) when #9 merges,
   and endpoints when #10 merges.
2. Wire the merged nodes, events and storage translators. Real nodes and
   host Events need their own watch filters, not the managed-by label.
3. Fix the guest packaging gap above.
4. Add the `laws/done/runtime` marker once CI proves every runtime law.
