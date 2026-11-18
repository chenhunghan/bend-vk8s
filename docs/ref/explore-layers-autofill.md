# Auto-filling the shared layer store: exploration report

I read the code only. Nothing was built or run. Anything about VM behaviour, macOS timing or bend-vmm is marked not verified.

## Findings

### The store and its fill today

`vk8s layers fill` is the only writer. It is a hidden command and reaches the image cache only over 127.0.0.1.
- `host/layers/fill.bend:248`: `r : Result<&1, &1, U32 & String, Socket> <- TCP.connect("127.0.0.1", port)`
- Layers go one after another, parent first. `host/layers/fill.bend:582`: `U.Lu.then(Unit, U32, Lf.layer(port, reg, repo, root, now, fl), u => Lf.layers(t, ...`
- Every ask lists the whole `layers/` directory to decide "present". `host/layers/fill.bend:573`: `ns : List<String> <- V.Fs.ls(root ++ "/layers")`.
- The compressed blob is also kept in the host OCI blob cache for 72 h. `host/layers/fill.bend:524-525`: `def Lf.blob(...)` then `S.Store.paths(root ++ "/oci", ...`.

### F3 and F5 are already fixed on main (6694748)

The review text is stale on these two points.
- gc reads every node's `layers.held`. `host/layers/fill.bend:805`: `hs : List<&2, String> <- Lf.held(cs, root ++ "/clusters")`. `host/layers/fill.bend:809` passes `F.Fill.hold(ls, hs)` to `Lay.gc.drop`.
- The record is written before the rename. `host/layers/unpack.bend:489`: `# The record first (used at now), then the rename that publishes the layer`.
- A record without its directory is not a layer. `src/layers/fill.bend:491`: `def Fill.present(m: Maybe<&2, Y.Layer>, there: Bool) -> Maybe<&2, Y.Layer>:`.
- Two fills of one layer racing is already safe. The loser of the rename drops its tmp directory. `host/layers/unpack.bend:468`: `# After the rename lost the race (EEXIST): another fill published the layer`.
- A failed fill removes its tmp directory and tar. `host/layers/unpack.bend:510`: `Lu.drop(tmp)`.

### The lock fails instead of waiting

fill and gc share one O_EXCL file for the whole run.
- `host/layers/fill.bend:56-59`: `# fill and gc each hold ~/.vk8s/layers.lock while they run ... A second fill or gc` and `# meanwhile fails and says so.`
- The user sees: `another `vk8s layers fill` or `vk8s layers gc` holds <root>/layers.lock; retry when it ends (remove it if none runs; a lock 60 minutes old is taken over)` (`host/layers/fill.bend:114-115`).
- The busy path returns `Fail{Lf.lock.held(root)}` at `host/layers/fill.bend:120`.
- The lock lasts 3600 s and a fill rewrites its time before each layer (`host/layers/fill.bend:571`).
- So today two fills never run together. A gc and a fill from automatic traffic would collide at random.
- `tests/layers_unpack.sh` has no case for the lock, gc or held (grep found none).

### gc

- It keeps held layers and drops a layer 72 h after its last use. `src/layers/store.bend:233`: `U32.is_ge(now, used) && U32.is_ge((now - used : U32), Lay.ttl())`.
- A held file is written before the Prepare answer is sent. `host/snapshotter.bend:290-293`: `Snapd.save(dirty, c, sn)`, `Snapd.hold(B.Spb.touches(acts), c, sn)`, then `Snapd.answer(...)`.
- A layer that is already present is not touched by a node's Prepare. Only a fill refreshes the record. `host/layers/fill.bend:561`: `U.Lu.then(Unit, Unit, U.Lu.rec.use(root, now, l), ...`.
- So a layer filled just under 72 h ago, whose Prepare lands in the same milliseconds as a gc, can lose its directory under a new lowerdir. This is narrow and not verified on a VM.

### Node side: how a node pulls and what the snapshotter sees

- containerd mirrors four registries through the cache VM at 10.0.2.2:15001-15004, with `pull` only and the upstream as fallback. `src/guest/plan.bend:908`: `[host."http://10.0.2.2:...` with `capabilities = ["pull"]`.
- The CRI image plugin uses the local pull path. `src/guest/plan.bend:701`: `discard_unpacked_layers = true\n  use_local_image_pull = true\n`.
- With the store on, `Plan.snapshotter_word` rewrites `snapshotter = "overlayfs"` to `"bend"`. The share is mounted `ro,nosuid` (`src/guest/plan.bend:2588`).
- containerd's unpacker calls Prepare per layer with label `containerd.io/snapshot.ref` set to the chain ID.
  - containerd v2.2.3 `core/unpack/unpacker.go:395-396`: `snapshotLabels := snapshots.FilterInheritedLabels(desc.Annotations)` and `snapshotLabels[labelSnapshotRef] = chainID`.
  - On AlreadyExists, with `Stat(chainID)` found, the layer is skipped: `return nil, nil` (`unpacker.go:~411-420`).
  - The blob fetch goroutine starts only after the first Prepare that does not return AlreadyExists (`unpacker.go:~452-466`). A layer answered AlreadyExists is never downloaded by the node.
- The snapshotter reads only that one label. `src/layers/snap.bend:406`: `+target : String = Sn.lget(Sn.labels(labels), "containerd.io/snapshot.ref")`.
- A miss is decided by `test -d /mnt/layers/<hex>`. `host/snapshotter.bend:244`: `ok : Bool <- Snapd.bb_ok(["test", "-d", d])`.
- The snapshotter serves one call at a time. `host/snapshotter.bend:20`: `One call at a time, as the overlay snapshotter takes its metadata`. The loop is `Snapd.loop` at `host/snapshotter.bend:345-355`.
- The store is read-only in the guest. A guest cannot fill it, so every fill must run on the host.

### The CRI annotations that would name the image do not arrive today

- containerd can pass the image ref, manifest digest and layer digest to the snapshotter.
  - `pkg/snapshotters/annotations.go` (v2.2.3) defines `containerd.io/snapshot/cri.image-ref`, `cri.manifest-digest`, `cri.layer-digest` and `cri.image-layers`.
  - `AppendInfoHandlerWrapper` sets them on each layer descriptor.
  - `FilterInheritedLabels` lets any `containerd.io/snapshot/` label through to Prepare.
  - The wrapper is added only `if !c.config.DisableSnapshotAnnotations` (`internal/cri/server/images/image_pull.go:267`).
- containerd's default is off. `internal/cri/config/config_unix.go:33`: `DisableSnapshotAnnotations: true,`.
- vk8s does not set it. `src/guest/plan.bend:700-701` has no `disable_snapshot_annotations`, and a grep of `src`, `host` and `scripts` finds none.
- So today a Prepare carries a chain ID and nothing else. The host cannot map a chain ID to a blob.
- With `disable_snapshot_annotations = false`, a Prepare of a missing layer carries the image ref and the image manifest digest, which the host can fetch by digest from the cache.
- Images that `ctr images import` unpacks (pause, add-ons) carry no annotations. They keep the per-node unpack.

### The image cache VM

- It runs upstream distribution's `registry` binary, v3.1.2 (`scripts/guest/fetch-assets.sh:47`). It has no vk8s Bend code on the blob path.
- Its config is `storage.filesystem`, `delete.enabled`, `proxy.remoteurl` and `ttl: 168h`. It has no `notifications` block (`src/guest/plan.bend:921-922`).
- Its data is in `data.img` in the VM. The host reaches it only through the forwards. `src/cli/cli.bend:1354`: `"--forward", Cli.cache_forwards(P.Plan.mirrors()),`.
- The cache's share (`~/.vk8s/cache/share`) holds only `ready` and `usage`. Blob writes are not visible on the host.
- distribution can notify on pulls.
  - `registry/handlers/app.go:784` wraps each repository in `notifications.Listen(...)`.
  - `notifications/listener.go:167-179`: `ServeBlob` calls `BlobPulled(...)`. `ManifestPulled` exists in `notifications/bridge.go:75`.
  - The webhook key syntax is not verified.
- A second concurrent request for a blob that is being cached is not cached.
  - `registry/proxy/proxyblobstore.go:99-103`: `_, ok := inflight[dgst]`, then `// Will return the blob from the remote store directly.`
  - So a host fill that runs at the same time as the node's own fetch downloads the cold layer from the upstream twice.
  - A fill started before the node's fetch avoids this. A Prepare that answers AlreadyExists removes the node's fetch.

### Host processes

- There is precedent for a host-global, long-lived helper that nobody stops: the cache VM. `host/vk8s.bend:652-656`: `Vk8s.cache_start`.
- There is precedent for a per-cluster Bend host process with a TCP listener: `host/idle_proxy.bend:214`: `TCP.listen("127.0.0.1", IdleCfg.port(c))`, started with `I.Proc.start` at `host/vk8s.bend:828`.
- A guest reaches any host loopback port as 10.0.2.2. `docs/ref/review-security-boundary-delta.md:139`: `The VMM maps 10.0.2.2 to the host's `127.0.0.1``. Pods can reach a new fill port too.

### Privacy invariant

- The cache has no credentials. Layers in the store are public images (`docs/ref/review-security-boundary-delta.md:152`).
- The fallback path uses the node's own pull credentials straight to the upstream. A host fill through the cache cannot read a private image, so it fails.
- Failing is the right result. The host must never fill from node-supplied bytes, because every node of every cluster reads the store.

### Failure modes today

- A full disk fails the fill with a write errno and drops the tmp directory.
- There is no free-space check. The review suggested one (`docs/ref/review-security-boundary-delta.md:115`); only the decompression cap exists.
- The store has no size ledger. A record holds no size (`src/layers/fill.bend:46-51`), and `Y.Layer` has no size field.
- The decompression cap is 50 times the blob, at most 64 GiB, and at most 2,000,000 entries (`src/layers/fill.bend:59-62`).

### Cold-pull measurement today

- No script or CI job measures a pull with the store on. `.github/workflows/ci.yml` runs only `tests/layers_unpack.sh` for layers (line 57).
- `scripts/bench/mode-footprint.sh` is the model for a Mac driver: it prints CSV on stdout and progress on stderr.
- `docs/ref/bench-plan.md` scenario 3 defines cache states and scenario 10 is the store on versus off.
- The cache states are: 3, absent from every tool-owned cache; 4, registry cache or layer store warm, node cold; 5, node warm.
- GOAL's gate is `docs/GOAL.md:150-151`: `pull is not slower than off by more than 10%`.
- STATUS evidence for context: nginx:1.27 `layers fill` took 5 s for 7 layers, about 200 MB (`docs/STATUS.md:1935-1938`). Off, a cold pull took 8.54 s and a cache-hit pull 1.94 s (`docs/STATUS.md:608`).

## Contradictions

| Where | Says | Actual |
|---|---|---|
| `docs/ref/review-security-boundary-delta.md:54-70` F3 | no host code reads `layers.held` | `host/layers/fill.bend:751-792` reads it and `:809` applies it |
| `docs/ref/review-security-boundary-delta.md:87-106` F5 | record after rename, no lock | `host/layers/unpack.bend:489-494` writes the record first, and `Lf.locked` exists |
| `docs/GOAL.md:144` | gc `runs safely beside a fill` | true only because a second caller fails (`host/layers/fill.bend:120`). Automatic fills would make gc fail at random |
| `docs/GOAL.md:141-142` | a pull `through the image cache or the node's fallback` fills the store | the fallback pulls with node credentials. The host can read only the cache's public content |
| `src/guest/plan.bend:2413-2421` and `src/layers/snap.bend:406` | the snapshotter can decide on the label | the labels that name the image never arrive, because containerd's default is `DisableSnapshotAnnotations: true` |
| `docs/STATUS.md:1946-1948` | fallback pulls are slow | a layer not in the store is also never filled later. That is the gap this work closes |

## Decisions

### D1. Where the fill triggers

| Option | What it changes | Cost and risk |
|---|---|---|
| A. Cache VM webhook (distribution `notifications`, `ManifestPulled`) to a host receiver | `Plan.registry_config`, a new host listener, a cache VM restart for old caches (`docs/STATUS.md:633-638`) | The node also unpacks its own copy, so a 1-node cluster holds two copies and fails the disk gate. N nodes pulling together all unpack. The host and node fetch the same cold blob and the proxy serves the second one uncached. Misses the fallback path. |
| B. Host tap proxy in front of the cache ports | ports 15001-15004 move, a Bend splice sits on every blob byte | Same duplicate-copy and double-download problems as A. An extra hop on the cold path threatens the 10% gate. Misses the fallback path. |
| C. Guest snapshotter asks the host on Prepare of a missing layer, and waits | containerd config, snapshotter ask effect, host filler service | Node never downloads or unpacks a layer the host filled, so disk is one copy. Covers cache and fallback for public images. The cold pull waits for the host. A blocked snapshotter call stalls all calls unless the wait runs outside the loop. |
| D. Guest records pulled images in a share file and the host fills later | annotations on, snapshotter writes a request file, a host watcher | No effect on cold pull. Same duplicate-copy problem as A. A guest-writable file read by the host needs the O_NOFOLLOW care of F3. |

Recommendation: C. Only C avoids the second copy, and the second copy is what makes disk worse for 1 node (`docs/GOAL.md:147-148`). Keep D's idea as the fallback when the ask fails: the node unpacks and the host can fill on the next request. A and B add a second download for cold layers (`proxyblobstore.go:99-103`) and cannot meet the disk gate.

### D2. Guest to host channel for C

| Option | What it changes | Cost and risk |
|---|---|---|
| 1. TCP line protocol to 10.0.2.2:PORT, served by a host-global daemon `vk8s layers serve` | a fixed port in the plan, a daemon started beside `Vk8s.cache_ensure`, a version-skew rule like the cache VM | Pods can reach it (F9), so every field is untrusted input, validated and capped. Needs a lifecycle with no owner. |
| 2. Same protocol, one server per cluster beside idle-proxy | the port goes in each VM's cmdline, started and stopped with the cluster | More plumbing. Several processes need the per-layer lock of D3. |
| 3. Mailbox files in the guest's share | polling, host writes into a guest-controlled directory | Symlink risk on host writes. Polling latency per layer. |
| 4. vsock | not verified. Needs a bend-vmm change | Sibling session. |

Recommendation: 1. It keeps one fixed port in the pure plan and gives in-process single-flight. D3 still protects against `layers fill` and `layers gc` from the CLI and a second daemon.

### D3. Locking with gc and concurrent fills

| Option | What it changes | Cost and risk |
|---|---|---|
| L1. One writer: the daemon owns the store, and the CLI becomes a client while it runs | `Lf.fill` and `Lf.gc` go through the daemon | Simple in process. Breaks CLI use when the daemon is dead, and a crashed daemon leaves the file lock. |
| L2. Per-layer lock files `<root>/layer-locks/<hex>`, O_EXCL, same 60 minute takeover. A fill waits on a busy layer, then re-checks present. gc try-locks each layer it would drop, re-reads the record and held under the lock, and skips a busy layer | `Lf.layer`, `Lf.gc.run`, `Lf.lock*` get v2 defs. The global lock is no longer taken | Safe across processes and clusters. Dedupes a second node's request. gc and fill no longer fail on each other. |

Recommendation: L2, with the daemon's in-process map as an optimisation. It matches the existing lock text and stale rule.

Optional hardening: gc renames the layer to tmp, re-reads held, then removes or renames back. This narrows the Prepare race above.

### D4. Store full or a fill fails mid-way

| Option | What it changes | Cost and risk |
|---|---|---|
| a. Answer `no` fast and let the node unpack | `Ask.reply` has a `no` case. Snapshotter falls through to `Sn.create` with `have` unchanged | Pull always succeeds. A partial image fill leaves a valid prefix of layers, each independent by chain ID. |
| b. Add a store cap, `VK8S_LAYERS_MAX`, and a free-space check before unpack | record v2 with a size, `Fill.room.v2` | Needs the size at fill time. This is also what GOAL wants for Usage (`docs/GOAL.md:145-146`). `Y.Layer` is a fixed contract, so the size lives in a new type. |

Recommendation: both. A is the failure behaviour. B makes "full" a clean refusal instead of ENOSPC halfway. The cap default is the owner's call. I suggest 20 GiB.

### D5. The guest's wait

- A bounded wait per ask, then answer a local Prepare. The host keeps filling after the guest gives up.
- The wait runs outside the one-call loop. Without that, a slow ask stalls Stat and Mounts for every pod on the node.
- I suggest 60 s, and a first ask per image that asks for all layers after the first miss so the host can fill them in parallel. The owner's call.
- The value matters for the 10% gate. Not verified without a Mac run.

### D6. The compressed blob in `~/.vk8s/oci`

- Keep it, as `fill` does now, or drop it after a successful publish for automatic fills.
- Recommendation: drop it after publish for automatic fills. `docs/ref/bench-plan.md` counts blobs in the disk measure, and the cache VM already holds the compressed copy.

### D7. Record format

- Adding `size` and `inodes` to the record is optional for auto-fill. It is the same change that GOAL needs for Usage.
- Recommendation: do it in the same slice, as `layer-meta 2`. A v1 record parses with the size unknown.

## Unchanged

- `Y.Layer`, `Sn.create`, `S.Op`, `Lay.gc.drop` and the existing `Fill.lock.*` defs. Laws pin them. New work is v2 defs.
- Container mode, native mode and the node host keep the per-node unpack. The gate is `Plan.layers_on` (`src/guest/plan.bend:2527-2528`).
- The cache VM keeps `pull` only and no credentials.
- The share stays `ro,nosuid` and the VMM stays the boundary.
- Out of scope but linked: filtered List (`src/layers/pb.bend:35`) and a Usage that does not run du over 9p (`docs/STATUS.md:1960`). They are separate GOAL items.
- The default flip (`VK8S_LAYERS=0` as opt-out) is not part of this.

## Candidate work items

Each item is one implementer task. Laws are append-only: new v2 defs, new laws under `# Proposed:`, proofs in `proofs/<module>.bend`, markers when all prove.

### W1. Ask protocol and labels (pure)

- New `src/layers/ask.bend`, new `laws/layers_ask.bend`, `proofs/layers_ask.bend`, `tests/layers_ask.bend`, and the `LAWS.bend` and `PROOF.bend` entries.
- Defs:
  - `Ask.of_labels.v2` builds the ask from `containerd.io/snapshot/cri.image-ref`, `cri.manifest-digest`, `cri.layer-digest` and the chain ID.
  - `Ask.render.v2` and `Ask.parse.v2`. `parse` is strict: only the four mirror registries (`src/guest/plan.bend:883-887`), a repo grammar, a 71 character digest, and a bounded line length.
  - `Ask.reply.v2` with `ok present`, `ok published` and `no <short reason>`.
  - `Ask.wait.max.v2` and `Ask.port.v2`.
- Laws:
  - `layers_ask.of_labels_exact`, with values from containerd's `annotations.go`.
  - `layers_ask.none_without_labels`, `layers_ask.none_for_view`, `layers_ask.none_if_present`.
  - `layers_ask.parse_refuses_other_registry`, `layers_ask.parse_refuses_long`, `layers_ask.roundtrip`.
- Nearby tests: `tests/layers_pull.bend` and `laws/layers_pull.bend:126`, which show the `P.Pull.ref` normalisation.

### W2. Per-layer locks, gc plan, parallel split (pure)

- Append v2 defs to `src/layers/fill.bend` after the lock section (line 600 on).
- Defs:
  - `Fill.llock.path.v2(root, chain)` for the lock file.
  - `Fill.gc.plan.v2(ls, held, locked, now)`.
  - `Fill.split.v2` for two balanced halves of the layer list.
  - `Fill.present.v2`, which takes a stat result instead of a directory listing.
- Laws in `laws/layers_fill.bend` after line 313:
  - `layers_fill.gc_skips_locked_v2`, `layers_fill.gc_keeps_held_v2` (same cases as the existing F3 laws).
  - `layers_fill.split_balanced_v2` (lengths differ by at most 1, concatenation equals the input).
  - `layers_fill.present_v2_needs_dir`.
- Tests: `tests/layers_fill.bend`.

### W3. Record v2 and the cap (pure)

- Append to `src/layers/fill.bend` near the record defs (lines 311-407).
- Defs: `Fill.rec.render.v2`, `Fill.rec.parse.v2` (accepts `layer-meta 1`), `Fill.cap.v2`, `Fill.room.v2`.
- Laws:
  - `layers_fill.rec_v2_roundtrip`.
  - `layers_fill.rec_v1_parses_v2`.
  - `layers_fill.room_refuses_over_cap`.
- Tests: `tests/layers_fill.bend`, `tests/layers_unpack.sh`.

### W4. Host fill with per-layer locks, parallel layers, optional blob drop

- `host/layers/fill.bend:568-582` (`Lf.layer`, `Lf.layers`), `:147-173` (`Lf.lock`, `Lf.locked`), `:802-824` (`Lf.gc.run`, `Lf.gc`), `:524` (`Lf.blob`).
- `host/layers/unpack.bend:518-535` (`Lu.publish`) for the blob drop and size capture.
- New v2 defs: `Lf.fill.v2`, `Lf.gc.v2`, `Lf.layer.v2`, `Lf.lock.layer`.
- Tests to add in `tests/layers_unpack.sh`:
  - three fills of the same layer at once give one publish and two `present`;
  - a gc during a fill removes nothing the fill uses;
  - a killed fill leaves no layer and no live lock after 60 minutes;
  - a store cap smaller than a layer fails the fill and leaves nothing.
- Depends on W2 and W3.

### W5. The filler daemon

- New `host/layers/serve.bend`. A TCP listener on `127.0.0.1:Ask.port.v2`, one connection per computation as in `host/idle_proxy.bend:131-214`.
- It parses with `Ask.parse.v2`, then runs a fill of the image's layers by manifest digest, bounded by a concurrency cap.
- Wire up `host/vk8s.bend`:
  - a start helper next to `Vk8s.cache_ensure` (`host/vk8s.bend:1825`), run when `VK8S_LAYERS=1`;
  - the hidden `layers serve` subcommand next to `Layers.main` (`host/layers/fill.bend:858`, `host/vk8s.bend:4013-4025`).
- Usage line at `host/layers/fill.bend:831`: `usage: vk8s layers fill IMAGE | vk8s layers gc` becomes a three-way usage.
- Tests: a new `tests/layers_serve.sh` on Linux CI using bash `/dev/tcp`, with a stub registry.
- Depends on W1 and W4.

### W6. Guest config and the snapshotter ask

- `src/guest/plan.bend:2455-2474`: add `Plan.snapshotter_word.v2` and `Plan.containerd_layers.v2`, which add `disable_snapshot_annotations = false` in the CRI images section when the store is on. Put it next to the `snapshotter = "bend"` line, not at the file end.
- Laws in `laws/plan.bend`:
  - `plan.containerd_layers_annotations_v2`;
  - `plan.containerd_config_unchanged_when_off`, which covers container, native and join (`src/standalone/join.bend:1551` stays as is).
- `src/guest/plan.bend:2610-2616`: `Plan.with_layers.v2` uses the new text.
- `host/snapshotter.bend:307-315` (`Snapd.apply`): add the ask before `Snapd.have`. Run the wait outside `Snapd.loop` (`:345-355`) so other calls continue. After the answer, re-probe with `test -d` and pass `have` to `S.Sn.apply` as today.
- Tests: `tests/layers_snap.bend`, `tests/plan.bend`, and the guest-image test `tests/guest_image.sh`.
- Not verifiable in the factory sandbox. A Mac run or a KVM job is needed.
- Depends on W1.

### W7. Evidence jobs

- `scripts/bench/cold-pull.sh`, modeled on `scripts/bench/mode-footprint.sh`, for the Mac. It runs paired on and off, alternating order, with `VK8S_LAYERS=1` and unset.
  - Workload: pinned digests of busybox:1.36 (1 layer), nginx:1.27 (7 layers, about 200 MB), coredns/coredns:1.14.2, and a 3-replica Deployment on 3 nodes.
  - Cold means state 3: `vk8s cache prune`, an empty `~/.vk8s/layers`, `~/.vk8s/layer-refs` and `~/.vk8s/oci`, and a fresh node. State 4 is also run: cache warm, store empty. That one stresses host unpack plus fsync against the guest's own unpack.
  - It records each phase as a monotonic timestamp: apply, `Pulled` event, container started, first HTTP 200.
  - Gate per image: median of paired on over off at most 1.10. Also report p90 and the raw rows. Use at least 5 pairs and declare the noise margin before the runs, as `docs/ref/bench-plan.md` requires.
  - Disk is `du -sk` of `~/.vk8s/layers`, `~/.vk8s/oci`, the cache and the cluster dirs, for 1, 3 and 10 nodes and 2 clusters.
- The filler logs per-phase times: fetch, decompress, unpack, fsync, rename. The likely hot spot is the directory fsync on macOS (`F_FULLFSYNC`).
- A CI job like `lan-throughput` (`.github/workflows/ci.yml:1209`) on amd64 KVM. It covers the pull with the store on, the layer count in `~/.vk8s/layers` without a manual fill, and the node's overlay lowerdir under `/mnt/layers`. It is a regression guard, not the Mac number.
- STATUS items: `docs/STATUS.md:2060` (shared layers on by default), `docs/ref/bench-plan.md` scenario 10.
- Depends on W5 and W6.

### W8. Docs

- `docs/STATUS.md` and `docs/ref/review-security-boundary-delta.md`: note that F3 and F5 are fixed (6694748) and the lock now has a per-layer successor. Fix the table above.
- `docs/GOAL.md:141-144`: say that the fallback fills only what the cache can read.

## Links

- https://github.com/containerd/containerd/blob/v2.2.3/core/unpack/unpacker.go
- https://github.com/containerd/containerd/blob/v2.2.3/pkg/snapshotters/annotations.go
- https://github.com/containerd/containerd/blob/v2.2.3/internal/cri/config/config_unix.go
- https://github.com/containerd/containerd/blob/v2.2.3/internal/cri/server/images/image_pull.go
- https://github.com/containerd/containerd/blob/v2.2.3/core/snapshots/snapshotter.go
- https://github.com/distribution/distribution/blob/v3.1.2/registry/proxy/proxyblobstore.go
- https://github.com/distribution/distribution/blob/v3.1.2/notifications/listener.go
- https://github.com/distribution/distribution/blob/v3.1.2/registry/handlers/app.go
- Repo files cited: `docs/GOAL.md`, `docs/STATUS.md`, `docs/DESIGN.md`, `docs/ref/review-security-boundary-delta.md`, `docs/ref/bench-plan.md`, `host/layers/fill.bend`, `host/layers/unpack.bend`, `host/snapshotter.bend`, `host/idle_proxy.bend`, `host/vk8s.bend`, `src/layers/fill.bend`, `src/layers/store.bend`, `src/layers/snap.bend`, `src/layers/pb.bend`, `src/guest/plan.bend`, `src/cli/cli.bend`, `scripts/bench/mode-footprint.sh`, `.github/workflows/ci.yml`.