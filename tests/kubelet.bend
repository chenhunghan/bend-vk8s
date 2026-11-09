import Base
import ../src/net/kubelet.bend as K
import ../src/net/subject.bend as T
import ../src/guest/plan.bend as P

# Tests for src/net/kubelet.bend. The laws in laws/kubelet.bend transcribe
# vcluster's kubelet proxy spec; these cover the rest: every route's
# parse and render, queries, request heads, the head forwarded to the
# host (hop-by-hop, credential and impersonation headers dropped),
# answers, the stats rewrite from JSON text, and the kubelet serving
# certificate step of the boot plan. VClusterName "vcluster", target
# namespace "test".

def report(name: String, got: String, want: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name ++ ": got " ++ got ++ ", want " ++ want)

def check(name: String, +got: String, +want: String) -> IO(Unit):
  report(name, got, want, String.eq(got, want))

def show_route(r: K.Route) -> String:
  match r:
    case K.RLogs{ns, pod, c}:
      "logs " ++ ns ++ " " ++ pod ++ " " ++ c
    case K.RExec{ns, pod, c}:
      "exec " ++ ns ++ " " ++ pod ++ " " ++ c
    case K.RAttach{ns, pod, c}:
      "attach " ++ ns ++ " " ++ pod ++ " " ++ c
    case K.RPortForward{ns, pod}:
      "portforward " ++ ns ++ " " ++ pod
    case K.RRun{ns, pod, c}:
      "run " ++ ns ++ " " ++ pod ++ " " ++ c
    case K.RPods{}:
      "pods"
    case K.RRunningPods{}:
      "runningpods"
    case K.RStats{}:
      "stats"
    case K.RMetrics{}:
      "metrics"
    case K.RCadvisor{}:
      "cadvisor"
    case K.RResource{}:
      "resource"
    case K.RProbes{}:
      "probes"
    case K.RHealthz{}:
      "healthz"
    case K.RUnknown{p}:
      "unknown " ++ p

def show_step(s: K.Step) -> String:
  match s:
    case K.Answer{code, ctype, body}:
      "answer " ++ U32.show(code) ++ " " ++ ctype ++ " " ++ body
    case K.Relay{m, t}:
      "relay " ++ m ++ " " ++ t
    case K.CheckPod{ns, pod, c, m, t}:
      "check " ++ ns ++ "/" ++ pod ++ "/" ++ c ++ " " ++ m ++ " " ++ t
    case K.NodeStep{r, q, m}:
      "node " ++ show_route(r) ++ " " ++ K.Kubelet.query.show(q) ++ " " ++ m
    case K.Stats{t}:
      "stats " ++ t
    case K.PodList{n}:
      "podlist " ++ n

def client() -> T.Subject:
  T.Subject{"kube-apiserver-kubelet-client", ["system:masters"]}

def decide(+method: String, uri: String) -> String:
  show_step(K.Kubelet.decide("vcluster", "test", client(), method, uri))

def roundtrip(+name: String, +path: String, +want: String) -> IO(Unit):
  do IO<Unit>:
    check("parse " ++ name, show_route(K.Kubelet.parse(path)), want)
    check("render " ++ name, K.Kubelet.render(K.Kubelet.parse(path)), path)

def show_req(m: Maybe<&2, K.Req>) -> String:
  match m:
    case None{}:
      "none"
    case Some{K.Req{method, uri, +hs}}:
      method ++ " " ++ uri ++ " upgrade=" ++ Bool.show(K.Kubelet.is_upgrade(hs)) ++ " host=" ++ K.Kubelet.header("host", hs)

def show_head(r: String & List<&2, U32>) -> String:
  match r:
    case (h, rest):
      h ++ "|" ++ Nat.show(List.length(&2, U32, rest))

def head() -> String:
  "POST /exec/default/nginx/web?command=sh&input=1&output=1 HTTP/1.1\r\nHost: 10.10.0.2:10250\r\nUpgrade: SPDY/3.1\r\nConnection: Upgrade\r\nX-Stream-Protocol-Version: v4.channel.k8s.io\r\nAuthorization: Bearer abc\r\nImpersonate-User: system:admin\r\nUser-Agent: kube-apiserver\r\n"

def headers(m: Maybe<&2, K.Req>) -> List<&2, K.Hdr>:
  match m:
    case None{}:
      []
    case Some{K.Req{method, uri, hs}}:
      hs

def bytes(s: String) -> List<&2, U32>:
  match s:
    case SNil{}:
      []
    case SCon{Chr{c}, t}:
      Con{c, bytes(t)}

def main() -> IO(Unit):
  do IO<Unit>:
    roundtrip("logs", "/containerLogs/default/nginx/web", "logs default nginx web")
    roundtrip("exec", "/exec/default/nginx/web", "exec default nginx web")
    roundtrip("attach", "/attach/default/nginx/web", "attach default nginx web")
    roundtrip("portforward", "/portForward/default/nginx", "portforward default nginx")
    roundtrip("run", "/run/default/nginx/web", "run default nginx web")
    roundtrip("pods", "/pods", "pods")
    roundtrip("runningpods", "/runningpods/", "runningpods")
    roundtrip("stats", "/stats/summary", "stats")
    roundtrip("metrics", "/metrics", "metrics")
    roundtrip("cadvisor", "/metrics/cadvisor", "cadvisor")
    roundtrip("resource", "/metrics/resource", "resource")
    roundtrip("probes", "/metrics/probes", "probes")
    roundtrip("healthz", "/healthz", "healthz")
    roundtrip("unknown", "/configz", "unknown /configz")
    roundtrip("no leading slash", "containerLogs/a/b/c", "unknown containerLogs/a/b/c")
    roundtrip("extra segment", "/exec/a/b/c/d", "unknown /exec/a/b/c/d")
    roundtrip("portforward extra", "/portForward/a/b/c", "unknown /portForward/a/b/c")
    roundtrip("empty", "", "unknown ")
    check("pods trailing slash", show_route(K.Kubelet.parse("/pods/")), "pods")
    check("runningpods no slash", show_route(K.Kubelet.parse("/runningpods")), "runningpods")
    check("query parse", K.Kubelet.query.show(K.Kubelet.query("a=1&&b&c=x=y")), "a=1&b=&c=x=y")
    check("query empty", K.Kubelet.query.suffix(K.Kubelet.query("")), "")
    check("exec flags off", decide("POST", "/exec/default/nginx/web?command=ls&input=0&tty=true"),
      "check default/nginx/web POST /api/v1/namespaces/test/pods/nginx-x-default-x-vcluster/exec?container=web&command=ls")
    check("logs unknown option dropped", decide("GET", "/containerLogs/default/nginx/web?follow=true&insecureSkipTLSVerifyBackend=true"),
      "check default/nginx/web GET /api/v1/namespaces/test/pods/nginx-x-default-x-vcluster/log?container=web&follow=true")
    check("logs since time kept encoded", decide("GET", "/containerLogs/default/nginx/web?sinceTime=2024-01-02T03%3A04%3A05Z"),
      "check default/nginx/web GET /api/v1/namespaces/test/pods/nginx-x-default-x-vcluster/log?container=web&sinceTime=2024-01-02T03%3A04%3A05Z")
    check("long host name hashed", decide("GET", "/containerLogs/a-very-long-namespace-name-for-tests/a-very-long-pod-name-0123456789/c"),
      "check a-very-long-namespace-name-for-tests/a-very-long-pod-name-0123456789/c GET /api/v1/namespaces/test/pods/a-very-long-pod-name-0123456789-x-a-very-long-namesp-b7b0baa4f7/log?container=c")
    check("run goes to the node", decide("POST", "/run/default/nginx/web?cmd=ls"), "node run default nginx web cmd=ls POST")
    check("pods ok on node", show_step(K.Kubelet.node_step(Some{"n1"}, K.RPods{}, [], "GET")), "podlist n1")
    check("run relayed to node", show_step(K.Kubelet.node_step(Some{"n1"}, K.RRun{"default", "nginx", "web"}, K.Kubelet.query("cmd=ls"), "POST")),
      "relay POST /api/v1/nodes/n1/proxy/run/default/nginx/web?cmd=ls")
    check("healthz answer", decide("GET", "/healthz"), "answer 200 text/plain; charset=utf-8 ok")
    check("post verb in denial", show_step(K.Kubelet.decide("vcluster", "test", T.Subject{"bob", []}, "POST", "/exec/a/b/c")),
      "answer 403 application/json {\"kind\":\"Status\",\"apiVersion\":\"v1\",\"metadata\":{},\"status\":\"Failure\",\"message\":\"forbidden: User \\\"bob\\\" cannot post path \\\"/exec/a/b/c\\\": forbidden\",\"reason\":\"Forbidden\",\"details\":{},\"code\":403}")
    check("request head", show_req(K.Kubelet.Req.parse(head())),
      "POST /exec/default/nginx/web?command=sh&input=1&output=1 upgrade=True host=10.10.0.2:10250")
    check("bad request line", show_req(K.Kubelet.Req.parse("GARBAGE\r\n")), "none")
    check("forward upgrade", K.Kubelet.forward_head("POST", "/api/v1/namespaces/test/pods/p/exec?container=web", "127.0.0.1:6443", "", headers(K.Kubelet.Req.parse(head()))),
      "POST /api/v1/namespaces/test/pods/p/exec?container=web HTTP/1.1\r\nHost: 127.0.0.1:6443\r\nUpgrade: SPDY/3.1\r\nX-Stream-Protocol-Version: v4.channel.k8s.io\r\nUser-Agent: kube-apiserver\r\nConnection: Upgrade\r\n\r\n")
    check("forward plain with token", K.Kubelet.forward_head("GET", "/x", "h", "tok", headers(K.Kubelet.Req.parse("GET /y HTTP/1.1\r\nHost: a\r\nConnection: keep-alive\r\nAccept: */*\r\n"))),
      "GET /x HTTP/1.1\r\nHost: h\r\nAccept: */*\r\nConnection: close\r\nAuthorization: Bearer tok\r\n\r\n")
    check("get head", K.Kubelet.get_head("/api/v1/pods", "127.0.0.1:6443", "", "X-Remote-User: u\r\n"),
      "GET /api/v1/pods HTTP/1.1\r\nHost: 127.0.0.1:6443\r\nAccept: application/json\r\nUser-Agent: vk8s-kubelet-proxy\r\nConnection: close\r\nX-Remote-User: u\r\n\r\n")
    check("answer text", K.Kubelet.answer_text(200, "text/plain; charset=utf-8", "ok"),
      "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-cache, private\r\nConnection: close\r\n\r\nok")
    check("head end found", Bool.show(K.Kubelet.head_end(bytes("GET / HTTP/1.1\r\nA: b\r\n\r\nrest"))), "True")
    check("head end missing", Bool.show(K.Kubelet.head_end(bytes("GET / HTTP/1.1\r\nA: b\r\n"))), "False")
    check("split head", show_head(K.Kubelet.split_head(bytes("GET / HTTP/1.1\r\nA: b\r\n\r\nrest"))), "GET / HTTP/1.1\r\nA: b|4")
    check("opt", K.Kubelet.opt(["vk8s", "kubelet-proxy", "--port=10250", "--target=ns"], "target", "d"), "ns")
    check("opt default", K.Kubelet.opt(["vk8s"], "port", "10250"), "10250")
    check("stats text", show_step(K.Kubelet.stats_answer(200, "vcluster", "test",
        "{\"node\":{\"nodeName\":\"n1\"},\"pods\":[{\"podRef\":{\"name\":\"nginx-x-default-x-vcluster\",\"namespace\":\"test\",\"uid\":\"h1\"}},{\"podRef\":{\"name\":\"x\",\"namespace\":\"kube-system\",\"uid\":\"h2\"}}]}",
        "{\"items\":[{\"metadata\":{\"name\":\"nginx\",\"namespace\":\"default\",\"uid\":\"v1\"}}]}", "{\"items\":[]}")),
      "answer 200 application/json {\"node\":{\"nodeName\":\"n1\"},\"pods\":[{\"podRef\":{\"name\":\"nginx\",\"namespace\":\"default\",\"uid\":\"v1\"}}]}")
    check("stats bad json", show_step(K.Kubelet.stats_answer(200, "vcluster", "test", "not json", "{}", "{}")),
      "answer 500 application/json {\"kind\":\"Status\",\"apiVersion\":\"v1\",\"metadata\":{},\"status\":\"Failure\",\"message\":\"cannot read the kubelet's stats summary\",\"reason\":\"InternalError\",\"details\":{},\"code\":500}")
    check("kubelet serving cert config", P.Plan.kubelet_serving_config("demo", "10.10.0.2"),
      "apiVersion: kubeadm.k8s.io/v1beta4\nkind: InitConfiguration\nlocalAPIEndpoint:\n  advertiseAddress: 10.10.0.2\n  bindPort: 6443\nnodeRegistration:\n  name: demo\n---\napiVersion: kubeadm.k8s.io/v1beta4\nkind: ClusterConfiguration\nkubernetesVersion: v1.36.6\ncertificatesDir: /var/lib/vcluster/pki/kubelet-serving\n")
