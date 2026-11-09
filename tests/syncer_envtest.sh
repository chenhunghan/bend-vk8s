#!/usr/bin/env bash
# The classic-mode syncer (host/syncer.bend) between two real control
# planes. It starts two etcd + kube-apiserver pairs (the official Linux
# binaries for this machine's architecture; no kubelets, no controller
# managers): a "virtual" cluster and a "host" cluster. It builds
# host/init.bend natively, runs two `vk8s-guest syncer` replicas between
# them and checks with kubectl:
#
# - only one replica holds the Lease vcluster-demo/vcluster-demo-controller on the host in
#   the virtual cluster; the other stays passive;
# - the host namespace is created;
# - a virtual Service, and a ConfigMap and a Secret that a virtual Pod
#   refers to, appear in the host namespace under vcluster's single
#   namespace names (SafeConcatName(name, "x", namespace, "x", vc):
#   pkg/util/translate/single_namespace.go), with the managed-by label and
#   the object-name/object-namespace annotations (translate/types.go);
# - a virtual delete removes the host copy; a host delete of a synced
#   ConfigMap removes the virtual one (vcluster's configmaps syncer:
#   host deleted while cached, virtual deleted);
# - the virtual service gets the host service's cluster IP (vcluster's
#   services syncer: the host create clears the cluster IP, then Sync
#   recreates the virtual service with the host one). As in vcluster,
#   both control planes use the host's service CIDR: a virtual
#   apiserver with another range rejects the host IP with 422;
# - after SIGTERM to the leader, the standby takes the Lease and syncs.
#
# Pods are not synced until the pod translator (#9) merges: the Pod here
# only supplies the references that gate ConfigMap and Secret sync.
#
# Needs: bend, clang (bend's native build), openssl, curl, Linux.
# Usage: tests/syncer_envtest.sh   (K8S, ETCD override the versions;
# ENVTEST_CACHE the download directory; KEEP=1 keeps the work directory;
# ENVTEST_TIMEOUT the bound of the whole run in seconds, default 900)
set -uo pipefail
cd "$(dirname "$0")/.."

# The whole run is bounded: a hung check or process reports instead of
# holding the job. timeout signals its process group, so the control
# planes and the syncers stop too.
if [ -z "${SYNCER_ENVTEST_BOUNDED:-}" ]; then
  SYNCER_ENVTEST_BOUNDED=1 timeout -k 30 "${ENVTEST_TIMEOUT:-900}" "tests/$(basename "$0")" "$@"
  rc=$?
  [ $rc -eq 124 ] && echo "FAIL syncer envtest timed out after ${ENVTEST_TIMEOUT:-900}s"
  exit $rc
fi

K8S=${K8S:-v1.36.6}
ETCD=${ETCD:-v3.5.21}
case $(uname -m) in
  x86_64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) echo "unsupported architecture $(uname -m)"; exit 1 ;;
esac
cache=${ENVTEST_CACHE:-$HOME/.cache/vk8s-envtest/$K8S-$ETCD-$arch}
work=$(mktemp -d)
pids=()
# cleanup stops every process it started: SIGTERM, up to 10 seconds,
# then SIGKILL. It never waits without a bound.
cleanup() {
  local p i alive
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done
  for ((i = 0; i < 20; i++)); do
    alive=0
    for p in "${pids[@]}"; do kill -0 "$p" 2>/dev/null && alive=1; done
    [ $alive = 0 ] && break
    sleep 0.5
  done
  for p in "${pids[@]}"; do kill -KILL "$p" 2>/dev/null; done
  wait 2>/dev/null
  if [ "${KEEP:-}" = 1 ]; then echo "work directory: $work"; else rm -rf "$work"; fi
}
trap cleanup EXIT
trap 'echo "FAIL interrupted"; exit 124' TERM INT

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
skip() { echo "SKIP $*"; }
# eventually NAME SECONDS COMMAND...: COMMAND succeeds within SECONDS
eventually() {
  local name=$1 secs=$2; shift 2
  local i
  for ((i = 0; i < secs * 2; i++)); do
    if "$@" >/dev/null 2>&1; then pass "$name"; return 0; fi
    sleep 0.5
  done
  fail "$name"; return 1
}

echo "== binaries ($K8S, etcd $ETCD, $arch)"
mkdir -p "$cache"
get() { # get URL FILE
  [ -s "$cache/$2" ] && return 0
  curl --proto '=https' --tlsv1.2 -fsSL -o "$cache/$2.part" "$1" && mv "$cache/$2.part" "$cache/$2"
}
get "https://dl.k8s.io/release/$K8S/bin/linux/$arch/kube-apiserver" kube-apiserver || { echo "FAIL download kube-apiserver"; exit 1; }
get "https://dl.k8s.io/release/$K8S/bin/linux/$arch/kubectl" kubectl || { echo "FAIL download kubectl"; exit 1; }
if [ ! -s "$cache/etcd" ]; then
  get "https://github.com/etcd-io/etcd/releases/download/$ETCD/etcd-$ETCD-linux-$arch.tar.gz" etcd.tgz \
    || { echo "FAIL download etcd"; exit 1; }
  tar -xzf "$cache/etcd.tgz" -C "$cache" --strip-components=1 "etcd-$ETCD-linux-$arch/etcd"
fi
chmod +x "$cache/kube-apiserver" "$cache/kubectl" "$cache/etcd"
pass "binaries"

echo "== build (bend host/init.bend)"
if ! bend host/init.bend -o "$work/vk8s-guest" >"$work/build.log" 2>&1; then
  cat "$work/build.log"; echo "FAIL build host/init.bend"; exit 1
fi
pass "build"

echo "== certificates"
pki=$work/pki
mkdir -p "$pki"
(
  cd "$pki" || exit 1
  openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt -days 2 -subj "/CN=envtest-ca" 2>/dev/null
  openssl req -newkey rsa:2048 -nodes -keyout server.key -out server.csr -subj "/CN=kube-apiserver" 2>/dev/null
  printf 'subjectAltName=IP:127.0.0.1,DNS:localhost\nextendedKeyUsage=serverAuth\n' > server.ext
  openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 2 -extfile server.ext 2>/dev/null
  openssl req -newkey rsa:2048 -nodes -keyout admin.key -out admin.csr -subj "/O=system:masters/CN=admin" 2>/dev/null
  printf 'extendedKeyUsage=clientAuth\n' > admin.ext
  openssl x509 -req -in admin.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out admin.crt -days 2 -extfile admin.ext 2>/dev/null
  openssl genrsa -out sa.key 2048 2>/dev/null
  openssl rsa -in sa.key -pubout -out sa.pub 2>/dev/null
) && [ -s "$pki/admin.crt" ] && [ -s "$pki/sa.pub" ] || { echo "FAIL certificates"; exit 1; }
pass "certificates"

# cluster NAME ETCD_PORT PEER_PORT API_PORT SERVICE_CIDR
cluster() {
  local name=$1 ep=$2 pp=$3 port=$4 cidr=$5 d=$work/$1
  mkdir -p "$d"
  "$cache/etcd" --name "$name" --data-dir "$d/etcd" \
    --listen-client-urls "http://127.0.0.1:$ep" --advertise-client-urls "http://127.0.0.1:$ep" \
    --listen-peer-urls "http://127.0.0.1:$pp" --initial-advertise-peer-urls "http://127.0.0.1:$pp" \
    --initial-cluster "$name=http://127.0.0.1:$pp" > "$d/etcd.log" 2>&1 &
  pids+=($!)
  "$cache/kube-apiserver" --etcd-servers "http://127.0.0.1:$ep" \
    --bind-address 127.0.0.1 --advertise-address 127.0.0.1 --secure-port "$port" --cert-dir "$d/certs" \
    --tls-cert-file "$pki/server.crt" --tls-private-key-file "$pki/server.key" --client-ca-file "$pki/ca.crt" \
    --service-account-issuer https://kubernetes.default.svc.cluster.local \
    --service-account-key-file "$pki/sa.pub" --service-account-signing-key-file "$pki/sa.key" \
    --service-cluster-ip-range "$cidr" --authorization-mode RBAC \
    --disable-admission-plugins ServiceAccount > "$d/apiserver.log" 2>&1 &
  pids+=($!)
  cat > "$d/kubeconfig" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: $name
  cluster:
    server: https://127.0.0.1:$port
    certificate-authority: $pki/ca.crt
users:
- name: admin
  user:
    client-certificate: $pki/admin.crt
    client-key: $pki/admin.key
contexts:
- name: $name
  context:
    cluster: $name
    user: admin
current-context: $name
EOF
}

echo "== control planes"
# vcluster runs the virtual control plane with the host's service CIDR
# (it detects the host range), so the host cluster IP that Sync copies
# back is valid in the virtual cluster too.
CIDR=10.96.0.0/16
cluster virtual 32379 32380 36443 "$CIDR"
cluster host 42379 42380 46443 "$CIDR"
V=$work/virtual/kubeconfig
H=$work/host/kubeconfig
# Every kubectl call is bounded, so no single check can hang.
kv() { "$cache/kubectl" --request-timeout=10s --kubeconfig "$V" "$@"; }
kh() { "$cache/kubectl" --request-timeout=10s --kubeconfig "$H" "$@"; }
eventually "virtual API ready" 60 kv get --raw /readyz || { tail -20 "$work/virtual/apiserver.log"; exit 1; }
eventually "host API ready" 60 kh get --raw /readyz || { tail -20 "$work/host/apiserver.log"; exit 1; }
eventually "virtual kube-system namespace" 30 kv get namespace kube-system
eventually "virtual default namespace" 30 kv get namespace default

echo "== syncers"
NS=vcluster-demo
# Both replicas read a vcluster.yaml that also enables service accounts
# (sync.toHost.serviceAccounts.enabled; the chart default is false).
printf 'sync:\n  toHost:\n    serviceAccounts:\n      enabled: true\n' > "$work/vcluster.yaml"
# syncer NAME: a replica (its Lease identity starts with NAME); its pid in $last
syncer() {
  HOSTNAME=$1 "$work/vk8s-guest" syncer --kubeconfig "$V" --host-kubeconfig "$H" --host-namespace "$NS" \
    --name demo --service-cidr "$CIDR" --config "$work/vcluster.yaml" > "$work/$1.log" 2>&1 &
  last=$!
  pids+=("$last")
}
holder_is() { kh -n vcluster-demo get lease vcluster-demo-controller -o 'jsonpath={.spec.holderIdentity}' | grep -q "^$1_"; }
gone() { ! "$@"; }
# A key from the initial list must stay pending until all nine stores
# are ready. Popping it early consumes the sole reconcile worker forever.
kv -n default create service clusterip before-start --tcp=82:8082 >/dev/null
syncer syncer-a
a=$last
eventually "first replica leads" 30 grep -q '"became leader"' "$work/syncer-a.log"
eventually "Lease vcluster-demo/vcluster-demo-controller on the host names the first replica" 30 holder_is syncer-a
syncer syncer-b
sleep 5
if grep -q '"became leader"' "$work/syncer-b.log"; then fail "second replica stays passive"; else pass "second replica stays passive"; fi
eventually "host namespace created" 30 kh get namespace "$NS"
grep -q 'services,configmaps,secrets,serviceaccounts' "$work/syncer-a.log" && pass "vcluster.yaml enable set" || fail "vcluster.yaml enable set"

eventually "initial list key reconciles after all stores are ready" 30 kh -n "$NS" get service before-start-x-default-x-demo
# Each path must finish a list and open a watch, on both leaders.
watchers_started() {
  local log=$1 path kind
  for kind in services configmaps secrets serviceaccounts pods; do
    path=/api/v1/$kind
    grep -F '"msg":"listed"' "$log" | grep -Fq "\"path\":\"$path\"" || return 1
    grep -F '"msg":"watching"' "$log" | grep -Fq "\"path\":\"$path\"" || return 1
    [ "$kind" = pods ] && continue
    path=/api/v1/namespaces/$NS/$kind
    grep -F '"msg":"listed"' "$log" | grep -Fq "\"path\":\"$path\"" || return 1
    grep -F '"msg":"watching"' "$log" | grep -Fq "\"path\":\"$path\"" || return 1
  done
}
eventually "all nine lists return and watches open" 30 watchers_started "$work/syncer-a.log"

echo "== virtual to host"
kv -n default create service clusterip test-svc --tcp=80:8080 >/dev/null
eventually "service synced as test-svc-x-default-x-demo" 30 kh -n "$NS" get service test-svc-x-default-x-demo
label() { kh -n "$NS" get "$1" "$2" -o "jsonpath={.metadata.labels.vcluster\.loft\.sh/managed-by}"; }
ann() { kh -n "$NS" get "$1" "$2" -o "jsonpath={.metadata.annotations.vcluster\.loft\.sh/$3}"; }
[ "$(label service test-svc-x-default-x-demo)" = demo ] && pass "service managed-by label" || fail "service managed-by label"
[ "$(ann service test-svc-x-default-x-demo object-name)" = test-svc ] && pass "service object-name annotation" || fail "service object-name annotation"
[ "$(ann service test-svc-x-default-x-demo object-namespace)" = default ] && pass "service object-namespace annotation" || fail "service object-namespace annotation"
[ "$(kh -n "$NS" get service test-svc-x-default-x-demo -o 'jsonpath={.spec.ports[0].port}')" = 80 ] && pass "service port" || fail "service port"
same_cluster_ip() {
  local h v
  h=$(kh -n "$NS" get service test-svc-x-default-x-demo -o 'jsonpath={.spec.clusterIP}') || return 1
  v=$(kv -n default get service test-svc -o 'jsonpath={.spec.clusterIP}') || return 1
  [ -n "$h" ] && [ "$h" = "$v" ]
}
eventually "virtual service gets the host cluster IP" 30 same_cluster_ip

kv -n default create configmap test-cm --from-literal=k=v >/dev/null
kv -n default create secret generic test-secret --from-literal=password=s3cret >/dev/null
sleep 3
if kh -n "$NS" get configmap test-cm-x-default-x-demo >/dev/null 2>&1; then
  fail "unreferenced configmap stays virtual (sync.toHost.configMaps.all=false)"
else
  pass "unreferenced configmap stays virtual (sync.toHost.configMaps.all=false)"
fi
kv -n default apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
  namespace: default
spec:
  containers:
  - name: c
    image: busybox
    envFrom:
    - configMapRef:
        name: test-cm
    - secretRef:
        name: test-secret
EOF
eventually "referenced configmap synced as test-cm-x-default-x-demo" 30 kh -n "$NS" get configmap test-cm-x-default-x-demo
eventually "referenced secret synced as test-secret-x-default-x-demo" 30 kh -n "$NS" get secret test-secret-x-default-x-demo
[ "$(kh -n "$NS" get configmap test-cm-x-default-x-demo -o 'jsonpath={.data.k}')" = v ] && pass "configmap data" || fail "configmap data"
[ "$(kh -n "$NS" get secret test-secret-x-default-x-demo -o 'jsonpath={.data.password}' | base64 -d)" = s3cret ] && pass "secret data" || fail "secret data"
kv -n default create serviceaccount test-sa >/dev/null
eventually "service account synced as test-sa-x-default-x-demo" 30 kh -n "$NS" get serviceaccount test-sa-x-default-x-demo
[ "$(label serviceaccount test-sa-x-default-x-demo)" = demo ] && pass "service account managed-by label" || fail "service account managed-by label"
skip "pod appears on the host and its status flows back (needs the pod translator, #9)"

echo "== deletes"
kv -n default delete service test-svc --wait=false >/dev/null
eventually "virtual delete removes the host service" 30 gone kh -n "$NS" get service test-svc-x-default-x-demo
kh -n "$NS" delete configmap test-cm-x-default-x-demo --wait=false >/dev/null
eventually "host delete removes the virtual configmap" 30 gone kv -n default get configmap test-cm

echo "== failover"
kill -TERM "$a"
eventually "standby takes the Lease" 40 holder_is syncer-b
kv -n default create service clusterip after-failover --tcp=81:8081 >/dev/null
eventually "new leader starts all nine watches" 30 watchers_started "$work/syncer-b.log"
eventually "new leader syncs" 30 kh -n "$NS" get service after-failover-x-default-x-demo

if [ $fails -gt 0 ]; then
  for f in syncer-a syncer-b; do echo "--- $f.log (tail)"; tail -30 "$work/$f.log"; done
  echo "$fails FAILED"; exit 1
fi
echo "ALL PASS"
