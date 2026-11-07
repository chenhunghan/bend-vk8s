import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../translate/names.bend as N
import ../translate/nodes.bend as Nd
import ./subject.bend as T

# vcluster's fake kubelet (pkg/server/filters/kubelet.go, metrics.go,
# nodename.go; pkg/authorization/kubeletauthorizer), as pure decisions.
#
# In classic mode virtual pods run on the host cluster, so the virtual
# kube-apiserver's kubelet calls (logs, exec, attach, port-forward, stats)
# must reach them there. The proxy (host/kubelet_proxy.bend) serves the
# kubelet API on the nodes' kubelet endpoint (port 10250, as vcluster's
# fake nodes advertise) and calls the host API server with the syncer's
# host credentials. Every decision is made here:
#
# - Kubelet.parse reads a kubelet path into a Route; Kubelet.render writes
#   one back (parse(render(r)) == r for well-formed routes).
# - Kubelet.allowed: the client certificate's identity (src/net/subject.bend).
# - Kubelet.host: a pod route becomes a request on the host pod's
#   subresource, in the target namespace, named by Names.host_name
#   (single-namespace mode); a node route becomes a host node proxy
#   request, as vcluster's WithFakeKubelet makes it.
# - Kubelet.decide: what the proxy does with one request (a Step).
# - Kubelet.stats: the stats/summary answer rewritten from host names back
#   to virtual ones (vcluster rewriteStats).
#
# The vcluster name, the target namespace and the namespace vcluster runs in
# are parameters.
#
# vcluster quirks kept as they are:
# - A node is named by the Host header only when it splits at ":" into
#   exactly two parts (nodename.go:40): a Host without a port, or an IPv6
#   literal, names none. Both GetNodeHost and GetNodeHostLegacy names
#   match, and exactly one node must match.
# - containerLogs with an empty namespace, pod or container, a pod that is
#   not in the virtual cluster, or a container that the virtual pod does
#   not list (init and ephemeral containers count) is Forbidden with
#   "access denied: pod does not belong to this virtual cluster"
#   (metrics.go:134-210). The same check guards exec, attach and
#   port-forward here.
# - In fake-node mode, unknown subpaths (and /run) go to the host node's
#   proxy as they are (metrics.go:222).
# - A stats pod that is not a virtual pod is dropped, and so is a volume
#   whose PVC is not a virtual PVC; a pod left with no volumes loses its
#   "volume" key (omitempty).
#
# Divergences (vk8s):
# - Pod routes call the host pod's log, exec, attach or portforward
#   subresource instead of the host node proxy, so the syncer needs no
#   nodes/proxy permission on the host. The kubelet query becomes the
#   pod API's: input, output, error and tty ("1", as kubelet reads them)
#   become stdin, stdout, stderr and tty=true; port becomes ports.
# - The identity check is local: the apiserver's kubelet client
#   certificate (CN kube-apiserver-kubelet-client) or a member of
#   system:masters; vcluster asks the virtual cluster with a
#   SubjectAccessReview.
# - Prometheus metrics are not rewritten yet, so the metrics paths are
#   Forbidden ("proxy subpath not permitted in shared mode"), never
#   leaked.
# - /pods and /runningpods list the virtual pods bound to the node.
# - The rewritten stats keep every field of the host's answer and print
#   compact JSON (vcluster re-encodes its typed Summary, indented).

# A kubelet API path.
type Route is Data:
  RLogs{ns: String, pod: String, container: String}
  RExec{ns: String, pod: String, container: String}
  RAttach{ns: String, pod: String, container: String}
  RPortForward{ns: String, pod: String}
  RRun{ns: String, pod: String, container: String}
  RPods{}
  RRunningPods{}
  RStats{}
  RMetrics{}
  RCadvisor{}
  RResource{}
  RProbes{}
  RHealthz{}
  RUnknown{path: String}

# One query parameter, its value as it came (still URL-encoded).
type Q is Data:
  Q{key: String, val: String}

# A string cut at its first "/": the part before it, whether there was a
# "/", and the part after it.
type Seg is Data:
  Seg{head: String, slash: Bool, rest: String}

# The kinds of namespaced routes.
type Kind is Data:
  KLogs{}
  KExec{}
  KAttach{}
  KRun{}
  KPf{}
  KNone{}

# The host request a kubelet request becomes: a host pod's subresource
# (/api/v1/namespaces/{ns}/pods/{name}/{sub}), a path under the host node's
# proxy, or nothing (the proxy answers itself).
type Host is Data:
  HPod{ns: String, name: String, sub: String, query: List<&2, Q>}
  HNode{path: String, query: List<&2, Q>}
  HLocal{}

# What the proxy does with one request.
# - Answer: answer it itself.
# - Relay: send it to the host API server as method and target, then relay
#   bytes both ways (a streamed log, an upgraded exec, a plain answer).
# - CheckPod: read the virtual pod ns/pod first; Kubelet.after_pod decides.
# - NodeStep: find the node the Host header names (Kubelet.node_of); then
#   Kubelet.node_step decides.
# - Stats: read the host's stats/summary at target; Kubelet.stats_answer
#   rewrites it.
# - PodList: answer the virtual pods bound to node (Kubelet.pods_answer).
type Step is Data:
  Answer{code: U32, ctype: String, body: String}
  Relay{method: String, target: String}
  CheckPod{ns: String, pod: String, container: String, method: String, target: String}
  NodeStep{route: Route, query: List<&2, Q>, method: String}
  Stats{target: String}
  PodList{node: String}

# A virtual object as the stats rewrite reads it: its host name, its
# virtual name and namespace, and its uid.
type VRef is Data:
  VRef{host: String, name: String, ns: String, uid: String}

# An HTTP header and a request head.
type Hdr is Data:
  Hdr{name: String, value: String}

type Req is Data:
  Req{method: String, uri: String, headers: List<&2, Hdr>}

# Strings
# -------

def Kubelet.str.pick(hit: Bool, a: String, b: String) -> String:
  match hit:
    case True{}:
      a
    case False{}:
      b

# Equality with a literal, walked on the literal first: it stops at the
# first difference (Bool.and never looks at the rest after False), so a
# path whose tail is unknown still compares.
def Kubelet.same.go(lit: String, s: String) -> Bool:
  match lit s:
    case SNil{} SNil{}:
      True{}
    case SNil{} SCon{y, yt}:
      False{}
    case SCon{x, xt} SNil{}:
      False{}
    case SCon{x, xt} SCon{y, yt}:
      Bool.and(Char.is_eq(x, y), Kubelet.same.go(xt, yt))

def Kubelet.same(lit: String, s: String) -> Bool:
  Kubelet.same.go(lit, s)

# A string with no "/".
def Kubelet.clean.at(slash: Bool, rest: Bool) -> Bool:
  match slash:
    case True{}:
      False{}
    case False{}:
      rest

def Kubelet.clean(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{+c, t}:
      Kubelet.clean.at(Char.is_eq(c, '/'), Kubelet.clean(t))

def Kubelet.Seg.cons(c: Char, s: Seg) -> Seg:
  match s:
    case Seg{h, sl, r}:
      Seg{SCon{c, h}, sl, r}

def Kubelet.seg.at(slash: Bool, c: Char, t: String, s: Seg) -> Seg:
  match slash:
    case True{}:
      Seg{"", True{}, t}
    case False{}:
      Kubelet.Seg.cons(c, s)

# A string cut at its first "/".
def Kubelet.seg(s: String) -> Seg:
  match s:
    case SNil{}:
      Seg{"", False{}, ""}
    case SCon{+c, +t}:
      Kubelet.seg.at(Char.is_eq(c, '/'), c, t, Kubelet.seg(t))

# A string cut at its first sep: before and after it (after is "" when
# there is no sep).
def Kubelet.cut.at(eq: Bool, +h: Char, +t: String, r: Q) -> Q:
  match eq r:
    case True{} Q{k, v}:
      Q{SNil{}, t}
    case False{} Q{k, v}:
      Q{SCon{h, k}, v}

def Kubelet.cut(s: String, +sep: Char) -> Q:
  match s:
    case SNil{}:
      Q{SNil{}, SNil{}}
    case SCon{+h, +t}:
      Kubelet.cut.at(Char.is_eq(h, sep), h, t, Kubelet.cut(t, sep))

def Kubelet.Q.key(q: Q) -> String:
  match q:
    case Q{k, v}:
      k

def Kubelet.Q.val(q: Q) -> String:
  match q:
    case Q{k, v}:
      v

def Kubelet.in(+x: String, xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{y, t}:
      Bool.or(String.eq(y, x), Kubelet.in(x, t))

# Paths
# -----

def Kubelet.p2(ns: String, pod: String) -> String:
  ns ++ SCon{'/', pod}

def Kubelet.p3(ns: String, pod: String, c: String) -> String:
  ns ++ SCon{'/', pod ++ SCon{'/', c}}

# The kubelet path of a route (kubelet's server.go routes; the
# apiserver's LogLocation, ExecLocation, AttachLocation and
# PortForwardLocation build the namespaced ones).
def Kubelet.render(r: Route) -> String:
  match r:
    case RLogs{ns, pod, c}:
      "/containerLogs/" ++ Kubelet.p3(ns, pod, c)
    case RExec{ns, pod, c}:
      "/exec/" ++ Kubelet.p3(ns, pod, c)
    case RAttach{ns, pod, c}:
      "/attach/" ++ Kubelet.p3(ns, pod, c)
    case RPortForward{ns, pod}:
      "/portForward/" ++ Kubelet.p2(ns, pod)
    case RRun{ns, pod, c}:
      "/run/" ++ Kubelet.p3(ns, pod, c)
    case RPods{}:
      "/pods"
    case RRunningPods{}:
      "/runningpods/"
    case RStats{}:
      "/stats/summary"
    case RMetrics{}:
      "/metrics"
    case RCadvisor{}:
      "/metrics/cadvisor"
    case RResource{}:
      "/metrics/resource"
    case RProbes{}:
      "/metrics/probes"
    case RHealthz{}:
      "/healthz"
    case RUnknown{p}:
      p

# A route render and parse agree on: every name free of "/". Unknown
# paths are not routes.
def Kubelet.well_formed(r: Route) -> Bool:
  match r:
    case RLogs{ns, pod, c}:
      Bool.and(Kubelet.clean(ns), Bool.and(Kubelet.clean(pod), Kubelet.clean(c)))
    case RExec{ns, pod, c}:
      Bool.and(Kubelet.clean(ns), Bool.and(Kubelet.clean(pod), Kubelet.clean(c)))
    case RAttach{ns, pod, c}:
      Bool.and(Kubelet.clean(ns), Bool.and(Kubelet.clean(pod), Kubelet.clean(c)))
    case RPortForward{ns, pod}:
      Bool.and(Kubelet.clean(ns), Kubelet.clean(pod))
    case RRun{ns, pod, c}:
      Bool.and(Kubelet.clean(ns), Bool.and(Kubelet.clean(pod), Kubelet.clean(c)))
    case RUnknown{p}:
      False{}
    case _:
      True{}

# Parsing
# -------

def Kubelet.fixed.pick(hit: Bool, r: Route, rest: Maybe<&2, Route>) -> Maybe<&2, Route>:
  match hit:
    case True{}:
      Some{r}
    case False{}:
      rest

# The paths without names. vcluster matches them by suffix on the node
# proxy path (IsKubeletHealthz, IsKubeletStats, IsKubeletMetrics,
# IsKubeletPods: a trailing "/" is trimmed for pods and runningpods).
def Kubelet.fixed(+p: String) -> Maybe<&2, Route>:
  Kubelet.fixed.pick(Kubelet.same("/healthz", p), RHealthz{},
  Kubelet.fixed.pick(Kubelet.same("/pods", p), RPods{},
  Kubelet.fixed.pick(Kubelet.same("/pods/", p), RPods{},
  Kubelet.fixed.pick(Kubelet.same("/runningpods", p), RRunningPods{},
  Kubelet.fixed.pick(Kubelet.same("/runningpods/", p), RRunningPods{},
  Kubelet.fixed.pick(Kubelet.same("/stats/summary", p), RStats{},
  Kubelet.fixed.pick(Kubelet.same("/metrics", p), RMetrics{},
  Kubelet.fixed.pick(Kubelet.same("/metrics/cadvisor", p), RCadvisor{},
  Kubelet.fixed.pick(Kubelet.same("/metrics/resource", p), RResource{},
  Kubelet.fixed.pick(Kubelet.same("/metrics/probes", p), RProbes{},
  None{}))))))))))

def Kubelet.kind.pick(hit: Bool, k: Kind, rest: Kind) -> Kind:
  match hit:
    case True{}:
      k
    case False{}:
      rest

def Kubelet.kind(+k: String) -> Kind:
  Kubelet.kind.pick(Kubelet.same("containerLogs", k), KLogs{},
  Kubelet.kind.pick(Kubelet.same("exec", k), KExec{},
  Kubelet.kind.pick(Kubelet.same("attach", k), KAttach{},
  Kubelet.kind.pick(Kubelet.same("run", k), KRun{},
  Kubelet.kind.pick(Kubelet.same("portForward", k), KPf{},
  KNone{})))))

def Kubelet.mk3(k: Kind, ns: String, pod: String, c: String, +p: String) -> Route:
  match k:
    case KLogs{}:
      RLogs{ns, pod, c}
    case KExec{}:
      RExec{ns, pod, c}
    case KAttach{}:
      RAttach{ns, pod, c}
    case KRun{}:
      RRun{ns, pod, c}
    case KPf{}:
      RUnknown{p}
    case KNone{}:
      RUnknown{p}

def Kubelet.three.c(ok: Bool, k: Kind, ns: String, pod: String, c: String, +p: String) -> Route:
  match ok:
    case True{}:
      Kubelet.mk3(k, ns, pod, c, p)
    case False{}:
      RUnknown{p}

def Kubelet.three.go(sl: Bool, k: Kind, ns: String, pod: String, +c: String, +p: String) -> Route:
  match sl:
    case True{}:
      Kubelet.three.c(Kubelet.clean(c), k, ns, pod, c, p)
    case False{}:
      RUnknown{p}

def Kubelet.three.b(s: Seg, k: Kind, ns: String, +p: String) -> Route:
  match s:
    case Seg{pod, sl, c}:
      Kubelet.three.go(sl, k, ns, pod, c, p)

def Kubelet.three.a(sl: Bool, k: Kind, ns: String, rest: String, +p: String) -> Route:
  match sl:
    case True{}:
      Kubelet.three.b(Kubelet.seg(rest), k, ns, p)
    case False{}:
      RUnknown{p}

# {ns}/{pod}/{container}.
def Kubelet.three(s: Seg, k: Kind, +p: String) -> Route:
  match s:
    case Seg{ns, sl, rest}:
      Kubelet.three.a(sl, k, ns, rest, p)

def Kubelet.two.b(ok: Bool, ns: String, pod: String, +p: String) -> Route:
  match ok:
    case True{}:
      RPortForward{ns, pod}
    case False{}:
      RUnknown{p}

def Kubelet.two.a(sl: Bool, ns: String, +pod: String, +p: String) -> Route:
  match sl:
    case True{}:
      Kubelet.two.b(Kubelet.clean(pod), ns, pod, p)
    case False{}:
      RUnknown{p}

# {ns}/{pod}.
def Kubelet.two(s: Seg, +p: String) -> Route:
  match s:
    case Seg{ns, sl, pod}:
      Kubelet.two.a(sl, ns, pod, p)

def Kubelet.parse.by(k: Kind, rest: String, +p: String) -> Route:
  match k:
    case KLogs{}:
      Kubelet.three(Kubelet.seg(rest), KLogs{}, p)
    case KExec{}:
      Kubelet.three(Kubelet.seg(rest), KExec{}, p)
    case KAttach{}:
      Kubelet.three(Kubelet.seg(rest), KAttach{}, p)
    case KRun{}:
      Kubelet.three(Kubelet.seg(rest), KRun{}, p)
    case KPf{}:
      Kubelet.two(Kubelet.seg(rest), p)
    case KNone{}:
      RUnknown{p}

def Kubelet.parse.kind.go(sl: Bool, k: Kind, rest: String, +p: String) -> Route:
  match sl:
    case True{}:
      Kubelet.parse.by(k, rest, p)
    case False{}:
      RUnknown{p}

def Kubelet.parse.kind(s: Seg, +p: String) -> Route:
  match s:
    case Seg{+k, sl, rest}:
      Kubelet.parse.kind.go(sl, Kubelet.kind(k), rest, p)

def Kubelet.parse.s0.go(ok: Bool, rest: String, +p: String) -> Route:
  match ok:
    case True{}:
      Kubelet.parse.kind(Kubelet.seg(rest), p)
    case False{}:
      RUnknown{p}

def Kubelet.parse.s0(s: Seg, +p: String) -> Route:
  match s:
    case Seg{h, sl, rest}:
      Kubelet.parse.s0.go(Bool.and(String.is_empty(h), sl), rest, p)

def Kubelet.parse.dyn(+p: String) -> Route:
  Kubelet.parse.s0(Kubelet.seg(p), p)

def Kubelet.parse.fixed(m: Maybe<&2, Route>, +p: String) -> Route:
  match m:
    case Some{r}:
      r
    case None{}:
      Kubelet.parse.dyn(p)

# The route of a kubelet path (no query).
def Kubelet.parse(+p: String) -> Route:
  Kubelet.parse.fixed(Kubelet.fixed(p), p)

# Queries
# -------

def Kubelet.query.put(empty: Bool, +p: String, rest: List<&2, Q>) -> List<&2, Q>:
  match empty:
    case True{}:
      rest
    case False{}:
      Con{Kubelet.cut(p, '='), rest}

def Kubelet.query.go(ps: List<&2, String>) -> List<&2, Q>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{+p, t}:
      Kubelet.query.put(String.is_empty(p), p, Kubelet.query.go(t))

# A raw query ("a=1&b=2") as its parameters, in order; a parameter
# without "=" has the value "", as Go's url.ParseQuery reads it.
def Kubelet.query(s: String) -> List<&2, Q>:
  Kubelet.query.go(String.split(s, '&'))

def Kubelet.Q.show(q: Q) -> String:
  match q:
    case Q{k, v}:
      k ++ "=" ++ v

def Kubelet.query.more(qs: List<&2, Q>) -> String:
  match qs:
    case Nil{}:
      ""
    case Con{q, t}:
      "&" ++ Kubelet.Q.show(q) ++ Kubelet.query.more(t)

def Kubelet.query.show(qs: List<&2, Q>) -> String:
  match qs:
    case Nil{}:
      ""
    case Con{q, t}:
      Kubelet.Q.show(q) ++ Kubelet.query.more(t)

# "?" and the query, or "" for none.
def Kubelet.query.suffix(qs: List<&2, Q>) -> String:
  match qs:
    case Nil{}:
      ""
    case Con{q, t}:
      "?" ++ Kubelet.Q.show(q) ++ Kubelet.query.more(t)

def Kubelet.keep.if(keep: Bool, q: Q, rest: List<&2, Q>) -> List<&2, Q>:
  match keep:
    case True{}:
      Con{q, rest}
    case False{}:
      rest

# The kubelet's container log parameters, which the pod log API names the
# same (PodLogOptions: follow, previous, timestamps, sinceSeconds,
# sinceTime, tailLines, limitBytes, stream).
def Kubelet.log_keys() -> List<&2, String>:
  ["follow", "previous", "timestamps", "sinceSeconds", "sinceTime", "tailLines", "limitBytes", "stream"]

def Kubelet.log_q(qs: List<&2, Q>) -> List<&2, Q>:
  match qs:
    case Nil{}:
      Nil{}
    case Con{+q, t}:
      Kubelet.keep.if(Kubelet.in(Kubelet.Q.key(q), Kubelet.log_keys()), q, Kubelet.log_q(t))

# The stream flags: kubelet reads input, output, error and tty as on when
# "1" (remotecommand NewOptions); the pod exec and attach APIs name them
# stdin, stdout, stderr and tty (PodExecOptions, PodAttachOptions).
def Kubelet.stream.name(+k: String) -> String:
  Kubelet.str.pick(String.eq(k, "input"), "stdin",
  Kubelet.str.pick(String.eq(k, "output"), "stdout",
  Kubelet.str.pick(String.eq(k, "error"), "stderr",
  Kubelet.str.pick(String.eq(k, "tty"), "tty", ""))))

def Kubelet.stream.named(empty: Bool, name: String, rest: List<&2, Q>) -> List<&2, Q>:
  match empty:
    case True{}:
      rest
    case False{}:
      Con{Q{name, "true"}, rest}

def Kubelet.stream.flag(on: Bool, +name: String, rest: List<&2, Q>) -> List<&2, Q>:
  match on:
    case True{}:
      Kubelet.stream.named(String.is_empty(name), name, rest)
    case False{}:
      rest

def Kubelet.stream.cmd(cmd: Bool, +k: String, +v: String, rest: List<&2, Q>) -> List<&2, Q>:
  match cmd:
    case True{}:
      Con{Q{"command", v}, rest}
    case False{}:
      Kubelet.stream.flag(String.eq(v, "1"), Kubelet.stream.name(k), rest)

def Kubelet.stream_q(qs: List<&2, Q>) -> List<&2, Q>:
  match qs:
    case Nil{}:
      Nil{}
    case Con{Q{+k, +v}, t}:
      Kubelet.stream.cmd(String.eq(k, "command"), k, v, Kubelet.stream_q(t))

def Kubelet.pf.if(port: Bool, +v: String, rest: List<&2, Q>) -> List<&2, Q>:
  match port:
    case True{}:
      Con{Q{"ports", v}, rest}
    case False{}:
      rest

# Port forwarding: the apiserver's port parameters are the pod API's ports.
def Kubelet.pf_q(qs: List<&2, Q>) -> List<&2, Q>:
  match qs:
    case Nil{}:
      Nil{}
    case Con{Q{+k, +v}, t}:
      Kubelet.pf.if(String.eq(k, "port"), v, Kubelet.pf_q(t))

# Host requests
# -------------

# The host request of a route: pod routes name the host pod (Names.host_name
# of the virtual pod and namespace, with the vcluster name) in the target
# namespace; node routes keep their path under the node's proxy.
def Kubelet.host(+vc: String, +target: String, r: Route, qs: List<&2, Q>) -> Host:
  match r:
    case RLogs{+ns, +pod, c}:
      HPod{target, N.Names.host_name(pod, ns, vc), "log", Con{Q{"container", c}, Kubelet.log_q(qs)}}
    case RExec{+ns, +pod, c}:
      HPod{target, N.Names.host_name(pod, ns, vc), "exec", Con{Q{"container", c}, Kubelet.stream_q(qs)}}
    case RAttach{+ns, +pod, c}:
      HPod{target, N.Names.host_name(pod, ns, vc), "attach", Con{Q{"container", c}, Kubelet.stream_q(qs)}}
    case RPortForward{+ns, +pod}:
      HPod{target, N.Names.host_name(pod, ns, vc), "portforward", Kubelet.pf_q(qs)}
    case RRun{ns, pod, c}:
      HNode{Kubelet.render(RRun{ns, pod, c}), qs}
    case RPods{}:
      HNode{"/pods", qs}
    case RRunningPods{}:
      HNode{"/runningpods/", qs}
    case RStats{}:
      HNode{"/stats/summary", qs}
    case RMetrics{}:
      HNode{"/metrics", qs}
    case RCadvisor{}:
      HNode{"/metrics/cadvisor", qs}
    case RResource{}:
      HNode{"/metrics/resource", qs}
    case RProbes{}:
      HNode{"/metrics/probes", qs}
    case RHealthz{}:
      HLocal{}
    case RUnknown{p}:
      HNode{p, qs}

# The namespace a host request names: the pod's, or t for the others.
def Kubelet.host_ns(t: String, h: Host) -> String:
  match h:
    case HPod{ns, name, sub, q}:
      ns
    case HNode{p, q}:
      t
    case HLocal{}:
      t

# The host request's path and query; node names the node of a node proxy
# request.
def Kubelet.host_path(h: Host, +node: String) -> String:
  match h:
    case HPod{ns, name, sub, q}:
      "/api/v1/namespaces/" ++ ns ++ "/pods/" ++ name ++ "/" ++ sub ++ Kubelet.query.suffix(q)
    case HNode{p, q}:
      "/api/v1/nodes/" ++ node ++ "/proxy" ++ p ++ Kubelet.query.suffix(q)
    case HLocal{}:
      ""

# Answers
# -------

def Kubelet.json_type() -> String:
  "application/json"

def Kubelet.text_type() -> String:
  "text/plain; charset=utf-8"

# A metav1.Status failure as the apiserver encodes it (field order of the
# Go struct, omitempty).
def Kubelet.status(+code: U32, msg: String, reason: String, details: List<&2, J.KV>) -> String:
  J.Json.show(J.Json.obj([
    J.KV{"kind", J.JStr{"Status"}},
    J.KV{"apiVersion", J.JStr{"v1"}},
    J.KV{"metadata", J.Json.obj([])},
    J.KV{"status", J.JStr{"Failure"}},
    J.KV{"message", J.JStr{msg}},
    J.KV{"reason", J.JStr{reason}},
    J.KV{"details", J.Json.obj(details)},
    J.KV{"code", J.Json.u32(code)}]))

# kerrors.NewForbidden(corev1.Resource("nodes"), "", errors.New(why)).
def Kubelet.nodes_forbidden(why: String) -> Step:
  Answer{403, Kubelet.json_type(), Kubelet.status(403, "nodes is forbidden: " ++ why, "Forbidden", [J.KV{"kind", J.JStr{"nodes"}}])}

# vcluster metrics.go:198: the containerLogs ownership check.
def Kubelet.not_ours() -> Step:
  Kubelet.nodes_forbidden("access denied: pod does not belong to this virtual cluster")

# vcluster metrics.go:216: a subpath the proxy does not forward.
def Kubelet.not_permitted() -> Step:
  Kubelet.nodes_forbidden("proxy subpath not permitted in shared mode")

# A failed authorization, as the apiserver's WithAuthorization writes it
# for a non-resource request (responsewriters.Forbidden; the verb is the
# lower-case method, and vcluster's kubelet authorizer's reason is
# "forbidden").
def Kubelet.denied(+user: String, +method: String, +path: String) -> Step:
  Answer{403, Kubelet.json_type(), Kubelet.status(403,
    "forbidden: User \"" ++ user ++ "\" cannot " ++ String.to_lower(method) ++ " path \"" ++ path ++ "\": forbidden",
    "Forbidden", [])}

def Kubelet.not_found() -> Step:
  Answer{404, Kubelet.json_type(), Kubelet.status(404, "the server could not find the requested resource", "NotFound", [])}

def Kubelet.internal(msg: String) -> Step:
  Answer{500, Kubelet.json_type(), Kubelet.status(500, msg, "InternalError", [])}

def Kubelet.healthz() -> Step:
  Answer{200, Kubelet.text_type(), "ok"}

# Authorization
# -------------

# pkg/certs constants: the apiserver's kubelet client certificate.
def Kubelet.client_cn() -> String:
  "kube-apiserver-kubelet-client"

def Kubelet.masters() -> String:
  "system:masters"

# Who may call the kubelet API: the apiserver's kubelet client, or a
# member of system:masters (whom every SubjectAccessReview allows).
def Kubelet.allowed(s: T.Subject) -> Bool:
  match s:
    case T.Subject{cn, orgs}:
      Bool.or(String.eq(cn, Kubelet.client_cn()), Kubelet.in(Kubelet.masters(), orgs))

def Kubelet.user(s: T.Subject) -> String:
  match s:
    case T.Subject{cn, orgs}:
      cn

# Deciding
# --------

def Kubelet.full2(+ns: String, +pod: String) -> Bool:
  Bool.not(String.is_empty(ns)) && Bool.not(String.is_empty(pod))

def Kubelet.full3(+ns: String, +pod: String, +c: String) -> Bool:
  Kubelet.full2(ns, pod) && Bool.not(String.is_empty(c))

def Kubelet.decide.pod(full: Bool, ns: String, pod: String, c: String, method: String, target: String) -> Step:
  match full:
    case True{}:
      CheckPod{ns, pod, c, method, target}
    case False{}:
      Kubelet.not_ours()

# An unknown path goes to the node, except a containerLogs path that is
# not {ns}/{pod}/{container} (vcluster IsKubeletContainerLogs: malformed).
def Kubelet.unknown(logs: Bool, p: String, qs: List<&2, Q>, method: String) -> Step:
  match logs:
    case True{}:
      Kubelet.not_ours()
    case False{}:
      NodeStep{RUnknown{p}, qs, method}

def Kubelet.decide.route(r: Route, +vc: String, +target: String, +method: String, +qs: List<&2, Q>) -> Step:
  match r:
    case RHealthz{}:
      Kubelet.healthz()
    case RLogs{+ns, +pod, +c}:
      Kubelet.decide.pod(Kubelet.full3(ns, pod, c), ns, pod, c, method,
        Kubelet.host_path(Kubelet.host(vc, target, RLogs{ns, pod, c}, qs), ""))
    case RExec{+ns, +pod, +c}:
      Kubelet.decide.pod(Kubelet.full3(ns, pod, c), ns, pod, c, method,
        Kubelet.host_path(Kubelet.host(vc, target, RExec{ns, pod, c}, qs), ""))
    case RAttach{+ns, +pod, +c}:
      Kubelet.decide.pod(Kubelet.full3(ns, pod, c), ns, pod, c, method,
        Kubelet.host_path(Kubelet.host(vc, target, RAttach{ns, pod, c}, qs), ""))
    case RPortForward{+ns, +pod}:
      Kubelet.decide.pod(Kubelet.full2(ns, pod), ns, pod, "", method,
        Kubelet.host_path(Kubelet.host(vc, target, RPortForward{ns, pod}, qs), ""))
    case RMetrics{}:
      Kubelet.not_permitted()
    case RCadvisor{}:
      Kubelet.not_permitted()
    case RResource{}:
      Kubelet.not_permitted()
    case RProbes{}:
      Kubelet.not_permitted()
    case RUnknown{+p}:
      Kubelet.unknown(String.starts_with(p, "/containerLogs/"), p, qs, method)
    case x:
      NodeStep{x, qs, method}

def Kubelet.decide.go(ok: Bool, +vc: String, +target: String, +user: String, +method: String, +path: String,
  +rawq: String) -> Step:
  match ok:
    case True{}:
      Kubelet.decide.route(Kubelet.parse(path), vc, target, method, Kubelet.query(rawq))
    case False{}:
      Kubelet.denied(user, method, path)

# One request: the client's identity, the method and the request target
# (path and query).
def Kubelet.decide(+vc: String, +target: String, +s: T.Subject, +method: String, uri: String) -> Step:
  +pq = Kubelet.cut(uri, '?')
  Kubelet.decide.go(Kubelet.allowed(s), vc, target, Kubelet.user(s), method, Kubelet.Q.key(pq), Kubelet.Q.val(pq))

# The virtual pods: does pod (an object, or null when it is not found)
# have container c? "" asks only whether the pod exists.
def Kubelet.has_name(+c: String, cs: List<&2, J.Json>) -> Bool:
  match cs:
    case Nil{}:
      False{}
    case Con{x, t}:
      Bool.or(String.eq(J.Json.str_or(J.Json.get(x, "name"), ""), c), Kubelet.has_name(c, t))

def Kubelet.parsed(r: Result<&2, &2, String, J.Json>) -> J.Json:
  match r:
    case Fail{e}:
      J.JNull{}
    case Done{x}:
      x

def Kubelet.is_obj(j: J.Json) -> Bool:
  match j:
    case J.JObj{ms}:
      True{}
    case _:
      False{}

def Kubelet.has_container(+pod: J.Json, +c: String) -> Bool:
  Kubelet.is_obj(pod) && (String.is_empty(c)
    || Kubelet.has_name(c, J.Json.items(J.Json.at(pod, ["spec", "containers"])))
    || Kubelet.has_name(c, J.Json.items(J.Json.at(pod, ["spec", "initContainers"])))
    || Kubelet.has_name(c, J.Json.items(J.Json.at(pod, ["spec", "ephemeralContainers"]))))

def Kubelet.after_pod.go(ok: Bool, method: String, target: String) -> Step:
  match ok:
    case True{}:
      Relay{method, target}
    case False{}:
      Kubelet.not_ours()

# After CheckPod: relay when the virtual pod has the container.
def Kubelet.after_pod(+pod: J.Json, +c: String, method: String, target: String) -> Step:
  Kubelet.after_pod.go(Kubelet.has_container(pod, c), method, target)

def Kubelet.after_get.if(found: Bool, ok: Bool, +code: U32, body: String, +c: String, method: String, target: String) -> Step:
  match found ok:
    case True{} _:
      Kubelet.after_pod(Kubelet.parsed(J.Json.parse(body)), c, method, target)
    case False{} True{}:
      Kubelet.not_ours()
    case False{} False{}:
      Kubelet.internal("cannot read the virtual pod (status " ++ U32.show(code) ++ "): " ++ body)

# After CheckPod, from the virtual API server's answer to the pod GET: a
# pod (200) is checked, a missing one (404) is not ours, any other answer
# is an error of its own, not a denial (vcluster metrics.go:163-167).
def Kubelet.after_get(+code: U32, body: String, +c: String, method: String, target: String) -> Step:
  Kubelet.after_get.if(U32.is_eq(code, 200), U32.is_eq(code, 404), code, body, c, method, target)

# Nodes
# -----

# nodes.GetNodeHostLegacy: the 0.14 hostname.
def Kubelet.legacy_host(+name: String, +vc: String, +current: String) -> String:
  Nd.Node.dots(name) ++ "." ++ vc ++ "." ++ current ++ "." ++ Nd.Node.node_suffix()

def Kubelet.node_hit(+h: String, +vc: String, +current: String, +n: String) -> Bool:
  Bool.or(String.eq(Nd.Node.host(n), h), String.eq(Kubelet.legacy_host(n, vc, current), h))

def Kubelet.str_keep(keep: Bool, x: String, rest: List<&2, String>) -> List<&2, String>:
  match keep:
    case True{}:
      Con{x, rest}
    case False{}:
      rest

def Kubelet.node_hits(+h: String, +vc: String, +current: String, ns: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}:
      Nil{}
    case Con{+n, t}:
      Kubelet.str_keep(Kubelet.node_hit(h, vc, current, n), n, Kubelet.node_hits(h, vc, current, t))

def Kubelet.one(ns: List<&2, String>) -> Maybe<&2, String>:
  match ns:
    case Con{n, Nil{}}:
      Some{n}
    case _:
      None{}

def Kubelet.node_of.go(ps: List<&2, String>, +vc: String, +current: String, +nodes: List<&2, String>) -> Maybe<&2, String>:
  match ps:
    case Con{+h, Con{p, Nil{}}}:
      Kubelet.one(Kubelet.node_hits(h, vc, current, nodes))
    case _:
      None{}

# The virtual node a Host header names (vcluster nodeNameFromHost, by
# hostname: the node list is the virtual cluster's).
def Kubelet.node_of(host: String, +vc: String, +current: String, +nodes: List<&2, String>) -> Maybe<&2, String>:
  Kubelet.node_of.go(String.split(host, ':'), vc, current, nodes)

def Kubelet.names(os: List<&2, J.Json>) -> List<&2, String>:
  match os:
    case Nil{}:
      Nil{}
    case Con{o, t}:
      Con{J.Json.str_or(J.Json.at(o, ["metadata", "name"]), ""), Kubelet.names(t)}

def Kubelet.node_names.if(ok: Bool, body: String) -> List<&2, String>:
  match ok:
    case True{}:
      Kubelet.names(J.Json.items(J.Json.get(Kubelet.parsed(J.Json.parse(body)), "items")))
    case False{}:
      Nil{}

# The names of the virtual nodes, from the answer to GET /api/v1/nodes.
def Kubelet.node_names(+code: U32, body: String) -> List<&2, String>:
  Kubelet.node_names.if(U32.is_eq(code, 200), body)

def Kubelet.node_step.go(r: Route, +n: String, qs: List<&2, Q>, method: String) -> Step:
  match r:
    case RStats{}:
      Stats{Kubelet.host_path(HNode{"/stats/summary", qs}, n)}
    case RPods{}:
      PodList{n}
    case RRunningPods{}:
      PodList{n}
    case x:
      Relay{method, Kubelet.host_path(HNode{Kubelet.render(x), qs}, n)}

# After NodeStep: node is the node the Host header names, if any.
def Kubelet.node_step(m: Maybe<&2, String>, r: Route, qs: List<&2, Q>, method: String) -> Step:
  match m:
    case Some{n}:
      Kubelet.node_step.go(r, n, qs, method)
    case None{}:
      Kubelet.not_found()

# Stats
# -----

def Kubelet.str_at(j: J.Json, path: List<&2, String>) -> String:
  J.Json.str_or(J.Json.at(j, path), "")

# A virtual object's references.
def Kubelet.vref(+vc: String, +o: J.Json) -> VRef:
  +name = Kubelet.str_at(o, ["metadata", "name"])
  +ns = Kubelet.str_at(o, ["metadata", "namespace"])
  VRef{N.Names.host_name(name, ns, vc), name, ns, Kubelet.str_at(o, ["metadata", "uid"])}

def Kubelet.vrefs.seq(+vc: String, os: List<&2, J.Json>) -> List<&2, VRef>:
  match os:
    case Nil{}:
      Nil{}
    case Con{o, t}:
      Con{Kubelet.vref(vc, o), Kubelet.vrefs.seq(vc, t)}

# The references of every virtual object, computed in halves in parallel
# (d levels deep).
def Kubelet.vrefs(d: Nat, +vc: String, +os: List<&2, J.Json>) -> List<&2, VRef>:
  match d:
    case 0n:
      Kubelet.vrefs.seq(vc, os)
    case 1n+p:
      +half = Nat.div(List.length(&2, J.Json, os), 2n)
      a b = Kubelet.vrefs(p, vc, List.take(&2, J.Json, os, half)) Kubelet.vrefs(p, vc, List.drop(&2, J.Json, os, half))
      List.append(&2, VRef, a, b)

def Kubelet.VRef.host(r: VRef) -> String:
  match r:
    case VRef{h, n, ns, u}:
      h

def Kubelet.find.at(hit: Bool, r: VRef, rest: Maybe<&2, VRef>) -> Maybe<&2, VRef>:
  match hit:
    case True{}:
      Some{r}
    case False{}:
      rest

def Kubelet.find(+h: String, rs: List<&2, VRef>) -> Maybe<&2, VRef>:
  match rs:
    case Nil{}:
      None{}
    case Con{+r, t}:
      Kubelet.find.at(String.eq(Kubelet.VRef.host(r), h), r, Kubelet.find(h, t))

# The virtual object a host reference (name and namespace) stands for: a
# host object in the target namespace whose name is a virtual object's
# host name (vcluster mappings.HostToVirtual, single-namespace mode).
def Kubelet.lookup.go(ok: Bool, m: Maybe<&2, VRef>) -> Maybe<&2, VRef>:
  match ok:
    case True{}:
      m
    case False{}:
      None{}

def Kubelet.lookup(+target: String, +refs: List<&2, VRef>, +ref: J.Json) -> Maybe<&2, VRef>:
  Kubelet.lookup.go(String.eq(Kubelet.str_at(ref, ["namespace"]), target), Kubelet.find(Kubelet.str_at(ref, ["name"]), refs))

def Kubelet.vol.go(m: Maybe<&2, VRef>, v: J.Json) -> Maybe<&2, J.Json>:
  match m:
    case Some{VRef{h, n, ns, u}}:
      Some{J.Json.set(v, "pvcRef", J.Json.obj([J.KV{"name", J.JStr{n}}, J.KV{"namespace", J.JStr{ns}}]))}
    case None{}:
      None{}

def Kubelet.vol.if(pvc: Bool, +target: String, +pvcs: List<&2, VRef>, +v: J.Json) -> Maybe<&2, J.Json>:
  match pvc:
    case True{}:
      Kubelet.vol.go(Kubelet.lookup(target, pvcs, J.Json.get(v, "pvcRef")), v)
    case False{}:
      Some{v}

# A volume: renamed when it names a virtual PVC, dropped when it names
# another, kept when it names none.
def Kubelet.vol(+target: String, +pvcs: List<&2, VRef>, +v: J.Json) -> Maybe<&2, J.Json>:
  Kubelet.vol.if(Bool.not(J.Json.is_null(J.Json.get(v, "pvcRef"))), target, pvcs, v)

def Kubelet.somes(ms: List<&2, Maybe<&2, J.Json>>) -> List<&2, J.Json>:
  match ms:
    case Nil{}:
      Nil{}
    case Con{Some{x}, t}:
      Con{x, Kubelet.somes(t)}
    case Con{None{}, t}:
      Kubelet.somes(t)

def Kubelet.vols(+target: String, +pvcs: List<&2, VRef>, vs: List<&2, J.Json>) -> List<&2, Maybe<&2, J.Json>>:
  match vs:
    case Nil{}:
      Nil{}
    case Con{v, t}:
      Con{Kubelet.vol(target, pvcs, v), Kubelet.vols(target, pvcs, t)}

def Kubelet.set_vols.if(empty: Bool, p: J.Json, vs: List<&2, J.Json>) -> J.Json:
  match empty:
    case True{}:
      J.Json.del(p, "volume")
    case False{}:
      J.Json.set(p, "volume", J.Json.arr(vs))

def Kubelet.set_vols(p: J.Json, +vs: List<&2, J.Json>) -> J.Json:
  Kubelet.set_vols.if(List.is_empty(&2, J.Json, vs), p, vs)

def Kubelet.renamed(v: VRef, +target: String, +pvcs: List<&2, VRef>, +p: J.Json) -> J.Json:
  match v:
    case VRef{h, n, ns, u}:
      Kubelet.set_vols(J.Json.set(p, "podRef", J.Json.obj([J.KV{"name", J.JStr{n}}, J.KV{"namespace", J.JStr{ns}}, J.KV{"uid", J.JStr{u}}])),
        Kubelet.somes(Kubelet.vols(target, pvcs, J.Json.items(J.Json.get(p, "volume")))))

def Kubelet.stats.pod.go(m: Maybe<&2, VRef>, +target: String, +pvcs: List<&2, VRef>, p: J.Json) -> Maybe<&2, J.Json>:
  match m:
    case Some{v}:
      Some{Kubelet.renamed(v, target, pvcs, p)}
    case None{}:
      None{}

# One pod's stats, renamed to the virtual pod, or dropped.
def Kubelet.stats.pod(+target: String, +pods: List<&2, VRef>, +pvcs: List<&2, VRef>, +p: J.Json) -> Maybe<&2, J.Json>:
  Kubelet.stats.pod.go(Kubelet.lookup(target, pods, J.Json.get(p, "podRef")), target, pvcs, p)

def Kubelet.stats.seq(+target: String, +pods: List<&2, VRef>, +pvcs: List<&2, VRef>, ps: List<&2, J.Json>) -> List<&2, J.Json>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{p, t}:
      List.append(&2, J.Json, Kubelet.somes([Kubelet.stats.pod(target, pods, pvcs, p)]), Kubelet.stats.seq(target, pods, pvcs, t))

# Every pod's stats, in halves in parallel (d levels deep).
def Kubelet.stats.par(d: Nat, +target: String, +pods: List<&2, VRef>, +pvcs: List<&2, VRef>, +ps: List<&2, J.Json>) ->
  List<&2, J.Json>:
  match d:
    case 0n:
      Kubelet.stats.seq(target, pods, pvcs, ps)
    case 1n+q:
      +half = Nat.div(List.length(&2, J.Json, ps), 2n)
      a b = Kubelet.stats.par(q, target, pods, pvcs, List.take(&2, J.Json, ps, half)) Kubelet.stats.par(q, target, pods, pvcs, List.drop(&2, J.Json, ps, half))
      List.append(&2, J.Json, a, b)

def Kubelet.depth() -> Nat:
  3n

# vcluster rewriteStats: the summary's pods renamed to the virtual pods
# (name, namespace, uid), their PVC volumes to the virtual PVCs; other pods
# and volumes dropped. pods and pvcs are the virtual objects.
def Kubelet.stats(+vc: String, +target: String, pods: List<&2, J.Json>, pvcs: List<&2, J.Json>, +summary: J.Json) -> J.Json:
  +prefs = Kubelet.vrefs(Kubelet.depth(), vc, pods)
  +crefs = Kubelet.vrefs(Kubelet.depth(), vc, pvcs)
  J.Json.set(summary, "pods", J.Json.arr(Kubelet.stats.par(Kubelet.depth(), target, prefs, crefs, J.Json.items(J.Json.get(summary, "pods")))))

def Kubelet.stats_answer.go(ok: Bool, +vc: String, +target: String, +summary: J.Json, pods: J.Json, pvcs: J.Json) -> Step:
  match ok:
    case True{}:
      Answer{200, Kubelet.json_type(), J.Json.show(Kubelet.stats(vc, target, J.Json.items(J.Json.get(pods, "items")),
        J.Json.items(J.Json.get(pvcs, "items")), summary))}
    case False{}:
      Kubelet.internal("cannot read the kubelet's stats summary")

def Kubelet.stats_answer.code(ok: Bool, +code: U32, +vc: String, +target: String, +summary: String, pods: String, pvcs: String) -> Step:
  match ok:
    case True{}:
      +s = Kubelet.parsed(J.Json.parse(summary))
      Kubelet.stats_answer.go(Kubelet.is_obj(s), vc, target, s, Kubelet.parsed(J.Json.parse(pods)), Kubelet.parsed(J.Json.parse(pvcs)))
    case False{}:
      Answer{code, Kubelet.json_type(), summary}

# After Stats: the host's answer (status and body) and the virtual pod and
# PVC lists (JSON text). A status other than 200 passes through as it is.
def Kubelet.stats_answer(+code: U32, +vc: String, +target: String, +summary: String, pods: String, pvcs: String) -> Step:
  Kubelet.stats_answer.code(U32.is_eq(code, 200), code, vc, target, summary, pods, pvcs)

def Kubelet.on_node.if(hit: Bool, p: J.Json) -> Maybe<&2, J.Json>:
  match hit:
    case True{}:
      Some{p}
    case False{}:
      None{}

def Kubelet.on_node(+node: String, ps: List<&2, J.Json>) -> List<&2, J.Json>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{+p, t}:
      List.append(&2, J.Json, Kubelet.somes([Kubelet.on_node.if(String.eq(Kubelet.str_at(p, ["spec", "nodeName"]), node), p)]),
        Kubelet.on_node(node, t))

# After PodList: the virtual pods bound to the node, as a PodList.
def Kubelet.pods_answer(+node: String, pods: String) -> Step:
  Answer{200, Kubelet.json_type(), J.Json.show(J.Json.obj([
    J.KV{"kind", J.JStr{"PodList"}},
    J.KV{"apiVersion", J.JStr{"v1"}},
    J.KV{"metadata", J.Json.obj([])},
    J.KV{"items", J.Json.arr(Kubelet.on_node(node, J.Json.items(J.Json.get(Kubelet.parsed(J.Json.parse(pods)), "items"))))}]))}

# HTTP
# ----

def Kubelet.hdr.of(q: Q) -> Hdr:
  match q:
    case Q{k, v}:
      Hdr{String.trim(k), String.trim(v)}

def Kubelet.hdr(line: String) -> Hdr:
  Kubelet.hdr.of(Kubelet.cut(line, ':'))

def Kubelet.hdrs.put(empty: Bool, l: String, rest: List<&2, Hdr>) -> List<&2, Hdr>:
  match empty:
    case True{}:
      rest
    case False{}:
      Con{Kubelet.hdr(l), rest}

def Kubelet.hdrs(ls: List<&2, String>) -> List<&2, Hdr>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{+l, t}:
      Kubelet.hdrs.put(String.is_empty(String.trim(l)), l, Kubelet.hdrs(t))

def Kubelet.Req.of(first: List<&2, String>, hs: List<&2, Hdr>) -> Maybe<&2, Req>:
  match first:
    case Con{m, Con{u, Con{v, Nil{}}}}:
      Some{Req{m, u, hs}}
    case _:
      None{}

def Kubelet.Req.lines(ls: List<&2, String>) -> Maybe<&2, Req>:
  match ls:
    case Nil{}:
      None{}
    case Con{l, t}:
      Kubelet.Req.of(String.split(String.trim(l), ' '), Kubelet.hdrs(t))

# A request head (the text before the blank line): the request line and
# the headers.
def Kubelet.Req.parse(head: String) -> Maybe<&2, Req>:
  Kubelet.Req.lines(String.split(head, '\n'))

def Kubelet.header.at(hit: Bool, v: String, rest: String) -> String:
  match hit:
    case True{}:
      v
    case False{}:
      rest

# A header's value ("" when absent); names compare without case.
def Kubelet.header(+name: String, hs: List<&2, Hdr>) -> String:
  match hs:
    case Nil{}:
      ""
    case Con{Hdr{n, v}, t}:
      Kubelet.header.at(String.eq(String.to_lower(n), String.to_lower(name)), v, Kubelet.header(name, t))

# An upgrade (SPDY/3.1, or a websocket v5.channel.k8s.io protocol).
def Kubelet.is_upgrade(+hs: List<&2, Hdr>) -> Bool:
  Bool.not(String.is_empty(Kubelet.header("Upgrade", hs)))

# The headers the proxy sets itself, or never forwards: hop-by-hop ones,
# the client's credentials, and impersonation (the host credentials must
# not be lent to another identity).
def Kubelet.dropped(+n: String) -> Bool:
  +l = String.to_lower(n)
  Kubelet.in(l, ["host", "authorization", "connection", "keep-alive", "proxy-connection", "proxy-authorization"])
    || String.starts_with(l, "impersonate-")

def Kubelet.hdrs.show(hs: List<&2, Hdr>) -> String:
  match hs:
    case Nil{}:
      ""
    case Con{Hdr{+n, v}, t}:
      Kubelet.str.pick(Kubelet.dropped(n), "", n ++ ": " ++ v ++ "\r\n") ++ Kubelet.hdrs.show(t)

def Kubelet.auth_line(+token: String) -> String:
  Kubelet.str.pick(String.is_empty(token), "", "Authorization: Bearer " ++ token ++ "\r\n")

# The request head sent to the host API server: the client's headers less
# the dropped ones; an upgrade keeps "Connection: Upgrade", anything else
# asks the host to close after its answer (the proxy relays one request
# per connection).
def Kubelet.forward_head(method: String, target: String, host: String, +token: String, +hs: List<&2, Hdr>) -> String:
  method ++ " " ++ target ++ " HTTP/1.1\r\nHost: " ++ host ++ "\r\n" ++ Kubelet.hdrs.show(hs)
    ++ Kubelet.str.pick(Kubelet.is_upgrade(hs), "Connection: Upgrade\r\n", "Connection: close\r\n")
    ++ Kubelet.auth_line(token) ++ "\r\n"

# A buffered GET (read to the end of the connection); extra is more header
# lines.
def Kubelet.get_head(path: String, host: String, +token: String, extra: String) -> String:
  "GET " ++ path ++ " HTTP/1.1\r\nHost: " ++ host ++ "\r\nAccept: application/json\r\nUser-Agent: vk8s-kubelet-proxy\r\nConnection: close\r\n"
    ++ Kubelet.auth_line(token) ++ extra ++ "\r\n"

def Kubelet.reason(+code: U32) -> String:
  Kubelet.str.pick(U32.is_eq(code, 200), "OK",
  Kubelet.str.pick(U32.is_eq(code, 400), "Bad Request",
  Kubelet.str.pick(U32.is_eq(code, 403), "Forbidden",
  Kubelet.str.pick(U32.is_eq(code, 404), "Not Found",
  Kubelet.str.pick(U32.is_eq(code, 500), "Internal Server Error",
  Kubelet.str.pick(U32.is_eq(code, 502), "Bad Gateway", "Error"))))))

# An answer the proxy writes itself; the connection closes after it.
def Kubelet.answer_text(+code: U32, ctype: String, body: String) -> String:
  "HTTP/1.1 " ++ U32.show(code) ++ " " ++ Kubelet.reason(code) ++ "\r\nContent-Type: " ++ ctype
    ++ "\r\nCache-Control: no-cache, private\r\nConnection: close\r\n\r\n" ++ body

# Where the head of a request ends: the bytes up to the blank line, and
# whether it was found.
def Kubelet.head_end.go(bs: List<&2, U32>) -> Bool:
  match bs:
    case Con{13, Con{10, Con{13, Con{10, t}}}}:
      True{}
    case Con{b, t}:
      Kubelet.head_end.go(t)
    case Nil{}:
      False{}

def Kubelet.head_end(bs: List<&2, U32>) -> Bool:
  Kubelet.head_end.go(bs)

# The head's bytes as text (one char per byte: the head is ASCII) and the
# bytes after the blank line.
def Kubelet.split_head.go(bs: List<&2, U32>, acc: String) -> String & List<&2, U32>:
  match bs:
    case Con{13, Con{10, Con{13, Con{10, t}}}}:
      (String.reverse(acc), t)
    case Con{b, t}:
      Kubelet.split_head.go(t, SCon{Chr{b}, acc})
    case Nil{}:
      (String.reverse(acc), Nil{})

def Kubelet.split_head(bs: List<&2, U32>) -> String & List<&2, U32>:
  Kubelet.split_head.go(bs, "")

# Options
# -------

def Kubelet.opt.at(hit: Bool, +a: String, +pre: String, rest: String) -> String:
  match hit:
    case True{}:
      String.drop(a, String.length(pre))
    case False{}:
      rest

# The value of --name=value in args, or d.
def Kubelet.opt(args: List<&2, String>, +name: String, d: String) -> String:
  match args:
    case Nil{}:
      d
    case Con{+a, t}:
      Kubelet.opt.at(String.starts_with(a, "--" ++ name ++ "="), a, "--" ++ name ++ "=", Kubelet.opt(t, name, d))
