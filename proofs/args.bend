import Base
import ../laws/args.bend as L
import ../src/lib/args.bend as A

# Proofs of laws/args.bend: `def L.<law>` for each law.

def L.args.merge.no_extra_args():
  {==}

def L.args.merge.extra_args():
  {==}

def L.args.merge.same_flag_last():
  {==}

def L.args.merge.same_flag_first():
  {==}

def L.args.merge.multi_same_flag():
  {==}

def L.args.merge.nil_extra_args():
  {==}

def L.args.merge.no_flags():
  {==}

def L.args.contains.inline_value():
  {==}

def L.args.contains.split_value():
  {==}

def L.args.contains.different_flag():
  {==}

def L.args.contains.non_flag_ignored():
  {==}

def L.args.merge.extras_last(base, extra):
  (A.Args.keep(base, extra), {==})

# A clash between True{} and False{} proves anything.

def Ar.disc_t(b: Bool) -> Type:
  match b:
    case True{}:
      Empty
    case False{}:
      Unit

def Ar.disc_f(b: Bool) -> Type:
  match b:
    case True{}:
      Unit
    case False{}:
      Empty

law Ar.false_ne_true:
  for h: {False{} == True{} : Bool}
  Empty

def Ar.false_ne_true(h):
  %h : Ar.disc_t(_)
  Unit{}

law Ar.true_ne_false:
  for h: {True{} == False{} : Bool}
  Empty

def Ar.true_ne_false(h):
  %h : Ar.disc_f(_)
  Unit{}

law Ar.absurd:
  for -a: +List<String>
  for -b: +List<String>
  for e: Empty
  {a == b : +List<String>}

def Ar.absurd(a, b, e):
  match e:

# keep.put on a known answer, stated {simple == computed} so that % puts
# the simple form in place.
law Ar.put_true:
  for c: Bool
  for -x: String
  for -r: +List<String>
  for h: {c == True{} : Bool}
  {r == A.Args.keep.put(c, x, r) : +List<String>}

def Ar.put_true(c, x, r, h):
  match c:
    case True{}:
      {==}
    case False{}:
      Ar.absurd(r, Con{x, r}, Ar.false_ne_true(h))

law Ar.put_false:
  for c: Bool
  for -x: String
  for -r: +List<String>
  for h: {c == False{} : Bool}
  {Con{x, r} == A.Args.keep.put(c, x, r) : +List<String>}

def Ar.put_false(c, x, r, h):
  match c:
    case True{}:
      Ar.absurd(Con{x, r}, r, Ar.true_ne_false(h))
    case False{}:
      {==}

def L.args.merge.named_dropped(x, base, extra, h):
  %Ar.put_true(A.Args.contains_flag(extra, x), x, A.Args.keep(base, extra), h) : {List.append(&2, String, _, extra)
    == A.Args.merge(base, extra) : +List<String>}
  {==}

def L.args.merge.unnamed_kept(x, base, extra, h):
  %Ar.put_false(A.Args.contains_flag(extra, x), x, A.Args.keep(base, extra), h) : {List.append(&2, String, _, extra)
    == Con{x, A.Args.merge(base, extra)} : +List<String>}
  {==}

def L.args.merge.no_extras(base):
  match base:
    case Nil{}:
      {==}
    case Con{b, t}:
      %L.args.merge.no_extras(t) : {Con{b, A.Args.merge(t, [])} == Con{b, _} : +List<String>}
      {==}
