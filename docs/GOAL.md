# Goal: finish bend-vk8s

A Bend rewrite of loft-sh/vcluster (reference clone `vcluster/`, main a8ab30e)
that runs virtual Kubernetes clusters in bend-vmm VMs on macOS (and, from
section 8, on Linux, in VMs or natively) from ONE binary, `vk8s`. Parity target: vcluster OSS (classic host-cluster mode) plus
standalone, private-nodes and vind behavior as described by public sources.
Never download, run or inspect vcluster-pro binaries.

DONE means every item below (sections 1-8) is checked off in docs/STATUS.md with evidence
(commit, test output, or conformance archive).

## Done (sections 1-7)

Checked off in docs/STATUS.md with evidence on 2026-11-16 (main f95b53e);
the full text of these sections is in git history (docs/GOAL.md before
this trim). Summary of what each required:

1. **Gates:** `bend PROOF.bend` (and `--verdict`) print ALL PROOFS CHECK,
   `scripts/check.sh` passes, every module has laws/done.
2. **Kubernetes conformance:** zero-failure sonobuoy certified-conformance
   on a 2-node etcd cluster and in classic mode.
3. **Classic mode:** every vcluster OSS syncer, the fake-kubelet proxy,
   k8sdefaultendpoint, CoreDNS in Bend, leader election.
4. **Standalone, private nodes, vind:** join tokens and /node/join, node
   add/remove, cert rotation, snapshot/restore (VM and open formats),
   upgrade, vcluster.yaml.
5. **CLI parity** with `vcluster ... --driver docker`.
6. **Production readiness:** signed binary with hash-pinned guest assets,
   image cache, soak test, security review, docs.
7. **Minimal host footprint** (targets revised with the user): an idle
   worker at most 640 MiB phys_footprint after a 30-pod burst, idle worker
   at most 2.5% host CPU and the image cache under 1%, disk give-back,
   a small resident boot image, default sizes kept as ceilings.

Keep these working: section 2's regression subset (scripts/regression.sh)
passes before any guest change lands, and a release re-runs the certified
suite.

## 8. Linux hosts and native mode

Added 2026-11-16 at the user's request. vk8s also runs on Linux, in VMs on
KVM and natively, and on x86_64 as well as arm64.

- **Linux arm64 on KVM:** `vk8s-linux-arm64` builds, boots the same guest
  assets under bend-vmm on `/dev/kvm`, and passes a smoke test (`create`,
  pods Running, `delete` leaves nothing). Releases ship it next to
  `vk8s-darwin-arm64`, each with its hash-pinned assets.
- **x86_64:** `vk8s-linux-amd64` on KVM, with an amd64 guest kernel and
  assets (hash-pinned like arm64). bend-vmm's x86_64 machine model is a
  need sent to the bend-vmm session. Same smoke test, plus the section 2
  regression subset in standalone and classic mode.
- **Native mode on Linux:** `vk8s create --native` (name to be decided)
  runs the control plane directly on the Linux host, as vcluster
  standalone does: a systemd unit per cluster, its data under a vk8s data
  directory, no VM. Nodes join with the same bootstrap tokens (private
  nodes); worker VMs stay available. Behavior from vcluster's public
  standalone docs and config schema, never from the pro binary. `delete`
  removes the unit, its data and its iptables state. Conformance: the
  section 2 regression subset, then a certified run.
- **Container mode (vind-style):** `--backend container`. On Linux, each
  node (and the control plane) is a container vk8s makes itself, with
  namespaces and a delegated cgroup v2 subtree, running the same node image
  and PID 1, as vcluster's docker driver runs nodes as containers, without
  needing Docker. On macOS, `--backend container` starts or reuses one
  shared bend-vmm "node host" VM and runs the node containers inside it (one
  guest kernel and page cache for all nodes). VM per node stays the default.
- **gVisor RuntimeClass:** nodes can ship gVisor's `runsc` and its containerd
  shim and offer an opt-in `gvisor` RuntimeClass for pods, in every backend
  (systrap platform, no nested virtualization needed).
- Apple's `container` / Containerization is out of scope for now (decided
  with the user 2026-11-16).
- **Decisions (user, 2026-11-16):** the flag is `--backend vm|container|native`;
  the default is `native` on Linux (lightest: no guest kernel, page cache or
  VMM) and `vm` on macOS. Native mode runs as the user and calls sudo only
  for the steps that need root (systemd unit, iptables, modules, sysctls),
  printing each. KVM on Linux arm64 is tested under bend-vmm's emulated-KVM
  job (recorded as such in STATUS) and on real KVM via GitHub x86_64 runners
  once bend-vmm has x86_64. Releases: a macOS release after the certified
  runs pass, then linux-arm64 once its smoke test passes (approved).
- **Testing:** container mode, native mode and gVisor need only a Linux
  kernel: they run in CI on GitHub's Linux runners and on the Mac inside a
  bend-vmm Linux dev VM (a Debian arm64 root filesystem with systemd, so
  native mode can be tested). The KVM backend needs real KVM: GitHub's
  x86_64 runners once bend-vmm has x86_64, bend-vmm's emulated-KVM job or
  a self-hosted runner for arm64 (this Mac, an M2, has no nested
  virtualization).
- Evidence: CI on Linux runners (KVM where the runner allows it), the
  smoke tests' logs, and the conformance archives in docs/STATUS.md.

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
