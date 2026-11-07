# bend-vk8s

vcluster, rewritten in [Bend](https://bend-lang.com), running virtual
Kubernetes clusters in [bend-vmm](https://github.com/chenhunghan/bend-vmm)
microVMs. One binary, `vk8s`, embeds the VMM. See docs/DESIGN.md.

## Quick start (macOS, Apple Silicon)

```sh
scripts/guest/build.sh        # kernel, initramfs, assets disk -> ~/.vk8s/assets/v1.36.6
scripts/build-mac.sh          # out/vk8s (signed for Hypervisor.framework)
out/vk8s create demo          # about 3 s to a ready API
out/vk8s connect demo         # adds context vk8s_demo to ~/.kube/config and switches to it
kubectl get ns
out/vk8s connect demo --print > demo.yaml   # or: the kubeconfig on stdout
out/vk8s list | pause demo | resume demo | delete demo   # delete also removes vk8s_demo
```

Status: control plane (kine + kube-apiserver/controller-manager/scheduler
v1.36.6) works; the VM is not yet a node (kubelet/containerd next), and the
syncer (classic mode) is in progress. `bend PROOF.bend` is the gate.
