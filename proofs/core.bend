import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../laws/core.bend as L
import ../src/sync/core.bend as C

# Proofs of laws/core.bend: `def L.<law>` for each law.
#
# The concrete laws compute. The general laws rest on one lemma: structural
# JSON equality is reflexive (core.json_refl, from String.order being
# reflexive, as proofs/meta.bend shows). An unmanaged host object makes
# Core.decide skip before anything else is read, so those laws compute
# once the hypothesis is rewritten in.

# Reflexivity kit (as in proofs/meta.bend).

law core.bool_refl:
  for a: Bool
  {Bool.cmp(a, a) == EQ{} : Cmp}

def core.bool_refl(a):
  match a:
    case False{}:
      {==}
    case True{}:
      {==}

law core.word_refl:
  for +n: Nat
  for +a: Word(n)
  {Word.cmp(n, a, a) == EQ{} : Cmp}

def core.word_refl(n, a):
  match n:
    case 0n:
      {==}
    case 1n+p:
      match a:
        case WCon{ab, at}:
          %Equal.sym(Cmp, Word.cmp(p, at, at), EQ{}, core.word_refl(p, at)) : {Word.cmp.fin(ab, ab, _) == EQ{} : Cmp}
          core.bool_refl(ab)

law core.u32_refl:
  for a: U32
  {U32.cmp(a, a) == EQ{} : Cmp}

def core.u32_refl(a):
  match a:
    case U32{x}:
      core.word_refl(32n, x)

law core.str_refl:
  for +a: String
  {String.order(a, a) == EQ{} : Cmp}

def core.str_refl(a):
  match a:
    case SNil{}:
      {==}
    case SCon{Chr{x}, t}:
      %Equal.sym(Cmp, U32.cmp(x, x), EQ{}, core.u32_refl(x)) : {String.order.go(t, t, _) == EQ{} : Cmp}
      core.str_refl(t)

law core.str_eq_refl:
  for +a: String
  {String.eq(a, a) == True{} : Bool}

def core.str_eq_refl(a):
  %Equal.sym(Cmp, String.order(a, a), EQ{}, core.str_refl(a)) : {Cmp.is_eq(_) == True{} : Bool}
  {==}

law core.json_refl:
  for +a: J.Json
  {C.Core.json_eq(a, a) == True{} : Bool}

def core.json_refl(a):
  match a:
    case J.JNull{}:
      {==}
    case J.JBool{b}:
      match b:
        case True{}:
          {==}
        case False{}:
          {==}
    case J.JNum{s}:
      core.str_eq_refl(s)
    case J.JStr{s}:
      core.str_eq_refl(s)
    case J.JArr{x}:
      core.json_refl(x)
    case J.JObj{x}:
      core.json_refl(x)
    case J.JNil{}:
      {==}
    case J.JCons{h, t}:
      %Equal.sym(Bool, C.Core.json_eq(h, h), True{}, core.json_refl(h)) : {Bool.and(_, C.Core.json_eq(t, t)) == True{} : Bool}
      core.json_refl(t)
    case J.JMem{k, v, t}:
      %Equal.sym(Bool, String.eq(k, k), True{}, core.str_eq_refl(k)) : {Bool.and(_, Bool.and(C.Core.json_eq(v, v), C.Core.json_eq(t, t))) == True{} : Bool}
      %Equal.sym(Bool, C.Core.json_eq(v, v), True{}, core.json_refl(v)) : {Bool.and(_, C.Core.json_eq(t, t)) == True{} : Bool}
      core.json_refl(t)

# Concrete laws: both sides compute.

def L.core.controller_sync_down():
  {==}

def L.core.reconcile_sync_down():
  {==}

def L.core.reconcile_adopt_writes():
  {==}

def L.core.reconcile_adopt_state():
  {==}

def L.core.reconcile_not_adopt():
  {==}

def L.core.from_host_new_namespace():
  {==}

def L.core.from_host_new_create():
  {==}

def L.core.from_host_update_writes():
  {==}

def L.core.from_host_update_state():
  {==}

def L.core.from_host_delete():
  {==}

def L.core.cache_rebase_written_rv():
  {==}

def L.core.cache_rebase_written_data():
  {==}

def L.core.cache_rebase_nothing():
  {==}

def L.core.cache_rebase_none():
  {==}

def L.core.sanitize_configmap():
  {==}

def L.core.sanitize_data_username():
  {==}

def L.core.sanitize_data_password():
  {==}

def L.core.sanitize_string_data():
  {==}

def L.core.sanitize_both_data():
  {==}

def L.core.sanitize_both_string_data():
  {==}

def L.core.sanitize_no_data():
  {==}

def L.core.sanitize_data_null():
  {==}

def L.core.sanitize_malformed():
  {==}

def L.core.sanitize_last_applied_kind():
  {==}

def L.core.sanitize_last_applied_api_version():
  {==}

def L.core.sanitize_last_applied_password():
  {==}

def L.core.sanitize_last_applied_username():
  {==}

# General laws.

# Not managed: exclude_p is True by computation, so decide skips.
def L.core.unmanaged_skip(cfg, vold, v, pold, p):
  {==}

def L.core.unmanaged_to_host(cfg, fields, mapped, expected, vold, v, pold, p, h):
  %Equal.sym(Bool, C.Core.is_managed_to_host(cfg, mapped, expected, p), False{}, h) : {C.Core.reconcile_to_host(cfg, fields, _, vold, v, pold, Some{p}) == C.Out{[], C.Settled{}} : C.Out}
  {==}

def L.core.unmanaged_from_host(cfg, fields, matched, vold, v, pold, p, vname, vns, ns, h):
  %Equal.sym(Bool, C.Core.is_managed_from_host(matched, p), False{}, h) : {C.Core.reconcile_from_host(cfg, fields, _, vold, v, pold, Some{p}, vname, vns, ns) == C.Out{[], C.Settled{}} : C.Out}
  {==}

def L.core.unmanaged_not_enqueued(named, is_delete, p):
  {==}

def L.core.apply_object_same(s, x, hs):
  %Equal.sym(Bool, C.Core.json_eq(x, x), True{}, core.json_refl(x)) : {C.Core.apply_object.if(_, s, x, x, hs) == [] : List<&2, C.Write>}
  {==}

law core.patch_host_same:
  for +skip: Bool
  for +x: J.Json
  for +hs: Bool
  {C.Core.patch_host(skip, x, x, hs) == [] : List<&2, C.Write>}

def core.patch_host_same(skip, x, hs):
  match skip:
    case True{}:
      {==}
    case False{}:
      L.core.apply_object_same(C.Host{}, x, hs)

def L.core.in_sync_no_writes(v, p, skip, hs):
  %Equal.sym(List<&2, C.Write>, C.Core.apply_object(C.Virtual{}, v, v, hs), [], L.core.apply_object_same(C.Virtual{}, v, hs)) : {C.Core.cat(_, C.Core.patch_host(skip, p, p, hs)) == [] : List<&2, C.Write>}
  core.patch_host_same(skip, p, hs)

def L.core.copy_bidirectional_in_sync(v, h):
  %Equal.sym(Bool, C.Core.json_eq(v, v), True{}, core.json_refl(v)) : {C.Core.cb.if(_, C.Core.json_eq(h, h), v, h) == (v, h) : J.Json & J.Json}
  %Equal.sym(Bool, C.Core.json_eq(h, h), True{}, core.json_refl(h)) : {C.Core.cb.if(True{}, _, v, h) == (v, h) : J.Json & J.Json}
  {==}

def L.core.merge_bidirectional_in_sync(v, h):
  %Equal.sym(Bool, C.Core.json_eq(v, v), True{}, core.json_refl(v)) : {C.Core.mb.if(_, C.Core.json_eq(h, h), v, v, h, h) == (v, h) : J.Json & J.Json}
  %Equal.sym(Bool, C.Core.json_eq(h, h), True{}, core.json_refl(h)) : {C.Core.mb.if(True{}, _, v, v, h, h) == (v, h) : J.Json & J.Json}
  {==}

def L.core.from_host_in_sync(fields, v, p, h):
  %Equal.sym(J.Json, C.Core.from_host.copy(fields, v, p), v, h) : {C.Out{C.Core.patch_writes(v, _, p, p, True{}, True{}), C.Settled{}} == C.Out{[], C.Settled{}} : C.Out}
  %Equal.sym(List<&2, C.Write>, C.Core.patch_writes(v, v, p, p, True{}, True{}), [], L.core.in_sync_no_writes(v, p, True{}, True{})) : {C.Out{_, C.Settled{}} == C.Out{[], C.Settled{}} : C.Out}
  {==}

def L.core.decide_total(cfg, managed, vold, v, pold, p):
  (C.Core.decide(cfg, managed, vold, v, pold, p), {==})

def L.core.decide_unique(cfg, managed, vold, v, pold, p, d1, d2, h1, h2):
  Equal.trans(C.Decision, d1, C.Core.decide(cfg, managed, vold, v, pold, p), d2, Equal.sym(C.Decision, C.Core.decide(cfg, managed, vold, v, pold, p), d1, h1), h2)

def L.core.decide_nothing(cfg, managed, vold, pold):
  {==}
