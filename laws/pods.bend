import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/translate/pods.bend as P
import ../src/translate/meta.bend as M
import ../src/translate/names.bend as N

# Spec for src/translate/pods.bend (vcluster pkg/controllers/resources/pods:
# translate/translator.go, diff.go, hosts.go, hostpath.go, envvars.go,
# token/sa_token_secret.go, syncer.go).
#
# The concrete laws transcribe every case of translate/translator_test.go,
# translate/diff_test.go and syncer_test.go (vcluster a8ab30e). Expected
# values are the Go tests' literals, or the vcluster calls the tests make
# to build them (translate.HostLabel, HostLabelNamespace, Default.HostName,
# mappings.VirtualToHostName), written with the same Bend functions. Where a
# test checks the state after a sync, the law states the writes that lead
# to it. Objects compare in canonical form (Pods.norm: members sorted, null
# members and empty arrays dropped), as Go compares structs.
#
# Fixtures follow vcluster's test harness: target namespace "test", current
# namespace "vcluster", vcluster name "vcluster" (so the workload service
# account is vc-workload-vcluster and the host path root is
# /tmp/vcluster/vcluster/vcluster), host version 1.31 in the syncer tests.
# translate.VClusterName is "suffix" in the translate package tests and in
# TestSyncTable, and "vcluster" from TestSync on (TestSync sets it).
#
# JSON fixtures are written with ` for ".

# Test fixtures.

def Laws.pods.j.r(r: Result<&2, &2, String, J.Json>) -> J.Json:
  match r:
    case Done{x}:
      x
    case Fail{e}:
      J.JNull{}

# A JSON value, written with ` for ".
def Laws.pods.j(s: String) -> J.Json:
  Laws.pods.j.r(J.Json.parse(P.Pods.subst(s, '`', '"')))

def Laws.pods.n(s: String) -> J.Json:
  P.Pods.norm(Laws.pods.j(s))

def Laws.pods.first(j: J.Json) -> J.Json:
  Maybe.default(&2, J.Json, List.head(&2, J.Json, J.Json.items(j)), J.JNull{})

def Laws.pods.fst(r: J.Json & J.Json) -> J.Json:
  (a, b) = r
  a

def Laws.pods.snd(r: J.Json & J.Json) -> J.Json:
  (a, b) = r
  b

def Laws.pods.pn(r: J.Json & J.Json) -> J.Json:
  (a, b) = r
  P.Pods.norm(J.Json.obj([J.KV{"virtual", a}, J.KV{"host", b}]))

def Laws.pods.mn(m: Maybe<&2, J.Json>) -> J.Json:
  match m:
    case None{}:
      J.JNull{}
    case Some{x}:
      P.Pods.norm(x)

# The harness configuration with translate.VClusterName vc.
def Laws.pods.cfg(vc: String) -> P.Cfg:
  P.Pods.cfg.default(vc, "test", "vcluster")

# The syncer tests' configuration: host version 1.31.0.
def Laws.pods.scfg(vc: String) -> P.Cfg:
  P.Pods.cfg.set_host_version(Laws.pods.cfg(vc), Some{P.Ver{1, 31, 0}})

def Laws.pods.inp0() -> P.Inp:
  P.Inp{[], [], "", "", [], []}

# The syncer tests' inputs: the vcluster service 1.2.3.4, the DNS service
# 2.2.2.2, the virtual nodes, the pod security verdict.
def Laws.pods.sin(nodes: List<&2, String>, ok: Bool) -> P.SInp:
  P.SInp{P.Inp{[], [], "2.2.2.2", "1.2.3.4", [], []}, P.DInp{[], []}, nodes, ok, False{}, None{}}

def Laws.pods.din0() -> P.DInp:
  P.DInp{[], []}

# pObjectMeta of the syncer tests for pod/ns with translate.VClusterName vc,
# with the vcluster.loft.sh/labels annotation la (JSON text) and the extra
# labels xl (JSON members, each after a comma).
def Laws.pods.pmeta(+vc: String, +pod: String, +ns: String, la: String, xl: String) -> String:
  +hn = N.Names.host_name(pod, ns, vc)
  "{`name`: `" ++ hn ++ "`, `namespace`: `test`, `annotations`: {`cluster-autoscaler.kubernetes.io/safe-to-evict`: `false`, `vcluster.loft.sh/labels`: `" ++ la ++ "`, `vcluster.loft.sh/name`: `" ++ pod ++ "`, `vcluster.loft.sh/namespace`: `" ++ ns ++ "`, `vcluster.loft.sh/object-name`: `" ++ pod ++ "`, `vcluster.loft.sh/object-uid`: ``, `vcluster.loft.sh/object-namespace`: `" ++ ns ++ "`, `vcluster.loft.sh/object-kind`: `/v1, Kind=Pod`, `vcluster.loft.sh/object-host-namespace`: `test`, `vcluster.loft.sh/object-host-name`: `" ++ hn ++ "`, `vcluster.loft.sh/service-account-name`: ``, `vcluster.loft.sh/uid`: ``}, `labels`: {`vcluster.loft.sh/namespace`: `" ++ ns ++ "`, `vcluster.loft.sh/managed-by`: `" ++ vc ++ "`" ++ xl ++ "}}"

# The fields of pPodBase's spec.
def Laws.pods.pspec(pod: String) -> String:
  "`automountServiceAccountToken`: false, `enableServiceLinks`: false, `hostAliases`: [{`ip`: `1.2.3.4`, `hostnames`: [`kubernetes.default.svc.cluster.local`, `kubernetes`, `kubernetes.default`, `kubernetes.default.svc`]}], `serviceAccountName`: `vc-workload-vcluster`, `hostname`: `" ++ pod ++ "`"

def Laws.pods.create(s: String) -> List<&2, P.Write>:
  [P.WCreateHost{Laws.pods.n(s)}]

# TestPodAffinityTermsTranslation: the pod is equestria/my-little-pody; the
# translated term and the recorded events.
def Laws.pods.aff(s: String) -> J.Json:
  +t = Laws.pods.j(s)
  P.Pods.norm(J.Json.obj([J.KV{"term", P.Pods.aff_term("suffix", "equestria", t)},
    J.KV{"events", J.Json.arr(P.Pods.jstrs(P.Pods.aff_term_events(t)))}]))

def Laws.pods.aff_warning() -> String:
  "Warning SyncWarning Inter-pod affinity rule(s) that use both .namespaces and .namespaceSelector fields in the same term are not supported by vcluster yet. The .namespaceSelector fields of the unsupported affinity entries will be ignored."

# TestDiffQOSClassPreservation: the QOS classes after Diff.
def Laws.pods.qos(r: J.Json & J.Json) -> J.Json:
  (a, b) = r
  P.Pods.norm(J.Json.obj([J.KV{"virtual", J.Json.at(a, ["status", "qosClass"])}, J.KV{"host", J.Json.at(b, ["status", "qosClass"])}]))

# TestDiffTolerationSync: the pods and the tolerations.
def Laws.pods.tv(tols: String) -> J.Json:
  Laws.pods.j("{`metadata`: {`name`: `testpod`, `namespace`: `testns`}, `spec`: {`tolerations`: [" ++ tols ++ "]}}")

def Laws.pods.tp(tols: String) -> J.Json:
  Laws.pods.j("{`metadata`: {`name`: `testpod-x-testns`, `namespace`: `test`}, `spec`: {`tolerations`: [" ++ tols ++ "]}}")

def Laws.pods.t_initial() -> String:
  "{`key`: `initial`, `operator`: `Equal`, `value`: `v1`, `effect`: `NoSchedule`}"

def Laws.pods.t_new() -> String:
  "{`key`: `new-key`, `operator`: `Exists`}"

def Laws.pods.t_enforced() -> String:
  "{`key`: `vcluster-enforced`, `operator`: `Exists`, `effect`: `NoExecute`}"

def Laws.pods.t_admission() -> String:
  "{`key`: `admission-injected`, `operator`: `Exists`}"

def Laws.pods.t_late() -> String:
  "{`key`: `late-webhook`, `operator`: `Exists`}"

def Laws.pods.tcfg() -> P.Cfg:
  P.Pods.cfg.set_enforced(Laws.pods.cfg("suffix"), [Laws.pods.j(Laws.pods.t_enforced())])

# The host tolerations after Diff(NewSyncEventWithOld(pOld, pNew, vOld, vNew)).
def Laws.pods.tdiff(vo: String, v: String, ho: String, h: String) -> J.Json:
  P.Pods.norm(J.Json.at(Laws.pods.snd(P.Pods.diff(Laws.pods.tcfg(), Laws.pods.din0(), Laws.pods.tp(ho), Laws.pods.tp(h), Laws.pods.tv(vo), Laws.pods.tv(v))), ["spec", "tolerations"]))

def Laws.pods.tols(s: String) -> J.Json:
  Laws.pods.n("[" ++ s ++ "]")

# Pod conditions and versions (diff_test.go).
def Laws.pods.ready() -> String:
  "[{`type`: `Ready`, `status`: `True`}]"

def Laws.pods.ready_gen1() -> String:
  "[{`type`: `Ready`, `status`: `True`, `observedGeneration`: 1}]"

def Laws.pods.not_ready() -> String:
  "[{`type`: `Ready`, `status`: `False`}]"

def Laws.pods.vcfg(ver: Maybe<&2, P.Ver>) -> P.Cfg:
  P.Pods.cfg.set_virtual_version(Laws.pods.cfg("suffix"), ver)

def Laws.pods.cc(ver: Maybe<&2, P.Ver>, vo: String, v: String, ho: String, h: String) -> J.Json:
  Laws.pods.pn(P.Pods.conditions_copy(Laws.pods.vcfg(ver), Laws.pods.j(vo), Laws.pods.j(v), Laws.pods.j(ho), Laws.pods.j(h)))

def Laws.pods.cc_want(v: String, h: String) -> J.Json:
  Laws.pods.pn((Laws.pods.j(v), Laws.pods.j(h)))

# A pod with only a name, a namespace and a status.
def Laws.pods.sp(name: String, ns: String, status: String) -> J.Json:
  Laws.pods.j("{`metadata`: {`name`: `" ++ name ++ "`, `namespace`: `" ++ ns ++ "`}, `status`: " ++ status ++ "}")

# TestDiffPodStatusObservedGeneration: the virtual pod's observed
# generation and conditions after Diff.
def Laws.pods.og(ver: Maybe<&2, P.Ver>) -> J.Json:
  +v = Laws.pods.fst(P.Pods.diff(Laws.pods.vcfg(ver), Laws.pods.din0(),
    Laws.pods.sp("testpod-x-testns", "test", "{}"),
    Laws.pods.sp("testpod-x-testns", "test", "{`observedGeneration`: 3, `conditions`: [{`type`: `Ready`, `status`: `True`, `observedGeneration`: 3}]}"),
    Laws.pods.sp("testpod", "testns", "{}"), Laws.pods.sp("testpod", "testns", "{}")))
  P.Pods.norm(J.Json.obj([J.KV{"observedGeneration", J.Json.at(v, ["status", "observedGeneration"])}, J.KV{"conditions", J.Json.at(v, ["status", "conditions"])}]))

# TestDiffConditionsCacheInformerDivergence: the host conditions after Diff.
def Laws.pods.div(ver: Maybe<&2, P.Ver>) -> J.Json:
  P.Pods.norm(J.Json.at(Laws.pods.snd(P.Pods.diff(Laws.pods.vcfg(ver), Laws.pods.din0(),
    Laws.pods.sp("testpod-x-testns", "test", "{`conditions`: " ++ Laws.pods.ready_gen1() ++ "}"),
    Laws.pods.sp("testpod-x-testns", "test", "{`conditions`: " ++ Laws.pods.ready_gen1() ++ "}"),
    Laws.pods.sp("testpod", "testns", "{`conditions`: " ++ Laws.pods.ready_gen1() ++ "}"),
    Laws.pods.sp("testpod", "testns", "{`conditions`: " ++ Laws.pods.ready() ++ "}"))), ["status", "conditions"]))

# TestDesiredVirtualStatus.
def Laws.pods.desired(ver: Maybe<&2, P.Ver>) -> J.Json:
  P.Pods.norm(P.Pods.desired_status(Laws.pods.vcfg(ver),
    Laws.pods.j("{`phase`: `Running`, `qosClass`: `Burstable`, `observedGeneration`: 5, `conditions`: [{`type`: `Ready`, `status`: `True`, `observedGeneration`: 5}]}"),
    Laws.pods.j("{`phase`: `Pending`, `qosClass`: `Guaranteed`, `observedGeneration`: 2}")))

# TestDiffResourceClaimStatus: the virtual claim statuses after Diff, with
# the host claims mapping back as `back` says.
def Laws.pods.rc(back: List<&2, M.KV>, claim: String) -> J.Json:
  +p = Laws.pods.sp("my-pod-x-default-x-123", "test", "{`resourceClaimStatuses`: [{`name`: `my-claim`, `resourceClaimName`: `" ++ claim ++ "`}]}")
  +v = Laws.pods.sp("my-pod", "default", "{`resourceClaimStatuses`: []}")
  P.Pods.norm(J.Json.at(Laws.pods.fst(P.Pods.diff(P.Pods.cfg.set_claims(Laws.pods.cfg("suffix"), True{}), P.DInp{[], back}, p, p, v, v)),
    ["status", "resourceClaimStatuses"]))

def Laws.pods.rc_want(claim: String) -> J.Json:
  Laws.pods.n("[{`name`: `my-claim`, `resourceClaimName`: `" ++ claim ++ "`}]")

# TestTranslateResourceClaims: test-ns/test-pod.
def Laws.pods.claims(cl: Bool, tpl: Bool, s: String) -> J.Json:
  P.Pods.norm(J.Json.arr(P.Pods.claims(cl, tpl, "suffix", "test-ns", J.Json.items(Laws.pods.j(s)))))

# TestVolumeTranslation: the host volumes and the first container's mounts.
def Laws.pods.vt(hp: Bool, pod: String) -> J.Json:
  +p = P.Pods.translate(P.Pods.cfg.set_host_paths(Laws.pods.cfg("suffix"), hp), Laws.pods.inp0(), Laws.pods.j(pod))
  P.Pods.norm(J.Json.obj([J.KV{"volumes", J.Json.at(p, ["spec", "volumes"])},
    J.KV{"volumeMounts", J.Json.get(Laws.pods.first(J.Json.at(p, ["spec", "containers"])), "volumeMounts")}]))

# TestBuildResizePatch: makePod(memory) and extra containers.
def Laws.pods.rp(+memory: String, more: String) -> J.Json:
  Laws.pods.j("{`metadata`: {`name`: `test-pod`, `namespace`: `default`}, `spec`: {`containers`: [{`name`: `c1`, `image`: `nginx`, `resources`: {`requests`: {`cpu`: `100m`, `memory`: `" ++ memory ++ "`}, `limits`: {`memory`: `" ++ memory ++ "`}}}" ++ more ++ "]}}")

def Laws.pods.c2() -> String:
  ", {`name`: `c2`, `image`: `busybox`, `resources`: {`requests`: {`cpu`: `50m`, `memory`: `10Mi`}}}"

def Laws.pods.rp_want() -> J.Json:
  Laws.pods.n("{`spec`: {`containers`: [{`name`: `c1`, `resources`: {`requests`: {`cpu`: `100m`, `memory`: `30Mi`}, `limits`: {`memory`: `30Mi`}}}]}}")

# TestResizeSkipsOldOrUnknownHostVersion: makePod(memory).
def Laws.pods.rs(memory: String) -> J.Json:
  Laws.pods.j("{`metadata`: {`name`: `test-pod`, `namespace`: `default`}, `spec`: {`containers`: [{`name`: `c1`, `image`: `nginx`, `resources`: {`requests`: {`memory`: `" ++ memory ++ "`}}}]}}")

# TestSyncTerminatingHostPodStatus: the virtual pod with a status, and the
# host pod.
def Laws.pods.term_v(status: String) -> J.Json:
  Laws.pods.j("{`metadata`: {`name`: `test-pod`, `namespace`: `default`, `deletionTimestamp`: `2026-01-01T00:00:00Z`, `deletionGracePeriodSeconds`: 30, `finalizers`: [`vcluster.loft.sh/test`]}, `spec`: {`containers`: [{`name`: `c1`, `image`: `nginx`}]}, `status`: " ++ status ++ "}")

def Laws.pods.term_p() -> J.Json:
  Laws.pods.j("{`metadata`: {`name`: `test-pod-x-default-x-suffix`, `namespace`: `test`, `deletionTimestamp`: `2026-01-01T00:00:00Z`, `deletionGracePeriodSeconds`: 30, `finalizers`: [`vcluster.loft.sh/test`]}, `spec`: {`containers`: [{`name`: `c1`, `image`: `nginx`}]}, `status`: {`phase`: `Failed`, `qosClass`: `Burstable`}}")

# TestSyncTable's virtual pod and host pod (pPodInitial) for testns/testpod.
def Laws.pods.st_v(more: String) -> J.Json:
  Laws.pods.j("{`metadata`: {`name`: `testpod`, `namespace`: `testns`}, `spec`: {" ++ more ++ "}}")

def Laws.pods.st_p(more: String) -> J.Json:
  Laws.pods.j("{`metadata`: " ++ Laws.pods.pmeta("suffix", "testpod", "testns", "", "") ++ ", `spec`: {" ++ Laws.pods.pspec("testpod") ++ more ++ "}}")

def Laws.pods.st_cfg(sel: List<&2, M.KV>) -> P.Cfg:
  P.Pods.cfg.set_node_selector(Laws.pods.scfg("suffix"), sel)

# TestSync's virtual pods (testns/testpod) and their host pods.
def Laws.pods.ts_v(spec: String) -> J.Json:
  Laws.pods.j("{`metadata`: {`name`: `testpod`, `namespace`: `testns`}, `spec`: {" ++ spec ++ "}}")

def Laws.pods.ts_p(spec: String) -> String:
  "{`metadata`: " ++ Laws.pods.pmeta("vcluster", "testpod", "testns", "", "") ++ ", `spec`: {" ++ Laws.pods.pspec("testpod") ++ spec ++ "}}"

def Laws.pods.hostpaths_v() -> J.Json:
  Laws.pods.j("{`metadata`: {`name`: `test-hostpaths`, `namespace`: `vcluster`}, `spec`: {`containers`: [{`name`: `nginx-placeholder`, `image`: `nginx`, `volumeMounts`: [{`name`: `pod-logs`, `mountPath`: `/var/log/pods`}, {`name`: `logs`, `mountPath`: `/var/log`}, {`name`: `kubelet-pods`, `mountPath`: `/var/lib/kubelet/pods`}]}], `volumes`: [{`name`: `pod-logs`, `hostPath`: {`path`: `/var/log/pods`}}, {`name`: `logs`, `hostPath`: {`path`: `/var/log`}}, {`name`: `kubelet-pods`, `hostPath`: {`path`: `/var/lib/kubelet/pods`}}]}}")

def Laws.pods.env() -> String:
  "[{`name`: `KUBERNETES_PORT`, `value`: `tcp://1.2.3.4:443`}, {`name`: `KUBERNETES_PORT_443_TCP`, `value`: `tcp://1.2.3.4:443`}, {`name`: `KUBERNETES_PORT_443_TCP_ADDR`, `value`: `1.2.3.4`}, {`name`: `KUBERNETES_PORT_443_TCP_PORT`, `value`: `443`}, {`name`: `KUBERNETES_PORT_443_TCP_PROTO`, `value`: `tcp`}, {`name`: `KUBERNETES_SERVICE_HOST`, `value`: `1.2.3.4`}, {`name`: `KUBERNETES_SERVICE_PORT`, `value`: `443`}, {`name`: `KUBERNETES_SERVICE_PORT_HTTPS`, `value`: `443`}]"

def Laws.pods.hostpaths_p() -> String:
  "{`metadata`: " ++ Laws.pods.pmeta("vcluster", "test-hostpaths", "vcluster", "", "") ++ ", `spec`: {" ++ Laws.pods.pspec("test-hostpaths") ++ ", `containers`: [{`name`: `nginx-placeholder`, `image`: `nginx`, `env`: " ++ Laws.pods.env() ++ ", `volumeMounts`: [{`name`: `pod-logs`, `mountPath`: `/var/log/pods`, `mountPropagation`: `HostToContainer`}, {`name`: `logs`, `mountPath`: `/var/log`, `mountPropagation`: `HostToContainer`}, {`name`: `kubelet-pods`, `mountPath`: `/var/lib/kubelet/pods`, `mountPropagation`: `HostToContainer`}, {`name`: `pod-logs-vcluster-physical`, `mountPath`: `/var/vcluster/physical/log/pods`}, {`name`: `logs-vcluster-physical`, `mountPath`: `/var/vcluster/physical/log`}, {`name`: `kubelet-pods-vcluster-physical`, `mountPath`: `/var/vcluster/physical/kubelet/pods`}]}], `volumes`: [{`name`: `pod-logs`, `hostPath`: {`path`: `/tmp/vcluster/vcluster/vcluster/log/pods`}}, {`name`: `logs`, `hostPath`: {`path`: `/tmp/vcluster/vcluster/vcluster/log`}}, {`name`: `kubelet-pods`, `hostPath`: {`path`: `/tmp/vcluster/vcluster/vcluster/kubelet/pods`}}, {`name`: `pod-logs-vcluster-physical`, `hostPath`: {`path`: `/var/log/pods`}}, {`name`: `logs-vcluster-physical`, `hostPath`: {`path`: `/var/log`}}, {`name`: `kubelet-pods-vcluster-physical`, `hostPath`: {`path`: `/var/lib/kubelet/pods`}}]}}"

def Laws.pods.basic() -> String:
  "{`matchLabels`: {`random-key`: `value`}}"

# basicSelectorTranslatedWithMarker's labels: HostLabel(random-key) and the
# marker.
def Laws.pods.basic_t() -> String:
  "`" ++ M.Meta.host_label("suffix", "random-key") ++ "`: `value`, `vcluster.loft.sh/managed-by`: `suffix`"

def Laws.pods.long_ns() -> String:
  M.Meta.convert(M.Meta.namespace_label_prefix(), "suffix", "pretty-loooooooooooong-test-key")

# translator_test.go: TestPodAffinityTermsTranslation

law pods.affinity_no_selector:
  {Laws.pods.aff("{`namespaces`: [`blabla`]}") == Laws.pods.n("{`term`: {}, `events`: []}") : J.Json}

law pods.affinity_empty_namespaces_null_selector:
  {Laws.pods.aff("{`labelSelector`: " ++ Laws.pods.basic() ++ ", `namespaces`: []}")
    == Laws.pods.n("{`term`: {`labelSelector`: {`matchLabels`: {" ++ Laws.pods.basic_t() ++ ", `vcluster.loft.sh/namespace`: `equestria`}}}, `events`: []}") : J.Json}

law pods.affinity_null_selector_namespaces:
  {Laws.pods.aff("{`labelSelector`: " ++ Laws.pods.basic() ++ ", `namespaces`: [`equestria`, `dummy namespace`]}")
    == Laws.pods.n("{`term`: {`labelSelector`: {`matchLabels`: {" ++ Laws.pods.basic_t() ++ "}, `matchExpressions`: [{`key`: `vcluster.loft.sh/namespace`, `operator`: `In`, `values`: [`equestria`, `dummy namespace`]}]}}, `events`: []}") : J.Json}

law pods.affinity_empty_selector_namespaces:
  {Laws.pods.aff("{`labelSelector`: " ++ Laws.pods.basic() ++ ", `namespaces`: [`equestria`], `namespaceSelector`: {}}")
    == Laws.pods.n("{`term`: {`labelSelector`: {`matchLabels`: {" ++ Laws.pods.basic_t() ++ "}}}, `events`: []}") : J.Json}

law pods.affinity_namespaces_and_selector:
  {Laws.pods.aff("{`labelSelector`: " ++ Laws.pods.basic() ++ ", `namespaces`: [`equestria`], `namespaceSelector`: " ++ Laws.pods.basic() ++ "}")
    == Laws.pods.n("{`term`: {`labelSelector`: {`matchLabels`: {" ++ Laws.pods.basic_t() ++ "}, `matchExpressions`: [{`key`: `vcluster.loft.sh/namespace`, `operator`: `In`, `values`: [`equestria`]}]}}, `events`: [`" ++ Laws.pods.aff_warning() ++ "`]}") : J.Json}

law pods.affinity_selector_no_namespaces:
  {Laws.pods.aff("{`labelSelector`: " ++ Laws.pods.basic() ++ ", `namespaceSelector`: {`matchLabels`: {`pretty-loooooooooooong-test-key`: `good-value`}}}")
    == Laws.pods.n("{`term`: {`labelSelector`: {`matchLabels`: {" ++ Laws.pods.basic_t() ++ ", `" ++ Laws.pods.long_ns() ++ "`: `good-value`}}}, `events`: []}") : J.Json}

law pods.affinity_selector_expressions:
  {Laws.pods.aff("{`labelSelector`: " ++ Laws.pods.basic() ++ ", `namespaceSelector`: {`matchExpressions`: [{`key`: `pretty-loooooooooooong-test-key`, `operator`: `NotIn`, `values`: [`bad-value`]}]}}")
    == Laws.pods.n("{`term`: {`labelSelector`: {`matchLabels`: {" ++ Laws.pods.basic_t() ++ "}, `matchExpressions`: [{`key`: `" ++ Laws.pods.long_ns() ++ "`, `operator`: `NotIn`, `values`: [`bad-value`]}]}}, `events`: []}") : J.Json}

# translator_test.go: TestVolumeTranslation

law pods.volume_ephemeral:
  {Laws.pods.vt(False{}, "{`metadata`: {`name`: `pod-name`, `namespace`: `test-ns`}, `spec`: {`volumes`: [{`name`: `eph-vol`, `ephemeral`: {`volumeClaimTemplate`: {}}}]}}")
    == Laws.pods.n("{`volumes`: [{`name`: `eph-vol`, `persistentVolumeClaim`: {`claimName`: `" ++ N.Names.host_name("pod-name-eph-vol", "test-ns", "suffix") ++ "`}}]}") : J.Json}

law pods.volume_hostpath_kubelet:
  {Laws.pods.vt(True{}, "{`metadata`: {`name`: `pod-name`, `namespace`: `test-ns`}, `spec`: {`containers`: [{`volumeMounts`: [{`name`: `kubelet-pods`, `mountPath`: `/var/lib/kubelet/pods`}]}], `volumes`: [{`name`: `kubelet-pods`, `hostPath`: {`path`: `/var/lib/kubelet/pods`}}]}}")
    == Laws.pods.n("{`volumes`: [{`name`: `kubelet-pods`, `hostPath`: {`path`: `/tmp/vcluster/vcluster/vcluster/kubelet/pods`}}, {`name`: `kubelet-pods-vcluster-physical`, `hostPath`: {`path`: `/var/lib/kubelet/pods`}}], `volumeMounts`: [{`name`: `kubelet-pods`, `mountPath`: `/var/lib/kubelet/pods`, `mountPropagation`: `HostToContainer`}, {`name`: `kubelet-pods-vcluster-physical`, `mountPath`: `/var/vcluster/physical/kubelet/pods`}]}") : J.Json}

law pods.volume_hostpath_logs:
  {Laws.pods.vt(True{}, "{`metadata`: {`name`: `pod-name`, `namespace`: `test-ns`}, `spec`: {`containers`: [{`volumeMounts`: [{`name`: `varlog`, `mountPath`: `/var/log/pods/`, `readOnly`: true}]}], `volumes`: [{`name`: `varlog`, `hostPath`: {`path`: `/var/log/pods/`}}]}}")
    == Laws.pods.n("{`volumes`: [{`name`: `varlog`, `hostPath`: {`path`: `/tmp/vcluster/vcluster/vcluster/log/pods`}}, {`name`: `varlog-vcluster-physical`, `hostPath`: {`path`: `/var/log/pods`}}], `volumeMounts`: [{`name`: `varlog`, `readOnly`: true, `mountPath`: `/var/log/pods/`, `mountPropagation`: `HostToContainer`}, {`name`: `varlog-vcluster-physical`, `readOnly`: true, `mountPath`: `/var/vcluster/physical/log/pods`}]}") : J.Json}

# translator_test.go: TestRewriteHostsTranslation

law pods.rewrite_hosts_args:
  {J.Json.get(P.Pods.hosts_container(Laws.pods.cfg("suffix"), "pod-name", "pod-name", "pod-name.subdomain.test-ns.cluster.local"), "args")
    == J.Json.arr([J.JStr{"-c"}, J.JStr{"sed -E -e 's/^(\\d+.\\d+.\\d+.\\d+\\s+)pod-name$/\\1 pod-name.subdomain.test-ns.cluster.local pod-name/' /etc/hosts > /hosts/hosts"}]) : J.Json}

law pods.rewrite_hosts_init_container:
  {P.Pods.names(J.Json.items(J.Json.at(P.Pods.translate(Laws.pods.cfg("suffix"), Laws.pods.inp0(),
      Laws.pods.j("{`metadata`: {`name`: `pod-name`, `namespace`: `test-ns`}, `spec`: {`subdomain`: `subdomain`, `containers`: [{}]}}")), ["spec", "initContainers"])))
    == ["vcluster-rewrite-hosts"] : List<&2, String>}

law pods.rewrite_hosts_mount:
  {P.Pods.norm(J.Json.get(Laws.pods.first(J.Json.at(P.Pods.translate(Laws.pods.cfg("suffix"), Laws.pods.inp0(),
      Laws.pods.j("{`metadata`: {`name`: `pod-name`, `namespace`: `test-ns`}, `spec`: {`subdomain`: `subdomain`, `containers`: [{}]}}")), ["spec", "containers"])), "volumeMounts"))
    == Laws.pods.n("[{`mountPath`: `/etc/hosts`, `name`: `vcluster-rewrite-hosts`, `subPath`: `hosts`}]") : J.Json}

law pods.rewrite_hosts_default_registry:
  {P.Pods.hosts_image("my-registry", "mirror.gcr.io", "library/alpine", "3.20") == "my-registry/library/alpine:3.20" : String}

law pods.rewrite_hosts_image_override:
  {P.Pods.hosts_image("", "private", "minimal/sed", "very-specific-tag") == "private/minimal/sed:very-specific-tag" : String}

# translator_test.go: TestPodResourcesTranslation

law pods.resources_new_host:
  {P.Pods.norm(J.Json.at(P.Pods.translate(P.Pods.cfg.set_host_version(Laws.pods.cfg("suffix"), Some{P.Ver{1, 34, 0}}), Laws.pods.inp0(),
      Laws.pods.j("{`metadata`: {`name`: `test-pod`, `namespace`: `default`}, `spec`: {`resources`: {`limits`: {`cpu`: `500m`}, `requests`: {`memory`: `128Mi`}}, `containers`: [{`name`: `test`}]}}")), ["spec", "resources"]))
    == Laws.pods.n("{`limits`: {`cpu`: `500m`}, `requests`: {`memory`: `128Mi`}}") : J.Json}

law pods.resources_old_host:
  {J.Json.at(P.Pods.translate(P.Pods.cfg.set_host_version(Laws.pods.cfg("suffix"), Some{P.Ver{1, 33, 9}}), Laws.pods.inp0(),
      Laws.pods.j("{`metadata`: {`name`: `test-pod`, `namespace`: `default`}, `spec`: {`resources`: {`limits`: {`cpu`: `500m`}}, `containers`: [{`name`: `test`}]}}")), ["spec", "resources"])
    == J.JNull{} : J.Json}

# translator_test.go: TestTranslateResourceClaims

law pods.claims_name:
  {Laws.pods.claims(True{}, True{}, "[{`name`: `claim-ref`, `resourceClaimName`: `my-claim`}]")
    == Laws.pods.n("[{`name`: `claim-ref`, `resourceClaimName`: `" ++ N.Names.host_name("my-claim", "test-ns", "suffix") ++ "`}]") : J.Json}

law pods.claims_template:
  {Laws.pods.claims(True{}, True{}, "[{`name`: `template-ref`, `resourceClaimTemplateName`: `my-template`}]")
    == Laws.pods.n("[{`name`: `template-ref`, `resourceClaimTemplateName`: `" ++ N.Names.host_name("my-template", "test-ns", "suffix") ++ "`}]") : J.Json}

law pods.claims_both:
  {Laws.pods.claims(True{}, True{}, "[{`name`: `claim-ref`, `resourceClaimName`: `existing-claim`}, {`name`: `template-ref`, `resourceClaimTemplateName`: `ephemeral-template`}]")
    == Laws.pods.n("[{`name`: `claim-ref`, `resourceClaimName`: `" ++ N.Names.host_name("existing-claim", "test-ns", "suffix") ++ "`}, {`name`: `template-ref`, `resourceClaimTemplateName`: `" ++ N.Names.host_name("ephemeral-template", "test-ns", "suffix") ++ "`}]") : J.Json}

law pods.claims_empty:
  {Laws.pods.claims(True{}, True{}, "[]") == Laws.pods.n("[]") : J.Json}

law pods.claims_name_disabled:
  {Laws.pods.claims(False{}, True{}, "[{`name`: `claim-ref`, `resourceClaimName`: `my-claim`}]")
    == Laws.pods.n("[{`name`: `claim-ref`, `resourceClaimName`: `my-claim`}]") : J.Json}

law pods.claims_template_disabled:
  {Laws.pods.claims(True{}, False{}, "[{`name`: `template-ref`, `resourceClaimTemplateName`: `my-template`}]")
    == Laws.pods.n("[{`name`: `template-ref`, `resourceClaimTemplateName`: `my-template`}]") : J.Json}

law pods.claims_both_disabled:
  {Laws.pods.claims(False{}, False{}, "[{`name`: `claim-ref`, `resourceClaimName`: `my-claim`}, {`name`: `template-ref`, `resourceClaimTemplateName`: `my-template`}]")
    == Laws.pods.n("[{`name`: `claim-ref`, `resourceClaimName`: `my-claim`}, {`name`: `template-ref`, `resourceClaimTemplateName`: `my-template`}]") : J.Json}

# translator_test.go: TestDiffResourceClaimStatus

law pods.claim_status_mapped:
  {Laws.pods.rc([M.KV{"host-claim", "virtual-claim"}], "host-claim") == Laws.pods.rc_want("virtual-claim") : J.Json}

law pods.claim_status_unmapped:
  {Laws.pods.rc([], "host-claim-unmapped") == Laws.pods.rc_want("host-claim-unmapped") : J.Json}

law pods.claim_status_missing:
  {Laws.pods.rc([], "missing-host-claim") == Laws.pods.rc_want("missing-host-claim") : J.Json}

# translator_test.go: TestTranslateEnforcedTolerationDedup

law pods.enforced_toleration_dedup:
  {P.Pods.norm(J.Json.at(P.Pods.translate(P.Pods.cfg.set_enforced(Laws.pods.cfg("suffix"), [Laws.pods.j("{`key`: `vcluster-enforced`, `operator`: `Exists`, `effect`: `NoSchedule`}")]),
      Laws.pods.inp0(), Laws.pods.j("{`metadata`: {`name`: `testpod`, `namespace`: `testns`}, `spec`: {`tolerations`: [{`key`: `vcluster-enforced`, `operator`: `Exists`, `effect`: `NoSchedule`}], `containers`: [{`name`: `c`, `image`: `nginx`}]}}")),
      ["spec", "tolerations"]))
    == Laws.pods.n("[{`key`: `vcluster-enforced`, `operator`: `Exists`, `effect`: `NoSchedule`}]") : J.Json}

# diff_test.go: TestDiffTolerationSync

law pods.tolerations_add:
  {Laws.pods.tdiff(Laws.pods.t_initial(), Laws.pods.t_initial() ++ ", " ++ Laws.pods.t_new(),
      Laws.pods.t_initial() ++ ", " ++ Laws.pods.t_enforced(), Laws.pods.t_initial() ++ ", " ++ Laws.pods.t_enforced())
    == Laws.pods.tols(Laws.pods.t_initial() ++ ", " ++ Laws.pods.t_new() ++ ", " ++ Laws.pods.t_enforced()) : J.Json}

law pods.tolerations_remove:
  {Laws.pods.tdiff(Laws.pods.t_initial() ++ ", " ++ Laws.pods.t_new(), Laws.pods.t_initial(),
      Laws.pods.t_initial() ++ ", " ++ Laws.pods.t_new() ++ ", " ++ Laws.pods.t_enforced(), Laws.pods.t_initial() ++ ", " ++ Laws.pods.t_new() ++ ", " ++ Laws.pods.t_enforced())
    == Laws.pods.tols(Laws.pods.t_initial() ++ ", " ++ Laws.pods.t_new() ++ ", " ++ Laws.pods.t_enforced()) : J.Json}

law pods.tolerations_enforced_missing:
  {Laws.pods.tdiff(Laws.pods.t_initial(), Laws.pods.t_initial() ++ ", " ++ Laws.pods.t_new(), Laws.pods.t_initial(), Laws.pods.t_initial())
    == Laws.pods.tols(Laws.pods.t_initial() ++ ", " ++ Laws.pods.t_new() ++ ", " ++ Laws.pods.t_enforced()) : J.Json}

law pods.tolerations_admission:
  {Laws.pods.tdiff(Laws.pods.t_initial(), Laws.pods.t_initial() ++ ", " ++ Laws.pods.t_new(),
      Laws.pods.t_initial() ++ ", " ++ Laws.pods.t_enforced() ++ ", " ++ Laws.pods.t_admission(), Laws.pods.t_initial() ++ ", " ++ Laws.pods.t_enforced() ++ ", " ++ Laws.pods.t_admission())
    == Laws.pods.tols(Laws.pods.t_initial() ++ ", " ++ Laws.pods.t_new() ++ ", " ++ Laws.pods.t_enforced() ++ ", " ++ Laws.pods.t_admission()) : J.Json}

law pods.tolerations_drift_enforced:
  {Laws.pods.tdiff(Laws.pods.t_initial(), Laws.pods.t_initial(), Laws.pods.t_initial(), Laws.pods.t_initial())
    == Laws.pods.tols(Laws.pods.t_initial() ++ ", " ++ Laws.pods.t_enforced()) : J.Json}

law pods.tolerations_drift_virtual:
  {Laws.pods.tdiff(Laws.pods.t_initial() ++ ", " ++ Laws.pods.t_new(), Laws.pods.t_initial() ++ ", " ++ Laws.pods.t_new(),
      Laws.pods.t_initial() ++ ", " ++ Laws.pods.t_enforced(), Laws.pods.t_initial() ++ ", " ++ Laws.pods.t_enforced())
    == Laws.pods.tols(Laws.pods.t_initial() ++ ", " ++ Laws.pods.t_new() ++ ", " ++ Laws.pods.t_enforced()) : J.Json}

law pods.tolerations_race:
  {Laws.pods.tdiff(Laws.pods.t_initial(), Laws.pods.t_initial() ++ ", " ++ Laws.pods.t_new(),
      Laws.pods.t_initial() ++ ", " ++ Laws.pods.t_enforced(), Laws.pods.t_initial() ++ ", " ++ Laws.pods.t_enforced() ++ ", " ++ Laws.pods.t_late())
    == Laws.pods.tols(Laws.pods.t_initial() ++ ", " ++ Laws.pods.t_new() ++ ", " ++ Laws.pods.t_enforced() ++ ", " ++ Laws.pods.t_late()) : J.Json}

# diff_test.go: TestConditionsCopyBidirectionalObservedGeneration

law pods.conditions_131_divergence:
  {Laws.pods.cc(Some{P.Ver{1, 31, 0}}, Laws.pods.ready_gen1(), Laws.pods.ready(), Laws.pods.ready_gen1(), Laws.pods.ready_gen1())
    == Laws.pods.cc_want(Laws.pods.ready(), Laws.pods.ready_gen1()) : J.Json}

law pods.conditions_131_status_change:
  {Laws.pods.cc(Some{P.Ver{1, 31, 0}}, Laws.pods.ready(), Laws.pods.not_ready(), Laws.pods.ready(), Laws.pods.ready())
    == Laws.pods.cc_want(Laws.pods.not_ready(), Laws.pods.not_ready()) : J.Json}

law pods.conditions_131_host_generation:
  {Laws.pods.cc(Some{P.Ver{1, 31, 0}}, Laws.pods.ready(), Laws.pods.ready(), Laws.pods.ready(), Laws.pods.ready_gen1())
    == Laws.pods.cc_want(Laws.pods.ready(), Laws.pods.ready_gen1()) : J.Json}

law pods.conditions_133_divergence:
  {Laws.pods.cc(Some{P.Ver{1, 33, 0}}, Laws.pods.ready_gen1(), Laws.pods.ready(), Laws.pods.ready_gen1(), Laws.pods.ready_gen1())
    == Laws.pods.cc_want(Laws.pods.ready(), Laws.pods.ready_gen1()) : J.Json}

law pods.conditions_134_change:
  {Laws.pods.cc(Some{P.Ver{1, 34, 0}}, Laws.pods.ready_gen1(), Laws.pods.ready(), Laws.pods.ready_gen1(), Laws.pods.ready_gen1())
    == Laws.pods.cc_want(Laws.pods.ready(), Laws.pods.ready()) : J.Json}

law pods.conditions_unknown_version:
  {Laws.pods.cc(None{}, Laws.pods.ready_gen1(), Laws.pods.ready(), Laws.pods.ready_gen1(), Laws.pods.ready_gen1())
    == Laws.pods.cc_want(Laws.pods.ready(), Laws.pods.ready()) : J.Json}

# diff_test.go: TestDiffPodStatusObservedGeneration

law pods.observed_generation_133:
  {Laws.pods.og(Some{P.Ver{1, 33, 0}}) == Laws.pods.n("{`conditions`: [{`type`: `Ready`, `status`: `True`}]}") : J.Json}

law pods.observed_generation_134:
  {Laws.pods.og(Some{P.Ver{1, 34, 0}}) == Laws.pods.n("{`observedGeneration`: 3, `conditions`: [{`type`: `Ready`, `status`: `True`, `observedGeneration`: 3}]}") : J.Json}

law pods.observed_generation_unknown:
  {Laws.pods.og(None{}) == Laws.pods.n("{`observedGeneration`: 3, `conditions`: [{`type`: `Ready`, `status`: `True`, `observedGeneration`: 3}]}") : J.Json}

# diff_test.go: TestDiffConditionsCacheInformerDivergence

law pods.divergence_133:
  {Laws.pods.div(Some{P.Ver{1, 33, 0}}) == Laws.pods.n(Laws.pods.ready_gen1()) : J.Json}

law pods.divergence_134:
  {Laws.pods.div(Some{P.Ver{1, 34, 0}}) == Laws.pods.n(Laws.pods.ready()) : J.Json}

law pods.divergence_unknown:
  {Laws.pods.div(None{}) == Laws.pods.n(Laws.pods.ready()) : J.Json}

# diff_test.go: TestDiffQOSClassPreservation

law pods.qos_class_kept:
  {Laws.pods.qos(P.Pods.diff(Laws.pods.cfg("suffix"), Laws.pods.din0(),
      Laws.pods.sp("testpod-x-testns", "test", "{`qosClass`: `Burstable`}"), Laws.pods.sp("testpod-x-testns", "test", "{`qosClass`: `Burstable`}"),
      Laws.pods.sp("testpod", "testns", "{}"), Laws.pods.sp("testpod", "testns", "{`qosClass`: `BestEffort`}")))
    == Laws.pods.n("{`virtual`: `BestEffort`, `host`: `Burstable`}") : J.Json}

# diff_test.go: TestDesiredVirtualStatus

law pods.desired_status_133:
  {Laws.pods.desired(Some{P.Ver{1, 33, 0}})
    == Laws.pods.n("{`phase`: `Running`, `qosClass`: `Guaranteed`, `observedGeneration`: 2, `conditions`: [{`type`: `Ready`, `status`: `True`}]}") : J.Json}

law pods.desired_status_134:
  {Laws.pods.desired(Some{P.Ver{1, 34, 0}})
    == Laws.pods.n("{`phase`: `Running`, `qosClass`: `Guaranteed`, `observedGeneration`: 5, `conditions`: [{`type`: `Ready`, `status`: `True`, `observedGeneration`: 5}]}") : J.Json}

law pods.desired_status_unknown:
  {Laws.pods.desired(None{})
    == Laws.pods.n("{`phase`: `Running`, `qosClass`: `Guaranteed`, `observedGeneration`: 5, `conditions`: [{`type`: `Ready`, `status`: `True`, `observedGeneration`: 5}]}") : J.Json}

# diff_test.go: TestDesiredVirtualStatusDoesNotMutateInputs (values are
# immutable in Bend; the law states the result the test reads).

law pods.desired_status_inputs:
  {P.Pods.norm(P.Pods.desired_status(Laws.pods.vcfg(Some{P.Ver{1, 33, 0}}),
      Laws.pods.j("{`qosClass`: `Burstable`, `observedGeneration`: 5, `conditions`: [{`type`: `Ready`, `observedGeneration`: 5}]}"),
      Laws.pods.j("{`qosClass`: `Guaranteed`, `observedGeneration`: 2}")))
    == Laws.pods.n("{`qosClass`: `Guaranteed`, `observedGeneration`: 2, `conditions`: [{`type`: `Ready`}]}") : J.Json}

# syncer_test.go: TestSyncTable (translate.VClusterName "suffix")

law pods.sync_table_delete_virtual_pod:
  {P.Pods.sync(Laws.pods.scfg("suffix"), Laws.pods.sin([], True{}),
      Some{Laws.pods.st_p(", `nodeName`: `test123`")}, Some{Laws.pods.st_p(", `nodeName`: `test123`")},
      Some{Laws.pods.st_v("`nodeName`: `test123`")}, Some{Laws.pods.st_v("`nodeName`: `test123`")})
    == [P.WRequeue{0}] : List<&2, P.Write>}

law pods.sync_table_injected_sidecar:
  {P.Pods.sync(Laws.pods.scfg("suffix"), Laws.pods.sin(["test123"], True{}),
      Some{Laws.pods.st_p(", `containers`: [{`name`: `nginx-not-injected`}, {`name`: `nginx-injected`}], `nodeName`: `test123`")},
      Some{Laws.pods.st_p(", `containers`: [{`name`: `nginx-not-injected`}, {`name`: `nginx-injected`}], `nodeName`: `test123`")},
      Some{Laws.pods.st_v("`containers`: [{`name`: `nginx-not-injected`}], `nodeName`: `test123`")},
      Some{Laws.pods.st_v("`containers`: [{`name`: `nginx-not-injected`}], `nodeName`: `test123`")})
    == [] : List<&2, P.Write>}

law pods.sync_table_node_selector:
  {P.Pods.sync(Laws.pods.st_cfg([M.KV{"labelB", "enforcedB"}, M.KV{"otherLabel", "abc"}]), Laws.pods.sin([], True{}), None{}, None{}, None{},
      Some{Laws.pods.st_v("`nodeSelector`: {`labelA`: `valueA`, `labelB`: `valueB`}")})
    == Laws.pods.create("{`metadata`: " ++ Laws.pods.pmeta("suffix", "testpod", "testns", "", "") ++ ", `spec`: {" ++ Laws.pods.pspec("testpod")
      ++ ", `nodeSelector`: {`labelA`: `valueA`, `labelB`: `enforcedB`, `otherLabel`: `abc`}}}") : List<&2, P.Write>}

law pods.sync_table_no_security_standard:
  {P.Pods.sync(Laws.pods.scfg("suffix"), Laws.pods.sin([], True{}), None{}, None{}, None{}, Some{Laws.pods.st_v("")})
    == Laws.pods.create("{`metadata`: " ++ Laws.pods.pmeta("suffix", "testpod", "testns", "", "") ++ ", `spec`: {" ++ Laws.pods.pspec("testpod") ++ "}}") : List<&2, P.Write>}

law pods.sync_table_privileged:
  {P.Pods.sync(Laws.pods.scfg("suffix"), Laws.pods.sin([], True{}), None{}, None{}, None{}, Some{Laws.pods.st_v("")})
    == Laws.pods.create("{`metadata`: " ++ Laws.pods.pmeta("suffix", "testpod", "testns", "", "") ++ ", `spec`: {" ++ Laws.pods.pspec("testpod") ++ "}}") : List<&2, P.Write>}

law pods.sync_table_restricted:
  {P.Pods.sync(Laws.pods.scfg("suffix"), Laws.pods.sin([], False{}), None{}, None{}, None{}, Some{Laws.pods.st_v("")})
    == [] : List<&2, P.Write>}

law pods.sync_table_labels:
  {P.Pods.sync(Laws.pods.scfg("suffix"), Laws.pods.sin([], True{}), None{}, None{}, None{},
      Some{Laws.pods.j("{`metadata`: {`name`: `testpod`, `namespace`: `testns`, `labels`: {`test.sh/abcd`: `yes`}}, `spec`: {}}")})
    == Laws.pods.create("{`metadata`: " ++ Laws.pods.pmeta("suffix", "testpod", "testns", "test.sh/abcd=\\`yes\\`", ", `test.sh/abcd`: `yes`")
      ++ ", `spec`: {" ++ Laws.pods.pspec("testpod") ++ "}}") : List<&2, P.Write>}

# syncer_test.go: TestSync (translate.VClusterName "vcluster")

law pods.sync_map_hostpaths:
  {P.Pods.sync(P.Pods.cfg.set_host_paths(Laws.pods.scfg("vcluster"), True{}), Laws.pods.sin([], True{}), None{}, None{}, None{}, Some{Laws.pods.hostpaths_v()})
    == Laws.pods.create(Laws.pods.hostpaths_p()) : List<&2, P.Write>}

law pods.sync_priority_class_from_host:
  {P.Pods.sync(P.Pods.cfg.set_pc_from_host(Laws.pods.scfg("vcluster"), True{}), Laws.pods.sin([], True{}), None{}, None{}, None{},
      Some{Laws.pods.ts_v("`priorityClassName`: `high-priority`")})
    == Laws.pods.create(Laws.pods.ts_p(", `priorityClassName`: `high-priority`")) : List<&2, P.Write>}

law pods.sync_priority_class_to_host:
  {P.Pods.sync(P.Pods.cfg.set_pc_to_host(Laws.pods.scfg("vcluster"), True{}), Laws.pods.sin([], True{}), None{}, None{}, None{},
      Some{Laws.pods.ts_v("`priorityClassName`: `high-priority`")})
    == Laws.pods.create(Laws.pods.ts_p(", `priorityClassName`: `vcluster-high-priority-x-test-x-vcluster`")) : List<&2, P.Write>}

law pods.sync_pods_priority_class_name:
  {P.Pods.sync(P.Pods.cfg.set_pod_pc(Laws.pods.scfg("vcluster"), "high-priority"), Laws.pods.sin([], True{}), None{}, None{}, None{},
      Some{Laws.pods.ts_v("")})
    == Laws.pods.create(Laws.pods.ts_p(", `priorityClassName`: `high-priority`")) : List<&2, P.Write>}

# syncer_test.go: TestBuildResizePatch

law pods.resize_patch_differs:
  {Laws.pods.mn(P.Pods.resize_patch(Laws.pods.rp("30Mi", ""), Laws.pods.rp("20Mi", ""))) == Laws.pods.rp_want() : J.Json}

law pods.resize_patch_equal:
  {P.Pods.resize_patch(Laws.pods.rp("20Mi", ""), Laws.pods.rp("20Mi", "")) == None{} : Maybe<&2, J.Json>}

law pods.resize_patch_only_diffs:
  {Laws.pods.mn(P.Pods.resize_patch(Laws.pods.rp("30Mi", Laws.pods.c2()), Laws.pods.rp("20Mi", Laws.pods.c2()))) == Laws.pods.rp_want() : J.Json}

law pods.resize_patch_missing_on_host:
  {Laws.pods.mn(P.Pods.resize_patch(Laws.pods.rp("30Mi", Laws.pods.c2()), Laws.pods.rp("20Mi", ""))) == Laws.pods.rp_want() : J.Json}

# syncer_test.go: TestResizeSkipsOldOrUnknownHostVersion

law pods.resize_unknown_host:
  {Bool.and(Maybe.is_some(&2, J.Json, P.Pods.resize_patch(Laws.pods.rs("30Mi"), Laws.pods.rs("20Mi"))),
      Maybe.is_none(&2, J.Json, P.Pods.resize(Laws.pods.cfg("vcluster"), Laws.pods.rs("30Mi"), Laws.pods.rs("20Mi")))) == True{} : Bool}

law pods.resize_old_host:
  {Bool.and(Maybe.is_some(&2, J.Json, P.Pods.resize_patch(Laws.pods.rs("30Mi"), Laws.pods.rs("20Mi"))),
      Maybe.is_none(&2, J.Json, P.Pods.resize(P.Pods.cfg.set_host_version(Laws.pods.cfg("vcluster"), Some{P.Ver{1, 34, 9}}), Laws.pods.rs("30Mi"), Laws.pods.rs("20Mi")))) == True{} : Bool}

# syncer_test.go: TestSyncTerminatingHostPodStatus (two syncs)

law pods.terminating_status_propagates:
  {P.Pods.sync(Laws.pods.cfg("vcluster"), Laws.pods.sin([], True{}), Some{Laws.pods.term_p()}, Some{Laws.pods.term_p()},
      Some{Laws.pods.term_v("{`phase`: `Running`, `qosClass`: `BestEffort`}")}, Some{Laws.pods.term_v("{`phase`: `Running`, `qosClass`: `BestEffort`}")})
    == [P.WVirtualStatus{P.Pods.norm(Laws.pods.term_v("{`phase`: `Failed`, `qosClass`: `BestEffort`}"))}] : List<&2, P.Write>}

law pods.terminating_status_unchanged:
  {P.Pods.sync(Laws.pods.cfg("vcluster"), Laws.pods.sin([], True{}), Some{Laws.pods.term_p()}, Some{Laws.pods.term_p()},
      Some{Laws.pods.term_v("{`phase`: `Failed`, `qosClass`: `BestEffort`}")}, Some{Laws.pods.term_v("{`phase`: `Failed`, `qosClass`: `BestEffort`}")})
    == [] : List<&2, P.Write>}

# General laws.

# Translation never drops a container or changes the container order.
law pods.containers_kept:
  for +cfg: P.Cfg
  for +inp: P.Inp
  for +v: J.Json
  {P.Pods.names(J.Json.items(J.Json.at(P.Pods.translate(cfg, inp, v), ["spec", "containers"])))
    == P.Pods.names(J.Json.items(J.Json.at(v, ["spec", "containers"]))) : List<&2, String>}

# The same for ephemeral containers.
law pods.ephemeral_containers_kept:
  for +cfg: P.Cfg
  for +inp: P.Inp
  for +v: J.Json
  {P.Pods.names(J.Json.items(J.Json.at(P.Pods.translate(cfg, inp, v), ["spec", "ephemeralContainers"])))
    == P.Pods.names(J.Json.items(J.Json.at(v, ["spec", "ephemeralContainers"]))) : List<&2, String>}

# Every host pod carries the managed-by marker label of its vcluster.
law pods.marker_label:
  for +cfg: P.Cfg
  for +inp: P.Inp
  for +v: J.Json
  {J.Json.get(J.Json.at(P.Pods.translate(cfg, inp, v), ["metadata", "labels"]), M.Meta.marker_label()) == J.JStr{P.Pods.cfg.vc(cfg)} : J.Json}

# Every host pod carries the object-name annotation of its virtual pod.
law pods.object_name:
  for +cfg: P.Cfg
  for +inp: P.Inp
  for +v: J.Json
  {J.Json.get(J.Json.at(P.Pods.translate(cfg, inp, v), ["metadata", "annotations"]), M.Meta.name_annotation()) == J.JStr{P.Pods.name_of(v)} : J.Json}

# Every host pod carries the object-namespace annotation of its virtual pod.
law pods.object_namespace:
  for +cfg: P.Cfg
  for +inp: P.Inp
  for +v: J.Json
  {J.Json.get(J.Json.at(P.Pods.translate(cfg, inp, v), ["metadata", "annotations"]), M.Meta.namespace_annotation()) == J.JStr{P.Pods.ns_of(v)} : J.Json}

# Back-sync of the status is idempotent: the desired virtual status of the
# desired virtual status is itself.
law pods.status_idempotent:
  for +cfg: P.Cfg
  for +h: J.Json
  for +vs: J.Json
  {P.Pods.desired_status(cfg, h, P.Pods.desired_status(cfg, h, vs)) == P.Pods.desired_status(cfg, h, vs) : J.Json}
