#!/usr/bin/env bash
# agent-substrate (github.com/agent-substrate/substrate) on a vk8s cluster,
# on a Linux KVM host: its quickstart (docs/get-started/quickstart.md) with
# a vk8s cluster in place of kind.
#   1. a local registry (registry:3 on 127.0.0.1:5001, as
#      hack/create-kind-cluster.sh runs it)
#   2. vk8s create -f docs/examples/substrate.vcluster.yaml (one VM node,
#      no idle sleep), then: the certificates.k8s.io/v1beta1 kinds are
#      served, every node's containerd reads localhost:5001 from the
#      registry (a hosts.toml mirror to 10.0.2.2:5001, the host's loopback
#      as the VM sees it) and its / is rshared (kind's entrypoint does
#      this; vk8s's VM nodes do not yet), a default StorageClass (local-path-provisioner;
#      kind ships one), and kube-public/local-registry-hosting
#   3. ATE_INSTALL_KIND=true semantics, adapted: ate-setup keeps pushing to
#      localhost:5001 and reads KUBECTL_CONTEXT=vk8s_NAME; atelet's
#      --localhost-registry-replacement (kind: kind-registry:5000, the
#      registry on kind's Docker network) becomes 10.0.2.2:5001, which pods
#      reach through their node's NAT
#   4. go run ./cmd/ate-setup deploy ate-system (gvisor class only: VM nodes
#      have no nested KVM), deploy demo counter, kubectl ate create actor,
#      kubectl ate proxy actor, and two POSTs: the memory count must go up
#      by one
# Prints each step's time (also to $GITHUB_STEP_SUMMARY when set). On a
# failure it prints the cluster's state, substrate's logs and the VMs'
# consoles, deletes the cluster and exits non-zero.
#
# usage: scripts/substrate-e2e.sh SUBSTRATE_DIR
# VK8S_BIN (default out/vk8s); SUBSTRATE_NAME (default substrate);
# SUBSTRATE_CPUS (default 4), SUBSTRATE_MEMORY (MiB, default 10240).
# Needs /dev/kvm, docker, go, kubectl, curl.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
repo=$PWD
sub=${1:?usage: scripts/substrate-e2e.sh SUBSTRATE_DIR}
sub=$(cd "$sub" && pwd) || exit 2
v=$repo/${VK8S_BIN:-out/vk8s}
case ${VK8S_BIN:-} in /*) v=$VK8S_BIN ;; esac
name=${SUBSTRATE_NAME:-substrate}
cpus=${SUBSTRATE_CPUS:-4}
mem=${SUBSTRATE_MEMORY:-10240}
ctx=vk8s_$name
reg_name=kind-registry
reg_port=5001
# the host's loopback as a VM node (and its pods, through the node's NAT)
# sees it (bend-vmm README: "The host itself stays reachable as 10.0.2.2")
reg_from_vm=10.0.2.2:$reg_port
dir=$HOME/.vk8s/clusters/$name
out=$repo/out/substrate
mkdir -p "$out"
rows=""
proxy_pid=""
now() { date +%s; }
row() { rows="$rows| $1 | $2 |"$'\n'; echo "substrate-e2e: $1: $2 s"; }
k() { kubectl --context "$ctx" "$@"; }

summary() {
  local head="### agent-substrate on vk8s ($1)"
  local table="| step | seconds |"$'\n'"|---|---|"$'\n'"$rows"
  echo "$head"; printf '%s' "$table"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then printf '%s\n\n%s\n' "$head" "$table" >> "$GITHUB_STEP_SUMMARY"; fi
}

dump() {
  echo "== vk8s list"; "$v" list 2>&1 || true
  echo "== nodes"; k get nodes -o wide 2>&1 || true
  echo "== pods"; k get pods -A -o wide 2>&1 || true
  echo "== pvc"; k get pvc -A 2>&1 || true
  echo "== events (last 80)"; k get events -A --sort-by=.lastTimestamp 2>&1 | tail -n 80 || true
  echo "== workerpools"; k get workerpools -A -o wide 2>&1 || true
  echo "== podcertificaterequests"; k get podcertificaterequests -A 2>&1 | tail -n 20 || true
  echo "== registry catalog"; curl -fsS "http://127.0.0.1:$reg_port/v2/_catalog" 2>&1 || true
  echo
  # every pod that is not Running or Succeeded: describe it
  k get pods -A --no-headers 2>/dev/null | awk '$4 != "Running" && $4 != "Completed" {print $1, $2}' |
    while read -r ns p; do
      echo "== describe $ns/$p"; k -n "$ns" describe pod "$p" 2>&1 | tail -n 40
    done
  for ns in ate-system ate-demo-counter vk8s-substrate-e2e; do
    for p in $(k -n "$ns" get pods -o name 2>/dev/null); do
      echo "== logs $ns/$p (last 150 lines)"
      k -n "$ns" logs "$p" --all-containers --tail=150 2>&1 || true
    done
  done
  for f in "$dir/console.log" "$dir"/nodes/*/console.log "$dir/vmm.log" "$HOME/.vk8s/cache/console.log"; do
    [ -f "$f" ] || continue
    echo "== $f (boot steps and failures)"
    grep -E 'vk8s: |vk8s-init: (start|spawn|stop|FAILED|timed out)|[Pp]anic' "$f" | head -n 80 || true
    echo "== $f (last 60 lines)"; tail -n 60 "$f"
  done
  for f in "$dir"/share/logs/*.log; do
    [ -f "$f" ] || continue
    echo "== $f (errors, first 40)"
    grep -E '^[EF][0-9]{4} |[Pp]anic|level=(error|fatal)' "$f" | head -n 40 || true
    echo "== $f (last 20 lines)"; tail -n 20 "$f"
  done
  echo "== host"; free -m; df -h / "$HOME"; docker ps -a
}
cleanup() {
  [ -n "$proxy_pid" ] && kill "$proxy_pid" 2>/dev/null
  "$v" delete "$name" >/dev/null 2>&1 || true
  "$v" cache stop >/dev/null 2>&1 || true
  docker rm -f "$reg_name" >/dev/null 2>&1 || true
}
fail() {
  echo "FAIL substrate-e2e: $*"
  dump
  summary "FAIL: $*"
  cleanup
  exit 1
}
# step LABEL CMD...: runs CMD with its output in the log (and in
# out/substrate/LOGNAME.log), records its time, fails on error
step() {
  local label=$1; shift
  local t0; t0=$(now)
  local log; log=$out/$(echo "$label" | tr -c 'a-zA-Z0-9\n' '-' | tr -s '-').log
  echo "substrate-e2e: == $label"
  "$@" 2>&1 | tee "$log"
  [ "${PIPESTATUS[0]}" = 0 ] || fail "$label"
  row "$label" $(( $(now) - t0 ))
}
# until_ok SECONDS CMD...: retries CMD every 3 s until it succeeds
until_ok() {
  local end=$(( $(date +%s) + $1 )); shift
  until "$@" >/dev/null 2>&1; do
    [ "$(date +%s)" -lt "$end" ] || return 1
    sleep 3
  done
}

# 1. the local registry, as create-kind-cluster.sh runs it
registry() {
  docker rm -f "$reg_name" >/dev/null 2>&1 || true
  docker run -d --restart=always --name "$reg_name" -p "127.0.0.1:$reg_port:5000" registry:3 &&
    until_ok 60 curl -fsS "http://127.0.0.1:$reg_port/v2/"
}
step "local registry on 127.0.0.1:$reg_port" registry

# 2. the cluster
"$v" delete "$name" >/dev/null 2>&1 || true
step "vk8s create -f docs/examples/substrate.vcluster.yaml ($cpus vCPUs, $mem MiB)" \
  "$v" create "$name" -f "$repo/docs/examples/substrate.vcluster.yaml" --nodes 0 \
  --cpus "$cpus" --memory "$mem" --idle-sleep 0 --connect=false
step "vk8s connect (context $ctx)" "$v" connect "$name"
k config use-context "$ctx" >/dev/null
nodes_ready() {
  until_ok 600 k get sa default || return 1
  k wait --for=condition=Ready node --all --timeout=600s
}
step "nodes Ready" nodes_ready
step "vk8s describe --config-only" "$v" describe "$name" --config-only

# the feature gates and the API group of the vcluster.yaml are in effect
api_check() {
  # (into a variable first: grep -q under pipefail can fail on SIGPIPE)
  local r; r=$(k api-resources --api-group=certificates.k8s.io -o wide) || return 1
  echo "$r"
  grep -q '^clustertrustbundles .*certificates.k8s.io/v1beta1' <<<"$r" &&
    grep -q '^podcertificaterequests .*certificates.k8s.io/v1beta1' <<<"$r" &&
    k get --raw /apis/certificates.k8s.io/v1beta1 >/dev/null
}
step "certificates.k8s.io/v1beta1 serves clustertrustbundles and podcertificaterequests" api_check

# every node's containerd reads localhost:5001 from the registry, as kind's
# hosts.toml does; vcluster.yaml has no key for registry mirrors, so a
# privileged DaemonSet writes the file (kind: docker exec on each node).
# It also makes the node's / rshared, as kind's node entrypoint does
# (`mount --make-rshared /`): atelet mounts /var/lib/ate with
# mountPropagation HostToContainer, which runc refuses on a private /
# ("is mounted on "/" but it is not a shared or slave mount"). vk8s's
# container nodes do this at boot (Container.system); its VM nodes do not
# yet (Plan.system).
mirror() {
  k apply -f - <<EOF || return 1
apiVersion: v1
kind: Namespace
metadata:
  name: vk8s-substrate-e2e
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: registry-mirror
  namespace: vk8s-substrate-e2e
spec:
  selector:
    matchLabels:
      app: registry-mirror
  template:
    metadata:
      labels:
        app: registry-mirror
    spec:
      hostPID: true
      tolerations:
      - operator: Exists
      containers:
      - name: write
        image: docker.io/library/busybox:1.36
        securityContext:
          privileged: true
        command:
        - sh
        - -c
        - |
          set -e
          nsenter -t 1 -m -- mount --make-rshared /
          grep ' / / ' /proc/1/mountinfo
          grep ' / / ' /proc/1/mountinfo | grep -q shared:
          mkdir -p /certs.d/localhost:$reg_port
          printf '%s\n' 'server = "http://localhost:$reg_port"' '' '[host."http://$reg_from_vm"]' '  capabilities = ["pull", "resolve"]' > /certs.d/localhost:$reg_port/hosts.toml
          cat /certs.d/localhost:$reg_port/hosts.toml
          exec sleep 2147483647
        volumeMounts:
        - name: certs
          mountPath: /certs.d
      volumes:
      - name: certs
        hostPath:
          path: /etc/containerd/certs.d
          type: DirectoryOrCreate
EOF
  k -n vk8s-substrate-e2e rollout status ds/registry-mirror --timeout=300s &&
    k -n vk8s-substrate-e2e logs ds/registry-mirror
}
step "every node: / rshared, hosts.toml localhost:$reg_port -> http://$reg_from_vm" mirror

# the mirror works: an image pushed to the host's localhost:5001 runs
pull_check() {
  docker pull -q docker.io/library/busybox:1.36 &&
    docker tag docker.io/library/busybox:1.36 "localhost:$reg_port/vk8s-e2e/busybox:1.36" &&
    docker push -q "localhost:$reg_port/vk8s-e2e/busybox:1.36" &&
    k -n vk8s-substrate-e2e run pull-check --image="localhost:$reg_port/vk8s-e2e/busybox:1.36" \
      --restart=Never -- echo pulled-from-local-registry &&
    until_ok 300 sh -c "kubectl --context $ctx -n vk8s-substrate-e2e get pod pull-check -o jsonpath='{.status.phase}' | grep Succeeded" &&
    k -n vk8s-substrate-e2e logs pull-check | grep pulled-from-local-registry &&
    k -n vk8s-substrate-e2e delete pod pull-check --wait=false
}
step "a pod runs an image from localhost:$reg_port" pull_check

# a default StorageClass (kind ships local-path-provisioner as "standard");
# substrate's rustfs PVC and postgres volumeClaimTemplates use the default
storage() {
  k apply -f "https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.31/deploy/local-path-storage.yaml" &&
    k patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' &&
    k -n local-path-storage rollout status deploy/local-path-provisioner --timeout=300s &&
    k get storageclass
}
step "default StorageClass (local-path-provisioner v0.0.31)" storage

hosting() {
  k apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:$reg_port"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF
}
step "kube-public/local-registry-hosting" hosting

# 3. ATE_INSTALL_KIND, adapted to vk8s
cd "$sub" || fail "cd $sub"
adapt() {
  local f=manifests/ate-install/kind/atelet/kustomization.yaml
  grep -q -- "--localhost-registry-replacement=kind-registry:5000" "$f" || {
    echo "$f has no --localhost-registry-replacement=kind-registry:5000 any more"; return 1; }
  sed -i "s|--localhost-registry-replacement=kind-registry:5000|--localhost-registry-replacement=$reg_from_vm|" "$f" &&
    git --no-pager diff --stat && git --no-pager diff
}
step "atelet: --localhost-registry-replacement=$reg_from_vm" adapt
export ATE_INSTALL_KIND=true
export KUBECTL_CONTEXT=$ctx
export ATE_INSTALL_ROLLOUT_TIMEOUT=${ATE_INSTALL_ROLLOUT_TIMEOUT:-20m}
export ATE_INSTALL_SANDBOX_CLASSES=gvisor

# 4. the quickstart
step "ate-setup deploy ate-system" \
  go run ./cmd/ate-setup deploy ate-system --credential-provider='{"name":"k8s.io"}' \
  --ingress-allowed-spiffe-ids=spiffe://cluster.local/ns/ate-system/sa/atenet-client
step "ate-setup deploy demo counter" go run ./cmd/ate-setup deploy demo counter
step "go install ./cmd/kubectl-ate" go install ./cmd/kubectl-ate
export PATH="$(go env GOPATH)/bin:$PATH"
step "kubectl ate create actor my-counter-1" \
  kubectl ate create actor my-counter-1 -a ate-demo-counter --template counter

kubectl ate proxy actor my-counter-1 -a ate-demo-counter > "$out/proxy.log" 2>&1 &
proxy_pid=$!
proxy_up() {
  until_ok 180 bash -c 'echo > /dev/tcp/127.0.0.1/8000' || { cat "$out/proxy.log"; return 1; }
}
step "kubectl ate proxy actor my-counter-1 (127.0.0.1:8000)" proxy_up

# the memory count of a response
count() { sed -n 's/.*preserved memory count: \([0-9][0-9]*\).*/\1/p' "$1" | head -n 1; }
post() { curl -sS -X POST -i --max-time 60 http://127.0.0.1:8000/ > "$1" 2>&1 && grep -q '^HTTP/1.1 200' "$1"; }
first=""
counter() {
  until_ok 300 post "$out/post1.txt" || { cat "$out/post1.txt"; echo "== proxy log"; cat "$out/proxy.log"; return 1; }
  cat "$out/post1.txt"
  first=$(count "$out/post1.txt")
  [ -n "$first" ] || { echo "no memory count in the first response"; return 1; }
  post "$out/post2.txt" || { cat "$out/post2.txt"; return 1; }
  cat "$out/post2.txt"
  local second; second=$(count "$out/post2.txt")
  echo "memory count: $first, then $second"
  [ "$second" = $(( first + 1 )) ]
}
step "curl -X POST http://localhost:8000/ twice: the counter increments" counter
echo "== proxy log"; cat "$out/proxy.log"

summary "PASS"
cleanup
echo "PASS substrate-e2e"
