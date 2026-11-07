import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import bend-kube-runtime@0.2.0.0/src/time.bend as T
import ../src/standalone/join.bend as JN

# Tests for src/standalone/join.bend. The laws in laws/join.bend transcribe
# the Go tests; these cover the vk8s design of /node/join (the vcluster
# handler is closed source; docs/ref/standalone-decisions.md), token
# generation, the CA hash errors and the time edge cases. Times other than
# the design come from Go's semantics and GNU date -u.

def X.check(name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name)

def X.report(name: String, got: String, want: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name ++ ": got " ++ String.quote(got) ++ ", want " ++ String.quote(want))

def X.same(name: String, +got: String, +want: String) -> IO(Unit):
  X.report(name, got, want, String.eq(got, want))

def X.show_auth(a: JN.Join.Auth) -> String:
  match a:
    case JN.Allowed{JN.User{n, gs}, t}:
      "allowed " ++ n ++ " [" ++ String.join(gs, ",") ++ "] " ++ t
    case JN.Denied{c, r}:
      "denied " ++ U32.show(c) ++ " " ++ r

def X.show_req(r: JN.Join.Req) -> String:
  match r:
    case JN.ReqOk{JN.Query{t, n}}:
      "ok " ++ t ++ " " ++ n
    case JN.ReqErr{c, m}:
      "error " ++ U32.show(c) ++ " " ++ m

def X.show_maybe(m: Maybe<&2, String>) -> String:
  match m:
    case None{}:
      "none"
    case Some{s}:
      "some " ++ s

def X.show_hash(h: JN.Join.Hash) -> String:
  match h:
    case JN.HashOk{s}:
      "ok " ++ s
    case JN.HashErr{e}:
      "error " ++ e

def X.show_time(m: Maybe<&2, JN.Join.Time>) -> String:
  match m:
    case None{}:
      "none"
    case Some{t}:
      JN.Join.rfc3339(t)

def X.now() -> JN.Join.Time:
  JN.Join.time_of_unix(1700000000)

def X.token() -> String:
  "abcdef.0123456789abcdef"

def X.worker() -> J.Json:
  JN.Join.token_secret("abcdef", "0123456789abcdef", False{}, None{})

def X.control_plane() -> J.Json:
  JN.Join.token_secret("abcdef", "0123456789abcdef", True{}, Some{JN.Join.time_of_unix(1700003600)})

def X.expired() -> J.Json:
  JN.Join.token_secret("abcdef", "0123456789abcdef", False{}, Some{JN.Join.time_of_unix(1699999999)})

def X.auth(token: String, ty: String, found: Maybe<&2, J.Json>) -> String:
  X.show_auth(JN.Join.authorize(JN.Query{token, ty}, found, X.now()))

def X.groups() -> String:
  "[system:bootstrappers,system:bootstrappers:kubeadm:default-node-token]"

def X.cert() -> String:
  "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n"

def X.script(ty: String) -> String:
  JN.Join.script(JN.Script{"10.0.2.15:6443", "abcdef.0123456789abcdef",
    "sha256:345959acb2c3b2feb87d281961c893f62a314207ef02599f1cc4a5fb255480b3", ty})

def X.expiration(e: String) -> J.Json:
  J.Json.obj([J.KV{"data", J.Json.obj([J.KV{"expiration", JN.Join.b64(e)}])}])

def main() -> IO(Unit):
  do IO<Unit>:
    X.same("authorize worker token as worker", X.auth(X.token(), "worker", Some{X.worker()}),
      "allowed system:bootstrap:abcdef " ++ X.groups() ++ " worker")
    X.same("authorize worker token without type", X.auth(X.token(), "", Some{X.worker()}),
      "allowed system:bootstrap:abcdef " ++ X.groups() ++ " worker")
    X.same("authorize worker token as control plane", X.auth(X.token(), "control-plane", Some{X.worker()}),
      "denied 403 the token is for worker nodes")
    X.same("authorize control-plane token without type", X.auth(X.token(), "", Some{X.control_plane()}),
      "allowed system:bootstrap:abcdef " ++ X.groups() ++ " control-plane")
    X.same("authorize control-plane token as worker", X.auth(X.token(), "worker", Some{X.control_plane()}),
      "denied 403 the token is for control-plane nodes")
    X.same("authorize expired token", X.auth(X.token(), "worker", Some{X.expired()}), "denied 401 token expired")
    X.same("authorize unknown token", X.auth(X.token(), "worker", None{}), "denied 401 unknown token")
    X.same("authorize wrong secret", X.auth("abcdef.0123456789abcdee", "worker", Some{X.worker()}), "denied 401 invalid token")
    X.same("authorize malformed token", X.auth("abcdef", "worker", Some{X.worker()}), "denied 401 malformed token")
    X.same("lookup", X.show_maybe(JN.Join.lookup(JN.Query{X.token(), ""})), "some bootstrap-token-abcdef")
    X.same("lookup malformed", X.show_maybe(JN.Join.lookup(JN.Query{"abc.def", ""})), "none")
    X.same("request other path", X.show_req(JN.Join.parse_request("/node/download?token=x")), "error 404 404 page not found")
    X.same("request without token", X.show_req(JN.Join.parse_request("/node/join")), "error 401 missing token")
    X.same("request bad type", X.show_req(JN.Join.parse_request("/node/join?token=x&type=master")),
      "error 400 invalid node type \"master\"")
    X.same("request escaped token", X.show_req(JN.Join.parse_request("/node/join?token=abcdef%2E0123456789abcdef&type=control-plane")),
      "ok abcdef.0123456789abcdef control-plane")
    X.same("request first token wins", X.show_req(JN.Join.parse_request("/node/join?token=a&token=b")), "ok a ")
    X.same("generate counting", JN.Join.generate([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21]),
      "012345.6789abcdefghijkl")
    X.same("generate no values", JN.Join.generate([]), "000000.0000000000000000")
    X.same("generate wraps at 36", JN.Join.generate([36, 71, 4294967295]), "0z3000.0000000000000000")
    X.check("generate validates", JN.Join.valid_token(JN.Join.generate([123456789, 987654321, 5, 77, 1000, 35, 36])))
    X.same("token from parts", X.show_maybe(JN.Join.parse_secret_name(JN.Join.secret_name("abcdef"))), "some abcdef")
    X.same("ca hash of no certificate", X.show_hash(JN.Join.ca_hash("")),
      "error failed to load CA certificate referenced by kubeconfig: data does not contain any valid RSA or ECDSA certificates")
    X.same("ca hash of two certificates", X.show_hash(JN.Join.ca_hash(X.cert() ++ X.cert())),
      "error multiple CA certificates found in configmap kube-root-ca.crt")
    X.same("ca hash of a broken certificate", X.show_hash(JN.Join.ca_hash(X.cert())),
      "error failed to load CA certificate referenced by kubeconfig: x509: malformed certificate")
    X.check("script runs kubeadm join", String.contains(X.script("worker"),
      "set -- join '10.0.2.15:6443' --token 'abcdef.0123456789abcdef' --discovery-token-ca-cert-hash 'sha256:345959acb2c3b2feb87d281961c893f62a314207ef02599f1cc4a5fb255480b3'\n"))
    X.check("script execs kubeadm", String.contains(X.script("worker"), "exec kubeadm \"$@\"\n"))
    X.check("script starts with a shebang", String.starts_with(X.script("worker"), "#!/bin/sh\n"))
    X.check("script takes --force-join", String.contains(X.script("worker"), "--force-join) force_join=true ;;"))
    X.check("script refuses control planes", String.contains(X.script("control-plane"), "vk8s does not join control-plane nodes yet"))
    X.check("script for control planes has no join", Bool.not(String.contains(X.script("control-plane"), "exec kubeadm")))
    X.same("time fraction dropped", X.show_time(JN.Join.parse_time("2009-11-10T23:00:00.123Z")), "2009-11-10T23:00:00Z")
    X.same("time unix zero", JN.Join.rfc3339(JN.Join.time_of_unix(0)), "1970-01-01T00:00:00Z")
    X.same("time year 2000", JN.Join.rfc3339(JN.Join.time_of_unix(946684800)), "2000-01-01T00:00:00Z")
    X.same("time hour 24", X.show_time(JN.Join.parse_time("2009-11-10T24:00:00Z")), "none")
    X.same("time month 13", X.show_time(JN.Join.parse_time("2009-13-10T23:00:00Z")), "none")
    X.same("time lowercase t", X.show_time(JN.Join.parse_time("2009-11-10t23:00:00Z")), "none")
    X.same("time bad offset", X.show_time(JN.Join.parse_time("2009-11-10T23:00:00+24:00")), "none")
    X.check("time from wall", String.eq(JN.Join.rfc3339(JN.Join.time_of_wall(T.Wall{19675, 80000, 5})), "2023-11-14T22:13:20Z"))
    X.check("expired at the instant", JN.Join.expired(X.expiration("2023-11-14T22:13:20Z"), X.now()))
    X.check("not expired a second later", Bool.not(JN.Join.expired(X.expiration("2023-11-14T22:13:21Z"), X.now())))
    X.check("no expiration never expires", Bool.not(JN.Join.expired(J.Json.obj([]), X.now())))
    X.check("unparseable expiration has expired", JN.Join.expired(X.expiration("tomorrow"), X.now()))
    X.same("usages error", JN.Join.validate_usages(["foo", "authentication", "bar", "foo"]),
      "invalid bootstrap token usage string: bar,foo, valid usage options: signing,authentication")
    X.same("query escape of a token", JN.Join.query_escape(X.token()), X.token())
