import Base
import bend-kube-runtime@0.11.0.0/src/http.bend as HT
import ../../src/oci/upstream.bend as U
import ./upstream.bend as UP

# Image cache client (plain HTTP)
# ===============================
#
# The IO of the plain side of src/oci/upstream.bend: a GET to the host's
# image cache (`vk8s cache serve`, host/cache/mirror.bend) on 127.0.0.1,
# over plain TCP, beside the TLS registry client of host/oci/upstream.bend.
# No TLS, no token, no redirect: the cache does the registry's auth and
# fills each object once (it follows a fill in progress for every client),
# and Up.via sends any answer but a 200 back to the caller, which then
# asks the registry itself. Used by the layer filler (host/layers/fill.bend,
# Lf.src and the v4 defs).
#
# - Up.plain.dialable: http to 127.0.0.1 only; Base's TCP.connect dials.
# - One request per connection (Connection: close), as the cache serves.
# - An answer is a UP.Resp (auth ""), so UP.Upc.parts and UP.Upc.media
#   read it, and OciBlob.fetch takes its socket (a plain socket is one
#   of the two kinds it reads). TlsSrv.close ends a plain socket too (an
#   fd with no TLS session is closed, host/effs/tls_server.c tsv_end), so
#   the filler's blob code closes either kind the same way.

def Plc.R(-A: Type) -> Type:
  UP.Upc.R(A)

def Plc.why(+what: String, e: U32 & String) -> String:
  UP.Upc.why(what, e)

def Plc.closed(-A: Type, s: Socket, +e: String) -> IO(Plc.R(A)):
  do IO<Plc.R(A)>:
    Socket.close(s)
    return Fail{e}

# Connecting
# ----------

def Plc.dialed(r: Result<&1, &1, U32 & String, Socket>, +host: String) -> Plc.R(Socket):
  match r:
    case Fail{e}:
      Fail{Plc.why("connecting to the image cache on " ++ host, e)}
    case Done{s}:
      Done{s}

def Plc.connect.to(p: String & U32, ok: Bool, +url: String) -> IO(Plc.R(Socket)):
  match p ok:
    case (+h, +n) True{}:
      IO.bind(Result<&1, &1, U32 & String, Socket>, Plc.R(Socket), TCP.connect(h, n),
        r => IO.pure(Plc.R(Socket), Plc.dialed(r, h ++ ":" ++ U32.show(n))))
    case (h, n) False{}:
      IO.pure(Plc.R(Socket), Fail{"not an http URL on 127.0.0.1: " ++ url})

# A TCP connection to url's host and port (Up.plain.dialable).
def Plc.connect(+url: String) -> IO(Plc.R(Socket)):
  Plc.connect.to(U.Up.dial(url), U.Up.plain.dialable(url), url)

# Reading
# -------

# One read of at most 64 KiB within ms: Some{bytes}, None{} once the
# peer closed, or why not.
def Plc.got(p: Socket & Poll<&1, &1, Result<&1, &1, U32 & String, Maybe<&1, List<&2, U32>>>, Unit>) ->
  Socket & Plc.R(Maybe<&2, List<&2, U32>>):
  match p:
    case (s, Ready{Done{Some{bs}}}):
      (s, Done{Some{bs}})
    case (s, Ready{Done{None{}}}):
      (s, Done{None{}})
    case (s, Ready{Fail{e}}):
      (s, Fail{Plc.why("reading from the image cache", e)})
    case (s, Wait{u}):
      (s, Fail{"the image cache sent nothing for 60 s"})

def Plc.recv(s: Socket) -> IO(Socket & Plc.R(Maybe<&2, List<&2, U32>>)):
  IO.bind(Socket & Poll<&1, &1, Result<&1, &1, U32 & String, Maybe<&1, List<&2, U32>>>, Unit>, Socket & Plc.R(Maybe<&2, List<&2, U32>>),
    TCP.try_recv_bytes(s, 65536, 60000), p => IO.pure(Socket & Plc.R(Maybe<&2, List<&2, U32>>), Plc.got(p)))

# Response heads
# --------------

def Plc.parsed(m: Maybe<&2, HT.Head>, +body: List<&2, U32>) -> Plc.R(HT.Head & List<&2, U32>):
  match m:
    case None{}:
      Fail{"the image cache sent a malformed response head"}
    case Some{h}:
      Done{(h, body)}

def Plc.head.big(big: Bool, s: Socket, h: List<&2, U32>, again: Socket -> List<&2, U32> -> IO(Socket & Plc.R(HT.Head & List<&2, U32>))) ->
  IO(Socket & Plc.R(HT.Head & List<&2, U32>)):
  match big:
    case True{}:
      IO.pure(Socket & Plc.R(HT.Head & List<&2, U32>), (s, Fail{"the image cache's response head passes 64 KiB"}))
    case False{}:
      again(s, h)

def Plc.head.cut(c: U.Cut, s: Socket, again: Socket -> List<&2, U32> -> IO(Socket & Plc.R(HT.Head & List<&2, U32>))) ->
  IO(Socket & Plc.R(HT.Head & List<&2, U32>)):
  match c:
    case U.Cut{h, b, True{}}:
      IO.pure(Socket & Plc.R(HT.Head & List<&2, U32>), (s, Plc.parsed(HT.Http.parse_head(U.Up.text(h)), b)))
    case U.Cut{+h, b, False{}}:
      Plc.head.big(U32.is_gt(UP.Upc.count(h, 0), 65536), s, h, again)

def Plc.head.recv(p: Socket & Plc.R(Maybe<&2, List<&2, U32>>), +acc: List<&2, U32>,
  again: Socket -> List<&2, U32> -> IO(Socket & Plc.R(HT.Head & List<&2, U32>))) -> IO(Socket & Plc.R(HT.Head & List<&2, U32>)):
  match p:
    case (s, Fail{e}):
      IO.pure(Socket & Plc.R(HT.Head & List<&2, U32>), (s, Fail{e}))
    case (s, Done{None{}}):
      IO.pure(Socket & Plc.R(HT.Head & List<&2, U32>), (s, Fail{"the image cache closed the connection before its response"}))
    case (s, Done{Some{bs}}):
      Plc.head.cut(U.Up.cut(List.append(&2, U32, acc, bs)), s, again)

# Reads a response until its head ends: the head, and the body bytes that
# came with it.
def Plc.head(fuel: Nat, s: Socket, +acc: List<&2, U32>) -> IO(Socket & Plc.R(HT.Head & List<&2, U32>)):
  match fuel:
    case 0n:
      IO.pure(Socket & Plc.R(HT.Head & List<&2, U32>), (s, Fail{"the image cache's response head did not end"}))
    case 1n+k:
      IO.bind(Socket & Plc.R(Maybe<&2, List<&2, U32>>), Socket & Plc.R(HT.Head & List<&2, U32>), Plc.recv(s),
        p => Plc.head.recv(p, acc, s2 => a2 => Plc.head(k, s2, a2)))

# One request
# -----------

def Plc.answered(q: Socket & Plc.R(HT.Head & List<&2, U32>), +url: String) -> IO(Plc.R(Socket & UP.Resp)):
  match q:
    case (s, Fail{e}):
      Plc.closed(Socket & UP.Resp, s, e)
    case (s, Done{(h, b)}):
      IO.pure(Plc.R(Socket & UP.Resp), Done{(s, UP.Resp{"", url, h, b})})

def Plc.sent(q: Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit>, +url: String) -> IO(Plc.R(Socket & UP.Resp)):
  match q:
    case (s, Fail{(e, rest)}):
      Plc.closed(Socket & UP.Resp, s, Plc.why("sending to the image cache", e))
    case (s, Done{u}):
      IO.bind(Socket & Plc.R(HT.Head & List<&2, U32>), Plc.R(Socket & UP.Resp), Plc.head(UP.Upc.forever(), s, Nil{}), h => Plc.answered(h, url))

def Plc.open.conn(r: Plc.R(Socket), +url: String, +accept: String) -> IO(Plc.R(Socket & UP.Resp)):
  match r:
    case Fail{e}:
      IO.pure(Plc.R(Socket & UP.Resp), Fail{e})
    case Done{s}:
      IO.bind(Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit>, Plc.R(Socket & UP.Resp), TCP.send(s, U.Up.request(url, accept, "")),
        q => Plc.sent(q, url))

# GET url once: the connection and the response head, whatever its
# status.
def Plc.open(+url: String, +accept: String) -> IO(Plc.R(Socket & UP.Resp)):
  IO.bind(Plc.R(Socket), Plc.R(Socket & UP.Resp), Plc.connect(url), r => Plc.open.conn(r, url, accept))

def Plc.take(v: U.Via, s: Socket, r: UP.Resp) -> IO(Plc.R(Socket & UP.Resp)):
  match v:
    case U.Take{}:
      IO.pure(Plc.R(Socket & UP.Resp), Done{(s, r)})
    case U.Around{w}:
      Plc.closed(Socket & UP.Resp, s, w)

# An answer's status, and the answer.
def Plc.status(r: UP.Resp) -> U32 & UP.Resp:
  match r:
    case UP.Resp{a, u, HT.Head{+st, why, hs}, b}:
      (st, UP.Resp{a, u, HT.Head{st, why, hs}, b})

def Plc.take.st(p: U32 & UP.Resp, s: Socket) -> IO(Plc.R(Socket & UP.Resp)):
  match p:
    case (st, r):
      Plc.take(U.Up.via(st), s, r)

def Plc.fetch.got(r: Plc.R(Socket & UP.Resp)) -> IO(Plc.R(Socket & UP.Resp)):
  match r:
    case Fail{e}:
      IO.pure(Plc.R(Socket & UP.Resp), Fail{e})
    case Done{(s, x)}:
      Plc.take.st(Plc.status(x), s)

# GET url from the image cache: the connection and its 200 answer's head
# (the body follows on the connection); any other answer fails with why
# (Up.via), and the caller asks the registry.
def Plc.fetch(+url: String, +accept: String) -> IO(Plc.R(Socket & UP.Resp)):
  IO.bind(Plc.R(Socket & UP.Resp), Plc.R(Socket & UP.Resp), Plc.open(url, accept), r => Plc.fetch.got(r))

# Bodies
# ------

def Plc.body.recv(p: Socket & Plc.R(Maybe<&2, List<&2, U32>>), r: HT.Resp, +n: U32,
  again: Socket -> HT.Resp -> U32 -> IO(Socket & Plc.R(List<&2, U32>))) -> IO(Socket & Plc.R(List<&2, U32>)):
  match p:
    case (s, Fail{e}):
      IO.pure(Socket & Plc.R(List<&2, U32>), (s, Fail{e}))
    case (s, Done{None{}}):
      again(s, HT.Http.eof(r), n)
    case (s, Done{Some{+bs}}):
      again(s, HT.Http.feed(bs, r), (n + UP.Upc.count(bs, 0) : U32))

def Plc.body.big(big: Bool, s: Socket, r: HT.Resp, +cap: U32, more: Socket -> HT.Resp -> IO(Socket & Plc.R(List<&2, U32>))) ->
  IO(Socket & Plc.R(List<&2, U32>)):
  match big:
    case True{}:
      IO.pure(Socket & Plc.R(List<&2, U32>), (s, Fail{"the image cache's body is larger than " ++ U32.show((cap / 1024 : U32)) ++ " KiB"}))
    case False{}:
      more(s, r)

def Plc.body.more(r: HT.Resp, s: Socket, +n: U32, +cap: U32, more: Socket -> HT.Resp -> IO(Socket & Plc.R(List<&2, U32>))) ->
  IO(Socket & Plc.R(List<&2, U32>)):
  match r:
    case HT.Resp{HT.PDone{}, h, out}:
      IO.pure(Socket & Plc.R(List<&2, U32>), (s, Done{UP.Upc.body.take(HT.Http.take(HT.Resp{HT.PDone{}, h, out}))}))
    case HT.Resp{HT.PErr{e}, h, out}:
      IO.pure(Socket & Plc.R(List<&2, U32>), (s, Fail{"the image cache sent a broken body: " ++ e}))
    case HT.Resp{HT.PLost{e}, h, out}:
      IO.pure(Socket & Plc.R(List<&2, U32>), (s, Fail{"the image cache sent a broken body: " ++ e}))
    case HT.Resp{p, h, out}:
      Plc.body.big(U32.is_gt(n, cap), s, HT.Resp{p, h, out}, cap, more)

# Reads a body (Content-Length, chunked, or until the close) of at most
# cap bytes, decoded.
def Plc.body(fuel: Nat, s: Socket, r: HT.Resp, +n: U32, +cap: U32) -> IO(Socket & Plc.R(List<&2, U32>)):
  match fuel:
    case 0n:
      IO.pure(Socket & Plc.R(List<&2, U32>), (s, Fail{"the image cache's body did not end"}))
    case 1n+k:
      Plc.body.more(r, s, n, cap,
        s2 => r2 => IO.bind(Socket & Plc.R(Maybe<&2, List<&2, U32>>), Socket & Plc.R(List<&2, U32>), Plc.recv(s2),
          p => Plc.body.recv(p, r2, n, s3 => r3 => n3 => Plc.body(k, s3, r3, n3, cap))))

def Plc.read.end(q: Socket & Plc.R(List<&2, U32>)) -> IO(Plc.R(List<&2, U32>)):
  match q:
    case (s, r):
      do IO<Plc.R(List<&2, U32>)>:
        Socket.close(s)
        return r

# The whole body of an answer (at most cap bytes); closes the connection.
def Plc.read(p: Socket & UP.Resp, +cap: U32) -> IO(Plc.R(List<&2, U32>)):
  match p:
    case (s, UP.Resp{a, u, +h, +b}):
      IO.bind(Socket & Plc.R(List<&2, U32>), Plc.R(List<&2, U32>),
        Plc.body(UP.Upc.forever(), s, UP.Upc.body.start(h, b), UP.Upc.count(b, 0), cap), q => Plc.read.end(q))

def Plc.doc.got(r: Plc.R(Socket & UP.Resp), +cap: U32) -> IO(Plc.R(List<&2, U32>)):
  match r:
    case Fail{e}:
      IO.pure(Plc.R(List<&2, U32>), Fail{e})
    case Done{p}:
      Plc.read(p, cap)

# GET a document (a manifest, a config, at most cap bytes) from the image
# cache: its bytes, or why not (any answer but a 200 included).
def Plc.doc(+url: String, +accept: String, +cap: U32) -> IO(Plc.R(List<&2, U32>)):
  IO.bind(Plc.R(Socket & UP.Resp), Plc.R(List<&2, U32>), Plc.fetch(url, accept), r => Plc.doc.got(r, cap))

def Plc.ping.got(r: Plc.R(Socket & UP.Resp)) -> IO(Bool):
  match r:
    case Fail{e}:
      IO.pure(Bool, False{})
    case Done{(s, x)}:
      do IO<Bool>:
        Socket.close(s)
        return True{}

# Whether the image cache answers its ping (GET /v2/, a 200) at base.
def Plc.ping(+base: String) -> IO(Bool):
  IO.bind(Plc.R(Socket & UP.Resp), Bool, Plc.fetch(base ++ "/v2/", "*/*"), r => Plc.ping.got(r))
