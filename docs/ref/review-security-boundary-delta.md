# Security review of the host/guest boundary since 2026-11-07

Read-only review of bend-vk8s `main` at 5d014ca. I cloned bend-vmm at d68fcf9, the commit behind pin 0xee7f0dd7, into /tmp/ref to read the VMM side. I did not build or run anything. Where I could not read the code I say "not verified".

**Status (2026-11-19).** The findings below describe `main` at 5d014ca. Commit 6694748 fixed F3, F5 and F6. The per-layer locks of W2 and W4 (`docs/ref/explore-layers-autofill.md`) later replaced the store-wide lock of the F5 fix. See the notes under F3 and F5 and the Status column of the table in "Contradictions".

## Findings

Ranked by severity. Areas with no finding are listed at the end of this section.

### F1. Medium: native host-node delete and restart act on host state shared with other software

Native mode is opt-in and needs sudo. These actions are not scoped to the cluster's data dir.

- **iptables.**
  - `Vk8s.nat.table` runs `<tool>-save`, drops every line that contains `KUBE-`, `FLANNEL-` or `CNI-` anywhere, and gives the rest to `<tool>-restore`.
  - The restore has no `--noflush`, so each affected table is replaced whole.
  - `host/vk8s.bend:3731`: `+r : Sh <- Vk8s.nat.exec(["sudo", save], "")`
  - `host/vk8s.bend:3721`: `+r : Sh <- Vk8s.nat.exec(["sudo", restore], text)`
  - `src/standalone/native_host.bend:639-640`: `def NHost.ipt_marks() ... ["KUBE-", "FLANNEL-", "CNI-"]`
  - A substring match also removes the chains of podman, nerdctl, containerd-CNI, k3s and microk8s. A rule another tool adds between save and restore is lost.
- **cgroup kill.**
  - Delete writes `1` to the shared `/sys/fs/cgroup/kubepods/cgroup.kill`.
  - `host/vk8s.bend:3680`: `["sudo", "tee", "/sys/fs/cgroup/kubepods/cgroup.kill"]`
  - The same kill runs at every unit start through `NHost.reset`.
  - `src/standalone/native_host.bend:308`: `k=/sys/fs/cgroup/kubepods; if [ -e $k/cgroup.kill ]; then echo 1 > $k/cgroup.kill`
  - Any other kubelet that uses that cgroup loses all its pods.
- **Create guard.** It checks two things at create time only.
  - `host/vk8s.bend:3627`: `grep -r -q -x --include=cluster.env HOST_NODE=1 home/.vk8s/clusters`. It looks in the current user's clusters only.
  - `host/vk8s.bend:3628`: `test -e /sys/fs/cgroup/kubepods`.
  - It does not stop a k3s or kubelet installed later, or another user's cluster.
- **ipsets.** `Netpol.ipset_ours` matches by name prefix `KUBE-SRC-`, `KUBE-DST-` and `kube-router-local-pods`. A k3s kube-router uses the same names.
- **Failure scenario.** A developer runs `vk8s create x --backend native`, then installs k3s. `vk8s delete x`, or a reboot where the unit starts after k3s, kills k3s's pods. Delete also removes its KUBE chains and rewrites the tables.
- **Fix.**
  - Delete only the exact rules vk8s installed, for example `iptables -D` of recorded rules, or restore with `--noflush` and `-X` of vk8s's own chains only.
  - Match chain names exactly, not `contains`.
  - Give vk8s's kubelet its own cgroup parent (`cgroupRoot`) and kill that one.
  - Refuse to start or delete when `kubepods` has pods the unit does not own.

### F2. Medium, not verified: NetworkPolicy and the startup gate cover IPv4 only

- **Gate.** The gate is `iptables-restore` only.
  - `src/guest/netpol.bend:150-156`: `*mangle ... -A VK8S-NETPOL-GATE -s <pod> -j DROP`
  - It has no ip6tables counterpart.
- **kube-router.** `--enable-ipv6` defaults to false (`kube-router/pkg/options/options.go:179` at v2.12.0). `Netpol.args` does not set it (`src/guest/netpol.bend:55-65`). No policy is installed for IPv6.
- **Guest settings.**
  - `src/guest/plan.bend:95` writes `bridge-nf-call-ip6tables`, so same-node bridged IPv6 reaches ip6tables FORWARD, which is empty.
  - `rg disable_ipv6` finds nothing in `src/` or `scripts/`.
  - So a pod may have a link-local fe80:: address on its bridge.
- **Failure scenario.** A pod finds a peer with `ping6 ff02::1%eth0` and connects to a service that listens on `::`, bypassing deny-all. This also works while the gate is closed. I did not test it.
- **Test.** Extend `tests/netpol_e2e.sh` with an fe80:: path on the same node.
- **Fix.**
  - Set `net.ipv6.conf.all.disable_ipv6=1` and `net.ipv6.conf.default.disable_ipv6=1` on nodes. This fits the IPv4-only plan.
  - Or run `--enable-ipv6` with an ip6tables gate.

### F3. Low to Medium: `vk8s layers gc` can delete layers that running nodes use

- **Holders are never filled.**
  - The guest writes the held list to `layers.held` (`src/guest/plan.bend:2445`).
  - Nothing on the host reads it. A search of `host/` and `src/` finds only the writer, `Spb.held`.
  - Holders are never added to a record. `Lay.hold` is only called from laws.
  - `Lf.gc` reads records and `Lay.gc.drop` decides on `hs` and `used`. `hs` is always empty.
  - `src/layers/store.bend:226-228`: `case Nil{}: Lay.expired(used, now)`.
- **Failure scenario.** A layer filled more than 72 hours ago, with pods still running on it, is removed under their overlay lowerdir. Pods then fail with ENOENT or EIO. Only `fill` refreshes `last-use`.
- **Contradictions.**
  - `docs/STATUS.md:1830-1832` says the held file is "for part 1's GC".
  - `src/layers/pb.bend:298` says "it never removes a held layer".
  - Neither is true today.
- **Fix.**
  - Have `gc` read every `~/.vk8s/clusters/*/**/share/layers.held` and treat those layers as held. Read it with `BinFile.read_all`, which uses `O_NOFOLLOW` and a size limit, and parse it strictly. The guest wrote it, so it is untrusted.
  - Or refuse to run while any VM of any cluster runs.
  - Note that a record's `holder <h>` line is not escaped. Reject newlines in holders if the guest's text ever reaches `Fill.rec.render`.
- **Fixed in 6694748.**
  - gc reads every node's `share/layers.held` under `~/.vk8s/clusters` with `BinFile.read_all` (O_NOFOLLOW, 4 MiB at most) and parses it strictly (`Fill.held.parse`).
  - The layers that a file names count as held (`Fill.hold`), so gc keeps them. See the comment at `host/layers/fill.bend:48-55`.
  - The comments in `src/layers/pb.bend` and `docs/STATUS.md` now say what the code does.

### F4. Low to Medium: the share quota counts written bytes only

- **What the VMM counts.**
  - `bend-vmm/src/fs/quota.bend:5-8`: "what the guest's writes may add to the bytes its files hold ... Growing a file by truncate makes it sparse (no disk), so only writes count."
  - `Quota.growth` returns a size for `FsWrite` and `FsWriteRam` only. Files, directories and symlinks add nothing.
- **Failure scenario.** Root in a VM creates millions of empty files or directories in its share, which sits in `~/.vk8s/clusters/<n>`. This bypasses the 1 GiB limit, so ENOSPC never fires. The host runs out of inodes or metadata space.
- **Contradiction.**
  - `docs/STATUS.md:681-684` says F6 is "Fixed" ("Every VM's share has a 1 GiB quota; writes past it fail with ENOSPC").
  - `src/cli/cli.bend:1071-1072` passes `quota=1G`.
  - The claim holds for data bytes only.
- **Fix.**
  - Ask bend-vmm for an inode and directory-entry cap per share. This is a sibling change.
  - Document the limit until then.
- **Related.** The pin raised the fid cap from 4096 to 65536 per share (`bend-vmm d68fcf9`). Memory per fid is bounded by the path length. I did not measure it.

### F5. Low: fill and gc race, and a record can outlive its directory

- **Record written after the rename.**
  - `host/layers/unpack.bend:464-467`: `L.LayerFs.rename_dir(tmp, ...)` then `Lu.placed(...)`.
  - `host/layers/unpack.bend:457-458`: after `fsync_dir` it calls `Lu.rec.use(root, now, l)`.
  - Between the rename and the record, a concurrent `gc` sees a layer directory with no record. `Fill.or` counts that as unused since 1970 (`src/layers/fill.bend:431`).
  - gc then deletes the layer that was just published.
  - The window is a directory fsync, which is long with `F_FULLFSYNC` on macOS.
- **Record without a directory.**
  - gc removes the directory first and the record second (`host/layers/fill.bend:581-583`).
  - A crash between the two leaves a record with no directory.
  - `Lf.layer` then answers "present" from the record alone (`host/layers/fill.bend:332-334`) and never refills.
  - Guests fall back to node-disk unpack. That is slow but safe.
- **Contradiction.**
  - `src/layers/fill.bend:52`: "A fill writes it before the rename and again on every later fill".
  - `host/layers/unpack.bend:31`: "... then the layer's record (Fill.rec)". The code does it after.
- **Fix.**
  - Write the record before the rename. gc already removes a record with no directory.
  - Make "present" also check that `layers/<hex>` exists.
  - Add a lock file between `fill` and `gc`.
- **Fixed in 6694748.**
  - A fill writes the record before the rename that publishes the layer (`src/layers/fill.bend:52-53`).
  - A layer is present only when its record and its directory are both there (`Fill.present`).
  - fill and gc took one store-wide lock, `~/.vk8s/layers.lock`. A second fill or gc failed.
- **Successor: per-layer locks (W2, W4).**
  - Each layer has its own lock, `~/.vk8s/layer-locks/<hex>` (`Fill.llock.path.v2`, `src/layers/fill.bend:694`). A lock one hour old is taken over.
  - A fill waits while another fill holds the lock, then checks present again (`Fill.present.v2`).
  - gc tries the lock of each layer it would remove and skips a busy one. Under the lock it reads the record and every `layers.held` again (`Fill.gc.recheck.v2`).
  - fill and gc no longer fail on each other. `~/.vk8s/layers.lock` is no longer taken (`host/layers/fill.bend:57-65`).

### F6. Low: the unpack has no resource limits

- `host/layers/unpack.bend:237` calls `Z.Unz.file(kind, blob, tar, 0)`. I could not read bend-kube-runtime's `Unz.file`, so I do not know what the last argument limits.
- The tar entry loop is bounded only by `Lu.forever()`, `4294967295` (`host/layers/unpack.bend:81`).
- The entry list is kept in memory (`acc` in `Lu.loop`, `host/layers/unpack.bend:432`).
- **Failure scenario.** A public image with a gzip bomb or tens of millions of entries fills the host disk or memory. The operator ran `vk8s layers fill` on it. The diffID check runs only after the whole decompression (`host/layers/unpack.bend:394-397`). The tmp tar is removed on failure.
- **Fix.**
  - Cap the decompressed size at the layer size times a ratio, or at a fixed limit.
  - Cap the entry count and the host path depth.
  - Check free disk before decompressing.

### F7. Low: the guest's layers mount is not read-only

- `src/guest/plan.bend:2427-2428`: `Mount{"9p", "layers", Plan.layers_dir(), "trans=virtio,version=9p2000.L,msize=524288"}`. There is no `ro`, `nosuid` or `nodev`.
- The real control is in the VMM. `bend-vmm/src/fs/readonly.bend:27-45` lists the operations that cannot change files and refuses all others with EROFS. That is an allowlist.
- A mount `ro` adds defence in depth against a VMM gap. The store is shared by every node of every cluster, so a write would reach all of them.
- A privileged pod can remount, so this is not a boundary on its own.
- **Fix.** Add `ro,nosuid`. `nodev` is not needed for lowerdirs.

### F8. Low, native only: the gate can open on stale rules

- `Netpol.synced` is true when `KUBE-ROUTER-FORWARD` already holds `-j KUBE-NWPLCY-TAIL`.
- On a host, kube-router removes nothing when it stops (`src/guest/netpol.bend:116-117`). `NHost.reset` and the unit restart clean no iptables.
- After a unit restart, `Init.netpol` can see the old chain at its first one-second look. It opens the gate before the new kube-router has synced.
- Impact is small. The old default-deny REJECT rules in the tail chain stay in force, and new pod IPs are not in `kube-router-local-pods`.
- Each start also inserts another `-I FORWARD 1` and `-I INPUT 1` jump (`src/guest/netpol.bend:154-155`). Delete removes them all.
- **Fix.** Clean the `KUBE-ROUTER-*` chains and the gate jumps before the native boot closes the gate. Or open only when the probe changes after the new kube-router starts.

### F9. Info: known or accepted

- **Guest reach to host loopback.**
  - The VMM maps 10.0.2.2 to the host's `127.0.0.1` (`bend-vmm/src/net/addr.bend:3-5`). Every pod with egress reaches any host loopback port.
  - vk8s adds the cache ports 15001-15004 to that set.
  - The `host/layers/fill.bend` client trusts the loopback ports, and a local process could squat on them.
  - Digest checks and the content-addressed chain IDs keep the store consistent, so this is a denial of service at worst.
  - `docs/ref/explore-native-control-plane.md:87` documents the reach.
- **Cache writes.**
  - The cache's `delete.enabled: true` (`src/guest/plan.bend:921`) does not let a client delete or push.
  - distribution's `proxyManifestStore.Delete` and `proxyBlobStore.Put`, `Create` and `Delete` return `ErrUnsupported`.
  - Containerd uses `capabilities = ["pull"]` (`src/guest/plan.bend:908`).
- **RBAC.**
  - `vk8s:network-policy` gives group `system:nodes` get, list and watch on pods, namespaces, nodes, services, networkpolicies and endpointslices (`src/guest/netpol.bend:105-106`).
  - Pods, services, endpoints and nodes were already readable through the Node authorizer. I did not check this against Kubernetes source.
  - Namespaces and NetworkPolicies are new, and low sensitivity.
- **Store contents.** Every node can read every layer in the store, across clusters. The cache has no credentials, so layers are public images.
- **`scripts/native-worker.sh`.**
  - It is a CI helper. It runs a `--privileged` container and `curl -fsSLk '$url' | sh`.
  - `sh -c` strings interpolate `$dns` and `$url`.
  - `down` deletes every `ip rule` for table 177 and the links `vk8s-w0` and `vk8sw0h`, whoever made them.
  - It is not on a product path.
- **Test gap.**
  - `tests/layers_unpack.sh` has no hard link to a symlink target and no entry under a symlink in the host run.
  - Only the pure plan has "symlink escape refused" (`tests/layers_tar.bend:99`).
  - `LayerFs.make` kind 3 relies on `linkat(..., 0)` not following a symlink (`host/layers/effs/layer_fs.c`). A follow would link a host file into the store.

### No finding

- **Unpack, path traversal and links.**
  - Names with `..` or a leading `/` are refused (`src/layers/tar.bend:49-50`, `Tar.path`).
  - An entry under an earlier non-directory or symlink is refused (`Tar.blocked`, `Tar.put.blocked`).
  - A hard link must name an earlier linkable entry, so it cannot be under a symlink (`Tar.link.path`).
  - Every created file is `O_EXCL|O_NOFOLLOW`. `mkdir` and `linkat` use the computed host path. `remove_tree` uses `openat` with `O_NOFOLLOW` and `unlinkat`.
  - Duplicate names, case collisions, non-ASCII names and anything starting `.bend-` get a hashed host name. No tar name can produce `.bend-meta`.
- **Whiteouts and `.bend-meta`.**
  - `.wh.` names are refused when empty, `.` or `..`.
  - Sidecar names and xattr names are percent-encoded. Xattr values are hex (`src/layers/meta.bend:30-40`).
  - A tar cannot inject a record.
  - Xattrs such as `trusted.overlay.*` are only text on the host. The guest sees them as containerd would.
- **Digests before publish.**
  - Blobs are checked for digest and size before they enter the cache (`Lf.blob.verified`).
  - The tar's SHA-256 must equal the diffID (`Lu.diff`).
  - The chain ID is a hash of the diffIDs, so a forged manifest cannot supply content for another image's chain.
- **Guest writes to the store.**
  - The share root is `~/.vk8s/layers` only (`src/cli/cli.bend:1960-1964`). `tmp/` and `layer-refs/` are outside it.
  - The VMM refuses writes on `ro` shares.
  - It walks each component with `openat(O_NOFOLLOW)`, so store symlinks cannot be followed (`bend-vmm/host/hvf.c:4364`).
  - `Share.rel_ok` refuses `.`, `..` and empty names (`bend-vmm/src/fs/contain.bend`).
- **Guest snapshotter.**
  - The socket is mode `384` (0600).
  - Layer paths come from validated 64-hex chain IDs.
  - `du` and `find` take the path as `$1`.
- **`Plan.with_rshared`.**
  - It adds `mount --make-rshared /`, as kind and container mode do (`src/guest/plan.bend:2478`).
  - It only matters for volumes that ask for propagation. Bidirectional needs a privileged container in Kubernetes, and HostToContainer only receives mounts.
  - It does not widen what a hostPath pod sees, which already includes `/share` and `/mnt/layers` by rbind.
  - The step is also added on the cache and control-plane VMs. That is harmless.
- **Native signals.**
  - `Native.safe` allows only pids above 1 and below 2^31 (`src/standalone/native.bend:421`).
  - `NInit.stop_each` and the P.Stop step use it. `NInit.shutdown` signals only its own table (`host/init.bend:1521-1535`).
  - `Sys.term` only counts SIGTERM and SIGINT (`host/effs/sys.c:19-41`). There is no `kill(-1)` in the native path.
  - The VM-only `Init.shutdown` sends `4294967295` (`host/init.bend:586`) and is not reached from native mode.
- **Native writes.**
  - Plan writes are relocated to the data dir, or are the kernel and name files that `Native.machine` drops (`src/standalone/native.bend:224-236`).
  - The unit runs the root-owned copy of the binary in a 0700 dir (`src/standalone/native_host.bend:371,442`).
  - Names pass `Cli.valid_name` before any `sudo rm`.
- **LAN offload.**
  - The receiving code bounds a packet at 65600 bytes and checks `off == got` and `off + n > total`.
  - Pieces come from up to 8 senders in the user's 0700 LAN dir (`bend-vmm/host/hvf.c:5662-5690`).
  - `LAN_WIRE` is checked before a VM starts (`src/cli/lan_wire.bend`).
- **Gate failure paths.**
  - A failed gate step stops the boot before the kubelet (`host/init.bend:496`, "the first failure stops the boot").
  - A missing marker or failed probe leaves the gate closed.
  - kube-router's TAIL jump goes into the same `iptables-restore` as the per-pod chains (`kube-router/pkg/controllers/netpol/npc_iptables.go:724-736` at v2.12.0). `Netpol.synced` is therefore a real first-sync signal.

## Contradictions

| Where | Says | Actual at 5d014ca | Status (2026-11-19) |
|---|---|---|---|
| `src/layers/fill.bend:52` | "A fill writes it before the rename" | `host/layers/unpack.bend:457-467` writes after | Fixed in 6694748: the code writes the record first |
| `docs/STATUS.md:1830-1832`, `src/layers/pb.bend:298` | held layers are kept by gc | no host code reads `layers.held` | Fixed in 6694748: gc reads every `layers.held` (F3) |
| `docs/STATUS.md:681-684` | F6 "Fixed" with a 1 GiB quota | the quota counts written bytes only | Fixed by the bend-vmm pin 0x37f03198 (93d1890): shares get `quota=1G,inodes=100000` (F4) |
| `src/layers/store.bend:20-21` | "the host empties tmp/ at start" | gc removes only tmp entries more than a day old (`Fill.stale`) | Fixed in 6694748: the comment now says what gc does |

## Decisions

| # | Choice | Options | What changes | Recommendation |
|---|---|---|---|---|
| D1 | Native delete and reset scope (F1) | A: exact chains and rules, own cgroup. B: keep, document single-tenant | A edits `NHost.ipt_*`, `Vk8s.nat.table`, `NHost.reset_script` and the kubelet cgroup root, plus laws `native.ipt_clean`. B is docs only | A. B leaves a destructive default. |
| D2 | IPv6 (F2) | A: test first, then disable IPv6 on nodes. B: ip6tables gate and `--enable-ipv6`. C: leave | A adds an e2e check and two sysctls in `Plan.sysctls`. B changes the gate and kube-router args | A, because the plan is IPv4-only. B only if dual-stack is a goal. |
| D3 | gc and holders (F3) | A: gc reads each `layers.held`. B: refuse while any VM runs. C: refresh `last-use` when a node starts | A needs a strict parser and a cluster scan. B is a small check in `Lf.gc`. C needs a host hook | B now, A later. |
| D4 | Record order and lock (F5) | A: write the record first and check the directory. B: add a lock file as well | A moves `Lu.rec.use` before `rename_dir`. B adds a lock in `Lf.fill` and `Lf.gc` | A, plus the doc fix. B if `fill` and `gc` can run together often. |
| D5 | Unpack limits (F6) | A: size, entry and depth caps. B: none | A touches `Lu.tar.run`, `Lu.loop` and `Lu.forever`. It needs a decision on Unz's limit argument | A with caps in `src/layers/` so a law can pin them. |
| D6 | Guest mount flags (F7) | A: `ro,nosuid`. B: none | A changes `Plan.layers_mount` and the plan laws | A. |
| D7 | Quota (F4) | A: ask bend-vmm for an inode cap. B: document | A is a sibling request. B is a docs line in STATUS | A and B now. |
| D8 | Native gate (F8) | A: clean the stale chains at native boot. B: accept | A adds a native pre-step | A, low cost. |

## Unchanged

- The F1 to F4 and F7 fixes from 2026-11-07: sanitized kubeconfig, `O_NOFOLLOW` share reads, restore staging, asset staging.
- Join tokens with a 1 hour expiry.
- The cache mirror with `pull` only.
- The pinned bend-kube-runtime flow and the sha-pinned guest assets.
- The container mode network and `Container.system`'s own `rshared`.

## Candidate work items

- **F1**
  - `host/vk8s.bend:3731-3735`, `:3715-3722`, `:3680`, `:3691`, `:3628`. Nearby tests: `tests/native_envtest.sh`, `tests/native_smoke.sh`.
  - `src/standalone/native_host.bend:639-640`, `:652-654`, `:711`, `:308`. Nearby laws: `native.ipt_clean`, `native.ipt_clean_none`, `native.delete_leaves_nothing` in `laws/native_host.bend`.
  - `src/guest/netpol.bend:164-165`, `:188-189`. Laws: `laws/netpol.bend`.
- **F2**
  - `src/guest/plan.bend:92-97`. Tests: `tests/plan.bend`, `tests/netpol_e2e.sh`.
  - `src/guest/netpol.bend:55-65` and `:150-156` for option B. Laws: `laws/netpol.bend`.
- **F3**
  - `host/layers/fill.bend:650-681`, `Lf.gc`. Tests: `tests/layers_fill.bend`, `tests/layers_unpack.sh`.
  - `src/layers/pb.bend:289-303`, `src/layers/store.bend:226-241`. Laws: `laws/layers_store.bend`, `laws/layers_pb.bend`.
- **F5**
  - `host/layers/unpack.bend:454-467` and `:210-214`. Tests: `tests/layers_unpack.sh`.
  - `host/layers/fill.bend:332-334` and `:581-583`.
  - `src/layers/fill.bend:50-56`, doc only.
  - `src/layers/store.bend:20-21`, doc only.
- **F6**
  - `host/layers/unpack.bend:81`, `:237`, `:394-397`, `:432`. Tests: `tests/layers_unpack.sh`, `tests/layers_tar.bend`.
  - `src/layers/tar.bend`, for a depth or entry cap in the plan. Laws: `laws/layers_tar.bend`.
- **F7**
  - `src/guest/plan.bend:2427-2428`. Laws: `laws/plan.bend`, `tests/plan.bend`.
- **F8**
  - `src/guest/netpol.bend:216-221` and `:306-319`. Laws: `laws/netpol.bend`.
  - `host/init.bend:885-891`, the gate loop.
- **Test gap**
  - `tests/layers_unpack.sh:75-90`. Add a hard link whose `linkname` is a symlink to a host file, then check that the link count of the host file is unchanged. Add an entry under a symlink.
- **F4, F9 and sibling work**
  - bend-vmm: inode and directory cap in `src/fs/quota.bend`. Request it from the bend-vmm session.
  - `docs/STATUS.md:681-684`. Correct the F6 line.

## Links

- https://github.com/chenhunghan/bend-vmm/tree/d68fcf9 (`src/fs/readonly.bend`, `src/fs/contain.bend`, `src/fs/quota.bend`, `src/net/addr.bend`, `src/net/nat.bend`, `host/hvf.c`, `README.md`)
- https://github.com/cloudnativelabs/kube-router/blob/v2.12.0/pkg/options/options.go
- https://github.com/cloudnativelabs/kube-router/blob/v2.12.0/pkg/controllers/netpol/npc_iptables.go
- https://github.com/cloudnativelabs/kube-router/blob/v2.12.0/pkg/controllers/netpol/network_policy_controller.go
- https://github.com/cloudnativelabs/kube-router/blob/v2.12.0/pkg/controllers/netpol/pod.go
- https://github.com/distribution/distribution/blob/main/registry/proxy/proxymanifeststore.go
- https://github.com/distribution/distribution/blob/main/registry/proxy/proxyblobstore.go
- Repo files cited above: `docs/STATUS.md`, `docs/ref/explore-native-control-plane.md`, `docs/DESIGN.md`.