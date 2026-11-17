import Base

# Sleep when idle (docs/GOAL.md section 10): a cluster with no API traffic
# through its host API forward for a while pauses with the pause machinery
# (bend-vmm pause for VMs, the cgroup freezer for container nodes) and
# resumes on the next connection to the forward, which waits until the
# API answers. Every decision is here; host/idle_proxy.bend moves bytes.
#
# The setting is how long a cluster may be idle, in seconds: 0 turns sleep
# off. It comes from `vk8s create --idle-sleep D`, else VK8S_IDLE_SLEEP,
# else 15 minutes. D is a whole number of minutes ("15"), or a duration in
# Go's time.ParseDuration form over whole hours, minutes and seconds
# ("90s", "1h30m"), as vcluster's sleep.auto.afterInactivity is written.

# Configuration
# -------------

# 15 minutes (docs/GOAL.md section 10).
def Idle.default_secs() -> U32:
  900

# The environment variable and the create flag.
def Idle.env_name() -> String:
  "VK8S_IDLE_SLEEP"

def Idle.flag_name() -> String:
  "--idle-sleep"

# The parser's state: the number being read, the total so far, whether
# digits are pending, whether a unit was read, whether the text is bad.
type Idle.Rd is Data:
  IdleRd{num: U32, tot: U32, digits: Bool, units: Bool, bad: Bool}

def Idle.unit.of(h: Bool, m: Bool, s: Bool) -> U32:
  match h m s:
    case True{} _ _:
      3600
    case False{} True{} _:
      60
    case False{} False{} True{}:
      1
    case False{} False{} False{}:
      0

# Seconds per unit: h, m, s; 0 for any other character.
def Idle.unit(c: Char) -> U32:
  match c:
    case Chr{+u}:
      Idle.unit.of(U32.is_eq(u, 104), U32.is_eq(u, 109), U32.is_eq(u, 115))

def Idle.feed.unit.go(none: Bool, digits: Bool, +mult: U32, +num: U32, +tot: U32, +units: Bool, +bad: Bool) -> Idle.Rd:
  match none digits:
    case True{} _:
      IdleRd{num, tot, digits, units, True{}}
    case False{} False{}:
      IdleRd{num, tot, False{}, units, True{}}
    case False{} True{}:
      IdleRd{0, (tot + (num * mult : U32) : U32), False{}, True{}, bad}

def Idle.feed.unit(+mult: U32, r: Idle.Rd) -> Idle.Rd:
  match r:
    case IdleRd{+num, +tot, +digits, +units, +bad}:
      Idle.feed.unit.go(U32.is_eq(mult, 0), digits, mult, num, tot, units, bad)

def Idle.feed.digit(+u: U32, r: Idle.Rd) -> Idle.Rd:
  match r:
    case IdleRd{+num, +tot, +digits, +units, +bad}:
      IdleRd{((num * 10 : U32) + (u - 48 : U32) : U32), tot, True{}, units, bad}

def Idle.feed.go(digit: Bool, +c: Char, r: Idle.Rd) -> Idle.Rd:
  match digit:
    case True{}:
      Idle.feed.digit(Char.to_u32(c), r)
    case False{}:
      Idle.feed.unit(Idle.unit(c), r)

def Idle.feed(+c: Char, r: Idle.Rd) -> Idle.Rd:
  Idle.feed.go(Char.is_digit(c), c, r)

# The end of the text: a bare number is minutes; after a unit, a number
# needs its own unit (Go: "missing unit in duration"); empty is no value.
def Idle.finish.go(bad: Bool, digits: Bool, units: Bool, +num: U32, +tot: U32) -> Maybe<&2, U32>:
  match bad digits units:
    case True{} _ _:
      None{}
    case False{} True{} False{}:
      Some{(num * 60 : U32)}
    case False{} True{} True{}:
      None{}
    case False{} False{} True{}:
      Some{tot}
    case False{} False{} False{}:
      None{}

def Idle.finish(r: Idle.Rd) -> Maybe<&2, U32>:
  match r:
    case IdleRd{+num, +tot, +digits, +units, +bad}:
      Idle.finish.go(bad, digits, units, num, tot)

def Idle.read(s: String, r: Idle.Rd) -> Maybe<&2, U32>:
  match s:
    case SNil{}:
      Idle.finish(r)
    case SCon{+c, t}:
      Idle.read(t, Idle.feed(c, r))

# A setting's seconds, or None{} when the text is empty or not a duration.
def Idle.parse(s: String) -> Maybe<&2, U32>:
  Idle.read(s, IdleRd{0, 0, False{}, False{}, False{}})

def Idle.pick(empty: Bool, +s: String, more: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match empty:
    case True{}:
      more
    case False{}:
      Idle.parse(s)

# The flag's value, else the environment's, else the default; None{} when
# the one that applies is not a duration.
def Idle.setting(+flag: String, +env: String) -> Maybe<&2, U32>:
  Idle.pick(String.is_empty(flag), flag, Idle.pick(String.is_empty(env), env, Some{Idle.default_secs()}))

def Idle.secs.go(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{+v}:
      v
    case None{}:
      Idle.default_secs()

# What a cluster's cluster.env records (IDLE_SLEEP=<seconds>), else the
# setting, else the default.
def Idle.secs(+recorded: String, +flag: String, +env: String) -> U32:
  Idle.secs.go(Idle.pick(String.is_empty(recorded), recorded, Idle.setting(flag, env)))

def Idle.env_line(+secs: U32) -> String:
  "IDLE_SLEEP=" ++ U32.show(secs) ++ "s\n"

# The create flag: `--idle-sleep D` or `--idle-sleep=D`. `prev` says the
# argument before was the bare flag.
def Idle.flag.pick(prev: Bool, eq: Bool, +a: String, more: String) -> String:
  match prev eq:
    case True{} _:
      a
    case False{} True{}:
      String.drop(a, 13n)
    case False{} False{}:
      more

def Idle.flag.go(args: +List<String>, prev: Bool) -> String:
  match args:
    case Nil{}:
      ""
    case Con{+a, rest}:
      Idle.flag.pick(prev, String.starts_with(a, "--idle-sleep="), a, Idle.flag.go(rest, String.eq(a, "--idle-sleep")))

# The flag's value in argv, "" when it is absent.
def Idle.flag(args: +List<String>) -> String:
  Idle.flag.go(args, False{})

def Idle.has_flag(args: +List<String>) -> Bool:
  match args:
    case Nil{}:
      False{}
    case Con{+a, rest}:
      String.starts_with(a, "--idle-sleep=") || String.eq(a, "--idle-sleep") || Idle.has_flag(rest)

def Idle.drop.pick(skip: Bool, +a: String, more: +List<String>) -> +List<String>:
  match skip:
    case True{}:
      more
    case False{}:
      Con{a, more}

def Idle.drop.go(args: +List<String>, prev: Bool) -> +List<String>:
  match args:
    case Nil{}:
      Nil{}
    case Con{+a, rest}:
      Idle.drop.pick(prev || String.starts_with(a, "--idle-sleep=") || String.eq(a, "--idle-sleep"), a,
        Idle.drop.go(rest, String.eq(a, "--idle-sleep")))

# argv without the flag and its value.
def Idle.drop_flag(args: +List<String>) -> +List<String>:
  Idle.drop.go(args, False{})

# The idle clock
# --------------

# The proxy's state: the open connections, when the last one opened or
# closed (seconds), and whether the cluster sleeps.
type Idle.St is Data:
  IdleSt{conns: U32, last: U32, asleep: Bool}

# What happens: a connection opens or closes, or the clock ticks; each at
# a time in seconds.
type Idle.Ev is Data:
  IdleOpen{now: U32}
  IdleClose{now: U32}
  IdleTick{now: U32}

# What the proxy does: nothing more, pause the cluster, or resume it before
# it forwards the connection that opened.
type Idle.Act is Data:
  IdleStay{}
  IdleSleep{}
  IdleWake{}

type Idle.Out is Data:
  IdleOut{st: Idle.St, act: Idle.Act}

def Idle.Out.act(o: Idle.Out) -> Idle.Act:
  match o:
    case IdleOut{s, a}:
      a

def Idle.Out.st(o: Idle.Out) -> Idle.St:
  match o:
    case IdleOut{s, a}:
      s

def Idle.start(+now: U32) -> Idle.St:
  IdleSt{0, now, False{}}

def Idle.dec.go(zero: Bool, +c: U32) -> U32:
  match zero:
    case True{}:
      0
    case False{}:
      (c - 1 : U32)

def Idle.dec(+c: U32) -> U32:
  Idle.dec.go(U32.is_eq(c, 0), c)

def Idle.open.go(asleep: Bool, +c: U32, +now: U32) -> Idle.Out:
  match asleep:
    case True{}:
      IdleOut{IdleSt{(c + 1 : U32), now, False{}}, IdleWake{}}
    case False{}:
      IdleOut{IdleSt{(c + 1 : U32), now, False{}}, IdleStay{}}

# A tick: a sleeping cluster stays asleep; sleep off (limit 0) or an open
# connection keeps it awake; a clock that went back restarts the count
# from now; past the limit with no connection, it sleeps.
def Idle.tick.go(asleep: Bool, off: Bool, idle: Bool, back: Bool, due: Bool, +c: U32, +last: U32, +now: U32) -> Idle.Out:
  match asleep off idle back due:
    case True{} _ _ _ _:
      IdleOut{IdleSt{c, last, True{}}, IdleStay{}}
    case False{} True{} _ _ _:
      IdleOut{IdleSt{c, last, False{}}, IdleStay{}}
    case False{} False{} False{} _ _:
      IdleOut{IdleSt{c, last, False{}}, IdleStay{}}
    case False{} False{} True{} True{} _:
      IdleOut{IdleSt{c, now, False{}}, IdleStay{}}
    case False{} False{} True{} False{} True{}:
      IdleOut{IdleSt{c, now, True{}}, IdleSleep{}}
    case False{} False{} True{} False{} False{}:
      IdleOut{IdleSt{c, last, False{}}, IdleStay{}}

def Idle.tick(+limit: U32, +c: U32, +last: U32, +asleep: Bool, +now: U32) -> Idle.Out:
  Idle.tick.go(asleep, U32.is_eq(limit, 0), U32.is_eq(c, 0), U32.is_lt(now, last), U32.is_ge((now - last : U32), limit), c, last, now)

def Idle.step.ev(+limit: U32, +c: U32, +last: U32, +asleep: Bool, ev: Idle.Ev) -> Idle.Out:
  match ev:
    case IdleOpen{+now}:
      Idle.open.go(asleep, c, now)
    case IdleClose{+now}:
      IdleOut{IdleSt{Idle.dec(c), now, asleep}, IdleStay{}}
    case IdleTick{+now}:
      Idle.tick(limit, c, last, asleep, now)

# The next state and action, for a limit in seconds (0: sleep off).
def Idle.step(+limit: U32, st: Idle.St, ev: Idle.Ev) -> Idle.Out:
  match st:
    case IdleSt{+c, +last, +asleep}:
      Idle.step.ev(limit, c, last, asleep, ev)

# How often the proxy ticks when no connection comes (milliseconds).
def Idle.tick_ms() -> U32:
  1000

# The guest side
# --------------

# The requests the proxy sends the control plane's PID 1 (host/init.bend,
# src/guest/plan.bend Plan.request): before the pause, and after the
# resume (with the VM's clock set from its RTC first, when the node is a
# VM whose clock stopped while it was paused).
def Idle.req_sleep() -> String:
  "idle-sleep"

def Idle.req_wake(vm: Bool) -> String:
  match vm:
    case True{}:
      "idle-wake-clock"
    case False{}:
      "idle-wake"

# The private loopback port a VM forwards its 6443 to when the idle proxy
# holds the cluster's port: 22000 plus the API port's offset in vcluster's
# 10000..12999, clear of classic's 13000.. and 16000.. ranges and the
# join server's 19000.. (src/cli/cli.bend Cli.join_port).
def Idle.inner_port(+port: U32) -> U32:
  (22000 + (port % 3000 : U32) : U32)

# The VM's port forwards with the API on a private loopback port (inner),
# which the idle proxy relays from the cluster's port; the other forwards
# keep the ports derived from the cluster's port.
def Idle.forwards(classic: Bool, +port: U32, +inner: U32) -> String:
  match classic:
    case True{}:
      "127.0.0.1:" ++ U32.show(inner) ++ ":6443,127.0.0.1:" ++ U32.show((13000 + (port % 3000 : U32) : U32)) ++ ":8132,127.0.0.1:"
        ++ U32.show((16000 + (port % 3000 : U32) : U32)) ++ ":10250"
    case False{}:
      "127.0.0.1:" ++ U32.show(inner) ++ ":6443,127.0.0.1:" ++ U32.show((19000 + (port % 3000 : U32) : U32)) ++ ":8443"

def Idle.with_forward.pick(prev: Bool, +f: String, +a: String) -> String:
  match prev:
    case True{}:
      f
    case False{}:
      a

def Idle.with_forward.go(flags: +List<String>, +f: String, prev: Bool) -> +List<String>:
  match flags:
    case Nil{}:
      Nil{}
    case Con{+a, rest}:
      Con{Idle.with_forward.pick(prev, f, a), Idle.with_forward.go(rest, f, String.eq(a, "--forward"))}

# bend-vmm flags with the value of --forward replaced by f.
def Idle.with_forward(flags: +List<String>, +f: String) -> +List<String>:
  Idle.with_forward.go(flags, f, False{})
