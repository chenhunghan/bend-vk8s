**Explorer report: running the vk8s control plane natively on macOS**

I changed nothing in the repository. All scratch work is in /tmp. No Go toolchain is available here, so nothing was compiled. Every claim about a build is marked as verified, from a published artifact, or from source reading only.

## Findings

### 1. Feasibility per component

**What runs in the control-plane VM today.**
- In standalone mode PID 1 runs the store, the apiserver, the controller manager, the scheduler and the join server (`src/guest/plan.bend:500-507`):
  ```
  Daemon{"kube-apiserver", ...}, WaitTcp{"127.0.0.1", 6443, 120000},
  Plan.default_endpoints(c), Daemon{"kube-controller-manager", ...},
  Daemon{"kube-scheduler", ...}, Plan.join_server(),
  ```
- The same VM is also a node. `Plan.boot` appends `Plan.node(c)` after `Plan.control_plane(c)` (`src/guest/plan.bend:737-746`). `Plan.node` starts containerd, kubelet and kube-proxy, applies flannel and CoreDNS, and writes the worker join material (`src/guest/plan.bend:694-735`).
- Classic mode has no node parts (`src/guest/plan.bend:1001`: "It has no local kubelet, containerd, flannel, kube-proxy, or kube-scheduler"). It runs apiserver, controller manager, store, syncer and konnectivity-server (`src/guest/plan.bend:1107-1120`).

**kube-apiserver and etcd: verified for darwin/arm64.**
- kubernetes-sigs/controller-tools publishes `envtest-v1.36.2-darwin-arm64.tar.gz`. It holds `kube-apiserver` (84 MB), `etcd` (26 MB) and `kubectl` (57 MB).
- I downloaded it to a scratch directory and read only the binary headers. Both binaries are Mach-O arm64 (magic `0xfeedfacf`, cpu `0x0100000c`).
- The build info embedded in kube-apiserver reads:
  ```
  path	k8s.io/kubernetes/cmd/kube-apiserver
  build	CGO_ENABLED=0 / GOARCH=arm64 / GOOS=darwin
  mod	k8s.io/kubernetes	v1.36.2
  ```
- etcd's build info reads `path go.etcd.io/etcd/server/v3`, `GOOS=darwin`, `CGO_ENABLED=0`.
- etcd also publishes official darwin-arm64 zips (`etcd-v3.6.8-darwin-arm64.zip`).

**Controller manager and scheduler: not verified by a build.**
- Nobody publishes darwin binaries. Kubernetes' own build lists them as Linux only (`kubernetes/hack/lib/golang.sh:23-28` for v1.36.6, `KUBE_SUPPORTED_SERVER_PLATFORMS`). Only the client set includes darwin (`hack/lib/golang.sh:41-49`).
- Code search on kubernetes main found no `go:build linux` file under `cmd/kube-controller-manager`, `cmd/kube-scheduler`, `cmd/kube-apiserver`, `pkg/scheduler` or `pkg/controller`. I searched the default branch, not the v1.36.6 tag.
- The controller manager imports volume plugins (`cmd/kube-controller-manager/app/plugins.go:28-37`: csi, iscsi, fc, flexvolume, hostpath, nfs). The Linux-specific code under them has non-Linux stubs. Examples from v1.36.6:
  - `pkg/volume/util/hostutil/hostutil_unsupported.go:1`: `//go:build !linux && !windows`
  - `staging/src/k8s.io/mount-utils/mount_unsupported.go:1`: `//go:build !linux && !windows`
  - `pkg/volume/emptydir/empty_dir_unsupported.go:1`: `//go:build !linux`
- The apiserver's own `/proc` use sits in `apiserver/pkg/server/loadmetrics`, which has `cpu_linux.go` and `cpu_others.go`. This is seen on main only and I did not read it. The prometheus process collector has a darwin file in the vendor tree.
- Nothing in the apiserver or controller manager needs cgroups. Only the kubelet and kube-proxy do, and those stay in worker VMs.

**kine: feasible, not verified.**
- `pkg/drivers/sqlite/sqlite_cgo.go:1` is `//go:build cgo` and uses mattn/go-sqlite3. `sqlite_nocgo.go:1` is `//go:build !cgo` and uses modernc.org/sqlite.
- Official kine releases for v0.17.5 carry Linux binaries only, with `-nocgo` variants. Both would need a darwin build.

**Other binaries.**
- kubectl: official darwin build.
- konnectivity-server: no darwin release (the v0.37.1 release has no assets). Not verified.
- kubeadm: no darwin evidence. Its server targets are Linux only. kubeadm hard-codes `KubernetesDir = "/etc/kubernetes"` (`kubernetes/cmd/kubeadm/app/constants/constants.go:38`). Not verified for darwin.
- The loft-sh/kubernetes bundle that vk8s fetches has Linux amd64 and arm64 assets only (`scripts/guest/fetch-assets.sh:3-8`, `:26`). A darwin asset set would be a new build and pin chain.

**vcluster itself has no native control plane.**
- Its release config builds the `vcluster` control-plane binary for Linux only (`vcluster/.goreleaser.yaml:41-42`, `goos: - linux`, `main: ./cmd/vcluster`). Only the CLI builds for darwin (`.goreleaser.yaml:64-66`, `main: ./cmd/vclusterctl`).
- This is from the cloned HEAD 3a0085b6, not the pinned a8ab30e.

**Bend host programs.**
- **Effects with a macOS path already:**
  - `host/effs/proc.c:52` guards `addclosefrom_np` with `#ifndef __APPLE__`, and `POSIX_SPAWN_SETSID` is guarded.
  - `host/effs/tls_server.c:15` says "an epoll (Linux) or kqueue (macOS) descriptor". The kqueue branch is at `:1089-1130`.
  - `host/effs/sys.c:9,47,63` guard the Linux-only power-key and `reboot` calls. The effect still compiles elsewhere.
- **OpenSSL is the real macOS dependency.** `host/effs/tls_server.c:143-151` dlopens `libssl.so.3`, then `/opt/homebrew/opt/openssl@3/lib/libssl.3.dylib`, then `libssl.3.dylib`. bend-kube's `src/effs/tls.c` at main (lines 114-122) does the same. I found no `__linux__` guard in bend-kube's `tls.c` or `sys.c`. The pinned bend-kube-runtime 0.8.1.0 is not verified.
- **Why this matters.** Today OpenSSL arrives only in the guest, as a dynamic glibc build shipped on the assets disk (`docs/syncer-runtime.md:19-26`). The macOS `vk8s` has never run TLS. It shells out to `kubectl` (`host/vk8s.bend:432`: "could not create a join token (is kubectl installed?)").
- **What is not verified.** Whether macOS's system LibreSSL satisfies the dlopen list, and whether the kqueue splice path has ever run. `tests/tls_server.sh:9` says its leak check is "Linux only". CI is Linux only (`.github/workflows/ci.yml`: `ubuntu-latest`, `ubuntu-24.04-arm`).
- **Supervisor.** `host/init.bend:383-426` (`Init.step`) executes Mount, Write, Run, Daemon, Spawn, WaitTcp, WaitFile, Modules, Stop and Log. A native supervisor needs only the subset without Mount and Modules. The plan hard-codes Linux paths and busybox:
  - `Plan.data()` is `/var/lib/vcluster` (`src/guest/plan.bend:36`).
  - `Plan.host_dir()` is `/var/lib/vk8s-host` (`:515`).
  - `Plan.busybox()` is `/bin/busybox`, and 26 steps are `Plan.bb(["sh", ...` scripts.
  - `Plan.link_kubeconfigs` writes under `/etc/kubernetes` (`:1183`). That directory is not writable by a macOS user. `kubeadm certs renew` cannot move it, because kubeadm hard-codes the path.
  - `host/kubelet_proxy.bend:155` hard-codes `/var/lib/vcluster/pki/`.

**Port collisions.** In a guest, every daemon has its own network namespace. Natively they would share the host's loopback, so these fixed ports would clash across clusters:
- kine metrics on `127.0.0.1:2381` (`src/guest/plan.bend:230`)
- etcd 2379, 2380 and 2381 (`:200-226`)
- the controller manager and scheduler, which get no `--secure-port` and so take 10257 and 10259 (`:334-359`, `:377-383`)
- konnectivity 8132, 8133 and 8134 (`:1072-1080`)
- the join server on 8443

### 2. Networking

**Today.**
- Every VM gets a NAT NIC on eth0 at `10.0.2.15/24` with a default route via `10.0.2.2`, and a LAN NIC on eth1 (`src/guest/plan.bend:102-113`).
- The control plane is `10.10.0.2` and worker i is `10.10.0.(2+i)` (`src/cli/cli.bend:1020-1023`).
- The LAN is `--lan DIR,ip=...` (`src/cli/cli.bend:1093`). Per `bend-vmm/README.md:30-34`, it is "one Unix datagram socket per VM, named by its MAC", carrying raw Ethernet frames, with no switch process. The host has no NIC on it, and macOS has no tap without root.
- Workers join `https://10.10.0.2:6443`. `Cli.api_endpoint` is `"10.10.0.2:6443"` (`src/cli/cli.bend:1060`). The kubeadm `controlPlaneEndpoint` and the `default/kubernetes` endpoint both use the node IP (`src/guest/plan.bend:135`, `:472-483`).
- The apiserver reaches kubelets directly on the LAN (`kubelet-preferred-address-types=InternalDNS,InternalIP,...`, `src/guest/plan.bend:293`).

**Workers reaching a native control plane.**
- The NAT gateway works. `bend-vmm/README.md:429-430`: "The host itself stays reachable as 10.0.2.2, which is the host's loopback: a service bound to 127.0.0.1 on the host is open to the guest."
- A native apiserver on `127.0.0.1:<port>` is reachable from every VM at `10.0.2.2:<port>`.
- The serving certificate already carries `10.0.2.2` (`src/guest/plan.bend:140`).
- Pods already reach `10.0.2.2` through the node's NAT. Classic mode depends on it, and `docs/STATUS.md:119-121` says a pod "read /version from the virtual API server through the host Service".
- Joining needs only a different server address and port in the discovery file and in `default/kubernetes`.

**Limits of the NAT path.**
- `bend-vmm/README.md:431-433`: "The guest holds at most 256 TCP connections and 128 UDP flows (the least recently used closes first...)".
- Every in-cluster API client of a worker VM would count against 256. client-go multiplexes watches over HTTP/2, which softens this. I did not measure it.
- A LAN host NIC does not exist today. Giving the host one would need a new bend-vmm feature.
- vsock exists (`bend-vmm/README.md:38-39`, `--vsock PATH`), but vk8s does not use it. Only the guest module is loaded (`scripts/guest/modules.txt:1`).

**Service IPs and flannel.**
- ClusterIPs and flannel host-gw are node-local and unchanged. flannel runs over the worker LAN, where pods keep MTU 1500 (`docs/STATUS.md:123-130`).
- The `default/kubernetes` endpoint would point at `10.0.2.2:<port>`. `Ep.standalone_endpoints` already takes the IP and port (`src/translate/endpoint.bend:539`).
- Pods reach the apiserver Service IP through kube-proxy DNAT, then the node's NAT.

**apiserver to kubelet, webhooks and aggregated APIs.**
- Kubelet connections use the `cluster` egress selector. `kubernetes/pkg/kubelet/client/kubelet_client.go:102` reads `networkContext := egressselector.Cluster.AsNetworkContext()`, and `cmd/kube-apiserver/app/server.go:254` does the same. Webhooks and aggregated APIs use the same type.
- A native apiserver cannot dial `10.10.0.x:10250` or pod IPs.
- vk8s already solved this for classic mode, where the VM is also outside the node network:
  - `Plan.egress_config` sets a `cluster` selection through a unix socket to konnectivity-server (`src/guest/plan.bend:1068-1070`).
  - The agent is a kube-system Deployment (`:1088`).
  - The server is bundled (`:1072-1080`), and the agent image is pinned (`:1083`).
- A native standalone control plane would reuse this design. The agent would run hostNetwork on a worker and dial `10.0.2.2:8132`, because it opens its own outbound connection. The agent exists only once one worker is Ready, so `kubectl logs` and `exec` wait for it.
- A per-worker `--forward` plus an HTTP-CONNECT proxy would cover kubelets only, not pod IPs.

**What vcluster does outside the node network.**
- vind avoids the problem. The control-plane and worker containers share one Docker network (`vcluster/pkg/cli/create_docker.go:626-627`, `--network`, `--network-alias`). It also turns konnectivity off: `// disable konnectivity by default` (`create_docker.go:978-980`).
- The OSS tree has stubs only for private-nodes konnectivity. `vcluster/pkg/pro/privatenodes.go:29-31`: `StartKonnectivity ... return NewFeatureError(licenseapi.VirtualClusterProDistroPrivateNodes)`. The same holds at `:42` for `WriteKonnectivityEgressConfig`.
- I did not look at pro binaries.
- Classic vcluster runs inside the host cluster's network, so it has no such problem. vk8s's VM does not, which is why vk8s added konnectivity (`docs/DESIGN.md:106-118`).

**Classic mode is the easy case.**
- Its VM already talks to the Mac only through loopback forwards and `10.0.2.2` (`src/cli/cli.bend:1065-1068`: API 6443, konnectivity 8132, fake kubelet 10250).
- Host-cluster pods reach it through host Services whose endpoints are `10.0.2.2:PORT` (`src/cli/cli.bend:1129-1150`).
- A native classic control plane would listen on those host ports directly. The syncer could use the original host kubeconfig, with no NAT rewrite (`src/cli/kubeconfig.bend:587`).

### 3. Parity

**Laws that pin the VM layout.** I list areas, not every case. The laws are the architect's, so existing ones stay untouched and new defs would carry laws under `# Proposed:`.
- `laws/cli.bend:71-78` (lan_ip), `:293-300` (forwards, join and api endpoints), `:380` (vmm_flags balloon).
- `laws/plan.bend`: the apiserver, controller manager, scheduler and kine flag laws (`:15-203`, `:273-278`), `plan.disks` (`:525`) and `plan.control_plane.join_server` (`:398`).
- `laws/classic.bend:51`: `K.KFlags.ip(K.Classic.kflags([])) == "10.10.0.2"`.
- `tests/cli.bend:121-126`, `tests/certs.bend:29-33`, `tests/konnectivity.bend`.
- No file carries a `FROZEN SPEC` header. A grep over `tests/` and `laws/` finds none.

**Per feature.**
- **Standalone mode.** A native control plane has no node. `controlPlane.standalone.joinNode.enabled` is in the supported list (`docs/CONFIG.md:23`, `laws/vcluster_config.bend:50` and `:165`), but nothing in `src` or `host` reads it. `docs/ref/vcluster-standalone.md:668` (D4) chose "always join". The default single-node cluster (`docs/DESIGN.md:95`) has no other node, so it would need a worker VM. Create time rises from about 4 s to the 2-node time of about 22 s (`docs/STATUS.md:487`).
- **Snapshot and restore.**
  - The VM snapshot is a pause, a `cp -c` clone of `data.img`, and a tar of exactly `metadata.json`, `cluster.env` and `data.img` (`host/vk8s.bend:1376-1403`, `docs/DESIGN.md:25`).
  - A native control plane has no disk image. It would need a new member list or a directory archive.
  - The open format (`docs/SNAPSHOT.md`) survives, but its dump runs through PID 1 and etcdctl in the guest (`src/guest/plan.bend:1249`, `host/snapshot_open.bend`). A native dump would run etcdctl on the Mac. It is also refused for classic mode today (`docs/SNAPSHOT.md`).
- **Cert rotation.** `Plan.certs_rotate` (`:1195`) relies on `/etc/kubernetes` links (`:1183`). A native version must regenerate kubeconfigs with `kubeadm init phase kubeconfig --kubeconfig-dir`, as `Plan.pki_steps` does (`:175-186`). The 24 h watcher and `Plan.certs_expiring` are pure and carry over. They need a long-lived native supervisor.
- **Upgrade.** `--upgrade` keeps the disk and reboots on new assets. Natively it would keep the directory and need a darwin asset set per Kubernetes version.
- **Join tokens.** They are Secrets in kube-system, and the join server reads them as `vk8s:join-server`. Unchanged, but the join server becomes a native TLS process (OpenSSL). `Cli.join_endpoint` is `10.10.0.2:8443` and would change (`src/cli/cli.bend:1057`).
- **Conformance.** Run (a) is 3 VMs with etcd, and run (b) is classic. Both need a re-run for any option (`docs/GOAL.md:21-27`).
- **GOAL sections and STATUS.** GOAL says "runs virtual Kubernetes clusters in bend-vmm VMs" (`docs/GOAL.md:3-5`) and §6 says "A fresh Mac needs only the binary" (`:99`). DESIGN's table maps the vind container to a control-plane VM (`:21`). A new footprint entry would belong in `docs/ref/footprint-decisions.md`, after M5.

### 4. Security and isolation

There is no security-review document in the repo. Only STATUS summarises it (`docs/STATUS.md:579-627`), so this section rests on that and on bend-vmm's README.

**Already true today.**
- bend-vmm is not sandboxed: "Not yet: the VMM is not sandboxed (it runs with your user's rights)" (`bend-vmm/README.md:454`).
- A guest can already reach the Mac's loopback services through `10.0.2.2` (`bend-vmm/README.md:429-430`) and whatever the Mac reaches. A VM-hosted apiserver can already be driven into SSRF against them.
- `data.img` holds the CA keys and sits in `~/.vk8s/clusters`, readable by the same user.

**Lost by going native.**
- The kernel and process boundary around the apiserver, etcd and controller manager. A bug there would give the user's rights directly: `~/.ssh`, `~/.aws`, `~/.kube/config` with other clusters' credentials, and the keychain.
- Containment of user-supplied flags. `vcluster.yaml` extraArgs reach the apiserver (`docs/STATUS.md:462-465`). In a guest, `--audit-log-path` writes into the guest. Natively it writes into the user's home.
- Resource limits. `--mem` is a hard ceiling for a VM. macOS has no cgroups. A runaway apiserver can use all RAM. Mitigations are `GOMEMLIMIT` and `GOMAXPROCS`.
- Loopback port isolation. Each native process listens on the host's loopback, visible to every local user. Metrics on 2381 are unauthenticated HTTP.
- Binary provenance. Today's assets are hashed in a single release. A new darwin set needs its own source and hash chain.

**Gained.**
- No root in the control plane.
- No clock skew after sleep. PID 1's RTC sync every 10 s exists for it (`docs/STATUS.md:187-188`).
- No dependence on a separately signed hypervisor entitlement for these processes.

### 5. Expected footprint

**Inputs from the repo.**

| Reading | Value | Source |
|---|---|---|
| Control-plane VM, idle | 1.1-1.2 GB, 1.2 GB after the latest build | `docs/STATUS.md:775`, `:781`, `:837` |
| Worker VM, idle | 563-613 MB | `docs/STATUS.md:837`, `docs/GOAL.md:123` |
| Guest use after a burst, worker | 272 MB | `docs/STATUS.md:659` |
| Guest use after a burst, control plane | 624 MB and 668 MB | `docs/STATUS.md:660`, `:674` |
| Host CPU, control plane | 5.9-9.3%, three readings | `docs/STATUS.md:795-796` |
| Host CPU, worker | 1.5-2.4% | `docs/STATUS.md:837` |
| Host cost of guest work | 1.5-2x | `docs/STATUS.md:728` |

**How I derived the estimates.**
- Control-plane-only guest use is 624-668 MB minus the worker's 272 MB, which is about 350-400 MB. That is an upper bound for native RSS. It includes page cache of the binaries, which macOS does not bill to a process.
- No per-process RSS exists in the repo. The 350-400 MB is a delta of guest use, not a measurement.
- The worker VM is about 0.58 GB. That is the node-only cost.

**Scenarios, per cluster.**

| Scenario | Memory today | Memory after | Saving |
|---|---|---|---|
| Native control plane, cluster with workers | 1.15 GB control-plane VM | about 0.35-0.4 GB native | about 0.7-0.8 GB |
| Native control plane, default single node | 1.15 GB one VM | about 0.35-0.4 GB native plus one 0.58 GB worker | about 0.15-0.25 GB |
| Slim VM, `joinNode=false` with workers | 1.15 GB | about 0.85-1.0 GB | about 0.15-0.3 GB |
| Native classic control plane | not measured | about 0.35-0.5 GB native | about 0.4-0.5 GB, a guess |

- **CPU, native with workers.** Subtract the node-like 1.9% from the control-plane VM's mean of about 7.5%, which leaves about 5.6% for control-plane daemons. Divide by the 1.5-2x virtualization factor. That gives about 2.8-3.7% native, a saving of about 3.5-4.5 points.
- **CPU, native single node.** The saving is about 2-3 points, after adding back a worker at about 1.9%.
- **CPU, slim VM.** It saves roughly the node's 1.5-2 points.

**Offsets against the saving.**
- NAT CPU in the worker VMMs for all API traffic. Unmeasured.
- macOS timer wakeups of five Go processes.
- Compressed pages: a worker shows 323 MiB compressed in one reading (`docs/STATUS.md:840-842`). Go heaps may behave differently.
- Go on darwin releases memory with `MADV_FREE_REUSABLE`. bend-vmm saw that this "did not lower RSS" (`docs/STATUS.md:627-628`). Footprint accounting of Go heaps is not verified. Measure with `vmmap -summary`, as GOAL §7 does.

### 6. Existing levers that need no new platform

- **Node components in the control-plane VM when workers exist.** `joinNode=false` is parsed and ignored (see Parity). `vcluster/config/config.go:535-537`: "If false, only the control plane binaries will be executed and no node will show up in the actual cluster."
- **kine is already the default** (`docs/DESIGN.md:146`). The `--backing-store etcd` mode costs more.
- **Defaults are ceilings.** A 1 GiB worker saves about 40 MB (`docs/STATUS.md:836-837`). The control-plane VM's `--mem` has not been tried.
- **Leader election.** `--leader-elect=true` for both the controller manager and the scheduler (`src/guest/plan.bend:349`, `:383`). Each is one lease write about every 2 s. The flags are pinned by laws (`laws/plan.bend:169`, `:191`). The request mix is unmeasured.
- **Go runtime tuning.** `Plan.daemon_cmd` and `Init.add_daemon` (`host/init.bend:236`) pass no environment, so `GOMEMLIMIT` and `GOMAXPROCS` would need an `env` wrapper. The size of the gain is unmeasured.

## Contradictions

1. **Design.** DESIGN and GOAL define vk8s as clusters in bend-vmm VMs (`docs/DESIGN.md:21`, `docs/GOAL.md:3-5`). A native control plane breaks that, so it would be an opt-in mode with a documented divergence.
2. **Config.** `docs/CONFIG.md:23` lists `joinNode.enabled` as supported. The boot plan ignores it, and D4 in `docs/ref/vcluster-standalone.md:668` chose always-join.
3. **Binary and dependencies.** GOAL §6 says "A fresh Mac needs only the binary" (`docs/GOAL.md:99`). Native TLS needs OpenSSL 3, which a fresh Mac lacks. The host binary already needs `kubectl` for `token create` and `node add` (`host/vk8s.bend:432`).
4. **Docs and code.** `src/standalone/certs.bend:1-6` says the host runs the steps with "kubeadm's library or openssl". The module is not imported by any host code, only by `tests/certs.bend`. Rotation goes through the kubeadm steps in `src/guest/plan.bend`.
5. **Build sources.** DESIGN says the apiserver, controller manager, scheduler, etcd and kine are "assets fetched by version" (`docs/DESIGN.md:58-62`). The pinned source has no darwin binaries. Only the apiserver and etcd have a third-party darwin source, and that source is the envtest release, not loft-sh.
6. **Reference commit.** My vcluster clone is HEAD 3a0085b6. The project pins a8ab30e. I used the clone only for facts that do not depend on that gap.

## Decisions

| Option | What it changes | Cost and risk | Footprint effect | Recommendation |
|---|---|---|---|---|
| A. Keep all VMs | Nothing. | None. | 0 | Baseline only. |
| B1. Slim VM: `joinNode=false` when workers exist | Drop the node part from the control-plane VM when `--nodes` is at least 1. | Low. Conformance (a) must pass again. Loses the control-plane node as pod capacity. Single-node unchanged. | About 0.15-0.3 GB and 1.5-2 CPU points per multi-node cluster | **Do first.** vcluster parity, no new platform, and it measures the real per-process split. |
| B2. Slim VM: Go env tuning, leader-election periods, smaller `--mem` | Env wrapper on daemons. Possible amended flag laws. | Low, but laws are the architect's. | Unknown until measured | Measure first. Take only what a measurement shows. |
| C1. Native classic control plane, opt-in | New darwin assets, OpenSSL on macOS, a native plan and supervisor. No LAN dependence. | Medium. Needs darwin controller manager, kubeadm, kine and konnectivity builds. | About 0.4-0.5 GB, a guess | **Second.** Simplest network. |
| C2. Native standalone control plane, opt-in | C1 plus workers over the NAT, konnectivity agents, new default endpoint, a no-disk snapshot. | High. Largest parity surface. | About 0.7-0.8 GB with workers, 0.15-0.25 GB single-node | Only after C1 and a measured NAT cost. |
| D. Native as default | Replaces the VM path. | Highest. The security loss applies to everyone. | Same as C2 | Do not do this. |

**Decisions for the maintainer.**
1. Does single-node standalone keep the VM? It must, since it has no other node. Native would then save only about 0.15-0.25 GB there, and the default flow would get slower.
2. Who provides darwin binaries? Options are our own pinned CI build (Go cross-compile from Linux), or envtest for the apiserver and etcd plus our own build for the rest. This changes the asset manifest and release.
3. Where does OpenSSL come from on macOS? Options are Homebrew, a bundled dylib, or a different TLS path. Without one, GOAL §6's "needs only the binary" fails.
4. Is the isolation loss from Security acceptable as an opt-in?
5. May flag laws change for leader election, or ports for several clusters? Those laws are architect-owned.

**Phased plan.**
- **Phase 0.** Measure the control-plane VM: per-process RSS, idle CPU, and the apiserver request mix.
- **Phase 1.** B1, then B2 if the numbers support it.
- **Phase 2.** Spike a darwin build of the controller manager, scheduler, kubeadm, kine and konnectivity-server. Run them on a Mac with the TLS path in an experiment.
- **Phase 3.** C1.
- **Phase 4.** Decide C2 using the Phase 0 and Phase 3 numbers.

## Unchanged

- The worker VM image, boot plan and supervision (`src/guest/supervise.bend`, proven).
- The balloon, idle reclaim and fstrim logic for workers and the cache VM.
- The image cache VM.
- Join tokens, the join protocol and the pure translators, CoreDNS manifest generation, and the `vcluster.yaml` parser.
- The flannel host-gw network between workers.
- All laws on translators in `src/translate/*` and `src/sync/*`.

## Candidate work items

Items are listed as code location, then the nearby laws and tests.

**B0. Measurement (no code change).**
- Per-process RSS and CPU in a running control-plane VM. Request mix from `/metrics` over 120 s.
- Nearby: `scripts/regression.sh`.

**B1. Slim control-plane VM when workers exist.**
- Split `Plan.node` into a runtime part and a control-plane-only part, and skip the runtime part: `src/guest/plan.bend:694`, `:737`.
- Pass the flag on the kernel command line: `src/cli/cli.bend:1096` (cmdline), `host/init.bend:754` (`Init.plan`), `:816` (`Init.boot`).
- Read `controlPlane.standalone.joinNode.enabled`: `src/config/vcluster.bend`, `src/guest/values.bend`, and the create flow in `host/vk8s.bend`.
- Adapt: `Plan.cp_daemons` (`src/guest/plan.bend:1188`) and `Plan.certs_rotate` (`:1195`).
- Laws and tests: `laws/plan.bend:398` (plan.control_plane.join_server), `laws/plan.bend:525`, `laws/vcluster_config.bend:50`, `:165`, `tests/plan.bend`, `tests/classic_plan.bend`, `scripts/regression.sh`.

**B2. Tuning.**
- Env wrapper: `host/init.bend:236` (`Init.add_daemon`) and `src/guest/plan.bend:500-507`.
- Leader-election periods and the flags: `src/guest/plan.bend:349`, `:383`.
- Laws and tests: `laws/plan.bend:169`, `:191`. Amendments need the architect.

**C0. Darwin assets.**
- A darwin fetch or build script beside `scripts/guest/fetch-assets.sh`.
- Manifest and release: `scripts/release-assets.sh`, `src/cli/manifest.bend`, `src/cli/assets.bend`.
- Tests: `laws/assets.bend`, `laws/manifest.bend`.

**C1. OpenSSL and the native executor.**
- `host/effs/tls_server.c:143-151`, bend-kube's `tls.c`.
- `host/effs/sys.c:9,47,63`, `host/effs/proc.c:52`, `host/init.bend:383-426`.
- Tests: `tests/tls_server.sh:9`, `tests/tls_server_echo.bend`, `tests/bin_file.sh`.
- Run on a Mac, since CI has no macOS runner.

**C2. Native plan with a data-dir parameter and no busybox.**
- New defs beside `src/guest/plan.bend:36-60` (`Plan.data`, `Plan.pki`, `Plan.bin`, `Plan.bb`). Replace the 26 `Plan.bb(["sh", ...` steps used by the control plane.
- Port allocation: `src/guest/plan.bend:200-230` (etcd, kine), `:334-383` (add secure ports), `:1072-1080` (konnectivity), `src/cli/cli.bend:1052` (join port).
- Laws and tests: `laws/plan.bend:203`, `tests/plan.bend`, `tests/konnectivity.bend`.

**C3. Classic native.**
- `src/guest/plan.bend:1159` (`Plan.classic_x`), `:1117`, `:1124`.
- `src/cli/cli.bend:1065` (`Cli.forwards`), `:1129` (`Cli.host_endpoints`).
- `src/cli/kubeconfig.bend:587` (`Kubeconfig.for_guest`).
- Laws and tests: `laws/classic.bend`, `laws/cli.bend:293-300`, `tests/classic_plan.bend`, `tests/syncer_envtest.sh`, `tests/kubelet_envtest.sh`.

**C4. Native standalone network and certs.**
- Endpoints and addresses: `src/guest/plan.bend:472` (`default_endpoints`), `:128-140` (SANs), `:694` (`Plan.node` join material), `:957` (`Plan.worker` discovery).
- Konnectivity for standalone: `src/guest/plan.bend:1068`, `:1088`, `:1107`.
- Worker flags and LAN numbering: `src/cli/cli.bend:1166`, `:1020`.
- Rotation: `src/guest/plan.bend:1183-1210`.
- Laws and tests: `laws/cli.bend:71-78`, `:297-300`, `laws/plan.bend:273-278`, `tests/cli.bend:121-126`, `tests/certs.bend`, `tests/join.bend`.

**C5. Lifecycle and snapshots.**
- `host/vk8s.bend:216`, `:304`, `:1376-1403`.
- `Plan.request.dump` at `src/guest/plan.bend:1249`, `host/snapshot_open.bend`.
- Docs: `docs/SNAPSHOT.md`, `docs/STATUS.md`.
- Tests: `tests/snapshot_envtest.sh`, `tests/snapshot.bend`.

## Links

- https://github.com/chenhunghan/bend-vk8s (the repo, read locally)
- https://github.com/chenhunghan/bend-vmm (README and DESIGN, commit 3cefde4)
- https://github.com/chenhunghan/bend-kube (`src/effs/tls.c`, `src/effs/sys.c` at main)
- https://github.com/loft-sh/vcluster (HEAD 3a0085b6; `.goreleaser.yaml`, `pkg/cli/create_docker.go`, `pkg/pro/privatenodes.go`, `config/config.go`)
- https://github.com/loft-sh/kubernetes/releases/tag/v1.36.6 (Linux-only assets)
- https://github.com/kubernetes/kubernetes/tree/v1.36.6 (`hack/lib/golang.sh`, `cmd/kubeadm/app/constants/constants.go`, `pkg/kubelet/client/kubelet_client.go`, `cmd/kube-apiserver/app/server.go`, `cmd/kube-controller-manager/app/plugins.go`, volume `_unsupported.go` stubs)
- https://github.com/kubernetes-sigs/controller-tools/releases/tag/envtest-v1.36.2 (darwin-arm64 apiserver and etcd)
- https://github.com/etcd-io/etcd/releases/tag/v3.6.8 (darwin-arm64 zips)
- https://github.com/k3s-io/kine (`pkg/drivers/sqlite/sqlite_cgo.go`, `sqlite_nocgo.go`; release v0.17.5)
- https://github.com/kubernetes-sigs/apiserver-network-proxy (v0.37.1, no release assets)