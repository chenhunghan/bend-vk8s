import Base
import ../src/oci/auth.bend as A

# tests/oci_auth.bend: every concrete law of laws/oci_auth.bend, run. One
# PASS/FAIL line per case; on a FAIL, both sides as text.

def T.check(+name: String, +got: String, +want: String) -> IO(Unit):
  T.check.go(String.eq(got, want), name, got, want)

def T.check.go(ok: Bool, +name: String, +got: String, +want: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name ++ ": got " ++ got ++ ", want " ++ want)

def T.str(s: String) -> String:
  String.quote(s)

def T.bool(b: Bool) -> String:
  Bool.show(b)

def T.strs(xs: List<&2, String>) -> String:
  "[" ++ String.join(T.quotes(xs), ",") ++ "]"

def T.quotes(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      Con{String.quote(x), T.quotes(t)}

def T.bearer(m: Maybe<&2, A.Bearer>) -> String:
  match m:
    case None{}:
      "None"
    case Some{A.Bearer{r, s, sc}}:
      "Bearer{" ++ String.quote(r) ++ "," ++ String.quote(s) ++ "," ++ T.strs(sc) ++ "}"

def T.params(ps: List<&2, A.Param>) -> String:
  match ps:
    case Nil{}:
      ""
    case Con{A.Param{k, v}, t}:
      String.quote(k) ++ "=" ++ String.quote(v) ++ ";" ++ T.params(t)

def T.ch(c: A.Challenge) -> String:
  match c:
    case A.Challenge{s, ps}:
      String.quote(s) ++ " " ++ T.params(ps)

def T.tok(m: Maybe<&2, A.Token>) -> String:
  match m:
    case None{}:
      "None"
    case Some{A.Token{t, e}}:
      "Token{" ++ String.quote(t) ++ "," ++ U32.show(e) ++ "}"

def T.hop(h: A.Hop) -> String:
  match h:
    case A.Follow{u, a}:
      "Follow{" ++ String.quote(u) ++ "," ++ Bool.show(a) ++ "}"
    case A.Refuse{w}:
      "Refuse{" ++ String.quote(w) ++ "}"

def main() -> IO(Unit):
  do IO<Unit>:
    T.check("oci_auth.challenge.single_scope",
      T.bearer(A.Auth.bearer("Bearer realm=\"https://auth.docker.io/token\",service=\"registry.docker.io\",scope=\"repository:foo/bar:pull,push\"")),
      T.bearer(Some{A.Bearer{"https://auth.docker.io/token", "registry.docker.io", ["repository:foo/bar:pull,push"]}}))
    T.check("oci_auth.challenge.multiple_scopes",
      T.bearer(A.Auth.bearer("Bearer realm=\"https://auth.docker.io/token\",service=\"registry.docker.io\",scope=\"repository:foo/bar:pull,push repository:foo/baz:pull repository:foo/foo:push\"")),
      T.bearer(Some{A.Bearer{"https://auth.docker.io/token", "registry.docker.io", ["repository:foo/bar:pull,push", "repository:foo/baz:pull", "repository:foo/foo:push"]}}))
    T.check("oci_auth.challenge.empty_param",
      T.ch(A.Auth.challenge("Bearer realm=\"https://auth.example.io/token\",empty=\"\",service=\"registry.example.io\",scope=\"repository:library/hello-world:pull,push\"")),
      T.ch(A.Challenge{"bearer", [A.Param{"realm", "https://auth.example.io/token"}, A.Param{"empty", ""}, A.Param{"service", "registry.example.io"}, A.Param{"scope", "repository:library/hello-world:pull,push"}]}))
    T.check("oci_auth.challenge.token_md",
      T.bearer(A.Auth.bearer("Bearer realm=\"https://auth.docker.io/token\",service=\"registry.docker.io\",scope=\"repository:samalba/my-app:pull,push\"")),
      T.bearer(Some{A.Bearer{"https://auth.docker.io/token", "registry.docker.io", ["repository:samalba/my-app:pull,push"]}}))
    T.check("oci_auth.challenge.scheme_case",
      T.bearer(A.Auth.bearer("BEARER Realm=\"https://ghcr.io/token\",Service=\"ghcr.io\"")),
      T.bearer(Some{A.Bearer{"https://ghcr.io/token", "ghcr.io", []}}))
    T.check("oci_auth.challenge.token_values",
      T.bearer(A.Auth.bearer("Bearer realm=\"https://quay.io/v2/auth\" , service=quay.io")),
      T.bearer(Some{A.Bearer{"https://quay.io/v2/auth", "quay.io", []}}))
    T.check("oci_auth.challenge.quoted_escape",
      T.ch(A.Auth.challenge("Bearer realm=\"https://a.example/t\\\"x\"")),
      T.ch(A.Challenge{"bearer", [A.Param{"realm", "https://a.example/t\"x"}]}))
    T.check("oci_auth.challenge.stops_at_junk",
      T.ch(A.Auth.challenge("Bearer realm=\"https://a.example/t\", junk service=\"x\"")),
      T.ch(A.Challenge{"bearer", [A.Param{"realm", "https://a.example/t"}]}))
    T.check("oci_auth.challenge.basic_not_bearer",
      T.bearer(A.Auth.bearer("Basic realm=\"Registry Realm\"")),
      T.bearer(None{}))
    T.check("oci_auth.challenge.no_realm",
      T.bearer(A.Auth.bearer("Bearer service=\"registry.docker.io\"")),
      T.bearer(None{}))
    T.check("oci_auth.token_url.token_md",
      T.str(A.Auth.token_url(A.Bearer{"https://auth.docker.io/token", "registry.docker.io", ["repository:samalba/my-app:pull,push"]})),
      T.str("https://auth.docker.io/token?scope=repository%3Asamalba%2Fmy-app%3Apull%2Cpush&service=registry.docker.io"))
    T.check("oci_auth.token_url.scopes",
      T.str(A.Auth.token_url(A.Bearer{"https://auth.docker.io/token", "registry.docker.io", ["repository:foo/bar:pull,push", "repository:foo/baz:pull"]})),
      T.str("https://auth.docker.io/token?scope=repository%3Afoo%2Fbar%3Apull%2Cpush&scope=repository%3Afoo%2Fbaz%3Apull&service=registry.docker.io"))
    T.check("oci_auth.token_url.no_service",
      T.str(A.Auth.token_url(A.Bearer{"https://ghcr.io/token", "", ["repository:library/busybox:pull"]})),
      T.str("https://ghcr.io/token?scope=repository%3Alibrary%2Fbusybox%3Apull"))
    T.check("oci_auth.token_url.escape",
      T.str(A.Auth.token_url(A.Bearer{"https://r.example/token", "x", ["a b~é"]})),
      T.str("https://r.example/token?scope=a+b~%C3%A9&service=x"))
    T.check("oci_auth.token.token_md",
      T.tok(A.Auth.token("{\"token\": \"eyJ0eXAiOiJKV1QiLCJhbGciOiJFUzI1NiIsImtpZCI6IlBZWU86VEVXVTpWN0pIOjI2SlY6QVFUWjpMSkMzOlNYVko6WEdIQTozNEYyOjJMQVE6WlJNSzpaN1E2In0.eyJpc3MiOiJhdXRoLmRvY2tlci5jb20iLCJzdWIiOiJqbGhhd24iLCJhdWQiOiJyZWdpc3RyeS5kb2NrZXIuY29tIiwiZXhwIjoxNDE1Mzg3MzE1LCJuYmYiOjE0MTUzODcwMTUsImlhdCI6MTQxNTM4NzAxNSwianRpIjoidFlKQ08xYzZjbnl5N2tBbjBjN3JLUGdiVjFIMWJGd3MiLCJhY2Nlc3MiOlt7InR5cGUiOiJyZXBvc2l0b3J5IiwibmFtZSI6InNhbWFsYmEvbXktYXBwIiwiYWN0aW9ucyI6WyJwdXNoIl19XX0.QhflHPfbd6eVF4lM9bwYpFZIV0PfikbyXuLx959ykRTBpe3CYnzs6YBK8FToVb5R47920PVLrh8zuLzdCr9t3w\", \"expires_in\": 3600,\"issued_at\": \"2009-11-10T23:00:00Z\"}")),
      T.tok(Some{A.Token{"eyJ0eXAiOiJKV1QiLCJhbGciOiJFUzI1NiIsImtpZCI6IlBZWU86VEVXVTpWN0pIOjI2SlY6QVFUWjpMSkMzOlNYVko6WEdIQTozNEYyOjJMQVE6WlJNSzpaN1E2In0.eyJpc3MiOiJhdXRoLmRvY2tlci5jb20iLCJzdWIiOiJqbGhhd24iLCJhdWQiOiJyZWdpc3RyeS5kb2NrZXIuY29tIiwiZXhwIjoxNDE1Mzg3MzE1LCJuYmYiOjE0MTUzODcwMTUsImlhdCI6MTQxNTM4NzAxNSwianRpIjoidFlKQ08xYzZjbnl5N2tBbjBjN3JLUGdiVjFIMWJGd3MiLCJhY2Nlc3MiOlt7InR5cGUiOiJyZXBvc2l0b3J5IiwibmFtZSI6InNhbWFsYmEvbXktYXBwIiwiYWN0aW9ucyI6WyJwdXNoIl19XX0.QhflHPfbd6eVF4lM9bwYpFZIV0PfikbyXuLx959ykRTBpe3CYnzs6YBK8FToVb5R47920PVLrh8zuLzdCr9t3w", 3600}}))
    T.check("oci_auth.token.access_token",
      T.tok(A.Auth.token("{\"access_token\": \"abc\", \"expires_in\": 300}")),
      T.tok(Some{A.Token{"abc", 300}}))
    T.check("oci_auth.token.access_token_wins",
      T.tok(A.Auth.token("{\"token\":\"t1\",\"access_token\":\"t2\",\"expires_in\":120}")),
      T.tok(Some{A.Token{"t2", 120}}))
    T.check("oci_auth.token.default_lifetime",
      T.tok(A.Auth.token("{\"token\":\"t\"}")),
      T.tok(Some{A.Token{"t", 60}}))
    T.check("oci_auth.token.min_lifetime",
      T.tok(A.Auth.token("{\"token\":\"t\",\"expires_in\":30}")),
      T.tok(Some{A.Token{"t", 60}}))
    T.check("oci_auth.token.skips_other_fields",
      T.tok(A.Auth.token("{\"refresh\":null,\"x\":{\"a\":[1,\"}\"]},\"ok\":true,\"token\":\"t\",\"expires_in\":600}")),
      T.tok(Some{A.Token{"t", 600}}))
    T.check("oci_auth.token.no_token",
      T.tok(A.Auth.token("{\"expires_in\": 300}")),
      T.tok(None{}))
    T.check("oci_auth.token.empty_token",
      T.tok(A.Auth.token("{\"token\": \"\"}")),
      T.tok(None{}))
    T.check("oci_auth.token.not_json",
      T.tok(A.Auth.token("<html>401</html>")),
      T.tok(None{}))
    T.check("oci_auth.token.truncated",
      T.tok(A.Auth.token("{\"token\":\"t\"")),
      T.tok(None{}))
    T.check("oci_auth.token.expires_string",
      T.tok(A.Auth.token("{\"token\":\"t\",\"expires_in\":\"60\"}")),
      T.tok(None{}))
    T.check("oci_auth.realm.docker_hub",
      T.bool(A.Auth.realm_allowed("https://registry-1.docker.io", "https://auth.docker.io/token")),
      T.bool(True{}))
    T.check("oci_auth.realm.same_authority",
      T.bool(A.Auth.realm_allowed("http://127.0.0.1:40000", "http://127.0.0.1:40000/token")),
      T.bool(True{}))
    T.check("oci_auth.realm.loopback_other_authority",
      T.bool(A.Auth.realm_allowed("http://127.0.0.1:40000", "http://127.0.0.1:40001/token")),
      T.bool(False{}))
    T.check("oci_auth.realm.off_origin",
      T.bool(A.Auth.realm_allowed("https://registry.example.com", "https://evil.example.net/token")),
      T.bool(False{}))
    T.check("oci_auth.realm.no_host",
      T.bool(A.Auth.realm_allowed("https://registry.example.com", "/token")),
      T.bool(False{}))
    T.check("oci_auth.realm.pick_filters",
      T.bearer(A.Auth.pick("https://registry.example.com", ["Bearer realm=\"https://auth.example.com/token\",service=\"registry.example.com\"", "Bearer realm=\"https://evil.example.net/token\",service=\"registry.example.com\""])),
      T.bearer(Some{A.Bearer{"https://auth.example.com/token", "registry.example.com", []}}))
    T.check("oci_auth.realm.pick_evil_first",
      T.bearer(A.Auth.pick("https://registry.example.com", ["Bearer realm=\"https://evil.example.net/token\",service=\"registry.example.com\"", "Bearer realm=\"https://auth.example.com/token\",service=\"registry.example.com\""])),
      T.bearer(Some{A.Bearer{"https://auth.example.com/token", "registry.example.com", []}}))
    T.check("oci_auth.redirect.status_301",
      T.bool(A.Auth.is_redirect(301)),
      T.bool(True{}))
    T.check("oci_auth.redirect.status_302",
      T.bool(A.Auth.is_redirect(302)),
      T.bool(True{}))
    T.check("oci_auth.redirect.status_303",
      T.bool(A.Auth.is_redirect(303)),
      T.bool(True{}))
    T.check("oci_auth.redirect.status_304",
      T.bool(A.Auth.is_redirect(304)),
      T.bool(False{}))
    T.check("oci_auth.redirect.status_307",
      T.bool(A.Auth.is_redirect(307)),
      T.bool(True{}))
    T.check("oci_auth.redirect.status_308",
      T.bool(A.Auth.is_redirect(308)),
      T.bool(True{}))
    T.check("oci_auth.redirect.status_200",
      T.bool(A.Auth.is_redirect(200)),
      T.bool(False{}))
    T.check("oci_auth.redirect.to_storage",
      T.hop(A.Auth.redirect(0, "https://registry.k8s.io/v2/pause/blobs/sha256:0123", "https://prod-registry-k8s-io-us-east-2.s3.dualstack.us-east-2.amazonaws.com/containers/images/sha256:0123")),
      T.hop(A.Follow{"https://prod-registry-k8s-io-us-east-2.s3.dualstack.us-east-2.amazonaws.com/containers/images/sha256:0123", False{}}))
    T.check("oci_auth.redirect.hop_9",
      T.hop(A.Auth.redirect(9, "https://a.example/x", "https://b.example/y")),
      T.hop(A.Follow{"https://b.example/y", False{}}))
    T.check("oci_auth.redirect.hop_10",
      T.hop(A.Auth.redirect(10, "https://a.example/x", "https://b.example/y")),
      T.hop(A.Refuse{"stopped after 10 redirects"}))
    T.check("oci_auth.redirect.http",
      T.hop(A.Auth.redirect(0, "https://a.example/x", "http://b.example/y")),
      T.hop(A.Refuse{"redirect to a non-https URL"}))
    T.check("oci_auth.redirect.refuse_loopback",
      T.hop(A.Auth.redirect(0, "https://a.example/x", "https://127.0.0.1/x")),
      T.hop(A.Refuse{"redirect to a private, loopback or local host"}))
    T.check("oci_auth.redirect.refuse_metadata",
      T.hop(A.Auth.redirect(0, "https://a.example/x", "https://169.254.169.254/latest/meta-data")),
      T.hop(A.Refuse{"redirect to a private, loopback or local host"}))
    T.check("oci_auth.redirect.refuse_localhost",
      T.hop(A.Auth.redirect(0, "https://a.example/x", "https://localhost/x")),
      T.hop(A.Refuse{"redirect to a private, loopback or local host"}))
    T.check("oci_auth.redirect.refuse_ipv6_loopback",
      T.hop(A.Auth.redirect(0, "https://a.example/x", "https://[::1]/x")),
      T.hop(A.Refuse{"redirect to a private, loopback or local host"}))
    T.check("oci_auth.redirect.refuse_private",
      T.hop(A.Auth.redirect(0, "https://a.example/x", "https://10.0.0.1/x")),
      T.hop(A.Refuse{"redirect to a private, loopback or local host"}))
    T.check("oci_auth.redirect.refuse_private_172",
      T.hop(A.Auth.redirect(0, "https://a.example/x", "https://172.16.5.4/x")),
      T.hop(A.Refuse{"redirect to a private, loopback or local host"}))
    T.check("oci_auth.redirect.refuse_private_192",
      T.hop(A.Auth.redirect(0, "https://a.example/x", "https://192.168.1.1/x")),
      T.hop(A.Refuse{"redirect to a private, loopback or local host"}))
    T.check("oci_auth.redirect.refuse_cgnat",
      T.hop(A.Auth.redirect(0, "https://a.example/x", "https://100.64.0.1/x")),
      T.hop(A.Refuse{"redirect to a private, loopback or local host"}))
    T.check("oci_auth.redirect.refuse_numeric",
      T.hop(A.Auth.redirect(0, "https://a.example/x", "https://2130706433/x")),
      T.hop(A.Refuse{"redirect to a private, loopback or local host"}))
    T.check("oci_auth.redirect.refuse_hex",
      T.hop(A.Auth.redirect(0, "https://a.example/x", "https://0x7f.1/x")),
      T.hop(A.Refuse{"redirect to a private, loopback or local host"}))
    T.check("oci_auth.redirect.refuse_single_label",
      T.hop(A.Auth.redirect(0, "https://a.example/x", "https://registry/x")),
      T.hop(A.Refuse{"redirect to a private, loopback or local host"}))
    T.check("oci_auth.redirect.refuse_internal",
      T.hop(A.Auth.redirect(0, "https://a.example/x", "https://metadata.google.internal/x")),
      T.hop(A.Refuse{"redirect to a private, loopback or local host"}))
    T.check("oci_auth.redirect.public_ip",
      T.hop(A.Auth.redirect(0, "https://a.example/x", "https://8.8.8.8/x")),
      T.hop(A.Follow{"https://8.8.8.8/x", False{}}))
    T.check("oci_auth.redirect.userinfo",
      T.hop(A.Auth.redirect(0, "https://a.example/x", "https://u:p@b.example/y")),
      T.hop(A.Refuse{"redirect URL carries credentials"}))
    T.check("oci_auth.redirect.empty",
      T.hop(A.Auth.redirect(0, "https://a.example/x", "")),
      T.hop(A.Refuse{"redirect without a Location"}))
    T.check("oci_auth.redirect.absolute_path",
      T.hop(A.Auth.redirect(0, "https://registry-1.docker.io/v2/library/busybox/blobs/sha256:01", "/v2/library/busybox/blobs/sha256:02")),
      T.hop(A.Follow{"https://registry-1.docker.io/v2/library/busybox/blobs/sha256:02", True{}}))
    T.check("oci_auth.redirect.default_port",
      T.hop(A.Auth.redirect(0, "https://r.example/v2/x", "https://R.example:443/v2/y")),
      T.hop(A.Follow{"https://R.example:443/v2/y", True{}}))
    T.check("oci_auth.redirect.other_port",
      T.hop(A.Auth.redirect(0, "https://r.example/v2/x", "https://r.example:8443/v2/y")),
      T.hop(A.Follow{"https://r.example:8443/v2/y", False{}}))
    T.check("oci_auth.redirect.network_path",
      T.hop(A.Auth.redirect(0, "https://r.example/v2/x", "//cdn.example.com/b?sig=1")),
      T.hop(A.Follow{"https://cdn.example.com/b?sig=1", False{}}))
    T.check("oci_auth.redirect.relative_path",
      T.hop(A.Auth.redirect(0, "https://r.example/v2/a/blobs/x?y=1", "z")),
      T.hop(A.Follow{"https://r.example/v2/a/blobs/z", True{}}))
    T.check("oci_auth.redirect.query_only",
      T.hop(A.Auth.redirect(0, "https://r.example/v2/a?y=1", "?z=2")),
      T.hop(A.Follow{"https://r.example/v2/a?z=2", True{}}))
    T.check("oci_auth.addr.public",
      T.bool(A.Auth.addr_allowed([151, 101, 0, 223])),
      T.bool(True{}))
    T.check("oci_auth.addr.loopback",
      T.bool(A.Auth.addr_allowed([127, 0, 0, 1])),
      T.bool(False{}))
    T.check("oci_auth.addr.link_local",
      T.bool(A.Auth.addr_allowed([169, 254, 169, 254])),
      T.bool(False{}))
    T.check("oci_auth.addr.private",
      T.bool(A.Auth.addr_allowed([172, 31, 255, 255])),
      T.bool(False{}))
    T.check("oci_auth.addr.after_private",
      T.bool(A.Auth.addr_allowed([172, 32, 0, 1])),
      T.bool(True{}))
