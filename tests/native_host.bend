import Base
import ../src/standalone/native_host.bend as NH
import ../src/standalone/native.bend as N
import ../src/standalone/join.bend as JN
import ../src/guest/plan.bend as P

# Tests for src/standalone/native_host.bend: the native plan of a cluster
# on a host, run. With the host node it runs containerd and the kubelet
# beside the control plane; with or without, no VM path, no VM port and no
# fixed host path may survive, so several clusters fit on one host.

def T.check(+name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name)

def T.env() -> N.Env:
  N.Native.env_of("/var/lib/vk8s/demo", "", "/home/u/.vk8s/clusters/demo/share", "", "", "")

def T.opts(node: Bool) -> NH.Opts:
  NH.Opts{11000, node, "amd64", "/run/systemd/resolve/resolv.conf"}

def T.step(s: P.Step) -> String:
  match s:
    case P.Mount{fs, src, dst, opts}:
      "mount " ++ fs ++ " " ++ src ++ " " ++ dst ++ " " ++ opts
    case P.Write{path, text}:
      "write " ++ path ++ " " ++ text
    case P.Run{prog, args}:
      "run " ++ prog ++ " " ++ String.join(args, " ")
    case P.Daemon{n, prog, args}:
      "daemon " ++ n ++ " " ++ prog ++ " " ++ String.join(args, " ")
    case P.Spawn{n, prog, args}:
      "spawn " ++ n ++ " " ++ prog ++ " " ++ String.join(args, " ")
    case P.WaitTcp{host, port, ms}:
      "waittcp " ++ host ++ ":" ++ U32.show(port)
    case P.Stop{names}:
      "stop " ++ String.join(names, " ")
    case P.WaitFile{path, ms}:
      "waitfile " ++ path
    case P.Modules{path}:
      "modules " ++ path
    case P.Log{t}:
      "log " ++ t

def T.steps(ss: +List<P.Step>) -> +List<String>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      Con{T.step(s), T.steps(t)}

def T.plan(node: Bool, etcd: Bool) -> +List<P.Step>:
  NH.NHost.boot(T.env(), T.opts(node), NH.NHost.cfg("demo", "10.1.0.4", 11000, etcd))

def T.text(node: Bool, etcd: Bool) -> String:
  String.join(T.steps(T.plan(node, etcd)), "\n")

def T.any(xs: +List<String>, +t: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{x, rest}:
      Bool.or(String.contains(t, x), T.any(rest, t))

# Nothing of the VM's: its paths, its ports, its NAT's cache address, and
# no host path another cluster or the distribution owns.
def T.vm_left() -> +List<String>:
  [ "/var/lib/vcluster", "/var/lib/vk8s-host", "/bin/busybox", "/etc/vk8s", "/usr/bin/vk8s-guest",
    "6443", "8443", "2379", "2380", "2381", "10.0.2.2",
    "/run/containerd", "/etc/containerd", "/etc/kubernetes", "/opt/cni/bin", "/etc/cni/net.d", "linux/arm64" ]

# Which VM string a step line still holds (the first two words of the
# line name the step), so a failing check says what is left.
def T.where.hit(hit: Bool, +x: String, +line: String) -> String:
  match hit:
    case True{}:
      "  left " ++ x ++ " in: " ++ NH.NHost.at(String.split(line, ' '), 0n) ++ " " ++ NH.NHost.at(String.split(line, ' '), 1n) ++ "\n"
    case False{}:
      ""

def T.where(xs: +List<String>, +line: String) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, rest}:
      T.where.hit(String.contains(line, x), x, line) ++ T.where(rest, line)

def T.left(+xs: +List<String>, ls: +List<String>) -> String:
  match ls:
    case Nil{}:
      ""
    case Con{l, t}:
      T.where(xs, l) ++ T.left(xs, t)

def T.diag.go(empty: Bool, +s: String) -> IO(Unit):
  match empty:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.write(s)

def T.diag(node: Bool, etcd: Bool) -> IO(Unit):
  T.diag.go(String.is_empty(T.left(T.vm_left(), T.steps(T.plan(node, etcd)))), T.left(T.vm_left(), T.steps(T.plan(node, etcd))))

def T.names(node: Bool) -> String:
  String.join(N.Native.daemon_names(T.plan(node, False{})), " ")

def T.script() -> String:
  JN.Join.install(JN.Join.script(JN.Script{"10.1.0.4:20443", "abcdef.0123456789abcdef", "sha256:00", "worker"}))

def main() -> IO(Unit):
  do IO<Unit>:
    T.check("host node: nothing of the VM's, no fixed port or host path left", Bool.not(T.any(T.vm_left(), T.text(True{}, False{}))))
    T.check("host node, etcd: nothing of the VM's left", Bool.not(T.any(T.vm_left(), T.text(True{}, True{}))))
    T.check("control plane only: nothing of the VM's left", Bool.not(T.any(T.vm_left(), T.text(False{}, False{}))))
    T.diag(True{}, False{})
    T.diag(True{}, True{})
    T.check("host node: no machine step", Nat.is_eq(N.Native.machine_count(T.plan(True{}, False{})), 0n))
    T.check("host node: the control plane, containerd and the kubelet",
      String.eq(T.names(True{}), "kine kube-apiserver kube-controller-manager kube-scheduler join-server containerd kubelet"))
    T.check("control plane only: no containerd, no kubelet",
      String.eq(T.names(False{}), "kine kube-apiserver kube-controller-manager kube-scheduler join-server"))
    T.check("the API server on the cluster's port",
      String.contains(T.text(True{}, False{}), "--secure-port=11000") && String.contains(T.text(True{}, False{}), "waittcp 127.0.0.1:11000"))
    T.check("the join server on the cluster's join port, against its API server",
      String.contains(T.text(True{}, False{}), " --port=21000 --api-port=11000")
        && String.contains(T.text(True{}, False{}), "--endpoint=10.1.0.4:11000"))
    T.check("the controller manager and the scheduler serve no fixed port",
      String.contains(T.text(True{}, False{}), " --secure-port=0"))
    T.check("etcd on the cluster's ports",
      String.contains(T.text(True{}, True{}), "--listen-client-urls=https://127.0.0.1:24000")
        && String.contains(T.text(True{}, True{}), "--listen-peer-urls=https://127.0.0.1:27000")
        && String.contains(T.text(True{}, True{}), "waittcp 127.0.0.1:24000"))
    T.check("kine's socket and metrics are the cluster's",
      String.contains(T.text(True{}, False{}), "--listen-address=unix:///var/lib/vk8s/demo/kine.sock")
        && String.contains(T.text(True{}, False{}), "--metrics-bind-address=127.0.0.1:30000"))
    T.check("containerd under the data dir, its pods' netns there too, no NRI socket",
      String.contains(T.text(True{}, False{}), "state = \"/var/lib/vk8s/demo/node/run/containerd\"")
        && String.contains(T.text(True{}, False{}), "netns_mounts_under_state_dir = true")
        && String.contains(T.text(True{}, False{}), "[plugins.'io.containerd.nri.v1.nri']\n  disable = true"))
    T.check("the CNI dirs are vk8s's",
      String.contains(T.text(True{}, False{}), "bin_dirs = [\"/opt/vk8s/cni/bin\"]")
        && String.contains(T.text(True{}, False{}), "conf_dir = \"/opt/vk8s/cni/net.d\""))
    T.check("the kubelet: the host's resolver, the pod logs and static pods under the data dir",
      String.contains(T.text(True{}, False{}), "resolvConf: /run/systemd/resolve/resolv.conf\n")
        && String.contains(T.text(True{}, False{}), "podLogsDir: /var/lib/vk8s/demo/pod-logs\n")
        && String.contains(T.text(True{}, False{}), "staticPodPath: /var/lib/vk8s/demo/node/kubernetes/manifests"))
    T.check("the cluster's kubeadm config keeps the nodes' resolver",
      String.contains(T.text(True{}, False{}), "resolvConf: /etc/resolv.conf\n"))
    T.check("the node is reset before containerd starts",
      String.contains(T.text(True{}, False{}), "run /var/lib/vk8s/demo/busybox sh -c k=/sys/fs/cgroup/kubepods;"))
    T.check("images import for the host's platform",
      String.contains(T.text(True{}, False{}), "--platform linux/amd64"))
    T.check("the image cache at the host's loopback",
      String.contains(T.text(True{}, False{}), "[host.\"http://127.0.0.1:15001\"]"))
    T.check("the kubeconfig names the cluster's port",
      String.contains(T.text(True{}, False{}), "s#https://10.1.0.4:11000#https://127.0.0.1:11000#"))
    T.check("the default endpoints name the cluster's port",
      String.contains(T.text(True{}, False{}), "\"port\":11000"))
    T.check("the plan ends with the published kubeconfig",
      String.ends_with(T.text(True{}, False{}), "log vk8s: kubeconfig published"))
    T.check("install script: a POSIX sh script that installs, then joins",
      String.starts_with(T.script(), "#!/bin/sh\n") && String.contains(T.script(), "systemctl enable --now vk8s-containerd.service\n")
        && String.ends_with(T.script(), "--ignore-preflight-errors=all\n"))
    T.check("install script: --reset-only removes what it installed",
      String.contains(T.script(), "  rm -f /etc/systemd/system/kubelet.service /etc/systemd/system/vk8s-containerd.service\n"))
