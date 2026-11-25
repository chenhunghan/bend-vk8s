import Base
import bend-kube-runtime@0.11.0.0/src/net.bend as NT
import bend-kube-runtime@0.11.0.0/src/http.bend as HT
import bend-kube-runtime@0.11.0.0/src/sys.bend as SY
import ../../src/oci/upstream.bend as U
import ../../src/oci/auth.bend as A
import ../../src/oci/size.bend as N
import ../tls_server.bend as TS

# Registry client
# ===============
#
# The IO of src/oci/upstream.bend: a GET to a registry (or to the storage
# it redirects to) over TLS, with anonymous token auth and redirects.
# Every decision is src/oci's; this file dials, sends and reads. Used by
# the layer filler (host/layers/fill.bend) and the image cache's mirror
# (host/oci/mirror.bend), so the host, not a VM, reaches the registries.
#
# - The name lookup and the TCP connect are bend-kube-runtime's Tls.dial
#   (getaddrinfo, IPv4 or IPv6). The handshake is TlsSrv.secure
#   (host/effs/tls_server.c, the system's CA roots): its sessions are the
#   ones OciBlob's TLS hooks read, so a layer blob goes from the registry
#   socket to its file with no byte in the Bend heap (OciBlob.fetch).
#   bend-kube-runtime 0.10.0.0's own TLS sessions do not set those hooks.
# - Upc.fetch and Upc.doc: one request per connection (Connection:
#   close). The image cache's mirror uses a session instead (Upc.ses,
#   Upc.sfetch, below): kept connections and a token cache.
# - A 401 with a Bearer challenge gets one anonymous token (the realm must
#   be https and allowed for the registry, src/oci/auth.bend), then the
#   request is sent again with it; the token is handed back, so the next
#   request of the same pull sends it at once (the image cache's session
#   keeps it for every pull of the repository: Upc.sfetch). Redirects: at
#   most 10, https only, Authorization only to the same origin.
# - VK8S_UPC_TRACE=1 prints a line per step (dial, handshake, response
#   head, token) with its wall time in ms (Upc.trace).
# - VK8S_UPSTREAM (tests only) replaces every registry's base URL, for a
#   stub registry on 127.0.0.1 (with SSL_CERT_FILE naming its CA).

def Upc.R(-A: Type) -> Type:
  Result<&1, &1, String, A>

# A final answer: the Authorization it was sent with (send it again with
# the pull's next request), the URL that answered, its head, and the body
# bytes that came with the head.
type Resp is Data:
  Resp{auth: String, url: String, head: HT.Head, rest: List<&2, U32>}

def Resp.auth(r: Resp) -> String:
  match r:
    case Resp{a, u, h, b}:
      a

def Resp.url(r: Resp) -> String:
  match r:
    case Resp{a, u, h, b}:
      u

# Whether the answer is a 200, and the answer.
def Upc.ok(r: Resp) -> Bool & Resp:
  match r:
    case Resp{a, u, HT.Head{+st, why, hs}, b}:
      (U32.is_eq(st, 200), Resp{a, u, HT.Head{st, why, hs}, b})

def Upc.hdrs.put(hit: Bool, v: String, rest: List<&2, String>) -> List<&2, String>:
  match hit:
    case True{}:
      Con{v, rest}
    case False{}:
      rest

# Every value of the header name (lowercase), in order, trimmed
# (bend-kube-runtime's Http.parse_header keeps the space after the colon).
def Upc.hdrs(hs: List<&2, HT.Header>, +name: String) -> List<&2, String>:
  match hs:
    case Nil{}:
      Nil{}
    case Con{HT.Header{n, v}, t}:
      Upc.hdrs.put(String.eq(HT.Http.lower(n), name), String.trim(v), Upc.hdrs(t, name))

def Upc.len.of(m: Maybe<&2, String>, chunked: Bool) -> Maybe<&2, N.Size>:
  match m chunked:
    case Some{v} False{}:
      N.Size.read(String.trim(v))
    case _ _:
      None{}

def Upc.chunked(m: Maybe<&2, String>) -> Bool:
  match m:
    case Some{v}:
      String.contains(HT.Http.lower(v), "chunked")
    case None{}:
      False{}

# An answer's status, Content-Length (None when it has none or the body
# is chunked) and the body bytes that came with the head.
def Upc.parts(r: Resp) -> U32 & (Maybe<&2, N.Size> & List<&2, U32>):
  match r:
    case Resp{a, u, HT.Head{st, why, +hs}, b}:
      (st, (Upc.len.of(HT.Http.find(hs, "content-length"), Upc.chunked(HT.Http.find(hs, "transfer-encoding"))), b))

# An answer's Content-Type ("" when it has none).
def Upc.media(r: Resp) -> String:
  match r:
    case Resp{a, u, HT.Head{st, why, hs}, b}:
      String.trim(Maybe.default(&2, String, HT.Http.find(hs, "content-type"), ""))

# The Bearer challenge of a 401 whose realm is allowed for base, if any.
def Upc.challenge.of(st: U32, hs: List<&2, HT.Header>, +base: String) -> Maybe<&2, A.Bearer>:
  Bool.pick(Maybe<&2, A.Bearer>, U32.is_eq(st, 401), A.Auth.pick(base, Upc.hdrs(hs, "www-authenticate")), None{})

def Upc.challenge(r: Resp, +base: String) -> Maybe<&2, A.Bearer>:
  match r:
    case Resp{a, u, HT.Head{st, why, hs}, b}:
      Upc.challenge.of(st, hs, base)

def Resp.status(r: Resp) -> U32:
  match r:
    case Resp{a, u, HT.Head{st, why, hs}, b}:
      st

def Upc.forever() -> Nat:
  U32.to_nat(4294967295)

def Upc.why(+what: String, e: U32 & String) -> String:
  match e:
    case (c, m):
      what ++ ": " ++ m ++ " (errno " ++ U32.show(c) ++ ")"

def Upc.count(bs: List<&2, U32>, +n: U32) -> U32:
  match bs:
    case Nil{}:
      n
    case Con{b, t}:
      Upc.count(t, (n + 1 : U32))

def Upc.base.of(r: Result<&1, &1, U32 & String, String>, +reg: String) -> String:
  match r:
    case Done{SCon{c, t}}:
      SCon{c, t}
    case _:
      U.Up.base(reg)

# The base URL of registry's API: VK8S_UPSTREAM when set (tests), else
# containerd's default host (Up.base).
def Upc.base(+reg: String) -> IO(String):
  IO.bind(Result<&1, &1, U32 & String, String>, String, IO.get_env("VK8S_UPSTREAM"), r => IO.pure(String, Upc.base.of(r, reg)))

# Tracing (VK8S_UPC_TRACE=1): one line per step with its wall ms
# ----------------------------------------------------------------

def Upc.trace.on(r: Result<&1, &1, U32 & String, String>) -> Bool:
  match r:
    case Done{v}:
      String.eq(v, "1")
    case Fail{e}:
      False{}

def Upc.trace.say(on: Bool, +s: String) -> IO(Unit):
  match on:
    case True{}:
      IO.print("upc " ++ s)
    case False{}:
      IO.pure(Unit, Unit{})

def Upc.trace(+label: String, t0: Nat) -> IO(Unit):
  do IO<Unit>:
    +t1 : Nat <- IO.now()
    r : Result<&1, &1, U32 & String, String> <- IO.get_env("VK8S_UPC_TRACE")
    Upc.trace.say(Upc.trace.on(r), Nat.show(t1) ++ " " ++ label ++ " " ++ Nat.show(Nat.sub(t1, t0)) ++ "ms")

# Connecting
# ----------

def Upc.secured(r: TS.TlsSrv.Res(Socket), +host: String) -> Upc.R(Socket):
  match r:
    case Fail{e}:
      Fail{Upc.why("TLS with " ++ host, e)}
    case Done{s}:
      Done{s}

def Upc.dialed(r: NT.Res(Socket), +host: String) -> IO(Upc.R(Socket)):
  match r:
    case Fail{e}:
      IO.pure(Upc.R(Socket), Fail{Upc.why("connecting to " ++ host, e)})
    case Done{s}:
      do IO<Upc.R(Socket)>:
        t0 : Nat <- IO.now()
        t : TS.TlsSrv.Res(Socket) <- TS.TlsSrv.secure(s, host, 30000)
        Upc.trace("tls " ++ host, t0)
        return Upc.secured(t, host)

def Upc.connect.to(p: String & U32, ok: Bool, +url: String) -> IO(Upc.R(Socket)):
  match p ok:
    case (+h, n) True{}:
      do IO<Upc.R(Socket)>:
        t0 : Nat <- IO.now()
        d : NT.Res(Socket) <- NT.Tls.dial(h, n, 30000)
        Upc.trace("dial " ++ h, t0)
        Upc.dialed(d, h)
    case (h, n) False{}:
      IO.pure(Upc.R(Socket), Fail{"not an https URL: " ++ url})

# A verified TLS session to url's host.
def Upc.connect(+url: String) -> IO(Upc.R(Socket)):
  Upc.connect.to(U.Up.dial(url), U.Up.dialable(url), url)

# Response heads
# --------------

def Upc.parsed(m: Maybe<&2, HT.Head>, s: Socket, +body: List<&2, U32>, +host: String) -> IO(Socket & Upc.R(HT.Head & List<&2, U32>)):
  match m:
    case None{}:
      IO.pure(Socket & Upc.R(HT.Head & List<&2, U32>), (s, Fail{host ++ " sent a malformed response head"}))
    case Some{h}:
      IO.pure(Socket & Upc.R(HT.Head & List<&2, U32>), (s, Done{(h, body)}))

def Upc.head.big(big: Bool, s: Socket, h: List<&2, U32>, +host: String,
  again: Socket -> List<&2, U32> -> IO(Socket & Upc.R(HT.Head & List<&2, U32>))) -> IO(Socket & Upc.R(HT.Head & List<&2, U32>)):
  match big:
    case True{}:
      IO.pure(Socket & Upc.R(HT.Head & List<&2, U32>), (s, Fail{host ++ "'s response head passes 64 KiB"}))
    case False{}:
      again(s, h)

def Upc.head.cut(c: U.Cut, s: Socket, +host: String, again: Socket -> List<&2, U32> -> IO(Socket & Upc.R(HT.Head & List<&2, U32>))) ->
  IO(Socket & Upc.R(HT.Head & List<&2, U32>)):
  match c:
    case U.Cut{h, b, True{}}:
      Upc.parsed(HT.Http.parse_head(U.Up.text(h)), s, b, host)
    case U.Cut{+h, b, False{}}:
      Upc.head.big(U32.is_gt(Upc.count(h, 0), 65536), s, h, host, again)

def Upc.head.recv(p: Socket & TS.TlsSrv.Res(Maybe<&1, List<&2, U32>>), +acc: List<&2, U32>, +host: String,
  again: Socket -> List<&2, U32> -> IO(Socket & Upc.R(HT.Head & List<&2, U32>))) -> IO(Socket & Upc.R(HT.Head & List<&2, U32>)):
  match p:
    case (s, Fail{e}):
      IO.pure(Socket & Upc.R(HT.Head & List<&2, U32>), (s, Fail{Upc.why("reading from " ++ host, e)}))
    case (s, Done{None{}}):
      IO.pure(Socket & Upc.R(HT.Head & List<&2, U32>), (s, Fail{host ++ " closed the connection before its response"}))
    case (s, Done{Some{bs}}):
      Upc.head.cut(U.Up.cut(List.append(&2, U32, acc, bs)), s, host, again)

# Reads a response until its head ends: the head, and the body bytes that
# came with it.
def Upc.head(fuel: Nat, s: Socket, +acc: List<&2, U32>, +host: String) -> IO(Socket & Upc.R(HT.Head & List<&2, U32>)):
  match fuel:
    case 0n:
      IO.pure(Socket & Upc.R(HT.Head & List<&2, U32>), (s, Fail{host ++ "'s response head did not end"}))
    case 1n+k:
      do IO<Socket & Upc.R(HT.Head & List<&2, U32>)>:
        p : Socket & TS.TlsSrv.Res(Maybe<&1, List<&2, U32>>) <- TS.TlsSrv.recv(s, 65536, 60000)
        Upc.head.recv(p, acc, host, s2 => a2 => Upc.head(k, s2, a2, host))

def Upc.closed(-A: Type, s: Socket, +e: String) -> IO(Upc.R(A)):
  do IO<Upc.R(A)>:
    TS.TlsSrv.close(s)
    return Fail{e}

# One request
# -----------

def Upc.got(q: Socket & Upc.R(HT.Head & List<&2, U32>), +auth: String, +url: String) -> IO(Upc.R(Socket & Resp)):
  match q:
    case (s, Fail{e}):
      Upc.closed(Socket & Resp, s, e)
    case (s, Done{(h, b)}):
      IO.pure(Upc.R(Socket & Resp), Done{(s, Resp{auth, url, h, b})})

def Upc.sent(p: Socket & TS.TlsSrv.Res(Unit), +auth: String, +url: String, +host: String) -> IO(Upc.R(Socket & Resp)):
  match p:
    case (s, Fail{e}):
      Upc.closed(Socket & Resp, s, Upc.why("sending to " ++ host, e))
    case (s, Done{u}):
      IO.bind(Socket & Upc.R(HT.Head & List<&2, U32>), Upc.R(Socket & Resp), Upc.head(Upc.forever(), s, Nil{}, host),
        q => Upc.got(q, auth, url))

def Upc.st.of(r: Upc.R(Socket & Resp)) -> U32 & Upc.R(Socket & Resp):
  match r:
    case Done{(s, Resp{a, u, HT.Head{+st, why, hs}, b})}:
      (st, Done{(s, Resp{a, u, HT.Head{st, why, hs}, b})})
    case Fail{e}:
      (0, Fail{e})

def Upc.st.say(p: U32 & Upc.R(Socket & Resp), +url: String, t0: Nat) -> IO(Upc.R(Socket & Resp)):
  match p:
    case (st, r):
      do IO<Upc.R(Socket & Resp)>:
        Upc.trace("head " ++ U32.show(st) ++ " " ++ String.take(url, 90n), t0)
        return r

# Sends the request text req (a GET of url with auth) on the session r,
# then reads the response head.
def Upc.open.req(r: Upc.R(Socket), +url: String, +req: String, +auth: String) -> IO(Upc.R(Socket & Resp)):
  match r:
    case Fail{e}:
      IO.pure(Upc.R(Socket & Resp), Fail{e})
    case Done{s}:
      do IO<Upc.R(Socket & Resp)>:
        t0 : Nat <- IO.now()
        p : Socket & TS.TlsSrv.Res(Unit) <- TS.TlsSrv.send(s, req, 60000)
        r : Upc.R(Socket & Resp) <- Upc.sent(p, auth, url, U.Up.dial.host(url))
        Upc.st.say(Upc.st.of(r), url, t0)

def Upc.open.conn(r: Upc.R(Socket), +url: String, +accept: String, +auth: String) -> IO(Upc.R(Socket & Resp)):
  Upc.open.req(r, url, U.Up.request(url, accept, auth), auth)

# GET url once: the session and the response head.
def Upc.open(+url: String, +accept: String, +auth: String) -> IO(Upc.R(Socket & Resp)):
  IO.bind(Upc.R(Socket), Upc.R(Socket & Resp), Upc.connect(url), r => Upc.open.conn(r, url, accept, auth))

# Bodies
# ------

def Upc.body.recv(p: Socket & TS.TlsSrv.Res(Maybe<&1, List<&2, U32>>), r: HT.Resp, +n: U32, +host: String,
  again: Socket -> HT.Resp -> U32 -> IO(Socket & Upc.R(List<&2, U32>))) -> IO(Socket & Upc.R(List<&2, U32>)):
  match p:
    case (s, Fail{e}):
      IO.pure(Socket & Upc.R(List<&2, U32>), (s, Fail{Upc.why("reading from " ++ host, e)}))
    case (s, Done{None{}}):
      again(s, HT.Http.eof(r), n)
    case (s, Done{Some{+bs}}):
      again(s, HT.Http.feed(bs, r), (n + Upc.count(bs, 0) : U32))

def Upc.body.take(rb: HT.Resp & List<&2, U32>) -> List<&2, U32>:
  match rb:
    case (r, bs):
      bs

def Upc.body.err(m: Maybe<&2, String>, +host: String) -> String:
  match m:
    case Some{e}:
      host ++ " sent a broken body: " ++ e
    case None{}:
      host ++ " closed the connection before the body's end"

def Upc.body.big(big: Bool, s: Socket, r: HT.Resp, +cap: U32, +host: String, more: Socket -> HT.Resp -> IO(Socket & Upc.R(List<&2, U32>))) ->
  IO(Socket & Upc.R(List<&2, U32>)):
  match big:
    case True{}:
      IO.pure(Socket & Upc.R(List<&2, U32>), (s, Fail{host ++ "'s body is larger than " ++ U32.show((cap / 1024 : U32)) ++ " KiB"}))
    case False{}:
      more(s, r)

def Upc.body.more(r: HT.Resp, s: Socket, +n: U32, +cap: U32, +host: String, more: Socket -> HT.Resp -> IO(Socket & Upc.R(List<&2, U32>))) ->
  IO(Socket & Upc.R(List<&2, U32>)):
  match r:
    case HT.Resp{HT.PDone{}, h, out}:
      IO.pure(Socket & Upc.R(List<&2, U32>), (s, Done{Upc.body.take(HT.Http.take(HT.Resp{HT.PDone{}, h, out}))}))
    case HT.Resp{HT.PErr{e}, h, out}:
      IO.pure(Socket & Upc.R(List<&2, U32>), (s, Fail{Upc.body.err(Some{e}, host)}))
    case HT.Resp{HT.PLost{e}, h, out}:
      IO.pure(Socket & Upc.R(List<&2, U32>), (s, Fail{Upc.body.err(Some{e}, host)}))
    case HT.Resp{p, h, out}:
      Upc.body.big(U32.is_gt(n, cap), s, HT.Resp{p, h, out}, cap, host, more)

# Reads a body (Content-Length, chunked, or until the close) of at most
# cap bytes, decoded.
def Upc.body(fuel: Nat, s: Socket, r: HT.Resp, +n: U32, +cap: U32, +host: String) -> IO(Socket & Upc.R(List<&2, U32>)):
  match fuel:
    case 0n:
      IO.pure(Socket & Upc.R(List<&2, U32>), (s, Fail{host ++ "'s body did not end"}))
    case 1n+k:
      Upc.body.more(r, s, n, cap, host,
        s2 => r2 => IO.bind(Socket & TS.TlsSrv.Res(Maybe<&1, List<&2, U32>>), Socket & Upc.R(List<&2, U32>), TS.TlsSrv.recv(s2, 65536, 60000),
          p => Upc.body.recv(p, r2, n, host, s3 => r3 => n3 => Upc.body(k, s3, r3, n3, cap, host))))

def Upc.body.start(+h: HT.Head, rest: List<&2, U32>) -> HT.Resp:
  HT.Http.feed(rest, HT.Resp{HT.Http.framing(h), Some{h}, Nil{}})

def Upc.read.end(q: Socket & Upc.R(List<&2, U32>)) -> IO(Upc.R(List<&2, U32>)):
  match q:
    case (s, r):
      do IO<Upc.R(List<&2, U32>)>:
        TS.TlsSrv.close(s)
        return r

# The whole body of an answer (at most cap bytes); closes the session.
def Upc.read(p: Socket & Resp, +cap: U32) -> IO(Upc.R(List<&2, U32>)):
  match p:
    case (s, Resp{a, +u, h, +b}):
      IO.bind(Socket & Upc.R(List<&2, U32>), Upc.R(List<&2, U32>),
        Upc.body(Upc.forever(), s, Upc.body.start(h, b), Upc.count(b, 0), cap, U.Up.dial.host(u)), q => Upc.read.end(q))

# Tokens
# ------

def Upc.token.of(m: Maybe<&2, A.Token>) -> Upc.R(String):
  match m:
    case None{}:
      Fail{"the token response has no token"}
    case Some{A.Token{t, e}}:
      Done{U.Up.bearer_auth(t)}

def Upc.token.body(r: Upc.R(List<&2, U32>)) -> Upc.R(String):
  match r:
    case Fail{e}:
      Fail{"fetching a token: " ++ e}
    case Done{bs}:
      Upc.token.of(A.Auth.token(U.Up.text(bs)))

def Upc.token.ok(p: Bool & Resp, s: Socket) -> IO(Upc.R(String)):
  match p:
    case (True{}, r):
      IO.bind(Upc.R(List<&2, U32>), Upc.R(String), Upc.read((s, r), 65536), b => IO.pure(Upc.R(String), Upc.token.body(b)))
    case (False{}, r):
      Upc.closed(String, s, "the token service answered HTTP " ++ U32.show(Resp.status(r)))

def Upc.token.got(r: Upc.R(Socket & Resp)) -> IO(Upc.R(String)):
  match r:
    case Fail{e}:
      IO.pure(Upc.R(String), Fail{"fetching a token: " ++ e})
    case Done{(s, x)}:
      Upc.token.ok(Upc.ok(x), s)

# An anonymous token for a challenge: the Authorization header to send.
def Upc.token(b: A.Bearer) -> IO(Upc.R(String)):
  do IO<Upc.R(String)>:
    t0 : Nat <- IO.now()
    r : Upc.R(Socket & Resp) <- Upc.open(A.Auth.token_url(b), "application/json", "")
    t : Upc.R(String) <- Upc.token.got(r)
    Upc.trace("token total", t0)
    return t

# GET with auth and redirects
# ---------------------------

def Upc.next(r: Resp, +hops: U32, tried: Bool) -> U.Next & Resp:
  match r:
    case Resp{a, +u, HT.Head{+st, why, +hs}, b}:
      (U.Up.next(st, u, hops, tried, String.trim(Maybe.default(&2, String, HT.Http.find(hs, "location"), "")), Upc.hdrs(hs, "www-authenticate")),
        Resp{a, u, HT.Head{st, why, hs}, b})

def Upc.retoken(t: Upc.R(String), again: String -> IO(Upc.R(Socket & Resp))) -> IO(Upc.R(Socket & Resp)):
  match t:
    case Fail{e}:
      IO.pure(Upc.R(Socket & Resp), Fail{e})
    case Done{a}:
      again(a)

def Upc.keep(keep: Bool, +auth: String) -> String:
  match keep:
    case True{}:
      auth
    case False{}:
      ""

def Upc.step(n: U.Next & Resp, s: Socket, +auth: String, +repo: String,
  token: String -> IO(Upc.R(Socket & Resp)), hop: String -> String -> IO(Upc.R(Socket & Resp))) -> IO(Upc.R(Socket & Resp)):
  match n:
    case (U.Final{}, r):
      IO.pure(Upc.R(Socket & Resp), Done{(s, r)})
    case (U.Token{b}, r):
      do IO<Upc.R(Socket & Resp)>:
        TS.TlsSrv.close(s)
        t : Upc.R(String) <- Upc.token(U.Up.scoped(b, repo))
        Upc.retoken(t, token)
    case (U.Hop{u, keep}, r):
      do IO<Upc.R(Socket & Resp)>:
        TS.TlsSrv.close(s)
        hop(u, Upc.keep(keep, auth))
    case (U.Stop{w}, r):
      Upc.closed(Socket & Resp, s, w)

def Upc.get.opened(r: Upc.R(Socket & Resp), +hops: U32, +tried: Bool, +auth: String, +repo: String,
  token: String -> IO(Upc.R(Socket & Resp)), hop: String -> String -> IO(Upc.R(Socket & Resp))) -> IO(Upc.R(Socket & Resp)):
  match r:
    case Fail{e}:
      IO.pure(Upc.R(Socket & Resp), Fail{e})
    case Done{(s, x)}:
      Upc.step(Upc.next(x, hops, tried), s, auth, repo, token, hop)

# GET url for repo with auth ("" for none): a 401 gets one anonymous
# token and the request again; redirects are followed. The answer's
# status may be anything but a redirect; the caller reads or closes it.
def Upc.get(fuel: Nat, +url: String, +accept: String, +auth: String, +tried: Bool, +hops: U32, +repo: String) -> IO(Upc.R(Socket & Resp)):
  match fuel:
    case 0n:
      IO.pure(Upc.R(Socket & Resp), Fail{"too many redirects or token rounds for " ++ url})
    case 1n+(+k):
      IO.bind(Upc.R(Socket & Resp), Upc.R(Socket & Resp), Upc.open(url, accept, auth),
        r => Upc.get.opened(r, hops, tried, auth, repo,
          a => Upc.get(k, url, accept, a, True{}, hops, repo),
          u => a => Upc.get(k, u, accept, a, tried, (hops + 1 : U32), repo)))

# GET url of repo: the session and the final answer's head.
def Upc.fetch(+url: String, +accept: String, +auth: String, +repo: String) -> IO(Upc.R(Socket & Resp)):
  Upc.get(14n, url, accept, auth, False{}, 0, repo)

def Upc.doc.with(+auth: String, r: Upc.R(List<&2, U32>)) -> Upc.R(String & List<&2, U32>):
  match r:
    case Fail{e}:
      Fail{e}
    case Done{bs}:
      Done{(auth, bs)}

def Upc.doc.read(s: Socket, r: Resp, +cap: U32) -> IO(Upc.R(String & List<&2, U32>)):
  match r:
    case Resp{+a, u, h, b}:
      IO.bind(Upc.R(List<&2, U32>), Upc.R(String & List<&2, U32>), Upc.read((s, Resp{a, u, h, b}), cap),
        bs => IO.pure(Upc.R(String & List<&2, U32>), Upc.doc.with(a, bs)))

def Upc.doc.ok(p: Bool & Resp, s: Socket, +cap: U32) -> IO(Upc.R(String & List<&2, U32>)):
  match p:
    case (True{}, r):
      Upc.doc.read(s, r, cap)
    case (False{}, +r):
      Upc.closed(String & List<&2, U32>, s, U.Up.dial.host(Resp.url(r)) ++ " answered HTTP " ++ U32.show(Resp.status(r)))

def Upc.doc.got(r: Upc.R(Socket & Resp), +cap: U32) -> IO(Upc.R(String & List<&2, U32>)):
  match r:
    case Fail{e}:
      IO.pure(Upc.R(String & List<&2, U32>), Fail{e})
    case Done{(s, x)}:
      Upc.doc.ok(Upc.ok(x), s, cap)

# GET a document of repo (a manifest, a config, at most cap bytes): the
# Authorization to send with the pull's next request, and its bytes. Any
# answer but 200 fails with its status.
def Upc.doc(+url: String, +accept: String, +auth: String, +repo: String, +cap: U32) -> IO(Upc.R(String & List<&2, U32>)):
  IO.bind(Upc.R(Socket & Resp), Upc.R(String & List<&2, U32>), Upc.fetch(url, accept, auth, repo), r => Upc.doc.got(r, cap))

# The session: kept connections and the token cache (feat/fast-cold-pull)
# -----------------------------------------------------------------------
#
# The image cache (host/cache/mirror.bend) starts one session per
# process (Upc.ses.new) and fetches through it (Upc.sfetch), from every
# port's fills at once. A session is one computation that owns:
#
# - idle TLS connections, by host and port (U.Up.pool.key): a request
#   takes one when there is one (else it dials), sends a keep-alive GET
#   (U.Up.request.keep) and, once the response is read to its end and
#   allows it (U.Up.keep), puts the connection back. One idle for
#   U.Up.pool.idle seconds is closed; at most U.Up.pool.max are kept per
#   host. A request on a kept connection that fails before its response
#   head (the server closed it meanwhile) is sent again on a new one.
# - the token cache (src/oci/auth.bend Auth.cache): each token a 401 got,
#   under the origin of the request and the token's scopes, until shortly
#   before it expires. A pull's request looks its token up first
#   (U.Up.pull_scopes) and sends it at once; a 401 still gets one fresh
#   token (and replaces the cached one), as before.
#
# Nothing else changes: the realm must be allowed for the registry
# (Auth.pick), redirects are https only and keep Authorization only on
# the same origin (Auth.redirect), and every byte is still checked
# against its digest by the caller before it is served or kept.

type UIdle is Type:
  UIdle{key: String, sock: Socket, at: U32}

type UReq is Type:
  # an idle connection to key, if the session has one
  UTake{key: String, back: Chan(Maybe<&1, Socket>)}
  # a connection to key, free for the next request
  UPut{key: String, sock: Socket}
  # the cached Authorization under key ("" when none)
  UAuth{key: String, back: Chan(String)}
  # a token to cache under key until until
  UToken{key: String, auth: String, until: U32}

def Upc.now.of(w: U32 & (U32 & U32)) -> U32:
  match w:
    case (d, (s, us)):
      ((d * 86400 : U32) + s : U32)

# The wall clock, in seconds since 1970.
def Upc.now() -> IO(U32):
  do IO<U32>:
    w : U32 & (U32 & U32) <- SY.Sys.wall()
    return Upc.now.of(w)

def Upc.idle.cons(u: UIdle, p: Maybe<&1, Socket> & List<&1, UIdle>) -> Maybe<&1, Socket> & List<&1, UIdle>:
  match p:
    case (m, rest):
      (m, Con{u, rest})

def Upc.idle.at(fresh: Bool, hit: Bool, u: UIdle, t: List<&1, UIdle>, again: List<&1, UIdle> -> IO(Maybe<&1, Socket> & List<&1, UIdle>)) ->
  IO(Maybe<&1, Socket> & List<&1, UIdle>):
  match fresh hit u:
    case False{} _ UIdle{k, s, a}:
      do IO<Maybe<&1, Socket> & List<&1, UIdle>>:
        TS.TlsSrv.close(s)
        again(t)
    case True{} True{} UIdle{k, s, a}:
      IO.pure(Maybe<&1, Socket> & List<&1, UIdle>, (Some{s}, t))
    case True{} False{} x:
      IO.bind(Maybe<&1, Socket> & List<&1, UIdle>, Maybe<&1, Socket> & List<&1, UIdle>, again(t),
        p => IO.pure(Maybe<&1, Socket> & List<&1, UIdle>, Upc.idle.cons(x, p)))

def Upc.idle.facts(u: UIdle, +key: String, +now: U32) -> Bool & (Bool & UIdle):
  match u:
    case UIdle{+k, s, +a}:
      (U.Up.pool.fresh(a, now), (String.eq(k, key), UIdle{k, s, a}))

def Upc.idle.go(f: Bool & (Bool & UIdle), t: List<&1, UIdle>, again: List<&1, UIdle> -> IO(Maybe<&1, Socket> & List<&1, UIdle>)) ->
  IO(Maybe<&1, Socket> & List<&1, UIdle>):
  match f:
    case (fresh, (hit, u)):
      Upc.idle.at(fresh, hit, u, t, again)

# An idle connection to key, taken out of xs, and the rest; on the way,
# the stale ones are closed (fuel: one step a connection).
def Upc.idle.take(fuel: Nat, xs: List<&1, UIdle>, +key: String, +now: U32) -> IO(Maybe<&1, Socket> & List<&1, UIdle>):
  match fuel xs:
    case _ Nil{}:
      IO.pure(Maybe<&1, Socket> & List<&1, UIdle>, (None{}, Nil{}))
    case 0n Con{u, t}:
      IO.pure(Maybe<&1, Socket> & List<&1, UIdle>, (None{}, Con{u, t}))
    case 1n+k Con{u, t}:
      Upc.idle.go(Upc.idle.facts(u, key, now), t, t2 => Upc.idle.take(k, t2, key, now))

def Upc.idle.keep.cons(u: UIdle, p: U32 & List<&1, UIdle>, +add: U32) -> U32 & List<&1, UIdle>:
  match p:
    case (n, rest):
      ((n + add : U32), Con{u, rest})

def Upc.idle.keep.at(fresh: Bool, hit: Bool, u: UIdle, rest: IO(U32 & List<&1, UIdle>)) -> IO(U32 & List<&1, UIdle>):
  match fresh u:
    case False{} UIdle{k, s, a}:
      do IO<U32 & List<&1, UIdle>>:
        TS.TlsSrv.close(s)
        rest
    case True{} x:
      IO.bind(U32 & List<&1, UIdle>, U32 & List<&1, UIdle>, rest,
        p => IO.pure(U32 & List<&1, UIdle>, Upc.idle.keep.cons(x, p, Bool.to_u32(hit))))

def Upc.idle.keep.go(f: Bool & (Bool & UIdle), rest: IO(U32 & List<&1, UIdle>)) -> IO(U32 & List<&1, UIdle>):
  match f:
    case (fresh, (hit, u)):
      Upc.idle.keep.at(fresh, hit, u, rest)

# xs without its stale connections (closed), and how many are to key.
def Upc.idle.keep(xs: List<&1, UIdle>, +key: String, +now: U32) -> IO(U32 & List<&1, UIdle>):
  match xs:
    case Nil{}:
      IO.pure(U32 & List<&1, UIdle>, (0, Nil{}))
    case Con{u, t}:
      Upc.idle.keep.go(Upc.idle.facts(u, key, now), Upc.idle.keep(t, key, now))

def Upc.idle.put.at(room: Bool, xs: List<&1, UIdle>, +key: String, s: Socket, +now: U32) -> IO(List<&1, UIdle>):
  match room:
    case True{}:
      IO.pure(List<&1, UIdle>, Con{UIdle{key, s, now}, xs})
    case False{}:
      do IO<List<&1, UIdle>>:
        TS.TlsSrv.close(s)
        return xs

def Upc.idle.put.go(p: U32 & List<&1, UIdle>, +key: String, s: Socket, +now: U32) -> IO(List<&1, UIdle>):
  match p:
    case (n, xs):
      Upc.idle.put.at(U32.is_lt(n, U.Up.pool.max()), xs, key, s, now)

# xs with s kept as idle to key (closed instead when key has its
# U.Up.pool.max already).
def Upc.idle.put(xs: List<&1, UIdle>, +key: String, s: Socket, +now: U32) -> IO(List<&1, UIdle>):
  IO.bind(U32 & List<&1, UIdle>, List<&1, UIdle>, Upc.idle.keep(xs, key, now), p => Upc.idle.put.go(p, key, s, now))

def Upc.ses.took(p: Maybe<&1, Socket> & List<&1, UIdle>, back: Chan(Maybe<&1, Socket>), toks: List<&2, A.Cached>,
  again: List<&1, UIdle> -> List<&2, A.Cached> -> IO(Unit)) -> IO(Unit):
  match p:
    case (m, rest):
      do IO<Unit>:
        _ : Result<&1, &1, Maybe<&1, Socket>, Unit> <- Chan.send(Maybe<&1, Socket>, back, m)
        again(rest, toks)

def Upc.ses.on(m: Maybe<&1, UReq>, idle: List<&1, UIdle>, +toks: List<&2, A.Cached>, +now: U32,
  again: List<&1, UIdle> -> List<&2, A.Cached> -> IO(Unit)) -> IO(Unit):
  match m:
    case None{}:
      IO.pure(Unit, Unit{})
    case Some{UTake{+key, back}}:
      IO.bind(Maybe<&1, Socket> & List<&1, UIdle>, Unit, Upc.idle.take(Upc.forever(), idle, key, now), p => Upc.ses.took(p, back, toks, again))
    case Some{UPut{+key, s}}:
      IO.bind(List<&1, UIdle>, Unit, Upc.idle.put(idle, key, s, now), xs => again(xs, toks))
    case Some{UAuth{+key, back}}:
      do IO<Unit>:
        _ : Result<&1, &1, String, Unit> <- Chan.send(String, back, A.Auth.cache.find(toks, key, now))
        again(idle, toks)
    case Some{UToken{+key, +auth, +until}}:
      again(idle, A.Auth.cache.put(toks, key, auth, until, now))

def Upc.ses.loop(n: Nat, +inbox: Chan(UReq), idle: List<&1, UIdle>, toks: List<&2, A.Cached>) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+k:
      do IO<Unit>:
        m : Maybe<&1, UReq> <- Chan.recv(UReq, inbox)
        +now : U32 <- Upc.now()
        Upc.ses.on(m, idle, toks, now, i2 => t2 => Upc.ses.loop(k, inbox, i2, t2))

# A new session, running until the process ends. A program that must
# end by itself (every computation done) does not start one.
def Upc.ses.new() -> IO(Chan(UReq)):
  do IO<Chan(UReq)>:
    +inbox : Chan(UReq) <- Chan.new(UReq, 4096)
    IO.spawn(Unit, Upc.ses.loop(Upc.forever(), inbox, Nil{}, Nil{}))
    return inbox

def Upc.ses.flat(m: Maybe<&1, Maybe<&1, Socket>>) -> Maybe<&1, Socket>:
  match m:
    case Some{x}:
      x
    case None{}:
      None{}

# An idle connection to key from the session, if it has one.
def Upc.take(+ses: Chan(UReq), +key: String) -> IO(Maybe<&1, Socket>):
  do IO<Maybe<&1, Socket>>:
    +back : Chan(Maybe<&1, Socket>) <- Chan.new(Maybe<&1, Socket>, 1)
    _ : Result<&1, &1, UReq, Unit> <- Chan.send(UReq, ses, UTake{key, back})
    m : Maybe<&1, Maybe<&1, Socket>> <- Chan.recv(Maybe<&1, Socket>, back)
    return Upc.ses.flat(m)

def Upc.put.sent(r: Result<&1, &1, UReq, Unit>) -> IO(Unit):
  match r:
    case Done{u}:
      IO.pure(Unit, Unit{})
    case Fail{UPut{k, s}}:
      TS.TlsSrv.close(s)
    case Fail{x}:
      IO.pure(Unit, Unit{})

# s, free for the next request to key, back to the session.
def Upc.put(+ses: Chan(UReq), +key: String, s: Socket) -> IO(Unit):
  IO.bind(Result<&1, &1, UReq, Unit>, Unit, Chan.send(UReq, ses, UPut{key, s}), r => Upc.put.sent(r))

def Upc.auth.got(m: Maybe<&1, String>) -> String:
  match m:
    case Some{a}:
      a
    case None{}:
      ""

# The cached Authorization under key ("" when none).
def Upc.auth(+ses: Chan(UReq), +key: String) -> IO(String):
  do IO<String>:
    +back : Chan(String) <- Chan.new(String, 1)
    _ : Result<&1, &1, UReq, Unit> <- Chan.send(UReq, ses, UAuth{key, back})
    m : Maybe<&1, String> <- Chan.recv(String, back)
    return Upc.auth.got(m)

# Requests on a session
# ---------------------

def Upc.sopen.retry(r: Upc.R(Socket & Resp), +url: String, +accept: String, +auth: String) -> IO(Upc.R(Socket & Resp)):
  match r:
    case Done{x}:
      IO.pure(Upc.R(Socket & Resp), Done{x})
    case Fail{e}:
      do IO<Upc.R(Socket & Resp)>:
        Upc.trace("kept connection failed (" ++ e ++ "), again on a new one", 0n)
        c : Upc.R(Socket) <- Upc.connect(url)
        Upc.open.req(c, url, U.Up.request.keep(url, accept, auth), auth)

def Upc.sopen.with(m: Maybe<&1, Socket>, +url: String, +accept: String, +auth: String) -> IO(Upc.R(Socket & Resp)):
  match m:
    case None{}:
      IO.bind(Upc.R(Socket), Upc.R(Socket & Resp), Upc.connect(url), c => Upc.open.req(c, url, U.Up.request.keep(url, accept, auth), auth))
    case Some{s}:
      IO.bind(Upc.R(Socket & Resp), Upc.R(Socket & Resp), Upc.open.req(Done{s}, url, U.Up.request.keep(url, accept, auth), auth),
        r => Upc.sopen.retry(r, url, accept, auth))

# GET url once on a kept connection (or a new one): the session and the
# response head.
def Upc.sopen(+ses: Chan(UReq), +url: String, +accept: String, +auth: String) -> IO(Upc.R(Socket & Resp)):
  IO.bind(Maybe<&1, Socket>, Upc.R(Socket & Resp), Upc.take(ses, U.Up.pool.key(url)), m => Upc.sopen.with(m, url, accept, auth))

def Upc.framed(+hs: List<&2, HT.Header>) -> Bool:
  Maybe.is_some(&2, String, HT.Http.find(hs, "content-length")) || Upc.chunked(HT.Http.find(hs, "transfer-encoding"))

# Whether the connection of answer r may carry the next request once its
# body is read to its end (U.Up.keep), and r.
def Upc.reuse(r: Resp) -> Bool & Resp:
  match r:
    case Resp{a, u, HT.Head{st, why, +hs}, b}:
      (U.Up.keep(String.join(Upc.hdrs(hs, "connection"), ","), Upc.framed(hs)), Resp{a, u, HT.Head{st, why, hs}, b})

# After a response read to its end: its connection back to the session
# when it may carry another request (keep), else closed.
def Upc.done(keep: Bool, +ses: Chan(UReq), +key: String, s: Socket) -> IO(Unit):
  match keep:
    case True{}:
      Upc.put(ses, key, s)
    case False{}:
      TS.TlsSrv.close(s)

def Upc.drain.end(q: Socket & Upc.R(List<&2, U32>), keep: Bool, +ses: Chan(UReq), +key: String) -> IO(Upc.R(List<&2, U32>)):
  match q:
    case (s, Done{bs}):
      do IO<Upc.R(List<&2, U32>)>:
        Upc.done(keep, ses, key, s)
        return Done{bs}
    case (s, Fail{e}):
      do IO<Upc.R(List<&2, U32>)>:
        TS.TlsSrv.close(s)
        return Fail{e}

def Upc.drain.go(q: Bool & Resp, s: Socket, +ses: Chan(UReq), +cap: U32) -> IO(Upc.R(List<&2, U32>)):
  match q:
    case (keep, Resp{a, +u, +h, +b}):
      IO.bind(Socket & Upc.R(List<&2, U32>), Upc.R(List<&2, U32>),
        Upc.body(Upc.forever(), s, Upc.body.start(h, b), Upc.count(b, 0), cap, U.Up.dial.host(u)),
        q2 => Upc.drain.end(q2, keep, ses, U.Up.pool.key(u)))

# The whole body of an answer (at most cap bytes); then its connection
# goes back to the session when it may carry another request, else it
# is closed.
def Upc.drain(+ses: Chan(UReq), p: Socket & Resp, +cap: U32) -> IO(Upc.R(List<&2, U32>)):
  match p:
    case (s, r):
      Upc.drain.go(Upc.reuse(r), s, ses, cap)

def Upc.stoken.of(m: Maybe<&2, A.Token>, +ses: Chan(UReq), +key: String, +sent: U32) -> IO(Upc.R(String)):
  match m:
    case None{}:
      IO.pure(Upc.R(String), Fail{"the token response has no token"})
    case Some{A.Token{+t, +e}}:
      do IO<Upc.R(String)>:
        _ : Result<&1, &1, UReq, Unit> <- Chan.send(UReq, ses, UToken{key, U.Up.bearer_auth(t), A.Auth.cache.until(sent, e)})
        return Done{U.Up.bearer_auth(t)}

def Upc.stoken.body(r: Upc.R(List<&2, U32>), +ses: Chan(UReq), +key: String, +sent: U32) -> IO(Upc.R(String)):
  match r:
    case Fail{e}:
      IO.pure(Upc.R(String), Fail{"fetching a token: " ++ e})
    case Done{bs}:
      Upc.stoken.of(A.Auth.token(U.Up.text(bs)), ses, key, sent)

def Upc.stoken.ok(p: Bool & Resp, s: Socket, +ses: Chan(UReq), +key: String, +sent: U32) -> IO(Upc.R(String)):
  match p:
    case (True{}, r):
      IO.bind(Upc.R(List<&2, U32>), Upc.R(String), Upc.drain(ses, (s, r), 65536), b => Upc.stoken.body(b, ses, key, sent))
    case (False{}, r):
      Upc.closed(String, s, "the token service answered HTTP " ++ U32.show(Resp.status(r)))

def Upc.stoken.got(r: Upc.R(Socket & Resp), +ses: Chan(UReq), +key: String, +sent: U32) -> IO(Upc.R(String)):
  match r:
    case Fail{e}:
      IO.pure(Upc.R(String), Fail{"fetching a token: " ++ e})
    case Done{(s, x)}:
      Upc.stoken.ok(Upc.ok(x), s, ses, key, sent)

# An anonymous token for a challenge, through the session; cached under
# key (Auth.cache.until, from when it was asked for). The Authorization
# header to send.
def Upc.stoken(+ses: Chan(UReq), b: A.Bearer, +key: String) -> IO(Upc.R(String)):
  do IO<Upc.R(String)>:
    +sent : U32 <- Upc.now()
    t0 : Nat <- IO.now()
    r : Upc.R(Socket & Resp) <- Upc.sopen(ses, A.Auth.token_url(b), "application/json", "")
    t : Upc.R(String) <- Upc.stoken.got(r, ses, key, sent)
    Upc.trace("token total", t0)
    return t

def Upc.sstep(n: U.Next & Resp, s: Socket, +ses: Chan(UReq), +auth: String, +repo: String, +url: String,
  token: String -> IO(Upc.R(Socket & Resp)), hop: String -> String -> IO(Upc.R(Socket & Resp))) -> IO(Upc.R(Socket & Resp)):
  match n:
    case (U.Final{}, r):
      IO.pure(Upc.R(Socket & Resp), Done{(s, r)})
    case (U.Token{+b}, r):
      do IO<Upc.R(Socket & Resp)>:
        _ : Upc.R(List<&2, U32>) <- Upc.drain(ses, (s, r), 65536)
        t : Upc.R(String) <- Upc.stoken(ses, U.Up.scoped(b, repo), U.Up.cache_key(url, b, repo))
        Upc.retoken(t, token)
    case (U.Hop{u, keep}, r):
      do IO<Upc.R(Socket & Resp)>:
        _ : Upc.R(List<&2, U32>) <- Upc.drain(ses, (s, r), 65536)
        hop(u, Upc.keep(keep, auth))
    case (U.Stop{w}, r):
      Upc.closed(Socket & Resp, s, w)

def Upc.sget.opened(r: Upc.R(Socket & Resp), +ses: Chan(UReq), +hops: U32, +tried: Bool, +auth: String, +repo: String, +url: String,
  token: String -> IO(Upc.R(Socket & Resp)), hop: String -> String -> IO(Upc.R(Socket & Resp))) -> IO(Upc.R(Socket & Resp)):
  match r:
    case Fail{e}:
      IO.pure(Upc.R(Socket & Resp), Fail{e})
    case Done{(s, x)}:
      Upc.sstep(Upc.next(x, hops, tried), s, ses, auth, repo, url, token, hop)

# Upc.get through the session.
def Upc.sget(+ses: Chan(UReq), fuel: Nat, +url: String, +accept: String, +auth: String, +tried: Bool, +hops: U32, +repo: String) ->
  IO(Upc.R(Socket & Resp)):
  match fuel:
    case 0n:
      IO.pure(Upc.R(Socket & Resp), Fail{"too many redirects or token rounds for " ++ url})
    case 1n+(+k):
      IO.bind(Upc.R(Socket & Resp), Upc.R(Socket & Resp), Upc.sopen(ses, url, accept, auth),
        r => Upc.sget.opened(r, ses, hops, tried, auth, repo, url,
          a => Upc.sget(ses, k, url, accept, a, True{}, hops, repo),
          u => a => Upc.sget(ses, k, u, accept, a, tried, (hops + 1 : U32), repo)))

# GET url of repo through the session: the pull's cached token sent at
# once when there is one. The session and the final answer's head; the
# caller reads its body, then gives the connection back with Upc.done
# (Upc.reuse says whether it may carry another request) or closes it.
def Upc.sfetch(+ses: Chan(UReq), +url: String, +accept: String, +repo: String) -> IO(Upc.R(Socket & Resp)):
  do IO<Upc.R(Socket & Resp)>:
    +a : String <- Upc.auth(ses, A.Auth.cache.key(url, U.Up.pull_scopes(repo)))
    Upc.sget(ses, 14n, url, accept, a, False{}, 0, repo)
