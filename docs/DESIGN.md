# bend-vk8s design

bend-vk8s is a rewrite of [vcluster](https://github.com/loft-sh/vcluster)
(reference: main at a8ab30e, 2026-11-05) in Bend. It runs virtual Kubernetes
clusters in [bend-vmm](https://github.com/chenhunghan/bend-vmm) microVMs
instead of Docker containers or host-cluster pods.

## Shape: one binary, `vk8s`

The same Bend source builds one `vk8s` binary per platform. It plays two roles:

| Role | Where | vcluster counterpart |
|---|---|---|
| `vk8s create/delete/list/connect/pause/resume/snapshot/restore` | the host (macOS arm64, Linux arm64) | `vcluster ... --driver docker` (vind), `pkg/cli/*_docker.go` |
| `vk8s run` (control plane supervisor, syncer, proxy, PKI, join) | inside a bend-vmm guest (Linux arm64) | the `vcluster` binary in a pod or in standalone mode (`cmd/vcluster`, `pkg/setup`, `pkg/k8s`, `pkg/controllers`, `pkg/server`) |

Where vind starts containers, `vk8s` boots bend-vmm VMs:

| vind (Docker) | vk8s (bend-vmm) |
|---|---|
| control-plane container (privileged) | control-plane VM on bend-vmm's fast path (`--kernel/--initrd`, no UEFI, no distro; see Guest image) |
| bind-mounted binaries and config | `--share` (virtio-9p) of the vcluster's state dir, or a cloud-init seed disk |
| published port 6443 | `--forward 127.0.0.1:<port>:6443` |
| `docker pause/unpause` | control socket `pause` / `resume` |
| snapshot (pause, volume export, tar.gz with metadata.json first) | pause, copy-on-write clone of the control plane's data disk, resume; tar.gz with metadata.json, cluster.env and data.img (holes kept) |
| `docker stop` | control socket `powerdown`: PID 1 stops the daemons one at a time, last started first, unmounts and powers off; `quit` after 60 s |
| `create --upgrade` (recreate the container, keep volumes) | stop the VMs, keep the data disk, boot on the current assets |
| registry proxy (host Docker's image store) | `vk8s cache`: a host process (`vk8s cache serve`, host/cache/mirror.bend) of pull-through, pull-only OCI mirrors on 127.0.0.1:15001-15004, every VM node's containerd mirror (10.0.2.2:1500x) |
| docker network for extra nodes | bend-vmm `--lan DIR,ip=…` (one LAN per cluster: control plane 10.10.0.2, worker i 10.10.0.(2+i)) |

bend-vmm is imported as a library (BendHub package by hash): `vk8s vmm
<flags>` runs a VM in its own process, and the cluster commands start one
such process per node.

Every VM on one bend-vmm LAN must run the same LAN wire format (bend-vmm
6951844 added checksum and TSO offload, MTU 2022). vk8s numbers these
formats (src/cli/lan_wire.bend: 1 before that pin, 2 since) and records
the cluster's as LAN_WIRE in cluster.env; a cluster.env without it is
version 1. Create, `create --upgrade` and restore start every VM on the
current binary and write the current version. `node add`, `certs
rotate-ca` and `vk8s vmm` itself (which a guest reset runs again) start a
VM beside running ones, so they refuse another version and name the two
ways out: recreate the cluster, or `vk8s create NAME --upgrade`.

Like vcluster, bend-vk8s does not reimplement the upstream Kubernetes
binaries. kube-apiserver, kube-controller-manager, kube-scheduler, etcd (or
kine), kubelet, containerd and the CNI plugins are assets fetched by version,
as vind pulls its "kubernetes" image. Everything vcluster itself
implements is rewritten in Bend.

## Guest image

No distribution and no init system. Each VM boots:

- **Kernel:** Alpine's `linux-virt` arm64 kernel (6.18, 9.9 MB). Its config
  has everything kubelet and containerd need, mostly as modules: cgroup v2
  (memcg, pids, cpuset, CFS bandwidth, BPF), overlayfs, bridge,
  br_netfilter, veth, vxlan, conntrack, nftables/iptables, IPVS, seccomp,
  and user namespaces. It also has every bend-vmm device: virtio-mmio, net,
  blk, 9p, vsock, rng, PL011 and PL031.
- **initramfs (about 3 MB, about 1 MB resident):** stage 0
  (scripts/guest/stage0.sh), busybox, the modules that mount the assets
  disk (virtio_mmio, virtio_blk, squashfs and their dependencies) and
  symlinks into it. Stage 0 loads those modules, copies the initramfs
  except the modules into a tmpfs, mounts the assets disk (/dev/vda)
  read-only at /assets in it, and switch_roots to `vk8s` as PID 1. vk8s
  loads the other modules (ext4, for the data disk, among them), mounts cgroup2, sets sysctls, and supervises every
  process itself, which replaces vcluster standalone's systemd unit.
  The initramfs stays in RAM in every VM, so nothing else goes into it.
- **Read-only, shared assets disks:** squashfs images (zstd, 256 KiB
  blocks; scripts/guest/mksqfs.sh) per Kubernetes version, stored and
  read compressed, never unpacked (docs/ref/footprint-decisions.md A1).
  The Kubernetes binaries are split into role sets, one disk each
  (footprint-decisions D1, scripts/guest/sets.txt): node (kubelet,
  kubeadm, containerd, runc, the CNI plugins, the pause image, gVisor's
  runsc and its containerd shim for the opt-in `gvisor` RuntimeClass),
  control-plane (kube-apiserver, kube-controller-manager,
  kube-scheduler, kubectl, etcd, kine), classic (konnectivity-server),
  cache (registry; the image cache VM's, which no longer boots: the cache
  runs on the host) and images (the add-on tars, only where the image
  cache does not run). A VM attaches the sets of its role from /dev/vdc
  on, and PID 1 joins them at /var/lib/vcluster/bin with a read-only
  overlay (Plan.disks.v3). The base disk, base.img (/dev/vda), holds the
  guest root under guest/: vk8s-guest (host/init.bend linked against
  glibc, which dlopens OpenSSL; PID 1 through the relative link
  sbin/vk8s-init), glibc, libssl, iptables and conntrack from Debian, the
  other kernel modules and the CA roots. The initramfs links /sbin/vk8s-init, /usr/lib (and /lib through
  it), /usr/share, /etc/ssl and each file of usr/bin and usr/sbin to
  /assets/guest. These dominate the size (about 300 MB), so they stay on
  the disk, which every VM shares: a guest holds only the pages it reads,
  as clean page cache it can drop.
- **Per-VM data disk** (a copy-on-write clone of a 16 GiB sparse ext4
  template): /var/lib/vcluster, which holds the etcd or kine data, the
  containerd root and the PKI. The kubelet's state is wiped at every boot,
  so a reboot, a restore or an upgrade re-creates the node's pods.
  PID 1 runs fstrim on it every 10 min, and bend-vmm punches holes in the
  image for what it frees, so deleted images and compacted data give host
  disk back (`Plan.fstrim`; periodic, not `mount -o discard`, which pays
  for a discard on every delete).

Assets come from the GitHub release this binary pins
(src/cli/manifest.bend, made by scripts/release-assets.sh). On first use
they are downloaded, checked against their SHA-256, and unpacked into
~/.vk8s/assets/<version>; VK8S_ASSETS points at a local build instead.
scripts/guest/fetch-assets.sh assembles the inputs from public, pinned
sources: loft-sh/kubernetes's bundle, dl.k8s.io and CNCF distribution.

Target: kernel to `vk8s` running in well under a second. `--restore` of a
paused cluster's snapshot is about 20-40 ms. Risk to verify early: Bend's
native `Process.run` needs glibc 2.34+ on Linux, so the guest build of
`vk8s` either ships its glibc in the initramfs or links statically.

## Modes (parity targets)

1. **Standalone, single node** (vind's default): one VM is both control
   plane and node. Works: `vk8s create` is Ready in about 4 s.
2. **Standalone, private nodes**: `vk8s create --nodes N`. Worker VMs join
   with kubeadm bootstrap tokens (the control plane uploads kubeadm-config,
   kubelet-config and cluster-info and sets up the bootstrap RBAC, as vcluster
   private nodes expect); flannel (host-gw over the LAN) and kube-proxy run as
   DaemonSets, as vcluster deploys them. Works.
   NetworkPolicy is enforced by kube-router's network policy controller
   alone (no routing, proxy or CNI; iptables and ipset), as k3s embeds it:
   a node asset that each node's PID 1 starts beside the kubelet, with the
   kubelet's own kubeconfig (src/guest/netpol.bend). Before the kubelet
   starts, PID 1 drops pod traffic in a mangle chain of its own
   (VK8S-NETPOL-GATE); it empties the chain once kube-router has finished
   its first full sync, and kube-router's --netpol-default-deny covers
   each later pod until its own chain exists. The same applies in node
   containers and on a native host node.
3. **Classic (host cluster)**: the control plane runs in a VM, and the syncer
   mirrors workloads into an existing host cluster reached through the VM's
   NAT (kubeconfig given at create). This is the vcluster syncer: `pkg/syncer`,
   `pkg/controllers/resources/*`, `pkg/mappings`, `pkg/server`.
   vcluster runs inside the host cluster; vk8s's VM does not. Two host
   Services bridge the gap. Their Endpoints are the Mac's loopback
   forwards, which host pods reach as 10.0.2.2 through the host VMs' NAT:
   - The vcluster Service `<vc>`: https to the virtual API server, and
     kubelet to the fake kubelet.
   - `<vc>-konnectivity`, for agents.

   The virtual API server's "cluster" egress (webhooks, aggregated APIs,
   the service and pod proxy, kubelets) goes through konnectivity. The
   server runs in the VM; the agent is a virtual kube-system Deployment
   that the syncer places on the host, so it opens those connections from
   inside the host network. Fake and real nodes advertise the vcluster
   Service's IP as their kubelet address, so kubelet traffic reaches the
   fake kubelet through the agent. Agents authenticate with a virtual
   service-account token, which the server reviews.

## The guest's PID 1

A busybox stage 0 loads the virtio and squashfs modules, copies the initramfs
into a tmpfs, mounts the assets disk read-only at /assets in it, and
switch_roots into it (runc's pivot_root refuses the initramfs rootfs), then
execs vk8s (`host/init.bend`, /sbin/vk8s-init, a link to
/assets/guest/sbin/vk8s-init, itself a link to ../usr/bin/vk8s-guest) as
PID 1. It is the dynamic glibc build: the base disk, with glibc's loader
and libraries, is mounted before it starts. vk8s runs the pure boot plan
(`src/guest/plan.bend`), then supervises: it starts every program through
its own spawn effect (`host/effs/proc.c`), reaps every exited child
(orphans too), and restarts a daemon 5 s after it exits
(`src/guest/supervise.bend`, proven; vcluster standalone relies on systemd's
Restart=always, RestartSec=5s). Daemon logs go to the host share
(`~/.vk8s/clusters/<name>/share/logs/`).

The power button (bend-vmm's `powerdown`, sent by `vk8s delete`) makes PID 1
stop the daemons one at a time, last started first (`Sup.stop_order`,
proven), giving each up to 10 s. Then it ends every other process, unmounts
and powers off. Stopping in order matters: kube-apiserver needs its store
while it shuts down.

The boot plan is idempotent on an existing data disk: RBAC objects are
applied, not created, and workers wipe their state and retry
`kubeadm join` until a stale Node object stops reading Ready.

Backing store: kine on SQLite by default (vcluster standalone's default), or
`--backing-store etcd` (vcluster's embedded etcd). vcluster's own
conformance configuration uses etcd: kine fails apimachinery/chunking.

The add-on images (flannel, CoreDNS, kube-proxy) are the images set
(`scripts/guest/images.sh`): a VM that boots while the image cache does
not run imports them and starts without pulls; with the cache, kubelet
pulls them through it at first use (footprint-decisions A3).

## Layers

- `src/` is pure Bend: every decision. That covers name translation, object
  translation (virtual to host and back), config parsing and defaults
  (vcluster.yaml), process command lines, PKI plans, the VM command lines,
  CLI argument parsing, and proxy request routing. No IO. Laws range over it.
- `host/` holds the IO layer: process supervision, files, sockets, TLS
  server effects (`host/effs/*.c`, OpenSSL via dlopen as bend-kube does),
  binary file effects (`host/bin_file.bend`: create 0600, append and
  ranged reads of `List<&2, U32>` bytes, for snapshot tar streams and
  store dumps), and the bend-kube-runtime client for talking to API
  servers.
- Kubernetes client: `bend-kube-runtime` from BendHub (JSON, YAML, HTTP,
  TLS client, watcher, store, queue). bend-kube has no TLS server, no socket
  splice and no two-cluster manager, so those live here.

## Verification gate

vcluster's conformance story has three layers. Each is mapped:

1. **Kubernetes conformance** (sonobuoy, `Justfile run-conformance`,
   `test/conformanceValues.yaml`; certified product under
   `ai-conformance/`). It runs the upstream e2e `[Conformance]` suite against
   a virtual cluster. Most of it exercises the upstream apiserver, which we
   ship unchanged. The rest exercises vcluster's own code: syncers, DNS,
   service account tokens, the kubelet proxy for logs/exec, and node and
   endpoint translation. That part is stated as laws over `src/`. The full
   sonobuoy run is `scripts/conformance.sh`, run against a live cluster.
2. **vcluster e2e suites** (`e2e/suite_*`, `e2e/test_*`): each behavior is
   a law (pure decision) or a scenario test (`tests/*.bend`, driven
   against a simulated API store).
3. **vcluster unit tests** (`pkg/**/*_test.go`): their table cases become
   concrete laws (`{f(input) == output}`, closed by `{==}`), and their
   invariants become general laws with proofs.

`bend PROOF.bend` must print ALL PROOFS CHECK before any commit, and
`scripts/check.sh` is the CI gate. `laws/done/<module>` ratchets a module
once it fully proves.
