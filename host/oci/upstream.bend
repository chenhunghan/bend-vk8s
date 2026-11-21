import Base
import bend-kube-runtime@0.10.0.0/src/net.bend as NT
import bend-kube-runtime@0.10.0.0/src/http.bend as HT
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
# - One request per connection (Connection: close).
# - A 401 with a Bearer challenge gets one anonymous token (the realm must
#   be https and allowed for the registry, src/oci/auth.bend), then the
#   request is sent again with it; the token is handed back, so the next
#   request of the same pull sends it at once. Redirects: at most 10,
#   https only, Authorization only to the same origin.
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
      IO.bind(TS.TlsSrv.Res(Socket), Upc.R(Socket), TS.TlsSrv.secure(s, host, 30000), t => IO.pure(Upc.R(Socket), Upc.secured(t, host)))

def Upc.connect.to(p: String & U32, ok: Bool, +url: String) -> IO(Upc.R(Socket)):
  match p ok:
    case (+h, n) True{}:
      IO.bind(NT.Res(Socket), Upc.R(Socket), NT.Tls.dial(h, n, 30000), d => Upc.dialed(d, h))
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

def Upc.open.conn(r: Upc.R(Socket), +url: String, +accept: String, +auth: String) -> IO(Upc.R(Socket & Resp)):
  match r:
    case Fail{e}:
      IO.pure(Upc.R(Socket & Resp), Fail{e})
    case Done{s}:
      IO.bind(Socket & TS.TlsSrv.Res(Unit), Upc.R(Socket & Resp), TS.TlsSrv.send(s, U.Up.request(url, accept, auth), 60000),
        p => Upc.sent(p, auth, url, U.Up.dial.host(url)))

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
  IO.bind(Upc.R(Socket & Resp), Upc.R(String), Upc.open(A.Auth.token_url(b), "application/json", ""), r => Upc.token.got(r))

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
