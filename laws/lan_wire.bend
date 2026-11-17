import Base
import ../src/cli/lan_wire.bend as W

# Spec for src/cli/lan_wire.bend: the bend-vmm LAN wire version a cluster
# records, and the guard on commands that start a VM beside running ones.

# Proposed: vk8s policy (the user's brief of 2026-11-17), not vcluster's:
# vcluster has no VM LAN. bend-vmm 6951844 (checksum and TSO offload, MTU
# 2022) is wire version 2; every earlier pin, and every cluster.env
# without LAN_WIRE, is version 1.
law lan_wire.current:
  {W.LanWire.current() == 2 : U32}

law lan_wire.env_line:
  {W.LanWire.env_line(2) == "LAN_WIRE=2\n" : String}

law lan_wire.recorded.missing:
  {W.LanWire.recorded("NAME=demo\nPORT=10001\nKUBERNETES=v1.36.6\nCREATED=1763390000\n") == 1 : U32}

law lan_wire.recorded.v2:
  {W.LanWire.recorded("NAME=demo\nKUBERNETES=v1.36.6\nLAN_WIRE=2\nCREATED=1763390000\n") == 2 : U32}

law lan_wire.recorded.bad:
  {W.LanWire.recorded("NAME=demo\nLAN_WIRE=x\n") == 0 : U32}

law lan_wire.decide.same:
  {W.LanWire.decide(False{}, 2, 2) == W.LanWireSame{} : W.LanWire.Act}

law lan_wire.decide.older_refused:
  {W.LanWire.decide(False{}, 1, 2) == W.LanWireRefuse{} : W.LanWire.Act}

law lan_wire.decide.newer_refused:
  {W.LanWire.decide(False{}, 3, 2) == W.LanWireRefuse{} : W.LanWire.Act}

law lan_wire.decide.upgrade_renews:
  {W.LanWire.decide(True{}, 1, 2) == W.LanWireRenew{} : W.LanWire.Act}

# When every VM restarts on this binary, no version is refused.
law lan_wire.decide.all_never_refuses:
  for +rec: U32
  for +mine: U32
  {W.LanWire.refuses(W.LanWire.decide(True{}, rec, mine)) == False{} : Bool}

law lan_wire.check.same:
  {W.LanWire.check(False{}, "demo", "NAME=demo\nLAN_WIRE=2\n") == "" : String}

law lan_wire.check.legacy_refused:
  {String.is_empty(W.LanWire.check(False{}, "demo", "NAME=demo\nPORT=10001\n")) == False{} : Bool}

law lan_wire.env_path.worker:
  {W.LanWire.env_path(["--mem", "2048", "--lan", "/Users/u/.vk8s/clusters/demo/lan,ip=10.10.0.3/24", "--net"]) == "/Users/u/.vk8s/clusters/demo/cluster.env" : String}

law lan_wire.env_path.none:
  {W.LanWire.env_path(["--mem", "2048", "--net"]) == "" : String}

law lan_wire.vmm_check.no_file:
  {W.LanWire.vmm_check("") == "" : String}

law lan_wire.vmm_check.same:
  {W.LanWire.vmm_check("NAME=demo\nLAN_WIRE=2\n") == "" : String}
