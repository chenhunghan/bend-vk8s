# Status against docs/GOAL.md

Each item is checked only with evidence: a commit, test output, or a
conformance archive. Known divergences from vcluster are listed at the end.

## 1. Gates

- [x] `bend PROOF.bend` prints ALL PROOFS CHECK and `scripts/check.sh`
  passes. The gate now also compiles host/init.bend and host/vk8s.bend:
  PR #6 had broken the host build without CI noticing.
- [ ] `bend PROOF.bend --verdict` re-checked for the whole tree (per-module
  verdicts run in CI).
- [ ] every src/ module has laws/done/<module>. Done: sha256, names, meta,
  args, plan, cli, kubeconfig, subject, supervise, services, duration,
  table. Pending: the factory modules in flight.

## 2. Conformance

- Run 1, 2026-11-07, single node, etcd, archive
  `out/conformance/202611070634_sonobuoy_*.tar.gz`: 444 passed, 6 failed,
  7136 skipped.
  - 2 failures were "Conformance test suite needs a cluster with at least
    2 nodes" (DaemonSet rollback, two untainted nodes).
  - 4 were session affinity. xt_recent was missing from the assets used
    for that run and is now in scripts/guest/modules.txt.
- [ ] (a) Run 2 on `vk8s create conf --nodes 2 --backing-store etcd`: in
  progress.
- [ ] (b) classic mode.

## 3. Classic mode

- [x] services, endpoints and endpointslices translator (PR #7, laws from
  vcluster's syncer_test.go).
- [ ] core sync framework #5, mappings #8, pods #9 (factory, CI).
- [ ] configmaps/secrets, storage, nodes/events, CoreDNS in Bend,
  k8sdefaultendpoint/servicesync: dispatched to the factory 2026-11-07.
- [ ] syncer runtime in the guest on bend-kube-runtime@0.3.0.0 (published
  2026-11-07, 0xd9b268abd125fd306c83ea43554e4f2c), fake-kubelet proxy,
  leader election.

## 4. Standalone

- [ ] join tokens and /node/join, certs, snapshot format, vcluster.yaml:
  dispatched to the factory 2026-11-07.
- [x] whole-cluster snapshot/restore, VM level (see 5).

## 5. CLI parity (`vcluster --driver docker`)

Smoke-tested on this Mac, 2026-11-07, with a 2-node cluster:
- [x] create (2 nodes in 21.7 s with sqlite; 3 nodes in 27.8 s with etcd)
- [x] delete. It is graceful: bend-vmm `powerdown` makes PID 1 stop the
  daemons last-started-first, unmount and power off. If the guest does not
  power off within 60 s, vk8s quits the VMM, then kills it.
  `--delete-context` works.
- [x] list, with the NAME/STATUS/CONNECTED/AGE table and `--output json`
  byte-exact against vcluster's Go code (laws in laws/table.bend,
  laws/cli.bend, laws/duration.bend).
- [x] connect: `--print`, `--update-current`, `-- COMMAND`
- [x] pause, resume
- [x] snapshot create NAME PATH and restore NAME PATH. The snapshot pauses
  the cluster, clones the disk copy-on-write and resumes; the tar.gz has
  metadata.json first (167 MB for a 2-node cluster). A ConfigMap and a
  Deployment survived a restore into a new name.
- [x] describe (`--config-only`, `-o json`)
- [x] logs NAME [COMPONENT] (vk8s only; vcluster has no `logs` command)

## 6. Production readiness

- [~] Binary that downloads hash-pinned assets.
  scripts/release-assets.sh packs them (about 355 MB) and generates
  src/cli/manifest.bend. vk8s verifies each archive's SHA-256 before
  unpacking. Tested against a local server: a tampered archive is refused
  and leaves nothing behind, and a valid set boots a 2-node cluster.
  scripts/guest/fetch-assets.sh rebuilds the inputs from public, pinned
  sources. Pending: the GitHub release upload, which is the user's call.
  The binary is ad-hoc signed; a Developer ID would need the user's
  certificate.
- [x] Image cache. `vk8s cache start|stop|status` runs a small VM with
  CNCF distribution v3.1.2 as pull-through registries for docker.io,
  registry.k8s.io, ghcr.io and quay.io, on 127.0.0.1:15001-15004. Every
  cluster's containerd tries it first through hosts.toml and falls back to
  upstream. `create` starts it unless VK8S_CACHE=off. Measured: nginx
  pulled in 8.54 s cold and 1.94 s from the cache in a second cluster.
- [ ] soak
- [ ] security review
- [x] README quick start; DESIGN.md needs an update for snapshot and shutdown.

## Known divergences

- The image cache stands in for vind's experimental.docker.registryProxy,
  which reads the host Docker's image store; a vk8s host has no container
  runtime.
- Factory PR deviations, as recorded in each PR: nodes #16 rounds
  requests per container and reads a negative quantity as 0.

- The kube context is `vk8s_NAME`, where vcluster names it
  `vcluster-docker_NAME`.
- describe shows the VMM pid as "Container ID" and adds Nodes and Backing
  store.
- Snapshots carry the control plane's disk only. On restore, workers join
  afresh with empty disks, and every node restarts its pods, as after a
  reboot. containerd state lives in memory.
- `restore` keeps the guest's original node names, so a cluster restored
  under a new name still has nodes named after the old one.
- kube-apiserver still uses `--endpoint-reconciler-type=lease` until the
  k8sdefaultendpoint port lands.
