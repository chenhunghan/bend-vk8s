import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../laws/storage.bend as L
import ../src/translate/names.bend as N
import ../src/translate/services.bend as S
import ../src/translate/storage.bend as T

# Proofs of laws/storage.bend: `def L.<law>` for each law.
#
# The concrete laws compute. The name laws compute too: T.St.named puts the
# name first in the metadata, and the metadata first in the object, so
# reading it back needs no lemma. The cap laws go by cases on whether the
# value exceeds the cap; the fake volume laws by cases on the claim lookup.

# Concrete laws: both sides compute.

def L.storage.pvc_create_forward():
  {==}

def L.storage.pvc_delete_forward_create():
  {==}

def L.storage.pvc_update_forward():
  {==}

def L.storage.pvc_update_forward_not_needed():
  {==}

def L.storage.pvc_delete_forward_update():
  {==}

def L.storage.pvc_backward_annotations():
  {==}

def L.storage.pvc_backward_status():
  {==}

def L.storage.pvc_recreate():
  {==}

def L.storage.pv_create_backward():
  {==}

def L.storage.pv_wrong_namespace():
  {==}

def L.storage.pv_no_virtual_pvc():
  {==}

def L.storage.pv_update_backward():
  {==}

def L.storage.pv_update_backward_again():
  {==}

def L.storage.pv_delete_backward():
  {==}

def L.storage.pv_delete_not_needed():
  {==}

def L.storage.pv_size():
  {==}

def L.storage.pv_retain():
  {==}

def L.storage.pv_delete_reclaim_delete():
  {==}

def L.storage.pv_wait_deleted():
  {==}

def L.storage.pv_delete_without_claim():
  {==}

def L.storage.fake_create():
  {==}

def L.storage.fake_create_not_needed():
  {==}

def L.storage.fake_delete():
  {==}

def L.storage.fake_delete_missing():
  {==}

def L.storage.sc_sync_down():
  {==}

def L.storage.sc_sync():
  {==}

def L.storage.pc_sync_to_host():
  {==}

def L.storage.pc_sync_to_host_create():
  {==}

def L.storage.pc_sync_to_host_delete_virtual():
  {==}

def L.storage.pc_sync_to_virtual():
  {==}

def L.storage.pc_sync_to_virtual_tohost():
  {==}

def L.storage.csi_sync_up():
  {==}

def L.storage.csi_sync_down():
  {==}

def L.storage.csi_sync():
  {==}

def L.storage.csi_sync_node_missing():
  {==}

# Host names.

def L.storage.sc_host_name(c, v):
  {==}

def L.storage.pc_host_name(c, v):
  {==}

def L.storage.pv_host_name(c, v):
  {==}

def L.storage.sc_to_host_creates(c, v, h):
  %Equal.sym(Bool, T.St.deleting(v), False{}, h) : {T.St.Sc.to_host.if(_, c, v) == T.St.done([T.HostCreate{T.St.Sc.translate(c, v)}]) : T.Outcome}
  {==}

# The cap.

law storage.cap_if:
  for b: Bool
  for +t: String
  for h: {T.St.exceeds(t) == b : Bool}
  {T.St.exceeds(T.St.cap_text.if(b, t)) == False{} : Bool}

def storage.cap_if(b, t, h):
  match b:
    case True{}:
      {==}
    case False{}:
      h

def L.storage.cap_text_bounded(t):
  storage.cap_if(T.St.exceeds(t), t, {==})

def L.storage.cap_bounded(j):
  match j:
    case J.JNull{}:
      {==}
    case J.JBool{b}:
      {==}
    case J.JNum{t}:
      L.storage.cap_text_bounded(t)
    case J.JStr{s}:
      {==}
    case J.JArr{xs}:
      {==}
    case J.JObj{ms}:
      {==}
    case J.JNil{}:
      {==}
    case J.JCons{a, b}:
      {==}
    case J.JMem{k, x, r}:
      {==}

def L.storage.pc_value_capped(c, v):
  L.storage.cap_bounded(J.Json.get(v, "value"))

def L.storage.cap_keeps(t, h):
  %Equal.sym(Bool, T.St.exceeds(t), False{}, h) : {T.St.cap_text.if(_, t) == t : String}
  {==}

# Fake volumes.

law storage.fake_sync_if:
  for b: Bool
  for +pv: J.Json
  {T.St.has_writes(T.St.Fake.sync.if(b, pv)) == Bool.not(b) : Bool}

def storage.fake_sync_if(b, pv):
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

def L.storage.fake_delete_iff_unneeded(pv, pvcs):
  storage.fake_sync_if(T.St.Fake.needed(S.Svc.name(pv), pvcs), pv)

def L.storage.fake_delete_same_name(a, b, pvcs, h):
  %Equal.sym(Bool, T.St.has_writes(T.St.Fake.sync(a, pvcs)), Bool.not(T.St.Fake.needed(S.Svc.name(a), pvcs)), L.storage.fake_delete_iff_unneeded(a, pvcs)) : {_ == T.St.has_writes(T.St.Fake.sync(b, pvcs)) : Bool}
  %Equal.sym(String, S.Svc.name(a), S.Svc.name(b), h) : {Bool.not(T.St.Fake.needed(_, pvcs)) == T.St.has_writes(T.St.Fake.sync(b, pvcs)) : Bool}
  Equal.sym(Bool, T.St.has_writes(T.St.Fake.sync(b, pvcs)), Bool.not(T.St.Fake.needed(S.Svc.name(b), pvcs)), L.storage.fake_delete_iff_unneeded(b, pvcs))

law storage.fake_create_m:
  for +name: String
  for m: Maybe<&2, J.Json>
  {T.St.has_writes(T.St.Fake.to_virtual.m(name, m)) == Maybe.is_some(&2, J.Json, m) : Bool}

def storage.fake_create_m(name, m):
  match m:
    case None{}:
      {==}
    case Some{p}:
      {==}

def L.storage.fake_create_iff_needed(name, pvcs):
  storage.fake_create_m(name, T.St.Fake.first(name, pvcs))
