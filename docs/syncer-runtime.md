# Classic syncer runtime

`host/syncer.bend` is vcluster's syncer pod for classic mode. The guest
program runs it as `vk8s-guest syncer --host-kubeconfig F --host-namespace
NS --name VC --service-cidr CIDR [--kubeconfig VIRTUAL] [--config YAML]`
(`host/init.bend` dispatches on `argv[1]`). `Plan.classic` starts it as a
daemon when the kernel command line carries `VK8S_MODE=classic`.
`Plan.boot` is unchanged.

`--service-cidr` and the virtual kube-apiserver's
`--service-cluster-ip-range` must be the host cluster's service CIDR, as
in vcluster. The host create clears the cluster IP (`Svc.to_host`), the
host allocates one, and `Svc.sync` recreates the virtual service with
that IP. A virtual apiserver with another range rejects the IP with
`422 ... the provided network does not match the current range`, and the
host service is then deleted with the virtual one.

The guest image holds `host/init.bend` twice. `/sbin/vk8s-init` is PID 1,
a static musl binary. `/usr/bin/vk8s-guest` is the same program as a
dynamic glibc binary, with `libssl.so.3` and `libcrypto.so.3` in
`/usr/lib/aarch64-linux-gnu`. The syncer daemon runs `/usr/bin/vk8s-guest`,
because bend-kube-runtime loads OpenSSL with `dlopen`. Its TLS client
(`src/effs/tls.c` at v0.5.1) opens `libcrypto.so.3`, then `libssl.so.3`.
It falls back to `.so.1.1` and `.so`, and `BEND_KUBE_LIBCRYPTO` and
`BEND_KUBE_LIBSSL` override the names. The image's names match the first
choice.

## How it runs (architect decisions 1 and 2)

- It uses bend-kube-runtime@0.5.1.0 (hash
  `0x4c2d28cc22034a4133c2ab77cd30309e`) through its lower-level modules.
  It does not use `Kube.control`. Each resource has one watcher driver
  per cluster (`Sync.watch`, like `R.Ctl.watch.subs`), and all drivers feed one inbox:
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
- No key is popped before every store has listed. `Queue.pop` marks the
  key as running. Popping during startup and then skipping its reconcile
  leaves the one worker occupied forever. `Sync.pop_ready` preserves the
  queue until all initial lists finish.
- `Sync.drive` is the pinned runtime's `Drv.run` loop with two added logs:
  `listed` after each successful list page, and `watching` after each watch
  request opens. Both include the API path. Failures retain the runtime's
  logs. Each driver runs in `IO.spawn`; the loop drains their shared inbox.
  Each request opens its own TLS socket. Configs from kubeconfig have no
  shared connection pool or rate-limit channel.
- The old driver logged `listing` and errors only. A quiet log after
  `listing` did not establish that the request was blocked.
- Reconciles run one at a time. Each reconcile:
  1. reads the virtual and the host object from the API server (a 404
     is an absent object) and the key's snapshots from its last
     successful reconcile (the old objects). It does not read the
     stores: they lag the syncer's own writes. After services `Sync`
     recreates a virtual service, a store read can show it gone while
     the snapshot has it, and `SyncToVirtual` then deletes the host
     service. The stores queue keys and hold the pods for references;
  2. calls `Runtime.step`;
  3. makes the ordered writes (host deletes, host writes, virtual
     deletes, virtual writes) and stops at the first error. A 404 on a
     delete counts as done.
  The queue's backoff and timers handle `Retry` and requeues.
- One Lease, `kube-system/vcluster-syncer-<vc>` in the virtual cluster,
  gates all of this. Its timing is `LOpts.default` (the one
  `Opts.with_election` uses: 15 s, 10 s, 2 s), which `Leader.elect`
  validates at startup. Only the leader starts the watches. Losing the Lease
  exits the process, which stops both clusters' drivers. SIGTERM releases
  the Lease and exits.
- On start, the leader creates the host namespace if it is missing.
- The pure translators keep bend-kube-runtime@0.2.0.0 JSON. Objects cross
  that boundary as JSON text (`Sync.to2`, `Sync.to4`).

Wired kinds (`Runtime.wired`): Services, ConfigMaps, Secrets and
ServiceAccounts. A kind runs only when the vcluster.yaml enables
`sync.toHost.<kind>.enabled`, as `register.go` registers a syncer. The
syncer reads the file that `--config` names, or the chart defaults
(`src/config/vcluster.bend`). By default, Services, ConfigMaps and
Secrets run, and ServiceAccounts do not. A disabled kind is not watched,
and its stores start ready and empty. The syncer logs the enable set at
start.

Pods (#9) merged, and nodes, events and storage are merged, but their
adapters are not wired yet. Endpoints (#10) is not merged.

Known limits of this version:

- `default/kubernetes` is skipped. vcluster's special Service mirrors the
  host Service of the vcluster pod, and a vk8s microVM has none.
- `young` (block-deletion within two minutes) is always false.
- Updates use `replace` without the status subresource. Status writes
  come with the pod adapter.
- The drain on SIGTERM does not wait for a running write before it
  releases the Lease.

## Envtest

`tests/syncer_envtest.sh` (CI job `syncer-envtest`) downloads etcd and the
official `kube-apiserver` and `kubectl` for the machine's architecture. It
starts a virtual and a host control plane (no kubelets) and builds
`host/init.bend` natively. Then it runs two syncer replicas and checks:

- the Lease holder, and that the second replica stays passive;
- that the syncer creates the host namespace;
- the enable set from a vcluster.yaml that also enables service accounts;
- the Service, the referenced ConfigMap, the referenced Secret and the
  ServiceAccount under
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
| `chart/values.yaml` `sync.toHost` enabled keys | `runtime.enabled_defaults` |

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

1. Wire the Pod adapter (#9, merged): its `SInp` needs the namespace
   labels, the services, the DNS IP, service account tokens and the
   virtual node names, and its writes are `Pods.Write`, with a status
   write. Wire endpoints when #10 merges.
2. Wire the merged events, fake nodes and storage (PVCs, fake PVs)
   translators. They read pod and PVC snapshots, so they follow pods.
   Host Events need their own watch filter, not the managed-by label.
3. Add the `laws/done/runtime` marker once CI proves every runtime law
   under `--verdict`.
