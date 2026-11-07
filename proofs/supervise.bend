import Base
import ../laws/supervise.bend as L
import ../src/guest/supervise.bend as S

def L.supervise.restart_after_5s():
  {==}

def L.supervise.orphan_ignored():
  {==}

def L.supervise.due_after_delay():
  {==}

def L.supervise.due_at_delay():
  {==}

def L.supervise.running_not_due():
  {==}

def L.supervise.exited_length(svcs, pid, now):
  match svcs:
    case Nil{}:
      {==}
    case Con{s, rest}:
      %L.supervise.exited_length(rest, pid, now) : {1n+List.length(&2, S.Svc, S.Sup.exited(rest, pid, now)) == 1n+_ : Nat}
      {==}

# {simple == computed}, so that % puts the simple form in place.
law Sv.and_not:
  for b: Bool
  {False{} == Bool.and(b, Bool.not(b)) : Bool}

def Sv.and_not(b):
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

def L.supervise.pid0_noop(svcs, now):
  match svcs:
    case Nil{}:
      {==}
    case Con{s, rest}:
      match s:
        case S.Svc{n, prog, args, log, p, r, due}:
          %L.supervise.pid0_noop(rest, now) : {Con{S.Sup.exited.one(S.Svc{n, prog, args, log, p, r, due}, 0, now), S.Sup.exited(rest, 0, now)}
            == Con{S.Svc{n, prog, args, log, p, r, due}, _} : +List<S.Svc>}
          %Sv.and_not(U32.is_eq(p, 0)) : {Con{S.Sup.exited.match(_, n, prog, args, log, p, r, due, now), S.Sup.exited(rest, 0, now)}
            == Con{S.Svc{n, prog, args, log, p, r, due}, S.Sup.exited(rest, 0, now)} : +List<S.Svc>}
          {==}

def Sv.disc(b: Bool) -> Type:
  match b:
    case True{}:
      Empty
    case False{}:
      Unit

law Sv.false_ne_true:
  for h: {False{} == True{} : Bool}
  Empty

def Sv.false_ne_true(h):
  %h : Sv.disc(_)
  Unit{}

law Sv.ex_falso:
  for c: Bool
  for e: Empty
  {c == False{} : Bool}

def Sv.ex_falso(c, e):
  match e:

law Sv.and_false:
  for b: Bool
  for c: Bool
  for h: {Bool.not(b) == True{} : Bool}
  {Bool.and(b, c) == False{} : Bool}

def Sv.and_false(b, c, h):
  match b:
    case True{}:
      Sv.ex_falso(c, Sv.false_ne_true(h))
    case False{}:
      {==}

def L.supervise.running_never_due(s, now, h):
  match s:
    case S.Svc{n, prog, args, log, p, r, due}:
      Sv.and_false(U32.is_eq(p, 0), Nat.is_le(due, now), h)

def L.supervise.stop_order_reverse():
  {==}

law Sv.append_nil:
  for xs: List<&2, U32>
  {xs == List.append(&2, U32, xs, Nil{}) : List<&2, U32>}

def Sv.append_nil(xs):
  match xs:
    case Nil{}:
      {==}
    case Con{x, t}:
      %Sv.append_nil(t) : {Con{x, t} == Con{x, _} : List<&2, U32>}
      {==}

def L.supervise.stop_order_skips_stopped(svcs, s, h):
  match s:
    case S.Svc{n, prog, args, log, p, r, due}:
      %Equal.sym(Bool, U32.is_eq(p, 0), True{}, h) : {List.append(&2, U32, S.Sup.stop_order(svcs), S.Sup.keep.if(_, p)) == S.Sup.stop_order(svcs) : List<&2, U32>}
      %Sv.append_nil(S.Sup.stop_order(svcs)) : {_ == S.Sup.stop_order(svcs) : List<&2, U32>}
      {==}

def L.supervise.stop_order_running_last(svcs, s, h):
  match s:
    case S.Svc{n, prog, args, log, p, r, due}:
      %Equal.sym(Bool, U32.is_eq(p, 0), False{}, h) : {List.append(&2, U32, S.Sup.stop_order(svcs), S.Sup.keep.if(_, p)) == List.append(&2, U32, S.Sup.stop_order(svcs), [p]) : List<&2, U32>}
      {==}

def L.supervise.exited_not_alive():
  {==}

def L.supervise.running_alive():
  {==}

def L.supervise.pids_named():
  {==}
