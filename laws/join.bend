import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/standalone/join.bend as JN

# Spec for src/standalone/join.bend (private-nodes / standalone join).
#
# The concrete laws transcribe every case of:
# - k8s.io/cluster-bootstrap/token/util/helpers_test.go (Kubernetes
#   v1.36.3, as vcluster a8ab30e pins it),
# - k8s.io/cluster-bootstrap/util/secrets/secrets_test.go,
# - plugin/pkg/auth/authenticator/token/bootstrap/bootstrap_test.go
#   (TestTokenAuthenticator),
# - cmd/kubeadm/app/util/pubkeypin/pubkeypin_test.go (TestHash),
# - Go 1.26 net/url url_test.go: queryEscapeTests, the QueryUnescape half
#   of unescapeTests, parseTests and TestQueryValues' Get calls,
# and the formats of vcluster's cmd/vclusterctl/cmd/token/create.go and
# pkg/cli/create_docker.go. Secret data in JSON is base64, as the API
# server sends it (values from coreutils base64). Times come from GNU
# date -u. TestTokenAuthenticator runs at time.Now(); the laws run at
# 2023-11-14T22:13:20Z (Unix 1700000000), between its two expirations.

# Fixtures.

def Laws.join.str(k: String, v: String) -> J.KV:
  J.KV{k, J.JStr{v}}

def Laws.join.now() -> JN.Join.Time:
  JN.Join.time_of_unix(1700000000)

# A Secret with a name, data (base64 values) and the bootstrap token type.
def Laws.join.secret(name: String, data: List<&2, J.KV>) -> J.Json:
  J.Json.obj([J.KV{"metadata", J.Json.obj([Laws.join.str("name", name)])},
    J.KV{"data", J.Json.obj(data)}, Laws.join.str("type", "bootstrap.kubernetes.io/token")])

# bootstrap_test.go: tokenID "foobar", tokenSecret "circumnavigation".
def Laws.join.id_kv() -> J.KV:
  Laws.join.str("token-id", "Zm9vYmFy")

def Laws.join.secret_kv() -> J.KV:
  Laws.join.str("token-secret", "Y2lyY3VtbmF2aWdhdGlvbg==")

def Laws.join.auth_kv() -> J.KV:
  Laws.join.str("usage-bootstrap-authentication", "dHJ1ZQ==")

def Laws.join.token() -> String:
  "foobar.circumnavigation"

def Laws.join.user(groups: List<&2, String>) -> Maybe<&2, JN.Join.User>:
  Some{JN.User{"system:bootstrap:foobar", groups}}

def Laws.join.auth(secrets: List<&2, J.Json>, token: String) -> Maybe<&2, JN.Join.User>:
  JN.Join.authenticate(token, secrets, Laws.join.now())

# pubkeypin testdata/test-cert.pem.
def Laws.join.test_cert() -> String:
  "-----BEGIN CERTIFICATE-----\n"
  ++ "MIIDRDCCAiygAwIBAgIJAJgVaCXvC6HkMA0GCSqGSIb3DQEBBQUAMB8xHTAbBgNV\n"
  ++ "BAMTFGt1YmVhZG0ta2V5cGlucy10ZXN0MCAXDTE3MDcwNTE3NDMxMFoYDzIxMTcw\n"
  ++ "NjExMTc0MzEwWjAfMR0wGwYDVQQDExRrdWJlYWRtLWtleXBpbnMtdGVzdDCCASIw\n"
  ++ "DQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAK0ba8mHU9UtYlzM1Own2Fk/XGjR\n"
  ++ "J4uJQvSeGLtz1hID1IA0dLwruvgLCPadXEOw/f/IWIWcmT+ZmvIHZKa/woq2iHi5\n"
  ++ "+HLhXs7aG4tjKGLYhag1hLjBI7icqV7ovkjdGAt9pWkxEzhIYClFMXDjKpMSynu+\n"
  ++ "YX6nZ9tic1cOkHmx2yiZdMkuriRQnpTOa7bb03OC1VfGl7gHlOAIYaj4539WCOr8\n"
  ++ "+ACTUMJUFEHcRZ2o8a/v6F9GMK+7SC8SJUI+GuroXqlMAdhEv4lX5Co52enYaClN\n"
  ++ "+D9FJLRpBv2YfiCQdJRaiTvCBSxEFz6BN+PtP5l2Hs703ZWEkOqCByM6HV8CAwEA\n"
  ++ "AaOBgDB+MB0GA1UdDgQWBBRQgUX8MhK2rWBWQiPHWcKzoWDH5DBPBgNVHSMESDBG\n"
  ++ "gBRQgUX8MhK2rWBWQiPHWcKzoWDH5KEjpCEwHzEdMBsGA1UEAxMUa3ViZWFkbS1r\n"
  ++ "ZXlwaW5zLXRlc3SCCQCYFWgl7wuh5DAMBgNVHRMEBTADAQH/MA0GCSqGSIb3DQEB\n"
  ++ "BQUAA4IBAQCaAUif7Pfx3X0F08cxhx8/Hdx4jcJw6MCq6iq6rsXM32ge43t8OHKC\n"
  ++ "pJW08dk58a3O1YQSMMvD6GJDAiAfXzfwcwY6j258b1ZlI9Ag0VokvhMl/XfdCsdh\n"
  ++ "AWImnL1t4hvU5jLaImUUMlYxMcSfHBGAm7WJIZ2LdEfg6YWfZh+WGbg1W7uxLxk6\n"
  ++ "y4h5rWdNnzBHWAGf7zJ0oEDV6W6RSwNXtC0JNnLaeIUm/6xdSddJlQPwUv8YH4jX\n"
  ++ "c1vuFqTnJBPcb7W//R/GI2Paicm1cmns9NLnPR35exHxFTy+D1yxmGokpoPMdife\n"
  ++ "aH+sfuxT8xeTPb3kjzF9eJTlnEquUDLM\n"
  ++ "-----END CERTIFICATE-----\n"

def Laws.join.p(k: String, v: String) -> JN.Join.Param:
  JN.Param{k, v}

def Laws.join.values(ps: List<&2, JN.Join.Param>, ok: Bool) -> JN.Join.Values:
  JN.Values{ps, ok}

# The query escape test input " ?&=#+%!<>#\"{}|\\^[]`☺\t:/@$'()*,;".
def Laws.join.esc_in() -> String:
  " ?&=#+%!<>#\"{}|\\^[]`" ++ String.from_list([Chr{9786}, Chr{9}]) ++ ":/@$'()*,;"

# helpers_test.go TestRandBytes: randBytes(n) has n chars.

law join.rand_bytes_0:
  {String.length(JN.Join.chars(0n, [], SNil{})) == 0n : Nat}

law join.rand_bytes_1:
  {String.length(JN.Join.chars(1n, [], SNil{})) == 1n : Nat}

law join.rand_bytes_2:
  {String.length(JN.Join.chars(2n, [], SNil{})) == 2n : Nat}

law join.rand_bytes_3:
  {String.length(JN.Join.chars(3n, [], SNil{})) == 3n : Nat}

law join.rand_bytes_100:
  {String.length(JN.Join.chars(100n, [], SNil{})) == 100n : Nat}

# helpers_test.go TestTokenFromIDAndSecret.

law join.token_from.foo_bar:
  {JN.Join.token_from("foo", "bar") == "foo.bar" : String}

law join.token_from.abcdef:
  {JN.Join.token_from("abcdef", "abcdef0123456789") == "abcdef.abcdef0123456789" : String}

law join.token_from.h_b:
  {JN.Join.token_from("h", "b") == "h.b" : String}

# helpers_test.go TestIsValidBootstrapToken.

law join.valid_token.empty:
  {JN.Join.valid_token("") == False{} : Bool}

law join.valid_token.dot:
  {JN.Join.valid_token(".") == False{} : Bool}

law join.valid_token.no_dot:
  {JN.Join.valid_token("1234567890123456789012") == False{} : Bool}

law join.valid_token.short_id:
  {JN.Join.valid_token("12345.1234567890123456") == False{} : Bool}

law join.valid_token.no_id:
  {JN.Join.valid_token(".1234567890123456") == False{} : Bool}

law join.valid_token.no_secret:
  {JN.Join.valid_token("123456.") == False{} : Bool}

law join.valid_token.colon_and_dot:
  {JN.Join.valid_token("123456:1234567890.123456") == False{} : Bool}

law join.valid_token.colon:
  {JN.Join.valid_token("abcdef:1234567890123456") == False{} : Bool}

law join.valid_token.upper_id:
  {JN.Join.valid_token("Abcdef.1234567890123456") == False{} : Bool}

law join.valid_token.upper_secret:
  {JN.Join.valid_token("123456.AABBCCDDEEFFGGHH") == False{} : Bool}

law join.valid_token.dash:
  {JN.Join.valid_token("123456.AABBCCD-EEFFGGHH") == False{} : Bool}

law join.valid_token.star:
  {JN.Join.valid_token("abc*ef.1234567890123456") == False{} : Bool}

law join.valid_token.letters_digits:
  {JN.Join.valid_token("abcdef.1234567890123456") == True{} : Bool}

law join.valid_token.digits_letters:
  {JN.Join.valid_token("123456.aabbccddeeffgghh") == True{} : Bool}

law join.valid_token.all_upper_id:
  {JN.Join.valid_token("ABCDEF.abcdef0123456789") == False{} : Bool}

law join.valid_token.mixed:
  {JN.Join.valid_token("abcdef.abcdef0123456789") == True{} : Bool}

law join.valid_token.digits:
  {JN.Join.valid_token("123456.1234560123456789") == True{} : Bool}

# helpers_test.go TestIsValidBootstrapTokenID.

law join.valid_id.empty:
  {JN.Join.valid_token_id("") == False{} : Bool}

law join.valid_id.long:
  {JN.Join.valid_token_id("1234567890123456789012") == False{} : Bool}

law join.valid_id.short:
  {JN.Join.valid_token_id("12345") == False{} : Bool}

law join.valid_id.upper_first:
  {JN.Join.valid_token_id("Abcdef") == False{} : Bool}

law join.valid_id.upper:
  {JN.Join.valid_token_id("ABCDEF") == False{} : Bool}

law join.valid_id.trailing_dot:
  {JN.Join.valid_token_id("abcdef.") == False{} : Bool}

law join.valid_id.letters:
  {JN.Join.valid_token_id("abcdef") == True{} : Bool}

law join.valid_id.digits:
  {JN.Join.valid_token_id("123456") == True{} : Bool}

# helpers_test.go TestBootstrapTokenSecretName.

law join.secret_name.foo:
  {JN.Join.secret_name("foo") == "bootstrap-token-foo" : String}

law join.secret_name.bar:
  {JN.Join.secret_name("bar") == "bootstrap-token-bar" : String}

law join.secret_name.empty:
  {JN.Join.secret_name("") == "bootstrap-token-" : String}

law join.secret_name.abcdef:
  {JN.Join.secret_name("abcdef") == "bootstrap-token-abcdef" : String}

# helpers_test.go TestValidateBootstrapGroupName.

law join.group.valid:
  {JN.Join.valid_group("system:bootstrappers:foo") == True{} : Bool}

law join.group.valid_nested:
  {JN.Join.valid_group("system:bootstrappers:foo:bar:baz") == True{} : Bool}

law join.group.dashes_number:
  {JN.Join.valid_group("system:bootstrappers:foo-bar-42") == True{} : Bool}

law join.group.uppercase:
  {JN.Join.valid_group("system:bootstrappers:Foo") == False{} : Bool}

law join.group.missing_prefix:
  {JN.Join.valid_group("foo") == False{} : Bool}

law join.group.no_body:
  {JN.Join.valid_group("system:bootstrappers:") == False{} : Bool}

law join.group.spaces:
  {JN.Join.valid_group("system:bootstrappers: ") == False{} : Bool}

law join.group.asterisk:
  {JN.Join.valid_group("system:bootstrappers:*") == False{} : Bool}

law join.group.trailing_colon:
  {JN.Join.valid_group("system:bootstrappers:foo:") == False{} : Bool}

law join.group.trailing_dash:
  {JN.Join.valid_group("system:bootstrappers:foo-") == False{} : Bool}

law join.group.script_tags:
  {JN.Join.valid_group("system:bootstrappers:<script> alert(\"scary?!\") </script>") == False{} : Bool}

law join.group.too_long:
  {JN.Join.valid_group("system:bootstrappers:" ++ String.repeat("x", 300n)) == False{} : Bool}

# helpers_test.go TestValidateUsages ("" is no error).

law join.usages.signing:
  {String.is_empty(JN.Join.validate_usages(["signing"])) == True{} : Bool}

law join.usages.authentication:
  {String.is_empty(JN.Join.validate_usages(["authentication"])) == True{} : Bool}

law join.usages.all_valid:
  {String.is_empty(JN.Join.validate_usages(["authentication", "signing"])) == True{} : Bool}

law join.usages.single_invalid:
  {String.is_empty(JN.Join.validate_usages(["authentication", "foo"])) == False{} : Bool}

law join.usages.all_invalid:
  {String.is_empty(JN.Join.validate_usages(["foo", "bar"])) == False{} : Bool}

# secrets_test.go TestGetSecretString.

law join.data.existing_key:
  {JN.Join.data(J.Json.obj([J.KV{"metadata", J.Json.obj([Laws.join.str("name", "foo")])}, J.KV{"data", J.Json.obj([Laws.join.str("foo", "YmFy")])}]), "foo") == "bar" : String}

law join.data.missing_key:
  {JN.Join.data(J.Json.obj([J.KV{"metadata", J.Json.obj([Laws.join.str("name", "foo")])}, J.KV{"data", J.Json.obj([Laws.join.str("foo", "YmFy")])}]), "baz") == "" : String}

law join.data.no_data:
  {JN.Join.data(J.Json.obj([J.KV{"metadata", J.Json.obj([Laws.join.str("name", "foo")])}]), "foo") == "" : String}

# secrets_test.go TestParseSecretName.

law join.parse_name.valid:
  {JN.Join.parse_secret_name("bootstrap-token-abc123") == Some{"abc123"} : Maybe<&2, String>}

law join.parse_name.blank:
  {JN.Join.parse_secret_name("") == None{} : Maybe<&2, String>}

law join.parse_name.no_prefix:
  {JN.Join.parse_secret_name("abc123") == None{} : Maybe<&2, String>}

law join.parse_name.no_id:
  {JN.Join.parse_secret_name("bootstrap-token-") == None{} : Maybe<&2, String>}

law join.parse_name.short_id:
  {JN.Join.parse_secret_name("bootstrap-token-abc") == None{} : Maybe<&2, String>}

law join.parse_name.long_id:
  {JN.Join.parse_secret_name("bootstrap-token-abc123ghi") == None{} : Maybe<&2, String>}

law join.parse_name.invalid_id:
  {JN.Join.parse_secret_name("bootstrap-token-ABC123") == None{} : Maybe<&2, String>}

# secrets_test.go TestGetGroups.

law join.groups.not_set:
  {JN.Join.groups(J.Json.obj([J.KV{"metadata", J.Json.obj([Laws.join.str("name", "test")])}, J.KV{"data", J.Json.obj([])}]))
    == Some{["system:bootstrappers"]} : Maybe<&2, List<&2, String>>}

law join.groups.empty:
  {JN.Join.groups(J.Json.obj([J.KV{"metadata", J.Json.obj([Laws.join.str("name", "test")])}, J.KV{"data", J.Json.obj([Laws.join.str("auth-extra-groups", "")])}]))
    == Some{["system:bootstrappers"]} : Maybe<&2, List<&2, String>>}

law join.groups.invalid_prefix:
  {JN.Join.groups(J.Json.obj([J.KV{"metadata", J.Json.obj([Laws.join.str("name", "test")])}, J.KV{"data", J.Json.obj([Laws.join.str("auth-extra-groups", "Zm9v")])}]))
    == None{} : Maybe<&2, List<&2, String>>}

law join.groups.valid:
  {JN.Join.groups(J.Json.obj([J.KV{"metadata", J.Json.obj([Laws.join.str("name", "test")])}, J.KV{"data", J.Json.obj([Laws.join.str("auth-extra-groups", "c3lzdGVtOmJvb3RzdHJhcHBlcnM6Zm9vLHN5c3RlbTpib290c3RyYXBwZXJzOmJhcixzeXN0ZW06Ym9vdHN0cmFwcGVyczpiYXI=")])}]))
    == Some{["system:bootstrappers", "system:bootstrappers:bar", "system:bootstrappers:foo"]} : Maybe<&2, List<&2, String>>}

# bootstrap_test.go TestTokenAuthenticator.

law join.authn.valid_token:
  {Laws.join.auth([Laws.join.secret("bootstrap-token-foobar", [Laws.join.id_kv(), Laws.join.secret_kv(), Laws.join.auth_kv()])], Laws.join.token())
    == Laws.join.user(["system:bootstrappers"]) : Maybe<&2, JN.Join.User>}

law join.authn.extra_group:
  {Laws.join.auth([Laws.join.secret("bootstrap-token-foobar", [Laws.join.id_kv(), Laws.join.secret_kv(), Laws.join.auth_kv(),
      Laws.join.str("auth-extra-groups", "c3lzdGVtOmJvb3RzdHJhcHBlcnM6Zm9v")])], Laws.join.token())
    == Laws.join.user(["system:bootstrappers", "system:bootstrappers:foo"]) : Maybe<&2, JN.Join.User>}

law join.authn.invalid_group:
  {Laws.join.auth([Laws.join.secret("bootstrap-token-foobar", [Laws.join.id_kv(), Laws.join.secret_kv(), Laws.join.auth_kv(),
      Laws.join.str("auth-extra-groups", "Zm9v")])], Laws.join.token())
    == None{} : Maybe<&2, JN.Join.User>}

law join.authn.invalid_secret_name:
  {Laws.join.auth([Laws.join.secret("bad-name", [Laws.join.id_kv(), Laws.join.secret_kv(), Laws.join.auth_kv()])], Laws.join.token())
    == None{} : Maybe<&2, JN.Join.User>}

law join.authn.no_usage:
  {Laws.join.auth([Laws.join.secret("bootstrap-token-foobar", [Laws.join.id_kv(), Laws.join.secret_kv()])], Laws.join.token())
    == None{} : Maybe<&2, JN.Join.User>}

law join.authn.wrong_token:
  {Laws.join.auth([Laws.join.secret("bootstrap-token-foobar", [Laws.join.id_kv(), Laws.join.secret_kv(), Laws.join.auth_kv()])], "barfoo.circumnavigation")
    == None{} : Maybe<&2, JN.Join.User>}

law join.authn.deleted_token:
  {Laws.join.auth([J.Json.obj([J.KV{"metadata", J.Json.obj([Laws.join.str("name", "bootstrap-token-foobar"), Laws.join.str("deletionTimestamp", "2023-11-14T22:13:20Z")])},
      J.KV{"data", J.Json.obj([Laws.join.id_kv(), Laws.join.secret_kv(), Laws.join.auth_kv()])}, Laws.join.str("type", "bootstrap.kubernetes.io/token")])], Laws.join.token())
    == None{} : Maybe<&2, JN.Join.User>}

law join.authn.expired_token:
  {Laws.join.auth([Laws.join.secret("bootstrap-token-foobar", [Laws.join.id_kv(), Laws.join.secret_kv(), Laws.join.auth_kv(),
      Laws.join.str("expiration", "MjAwOS0xMS0xMFQyMzowMDowMFo=")])], Laws.join.token())
    == None{} : Maybe<&2, JN.Join.User>}

law join.authn.not_expired_token:
  {Laws.join.auth([Laws.join.secret("bootstrap-token-foobar", [Laws.join.id_kv(), Laws.join.secret_kv(), Laws.join.auth_kv(),
      Laws.join.str("expiration", "MjEwOS0xMS0xMFQyMzowMDowMFo=")])], Laws.join.token())
    == Laws.join.user(["system:bootstrappers"]) : Maybe<&2, JN.Join.User>}

law join.authn.short_id:
  {Laws.join.auth([Laws.join.secret("bootstrap-token-foo", [Laws.join.str("token-id", "Zm9v"), Laws.join.secret_kv(), Laws.join.auth_kv()])], "foo.circumnavigation")
    == None{} : Maybe<&2, JN.Join.User>}

# pubkeypin_test.go TestHash is an executable test (tests/join.bend): the
# SHA-256 of a whole certificate is too much computation for the --verdict
# kernel's fuel.

# url_test.go queryEscapeTests, both ways (TestQueryEscape checks that
# QueryUnescape gives the input back).

law join.query_escape.empty:
  {JN.Join.query_escape("") == "" : String}

law join.query_escape.abc:
  {JN.Join.query_escape("abc") == "abc" : String}

law join.query_escape.space:
  {JN.Join.query_escape("one two") == "one+two" : String}

law join.query_escape.percent:
  {JN.Join.query_escape("10%") == "10%25" : String}

law join.query_escape.reserved:
  {JN.Join.query_escape(Laws.join.esc_in())
    == "+%3F%26%3D%23%2B%25%21%3C%3E%23%22%7B%7D%7C%5C%5E%5B%5D%60%E2%98%BA%09%3A%2F%40%24%27%28%29%2A%2C%3B" : String}

law join.query_roundtrip.empty:
  {JN.Join.query_unescape("") == Some{""} : Maybe<&2, String>}

law join.query_roundtrip.abc:
  {JN.Join.query_unescape("abc") == Some{"abc"} : Maybe<&2, String>}

law join.query_roundtrip.space:
  {JN.Join.query_unescape("one+two") == Some{"one two"} : Maybe<&2, String>}

law join.query_roundtrip.percent:
  {JN.Join.query_unescape("10%25") == Some{"10%"} : Maybe<&2, String>}

law join.query_roundtrip.reserved:
  {JN.Join.query_unescape("+%3F%26%3D%23%2B%25%21%3C%3E%23%22%7B%7D%7C%5C%5E%5B%5D%60%E2%98%BA%09%3A%2F%40%24%27%28%29%2A%2C%3B")
    == Some{Laws.join.esc_in()} : Maybe<&2, String>}

# url_test.go unescapeTests (QueryUnescape).

law join.unescape.empty:
  {JN.Join.query_unescape("") == Some{""} : Maybe<&2, String>}

law join.unescape.abc:
  {JN.Join.query_unescape("abc") == Some{"abc"} : Maybe<&2, String>}

law join.unescape.one:
  {JN.Join.query_unescape("1%41") == Some{"1A"} : Maybe<&2, String>}

law join.unescape.three:
  {JN.Join.query_unescape("1%41%42%43") == Some{"1ABC"} : Maybe<&2, String>}

law join.unescape.lower_hex:
  {JN.Join.query_unescape("%4a") == Some{"J"} : Maybe<&2, String>}

law join.unescape.upper_hex:
  {JN.Join.query_unescape("%6F") == Some{"o"} : Maybe<&2, String>}

law join.unescape.bare_percent:
  {JN.Join.query_unescape("%") == None{} : Maybe<&2, String>}

law join.unescape.one_hex:
  {JN.Join.query_unescape("%a") == None{} : Maybe<&2, String>}

law join.unescape.one_digit:
  {JN.Join.query_unescape("%1") == None{} : Maybe<&2, String>}

law join.unescape.short_tail:
  {JN.Join.query_unescape("123%45%6") == None{} : Maybe<&2, String>}

law join.unescape.bad_hex:
  {JN.Join.query_unescape("%zzzzz") == None{} : Maybe<&2, String>}

law join.unescape.plus:
  {JN.Join.query_unescape("a+b") == Some{"a b"} : Maybe<&2, String>}

law join.unescape.pct20:
  {JN.Join.query_unescape("a%20b") == Some{"a b"} : Maybe<&2, String>}

# url_test.go parseTests (ParseQuery): the pairs in order and whether no
# error was reported.

law join.parse_query.one:
  {JN.Join.parse_query("a=1") == Laws.join.values([Laws.join.p("a", "1")], True{}) : JN.Join.Values}

law join.parse_query.two:
  {JN.Join.parse_query("a=1&b=2") == Laws.join.values([Laws.join.p("a", "1"), Laws.join.p("b", "2")], True{}) : JN.Join.Values}

law join.parse_query.repeated:
  {JN.Join.parse_query("a=1&a=2&a=banana")
    == Laws.join.values([Laws.join.p("a", "1"), Laws.join.p("a", "2"), Laws.join.p("a", "banana")], True{}) : JN.Join.Values}

law join.parse_query.escaped:
  {JN.Join.parse_query("ascii=%3Ckey%3A+0x90%3E") == Laws.join.values([Laws.join.p("ascii", "<key: 0x90>")], True{}) : JN.Join.Values}

law join.parse_query.semicolon:
  {JN.Join.parse_query("a=1;b=2") == Laws.join.values([], False{}) : JN.Join.Values}

law join.parse_query.semicolon_key:
  {JN.Join.parse_query("a;b=1") == Laws.join.values([], False{}) : JN.Join.Values}

law join.parse_query.escaped_semicolon:
  {JN.Join.parse_query("a=%3B") == Laws.join.values([Laws.join.p("a", ";")], True{}) : JN.Join.Values}

law join.parse_query.escaped_semicolon_key:
  {JN.Join.parse_query("a%3Bb=1") == Laws.join.values([Laws.join.p("a;b", "1")], True{}) : JN.Join.Values}

law join.parse_query.semicolon_after:
  {JN.Join.parse_query("a=1&a=2;a=banana") == Laws.join.values([Laws.join.p("a", "1")], False{}) : JN.Join.Values}

law join.parse_query.semicolon_first:
  {JN.Join.parse_query("a;b&c=1") == Laws.join.values([Laws.join.p("c", "1")], False{}) : JN.Join.Values}

law join.parse_query.semicolon_middle:
  {JN.Join.parse_query("a=1&b=2;a=3&c=4") == Laws.join.values([Laws.join.p("a", "1"), Laws.join.p("c", "4")], False{}) : JN.Join.Values}

law join.parse_query.semicolon_last:
  {JN.Join.parse_query("a=1&b=2;c=3") == Laws.join.values([Laws.join.p("a", "1")], False{}) : JN.Join.Values}

law join.parse_query.only_semicolon:
  {JN.Join.parse_query(";") == Laws.join.values([], False{}) : JN.Join.Values}

law join.parse_query.trailing_semicolon:
  {JN.Join.parse_query("a=1;") == Laws.join.values([], False{}) : JN.Join.Values}

law join.parse_query.semicolon_segment:
  {JN.Join.parse_query("a=1&;") == Laws.join.values([Laws.join.p("a", "1")], False{}) : JN.Join.Values}

law join.parse_query.leading_semicolon:
  {JN.Join.parse_query(";a=1&b=2") == Laws.join.values([Laws.join.p("b", "2")], False{}) : JN.Join.Values}

law join.parse_query.semicolon_end:
  {JN.Join.parse_query("a=1&b=2;") == Laws.join.values([Laws.join.p("a", "1")], False{}) : JN.Join.Values}

# url_test.go TestQueryValues: Get on foo=bar&bar=1&bar=2&baz.

law join.query_get.foo:
  {JN.Join.get(JN.Join.params(JN.Join.parse_query("foo=bar&bar=1&bar=2&baz")), "foo") == "bar" : String}

law join.query_get.case_sensitive:
  {JN.Join.get(JN.Join.params(JN.Join.parse_query("foo=bar&bar=1&bar=2&baz")), "Foo") == "" : String}

law join.query_get.first:
  {JN.Join.get(JN.Join.params(JN.Join.parse_query("foo=bar&bar=1&bar=2&baz")), "bar") == "1" : String}

law join.query_get.no_value:
  {JN.Join.get(JN.Join.params(JN.Join.parse_query("foo=bar&bar=1&bar=2&baz")), "baz") == "" : String}

# Go time.Parse(time.RFC3339, s) (parseRFC3339), to whole seconds.

law join.time.utc:
  {JN.Join.parse_time("2009-11-10T23:00:00Z") == Some{JN.Join.time_of_unix(1257894000)} : Maybe<&2, JN.Join.Time>}

law join.time.east:
  {JN.Join.parse_time("2026-11-07T12:00:00+02:00") == Some{JN.Join.time_of_unix(1794045600)} : Maybe<&2, JN.Join.Time>}

law join.time.west_next_day:
  {JN.Join.parse_time("2026-11-07T23:30:00-01:00") == Some{JN.Join.time_of_unix(1794097800)} : Maybe<&2, JN.Join.Time>}

law join.time.leap_day:
  {JN.Join.parse_time("2024-02-29T00:00:00Z") == Some{JN.Join.time_of_unix(1709164800)} : Maybe<&2, JN.Join.Time>}

law join.time.no_leap_day:
  {JN.Join.parse_time("2023-02-29T00:00:00Z") == None{} : Maybe<&2, JN.Join.Time>}

law join.time.space:
  {JN.Join.parse_time("2009-11-10 23:00:00Z") == None{} : Maybe<&2, JN.Join.Time>}

law join.time.no_zone:
  {JN.Join.parse_time("2009-11-10T23:00:00") == None{} : Maybe<&2, JN.Join.Time>}

# create.go: time.Now().UTC().Add(ttl).Format(time.RFC3339), --expires 1h.
law join.time.expiry_format:
  {JN.Join.rfc3339(JN.Join.expiry(JN.Join.time_of_unix(1700000000), 3600)) == "2023-11-14T23:13:20Z" : String}

# create.go:203-225: the token Secret of `vcluster token create` (worker,
# --expires 1h at Unix 1700000000) and `--control-plane --expires ""`.

law join.token_secret.worker:
  {JN.Join.token_secret("abcdef", "0123456789abcdef", False{}, Some{JN.Join.time_of_unix(1700003600)})
    == J.Json.obj([
      J.KV{"metadata", J.Json.obj([Laws.join.str("name", "bootstrap-token-abcdef"), Laws.join.str("namespace", "kube-system"),
        J.KV{"labels", J.Json.obj([Laws.join.str("vcluster.loft.sh/token", "true"), Laws.join.str("vcluster.loft.sh/token-node-type", "worker")])}])},
      Laws.join.str("type", "bootstrap.kubernetes.io/token"),
      J.KV{"data", J.Json.obj([
        Laws.join.str("token-id", "YWJjZGVm"),
        Laws.join.str("token-secret", "MDEyMzQ1Njc4OWFiY2RlZg=="),
        Laws.join.str("usage-bootstrap-signing", "dHJ1ZQ=="),
        Laws.join.str("usage-bootstrap-authentication", "dHJ1ZQ=="),
        Laws.join.str("auth-extra-groups", "c3lzdGVtOmJvb3RzdHJhcHBlcnM6a3ViZWFkbTpkZWZhdWx0LW5vZGUtdG9rZW4="),
        Laws.join.str("description", "dG9rZW4gZ2VuZXJhdGVkIGJ5IGNsdXN0ZXItYXBpLWJvb3RzdHJhcC1wcm92aWRlci1rdWJlYWRt"),
        Laws.join.str("expiration", "MjAyMy0xMS0xNFQyMzoxMzoyMFo=")])}]) : J.Json}

law join.token_secret.control_plane:
  {JN.Join.token_secret("abcdef", "0123456789abcdef", True{}, None{})
    == J.Json.obj([
      J.KV{"metadata", J.Json.obj([Laws.join.str("name", "bootstrap-token-abcdef"), Laws.join.str("namespace", "kube-system"),
        J.KV{"labels", J.Json.obj([Laws.join.str("vcluster.loft.sh/token", "true"), Laws.join.str("vcluster.loft.sh/token-node-type", "control-plane")])}])},
      Laws.join.str("type", "bootstrap.kubernetes.io/token"),
      J.KV{"data", J.Json.obj([
        Laws.join.str("token-id", "YWJjZGVm"),
        Laws.join.str("token-secret", "MDEyMzQ1Njc4OWFiY2RlZg=="),
        Laws.join.str("usage-bootstrap-signing", "dHJ1ZQ=="),
        Laws.join.str("usage-bootstrap-authentication", "dHJ1ZQ=="),
        Laws.join.str("auth-extra-groups", "c3lzdGVtOmJvb3RzdHJhcHBlcnM6a3ViZWFkbTpkZWZhdWx0LW5vZGUtdG9rZW4="),
        Laws.join.str("description", "dG9rZW4gZ2VuZXJhdGVkIGJ5IGNsdXN0ZXItYXBpLWJvb3RzdHJhcC1wcm92aWRlci1rdWJlYWRt")])}]) : J.Json}

# create.go:120-128: the printed join command. The token and endpoint are
# the example in vcluster-docs deploy/control-plane/binary/manage.mdx.

law join.command.api_endpoint:
  {JN.Join.join_command("", "10.244.0.16:8443", "hzndlx.vhf08ob7pg97r2hb")
    == "curl -fsSLk \"https://10.244.0.16:8443/node/join?token=hzndlx.vhf08ob7pg97r2hb\" | sh -\n" : String}

law join.command.platform_endpoint:
  {JN.Join.join_command("https://platform.example.com/kubernetes/project/p/virtualcluster/vc", "10.244.0.16:8443", "hzndlx.vhf08ob7pg97r2hb")
    == "curl -fsSLk \"https://platform.example.com/kubernetes/project/p/virtualcluster/vc/node/join?token=hzndlx.vhf08ob7pg97r2hb\" | sh -\n" : String}

law join.command.kubeadm:
  {JN.Join.kubeadm_command("10.244.0.16:8443", "hzndlx.vhf08ob7pg97r2hb", "sha256:345959acb2c3b2feb87d281961c893f62a314207ef02599f1cc4a5fb255480b3")
    == "kubeadm join 10.244.0.16:8443 --token hzndlx.vhf08ob7pg97r2hb --discovery-token-ca-cert-hash sha256:345959acb2c3b2feb87d281961c893f62a314207ef02599f1cc4a5fb255480b3\n" : String}

# create_docker.go:741-748: the docker driver's worker join.
law join.command.docker_worker:
  {JN.Join.docker_join("vcluster.cp.demo", "hzndlx.vhf08ob7pg97r2hb", "v1.36.6", "arm64")
    == "\nsleep 2\nuntil curl -fsSLk -o /tmp/join.sh \"https://vcluster.cp.demo:8443/node/join?token=hzndlx.vhf08ob7pg97r2hb&type=worker\"; do\n  echo \"Waiting for vCluster API to be ready...\"\n  sleep 2\ndone\nsh /tmp/join.sh --bundle-path /var/lib/vcluster/bin/kubernetes-v1.36.6-arm64.tar.gz --force-join\n" : String}

# The two request shapes vcluster sends: the docker driver's (type=worker)
# and the printed command's (no type).

law join.request.docker_worker:
  {JN.Join.parse_request("/node/join?token=hzndlx.vhf08ob7pg97r2hb&type=worker")
    == JN.ReqOk{JN.Query{"hzndlx.vhf08ob7pg97r2hb", "worker"}} : JN.Join.Req}

law join.request.token_create:
  {JN.Join.parse_request("/node/join?token=hzndlx.vhf08ob7pg97r2hb")
    == JN.ReqOk{JN.Query{"hzndlx.vhf08ob7pg97r2hb", ""}} : JN.Join.Req}

# General laws.

# GenerateBootstrapToken always makes a valid token, whatever the random
# values (helpers_test.go TestGenerateBootstrapToken).
law join.generated_valid:
  for +rs: +List<U32>
  {JN.Join.valid_token(JN.Join.generate(rs)) == True{} : Bool}

# randBytes(n) has n chars, whatever the random values.
law join.chars_length:
  for +n: Nat
  for +rs: +List<U32>
  {String.length(JN.Join.chars(n, rs, SNil{})) == n : Nat}

# A token whose Secret has expired never authorizes a join.
law join.expired_never_authorizes:
  for +q: JN.Join.Query
  for +s: J.Json
  for +now: JN.Join.Time
  for h: {JN.Join.expired(s, now) == True{} : Bool}
  {JN.Join.allowed(JN.Join.authorize(q, Some{s}, now)) == False{} : Bool}

# Proposed: the /node/join answer (Join.respond, Join.reason, Join.render).
# The handler is closed source (vcluster-pro); the answers are vk8s design,
# docs/ref/standalone-decisions.md J1. The status texts are Go's
# net/http StatusText; the 404 body is http.NotFound's, the 405 body and
# Allow header are Go's ServeMux's, and error bodies end in a newline as
# http.Error writes them. A 200 needs the CA's SHA-256, too much for the
# --verdict kernel's fuel: tests/join.bend covers it.

def Laws.join.worker() -> J.Json:
  JN.Join.token_secret("abcdef", "0123456789abcdef", False{}, None{})

def Laws.join.get(target: String, found: Maybe<&2, J.Json>) -> JN.Join.Reply:
  JN.Join.respond("GET", target, found, "", "10.0.2.15:6443", Laws.join.now())

def Laws.join.text(code: U32, body: String) -> JN.Join.Reply:
  JN.Reply{code, "text/plain; charset=utf-8", body}

law join.reason.ok:
  {JN.Join.reason(200) == "OK" : String}

law join.reason.bad_request:
  {JN.Join.reason(400) == "Bad Request" : String}

law join.reason.unauthorized:
  {JN.Join.reason(401) == "Unauthorized" : String}

law join.reason.forbidden:
  {JN.Join.reason(403) == "Forbidden" : String}

law join.reason.not_found:
  {JN.Join.reason(404) == "Not Found" : String}

law join.reason.method_not_allowed:
  {JN.Join.reason(405) == "Method Not Allowed" : String}

law join.reason.internal:
  {JN.Join.reason(500) == "Internal Server Error" : String}

law join.respond.post:
  {JN.Join.respond("POST", "/node/join?token=abcdef.0123456789abcdef&type=worker", Some{Laws.join.worker()}, "", "10.0.2.15:6443", Laws.join.now())
    == Laws.join.text(405, "Method Not Allowed\n") : JN.Join.Reply}

law join.respond.head:
  {JN.Join.respond("HEAD", "/node/join?token=abcdef.0123456789abcdef", None{}, "", "10.0.2.15:6443", Laws.join.now())
    == Laws.join.text(405, "Method Not Allowed\n") : JN.Join.Reply}

law join.respond.other_path:
  {Laws.join.get("/node/download?token=abcdef.0123456789abcdef", None{})
    == Laws.join.text(404, "404 page not found\n") : JN.Join.Reply}

law join.respond.post_other_path:
  {JN.Join.respond("POST", "/healthz", None{}, "", "10.0.2.15:6443", Laws.join.now())
    == Laws.join.text(404, "404 page not found\n") : JN.Join.Reply}

law join.respond.missing_token:
  {Laws.join.get("/node/join?type=worker", None{})
    == Laws.join.text(401, "missing token\n") : JN.Join.Reply}

law join.respond.bad_type:
  {Laws.join.get("/node/join?token=abcdef.0123456789abcdef&type=master", Some{Laws.join.worker()})
    == Laws.join.text(400, "invalid node type \"master\"\n") : JN.Join.Reply}

law join.respond.malformed_token:
  {Laws.join.get("/node/join?token=abcdef", Some{Laws.join.worker()})
    == Laws.join.text(401, "malformed token\n") : JN.Join.Reply}

law join.respond.unknown_token:
  {Laws.join.get("/node/join?token=abcdef.0123456789abcdef", None{})
    == Laws.join.text(401, "unknown token\n") : JN.Join.Reply}

law join.respond.wrong_secret:
  {Laws.join.get("/node/join?token=abcdef.0123456789abcdee", Some{Laws.join.worker()})
    == Laws.join.text(401, "invalid token\n") : JN.Join.Reply}

law join.respond.expired_token:
  {Laws.join.get("/node/join?token=abcdef.0123456789abcdef",
      Some{JN.Join.token_secret("abcdef", "0123456789abcdef", False{}, Some{JN.Join.time_of_unix(1699999999)})})
    == Laws.join.text(401, "token expired\n") : JN.Join.Reply}

law join.respond.wrong_type:
  {Laws.join.get("/node/join?token=abcdef.0123456789abcdef&type=control-plane", Some{Laws.join.worker()})
    == Laws.join.text(403, "the token is for worker nodes\n") : JN.Join.Reply}

law join.respond.no_ca:
  {Laws.join.get("/node/join?token=abcdef.0123456789abcdef&type=worker", Some{Laws.join.worker()})
    == Laws.join.text(500, "failed to load CA certificate referenced by kubeconfig: data does not contain any valid RSA or ECDSA certificates\n") : JN.Join.Reply}

law join.render.not_found:
  {JN.Join.render(Laws.join.text(404, "404 page not found\n"))
    == "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: 19\r\nConnection: close\r\n\r\n404 page not found\n" : String}

law join.render.unauthorized:
  {JN.Join.render(Laws.join.text(401, "unknown token\n"))
    == "HTTP/1.1 401 Unauthorized\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: 14\r\nConnection: close\r\n\r\nunknown token\n" : String}

law join.render.method_not_allowed:
  {JN.Join.render(Laws.join.text(405, "Method Not Allowed\n"))
    == "HTTP/1.1 405 Method Not Allowed\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: 19\r\nAllow: GET\r\nConnection: close\r\n\r\nMethod Not Allowed\n" : String}

# Content-Length counts UTF-8 bytes: "☺" is three.
law join.render.utf8:
  {JN.Join.render(JN.Reply{200, "text/x-shellscript", String.from_list([Chr{9786}, Chr{10}])})
    == "HTTP/1.1 200 OK\r\nContent-Type: text/x-shellscript\r\nContent-Length: 4\r\nConnection: close\r\n\r\n" ++ String.from_list([Chr{9786}, Chr{10}]) : String}

# Only a GET is ever answered with a script.
law join.respond.only_get:
  for +m: String
  for +t: String
  for +f: Maybe<&2, J.Json>
  for +c: String
  for +e: String
  for +now: JN.Join.Time
  for h: {String.eq(m, "GET") == False{} : Bool}
  {JN.Join.served(JN.Join.respond(m, t, f, c, e, now)) == False{} : Bool}

# A token whose Secret the server did not find is never answered with a
# script.
law join.respond.unfound_never_served:
  for +m: String
  for +t: String
  for +c: String
  for +e: String
  for +now: JN.Join.Time
  {JN.Join.served(JN.Join.respond(m, t, None{}, c, e, now)) == False{} : Bool}
