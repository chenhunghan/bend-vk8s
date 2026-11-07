# Goal: finish bend-vk8s

A Bend rewrite of loft-sh/vcluster (reference clone `vcluster/`, main a8ab30e)
that runs virtual Kubernetes clusters in bend-vmm VMs on macOS from ONE
binary, `vk8s`. Parity target: vcluster OSS (classic host-cluster mode) plus
standalone, private-nodes and vind behavior as described by public sources.
Never download, run or inspect vcluster-pro binaries.

DONE means every item below is checked off in docs/STATUS.md with evidence
(commit, test output, or conformance archive).

## 1. Gates

`bend PROOF.bend` prints ALL PROOFS CHECK, `bend PROOF.bend --verdict` passes,
scripts/check.sh passes, and every src/ module has laws/done/<module>. No
@unsafe in src/.

## 2. Kubernetes conformance

`scripts/conformance.sh certified-conformance` passes with 0 failures on:
- (a) `vk8s create conf --nodes 2 --backing-store etcd`
- (b) classic mode against a host cluster

Archives go in out/conformance/, counts in STATUS.md. Fix vk8s for every
failure; never skip tests.

Open items from the first run (270 passed, 6 failed):
- session affinity: xt_recent, now added
- "at least two untainted nodes": needs --nodes
- DaemonSet "rollback without unnecessary restarts"

## 3. Classic mode (vcluster OSS parity)

`vk8s create NAME --host-kubeconfig F [--host-namespace NS]` runs the control
plane in a VM and the syncer inside the guest binary. The syncer reaches the
host cluster through bend-vmm's NAT at 10.0.2.2, using kubeconfig
tls-server-name (bend-kube-runtime@0.3.0.0, once the bend-kube session
confirms it is published).

Sync every syncer in docs/ref/vcluster-syncer.md F4 with vcluster's defaults
and config keys, conformance-path syncers first. Then:
- ingress, netpol, PDB, SA, PV/SC/PC
- CSI, runtimeclasses, volumesnapshots
- gateway API, custom resources

Also:
- fake and real nodes
- the fake-kubelet proxy for logs/exec/port-forward, over host/tls_server.bend
- the k8sdefaultendpoint controller, then drop the lease-reconciler deviation
  in src/guest/plan.bend
- CoreDNS manifests generated in Bend with laws, replacing
  scripts/guest/coredns.yaml
- servicesync/replicateServices
- leader election

Every pure translator carries laws transcribed from vcluster's *_test.go.
Tests use a second vk8s cluster as the host cluster. First merge open PRs #5
(core), #7 (services), #8 (mappings) and #9 (pods) once their CI is green and
their laws are reviewed.

## 4. Standalone, private nodes, vind (public sources only)

Sources: the open vcluster repo, vcluster-docs, open release assets
(install-standalone.sh, bundle-standalone.sh), loft-sh/kubernetes.

Implement:
- the /node/join?token=…&type= endpoint and join script, following the docs
  and cmd/vclusterctl/cmd/token
- `vk8s token create`, `vk8s node add/remove`
- `vk8s certs rotate`: 90-day renewal, 24 h watcher, per pkg/certs
- `vk8s snapshot/restore` in the open pkg/snapshot archive format, plus
  whole-VM snapshots through bend-vmm
- `--upgrade`
- parsing a subset of vcluster.yaml, with laws and validation messages that
  match vcluster

Where public sources don't specify a behavior, design it, record it in
docs/ref/standalone-decisions.md, and mark it as a known divergence in
STATUS.md.

## 5. CLI parity with `vcluster … --driver docker`

- create
- delete: graceful (powerdown, then quit), with --delete-context
- list
- connect: --print, `-- command`
- pause, resume
- snapshot, restore
- describe
- logs

Flags and messages match vcluster where they apply.

## 6. Production readiness

- **One binary:** a signed macOS arm64 `vk8s`. On the first `vk8s create` it
  downloads the pinned guest assets (kernel, initramfs, assets disk with
  preloaded images) from the GitHub release, verifies their sha256, and
  caches them in ~/.vk8s/assets/<ver>. A fresh Mac needs only the binary.
- A host-side image cache or registry proxy (this machine's link is slow).
- **Soak:** 10 create/delete cycles plus a 1 h workload with pause/resume,
  with no leaked processes, sockets or disk.
- A security review of the guest/host boundary.
- A README quick start and an up-to-date docs/DESIGN.md.

## Rules

- Follow AGENTS.md. LAWS.bend and laws/ are the spec: only add laws, never
  weaken them. Expected values come from vcluster's Go code or tests, never
  from our own Bend.
- Pure decisions live in src/ with laws; IO lives in host/. Parallelize
  balanced work.
- Delegate pure and Linux-testable work to the lns-factory (implementers,
  explorers, reviewers); do macOS/VM work yourself. Review every PR's laws
  before merging, and smoke-test merged main on the Mac. Build with
  VK8S_ASSETS=~/.vk8s/assets/dev so running clusters are not disturbed.
- Send bend-vmm needs to the bend-vmm Claude session and bend-kube needs to
  the bend-kube session. Pin released versions. BendHub publishes and GitHub
  releases are the user's call: ask first.
- Ask the user only for irreversible or outward-facing steps.
- Keep docs/STATUS.md current and post a short progress note at each
  milestone.
- Never check an item off without its evidence. If something cannot reach
  parity, document the gap and the reason in STATUS.md and move on.
