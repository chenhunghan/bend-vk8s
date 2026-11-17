import Base
import ../src/cli/idle.bend as I

# Spec for src/cli/idle.bend: sleep when idle (docs/GOAL.md section 10).

# Proposed: the setting's durations. Each concrete case is one case of Go's
# src/time/time_test.go (parseDurationTests and parseDurationErrorTests),
# which vcluster's sleep.auto.afterInactivity follows (config.Duration is
# read with time.ParseDuration), with Go's expected value in seconds.
# vk8s reads whole hours, minutes and seconds only.

# {"0", 0}
law idle.parse.go_zero:
  {I.Idle.parse("0") == Some{0} : Maybe<&2, U32>}

# {"5s", 5 * Second}
law idle.parse.go_5s:
  {I.Idle.parse("5s") == Some{5} : Maybe<&2, U32>}

# {"1478s", 1478 * Second}
law idle.parse.go_1478s:
  {I.Idle.parse("1478s") == Some{1478} : Maybe<&2, U32>}

# {"15m", 15 * Minute}
law idle.parse.go_15m:
  {I.Idle.parse("15m") == Some{900} : Maybe<&2, U32>}

# {"16h", 16 * Hour}
law idle.parse.go_16h:
  {I.Idle.parse("16h") == Some{57600} : Maybe<&2, U32>}

# {"3h30m", 3*Hour + 30*Minute}
law idle.parse.go_3h30m:
  {I.Idle.parse("3h30m") == Some{12600} : Maybe<&2, U32>}

# parseDurationErrorTests: "", "s", "1d", "."
law idle.parse.go_err_empty:
  {I.Idle.parse("") == None{} : Maybe<&2, U32>}

law idle.parse.go_err_unit_alone:
  {I.Idle.parse("s") == None{} : Maybe<&2, U32>}

law idle.parse.go_err_days:
  {I.Idle.parse("1d") == None{} : Maybe<&2, U32>}

law idle.parse.go_err_dot:
  {I.Idle.parse(".") == None{} : Maybe<&2, U32>}

# Proposed: vk8s policy (docs/GOAL.md section 10, the user's brief of
# 2026-11-17), not vcluster's: a bare number is minutes (Go refuses "3"),
# the default is 15 minutes, 0 turns sleep off, and the create flag wins
# over VK8S_IDLE_SLEEP.
law idle.parse.bare_minutes:
  {I.Idle.parse("15") == Some{900} : Maybe<&2, U32>}

law idle.setting.default:
  {I.Idle.setting("", "") == Some{900} : Maybe<&2, U32>}

law idle.setting.env_off:
  {I.Idle.setting("", "0") == Some{0} : Maybe<&2, U32>}

law idle.setting.flag_wins:
  for +env: String
  {I.Idle.setting("2m", env) == Some{120} : Maybe<&2, U32>}

law idle.flag.value:
  {I.Idle.flag(["create", "demo", "--idle-sleep", "0"]) == "0" : String}

law idle.flag.value_eq:
  {I.Idle.flag(["create", "demo", "--idle-sleep=90s"]) == "90s" : String}

law idle.flag.dropped:
  {I.Idle.drop_flag(["create", "demo", "--idle-sleep", "0", "--nodes", "1"]) == ["create", "demo", "--nodes", "1"] : +List<String>}

# Proposed: the idle clock (vk8s design). Sleep off never sleeps.
law idle.off_never_sleeps:
  for +st: I.Idle.St
  for +now: U32
  {I.Idle.Out.act(I.Idle.step(0, st, I.IdleTick{now})) == I.IdleStay{} : I.Idle.Act}

# An open connection (a watch, an exec, a port-forward) keeps it awake.
law idle.busy_never_sleeps:
  for +limit: U32
  for +c: U32
  for +last: U32
  for +now: U32
  for h: {U32.is_eq(c, 0) == False{} : Bool}
  {I.Idle.Out.act(I.Idle.step(limit, I.IdleSt{c, last, False{}}, I.IdleTick{now})) == I.IdleStay{} : I.Idle.Act}

# A sleeping cluster is not paused twice.
law idle.asleep_stays:
  for +limit: U32
  for +c: U32
  for +last: U32
  for +now: U32
  {I.Idle.step(limit, I.IdleSt{c, last, True{}}, I.IdleTick{now}) == I.IdleOut{I.IdleSt{c, last, True{}}, I.IdleStay{}} : I.Idle.Out}

# Idle for the limit with no connection: it sleeps.
law idle.due_sleeps:
  for +limit: U32
  for +last: U32
  for +now: U32
  for h1: {U32.is_eq(limit, 0) == False{} : Bool}
  for h2: {U32.is_lt(now, last) == False{} : Bool}
  for h3: {U32.is_ge((now - last : U32), limit) == True{} : Bool}
  {I.Idle.step(limit, I.IdleSt{0, last, False{}}, I.IdleTick{now}) == I.IdleOut{I.IdleSt{0, now, True{}}, I.IdleSleep{}} : I.Idle.Out}

# Not yet idle for the limit: it stays awake.
law idle.not_due_stays:
  for +limit: U32
  for +c: U32
  for +last: U32
  for +now: U32
  for h: {U32.is_ge((now - last : U32), limit) == False{} : Bool}
  {I.Idle.Out.act(I.Idle.step(limit, I.IdleSt{c, last, False{}}, I.IdleTick{now})) == I.IdleStay{} : I.Idle.Act}

# Clock jump: a clock that went back never puts the cluster to sleep; the
# count starts again from now.
law idle.clock_back:
  for +limit: U32
  for +c: U32
  for +last: U32
  for +now: U32
  for h: {U32.is_lt(now, last) == True{} : Bool}
  {I.Idle.Out.act(I.Idle.step(limit, I.IdleSt{c, last, False{}}, I.IdleTick{now})) == I.IdleStay{} : I.Idle.Act}

# The next connection to a sleeping cluster wakes it before it is
# forwarded, and counts.
law idle.open_wakes:
  for +limit: U32
  for +c: U32
  for +last: U32
  for +now: U32
  {I.Idle.step(limit, I.IdleSt{c, last, True{}}, I.IdleOpen{now}) == I.IdleOut{I.IdleSt{(c + 1 : U32), now, False{}}, I.IdleWake{}} : I.Idle.Out}

# A connection to an awake cluster never resumes it.
law idle.open_awake_passes:
  for +limit: U32
  for +c: U32
  for +last: U32
  for +now: U32
  {I.Idle.step(limit, I.IdleSt{c, last, False{}}, I.IdleOpen{now}) == I.IdleOut{I.IdleSt{(c + 1 : U32), now, False{}}, I.IdleStay{}} : I.Idle.Out}

# A closed connection restarts the count.
law idle.close_restarts:
  for +limit: U32
  for +c: U32
  for +last: U32
  for +a: Bool
  for +now: U32
  {I.Idle.step(limit, I.IdleSt{c, last, a}, I.IdleClose{now}) == I.IdleOut{I.IdleSt{I.Idle.dec(c), now, a}, I.IdleStay{}} : I.Idle.Out}

# Wake: a VM's clock is set from its RTC before the controllers resume
# (bend-vmm's virtual timer stops while the VM is paused on macOS); a
# container shares the host's clock.
law idle.wake_vm_sets_clock:
  {I.Idle.req_wake(True{}) == "idle-wake-clock" : String}

law idle.wake_container:
  {I.Idle.req_wake(False{}) == "idle-wake" : String}

# The VM forwards only the API to the private port; the derived ports are
# the cluster port's (laws/cli.bend cli.forwards.standalone and
# cli.classic_forwards.on).
law idle.forwards.standalone:
  {I.Idle.forwards(False{}, 10001, 40000) == "127.0.0.1:40000:6443,127.0.0.1:20001:8443" : String}

law idle.forwards.classic:
  {I.Idle.forwards(True{}, 10001, 40000) == "127.0.0.1:40000:6443,127.0.0.1:14001:8132,127.0.0.1:17001:10250" : String}

# The private API port: 22000 plus the cluster port's offset, as the join
# server's 19000.. (cli.join_port).
law idle.inner_port:
  {I.Idle.inner_port(10001) == 23001 : U32}
