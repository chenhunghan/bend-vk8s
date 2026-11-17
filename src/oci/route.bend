import Base
import ./size.bend as N
import ./grammar.bend as G

# Routing and responses of a pull-through, pull-only OCI Distribution
# mirror. Pure: the host (host/oci/) reads the request line and headers,
# calls Route.request, looks the object up in the store (src/oci/store.bend)
# or upstream, and sends what Route.found, Route.missing, Route.ping or the
# Reply carries. Part of the self-contained OCI library: it imports only
# Base and src/oci/.
#
# Sources: opencontainers/distribution-spec spec.md (endpoints end-1,
# end-2, end-3, error codes and body), RFC 9110 section 14 (Range), CNCF
# distribution registry/handlers and registry/storage/blobserver.go (the
# headers and the error messages), containerd core/remotes/docker
# resolver.go (what a mirror's answers make the client do).
#
# Decisions:
# - Only GET and HEAD are served; every other method is 405 UNSUPPORTED
#   (distribution's errcode for UNSUPPORTED is 405), with Allow: GET, HEAD.
# - A manifest by tag is refused with 404 UNSUPPORTED. The mirror is
#   configured with the "pull" capability only, so containerd resolves tags
#   upstream; if a tag reaches the mirror anyway, containerd's resolver
#   treats a 404 as "not here" and tries the next host, while a 400 or 405
#   would end as an unexpected-status error (a 405 also costs a GET retry).
#   spec.md lists 404 as end-3's only failure code.
# - A malformed or non-sha256 digest is 400 DIGEST_INVALID (spec.md: an
#   invalid digest or unsupported algorithm SHOULD be 400); a name that
#   fails the grammar is 400 NAME_INVALID; a reference that is neither a
#   tag nor a digest is 404 MANIFEST_UNKNOWN.
# - Any other path is 404 UNSUPPORTED (tags/list, referrers, _catalog,
#   uploads): a client of the referrers API then falls back as spec.md asks.
# - Range applies to blobs only, on GET only (RFC 9110 14.2: GET is the
#   only method with range handling). One byte range is served as 206;
#   several ranges are ignored (200, the whole blob; a server MAY ignore
#   Range), as is an unknown unit (MUST ignore) and a failed If-Range.
#   A malformed bytes range or an unsatisfiable one is 416 with
#   Content-Range: bytes */<size>, as Go's http.ServeContent answers.

type Header is Data:
  Hdr{name: String, value: String}

# A response body: none (HEAD, 416), a JSON text, or length bytes of the
# stored object from offset first.
type Body is Data:
  NoBody{}
  JsonBody{text: String}
  Stream{first: N.Size, length: N.Size}

type Resp is Data:
  Resp{status: U32, headers: List<&2, Header>, body: Body}

type Obj is Data:
  Manifest{}
  Blob{}

# What a request asks for: the ping, an object to look up by digest, or a
# response the request already decides.
type Req is Data:
  Ping{head: Bool}
  Fetch{head: Bool, obj: Obj, name: String, digest: G.Digest}
  Reply{resp: Resp}

# How a GET of a blob answers a Range header.
type Ranged is Data:
  Whole{}
  Part{first: N.Size, last: N.Size}
  Unsat{}

def Route.status(r: Resp) -> U32:
  match r:
    case Resp{s, h, b}:
      s

def Route.body(r: Resp) -> Body:
  match r:
    case Resp{s, h, b}:
      b

def Route.pick(hit: Bool, v: String, rest: Maybe<&2, String>) -> Maybe<&2, String>:
  match hit:
    case True{}:
      Some{v}
    case False{}:
      rest

def Route.find(hs: List<&2, Header>, +name: String) -> Maybe<&2, String>:
  match hs:
    case Nil{}:
      None{}
    case Con{Hdr{n, v}, t}:
      Route.pick(String.eq(String.to_lower(n), String.to_lower(name)), v, Route.find(t, name))

# The value of a response header; names compare case-insensitively.
def Route.header(r: Resp, +name: String) -> Maybe<&2, String>:
  match r:
    case Resp{s, h, b}:
      Route.find(h, name)

def Route.api_version() -> Header:
  Hdr{"Docker-Distribution-API-Version", "registry/2.0"}

def Route.length(+s: String) -> String:
  U32.show(U32.from_nat(String.length(s)))

# spec.md "Error Codes": {"errors": [{"code", "message"}]}, encoded as Go's
# json.Encoder writes distribution's errcode.Errors (a final newline).
def Route.error_json(code: String, message: String) -> String:
  "{\"errors\":[{\"code\":\"" ++ code ++ "\",\"message\":\"" ++ message ++ "\"}]}\n"

def Route.json.body(head: Bool, s: String) -> Body:
  match head:
    case True{}:
      NoBody{}
    case False{}:
      JsonBody{s}

# A JSON response; a HEAD gets the same headers and no body.
def Route.json(head: Bool, status: U32, +text: String) -> Resp:
  Resp{status, [Hdr{"Content-Type", "application/json"}, Hdr{"Content-Length", Route.length(text)}, Route.api_version()], Route.json.body(head, text)}

def Route.error(head: Bool, status: U32, code: String, message: String) -> Resp:
  Route.json(head, status, Route.error_json(code, message))

def Route.name_invalid(head: Bool) -> Resp:
  Route.error(head, 400, "NAME_INVALID", "invalid repository name")

def Route.digest_invalid(head: Bool) -> Resp:
  Route.error(head, 400, "DIGEST_INVALID", "provided digest did not match uploaded content")

def Route.manifest_unknown(head: Bool) -> Resp:
  Route.error(head, 404, "MANIFEST_UNKNOWN", "manifest unknown")

def Route.blob_unknown(head: Bool) -> Resp:
  Route.error(head, 404, "BLOB_UNKNOWN", "blob unknown to registry")

def Route.tag_refused(head: Bool) -> Resp:
  Route.error(head, 404, "UNSUPPORTED", "pull-only mirror: resolve tags upstream and pull by digest")

def Route.unknown(head: Bool) -> Resp:
  Route.error(head, 404, "UNSUPPORTED", "The operation is unsupported.")

def Route.not_allowed() -> Resp:
  +text = Route.error_json("UNSUPPORTED", "The operation is unsupported.")
  Resp{405, [Hdr{"Content-Type", "application/json"}, Hdr{"Content-Length", Route.length(text)}, Hdr{"Allow", "GET, HEAD"}, Route.api_version()], JsonBody{text}}

# GET /v2/ (end-1): 200 with "{}", as distribution's apiBase answers.
def Route.ping(head: Bool) -> Resp:
  Route.json(head, 200, "{}")

def Route.target(obj: Obj, r: G.Ref, head: Bool, name: String) -> Req:
  match obj r:
    case Manifest{} G.RDigest{d}:
      Fetch{head, Manifest{}, name, d}
    case Manifest{} G.RBadDigest{}:
      Reply{Route.digest_invalid(head)}
    case Manifest{} G.RTag{}:
      Reply{Route.tag_refused(head)}
    case Manifest{} G.RBad{}:
      Reply{Route.manifest_unknown(head)}
    case Blob{} G.RDigest{d}:
      Fetch{head, Blob{}, name, d}
    case Blob{} _:
      Reply{Route.digest_invalid(head)}

def Route.named(ok: Bool, head: Bool, obj: Obj, name: String, +ref: String) -> Req:
  match ok:
    case False{}:
      Reply{Route.name_invalid(head)}
    case True{}:
      Route.target(obj, G.Gram.ref(ref), head, name)

def Route.kind.go(man: Bool, blob: Bool, head: Bool, +name: String, ref: String) -> Req:
  match man blob:
    case True{} _:
      Route.named(G.Gram.name(name), head, Manifest{}, name, ref)
    case False{} True{}:
      Route.named(G.Gram.name(name), head, Blob{}, name, ref)
    case False{} False{}:
      Reply{Route.unknown(head)}

def Route.kind(head: Bool, +kind: String, name: String, ref: String) -> Req:
  Route.kind.go(String.eq(kind, "manifests"), String.eq(kind, "blobs"), head, name, ref)

# The path segments after /v2/, last first: <reference>, the endpoint
# ("manifests" or "blobs"), then the name's components.
def Route.parts(head: Bool, rev: List<&2, String>) -> Req:
  match rev:
    case Con{ref, Con{kind, Con{n, ns}}}:
      Route.kind(head, kind, String.join(List.reverse(&2, String, Con{n, ns}), "/"), ref)
    case _:
      Reply{Route.unknown(head)}

def Route.path.go(ping: Bool, v2: Bool, head: Bool, rest: String) -> Req:
  match ping v2:
    case True{} _:
      Ping{head}
    case False{} True{}:
      Route.parts(head, List.reverse(&2, String, String.split(rest, '/')))
    case False{} False{}:
      Reply{Route.unknown(head)}

def Route.path(head: Bool, +p: String) -> Req:
  Route.path.go(String.eq(p, "/v2/"), String.starts_with(p, "/v2/"), head, String.drop(p, 4n))

def Route.request.go(read: Bool, head: Bool, target: String) -> Req:
  match read:
    case False{}:
      Reply{Route.not_allowed()}
    case True{}:
      Route.path(head, G.Gram.before(target, '?'))

# A request: its method and its request-target (path and query; the query
# is ignored).
def Route.request(+method: String, target: String) -> Req:
  Route.request.go(Bool.or(String.eq(method, "GET"), String.eq(method, "HEAD")), String.eq(method, "HEAD"), target)

# Range (RFC 9110 section 14).

def Route.range.fit.go(ok: Bool, f: N.Size, l: N.Size) -> Ranged:
  match ok:
    case True{}:
      Part{f, l}
    case False{}:
      Unsat{}

# first-last against the size: satisfiable when first < size; last is
# cut to size - 1 (14.1.1).
def Route.range.fit(+f: N.Size, l: N.Size, +size: N.Size) -> Ranged:
  Route.range.fit.go(N.Size.is_lt(f, size), f, N.Size.min(l, N.Size.dec(size)))

def Route.range.order(bad: Bool, f: N.Size, l: N.Size, size: N.Size) -> Ranged:
  match bad:
    case True{}:
      Unsat{}
    case False{}:
      Route.range.fit(f, l, size)

def Route.range.last(m: Maybe<&2, N.Size>, +f: N.Size, size: N.Size) -> Ranged:
  match m:
    case None{}:
      Unsat{}
    case Some{+l}:
      Route.range.order(N.Size.is_lt(l, f), f, l, size)

def Route.range.end(open: Bool, f: N.Size, b: String, +size: N.Size) -> Ranged:
  match open:
    case True{}:
      Route.range.fit(f, N.Size.dec(size), size)
    case False{}:
      Route.range.last(N.Size.read(b), f, size)

def Route.range.from(m: Maybe<&2, N.Size>, +open: Bool, b: String, size: N.Size) -> Ranged:
  match m:
    case None{}:
      Unsat{}
    case Some{f}:
      Route.range.end(open, f, b, size)

def Route.range.suffix.first(lt: Bool, n: N.Size, size: N.Size) -> N.Size:
  match lt:
    case True{}:
      N.Size.sub(size, n)
    case False{}:
      N.Size.zero()

def Route.range.suffix.sized(empty: Bool, +n: N.Size, +size: N.Size) -> Ranged:
  match empty:
    case True{}:
      Whole{}
    case False{}:
      Part{Route.range.suffix.first(N.Size.is_lt(n, size), n, size), N.Size.dec(size)}

# -n: the last n bytes, all of them when n >= size; -0 is unsatisfiable.
# An empty blob has no byte to name, so it is served whole.
def Route.range.suffix.n(zero: Bool, n: N.Size, +size: N.Size) -> Ranged:
  match zero:
    case True{}:
      Unsat{}
    case False{}:
      Route.range.suffix.sized(N.Size.is_zero(size), n, size)

def Route.range.suffix(m: Maybe<&2, N.Size>, size: N.Size) -> Ranged:
  match m:
    case None{}:
      Unsat{}
    case Some{+n}:
      Route.range.suffix.n(N.Size.is_zero(n), n, size)

def Route.range.pair(suffix: Bool, a: String, b: String, size: N.Size) -> Ranged:
  match suffix:
    case True{}:
      Route.range.suffix(N.Size.read(b), size)
    case False{}:
      +e = b
      Route.range.from(N.Size.read(a), String.is_empty(e), e, size)

def Route.range.spec(parts: List<&2, String>, size: N.Size) -> Ranged:
  match parts:
    case Con{+a, Con{b, Nil{}}}:
      Route.range.pair(String.is_empty(a), a, b, size)
    case _:
      Unsat{}

def Route.range.one(xs: List<&2, String>, size: N.Size) -> Ranged:
  match xs:
    case Nil{}:
      Unsat{}
    case Con{r, Nil{}}:
      Route.range.spec(String.split(r, '-'), size)
    case _:
      Whole{}

def Route.range.keep(empty: Bool, x: String, rest: List<&2, String>) -> List<&2, String>:
  match empty:
    case True{}:
      rest
    case False{}:
      Con{x, rest}

# The list elements of a range-set, trimmed, empty ones dropped (RFC 9110
# 5.6.1: a recipient accepts empty list elements).
def Route.range.items(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      +y = String.trim(x)
      Route.range.keep(String.is_empty(y), y, Route.range.items(t))

def Route.range.bytes(bytes: Bool, set: String, size: N.Size) -> Ranged:
  match bytes:
    case True{}:
      Route.range.one(Route.range.items(String.split(set, ',')), size)
    case False{}:
      Whole{}

def Route.range.unit(ps: List<&2, String>, size: N.Size) -> Ranged:
  match ps:
    case Con{u, Con{set, Nil{}}}:
      Route.range.bytes(String.eq(String.to_lower(String.trim(u)), "bytes"), set, size)
    case _:
      Whole{}

def Route.range.if(ok: Bool, v: String, size: N.Size) -> Ranged:
  match ok:
    case True{}:
      Route.range.unit(String.split(v, '='), size)
    case False{}:
      Whole{}

def Route.if_range(m: Maybe<&2, String>, etag: String) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{v}:
      String.eq(String.trim(v), etag)

# The Range and If-Range headers of a GET against the blob's ETag and
# size. No Range: the whole blob. If-Range that is not the blob's ETag
# (14.2: a date never matches, the mirror sends no Last-Modified): whole.
def Route.range(range: Maybe<&2, String>, if_range: Maybe<&2, String>, etag: String, size: N.Size) -> Ranged:
  match range:
    case None{}:
      Whole{}
    case Some{v}:
      Route.range.if(Route.if_range(if_range, etag), v, size)

# A HEAD ignores Range (14.2).
def Route.range.get(head: Bool, range: Maybe<&2, String>, if_range: Maybe<&2, String>, etag: String, size: N.Size) -> Ranged:
  match head:
    case True{}:
      Whole{}
    case False{}:
      Route.range(range, if_range, etag, size)

# Responses for a found object.

def Route.etag(d: G.Digest) -> String:
  "\"" ++ G.Gram.digest.show(d) ++ "\""

# distribution's headers: manifests (registry/handlers/manifests.go) and
# blobs (registry/storage/blobserver.go, with http.ServeContent's
# Accept-Ranges).
def Route.content(obj: Obj, +d: G.Digest, media: String, len: String) -> List<&2, Header>:
  match obj:
    case Manifest{}:
      [Hdr{"Content-Type", media}, Hdr{"Content-Length", len}, Hdr{"Docker-Content-Digest", G.Gram.digest.show(d)}, Hdr{"ETag", Route.etag(d)}, Route.api_version()]
    case Blob{}:
      [Hdr{"Content-Type", media}, Hdr{"Content-Length", len}, Hdr{"Docker-Content-Digest", G.Gram.digest.show(d)}, Hdr{"ETag", Route.etag(d)}, Hdr{"Cache-Control", "max-age=31536000"}, Hdr{"Accept-Ranges", "bytes"}, Route.api_version()]

def Route.full.body(head: Bool, size: N.Size) -> Body:
  match head:
    case True{}:
      NoBody{}
    case False{}:
      Stream{N.Size.zero(), size}

def Route.full(head: Bool, obj: Obj, d: G.Digest, media: String, +size: N.Size) -> Resp:
  Resp{200, Route.content(obj, d, media, N.Size.show(size)), Route.full.body(head, size)}

def Route.partial(d: G.Digest, media: String, +f: N.Size, +l: N.Size, +size: N.Size) -> Resp:
  +n = N.Size.inc(N.Size.sub(l, f))
  Resp{206, Con{Hdr{"Content-Range", "bytes " ++ N.Size.show(f) ++ "-" ++ N.Size.show(l) ++ "/" ++ N.Size.show(size)}, Route.content(Blob{}, d, media, N.Size.show(n))}, Stream{f, n}}

def Route.unsat(size: N.Size) -> Resp:
  Resp{416, [Hdr{"Content-Range", "bytes */" ++ N.Size.show(size)}, Hdr{"Content-Length", "0"}, Route.api_version()], NoBody{}}

def Route.ranged(r: Ranged, head: Bool, d: G.Digest, media: String, size: N.Size) -> Resp:
  match r:
    case Whole{}:
      Route.full(head, Blob{}, d, media, size)
    case Part{f, l}:
      Route.partial(d, media, f, l, size)
    case Unsat{}:
      Route.unsat(size)

# The answer for an object the store holds (or upstream sent): its digest,
# media type and size, and the request's Range and If-Range headers.
def Route.found(obj: Obj, head: Bool, +d: G.Digest, media: String, +size: N.Size, range: Maybe<&2, String>, if_range: Maybe<&2, String>) -> Resp:
  match obj:
    case Manifest{}:
      Route.full(head, Manifest{}, d, media, size)
    case Blob{}:
      Route.ranged(Route.range.get(head, range, if_range, Route.etag(d), size), head, d, media, size)

# The answer for an object neither the store nor upstream has.
def Route.missing(obj: Obj, head: Bool) -> Resp:
  match obj:
    case Manifest{}:
      Route.manifest_unknown(head)
    case Blob{}:
      Route.blob_unknown(head)

# For laws and tests: the status a request is answered with before any
# lookup (0 for a Fetch, which needs one), and its JSON body ("" if none).
def Route.req.status(q: Req) -> U32:
  match q:
    case Ping{h}:
      200
    case Fetch{h, o, n, d}:
      0
    case Reply{r}:
      Route.status(r)

def Route.text(b: Body) -> String:
  match b:
    case JsonBody{t}:
      t
    case _:
      ""

def Route.req.body(q: Req) -> String:
  match q:
    case Ping{h}:
      Route.text(Route.body(Route.ping(h)))
    case Fetch{h, o, n, d}:
      ""
    case Reply{r}:
      Route.text(Route.body(r))
