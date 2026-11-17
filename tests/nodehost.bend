import Base
import ../src/cli/nodehost.bend as N
import ../src/cli/ctr.bend as R
import ../src/guest/plan.bend as P

# src/cli/nodehost.bend, run: the node host's boot plan and the steps of
# each request, as text.

def T.check(+name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name)

def T.step(s: P.Step) -> String:
  match s:
    case P.Mount{fs, src, dst, opts}:
      "mount " ++ fs ++ " " ++ src ++ " " ++ dst ++ " " ++ opts
    case P.Write{path, text}:
      "write " ++ path ++ " " ++ text
    case P.Run{prog, args}:
      "run " ++ prog ++ " " ++ String.join(args, " ")
    case P.Daemon{name, prog, args}:
      "daemon " ++ name
    case P.Spawn{name, prog, args}:
      "spawn " ++ name ++ " " ++ prog ++ " " ++ String.join(args, " ")
    case P.WaitTcp{host, port, ms}:
      "waittcp " ++ host
    case P.Stop{names}:
      "stop"
    case P.WaitFile{path, ms}:
      "waitfile " ++ path
    case P.Modules{path}:
      "modules " ++ path
    case P.Log{text}:
      "log " ++ text

def T.steps(ss: +List<P.Step>) -> String:
  match ss:
    case Nil{}:
      ""
    case Con{s, t}:
      T.step(s) ++ "\n" ++ T.steps(t)

def T.tools() -> N.Tools:
  N.Tools{"/usr/bin/ip", "/usr/bin/cpio", "/usr/sbin/iptables", "/var/lib/vcluster/bin/runc"}

def main() -> IO(Unit):
  do IO<Unit>:
    +boot : String = T.steps(N.Nh.boot(["node", "control-plane", "images"]))
    T.check("the node host loads its modules", String.contains(boot, "modules /etc/vk8s/modules\n"))
    T.check("the node host mounts its data disk and sets",
      String.contains(boot, "mount ext4 /dev/vdb /var/lib/vcluster rw\n") && String.contains(boot, "mount squashfs /dev/vdc /sets/node ro\n"))
    T.check("the node host mounts its share", String.contains(boot, "mount 9p share /var/lib/vk8s-host trans=virtio,version=9p2000.L\n"))
    T.check("the nodes' assets: the sets over the base disk",
      String.contains(boot, "mount overlay overlay /nodehost/assets ro,lowerdir=/sets/node:/sets/control-plane:/sets/images:/assets\n"))
    T.check("the node host says it is ready last", String.contains(boot, "write /var/lib/vk8s-host/ready ok\n\nlog vk8s: node host ready\n"))
    T.check("the node host starts no daemon", Bool.not(String.contains(boot, "daemon ")))
    +up : String = T.steps(N.Nh.up(T.tools(), "demo", 2, True{}, ""))
    T.check("up makes the bridge", String.contains(up, "run /usr/bin/ip link add vk8sbr2 type bridge\n"))
    T.check("up forwards the API port", String.contains(up, "run /usr/sbin/iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 16402"))
    T.check("up masquerades the LAN", String.contains(up, "-s 10.10.2.0/24 ! -o vk8sbr2"))
    T.check("up delegates the cgroups", String.contains(up, "run /bin/busybox mkdir -p /sys/fs/cgroup/vk8s/demo\n"))
    T.check("up unpacks the control plane's root",
      String.contains(up, "run /usr/bin/cpio -idmu --quiet --no-absolute-filenames -D /var/lib/vcluster/nodehost/clusters/demo/bundle/rootfs -F /var/lib/vk8s-host/vk8s.cpio\n"))
    T.check("up gives the control plane its address and store",
      String.contains(up, "VK8S_NODE_IP=10.10.2.2") && String.contains(up, "VK8S_STORE=etcd"))
    T.check("the node binds the node host's assets and its share",
      String.contains(up, "/nodehost/assets") && String.contains(up, "/var/lib/vk8s-host/clusters/demo/share"))
    T.check("up starts the control plane with runc last",
      String.ends_with(up, "spawn vk8s-demo-0 /var/lib/vcluster/bin/runc --root /run/vk8s/runc run -d --bundle /var/lib/vcluster/nodehost/clusters/demo/bundle vk8s-demo-0\n"))
    +join : String = T.steps(N.Nh.join(T.tools(), "demo", 2, 1, "abcdef.0123456789abcdef", "amd64"))
    T.check("join starts the worker in its namespace", String.contains(join, "run /usr/bin/ip netns add vk8s-demo-1\n"))
    T.check("join gives the worker its token and arch", String.contains(join, "VK8S_TOKEN=abcdef.0123456789abcdef") && String.contains(join, "VK8S_ARCH=amd64"))
    T.check("join makes no bridge", Bool.not(String.contains(join, "type bridge")))
    +post : String = T.steps(N.Nh.stop_post("/usr/bin/ip", "/r", "demo", 1))
    T.check("a stopped node's container and namespace go",
      String.contains(post, "run /r --root /run/vk8s/runc delete -f vk8s-demo-1\n") && String.contains(post, "run /usr/bin/ip netns del vk8s-demo-1\n"))
    +down : String = T.steps(N.Nh.down("/usr/bin/ip", "/usr/sbin/iptables", "demo", 2))
    T.check("down deletes the API forward", String.contains(down, "-t nat -D PREROUTING -i eth0 -p tcp --dport 16402"))
    T.check("down deletes the bridge and the cluster's directories",
      String.contains(down, "run /usr/bin/ip link del vk8sbr2\n") && String.contains(down, "rm -rf /var/lib/vcluster/nodehost/clusters/demo /var/lib/vk8s-host/clusters/demo\n"))
    T.check("up isolates the cluster's bridge from the others", String.contains(up, "-t filter -I FORWARD -i vk8sbr2 -o vk8sbr+ -m comment --comment vk8s:demo -j DROP\n"))
    T.check("down deletes the isolation rules", String.contains(down, "-t filter -D FORWARD -i vk8sbr+ -o vk8sbr2 -m comment --comment vk8s:demo -j DROP\n"))
    T.check("pause takes every node", String.eq(T.steps(N.Nh.freeze("/r", "pause", "demo", [0, 1])),
      "run /r --root /run/vk8s/runc pause vk8s-demo-0\nrun /r --root /run/vk8s/runc pause vk8s-demo-1\n"))
    T.check("a request round trip", String.eq(N.Nh.req_down("demo", 2, N.Nh.ws("1,3")), "down demo 2 1,3"))
    T.check("the tool candidates", String.eq(String.join(N.Nh.candidates("ip"), " "), "/usr/bin/ip /usr/sbin/ip /bin/ip /sbin/ip"))
