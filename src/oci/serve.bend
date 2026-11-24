import Base
import ./size.bend as N
import ./route.bend as R

# The pull-through mirror's HTTP/1.1 side: pure. The host
# (host/oci/mirror.bend) reads a request head, answers with what these
# defs render, and streams a blob as its fill grows (Serve.follow). Part
# of the OCI library: it imports only Base and src/oci/.
#
# Sources: RFC 9112 (request line, header fields, one response per
# connection with Connection: close), Go's net/http StatusText (reason
# phrases), CNCF distribution's errcode messages (registry/api/errcode
# and registry/api/v2/errors.go), and src/oci/fill.bend's machine (a
# follower is cut off before the last byte of a fill that is not
# committed).

# A request head: method, request-target, header fields in order.
type Rq is Data:
  Rq{method: String, target: String, headers: List<&2, R.Header>}

# What a follower of a fill does next: send the bytes up to `upto`, wait
# for more, or end (every byte sent).
type Fw is Data:
  FwSend{upto: N.Size}
  FwWait{}
  FwDone{}

# Requests
# --------

def Serve.words(s: String) -> List<&2, String>:
  String.split(s, ' ')

def Serve.header.go(ps: List<&2, String>) -> Maybe<&2, R.Header>:
  match ps:
    case Con{n, Con{v, rest}}:
      Some{R.Hdr{String.trim(n), String.trim(String.join(Con{v, rest}, ":"))}}
    case _:
      None{}

# A header line "Name: value" (the value trimmed; it may hold ":").
def Serve.header(+line: String) -> Maybe<&2, R.Header>:
  Serve.header.go(String.split(line, ':'))

def Serve.headers.put(m: Maybe<&2, R.Header>, rest: List<&2, R.Header>) -> List<&2, R.Header>:
  match m:
    case Some{h}:
      Con{h, rest}
    case None{}:
      rest

def Serve.headers(ls: List<&2, String>) -> List<&2, R.Header>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{l, t}:
      Serve.headers.put(Serve.header(String.trim(l)), Serve.headers(t))

def Serve.line.ok(+v: String) -> Bool:
  String.eq(v, "HTTP/1.1") || String.eq(v, "HTTP/1.0")

def Serve.line(ws: List<&2, String>, hs: List<&2, R.Header>) -> Maybe<&2, Rq>:
  match ws:
    case Con{m, Con{t, Con{+v, Nil{}}}}:
      Bool.pick(Maybe<&2, Rq>, Serve.line.ok(String.trim(v)), Some{Rq{m, t, hs}}, None{})
    case _:
      None{}

def Serve.request.go(ls: List<&2, String>) -> Maybe<&2, Rq>:
  match ls:
    case Con{first, rest}:
      Serve.line(Serve.words(String.trim(first)), Serve.headers(rest))
    case Nil{}:
      None{}

# A request head (the text before CRLF CRLF): the request line
# "METHOD TARGET HTTP/1.x" and its header fields; None when the line is
# not one.
def Serve.request(+text: String) -> Maybe<&2, Rq>:
  Serve.request.go(String.lines(text))

def Serve.method(r: Rq) -> String:
  match r:
    case Rq{m, t, hs}:
      m

def Serve.target(r: Rq) -> String:
  match r:
    case Rq{m, t, hs}:
      t

# A header of the request, by name (case-insensitive).
def Serve.get(r: Rq, +name: String) -> Maybe<&2, String>:
  match r:
    case Rq{m, t, hs}:
      R.Route.find(hs, name)

# Responses
# ---------

# Go's net/http StatusText for the statuses the mirror sends.
def Serve.reason(+s: U32) -> String:
  Bool.pick(String, U32.is_eq(s, 200), "OK",
  Bool.pick(String, U32.is_eq(s, 206), "Partial Content",
  Bool.pick(String, U32.is_eq(s, 400), "Bad Request",
  Bool.pick(String, U32.is_eq(s, 403), "Forbidden",
  Bool.pick(String, U32.is_eq(s, 404), "Not Found",
  Bool.pick(String, U32.is_eq(s, 405), "Method Not Allowed",
  Bool.pick(String, U32.is_eq(s, 416), "Requested Range Not Satisfiable",
  Bool.pick(String, U32.is_eq(s, 429), "Too Many Requests",
  Bool.pick(String, U32.is_eq(s, 502), "Bad Gateway",
  Bool.pick(String, U32.is_eq(s, 504), "Gateway Timeout", "Internal Server Error"))))))))))

def Serve.fields(hs: List<&2, R.Header>) -> String:
  match hs:
    case Nil{}:
      ""
    case Con{R.Hdr{n, v}, t}:
      n ++ ": " ++ v ++ "\r\n" ++ Serve.fields(t)

def Serve.body(b: R.Body) -> String:
  match b:
    case R.JsonBody{t}:
      t
    case _:
      ""

# A response's status line, header fields and Connection: close, then its
# JSON body (a stream's bytes follow from the file).
def Serve.render(r: R.Resp) -> String:
  match r:
    case R.Resp{+s, hs, b}:
      "HTTP/1.1 " ++ U32.show(s) ++ " " ++ Serve.reason(s) ++ "\r\n" ++ Serve.fields(hs) ++ "Connection: close\r\n\r\n" ++ Serve.body(b)

def Serve.message(+code: String) -> String:
  Bool.pick(String, String.eq(code, "BLOB_UNKNOWN"), "blob unknown to registry",
  Bool.pick(String, String.eq(code, "MANIFEST_UNKNOWN"), "manifest unknown",
  Bool.pick(String, String.eq(code, "DENIED"), "requested access to the resource is denied",
  Bool.pick(String, String.eq(code, "TOOMANYREQUESTS"), "too many requests", "unknown error"))))

def Serve.reply.go(empty: Bool, head: Bool, +status: U32, +code: String) -> R.Resp:
  match empty:
    case True{}:
      R.Resp{status, [R.Hdr{"Content-Length", "0"}, R.Route.api_version()], R.NoBody{}}
    case False{}:
      R.Route.error(head, status, code, Serve.message(code))

# The answer to the fill machine's Reply{status, code}: the OCI error
# body for code, or none ("": a 502 or 504).
def Serve.reply(head: Bool, +status: U32, +code: String) -> R.Resp:
  Serve.reply.go(String.is_empty(code), head, status, code)

# Following a fill
# ----------------

def Serve.follow.go(done: Bool, more: Bool, +limit: N.Size) -> Fw:
  match done more:
    case True{} _:
      FwDone{}
    case False{} True{}:
      FwSend{limit}
    case False{} False{}:
      FwWait{}

def Serve.limit(committed: Bool, +have: N.Size, +len: N.Size) -> N.Size:
  match committed:
    case True{}:
      len
    case False{}:
      N.Size.min(have, N.Size.dec(len))

# A follower that has sent `sent` of a body of `len` bytes, whose fill
# file holds `have` bytes now: until the fill is committed (renamed into
# the store), the last byte is held back, so a fill that ends discarded
# cuts the follower off before its end and the client's digest check
# fails (src/oci/fill.bend, Abort).
def Serve.follow(+sent: N.Size, +have: N.Size, +len: N.Size, +committed: Bool) -> Fw:
  Serve.follow.go(N.Size.is_eq(sent, len), N.Size.is_lt(sent, Serve.limit(committed, have, len)), Serve.limit(committed, have, len))

# Sizes
# -----

# A size in KiB, rounded down (at most 2^32 - 1 KiB).
def Serve.kib(s: N.Size) -> U32:
  match s:
    case N.Size{h, l}:
      ((h * 4194304 : U32) + (l / 1024 : U32) : U32)

# Misses (feat/fast-cold-pull)
# ----------------------------
#
# What the mirror does with a request for an object its store lacks:
# fill it from the upstream (True), or answer 404 so the client asks the
# upstream itself (False). A GET always fills. A HEAD of a manifest by
# digest fills too: it is how containerd resolves an image
# (core/remotes/docker/resolver.go Resolve: HEAD of manifests/<digest>
# on each host in order, the next host on a 404), so a 404 there sends
# every node to the registry itself (a TLS handshake, a 401 and a token
# from the VM) for an object the mirror fetches once anyway; it gets its
# head once the fill has one. A HEAD of a blob stays a 404 (nothing
# resolves blobs; a fill for a HEAD would fetch its whole body).
def Serve.miss.fills(+head: Bool, +manifest: Bool) -> Bool:
  Bool.not(head) || manifest
