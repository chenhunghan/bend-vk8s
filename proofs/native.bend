import Base
import ../laws/native.bend as L
import ../src/standalone/native.bend as N
import ../src/guest/plan.bend as P
import ../src/guest/supervise.bend as S

# Proofs of laws/native.bend: `def L.<law>` for each law.

def L.native.env_defaults():
  {==}

def L.native.env_given():
  {==}

def L.native.env_ok():
  {==}

def L.native.env_ok.empty():
  {==}

def L.native.env_ok.root():
  {==}

def L.native.env_ok.relative():
  {==}

def L.native.env_ok.space():
  {==}

def L.native.env_ok.quote():
  {==}

def L.native.cfg():
  {==}

def L.native.relocate_paths():
  {==}

def L.native.relocate_bin():
  {==}

def L.native.relocate_write():
  {==}

def L.native.relocate_length(env, ss):
  match ss:
    case Nil{}:
      {==}
    case Con{s, rest}:
      %L.native.relocate_length(env, rest) : {1n+List.length(&2, P.Step, N.Native.relocate(env, rest)) == 1n+_ : Nat}
      {==}

def L.native.busybox_path():
  {==}

def L.native.no_vm_busybox():
  {==}

def L.native.strips_machine_layer():
  {==}

# A step that strip keeps is no machine step, so the count stays 0.
law Nv.strip_go:
  for m: Bool
  for s: P.Step
  for rest: +List<P.Step>
  for hm: {N.Native.machine(s) == m : Bool}
  for hr: {N.Native.machine_count(rest) == 0n : Nat}
  {N.Native.machine_count(N.Native.strip.go(m, s, rest)) == 0n : Nat}

def Nv.strip_go(m, s, rest, hm, hr):
  match m:
    case True{}:
      hr
    case False{}:
      %Equal.sym(Bool, N.Native.machine(s), False{}, hm) : {N.Native.count.go(_, N.Native.machine_count(rest)) == 0n : Nat}
      hr

law Nv.strip_clean:
  for ss: +List<P.Step>
  {N.Native.machine_count(N.Native.strip(ss)) == 0n : Nat}

def Nv.strip_clean(ss):
  match ss:
    case Nil{}:
      {==}
    case Con{+s, +t}:
      Nv.strip_go(N.Native.machine(s), s, N.Native.strip(t), {==}, Nv.strip_clean(t))

def L.native.no_machine_steps(env, c):
  Nv.strip_clean(N.Native.relocate(env, N.Native.plan(c)))

def L.native.smoke_no_machine_steps(env, c):
  Nv.strip_clean(N.Native.relocate(env, N.Native.smoke_plan(c)))

def L.native.keeps_pki_steps():
  {==}

def L.native.control_plane_only():
  {==}

def L.native.control_plane_only.etcd():
  {==}

def L.native.cluster_layer():
  {==}

def L.native.join_server():
  {==}

def L.native.smoke_daemons():
  {==}

def L.native.dirname():
  {==}

def L.native.dirname.top():
  {==}

def L.native.stop_pids():
  {==}

def L.native.stop_names():
  {==}

# A pid that safe_pids keeps is safe, so the list stays all safe.
law Nv.keep_go:
  for b: Bool
  for p: U32
  for rest: List<&2, U32>
  for hb: {N.Native.safe(p) == b : Bool}
  for hr: {N.Native.all_safe(rest) == True{} : Bool}
  {N.Native.all_safe(N.Native.keep.go(b, p, rest)) == True{} : Bool}

def Nv.keep_go(b, p, rest, hb, hr):
  match b:
    case True{}:
      %Equal.sym(Bool, N.Native.safe(p), True{}, hb) : {Bool.and(_, N.Native.all_safe(rest)) == True{} : Bool}
      %Equal.sym(Bool, N.Native.all_safe(rest), True{}, hr) : {Bool.and(True{}, _) == True{} : Bool}
      {==}
    case False{}:
      hr

law Nv.safe_pids_ok:
  for ps: List<&2, U32>
  {N.Native.all_safe(N.Native.safe_pids(ps)) == True{} : Bool}

def Nv.safe_pids_ok(ps):
  match ps:
    case Nil{}:
      {==}
    case Con{+p, +t}:
      Nv.keep_go(N.Native.safe(p), p, N.Native.safe_pids(t), {==}, Nv.safe_pids_ok(t))

def L.native.shutdown_no_global_kill(svcs):
  Nv.safe_pids_ok(S.Sup.stop_order(svcs))
