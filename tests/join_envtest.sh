#!/usr/bin/env bash
# The standalone join server (host/join_server.bend, src/standalone/join.bend)
# end to end on Linux. It builds host/init.bend natively and starts:
#
# - a control plane: etcd and kube-apiserver from controller-tools'
#   envtest release, with requestheader authentication for the
#   front-proxy client certificate, as kubeadm configures it in the guest;
# - `vk8s join-server`, which reads bootstrap token Secrets as the user
#   vk8s:join-server (no groups) and answers /node/join.
#
# Bootstrap token Secrets in the shape of `vk8s token create`
# (Join.token_secret) go in with kubectl. Before the Role and RoleBinding
# of Plan.join_server_role/binding exist, the server must not read them;
# after, `curl | sh -s -- --force-join` runs the served script with a fake
# kubeadm first in PATH, which records its arguments. They must be
# `join <endpoint> --token <t> --discovery-token-ca-cert-hash sha256:<hash>`,
# with the hash from openssl. The errors: 401 for a malformed, unknown or
# expired token, 403 for the wrong node type, 404 for another path, 405
# for a POST.
#
# Needs bend, clang, openssl, curl; downloads envtest 1.36.2 unless
# KUBEBUILDER_ASSETS names a directory with etcd, kube-apiserver and
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
issue() { # issue NAME SUBJECT EXT CA
  # shellcheck disable=SC2086
  ossl req $ec -keyout "$1.key" -out "$1.csr" -subj "$2"
  printf '%b' "$3" >"$1.ext"
  ossl x509 -req -in "$1.csr" -CA "$4.pem" -CAkey "$4.key" -CAcreateserial \
    -days 2 -out "$1.pem" -extfile "$1.ext"
}
# The cluster CA is RSA 2048, as kubeadm makes it: its DER lengths take
# two bytes, which Join.ca_hash must read.
ossl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.pem -days 2 -subj "/CN=kubernetes"
# shellcheck disable=SC2086
ossl req -x509 $ec -keyout fpca.key -out fpca.pem -days 2 -subj "/CN=front-proxy-ca"
issue apiserver "/CN=kube-apiserver" "subjectAltName=IP:127.0.0.1,IP:10.10.0.2,DNS:localhost\nextendedKeyUsage=serverAuth" ca
issue admin "/O=system:masters/CN=admin" "extendedKeyUsage=clientAuth" ca
issue fpclient "/CN=front-proxy-client" "extendedKeyUsage=clientAuth" fpca
ossl ecparam -genkey -name prime256v1 -noout -out sa.key
ossl ec -in sa.key -pubout -out sa.pub
cd "$root"
if [ -s "$pki/apiserver.pem" ] && [ -s "$pki/fpclient.pem" ] && [ -s "$pki/sa.pub" ]; then
  pass "certificates"
else
  cat "$tmp/openssl.log"; echo "FAIL certificates"; exit 1
fi
# kubeadm's --discovery-token-ca-cert-hash: SHA-256 of the CA's DER
# SubjectPublicKeyInfo.
cahash=sha256:$(openssl x509 -in "$pki/ca.pem" -noout -pubkey | openssl pkey -pubin -outform der | sha256sum | awk '{print $1}')

base=$((20000 + RANDOM % 20000))
pe=$base            # etcd client
pp=$((base + 1))    # etcd peer
pa=$((base + 2))    # kube-apiserver
pj=$((base + 3))    # the join server
wait_for() { # wait_for SECONDS COMMAND...
  local n=$(($1 * 10)); shift
  for _ in $(seq "$n"); do
    "$@" >/dev/null 2>&1 && return 0
    sleep 0.1
  done
  return 1
}

echo "== control plane"
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
- name: vk8s
  cluster:
    server: https://127.0.0.1:$pa
    certificate-authority: $pki/ca.pem
users:
- name: admin
  user:
    client-certificate: $pki/admin.pem
    client-key: $pki/admin.key
contexts:
- name: vk8s
  context:
    cluster: vk8s
    user: admin
current-context: vk8s
EOF
kc() { "$assets/kubectl" --kubeconfig "$tmp/kubeconfig" --request-timeout=30s "$@"; }

echo "== token Secrets"
b64() { printf %s "$1" | base64 | tr -d '\n'; }
# secret ID SECRET NODE-TYPE [EXPIRATION]: a Secret as Join.token_secret
# writes it.
secret() {
  local exp=""
  [ -n "${4:-}" ] && exp=",\"expiration\":\"$(b64 "$4")\""
  printf '%s' "{\"apiVersion\":\"v1\",\"kind\":\"Secret\",\"metadata\":{\"name\":\"bootstrap-token-$1\",\"namespace\":\"kube-system\",\"labels\":{\"vcluster.loft.sh/token\":\"true\",\"vcluster.loft.sh/token-node-type\":\"$3\"}},\"type\":\"bootstrap.kubernetes.io/token\",\"data\":{\"token-id\":\"$(b64 "$1")\",\"token-secret\":\"$(b64 "$2")\",\"usage-bootstrap-signing\":\"$(b64 true)\",\"usage-bootstrap-authentication\":\"$(b64 true)\",\"auth-extra-groups\":\"$(b64 system:bootstrappers:kubeadm:default-node-token)\",\"description\":\"$(b64 'token generated by cluster-api-bootstrap-provider-kubeadm')\"$exp}}" \
    | kc apply -f - >>"$tmp/kubectl.log" 2>&1
}
worker=abcdef.0123456789abcdef
cp=cpcpcp.0123456789abcdef
old=old000.0123456789abcdef
secret abcdef 0123456789abcdef worker
secret cpcpcp 0123456789abcdef control-plane
secret old000 0123456789abcdef worker 2000-01-01T00:00:00Z
if [ "$(kc -n kube-system get secrets -o name 2>/dev/null | grep -c bootstrap-token-)" = 3 ]; then
  pass "token Secrets"
else
  dump "$tmp/kubectl.log"; echo "FAIL token Secrets"; exit 1
fi

echo "== the join server"
"$tmp/vk8s" join-server --bind=0.0.0.0 --port="$pj" \
  --cert="$pki/apiserver.pem" --key="$pki/apiserver.key" --ca="$pki/ca.pem" \
  --api=127.0.0.1 --api-port="$pa" --api-ca="$pki/ca.pem" \
  --api-cert="$pki/fpclient.pem" --api-key="$pki/fpclient.key" >"$tmp/join.log" 2>&1 &
pids+=($!)
if wait_for 20 grep -q 'listening' "$tmp/join.log"; then pass "join-server listening"; else dump "$tmp/join.log"; echo "FAIL join-server listening"; exit 1; fi

# get METHOD PATH: the status; the head goes to $tmp/head, the body to
# $tmp/body.
get() {
  curl -sk --max-time 20 -X "$1" -D "$tmp/head" -o "$tmp/body" -w '%{http_code}' "https://127.0.0.1:$pj$2"
}
body() { cat "$tmp/body"; }
has() { grep -qF -- "$1" <<<"$2"; }

echo "== no RBAC yet: the server's own user reads nothing"
check "without the Role the worker token is unknown" test "$(get GET "/node/join?token=$worker&type=worker")" = 401
check "the answer names an unknown token" test "$(body)" = "unknown token"

echo "== RBAC (Plan.join_server_role, Plan.join_server_binding)"
kc create role vk8s:join-server --namespace=kube-system --verb=get --resource=secrets >>"$tmp/kubectl.log" 2>&1
kc create rolebinding vk8s:join-server --namespace=kube-system --role=vk8s:join-server --user=vk8s:join-server >>"$tmp/kubectl.log" 2>&1
check "the join server may get Secrets in kube-system" test "$(kc auth can-i get secrets -n kube-system --as=vk8s:join-server 2>/dev/null)" = yes
check "the join server may not list Secrets" test "$(kc auth can-i list secrets -n kube-system --as=vk8s:join-server 2>/dev/null)" = no
check "the join server may not get Secrets elsewhere" test "$(kc auth can-i get secrets -n default --as=vk8s:join-server 2>/dev/null)" = no
# RBAC caches nothing, but give the binding a moment to reach the authorizer.
wait_for 10 sh -c "test \"\$(curl -sk -o /dev/null -w '%{http_code}' 'https://127.0.0.1:$pj/node/join?token=$worker&type=worker')\" = 200"

echo "== curl | sh"
mkdir -p "$tmp/bin"
cat >"$tmp/bin/kubeadm" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$KUBEADM_LOG"
EOF
chmod +x "$tmp/bin/kubeadm"
export KUBEADM_LOG="$tmp/kubeadm.log"
: >"$KUBEADM_LOG"
curl -sfLk --max-time 20 "https://127.0.0.1:$pj/node/join?token=$worker&type=worker" | PATH="$tmp/bin:$PATH" sh -s -- --force-join >"$tmp/script.log" 2>&1
st=$?
check "the script runs" test "$st" = 0
want="join 10.10.0.2:6443 --token $worker --discovery-token-ca-cert-hash $cahash"
check "kubeadm join gets the endpoint, the token and openssl's CA hash" test "$(tail -n 1 "$KUBEADM_LOG")" = "$want"
[ "$(tail -n 1 "$KUBEADM_LOG")" = "$want" ] || { echo "want: $want"; echo "got:"; cat "$KUBEADM_LOG" "$tmp/script.log"; }

echo "== answers"
check "a worker token without a type is served" test "$(get GET "/node/join?token=$worker")" = 200
check "the script is text/x-shellscript" has "Content-Type: text/x-shellscript" "$(cat "$tmp/head")"
check "the script carries the CA hash" has "$cahash" "$(body)"
check "an unknown token is 401" test "$(get GET "/node/join?token=zzzzzz.0123456789abcdef&type=worker")" = 401
check "an unknown token says so" test "$(body)" = "unknown token"
check "an expired token is 401" test "$(get GET "/node/join?token=$old&type=worker")" = 401
check "an expired token says so" test "$(body)" = "token expired"
check "a wrong secret is 401" test "$(get GET "/node/join?token=abcdef.ffffffffffffffff&type=worker")" = 401
check "a malformed token is 401" test "$(get GET "/node/join?token=bad&type=worker")" = 401
check "a malformed token says so" test "$(body)" = "malformed token"
check "a missing token is 401" test "$(get GET "/node/join?type=worker")" = 401
check "a control-plane token asked as worker is 403" test "$(get GET "/node/join?token=$cp&type=worker")" = 403
check "the 403 names the token's type" test "$(body)" = "the token is for control-plane nodes"
check "a bad type is 400" test "$(get GET "/node/join?token=$worker&type=master")" = 400
check "another path is 404" test "$(get GET "/healthz")" = 404
check "the 404 is Go's" test "$(body)" = "404 page not found"
check "a POST is 405" test "$(get POST "/node/join?token=$worker&type=worker")" = 405
check "the 405 allows GET" has "Allow: GET" "$(cat "$tmp/head")"
check "no client certificate is needed" test "$(get GET "/node/join?token=$worker")" = 200
check "the log never shows a token secret" sh -c "! grep -q 0123456789abcdef '$tmp/join.log'"

if [ $fails -gt 0 ]; then
  dump "$tmp/join.log" "$tmp/kubectl.log" "$tmp/apiserver.log"
  echo "$fails FAILED"
  exit 1
fi
echo "ALL PASSED"
