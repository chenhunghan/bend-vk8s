import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../laws/services.bend as L
import ../src/translate/meta.bend as M
import ../src/translate/names.bend as N
import ../src/translate/services.bend as S

# Proofs of laws/services.bend: `def L.<law>` for each law.
#
# The concrete laws compute. The selector law is proved key by key: Meta.insert
# only adds a key it is given, the keys host_keys inserts are the host keys
# of the virtual keys, and add_marker adds the two markers. Its kit is
# String.order(a, a) == EQ (as in proofs/meta.bend) and three Bool lemmas.
# The port laws go by induction on the list.

# Concrete laws: both sides compute.

def L.services.create_forward():
  {==}

def L.services.node_ports_backward():
  {==}

def L.services.ports_forward():
  {==}

def L.services.update_forward():
  {==}

def L.services.update_forward_not_needed():
  {==}

def L.services.backward_spec():
  {==}

def L.services.backward_spec_settled():
  {==}

def L.services.backward_spec_recreate():
  {==}

def L.services.backward_spec_recreated():
  {==}

def L.services.backward_status():
  {==}

def L.services.backward_not_needed():
  {==}

def L.services.kubernetes_no_host():
  {==}

def L.services.kubernetes_no_virtual():
  {==}

def L.services.kubernetes_recreate():
  {==}

def L.services.kubernetes_update():
  {==}

def L.services.external_name_to_cluster_ip():
  {==}

def L.services.external_name_to_node_port():
  {==}

def L.services.load_balancer_to_node_port():
  {==}

def L.services.load_balancer_to_cluster_ip():
  {==}

def L.services.endpoints_override_start():
  {==}

def L.services.endpoints_override_create():
  {==}

def L.services.endpoints_forward_create():
  {==}

def L.services.endpoints_forward_update():
  {==}

def L.services.endpoints_skip_kubernetes():
  {==}

def L.services.slices_override_start():
  {==}

def L.services.slices_override_create():
  {==}

def L.services.slices_forward_create():
  {==}

def L.services.slices_forward_update():
  {==}

def L.services.slices_skip_kubernetes():
  {==}

# Bool helpers (as in proofs/meta.bend).

def services.bdisc(b: Bool) -> Type:
  match b:
    case False{}:
      Empty
    case True{}:
      Unit

def services.tf_absurd(-A: Type, e: {True{} == False{} : Bool}) -> A:
  Empty.absurd(A, (%e : services.bdisc(_); Unit{}))

law services.and_l:
  for a: Bool
  for b: Bool
  for h: {Bool.and(a, b) == True{} : Bool}
  {a == True{} : Bool}

def services.and_l(a, b, h):
  match a:
    case True{}:
      {==}
    case False{}:
      h

law services.and_r:
  for a: Bool
  for b: Bool
  for h: {Bool.and(a, b) == True{} : Bool}
  {b == True{} : Bool}

def services.and_r(a, b, h):
  match a:
    case True{}:
      h
    case False{}:
      services.tf_absurd({b == True{} : Bool}, Equal.sym(Bool, False{}, True{}, h))

law services.and_i:
  for a: Bool
  for b: Bool
  for ha: {a == True{} : Bool}
  for hb: {b == True{} : Bool}
  {Bool.and(a, b) == True{} : Bool}

def services.and_i(a, b, ha, hb):
  %Equal.sym(Bool, a, True{}, ha) : {Bool.and(_, b) == True{} : Bool}
  hb

law services.or_true:
  for b: Bool
  {Bool.or(b, True{}) == True{} : Bool}

def services.or_true(b):
  match b:
    case False{}:
      {==}
    case True{}:
      {==}

# String.order(a, a) == EQ (as in proofs/meta.bend).

law services.bool_refl:
  for a: Bool
  {Bool.cmp(a, a) == EQ{} : Cmp}

def services.bool_refl(a):
  match a:
    case False{}:
      {==}
    case True{}:
      {==}

law services.word_refl:
  for +n: Nat
  for +a: Word(n)
  {Word.cmp(n, a, a) == EQ{} : Cmp}

def services.word_refl(n, a):
  match n:
    case 0n:
      {==}
    case 1n+p:
      match a:
        case WCon{ab, at}:
          %Equal.sym(Cmp, Word.cmp(p, at, at), EQ{}, services.word_refl(p, at)) : {Word.cmp.fin(ab, ab, _) == EQ{} : Cmp}
          services.bool_refl(ab)

law services.u32_refl:
  for a: U32
  {U32.cmp(a, a) == EQ{} : Cmp}

def services.u32_refl(a):
  match a:
    case U32{x}:
      services.word_refl(32n, x)

law services.str_refl:
  for +a: String
  {String.order(a, a) == EQ{} : Cmp}

def services.str_refl(a):
  match a:
    case SNil{}:
      {==}
    case SCon{Chr{x}, t}:
      %Equal.sym(Cmp, U32.cmp(x, x), EQ{}, services.u32_refl(x)) : {String.order.go(t, t, _) == EQ{} : Cmp}
      services.str_refl(t)

# Membership.

# k is a member of k <> a.
law services.elem_self:
  for +k: String
  for +a: +List<String>
  {M.Meta.elem(k, k <> a) == True{} : Bool}

def services.elem_self(k, a):
  %Equal.sym(Cmp, String.order(k, k), EQ{}, services.str_refl(k)) : {Bool.or(Cmp.is_eq(_), M.Meta.elem(k, a)) == True{} : Bool}
  {==}

# A member of a is a member of x <> a.
law services.elem_cons:
  for +k: String
  for +x: String
  for +a: +List<String>
  for +h: {M.Meta.elem(k, a) == True{} : Bool}
  {M.Meta.elem(k, x <> a) == True{} : Bool}

def services.elem_cons(k, x, a, h):
  %Equal.sym(Bool, M.Meta.elem(k, a), True{}, h) : {Bool.or(String.eq(k, x), _) == True{} : Bool}
  services.or_true(String.eq(k, x))

# Keys in a are keys in x <> a.
law services.keys_in_cons:
  for +m: +List<M.KV>
  for +x: String
  for +a: +List<String>
  for +h: {S.Svc.keys_in(m, a) == True{} : Bool}
  {S.Svc.keys_in(m, x <> a) == True{} : Bool}

def services.keys_in_cons(m, x, a, h):
  match m:
    case Nil{}:
      {==}
    case Con{M.KV{+k, +v}, +r}:
      services.and_i(M.Meta.elem(k, x <> a), S.Svc.keys_in(r, x <> a),
        services.elem_cons(k, x, a, services.and_l(M.Meta.elem(k, a), S.Svc.keys_in(r, a), h)),
        services.keys_in_cons(r, x, a, services.and_r(M.Meta.elem(k, a), S.Svc.keys_in(r, a), h)))

# Meta.insert adds no key but the one it is given.
law services.keys_in_insert_go:
  for +c: Cmp
  for +kk: String
  for +vv: String
  for +k: String
  for +v: String
  for +r: +List<M.KV>
  for +a: +List<String>
  for +hk: {M.Meta.elem(k, a) == True{} : Bool}
  for +hkk: {M.Meta.elem(kk, a) == True{} : Bool}
  for +hr: {S.Svc.keys_in(r, a) == True{} : Bool}
  for +ih: {S.Svc.keys_in(M.Meta.insert(k, v, r), a) == True{} : Bool}
  {S.Svc.keys_in(M.Meta.insert.if(c, kk, vv, k, v, r, M.Meta.insert(k, v, r)), a) == True{} : Bool}

def services.keys_in_insert_go(c, kk, vv, k, v, r, a, hk, hkk, hr, ih):
  match c:
    case LT{}:
      services.and_i(M.Meta.elem(k, a), S.Svc.keys_in(M.KV{kk, vv} <> r, a), hk,
        services.and_i(M.Meta.elem(kk, a), S.Svc.keys_in(r, a), hkk, hr))
    case EQ{}:
      services.and_i(M.Meta.elem(kk, a), S.Svc.keys_in(r, a), hkk, hr)
    case GT{}:
      services.and_i(M.Meta.elem(kk, a), S.Svc.keys_in(M.Meta.insert(k, v, r), a), hkk, ih)

law services.keys_in_insert:
  for +k: String
  for +v: String
  for +m: +List<M.KV>
  for +a: +List<String>
  for +hk: {M.Meta.elem(k, a) == True{} : Bool}
  for +hm: {S.Svc.keys_in(m, a) == True{} : Bool}
  {S.Svc.keys_in(M.Meta.insert(k, v, m), a) == True{} : Bool}

def services.keys_in_insert(k, v, m, a, hk, hm):
  match m:
    case Nil{}:
      services.and_i(M.Meta.elem(k, a), True{}, hk, {==})
    case Con{M.KV{+kk, +vv}, +r}:
      +hr = services.and_r(M.Meta.elem(kk, a), S.Svc.keys_in(r, a), hm)
      services.keys_in_insert_go(String.order(k, kk), kk, vv, k, v, r, a, hk,
        services.and_l(M.Meta.elem(kk, a), S.Svc.keys_in(r, a), hm), hr,
        services.keys_in_insert(k, v, r, a, hk, hr))

# The host labels of a map use the host keys of its keys.
law services.host_keys_go:
  for +b: Bool
  for +hk: String
  for +v: String
  for +rec: +List<M.KV>
  for +a: +List<String>
  for +ih: {S.Svc.keys_in(rec, a) == True{} : Bool}
  {S.Svc.keys_in(M.Meta.host_keys.if(b, hk, v, rec), hk <> a) == True{} : Bool}

def services.host_keys_go(b, hk, v, rec, a, ih):
  match b:
    case True{}:
      services.keys_in_cons(rec, hk, a, ih)
    case False{}:
      services.keys_in_insert(hk, v, rec, hk <> a, services.elem_self(hk, a), services.keys_in_cons(rec, hk, a, ih))

law services.keys_in_host_keys:
  for +vc: String
  for +m: +List<M.KV>
  {S.Svc.keys_in(M.Meta.host_keys(M.Meta.tkeys(vc), m), S.Svc.hl_keys(vc, M.Meta.keys(m))) == True{} : Bool}

def services.keys_in_host_keys(vc, m):
  match m:
    case Nil{}:
      {==}
    case Con{M.KV{+k, +v}, +r}:
      services.host_keys_go(Maybe.is_some(&2, String, M.Meta.is_translated.t(M.Meta.tkeys(vc), k)),
        M.Meta.host_label.t(M.Meta.tkeys(vc), k), v, M.Meta.host_keys(M.Meta.tkeys(vc), r),
        S.Svc.hl_keys(vc, M.Meta.keys(r)), services.keys_in_host_keys(vc, r))

# add_marker adds only the two markers.
law services.marker_go:
  for +b: Bool
  for +vc: String
  for +target: String
  for +ns: String
  for +nl: +List<M.KV>
  for +h: +List<String>
  for +ih: {S.Svc.keys_in(nl, h) == True{} : Bool}
  {S.Svc.keys_in(M.Meta.add_marker.if(b, vc, target, ns, nl), M.Meta.marker_label() <> M.Meta.namespace_label() <> h) == True{} : Bool}

def services.marker_go(b, vc, target, ns, nl, h, ih):
  match b:
    case True{}:
      services.keys_in_insert(M.Meta.marker_label(), N.Names.marker_cluster(target, vc), nl,
        M.Meta.marker_label() <> M.Meta.namespace_label() <> h, {==},
        services.keys_in_cons(nl, M.Meta.marker_label(), M.Meta.namespace_label() <> h, services.keys_in_cons(nl, M.Meta.namespace_label(), h, ih)))
    case False{}:
      +hm = services.keys_in_cons(nl, M.Meta.marker_label(), M.Meta.namespace_label() <> h, services.keys_in_cons(nl, M.Meta.namespace_label(), h, ih))
      services.keys_in_insert(M.Meta.namespace_label(), ns, M.Meta.insert(M.Meta.marker_label(), vc, nl),
        M.Meta.marker_label() <> M.Meta.namespace_label() <> h, {==},
        services.keys_in_insert(M.Meta.marker_label(), vc, nl, M.Meta.marker_label() <> M.Meta.namespace_label() <> h, {==}, hm))

# General laws.

def L.services.selector_keys(vc, target, ns, sel):
  services.marker_go(String.is_empty(ns), vc, target, ns, M.Meta.host_keys(M.Meta.tkeys(vc), sel),
    S.Svc.hl_keys(vc, M.Meta.keys(sel)), services.keys_in_host_keys(vc, sel))

def L.services.ports_keep_length(ps):
  match ps:
    case Nil{}:
      {==}
    case Con{+p, +r}:
      %L.services.ports_keep_length(r) : {1n+List.length(&2, S.Port, S.Svc.strip_node_ports(r)) == 1n+_ : Nat}
      {==}

def L.services.ports_keep_order(ps):
  match ps:
    case Nil{}:
      {==}
    case Con{S.Port{+n, +pr, +ap, +po, +tp, +np}, +r}:
      %L.services.ports_keep_order(r) : {S.Svc.port_id(S.Port{n, pr, ap, po, tp, np}) <> S.Svc.port_ids(S.Svc.strip_node_ports(r)) == S.Svc.port_id(S.Port{n, pr, ap, po, tp, np}) <> _ : List<&2, J.Json>}
      {==}
