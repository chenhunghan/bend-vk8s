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

# no_vm_busybox in one evaluation ran the verdict kernel out of fuel: it
# relocated every argument and path of the plan and checked every step for
# the machine layer. Two general lemmas leave only the relocated programs
# to compute: strip drops programs, never adds one (Nv.strip_progs), and
# relocation maps the program list (Nv.progs_relocate).

# Kit: booleans (copied from proofs/meta.bend, prefix Nv.).

def Nv.bdisc(b: Bool) -> Type:
  match b:
    case False{}:
      Empty
    case True{}:
      Unit

def Nv.tf_absurd(-A: Type, e: {True{} == False{} : Bool}) -> A:
  Empty.absurd(A, (%e : Nv.bdisc(_); Unit{}))

law Nv.or_ff:
  for a: Bool
  for b: Bool
  for ha: {a == False{} : Bool}
  for hb: {b == False{} : Bool}
  {Bool.or(a, b) == False{} : Bool}

def Nv.or_ff(a, b, ha, hb):
  %Equal.sym(Bool, a, False{}, ha) : {Bool.or(_, b) == False{} : Bool}
  hb

law Nv.or_fl:
  for a: Bool
  for b: Bool
  for h: {Bool.or(a, b) == False{} : Bool}
  {a == False{} : Bool}

def Nv.or_fl(a, b, h):
  match a:
    case False{}:
      {==}
    case True{}:
      h

law Nv.or_fr:
  for a: Bool
  for b: Bool
  for h: {Bool.or(a, b) == False{} : Bool}
  {b == False{} : Bool}

def Nv.or_fr(a, b, h):
  match a:
    case False{}:
      h
    case True{}:
      Nv.tf_absurd({b == False{} : Bool}, h)

law Nv.or_assoc:
  for c: Bool
  for p: Bool
  for q: Bool
  {Bool.or(c, Bool.or(p, q)) == Bool.or(Bool.or(c, p), q) : Bool}

def Nv.or_assoc(c, p, q):
  match c:
    case True{}:
      {==}
    case False{}:
      {==}

# Membership in an appended list.
law Nv.mem_app:
  for +a: +List<String>
  for +b: +List<String>
  for +x: String
  {S.Sup.member(List.append(&2, String, a, b), x) == Bool.or(S.Sup.member(a, x), S.Sup.member(b, x)) : Bool}

def Nv.mem_app(a, b, x):
  match a:
    case Nil{}:
      {==}
    case Con{+y, +t}:
      %Equal.sym(Bool, S.Sup.member(List.append(&2, String, t, b), x), Bool.or(S.Sup.member(t, x), S.Sup.member(b, x)), Nv.mem_app(t, b, x)) :
        {Bool.or(String.eq(y, x), _) == Bool.or(Bool.or(String.eq(y, x), S.Sup.member(t, x)), S.Sup.member(b, x)) : Bool}
      Nv.or_assoc(String.eq(y, x), S.Sup.member(t, x), S.Sup.member(b, x))

law Nv.mem_app_ff:
  for +a: +List<String>
  for +b: +List<String>
  for +x: String
  for ha: {S.Sup.member(a, x) == False{} : Bool}
  for hb: {S.Sup.member(b, x) == False{} : Bool}
  {S.Sup.member(List.append(&2, String, a, b), x) == False{} : Bool}

def Nv.mem_app_ff(a, b, x, ha, hb):
  %Equal.sym(Bool, S.Sup.member(List.append(&2, String, a, b), x), Bool.or(S.Sup.member(a, x), S.Sup.member(b, x)), Nv.mem_app(a, b, x)) :
    {_ == False{} : Bool}
  Nv.or_ff(S.Sup.member(a, x), S.Sup.member(b, x), ha, hb)

law Nv.mem_app_fl:
  for +a: +List<String>
  for +b: +List<String>
  for +x: String
  for h: {S.Sup.member(List.append(&2, String, a, b), x) == False{} : Bool}
  {S.Sup.member(a, x) == False{} : Bool}

def Nv.mem_app_fl(a, b, x, h):
  Nv.or_fl(S.Sup.member(a, x), S.Sup.member(b, x), (%Nv.mem_app(a, b, x) : {_ == False{} : Bool}; h))

law Nv.mem_app_fr:
  for +a: +List<String>
  for +b: +List<String>
  for +x: String
  for h: {S.Sup.member(List.append(&2, String, a, b), x) == False{} : Bool}
  {S.Sup.member(b, x) == False{} : Bool}

def Nv.mem_app_fr(a, b, x, h):
  Nv.or_fr(S.Sup.member(a, x), S.Sup.member(b, x), (%Nv.mem_app(a, b, x) : {_ == False{} : Bool}; h))

# Strip drops programs and never adds one.
law Nv.strip_go_progs:
  for m: Bool
  for +s: P.Step
  for +rest: +List<P.Step>
  for +x: String
  for hs: {S.Sup.member(N.Native.prog(s), x) == False{} : Bool}
  for hr: {S.Sup.member(N.Native.progs(rest), x) == False{} : Bool}
  {S.Sup.member(N.Native.progs(N.Native.strip.go(m, s, rest)), x) == False{} : Bool}

def Nv.strip_go_progs(m, s, rest, x, hs, hr):
  match m:
    case True{}:
      hr
    case False{}:
      Nv.mem_app_ff(N.Native.prog(s), N.Native.progs(rest), x, hs, hr)

law Nv.strip_progs:
  for +ss: +List<P.Step>
  for +x: String
  for +h: {S.Sup.member(N.Native.progs(ss), x) == False{} : Bool}
  {S.Sup.member(N.Native.progs(N.Native.strip(ss)), x) == False{} : Bool}

def Nv.strip_progs(ss, x, h):
  match ss:
    case Nil{}:
      {==}
    case Con{+s, +t}:
      Nv.strip_go_progs(N.Native.machine(s), s, N.Native.strip(t), x,
        Nv.mem_app_fl(N.Native.prog(s), N.Native.progs(t), x, h),
        Nv.strip_progs(t, x, Nv.mem_app_fr(N.Native.prog(s), N.Native.progs(t), x, h)))

# Relocation maps the program list.
law Nv.strs_app:
  for +e: N.Env
  for +a: +List<String>
  for +b: +List<String>
  {N.Native.strs(e, List.append(&2, String, a, b)) == List.append(&2, String, N.Native.strs(e, a), N.Native.strs(e, b)) : +List<String>}

def Nv.strs_app(e, a, b):
  match a:
    case Nil{}:
      {==}
    case Con{+y, +t}:
      %Equal.sym(+List<String>, N.Native.strs(e, List.append(&2, String, t, b)), List.append(&2, String, N.Native.strs(e, t), N.Native.strs(e, b)), Nv.strs_app(e, t, b)) :
        {Con{N.Native.str(e, y), _} == Con{N.Native.str(e, y), List.append(&2, String, N.Native.strs(e, t), N.Native.strs(e, b))} : +List<String>}
      {==}

law Nv.prog_step:
  for +e: N.Env
  for s: P.Step
  {N.Native.prog(N.Native.relocate.step(e, s)) == N.Native.strs(e, N.Native.prog(s)) : +List<String>}

def Nv.prog_step(e, s):
  match s:
    case P.Mount{fs, src, dst, opts}:
      {==}
    case P.Write{path, text}:
      {==}
    case P.Run{prog, args}:
      {==}
    case P.Daemon{name, prog, args}:
      {==}
    case P.Spawn{name, prog, args}:
      {==}
    case P.WaitTcp{host, port, ms}:
      {==}
    case P.Stop{names}:
      {==}
    case P.WaitFile{path, ms}:
      {==}
    case P.Modules{path}:
      {==}
    case P.Log{text}:
      {==}

law Nv.progs_relocate:
  for +e: N.Env
  for +ss: +List<P.Step>
  {N.Native.progs(N.Native.relocate(e, ss)) == N.Native.strs(e, N.Native.progs(ss)) : +List<String>}

def Nv.progs_relocate(e, ss):
  match ss:
    case Nil{}:
      {==}
    case Con{+s, +t}:
      %Equal.sym(+List<String>, N.Native.progs(N.Native.relocate(e, t)), N.Native.strs(e, N.Native.progs(t)), Nv.progs_relocate(e, t)) :
        {List.append(&2, String, N.Native.prog(N.Native.relocate.step(e, s)), _) == N.Native.strs(e, List.append(&2, String, N.Native.prog(s), N.Native.progs(t))) : +List<String>}
      %Equal.sym(+List<String>, N.Native.prog(N.Native.relocate.step(e, s)), N.Native.strs(e, N.Native.prog(s)), Nv.prog_step(e, s)) :
        {List.append(&2, String, _, N.Native.strs(e, N.Native.progs(t))) == N.Native.strs(e, List.append(&2, String, N.Native.prog(s), N.Native.progs(t))) : +List<String>}
      Equal.sym(+List<String>, N.Native.strs(e, List.append(&2, String, N.Native.prog(s), N.Native.progs(t))), List.append(&2, String, N.Native.strs(e, N.Native.prog(s)), N.Native.strs(e, N.Native.progs(t))), Nv.strs_app(e, N.Native.prog(s), N.Native.progs(t)))

# The one concrete evaluation: the plan's programs, relocated.
law Nv.no_vm_busybox.progs:
  {S.Sup.member(N.Native.strs(N.Native.env_of("/d", "", "", "", "", ""), N.Native.progs(N.Native.plan(P.Plan.default_cfg("demo", 6443, False{})))),
     "/bin/busybox") == False{} : Bool}

def Nv.no_vm_busybox.progs():
  {==}

# The boot plan's programs, for any env and config: strip and relocation
# go through the general lemmas here, on open terms. The closed proof
# below is then one application whose types match the law and the
# concrete lemma as written, so the verdict kernel has no closed plan to
# unfold while it compares boot with strip, relocate and plan.
law Nv.boot_progs:
  for +e: N.Env
  for +c: P.Cfg
  for +x: String
  for +h: {S.Sup.member(N.Native.strs(e, N.Native.progs(N.Native.plan(c))), x) == False{} : Bool}
  {S.Sup.member(N.Native.progs(N.Native.boot(e, c)), x) == False{} : Bool}

def Nv.boot_progs(e, c, x, h):
  Nv.strip_progs(N.Native.relocate(e, N.Native.plan(c)), x,
    (%Equal.sym(+List<String>, N.Native.progs(N.Native.relocate(e, N.Native.plan(c))),
        N.Native.strs(e, N.Native.progs(N.Native.plan(c))),
        Nv.progs_relocate(e, N.Native.plan(c))) :
      {S.Sup.member(_, x) == False{} : Bool};
     h))

def L.native.no_vm_busybox():
  Nv.boot_progs(N.Native.env_of("/d", "", "", "", "", ""), P.Plan.default_cfg("demo", 6443, False{}), "/bin/busybox",
    Nv.no_vm_busybox.progs())

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
