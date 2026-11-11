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

def X.test_cert() -> String:
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

def X.hash_show(h: JN.Join.Hash) -> String:
  match h:
    case JN.HashOk{v}:
      v
    case _:
      "error"

def X.show_reply(r: JN.Join.Reply) -> String:
  match r:
    case JN.Reply{c, t, b}:
      U32.show(c) ++ " " ++ t ++ " " ++ b

def X.respond(method: String, target: String, found: Maybe<&2, J.Json>, ca: String) -> String:
  X.show_reply(JN.Join.respond(method, target, found, ca, "10.0.2.15:6443", X.now()))

def X.get(target: String, found: Maybe<&2, J.Json>) -> String:
  X.respond("GET", target, found, X.test_cert())

def X.text(code: String, body: String) -> String:
  code ++ " text/plain; charset=utf-8 " ++ body

def X.served(+script: String) -> String:
  "HTTP/1.1 200 OK\r\nContent-Type: text/x-shellscript\r\nContent-Length: " ++ Nat.show(String.length(script))
    ++ "\r\nConnection: close\r\n\r\n" ++ script

def main() -> IO(Unit):
  do IO<Unit>:
    X.same("ca_hash of pubkeypin_test.go TestHash's certificate", X.hash_show(JN.Join.ca_hash(X.test_cert())),
      "sha256:345959acb2c3b2feb87d281961c893f62a314207ef02599f1cc4a5fb255480b3")
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
    X.same("respond 200 worker script", X.get("/node/join?token=abcdef.0123456789abcdef&type=worker", Some{X.worker()}),
      "200 text/x-shellscript " ++ X.script("worker"))
    X.same("respond 200 without type", X.get("/node/join?token=abcdef.0123456789abcdef", Some{X.worker()}),
      "200 text/x-shellscript " ++ X.script("worker"))
    X.same("respond 200 control-plane token", X.get("/node/join?token=abcdef.0123456789abcdef", Some{X.control_plane()}),
      "200 text/x-shellscript " ++ X.script("control-plane"))
    X.same("respond 200 escaped token", X.get("/node/join?token=abcdef%2E0123456789abcdef&type=worker", Some{X.worker()}),
      "200 text/x-shellscript " ++ X.script("worker"))
    X.same("respond 400 bad type", X.get("/node/join?token=abcdef.0123456789abcdef&type=master", Some{X.worker()}),
      X.text("400", "invalid node type \"master\"\n"))
    X.same("respond 401 missing token", X.get("/node/join", None{}), X.text("401", "missing token\n"))
    X.same("respond 401 empty token", X.get("/node/join?token=&type=worker", None{}), X.text("401", "missing token\n"))
    X.same("respond 401 malformed token", X.get("/node/join?token=abc.def", Some{X.worker()}), X.text("401", "malformed token\n"))
    X.same("respond 401 unknown token", X.get("/node/join?token=abcdef.0123456789abcdef", None{}), X.text("401", "unknown token\n"))
    X.same("respond 401 wrong secret", X.get("/node/join?token=abcdef.0123456789abcdee", Some{X.worker()}), X.text("401", "invalid token\n"))
    X.same("respond 401 expired token", X.get("/node/join?token=abcdef.0123456789abcdef", Some{X.expired()}), X.text("401", "token expired\n"))
    X.same("respond 403 wrong node type", X.get("/node/join?token=abcdef.0123456789abcdef&type=control-plane", Some{X.worker()}),
      X.text("403", "the token is for worker nodes\n"))
    X.same("respond 403 control-plane token as worker", X.get("/node/join?token=abcdef.0123456789abcdef&type=worker", Some{X.control_plane()}),
      X.text("403", "the token is for control-plane nodes\n"))
    X.same("respond 404 other path", X.get("/node/download?token=abcdef.0123456789abcdef", Some{X.worker()}), X.text("404", "404 page not found\n"))
    X.same("respond 404 root", X.get("/", None{}), X.text("404", "404 page not found\n"))
    X.same("respond 404 before 405", X.respond("DELETE", "/node/joins", None{}, X.test_cert()), X.text("404", "404 page not found\n"))
    X.same("respond 405 POST", X.respond("POST", "/node/join?token=abcdef.0123456789abcdef", Some{X.worker()}, X.test_cert()),
      X.text("405", "Method Not Allowed\n"))
    X.same("respond 405 HEAD", X.respond("HEAD", "/node/join?token=abcdef.0123456789abcdef", Some{X.worker()}, X.test_cert()),
      X.text("405", "Method Not Allowed\n"))
    X.same("respond 405 lower-case get", X.respond("get", "/node/join?token=abcdef.0123456789abcdef", Some{X.worker()}, X.test_cert()),
      X.text("405", "Method Not Allowed\n"))
    X.same("respond 500 no CA", X.respond("GET", "/node/join?token=abcdef.0123456789abcdef", Some{X.worker()}, ""),
      X.text("500", "failed to load CA certificate referenced by kubeconfig: data does not contain any valid RSA or ECDSA certificates\n"))
    X.same("respond 500 two CAs", X.respond("GET", "/node/join?token=abcdef.0123456789abcdef", Some{X.worker()}, X.cert() ++ X.cert()),
      X.text("500", "multiple CA certificates found in configmap kube-root-ca.crt\n"))
    X.same("reason 200", JN.Join.reason(200), "OK")
    X.same("reason 400", JN.Join.reason(400), "Bad Request")
    X.same("reason 401", JN.Join.reason(401), "Unauthorized")
    X.same("reason 403", JN.Join.reason(403), "Forbidden")
    X.same("reason 404", JN.Join.reason(404), "Not Found")
    X.same("reason 405", JN.Join.reason(405), "Method Not Allowed")
    X.same("reason 500", JN.Join.reason(500), "Internal Server Error")
    X.same("render 200 script", JN.Join.render(JN.Join.respond("GET", "/node/join?token=abcdef.0123456789abcdef&type=worker",
      Some{X.worker()}, X.test_cert(), "10.0.2.15:6443", X.now())), X.served(X.script("worker")))
    X.same("render 401", JN.Join.render(JN.Join.respond("GET", "/node/join?token=abcdef.0123456789abcdef", None{}, X.test_cert(),
      "10.0.2.15:6443", X.now())),
      "HTTP/1.1 401 Unauthorized\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: 14\r\nConnection: close\r\n\r\nunknown token\n")
    X.same("render 405", JN.Join.render(JN.Join.respond("PUT", "/node/join", None{}, "", "10.0.2.15:6443", X.now())),
      "HTTP/1.1 405 Method Not Allowed\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: 19\r\nAllow: GET\r\nConnection: close\r\n\r\nMethod Not Allowed\n")
