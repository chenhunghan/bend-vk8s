import Base
import ./cli.bend as CL
import ./ctr.bend as R

# The bend-vmm LAN wire version of a VM cluster (docs/GOAL.md section 10).
#
# A cluster's VMs talk on one bend-vmm LAN (`--lan DIR,ip=...`, one Unix
# datagram socket per VM). bend-vmm 6951844 (package
# 0x2740e30df705f4fb9b9db637023eca00) changed what crosses that LAN:
# checksum and TSO offload both ways, packets of up to 64 KiB split into
# 2 KiB datagrams by the sending host and joined by the receiving one, MTU
# 2022. Every VM on one LAN must run the same version ("Every VM on one
# LAN runs the same version", bend-vmm's commit and README). A VM that a
# newer vk8s starts beside the VMs of an older one cannot talk to them.
#
# vk8s numbers the wire versions it has shipped:
#   1: no offload (every bend-vmm pin up to 0x7fea7bfa, 90a4b77, MTU 2034;
#      also every cluster.env without LAN_WIRE)
#   2: checksum and TSO offload (bend-vmm 0x2740e30d, 6951844, MTU 2022)
# Raise LanWire.current() with every bend-vmm pin that changes the LAN's
# wire format, and only then.
#
# Create, upgrade and restore write LAN_WIRE=<current> into cluster.env
# (Vk8s.env_file): all of the cluster's VMs start on this binary. A command
# that starts a VM beside running ones (node add, certs rotate-ca, and
# `vk8s vmm` itself, which a guest reset starts again) refuses when the
# recorded version is not this binary's. Every decision is here; the host
# reads the file and acts.

# This binary's LAN wire version (bend-vmm 0x2740e30d, 6951844).
def LanWire.current() -> U32:
  2

# The version of a cluster that records none (made before LAN_WIRE).
def LanWire.legacy() -> U32:
  1

def LanWire.key() -> String:
  "LAN_WIRE"

# cluster.env's line.
def LanWire.env_line(+v: U32) -> String:
  "LAN_WIRE=" ++ U32.show(v) ++ "\n"

def LanWire.recorded.go(empty: Bool, +v: String) -> U32:
  match empty:
    case True{}:
      LanWire.legacy()
    case False{}:
      CL.Cli.num(U32.read(v), 0)

# The version a cluster.env text records: LanWire.legacy() without the
# line, 0 (no version vk8s ships) when its value is not a number.
def LanWire.recorded(+env: String) -> U32:
  +v = R.Ctr.setting(env, LanWire.key())
  LanWire.recorded.go(String.is_empty(v), v)

# What to do with a recorded version: the same as this binary's goes on;
# another one goes on only when every VM of the cluster starts again on
# this binary (create --upgrade), and is refused when a VM would start
# beside running ones.
type LanWire.Act is Data:
  LanWireSame{}
  LanWireRenew{}
  LanWireRefuse{}

def LanWire.decide.go(same: Bool, all: Bool) -> LanWire.Act:
  match same all:
    case True{} _:
      LanWireSame{}
    case False{} True{}:
      LanWireRenew{}
    case False{} False{}:
      LanWireRefuse{}

# `all`: every VM of the cluster stops and starts on this binary.
def LanWire.decide(all: Bool, +rec: U32, +mine: U32) -> LanWire.Act:
  LanWire.decide.go(U32.is_eq(rec, mine), all)

def LanWire.refuses(a: LanWire.Act) -> Bool:
  match a:
    case LanWireSame{}:
      False{}
    case LanWireRenew{}:
      False{}
    case LanWireRefuse{}:
      True{}

# The refusal: what differs and the two ways out.
def LanWire.refusal(+name: String, +rec: U32, +mine: U32) -> String:
  "vCluster " ++ name ++ " runs bend-vmm LAN wire version " ++ U32.show(rec) ++ ", but this vk8s runs version " ++ U32.show(mine)
    ++ ", and a VM of one version cannot talk to the cluster's other VMs. Recreate the cluster (vk8s delete " ++ name
    ++ ", then vk8s create " ++ name ++ "), or stop and restart all of it with this vk8s (vk8s create " ++ name
    ++ " --upgrade keeps the control plane's data)"

# What create --upgrade says when it moves a cluster to this version.
def LanWire.renewal(+name: String, +rec: U32, +mine: U32) -> String:
  "vCluster " ++ name ++ ": bend-vmm LAN wire version " ++ U32.show(rec) ++ " -> " ++ U32.show(mine) ++ " (every VM restarts on this vk8s)"

def LanWire.say(a: LanWire.Act, +name: String, +rec: U32, +mine: U32) -> String:
  match a:
    case LanWireSame{}:
      ""
    case LanWireRenew{}:
      LanWire.renewal(name, rec, mine)
    case LanWireRefuse{}:
      LanWire.refusal(name, rec, mine)

def LanWire.check.go(all: Bool, +name: String, +rec: U32) -> String:
  LanWire.say(LanWire.decide(all, rec, LanWire.current()), name, rec, LanWire.current())

# The message for a cluster.env text ("" when the versions match): a
# refusal when `all` is False (the host stops), a note when it is True.
def LanWire.check(all: Bool, +name: String, +env: String) -> String:
  LanWire.check.go(all, name, LanWire.recorded(env))

# `vk8s vmm`: the cluster.env beside the LAN directory its --lan flag
# names (DIR/lan,ip=... is the cluster DIR's), "" without --lan or for a
# LAN directory vk8s did not make.
def LanWire.lan_head(m: Maybe<&2, String>) -> String:
  match m:
    case None{}:
      ""
    case Some{+s}:
      s

def LanWire.env_path.go(hit: Bool, +d: String) -> String:
  match hit:
    case True{}:
      String.take(d, Nat.sub(String.length(d), 4n)) ++ "/cluster.env"
    case False{}:
      ""

def LanWire.env_path.dir(+d: String) -> String:
  LanWire.env_path.go(String.ends_with(d, "/lan"), d)

def LanWire.env_path.of(m: Maybe<&2, String>) -> String:
  match m:
    case None{}:
      ""
    case Some{+v}:
      LanWire.env_path.dir(LanWire.lan_head(List.head(&2, String, String.split(v, ','))))

def LanWire.env_path(flags: +List<String>) -> String:
  LanWire.env_path.of(CL.Cli.after(flags, "--lan"))

def LanWire.vmm_check.go(empty: Bool, +env: String) -> String:
  match empty:
    case True{}:
      ""
    case False{}:
      LanWire.check(False{}, R.Ctr.setting(env, "NAME"), env)

# The refusal for a VM about to start, from its cluster.env text; "" when
# there is no such file (not a cluster's LAN).
def LanWire.vmm_check(+env: String) -> String:
  LanWire.vmm_check.go(String.is_empty(env), env)
