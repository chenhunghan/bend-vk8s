import Base

# The supervisor's decisions, pure. vk8s is PID 1 and keeps the cluster's
# daemons running as vcluster standalone's systemd unit does for vcluster
# (Restart=always, RestartSec=5s): a daemon that exits is started again
# 5 s later. Exits of processes it did not start (orphans reparented to
# PID 1, such as containerd shims) change nothing.

type Svc is Data:
  # pid 0: not running; due: when to start it (ms, the IO clock)
  Svc{name: String, prog: String, args: +List<String>, log: String, pid: U32, restarts: U32, due: Nat}

def Sup.restart_ms() -> Nat:
  5000n

# A new daemon, to be started now.
def Sup.svc(+name: String, +prog: String, args: +List<String>, +log: String, +now: Nat) -> Svc:
  Svc{name, prog, args, log, 0, 0, now}

def Sup.exited.match(hit: Bool, +n: String, +prog: String, args: +List<String>, +log: String, +p: U32, +r: U32,
  +due: Nat, +now: Nat) -> Svc:
  match hit:
    case True{}:
      Svc{n, prog, args, log, 0, (r + 1 : U32), Nat.add(now, Sup.restart_ms())}
    case False{}:
      Svc{n, prog, args, log, p, r, due}

def Sup.exited.one(s: Svc, +pid: U32, +now: Nat) -> Svc:
  match s:
    case Svc{+n, +prog, +args, +log, +p, +r, +due}:
      Sup.exited.match(Bool.and(U32.is_eq(p, pid), Bool.not(U32.is_eq(p, 0))), n, prog, args, log, p, r, due, now)

# Handle the exit of process `pid` at time `now`.
def Sup.exited(svcs: +List<Svc>, +pid: U32, +now: Nat) -> +List<Svc>:
  match svcs:
    case Nil{}:
      Nil{}
    case Con{s, rest}:
      Con{Sup.exited.one(s, pid, now), Sup.exited(rest, pid, now)}

# Is this daemon to be started at `now`?
def Sup.is_due(s: Svc, +now: Nat) -> Bool:
  match s:
    case Svc{+n, +prog, +args, +log, +p, +r, +due}:
      Bool.and(U32.is_eq(p, 0), Nat.is_le(due, now))

def Sup.next_due.pick(due: Bool, +s: Svc, later: Maybe<&2, Svc>) -> Maybe<&2, Svc>:
  match due:
    case True{}:
      Some{s}
    case False{}:
      later

# The first daemon due at `now`, if any (its name).
def Sup.next_due(svcs: +List<Svc>, +now: Nat) -> Maybe<&2, Svc>:
  match svcs:
    case Nil{}:
      None{}
    case Con{+s, rest}:
      Sup.next_due.pick(Sup.is_due(s, now), s, Sup.next_due(rest, now))

def Sup.started.match(hit: Bool, +n: String, +prog: String, args: +List<String>, +log: String, +p: U32, +r: U32,
  +due: Nat, +pid: U32) -> Svc:
  match hit:
    case True{}:
      Svc{n, prog, args, log, pid, r, due}
    case False{}:
      Svc{n, prog, args, log, p, r, due}

def Sup.started.one(s: Svc, +name: String, +pid: U32) -> Svc:
  match s:
    case Svc{+n, +prog, +args, +log, +p, +r, +due}:
      Sup.started.match(String.eq(n, name), n, prog, args, log, p, r, due, pid)

# Record that daemon `name` now runs as `pid`.
def Sup.started(svcs: +List<Svc>, +name: String, +pid: U32) -> +List<Svc>:
  match svcs:
    case Nil{}:
      Nil{}
    case Con{s, rest}:
      Con{Sup.started.one(s, name, pid), Sup.started(rest, name, pid)}

def Sup.failed.match(hit: Bool, +n: String, +prog: String, args: +List<String>, +log: String, +p: U32, +r: U32,
  +due: Nat, +now: Nat) -> Svc:
  match hit:
    case True{}:
      Svc{n, prog, args, log, 0, (r + 1 : U32), Nat.add(now, Sup.restart_ms())}
    case False{}:
      Svc{n, prog, args, log, p, r, due}

def Sup.failed.one(s: Svc, +name: String, +now: Nat) -> Svc:
  match s:
    case Svc{+n, +prog, +args, +log, +p, +r, +due}:
      Sup.failed.match(String.eq(n, name), n, prog, args, log, p, r, due, now)

# A failed start counts as an exit: try again after the restart delay.
def Sup.failed(svcs: +List<Svc>, +name: String, +now: Nat) -> +List<Svc>:
  match svcs:
    case Nil{}:
      Nil{}
    case Con{s, rest}:
      Con{Sup.failed.one(s, name, now), Sup.failed(rest, name, now)}

def Sup.name(s: Svc) -> String:
  match s:
    case Svc{n, prog, args, log, p, r, due}:
      n

def Sup.pid(s: Svc) -> U32:
  match s:
    case Svc{n, prog, args, log, p, r, due}:
      p

def Sup.keep.if(stopped: Bool, +p: U32) -> List<&2, U32>:
  match stopped:
    case True{}:
      Nil{}
    case False{}:
      [p]

# The pid of a daemon if it runs.
def Sup.keep(s: Svc) -> List<&2, U32>:
  match s:
    case Svc{n, prog, args, log, +p, r, due}:
      Sup.keep.if(U32.is_eq(p, 0), p)

# Shutdown (the guest's power button): the pids to stop, last started
# first, so the kubelet stops before the API server and the API server
# before its store (the reverse of the boot plan's order).
def Sup.stop_order(svcs: +List<Svc>) -> List<&2, U32>:
  match svcs:
    case Nil{}:
      Nil{}
    case Con{s, rest}:
      List.append(&2, U32, Sup.stop_order(rest), Sup.keep(s))

# Grace before the remaining processes are killed (systemd's default
# TimeoutStopSec is 90 s; vk8s waits less, as the VM powers off after).
def Sup.stop_grace_ms() -> Nat:
  20000n

def Sup.alive.one(s: Svc, +pid: U32) -> Bool:
  match s:
    case Svc{n, prog, args, log, p, r, due}:
      U32.is_eq(p, pid)

# Is process `pid` (not 0) one of the running daemons?
def Sup.alive(svcs: +List<Svc>, +pid: U32) -> Bool:
  match svcs:
    case Nil{}:
      False{}
    case Con{s, rest}:
      Bool.or(Sup.alive.one(s, pid), Sup.alive(rest, pid))

# Each daemon gets this long to exit before the next one is told to stop.
def Sup.stop_each_ms() -> Nat:
  10000n
