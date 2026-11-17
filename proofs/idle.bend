import Base
import ../laws/idle.bend as L
import ../src/cli/idle.bend as I

# Proofs of laws/idle.bend: `def L.<law>` for each law.

def L.idle.parse.go_zero():
  {==}

def L.idle.parse.go_5s():
  {==}

def L.idle.parse.go_1478s():
  {==}

def L.idle.parse.go_15m():
  {==}

def L.idle.parse.go_16h():
  {==}

def L.idle.parse.go_3h30m():
  {==}

def L.idle.parse.go_err_empty():
  {==}

def L.idle.parse.go_err_unit_alone():
  {==}

def L.idle.parse.go_err_days():
  {==}

def L.idle.parse.go_err_dot():
  {==}

def L.idle.parse.bare_minutes():
  {==}

def L.idle.setting.default():
  {==}

def L.idle.setting.env_off():
  {==}

def L.idle.setting.flag_wins(env):
  {==}

def L.idle.flag.value():
  {==}

def L.idle.flag.value_eq():
  {==}

def L.idle.flag.dropped():
  {==}

def L.idle.off_never_sleeps(st, now):
  match st:
    case I.IdleSt{c, last, a}:
      match a:
        case True{}:
          {==}
        case False{}:
          {==}

# An awake tick with connections open stays, whatever the other tests say.
def idle.busy(off: Bool, back: Bool, due: Bool, +c: U32, +last: U32, +now: U32) ->
  {I.Idle.Out.act(I.Idle.tick.go(False{}, off, False{}, back, due, c, last, now)) == I.IdleStay{} : I.Idle.Act}:
  match off:
    case True{}:
      {==}
    case False{}:
      {==}

def L.idle.busy_never_sleeps(limit, c, last, now, h):
  %Equal.sym(Bool, U32.is_eq(c, 0), False{}, h) : {I.Idle.Out.act(I.Idle.tick.go(False{}, U32.is_eq(limit, 0), _, U32.is_lt(now, last), U32.is_ge((now - last : U32), limit), c, last, now))
    == I.IdleStay{} : I.Idle.Act}
  idle.busy(U32.is_eq(limit, 0), U32.is_lt(now, last), U32.is_ge((now - last : U32), limit), c, last, now)

def L.idle.asleep_stays(limit, c, last, now):
  {==}

def L.idle.due_sleeps(limit, last, now, h1, h2, h3):
  %Equal.sym(Bool, U32.is_eq(limit, 0), False{}, h1) : {I.Idle.tick.go(False{}, _, U32.is_eq(0, 0), U32.is_lt(now, last), U32.is_ge((now - last : U32), limit), 0, last, now)
    == I.IdleOut{I.IdleSt{0, now, True{}}, I.IdleSleep{}} : I.Idle.Out}
  %Equal.sym(Bool, U32.is_lt(now, last), False{}, h2) : {I.Idle.tick.go(False{}, False{}, U32.is_eq(0, 0), _, U32.is_ge((now - last : U32), limit), 0, last, now)
    == I.IdleOut{I.IdleSt{0, now, True{}}, I.IdleSleep{}} : I.Idle.Out}
  %Equal.sym(Bool, U32.is_ge((now - last : U32), limit), True{}, h3) : {I.Idle.tick.go(False{}, False{}, U32.is_eq(0, 0), False{}, _, 0, last, now)
    == I.IdleOut{I.IdleSt{0, now, True{}}, I.IdleSleep{}} : I.Idle.Out}
  {==}

# An awake tick before the limit stays.
def idle.not_due(off: Bool, idle: Bool, back: Bool, +c: U32, +last: U32, +now: U32) ->
  {I.Idle.Out.act(I.Idle.tick.go(False{}, off, idle, back, False{}, c, last, now)) == I.IdleStay{} : I.Idle.Act}:
  match off idle back:
    case True{} _ _:
      {==}
    case False{} False{} _:
      {==}
    case False{} True{} True{}:
      {==}
    case False{} True{} False{}:
      {==}

def L.idle.not_due_stays(limit, c, last, now, h):
  %Equal.sym(Bool, U32.is_ge((now - last : U32), limit), False{}, h) : {I.Idle.Out.act(I.Idle.tick.go(False{}, U32.is_eq(limit, 0), U32.is_eq(c, 0), U32.is_lt(now, last), _, c, last, now))
    == I.IdleStay{} : I.Idle.Act}
  idle.not_due(U32.is_eq(limit, 0), U32.is_eq(c, 0), U32.is_lt(now, last), c, last, now)

# An awake tick whose clock went back stays.
def idle.back(off: Bool, idle: Bool, due: Bool, +c: U32, +last: U32, +now: U32) ->
  {I.Idle.Out.act(I.Idle.tick.go(False{}, off, idle, True{}, due, c, last, now)) == I.IdleStay{} : I.Idle.Act}:
  match off idle:
    case True{} _:
      {==}
    case False{} False{}:
      {==}
    case False{} True{}:
      {==}

def L.idle.clock_back(limit, c, last, now, h):
  %Equal.sym(Bool, U32.is_lt(now, last), True{}, h) : {I.Idle.Out.act(I.Idle.tick.go(False{}, U32.is_eq(limit, 0), U32.is_eq(c, 0), _, U32.is_ge((now - last : U32), limit), c, last, now))
    == I.IdleStay{} : I.Idle.Act}
  idle.back(U32.is_eq(limit, 0), U32.is_eq(c, 0), U32.is_ge((now - last : U32), limit), c, last, now)

def L.idle.open_wakes(limit, c, last, now):
  {==}

def L.idle.open_awake_passes(limit, c, last, now):
  {==}

def L.idle.close_restarts(limit, c, last, a, now):
  {==}

def L.idle.wake_vm_sets_clock():
  {==}

def L.idle.wake_container():
  {==}

def L.idle.forwards.standalone():
  {==}

def L.idle.forwards.classic():
  {==}

def L.idle.inner_port():
  {==}
