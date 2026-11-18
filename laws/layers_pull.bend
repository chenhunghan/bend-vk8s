import Base
import ../src/layers/pull.bend as P
import ../src/layers/tar.bend as T
import ../src/oci/size.bend as N

# Spec for src/layers/pull.bend: which image a reference names, what to
# ask the image cache, and what its answers mean.
#
# Proposed: every law of this file is new (feat/layers-fill). Sources:
# - references: distribution/reference normalize_test.go
#   (TestParseDockerRef, TestParseRepositoryInfo, TestValidateRemoteName),
#   ParseDockerRef's results split into registry, repository and tag or
#   digest;
# - requests: distribution-spec spec.md ("GET /v2/<name>/manifests/
#   <reference>", "GET /v2/<name>/blobs/<digest>") with containerd's
#   resolver Accept list (core/remotes/docker/resolver.go);
# - response heads: RFC 9110 (Content-Length) and RFC 9112 (the head ends
#   with CRLF CRLF);
# - manifests and configs: the examples of image-spec image-index.md,
#   manifest.md and config.md, without their annotations and subject;
#   the platform variants of containerd platforms.Normalize;
# - compression: containerd core/images/mediatypes.go DiffCompression and
#   the vectors of pkg/archive/compression/compression_test.go;
# - chain IDs: image-spec config.md, as Python hashlib sha256 hex digests;
#   the empty descriptor's digest: image-spec manifest.md;
# - the cache's ports: vk8s's image cache (src/guest/plan.bend
#   Plan.mirrors, user decision).

def layers_pull.fx.mirrors() -> List<&2, P.Mirror>:
  [P.Mirror{"docker.io", 15001}, P.Mirror{"registry.k8s.io", 15002}, P.Mirror{"ghcr.io", 15003}, P.Mirror{"quay.io", 15004}]

# image-index.md's example, without its annotations.
def layers_pull.fx.index() -> String:
  "{\"schemaVersion\":2,\"mediaType\":\"application/vnd.oci.image.index.v1+json\",\"manifests\":[{\"mediaType\":\"application/vnd.oci.image.manifest.v1+json\",\"size\":7143,\"digest\":\"sha256:e692418e4cbaf90ca69d05a66403747baa33ee08806650b51fab815ad7fc331f\",\"platform\":{\"architecture\":\"ppc64le\",\"os\":\"linux\"}},{\"mediaType\":\"application/vnd.oci.image.manifest.v1+json\",\"size\":7682,\"digest\":\"sha256:5b0bcabd1ed22e9fb1310cf6c2dec7cdef19f0ad69efa1f392e94a4333501270\",\"platform\":{\"architecture\":\"amd64\",\"os\":\"linux\"}}]}"

# manifest.md's example, without its subject and annotations.
def layers_pull.fx.manifest() -> String:
  "{\"schemaVersion\":2,\"mediaType\":\"application/vnd.oci.image.manifest.v1+json\",\"config\":{\"mediaType\":\"application/vnd.oci.image.config.v1+json\",\"digest\":\"sha256:b5b2b2c507a0944348e0303114d8d93aaaa081732b86451d9bce1f432a537bc7\",\"size\":7023},\"layers\":[{\"mediaType\":\"application/vnd.oci.image.layer.v1.tar+gzip\",\"digest\":\"sha256:9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0\",\"size\":32654},{\"mediaType\":\"application/vnd.oci.image.layer.v1.tar+gzip\",\"digest\":\"sha256:3c3a4604a545cdc127456d94e421cd355bca5b528f4a9c1905b15da2eb4a4c6b\",\"size\":16724},{\"mediaType\":\"application/vnd.oci.image.layer.v1.tar+gzip\",\"digest\":\"sha256:ec4b8955958665577945c89419d1af06b5f7636b4ac3da7f12184802ad867736\",\"size\":73109}]}"

def layers_pull.fx.gz(d: String, +n: U32) -> P.Desc:
  P.Desc{"application/vnd.oci.image.layer.v1.tar+gzip", d, N.Size{0, n}}

# References (TestParseDockerRef)
# ----------

law layers_pull.ref.nothing:
  {P.Pull.ref("busybox") == Some{P.Img{"docker.io", "library/busybox", "latest", False{}}} : Maybe<&2, P.Img>}

law layers_pull.ref.tag_only:
  {P.Pull.ref("busybox:latest") == Some{P.Img{"docker.io", "library/busybox", "latest", False{}}} : Maybe<&2, P.Img>}

law layers_pull.ref.digest_only:
  {P.Pull.ref("busybox@sha256:e6693c20186f837fc393390135d8a598a96a833917917789d63766cab6c59582") == Some{P.Img{"docker.io", "library/busybox", "sha256:e6693c20186f837fc393390135d8a598a96a833917917789d63766cab6c59582", True{}}} : Maybe<&2, P.Img>}

law layers_pull.ref.path_only:
  {P.Pull.ref("library/busybox") == Some{P.Img{"docker.io", "library/busybox", "latest", False{}}} : Maybe<&2, P.Img>}

law layers_pull.ref.hostname_only:
  {P.Pull.ref("docker.io/busybox") == Some{P.Img{"docker.io", "library/busybox", "latest", False{}}} : Maybe<&2, P.Img>}

law layers_pull.ref.no_tag:
  {P.Pull.ref("docker.io/library/busybox") == Some{P.Img{"docker.io", "library/busybox", "latest", False{}}} : Maybe<&2, P.Img>}

law layers_pull.ref.no_path:
  {P.Pull.ref("docker.io/busybox:latest") == Some{P.Img{"docker.io", "library/busybox", "latest", False{}}} : Maybe<&2, P.Img>}

law layers_pull.ref.no_hostname:
  {P.Pull.ref("library/busybox:latest") == Some{P.Img{"docker.io", "library/busybox", "latest", False{}}} : Maybe<&2, P.Img>}

law layers_pull.ref.full:
  {P.Pull.ref("docker.io/library/busybox:latest") == Some{P.Img{"docker.io", "library/busybox", "latest", False{}}} : Maybe<&2, P.Img>}

law layers_pull.ref.gcr_no_tag:
  {P.Pull.ref("gcr.io/library/busybox") == Some{P.Img{"gcr.io", "library/busybox", "latest", False{}}} : Maybe<&2, P.Img>}

# With a tag and a digest, only the digest stays.
law layers_pull.ref.tag_and_digest:
  {P.Pull.ref("gcr.io/library/busybox:latest@sha256:e6693c20186f837fc393390135d8a598a96a833917917789d63766cab6c59582") == Some{P.Img{"gcr.io", "library/busybox", "sha256:e6693c20186f837fc393390135d8a598a96a833917917789d63766cab6c59582", True{}}} : Maybe<&2, P.Img>}

law layers_pull.ref.show:
  {P.Pull.show(P.Img{"gcr.io", "library/busybox", "sha256:e6693c20186f837fc393390135d8a598a96a833917917789d63766cab6c59582", True{}}) == "gcr.io/library/busybox@sha256:e6693c20186f837fc393390135d8a598a96a833917917789d63766cab6c59582" : String}

# References (TestParseRepositoryInfo, TestValidateRemoteName)
# ----------

law layers_pull.ref.localhost:
  {P.Pull.ref("localhost/fooo/bar") == Some{P.Img{"localhost", "fooo/bar", "latest", False{}}} : Maybe<&2, P.Img>}

law layers_pull.ref.upper_domain:
  {P.Pull.ref("LOCALDOMAIN/fooo") == Some{P.Img{"LOCALDOMAIN", "fooo", "latest", False{}}} : Maybe<&2, P.Img>}

law layers_pull.ref.ip_port:
  {P.Pull.ref("127.0.0.1:8000/private/moonbase") == Some{P.Img{"127.0.0.1:8000", "private/moonbase", "latest", False{}}} : Maybe<&2, P.Img>}

law layers_pull.ref.legacy_index:
  {P.Pull.ref("index.docker.io/library/ubuntu-12.04-base") == Some{P.Img{"docker.io", "library/ubuntu-12.04-base", "latest", False{}}} : Maybe<&2, P.Img>}

law layers_pull.ref.legacy_index_official:
  {P.Pull.ref("index.docker.io/debian") == Some{P.Img{"docker.io", "library/debian", "latest", False{}}} : Maybe<&2, P.Img>}

law layers_pull.ref.not_lowercase:
  {P.Pull.ref("docker/Docker") == None{} : Maybe<&2, P.Img>}

law layers_pull.ref.slashes:
  {P.Pull.ref("docker///docker") == None{} : Maybe<&2, P.Img>}

law layers_pull.ref.hex64:
  {P.Pull.ref("1a3f5e7d9c1b3a5f7e9d1c3b5a7f9e1d3c5b7a9f1e3d5d7c9b1a3f5e7d9c1b3a") == None{} : Maybe<&2, P.Img>}

law layers_pull.ref.no_repository:
  {P.Pull.ref("docker/") == None{} : Maybe<&2, P.Img>}

# The image cache
# ---------------

law layers_pull.port:
  {P.Pull.port(layers_pull.fx.mirrors(), "registry.k8s.io") == Some{15002} : Maybe<&2, U32>}

law layers_pull.port_none:
  {P.Pull.port(layers_pull.fx.mirrors(), "gcr.io") == None{} : Maybe<&2, U32>}

# Requests
# --------

law layers_pull.get.manifest:
  {P.Pull.get.manifest(15001, "library/busybox", "latest") == "GET /v2/library/busybox/manifests/latest HTTP/1.1\r\nHost: 127.0.0.1:15001\r\nUser-Agent: vk8s\r\nAccept: application/vnd.docker.distribution.manifest.v2+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.oci.image.index.v1+json, */*\r\nConnection: close\r\n\r\n" : String}

law layers_pull.get.blob:
  {P.Pull.get.blob(15002, "pause", "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a") == "GET /v2/pause/blobs/sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a HTTP/1.1\r\nHost: 127.0.0.1:15002\r\nUser-Agent: vk8s\r\nAccept: */*\r\nConnection: close\r\n\r\n" : String}

# Responses
# ---------

law layers_pull.got.head:
  {P.Pull.got(T.Tar.b("HTTP/1.1 200 OK\r\nContent-Type: application/vnd.oci.image.index.v1+json\r\nContent-Length: 2\r\n\r\n{}")) == P.GHead{200, Some{N.Size{0, 2}}, [123, 125]} : P.Got}

law layers_pull.got.more:
  {P.Pull.got(T.Tar.b("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n")) == P.GMore{} : P.Got}

law layers_pull.got.big:
  {P.Pull.got(T.Tar.b("HTTP/1.1 200 OK\r\nContent-Length: 5368709120\r\n\r\n")) == P.GHead{200, Some{N.Size{1, 1073741824}}, []} : P.Got}

law layers_pull.got.not_found:
  {P.Pull.got(T.Tar.b("HTTP/1.1 404 Not Found\r\n\r\n")) == P.GHead{404, None{}, []} : P.Got}

# The empty descriptor: "{}" has digest sha256:44136fa3...
law layers_pull.verified:
  {P.Pull.verified("sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a", [123, 125]) == True{} : Bool}

law layers_pull.verified_not:
  {P.Pull.verified("sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a", [123, 32, 125]) == False{} : Bool}

# Manifests
# ---------

law layers_pull.index.amd64:
  {P.Pull.manifest("amd64", layers_pull.fx.index()) == P.MIndex{"sha256:5b0bcabd1ed22e9fb1310cf6c2dec7cdef19f0ad69efa1f392e94a4333501270"} : P.Man}

law layers_pull.index.ppc64le:
  {P.Pull.manifest("ppc64le", layers_pull.fx.index()) == P.MIndex{"sha256:e692418e4cbaf90ca69d05a66403747baa33ee08806650b51fab815ad7fc331f"} : P.Man}

law layers_pull.index.none:
  {P.Pull.manifest("arm64", layers_pull.fx.index()) == P.MBad{"no linux/arm64 image in the image index"} : P.Man}

# platforms.Normalize: arm64/v8 is arm64.
law layers_pull.index.arm64_v8:
  {P.Pull.manifest("arm64", "{\"manifests\":[{\"mediaType\":\"application/vnd.oci.image.manifest.v1+json\",\"size\":7143,\"digest\":\"sha256:e692418e4cbaf90ca69d05a66403747baa33ee08806650b51fab815ad7fc331f\",\"platform\":{\"architecture\":\"arm\",\"os\":\"linux\",\"variant\":\"v7\"}},{\"mediaType\":\"application/vnd.oci.image.manifest.v1+json\",\"size\":7682,\"digest\":\"sha256:5b0bcabd1ed22e9fb1310cf6c2dec7cdef19f0ad69efa1f392e94a4333501270\",\"platform\":{\"architecture\":\"arm64\",\"os\":\"linux\",\"variant\":\"v8\"}}]}") == P.MIndex{"sha256:5b0bcabd1ed22e9fb1310cf6c2dec7cdef19f0ad69efa1f392e94a4333501270"} : P.Man}

law layers_pull.manifest:
  {P.Pull.manifest("amd64", layers_pull.fx.manifest()) == P.MImage{
    P.Desc{"application/vnd.oci.image.config.v1+json", "sha256:b5b2b2c507a0944348e0303114d8d93aaaa081732b86451d9bce1f432a537bc7", N.Size{0, 7023}},
    [layers_pull.fx.gz("sha256:9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0", 32654),
     layers_pull.fx.gz("sha256:3c3a4604a545cdc127456d94e421cd355bca5b528f4a9c1905b15da2eb4a4c6b", 16724),
     layers_pull.fx.gz("sha256:ec4b8955958665577945c89419d1af06b5f7636b4ac3da7f12184802ad867736", 73109)]} : P.Man}

law layers_pull.manifest.neither:
  {P.Pull.manifest("amd64", "{\"schemaVersion\":2}") == P.MBad{"neither an image index nor an image manifest"} : P.Man}

# Configs (config.md's example rootfs)
# -------

law layers_pull.config:
  {P.Pull.config("{\"rootfs\":{\"diff_ids\":[\"sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1\",\"sha256:5f70bf18a086007016e948b04aed3b82103a36bea41755b6cddfaf10ace3c6ef\"],\"type\":\"layers\"}}") == Some{["sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1", "sha256:5f70bf18a086007016e948b04aed3b82103a36bea41755b6cddfaf10ace3c6ef"]} : Maybe<&2, List<&2, String>>}

# rootfs.type must be "layers".
law layers_pull.config.type:
  {P.Pull.config("{\"rootfs\":{\"diff_ids\":[],\"type\":\"other\"}}") == None{} : Maybe<&2, List<&2, String>>}

# Compression (DiffCompression)
# -----------

law layers_pull.comp.oci_gzip:
  {P.Pull.comp("application/vnd.oci.image.layer.v1.tar+gzip") == P.CGzip{} : P.Comp}

law layers_pull.comp.oci_zstd:
  {P.Pull.comp("application/vnd.oci.image.layer.v1.tar+zstd") == P.CZstd{} : P.Comp}

law layers_pull.comp.oci_plain:
  {P.Pull.comp("application/vnd.oci.image.layer.v1.tar") == P.CNone{} : P.Comp}

law layers_pull.comp.nondistributable:
  {P.Pull.comp("application/vnd.oci.image.layer.nondistributable.v1.tar+gzip") == P.CGzip{} : P.Comp}

law layers_pull.comp.docker_gzip:
  {P.Pull.comp("application/vnd.docker.image.rootfs.diff.tar.gzip") == P.CGzip{} : P.Comp}

law layers_pull.comp.docker_foreign_gzip:
  {P.Pull.comp("application/vnd.docker.image.rootfs.foreign.diff.tar.gzip") == P.CGzip{} : P.Comp}

law layers_pull.comp.docker_zstd:
  {P.Pull.comp("application/vnd.docker.image.rootfs.diff.tar.zstd") == P.CZstd{} : P.Comp}

# "unknown": the blob's first bytes say.
law layers_pull.comp.docker_plain:
  {P.Pull.comp("application/vnd.docker.image.rootfs.diff.tar") == P.CSniff{} : P.Comp}

law layers_pull.comp.encrypted:
  {P.Pull.comp("application/vnd.oci.image.layer.v1.tar+gzip+encrypted") == P.CBad{"encrypted layers are not supported: application/vnd.oci.image.layer.v1.tar+gzip+encrypted"} : P.Comp}

law layers_pull.comp.unrecognised:
  {P.Pull.comp("application/vnd.oci.image.config.v1+json") == P.CBad{"unrecognised layer media type application/vnd.oci.image.config.v1+json"} : P.Comp}

# DetectCompression
# -----------------

law layers_pull.sniff.gzip:
  {P.Pull.sniff([31, 139, 8, 0, 0, 0, 0, 0]) == P.CGzip{} : P.Comp}

# TestDetectCompressionZstd: a Zstandard frame.
law layers_pull.sniff.zstd:
  {P.Pull.sniff([40, 181, 47, 253, 4, 0, 49, 0, 0, 100, 111, 99, 107, 101, 114, 22, 14, 33, 195]) == P.CZstd{} : P.Comp}

# TestDetectCompressionZstd: a skippable frame first.
law layers_pull.sniff.skippable:
  {P.Pull.sniff([80, 42, 77, 24, 4, 0, 0, 0, 93, 0, 0, 0, 40, 181, 47, 253]) == P.CZstd{} : P.Comp}

law layers_pull.sniff.plain:
  {P.Pull.sniff([104, 101, 108, 108, 111, 10]) == P.CNone{} : P.Comp}

# Layers
# ------

# config.md's diffIDs: ChainID(L0) = DiffID(L0), ChainID(L0|L1) =
# sha256("<ChainID(L0)> <DiffID(L1)>").
law layers_pull.fills:
  {P.Pull.fills(["sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1", "sha256:5f70bf18a086007016e948b04aed3b82103a36bea41755b6cddfaf10ace3c6ef"],
    [layers_pull.fx.gz("sha256:9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0", 32654),
     layers_pull.fx.gz("sha256:3c3a4604a545cdc127456d94e421cd355bca5b528f4a9c1905b15da2eb4a4c6b", 16724)]) == Some{[
    P.Fill{"sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1", "sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1", "",
      layers_pull.fx.gz("sha256:9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0", 32654), P.CGzip{}},
    P.Fill{"sha256:c3191d32a37d7159b2e30830937d2e30268ad6c375a773a8994911a3aba9b93f", "sha256:5f70bf18a086007016e948b04aed3b82103a36bea41755b6cddfaf10ace3c6ef", "sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1",
      layers_pull.fx.gz("sha256:3c3a4604a545cdc127456d94e421cd355bca5b528f4a9c1905b15da2eb4a4c6b", 16724), P.CGzip{}}]} : Maybe<&2, List<&2, P.Fill>>}

# containerd: "mismatched image rootfs and manifest layers".
law layers_pull.fills.mismatch:
  {P.Pull.fills(["sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1"], []) == None{} : Maybe<&2, List<&2, P.Fill>>}
