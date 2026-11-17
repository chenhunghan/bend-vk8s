import Base
import ../src/cli/lan_wire.bend as W

# The bend-vmm LAN wire guard (src/cli/lan_wire.bend): what a cluster.env
# records, the decision, and the messages the host prints.

def T.check(+name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name)

def main() -> IO(Unit):
  do IO<Unit>:
    T.check("current is 2", U32.is_eq(W.LanWire.current(), 2))
    T.check("env line", String.eq(W.LanWire.env_line(W.LanWire.current()), "LAN_WIRE=2\n"))
    T.check("no field is version 1", U32.is_eq(W.LanWire.recorded("NAME=a\nPORT=10001\n"), 1))
    T.check("empty file is version 1", U32.is_eq(W.LanWire.recorded(""), 1))
    T.check("recorded 2", U32.is_eq(W.LanWire.recorded("NAME=a\nLAN_WIRE=2\n"), 2))
    T.check("recorded with spaces", U32.is_eq(W.LanWire.recorded("LAN_WIRE= 2 \n"), 2))
    T.check("not a number is 0", U32.is_eq(W.LanWire.recorded("LAN_WIRE=two\n"), 0))
    T.check("same version passes", String.is_empty(W.LanWire.check(False{}, "a", "NAME=a\nLAN_WIRE=2\n")))
    T.check("old cluster refused", String.contains(W.LanWire.check(False{}, "a", "NAME=a\n"), "LAN wire version 1, but this vk8s runs version 2"))
    T.check("refusal says recreate", String.contains(W.LanWire.check(False{}, "a", "NAME=a\n"), "vk8s delete a, then vk8s create a"))
    T.check("refusal says upgrade", String.contains(W.LanWire.check(False{}, "a", "NAME=a\n"), "vk8s create a --upgrade"))
    T.check("newer cluster refused", String.contains(W.LanWire.check(False{}, "a", "LAN_WIRE=3\n"), "LAN wire version 3"))
    T.check("upgrade notes the change", String.contains(W.LanWire.check(True{}, "a", "NAME=a\n"), "LAN wire version 1 -> 2"))
    T.check("upgrade on same version is quiet", String.is_empty(W.LanWire.check(True{}, "a", "LAN_WIRE=2\n")))
    T.check("env path of a worker", String.eq(W.LanWire.env_path(["--lan", "/h/.vk8s/clusters/a/lan,ip=10.10.0.3/24"]), "/h/.vk8s/clusters/a/cluster.env"))
    T.check("env path of a control plane", String.eq(W.LanWire.env_path(["--cpus", "2", "--lan", "/h/c/a/lan,ip=10.10.0.2/24", "--net"]), "/h/c/a/cluster.env"))
    T.check("no --lan, no env path", String.is_empty(W.LanWire.env_path(["--cpus", "2"])))
    T.check("another LAN dir, no env path", String.is_empty(W.LanWire.env_path(["--lan", "/tmp/mylan,ip=10.0.0.2/24"])))
    T.check("vmm without cluster.env starts", String.is_empty(W.LanWire.vmm_check("")))
    T.check("vmm of a legacy cluster refused", String.contains(W.LanWire.vmm_check("NAME=old\nPORT=10001\n"), "vCluster old runs bend-vmm LAN wire version 1"))
    T.check("vmm of a current cluster starts", String.is_empty(W.LanWire.vmm_check("NAME=a\nLAN_WIRE=2\n")))
