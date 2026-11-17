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
