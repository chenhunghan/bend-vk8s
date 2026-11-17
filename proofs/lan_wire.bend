import Base
import ../laws/lan_wire.bend as L
import ../src/cli/lan_wire.bend as W

# Proofs of laws/lan_wire.bend: `def L.<law>` for each law.

def L.lan_wire.current():
  {==}

def L.lan_wire.env_line():
  {==}

def L.lan_wire.recorded.missing():
  {==}

def L.lan_wire.recorded.v2():
  {==}

def L.lan_wire.recorded.bad():
  {==}

def L.lan_wire.decide.same():
  {==}

def L.lan_wire.decide.older_refused():
  {==}

def L.lan_wire.decide.newer_refused():
  {==}

def L.lan_wire.decide.upgrade_renews():
  {==}

# Whatever U32.is_eq says, a whole restart is Same or Renew.
def lan_wire.all(same: Bool) -> {W.LanWire.refuses(W.LanWire.decide.go(same, True{})) == False{} : Bool}:
  match same:
    case True{}:
      {==}
    case False{}:
      {==}

def L.lan_wire.decide.all_never_refuses(rec, mine):
  lan_wire.all(U32.is_eq(rec, mine))

def L.lan_wire.check.same():
  {==}

def L.lan_wire.check.legacy_refused():
  {==}

def L.lan_wire.env_path.worker():
  {==}

def L.lan_wire.env_path.none():
  {==}

def L.lan_wire.vmm_check.no_file():
  {==}

def L.lan_wire.vmm_check.same():
  {==}
