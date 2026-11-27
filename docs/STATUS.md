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
  references change (vcluster's mappings store dispatches only when a
  mapping's references are added or removed: addMapping/removeMapping),
  "used" is a reference-count lookup, and
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
  every stored pod. As vcluster's mappings store does (addMapping,
  removeMapping), the syncer now queues a ConfigMap or Secret only when
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
- [x] vcluster.yaml passthrough for agent-substrate (github.com/
  agent-substrate/substrate, hack/create-kind-cluster.sh): implemented,
  not yet run against a substrate install. `create -f` now works with
  every backend except container mode in the macOS node host (refused
  with a message: its shares are in the node-host VM).
  - Control plane: `controlPlane.distro.k8s.<component>.extraArgs` carry
    `--feature-gates=ClusterTrustBundle=true,ClusterTrustBundleProjection=true,PodCertificateRequest=true`
    and `--runtime-config=certificates.k8s.io/v1beta1=true` (laws
    values.feature_gates, values.substrate_*). Flags vk8s owns
    are refused by name (values.owned_*).
  - Kubelet: vcluster's `privateNodes.kubelet.config` goes into the
    KubeletConfiguration of kubelet-config.yaml and kubeadm.yaml, so
    worker VMs and containers get it from the kubelet-config ConfigMap
    (values.kubelet_lines, values.with_kubelet; strict decoding laws
    vcluster_config.kubelet_*). Keys vk8s writes are refused
    (values.owned_kubelet).
  - Sysctls: `vk8s.nodes.proxyArp: true` (vk8s extension) sets
    net.ipv4.conf.all.proxy_arp=1 and, with IPv6, proxy_ndp=1 on VM and
    container nodes at boot (values.proxy_arp*, values.with_node); native
    preflight asks for them (native.proxy_sysctls*,
    native.preflight_proxy).
  - Evidence still needed: CI gate (check.sh with VERDICT=1), the
    regression subset at 43/0, and a substrate install on a vk8s cluster.
  - Evidence (2026-11-18), a proof of concept (the job, its script and
    the example vcluster.yaml were removed afterwards: substrate is not
    part of vk8s; see commit 9bfc616 for them), run
    https://github.com/chenhunghan/bend-vk8s/actions/runs/44245074334:
    agent-substrate's quickstart on a 2-node vk8s VM cluster on KVM:
    `ate-setup deploy ate-system`, `deploy demo counter` (64 s), `kubectl
    ate create actor my-counter-1`, `kubectl ate proxy`, two POSTs: the
    counter went 1 -> 2 with memory, file and rootfs state preserved.
    PASS. Gate green with VERDICT=1; regression 43/0 on main.
  - Gap found and fixed: a VM node's / was a private mount, so runc
    refused atelet's /var/lib/ate (mountPropagation HostToContainer). PID 1
    now runs `mount --make-rshared /` after the cgroup2 mount on VM nodes
    (Plan.with_rshared, laws plan.rshared_step, plan.with_rshared.*), as
    kind and vk8s's container mode do. Mac: a HostToContainer hostPath
    pod runs on a VM node (mountinfo `master:1`).
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
- [x] Released 2026-11-25 (main 51be2c2; the manifests pin the assets
  since 12bc963), one release per asset arch:
  https://github.com/chenhunghan/bend-vk8s/releases/tag/v1.36.6-92057045
  (`vk8s-darwin-arm64` SHA-256 2a854d62…d954, `vk8s-linux-arm64`
  10aebecd…10a5, the arm64 sets, OpenSSL 3 for macOS with its license) and
  https://github.com/chenhunghan/bend-vk8s/releases/tag/v1.36.6-a65797c8
  (`vk8s-linux-amd64` a90f4958…300f, the amd64 sets). The Linux binaries
  are CI's (run 45558518893, job linux-build).
  - On the release candidate, on the Mac, one run at a time: the
    regression subset 43/0 standalone (13.7 min) and 43/0 classic
    (18.0 min); certified conformance 450 passed, 0 failed standalone
    (2 workers, etcd; 116 min) and 450 passed, 0 failed classic (131 min;
    archives 202611250632_sonobuoy_35b23fb9 and
    202611250829_sonobuoy_5cb0afca); scripts/soak.sh 10 60: ten
    create/delete cycles (create and a pod 21-24 s, delete 2-4 s), 174
    workload rounds with pause/resume, 0 apiserver restarts, no VMM,
    socket or directory left, SOAK OK.
  - CI on 51be2c2 (run 45570179073): every job green on the second
    attempt; the first failed container-smoke arm64, see the known issue
    below.
  - From the release itself, in an empty home: curl as the README says,
    SHA256SUMS checked, `vk8s create` fetched and verified the base
    files, the node and control-plane sets and OpenSSL, and returned in
    31 s; node Ready, nginx rolled out, delete 1 s. With no other vk8s
    server running, `vk8s cache serve` and `vk8s layers serve` had the
    release's libssl.3.dylib and libcrypto.3.dylib loaded (lsof), not
    Homebrew's, and the layer store filled (TLS to the registries).
  - Known issue, Linux container backend (to look at next): in that first
    CI attempt, tests/netpol_e2e.sh's "FORWARD jumps to
    KUBE-ROUTER-FORWARD before any ACCEPT" failed on the worker for its
    whole 60 s, before any policy existed. Two minutes later the order
    was right, and every deny and allow check passed. While the order is
    wrong, pod traffic on that node can pass policy until kube-router's
    next sync. The cause is not known: the test's dump runs too late to
    show the chain as it was. Not seen in VM mode.
    Looked for after the release (2026-11-25): the same smoke test 192
    more times on the same CI runner type (ubuntu-24.04-arm, 12 jobs of
    8 rounds, twice), every one green, so about 1 in 200 or rarer.
    kube-router v2.12.0's source (npc_iptables.go) puts its jump back at
    the top on every full sync, which runs at each pod, namespace or
    policy event and every 5 minutes; no order of kube-proxy, flannel
    and kube-router starting was found that leaves the jump behind an
    ACCEPT for 60 s. Still open. The test now prints the FORWARD chain
    and kube-router's process ids at the moment the check fails
    (c6c0fea), so the next occurrence shows the cause.
- [x] Released 2026-11-27 (main 290d07a, which pins the assets), one
  release per asset arch:
  https://github.com/chenhunghan/bend-vk8s/releases/tag/v1.36.6-229e3489
  (`vk8s-darwin-arm64` SHA-256 d3486fa4…de31, `vk8s-linux-arm64`
  255cf09f…319c, the arm64 sets, the same OpenSSL 3 archives for macOS
  as v1.36.6-92057045 with their license) and
  https://github.com/chenhunghan/bend-vk8s/releases/tag/v1.36.6-37a70144
  (`vk8s-linux-amd64` 3a12f06e…f06d, the amd64 sets). The Linux binaries
  are CI's (run 45920693816, job linux-build, every job that ran
  passed).
  - On the release candidate, on the Mac, one run at a time under the
    guard (2026-11-27 03:08 to 08:02): the regression subset 43/0
    standalone (13.3 min) and 43/0 classic (18.3 min); certified
    conformance 450 passed, 0 failed standalone (119 min) and 450
    passed, 0 failed classic (129 min; archives
    202611270128_sonobuoy_74fa88d1 and 202611270328_sonobuoy_e943017c);
    scripts/soak.sh 10 20: ten create/delete cycles (create and a pod
    20-23 s, delete 2-3 s), 58 workload rounds with pause/resume, web
    ready 4/4, 0 apiserver restarts, no VMM or socket left, the cache
    0 MiB larger, SOAK OK.
  - The 24-hour uptime run is the item below (built from a6ccf81; the
    commits after it add only paths a VM node does not take).
  - From the release itself: curl as the README says, SHA256SUMS
    checked, `vk8s create` fetched and verified the base files and the
    node and control-plane sets into ~/.vk8s/assets/v1.36.6-229e3489
    and returned in 29 s; node Ready, nginx rolled out in 10 s, delete
    clean.
  - Not in this release: the quieter snapshotter log (branch
    fix/snapshotter-quiet-log; it changes the snapshotter, so it needs
    its own 24-hour run). Not investigated: lan-throughput failed once
    in CI on 56175d4 (run 45918625357) and passed on 290d07a.
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
- [x] Image cache upkeep (user decision 2026-11-17: no automatic size cap;
  the user controls the cache). `vk8s cache status` shows each
  registry's size and the total (du in the cache VM, request cache-usage),
  data.img's allocated size on the host and the expiry. `vk8s cache prune
  [REGISTRY]` (request cache-prune:R,...; P.Plan.cache_prune) stops those
  registries, renames their storage aside and removes it, runs fstrim and
  prints what data.img freed; the supervisor restarts them empty 5 s later
  and clusters fall back to the upstream meanwhile. A stopped cache is
  started for the prune and stopped again. Expiry checked in distribution
  v3.1.2: proxy ttl 168h counts from when a blob or manifest was cached
  (proxyblobstore.go, proxymanifeststore.go schedule it only after an
  upstream fetch); cache hits do not extend it. Laws and gate done; open:
  a run on a Mac with a filled cache (prune frees data.img on the host).
  User decision 2026-11-17 (PR #58): `cache prune` empties the whole
  cache, every blob of all registries, with no --all flag and no
  expired-only mode; an optional REGISTRY narrows it. The ttl stays
  distribution's 7 days from fetch; 3 days from last use comes later
  with a Bend registry.
  - Mac evidence (2026-11-18, main 9a30847): `cache status` showed
    docker.io 575.1 MiB, registry.k8s.io 312.7 MiB, ghcr.io 38.4 MiB;
    `cache prune` took 5 s, emptied all four and printed "freed 925.9 MiB
    on the host (data.img: 1.2 GiB -> 336.5 MiB allocated)" (du agreed:
    337M). A new cluster then pulled nginx:1.27 and the cache refilled
    (docker.io 86.0 MiB).
  - Found on the way (follow-up): a cache VM started by an older vk8s
    (before the share-write hardening of #67) answered no request
    (`mkdir -p /var/lib/vk8s-host/requests` failed in its guest), so
    status showed no sizes and prune failed until `cache stop` and
    `cache start`. vk8s should restart a cache VM whose guest is older
    than its assets.
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
  - Run 4 (2026-11-18, after the layer store, NetworkPolicy and the
    security fixes; scripts/soak.sh 10 60): workload 172 rounds and 17
    pause/resume cycles, no leaked VMM, socket or cluster dir, cache
    growth under the 512 MiB limit; one of 10 cycles failed (cycle 7,
    pod not Ready within 180 s; 197 s for that cycle). The soak now keeps
    a failed cycle's pod, events, nodes and cluster logs (12efdb1).
    Rerun with 30 cycles: 30/30 passed.
- [x] 24-hour uptime run (docs/RELEASE.md "Gates"; scripts/uptime.sh 24),
  2026-11-26 01:43 to 2026-11-27 01:45 on this Mac: UPTIME OK. One
  cluster of two VM nodes with a 2-replica nginx Deployment and the
  default idle sleep, sampled from the host every 10 minutes (144
  samples) and checked through the API every 2 hours (13 checks,
  out/uptime/checks.csv and samples.csv).
  - Every check: 2 of 2 nodes Ready, 2 of 2 replicas available, 0
    container restarts in the whole run, and a new pod ran to
    completion. The first `kubectl get nodes` of a check, which wakes
    the cluster, answered in 176 ms (awake, check 0) and in 344 to
    1145 ms from sleep (median 450 ms).
  - Both VMM processes lived the whole run. Asleep (132 samples) their
    summed footprint was 13 to 17 MiB (mean 15); the sample 10 minutes
    after a wake read 586 to 1939 MiB (the two guests awake).
  - Disk: the layer store stayed at 296 MiB. The cluster's folder grew
    from 45 to 90 MiB, about 3.7 MiB with each wake and nothing while
    asleep. A second cluster on the release candidate, watched for 16
    minutes awake, shows where it goes: the daemons' logs on the share
    (1.5 MiB in 16 minutes for both nodes, 1.3 MiB of it
    snapshotter.log, which gets a line for each of the kubelet's and
    containerd's Stat and Usage calls, about five a second) and the
    data disks between two fstrim runs (the control plane's went from
    26.0 to 28.1 MiB and back to 27.1 at the 10-minute fstrim). Both
    have a bound: PID 1 cuts a log past 32 MiB to its last 8 MiB
    (Plan.trim_logs), and fstrim gives freed blocks back. So a node's
    logs can reach about 40 MiB per daemon before they stop growing; a
    quieter snapshotter log (a line only for a call that changes the
    state or takes 100 ms or more; Spb.log_due, two proposed laws) is
    on branch fix/snapshotter-quiet-log for the release after this
    one, since it changes the snapshotter and so needs its own run.
  - Built from a6ccf81 (binary and guest assets). The commits on main
    since then that touch the run's paths add branches VM nodes do not
    take: the layer store in node containers, on a native host node and
    in the macOS node host (host/snapshotter.bend and src/layers: the
    no-wait mode, which a VM node does not use, layers_ask.waits_v4_vm;
    host/init.bend: the node-host role only; host/layers/fill.bend:
    the list gc keeps). bend-vmm's pin is the same. So the run holds for
    the release candidate at 103627a under RELEASE.md's rule.
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
  - Delta review (2026-11-18, main 5d014ca, factory explorer
    review-security-boundary-delta, report in
    docs/ref/review-security-boundary-delta.md) of what changed since: the
    shared layer store, NetworkPolicy and its gate, rshared /, native
    mode, the cache VM. No high finding. Unpack traversal and links,
    digests before publish, guest writes to the store, rshared and
    native signals: no finding. Being fixed (branches, then merged here):
    F1 native delete/restart touch host-wide iptables tables and the
    shared kubepods cgroup (feat/sec-native-scope); F2 NetworkPolicy is
    IPv4 only, fe80:: can bypass it (feat/sec-netpol-ipv6, with F7 ro
    layers mount and F8 native stale gate); F3 `layers gc` ignores
    layers.held, F5 fill/gc race, F6 unpack size caps
    (feat/sec-layers-gc). F4 (known gap until bend-vmm adds it): the
    1 GiB share quota counts written bytes, not inodes; asked bend-vmm
    for a per-share inode cap.
    Fixed: F1-F3 and F5-F8 merged in 791b835 (native_boot.v3 keeps F1's
    per-cluster cgroup and iptables scope with F8's clean step); F4 by
    the bend-vmm pin 0x37f03198 (4431b9a, `--share DIR,quota=1G,
    inodes=100000`, 93d1890). Evidence: gate green; CI on a296f4f green
    (push run 44304191063, native-smoke included); native re-certified
    450/0 (run 44327346899); Mac smoke 2026-11-18: a 3-node cluster with
    the inode cap, NetworkPolicy e2e 28/0 with IPv6 off in pods and
    fe80:: blocked.
    F3 and F5 came in with commit 6694748: gc reads every node's
    layers.held, and a fill writes the record before the rename. Its
    store-wide ~/.vk8s/layers.lock now has a per-layer successor (W2,
    W4: ~/.vk8s/layer-locks/<hex>), so fill and gc no longer fail on
    each other. The report's notes and its table say so.
- [x] README (every command, building from source, verification) and
  DESIGN.md (snapshot, shutdown, upgrade, cache, pinned assets).

- [x] License and attribution (2026-11-27; the owner chose Apache-2.0).
  The repository had no license file. Now: LICENSE (Apache-2.0), NOTICE
  (derived from vcluster by Loft Labs, Apache-2.0, none of whose source
  files are here: checked, no file of vcluster/ is in the tree; what is
  taken is behaviour, formats, names, chart defaults and tests restated
  as laws; not affiliated with Loft Labs) and THIRD_PARTY_LICENSES.md
  (each program the assets hold, with version, license and source,
  among them the GPL-2.0 kernel and BusyBox and the Debian packages,
  and where their source is). scripts/release-assets.sh copies the three
  into every release from the next one on; releases v1.36.6-229e3489
  and v1.36.6-37a70144 do not have them. README says what vk8s is
  without calling it vcluster, with the disclaimer and a License
  section. Comments and docs that used "vcluster" for our own cluster
  say "virtual cluster" (53 lines; references to vcluster's code and
  tests stay), and so do the three CLI lines after create and connect.
  Left as they are: laws/ and proofs/ (the spec), docs/ref and this
  file's history, and the names that are vcluster's format
  (vcluster.yaml, vcluster.loft.sh/ labels, /var/lib/vcluster, the
  namespace vcluster-<name>): changing them would break compatibility.

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
  - PID 1 runs busybox `fstrim -v /var/lib/vcluster` every 10 min (600
    ticks of 1 s; was 2400 of 250 ms) in the background on every VM: control plane,
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

- [x] Linux arm64 on KVM (UNVERIFIED on KVM; accepted as such by the
  user 2026-11-17, no arm64 KVM host available): build, smoke test,
  release asset. Build done
  (#44, merged 4a5769a): `bend -o` natively on ubuntu-24.04-arm (X11
  headers for bend-vmm's display), `vk8s version` and `--help` run there;
  the image copy, preflight and dates now go through Bend (clone via a
  spawned cp with an argument list, PATH lookup in Bend, dates in Bend);
  Mac smoke of the merge passed (create, list, describe, Ready, delete). bend-vmm runs
  on KVM today (needs an in-kernel GICv3; images on ext4/xfs; memory via
  VmRSS or cgroup; snapshots restore only on the hypervisor that took
  them). GitHub's arm64 runners have no /dev/kvm.
  Smoke under emulation (decided: arm64 KVM is tested under emulation and
  recorded as such): workflow emulated-kvm (nightly, by hand, and on pull
  requests that change host/vk8s.bend or the smoke) builds
  vk8s-linux-arm64 and the arm64 assets on ubuntu-24.04-arm, then
  scripts/smoke-emulated-kvm.sh boots an Ubuntu arm64 L1 with KVM in QEMU
  TCG with EL2 (-machine virt,virtualization=on -cpu max, as bend-vmm's
  host-linux job) and runs scripts/smoke-linux.sh in it, with an ext4 work
  disk for HOME and the assets. Waits scale for the emulation:
  SMOKE_SLOW=6 for the smoke, VK8S_WAIT_SCALE=20 for vk8s (new, laws
  cli.wait_scale.* and cli.wait_tries.* proposed). The full smoke does
  not fit nested TCG: run 43962666574 (c3dda68,
  https://github.com/chenhunghan/bend-vk8s/actions/runs/43962666574)
  failed after 78 min of `vk8s create`: in the L2 the API server could
  not finish TLS handshakes to itself ([::1]:6443 openapi "TLS handshake
  timeout"), kine queries took 1 to 1.4 s, and the boot's
  default_endpoints wait failed. So under emulation the job runs the
  minimal smoke (SMOKE_MINIMAL=1, what this section asks): create one
  control-plane VM of 2 vCPUs, no worker, no image cache VM, the node
  Ready, a pod Running, delete, nothing left; the L1 has one vCPU (one
  TCG thread) per L2 vCPU. The gVisor pod, snapshot and restore stay in
  the real-KVM amd64 kvm-smoke job. The minimal smoke did not fit nested
  TCG either: run 44000027583 (8fce2fd) ran 87 min and the one
  control-plane node never passed the Bootstrap wait. Merged (#53,
  2026-11-17) with the emulated-kvm workflow manual only
  (workflow_dispatch). Open, for the future: a real arm64 KVM host (a
  self-hosted runner or a cloud arm64 machine with KVM) to run
  scripts/smoke-linux.sh. Published anyway at the user's request
  (2026-11-17): release v1.36.6-f3265aa9
  (https://github.com/chenhunghan/bend-vk8s/releases/tag/v1.36.6-f3265aa9)
  carries vk8s-linux-arm64 (CI run 44042627488, 5d013a7; libX11 loaded at
  run time) and the arm64 role sets. Tested from the download on a Debian
  13 arm64 host (dev VM): SHA-256 OK, assets fetched and verified, native
  cluster created in 25.8 s, node Ready, deleted clean (a pod ran in the
  same test from a local mirror). Found and fixed on the way: macOS tar
  put ._ members and provenance xattrs into the archives (5d013a7). Open:
  native preflight looks up iptables-save only on the user's PATH, which on
  Debian lacks /usr/sbin. Release prep: scripts/release-assets.sh --binary adds
  vk8s-linux-arm64 to the arm64 release (next to vk8s-darwin-arm64, the
  same assets) and vk8s-linux-amd64 to the amd64 release, with their
  SHA-256 in SHA256SUMS (docs/RELEASE.md); nothing is published yet.
- [x] x86_64 on KVM: amd64 guest assets, bend-vmm x86_64, smoke test and
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
  #47 (merged 2026-11-16): per-arch manifests and role sets (Manifest.arch
  from uname), an amd64 guest (Alpine linux-virt x86_64 bzImage, the x86
  module list, console=ttyS0, linux/amd64 image platform), bend-vmm pinned
  at 0xd0e7b290 (adf9dcc, x86 reboot fix), and scripts/smoke-linux.sh in
  CI job kvm-smoke on ubuntu-24.04 with real KVM: an amd64 cluster is
  created, nodes go Ready, a pod runs, snapshot and restore keep it (restore
  22.8 s, nodes Ready 16.2 s later), delete leaves nothing. The smoke found
  that `vk8s snapshot` could miss kine's last commit (SQLite WAL): the CLI
  now asks the guest to sync before pausing. On the Mac the same merge
  found macOS tar adding AppleDouble entries (com.apple.provenance) that
  made restore refuse the archive; fixed with COPYFILE_DISABLE. Mac arm64
  on the merged build: snapshot round trip keeps the pod; regression 43/0
  standalone (11 min) and classic (15 min). Open for this item: the
  regression subset on amd64 (only the smoke runs there so far) and an
  amd64 release manifest.
  Done 2026-11-16: #51 adds CI job kvm-regression (ubuntu-24.04, real
  KVM, default VM sizes): the regression subset on amd64 passed 43/0 in
  standalone (14 min) and in classic (19 min), run 43901079845. An amd64
  release manifest comes with the next release.
  CI job kvm-regression (after kvm-smoke, from its amd64 build artifact)
  runs scripts/regression.sh on ubuntu-24.04 with real KVM, one mode per
  runner (MODES=standalone, MODES=classic), default VM memory, sonobuoy
  v0.57.5 pinned by sha256; it uploads the results archives. Its focus
  list is scripts/regression-focus.txt, rebuilt from sections 2 and 3
  because out/conformance/regression-focus.txt was never committed; it
  matches 36 conformance tests, not the original 43.
  Phases 2 and 3 of docs/ref/explore-linux-hosts.md (branch
  feat/linux-arch-assets): bend-vmm pinned at 0xd0e7b290 (adf9dcc, x86_64
  snapshots and a reset stub at the BIOS reset vector, so an x86_64 guest
  reboot no longer hangs); per-arch manifests (Manifest.for_arch from `uname -m`;
  manifest_arm64.bend keeps v1.36.6-42a05fb8, manifest_amd64.bend has no
  release yet, so amd64 hosts need VK8S_ASSETS); ARCH=amd64 for
  fetch-assets.sh (loft-sh amd64 bundle 22d989e0, registry 40df2224),
  alpine-kernel.sh (bzImage), build.sh (zig x86_64 musl and gnu.2.38,
  stripped; Alpine busybox-static), debs.py (amd64 Debian root), pack.sh
  (modules.amd64.txt, no ACPI button) and release-assets.sh; console=ttyS0
  and VK8S_ARCH=amd64 on x86 (Cli.arch_flags), the guest's image import
  platform linux/amd64 (Plan.arch_args). CI job kvm-smoke runs
  scripts/smoke-linux.sh on ubuntu-24.04 (real KVM) with the amd64 build;
  its arm64 leg skips on hosted runners without /dev/kvm. Evidence (the
  smoke run and its timings) follows from CI; the regression subset on
  x86_64 is still open. Rebased onto the per-role asset sets (#48): each
  arch builds base.img and its role sets (mksets.sh into
  ~/.vk8s/assets/<ver>[-amd64]), release-assets.sh pins each arch's base
  files and set archives in manifest_<arch>.bend (Manifest.sets_for), and
  the host picks its arch, then its role's sets of that arch's release.
- [x] Native mode on Linux: the control plane as a systemd unit, nodes
  joining by bootstrap token, regression subset then a certified run.
  Pure layer merged (#46, 778fbcd): src/standalone/native.bend (the native
  boot plan: the cluster layer without the machine layer, relocated under
  a per-cluster data dir; laws/done/native, proved under --verdict) and a
  host-safe shutdown in host/init.bend (Sys.term, SIGTERM to its own
  daemons only; never kill(-1), umount -a or poweroff). native-envtest in
  CI runs a reduced native plan as a normal process. Mac: the VM PID 1
  path is unchanged (create, both nodes Ready, delete in 16 s).
  Host side (N3 to N5, docs/ref/native-host.md): `vk8s create NAME
  --backend native` installs vk8s-NAME.service (Restart=always,
  KillMode=control-group, Delegate=yes; sudo steps as argument lists,
  each printed), extracts the node and control-plane sets into
  /var/lib/vk8s/NAME, and runs the control plane and, on the host's
  first native cluster, the host node (containerd, kubelet, flannel,
  kube-proxy) on per-cluster ports. Delete removes the unit, the pods,
  their mounts, cgroups and iptables rules, cni0 and the dirs
  (src/standalone/native_host.bend, laws/native_host.bend). The join
  server of a native cluster serves the installing join script
  (Join.install: node bundle, containerd and kubelet units). CI job
  native-smoke; its timings are in the job summary. Merged (#52, 2026-11-17;
  gate and Mac VM smoke green after the merge). Regression subset in CI
  (native-regression, x86_64): 42 passed, 0 failed (the two-node DaemonSet
  test is skipped: a native cluster has one node, the host). Certified
  run: CI job native-certified (workflow_dispatch, or a PR labelled
  `certify`; scripts/conformance.sh certified-conformance on a native
  etcd cluster `cert`, counts in the job summary, archive as artifact
  certified-native-standalone-amd64). Its run of 2026-11-17 on one node
  (skip of the DaemonSet test only): 448 passed, 1 failed (`should have
  at least two untainted nodes`), 7137 skipped, 115 min. A skip makes a
  run non-certified, so the job now joins a second node and skips
  nothing: scripts/native-worker.sh starts an isolated systemd container
  on the runner (kind's node image as the root; own mount, cgroup and
  network namespaces; no Docker network, a veth on the bridge vk8sw0)
  and runs the cluster's installing join script in it (`vk8s token
  create`, Join.install: vk8s's node bundle, containerd and kubelet).
  flannel host-gw cannot route the host's pods to that node through the
  runner's eth0, so a policy rule (table 177) routes its pod CIDR through
  vk8sw0. The join script gives kubeadm join a kubeletconfiguration
  patch (Join.install.patches): the cluster's kubelet-config names the
  host's CA path (/var/lib/vk8s/<name>/pki/ca.crt), which a joined node
  lacks, so its kubelet reads the CA kubeadm join writes to
  /etc/kubernetes/pki/ca.crt (run 44054467129 failed there, at
  kubelet-wait-bootstrap). The node's containerd finds the bundle's
  shim first on its PATH (the unit sets PATH=$bin:...; the law
  join.install.containerd keeps runtime_path out of the node's
  config): run 44071111406 joined
  cert-w1, but containerd took kind's newer shim from /usr/local/bin and
  no sandbox started ("failed to create TTRPC connection: unsupported
  protocol"), so flannel's DaemonSet pod never wrote the CNI config and
  the node stayed NotReady. Two-node runs: PR runs 44125381848,
  44136970939 and 44153577932 had 449 passed, 1 failed each, and run
  44177358472 on main 8b29df0 had 447 passed, 3 failed. Every failure
  except one was a NodePort session affinity test (`should have session
  affinity work for NodePort service`: "service is not reachable within
  2m0s timeout on endpoint 10.1.1.189:31339"; `should be able to switch
  session affinity for NodePort service`: "Affinity shouldn't hold but
  did"). In each one, the exec pod was on cert-w1, it called the host's
  IP, and 2 of the 3 backends were on cert-w1. Only the host's backend
  answered (run 44177358472: 10 of 16 curls, all from the one backend
  on cert). Cause: the host DNATs the packet to a pod on cert-w1, and
  that route leaves through vk8sw0, the bridge the packet came in on.
  With br_netfilter, such a packet is bridged again from its ingress
  port, and the bridge drops it because vk8sw0h is not in hairpin mode.
  The KVM runs have no such bridge between nodes. Fix:
  scripts/native-worker.sh turns hairpin mode on for vk8sw0h and fails
  `up` when it is off. The test harness is the only change; the native
  host plan and its laws stay as they are. The third failure in
  44177358472, `[sig-node] Probing container should *not* be restarted
  with a GRPC liveness probe`, happened once in the four runs: on
  cert-w1, "Liveness probe failed: timeout: failed to connect service
  \"10.244.1.50:5000\" within 5s" 25 s after the container started
  (FailureThreshold 1). The archive keeps no kubelet log from that time,
  so its cause is still open. The job's failure logs now keep cert-w1's
  probe failures and its neighbour table on cni0. That table can show a
  stale MAC for a pod IP that was used before (the bridge CNI plugin
  sends no gratuitous ARP).
  Certified (2026-11-18): run 44237295035 (bd85a0a), native-certified,
  native control plane plus a joined worker: sonobuoy certified-conformance
  Passed 450, Failed 0 (skipped 7136, 115 min; archive
  202611180544_sonobuoy_aa722e92-...). The gRPC liveness probe passed.
  Open: per-cluster
  netns (N6), worker VMs for native clusters (bend-vmm's user-mode NAT
  gives the host no route to a VM), pause/snapshot/upgrade of native
  clusters.
  - Two [Conformance] tests need two nodes: `[sig-apps] Daemon set
    [Serial] should rollback without unnecessary restarts [Conformance]`
    (test/e2e/apps/daemon_set.go:451 in Kubernetes v1.36: "Conformance
    test suite needs a cluster with at least 2 nodes.") and
    `[sig-architecture] Conformance Tests should have at least two
    untainted nodes [Conformance]` (test/e2e/architecture/conformance.go).
    A native cluster's own node is the host, so a certified run needs a
    joined node; vcluster standalone passes them when private nodes
    join. native-regression still has one node and skips the DaemonSet
    test.
  - gRPC liveness probe (2026-11-18): the native-focus job (scripts/
    native-focus.sh) ran only that test 10 times on a native 2-node
    cluster, twice (runs 44218324102 and 44218309622): 20 of 20 passed,
    with kubelet -v=4 probe logs. It failed in 2 of the last 2 full
    certified runs (449/1), so it depends on full-suite load on the shared
    runner (the native worker shares the runner with the control-plane VM
    and the GitHub agent), not on the probe path itself.
  - Default backend on Linux is native (2026-11-18, 50e18a7):
    Backend.parse.v2 picks native when `uname -s` is Linux and vm
    otherwise; an explicit `--backend` wins (laws backend.default_v2_*,
    backend.parse_v2_*; v1 laws unchanged). Evidence: native
    re-certified after the cgroup fix (root controllers enabled, reset
    v3): run 44327346899 on 649419d, native-certified Passed 450,
    Failed 0 (skipped 7136, 116 min; archive
    202611181456_sonobuoy_00731dc8-...). The run before it on a296f4f
    (44304969823) had one failure, `[sig-node] Probing container should
    *not* be restarted with a tcp:8080 liveness probe`: the worker
    cert-w1's kubelet timed out dialing its own pod 20 s after start
    (FailureThreshold 1). native-focus ran that test alone 10 times
    (run 44327364338): all passed. Same pattern as the gRPC probe above,
    load on the shared runner; open: whether the worker's stale cni0
    neighbour entries (FAILED for reused pod IPs) add to it. macOS stays
    vm (container-mode footprint, below).
- [x] Container mode: `--backend container` on Linux (namespaces + cgroup
  v2, no Docker) and on macOS (node containers in one shared bend-vmm VM);
  smoke test and the regression subset in CI and on the Mac.
  - Pure part (Phase 6 C1 and C3 of docs/ref/explore-linux-hosts.md):
    `src/guest/container.bend` renders a node's OCI config.json and
    `Plan.boot_container` (laws/container.bend, proven); CI starts the
    config with runc over busybox (tests/container_runc.sh). The macOS
    node host (C4) is open.
  - Host integration (C2): `vk8s create NAME --backend container
    [--nodes N]` runs on a Linux host as root. src/cli/ctr.bend decides
    every name, address, argument list and message (laws/ctr.bend,
    proposed); host/vk8s.bend (Vk8s.ctr.*) runs them as argument lists,
    with no shell. Per cluster: a slot k (1..250), the bridge vk8sbr<k>
    at 10.10.k.1/24, MASQUERADE and FORWARD accepts tagged
    `vk8s:<cluster>`, host cgroup delegation under /sys/fs/cgroup/vk8s,
    and the asset disks (base.img and each set) loop-mounted read-only
    and joined in a read-only overlay at <dir>/assets. Per node: the
    initramfs unpacked as its root, its data dir and share, a named
    network namespace with a veth (eth0 at 10.10.k.(2+i)), and runc
    (`run -d`) with the config.json of C.Container.config joined to that
    namespace. A kernel preflight (root, tools, modules, cgroup v2
    controllers) runs first. PID 1 takes VK8S_NODE_IP as the control
    plane's address, drops the cache VM's registry mirrors, and sets
    kube-proxy's conntrack.maxPerCore to 0 (container_host laws).
    `delete` (by cluster.env BACKEND=container) asks each PID 1 to stop
    on its share, then removes the containers, namespaces, bridge,
    tagged rules, cgroups, mount and directory; `list`, `pause` and
    `resume` use runc state, pause and resume. CI job container-smoke
    (tests/container_smoke.sh): create with a worker, nodes Ready,
    flannel and CoreDNS available, a pod Running, delete, nothing left;
    on ubuntu-24.04-arm and ubuntu-latest (amd64), both gating. In a
    node container flanneld uses eth0, not the VM's eth1
    (Container.adapt rewrites the manifest's --iface), and an amd64
    node gets VK8S_ARCH=amd64 in its environment (Ctr.arch_env).
  - Regression subset in container mode (branch
    feat/container-regression-nodehost): scripts/regression.sh takes
    VK8S_BACKEND=container (it passes `--backend container` to each
    create, refuses classic, and on Linux starts itself again under
    sudo). CI job container-regression runs MODES=standalone (st,
    --backing-store etcd, 2 workers) on ubuntu-24.04-arm and
    ubuntu-latest from container-smoke's build; target 0 failed on the
    focus list (scripts/regression-focus.txt). Classic is not run in
    container mode: `--backend container` has no `--host-kubeconfig`,
    and a classic vcluster's host Services point at 10.0.2.2 (the VM
    NAT), which a container host cluster's pods cannot reach. Evidence
    follows from CI.
  - macOS node host (C4, D11 a; branch feat/container-regression-nodehost):
    src/cli/nodehost.bend (laws/nodehost.bend, proposed; no done marker
    until CI proves them) decides the node host: one bend-vmm VM at
    ~/.vk8s/nodehost (8 GiB, 4 vCPUs, balloon auto; VK8S_NODE_HOST_MEMORY
    and VK8S_NODE_HOST_CPUS override), the base disk, a data disk, the
    node, control-plane (and images) sets, the share, and 16 forwards
    127.0.0.1:16401-16416 fixed at start (bend-vmm's cap), so at most 16
    container clusters per Mac; cluster k (slot 1..16) has API port
    16400+k, which a tagged DNAT rule in the VM sends to 10.10.k.2:6443.
    host/init.bend's node-host role boots Nh.boot, then serves the Mac's
    requests on the share (up, join, down, pause, resume) by running
    the steps Nh.up, Nh.join, Nh.down and Nh.freeze build from
    src/cli/ctr.bend (bridge, veth and netns, rules, cgroups, the
    initramfs unpacked as each node's root, runc), and keeps runc's list
    on the share for `vk8s list`. Each node's share is on the node
    host's share (clusters/<name>[/nodes/worker-<i>]/share), its root
    and data on the VM's ext4 data disk. `vk8s delete` stops the
    cluster's nodes (stop file, then cgroup.events empty, then runc
    kill and delete), removes its network, rules and cgroups, and stops
    the node host when no NODEHOST=1 cluster is left. The guest root
    gains Debian's iproute2 and GNU cpio (busybox's ip has no netns or
    veth, its cpio no -D). VK8S_NODE_HOST=vm takes the same path on a
    Linux host with KVM: CI job nodehost-smoke (amd64, real KVM,
    tests/nodehost_smoke.sh) creates two clusters in one node host,
    checks nodes Ready, a pod Running, list, pause and resume, and that
    the node host stops with the last delete. Open: the Mac smoke and
    the regression subset on the Mac
    (`VK8S_BACKEND=container MODES=standalone scripts/regression.sh`),
    run by the maintainer; one request at a time per node host (two
    concurrent vk8s commands share one request slot).
  - `src/cli/backend.bend` parses `--backend vm|container|native` in
    the host CLI. The effective default stays vm; native answers that it
    is not available yet. No done marker for container_host, backend or
    ctr until CI proves them.
  #54 (merged 2026-11-16): CI job container-regression runs the regression
  subset with --backend container (standalone, etcd, 2 workers) on
  ubuntu-24.04-arm and ubuntu-latest: 43/0. macOS: `--backend container`
  starts or reuses one shared bend-vmm node-host VM (8 GiB, 4 vCPUs, API
  forwards 127.0.0.1:16401-16416, so at most 16 container clusters) and
  runs the node containers in it; delete stops the node host when no
  container cluster is left. Mac (M2) 2026-11-16: create with 1 worker in
  24 s, both nodes Ready, list/pause/resume, delete stopped the node host;
  regression subset in container mode 43/0 in 11.7 min. Classic over a
  container-mode host cluster is not supported yet (no --host-kubeconfig
  for --backend container; host Services point at the VM NAT address).
  Footprint, measured once 2 min after create: the node host held 3.1 GB
  (resident 2.4 GB, balloon still inflating) for a cluster that VM mode
  holds in ~1.8 GB; to be measured settled before container becomes the
  macOS default. Settled (2026-11-16, 30-pod burst then 15 min idle, one
  cluster with 1 worker): node host 3.3 GB phys_footprint (resident
  2.5 GB, balloon 3967 MiB, its half-of-RAM cap) and 19.6% idle host CPU,
  against ~1.8 GB and ~8-11% for the same cluster in VM mode. The macOS
  default therefore stays vm (GOAL section 8 decision: container becomes
  the default only with evidence); open work: the node host's page-cache
  reclaim and balloon cap, its 4 vCPUs, and per-container kubelet/cgroup
  overhead, then measure again.
  Node-host footprint (PR #55, merged): the node host's PID 1 ran none of a cluster VM's
  periodic chores, and the node containers skip them by law
  (container_host.no_machine_maintenance), so in container mode nothing
  reclaimed page cache, compacted, trimmed the data disk, trimmed the
  share's logs (each node's runc output) or set the clock after the Mac
  slept. Nhi.serve now runs Nh.chores each second: log trim 60 s, clock
  10 s, fstrim 10 min, guarded idle reclaim 30 s, idle compaction
  10 min, as Init.supervise (laws nodehost.chores_*). runc's list goes to
  the share after each request and every 30 s (was every 5 s; law
  nodehost.list_due). Defaults 2 vCPUs and 6144 MiB (were 4 and 8192;
  law nodehost.defaults): the auto balloon holds at most half of RAM, so
  8 GiB let the guest keep 4 GiB; 6 GiB is a 2-worker cluster's RAM in
  VM mode. The node host is sized at its first start, so many clusters
  need VK8S_NODE_HOST_MEMORY and VK8S_NODE_HOST_CPUS. Kubelet in a node
  container matches kind (cgroupRoot /kubelet, private cgroup namespace;
  kind sets no housekeeping interval), so no kubelet change. Open: the
  idle check counts all vCPUs, so with many busy clusters the reclaim
  does not run. Measured on the Mac (2026-11-17, 1 worker, 30-pod burst
  then idle): phys_footprint 1.6 GB at 3, 10 and 15 min (resident
  1.56 GB, balloon 2961 MiB), was 3.3 GB; idle host CPU 14.5%, was
  19.6%. VM mode for the same cluster: ~1.8 GB, 8-11%. Memory now beats
  VM mode; CPU does not, so the macOS default stays vm (section8
  decision: switch only with footprint evidence and a certified run).
  Next: profile the node host's idle CPU (kubelet x2, containerd x2,
  control plane in one guest).
  Settled, one run each (2026-11-18, Mac M2, scripts/bench/mode-footprint.sh,
  sleep off; 10 min settle, then a 30-pod burst, deleted, 15 min idle;
  phys_footprint and CPU summed over the cluster's VMMs over 5 min; the
  image cache VM was not running in any measurement):

  | nodes | mode | phase | footprint MiB | CPU % | disk MiB |
  |---|---|---|---|---|---|
  | 1 | vm | settled / after burst | 1296 / 1446 | 12.0 / 12.7 | 305 / 341 |
  | 1 | container | settled / after burst | 1354 / 1491 | 10.0 / 8.0 | 451 / 456 |
  | 3 | vm | settled / after burst | 2583 / 2776 | 11.3 / 11.7 | 741 / 785 |
  | 3 | container | settled / after burst | 1892 / 2110 | 14.7 / 12.0 | 1034 / 1041 |

  Not lighter overall, so the macOS default stays vm. For one node
  (what `vk8s create` makes by default), container mode holds about
  60 MiB more memory and 150 MiB more disk, though it uses less CPU. For
  three nodes it holds about 25% less memory, because the nodes share
  one guest kernel and page cache, but it uses more CPU (14.7% against
  11.3% settled) and about 40% more disk (the node host's data disk and
  each node's unpacked images). Container mode is the better choice for
  multi-node clusters when memory is the limit, so it stays a documented
  option; it does not become the default.
- [x] gVisor RuntimeClass: runsc and its containerd shim in the nodes, an
  opt-in `gvisor` RuntimeClass; a pod runs under it in each backend.
  VM nodes (Mac, amd64 KVM), container and native nodes (#57, merged
  2026-11-17): CI container-smoke (arm64, amd64), native-smoke and
  nodehost-smoke green on d5747d5 (run 44031265586); Mac container mode
  after the merge: a gvisor pod Succeeded (dmesg "Starting gVisor...",
  uname 4.19.0-gvisor) and a runc pod ran as the default.
  - VM nodes (feat/gvisor-runtimeclass): gVisor 20261109.0 (runsc,
    containerd-shim-runsc-v1, gvisor-bin/ without checkpointgofer and
    runsc-metric-server) in the node set, pinned per arch in
    scripts/guest/fetch-assets.sh (gvisor-aarch64 and gvisor-x86_64
    .tar.bz2, SHA-256 from the release's SHA256SUMS). Plan.runtime writes the runsc runtime (containerd
    v3 keys) and runsc.toml (systrap); modules.txt loads af_packet
    (runsc's sandbox network opens AF_PACKET raw sockets on the pod's
    veth); Plan.node applies the `gvisor`
    RuntimeClass (laws plan.containerd_runsc*, plan.runtime.runsc,
    plan.runtimeclass_gvisor, plan.node.runtimeclass_gvisor; that runc
    stays the default is a check in tests/gvisor_boot.bend, as the law
    ran the verdict kernel out of fuel). CI
    (assets-disk, role gvisor, 4 KiB pages) boots a node from the
    rendered plan under qemu and checks that a pod with
    `runtimeClassName: gvisor` prints "Starting gVisor" in its dmesg and
    a runc pod does not. The amd64 kvm-smoke job (scripts/smoke-linux.sh,
    real KVM, the vk8s binary) runs busybox's dmesg with
    `runtimeClassName: gvisor` on the worker and checks its log for
    "Starting gVisor".
  - Container-mode and native-mode nodes (#57,
    feat/gvisor-container-native): they run the VM's Plan.runtime and
    Plan.node, so they get the runsc runtime and the RuntimeClass already;
    native mode extracts the whole node set (runsc, the shim, gvisor-bin/)
    into its data dir. Added: Container.runsc_caps, the capabilities runsc
    uses (gVisor's gofer caps, the sandbox's ambient caps, systrap's
    CAP_SYS_PTRACE, CAP_NET_ADMIN and CAP_NET_RAW for the AF_PACKET
    sandbox network), which the node container grants
    (container.runsc_caps_held). It has no seccomp, AppArmor, masked or
    read-only path, and keeps runc's default /dev nodes. Ctr.modules.v2
    makes the container host load af_packet (the node host VM loads it
    from modules.txt). On a native host node, runsc.toml names the shim's
    root, which moves under the data dir, so runsc's state stays out of
    the host's /run/containerd (native.runsc_text, native.extra_runsc,
    native.runsc_root). Checks: tests/container_smoke.sh
    (container-smoke, arm64 and amd64), tests/native_smoke.sh
    (native-smoke) and tests/nodehost_smoke.sh (nodehost-smoke, the macOS
    path on amd64 KVM) run busybox's dmesg with `runtimeClassName:
    gvisor` and check "Starting gVisor", and check that a runc pod runs
    as the default. First CI run:
    https://github.com/chenhunghan/bend-vk8s/actions/runs/44031265586
    (passed).
  - Open: the 16 KiB-page kernel (gVisor assumes 4 KiB pages), and
    footprint and idle CPU under gVisor on the Mac.
  #50 (merged 2026-11-16): runsc and containerd-shim-runsc-v1 pinned per
  arch in the node role set, a runsc runtime (systrap) in the generated
  containerd config, and a `gvisor` RuntimeClass applied at boot (laws in
  laws/plan.bend; runc stays the default). Mac: a pod with
  runtimeClassName gvisor ran to Succeeded in a bend-vmm VM node, its
  dmesg "Starting gVisor...", uname 4.19.0-gvisor; the regression subset
  on that build passed 43/0 standalone (11.0 min) and classic (15.3 min).
- [x] Linux dev VM on the Mac: a bend-vmm VM with a Debian arm64 root
  filesystem and systemd, to run vk8s-linux-arm64 (container and native
  modes, gVisor) locally. #43 (merged): scripts/dev/rootfs.sh builds the
  image in CI (job dev-vm, qemu boot test), scripts/dev/linux-vm.sh boots
  it under vk8s's embedded bend-vmm. On the Mac 2026-11-16 (artifact of
  run 43850997387, pinned): `systemctl is-system-running` = running,
  aarch64, 4 vCPUs, 3.9 GB, cgroup v2, the repo at /repo, ssh on 2222.

- [ ] Linux release gates (opened 2026-11-27; a note for the next
  session). Release v1.36.6-229e3489 / v1.36.6-37a70144 ran certified
  conformance, the soak and the 24-hour uptime run on the Mac only. On
  Linux it has CI's smoke and regression jobs (run 45920693816). To call
  Linux production ready by docs/RELEASE.md's gates:
  1. Native, amd64: done. CI job native-certified on main bfee8fb (same
     code as the release's 290d07a), run 45955208678, 2026-11-27:
     passed 450, failed 0 in 1 h 54 min ("vk8s certified-conformance on
     cert (Linux x86_64): PASS").
     - The run as a whole is red for another job: container-smoke on
       arm64, tests/native_layers.sh "(e) after the last delete: no loop
       device on a store" and "as many loop devices as before the test
       (0, 38)". The opt-in layer store of a native host node
       (VK8S_LAYERS=1) left 38 loop devices after the cluster's delete,
       once. To look at; it passed on 290d07a (run 45920693816).
     - Main's own run on 5cf2d8b (45959492049) is red only in
       nodehost-smoke: Docker Hub answered the node's pull of busybox
       with 429 Too Many Requests, so no pod ran. Not vk8s; the test
       has no way around the limit yet (the node pulls it itself).
  2. KVM, amd64: not built yet. Add dispatch-only jobs beside
     kvm-regression, on ubuntu-24.04 (the runner with a writable
     /dev/kvm): kvm-certified, one job per mode (standalone, classic;
     scripts/conformance.sh in certified mode, as native-certified calls
     it), and kvm-soak (scripts/soak.sh 10 20, so far run only on
     macOS). Build them on a ci/ branch, where the heavy jobs run,
     until each is green once. Unknown: whether a control plane and a
     worker VM fit the runner's 16 GB, and whether a mode finishes inside
     GitHub's 6 hours for a job (about 2 hours on the Mac).
  3. Record the results here and in the amd64 release's notes
     (`gh release edit v1.36.6-37a70144`), which now say these ran on
     the arm64 assets only.
  Not covered by hosted runners, each a decision for the owner: KVM on
  arm64 (GitHub's arm64 runners have no /dev/kvm; kvm-smoke's arm64 job
  skips its steps there, so its green is not a test) and a 24-hour
  uptime run on Linux (longer than a hosted job). Either needs a Linux
  machine of the owner's as a self-hosted runner, or the owner accepts
  the Mac's run for the guest, which is the same code on both hosts.

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
- [x] Per-role contents (node set, control-plane set): implemented
  (footprint-decisions D1, branch feat/per-role-asset-sets): base.img
  plus one squashfs disk per set (node, control-plane, classic, cache,
  images; scripts/guest/sets.txt), mounted by PID 1 at /sets/<set> and
  joined at /var/lib/vcluster/bin by a read-only overlay
  (`Plan.disks.v3`, `Plan.with_sets`; the plans keep `Plan.disks.v2`).
  Each VM's role picks its sets (`Assets.role_sets`); the host fetches
  only those (`Manifest.sets()`, `Assets.fetch_into_sh`). New laws are
  proposed beside the old ones, which stay. Evidence still due: CI's
  per-role qemu boots (tests/kernel16k_boot.sh, sizes per set and role),
  then the Mac regression subset after merge, then a release that pins
  base.img and the sets.
- [x] Runtime-unneeded tools dropped: helm, crictl, the kube-proxy
  binary, vcluster-tunnel, the bandwidth and firewall CNI plugins
  (footprint-decisions A2). ctr stays (image import), etcdutl stays
  (etcd restore). The regression subset passes on it (above).
- [x] Preloaded images pulled through the image cache where it runs:
  implemented with D1: the tars are the images set, which a VM gets
  (and a host fetches) only when the image cache does not run; without
  it nothing is imported and kubelet pulls the add-ons through the
  cache (footprint-decisions A3). Evidence due: the Mac regression subset
  with the cache running (add-ons pulled) and with VK8S_CACHE=off
  (imported from the images set).
- Evidence for the two items above:
  Mac 2026-11-16 (#48 merged): per-role disks base 11 MB, node 64 MB,
  control-plane 88 MB, classic 25 MB, cache 12 MB, images 86 MB; a worker
  mounts base + node, the control plane base + node + control-plane, and
  with the image cache running no VM mounts the images disk (the add-on
  images come through the cache). A 2-node cluster went Ready, and
  scripts/regression.sh passed: standalone 43/0 in 11 min, classic 43/0
  in 15 min.
- [x] Download and on-disk assets about 200-300 MB per arch; regression
  subset passes. 2026-11-16, main 8a92017: vk8s-init and vk8s-guest built
  stripped (zig -s; 81 MB -> 7.8 MB each) and a fresh fetch without the
  dropped tools: assets.img 287 MB squashfs (was 1.03 GB raw ext4; 274 MB
  gzip'd, so the download is ~285 MB with the kernel and initramfs). The
  regression subset on it: standalone 43/0 in 11 min, classic 43/0 in 16
  min. arm64 measured; amd64 follows with its assets.

## Follow-ups after the release

### Code review findings (2026-11-16), deferred until GOAL sections 8-9 are done

Reports: docs/ref/review-bend-vk8s-pr-{40,46,47,48,49}.md and
docs/ref/review-direct-commits-main.md. Deferred at the user's call (goal
first); native P1 items are being fixed in #52.
- [x] Snapshot/request (pr-47): symlink-safe host writes into guest shares
  (P1); a failed sync must fail the snapshot (P1); private extraction dirs
  in fetch-assets.sh; restore ignores AppleDouble entries (direct F12).
  Done 2026-11-17 (branch fix/snapshot-request-hardening):
  - Host writes into shares go through `Vk8s.share_put`/`share_copy`: a
    0600 temporary file in a host-owned directory, then `BinFile.place`
    (host/effs/bin_file.c), which walks the share path with openat and
    O_DIRECTORY | O_NOFOLLOW and moves the file with renameat. A link
    planted at any component fails (ENOTDIR on Linux, ELOOP on macOS); a
    link at the name is replaced, not followed. Used by the request
    channel (`Vk8s.request.n`), the container stop file, discovery.conf
    (VM, container and node-host workers), vk8s.cpio (node host) and
    `node load-image`. C because Base's File and bend-vmm's V.Fs have no
    openat/renameat (V.Fs.rename follows links in the parent path).
    Evidence: tests/bin_file.sh (CI job check) checks a linked directory,
    a link inside the path, `..`, a two-part name, a link at the name
    (the file it points at stays), and 0700 for made directories.
  - `vk8s snapshot create` dies when the guest does not answer sync
    (paused, stopped, old guest, or sync failed), before it pauses or
    copies anything.
  - `restore_sh` drops `._*` entries from the listing; tar extracts the
    three members by name.
  - fetch-assets.sh downloads, links, re-checks and unpacks in a private
    `mktemp -d` per run; kept images return to bin/ on failure too.
  Not yet covered: the Mac regression (43/0) and smoke after this change
  (user, Mac); no test runs `restore_sh` on a `._` archive. Left as is,
  with the guest stopped when they run: create-time host-kubeconfig and
  vcluster.yaml (fresh directory, no guest has run), and the node host's
  `rm -f share/requests/{request,response}` at boot. Open: the open
  format's `rm -rf share/snapshot/export` runs while the guest runs and
  follows a link planted as share/snapshot (deletes a directory named
  export elsewhere).
- [x] Container backend (pr-49, pr-48 #1): atomic per-host slots and
  Checked off 2026-11-19: merged to main (51bff9a); CI push run 44304191063
  on a296f4f green (container-smoke arm64 and amd64, container-regression 43/0 on both, verdict).
  ownership-checked delete; inter-cluster FORWARD isolation; iptables -w and
  failing delete on errors; container create fetches its role sets.
  Fixed on branch fix/container-slots-isolation, to be checked off with the
  CI run that proves it (container-smoke arm64 and amd64,
  container-regression 43/0, verdict for proofs/ctr.bend and
  proofs/nodehost.bend):
  - Slots: a per-host registry under /run/vk8s/slots. create reserves slot
    k with `mkdir /run/vk8s/slots/k` (fails when held, so two creates
    from one or two homes never share a slot), skips a slot whose bridge
    exists, and writes the cluster's directory to its owner file. delete
    removes the bridge only when the owner file names the cluster, and
    frees the slot last. Laws ctr.slot_registry, ctr.slot_commands,
    ctr.free, ctr.owns.
  - Isolation: Ctr.rules.v2 adds Ctr.isolate: DROP from and to any other
    vk8sbr+ bridge, the bridge's own traffic accepted above them (law
    ctr.isolate). The node host VM uses it too (Nh.rules.v2, laws
    nodehost.rules.v2, nodehost.unrules.v2).
  - iptables -w 30 on every call on a Linux host (Ctr.ipt; laws ctr.ipt,
    ctr.rules.v2, ctr.list_rules, ctr.net_cleanup.v2).
  - delete checks what is left: the nodes' runc state and network
    namespaces, tagged rules in a fresh listing, its bridge, its cgroup
    (20 tries) and the asset mounts. Anything left: it names it, keeps
    cluster.env and the slot, and exits 1 (laws ctr.rules_gone,
    ctr.leftovers, ctr.delete_failed, ctr.unowned_message).
  - create calls sets_ensure for the control plane's sets before its
    asset check, with images when the dir holds it or the pinned release
    pins it (law ctr.want_images).
  - tests/container_smoke.sh: create without the sets stops at the sets
    check; a second cluster from another $HOME is created at the same
    time and takes another slot; each node reaches its own API, the
    other cluster's API times out (dropped) both ways; deleting it frees
    its slot and keeps the first's bridge.
  - Open: the macOS node host still picks its slot from the home's
    cluster.env files (Nh.slot); one node host VM serves one home, so the
    race is between two creates of one user at the same moment.
- [x] Assets (pr-48 #2, #3): pin every guest build input (Alpine kernel,
  busybox, CA bundle, Debian packages via a signed index, images by digest);
  optional sets (images, cache) not mandatory.
- [x] Syncer (pr-40): keep pod references until the host pod is gone
  optional sets (images, cache) not mandatory. Done in #66:
  scripts/guest/pins.sh pins Alpine v3.24 linux-virt-6.18.63-r0 and
  busybox-static-1.37.0-r31 (per arch, SHA-256), cacert-2026-11-05.pem
  (SHA-256, equal to curl.se's .sha256) and the five images by index
  digest (images.sh refuses another digest); scripts/guest/debs.lock pins
  each .deb by SHA-256, written by `debs.py --lock` from trixie's InRelease
  (gpgv: "Good signature" from the 13/trixie keys) and Packages.xz checked
  against it. CI probe runs 44074179213 (the pins) and 44076414678 (lock
  regenerated identically, build from the lock on both arches, the
  snapshot.debian.org fallback, a tampered SHA-256 refused). Optional sets:
  Vk8s.sets_ensure.v2 drops an absent images/cache set with a warning
  (laws assets.optional.*, assets.present.*, assets.missing_*), and the
  cache VM does not boot without cache.img, so create goes on with the
  "pulling from the registries directly" warning. Not pinned: the Ubuntu
  busybox CI's container-smoke passes as BUSYBOX_BIN (a test build, not a
  release), and scripts/dev/rootfs.sh (the dev VM, not the guest).
  2026-11-21: Alpine dropped linux-virt-6.18.63-r0 from v3.24 (only the
  newest build stays), so amd64 guest builds got a 404; the pins moved to
  6.18.64-r0 and kernel.sh to KVER 6.18.64 (aports d65a2d33, same base
  and virt config). Main 0dd6ae0, CI 44848625964: every job green,
  container and kvm regressions included.
- [x] Syncer (pr-40): keep pod references until the host pod is gone
  Checked off 2026-11-19: merged to main (classic.vpod_gone_keys in src/sync/classic.bend); CI push run 44304191063
  on a296f4f green (syncer-envtest, verdict).
  (vcluster mappings store parity); relist queues the old references.
  vcluster 3a0085b6 pkg/mappings/store/store.go keeps a pod's mapping and
  its references while objectExists (the virtual or the host pod is
  found) and dispatches them from removeMapping once neither is
  (store_test.go TestGarbageCollectMappings). The syncer's index now
  tracks, by virtual key, which host pods the host pod store holds: a
  virtual delete (or a relist that drops the pod) keeps the references
  while the host pod is cached, and the host pod's delete (or relist
  drop) releases them and queues the held keys
  (CL.Classic.vpod_gone_keys, hpod_gone_keys, pod_vkeys). A relist
  (OInitApply) queues the old references as an update does
  (pod_event_keys). Evidence: new laws classic.vpod_gone_keys_*,
  hpod_gone_keys_*, pod_vkeys, pod_event_keys_changed/_same (proposed);
  tests/syncer_refs.bend (force delete with a host pod, host delete
  first, recreated pod, both relist drops, relist with changed
  references); CI syncer-envtest "host configmap stays while its host
  pod terminates" and "host configmap leaves once the host pod is gone"
  (a force-deleted virtual pod whose host pod is bound to a node).
- [x] PID 1 and ports (direct F1-F7, F9, F11): refault back-off counts on
  every run; guard against a missing vmstat field; reclaim and compaction
  as background steps off fstrim's tick; a law for the tick length; first
  compaction sooner; reserve the API port before slow steps; probe derived
  ports; random seed fallback.
  Done 2026-11-17 in pure Bend, no new shell. PID 1 decides reclaim and
  compaction with P.Plan.reclaim_turn and P.Plan.compact_turn, keeps their
  state in memory, and hands the kernel writes to a background chore
  worker (host/init.bend Init.mem; File.write on an IO helper thread, so
  the loop never blocks; a chore due while one runs is skipped). Evidence:
  laws plan.reclaim_turn.busy_counts and busy_spike (F1), blind and
  blind_again (F2), reclaim_due and compact_due (F3, off fstrim's tick 0),
  tick_ms and tick_periods (F9), compact_due.first and mem_init (F11:
  first compaction at 5 min, was 20); the node host runs the same
  (nodehost.chores_v2_*). Ports: Vk8s.reserve makes the cluster dir with
  one mkdir and records the port at once, then re-checks for another
  cluster with the same port (F5, also classic before its host Service
  and both restores); every derived port is probed with Bend TCP connect
  and bind, no nc (F6, cli.host_ports.*); a failed IO.random_u32 falls
  back to the clock, spread per try, and says so (F7,
  cli.fallback_seed); laws cli.port_from.range and
  cli.recorded_elsewhere.*. Not changed: the reclaim amount (F4 is
  decision D2) and the old script laws, which stay as written (F8).
- [x] Native P2 (pr-46 #4-#6): kill timed-out boot commands, interrupt
  Checked off 2026-11-19: merged to main (#65, fd37bc0); CI push run 44304191063
  on a296f4f green (native-envtest, native-smoke, verdict).
  boot on SIGTERM, per-cluster KUBECACHEDIR.
  Fix in #65 (feat/native-boot-signals, not merged; check off when
  native-envtest and native-smoke pass on it). #4: NInit.run_cmd kills
  (SIGKILL) and reaps a boot command whose wait ends without an exit
  (N.Native.orphan). #5: Sys.pending (C: Bend has no signal handlers)
  ends the native steps (N.Native.go_on), command waits and TCP/file
  waits; the runner then stops what it started. #6: Sys.setenv (C:
  Bend has no setenv, and kubectl also runs inside the plans' `sh -c`
  strings, so --cache-dir cannot reach every call) sets
  KUBECACHEDIR=DATA/kube-cache (N.Native.cache_dir) before the first
  child. Laws: native.orphan.*, native.go_on.*, native.cache_dir
  (Proposed). Tests: tests/native.bend; native-envtest (SIGTERM while
  kubeadm hangs: exit within 15 s; while the API wait loops: within
  40 s; no process left; daemons' KUBECACHEDIR; no ~/.kube);
  native-smoke (the unit's kube-apiserver has KUBECACHEDIR; kubectl's
  discovery cache is under DATA/kube-cache).
- Process: change pinned behavior with v2 defs, not in-place law edits
  (direct F8).

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

- Pod references (the syncer's ConfigMap and Secret index) are released
  at the event that leaves neither the virtual nor the host pod, not at
  vcluster's next mappings garbage collection (every 3 min:
  pkg/mappings/store/store.go GarbageCollectionInterval). The index lives
  in memory: after a syncer restart, a virtual pod that is already gone
  holds nothing while its host pod still terminates, so its ConfigMaps
  follow the virtual pods only. vcluster keeps its mappings in etcd
  (pkg/setup/controller_context.go: store.NewEtcdBackend; store.go start
  lists them) and holds them across restarts.

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
- The image cache runs on the host since feat/no-cache-vm (`vk8s cache
  serve`, not a VM). What changed for users:
  - `cache status` measures the host store (~/.vk8s/cache/store) every
    time, running or not, and shows its path instead of data.img's
    allocated size; while an old cache VM's data.img is still there, it
    says so.
  - Expiry: a cached blob goes 72 hours after its last use (every pull
    counts), not 7 days after it was cached (distribution's proxy ttl);
    the user's decision of 2026-11-17 ("3 days from last use comes later
    with a Bend registry").
  - `cache prune [REGISTRY]` removes the registries' directories from the
    store (no fstrim, nothing restarts); pruning all of them also
    removes an old cache VM's data.img.
  - `cache stop` ends the host process (and an old cache VM that still
    runs); `cache start` and create stop such a VM first, as it holds
    the ports.
  - Layers that the shared layer store fills come straight from the
    registries and are not kept in the image cache (they were, through
    the cache VM, as a second copy).
  - The mirror answers a Range or HEAD request for content it does not
    hold, and anything over its caps, with 404 or 429, so containerd
    fetches that from the upstream itself (distribution's proxy fetched
    it). TLS to the registries uses the CA roots of the OpenSSL vk8s
    loads (SSL_CERT_FILE overrides them); HTTPS_PROXY is not used (the
    cache VM had none either).
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

## 10. Lightest personal Kubernetes

- [x] Baseline (2026-11-17, main 36ecbb7, Mac, VM mode, the default
  single-node cluster: one VM, 2 vCPUs, 2048 MiB, settled 10 min after
  boot): phys_footprint 1.2 GB, idle host CPU 7.0%. A control plane plus
  one worker (two VMs) measured ~1.8 GB and 8-11%, so the control plane is
  most of the idle cost. bend-vmm's own share is ~0.03% of a core (about
  90 MMIO exits/s per VM at ~3 us each, bend-vmm's numbers), so the cost is
  the guest's Kubernetes processes. In flight: idle tuning
  (tune-idle-components), sleep when idle (add-sleep-when-idle), shared
  image layers (explore-shared-image-layers), feature-gate and sysctl
  passthrough for agent-substrate (add-extraargs-sysctls).
- [x] Idle tuning (tune-idle-components, PR pending measurement). In the
  plan, with laws under `# Proposed:` in laws/plan.bend:
  - kube-controller-manager and kube-scheduler: `--leader-elect=false`
    (upstream: true, 15 s lease, 2 s retry period, so two Lease writes
    every 2 s through the API server into kine). vk8s has one control
    plane.
  - kube-controller-manager: `--controllers=*,bootstrapsigner,tokencleaner,-ttl`.
    No test of the v1.36.0 conformance list names TTL; vcluster turns ttl
    off in its classic sets. Every other default controller stays (the
    conformance list uses it, the cluster needs it, or it does no idle
    work).
  - kubelet (control plane and workers): `--housekeeping-interval=30s`
    (upstream 10 s; dynamic housekeeping backs an unchanged container off
    to 15 s at most, a base above that stays).
  - GOGC=50 and a soft GOMEMLIMIT per Go daemon (apiserver 640 MiB,
    controller manager 256, scheduler 128, kubelet 192, containerd 128,
    kine 128, etcd 256; upstream GOGC=100, no limit). PID 1 starts those
    daemons under `busybox env` (Plan.go_env, Plan.env_prog/env_args), so
    the boot plans keep their programs.
  - Not changed, on purpose: syncFrequency (1m; the conformance tests'
    240 s wait for ConfigMap/Secret volume updates assumes it), the image
    and container GC periods (constants in pkg/kubelet/kubelet.go, 5 min
    and 1 min; Plan.image_gc already sets the age), node status and node
    lease settings, every API group.
  - Open: the Mac measurement against the baseline above (1.2 GB, 7.0%)
    and the CI regression result (43/0) for this change.
  - Mac measurement (2026-11-18, main 9a30847, same method as the
    baseline, --idle-sleep 0, 10 min settled): phys_footprint 1315 MB
    (peak 1805 MB), idle 8.9% of one core over 120 s. That is no better
    than the baseline (1.2 GB, 7.0%); this run had the image cache VM up
    and kube-router (NetworkPolicy, about 57 MiB RSS) added since the
    baseline, so the comparison is not clean. CI regression 43/0 on main
    (container-regression amd64, run 44215573705). Still open: a clean
    A/B of the idle flags on one build; sleep when idle is what removes
    idle cost today.
  - Rerun with the image cache VM off (VK8S_CACHE=off, same build):
    phys_footprint 1214 MB (peak 1967 MB), idle 8.5% of one core. Level
    with the baseline although kube-router now runs beside it; the idle
    flags' own effect needs an A/B with the flags off.
  - A/B (2026-11-18, same build 85c1813, cache VM off, a local guest
    build with Plan.controller_manager_idle, scheduler_idle, kubelet_idle
    and go_envs emptied): flags off phys_footprint 1323 MB (peak 1997 MB),
    idle 8.0% of one core; flags on 1214 MB (peak 1967 MB), 8.5%. The
    flags save about 110 MB (8%) of the VM's footprint; idle CPU is
    within noise (the remaining cost is the components' own loops, which
    sleep when idle removes). CI regression 43/0 on main.
  - Fix (2026-11-17, after CI's assets-disk gVisor role failed with
    "serviceaccount default/default not found" for 600 s): without leader
    election kube-controller-manager waits only 10 s for the API server's
    /healthz (v1.36.0 controllermanager.go CreateControllerContext,
    WaitForAPIServer(versionedClient, 10*time.Second)) and then exits;
    with it, the lease loop retried every 2 s until the API server served
    it. Under qemu TCG /healthz takes longer than 10 s after 6443 opens,
    and that harness has no supervisor, so the controller manager never
    came back. On the Mac PID 1's supervisor restarts it, which hid the
    gap. The plan now waits for /healthz (up to 120 s times
    VK8S_WAIT_SCALE, never failing) in Plan.default_endpoints.v2, the step
    right before kube-controller-manager; leader election stays off and
    the GOGC/GOMEMLIMIT settings stay (the harness does not apply them,
    so they were not the cause). Laws plan.apiserver_healthy*,
    plan.default_endpoints.*, plan.control_plane.healthy; the gVisor
    harness runs the same wait with VK8S_WAIT_SCALE=5.
- [x] Layer blobs discarded once unpacked (interim step of shared image
  layers, 2026-11-17): every node's containerd (VM, container and host
  node, and the standalone join script) sets
  `discard_unpacked_layers = true` in `plugins.'io.containerd.cri.v1.images'`
  (containerd v2.2.3 internal/cri/config/config.go; laws
  plan.containerd_images, plan.containerd_config.images,
  native.extra_containerd_images, join.install.containerd). The transfer
  service does not support the option, so the config also names
  `use_local_image_pull = true`, which containerd 2.1+ sets by itself
  then. A node keeps each pulled layer once (the overlayfs snapshot),
  not also its compressed blob; the expected saving is the images'
  compressed size. Images that ctr imports (pause, the preloaded add-ons,
  node load-image, the join script's pause) drop their blobs too: v2
  import lines with `--local --discard-unpacked-layers` (containerd
  v2.2.3 ctr refuses the flag without --local; laws plan.imports.v2,
  plan.runtime.v2, plan.image_load.v2, plan.request.image_load.v2,
  join.install.pause.v2, join.install.join.v2). scripts/guest/images.sh pulls the blobs again before it exports.
  Open: the measurement (du of the content store,
  /var/lib/vcluster/containerd/io.containerd.content.v1.content, before
  and after a pull of the regression images on a single-node cluster)
  and the regression subset (43/0) need a VM run; the factory sandbox
  cannot boot one.
  - Evidence (2026-11-18, Mac, main 9adf6b3, default single-node VM):
    after pulling nginx:1.27, agnhost:2.56, httpd:2.4.39-4 and busybox:1.36
    (plus the preloaded images), du of /var/lib/vcluster/containerd gave
    io.containerd.content.v1.content 1 MB and
    io.containerd.snapshotter.v1.overlayfs 764 MB: the compressed layer
    blobs are gone once unpacked. Regression subset: CI kvm-regression
    (classic, standalone) and container-regression 43/0 green on main
    (run 44206410798, dec3ba0).
- [x] Shared read-only layer store, part 1 of 2: the host side (branch
  feat/layers-fill; open until the Mac test and part 2, the guest
  snapshotter). The pure core (src/layers/{tar,meta,store,snap}.bend) is
  on main. This part adds:
  - `vk8s layers fill IMAGE` (hidden): the reference is normalized as
    distribution/reference ParseDockerRef, and the manifest (the
    linux/<arch> one of an index), the config and each layer blob come
    from the image cache on 127.0.0.1:15001-15004 over plain HTTP, each
    checked by digest when it has one (src/layers/pull.bend). Blobs land
    in the OCI blob cache at ~/.vk8s/oci (src/oci/store.bend layout,
    OciBlob.fetch, digest and size checked). Each layer is decompressed
    with bend-kube 0.10.0's Unz.file (gzip; zstd needs libzstd, and the
    error names `brew install zstd`), checked against its diffID
    (OciBlob.hash), unpacked by the 64-bit loop of src/layers/fill.bend
    with the LayerFs effects (host/layers/effs/layer_fs.c: range copy,
    entry creation, directory fsync, no-replace rename, recursive
    remove), given its .bend-meta files, fsynced, renamed to
    ~/.vk8s/layers/<hex>, and recorded in ~/.vk8s/layer-refs/<hex>. A
    layer with a record is only touched (its last use).
  - `vk8s layers gc` (hidden): removes the layers Lay.gc.drop says (no
    holder, 72 h since the last use; no readable record counts as
    unused), tmp entries whose name says they are a day old, and expired
    blob cache files (Store.sweep, 72 h).
  - Laws: laws/layers_pull.bend and laws/layers_fill.bend (all
    proposed), with markers. tests/layers_unpack.sh runs the pipeline
    natively in CI on Python tarfile layers and a 5 GiB layer.
  - Not covered: registries the image cache does not serve, and fills
    when the cache does not run (bend-kube's TLS sockets do not set
    OciBlob's TLS hooks, so OciBlob.fetch cannot read an upstream HTTPS
    registry directly). Open: the Mac test (APFS, F_FULLFSYNC,
    renamex_np, libzstd present and absent).
- [x] Shared image layers, part 2: the guest side (branch
  feat/layers-snapshotter-guest; open until a Mac run with
  VK8S_LAYERS=1 and part 1's store shows a pod start on shared layers).
  - Snapshotter: `vk8s-guest snapshotter SOCKET ROOT HELD`
    (host/snapshotter.bend), containerd.services.snapshots.v1.Snapshots
    over gRPC (h2c) on /run/vk8s/snapshotter.sock with bend-kube-runtime
    0.10.0.0's Grpc.serve/reply/send/finish and pb. All ten methods;
    src/layers/snap.bend decides each call, one at a time.
    src/layers/pb.bend maps snapshots.proto (laws/layers_pb.bend: request
    and answer bytes from protobufjs on containerd's api/ protos). A
    Prepare with containerd.io/snapshot.ref for a layer whose
    /mnt/layers/<hex> exists answers AlreadyExists (the unpacker skips
    it); any other layer goes onto the node disk, where containerd's
    differ unpacks it into the overlay mounts, as with overlayfs.
  - State: ROOT/state (src/layers/state.bend, laws/layers_state.bend),
    written through a rename after every call that changes it, so a
    restart or a reboot keeps the snapshots. No state file: a fresh
    state, ROOT/snapshots emptied.
  - Held layers: share/layers.held, "<chain ID> <node>/<snapshot key>"
    per snapshot on a shared layer, rewritten after each acquire or
    release (Spb.held). `vk8s layers gc` reads every node's file under
    ~/.vk8s/clusters (<cluster>/share and <cluster>/nodes/<worker>/share;
    BinFile.read_all, O_NOFOLLOW, 4 MiB at most) and parses it strictly
    (Fill.held.parse: "sha256:" and 64 lowercase hex digits, a space, a
    holder; other lines are ignored). gc never removes a layer that a file
    names (Fill.hold), so a stopped cluster's layers stay until it is
    deleted (security review 2026-11-18 F3).
  - fill and gc: a fill writes the layer's record before the rename that
    publishes it, and takes a layer as present only when its record and
    its directory are both there (Fill.present). Each layer has its own
    lock, ~/.vk8s/layer-locks/<hex> (O_EXCL; a lock an hour old is taken
    over; W4, Lf.fill.v2, Lf.gc.v2): a fill waits while another fill
    holds it, then checks present again with lstat (Fill.present.v2), so
    concurrent fills of one layer publish it once; gc tries the lock of
    each layer it would remove, skips a held one, and under the lock reads
    the record and every node's layers.held again (Fill.gc.recheck.v2),
    so a gc never removes a layer a fill is using (F5) and neither fails
    on the other. ~/.vk8s/layers.lock is no longer taken. An image's
    layers fill in two halves at once (Fill.split.v2, IO.fork). An
    automatic fill can remove each blob it published from ~/.vk8s/oci
    (Fill.blob.drop.v2); `vk8s layers fill` keeps it. Not yet run on a
    Mac or in CI on this branch: tests/layers_unpack.sh has the cases.
  - Unpack limits: the gzip/zstd output is capped at 50 times the
    compressed layer and at 64 GiB (Unz.file's max_mib, Fill.unz.mib),
    and a layer has at most 2,000,000 tar entries (Fill.max_ents); past
    either the fill fails and removes its tmp entries (F6).
  - PID 1: with VK8S_LAYERS=1 on the kernel command line in a VM (not
    container mode, cache or node host; Plan.layers_on), the write of
    containerd's config becomes the layers mount (`mount -t 9p -o
    trans=virtio,version=9p2000.L,msize=524288 layers
    /mnt/layers`), the snapshotter daemon and a wait for its socket,
    then the config with `snapshotter = "bend"` and proxy_plugins."bend"
    (Plan.with_layers). PID 1 sets CONTAINERD_SNAPSHOTTER=bend, so ctr's
    imports unpack for it. Without the flag the plan is unchanged.
  - Host: with VK8S_LAYERS=1, cluster and worker VMs get `--share
    ~/.vk8s/layers,tag=layers,meta,ro` and VK8S_LAYERS=1 on --cmdline
    (Cli.with_layers in Vk8s.role_flags); the cache VM never does.
  - Layout: part 1 (PR #77) publishes each layer at
    ~/.vk8s/layers/<hex>, so a node's lowerdir is /mnt/layers/<hex>
    (Lay.mount), with no /fs suffix.
  - bend-kube: the guest program links bend-kube-runtime 0.10.0.0 only
    (syncer, join server, snapshotter); 0.2.0.0's json and http stay.
  - Open: List ignores filters. Not built or run in the
    factory sandbox (no bend there): typing, proofs, the gate and a VM
    run are the owner's.
  - Mac evidence (2026-11-18, merged locally with compile fixes, bend-vmm
    0x79c2f532): `vk8s layers fill` busybox:1.36 (1 layer, <1 s) and
    nginx:1.27 (7 layers, 5 s, about 200 MB). With VK8S_LAYERS=1, a
    2-worker cluster runs a 3-replica nginx Deployment from the shared
    store: each pod's overlay lowerdir is /mnt/layers/<hex>, and exec works.
    Without VK8S_LAYERS, nothing changes (a pod runs, as before).
  - Fixed on the way: the host shared ~/layers, not ~/.vk8s/layers; the
    two bend-kube versions; bend-vmm's exponential Meta.pct (fixed in
    0x79c2f532); cache=loose made v9fs keep a fid per cached dentry and
    hit bend-vmm's 4096-fid cap (EMFILE), so the share mounts with the
    default cache now.
  - Open: images that are not in the store (the fallback path) pull very
    slowly or stall. coredns/coredns:1.14.2 had not finished after 5 min,
    the control-plane guest sat at about 100% vCPU, and new pods on the
    busy node stayed in ContainerCreating. The snapshotter serves one
    call at a time; each call saves state and spawns busybox. Next: time
    each call in snapshotter.log, find the hot call. Until then, the store
    stays opt-in (VK8S_LAYERS=1).
  - Fixed (PR #78, 2026-11-18): Sn.without, Sn.cleanup.go and
    Sn.relabel.go recursed in both arguments of Bool.pick, so Commit,
    Remove and Cleanup were exponential in the node's snapshots. Mac,
    VK8S_LAYERS=1, 2 workers: the three VMs idle at 12.4%, 0.6%, 3.2%;
    nginx 3/3 from the store and the Service answers by name (coredns,
    pulled through the fallback, serves DNS). snapshotter.log timings:
    1288 Stat, 46 Prepare, 29 Commit, 21 Mounts, 7 List all under 25 ms;
    Usage of a shared layer runs du over 9p (10 calls, up to 8.2 s, 16 s
    in all), the one slow call left. The store stays opt-in until
    measured against lima (GOAL section 10).
  - Suspect found in the code (branch fix/snapshotter-hot-calls, not yet
    measured): Bool.pick evaluates both arguments, and Sn.without
    (Commit, Remove), Sn.cleanup.go (Cleanup) and Sn.relabel.go (Update)
    recursed in both, so each such call cost 2^n in the node's snapshots.
    The unpacker commits once per layer, so a node with 30 or more
    snapshots spun its one call loop at 100% vCPU. They recurse once
    now (tests/layers_snap.bend: Remove, Cleanup and Update among 40).
    snapshotter.log now has one line per call (`call <method> key=..
    ms=.. snaps=..`), per busybox spawn, per state render and per file
    write. Next: the Mac run with coredns/coredns:1.14.2 from outside
    the store, and the log's slowest calls.
  - No slow snapshotter call (branch feat/layers-usage-list, 2026-11-18,
    not yet measured on the Mac): a fill records what it unpacked (bytes
    of regular files, inodes as fs.DiskUsage counts them) in a layer
    record of version 2 (Fill.rec.render.v2/parse.v2; version 1 still
    parses, size unknown) and publishes a copy beside the layer,
    ~/.vk8s/layers/<hex>.rec, which nodes read as /mnt/layers/<hex>.rec.
    Usage of a shared layer answers that (Sn.apply.v2, RUsage); only a
    layer an older vk8s filled is still measured with du. List applies
    ListSnapshots filters as containerd does (src/layers/filters.bend,
    laws/layers_filters.bend; checkWalk's cases in laws/layers_snap.bend);
    a "~=" with regular expression operators is refused (no RE2 in Bend).
    Next: snapshotter.log on the Mac shows Usage under 25 ms.
- [x] Sleep when idle (branch feat/sleep-when-idle; open until CI's
  container-smoke runs tests/idle_sleep_smoke.sh green on both arches and
  a Mac smoke covers VM mode). Design:
  - Setting: `vk8s create --idle-sleep D`, else VK8S_IDLE_SLEEP, else 15
    minutes; D is minutes ("15") or whole h/m/s in Go duration form
    ("90s", "1h30m"); 0 turns it off. Recorded as IDLE_SLEEP=<s>s in
    cluster.env. src/cli/idle.bend, laws/idle.bend (all proposed; the
    concrete durations are cases of Go's time_test.go, which vcluster's
    sleep.auto.afterInactivity follows), proofs/idle.bend, laws/done/idle.
  - The API forward: `vk8s idle-proxy` (host/idle_proxy.bend, Bend TCP
    effects and TlsSrv.splice, no shell) holds 127.0.0.1:PORT. A VM
    forwards 6443 to 127.0.0.1:22000+PORT%3000 instead (Idle.inner_port).
    A local container cluster gets a loopback port, and its kubeconfig
    names it (workers still join through the bridge). Traffic is a
    connection: an open connection (a watch, exec, port-forward) keeps
    the cluster awake; after the limit with none, the proxy runs
    `vk8s pause NAME`; the next connection waits while `vk8s resume NAME`
    runs, then is relayed. The idle clock is the monotonic IO clock; a
    clock that goes back restarts the count (law idle.clock_back).
  - No eviction: `vk8s pause` (manual or idle) first asks the control
    plane's PID 1 for idle-sleep (SIGSTOP kube-controller-manager);
    `vk8s resume` then asks for idle-wake (containers) or idle-wake-clock
    (VMs: hwclock -s first, since the guest clock stops while paused on
    macOS), which kills the stopped kube-controller-manager; the
    supervisor starts a fresh one 5 s later, whose node lifecycle
    controller starts every node's grace period at wake, after the kubelet
    renewed its lease. laws plan.request.idle_*.
  - Wake v2 (2026-11-17, after CI's container-smoke failed "after the
    wake: no eviction"): PID 1 runs Plan.request_mode.v2. On idle-wake and
    idle-wake-clock it first waits until every Lease in kube-node-lease
    has a renewTime at or after the wake (up to 20 s times
    VK8S_WAIT_SCALE; a VM sets its clock first), then kills the stopped
    kube-controller-manager, so the supervisor starts the new one only
    against fresh leases. Laws plan.node_leases_renewed*,
    plan.request.*.v2, plan.request_mode.v2.*. The failing run slept only
    about 2 s, too short for a lease to go stale, and the smoke checked
    every event since the boot: it now fails only on an eviction event
    that was not there before the first sleep, prints the events that
    match, and prints its diagnostics before the delete on any FAIL.
    Open: which event matched in that run (the next container-smoke run
    prints it).
    The host sends idle-wake and does not wait for its answer
    (Vk8s.idle.wake): the lease wait takes up to one 10 s renew period,
    and kubectl gave up on its TLS handshake while the idle proxy held
    its connection ("kubectl answers through the sleeping cluster's
    forward"). A resume of a container that was not paused sends none.
  - Off in scripts/regression.sh, soak.sh and conformance.sh (which
    refuses a cluster whose IDLE_SLEEP is not 0).
  - Not covered: node-host container clusters (macOS container mode; its
    forward is the node host VM's) and native clusters (systemd units on
    the host, no pause machinery) never sleep; they record no IDLE_SLEEP.
    A cluster paused by hand keeps its connections waiting, as before.
  - Evidence (2026-11-18): CI run 44215573705 on main (79cc1c1):
    tests/idle_sleep_smoke.sh 35 PASS, 0 FAIL on both container-smoke
    arches (pause through the cgroup freezer, wake through the proxy).
    Mac, VM mode (main dec3ba0 and earlier): a cluster with --idle-sleep
    60s showed `paused` in `vk8s list`, then `running` after kubectl,
    with its pod still Running and 0 evictions; container mode the same.
- [x] bend-vmm LAN offload (branch feat/lan-wire-guard; open until CI's
  lan-throughput job records its numbers here). host/vk8s.bend pins
  bend-vmm 0x2740e30df705f4fb9b9db637023eca00 (6951844: checksum and TSO
  offload both ways on the LAN, MTU 2022; bend-vmm measured VM-to-VM TCP
  55.7 -> 91.1 MB/s) instead of 0x7fea7bfa (90a4b77, MTU 2034).
  - Measurement: CI job lan-throughput (amd64, real KVM) runs
    scripts/lan-throughput.sh on kvm-smoke's binary ("after") and on the
    same tree built with the previous pin ("before"): a control plane
    and one worker, an iperf3 server on the control plane, 3 clients of
    15 s each on the worker, pod to pod (flannel host-gw) and node to
    node (hostNetwork). The table is in the job summary and the
    lan-throughput-amd64 artifact. Before: pending. After: pending.
  - The LAN wire guard (src/cli/lan_wire.bend, laws/lan_wire.bend, all
    proposed; laws/done/lan_wire): every VM on one LAN must run the same
    bend-vmm wire format. cluster.env records LAN_WIRE (2 for this pin; a
    file without it is version 1). create, create --upgrade and restore
    start every VM on this binary and write LAN_WIRE=2 (--upgrade prints
    the change). node add, certs rotate-ca and `vk8s vmm` (which a guest
    reset runs again) refuse another version and name both ways out:
    recreate the cluster, or `vk8s create NAME --upgrade`. pause and
    resume start no VM process (the control socket's pause and resume),
    so they need no check. scripts/lan-throughput.sh checks the refusal
    end to end on a cluster whose LAN_WIRE line is gone.
  - Evidence (2026-11-18): CI run 44215573705, job lan-throughput
    (amd64, KVM, 2 VM nodes): before (bend-vmm 0x7fea7bfa, no offload)
    pod-to-pod 51.3/51.1/52.0 MB/s, node-to-node 51.8/51.0/51.7 MB/s;
    after (0x2740e30d) pod 110/123/136 MB/s, node 115/114/116 MB/s, about
    2.3x. The wire guard refused node add on a version 1 cluster.
- [x] Shared image layers on by default (GOAL section 10, added
  2026-11-18): auto-fill on pull, cheap Usage and filtered List, store
  on vs off measured better (disk, memory, time to a running pod, idle
  CPU), regression 43/0 and a certified run with the store on, a soak,
  then VK8S_LAYERS=0 as the opt-out. Done 2026-11-20 (5ceac2c): VM
  nodes get the store unless VK8S_LAYERS=0 (Cli.layers_on.v2,
  Srv.spawn.v3, laws cli.layers_on.v2.*, layers_serve.spawn_v3_*);
  `vk8s create --help` and README.md say so; CI run 44710443105 green
  (regression standalone off/on, classic, native, container amd64 and
  arm64). Container and native nodes keep the per-node unpack. The
  savings reach users with the next guest asset release (the pinned
  v1.36.6-f3265aa9 has no snapshotter and ignores the store); its
  release notes must say the store is on and how to turn it off.
  - The filler daemon (W5 of docs/ref/explore-layers-autofill.md, branch
    feat/layers-serve): `vk8s layers serve` (host/layers/serve.bend)
    listens on 127.0.0.1:32000 (Ask.port.v2), reads one ask a
    connection (Ask.parse.v2), and fills the asked image by its manifest
    digest through the v2 fill; it answers "ok present", "ok published"
    or "no <reason>". Caps and dedupe are pure (src/layers/serve.bend,
    laws/layers_serve.bend, laws/done/layers_serve): 4 image fills, 64
    waiting asks and 128 connections at once; asks for an image a fill
    runs for wait for that fill. `vk8s create` starts it with
    VK8S_LAYERS=1 unless the port is taken (log ~/.vk8s/layers-serve.log).
    tests/layers_serve.sh covers it on Linux CI with a stub registry.
  - The guest's ask (W6, 0a5301d): with VK8S_LAYERS=1 containerd sends
    the snapshot annotations (disable_snapshot_annotations = false), and
    the node's snapshotter asks the filler for a missing layer before it
    unpacks it locally.
  - Mac evidence for W5 + W6 (2026-11-19, 0a4bc57, local guest build): a
    VM cluster with 2 workers and VK8S_LAYERS=1 came up in 26 s. The
    nodes asked the filler for kube-proxy, flannel and coredns layers,
    and all 10 system pods ran (coredns stalled for more than 5 min on
    2026-11-18). A redis:7.4-alpine Deployment, not in the store before,
    rolled out 3 replicas in 22 s: the three nodes asked for the same
    layer, and the filler fetched it once and answered "ok published"
    to each. The pod's root overlay has only /mnt/layers/<hex> lowerdirs,
    and redis-cli ping answers. No ask got a "no"; the store went to 78
    layers, 512 MB. Next: the cold-pull bench (W7), then
    regression, certified and soak runs with the store on.
  - Cold-pull bench (W7, scripts/bench/cold-pull.sh, 2026-11-19, Apple
    M2 Pro, 32 GiB, macOS 27.2.1, binary 0a4bc57, 3 VM nodes, pinned
    busybox, nginx and redis Deployments of 3 replicas, on/off pairs in
    alternating order, noise margin 10% declared in the script). Median
    of paired on/off (below 1 means the store is better):

    | state | ready | busybox | nginx | redis | VMM footprint | cluster disk |
    |---|---|---|---|---|---|---|
    | 3: all cold, 5 pairs | 0.99 | 0.78 | 0.66 | 1.17 | 0.55 | 0.05 |
    | 4: cache warm, store cold, 4 pairs | 1.08 | 1.37 | 1.47 | 1.10 | 0.53 | 0.05 |

    Footprint medians: 2818 vs 5156 MiB (state 3); cluster dirs 71 vs
    1535 MiB, plus a 511 MiB shared store. Redis in state 3 is noisy
    (paired ratios 0.42 to 3.13). Gate not met: in state 4 the host fill
    is slower than each node's own unpack. Suspect: LayerFs.fsync_dir
    uses F_FULLFSYNC (host/layers/effs/layer_fs.c:415) for every
    directory of a layer; one F_FULLFSYNC before the publishing rename
    keeps the same crash guarantee. Next: per-phase fill times to
    confirm, the fix, and a rerun. The default stays opt-in.
  - One squashfs image per layer (docs/ref/layers-sqfs.md, 2026-11-19,
    feat/layers-sqfs). Why: the directory store made a host file per
    tar entry (plus a .bend-meta per directory, and as many deletes at
    gc); on this Mac the endpoint security agent records every create,
    rename and delete, and a cold-pull bench that wiped and refilled the
    store hung the Mac twice. Now a fill writes `<hex>.sqfs` through one
    open file (src/layers/sqfs.bend: a pure squashfs 4.0 writer, 30
    laws whose expected bytes come from squashfs-tools 4.7.5 and
    squashfs_fs.h), and a node loop-mounts it at /mnt/layers/<hex>
    (plan v4: the share at /mnt/layers-store, a tmpfs at /mnt/layers).
    Evidence, CI run 44569074785: kvm-regression (standalone, 1) with
    VK8S_LAYERS=1 Passed 43, 0 failed, in 16.1 min (30.8 min with the
    directory store); 85 layer images and 255 host files under
    layers, layer-refs and tmp (3 a layer: the image and two records);
    every lowerdir of the probe pod's root is /mnt/layers/<hex>; 16 asks
    ok published, 145 ok present, 0 no. tests/layers_sqfs.sh: the kernel
    mounts the images (contents, hard links, owners, devices,
    security.capability), overlayfs applies their whiteouts and opaque
    directories, and alpine 3.20's layer (517 tar entries, 96
    directories: 613 host files in the directory store) is one image
    whose files match tar's. Next: the user's one-fill fs_usage check
    on the Mac, then the cold-pull bench with fewer runs and no full
    wipes.
  - Endpoint-security check on the Mac (2026-11-19, the user ran
    `sudo fs_usage -w -f filesys sentineld` during one
    `vk8s layers fill docker.io/library/nginx:1.27`, 7 layers, 2.8 s,
    binary f3bbf16): the agent logged 233 operations on ~/.vk8s paths in
    all, about 33 a layer (tmp 79, oci 70, layers 28, cache 28,
    layer-refs 14, layer-locks 14; statfs64 126, WrData 107). Without
    oci (a manual fill keeps its blobs for 72 h; an automatic fill drops
    them) and cache (the image cache VM's own disk), about 19 a layer.
    The same capture of the directory store saw 3,475 operations in
    ~/.vk8s/tmp alone in 10 s. The fill left 2 files a layer in layers
    and one in layer-refs; tmp was empty.
  - Cold-pull bench on squashfs images (2026-11-19, binary bd48287 =
    main with the layer images, arm64 guest assets from CI run
    44606147328, scripts/bench/cold-pull.sh under scripts/bench/guard.sh
    (never tripped), 3 pairs a state as the user approved; the plan's
    5 pairs not run). Median of paired on/off:

    | state | ready | busybox | nginx | redis | VMM footprint | cluster disk |
    |---|---|---|---|---|---|---|
    | 3: all cold | 0.96 | 1.00 | 0.40 | 1.07 | 0.72 | 0.04 |
    | 4: cache warm, store cold | 0.98 | 1.10 | 0.77 | 0.68 | 0.58 | 0.05 |

    Every image is within the 10% cold-pull gate (busybox in state 4 at
    1.10: a 2 s pull, ratios 1.45/1.10/0.81). The directory store's
    state 4 was 1.37 to 1.47. A Mac smoke first: 2 workers, redis from
    the images, lowerdirs /mnt/layers/<hex>, redis-cli ping answers.
  - Certified run with the store on: PASS, 450 passed, 0 failed, 7136
    skipped, 111 minutes (st, 2 workers, etcd, VK8S_LAYERS=1, guest
    assets from CI run 44606147328, main bd48287, 2026-11-20 06:17;
    archive 202611200617_sonobuoy_2f704f6d). The store held 127 layer
    images (one .sqfs file each, no layer directories) after the run.
    It ran under scripts/bench/guard.sh with the host DNS probe: 226
    lookups, the slowest 105 ms, load at most 7, memory free at least
    74%; the guard never tripped.
    An earlier attempt (2026-11-19 22:47) lost its API connection at
    23:52:43 when the Mac's DNS daemon (mDNSResponder) froze; networking
    timed out for the rest of the night and the shutdown on 2026-11-20
    07:23 ended in a watchdog panic. The 2026-11-19 16:49 panic had the
    same start, after the corporate VPN reloaded its DNS proxy. vk8s
    and bend-vmm never call mDNSResponder (guest DNS is UDP to the
    host's resolv.conf server); suspect: host network filters (VPN DNS
    proxy, endpoint security network monitor). Long Mac runs go under
    the guard, which stops the run and deletes its clusters when a
    lookup takes over 5 s three checks in a row.
  - Soak with the store on: SOAK OK (scripts/soak.sh 10 60,
    VK8S_LAYERS=1, guest assets from CI run 44606147328, main bd48287,
    2026-11-20). 10 create/delete cycles of a 1-worker cluster (create
    to a running pod 30-36 s, delete 15-18 s), then 60 minutes of
    workload with pause/resume: 174 rounds, web ready 4/4, 0 apiserver
    restarts. Leaks: 0 VMM processes, 0 sockets, image cache +1 MiB.
    Under the guard: slowest DNS lookup 58 ms, never tripped.
  - A store left by an older vk8s: a layer directory from the
    directory store still counts as present (Fill.present.v3, law
    layers_fill.present_v3_old_dir) and a node bind-mounts it
    (Snapd.ensure); guest assets older than the store (the pinned
    v1.36.6-f3265aa9) have no snapshotter and unpack per node, so the
    store on with them changes nothing on the node.
  - Flakes seen on the way (2026-11-19), each green on a rerun:
    container-regression's coredns not Ready in time (amd64 on a
    docs-only branch, arm64 on main 44589708760; container mode never
    uses the store), syncer-envtest's "second host API ready" failover
    case (twice), and oci-blob-macos's 15-minute job timeout. Open.
  - Regression with the store on (GOAL gate): CI job kvm-regression
    (standalone, 1), VK8S_LAYERS=1, VM mode, amd64 KVM:
    scripts/regression.sh Passed 43, 0 failed (30.8 min; run
    44531835946 on 3480dc6; the store check passed on 7f672b4, run
    44540073924). The store filled itself with 85 layers and no
    `vk8s layers fill`; 16 asks were answered "ok published" and none
    "no"; pods ran on /mnt/layers lowerdirs (tests/layers_store_ci.sh).
    The filler logs each image's fill time (for example coredns, 13
    layers in 6.1 s).
  - Security review F3 and F5 (gc keeps held layers; record before
    publish) are fixed in 6694748. The per-layer locks of W2 and W4
    replace that fix's store-wide ~/.vk8s/layers.lock.
  - Docs (W8): README "Shared layer store" describes the automatic
    fill; docs/ref/review-security-boundary-delta.md marks F3 and F5
    fixed; GOAL says the fallback fills only what the cache can read.
- [x] Measure against lima (GOAL section 10): idle CPU, memory, disk,
  create time and time to a running pod, vk8s against k3s in lima and in
  Apple's container runtime on the same Mac (the incumbent cluster and
  its workload are not on this Mac). Done 2026-11-25:
  docs/ref/bench-round1.md, three passes of five configurations on
  release v1.36.6-92057045 (out/bench/lightest-final.csv).
  - Medians: vk8s idles at 1189 MiB (k3s in Apple's container runtime
    1476, tuned k3s in lima 2100, lima's default k3s 3119), adds 367 MiB
    of disk for an idle cluster over 276 MiB installed (lima: 1154 over
    3845), and is first to working DNS (33.2 s; 34.8, 61.9, 38.4). The
    claim this supports: lowest memory and disk measured among these
    configurations on this Mac. Not measured: several nodes, hours of
    churn, the incumbent's workload.
  - Where vk8s trailed k3s, each explained in bench-round1.md with the
    measurements: idle CPU (10.1% of a core against 6.7% for the tuned
    k3s; the upstream control-plane processes, about one API request a
    second, nothing of ours busy), create to node Ready (26.7 s against
    21.9 s for lima's default k3s; the node waits for the flannel pod,
    which k3s runs in-process), the first nginx pod (8.6 s against 7.5
    s; the Docker Hub download, which varies more than the gap), the
    same pod again (0.9 s against 0.4 s; the stock kubelet before the
    sandbox), delete (below), and what a VM-mode delete leaves (the
    image cache and layer filler, 60 MiB and 596 MiB, shared by every
    cluster; by design).
  - Fixed: a container-mode delete took 4.8 s, because the last
    cluster's delete asked the node host to take its containers down
    (one second of grace, and a poll each way) and then stopped the VM
    (the grace again). The last cluster's delete now stops the VM
    directly (Nh.down_first, Nh.down_late; laws nodehost.others,
    nodehost.down_first, nodehost.down_late). Measured on the new
    binary: 2.2 s for the last cluster, 4.5 s with another cluster
    still there (its containers kept running). Released in
    v1.36.6-229e3489 and v1.36.6-37a70144 (2026-11-27).
  - Possible later, not done: flannel as a node daemon beside
    kube-router instead of a DaemonSet (about 6 s off create to node
    Ready, and one less image to pull). It changes how worker nodes get
    their network, so it wants its own regression and conformance run.
  - Decided 2026-11-24: the incumbent cluster is not on this Mac, so the
    comparison is against k3s in lima (and in Apple's container), latest
    versions, three passes (scripts/bench/lightest.sh); a pilot ran first.
  - From the pilot, where vk8s trailed, measured on the released build
    (2026-11-25, one fresh cluster, out/slot):
    - Idle CPU (pilot 5.2% of a core against 4.5% for the tuned k3s, one
      clean pass each). In the guest over 180 s, per cent of one core:
      kube-apiserver 1.72, kine 1.38, kubelet 0.95,
      kube-controller-manager 0.81, containerd 0.44, vk8s's own PID 1
      and guest daemon 0.36, CoreDNS 0.18, flannel 0.12, scheduler 0.11.
      So the cost is Kubernetes' own components; k3s runs the same ones
      in one process with kine inside. Whether the gap is real waits for
      three clean passes.
    - The same image again (pilot 1.2-1.7 s against 0.6 s, both from a
      0.5 s poll). Timed by a watch: 1.27, 0.62, 0.94, 0.64, 1.25 s. In
      a fast and a slow run containerd took the same: 150 ms for the
      sandbox, 25 ms to start the container. What varies is the stock
      kubelet before RunPodSandbox (0.22 s and 0.76 s after
      VerifyControllerAttachedVolume). lightest.sh now times five
      repeats by a watch and reports the median, for every tool.
    - Delete: explained under "delete in about 2 s" below.
- [x] NetworkPolicy enforcement (option A of explore-netpol-cni, chosen by
  the user 2026-11-17): kube-router v2.12.0's network policy controller
  alone, beside flannel and kube-proxy, as k3s embeds it
  (src/guest/netpol.bend, laws/netpol.bend, laws/done/netpol).
  - Asset: the release binary per arch, SHA-256 pinned from its
    checksums.txt (scripts/guest/fetch-assets.sh), in the node set
    (scripts/guest/sets.txt): 104 MB unpacked, about 41-45 MB compressed
    per arch, the largest single addition to the node set since section
    9. The guest gets Debian's ipset (scripts/guest/debs.txt) and the
    modules ip_set, ip_set_hash_ip, ip_set_hash_net, xt_NFLOG,
    nfnetlink_log and xt_limit, and nft_log and nft_limit, which
    iptables-nft uses for -j NFLOG and -m limit
    (scripts/guest/modules.txt); container mode on Linux and native mode
    load them on the host.
  - Lifecycle: a node asset that each node's PID 1 starts right after the
    kubelet and supervises (not a DaemonSet), with the kubelet's own
    kubeconfig and node name; flags --run-firewall=true --run-router=false
    --run-service-proxy=false --run-loadbalancer=false --enable-cni=false
    --use-nftables-for-netpol=false --netpol-default-deny=true
    --health-port=0. A control plane grants the group system:nodes
    get/list/watch on what the controller watches (ClusterRole
    vk8s:network-policy). Certificate rotation restarts it with the
    kubelet. The same in a VM, in node containers (Linux and the macOS
    node host) and on a native host node; native delete removes the
    gate's rules and kube-router's ipsets.
  - Startup protection: before the kubelet starts, PID 1 drops pod
    traffic (mangle FORWARD and INPUT, from or to the pod CIDR, chain
    VK8S-NETPOL-GATE); it empties the chain once kube-router's first full
    sync has put the jump to KUBE-NWPLCY-TAIL in KUBE-ROUTER-FORWARD.
    --netpol-default-deny then covers each new pod.
  - IPv4 only (docs/ref/review-security-boundary-delta.md F2, D2 A).
    kube-router runs without --enable-ipv6 and the gate is iptables
    only. So VM and container nodes turn IPv6 off after the share's
    mount when the kernel has it (P.Plan.with_ipv6_off): all and
    default disable_ipv6=1 in the node's own network namespace, and
    ip6tables FORWARD policy DROP, which stops bridged pod-to-pod
    IPv6 over fe80:: (pods' own namespaces keep the kernel's IPv6
    defaults). tests/netpol_e2e.sh checks the fe80:: path under
    deny-all. Native host nodes are not covered: vk8s does not change
    a host's sysctls or its ip6tables policy, so pods on a native host
    node can still reach each other over fe80:: on the cni0 bridge,
    past every NetworkPolicy, unless the host drops it, for example
    `ip6tables -I FORWARD -i cni0 -j DROP` (with br_netfilter's
    bridge-nf-call-ip6tables=1). Status: pending CI.
  - Native restarts (F8, D8 A): after the node's reset and before the
    gate closes, the native boot (NP.Netpol.native_boot.v2) deletes
    every jump to VK8S-NETPOL-GATE from mangle FORWARD and INPUT and
    empties every KUBE-ROUTER-* chain of the filter table, so PID 1
    cannot open the gate on an old kube-router's rules and the jumps
    do not pile up. Status: pending CI.
  - CI evidence (main 1a69b20, run 44253533109, all jobs green):
    container-smoke amd64 and arm64 and kvm-smoke amd64 ran
    tests/netpol_e2e.sh with no FAIL line; container-regression amd64
    and arm64, kvm-regression and native-regression passed. kube-router
    idle on the worker (60 s): container amd64 58.7 MiB RSS / 0.02% of a
    core, arm64 57.0 MiB / 0.02%, KVM VM 19.3 MiB / 0.13%.
  - Was pending CI: tests/netpol_e2e.sh (a deny-all ingress policy
    makes a pod unreachable, an allow policy restores it) in the
    container smoke and the KVM smoke; the same script prints kube-router's
    idle RSS and CPU on the worker (MEASURE lines in those jobs' logs and
    summaries), to be added here against the baseline above; the
    regression subset must stay 43/0.
  - Mac evidence (VM mode, 3 nodes, 2026-11-18, branch merged at the
    debs.lock ipset pin): tests/netpol_e2e.sh np-worker-1 np, 26 PASS,
    0 FAIL. Deny-all blocks all four paths (cross-node pod IP, Service,
    same node, unnamed client) and keeps them blocked for 20 s; the allow
    policy reopens client and local and keeps other blocked. The probe's
    netfilter checks first failed because it tested /host/usr/sbin/iptables,
    a symlink with an absolute target, in its own root; it now tests in
    the node's root (chroot /host test -x). The finding below no longer
    reproduces; the build that showed it lacked the ipset pin.
  - Was open (Mac, VM mode, 2 nodes, 2026-11-17): with kube-router running
    on the control plane, a deny-all ingress policy on nginx (worker-1)
    did not block a busybox pod on the control plane that fetched
    http://web, after 15 s. Cause not found yet. From kube-router
    v2.12.0's code (pod.go, npc_iptables.go), a synced kube-router on
    worker-1 must reject that traffic in KUBE-ROUTER-FORWARD. Also, the
    startup gate drops all pod traffic on worker-1 until kube-router there
    has synced. So the next run must look at worker-1 itself.
    tests/netpol_e2e.sh now does this. It checks four paths: pod IP and
    Service across the nodes, the same node, and a pod that the allow
    policy does not name. A privileged probe pod on each node checks
    that kube-router runs, that FORWARD jumps to KUBE-ROUTER-FORWARD
    before any ACCEPT, that the server's IP has its KUBE-POD-FW jump and
    is in kube-router-local-pods, and that the gate is open. On any FAIL,
    the probe prints each node's FORWARD counters, kube-router's chains,
    the gate, the ipsets and the kube-router log.
  - scripts/guest/build.sh now stops when out/assets lacks a pinned
    binary of sets.txt (only the images set is optional). Before this

## 11. Smaller and purer

GOAL section 11 (added 2026-11-20). bend-vmm items wait for the bend-vmm
session's notice.

- [x] gc never removes a layer being mounted (79e8176, merged ec8970d):
  `vk8s layers serve` refreshes the record's last use of a layer at
  least a day old (Fill.touch.due.v3, Fill.rec.at.v3) under the layer's
  lock, the lock gc rechecks under, and asks present again there
  (Ls.present.v3); gc removes only at 72 h, so a layer it answers for
  has 48 h or more left. A layer used in the last day costs no host
  write. Laws layers_fill.touch_*_v3, rec_at_v3*, rec_due_v3_*;
  tests/layers_serve.sh: a fresh layer not written again, a day-old one
  refreshed with the rest of its record kept, no lock left. CI run
  44700685486 green (kvm-regression standalone/0 green on a rerun:
  flannel restarts, coredns not Ready, the open flake).
- [x] One read per layer (e63260f, 2026-11-24). bend-kube-runtime
  0.11.0.0 (published with the user's OK) has Unz.file_sha256, which
  returns the SHA-256 of the bytes it writes from the same pass; every
  import is on it (84 files; laws and proofs differ in import lines
  only). The filler and the unpacker take a compressed layer's diffID
  from that pass (Lu.diff.have, Fill.diff.check, Fill.diff.once; laws
  layers_fill.diff_check_*, the general diff_check_refuses,
  diff_once_*, layers_serve.diff_line_*): each layer logs "diffID
  checked in 0 ms: hashed while decompressing, no second read of the
  tar". An uncompressed layer keeps its own hash: the filler does not
  hash again a blob it finds in its blob cache, so that read is the
  only check of the bytes on disk. A layer whose bytes are not its
  diffID is refused and nothing is left (tests/layers_serve.sh,
  tests/layers_unpack.sh: gzip, zstd, uncompressed). The hash is C
  inside the decompress effect, with the ARMv8 SHA-2 instructions
  (about 3.3 GB/s): src/lib/sha256.bend, the pure Bend one, hashed
  4 MiB in 92 s on ten cores (about 45 KB/s; 2026-11-24), so it stays
  for names. Mac, 3 cold nginx fills each: decompress summed over the
  layers 321 to 269 ms (the fetch is most of a fill: wall 5.3 to
  5.0 s). 0.11.0.0's TLS also refuses a context that cannot require
  TLS 1.2 or refuse renegotiation, and tries a failed OpenSSL load
  again. CI 45449310411: every job. The guest binary changes, so it
  reaches users with the next asset release.
- [x] Compressed arm64 kernel: scripts/guest/alpine-kernel.sh keeps
  Alpine's EFI zboot vmlinuz-virt as DIR/Image (10.4 MB, was 36.4 MB raw;
  it checks the payload inflates to an arm64 Image). CI run 44719395414:
  assets-disk boots every role under qemu with it, dev-vm, kvm-smoke and
  kernel16k green (syncer-load-envtest green on a rerun: 10.9 s vs 10 s,
  no VM). Mac (bend-vmm 0x9f122a1b): a 2-node cluster on the sqfs-arm64
  assets with only Image swapped came up in 16 s, both nodes on
  6.18.63-0-virt, nginx Ready. Reaches users with the next asset release.
- [x] No image-cache VM (factory, merged 6353b6d; open until the Mac
  gates: cold-pull bench within 10%, the 43/0 subset, a certified run,
  which need the owner's OK). Mac smoke (2026-11-21): cache start stops
  the old cache VM and starts the host cache; a cold nginx pull through
  it Runs in 53 s and fills docker.io/registry.k8s.io/ghcr.io (104 MiB);
  stop leaves no process.
  - Gate 1, cold-pull bench (2026-11-21, user-approved, 3 pairs a
    state, scripts/bench/cold-pull.sh under scripts/bench/guard.sh, guest
    assets built on the Mac from main 40d7dde, binary 40d7dde). Median of
    paired store on/off: state 3 (all cold) ready 1.05, busybox 1.13,
    nginx 1.15, redis 1.17; state 4 (cache warm, store cold) 1.34, 2.20,
    2.20, 2.07: the filler fetched every layer from the registry while
    the nodes without the store read the warm cache. Fix 81c5031: the
    filler uses a blob the host cache's store holds, in place. State 4
    after it: 1.09, 1.54, 1.09, 1.08 (busybox about 1.3 s slower on a
    2 s pull). VMM footprint 0.6, cluster disk 0.05. Not yet within
    10% everywhere; the user chose to fix first: the filler is to use
    the host cache as its registry (factory task
    layer-filler-via-host-cache), then the bench reruns.
  - What the cache VM did (main ff96e48): CNCF distribution v3.1.2 as
    four pull-through registries (src/guest/plan.bend Plan.cache,
    Plan.registry_steps, Plan.registry_config: proxy ttl 168h) behind
    bend-vmm forwards 127.0.0.1:15001-15004 (C.Cli.cache_forwards); every
    VM node's containerd tried it first (Plan.mirror_steps,
    Plan.hosts_toml_pull: certs.d hosts.toml, `pull` only, the upstream
    as fallback; native nodes as 127.0.0.1, container nodes not at all);
    `vk8s cache start|stop|status|prune` booted, stopped, measured (du in
    the guest, request cache-usage) and emptied it (request cache-prune,
    fstrim of data.img); create started it unless VK8S_CACHE=off, and
    while it ran no node attached the images set (Assets.role_sets);
    the layer filler read every manifest and blob from it.
  - Now: `vk8s cache serve` (hidden; host/cache/mirror.bend) is the
    image cache, a host process on the same ports: src/oci's route,
    store (~/.vk8s/cache/store), single-flight fill-and-follow and
    upstream auth, src/oci/serve.bend for the HTTP side. The registries
    are dialed by the host (host/oci/upstream.bend: bend-kube-runtime's
    Tls.dial for the name lookup and connect, TlsSrv.secure for a
    handshake against the system's CA roots, an anonymous token per
    401, redirects per src/oci/auth.bend), so no registry DNS or TLS
    goes through a VM's NAT for cached content. The layer filler pulls
    from the registries the same way (no cache in its path), so any
    host can fill the store. The guest side is unchanged: hosts.toml
    still names 10.0.2.2:15001-15004. Idle on Linux: 0.3% of a core,
    6.6 MiB RSS (was a 1 GiB VM).
  - New laws (proposed): laws/oci_upstream.bend, laws/oci_serve.bend
    (both done), laws/cli.bend cli.cache_status.v2.*,
    cli.cache_pruned.v2. Tests: tests/cache_mirror.sh (TLS stub
    registry with token auth; one fetch for three clients that follow
    it; a digest mismatch cuts the client off; Range, HEAD, tags,
    stop), tests/layers_serve.sh now fills from the TLS stub.
  - cache.img and the registry binary no longer ship: scripts/guest/
    sets.txt has no cache set, and release v1.36.6-92057045 has no
    cache.img.
  - Gates closed (2026-11-25). Cold-pull bench again, with the host
    cache and lz4 layer images (main ebb07b7, released guest assets
    v1.36.6-92057045, 3 nodes, 3 pairs a state, under the guard, which
    never tripped; raw out/bench/cold-pull-s{3,4}.csv). The bench now
    starts one unmeasured Deployment of an image the nodes hold, so the
    first measured image does not also pay a node's first pod of the
    namespace (0.2 to 1.1 s before the sandbox with the store on or
    off, which had put busybox at 1.34 and 1.55 the same morning).
    Median of paired store on/off:

    | state | ready | busybox | nginx | redis | VMM footprint | cluster disk |
    |---|---|---|---|---|---|---|
    | 3: all cold | 0.97 | 1.00 | 0.88 | 0.75 | 0.64 | 0.05 |
    | 4: cache warm, store cold | 0.90 | 0.95 | 0.62 | 0.60 | 0.65 | 0.05 |

    Every image is within 10%; the store held 233 MiB (487 with raw
    images). The 43/0 subset and the certified run are the release
    candidate's, which ran on the host cache: standalone and classic
    43 passed, 0 failed; certified 450 passed, 0 failed in both modes
    (section 6).
- [x] Compressed layer images, if measured better. Measured
  (2026-11-24, branch feat/layer-disk, docs/ref/layers-compress.md);
  blocked, the user's decision needed. No compressor exists as a Bend
  effect: Base has none, bend-kube-runtime 0.11.0.0 and bend-vmm only
  decompress, and a pure Bend one is far too slow (the pure gzip decoder
  does about 5 MB/s; the five images below hold 441 MiB of file data).
  The guest needs nothing: Alpine's squashfs has zlib, lz4, xz and zstd
  built in. What it would buy, with sqfstar 4.7.5 as the oracle (128 KiB
  blocks, one image per layer; coredns, nginx, flannel, its CNI plugin
  and kube-proxy together): raw, as today, 440.9 MiB; lz4 205.0 (-54%);
  zstd 1 158.7 (-64%); zstd 3 152.5 (-65%); the registry's gzip blobs
  are 148.6. Host CPU per nginx fill is 0.94 s warm and 1.45 s cold;
  lz4 adds 0.09 s (+10% warm, +6% cold), zstd 1 0.15 s (+16%, +10%),
  zstd 3 0.22 s (+23%, +15%), zlib 1.16 s. In the guest (one node,
  bend-vmm 0x002839320e5a033b05bcedb51711713f, nginx's two big layers
  swapped, medians of 3): pod Ready 1.29 s raw, 1.14 lz4, 1.06 zstd 1;
  every file of the pod's root read cold 5.15 s raw, 2.67 lz4, 2.12
  zstd 1 (VMM CPU 9.2, 4.7, 3.5 s), because on that pin the cost is
  bytes over 9p. By GOAL's rule (host CPU per fill and time to a running
  pod within 10%): zstd is over on host CPU, lz4 is within. Decided
  by the user 2026-11-25: lz4 through a small C routine, after the next
  release. The question was: allow a compression effect in bend-kube-runtime beside Unz
  (C: `Zip.blocks`, file to file in 128 KiB blocks, raw when a block
  does not shrink; lz4 can be a small C routine with no library, zstd
  needs libzstd, which macOS does not ship), and which compressor (lz4
  by the rule; zstd 1 if 0.15 CPU-seconds once per image is acceptable
  for 10% more disk), or keep the images raw. The vk8s side is then a
  v2 of src/layers/sqfs.bend with new laws.
  Done (2026-11-25, the commit that adds Sqfs.image_z): the filler
  writes file data in lz4 blocks. bend-kube-runtime 0.12.0.0 has the
  effect (`Zip.blocks`, src/effs/zip.c: LZ4's block format in portable
  C, no library; bend-kube 184e4c3); every import moved to that pin.
  src/layers/sqfs.bend gained Sqfs.image_z beside Sqfs.image (the
  tables are laid out as before, each regular file's block list
  replaced by the words the compressor answered; super block:
  compression 5, COMP_OPT, the 10 bytes of options, data from 106),
  with 12 proposed laws whose bytes come from an image sqfstar 4.7.5
  wrote with -comp lz4 (laws/layers_sqfs.bend; no existing law
  changed). Old raw images stay readable and are not rewritten.
  Measured on the Mac (M5 Pro), raw build against lz4 build:
  - disk: the layer store of a one-node cluster with nginx (36 layer
    images) 450 MiB raw, 211 MiB lz4 (-53%); nginx alone 189 to 93 MiB.
  - time to a running pod, 4 clusters each in alternating order, store
    emptied before each, nginx's blobs in the image cache: first nginx
    pod (fill and start) median 1930 ms raw, 1935 ms lz4; a repeat pod
    640 ms raw, 650 ms lz4 (8 each); create to CoreDNS Ready 25.3 s
    raw, 24.8 s lz4. All within 2%.
  - reading every file of the pod's root cold (200 MB, node caches
    dropped, 12 reads each): median 1824 ms raw, 1102 ms lz4.
  - host CPU per fill (`vk8s layers fill` of nginx, blobs local, 3
    each): 1.00, 0.97, 1.00 s raw; 1.22, 1.15, 1.14 s lz4. That is
    +15%, over GOAL's 10%: the compressor alone takes 0.19 s for
    nginx's 202 MB (1.0 GB/s; liblz4 itself does 1.6 GB/s on the same
    data, which would still be +12%). Kept all the same, as the user
    chose lz4 on 2026-11-25 from the estimate (+10%): it is 0.15 s of
    CPU once per image per machine, against half the disk and 0.7 s
    less on each cold read of the image in every node. To undo it, the
    filler's call of Sqfs.image_z goes back to Sqfs.image.
  - tests: unsquashfs 4.7.5 on the Mac reads the images back byte for
    byte (blocks that shrink, blocks that do not, empty files beside
    them); the guest kernel mounts them (the clusters above);
    tests/layers_sqfs.sh has the same checks under a Linux loop mount
    for CI.
- [x] Optional sets fetched on demand (gVisor, etcd) (4111c70,
  2026-11-24). sets.txt has the sets gvisor (runsc, its shim, gvisor-bin)
  and etcd (etcd, etcdutl; etcdctl stays with the control plane, kine's
  snapshot uses it); Assets.role_sets.v2 adds them only for `--gvisor`
  and `--backing-store etcd`. cluster.env records GVISOR=1|0, and
  upgrade, VM restore, node add and rotate-ca reuse it; without gVisor
  Plan.with_gvisor leaves out runsc.toml, the runsc stanza and the
  RuntimeClass. create prints `Optional features off: gVisor (--gvisor),
  etcd (--backing-store etcd)`. Laws assets.role_sets.v2.*,
  assets.optional.*, cli.gvisor.*, plan.with_gvisor.*, ctr.sets.v2.*,
  nodehost.sets.v2, native.sets.v2. CI 45417515516: 29 of 29 jobs
  (kvm-smoke runs a gVisor pod, restores, and checks a second cluster
  has no gvisor set). Mac (2026-11-24, assets built from main): a
  default cluster attaches base, node, control-plane and data only and
  has no RuntimeClass; `--gvisor --backing-store etcd --nodes 1` has
  GVISOR=1 and STORE=etcd, a runtimeClassName gvisor pod logs "Starting
  gVisor...", etcd.img is on the control plane only, and a worker added
  later attaches gvisor.img. Squashfs sizes: node 147 to 100 MB,
  control-plane 88 to 76 MB, gvisor 47 MB, etcd 13 MB. On a Mac's node
  host gVisor belongs to the shared VM: a create that needs a set the
  running node host lacks stops and says which clusters to delete.
  Reaches users with the next asset release; until then a released
  binary uses the old sets, which hold both.
- [x] Container regression flannel crash (2026-11-20, found after the
  runtime pin; factory tasks fix-container-flannel-crash and round two):
  flannel crash-looped on one node in about one job in six ("Failed to
  create SubnetManager ... dial tcp 10.96.0.1:443: i/o timeout"). Two
  races: kube-router's full filter-table restore (no --noflush, v2.12.0
  pkg/utils/iptables.go) removed the chains kube-proxy had just made, so
  kube-proxy wrote no Service rule (kube-router now waits for
  kube-proxy's KUBE-NODEPORTS jump, Netpol.with_cfg.v2, laws
  netpol.after_proxy_*); and flanneld could start before kube-proxy
  (whose pod retries "services have not yet been read at least once"),
  so its first SYN left un-NATed and conntrack kept the flow (flannel's
  DaemonSet now waits in an init container for kube-proxy's rule for
  the API Service). Repro runs: 2/16 shards crashed on the first fix
  (44808578892); 16/16 passed on the second (44824614556) and 16/16 with
  the race forced on every shard (44836823308).
- [x] Power button missed early after boot (found 2026-11-21, cause from
  the bend-vmm session): `powerdown` sends KEY_POWER on the virtio-input
  keyboard and bend-vmm queues it, but evdev passes a key only to
  descriptors open at that moment, and PID 1 opened /dev/input/event*
  only at its first supervise tick, so a press during the boot steps was
  lost (delete right after create took 61 s, node delete 62 s, a worker
  pressed while booting kept running). Fixes: PID 1 opens the devices
  right after the Modules step (host/init.bend; reaches the Mac with the
  next asset release), and vk8s presses again every 5 s during its 60 s
  wait (Vk8s.vm.patient; harmless, PID 1 counts presses). Mac with the
  released guest and the vk8s fix alone: node delete 8 s, delete 16 s,
  no VMM left.
- [x] Control-plane-only nodes (joinNode.enabled: false): vcluster's
  controlPlane.standalone.joinNode.enabled false (config/config.go: "only
  the control plane binaries will be executed and no node will show up")
  runs a standalone control plane without its node's daemons
  (containerd, kubelet, the layer snapshotter, kube-router) and the
  steps that need them (the containerd and snapshotter socket waits, the
  ctr imports): Values.join_node.v2, laws values.join_node.off/on/
  absent/not_cp. CI 44794330088 kvm-smoke step 3b (amd64 and arm64):
  create 21.5 s, the worker is the only node, a pod Runs on it, delete.
- [x] One guest binary and one runtime pin. Runtime pin done (factory
  task runtime-single-kube-pin-2, 2efdb59 and 5b10bfd, merged): every
  file imports bend-kube-runtime@0.10.0.0 (73 files, import lines only;
  laws and proofs differ only in imports, checked); 0.2.0.0's time,
  http, base64, utf8 and yaml modules are byte-identical in 0.10.0.0,
  json only gains Json.keys and Json.mem_keys. Guest PID 1's C is 246 KB
  smaller (229 duplicate functions gone); the host binary's is
  unchanged. CI 44761272388 check and verdict green; PROOF.bend ALL
  PROOFS CHECK after the merge. One guest binary (factory task
  one-guest-init-binary, 18f033e and 1ab438b, merged cd98849): init.c
  is built once, as the dynamic glibc /usr/bin/vk8s-guest, and
  /sbin/vk8s-init (PID 1) is a relative link to it on the base disk;
  stage 0 mounts the base disk (glibc's loader) before PID 1 runs. The
  static musl build (about 9.7 MB) and host/musl_shim.h are gone. CI
  44785190640 booted every role from it: kvm-smoke amd64 and arm64,
  container-smoke both arches, native-smoke, kvm-regression standalone
  and classic, kernel16k; tests/guest_image.sh checks one copy of the
  binary on the disk. No law changed. The Mac gets it with the next
  asset release.
- [x] Shared assets and layers off the VM (native, container). Native
  half done (factory, merged d604ec9): a Linux native cluster's
  bin/ is a symlink to one root-owned, read-only copy of the role sets
  per asset version, /var/lib/vk8s/.assets/<key>/bin (key: 16 hex of
  the SHA-256 of the set images' digests), unpacked once into a stage
  dir and renamed into place (NHost.unpack_cmds, NHost.publish_cmd,
  NHost.prepare_cmds.v2). No mount, so a reboot restores nothing. Delete
  removes the copy with the last cluster that links to it
  (NHost.release_cmds); `vk8s assets prune` stays on ~/.vk8s/assets.
  Proposed laws native.assets_root ... native.delete_leaves_nothing_v2,
  all proven. CI run 44852406913 (all green): native-smoke checks one
  copy for two clusters, no write bit, a unit restart with nothing to
  restore, the copy kept by the second delete and gone after the last;
  native-regression 42 passed, 0 failed. Disk of two native clusters
  (scripts/native-disk.sh, du -sk; before = the data dirs plus one
  unsquashfs of the sets per cluster, measured by unpacking them again):
  one copy of the sets is 813.1 MiB. native-smoke (demo with the host
  node, a control plane beside it): 2401.7 MiB before, 1588.6 MiB after
  (-34%). native-regression (st after the regression subset, etcd, and
  a control plane beside it): 3415.5 MiB before, 2602.3 MiB after
  (-24%). Each further cluster of the same version saves 813.1 MiB.
  Container half on Linux merged (ce63745, 2026-11-24), opt-in
  (VK8S_LAYERS=1; unset, Ctr.json.v2 is Ctr.json byte for byte, law
  ctr.json_v2_off): each node's config binds the store read-only and the
  host's /dev (for the loop devices), the snapshotter loop-mounts the
  layer images in the container's own mount namespace, and the node
  asks the filler at its bridge gateway (a DNAT to 127.0.0.1:32000, an
  INPUT accept, and a drop of the rest of 127/8 from the bridge, all
  tagged for the cluster's cleanup). Laws plan.layers_on_v2.*,
  plan.with_layers.v5.*, container.layers_mounts, ctr.layers_*. CI
  45412640291: 29 of 29 jobs; tests/container_layers.sh 30 PASS per
  arch (lowerdirs are /mnt/layers/<hex>, one image per layer on the
  host, no loop device, mount or rule after delete). Two nodes, nginx,
  then: disk 945 to 448 MiB on arm64 and 919 to 510 MiB on amd64; cold
  start 3.4 to 7.2 s and 4.0 to 21.1 s.
  Measured again (2026-11-26, feat/shared-layers-2, CI 45720781566,
  after the faster fill ebf32a8, the lz4 images ebb07b7 and the
  snapshotter without busybox; the test now waits for every add-on pod
  before it times a start, since a pod's pull waited up to 2 s behind
  the add-ons' pulls). Container nodes, two nodes, store off against on:

  | | arm64 off | arm64 on | amd64 off | amd64 on |
  |---|---|---|---|---|
  | disk, nodes + store (MiB) | 929 | 269 (0.29) | 974 | 287 (0.29) |
  | nginx:1.27 cold, run to Ready (s) | 4.4 | 7.0 | 4.0 | 5.5 |
  | nginx warm, on the other node (s) | 4.5 | 2.5 | 3.9 | 1.3 |
  | httpd:2.4 cold / warm (s) | 3.2 / 3.4 | 6.0 / 1.9 | 2.6 / 2.7 | 4.4 / 1.3 |
  | redis:7 cold / warm (s) | 3.1 / 3.0 | 6.4 / 1.8 | 2.5 / 2.6 | 4.8 / 1.3 |
  | create (s) | 9.7 | 10.5 | 10.9 | 12.2 |

  The cold start is 38% to 106% slower, not within 10%, so the default
  stayed off for container nodes until the no-wait mode below
  (VK8S_LAYERS=1 opted in; no law or def changed). Where the time goes (the filler's log and the pods' events,
  run 45705988701, arm64, nginx): containerd's own pull with the store
  off is 2.7 s (2.5 s on amd64); with the store on the pull is 5.7 s, of
  which the fill is 4.4 s (3.4 s on amd64): 7 layers side by side,
  summed fetch 2.0 s, decompress 2.4 s, unpack (the squashfs image with
  lz4 blocks) 3.5 s, fsync and rename 0.02 s; the largest layer alone
  took 4.0 s (fetch 0.4, decompress 1.2, unpack 2.3). The other 1.3 s
  is the node's manifest resolve, the ask, and the filler's own token,
  manifest and config requests. So the fill's CPU work alone is longer
  than containerd's whole pull on these 4-core runners (the same fill
  is 1.15 s on the Mac), and no change to the ask or the snapshotter
  can bring a cold start within 10%: it needs a fill about twice as
  fast (the decompressor Unz.file and the block compressor Zip.blocks
  are bend-kube-runtime's; the image's tables are src/layers/sqfs.bend)
  or a node that does not wait for the fill. Decision for the owner,
  one of: (a) accept the slower first pull for 0.29 of the disk and
  warm starts 1.8 to 3 times faster, and turn it on; (b) a no-wait
  mode: a node unpacks a layer the store lacks itself while the filler
  fills the store for the next node (cold start as off, the first node
  keeps its copy); (c) a faster Unz and Zip in bend-kube-runtime, then
  measure again. The container regression with the store on was not
  run, as the default did not change.
  Native host nodes done, opt-in (VK8S_LAYERS=1 at create, for the
  cluster that runs the host's node). Design: the node runs in the
  host's mount namespace, so it reads the store where it is and mounts
  each layer image under its own data dir,
  /var/lib/vk8s/NAME/node/layers/<hex>, on a loop device of its own
  with autoclear (src/layers/place.bend: the snapshotter gets the two
  places as arguments and rewrites each path where it leaves the pure
  code; NHost.with_layers puts the snapshotter in front of containerd;
  NHost.unit.v2 names the store in the unit). The snapshotter is the
  guest binary of the assets' base disk, copied into the data dir at
  create (NHost.layers_guest_cmds), not the host binary: with the
  snapshotter linked in, the host binary's C needs 18.9 GB instead of
  17.1 GB to compile at -O2, which took the Linux host build from 1 to 7
  minutes to 16 to 19 and ended two 16 GB runners (CI 45726332499,
  45735703754). The guest binary needs glibc 2.38 (Ubuntu 24.04 has
  2.39); on a host where it does not run, or with assets that have no
  base disk, create says so and leaves the store off. What holds a layer for a
  cluster is that mount: a reference the kernel keeps per cluster and
  per layer, with no count in a file to go stale. It ends where every
  mount of the cluster ends, at the unit's next start (the reset script
  unmounts everything under the data dir after it has ended the pods;
  the snapshotter mounts again only what its snapshots stand on) and at
  delete (after the unit is stopped and the pods ended). Another
  cluster on the same image has its own loop device, so an unmount
  never takes it. No count across native clusters exists because only
  one native cluster runs a host's node (the others are control planes
  only); the second cluster in the tests is a node container on the
  same store, or the next native cluster. A store directory of an older
  vk8s is not bound under the data dir (the node unpacks such a layer).
  Laws layers_place.* (16, laws/done/layers_place) and native.layers_*,
  native.unit_v2_*, native.with_layers_* (14), all proven.
  tests/native_layers.sh, in native-smoke (amd64) and in container-smoke
  beside a node container (both arches), CI 45720781566: lowerdirs are
  the data dir's layer mounts, each a squashfs on a loop device backed
  by the store's image; one image per layer; after a kill of every
  process of the unit 35 mounts stay and after its restart there are 35
  mounts and 35 loop devices, none twice; with a node container on the
  same 7 images (70 loop devices), the native delete leaves no mount
  under /var/lib/vk8s and takes its own 35, the container's pod reads
  the same nginx again with the page cache dropped and a new pod
  starts; the last delete leaves no loop device. Measured, one host
  node, nginx:

  | | arm64 off | arm64 on | amd64 off | amd64 on |
  |---|---|---|---|---|
  | disk, data dir + store (MiB) | 635 | 374 (0.59) | 640 | 406 (0.63) |
  | cold, run to Ready (s) | 3.7 | 7.2 | 3.1 to 3.8 | 5.5 to 6.0 |
  | second pod, image on the node (s) | 0.5 | 0.5 | 0.5 to 0.6 | 0.6 |
  | first pod of a second cluster, image in the store (s) | | 4.2 (container) | | 1.5 (native), 2.2 (container) |

  The cold start has the same cost as in a node container, so native
  stays opt-in too. The branch's last run, CI 45744286594 (34e551d, the
  snapshotter from the base disk): 29 of 29 jobs, native_layers.sh OK
  in native-smoke and in both container-smoke jobs, container_layers.sh
  OK on both arches; its numbers agree (container cold 3.3 to 6.1 s on
  arm64 and 4.1 to 6.2 s on amd64, disk 0.29; native cold 2.7 to 5.4 s
  and 3.0 to 3.7 against 6.3 to 6.7 s, disk 0.59 and 0.64; a second
  cluster's first pod 1.8 s native, 2.6 to 2.9 s container).
  The no-wait mode, option (b), built, and the store on by default for
  node containers (2026-11-26, feat/layers-nowait; the owner's
  decision). A node container and a
  native host node (the nodes whose PID 1 environment names the filler,
  VK8S_LAYERS_ASK; Ask.nowait.v4) do not wait for the fill of a layer
  the store lacks: the Prepare is answered at once as with the store
  off, containerd fetches and unpacks the layer on the node, and that
  node keeps its copy. The ask is kept (Ask.later.*.v4): each kept ask,
  and each Prepare, View or Commit while asks are kept (Spb.busy.v7),
  starts a 3 s timer (Ask.quiet.ms.v4) that carries a count, and the
  timer whose count is still the current one, with no layer being
  unpacked (Ask.unpacking.v4: no active snapshot with a
  containerd.io/snapshot.ref label), sends the asks to the filler one
  at a time. So the fill starts 3 s after the node's last pull activity,
  when the pod has started, and its CPU work does not meet the pull: no
  nice and no change to the filler were needed. A layer the store holds
  is asked for and waited for as before (the answer comes at once, and
  the filler renews the layer's last use under its lock before the node
  mounts it; Ask.waits.v4). A VM node waits for every fill as before:
  its path, the pack and its defaults are unchanged. A chain that is
  not all in the store works without a change to the snapshot code:
  each snapshot keeps its own lower directory (Sn.lowers), a shared
  layer's /mnt/layers/<hex> or an unpacked one's snapshots/<id>/fs
  (laws layers_snap.mixed_*, 9: the lower layer shared and the upper
  unpacked, the reverse, one unpacked between two shared, what is held,
  and that an unpacked layer under a shared one cannot be removed).
  The store is the default for node containers (Ctr.layers_on.v2;
  VK8S_LAYERS=0 turns it off). A native host node stays opt-in
  (VK8S_LAYERS=1, NHost.layers_on as before, and it does not wait
  either): only one native cluster runs a host's node, so the common
  case is one cluster on an empty store, which keeps its own copy
  beside the store's (1.32 to 1.38 of the disk, below) and gains
  nothing until another cluster uses the store.
  Laws added, all proposed and proven, the strict kernel check
  included: layers_ask.nowait_v4, .waits_v4, .waits_v4_vm,
  .nowait_said_v4, .quiet_ms_v4, .later_* (16), .unpacking_* (4);
  layers_pb.busy_v7, .busy_not_v7, .busy_unknown_v7;
  layers_snap.mixed_* (9); ctr.layers_on_v2, .layers_on_v2_was_on,
  .layers_note_v2. No existing law changed or contradicted the mode.
  Tests, both rewritten for it: tests/container_layers.sh (the first
  node's pod stands on its own unpack and the second node's on the
  store's images; nginx:1.27-otel, nginx:1.27 and one layer more, on
  the second node has its 7 lower layers from the store and the top one
  unpacked there, and then, the store filled, on the first node the top
  layer from the store over the 7 it unpacked itself, and both pods
  read the same files; the next cluster stands on the store with no
  image written for it; delete leaves nothing) and tests/native_layers.sh
  (the first cluster on an empty store unpacks for itself and the
  filler fills the store; the next native cluster stands on it, with
  the crash and restart, the mixed chain and the node container beside
  it as before). A start is timed only when no fill runs (the tests
  wait until every kept ask is answered). CI 45760130791 (the full
  lane; container-smoke both arches, native-smoke): both tests OK,
  tests/container_smoke.sh and tests/idle_sleep_smoke.sh pass on the
  store too. Earlier runs of the two tests alone: 45756008339 (both
  arches OK), 45752161247 (arm64; its one failure was the test not
  reading the worker's log). Container nodes, two nodes, CI 45760130791,
  store off against on:

  | | arm64 off | arm64 on | amd64 off | amd64 on |
  |---|---|---|---|---|
  | nginx:1.27 cold, run to Ready (s) | 3.4 | 3.4 | 3.7 | 3.4 |
  | six images cold, summed (s) | 12.8 | 13.7 (1.07) | 12.5 | 13.0 (1.04) |
  | their pulls alone, summed (s) | 9.3 | 10.1 (1.08) | 8.8 | 9.3 (1.06) |
  | nginx warm, on the other node (s) | 3.2 | 1.2 | 3.1 | 2.0 |
  | five images warm, summed (s) | 9.5 | 6.3 | 9.0 | 5.4 |
  | disk, nodes + store, the first cluster on an empty store (MiB) | 995 | 934 (0.94) | 905 | 932 (1.03) |
  | disk, the second node (MiB) | 490 | 222 (0.45) | 486 | 213 (0.44) |
  | disk, the next cluster's two nodes (MiB) | | 60 (0.06 of 995) | | 63 (0.07 of 905) |
  | the next cluster's first nginx pod (s) | | 1.9 | | 1.7 |
  | create (s) | 10.2 | 10.5 | 10.9 | 11.6 |

  (The six images: nginx:1.27, httpd:2.4, redis:7, memcached:1.6,
  caddy:2, registry:2; "pulls alone" is the kubelet's Pulled event.)
  The other runs agree: nginx cold 3.7 to 3.6 s and 3.9 to 3.6 s on
  arm64, 3.6 to 3.1 s on amd64; the six images 12.9 to 13.1 s (1.02) on
  arm64 and 12.4 to 13.0 s (1.05) on amd64 (45756008339). One native
  host node, nginx, cold run to Ready, off against on: arm64 3.7 to
  2.6, 3.3 to 2.4 and 2.6 to 3.0 s (three runs; mean 3.2 to 2.7); amd64
  3.3 to 3.1, 3.9 to 3.2 and 4.6 to 3.0 s (mean 3.9 to 3.1). Its disk,
  data dir + store: 678 to 896 MiB (1.32) on arm64 and 616 to 853 MiB
  (1.38) on amd64 for the first cluster on an empty store (the node's
  own copy and the store's), and 152 MiB (0.22) and 169 MiB (0.27) for
  the next native cluster's data dir; that cluster's first nginx pod is
  Ready in 1.1 to 2.8 s, a node container's beside it in 2.0 to 2.4 s.
  So the cold start is within 10% of store-off on both arches, on
  average and in each run's sum; single samples differ by up to 0.8 s
  either way (the pull is a download; one native run on arm64 was 15%
  slower with the store on, two were 27 and 30% faster). What is left
  of the difference is not the fill: the pull itself is 6 to 8% longer
  with the store on, about 0.1 s an image, because the Bend snapshotter
  writes its whole state after each Prepare and Commit (about 10 ms a
  call at 64 snapshots: 7 ms to render 50 KB, 2 ms to write it) where
  containerd's overlay snapshotter updates one bolt record. That cost
  grows with the number of snapshots a node holds; it was not measured
  on a node with hundreds, and VM nodes have had it since the store
  became their default. What the mode costs: the node that pulls an
  image first keeps its own copy, so a host's first cluster on an empty
  store uses as much disk as with the store off, plus the store's
  compressed copy (0.94 to 1.03 for two container nodes, 1.32 to 1.38
  for one native node); the gain comes with the second node (0.44 to
  0.45) and each next cluster (0.06 to 0.07; 0.22 to 0.27 native). Two
  nodes that pull the same image at the same moment each unpack it. A
  node never swaps the copy it unpacked for the store's. The container
  regression subset ran on the store (the default): CI 45760130791
  container-regression, 43 passed, 0 failed on both arches (the full
  lane: 29 of 29 jobs); after it the store held 84 layer images (548
  MiB) on arm64 and 85 (513 MiB) on amd64, with 34 and 47 asks waited
  for (layers mounted from the store) and 125 and 116 not waited for,
  each answered ok once its pull was over (its three nodes pull most
  test images at the same moment, so each unpacks its own).
  Known costs and limits of the mode, accepted as it is: (1) The node
  that pulls an image first keeps its copy and never swaps it for the
  store's, so a host's first cluster on an empty store saves no disk,
  and nodes that pull the same image at the same moment each unpack it
  (the regression's three nodes: 125 and 116 layers unpacked against 34
  and 47 mounted). (2) The snapshotter rewrites its whole state after
  each Prepare and Commit, about 10 ms a call at 64 snapshots; VM nodes
  share that code, and a node with hundreds of snapshots was not
  measured. (3) With the store on by default every node container
  binds the host's /dev (for the loop devices) and its bridge gets the
  rules to the filler; that was opt-in before. (4) One filler runs per
  host and serves the store of the home it was started from, so
  clusters made from different homes (root's node containers and a
  user's native cluster, say) do not share layers; with no-wait their
  nodes only lose the sharing.
  Not done here: the native
  regression runs without the store (opt-in, and its assets have no
  base disk); the
  state write after each call (a record a call, or a journal, would
  take the remaining 0.1 s an image off).
  The macOS node host, built and run on a Linux host with KVM
  (2026-11-26, feat/layers-nodehost; the Mac's run is below).
  The sketch was "share the store into the shared VM once; DNAT the
  gateway's port to 10.0.2.2:32000". Checked against the code, the first
  half holds and the second is not needed:
  - The store. The node host VM gets the share a VM node gets
    (Cli.with_layers: tag layers, read-only, bend-vmm's meta mode, and
    VK8S_LAYERS=1 on the kernel command line; Nh.flags.v2), once, when
    it starts, since bend-vmm's shares are fixed then. Its PID 1 mounts
    it at /mnt/layers-store (Nh.layers_mount, the mount of a VM node,
    Plan.layers_store_mount.v4) and writes on its share whether it did
    ("1" or "0" in share/layers, Nh.layers_ack), both before it says
    ready: its boot plan runs in two parts that together are the plan
    of before (Nh.boot_head, Nh.boot_tail; law nodehost.boot_parts). A
    mount that fails does not stop the boot. A node container binds that mount and
    the VM's /dev exactly as a node container on a Linux host binds the
    host's (Ctr.json.v2 with the VM's path; Nh.node.v2), and its
    snapshotter loop-mounts the images in the container's own mount
    namespace, the code path of the Linux container half, unchanged.
  - The pack disk (what VM nodes read layers from) was the other way
    in, and is not used: a pack belongs to one VM under
    ~/.vk8s/clusters, keyed by a file in that VM's share, and its
    entries are dropped by the one snapshotter that added them. In the
    node host several snapshotters (one per node container, of several
    clusters) would share one pack: a drop by one would end a range
    another still has mounted, so it would need a count across
    containers that a killed container never gives back (delete kills
    them), and gc could not tell a live entry from a leaked one. The
    share needs none of that: a mount in a container's namespace is
    the reference, and it ends with the container. The price is the
    read path the pack was built to avoid (loop over 9p: a cold read of
    a 200 MB root at 1.8 to 2.2 s against 0.23 to 0.28 s on the Mac,
    and slower on nested KVM); the node host softens it, because one
    guest kernel's page cache serves every node of every cluster, so a
    layer is read through the share once per node host, not once per
    node. A pack shared by a VM's containers stays possible later
    (the mounts would have to move to the VM's PID 1).
  - The filler. On a Linux host the node asks its bridge gateway and
    three rules lead to the host's loopback, because no container can
    route to 127.0.0.1 of the host. In the node host the Mac's loopback
    has an address every guest routes to, 10.0.2.2 (bend-vmm's NAT;
    Ask.host.v2, what a VM node asks), and a node container reaches it
    through its default route: the bridge, the VM's forwarding and the
    masquerade the cluster has already (Ctr.rules; it is how the node
    reaches a registry). So PID 1's environment names 10.0.2.2
    (VK8S_LAYERS_ASK, Nh.layers_env) and no rule, route_localnet or
    DNAT is added: delete has nothing more to undo (law
    nodehost.up_v2_on_rules: a cluster's first 17 steps, its rules
    among them, are the same with and without the store). Naming the
    address is also what puts the node in the no-wait mode
    (Ask.nowait.v4).
  - Per cluster. The store is a cluster's choice at create
    (VK8S_LAYERS=0 opts out, Nh.layers_on), carried as the last word
    "layers" of its up and join requests (Nh.parse.v2, a new Req around
    the Op of before; without the word every request parses as before,
    so an older vk8s on the Mac still drives this guest). The Mac
    sends the word only when PID 1's file on the share says "1"
    (Nh.layers_use): a create that asks for the store in a node host
    that runs without it (VK8S_LAYERS=0 at its first cluster, a mount
    that failed, or guest assets older than the store, whose PID 1
    writes no such file and would refuse the word) says so and leaves
    the word out (Nh.layers_say), and PID 1 starts a node on the store
    only when its own mount worked (Nh.req_on). So this vk8s with
    older guest assets, and older vk8s with these, both run container
    clusters as before, without the store.
  - Delete. Nothing of the store is in the VM's own mount namespace or
    rules, so Nh.down and Nh.unrules.v2 are unchanged. PID 1 now says
    after each down request what of the cluster is left (Nh.after):
    the cluster's mounts in the VM's /proc/mounts (its directories, its
    nodes' network namespaces), its tagged rules in both tables, and
    the loop devices in use in the whole VM (/proc/partitions lists a
    loop device only while a file backs it).
  - gc. A node's layers.held is on its share, under the node host's
    share on the Mac, so the filler's gc reads those too
    (Nh.held_root; Lf.held.v7): the clusters looked up are the
    host-made folders of ~/.vk8s/clusters, a worker's folder there is
    the guest's (a guest can only make gc keep more).
  VM-mode clusters and Linux container and native nodes run none of
  this code: only Vk8s.nh.* and PID 1's node-host role changed, and
  with the store off the node's steps and config are the ones before
  (laws nodehost.node_v2_off, .up_v2_off, .join_v2_off). No bend-vmm
  change was needed. Laws added, all proposed and proven, the kernel's
  verdict included (36: nodehost.layers_on, .layers_mark, .boot_parts,
  .boot_tail, .layers_use,
  .layers_use_mark, .layers_say, .flags_v2_on, .flags_v2_off,
  .layers_mount, .layers_store, .layers_env_on, .layers_env_off,
  .layers_env_nowait, .layers_env_nowait_on, .node_v2_off, .up_v2_off,
  .join_v2_off, .node_v2_on_config, .node_v2_on_before,
  .node_v2_on_after, .up_v2_on_rules, .up_v2_on_node, .requests_v2,
  .parse_v2_layers, .parse_v2_plain, .parse_v2_bad, .req_op, .req_on,
  .held_root, .mounts_left, .mounts_left_none, .rules_left,
  .list_rules, .loops, .after).
  tests/nodehost_layers.sh, in CI job nodehost-smoke after
  tests/nodehost_smoke.sh (amd64, real KVM, VK8S_NODE_HOST=vm, no root
  and no runc on the host): the same workload with VK8S_LAYERS=0 and
  with the default, each in a fresh home and a fresh node host with two
  one-node clusters; nginx:1.27 cold in the first cluster, then in the
  second; httpd:2.4 cold in the second, then in the first. Off, nothing
  of the store exists (no share, no filler, no snapshotter). On: the
  first cluster's pod stands on its node's own unpack; every lowerdir
  of the second cluster's pod is /mnt/layers/<hex>, in that node a
  squashfs on a loop device backed by <hex>.sqfs, which the host's
  store holds; no image is written and no ask kept for it; both pods
  read the same nginx; the node's layers.held is where gc reads it; the
  other way round with httpd, after which the loop devices in use in
  the VM are exactly the two nodes' layer mounts (41 = 6 + 35: the
  second cluster's add-on images came from the store too); delete of
  the first cluster: PID 1 says "after on1: no mount and 0 rules of it
  left, 35 loop devices in use", a pod of the second cluster counts 35
  too, its nginx pod reads the same file with the page cache dropped,
  a new pod starts from the store in 1.0 s; the last delete stops the
  node host and removes its directory, the store stays.
  tests/nodehost_smoke.sh (the default is on now: a cluster with a
  worker and --gvisor, a second cluster, pause, resume, delete) also
  checks that the node host has the share and that both of a's nodes
  run the snapshotter (the up and the join request). CI 45784489744
  (the two tests alone): nodehost_layers 68 PASS, nodehost_smoke 38
  PASS. Measured there, store off against on:

  | | off | on |
  |---|---|---|
  | nginx:1.27 cold in the first cluster, run to Ready (s) | 7.1 | 6.9 (0.97) |
  | its pull alone (s) | 5.5 | 5.3 |
  | nginx in the second cluster, run to Ready (s) | 4.9 | 1.9 (0.39) |
  | its pull alone (s) | 3.9 | 1.2 |
  | httpd:2.4 cold in the second cluster (s) | 3.8 | 3.8 |
  | httpd in the first cluster (s) | 3.7 | 1.9 |
  | create, first / second cluster (s) | 17.3 / 14.3 | 16.0 / 11.3 |
  | the node host's data disk after the first cluster's pod (MiB) | 617 | 535 |
  | what the second cluster's create added to it (MiB) | 343 | 46 |
  | what the second cluster's nginx pod added to it (MiB) | 256 | 2.5 |
  | data disk after all four pods (MiB) | 1553 | 761 |
  | the store on the host (MiB) | | 289 |
  | data disk + store (MiB) | 1553 | 1050 (0.68) |

  (The data disk is the allocated size of ~/.vk8s/nodehost/data.img
  after a sync in the guest; "pull alone" is the kubelet's Pulled
  event.) Two more runs, in job nodehost-smoke of the full lane
  (45790503240, and 45797556712 with four more images, redis:7,
  memcached:1.6, caddy:2 and registry:2, each cold in the first
  cluster and then in the second): nginx cold 6.6 to 11.0 s and 11.6
  to 13.3 s (its pull 5.2 to 8.8 and 8.7 to 10.8 s), nginx in the
  second cluster 7.3 to 2.6 s and 5.2 to 2.1 s, httpd cold 5.8 to 5.0
  and 5.5 to 4.2 s, in the other cluster 5.6 to 2.7 and 6.7 to 2.0 s;
  the six images of the last run summed: cold 36.4 to 29.0 s (0.80),
  their pulls alone 29.6 to 22.6 s, in the other cluster 23.5 to 16.3
  s (0.69); data disk + store 1466 to 1077 MiB (0.73) and 1464 to 1092
  MiB (0.75); the second cluster's nginx pod added 251 and 246 MiB
  with the store off, 2.3 and 2.3 MiB with it on. A single pull on
  these runners is a download through bend-vmm's NAT under nested KVM
  and varies by seconds either way (the first pull of a fresh node
  host is the slowest in both modes: 7.1, 6.6 and 11.6 s off, 6.9,
  11.0 and 13.3 s on; redis cold 8.6 s off and 4.4 s on in the same
  run); the ten cold starts of the three runs sum to 59.7 s off and
  55.7 s on (0.93). The snapshotter's log shows why the store does not
  enter a cold pull: every layer of an image is answered "not in the
  store" at once, and "the pull is over: N asks" comes once, after the
  last of them, so the fill (3.8 s for nginx on the runner) starts
  when the pod has started.
  So a cold start costs what it costs with the store off, and a
  second cluster in the same node host starts its first pod from the
  store without unpacking a layer, in 0.36 to 0.40 of the time, with
  0.13 of the disk for its create and 0.01 for the image. The first
  cluster keeps its own copy, as on Linux. These are nested-KVM
  numbers through the 9p share; the Mac's are open.
  Known limits, as built: (1) the layers come through the share, not a
  pack (above). (2) A node host that started with VK8S_LAYERS=0, or
  from an older vk8s or older guest assets, has no store until it
  stops with its last container cluster; create says so. (3) VK8S_LAYERS=0 on a later
  create opts that cluster out, but the VM keeps the share mounted for
  the others. (4) One filler serves one home's store (as before), and
  a node host serves one home. (5) Any pod can reach 10.0.2.2:32000,
  as in a VM node; the filler takes only well-formed asks for public
  images. (6) The compatibility with older guest assets and an older
  vk8s (the word only after PID 1's "1") is by construction and by
  law, not run: CI builds both sides from one tree.
  The Mac (2026-11-27, main 103627a, the release candidate's binary and
  assets): tests/nodehost_smoke.sh 38 of 38 and tests/nodehost_layers.sh
  70 of 70 (out/mac-nh-smoke.log, out/mac-nh-layers.log; the store
  shared from the test's ~/.vk8s, the filler on the Mac). Its numbers,
  store off against on: six cold starts sum to 32.9 s and 33.4 s
  (1.02; the pulls 28.4 and 28.6 s); the same six images in the other
  cluster 33.5 s and 20.9 s (0.62); the second cluster's first nginx pod
  9.4 s and 4.1 s (0.44; its pull 7.2 and 2.8 s); the node host's data
  disk plus the store 1533 and 1111 MiB (0.72), and the second
  cluster's nginx pod adds 279 MiB to the data disk with the store off
  and 2.6 MiB with it on. Sleep and wake with layer mounts, by hand:
  two container clusters with `--idle-sleep 2`, an nginx pod in each
  (the second's root on 7 store layers); both slept and the VM
  hibernated at 8.7 MB (1.86 GB awake); a read of the pod's binary
  through the second cluster's kubeconfig answered in 1.4 s with the
  same SHA-256, 0 restarts in either cluster, and a new pod started
  from the store. Both tests' timers and one count needed macOS forms
  (perl for `date +%s.%N`, `wc -l` without its padding).
  Not run: the regression subset in the node host with the store on
  (CI has no such lane; the Linux container regression ran 43 of 43 on
  the same snapshotter path).
- [x] Fewer shell-outs (host only needs vk8s). First batch merged:
  control-socket lines through bend-vmm's typed API (V.Vmm.ctl) instead
  of nc; join tokens and request IDs from IO.random_u32 with unbiased
  [a-z0-9] draws (Tok.id_from, laws token.*) instead of tr </dev/urandom;
  19 existence checks on vk8s's own paths through lstat (V.Fs.facts)
  instead of test processes (user-named paths keep test). Second batch
  merged: mkdir -p, chmod 700, rm -f, rm -rf (an lstat worklist that
  never follows a symlink) and date +%s through V.Fs effects; the
  cluster files (cluster.env, port, kubeconfig, discovery.conf,
  vcluster.yaml, host kubeconfig) through File writes, owner-only ones
  chmod 600. Mac (2026-11-20): create with a worker, delete, snapshot,
  restore all pass; a symlink planted in a cluster folder is removed,
  its target kept. Third batch merged: no curl left (the cache check is
  a TCP GET in Bend; /livez goes through bend-kube-runtime's client on
  the cluster kubeconfig, verified against the cluster CA where curl -k
  was not); join-token Secrets are applied, listed and deleted through
  the same client (server-side apply, field manager vk8s). Mac
  (2026-11-20): node add joins with a client-made token; token create,
  list (table and JSON) and delete work, and deleting a missing token
  reports the API's 404. Fourth batch merged: vk8s list and the
  cluster.env settings read in Bend (V.Fs.ls, the file itself,
  bend-vmm's status json, the kubeconfig's current context; only date
  +%z for the UTC offset stays a process); the Mac's old and new list
  output (table and JSON, a hibernated and a connected running cluster)
  are identical. Fifth batch merged: describe and logs in Bend (output
  identical to the old shell scripts on the Mac, logs byte for byte);
  upgrade's stale worker Nodes go through the client (Mac: 2 workers to
  1 deletes worker-2's Node); whole files read through Vk8s.read_text
  (Vk8s.slurp stops at 4 KiB, so list lost the current context of a
  larger kubeconfig). Sixth batch merged: classic mode's host namespace
  (Terminating waited out, created with vcluster's created annotation)
  and its host Services and Endpoints through the client on the host
  kubeconfig (Mac: a classic cluster on a vk8s host cluster comes up,
  the namespace annotated, delete removes it). Seventh batch merged: the
  classic service CIDR probe (vcluster isInRange) through the client, so
  classic create runs no kubectl (Mac: 10.96.0.0/12 found on a vk8s host
  cluster, no probe Service left). Eighth batch merged (d001c46,
  2026-11-24): node delete drains through the client (src/cli/drain.bend,
  71 laws from kubectl v0.36.3's drain library and vcluster's delete.go,
  laws/done/drain): cordon, pods in pages of 500, DaemonSet and mirror
  pods skipped, evictions with a 5 s retry on a 429, a wait per pod; a
  Node read that fails other than 404 now stops the command, as vcluster
  does. Snapshot and restore stage in Bend (mktemp, cluster.env copy,
  metadata.json from Cli.snapshot_meta, the 1 MiB format check and the
  open-format decompress through Unz); the VM stop scripts were already
  gone (6a6009f). Mac (2026-11-24, 3 nodes, isolated HOME): a drain past
  a PodDisruptionBudget evicts and reschedules the pod and removes the
  node with no kubectl process; --drain=false cordons and deletes; a
  VM-format snapshot (mode 0600, metadata.json, cluster.env, data.img)
  restores under a new name with its ConfigMap; an open-format one too.
  Stays a process: the tar calls of snapshot and restore (Bend has no
  gzip compressor and no effect that reads or writes a file's holes, so
  a sparse disk cannot be archived without them). Ninth batch merged
  (1ca1d0e): the test checks (Vk8s.st, following a final symlink as test
  does), cluster.env's worker lines (Cli.env_workers), certs check's
  output file by request ID, the join command's CA through the base64
  module (Cli.ca_data), date +%s, the binary's own path, the O_NOFOLLOW
  share read, and classic delete through the client (Cli.cleanup.*,
  from vcluster's delete_helm.go; it now prints "Successfully deleted
  virtual cluster namespace NS"). Tenth batch merged (f20bb14): clones
  through Hvf.clone (cp stays for a symlinked source and a volume that
  cannot clone), arch and OS without uname (Cli.machine, Cli.os_of),
  mkdir and the exclusive mkdir 700 of a reservation, rm -rf, the port
  pick (Cli.port_in), the host kubeconfig's absolute path
  (Cli.abs_path, sh's logical cd), file reads that follow symlinks, and
  the kubeconfig write (temp file 0600, rename). Mac (2026-11-24,
  isolated HOME): batch 9's eight checks pass (the kubeadm CA hash
  equals openssl's; a classic create and delete leave no host Service,
  lease or namespace); batch 10 with logging wrappers around cp, uname,
  grep, mkdir, rm, cat, mv, chmod, mktemp, dirname and basename: a
  3-node create logs one call (rm -f in the VMM launch script), connect
  into a symlinked kubeconfig none. Still a process in macOS VM mode,
  with the reason: tar for snapshot and restore and the perl and gzip of
  the open format (no gzip compressor, no effect for a file's holes);
  du for assets prune and cache status (Hvf.size_kib reads 0 for a
  copy-on-write clone); date +%z (no UTC-offset effect); ps for assets
  prune (no process-list effect); curl and shasum for the asset fetch
  (the fetch of OpenSSL itself cannot use the TLS it brings); sh and
  nohup to start a VMM; cp as the clone fallback; and the user's own
  command of `connect -- CMD`. The macOS node host still runs test,
  grep and rm for container clusters. Guest half (merged 2026-11-25,
  from feat/guest-no-busybox): a running node starts no busybox
  process. PID 1 does itself the busybox command lines of the plans it
  knows (src/guest/sysop.bend Sysop.of, laws sysop.*: mkdir -p, rm -f,
  hwclock -s -u, killall -STOP/-KILL of a daemon it supervises, fstrim
  -v; the plans and their laws are unchanged, any other command line
  stays a process), trims the logs itself (Gs.trim_logs, in place of the
  `sh -c` loop each minute), and starts each Go daemon with GOGC and
  GOMEMLIMIT in its environment (Proc.start_env) instead of under
  `busybox env`. The snapshotter makes, removes and renames, probes
  (test, mountpoint, ls), mounts (LoopDev.mount, bind), unmounts,
  measures a Usage (a walk by lstat in place of `sh -c 'du && find |
  wc'`) and reads a small layer in place of tar, all through
  host/gsys.bend: eleven system call effects in host/effs/gsys.c, a
  loop mount of a file in pack_loop.c and the environment in proc.c
  (bend-vmm's V.Fs cannot be linked into PID 1: hvf.c's constructors
  block SIGTERM and set BENDRTS). tests/gsys.sh checks the effects
  against mkdir, test, ls, du, find, rm, mv and tail. Mac (2026-11-25,
  one VM node, the same host binary, scripts/bench/guest-spawns.sh):
  over 5 idle minutes with one nginx pod the snapshotter's busybox
  processes go 349 to 0 (336 were Usage's shell), PID 1's busybox steps
  35 to 0, the guest's forks 2894 to 1459 and its busy vCPU ticks 1838
  to 1342 (2.2% of all vCPU time after); the first nginx pod costs 51
  snapshotter processes before and none after, a repeat pod 7 and none,
  the boot 219 and none. Pod start is no worse: containerd's
  RunPodSandbox to StartContainer, median of 20 repeat pods, 239 ms
  before and 234 ms after (scripts/bench/cri-start.py); kubectl run to
  Ready with a varied gap, mean of 20, 1047 and 1036 ms (the kubelet
  reports a started container at its next relist, so without the gap
  the times sit in two groups 320 ms apart). Pause, resume (the wake
  sets the clock and restarts kube-controller-manager) and delete pass;
  at tick 600 fstrim.log reads "/var/lib/vcluster: 16713838592 bytes
  trimmed"; the guest clock is within 1 s of the host after 11 minutes.
  After the merge (Mac, the merged build and its guest assets): a
  node with VK8S_PACK=0 loop-mounts its layer images from the share
  through LoopDev.mount and reads a pod's root cold in about 1.0 s (271
  ms from the pack), and a 2-node cluster runs nginx and comes back
  from pause and resume with both nodes Ready. Not run on a VM: the
  trim of a log past 32 MiB (tests/gsys.sh covers it) and the bind of
  an older store's directory; a node container and the node host run
  in CI's container jobs. Checked off: what is left runs once per
  boot, wake, day or snapshot, not while a node works. Still a process in the guest,
  and when: the wake's wait for the node leases (`sh -c` around kubectl,
  once per wake), the daily certificate check (`sh -c` around kubeadm
  and awk), the boot's mounts, insmod, `sh -c` steps and `umount -a -r`
  at power-off (once each), a node container's loop links (one ln when
  its snapshotter starts), open-format snapshots (sh), and the native
  host's mkdir at boot.
- [x] Every module proven: laws/done markers for backend,
  container_host, ctr, nodehost, layers_pb and layers_state (add4c3a).
  Every law already had a proof; each file printed ALL PROOFS CHECK on
  the Mac, and CI run 44729979858's check (ratchet) and verdict (the
  BendTT kernel recheck) passed.
- [x] Idle sleep everywhere (1cfa87e): container clusters on the macOS
  node host get an idle proxy in front of their node-host port and sleep
  (their containers frozen, an `asleep` marker, Nh.asleep_file); when
  every node-host cluster sleeps the VM hibernates; anything that needs
  the node host (Vk8s.nh.running, a cluster's pause or resume) resumes
  it first, so a sleeping node host is never booted again, and `vk8s
  list` reads it without waking it. Mac (2026-11-20): two container
  clusters, VM 1985 MB awake, 11 MB after 150 s idle (both paused,
  "hibernated":true); one kubectl through na's kubeconfig answered in
  1.8 s, the VM awake (534 MB), na running and nb still paused, na's
  pods 0 restarts; both deleted, the node host stopped. Fast-lane CI
  44754226628 green. Native clusters do not sleep (user decision).
- [x] Deep sleep (ce108dc, cc9916b; bend-vmm 0x00283932): `vk8s pause`
  and idle sleep hibernate each VM (Idle.hib_line: `hibernate
  <vmdir>/hibernate.snap` through V.Vmm.ctl), control plane first, and
  pause one whose hibernate fails; native clusters pause as before.
  `vk8s list` and `describe` show `hibernated` (status json
  "hibernated":true). Laws idle.hib_line, idle.hibernated_*,
  idle.vm_dirs_*. Mac (2026-11-20, sqfs-arm64 assets, 1 worker, 2 nginx
  pods): 1637 MB awake (control plane 1129 + worker 508) to 14 MB asleep;
  pause 3.1-3.3 s with the controller stop; readyz 0.35-0.6 s after
  resume; pods 0 restarts, nodes Ready, the Service answers; the
  hibernate files gone; a second round incremental. Awake again: 478 MB
  (pages come back as the guest touches them). Idle stays "no API use
  for N minutes" (README, Sleep when idle); no busy check (user
  decision). Reclaim before hibernate measured and not added: after an
  image burst, a forced memory.reclaim dropped the guest's page cache
  from 1.1 GB to 105 MB but the VMM's footprint stayed (1182 vs 1190
  MB; the freed pages return only through free page reporting), so the
  hibernate wrote as much (1.8 s +1266 MiB plain, 2.2 s +1335 MiB
  reclaimed); the guests' own 30 s idle reclaim covers a quiet cluster.
  Disk while asleep: about the VMM's footprint, sparse, back on wake.
  Fast-lane CI 44745953777: check and verdict green.
- [x] Auto balloon: measured, not adopted. bend-vmm 0x9f122a1b's
  `--balloon auto,max=75` (branch feat/balloon-cap, Cli.balloon_cap.v2,
  895b698, not merged) against plain auto on the Mac (2026-11-20, guest
  assets sqfs-arm64, idle, phys_footprint at 2/4/6 min): a 1-node
  cluster 1071/1093/1108 MB plain vs 1082/1102/1115 MB capped; a
  cluster with 1 worker, worker 525/527/533 vs 508/521/528 MB, control
  plane 1093/1113/1118 vs 1102/1114/1127 MB. No saving beyond noise:
  free page reporting already returns an idle guest's free pages, and
  an idle control plane uses more than half its 2 GiB, so the 50% cap
  never binds. Revisit for a VM that keeps memory free that page
  reporting misses (the 6 GiB macOS node-host VM).
- Pin bump to 0x9f122a1b: done 2026-11-20 (host/vk8s.bend,
  host/layers/{unpack,fill}.bend), CI run 44719276269 green; Mac smoke
  on the new binary: create 11 s, nginx Ready on /mnt/layers lowerdirs,
  pause/resume with the pod Running, clean delete.
- [x] delete in about 2 s (95bf5db, 2026-11-24; found by the round-1
  benchmark: 16.3 s against 0.5 s for a k3s VM in lima). delete pressed
  each guest's power button and waited for a full shutdown (up to 60 s)
  before removing the disks it had just let the guest sync. vcluster's
  docker driver stops a container it deletes with `docker stop -t=1`
  (pkg/cli/delete_docker.go), so delete now presses the button, waits
  1 s, then quits and kills the VMM (Vk8s.end_vms); pause, stop and node
  delete keep the graceful path. Mac: 2 nodes 2.1 s, 1 node 1.5 s, no
  VMM and no cluster dir left.
  - What is left against k3s in lima (1.5 s to 0.3-0.5 s) is that one
    second, kept on purpose: it is vcluster's grace, and it lets the
    guest flush before its disk goes. `limactl delete -f` kills the VM
    at once. Not a defect; no change planned.
- [x] A host without OpenSSL 3 says so (f9c2050, 2026-11-24; found on a
  Mac that had never had Homebrew's openssl@3). bend-kube-runtime loads
  libssl and libcrypto at run time; without them `vk8s create` succeeded
  and said nothing while the image cache answered 502 to every node and
  every layer fill failed, so both default-on features were off, and
  `certs rotate-ca` rotated the CA and then died. Now create, cache
  start and the two serve logs warn with the cause and the fix
  (Cli.tls_degraded), and token, node add, certs rotate and classic
  create stop before any change (Cli.tls_needed); laws cli.tls_*,
  cli.host_mac.*. Open until a release carries them: OpenSSL 3 as a
  hash-pinned darwin host asset (scripts/host-openssl.sh,
  Manifest.host_darwin, Assets.host_fetch, Cli.tls_env; docs/ref/
  macos-tls.md), so a Mac needs only the binary. Not yet run on a VM:
  the warning at create and the shipped-library path.
- [x] Cold pulls about twice as fast (ebf32a8, 2026-11-24; found by the
  round-1 benchmark: first nginx pod 12.0 s against 7.5 s for k3s in
  lima). Per blob the image cache opened three TLS connections and
  fetched its own token (about 1.07 s whatever the size: registry TCP
  and TLS 220 ms, the 401 110 ms, the token 160-330 ms, the registry
  again 230 ms, the redirect 120 ms, the CDN 40 ms); the index, manifest
  and config came one after another (2.8 s before any layer); the
  layers ran as two halves, both big ones in the same half. Now one
  session per process keeps connections per host (at most 8, idle 30 s)
  and tokens per origin and scope until 10 s before they expire
  (Auth.cache.*, general laws oci_auth.cache.put_find and .only_key: a
  token is never found under another host or scope); the layers go
  through one queue, biggest first, 4 lanes (Fill.order.v5,
  Fill.lanes.v5); a checked manifest prefetches what the pull asks next
  (Pull.prefetch.v5); a HEAD of a missing manifest fills instead of 404;
  the cache's loop waits for events instead of polling every 50 ms.
  Digest checks, the token realm check and the redirect rules are as
  before. Mac, 3 runs each: cold nginx fill 9.7-10.1 to 5.0-5.6 s (the
  two big layers alone take 3.8 s at this link's 18 MB/s), a small blob
  0.9-1.0 to about 0.15 s, first nginx pod 12.5-14.4 to 7.4-9.1 s, node
  Ready 34-46 to 22-26 s. CI 45430261096 (main, full lane): all jobs.
- [x] CoreDNS comes up with the node (8ba9e3b, 2026-11-24).
  flannel's install-cni wrote the CNI config before flanneld wrote
  /run/flannel/subnet.env: the node went Ready, CoreDNS's first sandbox
  failed ("failed to load flannel 'subnet.env'") and the kubelet's
  pod-worker backoff retried 12-19 s later, on every create. Now
  flanneld's own container installs the config (a rename) once
  subnet.env is not empty, and the init container only removes a stale
  one when subnet.env is missing (a reboot empties /run)
  (scripts/guest/flannel.yaml; only vk8s.cpio changes). Mac, 3 cold
  creates each: CoreDNS Available 41-48 to 33-37 s from create, node
  Ready 19-27 to 27-29 s (it now waits for the lease), sandbox failures
  1 a run to 0; 3 nodes with pod-to-pod traffic both ways, all flannel
  pods deleted, pause and resume, a reboot, and an upgrade from the old
  manifest all keep networking. CI 45441651253: every job; the
  regression subset 43/0 in the five VM and container modes, native
  42/0 (its count). One zombie ([mv]) stays per flannel container
  start: flanneld is PID 1 there and does not reap. On main with assets
  built from it: node Ready 26.6 and 26.7 s, CoreDNS 35.3 and 33.2 s,
  first nginx pod 7.5 and 6.4 s.
- CI flake census (2026-11-24; 728 runs since 2026-11-07, 414 failed
  jobs read, about 80 of them flakes or infrastructure). The flannel
  crash-loop, the "open flake" above (flannel restarts, coredns not
  Ready), was the kube-router and kube-proxy race fixed on 2026-11-21:
  21 in 1157 cluster-creating jobs before 90343ee, 0 in 287 after.
  Live when counted: classic mode's in-place resize test reading stale
  status (11 of 229), the syncer envtest's second etcd on a port in the
  ephemeral range (12), the load envtest's 10 s limit (6), the
  websocket log test with the layer store on (2 of 8 on 2026-11-24),
  `vk8s list` showing a Ready node-host cluster as stopped (3). The
  subnet.env ordering above explains none of them. Fixes are on the
  branches feat/classic-resize-gen, feat/deflake-tests and feat/ws-logs.
- Proposal, waits for the user's decision (2026-11-24): layer images on
  one "pack" disk instead of the 9p share. Why: a node reads a layer
  through loop, squashfs and 9p, and the guest's 9p sends one 4 KiB
  read per page whatever msize says. On macOS bend-vmm
  0x2cb44898b57f05c48f38583063e077bf (8d70fc6; pin bump pending its CI)
  routes a device's interrupt to the vCPU that asked: 28.6 to
  4.4 ms/MiB from the second vCPU, node.img read whole 3.8-4.0 to
  2.1-2.2 s against 1.5-1.7 s on a virtio disk. On Linux KVM it changes
  nothing: a request costs three exits (about 260 us nested), so the
  same read takes 15.7-18.4 s over 9p against 1.9-4.3 s on a disk, and
  CI read small layers at up to 200 ms/MiB (run 45447343443). The pack
  disk (bend-vmm session's evaluation, measured with a stand-in image):
  one read-only virtio-blk per VM whose content is the layer files one
  after another; `pack add PATH` appends a file at the next aligned
  offset, grows the capacity and answers OFFSET LENGTH; the guest
  mounts it with a loop device at that offset; `pack drop OFFSET` makes
  a range dead and never reuses it. Whole node.img: 1.74-1.79 s on
  macOS (a plain disk 1.76 s) and about 1.8 s on nested KVM, in about
  42 requests against 24,500 over 9p. Cost: 3-5 days in bend-vmm (the
  table, the read split and the commands in Bend with laws; C only to
  open, stat and close a file in a small descriptor cache), then the
  vk8s side: the snapshotter asks the host to add a layer and mounts by
  offset (util-linux losetup or LOOP_CONFIGURE for the size limit), gc
  drops after the unmount, snapshots carry the table. Decided by the user
  2026-11-25: build it, after the next release; the bend-vmm session has
  the go-ahead for its side. The vk8s side: "The pack disk, the vk8s
  side" at the end of this list.
- [x] A container's first exec does not wait on the share (45e2c51,
  2026-11-25). With the layer store on, a container was Running 26 to
  143 ms before its first process could exec: the first read of a layer
  image goes through loop, squashfs and the 9p share, uncached, so the
  upstream test that reads a pod's log once right after Running got
  nothing (2 of 8 runs on 2026-11-24; in a loop on the Mac 30 of 30
  empty reads with the store on, 0 of 30 off). The snapshotter now reads
  a layer image of at most 8 MiB once when it mounts it, and answers the
  Prepare afterwards (Spb.warm.v6, Lay.warm_args.v6; laws
  layers_pb.warm_*_v6, layers_store.warm_args_v6): 0 of 30 empty reads,
  a busybox pull 80 ms longer. A Prepare back from that read is
  answered, not probed again: in a node container `mountpoint -q` did
  not report the mount just made, and each return mounted and read the
  image once more until no loop device was left (4093 on 15 images in
  CI run 45447343443). A failed image mount no longer leaves an empty
  mountpoint that a later Prepare took for the layer. A failed
  regression job uploads its nodes' containerd, kubelet and snapshotter
  logs. CI 45538127456: every job, container-smoke with the store on
  included. bend-vmm 0x2cb44898b57f05c48f38583063e077bf (f837993) is the
  other half on macOS: a device's interrupt goes to the vCPU that asked
  (a 9p read from the second vCPU 28.6 to 4.4 ms/MiB, its numbers).
- [x] The node host answers once its list is right, and its disk goes
  with its last cluster (3229956, 2026-11-25). `vk8s list` showed a
  container cluster on the macOS node host as stopped for up to 26 s
  after create: PID 1 wrote share/runc-list before runc had registered
  the container, then only every 30 ticks. A request is now answered
  when the list shows its effect (Nh.want, Nh.settled; up, join, down,
  pause, resume; at most 30 s, then failed). When the last container
  cluster is deleted and no VMM lives, the node host's directory is
  renamed and removed (Nh.stop_due, Nh.reclaim; laws nodehost.want,
  .settled_*, .stop_due, .reclaim*): 619 MiB to nothing on the Mac,
  list right at +0.2 s in 3 of 3 creates, pause and resume shown at
  once. CI 45517032748: every job, nodehost-smoke with a 5 s bound.
- [x] An image is not kept twice (b55a1db, 2026-11-25). On a node with
  the layer store nothing reads the cache's layer blobs after a fill (a
  second cluster started nginx in 1.26 s; 35 of 35 layer sidecars
  untouched). When a fill publishes a layer it sets the blob's last use
  in the cache to 72 h less 10 min ago, so the hourly sweep removes it
  (Store.lapse.*, laws oci_store.lapse.*): after nginx, cache store 151
  to 0.14 MiB with the layer store at 445 MiB; a cluster without the
  store then refetches what it asks for. CI 45517033515: every job.
- [x] A restore lists the nodes that exist (1081292, 2026-11-25). An
  open-format restore under a new name kept the old cluster's Nodes,
  NotReady for good, with their pods listed Running; a VM-format
  restore booted workers 1..NODES whatever WORKERS said. Now the
  snapshot's worker indices boot and the stale Nodes are removed through
  the client with vcluster's line "Removing node X from vCluster Y"
  (Cli.nodes_stale, Cli.restore_stale; create_docker.go's
  ensureVClusterNodes). An open restore with the layer store on never
  reached the kubelet ("snapshotter not loaded: bend"): PID 1 used the
  bare restore plan; it now gets the wrappers every boot gets. The
  OpenSSL warning was seen on a real create (before the cache starts,
  first line of both logs, the cluster comes up); its fix text now names
  a loader variable that is set. CI 45538622963: every job, kvm-smoke
  with an open snapshot restored under a new name.
- Guest kernel 6.18.65 and a mirror of the pinned inputs (3b7d387,
  fe9fc7b, 2026-11-25). Alpine dropped linux-virt-6.18.64 on 2026-11-24
  and every guest build 404ed. The pins and the 16 KiB kernel are on
  6.18.65 (same config; the packages byte-identical on two mirrors and
  matching APKINDEX). The pre-release `guest-inputs` of this repo holds a
  copy of every hash-pinned input with one upstream (the Alpine
  packages, the 52 Debian packages, the Kubernetes, gVisor and
  kube-router archives, the CA bundle: 63 files, 856 MiB); each fetch
  tries upstream, then the copy, the pin checked for either, a mismatch
  failing at once; CI's check job fails when a pin has no copy.
- Classic resize (d8f1e38) and the test harness (b551b57), 2026-11-24:
  a virtual pod's observedGeneration is held while a resize is pending
  (Classic.obs_target_r; laws classic obs_resize_*), as vcluster copies
  the host's; the trigger in CI was not identified. The envtests' ports
  are below the ephemeral range and checked free, the load test starts
  its delete after a resync tick (the 10 s failures were ticks inside
  the delete), sleeps before assertions became waits, and
  scripts/regression.sh prints each failure's message. Seen since, once
  (main 3b7d387, classic): the resize test's pod never started on the
  host cluster, RunContainerError "context deadline exceeded"; passed on
  a rerun; the node logs that would explain it are uploaded from now on.

- [x] The pack disk, the vk8s side (branch feat/pack-disk, 2026-11-25;
  closed 2026-11-27: CI's KVM jobs ran it, run 45719495574 and every
  run of main since, and the long suites ran on it for release
  v1.36.6-229e3489: regression 43/0 and certified conformance 450/0 in
  both modes, the soak and the 24-hour uptime run, section 6). A VM node mounts its layer images from bend-vmm's pack, not
  through the layers share (src/layers/pack.bend, laws/layers_pack.bend,
  92 laws, all proposed; docs/ref/layers-sqfs.md, "The pack disk").
  bend-vmm is 0x2324e729258ea5021b37b97947af4c3f.
  - Host: a VM on the layer store starts with `--pack layers`,
    VK8S_PACK=<vm> on the kernel command line (its folder under
    ~/.vk8s/clusters) and a new random key in its share (pack.key).
    VK8S_PACK=0 in the host's environment leaves them out. Every VM
    mode host gets it, Linux KVM too (one code path; only macOS was
    run here). Node containers, native nodes and the node host VM keep
    the share or the per-node unpack.
  - Who adds: the layer filler (`vk8s layers serve`). It knows the
    store and reaches every VM's control socket; the guest reaches it
    already. Two new lines on its port: `pack <vm> <key> <chain>`,
    answered `at <offset> <length>` after `pack add PATH` on that VM's
    control socket, and `drop <vm> <key> <chain>`, answered `ok
    dropped` after `pack drop` of every live entry of the image. Any
    pod can reach the port, so the filler takes a line only with the
    key in that VM's share, which only the node's root reads.
  - Guest: the snapshotter uses the pack when VK8S_PACK is set, a disk
    has the serial `layers` and the share has the key. It mounts the
    range it is told through a loop device with the offset and a size
    limit (LOOP_CONFIGURE in a C effect, host/effs/pack_loop.c:
    busybox has no size limit for a block device). No answer, a "no"
    or a failed mount ends in the mount from the share. When no
    snapshot stands on a layer any more it unmounts the layer and
    sends the drop line; without a pack a layer stays mounted, as
    before. It writes layers.held at its start now (a cluster restored
    under another name had none until its next pull).
  - gc: a layer that is live on any VM's pack counts as held
    (`status json` of every VM folder, at the plan and under the
    layer's lock; a hibernated VM answers it too).
  - Compatibility, each run on the Mac with an nginx pod: this binary
    with the guest assets of main (they ignore VK8S_PACK and the
    disk), main's binary with these assets ("pack: none (no
    VK8S_PACK)"), and these with main's binary as the filler (36 lines
    answered "no not a valid ask"): 36 loop devices on the share each
    time, the pod Ready.
  - Run on the Mac (Apple M5 Pro, macOS 27.2.1, local guest build):
    36 layers of a one-node cluster on /dev/vde (after base, data, node
    and control-plane), each loop device with its offset and size
    limit; a worker's 22 on its own pack; the nginx image removed: 7
    layers unmounted, 7 entries dropped (36 live to 29), pulled again:
    7 new entries; `create --upgrade` and a reboot from inside the
    guest: the pack empty, then the 36 layers of the saved state added
    again at boot; `pause` (hibernate) and `resume`: the table kept (36
    live), a pod's 200 MB read whole afterwards; a VM-format snapshot
    restored under another name: 35 layers on the new VM's pack; gc
    with an expired layer nothing holds: kept while live on a pack,
    removed after its `pack drop`; delete: no VMM left.
    tests/layers_serve.sh has the two lines against a stand-in control
    socket (tests/lib/pack_ctl.py; its checks pass on the Mac against
    the real filler, CI runs them on Linux).
  - Measured (3 clusters with the pack, 3 with VK8S_PACK=0,
    alternating; scripts/bench/pack-read.sh): a cold read of an nginx
    pod's root file system (200,192,000 bytes, the node's caches
    dropped, 9 reads each) 240 ms (228 to 278) from the pack and 1952
    ms (1785 to 2170) through the share; warm 70 to 72 against 80 to
    85 ms. The first nginx pod is Ready in 1035 to 1098 ms against
    1051 to 1096, a repeat pod in 571 to 644 against 598 to 641:
    no change (nginx reads little to start). The filler answers a pack
    line in 1 to 3 ms; with a `status json` before each add it was 62
    to 95 ms (bend-vmm's `status json` takes about 73 ms), so that
    build's add did not look the image up first (it does now, with
    `pack list`, below).
  - bend-vmm fault found on the way, fixed there: with
    0x51718d1816cd36f20955e9590377c5e5 a guest reset after a hibernate
    and a resume ended the VMM (`vk8s pause NAME`, `vk8s resume NAME`,
    then `reboot -f` in the guest: vmm.log had "bend-vmm: reset", then
    "bend-vmm: cannot join the LAN in <dir>/lan (48; ...)", and the
    process was gone), with or without --pack. Cause: on macOS the
    reset's exec started the new image while the old one's threads
    still held the LAN socket and the disk. Fixed in bend-vmm 9b7dda8;
    vk8s is on 0x2324e729258ea5021b37b97947af4c3f, where the same steps
    log "bend-vmm: reset", the VMM keeps its process and the node is
    Ready again (Mac, 2026-11-25).
  - With that pin the filler reads a pack's table with `pack list`
    (under 0.1 ms; `status json` took 15 to 70): an add first looks the
    image up and answers the entry it has, so an image is on a pack
    once (Pack.list.v8, Pack.held.v8, laws layers_pack.list*,
    layers_pack.held.*).
  - Not done: a snapshotter that starts again inside a running VM does
    not look for a layer mounted but not held (one whose Prepare was
    cut off); a drop line that is lost leaves its entry live until the
    VM stops (gc keeps the layer meanwhile); the long suites
    (regression, conformance, soak) and Linux KVM were not run.

## 12. Host-integrated workloads

Added 2026-11-25: a VM node can host a workload that works on the host's
files, talks to a program on the host and brings its own container
runtime (until now such a workload needed a distribution VM with its own
Kubernetes).

- [x] `vk8s create --mount HOSTDIR[:rw]`, `--host-socket
  GUESTPATH=HOSTPATH` and `--node-setup SCRIPT` (VM backend; README
  "Host-integrated workloads"). src/cli/extras.bend decides the flags,
  the cluster.env record (`MOUNT_<i>`, `HOST_SOCKET_<i>`, `NODE_SETUP`),
  each VM's bend-vmm flags (`--share DIR,tag=m<i>[,ro]`, `--vsock
  <vm dir>/vsock`), the links `<vm dir>/vsock_<100+i>` to the host
  sockets and the node's share file `node-extras`;
  src/guest/extras.bend reads that file and puts the 9p mounts (by
  path length, so mounts nest), the socket proxy and the script before
  the plan's containerd daemon, and with a script makes containerd's
  config import `/etc/containerd/conf.d/*.toml`; PID 1 then has
  `/usr/local/bin` first on its children's PATH. No path goes on the
  kernel command line. host/host_socket.bend is the proxy (the guest
  binary's `host-sockets` mode, a supervised daemon): a Unix listener
  per socket, mode 0666, each connection to AF_VSOCK CID 2 and copied
  both ways in Bend, a half-close passed on; host/effs/vsock.c holds the
  two system calls Bend lacks (the AF_VSOCK connect and
  shutdown(SHUT_WR)). The container and native backends and classic
  mode refuse the flags. No bend-vmm change: its `connect` follows the
  link, so a host path with spaces or longer than a socket path works.
  Laws extras.* (38, all proven; laws/done/extras), tests/extras.bend
  (45), tests/node_extras.sh on the Mac (one cluster, 107 checks: after
  create, after pause and resume, and after create --upgrade, then
  delete). By hand: a script that exits 7 gives create's warning and
  the node starts; `--mount none --node-setup none` on an upgrade
  empties the record; `--backend container`, `--host-kubeconfig` and a
  missing directory are refused before anything is made.
  Found on the way:
  - The node's root is a tmpfs, so the script writes /usr/local/bin,
    /etc and /var/lib; it is rebuilt at each boot (the script runs
    again) and what it installs is guest RAM. /var/lib/vcluster is the
    data disk.
  - Ownership over 9p: bend-vmm reports the host's uid, gid and mode,
    and the guest kernel checks them. A pod as the Mac user's uid
    (501:20) creates, writes and chmods in a `:rw` mount; root does too;
    every file belongs to the Mac user on both sides whoever made it; a
    chown succeeds and changes nothing; another uid (the pause image's
    65535 too) is "other" to the mode. Nothing needed fixing in vk8s or
    bend-vmm for a workload that runs as the host user's uid or as root.
  - A static Linux binary runs from a read-only 9p mount (every pod of
    the test runs the mount's busybox).
  - A copy of containerd-shim-runc-v2 named containerd-shim-extra-v2 in
    /usr/local/bin serves `runtime_type = "io.containerd.extra.v2"`, and
    containerd 2.2 merges a drop-in's runtime table into the cri plugin's
    (the default runc runtime and the CNI settings stay).
  - Not done: the flags on Linux KVM hosts were not run (the code is the
    same; `vk8s vmm` there takes the same flags); a multi-node cluster
    was not run with them (workers get the same flags, links and share
    file through the same code); bend-vmm's 9p serves regular files and
    directories only and follows no symbolic link on the host side (a
    link inside a mount resolves in the node, which works when its
    target is under a mount too); the proxy moves bytes as Bend lists
    (the test sends 1 MiB whole; its speed was not measured); a proxy that
    restarts replaces its socket file, so a pod that mounted the old one
    must restart; the script has no timeout.
- [x] A real host program reached from a pod (2026-11-27, this Mac, the
  release candidate at 56175d4). A one-node VM cluster with `--cpus 2
  --memory 3072 --idle-sleep 0`, `--mount` of the home directory (read
  only) and of one state directory (`:rw`), and `--host-socket` to the
  unix socket of a sandbox service that runs on the Mac. A pod as the
  Mac user's uid (501:20), with the home directory, the state directory
  and the socket's directory as hostPath volumes, ran the service's
  Linux client from the read-only mount: the service on the Mac booted
  a microVM, the client streamed its output for 20 s through the
  socket proxy and exited 0 (21.8 s in all, the same as the Mac's own
  client). The client wrote its files to the `:rw` mount.
  Not run: the whole workload that this section was made for. Its
  node-side runtime shim and its controller build only against an older
  release of that service, and that release does not start a guest on
  this Mac (macOS 27.2; "guest session connection timed out"), while
  the two newest releases start one but do not compile them. So
  `--node-setup` with that shim (a pod whose runtime class makes the
  shim start the microVM) was not run here; tests/node_extras.sh covers
  the script, the drop-in and a second runtime with stand-ins.
  - Run 2026-11-27 on release v1.36.6-229e3489, after the workload's
    shim and controller were ported to the service's current release:
    its own start script made the cluster (4 vCPUs, 8192 MiB,
    `--idle-sleep 0`, the home mount, a `:rw` state folder, one host
    socket, `--node-setup`), the setup script installed the shim and its
    containerd drop-in, and a pod with that runtime class started a
    microVM on the Mac through the shim, printed its output and
    Completed in 28 s. `kubectl exec` into such a pod worked; deleting a
    running one stopped and removed the microVM; `create --upgrade`
    after a rebuilt shim ran the setup script again and kept the data.
    The decision that was open here is closed.
  - Found by it, in vk8s: the guest root has glibc and no
    `libgcc_s.so.1`, which nearly every Rust or C++ program loads, and
    `/usr/lib` and `/lib` are read-only, so a setup script cannot add
    it (it failed with "Read-only file system", and `vk8s create`
    said only that the script exited 1). The workload now links its
    shim statically and wraps its client with `LD_LIBRARY_PATH`. To do
    in the next asset release: Debian's `libgcc-s1` in the guest root
    (scripts/guest/debs.py --lock), and README's lines on what a
    setup script can write naming the library folders as read-only.
