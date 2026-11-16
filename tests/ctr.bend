import Base
import ../src/cli/ctr.bend as R
import ../src/guest/container.bend as C

# src/cli/ctr.bend, run: the container host's names, argument lists,
# rule cleanup, preflight and config.json as text.

def T.check(+name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name)

def T.argvs(cs: +List<+List<String>>) -> String:
  match cs:
    case Nil{}:
      ""
    case Con{c, t}:
      String.join(c, " ") ++ "\n" ++ T.argvs(t)

def T.rules_text() -> String:
  "-P FORWARD DROP\n"
  ++ "-A FORWARD -o vk8sbr1 -m comment --comment vk8s:demo -j ACCEPT\n"
  ++ "-A FORWARD -i vk8sbr1 -m comment --comment vk8s:demo -j ACCEPT\n"
  ++ "-A FORWARD -i vk8sbr2 -m comment --comment vk8s:demo-2 -j ACCEPT\n"
  ++ "-A FORWARD -j DOCKER-USER\n"

def main() -> IO(Unit):
  do IO<Unit>:
    T.check("control plane at .2, worker 3 at .5", String.eq(R.Ctr.node_ip(7, 0) ++ " " ++ R.Ctr.node_ip(7, 3), "10.10.7.2 10.10.7.5"))
    T.check("interface names fit IFNAMSIZ", Nat.is_le(String.length(R.Ctr.veth(250, 99999)), 15n) && Nat.is_le(String.length(R.Ctr.bridge(250)), 15n))
    T.check("the first free slot", U32.is_eq(R.Ctr.slot(R.Ctr.slots("SLOT=1\nSLOT=3\n")), 2))
    T.check("no slot when all 250 are taken", U32.is_eq(R.Ctr.slot.go(0n, 1, []), 0))
    T.check("cleanup deletes only this cluster's two rules", String.eq(T.argvs(R.Ctr.undo("filter", "vk8s:demo", T.rules_text())),
      "-t filter -D FORWARD -o vk8sbr1 -m comment --comment vk8s:demo -j ACCEPT\n-t filter -D FORWARD -i vk8sbr1 -m comment --comment vk8s:demo -j ACCEPT\n"))
    T.check("cleanup of a host without rules is empty", String.eq(T.argvs(R.Ctr.undo("nat", "vk8s:demo", "-P POSTROUTING ACCEPT\n")), ""))
    T.check("the bridge rules masquerade the LAN", String.contains(T.argvs(R.Ctr.rules("demo", 4)), "-s 10.10.4.0/24 ! -o vk8sbr4"))
    T.check("a ready host passes the preflight", String.is_empty(R.Ctr.preflight_message(True{}, True{}, [], [], R.Ctr.missing_controllers("cpu memory pids io"))))
    T.check("the preflight names a missing controller", String.contains(R.Ctr.preflight_message(True{}, True{}, [], [], R.Ctr.missing_controllers("cpu io")), "memory, pids"))
    T.check("root from /proc/self/status", R.Ctr.root("Uid:\t0\t0\t0\t0\nGid:\t0\t0\t0\t0\n"))
    T.check("a user is not root", Bool.not(R.Ctr.root("Uid:\t1001\t1001\t1001\t1001\n")))
    T.check("the node's config.json joins its network namespace",
      String.contains(R.Ctr.json(C.Spec{"demo", "demo", "/r", "/d", "/s", "/a", R.Ctr.env_cp("demo", 1, 6443, True{})}, "/run/netns/vk8s-demo-0"),
        "\"path\":\"/run/netns/vk8s-demo-0\""))
    T.check("the node's config.json is the control plane's environment",
      String.contains(R.Ctr.json(C.Spec{"demo", "demo", "/r", "/d", "/s", "/a", R.Ctr.env_cp("demo", 1, 6443, True{})}, "/n"),
        "VK8S_STORE=etcd"))
    T.check("runc state: paused", String.eq(R.Ctr.status("{\n  \"id\": \"x\",\n  \"status\": \"paused\",\n  \"pid\": 1\n}"), "paused"))
    T.check("the assets overlay: the sets over the base disk",
      String.eq(String.join(R.Ctr.mount_overlay(R.Ctr.lowers("/c", ["node", "control-plane"]), "/c/assets"), " "),
        "-t overlay -o ro,lowerdir=/c/sets/node:/c/sets/control-plane:/c/base overlay /c/assets"))
    T.check("a container cluster mounts node and control-plane, and images when built",
      String.eq(String.join(R.Ctr.sets(False{}), " ") ++ "|" ++ String.join(R.Ctr.sets(True{}), " "), "node control-plane|node control-plane images"))
    T.check("delete unmounts the overlay first, the base disk last",
      String.eq(String.join(R.Ctr.asset_mounts("/c"), " "), "/c/assets /c/sets/node /c/sets/control-plane /c/sets/images /c/base"))
    T.check("the cluster's settings", String.eq(R.Ctr.setting("BACKEND=container\nSLOT=9\n", "SLOT"), "9"))
    T.check("an amd64 node names its arch for PID 1's image import",
      String.eq(String.join(R.Ctr.arch_env("amd64", ["VK8S_NAME=demo"]), " ") ++ "|" ++ String.join(R.Ctr.arch_env("arm64", ["VK8S_NAME=demo"]), " "),
        "VK8S_NAME=demo VK8S_ARCH=amd64|VK8S_NAME=demo"))
