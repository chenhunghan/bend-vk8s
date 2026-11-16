# Native mode on a Linux host: the host side (N3, N4, N5)

`vk8s create NAME --backend native` runs a virtual cluster on this Linux
host with no VM. This document records the decisions of
docs/ref/explore-linux-hosts.md Phase 5, N3 to N5, and what CI proves.
The pure layer (N1, N2) is in `src/standalone/native.bend` (#46). The host
side is in:

- `src/standalone/native_host.bend` (`NHost`): every decision, as data.
  Its spec is `laws/native_host.bend`, proven in `proofs/native_host.bend`.
- `host/vk8s.bend` (`Vk8s.nat.*`): runs the argument lists.
- `host/init.bend` (`NInit`): the supervisor that the unit runs.
- `src/standalone/join.bend` (`Join.install`): the installing join
  script.

vcluster standalone's runtime is closed source (`pkg/pro/standalone.go`).
Its public `install-standalone.sh` and docs are the reference. The values
are vk8s design unless a law names their source.

## Shape

| | vcluster standalone | vk8s native |
|---|---|---|
| unit | `vcluster.service`, one per host | `vk8s-NAME.service`, one per cluster |
| runs | `$DATA_DIR/bin/vcluster start` | `/var/lib/vk8s/NAME/vk8s native` (this binary, copied in) |
| data | `/var/lib/vcluster` | `/var/lib/vk8s/NAME` (root, 0700) |
| user-visible files | `/etc/vcluster` | `~/.vk8s/clusters/NAME` (cluster.env, kubeconfig, `share/` with logs) |
| restart | `Restart=always`, `RestartSec=5s` | the same |
| kill | `KillMode=process` | `KillMode=control-group` (stop ends every process the unit started) |
| cgroup | `Delegate=yes` | the same |
| node on the control plane | yes (default) | yes for the host's first native cluster (see "Several clusters") |

The CLI runs as the user. Each step that needs root runs as an argument
list through `sudo` (no `sh -c`), and the CLI prints it first as
`+ sudo ...` (`NHost.show`). The unit runs as root.

## N3: the unit, create and delete

`NHost.unit` writes the unit text. Laws `native.unit_text`,
`native.unit_restart`, `native.unit_kill_mode`, `native.unit_delegate` and
`native.unit_exec` pin it. The unit's environment is what `NInit.main`
reads: `VK8S_DATA`, `VK8S_SHARE`, `VK8S_NAME`, `VK8S_STORE`,
`VK8S_NODE_IP`, `VK8S_PORT`, `VK8S_HOST_NODE`, `VK8S_ARCH`, `VK8S_RESOLV`
and `VK8S_JOIN_INSTALL`.

Create does these steps:

1. Preflight (N4).
2. `~/.vk8s/clusters/NAME/{cluster.env,port,share}` (the user's).
3. `NHost.prepare_cmds`: the data dir, this binary installed into it,
   busybox and flannel's manifest from `vk8s.cpio`, and the role sets.
4. flannel's manifest for a host (`NHost.flannel`), into the data dir.
5. `NHost.install_cmds`: `install` the unit file,
   `systemctl daemon-reload`, `systemctl enable --now`.
6. Wait for `share/kubeconfig.yaml`. The host-owned kubeconfig is then
   made as for a VM (`Vk8s.own_kubeconfig`).

The supervisor runs `NHost.boot`:

- With the host node: the PKI, the control plane, a node reset, the VM's
  `Plan.node` (containerd, the kubelet, kube-proxy, flannel, CoreDNS, the
  join material), and the kubeconfig.
- Without the host node: `Native.plan` (the control plane only).

`NHost.boot` changes the VM's steps for a host (`NHost.extra`), relocates
them (`NHost.rules`: ports, node paths, then `Native.rules`), drops the
machine steps (`Native.strip`), and adjusts the waits and the image
platform (`NHost.post`). The node reset ends the pods that the last
start left (`cgroup.kill`), unmounts what they left under the data dir,
and starts containerd and the kubelet afresh, as a VM's reboot does.

Delete (`Vk8s.nat.delete`) does these steps:

1. `systemctl disable --now` (`NHost.stop_cmds`). `KillMode=control-group`
   ends the supervisor, the daemons and containerd's shims.
2. The pods' processes. They live in the kubelet's cgroups
   (`/sys/fs/cgroup/kubepods`), outside the unit's. One write to
   `cgroup.kill` ends them all (Linux 5.14+).
3. Every mount under the data dir, the last mounted first
   (`NHost.mounts_under` on `/proc/self/mountinfo`, `umount -l`).
   containerd keeps the pods' network namespaces under its state dir
   (`netns_mounts_under_state_dir`), so this step finds them too.
4. The emptied kubepods cgroups.
5. iptables: `NHost.ipt_clean` cuts each `*-save` output (IPv4, IPv6,
   nf_tables and legacy) into tables. Only a table that holds a `KUBE-`,
   `FLANNEL-` or `CNI-` line goes back to `*-restore`, without those
   lines. Other tables (Docker's, for example) are not rewritten.
6. `NHost.remove_cmds`: `cni0` (and `flannel.1` if a vxlan backend made
   it), `/run/flannel`, the CNI plugins' state for `cbr0`, `/opt/vk8s`, the
   kubelet's links to the pod logs, the data dir (`rm -rf
   --one-file-system`), the unit file, `daemon-reload`, and the cluster
   dir.

Law `native.delete_leaves_nothing` (and `.control_plane`): every unit,
file, dir and link that create makes (`NHost.made`) is one that a delete
command removes (`NHost.removes`). Law `native.delete_stops_first`: the
unit stops before anything is removed.

## N4: binaries, preflight, several clusters per host

**Binaries: extracted once into the data dir.** The native cluster runs
from the node and control-plane role sets (`node.img`,
`control-plane.img`, and `images.img` when present). `unsquashfs` extracts
them into `/var/lib/vk8s/NAME/bin`. GNU `cpio` extracts busybox and
flannel's manifest from `vk8s.cpio`.

The other choice was a read-only loop mount. We did not take it, for
these reasons:

- `Plan.bin()` is one dir. Two set images would need an overlay mount on
  top of the two loop mounts. That is three root mounts per cluster.
- The unit must restore the mounts after each reboot (an
  `ExecStartPre=` or mount units). Delete must unmount them, and a failed
  unmount leaks a loop device.
- Extraction needs no root mount, survives reboots, and `rm -rf` undoes
  it.

The cost is the unpacked size of the sets per cluster (scripts/guest/sizes.sh
prints it). The sets stay compressed in `~/.vk8s/assets`.

**Preflight** (`NHost.preflight`). Create stops before it changes anything
when one of these is missing:

- a tool: `sudo`, `systemctl`, `unsquashfs`, `cpio`, `ip`,
  `iptables-save`, `iptables-restore`, `kubectl`, `perl`;
- systemd (`/run/systemd/system`);
- cgroup v2;
- for a host node: the modules `overlay` and `br_netfilter`, and the
  sysctls `net.ipv4.ip_forward=1` and `net.bridge.bridge-nf-call-iptables=1`.

The message names the exact command, for example
`- run: sudo sysctl -w net.ipv4.ip_forward=1` (law
`native.preflight_commands`). vk8s does not run these commands itself,
because they change the host for every user.

**What the laws pin, and how native moves it.** `laws/plan.bend` pins the
VM's literals. Native mode keeps them in the plan and rewrites them per
cluster (`NHost.port_rules`, `NHost.node_rules`, `Native.rules`):

| pinned in the VM plan | native cluster with API port P (picked from 10000..12999) |
|---|---|
| `/var/lib/vcluster` (85 laws) | `/var/lib/vk8s/NAME` |
| `/var/lib/vk8s-host` (the 9p share) | `~/.vk8s/clusters/NAME/share` |
| API `--secure-port=6443`, `bindPort`, `:6443`, the default endpoints | P |
| join server 8443 | `19000 + P mod 3000` (`C.Cli.join_port`, the VM's forward) |
| etcd 2379, 2380 | `22000 + P mod 3000`, `25000 + P mod 3000` |
| etcd and kine metrics 2381 | `28000 + P mod 3000` |
| kine socket | already a unix socket in the data dir |
| controller manager 10257, scheduler 10259 | `--secure-port=0` (no HTTPS port) |
| `/run/containerd`, `/etc/containerd`, `/etc/kubernetes` | under `/var/lib/vk8s/NAME/node` |
| `/opt/cni/bin`, `/etc/cni/net.d` | `/opt/vk8s/cni/{bin,net.d}` (vk8s's own, so that delete never touches the distribution's) |
| image cache at `10.0.2.2:1500x` (the VM's NAT) | `127.0.0.1:1500x` |

Laws: `native.ports`, `native.wait_ports`, `native.join_server_port`,
`native.no_fixed_cm_port`, `native.no_fixed_scheduler_port` and
`native.node_paths`. `tests/native_host.bend` checks the whole plan: no
6443, 8443, 2379-2381, VM path, fixed host path or `10.0.2.2` remains.

**One host node per host.** The control plane is fully per cluster. A
node is not, because kubelet ports 10250 and 10248, the `cni0` bridge,
flannel's `/run/flannel`, kube-proxy's `KUBE-` chains and the
`/sys/fs/cgroup/kubepods` cgroup belong to the host. So the first native
cluster on a host also runs the host node (`HOST_NODE=1`), as vcluster
standalone does. Later clusters are control planes only, and their nodes
join by token. The same is true when another kubelet already runs on the
host (`/sys/fs/cgroup/kubepods` exists, for example k3s or kind).
Per-cluster network namespaces (Phase 5 N6, shared with container mode)
would lift this limit.

## N5: nodes

- **Real Linux nodes** join by token. `vk8s token create NAME` prints
  `curl -fsSLk "https://IP:JOIN/node/join?token=..." | sh -s --` with the
  native cluster's address and join port (`JOIN_ENDPOINT` in cluster.env).
  A native cluster's join server (`VK8S_JOIN_INSTALL=1`) answers with
  `Join.install` of the script. It installs the node bundle and then
  joins:
  1. It gets the bundle: loft-sh/kubernetes v1.36.6's full release
     archive for the node's arch, checked against the SHA-256 that
     scripts/guest/fetch-assets.sh pins. `--bundle-path` gives a local
     copy, and `--repository-url` a mirror.
  2. It installs kubelet, kubeadm, containerd, the runc shim, runc, ctr
     and the CNI plugins in `/opt/vk8s/node/bin` (`--binaries-dir` moves
     them).
  3. It writes containerd's config, a `vk8s-containerd.service` unit and
     the `kubelet.service` unit that kubeadm drives. It imports the pause
     image.
  4. It runs `kubeadm join` from the bundle against that containerd. The
     script no longer does `exec kubeadm`.

  `--reset-only` runs `kubeadm reset`, then removes the units and the
  installed files. Laws: `join.script_installs_bundle` and its siblings
  in laws/join.bend. A control-plane join is still refused.
- **Worker VMs** (`--nodes N`) are not started for a native cluster.
  bend-vmm's VMs use user-mode NAT: a VM reaches the host at 10.0.2.2,
  but the host's API server cannot reach a VM's kubelet (logs, exec), and
  flannel's host-gw routes cannot reach a VM's pods. `create --backend
  native --nodes N` with N > 0 stops and says to join nodes by token
  (`NHost.nodes_msg`). The VM backend's own workers do not change.

## CI evidence

Job `native-smoke` (tests/native_smoke.sh) on ubuntu-latest (systemd,
passwordless sudo, x86_64) does these steps:

1. Preflight: with forwarding off, create fails and names the command.
2. Create: the unit is active, the API answers `/readyz`, node `demo` is
   Ready, and a pod runs on it.
3. A second cluster runs at the same time, control plane only, on its
   own port. It is deleted, and the first cluster still answers.
4. `token create`: the join server answers the installing script, and
   `sh -n` accepts it.
5. Delete: no unit, data dir, cluster dir, process, pod process, mount,
   kubepods cgroup, `KUBE-`/`FLANNEL-`/`CNI-` rule, `cni0` or extra veth
   remains.

The job prints the time of each step to the job summary.

A second node does not join on the runner. The runner is already demo's
node: its kubelet ports, `cni0` and kube-proxy's rules are taken. Also,
the runners of a workflow cannot reach each other. To join a real node,
run the printed command on another Linux machine that can reach the host
on the API port and the join port.

## Not done

- Per-cluster network namespaces, so that each cluster can have its own
  host node (N6).
- Worker VMs for native clusters: this needs a VM network that the host
  can route to.
- `pause`, `resume`, `snapshot`, `restore` and `upgrade` for native
  clusters.
- The certified conformance run and a distro matrix beyond Ubuntu
  (maintainer).
- `--backend native` as the effective default on Linux. `Backend.effective`
  keeps vm until the regression subset passes (law
  `backend.effective_vm`).
