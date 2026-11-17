import Base
import ../src/oci/store.bend as S
import ../src/oci/size.bend as N

# Tests for src/oci/store.bend. The layout, the 72 h expiry since last use
# and the prune plan are user decisions of 2026-11-17; the name grammars
# come from distribution/reference and the image-spec.

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

def T.bool(b: Bool) -> String:
  match b:
    case True{}:
      "true"
    case False{}:
      "false"

def T.meta(m: Maybe<&2, S.Meta>) -> String:
  match m:
    case None{}:
      "<none>"
    case Some{x}:
      S.Store.meta.render(x)

def T.blob(+reg: String, +dig: String) -> String:
  T.opt(S.Store.blob_path("/var/cache/oci", reg, dig))

def main() -> IO(Unit):
  do IO<Unit>:
    check("blob path", T.blob("docker.io", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"), "/var/cache/oci/docker.io/blobs/sha256/e3/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    check("meta path", T.opt(S.Store.meta_path("/c", "ghcr.io", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")), "/c/ghcr.io/blobs/sha256/ba/ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad.meta")
    check("port", T.blob("localhost:5000", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"), "/var/cache/oci/localhost:5000/blobs/sha256/e3/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    check("lowercase", T.blob("Registry.K8S.io", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"), "/var/cache/oci/registry.k8s.io/blobs/sha256/e3/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    check("dot dot registry", T.blob("..", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"), "<none>")
    check("slash registry", T.blob("docker.io/../..", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"), "<none>")
    check("empty registry", T.blob("", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"), "<none>")
    check("traversal digest", T.blob("docker.io", "sha256:../../../../etc/passwd"), "<none>")
    check("upper digest", T.blob("docker.io", "sha256:E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855"), "<none>")
    check("sha512 digest", T.blob("docker.io", "sha512:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"), "<none>")
    check("tmp", S.Store.tmp_dir("/c"), "/c/tmp")
    check("meta round trip", T.meta(S.Store.meta.parse(S.Store.meta.render(S.Meta{"application/vnd.oci.image.index.v1+json", N.Size{2, 5}, 1763337600}))),
      "oci-cache-meta 1\nmedia-type application/vnd.oci.image.index.v1+json\nsize 8589934597\nlast-use 1763337600\n")
    check("meta garbage", T.meta(S.Store.meta.parse("size 1\n")), "<none>")
    check("media cleaned", T.meta(Some{S.Store.meta.new("Application/JSON ; q=1", N.Size.of(2), 5)}),
      "oci-cache-meta 1\nmedia-type Application/JSON\nsize 2\nlast-use 5\n")
    check("media refused", T.meta(Some{S.Store.meta.new("a/b\nc", N.Size.of(2), 5)}),
      "oci-cache-meta 1\nmedia-type application/octet-stream\nsize 2\nlast-use 5\n")
    check("fresh 71h59m59s", T.bool(S.Store.expired(S.Meta{"a/b", N.Size.of(1), 1000}, 260199)), "false")
    check("expired 72h", T.bool(S.Store.expired(S.Meta{"a/b", N.Size.of(1), 1000}, 260200)), "true")
    check("expired later", T.bool(S.Store.expired(S.Meta{"a/b", N.Size.of(1), 1000}, 4000000000)), "true")
    check("clock back", T.bool(S.Store.expired(S.Meta{"a/b", N.Size.of(1), 1000}, 999)), "false")
    check("hit renews", T.meta(S.Store.hit("oci-cache-meta 1\nmedia-type a/b\nsize 1\nlast-use 1000\n", 900000)),
      "oci-cache-meta 1\nmedia-type a/b\nsize 1\nlast-use 900000\n")
    check("sweep", String.join(S.Store.sweep("/c", 300000, [
      S.Item{"docker.io", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", Some{"oci-cache-meta 1\nmedia-type a/b\nsize 1\nlast-use 1000\n"}},
      S.Item{"docker.io", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", Some{"oci-cache-meta 1\nmedia-type a/b\nsize 1\nlast-use 200000\n"}},
      S.Item{"..", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", None{}}]), " "),
      "/c/docker.io/blobs/sha256/e3/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 /c/docker.io/blobs/sha256/e3/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.meta")
    check("prune", String.join(S.Store.prune("/c", ["docker.io", "a/b", "quay.io"]), " "), "/c/tmp /c/docker.io /c/quay.io")
    check("verified", T.bool(S.Store.verified("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", Some{N.Size.zero()}, N.Size.zero())), "true")
    check("verified wrong", T.bool(S.Store.verified("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", None{}, N.Size.zero())), "false")
