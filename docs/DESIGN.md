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
| snapshot (etcd + container state) | control socket `snapshot PATH` (whole-VM, copy-on-write restore) plus an etcd snapshot for portability |
| `docker stop` | control socket `powerdown` (then `quit` after a grace period) |
| docker network for extra nodes | bend-vmm VM-to-VM switch (requested from bend-vmm; not yet built) |

Until bend-vmm can be imported as a library (requested: a `Vmm.run(args)`
entry), `vk8s` runs `bend-vmm` as a child process, one per node.

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
- **initramfs (about 5 MB):** busybox, the kernel modules we load, and
  `vk8s` as PID 1. vk8s loads the modules, mounts cgroup2, sets sysctls,
  and supervises every process itself, which replaces vcluster
  standalone's systemd unit.
- **Read-only, shared assets disk:** an ext4 or squashfs image per
  Kubernetes version holding kube-apiserver, kube-controller-manager,
  kube-scheduler, kubelet, etcd or kine, containerd, runc and the CNI
  plugins. These are static binaries and dominate the size (about 300 MB),
  so they stay out of RAM and are shared by every VM.
- **Per-VM qcow2 data disk:** /var/lib (etcd or kine data, containerd
  images, the PKI).

Target: kernel to `vk8s` running in well under a second. `--restore` of a
paused cluster's snapshot is about 20-40 ms. Risk to verify early: Bend's
native `Process.run` needs glibc 2.34+ on Linux, so the guest build of
`vk8s` either ships its glibc in the initramfs or links statically.

## Modes (parity targets)

1. **Standalone, single node** (vind's default): one VM is both control
   plane and node. Needs nothing new from bend-vmm. First milestone.
2. **Standalone, private nodes**: more VMs join with a join token. Blocked on
   bend-vmm VM-to-VM networking.
3. **Classic (host cluster)**: the control plane runs in a VM, and the syncer
   mirrors workloads into an existing host cluster reached through the VM's
   NAT (kubeconfig given at create). This is the vcluster syncer: `pkg/syncer`,
   `pkg/controllers/resources/*`, `pkg/mappings`, `pkg/server`.

## Layers

- `src/` is pure Bend: every decision. That covers name translation, object
  translation (virtual to host and back), config parsing and defaults
  (vcluster.yaml), process command lines, PKI plans, the VM command lines,
  CLI argument parsing, and proxy request routing. No IO. Laws range over it.
- `host/` holds the IO layer: process supervision, files, sockets, TLS
  server effects (`host/effs/*.c`, OpenSSL via dlopen as bend-kube does),
  and the bend-kube-runtime client for talking to API servers.
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
