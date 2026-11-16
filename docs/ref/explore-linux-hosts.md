# Explorer report: Linux hosts, x86_64, native mode, container mode, gVisor, dev VM

The working tree is at 0aa6e41. `origin/main` is at 849d7f2, which adds the container, gVisor and dev VM scope. I read that scope from `origin/main:docs/GOAL.md` and `origin/main:docs/STATUS.md`, whose line numbers differ from the tree. I did not run Bend or build anything. The network blocks `dl-cdn.alpinelinux.org`, `deb.debian.org`, `dl.k8s.io` and `storage.googleapis.com`. GitHub is reachable. I cloned the references into `/tmp/refs`: vcluster, vcluster-docs, bend-vmm, kind and gvisor.

## Findings

### 1. Build for linux-arm64 and linux-amd64

**Pipeline today**
- `host/vk8s.bend:2` imports bend-vmm by package hash: `import 0xe13a97cc62789dc4181c0e4284f7bab6/main.bend as V`.
- bend-vmm is used at one place only. `host/vk8s.bend:1669`: `V.Vmm.run(["vk8s", "vmm"], Vk8s.lin(flags))`.
- The only Mac build script is `scripts/build-mac.sh`. It signs the binary at `:23`: `codesign -s - --entitlements host/hv.entitlements -f "$tmp" 2>/dev/null`. `host/hv.entitlements` holds only `com.apple.security.hypervisor`.
- The gate compiles `host/vk8s.bend` to C only. `scripts/check.sh:72`: `out=$(bend "$h" -o "$tmp/$(basename "$h" .bend).c" 2>&1)`. No CI job links a Linux `vk8s`.
- CI installs Bend 2.0.40 for Linux x64 only (`.github/workflows/ci.yml:13`). bend-vmm pins the Linux arm64 Bend tarball: `bend-vmm/.github/workflows/ci.yml:81` `BEND_SHA_LINUX_ARM64: 2f42a6fa34ec…`.

**bend-vmm's Linux build**
- It supports Linux arm64 only. `bend-vmm/README.md:60`: "Hosts: macOS 15+ on Apple Silicon, or Linux on arm64 with `/dev/kvm`", kernel 6.7+.
- Its release job builds on `ubuntu-24.04-arm` (`bend-vmm/.github/workflows/release.yml:69`). It installs `clang libx11-dev` (`:76`) and prints `ldd out/bend-vmm` (`:90`), so the binary is dynamic glibc.
- bend-vmm has no x86 code. A grep for x86 and amd64 in its markdown finds nothing.
- `bend-vmm/host/hvf.c:464` calls `ioctl(kvm_vm, KVM_ARM_PREFERRED_TARGET, &init)` with no arch guard. The file has 14 `KVM_ARM*` or `__aarch64__` hits and no `#error`. An x86_64 build of the pinned package would fail on x86 headers. I did not build it.
- The vk8s pin 35d8a07 is two commits behind bend-vmm HEAD. Those two commits only touch the README and `check-host`.
- bend-vmm exports a typed control API: `V.Vmm.status`, `pause`, `resume`, `stop`, `powerdown`, `ctl` (`bend-vmm/README.md:330-333`).

**glibc or static**
- `docs/DESIGN.md:89-90`: "native `Process.run` needs glibc 2.34+ on Linux".
- `host/effs/proc.c:52-53` guards `posix_spawn_file_actions_addclosefrom_np(&acts, 3)` with `#ifndef __APPLE__`, so Linux needs glibc 2.34.
- The binary dlopens `libssl.so.3` (`host/effs/tls_server.c:144`) and `libz.so.1` (`bend-vmm/host/hvf.c:1263`). A static musl `vk8s` cannot do that. Musl is used only for PID 1 (`scripts/guest/build.sh:47`).
- `scripts/guest/build.sh:51` already shows the cross recipe: `zig cc -target aarch64-linux-gnu.2.38 -O2 -w out/build/init.c -lm -ldl -lpthread`. Whether zig's bundled headers carry `linux/kvm.h` is not verified.
- Entitlements are Mac only. On Linux the VMM needs read and write access to `/dev/kvm`. `bend-vmm/scripts/ci/kvm-runner.sh` does `sudo usermod -aG kvm "$USER"`.

**macOS assumptions in `host/*.bend`, scripts and `src/`**

| Site | Assumption |
|---|---|
| `host/vk8s.bend:217,304,467,1241,1376,1501` | `cp -c` (APFS clone) of `data.img` (and snapshot archives) |
| `scripts/guest/build.sh:71-72` | `cp -c` into `~/.vk8s/assets` |
| `host/vk8s.bend:81,297,313,316,326,726,758,1047,1062,1064` | `nc -U -w N` to the control socket |
| `host/vk8s.bend:425` | `date -u -v+1H +%Y-%m-%dT%H:%M:%SZ` (BSD `-v`) |
| `host/vk8s.bend:766,807,814` | `date -r "$c"` with epoch seconds. GNU `date -r` takes a file name. |
| `host/vk8s.bend:765,805,812` | `stat -f %B` (BSD birth time). GNU `stat -f` means filesystem status. |
| `host/vk8s.bend:461,1549` | "macOS allows 103 bytes" |
| `src/cli/assets.bend:32,45` | `shasum -a 256 -c -s` in the fetch strings |
| `scripts/guest/fetch-assets.sh:24`, `scripts/release-assets.sh:17-18` | `shasum -a 256` |
| `scripts/guest/build.sh:20`, `scripts/guest/pack.sh:23` | fallback path `/opt/homebrew/opt/e2fsprogs/sbin/mkfs.ext4` |
| `scripts/regression.sh:1` | `#!/usr/bin/env zsh` |
| `scripts/soak.sh:19-20` | `lsof -U`, `pgrep -f` |
| `host/effs/tls_server.c:144-150` | Homebrew OpenSSL paths, listed after the `.so` names, so Linux is fine |

Notes on the table:
- `nc -U` works with netcat-openbsd, which is Debian and Ubuntu's `nc`. Not verified on other distros.
- `cp -c` on GNU cp is not verified.
- `paths_fit` allows 103 bytes (`src/cli/cli.bend:1248-1249`: `Nat.is_le(Nat.add(String.length(dir), 27n), 103n)`). Linux allows more, so 103 is safe but conservative. Laws pin it (`laws/cli.bend:136-143`).
- I found no `launchd` and no `plist` use besides the entitlements file. VMMs start with `nohup <self> vmm … &` (`host/vk8s.bend:304`). A Linux login session that kills user processes on logout would kill them. Not verified.

**Already portable**
- `host/effs/tls_server.c:37-40` and `:1089-1179` have epoll and kqueue branches.
- `host/effs/sys.c:9-11` has Linux-only includes.
- `tests/bin_file.sh:30` already falls back from `stat -c` to `stat -f`.
- `Vk8s.sh` runs `/bin/sh -c` (`host/vk8s.bend:33`). I found no bashisms in the host strings. Dash and `pipefail` are not verified.

### 2. Guest assets per arch

**arm64 hard-codes**
- `scripts/guest/build.sh:18` points at `.../main/aarch64`.
- `scripts/guest/build.sh:36` asserts the EFI zboot header: `assert b[4:8] == b"zimg", "not an EFI zboot image"`.
- `scripts/guest/build.sh:47,51` use `aarch64-linux-musl` and `aarch64-linux-gnu.2.38`.
- `scripts/guest/debs.py:24` uses `binary-arm64/Packages.gz`. Line 52 skips `usr/lib/aarch64-linux-gnu/gconv`.
- `scripts/guest/fetch-assets.sh:12-14,28-30` pin arm64 SHAs and URLs: the `-arm64-full.tar.gz` bundle, `registry_${REG}_linux_arm64`, and `kube-proxy` from `bin/linux/arm64`.
- `src/guest/plan.bend:667` and `:1295` pass `images import --platform linux/arm64`. No law pins that string. `scripts/guest/images.sh:33` exports with `--platform linux/arm64` from a running vk8s cluster.
- The kernel command line `console=ttyAMA0` is built at `src/cli/cli.bend:1095,1178,1276`. No law or test pins it.
- The module lists in `scripts/guest/modules.early.txt` and `modules.txt` name `virtio_mmio`, `virtio_input`, `evdev` and `rtc`-era arm64 pieces. `scripts/guest/modules.py` skips names listed in `modules.builtin` and fails on unknown ones.
- `scripts/guest/links.py:12` documents `/lib/ld-linux-aarch64.so.1`. On amd64 the glibc loader is `/lib64/ld-linux-x86-64.so.2`. `links.py` links any other top-level entry as a whole, so a `lib64` tree would link. The Debian amd64 deb layout is not verified.

**amd64 sources, read from GitHub**
- loft-sh/kubernetes v1.36.6 has `kubernetes-v1.36.6-amd64-full.tar.gz`, sha256 `22d989e057caa2231500cfbfea0fdb49a6ab62193a4a230bb25447236a687c69`. The arm64 full bundle is `e017844d…`, which equals `BUNDLE_SHA` at `scripts/guest/fetch-assets.sh:12`.
- distribution v3.1.2 amd64 registry sha256 is `40df2224d410f72ae425c3371873b078bbdbda3b8b612be9571f0e6751f3acc8`. The arm64 one equals `REG_SHA` (`09d26f88…`).
- The amd64 `kube-proxy` sha256 is not verified, because `dl.k8s.io` is blocked here.
- `tests/snapshot_store_spike.sh:54-63` already pins amd64 and arm64 etcd and kine SHAs. `tests/syncer_envtest.sh:77-80` maps `uname -m` to amd64 or arm64.

**Kernel and boot facts for amd64**
- The Alpine x86_64 kernel format is not verified. I could not download it.
- `origin/main:docs/STATUS.md:847-851` records the bend-vmm x86_64 plan: "bzImage boot, virtio-mmio devices on the kernel command line, KVM's in-kernel irqchip/PIT, 16550 console, CMOS RTC, MP table, a minimal ACPI power button (our initramfs loads `button`)". It adds "Alpine's x86_64 virt kernel has VIRTIO_MMIO and VIRTIO_MMIO_CMDLINE_DEVICES built in".
- `host/effs/sys.c:42-48` reads `/dev/input/event*` for `KEY_POWER`. An ACPI power button needs the `button` module and `evdev` to reach it.
- The console becomes `ttyS0` on x86. The RTC step (`src/guest/plan.bend:1385`) names bend-vmm's PL031 in its comment. Not verified for CMOS.
- `scripts/guest/build.sh:19` defaults `BUSYBOX` to a `x86_64-linux-musl` URL. The variable is never used. Line 43-44 takes `$BUSYBOX_BIN` or `$HOME/bend-vmm/out/guest/busybox` and says "need a static arm64 busybox".

**How the binary picks assets today**
- It does not pick by arch. `src/cli/manifest.bend:7-16` has one `Manifest.version()` (`"v1.36.6-69181a9a"`) and one `Manifest.files()` of four archives: `Image.tgz`, `vk8s.cpio.tgz`, `assets.img.tgz`, `data.img.tgz`.
- `scripts/release-assets.sh:19-20` builds the version as `$K8S-<first 8 hex of the sha of the sums>`, so arm64 and amd64 sets get different versions.
- `src/cli/assets.bend:17` `Assets.dir(home, ver)` gives `~/.vk8s/assets/<ver>`.
- `src/cli/assets.bend:24` `have_sh` tests four fixed names: `Image`, `vk8s.cpio`, `assets.img`, `data.img`. It is not pinned by a law.
- `laws/assets.bend:15-17` pins `assets.fetch_checks_sum` to the exact `shasum -a 256 -c -s` string. `assets.url`, `assets.dir` and `assets.strict_lists_members` pin the URL form, the dir form and the one-member rule. `fetch_one_strict` derives the member name by dropping `.tgz` (`src/cli/assets.bend:40`).
- `data.img` is an arch-neutral sparse ext4. `Image`, `vk8s.cpio` and `assets.img` are arch specific.
- Release flow today: `README.md:13` downloads `vk8s-darwin-arm64` from the release `v1.36.6-69181a9a`. `gh release list` shows only that one release. The release step is manual.

### 3. CI runners and KVM

- `ubuntu-latest` x86_64 has `/dev/kvm` once a udev rule opens it. The recipe is in the android-emulator-runner README: `KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"`, then `udevadm control --reload-rules` and `udevadm trigger --name-match=kvm`. runner-images issue 14482 reproduces on `ubuntu-latest` image 20260726.254.1 "with KVM enabled (`/dev/kvm` udev rule, `MODE="0666"`)".
- arm64 hosted runners have no `/dev/kvm`. A GitHub staff reply on 2026-08-20 in runner-images issue 14062 says "the ARM64 hosted fleet doesn't surface a nested KVM device". `bend-vmm/docs/DESIGN.md:162-163` says the same.
- Fallbacks that exist for arm64 KVM:
  - `bend-vmm/scripts/ci/emulated-kvm.sh`. QEMU emulates EL2, about an hour. It uses `/dev/kvm` directly when present (`:18`).
  - A self-hosted runner with `scripts/ci/kvm-runner.sh`, gated by the repository variable `KVM_RUNNER` (`bend-vmm/.github/workflows/ci.yml:105-106`).
- vk8s CI already boots the production guest under QEMU TCG on `ubuntu-24.04-arm`: `.github/workflows/ci.yml:224-269` and `tests/kernel16k_boot.sh:112`. It uses stage 0, the assets disk and a PL011 console, with no network.
- vk8s CI downloads amd64 Kubernetes binaries on `ubuntu-latest` already (`tests/syncer_envtest.sh:124-128`, cached at `ci.yml` key `envtest-v1.36.6-v3.5.21`).
- Native, container and gVisor modes need no KVM. kind runs clusters in containers on `ubuntu-24.04` runners (`kind/.github/workflows/docker.yaml:17`).
- A qemu `-M microvm` boot of the amd64 guest on `ubuntu-latest` with `-enable-kvm` is my proposal. It would validate amd64 assets before bend-vmm has x86. Not verified.

### 4. Native mode on Linux

**What PID 1 does today**
- `src/guest/plan.bend:737-745` composes `Plan.boot` from `Plan.system`, `Modules`, `Plan.sysctls`, `Plan.network`, `Plan.disks`, a 9p `Mount`, then `Plan.pki_steps`, `Plan.control_plane`, `Plan.node`, `Plan.publish`. The first six are the machine layer. The last four are the cluster layer.
- The cluster layer is pure Bend data:
  - kubeadm certs and kubeconfigs: `Plan.pki_steps` (`:175`).
  - kine or etcd: `Plan.store` (`:236`).
  - kube-apiserver with `--secure-port=6443` (`:280`), controller manager, scheduler, join server: `Plan.control_plane.k8s` (`:500`).
  - upload-config, bootstrap-token and flannel apply: `Plan.node` (`:694`).
  - CoreDNS from `CD.Coredns.default_manifest()` (`:724`).
  - publish of the kubeconfig: `Plan.publish` (`:521`).
- `host/init.bend:383-430` (`Init.step`) interprets the steps: `Mount`, `Write`, `Run`, `Daemon`, `Spawn`, `WaitTcp`, `WaitFile`, `Modules`, `Stop`, `Log`.
- `src/guest/supervise.bend` restarts a daemon 5 s after exit, and `Init.shutdown` stops daemons in reverse order. The same file says it mirrors systemd's `Restart=always`, `RestartSec=5s`.
- Cert rotation, snapshot dumps and image loads run as host requests from `share/requests` (`Plan.request`, `src/guest/plan.bend:1308`). The 24 h cert check is `Init.cert_timer`.

**VM-only parts that must not run on a host**
- `Init.shutdown` calls `Proc.signal(4294967295, 15)` then `9`, which is `kill(-1)` (`host/init.bend:526-527`). It then runs `umount -a -r` and `Sys.poweroff`.
- `Plan.system` mounts proc, sysfs, devtmpfs, devpts, shm, mqueue, tmpfs on `/run` and `/tmp`, and cgroup2 (`src/guest/plan.bend:70-80`).
- `Modules` runs `insmod` on the guest kernel's modules.
- `Plan.sysctls` writes `net.ipv4.ip_forward`, `net.bridge.*`, `fs.inotify.max_user_watches` and `page_reporting_order` (`:92-97`). The inotify and ip_forward writes are global on a host.
- `Plan.net` configures `eth0` as 10.0.2.15 and `eth1` on the LAN (`:102-111`). `Plan.disks` mounts `/dev/vdb` and `/dev/vda` (`:122-124`).
- PID 1 also runs clock sync, `fstrim`, page-cache reclaim and compaction every tick (`host/init.bend:676-692`).
- `Sys.power()` reads the power button from `/dev/input` (`host/effs/sys.c:42-48`). No effect handles SIGTERM.
- `Plan.bb` runs every helper step through `/bin/busybox` (`src/guest/plan.bend:45-49`). A host has no `/bin/busybox` by default. Some steps use `set -o pipefail` (`:683,1294`).
- `kubectl` is called from the plan as a binary on the assets disk. The host CLI calls `kubectl` from the host (21 uses in `host/vk8s.bend`).

**Fixed paths and ports**
- `Plan.data()` is `/var/lib/vcluster`, the same as vcluster standalone (`src/guest/plan.bend:36-37`). `/var/lib/vcluster` appears 85 times in `laws/plan.bend` and 10 times in `laws/certs.bend`. The constants cannot change without breaking laws.
- Fixed ports: 6443, 8443 (join), etcd 2379, 2380, 2381 (`:203-210`). Also containerd at `/run/containerd`, `/etc/containerd`, `/etc/cni/net.d`, `/opt/cni/bin` and `/etc/kubernetes` in `Plan.runtime` and `Plan.containerd_config` (`:535-545`, `:657-667`).
- `tests/snapshot_envtest.sh:231-244` already runs the guest's `Run` steps on a Linux CI host. It rewrites `/var/lib/` to a scratch root with bash and strips the `'/bin/busybox'` prefix. That is the relocation seam, done by hand.
- `Init.boot` reads its settings from the kernel command line environment: `VK8S_NAME`, `VK8S_PORT`, `VK8S_STORE`, `VK8S_ROLE`, `VK8S_MODE`, `VK8S_NODE_IP`, `VK8S_TOKEN`, `VK8S_HOST_NAMESPACE`, `VK8S_SERVICE_CIDR`, `VK8S_EXTRA_SAN` (`host/init.bend:816-830`).

**What vcluster standalone publishes**
- The repo's earlier report `docs/ref/vcluster-standalone.md:257-321` records the install script. I re-read the public release asset `install-standalone.sh`, as text only:
  - `CONF_DIR="/etc/vcluster"` and `DATA_DIR="/var/lib/vcluster"` (`:35-36`). The unit is `vcluster.service` (`:38`).
  - The unit has `Type=notify` (`:255`), `KillMode=process`, `Delegate=yes` (`:276-277`), `Restart=always` and `RestartSec=5s` (`:286-287`).
  - `ExecStart=${DATA_DIR}/bin/vcluster start --config ${CONF_DIR}/vcluster.yaml` (`:288`).
- `vcluster/pkg/constants/standalone.go:15-19` has `VClusterStandaloneSystemdServiceName = "vcluster"` and the unit file path.
- The standalone runtime is closed. `vcluster/pkg/pro/standalone.go` says "standalone requires the pro binary". Behavior comes from docs, the script and config schema only.
- Host requirements, `vcluster-docs/vcluster/deploy/control-plane/binary/node-requirements.mdx:18-22`: "Linux distribution with systemd support", "`iptables` binaries installed", "Root user access", and raised inotify limits. Supported: Ubuntu 22.04 and 24.04, RHEL 8 to 10, CentOS Stream 9, Rocky 9 and 10 (`:73`).
- Ports: `troubleshooting.mdx:27` "Ensure ports 6443 (API Server) and other required ports are accessible". Join uses `https://10.244.0.16:8443/node/join?token=…` (`manage.mdx:244`). Logs: `journalctl -u vcluster.service` (`troubleshooting.mdx:20`).
- The control plane node is also a worker by default, and docs warn against that for production (`basics.mdx:69-72`). vcluster allows one cluster per host: one unit name and one data dir.
- Cleanup, `install-standalone.sh --reset-only` (`:68-96` in the earlier report): stops and disables the unit, removes secrets, drop-ins, `/var/lib/vcluster`, `/etc/kubernetes`, `/var/lib/kubelet`, `/var/lib/etcd`, and `pkill`s vcluster.
- The docker driver runs this same standalone install inside a privileged systemd container (`docs/ref/vcluster-standalone.md:143-148,425` area, `vcluster/pkg/cli/create_docker.go:623-625`).

**Join for real nodes**
- `src/standalone/join.bend:1306-1322` makes the worker script end in `exec kubeadm "$@"`. It ignores the download flags (`:1294-1296`). A real Linux node has no kubeadm, kubelet or containerd from this script. vcluster's script installs them (`docs/ref/vcluster-standalone.md:536-542`).
- `Join.script.body` refuses control-plane joins (`:1327`).

**`delete` and iptables**
- `vk8s delete` today removes the cluster dir and fails if it remains (`docs/STATUS.md` section 7 notes). The VM backend needs no host iptables, because bend-vmm's NAT is user mode (`bend-vmm/src/net/nat.bend`, not read in full).
- kube-proxy and flannel in a native cluster would write host iptables if a node ran on the host. A control-plane-only host writes none.

**explore-native-control-plane**
- No branch, PR, issue or doc with that name exists in the repo or on GitHub. `git branch -a` and `gh pr list` show nothing. Not verified what that session has decided.

### 5. Container mode (D)

**What vcluster's docker driver and kind do**
- vcluster control plane container, `vcluster/pkg/cli/create_docker.go:623-626`: `"--tmpfs", "/run"`, `"--tmpfs", "/tmp"`, `"--privileged"`. A per-cluster Docker network and the `ghcr.io/loft-sh/vm-container` image (Ubuntu with systemd) complete it. Workers use the same flags (`:684-687`).
- vcluster loads host modules `overlay`, `bridge`, `br_netfilter` with `modprobe` (`vcluster/pkg/cli/docker_runtime.go:174-179`).
- kind, `kind/pkg/cluster/internal/providers/docker/provision.go`:
  - `:175` `"--cgroupns=private"`
  - `:226-228` `"--privileged"`, `"seccomp=unconfined"`, `"apparmor=unconfined"`
  - `:231` `"--tmpfs", "/run"`
  - `:239` `"--volume", "/lib/modules:/lib/modules:ro"`
- kind's entrypoint, `kind/images/base/files/usr/local/bin/entrypoint`:
  - `:192` `mount --make-rshared /`
  - `:264-269` cgroup v2: the root `cgroup.subtree_control` cannot take controllers while `cgroup.procs` holds PID 1. The process moves to `/init.scope` first. kubelet then needs a `/kubelet` cgroup.
  - `:415-427` `select_iptables`: chooses `iptables-legacy` or `-nft` by which one has rules.
  - It also detects overlayfs on userns and fuse-overlayfs, and sets `cgroupRoot: /kubelet` in the kubelet config (`kind/pkg/cluster/internal/kubeadm/config.go:278`).
- kind's rootless doc (`kind/site/content/docs/user/rootless.md:19-116`) needs cgroup v2 with delegation of cpu and other controllers, and the host modules `ip6_tables`, `ip6table_nat`, `iptable_nat` loaded.
- vcluster's delete removes the container, volumes and kube context (`vcluster/pkg/cli/delete_docker.go:160-193`).
- No container runtime is available on a vk8s host by design. `runc` is in the node bundle that `scripts/guest/fetch-assets.sh:18-19` unpacks. `Plan.containerd_config` points containerd at `/var/lib/vcluster/bin/runc` (`src/guest/plan.bend:541-542`).

**How the node image carries over**
- Stage 0's end state (`scripts/guest/stage0.sh`) is an initramfs copy in a tmpfs root plus the assets image mounted read-only at `/assets`. A container rootfs can be the unpacked `vk8s.cpio` plus a loop mount of `assets.img` at `/assets`. Stage 0 itself is not needed.
- The machine layer must be swapped. The runtime provides proc, sys, dev and network, and `Modules` and the page-reporting write must be skipped. `/etc/vk8s/modules` are built for the Alpine kernel and cannot load into a host kernel.
- `Plan.disks` becomes bind mounts of the data dir and the share dir. `Mount{"9p", …}` becomes a bind mount of the share.
- Containerd's overlayfs snapshotter needs its root on ext4 or xfs, not on the container's overlay. bend-vmm's note says "images on ext4/xfs" for VM disks (`origin/main:docs/STATUS.md:842`).
- A pid-namespace PID 1 needs a stop signal handler, and `Init.shutdown` must not call `kill(-1)` or `reboot`. The behavior of `reboot(RB_POWER_OFF)` in a pid namespace is not verified.
- Host sysctls: `fs.inotify.max_user_watches` is global (`src/guest/plan.bend:96`). `net.bridge.*` needs `br_netfilter` loaded on the host. Whether `net.bridge.*` is namespaced is not verified.
- The VM LAN gives flannel host-gw an L2 segment (`Cli.lan_ip`, `src/cli/cli.bend:1022`). A container backend needs a bridge and veth pairs plus a host MASQUERADE rule for egress. That host state must be cleaned on delete. The user-mode DNS 10.0.2.3 (`src/guest/plan.bend:110`) has no container equivalent. vcluster writes `k8s-resolv.conf` from the host resolver for the same reason (`docs/ref/vcluster-standalone.md:130-137`).

**macOS shared node-host VM**
- bend-vmm `--forward` is fixed at start. `bend-vmm/README.md:95`: "repeatable, at most 16; a port already in use stops the VMM at startup". Many clusters in one VM do not fit that cap if each needs two forwards.
- `--vsock PATH` bridges guest CID 3 to Unix sockets under PATH (`bend-vmm/README.md:93`).
- Existing laws pin the VMM flag order. `laws/cli.bend:380-381`: `List.drop(&2, String, C.Cli.vmm_flags("/d", "/a", "demo", 10001, 2, 2048, False{}), 22n) == ["--balloon", "auto"]`. New flags must come after `--balloon auto` or live in new defs.

### 6. gVisor (E)

- Release 20261109.0 on GitHub (`google/gvisor`) carries `gvisor-aarch64.tar.zstd` and `gvisor-x86_64.tar.zstd`. `SHA256SUMS` says:
  - aarch64: `c7394eca1fea29ada6a154857267e940a2232086893ed4fb814b7f0233325a7b`
  - x86_64: `84c29e8f92ba306b1a8c8cb1793fc32fe7388ca894da0427a22f3d8f6448af12`
- I downloaded the aarch64 tarball (60,321,074 bytes). Its sha256 matches. The unpacked size is not verified. There is no zstd tool here.
- `gvisor/g3doc/user_guide/install.md:5`: "gVisor supports x86\_64 and ARM64, and requires Linux 5.6+".
- The tarball holds `runsc`, `containerd-shim-runsc-v1` and a `gvisor-bin/` dir. `runsc` looks for `gvisor-bin/` next to itself.
- `gvisor/g3doc/user_guide/platforms.md:30-32`: systrap often beats KVM inside a VM. systrap uses `SECCOMP_RET_TRAP` (`g3doc/architecture_guide/platforms.md:53`). It is the default platform. arm64 and amd64 filters exist (`pkg/sentry/platform/systrap/filters_arm64.go`, `filters_amd64.go`).
- containerd stanza in docs: `runtime_type = "io.containerd.runsc.v1"` under `...containerd.runtimes.runsc` (`g3doc/user_guide/containerd/quick_start.md:32-33`). Those docs use the v2 plugin names. `src/guest/plan.bend:535-545` writes config `version = 3` with `plugins.'io.containerd.cri.v1.runtime'`, so the key names must be re-checked.
- The FAQ warns that kubeadm may prefer Docker over containerd when both exist (`gvisor/g3doc/user_guide/FAQ.md:102-113`). vk8s has no Docker.
- The syncer already carries a `runtimeClassName` field (`src/translate/pods.bend:43,2561`) and `sync.fromHost.runtimeClasses` defaults off (`laws/vcluster_config.bend:321-322`).
- What works inside our guests and container nodes is not verified. The Alpine kernel has seccomp and user namespaces (`docs/DESIGN.md:48-49`).

### 7. Testing and the Mac dev VM (F)

- bend-vmm already boots a real distro on the Mac. `bend-vmm/scripts/ubuntu-check.sh` boots Ubuntu 24.04's arm64 cloud image through UEFI from a qcow2 overlay with a cloud-init seed. systemd powers off cleanly on the power button, and sshd answers through a `--forward`.
- bend-vmm's direct-kernel path: `scripts/guest-assets.sh` uses Ubuntu's kernel plus busybox. `scripts/linux-assets.sh` fetches the Debian bookworm netboot kernel as an "uncompressed Image".
- vk8s already extracts the Alpine kernel and its modules to `out/build/kernel` (`scripts/guest/build.sh:24-35`). The `modules.py` helper reads `.ko` and `.ko.gz` only. Debian modules ship as `.ko.xz`. Not verified for Debian's current kernel.
- `debs.py` already pulls Debian trixie packages without dependency resolution (`scripts/guest/debs.py:12-13`). A systemd rootfs needs a real resolver, so use `debootstrap`.
- The Mac is an M2 and cannot nest KVM (`origin/main:docs/GOAL.md:72-79`).

## Contradictions

1. `docs/DESIGN.md:14` says the host role runs on "macOS arm64, Linux arm64". Nothing builds or tests for Linux. `scripts/build-mac.sh` is the only build script.
2. `scripts/guest/build.sh:19` defaults `BUSYBOX` to an x86_64 binary, but `:43-44` demands "a static arm64 busybox". The variable is dead.
3. runner-images issue 14549 says `/dev/kvm` exists on `ubuntu-24.04-arm` "out of the box". It was closed within a minute. The staff reply in issue 14062 (2026-08-20) and `bend-vmm/docs/DESIGN.md:162-163` say the arm64 hosted fleet has none. Treat it as absent and probe at run time.
4. `src/standalone/join.bend:1322` ends the worker script with `exec kubeadm`. vcluster's script installs binaries and starts systemd units (`docs/ref/vcluster-standalone.md:536-542`). On a real Linux node vk8s's script cannot join.
5. `laws/assets.bend:15-17` pins `shasum -a 256`. Minimal Linux hosts may lack `shasum`. The law cannot change, so a Linux path needs a new fetch def.
6. `docs/GOAL.md` section 8 says "a systemd unit per cluster". vcluster standalone has one fixed unit and data dir (`install-standalone.sh:35-38`). Plan literals (`6443`, `2379`, `/var/lib/vcluster`) are pinned by laws, so several clusters per host need isolation outside the plan.
7. `Init.shutdown` (`host/init.bend:526-527`) kills every process. That is correct as VM PID 1 and catastrophic as a host service.

## Decisions

**D1. Linux host build recipe**

| Option | Changes in the work | Notes |
|---|---|---|
| a. Native `bend -o` with clang on each runner, as bend-vmm's release does | New CI jobs per arch | glibc floor equals the runner's, 2.39 on Ubuntu 24.04. Debian 12 (2.36) would fail. |
| b. `bend -o x.c`, then `zig cc -target <arch>-linux-gnu.2.34` | Build script like `build.sh:51`; works on the Mac for the dev VM and cross-builds amd64 | `linux/kvm.h` in zig is not verified. |

Recommendation: b, with a one-day spike first and a fallback to a. Reason: one recipe serves CI, the Mac dev VM and both arches, and it lowers the glibc floor.

**D2. Pinning arch assets**

| Option | Changes | Notes |
|---|---|---|
| a. Two manifests in one binary, `uname -m` picks, one release tag per arch | `Manifest.files_arm64/amd64`, a pure `Manifest.for_arch`, `Assets.dir` unchanged | Version hash differs per arch already (`scripts/release-assets.sh:19-20`). No existing law changes. |
| b. One tag, arch-suffixed archive names | New member rule, `have_sh` per arch | `fetch_one_strict` drops `.tgz` for the member name (`src/cli/assets.bend:40`). |
| c. One generated manifest per platform build | Release script emits per-build manifests | A binary then cannot fetch the other arch. |

Recommendation: a. Reason: no change to laws, and darwin-arm64 and linux-arm64 share the arm64 set.

**D3. BSD and GNU shell strings**

| Option | Notes |
|---|---|
| a. A fallback chain in pure defs, `cp --reflink=auto --sparse=always A B 2>/dev/null \|\| cp -c A B 2>/dev/null \|\| cp A B`, plus epoch-to-date done in Bend | One string works on both OSes. macOS fails the first `cp` fast. |
| b. Pick strings at run time from `uname -s` | More branches, more laws. |

Recommendation: a for `cp -c`. For `date -r` and `date -v`, render times in Bend (`src/standalone/join.bend` already converts RFC 3339). Reason: no per-OS forks.

**D4. `nc -U`**

| Option | Notes |
|---|---|
| a. Keep `nc`, add a preflight that names `netcat-openbsd` | Smallest change. |
| b. Use the typed `V.Vmm.status` and `powerdown` | Removes a dependency. The call sites are 10 shell pipelines. |

Recommendation: a first, b as follow-up.

**D5. x86_64 sequencing**

| Option | Notes |
|---|---|
| a. Wait for bend-vmm x86 before any amd64 binary | The pinned package cannot compile on x86 headers (`hvf.c:464`). |
| b. Add a no-VM entry file that does not import `V` | `V` is used once (`host/vk8s.bend:1669`). amd64 native, container and gVisor can ship earlier. |

Recommendation: b. Reason: only the `vmm` subcommand needs bend-vmm.

**D6. Native mode shape**

| Option | Notes |
|---|---|
| a. One unit runs the existing step interpreter and supervisor, with a native plan | Matches vcluster's single `vcluster.service` that supervises children. Reuses the pure plan. |
| b. One systemd unit per daemon, generated from steps | Drops the supervisor and loses the proven stop order. |

Recommendation: a.

**D7. Several clusters on one host**

| Option | Notes |
|---|---|
| a. One native cluster per host, unit `vk8s.service` (name to settle) | Matches vcluster. No plan change. |
| b. Per-cluster units with a private network namespace and bind mounts | Keeps ports and paths literal. Shares machinery with container mode. |
| c. Parameterize ports and paths in the plan | Breaks laws that pin the literals. |

Recommendation: a first, b after the container backend exists, never c.

**D8. Does the native control plane also run a node**

| Option | Notes |
|---|---|
| a. Control plane only | No host containerd, kubelet, CNI or iptables. Workers are VMs on the host or other machines. |
| b. Control plane plus node on the host, as vcluster's default | Writes `/etc/containerd`, `/etc/cni`, `/opt/cni/bin`, host iptables. Conflicts with Docker or k3s. |

Recommendation: a. vcluster's docs warn against b for production (`basics.mdx:69-72`). Real nodes need an installing join script (D13).

**D9. Container launcher**

| Option | Notes |
|---|---|
| a. `runc` with a generated OCI `config.json` | `runc` is in the assets already. The config is pure Bend with laws. No new C. |
| b. A new C effect with `clone`, `unshare` and `pivot_root` | More code, no dependency. |
| c. `unshare` and `chroot` from util-linux strings | Fragile cgroup and mount handling. |

Recommendation: a. Reason: a privileged config with private cgroupns matches what kind asks Docker for (`provision.go:175-239`).

**D10. Container network**

| Option | Notes |
|---|---|
| a. Host bridge per cluster, veth per node, `ip` commands, MASQUERADE tagged per cluster | Host `iproute2` and a netfilter rule are needed. Delete must remove both. |
| b. CNI bridge plugin from the bundle | Needs a CNI driver we do not ship. |

Recommendation: a.

**D11. Reaching many clusters on the macOS node-host VM**

| Option | Notes |
|---|---|
| a. A pre-allocated forward range at VM start, 16 max | Caps clusters. |
| b. bend-vmm adds forwards at run time | A need for the bend-vmm session. |
| c. `--vsock` plus a host proxy per cluster | A new proxy process. |

Recommendation: a for the first cut, b as the need to send.

**D12. gVisor packaging**

| Option | Notes |
|---|---|
| a. Ship runsc and the shim in `assets.img` | `pack.sh` copies the whole bin dir. One new `get` line in `fetch-assets.sh`. Download grows. |
| b. A fifth optional archive | New `have_sh` and manifest members. |

Recommendation: a. Reason: fewer moving parts, the disk is shared and only read pages cost memory.

**D13. Join script for real nodes**

| Option | Notes |
|---|---|
| a. Extend `Join.script` to install the node bundle and units, behind a flag | Needed for native private nodes on other hosts. |
| b. Only VM workers join native clusters | Smaller, but hides a documented flow. |

Recommendation: a, after native N3.

**D14. Dev VM image**

| Option | Notes |
|---|---|
| a. Ubuntu 24.04 cloud image through UEFI | Proven by `bend-vmm/scripts/ubuntu-check.sh`. Uses `--firmware`, not `--kernel`. No Debian. |
| b. Alpine `Image` from `out/build/kernel`, a stage-0-style initramfs and a debootstrap trixie rootfs on `/dev/vda` | Matches your `--kernel/--initrd/--disk` ask. Same kernel as production guests. The rootfs is built on a Linux runner. |

Recommendation: b for fidelity, a as the first quick start. Reason: a needs no build and is proven today.

**D15. Sharing the design with explore-native-control-plane**
- Proposal: share a pure `Env` record (data root, run dir, share dir, bin dir, busybox path, node IP, ports, supervisor mode) and a pure relocate pass over `Plan` steps. Share the host step interpreter too.
- Only the service adapter differs: systemd on Linux, a launchd adapter on macOS.
- macOS native needs darwin builds of kube-apiserver and etcd. The loft-sh bundle is Linux only. Not verified for darwin.
- Recommendation: ask that session to confirm `Env` before either lands.

## Unchanged

- Everything under `src/translate`, `src/sync`, `src/config`, `src/net` and the syncer in `host/syncer.bend`.
- The classic-mode plan and its konnectivity path.
- `Create{…}` constructor and its laws (`laws/cli.bend:14-221`). New flags use wrapper constructors like `NoConnect`, `Classic`, `WithValues` (`src/cli/cli.bend:30-37`).
- `Plan.data()`, `Plan.pki()` and the pinned port literals.
- `assets.url`, `assets.dir`, `assets.fetch_checks_sum`, `assets.strict_lists_members`, `assets.fetch_sh_unique_staging`.
- `paths_fit` at 103.
- The 16 KiB kernel opt-in (`scripts/guest/kernel.sh`).
- The bend-vmm pin until its x86 and Linux notes land.

## Candidate work items

Sizes are S, M or L. "Linux CI" means testable on a GitHub Linux runner.

### Phase 0: Linux build spike (S)
- `.github/workflows/ci.yml` after `:13`: a job on `ubuntu-24.04-arm` that installs the arm64 Bend (sha from `bend-vmm/.github/workflows/ci.yml:81`) and clang, then builds `bend host/vk8s.bend -o out/vk8s`, runs `ldd`, and runs `out/vk8s version`. Linux CI.
- `scripts/build-linux.sh` as the zig recipe from `scripts/guest/build.sh:47-51` with `gnu.2.34`. Tests: `scripts/check.sh:70-76`.
- Laws: none.

### Phase 1: Portable host strings (M)
- `host/vk8s.bend:217,304,467,1241,1376,1501` and `scripts/guest/build.sh:71-72`: one `Cli.clone_sh(src, dst)` def. Tests: `tests/cli.bend`. Laws proposed in `laws/cli.bend`: `cli.clone_sh.chain`.
- `host/vk8s.bend:425,766,807,814,765,805,812`: render dates and creation time in Bend. Laws: `cli.rfc3339_in_one_hour`, `cli.created_text`, taken from vcluster's docker `list` output format.
- `src/cli/assets.bend:32,45`: new `Assets.fetch_one_strict_linux` using `sha256sum` or `shasum`, leaving the pinned law alone. Laws: `assets.sha_tool_fallback`.
- A preflight for `nc`, `curl`, `kubectl`, `tar`, `/dev/kvm`: new `Cli.preflight` in `src/cli/cli.bend`. Laws: `cli.preflight.names_missing`.
- `scripts/regression.sh:1`, `scripts/soak.sh:19-20`: make portable. Maintainer test.

### Phase 2: Arch-aware assets (M)
- `src/cli/manifest.bend:7-16`: generated per-arch manifests. Pure `Manifest.for_arch(uname)` mapping `arm64`, `aarch64` and `x86_64`. Tests: `tests/cli.bend`. Laws: `manifest.arch_arm64`, `manifest.arch_aarch64`, `manifest.arch_x86_64`, `manifest.unknown_arch`.
- `host/vk8s.bend:166-186` (`Vk8s.assets.*`): read `uname -m` and pick the manifest.
- `scripts/release-assets.sh:12-25`: per-arch run emitting both manifests.
- `scripts/guest/fetch-assets.sh:12-14,28-30`: arch switch with the amd64 pins above. The amd64 `kube-proxy` sha still needs a read from `dl.k8s.io`.
- `scripts/guest/build.sh:18,36,47,51` and `scripts/guest/debs.py:24,52`: arch switch, bzImage branch, zig targets, `binary-amd64`, `x86_64-linux-gnu` gconv path. `scripts/guest/links.py` and `tests/guest_image.sh:55-164`: add a `lib64` case. Linux CI.
- `scripts/guest/modules*.txt`: x86 variants adding `button`, and check builtin names with `modules.py`.
- `src/guest/plan.bend:667,1295`, `scripts/guest/images.sh:33`: platform string per arch. Laws: `plan.image_platform`.
- `src/cli/cli.bend:1095,1178,1276`: console per arch (`ttyAMA0`, `ttyS0`). Add after the balloon flags to keep `laws/cli.bend:380-381` true.
- A qemu `-M microvm` boot of the amd64 guest on `ubuntu-latest`, patterned on `tests/kernel16k_boot.sh`. Linux CI.

### Phase 3: linux-arm64 KVM smoke and release (M)
- `scripts/smoke-linux.sh`: create, wait for pods Running, delete, assert no process, socket or dir remains. Reuse the checks in `scripts/soak.sh`.
- CI job guarded by `test -w /dev/kvm`, with a udev step on x86. arm64 hosted runners skip with a message. Self-hosted arm64 runner with `bend-vmm/scripts/ci/kvm-runner.sh` and a `KVM_RUNNER` variable, as `bend-vmm/.github/workflows/ci.yml:105`.
- `README.md:10-13`: install section per OS.
- Maintainer only: real KVM arm64 hardware run, the release upload and signing choices.

### Phase 4: No-VM entry (S)
- `host/vk8s_novm.bend` plus a shared `host/cli_main.bend`, moving `Vk8s.run.go` out of `host/vk8s.bend:1669`. The `vmm` subcommand answers "built without VM support". `scripts/check.sh:71` compiles it too. Linux CI.

### Phase 5: Native mode (L, mostly Linux CI)
- N1 pure: `src/standalone/native.bend` with `Env`, `Native.relocate(env, steps)` and a native boot plan that drops `Plan.system`, `Modules`, `Plan.sysctls`, `Plan.network`, `Plan.disks` and the 9p mount, and keeps the cluster layer. Laws in `laws/native.bend`: `native.relocate_paths`, `native.no_machine_steps`, `native.keeps_pki_steps`, `native.busybox_path`. Proofs in `proofs/native.bend`. Tests: `tests/native.bend`, `tests/plan.bend`.
- N2 host: a `Sys.term()` effect in `host/effs/sys.c` beside `sys_power_run` (`:42-48`) for SIGTERM. A native shutdown that stops daemons in `Sup.stop_order` and never calls `kill(-1)`, `umount -a` or `poweroff` (cf. `host/init.bend:526-527`). Laws: `native.shutdown_no_global_kill`.
- N3 host: unit writer and installer for `/etc/systemd/system/...service` with `Restart=always`, `RestartSec=5s`, `Delegate=yes`, `KillMode=control-group` and `Type=simple`. A CLI wrapper `Backend{c, backend}` at `src/cli/cli.bend:550-555`. `delete` stops and removes the unit, the data dir and any host rules. Laws: `native.unit_text`, `native.delete_leaves_nothing`.
- N4 host: busybox for native (extract from `vk8s.cpio` into the data dir), a host sysctl check that fails with the command to run, and `set -o pipefail` replaced where dash may lack it.
- N5: `Join.script` installer for real nodes (`src/standalone/join.bend:1306-1322`). Laws: `join.script_installs_bundle`.
- N6 later: per-cluster netns and bind mounts for several clusters (D7).
- Tests: `ubuntu-latest` has systemd and root. A job runs `vk8s create --native`, waits for the API, runs `vk8s token create`, joins a worker VM or a second runner step, then `delete`. Extend `tests/join_envtest.sh`.
- Maintainer only: certified conformance run (about 150 min per run, `scripts/conformance.sh`), distro matrix beyond Ubuntu.

### Phase 6: Container mode (L)
- C1 pure: `src/guest/container.bend` with an OCI `config.json` generator (private cgroupns, all caps, no seccomp, bind mounts of data, share and `/assets`, tmpfs `/run` and `/tmp`) and `Plan.boot_container`. Laws: `container.config_privileged`, `container.cgroup_delegation`, `container.no_modules_step`, `container.mounts`. Tests: `tests/container.bend`.
- C2 host: `runc` driver (`run -d`, `kill`, `delete`, `state`), loop mount of `assets.img`, bridge and veth, host MASQUERADE tagged per cluster, kernel preflight (overlay, br_netfilter, nf_tables, veth, cgroup v2 controllers). Reuse `Init.step` with a stop signal. Laws: `container.net_cleanup`, `container.preflight_message`.
- C3: cgroup v2 handling in PID 1 (move PID 1 to an init cgroup, enable controllers, create the kubelet cgroup), following `kind/.../entrypoint:264-269`. Laws: `container.cgroup_steps`.
- C4 macOS: a `node-host` role in `host/init.bend:816-830` that runs C2 inside a bend-vmm VM, and a host-side forward plan (D11). Maintainer test.
- Tests: Linux CI on `ubuntu-latest` and `ubuntu-24.04-arm`, `--backend container` with 1 and 2 nodes, then the regression subset.

### Phase 7: gVisor (M)
- `scripts/guest/fetch-assets.sh`: a `get` for `gvisor-<arch>.tar.zstd` with the sha256s above. `pack.sh` copies it into the bin tree.
- `src/guest/plan.bend:535-545`: a `runsc` runtime stanza with the v3 key names, checked against containerd's docs. A `gvisor` RuntimeClass manifest with handler `runsc`. Laws: `plan.containerd_runsc`, `plan.runtimeclass_gvisor`. Tests: `tests/plan.bend`.
- Tests: a pod with `runtimeClassName: gvisor` that prints `dmesg` (the "Starting gVisor..." line in the quick start), in container-mode CI first, then VM nodes.
- Maintainer only: footprint and idle CPU under gVisor in VM nodes on the Mac.

### Phase 8: Linux dev VM on the Mac (S to M)
- `scripts/dev/linux-vm.sh`: boot flags `--kernel out/build/kernel/.../Image --initrd dev.cpio --disk rootfs.img --share <repo> --forward 127.0.0.1:2222:22 --mem 4096 --cpus 4`.
- A CI job on `ubuntu-24.04-arm` running `debootstrap --arch=arm64 trixie` with systemd, iproute2, iptables, conntrack, kmod, curl, ca-certificates and openssh-server, `mkfs.ext4 -d`, and copying `lib/modules` from the Alpine kernel apk. The initramfs is a small stage-0 variant that switches root to `/dev/vda`. Publish as a hash-pinned artifact.
- Option a in D14 for the first day: the Ubuntu cloud image with `scripts/ubuntu-check.sh` flags.
- Maintainer only: the Mac boot, since the M2 has no KVM and the VM runs only container, native and gVisor.

## Links

- https://github.com/chenhunghan/bend-vk8s (repo, `origin/main` 849d7f2)
- https://github.com/chenhunghan/bend-vmm (README, `host/hvf.c`, CI and release workflows, `scripts/ci/*`, `scripts/ubuntu-check.sh`)
- https://github.com/loft-sh/vcluster (`pkg/cli/create_docker.go`, `docker_runtime.go`, `delete_docker.go`, `pkg/constants/standalone.go`, `pkg/pro/standalone.go`)
- https://github.com/loft-sh/vcluster-docs (`vcluster/deploy/control-plane/binary/*.mdx`)
- https://github.com/loft-sh/vcluster/releases (release asset `install-standalone.sh`, read as text, not run)
- https://github.com/loft-sh/kubernetes/releases/tag/v1.36.6 (amd64 and arm64 bundles and digests)
- https://github.com/distribution/distribution/releases/tag/v3.1.2 (registry `.sha256` files)
- https://github.com/kubernetes-sigs/kind (`provision.go`, `entrypoint`, `rootless.md`, workflows)
- https://github.com/google/gvisor (docs under `g3doc`, release `release-20261109.0`)
- https://github.com/actions/runner-images/issues/14062 (no KVM on arm64 hosted runners)
- https://github.com/actions/runner-images/issues/14549 (conflicting claim, closed in a minute)
- https://github.com/actions/runner-images/issues/14482 (x86 `ubuntu-latest` with the `/dev/kvm` udev rule)
- https://github.com/ReactiveCircus/android-emulator-runner (the udev rule text)

## Not verified

- I ran no Bend build and no `zig cc` build of `host/vk8s.bend`, so the Linux link recipe is untested.
- I did not read Alpine x86_64's kernel format or config, Debian amd64's loader paths, or the amd64 `kube-proxy` sha, because those hosts are blocked here.
- I did not read the gVisor unpacked size, its behavior in HVF/KVM guests, or its containerd v3 key names.
- I did not check `reboot(RB_POWER_OFF)` in a pid namespace, `net.bridge.*` namespacing, dash's `pipefail`, or GNU `cp -c`.
- I found nothing on the explore-native-control-plane session.