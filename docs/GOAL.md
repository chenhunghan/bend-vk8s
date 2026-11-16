# Goal: finish bend-vk8s

A Bend rewrite of loft-sh/vcluster (reference clone `vcluster/`, main a8ab30e)
that runs virtual Kubernetes clusters in bend-vmm VMs on macOS from ONE
binary, `vk8s`. Parity target: vcluster OSS (classic host-cluster mode) plus
standalone, private-nodes and vind behavior as described by public sources.
Never download, run or inspect vcluster-pro binaries.

DONE means every item below (sections 1-7) is checked off in docs/STATUS.md with evidence
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

## 7. Minimal host footprint

Every VM holds only the host CPU, memory and disk it is using, and gives
the rest back when it stops using it. Baseline (2026-11-15, `vk8s create
--nodes 1`, 2 vCPU / 2048 MiB per VM, idle 3 min): the worker's VMM held
1.8-2.0 GB while its guest used 115 MB (AnonPages) with 877 MB free; idle
host CPU was 5-10% (control plane), 1-2% (worker), 0.1% (image cache).
Device-side work goes to the bend-vmm session as a need.

- **Memory give-back:** guest pages the guest frees return to macOS
  (bend-vmm virtio-balloon with free page reporting; the guest loads
  virtio_balloon and drops its page cache when idle). Target: after a
  30-pod burst and 2 min idle, a worker VMM's physical footprint
  (`vmmap -summary PID`, "Physical footprint", what Activity Monitor
  shows; plain `footprint PID` undercounts guest RAM touched only through
  Hypervisor.framework) is at most 640 MiB. (Revised again 2026-11-16 with
  the user from 512 MiB: after bend-vmm stopped double-charging pages its
  threads write and PID 1 stopped holding cold page cache, what remains is
  what a stock kubelet and containerd worker holds: ~83 MB the guest
  kernel reserves at boot, ~240 MB hot file cache, ~120 MB anon, slab. A
  1 GiB worker saves only ~40 MB, so workers stay 2 GiB. Revised 2026-11-15 with the
  user: the earlier target, within 256 MiB of the guest's used memory,
  measured the gap rather than the cost; a 16 KiB-page guest kernel met
  the gap while the guest's own use doubled and the host total stayed the
  same. That kernel stays an opt-in build, VK8S_KERNEL=16k.)
- **Resident boot image:** what the initramfs keeps in RAM is as small as
  practical (baseline 207 MB Shmem per VM); large binaries live on the
  read-only assets disk.
- **Idle CPU:** an idle vCPU sleeps until its next timer or interrupt
  instead of polling (bend-vmm). Target: an idle worker (2 vCPU, stock
  kubelet) at most 2.5% host CPU and the image cache VM under 1%, on a
  quiet host over 3 x 120 s. (Revised 2026-11-16 with the user from
  "each under 1%": kubelet's fixed timers alone cost about 1.35% of host
  CPU under virtualization, and they cannot be configured.)
- **Disk give-back:** files the guest deletes free host disk (discard or a
  periodic fstrim on writable disks; bend-vmm punches holes). Target: after
  pulling and then removing a 500 MB image, the node's data.img shrinks by
  at least 400 MB. `vk8s delete` leaves nothing behind, and superseded
  asset versions in ~/.vk8s/assets can be removed by vk8s.
- **Defaults:** the default VM sizes are ceilings, not costs: with memory
  give-back in place, an idle default cluster costs about what it uses.
- Evidence for each item: before and after numbers in docs/STATUS.md, and
  no regression in the section 2 conformance runs.

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
