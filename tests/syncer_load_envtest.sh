#!/usr/bin/env bash
# The classic-mode syncer (host/syncer.bend) under the load of the e2e test
# "[sig-storage] EmptyDir wrapper volumes should not cause race condition
# when used for configmaps [Serial]" (test/e2e/storage/empty_dir_wrapper.go:
# 50 ConfigMaps, then a ReplicationController of 5 pods that each mount all
# 50 ConfigMaps, deleted again). Here: 50 ConfigMaps and 25 pods that each
# mount all of them, in one virtual namespace, then the pods are deleted.
#
# Two etcd + kube-apiserver pairs as in tests/syncer_envtest.sh, the
# virtual one with kube-scheduler (the virtual scheduler), and the
# syncer with vcluster's conformance profile (test/conformanceValues.yaml:
# real nodes, the virtual scheduler). No kubelet runs: the script plays
# the host kubelet. It sets each host pod Running, posts a FailedMount
# event about it (as the kubelet does while a wrapped volume waits), and
# removes a terminating host pod (force delete).
#
# It measures and checks:
# - the time until every host pod exists, and until every virtual pod runs;
# - virtual delete -> host delete: the time from deleting the virtual pods
#   until every host pod is terminating or gone (must be <= 10 s). The
#   delete starts right after a resync tick, so that no tick runs within
#   it: a tick's four LISTs hold the syncer's one loop for seconds;
# - host delete -> virtual delete: the time from removing the host pods
#   until every virtual pod is gone;
# - the syncer's 30 s resync tick: the longest gap between two resyncs
#   during the load (must be <= 75 s: at most one tick dropped), and the
#   "resync dropped" warnings;
# - the syncer's per-minute "syncer load" lines are printed for diagnosis.
#
# Needs: bend, clang (bend's native build), openssl, curl, python3, Linux.
# Usage: tests/syncer_load_envtest.sh   (K8S, ETCD override the versions;
# ENVTEST_CACHE the download directory; KEEP=1 keeps the work directory;
# ENVTEST_TIMEOUT the bound of the whole run in seconds, default 1500;
# PODS and CMS the load, default 25 and 50)
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib/ports.sh

if [ -z "${SYNCER_ENVTEST_BOUNDED:-}" ]; then
  SYNCER_ENVTEST_BOUNDED=1 timeout -k 30 "${ENVTEST_TIMEOUT:-1500}" "tests/$(basename "$0")" "$@"
  rc=$?
  [ $rc -eq 124 ] && echo "FAIL syncer load envtest timed out after ${ENVTEST_TIMEOUT:-1500}s"
  exit $rc
fi

K8S=${K8S:-v1.36.6}
ETCD=${ETCD:-v3.5.21}
PODS=${PODS:-25}
CMS=${CMS:-50}
case $(uname -m) in
  x86_64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) echo "unsupported architecture $(uname -m)"; exit 1 ;;
esac
cache=${ENVTEST_CACHE:-$HOME/.cache/vk8s-envtest/$K8S-$ETCD-$arch}
work=$(mktemp -d)
pids=()
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
# diag: the syncer's meter lines, resync lines and log tail.
diag() {
  [ -s "$work/syncer.log" ] || return 0
  echo "--- syncer load lines"; grep -F '"msg":"syncer load"' "$work/syncer.log" | tail -40
  echo "--- resync lines"; grep -F '"msg":"resync' "$work/syncer.log" | tail -20 | cut -c1-300
  echo "--- slow reconciles: $(grep -cF '"msg":"slow reconcile"' "$work/syncer.log")"
  echo "--- syncer.log (tail)"; tail -40 "$work/syncer.log" | cut -c1-400
}
trap cleanup EXIT
trap 'echo "FAIL interrupted"; diag; exit 124' TERM INT

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
eventually() {
  local name=$1 secs=$2; shift 2
  local i
  for ((i = 0; i < secs * 2; i++)); do
    if "$@" >/dev/null 2>&1; then pass "$name"; return 0; fi
    sleep 0.5
  done
  fail "$name"; return 1
}
now() { date +%s.%N; }
# resyncs: the resync ticks the syncer has run so far.
resyncs() { grep -cF '"msg":"resync"' "$work/syncer.log"; }
# next_resync SECONDS: a resync tick runs within SECONDS from now.
next_resync() {
  local n end=$((SECONDS + $1))
  n=$(resyncs)
  while [ "$(resyncs)" -le "$n" ]; do
    [ $SECONDS -lt $end ] || return 1
    sleep 0.2
  done
}
since() { python3 -c 'import sys; print("%.1f" % (float(sys.argv[2]) - float(sys.argv[1])))' "$1" "$(now)"; }

echo "== binaries ($K8S, etcd $ETCD, $arch)"
mkdir -p "$cache"
get() {
  [ -s "$cache/$2" ] && return 0
  curl --proto '=https' --tlsv1.2 -fsSL --retry 5 --retry-all-errors --retry-delay 5 -o "$cache/$2.part" "$1" && mv "$cache/$2.part" "$cache/$2"
}
get "https://dl.k8s.io/release/$K8S/bin/linux/$arch/kube-apiserver" kube-apiserver || { echo "FAIL download kube-apiserver"; exit 1; }
get "https://dl.k8s.io/release/$K8S/bin/linux/$arch/kubectl" kubectl || { echo "FAIL download kubectl"; exit 1; }
get "https://dl.k8s.io/release/$K8S/bin/linux/$arch/kube-scheduler" kube-scheduler || { echo "FAIL download kube-scheduler"; exit 1; }
if [ ! -s "$cache/etcd" ]; then
  get "https://github.com/etcd-io/etcd/releases/download/$ETCD/etcd-$ETCD-linux-$arch.tar.gz" etcd.tgz \
    || { echo "FAIL download etcd"; exit 1; }
  tar -xzf "$cache/etcd.tgz" -C "$cache" --strip-components=1 "etcd-$ETCD-linux-$arch/etcd"
fi
chmod +x "$cache/kube-apiserver" "$cache/kubectl" "$cache/kube-scheduler" "$cache/etcd"
pass "binaries"

echo "== build (bend host/init.bend)"
if ! bend host/init.bend -o "$work/vk8s-guest" >"$work/build.log" 2>&1; then
  cat "$work/build.log"; echo "FAIL build host/init.bend"; exit 1
fi
pass "build"

echo "== certificates"
nodeip=$(ip -4 -o route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p')
[ -n "$nodeip" ] || nodeip=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -v '^127\.' | grep -m1 '^[0-9.]*$')
[ -n "$nodeip" ] || nodeip=127.0.0.1
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
  openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -keyout kserve.key -out kserve.csr -subj "/CN=vk8s-fake-kubelet" 2>/dev/null
  printf 'subjectAltName=IP:127.0.0.1,IP:%s\nextendedKeyUsage=serverAuth\n' "$nodeip" > kserve.ext
  openssl x509 -req -in kserve.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out kserve.crt -days 2 -extfile kserve.ext 2>/dev/null
  openssl genrsa -out sa.key 2048 2>/dev/null
  openssl rsa -in sa.key -pubout -out sa.pub 2>/dev/null
) && [ -s "$pki/admin.crt" ] && [ -s "$pki/kserve.crt" ] && [ -s "$pki/sa.pub" ] || { echo "FAIL certificates"; exit 1; }
pass "certificates"

# cluster NAME ETCD_PORT PEER_PORT API_PORT SERVICE_CIDR
# As in tests/syncer_envtest.sh: the ports must be free, and etcd must
# listen before its API server starts.
cluster() {
  local name=$1 ep=$2 pp=$3 port=$4 cidr=$5 d=$work/$1 epid
  mkdir -p "$d"
  if ! ports_free "$ep" "$pp" "$port"; then
    echo "FAIL $name: one of the ports $ep $pp $port is taken"
    ss -H -tanp 2>/dev/null | grep -E ":($ep|$pp|$port) " | head -20
    exit 1
  fi
  "$cache/etcd" --name "$name" --data-dir "$d/etcd" \
    --listen-client-urls "http://127.0.0.1:$ep" --advertise-client-urls "http://127.0.0.1:$ep" \
    --listen-peer-urls "http://127.0.0.1:$pp" --initial-advertise-peer-urls "http://127.0.0.1:$pp" \
    --initial-cluster "$name=http://127.0.0.1:$pp" > "$d/etcd.log" 2>&1 &
  epid=$!
  pids+=("$epid")
  if ! port_wait "$ep" 60 "$epid"; then
    echo "FAIL $name: etcd listens on 127.0.0.1:$ep"
    echo "--- $d/etcd.log (tail)"; tail -40 "$d/etcd.log"
    exit 1
  fi
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
# Ports below 32768: the ephemeral range (32768-60999) can already hold
# a client socket on the port, and etcd or the apiserver then fails to bind.
CIDR=10.96.0.0/16
cluster virtual 22379 22380 26443 "$CIDR"
cluster host 23379 23380 27443 "$CIDR"
V=$work/virtual/kubeconfig
H=$work/host/kubeconfig
kv() { "$cache/kubectl" --request-timeout=20s --kubeconfig "$V" "$@"; }
kh() { "$cache/kubectl" --request-timeout=20s --kubeconfig "$H" "$@"; }
eventually "virtual API ready" 60 kv get --raw /readyz || { tail -20 "$work/virtual/apiserver.log"; exit 1; }
eventually "host API ready" 60 kh get --raw /readyz || { tail -20 "$work/host/apiserver.log"; exit 1; }
eventually "virtual default namespace" 30 kv get namespace default
eventually "virtual priority classes bootstrapped" 30 kv get priorityclass system-node-critical
kv -n kube-system create service clusterip kube-dns --tcp=53:53 >/dev/null

echo "== syncer (conformance profile)"
NS=vcluster-load
VC=load
cat > "$work/conformance.yaml" <<'EOF2'
controlPlane:
  advanced:
    virtualScheduler:
      enabled: true
networking:
  advanced:
    proxyKubelets:
      byHostname: false
      byIP: false
sync:
  fromHost:
    csiDrivers:
      enabled: false
    csiStorageCapacities:
      enabled: false
    nodes:
      enabled: true
      selector:
        all: true
  toHost:
    persistentVolumes:
      enabled: true
    priorityClasses:
      enabled: true
    storageClasses:
      enabled: true
EOF2
kh apply -f - >/dev/null <<EOF2
apiVersion: v1
kind: Node
metadata:
  name: hnode
  labels:
    kubernetes.io/hostname: hnode
    kubernetes.io/os: linux
EOF2
kh patch node hnode --subresource=status --type=merge -p "{\"status\":{\"capacity\":{\"cpu\":\"64\",\"memory\":\"64Gi\",\"pods\":\"250\"},\"allocatable\":{\"cpu\":\"64\",\"memory\":\"64Gi\",\"pods\":\"250\"},\"conditions\":[{\"type\":\"Ready\",\"status\":\"True\",\"reason\":\"KubeletReady\",\"message\":\"ready\",\"lastHeartbeatTime\":\"2026-01-01T00:00:00Z\",\"lastTransitionTime\":\"2026-01-01T00:00:00Z\"}],\"addresses\":[{\"type\":\"InternalIP\",\"address\":\"$nodeip\"}],\"daemonEndpoints\":{\"kubeletEndpoint\":{\"Port\":10250}}}}" >/dev/null
# No node lifecycle controller lifts the not-ready taint: lift it.
kh taint node hnode node.kubernetes.io/not-ready:NoSchedule- >/dev/null 2>&1 || true
HOSTNAME=syncer-load "$work/vk8s-guest" syncer --kubeconfig "$V" --host-kubeconfig "$H" --host-namespace "$NS" \
  --name "$VC" --service-cidr "$CIDR" --config "$work/conformance.yaml" \
  --kubelet-ip "$nodeip" --kubelet-cert "$pki/kserve.crt" --kubelet-key "$pki/kserve.key" \
  --kubelet-client-ca "$pki/ca.crt" --kubelet-dir "$work" > "$work/syncer.log" 2>&1 &
pids+=($!)
eventually "syncer leads" 30 grep -q '"became leader"' "$work/syncer.log"
eventually "host namespace created" 30 kh get namespace "$NS"
# The vcluster's own host Service: pods wait for it (findKubernetesIP).
kh apply -f - >/dev/null <<EOF2
apiVersion: v1
kind: Service
metadata:
  name: $VC
  namespace: $NS
  labels:
    app: vcluster
    release: $VC
spec:
  type: ClusterIP
  ports:
  - name: https
    port: 443
    targetPort: 26443
    protocol: TCP
EOF2
eventually "host node hnode appears in the virtual cluster" 60 kv get node hnode
"$cache/kube-scheduler" --kubeconfig "$V" --authentication-kubeconfig "$V" --authorization-kubeconfig "$V" \
  --bind-address 127.0.0.1 --secure-port 10279 --cert-dir "$work/scheduler-certs" --leader-elect=false > "$work/scheduler.log" 2>&1 &
pids+=($!)

echo "== load: $CMS ConfigMaps, $PODS pods mounting all of them"
kv create namespace load >/dev/null
{
  for ((i = 0; i < CMS; i++)); do
    printf -- '---\napiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: racey-configmap-%d\n  namespace: load\ndata:\n  data-1: value-1\n' "$i"
  done
} > "$work/cms.yaml"
kv apply -f "$work/cms.yaml" >/dev/null || fail "create the ConfigMaps"
# Pods as the e2e test's ReplicationController makes them: one container,
# every ConfigMap as a volume, each mounted under /etc/config-<i>.
{
  for ((p = 0; p < PODS; p++)); do
    printf -- '---\napiVersion: v1\nkind: Pod\nmetadata:\n  name: wrapped-volume-race-%d\n  namespace: load\n  labels:\n    name: wrapped-volume-race\nspec:\n  terminationGracePeriodSeconds: 30\n  containers:\n  - name: test-container\n    image: registry.k8s.io/e2e-test-images/busybox:1.37.0-1\n    command: ["sleep", "10000"]\n    resources:\n      requests:\n        cpu: 10m\n    volumeMounts:\n' "$p"
    for ((i = 0; i < CMS; i++)); do
      printf '    - name: racey-configmap-%d\n      mountPath: /etc/config-%d\n' "$i" "$i"
    done
    printf '  volumes:\n'
    for ((i = 0; i < CMS; i++)); do
      printf '  - name: racey-configmap-%d\n    configMap:\n      name: racey-configmap-%d\n' "$i" "$i"
    done
  done
} > "$work/pods.yaml"
t_load=$(now)
date -u +%Y-%m-%dT%H:%M:%S > "$work/load-start"
kv apply -f "$work/pods.yaml" >/dev/null || fail "create the pods"

# host pods: the managed host pods' names (and deletion timestamps).
hpods() { kh -n "$NS" get pods -l "vcluster.loft.sh/managed-by=$VC" -o 'jsonpath={range .items[*]}{.metadata.name}{" "}{.metadata.deletionTimestamp}{"\n"}{end}'; }
count_host() { [ "$(hpods | grep -c .)" -ge "$PODS" ]; }
hcms() { [ "$(kh -n "$NS" get configmaps -l "vcluster.loft.sh/managed-by=$VC" -o name | grep -c .)" -ge "$CMS" ]; }
if eventually "every pod reaches the host" 600 count_host; then
  echo "MEASURE create -> all host pods: $(since "$t_load") s"
fi
eventually "every ConfigMap reaches the host" 120 hcms && echo "MEASURE create -> all host ConfigMaps: $(since "$t_load") s"

# The kubelet's part: each host pod runs, and the kubelet reports a
# FailedMount event about it first (wrapped volumes wait for their
# ConfigMaps), then again with count 2.
# A bare wait would wait for the control planes and the syncer too: wait
# only for these kubectl calls.
jobs_=()
for h in $(hpods | awk '{print $1}'); do
  kh -n "$NS" patch pod "$h" --subresource=status --type=merge \
    -p '{"status":{"phase":"Running","podIP":"10.1.3.1","podIPs":[{"ip":"10.1.3.1"}],"conditions":[{"type":"Ready","status":"True"}]}}' >/dev/null &
  jobs_+=($!)
  kh -n "$NS" apply -f - >/dev/null <<EOF2 &
apiVersion: v1
kind: Event
metadata:
  name: $h.mount
  namespace: $NS
involvedObject:
  apiVersion: v1
  kind: Pod
  name: $h
  namespace: $NS
reason: FailedMount
message: 'MountVolume.SetUp failed for volume "racey-configmap-0" : configmap "racey-configmap-0" not found'
type: Warning
count: 1
EOF2
  jobs_+=($!)
done
wait "${jobs_[@]}"
jobs_=()
for h in $(hpods | awk '{print $1}'); do
  kh -n "$NS" patch event "$h.mount" --type=merge -p '{"count":2}' >/dev/null &
  jobs_+=($!)
done
wait "${jobs_[@]}"
running() { [ "$(kv -n load get pods -o 'jsonpath={range .items[*]}{.status.phase}{"\n"}{end}' | grep -c '^Running$')" -ge "$PODS" ]; }
eventually "every virtual pod runs" 600 running && echo "MEASURE create -> all virtual pods Running: $(since "$t_load") s"

echo "== delete"
# The syncer's loop runs a resync tick every 30 s: four LISTs (the pods
# of both clusters, the host ConfigMaps and Secrets) that it parses before
# the next reconcile. Where the tick falls in this test followed from how
# long the steps above took. In three weeks of CI every run that broke
# the 10 s below (6 of 6: 10.9-13.7 s) had a tick inside the delete, and
# no passing run had one (60 of 60 read: 4.0-8.8 s, median 6.7 s). So the
# delete starts right after a tick: the next one is about 30 s away, and
# the 10 s bound measures the delete path alone, in every run.
if next_resync 80; then
  echo "INFO a resync tick ran: the delete starts now"
else
  fail "a resync tick runs within 80 s before the delete"
fi
n_del=$(resyncs)
t_del=$(now)
kv -n load delete pods --all --wait=false >/dev/null
# virtual delete -> host delete: every host pod terminating or gone.
host_deleted() { [ "$(hpods | awk 'NF == 1' | grep -c .)" -eq 0 ]; }
dt=""
for ((i = 0; i < 1200; i++)); do
  if host_deleted; then dt=$(since "$t_del"); break; fi
  sleep 0.5
done
if [ -n "$dt" ]; then
  echo "MEASURE virtual delete -> all host pods deleted: $dt s"
  echo "MEASURE resync ticks during the delete: $(($(resyncs) - n_del))"
  python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) <= 10 else 1)' "$dt" \
    && pass "virtual delete reaches every host pod within 10 s ($dt s)" \
    || fail "virtual delete reaches every host pod within 10 s ($dt s)"
else
  fail "virtual delete reaches every host pod within 10 s (not within 600 s)"
fi
# The kubelet's part: the terminating host pods go.
t_force=$(now)
kh -n "$NS" delete pods -l "vcluster.loft.sh/managed-by=$VC" --grace-period=0 --force >/dev/null 2>&1
vgone() { [ "$(kv -n load get pods -o name | grep -c .)" -eq 0 ]; }
dv=""
for ((i = 0; i < 1200; i++)); do
  if vgone; then dv=$(since "$t_force"); break; fi
  sleep 0.5
done
if [ -n "$dv" ]; then
  echo "MEASURE host delete -> all virtual pods gone: $dv s"
  pass "host delete releases every virtual pod ($dv s)"
else
  fail "host delete releases every virtual pod (not within 600 s)"
fi
kv -n load delete configmaps --all --wait=false >/dev/null
nocms() { [ "$(kh -n "$NS" get configmaps -l "vcluster.loft.sh/managed-by=$VC" -o name | grep -c .)" -eq 0 ]; }
t_cm=$(now)
eventually "virtual ConfigMap deletes reach the host" 300 nocms && echo "MEASURE ConfigMap delete -> host ConfigMaps gone: $(since "$t_cm") s"
# One more tick after the load, so the last gap is measured too. Without
# one in 80 s the gap check below fails on the gap to the load's end.
next_resync 80 || echo "INFO no resync tick within 80 s after the load"
date -u +%Y-%m-%dT%H:%M:%S > "$work/load-end"
echo "MEASURE whole load: $(since "$t_load") s"

echo "== resync ticks"
# The longest gap between resyncs (or the load's ends) during the load.
gap=$(python3 - "$work/syncer.log" "$(cat "$work/load-start")" "$(cat "$work/load-end")" <<'PY'
import json, sys, datetime
def t(s):
    return datetime.datetime.fromisoformat(s.rstrip("Z")[:19])
start, end = t(sys.argv[2]), t(sys.argv[3])
ticks, dropped = [], 0
for line in open(sys.argv[1], errors="replace"):
    try:
        j = json.loads(line)
    except Exception:
        continue
    ts = j.get("ts")
    if not ts:
        continue
    if j.get("msg") == "resync" and start <= t(ts) <= end:
        ticks.append(t(ts))
    if j.get("msg") == "resync dropped" and start <= t(ts) <= end:
        dropped += 1
points = [start] + ticks + [end]
gaps = [(b - a).total_seconds() for a, b in zip(points, points[1:])]
print("%d %d %.0f" % (len(ticks), dropped, max(gaps)))
PY
)
read -r nticks ndropped maxgap <<<"${gap:-0 0 9999}"
echo "MEASURE resyncs during the load: $nticks, dropped: $ndropped, longest gap: $maxgap s"
# 75 s is not a speed limit of the runner: the tick period is 30 s and a
# tick over 20 s late is dropped, so one dropped tick gives a gap of 60 s
# (plus the loop's lateness), two give 90 s. Observed: 29-36 s in 66 runs.
[ "${maxgap%.*}" -le 75 ] && pass "resync never late by more than one tick (longest gap $maxgap s)" \
  || fail "resync never late by more than one tick (longest gap $maxgap s)"

echo "MEASURE slow reconciles: $(grep -cF '"msg":"slow reconcile"' "$work/syncer.log")"
diag

if [ $fails -gt 0 ]; then
  echo "$fails FAILED"; exit 1
fi
echo "ALL PASS"
