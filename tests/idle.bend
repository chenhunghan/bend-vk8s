import Base
import ../src/cli/idle.bend as I

# Sleep when idle (src/cli/idle.bend): the setting's parser, the create
# flag, the idle clock and the VM's forwards.

def T.check(+name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name)

def T.secs(m: Maybe<&2, U32>, +want: U32) -> Bool:
  match m:
    case Some{+v}:
      U32.is_eq(v, want)
    case None{}:
      False{}

def T.none(m: Maybe<&2, U32>) -> Bool:
  match m:
    case Some{v}:
      False{}
    case None{}:
      True{}

def T.act.of(a: I.Idle.Act) -> String:
  match a:
    case I.IdleStay{}:
      "stay"
    case I.IdleSleep{}:
      "sleep"
    case I.IdleWake{}:
      "wake"

def T.act(o: I.Idle.Out) -> String:
  T.act.of(I.Idle.Out.act(o))

def T.st.asleep(s: I.Idle.St) -> Bool:
  match s:
    case I.IdleSt{c, l, a}:
      a

def T.asleep(o: I.Idle.Out) -> Bool:
  T.st.asleep(I.Idle.Out.st(o))

def T.st.conns(s: I.Idle.St) -> U32:
  match s:
    case I.IdleSt{c, l, a}:
      c

def T.conns(o: I.Idle.Out) -> U32:
  T.st.conns(I.Idle.Out.st(o))

def main() -> IO(Unit):
  do IO<Unit>:
    T.check("a bare number is minutes", T.secs(I.Idle.parse("15"), 900))
    T.check("0 turns sleep off", T.secs(I.Idle.parse("0"), 0))
    T.check("seconds", T.secs(I.Idle.parse("45s"), 45))
    T.check("hours and minutes", T.secs(I.Idle.parse("1h30m"), 5400))
    T.check("a number after a unit needs a unit", T.none(I.Idle.parse("1h30")))
    T.check("words are not a duration", T.none(I.Idle.parse("ten")))
    T.check("a fraction is refused", T.none(I.Idle.parse("1.5h")))
    T.check("a unit alone is refused", T.none(I.Idle.parse("m")))
    T.check("empty is no value", T.none(I.Idle.parse("")))
    T.check("default is 15 minutes", T.secs(I.Idle.setting("", ""), 900))
    T.check("the flag wins over the environment", T.secs(I.Idle.setting("2m", "0"), 120))
    T.check("the environment applies without the flag", T.secs(I.Idle.setting("", "0"), 0))
    T.check("a recorded setting wins", U32.is_eq(I.Idle.secs("30s", "", "0"), 30))
    T.check("a bad setting falls back to the default", U32.is_eq(I.Idle.secs("", "x", ""), 900))
    T.check("flag value after the flag", String.eq(I.Idle.flag(["create", "a", "--idle-sleep", "2m"]), "2m"))
    T.check("flag value with =", String.eq(I.Idle.flag(["create", "a", "--idle-sleep=0"]), "0"))
    T.check("no flag", String.eq(I.Idle.flag(["create", "a"]), ""))
    T.check("has flag", I.Idle.has_flag(["create", "--idle-sleep", "1"]))
    T.check("drop flag and value", String.eq(String.join(I.Idle.drop_flag(["create", "--idle-sleep", "1", "a"]), " "), "create a"))
    T.check("drop flag=", String.eq(String.join(I.Idle.drop_flag(["create", "--idle-sleep=1", "a"]), " "), "create a"))
    T.check("tick before the limit stays", String.eq(T.act(I.Idle.step(60, I.IdleSt{0, 100, False{}}, I.IdleTick{159})), "stay"))
    T.check("tick at the limit sleeps", String.eq(T.act(I.Idle.step(60, I.IdleSt{0, 100, False{}}, I.IdleTick{160})), "sleep"))
    T.check("sleeping is recorded", T.asleep(I.Idle.step(60, I.IdleSt{0, 100, False{}}, I.IdleTick{160})))
    T.check("an open connection keeps it awake", String.eq(T.act(I.Idle.step(60, I.IdleSt{1, 100, False{}}, I.IdleTick{1000})), "stay"))
    T.check("limit 0 never sleeps", String.eq(T.act(I.Idle.step(0, I.IdleSt{0, 100, False{}}, I.IdleTick{100000})), "stay"))
    T.check("a clock that went back does not sleep", String.eq(T.act(I.Idle.step(60, I.IdleSt{0, 100, False{}}, I.IdleTick{10})), "stay"))
    T.check("a connection wakes a sleeping cluster", String.eq(T.act(I.Idle.step(60, I.IdleSt{0, 100, True{}}, I.IdleOpen{500})), "wake"))
    T.check("waking is recorded", Bool.not(T.asleep(I.Idle.step(60, I.IdleSt{0, 100, True{}}, I.IdleOpen{500}))))
    T.check("a connection to an awake cluster passes", String.eq(T.act(I.Idle.step(60, I.IdleSt{0, 100, False{}}, I.IdleOpen{500})), "stay"))
    T.check("a connection counts", U32.is_eq(T.conns(I.Idle.step(60, I.IdleSt{2, 100, False{}}, I.IdleOpen{500})), 3))
    T.check("a close counts down", U32.is_eq(T.conns(I.Idle.step(60, I.IdleSt{2, 100, False{}}, I.IdleClose{500})), 1))
    T.check("a stray close stays at 0", U32.is_eq(T.conns(I.Idle.step(60, I.IdleSt{0, 100, False{}}, I.IdleClose{500})), 0))
    T.check("standalone forwards", String.eq(I.Idle.forwards(False{}, 10001, 41234), "127.0.0.1:41234:6443,127.0.0.1:20001:8443"))
    T.check("classic forwards", String.eq(I.Idle.forwards(True{}, 10001, 41234), "127.0.0.1:41234:6443,127.0.0.1:14001:8132,127.0.0.1:17001:10250"))
    T.check("with_forward", String.eq(String.join(I.Idle.with_forward(["--mem", "1", "--forward", "x", "--lan", "y"], "z"), " "), "--mem 1 --forward z --lan y"))
    T.check("wake requests", String.eq(I.Idle.req_wake(True{}), "idle-wake-clock") && String.eq(I.Idle.req_wake(False{}), "idle-wake"))
