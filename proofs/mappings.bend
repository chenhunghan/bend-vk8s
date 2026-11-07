import Base
import ../laws/mappings.bend as L
import ../src/sync/mappings.bend as M

# Proofs of laws/mappings.bend: `def L.<law>` for each law.
#
# The concrete laws compute. The general laws rest on a small kit:
# String.eq is reflexive and String.eq(a, b) == True gives a == b (the
# String.order lemmas of proofs/meta.bend, copied under the mp. prefix), so
# NN.eq and NM.same are equality. A lookup in a store with one more mapping
# at the end is the old lookup, else the new mapping's (mp.look_app); finding
# by key works the same way (mp.find_app). A passed conflict check means each
# side's lookup is absent or the recorded name (mp.conf_ok). The proofs case
# on computed values (the conflict check, the verification, the find) through
# helper lemmas that take the value and its defining equation.

# Kit: string equality (copied from proofs/meta.bend, prefix mp.).

def mp.cdisc_eq(c: Cmp) -> Type:
  match c:
    case LT{}:
      Unit
    case EQ{}:
      Empty
    case GT{}:
      Unit

def mp.bdisc(b: Bool) -> Type:
  match b:
    case False{}:
      Empty
    case True{}:
      Unit

def mp.tf_absurd(-A: Type, e: {True{} == False{} : Bool}) -> A:
  Empty.absurd(A, (%e : mp.bdisc(_); Unit{}))

def mp.ne_eq(-A: Type, -x: Cmp, e: {x == EQ{} : Cmp}, d: mp.cdisc_eq(x)) -> A:
  Empty.absurd(A, (%e : mp.cdisc_eq(_); d))

law mp.bool_refl:
  for a: Bool
  {Bool.cmp(a, a) == EQ{} : Cmp}

def mp.bool_refl(a):
  match a:
    case False{}:
      {==}
    case True{}:
      {==}

law mp.word_refl:
  for +n: Nat
  for +a: Word(n)
  {Word.cmp(n, a, a) == EQ{} : Cmp}

def mp.word_refl(n, a):
  match n:
    case 0n:
      {==}
    case 1n+p:
      match a:
        case WCon{ab, at}:
          %Equal.sym(Cmp, Word.cmp(p, at, at), EQ{}, mp.word_refl(p, at)) : {Word.cmp.fin(ab, ab, _) == EQ{} : Cmp}
          mp.bool_refl(ab)

law mp.fin_eq_t:
  for ab: Bool
  for bb: Bool
  for t: Cmp
  for +e: {Word.cmp.fin(ab, bb, t) == EQ{} : Cmp}
  {t == EQ{} : Cmp}

def mp.fin_eq_t(ab, bb, t, e):
  match t:
    case LT{}:
      mp.ne_eq({LT{} == EQ{} : Cmp}, LT{}, e, Unit{})
    case EQ{}:
      {==}
    case GT{}:
      mp.ne_eq({GT{} == EQ{} : Cmp}, GT{}, e, Unit{})

law mp.bool_eq:
  for a: Bool
  for b: Bool
  for +e: {Bool.cmp(a, b) == EQ{} : Cmp}
  {a == b : Bool}

def mp.bool_eq(a, b, e):
  match a b:
    case False{} False{}:
      {==}
    case False{} True{}:
      mp.ne_eq({False{} == True{} : Bool}, LT{}, e, Unit{})
    case True{} False{}:
      mp.ne_eq({True{} == False{} : Bool}, GT{}, e, Unit{})
    case True{} True{}:
      {==}

law mp.fin_eq_b:
  for ab: Bool
  for bb: Bool
  for t: Cmp
  for +e: {Word.cmp.fin(ab, bb, t) == EQ{} : Cmp}
  {ab == bb : Bool}

def mp.fin_eq_b(ab, bb, t, e):
  match t:
    case LT{}:
      mp.ne_eq({ab == bb : Bool}, LT{}, e, Unit{})
    case EQ{}:
      mp.bool_eq(ab, bb, e)
    case GT{}:
      mp.ne_eq({ab == bb : Bool}, GT{}, e, Unit{})

law mp.word_eq:
  for +n: Nat
  for +a: Word(n)
  for +b: Word(n)
  for +e: {Word.cmp(n, a, b) == EQ{} : Cmp}
  {a == b : Word(n)}

def mp.word_eq(n, a, b, e):
  match n:
    case 0n:
      match a b:
        case WNil{} WNil{}:
          {==}
    case 1n+p:
      match a b:
        case WCon{ab, at} WCon{bb, bt}:
          %mp.fin_eq_b(ab, bb, Word.cmp(p, at, bt), e) : {WCon{ab, at} == WCon{_, bt} : Word(1n+p)}
          %mp.word_eq(p, at, bt, mp.fin_eq_t(ab, bb, Word.cmp(p, at, bt), e)) : {WCon{ab, at} == WCon{ab, _} : Word(1n+p)}
          {==}

law mp.u32_refl:
  for a: U32
  {U32.cmp(a, a) == EQ{} : Cmp}

def mp.u32_refl(a):
  match a:
    case U32{x}:
      mp.word_refl(32n, x)

law mp.u32_eq:
  for a: U32
  for b: U32
  for +e: {U32.cmp(a, b) == EQ{} : Cmp}
  {a == b : U32}

def mp.u32_eq(a, b, e):
  match a b:
    case U32{x} U32{y}:
      %mp.word_eq(32n, x, y, e) : {U32{x} == U32{_} : U32}
      {==}

law mp.go_lt:
  for a: String
  for b: String
  {String.order.go(a, b, LT{}) == LT{} : Cmp}

def mp.go_lt(a, b):
  match a b:
    case SNil{} SNil{}:
      {==}
    case SNil{} SCon{Chr{x}, t}:
      {==}
    case SCon{Chr{x}, t} SNil{}:
      {==}
    case SCon{Chr{x}, t1} SCon{Chr{y}, t2}:
          {==}

law mp.go_gt:
  for a: String
  for b: String
  {String.order.go(a, b, GT{}) == GT{} : Cmp}

def mp.go_gt(a, b):
  match a b:
    case SNil{} SNil{}:
      {==}
    case SNil{} SCon{Chr{x}, t}:
      {==}
    case SCon{Chr{x}, t} SNil{}:
      {==}
    case SCon{Chr{x}, t1} SCon{Chr{y}, t2}:
          {==}

law mp.str_refl:
  for +a: String
  {String.order(a, a) == EQ{} : Cmp}

def mp.str_refl(a):
  match a:
    case SNil{}:
      {==}
    case SCon{Chr{x}, t}:
      %Equal.sym(Cmp, U32.cmp(x, x), EQ{}, mp.u32_refl(x)) : {String.order.go(t, t, _) == EQ{} : Cmp}
      mp.str_refl(t)

law mp.go_eq_c:
  for a: String
  for b: String
  for c: Cmp
  for +e: {String.order.go(a, b, c) == EQ{} : Cmp}
  {c == EQ{} : Cmp}

def mp.go_eq_c(a, b, c, e):
  match c:
    case LT{}:
      mp.ne_eq({LT{} == EQ{} : Cmp}, LT{}, Equal.trans(Cmp, LT{}, String.order.go(a, b, LT{}), EQ{}, Equal.sym(Cmp, String.order.go(a, b, LT{}), LT{}, mp.go_lt(a, b)), e), Unit{})
    case EQ{}:
      {==}
    case GT{}:
      mp.ne_eq({GT{} == EQ{} : Cmp}, GT{}, Equal.trans(Cmp, GT{}, String.order.go(a, b, GT{}), EQ{}, Equal.sym(Cmp, String.order.go(a, b, GT{}), GT{}, mp.go_gt(a, b)), e), Unit{})

law mp.str_eq_go:
  for +a: String
  for +b: String
  for +c: Cmp
  for +e: {String.order.go(a, b, c) == EQ{} : Cmp}
  {a == b : String}

def mp.str_eq_go(a, b, c, e):
  match a b:
    case SNil{} SNil{}:
      {==}
    case SNil{} SCon{Chr{x}, t}:
      match c:
        case LT{}:
          mp.ne_eq({SNil{} == SCon{Chr{x}, t} : String}, LT{}, e, Unit{})
        case EQ{}:
          mp.ne_eq({SNil{} == SCon{Chr{x}, t} : String}, LT{}, e, Unit{})
        case GT{}:
          mp.ne_eq({SNil{} == SCon{Chr{x}, t} : String}, GT{}, e, Unit{})
    case SCon{Chr{x}, t} SNil{}:
      match c:
        case LT{}:
          mp.ne_eq({SCon{Chr{x}, t} == SNil{} : String}, LT{}, e, Unit{})
        case EQ{}:
          mp.ne_eq({SCon{Chr{x}, t} == SNil{} : String}, GT{}, e, Unit{})
        case GT{}:
          mp.ne_eq({SCon{Chr{x}, t} == SNil{} : String}, GT{}, e, Unit{})
    case SCon{Chr{x}, t1} SCon{Chr{y}, t2}:
      match c:
        case LT{}:
          mp.ne_eq({SCon{Chr{x}, t1} == SCon{Chr{y}, t2} : String}, LT{}, e, Unit{})
        case EQ{}:
          %mp.u32_eq(x, y, mp.go_eq_c(t1, t2, U32.cmp(x, y), e)) : {SCon{Chr{x}, t1} == SCon{Chr{_}, t2} : String}
          %mp.str_eq_go(t1, t2, U32.cmp(x, y), e) : {SCon{Chr{x}, t1} == SCon{Chr{x}, _} : String}
          {==}
        case GT{}:
          mp.ne_eq({SCon{Chr{x}, t1} == SCon{Chr{y}, t2} : String}, GT{}, e, Unit{})

law mp.str_eq:
  for +a: String
  for +b: String
  for +e: {String.order(a, b) == EQ{} : Cmp}
  {a == b : String}

def mp.str_eq(a, b, e):
  mp.str_eq_go(a, b, EQ{}, e)

# Booleans and equality of names.

law mp.seq_refl:
  for +a: String
  {String.eq(a, a) == True{} : Bool}

def mp.seq_refl(a):
  %Equal.sym(Cmp, String.order(a, a), EQ{}, mp.str_refl(a)) : {Cmp.is_eq(_) == True{} : Bool}
  {==}

law mp.is_eq_true:
  for c: Cmp
  for +e: {Cmp.is_eq(c) == True{} : Bool}
  {c == EQ{} : Cmp}

def mp.is_eq_true(c, e):
  match c:
    case LT{}:
      mp.tf_absurd({LT{} == EQ{} : Cmp}, Equal.sym(Bool, False{}, True{}, e))
    case EQ{}:
      {==}
    case GT{}:
      mp.tf_absurd({GT{} == EQ{} : Cmp}, Equal.sym(Bool, False{}, True{}, e))

law mp.seq_eq:
  for +a: String
  for +b: String
  for +e: {String.eq(a, b) == True{} : Bool}
  {a == b : String}

def mp.seq_eq(a, b, e):
  mp.str_eq(a, b, mp.is_eq_true(String.order(a, b), e))

law mp.and_l:
  for a: Bool
  for b: Bool
  for +e: {Bool.and(a, b) == True{} : Bool}
  {a == True{} : Bool}

def mp.and_l(a, b, e):
  match a:
    case False{}:
      mp.tf_absurd({False{} == True{} : Bool}, Equal.sym(Bool, False{}, True{}, e))
    case True{}:
      {==}

law mp.and_r:
  for a: Bool
  for b: Bool
  for +e: {Bool.and(a, b) == True{} : Bool}
  {b == True{} : Bool}

def mp.and_r(a, b, e):
  match a:
    case False{}:
      mp.tf_absurd({b == True{} : Bool}, Equal.sym(Bool, False{}, True{}, e))
    case True{}:
      e

law mp.nn_refl:
  for +n: M.NN
  {M.NN.eq(n, n) == True{} : Bool}

def mp.nn_refl(n):
  match n:
    case M.NN{ns, name}:
      %Equal.sym(Bool, String.eq(ns, ns), True{}, mp.seq_refl(ns)) : {Bool.and(_, String.eq(name, name)) == True{} : Bool}
      mp.seq_refl(name)

law mp.nn_eq:
  for +a: M.NN
  for +b: M.NN
  for +e: {M.NN.eq(a, b) == True{} : Bool}
  {a == b : M.NN}

def mp.nn_eq(a, b, e):
  match a b:
    case M.NN{an, am} M.NN{bn, bm}:
      %mp.seq_eq(an, bn, mp.and_l(String.eq(an, bn), String.eq(am, bm), e)) : {M.NN{an, am} == M.NN{_, bm} : M.NN}
      %mp.seq_eq(am, bm, mp.and_r(String.eq(an, bn), String.eq(am, bm), e)) : {M.NN{an, am} == M.NN{an, _} : M.NN}
      {==}

law mp.nm_same_refl:
  for +x: M.NM
  {M.NM.same(x, x) == True{} : Bool}

def mp.nm_same_refl(x):
  match x:
    case M.NM{g, v, h}:
      %Equal.sym(Bool, String.eq(g, g), True{}, mp.seq_refl(g)) : {Bool.and(_, Bool.and(M.NN.eq(v, v), M.NN.eq(h, h))) == True{} : Bool}
      %Equal.sym(Bool, M.NN.eq(v, v), True{}, mp.nn_refl(v)) : {Bool.and(_, M.NN.eq(h, h)) == True{} : Bool}
      mp.nn_refl(h)

law mp.nm_same_eq:
  for +x: M.NM
  for +y: M.NM
  for +e: {M.NM.same(x, y) == True{} : Bool}
  {x == y : M.NM}

def mp.nm_same_eq(x, y, e):
  match x y:
    case M.NM{xg, xv, xh} M.NM{yg, yv, yh}:
      %mp.seq_eq(xg, yg, mp.and_l(String.eq(xg, yg), Bool.and(M.NN.eq(xv, yv), M.NN.eq(xh, yh)), e)) : {M.NM{xg, xv, xh} == M.NM{_, yv, yh} : M.NM}
      %mp.nn_eq(xv, yv, mp.and_l(M.NN.eq(xv, yv), M.NN.eq(xh, yh), mp.and_r(String.eq(xg, yg), Bool.and(M.NN.eq(xv, yv), M.NN.eq(xh, yh)), e))) : {M.NM{xg, xv, xh} == M.NM{xg, _, yh} : M.NM}
      %mp.nn_eq(xh, yh, mp.and_r(M.NN.eq(xv, yv), M.NN.eq(xh, yh), mp.and_r(String.eq(xg, yg), Bool.and(M.NN.eq(xv, yv), M.NN.eq(xh, yh)), e))) : {M.NM{xg, xv, xh} == M.NM{xg, xv, _} : M.NM}
      {==}

def mp.ndisc(m: Maybe<&2, String>) -> Type:
  match m:
    case None{}:
      Empty
    case Some{x}:
      Unit

# Lookups.

law mp.or_none:
  for a: Maybe<&2, M.NN>
  {M.Look.or(a, None{}) == a : Maybe<&2, M.NN>}

def mp.or_none(a):
  match a:
    case None{}:
      {==}
    case Some{x}:
      {==}

law mp.or_assoc:
  for a: Maybe<&2, M.NN>
  for b: Maybe<&2, M.NN>
  for c: Maybe<&2, M.NN>
  {M.Look.or(a, M.Look.or(b, c)) == M.Look.or(M.Look.or(a, b), c) : Maybe<&2, M.NN>}

def mp.or_assoc(a, b, c):
  match a:
    case None{}:
      {==}
    case Some{x}:
      {==}

# A lookup in a list with one more mapping at the end.
law mp.look_app:
  for +d: M.Dir
  for +ms: List<&2, M.Mapping>
  for +m: M.Mapping
  for +g: String
  for +n: M.NN
  {M.Look.ms(d, List.append(&2, M.Mapping, ms, [m]), g, n) == M.Look.or(M.Look.ms(d, ms, g, n), M.Look.mapping(d, m, g, n)) : Maybe<&2, M.NN>}

def mp.look_app(d, ms, m, g, n):
  match ms:
    case Nil{}:
      mp.or_none(M.Look.mapping(d, m, g, n))
    case Con{x, t}:
      %Equal.sym(Maybe<&2, M.NN>, M.Look.ms(d, List.append(&2, M.Mapping, t, [m]), g, n), M.Look.or(M.Look.ms(d, t, g, n), M.Look.mapping(d, m, g, n)), mp.look_app(d, t, m, g, n)) :
        {M.Look.or(M.Look.mapping(d, x, g, n), _) == M.Look.or(M.Look.or(M.Look.mapping(d, x, g, n), M.Look.ms(d, t, g, n)), M.Look.mapping(d, m, g, n)) : Maybe<&2, M.NN>}
      mp.or_assoc(M.Look.mapping(d, x, g, n), M.Look.ms(d, t, g, n), M.Look.mapping(d, m, g, n))

# A name mapping answers its own key.
law mp.nm_hit:
  for +d: M.Dir
  for +g: String
  for +v: M.NN
  for +h: M.NN
  {M.Look.nm(d, M.NM{g, v, h}, g, M.Dir.key(d, v, h)) == Some{M.Dir.val(d, v, h)} : Maybe<&2, M.NN>}

def mp.nm_hit(d, g, v, h):
  %Equal.sym(Bool, String.eq(g, g), True{}, mp.seq_refl(g)) : {M.Look.when(Bool.and(_, M.NN.eq(M.Dir.key(d, v, h), M.Dir.key(d, v, h))), M.Dir.val(d, v, h)) == Some{M.Dir.val(d, v, h)} : Maybe<&2, M.NN>}
  %Equal.sym(Bool, M.NN.eq(M.Dir.key(d, v, h), M.Dir.key(d, v, h)), True{}, mp.nn_refl(M.Dir.key(d, v, h))) : {M.Look.when(_, M.Dir.val(d, v, h)) == Some{M.Dir.val(d, v, h)} : Maybe<&2, M.NN>}
  {==}

law mp.self_hit:
  for +d: M.Dir
  for +g: String
  for +v: M.NN
  for +h: M.NN
  {M.Look.mapping(d, M.Mapping{M.NM{g, v, h}, []}, g, M.Dir.key(d, v, h)) == Some{M.Dir.val(d, v, h)} : Maybe<&2, M.NN>}

def mp.self_hit(d, g, v, h):
  %Equal.sym(Maybe<&2, M.NN>, M.Look.nm(d, M.NM{g, v, h}, g, M.Dir.key(d, v, h)), Some{M.Dir.val(d, v, h)}, mp.nm_hit(d, g, v, h)) : {M.Look.or(_, None{}) == Some{M.Dir.val(d, v, h)} : Maybe<&2, M.NN>}
  {==}

law mp.some_or_r:
  for a: Maybe<&2, M.NN>
  for l: Maybe<&2, M.NN>
  for +e: {Maybe.is_some(&2, M.NN, l) == True{} : Bool}
  {Maybe.is_some(&2, M.NN, M.Look.or(a, l)) == True{} : Bool}

def mp.some_or_r(a, l, e):
  match a:
    case None{}:
      e
    case Some{x}:
      {==}

law mp.or_some_eq:
  for a: Maybe<&2, M.NN>
  for +w: M.NN
  for +e1: {M.Look.or(a, Some{w}) == Some{w} : Maybe<&2, M.NN>}
  for +e2: {Maybe.is_some(&2, M.NN, a) == True{} : Bool}
  {a == Some{w} : Maybe<&2, M.NN>}

def mp.or_some_eq(a, w, e1, e2):
  match a:
    case None{}:
      mp.tf_absurd({None{} == Some{w} : Maybe<&2, M.NN>}, Equal.sym(Bool, False{}, True{}, e2))
    case Some{y}:
      e1

# Conflict checks.

law mp.side_if:
  for b: Bool
  for +x: M.NN
  for +want: M.NN
  for +eb: {M.NN.eq(x, want) == b : Bool}
  for msg: String
  for rest: Maybe<&2, String>
  for +e: {M.Check.side.if(b, msg, rest) == None{} : Maybe<&2, String>}
  {M.Look.or(Some{x}, Some{want}) == Some{want} : Maybe<&2, M.NN>}

def mp.side_if(b, x, want, eb, msg, rest, e):
  match b:
    case True{}:
      %mp.nn_eq(x, want, eb) : {Some{x} == Some{_} : Maybe<&2, M.NN>}
      {==}
    case False{}:
      Empty.absurd({Some{x} == Some{want} : Maybe<&2, M.NN>}, (%e : mp.ndisc(_); Unit{}))

law mp.side_ok:
  for found: Maybe<&2, M.NN>
  for +g: String
  for +key: M.NN
  for +want: M.NN
  for +rest: Maybe<&2, String>
  for +e: {M.Check.side(found, g, key, want, rest) == None{} : Maybe<&2, String>}
  {M.Look.or(found, Some{want}) == Some{want} : Maybe<&2, M.NN>}

def mp.side_ok(found, g, key, want, rest, e):
  match found:
    case None{}:
      {==}
    case Some{+x}:
      mp.side_if(M.NN.eq(x, want), x, want, {==}, M.Check.msg(M.Obj.show(g, key), M.Obj.show(g, x), M.Obj.show(g, key), M.Obj.show(g, want)), rest, e)

law mp.side_rest_if:
  for b: Bool
  for msg: String
  for rest: Maybe<&2, String>
  for +e: {M.Check.side.if(b, msg, rest) == None{} : Maybe<&2, String>}
  {rest == None{} : Maybe<&2, String>}

def mp.side_rest_if(b, msg, rest, e):
  match b:
    case True{}:
      e
    case False{}:
      Empty.absurd({rest == None{} : Maybe<&2, String>}, (%e : mp.ndisc(_); Unit{}))

law mp.side_rest:
  for found: Maybe<&2, M.NN>
  for +g: String
  for +key: M.NN
  for +want: M.NN
  for +rest: Maybe<&2, String>
  for +e: {M.Check.side(found, g, key, want, rest) == None{} : Maybe<&2, String>}
  {rest == None{} : Maybe<&2, String>}

def mp.side_rest(found, g, key, want, rest, e):
  match found:
    case None{}:
      e
    case Some{+x}:
      mp.side_rest_if(M.NN.eq(x, want), M.Check.msg(M.Obj.show(g, key), M.Obj.show(g, x), M.Obj.show(g, key), M.Obj.show(g, want)), rest, e)

# No conflict: each side's lookup is absent or the recorded name.
law mp.conf_ok:
  for +d: M.Dir
  for +ms: List<&2, M.Mapping>
  for +g: String
  for +v: M.NN
  for +h: M.NN
  for +e: {M.Check.conflict(ms, M.NM{g, v, h}) == None{} : Maybe<&2, String>}
  {M.Look.or(M.Look.ms(d, ms, g, M.Dir.key(d, v, h)), Some{M.Dir.val(d, v, h)}) == Some{M.Dir.val(d, v, h)} : Maybe<&2, M.NN>}

def mp.conf_ok(d, ms, g, v, h, e):
  match d:
    case M.V2H{}:
      mp.side_ok(M.Look.ms(M.V2H{}, ms, g, v), g, v, h, None{}, mp.side_rest(M.Look.ms(M.H2V{}, ms, g, h), g, h, v, M.Check.side(M.Look.ms(M.V2H{}, ms, g, v), g, v, h, None{}), e))
    case M.H2V{}:
      mp.side_ok(M.Look.ms(M.H2V{}, ms, g, h), g, h, v, M.Check.side(M.Look.ms(M.V2H{}, ms, g, v), g, v, h, None{}), e)

# Finding a mapping by key.

def mp.fsame(f: Maybe<&2, M.Mapping>, k: M.NM) -> Bool:
  match f:
    case None{}:
      True{}
    case Some{M.Mapping{x, rs}}:
      M.NM.same(x, k)

def mp.fsome(f: Maybe<&2, M.Mapping>, l: Maybe<&2, M.NN>) -> Bool:
  match f:
    case None{}:
      True{}
    case Some{m}:
      Maybe.is_some(&2, M.NN, l)

def mp.for(a: Maybe<&2, M.Mapping>, b: Maybe<&2, M.Mapping>) -> Maybe<&2, M.Mapping>:
  match a:
    case None{}:
      b
    case Some{m}:
      Some{m}

law mp.find_same_if:
  for b: Bool
  for +y: M.NM
  for +ys: List<&2, M.NM>
  for +t: List<&2, M.Mapping>
  for +k: M.NM
  for +eb: {M.NM.same(y, k) == b : Bool}
  for +ih: {mp.fsame(M.Find.go(t, k), k) == True{} : Bool}
  {mp.fsame(M.Find.if(b, M.Mapping{y, ys}, M.Find.go(t, k)), k) == True{} : Bool}

def mp.find_same_if(b, y, ys, t, k, eb, ih):
  match b:
    case True{}:
      eb
    case False{}:
      ih

# The mapping found has the key looked for.
law mp.find_same:
  for +ms: List<&2, M.Mapping>
  for +k: M.NM
  {mp.fsame(M.Find.go(ms, k), k) == True{} : Bool}

def mp.find_same(ms, k):
  match ms:
    case Nil{}:
      {==}
    case Con{M.Mapping{+y, +ys}, +t}:
      mp.find_same_if(M.NM.same(y, k), y, ys, t, k, {==}, mp.find_same(t, k))

law mp.fsome_or:
  for f: Maybe<&2, M.Mapping>
  for a: Maybe<&2, M.NN>
  for l: Maybe<&2, M.NN>
  for +e: {mp.fsome(f, l) == True{} : Bool}
  {mp.fsome(f, M.Look.or(a, l)) == True{} : Bool}

def mp.fsome_or(f, a, l, e):
  match f:
    case None{}:
      {==}
    case Some{m}:
      mp.some_or_r(a, l, e)

law mp.find_look_if:
  for b: Bool
  for +d: M.Dir
  for +y: M.NM
  for +ys: List<&2, M.NM>
  for +t: List<&2, M.Mapping>
  for +g: String
  for +v: M.NN
  for +h: M.NN
  for +eb: {M.NM.same(y, M.NM{g, v, h}) == b : Bool}
  for +ih: {mp.fsome(M.Find.go(t, M.NM{g, v, h}), M.Look.ms(d, t, g, M.Dir.key(d, v, h))) == True{} : Bool}
  {mp.fsome(M.Find.if(b, M.Mapping{y, ys}, M.Find.go(t, M.NM{g, v, h})), M.Look.or(M.Look.mapping(d, M.Mapping{y, ys}, g, M.Dir.key(d, v, h)), M.Look.ms(d, t, g, M.Dir.key(d, v, h)))) == True{} : Bool}

def mp.find_look_if(b, d, y, ys, t, g, v, h, eb, ih):
  match b:
    case True{}:
      %Equal.sym(M.NM, y, M.NM{g, v, h}, mp.nm_same_eq(y, M.NM{g, v, h}, eb)) :
        {Maybe.is_some(&2, M.NN, M.Look.or(M.Look.mapping(d, M.Mapping{_, ys}, g, M.Dir.key(d, v, h)), M.Look.ms(d, t, g, M.Dir.key(d, v, h)))) == True{} : Bool}
      %Equal.sym(Maybe<&2, M.NN>, M.Look.nm(d, M.NM{g, v, h}, g, M.Dir.key(d, v, h)), Some{M.Dir.val(d, v, h)}, mp.nm_hit(d, g, v, h)) :
        {Maybe.is_some(&2, M.NN, M.Look.or(M.Look.or(_, M.Look.refs(d, ys, g, M.Dir.key(d, v, h))), M.Look.ms(d, t, g, M.Dir.key(d, v, h)))) == True{} : Bool}
      {==}
    case False{}:
      mp.fsome_or(M.Find.go(t, M.NM{g, v, h}), M.Look.mapping(d, M.Mapping{y, ys}, g, M.Dir.key(d, v, h)), M.Look.ms(d, t, g, M.Dir.key(d, v, h)), ih)

# A store holding a mapping with key (g, v, h) answers both of its names.
law mp.find_look:
  for +d: M.Dir
  for +ms: List<&2, M.Mapping>
  for +g: String
  for +v: M.NN
  for +h: M.NN
  {mp.fsome(M.Find.go(ms, M.NM{g, v, h}), M.Look.ms(d, ms, g, M.Dir.key(d, v, h))) == True{} : Bool}

def mp.find_look(d, ms, g, v, h):
  match ms:
    case Nil{}:
      {==}
    case Con{M.Mapping{+y, +ys}, +t}:
      mp.find_look_if(M.NM.same(y, M.NM{g, v, h}), d, y, ys, t, g, v, h, {==}, mp.find_look(d, t, g, v, h))

law mp.find_if_or:
  for b: Bool
  for m: M.Mapping
  for a: Maybe<&2, M.Mapping>
  for x: Maybe<&2, M.Mapping>
  {M.Find.if(b, m, mp.for(a, x)) == mp.for(M.Find.if(b, m, a), x) : Maybe<&2, M.Mapping>}

def mp.find_if_or(b, m, a, x):
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

law mp.for_none:
  for a: Maybe<&2, M.Mapping>
  {mp.for(a, None{}) == a : Maybe<&2, M.Mapping>}

def mp.for_none(a):
  match a:
    case None{}:
      {==}
    case Some{m}:
      {==}

# Finding in a list with one more mapping at the end.
law mp.find_app:
  for +ms: List<&2, M.Mapping>
  for +m: M.Mapping
  for +k: M.NM
  {M.Find.go(List.append(&2, M.Mapping, ms, [m]), k) == mp.for(M.Find.go(ms, k), M.Find.go([m], k)) : Maybe<&2, M.Mapping>}

def mp.find_app(ms, m, k):
  match ms:
    case Nil{}:
      {==}
    case Con{M.Mapping{+y, +ys}, +t}:
      %Equal.sym(Maybe<&2, M.Mapping>, M.Find.go(List.append(&2, M.Mapping, t, [m]), k), mp.for(M.Find.go(t, k), M.Find.go([m], k)), mp.find_app(t, m, k)) :
        {M.Find.if(M.NM.same(y, k), M.Mapping{y, ys}, _) == mp.for(M.Find.if(M.NM.same(y, k), M.Mapping{y, ys}, M.Find.go(t, k)), M.Find.go([m], k)) : Maybe<&2, M.Mapping>}
      mp.find_if_or(M.NM.same(y, k), M.Mapping{y, ys}, M.Find.go(t, k), M.Find.go([m], k))

# Lookup after record.

def mp.nn(ns: String, c: Char, t: String) -> M.NN:
  M.NN{ns, SCon{c, t}}

law mp.rec_f:
  for +d: M.Dir
  for +ms: List<&2, M.Mapping>
  for +g: String
  for +vns: String
  for +vc: Char
  for +vt: String
  for +hns: String
  for +hc: Char
  for +ht: String
  for f: Maybe<&2, M.Mapping>
  for +ef: {M.Find.go(ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) == f : Maybe<&2, M.Mapping>}
  for +ec: {M.Check.conflict(ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) == None{} : Maybe<&2, String>}
  {L.Laws.mappings.ok_look(d, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), M.Add.found(f, None{}, ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)))
    == Some{M.Dir.val(d, mp.nn(vns, vc, vt), mp.nn(hns, hc, ht))} : Maybe<&2, M.NN>}

def mp.rec_f(d, ms, g, vns, vc, vt, hns, hc, ht, f, ef, ec):
  match f:
    case None{}:
      %Equal.sym(Maybe<&2, M.NN>, M.Look.ms(d, List.append(&2, M.Mapping, ms, [M.Mapping{M.NM{g, mp.nn(vns, vc, vt), mp.nn(hns, hc, ht)}, []}]), g, M.Dir.key(d, mp.nn(vns, vc, vt), mp.nn(hns, hc, ht))),
          M.Look.or(M.Look.ms(d, ms, g, M.Dir.key(d, mp.nn(vns, vc, vt), mp.nn(hns, hc, ht))), M.Look.mapping(d, M.Mapping{M.NM{g, mp.nn(vns, vc, vt), mp.nn(hns, hc, ht)}, []}, g, M.Dir.key(d, mp.nn(vns, vc, vt), mp.nn(hns, hc, ht)))),
          mp.look_app(d, ms, M.Mapping{M.NM{g, mp.nn(vns, vc, vt), mp.nn(hns, hc, ht)}, []}, g, M.Dir.key(d, mp.nn(vns, vc, vt), mp.nn(hns, hc, ht)))) :
        {_ == Some{M.Dir.val(d, mp.nn(vns, vc, vt), mp.nn(hns, hc, ht))} : Maybe<&2, M.NN>}
      %Equal.sym(Maybe<&2, M.NN>, M.Look.mapping(d, M.Mapping{M.NM{g, mp.nn(vns, vc, vt), mp.nn(hns, hc, ht)}, []}, g, M.Dir.key(d, mp.nn(vns, vc, vt), mp.nn(hns, hc, ht))), Some{M.Dir.val(d, mp.nn(vns, vc, vt), mp.nn(hns, hc, ht))}, mp.self_hit(d, g, mp.nn(vns, vc, vt), mp.nn(hns, hc, ht))) :
        {M.Look.or(M.Look.ms(d, ms, g, M.Dir.key(d, mp.nn(vns, vc, vt), mp.nn(hns, hc, ht))), _) == Some{M.Dir.val(d, mp.nn(vns, vc, vt), mp.nn(hns, hc, ht))} : Maybe<&2, M.NN>}
      mp.conf_ok(d, ms, g, mp.nn(vns, vc, vt), mp.nn(hns, hc, ht), ec)
    case Some{M.Mapping{+x, +rs}}:
      %Equal.sym(Bool, M.NM.same(x, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)), True{}, (%ef : {mp.fsame(_, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) == True{} : Bool}; mp.find_same(ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)))) :
        {L.Laws.mappings.ok_look(d, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), M.Add.found.if(Bool.or(_, M.Upd.has(rs, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht))), None{}, ms, x, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)))
          == Some{M.Dir.val(d, mp.nn(vns, vc, vt), mp.nn(hns, hc, ht))} : Maybe<&2, M.NN>}
      mp.or_some_eq(M.Look.ms(d, ms, g, M.Dir.key(d, mp.nn(vns, vc, vt), mp.nn(hns, hc, ht))), M.Dir.val(d, mp.nn(vns, vc, vt), mp.nn(hns, hc, ht)),
        mp.conf_ok(d, ms, g, mp.nn(vns, vc, vt), mp.nn(hns, hc, ht), ec),
        (%ef : {mp.fsome(_, M.Look.ms(d, ms, g, M.Dir.key(d, mp.nn(vns, vc, vt), mp.nn(hns, hc, ht)))) == True{} : Bool}; mp.find_look(d, ms, g, mp.nn(vns, vc, vt), mp.nn(hns, hc, ht))))

law mp.rec_c:
  for +d: M.Dir
  for +ms: List<&2, M.Mapping>
  for +g: String
  for +vns: String
  for +vc: Char
  for +vt: String
  for +hns: String
  for +hc: Char
  for +ht: String
  for c: Maybe<&2, String>
  for +ec: {M.Check.conflict(ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) == c : Maybe<&2, String>}
  {L.Laws.mappings.ok_look(d, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), M.Add.checked(c, None{}, ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)))
    == Some{M.Dir.val(d, mp.nn(vns, vc, vt), mp.nn(hns, hc, ht))} : Maybe<&2, M.NN>}

def mp.rec_c(d, ms, g, vns, vc, vt, hns, hc, ht, c, ec):
  match c:
    case Some{x}:
      {==}
    case None{}:
      mp.rec_f(d, ms, g, vns, vc, vt, hns, hc, ht, M.Find.go(ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)), {==}, ec)

def L.mappings.record_lookup_virtual(ms, g, vns, vc, vt, hns, hc, ht):
  mp.rec_c(M.V2H{}, ms, g, vns, vc, vt, hns, hc, ht, M.Check.conflict(ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)), {==})

def L.mappings.record_lookup_host(ms, g, vns, vc, vt, hns, hc, ht):
  mp.rec_c(M.H2V{}, ms, g, vns, vc, vt, hns, hc, ht, M.Check.conflict(ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)), {==})

# Recording is idempotent.

# The conflict check passes again after the record appended the mapping.
law mp.conf_app:
  for +ms: List<&2, M.Mapping>
  for +g: String
  for +v: M.NN
  for +h: M.NN
  for +ec: {M.Check.conflict(ms, M.NM{g, v, h}) == None{} : Maybe<&2, String>}
  {M.Check.conflict(List.append(&2, M.Mapping, ms, [M.Mapping{M.NM{g, v, h}, []}]), M.NM{g, v, h}) == None{} : Maybe<&2, String>}

def mp.conf_app(ms, g, v, h, ec):
  %Equal.sym(Maybe<&2, M.NN>, M.Look.ms(M.H2V{}, List.append(&2, M.Mapping, ms, [M.Mapping{M.NM{g, v, h}, []}]), g, h), M.Look.or(M.Look.ms(M.H2V{}, ms, g, h), M.Look.mapping(M.H2V{}, M.Mapping{M.NM{g, v, h}, []}, g, h)), mp.look_app(M.H2V{}, ms, M.Mapping{M.NM{g, v, h}, []}, g, h)) :
    {M.Check.side(_, g, h, v, M.Check.side(M.Look.ms(M.V2H{}, List.append(&2, M.Mapping, ms, [M.Mapping{M.NM{g, v, h}, []}]), g, v), g, v, h, None{})) == None{} : Maybe<&2, String>}
  %Equal.sym(Maybe<&2, M.NN>, M.Look.mapping(M.H2V{}, M.Mapping{M.NM{g, v, h}, []}, g, h), Some{v}, mp.self_hit(M.H2V{}, g, v, h)) :
    {M.Check.side(M.Look.or(M.Look.ms(M.H2V{}, ms, g, h), _), g, h, v, M.Check.side(M.Look.ms(M.V2H{}, List.append(&2, M.Mapping, ms, [M.Mapping{M.NM{g, v, h}, []}]), g, v), g, v, h, None{})) == None{} : Maybe<&2, String>}
  %Equal.sym(Maybe<&2, M.NN>, M.Look.or(M.Look.ms(M.H2V{}, ms, g, h), Some{v}), Some{v}, mp.conf_ok(M.H2V{}, ms, g, v, h, ec)) :
    {M.Check.side(_, g, h, v, M.Check.side(M.Look.ms(M.V2H{}, List.append(&2, M.Mapping, ms, [M.Mapping{M.NM{g, v, h}, []}]), g, v), g, v, h, None{})) == None{} : Maybe<&2, String>}
  %Equal.sym(Bool, M.NN.eq(v, v), True{}, mp.nn_refl(v)) :
    {M.Check.side.if(_, M.Check.msg(M.Obj.show(g, h), M.Obj.show(g, v), M.Obj.show(g, h), M.Obj.show(g, v)), M.Check.side(M.Look.ms(M.V2H{}, List.append(&2, M.Mapping, ms, [M.Mapping{M.NM{g, v, h}, []}]), g, v), g, v, h, None{})) == None{} : Maybe<&2, String>}
  %Equal.sym(Maybe<&2, M.NN>, M.Look.ms(M.V2H{}, List.append(&2, M.Mapping, ms, [M.Mapping{M.NM{g, v, h}, []}]), g, v), M.Look.or(M.Look.ms(M.V2H{}, ms, g, v), M.Look.mapping(M.V2H{}, M.Mapping{M.NM{g, v, h}, []}, g, v)), mp.look_app(M.V2H{}, ms, M.Mapping{M.NM{g, v, h}, []}, g, v)) :
    {M.Check.side(_, g, v, h, None{}) == None{} : Maybe<&2, String>}
  %Equal.sym(Maybe<&2, M.NN>, M.Look.mapping(M.V2H{}, M.Mapping{M.NM{g, v, h}, []}, g, v), Some{h}, mp.self_hit(M.V2H{}, g, v, h)) :
    {M.Check.side(M.Look.or(M.Look.ms(M.V2H{}, ms, g, v), _), g, v, h, None{}) == None{} : Maybe<&2, String>}
  %Equal.sym(Maybe<&2, M.NN>, M.Look.or(M.Look.ms(M.V2H{}, ms, g, v), Some{h}), Some{h}, mp.conf_ok(M.V2H{}, ms, g, v, h, ec)) :
    {M.Check.side(_, g, v, h, None{}) == None{} : Maybe<&2, String>}
  %Equal.sym(Bool, M.NN.eq(h, h), True{}, mp.nn_refl(h)) :
    {M.Check.side.if(_, M.Check.msg(M.Obj.show(g, v), M.Obj.show(g, h), M.Obj.show(g, v), M.Obj.show(g, h)), None{}) == None{} : Maybe<&2, String>}
  {==}

# The mapping found has the key looked for (as a hypothesis on Find.go).
law mp.found_same:
  for +ms: List<&2, M.Mapping>
  for +k: M.NM
  for +x: M.NM
  for +rs: List<&2, M.NM>
  for +ef: {M.Find.go(ms, k) == Some{M.Mapping{x, rs}} : Maybe<&2, M.Mapping>}
  {M.NM.same(x, k) == True{} : Bool}

def mp.found_same(ms, k, x, rs, ef):
  %ef : {mp.fsame(_, k) == True{} : Bool}
  mp.find_same(ms, k)

law mp.idem_f:
  for +vf: Maybe<&2, String>
  for +ms: List<&2, M.Mapping>
  for +g: String
  for +vns: String
  for +vc: Char
  for +vt: String
  for +hns: String
  for +hc: Char
  for +ht: String
  for f: Maybe<&2, M.Mapping>
  for +ef: {M.Find.go(ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) == f : Maybe<&2, M.Mapping>}
  for +eb: {M.Verify.nm(vf, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) == True{} : Bool}
  for +ec: {M.Check.conflict(ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) == None{} : Maybe<&2, String>}
  for +eadd: {M.Store.add_reference(M.Store{vf, ms}, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) == M.Add.found(f, vf, ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) : M.Res}
  {L.Laws.mappings.again(M.Add.found(f, vf, ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) == M.Add.found(f, vf, ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) : M.Res}

def mp.idem_f(vf, ms, g, vns, vc, vt, hns, hc, ht, f, ef, eb, ec, eadd):
  match f:
    case Some{M.Mapping{+x, +rs}}:
      %Equal.sym(Bool, M.NM.same(x, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)), True{}, mp.found_same(ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), x, rs, ef)) :
        {L.Laws.mappings.again(M.Add.found.if(Bool.or(_, M.Upd.has(rs, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht))), vf, ms, x, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) == M.Add.found.if(Bool.or(_, M.Upd.has(rs, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht))), vf, ms, x, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) : M.Res}
      (%mp.found_same(ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), x, rs, ef) : {M.Store.add_reference(M.Store{vf, ms}, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) == M.Add.found.if(Bool.or(_, M.Upd.has(rs, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht))), vf, ms, x, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) : M.Res}; eadd)
    case None{}:
      %Equal.sym(Maybe<&2, String>, M.Check.conflict(List.append(&2, M.Mapping, ms, [M.Mapping{L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), []}]), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)), None{}, mp.conf_app(ms, g, mp.nn(vns, vc, vt), mp.nn(hns, hc, ht), ec)) :
        {M.Add.checked(_, vf, List.append(&2, M.Mapping, ms, [M.Mapping{L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), []}]), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) == M.Ok{M.Store{vf, List.append(&2, M.Mapping, ms, [M.Mapping{L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), []}])}} : M.Res}
      %Equal.sym(Bool, M.Verify.nm(vf, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)), True{}, eb) :
        {M.Add.verified(_, vf, List.append(&2, M.Mapping, ms, [M.Mapping{L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), []}]), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) == M.Ok{M.Store{vf, List.append(&2, M.Mapping, ms, [M.Mapping{L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), []}])}} : M.Res}
      %Equal.sym(Maybe<&2, M.Mapping>, M.Find.go(List.append(&2, M.Mapping, ms, [M.Mapping{L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), []}]), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)), mp.for(M.Find.go(ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)), M.Find.go([M.Mapping{L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), []}], L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht))), mp.find_app(ms, M.Mapping{L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), []}, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht))) :
        {M.Add.found(_, vf, List.append(&2, M.Mapping, ms, [M.Mapping{L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), []}]), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) == M.Ok{M.Store{vf, List.append(&2, M.Mapping, ms, [M.Mapping{L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), []}])}} : M.Res}
      %Equal.sym(Maybe<&2, M.Mapping>, M.Find.go(ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)), None{}, ef) : {M.Add.found(mp.for(_, M.Find.go([M.Mapping{L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), []}], L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht))), vf, List.append(&2, M.Mapping, ms, [M.Mapping{L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), []}]), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) == M.Ok{M.Store{vf, List.append(&2, M.Mapping, ms, [M.Mapping{L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), []}])}} : M.Res}
      %Equal.sym(Bool, M.NM.same(L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)), True{}, mp.nm_same_refl(L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht))) :
        {M.Add.found(M.Find.if(_, M.Mapping{L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), []}, None{}), vf, List.append(&2, M.Mapping, ms, [M.Mapping{L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), []}]), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) == M.Ok{M.Store{vf, List.append(&2, M.Mapping, ms, [M.Mapping{L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), []}])}} : M.Res}
      %Equal.sym(Bool, M.NM.same(L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)), True{}, mp.nm_same_refl(L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht))) :
        {M.Add.found.if(Bool.or(_, M.Upd.has([], L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht))), vf, List.append(&2, M.Mapping, ms, [M.Mapping{L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), []}]), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) == M.Ok{M.Store{vf, List.append(&2, M.Mapping, ms, [M.Mapping{L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), []}])}} : M.Res}
      {==}

law mp.idem_v:
  for +vf: Maybe<&2, String>
  for +ms: List<&2, M.Mapping>
  for +g: String
  for +vns: String
  for +vc: Char
  for +vt: String
  for +hns: String
  for +hc: Char
  for +ht: String
  for b: Bool
  for +eb: {M.Verify.nm(vf, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) == b : Bool}
  for +ec: {M.Check.conflict(ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) == None{} : Maybe<&2, String>}
  for +eadd: {M.Store.add_reference(M.Store{vf, ms}, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) == M.Add.verified(b, vf, ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) : M.Res}
  {L.Laws.mappings.again(M.Add.verified(b, vf, ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) == M.Add.verified(b, vf, ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) : M.Res}

def mp.idem_v(vf, ms, g, vns, vc, vt, hns, hc, ht, b, eb, ec, eadd):
  match b:
    case False{}:
      eadd
    case True{}:
      mp.idem_f(vf, ms, g, vns, vc, vt, hns, hc, ht, M.Find.go(ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)), {==}, eb, ec, eadd)

law mp.idem_c:
  for +vf: Maybe<&2, String>
  for +ms: List<&2, M.Mapping>
  for +g: String
  for +vns: String
  for +vc: Char
  for +vt: String
  for +hns: String
  for +hc: Char
  for +ht: String
  for c: Maybe<&2, String>
  for +ec: {M.Check.conflict(ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) == c : Maybe<&2, String>}
  for +eadd: {M.Store.add_reference(M.Store{vf, ms}, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) == M.Add.checked(c, vf, ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) : M.Res}
  {L.Laws.mappings.again(M.Add.checked(c, vf, ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) == M.Add.checked(c, vf, ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht), L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)) : M.Res}

def mp.idem_c(vf, ms, g, vns, vc, vt, hns, hc, ht, c, ec, eadd):
  match c:
    case Some{x}:
      {==}
    case None{}:
      mp.idem_v(vf, ms, g, vns, vc, vt, hns, hc, ht, M.Verify.nm(vf, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)), {==}, ec, eadd)

def L.mappings.record_idempotent(vf, ms, nm):
  match nm:
    case M.NM{g, M.NN{vns, SNil{}}, h}:
      {==}
    case M.NM{g, M.NN{vns, SCon{vc, vt}}, M.NN{hns, SNil{}}}:
      {==}
    case M.NM{g, M.NN{vns, SCon{vc, vt}}, M.NN{hns, SCon{hc, ht}}}:
          mp.idem_c(vf, ms, g, vns, vc, vt, hns, hc, ht, M.Check.conflict(ms, L.Laws.mappings.nm(g, vns, vc, vt, hns, hc, ht)), {==}, {==})

# Garbage collection.

law mp.gc_dead:
  for ms: List<&2, M.Mapping>
  {M.GC.go(ms, [], []) == [] : List<&2, M.Mapping>}

def mp.gc_dead(ms):
  match ms:
    case Nil{}:
      {==}
    case Con{M.Mapping{M.NM{g, v, h}, rs}, t}:
      mp.gc_dead(t)

def L.mappings.collect_dead(vf, ms):
  %Equal.sym(List<&2, M.Mapping>, M.GC.go(ms, [], []), [], mp.gc_dead(ms)) : {M.Store{vf, _} == M.Store{vf, []} : M.Store}
  {==}

law mp.gc_find_same:
  for sb: Bool
  for +x: M.NM
  for +rs: List<&2, M.NM>
  for +lv: List<&2, M.Obj>
  for +lh: List<&2, M.Obj>
  for +nm: M.NM
  for +rest: List<&2, M.Mapping>
  for +esb: {M.NM.same(x, nm) == sb : Bool}
  for +ekb: {M.Store.live(lv, lh, x) == True{} : Bool}
  for +dead: {M.Store.live(lv, lh, nm) == False{} : Bool}
  for +ih: {M.Find.go(rest, nm) == None{} : Maybe<&2, M.Mapping>}
  {M.Find.if(sb, M.Mapping{x, rs}, M.Find.go(rest, nm)) == None{} : Maybe<&2, M.Mapping>}

def mp.gc_find_same(sb, x, rs, lv, lh, nm, rest, esb, ekb, dead, ih):
  match sb:
    case False{}:
      ih
    case True{}:
      mp.tf_absurd({Some{M.Mapping{x, rs}} == None{} : Maybe<&2, M.Mapping>},
        Equal.trans(Bool, True{}, M.Store.live(lv, lh, nm), False{},
          Equal.sym(Bool, M.Store.live(lv, lh, nm), True{}, (%mp.nm_same_eq(x, nm, esb) : {M.Store.live(lv, lh, _) == True{} : Bool}; ekb)),
          dead))

law mp.gc_find_if:
  for kb: Bool
  for +x: M.NM
  for +rs: List<&2, M.NM>
  for +lv: List<&2, M.Obj>
  for +lh: List<&2, M.Obj>
  for +nm: M.NM
  for +rest: List<&2, M.Mapping>
  for +ekb: {M.Store.live(lv, lh, x) == kb : Bool}
  for +dead: {M.Store.live(lv, lh, nm) == False{} : Bool}
  for +ih: {M.Find.go(rest, nm) == None{} : Maybe<&2, M.Mapping>}
  {M.Find.go(M.GC.keep(kb, M.Mapping{x, rs}, rest), nm) == None{} : Maybe<&2, M.Mapping>}

def mp.gc_find_if(kb, x, rs, lv, lh, nm, rest, ekb, dead, ih):
  match kb:
    case False{}:
      ih
    case True{}:
      mp.gc_find_same(M.NM.same(x, nm), x, rs, lv, lh, nm, rest, {==}, ekb, dead, ih)

law mp.gc_find:
  for +ms: List<&2, M.Mapping>
  for +lv: List<&2, M.Obj>
  for +lh: List<&2, M.Obj>
  for +nm: M.NM
  for +dead: {M.Store.live(lv, lh, nm) == False{} : Bool}
  {M.Find.go(M.GC.go(ms, lv, lh), nm) == None{} : Maybe<&2, M.Mapping>}

def mp.gc_find(ms, lv, lh, nm, dead):
  match ms:
    case Nil{}:
      {==}
    case Con{M.Mapping{+x, +rs}, +t}:
      mp.gc_find_if(M.Store.live(lv, lh, x), x, rs, lv, lh, nm, M.GC.go(t, lv, lh), {==}, dead, mp.gc_find(t, lv, lh, nm, dead))

def L.mappings.collect_dead_mapping(vf, ms, live_v, live_h, nm, dead):
  %Equal.sym(Maybe<&2, M.Mapping>, M.Find.go(M.GC.go(ms, live_v, live_h), nm), None{}, mp.gc_find(ms, live_v, live_h, nm, dead)) : {Maybe.is_some(&2, M.Mapping, _) == False{} : Bool}
  {==}

def L.mappings.unreferenced_unused(s, g, n, none):
  %Equal.sym(List<&2, M.NM>, M.Store.references_to(s, g, n), [], none) : {Bool.not(List.is_empty(&2, M.NM, _)) == False{} : Bool}
  {==}

# Concrete laws: both sides compute.

def L.mappings.delete_reference_added():
  {==}

def L.mappings.delete_reference_deleted():
  {==}

def L.mappings.delete_reference_pod_refs():
  {==}

def L.mappings.delete_reference_pod_deleted():
  {==}

def L.mappings.delete_reference_other_pod():
  {==}

def L.mappings.delete_reference_secret_deleted():
  {==}

def L.mappings.watch_save():
  {==}

def L.mappings.watch_save_other():
  {==}

def L.mappings.watch_update():
  {==}

def L.mappings.watch_delete():
  {==}

def L.mappings.watch_delete_other():
  {==}

def L.mappings.watch_save_again():
  {==}

def L.mappings.watch_delete_reconstructed():
  {==}

def L.mappings.gc_recorded():
  {==}

def L.mappings.gc_referenced():
  {==}

def L.mappings.gc_collected():
  {==}

def L.mappings.gc_rerecorded():
  {==}

def L.mappings.gc_pod_alive():
  {==}

def L.mappings.gc_conflict_self():
  {==}

def L.mappings.gc_conflict_owner():
  {==}

def L.mappings.gc_pod_deleted():
  {==}

def L.mappings.store_virtual_to_host():
  {==}

def L.mappings.store_host_to_virtual():
  {==}

def L.mappings.store_host_to_virtual_empty():
  {==}

def L.mappings.store_inner():
  {==}

def L.mappings.store_not_added():
  {==}

def L.mappings.store_mapping():
  {==}

def L.mappings.store_mapping_refs():
  {==}

def L.mappings.store_collected():
  {==}

def L.mappings.store_collected_inner():
  {==}

def L.mappings.record_mapping_root_ca():
  {==}

def L.mappings.recorder_migrate_simple():
  {==}

def L.mappings.recorder_migrate_marker_missing():
  {==}

def L.mappings.recorder_migrate_wrong_namespace():
  {==}

def L.mappings.recorder_migrate_wrong_kind():
  {==}

def L.mappings.recorder_unrecorded_name():
  {==}

def L.mappings.recorder_unrecorded():
  {==}

def L.mappings.recorder_conflict_empty():
  {==}

def L.mappings.recorder_mapping():
  {==}

def L.mappings.recorder_another_host():
  {==}

def L.mappings.recorder_another_virtual():
  {==}

def L.mappings.recorder_other_conflict():
  {==}

def L.mappings.recorder_managed():
  {==}

def L.mappings.recorder_not_managed():
  {==}

def L.mappings.by_annotations_simple():
  {==}

def L.mappings.by_annotations_other_annotations():
  {==}

def L.mappings.by_annotations_wrong_kind():
  {==}

def L.mappings.by_annotations_wrong_host_namespace():
  {==}

def L.mappings.by_annotations_wrong_host_name():
  {==}

def L.mappings.by_annotations_name_missing():
  {==}

def L.mappings.by_store_simple():
  {==}

def L.mappings.by_store_wrong_name_mapping():
  {==}

def L.mappings.by_store_match_within_name():
  {==}

def L.mappings.by_store_match_multiple_within_name():
  {==}

def L.mappings.by_store_regular_name():
  {==}

def L.mappings.by_store_regular_name_in_between():
  {==}

def L.mappings.by_name_single_namespace():
  {==}

def L.mappings.by_name_host_name_short():
  {==}

def L.mappings.by_name_multi_namespace():
  {==}

def L.mappings.configmaps_from_pod():
  {==}

def L.mappings.secrets_from_ingress():
  {==}

def L.mappings.secrets_from_pod():
  {==}
