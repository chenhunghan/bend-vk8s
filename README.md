# bend-vk8s

vcluster, rewritten in [Bend](https://bend-lang.com), running virtual
Kubernetes clusters in [bend-vmm](https://github.com/chenhunghan/bend-vmm)
microVMs instead of Docker containers. One binary, `vk8s`, embeds the VMM.
Its CLI follows `vcluster … --driver docker` (vind). See docs/DESIGN.md for
the architecture and docs/STATUS.md for where it stands against
docs/GOAL.md.

## Install (macOS 15+, Apple Silicon)

```sh
curl -fLo vk8s https://github.com/chenhunghan/bend-vk8s/releases/download/v1.36.6-92057045/vk8s-darwin-arm64
chmod +x vk8s && sudo mv vk8s /usr/local/bin/
```

Nothing else to install. vk8s loads OpenSSL 3 at run time for every TLS
connection the host makes: the image cache and the shared layer store
reaching the registries, and the Kubernetes client (`vk8s token`,
`vk8s node add`, `vk8s certs rotate`, classic mode). macOS ships no
OpenSSL 3, so the release carries it (docs/ref/macos-tls.md): on first
use vk8s fetches `libssl.3.dylib` and `libcrypto.3.dylib` with the guest
assets, checks their SHA-256 and uses them. `BEND_KUBE_LIBSSL` and
`BEND_KUBE_LIBCRYPTO` name other files. If OpenSSL cannot load,
`vk8s create` warns once and runs without the image cache and the layer
store (nodes pull images themselves, slower), and the commands that need
the Kubernetes API stop with a message naming the fix. Linux hosts need
the `libssl3` package, which most distributions install.

## Install (Linux arm64)

```sh
curl -fLo vk8s https://github.com/chenhunghan/bend-vk8s/releases/download/v1.36.6-92057045/vk8s-linux-arm64
chmod +x vk8s && sudo mv vk8s /usr/local/bin/
vk8s create demo                    # native on Linux by default
vk8s create demo --backend vm       # or a KVM VM per node, or --backend container (as root)
```

On Linux, `vk8s create` uses native mode unless `--backend` says
otherwise; on macOS the default is a VM per node. Native mode needs `unsquashfs` (squashfs-tools), `cpio`, `iptables` and
`kubectl`, and runs sudo for the root steps, printing each. The KVM VM
backend on arm64 is built but unverified (no arm64 KVM host was available).
Linux x86_64: `vk8s-linux-amd64` from release v1.36.6-a65797c8.

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
vk8s create sandbox --gvisor   # adds the gvisor RuntimeClass (runtimeClassName: gvisor)
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
| `create NAME [--nodes N] [--backing-store sqlite\|etcd] [--gvisor] [--cpus N] [--memory MiB] [--port P]` | boot a cluster; connects unless `--connect=false` |
| `create NAME --upgrade [...]` | recreate on the current assets with new settings, keeping the data |
| `create NAME --host-kubeconfig F [--host-namespace NS] [-f vcluster.yaml]` | classic mode: the control plane in a VM, workloads synced to a host cluster |
| `connect NAME [--print] [--update-current=false] [-- CMD]` | add the context, print the kubeconfig, or run a command |
| `list`, `describe NAME [--config-only] [-o json]`, `logs NAME [COMPONENT]` | inspect |
| `pause NAME`, `resume NAME` | put every VM of a cluster to sleep (hibernate; see [Sleep when idle](#sleep-when-idle)) or wake it |
| `snapshot create NAME PATH [--format vm\|open]`, `restore NAME PATH` | vm (default): a tar.gz of the control plane's disk with vk8s's metadata.json first (the layout is vk8s's own; vind's archive also starts with a metadata.json but holds Docker volumes, so the two do not interchange). open: vcluster's snapshot archive of the store, standalone clusters only, no pause (docs/SNAPSHOT.md). restore reads either |
| `node add NAME [--count N]`, `node delete NAME NODE [--drain=false]` | add or remove worker VMs |
| `cache start\|stop\|status` | the shared pull-through image cache that every cluster uses |
| `cache prune [docker.io\|registry.k8s.io\|ghcr.io\|quay.io]` | empty the whole cache, every blob of all registries (a REGISTRY: only that one); see [Image cache](#image-cache) |
| `assets prune [--dry-run]` | remove superseded guest asset versions from ~/.vk8s/assets |
| `delete NAME [--delete-context=false]` | graceful stop and cleanup |

## Optional features

gVisor and the etcd backing store are off by default, and their binaries
are optional asset sets that vk8s fetches (SHA-256 checked) and attaches
only when a cluster asks for them: `vk8s create NAME --gvisor` adds the
`gvisor` set to every node and a `gvisor` RuntimeClass (pods that set
`runtimeClassName: gvisor` run under runsc; runc stays the default), and
`--backing-store etcd` adds the `etcd` set to the control plane. `create`
names the features that are off and their flags in one line. The choice
is kept in the cluster's cluster.env (`GVISOR=1`, `STORE=etcd`), so
`create --upgrade`, `node add`, `restore` and `certs rotate-ca` attach the
same sets (`create --upgrade --gvisor=false` turns gVisor off). On the
container backend the node host VM of a Mac is shared by every container
cluster, so gVisor there is the node host's: it has the gvisor set once a
cluster asked for it. NetworkPolicy (kube-router) is always on.

## Host-integrated workloads

Three `vk8s create` options give every VM node of a cluster a part of
the host, for a workload that works on the host's files and talks to a
program on the host (VM backend only; the container and native backends
and classic mode refuse them):

```sh
vk8s create dev \
  --mount "$HOME" --mount "$HOME/work:rw" \
  --host-socket "/run/user/$(id -u)/app.sock=$HOME/Library/Application Support/app/app.sock" \
  --node-setup "$HOME/work/node-setup.sh"
```

- `--mount HOSTDIR[:rw]` (up to 6): the directory appears in each node
  at the same absolute path, read-only unless `:rw`, mounted before
  containerd and the kubelet start, so pods use it as a `hostPath`
  volume. Mounts nest: a writable sub-folder of a read-only mount works,
  in any order of the flags. The path must be an existing directory with
  no comma or newline, outside the node's own directories (`/etc`,
  `/usr`, `/var/lib`, `/run`, ...). Every file belongs to the host user:
  the node sees the host's uid, gid and mode, so a pod running as that
  uid (`runAsUser`) or as root writes a `:rw` mount, and any other uid
  gets what the mode gives others. Files a pod creates belong to the
  host user on both sides, whoever made them; `chmod` reaches the host,
  `chown` changes nothing. A Linux binary runs from a mount. A read-only
  mount refuses every write on the host side too.
- `--host-socket GUESTPATH=HOSTPATH` (up to 8): each node listens on the
  Unix socket GUESTPATH (mode 0666, its directories made), and every
  connection reaches the host's Unix socket HOSTPATH, which may hold
  spaces, be longer than a socket path and appear after the cluster
  started. A pod mounts GUESTPATH as a `hostPath` of type `Socket`. A
  side that shuts down its writes still gets the other's answer.
- `--node-setup SCRIPT`: a path in the node, normally under a mount.
  PID 1 runs it with `/bin/sh` as root at every boot, after the mounts
  and the sockets and before containerd. Its output is in the node's
  logs (`~/.vk8s/clusters/NAME/share/logs/node-setup.log`); when it
  does not exit 0, `create` prints a warning and the node starts
  anyway. The node's root is a tmpfs: the script can write
  `/usr/local/bin`, `/etc` and `/var/lib` (but `/var/lib/vcluster` is
  the data disk, which outlives a boot), and all of it is gone at the
  next boot, when the script runs again. With a script, containerd
  imports `/etc/containerd/conf.d/*.toml` and has `/usr/local/bin`
  first on its PATH, so the script adds a runtime handler with a
  drop-in and a `containerd-shim-NAME-v2` binary:

  ```toml
  version = 3
  [plugins."io.containerd.cri.v1.runtime".containerd.runtimes.NAME]
    runtime_type = "io.containerd.NAME.v2"
  ```

The three are recorded in the cluster's cluster.env (`MOUNT_<i>`,
`HOST_SOCKET_<i>`, `NODE_SETUP`), so `create --upgrade`, `node add`,
`certs rotate-ca` and a restored snapshot keep them. On `create
--upgrade` a kind of flag that is given replaces that kind's record, and
the value `none` empties it (`--mount none`). The script does not run
again for `vk8s pause` and `resume`.

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

`vk8s create` starts the image cache on the host (`vk8s cache serve`, a
process of vk8s itself; its blobs in `~/.vk8s/cache/store`): pull-through
registries for docker.io, registry.k8s.io, ghcr.io and quay.io on
127.0.0.1:15001-15004. Every cluster's containerd pulls through it and
falls back to the upstream when it does not answer. `VK8S_CACHE=off`
skips it. It uses a few MiB of memory (the VM it replaced took 1 GiB).

- There is no size cap. You decide when to free space.
- A cached blob expires 72 hours (3 days) after its last use; every pull
  served from the cache is a use. An hourly sweep removes expired blobs.
- An image is not kept twice. Once the shared layer store holds a layer,
  the cache drops that layer's compressed blob at the first sweep 10
  minutes later, unless a node asked the cache for it meanwhile (nodes on
  the layer store never do; a node without it, `VK8S_LAYERS=0` or another
  backend, gets the blob from the cache or, after the sweep, through the
  cache from the registry). Manifests and configs stay for the 72 hours.
- `vk8s cache status` shows the state, the size of each registry and the
  total, the store's path and the expiry. A `data.img` left by the image
  cache VM of an older vk8s is named with its size.
- `vk8s cache prune` empties the whole cache, every cached blob of all
  four registries, whatever its age; `vk8s cache prune REGISTRY` empties
  one registry. Pruning all of them also removes an older vk8s's
  `data.img`. Running clusters keep working: they pull from the upstream.
- `vk8s cache start` stops the image cache VM of an older vk8s, if one
  runs, and starts the host cache in its place.
## Shared layer store

Nodes share image layers by default; `VK8S_LAYERS=0 vk8s create NAME`
turns the shared layer store off. The host keeps each image layer once,
as one read-only squashfs image `~/.vk8s/layers/<hex>.sqfs`
(`src/layers/sqfs.bend`, `docs/ref/layers-sqfs.md`). Each VM node sees
the store read-only at `/mnt/layers-store` and loop-mounts the images
its pods use under `/mnt/layers`. On a Linux host a node container binds
the store read-only, and a native cluster's host node reads it where it
is and loop-mounts the images under its own data dir,
`/var/lib/vk8s/NAME/node/layers`, which the unit's restart and
`vk8s delete` unmount (its snapshotter is the guest binary of the
assets' base disk, which needs glibc 2.38 on the host; with assets that
have no base disk the store stays off, and with `VK8S_LAYERS=1` create
says why). It needs guest assets with the layer image snapshotter (the
`loop` module and `Snapd.ensure`); older assets ignore the store and
unpack per node.

A node container and a native host node do not wait for a layer the
store lacks (`Ask.nowait.v4`, `src/layers/ask.bend`): containerd fetches
and unpacks it on the node, as with the store off, and that node keeps
its copy. The node's snapshotter asks the filler once its pull activity
has stopped for 3 s, so the fill does not slow the pod's start, and the
next node, or the next cluster, mounts the layer from the store. A layer
the store already holds is mounted from it, also over or under a layer
the node unpacked itself. A VM node waits for the fill, as before (the
same fill takes 1.2 s on a Mac and 4.4 s on a 4-core Linux runner, where
containerd's whole pull takes 2.7 s).

A VM node reads the layer images from a pack disk, not through the
share (`src/layers/pack.bend`, bend-vmm's `--pack`): one read-only
virtio-blk disk per VM that the images join as the node mounts them.
The node's snapshotter asks the filler for a layer the store holds
(`pack <vm> <key> <chain>`), the filler has the VM's control socket add
the image (`pack add PATH`) and answers where it is (`at <offset>
<length>`), and the node mounts that range through a loop device with
the offset and a size limit. When the node's last snapshot on a layer
goes, it unmounts the layer and the filler ends its entry (`drop`,
`pack drop OFFSET`). `<key>` is a random key the host writes into the
VM's share at each start, so only that node's root can ask for its
pack. `vk8s layers gc` keeps every layer that is live on a running or
hibernated VM's pack. The share stays for the store's probes, the
layers' records and as the fall back: no answer, a "no" (a filler from
before the pack answers so), or a failed mount ends in the loop mount
from the share. `VK8S_PACK=0 vk8s create NAME` starts the VMs without a
pack. A VM gets `VK8S_PACK=<vm>` on its kernel command line only when
its host started it with `--pack`, and a node uses the pack only then,
so older guest assets on this host and these assets on an older host
both keep the share. After a restart the pack is empty and the node
asks again for each layer its snapshots stand on; a hibernated VM keeps
its pack. Cold, a pod reads its 200 MB nginx root file system in 0.23
to 0.28 s from the pack and in 1.8 to 2.2 s through the share (an M5
Pro Mac; `scripts/bench/pack-read.sh`).

The store fills itself while nodes pull:

- **Who asks.** The node's snapshotter asks when containerd prepares a
  layer that the store does not have. containerd then sends the image's
  name and digests as labels (`disable_snapshot_annotations = false`,
  `src/guest/plan.bend:2642`). There is no ask for images that
  `ctr images import` loads, or for a registry that the image cache does
  not serve (`Ask.of_labels.v2`, `src/layers/ask.bend:119-130`).
- **The wait.** A VM node waits at most 60 s for the answer
  (`Ask.wait.max.v2`, `src/layers/ask.bend`). Other snapshotter calls go
  on while it waits (`host/snapshotter.bend`). A node container and a
  native host node wait only for a layer the store holds (the answer
  comes at once); for any other they keep the ask until the pull is over
  (`Ask.waits.v4`, `Ask.later.due.v4`).
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
  image gets a "no", and the node unpacks it. It talks to the image
  cache in plain HTTP on 127.0.0.1, so the nodes and the filler share
  one registry fetch for each blob. It takes a blob that the cache
  already stores as a hard link, with no copy. When the cache does not
  run, or does not answer a request with a 200, the filler asks the
  registry itself (`host/layers/fill.bend`, `Lf.fill.port.v4`).
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
  `src/layers/fill.bend:983-989`; `host/layers/serve.bend:172`). It
  also lapses the cache's copy, which then goes at the cache's first
  sweep 10 minutes later unless a node asked for it (`Store.lapse`,
  `src/oci/store.bend`; `Lf.blob.lapse`, `host/layers/fill.bend`;
  `docs/ref/layers-compress.md`).

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
nothing else but OpenSSL 3 on the host (see Install). The arm64 release carries `vk8s-darwin-arm64` and
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
