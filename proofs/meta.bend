import Base
import ../laws/meta.bend as L
import ../src/translate/meta.bend as M
import ../src/translate/names.bend as N

# Proofs of laws/meta.bend: `def L.<law>` for each law.
#
# The concrete laws compute. The general laws rest on a small kit: String.order
# is a strict total order (meta.str_flip, meta.str_eq, meta.str_trans), get
# commutes with insert, delete, union and the filters, and two canonical maps
# that agree on every key are equal (L.meta.ext). The label round trip is
# proved key by key: a key either lacks the vcluster.loft.sh/ prefix, is
# "release", or has the prefix; every translated key starts with
# vcluster.loft.sh/label- (meta.conv_lp).

# Concrete laws: both sides compute.

def L.meta.virtual_labels_nil():
  {==}

def L.meta.virtual_labels():
  {==}

def L.meta.not_rewriting_host():
  {==}

def L.meta.not_rewriting_virtual():
  {==}

def L.meta.not_rewriting_host_metadata():
  {==}

def L.meta.annotations_host():
  {==}

def L.meta.annotations_virtual():
  {==}

def L.meta.annotations_host_again():
  {==}

def L.meta.recursive_forward():
  {==}

def L.meta.recursive_back_10():
  {==}

def L.meta.recursive_back_9():
  {==}

def L.meta.recursive_back_8():
  {==}

def L.meta.recursive_back_7():
  {==}

def L.meta.recursive_back_6():
  {==}

def L.meta.recursive_back_5():
  {==}

def L.meta.recursive_back_4():
  {==}

def L.meta.recursive_back_3():
  {==}

def L.meta.recursive_back_2():
  {==}

def L.meta.recursive_back_1():
  {==}

def L.meta.recursive_back_0():
  {==}

def L.meta.labels_map_host():
  {==}

def L.meta.labels_map_virtual():
  {==}

def L.meta.labels_map_host_again():
  {==}

def L.meta.labels_map_host_deleted():
  {==}

def L.meta.label_selector_host():
  {==}

def L.meta.label_selector_virtual():
  {==}

def L.meta.label_selector_host_again():
  {==}

def L.meta.annotations_sync_excluded():
  {==}

def L.meta.annotations_sync():
  {==}

def L.meta.annotations_sync_create_virtual():
  {==}

def L.meta.annotations_sync_create_host():
  {==}

def L.meta.tkeys_convert(vc):
  {==}
def meta.flip(c: Cmp) -> Cmp:
  match c:
    case LT{}:
      GT{}
    case EQ{}:
      EQ{}
    case GT{}:
      LT{}

law meta.bool_flip:
  for a: Bool
  for b: Bool
  {Bool.cmp(b, a) == meta.flip(Bool.cmp(a, b)) : Cmp}

def meta.bool_flip(a, b):
  match a b:
    case False{} False{}:
      {==}
    case False{} True{}:
      {==}
    case True{} False{}:
      {==}
    case True{} True{}:
      {==}

law meta.fin_flip:
  for ab: Bool
  for bb: Bool
  for t: Cmp
  {Word.cmp.fin(bb, ab, meta.flip(t)) == meta.flip(Word.cmp.fin(ab, bb, t)) : Cmp}

def meta.fin_flip(ab, bb, t):
  match t:
    case LT{}:
      {==}
    case EQ{}:
      meta.bool_flip(ab, bb)
    case GT{}:
      {==}

law meta.word_flip:
  for +n: Nat
  for +a: Word(n)
  for +b: Word(n)
  {Word.cmp(n, b, a) == meta.flip(Word.cmp(n, a, b)) : Cmp}

def meta.word_flip(n, a, b):
  match n:
    case 0n:
      {==}
    case 1n+p:
      match a b:
        case WCon{ab, at} WCon{bb, bt}:
          %Equal.sym(Cmp, Word.cmp(p, bt, at), meta.flip(Word.cmp(p, at, bt)), meta.word_flip(p, at, bt)) : {Word.cmp.fin(bb, ab, _) == meta.flip(Word.cmp.fin(ab, bb, Word.cmp(p, at, bt))) : Cmp}
          meta.fin_flip(ab, bb, Word.cmp(p, at, bt))


def meta.tcomb(a: Cmp, b: Cmp) -> Cmp:
  match a:
    case LT{}:
      LT{}
    case EQ{}:
      b
    case GT{}:
      GT{}

def meta.cdisc_lt(c: Cmp) -> Type:
  match c:
    case LT{}:
      Empty
    case EQ{}:
      Unit
    case GT{}:
      Unit

def meta.cdisc_eq(c: Cmp) -> Type:
  match c:
    case LT{}:
      Unit
    case EQ{}:
      Empty
    case GT{}:
      Unit

def meta.bdisc(b: Bool) -> Type:
  match b:
    case False{}:
      Empty
    case True{}:
      Unit

def meta.tf_empty(e: {True{} == False{} : Bool}) -> Empty:
  %e : meta.bdisc(_)
  Unit{}

# True is not False.
def meta.tf_absurd(-A: Type, e: {True{} == False{} : Bool}) -> A:
  Empty.absurd(A, (%e : meta.bdisc(_); Unit{}))

# x == LT with x not LT.
def meta.ne_lt(-A: Type, -x: Cmp, e: {x == LT{} : Cmp}, d: meta.cdisc_lt(x)) -> A:
  Empty.absurd(A, (%e : meta.cdisc_lt(_); d))

def meta.ne_eq(-A: Type, -x: Cmp, e: {x == EQ{} : Cmp}, d: meta.cdisc_eq(x)) -> A:
  Empty.absurd(A, (%e : meta.cdisc_eq(_); d))

law meta.bool_refl:
  for a: Bool
  {Bool.cmp(a, a) == EQ{} : Cmp}

def meta.bool_refl(a):
  match a:
    case False{}:
      {==}
    case True{}:
      {==}

law meta.word_refl:
  for +n: Nat
  for +a: Word(n)
  {Word.cmp(n, a, a) == EQ{} : Cmp}

def meta.word_refl(n, a):
  match n:
    case 0n:
      {==}
    case 1n+p:
      match a:
        case WCon{ab, at}:
          %Equal.sym(Cmp, Word.cmp(p, at, at), EQ{}, meta.word_refl(p, at)) : {Word.cmp.fin(ab, ab, _) == EQ{} : Cmp}
          meta.bool_refl(ab)

# fin(ab, bb, t) == EQ forces t == EQ.
law meta.fin_eq_t:
  for ab: Bool
  for bb: Bool
  for t: Cmp
  for e: {Word.cmp.fin(ab, bb, t) == EQ{} : Cmp}
  {t == EQ{} : Cmp}

def meta.fin_eq_t(ab, bb, t, e):
  match t:
    case LT{}:
      meta.ne_eq({LT{} == EQ{} : Cmp}, LT{}, e, Unit{})
    case EQ{}:
      {==}
    case GT{}:
      meta.ne_eq({GT{} == EQ{} : Cmp}, GT{}, e, Unit{})

law meta.bool_eq:
  for a: Bool
  for b: Bool
  for e: {Bool.cmp(a, b) == EQ{} : Cmp}
  {a == b : Bool}

def meta.bool_eq(a, b, e):
  match a b:
    case False{} False{}:
      {==}
    case False{} True{}:
      meta.ne_eq({False{} == True{} : Bool}, LT{}, e, Unit{})
    case True{} False{}:
      meta.ne_eq({True{} == False{} : Bool}, GT{}, e, Unit{})
    case True{} True{}:
      {==}

law meta.fin_eq_b:
  for ab: Bool
  for bb: Bool
  for t: Cmp
  for e: {Word.cmp.fin(ab, bb, t) == EQ{} : Cmp}
  {ab == bb : Bool}

def meta.fin_eq_b(ab, bb, t, e):
  match t:
    case LT{}:
      meta.ne_eq({ab == bb : Bool}, LT{}, e, Unit{})
    case EQ{}:
      meta.bool_eq(ab, bb, e)
    case GT{}:
      meta.ne_eq({ab == bb : Bool}, GT{}, e, Unit{})

law meta.word_eq:
  for +n: Nat
  for +a: Word(n)
  for +b: Word(n)
  for +e: {Word.cmp(n, a, b) == EQ{} : Cmp}
  {a == b : Word(n)}

def meta.word_eq(n, a, b, e):
  match n:
    case 0n:
      match a b:
        case WNil{} WNil{}:
          {==}
    case 1n+p:
      match a b:
        case WCon{ab, at} WCon{bb, bt}:
          %meta.fin_eq_b(ab, bb, Word.cmp(p, at, bt), e) : {WCon{ab, at} == WCon{_, bt} : Word(1n+p)}
          %meta.word_eq(p, at, bt, meta.fin_eq_t(ab, bb, Word.cmp(p, at, bt), e)) : {WCon{ab, at} == WCon{ab, _} : Word(1n+p)}
          {==}

law meta.fin_not_gt:
  for ab: Bool
  for bb: Bool
  for t: Cmp
  for e: {Cmp.is_gt(Word.cmp.fin(ab, bb, t)) == False{} : Bool}
  {Cmp.is_gt(t) == False{} : Bool}

def meta.fin_not_gt(ab, bb, t, e):
  match t:
    case LT{}:
      {==}
    case EQ{}:
      {==}
    case GT{}:
      meta.tf_absurd({True{} == False{} : Bool}, e)

law meta.fin_comb:
  for r1: Cmp
  for r2: Cmp
  for a0: Bool
  for b0: Bool
  for c0: Bool
  for n1: {Cmp.is_gt(Word.cmp.fin(a0, b0, r1)) == False{} : Bool}
  for n2: {Cmp.is_gt(Word.cmp.fin(b0, c0, r2)) == False{} : Bool}
  {Word.cmp.fin(a0, c0, meta.tcomb(r1, r2)) == meta.tcomb(Word.cmp.fin(a0, b0, r1), Word.cmp.fin(b0, c0, r2)) : Cmp}

def meta.fin_comb(r1, r2, a0, b0, c0, n1, n2):
  match r1 r2:
    case LT{} LT{}:
      {==}
    case LT{} EQ{}:
      {==}
    case LT{} GT{}:
      meta.tf_absurd({LT{} == LT{} : Cmp}, n2)
    case EQ{} LT{}:
      match a0 b0:
        case False{} False{}:
          {==}
        case False{} True{}:
          {==}
        case True{} False{}:
          meta.tf_absurd({LT{} == GT{} : Cmp}, n1)
        case True{} True{}:
          {==}
    case EQ{} EQ{}:
      match a0 b0 c0:
        case False{} False{} False{}:
          {==}
        case False{} False{} True{}:
          {==}
        case False{} True{} False{}:
          meta.tf_absurd({EQ{} == meta.tcomb(LT{}, GT{}) : Cmp}, n2)
        case False{} True{} True{}:
          {==}
        case True{} False{} False{}:
          meta.tf_absurd({GT{} == GT{} : Cmp}, n1)
        case True{} False{} True{}:
          meta.tf_absurd({EQ{} == GT{} : Cmp}, n1)
        case True{} True{} False{}:
          meta.tf_absurd({GT{} == GT{} : Cmp}, n2)
        case True{} True{} True{}:
          {==}
    case EQ{} GT{}:
      meta.tf_absurd({Word.cmp.fin(a0, c0, GT{}) == meta.tcomb(Bool.cmp(a0, b0), GT{}) : Cmp}, n2)
    case GT{} _:
      meta.tf_absurd({GT{} == GT{} : Cmp}, n1)

law meta.word_comb:
  for +n: Nat
  for +a: Word(n)
  for +b: Word(n)
  for +c: Word(n)
  for +n1: {Cmp.is_gt(Word.cmp(n, a, b)) == False{} : Bool}
  for +n2: {Cmp.is_gt(Word.cmp(n, b, c)) == False{} : Bool}
  {Word.cmp(n, a, c) == meta.tcomb(Word.cmp(n, a, b), Word.cmp(n, b, c)) : Cmp}

def meta.word_comb(n, a, b, c, n1, n2):
  match n:
    case 0n:
      {==}
    case 1n+p:
      match a b c:
        case WCon{a0, at} WCon{b0, bt} WCon{c0, ct}:
          %Equal.sym(Cmp, Word.cmp(p, at, ct), meta.tcomb(Word.cmp(p, at, bt), Word.cmp(p, bt, ct)),
            meta.word_comb(p, at, bt, ct,
              meta.fin_not_gt(a0, b0, Word.cmp(p, at, bt), n1),
              meta.fin_not_gt(b0, c0, Word.cmp(p, bt, ct), n2))) :
            {Word.cmp.fin(a0, c0, _) == meta.tcomb(Word.cmp.fin(a0, b0, Word.cmp(p, at, bt)), Word.cmp.fin(b0, c0, Word.cmp(p, bt, ct))) : Cmp}
          meta.fin_comb(Word.cmp(p, at, bt), Word.cmp(p, bt, ct), a0, b0, c0, n1, n2)

law meta.u32_flip:
  for a: U32
  for b: U32
  {U32.cmp(b, a) == meta.flip(U32.cmp(a, b)) : Cmp}

def meta.u32_flip(a, b):
  match a b:
    case U32{x} U32{y}:
      meta.word_flip(32n, x, y)

law meta.u32_refl:
  for a: U32
  {U32.cmp(a, a) == EQ{} : Cmp}

def meta.u32_refl(a):
  match a:
    case U32{x}:
      meta.word_refl(32n, x)

law meta.u32_eq:
  for a: U32
  for b: U32
  for e: {U32.cmp(a, b) == EQ{} : Cmp}
  {a == b : U32}

def meta.u32_eq(a, b, e):
  match a b:
    case U32{x} U32{y}:
      %meta.word_eq(32n, x, y, e) : {U32{x} == U32{_} : U32}
      {==}

law meta.u32_comb:
  for a: U32
  for b: U32
  for c: U32
  for n1: {Cmp.is_gt(U32.cmp(a, b)) == False{} : Bool}
  for n2: {Cmp.is_gt(U32.cmp(b, c)) == False{} : Bool}
  {U32.cmp(a, c) == meta.tcomb(U32.cmp(a, b), U32.cmp(b, c)) : Cmp}

def meta.u32_comb(a, b, c, n1, n2):
  match a b c:
    case U32{x} U32{y} U32{z}:
      meta.word_comb(32n, x, y, z, n1, n2)

# Strings: String.order is a strict total order.

law meta.go_lt:
  for a: String
  for b: String
  {String.order.go(a, b, LT{}) == LT{} : Cmp}

def meta.go_lt(a, b):
  match a b:
    case SNil{} SNil{}:
      {==}
    case SNil{} SCon{Chr{x}, t}:
      {==}
    case SCon{Chr{x}, t} SNil{}:
      {==}
    case SCon{Chr{x}, t1} SCon{Chr{y}, t2}:
          {==}

law meta.go_gt:
  for a: String
  for b: String
  {String.order.go(a, b, GT{}) == GT{} : Cmp}

def meta.go_gt(a, b):
  match a b:
    case SNil{} SNil{}:
      {==}
    case SNil{} SCon{Chr{x}, t}:
      {==}
    case SCon{Chr{x}, t} SNil{}:
      {==}
    case SCon{Chr{x}, t1} SCon{Chr{y}, t2}:
          {==}

law meta.str_flip:
  for +a: String
  for +b: String
  for c: Cmp
  {String.order.go(b, a, meta.flip(c)) == meta.flip(String.order.go(a, b, c)) : Cmp}

def meta.str_flip(a, b, c):
  match a b:
    case SNil{} SNil{}:
      match c:
        case LT{}:
          {==}
        case EQ{}:
          {==}
        case GT{}:
          {==}
    case SNil{} SCon{Chr{x}, t}:
      match c:
        case LT{}:
          {==}
        case EQ{}:
          {==}
        case GT{}:
          {==}
    case SCon{Chr{x}, t} SNil{}:
      match c:
        case LT{}:
          {==}
        case EQ{}:
          {==}
        case GT{}:
          {==}
    case SCon{Chr{x}, t1} SCon{Chr{y}, t2}:
      match c:
        case LT{}:
          {==}
        case EQ{}:
          %Equal.sym(Cmp, U32.cmp(y, x), meta.flip(U32.cmp(x, y)), meta.u32_flip(x, y)) :
            {String.order.go(t2, t1, _) == meta.flip(String.order.go(t1, t2, U32.cmp(x, y))) : Cmp}
          meta.str_flip(t1, t2, U32.cmp(x, y))
        case GT{}:
          {==}

law meta.str_refl:
  for +a: String
  {String.order(a, a) == EQ{} : Cmp}

def meta.str_refl(a):
  match a:
    case SNil{}:
      {==}
    case SCon{Chr{x}, t}:
      %Equal.sym(Cmp, U32.cmp(x, x), EQ{}, meta.u32_refl(x)) : {String.order.go(t, t, _) == EQ{} : Cmp}
      meta.str_refl(t)

# go(a, b, c) == EQ forces c == EQ.
law meta.go_eq_c:
  for a: String
  for b: String
  for c: Cmp
  for e: {String.order.go(a, b, c) == EQ{} : Cmp}
  {c == EQ{} : Cmp}

def meta.go_eq_c(a, b, c, e):
  match c:
    case LT{}:
      meta.ne_eq({LT{} == EQ{} : Cmp}, LT{}, Equal.trans(Cmp, LT{}, String.order.go(a, b, LT{}), EQ{}, Equal.sym(Cmp, String.order.go(a, b, LT{}), LT{}, meta.go_lt(a, b)), e), Unit{})
    case EQ{}:
      {==}
    case GT{}:
      meta.ne_eq({GT{} == EQ{} : Cmp}, GT{}, Equal.trans(Cmp, GT{}, String.order.go(a, b, GT{}), EQ{}, Equal.sym(Cmp, String.order.go(a, b, GT{}), GT{}, meta.go_gt(a, b)), e), Unit{})

law meta.str_eq_go:
  for +a: String
  for +b: String
  for +c: Cmp
  for +e: {String.order.go(a, b, c) == EQ{} : Cmp}
  {a == b : String}

def meta.str_eq_go(a, b, c, e):
  match a b:
    case SNil{} SNil{}:
      {==}
    case SNil{} SCon{Chr{x}, t}:
      match c:
        case LT{}:
          meta.ne_eq({SNil{} == SCon{Chr{x}, t} : String}, LT{}, e, Unit{})
        case EQ{}:
          meta.ne_eq({SNil{} == SCon{Chr{x}, t} : String}, LT{}, e, Unit{})
        case GT{}:
          meta.ne_eq({SNil{} == SCon{Chr{x}, t} : String}, GT{}, e, Unit{})
    case SCon{Chr{x}, t} SNil{}:
      match c:
        case LT{}:
          meta.ne_eq({SCon{Chr{x}, t} == SNil{} : String}, LT{}, e, Unit{})
        case EQ{}:
          meta.ne_eq({SCon{Chr{x}, t} == SNil{} : String}, GT{}, e, Unit{})
        case GT{}:
          meta.ne_eq({SCon{Chr{x}, t} == SNil{} : String}, GT{}, e, Unit{})
    case SCon{Chr{x}, t1} SCon{Chr{y}, t2}:
      match c:
        case LT{}:
          meta.ne_eq({SCon{Chr{x}, t1} == SCon{Chr{y}, t2} : String}, LT{}, e, Unit{})
        case EQ{}:
          %meta.u32_eq(x, y, meta.go_eq_c(t1, t2, U32.cmp(x, y), e)) : {SCon{Chr{x}, t1} == SCon{Chr{_}, t2} : String}
          %meta.str_eq_go(t1, t2, U32.cmp(x, y), e) : {SCon{Chr{x}, t1} == SCon{Chr{x}, _} : String}
          {==}
        case GT{}:
          meta.ne_eq({SCon{Chr{x}, t1} == SCon{Chr{y}, t2} : String}, GT{}, e, Unit{})

law meta.str_eq:
  for +a: String
  for +b: String
  for +e: {String.order(a, b) == EQ{} : Cmp}
  {a == b : String}

def meta.str_eq(a, b, e):
  meta.str_eq_go(a, b, EQ{}, e)

law meta.go_not_gt:
  for a: String
  for b: String
  for c: Cmp
  for e: {String.order.go(a, b, c) == LT{} : Cmp}
  {Cmp.is_gt(c) == False{} : Bool}

def meta.go_not_gt(a, b, c, e):
  match c:
    case LT{}:
      {==}
    case EQ{}:
      {==}
    case GT{}:
      meta.ne_lt({True{} == False{} : Bool}, GT{}, Equal.trans(Cmp, GT{}, String.order.go(a, b, GT{}), LT{}, Equal.sym(Cmp, String.order.go(a, b, GT{}), GT{}, meta.go_gt(a, b)), e), Unit{})

law meta.str_trans_go:
  for +a: String
  for +b: String
  for +c: String
  for +c1: Cmp
  for +c2: Cmp
  for +h1: {String.order.go(a, b, c1) == LT{} : Cmp}
  for +h2: {String.order.go(b, c, c2) == LT{} : Cmp}
  {String.order.go(a, c, meta.tcomb(c1, c2)) == LT{} : Cmp}

def meta.str_trans_go(a, b, c, c1, c2, h1, h2):
  match a b c:
    case SNil{} SNil{} SNil{}:
      match c1 c2:
        case LT{} _:
          {==}
        case EQ{} LT{}:
          {==}
        case EQ{} EQ{}:
          meta.ne_lt({EQ{} == LT{} : Cmp}, EQ{}, h1, Unit{})
        case EQ{} GT{}:
          meta.ne_lt({GT{} == LT{} : Cmp}, GT{}, h2, Unit{})
        case GT{} _:
          meta.ne_lt({GT{} == LT{} : Cmp}, GT{}, h1, Unit{})
    case SNil{} SNil{} SCon{Chr{z}, t3}:
      match c1 c2:
        case LT{} _:
          {==}
        case EQ{} LT{}:
          {==}
        case EQ{} EQ{}:
          {==}
        case EQ{} GT{}:
          meta.ne_lt({GT{} == LT{} : Cmp}, GT{}, h2, Unit{})
        case GT{} _:
          meta.ne_lt({GT{} == LT{} : Cmp}, GT{}, h1, Unit{})
    case SNil{} SCon{Chr{y}, t2} SNil{}:
      match c1 c2:
        case LT{} _:
          {==}
        case EQ{} LT{}:
          {==}
        case EQ{} EQ{}:
          meta.ne_lt({EQ{} == LT{} : Cmp}, GT{}, h2, Unit{})
        case EQ{} GT{}:
          meta.ne_lt({GT{} == LT{} : Cmp}, GT{}, h2, Unit{})
        case GT{} _:
          meta.ne_lt({GT{} == LT{} : Cmp}, GT{}, h1, Unit{})
    case SNil{} SCon{Chr{y}, t2} SCon{Chr{z}, t3}:
      match c1 c2:
        case LT{} _:
          {==}
        case EQ{} LT{}:
          {==}
        case EQ{} EQ{}:
          {==}
        case EQ{} GT{}:
          meta.ne_lt({GT{} == LT{} : Cmp}, GT{}, h2, Unit{})
        case GT{} _:
          meta.ne_lt({GT{} == LT{} : Cmp}, GT{}, h1, Unit{})
    case SCon{Chr{x}, t1} SNil{} _:
      match c1:
        case LT{}:
          meta.go_lt(SCon{Chr{x}, t1}, c)
        case EQ{}:
          meta.ne_lt({String.order.go(SCon{Chr{x}, t1}, c, meta.tcomb(EQ{}, c2)) == LT{} : Cmp}, GT{}, h1, Unit{})
        case GT{}:
          meta.ne_lt({String.order.go(SCon{Chr{x}, t1}, c, GT{}) == LT{} : Cmp}, GT{}, h1, Unit{})
    case SCon{Chr{x}, t1} SCon{Chr{y}, t2} SNil{}:
      match c1 c2:
        case LT{} _:
          {==}
        case EQ{} LT{}:
          {==}
        case EQ{} EQ{}:
          meta.ne_lt({GT{} == LT{} : Cmp}, GT{}, h2, Unit{})
        case EQ{} GT{}:
          meta.ne_lt({GT{} == LT{} : Cmp}, GT{}, h2, Unit{})
        case GT{} _:
          meta.ne_lt({GT{} == LT{} : Cmp}, GT{}, h1, Unit{})
    case SCon{Chr{x}, t1} SCon{Chr{y}, t2} SCon{Chr{z}, t3}:
      match c1 c2:
        case LT{} _:
          {==}
        case EQ{} LT{}:
          {==}
        case EQ{} EQ{}:
          %Equal.sym(Cmp, U32.cmp(x, z), meta.tcomb(U32.cmp(x, y), U32.cmp(y, z)),
            meta.u32_comb(x, y, z, meta.go_not_gt(t1, t2, U32.cmp(x, y), h1), meta.go_not_gt(t2, t3, U32.cmp(y, z), h2))) :
            {String.order.go(t1, t3, _) == LT{} : Cmp}
          meta.str_trans_go(t1, t2, t3, U32.cmp(x, y), U32.cmp(y, z), h1, h2)
        case EQ{} GT{}:
          meta.ne_lt({String.order.go(SCon{Chr{x}, t1}, SCon{Chr{z}, t3}, GT{}) == LT{} : Cmp}, GT{}, h2, Unit{})
        case GT{} _:
          meta.ne_lt({String.order.go(SCon{Chr{x}, t1}, SCon{Chr{z}, t3}, GT{}) == LT{} : Cmp}, GT{}, h1, Unit{})

law meta.str_trans:
  for +a: String
  for +b: String
  for +c: String
  for +h1: {String.order(a, b) == LT{} : Cmp}
  for +h2: {String.order(b, c) == LT{} : Cmp}
  {String.order(a, c) == LT{} : Cmp}

def meta.str_trans(a, b, c, h1, h2):
  meta.str_trans_go(a, b, c, EQ{}, EQ{}, h1, h2)

# Bool helpers.

law meta.and_l:
  for a: Bool
  for b: Bool
  for h: {Bool.and(a, b) == True{} : Bool}
  {a == True{} : Bool}

def meta.and_l(a, b, h):
  match a:
    case True{}:
      {==}
    case False{}:
      h

law meta.and_r:
  for a: Bool
  for b: Bool
  for h: {Bool.and(a, b) == True{} : Bool}
  {b == True{} : Bool}

def meta.and_r(a, b, h):
  match a:
    case True{}:
      h
    case False{}:
      meta.tf_absurd({b == True{} : Bool}, Equal.sym(Bool, False{}, True{}, h))

law meta.and_i:
  for a: Bool
  for b: Bool
  for ha: {a == True{} : Bool}
  for hb: {b == True{} : Bool}
  {Bool.and(a, b) == True{} : Bool}

def meta.and_i(a, b, ha, hb):
  %Equal.sym(Bool, a, True{}, ha) : {Bool.and(_, b) == True{} : Bool}
  hb

# Maps: get.

# q differs from k and k equals kk, so q differs from kk.
law meta.ne_move:
  for +q: String
  for +k: String
  for +kk: String
  for +e: {String.order(k, kk) == EQ{} : Cmp}
  for +h: {Cmp.is_eq(String.order(q, k)) == False{} : Bool}
  {Cmp.is_eq(String.order(q, kk)) == False{} : Bool}

def meta.ne_move(q, k, kk, e, h):
  %meta.str_eq(k, kk, e) : {Cmp.is_eq(String.order(q, _)) == False{} : Bool}
  h

law meta.get_if_ne:
  for c: Cmp
  for v: String
  for rec: Maybe<&2, String>
  for h: {Cmp.is_eq(c) == False{} : Bool}
  {M.Meta.get.if(c, v, rec) == rec : Maybe<&2, String>}

def meta.get_if_ne(c, v, rec, h):
  match c:
    case LT{}:
      {==}
    case EQ{}:
      meta.tf_absurd({Some{v} == rec : Maybe<&2, String>}, h)
    case GT{}:
      {==}

law meta.get_insert_same_go:
  for c: Cmp
  for +kk: String
  for vv: String
  for +k: String
  for +v: String
  for r: +List<M.KV>
  for e: {String.order(k, kk) == c : Cmp}
  for ih: {M.Meta.get(k, M.Meta.insert(k, v, r)) == Some{v} : Maybe<&2, String>}
  {M.Meta.get(k, M.Meta.insert.if(c, kk, vv, k, v, r, M.Meta.insert(k, v, r))) == Some{v} : Maybe<&2, String>}

def meta.get_insert_same_go(c, kk, vv, k, v, r, e, ih):
  match c:
    case LT{}:
      %Equal.sym(Cmp, String.order(k, k), EQ{}, meta.str_refl(k)) : {M.Meta.get.if(_, v, M.Meta.get(k, M.KV{kk, vv} <> r)) == Some{v} : Maybe<&2, String>}
      {==}
    case EQ{}:
      %Equal.sym(Cmp, String.order(k, kk), EQ{}, e) : {M.Meta.get.if(_, v, M.Meta.get(k, r)) == Some{v} : Maybe<&2, String>}
      {==}
    case GT{}:
      %Equal.sym(Cmp, String.order(k, kk), GT{}, e) : {M.Meta.get.if(_, vv, M.Meta.get(k, M.Meta.insert(k, v, r))) == Some{v} : Maybe<&2, String>}
      ih

def L.meta.get_insert_same(k, v, m):
  match m:
    case Nil{}:
      %Equal.sym(Cmp, String.order(k, k), EQ{}, meta.str_refl(k)) : {M.Meta.get.if(_, v, None{}) == Some{v} : Maybe<&2, String>}
      {==}
    case Con{M.KV{+kk, vv}, +r}:
      meta.get_insert_same_go(String.order(k, kk), kk, vv, k, v, r, {==}, L.meta.get_insert_same(k, v, r))

law meta.get_insert_other_go:
  for c: Cmp
  for +kk: String
  for +vv: String
  for +q: String
  for +k: String
  for +v: String
  for +r: +List<M.KV>
  for +e: {String.order(k, kk) == c : Cmp}
  for +h: {String.eq(q, k) == False{} : Bool}
  for +ih: {M.Meta.get(q, M.Meta.insert(k, v, r)) == M.Meta.get(q, r) : Maybe<&2, String>}
  {M.Meta.get(q, M.Meta.insert.if(c, kk, vv, k, v, r, M.Meta.insert(k, v, r))) == M.Meta.get(q, M.KV{kk, vv} <> r) : Maybe<&2, String>}

def meta.get_insert_other_go(c, kk, vv, q, k, v, r, e, h, ih):
  match c:
    case LT{}:
      meta.get_if_ne(String.order(q, k), v, M.Meta.get(q, M.KV{kk, vv} <> r), h)
    case EQ{}:
      +h2 = meta.ne_move(q, k, kk, e, h)
      Equal.trans(Maybe<&2, String>, M.Meta.get.if(String.order(q, kk), v, M.Meta.get(q, r)), M.Meta.get(q, r), M.Meta.get.if(String.order(q, kk), vv, M.Meta.get(q, r)),
        meta.get_if_ne(String.order(q, kk), v, M.Meta.get(q, r), h2),
        Equal.sym(Maybe<&2, String>, M.Meta.get.if(String.order(q, kk), vv, M.Meta.get(q, r)), M.Meta.get(q, r), meta.get_if_ne(String.order(q, kk), vv, M.Meta.get(q, r), h2)))
    case GT{}:
      %Equal.sym(Maybe<&2, String>, M.Meta.get(q, M.Meta.insert(k, v, r)), M.Meta.get(q, r), ih) :
        {M.Meta.get.if(String.order(q, kk), vv, _) == M.Meta.get(q, M.KV{kk, vv} <> r) : Maybe<&2, String>}
      {==}

def L.meta.get_insert_other(q, k, v, m, h):
  match m:
    case Nil{}:
      meta.get_if_ne(String.order(q, k), v, None{}, h)
    case Con{M.KV{+kk, +vv}, +r}:
      meta.get_insert_other_go(String.order(k, kk), kk, vv, q, k, v, r, {==}, h, L.meta.get_insert_other(q, k, v, r, h))

law meta.get_delete_same_go:
  for c: Cmp
  for +kk: String
  for +vv: String
  for +k: String
  for +r: +List<M.KV>
  for +e: {String.order(k, kk) == c : Cmp}
  for +ih: {M.Meta.get(k, M.Meta.delete(k, r)) == None{} : Maybe<&2, String>}
  {M.Meta.get(k, M.Meta.delete.if(c, M.KV{kk, vv}, M.Meta.delete(k, r))) == None{} : Maybe<&2, String>}

def meta.get_delete_same_go(c, kk, vv, k, r, e, ih):
  match c:
    case LT{}:
      %Equal.sym(Cmp, String.order(k, kk), LT{}, e) : {M.Meta.get.if(_, vv, M.Meta.get(k, M.Meta.delete(k, r))) == None{} : Maybe<&2, String>}
      ih
    case EQ{}:
      ih
    case GT{}:
      %Equal.sym(Cmp, String.order(k, kk), GT{}, e) : {M.Meta.get.if(_, vv, M.Meta.get(k, M.Meta.delete(k, r))) == None{} : Maybe<&2, String>}
      ih

def L.meta.get_delete_same(k, m):
  match m:
    case Nil{}:
      {==}
    case Con{M.KV{+kk, +vv}, +r}:
      meta.get_delete_same_go(String.order(k, kk), kk, vv, k, r, {==}, L.meta.get_delete_same(k, r))

law meta.get_delete_other_go:
  for c: Cmp
  for +kk: String
  for +vv: String
  for +q: String
  for +k: String
  for +r: +List<M.KV>
  for +e: {String.order(k, kk) == c : Cmp}
  for +h: {String.eq(q, k) == False{} : Bool}
  for +ih: {M.Meta.get(q, M.Meta.delete(k, r)) == M.Meta.get(q, r) : Maybe<&2, String>}
  {M.Meta.get(q, M.Meta.delete.if(c, M.KV{kk, vv}, M.Meta.delete(k, r))) == M.Meta.get(q, M.KV{kk, vv} <> r) : Maybe<&2, String>}

def meta.get_delete_other_go(c, kk, vv, q, k, r, e, h, ih):
  match c:
    case LT{}:
      %Equal.sym(Maybe<&2, String>, M.Meta.get(q, M.Meta.delete(k, r)), M.Meta.get(q, r), ih) :
        {M.Meta.get.if(String.order(q, kk), vv, _) == M.Meta.get(q, M.KV{kk, vv} <> r) : Maybe<&2, String>}
      {==}
    case EQ{}:
      +h2 = meta.ne_move(q, k, kk, e, h)
      Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.delete(k, r)), M.Meta.get(q, r), M.Meta.get.if(String.order(q, kk), vv, M.Meta.get(q, r)),
        ih,
        Equal.sym(Maybe<&2, String>, M.Meta.get.if(String.order(q, kk), vv, M.Meta.get(q, r)), M.Meta.get(q, r), meta.get_if_ne(String.order(q, kk), vv, M.Meta.get(q, r), h2)))
    case GT{}:
      %Equal.sym(Maybe<&2, String>, M.Meta.get(q, M.Meta.delete(k, r)), M.Meta.get(q, r), ih) :
        {M.Meta.get.if(String.order(q, kk), vv, _) == M.Meta.get(q, M.KV{kk, vv} <> r) : Maybe<&2, String>}
      {==}

def L.meta.get_delete_other(q, k, m, h):
  match m:
    case Nil{}:
      {==}
    case Con{M.KV{+kk, +vv}, +r}:
      meta.get_delete_other_go(String.order(k, kk), kk, vv, q, k, r, {==}, h, L.meta.get_delete_other(q, k, r, h))

# Canonical form.

law meta.is_lt_true:
  for c: Cmp
  for h: {Cmp.is_lt(c) == True{} : Bool}
  {c == LT{} : Cmp}

def meta.is_lt_true(c, h):
  match c:
    case LT{}:
      {==}
    case EQ{}:
      meta.tf_absurd({EQ{} == LT{} : Cmp}, Equal.sym(Bool, False{}, True{}, h))
    case GT{}:
      meta.tf_absurd({GT{} == LT{} : Cmp}, Equal.sym(Bool, False{}, True{}, h))

law meta.lt_is_lt:
  for c: Cmp
  for h: {c == LT{} : Cmp}
  {Cmp.is_lt(c) == True{} : Bool}

def meta.lt_is_lt(c, h):
  %Equal.sym(Cmp, c, LT{}, h) : {Cmp.is_lt(_) == True{} : Bool}
  {==}

# order(k, kk) == GT gives order(kk, k) == LT.
law meta.flip_gt:
  for +k: String
  for +kk: String
  for +e: {String.order(k, kk) == GT{} : Cmp}
  {String.order(kk, k) == LT{} : Cmp}

def meta.flip_gt(k, kk, e):
  Equal.trans(Cmp, String.order(kk, k), meta.flip(String.order(k, kk)), LT{}, meta.str_flip(k, kk, EQ{}),
    Equal.cong(Cmp, Cmp, meta.flip, String.order(k, kk), GT{}, e))

law meta.above_mono:
  for +a: String
  for +b: String
  for +m: +List<M.KV>
  for +h1: {String.order(a, b) == LT{} : Cmp}
  for +h2: {M.Meta.above(b, m) == True{} : Bool}
  {M.Meta.above(a, m) == True{} : Bool}

def meta.above_mono(a, b, m, h1, h2):
  match m:
    case Nil{}:
      {==}
    case Con{M.KV{+kk, vv}, +r}:
      meta.and_i(Cmp.is_lt(String.order(a, kk)), M.Meta.above(a, r),
        meta.lt_is_lt(String.order(a, kk), meta.str_trans(a, b, kk, h1, meta.is_lt_true(String.order(b, kk), meta.and_l(Cmp.is_lt(String.order(b, kk)), M.Meta.above(b, r), h2)))),
        meta.above_mono(a, b, r, h1, meta.and_r(Cmp.is_lt(String.order(b, kk)), M.Meta.above(b, r), h2)))

law meta.above_insert_go:
  for c: Cmp
  for +kk: String
  for +vv: String
  for +x: String
  for +k: String
  for +v: String
  for +r: +List<M.KV>
  for +h1: {M.Meta.above(x, M.KV{kk, vv} <> r) == True{} : Bool}
  for +h2: {String.order(x, k) == LT{} : Cmp}
  for +ih: {M.Meta.above(x, M.Meta.insert(k, v, r)) == True{} : Bool}
  {M.Meta.above(x, M.Meta.insert.if(c, kk, vv, k, v, r, M.Meta.insert(k, v, r))) == True{} : Bool}

def meta.above_insert_go(c, kk, vv, x, k, v, r, h1, h2, ih):
  match c:
    case LT{}:
      meta.and_i(Cmp.is_lt(String.order(x, k)), M.Meta.above(x, M.KV{kk, vv} <> r), meta.lt_is_lt(String.order(x, k), h2), h1)
    case EQ{}:
      h1
    case GT{}:
      meta.and_i(Cmp.is_lt(String.order(x, kk)), M.Meta.above(x, M.Meta.insert(k, v, r)),
        meta.and_l(Cmp.is_lt(String.order(x, kk)), M.Meta.above(x, r), h1), ih)

law meta.above_insert:
  for +x: String
  for +k: String
  for +v: String
  for +m: +List<M.KV>
  for +h1: {M.Meta.above(x, m) == True{} : Bool}
  for +h2: {String.order(x, k) == LT{} : Cmp}
  {M.Meta.above(x, M.Meta.insert(k, v, m)) == True{} : Bool}

def meta.above_insert(x, k, v, m, h1, h2):
  match m:
    case Nil{}:
      meta.and_i(Cmp.is_lt(String.order(x, k)), True{}, meta.lt_is_lt(String.order(x, k), h2), {==})
    case Con{M.KV{+kk, +vv}, +r}:
      meta.above_insert_go(String.order(k, kk), kk, vv, x, k, v, r, h1, h2,
        meta.above_insert(x, k, v, r, meta.and_r(Cmp.is_lt(String.order(x, kk)), M.Meta.above(x, r), h1), h2))

law meta.insert_canon_go:
  for c: Cmp
  for +kk: String
  for +vv: String
  for +k: String
  for +v: String
  for +r: +List<M.KV>
  for +e: {String.order(k, kk) == c : Cmp}
  for +h: {M.Meta.canon(M.KV{kk, vv} <> r) == True{} : Bool}
  for +ih: {M.Meta.canon(M.Meta.insert(k, v, r)) == True{} : Bool}
  {M.Meta.canon(M.Meta.insert.if(c, kk, vv, k, v, r, M.Meta.insert(k, v, r))) == True{} : Bool}

def meta.insert_canon_go(c, kk, vv, k, v, r, e, h, ih):
  match c:
    case LT{}:
      meta.and_i(M.Meta.above(k, M.KV{kk, vv} <> r), M.Meta.canon(M.KV{kk, vv} <> r),
        meta.and_i(Cmp.is_lt(String.order(k, kk)), M.Meta.above(k, r), meta.lt_is_lt(String.order(k, kk), e),
          meta.above_mono(k, kk, r, e, meta.and_l(M.Meta.above(kk, r), M.Meta.canon(r), h))),
        h)
    case EQ{}:
      h
    case GT{}:
      meta.and_i(M.Meta.above(kk, M.Meta.insert(k, v, r)), M.Meta.canon(M.Meta.insert(k, v, r)),
        meta.above_insert(kk, k, v, r, meta.and_l(M.Meta.above(kk, r), M.Meta.canon(r), h), meta.flip_gt(k, kk, e)),
        ih)

def L.meta.insert_canon(k, v, m, h):
  match m:
    case Nil{}:
      {==}
    case Con{M.KV{+kk, +vv}, +r}:
      meta.insert_canon_go(String.order(k, kk), kk, vv, k, v, r, {==}, h,
        L.meta.insert_canon(k, v, r, meta.and_r(M.Meta.above(kk, r), M.Meta.canon(r), h)))

law meta.above_delete_go:
  for c: Cmp
  for +kk: String
  for +vv: String
  for +x: String
  for +k: String
  for +r: +List<M.KV>
  for +h: {M.Meta.above(x, M.KV{kk, vv} <> r) == True{} : Bool}
  for +ih: {M.Meta.above(x, M.Meta.delete(k, r)) == True{} : Bool}
  {M.Meta.above(x, M.Meta.delete.if(c, M.KV{kk, vv}, M.Meta.delete(k, r))) == True{} : Bool}

def meta.above_delete_go(c, kk, vv, x, k, r, h, ih):
  match c:
    case LT{}:
      meta.and_i(Cmp.is_lt(String.order(x, kk)), M.Meta.above(x, M.Meta.delete(k, r)), meta.and_l(Cmp.is_lt(String.order(x, kk)), M.Meta.above(x, r), h), ih)
    case EQ{}:
      ih
    case GT{}:
      meta.and_i(Cmp.is_lt(String.order(x, kk)), M.Meta.above(x, M.Meta.delete(k, r)), meta.and_l(Cmp.is_lt(String.order(x, kk)), M.Meta.above(x, r), h), ih)

law meta.above_delete:
  for +x: String
  for +k: String
  for +m: +List<M.KV>
  for +h: {M.Meta.above(x, m) == True{} : Bool}
  {M.Meta.above(x, M.Meta.delete(k, m)) == True{} : Bool}

def meta.above_delete(x, k, m, h):
  match m:
    case Nil{}:
      {==}
    case Con{M.KV{+kk, +vv}, +r}:
      meta.above_delete_go(String.order(k, kk), kk, vv, x, k, r, h,
        meta.above_delete(x, k, r, meta.and_r(Cmp.is_lt(String.order(x, kk)), M.Meta.above(x, r), h)))

law meta.delete_canon_go:
  for c: Cmp
  for +kk: String
  for +vv: String
  for +k: String
  for +r: +List<M.KV>
  for +h: {M.Meta.canon(M.KV{kk, vv} <> r) == True{} : Bool}
  for +ih: {M.Meta.canon(M.Meta.delete(k, r)) == True{} : Bool}
  {M.Meta.canon(M.Meta.delete.if(c, M.KV{kk, vv}, M.Meta.delete(k, r))) == True{} : Bool}

def meta.delete_canon_go(c, kk, vv, k, r, h, ih):
  match c:
    case LT{}:
      meta.and_i(M.Meta.above(kk, M.Meta.delete(k, r)), M.Meta.canon(M.Meta.delete(k, r)),
        meta.above_delete(kk, k, r, meta.and_l(M.Meta.above(kk, r), M.Meta.canon(r), h)), ih)
    case EQ{}:
      ih
    case GT{}:
      meta.and_i(M.Meta.above(kk, M.Meta.delete(k, r)), M.Meta.canon(M.Meta.delete(k, r)),
        meta.above_delete(kk, k, r, meta.and_l(M.Meta.above(kk, r), M.Meta.canon(r), h)), ih)

def L.meta.delete_canon(k, m, h):
  match m:
    case Nil{}:
      {==}
    case Con{M.KV{+kk, +vv}, +r}:
      meta.delete_canon_go(String.order(k, kk), kk, vv, k, r, h,
        L.meta.delete_canon(k, r, meta.and_r(M.Meta.above(kk, r), M.Meta.canon(r), h)))

def L.meta.from_list_canon(xs):
  match xs:
    case Nil{}:
      {==}
    case Con{M.KV{+k, +v}, +r}:
      L.meta.insert_canon(k, v, M.Meta.from_list(r), L.meta.from_list_canon(r))

def L.meta.union_canon(a, b, h):
  match a:
    case Nil{}:
      h
    case Con{M.KV{+k, +v}, +r}:
      L.meta.insert_canon(k, v, M.Meta.union(r, b), L.meta.union_canon(r, b, h))

# Extensionality.

def meta.mdisc(m: Maybe<&2, String>) -> Type:
  match m:
    case None{}:
      Empty
    case Some{x}:
      Unit

def meta.some_none(-A: Type, -v: String, e: {Some{v} == None{} : Maybe<&2, String>}) -> A:
  Empty.absurd(A, (%e : meta.mdisc(_); Unit{}))

law meta.some_inj:
  for -a: String
  for -b: String
  for e: {Some{a} == Some{b} : Maybe<&2, String>}
  {a == b : String}

def meta.some_inj(a, b, e):
  Equal.cong(Maybe<&2, String>, String, m => Maybe.default(&2, String, m, ""), Some{a}, Some{b}, e)

law meta.get_self:
  for +k: String
  for v: String
  for r: +List<M.KV>
  {M.Meta.get(k, M.KV{k, v} <> r) == Some{v} : Maybe<&2, String>}

def meta.get_self(k, v, r):
  %Equal.sym(Cmp, String.order(k, k), EQ{}, meta.str_refl(k)) : {M.Meta.get.if(_, v, M.Meta.get(k, r)) == Some{v} : Maybe<&2, String>}
  {==}

law meta.get_above_none:
  for +q: String
  for +m: +List<M.KV>
  for +h: {M.Meta.above(q, m) == True{} : Bool}
  {M.Meta.get(q, m) == None{} : Maybe<&2, String>}

def meta.get_above_none(q, m, h):
  match m:
    case Nil{}:
      {==}
    case Con{M.KV{+kk, +vv}, +r}:
      %Equal.sym(Cmp, String.order(q, kk), LT{}, meta.is_lt_true(String.order(q, kk), meta.and_l(Cmp.is_lt(String.order(q, kk)), M.Meta.above(q, r), h))) :
        {M.Meta.get.if(_, vv, M.Meta.get(q, r)) == None{} : Maybe<&2, String>}
      meta.get_above_none(q, r, meta.and_r(Cmp.is_lt(String.order(q, kk)), M.Meta.above(q, r), h))

law meta.lt_not_eq:
  for c: Cmp
  for h: {c == LT{} : Cmp}
  {Cmp.is_eq(c) == False{} : Bool}

def meta.lt_not_eq(c, h):
  %Equal.sym(Cmp, c, LT{}, h) : {Cmp.is_eq(_) == False{} : Bool}
  {==}

law meta.gt_not_eq:
  for c: Cmp
  for h: {c == GT{} : Cmp}
  {Cmp.is_eq(c) == False{} : Bool}

def meta.gt_not_eq(c, h):
  %Equal.sym(Cmp, c, GT{}, h) : {Cmp.is_eq(_) == False{} : Bool}
  {==}

# The tails of two canonical maps with equal heads' keys agree everywhere.
law meta.ext_tail_go:
  for c: Cmp
  for +q: String
  for +k1: String
  for +v1: String
  for +r1: +List<M.KV>
  for +k2: String
  for +v2: String
  for +r2: +List<M.KV>
  for +ec: {String.order(q, k1) == c : Cmp}
  for +ek: {String.order(k1, k2) == EQ{} : Cmp}
  for +ha: {M.Meta.above(k1, r1) == True{} : Bool}
  for +hb: {M.Meta.above(k2, r2) == True{} : Bool}
  for +eq: {M.Meta.get(q, M.KV{k1, v1} <> r1) == M.Meta.get(q, M.KV{k2, v2} <> r2) : Maybe<&2, String>}
  {M.Meta.get(q, r1) == M.Meta.get(q, r2) : Maybe<&2, String>}

def meta.ext_tail_go(c, q, k1, v1, r1, k2, v2, r2, ec, ek, ha, hb, eq):
  match c:
    case EQ{}:
      +eqk = meta.str_eq(q, k1, ec)
      +e12 = meta.str_eq(k1, k2, ek)
      %Equal.sym(String, q, k1, eqk) : {M.Meta.get(_, r1) == M.Meta.get(_, r2) : Maybe<&2, String>}
      Equal.trans(Maybe<&2, String>, M.Meta.get(k1, r1), None{}, M.Meta.get(k1, r2), meta.get_above_none(k1, r1, ha),
        Equal.sym(Maybe<&2, String>, M.Meta.get(k1, r2), None{}, (%Equal.sym(String, k1, k2, e12) : {M.Meta.get(_, r2) == None{} : Maybe<&2, String>}; meta.get_above_none(k2, r2, hb))))
    case LT{}:
      +n1 = meta.lt_not_eq(String.order(q, k1), ec)
      +n2 = meta.ne_move(q, k1, k2, ek, n1)
      Equal.trans(Maybe<&2, String>, M.Meta.get(q, r1), M.Meta.get(q, M.KV{k1, v1} <> r1), M.Meta.get(q, r2),
        Equal.sym(Maybe<&2, String>, M.Meta.get(q, M.KV{k1, v1} <> r1), M.Meta.get(q, r1), meta.get_if_ne(String.order(q, k1), v1, M.Meta.get(q, r1), n1)),
        Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.KV{k1, v1} <> r1), M.Meta.get(q, M.KV{k2, v2} <> r2), M.Meta.get(q, r2), eq,
          meta.get_if_ne(String.order(q, k2), v2, M.Meta.get(q, r2), n2)))
    case GT{}:
      +n1 = meta.gt_not_eq(String.order(q, k1), ec)
      +n2 = meta.ne_move(q, k1, k2, ek, n1)
      Equal.trans(Maybe<&2, String>, M.Meta.get(q, r1), M.Meta.get(q, M.KV{k1, v1} <> r1), M.Meta.get(q, r2),
        Equal.sym(Maybe<&2, String>, M.Meta.get(q, M.KV{k1, v1} <> r1), M.Meta.get(q, r1), meta.get_if_ne(String.order(q, k1), v1, M.Meta.get(q, r1), n1)),
        Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.KV{k1, v1} <> r1), M.Meta.get(q, M.KV{k2, v2} <> r2), M.Meta.get(q, r2), eq,
          meta.get_if_ne(String.order(q, k2), v2, M.Meta.get(q, r2), n2)))

law meta.is_eq_true:
  for c: Cmp
  for h: {Cmp.is_eq(c) == True{} : Bool}
  {c == EQ{} : Cmp}

def meta.is_eq_true(c, h):
  match c:
    case LT{}:
      meta.tf_absurd({LT{} == EQ{} : Cmp}, Equal.sym(Bool, False{}, True{}, h))
    case EQ{}:
      {==}
    case GT{}:
      meta.tf_absurd({GT{} == EQ{} : Cmp}, Equal.sym(Bool, False{}, True{}, h))

law meta.opt_eq_true:
  for x: Maybe<&2, String>
  for y: Maybe<&2, String>
  for h: {M.Meta.opt_eq(x, y) == True{} : Bool}
  {x == y : Maybe<&2, String>}

def meta.opt_eq_true(x, y, h):
  match x y:
    case None{} None{}:
      {==}
    case None{} Some{b}:
      meta.tf_absurd({None{} == Some{b} : Maybe<&2, String>}, Equal.sym(Bool, False{}, True{}, h))
    case Some{a} None{}:
      meta.tf_absurd({Some{a} == None{} : Maybe<&2, String>}, Equal.sym(Bool, False{}, True{}, h))
    case Some{+a} Some{+b}:
      %meta.str_eq(a, b, meta.is_eq_true(String.order(a, b), h)) : {Some{a} == Some{_} : Maybe<&2, String>}
      {==}

law meta.opt_eq_refl:
  for x: Maybe<&2, String>
  {M.Meta.opt_eq(x, x) == True{} : Bool}

def meta.opt_eq_refl(x):
  match x:
    case None{}:
      {==}
    case Some{+a}:
      %Equal.sym(Cmp, String.order(a, a), EQ{}, meta.str_refl(a)) : {Cmp.is_eq(_) == True{} : Bool}
      {==}

law meta.opt_eq_of:
  for +x: Maybe<&2, String>
  for +y: Maybe<&2, String>
  for +e: {x == y : Maybe<&2, String>}
  {M.Meta.opt_eq(x, y) == True{} : Bool}

def meta.opt_eq_of(x, y, e):
  %e : {M.Meta.opt_eq(x, _) == True{} : Bool}
  meta.opt_eq_refl(x)

law meta.agree_head:
  for +q: String
  for +r: +List<String>
  for +a: +List<M.KV>
  for +b: +List<M.KV>
  for +h: {M.Meta.agree_on(q <> r, a, b) == True{} : Bool}
  {M.Meta.get(q, a) == M.Meta.get(q, b) : Maybe<&2, String>}

def meta.agree_head(q, r, a, b, h):
  meta.opt_eq_true(M.Meta.get(q, a), M.Meta.get(q, b),
    meta.and_l(M.Meta.opt_eq(M.Meta.get(q, a), M.Meta.get(q, b)), M.Meta.agree_on(r, a, b), h))

law meta.agree_tail:
  for +ks: +List<String>
  for +k1: String
  for +v1: String
  for +r1: +List<M.KV>
  for +k2: String
  for +v2: String
  for +r2: +List<M.KV>
  for +ek: {String.order(k1, k2) == EQ{} : Cmp}
  for +ta: {M.Meta.above(k1, r1) == True{} : Bool}
  for +tb: {M.Meta.above(k2, r2) == True{} : Bool}
  for +h: {M.Meta.agree_on(ks, M.KV{k1, v1} <> r1, M.KV{k2, v2} <> r2) == True{} : Bool}
  {M.Meta.agree_on(ks, r1, r2) == True{} : Bool}

def meta.agree_tail(ks, k1, v1, r1, k2, v2, r2, ek, ta, tb, h):
  match ks:
    case Nil{}:
      {==}
    case Con{+q, +rest}:
      meta.and_i(M.Meta.opt_eq(M.Meta.get(q, r1), M.Meta.get(q, r2)), M.Meta.agree_on(rest, r1, r2),
        meta.opt_eq_of(M.Meta.get(q, r1), M.Meta.get(q, r2),
          meta.ext_tail_go(String.order(q, k1), q, k1, v1, r1, k2, v2, r2, {==}, ek, ta, tb, meta.agree_head(q, rest, M.KV{k1, v1} <> r1, M.KV{k2, v2} <> r2, h))),
        meta.agree_tail(rest, k1, v1, r1, k2, v2, r2, ek, ta, tb,
          meta.and_r(M.Meta.opt_eq(M.Meta.get(q, M.KV{k1, v1} <> r1), M.Meta.get(q, M.KV{k2, v2} <> r2)), M.Meta.agree_on(rest, M.KV{k1, v1} <> r1, M.KV{k2, v2} <> r2), h)))

law meta.ext_go:
  for c: Cmp
  for +k1: String
  for +v1: String
  for +r1: +List<M.KV>
  for +k2: String
  for +v2: String
  for +r2: +List<M.KV>
  for +ec: {String.order(k1, k2) == c : Cmp}
  for +ha: {M.Meta.canon(M.KV{k1, v1} <> r1) == True{} : Bool}
  for +hb: {M.Meta.canon(M.KV{k2, v2} <> r2) == True{} : Bool}
  for +he: {M.Meta.agree(M.KV{k1, v1} <> r1, M.KV{k2, v2} <> r2) == True{} : Bool}
  for ih: {M.Meta.agree(r1, r2) == True{} : Bool} -> {r1 == r2 : +List<M.KV>}
  {M.KV{k1, v1} <> r1 == M.KV{k2, v2} <> r2 : +List<M.KV>}

def meta.ext_go(c, k1, v1, r1, k2, v2, r2, ec, ha, hb, he, ih):
  match c:
    case LT{}:
      +a = {M.KV{k1, v1} <> r1 : +List<M.KV>}
      +b = {M.KV{k2, v2} <> r2 : +List<M.KV>}
      +ha1 = meta.and_l(M.Meta.agree_on(M.Meta.keys(a), a, b), M.Meta.agree_on(M.Meta.keys(b), a, b), he)
      +hb1 = meta.and_r(M.Meta.agree_on(M.Meta.keys(a), a, b), M.Meta.agree_on(M.Meta.keys(b), a, b), he)
      +a2 = meta.above_mono(k1, k2, r2, ec, meta.and_l(M.Meta.above(k2, r2), M.Meta.canon(r2), hb))
      meta.some_none({a == b : +List<M.KV>}, v1,
        Equal.trans(Maybe<&2, String>, Some{v1}, M.Meta.get(k1, a), None{},
          Equal.sym(Maybe<&2, String>, M.Meta.get(k1, a), Some{v1}, meta.get_self(k1, v1, r1)),
          Equal.trans(Maybe<&2, String>, M.Meta.get(k1, a), M.Meta.get(k1, b), None{}, meta.agree_head(k1, M.Meta.keys(r1), a, b, ha1),
            Equal.trans(Maybe<&2, String>, M.Meta.get(k1, b), M.Meta.get(k1, r2), None{},
              meta.get_if_ne(String.order(k1, k2), v2, M.Meta.get(k1, r2), meta.lt_not_eq(String.order(k1, k2), ec)),
              meta.get_above_none(k1, r2, a2)))))
    case GT{}:
      +a = {M.KV{k1, v1} <> r1 : +List<M.KV>}
      +b = {M.KV{k2, v2} <> r2 : +List<M.KV>}
      +ha1 = meta.and_l(M.Meta.agree_on(M.Meta.keys(a), a, b), M.Meta.agree_on(M.Meta.keys(b), a, b), he)
      +hb1 = meta.and_r(M.Meta.agree_on(M.Meta.keys(a), a, b), M.Meta.agree_on(M.Meta.keys(b), a, b), he)
      +fl = meta.flip_gt(k1, k2, ec)
      +a1 = meta.above_mono(k2, k1, r1, fl, meta.and_l(M.Meta.above(k1, r1), M.Meta.canon(r1), ha))
      meta.some_none({a == b : +List<M.KV>}, v2,
        Equal.trans(Maybe<&2, String>, Some{v2}, M.Meta.get(k2, b), None{},
          Equal.sym(Maybe<&2, String>, M.Meta.get(k2, b), Some{v2}, meta.get_self(k2, v2, r2)),
          Equal.trans(Maybe<&2, String>, M.Meta.get(k2, b), M.Meta.get(k2, a), None{},
            Equal.sym(Maybe<&2, String>, M.Meta.get(k2, a), M.Meta.get(k2, b), meta.agree_head(k2, M.Meta.keys(r2), a, b, hb1)),
            Equal.trans(Maybe<&2, String>, M.Meta.get(k2, a), M.Meta.get(k2, r1), None{},
              meta.get_if_ne(String.order(k2, k1), v1, M.Meta.get(k2, r1), meta.lt_not_eq(String.order(k2, k1), fl)),
              meta.get_above_none(k2, r1, a1)))))
    case EQ{}:
      +a = {M.KV{k1, v1} <> r1 : +List<M.KV>}
      +b = {M.KV{k2, v2} <> r2 : +List<M.KV>}
      +ha1 = meta.and_l(M.Meta.agree_on(M.Meta.keys(a), a, b), M.Meta.agree_on(M.Meta.keys(b), a, b), he)
      +hb1 = meta.and_r(M.Meta.agree_on(M.Meta.keys(a), a, b), M.Meta.agree_on(M.Meta.keys(b), a, b), he)
      +ek = meta.str_eq(k1, k2, ec)
      +ev = Equal.trans(Maybe<&2, String>, Some{v1}, M.Meta.get(k1, a), Some{v2},
        Equal.sym(Maybe<&2, String>, M.Meta.get(k1, a), Some{v1}, meta.get_self(k1, v1, r1)),
        Equal.trans(Maybe<&2, String>, M.Meta.get(k1, a), M.Meta.get(k1, b), Some{v2}, meta.agree_head(k1, M.Meta.keys(r1), a, b, ha1),
          (%Equal.sym(Cmp, String.order(k1, k2), EQ{}, ec) : {M.Meta.get.if(_, v2, M.Meta.get(k1, r2)) == Some{v2} : Maybe<&2, String>}; {==})))
      +ta = meta.and_l(M.Meta.above(k1, r1), M.Meta.canon(r1), ha)
      +tb = meta.and_l(M.Meta.above(k2, r2), M.Meta.canon(r2), hb)
      +t1 = meta.agree_tail(M.Meta.keys(r1), k1, v1, r1, k2, v2, r2, ec, ta, tb,
        meta.and_r(M.Meta.opt_eq(M.Meta.get(k1, a), M.Meta.get(k1, b)), M.Meta.agree_on(M.Meta.keys(r1), a, b), ha1))
      +t2 = meta.agree_tail(M.Meta.keys(r2), k1, v1, r1, k2, v2, r2, ec, ta, tb,
        meta.and_r(M.Meta.opt_eq(M.Meta.get(k2, a), M.Meta.get(k2, b)), M.Meta.agree_on(M.Meta.keys(r2), a, b), hb1))
      %ek : {a == M.KV{_, v2} <> r2 : +List<M.KV>}
      %meta.some_inj(v1, v2, ev) : {a == M.KV{k1, _} <> r2 : +List<M.KV>}
      %ih(meta.and_i(M.Meta.agree_on(M.Meta.keys(r1), r1, r2), M.Meta.agree_on(M.Meta.keys(r2), r1, r2), t1, t2)) : {a == M.KV{k1, v1} <> _ : +List<M.KV>}
      {==}

def L.meta.ext(a, b, ha, hb, he):
  match a b:
    case Nil{} Nil{}:
      {==}
    case Nil{} Con{M.KV{+k, +v}, +r}:
      meta.some_none({Nil{} == M.KV{k, v} <> r : +List<M.KV>}, v,
        Equal.trans(Maybe<&2, String>, Some{v}, M.Meta.get(k, M.KV{k, v} <> r), None{},
          Equal.sym(Maybe<&2, String>, M.Meta.get(k, M.KV{k, v} <> r), Some{v}, meta.get_self(k, v, r)),
          Equal.sym(Maybe<&2, String>, None{}, M.Meta.get(k, M.KV{k, v} <> r),
            meta.agree_head(k, M.Meta.keys(r), Nil{}, M.KV{k, v} <> r, meta.and_r(True{}, M.Meta.agree_on(M.Meta.keys(M.KV{k, v} <> r), Nil{}, M.KV{k, v} <> r), he)))))
    case Con{M.KV{+k, +v}, +r} Nil{}:
      meta.some_none({M.KV{k, v} <> r == Nil{} : +List<M.KV>}, v,
        Equal.trans(Maybe<&2, String>, Some{v}, M.Meta.get(k, M.KV{k, v} <> r), None{},
          Equal.sym(Maybe<&2, String>, M.Meta.get(k, M.KV{k, v} <> r), Some{v}, meta.get_self(k, v, r)),
          meta.agree_head(k, M.Meta.keys(r), M.KV{k, v} <> r, Nil{}, meta.and_l(M.Meta.agree_on(M.Meta.keys(M.KV{k, v} <> r), M.KV{k, v} <> r, Nil{}), True{}, he))))
    case Con{M.KV{+k1, +v1}, +r1} Con{M.KV{+k2, +v2}, +r2}:
      meta.ext_go(String.order(k1, k2), k1, v1, r1, k2, v2, r2, {==}, ha, hb, he,
        e2 => L.meta.ext(r1, r2, meta.and_r(M.Meta.above(k1, r1), M.Meta.canon(r1), ha), meta.and_r(M.Meta.above(k2, r2), M.Meta.canon(r2), hb), e2))

def L.meta.should_delete_deleting(name, namespace, uid, kind, labels, annotations):
  {==}

def L.meta.apply_maps_managed_string(from, to, managed, exclude):
  {==}

# Filters keep the canonical form.

law meta.above_keep_if:
  for b: Bool
  for +x: String
  for +kk: String
  for +vv: String
  for +rec: +List<M.KV>
  for +hk: {Cmp.is_lt(String.order(x, kk)) == True{} : Bool}
  for +hr: {M.Meta.above(x, rec) == True{} : Bool}
  {M.Meta.above(x, M.Meta.keep.if(b, M.KV{kk, vv}, rec)) == True{} : Bool}

def meta.above_keep_if(b, x, kk, vv, rec, hk, hr):
  match b:
    case True{}:
      hr
    case False{}:
      meta.and_i(Cmp.is_lt(String.order(x, kk)), M.Meta.above(x, rec), hk, hr)

law meta.canon_keep_if:
  for b: Bool
  for +kk: String
  for +vv: String
  for +rec: +List<M.KV>
  for +ha: {M.Meta.above(kk, rec) == True{} : Bool}
  for +hc: {M.Meta.canon(rec) == True{} : Bool}
  {M.Meta.canon(M.Meta.keep.if(b, M.KV{kk, vv}, rec)) == True{} : Bool}

def meta.canon_keep_if(b, kk, vv, rec, ha, hc):
  match b:
    case True{}:
      hc
    case False{}:
      meta.and_i(M.Meta.above(kk, rec), M.Meta.canon(rec), ha, hc)

law meta.to_part_above:
  for +x: String
  for +to: +List<M.KV>
  for +from: +List<M.KV>
  for +managed: +List<String>
  for +exclude: +List<String>
  for +h: {M.Meta.above(x, to) == True{} : Bool}
  {M.Meta.above(x, M.Meta.to_part(to, from, managed, exclude)) == True{} : Bool}

def meta.to_part_above(x, to, from, managed, exclude, h):
  match to:
    case Nil{}:
      {==}
    case Con{M.KV{+kk, +v}, +r}:
      meta.above_keep_if(Bool.not(M.Meta.to_keep(kk, from, managed, exclude)), x, kk, v, M.Meta.to_part(r, from, managed, exclude),
        meta.and_l(Cmp.is_lt(String.order(x, kk)), M.Meta.above(x, r), h),
        meta.to_part_above(x, r, from, managed, exclude, meta.and_r(Cmp.is_lt(String.order(x, kk)), M.Meta.above(x, r), h)))

law meta.to_part_canon:
  for +to: +List<M.KV>
  for +from: +List<M.KV>
  for +managed: +List<String>
  for +exclude: +List<String>
  for +h: {M.Meta.canon(to) == True{} : Bool}
  {M.Meta.canon(M.Meta.to_part(to, from, managed, exclude)) == True{} : Bool}

def meta.to_part_canon(to, from, managed, exclude, h):
  match to:
    case Nil{}:
      {==}
    case Con{M.KV{+kk, +v}, +r}:
      meta.canon_keep_if(Bool.not(M.Meta.to_keep(kk, from, managed, exclude)), kk, v, M.Meta.to_part(r, from, managed, exclude),
        meta.to_part_above(kk, r, from, managed, exclude, meta.and_l(M.Meta.above(kk, r), M.Meta.canon(r), h)),
        meta.to_part_canon(r, from, managed, exclude, meta.and_r(M.Meta.above(kk, r), M.Meta.canon(r), h)))

def L.meta.apply_maps_canon(from, to, managed, exclude, h):
  L.meta.union_canon(M.Meta.keep_out(from, exclude, []), M.Meta.to_part(to, from, managed, exclude),
    meta.to_part_canon(to, from, managed, exclude, h))

law meta.keep_out_above:
  for +x: String
  for +m: +List<M.KV>
  for +xs: +List<String>
  for +ps: +List<String>
  for +h: {M.Meta.above(x, m) == True{} : Bool}
  {M.Meta.above(x, M.Meta.keep_out(m, xs, ps)) == True{} : Bool}

def meta.keep_out_above(x, m, xs, ps, h):
  match m:
    case Nil{}:
      {==}
    case Con{M.KV{+kk, +v}, +r}:
      meta.above_keep_if(M.Meta.excluded(kk, xs, ps), x, kk, v, M.Meta.keep_out(r, xs, ps),
        meta.and_l(Cmp.is_lt(String.order(x, kk)), M.Meta.above(x, r), h),
        meta.keep_out_above(x, r, xs, ps, meta.and_r(Cmp.is_lt(String.order(x, kk)), M.Meta.above(x, r), h)))

law meta.keep_out_canon:
  for +m: +List<M.KV>
  for +xs: +List<String>
  for +ps: +List<String>
  for +h: {M.Meta.canon(m) == True{} : Bool}
  {M.Meta.canon(M.Meta.keep_out(m, xs, ps)) == True{} : Bool}

def meta.keep_out_canon(m, xs, ps, h):
  match m:
    case Nil{}:
      {==}
    case Con{M.KV{+kk, +v}, +r}:
      meta.canon_keep_if(M.Meta.excluded(kk, xs, ps), kk, v, M.Meta.keep_out(r, xs, ps),
        meta.keep_out_above(kk, r, xs, ps, meta.and_l(M.Meta.above(kk, r), M.Meta.canon(r), h)),
        meta.keep_out_canon(r, xs, ps, meta.and_r(M.Meta.above(kk, r), M.Meta.canon(r), h)))

law meta.above_keys:
  for +k: String
  for +m: +List<M.KV>
  {M.Meta.str_above(k, M.Meta.keys(m)) == M.Meta.above(k, m) : Bool}

def meta.above_keys(k, m):
  match m:
    case Nil{}:
      {==}
    case Con{M.KV{+kk, +v}, +r}:
      %Equal.sym(Bool, M.Meta.str_above(k, M.Meta.keys(r)), M.Meta.above(k, r), meta.above_keys(k, r)) : {Bool.and(Cmp.is_lt(String.order(k, kk)), _) == M.Meta.above(k, M.KV{kk, v} <> r) : Bool}
      {==}

law meta.canon_sorted:
  for +m: +List<M.KV>
  for +h: {M.Meta.canon(m) == True{} : Bool}
  {M.Meta.sorted(M.Meta.keys(m)) == True{} : Bool}

def meta.canon_sorted(m, h):
  match m:
    case Nil{}:
      {==}
    case Con{M.KV{+kk, +v}, +r}:
      meta.and_i(M.Meta.str_above(kk, M.Meta.keys(r)), M.Meta.sorted(M.Meta.keys(r)),
        (%Equal.sym(Bool, M.Meta.str_above(kk, M.Meta.keys(r)), M.Meta.above(kk, r), meta.above_keys(kk, r)) : {_ == True{} : Bool}; meta.and_l(M.Meta.above(kk, r), M.Meta.canon(r), h)),
        meta.canon_sorted(r, meta.and_r(M.Meta.above(kk, r), M.Meta.canon(r), h)))

def L.meta.apply_maps_managed_sorted(from, exclude, h):
  meta.canon_sorted(M.Meta.keep_out(from, exclude, []), meta.keep_out_canon(from, exclude, [], h))

# get through union and the filters.

law meta.or_l:
  for a: Bool
  for b: Bool
  for h: {a == True{} : Bool}
  {Bool.or(a, b) == True{} : Bool}

def meta.or_l(a, b, h):
  %Equal.sym(Bool, a, True{}, h) : {Bool.or(_, b) == True{} : Bool}
  {==}

law meta.elem_move:
  for +q: String
  for +kk: String
  for +xs: +List<String>
  for +ec: {String.order(q, kk) == EQ{} : Cmp}
  for +h: {M.Meta.elem(q, xs) == True{} : Bool}
  {M.Meta.elem(kk, xs) == True{} : Bool}

def meta.elem_move(q, kk, xs, ec, h):
  %meta.str_eq(q, kk, ec) : {M.Meta.elem(_, xs) == True{} : Bool}
  h

law meta.not_eq_of:
  for c: Cmp
  for +e: {Cmp.is_eq(c) == False{} : Bool}
  {Cmp.is_eq(c) == False{} : Bool}

def meta.not_eq_of(c, e):
  e

law meta.get_union_go:
  for c: Cmp
  for +q: String
  for +k: String
  for +v: String
  for +rest: +List<M.KV>
  for +rq: Maybe<&2, String>
  for +bq: Maybe<&2, String>
  for +ec: {String.order(q, k) == c : Cmp}
  for +ih: {M.Meta.get(q, rest) == Maybe.or(&2, String, rq, bq) : Maybe<&2, String>}
  {M.Meta.get(q, M.Meta.insert(k, v, rest)) == Maybe.or(&2, String, M.Meta.get.if(c, v, rq), bq) : Maybe<&2, String>}

def meta.get_union_go(c, q, k, v, rest, rq, bq, ec, ih):
  match c:
    case EQ{}:
      %Equal.sym(String, q, k, meta.str_eq(q, k, ec)) : {M.Meta.get(_, M.Meta.insert(k, v, rest)) == Some{v} : Maybe<&2, String>}
      L.meta.get_insert_same(k, v, rest)
    case LT{}:
      Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.insert(k, v, rest)), M.Meta.get(q, rest), Maybe.or(&2, String, rq, bq),
        L.meta.get_insert_other(q, k, v, rest, meta.lt_not_eq(String.order(q, k), ec)), ih)
    case GT{}:
      Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.insert(k, v, rest)), M.Meta.get(q, rest), Maybe.or(&2, String, rq, bq),
        L.meta.get_insert_other(q, k, v, rest, meta.gt_not_eq(String.order(q, k), ec)), ih)

law meta.get_union:
  for +q: String
  for +a: +List<M.KV>
  for +b: +List<M.KV>
  {M.Meta.get(q, M.Meta.union(a, b)) == Maybe.or(&2, String, M.Meta.get(q, a), M.Meta.get(q, b)) : Maybe<&2, String>}

def meta.get_union(q, a, b):
  match a:
    case Nil{}:
      {==}
    case Con{M.KV{+k, +v}, +r}:
      meta.get_union_go(String.order(q, k), q, k, v, M.Meta.union(r, b), M.Meta.get(q, r), M.Meta.get(q, b), {==}, meta.get_union(q, r, b))

# Keeping or dropping an entry whose key is not q does not change get(q, _).
law meta.get_keep_if_ne:
  for b: Bool
  for +q: String
  for +kk: String
  for +vv: String
  for +rec: +List<M.KV>
  for +h: {Cmp.is_eq(String.order(q, kk)) == False{} : Bool}
  {M.Meta.get(q, M.Meta.keep.if(b, M.KV{kk, vv}, rec)) == M.Meta.get(q, rec) : Maybe<&2, String>}

def meta.get_keep_if_ne(b, q, kk, vv, rec, h):
  match b:
    case True{}:
      {==}
    case False{}:
      meta.get_if_ne(String.order(q, kk), vv, M.Meta.get(q, rec), h)

law meta.get_keep_out_ex_go:
  for c: Cmp
  for +q: String
  for +kk: String
  for +v: String
  for +rec: +List<M.KV>
  for +xs: +List<String>
  for +ps: +List<String>
  for +ec: {String.order(q, kk) == c : Cmp}
  for +h: {M.Meta.excluded(q, xs, ps) == True{} : Bool}
  for +ih: {M.Meta.get(q, rec) == None{} : Maybe<&2, String>}
  {M.Meta.get(q, M.Meta.keep.if(M.Meta.excluded(kk, xs, ps), M.KV{kk, v}, rec)) == None{} : Maybe<&2, String>}

def meta.get_keep_out_ex_go(c, q, kk, v, rec, xs, ps, ec, h, ih):
  match c:
    case EQ{}:
      %Equal.sym(Bool, M.Meta.excluded(kk, xs, ps), True{}, (%meta.str_eq(q, kk, ec) : {M.Meta.excluded(_, xs, ps) == True{} : Bool}; h)) :
        {M.Meta.get(q, M.Meta.keep.if(_, M.KV{kk, v}, rec)) == None{} : Maybe<&2, String>}
      ih
    case LT{}:
      Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.keep.if(M.Meta.excluded(kk, xs, ps), M.KV{kk, v}, rec)), M.Meta.get(q, rec), None{},
        meta.get_keep_if_ne(M.Meta.excluded(kk, xs, ps), q, kk, v, rec, meta.lt_not_eq(String.order(q, kk), ec)), ih)
    case GT{}:
      Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.keep.if(M.Meta.excluded(kk, xs, ps), M.KV{kk, v}, rec)), M.Meta.get(q, rec), None{},
        meta.get_keep_if_ne(M.Meta.excluded(kk, xs, ps), q, kk, v, rec, meta.gt_not_eq(String.order(q, kk), ec)), ih)

law meta.get_keep_out_ex:
  for +q: String
  for +m: +List<M.KV>
  for +xs: +List<String>
  for +ps: +List<String>
  for +h: {M.Meta.excluded(q, xs, ps) == True{} : Bool}
  {M.Meta.get(q, M.Meta.keep_out(m, xs, ps)) == None{} : Maybe<&2, String>}

def meta.get_keep_out_ex(q, m, xs, ps, h):
  match m:
    case Nil{}:
      {==}
    case Con{M.KV{+kk, +v}, +r}:
      meta.get_keep_out_ex_go(String.order(q, kk), q, kk, v, M.Meta.keep_out(r, xs, ps), xs, ps, {==}, h, meta.get_keep_out_ex(q, r, xs, ps, h))

law meta.get_to_part_ex_go:
  for c: Cmp
  for +q: String
  for +kk: String
  for +v: String
  for +r: +List<M.KV>
  for +rec: +List<M.KV>
  for +from: +List<M.KV>
  for +managed: +List<String>
  for +exclude: +List<String>
  for +ec: {String.order(q, kk) == c : Cmp}
  for +h: {M.Meta.elem(q, exclude) == True{} : Bool}
  for +ih: {M.Meta.get(q, rec) == M.Meta.get(q, r) : Maybe<&2, String>}
  {M.Meta.get(q, M.Meta.keep.if(Bool.not(M.Meta.to_keep(kk, from, managed, exclude)), M.KV{kk, v}, rec)) == M.Meta.get(q, M.KV{kk, v} <> r) : Maybe<&2, String>}

def meta.get_to_part_ex_go(c, q, kk, v, r, rec, from, managed, exclude, ec, h, ih):
  match c:
    case EQ{}:
      +hk = meta.elem_move(q, kk, exclude, ec, h)
      %Equal.sym(Bool, M.Meta.elem(kk, exclude), True{}, hk) :
        {M.Meta.get(q, M.Meta.keep.if(Bool.not(Bool.or(_, Bool.and(Bool.not(M.Meta.has(kk, from)), Bool.not(M.Meta.elem(kk, managed))))), M.KV{kk, v}, rec)) == M.Meta.get(q, M.KV{kk, v} <> r) : Maybe<&2, String>}
      %Equal.sym(Cmp, String.order(q, kk), EQ{}, ec) : {M.Meta.get.if(_, v, M.Meta.get(q, rec)) == M.Meta.get.if(_, v, M.Meta.get(q, r)) : Maybe<&2, String>}
      {==}
    case LT{}:
      +n = meta.lt_not_eq(String.order(q, kk), ec)
      Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.keep.if(Bool.not(M.Meta.to_keep(kk, from, managed, exclude)), M.KV{kk, v}, rec)), M.Meta.get(q, r), M.Meta.get(q, M.KV{kk, v} <> r),
        Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.keep.if(Bool.not(M.Meta.to_keep(kk, from, managed, exclude)), M.KV{kk, v}, rec)), M.Meta.get(q, rec), M.Meta.get(q, r),
          meta.get_keep_if_ne(Bool.not(M.Meta.to_keep(kk, from, managed, exclude)), q, kk, v, rec, n), ih),
        Equal.sym(Maybe<&2, String>, M.Meta.get(q, M.KV{kk, v} <> r), M.Meta.get(q, r), meta.get_if_ne(String.order(q, kk), v, M.Meta.get(q, r), n)))
    case GT{}:
      +n = meta.gt_not_eq(String.order(q, kk), ec)
      Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.keep.if(Bool.not(M.Meta.to_keep(kk, from, managed, exclude)), M.KV{kk, v}, rec)), M.Meta.get(q, r), M.Meta.get(q, M.KV{kk, v} <> r),
        Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.keep.if(Bool.not(M.Meta.to_keep(kk, from, managed, exclude)), M.KV{kk, v}, rec)), M.Meta.get(q, rec), M.Meta.get(q, r),
          meta.get_keep_if_ne(Bool.not(M.Meta.to_keep(kk, from, managed, exclude)), q, kk, v, rec, n), ih),
        Equal.sym(Maybe<&2, String>, M.Meta.get(q, M.KV{kk, v} <> r), M.Meta.get(q, r), meta.get_if_ne(String.order(q, kk), v, M.Meta.get(q, r), n)))

law meta.get_to_part_ex:
  for +q: String
  for +to: +List<M.KV>
  for +from: +List<M.KV>
  for +managed: +List<String>
  for +exclude: +List<String>
  for +h: {M.Meta.elem(q, exclude) == True{} : Bool}
  {M.Meta.get(q, M.Meta.to_part(to, from, managed, exclude)) == M.Meta.get(q, to) : Maybe<&2, String>}

def meta.get_to_part_ex(q, to, from, managed, exclude, h):
  match to:
    case Nil{}:
      {==}
    case Con{M.KV{+kk, +v}, +r}:
      meta.get_to_part_ex_go(String.order(q, kk), q, kk, v, r, M.Meta.to_part(r, from, managed, exclude), from, managed, exclude, {==}, h,
        meta.get_to_part_ex(q, r, from, managed, exclude, h))

def L.meta.apply_maps_excluded(k, from, to, managed, exclude, h):
  +hx = meta.or_l(M.Meta.elem(k, exclude), M.Meta.any_prefix(k, []), h)
  %Equal.sym(Maybe<&2, String>, M.Meta.get(k, M.Meta.union(M.Meta.keep_out(from, exclude, []), M.Meta.to_part(to, from, managed, exclude))),
    Maybe.or(&2, String, M.Meta.get(k, M.Meta.keep_out(from, exclude, [])), M.Meta.get(k, M.Meta.to_part(to, from, managed, exclude))),
    meta.get_union(k, M.Meta.keep_out(from, exclude, []), M.Meta.to_part(to, from, managed, exclude))) : {_ == M.Meta.get(k, to) : Maybe<&2, String>}
  %Equal.sym(Maybe<&2, String>, M.Meta.get(k, M.Meta.keep_out(from, exclude, [])), None{}, meta.get_keep_out_ex(k, from, exclude, [], hx)) : {Maybe.or(&2, String, _, M.Meta.get(k, M.Meta.to_part(to, from, managed, exclude))) == M.Meta.get(k, to) : Maybe<&2, String>}
  meta.get_to_part_ex(k, to, from, managed, exclude, h)

# Prefixes.

law meta.go_if_b:
  for +pt: String
  for +t: String
  for b: Bool
  for +h: {String.starts_with.go.if(pt, t, b) == True{} : Bool}
  {b == True{} : Bool}

def meta.go_if_b(pt, t, b, h):
  match b:
    case True{}:
      {==}
    case False{}:
      h

law meta.go_if_t:
  for +pt: String
  for +t: String
  for b: Bool
  for +h: {String.starts_with.go.if(pt, t, b) == True{} : Bool}
  {String.starts_with.go(pt, t) == True{} : Bool}

def meta.go_if_t(pt, t, b, h):
  match b:
    case True{}:
      h
    case False{}:
      meta.tf_absurd({String.starts_with.go(pt, t) == True{} : Bool}, Equal.sym(Bool, False{}, True{}, h))

law meta.char_eq:
  for x: Char
  for y: Char
  for h: {Char.is_eq(x, y) == True{} : Bool}
  {x == y : Char}

def meta.char_eq(x, y, h):
  match x y:
    case Chr{+a} Chr{+b}:
      %meta.u32_eq(a, b, meta.is_eq_true(U32.cmp(a, b), h)) : {Chr{a} == Chr{_} : Char}
      {==}

# A string that starts with p is p followed by the rest.
law meta.sw_decomp:
  for +p: String
  for +s: String
  for +h: {String.starts_with.go(p, s) == True{} : Bool}
  {s == String.append(p, String.drop(s, String.length(p))) : String}

def meta.sw_decomp(p, s, h):
  match p s:
    case SNil{} SNil{}:
      {==}
    case SNil{} SCon{x, xt}:
      {==}
    case SCon{y, yt} SNil{}:
      meta.tf_absurd({SNil{} == String.append(SCon{y, yt}, String.drop(SNil{}, String.length(SCon{y, yt}))) : String}, Equal.sym(Bool, False{}, True{}, h))
    case SCon{+y, +yt} SCon{+x, +xt}:
      %Equal.sym(Char, x, y, meta.char_eq(x, y, meta.go_if_b(yt, xt, Char.is_eq(x, y), h))) : {SCon{_, xt} == SCon{y, String.append(yt, String.drop(xt, String.length(yt)))} : String}
      %Equal.sym(String, xt, String.append(yt, String.drop(xt, String.length(yt))), meta.sw_decomp(yt, xt, meta.go_if_t(yt, xt, Char.is_eq(x, y), h))) : {SCon{y, _} == SCon{y, String.append(yt, String.drop(xt, String.length(yt)))} : String}
      {==}

def meta.LP() -> String:
  "vcluster.loft.sh/label-"

law meta.conv_lp_if:
  for b: Bool
  for +vc: String
  for +hh: String
  {String.starts_with(N.Names.shorten.if(b, String.join(["vcluster.loft.sh/label", vc, "x", hh], "-")), meta.LP()) == True{} : Bool}

def meta.conv_lp_if(b, vc, hh):
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

law meta.conv_lp:
  for +vc: String
  for +hh: String
  {String.starts_with(M.Meta.convert.h(M.Meta.label_prefix(), vc, hh), meta.LP()) == True{} : Bool}

def meta.conv_lp(vc, hh):
  meta.conv_lp_if(Nat.is_le(String.length(String.join(["vcluster.loft.sh/label", vc, "x", hh], "-")), 63n), vc, hh)

def meta.VP() -> String:
  "vcluster.loft.sh/"

def meta.CR(vc: String) -> String:
  M.Meta.convert.h(M.Meta.label_prefix(), vc, "a4d451ec23")

def meta.CN(vc: String) -> String:
  M.Meta.convert.h(M.Meta.label_prefix(), vc, "101dcd4e86")

def meta.CM(vc: String) -> String:
  M.Meta.convert.h(M.Meta.label_prefix(), vc, "e5f1b28ab2")

def meta.CC(vc: String) -> String:
  M.Meta.convert.h(M.Meta.label_prefix(), vc, "2080cec00f")

law meta.lp_pre:
  for +s: String
  for +h: {String.starts_with(s, meta.LP()) == True{} : Bool}
  {String.starts_with(s, meta.VP()) == True{} : Bool}

def meta.lp_pre(s, h):
  %Equal.sym(String, s, String.append(meta.LP(), String.drop(s, String.length(meta.LP()))), meta.sw_decomp(meta.LP(), s, h)) : {String.starts_with(_, meta.VP()) == True{} : Bool}
  {==}

law meta.lp_not_nsp:
  for +s: String
  for +h: {String.starts_with(s, meta.LP()) == True{} : Bool}
  {String.starts_with(s, M.Meta.namespace_label_prefix()) == False{} : Bool}

def meta.lp_not_nsp(s, h):
  %Equal.sym(String, s, String.append(meta.LP(), String.drop(s, String.length(meta.LP()))), meta.sw_decomp(meta.LP(), s, h)) : {String.starts_with(_, M.Meta.namespace_label_prefix()) == False{} : Bool}
  {==}

law meta.lp_ne_ns:
  for +s: String
  for +h: {String.starts_with(s, meta.LP()) == True{} : Bool}
  {String.eq(s, M.Meta.namespace_label()) == False{} : Bool}

def meta.lp_ne_ns(s, h):
  %Equal.sym(String, s, String.append(meta.LP(), String.drop(s, String.length(meta.LP()))), meta.sw_decomp(meta.LP(), s, h)) : {String.eq(_, M.Meta.namespace_label()) == False{} : Bool}
  {==}

law meta.lp_ne_mk:
  for +s: String
  for +h: {String.starts_with(s, meta.LP()) == True{} : Bool}
  {String.eq(s, M.Meta.marker_label()) == False{} : Bool}

def meta.lp_ne_mk(s, h):
  %Equal.sym(String, s, String.append(meta.LP(), String.drop(s, String.length(meta.LP()))), meta.sw_decomp(meta.LP(), s, h)) : {String.eq(_, M.Meta.marker_label()) == False{} : Bool}
  {==}

law meta.lp_ne_ctl:
  for +s: String
  for +h: {String.starts_with(s, meta.LP()) == True{} : Bool}
  {String.eq(s, M.Meta.controller_label()) == False{} : Bool}

def meta.lp_ne_ctl(s, h):
  %Equal.sym(String, s, String.append(meta.LP(), String.drop(s, String.length(meta.LP()))), meta.sw_decomp(meta.LP(), s, h)) : {String.eq(_, M.Meta.controller_label()) == False{} : Bool}
  {==}

law meta.lp_ne_rel:
  for +s: String
  for +h: {String.starts_with(s, meta.LP()) == True{} : Bool}
  {String.eq(s, M.Meta.release_label()) == False{} : Bool}

def meta.lp_ne_rel(s, h):
  %Equal.sym(String, s, String.append(meta.LP(), String.drop(s, String.length(meta.LP()))), meta.sw_decomp(meta.LP(), s, h)) : {String.eq(_, M.Meta.release_label()) == False{} : Bool}
  {==}

law meta.is_eq_flip:
  for c: Cmp
  {Cmp.is_eq(meta.flip(c)) == Cmp.is_eq(c) : Bool}

def meta.is_eq_flip(c):
  match c:
    case LT{}:
      {==}
    case EQ{}:
      {==}
    case GT{}:
      {==}

law meta.eq_sym:
  for +a: String
  for +b: String
  {String.eq(a, b) == String.eq(b, a) : Bool}

def meta.eq_sym(a, b):
  %Equal.sym(Cmp, String.order(b, a), meta.flip(String.order(a, b)), meta.str_flip(a, b, EQ{})) : {String.eq(a, b) == Cmp.is_eq(_) : Bool}
  Equal.sym(Bool, Cmp.is_eq(meta.flip(String.order(a, b))), Cmp.is_eq(String.order(a, b)), meta.is_eq_flip(String.order(a, b)))

law meta.epf_go:
  for b: Bool
  for +k: String
  for +x: String
  for +e: {String.eq(k, x) == b : Bool}
  for +hk: {String.starts_with(k, meta.VP()) == False{} : Bool}
  for +hx: {String.starts_with(x, meta.VP()) == True{} : Bool}
  {b == False{} : Bool}

def meta.epf_go(b, k, x, e, hk, hx):
  match b:
    case False{}:
      {==}
    case True{}:
      meta.tf_absurd({True{} == False{} : Bool},
        Equal.trans(Bool, True{}, String.starts_with(x, meta.VP()), False{}, Equal.sym(Bool, String.starts_with(x, meta.VP()), True{}, hx),
          (%meta.str_eq(k, x, meta.is_eq_true(String.order(k, x), e)) : {String.starts_with(_, meta.VP()) == False{} : Bool}; hk)))

# A string without the vcluster prefix differs from one with it.
law meta.eq_pre_false:
  for +k: String
  for +x: String
  for +hk: {String.starts_with(k, meta.VP()) == False{} : Bool}
  for +hx: {String.starts_with(x, meta.VP()) == True{} : Bool}
  {String.eq(k, x) == False{} : Bool}

def meta.eq_pre_false(k, x, hk, hx):
  meta.epf_go(String.eq(k, x), k, x, {==}, hk, hx)

law meta.eq_pre_false_r:
  for +x: String
  for +k: String
  for +hk: {String.starts_with(k, meta.VP()) == False{} : Bool}
  for +hx: {String.starts_with(x, meta.VP()) == True{} : Bool}
  {String.eq(x, k) == False{} : Bool}

def meta.eq_pre_false_r(x, k, hk, hx):
  Equal.trans(Bool, String.eq(x, k), String.eq(k, x), False{}, meta.eq_sym(x, k), meta.eq_pre_false(k, x, hk, hx))

law meta.nsp_go:
  for b: Bool
  for +k: String
  for +e: {String.starts_with(k, M.Meta.namespace_label_prefix()) == b : Bool}
  for +hk: {String.starts_with(k, meta.VP()) == False{} : Bool}
  {b == False{} : Bool}

def meta.nsp_go(b, k, e, hk):
  match b:
    case False{}:
      {==}
    case True{}:
      meta.tf_absurd({True{} == False{} : Bool},
        Equal.trans(Bool, True{}, String.starts_with(k, meta.VP()), False{},
          Equal.sym(Bool, String.starts_with(k, meta.VP()), True{},
            (%Equal.sym(String, k, String.append(M.Meta.namespace_label_prefix(), String.drop(k, String.length(M.Meta.namespace_label_prefix()))),
                meta.sw_decomp(M.Meta.namespace_label_prefix(), k, e)) : {String.starts_with(_, meta.VP()) == True{} : Bool}; {==})),
          hk))

law meta.nsp_unpre:
  for +k: String
  for +hk: {String.starts_with(k, meta.VP()) == False{} : Bool}
  {String.starts_with(k, M.Meta.namespace_label_prefix()) == False{} : Bool}

def meta.nsp_unpre(k, hk):
  meta.nsp_go(String.starts_with(k, M.Meta.namespace_label_prefix()), k, {==}, hk)

# The translated-key table on keys of each class.

law meta.conv_ne_unpre:
  for +vc: String
  for +hh: String
  for +k: String
  for +hk: {String.starts_with(k, meta.VP()) == False{} : Bool}
  {String.eq(M.Meta.convert.h(M.Meta.label_prefix(), vc, hh), k) == False{} : Bool}

def meta.conv_ne_unpre(vc, hh, k, hk):
  meta.eq_pre_false_r(M.Meta.convert.h(M.Meta.label_prefix(), vc, hh), k, hk, meta.lp_pre(M.Meta.convert.h(M.Meta.label_prefix(), vc, hh), meta.conv_lp(vc, hh)))

law meta.get_tk_unpre:
  for +vc: String
  for +k: String
  for +hk: {String.starts_with(k, meta.VP()) == False{} : Bool}
  {M.Meta.get(k, M.Meta.tkeys(vc)) == M.Meta.get.if(String.order(k, "release"), meta.CR(vc), None{}) : Maybe<&2, String>}

def meta.get_tk_unpre(vc, k, hk):
  +x3 = {M.Meta.get.if(String.order(k, M.Meta.controller_label()), meta.CC(vc), None{}) : Maybe<&2, String>}
  +x2 = {M.Meta.get.if(String.order(k, M.Meta.marker_label()), meta.CM(vc), x3) : Maybe<&2, String>}
  +e1 = meta.get_if_ne(String.order(k, M.Meta.controller_label()), meta.CC(vc), None{}, meta.eq_pre_false(k, M.Meta.controller_label(), hk, {==}))
  +e2 = meta.get_if_ne(String.order(k, M.Meta.marker_label()), meta.CM(vc), x3, meta.eq_pre_false(k, M.Meta.marker_label(), hk, {==}))
  +e3 = meta.get_if_ne(String.order(k, M.Meta.namespace_label()), meta.CN(vc), x2, meta.eq_pre_false(k, M.Meta.namespace_label(), hk, {==}))
  +inner = Equal.trans(Maybe<&2, String>, M.Meta.get.if(String.order(k, M.Meta.namespace_label()), meta.CN(vc), x2), x2, None{}, e3,
    Equal.trans(Maybe<&2, String>, x2, x3, None{}, e2, e1))
  %Equal.sym(Maybe<&2, String>, M.Meta.get.if(String.order(k, M.Meta.namespace_label()), meta.CN(vc), x2), None{}, inner) :
    {M.Meta.get.if(String.order(k, "release"), meta.CR(vc), _) == M.Meta.get.if(String.order(k, "release"), meta.CR(vc), None{}) : Maybe<&2, String>}
  {==}

law meta.it_if_false:
  for b: Bool
  for o: String
  for +rec: Maybe<&2, String>
  for +h: {b == False{} : Bool}
  {M.Meta.is_translated.if(b, o, rec) == rec : Maybe<&2, String>}

def meta.it_if_false(b, o, rec, h):
  %Equal.sym(Bool, b, False{}, h) : {M.Meta.is_translated.if(_, o, rec) == rec : Maybe<&2, String>}
  {==}

law meta.it_unpre:
  for +vc: String
  for +k: String
  for +hk: {String.starts_with(k, meta.VP()) == False{} : Bool}
  {M.Meta.is_translated.t(M.Meta.tkeys(vc), k) == None{} : Maybe<&2, String>}

def meta.it_unpre(vc, k, hk):
  +y3 = {M.Meta.is_translated.if(String.eq(meta.CC(vc), k), M.Meta.controller_label(), None{}) : Maybe<&2, String>}
  +y2 = {M.Meta.is_translated.if(String.eq(meta.CM(vc), k), M.Meta.marker_label(), y3) : Maybe<&2, String>}
  +y1 = {M.Meta.is_translated.if(String.eq(meta.CN(vc), k), M.Meta.namespace_label(), y2) : Maybe<&2, String>}
  Equal.trans(Maybe<&2, String>, M.Meta.is_translated.if(String.eq(meta.CR(vc), k), M.Meta.release_label(), y1), y1, None{},
    meta.it_if_false(String.eq(meta.CR(vc), k), M.Meta.release_label(), y1, meta.conv_ne_unpre(vc, "a4d451ec23", k, hk)),
    Equal.trans(Maybe<&2, String>, y1, y2, None{},
      meta.it_if_false(String.eq(meta.CN(vc), k), M.Meta.namespace_label(), y2, meta.conv_ne_unpre(vc, "101dcd4e86", k, hk)),
      Equal.trans(Maybe<&2, String>, y2, y3, None{},
        meta.it_if_false(String.eq(meta.CM(vc), k), M.Meta.marker_label(), y3, meta.conv_ne_unpre(vc, "e5f1b28ab2", k, hk)),
        meta.it_if_false(String.eq(meta.CC(vc), k), M.Meta.controller_label(), None{}, meta.conv_ne_unpre(vc, "2080cec00f", k, hk)))))

law meta.eq_refl:
  for +s: String
  {String.eq(s, s) == True{} : Bool}

def meta.eq_refl(s):
  %Equal.sym(Cmp, String.order(s, s), EQ{}, meta.str_refl(s)) : {Cmp.is_eq(_) == True{} : Bool}
  {==}

law meta.hl_unpre_eq:
  for +vc: String
  for +k: String
  for +hk: {String.starts_with(k, meta.VP()) == False{} : Bool}
  for +c: {String.order(k, "release") == EQ{} : Cmp}
  {M.Meta.host_label.t(M.Meta.tkeys(vc), k) == meta.CR(vc) : String}

def meta.hl_unpre_eq(vc, k, hk, c):
  %Equal.sym(Maybe<&2, String>, M.Meta.get(k, M.Meta.tkeys(vc)), M.Meta.get.if(String.order(k, "release"), meta.CR(vc), None{}), meta.get_tk_unpre(vc, k, hk)) :
    {Maybe.default(&2, String, _, k) == meta.CR(vc) : String}
  %Equal.sym(Cmp, String.order(k, "release"), EQ{}, c) : {Maybe.default(&2, String, M.Meta.get.if(_, meta.CR(vc), None{}), k) == meta.CR(vc) : String}
  {==}

law meta.hl_unpre_ne:
  for +vc: String
  for +k: String
  for +hk: {String.starts_with(k, meta.VP()) == False{} : Bool}
  for +n: {Cmp.is_eq(String.order(k, "release")) == False{} : Bool}
  {M.Meta.host_label.t(M.Meta.tkeys(vc), k) == k : String}

def meta.hl_unpre_ne(vc, k, hk, n):
  %Equal.sym(Maybe<&2, String>, M.Meta.get(k, M.Meta.tkeys(vc)), M.Meta.get.if(String.order(k, "release"), meta.CR(vc), None{}), meta.get_tk_unpre(vc, k, hk)) :
    {Maybe.default(&2, String, _, k) == k : String}
  %Equal.sym(Maybe<&2, String>, M.Meta.get.if(String.order(k, "release"), meta.CR(vc), None{}), None{}, meta.get_if_ne(String.order(k, "release"), meta.CR(vc), None{}, n)) :
    {Maybe.default(&2, String, _, k) == k : String}
  {==}

law meta.vl_unpre_eq:
  for +vc: String
  for +k: String
  for +hk: {String.starts_with(k, meta.VP()) == False{} : Bool}
  for +c: {String.order(k, "release") == EQ{} : Cmp}
  {M.Meta.virtual_label.t(M.Meta.tkeys(vc), k) == None{} : Maybe<&2, String>}

def meta.vl_unpre_eq(vc, k, hk, c):
  %Equal.sym(Maybe<&2, String>, M.Meta.get(k, M.Meta.tkeys(vc)), M.Meta.get.if(String.order(k, "release"), meta.CR(vc), None{}), meta.get_tk_unpre(vc, k, hk)) :
    {M.Meta.virtual_label.if(Maybe.is_some(&2, String, _), M.Meta.tkeys(vc), k) == None{} : Maybe<&2, String>}
  %Equal.sym(Cmp, String.order(k, "release"), EQ{}, c) :
    {M.Meta.virtual_label.if(Maybe.is_some(&2, String, M.Meta.get.if(_, meta.CR(vc), None{})), M.Meta.tkeys(vc), k) == None{} : Maybe<&2, String>}
  {==}

law meta.vl_unpre_ne:
  for +vc: String
  for +k: String
  for +hk: {String.starts_with(k, meta.VP()) == False{} : Bool}
  for +n: {Cmp.is_eq(String.order(k, "release")) == False{} : Bool}
  {M.Meta.virtual_label.t(M.Meta.tkeys(vc), k) == Some{k} : Maybe<&2, String>}

def meta.vl_unpre_ne(vc, k, hk, n):
  %Equal.sym(Maybe<&2, String>, M.Meta.get(k, M.Meta.tkeys(vc)), M.Meta.get.if(String.order(k, "release"), meta.CR(vc), None{}), meta.get_tk_unpre(vc, k, hk)) :
    {M.Meta.virtual_label.if(Maybe.is_some(&2, String, _), M.Meta.tkeys(vc), k) == Some{k} : Maybe<&2, String>}
  %Equal.sym(Maybe<&2, String>, M.Meta.get.if(String.order(k, "release"), meta.CR(vc), None{}), None{}, meta.get_if_ne(String.order(k, "release"), meta.CR(vc), None{}, n)) :
    {M.Meta.virtual_label.if(Maybe.is_some(&2, String, _), M.Meta.tkeys(vc), k) == Some{k} : Maybe<&2, String>}
  %Equal.sym(Maybe<&2, String>, M.Meta.is_translated.t(M.Meta.tkeys(vc), k), None{}, meta.it_unpre(vc, k, hk)) :
    {Maybe.or(&2, String, _, Some{k}) == Some{k} : Maybe<&2, String>}
  {==}

law meta.get_tk_cr:
  for +vc: String
  {M.Meta.get(meta.CR(vc), M.Meta.tkeys(vc)) == None{} : Maybe<&2, String>}

def meta.get_tk_cr(vc):
  +lp = meta.conv_lp(vc, "a4d451ec23")
  +x3 = {M.Meta.get.if(String.order(meta.CR(vc), M.Meta.controller_label()), meta.CC(vc), None{}) : Maybe<&2, String>}
  +x2 = {M.Meta.get.if(String.order(meta.CR(vc), M.Meta.marker_label()), meta.CM(vc), x3) : Maybe<&2, String>}
  +x1 = {M.Meta.get.if(String.order(meta.CR(vc), M.Meta.namespace_label()), meta.CN(vc), x2) : Maybe<&2, String>}
  Equal.trans(Maybe<&2, String>, M.Meta.get.if(String.order(meta.CR(vc), "release"), meta.CR(vc), x1), x1, None{},
    meta.get_if_ne(String.order(meta.CR(vc), "release"), meta.CR(vc), x1, meta.lp_ne_rel(meta.CR(vc), lp)),
    Equal.trans(Maybe<&2, String>, x1, x2, None{}, meta.get_if_ne(String.order(meta.CR(vc), M.Meta.namespace_label()), meta.CN(vc), x2, meta.lp_ne_ns(meta.CR(vc), lp)),
      Equal.trans(Maybe<&2, String>, x2, x3, None{}, meta.get_if_ne(String.order(meta.CR(vc), M.Meta.marker_label()), meta.CM(vc), x3, meta.lp_ne_mk(meta.CR(vc), lp)),
        meta.get_if_ne(String.order(meta.CR(vc), M.Meta.controller_label()), meta.CC(vc), None{}, meta.lp_ne_ctl(meta.CR(vc), lp)))))

law meta.vl_cr:
  for +vc: String
  {M.Meta.virtual_label.t(M.Meta.tkeys(vc), meta.CR(vc)) == Some{"release"} : Maybe<&2, String>}

def meta.vl_cr(vc):
  %Equal.sym(Maybe<&2, String>, M.Meta.get(meta.CR(vc), M.Meta.tkeys(vc)), None{}, meta.get_tk_cr(vc)) :
    {M.Meta.virtual_label.if(Maybe.is_some(&2, String, _), M.Meta.tkeys(vc), meta.CR(vc)) == Some{"release"} : Maybe<&2, String>}
  %Equal.sym(Bool, String.eq(meta.CR(vc), meta.CR(vc)), True{}, meta.eq_refl(meta.CR(vc))) :
    {Maybe.or(&2, String, M.Meta.is_translated.if(_, "release", M.Meta.is_translated.t([M.KV{M.Meta.namespace_label(), meta.CN(vc)}, M.KV{M.Meta.marker_label(), meta.CM(vc)}, M.KV{M.Meta.controller_label(), meta.CC(vc)}], meta.CR(vc))), Some{meta.CR(vc)}) == Some{"release"} : Maybe<&2, String>}
  {==}

law meta.eq_flip:
  for +a: String
  for +b: String
  for +e: {String.order(a, b) == EQ{} : Cmp}
  {String.order(b, a) == EQ{} : Cmp}

def meta.eq_flip(a, b, e):
  Equal.trans(Cmp, String.order(b, a), meta.flip(String.order(a, b)), EQ{}, meta.str_flip(a, b, EQ{}),
    Equal.cong(Cmp, Cmp, meta.flip, String.order(a, b), EQ{}, e))

law meta.it3:
  for b1: Bool
  for b2: Bool
  for b3: Bool
  for +k: String
  for +q: String
  for +hkq: {String.eq(k, q) == False{} : Bool}
  for +hq: {String.starts_with(q, meta.VP()) == False{} : Bool}
  {M.Meta.maybe_is(Maybe.or(&2, String, M.Meta.is_translated.if(b1, M.Meta.namespace_label(), M.Meta.is_translated.if(b2, M.Meta.marker_label(), M.Meta.is_translated.if(b3, M.Meta.controller_label(), None{}))), Some{k}), q) == False{} : Bool}

def meta.it3(b1, b2, b3, k, q, hkq, hq):
  match b1:
    case True{}:
      meta.eq_pre_false_r(M.Meta.namespace_label(), q, hq, {==})
    case False{}:
      match b2:
        case True{}:
          meta.eq_pre_false_r(M.Meta.marker_label(), q, hq, {==})
        case False{}:
          match b3:
            case True{}:
              meta.eq_pre_false_r(M.Meta.controller_label(), q, hq, {==})
            case False{}:
              hkq

law meta.vlp_if:
  for b: Bool
  for +vc: String
  for +k: String
  for +q: String
  for +hk: {String.starts_with(k, meta.VP()) == True{} : Bool}
  for +hn: {String.eq(meta.CR(vc), k) == False{} : Bool}
  for +hq: {String.starts_with(q, meta.VP()) == False{} : Bool}
  {M.Meta.maybe_is(M.Meta.virtual_label.if(b, M.Meta.tkeys(vc), k), q) == False{} : Bool}

def meta.vlp_if(b, vc, k, q, hk, hn, hq):
  match b:
    case True{}:
      {==}
    case False{}:
      %Equal.sym(Bool, String.eq(meta.CR(vc), k), False{}, hn) :
        {M.Meta.maybe_is(Maybe.or(&2, String, M.Meta.is_translated.if(_, "release", M.Meta.is_translated.t([M.KV{M.Meta.namespace_label(), meta.CN(vc)}, M.KV{M.Meta.marker_label(), meta.CM(vc)}, M.KV{M.Meta.controller_label(), meta.CC(vc)}], k)), Some{k}), q) == False{} : Bool}
      meta.it3(String.eq(meta.CN(vc), k), String.eq(meta.CM(vc), k), String.eq(meta.CC(vc), k), k, q, meta.eq_pre_false_r(k, q, hq, hk), hq)

# A prefixed key other than the release key never translates back to an
# unprefixed one.
law meta.vlp:
  for +vc: String
  for +k: String
  for +q: String
  for +hk: {String.starts_with(k, meta.VP()) == True{} : Bool}
  for +hn: {String.eq(meta.CR(vc), k) == False{} : Bool}
  for +hq: {String.starts_with(q, meta.VP()) == False{} : Bool}
  {M.Meta.maybe_is(M.Meta.virtual_label.t(M.Meta.tkeys(vc), k), q) == False{} : Bool}

def meta.vlp(vc, k, q, hk, hn, hq):
  meta.vlp_if(M.Meta.has(k, M.Meta.tkeys(vc)), vc, k, q, hk, hn, hq)

law meta.gb_skip:
  for mv: Maybe<&2, String>
  for +val: String
  for +q: String
  for +rec: +List<M.KV>
  for +h: {M.Meta.maybe_is(mv, q) == False{} : Bool}
  {M.Meta.get(q, M.Meta.back.if(mv, val, rec)) == M.Meta.get(q, rec) : Maybe<&2, String>}

def meta.gb_skip(mv, val, q, rec, h):
  match mv:
    case None{}:
      {==}
    case Some{+x}:
      meta.get_if_ne(String.order(q, x), val, M.Meta.get(q, rec), Equal.trans(Bool, String.eq(q, x), String.eq(x, q), False{}, meta.eq_sym(q, x), h))

law meta.cr_of:
  for +vc: String
  for +k: String
  for +e: {String.eq(meta.CR(vc), k) == True{} : Bool}
  {meta.CR(vc) == k : String}

def meta.cr_of(vc, k, e):
  meta.str_eq(meta.CR(vc), k, meta.is_eq_true(String.order(meta.CR(vc), k), e))

# An unprefixed q other than "release": back keeps get(q, _).
law meta.vl_skip_q:
  for b: Bool
  for +vc: String
  for +k: String
  for +q: String
  for +ecr: {String.eq(meta.CR(vc), k) == b : Bool}
  for +hk: {String.starts_with(k, meta.VP()) == True{} : Bool}
  for +hq: {String.starts_with(q, meta.VP()) == False{} : Bool}
  for +hrq: {String.eq("release", q) == False{} : Bool}
  {M.Meta.maybe_is(M.Meta.virtual_label.t(M.Meta.tkeys(vc), k), q) == False{} : Bool}

def meta.vl_skip_q(b, vc, k, q, ecr, hk, hq, hrq):
  match b:
    case True{}:
      %meta.cr_of(vc, k, ecr) : {M.Meta.maybe_is(M.Meta.virtual_label.t(M.Meta.tkeys(vc), _), q) == False{} : Bool}
      %Equal.sym(Maybe<&2, String>, M.Meta.virtual_label.t(M.Meta.tkeys(vc), meta.CR(vc)), Some{"release"}, meta.vl_cr(vc)) : {M.Meta.maybe_is(_, q) == False{} : Bool}
      hrq
    case False{}:
      meta.vlp(vc, k, q, hk, ecr, hq)

law meta.back_n_un:
  for c: Cmp
  for +vc: String
  for +q: String
  for +k: String
  for +val: String
  for +rest: +List<M.KV>
  for +ec: {String.order(k, "release") == c : Cmp}
  for +hk: {String.starts_with(k, meta.VP()) == False{} : Bool}
  for +hr: {String.eq(q, "release") == False{} : Bool}
  for +ih: {M.Meta.get(q, M.Meta.back(M.Meta.tkeys(vc), rest)) == M.Meta.get(q, rest) : Maybe<&2, String>}
  {M.Meta.get(q, M.Meta.back.if(M.Meta.virtual_label.t(M.Meta.tkeys(vc), k), val, M.Meta.back(M.Meta.tkeys(vc), rest))) == M.Meta.get(q, M.KV{k, val} <> rest) : Maybe<&2, String>}

def meta.back_n_un(c, vc, q, k, val, rest, ec, hk, hr, ih):
  match c:
    case EQ{}:
      +n = meta.ne_move(q, "release", k, meta.eq_flip(k, "release", ec), hr)
      %Equal.sym(Maybe<&2, String>, M.Meta.virtual_label.t(M.Meta.tkeys(vc), k), None{}, meta.vl_unpre_eq(vc, k, hk, ec)) :
        {M.Meta.get(q, M.Meta.back.if(_, val, M.Meta.back(M.Meta.tkeys(vc), rest))) == M.Meta.get(q, M.KV{k, val} <> rest) : Maybe<&2, String>}
      Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.back(M.Meta.tkeys(vc), rest)), M.Meta.get(q, rest), M.Meta.get(q, M.KV{k, val} <> rest), ih,
        Equal.sym(Maybe<&2, String>, M.Meta.get(q, M.KV{k, val} <> rest), M.Meta.get(q, rest), meta.get_if_ne(String.order(q, k), val, M.Meta.get(q, rest), n)))
    case LT{}:
      %Equal.sym(Maybe<&2, String>, M.Meta.virtual_label.t(M.Meta.tkeys(vc), k), Some{k}, meta.vl_unpre_ne(vc, k, hk, meta.lt_not_eq(String.order(k, "release"), ec))) :
        {M.Meta.get(q, M.Meta.back.if(_, val, M.Meta.back(M.Meta.tkeys(vc), rest))) == M.Meta.get(q, M.KV{k, val} <> rest) : Maybe<&2, String>}
      %Equal.sym(Maybe<&2, String>, M.Meta.get(q, M.Meta.back(M.Meta.tkeys(vc), rest)), M.Meta.get(q, rest), ih) :
        {M.Meta.get.if(String.order(q, k), val, _) == M.Meta.get(q, M.KV{k, val} <> rest) : Maybe<&2, String>}
      {==}
    case GT{}:
      %Equal.sym(Maybe<&2, String>, M.Meta.virtual_label.t(M.Meta.tkeys(vc), k), Some{k}, meta.vl_unpre_ne(vc, k, hk, meta.gt_not_eq(String.order(k, "release"), ec))) :
        {M.Meta.get(q, M.Meta.back.if(_, val, M.Meta.back(M.Meta.tkeys(vc), rest))) == M.Meta.get(q, M.KV{k, val} <> rest) : Maybe<&2, String>}
      %Equal.sym(Maybe<&2, String>, M.Meta.get(q, M.Meta.back(M.Meta.tkeys(vc), rest)), M.Meta.get(q, rest), ih) :
        {M.Meta.get.if(String.order(q, k), val, _) == M.Meta.get(q, M.KV{k, val} <> rest) : Maybe<&2, String>}
      {==}

law meta.back_n_go:
  for pk: Bool
  for +vc: String
  for +q: String
  for +k: String
  for +val: String
  for +rest: +List<M.KV>
  for +epk: {String.starts_with(k, meta.VP()) == pk : Bool}
  for +hq: {String.starts_with(q, meta.VP()) == False{} : Bool}
  for +hr: {String.eq(q, "release") == False{} : Bool}
  for +ih: {M.Meta.get(q, M.Meta.back(M.Meta.tkeys(vc), rest)) == M.Meta.get(q, rest) : Maybe<&2, String>}
  {M.Meta.get(q, M.Meta.back.if(M.Meta.virtual_label.t(M.Meta.tkeys(vc), k), val, M.Meta.back(M.Meta.tkeys(vc), rest))) == M.Meta.get(q, M.KV{k, val} <> rest) : Maybe<&2, String>}

def meta.back_n_go(pk, vc, q, k, val, rest, epk, hq, hr, ih):
  match pk:
    case False{}:
      meta.back_n_un(String.order(k, "release"), vc, q, k, val, rest, {==}, epk, hr, ih)
    case True{}:
      +hrq = Equal.trans(Bool, String.eq("release", q), String.eq(q, "release"), False{}, meta.eq_sym("release", q), hr)
      Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.back.if(M.Meta.virtual_label.t(M.Meta.tkeys(vc), k), val, M.Meta.back(M.Meta.tkeys(vc), rest))), M.Meta.get(q, rest), M.Meta.get(q, M.KV{k, val} <> rest),
        Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.back.if(M.Meta.virtual_label.t(M.Meta.tkeys(vc), k), val, M.Meta.back(M.Meta.tkeys(vc), rest))), M.Meta.get(q, M.Meta.back(M.Meta.tkeys(vc), rest)), M.Meta.get(q, rest),
          meta.gb_skip(M.Meta.virtual_label.t(M.Meta.tkeys(vc), k), val, q, M.Meta.back(M.Meta.tkeys(vc), rest),
            meta.vl_skip_q(String.eq(meta.CR(vc), k), vc, k, q, {==}, epk, hq, hrq)),
          ih),
        Equal.sym(Maybe<&2, String>, M.Meta.get(q, M.KV{k, val} <> rest), M.Meta.get(q, rest),
          meta.get_if_ne(String.order(q, k), val, M.Meta.get(q, rest), meta.eq_pre_false(q, k, hq, epk))))

law meta.back_n:
  for +vc: String
  for +q: String
  for +r: +List<M.KV>
  for +hq: {String.starts_with(q, meta.VP()) == False{} : Bool}
  for +hr: {String.eq(q, "release") == False{} : Bool}
  {M.Meta.get(q, M.Meta.back(M.Meta.tkeys(vc), r)) == M.Meta.get(q, r) : Maybe<&2, String>}

def meta.back_n(vc, q, r, hq, hr):
  match r:
    case Nil{}:
      {==}
    case Con{M.KV{+k, +val}, +rest}:
      meta.back_n_go(String.starts_with(k, meta.VP()), vc, q, k, val, rest, {==}, hq, hr, meta.back_n(vc, q, rest, hq, hr))

law meta.back_rel_rhs:
  for +vc: String
  for +k: String
  for +val: String
  for +rest: +List<M.KV>
  for +hk: {String.starts_with(k, meta.VP()) == False{} : Bool}
  {M.Meta.get(meta.CR(vc), rest) == M.Meta.get(meta.CR(vc), M.KV{k, val} <> rest) : Maybe<&2, String>}

def meta.back_rel_rhs(vc, k, val, rest, hk):
  Equal.sym(Maybe<&2, String>, M.Meta.get(meta.CR(vc), M.KV{k, val} <> rest), M.Meta.get(meta.CR(vc), rest),
    meta.get_if_ne(String.order(meta.CR(vc), k), val, M.Meta.get(meta.CR(vc), rest), meta.conv_ne_unpre(vc, "a4d451ec23", k, hk)))

law meta.back_rel_un:
  for c: Cmp
  for +vc: String
  for +k: String
  for +val: String
  for +rest: +List<M.KV>
  for +ec: {String.order(k, "release") == c : Cmp}
  for +hk: {String.starts_with(k, meta.VP()) == False{} : Bool}
  for +ih: {M.Meta.get("release", M.Meta.back(M.Meta.tkeys(vc), rest)) == M.Meta.get(meta.CR(vc), rest) : Maybe<&2, String>}
  {M.Meta.get("release", M.Meta.back.if(M.Meta.virtual_label.t(M.Meta.tkeys(vc), k), val, M.Meta.back(M.Meta.tkeys(vc), rest))) == M.Meta.get(meta.CR(vc), M.KV{k, val} <> rest) : Maybe<&2, String>}

def meta.back_rel_un(c, vc, k, val, rest, ec, hk, ih):
  match c:
    case EQ{}:
      %Equal.sym(Maybe<&2, String>, M.Meta.virtual_label.t(M.Meta.tkeys(vc), k), None{}, meta.vl_unpre_eq(vc, k, hk, ec)) :
        {M.Meta.get("release", M.Meta.back.if(_, val, M.Meta.back(M.Meta.tkeys(vc), rest))) == M.Meta.get(meta.CR(vc), M.KV{k, val} <> rest) : Maybe<&2, String>}
      Equal.trans(Maybe<&2, String>, M.Meta.get("release", M.Meta.back(M.Meta.tkeys(vc), rest)), M.Meta.get(meta.CR(vc), rest), M.Meta.get(meta.CR(vc), M.KV{k, val} <> rest), ih, meta.back_rel_rhs(vc, k, val, rest, hk))
    case LT{}:
      +n = Equal.trans(Bool, String.eq("release", k), String.eq(k, "release"), False{}, meta.eq_sym("release", k), meta.lt_not_eq(String.order(k, "release"), ec))
      %Equal.sym(Maybe<&2, String>, M.Meta.virtual_label.t(M.Meta.tkeys(vc), k), Some{k}, meta.vl_unpre_ne(vc, k, hk, meta.lt_not_eq(String.order(k, "release"), ec))) :
        {M.Meta.get("release", M.Meta.back.if(_, val, M.Meta.back(M.Meta.tkeys(vc), rest))) == M.Meta.get(meta.CR(vc), M.KV{k, val} <> rest) : Maybe<&2, String>}
      Equal.trans(Maybe<&2, String>, M.Meta.get.if(String.order("release", k), val, M.Meta.get("release", M.Meta.back(M.Meta.tkeys(vc), rest))), M.Meta.get(meta.CR(vc), rest), M.Meta.get(meta.CR(vc), M.KV{k, val} <> rest),
        Equal.trans(Maybe<&2, String>, M.Meta.get.if(String.order("release", k), val, M.Meta.get("release", M.Meta.back(M.Meta.tkeys(vc), rest))), M.Meta.get("release", M.Meta.back(M.Meta.tkeys(vc), rest)), M.Meta.get(meta.CR(vc), rest),
          meta.get_if_ne(String.order("release", k), val, M.Meta.get("release", M.Meta.back(M.Meta.tkeys(vc), rest)), n), ih),
        meta.back_rel_rhs(vc, k, val, rest, hk))
    case GT{}:
      +n = Equal.trans(Bool, String.eq("release", k), String.eq(k, "release"), False{}, meta.eq_sym("release", k), meta.gt_not_eq(String.order(k, "release"), ec))
      %Equal.sym(Maybe<&2, String>, M.Meta.virtual_label.t(M.Meta.tkeys(vc), k), Some{k}, meta.vl_unpre_ne(vc, k, hk, meta.gt_not_eq(String.order(k, "release"), ec))) :
        {M.Meta.get("release", M.Meta.back.if(_, val, M.Meta.back(M.Meta.tkeys(vc), rest))) == M.Meta.get(meta.CR(vc), M.KV{k, val} <> rest) : Maybe<&2, String>}
      Equal.trans(Maybe<&2, String>, M.Meta.get.if(String.order("release", k), val, M.Meta.get("release", M.Meta.back(M.Meta.tkeys(vc), rest))), M.Meta.get(meta.CR(vc), rest), M.Meta.get(meta.CR(vc), M.KV{k, val} <> rest),
        Equal.trans(Maybe<&2, String>, M.Meta.get.if(String.order("release", k), val, M.Meta.get("release", M.Meta.back(M.Meta.tkeys(vc), rest))), M.Meta.get("release", M.Meta.back(M.Meta.tkeys(vc), rest)), M.Meta.get(meta.CR(vc), rest),
          meta.get_if_ne(String.order("release", k), val, M.Meta.get("release", M.Meta.back(M.Meta.tkeys(vc), rest)), n), ih),
        meta.back_rel_rhs(vc, k, val, rest, hk))

law meta.back_rel_pre:
  for b: Bool
  for +vc: String
  for +k: String
  for +val: String
  for +rest: +List<M.KV>
  for +ecr: {String.eq(meta.CR(vc), k) == b : Bool}
  for +hk: {String.starts_with(k, meta.VP()) == True{} : Bool}
  for +ih: {M.Meta.get("release", M.Meta.back(M.Meta.tkeys(vc), rest)) == M.Meta.get(meta.CR(vc), rest) : Maybe<&2, String>}
  {M.Meta.get("release", M.Meta.back.if(M.Meta.virtual_label.t(M.Meta.tkeys(vc), k), val, M.Meta.back(M.Meta.tkeys(vc), rest))) == M.Meta.get(meta.CR(vc), M.KV{k, val} <> rest) : Maybe<&2, String>}

def meta.back_rel_pre(b, vc, k, val, rest, ecr, hk, ih):
  match b:
    case True{}:
      %meta.cr_of(vc, k, ecr) : {M.Meta.get("release", M.Meta.back.if(M.Meta.virtual_label.t(M.Meta.tkeys(vc), _), val, M.Meta.back(M.Meta.tkeys(vc), rest))) == M.Meta.get(meta.CR(vc), M.KV{_, val} <> rest) : Maybe<&2, String>}
      %Equal.sym(Maybe<&2, String>, M.Meta.virtual_label.t(M.Meta.tkeys(vc), meta.CR(vc)), Some{"release"}, meta.vl_cr(vc)) :
        {M.Meta.get("release", M.Meta.back.if(_, val, M.Meta.back(M.Meta.tkeys(vc), rest))) == M.Meta.get(meta.CR(vc), M.KV{meta.CR(vc), val} <> rest) : Maybe<&2, String>}
      Equal.trans(Maybe<&2, String>, M.Meta.get("release", M.KV{"release", val} <> M.Meta.back(M.Meta.tkeys(vc), rest)), Some{val}, M.Meta.get(meta.CR(vc), M.KV{meta.CR(vc), val} <> rest),
        meta.get_self("release", val, M.Meta.back(M.Meta.tkeys(vc), rest)),
        Equal.sym(Maybe<&2, String>, M.Meta.get(meta.CR(vc), M.KV{meta.CR(vc), val} <> rest), Some{val}, meta.get_self(meta.CR(vc), val, rest)))
    case False{}:
      Equal.trans(Maybe<&2, String>, M.Meta.get("release", M.Meta.back.if(M.Meta.virtual_label.t(M.Meta.tkeys(vc), k), val, M.Meta.back(M.Meta.tkeys(vc), rest))), M.Meta.get(meta.CR(vc), rest), M.Meta.get(meta.CR(vc), M.KV{k, val} <> rest),
        Equal.trans(Maybe<&2, String>, M.Meta.get("release", M.Meta.back.if(M.Meta.virtual_label.t(M.Meta.tkeys(vc), k), val, M.Meta.back(M.Meta.tkeys(vc), rest))), M.Meta.get("release", M.Meta.back(M.Meta.tkeys(vc), rest)), M.Meta.get(meta.CR(vc), rest),
          meta.gb_skip(M.Meta.virtual_label.t(M.Meta.tkeys(vc), k), val, "release", M.Meta.back(M.Meta.tkeys(vc), rest), meta.vlp(vc, k, "release", hk, ecr, {==})),
          ih),
        Equal.sym(Maybe<&2, String>, M.Meta.get(meta.CR(vc), M.KV{k, val} <> rest), M.Meta.get(meta.CR(vc), rest), meta.get_if_ne(String.order(meta.CR(vc), k), val, M.Meta.get(meta.CR(vc), rest), ecr)))

law meta.back_rel_go:
  for pk: Bool
  for +vc: String
  for +k: String
  for +val: String
  for +rest: +List<M.KV>
  for +epk: {String.starts_with(k, meta.VP()) == pk : Bool}
  for +ih: {M.Meta.get("release", M.Meta.back(M.Meta.tkeys(vc), rest)) == M.Meta.get(meta.CR(vc), rest) : Maybe<&2, String>}
  {M.Meta.get("release", M.Meta.back.if(M.Meta.virtual_label.t(M.Meta.tkeys(vc), k), val, M.Meta.back(M.Meta.tkeys(vc), rest))) == M.Meta.get(meta.CR(vc), M.KV{k, val} <> rest) : Maybe<&2, String>}

def meta.back_rel_go(pk, vc, k, val, rest, epk, ih):
  match pk:
    case False{}:
      meta.back_rel_un(String.order(k, "release"), vc, k, val, rest, {==}, epk, ih)
    case True{}:
      meta.back_rel_pre(String.eq(meta.CR(vc), k), vc, k, val, rest, {==}, epk, ih)

law meta.back_rel:
  for +vc: String
  for +r: +List<M.KV>
  {M.Meta.get("release", M.Meta.back(M.Meta.tkeys(vc), r)) == M.Meta.get(meta.CR(vc), r) : Maybe<&2, String>}

def meta.back_rel(vc, r):
  match r:
    case Nil{}:
      {==}
    case Con{M.KV{+k, +val}, +rest}:
      meta.back_rel_go(String.starts_with(k, meta.VP()), vc, k, val, rest, {==}, meta.back_rel(vc, rest))

# Keys that are unprefixed or the release key.
def meta.gk(+vc: String, +k: String) -> Bool:
  Bool.or(Bool.not(String.starts_with(k, meta.VP())), String.eq(meta.CR(vc), k))

def meta.good_all(+vc: String, m: +List<M.KV>) -> Bool:
  match m:
    case Nil{}:
      True{}
    case Con{M.KV{k, v}, r}:
      Bool.and(meta.gk(vc, k), meta.good_all(vc, r))

law meta.gk_pre:
  for +vc: String
  for +k: String
  for +epk: {String.starts_with(k, meta.VP()) == True{} : Bool}
  for +hg: {meta.gk(vc, k) == True{} : Bool}
  {String.eq(meta.CR(vc), k) == True{} : Bool}

def meta.gk_pre(vc, k, epk, hg):
  %epk : {Bool.or(Bool.not(_), String.eq(meta.CR(vc), k)) == True{} : Bool}
  hg

law meta.back_vc_un:
  for c: Cmp
  for +vc: String
  for +q: String
  for +k: String
  for +val: String
  for +rest: +List<M.KV>
  for +ec: {String.order(k, "release") == c : Cmp}
  for +hk: {String.starts_with(k, meta.VP()) == False{} : Bool}
  for +hq: {String.starts_with(q, meta.VP()) == True{} : Bool}
  for +ih: {M.Meta.get(q, M.Meta.back(M.Meta.tkeys(vc), rest)) == None{} : Maybe<&2, String>}
  {M.Meta.get(q, M.Meta.back.if(M.Meta.virtual_label.t(M.Meta.tkeys(vc), k), val, M.Meta.back(M.Meta.tkeys(vc), rest))) == None{} : Maybe<&2, String>}

def meta.back_vc_un(c, vc, q, k, val, rest, ec, hk, hq, ih):
  match c:
    case EQ{}:
      %Equal.sym(Maybe<&2, String>, M.Meta.virtual_label.t(M.Meta.tkeys(vc), k), None{}, meta.vl_unpre_eq(vc, k, hk, ec)) :
        {M.Meta.get(q, M.Meta.back.if(_, val, M.Meta.back(M.Meta.tkeys(vc), rest))) == None{} : Maybe<&2, String>}
      ih
    case LT{}:
      %Equal.sym(Maybe<&2, String>, M.Meta.virtual_label.t(M.Meta.tkeys(vc), k), Some{k}, meta.vl_unpre_ne(vc, k, hk, meta.lt_not_eq(String.order(k, "release"), ec))) :
        {M.Meta.get(q, M.Meta.back.if(_, val, M.Meta.back(M.Meta.tkeys(vc), rest))) == None{} : Maybe<&2, String>}
      Equal.trans(Maybe<&2, String>, M.Meta.get.if(String.order(q, k), val, M.Meta.get(q, M.Meta.back(M.Meta.tkeys(vc), rest))), M.Meta.get(q, M.Meta.back(M.Meta.tkeys(vc), rest)), None{},
        meta.get_if_ne(String.order(q, k), val, M.Meta.get(q, M.Meta.back(M.Meta.tkeys(vc), rest)), meta.eq_pre_false_r(q, k, hk, hq)), ih)
    case GT{}:
      %Equal.sym(Maybe<&2, String>, M.Meta.virtual_label.t(M.Meta.tkeys(vc), k), Some{k}, meta.vl_unpre_ne(vc, k, hk, meta.gt_not_eq(String.order(k, "release"), ec))) :
        {M.Meta.get(q, M.Meta.back.if(_, val, M.Meta.back(M.Meta.tkeys(vc), rest))) == None{} : Maybe<&2, String>}
      Equal.trans(Maybe<&2, String>, M.Meta.get.if(String.order(q, k), val, M.Meta.get(q, M.Meta.back(M.Meta.tkeys(vc), rest))), M.Meta.get(q, M.Meta.back(M.Meta.tkeys(vc), rest)), None{},
        meta.get_if_ne(String.order(q, k), val, M.Meta.get(q, M.Meta.back(M.Meta.tkeys(vc), rest)), meta.eq_pre_false_r(q, k, hk, hq)), ih)

law meta.back_vc_go:
  for pk: Bool
  for +vc: String
  for +q: String
  for +k: String
  for +val: String
  for +rest: +List<M.KV>
  for +epk: {String.starts_with(k, meta.VP()) == pk : Bool}
  for +hq: {String.starts_with(q, meta.VP()) == True{} : Bool}
  for +hg: {meta.gk(vc, k) == True{} : Bool}
  for +ih: {M.Meta.get(q, M.Meta.back(M.Meta.tkeys(vc), rest)) == None{} : Maybe<&2, String>}
  {M.Meta.get(q, M.Meta.back.if(M.Meta.virtual_label.t(M.Meta.tkeys(vc), k), val, M.Meta.back(M.Meta.tkeys(vc), rest))) == None{} : Maybe<&2, String>}

def meta.back_vc_go(pk, vc, q, k, val, rest, epk, hq, hg, ih):
  match pk:
    case False{}:
      meta.back_vc_un(String.order(k, "release"), vc, q, k, val, rest, {==}, epk, hq, ih)
    case True{}:
      %meta.cr_of(vc, k, meta.gk_pre(vc, k, epk, hg)) : {M.Meta.get(q, M.Meta.back.if(M.Meta.virtual_label.t(M.Meta.tkeys(vc), _), val, M.Meta.back(M.Meta.tkeys(vc), rest))) == None{} : Maybe<&2, String>}
      %Equal.sym(Maybe<&2, String>, M.Meta.virtual_label.t(M.Meta.tkeys(vc), meta.CR(vc)), Some{"release"}, meta.vl_cr(vc)) :
        {M.Meta.get(q, M.Meta.back.if(_, val, M.Meta.back(M.Meta.tkeys(vc), rest))) == None{} : Maybe<&2, String>}
      Equal.trans(Maybe<&2, String>, M.Meta.get.if(String.order(q, "release"), val, M.Meta.get(q, M.Meta.back(M.Meta.tkeys(vc), rest))), M.Meta.get(q, M.Meta.back(M.Meta.tkeys(vc), rest)), None{},
        meta.get_if_ne(String.order(q, "release"), val, M.Meta.get(q, M.Meta.back(M.Meta.tkeys(vc), rest)), meta.eq_pre_false_r(q, "release", {==}, hq)), ih)

law meta.back_vc:
  for +vc: String
  for +q: String
  for +r: +List<M.KV>
  for +hq: {String.starts_with(q, meta.VP()) == True{} : Bool}
  for +hg: {meta.good_all(vc, r) == True{} : Bool}
  {M.Meta.get(q, M.Meta.back(M.Meta.tkeys(vc), r)) == None{} : Maybe<&2, String>}

def meta.back_vc(vc, q, r, hq, hg):
  match r:
    case Nil{}:
      {==}
    case Con{M.KV{+k, +val}, +rest}:
      meta.back_vc_go(String.starts_with(k, meta.VP()), vc, q, k, val, rest, {==}, hq,
        meta.and_l(meta.gk(vc, k), meta.good_all(vc, rest), hg),
        meta.back_vc(vc, q, rest, hq, meta.and_r(meta.gk(vc, k), meta.good_all(vc, rest), hg)))

# host_keys on a map without vcluster keys.

law meta.not_true:
  for b: Bool
  for h: {Bool.not(b) == True{} : Bool}
  {b == False{} : Bool}

def meta.not_true(b, h):
  match b:
    case False{}:
      {==}
    case True{}:
      Equal.sym(Bool, False{}, True{}, h)

law meta.nvk_head:
  for +k: String
  for +v: String
  for +r: +List<M.KV>
  for +h: {M.Meta.no_vc_keys(M.KV{k, v} <> r) == True{} : Bool}
  {String.starts_with(k, meta.VP()) == False{} : Bool}

def meta.nvk_head(k, v, r, h):
  meta.not_true(String.starts_with(k, meta.VP()), meta.and_l(Bool.not(String.starts_with(k, meta.VP())), M.Meta.no_vc_keys(r), h))

law meta.nvk_tail:
  for +k: String
  for +v: String
  for +r: +List<M.KV>
  for +h: {M.Meta.no_vc_keys(M.KV{k, v} <> r) == True{} : Bool}
  {M.Meta.no_vc_keys(r) == True{} : Bool}

def meta.nvk_tail(k, v, r, h):
  meta.and_r(Bool.not(String.starts_with(k, meta.VP())), M.Meta.no_vc_keys(r), h)

law meta.hk_cons:
  for +vc: String
  for +k: String
  for +v: String
  for +r: +List<M.KV>
  for +hk: {String.starts_with(k, meta.VP()) == False{} : Bool}
  {M.Meta.host_keys(M.Meta.tkeys(vc), M.KV{k, v} <> r) == M.Meta.insert(M.Meta.host_label.t(M.Meta.tkeys(vc), k), v, M.Meta.host_keys(M.Meta.tkeys(vc), r)) : +List<M.KV>}

def meta.hk_cons(vc, k, v, r, hk):
  %Equal.sym(Maybe<&2, String>, M.Meta.is_translated.t(M.Meta.tkeys(vc), k), None{}, meta.it_unpre(vc, k, hk)) :
    {M.Meta.host_keys.if(Maybe.is_some(&2, String, _), M.Meta.host_label.t(M.Meta.tkeys(vc), k), v, M.Meta.host_keys(M.Meta.tkeys(vc), r)) == M.Meta.insert(M.Meta.host_label.t(M.Meta.tkeys(vc), k), v, M.Meta.host_keys(M.Meta.tkeys(vc), r)) : +List<M.KV>}
  {==}

law meta.get_insert_cons_go:
  for c: Cmp
  for +q: String
  for +k: String
  for +v: String
  for +rec: +List<M.KV>
  for +r: +List<M.KV>
  for +ec: {String.order(q, k) == c : Cmp}
  for +ih: {M.Meta.get(q, rec) == M.Meta.get(q, r) : Maybe<&2, String>}
  {M.Meta.get(q, M.Meta.insert(k, v, rec)) == M.Meta.get(q, M.KV{k, v} <> r) : Maybe<&2, String>}

def meta.get_insert_cons_go(c, q, k, v, rec, r, ec, ih):
  match c:
    case EQ{}:
      %Equal.sym(String, q, k, meta.str_eq(q, k, ec)) : {M.Meta.get(_, M.Meta.insert(k, v, rec)) == M.Meta.get(_, M.KV{k, v} <> r) : Maybe<&2, String>}
      Equal.trans(Maybe<&2, String>, M.Meta.get(k, M.Meta.insert(k, v, rec)), Some{v}, M.Meta.get(k, M.KV{k, v} <> r),
        L.meta.get_insert_same(k, v, rec), Equal.sym(Maybe<&2, String>, M.Meta.get(k, M.KV{k, v} <> r), Some{v}, meta.get_self(k, v, r)))
    case LT{}:
      +n = meta.lt_not_eq(String.order(q, k), ec)
      Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.insert(k, v, rec)), M.Meta.get(q, r), M.Meta.get(q, M.KV{k, v} <> r),
        Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.insert(k, v, rec)), M.Meta.get(q, rec), M.Meta.get(q, r), L.meta.get_insert_other(q, k, v, rec, n), ih),
        Equal.sym(Maybe<&2, String>, M.Meta.get(q, M.KV{k, v} <> r), M.Meta.get(q, r), meta.get_if_ne(String.order(q, k), v, M.Meta.get(q, r), n)))
    case GT{}:
      +n = meta.gt_not_eq(String.order(q, k), ec)
      Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.insert(k, v, rec)), M.Meta.get(q, r), M.Meta.get(q, M.KV{k, v} <> r),
        Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.insert(k, v, rec)), M.Meta.get(q, rec), M.Meta.get(q, r), L.meta.get_insert_other(q, k, v, rec, n), ih),
        Equal.sym(Maybe<&2, String>, M.Meta.get(q, M.KV{k, v} <> r), M.Meta.get(q, r), meta.get_if_ne(String.order(q, k), v, M.Meta.get(q, r), n)))

law meta.get_insert_cons:
  for +q: String
  for +k: String
  for +v: String
  for +rec: +List<M.KV>
  for +r: +List<M.KV>
  for +ih: {M.Meta.get(q, rec) == M.Meta.get(q, r) : Maybe<&2, String>}
  {M.Meta.get(q, M.Meta.insert(k, v, rec)) == M.Meta.get(q, M.KV{k, v} <> r) : Maybe<&2, String>}

def meta.get_insert_cons(q, k, v, rec, r, ih):
  meta.get_insert_cons_go(String.order(q, k), q, k, v, rec, r, {==}, ih)

law meta.get_from_list:
  for +q: String
  for +xs: +List<M.KV>
  {M.Meta.get(q, M.Meta.from_list(xs)) == M.Meta.get(q, xs) : Maybe<&2, String>}

def meta.get_from_list(q, xs):
  match xs:
    case Nil{}:
      {==}
    case Con{M.KV{+k, +v}, +r}:
      meta.get_insert_cons(q, k, v, M.Meta.from_list(r), r, meta.get_from_list(q, r))

law meta.hk_n_go:
  for c: Cmp
  for +vc: String
  for +q: String
  for +k: String
  for +v: String
  for +r: +List<M.KV>
  for +ec: {String.order(k, "release") == c : Cmp}
  for +hk: {String.starts_with(k, meta.VP()) == False{} : Bool}
  for +hq: {String.starts_with(q, meta.VP()) == False{} : Bool}
  for +hr: {String.eq(q, "release") == False{} : Bool}
  for +ih: {M.Meta.get(q, M.Meta.host_keys(M.Meta.tkeys(vc), r)) == M.Meta.get(q, r) : Maybe<&2, String>}
  {M.Meta.get(q, M.Meta.insert(M.Meta.host_label.t(M.Meta.tkeys(vc), k), v, M.Meta.host_keys(M.Meta.tkeys(vc), r))) == M.Meta.get(q, M.KV{k, v} <> r) : Maybe<&2, String>}

def meta.hk_n_go(c, vc, q, k, v, r, ec, hk, hq, hr, ih):
  match c:
    case EQ{}:
      %Equal.sym(String, M.Meta.host_label.t(M.Meta.tkeys(vc), k), meta.CR(vc), meta.hl_unpre_eq(vc, k, hk, ec)) :
        {M.Meta.get(q, M.Meta.insert(_, v, M.Meta.host_keys(M.Meta.tkeys(vc), r))) == M.Meta.get(q, M.KV{k, v} <> r) : Maybe<&2, String>}
      Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.insert(meta.CR(vc), v, M.Meta.host_keys(M.Meta.tkeys(vc), r))), M.Meta.get(q, r), M.Meta.get(q, M.KV{k, v} <> r),
        Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.insert(meta.CR(vc), v, M.Meta.host_keys(M.Meta.tkeys(vc), r))), M.Meta.get(q, M.Meta.host_keys(M.Meta.tkeys(vc), r)), M.Meta.get(q, r),
          L.meta.get_insert_other(q, meta.CR(vc), v, M.Meta.host_keys(M.Meta.tkeys(vc), r), meta.eq_pre_false(q, meta.CR(vc), hq, meta.lp_pre(meta.CR(vc), meta.conv_lp(vc, "a4d451ec23")))),
          ih),
        Equal.sym(Maybe<&2, String>, M.Meta.get(q, M.KV{k, v} <> r), M.Meta.get(q, r),
          meta.get_if_ne(String.order(q, k), v, M.Meta.get(q, r), meta.ne_move(q, "release", k, meta.eq_flip(k, "release", ec), hr))))
    case LT{}:
      %Equal.sym(String, M.Meta.host_label.t(M.Meta.tkeys(vc), k), k, meta.hl_unpre_ne(vc, k, hk, meta.lt_not_eq(String.order(k, "release"), ec))) :
        {M.Meta.get(q, M.Meta.insert(_, v, M.Meta.host_keys(M.Meta.tkeys(vc), r))) == M.Meta.get(q, M.KV{k, v} <> r) : Maybe<&2, String>}
      meta.get_insert_cons(q, k, v, M.Meta.host_keys(M.Meta.tkeys(vc), r), r, ih)
    case GT{}:
      %Equal.sym(String, M.Meta.host_label.t(M.Meta.tkeys(vc), k), k, meta.hl_unpre_ne(vc, k, hk, meta.gt_not_eq(String.order(k, "release"), ec))) :
        {M.Meta.get(q, M.Meta.insert(_, v, M.Meta.host_keys(M.Meta.tkeys(vc), r))) == M.Meta.get(q, M.KV{k, v} <> r) : Maybe<&2, String>}
      meta.get_insert_cons(q, k, v, M.Meta.host_keys(M.Meta.tkeys(vc), r), r, ih)

law meta.hk_n:
  for +vc: String
  for +q: String
  for +m: +List<M.KV>
  for +hq: {String.starts_with(q, meta.VP()) == False{} : Bool}
  for +hr: {String.eq(q, "release") == False{} : Bool}
  for +hm: {M.Meta.no_vc_keys(m) == True{} : Bool}
  {M.Meta.get(q, M.Meta.host_keys(M.Meta.tkeys(vc), m)) == M.Meta.get(q, m) : Maybe<&2, String>}

def meta.hk_n(vc, q, m, hq, hr, hm):
  match m:
    case Nil{}:
      {==}
    case Con{M.KV{+k, +v}, +r}:
      +hk = meta.nvk_head(k, v, r, hm)
      %Equal.sym(+List<M.KV>, M.Meta.host_keys(M.Meta.tkeys(vc), M.KV{k, v} <> r), M.Meta.insert(M.Meta.host_label.t(M.Meta.tkeys(vc), k), v, M.Meta.host_keys(M.Meta.tkeys(vc), r)), meta.hk_cons(vc, k, v, r, hk)) :
        {M.Meta.get(q, _) == M.Meta.get(q, M.KV{k, v} <> r) : Maybe<&2, String>}
      meta.hk_n_go(String.order(k, "release"), vc, q, k, v, r, {==}, hk, hq, hr, meta.hk_n(vc, q, r, hq, hr, meta.nvk_tail(k, v, r, hm)))

law meta.hk_rel_go:
  for c: Cmp
  for +vc: String
  for +k: String
  for +v: String
  for +r: +List<M.KV>
  for +ec: {String.order(k, "release") == c : Cmp}
  for +hk: {String.starts_with(k, meta.VP()) == False{} : Bool}
  for +ih: {M.Meta.get(meta.CR(vc), M.Meta.host_keys(M.Meta.tkeys(vc), r)) == M.Meta.get("release", r) : Maybe<&2, String>}
  {M.Meta.get(meta.CR(vc), M.Meta.insert(M.Meta.host_label.t(M.Meta.tkeys(vc), k), v, M.Meta.host_keys(M.Meta.tkeys(vc), r))) == M.Meta.get("release", M.KV{k, v} <> r) : Maybe<&2, String>}

def meta.hk_rel_go(c, vc, k, v, r, ec, hk, ih):
  match c:
    case EQ{}:
      %Equal.sym(String, M.Meta.host_label.t(M.Meta.tkeys(vc), k), meta.CR(vc), meta.hl_unpre_eq(vc, k, hk, ec)) :
        {M.Meta.get(meta.CR(vc), M.Meta.insert(_, v, M.Meta.host_keys(M.Meta.tkeys(vc), r))) == M.Meta.get("release", M.KV{k, v} <> r) : Maybe<&2, String>}
      Equal.trans(Maybe<&2, String>, M.Meta.get(meta.CR(vc), M.Meta.insert(meta.CR(vc), v, M.Meta.host_keys(M.Meta.tkeys(vc), r))), Some{v}, M.Meta.get("release", M.KV{k, v} <> r),
        L.meta.get_insert_same(meta.CR(vc), v, M.Meta.host_keys(M.Meta.tkeys(vc), r)),
        Equal.sym(Maybe<&2, String>, M.Meta.get("release", M.KV{k, v} <> r), Some{v},
          (%Equal.sym(Cmp, String.order("release", k), EQ{}, meta.eq_flip(k, "release", ec)) : {M.Meta.get.if(_, v, M.Meta.get("release", r)) == Some{v} : Maybe<&2, String>}; {==})))
    case LT{}:
      +n = Equal.trans(Bool, String.eq("release", k), String.eq(k, "release"), False{}, meta.eq_sym("release", k), meta.lt_not_eq(String.order(k, "release"), ec))
      %Equal.sym(String, M.Meta.host_label.t(M.Meta.tkeys(vc), k), k, meta.hl_unpre_ne(vc, k, hk, meta.lt_not_eq(String.order(k, "release"), ec))) :
        {M.Meta.get(meta.CR(vc), M.Meta.insert(_, v, M.Meta.host_keys(M.Meta.tkeys(vc), r))) == M.Meta.get("release", M.KV{k, v} <> r) : Maybe<&2, String>}
      Equal.trans(Maybe<&2, String>, M.Meta.get(meta.CR(vc), M.Meta.insert(k, v, M.Meta.host_keys(M.Meta.tkeys(vc), r))), M.Meta.get("release", r), M.Meta.get("release", M.KV{k, v} <> r),
        Equal.trans(Maybe<&2, String>, M.Meta.get(meta.CR(vc), M.Meta.insert(k, v, M.Meta.host_keys(M.Meta.tkeys(vc), r))), M.Meta.get(meta.CR(vc), M.Meta.host_keys(M.Meta.tkeys(vc), r)), M.Meta.get("release", r),
          L.meta.get_insert_other(meta.CR(vc), k, v, M.Meta.host_keys(M.Meta.tkeys(vc), r), meta.conv_ne_unpre(vc, "a4d451ec23", k, hk)), ih),
        Equal.sym(Maybe<&2, String>, M.Meta.get("release", M.KV{k, v} <> r), M.Meta.get("release", r), meta.get_if_ne(String.order("release", k), v, M.Meta.get("release", r), n)))
    case GT{}:
      +n = Equal.trans(Bool, String.eq("release", k), String.eq(k, "release"), False{}, meta.eq_sym("release", k), meta.gt_not_eq(String.order(k, "release"), ec))
      %Equal.sym(String, M.Meta.host_label.t(M.Meta.tkeys(vc), k), k, meta.hl_unpre_ne(vc, k, hk, meta.gt_not_eq(String.order(k, "release"), ec))) :
        {M.Meta.get(meta.CR(vc), M.Meta.insert(_, v, M.Meta.host_keys(M.Meta.tkeys(vc), r))) == M.Meta.get("release", M.KV{k, v} <> r) : Maybe<&2, String>}
      Equal.trans(Maybe<&2, String>, M.Meta.get(meta.CR(vc), M.Meta.insert(k, v, M.Meta.host_keys(M.Meta.tkeys(vc), r))), M.Meta.get("release", r), M.Meta.get("release", M.KV{k, v} <> r),
        Equal.trans(Maybe<&2, String>, M.Meta.get(meta.CR(vc), M.Meta.insert(k, v, M.Meta.host_keys(M.Meta.tkeys(vc), r))), M.Meta.get(meta.CR(vc), M.Meta.host_keys(M.Meta.tkeys(vc), r)), M.Meta.get("release", r),
          L.meta.get_insert_other(meta.CR(vc), k, v, M.Meta.host_keys(M.Meta.tkeys(vc), r), meta.conv_ne_unpre(vc, "a4d451ec23", k, hk)), ih),
        Equal.sym(Maybe<&2, String>, M.Meta.get("release", M.KV{k, v} <> r), M.Meta.get("release", r), meta.get_if_ne(String.order("release", k), v, M.Meta.get("release", r), n)))

law meta.hk_rel:
  for +vc: String
  for +m: +List<M.KV>
  for +hm: {M.Meta.no_vc_keys(m) == True{} : Bool}
  {M.Meta.get(meta.CR(vc), M.Meta.host_keys(M.Meta.tkeys(vc), m)) == M.Meta.get("release", m) : Maybe<&2, String>}

def meta.hk_rel(vc, m, hm):
  match m:
    case Nil{}:
      {==}
    case Con{M.KV{+k, +v}, +r}:
      +hk = meta.nvk_head(k, v, r, hm)
      %Equal.sym(+List<M.KV>, M.Meta.host_keys(M.Meta.tkeys(vc), M.KV{k, v} <> r), M.Meta.insert(M.Meta.host_label.t(M.Meta.tkeys(vc), k), v, M.Meta.host_keys(M.Meta.tkeys(vc), r)), meta.hk_cons(vc, k, v, r, hk)) :
        {M.Meta.get(meta.CR(vc), _) == M.Meta.get("release", M.KV{k, v} <> r) : Maybe<&2, String>}
      meta.hk_rel_go(String.order(k, "release"), vc, k, v, r, {==}, hk, meta.hk_rel(vc, r, meta.nvk_tail(k, v, r, hm)))

# The host map R that VirtualLabelsMap reads back.

def meta.XS() -> +List<String>:
  [M.Meta.marker_label(), M.Meta.namespace_label(), M.Meta.controller_label()]

def meta.PS() -> +List<String>:
  [M.Meta.namespace_label_prefix()]

def meta.NL(+vc: String, m: +List<M.KV>) -> +List<M.KV>:
  M.Meta.host_keys(M.Meta.tkeys(vc), m)

def meta.NL2(+vc: String, target: String, +ns: String, m: +List<M.KV>) -> +List<M.KV>:
  M.Meta.add_marker.if(String.is_empty(ns), vc, target, ns, meta.NL(vc, m))

def meta.RR(+vc: String, target: String, +ns: String, m: +List<M.KV>) -> +List<M.KV>:
  M.Meta.union(M.Meta.keep_out(meta.NL2(vc, target, ns, m), meta.XS(), meta.PS()), [])

law meta.or_ff:
  for a: Bool
  for b: Bool
  for ha: {a == False{} : Bool}
  for hb: {b == False{} : Bool}
  {Bool.or(a, b) == False{} : Bool}

def meta.or_ff(a, b, ha, hb):
  %Equal.sym(Bool, a, False{}, ha) : {Bool.or(_, b) == False{} : Bool}
  hb

law meta.or_fl:
  for a: Bool
  for b: Bool
  for h: {Bool.or(a, b) == False{} : Bool}
  {a == False{} : Bool}

def meta.or_fl(a, b, h):
  match a:
    case False{}:
      {==}
    case True{}:
      h

law meta.or_fr:
  for a: Bool
  for b: Bool
  for h: {Bool.or(a, b) == False{} : Bool}
  {b == False{} : Bool}

def meta.or_fr(a, b, h):
  match a:
    case False{}:
      h
    case True{}:
      meta.tf_absurd({b == False{} : Bool}, h)

law meta.or_r:
  for a: Bool
  for b: Bool
  for h: {b == True{} : Bool}
  {Bool.or(a, b) == True{} : Bool}

def meta.or_r(a, b, h):
  match a:
    case False{}:
      h
    case True{}:
      {==}

law meta.excl_of:
  for +k: String
  for +h1: {String.eq(k, M.Meta.marker_label()) == False{} : Bool}
  for +h2: {String.eq(k, M.Meta.namespace_label()) == False{} : Bool}
  for +h3: {String.eq(k, M.Meta.controller_label()) == False{} : Bool}
  for +h4: {String.starts_with(k, M.Meta.namespace_label_prefix()) == False{} : Bool}
  {M.Meta.excluded(k, meta.XS(), meta.PS()) == False{} : Bool}

def meta.excl_of(k, h1, h2, h3, h4):
  meta.or_ff(M.Meta.elem(k, meta.XS()), M.Meta.any_prefix(k, meta.PS()),
    meta.or_ff(String.eq(k, M.Meta.marker_label()), M.Meta.elem(k, [M.Meta.namespace_label(), M.Meta.controller_label()]), h1,
      meta.or_ff(String.eq(k, M.Meta.namespace_label()), M.Meta.elem(k, [M.Meta.controller_label()]), h2,
        meta.or_ff(String.eq(k, M.Meta.controller_label()), False{}, h3, {==}))),
    meta.or_ff(String.starts_with(k, M.Meta.namespace_label_prefix()), False{}, h4, {==}))

law meta.excl_unpre:
  for +k: String
  for +hk: {String.starts_with(k, meta.VP()) == False{} : Bool}
  {M.Meta.excluded(k, meta.XS(), meta.PS()) == False{} : Bool}

def meta.excl_unpre(k, hk):
  meta.excl_of(k, meta.eq_pre_false(k, M.Meta.marker_label(), hk, {==}), meta.eq_pre_false(k, M.Meta.namespace_label(), hk, {==}),
    meta.eq_pre_false(k, M.Meta.controller_label(), hk, {==}), meta.nsp_unpre(k, hk))

law meta.excl_cr:
  for +vc: String
  {M.Meta.excluded(meta.CR(vc), meta.XS(), meta.PS()) == False{} : Bool}

def meta.excl_cr(vc):
  +lp = meta.conv_lp(vc, "a4d451ec23")
  meta.excl_of(meta.CR(vc), meta.lp_ne_mk(meta.CR(vc), lp), meta.lp_ne_ns(meta.CR(vc), lp), meta.lp_ne_ctl(meta.CR(vc), lp), meta.lp_not_nsp(meta.CR(vc), lp))

law meta.excl_mk:
  for +k: String
  for +h: {M.Meta.excluded(k, meta.XS(), meta.PS()) == False{} : Bool}
  {String.eq(k, M.Meta.marker_label()) == False{} : Bool}

def meta.excl_mk(k, h):
  meta.or_fl(String.eq(k, M.Meta.marker_label()), M.Meta.elem(k, [M.Meta.namespace_label(), M.Meta.controller_label()]),
    meta.or_fl(M.Meta.elem(k, meta.XS()), M.Meta.any_prefix(k, meta.PS()), h))

law meta.excl_ns:
  for +k: String
  for +h: {M.Meta.excluded(k, meta.XS(), meta.PS()) == False{} : Bool}
  {String.eq(k, M.Meta.namespace_label()) == False{} : Bool}

def meta.excl_ns(k, h):
  meta.or_fl(String.eq(k, M.Meta.namespace_label()), M.Meta.elem(k, [M.Meta.controller_label()]),
    meta.or_fr(String.eq(k, M.Meta.marker_label()), M.Meta.elem(k, [M.Meta.namespace_label(), M.Meta.controller_label()]),
      meta.or_fl(M.Meta.elem(k, meta.XS()), M.Meta.any_prefix(k, meta.PS()), h)))

law meta.get_keep_out_in_go:
  for c: Cmp
  for +q: String
  for +kk: String
  for +v: String
  for +r: +List<M.KV>
  for +rec: +List<M.KV>
  for +xs: +List<String>
  for +ps: +List<String>
  for +ec: {String.order(q, kk) == c : Cmp}
  for +h: {M.Meta.excluded(q, xs, ps) == False{} : Bool}
  for +ih: {M.Meta.get(q, rec) == M.Meta.get(q, r) : Maybe<&2, String>}
  {M.Meta.get(q, M.Meta.keep.if(M.Meta.excluded(kk, xs, ps), M.KV{kk, v}, rec)) == M.Meta.get(q, M.KV{kk, v} <> r) : Maybe<&2, String>}

def meta.get_keep_out_in_go(c, q, kk, v, r, rec, xs, ps, ec, h, ih):
  match c:
    case EQ{}:
      %Equal.sym(Bool, M.Meta.excluded(kk, xs, ps), False{}, (%meta.str_eq(q, kk, ec) : {M.Meta.excluded(_, xs, ps) == False{} : Bool}; h)) :
        {M.Meta.get(q, M.Meta.keep.if(_, M.KV{kk, v}, rec)) == M.Meta.get(q, M.KV{kk, v} <> r) : Maybe<&2, String>}
      %Equal.sym(Cmp, String.order(q, kk), EQ{}, ec) : {M.Meta.get.if(_, v, M.Meta.get(q, rec)) == M.Meta.get.if(_, v, M.Meta.get(q, r)) : Maybe<&2, String>}
      {==}
    case LT{}:
      +n = meta.lt_not_eq(String.order(q, kk), ec)
      Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.keep.if(M.Meta.excluded(kk, xs, ps), M.KV{kk, v}, rec)), M.Meta.get(q, r), M.Meta.get(q, M.KV{kk, v} <> r),
        Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.keep.if(M.Meta.excluded(kk, xs, ps), M.KV{kk, v}, rec)), M.Meta.get(q, rec), M.Meta.get(q, r),
          meta.get_keep_if_ne(M.Meta.excluded(kk, xs, ps), q, kk, v, rec, n), ih),
        Equal.sym(Maybe<&2, String>, M.Meta.get(q, M.KV{kk, v} <> r), M.Meta.get(q, r), meta.get_if_ne(String.order(q, kk), v, M.Meta.get(q, r), n)))
    case GT{}:
      +n = meta.gt_not_eq(String.order(q, kk), ec)
      Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.keep.if(M.Meta.excluded(kk, xs, ps), M.KV{kk, v}, rec)), M.Meta.get(q, r), M.Meta.get(q, M.KV{kk, v} <> r),
        Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.keep.if(M.Meta.excluded(kk, xs, ps), M.KV{kk, v}, rec)), M.Meta.get(q, rec), M.Meta.get(q, r),
          meta.get_keep_if_ne(M.Meta.excluded(kk, xs, ps), q, kk, v, rec, n), ih),
        Equal.sym(Maybe<&2, String>, M.Meta.get(q, M.KV{kk, v} <> r), M.Meta.get(q, r), meta.get_if_ne(String.order(q, kk), v, M.Meta.get(q, r), n)))

law meta.get_keep_out_in:
  for +q: String
  for +m: +List<M.KV>
  for +xs: +List<String>
  for +ps: +List<String>
  for +h: {M.Meta.excluded(q, xs, ps) == False{} : Bool}
  {M.Meta.get(q, M.Meta.keep_out(m, xs, ps)) == M.Meta.get(q, m) : Maybe<&2, String>}

def meta.get_keep_out_in(q, m, xs, ps, h):
  match m:
    case Nil{}:
      {==}
    case Con{M.KV{+kk, +v}, +r}:
      meta.get_keep_out_in_go(String.order(q, kk), q, kk, v, r, M.Meta.keep_out(r, xs, ps), xs, ps, {==}, h, meta.get_keep_out_in(q, r, xs, ps, h))

law meta.get_marker:
  for b: Bool
  for +q: String
  for +vc: String
  for +target: String
  for +ns: String
  for +nl: +List<M.KV>
  for +hm: {String.eq(q, M.Meta.marker_label()) == False{} : Bool}
  for +hn: {String.eq(q, M.Meta.namespace_label()) == False{} : Bool}
  {M.Meta.get(q, M.Meta.add_marker.if(b, vc, target, ns, nl)) == M.Meta.get(q, nl) : Maybe<&2, String>}

def meta.get_marker(b, q, vc, target, ns, nl, hm, hn):
  match b:
    case True{}:
      L.meta.get_insert_other(q, M.Meta.marker_label(), N.Names.marker_cluster(target, vc), nl, hm)
    case False{}:
      Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.insert(M.Meta.namespace_label(), ns, M.Meta.insert(M.Meta.marker_label(), vc, nl))), M.Meta.get(q, M.Meta.insert(M.Meta.marker_label(), vc, nl)), M.Meta.get(q, nl),
        L.meta.get_insert_other(q, M.Meta.namespace_label(), ns, M.Meta.insert(M.Meta.marker_label(), vc, nl), hn),
        L.meta.get_insert_other(q, M.Meta.marker_label(), vc, nl, hm))

law meta.or_none:
  for x: Maybe<&2, String>
  {Maybe.or(&2, String, x, None{}) == x : Maybe<&2, String>}

def meta.or_none(x):
  match x:
    case None{}:
      {==}
    case Some{y}:
      {==}

# On a key that VirtualLabelsMap does not exclude, R reads like host_keys.
law meta.rr_get:
  for +vc: String
  for +target: String
  for +ns: String
  for +m: +List<M.KV>
  for +q: String
  for +h: {M.Meta.excluded(q, meta.XS(), meta.PS()) == False{} : Bool}
  {M.Meta.get(q, meta.RR(vc, target, ns, m)) == M.Meta.get(q, meta.NL(vc, m)) : Maybe<&2, String>}

def meta.rr_get(vc, target, ns, m, q, h):
  +a = M.Meta.keep_out(meta.NL2(vc, target, ns, m), meta.XS(), meta.PS())
  Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.union(a, [])), Maybe.or(&2, String, M.Meta.get(q, a), None{}), M.Meta.get(q, meta.NL(vc, m)),
    meta.get_union(q, a, []),
    Equal.trans(Maybe<&2, String>, Maybe.or(&2, String, M.Meta.get(q, a), None{}), M.Meta.get(q, a), M.Meta.get(q, meta.NL(vc, m)),
      meta.or_none(M.Meta.get(q, a)),
      Equal.trans(Maybe<&2, String>, M.Meta.get(q, a), M.Meta.get(q, meta.NL2(vc, target, ns, m)), M.Meta.get(q, meta.NL(vc, m)),
        meta.get_keep_out_in(q, meta.NL2(vc, target, ns, m), meta.XS(), meta.PS(), h),
        meta.get_marker(String.is_empty(ns), q, vc, target, ns, meta.NL(vc, m), meta.excl_mk(q, h), meta.excl_ns(q, h)))))

# R holds only good keys.

def meta.goodx(+vc: String, +k: String) -> Bool:
  Bool.or(M.Meta.excluded(k, meta.XS(), meta.PS()), meta.gk(vc, k))

def meta.goodx_all(+vc: String, m: +List<M.KV>) -> Bool:
  match m:
    case Nil{}:
      True{}
    case Con{M.KV{k, v}, r}:
      Bool.and(meta.goodx(vc, k), meta.goodx_all(vc, r))

law meta.good_insert_go:
  for c: Cmp
  for +vc: String
  for +kk: String
  for +vv: String
  for +k: String
  for +v: String
  for +r: +List<M.KV>
  for +hk: {meta.gk(vc, k) == True{} : Bool}
  for +hm: {meta.good_all(vc, M.KV{kk, vv} <> r) == True{} : Bool}
  for +ih: {meta.good_all(vc, M.Meta.insert(k, v, r)) == True{} : Bool}
  {meta.good_all(vc, M.Meta.insert.if(c, kk, vv, k, v, r, M.Meta.insert(k, v, r))) == True{} : Bool}

def meta.good_insert_go(c, vc, kk, vv, k, v, r, hk, hm, ih):
  match c:
    case LT{}:
      meta.and_i(meta.gk(vc, k), meta.good_all(vc, M.KV{kk, vv} <> r), hk, hm)
    case EQ{}:
      hm
    case GT{}:
      meta.and_i(meta.gk(vc, kk), meta.good_all(vc, M.Meta.insert(k, v, r)), meta.and_l(meta.gk(vc, kk), meta.good_all(vc, r), hm), ih)

law meta.good_insert:
  for +vc: String
  for +k: String
  for +v: String
  for +m: +List<M.KV>
  for +hk: {meta.gk(vc, k) == True{} : Bool}
  for +hm: {meta.good_all(vc, m) == True{} : Bool}
  {meta.good_all(vc, M.Meta.insert(k, v, m)) == True{} : Bool}

def meta.good_insert(vc, k, v, m, hk, hm):
  match m:
    case Nil{}:
      meta.and_i(meta.gk(vc, k), True{}, hk, {==})
    case Con{M.KV{+kk, +vv}, +r}:
      meta.good_insert_go(String.order(k, kk), vc, kk, vv, k, v, r, hk, hm,
        meta.good_insert(vc, k, v, r, hk, meta.and_r(meta.gk(vc, kk), meta.good_all(vc, r), hm)))

law meta.goodx_insert_go:
  for c: Cmp
  for +vc: String
  for +kk: String
  for +vv: String
  for +k: String
  for +v: String
  for +r: +List<M.KV>
  for +hk: {meta.goodx(vc, k) == True{} : Bool}
  for +hm: {meta.goodx_all(vc, M.KV{kk, vv} <> r) == True{} : Bool}
  for +ih: {meta.goodx_all(vc, M.Meta.insert(k, v, r)) == True{} : Bool}
  {meta.goodx_all(vc, M.Meta.insert.if(c, kk, vv, k, v, r, M.Meta.insert(k, v, r))) == True{} : Bool}

def meta.goodx_insert_go(c, vc, kk, vv, k, v, r, hk, hm, ih):
  match c:
    case LT{}:
      meta.and_i(meta.goodx(vc, k), meta.goodx_all(vc, M.KV{kk, vv} <> r), hk, hm)
    case EQ{}:
      hm
    case GT{}:
      meta.and_i(meta.goodx(vc, kk), meta.goodx_all(vc, M.Meta.insert(k, v, r)), meta.and_l(meta.goodx(vc, kk), meta.goodx_all(vc, r), hm), ih)

law meta.goodx_insert:
  for +vc: String
  for +k: String
  for +v: String
  for +m: +List<M.KV>
  for +hk: {meta.goodx(vc, k) == True{} : Bool}
  for +hm: {meta.goodx_all(vc, m) == True{} : Bool}
  {meta.goodx_all(vc, M.Meta.insert(k, v, m)) == True{} : Bool}

def meta.goodx_insert(vc, k, v, m, hk, hm):
  match m:
    case Nil{}:
      meta.and_i(meta.goodx(vc, k), True{}, hk, {==})
    case Con{M.KV{+kk, +vv}, +r}:
      meta.goodx_insert_go(String.order(k, kk), vc, kk, vv, k, v, r, hk, hm,
        meta.goodx_insert(vc, k, v, r, hk, meta.and_r(meta.goodx(vc, kk), meta.goodx_all(vc, r), hm)))

law meta.gk_unpre:
  for +vc: String
  for +k: String
  for +hk: {String.starts_with(k, meta.VP()) == False{} : Bool}
  {meta.gk(vc, k) == True{} : Bool}

def meta.gk_unpre(vc, k, hk):
  %Equal.sym(Bool, String.starts_with(k, meta.VP()), False{}, hk) : {Bool.or(Bool.not(_), String.eq(meta.CR(vc), k)) == True{} : Bool}
  {==}

law meta.gk_hl:
  for c: Cmp
  for +vc: String
  for +k: String
  for +ec: {String.order(k, "release") == c : Cmp}
  for +hk: {String.starts_with(k, meta.VP()) == False{} : Bool}
  {meta.gk(vc, M.Meta.host_label.t(M.Meta.tkeys(vc), k)) == True{} : Bool}

def meta.gk_hl(c, vc, k, ec, hk):
  match c:
    case EQ{}:
      %Equal.sym(String, M.Meta.host_label.t(M.Meta.tkeys(vc), k), meta.CR(vc), meta.hl_unpre_eq(vc, k, hk, ec)) : {meta.gk(vc, _) == True{} : Bool}
      meta.or_r(Bool.not(String.starts_with(meta.CR(vc), meta.VP())), String.eq(meta.CR(vc), meta.CR(vc)), meta.eq_refl(meta.CR(vc)))
    case LT{}:
      %Equal.sym(String, M.Meta.host_label.t(M.Meta.tkeys(vc), k), k, meta.hl_unpre_ne(vc, k, hk, meta.lt_not_eq(String.order(k, "release"), ec))) : {meta.gk(vc, _) == True{} : Bool}
      meta.gk_unpre(vc, k, hk)
    case GT{}:
      %Equal.sym(String, M.Meta.host_label.t(M.Meta.tkeys(vc), k), k, meta.hl_unpre_ne(vc, k, hk, meta.gt_not_eq(String.order(k, "release"), ec))) : {meta.gk(vc, _) == True{} : Bool}
      meta.gk_unpre(vc, k, hk)

law meta.goodx_nl:
  for +vc: String
  for +m: +List<M.KV>
  for +hm: {M.Meta.no_vc_keys(m) == True{} : Bool}
  {meta.goodx_all(vc, meta.NL(vc, m)) == True{} : Bool}

def meta.goodx_nl(vc, m, hm):
  match m:
    case Nil{}:
      {==}
    case Con{M.KV{+k, +v}, +r}:
      +hk = meta.nvk_head(k, v, r, hm)
      %Equal.sym(+List<M.KV>, M.Meta.host_keys(M.Meta.tkeys(vc), M.KV{k, v} <> r), M.Meta.insert(M.Meta.host_label.t(M.Meta.tkeys(vc), k), v, M.Meta.host_keys(M.Meta.tkeys(vc), r)), meta.hk_cons(vc, k, v, r, hk)) :
        {meta.goodx_all(vc, _) == True{} : Bool}
      meta.goodx_insert(vc, M.Meta.host_label.t(M.Meta.tkeys(vc), k), v, M.Meta.host_keys(M.Meta.tkeys(vc), r),
        meta.or_r(M.Meta.excluded(M.Meta.host_label.t(M.Meta.tkeys(vc), k), meta.XS(), meta.PS()), meta.gk(vc, M.Meta.host_label.t(M.Meta.tkeys(vc), k)),
          meta.gk_hl(String.order(k, "release"), vc, k, {==}, hk)),
        meta.goodx_nl(vc, r, meta.nvk_tail(k, v, r, hm)))

law meta.goodx_nl2:
  for b: Bool
  for +vc: String
  for +target: String
  for +ns: String
  for +nl: +List<M.KV>
  for +h: {meta.goodx_all(vc, nl) == True{} : Bool}
  {meta.goodx_all(vc, M.Meta.add_marker.if(b, vc, target, ns, nl)) == True{} : Bool}

def meta.goodx_nl2(b, vc, target, ns, nl, h):
  match b:
    case True{}:
      meta.goodx_insert(vc, M.Meta.marker_label(), N.Names.marker_cluster(target, vc), nl, {==}, h)
    case False{}:
      meta.goodx_insert(vc, M.Meta.namespace_label(), ns, M.Meta.insert(M.Meta.marker_label(), vc, nl), {==},
        meta.goodx_insert(vc, M.Meta.marker_label(), vc, nl, {==}, h))

law meta.good_keep_go:
  for b: Bool
  for +vc: String
  for +kk: String
  for +v: String
  for +rec: +List<M.KV>
  for +eb: {M.Meta.excluded(kk, meta.XS(), meta.PS()) == b : Bool}
  for +hx: {meta.goodx(vc, kk) == True{} : Bool}
  for +ih: {meta.good_all(vc, rec) == True{} : Bool}
  {meta.good_all(vc, M.Meta.keep.if(b, M.KV{kk, v}, rec)) == True{} : Bool}

def meta.good_keep_go(b, vc, kk, v, rec, eb, hx, ih):
  match b:
    case True{}:
      ih
    case False{}:
      meta.and_i(meta.gk(vc, kk), meta.good_all(vc, rec), (%eb : {Bool.or(_, meta.gk(vc, kk)) == True{} : Bool}; hx), ih)

law meta.good_keep:
  for +vc: String
  for +m: +List<M.KV>
  for +h: {meta.goodx_all(vc, m) == True{} : Bool}
  {meta.good_all(vc, M.Meta.keep_out(m, meta.XS(), meta.PS())) == True{} : Bool}

def meta.good_keep(vc, m, h):
  match m:
    case Nil{}:
      {==}
    case Con{M.KV{+kk, +v}, +r}:
      meta.good_keep_go(M.Meta.excluded(kk, meta.XS(), meta.PS()), vc, kk, v, M.Meta.keep_out(r, meta.XS(), meta.PS()), {==},
        meta.and_l(meta.goodx(vc, kk), meta.goodx_all(vc, r), h),
        meta.good_keep(vc, r, meta.and_r(meta.goodx(vc, kk), meta.goodx_all(vc, r), h)))

law meta.good_union:
  for +vc: String
  for +a: +List<M.KV>
  for +b: +List<M.KV>
  for +ha: {meta.good_all(vc, a) == True{} : Bool}
  for +hb: {meta.good_all(vc, b) == True{} : Bool}
  {meta.good_all(vc, M.Meta.union(a, b)) == True{} : Bool}

def meta.good_union(vc, a, b, ha, hb):
  match a:
    case Nil{}:
      hb
    case Con{M.KV{+k, +v}, +r}:
      meta.good_insert(vc, k, v, M.Meta.union(r, b), meta.and_l(meta.gk(vc, k), meta.good_all(vc, r), ha),
        meta.good_union(vc, r, b, meta.and_r(meta.gk(vc, k), meta.good_all(vc, r), ha), hb))

law meta.good_rr:
  for +vc: String
  for +target: String
  for +ns: String
  for +m: +List<M.KV>
  for +hm: {M.Meta.no_vc_keys(m) == True{} : Bool}
  {meta.good_all(vc, meta.RR(vc, target, ns, m)) == True{} : Bool}

def meta.good_rr(vc, target, ns, m, hm):
  meta.good_union(vc, M.Meta.keep_out(meta.NL2(vc, target, ns, m), meta.XS(), meta.PS()), [],
    meta.good_keep(vc, meta.NL2(vc, target, ns, m), meta.goodx_nl2(String.is_empty(ns), vc, target, ns, meta.NL(vc, m), meta.goodx_nl(vc, m, hm))),
    {==})

# The round trip.

law meta.nvk_none:
  for +q: String
  for +m: +List<M.KV>
  for +hm: {M.Meta.no_vc_keys(m) == True{} : Bool}
  for +hq: {String.starts_with(q, meta.VP()) == True{} : Bool}
  {M.Meta.get(q, m) == None{} : Maybe<&2, String>}

def meta.nvk_none(q, m, hm, hq):
  match m:
    case Nil{}:
      {==}
    case Con{M.KV{+k, +v}, +r}:
      Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.KV{k, v} <> r), M.Meta.get(q, r), None{},
        meta.get_if_ne(String.order(q, k), v, M.Meta.get(q, r), meta.eq_pre_false_r(q, k, meta.nvk_head(k, v, r, hm), hq)),
        meta.nvk_none(q, r, meta.nvk_tail(k, v, r, hm), hq))

law meta.restrict_nil:
  for +r: +List<M.KV>
  {M.Meta.restrict(r, []) == [] : +List<M.KV>}

def meta.restrict_nil(r):
  match r:
    case Nil{}:
      {==}
    case Con{M.KV{+k, +val}, +rest}:
      meta.restrict_nil(rest)

law meta.rt_b_un:
  for b: Bool
  for +vc: String
  for +target: String
  for +ns: String
  for +m: +List<M.KV>
  for +q: String
  for +eb: {String.eq(q, "release") == b : Bool}
  for +hq: {String.starts_with(q, meta.VP()) == False{} : Bool}
  for +hm: {M.Meta.no_vc_keys(m) == True{} : Bool}
  {M.Meta.get(q, M.Meta.back(M.Meta.tkeys(vc), meta.RR(vc, target, ns, m))) == M.Meta.get(q, m) : Maybe<&2, String>}

def meta.rt_b_un(b, vc, target, ns, m, q, eb, hq, hm):
  match b:
    case True{}:
      %Equal.sym(String, q, "release", meta.str_eq(q, "release", meta.is_eq_true(String.order(q, "release"), eb))) :
        {M.Meta.get(_, M.Meta.back(M.Meta.tkeys(vc), meta.RR(vc, target, ns, m))) == M.Meta.get(_, m) : Maybe<&2, String>}
      Equal.trans(Maybe<&2, String>, M.Meta.get("release", M.Meta.back(M.Meta.tkeys(vc), meta.RR(vc, target, ns, m))), M.Meta.get(meta.CR(vc), meta.RR(vc, target, ns, m)), M.Meta.get("release", m),
        meta.back_rel(vc, meta.RR(vc, target, ns, m)),
        Equal.trans(Maybe<&2, String>, M.Meta.get(meta.CR(vc), meta.RR(vc, target, ns, m)), M.Meta.get(meta.CR(vc), meta.NL(vc, m)), M.Meta.get("release", m),
          meta.rr_get(vc, target, ns, m, meta.CR(vc), meta.excl_cr(vc)), meta.hk_rel(vc, m, hm)))
    case False{}:
      Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.back(M.Meta.tkeys(vc), meta.RR(vc, target, ns, m))), M.Meta.get(q, meta.RR(vc, target, ns, m)), M.Meta.get(q, m),
        meta.back_n(vc, q, meta.RR(vc, target, ns, m), hq, eb),
        Equal.trans(Maybe<&2, String>, M.Meta.get(q, meta.RR(vc, target, ns, m)), M.Meta.get(q, meta.NL(vc, m)), M.Meta.get(q, m),
          meta.rr_get(vc, target, ns, m, q, meta.excl_unpre(q, hq)), meta.hk_n(vc, q, m, hq, eb, hm)))

law meta.rt_b_go:
  for pq: Bool
  for +vc: String
  for +target: String
  for +ns: String
  for +m: +List<M.KV>
  for +q: String
  for +epq: {String.starts_with(q, meta.VP()) == pq : Bool}
  for +hm: {M.Meta.no_vc_keys(m) == True{} : Bool}
  {M.Meta.get(q, M.Meta.back(M.Meta.tkeys(vc), meta.RR(vc, target, ns, m))) == M.Meta.get(q, m) : Maybe<&2, String>}

def meta.rt_b_go(pq, vc, target, ns, m, q, epq, hm):
  match pq:
    case True{}:
      Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.back(M.Meta.tkeys(vc), meta.RR(vc, target, ns, m))), None{}, M.Meta.get(q, m),
        meta.back_vc(vc, q, meta.RR(vc, target, ns, m), epq, meta.good_rr(vc, target, ns, m, hm)),
        Equal.sym(Maybe<&2, String>, M.Meta.get(q, m), None{}, meta.nvk_none(q, m, hm, epq)))
    case False{}:
      meta.rt_b_un(String.eq(q, "release"), vc, target, ns, m, q, {==}, epq, hm)

# Translating R's keys back gives m's values everywhere.
law meta.rt_b:
  for +vc: String
  for +target: String
  for +ns: String
  for +m: +List<M.KV>
  for +q: String
  for +hm: {M.Meta.no_vc_keys(m) == True{} : Bool}
  {M.Meta.get(q, M.Meta.from_list(M.Meta.back(M.Meta.tkeys(vc), meta.RR(vc, target, ns, m)))) == M.Meta.get(q, m) : Maybe<&2, String>}

def meta.rt_b(vc, target, ns, m, q, hm):
  Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.from_list(M.Meta.back(M.Meta.tkeys(vc), meta.RR(vc, target, ns, m)))), M.Meta.get(q, M.Meta.back(M.Meta.tkeys(vc), meta.RR(vc, target, ns, m))), M.Meta.get(q, m),
    meta.get_from_list(q, M.Meta.back(M.Meta.tkeys(vc), meta.RR(vc, target, ns, m))),
    meta.rt_b_go(String.starts_with(q, meta.VP()), vc, target, ns, m, q, {==}, hm))

def meta.BB(+vc: String, target: String, +ns: String, m: +List<M.KV>) -> +List<M.KV>:
  M.Meta.from_list(M.Meta.back(M.Meta.tkeys(vc), meta.RR(vc, target, ns, m)))

def meta.LHS0(+vc: String, +target: String, +ns: String, +m: +List<M.KV>) -> +List<M.KV>:
  M.Meta.union(meta.BB(vc, target, ns, m), M.Meta.restrict(meta.RR(vc, target, ns, m), []))

law meta.rt_pw:
  for +vc: String
  for +target: String
  for +ns: String
  for +m: +List<M.KV>
  for +q: String
  for +hm: {M.Meta.no_vc_keys(m) == True{} : Bool}
  {M.Meta.get(q, meta.LHS0(vc, target, ns, m)) == M.Meta.get(q, m) : Maybe<&2, String>}

def meta.rt_pw(vc, target, ns, m, q, hm):
  %Equal.sym(+List<M.KV>, M.Meta.restrict(meta.RR(vc, target, ns, m), []), [], meta.restrict_nil(meta.RR(vc, target, ns, m))) :
    {M.Meta.get(q, M.Meta.union(meta.BB(vc, target, ns, m), _)) == M.Meta.get(q, m) : Maybe<&2, String>}
  Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.Meta.union(meta.BB(vc, target, ns, m), [])), Maybe.or(&2, String, M.Meta.get(q, meta.BB(vc, target, ns, m)), None{}), M.Meta.get(q, m),
    meta.get_union(q, meta.BB(vc, target, ns, m), []),
    Equal.trans(Maybe<&2, String>, Maybe.or(&2, String, M.Meta.get(q, meta.BB(vc, target, ns, m)), None{}), M.Meta.get(q, meta.BB(vc, target, ns, m)), M.Meta.get(q, m),
      meta.or_none(M.Meta.get(q, meta.BB(vc, target, ns, m))), meta.rt_b(vc, target, ns, m, q, hm)))

law meta.rt_agree:
  for +ks: +List<String>
  for +vc: String
  for +target: String
  for +ns: String
  for +m: +List<M.KV>
  for +hm: {M.Meta.no_vc_keys(m) == True{} : Bool}
  {M.Meta.agree_on(ks, meta.LHS0(vc, target, ns, m), m) == True{} : Bool}

def meta.rt_agree(ks, vc, target, ns, m, hm):
  match ks:
    case Nil{}:
      {==}
    case Con{+q, +rest}:
      meta.and_i(M.Meta.opt_eq(M.Meta.get(q, meta.LHS0(vc, target, ns, m)), M.Meta.get(q, m)), M.Meta.agree_on(rest, meta.LHS0(vc, target, ns, m), m),
        meta.opt_eq_of(M.Meta.get(q, meta.LHS0(vc, target, ns, m)), M.Meta.get(q, m), meta.rt_pw(vc, target, ns, m, q, hm)),
        meta.rt_agree(rest, vc, target, ns, m, hm))

def L.meta.labels_round_trip(vc, target, ns, m, hc, hk):
  +lhs = meta.LHS0(vc, target, ns, m)
  +canon_l = L.meta.union_canon(meta.BB(vc, target, ns, m), M.Meta.restrict(meta.RR(vc, target, ns, m), []),
    (%Equal.sym(+List<M.KV>, M.Meta.restrict(meta.RR(vc, target, ns, m), []), [], meta.restrict_nil(meta.RR(vc, target, ns, m))) : {M.Meta.canon(_) == True{} : Bool}; {==}))
  Equal.cong(+List<M.KV>, Maybe<&2, List<&2, M.KV>>, x => Some{x}, lhs, m,
    L.meta.ext(lhs, m, canon_l, hc,
      meta.and_i(M.Meta.agree_on(M.Meta.keys(lhs), lhs, m), M.Meta.agree_on(M.Meta.keys(m), lhs, m),
        meta.rt_agree(M.Meta.keys(lhs), vc, target, ns, m, hk), meta.rt_agree(M.Meta.keys(m), vc, target, ns, m, hk))))

# The round trip when the virtual object already has the labels.

law meta.keep_in_go:
  for b: Bool
  for +k: String
  for +v: String
  for +rec: +List<M.KV>
  for +eb: {M.Meta.excluded(k, meta.XS(), meta.PS()) == b : Bool}
  for +hk: {String.starts_with(k, meta.VP()) == False{} : Bool}
  for +ih: {rec == [] : +List<M.KV>}
  {M.Meta.keep.if(Bool.not(b), M.KV{k, v}, rec) == [] : +List<M.KV>}

def meta.keep_in_go(b, k, v, rec, eb, hk, ih):
  match b:
    case False{}:
      ih
    case True{}:
      meta.tf_absurd({M.Meta.keep.if(False{}, M.KV{k, v}, rec) == [] : +List<M.KV>},
        Equal.trans(Bool, True{}, M.Meta.excluded(k, meta.XS(), meta.PS()), False{}, Equal.sym(Bool, M.Meta.excluded(k, meta.XS(), meta.PS()), True{}, eb), meta.excl_unpre(k, hk)))

law meta.keep_in_nvk:
  for +m: +List<M.KV>
  for +hm: {M.Meta.no_vc_keys(m) == True{} : Bool}
  {M.Meta.keep_in(m, meta.XS(), meta.PS()) == [] : +List<M.KV>}

def meta.keep_in_nvk(m, hm):
  match m:
    case Nil{}:
      {==}
    case Con{M.KV{+k, +v}, +r}:
      meta.keep_in_go(M.Meta.excluded(k, meta.XS(), meta.PS()), k, v, M.Meta.keep_in(r, meta.XS(), meta.PS()), {==}, meta.nvk_head(k, v, r, hm), meta.keep_in_nvk(r, meta.nvk_tail(k, v, r, hm)))

law meta.above_restrict_if:
  for mv: Maybe<&2, String>
  for +x: String
  for +k: String
  for +rec: +List<M.KV>
  for +hk: {Cmp.is_lt(String.order(x, k)) == True{} : Bool}
  for +hr: {M.Meta.above(x, rec) == True{} : Bool}
  {M.Meta.above(x, M.Meta.restrict.if(mv, k, rec)) == True{} : Bool}

def meta.above_restrict_if(mv, x, k, rec, hk, hr):
  match mv:
    case None{}:
      hr
    case Some{y}:
      meta.and_i(Cmp.is_lt(String.order(x, k)), M.Meta.above(x, rec), hk, hr)

law meta.above_restrict:
  for +x: String
  for +r: +List<M.KV>
  for +v: +List<M.KV>
  for +h: {M.Meta.above(x, r) == True{} : Bool}
  {M.Meta.above(x, M.Meta.restrict(r, v)) == True{} : Bool}

def meta.above_restrict(x, r, v, h):
  match r:
    case Nil{}:
      {==}
    case Con{M.KV{+k, +val}, +rest}:
      meta.above_restrict_if(M.Meta.get(k, v), x, k, M.Meta.restrict(rest, v),
        meta.and_l(Cmp.is_lt(String.order(x, k)), M.Meta.above(x, rest), h),
        meta.above_restrict(x, rest, v, meta.and_r(Cmp.is_lt(String.order(x, k)), M.Meta.above(x, rest), h)))

law meta.canon_restrict_if:
  for mv: Maybe<&2, String>
  for +k: String
  for +rec: +List<M.KV>
  for +ha: {M.Meta.above(k, rec) == True{} : Bool}
  for +hc: {M.Meta.canon(rec) == True{} : Bool}
  {M.Meta.canon(M.Meta.restrict.if(mv, k, rec)) == True{} : Bool}

def meta.canon_restrict_if(mv, k, rec, ha, hc):
  match mv:
    case None{}:
      hc
    case Some{y}:
      meta.and_i(M.Meta.above(k, rec), M.Meta.canon(rec), ha, hc)

law meta.restrict_canon:
  for +r: +List<M.KV>
  for +v: +List<M.KV>
  for +h: {M.Meta.canon(r) == True{} : Bool}
  {M.Meta.canon(M.Meta.restrict(r, v)) == True{} : Bool}

def meta.restrict_canon(r, v, h):
  match r:
    case Nil{}:
      {==}
    case Con{M.KV{+k, +val}, +rest}:
      meta.canon_restrict_if(M.Meta.get(k, v), k, M.Meta.restrict(rest, v),
        meta.above_restrict(k, rest, v, meta.and_l(M.Meta.above(k, rest), M.Meta.canon(rest), h)),
        meta.restrict_canon(rest, v, meta.and_r(M.Meta.above(k, rest), M.Meta.canon(rest), h)))

def meta.rv(b: Bool, x: Maybe<&2, String>) -> Maybe<&2, String>:
  match b:
    case True{}:
      x
    case False{}:
      None{}

law meta.rv_none:
  for b: Bool
  {meta.rv(b, None{}) == None{} : Maybe<&2, String>}

def meta.rv_none(b):
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

law meta.or_rv:
  for x: Maybe<&2, String>
  for b: Bool
  {Maybe.or(&2, String, x, meta.rv(b, x)) == x : Maybe<&2, String>}

def meta.or_rv(x, b):
  match x:
    case None{}:
      meta.rv_none(b)
    case Some{y}:
      {==}

law meta.get_move_none:
  for +q: String
  for +k: String
  for +v: +List<M.KV>
  for +ec: {String.order(q, k) == EQ{} : Cmp}
  for +e: {M.Meta.get(k, v) == None{} : Maybe<&2, String>}
  {M.Meta.get(q, v) == None{} : Maybe<&2, String>}

def meta.get_move_none(q, k, v, ec, e):
  %Equal.sym(String, q, k, meta.str_eq(q, k, ec)) : {M.Meta.get(_, v) == None{} : Maybe<&2, String>}
  e

law meta.get_restrict_go:
  for c: Cmp
  for mv: Maybe<&2, String>
  for +q: String
  for +k: String
  for +val: String
  for +rest: +List<M.KV>
  for +rec: +List<M.KV>
  for +v: +List<M.KV>
  for +ec: {String.order(q, k) == c : Cmp}
  for +emv: {M.Meta.get(k, v) == mv : Maybe<&2, String>}
  for +ih: {M.Meta.get(q, rec) == meta.rv(Maybe.is_some(&2, String, M.Meta.get(q, rest)), M.Meta.get(q, v)) : Maybe<&2, String>}
  {M.Meta.get(q, M.Meta.restrict.if(mv, k, rec)) == meta.rv(Maybe.is_some(&2, String, M.Meta.get.if(c, val, M.Meta.get(q, rest))), M.Meta.get(q, v)) : Maybe<&2, String>}

def meta.get_restrict_go(c, mv, q, k, val, rest, rec, v, ec, emv, ih):
  match c:
    case EQ{}:
      match mv:
        case None{}:
          +gqv = meta.get_move_none(q, k, v, ec, emv)
          +b = Maybe.is_some(&2, String, M.Meta.get(q, rest))
          Equal.trans(Maybe<&2, String>, M.Meta.get(q, rec), meta.rv(b, M.Meta.get(q, v)), M.Meta.get(q, v), ih,
            Equal.trans(Maybe<&2, String>, meta.rv(b, M.Meta.get(q, v)), None{}, M.Meta.get(q, v),
              (%Equal.sym(Maybe<&2, String>, M.Meta.get(q, v), None{}, gqv) : {meta.rv(b, _) == None{} : Maybe<&2, String>}; meta.rv_none(b)),
              Equal.sym(Maybe<&2, String>, M.Meta.get(q, v), None{}, gqv)))
        case Some{+y}:
          %Equal.sym(Cmp, String.order(q, k), EQ{}, ec) : {M.Meta.get.if(_, y, M.Meta.get(q, rec)) == M.Meta.get(q, v) : Maybe<&2, String>}
          %Equal.sym(String, q, k, meta.str_eq(q, k, ec)) : {Some{y} == M.Meta.get(_, v) : Maybe<&2, String>}
          Equal.sym(Maybe<&2, String>, M.Meta.get(k, v), Some{y}, emv)
    case LT{}:
      match mv:
        case None{}:
          ih
        case Some{+y}:
          Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.KV{k, y} <> rec), M.Meta.get(q, rec), meta.rv(Maybe.is_some(&2, String, M.Meta.get(q, rest)), M.Meta.get(q, v)),
            meta.get_if_ne(String.order(q, k), y, M.Meta.get(q, rec), meta.lt_not_eq(String.order(q, k), ec)), ih)
    case GT{}:
      match mv:
        case None{}:
          ih
        case Some{+y}:
          Equal.trans(Maybe<&2, String>, M.Meta.get(q, M.KV{k, y} <> rec), M.Meta.get(q, rec), meta.rv(Maybe.is_some(&2, String, M.Meta.get(q, rest)), M.Meta.get(q, v)),
            meta.get_if_ne(String.order(q, k), y, M.Meta.get(q, rec), meta.gt_not_eq(String.order(q, k), ec)), ih)

law meta.get_restrict:
  for +q: String
  for +r: +List<M.KV>
  for +v: +List<M.KV>
  {M.Meta.get(q, M.Meta.restrict(r, v)) == meta.rv(Maybe.is_some(&2, String, M.Meta.get(q, r)), M.Meta.get(q, v)) : Maybe<&2, String>}

def meta.get_restrict(q, r, v):
  match r:
    case Nil{}:
      {==}
    case Con{M.KV{+k, +val}, +rest}:
      meta.get_restrict_go(String.order(q, k), M.Meta.get(k, v), q, k, val, rest, M.Meta.restrict(rest, v), v, {==}, {==}, meta.get_restrict(q, rest, v))

def meta.LHS1(+vc: String, +target: String, +ns: String, +m: +List<M.KV>, +ki: +List<M.KV>) -> +List<M.KV>:
  M.Meta.union(M.Meta.from_list(M.Meta.back(M.Meta.tkeys(vc), M.Meta.union(M.Meta.keep_out(meta.NL2(vc, target, ns, m), meta.XS(), meta.PS()), ki))),
    M.Meta.restrict(M.Meta.union(M.Meta.keep_out(meta.NL2(vc, target, ns, m), meta.XS(), meta.PS()), ki), m))

def meta.LHS2(+vc: String, +target: String, +ns: String, +m: +List<M.KV>) -> +List<M.KV>:
  M.Meta.union(meta.BB(vc, target, ns, m), M.Meta.restrict(meta.RR(vc, target, ns, m), m))

law meta.rt2_pw:
  for +vc: String
  for +target: String
  for +ns: String
  for +m: +List<M.KV>
  for +q: String
  for +hm: {M.Meta.no_vc_keys(m) == True{} : Bool}
  {M.Meta.get(q, meta.LHS2(vc, target, ns, m)) == M.Meta.get(q, m) : Maybe<&2, String>}

def meta.rt2_pw(vc, target, ns, m, q, hm):
  +b = Maybe.is_some(&2, String, M.Meta.get(q, meta.RR(vc, target, ns, m)))
  Equal.trans(Maybe<&2, String>, M.Meta.get(q, meta.LHS2(vc, target, ns, m)), Maybe.or(&2, String, M.Meta.get(q, meta.BB(vc, target, ns, m)), M.Meta.get(q, M.Meta.restrict(meta.RR(vc, target, ns, m), m))), M.Meta.get(q, m),
    meta.get_union(q, meta.BB(vc, target, ns, m), M.Meta.restrict(meta.RR(vc, target, ns, m), m)),
    (%Equal.sym(Maybe<&2, String>, M.Meta.get(q, meta.BB(vc, target, ns, m)), M.Meta.get(q, m), meta.rt_b(vc, target, ns, m, q, hm)) :
       {Maybe.or(&2, String, _, M.Meta.get(q, M.Meta.restrict(meta.RR(vc, target, ns, m), m))) == M.Meta.get(q, m) : Maybe<&2, String>}
     %Equal.sym(Maybe<&2, String>, M.Meta.get(q, M.Meta.restrict(meta.RR(vc, target, ns, m), m)), meta.rv(b, M.Meta.get(q, m)), meta.get_restrict(q, meta.RR(vc, target, ns, m), m)) :
       {Maybe.or(&2, String, M.Meta.get(q, m), _) == M.Meta.get(q, m) : Maybe<&2, String>}
     meta.or_rv(M.Meta.get(q, m), b)))

law meta.rt2_agree:
  for +ks: +List<String>
  for +vc: String
  for +target: String
  for +ns: String
  for +m: +List<M.KV>
  for +hm: {M.Meta.no_vc_keys(m) == True{} : Bool}
  {M.Meta.agree_on(ks, meta.LHS2(vc, target, ns, m), m) == True{} : Bool}

def meta.rt2_agree(ks, vc, target, ns, m, hm):
  match ks:
    case Nil{}:
      {==}
    case Con{+q, +rest}:
      meta.and_i(M.Meta.opt_eq(M.Meta.get(q, meta.LHS2(vc, target, ns, m)), M.Meta.get(q, m)), M.Meta.agree_on(rest, meta.LHS2(vc, target, ns, m), m),
        meta.opt_eq_of(M.Meta.get(q, meta.LHS2(vc, target, ns, m)), M.Meta.get(q, m), meta.rt2_pw(vc, target, ns, m, q, hm)),
        meta.rt2_agree(rest, vc, target, ns, m, hm))

def L.meta.labels_round_trip_sync(vc, target, ns, m, hc, hk):
  +lhs = meta.LHS2(vc, target, ns, m)
  +canon_r = L.meta.union_canon(M.Meta.keep_out(meta.NL2(vc, target, ns, m), meta.XS(), meta.PS()), [], {==})
  +canon_l = L.meta.union_canon(meta.BB(vc, target, ns, m), M.Meta.restrict(meta.RR(vc, target, ns, m), m), meta.restrict_canon(meta.RR(vc, target, ns, m), m, canon_r))
  %Equal.sym(+List<M.KV>, M.Meta.keep_in(m, meta.XS(), meta.PS()), [], meta.keep_in_nvk(m, hk)) :
    {Some{meta.LHS1(vc, target, ns, m, _)} == Some{m} : Maybe<&2, List<&2, M.KV>>}
  Equal.cong(+List<M.KV>, Maybe<&2, List<&2, M.KV>>, x => Some{x}, lhs, m,
    L.meta.ext(lhs, m, canon_l, hc,
      meta.and_i(M.Meta.agree_on(M.Meta.keys(lhs), lhs, m), M.Meta.agree_on(M.Meta.keys(m), lhs, m),
        meta.rt2_agree(M.Meta.keys(lhs), vc, target, ns, m, hk), meta.rt2_agree(M.Meta.keys(m), vc, target, ns, m, hk))))
