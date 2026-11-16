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
- [x] (b) classic mode. Run 17, 2026-11-12, on main 032b6b9 (assets
  classic19), vcluster's conformance profile
  (docs/examples/conformance-classic.yaml: virtual scheduler, real nodes,
  embedded etcd) for `vc` over a fresh 3-VM `hc` (1 control plane, 2
  workers): Status passed, 450 passed, 0 failed, 149 min. Archive:
  `out/conformance/202611111630_sonobuoy_fdc0fc86-fe81-41be-bec0-f269b76ab45b.tar.gz`.
  The runs before it and their fixes are listed under section 3.
- History: Sonobuoy quick passes (2026-11-10, main fb557e6,
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
- [x] Classic-mode host contract on main: `vk8s create NAME
  --host-kubeconfig F [--host-namespace NS]`, defaulting to vcluster-NAME.
  The host kubeconfig reaches the guest share, rewritten for the NAT
  (Kubeconfig.for_guest, laws), with `VK8S_MODE=classic` and
  `VK8S_HOST_NAMESPACE` on the kernel command line. Every vk8s cluster
  carries 10.0.2.2 in its serving certificate.
- [x] Syncer runtime (#18) merged: two watch drivers on
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
- [x] Pods, fake nodes, host events, claims and fake volumes wired into
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

- [x] Classic wiring (#23) merged: pods, fake nodes, events, PVCs, fake PVs,
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
- [x] Classic runs 3 (2ef57ab) and 4 (0c6856e) each ended with four failures,
  fixed since:
  - ExternalName to ClusterIP changed the Service's address every round.
    While the host Service has no IP, the host is now updated instead of
    the virtual Service being recreated (vcluster's proxy patches the host
    first).
  - A 409 retry on a virtual node overwrote a test's NoExecute taint.
    Fresh-resourceVersion retries now apply to host objects only.
  - Some scheduled pods never reached the host, with no error. Virtual
    pods without a host pod are now requeued every 30 s. Reconciles over
    3 s are logged; real-node reconciles take 3-4 s (see follow-ups).
  - Preemption's extended resource was lost. A user's change to a real
    node's capacity now goes to the host node's status (vcluster's
    nodechanges filter).
  - Pod lifecycle and init containers showed stale conditions. The
    syncer took its own status write for a user's
    (conditionsCopyBidirectional). A key's last snapshot is now the object
    the step wrote, as vcluster's informer holds its own write.
- [x] Classic run 5 (4393dd6) ran 1 h 55 min with no failure, then one: a
  scheduled pod (Secrets via the environment) never reached the host, with
  no syncer activity for it. The 30 s resync reads the syncer's own stores,
  so the watch event never arrived. bend-kube-runtime 0.8.1.0 fixes a
  watcher that lost an event after a line it could not parse, and a PUT
  replayed after a stale pooled connection (spurious 409s): pinned in
  #28.
- [x] Classic run 6 (9d75014) ran 1 h 25 min without a failure, then two:
  - An evicted Job pod never left. Its host pod vanished before its final
    status reached the virtual pod, which stayed non-terminal under the
    Job's finalizer. A virtual pod being deleted with no host pod now
    becomes Failed first.
  - DaemonSet pods were not synced for 5 minutes. The virtual pod watch
    stayed open but delivered nothing until its 290 s timeout. Watches now
    end after 60 s, and the 30 s resync lists the virtual and host pods
    fresh instead of reading the watch stores.
- [x] Classic run 7 (50cbe0a) ran 70 min without a failure, then one: a pod
  stuck on FailedMount because its namespace's kube-root-ca.crt never
  reached the host. ConfigMaps sync only when a pod uses them, and this
  one was reconciled before its first pod reached the syncer. The 30 s
  resync now also queues the ConfigMaps and Secrets of every live virtual
  pod (573372c).
- [x] Classic run 8 (573372c) failed once, around 60 min: a projected
  ConfigMap stayed unsynced while the resync queued it every 30 s. The
  ConfigMap reconcile judged it unused from the syncer's pod store, which
  lacked the pod (the pod itself had reached the host through the LIST
  resync). Config reconciles now read their namespace's pods fresh
  (8460ccb).
- [x] Classic run 9 (8460ccb) failed once, at 70 min: "retrieving logs over
  websockets" read an empty log 0.3 s after the pod turned Running. It did
  not reproduce in five immediate reads, and the fake kubelet relayed the
  request normally; it looks like a narrow race. Run 10 is in progress on
  the same build.
- [x] Classic run 10 (8460ccb) failed once, at 40 min: a webhook pod was
  ready on the host but stayed unready in the virtual cluster. Its host
  status event never reached the syncer. The resync now also requeues
  virtual pods whose phase or Ready condition differs from the host pod's
  (5f023a6).
- [x] Classic run 11 (5f023a6) failed once, at 95 min: a webhook pod
  scheduled in the virtual cluster never reached the host. Diagnostics
  (5f4888f) now log each resync's counts, the pods it requeues, and any
  pod step that leaves a scheduled pod without a host pod.
- [x] Classic run 12 (5f4888f) failed once, at 85 min: the EmptyDir wrapper
  race test (pods with 50 ConfigMaps each) timed out on its third round.
  The diagnostics showed every missing pod caught by the next resync, but
  the resync was queueing every referenced ConfigMap every 30 s, and each
  config reconcile listed its namespace's pods, which flooded the single
  worker. The resync now queues only references the host lacks, a config
  reconcile lists pods only when its store shows no reference, and resync
  ticks older than 20 s are dropped (8e73fe4, b3f6515). The test passes
  alone on the new build.
- [x] Classic run 13 (b3f6515) failed once: websocket logs read empty again.
  A tight repro under load found the real cause of most failures since
  run 5: virtual pods reached Running 30 s to 4 min after their host
  containers started. The syncer's single worker was starved. Every pod
  event queued its real node, and each node reconcile listed and parsed
  every host pod on the node (0.5-1.4 s; 70 of them during a 30-pod
  burst). Real-node reconciles now list only the host pods this vcluster
  does not manage (the only ones its allocatable counts), and pod events
  no longer queue real nodes. A 30-pod burst now reaches Running in 53 s
  (was 130 s), with 5 slow node reconciles (was 70). e7f2e7b.
- [x] Classic run 14 (e7f2e7b) failed once, at 70 min: the 500 podspec
  updates test saw observedGeneration stop at 499. The host pod observed
  its last update after the final sync, and the resync's lag check looked
  only at phase and Ready. It now also requeues a pod whose virtual
  observedGeneration differs from what the host pod's lag maps to
  (e396121).
  The common cause of the pod and ConfigMap misses in runs 5-10 is a watch
  event that never reaches the syncer's stores; the root cause is still
  open. The safety nets: bend-kube 0.8.1, 60 s watches, a 30 s resync
  from fresh LISTs (missing host pods, lagging pod status, referenced
  ConfigMaps and Secrets), and config reconciles from fresh pod lists.
- [x] Classic run 15 (e396121) failed once: the Job pod failure policy
  test saw its job fail, because the syncer's status writes dropped the
  DisruptionTarget condition the API server adds to a pod being evicted.
  While a virtual pod is being deleted, conditions only it carries stay
  (614dcdd).
- [x] Websocket logs (runs 9, 13 and a focused run on 614dcdd): the virtual
  API server read the fake kubelet's relayed log stream on the plain path
  but got an empty frame over websockets (reproduced with curl). The fake
  kubelet now fetches a plain (non-follow) log read from the host and
  answers with a framed body; follow logs, exec, attach and port-forward
  still splice (a4c9798). A focused run of the 28 tests that failed in
  runs 1-15 (43 with dependents, 39 min) then passed except this one,
  which the curl repro confirmed fixed.
- [x] Classic run 16 (a4c9798) failed twice, both image pulls slower than
  the tests' 5 min: the image cache VM had restarted after a host crash
  and its 183 MB initramfs did not unpack in 512 MiB, so no registry ran
  while `cache status` said running. The cache VM now has 1 GiB, and the
  cache counts as running only when a registry answers; a VM without one
  is restarted (032b6b9). Every other test passed.
- [x] Classic run 17 (032b6b9): 450 passed, 0 failed (2b).
- [x] Re-certified 2026-11-16 on main 7ed2087 (assets built from it: bend-vmm
  0xe13a97cc, auto balloon, 16 KiB reporting, guarded reclaim, 1 s PID 1
  tick, the classic syncer fix #40), both runs in parallel on one Mac:
  standalone `st` (`--nodes 2 --backing-store etcd`): Status passed, 450
  passed, 0 failed (archive out/conformance/202611160528_sonobuoy_*); classic
  `vc` on a fresh 3-VM `hc` with docs/examples/conformance-classic.yaml:
  Status passed, 450 passed, 0 failed.
- [x] Virtual pods that SyncToHost deletes (deletionTimestamp or startTime,
  no host pod) no longer wait on a token, so terminating namespaces
  finish (7c0d4f5).
- [x] Regression check of the section 7 guest image (main 58b5bf6: 3 MB
  boot image, balloon with 64 KiB free page reporting, idle reclaim,
  fstrim, bend-vmm 0x3c5aa333, join server, open snapshot), 2026-11-15,
  `scripts/regression.sh` (the 28-name focus list, 43 tests): standalone
  etcd 2 workers 43 passed, 0 failed, in 11 min; classic 43 passed,
  0 failed, in 80 min. Of classic's 80 min, test bodies took 30; the
  EmptyDir wrapper race test's namespace took about 50 min to delete
  (host pods deleted 30 min after the virtual delete; the syncer loop
  stayed over 20 s behind, so resync ticks were dropped for 45 min).
  It passed, but the syncer was falling behind; factory task
  fix-classic-syncer-lag reproduced it in the envtest (#40).
- [x] Classic syncer throughput (#40, merged in 7fc5524): every virtual pod
  event queued all of its ConfigMaps and each ConfigMap reconcile scanned
  every stored pod. ConfigMaps and Secrets are now queued only when a pod's
  references change (vcluster's mappings store dispatches only from
  AddReference/DeleteReference), "used" is a reference-count lookup, and
  the loop folds its whole inbox before it runs keys. Envtest
  (tests/syncer_load_envtest.sh, 50 ConfigMaps x 25 pods): whole load
  537 s -> 62 s, resyncs dropped 8 -> 0. On the Mac, scripts/regression.sh
  on 7fc5524 (with bend-vmm 0x5fb57f1b, auto balloon, 16 KiB reporting,
  idle compaction): standalone 43/0 in 12 min, classic 43/0 in 18 min
  (was 80).
- [x] The EmptyDir wrapper volumes race test (50 ConfigMaps, pods that
  mount all of them) held the classic syncer's loop more than 20 s behind
  for about 45 min on the Mac, so no resync ran and terminating pods
  waited half an hour. CI syncer-load-envtest reproduces it (25 pods x 50
  ConfigMaps, the script plays the kubelet). The syncer's new meter
  ("syncer load" each minute and at each resync; "resync dropped") showed
  ConfigMap reconciles taking 57-59 s of every minute: each virtual pod
  event queued all 50 of its ConfigMaps, and each such reconcile parsed
  every stored pod. As vcluster's mappings store does (AddReference,
  DeleteReference), the syncer now queues a ConfigMap or Secret only when
  a pod's references change, and counts references per key, so "used" is
  one lookup. The loop folds the whole inbox before it runs keys, and it
  runs at most 64 keys or 5 s between looks at the inbox. Envtest, before
  -> after: host pods 223 s -> 9 s, virtual pods Running 252 s -> 15 s,
  host delete -> virtual pods gone 235 s -> 5 s, virtual delete -> host
  delete 4 s -> 5 s, longest gap between resyncs 538 s -> 30 s (#40).

- [x] vcluster's conformance profile in classic mode
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
- [x] Serving /node/join from the control plane. The pure answer is in:
  `Join.respond` chains the request, lookup, authorization, CA hash and
  script into a status, content type and body, and `Join.render` writes
  the HTTP/1.1 response (decisions J1 item 7, proposed laws in
  laws/join.bend). The guest join server (`vk8s join-server`,
  host/join_server.bend, J1 item 8) serves it on 8443 in a standalone
  control-plane VM. It reads token Secrets as the user `vk8s:join-server`
  through a Role that may only get Secrets in kube-system (proposed laws
  in laws/plan.bend). `vk8s token create` prints the curl form with
  `10.10.0.2:8443` for nodes on the VM LAN; the host reaches the join
  server at `127.0.0.1:<19000 + port % 3000>` (laws/cli.bend). Tested on
  Linux by tests/join_envtest.sh: envtest kube-apiserver, `curl | sh`
  with a fake kubeadm (its arguments carry openssl's CA hash), and 401,
  403, 404 and 405 answers. vk8s's own workers join directly
  (`Plan.worker`).
  Tested on the Mac (2026-11-15, #33's head, `vk8s create jt --nodes 1`):
  `token create` printed `curl -fsSLk "https://10.10.0.2:8443/node/join?token=…" | sh -`;
  through the forward 127.0.0.1:21369 the served script ran with a fake
  kubeadm as `kubeadm join 10.10.0.2:6443 --token … --discovery-token-ca-cert-hash sha256:55ec89aa…`,
  the hash equal to openssl's SHA-256 of the CA public key. type=master
  gave 400, an unknown or missing token 401, a worker token used as
  control-plane 403, POST 405, /healthz 404. `kubectl auth can-i
  --as=vk8s:join-server`: get secrets in kube-system yes; list secrets,
  secrets in default, pods, nodes no.
- [x] vcluster.yaml subset: the pure parser, defaults and validation are
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
- [x] Open snapshot format (#21, pkg/snapshot): the tar record codec, URL
  parsing, archive kinds and restore plans, with laws from vcluster's
  tests. Every law proves, the general tar round trip included
  (laws/done/snapshot). Not wired to the CLI, which uses vk8s's
  VM-level format. The store tools for it are proven on Linux by
  tests/snapshot_store_spike.sh (CI job snapshot-store-spike): etcdutl
  restore with --bump-revision 1000 --mark-compacted into a new member
  name, and etcdctl txn creates and paged gets through kine on SQLite.
  The phase-one decisions are in docs/ref/snapshot-decisions.md.
  The pure parts of phase one are in place: `snapshot create ...
  --format open` parses to `SnapshotOpen` (remote schemes refused by
  name), the request `snapshot-dump` (D16; it supersedes `snapshot-export`)
  dumps etcd or kine to the share,
  and `Plan.boot_restore` restores the store at boot (decisions D9-D13).
  The host side is written (host/snapshot_open.bend): `snapshot create
  NAME PATH --format open` refuses classic clusters, asks the guest for
  the dump, writes vcluster's archive (etcd: the database entry streamed
  behind `Snap.Tar.file_header`; kine: `Snap.write_kv` of the pages) with
  gzip -3 and mode 0600, and removes the share copies. `restore` tells the
  format from the first tar entry and, for the open format, creates the
  cluster with the archive's store and puts the db or puts file and the
  marker on its share before the first boot; PID 1 then boots with
  `Plan.boot_restore`. tests/snapshot_envtest.sh (CI job
  snapshot-envtest) runs the round trip on Linux for etcd and kine: the
  guest's export steps, the host archive code, tar -tzPf, the host
  restore files, the guest's restore steps into a fresh store, and every
  key compared.
  Tested on the Mac (2026-11-15, #39 merged with main 29a7653): for each
  store, `vk8s create sa-X --backing-store X`, a ConfigMap `keep` and a
  namespace `team-a`, `vk8s snapshot create sa-X F --format open`,
  `vk8s restore sb-X F`. kine (sqlite): a 59 KB key/value archive in
  1 s, mode 600, first entry /vcluster/snapshot/revision; etcd: an 83 KB
  archive whose first entry is /vcluster/snapshot/db. Each restore made
  a cluster with the archive's store (STORE=sqlite, STORE=etcd) that
  served the ConfigMap (who=sqlite, who=etcd) and the namespace.
- [x] whole-cluster snapshot/restore, VM level (see 5).
- [x] Certificates. `vk8s certs rotate NAME` and `vk8s certs check NAME`
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

- [x] Released 2026-11-12:
  https://github.com/chenhunghan/bend-vk8s/releases/tag/v1.36.6-69181a9a
  (main 2b6eba3; the binary built at 034b3cf, which pins the assets).
  `vk8s-darwin-arm64` is ad-hoc signed with com.apple.security.hypervisor
  (SHA-256 6e62c7ee…0b92). Tested from the release itself: the binary
  fetched with curl as the README says, with no local assets, downloaded
  and verified the four archives from GitHub and booted a Ready cluster in
  93 s (download included). The released guest assets were built from
  the same guest sources (a4c9798) as classic19, the build that passed
  classic run 17; later commits changed only the host binary and docs.
- [x] Released 2026-11-16 (user-approved after the re-certification):
  https://github.com/chenhunghan/bend-vk8s/releases/tag/v1.36.6-42a05fb8
  (main 85a93bb; guest assets built from 7ed2087, the re-certified build).
  `vk8s-darwin-arm64` ad-hoc signed with com.apple.security.hypervisor
  (SHA-256 cc3ec59d…7e11). Tested from the release: downloaded with curl,
  checked against SHA256SUMS, and with no local assets for the version it
  fetched and verified the archives (~360 MB) and created a cluster in
  57 s; the node went Ready and a pod ran; delete left nothing.
- [x] Binary that downloads hash-pinned assets.
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

## 7. Minimal host footprint

- [x] Memory give-back. Baseline 2026-11-15: an idle worker VMM held
  1.8-2.0 GB RSS for 115 MB of guest AnonPages (877 MB free). Done in
  code, not measured yet (docs/ref/footprint-decisions.md M1, M2):
  - bend-vmm pin moved from 0x09bd79c7… to 0x5d8f2af4… (bend-vmm
    e4b1bdf, virtio-balloon with free page reporting; API otherwise
    unchanged; on macOS it unmaps reported ranges and maps fresh pages,
    since MADV_FREE_REUSABLE did not lower RSS, and its test went from
    1141 to 179 MiB RSS in 3 s). Every VM
    (control plane, workers, image cache) starts with
    `--balloon free-page-reporting` (Cli.balloon_flags).
  - The guest loads virtio_balloon (scripts/guest/modules.txt). Alpine
    linux-virt 6.18.63 has CONFIG_VIRTIO_BALLOON=m, which selects
    CONFIG_PAGE_REPORTING=y. Without the device the module only
    registers its driver.
  - PID 1 reclaims page cache when the node is idle (Plan.idle_reclaim,
    every 30 s): when less than 10% of vCPU time was busy over the
    window, it writes the file cache above 64 MiB to the root cgroup's
    memory.reclaim (swappiness=0). Under load it does nothing.
  - Waits on the Mac measurement after merge: the target (a worker VMM
    within 256 MiB of MemTotal - MemAvailable after a 30-pod burst and
    2 min idle), the section 2 conformance runs, and a check on the Mac
    that `vk8s create` boots with the new pin.
  - Inflate/deflate from the control socket and DEFLATE_ON_OOM come next
    from bend-vmm.
  - Measured 2026-11-15 on the Mac (main 6718002 plus order 4; 2 GiB
    worker, 30-pod burst, 2 min idle, BEND_VMM_TRACE=16): the guest
    reports (505 releases at order 9, none refused). Guest used
    (MemTotal - MemAvailable) 275 MB. phys_footprint (vmmap) 2.4 GB at
    the burst, 1.2 GB idle at order 9, 1.1 GB after drop_caches and
    compact_memory, 778 MB with page_reporting_order 4 (1363 releases).
    The `footprint` tool says 293 MB and vmmap's dirty total is 312 MB
    (306 MB of it guest RAM), so about 466 MB of phys_footprint is in no
    region; sent to bend-vmm (macOS accounting after hv_vm_unmap, or
    compressed pages). Target (within 256 MiB of guest use) not met yet.
  - bend-vmm's automatic balloon (0xe9825c44, ea30ce3), measured
    2026-11-15 with `--balloon auto`, which every VM now gets (the four
    cli balloon laws amended with the user's approval): 4.5 min after a
    30-pod burst a 2 GiB worker's balloon held 985 MiB, real guest use
    (MemTotal - MemAvailable - balloon) was 272 MB, phys_footprint 820 MB;
    the control plane 624 MB used, 1.7 GB phys_footprint. vmmap's regions
    hold only ~70 MB dirty, so about 500 MB per VM is charged outside
    every region even for ballooned pages: a macOS accounting issue in
    bend-vmm's backing memory, sent to bend-vmm with these numbers.
    bend-vmm traced it to its 64 KiB release granule: a block goes back only
    when all 16 guest pages are free, which fragmented memory rarely
    allows; it plans to release at 16 KiB (its laws change, asked of its
    user). Meanwhile PID 1 compacts memory every 10 min when idle
    (footprint-decisions M4): 777 MB -> 741 MB phys_footprint for 265 MB
    used.
  - bend-vmm 0x5fb57f1b (3aa445a) releases 16 KiB blocks; guests report at
    order 2 (16 KiB; law amended with the user's approval). Measured on
    7fc5524 on the regression cluster after its suite (more fragmented):
    12.5 min after a 30-pod burst the workers held 784-890 MB for ~275 MB
    used, the control plane 1.8 GB for 668 MB. With 4 KiB guest pages a
    free page next to used ones never fills a 16 KiB host page, so the gap
    stays; the user approved a guest kernel with 16 KiB pages (#41,
    VK8S_KERNEL=16k, in CI).
  - 16K-page kernel on the Mac (2026-11-15, #41's CI artifact, built
    from kernel.org 6.18.63 with Alpine's virt config): a 1-worker
    cluster boots under bend-vmm (both nodes Ready, PAGESIZE 16384).
    Reporting order 0 (one 16 KiB page), 12.5 min after a 30-pod burst:
    worker real use ~600 MB (AnonPages 206 MB, file cache 204 MB that
    idle reclaim does not drop), phys_footprint 867 MB: gap ~263 MB, about
    the target. The control plane: 1.8 GB for about 1.1 GB used. But the
    guest itself uses about twice the memory with 16 KiB pages (anon 206
    vs ~115 MB on 4 KiB), so the host total is no lower than with the
    4 KiB kernel (741-890 MB). Decided with the user: the 4 KiB Alpine
    kernel stays the default, the 16K kernel is opt-in (#41), and the GOAL
    target is now absolute: a worker VMM at most 512 MiB phys_footprint
    after a 30-pod burst and 2 min idle. Today 741-890 MB: not met.
  - A 1 GiB worker (temporary build) is no smaller: 747 MB phys_footprint
    12.5 min after the burst, with ~355 MB in use, 338 MB free in mostly
    order-9/10 blocks and a 317 MiB balloon. About 400 MB that the guest
    has free or ballooned stays charged whatever the RAM size; sent to
    bend-vmm (auto mode releasing reported pages, fixed charges).
- [x] Resident boot image (baseline 207 MB Shmem per VM). Measured on the
  Mac (#36's head, 2026-11-15): Shmem 33 MB in a worker; standalone,
  classic and the image cache boot from the 3.1 MB cpio. The initramfs
  vk8s.cpio held 183.8 MB uncompressed (release v1.36.6-69181a9a): vk8s-init
  77.8 MB (static PID 1), vk8s-guest 76.0 MB, glibc/libssl/iptables libs
  21.0 MB, kernel modules 7.0 MB, busybox 1.1 MB, iptables/conntrack tools
  0.6 MB, CA roots 0.2 MB. Stage 0 copied all of it into a tmpfs. Now
  (scripts/guest/pack.sh) the cpio holds stage 0, busybox and the six
  modules that mount the assets disk: 3.1 MB on the same files, of which
  stage 0 copies 1.1 MB into the tmpfs. Stage 0 mounts the assets disk at
  /assets and runs PID 1 from its guest/ directory, with every other file
  there (symlinks from the initramfs). Shmem not measured yet (Mac, after
  a release with the new guest assets).
- [x] Idle CPU. Baseline: control plane 5-10%, worker 1-2%, cache 0.1%.
  bend-vmm measured an idle 2-vCPU guest at 0.07% host CPU (6 exits in
  30 s): the 1-2% per worker is kubelet and containerd inside the guest.
  On macOS the in-kernel GIC lets Hypervisor.framework handle guest WFI
  itself, so bend-vmm's 1 ms WFI loop (host/main.bend:1283) does not run
  there; bend-vmm is measuring where an idle VM's 1-2% goes (likely
  virtual-timer exits), 2026-11-15.
  Measured 2026-11-15 (main 58b5bf6, 180 s idle): image cache 0.37% (meets
  <1%), workers 2.1-2.8%, control planes 6.3-9.2%. Inside an idle worker
  the guest is busy 1.1% of one CPU (kubelet 0.61 s per 60 s, containerd
  0.18, PID 1 0.11, flanneld 0.07). SIGSTOP on kubelet alone took the
  worker from 2.58% to 1.23% host CPU, yet kubelet's pprof shows only
  0.68% CPU spread over its fixed timers (volume reconciler every 100 ms,
  PLEG relist every 1 s, pod cleanups every 2 s, node status every 10 s);
  Evented PLEG and --housekeeping-interval=60s changed nothing (2.68%,
  2.63%). So the host pays about twice the guest's work in per-wakeup
  cost; sent to bend-vmm (cost of a 10 Hz timer guest, exit and vCPU
  wake/park path).
  bend-vmm measured a guest that only wakes on a 10 Hz timer at 0.08-0.10%
  host CPU: wakeups are cheap, real guest work costs 1.5-2x on the host.
  A 1-vCPU worker idles at 1.47-1.69% (2 vCPUs: 2.14-2.78%, same run);
  not the default, since it halves a worker's schedulable CPU (a defaults
  decision for this section). Open: the remaining cost is kubelet's own
  fixed timers.
  Decided with the user: trim what vk8s controls, then set the target to
  what a stock kubelet allows. PID 1 now ticks every 1 s instead of
  250 ms (tick-count laws amended, periods unchanged): side by side, 3
  rounds of 120 s, a worker went 2.83-3.20% -> 2.74-2.97%.
  Regression found the same day: bend-vmm's automatic balloon costs an
  idle control plane about 20 points of host CPU (24-36% with auto,
  10.5-11% after `balloon 0`): its target chases the control plane's
  moving free memory and inflation into fragmented memory is slow. Sent
  to bend-vmm (fast inflation and target hysteresis in its next build).
  bend-vmm 0x2415470a (8727030: one-pass inflate, a 96 MiB hysteresis band
  on the auto target, kept/resident/compressed in status json): control
  plane 15.1-16.1% (was 24-36%; 10.5% with the balloon pinned at 0),
  worker 3.75-3.8%. Worker memory on it: phys_footprint 731-762 MB for
  ~347 MB held by the guest; bend-vmm's mincore resident 471 MiB and
  kept 1 MiB, so about 290 MB of the footprint is outside resident guest
  RAM (the RAM mapping is split into ~67k regions). Sent to bend-vmm.
  The control plane's extra CPU was ours: PID 1's idle reclaim pushed all
  file cache down to 64 MiB every 30 s, and the nodes re-read it
  (workingset_refault_file: control plane ~215k pages/min, worker ~72k;
  kswapd 0). Suppressing it took the control plane 14.4% -> 11.7% and a
  worker 3.7% -> 2.9%. The reclaim now takes only inactive file pages and
  backs off 10 min after a run that saw over 10 MiB of refaults
  (plan.idle_reclaim amended under the approved trim): refaults ~0,
  control plane 11.8-12.3%, worker 3.5% (host load varies run to run).
  Cost: the hot cache stays, so an idle worker holds 1.0 GB phys_footprint
  (was 731-762 MB while thrashing) and the control plane 2.1 GB.
  Where the rest of a worker's footprint sits (2026-11-16, bend-vmm
  0x2415470a): `sudo footprint --unmapped` on an idle worker after a
  burst counts 406 MB in the task's VM objects (401 MB of it guest RAM, in
  ~64.7k regions) and nothing unmapped, while phys_footprint is 1085 MB
  (status json: resident 593 MiB, compressed 89, balloon kept 26). About
  680 MB is charged to the task outside any VM object, most likely
  Hypervisor.framework's own accounting for guest RAM it has mapped.
  bend-vmm's standalone runs show ~50 MB; ruled out so far: its devices,
  --lan, the vk8s embedding, guest init_on_alloc and THP. With bend-vmm
  (hv map/unmap churn from hours of 16 KiB releases is the lead).
  Found by bend-vmm: a guest page the VMM's own threads write (disk and
  9p reads, LAN receive, kernel and initrd load) was charged twice to
  phys_footprint while the guest maps it. bend-vmm 0xe13a97cc (35d8a07)
  remaps written runs onto themselves every 2 s. Measured 2026-11-16
  (30-pod burst, 10 min idle): the worker gap (phys_footprint - resident
  - compressed) went from 350-690 MB to ~80 MB, the control plane's from
  550-950 MB to ~0; worker 749 MB, control plane 1.2 GB.
  The rest was guest page cache never re-read (311 MB Active(file) on an
  idle worker that had refaulted 571 pages: preloaded image tars read at
  boot). The idle reclaim now counts Active + Inactive file pages again,
  guarded: after a run that saw over 10 MiB of refaults it backs off 1 h.
  Measured on i2 (same burst, 17 min idle): worker 563-575 MB (resident
  548-556 MiB, gap ~20), control plane 1.2 GB, refaults over 6 min 0 on
  both. Target (<= 512 MiB) not met by 50-60 MB.
  A 1 GiB worker on the same build: 527 MB (10 min idle). The guest holds
  ~516 MB (MemTotal excludes 83 MB the kernel reserves at boot: image,
  struct pages), so the levers left are guest-side. Decided with the
  user: target <= 640 MiB, workers stay 2 GiB. Met: 2 GiB worker 563-613
  MB across readings (613 with 323 MiB compressed by macOS).
  No regression: scripts/regression.sh on main 7ed2087 (bend-vmm
  0xe13a97cc, guarded reclaim, 1 s tick, auto balloon, 16 KiB reporting,
  idle compaction), 2026-11-16: standalone 43 passed, 0 failed, 11 min;
  classic 43 passed, 0 failed, 15 min.
  Target revised with the user (GOAL section 7): idle worker <= 2.5%,
  image cache < 1%. Measured 2026-11-16 on main 791a350 (bend-vmm
  0x2415470a), quiet host (load ~3), g1 idle 30 min after a 30-pod
  burst, 3 x 120 s: worker 1.79%, 1.53%, 2.36%; image cache 0.36%,
  0.30%, 0.50%; control plane 7.4%, 5.9%, 9.3% (no target). Met.
- [x] Disk give-back. Measured 2026-11-15 on the Mac (main 58da2d6): a
  worker's data.img (du) went 938 MB at start, 2389 MB after pulling
  python:3.12, 2505 MB after the pod was deleted, then 610 MB once kubelet
  removed the image (imageMaximumGCAge 1h) and PID 1's fstrim reported
  "2416758784 bytes trimmed". `vk8s delete` left no cluster dir and no
  process; `vk8s assets prune` removed a superseded v1.36.5-00000000 and
  kept the pinned release and the local build.
  bend-vmm offers VIRTIO_BLK_F_DISCARD and punches
  holes in the raw image (host/hvf.c hvf_disk_discard_run). Done in
  code, not measured yet:
  - PID 1 runs busybox `fstrim -v /var/lib/vcluster` every 10 min (2400
    ticks of 250 ms) in the background on every VM: control plane,
    workers and the image cache (Plan.fstrim, Plan.fstrim_due; laws
    plan.fstrim*, plan.disks.no_online_discard). Periodic fstrim, not
    `mount -o discard`: online discard sends a discard with every delete
    (containerd's many small files, etcd and kine compaction), and each
    waits on the host's hole punch; fstrim batches them. Each run's
    output is in share/logs/fstrim.log.
  - kubelet removes images no container used for 1 h
    (`imageMaximumGCAge: 1h`, Plan.image_gc, law plan.image_gc), on the
    control plane's kubelet and, through kubeadm's kubelet-config, on
    workers. With kubelet's defaults (GC above 85 % disk use) a 16 GiB
    sparse data disk kept every image it ever pulled. kubelet's GC runs
    every 5 min, so a removed image's blocks go back within about 15 min.
  - `vk8s delete` checks that the cluster dir is gone and fails if not.
    The dir holds every node's disk, share, logs and sockets; nothing
    else on the host is per cluster except the kube context, which
    delete removes (and the host objects of a classic cluster).
  - `vk8s assets prune [--dry-run]` removes superseded release versions
    from ~/.vk8s/assets (Cli.assets_prune, laws cli.assets*).
  - Mac test plan (target: data.img shrinks by at least 400 MB): create
    a cluster with `--nodes 1`; `du -k` the worker's data.img; run a pod
    with a ~500 MB image on the worker and `du -k` again; delete the pod;
    wait 1 h 5 min (image GC) and 10 min (fstrim; see
    share/logs/fstrim.log); `du -k` once more.
- [x] Defaults re-sized once memory give-back works. Decided with the user
  2026-11-16: the sizes stay (control plane and workers 2 vCPU / 2048
  MiB, image cache 1 vCPU / 1024 MiB). They are ceilings: an idle worker
  holds 563-613 MB of its 2 GiB (a 1 GiB worker 527 MB, so a smaller
  default saves ~40 MB and halves pod capacity), an idle control plane
  ~1.1-1.2 GB, and 2 vCPUs idle at 1.5-2.4% host CPU (1 vCPU 1.5-1.7%).

## 8. Linux hosts and native mode

- [ ] Linux arm64 on KVM: build, smoke test, release asset. bend-vmm runs
  on KVM today (needs an in-kernel GICv3; images on ext4/xfs; memory via
  VmRSS or cgroup; snapshots restore only on the hypervisor that took
  them). GitHub's arm64 runners have no /dev/kvm.
- [ ] x86_64 on KVM: amd64 guest assets, bend-vmm x86_64, smoke test and
  the regression subset. bend-vmm's x86_64 machine model is approved
  (2026-11-16) and starts once its host-linux CI is green: bzImage boot,
  virtio-mmio devices on the kernel command line, KVM's in-kernel
  irqchip/PIT, 16550 console, CMOS RTC, MP table, a minimal ACPI power
  button (our initramfs loads `button`), snapshots last. Alpine's x86_64
  virt kernel has VIRTIO_MMIO and VIRTIO_MMIO_CMDLINE_DEVICES built in.
  Done in bend-vmm 2026-11-16 (c4dbeed, package 0xa2063aca): x86_64 Linux
  guests on KVM, bzImage, COM1/ttyS0 console, virtio-mmio described in the
  ACPI DSDT, CMOS RTC, ACPI power-off; its check-host suite passes on
  GitHub x86_64 runners (real KVM): NAT, --forward, --lan, 9p with quota,
  balloon (reporting, auto), disks (ro, nocache, qcow2, discard), pause/
  resume, 8 vCPUs. Not yet on x86: snapshots/--restore (asked). Our side:
  amd64 guest assets (Alpine linux-virt x86_64, modules af_packet, evdev,
  virtio-rng, virtio_net/blk/balloon/input, 9p stack, vsock), the pin, and
  the smoke test, after #42 and #44.
- [ ] Native mode on Linux: the control plane as a systemd unit, nodes
  joining by bootstrap token, regression subset then a certified run.
- [ ] Container mode: `--backend container` on Linux (namespaces + cgroup
  v2, no Docker) and on macOS (node containers in one shared bend-vmm VM);
  smoke test and the regression subset in CI and on the Mac.
- [ ] gVisor RuntimeClass: runsc and its containerd shim in the nodes, an
  opt-in `gvisor` RuntimeClass; a pod runs under it in each backend.
- [ ] Linux dev VM on the Mac: a bend-vmm VM with a Debian arm64 root
  filesystem and systemd, to run vk8s-linux-arm64 (container and native
  modes, gVisor) locally.

## 9. Asset disk footprint

Baseline (v1.36.6 assets, 2026-11-16): assets.img 1.0-1.2 GB raw ext4,
~922 MB of binaries and images, ~355 MB compressed download. Largest:
kube-apiserver 78 MB, konnectivity-server 68, kube-controller-manager 66,
kubeadm 65, helm 55, kubelet 54, kubectl 53, registry 50, kube-scheduler 44,
containerd 43, kube-proxy 40, kine 38, crictl 36, CNI 28, preloaded images
83.

Measured 2026-11-16 from the pinned inputs (loft-sh v1.36.6 arm64
bundle, registry 3.1.2; KiB; gzip -6 is what release-assets.sh does):

| bin/ of the assets disk | Uncompressed | gzip |
|---|---|---|
| before (with helm, crictl, vcluster-tunnel, bandwidth, firewall, pause-image.txt; kube-proxy binary about 40000 more) | 819008 | 264898 |
| after A2 | 690344 | 216704 |
| dropped | 128664 (+ about 40000 kube-proxy) | 48194 (+ kube-proxy) |

Squashfs (zstd -19, 256 KiB blocks), measured by CI's assets-disk job
(scripts/guest/sizes.sh and tests/kernel16k_boot.sh, run 43834400562,
cb6f2a9; KiB):

| Set (after A2) | Uncompressed | squashfs | squashfs gzip'd |
|---|---|---|---|
| node | 226944 | 62268 | 62252 |
| control-plane | 342896 | 86808 | 86789 |
| classic (konnectivity-server) | 69448 | 24964 | 24953 |
| image cache (registry) | 51080 | 11820 | 11814 |
| standalone (node + control-plane) | 569836 | 149072 | 149041 |
| all of bin/ | 690356 | 185852 | 185808 |

| assets disk, bin/ part | On disk | Download |
|---|---|---|
| before: ext4, all tools | at least 819008 | 264898 (gzip) |
| after: squashfs, A2 | 185852 | about 185852 (gzip adds nothing) |

On disk, bin/ shrinks by about 77%, and its download by about 30%.
The test disk with bin/ and the guest root (23392 uncompressed) is
193080. The preloaded images (about 83 MB) are not in the CI disk; the
whole assets.img comes from the Mac build (pack.sh prints it).

- [x] Compressed read-only assets disk: squashfs, zstd
  (footprint-decisions A1; erofs lacked zstd in Homebrew's and Ubuntu
  24.04's erofs-utils). CI's assets-disk (4 KiB pages) and kernel16k
  jobs boot it under qemu. Mac (2026-11-16, main with #42 merged): the
  disk is 360 MB (was 1.03 GB raw ext4), a 2-node cluster boots from it,
  and scripts/regression.sh passes: standalone 43/0 in 10 min, classic
  43/0 in 16 min. The next release's manifest pins it.
- [ ] Per-role contents (node set, control-plane set): designed
  (footprint-decisions D1); blocked on manifest.four_archives and
  plan.disks, which are the architect's.
- [x] Runtime-unneeded tools dropped: helm, crictl, the kube-proxy
  binary, vcluster-tunnel, the bandwidth and firewall CNI plugins
  (footprint-decisions A2). ctr stays (image import), etcdutl stays
  (etcd restore). The regression subset passes on it (above).
- [ ] Preloaded images pulled through the image cache where it runs:
  not yet; saves nothing while the images are part of the one assets
  archive (footprint-decisions A3, D1).
- [ ] Download and on-disk assets about 200-300 MB per arch; regression
  subset passes.

## Follow-ups after the release

- Move the syncer's object updates from full PUTs (with a 409 retry) to
  merge, strategic or server-side-apply patches. The pinned
  bend-kube-runtime client has them (Client.patch, Client.apply).
- Real-node reconciles still take about 0.5 s (node objects are large).
  More workers than one, or informer-style caches instead of GETs per
  reconcile, would raise the syncer's throughput further.
- Move the pin from bend-kube-runtime 0.5.5.0 to 0.7/0.8, whose
  Client.replace_retry is the 409 retry vk8s hand-writes, and consider
  Kube.control (per-watch cluster config, RAnnotated/RMap relations) for
  the syncer loop. It reconciles from
  caches one key at a time, unlike vk8s's ordered writes from fresh GETs.
- Superseded: the bend-vmm pin moved from 0x09bd79c7… to 0x5d8f2af4…
  (bend-vmm e4b1bdf, the virtio-balloon for memory give-back; section
  7). It also includes 170eaca (0x52665ac8…), the qcow2 change.

## Known divergences

- Disk give-back (section 7) is vk8s design: PID 1 trims the data disk
  every 10 min, and kubelet gets `imageMaximumGCAge: 1h`. vcluster leaves
  trimming to its host and keeps kubelet's image GC defaults.
- `vk8s assets prune [--dry-run]` has no vcluster equivalent (vind's
  assets are Docker images, which `docker image prune` removes). It
  removes the dirs of ~/.vk8s/assets named as releases (vK8S-HASH, for
  example v1.36.6-69181a9a) except the version this binary pins, the dir
  VK8S_ASSETS names, and any dir that a running process's arguments name,
  as written or resolved (bend-vmm's --kernel and --disk). Local builds
  (v1.36.6 from scripts/guest/build.sh, dev) and download staging dirs
  stay. A stopped cluster needs no assets dir: its data disk is a copy,
  and it boots again on the pinned version.

- /node/join (vcluster-pro, closed source): the answers are vk8s design
  (docs/ref/standalone-decisions.md J1). Errors are plain-text bodies
  with the status Join.parse_request or Join.authorize chooses, HEAD is
  405, only bootstrap tokens are accepted, and the script refuses
  control-plane joins.
- /node/join port: vcluster serves the API and /node/join on one proxy
  port, 8443. vk8s keeps the API server on 6443 and serves only
  /node/join on 8443 (J1 item 8). `vk8s token create` prints
  `10.10.0.2:8443` for the curl form and `10.10.0.2:6443` for
  `--kubeadm`.

- vcluster.yaml: settings vk8s cannot honor yet are refused by name
  instead of ignored: another Kubernetes version, service or pod CIDR,
  cluster domain, and CoreDNS replica count (section 4).
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
- Open-format snapshot, phase one (planned; docs/ref/snapshot-decisions.md
  D3-D5): only file:// URLs and bare paths (vcluster also writes s3, oci,
  container and https); standalone clusters only, classic refused; restore
  only into a new name (vcluster standalone restores in place: it stops the
  service and replaces the data dir).
  The guest dumps kine with etcdctl pages written as raw JSON, and a
  restore boot applies the puts with etcdctl txn (vcluster uses the Go
  etcd client); a compaction that kine refuses after a restore does not
  stop the boot (D11-D13). The puts leave out kine's own
  /registry/health, which the new kine already holds (D14).
  An etcd archive restores into embedded etcd and a key/value archive
  into kine: the restore picks the store from the archive and converts
  neither (vcluster converts an etcd archive for other stores and puts a
  key/value archive into etcd). After an etcd restore, vk8s does not run
  vcluster's postRestoreSnapshotDataMutation yet (the new vCluster keeps
  the namespaces' kube-root-ca.crt, which kube-controller-manager
  rewrites, and the mappings), and it refuses archives with skip keys.
  `create NAME --restore PATH` and `restore NAME PATH` refuse
  `--backing-store`: the snapshot decides the store (D15).
- The embedded etcd member is named after the cluster with the loopback
  peer https://127.0.0.1:2380; vcluster standalone names it after the node
  IP with peer https://IP:2380. A restore passes the new cluster's name and
  peer to etcdutl.
