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
| control-plane container (privileged) | control-plane VM: Ubuntu 24.04 arm64 image (UEFI) or kernel+initrd, qcow2 overlay over a shared read-only base |
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
