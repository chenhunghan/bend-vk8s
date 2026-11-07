# Reimplementation spec: vcluster classic-mode serving layer, as read at commit a8ab30ea

Repo state: `main` at `a8ab30eab6f27b183a80783f4e5854c1a2eb6ef5`. I read the code only and did not run it.

**Test coverage.** Most of the serving layer has no unit test. These have none: `pkg/server/filters/redirect.go`, `service.go`, `nodename.go`, `nodechanges.go`, `kubelet.go`, `metrics.go`, `pkg/server/handler`, all of `pkg/authentication` and `pkg/authorization`, `pkg/apiservice` and `pkg/integrations/metricsserver`. I use three sources for examples:
- unit tests;
- e2e specs named `e2e/test_*.go`, which are run by `e2e/suite_*_test.go`;
- examples labelled "derived", which come from the code only.

## Findings

### 1. Processes, ports and who talks to whom

| Listener | Where | Notes |
|---|---|---|
| Proxy TLS server | `ControlPlane.Proxy.BindAddress:Port`, default `0.0.0.0:8443` | `config/values.yaml:244` `proxy:`, `:245` `bindAddress: "0.0.0.0"`, `:246` `port: 8443`. Bound at `pkg/server/server.go:280` `sso.BindPort = ctx.Config.ControlPlane.Proxy.Port`. |
| Virtual kube-apiserver | `127.0.0.1:6443` | `pkg/k8s/k8s.go:93` `"--bind-address=127.0.0.1"`, plus `--secure-port=6443`. Started as a child process by the syncer. |
| Aggregated API proxy for metrics-server | `localhost:9001`, TLS | `pkg/integrations/metricsserver/metricsserver.go:33` `const hostPort = 9001`. `pkg/apiservice/generic.go:166` `Addr: "localhost:" + strconv.Itoa(port)`. |
| Controller-manager and scheduler metrics, read by the proxy | `https://127.0.0.1:10257`, `https://127.0.0.1:10259` | `pkg/server/filters/k8s_metrics.go:17` and `:18`. TLS verification is off. |
| Host Service port `kubelet` | 10250, targetPort 8443 | `chart/templates/service.yaml:40-42`. Rendered only when `proxyKubelets.byHostname` is true and the Service type is not LoadBalancer. |
| Per-node host Service | port 10250, targetPort 8443 | `pkg/controllers/resources/nodes/nodeservice/node_service.go:30` `KubeletTargetPort = 8443`. The port is named `kubelet` at `:167`. |
| CoreDNS | listens 1053; Service 53 forwards to 1053; metrics 9153 | `pkg/coredns/template.go:17` `.:1053 {`. |

### 2. Handler chain, outermost to innermost

Source: `pkg/server/server.go:73-181` for the inner chain, `:353-361` and `:364-448` for the outer chain. Filters are applied in code order, so the last one applied is outermost.

1. `WithNodeName`. It is outermost, outside the generic chain: `server.go:356` `defaultHandler = filters.WithNodeName(defaultHandler, ...)`. In private-nodes mode it is `pro.WithKonnectivity` instead.
2. Generic chain from `DefaultBuildHandlerChain`, copied from k8s.io/apiserver:
   - AuditInit `:446`, PanicRecovery `:445`, MuxAndDiscoveryComplete `:444`, RequestReceivedTimestamp `:437`, RequestInfo `:436`, LatencyTrackers `:432`.
   - Tracing, only if the feature gate is on `:429`. HTTPLogging `:428`. HSTS `:421`. CacheControl `:420`. WarningRecorder `:419`.
   - Probabilistic GOAWAY, only when HTTP/2 is on and `GoawayChance > 0` `:416`.
   - WaitGroup `:409`. RequestDeadline `:407`. TimeoutForNonLongRunning `:405`. CORS `:401`.
   - Authentication `:398`. Audit `:390`.
   - `WithOriginalUser` then Impersonation `:384-386`. `WithOriginalUser` stores the pre-impersonation user under `servertypes.OriginalUserKey`.
   - MaxInFlight `:380`, or PriorityAndFairness when `FlowControl != nil`.
   - Authorization `:369`. Plugin interceptors `:366`.
3. The mux at `"/"`, `server.go:179`. Inside it, outermost to innermost:
   - Post hooks. In classic mode this is the metrics-server proxy.
   - `WithPprof`, only when `DEBUG=true`, `:170-172`.
   - `WithPodSchedulerCheck`, only with hybrid scheduling `:165`. The OSS body is a no-op: `pkg/server/filters/podscheduling.go:10-12`.
   - `WithFakeKubelet` `:163`.
   - `WithNodeChanges`, only when `Sync.FromHost.Nodes.Enabled && SyncBackChanges` `:160`.
   - `WithMetricsProxy` `:157`.
   - `WithRedirect` `:156`.
   - `WithServiceCreateRedirect` `:155`.
   - `WithK8sMetrics`. This one is installed even in private-nodes mode `:143`.
   - Pre hooks.
   - `ImpersonatingHandler("", virtualConfig)`, the terminal reverse proxy to the virtual kube-apiserver `:135`.

Every filter from `WithFakeKubelet` down to `WithServiceCreateRedirect` is installed only when `!PrivateNodes.Enabled` `:144`.

### 3. TLS server requirements

- **Serving cert.** It is supplied by the cert syncer: `server.go:279` `sso.ServerCert.GeneratedCert = s.certSyncer`.
  - Key type is EC: `pkg/server/cert/cert.go:128` `MakeEllipticPrivateKeyPEM`.
  - CN is `kube-apiserver` `:51`. ExtKeyUsage is ServerAuth.
  - The signing CA is `VirtualClusterKubeConfig().ServerCACert` and `ServerCAKey`.
  - The served chain is leaf then CA: `:148` `certificate := append(certhelper.EncodeCertPEM(cert), certhelper.EncodeCertPEM(caCert[0])...)`.
  - Validity defaults to `certhelper.DefaultCertDuration`. The code comment says 365 days. `DEVELOPMENT=true` plus `VCLUSTER_CERTS_VALIDITYPERIOD` overrides it: `:326-336`.
  - It regenerates when the CA is expired, which is an error: `:95` `expired CA certificate: %s`. It also regenerates when the leaf fails verification against the CA, when the leaf has 90 days or less left, or when a wanted SAN is missing. `pkg/util/certhelper/cert.go:116` `return diffDays <= 90`.
  - It re-evaluates every 2 seconds with jitter 1.25 and calls `Enqueue` on every listener each tick: `pkg/server/cert/syncer.go:104` and `:106` `}, time.Second*2, 1.25, true)`.
- **SANs.**
  - Fixed DNS names: `kubernetes.default.svc.<clusterDomain>`, `kubernetes.default.svc`, `kubernetes.default`, `kubernetes`, `localhost`. Fixed IP: `127.0.0.1`. Source: `cert.go:55-61` and `:69`.
  - Extra SANs gathered in `getExtraSANs`:
    - the ingress host;
    - `proxy.extraSANs`;
    - the host part of `controlPlane.endpoint`, which must parse as `host:port`;
    - the vcluster name and `name.namespace`;
    - `*.nodes.vcluster.com` `:224`;
    - `*.<vclusterName>.<ns>.nodes.vcluster.com`;
    - the host Service ClusterIP and LoadBalancer ingress IPs and hostnames;
    - pod host IPs, when the Service is NodePort;
    - the `POD_IP` env var `:293`;
    - node-service ClusterIPs, when `byIP` is true `:298`.
  - The fake kubelet hostname `<node-with-dashes>.nodes.vcluster.com` is covered by the single-label wildcard.
- **Client certs.**
  - Client auth is "request, do not require". `pkg/server/secure_serving.go:151` `tlsConfig.ClientAuth = tls.RequestClientCert`. This applies when `ClientCA != nil`.
  - `ClientCA` comes from `VirtualClusterKubeConfig().ClientCACert`: `server.go:291`. The upstream apply step at `vendor/k8s.io/apiserver/pkg/server/config.go:550-555` assigns it to the serving info.
  - Request-header auth uses `RequestHeaderCACert`: `server.go:290`.
  - Header names and the allowed-names default come from vendored `DelegatingAuthenticationOptions`. Not verified.
- **SNI.** No SNI certs are configured. `secure_serving.go:154` treats `len(s.SNICerts) > 0` as optional and nothing sets it. SNI is not used to pick a cert. Node identity comes from the HTTP Host header instead: `pkg/server/filters/nodename.go:40` `splitted := strings.Split(req.Host, ":")`. It needs exactly two parts, so Host without a port and IPv6 literals yield no node.
- **Protocols.**
  - TLS minimum is 1.2. `NextProtos` is `h2, http/1.1` `secure_serving.go:120-122`. `DisableHTTP2` forces `http/1.1` only `:126-129`.
  - HTTP/2 settings:
    - `MaxConcurrentStreams` is 1000: `server.go:278` `sso.HTTP2MaxStreamsPerConnection = 1000`.
    - Per-stream receive buffer and max frame size are both 256 KiB `:78`.
    - Per-connection buffer is stream buffer times streams `:102`.
    - Server pings after 30s idle with a 15s ping timeout `:43-44`.
  - HTTP/1 settings: `IdleTimeout` 90s, `ReadHeaderTimeout` 32s, `MaxHeaderBytes` 1 MiB `:67-71`.
  - TLS handshake errors are logged at `V(5)` and counted in `metrics.TLSHandshakeErrors` `:233-236`.
- **Upgrades, exec and websocket.**
  - Exec, attach and port-forward are reverse-proxied by `proxy.NewUpgradeAwareHandler` in `pkg/server/handler/handler.go:87-91`. Settings: `UseRequestLocation = true`, `UseLocationHost = true`.
  - The upgrade leg uses a separate HTTP/1.1-only transport: `handler.go:117` "makeUpgradeTransport creates a transport that explicitly bypasses HTTP2 support".
  - The SPDY and websocket handshake logic is in vendored apimachinery. Not verified.
  - Upgrade requests are long-running, so the request timeout does not apply. `server.go:204` lists `attach, exec, proxy, log, portforward`, and `:203` `watch, proxy` for verbs.
- **Timeouts.**
  - `LongRunningFunc` also exempts non-resource paths `/v2*`, `/node/download*` and `/node/control-plane-download*`: `server.go:195-199`.
  - The default `RequestTimeout` is said to be 60s in the comment at `:192`. Not verified in vendor.
  - `RunServer` uses `serverConfig.RequestTimeout` as the shutdown timeout, with `ctx.StopChan`: `server.go:309`.

### 4. Authentication

Order is fail-on-error, so the first error aborts the request: `server.go:301-305`.
1. `delegatingauthenticator.New(uncachedVirtualClient)`, wrapped in `bearertoken`.
   - It reads `Authorization`, splits on spaces, requires `bearer` case-insensitively, and rejects an empty token. A token with extra leading space adds the warning "the provided Authorization header contains extra space before the bearer token, and is ignored": `pkg/authentication/bearertoken/bearertoken.go:28`.
   - On success it deletes the `Authorization` header: `bearertoken.go:63-65`.
   - It creates a `TokenReview` in the virtual cluster `pkg/authentication/delegatingauthenticator/delegatingauthenticator.go:47` and `:52`.
   - Not authenticated returns `(nil, false, nil)`. A create error returns the error.
   - Only successes are cached, in an LRU of 512 entries for 5 seconds: `:17` and `:21`.
   - The user is built from `Status.User`: name, UID, groups, extra. Audiences are carried over.
2. `platformauthenticator.Default`. It returns no opinion unless `SetDelegate` was called: `platformauthenticator.go:31`. No OSS code calls `SetDelegate`. Not verified for the pro build.
3. The upstream delegating authenticator, for client certs and request headers. `RemoteKubeConfigFileOptional = true` and `SkipInClusterLookup = true`: `server.go:288-289`.

A failed authentication returns the upstream `Unauthorized` Status JSON. This is upstream behaviour and not verified in the repo.

### 5. Authorization

The union is, in order, `kubeletauthorizer`, `delegatingauthorizer`, `impersonationauthorizer`, `allowall`: `server.go:270-275`. The first Allow or Deny wins and NoOpinion falls through. Anything not matched by an earlier rule is allowed at this front door. The virtual kube-apiserver does the real RBAC when the request is proxied through with impersonation.

- **`kubeletauthorizer`.**
  - It acts only if `NodeNameFrom(ctx)` is set, otherwise NoOpinion: `pkg/authorization/kubeletauthorizer/authorizer.go:37`.
  - A resource request on a kubelet host is `DecisionDeny` with reason `forbidden`: `:41`.
  - Non-resource requests become a `SubjectAccessReview` in the virtual cluster, sent with the uncached virtual client, by path suffix:

    | Path test | SAR attributes |
    |---|---|
    | suffix `/stats/summary` `:62` | `get nodes/stats <node>` |
    | metrics suffixes `:71` | `get nodes/metrics <node>` |
    | `/pods` or `/runningpods` suffix, or prefix `/containerLogs/` `:80` | `get nodes/proxy <node>` |
    | anything else `:92` | NonResourceAttributes `{path, verb}` |

  - Allowed results are cached for 5 seconds in an LRU of 256 entries: `delegatingauthorizer/cache.go:14` and `:22`. Denials are never cached.
- **`delegatingauthorizer`.**
  - It applies only to the configured list. Otherwise NoOpinion `authorizer.go:48`.
  - It sends a `SubjectAccessReview` to the virtual cluster with the user, UID, groups, extra and the resource or non-resource attributes: `:58`. The result is allow when `Allowed && !Denied`. Otherwise it denies with `Status.Reason`.
  - Configured resources `server.go:100-126` and `:208-229`:
    - core `nodes/proxy` and `pods/{portforward,exec,attach,log}`, all verbs;
    - `services` `create`;
    - `metrics.k8s.io/*/*/*` for all verbs, when `Integrations.MetricsServer.Enabled`;
    - `subresources.kubevirt.io/*/*/*` for all verbs, when `Integrations.KubeVirt.Enabled`.
  - Configured non-resources `:243-269` and `:318-351`:
    - `/v2*`, verb `*` normally, or verb `!head,get` when `AnonymousPull` is on. This is added when the registry or docker-registry daemon is enabled.
    - `/vcluster/features`, verb `*`.
    - `/controller-manager/metrics`, `/scheduler/metrics`, `/metrics/controller-manager`, `/metrics/scheduler`, `/metrics/etcd`, `/metrics/kine`, `/metrics/syncer`.
  - Verb syntax: a comma list, `*`, or a leading `!` to negate. A path ending in `*` is a prefix match. Source: `authorizer.go:105` and `:114`.
- **`impersonationauthorizer`.** It acts only for resource requests with verb `impersonate`. Otherwise NoOpinion `authorizer.go:29`. Then it sends a SAR to the virtual cluster and caches allows.
- **`allowall`** returns Allow: `pkg/authorization/allowall/authorizer.go:16`.

### 6. Filters and handlers: what each intercepts

Common fact: `ImpersonatingHandler` returns an empty 401 when there is no user in the context: `handler.go:25-29`. Otherwise it copies the virtual config and sets `Impersonate.UserName`, `Groups` and `Extra` from that user: `handler.go:31-34`.

| Filter | Intercepts | Rewrites | Forwards to | Auth |
|---|---|---|---|---|
| `WithNodeName` `filters/nodename.go:23` | Every request, on Host header | Sets `nodeNameKey` in the context. It lists virtual Nodes by the field index `IndexByHostName`; exactly one match wins. If `byIP` is on, it also lists host Services in the host namespace by the `IndexByClusterIP` index and reads label `vcluster.loft.sh/node`. | Passes through | None. Provides input to `kubeletauthorizer`. |
| `WithFakeKubelet` `filters/kubelet.go:13` | Requests where the node name is set | Path becomes `/api/v1/nodes/<node>/proxy<path>` `:24`, then the allowlist below | Host API through `handleNodeRequest` or `streamNodeRequest` | `kubeletauthorizer` already ran. |
| `WithNodeChanges` `nodechanges.go:27` | core v1 `nodes`, verb `update` `:38` or `patch` `:62`, no `dryRun` | Update: copies only labels, `spec.taints`, `spec.unschedulable` and `status.capacity` from the virtual node onto the host node `:143-146`, using a merge patch. It uses the status subresource when the request is for `/status`. Patch: runs the patch as `dryRun=All` against the virtual server first `:89-91`, then applies the result as above. | Host Nodes through the uncached host client | See Contradictions. No SAR rule covers this. |
| `WithMetricsProxy` `metrics.go:41` | core `nodes/proxy`, any verb, resource requests | Strips port 10250 from the node segment. Then runs the subpath allowlist. | Host API | SAR `nodes/proxy` against the virtual cluster, via the redirect list. |
| `WithRedirect` `redirect.go:26` | core `nodes/proxy` and `pods/{portforward,exec,attach,log}` | See section 7 | Host API | SAR in the virtual cluster, via the delegating authorizer. |
| `WithServiceCreateRedirect` `service.go:30` | core `services`, no subresource, `create` `:47` or `update` `:74`, no `dryRun` | See section 8 | Host and virtual APIs | `create`: SAR. `update`: no front SAR. |
| `WithK8sMetrics` `k8s_metrics.go:22` | Exact paths | `/metrics/syncer` is served from the in-process controller-runtime registry. The others set the path to `/metrics`, drop `Authorization`, and forward. | See below | SAR non-resource via the delegating authorizer. |
| `WithPprof` `pprof.go:12` | Prefix `/debug/pprof/` | Dispatches `cmdline`, `profile`, `trace`, `symbol`, else Index | In-process | None. Only when `DEBUG=true`. |
| `WithPanicRecovery` `panic_recovery.go:53` | Every request | `http.ErrAbortHandler` is honoured silently. Otherwise `500 This request caused apiserver to panic. Look in the logs for details.` | n/a | n/a |

Other k8s_metrics.go targets, derived from `:50-70`:
- `/controller-manager/metrics` and `/metrics/controller-manager` go to `https://127.0.0.1:10257`.
- `/scheduler/metrics` and `/metrics/scheduler` go to `https://127.0.0.1:10259`.
- `/metrics/etcd` goes to `constants.LocalBackingStoreMetricsHost`, only when embedded etcd is on.
- `/metrics/kine` goes to the same host for embedded or external database stores. For etcd stores it falls through.

### 7. Exec, attach, port-forward, log and nodes/proxy

This is the main answer to "how do logs, exec and port-forward reach the real pod".
- These requests never reach the virtual kube-apiserver. The syncer front proxy catches them first and sends them to the host API server with host credentials.
- `WithRedirect` applies the resource list at `redirect.go:36`. It then calls admission webhooks `:85`. For `pods/{exec,attach,portforward}` only, it decodes the query into `PodExecOptions`, `PodAttachOptions` or `PodPortForwardOptions`, and runs the validating webhook plugins with operation CONNECT. Failure returns `pods/exec "<name>" is forbidden: <webhook error>`, derived from `NewForbidden`. The error is logged at `:122` as `Admission validate failed for %s: %v`.
- Path rewrite for non-node resources, `redirect.go:44-67`:
  - It requires a namespace. Otherwise it returns 400 `namespace required`.
  - It requires the path to split into at least 6 segments. Otherwise it returns 400 `unexpected url`.
  - It sets `splitted[4]` to the host namespace and `splitted[6]` to the host pod name, using `mappings.VirtualToHost` for Pods `:59`.
  - It appends a trailing `/` when there are exactly 8 segments `:66`, so the host API server does not redirect to the wrong path.
- It deletes `Authorization` `:76` and forwards with `handler.Handler("", HostManager.GetConfig(), nil)`. The query string is untouched. `command=`, `stdin=`, `tty=` and `container=` pass through as-is.
- Admission webhook client config is minimal. Mutating and validating plugins are registered, but the webhook config provider is empty: `server.go:538-541`. Only calls to `kubernetes.default.svc:443` are authenticated: `:520-534`. All other targets are anonymous, with a 30s timeout and user agent `kube-apiserver-admission`.
- `nodes/proxy` is always caught earlier by `WithMetricsProxy`, because that filter is outer. So the `info.Resource != "nodes"` branch in `WithRedirect` never runs for nodes.

Example, derived from code: `GET /api/v1/namespaces/team-a/pods/web/log?follow=true` with Upgrade headers absent.
- Authz sends a SAR `get pods/log web ns=team-a` to the virtual cluster.
- The path is rewritten to `/api/v1/namespaces/<host-ns>/pods/<translated-name>/log/`. The trailing `/` appears only when the path splits into exactly 8 segments, so `log` itself yields 8 and gets the slash.
- The request is forwarded to the host API server with the syncer's host credentials.

### 8. Service create and update interception

`pkg/server/filters/service.go`.
- Create:
  - The namespace is forced from RequestInfo.
  - If `GenerateName != ""` and `Name == ""`, the name is `GenerateName` plus a random 5-character suffix `:208-211`.
  - The host Service gets `translate.HostMetadata`, the annotation `services.ServiceBlockDeletion=true` `:217`, and a translated selector.
  - After the host create, the virtual Service copies `ClusterIP`, `ClusterIPs`, `Ports`, `HealthCheckNodePort` and `Status` from the host Service. It is then created with an impersonating client for the requesting user.
  - If the virtual create fails, the host Service is deleted `:238`.
  - Success returns 201 with the virtual object. Host `AlreadyExists` is mapped to `services "<name>" already exists`.
- Update, PUT only:
  - It runs only when the stored virtual Service has `Type: ExternalName` `:90`.
  - If the `resourceVersion` differs, the type is unchanged, or `ClusterIP` is set, it does a plain virtual update.
  - Otherwise it patches the host Service with `Type`, `Ports` and `ClusterIP=""`, then copies back `ClusterIP`, `HealthCheckNodePort` and `Ports`, and updates the virtual Service. If that fails it deletes the host Service.
  - Because the verb must be `update`, a PATCH for the same type change is not intercepted. Derived.

### 9. Kubelet proxy allowlist and rewriting

`pkg/server/filters/metrics.go`. It applies both to `nodes/proxy` requests and to fake-kubelet requests.
- Port rewrite `:61-75`. The node segment is `splitted[4]`. A `name:port` or `scheme:name:port` form with port `10250` loses the port: `name:10250` becomes `name`, and `https:name:10250` becomes `https:name:`.
- `enforceKubeletSubpathAllowlist` at `:117-225`. Its last parameter is `Sync.FromHost.Nodes.Enabled`:
  - Suffix `/healthz`: allowed in all modes `:126`.
  - Metrics, stats or pods suffixes: allowed, with the response filtered `:130`.
  - `containerLogs`: see below.
  - Anything else: with shared nodes on, 403 `proxy subpath not permitted in shared mode` `:213-220`. With shared nodes off, it is forwarded `:222-223`.
- `containerLogs` rules `:134-210`:
  - The path must be `.../containerLogs/<ns>/<pod>/<container>` with all three non-empty.
  - The pod must be found in the mappings store and must exist in the virtual cluster. The container must be in the virtual pod's containers, init containers or ephemeral containers.
  - Otherwise: `nodes is forbidden: access denied: pod does not belong to this virtual cluster`, derived from `NewForbidden` with an empty name.
  - On success it rewrites the namespace and name to host values and streams the response without buffering, so `logs -f` works `:207`. A non-NotFound error from the virtual Get is returned as itself, not as a denial `:163-167`.
- `handleNodeRequest` `:240-287`:
  - It deletes `Authorization`, calls the host with a buffered `ExecuteRequest`, and decodes gzip responses.
  - A non-200 response is passed through unchanged.
  - Metrics are rewritten and the Content-Type is set from `expfmt.Negotiate`.
  - Pods and stats JSON drop `Content-Length`.
- Rewrites:
  - Prometheus text: label `pod`, `namespace` and `persistentvolumeclaim` are mapped host to virtual. Series for unmapped pods or PVCs are dropped. Series without pod or PVC labels are kept. Output is sorted by family name `:415-428`.
  - Stats summary: pods are mapped to virtual name, namespace and UID. Volumes with an unmapped PVC are dropped. Pods missing in the virtual cluster are dropped. Output is `json.MarshalIndent` with two spaces.
  - `/pods` and `/runningpods`: returns the virtual `Pod` objects, filtered.

### 10. Metrics-server integration and the aggregated API proxy

- `pkg/integrations/metricsserver/metricsserver.go`.
  - `Register` returns early in private-nodes mode `:77`.
  - If the vcluster does not deploy its own metrics server, it appends `RegisterOrDeregisterAPIService` to `AcquiredLeaderHooks` `:55`. That hook runs after the controllers register.
  - If the integration is enabled, it starts the 9001 listener on every replica, because integrations start before leader election. It also appends a post-hook that applies the same proxy handler on the 8443 server `:75`.
  - Defaults: service name `metrics-server`, namespace `kube-system`, port 443.
- `StartAPIServiceProxy` `pkg/apiservice/generic.go:181-217`.
  - Target is `https://<svc>.<ns>[:port]` with the host config's TLS fields cleared and `Insecure = true` `:201`.
  - The 9001 server uses `ServerCACert` and `ServerCAKey` directly as its TLS cert and key, with plain `ListenAndServeTLS`: `:157-158` and `:172`.
  - It runs `WithRequestInfo`, and has no authentication, no panic recovery and no timeouts.
- `serveHandler` `:219-237`: only GET is allowed, and only discovery-like paths. These are `openapi*`, empty path, `version`, `api`, `apis`, `apis/<g>` and `apis/<g>/<v>`, `api/<v>`, `.well-known`, `readyz`, `livez` `:239-273`. Anything else is 403 `paths other than discovery paths are not allowed`, via `NewForbidden`.
- `RegisterAPIService` and `createOperation` `:89-154`.
  - They create the Service `kube-system/<name>` as ExternalName `localhost` with the port `9001`, and the `APIService <version>.<group>`: `InsecureSkipTLSVerify: true`, `GroupPriorityMinimum: 100`, `VersionPriority: 100`.
  - They retry with exponential backoff, base 1s, factor 1.5, cap 1 minute.
  - `protection.go` adds a `ValidatingAdmissionPolicy` named `vcluster-protected-apiservices`. It denies DELETE on labelled Services and APIServices with the message `deletion of vCluster-protected resources is denied; remove the corresponding entry from your vCluster configuration`. The label key is `vcluster.loft.sh/protected`. Per-feature bindings are named `vcluster-protected-<tag>`.
- `WithMetricsServerProxy` handles `metrics.k8s.io/v1beta1` `nodes` and `pods`. The handler is `handleMetricsServerProxyRequest`.
  - Label selectors in `?labelSelector=` are translated with `translate.HostLabel` per key.
  - Pod GET: the namespace and name segments `[5]` and `[7]` become host values, and the response name and namespace are rewritten back.
  - Pod LIST:
    - A namespaced list rewrites segment `[5]`. For all namespaces in single-namespace-target mode it inserts `namespaces/<hostNS>`.
    - Results are filtered to the virtual pods that exist, matched by host key, then renamed and relabelled with the virtual pod's labels.
    - A Table request `Accept: ...as=Table;...` is rewritten row by row.
  - Nodes:
    - A Table request is refused: 403, `cannot list nodes in table response format` `:207`.
    - Otherwise nodes are filtered to those that exist in the virtual cluster, with labels replaced by the virtual labels.

### 11. Node sync and how a "kubelet" is reached

- **Syncer choice.** `pkg/controllers/resources/nodes/register.go:21` and `:24`. If `Sync.FromHost.Nodes.Enabled` is false, which is the default, a fake node syncer runs. Otherwise the real node syncer runs.
- **Fake nodes.** `fake_syncer.go`.
  - A fake node is created for a node name only when a virtual or non-DaemonSet host pod is assigned to it: `FakeSyncToVirtual` `:68` and `isNodeNeededByPod`.
  - Labels are `vcluster.loft.sh/fake-node: "true"` `:161` plus arch, os and `kubernetes.io/hostname: fake-<name>`.
  - Capacity and allocatable are fixed: cpu 16, memory 32Gi, ephemeral-storage 100Gi, pods 110.
  - It sets all four conditions: MemoryPressure False, DiskPressure False, PIDPressure False, Ready True. Kubelet and kube-proxy version come from `FakeNodesVersion`, which is set from the virtual cluster version at `controller_context.go:378`.
  - Taints are cleared after creation `:277`.
  - `kubelet` port in `status.daemonEndpoints.kubeletEndpoint.port` is `10250`.
  - A fake node is deleted when no pod needs it anymore `:90`.
- **Real nodes.** `syncer.go`.
  - The real syncer creates a virtual node for a host node only if `shouldSync` is true `:357`. That is when the selector matches, or when a pod needs the node, and it requeues after creating.
  - It writes the marker label `translate.MarkerLabel`.
  - With fake kubelets on, it sets `DaemonEndpoints` to port 10250 and rewrites addresses: `translate.go:126-142`.
    - It adds a Hostname address `<node with dots replaced by dashes>.nodes.vcluster.com` when `byHostname` is on `:135`.
    - It adds an InternalIP, the node-service ClusterIP, when `byIP` is on `:142`.
    - It keeps other address types and drops the host's own InternalIP, InternalDNS and Hostname addresses.
- **Per-node Service.** `nodeservice.GetNodeIP` `node_service.go:125`. It creates a host Service `SafeConcatName(vclusterName, "node", <name with dots replaced>)`:
  - port 10250 named `kubelet`;
  - labels `vcluster.loft.sh/belongs-to` and `vcluster.loft.sh/node`;
  - the vcluster Service's selector, with targetPort 8443 `:151`;
  - when that selector is nil, a hand-built Endpoints object that copies the `https` port as `kubelet` `:222`.
  A cleanup loop runs every 4 seconds `:63`.
- **How a pod or in-cluster client reaches the fake kubelet.**
  1. The client resolves `<node>.nodes.vcluster.com`. CoreDNS rewrites it to `kubernetes.default.svc.cluster.local` `pkg/coredns/template.go:25`. That ClusterIP equals the host vcluster Service ClusterIP, because `SyncKubernetesService` copies it: `pkg/specialservices/service_syncer.go:59`.
  2. It connects to port 10250. The host Service maps that to the syncer's 8443.
  3. The syncer reads the Host header. `WithNodeName` finds the node, `kubeletauthorizer` applies SARs, and `WithFakeKubelet` forwards to the host API server's `nodes/<node>/proxy/...`.
  - By IP, the client connects to the per-node Service ClusterIP on 10250 and `WithNodeName` finds the node through the `IndexByClusterIP` index.
  - e2e confirms: `https://<hostname>:<port>/healthz` returns `ok`. `e2e/test_core/coredns/test_coredns.go:141` and the curl at `:187`.
- **Embedded kube-apiserver flags.** In classic mode it is started without `--kubelet-preferred-address-types` or kubelet client certs. These flags are added only when `PrivateNodes.Enabled`: `pkg/k8s/k8s.go:85-93`. The upstream default address-type order is therefore used. Not verified in vendor. The syncer does not forward `exec`, `log` or `portforward` to that apiserver, so this does not affect those verbs.

### 12. CoreDNS

- `pkg/coredns/coredns.go`.
  - `ApplyManifest` returns nil when `ControlPlane.CoreDNS.Enabled` is false `:39-41`.
  - Image: default `coredns/coredns:1.14.2` `:21`. `constants.CoreDNSVersionMap` maps virtual `Major.Minor` from 1.30 to 1.36 to pinned images, for example `1.34` maps to `coredns/coredns:1.12.1`. A registry prefix is added: the configured `defaultImageRegistry` with a trailing slash trimmed, or `docker.io` `:62-67`.
  - Tests: `pkg/coredns/coredns_test.go:19` and `:24`. Known version `1.34` yields `docker.io/coredns/coredns:1.12.1`. Unknown `1.99` yields `docker.io/` plus `DefaultImage`.
  - Run-as uid and gid are the process's, falling back to 1001 if root `:95-113`. `HOST_CLUSTER_DNS` is the first nameserver in `/etc/resolv.conf`, or the literal path `/etc/resolv.conf`.
- Corefile `template.go:14-62`:
  - listens on 1053 with plugins `errors`, `health`, `ready`;
  - `vcluster` only when embedded and `networking.resolveDNS`;
  - `rewrite name regex .*\.nodes\.vcluster\.com kubernetes.default.svc.cluster.local` when `byHostname`;
  - `kubernetes <clusterDomain?> cluster.local in-addr.arpa ip6.arpa`, with `fallthrough` limited to `in-addr.arpa ip6.arpa` unless `fallbackHostCluster`;
  - `hosts /etc/coredns/NodeHosts` with ttl 60, reload 15s, and fallthrough;
  - `prometheus :9153`;
  - `forward . /etc/resolv.conf`, or the host DNS when `fallbackHostCluster`, or with `fallbackDns` when network policies are on;
  - `cache 30`, `loop`, `reload` only when not embedded, `loadbalance`;
  - `import /etc/coredns/custom/*.server`.
- Manifests `template.go:64-`. `overwriteManifests` replaces everything. Embedded mode produces only a ConfigMap `coredns` with `NodeHosts: ""` and the `kube-dns` Service. Default mode produces ServiceAccount, ClusterRole and ClusterRoleBinding `system:coredns`, ConfigMap, Deployment `coredns` (replicas from config, label `k8s-app: vcluster-kube-dns`, args `-conf /etc/coredns/Corefile`, probes on 8080 `/health` and 8181 `/ready`), and the `kube-dns` Service in `kube-system`. The default Service ports are 53 UDP and 53 TCP to targetPort 1053, plus 9153.
- Apply loop `pkg/setup/controllers.go:158-191`.
  - It runs in a goroutine with exponential backoff, 1s base, factor 1.5, cap 1 minute, forever.
  - If the existing Deployment's selector label `k8s-app` is not `vcluster-kube-dns`, it deletes the Deployment first, because the selector is immutable.
  - `ErrNoCoreDNSManifests` ends the loop quietly. Any other error is retried.
  - When `CoreDNS.Embedded` is true, the Deployment `coredns` is deleted afterwards.
- NodeHosts controller `pkg/controllers/coredns/nodehosts.go`.
  - It is named `coredns_nodehosts` `:122`. It watches the virtual `kube-system/coredns` ConfigMap with a `ResourceVersionChanged` predicate and every virtual Node. It runs on the virtual manager.
  - Each reconcile lists all virtual Nodes. For each, it takes every `InternalIP` and the `Hostname` address, defaulting to the node name. It writes one line `<ip> <hostname>` per IP. Lines are sorted `:99` and joined with `\n`.
  - If the ConfigMap is missing, it requeues after 1 second. An error from `Get` other than NotFound is not checked, so the code goes on with a zero object. The patch preserves other keys such as `Corefile`.
  - Tests `nodehosts_test.go:28`: a dual-stack node gives `"172.25.10.26 node-a\nfd20:14d:70d:1014::1a node-a"`. A node without an InternalIP is skipped. No nodes gives `""`.

### 13. `k8sdefaultendpoint`

- Registered on the host manager, outside private-nodes mode `pkg/controllers/register.go:62`.
- `Register` `register.go:10-29`. It uses the discovery client of the virtual cluster. `ShouldUseLegacy` is true when `discovery.k8s.io/v1` is not found or has no `EndpointSlice` kind `:31`. The test is `register_test.go:12`. Legacy means a v1beta1 provider, with log `Registering legacy discovery endpoint for k8s.io/api/discovery/v1beta1`.
- Controller `k8sdefaultendpoint.go`. It is named `kubernetes_default_endpoint` `:98`. It watches the host Endpoints named like the vcluster in the host namespace, and the virtual `default/kubernetes` Endpoints and EndpointSlice.
- Reconcile `:109-182`:
  - It gets the host Endpoints. If missing, it returns without error.
  - It create-or-patches the virtual `default/kubernetes` Endpoints with label `endpointslice.kubernetes.io/skip-mirror: "true"` `:134`. It keeps only ports named `https` `:141`, and blanks `Hostname`, `NodeName` and `TargetRef` on all addresses.
  - If the result is Created or Updated `:177`, it creates or patches the virtual `default/kubernetes` EndpointSlice from it. It uses address type IPv4 unless all addresses are IPv6. Ready is true for addresses and false for not-ready addresses. It takes only the first subset.
- Test examples: `provider_test.go` calls both providers with one address `127.0.0.1` and one port `{Name: "name", Port: 8081, Protocol: "https"}`, and only asserts no error. The e2e `test_k8sdefaultendpoint.go:39` asserts that host and virtual IPs and the non-`kubelet` ports match.

### 14. `servicesync` and `specialservices`

- Registration `pkg/controllers/register.go:106-190`, in this order:
  1. `ReplicateServices.FromHost`. A new global host manager is created, started and cache-synced. The controller is named `map-host-service-syncer`, with `CreateNamespace` and `CreateEndpoints` true.
  2. `ReplicateServices.ToHost`. The controller is named `map-virtual-service-syncer`, with `IsVirtualToHostSyncer: true`. It gets `CreateEndpoints = true` only when namespace sync is on `:180`.
- Mapping parse `register.go:192-234`. A `from` value without a namespace needs a default namespace, otherwise the error is `invalid service mapping, please use namespace1/service1=service2`. Host-to-virtual `to` needs `ns/name`. Virtual-to-host `to` needs a bare name.
- Reconcile `servicesync.go:87-127`:
  - It looks up the key in the mapping.
  - If the source Service is gone, it deletes the target `:103`.
  - Otherwise it strips node ports `:119` and takes one of two paths.
- Selector path, used when `CreateEndpoints` is false:
  - It creates the target with label `translate.ControllerLabel: vcluster`, the source ports, and a translated selector.
  - It copies `ClusterIP: None` for a headless source.
  - For virtual-to-host it also adds an owner reference `:159`.
  - An existing target without the label is left alone `:165`.
- Endpoints path, used when `CreateEndpoints` is true:
  - It creates a headless target Service plus an Endpoints object.
  - Headless source: it copies the source Endpoints subsets.
  - Otherwise it uses one subset pointing at the source ClusterIP with converted ports.
  - It mirrors LoadBalancer status through `Status().Update` `:245`.
- Tests `servicesync_test.go:50`. "Sync host service to new virtual service" turns host `host-namespace/host-service`, selector `app: host-app`, port `http` 8080, into virtual `virtual-namespace/virtual-service` with `ClusterIP: None`, port `http` 8080, and the label `translate.ControllerLabel: vcluster`, and no selector. `TestFromHostReconcileLoadBalancerCreatesEndpoints` at `:191` covers LoadBalancer status copying.
- `specialservices`.
  - `NewDefaultServiceSyncer` returns an `Interface` with one special service, `default/kubernetes`, synced by `SyncKubernetesService` `resolver.go:30`.
  - `SyncKubernetesService`, `service_syncer.go:28`: it reads the host Service named like the vcluster in the host namespace, and the virtual `default/kubernetes`. If `ClusterIP` or `ClusterIPs` differ, it deletes and recreates the virtual Service with the host's `ClusterIP`, `ClusterIPs`, `IPFamilies` and `IPFamilyPolicy`. If only ports differ it updates them. Ports go through `TranslateServicePorts`, which drops the port named `kubelet` `pkg/controllers/resources/services/syncer.go:295`.
  - `DNSNamespace` returns the host client and the host namespace mapped from `kube-system`.
  - Other users: the Service, Endpoints and EndpointSlice syncers skip special services in `ReconcileStart`, and the pod syncer reads the kube-dns host Service ClusterIP.
  - `Default` is set in `setup/initialize.go:28` from `pro.InitDNSServiceSyncing`, which in OSS returns `NewDefaultServiceSyncer`: `pkg/pro/integrated_coredns.go:14-16`.

### 15. Syncer startup, classic mode

Entry is `cmd/vcluster/cmd/start.go`.
1. `ExecuteStart` `:55-64`. If both `POD_NAME` and `POD_NAMESPACE` are empty, it starts standalone. Otherwise `StartInCluster`.
2. `StartInCluster` `:67-206`, in order:
   1. Read `VCLUSTER_NAME` and load the config `:70`.
   2. Host client config and current namespace `:76`. Defaults: QPS 40, burst 80, timeout 0, overridable by `VCLUSTER_PHYSICAL_CLIENT_QPS`, `_BURST`, `_TIMEOUT`: `pkg/setup/config/config.go:30-52`.
   3. `InitAndValidateConfig` `:82`. It sets `translate.VClusterName` and the `NAMESPACE` env var, creates clients and the namespace translator, runs `EnsureBackingStoreChanges`, and sets the global owner.
   4. Telemetry, `LicenseInit` `:103`, and the check that no other vcluster is in the namespace. The error is: `there is already a virtual cluster in namespace %s; creating multiple virtual clusters inside the same namespace is not supported` `:118`.
   5. `setup.Initialize` `:123`. It computes the service CIDR, migrates k3s to k8s, and generates certs if the cert dir equals the PKI dir. It then starts a cert watcher, starts embedded etcd if enabled, and starts the k8s processes in a goroutine. It also sets `specialservices.Default` `pkg/setup/initialize.go:28`.
   6. `NewControllerContext` `:132`:
      - `LoadVirtualConfig` polls every second, up to 1 hour. It needs the kubeconfig file, a working `ServerVersion`, and the `default/default` ServiceAccount: `controller_context.go:200-232`. Virtual client QPS is 1000, burst 2000.
      - Plugins start unless this is a plugin or standalone `:54`.
      - A host manager and a virtual manager are created with `LeaderElection: false` and metrics bind `"0"` by default. The host cache is limited to the host namespace unless namespace sync is on `:115-147`.
      - It reads the virtual version and sets `FakeNodesVersion`, runs `DisableMissingAPIs` on the host discovery, creates the etcd client, reads the host version, and creates the mapping store `:431`.
   7. `LicenseStart` `:138`. `StartIntegrations` `:144`, which starts the metrics-server proxy.
   8. `StartManagers` `:150`. In classic mode it first registers server indices, then resource mappings, then builds syncers, then pro syncers: `pkg/setup/managers.go:61-79`. Then it starts the host and virtual managers in goroutines, and waits for the host cache sync and then the virtual cache sync `:50`. A sync error is not checked.
   9. `StartProxy` `:156`. The TLS server starts before leader election, so every replica serves it. A serve error exits the process with code 1.
   10. `StartKonnectivity` `:162`. In classic mode this does nothing.
   11. Embedded CoreDNS, kube-vip and the custom-resource proxy, if configured `:168-194`. OSS returns a feature error for embedded CoreDNS.
   12. `StartLeaderElection` `:197`. If `HighAvailability.Replicas > 1`, it runs leader election, otherwise it runs controllers directly `:210`. The Lease is named `SafeConcatName("vcluster", VClusterName, "controller")` in the host namespace `pkg/leaderelection/leaderelection.go:52-54`. It uses the configured lease duration, renew deadline and retry period. Defaults 60, 40, 15 seconds: `config/values.yaml:353-357`. Losing leadership exits with code 1.
   13. Block on `controllerCtx.StopChan`. This channel is never closed, since it is built as `make(<-chan struct{})` `controller_context.go:367`.
3. `StartControllers` `pkg/setup/controllers.go:44-155`, in order:
   1. `MigrateK3sToK8sStateless`.
   2. `deploy.RegisterInitManifestsController`.
   3. Goroutine: `ApplyCoreDNS`, then delete the Deployment if embedded.
   4. `MigrateMappers`.
   5. `SyncKubernetesService`, which retries on conflict after 1 second.
   6. `controllers.RegisterControllers` (see below).
   7. `pro.RegisterProControllers`.
   8. `AcquiredLeaderHooks`, which holds the metrics-server APIService registration.
   9. Goroutine: write the kubeconfig Secret every 10s until it succeeds.
   10. `plugin.DefaultManager.SetLeader`.
   11. Mapping store GC.
   12. `deletePreviouslySyncedResources`.
   13. `pro.StartPrivateNodesMode`, which does nothing in classic mode.
   14. Log `Successfully started vCluster controllers`.
4. `RegisterControllers` `pkg/controllers/register.go:30-104`, in order:
   1. CoreDNS NodeHosts `:34`.
   2. Pod-security controller, when `Policies.PodSecurityStandard != ""` `:40`.
   3. Snapshot controller `:47`, then restore controller `:51`.
   4. If private nodes, stop here.
   5. `k8sdefaultendpoint.Register` `:62`.
   6. Service sync controllers, from host first and then to host `:68`.
   7. For each syncer in build order: fake syncer, then real syncer, then custom starter `:76-100`.

### 16. Default syncer set, in build order

`pkg/controllers/resources/register.go:51-89`. Defaults are from `config/values.yaml`.
- Enabled by default: Services, ConfigMaps from the virtual side, Endpoints, EndpointSlices, Pods, PersistentVolumeClaims, and Events from host. `values.yaml:5-20` and `:83-84`.
- Always built, with no switch: PersistentVolumes `register.go:86` and Nodes `:87`. Nodes is the fake syncer by default.
- Secrets to host have `enabled: true` `values.yaml:15-17`. Gateway API, ingresses, network policies, priority classes, PDBs and the rest are off by default.
- `csiDrivers`, `csiNodes`, `csiStorageCapacities` and `storageClasses` from host default to `auto`, and the factories require the literal `"true"` `register.go:81`. `auto` becomes `true` only when virtual scheduling is on and PVC sync is on: `pkg/config/validation.go:63-78`. `DisableMissingAPIs` can also force `false` `pkg/config/config.go:168-182`.
- If virtual scheduling is on and no node selector is set, the node selector becomes "all" `validation.go:58-60`.
- Networking defaults: `proxyKubelets.byHostname: true` and `byIP: true` `config/values.yaml:622-624`. `clusterDomain: cluster.local`. `fallbackHostCluster: false`.

### 17. Examples taken from tests

- `pkg/server/secure_serving_test.go:20` `TestServeSecureClosesBlackholedConnection`. With ping timeouts lowered to 1s, a quiet stream on a healthy HTTP/2 connection survives three ping rounds. After the relay starts dropping all bytes, the server must cancel the request context within 10 seconds.
- `pkg/server/server_test.go:5` `TestMetricsAuthNonResources`. The expected set is exactly the 7 metrics paths listed in section 5, each with verb `*`.
- `pkg/server/filters/k8s_metrics_test.go`:
  - `GET /metrics/syncer` returns 200 and a body containing `vcluster_syncer_metrics_route_probe_total 1` `:325-330`.
  - `/metrics` falls through to the next handler `:333-335`.
  - `/metrics/kine` with no backing store set uses `localBackingStoreMetricsURL`. With embedded etcd, deployed etcd or external etcd it returns nil.
  - `/metrics/etcd` returns nil unless embedded etcd is on.
- `pkg/server/cert/cert_test.go`. A leaf expiring in 60 days is flagged expired. One expiring in 200 days is not `:411` and `:423`. `sansChanged` is true for a new DNS name or a new IP, false when they match.
- Kubelet proxy e2e, `e2e/test_security/kubeletproxy/test_kubelet_proxy.go`. Config: `e2e/vcluster-kubelet-proxy.yaml` with `sync.fromHost.nodes.enabled: true` and `byHostname: true`.
  - `GET /api/v1/nodes/<node>/proxy/healthz` returns body `ok` `:49-53`.
  - `/proxy/pods` and `/proxy/runningpods` return only virtual pods.
  - `GET /api/v1/nodes/<node>/proxy/containerLogs/nonexistent-ns/nonexistent-pod/main` is 403 Forbidden `:129-135`.
  - `.../containerLogs/<ns>/<pod>/logger` returns the log line `kubelet-proxy-test-ok` `:216-222`.
  - `.../containerLogs/<ns>/<pod>/injected-sidecar` is 403 `:231-237`.
- Metrics-server e2e `e2e/test_integration/metricsproxy/test_metricsproxy.go`. The APIService `v1beta1.metrics.k8s.io` reaches `Available=True` `:53-54`. Node metrics are non-empty. Pod metrics in `kube-system` are non-empty.
- Fake node unit test `fake_syncer_test.go:48`. `ProxyKubelets.ByIP=false`, a pod on `mynode`. The expected Node has labels `vcluster.loft.sh/fake-node: "true"`, `kubernetes.io/hostname: fake-mynode`, address `{Type: Hostname, Address: GetNodeHost("mynode")}`, `KubeletEndpoint.Port = constants.KubeletPort`, capacity cpu 16 and memory 32Gi, and four conditions. The "Delete test" with no pod expects the Node to be removed.
- `register_test.go:12` `TestShouldUseLegacy`. A fake discovery with no resources returns true. `discovery.k8s.io/v1` with kind `EndpointSliceIsNotAvailableButResourceDoes` returns true. With kind `EndpointSlice` it returns false.
- Corefile and manifest goldens `pkg/coredns/template_test.go`. The default output (test `default`) contains `rewrite name regex .*\.nodes\.vcluster\.com kubernetes.default.svc.cluster.local`, the kubernetes block with `pods insecure` and `fallthrough in-addr.arpa ip6.arpa`, and `forward . /etc/resolv.conf`. The embedded Corefile adds `kubeconfig /data/vcluster/admin.conf` and drops `reload`. `overwriteManifests: "abc"` produces exactly `abc`.

Request and response examples I derived from code, with no test coverage, appear in sections 7 to 10.

## Contradictions

1. **No front-door authorization for node update and patch.** The comment at `pkg/server/filters/nodechanges.go:46` says `// authorization will be done at this point already, so we can redirect the request to the physical cluster`. The authorizer union has no rule for `nodes` update or patch: `server.go:208-229` lists only `services` create, `nodes/proxy`, four pod subresources, and the metrics and kubevirt groups. The final `allowall` allows it. The patch path then calls `handler.Handler("", virtualConfig, nil)` with no impersonation at `nodechanges.go:81`, so the dry run runs with the syncer's own virtual credentials. Net effect, derived: with `syncBackChanges` on, any authenticated user can reach the host-node write path. Whether virtual RBAC blocks it elsewhere is not verified.
2. **Same comment for service update.** `service.go:119` repeats the comment, but `update` is not in the SAR list. The ExternalName Get at `:90` uses the uncached syncer client, not the user. The later virtual Update is impersonated, so RBAC applies there.
3. **Parameter name versus meaning.** `enforceKubeletSubpathAllowlist` names its last argument `sharedNodes`, but both callers pass `Sync.FromHost.Nodes.Enabled`, which is the real-node mode: `metrics.go:82`, `kubelet.go:28`. In the default fake-node mode, unknown subpaths such as `/exec` are forwarded to the host node proxy `metrics.go:222-223`. The comment there says "dedicated/virtual nodes: forward unknown subpaths".
4. **Dead branch.** The `nodes` entry in `redirectResources` can never be handled by `WithRedirect`, because `WithMetricsProxy` is outer and consumes every `nodes/proxy` request. It still matters for authorization.
5. **Nil error passed to `FailWithStatus`.** `metricsserver.go:322` calls `FailWithStatus(..., http.StatusNotFound, err)` where `err` is nil at that point. `FailWithStatus` calls `err.Error()` eagerly at `pkg/util/request/*.go:26`, so a node-metrics GET for a node not in the virtual cluster will panic. On port 9001 there is no panic recovery.
6. **Unchecked Get error.** `nodehosts.go:48-52` handles only NotFound after `Get`. Any other error continues with an empty ConfigMap and then patches.
7. **Bound check mismatch.** `redirect.go:52` requires `len(splitted) >= 6`, then reads `splitted[6]` at `:58`.
8. **Doc mismatch for Service ports.** The host Service exposes `kubelet` 10250 only when `byHostname` is true `chart/templates/service.yaml:37`. The per-node Services for `byIP` do not depend on it. The virtual `kubernetes` Service drops `kubelet` `services/syncer.go:295`. Both facts are consistent with traffic arriving via the host ClusterIP, but the byIP case with `byHostname` false is not verified end to end.

## Decisions

| # | Decision | Options and what each changes | Recommendation |
|---|---|---|---|
| 1 | Kubernetes API machinery | A: rebuild only the filters that matter here, RequestInfo, authn union, authz union, impersonation, timeouts, panic recovery. B: full upstream chain with audit, flow control, CORS, HSTS, warnings, GOAWAY. B needs a Bend implementation of each. | A. Audit and flow control backends are unset in this code; the only config I read is in `server.go`. Not verified in vendor. |
| 2 | Scope of the proxy rewrite engine | A: HTTP reverse proxy with SPDY and websocket upgrade only. B: A plus table and protobuf negotiation, for metrics-server table rewriting and negotiated Status errors. B adds `as=Table;` support and protobuf encoding. | B for metrics.k8s.io only. Everything else can stay JSON. |
| 3 | Kubelet reach | A: both `byHostname` and `byIP` as today. B: hostname only. B drops the node-service garbage collector, the ClusterIP index and the SAN list entries. | A, since both default to true. |
| 4 | Node sync | A: both fake and real. B: fake only. B drops the allocatable math, taint merge and `SyncBackChanges` filter. | A, because `Sync.FromHost.Nodes.Enabled` is a documented switch. |
| 5 | Node write-back authorization, Contradictions 1 | A: reproduce exactly. B: add a SAR for `nodes` update and patch and run the dry run impersonated. | B. It closes the gap. It is a behaviour change, so treat it as a deliberate divergence. |
| 6 | The three bugs in Contradictions 5 to 7 | A: preserve. B: fix. | B. Preserving a nil dereference serves no one. |
| 7 | Cert and TLS | A: dynamic reload with a 2s poll as in `cert/syncer.go:106`. B: reload on file change only. A needs a background loop and listener signalling. | A. It keeps SAN updates automatic when node Services appear. |
| 8 | Pro and private-nodes paths | A: skip them and return feature errors as `pkg/pro` does. B: implement. | A. The stubs in `pkg/pro` define the OSS behaviour. |
| 9 | Extension hooks | A: keep `PreServerHooks`, `PostServerHooks` and plugin interceptors. B: keep only `PostServerHooks` for metrics-server. | B unless plugins are in scope. |
| 10 | Leader election | A: Lease based, as in `leaderelection.go`, only when replicas exceed 1. B: always. | A. It matches current behaviour. |

## Unchanged

- Anything in `pkg/pro` beyond the stubs I read, including konnectivity, license, embedded etcd and private nodes, none of which run in classic OSS mode.
- Resource syncer internals: `pkg/syncer`, `pkg/mappings`, and each per-resource syncer apart from nodes. I read only how they are registered.
- The virtual control plane processes: controller-manager and scheduler flags, etcd, certificate generation in `pkg/certs`, and the init manifests controller.
- Snapshot, restore, pod-security and kubeconfig-export controllers, which I only listed in order.
- Telemetry, plugins and standalone mode.

## Candidate work items

Per area, the code locations that change and the nearby tests.

- **TLS server.** `pkg/server/secure_serving.go:48-222` and `pkg/server/server.go:183-316`. Tests: `pkg/server/secure_serving_test.go`, `pkg/server/server_test.go`.
- **Serving cert and SANs.** `pkg/server/cert/cert.go:41-148`, `:156-299`, and `pkg/server/cert/syncer.go:81-107`. Tests: `pkg/server/cert/cert_test.go`.
- **Handler chain and ordering.** `pkg/server/server.go:73-181`, `:353-361`, `:364-448`. No tests.
- **Authentication.** `pkg/authentication/bearertoken/bearertoken.go:39-68`, `delegatingauthenticator/delegatingauthenticator.go:17-72`, `platformauthenticator/platformauthenticator.go:20-35`. No tests.
- **Authorization.** `pkg/authorization/delegatingauthorizer/authorizer.go:46-135`, `cache.go:14-69`, `kubeletauthorizer/authorizer.go:36-107`, `impersonationauthorizer/authorizer.go:29-66`. No tests.
- **Reverse proxy and impersonation.** `pkg/server/handler/handler.go:24-140`. No tests.
- **Exec, attach, port-forward, log.** `pkg/server/filters/redirect.go:26-83`, `:85-131`, `:133-146`; admission wiring `server.go:461-541`. No tests; e2e covers only kubelet paths.
- **Service create and update.** `pkg/server/filters/service.go:30-117`, `:118-186`, `:187-243`. No tests.
- **Node write-back.** `pkg/server/filters/nodechanges.go:27-110`, `:109-181`, and the Contradictions 1 fix. No tests.
- **Kubelet proxy and rewrites.** `pkg/server/filters/metrics.go:41-97`, `:117-225`, `:240-287`, `:289-406`, `:408-523`, and `pkg/server/filters/kubelet.go:13-44`, `nodename.go:23-76`. e2e: `e2e/test_security/kubeletproxy/test_kubelet_proxy.go`.
- **Syncer, controller-manager, scheduler, etcd metrics.** `pkg/server/filters/k8s_metrics.go:22-79`. Tests: `pkg/server/filters/k8s_metrics_test.go`.
- **Metrics-server integration.** `pkg/integrations/metricsserver/metricsserver.go:49-116`, `:118-143`, `:170-257`, `:259-520`, and the nil-error bug at `:322`. e2e: `e2e/test_integration/metricsproxy/test_metricsproxy.go`.
- **Aggregated API proxy and deletion protection.** `pkg/apiservice/generic.go:89-295`, `pkg/apiservice/protection.go:24-90`. No tests.
- **Node sync and node Services.** `pkg/controllers/resources/nodes/fake_syncer.go:32-286`, `syncer.go:37-380`, `translate.go:51-290`, `nodeservice/node_service.go:63-330`. Tests: `fake_syncer_test.go:48`, `syncer_test.go:66` and `:114`, `translate_test.go:24`.
- **CoreDNS.** `pkg/coredns/coredns.go:38-135`, `template.go:14-62`, `:64-346`, `:348-420`; `pkg/setup/controllers.go:158-191`; `pkg/controllers/coredns/nodehosts.go:36-126`. Tests: `pkg/coredns/template_test.go`, `coredns_test.go`, `pkg/controllers/coredns/nodehosts_test.go:28`; e2e `e2e/test_core/coredns/test_coredns.go:141`.
- **`k8sdefaultendpoint`.** `pkg/controllers/k8sdefaultendpoint/register.go:10-50`, `k8sdefaultendpoint.go:62-182`, `provider.go`, `v1betaprovider.go`. Tests: `register_test.go:12`, `provider_test.go`; e2e `e2e/test_core/sync/test_k8sdefaultendpoint.go:39`.
- **`servicesync` and `specialservices`.** `pkg/controllers/servicesync/servicesync.go:41-360`, `pkg/controllers/register.go:106-234`, `pkg/specialservices/resolver.go:30`, `service_syncer.go:28-90`. Tests: `servicesync_test.go:20`, `:50`, `:191`; e2e `e2e/test_core/sync/test_servicesync.go`.
- **Startup, leader election and syncer set.** `cmd/vcluster/cmd/start.go:55-222`, `pkg/setup/proxy.go:10-27`, `pkg/setup/initialize.go:21-103`, `pkg/setup/managers.go:16-90`, `pkg/setup/controller_context.go:46-445`, `pkg/setup/controllers.go:44-155`, `pkg/controllers/register.go:30-104`, `pkg/controllers/resources/register.go:51-135`, `pkg/leaderelection/leaderelection.go:25-96`. Tests: `pkg/setup/controllers_test.go`, `pkg/setup/controller_context_test.go`, `pkg/setup/controller_context_gateway_test.go`. I did not read these, so what they assert is not verified.

## Links

No external sites were used. Everything above comes from the local checkout of the vcluster repo at commit `a8ab30eab6f27b183a80783f4e5854c1a2eb6ef5`, plus the vendored Kubernetes libraries under `vendor/k8s.io/`. I did not look at the remote URL of the checkout, so I do not give one.