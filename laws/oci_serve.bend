import Base
import ../src/oci/serve.bend as S
import ../src/oci/route.bend as R
import ../src/oci/size.bend as N

# Spec for src/oci/serve.bend: the image cache mirror's HTTP/1.1 side on
# the host. Expected values come from RFC 9112 (the request line, header
# fields: a field name is case-insensitive, its value trimmed), Go's
# net/http StatusText (reason phrases), CNCF distribution's errcode
# messages (registry/api/v2/errors.go: "blob unknown to registry",
# "manifest unknown"), and src/oci/fill.bend's machine (a follower is cut
# off before the last byte of a fill that is not committed).

# Proposed: every law of this file (new module, feat/no-cache-vm).

# containerd asks a mirror for content by digest, with ?ns= (resolver.go).
law oci_serve.request.containerd:
  {S.Serve.request("GET /v2/library/busybox/blobs/sha256:00?ns=docker.io HTTP/1.1\r\nHost: 10.0.2.2:15001\r\nrange:  bytes=0-9 \r\nUser-Agent: containerd/v2.2.3")
    == Some{S.Rq{"GET", "/v2/library/busybox/blobs/sha256:00?ns=docker.io",
      [R.Hdr{"Host", "10.0.2.2:15001"}, R.Hdr{"range", "bytes=0-9"}, R.Hdr{"User-Agent", "containerd/v2.2.3"}]}} : Maybe<&2, S.Rq>}
law oci_serve.request.get_range:
  {Maybe.default(&2, String, S.Serve.get(S.Rq{"GET", "/", [R.Hdr{"Range", "bytes=0-9"}]}, "range"), "") == "bytes=0-9" : String}
law oci_serve.request.http10:
  {S.Serve.request("HEAD /v2/ HTTP/1.0") == Some{S.Rq{"HEAD", "/v2/", []}} : Maybe<&2, S.Rq>}
law oci_serve.request.not_http:
  {S.Serve.request("GET /v2/ SPDY/3") == None{} : Maybe<&2, S.Rq>}
law oci_serve.request.no_target:
  {S.Serve.request("GET HTTP/1.1") == None{} : Maybe<&2, S.Rq>}

# The ping, rendered: status line, the route's fields, Connection: close.
law oci_serve.render.ping:
  {S.Serve.render(R.Route.ping(False{}))
    == "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\nDocker-Distribution-API-Version: registry/2.0\r\nConnection: close\r\n\r\n{}" : String}
law oci_serve.render.head:
  {S.Serve.render(R.Route.ping(True{}))
    == "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\nDocker-Distribution-API-Version: registry/2.0\r\nConnection: close\r\n\r\n" : String}
# StatusText.
law oci_serve.reason:
  {[S.Serve.reason(206), S.Serve.reason(416), S.Serve.reason(429), S.Serve.reason(502), S.Serve.reason(504)]
    == ["Partial Content", "Requested Range Not Satisfiable", "Too Many Requests", "Bad Gateway", "Gateway Timeout"] : List<&2, String>}

# The fill machine's replies: an OCI error body, or none for 502 and 504.
law oci_serve.reply.blob_unknown:
  {S.Serve.reply(False{}, 404, "BLOB_UNKNOWN") == R.Route.blob_unknown(False{}) : R.Resp}
law oci_serve.reply.manifest_unknown:
  {S.Serve.reply(False{}, 404, "MANIFEST_UNKNOWN") == R.Route.manifest_unknown(False{}) : R.Resp}
law oci_serve.reply.bad_gateway:
  {S.Serve.render(S.Serve.reply(False{}, 502, ""))
    == "HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nDocker-Distribution-API-Version: registry/2.0\r\nConnection: close\r\n\r\n" : String}

# Following a fill of 10 bytes: the last byte waits for the commit.
law oci_serve.follow.held:
  {S.Serve.follow(N.Size.zero(), N.Size.of(10), N.Size.of(10), False{}) == S.FwSend{N.Size.of(9)} : S.Fw}
law oci_serve.follow.partial:
  {S.Serve.follow(N.Size.of(2), N.Size.of(6), N.Size.of(10), False{}) == S.FwSend{N.Size.of(6)} : S.Fw}
law oci_serve.follow.wait:
  {S.Serve.follow(N.Size.of(9), N.Size.of(10), N.Size.of(10), False{}) == S.FwWait{} : S.Fw}
law oci_serve.follow.committed:
  {S.Serve.follow(N.Size.of(9), N.Size.of(10), N.Size.of(10), True{}) == S.FwSend{N.Size.of(10)} : S.Fw}
law oci_serve.follow.done:
  {S.Serve.follow(N.Size.of(10), N.Size.of(10), N.Size.of(10), True{}) == S.FwDone{} : S.Fw}
# Past 4 GiB: 2^32 + 5 bytes, 2^32 on disk.
law oci_serve.follow.big:
  {S.Serve.follow(N.Size.zero(), N.Size{1, 0}, N.Size{1, 5}, False{}) == S.FwSend{N.Size{1, 0}} : S.Fw}

# Sizes in KiB, rounded down, past 4 GiB too.
law oci_serve.kib:
  {[S.Serve.kib(N.Size.of(1023)), S.Serve.kib(N.Size.of(2048)), S.Serve.kib(N.Size{1, 1024})] == [0, 2, 4194305] : List<&2, U32>}

# Proposed: the laws below (feat/fast-cold-pull): what a miss does.
# Expected values come from containerd core/remotes/docker/resolver.go
# (Resolve sends HEAD manifests/<digest> to each host in order and tries
# the next host on a 404) and the OCI distribution spec ("Checking if
# content exists": HEAD of a manifest or a blob).
law oci_serve.miss.get_blob:
  {S.Serve.miss.fills(False{}, False{}) == True{} : Bool}
law oci_serve.miss.get_manifest:
  {S.Serve.miss.fills(False{}, True{}) == True{} : Bool}
law oci_serve.miss.head_manifest:
  {S.Serve.miss.fills(True{}, True{}) == True{} : Bool}
law oci_serve.miss.head_blob:
  {S.Serve.miss.fills(True{}, False{}) == False{} : Bool}
