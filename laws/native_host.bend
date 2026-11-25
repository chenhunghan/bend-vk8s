import Base
import ../src/standalone/native_host.bend as NH
import ../src/standalone/native.bend as N
import ../src/guest/plan.bend as P

# Spec for src/standalone/native_host.bend: native mode on a Linux host,
# the host side (docs/GOAL.md section 8, docs/ref/explore-linux-hosts.md
# Phase 5, N3 and N4, docs/ref/native-host.md). vcluster standalone runs
# as one systemd unit (install-standalone.sh: Restart=always,
# RestartSec=5s, Delegate=yes); its runtime is closed source
# (pkg/pro/standalone.go), so the values are vk8s design.

# Proposed: native mode, N3 (the unit, install and delete) and N4 (the
# binaries, the preflight, several clusters per host).

# --- The unit

law native.unit_name:
  {NH.NHost.unit_name("demo") == "vk8s-demo.service" : String}

law native.unit_path:
  {NH.NHost.unit_path("demo") == "/etc/systemd/system/vk8s-demo.service" : String}

law native.data_dir:
  {NH.NHost.data_dir("demo") == "/var/lib/vk8s/demo" : String}

law native.unit_text:
  {NH.NHost.unit(NH.Inst{"demo", "/var/lib/vk8s/demo", "/home/u/.vk8s/clusters/demo/share", "10.1.0.4", 10443, False{}, True{}, "amd64",
     "/run/systemd/resolve/resolv.conf"}) ==
   "[Unit]\nDescription=vk8s native cluster demo\nWants=network-online.target\nAfter=network-online.target\n\n[Service]\nType=simple\n"
   ++ "Environment=VK8S_DATA=/var/lib/vk8s/demo\nEnvironment=VK8S_SHARE=/home/u/.vk8s/clusters/demo/share\nEnvironment=VK8S_NAME=demo\n"
   ++ "Environment=VK8S_STORE=sqlite\nEnvironment=VK8S_NODE_IP=10.1.0.4\nEnvironment=VK8S_PORT=10443\nEnvironment=VK8S_HOST_NODE=1\n"
   ++ "Environment=VK8S_ARCH=amd64\nEnvironment=VK8S_RESOLV=/run/systemd/resolve/resolv.conf\nEnvironment=VK8S_JOIN_INSTALL=1\n"
   ++ "ExecStart=/var/lib/vk8s/demo/vk8s native\nRestart=always\nRestartSec=5s\nKillMode=control-group\nDelegate=yes\n"
   ++ "TimeoutStopSec=90\nLimitNOFILE=1048576\nTasksMax=infinity\n\n[Install]\nWantedBy=multi-user.target\n" : String}

# The unit's supervision, whatever the cluster: restarted 5 s after it
# exits, every process it started ended with it, its cgroup delegated, and
# vk8s in native supervisor mode over the data dir.
law native.unit_restart:
  {String.contains(NH.NHost.unit(NH.Inst{"a", "/var/lib/vk8s/a", "/s", "10.0.0.1", 11000, True{}, False{}, "", "/etc/resolv.conf"}),
    "\nRestart=always\nRestartSec=5s\n") == True{} : Bool}

law native.unit_kill_mode:
  {String.contains(NH.NHost.unit(NH.Inst{"a", "/var/lib/vk8s/a", "/s", "10.0.0.1", 11000, True{}, False{}, "", "/etc/resolv.conf"}),
    "\nKillMode=control-group\n") == True{} : Bool}

law native.unit_delegate:
  {String.contains(NH.NHost.unit(NH.Inst{"a", "/var/lib/vk8s/a", "/s", "10.0.0.1", 11000, True{}, False{}, "", "/etc/resolv.conf"}),
    "\nDelegate=yes\n") == True{} : Bool}

law native.unit_exec:
  {String.contains(NH.NHost.unit(NH.Inst{"a", "/var/lib/vk8s/a", "/s", "10.0.0.1", 11000, True{}, False{}, "", "/etc/resolv.conf"}),
    "\nExecStart=/var/lib/vk8s/a/vk8s native\n") == True{} : Bool}

# Installed and started with sudo, each command an argument list.
law native.install_cmds:
  {NH.NHost.install_cmds("demo", "/home/u/.vk8s/clusters/demo/vk8s-demo.service") ==
    [ ["sudo", "install", "-m", "0644", "/home/u/.vk8s/clusters/demo/vk8s-demo.service", "/etc/systemd/system/vk8s-demo.service"],
      ["sudo", "systemctl", "daemon-reload"],
      ["sudo", "systemctl", "enable", "--now", "vk8s-demo.service"] ] : List<&2, List<&2, String>>}

# What is printed before a command runs: its words, quoted only where a
# shell would need it.
law native.show:
  {NH.NHost.show(["sudo", "systemctl", "enable", "--now", "vk8s-demo.service"]) == "+ sudo systemctl enable --now vk8s-demo.service" : String}

law native.show_quotes:
  {NH.NHost.show(["sudo", "find", "/var/lib/cni/results", "-name", "cbr0-*", ""]) == "+ sudo find /var/lib/cni/results -name 'cbr0-*' ''" : String}

# --- N4: the binaries

law native.prepare_cmds:
  {NH.NHost.prepare_cmds("/var/lib/vk8s/demo", "/a", "/usr/local/bin/vk8s", NH.NHost.sets()) ==
    [ ["sudo", "mkdir", "-p", "-m", "0700", "/var/lib/vk8s/demo"],
      ["sudo", "install", "-m", "0755", "/usr/local/bin/vk8s", "/var/lib/vk8s/demo/vk8s"],
      ["sudo", "mkdir", "-p", "/var/lib/vk8s/demo/initramfs"],
      ["sudo", "cpio", "-i", "-d", "--quiet", "--no-absolute-filenames", "-D", "/var/lib/vk8s/demo/initramfs", "-F", "/a/vk8s.cpio",
        "bin/busybox", "etc/vk8s/flannel.yaml"],
      ["sudo", "install", "-m", "0755", "/var/lib/vk8s/demo/initramfs/bin/busybox", "/var/lib/vk8s/demo/busybox"],
      ["sudo", "unsquashfs", "-f", "-n", "-d", "/var/lib/vk8s/demo/bin", "/a/node.img"],
      ["sudo", "unsquashfs", "-f", "-n", "-d", "/var/lib/vk8s/demo/bin", "/a/control-plane.img"] ] : List<&2, List<&2, String>>}

# flannel on a host: the host's default interface, vk8s's CNI dirs.
law native.flannel:
  {NH.NHost.flannel("      - args:\n        - --ip-masq\n        - --kube-subnet-mgr\n        - --iface=eth1\n        command:\n"
     ++ "          path: /opt/cni/bin\n          path: /etc/cni/net.d\n") ==
   "      - args:\n        - --ip-masq\n        - --kube-subnet-mgr\n        command:\n          path: /opt/vk8s/cni/bin\n          path: /opt/vk8s/cni/net.d\n" : String}

# --- N4: the preflight names the exact command to run

law native.preflight_ok:
  {NH.NHost.preflight([], True{}, True{}, [], []) == "" : String}

law native.preflight_commands:
  {NH.NHost.preflight(["unsquashfs"], True{}, True{}, ["br_netfilter"], NH.NHost.sysctls_needed(True{}, "1\n", "")) ==
    "vk8s: --backend native needs this first:\n- install: unsquashfs\n- run: sudo modprobe -a br_netfilter\n"
    ++ "- run: sudo sysctl -w net.bridge.bridge-nf-call-iptables=1\n" : String}

law native.preflight_host:
  {NH.NHost.preflight([], False{}, False{}, [], NH.NHost.sysctls_needed(True{}, "0\n", "0\n")) ==
    "vk8s: --backend native needs this first:\n- systemd as the init system (/run/systemd/system)\n"
    ++ "- the unified cgroup v2 hierarchy at /sys/fs/cgroup\n"
    ++ "- run: sudo sysctl -w net.ipv4.ip_forward=1 net.bridge.bridge-nf-call-iptables=1\n" : String}

# A control plane without the host node changes no sysctl.
law native.sysctls_control_plane:
  {NH.NHost.sysctls_needed(False{}, "0\n", "") == [] : +List<String>}

# --- N4: several clusters per host. The plan pins 6443 (API), 8443
# (join), 2379-2381 (etcd, kine's metrics) and /var/lib/vcluster; a native
# cluster moves the ports by its API port's offset and the paths under its
# data dir.

law native.ports:
  {NH.NHost.relocate.step(NH.NHost.port_rules(10443),
     P.Run{"/k", ["--secure-port=6443", "https://10.1.0.4:6443", "bindPort: 6443", "{\"port\":6443}",
       "--listen-client-urls=https://127.0.0.1:2379", "https://127.0.0.1:2380", "--metrics-bind-address=127.0.0.1:2381"]}) ==
   P.Run{"/k", ["--secure-port=10443", "https://10.1.0.4:10443", "bindPort: 10443", "{\"port\":10443}",
       "--listen-client-urls=https://127.0.0.1:23443", "https://127.0.0.1:26443", "--metrics-bind-address=127.0.0.1:29443"]} : P.Step}

law native.wait_ports:
  {NH.NHost.post(NH.Opts{10443, True{}, "", "/etc/resolv.conf"},
     [P.WaitTcp{"127.0.0.1", 6443, 5}, P.WaitTcp{"127.0.0.1", 8443, 5}, P.WaitTcp{"127.0.0.1", 2379, 5}, P.WaitTcp{"127.0.0.1", 15004, 5}]) ==
   [P.WaitTcp{"127.0.0.1", 10443, 5}, P.WaitTcp{"127.0.0.1", 20443, 5}, P.WaitTcp{"127.0.0.1", 23443, 5}, P.WaitTcp{"127.0.0.1", 15004, 5}]
   : +List<P.Step>}

law native.join_server_port:
  {NH.NHost.extra_args(10443, "join-server") == ["--port=20443", "--api-port=10443"] : +List<String>}

law native.no_fixed_cm_port:
  {NH.NHost.extra_args(10443, "kube-controller-manager") == ["--secure-port=0"] : +List<String>}

law native.no_fixed_scheduler_port:
  {NH.NHost.extra_args(10443, "kube-scheduler") == ["--secure-port=0"] : +List<String>}

law native.kube_apiserver_args_kept:
  {NH.NHost.extra_args(10443, "kube-apiserver") == [] : +List<String>}

# The host node's containerd, CNI and static pods.
law native.node_paths:
  {NH.NHost.relocate.step(NH.NHost.node_rules("/var/lib/vk8s/demo"),
     P.Run{"/c", ["--address", "/run/containerd/containerd.sock", "/etc/containerd/config.toml", "/etc/kubernetes/manifests",
       "cp /var/lib/vcluster/bin/cni/bin/* /opt/cni/bin/", "/etc/cni/net.d", "http://10.0.2.2:15001"]}) ==
   P.Run{"/c", ["--address", "/var/lib/vk8s/demo/node/run/containerd/containerd.sock", "/var/lib/vk8s/demo/node/containerd/config.toml",
       "/var/lib/vk8s/demo/node/kubernetes/manifests", "cp /var/lib/vcluster/bin/cni/bin/* /opt/vk8s/cni/bin/", "/opt/vk8s/cni/net.d",
       "http://127.0.0.1:15001"]} : P.Step}

law native.kubelet_text:
  {NH.NHost.kubelet_text("/run/systemd/resolve/resolv.conf", "failSwapOn: false\nresolvConf: /etc/resolv.conf\nstaticPodPath: /etc/kubernetes/manifests\n")
    == "failSwapOn: false\nresolvConf: /run/systemd/resolve/resolv.conf\nstaticPodPath: /etc/kubernetes/manifests\npodLogsDir: /var/lib/vcluster/pod-logs\n"
    : String}

law native.cfg_port:
  {NH.NHost.cfg("demo", "10.1.0.4", 10443, False{}) ==
    P.Cfg{"demo", "10.1.0.4", "10.96.0.0/12", "10.244.0.0/16", "cluster.local", 10443, False{}} : P.Cfg}

law native.env_text:
  {NH.NHost.env_text("demo", 10443, False{}, "10.1.0.4", True{}) ==
    "NAME=demo\nGUEST=demo\nPORT=10443\nCPUS=0\nMEMORY=0\nSTORE=sqlite\nNODES=0\nWORKERS=\nKUBERNETES=v1.36.6\nBACKEND=native\n"
    ++ "NODE_IP=10.1.0.4\nHOST_NODE=1\nDATA=/var/lib/vk8s/demo\nUNIT=vk8s-demo.service\nAPI_ENDPOINT=10.1.0.4:10443\n"
    ++ "JOIN_ENDPOINT=10.1.0.4:20443\n" : String}

# --- N3: delete leaves nothing: every unit, file, dir and link create
# makes is one a delete command removes; the unit is stopped first.

law native.delete_leaves_nothing:
  {NH.NHost.leftover(NH.NHost.made("demo", "/home/u/.vk8s/clusters/demo", True{}),
     NH.NHost.removes(NH.NHost.delete_cmds("demo", "/home/u/.vk8s/clusters/demo", True{}))) == [] : +List<String>}

law native.delete_leaves_nothing.control_plane:
  {NH.NHost.leftover(NH.NHost.made("demo", "/home/u/.vk8s/clusters/demo", False{}),
     NH.NHost.removes(NH.NHost.delete_cmds("demo", "/home/u/.vk8s/clusters/demo", False{}))) == [] : +List<String>}

law native.delete_stops_first:
  {List.take(&2, List<&2, String>, NH.NHost.delete_cmds("demo", "/home/u/.vk8s/clusters/demo", True{}), 1n) ==
    [["sudo", "systemctl", "disable", "--now", "vk8s-demo.service"]] : List<&2, List<&2, String>>}

# A leftover is reported.
law native.leftover:
  {NH.NHost.leftover(["/a", "link:cni0", "/b"], ["/b"]) == ["/a", "link:cni0"] : +List<String>}

# The pods' mounts under the data dir, the last mounted first; another
# cluster's (demo2) and the host's stay.
law native.mounts_under:
  {NH.NHost.mounts_under("22 1 8:1 / / rw - ext4 /dev/sda1 rw\n301 22 0:50 / /var/lib/vk8s/demo/kubelet/pods/a/volumes/x rw - tmpfs tmpfs rw\n"
     ++ "302 22 0:51 / /var/lib/vk8s/demo2/x rw - tmpfs tmpfs rw\n303 22 0:52 / /var/lib/vk8s/demo/node/run/containerd/x/rootfs rw - overlay overlay rw\n",
     "/var/lib/vk8s/demo") ==
   ["/var/lib/vk8s/demo/node/run/containerd/x/rootfs", "/var/lib/vk8s/demo/kubelet/pods/a/volumes/x"] : +List<String>}

law native.umount_cmds:
  {NH.NHost.umount_cmds(["/var/lib/vk8s/demo/x"]) == [["sudo", "umount", "-l", "/var/lib/vk8s/demo/x"]] : List<&2, List<&2, String>>}

# iptables: only the tables that held a KUBE-, FLANNEL- or CNI- line go
# back to iptables-restore, without those lines (iptables-save(8),
# iptables-restore(8): a table in the input is replaced whole).
law native.ipt_clean:
  {NH.NHost.ipt_clean("# Generated by iptables-nft-save\n*nat\n:PREROUTING ACCEPT [0:0]\n:DOCKER - [0:0]\n"
     ++ "-A PREROUTING -m addrtype --dst-type LOCAL -j DOCKER\nCOMMIT\n*filter\n:INPUT ACCEPT [0:0]\n:KUBE-FIREWALL - [0:0]\n"
     ++ ":FLANNEL-FWD - [0:0]\n-A INPUT -j KUBE-FIREWALL\n-A INPUT -i lo -j ACCEPT\n-A FORWARD -m comment --comment \"flanneld forward\" -j FLANNEL-FWD\n"
     ++ "COMMIT\n# Completed\n") ==
   "*filter\n:INPUT ACCEPT [0:0]\n-A INPUT -i lo -j ACCEPT\nCOMMIT\n# Completed\n" : String}

law native.ipt_clean_none:
  {NH.NHost.ipt_clean("*filter\n:INPUT ACCEPT [0:0]\n-A INPUT -i lo -j ACCEPT\nCOMMIT\n") == "" : String}

# The host's address, from `ip -4 -o route get 1.1.1.1`.
law native.route_src:
  {NH.NHost.route_src("1.1.1.1 via 10.1.0.1 dev eth0 src 10.1.0.4 uid 1001 \\    cache \n") == "10.1.0.4" : String}

law native.ip_ok:
  {NH.NHost.ip_ok("10.1.0.4") == True{} : Bool}

law native.ip_ok.not_an_address:
  {NH.NHost.ip_ok("10.1.0.4;x") == False{} : Bool}

# Proposed: gVisor on a host node (docs/GOAL.md section 8). The shim keeps
# runsc's state under its `root` option, by default the host's
# /run/containerd/runsc (gVisor pkg/shim/v1/proc/proc.go RunscRoot;
# pkg/shim/v1/runsc/options.go `toml:"root"`), where a host's own
# containerd keeps its state. runsc.toml names that root, so the host
# node's path rules move it under the data dir with containerd's state.
law native.runsc_text:
  {NH.NHost.runsc_text("binary_name = \"/r\"\n") == "root = \"/run/containerd/runsc\"\nbinary_name = \"/r\"\n" : String}

law native.extra_runsc:
  {NH.NHost.extra.step(NH.Opts{11000, True{}, "amd64", "/run/systemd/resolve/resolv.conf"},
     P.Write{"/etc/containerd/runsc.toml", "binary_name = \"/r\"\n"}) ==
   P.Write{"/etc/containerd/runsc.toml", "root = \"/run/containerd/runsc\"\nbinary_name = \"/r\"\n"} : P.Step}

law native.runsc_root:
  {NH.NHost.relocate.step(NH.NHost.node_rules("/var/lib/vk8s/demo"), P.Write{"/etc/containerd/runsc.toml", "root = \"/run/containerd/runsc\"\n"}) ==
   P.Write{"/var/lib/vk8s/demo/node/containerd/runsc.toml", "root = \"/var/lib/vk8s/demo/node/run/containerd/runsc\"\n"} : P.Step}

# Proposed: vk8s.nodes.proxyArp on a host node (src/guest/values.bend; the
# sysctls of agent-substrate's hack/create-kind-cluster.sh: `sysctl
# net.ipv4.conf.all.proxy_arp=1`, `sysctl -e net.ipv6.conf.all.proxy_ndp=1`).
# The preflight asks for those not yet 1; a host without IPv6 (no
# proxy_ndp file) skips the IPv6 one.

law native.proxy_sysctls:
  {NH.NHost.proxy_sysctls_needed(True{}, True{}, "0\n", "0\n") == ["net.ipv4.conf.all.proxy_arp=1", "net.ipv6.conf.all.proxy_ndp=1"] : +List<String>}

law native.proxy_sysctls_no_ipv6:
  {NH.NHost.proxy_sysctls_needed(True{}, True{}, "0\n", "") == ["net.ipv4.conf.all.proxy_arp=1"] : +List<String>}

law native.proxy_sysctls_set:
  {NH.NHost.proxy_sysctls_needed(True{}, True{}, "1\n", "1\n") == [] : +List<String>}

# Off (the default), or a control plane without the host node: none.
law native.proxy_sysctls_off:
  {NH.NHost.proxy_sysctls_needed(False{}, True{}, "0\n", "0\n") == [] : +List<String>}

law native.proxy_sysctls_control_plane:
  {NH.NHost.proxy_sysctls_needed(True{}, False{}, "0\n", "0\n") == [] : +List<String>}

law native.preflight_proxy:
  {NH.NHost.preflight([], True{}, True{}, [], List.append(&2, String, NH.NHost.sysctls_needed(True{}, "1\n", "1\n"),
     NH.NHost.proxy_sysctls_needed(True{}, True{}, "0\n", "0\n"))) ==
    "vk8s: --backend native needs this first:\n"
    ++ "- run: sudo sysctl -w net.ipv4.conf.all.proxy_arp=1 net.ipv6.conf.all.proxy_ndp=1\n" : String}
# Proposed: the host node's containerd config keeps the VM's image
# section (P.Plan.containerd_images: layer blobs discarded once
# unpacked, docs/GOAL.md section 10); the host node's rewrite only adds
# the runc shim's path and the host's extras.
law native.extra_containerd_images:
  {NH.NHost.extra.step(NH.Opts{11000, True{}, "amd64", "/run/systemd/resolve/resolv.conf"},
     P.Write{"/etc/containerd/config.toml", P.Plan.containerd_images()}) ==
   P.Write{"/etc/containerd/config.toml", P.Plan.containerd_images() ++ NH.NHost.containerd_extra()} : P.Step}

# Proposed: native mode v2 touches only what is the cluster's own
# (security review docs/ref/review-security-boundary-delta.md, F1). The
# pinned v1 defs above stay; the host runs the v2 ones.

# The host node's kubelet runs its pods under the cluster's own cgroup
# root (kubelet --cgroup-root; container mode's kind config.go:278 uses
# /kubelet), not the host's /kubepods.
law native.cgroup_root:
  {NH.NHost.cgroup_root("demo") == "/vk8s-demo" : String}

law native.cgroup_dir:
  {NH.NHost.cgroup_dir("demo") == "/sys/fs/cgroup/vk8s-demo" : String}

law native.env_cgroup:
  {NH.NHost.env_cgroup("demo") == "CGROUP=/vk8s-demo\n" : String}

law native.kubelet_cgroup_root:
  {NH.NHost.kubelet_root("/vk8s-demo", [P.Daemon{"kubelet", "/k", ["--a=b"]}, P.Daemon{"containerd", "/c", ["--x"]}, P.Log{"kubelet"}]) ==
    [P.Daemon{"kubelet", "/k", ["--a=b", "--cgroup-root=/vk8s-demo"]}, P.Daemon{"containerd", "/c", ["--x"]}, P.Log{"kubelet"}] : +List<P.Step>}

# The v2 node reset ends the cluster's own cgroup only, never the host's
# /kubepods, and refuses while another kubelet runs or /kubepods holds
# pods.
law native.reset_v2_own_cgroup:
  {NH.NHost.reset_kill.v2("demo") ==
    "c=/sys/fs/cgroup/vk8s-demo; if [ -e $c/cgroup.kill ]; then echo 1 > $c/cgroup.kill; sleep 2; fi; " : String}

# The whole v2 reset for a cluster "demo": it refuses while another
# kubelet runs in the host's network namespace or /kubepods holds a
# process, and kills only /sys/fs/cgroup/vk8s-demo (never $k/cgroup.kill).
law native.reset_v2_script:
  {NH.NHost.reset_script.v2("/var/lib/vk8s/demo", "demo") ==
    "o=$(n=$(readlink /proc/1/ns/net); for p in /proc/[0-9]*; do c=$(cat $p/comm 2>/dev/null) || continue; case $c in (kubelet|k3s|k3s-server|k3s-agent|kubelite) if [ \"$(readlink $p/ns/net)\" = \"$n\" ]; then echo \"${p#/proc/} $c $(readlink $p/exe)\"; fi;; esac; done; true); if [ -n \"$o\" ]; then echo \"vk8s: another kubelet runs on this host ($o); the host node does not start\"; exit 1; fi; k=/sys/fs/cgroup/kubepods; if [ -d $k ] && find $k -name cgroup.procs -exec cat {} + 2>/dev/null | grep -q .; then echo \"vk8s: $k holds pods that are not this cluster's; the host node does not start\"; exit 1; fi; c=/sys/fs/cgroup/vk8s-demo; if [ -e $c/cgroup.kill ]; then echo 1 > $c/cgroup.kill; sleep 2; fi; awk -v d='/var/lib/vk8s/demo/' 'index($5, d) == 1 { print $5 }' /proc/self/mountinfo | sort -r | while read -r m; do umount -l \"$m\" || true; done; rm -rf '/var/lib/vk8s/demo/kubelet' '/var/lib/vk8s/demo/node/run'; if [ -d $c ]; then find $c -mindepth 1 -depth -type d -exec rmdir {} + 2>/dev/null; fi; mkdir -p $c && { sed -e 's/ / +/g' -e 's/^/+/' $c/cgroup.controllers > $c/cgroup.subtree_control || true; }" : String}

law native.reset_v2_step:
  {NH.NHost.reset.v2(N.Native.env_of("/var/lib/vk8s/demo", "", "/s", "", "", ""), "demo") ==
    P.Run{"/var/lib/vk8s/demo/busybox", ["sh", "-c", NH.NHost.reset_script.v2("/var/lib/vk8s/demo", "demo")]} : P.Step}

# Which kubelets run, from the script's "<pid> <name> <exe>" lines: k3s
# is foreign; a native cluster's kubelet runs from its data dir.
law native.foreign_kubelets:
  {NH.NHost.foreign_kubelets("812 k3s-server /usr/local/bin/k3s\n901 kubelet /var/lib/vk8s/a/bin/kubelet\n\n") ==
    ["812 k3s-server /usr/local/bin/k3s"] : +List<String>}

law native.vk8s_kubelets:
  {NH.NHost.vk8s_kubelets("812 k3s-server /usr/local/bin/k3s\n901 kubelet /var/lib/vk8s/a/bin/kubelet\n\n") ==
    ["901 kubelet /var/lib/vk8s/a/bin/kubelet"] : +List<String>}

law native.no_kubelets:
  {NH.NHost.foreign_kubelets("") == [] : +List<String>}

# Delete ends the cluster's own cgroup; a cluster made before v2 (no
# CGROUP line) used /kubepods, which it leaves while another kubelet runs.
law native.kill_dir:
  {NH.NHost.kill_dir("/vk8s-demo", False{}, "demo") == "/sys/fs/cgroup/vk8s-demo" : String}

law native.kill_dir_shared:
  {NH.NHost.kill_dir("/vk8s-demo", True{}, "demo") == "/sys/fs/cgroup/vk8s-demo" : String}

law native.kill_dir_legacy:
  {NH.NHost.kill_dir("", False{}, "demo") == "/sys/fs/cgroup/kubepods" : String}

law native.kill_dir_legacy_shared:
  {NH.NHost.kill_dir("", True{}, "demo") == "" : String}

# iptables v2: by exact name, for iptables-restore --noflush (iptables-
# restore(8): with --noflush a table is not flushed; -D, -F and -X act on
# what they name). kube-proxy's KUBE-SERVICES and its hashed
# KUBE-SVC-NPX46M4PTMTKRN6Y (default/kubernetes:https), kubelet's
# KUBE-FIREWALL, flannel's FLANNEL-FWD and portmap's chain for cbr0
# leave, with the rules that jump to them; Docker's chain, portmap's
# shared CNI-HOSTPORT-DNAT, another network's (podman) chain and a
# KUBE- name of no known form stay.
law native.ipt_delete:
  {NH.NHost.ipt_delete(NH.NHost.ipt_names(), NH.NHost.ipt_hashed(), True{},
     "# Generated by iptables-nft-save\n*nat\n:PREROUTING ACCEPT [0:0]\n:DOCKER - [0:0]\n:KUBE-SERVICES - [0:0]\n"
     ++ ":KUBE-SVC-NPX46M4PTMTKRN6Y - [0:0]\n:KUBE-SVC-MINE - [0:0]\n"
     ++ "-A PREROUTING -m addrtype --dst-type LOCAL -j DOCKER\n"
     ++ "-A PREROUTING -m comment --comment \"kubernetes service portals\" -j KUBE-SERVICES\n"
     ++ "-A KUBE-SERVICES -d 10.96.0.1/32 -p tcp -m comment --comment \"default/kubernetes:https cluster IP\" -j KUBE-SVC-NPX46M4PTMTKRN6Y\n"
     ++ "-A KUBE-SVC-MINE -j RETURN\nCOMMIT\n# Completed\n") ==
   "*nat\n-D PREROUTING -m comment --comment \"kubernetes service portals\" -j KUBE-SERVICES\n"
   ++ "-F KUBE-SERVICES\n-F KUBE-SVC-NPX46M4PTMTKRN6Y\n"
   ++ "-X KUBE-SERVICES\n-X KUBE-SVC-NPX46M4PTMTKRN6Y\nCOMMIT\n" : String}

# The CNI portmap chains: only the DN chain a cbr0-tagged rule jumps to.
law native.ipt_delete_cni:
  {NH.NHost.ipt_delete(NH.NHost.ipt_names(), NH.NHost.ipt_hashed(), True{},
     "*nat\n:CNI-HOSTPORT-DNAT - [0:0]\n"
     ++ ":CNI-DN-0123456789abcdef01234 - [0:0]\n:CNI-DN-fedcba9876543210fedcb - [0:0]\n"
     ++ "-A CNI-HOSTPORT-DNAT -p tcp -m comment --comment \"dnat name: \\\"cbr0\\\" id: \\\"abc\\\"\" -m multiport --dports 80 -j CNI-DN-0123456789abcdef01234\n"
     ++ "-A CNI-HOSTPORT-DNAT -p tcp -m comment --comment \"dnat name: \\\"podman\\\" id: \\\"def\\\"\" -m multiport --dports 81 -j CNI-DN-fedcba9876543210fedcb\n"
     ++ "COMMIT\n") ==
   "*nat\n-D CNI-HOSTPORT-DNAT -p tcp -m comment --comment \"dnat name: \\\"cbr0\\\" id: \\\"abc\\\"\" -m multiport --dports 80 -j CNI-DN-0123456789abcdef01234\n"
   ++ "-F CNI-DN-0123456789abcdef01234\n-X CNI-DN-0123456789abcdef01234\nCOMMIT\n" : String}

# The filter table: kubelet's and flannel's chains and their jumps.
law native.ipt_delete_filter:
  {NH.NHost.ipt_delete(NH.NHost.ipt_names(), NH.NHost.ipt_hashed(), True{},
     "*filter\n:INPUT ACCEPT [0:0]\n:KUBE-FIREWALL - [0:0]\n:FLANNEL-FWD - [0:0]\n-A INPUT -j KUBE-FIREWALL\n-A INPUT -i lo -j ACCEPT\n"
     ++ "-A FORWARD -m comment --comment \"flanneld forward\" -j FLANNEL-FWD\nCOMMIT\n") ==
   "*filter\n-D INPUT -j KUBE-FIREWALL\n-D FORWARD -m comment --comment \"flanneld forward\" -j FLANNEL-FWD\n"
   ++ "-F KUBE-FIREWALL\n-F FLANNEL-FWD\n-X KUBE-FIREWALL\n-X FLANNEL-FWD\nCOMMIT\n" : String}

# A save with none of vk8s's chains gives nothing to restore.
law native.ipt_delete_none:
  {NH.NHost.ipt_delete(NH.NHost.ipt_names(), NH.NHost.ipt_hashed(), True{},
    "*filter\n:INPUT ACCEPT [0:0]\n:DOCKER - [0:0]\n-A INPUT -i lo -j ACCEPT\n-A INPUT -j DOCKER\nCOMMIT\n") == "" : String}

# A rule that only mentions a KUBE- name (in a comment) is not vk8s's.
law native.ipt_delete_by_name:
  {NH.NHost.ipt_delete(NH.NHost.ipt_names(), NH.NHost.ipt_hashed(), True{},
    "*filter\n:INPUT ACCEPT [0:0]\n:MINE - [0:0]\n-A INPUT -m comment --comment KUBE-SERVICES -j MINE\nCOMMIT\n") == "" : String}

# The hashed names: a prefix and exactly 16 base32 characters.
law native.hashed_ok:
  {NH.NHost.hashed_ok(NH.NHost.ipt_hashed(), "KUBE-SEP-ABCDEFGHIJKLMN27") == True{} : Bool}

law native.hashed_short:
  {NH.NHost.hashed_ok(NH.NHost.ipt_hashed(), "KUBE-SEP-ABCDEFGHIJKLMN2") == False{} : Bool}

law native.hashed_not_base32:
  {NH.NHost.hashed_ok(NH.NHost.ipt_hashed(), "KUBE-SEP-ABCDEFGHIJKLMN28") == False{} : Bool}

law native.ipt_restore_cmd:
  {NH.NHost.ipt_restore_cmd("iptables-legacy") == ["sudo", "iptables-legacy-restore", "--noflush"] : +List<String>}

# Proposed: the v3 node reset first lets the root cgroup pass its
# controllers down, so the kubelet accepts --cgroup-root=/vk8s-<name>
# (native-smoke on 93d1890: "has some missing controllers: hugetlb").
law native.root_ctl:
  {NH.NHost.root_ctl() ==
    "r=/sys/fs/cgroup; for x in $(cat $r/cgroup.controllers); do echo +$x > $r/cgroup.subtree_control 2>/dev/null || true; done; " : String}

law native.reset_v3_script:
  for d: String
  for n: String
  {NH.NHost.reset_script.v3(d, n) == NH.NHost.root_ctl() ++ NH.NHost.reset_script.v2(d, n) : String}

# Proposed: shared binaries (docs/GOAL.md section 11, "Shared assets and
# layers off the VM"; docs/ref/native-host.md). The role sets are
# unpacked once per asset version into /var/lib/vk8s/.assets/<key>/bin,
# atomically (a stage dir renamed into place), and each cluster's bin/
# is a symlink to it (prepare_cmds.v2 replaces prepare_cmds' unsquashfs
# per cluster). Delete removes the shared copy with the last cluster that
# links to it. vcluster has no equivalent (one cluster per host, its
# binaries in $DATA_DIR/bin): the values are vk8s design. The key's
# expected values come from coreutils: printf '%s\n%s\n' H1 H2 | sha256sum,
# first 16 digits, where H1 and H2 are the sha256sum of "node" and of
# "control-plane".

law native.assets_root:
  {NH.NHost.assets_root() == "/var/lib/vk8s/.assets" : String}

law native.shared_bin:
  {NH.NHost.shared_bin("0123456789abcdef") == "/var/lib/vk8s/.assets/0123456789abcdef/bin" : String}

law native.sum_cmd:
  {NH.NHost.sum_cmd("/a", NH.NHost.sets()) == ["sha256sum", "/a/node.img", "/a/control-plane.img"] : +List<String>}

law native.asset_key:
  {NH.NHost.asset_key("545ea538461003efdc8c81c244531b003f6f26cfccf6c0073b3239fdedf49446  /a/node.img\n"
     ++ "9682666514c07508d9ee41ca0a32cf2fc8e0fbda9466c5bfd0f88b82ca5389e9  /a/control-plane.img\n") == "6a6e2f93465b898a" : String}

# The same images in another asset dir share the copy.
law native.asset_key_paths:
  {NH.NHost.asset_key("545ea538461003efdc8c81c244531b003f6f26cfccf6c0073b3239fdedf49446  /home/u/.vk8s/assets/dev/node.img\n"
     ++ "9682666514c07508d9ee41ca0a32cf2fc8e0fbda9466c5bfd0f88b82ca5389e9  /home/u/.vk8s/assets/dev/control-plane.img\n")
   == "6a6e2f93465b898a" : String}

# Another set list (here the node set alone) is another copy.
law native.asset_key_sets:
  {NH.NHost.asset_key("545ea538461003efdc8c81c244531b003f6f26cfccf6c0073b3239fdedf49446  /a/node.img\n") == "455de019e41996cc" : String}

law native.unpack_cmds:
  {NH.NHost.unpack_cmds("/a", NH.NHost.sets(), "0123456789abcdef", "demo") ==
    [ ["sudo", "mkdir", "-p", "-m", "0755", "/var/lib/vk8s/.assets"],
      ["sudo", "rm", "-rf", "--one-file-system", "/var/lib/vk8s/.assets/.stage-0123456789abcdef-demo"],
      ["sudo", "mkdir", "-m", "0755", "/var/lib/vk8s/.assets/.stage-0123456789abcdef-demo"],
      ["sudo", "unsquashfs", "-f", "-n", "-d", "/var/lib/vk8s/.assets/.stage-0123456789abcdef-demo/bin", "/a/node.img"],
      ["sudo", "unsquashfs", "-f", "-n", "-d", "/var/lib/vk8s/.assets/.stage-0123456789abcdef-demo/bin", "/a/control-plane.img"],
      ["sudo", "chmod", "-R", "a-w", "/var/lib/vk8s/.assets/.stage-0123456789abcdef-demo/bin"] ] : List<&2, List<&2, String>>}

law native.publish_cmd:
  {NH.NHost.publish_cmd("0123456789abcdef", "demo") ==
    ["sudo", "mv", "-T", "/var/lib/vk8s/.assets/.stage-0123456789abcdef-demo", "/var/lib/vk8s/.assets/0123456789abcdef"] : +List<String>}

law native.unstage_cmd:
  {NH.NHost.unstage_cmd("0123456789abcdef", "demo") ==
    ["sudo", "rm", "-rf", "--one-file-system", "/var/lib/vk8s/.assets/.stage-0123456789abcdef-demo"] : +List<String>}

law native.has_cmd:
  {NH.NHost.has_cmd("0123456789abcdef") == ["sudo", "test", "-d", "/var/lib/vk8s/.assets/0123456789abcdef/bin"] : +List<String>}

# No unsquashfs per cluster: bin/ links to the shared copy.
law native.prepare_cmds_v2:
  {NH.NHost.prepare_cmds.v2("/var/lib/vk8s/demo", "/a", "/usr/local/bin/vk8s", "0123456789abcdef") ==
    [ ["sudo", "mkdir", "-p", "-m", "0700", "/var/lib/vk8s/demo"],
      ["sudo", "install", "-m", "0755", "/usr/local/bin/vk8s", "/var/lib/vk8s/demo/vk8s"],
      ["sudo", "mkdir", "-p", "/var/lib/vk8s/demo/initramfs"],
      ["sudo", "cpio", "-i", "-d", "--quiet", "--no-absolute-filenames", "-D", "/var/lib/vk8s/demo/initramfs", "-F", "/a/vk8s.cpio",
        "bin/busybox", "etc/vk8s/flannel.yaml"],
      ["sudo", "install", "-m", "0755", "/var/lib/vk8s/demo/initramfs/bin/busybox", "/var/lib/vk8s/demo/busybox"],
      ["sudo", "ln", "-s", "-f", "-n", "/var/lib/vk8s/.assets/0123456789abcdef/bin", "/var/lib/vk8s/demo/bin"] ]
    : List<&2, List<&2, String>>}

law native.link_cmd:
  {NH.NHost.link_cmd("/var/lib/vk8s/demo") == ["sudo", "readlink", "/var/lib/vk8s/demo/bin"] : +List<String>}

law native.users_cmd:
  {NH.NHost.users_cmd("/var/lib/vk8s/.assets/0123456789abcdef/bin") ==
    ["sudo", "find", "/var/lib/vk8s", "-mindepth", "2", "-maxdepth", "2", "-name", "bin", "-lname",
      "/var/lib/vk8s/.assets/0123456789abcdef/bin"] : +List<String>}

law native.shared_key:
  {NH.NHost.shared_key("/var/lib/vk8s/.assets/0123456789abcdef/bin\n") == "0123456789abcdef" : String}

# A link anywhere else, or a key that is not 16 hex digits, is not a
# shared copy (delete removes nothing more).
law native.shared_key_other:
  {NH.NHost.shared_key("/opt/x/0123456789abcdef/bin") == "" : String}

law native.shared_key_dots:
  {NH.NHost.shared_key("/var/lib/vk8s/.assets/../../../../etc/bin") == "" : String}

law native.shared_key_none:
  {NH.NHost.shared_key("") == "" : String}

# The last cluster that links to the copy takes it (and the empty dirs).
law native.release_last:
  {NH.NHost.release_cmds("/var/lib/vk8s/.assets/0123456789abcdef/bin\n", "") ==
    [ ["sudo", "rm", "-rf", "--one-file-system", "/var/lib/vk8s/.assets/0123456789abcdef"],
      ["sudo", "rmdir", "--ignore-fail-on-non-empty", "/var/lib/vk8s/.assets"],
      ["sudo", "rmdir", "--ignore-fail-on-non-empty", "/var/lib/vk8s"] ] : List<&2, List<&2, String>>}

# Another cluster links to it: it stays.
law native.release_kept:
  {NH.NHost.release_cmds("/var/lib/vk8s/.assets/0123456789abcdef/bin\n", "/var/lib/vk8s/second/bin\n") == [] : List<&2, List<&2, String>>}

# A cluster made before v2 (bin is a dir, readlink prints nothing).
law native.release_before_v2:
  {NH.NHost.release_cmds("", "") == [] : List<&2, List<&2, String>>}

# The last cluster's delete leaves nothing, the shared copy included.
law native.delete_leaves_nothing_v2:
  {NH.NHost.leftover(NH.NHost.made.v2("demo", "/home/u/.vk8s/clusters/demo", True{}, "0123456789abcdef"),
     NH.NHost.removes(List.append(&2, List<&2, String>, NH.NHost.delete_cmds("demo", "/home/u/.vk8s/clusters/demo", True{}),
       NH.NHost.release_cmds("/var/lib/vk8s/.assets/0123456789abcdef/bin", "")))) == [] : +List<String>}

# Proposed: optional sets on demand (docs/GOAL.md section 11; vk8s
# design). A native cluster unpacks etcd with the etcd backing store and
# gvisor with --gvisor beside node and control-plane.
law native.sets.v2:
  {[NH.NHost.sets.v2(False{}, False{}), NH.NHost.sets.v2(True{}, False{}), NH.NHost.sets.v2(True{}, True{})]
   == [["node", "control-plane"], ["node", "control-plane", "gvisor"], ["node", "control-plane", "etcd", "gvisor"]]
   : List<&2, +List<String>>}

# Proposed: the shared layer store on a native host node (docs/GOAL.md
# section 11, the native half; vk8s's design, nothing of vcluster's).
# Opt-in (VK8S_LAYERS=1 at create) and only for the cluster that runs
# the host's node. The unit names the host's store; the supervisor then
# puts the Bend snapshotter in front of containerd, as on a VM node
# (plan.with_layers.v5.*), with every path under the cluster's data dir
# and the store read where the host keeps it. A layer's mount under the
# data dir is the cluster's hold on it: the unit's next start and delete
# unmount everything under the data dir (native.reset_script_v2.*,
# native.umount_cmds), so nothing else counts it.

def Laws.native.layers.env() -> N.Env:
  N.Native.env_of("/var/lib/vk8s/demo", "", "/home/u/.vk8s/clusters/demo/share", "", "", "")

def Laws.native.layers.inst() -> NH.Inst:
  NH.Inst{"demo", "/var/lib/vk8s/demo", "/home/u/.vk8s/clusters/demo/share", "10.1.0.4", 10443, False{}, True{}, "amd64",
    "/run/systemd/resolve/resolv.conf"}

law native.layers_on:
  {[NH.NHost.layers_on("1", True{}), NH.NHost.layers_on("1", False{}), NH.NHost.layers_on("", True{}), NH.NHost.layers_on("0", True{})] ==
    [True{}, False{}, False{}, False{}] : List<&2, Bool>}
law native.layers_native:
  {[NH.NHost.layers_native("/home/u/.vk8s/layers", True{}), NH.NHost.layers_native("/home/u/.vk8s/layers", False{}),
    NH.NHost.layers_native("", True{})] == [True{}, False{}, False{}] : List<&2, Bool>}
# The unit without a store is the unit as it was; with one, the same
# text with the store's place before ExecStart.
law native.unit_v2_off:
  for i: NH.Inst
  {NH.NHost.unit.v2(i, "") == NH.NHost.unit(i) : String}
law native.unit_v2_on:
  {NH.NHost.unit.v2(Laws.native.layers.inst(), "/home/u/.vk8s/layers") ==
   "[Unit]\nDescription=vk8s native cluster demo\nWants=network-online.target\nAfter=network-online.target\n\n[Service]\nType=simple\n"
   ++ "Environment=VK8S_DATA=/var/lib/vk8s/demo\nEnvironment=VK8S_SHARE=/home/u/.vk8s/clusters/demo/share\nEnvironment=VK8S_NAME=demo\n"
   ++ "Environment=VK8S_STORE=sqlite\nEnvironment=VK8S_NODE_IP=10.1.0.4\nEnvironment=VK8S_PORT=10443\nEnvironment=VK8S_HOST_NODE=1\n"
   ++ "Environment=VK8S_ARCH=amd64\nEnvironment=VK8S_RESOLV=/run/systemd/resolve/resolv.conf\nEnvironment=VK8S_JOIN_INSTALL=1\n"
   ++ "Environment=VK8S_LAYERS_STORE=/home/u/.vk8s/layers\n"
   ++ "ExecStart=/var/lib/vk8s/demo/vk8s native\nRestart=always\nRestartSec=5s\nKillMode=control-group\nDelegate=yes\n"
   ++ "TimeoutStopSec=90\nLimitNOFILE=1048576\nTasksMax=infinity\n\n[Install]\nWantedBy=multi-user.target\n" : String}
law native.layers_ask:
  {NH.NHost.layers_ask() == "127.0.0.1" : String}
# Every place of the node's is under the data dir; containerd's config
# is where the host node's rules put it.
law native.layers_places:
  {[NH.NHost.layers_mounts("/var/lib/vk8s/demo"), NH.NHost.layers_sock("/var/lib/vk8s/demo"), NH.NHost.layers_config_path("/var/lib/vk8s/demo")] ==
    ["/var/lib/vk8s/demo/node/layers", "/var/lib/vk8s/demo/node/run/vk8s/snapshotter.sock", "/var/lib/vk8s/demo/node/containerd/config.toml"]
    : List<&2, String>}
law native.layers_config_path:
  {NH.NHost.str(NH.NHost.node_rules("/var/lib/vk8s/demo"), P.Plan.containerd_config_path()) == NH.NHost.layers_config_path("/var/lib/vk8s/demo")
    : String}
law native.layers_config:
  {NH.NHost.layers_config("/var/lib/vk8s/demo", "[plugins.'io.containerd.cri.v1.images']\n  snapshotter = \"overlayfs\"\n  x = 1\n") ==
    "[plugins.'io.containerd.cri.v1.images']\n  snapshotter = \"bend\"\n  disable_snapshot_annotations = false\n  x = 1\n"
    ++ "[proxy_plugins]\n  [proxy_plugins.bend]\n    type = \"snapshot\"\n    address = \"/var/lib/vk8s/demo/node/run/vk8s/snapshotter.sock\"\n" : String}
law native.layers_steps:
  {NH.NHost.layers_steps(Laws.native.layers.env(), "/home/u/.vk8s/layers", "snapshotter = \"overlayfs\"\n") ==
    [ P.Run{"/var/lib/vk8s/demo/busybox", ["mkdir", "-p", "/var/lib/vk8s/demo/node/run/vk8s", "/var/lib/vk8s/demo/node/layers",
        "/var/lib/vk8s/demo/containerd/io.containerd.snapshotter.v1.bend"]},
      P.Daemon{"snapshotter", "/proc/self/exe", ["snapshotter", "/var/lib/vk8s/demo/node/run/vk8s/snapshotter.sock",
        "/var/lib/vk8s/demo/containerd/io.containerd.snapshotter.v1.bend", "/home/u/.vk8s/clusters/demo/share/layers.held",
        "/home/u/.vk8s/layers", "/var/lib/vk8s/demo/node/layers"]},
      P.WaitFile{"/var/lib/vk8s/demo/node/run/vk8s/snapshotter.sock", 30000},
      P.Write{"/var/lib/vk8s/demo/node/containerd/config.toml", "snapshotter = \"bend\"\n  disable_snapshot_annotations = false\n"
        ++ "[proxy_plugins]\n  [proxy_plugins.bend]\n    type = \"snapshot\"\n    address = \"/var/lib/vk8s/demo/node/run/vk8s/snapshotter.sock\"\n"} ]
    : +List<P.Step>}
# On: the write of containerd's config becomes those steps, the rest of
# the plan stays in its order. Off: the plan as it is.
law native.with_layers_on:
  {NH.NHost.with_layers(True{}, Laws.native.layers.env(), "/home/u/.vk8s/layers",
     [ P.Log{"a"}, P.Write{"/var/lib/vk8s/demo/node/containerd/config.toml", "snapshotter = \"overlayfs\"\n"},
       P.Write{"/var/lib/vk8s/demo/node/containerd/runsc.toml", "r"}, P.Log{"b"} ]) ==
    List.append(&2, P.Step, Con{P.Log{"a"}, NH.NHost.layers_steps(Laws.native.layers.env(), "/home/u/.vk8s/layers", "snapshotter = \"overlayfs\"\n")},
      [P.Write{"/var/lib/vk8s/demo/node/containerd/runsc.toml", "r"}, P.Log{"b"}]) : +List<P.Step>}
law native.with_layers_off:
  for +e: N.Env
  for +store: String
  for steps: +List<P.Step>
  {NH.NHost.with_layers(False{}, e, store, steps) == steps : +List<P.Step>}
# Delete (and the unit's next start, by the same rule in its reset
# script) unmounts the cluster's layers with everything else under its
# data dir, the last mounted first: a container's root before the layer
# it stands on. Another cluster's mount of the same image is not under
# this data dir and stays.
law native.layers_umount:
  {NH.NHost.umount_cmds(NH.NHost.mounts_under(
     "36 25 7:3 / /var/lib/vk8s/demo/node/layers/aa ro,nosuid - squashfs /dev/loop3 ro\n"
     ++ "37 25 7:4 / /mnt/layers/aa ro,nosuid - squashfs /dev/loop4 ro\n"
     ++ "40 25 0:50 / /var/lib/vk8s/demo/node/run/containerd/io.containerd.runtime.v2.task/k8s.io/c1/rootfs rw - overlay overlay rw\n",
     "/var/lib/vk8s/demo")) ==
    [ ["sudo", "umount", "-l", "/var/lib/vk8s/demo/node/run/containerd/io.containerd.runtime.v2.task/k8s.io/c1/rootfs"],
      ["sudo", "umount", "-l", "/var/lib/vk8s/demo/node/layers/aa"] ] : List<&2, List<&2, String>>}
law native.layers_modprobe:
  {NH.NHost.layers_modprobe() == [["sudo", "modprobe", "-a", "loop", "squashfs"]] : List<&2, List<&2, String>>}
law native.layers_note:
  {NH.NHost.layers_note("/home/u/.vk8s/layers", "/var/lib/vk8s/demo") ==
    "Shared layer store: /home/u/.vk8s/layers (VK8S_LAYERS=1), its layers mounted under /var/lib/vk8s/demo/node/layers" : String}
