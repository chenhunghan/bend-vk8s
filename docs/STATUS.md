# Status against docs/GOAL.md

Each item is checked only with evidence: a commit, test output, or a
conformance archive. Known divergences from vcluster are listed at the end.

## 1. Gates

- [x] `bend PROOF.bend` prints ALL PROOFS CHECK and `scripts/check.sh`
  passes. The gate now also compiles host/init.bend and host/vk8s.bend:
  PR #6 had broken the host build without CI noticing.
- [x] `bend PROOF.bend --verdict` prints ALL PROOFS CHECK for the whole
  tree, re-checked by the Lean-verified kernel (2026-11-07, 3 min 19 s,
  out/verdict.log).
- [x] Every module on main has laws/done/<module>: sha256, names, meta,
  args, plan, cli, kubeconfig, subject, supervise, services, duration,
  table, assets, manifest, core, mappings, configs, nodes, storage. Open
  factory PRs add theirs as they land.

## 2. Conformance

- Run 1, 2026-11-07, single node, etcd, archive
  `out/conformance/202611070634_sonobuoy_*.tar.gz`: 444 passed, 6 failed,
  7136 skipped.
  - 2 failures were "Conformance test suite needs a cluster with at least
    2 nodes" (DaemonSet rollback, two untainted nodes).
  - 4 were session affinity. xt_recent was missing from the assets used
    for that run and is now in scripts/guest/modules.txt.
- [x] (a) Run 2, 2026-11-07, on `vk8s create conf --nodes 2
  --backing-store etcd` (3 VMs, current assets): Status passed, 450 passed,
  0 failed, 7136 skipped. Archive:
  `out/conformance/202611070848_sonobuoy_3cd8fa08-b69e-4f71-87c9-ec994590115c.tar.gz`.
- [x] Run 3, 2026-11-09, re-run on main c137a7f after the security fixes,
  vcluster's endpoint-reconciler=none, the request channel and the share
  quota, on the same 3-VM etcd setup: Status passed, 450 passed, 0 failed,
  7136 skipped. Archive:
  `out/conformance/202611091200_sonobuoy_532e9287-2520-446c-aecd-e01a400c3be4.tar.gz`.
- [x] Run 4, 2026-11-10, on main 322fa84  after flannel host-gw and bend-vmm
  cf57ce4 (NAT segments follow the guest's MSS), same 3-VM etcd setup:
  Status passed, 450 passed, 0 failed. Archive:
  `out/conformance/202611092130_sonobuoy_cf57387e-b642-47de-862b-83a1f6a259ef.tar.gz`.
- [ ] (b) classic mode. Sonobuoy quick passes (2026-11-10, main fb557e6,
  `vc` over a 2-VM `hc`: 8 passed, 0 failed). It needed one fix: fake nodes
  kept the node.kubernetes.io/not-ready taint that TaintNodesByCondition
  adds on create, which vcluster's createFakeNode removes. Fixed with
  Classic.node_untaint and law classic.fake_node_untaint. A full
  certified-conformance run with fake nodes is in progress; the vcluster
  conformance profile (virtual scheduler, real nodes) is PR #26.

## 3. Classic mode

- [x] services, endpoints and endpointslices translator (PR #7, laws from
  vcluster's syncer_test.go).
- [x] Pure translators merged with laws from vcluster's *_test.go: core
  sync framework (#5), mappings (#8), configmaps/secrets/serviceaccounts
  (#15), nodes/fake nodes/events (#16), PVC/PV/StorageClass/PriorityClass
  and CSINode (#14).
- [x] Pods (#9) merged, with laws from translator_test.go, syncer_test.go
  and diff_test.go.
- [x] k8sdefaultendpoint and servicesync (#10) merged with laws from
  vcluster's tests. The standalone guest now runs as vcluster does: the API
  server has `--endpoint-reconciler-type=none`, and PID 1 writes
  default/kubernetes from Ep.standalone_endpoints and Ep.standalone_slice.
  Tested on a 2-node cluster: Endpoints and the slice at 10.10.0.2:6443
  carry kubernetes.io/service-name, CoreDNS became ready, and a pod
  resolved kubernetes.default.
- [x] CoreDNS in Bend (#11): src/guest/coredns.bend ports vcluster's
  template.go and coredns.go. Every TestProcessManifests and
  TestProcessCorefile case is a law per document, so they fit the verdict
  kernel. The guest writes Coredns.default_manifest() and applies it;
  scripts/guest/coredns.yaml is no longer in the image and survives only as
  the test fixture it must equal. Tested: CoreDNS became available and a
  pod resolved kubernetes.default.
- [~] Classic-mode host contract on main: `vk8s create NAME
  --host-kubeconfig F [--host-namespace NS]`, defaulting to vcluster-NAME.
  The host kubeconfig reaches the guest share, rewritten for the NAT
  (Kubeconfig.for_guest, laws), with `VK8S_MODE=classic` and
  `VK8S_HOST_NAMESPACE` on the kernel command line. Every vk8s cluster
  carries 10.0.2.2 in its serving certificate.
- [~] Syncer runtime (#18) merged: two watch drivers on
  bend-kube-runtime@0.5.5.0 with the leadership fence, vcluster's Lease
  (host namespace, vcluster-<vc>-controller), and Services, ConfigMaps,
  Secrets and ServiceAccounts with vcluster's defaults. It runs as
  /usr/bin/vk8s-guest, a dynamic glibc build, because bend-kube dlopens
  libssl.so.3. CI syncer-envtest has 35 PASS, 1 SKIP (pods). The host CLI
  detects the host cluster's service CIDR as vcluster does (src/net/cidr.bend,
  laws from servicecidr_test.go) and gives it to the virtual API server.
  Tested on this Mac: `vk8s create vc --host-kubeconfig` over a vk8s host
  `hc` detected 10.96.0.0/12. A virtual Service `web` appeared on the
  host as web-x-default-x-vc, the virtual Service took the host cluster IP
  (vcluster's recreateService), and the Lease vcluster-vc-controller sits
  in the host namespace.
- [~] Pods, fake nodes, host events, claims and fake volumes wired into
  the syncer runtime (src/sync/classic.bend, laws/classic.bend); the
  leader starts the fake kubelet on :10250; Plan.classic applies
  vcluster's default CoreDNS. CI syncer-envtest covers pod sync, status
  flowback, a fake node, kubectl logs through the fake kubelet, host
  events and claims. Known gaps (at that time): host pods got the
  virtual default/kubernetes IP as KUBERNETES_SERVICE_HOST; they now get
  the host Service's IP (see below); pod events are logged, not written as
  virtual Events. Not yet tested on the Mac.
- [x] Fake-kubelet proxy (#20) merged: src/net/kubelet.bend with laws
  (route parse/render, host requests, ownership, stats rewriting) and
  host/kubelet_proxy.bend on :10250 with client-certificate authentication.
  The new TlsSrv.connect shares the server's session table so splice
  relays. Forwarded heads drop Authorization and Impersonate-*. The
  kubelet-envtest CI job passes (kubectl logs, logs -f and exec reach the
  host pod). The syncer starts it in the guest (#23).

- [~] Classic wiring (#23) merged: pods, fake nodes, events, PVCs, fake PVs,
  the fake kubelet started by the syncer, and CoreDNS deployed in the
  virtual cluster. The host CLI also creates the vcluster's host Service
  (Endpoints at 10.0.2.2:PORT, the API forward reached through bend-vmm's
  NAT) and puts its IP in the API server's SANs. The controller manager
  runs with vcluster's classic flags (no node lifecycle).
  Tested on this Mac, `vc` over a fresh 2-VM host `hc`: a pod created in
  the virtual cluster ran on the host (hc-worker-1), its status flowed
  back, `kubectl logs` and `kubectl exec` worked through the fake kubelet,
  and the fake node is Ready.
  Open: the virtual default/kubernetes kept 10.96.0.1, the host's own
  kubernetes IP, instead of the host Service's, so in-pod API calls
  reached the host API server and CoreDNS was not ready. Cause: the
  runtime dropped the default/kubernetes key, and no watch saw the host
  Service. The fix-classic-kubernetes-service PR queues the key, watches
  the host Service by name, and takes pods' KUBERNETES_SERVICE_HOST from
  it (CI syncer-envtest checks it). A VM's NAT DNS could go stale after a
  host network change (fixed in bend-vmm 19e3a0d, pinned).
- [x] default/kubernetes in classic mode (#25 merged). Tested on this Mac
  2026-11-10, on main 5100a96, with `vc` over a fresh 2-VM `hc`. The virtual
  default/kubernetes took the host Service's IP (10.108.237.39), and host
  pods get it as KUBERNETES_SERVICE_HOST. CoreDNS became Ready, and a
  virtual pod resolved kubernetes.default.svc.cluster.local and read
  /version from the virtual API server through the host Service.
  The test found a pod-egress stall: bend-vmm's NAT sends 1460-byte
  segments whatever MSS the guest announces (src/net/nat.bend:405), so
  pods on flannel vxlan (MTU 1450) could open TCP connections through the
  NAT but never finished TLS. Flannel now uses host-gw on the VM LAN, so
  pods keep MTU 1500. The NAT fix was reported to bend-vmm. The standalone
  conformance runs above used vxlan; the classic conformance run
  re-exercises pod networking on host-gw. bend-vmm then fixed the NAT
  (cf57ce4: segments follow the guest's MSS), pinned in b2fa246.
- [x] Classic egress through konnectivity (d3b8ed7). vcluster runs inside
  the host cluster; the vk8s VM does not, so the virtual API server could
  not reach webhook Services, aggregated API servers, pod IPs or kubelets.
  The preliminary classic conformance run failed on webhooks.
  Now the API server's "cluster" egress (the upstream
  EgressSelectorConfiguration) goes through the bundled konnectivity-server.
  Its agent (registry.k8s.io/kas-network-proxy/proxy-agent:v0.34.0, pinned
  by digest) is a virtual kube-system Deployment that the syncer places on
  the host. It reaches the server through a second host Service,
  `<vc>-konnectivity`. The vcluster Service gained vcluster's kubelet port
  (to the fake kubelet), and nodes advertise its IP as their kubelet
  address. Tested on this Mac: the service proxy, pod proxy, logs and exec
  work through the agent. A focused sonobuoy run passed AdmissionWebhook
  "should mutate everything except 'skip-me' configmaps", Aggregator
  "Sample API Server" and CustomResourceConversionWebhook "convert from CR
  v1 to CR v2". tests/konnectivity.bend and laws cli.konn_port etc. cover
  the plan.
- [x] `vk8s delete` of a classic cluster now removes its host objects, as
  vcluster delete does: the two Services, objects labeled
  vcluster.loft.sh/managed-by, the Lease, and the host namespace if vk8s
  created it (annotation vcluster.loft.sh/created=true) and no other
  vcluster is left in it. Stale objects from an earlier cluster of the same
  name had made the syncer delete a new virtual ConfigMap (vcluster's
  HostOld rule).
- [x] vcluster's conformance profile on classic (#26, b21c3d5, 360c320). It
  runs with the virtual scheduler, real nodes (selector.all), proxyKubelets
  off, and PV/PriorityClass/StorageClass toHost
  (docs/examples/conformance-classic.yaml; the one divergence is embedded
  etcd). A first classic certified run (2026-11-10) found these, each now
  fixed and checked on this Mac:
  - NodePort tests failed while nodes advertised the Service IP. Real nodes
    now keep the host's addresses and gain an InternalDNS address (the
    vcluster Service IP) that the API server prefers for kubelet traffic.
  - DNS PTR, multiport endpoints and ExternalName→ClusterIP/NodePort
    failed because the virtual Service was recreated at the host's IP, so
    clients held a dead address. vcluster avoids this with a proxy filter
    that creates the host Service first. vk8s has no proxy, so the host
    Service now asks for the virtual ClusterIP and NodePorts; the
    translated Service is the fallback.
  - The in-place resize "with equivalents" test failed: the virtual pod's
    observedGeneration now follows the virtual generation, less the host's
    lag.
  - Guests fell behind the host clock while the Mac slept, so TLS between
    clusters failed ("not yet valid"). PID 1 now sets the clock from the
    RTC every 10 s.
- [x] Endpoints and EndpointSlices to the host in the classic syncer
  (`CL.Classic.eps`, a third watch table). Selector-less Services with
  hand-made Endpoints or EndpointSlices now reach the host, which the
  multi-port EndpointSlice conformance test needs. Envtest covers it.
- [x] Classic run 2 (2026-11-10, 360c320) found seven failures; fixes since:
  - Endpoints and EndpointSlices of selector-less Services now sync to the
    host (#27, vcluster's endpoints/endpointslices syncers).
  - The syncer reads the host's version, so in-place resizes reach host
    pods (vcluster skips the resize on hosts below 1.35; vk8s never knew
    the version).
  - An update that loses a race (409) is retried once with the current
    resourceVersion. A busy host pod had conflicted 325 times in a row,
    which also stalled its status (pod lifecycle) and slowed the queue
    (pods Pending for 5 minutes).
  - The conformance profile restores vcluster's
    --service-account-jwks-uri extraArg (OIDC discovery).
  - Still under watch: "DNS for ExternalName services" (repeated Service
    recreation under quick successive changes; a manual repro converged).
  Run 3 is in progress on 2ef57ab.
- [x] Virtual pods that SyncToHost deletes (deletionTimestamp or startTime,
  no host pod) no longer wait on a token, so terminating namespaces
  finish (7c0d4f5).

- [~] vcluster's conformance profile in classic mode
  (test/conformanceValues.yaml): the vcluster.yaml subset takes
  `controlPlane.advanced.virtualScheduler`, `sync.fromHost.nodes.selector`
  and `networking.advanced.proxyKubelets` (laws from the chart and
  validation.go). With the profile the syncer runs the real node syncer
  (selector.all: every host node with its status), the virtual
  scheduler's pod rules (no host pod before a node is bound; no affinity,
  topology spread or node selector on the host), real PersistentVolumes,
  StorageClasses and PriorityClasses to the host, and CSINodes from the
  host; the guest runs kube-scheduler and vcluster's virtual-scheduler
  controller manager flags, and the syncer reads the share's
  vcluster.yaml. CI syncer-envtest covers it on a second pair of control
  planes with a real kube-scheduler. laws/done/classic is added. The
  virtual scheduler applies to both classic control planes, with and
  without konnectivity (tests/classic_plan.bend). With proxyKubelets off,
  as in vcluster's profile, real nodes keep the host nodes' kubelet
  addresses, which the virtual API server reaches through the
  konnectivity agent in the host network; with byIP on, they advertise
  `--kubelet-ip` (the vcluster Service IP), which the agent routes to the
  fake kubelet. Not yet run under sonobuoy (2b).

## 4. Standalone

- [x] Join tokens. PR #13 merged the pure join module: bootstrap tokens,
  the /node/join request, authorization and the join script, with design
  decisions in docs/ref/standalone-decisions.md J1. `vk8s token create
  NAME [--expires 1h] [--kubeadm] [--control-plane]`, `token list [--output
  json]` and `token delete` follow vcluster's token commands:
  - Token Secrets carry vcluster's labels.
  - `--expires` uses Go's time.ParseDuration, so vcluster's "1d" quirk is
    kept (laws generated from Go's own output).
  - The `--kubeadm` discovery hash matched openssl's SHA-256 of the CA's
    public key.
- [ ] Serving /node/join from the control plane. vk8s's own workers join
  directly, and machines outside vk8s cannot reach the VM LAN, so it is
  low priority.
- [~] vcluster.yaml subset: the pure parser, defaults and validation are
  merged (#17, 106 laws, vcluster's ParseConfigBytes messages, docs/CONFIG.md).
  `vk8s create NAME -f vcluster.yaml` validates the file with vcluster's
  messages, takes the backing store from it, and gives each component its
  extraArgs: the guest merges them over vk8s's flags (src/guest/values.bend,
  laws). Settings vk8s cannot honor yet are refused by name: another
  Kubernetes version, service or pod CIDR, cluster domain, or CoreDNS
  replica count. `describe --config-only` prints the file. Tested: a
  vcluster.yaml with embedded etcd and API server extraArgs (`--v=2
  --event-ttl=2h`) gave an etcd cluster whose API server logged exactly
  those flags.
- [~] Open snapshot format (#21, pkg/snapshot): the tar record codec, URL
  parsing, archive kinds and restore plans, with laws from vcluster's
  tests. Every law proves, the general tar round trip included
  (laws/done/snapshot). Not wired to the CLI, which uses vk8s's
  VM-level format.
- [x] whole-cluster snapshot/restore, VM level (see 5).
- [~] Certificates. `vk8s certs rotate NAME` and `vk8s certs check NAME`
  run over a host-to-guest request channel: the host writes share/requests,
  PID 1 runs Plan.request's steps, and only known actions are accepted
  (law). Rotate renews every certificate with kubeadm, keeping the CA, then
  restarts the control plane on the new ones and rebuilds the host-owned
  kubeconfig. Tested: the serving certificate's serial changed, the API was
  back in about 1 s, and kubectl worked. vcluster's watcher is in place:
  PID 1 checks every 24 h and rotates every leaf certificate when one is
  within 90 days of expiry, as pkg/certs/watcher.go does. The decision is
  Plan.certs_expiring (laws for 89d, 90d, hours, `<invalid>` and years),
  reading kubeadm's leaf table (all 11 found on a live cluster). The same
  check runs on request (`certs-auto`).
  - `vk8s certs rotate-ca NAME` follows vcluster's Rotate(withCA): back up
    to pki.bak/<time>, remove everything but sa.key and sa.pub, make the
    whole PKI anew, and restart the daemons. Once the API is back it
    refreshes cluster-info, mints a join token and restarts the add-ons;
    the workers rejoin under the new CA. Tested: the CA fingerprint
    changed, both nodes were Ready, an existing pod kept running, CoreDNS
    was ready again in about 22 s, and a pod resolved kubernetes.default.
    Workloads that call the API must be restarted to load the new CA, as
    with vcluster. vcluster's own certs commands exist only for its helm
  driver.
- [x] `vk8s node add NAME [--count N]` and `vk8s node delete NAME NODE
  [--drain=false]`. Delete follows vcluster node delete: cordon, then
  drain with Force, IgnoreAllDaemonSets, DeleteEmptyDirData, a 30 s grace
  and a 30 min timeout, then delete the Node; vk8s also stops the worker
  VM. Worker indices are kept in cluster.env WORKERS and survive upgrades.
  Tested: add 2, delete the middle worker, upgrade keeps workers 1 and 3,
  and `--upgrade --nodes 1` removes the stale Node object.

- [x] Pure vcluster.yaml subset: parser, defaults, validation, 106 laws
  proven (config_yaml, vcluster_config are done and pass the verdict
  kernel). Not yet wired to host IO. See docs/CONFIG.md.

## 5. CLI parity (`vcluster --driver docker`)

Smoke-tested on this Mac, 2026-11-07, with a 2-node cluster:
- [x] create (2 nodes in 21.7 s with sqlite; 3 nodes in 27.8 s with etcd)
- [x] delete. It is graceful: bend-vmm `powerdown` makes PID 1 stop the
  daemons last-started-first, unmount and power off. If the guest does not
  power off within 60 s, vk8s quits the VMM, then kills it.
  `--delete-context` works.
- [x] list, with the NAME/STATUS/CONNECTED/AGE table and `--output json`
  byte-exact against vcluster's Go code (laws in laws/table.bend,
  laws/cli.bend, laws/duration.bend).
- [x] connect: `--print`, `--update-current`, `-- COMMAND`
- [x] pause, resume
- [x] snapshot create NAME PATH and restore NAME PATH. The snapshot pauses
  the cluster, clones the disk copy-on-write and resumes; the tar.gz has
  metadata.json first (167 MB for a 2-node cluster). A ConfigMap and a
  Deployment survived a restore into a new name.
- [x] create --upgrade, which follows vcluster's flow: "already exists, use
  --upgrade" and "recreating it...". It stops the VMs gracefully, keeps the
  data disk and port, and applies new settings. Tested going from 1 to 2
  workers and 2 to 3 GiB in 39 s; the data survived.
- [x] `node load-image NAME NODE --archive FILE` (tar or tar.gz) through
  the request channel. Image names are restricted to [a-z0-9.-] (law).
  `--image` needs Docker, so vk8s explains and points to `--archive`.
- [x] describe (`--config-only`, `-o json`)
- [x] logs NAME [COMPONENT] (vk8s only; vcluster has no `logs` command)

## 6. Production readiness

- [~] Binary that downloads hash-pinned assets.
  scripts/release-assets.sh packs them (about 355 MB) and generates
  src/cli/manifest.bend. vk8s verifies each archive's SHA-256 before
  unpacking. Tested against a local server: a tampered archive is refused
  and leaves nothing behind, and a valid set boots a 2-node cluster.
  scripts/guest/fetch-assets.sh rebuilds the inputs from public, pinned
  sources. The user approved publishing the release (2026-11-09); it goes
  out with the final asset build. The user chose ad-hoc signing with the
  Hypervisor entitlement (2026-11-09); no Developer ID is needed.
- [x] Image cache. `vk8s cache start|stop|status` runs a small VM with
  CNCF distribution v3.1.2 as pull-through registries for docker.io,
  registry.k8s.io, ghcr.io and quay.io, on 127.0.0.1:15001-15004. Every
  cluster's containerd tries it first through hosts.toml and falls back to
  upstream. `create` starts it unless VK8S_CACHE=off. Measured: nginx
  pulled in 8.54 s cold and 1.94 s from the cache in a second cluster.
- [x] Soak (scripts/soak.sh 10 60). Run 1, 2026-11-07:
  - 10 create/delete cycles, each with 1 worker and a pod: all passed,
    about 24 s to create and 15 s to delete.
  - 60-minute workload: 173 rounds of ConfigMap writes and deletes and 17
    pause/resume cycles; the Deployment was 4/4 ready at the end and the
    API server never restarted.
  - Leaks: zero VMM processes, zero sockets, disk 309 MiB lower than at
    the start.
  - One ConfigMap write failed, at round 92. The API server logged no
    error then, so the client side is suspected, and out/vk8s was rebuilt
    during the run.
  - Run 2 used a frozen binary. Cycle 10's create reported "did not come
    up" within 1 s although the VM had booted: a single failed `kill -0`
    check under load counted as a dead VMM. Fixed (b83ba80): a VMM counts
    as gone only after three failed checks in a row.
  - Run 3 (frozen binary with that fix, current guest), 2026-11-07:
    - 10/10 create/delete cycles passed (22-28 s and 15 s).
    - Workload: 174 rounds and 17 pause/resume cycles with zero failed
      calls, the Deployment 4/4, no API server restart.
    - Zero VMM processes and zero sockets left.
    - Its whole-volume disk check failed by 2249 MiB, but asset builds and
      test clusters made meanwhile (f6, classic, hc, vc) total 3.6 GB.
      The check now measures what the soak itself can leak: its cluster
      directory and the image cache's growth (cf789bc).
- [x] Security review of the guest/host boundary: a factory explorer
  report, review-vk8s-security-boundary, 2026-11-07.
  Fixed and tested on this Mac:
  - F1: the guest's kubeconfig is never used as is. Kubeconfig.sanitize
    keeps only the three embedded certificates and sets the server to the
    host's forward; laws cover an exec plugin, another server and a skipped
    TLS check. connect, exec and kubectl all use the host-owned file
    (mode 0600).
  - F4: share files are read with O_NOFOLLOW, regular files only, size
    bounded. The join token must match kubeadm's pattern (law). The host
    builds discovery.conf from the CA instead of copying the guest's.
  - F2/F3: restore unpacks into a private staging directory. Exactly
    metadata.json (first), cluster.env and data.img are accepted, all
    regular files, and a qcow2 disk is refused. Tested: a symlinked
    cluster.env, a qcow2 header and an extra member are all refused, and
    the victim file was untouched.
  - F7: asset fetch uses a unique staging directory per run and accepts
    exactly one regular member per archive, extracted by name.
  - F5: the cache mirror has `pull` only, so tags resolve upstream (law).
  - H3: snapshot archives and host-owned files are mode 0600.
  - H2: no never-expiring tokens. Each boot mints a 1 h join token, and
    `node add` mints its own 1 h token as a kubeadm bootstrap-token Secret
    (law). Tested: every token in a cluster carries an expiration.
  - C: proc.c checks every spawn-setup return; the musl closefrom shim
    closes up to the open-file limit; the TLS listener is CLOEXEC; exec.c
    frees on failure and checks setenv.
  - F6: bend-vmm 0x9b8f2c0a3d76a7c0e967cd5ae59d1b06 (requested from the
    bend-vmm session). Every VM's share has a 1 GiB quota; writes past it
    fail with ENOSPC. The VMM writes the console itself and rotates it at
    64 MiB, keeping 2. PID 1 trims daemon logs about once a minute: past
    32 MiB a log keeps its last 8 MiB as .log.1. Tested: the flags are
    active and the cluster works; the trim logic was checked on a 40 MiB
    log.
  - Splice idle deadline: a TLS splice with no bytes either way for 4 h
    ends, kubelet's --streaming-connection-idle-timeout default; the
    deadline resets on every byte.
  Every finding of the review is fixed.
- [x] README (every command, building from source, verification) and
  DESIGN.md (snapshot, shutdown, upgrade, cache, pinned assets).

## Follow-ups after the release

- Move the syncer's object updates from full PUTs (with a 409 retry) to
  merge, strategic or server-side-apply patches. The pinned
  bend-kube-runtime client has them (Client.patch, Client.apply).
- Real-node reconciles take 3-4 s with the virtual scheduler: each lists
  the node's host pods in every namespace from the API (vcluster reads an
  informer cache). A watch-backed cache of host pods would free the single
  worker; the 30 s pod resync covers events left waiting meanwhile.
- Move the pin from bend-kube-runtime 0.5.5.0 to 0.7/0.8, whose
  Client.replace_retry is the 409 retry vk8s hand-writes, and consider
  Kube.control (per-watch cluster config, RAnnotated/RMap relations) for
  the syncer loop. It reconciles from
  caches one key at a time, unlike vk8s's ordered writes from fresh GETs.

## Known divergences

- The image cache stands in for vind's experimental.docker.registryProxy,
  which reads the host Docker's image store; a vk8s host has no container
  runtime.
- Factory PR deviations, as recorded in each PR: nodes #16 rounds
  requests per container and reads a negative quantity as 0. Pods #9
  compares resource quantities as text ("1Gi" differs from "1024Mi"), and
  resolves Go's random map order deterministically.
- Concrete laws too heavy for the verdict kernel's fuel become executable
  tests instead (the SHA-256 of a whole certificate in join #13). Laws
  are never weakened to fit; they are split.
- The kube context is `vk8s_NAME`, where vcluster names it
  `vcluster-docker_NAME`.
- describe shows the VMM pid as "Container ID" and adds Nodes and Backing
  store.
- Snapshots carry the control plane's disk only. On restore, workers join
  afresh with empty disks, and every node restarts its pods, as after a
  reboot (the kubelet's state is wiped at boot).
- `restore` keeps the guest's original node names, so a cluster restored
  under a new name still has nodes named after the old one.
- default/kubernetes is written once at boot. vcluster's controller
  watches it; in standalone the address never changes, so a one-time write
  suffices.
