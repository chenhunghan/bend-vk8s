import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/translate/pods.bend as P
import ../src/translate/meta.bend as M

# Tests for src/translate/pods.bend. The laws in laws/pods.bend transcribe
# vcluster's own tests; these cover the rest of the pod syncer: service
# environment variables, DNS, field references, service account tokens,
# owner references, priority classes, host paths and the syncer's writes.
# Expected values follow vcluster's Go code (translator.go, envvars.go,
# hostpath.go, syncer.go at a8ab30e), with translate.VClusterName "suffix",
# target namespace "test" and the virtual namespace "ns1". The namespace
# label key hash was computed with Python's hashlib (sha256("team")).

def report(name: String, got: String, want: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name ++ ": got " ++ got ++ ", want " ++ want)

def check(name: String, +got: String, +want: String) -> IO(Unit):
  report(name, got, want, String.eq(got, want))

def jr(r: Result<&2, &2, String, J.Json>) -> J.Json:
  match r:
    case Done{x}:
      x
    case Fail{e}:
      J.JStr{"parse error: " ++ e}

# A JSON value, written with ` for ".
def j(s: String) -> J.Json:
  jr(J.Json.parse(P.Pods.subst(s, '`', '"')))

def show(x: J.Json) -> String:
  J.Json.show(P.Pods.norm(x))

# got (a value) against want (JSON text with `), both in canonical form.
def checkj(name: String, got: J.Json, want: String) -> IO(Unit):
  check(name, show(got), show(j(want)))

def show_w(w: P.Write) -> String:
  match w:
    case P.WCreateHost{o}:
      "CreateHost " ++ J.Json.show(o)
    case P.WCreateVirtual{o}:
      "CreateVirtual " ++ J.Json.show(o)
    case P.WPatchHost{o}:
      "PatchHost " ++ J.Json.show(o)
    case P.WPatchVirtual{o}:
      "PatchVirtual " ++ J.Json.show(o)
    case P.WVirtualStatus{o}:
      "VirtualStatus " ++ J.Json.show(o)
    case P.WDeleteHost{g, u}:
      "DeleteHost " ++ g ++ " " ++ u
    case P.WDeleteVirtual{g, u}:
      "DeleteVirtual " ++ g ++ " " ++ u
    case P.WBind{n}:
      "Bind " ++ n
    case P.WEphemeral{o}:
      "Ephemeral " ++ J.Json.show(o)
    case P.WResize{o}:
      "Resize " ++ J.Json.show(o)
    case P.WSecret{o}:
      "Secret " ++ J.Json.show(o)
    case P.WEvent{k, r, m}:
      "Event " ++ k ++ " " ++ r ++ " " ++ m
    case P.WRequeue{ms}:
      "Requeue " ++ U32.show(ms)
    case P.WError{m}:
      "Error " ++ m

def show_ws(ws: List<&2, P.Write>) -> String:
  match ws:
    case Nil{}:
      ""
    case Con{w, r}:
      show_w(w) ++ ";" ++ show_ws(r)

def show_maybe(m: Maybe<&2, String>) -> String:
  match m:
    case None{}:
      "none"
    case Some{x}:
      x

def show_mj(m: Maybe<&2, J.Json>) -> String:
  match m:
    case None{}:
      "none"
    case Some{x}:
      show(x)

def snd(r: J.Json & J.Json) -> J.Json:
  (a, b) = r
  b

def cfg() -> P.Cfg:
  P.Pods.cfg.default("suffix", "test", "vcluster")

def inp(dns: String, kube: String) -> P.Inp:
  P.Inp{[], [], dns, kube, [], []}

def sin(nodes: List<&2, String>) -> P.SInp:
  P.SInp{inp("2.2.2.2", "1.2.3.4"), P.DInp{[], []}, nodes, True{}, False{}, None{}}

def pod(spec: String) -> J.Json:
  j("{`metadata`: {`name`: `web`, `namespace`: `ns1`, `uid`: `vu`}, `spec`: {" ++ spec ++ "}}")

def tr(c: P.Cfg, i: P.Inp, v: J.Json) -> J.Json:
  P.Pods.translate(c, i, v)

def spec_at(v: J.Json, k: String) -> J.Json:
  J.Json.get(J.Json.get(v, "spec"), k)

def ann_at(v: J.Json, k: String) -> J.Json:
  J.Json.get(J.Json.get(J.Json.get(v, "metadata"), "annotations"), k)

def first(j: J.Json) -> J.Json:
  Maybe.default(&2, J.Json, List.head(&2, J.Json, J.Json.items(j)), J.JNull{})

def kube_env() -> String:
  "`KUBERNETES_PORT`: `tcp://1.2.3.4:443`, `KUBERNETES_PORT_443_TCP`: `tcp://1.2.3.4:443`, `KUBERNETES_PORT_443_TCP_ADDR`: `1.2.3.4`, `KUBERNETES_PORT_443_TCP_PORT`: `443`, `KUBERNETES_PORT_443_TCP_PROTO`: `tcp`, `KUBERNETES_SERVICE_HOST`: `1.2.3.4`, `KUBERNETES_SERVICE_PORT`: `443`, `KUBERNETES_SERVICE_PORT_HTTPS`: `443`"

def senv(links: Bool, svcs: String) -> J.Json:
  P.Pods.obj_of(P.Pods.services_env(links, J.Json.items(j(svcs)), "1.2.3.4"))

def tok_pod() -> J.Json:
  pod("`serviceAccountName`: `app`, `volumes`: [{`name`: `kube-api-access`, `projected`: {`sources`: [{`serviceAccountToken`: {`path`: `token`, `expirationSeconds`: 3607}}, {`configMap`: {`name`: `kube-root-ca.crt`}}]}}]")

def main() -> IO(Unit):
  do IO<Unit>:
    # Service environment variables (envvars.go, ServicesToEnvironmentVariables).
    checkj("service env with links",
      senv(True{}, "[{`metadata`: {`name`: `my-svc`}, `spec`: {`clusterIP`: `10.0.0.1`, `ports`: [{`name`: `http`, `port`: 80}]}}]"),
      "{" ++ kube_env() ++ ", `MY_SVC_SERVICE_HOST`: `10.0.0.1`, `MY_SVC_SERVICE_PORT`: `80`, `MY_SVC_SERVICE_PORT_HTTP`: `80`, `MY_SVC_PORT`: `tcp://10.0.0.1:80`, `MY_SVC_PORT_80_TCP`: `tcp://10.0.0.1:80`, `MY_SVC_PORT_80_TCP_PROTO`: `tcp`, `MY_SVC_PORT_80_TCP_PORT`: `80`, `MY_SVC_PORT_80_TCP_ADDR`: `10.0.0.1`}")
    checkj("service env without links",
      senv(False{}, "[{`metadata`: {`name`: `my-svc`}, `spec`: {`clusterIP`: `10.0.0.1`, `ports`: [{`port`: 80}]}}]"),
      "{" ++ kube_env() ++ "}")
    checkj("headless service skipped",
      senv(True{}, "[{`metadata`: {`name`: `my-svc`}, `spec`: {`clusterIP`: `None`, `ports`: [{`port`: 80}]}}]"),
      "{" ++ kube_env() ++ "}")
    checkj("ipv6 udp service",
      senv(True{}, "[{`metadata`: {`name`: `dns-svc`}, `spec`: {`clusterIP`: `fd00::1`, `ports`: [{`name`: `dns`, `port`: 53, `protocol`: `UDP`}]}}]"),
      "{" ++ kube_env() ++ ", `DNS_SVC_SERVICE_HOST`: `fd00::1`, `DNS_SVC_SERVICE_PORT`: `53`, `DNS_SVC_SERVICE_PORT_DNS`: `53`, `DNS_SVC_PORT`: `udp://[fd00::1]:53`, `DNS_SVC_PORT_53_UDP`: `udp://[fd00::1]:53`, `DNS_SVC_PORT_53_UDP_PROTO`: `udp`, `DNS_SVC_PORT_53_UDP_PORT`: `53`, `DNS_SVC_PORT_53_UDP_ADDR`: `fd00::1`}")

    # DNS (translateDNSConfig).
    checkj("dns cluster first",
      J.Json.obj([J.KV{"p", spec_at(tr(cfg(), inp("10.96.0.10", "1.2.3.4"), pod("`dnsPolicy`: `ClusterFirst`")), "dnsPolicy")},
        J.KV{"c", spec_at(tr(cfg(), inp("10.96.0.10", "1.2.3.4"), pod("`dnsPolicy`: `ClusterFirst`")), "dnsConfig")}]),
      "{`p`: `None`, `c`: {`nameservers`: [`10.96.0.10`], `options`: [{`name`: `ndots`, `value`: `5`}], `searches`: [`ns1.svc.cluster.local`, `svc.cluster.local`, `cluster.local`]}}")
    checkj("dns cluster first with host network stays",
      J.Json.obj([J.KV{"p", spec_at(tr(cfg(), inp("10.96.0.10", "1.2.3.4"), pod("`dnsPolicy`: `ClusterFirst`, `hostNetwork`: true")), "dnsPolicy")},
        J.KV{"c", spec_at(tr(cfg(), inp("10.96.0.10", "1.2.3.4"), pod("`dnsPolicy`: `ClusterFirst`, `hostNetwork`: true")), "dnsConfig")}]),
      "{`p`: `ClusterFirst`}")
    checkj("dns merges the pod's config",
      spec_at(tr(cfg(), inp("10.96.0.10", "1.2.3.4"), pod("`dnsPolicy`: `ClusterFirstWithHostNet`, `dnsConfig`: {`nameservers`: [`8.8.8.8`, `10.96.0.10`], `searches`: [`cluster.local`, `example.com`], `options`: [{`name`: `edns0`}]}")), "dnsConfig"),
      "{`nameservers`: [`10.96.0.10`, `8.8.8.8`], `options`: [{`name`: `ndots`, `value`: `5`}], `searches`: [`ns1.svc.cluster.local`, `svc.cluster.local`, `cluster.local`, `example.com`]}")
    checkj("dns none stays",
      spec_at(tr(cfg(), inp("10.96.0.10", "1.2.3.4"), pod("`dnsPolicy`: `None`")), "dnsPolicy"), "`None`")
    checkj("dns without a dns ip stays",
      spec_at(tr(cfg(), inp("", "1.2.3.4"), pod("`dnsPolicy`: `ClusterFirst`")), "dnsPolicy"), "`ClusterFirst`")

    # Field references (translateFieldRef).
    check("field ref name", P.Pods.field_path("suffix", "metadata.name"), "metadata.annotations['vcluster.loft.sh/name']")
    check("field ref labels", P.Pods.field_path("suffix", "metadata.labels"), "metadata.annotations['vcluster.loft.sh/labels']")
    check("field ref service account", P.Pods.field_path("suffix", "spec.serviceAccountName"), "metadata.annotations['vcluster.loft.sh/service-account-name']")
    check("field ref reserved label", P.Pods.field_path("suffix", "metadata.labels['release']"), "metadata.labels['vcluster.loft.sh/label-suffix-x-a4d451ec23']")
    check("field ref plain label", P.Pods.field_path("suffix", "metadata.labels['app']"), "metadata.labels['app']")
    check("field ref other", P.Pods.field_path("suffix", "status.podIP"), "status.podIP")

    # LabelsAnnotation.
    check("labels annotation sorts lines", P.Pods.labels_text([M.KV{"a", "x"}, M.KV{"a.b", "y"}]), "a.b=\"y\"\na=\"x\"")

    # Container environment (TranslateContainerEnv).
    checkj("env refs translated",
      J.Json.arr(P.Pods.env_list("suffix", "ns1", [], J.Json.items(j("[{`name`: `A`, `valueFrom`: {`configMapKeyRef`: {`name`: `cm`, `key`: `k`}}}, {`name`: `B`, `valueFrom`: {`secretKeyRef`: {`name`: `s`, `key`: `k`}}}, {`name`: `C`, `valueFrom`: {`fieldRef`: {`fieldPath`: `metadata.namespace`}}}, {`name`: `D`, `value`: `d`}]")))),
      "[{`name`: `A`, `valueFrom`: {`configMapKeyRef`: {`name`: `cm-x-ns1-x-suffix`, `key`: `k`}}}, {`name`: `B`, `valueFrom`: {`secretKeyRef`: {`name`: `s-x-ns1-x-suffix`, `key`: `k`}}}, {`name`: `C`, `valueFrom`: {`fieldRef`: {`fieldPath`: `metadata.annotations['vcluster.loft.sh/namespace']`}}}, {`name`: `D`, `value`: `d`}]")
    checkj("env service variables first, own names kept",
      J.Json.arr(P.Pods.env_list("suffix", "ns1", [M.KV{"A", "1"}, M.KV{"B", "2"}], J.Json.items(j("[{`name`: `B`, `value`: `mine`}]")))),
      "[{`name`: `A`, `value`: `1`}, {`name`: `B`, `value`: `mine`}]")
    checkj("env from translated",
      J.Json.arr(P.Pods.tr_env_froms("suffix", "ns1", J.Json.items(j("[{`configMapRef`: {`name`: `cm2`}}, {`secretRef`: {`name`: `s2`}, `prefix`: `P_`}]")))),
      "[{`configMapRef`: {`name`: `cm2-x-ns1-x-suffix`}}, {`secretRef`: {`name`: `s2-x-ns1-x-suffix`}, `prefix`: `P_`}]")

    # Hostname and images.
    check("hostname dots and trailing dash", P.Pods.hostname_of("my.pod."), "my-pod")
    check("hostname cut to 63", P.Pods.hostname_of("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"), "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    check("image translated", P.Pods.image([M.KV{"nginx", "mirror/nginx"}], "nginx"), "mirror/nginx")
    check("image kept", P.Pods.image([M.KV{"nginx", "mirror/nginx"}], "busybox"), "busybox")
    checkj("container image translated on the host",
      J.Json.get(first(spec_at(tr(P.Pods.cfg.set_images(cfg(), [M.KV{"nginx", "mirror/nginx"}]), inp("", "1.2.3.4"), pod("`containers`: [{`name`: `c`, `image`: `nginx`}]")), "containers")), "image"),
      "`mirror/nginx`")

    # Namespace labels and the marker labels.
    checkj("host labels",
      J.Json.get(J.Json.get(tr(cfg(), P.Inp{[M.KV{"team", "x"}], [], "", "", [], []}, j("{`metadata`: {`name`: `web`, `namespace`: `ns1`, `labels`: {`app`: `a`}}, `spec`: {}}")), "metadata"), "labels"),
      "{`app`: `a`, `vcluster.loft.sh/managed-by`: `suffix`, `vcluster.loft.sh/namespace`: `ns1`, `vcluster.loft.sh/ns-label-suffix-x-ca8b22d0db`: `x`}")

    # Service account tokens.
    checkj("token requests",
      J.Json.arr(P.Pods.token_requests(cfg(), pod("`serviceAccountName`: `app`, `volumes`: [{`name`: `v`, `projected`: {`sources`: [{`serviceAccountToken`: {`path`: `token`}}, {`serviceAccountToken`: {`audience`: `vault`, `path`: `t2`}}]}}]"))),
      "[{`serviceAccountName`: `app`, `namespace`: `ns1`, `request`: {`apiVersion`: `authentication.k8s.io/v1`, `kind`: `TokenRequest`, `spec`: {`audiences`: [`https://kubernetes.default.svc.cluster.local`, `https://kubernetes.default.svc`, `https://kubernetes.default`], `boundObjectRef`: {`apiVersion`: `v1`, `kind`: `Pod`, `name`: `web`, `uid`: `vu`}, `expirationSeconds`: 315360000}}}, {`serviceAccountName`: `app`, `namespace`: `ns1`, `request`: {`apiVersion`: `authentication.k8s.io/v1`, `kind`: `TokenRequest`, `spec`: {`audiences`: [`vault`], `boundObjectRef`: {`apiVersion`: `v1`, `kind`: `Pod`, `name`: `web`, `uid`: `vu`}, `expirationSeconds`: 315360000}}}]")
    checkj("token as annotation",
      J.Json.obj([J.KV{"a", ann_at(tr(cfg(), P.Inp{[], [], "", "1.2.3.4", [P.Tok{"abcdefgh", "TOKEN"}], []}, tok_pod()), "vcluster.loft.sh/token-abcdefgh")},
        J.KV{"v", first(spec_at(tr(cfg(), P.Inp{[], [], "", "1.2.3.4", [P.Tok{"abcdefgh", "TOKEN"}], []}, tok_pod()), "volumes"))}]),
      "{`a`: `TOKEN`, `v`: {`name`: `kube-api-access`, `projected`: {`sources`: [{`downwardAPI`: {`items`: [{`path`: `token`, `fieldRef`: {`apiVersion`: `v1`, `fieldPath`: `metadata.annotations['vcluster.loft.sh/token-abcdefgh']`}, `mode`: 420}]}}, {`configMap`: {`name`: `kube-root-ca.crt-x-ns1-x-suffix`}}]}}}")
    checkj("token as secret",
      first(spec_at(tr(P.Pods.cfg.set_sa_secrets(cfg(), True{}), P.Inp{[], [], "", "1.2.3.4", [P.Tok{"abcdefgh", "TOKEN"}], []}, tok_pod()), "volumes")),
      "{`name`: `kube-api-access`, `projected`: {`sources`: [{`secret`: {`name`: `web-sa-token-x-ns1-x-suffix`, `items`: [{`key`: `kube-api-access`, `path`: `token`, `mode`: 420}]}}, {`configMap`: {`name`: `kube-root-ca.crt-x-ns1-x-suffix`}}]}}")
    check("token secret",
      show_mj(P.Pods.token_secret(P.Pods.cfg.set_sa_secrets(cfg(), True{}), P.Inp{[], [], "", "1.2.3.4", [P.Tok{"abcdefgh", "TOKEN"}], []}, tok_pod())),
      show(j("{`apiVersion`: `v1`, `kind`: `Secret`, `metadata`: {`name`: `web-sa-token-x-ns1-x-suffix`, `namespace`: `test`, `annotations`: {`vcluster.loft.sh/skip-backsync`: `true`}}, `type`: `Opaque`, `stringData`: {`kube-api-access`: `TOKEN`}}")))
    check("no token secret by default",
      show_mj(P.Pods.token_secret(cfg(), P.Inp{[], [], "", "1.2.3.4", [P.Tok{"abcdefgh", "TOKEN"}], []}, tok_pod())), "none")

    # Owner references and the autoscaler annotations.
    checkj("owner annotations",
      J.Json.obj([J.KV{"refs", ann_at(tr(cfg(), inp("", "1.2.3.4"), j("{`metadata`: {`name`: `web`, `namespace`: `ns1`, `ownerReferences`: [{`apiVersion`: `apps/v1`, `kind`: `ReplicaSet`, `name`: `web-abc`, `uid`: `u1`, `controller`: true, `blockOwnerDeletion`: true}]}, `spec`: {}}")), "vcluster.loft.sh/owner-references")},
        J.KV{"kind", ann_at(tr(cfg(), inp("", "1.2.3.4"), j("{`metadata`: {`name`: `web`, `namespace`: `ns1`, `ownerReferences`: [{`apiVersion`: `apps/v1`, `kind`: `ReplicaSet`, `name`: `web-abc`, `uid`: `u1`, `controller`: true, `blockOwnerDeletion`: true}]}, `spec`: {}}")), "vcluster.loft.sh/owner-set-kind")},
        J.KV{"evict", ann_at(tr(cfg(), inp("", "1.2.3.4"), j("{`metadata`: {`name`: `web`, `namespace`: `ns1`, `ownerReferences`: [{`apiVersion`: `apps/v1`, `kind`: `ReplicaSet`, `name`: `web-abc`, `uid`: `u1`, `controller`: true, `blockOwnerDeletion`: true}]}, `spec`: {}}")), "cluster-autoscaler.kubernetes.io/safe-to-evict")}]),
      "{`refs`: `[{\\`apiVersion\\`:\\`apps/v1\\`,\\`kind\\`:\\`ReplicaSet\\`,\\`name\\`:\\`web-abc\\`,\\`uid\\`:\\`u1\\`,\\`controller\\`:true,\\`blockOwnerDeletion\\`:true}]`, `kind`: `ReplicaSet`, `evict`: `true`}")
    checkj("daemonset pod",
      ann_at(tr(cfg(), inp("", "1.2.3.4"), j("{`metadata`: {`name`: `web`, `namespace`: `ns1`, `ownerReferences`: [{`apiVersion`: `apps/v1`, `kind`: `DaemonSet`, `name`: `ds`, `uid`: `u2`, `controller`: true}]}, `spec`: {}}")), "cluster-autoscaler.kubernetes.io/daemonset-pod"),
      "`true`")

    # Priority classes.
    checkj("priority capped",
      J.Json.obj([J.KV{"n", spec_at(tr(P.Pods.cfg.set_pc_to_host(cfg(), True{}), inp("", "1.2.3.4"), pod("`priorityClassName`: `high`, `priority`: 2000000000")), "priorityClassName")},
        J.KV{"p", spec_at(tr(P.Pods.cfg.set_pc_to_host(cfg(), True{}), inp("", "1.2.3.4"), pod("`priorityClassName`: `high`, `priority`: 2000000000")), "priority")}]),
      "{`n`: `vcluster-high-x-test-x-suffix`, `p`: 1000000000}")
    checkj("priority cleared without priority class sync",
      J.Json.obj([J.KV{"n", spec_at(tr(cfg(), inp("", "1.2.3.4"), pod("`priorityClassName`: `x`, `priority`: 5")), "priorityClassName")},
        J.KV{"p", spec_at(tr(cfg(), inp("", "1.2.3.4"), pod("`priorityClassName`: `x`, `priority`: 5")), "priority")}]),
      "{}")

    # Host paths.
    checkj("kubelet sub-path uid translated",
      first(spec_at(tr(cfg(), P.Inp{[], [], "", "", [], [M.KV{"vuid", "huid"}]}, pod("`volumes`: [{`name`: `x`, `hostPath`: {`path`: `/var/lib/kubelet/pods/vuid/volumes/x`}}]")), "volumes")),
      "{`name`: `x`, `hostPath`: {`path`: `/var/lib/kubelet/pods/huid/volumes/x`}}")
    check("kubelet sub-path without uid fails",
      show_maybe(P.Pods.check(cfg(), pod("`volumes`: [{`name`: `x`, `hostPath`: {`path`: `/var/lib/kubelet/pods//x`}}]"))),
      "failed to translate kubelet sub-path for pPod web-x-ns1-x-suffix: no virtual UID found in hostPath /var/lib/kubelet/pods//x")

    # Ephemeral containers are translated like containers.
    check("ephemeral containers kept",
      String.join(P.Pods.names(J.Json.items(spec_at(tr(cfg(), inp("", "1.2.3.4"), pod("`ephemeralContainers`: [{`name`: `dbg`}]")), "ephemeralContainers"))), ","), "dbg")

    # The syncer's writes.
    check("started virtual pod without host pod is deleted",
      show_ws(P.Pods.sync(cfg(), sin([]), None{}, None{}, None{}, Some{j("{`metadata`: {`name`: `web`, `namespace`: `ns1`}, `spec`: {}, `status`: {`startTime`: `2026-01-01T00:00:00Z`}}")})),
      "DeleteVirtual 0 ;")
    check("missing dns ip",
      show_ws(P.Pods.sync(cfg(), P.SInp{inp("", "1.2.3.4"), P.DInp{[], []}, [], True{}, False{}, None{}}, None{}, None{}, None{}, Some{pod("")})),
      "Error waiting for DNS service IP;")
    check("host pod deleting deletes the virtual pod",
      show_ws(P.Pods.sync(cfg(), sin([]), Some{j("{`metadata`: {`name`: `web-x-ns1-x-suffix`, `namespace`: `test`, `deletionTimestamp`: `2026-01-01T00:00:00Z`, `deletionGracePeriodSeconds`: 10}, `spec`: {}}")},
        Some{j("{`metadata`: {`name`: `web-x-ns1-x-suffix`, `namespace`: `test`, `deletionTimestamp`: `2026-01-01T00:00:00Z`, `deletionGracePeriodSeconds`: 10}, `spec`: {}}")},
        Some{pod("`terminationGracePeriodSeconds`: 10")}, Some{pod("`terminationGracePeriodSeconds`: 10")})),
      "DeleteVirtual 10 ;")
    check("virtual pod deleting deletes the host pod",
      show_ws(P.Pods.sync(cfg(), sin([]), Some{j("{`metadata`: {`name`: `web-x-ns1-x-suffix`, `namespace`: `test`, `uid`: `hu`}, `spec`: {}}")},
        Some{j("{`metadata`: {`name`: `web-x-ns1-x-suffix`, `namespace`: `test`, `uid`: `hu`}, `spec`: {}}")},
        Some{j("{`metadata`: {`name`: `web`, `namespace`: `ns1`, `deletionTimestamp`: `2026-01-01T00:00:00Z`, `deletionGracePeriodSeconds`: 5}, `spec`: {}}")},
        Some{j("{`metadata`: {`name`: `web`, `namespace`: `ns1`, `deletionTimestamp`: `2026-01-01T00:00:00Z`, `deletionGracePeriodSeconds`: 5}, `spec`: {}}")})),
      "DeleteHost 5 hu;")
    check("host node binds the virtual pod",
      show_ws(P.Pods.sync(cfg(), sin(["n1"]), Some{j("{`metadata`: {`name`: `web-x-ns1-x-suffix`, `namespace`: `test`}, `spec`: {`nodeName`: `n1`}}")},
        Some{j("{`metadata`: {`name`: `web-x-ns1-x-suffix`, `namespace`: `test`}, `spec`: {`nodeName`: `n1`}}")}, Some{pod("")}, Some{pod("")})),
      "Bind n1;Requeue 0;")
    check("virtual node differs from the host's",
      show_ws(P.Pods.sync(cfg(), sin([]), Some{j("{`metadata`: {`name`: `web-x-ns1-x-suffix`, `namespace`: `test`}, `spec`: {}}")},
        Some{j("{`metadata`: {`name`: `web-x-ns1-x-suffix`, `namespace`: `test`}, `spec`: {}}")}, Some{pod("`nodeName`: `n2`")}, Some{pod("`nodeName`: `n2`")})),
      "DeleteVirtual 30 ;")
    check("host pod without virtual pod is deleted",
      show_ws(P.Pods.sync(cfg(), sin([]), None{}, Some{j("{`metadata`: {`name`: `web-x-ns1-x-suffix`, `namespace`: `test`}, `spec`: {}}")}, Some{pod("")}, None{})),
      "DeleteHost  ;")
    check("node selector with unknown node waits",
      show_ws(P.Pods.sync(P.Pods.cfg.set_node_selector(cfg(), [M.KV{"pool", "a"}]), sin([]), None{}, None{}, None{}, Some{pod("`nodeName`: `n9`")})),
      "Event Warning SyncWarning Given nodeName n9 does not exist in virtual cluster;Requeue 15000;")
    check("virtual scheduler waits for a node",
      show_ws(P.Pods.sync(P.Pods.cfg.set_virtual_scheduler(cfg(), True{}), sin([]), None{}, None{}, None{}, Some{pod("")})), "")
    checkj("virtual label change reaches the host",
      J.Json.get(J.Json.get(snd(P.Pods.diff(cfg(), P.DInp{[], []},
        j("{`metadata`: {`name`: `web-x-ns1-x-suffix`, `namespace`: `test`, `labels`: {`a`: `1`, `vcluster.loft.sh/managed-by`: `suffix`, `vcluster.loft.sh/namespace`: `ns1`}}, `spec`: {}}"),
        j("{`metadata`: {`name`: `web-x-ns1-x-suffix`, `namespace`: `test`, `labels`: {`a`: `1`, `vcluster.loft.sh/managed-by`: `suffix`, `vcluster.loft.sh/namespace`: `ns1`}}, `spec`: {}}"),
        j("{`metadata`: {`name`: `web`, `namespace`: `ns1`, `labels`: {`a`: `1`}}, `spec`: {}}"),
        j("{`metadata`: {`name`: `web`, `namespace`: `ns1`, `labels`: {`a`: `2`}}, `spec`: {}}"))), "metadata"), "labels"),
      "{`a`: `2`, `vcluster.loft.sh/managed-by`: `suffix`, `vcluster.loft.sh/namespace`: `ns1`}")
