#!/usr/bin/env bash
# A stub OCI registry over TLS for the host's registry client tests
# (tests/layers_serve.sh, tests/cache_mirror.sh). Source it, then
#
#   stub_registry TMP PORT
#
# makes TMP/ca.pem (a test CA; trust it with SSL_CERT_FILE) and serves
# https://127.0.0.1:PORT, as VK8S_UPSTREAM then names it. It serves
# /v2/library/busybox/{manifests,blobs}/<digest> from TMP/reg/<digest>,
# asks for a token as Docker Hub does (/v2/ and every repository request
# without "Bearer t-repository:library/busybox:pull" answer 401 with a
# Bearer challenge; /token hands out "t-<scope>"), logs each path to
# TMP/reg.log and each repository request's Authorization to
# TMP/auth.log, waits TMP/delay seconds (when that file exists) before
# each blob, and sends a blob's body in pieces of TMP/drip bytes, 50 ms
# apart (when that file exists). Its pid is in stub_pid.
stub_registry() {
  local tmp=$1 sport=$2
  # A test CA and the stub's certificate for 127.0.0.1.
  (
    cd "$tmp" &&
      openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -keyout ca.key -out ca.pem -days 2 -subj "/CN=vk8s-test-ca" &&
      openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -keyout stub.key -out stub.csr -subj "/CN=127.0.0.1" &&
      printf 'subjectAltName=IP:127.0.0.1\nextendedKeyUsage=serverAuth\n' >stub.ext &&
      openssl x509 -req -in stub.csr -CA ca.pem -CAkey ca.key -CAcreateserial -days 2 -out stub.pem -extfile stub.ext
  ) >"$tmp/openssl.log" 2>&1 || {
    cat "$tmp/openssl.log"
    echo "FAIL certificates"
    return 1
  }
  cat >"$tmp/registry.py" <<'PY'
import http.server, os, ssl, sys, time, urllib.parse
tmp, port = sys.argv[1], int(sys.argv[2])
base = f"https://127.0.0.1:{port}"
want = "Bearer t-repository:library/busybox:pull"

class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a):
        pass
    def answer(self, code, body=b"", kind="application/octet-stream", extra=()):
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        for k, v in extra:
            self.send_header(k, v)
        self.send_header("Connection", "close")
        self.end_headers()
        drip = f"{tmp}/drip"
        if len(body) > 0 and kind == "application/octet-stream" and os.path.exists(drip):
            n = int(open(drip).read())
            for i in range(0, len(body), n):
                self.wfile.write(body[i:i + n])
                self.wfile.flush()
                time.sleep(0.05)
        else:
            self.wfile.write(body)
    def challenge(self, scope):
        c = f'Bearer realm="{base}/token",service="stub"' + (f',scope="{scope}"' if scope else "")
        self.answer(401, b'{"errors":[{"code":"UNAUTHORIZED"}]}', "application/json", [("WWW-Authenticate", c)])
    def do_GET(self):
        with open(f"{tmp}/reg.log", "a") as f:
            f.write(self.path + "\n")
        u = urllib.parse.urlparse(self.path)
        if u.path == "/token":
            q = urllib.parse.parse_qs(u.query)
            tok = "t-" + " ".join(q.get("scope", []))
            return self.answer(200, ('{"token":"%s","expires_in":300}' % tok).encode(), "application/json")
        if u.path == "/v2/":
            return self.challenge("")
        parts = u.path.split("/")
        if len(parts) == 6 and parts[:4] == ["", "v2", "library", "busybox"] and parts[4] in ("manifests", "blobs"):
            auth = self.headers.get("Authorization", "")
            with open(f"{tmp}/auth.log", "a") as f:
                f.write(auth + "\n")
            if auth != want:
                return self.challenge("repository:library/busybox:pull")
            p = f"{tmp}/reg/{parts[5]}"
            if "/" in parts[5] or not os.path.isfile(p):
                return self.answer(404)
            if parts[4] == "blobs" and os.path.exists(f"{tmp}/delay"):
                time.sleep(float(open(f"{tmp}/delay").read()))
            kind = "application/vnd.oci.image.manifest.v1+json" if parts[4] == "manifests" else "application/octet-stream"
            return self.answer(200, open(p, "rb").read(), kind)
        self.answer(404)

srv = http.server.ThreadingHTTPServer(("127.0.0.1", port), H)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(f"{tmp}/stub.pem", f"{tmp}/stub.key")
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
srv.serve_forever()
PY
  python3 -I "$tmp/registry.py" "$tmp" "$sport" >"$tmp/registry.err" 2>&1 &
  stub_pid=$!
}
