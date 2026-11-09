import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/net/kubelet.bend as K
import ../src/net/subject.bend as T

# Spec for src/net/kubelet.bend: vcluster's fake kubelet (vcluster a8ab30e,
# pkg/server/filters/kubelet.go, metrics.go and nodename.go, and
# pkg/authorization/kubeletauthorizer).
#
# vcluster has no unit test for these filters. The concrete laws
# transcribe every case of its kubelet proxy e2e spec
# (e2e/test_security/kubeletproxy/test_kubelet_proxy.go) and the branches
# of the code the spec drives: enforceKubeletSubpathAllowlist (metrics.go
# :117-225), nodeNameFromHost (nodename.go:39-76) with GetNodeHost and
# GetNodeHostLegacy (fake_syncer.go:324-332), and rewriteStats
# (metrics.go:289-344). The host requests follow the kube-apiserver's
# kubelet requests (pkg/registry/core/pod/strategy.go: LogLocation,
# streamLocation, PortForwardLocation; url.Values.Encode sorts the keys)
# and the pod API's options (PodLogOptions, PodExecOptions,
# PodAttachOptions, PodPortForwardOptions). Status bodies are
# kerrors.NewForbidden and responsewriters.Forbidden as encoded by the
# apiserver (compact). As in vcluster's tests: VClusterName "vcluster",
# target namespace "test", current namespace "vcluster-ns".

# Fixtures.

def Laws.kubelet.client() -> T.Subject:
  T.Subject{"kube-apiserver-kubelet-client", ["system:masters"]}

def Laws.kubelet.decide(+method: String, uri: String) -> K.Step:
  K.Kubelet.decide("vcluster", "test", Laws.kubelet.client(), method, uri)

def Laws.kubelet.str(k: String, v: String) -> J.KV:
  J.KV{k, J.JStr{v}}

def Laws.kubelet.obj(k: String, fs: List<&2, J.KV>) -> J.KV:
  J.KV{k, J.Json.obj(fs)}

def Laws.kubelet.arr(k: String, xs: List<&2, J.Json>) -> J.KV:
  J.KV{k, J.Json.arr(xs)}

def Laws.kubelet.container(n: String) -> J.Json:
  J.Json.obj([Laws.kubelet.str("name", n)])

# The e2e spec's pod: one container, "logger".
def Laws.kubelet.logger_pod() -> J.Json:
  J.Json.obj([
    Laws.kubelet.obj("metadata", [Laws.kubelet.str("name", "logger-abc123"), Laws.kubelet.str("namespace", "kubelet-proxy-test-abc123")]),
    Laws.kubelet.obj("spec", [Laws.kubelet.arr("containers", [Laws.kubelet.container("logger")])])])

# A pod with an init container and an ephemeral container.
def Laws.kubelet.debug_pod() -> J.Json:
  J.Json.obj([
    Laws.kubelet.obj("metadata", [Laws.kubelet.str("name", "web"), Laws.kubelet.str("namespace", "default")]),
    Laws.kubelet.obj("spec", [
      Laws.kubelet.arr("containers", [Laws.kubelet.container("app")]),
      Laws.kubelet.arr("initContainers", [Laws.kubelet.container("setup")]),
      Laws.kubelet.arr("ephemeralContainers", [Laws.kubelet.container("debugger")])])])

def Laws.kubelet.logs_target() -> String:
  "/api/v1/namespaces/test/pods/logger-abc123-x-kubelet-proxy-test-abc123-x-vcluster/log?container=logger"

# kerrors.NewForbidden(corev1.Resource("nodes"), "", errors.New(why)).
def Laws.kubelet.forbidden(why: String) -> K.Step:
  K.Answer{403, "application/json",
    "{\"kind\":\"Status\",\"apiVersion\":\"v1\",\"metadata\":{},\"status\":\"Failure\",\"message\":\"nodes is forbidden: "
    ++ why ++ "\",\"reason\":\"Forbidden\",\"details\":{\"kind\":\"nodes\"},\"code\":403}"}

def Laws.kubelet.not_ours() -> K.Step:
  Laws.kubelet.forbidden("access denied: pod does not belong to this virtual cluster")

# e2e: "GET /healthz via node proxy returns ok for every virtual node".
law kubelet.healthz_ok:
  {Laws.kubelet.decide("GET", "/healthz") == K.Answer{200, "text/plain; charset=utf-8", "ok"} : K.Step}

# e2e: "GET /pods via node proxy returns only pods belonging to this
# vcluster" (IsKubeletPods): a node route.
law kubelet.pods_route:
  {Laws.kubelet.decide("GET", "/pods") == K.NodeStep{K.RPods{}, [], "GET"} : K.Step}

# e2e: "GET /runningpods via node proxy ..." (IsKubeletPods trims a
# trailing "/").
law kubelet.runningpods_route:
  {Laws.kubelet.decide("GET", "/runningpods/") == K.NodeStep{K.RRunningPods{}, [], "GET"} : K.Step}

law kubelet.runningpods_node:
  {K.Kubelet.node_step(Some{"mynode"}, K.RRunningPods{}, [], "GET") == K.PodList{"mynode"} : K.Step}

# The pod list holds only the virtual pods of the node.
law kubelet.pods_answer_only_node:
  {K.Kubelet.pods_answer("mynode",
     "{\"kind\":\"PodList\",\"items\":[{\"metadata\":{\"name\":\"a\",\"namespace\":\"default\"},\"spec\":{\"nodeName\":\"mynode\"}},{\"metadata\":{\"name\":\"b\",\"namespace\":\"default\"},\"spec\":{\"nodeName\":\"other\"}}]}")
   == K.Answer{200, "application/json",
     "{\"kind\":\"PodList\",\"apiVersion\":\"v1\",\"metadata\":{},\"items\":[{\"metadata\":{\"name\":\"a\",\"namespace\":\"default\"},\"spec\":{\"nodeName\":\"mynode\"}}]}"} : K.Step}

# e2e: "GET /containerLogs for a non-existent pod returns 403 Forbidden":
# the request reads the virtual pod first, which is not found.
law kubelet.logs_check_pod:
  {Laws.kubelet.decide("GET", "/containerLogs/nonexistent-ns/nonexistent-pod/main")
    == K.CheckPod{"nonexistent-ns", "nonexistent-pod", "main", "GET",
      "/api/v1/namespaces/test/pods/nonexistent-pod-x-nonexistent-ns-x-vcluster/log?container=main"} : K.Step}

law kubelet.logs_missing_pod:
  {K.Kubelet.after_pod(J.JNull{}, "main", "GET",
     "/api/v1/namespaces/test/pods/nonexistent-pod-x-nonexistent-ns-x-vcluster/log?container=main")
    == Laws.kubelet.not_ours() : K.Step}

# e2e: "GET /containerLogs with a valid pod and container returns log
# output": the request goes to the host pod's log.
law kubelet.logs_valid:
  {Laws.kubelet.decide("GET", "/containerLogs/kubelet-proxy-test-abc123/logger-abc123/logger")
    == K.CheckPod{"kubelet-proxy-test-abc123", "logger-abc123", "logger", "GET", Laws.kubelet.logs_target()} : K.Step}

law kubelet.logs_valid_relay:
  {K.Kubelet.after_pod(Laws.kubelet.logger_pod(), "logger", "GET", Laws.kubelet.logs_target())
    == K.Relay{"GET", Laws.kubelet.logs_target()} : K.Step}

# e2e: "GET /containerLogs with a valid pod but an unknown container
# returns 403 Forbidden" (a host-only injected sidecar).
law kubelet.logs_sidecar:
  {K.Kubelet.after_pod(Laws.kubelet.logger_pod(), "injected-sidecar", "GET", Laws.kubelet.logs_target())
    == Laws.kubelet.not_ours() : K.Step}

# metrics.go:146: init and ephemeral containers are the pod's too.
law kubelet.logs_init_container:
  {K.Kubelet.after_pod(Laws.kubelet.debug_pod(), "setup", "GET", "/t") == K.Relay{"GET", "/t"} : K.Step}

law kubelet.logs_ephemeral_container:
  {K.Kubelet.after_pod(Laws.kubelet.debug_pod(), "debugger", "GET", "/t") == K.Relay{"GET", "/t"} : K.Step}

# metrics.go:139-145: a containerLogs path without a namespace, pod and
# container, or with an empty one, is malformed.
law kubelet.logs_empty_segment:
  {Laws.kubelet.decide("GET", "/containerLogs/default//main") == Laws.kubelet.not_ours() : K.Step}

law kubelet.logs_too_short:
  {Laws.kubelet.decide("GET", "/containerLogs/default/web") == Laws.kubelet.not_ours() : K.Step}

# The log options pass to the pod log API; LogLocation sorts them.
law kubelet.logs_options:
  {Laws.kubelet.decide("GET", "/containerLogs/default/nginx/web?follow=true&limitBytes=100&previous=true&sinceSeconds=5&tailLines=10&timestamps=true")
    == K.CheckPod{"default", "nginx", "web", "GET",
      "/api/v1/namespaces/test/pods/nginx-x-default-x-vcluster/log?container=web&follow=true&limitBytes=100&previous=true&sinceSeconds=5&tailLines=10&timestamps=true"} : K.Step}

# streamLocation: kubelet's input, output, error and tty ("1") are the exec
# API's stdin, stdout, stderr and tty; the command keeps its order.
law kubelet.exec_options:
  {Laws.kubelet.decide("POST", "/exec/default/nginx/web?command=sh&command=-c&command=echo+hi&error=1&input=1&output=1&tty=1")
    == K.CheckPod{"default", "nginx", "web", "POST",
      "/api/v1/namespaces/test/pods/nginx-x-default-x-vcluster/exec?container=web&command=sh&command=-c&command=echo+hi&stderr=true&stdin=true&stdout=true&tty=true"} : K.Step}

law kubelet.attach_options:
  {Laws.kubelet.decide("POST", "/attach/default/nginx/web?error=1&output=1")
    == K.CheckPod{"default", "nginx", "web", "POST",
      "/api/v1/namespaces/test/pods/nginx-x-default-x-vcluster/attach?container=web&stderr=true&stdout=true"} : K.Step}

# PortForwardLocation: port is the port-forward API's ports.
law kubelet.portforward_options:
  {Laws.kubelet.decide("GET", "/portForward/default/nginx?port=8080&port=9090")
    == K.CheckPod{"default", "nginx", "", "GET",
      "/api/v1/namespaces/test/pods/nginx-x-default-x-vcluster/portforward?ports=8080&ports=9090"} : K.Step}

law kubelet.portforward_pod_exists:
  {K.Kubelet.after_pod(Laws.kubelet.debug_pod(), "", "GET", "/t") == K.Relay{"GET", "/t"} : K.Step}

# IsKubeletStats: the stats go through the node's proxy, then rewriteStats.
law kubelet.stats_route:
  {Laws.kubelet.decide("GET", "/stats/summary") == K.NodeStep{K.RStats{}, [], "GET"} : K.Step}

law kubelet.stats_node:
  {K.Kubelet.node_step(Some{"mynode"}, K.RStats{}, [], "GET")
    == K.Stats{"/api/v1/nodes/mynode/proxy/stats/summary"} : K.Step}

# metrics.go:222: in fake-node mode an unknown subpath is forwarded.
law kubelet.unknown_forwarded:
  {Laws.kubelet.decide("GET", "/configz") == K.NodeStep{K.RUnknown{"/configz"}, [], "GET"} : K.Step}

law kubelet.unknown_node:
  {K.Kubelet.node_step(Some{"mynode"}, K.RUnknown{"/configz"}, [], "GET")
    == K.Relay{"GET", "/api/v1/nodes/mynode/proxy/configz"} : K.Step}

law kubelet.no_node:
  {K.Kubelet.node_step(None{}, K.RStats{}, [], "GET")
    == K.Answer{404, "application/json",
      "{\"kind\":\"Status\",\"apiVersion\":\"v1\",\"metadata\":{},\"status\":\"Failure\",\"message\":\"the server could not find the requested resource\",\"reason\":\"NotFound\",\"details\":{},\"code\":404}"} : K.Step}

# The metrics paths are not forwarded (see the module's divergences).
law kubelet.metrics_blocked:
  {Laws.kubelet.decide("GET", "/metrics/cadvisor")
    == Laws.kubelet.forbidden("proxy subpath not permitted in shared mode") : K.Step}

# nodeNameFromHost: GetNodeHost names a node.
law kubelet.node_by_hostname:
  {K.Kubelet.node_of("mynode.nodes.vcluster.com:10250", "vcluster", "vcluster-ns", ["other", "mynode"]) == Some{"mynode"} : Maybe<&2, String>}

# GetNodeHost replaces every "." by "-".
law kubelet.node_with_dots:
  {K.Kubelet.node_of("ip-10-0-0-1-ec2-internal.nodes.vcluster.com:10250", "vcluster", "vcluster-ns", ["ip-10-0-0-1.ec2.internal"])
    == Some{"ip-10-0-0-1.ec2.internal"} : Maybe<&2, String>}

# GetNodeHostLegacy (the 0.14 hostname) names it too.
law kubelet.node_legacy:
  {K.Kubelet.node_of("mynode.vcluster.vcluster-ns.nodes.vcluster.com:10250", "vcluster", "vcluster-ns", ["mynode"]) == Some{"mynode"} : Maybe<&2, String>}

# strings.Split(req.Host, ":") must give two parts.
law kubelet.node_no_port:
  {K.Kubelet.node_of("mynode.nodes.vcluster.com", "vcluster", "vcluster-ns", ["mynode"]) == None{} : Maybe<&2, String>}

law kubelet.node_ipv6:
  {K.Kubelet.node_of("[::1]:10250", "vcluster", "vcluster-ns", ["mynode"]) == None{} : Maybe<&2, String>}

law kubelet.node_unknown:
  {K.Kubelet.node_of("other.nodes.vcluster.com:10250", "vcluster", "vcluster-ns", ["mynode"]) == None{} : Maybe<&2, String>}

# kubeletauthorizer: the apiserver's kubelet client and system:masters
# pass; anyone else is denied as WithAuthorization denies a non-resource
# request.
law kubelet.allow_apiserver:
  {K.Kubelet.allowed(T.Subject.parse("CN=kube-apiserver-kubelet-client,O=system:masters")) == True{} : Bool}

law kubelet.allow_apiserver_no_group:
  {K.Kubelet.allowed(T.Subject{"kube-apiserver-kubelet-client", []}) == True{} : Bool}

law kubelet.allow_masters:
  {K.Kubelet.allowed(T.Subject{"admin", ["system:masters"]}) == True{} : Bool}

law kubelet.deny_node:
  {K.Kubelet.allowed(T.Subject{"system:node:mynode", ["system:nodes"]}) == False{} : Bool}

law kubelet.deny_answer:
  {K.Kubelet.decide("vcluster", "test", T.Subject{"system:node:mynode", ["system:nodes"]}, "GET", "/stats/summary?only_cpu_and_memory=true")
    == K.Answer{403, "application/json",
      "{\"kind\":\"Status\",\"apiVersion\":\"v1\",\"metadata\":{},\"status\":\"Failure\",\"message\":\"forbidden: User \\\"system:node:mynode\\\" cannot get path \\\"/stats/summary\\\": forbidden\",\"reason\":\"Forbidden\",\"details\":{},\"code\":403}"} : K.Step}

# rewriteStats.

def Laws.kubelet.meta(n: String, ns: String, uid: String) -> J.KV:
  Laws.kubelet.obj("metadata", [Laws.kubelet.str("name", n), Laws.kubelet.str("namespace", ns), Laws.kubelet.str("uid", uid)])

def Laws.kubelet.ref(k: String, n: String, ns: String) -> J.KV:
  Laws.kubelet.obj(k, [Laws.kubelet.str("name", n), Laws.kubelet.str("namespace", ns)])

def Laws.kubelet.pod_ref(n: String, ns: String, uid: String) -> J.KV:
  Laws.kubelet.obj("podRef", [Laws.kubelet.str("name", n), Laws.kubelet.str("namespace", ns), Laws.kubelet.str("uid", uid)])

def Laws.kubelet.cpu() -> J.KV:
  Laws.kubelet.obj("cpu", [J.KV{"usageNanoCores", J.JNum{"1000"}}])

def Laws.kubelet.vpods() -> List<&2, J.Json>:
  [J.Json.obj([Laws.kubelet.meta("nginx", "default", "v-uid-1")])]

def Laws.kubelet.vpvcs() -> List<&2, J.Json>:
  [J.Json.obj([Laws.kubelet.meta("data", "default", "v-pvc-1")])]

def Laws.kubelet.node() -> J.KV:
  Laws.kubelet.obj("node", [Laws.kubelet.str("nodeName", "mynode")])

# The host's summary: the virtual pod (a volume of a virtual PVC, one of
# another PVC, an emptyDir), a host pod, a pod of the same name in another
# namespace, and a virtual pod whose only volume is another PVC.
def Laws.kubelet.summary() -> J.Json:
  J.Json.obj([Laws.kubelet.node(), Laws.kubelet.arr("pods", [
    J.Json.obj([Laws.kubelet.pod_ref("nginx-x-default-x-vcluster", "test", "h-uid-1"), Laws.kubelet.cpu(),
      Laws.kubelet.arr("volume", [
        J.Json.obj([Laws.kubelet.str("name", "data"), Laws.kubelet.ref("pvcRef", "data-x-default-x-vcluster", "test")]),
        J.Json.obj([Laws.kubelet.str("name", "other"), Laws.kubelet.ref("pvcRef", "other-x-default-x-vcluster", "test")]),
        J.Json.obj([Laws.kubelet.str("name", "tmp")])])]),
    J.Json.obj([Laws.kubelet.pod_ref("coredns-123", "kube-system", "h-uid-2"), Laws.kubelet.cpu()]),
    J.Json.obj([Laws.kubelet.pod_ref("nginx-x-default-x-vcluster", "elsewhere", "h-uid-3"), Laws.kubelet.cpu()])])])

law kubelet.stats_rewrite:
  {K.Kubelet.stats("vcluster", "test", Laws.kubelet.vpods(), Laws.kubelet.vpvcs(), Laws.kubelet.summary())
    == J.Json.obj([Laws.kubelet.node(), Laws.kubelet.arr("pods", [
      J.Json.obj([Laws.kubelet.pod_ref("nginx", "default", "v-uid-1"), Laws.kubelet.cpu(),
        Laws.kubelet.arr("volume", [
          J.Json.obj([Laws.kubelet.str("name", "data"), Laws.kubelet.ref("pvcRef", "data", "default")]),
          J.Json.obj([Laws.kubelet.str("name", "tmp")])])])])]) : J.Json}

# A pod whose volumes all go loses "volume" (omitempty).
law kubelet.stats_no_volumes:
  {K.Kubelet.stats("vcluster", "test", Laws.kubelet.vpods(), [],
     J.Json.obj([Laws.kubelet.arr("pods", [
       J.Json.obj([Laws.kubelet.pod_ref("nginx-x-default-x-vcluster", "test", "h-uid-1"),
         Laws.kubelet.arr("volume", [J.Json.obj([Laws.kubelet.str("name", "data"), Laws.kubelet.ref("pvcRef", "data-x-default-x-vcluster", "test")])])])])]))
    == J.Json.obj([Laws.kubelet.arr("pods", [J.Json.obj([Laws.kubelet.pod_ref("nginx", "default", "v-uid-1")])])]) : J.Json}

# A status other than 200 passes through (handleNodeRequest).
law kubelet.stats_error_passes:
  {K.Kubelet.stats_answer(503, "vcluster", "test", "unavailable", "{}", "{}") == K.Answer{503, "application/json", "unavailable"} : K.Step}

# General laws.

# Parsing a rendered route gives the route back, for every route whose
# names hold no "/".
law kubelet.parse_render:
  for r: K.Route
  for +h: {K.Kubelet.well_formed(r) == True{} : Bool}
  {K.Kubelet.parse(K.Kubelet.render(r)) == r : K.Route}

# No route names a host pod outside the target namespace.
law kubelet.host_in_target:
  for vc: String
  for t: String
  for r: K.Route
  for qs: List<&2, K.Q>
  {K.Kubelet.host_ns(t, K.Kubelet.host(vc, t, r, qs)) == t : String}
