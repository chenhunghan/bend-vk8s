import Base
import ../laws/names.bend as L
import ../src/translate/names.bend as N
import ../src/lib/sha256.bend as H

# Proofs of laws/names.bend: `def L.<law>` for each law.

# Concrete laws: both sides compute.

def L.names.short_joins():
  {==}

def L.names.empty_stays_empty():
  {==}

def L.names.long_is_hashed():
  {==}

def L.names.dot_dash_collapses():
  {==}

def L.names.cluster_scoped():
  {==}

def L.names.marker_cluster():
  {==}

def L.names.root_ca():
  {==}

# Lemmas for the general laws. "x fits n" is Nat.is_le(String.length(x), n).

def names.disc(b: Bool) -> Type:
  match b:
    case False{}:
      Unit
    case True{}:
      Empty

# False is not True.
def names.false_true(e: {False{} == True{} : Bool}) -> Empty:
  %e : names.disc(_)
  Unit{}

def names.absurd(-A: Type, e: {False{} == True{} : Bool}) -> A:
  Empty.absurd(A, names.false_true(e))

# 0 <= n.
law names.zero_le:
  for n: Nat
  {Nat.is_le(0n, n) == True{} : Bool}

def names.zero_le(n):
  match n:
    case 0n:
      {==}
    case 1n+p:
      {==}

# a <= m implies a <= m + 1.
law names.le_succ:
  for a: Nat
  for m: Nat
  for h: {Nat.is_le(a, m) == True{} : Bool}
  {Nat.is_le(a, 1n+m) == True{} : Bool}

def names.le_succ(a, m, h):
  match a m:
    case 0n _:
      {==}
    case 1n+ap 0n:
      names.absurd({Nat.is_le(1n+ap, 1n) == True{} : Bool}, h)
    case 1n+ap 1n+mp:
      names.le_succ(ap, mp, h)

# a <= q implies a <= p + q.
law names.le_add:
  for +a: Nat
  for +p: Nat
  for +q: Nat
  for h: {Nat.is_le(a, q) == True{} : Bool}
  {Nat.is_le(a, Nat.add(p, q)) == True{} : Bool}

def names.le_add(a, p, q, h):
  match p:
    case 0n:
      h
    case 1n+pp:
      names.le_succ(a, Nat.add(pp, q), names.le_add(a, pp, q, h))

# take(s, n) fits n.
law names.take_fits:
  for s: String
  for n: Nat
  {Nat.is_le(String.length(String.take(s, n)), n) == True{} : Bool}

def names.take_fits(s, n):
  match s n:
    case SNil{} _:
      names.zero_le(n)
    case SCon{h, t} 0n:
      {==}
    case SCon{h, t} 1n+p:
      names.take_fits(t, p)

# If a fits p and b fits q, a ++ b fits p + q.
law names.append_fits:
  for a: String
  for b: String
  for p: Nat
  for q: Nat
  for ha: {Nat.is_le(String.length(a), p) == True{} : Bool}
  for hb: {Nat.is_le(String.length(b), q) == True{} : Bool}
  {Nat.is_le(String.length(String.append(a, b)), Nat.add(p, q)) == True{} : Bool}

def names.append_fits(a, b, p, q, ha, hb):
  match a p:
    case SNil{} 0n:
      hb
    case SNil{} 1n+pp:
      names.le_add(String.length(b), 1n+pp, q, hb)
    case SCon{h, t} 0n:
      names.absurd({Nat.is_le(String.length(String.append(SCon{h, t}, b)), q) == True{} : Bool}, ha)
    case SCon{h, t} 1n+pp:
      names.append_fits(t, b, pp, q, ha, hb)

# Emitting one more character fits one more.
law names.emit_fits:
  for b: Bool
  for c: Char
  for r: String
  for m: Nat
  for h: {Nat.is_le(String.length(r), m) == True{} : Bool}
  {Nat.is_le(String.length(N.Names.emit(b, c, r)), 1n+m) == True{} : Bool}

def names.emit_fits(b, c, r, m, h):
  match b:
    case True{}:
      names.le_succ(String.length(r), m, h)
    case False{}:
      h

# Collapsing ".-" never makes a name longer.
law names.collapse_fits:
  for +x: String
  for +n: Nat
  for h: {Nat.is_le(String.length(x), n) == True{} : Bool}
  {Nat.is_le(String.length(N.Names.collapse(x)), n) == True{} : Bool}

def names.collapse_fits(x, n, h):
  match x n:
    case SNil{} _:
      names.zero_le(n)
    case SCon{c, t} 0n:
      names.absurd({Nat.is_le(String.length(N.Names.collapse(SCon{c, t})), 0n) == True{} : Bool}, h)
    case SCon{c, t} 1n+m:
      names.emit_fits(N.Names.drop(c, t), c, N.Names.collapse(t), m,
        names.collapse_fits(t, m, h))

# A hashed name fits 52 + 1 + 10 = 63.
law names.hashed_fits:
  for +s: String
  {Nat.is_le(String.length(N.Names.hashed(s)), 63n) == True{} : Bool}

def names.hashed_fits(s):
  names.collapse_fits(
    String.append(String.take(s, 52n), SCon{'-', String.take(H.Sha256.hex_of(s), 10n)}),
    63n,
    names.append_fits(String.take(s, 52n), SCon{'-', String.take(H.Sha256.hex_of(s), 10n)},
      52n, 11n, names.take_fits(s, 52n), names.take_fits(H.Sha256.hex_of(s), 10n)))

# Either branch of shorten fits 63; e records which branch was taken.
law names.shorten_fits:
  for b: Bool
  for +s: String
  for e: {Nat.is_le(String.length(s), 63n) == b : Bool}
  {Nat.is_le(String.length(N.Names.shorten.if(b, s)), 63n) == True{} : Bool}

def names.shorten_fits(b, s, e):
  match b:
    case True{}:
      e
    case False{}:
      names.hashed_fits(s)

def L.names.at_most_63(parts):
  +j = String.join(parts, "-")
  names.shorten_fits(Nat.is_le(String.length(j), 63n), j, {==})

def L.names.single_part_short(s, h):
  %Equal.sym(Bool, Nat.is_le(String.length(s), 63n), True{}, h) : {N.Names.shorten.if(_, s) == s : String}
  {==}
