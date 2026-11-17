#!/usr/bin/env bash
# A second node for a native cluster on one Linux CI runner, joined by
# the cluster's own installing join script (vk8s token create, then
# Join.install over curl | sh), so that the certified conformance run
# has the two untainted nodes that two [Conformance] tests ask for
# (docs/STATUS.md, section 8).
#
#   scripts/native-worker.sh up CLUSTER [NODE]
#   scripts/native-worker.sh down CLUSTER [NODE]
#
# The runner is already the cluster's host node (its kubelet ports, cni0,
# kube-proxy's rules, /sys/fs/cgroup/kubepods), so the second node runs
# isolated from it: a privileged container with its own systemd, mount,
# cgroup and network namespaces. The image is kind's node image (a
# Debian root with systemd, iproute2, iptables and curl, and an entrypoint
# that prepares cgroup v2 and mounts for a nested kubelet). Its own
# containerd and kubelet units are disabled and removed before the join;
# the join script installs vk8s's node bundle (loft-sh/kubernetes
# v1.36.6), its containerd and its kubelet, as on any Linux machine.
#
# Network: the container has no Docker network (--network none). A veth
# joins it to the bridge vk8sw0 at 192.168.77.1/24, where the node has
# 192.168.77.2; the host masquerades its traffic out. flannel's host-gw
# backend routes a node's pod /24 through its peer's node IP on its own
# external interface, so:
#   - in the node, the host's IP (NODE_IP of cluster.env) is on-link on
#     eth0, and the node's flannel adds its route to the host's pods;
#   - on the host, flannel's route to the node's pods (via 192.168.77.2
#     on eth0) cannot exist, so a policy rule sends the node's pod CIDR
#     through vk8sw0 (table 177).
# Needs docker, sudo, ip, iptables, kubectl and the vk8s binary
# (VK8S_BIN, default out/vk8s). Linux only; runs as a user with
# passwordless sudo (GitHub's ubuntu-latest).
set -euo pipefail
cd "$(dirname "$0")/.."
cmd=${1:?usage: scripts/native-worker.sh up|down CLUSTER [NODE]}
name=${2:?usage: scripts/native-worker.sh up|down CLUSTER [NODE]}
node=${3:-$name-w1}
v=${VK8S_BIN:-out/vk8s}
# kind v0.33.0's image for Kubernetes 1.36 (its release notes pin the
# digest); only its root and entrypoint are used
image=${VK8S_WORKER_IMAGE:-kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed}
br=vk8sw0
net=192.168.77
hip=$net.1
wip=$net.2
hveth=vk8sw0h
cveth=vk8sw0c
table=177
tag="vk8s-worker:$name"
d=$HOME/.vk8s/clusters/$name
export KUBECONFIG=$d/kubeconfig.yaml

say() { echo "native-worker: $*"; }
x() { echo "+ $*"; "$@"; }
in_node() { docker exec "$node" "$@"; }

down() {
  x docker rm -f "$node" >/dev/null 2>&1 || true
  while sudo ip rule del lookup "$table" 2>/dev/null; do :; done
  sudo ip route flush table "$table" 2>/dev/null || true
  sudo ip link delete "$hveth" 2>/dev/null || true
  sudo ip link delete "$br" 2>/dev/null || true
  for spec in "nat POSTROUTING -s $net.0/24 ! -o $br -j MASQUERADE" "filter FORWARD -i $br -j ACCEPT" "filter FORWARD -o $br -j ACCEPT"; do
    set -- $spec
    t=$1; shift
    while sudo iptables -t "$t" -D "$@" -m comment --comment "$tag" 2>/dev/null; do :; done
  done
  say "node $node is gone"
}

up() {
  [ -f "$d/cluster.env" ] || { say "no cluster $name ($d/cluster.env)"; exit 1; }
  hostip=$(sed -n 's/^NODE_IP=//p' "$d/cluster.env")
  [ -n "$hostip" ] || { say "no NODE_IP in $d/cluster.env"; exit 1; }
  command -v docker >/dev/null || { say "docker is missing"; exit 1; }

  # the bridge, NAT and forwarding (Docker's FORWARD policy is DROP)
  x sudo ip link add "$br" type bridge
  x sudo ip addr add "$hip/24" dev "$br"
  x sudo ip link set "$br" up
  x sudo sysctl -q -w "net.ipv4.conf.$br.proxy_arp=1"
  x sudo iptables -t nat -A POSTROUTING -s "$net.0/24" ! -o "$br" -j MASQUERADE -m comment --comment "$tag"
  x sudo iptables -t filter -I FORWARD 1 -i "$br" -j ACCEPT -m comment --comment "$tag"
  x sudo iptables -t filter -I FORWARD 1 -o "$br" -j ACCEPT -m comment --comment "$tag"

  # the container, as kind runs a node (kind pkg/cluster/internal/providers/docker)
  x docker run -d --name "$node" --hostname "$node" --privileged \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined \
    --cgroupns=private --network none --tmpfs /tmp --tmpfs /run \
    --volume /var --volume /lib/modules:/lib/modules:ro -e container=docker \
    "$image" >/dev/null
  pid=$(docker inspect -f '{{.State.Pid}}' "$node")
  x sudo ip link add "$hveth" type veth peer name "$cveth"
  x sudo ip link set "$hveth" master "$br" up
  x sudo ip link set "$cveth" netns "$pid"
  x in_node ip link set "$cveth" name eth0
  x in_node ip addr add "$wip/24" dev eth0
  x in_node ip link set lo up
  x in_node ip link set eth0 up
  x in_node ip route add "$hostip/32" dev eth0 scope link
  x in_node ip route add default via "$hip" dev eth0
  # the kubelet takes the node IP from the hostname
  in_node sh -c "echo '$wip $node' >> /etc/hosts"
  # the host's upstream resolvers (its /etc/resolv.conf is
  # systemd-resolved's stub at 127.0.0.53); the kubelet reads either file,
  # as the cluster's kubelet configuration says
  dns=$(grep '^nameserver' /run/systemd/resolve/resolv.conf 2>/dev/null | grep -v ' 127\.' || true)
  [ -n "$dns" ] || dns="nameserver 8.8.8.8"

  # systemd up, kind's own containerd and kubelet out of the way
  i=0
  until s=$(in_node systemctl is-system-running 2>/dev/null); [ "$s" = running ] || [ "$s" = degraded ]; do
    i=$((i + 1)); [ "$i" -lt 120 ] || { say "systemd in $node did not start ($s)"; exit 1; }
    sleep 1
  done
  in_node sh -c "printf '%s\n' '$dns' > /etc/resolv.conf; mkdir -p /run/systemd/resolve; cp /etc/resolv.conf /run/systemd/resolve/resolv.conf"
  x in_node sh -c 'systemctl disable --now kubelet.service containerd.service 2>/dev/null || true
    rm -rf /etc/systemd/system/kubelet.service.d /usr/lib/systemd/system/kubelet.service.d /lib/systemd/system/kubelet.service.d
    rm -f /etc/systemd/system/kubelet.service /usr/lib/systemd/system/kubelet.service /lib/systemd/system/kubelet.service
    systemctl daemon-reload
    sed -e "s/ / +/g" -e "s/^/+/" /sys/fs/cgroup/cgroup.controllers > /sys/fs/cgroup/cgroup.subtree_control || true'

  # join with the cluster's installing join script
  out=$("$v" token create "$name")
  url=$(printf '%s\n' "$out" | grep -o 'https://[^" ]*/node/join?token=[^" ]*' | head -1)
  [ -n "$url" ] || { say "no join URL in: $out"; exit 1; }
  say "joining $node with ${url%%\?*}"
  in_node sh -c "curl -fsSLk '$url' | sh -s --"

  x kubectl wait --for=condition=Ready "node/$node" --timeout=600s
  cidr=$(kubectl get node "$node" -o jsonpath='{.spec.podCIDR}')
  [ -n "$cidr" ] || { say "node $node has no pod CIDR"; exit 1; }
  x sudo ip route replace "$cidr" via "$wip" dev "$br" table "$table"
  x sudo ip rule add to "$cidr" lookup "$table" priority "$table"
  kubectl get nodes -o wide
}

case $cmd in
  up) up ;;
  down) down ;;
  *) echo "usage: scripts/native-worker.sh up|down CLUSTER [NODE]"; exit 2 ;;
esac
