import Base
import bend-kube-runtime@0.2.0.0/src/http.bend as H
import ../src/net/kubelet.bend as K
import ../src/net/subject.bend as T
import ./tls_server.bend as S

# The fake kubelet's server (vcluster pkg/server/filters/kubelet.go): the
# kubelet API on :10250, for the virtual kube-apiserver's logs, exec,
# attach, port-forward and stats calls. Every decision is
# src/net/kubelet.bend's; this file only moves bytes.
#
# A connection: the TLS handshake asks for a client certificate from the
# cluster CA (the apiserver's kubelet client certificate); one HTTP/1.1
# request head is read; K.Kubelet.decide says what to do. A relayed request
# is sent to the host API server with the syncer's host credentials
# (TlsSrv.connect) and the two connections are spliced, so a followed log
# streams as it comes and an upgraded exec, attach or port-forward
# (SPDY/3.1, or websocket v5.channel.k8s.io) flows byte for byte both
# ways. One request per connection: a relayed one asks the host to close
# after its answer, and the proxy's own answers close too.
#
# The virtual API server (pod checks, nodes, stats names) is read as the
# aggregator reads it: the front-proxy client certificate and the
# X-Remote-User/X-Remote-Group headers (kube-apiserver's requestheader
# authentication, which vk8s's control plane configures).
#
# Kubelet.serve(cfg) runs forever; the syncer's main starts it with
# IO.spawn. `vk8s kubelet-proxy --flag=value ...` (host/init.bend) runs it
# alone, for tests: see Kubelet.cfg for the flags.

# An API server to call: an IPv4 address and port, the name its
# certificate carries ("" for the address), its CA bundle, a client
# certificate and key (PEM files, "" for none), a bearer token ("" for
# none), and more header lines for each request.
type Up is Data:
  Up{addr: String, port: U32, name: String, ca: String, cert: String, key: String, token: String, extra: String}

# The proxy: where it listens and its serving certificate and key, the CA
# its clients' certificates chain to, the vcluster name, the target
# namespace and the namespace vcluster runs in, the host API server and
# the virtual one.
type KCfg is Data:
  KCfg{bind: String, port: U32, cert: String, key: String, ca: String, vc: String, target: String,
    current: String, host: Up, virt: Up}

# A buffered answer: its status (0 when the call failed) and body (or why
# it failed).
type Got is Data:
  Got{code: U32, body: String}

def Kubelet.Res(-A: Type) -> Type:
  Result<&1, &1, U32 & String, A>

def Kubelet.forever() -> Nat:
  U32.to_nat(4294967295)

def Kubelet.say(+s: String) -> IO(Unit):
  IO.print("kubelet-proxy: " ++ s)

# Configuration
# -------------

def Kubelet.Up.addr(u: Up) -> String:
  match u:
    case Up{a, p, n, ca, c, k, t, x}:
      a

def Kubelet.Up.hostport.go(empty: Bool, a: String, n: String, +p: U32) -> String:
  match empty:
    case True{}:
      a ++ ":" ++ U32.show(p)
    case False{}:
      n ++ ":" ++ U32.show(p)

def Kubelet.Up.hostport(u: Up) -> String:
  match u:
    case Up{a, p, +n, ca, c, k, t, x}:
      Kubelet.Up.hostport.go(String.is_empty(n), a, n, p)

def Kubelet.Up.token(u: Up) -> String:
  match u:
    case Up{a, p, n, ca, c, k, t, x}:
      t

def Kubelet.Up.extra(u: Up) -> String:
  match u:
    case Up{a, p, n, ca, c, k, t, x}:
      x

def Kubelet.KCfg.bind(c: KCfg) -> String:
  match c:
    case KCfg{b, p, ce, k, ca, vc, t, cur, h, v}:
      b

def Kubelet.KCfg.port(c: KCfg) -> U32:
  match c:
    case KCfg{b, p, ce, k, ca, vc, t, cur, h, v}:
      p

def Kubelet.KCfg.cert(c: KCfg) -> String:
  match c:
    case KCfg{b, p, ce, k, ca, vc, t, cur, h, v}:
      ce

def Kubelet.KCfg.key(c: KCfg) -> String:
  match c:
    case KCfg{b, p, ce, k, ca, vc, t, cur, h, v}:
      k

def Kubelet.KCfg.ca(c: KCfg) -> String:
  match c:
    case KCfg{b, p, ce, k, ca, vc, t, cur, h, v}:
      ca

def Kubelet.KCfg.vc(c: KCfg) -> String:
  match c:
    case KCfg{b, p, ce, k, ca, vc, t, cur, h, v}:
      vc

def Kubelet.KCfg.target(c: KCfg) -> String:
  match c:
    case KCfg{b, p, ce, k, ca, vc, t, cur, h, v}:
      t

def Kubelet.KCfg.current(c: KCfg) -> String:
  match c:
    case KCfg{b, p, ce, k, ca, vc, t, cur, h, v}:
      cur

def Kubelet.KCfg.host(c: KCfg) -> Up:
  match c:
    case KCfg{b, p, ce, k, ca, vc, t, cur, h, v}:
      h

def Kubelet.KCfg.virt(c: KCfg) -> Up:
  match c:
    case KCfg{b, p, ce, k, ca, vc, t, cur, h, v}:
      v

def Kubelet.port.of(m: Maybe<&2, U32>, +d: U32) -> U32:
  match m:
    case Some{p}:
      p
    case None{}:
      d

def Kubelet.num(+args: List<&2, String>, +name: String, +d: U32) -> U32:
  Kubelet.port.of(U32.read(K.Kubelet.opt(args, name, "")), d)

# The impersonation headers of the virtual API server's requests.
def Kubelet.remote() -> String:
  "X-Remote-User: vk8s:kubelet-proxy\r\nX-Remote-Group: system:masters\r\n"

def Kubelet.pki(+f: String) -> String:
  "/var/lib/vcluster/pki/" ++ f

# The flags of `vk8s kubelet-proxy` (defaults: the guest's PKI):
#   --bind=0.0.0.0 --port=10250
#   --cert=pki/kubelet-serving.crt --key=pki/kubelet-serving.key
#   --client-ca=pki/ca.crt
#   --vcluster=vk8s --target=<host namespace> --current=<host namespace>
#   --host=10.0.2.2 --host-port=443 --host-name= --host-ca= --host-cert=
#   --host-key= --host-token=
#   --virtual=127.0.0.1 --virtual-port=6443 --virtual-name=
#   --virtual-ca=pki/ca.crt --virtual-cert=pki/front-proxy-client.crt
#   --virtual-key=pki/front-proxy-client.key
def Kubelet.cfg(+args: List<&2, String>) -> KCfg:
  +target = K.Kubelet.opt(args, "target", "default")
  KCfg{K.Kubelet.opt(args, "bind", "0.0.0.0"), Kubelet.num(args, "port", 10250),
    K.Kubelet.opt(args, "cert", Kubelet.pki("kubelet-serving.crt")), K.Kubelet.opt(args, "key", Kubelet.pki("kubelet-serving.key")),
    K.Kubelet.opt(args, "client-ca", Kubelet.pki("ca.crt")),
    K.Kubelet.opt(args, "vcluster", "vk8s"), target, K.Kubelet.opt(args, "current", target),
    Up{K.Kubelet.opt(args, "host", "10.0.2.2"), Kubelet.num(args, "host-port", 443), K.Kubelet.opt(args, "host-name", ""),
      K.Kubelet.opt(args, "host-ca", ""), K.Kubelet.opt(args, "host-cert", ""), K.Kubelet.opt(args, "host-key", ""),
      K.Kubelet.opt(args, "host-token", ""), ""},
    Up{K.Kubelet.opt(args, "virtual", "127.0.0.1"), Kubelet.num(args, "virtual-port", 6443), K.Kubelet.opt(args, "virtual-name", ""),
      K.Kubelet.opt(args, "virtual-ca", Kubelet.pki("ca.crt")), K.Kubelet.opt(args, "virtual-cert", Kubelet.pki("front-proxy-client.crt")),
      K.Kubelet.opt(args, "virtual-key", Kubelet.pki("front-proxy-client.key")), "", Kubelet.remote()}}

# Calling API servers
# -------------------

def Kubelet.dial(u: Up) -> IO(Kubelet.Res(Socket)):
  match u:
    case Up{a, p, n, ca, c, k, t, x}:
      S.TlsSrv.connect(a, p, n, ca, c, k, 10000)

def Kubelet.decoded.go(r: Result<&2, &1, String, H.Head & String>) -> Got:
  match r:
    case Fail{e}:
      Got{0, e}
    case Done{(H.Head{st, reason, hs}, body)}:
      Got{st, body}

def Kubelet.decoded(chunks: List<&2, List<&2, U32>>) -> Got:
  Kubelet.decoded.go(H.Http.decode(List.concat(&2, U32, List.reverse(&2, List<&2, U32>, chunks))))

def Kubelet.fetch.got(r: Socket & Kubelet.Res(Maybe<&1, List<&2, U32>>), chunks: List<&2, List<&2, U32>>,
  again: (Socket & List<&2, List<&2, U32>>) -> IO(Got)) -> IO(Got):
  match r:
    case (s, Done{Some{bs}}):
      again((s, Con{bs, chunks}))
    case (s, Done{None{}}):
      do IO<Got>:
        S.TlsSrv.close(s)
        return Kubelet.decoded(chunks)
    case (s, Fail{(c, m)}):
      do IO<Got>:
        S.TlsSrv.close(s)
        return Got{0, m}

def Kubelet.fetch.stop(st: Socket & List<&2, List<&2, U32>>) -> IO(Got):
  match st:
    case (s, chunks):
      do IO<Got>:
        S.TlsSrv.close(s)
        return Kubelet.decoded(chunks)

# Reads an answer to the end of the connection (at most n reads).
def Kubelet.fetch.read(n: Nat, st: Socket & List<&2, List<&2, U32>>) -> IO(Got):
  match n:
    case 0n:
      Kubelet.fetch.stop(st)
    case 1n+p:
      (s, chunks) = st
      do IO<Got>:
        r : Socket & Kubelet.Res(Maybe<&1, List<&2, U32>>) <- S.TlsSrv.recv(s, 65536, 30000)
        Kubelet.fetch.got(r, chunks, q => Kubelet.fetch.read(p, q))

def Kubelet.fetch.sent(q: Socket & Kubelet.Res(Unit)) -> IO(Got):
  match q:
    case (s, Done{x}):
      Kubelet.fetch.read(U32.to_nat(512), (s, Nil{}))
    case (s, Fail{(c, m)}):
      do IO<Got>:
        S.TlsSrv.close(s)
        return Got{0, m}

def Kubelet.fetch.go(r: Kubelet.Res(Socket), head: String) -> IO(Got):
  match r:
    case Fail{(c, m)}:
      IO.pure(Got, Got{0, m})
    case Done{s}:
      do IO<Got>:
        q : Socket & Kubelet.Res(Unit) <- S.TlsSrv.send(s, head, 30000)
        Kubelet.fetch.sent(q)

# A GET, read whole (HTTP/1.1, chunked or not, decoded by bend-kube).
def Kubelet.fetch(+u: Up, path: String) -> IO(Got):
  do IO<Got>:
    r : Kubelet.Res(Socket) <- Kubelet.dial(u)
    Kubelet.fetch.go(r, K.Kubelet.get_head(path, Kubelet.Up.hostport(u), Kubelet.Up.token(u), Kubelet.Up.extra(u)))

def Kubelet.Got.code(g: Got) -> U32:
  match g:
    case Got{c, b}:
      c

def Kubelet.Got.body(g: Got) -> String:
  match g:
    case Got{c, b}:
      b

def Kubelet.zero.if(z: Bool) -> Maybe<&2, U32>:
  match z:
    case True{}:
      Some{502}
    case False{}:
      None{}

def Kubelet.zero(+c: U32) -> Maybe<&2, U32>:
  Kubelet.zero.if(U32.is_eq(c, 0))

# A failed call (status 0) answers 502.
def Kubelet.Got.status.of(+c: U32) -> U32:
  Kubelet.port.of(Kubelet.zero(c), c)

# Answering
# ---------

def Kubelet.end(q: Socket & Kubelet.Res(Unit)) -> IO(Unit):
  match q:
    case (s, r):
      S.TlsSrv.close(s)

# An answer of the proxy's own; the connection closes after it.
def Kubelet.answer(t: Socket, +code: U32, ctype: String, body: String) -> IO(Unit):
  do IO<Unit>:
    q : Socket & Kubelet.Res(Unit) <- S.TlsSrv.send(t, K.Kubelet.answer_text(code, ctype, body), 30000)
    Kubelet.end(q)

def Kubelet.unreachable(t: Socket, +m: String) -> IO(Unit):
  do IO<Unit>:
    Kubelet.say("host API server: " ++ m)
    Kubelet.answer(t, 502, K.Kubelet.text_type(), "kubelet-proxy: cannot reach the host API server: " ++ m)

def Kubelet.relay.splice(q: Socket & Kubelet.Res(Unit), t: Socket) -> IO(Unit):
  match q:
    case (u, r):
      S.TlsSrv.splice(t, u)

def Kubelet.relay.sent(q: Socket & Kubelet.Res(Unit), t: Socket, rest: List<&2, U32>) -> IO(Unit):
  match q:
    case (u, Done{x}):
      do IO<Unit>:
        q2 : Socket & Kubelet.Res(Unit) <- S.TlsSrv.send_bytes(u, rest, 30000)
        Kubelet.relay.splice(q2, t)
    case (u, Fail{(c, m)}):
      do IO<Unit>:
        S.TlsSrv.close(u)
        Kubelet.unreachable(t, m)

def Kubelet.relay.go(r: Kubelet.Res(Socket), t: Socket, head: String, rest: List<&2, U32>) -> IO(Unit):
  match r:
    case Fail{(c, m)}:
      Kubelet.unreachable(t, m)
    case Done{u}:
      do IO<Unit>:
        q : Socket & Kubelet.Res(Unit) <- S.TlsSrv.send(u, head, 30000)
        Kubelet.relay.sent(q, t, rest)

# Sends the request to the host API server, then relays both ways until
# either side closes.
def Kubelet.relay(t: Socket, method: String, target: String, +hs: List<&2, K.Hdr>, rest: List<&2, U32>, +c: KCfg) -> IO(Unit):
  do IO<Unit>:
    +u : Up = Kubelet.KCfg.host(c)
    r : Kubelet.Res(Socket) <- Kubelet.dial(u)
    Kubelet.relay.go(r, t, K.Kubelet.forward_head(method, target, Kubelet.Up.hostport(u), Kubelet.Up.token(u), hs), rest)

# An Answer step; anything else here is a fault of the proxy's.
def Kubelet.final.answer(s: K.Step, t: Socket) -> IO(Unit):
  match s:
    case K.Answer{code, ctype, body}:
      Kubelet.answer(t, code, ctype, body)
    case _:
      Kubelet.answer(t, 500, K.Kubelet.text_type(), "kubelet-proxy: unexpected step")

def Kubelet.stats(t: Socket, target: String, +c: KCfg) -> IO(Unit):
  do IO<Unit>:
    +g : Got <- Kubelet.fetch(Kubelet.KCfg.host(c), target)
    +pods : Got <- Kubelet.fetch(Kubelet.KCfg.virt(c), "/api/v1/pods")
    +pvcs : Got <- Kubelet.fetch(Kubelet.KCfg.virt(c), "/api/v1/persistentvolumeclaims")
    Kubelet.final.answer(K.Kubelet.stats_answer(Kubelet.Got.status.of(Kubelet.Got.code(g)), Kubelet.KCfg.vc(c), Kubelet.KCfg.target(c),
      Kubelet.Got.body(g), Kubelet.Got.body(pods), Kubelet.Got.body(pvcs)), t)

def Kubelet.podlist(t: Socket, +n: String, +c: KCfg) -> IO(Unit):
  do IO<Unit>:
    +g : Got <- Kubelet.fetch(Kubelet.KCfg.virt(c), "/api/v1/pods")
    Kubelet.final.answer(K.Kubelet.pods_answer(n, Kubelet.Got.body(g)), t)

# The last steps of a request: answer, relay, stats or pod list.
def Kubelet.final(s: K.Step, +hs: List<&2, K.Hdr>, rest: List<&2, U32>, t: Socket, +c: KCfg) -> IO(Unit):
  match s:
    case K.Answer{code, ctype, body}:
      Kubelet.answer(t, code, ctype, body)
    case K.Relay{m, target}:
      Kubelet.relay(t, m, target, hs, rest, c)
    case K.Stats{target}:
      Kubelet.stats(t, target, c)
    case K.PodList{n}:
      Kubelet.podlist(t, n, c)
    case _:
      Kubelet.answer(t, 500, K.Kubelet.text_type(), "kubelet-proxy: unexpected step")

def Kubelet.check(t: Socket, +ns: String, +pod: String, +ctr: String, method: String, target: String, +hs: List<&2, K.Hdr>,
  rest: List<&2, U32>, +c: KCfg) -> IO(Unit):
  do IO<Unit>:
    +g : Got <- Kubelet.fetch(Kubelet.KCfg.virt(c), "/api/v1/namespaces/" ++ ns ++ "/pods/" ++ pod)
    Kubelet.final(K.Kubelet.after_get(Kubelet.Got.code(g), Kubelet.Got.body(g), ctr, method, target), hs, rest, t, c)

def Kubelet.node(t: Socket, r: K.Route, q: List<&2, K.Q>, method: String, +hs: List<&2, K.Hdr>, rest: List<&2, U32>, +c: KCfg) -> IO(Unit):
  do IO<Unit>:
    +g : Got <- Kubelet.fetch(Kubelet.KCfg.virt(c), "/api/v1/nodes")
    +names : List<&2, String> = K.Kubelet.node_names(Kubelet.Got.code(g), Kubelet.Got.body(g))
    +m : Maybe<&2, String> = K.Kubelet.node_of(K.Kubelet.header("Host", hs), Kubelet.KCfg.vc(c), Kubelet.KCfg.current(c), names)
    Kubelet.final(K.Kubelet.node_step(m, r, q, method), hs, rest, t, c)

def Kubelet.step(s: K.Step, +hs: List<&2, K.Hdr>, rest: List<&2, U32>, t: Socket, +c: KCfg) -> IO(Unit):
  match s:
    case K.CheckPod{ns, pod, ctr, m, target}:
      Kubelet.check(t, ns, pod, ctr, m, target, hs, rest, c)
    case K.NodeStep{r, q, m}:
      Kubelet.node(t, r, q, m, hs, rest, c)
    case x:
      Kubelet.final(x, hs, rest, t, c)

# Reading the request
# -------------------

def Kubelet.request.go(m: Maybe<&2, K.Req>, rest: List<&2, U32>, t: Socket, +subj: T.Subject, +c: KCfg) -> IO(Unit):
  match m:
    case None{}:
      Kubelet.answer(t, 400, K.Kubelet.text_type(), "kubelet-proxy: bad request")
    case Some{K.Req{+method, +uri, +hs}}:
      do IO<Unit>:
        Kubelet.say(K.Kubelet.user(subj) ++ " " ++ method ++ " " ++ uri)
        Kubelet.step(K.Kubelet.decide(Kubelet.KCfg.vc(c), Kubelet.KCfg.target(c), subj, method, uri), hs, rest, t, c)

def Kubelet.request(hd: String & List<&2, U32>, t: Socket, +subj: T.Subject, +c: KCfg) -> IO(Unit):
  match hd:
    case (text, rest):
      Kubelet.request.go(K.Kubelet.Req.parse(text), rest, t, subj, c)

def Kubelet.read.more(done: Bool, t: Socket, +all: List<&2, U32>, +subj: T.Subject, +c: KCfg,
  again: (Socket & List<&2, U32>) -> IO(Unit)) -> IO(Unit):
  match done:
    case True{}:
      Kubelet.request(K.Kubelet.split_head(all), t, subj, c)
    case False{}:
      again((t, all))

def Kubelet.read.got(r: Socket & Kubelet.Res(Maybe<&1, List<&2, U32>>), acc: List<&2, U32>, +subj: T.Subject, +c: KCfg,
  again: (Socket & List<&2, U32>) -> IO(Unit)) -> IO(Unit):
  match r:
    case (t, Done{Some{bs}}):
      +all = List.append(&2, U32, acc, bs)
      Kubelet.read.more(K.Kubelet.head_end(all), t, all, subj, c, again)
    case (t, Done{None{}}):
      S.TlsSrv.close(t)
    case (t, Fail{e}):
      S.TlsSrv.close(t)

def Kubelet.read.stop(st: Socket & List<&2, U32>) -> IO(Unit):
  match st:
    case (t, acc):
      Kubelet.answer(t, 400, K.Kubelet.text_type(), "kubelet-proxy: request head too large")

# Reads up to the blank line that ends the request head (at most n reads).
def Kubelet.read(n: Nat, st: Socket & List<&2, U32>, +subj: T.Subject, +c: KCfg) -> IO(Unit):
  match n:
    case 0n:
      Kubelet.read.stop(st)
    case 1n+p:
      (t, acc) = st
      do IO<Unit>:
        r : Socket & Kubelet.Res(Maybe<&1, List<&2, U32>>) <- S.TlsSrv.recv(t, 16384, 30000)
        Kubelet.read.got(r, acc, subj, c, q => Kubelet.read(p, q, subj, c))

def Kubelet.who(p: Socket & Kubelet.Res(T.Subject), +c: KCfg) -> IO(Unit):
  match p:
    case (t, Done{subj}):
      Kubelet.read(U32.to_nat(16), (t, Nil{}), subj, c)
    case (t, Fail{e}):
      Kubelet.read(U32.to_nat(16), (t, Nil{}), T.Subject{"", []}, c)

def Kubelet.conn.go(r: Kubelet.Res(Socket), +c: KCfg) -> IO(Unit):
  match r:
    case Fail{(code, m)}:
      Kubelet.say("handshake: " ++ m)
    case Done{t}:
      do IO<Unit>:
        p : Socket & Kubelet.Res(T.Subject) <- S.TlsSrv.subject(t)
        Kubelet.who(p, c)

def Kubelet.conn(s: Socket, +c: KCfg) -> IO(Unit):
  do IO<Unit>:
    r : Kubelet.Res(Socket) <- S.TlsSrv.handshake(s, Kubelet.KCfg.cert(c), Kubelet.KCfg.key(c), Kubelet.KCfg.ca(c), 10000)
    Kubelet.conn.go(r, c)

# Serving
# -------

def Kubelet.got(r: Listener & Kubelet.Res(Socket), +c: KCfg, again: Listener -> IO(Unit)) -> IO(Unit):
  match r:
    case (l, Done{s}):
      do IO<Unit>:
        IO.spawn(Unit, Kubelet.conn(s, c))
        again(l)
    case (l, Fail{(code, m)}):
      do IO<Unit>:
        Kubelet.say("accept: " ++ m)
        again(l)

def Kubelet.loop(n: Nat, l: Listener, +c: KCfg) -> IO(Unit):
  match n:
    case 0n:
      Listener.close(l)
    case 1n+p:
      do IO<Unit>:
        r : Listener & Kubelet.Res(Socket) <- TCP.accept(l)
        Kubelet.got(r, c, l2 => Kubelet.loop(p, l2, c))

def Kubelet.serve.go(r: Kubelet.Res(Listener), +c: KCfg) -> IO(Unit):
  match r:
    case Done{l}:
      do IO<Unit>:
        Kubelet.say("listening on " ++ Kubelet.KCfg.bind(c) ++ ":" ++ U32.show(Kubelet.KCfg.port(c)) ++ " for vcluster "
          ++ Kubelet.KCfg.vc(c) ++ ", target namespace " ++ Kubelet.KCfg.target(c) ++ ", host API server "
          ++ Kubelet.Up.addr(Kubelet.KCfg.host(c)))
        Kubelet.loop(Kubelet.forever(), l, c)
    case Fail{(code, m)}:
      IO.print_err("kubelet-proxy: listen: " ++ m)

# The fake kubelet: serves until the process ends.
def Kubelet.serve(+c: KCfg) -> IO(Unit):
  do IO<Unit>:
    r : Kubelet.Res(Listener) <- S.TlsSrv.listen(Kubelet.KCfg.bind(c), Kubelet.KCfg.port(c))
    Kubelet.serve.go(r, c)
