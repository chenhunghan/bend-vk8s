import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../laws/nodes.bend as L
import ../src/translate/meta.bend as M
import ../src/translate/services.bend as S
import ../src/translate/nodes.bend as ND

# Proofs of laws/nodes.bend: `def L.<law>` for each law.
#
# The concrete laws compute. The fake node law goes in two steps: whether a
# pod needs the node is membership in the pods' node names (by induction
# on the pod lists), and the step for a node creates it or keeps it exactly
# when it is needed. The event laws rewrite with the hypothesis that the
# kind is accepted; the written event's involved object is built with the
# virtual object's namespace and name first, so reading them back computes,
# up to String.eq(s, s) == True.

# Concrete laws: both sides compute.

def L.nodes.backwards_simple():
  {==}

def L.nodes.backwards_not_ready_1():
  {==}

def L.nodes.backwards_not_ready_2():
  {==}

def L.nodes.backwards_not_ready_3():
  {==}

def L.nodes.backwards_custom_taint_1():
  {==}

def L.nodes.backwards_custom_taint_2():
  {==}

def L.nodes.backwards_custom_taint_3():
  {==}

def L.nodes.create_backward():
  {==}

def L.nodes.create_backward_not_needed():
  {==}

def L.nodes.update_backward_no_change():
  {==}

def L.nodes.update_backward():
  {==}

def L.nodes.delete_backward():
  {==}

def L.nodes.label_matched():
  {==}

def L.nodes.label_not_matched():
  {==}

def L.nodes.clear_nodes():
  {==}

def L.nodes.dont_clear_nodes():
  {==}

def L.nodes.matching_taints():
  {==}

def L.nodes.not_matching_taints():
  {==}

def L.nodes.toleration_empty_key_exists():
  {==}

def L.nodes.rancher_annotations():
  {==}

def L.nodes.fake_create():
  {==}

def L.nodes.fake_delete():
  {==}

def L.nodes.event_create():
  {==}

def L.nodes.event_update():
  {==}

# String.order(a, a) == EQ (as in proofs/services.bend).

law nodes.bool_refl:
  for a: Bool
  {Bool.cmp(a, a) == EQ{} : Cmp}

def nodes.bool_refl(a):
  match a:
    case False{}:
      {==}
    case True{}:
      {==}

law nodes.word_refl:
  for +n: Nat
  for +a: Word(n)
  {Word.cmp(n, a, a) == EQ{} : Cmp}

def nodes.word_refl(n, a):
  match n:
    case 0n:
      {==}
    case 1n+p:
      match a:
        case WCon{ab, at}:
          %Equal.sym(Cmp, Word.cmp(p, at, at), EQ{}, nodes.word_refl(p, at)) : {Word.cmp.fin(ab, ab, _) == EQ{} : Cmp}
          nodes.bool_refl(ab)

law nodes.u32_refl:
  for a: U32
  {U32.cmp(a, a) == EQ{} : Cmp}

def nodes.u32_refl(a):
  match a:
    case U32{x}:
      nodes.word_refl(32n, x)

law nodes.str_refl:
  for +a: String
  {String.order(a, a) == EQ{} : Cmp}

def nodes.str_refl(a):
  match a:
    case SNil{}:
      {==}
    case SCon{Chr{x}, t}:
      %Equal.sym(Cmp, U32.cmp(x, x), EQ{}, nodes.u32_refl(x)) : {String.order.go(t, t, _) == EQ{} : Cmp}
      nodes.str_refl(t)

law nodes.eq_refl:
  for +a: String
  {String.eq(a, a) == True{} : Bool}

def nodes.eq_refl(a):
  %Equal.sym(Cmp, String.order(a, a), EQ{}, nodes.str_refl(a)) : {Cmp.is_eq(_) == True{} : Bool}
  {==}

# Svc.sj then Svc.str gives the string back.
law nodes.sj_refl:
  for +s: String
  {String.eq(S.Svc.str(S.Svc.sj(s)), s) == True{} : Bool}

def nodes.sj_refl(s):
  match s:
    case SNil{}:
      {==}
    case SCon{+c, +t}:
      nodes.eq_refl(SCon{c, t})

# Membership.

law nodes.or_assoc:
  for c: Bool
  for p: Bool
  for q: Bool
  {Bool.or(c, Bool.or(p, q)) == Bool.or(Bool.or(c, p), q) : Bool}

def nodes.or_assoc(c, p, q):
  match c:
    case True{}:
      {==}
    case False{}:
      {==}

law nodes.elem_cat:
  for +k: String
  for +a: +List<String>
  for +b: +List<String>
  {M.Meta.elem(k, M.Meta.cat(a, b)) == Bool.or(M.Meta.elem(k, a), M.Meta.elem(k, b)) : Bool}

def nodes.elem_cat(k, a, b):
  match a:
    case Nil{}:
      {==}
    case Con{+x, +r}:
      %Equal.sym(Bool, M.Meta.elem(k, M.Meta.cat(r, b)), Bool.or(M.Meta.elem(k, r), M.Meta.elem(k, b)), nodes.elem_cat(k, r, b)) : {Bool.or(String.eq(k, x), _) == Bool.or(Bool.or(String.eq(k, x), M.Meta.elem(k, r)), M.Meta.elem(k, b)) : Bool}
      nodes.or_assoc(String.eq(k, x), M.Meta.elem(k, r), M.Meta.elem(k, b))

# One pod: it counts for k exactly when its node name joins the list.
law nodes.keep_elem:
  for +b: Bool
  for +k: String
  for +x: String
  for +rest: +List<String>
  for +rec: Bool
  for h: {rec == M.Meta.elem(k, rest) : Bool}
  {Bool.or(Bool.and(b, String.eq(k, x)), rec) == M.Meta.elem(k, ND.Node.keep_node(b, x, rest)) : Bool}

def nodes.keep_elem(b, k, x, rest, rec, h):
  match b:
    case True{}:
      %Equal.sym(Bool, rec, M.Meta.elem(k, rest), h) : {Bool.or(String.eq(k, x), _) == Bool.or(String.eq(k, x), M.Meta.elem(k, rest)) : Bool}
      {==}
    case False{}:
      h

law nodes.v_elem:
  for +name: String
  for +ps: List<&2, J.Json>
  {ND.Node.any_v(name, ps) == M.Meta.elem(name, ND.Node.v_nodes(ps)) : Bool}

def nodes.v_elem(name, ps):
  match ps:
    case Nil{}:
      {==}
    case Con{+p, +r}:
      nodes.keep_elem(ND.Node.v_live(p), name, ND.Node.pod_node(p), ND.Node.v_nodes(r), ND.Node.any_v(name, r), nodes.v_elem(name, r))

law nodes.h_elem:
  for +name: String
  for +ps: List<&2, J.Json>
  {ND.Node.any_h(name, ps) == M.Meta.elem(name, ND.Node.h_nodes(ps)) : Bool}

def nodes.h_elem(name, ps):
  match ps:
    case Nil{}:
      {==}
    case Con{+p, +r}:
      nodes.keep_elem(ND.Node.h_live(p), name, ND.Node.pod_node(p), ND.Node.h_nodes(r), ND.Node.any_h(name, r), nodes.h_elem(name, r))

# A pod needs the node exactly when the node is one of the pods' nodes.
law nodes.needed_elem:
  for +name: String
  for +vpods: List<&2, J.Json>
  for +hpods: List<&2, J.Json>
  {ND.Node.needed(name, vpods, hpods) == M.Meta.elem(name, ND.Node.pod_nodes(vpods, hpods)) : Bool}

def nodes.needed_elem(name, vpods, hpods):
  %Equal.sym(Bool, M.Meta.elem(name, M.Meta.cat(ND.Node.v_nodes(vpods), ND.Node.h_nodes(hpods))), Bool.or(M.Meta.elem(name, ND.Node.v_nodes(vpods)), M.Meta.elem(name, ND.Node.h_nodes(hpods))), nodes.elem_cat(name, ND.Node.v_nodes(vpods), ND.Node.h_nodes(hpods))) : {Bool.or(ND.Node.any_v(name, vpods), ND.Node.any_h(name, hpods)) == _ : Bool}
  %nodes.v_elem(name, vpods) : {Bool.or(ND.Node.any_v(name, vpods), ND.Node.any_h(name, hpods)) == Bool.or(_, M.Meta.elem(name, ND.Node.h_nodes(hpods))) : Bool}
  %nodes.h_elem(name, hpods) : {Bool.or(ND.Node.any_v(name, vpods), ND.Node.any_h(name, hpods)) == Bool.or(ND.Node.any_v(name, vpods), _) : Bool}
  {==}

# The fake node step.

# A needed node that exists stays, whether its addresses change or not.
law nodes.update_keeps:
  for +c: Bool
  for +name: String
  for +w: J.Json
  {ND.Node.after(S.Svc.update.if(c, S.VirtualUpdate{w}, []), name, True{}) == True{} : Bool}

def nodes.update_keeps(c, name, w):
  match c:
    case True{}:
      {==}
    case False{}:
      {==}

law nodes.step_exists:
  for +b: Bool
  for +f: ND.Fake
  for +name: String
  for +ip: String
  for +node: Maybe<&2, J.Json>
  {ND.Node.exists_after(name, node, ND.Node.fake_step.if(b, f, name, ip, node)) == b : Bool}

def nodes.step_exists(b, f, name, ip, node):
  match b node:
    case True{} None{}:
      %Equal.sym(Bool, String.eq(name, name), True{}, nodes.eq_refl(name)) : {ND.Node.hit(_, False{}) == True{} : Bool}
      {==}
    case True{} Some{+n}:
      nodes.update_keeps(S.Svc.eq(J.Json.at(n, ["status", "addresses"]), ND.Node.fake_addresses(f, name, ip)), name, ND.Node.put_status(n, "addresses", ND.Node.fake_addresses(f, name, ip)))
    case False{} None{}:
      {==}
    case False{} Some{+n}:
      %Equal.sym(Bool, String.eq(name, name), True{}, nodes.eq_refl(name)) : {ND.Node.miss(_, True{}) == False{} : Bool}
      {==}

def L.nodes.fake_set(f, name, ip, node, vpods, hpods):
  %nodes.needed_elem(name, vpods, hpods) : {ND.Node.exists_after(name, node, ND.Node.fake_step(f, name, ip, node, vpods, hpods)) == _ : Bool}
  nodes.step_exists(ND.Node.needed(name, vpods, hpods), f, name, ip, node)

# Events.

# The involved object of a translated event is v's namespace and name.
law nodes.translate_refers:
  for +h: J.Json
  for +md: J.Json
  for +tm: J.Json
  for +v: J.Json
  {ND.Ev.refers_one(ND.Ev.translate(h, md, tm, v), v) == True{} : Bool}

def nodes.translate_refers(h, md, tm, v):
  %Equal.sym(Bool, String.eq(S.Svc.str(S.Svc.sj(S.Svc.namespace(v))), S.Svc.namespace(v)), True{}, nodes.sj_refl(S.Svc.namespace(v))) : {Bool.and(_, String.eq(S.Svc.str(S.Svc.sj(S.Svc.name(v))), S.Svc.name(v))) == True{} : Bool}
  nodes.sj_refl(S.Svc.name(v))

law nodes.refers_create:
  for +c: Bool
  for +e: J.Json
  for +v: J.Json
  for h: {ND.Ev.refers_one(e, v) == True{} : Bool}
  {ND.Ev.refers(S.Outcome{ND.Ev.create_if(c, e), S.NoRequeue{}}, v) == True{} : Bool}

def nodes.refers_create(c, e, v, h):
  match c:
    case True{}:
      %Equal.sym(Bool, ND.Ev.refers_one(e, v), True{}, h) : {Bool.and(_, True{}) == True{} : Bool}
      {==}
    case False{}:
      {==}

law nodes.refers_update:
  for +c: Bool
  for +e: J.Json
  for +v: J.Json
  for h: {ND.Ev.refers_one(e, v) == True{} : Bool}
  {ND.Ev.refers(S.Svc.done(S.Svc.update.if(c, S.VirtualUpdate{e}, [])), v) == True{} : Bool}

def nodes.refers_update(c, e, v, h):
  match c:
    case True{}:
      {==}
    case False{}:
      %Equal.sym(Bool, ND.Ev.refers_one(e, v), True{}, h) : {Bool.and(_, True{}) == True{} : Bool}
      {==}

def L.nodes.event_create_refers(h, v, live, ha):
  %Equal.sym(Bool, ND.Ev.accepted(h), True{}, ha) : {ND.Ev.refers(ND.Ev.stv.if(_, h, Some{v}, live), v) == True{} : Bool}
  nodes.refers_create(M.Meta.elem(S.Svc.namespace(v), live), ND.Ev.translate(h, ND.Ev.reset(h), h, v), v, nodes.translate_refers(h, ND.Ev.reset(h), h, v))

def L.nodes.event_update_refers(h, v, ve, ha):
  %Equal.sym(Bool, ND.Ev.accepted(h), True{}, ha) : {ND.Ev.refers(ND.Ev.sync.if(_, h, Some{v}, ve), v) == True{} : Bool}
  nodes.refers_update(S.Svc.eq(ve, ND.Ev.translate(h, J.Json.get(ve, "metadata"), ve, v)), ND.Ev.translate(h, J.Json.get(ve, "metadata"), ve, v), v, nodes.translate_refers(h, J.Json.get(ve, "metadata"), ve, v))
