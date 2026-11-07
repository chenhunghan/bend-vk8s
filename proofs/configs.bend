import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../laws/configs.bend as L
import ../src/translate/names.bend as N
import ../src/translate/services.bend as S
import ../src/translate/configs.bend as C
import ./meta.bend as PM

# Proofs of laws/configs.bend: `def L.<law>` for each law.

# Concrete laws: both sides compute.

def L.configs.defaults():
  {==}

def L.configs.cm_unused():
  {==}

def L.configs.cm_used():
  {==}

def L.configs.cm_update_used():
  {==}

def L.configs.cm_remove_unused():
  {==}

def L.configs.secret_unused():
  {==}

def L.configs.secret_used():
  {==}

def L.configs.secret_update_used():
  {==}

def L.configs.secret_remove_unused():
  {==}

def L.configs.sa_sync():
  {==}

def L.configs.mapping_config_maps():
  {==}

def L.configs.mapping_ingress_secrets():
  {==}

def L.configs.mapping_pod_secrets():
  {==}

# Bool helpers (as in proofs/meta.bend).

def configs.bdisc(b: Bool) -> Type:
  match b:
    case False{}:
      Empty
    case True{}:
      Unit

def configs.tf_absurd(-A: Type, e: {True{} == False{} : Bool}) -> A:
  Empty.absurd(A, (%e : configs.bdisc(_); Unit{}))

# String.eq(k, a) == True and String.eq(a, b) == False give
# String.eq(k, b) == False (String.order(k, a) == EQ makes k == a, by the
# lemmas of proofs/meta.bend).
law configs.eq_ne:
  for +k: String
  for +a: String
  for +b: String
  for +ea: {String.eq(k, a) == True{} : Bool}
  for +hab: {String.eq(a, b) == False{} : Bool}
  {String.eq(k, b) == False{} : Bool}

def configs.eq_ne(k, a, b, ea, hab):
  %Equal.sym(String, k, a, PM.meta.str_eq(k, a, PM.meta.is_eq_true(String.order(k, a), ea))) : {String.eq(_, b) == False{} : Bool}
  hab

# A key a with String.eq(a, b) == False: setting a leaves the value under b.

# The JMem step, with the two head tests pa and pb as parameters.
law configs.lookup_put_mem:
  for +k: String
  for +y: J.Json
  for +t: J.Json
  for +a: String
  for +x: J.Json
  for +b: String
  for +hab: {String.eq(a, b) == False{} : Bool}
  for +pa: Bool
  for +pb: Bool
  for +ea: {String.eq(k, a) == pa : Bool}
  for +eb: {String.eq(k, b) == pb : Bool}
  for +ih: {J.Json.lookup(J.Json.put_mem(t, a, x), b) == J.Json.lookup(t, b) : J.Json}
  {J.Json.lookup(J.Json.put_mem.go(J.JMem{k, y, t}, a, x, pa), b) == J.Json.lookup.go(J.JMem{k, y, t}, b, pb) : J.Json}

def configs.lookup_put_mem(k, y, t, a, x, b, hab, pa, pb, ea, eb, ih):
  match pa pb:
    case True{} True{}:
      configs.tf_absurd({J.Json.lookup.go(J.JMem{k, x, t}, b, String.eq(k, b)) == J.Json.lookup.go(J.JMem{k, y, t}, b, True{}) : J.Json},
        Equal.trans(Bool, True{}, String.eq(k, b), False{}, Equal.sym(Bool, String.eq(k, b), True{}, eb), configs.eq_ne(k, a, b, ea, hab)))
    case True{} False{}:
      %Equal.sym(Bool, String.eq(k, b), False{}, eb) : {J.Json.lookup.go(J.JMem{k, x, t}, b, _) == J.Json.lookup.go(J.JMem{k, y, t}, b, False{}) : J.Json}
      {==}
    case False{} True{}:
      %Equal.sym(Bool, String.eq(k, b), True{}, eb) : {J.Json.lookup.go(J.JMem{k, y, J.Json.put_mem(t, a, x)}, b, _) == J.Json.lookup.go(J.JMem{k, y, t}, b, True{}) : J.Json}
      {==}
    case False{} False{}:
      %Equal.sym(Bool, String.eq(k, b), False{}, eb) : {J.Json.lookup.go(J.JMem{k, y, J.Json.put_mem(t, a, x)}, b, _) == J.Json.lookup.go(J.JMem{k, y, t}, b, False{}) : J.Json}
      ih

law configs.lookup_put_other:
  for +ms: J.Json
  for +a: String
  for +x: J.Json
  for +b: String
  for +hab: {String.eq(a, b) == False{} : Bool}
  {J.Json.lookup(J.Json.put_mem(ms, a, x), b) == J.Json.lookup(ms, b) : J.Json}

def configs.lookup_put_other(ms, a, x, b, hab):
  match ms:
    case J.JMem{+k, +y, +t}:
      configs.lookup_put_mem(k, y, t, a, x, b, hab, String.eq(k, a), String.eq(k, b), {==}, {==}, configs.lookup_put_other(t, a, x, b, hab))
    case J.JNull{}:
      %Equal.sym(Bool, String.eq(a, b), False{}, hab) : {J.Json.lookup.go(J.JMem{a, x, J.JNil{}}, b, _) == J.JNull{} : J.Json}
      {==}
    case J.JBool{q}:
      %Equal.sym(Bool, String.eq(a, b), False{}, hab) : {J.Json.lookup.go(J.JMem{a, x, J.JNil{}}, b, _) == J.JNull{} : J.Json}
      {==}
    case J.JNum{q}:
      %Equal.sym(Bool, String.eq(a, b), False{}, hab) : {J.Json.lookup.go(J.JMem{a, x, J.JNil{}}, b, _) == J.JNull{} : J.Json}
      {==}
    case J.JStr{q}:
      %Equal.sym(Bool, String.eq(a, b), False{}, hab) : {J.Json.lookup.go(J.JMem{a, x, J.JNil{}}, b, _) == J.JNull{} : J.Json}
      {==}
    case J.JArr{q}:
      %Equal.sym(Bool, String.eq(a, b), False{}, hab) : {J.Json.lookup.go(J.JMem{a, x, J.JNil{}}, b, _) == J.JNull{} : J.Json}
      {==}
    case J.JObj{q}:
      %Equal.sym(Bool, String.eq(a, b), False{}, hab) : {J.Json.lookup.go(J.JMem{a, x, J.JNil{}}, b, _) == J.JNull{} : J.Json}
      {==}
    case J.JNil{}:
      %Equal.sym(Bool, String.eq(a, b), False{}, hab) : {J.Json.lookup.go(J.JMem{a, x, J.JNil{}}, b, _) == J.JNull{} : J.Json}
      {==}
    case J.JCons{p, q}:
      %Equal.sym(Bool, String.eq(a, b), False{}, hab) : {J.Json.lookup.go(J.JMem{a, x, J.JNil{}}, b, _) == J.JNull{} : J.Json}
      {==}

law configs.get_set_other:
  for +j: J.Json
  for +a: String
  for +x: J.Json
  for +b: String
  for +hab: {String.eq(a, b) == False{} : Bool}
  {J.Json.get(J.Json.set(j, a, x), b) == J.Json.get(j, b) : J.Json}

def configs.get_set_other(j, a, x, b, hab):
  match j:
    case J.JObj{+ms}:
      configs.lookup_put_other(ms, a, x, b, hab)
    case J.JNull{}:
      configs.lookup_put_other(J.JNull{}, a, x, b, hab)
    case J.JBool{q}:
      configs.lookup_put_other(J.JNull{}, a, x, b, hab)
    case J.JNum{q}:
      configs.lookup_put_other(J.JNull{}, a, x, b, hab)
    case J.JStr{q}:
      configs.lookup_put_other(J.JNull{}, a, x, b, hab)
    case J.JArr{q}:
      configs.lookup_put_other(J.JNull{}, a, x, b, hab)
    case J.JNil{}:
      configs.lookup_put_other(J.JNull{}, a, x, b, hab)
    case J.JCons{p, q}:
      configs.lookup_put_other(J.JNull{}, a, x, b, hab)
    case J.JMem{p, q, r}:
      configs.lookup_put_other(J.JNull{}, a, x, b, hab)

# The secret type step keeps data.
law configs.opaque_keeps:
  for +t: Bool
  for +o: J.Json
  {J.Json.get(C.Configs.opaque.if(t, o), "data") == J.Json.get(o, "data") : J.Json}

def configs.opaque_keeps(t, o):
  match t:
    case True{}:
      configs.get_set_other(o, "type", J.JStr{C.Configs.opaque()}, "data", {==})
    case False{}:
      {==}

# General laws.

def L.configs.cm_keeps_data(c, v):
  configs.get_set_other(v, "metadata", C.Configs.host_meta(c, C.Configs.cm_kind(), v, C.Configs.cm_host_ref(c, S.Svc.namespace(v), S.Svc.name(v))), "data", {==})

def L.configs.cm_keeps_binary_data(c, v):
  configs.get_set_other(v, "metadata", C.Configs.host_meta(c, C.Configs.cm_kind(), v, C.Configs.cm_host_ref(c, S.Svc.namespace(v), S.Svc.name(v))), "binaryData", {==})

def L.configs.secret_keeps_data(c, v):
  +o = C.Configs.host_copy(c, C.Configs.secret_kind(), v, C.Configs.secret_host_ref(c, S.Svc.namespace(v), S.Svc.name(v)))
  Equal.trans(J.Json, J.Json.get(C.Configs.secret_to_host(c, v), "data"), J.Json.get(o, "data"), J.Json.get(v, "data"),
    configs.opaque_keeps(String.eq(C.Configs.str_at(v, ["type"]), C.Configs.sa_token_type()), o),
    configs.get_set_other(v, "metadata", C.Configs.host_meta(c, C.Configs.secret_kind(), v, C.Configs.secret_host_ref(c, S.Svc.namespace(v), S.Svc.name(v))), "data", {==}))

def L.configs.secret_host_name(c, ns, name):
  match name:
    case SNil{}:
      {==}
    case SCon{h, t}:
      {==}

def L.configs.sa_host_name(c, ns, name):
  match name:
    case SNil{}:
      {==}
    case SCon{h, t}:
      {==}

def L.configs.cm_host_name(c, ns, name, h):
  match name:
    case SNil{}:
      {==}
    case SCon{+a, +t}:
      %Equal.sym(Bool, String.eq(N.Names.host_name(SCon{a, t}, ns, S.Svc.vc(c)), "kube-root-ca.crt"), False{}, h) :
        {C.Configs.ref_name(C.Configs.root_ca_ref.if(_, c, C.Configs.plain_ref(c, ns, SCon{a, t}))) == N.Names.host_name(SCon{a, t}, ns, S.Svc.vc(c)) : String}
      {==}
