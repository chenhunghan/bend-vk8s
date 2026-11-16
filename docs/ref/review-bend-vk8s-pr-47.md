## Findings

Line numbers refer to PR head `ba7e259`. All three defects remain on current main `881a387`.

1. **P1: Snapshot requests can overwrite host files through guest-created symlinks.** `host/vk8s.bend:1353`

   ```bend
   ++ Vk8s.q(id) ++ " " ++ Vk8s.q(action) ++ " > \"$d/request.tmp\" && mv \"$d/request.tmp\" \"$d/request\"")
   ```

   The new snapshot sync call writes through a predictable path in the guest-writable share without rejecting symlinks.

   **Scenario:** A compromised guest creates `/var/lib/vk8s-host/requests/request.tmp` pointing to `/home/alice/.kube/config`. When Alice runs `vk8s snapshot create demo /tmp/demo.tgz`, shell redirection truncates her kubeconfig and replaces it with the request text. I traced symlink creation through the pinned bend-vmm’s `P9.symlink`, `Fs.call`, and `symlinkat`; arbitrary symlink targets are permitted. The unsafe helper predates this PR, but snapshots now invoke it.

   **Fix:** Publish requests using directory-relative file operations that reject symlinks in every path component and create temporary files exclusively.

2. **P1: Failed sync still produces a successful backup that can omit existing data.** `host/vk8s.bend:1607`

   ```bend
   synced : Bool <- Vk8s.request.n(60n, dir, "sync")
   Vk8s.unless(synced, Vk8s.say("vCluster " ++ name ++ " did not flush its disk; the snapshot may miss its last writes"))
   ```

   A failed or timed-out flush only prints a warning before the host copies `data.img` and reports success.

   **Scenario:** Pause a guest while a completed write to `/var/lib/vcluster/marker` remains in its page cache, then run `vk8s snapshot create demo /tmp/demo.tgz`. The paused guest cannot answer sync. After roughly 30 seconds, the host copies the disk without guest memory; restoring that successful backup loses the write. The pinned VMM’s pause operation stops vCPUs and does not flush guest caches.

   **Fix:** Require a successful flush before creating a successful disk-only backup, and reject paused guests unless a safe flush procedure preserves their prior state.

3. **P2: Concurrent architecture fetches can silently mix binaries.** `scripts/guest/fetch-assets.sh:54`

   ```bash
   rm -rf loft reg && mkdir -p loft/node reg
   tar -xzf "full$sfx.tgz" -C loft
   tar -xzf "loft/release/kubernetes-$K8S-$arch.tar.gz" -C loft/node
   ```

   Architecture-specific archives and output directories still share mutable extraction directories.

   **Scenario:** Run `ARCH=arm64 scripts/guest/fetch-assets.sh` and `ARCH=amd64 scripts/guest/fetch-assets.sh` concurrently. After arm64 extraction, the amd64 invocation can replace `loft` and `reg` before arm64 copies their contents. The arm64 output then contains amd64 executables despite both archive checksums passing. Current main also shares `gvisor`.

   **Fix:** Give each invocation a private extraction directory, including temporary image preservation, and copy only from that directory.

## Questions for the author

- **Not verified:** Can the smoke test require evidence that the restored container actually restarted? `scripts/smoke-linux.sh:85` checks only the persisted Pod phase. Compare `.status.containerStatuses[0].state.running.startedAt` against the restore time using `out/vk8s connect smoke -- kubectl get pod smoke -o json` before accepting the restored pod.

## What was checked and how

- Reviewed all 30 changed files, including manifests, architecture helpers, guest packaging, laws, proofs, tests, snapshot handling, and CI. Read `CLAUDE.md`, `docs/DESIGN.md`, and `docs/GOAL.md`. Neither requested review skill file was present.
- Compared `6d0db03..ba7e259` and checked relevant changes through current main. Used `git diff`, `git show`, `rg`, `gh pr view 47`, `gh pr diff 47`, and GitHub API reads. No existing review comments duplicated these findings.
- Verified both amd64 download digests against GitHub release metadata. Existing laws remain unchanged. No incorrect new expected value or arm64 argument regression was verified.
- Read the pinned bend-vmm’s pause and shared-filesystem implementations, plus vcluster’s snapshot implementation and tests.
- Read CI run `43886668324`: amd64 smoke passed; arm64 skipped because KVM was unavailable.
- Installed no dependencies and ran no builds, tests, servers, or databases. Changed no working-copy files and wrote nothing to GitHub. Live failure reproduction and a full audit of subsequent container/native changes were outside this review.

## Links

- https://github.com/chenhunghan/bend-vk8s/pull/47
- https://github.com/chenhunghan/bend-vk8s/actions/runs/43886668324
- https://github.com/chenhunghan/bend-vk8s/blob/ba7e259/docs/DESIGN.md
- https://github.com/chenhunghan/bend-vk8s/blob/ba7e259/docs/GOAL.md
- https://github.com/chenhunghan/bend-vmm/tree/adf9dcc
- https://github.com/loft-sh/vcluster/blob/a8ab30e/pkg/cli/snapshot_docker.go
- https://github.com/loft-sh/vcluster/blob/a8ab30e/pkg/cli/snapshot_docker_test.go
- https://github.com/loft-sh/kubernetes/releases/tag/v1.36.6
- https://github.com/distribution/distribution/releases/tag/v3.1.2