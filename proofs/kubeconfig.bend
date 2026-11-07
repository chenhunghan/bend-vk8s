import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../laws/kubeconfig.bend as L
import ../src/cli/kubeconfig.bend as K

# Proofs of laws/kubeconfig.bend: `def L.<law>` for each law. Helper lemmas
# are stated {simple == computed}, so that % puts the simple form in place.

# String equality is reflexive
# ----------------------------

law Kp.bool_refl:
  for b: Bool
  {EQ{} == Bool.cmp(b, b) : Cmp}

def Kp.bool_refl(b):
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

law Kp.word_refl:
  for n: Nat
  for w: Word(n)
  {EQ{} == Word.cmp(n, w, w) : Cmp}

def Kp.word_refl(n, w):
  match n:
    case 0n:
      {==}
    case 1n+p:
      match w:
        case WCon{wb, wt}:
          %Kp.word_refl(p, wt) : {EQ{} == Word.cmp.fin(wb, wb, _) : Cmp}
          Kp.bool_refl(wb)

law Kp.u32_refl:
  for x: U32
  {EQ{} == U32.cmp(x, x) : Cmp}

def Kp.u32_refl(x):
  match x:
    case U32{w}:
      Kp.word_refl(32n, w)

law Kp.order_refl:
  for s: String
  {EQ{} == String.order.go(s, s, EQ{}) : Cmp}

def Kp.order_refl(s):
  match s:
    case SNil{}:
      {==}
    case SCon{Chr{x}, t}:
      %Kp.u32_refl(x) : {EQ{} == String.order.go(t, t, _) : Cmp}
      Kp.order_refl(t)

law Kp.eq_refl:
  for s: String
  {True{} == String.eq(s, s) : Bool}

def Kp.eq_refl(s):
  %Kp.order_refl(s) : {True{} == Cmp.is_eq(_) : Bool}
  {==}

# Booleans
# --------

def Kp.disc(b: Bool) -> Type:
  match b:
    case True{}:
      Empty
    case False{}:
      Unit

law Kp.false_ne_true:
  for h: {False{} == True{} : Bool}
  Empty

def Kp.false_ne_true(h):
  %h : Kp.disc(_)
  Unit{}

law Kp.ex_falso:
  for c: Bool
  for e: Empty
  {False{} == c : Bool}

def Kp.ex_falso(c, e):
  match e:

law Kp.or_l:
  for a: Bool
  for b: Bool
  for h: {False{} == Bool.or(a, b) : Bool}
  {False{} == a : Bool}

def Kp.or_l(a, b, h):
  match a:
    case True{}:
      Kp.ex_falso(True{}, Kp.false_ne_true(h))
    case False{}:
      {==}

law Kp.or_r:
  for a: Bool
  for b: Bool
  for h: {False{} == Bool.or(a, b) : Bool}
  {False{} == b : Bool}

def Kp.or_r(a, b, h):
  match a:
    case True{}:
      Kp.ex_falso(b, Kp.false_ne_true(h))
    case False{}:
      h

law Kp.or_true:
  for a: Bool
  {True{} == Bool.or(a, True{}) : Bool}

def Kp.or_true(a):
  match a:
    case True{}:
      {==}
    case False{}:
      {==}

# Entry lists
# -----------

law Kp.has_snoc:
  for +xs: List<&2, K.Ent>
  for +n: String
  for +b: J.Json
  {True{} == K.Kubeconfig.has(List.append(&2, K.Ent, xs, [K.Ent{n, b}]), n) : Bool}

def Kp.has_snoc(xs, n, b):
  match xs:
    case Nil{}:
      %Kp.eq_refl(n) : {True{} == Bool.or(_, False{}) : Bool}
      {==}
    case Con{K.Ent{k, c}, t}:
      %Kp.has_snoc(t, n, b) : {True{} == Bool.or(String.eq(k, n), _) : Bool}
      Kp.or_true(String.eq(k, n))

law Kp.del_snoc:
  for +xs: List<&2, K.Ent>
  for +n: String
  for +b: J.Json
  {K.Kubeconfig.del(xs, n) == K.Kubeconfig.del(List.append(&2, K.Ent, xs, [K.Ent{n, b}]), n) : List<&2, K.Ent>}

def Kp.del_snoc(xs, n, b):
  match xs:
    case Nil{}:
      %Kp.eq_refl(n) : {Nil{} == K.Kubeconfig.del.if(n, b, Nil{}, _) : List<&2, K.Ent>}
      {==}
    case Con{K.Ent{k, c}, t}:
      %Kp.del_snoc(t, n, b) : {K.Kubeconfig.del.if(k, c, K.Kubeconfig.del(t, n), String.eq(k, n))
        == K.Kubeconfig.del.if(k, c, _, String.eq(k, n)) : List<&2, K.Ent>}
      {==}

law Kp.del_absent:
  for +xs: List<&2, K.Ent>
  for +n: String
  for h: {False{} == K.Kubeconfig.has(xs, n) : Bool}
  {xs == K.Kubeconfig.del(xs, n) : List<&2, K.Ent>}

def Kp.del_absent(xs, n, h):
  match xs:
    case Nil{}:
      {==}
    case Con{K.Ent{k, c}, t}:
      %Kp.or_l(String.eq(k, n), K.Kubeconfig.has(t, n), h) : {Con{K.Ent{k, c}, t}
        == K.Kubeconfig.del.if(k, c, K.Kubeconfig.del(t, n), _) : List<&2, K.Ent>}
      %Kp.del_absent(t, n, Kp.or_r(String.eq(k, n), K.Kubeconfig.has(t, n), h)) : {Con{K.Ent{k, c}, t}
        == Con{K.Ent{k, c}, _} : List<&2, K.Ent>}
      {==}

law Kp.del_put:
  for +xs: List<&2, K.Ent>
  for +n: String
  for +b: J.Json
  for h: {False{} == K.Kubeconfig.has(xs, n) : Bool}
  {xs == K.Kubeconfig.del(K.Kubeconfig.put(xs, n, b), n) : List<&2, K.Ent>}

def Kp.del_put(xs, n, b, h):
  %Kp.del_absent(xs, n, h) : {xs == K.Kubeconfig.del(List.append(&2, K.Ent, _, [K.Ent{n, b}]), n) : List<&2, K.Ent>}
  %Kp.del_snoc(xs, n, b) : {xs == _ : List<&2, K.Ent>}
  Kp.del_absent(xs, n, h)

law Kp.find_snoc:
  for +xs: List<&2, K.Ent>
  for +n: String
  for +b: J.Json
  for h: {False{} == K.Kubeconfig.has(xs, n) : Bool}
  {Some{b} == K.Kubeconfig.find(List.append(&2, K.Ent, xs, [K.Ent{n, b}]), n) : Maybe<&2, J.Json>}

def Kp.find_snoc(xs, n, b, h):
  match xs:
    case Nil{}:
      %Kp.eq_refl(n) : {Some{b} == K.Kubeconfig.find.if(b, None{}, _) : Maybe<&2, J.Json>}
      {==}
    case Con{K.Ent{k, c}, t}:
      %Kp.or_l(String.eq(k, n), K.Kubeconfig.has(t, n), h) : {Some{b}
        == K.Kubeconfig.find.if(c, K.Kubeconfig.find(List.append(&2, K.Ent, t, [K.Ent{n, b}]), n), _) : Maybe<&2, J.Json>}
      Kp.find_snoc(t, n, b, Kp.or_r(String.eq(k, n), K.Kubeconfig.has(t, n), h))

law Kp.find_put:
  for +xs: List<&2, K.Ent>
  for +n: String
  for +b: J.Json
  for h: {False{} == K.Kubeconfig.has(xs, n) : Bool}
  {Some{b} == K.Kubeconfig.find(K.Kubeconfig.put(xs, n, b), n) : Maybe<&2, J.Json>}

def Kp.find_put(xs, n, b, h):
  %Kp.del_absent(xs, n, h) : {Some{b} == K.Kubeconfig.find(List.append(&2, K.Ent, _, [K.Ent{n, b}]), n) : Maybe<&2, J.Json>}
  Kp.find_snoc(xs, n, b, h)

# Concrete laws
# -------------

def L.kubeconfig.exchange_specified():
  {==}

def L.kubeconfig.exchange_same_name():
  {==}

def L.kubeconfig.context_name():
  {==}

def L.kubeconfig.print_renames():
  {==}

def L.kubeconfig.merge_into_missing():
  {==}

def L.kubeconfig.merge_into_empty():
  {==}

def L.kubeconfig.merge_keeps_others():
  {==}

def L.kubeconfig.merge_current_untouched():
  {==}

def L.kubeconfig.merge_replaces_same_name():
  {==}

def L.kubeconfig.merge_needs_entries():
  {==}

def L.kubeconfig.target_default():
  {==}

def L.kubeconfig.target_first():
  {==}

def L.kubeconfig.remove_restores():
  {==}

def L.kubeconfig.remove_absent_unchanged():
  {==}

def L.kubeconfig.remove_last():
  {==}

def L.kubeconfig.remove_keeps_shared_user():
  {==}

# General laws
# ------------

def L.kubeconfig.merge_has_context(kc, n, cl, u, set):
  match kc:
    case K.Kc{cls, ctxs, us, cur, pr}:
      Equal.sym(Bool, True{}, K.Kubeconfig.has(K.Kubeconfig.put(ctxs, n, K.Kubeconfig.ctx_body(n)), n),
        Kp.has_snoc(K.Kubeconfig.del(ctxs, n), n, K.Kubeconfig.ctx_body(n)))

def L.kubeconfig.merge_sets_current(kc, n, cl, u):
  match kc:
    case K.Kc{cls, ctxs, us, cur, pr}:
      {==}

def L.kubeconfig.merge_keeps_current(kc, n, cl, u):
  match kc:
    case K.Kc{cls, ctxs, us, cur, pr}:
      {==}

def L.kubeconfig.merge_then_remove_fresh(cls, ctxs, us, cur, pr, n, cl, u, set, h1, h2, h3, h4, h5):
  %Kp.find_put(ctxs, n, K.Kubeconfig.ctx_body(n), Equal.sym(Bool, K.Kubeconfig.has(ctxs, n), False{}, h2)) : {K.Kubeconfig.entries(
    K.Kubeconfig.unset.go(_, K.Kubeconfig.put(cls, n, cl), K.Kubeconfig.put(ctxs, n, K.Kubeconfig.ctx_body(n)),
      K.Kubeconfig.put(us, n, u), K.Kubeconfig.cur_set(set, cur, n), pr, n)) == K.Ents{cls, ctxs, us} : K.Ents}
  %Kp.del_put(ctxs, n, K.Kubeconfig.ctx_body(n), Equal.sym(Bool, K.Kubeconfig.has(ctxs, n), False{}, h2)) : {K.Ents{
    K.Kubeconfig.keep_if(K.Kubeconfig.refs(_, "cluster", n), K.Kubeconfig.put(cls, n, cl), n), _,
    K.Kubeconfig.keep_if(K.Kubeconfig.refs(_, "user", n), K.Kubeconfig.put(us, n, u), n)} == K.Ents{cls, ctxs, us} : K.Ents}
  %Equal.sym(Bool, K.Kubeconfig.refs(ctxs, "cluster", n), False{}, h4) : {K.Ents{
    K.Kubeconfig.keep_if(_, K.Kubeconfig.put(cls, n, cl), n), ctxs,
    K.Kubeconfig.keep_if(K.Kubeconfig.refs(ctxs, "user", n), K.Kubeconfig.put(us, n, u), n)} == K.Ents{cls, ctxs, us} : K.Ents}
  %Equal.sym(Bool, K.Kubeconfig.refs(ctxs, "user", n), False{}, h5) : {K.Ents{
    K.Kubeconfig.del(K.Kubeconfig.put(cls, n, cl), n), ctxs,
    K.Kubeconfig.keep_if(_, K.Kubeconfig.put(us, n, u), n)} == K.Ents{cls, ctxs, us} : K.Ents}
  %Kp.del_put(cls, n, cl, Equal.sym(Bool, K.Kubeconfig.has(cls, n), False{}, h1)) : {K.Ents{
    _, ctxs, K.Kubeconfig.del(K.Kubeconfig.put(us, n, u), n)} == K.Ents{cls, ctxs, us} : K.Ents}
  %Kp.del_put(us, n, u, Equal.sym(Bool, K.Kubeconfig.has(us, n), False{}, h3)) : {K.Ents{
    cls, ctxs, _} == K.Ents{cls, ctxs, us} : K.Ents}
  {==}
