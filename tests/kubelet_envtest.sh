#!/usr/bin/env bash
# The fake kubelet (host/kubelet_proxy.bend, src/net/kubelet.bend) end to
# end on Linux. It builds host/init.bend natively and starts:
#
# - a virtual control plane: etcd and kube-apiserver from controller-tools'
#   envtest release, whose --kubelet-client-* flags name the apiserver's
#   kubelet client certificate (CN kube-apiserver-kubelet-client);
# - a fake "host" API server (Python, TLS with a client certificate
#   required) that records every request it gets and answers a pod log, a
#   node's stats summary, and 400 to anything else (an exec upgrade);
# - `vk8s kubelet-proxy`, the fake kubelet, between them.
#
# A virtual Node "vnode" points its kubelet endpoint at the proxy, and a
# virtual Pod default/nginx is bound to it. Then kubectl logs, exec and the
# node proxy run against the virtual API server, and curl calls the proxy
# directly; the host must see the requests on the host pod
# nginx-x-default-x-vk8s in namespace vk8s-host.
#
# Needs bend, clang, openssl, curl, python3; downloads envtest 1.36.2
# unless KUBEBUILDER_ASSETS names a directory with etcd, kube-apiserver and
# kubectl. Prints PASS/FAIL lines; exits 1 on any FAIL.
set -uo pipefail
cd "$(dirname "$0")/.."
root=$(pwd)

tmp=$(mktemp -d)
pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done
  rm -rf "$tmp"
}
trap cleanup EXIT

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
check() { # check NAME CONDITION-COMMAND...
  local name=$1; shift
  if "$@"; then pass "$name"; else fail "$name"; fi
}
dump() { # dump FILE...: show logs after a failure
  for f in "$@"; do echo "--- $f"; tail -n 40 "$f" 2>/dev/null; done
}

echo "== envtest binaries"
assets=${KUBEBUILDER_ASSETS:-}
if [ -z "$assets" ]; then
  ver=1.36.2
  case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) echo "FAIL envtest: unknown architecture $(uname -m)"; exit 1 ;;
  esac
  name="envtest-v$ver-linux-$arch.tar.gz"
  url="https://github.com/kubernetes-sigs/controller-tools/releases/download/envtest-v$ver/$name"
  if ! curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 -o "$tmp/$name" "$url" || ! curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 -o "$tmp/$name.sha512" "$url.sha512"; then
    echo "FAIL envtest download"; exit 1
  fi
  want=$(awk '{print $1}' "$tmp/$name.sha512")
  [ "$arch" = amd64 ] && want=ea743186c8a799f5cf8faf16969f86189d003cb7d130e0ac4b58789f1e5748dcf30ebe91c837a10d5ac415383da3e10b9e64d65785c938c23e739781cfb76f08
  got=$(sha512sum "$tmp/$name" | awk '{print $1}')
  if [ "$want" != "$got" ]; then echo "FAIL envtest checksum"; exit 1; fi
  mkdir -p "$tmp/envtest"
  tar -xzf "$tmp/$name" -C "$tmp/envtest"
  assets="$tmp/envtest/controller-tools/envtest"
fi
for b in etcd kube-apiserver kubectl; do
  [ -x "$assets/$b" ] || { echo "FAIL envtest: no $assets/$b"; exit 1; }
done
pass "envtest binaries"

echo "== build"
if ! bend host/init.bend -o "$tmp/vk8s" >"$tmp/build.log" 2>&1; then
  cat "$tmp/build.log"
  echo "FAIL build host/init.bend"
  exit 1
fi
pass "build"

echo "== certificates"
pki="$tmp/pki"
mkdir -p "$pki"
ossl() { openssl "$@" >>"$tmp/openssl.log" 2>&1; }
ec="-newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes"
cd "$pki"
ca() { # ca NAME CN
  # shellcheck disable=SC2086
  ossl req -x509 $ec -keyout "$1.key" -out "$1.pem" -days 2 -subj "/CN=$2"
}
issue() { # issue NAME SUBJECT EXT CA
  # shellcheck disable=SC2086
  ossl req $ec -keyout "$1.key" -out "$1.csr" -subj "$2"
  printf '%b' "$3" >"$1.ext"
  ossl x509 -req -in "$1.csr" -CA "$4.pem" -CAkey "$4.key" -CAcreateserial \
    -days 2 -out "$1.pem" -extfile "$1.ext"
}
ca ca vk8s-ca
ca fpca vk8s-front-proxy-ca
ca hostca host-ca
issue apiserver "/CN=kube-apiserver" "subjectAltName=IP:127.0.0.1,DNS:localhost\nextendedKeyUsage=serverAuth" ca
issue kclient "/O=system:masters/CN=kube-apiserver-kubelet-client" "extendedKeyUsage=clientAuth" ca
issue admin "/O=system:masters/CN=admin" "extendedKeyUsage=clientAuth" ca
issue mallory "/CN=mallory" "extendedKeyUsage=clientAuth" ca
issue kserve "/CN=vnode" "subjectAltName=DNS:vnode,DNS:vnode.nodes.vcluster.com,IP:127.0.0.1\nextendedKeyUsage=serverAuth" ca
issue fpclient "/CN=front-proxy-client" "extendedKeyUsage=clientAuth" fpca
issue host "/CN=host-apiserver" "subjectAltName=IP:127.0.0.1\nextendedKeyUsage=serverAuth" hostca
issue syncer "/CN=vk8s-syncer" "extendedKeyUsage=clientAuth" hostca
ossl ecparam -genkey -name prime256v1 -noout -out sa.key
ossl ec -in sa.key -pubout -out sa.pub
cd "$root"
if [ -s "$pki/kserve.pem" ] && [ -s "$pki/syncer.pem" ] && [ -s "$pki/sa.pub" ]; then
  pass "certificates"
else
  cat "$tmp/openssl.log"; echo "FAIL certificates"; exit 1
fi

base=$((20000 + RANDOM % 20000))
pe=$base            # etcd client
pp=$((base + 1))    # etcd peer
pa=$((base + 2))    # virtual kube-apiserver
ph=$((base + 3))    # fake host API server
pk=$((base + 4))    # the fake kubelet
wait_for() { # wait_for SECONDS COMMAND...
  local n=$(($1 * 10)); shift
  for _ in $(seq "$n"); do
    "$@" >/dev/null 2>&1 && return 0
    sleep 0.1
  done
  return 1
}

echo "== virtual control plane"
"$assets/etcd" --data-dir "$tmp/etcd" --name default \
  --listen-client-urls "http://127.0.0.1:$pe" --advertise-client-urls "http://127.0.0.1:$pe" \
  --listen-peer-urls "http://127.0.0.1:$pp" --initial-advertise-peer-urls "http://127.0.0.1:$pp" \
  --initial-cluster "default=http://127.0.0.1:$pp" >"$tmp/etcd.log" 2>&1 &
pids+=($!)
"$assets/kube-apiserver" \
  --etcd-servers="http://127.0.0.1:$pe" \
  --bind-address=127.0.0.1 --advertise-address=127.0.0.1 --secure-port="$pa" \
  --tls-cert-file="$pki/apiserver.pem" --tls-private-key-file="$pki/apiserver.key" \
  --client-ca-file="$pki/ca.pem" \
  --service-account-issuer=https://kubernetes.default.svc \
  --service-account-key-file="$pki/sa.pub" --service-account-signing-key-file="$pki/sa.key" \
  --service-cluster-ip-range=10.0.0.0/24 \
  --authorization-mode=RBAC \
  --disable-admission-plugins=ServiceAccount \
  --kubelet-client-certificate="$pki/kclient.pem" --kubelet-client-key="$pki/kclient.key" \
  --kubelet-preferred-address-types=InternalIP \
  --requestheader-client-ca-file="$pki/fpca.pem" --requestheader-allowed-names=front-proxy-client \
  --requestheader-username-headers=X-Remote-User --requestheader-group-headers=X-Remote-Group \
  --requestheader-extra-headers-prefix=X-Remote-Extra- \
  >"$tmp/apiserver.log" 2>&1 &
pids+=($!)
ready() {
  [ "$(curl -s --cacert "$pki/ca.pem" --cert "$pki/admin.pem" --key "$pki/admin.key" "https://127.0.0.1:$pa/readyz")" = ok ]
}
if wait_for 90 ready; then pass "kube-apiserver ready"; else dump "$tmp/etcd.log" "$tmp/apiserver.log"; echo "FAIL kube-apiserver ready"; exit 1; fi

cat >"$tmp/kubeconfig" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: virtual
  cluster:
    server: https://127.0.0.1:$pa
    certificate-authority: $pki/ca.pem
users:
- name: admin
  user:
    client-certificate: $pki/admin.pem
    client-key: $pki/admin.key
contexts:
- name: virtual
  context:
    cluster: virtual
    user: admin
current-context: virtual
EOF
kc() { "$assets/kubectl" --kubeconfig "$tmp/kubeconfig" --request-timeout=30s "$@"; }

echo "== fake host API server"
cat >"$tmp/host.py" <<'EOF'
import http.server, json, ssl, sys

port, cert, key, ca, log = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
SUMMARY = {
    "node": {"nodeName": "vnode"},
    "pods": [
        {"podRef": {"name": "nginx-x-default-x-vk8s", "namespace": "vk8s-host", "uid": "host-uid-1"},
         "cpu": {"usageNanoCores": 1000}},
        {"podRef": {"name": "intruder", "namespace": "other-tenant", "uid": "host-uid-2"}},
    ],
}


class Host(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def any(self):
        with open(log, "a") as f:
            f.write("%s %s upgrade=%s auth=%s impersonate=%s\n" % (
                self.command, self.path, self.headers.get("Upgrade", ""),
                "yes" if self.headers.get("Authorization") else "no",
                self.headers.get("Impersonate-User", "")))
        path = self.path.split("?")[0]
        if path.startswith("/api/v1/namespaces/vk8s-host/pods/") and path.endswith("/log"):
            self.reply(200, "text/plain", b"hello from the host pod\n")
        elif path == "/api/v1/nodes/vnode/proxy/stats/summary":
            self.reply(200, "application/json", json.dumps(SUMMARY).encode())
        else:
            status = {"kind": "Status", "apiVersion": "v1", "metadata": {}, "status": "Failure",
                      "message": "fake host: no upgrade here", "reason": "BadRequest", "code": 400}
            self.reply(400, "application/json", json.dumps(status).encode())

    def reply(self, code, ctype, body):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.end_headers()
        self.wfile.write(body)

    do_GET = do_POST = any

    def log_message(self, *args):
        pass


srv = http.server.ThreadingHTTPServer(("127.0.0.1", port), Host)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(cert, key)
ctx.load_verify_locations(ca)
ctx.verify_mode = ssl.CERT_REQUIRED
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
print("ready", flush=True)
srv.serve_forever()
EOF
touch "$tmp/host-requests.log"
python3 "$tmp/host.py" "$ph" "$pki/host.pem" "$pki/host.key" "$pki/hostca.pem" "$tmp/host-requests.log" >"$tmp/host.log" 2>&1 &
pids+=($!)
if wait_for 20 grep -q '^ready' "$tmp/host.log"; then pass "fake host ready"; else dump "$tmp/host.log"; echo "FAIL fake host ready"; exit 1; fi

echo "== the fake kubelet"
"$tmp/vk8s" kubelet-proxy --bind=127.0.0.1 --port="$pk" \
  --cert="$pki/kserve.pem" --key="$pki/kserve.key" --client-ca="$pki/ca.pem" \
  --vcluster=vk8s --target=vk8s-host --current=vk8s-host \
  --host=127.0.0.1 --host-port="$ph" --host-ca="$pki/hostca.pem" --host-cert="$pki/syncer.pem" --host-key="$pki/syncer.key" \
  --virtual=127.0.0.1 --virtual-port="$pa" --virtual-ca="$pki/ca.pem" \
  --virtual-cert="$pki/fpclient.pem" --virtual-key="$pki/fpclient.key" >"$tmp/proxy.log" 2>&1 &
pids+=($!)
if wait_for 20 grep -q 'listening' "$tmp/proxy.log"; then pass "kubelet-proxy listening"; else dump "$tmp/proxy.log"; echo "FAIL kubelet-proxy listening"; exit 1; fi

echo "== virtual node and pod"
kc apply -f - >"$tmp/kubectl.log" 2>&1 <<EOF
apiVersion: v1
kind: Node
metadata:
  name: vnode
EOF
kc patch node vnode --subresource=status --type=merge \
  -p "{\"status\":{\"addresses\":[{\"type\":\"InternalIP\",\"address\":\"127.0.0.1\"},{\"type\":\"Hostname\",\"address\":\"vnode.nodes.vcluster.com\"}],\"daemonEndpoints\":{\"kubeletEndpoint\":{\"Port\":$pk}}}}" \
  >>"$tmp/kubectl.log" 2>&1
kc apply -f - >>"$tmp/kubectl.log" 2>&1 <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  namespace: default
spec:
  nodeName: vnode
  containers:
  - name: web
    image: nginx
EOF
if kc get pod nginx >/dev/null 2>&1 && kc get node vnode -o jsonpath='{.status.daemonEndpoints.kubeletEndpoint.Port}' | grep -qx "$pk"; then
  pass "node and pod"
else
  dump "$tmp/kubectl.log"; echo "FAIL node and pod"; exit 1
fi

hostlog="$tmp/host-requests.log"
seen() { grep -F -- "$1" "$hostlog" | grep -qF -- "$2"; }
has() { grep -qF -- "$1" <<<"$2"; }
lacks() { ! grep -qF -- "$1" <<<"$2"; }

echo "== kubectl logs"
out=$(kc logs nginx -c web --tail=5 --timestamps 2>&1)
check "kubectl logs reaches the host pod" has "hello from the host pod" "$out"
check "host log request names the host pod" seen "GET /api/v1/namespaces/vk8s-host/pods/nginx-x-default-x-vk8s/log?container=web&" "tailLines=5"
check "host log request keeps timestamps" seen "/pods/nginx-x-default-x-vk8s/log?container=web&" "timestamps=true"
check "host requests carry no client credentials" lacks "auth=yes" "$(cat "$hostlog")"

echo "== kubectl logs --follow"
out=$(timeout 20 "$assets/kubectl" --kubeconfig "$tmp/kubeconfig" logs -f nginx -c web 2>&1)
check "followed logs stream through" has "hello from the host pod" "$out"
check "follow passes to the host" seen "/pods/nginx-x-default-x-vk8s/log?container=web&" "follow=true"

echo "== kubectl exec"
timeout 40 "$assets/kubectl" --kubeconfig "$tmp/kubeconfig" exec nginx -c web -- echo hi >"$tmp/exec.log" 2>&1
check "exec reaches the host pod" seen "/api/v1/namespaces/vk8s-host/pods/nginx-x-default-x-vk8s/exec?container=web&command=echo&command=hi" "stdout=true"
check "exec is an upgrade at the host" lacks "upgrade= " "$(grep -F '/pods/nginx-x-default-x-vk8s/exec?' "$hostlog")"

echo "== node proxy through the virtual API server"
out=$(kc get --raw /api/v1/nodes/vnode/proxy/healthz 2>&1)
check "nodes/proxy healthz is ok" test "$out" = ok

echo "== the kubelet API directly"
kcurl() { # kcurl CERT PATH: curl the proxy as the node's hostname
  curl -s --max-time 20 --cacert "$pki/ca.pem" --cert "$pki/$1.pem" --key "$pki/$1.key" \
    --resolve "vnode.nodes.vcluster.com:$pk:127.0.0.1" "https://vnode.nodes.vcluster.com:$pk$2"
}
out=$(kcurl kclient /healthz)
check "healthz" test "$out" = ok
out=$(kcurl kclient /stats/summary)
check "stats renamed to the virtual pod" has '"podRef":{"name":"nginx","namespace":"default","uid":"' "$out"
check "stats drop other tenants" lacks intruder "$out"
check "stats asked the host node" seen "GET /api/v1/nodes/vnode/proxy/stats/summary" "GET"
out=$(kcurl kclient /pods)
check "pods lists the virtual pod" has '"name":"nginx"' "$out"
out=$(kcurl kclient /containerLogs/default/nginx/injected-sidecar)
check "unknown container is forbidden" has 'pod does not belong to this virtual cluster' "$out"
out=$(kcurl kclient /containerLogs/default/missing/web)
check "missing pod is forbidden" has 'pod does not belong to this virtual cluster' "$out"
out=$(kcurl mallory /healthz)
check "another identity is forbidden" has 'cannot get path' "$out"
check "no client certificate, no handshake" sh -c "! curl -s --max-time 10 --cacert '$pki/ca.pem' --resolve 'vnode.nodes.vcluster.com:$pk:127.0.0.1' 'https://vnode.nodes.vcluster.com:$pk/healthz' >/dev/null"

if [ $fails -gt 0 ]; then
  dump "$tmp/proxy.log" "$hostlog" "$tmp/exec.log" "$tmp/apiserver.log"
  echo "$fails FAILED"
  exit 1
fi
echo "ALL PASSED"
