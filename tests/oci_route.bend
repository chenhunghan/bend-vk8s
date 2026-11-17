import Base
import ../src/oci/route.bend as R
import ../src/oci/grammar.bend as G
import ../src/oci/size.bend as N

# Tests for src/oci/route.bend. Expected values follow distribution-spec
# spec.md, RFC 9110 section 14, CNCF distribution and containerd's
# core/remotes/docker (see laws/oci_route.bend for each source).

def report(name: String, got: String, want: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name ++ ": got " ++ got ++ ", want " ++ want)

def check(name: String, +got: String, +want: String) -> IO(Unit):
  report(name, got, want, String.eq(got, want))

def T.opt(m: Maybe<&2, String>) -> String:
  match m:
    case None{}:
      "<none>"
    case Some{v}:
      v

def T.ranged(r: R.Ranged) -> String:
  match r:
    case R.Whole{}:
      "whole"
    case R.Unsat{}:
      "unsatisfiable"
    case R.Part{f, l}:
      N.Size.show(f) ++ "-" ++ N.Size.show(l)

def T.req(q: R.Req) -> String:
  match q:
    case R.Ping{h}:
      "ping"
    case R.Fetch{h, R.Manifest{}, n, d}:
      "manifest " ++ n ++ " " ++ G.Gram.digest.show(d)
    case R.Fetch{h, R.Blob{}, n, d}:
      "blob " ++ n ++ " " ++ G.Gram.digest.show(d)
    case R.Reply{r}:
      U32.show(R.Route.status(r))

def T.body(b: R.Body) -> String:
  match b:
    case R.NoBody{}:
      "none"
    case R.JsonBody{t}:
      t
    case R.Stream{f, n}:
      N.Size.show(f) ++ "+" ++ N.Size.show(n)

def T.route(+m: String, +p: String) -> String:
  T.req(R.Route.request(m, p))

def T.range(h: String, +size: U32) -> String:
  T.ranged(R.Route.range(Some{h}, None{}, "\"sha256:E\"", N.Size.of(size)))

def T.blob(+range: String, +size: N.Size) -> R.Resp:
  R.Route.found(R.Blob{}, False{}, G.Sha256{"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}, "application/octet-stream", size, Some{range}, None{})

def main() -> IO(Unit):
  do IO<Unit>:
    check("ping", T.route("GET", "/v2/"), "ping")
    check("ping head", T.route("HEAD", "/v2/"), "ping")
    check("blob", T.route("GET", "/v2/library/alpine/blobs/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"), "blob library/alpine sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    check("manifest", T.route("HEAD", "/v2/a/b/c/manifests/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"), "manifest a/b/c sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    check("query ignored", T.route("GET", "/v2/alpine/blobs/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855?ns=docker.io"), "blob alpine sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    check("tag refused", T.route("GET", "/v2/alpine/manifests/latest"), "404")
    check("sha512 refused", T.route("GET", "/v2/alpine/manifests/sha512:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"), "400")
    check("blob by tag", T.route("GET", "/v2/alpine/blobs/latest"), "400")
    check("bad name", T.route("GET", "/v2/Alpine/blobs/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"), "400")
    check("traversal name", T.route("GET", "/v2/../x/blobs/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"), "400")
    check("tags list", T.route("GET", "/v2/alpine/tags/list"), "404")
    check("push", T.route("PUT", "/v2/alpine/manifests/latest"), "405")
    check("delete", T.route("DELETE", "/v2/alpine/blobs/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"), "405")
    check("tag body", R.Route.req.body(R.Route.request("GET", "/v2/alpine/manifests/latest")),
      "{\"errors\":[{\"code\":\"UNSUPPORTED\",\"message\":\"pull-only mirror: resolve tags upstream and pull by digest\"}]}\n")
    check("missing blob", T.body(R.Route.body(R.Route.missing(R.Blob{}, False{}))),
      "{\"errors\":[{\"code\":\"BLOB_UNKNOWN\",\"message\":\"blob unknown to registry\"}]}\n")
    check("missing manifest head", T.body(R.Route.body(R.Route.missing(R.Manifest{}, True{}))), "none")
    check("range first", T.range("bytes=0-99", 1000), "0-99")
    check("range open", T.range("bytes=100-", 1000), "100-999")
    check("range suffix", T.range("bytes=-100", 1000), "900-999")
    check("range suffix long", T.range("bytes=-5000", 1000), "0-999")
    check("range cut", T.range("bytes=10-5000", 1000), "10-999")
    check("range at end", T.range("bytes=1000-", 1000), "unsatisfiable")
    check("range backwards", T.range("bytes=9-3", 1000), "unsatisfiable")
    check("range suffix zero", T.range("bytes=-0", 1000), "unsatisfiable")
    check("range unknown unit", T.range("lines=1-2", 1000), "whole")
    check("range several", T.range("bytes=0-1, 4-5", 1000), "whole")
    check("range empty blob", T.range("bytes=0-0", 0), "unsatisfiable")
    check("range empty blob suffix", T.range("bytes=-1", 0), "whole")
    check("range 206", U32.show(R.Route.status(T.blob("bytes=0-99", N.Size.of(1000)))), "206")
    check("range content-range", T.opt(R.Route.header(T.blob("bytes=0-99", N.Size.of(1000)), "Content-Range")), "bytes 0-99/1000")
    check("range content-length", T.opt(R.Route.header(T.blob("bytes=0-99", N.Size.of(1000)), "Content-Length")), "100")
    check("range body", T.body(R.Route.body(T.blob("bytes=100-199", N.Size.of(1000)))), "100+100")
    check("range 416", U32.show(R.Route.status(T.blob("bytes=1000-", N.Size.of(1000)))), "416")
    check("range 416 content-range", T.opt(R.Route.header(T.blob("bytes=1000-", N.Size.of(1000)), "Content-Range")), "bytes */1000")
    check("range past 4 GiB", T.opt(R.Route.header(T.blob("bytes=4294967296-", N.Size{1, 1073741824}), "Content-Range")),
      "bytes 4294967296-5368709119/5368709120")
    check("digest header", T.opt(R.Route.header(T.blob("lines=0-1", N.Size.of(3)), "docker-content-digest")), "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    check("size show", N.Size.show(N.Size{4294967295, 4294967295}), "18446744073709551615")
    check("size read", T.ranged(R.Part{N.Size.zero(), Maybe.default(&2, N.Size, N.Size.read("123456789012345678"), N.Size.zero())}), "0-123456789012345678")
