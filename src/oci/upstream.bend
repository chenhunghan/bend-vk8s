import Base
import ./size.bend as N
import ./auth.bend as A

# OCI upstream client: pure. The host (host/oci/upstream.bend) dials a
# registry over TLS, sends these requests and reads the answers; these
# defs say where a registry lives, what to send, and what each response
# head makes the client do next. Part of the OCI library: it imports only
# Base and src/oci/.
#
# Used by vk8s's two pullers on the host: the layer filler (`vk8s layers
# serve` and `vk8s layers fill`, host/layers/fill.bend) and the image
# cache's pull-through mirror (host/oci/mirror.bend). Both pull public
# content anonymously, as the image cache VM's distribution proxy did.
#
# Sources:
# - containerd core/remotes/docker/config/hosts.go: docker.io's API host
#   is registry-1.docker.io; any other registry is its own host, over
#   https.
# - Go's net/http Request.Write: the request line carries the URL's path
#   and query (RequestURI, no fragment), and Host is the URL's Host.
# - containerd core/remotes/docker/authorizer.go and scope.go: a 401 with
#   a Bearer challenge is answered once with an anonymous token; a
#   challenge with no scope gets "repository:<name>:pull" (the
#   repository scope of the pull, scope.go RepositoryScope); a second 401
#   is final.
# - src/oci/auth.bend for challenges, token requests and responses, and
#   redirects (https only, at most 10, Authorization kept only for the
#   same origin).

# What a response head makes the client do.
type Next is Data:
  # the answer to give back: read its body, or map its status
  Final{}
  # fetch an anonymous token for this challenge, then ask again with it
  Token{bearer: A.Bearer}
  # ask again at url, with the Authorization header when auth
  Hop{url: String, auth: Bool}
  # give up: why
  Stop{why: String}

# The bytes of a response so far, cut after the head's CRLF CRLF.
type Cut is Data:
  Cut{head: +List<U32>, body: +List<U32>, found: Bool}

# Where a registry lives
# ----------------------

def Up.host_of(+registry: String) -> String:
  Bool.pick(String, String.eq(registry, "docker.io"), "registry-1.docker.io", registry)

# The base URL of registry's API (containerd's default host).
def Up.base(+registry: String) -> String:
  "https://" ++ Up.host_of(registry)

# The URL of a manifest or a blob (kind "manifests" or "blobs") of repo.
def Up.url(+base: String, +repo: String, +kind: String, +ref: String) -> String:
  base ++ "/v2/" ++ repo ++ "/" ++ kind ++ "/" ++ ref

# What a GET of a manifest accepts, as containerd's resolver asks
# (core/remotes/docker/resolver.go): Docker schema 2 manifest and list,
# OCI manifest and index, then anything.
def Up.manifest_accept() -> String:
  "application/vnd.docker.distribution.manifest.v2+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.oci.image.index.v1+json, */*"

# The request
# -----------

def Up.first(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, t}:
      x

def Up.target.go(+p: String) -> String:
  Bool.pick(String, String.is_empty(p), "/", p)

# The request target of a URL's rest (path and query, no fragment).
def Up.target(+rest: String) -> String:
  Up.target.go(Up.first(String.split(rest, '#')))

def Up.auth_line(+auth: String) -> String:
  Bool.pick(String, String.is_empty(auth), "", "Authorization: " ++ auth ++ "\r\n")

def Up.request.go(u: A.Url, +accept: String, +auth: String) -> String:
  match u:
    case A.Url{sc, au, r}:
      "GET " ++ Up.target(r) ++ " HTTP/1.1\r\nHost: " ++ A.Url.hostport(au) ++ "\r\nUser-Agent: vk8s\r\nAccept: " ++ accept ++ "\r\n"
        ++ Up.auth_line(auth) ++ "Connection: close\r\n\r\n"

# A GET of url: Host, User-Agent, Accept, Authorization when auth is not
# "", and Connection: close (one request per connection).
def Up.request(+url: String, +accept: String, +auth: String) -> String:
  Up.request.go(A.Url.parse(url), accept, auth)

# The Authorization header value for a token.
def Up.bearer_auth(+token: String) -> String:
  "Bearer " ++ token

# Where to dial
# -------------

def Up.port.of(m: Maybe<&2, N.Size>) -> U32:
  match m:
    case Some{N.Size{+h, +l}}:
      Bool.pick(U32, U32.is_zero(h) && U32.is_lt(l, 65536), l, 0)
    case None{}:
      0

def Up.dial.go(u: A.Url) -> String & U32:
  match u:
    case A.Url{+sc, +au, r}:
      (A.Url.host(au), Up.port.of(N.Size.read(A.Url.eport(sc, A.Url.port(A.Url.hostport(au))))))

# The hostname (also the TLS server name) and port to dial for url (0:
# none, as for a URL that is not https).
def Up.dial(+url: String) -> String & U32:
  Up.dial.go(A.Url.parse(url))

def Up.dial.fst(p: String & U32) -> String:
  match p:
    case (h, n):
      h

# The hostname of url, for messages.
def Up.dial.host(+url: String) -> String:
  Up.dial.fst(Up.dial(url))

# Whether url may be dialed: https, with a host and a port.
def Up.dialable.go(p: String & U32, https: Bool) -> Bool:
  match p:
    case (h, n):
      https && Bool.not(String.is_empty(h)) && Bool.not(U32.is_zero(n))

def Up.dialable(+url: String) -> Bool:
  Up.dialable.go(Up.dial(url), A.Auth.is_https(url))

# Responses
# ---------

def Up.crlf2(bs: +List<U32>) -> Bool:
  match bs:
    case Con{a, Con{b, Con{c, Con{d, t}}}}:
      U32.is_eq(a, 13) && U32.is_eq(b, 10) && U32.is_eq(c, 13) && U32.is_eq(d, 10)
    case _:
      False{}

def Up.cut.cons(c: U32, r: Cut) -> Cut:
  match r:
    case Cut{h, b, f}:
      Cut{Con{c, h}, b, f}

def Up.cut.at(hit: Bool, c: U32, +t: +List<U32>, r: Cut) -> Cut:
  match hit:
    case True{}:
      Cut{Nil{}, List.drop(&2, U32, t, 3n), True{}}
    case False{}:
      Up.cut.cons(c, r)

# The bytes of a response so far, cut at the first CRLF CRLF: the head
# (without it) and the body bytes that came along.
def Up.cut(bs: +List<U32>) -> Cut:
  match bs:
    case Nil{}:
      Cut{Nil{}, Nil{}, False{}}
    case Con{+c, +t}:
      Up.cut.at(Up.crlf2(Con{c, t}), c, t, Up.cut(t))

# Bytes as text, one character per byte (an HTTP head is ASCII).
def Up.text(bs: List<&2, U32>) -> String:
  match bs:
    case Nil{}:
      SNil{}
    case Con{b, t}:
      SCon{Chr{b}, Up.text(t)}

# A challenge's scopes, or the pull scope of repo when it names none.
def Up.scoped(b: A.Bearer, +repo: String) -> A.Bearer:
  match b:
    case A.Bearer{r, sv, +sc}:
      A.Bearer{r, sv, Bool.pick(+List<String>, List.is_empty(&2, String, sc), ["repository:" ++ repo ++ ":pull"], sc)}

# A token request for the pull of repo (a ping of /v2/ before a pull):
# the challenge's realm and service, the repository's pull scope.
def Up.repo_scoped(b: A.Bearer, +repo: String) -> A.Bearer:
  match b:
    case A.Bearer{r, sv, sc}:
      A.Bearer{r, sv, ["repository:" ++ repo ++ ":pull"]}

def Up.on401(m: Maybe<&2, A.Bearer>) -> Next:
  match m:
    case None{}:
      Final{}
    case Some{b}:
      Token{b}

def Up.on3xx(h: A.Hop) -> Next:
  match h:
    case A.Follow{u, a}:
      Hop{u, a}
    case A.Refuse{w}:
      Stop{w}

def Up.next.go(deny: Bool, moved: Bool, tried: Bool, +url: String, +hops: U32, +loc: String, chs: List<&2, String>) -> Next:
  match deny moved tried:
    case True{} _ False{}:
      Up.on401(A.Auth.pick(url, chs))
    case True{} _ True{}:
      Final{}
    case False{} True{} _:
      Up.on3xx(A.Auth.redirect(hops, url, loc))
    case False{} False{} _:
      Final{}

# What a response head to a GET of url means. status: its status; hops:
# redirects followed so far; tried: a token was already sent; loc: its
# Location ("" when none); chs: its WWW-Authenticate values in order.
def Up.next(+status: U32, +url: String, +hops: U32, tried: Bool, +loc: String, chs: List<&2, String>) -> Next:
  Up.next.go(U32.is_eq(status, 401), A.Auth.is_redirect(status), tried, url, hops, loc, chs)
