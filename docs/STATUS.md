# Status against docs/GOAL.md

Each item is checked only with evidence: a commit, test output, or a
conformance archive. Known divergences from vcluster are listed at the end.

## 1. Gates

- [x] `bend PROOF.bend` prints ALL PROOFS CHECK and `scripts/check.sh`
  passes. The gate now also compiles host/init.bend and host/vk8s.bend:
  PR #6 had broken the host build without CI noticing.
- [x] `bend PROOF.bend --verdict` prints ALL PROOFS CHECK for the whole
  tree, re-checked by the Lean-verified kernel (2026-11-07, 3 min 19 s,
  out/verdict.log).
- [x] Every module on main has laws/done/<module>: sha256, names, meta,
  args, plan, cli, kubeconfig, subject, supervise, services, duration,
  table, assets, manifest, core, mappings, configs, nodes, storage. Open
  factory PRs add theirs as they land.

## 2. Conformance

- Run 1, 2026-11-07, single node, etcd, archive
  `out/conformance/202611070634_sonobuoy_*.tar.gz`: 444 passed, 6 failed,
  7136 skipped.
  - 2 failures were "Conformance test suite needs a cluster with at least
    2 nodes" (DaemonSet rollback, two untainted nodes).
  - 4 were session affinity. xt_recent was missing from the assets used
    for that run and is now in scripts/guest/modules.txt.
- [x] (a) Run 2, 2026-11-07, on `vk8s create conf --nodes 2
  --backing-store etcd` (3 VMs, current assets): Status passed, 450 passed,
  0 failed, 7136 skipped. Archive:
  `out/conformance/202611070848_sonobuoy_3cd8fa08-b69e-4f71-87c9-ec994590115c.tar.gz`.
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
- [~] Certificates. `vk8s certs rotate NAME` and `vk8s certs check NAME`
  run over a host-to-guest request channel: the host writes share/requests,
  PID 1 runs Plan.request's steps, and only known actions are accepted
  (law). Rotate renews every certificate with kubeadm, keeping the CA, then
  restarts the control plane on the new ones and rebuilds the host-owned
  kubeconfig. Tested: the serving certificate's serial changed, the API was
  back in about 1 s, and kubectl worked. Pending: the in-guest 24 h
  watcher with vcluster's renewal threshold (pure decision in PR #12), and
  CA rotation. vcluster's own certs commands exist only for its helm
  driver.
- [x] `vk8s node add NAME [--count N]` and `vk8s node delete NAME NODE
  [--drain=false]`. Delete follows vcluster node delete: cordon, then
  drain with Force, IgnoreAllDaemonSets, DeleteEmptyDirData, a 30 s grace
  and a 30 min timeout, then delete the Node; vk8s also stops the worker
  VM. Worker indices are kept in cluster.env WORKERS and survive upgrades.
  Tested: add 2, delete the middle worker, upgrade keeps workers 1 and 3,
  and `--upgrade --nodes 1` removes the stale Node object.

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
- [x] create --upgrade, which follows vcluster's flow: "already exists, use
  --upgrade" and "recreating it...". It stops the VMs gracefully, keeps the
  data disk and port, and applies new settings. Tested going from 1 to 2
  workers and 2 to 3 GiB in 39 s; the data survived.
- [x] `node load-image NAME NODE --archive FILE` (tar or tar.gz) through
  the request channel. Image names are restricted to [a-z0-9.-] (law).
  `--image` needs Docker, so vk8s explains and points to `--archive`.
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
- [~] Security review of the guest/host boundary: a factory explorer
  report, review-vk8s-security-boundary, 2026-11-07.
  Fixed and tested on this Mac:
  - F1: the guest's kubeconfig is never used as is. Kubeconfig.sanitize
    keeps only the three embedded certificates and sets the server to the
    host's forward; laws cover an exec plugin, another server and a skipped
    TLS check. connect, exec and kubectl all use the host-owned file
    (mode 0600).
  - F4: share files are read with O_NOFOLLOW, regular files only, size
    bounded. The join token must match kubeadm's pattern (law). The host
    builds discovery.conf from the CA instead of copying the guest's.
  - F2/F3: restore unpacks into a private staging directory. Exactly
    metadata.json (first), cluster.env and data.img are accepted, all
    regular files, and a qcow2 disk is refused. Tested: a symlinked
    cluster.env, a qcow2 header and an extra member are all refused, and
    the victim file was untouched.
  - F7: asset fetch uses a unique staging directory per run and accepts
    exactly one regular member per archive, extracted by name.
  - F5: the cache mirror has `pull` only, so tags resolve upstream (law).
  - H3: snapshot archives and host-owned files are mode 0600.
  - H2: no never-expiring tokens. Each boot mints a 1 h join token, and
    `node add` mints its own 1 h token as a kubeadm bootstrap-token Secret
    (law). Tested: every token in a cluster carries an expiration.
  - C: proc.c checks every spawn-setup return; the musl closefrom shim
    closes up to the open-file limit; the TLS listener is CLOEXEC; exec.c
    frees on failure and checks setenv.
  Open, documented:
  - F6: guest logs and the share are not size-bounded.
  - TLS splice has no idle deadline yet (fake-kubelet work in progress).
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
  reboot (the kubelet's state is wiped at boot).
- `restore` keeps the guest's original node names, so a cluster restored
  under a new name still has nodes named after the old one.
- kube-apiserver still uses `--endpoint-reconciler-type=lease` until the
  k8sdefaultendpoint port lands.
