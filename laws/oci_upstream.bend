import Base
import ../src/oci/upstream.bend as U
import ../src/oci/auth.bend as A

# Spec for src/oci/upstream.bend: the host's registry client (the layer
# filler and the image cache's mirror). Expected values come from:
# - containerd core/remotes/docker/config/hosts.go (docker.io's API host
#   is "registry-1.docker.io", every other registry is "https://" and its
#   own name),
# - Go's net/http Request.Write (the request line carries RequestURI, the
#   path and query; Host is URL.Host, its port kept as written),
# - distribution docs/spec/auth/token.md (the Docker Hub challenge and its
#   token request), containerd core/remotes/docker/scope.go
#   (RepositoryScope: "repository:" + name + ":pull") and authorizer.go
#   (a second 401 after a token is final),
# - RFC 9110 section 15.4 and src/oci/auth.bend's redirect laws (a
#   registry's blob redirect to object storage drops Authorization).

# Proposed: every law of this file (new module, feat/no-cache-vm).

# hosts.go: "docker.io" is served at registry-1.docker.io.
law oci_upstream.base.docker_hub:
  {U.Up.base("docker.io") == "https://registry-1.docker.io" : String}
law oci_upstream.base.other:
  {U.Up.base("registry.k8s.io") == "https://registry.k8s.io" : String}
law oci_upstream.url.manifest:
  {U.Up.url("https://registry-1.docker.io", "library/busybox", "manifests", "latest")
    == "https://registry-1.docker.io/v2/library/busybox/manifests/latest" : String}

# Request.Write: "GET /v2/... HTTP/1.1", Host as in the URL.
law oci_upstream.request.anonymous:
  {U.Up.request("https://registry-1.docker.io/v2/library/busybox/manifests/latest", "*/*", "")
    == "GET /v2/library/busybox/manifests/latest HTTP/1.1\r\nHost: registry-1.docker.io\r\nUser-Agent: vk8s\r\nAccept: */*\r\nConnection: close\r\n\r\n" : String}
law oci_upstream.request.token:
  {U.Up.request("https://registry.k8s.io/v2/pause/blobs/sha256:00", "*/*", U.Up.bearer_auth("t0k"))
    == "GET /v2/pause/blobs/sha256:00 HTTP/1.1\r\nHost: registry.k8s.io\r\nUser-Agent: vk8s\r\nAccept: */*\r\nAuthorization: Bearer t0k\r\nConnection: close\r\n\r\n" : String}
# RequestURI keeps the query (a signed storage URL) and drops the fragment.
law oci_upstream.request.query:
  {U.Up.request("https://storage.example.com:8443/b/x?sig=a%2Fb&exp=1#frag", "*/*", "")
    == "GET /b/x?sig=a%2Fb&exp=1 HTTP/1.1\r\nHost: storage.example.com:8443\r\nUser-Agent: vk8s\r\nAccept: */*\r\nConnection: close\r\n\r\n" : String}
law oci_upstream.request.root:
  {U.Up.request("https://ghcr.io", "*/*", "")
    == "GET / HTTP/1.1\r\nHost: ghcr.io\r\nUser-Agent: vk8s\r\nAccept: */*\r\nConnection: close\r\n\r\n" : String}

# Where to dial: the hostname (lowercase) and the effective port.
law oci_upstream.dial.default_port:
  {U.Up.dial("https://Registry-1.Docker.io/v2/") == ("registry-1.docker.io", 443) : String & U32}
law oci_upstream.dial.port:
  {U.Up.dial("https://127.0.0.1:15443/v2/") == ("127.0.0.1", 15443) : String & U32}
law oci_upstream.dialable.https:
  {U.Up.dialable("https://quay.io/v2/") == True{} : Bool}
law oci_upstream.dialable.http:
  {U.Up.dialable("http://quay.io/v2/") == False{} : Bool}

# token.md: the challenge of a pull, answered with a token request.
law oci_upstream.next.challenge:
  {U.Up.next(401, "https://registry-1.docker.io/v2/samalba/my-app/manifests/latest", 0, False{}, "",
     ["Bearer realm=\"https://auth.docker.io/token\",service=\"registry.docker.io\",scope=\"repository:samalba/my-app:pull,push\""])
    == U.Token{A.Bearer{"https://auth.docker.io/token", "registry.docker.io", ["repository:samalba/my-app:pull,push"]}} : U.Next}
# authorizer.go: a 401 after the token was sent is the answer.
law oci_upstream.next.second_401:
  {U.Up.next(401, "https://registry-1.docker.io/v2/samalba/my-app/manifests/latest", 0, True{}, "",
     ["Bearer realm=\"https://auth.docker.io/token\",service=\"registry.docker.io\",scope=\"repository:samalba/my-app:pull,push\""])
    == U.Final{} : U.Next}
# A 401 with no Bearer challenge (Basic: credentials only) is the answer.
law oci_upstream.next.basic:
  {U.Up.next(401, "https://quay.io/v2/a/b/manifests/1", 0, False{}, "", ["Basic realm=\"quay\""]) == U.Final{} : U.Next}
# proxyauth.go realmAllowed: a realm on another domain is not used.
law oci_upstream.next.foreign_realm:
  {U.Up.next(401, "https://quay.io/v2/a/b/manifests/1", 0, False{}, "", ["Bearer realm=\"https://evil.example/token\""]) == U.Final{} : U.Next}
# A blob redirect to object storage: followed, without Authorization.
law oci_upstream.next.storage:
  {U.Up.next(307, "https://registry.k8s.io/v2/pause/blobs/sha256:00", 0, True{}, "https://us-west1-docker.pkg.dev/v2/k8s-artifacts-prod/images/pause/blobs/sha256:00", [])
    == U.Hop{"https://us-west1-docker.pkg.dev/v2/k8s-artifacts-prod/images/pause/blobs/sha256:00", False{}} : U.Next}
law oci_upstream.next.same_origin:
  {U.Up.next(302, "https://ghcr.io/v2/a/b/blobs/sha256:00", 0, True{}, "/v2/a/c/blobs/sha256:00", [])
    == U.Hop{"https://ghcr.io/v2/a/c/blobs/sha256:00", True{}} : U.Next}
law oci_upstream.next.http_refused:
  {U.Up.next(302, "https://ghcr.io/v2/a/b/blobs/sha256:00", 0, False{}, "http://ghcr.io/x", []) == U.Stop{"redirect to a non-https URL"} : U.Next}
law oci_upstream.next.hop_limit:
  {U.Up.next(302, "https://ghcr.io/v2/a/b/blobs/sha256:00", 10, False{}, "https://ghcr.io/x", []) == U.Stop{"stopped after 10 redirects"} : U.Next}
law oci_upstream.next.ok:
  {U.Up.next(200, "https://ghcr.io/v2/a/b/blobs/sha256:00", 0, False{}, "", []) == U.Final{} : U.Next}
law oci_upstream.next.not_found:
  {U.Up.next(404, "https://ghcr.io/v2/a/b/blobs/sha256:00", 0, False{}, "", []) == U.Final{} : U.Next}

# scope.go RepositoryScope: a challenge with no scope gets the pull scope.
law oci_upstream.scoped.none:
  {U.Up.scoped(A.Bearer{"https://auth.docker.io/token", "registry.docker.io", []}, "library/busybox")
    == A.Bearer{"https://auth.docker.io/token", "registry.docker.io", ["repository:library/busybox:pull"]} : A.Bearer}
law oci_upstream.scoped.kept:
  {U.Up.scoped(A.Bearer{"https://auth.docker.io/token", "registry.docker.io", ["repository:a/b:pull"]}, "library/busybox")
    == A.Bearer{"https://auth.docker.io/token", "registry.docker.io", ["repository:a/b:pull"]} : A.Bearer}
# token.md's token request for that scope.
law oci_upstream.scoped.token_url:
  {A.Auth.token_url(U.Up.scoped(A.Bearer{"https://auth.docker.io/token", "registry.docker.io", []}, "samalba/my-app"))
    == "https://auth.docker.io/token?scope=repository%3Asamalba%2Fmy-app%3Apull&service=registry.docker.io" : String}

# Response heads: the head is cut at the first CRLF CRLF.
law oci_upstream.cut.found:
  {U.Up.cut([72, 13, 10, 13, 10, 98]) == U.Cut{[72], [98], True{}} : U.Cut}
law oci_upstream.cut.more:
  {U.Up.cut([72, 13, 10, 13]) == U.Cut{[72, 13, 10, 13], [], False{}} : U.Cut}
# The token of a pull asked before its first request (a ping of /v2/,
# whose challenge names no repository): the repository's pull scope
# (scope.go RepositoryScope), the challenge's realm and service.
law oci_upstream.repo_scoped:
  {U.Up.repo_scoped(A.Bearer{"https://ghcr.io/token", "ghcr.io", ["repository:user/image:pull"]}, "stefanprodan/podinfo")
    == A.Bearer{"https://ghcr.io/token", "ghcr.io", ["repository:stefanprodan/podinfo:pull"]} : A.Bearer}

# Proposed: the laws below (feat/fill-via-cache): the layer filler asks
# the host image cache (`vk8s cache serve`) over plain HTTP first.
# Expected values come from src/guest/plan.bend Plan.mirrors (docker.io
# on 127.0.0.1:15001, ghcr.io on 15003), Go's net/http Request.Write (as
# above; Host keeps the port), src/oci/route.bend (the cache refuses a
# manifest by tag with 404) and containerd's core/remotes/docker
# resolver.go (a mirror's error sends the pull to the next host).
law oci_upstream.mirror.base:
  {U.Up.mirror(15001) == "http://127.0.0.1:15001" : String}
law oci_upstream.mirror.url:
  {U.Up.url(U.Up.mirror(15003), "stefanprodan/podinfo", "blobs", "sha256:00")
    == "http://127.0.0.1:15003/v2/stefanprodan/podinfo/blobs/sha256:00" : String}
law oci_upstream.mirror.request:
  {U.Up.request("http://127.0.0.1:15001/v2/library/busybox/blobs/sha256:00", "*/*", "")
    == "GET /v2/library/busybox/blobs/sha256:00 HTTP/1.1\r\nHost: 127.0.0.1:15001\r\nUser-Agent: vk8s\r\nAccept: */*\r\nConnection: close\r\n\r\n" : String}
law oci_upstream.mirror.dial:
  {U.Up.dial("http://127.0.0.1:15002/v2/") == ("127.0.0.1", 15002) : String & U32}
# Blobs and manifests by digest go to the cache; a tag goes upstream.
law oci_upstream.mirror.asks.blob:
  {U.Up.mirror.asks("blobs", "sha256:00") == True{} : Bool}
law oci_upstream.mirror.asks.digest:
  {U.Up.mirror.asks("manifests", "sha256:00") == True{} : Bool}
law oci_upstream.mirror.asks.tag:
  {U.Up.mirror.asks("manifests", "latest") == False{} : Bool}
# Plain HTTP only to the loopback cache.
law oci_upstream.plain.loopback:
  {U.Up.plain.dialable("http://127.0.0.1:15001/v2/") == True{} : Bool}
law oci_upstream.plain.remote:
  {U.Up.plain.dialable("http://quay.io/v2/") == False{} : Bool}
law oci_upstream.plain.https:
  {U.Up.plain.dialable("https://127.0.0.1:15001/v2/") == False{} : Bool}
law oci_upstream.plain.localhost_name:
  {U.Up.plain.dialable("http://localhost:15001/v2/") == False{} : Bool}
# The cache's answers.
law oci_upstream.via.ok:
  {U.Up.via(200) == U.Take{} : U.Via}
law oci_upstream.via.tag_refused:
  {U.Up.via(404) == U.Around{"the image cache answered HTTP 404"} : U.Via}
law oci_upstream.via.bad_gateway:
  {U.Up.via(502) == U.Around{"the image cache answered HTTP 502"} : U.Via}
law oci_upstream.via.timeout:
  {U.Up.via(504) == U.Around{"the image cache answered HTTP 504"} : U.Via}
law oci_upstream.via.redirect:
  {U.Up.via(307) == U.Around{"the image cache answered HTTP 307"} : U.Via}

# Proposed: the laws below (feat/fast-cold-pull): the image cache's
# registry client keeps its connections and its tokens. Expected values
# come from RFC 9112 section 9.3 (HTTP/1.1 connections persist unless
# "close" is sent; Go's Request.Write sends no Connection header then),
# RFC 9112 section 9.6 (the "close" option, case-insensitive, in a list),
# containerd's scope.go RepositoryScope and authorizer.go (as above), and
# vk8s's design (connections idle 30 s or more are not reused; at most 8
# kept per host and port, the cache's upstream fetches per registry).
law oci_upstream.request.keep:
  {U.Up.request.keep("https://registry-1.docker.io/v2/library/nginx/blobs/sha256:00", "*/*", U.Up.bearer_auth("t0k"))
    == "GET /v2/library/nginx/blobs/sha256:00 HTTP/1.1\r\nHost: registry-1.docker.io\r\nUser-Agent: vk8s\r\nAccept: */*\r\nAuthorization: Bearer t0k\r\n\r\n" : String}
law oci_upstream.request.keep.anonymous:
  {U.Up.request.keep("https://storage.example.com:8443/b/x?sig=a%2Fb#frag", "*/*", "")
    == "GET /b/x?sig=a%2Fb HTTP/1.1\r\nHost: storage.example.com:8443\r\nUser-Agent: vk8s\r\nAccept: */*\r\n\r\n" : String}
law oci_upstream.keep.default:
  {U.Up.keep("", True{}) == True{} : Bool}
law oci_upstream.keep.keep_alive:
  {U.Up.keep("keep-alive", True{}) == True{} : Bool}
law oci_upstream.keep.close:
  {U.Up.keep("close", True{}) == False{} : Bool}
law oci_upstream.keep.close_listed:
  {U.Up.keep("Keep-Alive, Close", True{}) == False{} : Bool}
# A body that ran to the connection's end, or was not read whole.
law oci_upstream.keep.unframed:
  {U.Up.keep("", False{}) == False{} : Bool}
law oci_upstream.pool.key:
  {U.Up.pool.key("https://production.cloudfront.docker.com/registry-v2/docker/registry/v2/blobs/sha256/9d/9d29/data?Expires=1")
    == "production.cloudfront.docker.com:443" : String}
law oci_upstream.pool.key.port:
  {U.Up.pool.key("https://127.0.0.1:15443/v2/") == "127.0.0.1:15443" : String}
law oci_upstream.pool.fresh:
  {U.Up.pool.fresh(100, 129) == True{} : Bool}
law oci_upstream.pool.stale:
  {U.Up.pool.fresh(100, 130) == False{} : Bool}
law oci_upstream.pool.clock_behind:
  {U.Up.pool.fresh(130, 100) == False{} : Bool}
law oci_upstream.pool.max:
  {U.Up.pool.max() == 8 : U32}
law oci_upstream.pull_scopes:
  {U.Up.pull_scopes("library/nginx") == ["repository:library/nginx:pull"] : +List<String>}
# Docker Hub's challenge names the pull's scope: the token is cached
# under the key the pull's next request looks up.
law oci_upstream.cache_key.docker_hub:
  {U.Up.cache_key("https://registry-1.docker.io/v2/library/nginx/manifests/sha256:00",
     A.Bearer{"https://auth.docker.io/token", "registry.docker.io", ["repository:library/nginx:pull"]}, "library/nginx")
    == A.Auth.cache.key("https://registry-1.docker.io/v2/library/nginx/blobs/sha256:11", U.Up.pull_scopes("library/nginx")) : String}
# A challenge with no scope gets the pull's (scope.go): the same key.
law oci_upstream.cache_key.no_scope:
  {U.Up.cache_key("https://registry.k8s.io/v2/pause/blobs/sha256:00", A.Bearer{"https://registry.k8s.io/token", "registry.k8s.io", []}, "pause")
    == "https://registry.k8s.io:443 repository:pause:pull" : String}
# A challenge for other scopes: cached under them, so the pull's next
# request does not send it.
law oci_upstream.cache_key.other_scope:
  {U.Up.cache_key("https://quay.io/v2/a/b/blobs/sha256:00", A.Bearer{"https://quay.io/v2/auth", "quay.io", ["repository:a/b:pull,push"]}, "a/b")
    == "https://quay.io:443 repository:a/b:pull,push" : String}
