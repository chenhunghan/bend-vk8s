# Goal: finish bend-vk8s

A Bend rewrite of loft-sh/vcluster (reference clone `vcluster/`, main a8ab30e)
that runs virtual Kubernetes clusters in bend-vmm VMs on macOS (and, from
section 8, on Linux, in VMs or natively) from ONE binary, `vk8s`. Parity target: vcluster OSS (classic host-cluster mode) plus
standalone, private-nodes and vind behavior as described by public sources.
Never download, run or inspect vcluster-pro binaries.

DONE means every item below (sections 1-9) is checked off in docs/STATUS.md with evidence
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
  VMM) and `container` on macOS (one shared bend-vmm VM for all nodes;
  `vm` stays the default until container mode passes the regression subset
  and a certified run on the Mac, and the switch lands with that evidence). Native mode runs as the user and calls sudo only
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

## 9. Asset disk footprint

Added 2026-11-16 at the user's request. The guest assets are mostly
upstream Kubernetes and container binaries (~922 MB uncompressed on a raw
ext4 assets.img of 1.0-1.2 GB; ~355 MB compressed download). Shrink what a
host downloads and stores, without changing behavior:

- **Compressed read-only assets disk:** assets.img becomes squashfs or
  erofs (zstd or lz4), mounted read-only and never unpacked (as Talos and
  snaps do). Target: assets on disk within 10% of the compressed download.
- **Per-role contents:** a node set (kubelet, containerd, runc, CNI,
  kube-proxy) and a control-plane set; konnectivity only for classic mode,
  the registry only for the image cache. A worker-only host downloads only
  the node set.
- **No runtime-unneeded tools:** drop crictl, ctr and helm (or replace their
  uses), and duplicates such as kube-proxy shipped as binary and image.
- **Preloaded images:** pulled on first use through the image cache where it
  runs, preloaded only where there is no cache.
- Not in scope unless decided later: a k3s-style multi-call Kubernetes
  build (biggest saving, but our own Kubernetes distribution instead of
  pinned upstream release hashes).
- Target overall: the download and the on-disk assets each about 200-300 MB
  per arch, and no regression in the section 2 runs.
- Evidence: before and after sizes per asset and per role in STATUS.md,
  and the regression subset in standalone and classic mode.

## 10. Lightest personal Kubernetes

Added 2026-11-17 at the user's request: vk8s should be the lightest
Kubernetes for personal use and replace the lima (k0s) cluster that the
lns-factory uses. The default cluster is already single-node (one VM).

- **Idle tuning:** longer kubelet housekeeping/sync/image-GC intervals,
  leader election off on a single control plane, GOMEMLIMIT/GOGC per
  component, controllers that conformance does not exercise off. Node
  status and lease intervals stay at upstream defaults unless a certified
  run proves otherwise; no GA API group is disabled.
- **Sleep when idle:** a cluster with no API traffic for N minutes pauses
  (0% CPU) and resumes on the next request through its API forward. Resume
  refreshes the node lease and status before controllers act, so no pod is
  evicted for the time asleep. Default on for personal use, an opt-out
  flag; the conformance scripts turn it off.
- **Shared image layers:** layers are stored once on the host and shared
  read-only into nodes (a snapshotter backed by the Bend OCI mirror's store
  or a shared layer store), so N clusters do not keep N copies.
- **Shared image layers on by default, once proven better** (added
  2026-11-18 at the user's request). Today the store is opt-in
  (VK8S_LAYERS=1). It becomes the default only when all of these hold,
  with the evidence in STATUS.md; until then it stays opt-in:
  - The store fills itself: a pull (through the image cache or the
    node's fallback) puts its layers in the store, so no manual
    `vk8s layers fill` is needed. The fallback fills only what the
    image cache can read (public images of the registries it serves).
    `vk8s layers gc` keeps every layer a
    running node holds (review F3) and runs safely beside a fill (F5).
  - No slow snapshotter call: Usage of a shared layer comes from a size
    recorded at fill time, not du over 9p; List honours its filters.
  - Measured better, same Mac, same workload, store on vs off: host disk
    for 1, 3 and 10 nodes (and 2 clusters), host memory (phys_footprint),
    time to a running pod with a cold and a warm store, and idle CPU. On
    is better on disk and not worse beyond noise on the rest; a cold
    pull is not slower than off by more than 10%.
  - Conformance with the store on: the regression subset at 43/0 in CI
    (VM mode), then a certified run with 0 failures on the Mac.
  - A soak with the store on (scripts/soak.sh 10 60) passes with no
    leak, and a store left by an older vk8s still works or is rebuilt.
  - Then flip the default: VK8S_LAYERS=0 is the opt-out, `vk8s create`
    documents it, and the next release notes say so. Container and
    native nodes keep the per-node unpack unless measured the same way.
- **Measure against lima:** idle CPU, memory, disk, create time, time to
  a running pod and hours of churn, on the lns-factory's real workload,
  vk8s (store on and off) against the lima (k0s) cluster on the same
  Mac. No "lightest" claim is made until this is in STATUS.md. The
  method is docs/ref/bench-plan.md (reviewed by codex and pi, 2026-11-18).
- Conformance stays: every change keeps the regression subset at 43/0 in
  CI, and a certified run on the Mac (both modes, 0 failures) closes the
  section.

## 11. Smaller and purer

Added 2026-11-20 at the user's request, from an audit of main (34ab54a)
against the pure-Bend and lowest-footprint goals. Items marked
"bend-vmm" wait for the bend-vmm session, which says when its side has
landed; pin its release, then do the vk8s side. Every item keeps the
regression subset at 43/0 in CI; items that change what a node runs
also need a Mac smoke run (no long Mac runs without the user's OK).

- **gc never removes a layer being mounted:** `vk8s layers serve` bumps
  a layer's last use when it answers present, or gc re-reads the held
  set after taking a layer's lock, so a layer near its 3-day expiry is
  not removed between present and the node's mount. Lands before the
  store becomes the default (section 10).
- **One read per layer:** the diffID is hashed while the blob is
  decompressed, not by reading the tar again. Needs bend-kube-runtime's
  Unz.file to hash what it writes (a bend-kube change and a BendHub
  publish, the user's call).
- **Compressed arm64 kernel:** ship Alpine's gzip payload as `Image`
  (bend-vmm already inflates gzip kernels), about 36 MB to 10 MB on
  disk and download; boot checked on macOS HVF and Linux KVM.
- **No image-cache VM:** `vk8s layers serve` pulls from registries
  itself with the proven src/oci modules (route, auth, single-flight
  fill, store) and host/oci, so cache.img and its VM (150-300 MiB RAM)
  go away and registry DNS/TLS leave the VM NAT. Same gates as the
  store: cold-pull bench within 10%, 43/0, a certified run.
- **Compressed layer images, if measured better:** zstd blocks in the
  layer squashfs images (the guest kernel reads them) only when host
  CPU per fill and time to a running pod stay within 10% while disk
  drops; otherwise document why not.
- **Optional sets fetched on demand:** gVisor (runsc) and etcd move out
  of node.img and control-plane.img into their own sets, fetched and
  attached only when `--gvisor` or `--backing-store etcd` asks for
  them; the choice persists in cluster.env through upgrade, node add,
  restore and cert rotation; `vk8s create` names the optional features
  that are off and their flags. kube-router (NetworkPolicy, a parity
  feature) stays in the default set unless the user decides otherwise.
- **Control-plane-only nodes:** `controlPlane.standalone.joinNode.enabled:
  false` with workers leaves the kubelet, containerd and node networking
  off the control-plane VM.
- **One guest binary and one runtime pin:** every import of
  bend-kube-runtime on one version; vk8s-init and vk8s-guest share one
  build where the guest's libc allows.
- **Shared assets and layers off the VM:** Linux native clusters use one
  read-only copy of a version's binaries (not an unsquashfs per
  cluster), and native and container nodes loop-mount the shared layer
  images instead of unpacking per node, each measured as in section 10.
- **Fewer shell-outs:** host/vk8s.bend's `sh -c` calls give way to the
  Bend effects that already exist (bend-vmm's control API, file effects,
  random, bend-kube-runtime for the kubectl and curl calls), so a host
  needs only the vk8s binary; guest hot paths (daemon env, snapshotter
  file operations, simple plan scripts) stop spawning busybox.
- **Every module proven:** laws/done markers for backend,
  container_host, ctr, nodehost, layers_pb and layers_state.
- **Idle sleep everywhere:** a macOS node-host VM sleeps when all its
  container clusters are idle. Linux native clusters do not sleep (the
  user, 2026-11-20: their API server owns the host's :6443, so an idle
  proxy would move it and change the unit, PKI and joins; native mode
  is for Linux servers).
- **Deep sleep (bend-vmm):** once bend-vmm can hibernate a paused VM's
  RAM to disk, idle sleep reclaims memory first and hibernates instead
  of pausing; `vk8s list` shows it. Idle stays "no API use for N
  minutes": no busy check of the workloads (the user, 2026-11-20: wake
  is fast, and background work pausing is documented, with
  `--idle-sleep 0` or a longer limit for long unattended jobs).
- **Auto balloon (bend-vmm):** once bend-vmm's auto balloon deflates
  fast on bursts, vk8s passes it a cap (about 75-80%) and measures the
  awake memory saved.

## Rules

- Follow AGENTS.md. LAWS.bend and laws/ are the spec: only add laws, never
  weaken them. Expected values come from vcluster's Go code or tests, never
  from our own Bend.
- Pure decisions live in src/ with laws; IO lives in host/. Parallelize
  balanced work.
- Pure Bend as far as possible (user, 2026-11-16): new logic is Bend code
  and Bend effects, not `sh -c` strings, Python, C files or extra CLIs,
  unless Bend cannot do it; then keep the foreign part minimal and say why.
  Build scripts and CI glue may stay shell.
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
