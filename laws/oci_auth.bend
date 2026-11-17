import Base
import ../src/oci/auth.bend as A

# Spec for src/oci/auth.bend: upstream token auth and redirects of the OCI
# pull-through mirror. Expected values come from:
# - containerd core/remotes/docker/auth/parse_test.go (challenges),
# - distribution docs/spec/auth/token.md (the challenge, token request and
#   token response examples; expires_in defaults to and is at least 60 s),
# - Go's url.Values.Encode and url.QueryEscape (the token request URL, as
#   containerd's FetchToken builds it: keys sorted, scope before service),
# - distribution registry/proxy/proxyauth_test.go (realm restrictions),
# - containerd's CheckRedirect ("stopped after 10 redirects") and its
#   isRegistryOrigin / stripSensitiveHeadersForExternalURLs (Authorization
#   only to the same origin), RFC 9110 section 15.4 (redirect statuses),
#   RFC 3986 section 5.2 (resolving a Location), and RFC 1918, 6598, 3927,
#   5735 for the addresses a redirect may not reach.

# parse_test.go TestParseAuthHeaderBearer "SingleScope"
law oci_auth.challenge.single_scope:
  {A.Auth.bearer("Bearer realm=\"https://auth.docker.io/token\",service=\"registry.docker.io\",scope=\"repository:foo/bar:pull,push\"")
    == Some{A.Bearer{"https://auth.docker.io/token", "registry.docker.io", ["repository:foo/bar:pull,push"]}} : Maybe<&2, A.Bearer>}

# parse_test.go TestParseAuthHeaderBearer "MultipleScopes" (fetch.go splits scope on " ")
law oci_auth.challenge.multiple_scopes:
  {A.Auth.bearer("Bearer realm=\"https://auth.docker.io/token\",service=\"registry.docker.io\",scope=\"repository:foo/bar:pull,push repository:foo/baz:pull repository:foo/foo:push\"")
    == Some{A.Bearer{"https://auth.docker.io/token", "registry.docker.io", ["repository:foo/bar:pull,push", "repository:foo/baz:pull", "repository:foo/foo:push"]}} : Maybe<&2, A.Bearer>}

# parse_test.go TestParseAuthHeader: an empty quoted value is kept as ""
law oci_auth.challenge.empty_param:
  {A.Auth.challenge("Bearer realm=\"https://auth.example.io/token\",empty=\"\",service=\"registry.example.io\",scope=\"repository:library/hello-world:pull,push\"")
    == A.Challenge{"bearer", [A.Param{"realm", "https://auth.example.io/token"}, A.Param{"empty", ""},
      A.Param{"service", "registry.example.io"}, A.Param{"scope", "repository:library/hello-world:pull,push"}]} : A.Challenge}

# token.md: the Www-Authenticate header of its example
law oci_auth.challenge.token_md:
  {A.Auth.bearer("Bearer realm=\"https://auth.docker.io/token\",service=\"registry.docker.io\",scope=\"repository:samalba/my-app:pull,push\"")
    == Some{A.Bearer{"https://auth.docker.io/token", "registry.docker.io", ["repository:samalba/my-app:pull,push"]}} : Maybe<&2, A.Bearer>}

# parse.go lowercases the scheme and the keys
law oci_auth.challenge.scheme_case:
  {A.Auth.bearer("BEARER Realm=\"https://ghcr.io/token\",Service=\"ghcr.io\"")
    == Some{A.Bearer{"https://ghcr.io/token", "ghcr.io", []}} : Maybe<&2, A.Bearer>}

# parse.go: unquoted (token) values, spaces around commas
law oci_auth.challenge.token_values:
  {A.Auth.bearer("Bearer realm=\"https://quay.io/v2/auth\" , service=quay.io")
    == Some{A.Bearer{"https://quay.io/v2/auth", "quay.io", []}} : Maybe<&2, A.Bearer>}

# parse.go expectTokenOrQuoted: a backslash escapes the next character
law oci_auth.challenge.quoted_escape:
  {A.Auth.challenge("Bearer realm=\"https://a.example/t\\\"x\"")
    == A.Challenge{"bearer", [A.Param{"realm", "https://a.example/t\"x"}]} : A.Challenge}

# parse.go: the parse stops at a key with no "=" and keeps what it has
law oci_auth.challenge.stops_at_junk:
  {A.Auth.challenge("Bearer realm=\"https://a.example/t\", junk service=\"x\"")
    == A.Challenge{"bearer", [A.Param{"realm", "https://a.example/t"}]} : A.Challenge}

# A Basic challenge offers no token
law oci_auth.challenge.basic_not_bearer:
  {A.Auth.bearer("Basic realm=\"Registry Realm\"") == None{} : Maybe<&2, A.Bearer>}

# fetch.go: "no realm specified for token auth challenge"
law oci_auth.challenge.no_realm:
  {A.Auth.bearer("Bearer service=\"registry.docker.io\"") == None{} : Maybe<&2, A.Bearer>}

# token.md: the example token request, encoded as url.Values.Encode
law oci_auth.token_url.token_md:
  {A.Auth.token_url(A.Bearer{"https://auth.docker.io/token", "registry.docker.io", ["repository:samalba/my-app:pull,push"]})
    == "https://auth.docker.io/token?scope=repository%3Asamalba%2Fmy-app%3Apull%2Cpush&service=registry.docker.io" : String}

# fetch.go: one scope parameter per scope, in order
law oci_auth.token_url.scopes:
  {A.Auth.token_url(A.Bearer{"https://auth.docker.io/token", "registry.docker.io", ["repository:foo/bar:pull,push", "repository:foo/baz:pull"]})
    == "https://auth.docker.io/token?scope=repository%3Afoo%2Fbar%3Apull%2Cpush&scope=repository%3Afoo%2Fbaz%3Apull&service=registry.docker.io" : String}

# fetch.go: no service parameter when the challenge has none
law oci_auth.token_url.no_service:
  {A.Auth.token_url(A.Bearer{"https://ghcr.io/token", "", ["repository:library/busybox:pull"]})
    == "https://ghcr.io/token?scope=repository%3Alibrary%2Fbusybox%3Apull" : String}

# url.QueryEscape: space is "+", "~" stays, UTF-8 bytes are %XX
law oci_auth.token_url.escape:
  {A.Auth.token_url(A.Bearer{"https://r.example/token", "x", ["a b~é"]})
    == "https://r.example/token?scope=a+b~%C3%A9&service=x" : String}

# token.md: the example token response
law oci_auth.token.token_md:
  {A.Auth.token("{\"token\": \"eyJ0eXAiOiJKV1QiLCJhbGciOiJFUzI1NiIsImtpZCI6IlBZWU86VEVXVTpWN0pIOjI2SlY6QVFUWjpMSkMzOlNYVko6WEdIQTozNEYyOjJMQVE6WlJNSzpaN1E2In0.eyJpc3MiOiJhdXRoLmRvY2tlci5jb20iLCJzdWIiOiJqbGhhd24iLCJhdWQiOiJyZWdpc3RyeS5kb2NrZXIuY29tIiwiZXhwIjoxNDE1Mzg3MzE1LCJuYmYiOjE0MTUzODcwMTUsImlhdCI6MTQxNTM4NzAxNSwianRpIjoidFlKQ08xYzZjbnl5N2tBbjBjN3JLUGdiVjFIMWJGd3MiLCJhY2Nlc3MiOlt7InR5cGUiOiJyZXBvc2l0b3J5IiwibmFtZSI6InNhbWFsYmEvbXktYXBwIiwiYWN0aW9ucyI6WyJwdXNoIl19XX0.QhflHPfbd6eVF4lM9bwYpFZIV0PfikbyXuLx959ykRTBpe3CYnzs6YBK8FToVb5R47920PVLrh8zuLzdCr9t3w\", \"expires_in\": 3600,\"issued_at\": \"2009-11-10T23:00:00Z\"}")
    == Some{A.Token{"eyJ0eXAiOiJKV1QiLCJhbGciOiJFUzI1NiIsImtpZCI6IlBZWU86VEVXVTpWN0pIOjI2SlY6QVFUWjpMSkMzOlNYVko6WEdIQTozNEYyOjJMQVE6WlJNSzpaN1E2In0.eyJpc3MiOiJhdXRoLmRvY2tlci5jb20iLCJzdWIiOiJqbGhhd24iLCJhdWQiOiJyZWdpc3RyeS5kb2NrZXIuY29tIiwiZXhwIjoxNDE1Mzg3MzE1LCJuYmYiOjE0MTUzODcwMTUsImlhdCI6MTQxNTM4NzAxNSwianRpIjoidFlKQ08xYzZjbnl5N2tBbjBjN3JLUGdiVjFIMWJGd3MiLCJhY2Nlc3MiOlt7InR5cGUiOiJyZXBvc2l0b3J5IiwibmFtZSI6InNhbWFsYmEvbXktYXBwIiwiYWN0aW9ucyI6WyJwdXNoIl19XX0.QhflHPfbd6eVF4lM9bwYpFZIV0PfikbyXuLx959ykRTBpe3CYnzs6YBK8FToVb5R47920PVLrh8zuLzdCr9t3w", 3600}} : Maybe<&2, A.Token>}

# token.md: access_token is accepted for token
law oci_auth.token.access_token:
  {A.Auth.token("{\"access_token\": \"abc\", \"expires_in\": 300}") == Some{A.Token{"abc", 300}} : Maybe<&2, A.Token>}

# containerd and distribution: access_token wins when both are set
law oci_auth.token.access_token_wins:
  {A.Auth.token("{\"token\":\"t1\",\"access_token\":\"t2\",\"expires_in\":120}") == Some{A.Token{"t2", 120}} : Maybe<&2, A.Token>}

# token.md: expires_in, when omitted, defaults to 60 seconds
law oci_auth.token.default_lifetime:
  {A.Auth.token("{\"token\":\"t\"}") == Some{A.Token{"t", 60}} : Maybe<&2, A.Token>}

# token.md: never less than 60 seconds (session.go raises it)
law oci_auth.token.min_lifetime:
  {A.Auth.token("{\"token\":\"t\",\"expires_in\":30}") == Some{A.Token{"t", 60}} : Maybe<&2, A.Token>}

# other fields, nested values and literals are skipped
law oci_auth.token.skips_other_fields:
  {A.Auth.token("{\"refresh\":null,\"x\":{\"a\":[1,\"}\"]},\"ok\":true,\"token\":\"t\",\"expires_in\":600}") == Some{A.Token{"t", 600}} : Maybe<&2, A.Token>}

# fetch.go ErrNoToken: a response with no token
law oci_auth.token.no_token:
  {A.Auth.token("{\"expires_in\": 300}") == None{} : Maybe<&2, A.Token>}

# fetch.go ErrNoToken: an empty token
law oci_auth.token.empty_token:
  {A.Auth.token("{\"token\": \"\"}") == None{} : Maybe<&2, A.Token>}

# json.Decoder fails: no token
law oci_auth.token.not_json:
  {A.Auth.token("<html>401</html>") == None{} : Maybe<&2, A.Token>}

# json.Decoder fails on an unexpected EOF: no token
law oci_auth.token.truncated:
  {A.Auth.token("{\"token\":\"t\"") == None{} : Maybe<&2, A.Token>}

# json.Decoder fails on a string expires_in: no token
law oci_auth.token.expires_string:
  {A.Auth.token("{\"token\":\"t\",\"expires_in\":\"60\"}") == None{} : Maybe<&2, A.Token>}

# proxyauth_test.go TestRealmAllowedForDockerHubStyleAuthService
law oci_auth.realm.docker_hub:
  {A.Auth.realm_allowed("https://registry-1.docker.io", "https://auth.docker.io/token") == True{} : Bool}

# proxyauth_test.go TestConfigureAuthAllowsSameAuthorityRealm (httptest URL)
law oci_auth.realm.same_authority:
  {A.Auth.realm_allowed("http://127.0.0.1:40000", "http://127.0.0.1:40000/token") == True{} : Bool}

# proxyauth_test.go TestConfigureAuthRejectsLoopbackRealmOnDifferentAuthority
law oci_auth.realm.loopback_other_authority:
  {A.Auth.realm_allowed("http://127.0.0.1:40000", "http://127.0.0.1:40001/token") == False{} : Bool}

# proxyauth_test.go TestRealmFilteringChallengeManagerDropsOffOriginBearer: the evil realm
law oci_auth.realm.off_origin:
  {A.Auth.realm_allowed("https://registry.example.com", "https://evil.example.net/token") == False{} : Bool}

# proxyauth.go: a realm with no host is refused
law oci_auth.realm.no_host:
  {A.Auth.realm_allowed("https://registry.example.com", "/token") == False{} : Bool}

# proxyauth_test.go TestRealmFilteringChallengeManagerDropsOffOriginBearer: the surviving challenge
law oci_auth.realm.pick_filters:
  {A.Auth.pick("https://registry.example.com", ["Bearer realm=\"https://auth.example.com/token\",service=\"registry.example.com\"", "Bearer realm=\"https://evil.example.net/token\",service=\"registry.example.com\""])
    == Some{A.Bearer{"https://auth.example.com/token", "registry.example.com", []}} : Maybe<&2, A.Bearer>}

# the order of the headers does not matter: the evil realm is dropped
law oci_auth.realm.pick_evil_first:
  {A.Auth.pick("https://registry.example.com", ["Bearer realm=\"https://evil.example.net/token\",service=\"registry.example.com\"", "Bearer realm=\"https://auth.example.com/token\",service=\"registry.example.com\""])
    == Some{A.Bearer{"https://auth.example.com/token", "registry.example.com", []}} : Maybe<&2, A.Bearer>}

# RFC 9110 section 15.4: 301, 302, 303, 307 and 308 redirect; 304 does not.
law oci_auth.redirect.status_301:
  {A.Auth.is_redirect(301) == True{} : Bool}

law oci_auth.redirect.status_302:
  {A.Auth.is_redirect(302) == True{} : Bool}

law oci_auth.redirect.status_303:
  {A.Auth.is_redirect(303) == True{} : Bool}

law oci_auth.redirect.status_304:
  {A.Auth.is_redirect(304) == False{} : Bool}

law oci_auth.redirect.status_307:
  {A.Auth.is_redirect(307) == True{} : Bool}

law oci_auth.redirect.status_308:
  {A.Auth.is_redirect(308) == True{} : Bool}

law oci_auth.redirect.status_200:
  {A.Auth.is_redirect(200) == False{} : Bool}

# registry.k8s.io sends blobs to object storage: follow it, without Authorization
law oci_auth.redirect.to_storage:
  {A.Auth.redirect(0, "https://registry.k8s.io/v2/pause/blobs/sha256:0123",
    "https://prod-registry-k8s-io-us-east-2.s3.dualstack.us-east-2.amazonaws.com/containers/images/sha256:0123")
    == A.Follow{"https://prod-registry-k8s-io-us-east-2.s3.dualstack.us-east-2.amazonaws.com/containers/images/sha256:0123", False{}} : A.Hop}

# containerd: a 10th redirect is still followed
law oci_auth.redirect.hop_9:
  {A.Auth.redirect(9, "https://a.example/x", "https://b.example/y") == A.Follow{"https://b.example/y", False{}} : A.Hop}

# containerd CheckRedirect: "stopped after 10 redirects"
law oci_auth.redirect.hop_10:
  {A.Auth.redirect(10, "https://a.example/x", "https://b.example/y") == A.Refuse{"stopped after 10 redirects"} : A.Hop}

# https only
law oci_auth.redirect.http:
  {A.Auth.redirect(0, "https://a.example/x", "http://b.example/y") == A.Refuse{"redirect to a non-https URL"} : A.Hop}

# never to a private, loopback or local host: https://127.0.0.1/x
law oci_auth.redirect.refuse_loopback:
  {A.Auth.redirect(0, "https://a.example/x", "https://127.0.0.1/x") == A.Refuse{"redirect to a private, loopback or local host"} : A.Hop}

# never to a private, loopback or local host: https://169.254.169.254/latest/meta-data
law oci_auth.redirect.refuse_metadata:
  {A.Auth.redirect(0, "https://a.example/x", "https://169.254.169.254/latest/meta-data") == A.Refuse{"redirect to a private, loopback or local host"} : A.Hop}

# never to a private, loopback or local host: https://localhost/x
law oci_auth.redirect.refuse_localhost:
  {A.Auth.redirect(0, "https://a.example/x", "https://localhost/x") == A.Refuse{"redirect to a private, loopback or local host"} : A.Hop}

# never to a private, loopback or local host: https://[::1]/x
law oci_auth.redirect.refuse_ipv6_loopback:
  {A.Auth.redirect(0, "https://a.example/x", "https://[::1]/x") == A.Refuse{"redirect to a private, loopback or local host"} : A.Hop}

# never to a private, loopback or local host: https://10.0.0.1/x
law oci_auth.redirect.refuse_private:
  {A.Auth.redirect(0, "https://a.example/x", "https://10.0.0.1/x") == A.Refuse{"redirect to a private, loopback or local host"} : A.Hop}

# never to a private, loopback or local host: https://172.16.5.4/x
law oci_auth.redirect.refuse_private_172:
  {A.Auth.redirect(0, "https://a.example/x", "https://172.16.5.4/x") == A.Refuse{"redirect to a private, loopback or local host"} : A.Hop}

# never to a private, loopback or local host: https://192.168.1.1/x
law oci_auth.redirect.refuse_private_192:
  {A.Auth.redirect(0, "https://a.example/x", "https://192.168.1.1/x") == A.Refuse{"redirect to a private, loopback or local host"} : A.Hop}

# never to a private, loopback or local host: https://100.64.0.1/x
law oci_auth.redirect.refuse_cgnat:
  {A.Auth.redirect(0, "https://a.example/x", "https://100.64.0.1/x") == A.Refuse{"redirect to a private, loopback or local host"} : A.Hop}

# never to a private, loopback or local host: https://2130706433/x
law oci_auth.redirect.refuse_numeric:
  {A.Auth.redirect(0, "https://a.example/x", "https://2130706433/x") == A.Refuse{"redirect to a private, loopback or local host"} : A.Hop}

# never to a private, loopback or local host: https://0x7f.1/x
law oci_auth.redirect.refuse_hex:
  {A.Auth.redirect(0, "https://a.example/x", "https://0x7f.1/x") == A.Refuse{"redirect to a private, loopback or local host"} : A.Hop}

# never to a private, loopback or local host: https://registry/x
law oci_auth.redirect.refuse_single_label:
  {A.Auth.redirect(0, "https://a.example/x", "https://registry/x") == A.Refuse{"redirect to a private, loopback or local host"} : A.Hop}

# never to a private, loopback or local host: https://metadata.google.internal/x
law oci_auth.redirect.refuse_internal:
  {A.Auth.redirect(0, "https://a.example/x", "https://metadata.google.internal/x") == A.Refuse{"redirect to a private, loopback or local host"} : A.Hop}

# a public IPv4 literal may be followed
law oci_auth.redirect.public_ip:
  {A.Auth.redirect(0, "https://a.example/x", "https://8.8.8.8/x") == A.Follow{"https://8.8.8.8/x", False{}} : A.Hop}

# a Location with credentials is refused
law oci_auth.redirect.userinfo:
  {A.Auth.redirect(0, "https://a.example/x", "https://u:p@b.example/y") == A.Refuse{"redirect URL carries credentials"} : A.Hop}

# a 3xx with no Location is refused
law oci_auth.redirect.empty:
  {A.Auth.redirect(0, "https://a.example/x", "") == A.Refuse{"redirect without a Location"} : A.Hop}

# RFC 3986 5.2: an absolute-path reference stays on the origin, Authorization kept
law oci_auth.redirect.absolute_path:
  {A.Auth.redirect(0, "https://registry-1.docker.io/v2/library/busybox/blobs/sha256:01", "/v2/library/busybox/blobs/sha256:02")
    == A.Follow{"https://registry-1.docker.io/v2/library/busybox/blobs/sha256:02", True{}} : A.Hop}

# containerd effectivePort: :443 is the https origin
law oci_auth.redirect.default_port:
  {A.Auth.redirect(0, "https://r.example/v2/x", "https://R.example:443/v2/y") == A.Follow{"https://R.example:443/v2/y", True{}} : A.Hop}

# another port is another origin
law oci_auth.redirect.other_port:
  {A.Auth.redirect(0, "https://r.example/v2/x", "https://r.example:8443/v2/y") == A.Follow{"https://r.example:8443/v2/y", False{}} : A.Hop}

# RFC 3986 5.2: a network-path reference takes the scheme
law oci_auth.redirect.network_path:
  {A.Auth.redirect(0, "https://r.example/v2/x", "//cdn.example.com/b?sig=1") == A.Follow{"https://cdn.example.com/b?sig=1", False{}} : A.Hop}

# RFC 3986 5.2: a relative-path reference merges with the base path
law oci_auth.redirect.relative_path:
  {A.Auth.redirect(0, "https://r.example/v2/a/blobs/x?y=1", "z") == A.Follow{"https://r.example/v2/a/blobs/z", True{}} : A.Hop}

# RFC 3986 5.2: a query-only reference keeps the base path
law oci_auth.redirect.query_only:
  {A.Auth.redirect(0, "https://r.example/v2/a?y=1", "?z=2") == A.Follow{"https://r.example/v2/a?z=2", True{}} : A.Hop}

# DNS: the host layer checks every address a redirect target resolves to.
law oci_auth.addr.public:
  {A.Auth.addr_allowed([151, 101, 0, 223]) == True{} : Bool}

law oci_auth.addr.loopback:
  {A.Auth.addr_allowed([127, 0, 0, 1]) == False{} : Bool}

law oci_auth.addr.link_local:
  {A.Auth.addr_allowed([169, 254, 169, 254]) == False{} : Bool}

law oci_auth.addr.private:
  {A.Auth.addr_allowed([172, 31, 255, 255]) == False{} : Bool}

law oci_auth.addr.after_private:
  {A.Auth.addr_allowed([172, 32, 0, 1]) == True{} : Bool}

# General laws.

# No redirect past the 10th, whatever the URLs.
law oci_auth.redirect.hop_limit:
  for hops: U32
  for from: String
  for loc: String
  for h: {U32.is_ge(hops, 10) == True{} : Bool}
  {A.Auth.redirect(hops, from, loc) == A.Refuse{"stopped after 10 redirects"} : A.Hop}

# A token lives at least 60 seconds...
law oci_auth.lifetime.floor:
  for e: U32
  for h: {U32.is_lt(e, 60) == True{} : Bool}
  {A.Auth.lifetime(e) == 60 : U32}

# ...and as long as the server says when that is longer.
law oci_auth.lifetime.keep:
  for e: U32
  for h: {U32.is_lt(e, 60) == False{} : Bool}
  {A.Auth.lifetime(e) == e : U32}
