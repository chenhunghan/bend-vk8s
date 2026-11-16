## Findings

I found two defects by reading. I did not run Bend or the tests. The bend-kube-runtime source (`Q.Queue`, `St.Store`) is not on this machine, so I did not read it.

I checked the code on the merged branch head, which includes the later commits on `fix/syncer-load`. PR #40 itself changes `host/syncer.bend`, `src/sync/classic.bend`, the tests, the CI workflow and `docs/STATUS.md`. It adds or changes no laws.

**1. Medium. A virtual pod delete releases its ConfigMaps and Secrets at once. vcluster keeps them until the host pod is also gone.**

`host/syncer.bend:564`
```
case W.ODelete{+x}:
  PF{Refs.del(pr, C.Obj.key(x)), ks}
```
The same code queues the old keys, so the ConfigMap reconcile sees "unused".

In vcluster, `removeMapping` is the path that dispatches a pod's references. It is called from `garbageCollectMapping` and `DeleteMapping`.
- `pkg/mappings/store/store.go:688-697`: `removeMapping` dispatches `s.watches[reference.GroupVersionKind]` for each reference.
- `store.go:195-250`: `objectExists` returns true while the virtual object or the host object exists.
- `store.go:106-130`: GC runs only on a periodic interval.

The `DeleteReference` that the PR cites is called only by `pkg/mappings/resources/services.go`. Pod ConfigMap and Secret references are never removed through it.

Failure scenario:
1. `kubectl delete pod p --force --grace-period=0` in the virtual cluster removes the virtual pod at once. The host pod is still terminating.
2. The `ODelete` event drops the references and queues `configmaps|ns/cm`.
3. `Sync.refd` is false, so `Sync.ns_pods` lists the namespace pods and sees no virtual pod.
4. The reconcile deletes the host ConfigMap while the host pod is still running its grace period. The kubelet then reports `configmap not found` for a pod that is still alive.

The old scan had the same flaw, but the PR claims parity with the mappings store, and this is the part of that parity that differs.

Fix: keep a pod's references until its host pod is gone too, by indexing host pods, or by deleting the references when `hpods` drops the matching pod. Also correct the claim in `docs/STATUS.md` ("As vcluster's mappings store does (AddReference, DeleteReference)") and the comment at `src/sync/classic.bend:2290`.

**2. Low to medium. A relist that replaces a pod with different references leaves the old ConfigMaps and Secrets on the host.**

`host/syncer.bend:562-563`
```
case W.OInitApply{+x}:
  PF{Refs.set(pr, C.Obj.key(x), CL.Classic.ref_sig(ks)), ks}
```
`Refs.set` decrements the old counts. It queues only the new object's keys. `Sync.pr_apply` (the `OApply` path, line 554) queues the old references through `pod_event_keys`, so only the relist path has the gap.

Failure scenario:
1. The pods watch breaks and relists. A StatefulSet pod `ss-0` was recreated during the gap with a new revision that mounts `cm-new` instead of `cm-old`.
2. The relist delivers `OInitApply` for `ss-0`.
3. The index now says `cm-old` has no referrers. `cm-old` is never queued.
4. The host copy of `cm-old` stays. The resync does not clean it up: `Classic.missing_refs` (`src/sync/classic.bend:2246`) queues only references whose host copy is missing.
5. The host copy stays until something else touches `cm-old`.

A restart is not affected. The index starts empty and the host ConfigMap watch relists, which queues the old key.

Fix: in the `OInitApply` branch, use `pod_event_keys(Refs.sig(pr, pk), sig, ks)`, as `OApply` does.

## Questions for the author

- Not verified: does `Sync.unpop` match `Q.Queue.pop`? It rebuilds `Q.Queue{Con{key, f}, b, inq, run, d, g, fl, (n - 1), mx}` by position. If `pop` also touches `d`, `g` or `fl`, a popped-then-returned key could lose fairness or its backoff state. No test covers `unpop`. The 64-key limit reaches it on every full batch (fuel 0 with a key popped).
- Not verified: the index has no repair path. The resync comment says it catches "a pod whose event never reached a store", but the resync never reconciles `Refs` with its fresh pod list. A pod that is wrongly in the index keeps its ConfigMaps "used" until the next relist. If a missed delete is possible, which command shows it?
- The tests have no case for `OInitApply`, `OInitDone` (the `Refs.dels` path), duplicate references, or the drain budget. `tests/syncer_load_envtest.sh` never checks that a ConfigMap leaves the host after its last pod is deleted. A test for that and for finding 2 would catch the "unused" side that the index now owns.
- Three new decision helpers, `ref_sig`, `sig_keys` and `pod_event_keys`, have no laws. The `Refs` type and its counting live in `host/syncer.bend`, although `CLAUDE.md` puts pure decisions in `src/`. The expected values in `tests/syncer_refs.bend` come from the author's reading of vcluster, not from vcluster tests. Was that intended?
- `Sync.resync.tick` now flushes the meter on every tick, so the "once a minute" log runs every 30 s. Is that intended? It is not a defect.

Outside this PR: `laws/cli.bend` changed in the same merge (`cli.balloon_flags` and three related laws). It says "Amended 2026-11-15 with the user's approval", but `CLAUDE.md` rule 1 forbids editing existing laws. I did not review it further.

## What was checked and how

- **PR and code read:** `gh pr view 40`, `gh pr diff 40` and its file list, and the review threads (none). `git diff 3b9208d~2 5a4cdef` for `host/syncer.bend` and `src/sync/classic.bend`.
- **Index logic:** `Refs` (`new`, `sig`, `has`, `count`, `down`, `counts`, `set`, `del`, `dels`), `Sync.pr_apply`, `pr_out`, `pr_step`, `fold`, `on_outs`, `refd`, `refs_for` and `reconcile.snap`.
- **Loop logic:** `Sync.loop`, `absorb`, `drain`, `drain_all`, `batch_ms`, `unpop`, `next`, `resync`, `resync.fresh` and `resync.tick`.
- **Reference extraction:** `Classic.pod_keys`, `Runtime.pod_keys`, `Configs.pod_config_maps` and `pod_secrets`, compared with `configMapsFromPod` and `secretNamesFromPod` in vcluster. They match.
- **Tests:** `tests/syncer_refs.bend`, the `tests/syncer_queue.bend` diff, `scripts/check.sh` test discovery, and the assertions and thresholds in `tests/syncer_load_envtest.sh`.
- **vcluster comparison:** a shallow clone of loft-sh/vcluster at `3a0085b6`: `pkg/mappings/store/store.go`, `pkg/mappings/resources/configmaps.go` and `secrets.go`, and `pkg/controllers/resources/configmaps/to_host_syncer.go`.
- **Index counts:** the counts balance, including duplicate keys. A count cannot go below zero, and there is no leak when a pod is deleted.
- **Ordering and the 5 s budget:** I found no starvation. The first key of a drain always runs, and the inbox is folded before every drain.
- **Not covered:** the bend-kube-runtime internals (`Q.Queue`, `St.Store.dropped`, `St.Store` key format), the CI run results, and the Ingress and `useSecretsForSATokens` paths.

## Links

- https://github.com/chenhunghan/bend-vk8s/pull/40
- https://github.com/loft-sh/vcluster/blob/3a0085b6/pkg/mappings/store/store.go
- https://github.com/loft-sh/vcluster/blob/3a0085b6/pkg/mappings/resources/configmaps.go
- https://github.com/loft-sh/vcluster/blob/3a0085b6/pkg/controllers/resources/configmaps/to_host_syncer.go