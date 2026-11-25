import Base
import bend-kube-runtime@0.11.0.0/src/json.bend as J
import bend-kube-runtime@0.11.0.0/src/sys.bend as Y
import ../src/net/kubelet.bend as K
import ../src/standalone/join.bend as JN
import ../src/guest/plan.bend as P
import ./kubelet_proxy.bend as KP
import ./tls_server.bend as S

# The standalone /node/join server (vk8s design,
# docs/ref/standalone-decisions.md J1; vcluster's handler is closed
# source). Every decision is src/standalone/join.bend's
# (Join.lookup, Join.respond, Join.render); this file only moves bytes.
#
# A connection: the TLS handshake asks for no client certificate (a
# joining machine has none; the token is its credential); one HTTP/1.1
# request head is read (K.Kubelet.head_end, K.Kubelet.Req.parse). For a
# GET whose token is well formed, the token's Secret is read from the
# local API server with the front-proxy client certificate as the user
# P.Plan.join_server_user(), without groups: a Role lets that user get
# Secrets in kube-system and nothing else (P.Plan.join_server_role). The
# answer is Join.render(Join.respond(...)) with the CA PEM, the kubeadm
# endpoint and the wall clock; then the connection closes. Each
# connection runs in its own IO.spawn.
#
# The log names the method, the path (never the query, which holds the
# token) and the status.
#
# `vk8s join-server --flag=value ...` (host/init.bend) runs it; the
# standalone plan starts it as a daemon (P.Plan.join_server). See
# JoinSrv.cfg for the flags.

def JoinSrv.Res(-A: Type) -> Type:
  Result<&1, &1, U32 & String, A>

# The server: where it listens, its serving certificate and key, the CA
# PEM file whose hash the script carries, the kubeadm endpoint the script
# joins (host:port), and the API server that holds the token Secrets.
type JCfg is Data:
  JCfg{bind: String, port: U32, cert: String, key: String, ca: String, endpoint: String, api: KP.Up}

def JoinSrv.forever() -> Nat:
  U32.to_nat(4294967295)

def JoinSrv.say(+s: String) -> IO(Unit):
  IO.print("join-server: " ++ s)

# Configuration
# -------------

def JoinSrv.JCfg.bind(c: JCfg) -> String:
  match c:
    case JCfg{b, p, ce, k, ca, e, a}:
      b

def JoinSrv.JCfg.port(c: JCfg) -> U32:
  match c:
    case JCfg{b, p, ce, k, ca, e, a}:
      p

def JoinSrv.JCfg.cert(c: JCfg) -> String:
  match c:
    case JCfg{b, p, ce, k, ca, e, a}:
      ce

def JoinSrv.JCfg.key(c: JCfg) -> String:
  match c:
    case JCfg{b, p, ce, k, ca, e, a}:
      k

def JoinSrv.JCfg.ca(c: JCfg) -> String:
  match c:
    case JCfg{b, p, ce, k, ca, e, a}:
      ca

def JoinSrv.JCfg.endpoint(c: JCfg) -> String:
  match c:
    case JCfg{b, p, ce, k, ca, e, a}:
      e

def JoinSrv.JCfg.api(c: JCfg) -> KP.Up:
  match c:
    case JCfg{b, p, ce, k, ca, e, a}:
      a

# The requestheader identity of the API server's requests: a user and no
# X-Remote-Group, so not system:masters.
def JoinSrv.remote() -> String:
  "X-Remote-User: " ++ P.Plan.join_server_user() ++ "\r\n"

# The flags of `vk8s join-server` (defaults: the guest's PKI):
#   --bind=0.0.0.0 --port=8443
#   --cert=pki/apiserver.crt --key=pki/apiserver.key
#   --ca=pki/ca.crt (the CA whose hash the script carries)
#   --endpoint=10.10.0.2:6443 (kubeadm's controlPlaneEndpoint)
#   --api=127.0.0.1 --api-port=6443 --api-name= --api-ca=pki/ca.crt
#   --api-cert=pki/front-proxy-client.crt --api-key=pki/front-proxy-client.key
def JoinSrv.cfg(+args: List<&2, String>) -> JCfg:
  JCfg{K.Kubelet.opt(args, "bind", "0.0.0.0"), KP.Kubelet.num(args, "port", 8443),
    K.Kubelet.opt(args, "cert", KP.Kubelet.pki("apiserver.crt")), K.Kubelet.opt(args, "key", KP.Kubelet.pki("apiserver.key")),
    K.Kubelet.opt(args, "ca", KP.Kubelet.pki("ca.crt")), K.Kubelet.opt(args, "endpoint", "10.10.0.2:6443"),
    KP.Up{K.Kubelet.opt(args, "api", "127.0.0.1"), KP.Kubelet.num(args, "api-port", 6443), K.Kubelet.opt(args, "api-name", ""),
      K.Kubelet.opt(args, "api-ca", KP.Kubelet.pki("ca.crt")), K.Kubelet.opt(args, "api-cert", KP.Kubelet.pki("front-proxy-client.crt")),
      K.Kubelet.opt(args, "api-key", KP.Kubelet.pki("front-proxy-client.key")), "", JoinSrv.remote()}}

# Inputs
# ------

def JoinSrv.slurp.close(p: File & Result<&1, &1, U32 & String, String>) -> IO(String):
  match p:
    case (f, Done{s}):
      do IO<String>:
        File.close(f)
        return s
    case (f, Fail{e}):
      do IO<String>:
        File.close(f)
        return ""

def JoinSrv.slurp.go(r: Result<&1, &1, U32 & String, File>) -> IO(String):
  match r:
    case Fail{e}:
      IO.pure(String, "")
    case Done{f}:
      do IO<String>:
        p : File & Result<&1, &1, U32 & String, String> <- File.read(f, 1048576)
        JoinSrv.slurp.close(p)

# A file's text, "" when it cannot be read (the CA then gives a 500 with
# Join.ca_hash's message). Read per request: a CA rotation needs no
# restart.
def JoinSrv.slurp(+path: String) -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    JoinSrv.slurp.go(r)

# The wall clock (days since 1970-01-01, (second of the day, us)) as a
# Join.Time.
def JoinSrv.now(w: U32 & (U32 & U32)) -> JN.Join.Time:
  match w:
    case (d, (s, us)):
      JN.Join.time_of_unix(((d * 86400 : U32) + s : U32))

# The Secret a request names: only a GET reaches the lookup (any other
# method is answered without one), and Join.lookup gives None for a
# malformed token.
def JoinSrv.secret_of(r: JN.Join.Req) -> Maybe<&2, String>:
  match r:
    case JN.ReqOk{q}:
      JN.Join.lookup(q)
    case JN.ReqErr{code, msg}:
      None{}

def JoinSrv.wanted(get: Bool, uri: String) -> Maybe<&2, String>:
  match get:
    case True{}:
      JoinSrv.secret_of(JN.Join.parse_request(uri))
    case False{}:
      None{}

def JoinSrv.parsed(r: Result<&2, &2, String, J.Json>) -> Maybe<&2, J.Json>:
  match r:
    case Fail{e}:
      None{}
    case Done{x}:
      Some{x}

# The Secret as the API server gave it: 200 and its JSON, else not found
# (404, or 403 before the Role exists, or no answer).
def JoinSrv.found(ok: Bool, body: String) -> Maybe<&2, J.Json>:
  match ok:
    case True{}:
      JoinSrv.parsed(J.Json.parse(body))
    case False{}:
      None{}

def JoinSrv.note.if(quiet: Bool, +code: U32, body: String) -> IO(Unit):
  match quiet:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      JoinSrv.say("API server answered " ++ U32.show(code) ++ " for a token Secret: " ++ String.take(body, 200n))

# Anything but 200 or 404 from the API server is worth a log line (403:
# the Role is missing; 0: the API server is down).
def JoinSrv.note(+code: U32, body: String) -> IO(Unit):
  JoinSrv.note.if(Bool.or(U32.is_eq(code, 200), U32.is_eq(code, 404)), code, body)

# Answering
# ---------

def JoinSrv.end(q: Socket & JoinSrv.Res(Unit)) -> IO(Unit):
  match q:
    case (s, r):
      S.TlsSrv.close(s)

def JoinSrv.send(t: Socket, r: JN.Join.Reply) -> IO(Unit):
  do IO<Unit>:
    q : Socket & JoinSrv.Res(Unit) <- S.TlsSrv.send(t, JN.Join.render(r), 30000)
    JoinSrv.end(q)

def JoinSrv.code(r: JN.Join.Reply) -> U32:
  match r:
    case JN.Reply{c, t, b}:
      c

# The path of a request target, without its query.
def JoinSrv.path(target: String) -> String:
  JN.Join.cut_before(JN.Join.cut(target, 63))

# A native cluster's join server (VK8S_JOIN_INSTALL=1, set by its systemd
# unit) answers with the installing script (JN.Join.install_reply): real
# Linux nodes get the node bundle and its units, not only kubeadm.
def JoinSrv.installing(r: Result<&1, &1, U32 & String, String>) -> Bool:
  match r:
    case Fail{e}:
      False{}
    case Done{v}:
      String.eq(v, "1")

def JoinSrv.install(install: Bool, r: JN.Join.Reply) -> JN.Join.Reply:
  match install:
    case True{}:
      JN.Join.install_reply(r)
    case False{}:
      r

def JoinSrv.reply(t: Socket, +method: String, +target: String, found: Maybe<&2, J.Json>, +c: JCfg) -> IO(Unit):
  do IO<Unit>:
    ca : String <- JoinSrv.slurp(JoinSrv.JCfg.ca(c))
    w : U32 & (U32 & U32) <- Y.Sys.wall()
    ie : Result<&1, &1, U32 & String, String> <- IO.get_env("VK8S_JOIN_INSTALL")
    +r : JN.Join.Reply = JoinSrv.install(JoinSrv.installing(ie), JN.Join.respond(method, target, found, ca, JoinSrv.JCfg.endpoint(c), JoinSrv.now(w)))
    JoinSrv.say(method ++ " " ++ JoinSrv.path(target) ++ " " ++ U32.show(JoinSrv.code(r)))
    JoinSrv.send(t, r)

def JoinSrv.lookup(m: Maybe<&2, String>, t: Socket, +method: String, +target: String, +c: JCfg) -> IO(Unit):
  match m:
    case None{}:
      JoinSrv.reply(t, method, target, None{}, c)
    case Some{name}:
      do IO<Unit>:
        +g : KP.Got <- KP.Kubelet.fetch(JoinSrv.JCfg.api(c), "/api/v1/namespaces/kube-system/secrets/" ++ name)
        JoinSrv.note(KP.Kubelet.Got.code(g), KP.Kubelet.Got.body(g))
        JoinSrv.reply(t, method, target, JoinSrv.found(U32.is_eq(KP.Kubelet.Got.code(g), 200), KP.Kubelet.Got.body(g)), c)

# Reading the request
# -------------------

def JoinSrv.request.go(m: Maybe<&2, K.Req>, t: Socket, +c: JCfg) -> IO(Unit):
  match m:
    case None{}:
      JoinSrv.send(t, JN.Join.fail(400, "bad request"))
    case Some{K.Req{+method, +uri, hs}}:
      JoinSrv.lookup(JoinSrv.wanted(String.eq(method, "GET"), uri), t, method, uri, c)

def JoinSrv.request(hd: String & List<&2, U32>, t: Socket, +c: JCfg) -> IO(Unit):
  match hd:
    case (text, rest):
      JoinSrv.request.go(K.Kubelet.Req.parse(text), t, c)

def JoinSrv.read.more(done: Bool, t: Socket, +all: List<&2, U32>, +c: JCfg,
  again: (Socket & List<&2, U32>) -> IO(Unit)) -> IO(Unit):
  match done:
    case True{}:
      JoinSrv.request(K.Kubelet.split_head(all), t, c)
    case False{}:
      again((t, all))

def JoinSrv.read.got(r: Socket & JoinSrv.Res(Maybe<&1, List<&2, U32>>), acc: List<&2, U32>, +c: JCfg,
  again: (Socket & List<&2, U32>) -> IO(Unit)) -> IO(Unit):
  match r:
    case (t, Done{Some{bs}}):
      +all = List.append(&2, U32, acc, bs)
      JoinSrv.read.more(K.Kubelet.head_end(all), t, all, c, again)
    case (t, Done{None{}}):
      S.TlsSrv.close(t)
    case (t, Fail{e}):
      S.TlsSrv.close(t)

def JoinSrv.read.stop(st: Socket & List<&2, U32>) -> IO(Unit):
  match st:
    case (t, acc):
      JoinSrv.send(t, JN.Join.fail(400, "request head too large"))

# Reads up to the blank line that ends the request head (at most n reads).
def JoinSrv.read(n: Nat, st: Socket & List<&2, U32>, +c: JCfg) -> IO(Unit):
  match n:
    case 0n:
      JoinSrv.read.stop(st)
    case 1n+p:
      (t, acc) = st
      do IO<Unit>:
        r : Socket & JoinSrv.Res(Maybe<&1, List<&2, U32>>) <- S.TlsSrv.recv(t, 16384, 30000)
        JoinSrv.read.got(r, acc, c, q => JoinSrv.read(p, q, c))

def JoinSrv.conn.go(r: JoinSrv.Res(Socket), +c: JCfg) -> IO(Unit):
  match r:
    case Fail{(code, m)}:
      JoinSrv.say("handshake: " ++ m)
    case Done{t}:
      JoinSrv.read(U32.to_nat(16), (t, Nil{}), c)

# No client certificate is asked for (ca "").
def JoinSrv.conn(s: Socket, +c: JCfg) -> IO(Unit):
  do IO<Unit>:
    r : JoinSrv.Res(Socket) <- S.TlsSrv.handshake(s, JoinSrv.JCfg.cert(c), JoinSrv.JCfg.key(c), "", 10000)
    JoinSrv.conn.go(r, c)

# Serving
# -------

def JoinSrv.got(r: Listener & JoinSrv.Res(Socket), +c: JCfg, again: Listener -> IO(Unit)) -> IO(Unit):
  match r:
    case (l, Done{s}):
      do IO<Unit>:
        IO.spawn(Unit, JoinSrv.conn(s, c))
        again(l)
    case (l, Fail{(code, m)}):
      do IO<Unit>:
        JoinSrv.say("accept: " ++ m)
        again(l)

def JoinSrv.loop(n: Nat, l: Listener, +c: JCfg) -> IO(Unit):
  match n:
    case 0n:
      Listener.close(l)
    case 1n+p:
      do IO<Unit>:
        r : Listener & JoinSrv.Res(Socket) <- TCP.accept(l)
        JoinSrv.got(r, c, l2 => JoinSrv.loop(p, l2, c))

def JoinSrv.serve.go(r: JoinSrv.Res(Listener), +c: JCfg) -> IO(Unit):
  match r:
    case Done{l}:
      do IO<Unit>:
        JoinSrv.say("listening on " ++ JoinSrv.JCfg.bind(c) ++ ":" ++ U32.show(JoinSrv.JCfg.port(c)) ++ ", joining nodes to "
          ++ JoinSrv.JCfg.endpoint(c) ++ ", token Secrets from " ++ KP.Kubelet.Up.hostport(JoinSrv.JCfg.api(c)))
        JoinSrv.loop(JoinSrv.forever(), l, c)
    case Fail{(code, m)}:
      IO.print_err("join-server: listen: " ++ m)

# The join server: serves until the process ends.
def JoinSrv.serve(+c: JCfg) -> IO(Unit):
  do IO<Unit>:
    r : JoinSrv.Res(Listener) <- S.TlsSrv.listen(JoinSrv.JCfg.bind(c), JoinSrv.JCfg.port(c))
    JoinSrv.serve.go(r, c)
