# Report: how vcluster runs in the docker driver (vind) and in standalone mode, as input for the Bend microVM rewrite

I explored `/home/node/task` on `main`, `git describe` = `v0.37.0-rc.2-75-ga8ab30ea`. I also read the public repos `loft-sh/kubernetes` and `loft-sh/vm-container`, the public `loft-sh/vcluster-docs` repo, and the `v0.37.6` release assets. I ran nothing I downloaded.

The main limit: **the standalone runtime is not in this repo**. Parts (2) and (3) of your brief cannot be specified fully from here.

## Findings

### 0. What is and is not readable

The standalone entrypoint, embedded etcd, konnectivity, node upgrade and the control-plane kubelet/containerd bootstrap are stubs here. The real code is injected by a private binary.

- `pkg/pro/privatenodes.go:61`: `var StartStandalone = func(_ context.Context, _ *StandaloneOptions) error {` returns `NewFeatureError(licenseapi.Standalone)`.
- `pkg/pro/standalone.go:7`: "Injected by vcluster-pro at startup; the noop default is never reached in practice".
- `pkg/pro/embedded_etcd.go:11`: `StartEmbeddedEtcd` is a stub returning a feature error.
- `pkg/pro/privatenodes.go:21`: `StartKonnectivity` is a stub returning a feature error.
- `pkg/pro/privatenodes.go:39`: `UpgradeNode` is a stub returning a feature error.
- `cmd/vcluster/cmd/start.go:56-62`: when `POD_NAME` and `POD_NAMESPACE` are both empty, `ExecuteStart` calls `pro.StartStandalone`. Otherwise it calls `StartInCluster`.
- `gh repo view loft-sh/vcluster-pro` fails with "Could not resolve to a Repository". The private repo is not readable.
- The `/node/join` handler that serves the join script is not in this repo either. `pkg/server/server.go:196-197` only exempts `/node/download` and `/node/control-plane-download` from the request timeout.

What I could read instead:
- Shared OSS code that standalone very likely reuses: `pkg/k8s`, `pkg/certs`, `pkg/etcd`, `pkg/snapshot`.
- The install script and bundle script, published as release assets.
- The public docs.

Version caveat: the install script I read is from release `v0.37.6`. This checkout is `v0.37.0-rc.2` plus 75 commits. The docker driver fetches the script that matches `--chart-version`, so details may differ.

### 1. Docker driver (vind)

#### 1.1 Gates and pre-flight

- `pkg/cli/create_docker.go:57`: `--chart-version` is mandatory. Error: `please specify a vCluster version via --chart-version`.
- `pkg/cli/create_docker.go:62`: the minimum version is `v0.31.0-alpha.0`. Error: `please use a newer version of vCluster, the minimum version is v0.31.0-alpha.0`.
- `pkg/cli/docker_runtime.go:27`: `EnsureDockerDaemon` looks for the `docker` CLI and pings it with `docker version --format {{.Server.Version}}`.
  - If the ping fails and `DOCKER_HOST` is unset, it falls back to Podman's Docker-compatible socket.
  - On linux it runs `podman info --format {{.Host.RemoteSocket.Path}}`.
  - On other platforms it runs `podman machine inspect --format {{.ConnectionInfo.PodmanSocket.Path}}`.
  - On windows the fallback is refused.
- `pkg/cli/create_docker.go:89`: if the control-plane container already exists and `--upgrade` is not set, the error is `vCluster %s already exists, use --upgrade to upgrade it`.

#### 1.2 Names

`pkg/constants/cli.go:19-22`:

- Control plane container: `vcluster.cp.<name>`.
- Worker container: `vcluster.node.<name>.<node>`.
- Load balancer container: `vcluster.lb.<name>.<x>`.
- Network: `vcluster.<name>`.

Volume names (`pkg/cli/create_docker.go:1616-1625`):

- Control plane: `vcluster.cp.<name>.<vol>`.
- Worker: `vcluster.node.<name>.<node>.<vol>`.

#### 1.3 Assets pulled on the host

All pulls go through `oci.PullImage` with `ArchitectureChoice = runtime.GOARCH` (`pkg/cli/oci/pull.go:33-34`). So the arch is the CLI host's arch.

| Asset | Source | Host cache path |
|---|---|---|
| Kubernetes bundle | image `ghcr.io/loft-sh/kubernetes:<ver>-full`, path `/kubernetes` extracted (`create_docker.go:901,937`) | `<dir of config.json>/docker/kubernetes/<ver>` |
| vcluster binary | image `ghcr.io/loft-sh/vcluster-pro:<ver>`, file `/vcluster` (`create_docker.go:828,866`) | `<dir>/docker/vcluster/<ver>/vcluster` |
| install script | `https://github.com/loft-sh/vcluster/releases/download/v<ver>/install-standalone.sh` (`create_docker.go:492`) | `<dir>/docker/install-standalone/v<ver>/install-standalone.sh` |

Notes on these assets:
- The script must start with `#!`.
- The env var `VCLUSTER_INSTALL_STANDALONE_SCRIPT` overrides the download (`create_docker.go:466`).
- Downloads go into a `.downloading` staging dir and are renamed on success.
- The Kubernetes version is `controlPlane.distro.k8s.version`, else `...image.tag`, else the default config tag. The chart default is `tag: "v1.36.6"` (`chart/values.yaml:325`).
- `create_docker.go:1004` pins that version into the generated `vcluster.yaml`. Without the pin, an older `--chart-version` would re-download binaries into a noexec `/tmp`.

Layout of the Kubernetes image, from `kubernetes/hack/Dockerfile:17-27`. All entries are under `/kubernetes/`:

- `kube-apiserver`, `kube-controller-manager`, `kube-scheduler`
- `helm`, `etcd`, `etcdctl`, `etcdutl`
- `kine`, `konnectivity-server`
- `kubernetes-*-amd64.tar.gz`, `kubernetes-*-arm64.tar.gz`

The node bundle `kubernetes-<ver>-<arch>.tar.gz` is built by `kubernetes/hack/download.sh`. See "Upstream binaries" below.

#### 1.4 Generated config (`loadUserValues`, `create_docker.go:956-1008`)

Forced values (`create_docker.go:974-979`):

- `experimental.docker.enabled=true`
- `controlPlane.standalone.enabled=true`
- `privateNodes.enabled=true`
- `controlPlane.advanced.konnectivity.server.enabled=false`
- `controlPlane.advanced.konnectivity.agent.enabled=false`

Written files under `<dir>/docker/vclusters/<name>/`:

- `vcluster.yaml`
- `.version` (the chart version)
- `token.txt` (64 random chars, mode 0644, `create_docker.go:590-591`)
- `k8s-resolv.conf`
- `kubelet.env`

Contents of the DNS files (`create_docker.go:559,567`):

- `k8s-resolv.conf`: `# Custom Kubelet DNS resolver\nnameserver <host dns>\noptions ndots:0\n`.
- `kubelet.env`: `KUBELET_EXTRA_ARGS=--resolv-conf=/etc/k8s-resolv.conf`.
- The reason: Docker's `127.0.0.11` does not work for CoreDNS or `dnsPolicy: Default`.
- The upstream DNS comes from an `alpine` container reading `/etc/resolv.conf`: the `ExtServers` comment first, else the first nameserver that is not `127.0.0.11` (`create_docker.go:1233-1260`).
- Both files are written only if `k8s-resolv.conf` does not yet exist.

#### 1.5 Control-plane container args (`runControlPlaneContainer`, `create_docker.go:618-677`)

```
docker run -d -h <cpHostname> --tmpfs /run --tmpfs /tmp --privileged
  --network vcluster.<name> --network-alias <cpHostname>
  -e VCLUSTER_NAME=<name> -p <random 10000-12999>:8443 --name vcluster.cp.<name>
  -v vcluster.cp.<name>.var:/var        -v vcluster.cp.<name>.etc:/etc
  -v vcluster.cp.<name>.bin:/usr/local/bin  -v vcluster.cp.<name>.cni-bin:/opt/cni/bin
  <experimental.docker.args> <ports as -p> <volumes as -v> <env as -e>
  --mount type=bind,src=<k8sDir>/<each entry>,dst=/var/lib/vcluster/bin/<entry>,ro
  --mount type=bind,src=<vclusterDir>/vcluster,dst=/var/lib/vcluster/bin/vcluster,ro
  --mount type=bind,src=<cfgDir>/vcluster.yaml,dst=/etc/vcluster/vcluster.yaml,ro
  --mount type=bind,src=<cfgDir>/k8s-resolv.conf,dst=/etc/k8s-resolv.conf,ro
  --mount type=bind,src=<cfgDir>/kubelet.env,dst=/etc/vcluster/vcluster-flags.env,ro
  [--mount ...containerd.sock -> /var/run/docker/containerd/containerd.sock,ro]
  [--mount ...docker.sock     -> /var/run/docker/docker.sock,ro]
  ghcr.io/loft-sh/vm-container   (or experimental.docker.image)
```

- The port is `clihelper.RandomPort()`, which picks 10000 to 12999 (`pkg/util/clihelper/clihelper.go:172-183`).
- The proxy listens on 8443 (`chart/values.yaml:517`).
- `cpHostname` equals the vCluster name, unless the restore marker file `.restore-hostname` overrides it (`create_docker.go:69-76`).
- The containerd socket is mounted only when `registryProxy.enabled` and Docker uses the containerd image store (`create_docker.go:1058-1079`).
- The docker socket is mounted only when `loadBalancer.enabled` (`create_docker.go:1082-1088, 1154`).

#### 1.6 Worker container (`runWorkerContainer`, `create_docker.go:679-736`)

- Same as the control plane, but with `-h <node name>`, no `-p 8443` and no `VCLUSTER_NAME`.
- It mounts only entries whose name starts with `kubernetes-` (the bundle tarballs) from the Kubernetes dir.
- It mounts `k8s-resolv.conf` and `kubelet.env` (to `/etc/vcluster/vcluster-flags.env`).
- It does not mount the vcluster binary or `vcluster.yaml`.

#### 1.7 The vm-container image (`vm-container/Dockerfile`, `files/entrypoint.sh`)

- Base `ubuntu:noble`.
- Packages: `curl fuse binutils jq conntrack iptables strace apt-transport-https iproute2 ca-certificates gpg systemd systemd-sysv dbus cloud-init kmod openssh-server`.
- `STOPSIGNAL SIGRTMIN+3`, `ENV container=docker`, and it runs `/entrypoint.sh`.
- The entrypoint masks `systemd-udevd`, `systemd-sysctl`, `systemd-networkd(.socket)` and `systemd-resolved` by symlinking to `/dev/null`.
- It disables cloud-init network config, runs `ssh-keygen -A`, and sets cgroup v2 `subtree_control`.
- It runs `unshare --cgroup`, mounts a fresh cgroup2, and calls `escape-cgroup.sh` and `create-kubelet-cgroup.sh`.
- It runs `mount --make-rshared /` and then `exec /lib/systemd/systemd`.
- `files/create-kubelet-cgroup.sh` creates `/sys/fs/cgroup/kubelet` and `/sys/fs/cgroup/kubelet.slice` with all controllers enabled.
- It errors on cgroup v1: "this script should not be called on cgroup v1 hosts".

#### 1.8 Install step (`installVClusterStandalone`, `create_docker.go:413-462`)

1. The host fetches the install script, from the cache or GitHub.
2. The host runs `docker exec -i <cp> bash -c ...` with the script on stdin (`create_docker.go:428`):
   - First it loops up to 120 times, 0.5 s apart, until `systemctl is-system-running` is `running` or `degraded`.
   - Then it runs `sh -s -- --skip-download --skip-wait --vcluster-name <name> --join-token <64 chars> [platform args]`.
3. If `controlPlane.standalone.joinNode.enabled`, it prints `Waiting for vCluster standalone node to be joined...`.
   - It polls `kubectl get nodes --request-timeout=10s --no-headers | wc -l >= 1` for 3 minutes.
   - On failure the error is `failed to start vCluster standalone. Node couldn't join: ...:\nvCluster logs:\n...Kubelet logs:\n...`.
   - The logs come from `journalctl -u vcluster.service` and `journalctl -u kubelet.service`.

The platform args, when `--add` is used and a platform login exists (`create_docker.go:330-336`):

- `--platform-access-key`
- `--platform-host`
- `--platform-insecure`
- `--platform-project`
- `--platform-instance-name`

#### 1.9 Network (`createNetwork`, `create_docker.go:1532-1592`)

- It creates a throwaway probe network to learn a free subnet, deletes it, then runs `docker network create --subnet <subnet> vcluster.<name>`.
- On a user-specified `experimental.docker.network`, it uses that name instead.
- `isDockerNetworkReachable` (`create_docker.go:1262`) starts an `alpine nc -l -p 8080` container and dials its IP from the host for 3 s.
- If the network is reachable, `loadBalancer.forwardPorts` is set to false.
- Otherwise, only on macOS, it adds `ifconfig lo0 alias <ip>` for the last 10 IPs of the subnet (`create_docker.go:1120-1125`).
- Unsupported cases disable the load balancer with a warning, for example `Load balancer type services are not supported inside the vCluster because the docker network is not reachable. Port-forwarding will not work. This is only supported on macOS`.

#### 1.10 Kernel modules (`docker_runtime.go:151-216`)

- The modules are `overlay`, `bridge`, `br_netfilter`.
- On linux hosts, `modprobe` runs for modules missing from `/proc/modules`.
  - A failure only warns: `Could not load kernel module %s: %v. If node join fails, run: sudo modprobe overlay && sudo modprobe bridge && sudo modprobe br_netfilter`.
- On other platforms, a privileged `alpine nsenter -t 1 -m -p -u -i -n` container runs the same loop inside the daemon VM.
- Only if a module had to be loaded, it also runs `sysctl -qw net.bridge.bridge-nf-call-iptables=1 net.bridge.bridge-nf-call-ip6tables=1 net.ipv4.ip_forward=1`.

#### 1.11 Extra nodes (`ensureVClusterNodes`, `create_docker.go:759-825`)

1. List containers with prefix `vcluster.node.<name>.`.
2. Remove those not in `experimental.docker.nodes`: stop, rm, and remove their 4 volumes.
3. For each configured node that does not exist yet:
   - A node name is required.
   - If its `var` volume already exists (restored from a snapshot), start the container and skip the join.
   - Otherwise run the worker container, then `joinDockerContainer`.
4. `validateConfig` rejects an empty name, a duplicate, or a name equal to the vCluster name (`create_docker.go:1214-1231`).

The join script run inside the worker (`create_docker.go:741-748`):

```
sleep 2
until curl -fsSLk -o /tmp/join.sh "https://<cpHostname>:8443/node/join?token=<urlenc token>&type=worker"; do ... sleep 2; done
sh /tmp/join.sh --bundle-path /var/lib/vcluster/bin/kubernetes-<k8sver>-<GOARCH>.tar.gz --force-join
```

- The token is the 64-char `token.txt` value, not a kubeadm bootstrap token.
- A quirk: `joinDockerContainer`'s first parameter is named `vClusterName` but receives `cpHostname`.
- The curl URL host is the network alias, so it resolves on the docker network.

#### 1.12 Other lifecycle flows

- **delete** (`delete_docker.go:62-141`):
  - It stops the control plane with `docker stop -t=1` and removes it with `docker rm`.
  - It then removes the 4 control-plane volumes (a failure only warns).
  - It stops and removes each worker and its volumes.
  - It stops and removes each `vcluster.lb.<name>.*` container.
  - It runs `docker network rm vcluster.<name>` and deletes the platform instance.
    - The instance is found by the label `vcluster.loft.sh/join-token=<hash(token)[:32]>`.
  - With `--delete-context` it removes the kube context `vcluster-docker_<name>`.
  - It deletes `<dir>/docker/vclusters/<name>`.
  - Not found: `vCluster container %s not found`, or it is ignored with `--ignore-not-found`.
- **pause** (`pause_docker.go:38-77`): `docker stop` on the control plane, then every worker, then every load balancer.
  - Message when already stopped: `vCluster %s is already paused (container stopped)`.
- **resume** (`resume_docker.go:38-67`): `docker start` on the control plane, then workers, then load balancers.
  - Message when already running: `vCluster %s is already running`.
- **connect** (`connect_docker.go:67-137`, `160-200`):
  - It reads the host port mapped to `8443/tcp`.
  - It runs `docker exec vcluster.cp.<name> cat /var/lib/vcluster/kubeconfig.yaml`, polling every 2 s for up to 5 min.
  - After 10 s it checks `systemctl show vcluster.service --property=MainPID --value`. A value of `0` means failed.
  - It rewrites the kubeconfig: `server: https://localhost:<hostPort>`, `CertificateAuthorityData=nil`, `InsecureSkipTLSVerify=true`.
  - The context, cluster and user are all named `vcluster-docker_<name>`.
  - It waits up to 3 min for `GET serviceaccounts/default` in `default` to succeed. Success message: `vCluster is ready`.
- **list** (`list_docker.go:90`, `80`, `66`):
  - It runs `docker ps -a --filter name=^vcluster.cp. --format {{.ID}}`, then `docker inspect` for each.
  - Table columns are `NAME STATUS CONNECTED AGE`.
  - In JSON output `Namespace` is the literal `"docker"`.
- **snapshot** (`snapshot_docker.go:55-190`):
  - It pauses the vCluster unless it was already stopped, and resumes it afterwards.
  - It writes a tar.gz with entries in this order:
    - `metadata.json` first.
    - `volumes/cp.<vol>.tar` and `volumes/node.<node>.<vol>.tar` for the volumes `var etc bin cni-bin`.
    - `config/...`.
  - Each volume is exported by `docker run --rm -v <vol>:/data:ro alpine tar cf - -C /data .` into a temp file (`snapshot_docker.go:271`).
  - `metadata.json` holds `name, createdAt, vclusterVersion, volumes, configDir, nodes, vclusterYAML`.
  - `oci://`, `s3://` and `https://` outputs are pushed through the shared snapshot storage layer.
- **restore** (`restore_docker.go:62-219`):
  - The first tar entry must be `metadata.json`. Otherwise the error is `expected metadata.json as first entry, got %s`.
  - It refuses an existing target: `vCluster %q already exists; delete it first or use a different name`.
  - It streams each volume into `docker volume create` plus `docker run --rm -i -v <vol>:/data alpine tar xf - -C /data`.
  - It writes `config/*` to the config dir, with a path-traversal check.
  - If restoring under a different name, it writes `.restore-hostname` with the original name.
  - It calls `CreateDocker` with the snapshot's `vcluster.yaml` appended to `Values`.
- Docker snapshots are volume tarballs, not etcd archives. They only restore as docker vClusters (`restore_docker.go:99`).

### 2. Standalone: what runs

#### 2.1 Install script (release asset, `vcluster-release-v0.37.6/install-standalone.sh`)

Paths (`:35-42`):

- `CONF_DIR=/etc/vcluster`
- `DATA_DIR=/var/lib/vcluster`
- Unit `/etc/systemd/system/vcluster.service`
- Secrets `/etc/vcluster/secrets/platform.env` and `/etc/vcluster/secrets/join.env`, mode 0700 dir

Flags (`:100-197`):

- `--vcluster-version`
- `--skip-download`
- `--platform-access-key`, `--platform-host`, `--platform-insecure`, `--platform-instance-name`, `--platform-project`, `--platform-skip-config-sync`
- `--vcluster-name` (default `vcluster`)
- `--node-ip`
- `--skip-wait`
- `--extra-env`
- `--config`
- `--binary`
- `--join-token`, `--join-endpoint`
- `--vcluster-kubernetes-bundle`
- `--reset-only`
- `--fips`
- `--skip-selinux-rpm`, `--selinux-rpm-url`, `--containerd-selinux`

Steps in order:

1. Require `curl`, `systemctl` and root.
2. `mkdir` the data, config and secrets dirs.
3. Get the binary:
   - `--binary`: copy it to `${DATA_DIR}/bin/vcluster`.
   - `--skip-download`: use the existing binary.
   - Otherwise download `https://github.com/loft-sh/vcluster/releases/download/<ver>/vcluster-linux-<arch>-standalone` (`-standalone-fips` with `--fips`) and also `vcluster-linux-<arch>` as `${DATA_DIR}/bin/vcluster-cli` (`:367-383`).
4. With `--join-token` and `--join-endpoint`, it joins as an extra control-plane node (`:318-359`):
   - It polls `https://<ep>/node/join?token=<t>` until HTTP 200, then downloads `https://<ep>/node/control-plane-download/<t>`.
   - The bundle contains `vcluster.yaml`, `vcluster`, `pki/` and `release/`.
   - It deletes `pki/etcd/{peer,server}.{crt,key}`.
   - It writes `${DATA_DIR}/peers.txt` as `<ip>=https://<ip>:2380`.
5. Copy `--config` to `/etc/vcluster/vcluster.yaml`.
6. On RHEL-family hosts with SELinux enabled, install the `vcluster-selinux` RPM from `rpm.vcluster.com`.
7. Create `/var/log/journal` and restart `systemd-journald`.
8. Write the secret env files and the unit, then `systemctl daemon-reload && systemctl enable --now vcluster.service`.
9. Fail if `MainPID` is `0` (`check_vcluster_service_exit`, `:464-473`).
10. Unless `--skip-wait`: wait for `/usr/local/bin/kubectl`, then for `kubectl --kubeconfig /var/lib/vcluster/kubeconfig.yaml get nodes`, polling every 5 s.
    - It then symlinks `~/.kube/config` to the data-dir kubeconfig and `/usr/local/bin/vcluster` to `vcluster-cli`.

Unit file (`:255-288`):

```
[Unit] Wants=network-online.target After=network-online.target dbus.service
[Service] Type=notify  User=root  KillMode=process  Delegate=yes
LimitNOFILE=1048576 LimitNPROC=infinity LimitCORE=infinity TasksMax=infinity
TimeoutStartSec=0  Restart=always  RestartSec=5s
Environment=LOFT_PLATFORM_HOST/_INSECURE/_INSTANCE_NAME/_PROJECT_NAME/_SKIP_CONFIG_SYNC,
  VCLUSTER_NAME, VCLUSTER_KUBERNETES_BUNDLE, VCLUSTER_CONTAINERD_SELINUX,
  VCLUSTER_SELINUX_RPM_URL, VCLUSTER_STANDALONE_IP_ADDRESS
EnvironmentFile=-/etc/vcluster/secrets/platform.env  -.../join.env  -/etc/default/%N  -/etc/sysconfig/%N
ExecStart=/var/lib/vcluster/bin/vcluster start --config /etc/vcluster/vcluster.yaml
[Install] WantedBy=multi-user.target
```

The join token reaches the binary as `VCLUSTER_JOIN_TOKEN` through `join.env` (`:431`). What the binary does with it is not verified.

`--reset-only` stops and disables the unit, removes the secrets and drop-in dirs, `/var/lib/vcluster`, `/etc/kubernetes`, `/var/lib/kubelet`, `/var/run/kubernetes`, `/var/lib/etcd`, `~/.kube` and `~/.vcluster`, and `pkill`s vcluster (`:68-96`).

#### 2.2 Config loading in standalone

- `pkg/config/parse.go:75-79` forces `Standalone.Enabled=true`, `PrivateNodes.Enabled=true`, and `DataDir=/var/lib/vcluster` when empty.
- Default config path is `/etc/vcluster/vcluster.yaml` (`pkg/constants/standalone.go`).
- Standalone is detected by the unit file `/etc/systemd/system/vcluster.service` (`pkg/util/standalone/host.go:15`).
- The service name is `vcluster`. `IsServiceActive` treats `active reloading refreshing activating deactivating` as active (`service_manager.go`).
- Runtime metadata is the JSON file `<dataDir>/standalone-runtime-metadata` with fields `version, ip, nodeClaim, startTime` (`pkg/util/standalone/metadata.go`).
- The docs say the supported backing stores in standalone are SQLite (the default) or embedded etcd (`vcluster-docs/vcluster/deploy/control-plane/binary/basics.mdx:62`).
- `controlPlane.standalone.joinNode.enabled` defaults to true (`vcluster-docs/vcluster/_partials/config/controlPlane/standalone/joinNode.mdx`). When true, the control-plane node also runs kubelet.

#### 2.3 Processes the binary launches

Evidence status: the process flags below come from the shared in-pod path in `pkg/k8s/k8s.go`. That is the only open implementation. `pkg/setup/initialize.go:91` calls `k8s.StartK8S`, and the cert code has standalone branches.

Not verified: that standalone calls `StartK8S` unchanged. `pro.SetStandaloneConstants` remaps the path constants to the data dir (`pkg/pro/standalone.go:7`).

Path constants in-pod (`pkg/constants/paths.go`):

- `DataDir=/data`, `PKIDir=/data/pki`, `BinariesDir=/binaries`, `K8sKineEndpoint=unix:///data/kine.sock`, `K8sSqliteDatabase=/data/state.db`, `EmbeddedEtcdData=/data/etcd`.
- Standalone PKI is `<DataDir>/pki` (`pkg/etcd/client.go:84-85`). The user kubeconfig is `<DataDir>/kubeconfig.yaml` (`pkg/setup/controllers.go:298`).
- In the docker driver the bundle binaries sit at `/var/lib/vcluster/bin/<name>`, via the bind mounts above.

Common behaviour (`pkg/util/command/command.go`):

- `RunCommand` sets `cmd.Dir=DataDir`.
- It prepends `_VCLUSTER_MANAGED=yes` to the environment.
- It appends `BinariesDir` and `/usr/local/bin` to `PATH`.
- It kills a stale process found via a pid file, then writes the new pid file.
- On cancel it sends SIGINT, waits, sleeps 2 s, then kills.
- Any child exit calls `osutil.Exit` in `pkg/k8s/k8s.go`: exit code 1 on error, 0 on a clean finish. The vcluster process dies, and systemd restarts it after 5 s.

**kube-apiserver** (`pkg/k8s/k8s.go:53-111`). The binary is waited on until etcd is reachable:

```
--service-cluster-ip-range=<serviceCIDR>   (default 10.96.0.0/12 for private nodes, pkg/util/servicecidr/servicecidr.go:36)
--bind-address=127.0.0.1 --secure-port=6443 --advertise-address=127.0.0.1
--allow-privileged=true --authorization-mode=Node,RBAC
--client-ca-file=<pki>/client-ca.crt --enable-bootstrap-token-auth=true
--etcd-servers=<endpoints> [--etcd-cafile=<pki>/etcd/ca.crt
  --etcd-certfile=<pki>/apiserver-etcd-client.crt --etcd-keyfile=<pki>/apiserver-etcd-client.key]
--proxy-client-cert-file=<pki>/front-proxy-client.crt --proxy-client-key-file=<pki>/front-proxy-client.key
--requestheader-allowed-names=front-proxy-client
--requestheader-client-ca-file=<pki>/front-proxy-ca.crt
--requestheader-extra-headers-prefix=X-Remote-Extra- --requestheader-group-headers=X-Remote-Group
--requestheader-username-headers=X-Remote-User
--service-account-issuer=https://kubernetes.default.svc.cluster.local   (or .<clusterDomain>)
--service-account-key-file=<pki>/sa.pub --service-account-signing-key-file=<pki>/sa.key
--tls-cert-file=<pki>/apiserver.crt --tls-private-key-file=<pki>/apiserver.key
--profiling=false --endpoint-reconciler-type=none
```

With private nodes, which standalone always enables, it also adds (`pkg/k8s/k8s.go:85-93`):

```
--kubelet-client-certificate=<pki>/apiserver-kubelet-client.crt
--kubelet-client-key=<pki>/apiserver-kubelet-client.key
--enable-admission-plugins=NodeRestriction
--kubelet-preferred-address-types=InternalDNS,InternalIP,Hostname,ExternalDNS,ExternalIP
```

If `konnectivity.server.enabled`, it also passes `--egress-selector-config-file=<path from pro.WriteKonnectivityEgressConfig>`. That function is a stub here. `extraArgs` override matching flags through `MergeArgs` (`command.go:22-31`).

**kube-controller-manager** (`pkg/k8s/k8s.go:147-182`):

```
--service-cluster-ip-range=<cidr> --authentication-kubeconfig=<pki>/controller-manager.conf
--authorization-kubeconfig=<pki>/controller-manager.conf --bind-address=127.0.0.1
--client-ca-file=<pki>/client-ca.crt --cluster-name=kubernetes
--kubeconfig=<pki>/controller-manager.conf --requestheader-client-ca-file=<pki>/front-proxy-ca.crt
--root-ca-file=<pki>/server-ca.crt --service-account-private-key-file=<pki>/sa.key
--use-service-account-credentials=true --leader-elect=true
--cluster-signing-cert-file=<server-ca.crt> --cluster-signing-key-file=<server-ca.key>
```

- The split-CA variant `--cluster-signing-kube-apiserver-client-*`, `-kubelet-client-*`, `-kubelet-serving-*` and `-legacy-unknown-*` is used only when the CAs differ (`appendClusterSigningArgs`).
- With private nodes it adds `--controllers=*,bootstrapsigner,tokencleaner`, `--allocate-node-cidrs=true`, `--cluster-cidr=<networking.podCIDR>` and `--cloud-provider=external`. The default pod CIDR is `10.244.0.0/16` (`chart/values.yaml:1174`).
- If `sync.toHost.resourceClaimTemplates.enabled`, it appends `,-resourceclaim-controller`.
- Not verified: how CSRs get approved. The `*` in `--controllers` includes the upstream default CSR controllers. That is inference from the flag, not a read of any approval code.

**kube-scheduler** (`pkg/k8s/k8s.go:226-241`). It runs when the virtual scheduler is enabled or private nodes are on. Flags:

```
--authentication-kubeconfig=<pki>/scheduler.conf --authorization-kubeconfig=<pki>/scheduler.conf
--bind-address=127.0.0.1 --kubeconfig=<pki>/scheduler.conf --leader-elect=true
```

**Backing store** (`pkg/k8s/k8s.go:305-380`):

- Embedded database, the SQLite default, runs `kine`:
  ```
  --endpoint=sqlite://<DataDir>/state.db?_journal=WAL&cache=shared&_busy_timeout=30000&_txlock=immediate
  --listen-address=unix://<DataDir>/kine.sock --metrics-bind-address=127.0.0.1:2381
  ```
  plus `--ca-file`, `--key-file` and `--cert-file` when set. The apiserver then uses `--etcd-servers=unix://<DataDir>/kine.sock`.
- Embedded etcd: endpoint `https://127.0.0.1:2379`, client certs `pki/etcd/ca.crt` and `pki/apiserver-etcd-client.*`.
  - The launcher `pro.StartEmbeddedEtcd` is a stub.
  - The peer name is the standalone IP, and the peer URL is `https://<ip>:2380` (`pkg/snapshot/restoreclient.go:1165-1172`).
  - The IP comes from `VCLUSTER_STANDALONE_IP_ADDRESS` or the runtime metadata.
  - The data dir is `<DataDir>/etcd`.
  - Metrics bind `127.0.0.1:2381` (`pkg/constants/paths.go`).
- Docs show a pod-mode embedded etcd command line. This is not standalone and it varies by version (`vcluster-docs/.../hardening-guide/private-nodes/2-etcd.mdx:47`). Its main flags:
  ```
  etcd --data-dir=/data/etcd --listen-client-urls=https://0.0.0.0:2379 --listen-peer-urls=https://0.0.0.0:2380
   --listen-metrics-urls=http://0.0.0.0:2381 --name=<n> --heartbeat-interval=500 --election-timeout=5000
   --client-cert-auth=true --cert-file=/data/pki/etcd/server.crt --key-file=/data/pki/etcd/server.key
   --peer-client-cert-auth=true --peer-cert-file=/data/pki/etcd/peer.crt --peer-key-file=/data/pki/etcd/peer.key
   --trusted-ca-file=/data/pki/etcd/ca.crt --peer-trusted-ca-file=/data/pki/etcd/ca.crt
   --initial-cluster-token=vcluster --initial-cluster-state=new --snapshot-count=10000 ...
  ```

**Not readable, so not specified:**

- konnectivity-server flags and the egress selector file.
- konnectivity-agent flags. Only the config schema exists (`config/config.go:783-826`). The agent image is `registry.k8s.io/kas-network-proxy/proxy-agent:v0.34.0` (`images-private-nodes.txt`).
- kubelet and containerd for the control-plane node.
  - Only knobs are visible in the `controlPlane.standalone.joinNode` schema (`config/config.go:535-566`): `preInstallCommands`, `preJoinCommands`, `postJoinCommands`, `containerd`, `caCertPath`, `skipPhases`, `nodeRegistration`.
  - File paths come only from docs: `/var/lib/kubelet/config.yaml`, `/var/lib/kubelet/kubeadm-flags.env`, `/etc/kubernetes/kubelet.conf`, `/etc/kubernetes/pki/ca.crt`, `/etc/systemd/system/kubelet.service.d/10-kubeadm.conf`, `/etc/systemd/system/containerd.service`, `/etc/systemd/system/kubelet.service`.
  - The docker driver's only visible kubelet input is `KUBELET_EXTRA_ARGS=--resolv-conf=/etc/k8s-resolv.conf` read from `/etc/vcluster/vcluster-flags.env`.

#### 2.4 PKI (`pkg/certs`)

Generation uses the vendored kubeadm library (`k8s.io/kubernetes v1.36.3`, `go.mod:70`).

- `pkg/kubeadm/config.go:13-34` builds the config:
  - `ClusterName` equals the vCluster name for standalone, `NodeRegistration.Name` equals the vCluster name.
  - `ControlPlaneEndpoint` is `127.0.0.1:6443`, `LocalAPIEndpoint` is `127.0.0.1:6443`.
  - Service subnet and pod subnet come from the config.
- Key type is RSA-2048 (`vendor/k8s.io/kubernetes/cmd/kubeadm/app/apis/kubeadm/v1beta4/defaults.go:61`).
- Validity:
  - Leaf certs: 1 year (`vendor/.../constants/constants.go:48`).
  - CAs: 10 years (`constants.go:50`).
  - Kubeconfig client certs: 1 year (`vendor/.../phases/kubeconfig/kubeconfig.go:476`).
  - The `CertificateValidity` constant in `pkg/certs/constants.go:23` is 10 years but is not referenced anywhere.
  - `BuildKubeConfig` makes RSA-2048 client certs valid 10 years (`pkg/certs/ensure.go`).

Files in `<DataDir>/pki` (`pkg/certs/constants.go:65-141`):

| File | Notes |
|---|---|
| `ca.crt`, `ca.key` | CN `kubernetes`. `server-ca.*` and `client-ca.*` are copies, made by `splitCACert` (`ensure.go:420-470`). |
| `apiserver.crt/.key` | CN `kube-apiserver`, serverAuth. |
| `apiserver-kubelet-client.crt/.key` | CN `kube-apiserver-kubelet-client`, clientAuth. |
| `front-proxy-ca.*` | CN `front-proxy-ca`. |
| `front-proxy-client.*` | CN `front-proxy-client`. |
| `etcd/ca.*` | CN `etcd-ca`. |
| `etcd/server.*`, `etcd/peer.*` | CN is the node name, server and client auth. |
| `etcd/healthcheck-client.*` | CN `kube-etcd-healthcheck-client`. |
| `apiserver-etcd-client.*` | CN `kube-apiserver-etcd-client`. |
| `sa.key`, `sa.pub` | Service account keypair. |

SANs:

- API server cert (`vendor/.../pkiutil/pki_helpers.go:375-422`):
  - DNS: node name (the vCluster name), `kubernetes`, `kubernetes.default`, `kubernetes.default.svc`, and `kubernetes.default.svc.<clusterDomain>`.
  - IP: first service IP (`10.96.0.1` for the default CIDR), advertise address `127.0.0.1`, and the control-plane endpoint host `127.0.0.1`.
  - `InitKubeadmConfig` sets no extra `apiServer.certSANs`, so any host or IP SANs for external access are added elsewhere. Not verified.
- etcd server and peer certs (`pki_helpers.go:439-466` plus `ensure.go:658-710`):
  - DNS: node name and `localhost`.
  - IP: `127.0.0.1`, `::1`, and the advertise address.
  - Extra SANs in standalone mode: `localhost`, `127.0.0.1`, `0.0.0.0`, plus `controlPlane.proxy.extraSANs`.
- The 8443 proxy cert is not generated in this repo. Not verified.

Kubeconfigs written into the PKI dir (`ensure.go:225-251`), with server `127.0.0.1:6443`:

- `admin.conf`:
  - It is the kubeadm `super-admin.conf`, renamed.
  - The client is CN `kubernetes-super-admin`, org `system:masters`.
- `controller-manager.conf`: user `system:kube-controller-manager`.
- `scheduler.conf`: user `system:kube-scheduler`.

The user-facing `<DataDir>/kubeconfig.yaml` is written by the controller start. It is also copied to `~/.kube/config` if that file does not exist (`pkg/setup/controllers.go:296-322`).

Rotation:

- On startup (`ensure.go:84-113`) in standalone:
  - If `pki/ca.key` is missing, generate everything.
  - Otherwise, if any leaf cert is within 90 days of expiry (`pkg/util/certhelper/cert.go:113-117`), delete leaf files except SA and CA files and regenerate.
- The watcher checks every 24 h (`pkg/certs/watcher.go:27`).
  - On expiry it rotates the leaf certs and removes `etcd/{server,peer}.{crt,key}` so they regenerate at runtime.
  - It then sleeps a random 5 s to 5 min and calls `osutil.Exit(0)`. systemd restarts the service (`watcher.go:253-269`).
- Manual: `vcluster certs rotate` and `rotate-ca`.
  - They back up to `<pki>/../pki.bak/<unix time>`.
  - They keep the SA keys. With `rotate-ca` they also regenerate the CAs.
- Warning text for an expiring CA: `CA certificate (CN=%s) expires at %s; run "vcluster certs rotate-ca" to renew`.

#### 2.5 Health checks and restart

- `etcd.WaitForEtcd` polls `MemberList` every 1 s, timeout 10 min (`pkg/etcd/util.go:18,27-51`).
- `waitForAPI` polls `GET /readyz` every 2 s, timeout 5 min, using `admin.conf` (`pkg/k8s/k8s.go:438-474`).
- If the readiness wait fails, `StartK8S` returns an error. The goroutine in `initialize.go:91-100` then calls `osutil.Exit(1)`.
- Unit: `Restart=always`, `RestartSec=5s`, `Type=notify`. Where `sd_notify` is sent is not verified.

### 3. Private nodes: how a node joins

#### 3.1 Join token (`cmd/vclusterctl/cmd/token/create.go:134-258`)

- It reads the `kubeadm-config` ConfigMap in `kube-system`. The API endpoint is `ClusterConfiguration.ControlPlaneEndpoint`.
  - Error: `getting kubeadm config: ... Are you connected to a vCluster with private nodes enabled?`.
- An optional platform endpoint comes from the annotation `vcluster.loft.sh/join-script-endpoint`, which must be https.
- It generates a standard kubeadm bootstrap token and creates the Secret `bootstrap-token-<id>` in `kube-system`:
  - Type `bootstrap.kubernetes.io/token`.
  - Labels `vcluster.loft.sh/token=true` and `vcluster.loft.sh/token-node-type=worker` (or `control-plane`).
  - Extra groups `system:bootstrappers:kubeadm:default-node-token`.
  - Usages signing and authentication.
  - Expiration is `now + --expires` (default `1h`).
- `--profile` patches the node profile spec into the Secret.
- It prints `curl -fsSLk "https://<apiEndpoint>/node/join?token=<t>" | sh -`, or the platform URL.
- With `--kubeadm`, it prints `kubeadm join <endpoint> --token <t> --discovery-token-ca-cert-hash <hash>`.
  - The hash is a `pubkeypin` of the single cert in the `kube-root-ca.crt` ConfigMap.

#### 3.2 The join script and the node

- The vCluster API server serves `/node/join` and `/node/download`, and for control planes `/node/control-plane-download/<token>`. The handlers are closed source, so the script text is not verified.
- Docs show what the script does on the node (`vcluster-docs/.../private-nodes/join.mdx`):
  - Install the Kubernetes binaries.
  - Enable and start `containerd` and `kubelet` via systemd.
  - Run kubeadm's preflight, kubelet-start and TLS bootstrap phases.
  - Write `/var/lib/kubelet/config.yaml` and `/var/lib/kubelet/kubeadm-flags.env`.
- Script flags from the docs: `--kubernetes-version`, `--repository-url`, `--binaries-dir` (default `/usr/local/bin`), `--cni-binaries-dir` (default `/opt/cni/bin`), `--skip-reset`, `--bundle-path`, `--reset-only`, `--skip-join`, `--node-name`, `--force-join`, `--skip-selinux-rpm`, `--selinux-rpm-url`, `--containerd-selinux`.
- Host requirements: systemd, `iptables`, `curl`, root (`private-nodes/node-requirements.mdx`). Control-plane docs add raising `fs.inotify.max_user_watches` to 524288.
- The node-side upgrade command is `vcluster node upgrade` with `--kubernetes-version`, `--bundle-repository` (default `https://github.com/loft-sh/kubernetes/releases/download`), `--binaries-path` (default `/usr/local/bin`), `--cni-binaries-path` (default `/opt/cni/bin`). It is a stub here.

#### 3.3 In-cluster node components

- Defaults (`chart/values.yaml:944-1000`):
  - `deploy.cni.flannel.enabled: true`.
  - `deploy.kubeProxy.enabled: true`.
  - `deploy.localPathProvisioner.enabled: true`.
- kube-proxy runs as a pod. Its ConfigMap is `kube-proxy` in `kube-system`, and its kubeconfig is `/var/lib/kube-proxy/kubeconfig.conf` (`vcluster-docs/.../4-worker-node.mdx`).
- Where the manifests for flannel, kube-proxy, CoreDNS and local-path are rendered is not in this repo. Not verified.
- Image list for private nodes (`images-private-nodes.txt`):
  - `registry.k8s.io/kas-network-proxy/proxy-agent:v0.34.0`
  - `ghcr.io/loft-sh/kubernetes:v1.36.6-full`
  - `registry.k8s.io/kube-proxy:v1.36.6`
  - `coredns/coredns:1.14.2`
- CoreDNS per minor: `pkg/constants/coredns.go`, for example `"1.36": "coredns/coredns:1.14.2"`.

### 4. Snapshot and restore in standalone

CLI:

- `vcluster snapshot create <url> --standalone` and `vcluster restore --standalone <url>` (`cmd/vclusterctl/cmd/restore.go:58-79`).
- `resolveSnapshotArgs` requires exactly 1 argument: `unexpected amount of arguments: %d, need exactly 1 argument...` (`pkg/cli/snapshot_helm.go:228-233`).
- `--standalone` with `--driver docker` errors: `--standalone cannot be used with --driver docker`.

Schemes (`pkg/snapshot/options.go:52`): `oci`, `s3`, `container`, `https`, and `azure` (handled at `:37`).

Archive format (`pkg/snapshot/client.go`):

- A tar.gz at gzip level 3.
- Entries in order:
  - Optional release at `snapshotapi.SnapshotReleaseKey`.
  - Optional request at `/vcluster/snapshot/request/<apiVersion>`.
  - For an embedded etcd store: the raw bolt DB at `/vcluster/snapshot/db`, then optional `/vcluster/snapshot/skipkeys`. This is an EtcdSnapshot archive.
  - For every other store: `/vcluster/snapshot/revision`, then one entry per etcd key. This is a KeyValueSnapshot archive. Keys under `/vcluster/snapshot/` are skipped.
- For standalone, `HostNamespace` is set to `kube-system` and `pro.SetStandaloneConstants` is called first (`client.go:121-127`).

Restore (`pkg/cli/restore_helm.go:81-148`, `pkg/snapshot/restoreclient.go:140-350`):

1. The CLI loads the standalone config and `systemctl stop vcluster`.
2. It runs `<dataDir>/bin/vcluster restore` with the env `VCLUSTER_NAME`, `VCLUSTER_STANDALONE=true` and `VCLUSTER_STORAGE_OPTIONS=<json>`. With embedded etcd it also sets `VCLUSTER_STANDALONE_IP_ADDRESS`.
3. The restore command refuses to run while the unit is active:
   - `refusing to restore: vcluster.service is %s on this host; use the vcluster CLI ("vcluster restore --standalone <snapshot-url>")...` (`cmd/vcluster/cmd/snapshot/restore.go:41-47`).
4. Embedded etcd with an EtcdSnapshot archive:
   - It backs up the etcd data dir and calls `etcdutl` `snapshot.Restore` with name and peer URL `https://<ip>:2380` and cluster token `vcluster`.
   - It sets `RevisionBump=1000`, or more if the live revision is higher, and `MarkCompacted=true`.
   - It then starts embedded etcd to delete the skipped keys.
5. Every other store:
   - An etcd archive is converted to key-value first, with the log line `Converting etcd snapshot to key-value snapshot`.
   - `restoreKeyValueSnapshot` recreates the store and streams the keys back.
6. The CLI always runs `systemctl start vcluster` afterwards, and joins any restart error into the restore error.

### 5. Conformance

AI conformance, `ai-conformance/`:

- Layout is `v1.34/vcluster-private-nodes/` and `v1.35/vcluster-private-nodes/`, each with `PRODUCT.yaml` and `README.md`.
- `PRODUCT.yaml` is a self-assessment: `platformName: "vCluster with Private Nodes"`, `platformVersion: "v0.32.0"`, with evidence URLs and notes per requirement.
- v1.34 has 9 items, all MUST: `dra_support`, `ai_inference`, `gang_scheduling`, `cluster_autoscaling`, `pod_autoscaling`, `accelerator_metrics`, `ai_service_metrics`, `secure_accelerator_access`, `robust_controller`.
- v1.35 adds 3 SHOULD items: `driver_runtime_management`, `gpu_sharing`, `virtualized_accelerator`. That gives 9 MUST and 3 SHOULD.
- The submission target is `https://github.com/cncf/k8s-ai-conformance/tree/main/v1.35/vcluster-private-nodes`. No script in this repo runs or checks it. The only repo mentions are the README logo link and these files.

Kubernetes conformance:

- `Justfile:170-175`, target `run-conformance k8s_version="1.31.1" mode="conformance-lite" tag="conf"`:
  - `create-conformance`: `minikube start --kubernetes-version {{k8s_version}} --nodes=2` and `minikube addons enable metrics-server` (`Justfile:186-188`).
  - `build-dev-image`, then `minikube image load vcluster:dev-{{tag}}`.
  - `vcluster create vcluster -n vcluster -f ./conformance/v1.31/vcluster.yaml`.
  - `sonobuoy run --mode={{mode}} --level=debug`.
  - Helpers: `conformance-status` runs `sonobuoy status`, `conformance-logs` runs `sonobuoy logs`.
- `devspace dev --profile test-conformance` uses `test/conformanceValues.yaml` (`devspace.yaml:10,137-147`).
  - That values file sets the pod-mode k8s distro with `image.tag: v1.33.1`, deployed etcd, the virtual scheduler, and node sync of all nodes.
- Both run against pod-mode vCluster on minikube. Neither exercises standalone or private nodes.
- `hack/gke-conformance-test-failures.log` is a leftover log of 6 failed NodePort and LimitRange tests.

### Upstream binaries and assets to ship

From `kubernetes/hack/download.sh` with versions from `kubernetes/hack/kubernetes-v1.36` at the time I cloned. Every asset is built for both amd64 and arm64.

| Asset | Version | Source | Used by |
|---|---|---|---|
| kube-apiserver, kube-controller-manager, kube-scheduler | `v1.36.6` (chart default) | `dl.k8s.io/release/<v>/bin/linux/<arch>/` | control plane |
| kubelet, kubeadm, kubectl | `v1.36.6` | `dl.k8s.io` | node bundle |
| etcd, etcdctl, etcdutl | `v3.6.16` | etcd-io release tarball | embedded etcd, restore |
| kine | `v0.14.16.vcluster.4`, sha256 pinned in `download.sh:20-50` | `github.com/loft-sh/kine/releases` | SQLite store |
| konnectivity-server | `v0.34.0` | copied from `registry.k8s.io/kas-network-proxy/proxy-server:v0.34.0` | egress to nodes |
| helm | `v3.22.1` | `get.helm.sh` | control plane |
| containerd, containerd-shim-runc-v2, ctr | `2.2.3` | containerd release | node bundle |
| runc | `v1.4.2` | opencontainers release | node bundle |
| crictl | `v1.35.0` | cri-tools release | node bundle |
| CNI plugins `loopback portmap bandwidth bridge firewall host-local` | `v1.9.1` | containernetworking release | node bundle |
| pause image tar and `pause-image.txt` | `registry.k8s.io/pause:3.10.2` | docker save | node bundle |
| `vcluster-tunnel` | tailscaled fork `v1.96.4-loft.3`, sha256 pinned | `github.com/loft-sh/tailscale/releases` | VPN, node bundle |
| vcluster standalone binary and `vcluster-cli` | release version | `vcluster-linux-<arch>-standalone`, `vcluster-linux-<arch>` | control plane, CLI |
| `install-standalone.sh` | release version | release asset | install |

In-cluster images (`images-private-nodes.txt`): `registry.k8s.io/kube-proxy:v1.36.6`, `coredns/coredns:1.14.2`, `proxy-agent:v0.34.0`. Flannel and local-path-provisioner images are not verified.

Packaging:

- The node bundle is `kubernetes-<ver>-<arch>.tar.gz`, containing `./release/{kubeadm,kubelet,kubectl,cni/bin/*,containerd,containerd-shim-runc-v2,ctr,runc,crictl,vcluster-tunnel,pause-image.tar,pause-image.txt}`.
- The full bundle `kubernetes-<ver>-<arch>-full.tar.gz` adds the control-plane binaries and the node bundle, and is published as a GitHub release asset on `loft-sh/kubernetes`.
- `bundle-standalone.sh` downloads it from `https://github.com/loft-sh/kubernetes/releases/download/<ver>/kubernetes-<ver>-<arch>-full.tar.gz`.
- The image `ghcr.io/loft-sh/kubernetes:<ver>-full` is built in `release.yaml` from `hack/Dockerfile`.

Guest OS packages the vm-container assumes: `iptables`, `conntrack`, `iproute2`, `kmod`, `ca-certificates`, `curl`, `systemd`, `dbus`.

## Contradictions

1. The Justfile points at a deleted file. `Justfile:173` passes `./conformance/v1.31/vcluster.yaml`. Commit `709a5f0b` removed the `conformance/` folder, a message saying it was "out of date". `just run-conformance` cannot work as written.
2. `ai-conformance/v1.35/vcluster-private-nodes/README.md:20` says "8 MUST + 3 SHOULD". Its `PRODUCT.yaml` has 9 MUST and 3 SHOULD.
3. Both `PRODUCT.yaml` files say `platformVersion: "v0.32.0"`. This repo is `v0.37.x`.
4. `create_docker.go:142-152` lists the Kubernetes image layout without `etcdutl`. `kubernetes/hack/Dockerfile:23` copies `etcdutl` into `/kubernetes/`. The docker driver bind-mounts every entry, so `etcdutl` is mounted.
5. `connect_docker.go:160` has a stale comment, "written to /data/kubeconfig.yaml". The code reads `/var/lib/vcluster/kubeconfig.yaml` (`connect_docker.go:162`).
6. The pod-mode hardening guide shows `--authorization-mode=RBAC` for the apiserver. `pkg/k8s/k8s.go:44` builds `Node,RBAC`. The doc may reflect an older version or user overrides. Not verified.
7. The install script I read is `v0.37.6`. This checkout is `v0.37.0-rc.2` plus 75 commits. The driver downloads the script matching `--chart-version`, so the two may differ.
8. The docker driver's join token is a 64-char random string in `token.txt`, sent as `/node/join?token=...&type=worker`. `vcluster token create` makes kubeadm bootstrap tokens and prints the same URL shape. The server-side validation of each form is closed source. Not verified.

## Decisions

| # | Decision | Options and effect on the work | Recommendation |
|---|---|---|---|
| D1 | How to close the closed-source gap for the node and control-plane details | **a** Get read access to `vcluster-pro`. **b** Run `strings` on the release `vcluster-linux-arm64-standalone` binary. **c** Black-box a running vind: `docker exec <cp> ps -ef`, `systemctl cat`, and copy `/etc/kubernetes`, `/var/lib/kubelet/config.yaml`, containerd `config.toml`, the flannel and kube-proxy manifests, and the join script from `/node/join`. | **c**, plus **a** if access exists. It gives exact flags and files for the parts I could not read. Any run of a release binary should happen in a sandbox. |
| D2 | Init system in the microVM | **a** Keep systemd, as the install script, `kubeadm` kubelet start and `journalctl` assume. **b** Write a supervisor in the Bend binary with `Restart=always` and 5 s delay semantics, and start kubelet and containerd itself. | **b** for "one binary". Needs a spike: kubeadm's kubelet-start phase shells out to `systemctl`. Not verified how the join script handles that. |
| D3 | Backing store for v1 | **a** kine with SQLite, the standalone default, key-value snapshots. **b** Embedded etcd, with peers, `etcdutl` restore and revision bump. | **a**. It is the default, needs no peer IP logic, and the snapshot restore path is the plain key-value one. Defer HA and embedded etcd. |
| D4 | Does the first VM also run kubelet | **a** Yes, as `joinNode.enabled: true` does by default, which needs containerd, runc, CNI, kube-proxy and flannel in the same VM. **b** Control plane only. | **a**, to match vind, where the control-plane container joins itself. |
| D5 | Join protocol | **a** Wire-compatible `/node/join?token=&type=worker` plus kubeadm bootstrap tokens, so `vcluster token create` keeps working. **b** A new simpler protocol. | **a**. The CLI already emits those tokens (`create.go:134-258`). Needs D1 to learn the script content. |
| D6 | Snapshot formats | **a** Reuse the vCluster key-value archive for cluster data. **b** Also add a vind-style whole-disk snapshot for lifecycle `snapshot` and `restore`. | Both. **a** gives cross-compat with `vcluster snapshot`. **b** replaces the Docker volume tarballs. Archive entry names and order are listed above. |
| D7 | PKI | **a** Reproduce file names, CNs, SANs, key types and validity exactly. **b** Pick your own. | **a**. The apiserver, controller-manager, restore code and join flow all read these names. Use RSA-2048, 1 year leaf, 10 year CA, 90 day renewal. |
| D8 | Asset delivery | **a** Fetch `kubernetes-<ver>-arm64-full.tar.gz` from the `loft-sh/kubernetes` release. **b** Rebuild each upstream binary. | **a** with the versions pinned in the table and sha256 for kine and tailscale. |
| D9 | Kubernetes version | Chart default is `v1.36.6`. AI conformance exists only for v1.34 and v1.35. | Pick one version per release and say which conformance applies. v1.35 covers the AI items. |
| D10 | Conformance setup | **a** Fix the Justfile target by restoring a values file. **b** Write a new target that creates the microVM cluster and runs `sonobuoy run --mode=certified-conformance` or `conformance-lite`. | **b**. The old target runs pod-mode on minikube and is broken. Sonobuoy flags beyond `--mode` and `--level` are not in this repo. |

## Unchanged

- Helm and platform drivers: `create_helm.go`, `create_platform.go`, `connect_helm.go`, `delete_helm.go`, and the chart.
- The syncer, resource controllers, and `pkg/server` request handling apart from the `/node/*` long-running exemption.
- The snapshot storage backends (`oci`, `s3`, `azure`, `container`) and the snapshot request and controller logic.
- The `vcluster.yaml` schema (`config/config.go`). The rewrite consumes it.
- The `ai-conformance/` files, unless you re-certify.

## Candidate work items

Reference implementation in this repo, with nearby tests. Each item is something the Bend rewrite must mirror.

Docker driver analogue:
- `pkg/cli/create_docker.go:53-263` create flow. Tests: `pkg/cli/create_docker_test.go` covers `getInstallStandaloneScript`, script validation and `pinKubernetesVersion`.
- `pkg/cli/create_docker.go:618-736` container args and mounts.
- `pkg/cli/create_docker.go:738-825` node join and node reconcile.
- `pkg/cli/create_docker.go:886-954` and `827-884` asset pulls.
- `pkg/cli/docker_runtime.go:151-216` kernel modules. Tests: `pkg/cli/docker_runtime_test.go`.
- `pkg/cli/delete_docker.go:37-150`, `pause_docker.go`, `resume_docker.go`, `connect_docker.go:67-306`, `list_docker.go`. No dedicated tests found.
- `pkg/cli/snapshot_docker.go`, `restore_docker.go`. Tests: `pkg/cli/snapshot_docker_test.go`.

Standalone runtime:
- `pkg/k8s/k8s.go:31-250` process flags and `:258-380` kine and backing store. Tests: `pkg/k8s/k8s_test.go`.
- `pkg/util/command/command.go:44-126` process runner with pid file. Tests: `command_test.go`.
- `pkg/certs/ensure.go:84-113`, `225-251`, `658-710`, `pkg/certs/rotate.go`, `pkg/certs/watcher.go:26-270`. Tests: `ensure_test.go`, `watcher_test.go`.
- `pkg/kubeadm/config.go:13-34`.
- `pkg/etcd/util.go:27-51`, `pkg/etcd/client.go:60-110`. Tests: `client_test.go`, `util_test.go`.
- `pkg/util/standalone/*`. Tests: `host_test.go`, `metadata_test.go`, `service_manager_test.go`.
- `pkg/setup/controllers.go:296-322` kubeconfig writing.
- `pkg/config/parse.go:59-80`, `pkg/config/load.go`.

Join and token:
- `cmd/vclusterctl/cmd/token/create.go:134-258`.
- `cmd/vcluster/cmd/node/upgrade.go`.
- `pkg/server/server.go:190-200`.

Snapshot and restore:
- `pkg/snapshot/client.go:205-420`, `pkg/snapshot/restoreclient.go:140-520`, `pkg/cli/restore_helm.go:76-148`, `cmd/vcluster/cmd/snapshot/restore.go`. Tests: `pkg/snapshot/restoreclient_test.go`, `cmd/vcluster/cmd/snapshot/restore_test.go`, `pkg/snapshot/client_test.go`.

Conformance:
- `Justfile:170-193` stale target. `devspace.yaml:10,137-147`. `test/conformanceValues.yaml`.
- `ai-conformance/v1.35/vcluster-private-nodes/PRODUCT.yaml` and `README.md:20`.

Per option:
- D1c: capture from a running vind `/etc/systemd/system/*.service`, `/var/lib/kubelet/*`, `/etc/containerd/config.toml` and the join script. Nothing in this repo changes.
- D2b: `pkg/util/command/command.go` and `pkg/util/standalone/service_manager.go` are the behaviours to reimplement.
- D3a: `pkg/k8s/k8s.go:28,274-303` and `pkg/snapshot/restoreclient.go` key-value path.
- D3b: add `pkg/snapshot/restoreclient.go:140-350` and `pkg/pro/embedded_etcd.go` behaviour. The latter is closed.
- D10b: replace `Justfile:170-193`.

## Links

- `https://github.com/loft-sh/vcluster` and release `https://github.com/loft-sh/vcluster/releases/tag/v0.37.6`, assets `install-standalone.sh`, `bundle-standalone.sh`, `images.txt`, `images-private-nodes.txt`
- `https://github.com/loft-sh/kubernetes`, files `hack/download.sh`, `hack/Dockerfile`, `hack/kubernetes-v1.36`, `.github/workflows/release.yaml`
- `https://github.com/loft-sh/vm-container`, files `Dockerfile`, `files/entrypoint.sh`, `files/create-kubelet-cgroup.sh`, `files/escape-cgroup.sh`
- `https://github.com/loft-sh/vcluster-docs`, files `vcluster/deploy/worker-nodes/private-nodes/join.mdx`, `vcluster/deploy/worker-nodes/private-nodes/node-requirements.mdx`, `vcluster/deploy/control-plane/binary/basics.mdx`, `vcluster/deploy/control-plane/binary/node-requirements.mdx`, `vcluster/deploy/control-plane/binary/manage.mdx`, `vcluster/deploy/control-plane/docker-container/basics.mdx`, `vcluster/deploy/control-plane/kubernetes-pod/security/hardening-guide/private-nodes/2-etcd.mdx`, `.../4-worker-node.mdx`, `vcluster/_partials/config/controlPlane/standalone/joinNode.mdx`
- `https://github.com/cncf/k8s-ai-conformance/tree/main/v1.35/vcluster-private-nodes`
- `https://github.com/loft-sh/vcluster-pro`. Not readable.