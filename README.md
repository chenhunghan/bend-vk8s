# bend-vk8s

vcluster, rewritten in [Bend](https://bend-lang.com), running virtual
Kubernetes clusters in [bend-vmm](https://github.com/chenhunghan/bend-vmm)
microVMs instead of Docker containers. One binary, `vk8s`, embeds the VMM.
Its CLI follows `vcluster … --driver docker` (vind). See docs/DESIGN.md for
the architecture and docs/STATUS.md for where it stands against
docs/GOAL.md.

## Install (macOS 15+, Apple Silicon)

```sh
curl -fLo vk8s https://github.com/chenhunghan/bend-vk8s/releases/download/v1.36.6-42a05fb8/vk8s-darwin-arm64
chmod +x vk8s && sudo mv vk8s /usr/local/bin/
```

## Install (Linux arm64)

```sh
curl -fLo vk8s https://github.com/chenhunghan/bend-vk8s/releases/download/v1.36.6-f3265aa9/vk8s-linux-arm64
chmod +x vk8s && sudo mv vk8s /usr/local/bin/
vk8s create demo                    # native on Linux by default
vk8s create demo --backend vm       # or a KVM VM per node, or --backend container (as root)
```

On Linux, `vk8s create` uses native mode unless `--backend` says
otherwise; on macOS the default is a VM per node. Native mode needs `unsquashfs` (squashfs-tools), `cpio`, `iptables` and
`kubectl`, and runs sudo for the root steps, printing each. The KVM VM
backend on arm64 is built but unverified (no arm64 KVM host was available).

The macOS binary is ad-hoc signed with the Hypervisor entitlement (no Developer
ID). Download it with curl as above: a browser marks the file quarantined,
and Gatekeeper then refuses it until you run
`xattr -d com.apple.quarantine vk8s`. On first use it downloads the guest
assets of the same release and checks each archive's SHA-256 against the
hashes built into the binary.

## Quick start

```sh
vk8s create demo               # downloads the pinned guest assets once, boots, connects
kubectl get nodes              # vk8s_demo is now the current context
vk8s create big --nodes 2 --backing-store etcd   # 1 control plane + 2 worker VMs
vk8s list                      # NAME STATUS CONNECTED AGE (--output json)
vk8s connect demo -- kubectl get ns
vk8s delete demo               # graceful power-off; removes the vk8s_demo context
```

A cluster with one worker is ready in about 22 s; a single node in a few
seconds. A 3-VM etcd cluster passes the CNCF certified-conformance suite:
450 passed, 0 failed. So does a classic-mode vcluster (vcluster's
conformance profile) over a vk8s host cluster.

## Commands

| Command | What it does |
|---|---|
| `create NAME [--nodes N] [--backing-store sqlite\|etcd] [--cpus N] [--memory MiB] [--port P]` | boot a cluster; connects unless `--connect=false` |
| `create NAME --upgrade [...]` | recreate on the current assets with new settings, keeping the data |
| `create NAME --host-kubeconfig F [--host-namespace NS] [-f vcluster.yaml]` | classic mode: the control plane in a VM, workloads synced to a host cluster |
| `connect NAME [--print] [--update-current=false] [-- CMD]` | add the context, print the kubeconfig, or run a command |
| `list`, `describe NAME [--config-only] [-o json]`, `logs NAME [COMPONENT]` | inspect |
| `pause NAME`, `resume NAME` | put every VM of a cluster to sleep (hibernate; see [Sleep when idle](#sleep-when-idle)) or wake it |
| `snapshot create NAME PATH [--format vm\|open]`, `restore NAME PATH` | vm (default): a tar.gz of the control plane's disk with vk8s's metadata.json first (the layout is vk8s's own; vind's archive also starts with a metadata.json but holds Docker volumes, so the two do not interchange). open: vcluster's snapshot archive of the store, standalone clusters only, no pause (docs/SNAPSHOT.md). restore reads either |
| `node add NAME [--count N]`, `node delete NAME NODE [--drain=false]` | add or remove worker VMs |
| `cache start\|stop\|status` | the shared pull-through image cache that every cluster uses |
| `cache prune [docker.io\|registry.k8s.io\|ghcr.io\|quay.io]` | empty the whole cache, every blob of all registries (a REGISTRY: only that one), and give the space back to the host; see [Image cache](#image-cache) |
| `assets prune [--dry-run]` | remove superseded guest asset versions from ~/.vk8s/assets |
| `delete NAME [--delete-context=false]` | graceful stop and cleanup |

## Sleep when idle

A cluster sleeps after 15 minutes with no Kubernetes API use
(`vk8s create --idle-sleep D`, or `VK8S_IDLE_SLEEP`; minutes, or a
duration such as `90s` or `1h30m`; `0` never sleeps). "No API use"
means no connection through the cluster's API port: kubectl, a client,
a `kubectl logs -f` or a watch all keep it awake. Workloads inside the
cluster do not: a sleeping cluster's background work pauses (a Job, a
build, a CronJob that comes due) and continues when the cluster wakes.
For long unattended jobs, create the cluster with `--idle-sleep 0` or a
longer limit.

Asleep, each VM hibernates: it stops, its RAM goes into a file in its
folder, and the VM process keeps a few MiB (a cluster with one worker
went from 1637 MB to 14 MB on an M2 Pro). The next connection to the API
port wakes it; the API answers in under a second, and memory comes back
page by page as the guest uses it. Pods keep their memory and their
connections inside the cluster; a connection to an outside server may
have been dropped by that server. Only the API port wakes a cluster:
traffic to a NodePort or a LAN address does not. `vk8s list` shows a
sleeping cluster as `hibernated`. If the VM process ends while it sleeps
(a reboot), the cluster boots again from its disk, as after a power cut.

## Image cache

`vk8s create` starts a small VM (`~/.vk8s/cache`) with CNCF distribution
v3.1.2 as pull-through registries for docker.io, registry.k8s.io, ghcr.io
and quay.io. Every cluster's containerd pulls through it and falls back to
the upstream when it does not answer. `VK8S_CACHE=off` skips it.

- There is no size cap. You decide when to free space.
- A cached image expires 7 days (`proxy.ttl: 168h`) after it was cached.
  (Planned: 3 days after its last use, with a Bend registry.)
  distribution v3.1.2 sets the expiry once, when it fetches a blob or a
  manifest from the upstream; a pull served from the cache does not
  extend it. The registry then deletes it, and the guest's fstrim (every
  10 min) gives the blocks back to the host.
- `vk8s cache status` shows the state, the size of each registry and the
  total (measured in the cache VM with `du`; the last measurement when the
  cache is stopped), the size that `data.img` holds on the host (allocated
  blocks, not its sparse length) and the expiry.
- `vk8s cache prune` empties the whole cache: every cached blob of all
  four registries, whatever its age (there is no expired-only mode).
  `vk8s cache prune REGISTRY` empties one registry. The prune stops the
  registry, removes its storage, restarts it empty about 5 s later and runs
  fstrim, so the space returns to the host now. It prints each registry's
  size before the prune and what `data.img` freed. Running clusters keep
  working: they pull from the upstream while the registry restarts. A
  stopped cache is started for the prune and stopped again after it.

## Shared layer store

VM nodes share image layers by default; `VK8S_LAYERS=0 vk8s create
NAME` turns the shared layer store off. The host keeps each image layer
once, as one read-only squashfs image `~/.vk8s/layers/<hex>.sqfs`
(`src/layers/sqfs.bend`, `docs/ref/layers-sqfs.md`). Each VM node sees
the store read-only at `/mnt/layers-store` and loop-mounts the images
its pods use under `/mnt/layers`. Container-mode and native nodes unpack
per node as before. It needs guest assets with the layer image
snapshotter (the `loop` module and `Snapd.ensure`); older assets ignore
the store and unpack per node.

The store fills itself while nodes pull:

- **Who asks.** The node's snapshotter asks when containerd prepares a
  layer that the store does not have. containerd then sends the image's
  name and digests as labels (`disable_snapshot_annotations = false`,
  `src/guest/plan.bend:2642`). There is no ask for images that
  `ctr images import` loads, or for a registry that the image cache does
  not serve (`Ask.of_labels.v2`, `src/layers/ask.bend:119-130`).
- **The wait.** The node waits at most 60 s for the answer
  (`src/layers/ask.bend:337-338`). Other snapshotter calls go on while it
  waits (`host/snapshotter.bend:31-38`).
- **The fallback.** When the layer is still not in the store, the node
  unpacks it on its own disk, as it does without the store. This happens
  after a "no", after 60 s with no answer, or when the filler does not
  run. A pull never fails because of the ask
  (`host/snapshotter.bend:42-47`).
- **The filler.** `vk8s layers serve` answers the asks. It listens on
  `127.0.0.1:32000` (`src/layers/ask.bend:330-331`); a node reaches it as
  `10.0.2.2:32000`. It fetches the image by its manifest digest from the
  image cache, checks every digest, and publishes the layers. So it
  fills only public images that the image cache can read. A private
  image gets a "no", and the node unpacks it.
- **Start and log.** `vk8s create` starts the filler unless
  `VK8S_LAYERS=0` is set or something listens on the port already
  (`host/vk8s.bend:722-726`, `src/layers/serve.bend:271-272`). Its log
  is `~/.vk8s/layers-serve.log` (`src/layers/serve.bend:275-276`). One
  filler serves every cluster, and nothing stops it, as nothing stops
  the image cache (`host/vk8s.bend:717-721`). When it does not start,
  `vk8s create` prints a warning and the nodes unpack their layers
  themselves (`host/vk8s.bend:714-715`).
- **Caps.** At most 4 image fills, 64 waiting asks and 128 connections
  at once (`src/layers/serve.bend:45-54`). Past a cap the answer is "no"
  ("the filler is busy") and the node unpacks the layer itself. Asks for
  one image share one fill.
- **Blobs.** An automatic fill removes each compressed blob from
  `~/.vk8s/oci` after it publishes the layer, because the image cache
  keeps a compressed copy (`Fill.blob.drop.v2`,
  `src/layers/fill.bend:983-989`; `host/layers/serve.bend:172`).

Two hidden commands work on the store by hand:

- `vk8s layers fill IMAGE` fills the store with one image from the image
  cache. It keeps the compressed blobs in `~/.vk8s/oci` for 72 h
  (`host/layers/fill.bend:1101-1104`).
- `vk8s layers gc` removes layers that no node holds and that no fill
  used for 72 h (`src/layers/store.bend:44-45`). It keeps every layer a
  node of any cluster holds, including a stopped one.

Each layer has its own lock in `~/.vk8s/layer-locks`. A fill and a gc
can run at the same time, and two fills of one layer publish it once
(`host/layers/fill.bend:57-65`).

## Classic mode

```sh
vk8s create vc --host-kubeconfig ~/.kube/host.yaml        # namespace vcluster-vc on the host
vk8s create vc --host-kubeconfig host.yaml -f docs/examples/conformance-classic.yaml
vk8s delete vc                                            # also removes what it made on the host
```

The virtual control plane runs in a VM. vcluster's syncer, rewritten in
Bend, places pods, services, configmaps, secrets and the rest on the host
cluster. Its fake kubelet serves `kubectl logs`/`exec`. The API server
reaches webhooks, aggregated APIs and pods through a konnectivity agent on
the host (docs/DESIGN.md).

## Building from source

```sh
scripts/guest/fetch-assets.sh  # pinned public binaries -> out/assets/v1.36.6/bin
scripts/guest/images.sh        # preloaded add-on images (optional)
scripts/guest/build.sh         # kernel, initramfs, assets disk -> ~/.vk8s/assets/v1.36.6
scripts/build-mac.sh           # out/vk8s, signed for Hypervisor.framework
VK8S_ASSETS=~/.vk8s/assets/v1.36.6 out/vk8s create demo
```

`scripts/release-assets.sh` packs one arch's assets for a release and pins
their SHA-256 in src/cli/manifest_<arch>.bend; a released binary needs
nothing else. The arm64 release carries `vk8s-darwin-arm64` and
`vk8s-linux-arm64` (the same arm64 assets), the amd64 release
`vk8s-linux-amd64`. See docs/RELEASE.md.

## A Linux dev VM on the Mac

`scripts/dev/linux-vm.sh` boots a Debian trixie arm64 VM with systemd
under vk8s's bend-vmm, shares this repository at `/repo` and prints an
ssh command (`127.0.0.1:2222`, user `dev`, passwordless sudo). Use it to
run `vk8s-linux-arm64` in container, native or gVisor mode on a Mac. CI
builds and boot-tests the image (job `dev-vm`). See docs/ref/dev-vm.md.

## Verification

`bend PROOF.bend` (ALL PROOFS CHECK, also with `--verdict`) and
`scripts/check.sh` (proofs, the ratchet of laws/done, tests, and host
compile) gate every change. Laws transcribe vcluster's own Go tests;
`scripts/conformance.sh` runs sonobuoy, and `scripts/soak.sh` runs the soak.
