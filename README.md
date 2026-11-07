# bend-vk8s

vcluster, rewritten in [Bend](https://bend-lang.com), running virtual
Kubernetes clusters in [bend-vmm](https://github.com/chenhunghan/bend-vmm)
microVMs instead of Docker containers. One binary, `vk8s`, embeds the VMM.
Its CLI follows `vcluster … --driver docker` (vind). See docs/DESIGN.md for
the architecture and docs/STATUS.md for where it stands against
docs/GOAL.md.

## Quick start (macOS, Apple Silicon)

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
450 passed, 0 failed.

## Commands

| Command | What it does |
|---|---|
| `create NAME [--nodes N] [--backing-store sqlite\|etcd] [--cpus N] [--memory MiB] [--port P]` | boot a cluster; connects unless `--connect=false` |
| `create NAME --upgrade [...]` | recreate on the current assets with new settings, keeping the data |
| `create NAME --host-kubeconfig F [--host-namespace NS]` | classic mode: sync to a host cluster (in progress) |
| `connect NAME [--print] [--update-current=false] [-- CMD]` | add the context, print the kubeconfig, or run a command |
| `list`, `describe NAME [--config-only] [-o json]`, `logs NAME [COMPONENT]` | inspect |
| `pause NAME`, `resume NAME` | freeze or thaw every VM of a cluster |
| `snapshot create NAME PATH`, `restore NAME PATH` | tar.gz with metadata.json first, as vind writes |
| `node add NAME [--count N]`, `node delete NAME NODE [--drain=false]` | add or remove worker VMs |
| `cache start\|stop\|status` | the shared pull-through image cache that every cluster uses |
| `delete NAME [--delete-context=false]` | graceful stop and cleanup |

## Building from source

```sh
scripts/guest/fetch-assets.sh  # pinned public binaries -> out/assets/v1.36.6/bin
scripts/guest/images.sh        # preloaded add-on images (optional)
scripts/guest/build.sh         # kernel, initramfs, assets disk -> ~/.vk8s/assets/v1.36.6
scripts/build-mac.sh           # out/vk8s, signed for Hypervisor.framework
VK8S_ASSETS=~/.vk8s/assets/v1.36.6 out/vk8s create demo
```

`scripts/release-assets.sh` packs the assets for a release and pins their
SHA-256 in src/cli/manifest.bend; a released binary needs nothing else.

## Verification

`bend PROOF.bend` (ALL PROOFS CHECK, also with `--verdict`) and
`scripts/check.sh` (proofs, the ratchet of laws/done, tests, and host
compile) gate every change. Laws transcribe vcluster's own Go tests;
`scripts/conformance.sh` runs sonobuoy, and `scripts/soak.sh` runs the soak.
