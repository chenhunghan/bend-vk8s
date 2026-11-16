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

# keeps_pki_steps, control_plane_only and smoke_daemons in one evaluation
# ran the verdict kernel out of fuel: each relocated a whole plan, every
# string character by character. General lemmas on open terms carry the
# plan through relocation and strip; the closed proofs compute only the
# PKI's machine steps (without the written texts) and the daemon names
# of the plan as data.

# Kit: naturals (copied from proofs/snapshot.bend, prefix Nv.).

def Nv.ndisc(n: Nat) -> Type:
  match n:
    case 0n:
      Unit
    case 1n+p:
      Empty

def Nv.zs(-A: Type, -p: Nat, e: {0n == 1n+p : Nat}) -> A:
  Empty.absurd(A, (%e : Nv.ndisc(_); Unit{}))

def Nv.sz(-A: Type, -p: Nat, e: {1n+p == 0n : Nat}) -> A:
  Nv.zs(A, p, Equal.sym(Nat, 1n+p, 0n, e))

# A count of 0 has a head that is no machine step, and a tail of count 0.
law Nv.count_head:
  for m: Bool
  for +k: Nat
  for h: {N.Native.count.go(m, k) == 0n : Nat}
  {m == False{} : Bool}

def Nv.count_head(m, k, h):
  match m:
    case True{}:
      Nv.sz({True{} == False{} : Bool}, k, h)
    case False{}:
      {==}

law Nv.count_rest:
  for m: Bool
  for +k: Nat
  for h: {N.Native.count.go(m, k) == 0n : Nat}
  {k == 0n : Nat}

def Nv.count_rest(m, k, h):
  match m:
    case True{}:
      Nv.sz({k == 0n : Nat}, k, h)
    case False{}:
      h

# Whether a step is a machine step once relocated, without relocating
# the text it writes (machine reads only a Write's path).
def Nv.mstep(+e: N.Env, s: P.Step) -> Bool:
  match s:
    case P.Mount{fs, src, dst, opts}:
      True{}
    case P.Modules{path}:
      True{}
    case P.Write{path, text}:
      N.Native.machine_path(N.Native.str(e, path))
    case P.Run{prog, args}:
      N.Native.machine_run(N.Native.strs(e, args))
    case _:
      False{}

def Nv.mcount(+e: N.Env, ss: +List<P.Step>) -> Nat:
  match ss:
    case Nil{}:
      0n
    case Con{s, t}:
      N.Native.count.go(Nv.mstep(e, s), Nv.mcount(e, t))

law Nv.mstep_eq:
  for +e: N.Env
  for s: P.Step
  {N.Native.machine(N.Native.relocate.step(e, s)) == Nv.mstep(e, s) : Bool}

def Nv.mstep_eq(e, s):
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

law Nv.mcount_eq:
  for +e: N.Env
  for +ss: +List<P.Step>
  {N.Native.machine_count(N.Native.relocate(e, ss)) == Nv.mcount(e, ss) : Nat}

def Nv.mcount_eq(e, ss):
  match ss:
    case Nil{}:
      {==}
    case Con{+s, +t}:
      %Equal.sym(Nat, N.Native.machine_count(N.Native.relocate(e, t)), Nv.mcount(e, t), Nv.mcount_eq(e, t)) :
        {N.Native.count.go(N.Native.machine(N.Native.relocate.step(e, s)), _) == N.Native.count.go(Nv.mstep(e, s), Nv.mcount(e, t)) : Nat}
      %Equal.sym(Bool, N.Native.machine(N.Native.relocate.step(e, s)), Nv.mstep(e, s), Nv.mstep_eq(e, s)) :
        {N.Native.count.go(_, Nv.mcount(e, t)) == N.Native.count.go(Nv.mstep(e, s), Nv.mcount(e, t)) : Nat}
      {==}

# Taking nothing gives nothing.
law Nv.take_zero:
  for xs: +List<P.Step>
  {List.take(&2, P.Step, xs, 0n) == Nil{} : +List<P.Step>}

def Nv.take_zero(xs):
  match xs:
    case Nil{}:
      {==}
    case Con{x, t}:
      {==}

# A kept head stays the head.
law Nv.pref_go:
  for m: Bool
  for +r: P.Step
  for +rest: +List<P.Step>
  for +n: Nat
  for +want: +List<P.Step>
  for hm: {m == False{} : Bool}
  for hr: {List.take(&2, P.Step, rest, n) == want : +List<P.Step>}
  {List.take(&2, P.Step, N.Native.strip.go(m, r, rest), 1n+n) == Con{r, want} : +List<P.Step>}

def Nv.pref_go(m, r, rest, n, want, hm, hr):
  %Equal.sym(Bool, m, False{}, hm) : {List.take(&2, P.Step, N.Native.strip.go(_, r, rest), 1n+n) == Con{r, want} : +List<P.Step>}
  %hr : {Con{r, List.take(&2, P.Step, rest, n)} == Con{r, _} : +List<P.Step>}
  {==}

# A prefix a with no machine step once relocated comes first, relocated,
# in the stripped and relocated a ++ b, whatever b is.
law Nv.pref:
  for +e: N.Env
  for +a: +List<P.Step>
  for +b: +List<P.Step>
  for +h: {N.Native.machine_count(N.Native.relocate(e, a)) == 0n : Nat}
  {List.take(&2, P.Step, N.Native.strip(N.Native.relocate(e, List.append(&2, P.Step, a, b))), List.length(&2, P.Step, a)) ==
    N.Native.relocate(e, a) : +List<P.Step>}

def Nv.pref(e, a, b, h):
  match a:
    case Nil{}:
      Nv.take_zero(N.Native.strip(N.Native.relocate(e, b)))
    case Con{+s, +t}:
      Nv.pref_go(N.Native.machine(N.Native.relocate.step(e, s)), N.Native.relocate.step(e, s),
        N.Native.strip(N.Native.relocate(e, List.append(&2, P.Step, t, b))), List.length(&2, P.Step, t), N.Native.relocate(e, t),
        Nv.count_head(N.Native.machine(N.Native.relocate.step(e, s)), N.Native.machine_count(N.Native.relocate(e, t)), h),
        Nv.pref(e, t, b, Nv.count_rest(N.Native.machine(N.Native.relocate.step(e, s)), N.Native.machine_count(N.Native.relocate(e, t)), h)))

# The boot plan's PKI prefix, for any env and config (Native.plan starts
# with the PKI steps).
law Nv.boot_pki:
  for +e: N.Env
  for +c: P.Cfg
  for +h: {Nv.mcount(e, P.Plan.pki_steps(c)) == 0n : Nat}
  {List.take(&2, P.Step, N.Native.boot(e, c), List.length(&2, P.Step, P.Plan.pki_steps(c))) ==
    N.Native.relocate(e, P.Plan.pki_steps(c)) : +List<P.Step>}

def Nv.boot_pki(e, c, h):
  Nv.pref(e, P.Plan.pki_steps(c),
    List.append(&2, P.Step, N.Native.with_join_args(c, P.Plan.control_plane(c)),
    List.append(&2, P.Step, N.Native.cluster(c), P.Plan.publish(c))),
    (%Equal.sym(Nat, N.Native.machine_count(N.Native.relocate(e, P.Plan.pki_steps(c))), Nv.mcount(e, P.Plan.pki_steps(c)),
        Nv.mcount_eq(e, P.Plan.pki_steps(c))) :
      {_ == 0n : Nat};
     h))

# Nv.pki_clean in one evaluation ran the verdict kernel out of fuel: it
# relocated the arguments of all 13 PKI steps, two long shell lines
# among them. Nv.mc_peel splits the count into the head step and the
# tail on open terms, so each closed lemma below relocates one step.

def Nv.mhead(+e: N.Env, ss: +List<P.Step>) -> Bool:
  match ss:
    case Nil{}:
      False{}
    case Con{s, t}:
      Nv.mstep(e, s)

def Nv.tl(ss: +List<P.Step>) -> +List<P.Step>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      t

# A list counts no machine step when its head is none and its tail
# counts none.
law Nv.mc_peel:
  for +e: N.Env
  for +ss: +List<P.Step>
  for hh: {Nv.mhead(e, ss) == False{} : Bool}
  for ht: {Nv.mcount(e, Nv.tl(ss)) == 0n : Nat}
  {Nv.mcount(e, ss) == 0n : Nat}

def Nv.mc_peel(e, ss, hh, ht):
  match ss:
    case Nil{}:
      {==}
    case Con{+s, +t}:
      %Equal.sym(Bool, Nv.mstep(e, s), False{}, hh) : {N.Native.count.go(_, Nv.mcount(e, t)) == 0n : Nat}
      ht

# The concrete evaluations: each PKI step on its own, then the end.

law Nv.pki_step0:
  {Nv.mhead(N.Native.env_of("/d", "", "", "", "", ""), P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{}))) == False{} : Bool}

def Nv.pki_step0():
  {==}

law Nv.pki_step1:
  {Nv.mhead(N.Native.env_of("/d", "", "", "", "", ""), Nv.tl(P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{})))) == False{} : Bool}

def Nv.pki_step1():
  {==}

law Nv.pki_step2:
  {Nv.mhead(N.Native.env_of("/d", "", "", "", "", ""), Nv.tl(Nv.tl(P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{}))))) == False{} : Bool}

def Nv.pki_step2():
  {==}

law Nv.pki_step3:
  {Nv.mhead(N.Native.env_of("/d", "", "", "", "", ""), Nv.tl(Nv.tl(Nv.tl(P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{})))))) == False{} : Bool}

def Nv.pki_step3():
  {==}

law Nv.pki_step4:
  {Nv.mhead(N.Native.env_of("/d", "", "", "", "", ""), Nv.tl(Nv.tl(Nv.tl(Nv.tl(P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{}))))))) == False{} : Bool}

def Nv.pki_step4():
  {==}

law Nv.pki_step5:
  {Nv.mhead(N.Native.env_of("/d", "", "", "", "", ""), Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{})))))))) == False{} : Bool}

def Nv.pki_step5():
  {==}

law Nv.pki_step6:
  {Nv.mhead(N.Native.env_of("/d", "", "", "", "", ""), Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{}))))))))) == False{} : Bool}

def Nv.pki_step6():
  {==}

law Nv.pki_step7:
  {Nv.mhead(N.Native.env_of("/d", "", "", "", "", ""), Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{})))))))))) == False{} : Bool}

def Nv.pki_step7():
  {==}

law Nv.pki_step8:
  {Nv.mhead(N.Native.env_of("/d", "", "", "", "", ""), Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{}))))))))))) == False{} : Bool}

def Nv.pki_step8():
  {==}

law Nv.pki_step9:
  {Nv.mhead(N.Native.env_of("/d", "", "", "", "", ""), Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{})))))))))))) == False{} : Bool}

def Nv.pki_step9():
  {==}

law Nv.pki_step10:
  {Nv.mhead(N.Native.env_of("/d", "", "", "", "", ""), Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{}))))))))))))) == False{} : Bool}

def Nv.pki_step10():
  {==}

law Nv.pki_step11:
  {Nv.mhead(N.Native.env_of("/d", "", "", "", "", ""), Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{})))))))))))))) == False{} : Bool}

def Nv.pki_step11():
  {==}

law Nv.pki_step12:
  {Nv.mhead(N.Native.env_of("/d", "", "", "", "", ""), Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{}))))))))))))))) == False{} : Bool}

def Nv.pki_step12():
  {==}

law Nv.pki_end:
  {Nv.mcount(N.Native.env_of("/d", "", "", "", "", ""), Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{})))))))))))))))) == 0n : Nat}

def Nv.pki_end():
  {==}

# No PKI step is a machine step on the host.
law Nv.pki_clean:
  {Nv.mcount(N.Native.env_of("/d", "", "", "", "", ""), P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{}))) == 0n : Nat}

def Nv.pki_clean():
  Nv.mc_peel(N.Native.env_of("/d", "", "", "", "", ""), P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{})), Nv.pki_step0(),
    Nv.mc_peel(N.Native.env_of("/d", "", "", "", "", ""), Nv.tl(P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{}))), Nv.pki_step1(),
    Nv.mc_peel(N.Native.env_of("/d", "", "", "", "", ""), Nv.tl(Nv.tl(P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{})))), Nv.pki_step2(),
    Nv.mc_peel(N.Native.env_of("/d", "", "", "", "", ""), Nv.tl(Nv.tl(Nv.tl(P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{}))))), Nv.pki_step3(),
    Nv.mc_peel(N.Native.env_of("/d", "", "", "", "", ""), Nv.tl(Nv.tl(Nv.tl(Nv.tl(P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{})))))), Nv.pki_step4(),
    Nv.mc_peel(N.Native.env_of("/d", "", "", "", "", ""), Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{}))))))), Nv.pki_step5(),
    Nv.mc_peel(N.Native.env_of("/d", "", "", "", "", ""), Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{})))))))), Nv.pki_step6(),
    Nv.mc_peel(N.Native.env_of("/d", "", "", "", "", ""), Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{}))))))))), Nv.pki_step7(),
    Nv.mc_peel(N.Native.env_of("/d", "", "", "", "", ""), Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{})))))))))), Nv.pki_step8(),
    Nv.mc_peel(N.Native.env_of("/d", "", "", "", "", ""), Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{}))))))))))), Nv.pki_step9(),
    Nv.mc_peel(N.Native.env_of("/d", "", "", "", "", ""), Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{})))))))))))), Nv.pki_step10(),
    Nv.mc_peel(N.Native.env_of("/d", "", "", "", "", ""), Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{}))))))))))))), Nv.pki_step11(),
    Nv.mc_peel(N.Native.env_of("/d", "", "", "", "", ""), Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(Nv.tl(P.Plan.pki_steps(P.Plan.default_cfg("demo", 6443, False{})))))))))))))), Nv.pki_step12(),
    Nv.pki_end())))))))))))))

def L.native.keeps_pki_steps():
  Nv.boot_pki(N.Native.env_of("/d", "", "", "", "", ""), P.Plan.default_cfg("demo", 6443, False{}), Nv.pki_clean())

# Strip and relocation keep the daemon names: a machine step is no
# daemon, and relocation keeps every name.
law Nv.dn_go0:
  for m: Bool
  for +s: P.Step
  for +rest: +List<P.Step>
  for +want: +List<String>
  for hd: {N.Native.daemon_name(s) == Nil{} : +List<String>}
  for hr: {N.Native.daemon_names(rest) == want : +List<String>}
  {N.Native.daemon_names(N.Native.strip.go(m, s, rest)) == want : +List<String>}

def Nv.dn_go0(m, s, rest, want, hd, hr):
  match m:
    case True{}:
      hr
    case False{}:
      %Equal.sym(+List<String>, N.Native.daemon_name(s), Nil{}, hd) : {List.append(&2, String, _, N.Native.daemon_names(rest)) == want : +List<String>}
      hr

law Nv.dn_strip_go:
  for +s: P.Step
  for +rest: +List<P.Step>
  for +want: +List<String>
  for hr: {N.Native.daemon_names(rest) == want : +List<String>}
  {N.Native.daemon_names(N.Native.strip.go(N.Native.machine(s), s, rest)) == List.append(&2, String, N.Native.daemon_name(s), want) : +List<String>}

def Nv.dn_strip_go(s, rest, want, hr):
  match s:
    case P.Mount{fs, src, dst, opts}:
      hr
    case P.Write{+path, +text}:
      Nv.dn_go0(N.Native.machine_path(path), P.Write{path, text}, rest, want, {==}, hr)
    case P.Run{+prog, +args}:
      Nv.dn_go0(N.Native.machine_run(args), P.Run{prog, args}, rest, want, {==}, hr)
    case P.Daemon{+name, prog, args}:
      %hr : {Con{name, N.Native.daemon_names(rest)} == Con{name, _} : +List<String>}
      {==}
    case P.Spawn{name, prog, args}:
      hr
    case P.WaitTcp{host, port, ms}:
      hr
    case P.Stop{names}:
      hr
    case P.WaitFile{path, ms}:
      hr
    case P.Modules{path}:
      hr
    case P.Log{text}:
      hr

law Nv.dn_strip:
  for +ss: +List<P.Step>
  {N.Native.daemon_names(N.Native.strip(ss)) == N.Native.daemon_names(ss) : +List<String>}

def Nv.dn_strip(ss):
  match ss:
    case Nil{}:
      {==}
    case Con{+s, +t}:
      Nv.dn_strip_go(s, N.Native.strip(t), N.Native.daemon_names(t), Nv.dn_strip(t))

law Nv.dn_step:
  for +e: N.Env
  for s: P.Step
  {N.Native.daemon_name(N.Native.relocate.step(e, s)) == N.Native.daemon_name(s) : +List<String>}

def Nv.dn_step(e, s):
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

law Nv.dn_relocate:
  for +e: N.Env
  for +ss: +List<P.Step>
  {N.Native.daemon_names(N.Native.relocate(e, ss)) == N.Native.daemon_names(ss) : +List<String>}

def Nv.dn_relocate(e, ss):
  match ss:
    case Nil{}:
      {==}
    case Con{+s, +t}:
      %Equal.sym(+List<String>, N.Native.daemon_names(N.Native.relocate(e, t)), N.Native.daemon_names(t), Nv.dn_relocate(e, t)) :
        {List.append(&2, String, N.Native.daemon_name(N.Native.relocate.step(e, s)), _) == List.append(&2, String, N.Native.daemon_name(s), N.Native.daemon_names(t)) : +List<String>}
      %Equal.sym(+List<String>, N.Native.daemon_name(N.Native.relocate.step(e, s)), N.Native.daemon_name(s), Nv.dn_step(e, s)) :
        {List.append(&2, String, _, N.Native.daemon_names(t)) == List.append(&2, String, N.Native.daemon_name(s), N.Native.daemon_names(t)) : +List<String>}
      {==}

law Nv.dn_native:
  for +e: N.Env
  for +ss: +List<P.Step>
  for +want: +List<String>
  for +h: {N.Native.daemon_names(ss) == want : +List<String>}
  {N.Native.daemon_names(N.Native.strip(N.Native.relocate(e, ss))) == want : +List<String>}

def Nv.dn_native(e, ss, want, h):
  %Equal.sym(+List<String>, N.Native.daemon_names(N.Native.strip(N.Native.relocate(e, ss))), N.Native.daemon_names(N.Native.relocate(e, ss)),
    Nv.dn_strip(N.Native.relocate(e, ss))) : {_ == want : +List<String>}
  %Equal.sym(+List<String>, N.Native.daemon_names(N.Native.relocate(e, ss)), N.Native.daemon_names(ss), Nv.dn_relocate(e, ss)) :
    {_ == want : +List<String>}
  h

# The boot and smoke plans' daemons, for any env and config, stated with
# boot and smoke as the laws are, so the closed proofs below are single
# applications.
law Nv.boot_daemons:
  for +e: N.Env
  for +c: P.Cfg
  for +want: +List<String>
  for +h: {N.Native.daemon_names(N.Native.plan(c)) == want : +List<String>}
  {N.Native.daemon_names(N.Native.boot(e, c)) == want : +List<String>}

def Nv.boot_daemons(e, c, want, h):
  Nv.dn_native(e, N.Native.plan(c), want, h)

law Nv.smoke_daemons:
  for +e: N.Env
  for +c: P.Cfg
  for +want: +List<String>
  for +h: {N.Native.daemon_names(N.Native.smoke_plan(c)) == want : +List<String>}
  {N.Native.daemon_names(N.Native.smoke(e, c)) == want : +List<String>}

def Nv.smoke_daemons(e, c, want, h):
  Nv.dn_native(e, N.Native.smoke_plan(c), want, h)

# The concrete evaluations: the daemon names of the plans as data.
law Nv.plan_daemons:
  {N.Native.daemon_names(N.Native.plan(P.Plan.default_cfg("demo", 6443, False{}))) ==
    ["kine", "kube-apiserver", "kube-controller-manager", "kube-scheduler", "join-server"] : +List<String>}

def Nv.plan_daemons():
  {==}

law Nv.plan_daemons.etcd:
  {N.Native.daemon_names(N.Native.plan(P.Plan.default_cfg("demo", 6443, True{}))) ==
    ["etcd", "kube-apiserver", "kube-controller-manager", "kube-scheduler", "join-server"] : +List<String>}

def Nv.plan_daemons.etcd():
  {==}

law Nv.smoke_plan_daemons:
  {N.Native.daemon_names(N.Native.smoke_plan(P.Plan.default_cfg("demo", 6443, True{}))) == ["etcd", "kube-apiserver", "join-server"] : +List<String>}

def Nv.smoke_plan_daemons():
  {==}

def L.native.control_plane_only():
  Nv.boot_daemons(N.Native.env_of("/d", "", "", "", "", ""), P.Plan.default_cfg("demo", 6443, False{}),
    ["kine", "kube-apiserver", "kube-controller-manager", "kube-scheduler", "join-server"], Nv.plan_daemons())

def L.native.control_plane_only.etcd():
  Nv.boot_daemons(N.Native.env_of("/d", "", "", "", "", ""), P.Plan.default_cfg("demo", 6443, True{}),
    ["etcd", "kube-apiserver", "kube-controller-manager", "kube-scheduler", "join-server"], Nv.plan_daemons.etcd())

def L.native.cluster_layer():
  {==}

def L.native.join_server():
  {==}

def L.native.smoke_daemons():
  Nv.smoke_daemons(N.Native.env_of("/d", "", "", "", "", ""), P.Plan.default_cfg("demo", 6443, True{}), ["etcd", "kube-apiserver", "join-server"], Nv.smoke_plan_daemons())

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

def L.native.signal_now.running():
  {==}

def L.native.signal_now.reaped():
  {==}

def L.native.signal_now.unknown():
  {==}

def L.native.signal_now.stopped():
  {==}

def L.native.signal_now_safe(svcs, p):
  Nv.safe_pids_ok(N.Native.alive_pid.go(S.Sup.alive(svcs, p), p))
