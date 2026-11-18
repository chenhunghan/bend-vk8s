import Base
import ../src/layers/pull.bend as P
import ../src/layers/tar.bend as T

# Tests for src/layers/pull.bend. References are cases of
# distribution/reference normalize_test.go; the manifest is image-spec
# manifest.md's example (without subject and annotations).

def report(name: String, got: String, want: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name ++ ": got " ++ got ++ ", want " ++ want)

def check(name: String, +got: String, +want: String) -> IO(Unit):
  report(name, got, want, String.eq(got, want))

def X.ref(m: Maybe<&2, P.Img>) -> String:
  match m:
    case None{}:
      "<none>"
    case Some{i}:
      P.Pull.show(i)

def X.man(m: P.Man) -> String:
  match m:
    case P.MIndex{d}:
      "index " ++ d
    case P.MImage{c, ls}:
      "image " ++ P.Desc.digest(c) ++ " " ++ U32.show(U32.from_nat(List.length(&2, P.Desc, ls)))
    case P.MBad{w}:
      "bad " ++ w

def X.comp(c: P.Comp) -> String:
  match c:
    case P.CNone{}:
      "none"
    case P.CGzip{}:
      "gzip"
    case P.CZstd{}:
      "zstd"
    case P.CSniff{}:
      "sniff"
    case P.CBad{w}:
      "bad " ++ w

def X.got(g: P.Got) -> String:
  match g:
    case P.GMore{}:
      "more"
    case P.GBad{w}:
      "bad " ++ w
    case P.GHead{s, l, b}:
      "head " ++ U32.show(s) ++ " " ++ U32.show(U32.from_nat(List.length(&2, U32, b)))

def main() -> IO(Unit):
  do IO<Unit>:
    check("official image", X.ref(P.Pull.ref("busybox")), "docker.io/library/busybox:latest")
    check("tag and digest", X.ref(P.Pull.ref("gcr.io/library/busybox:latest@sha256:e6693c20186f837fc393390135d8a598a96a833917917789d63766cab6c59582")),
      "gcr.io/library/busybox@sha256:e6693c20186f837fc393390135d8a598a96a833917917789d63766cab6c59582")
    check("registry with a port", X.ref(P.Pull.ref("localhost:5000/a/b:v1")), "localhost:5000/a/b:v1")
    check("uppercase repository", X.ref(P.Pull.ref("docker/Docker")), "<none>")
    check("registry.k8s.io pause", X.ref(P.Pull.ref("registry.k8s.io/pause:3.10")), "registry.k8s.io/pause:3.10")
    check("manifest", X.man(P.Pull.manifest("arm64", "{\"schemaVersion\":2,\"config\":{\"mediaType\":\"application/vnd.oci.image.config.v1+json\",\"digest\":\"sha256:b5b2b2c507a0944348e0303114d8d93aaaa081732b86451d9bce1f432a537bc7\",\"size\":7023},\"layers\":[{\"mediaType\":\"application/vnd.oci.image.layer.v1.tar+gzip\",\"digest\":\"sha256:9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0\",\"size\":32654}]}")),
      "image sha256:b5b2b2c507a0944348e0303114d8d93aaaa081732b86451d9bce1f432a537bc7 1")
    check("docker list, arm64", X.man(P.Pull.manifest("arm64", "{\"mediaType\":\"application/vnd.docker.distribution.manifest.list.v2+json\",\"manifests\":[{\"digest\":\"sha256:5b0bcabd1ed22e9fb1310cf6c2dec7cdef19f0ad69efa1f392e94a4333501270\",\"platform\":{\"architecture\":\"amd64\",\"os\":\"linux\"}},{\"digest\":\"sha256:e692418e4cbaf90ca69d05a66403747baa33ee08806650b51fab815ad7fc331f\",\"platform\":{\"architecture\":\"arm64\",\"os\":\"linux\",\"variant\":\"v8\"}}]}")),
      "index sha256:e692418e4cbaf90ca69d05a66403747baa33ee08806650b51fab815ad7fc331f")
    check("gzip layer", X.comp(P.Pull.comp("application/vnd.oci.image.layer.v1.tar+gzip")), "gzip")
    check("docker plain layer sniffs", X.comp(P.Pull.comp("application/vnd.docker.image.rootfs.diff.tar")), "sniff")
    check("gzip magic", X.comp(P.Pull.sniff([31, 139, 8, 0, 0, 0, 0, 0])), "gzip")
    check("response head", X.got(P.Pull.got(T.Tar.b("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}"))), "head 200 2")
    check("response head pending", X.got(P.Pull.got(T.Tar.b("HTTP/1.1 200 OK\r\n"))), "more")
