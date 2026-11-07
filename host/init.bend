import Base
import ../src/guest/plan.bend as P
import ../src/guest/supervise.bend as S
import ./kubelet_proxy.bend as KP

# vk8s as PID 1 in the cluster VM. It runs the boot plan of
# src/guest/plan.bend, then supervises the daemons it started (restart
# 5 s after an exit, src/guest/supervise.bend) and reaps every orphan.
# Every program starts through the Proc effects: Base's Process.run waits
# on its own child, which this reaper would take from it.

def Proc.start(prog: String, args: List<String>, log: String) -> IO(Result<&1, &1, U32 & String, U32>):
  import "./effs/proc.c"
  import "./effs/proc.js"

def Proc.reap() -> IO(List<(U32 & U32)>):
  import "./effs/proc.c"
  import "./effs/proc.js"

# kill(2); pid 4294967295 is -1. Returns 0 or the errno.
def Proc.signal(pid: U32, sig: U32) -> IO(U32):
  import "./effs/sys.c"
  import "./effs/sys.js"

# KEY_POWER presses since the last call (bend-vmm's `powerdown`).
def Sys.power() -> IO(U32):
  import "./effs/sys.c"
  import "./effs/sys.js"

# sync(2), then power the VM off.
def Sys.poweroff() -> IO(U32):
  import "./effs/sys.c"
  import "./effs/sys.js"

# The state threaded through the boot: whether every step so far
# succeeded, and the daemons.
type St is Data:
  St{ok: Bool, svcs: +List<S.Svc>}

def Init.say(+s: String) -> IO(Unit):
  IO.print("vk8s-init: " ++ s)

def Init.lin(xs: +List<String>) -> List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      Con{x, Init.lin(t)}

# Reaped exits folded into the daemons, and the awaited pid's status if seen.
type Fed is Data:
  Fed{status: Maybe<&2, U32>, svcs: +List<S.Svc>}

def Init.feed.hit(hit: Bool, st: Maybe<&2, U32>, svcs: +List<S.Svc>, +pid: U32, +code: U32, +now: Nat) -> Fed:
  match hit:
    case True{}:
      Fed{Some{code}, svcs}
    case False{}:
      Fed{st, S.Sup.exited(svcs, pid, now)}

def Init.feed.one(+target: U32, +pid: U32, +code: U32, +now: Nat, f: Fed) -> Fed:
  match f:
    case Fed{st, svcs}:
      Init.feed.hit(U32.is_eq(pid, target), st, svcs, pid, code, now)

def Init.feed(exits: List<(U32 & U32)>, +target: U32, +now: Nat, f: Fed) -> Fed:
  match exits:
    case Nil{}:
      f
    case Con{(pid, code), rest}:
      Init.feed(rest, target, now, Init.feed.one(target, pid, code, now, f))

def Init.exits_noted(exits: List<(U32 & U32)>, +now: Nat, svcs: +List<S.Svc>) -> +List<S.Svc>:
  match exits:
    case Nil{}:
      svcs
    case Con{(pid, code), rest}:
      Init.exits_noted(rest, now, S.Sup.exited(svcs, pid, now))

def Init.sleep_then(next: IO(Fed)) -> IO(Fed):
  do IO<Fed>:
    IO.sleep(20)
    next

def Init.wait.go(st: Maybe<&2, U32>, svcs: +List<S.Svc>, again: IO(Fed)) -> IO(Fed):
  match st:
    case Some{c}:
      IO.pure(Fed, Fed{Some{c}, svcs})
    case None{}:
      again

def Fed.status(f: Fed) -> Maybe<&2, U32>:
  match f:
    case Fed{st, svcs}:
      st

def Fed.svcs(f: Fed) -> +List<S.Svc>:
  match f:
    case Fed{st, svcs}:
      svcs

# Wait for `pid` to exit (n polls, 20 ms apart), noting other exits.
def Init.wait(n: Nat, +pid: U32, svcs: +List<S.Svc>) -> IO(Fed):
  match n:
    case 0n:
      IO.pure(Fed, Fed{None{}, svcs})
    case 1n+p:
      do IO<Fed>:
        exits : List<(U32 & U32)> <- Proc.reap()
        +now : Nat <- IO.now()
        +f : Fed = Init.feed(exits, pid, now, Fed{None{}, svcs})
        Init.wait.go(Fed.status(f), Fed.svcs(f), Init.sleep_then(Init.wait(p, pid, Fed.svcs(f))))

def Init.start_pid(r: Result<&1, &1, U32 & String, U32>) -> IO(U32):
  match r:
    case Fail{(code, msg)}:
      do IO<U32>:
        Init.say("cannot start: " ++ msg ++ " (errno " ++ U32.show(code) ++ ")")
        return 0
    case Done{pid}:
      IO.pure(U32, pid)

def Init.wait_fuel(none: Bool) -> Nat:
  match none:
    case True{}:
      0n
    case False{}:
      30000n

def Init.started(r: Result<&1, &1, U32 & String, U32>) -> U32:
  match r:
    case Fail{e}:
      0
    case Done{pid}:
      pid

def Init.status_ok(st: Maybe<&2, U32>) -> Bool:
  match st:
    case Some{c}:
      U32.is_eq(c, 0)
    case None{}:
      False{}

def Init.fed_st(ok: Bool, f: Fed) -> St:
  match f:
    case Fed{st, svcs}:
      St{Bool.and(ok, Init.status_ok(st)), svcs}

def St.ok(s: St) -> Bool:
  match s:
    case St{ok, svcs}:
      ok

def St.svcs(s: St) -> +List<S.Svc>:
  match s:
    case St{ok, svcs}:
      svcs

def St.with_ok(s: St, ok: Bool) -> St:
  match s:
    case St{o, svcs}:
      St{Bool.and(o, ok), svcs}

def Init.report(ok: Bool, +what: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      Init.say("FAILED: " ++ what)

# Run a program to completion (console output; at most 10 minutes).
def Init.run(+prog: String, +args: +List<String>, s: St) -> IO(St):
  match s:
    case St{ok, svcs}:
      do IO<St>:
        r : Result<&1, &1, U32 & String, U32> <- Proc.start(prog, Init.lin(args), "")
        +pid : U32 <- Init.start_pid(r)
        f : Fed <- Init.wait(Init.wait_fuel(U32.is_eq(pid, 0)), pid, svcs)
        +st : St = Init.fed_st(Bool.and(ok, Bool.not(U32.is_eq(pid, 0))), f)
        Init.report(St.ok(st), prog ++ P.Plan.sh_words(args))
        return st

def Init.bb(args: +List<String>, s: St) -> IO(St):
  Init.run("/bin/busybox", args, s)

def Init.again.go(first: Bool, r: U32) -> String:
  match first:
    case True{}:
      ""
    case False{}:
      " (restart " ++ U32.show(r) ++ ")"

def Init.again(+r: U32) -> String:
  Init.again.go(U32.is_eq(r, 0), r)

def Init.start_svc.done(ok: Bool, +pid: U32, +name: String, +now: Nat, svcs: +List<S.Svc>) -> +List<S.Svc>:
  match ok:
    case False{}:
      S.Sup.failed(svcs, name, now)
    case True{}:
      S.Sup.started(svcs, name, pid)

# Start daemon c of the table.
def Init.start_svc(c: S.Svc, svcs: +List<S.Svc>, +now: Nat) -> IO(+List<S.Svc>):
  match c:
    case S.Svc{+name, +prog, +args, +log, p, r, due}:
      do IO<+List<S.Svc>>:
        Init.say("start " ++ name ++ Init.again(r))
        res : Result<&1, &1, U32 & String, U32> <- Proc.start(prog, Init.lin(args), log)
        +pid : U32 = Init.started(res)
        return Init.start_svc.done(Bool.not(U32.is_eq(pid, 0)), pid, name, now, svcs)

def Init.start_due.go(m: Maybe<&2, S.Svc>, again: +List<S.Svc> -> IO(+List<S.Svc>), svcs: +List<S.Svc>, +now: Nat) ->
  IO(+List<S.Svc>):
  match m:
    case None{}:
      IO.pure(+List<S.Svc>, svcs)
    case Some{c}:
      do IO<+List<S.Svc>>:
        +s2 : +List<S.Svc> <- Init.start_svc(c, svcs, now)
        again(s2)

# Start every daemon that is due (at most n).
def Init.start_due(n: Nat, +svcs: +List<S.Svc>, +now: Nat) -> IO(+List<S.Svc>):
  match n:
    case 0n:
      IO.pure(+List<S.Svc>, svcs)
    case 1n+p:
      Init.start_due.go(S.Sup.next_due(svcs, now), s => Init.start_due(p, s, now), svcs, now)

def Init.add_daemon(+name: String, +prog: String, args: +List<String>, s: St) -> IO(St):
  match s:
    case St{ok, svcs}:
      do IO<St>:
        +now : Nat <- IO.now()
        +log : String = P.Plan.host_dir() ++ "/logs/" ++ name ++ ".log"
        +s2 : +List<S.Svc> = List.append(&2, S.Svc, svcs, [S.Sup.svc(name, prog, args, log, now)])
        +s3 : +List<S.Svc> <- Init.start_due(U32.to_nat(64), s2, now)
        return St{ok, s3}

def Init.write.close(p: File & Result<&1, &1, U32 & String, Unit>) -> IO(Bool):
  match p:
    case (f, Done{u}):
      do IO<Bool>:
        File.close(f)
        return True{}
    case (f, Fail{e}):
      do IO<Bool>:
        File.close(f)
        return False{}

def Init.write.go(r: Result<&1, &1, U32 & String, File>, +text: String) -> IO(Bool):
  match r:
    case Fail{e}:
      IO.pure(Bool, False{})
    case Done{f}:
      do IO<Bool>:
        p : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, text)
        Init.write.close(p)

def Init.write(+path: String, +text: String, s: St) -> IO(St):
  do IO<St>:
    +s1 : St <- Init.bb(["sh", "-c", "mkdir -p \"$(dirname " ++ P.Plan.sh_quote(path) ++ ")\""], s)
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "w")
    +ok : Bool <- Init.write.go(r, text)
    Init.report(ok, "write " ++ path)
    return St.with_ok(s1, ok)

def Init.read.close(p: File & Result<&1, &1, U32 & String, String>) -> IO(String):
  match p:
    case (f, Done{s}):
      do IO<String>:
        File.close(f)
        return s
    case (f, Fail{e}):
      do IO<String>:
        File.close(f)
        return ""

def Init.read.go(r: Result<&1, &1, U32 & String, File>) -> IO(String):
  match r:
    case Fail{e}:
      IO.pure(String, "")
    case Done{f}:
      do IO<String>:
        p : File & Result<&1, &1, U32 & String, String> <- File.read(f, 1048576)
        Init.read.close(p)

def Init.read(+path: String) -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    Init.read.go(r)

def Init.insmod(empty: Bool, +m: String, s: St) -> IO(St):
  match empty:
    case True{}:
      IO.pure(St, s)
    case False{}:
      Init.bb(["insmod", String.trim(m)], s)

def Init.insmods(ms: List<&2, String>, s: St) -> IO(St):
  match ms:
    case Nil{}:
      IO.pure(St, s)
    case Con{+m, t}:
      do IO<St>:
        +s2 : St <- Init.insmod(String.is_empty(String.trim(m)), m, s)
        Init.insmods(t, s2)

def Init.connected(r: Result<&1, &1, U32 & String, Socket>) -> IO(Bool):
  match r:
    case Fail{e}:
      IO.pure(Bool, False{})
    case Done{sk}:
      do IO<Bool>:
        Socket.close(sk)
        return True{}

def Init.or_retry(ok: Bool, retry: IO(Bool)) -> IO(Bool):
  match ok:
    case True{}:
      IO.pure(Bool, True{})
    case False{}:
      retry

def Init.pause_then(next: IO(Bool)) -> IO(Bool):
  do IO<Bool>:
    IO.sleep(250)
    next

def Init.wait_tcp(n: Nat, +host: String, +port: U32) -> IO(Bool):
  match n:
    case 0n:
      IO.pure(Bool, False{})
    case 1n+p:
      do IO<Bool>:
        r : Result<&1, &1, U32 & String, Socket> <- TCP.connect(host, port)
        ok : Bool <- Init.connected(r)
        Init.or_retry(ok, Init.pause_then(Init.wait_tcp(p, host, port)))

# A path exists: it opens, or (a socket) refuses with ENXIO.
def Init.exists_path(r: Result<&1, &1, U32 & String, File>) -> IO(Bool):
  match r:
    case Fail{(code, msg)}:
      IO.pure(Bool, U32.is_eq(code, 6))
    case Done{f}:
      do IO<Bool>:
        File.close(f)
        return True{}

def Init.wait_file(n: Nat, +path: String) -> IO(Bool):
  match n:
    case 0n:
      IO.pure(Bool, False{})
    case 1n+p:
      do IO<Bool>:
        r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
        ok : Bool <- Init.exists_path(r)
        Init.or_retry(ok, Init.pause_then(Init.wait_file(p, path)))

def Init.tries(ms: U32) -> Nat:
  U32.to_nat((ms / 250 : U32))

def Init.waited(+ok: Bool, +what: String, s: St) -> IO(St):
  do IO<St>:
    Init.report(ok, "timed out waiting for " ++ what)
    return St.with_ok(s, ok)

def Init.signal_all(pids: List<&2, U32>, +sig: U32) -> IO(Unit):
  match pids:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{pid, rest}:
      do IO<Unit>:
        e : U32 <- Proc.signal(pid, sig)
        Init.signal_all(rest, sig)

def Init.step(step: P.Step, +s: St) -> IO(St):
  match step:
    case P.Mount{+fs, +src, +dst, +opts}:
      do IO<St>:
        +s1 : St <- Init.bb(["mkdir", "-p", dst], s)
        Init.bb(["mount", "-t", fs, "-o", opts, src, dst], s1)
    case P.Write{+path, +text}:
      Init.write(path, text, s)
    case P.Run{+prog, +args}:
      do IO<St>:
        Init.say("run " ++ prog ++ P.Plan.sh_words(args))
        Init.run(prog, args, s)
    case P.Daemon{+name, +prog, +args}:
      do IO<St>:
        +s1 : St <- Init.bb(["mkdir", "-p", P.Plan.host_dir() ++ "/logs"], s)
        Init.add_daemon(name, prog, args, s1)
    case P.Spawn{+name, +prog, +args}:
      do IO<St>:
        Init.say("spawn " ++ name)
        +s1 : St <- Init.bb(["mkdir", "-p", P.Plan.host_dir() ++ "/logs"], s)
        r : Result<&1, &1, U32 & String, U32> <- Proc.start(prog, Init.lin(args), P.Plan.host_dir() ++ "/logs/" ++ name ++ ".log")
        +pid : U32 <- Init.start_pid(r)
        return St.with_ok(s1, Bool.not(U32.is_eq(pid, 0)))
    case P.WaitTcp{+host, +port, +ms}:
      do IO<St>:
        ok : Bool <- Init.wait_tcp(Init.tries(ms), host, port)
        Init.waited(ok, host ++ ":" ++ U32.show(port), s)
    case P.WaitFile{+path, +ms}:
      do IO<St>:
        ok : Bool <- Init.wait_file(Init.tries(ms), path)
        Init.waited(ok, path, s)
    case P.Modules{+path}:
      do IO<St>:
        text : String <- Init.read(path)
        Init.insmods(String.lines(text), s)
    case P.Stop{+names}:
      do IO<St>:
        Init.say("stop" ++ P.Plan.sh_words(names))
        Init.signal_all(S.Sup.pids_named(St.svcs(s), names), 15)
        return s
    case P.Log{+text}:
      do IO<St>:
        Init.say(text)
        return s

def Init.steps.next(ok: Bool, again: IO(St), +s: St) -> IO(St):
  match ok:
    case True{}:
      again
    case False{}:
      IO.pure(St, s)

# Steps run in order; the first failure stops the boot.
def Init.steps(ss: List<&2, P.Step>, s: St) -> IO(St):
  match ss:
    case Nil{}:
      IO.pure(St, s)
    case Con{step, t}:
      do IO<St>:
        +s2 : St <- Init.step(step, s)
        Init.steps.next(St.ok(s2), Init.steps(t, s2), s2)

def Init.none_left(pids: List<&2, U32>) -> Bool:
  match pids:
    case Nil{}:
      True{}
    case Con{p, t}:
      False{}

def Init.drain.go(done: Bool, again: IO(Unit)) -> IO(Unit):
  match done:
    case True{}:
      Init.say("every daemon stopped")
    case False{}:
      again

def Init.running_names.go(stopped: Bool, +n: String, rest: String) -> String:
  match stopped:
    case True{}:
      rest
    case False{}:
      " " ++ n ++ rest

def Init.running_names(svcs: +List<S.Svc>) -> String:
  match svcs:
    case Nil{}:
      ""
    case Con{+s, t}:
      Init.running_names.go(U32.is_eq(S.Sup.pid(s), 0), S.Sup.name(s), Init.running_names(t))

# Wait (n polls, 250 ms apart) until every daemon has exited.
def Init.drain(n: Nat, +svcs: +List<S.Svc>) -> IO(Unit):
  match n:
    case 0n:
      Init.say("grace period over; still running:" ++ Init.running_names(svcs))
    case 1n+p:
      do IO<Unit>:
        IO.sleep(250)
        exits : List<(U32 & U32)> <- Proc.reap()
        +now : Nat <- IO.now()
        +s2 : +List<S.Svc> = Init.exits_noted(exits, now, svcs)
        Init.drain.go(Init.none_left(S.Sup.stop_order(s2)), Init.drain(p, s2))

def Init.stop_wait.go(gone: Bool, +svcs: +List<S.Svc>, again: IO(+List<S.Svc>)) -> IO(+List<S.Svc>):
  match gone:
    case True{}:
      IO.pure(+List<S.Svc>, svcs)
    case False{}:
      again

# Wait (n polls, 100 ms apart) for daemon `pid` to exit, noting all exits.
def Init.stop_wait(n: Nat, +pid: U32, +svcs: +List<S.Svc>) -> IO(+List<S.Svc>):
  match n:
    case 0n:
      IO.pure(+List<S.Svc>, svcs)
    case 1n+p:
      do IO<+List<S.Svc>>:
        IO.sleep(100)
        exits : List<(U32 & U32)> <- Proc.reap()
        +now : Nat <- IO.now()
        +s2 : +List<S.Svc> = Init.exits_noted(exits, now, svcs)
        Init.stop_wait.go(Bool.not(S.Sup.alive(s2, pid)), s2, Init.stop_wait(p, pid, s2))

# Stop the daemons one at a time, last started first, as systemd stops
# units in reverse order: each one exits while what it needs still runs.
def Init.stop_each(pids: List<&2, U32>, +svcs: +List<S.Svc>) -> IO(+List<S.Svc>):
  match pids:
    case Nil{}:
      IO.pure(+List<S.Svc>, svcs)
    case Con{+pid, rest}:
      do IO<+List<S.Svc>>:
        e : U32 <- Proc.signal(pid, 15)
        +s2 : +List<S.Svc> <- Init.stop_wait(Nat.div(S.Sup.stop_each_ms(), 100n), pid, svcs)
        Init.stop_each(rest, s2)

# The power button: stop the daemons, end every other process, unmount,
# power off.
def Init.shutdown(+svcs: +List<S.Svc>) -> IO(Unit):
  do IO<Unit>:
    Init.say("power button: stopping the cluster")
    +s2 : +List<S.Svc> <- Init.stop_each(S.Sup.stop_order(svcs), svcs)
    Init.say("daemons stopped; still running:" ++ Init.running_names(s2))
    e1 : U32 <- Proc.signal(4294967295, 15)
    IO.sleep(1000)
    e2 : U32 <- Proc.signal(4294967295, 9)
    IO.sleep(250)
    exits : List<(U32 & U32)> <- Proc.reap()
    st : St <- Init.bb(["umount", "-a", "-r"], St{True{}, []})
    Init.say("powering off")
    e3 : U32 <- Sys.poweroff()
    Init.say("poweroff failed (errno " ++ U32.show(e3) ++ ")")

def Init.supervise.go(pressed: Bool, +svcs: +List<S.Svc>, again: IO(Unit)) -> IO(Unit):
  match pressed:
    case True{}:
      Init.shutdown(svcs)
    case False{}:
      again

def Init.request.answer(ok: Bool) -> String:
  match ok:
    case True{}:
      " done\n"
    case False{}:
      " failed\n"

def Init.certs_auto.go(expiring: Bool, +c: P.Cfg, st: St) -> IO(St):
  match expiring:
    case True{}:
      do IO<St>:
        Init.say("a certificate expires within 90 days: rotating")
        Init.steps(P.Plan.certs_rotate(c), st)
    case False{}:
      IO.pure(St, st)

# vcluster's cert watcher: rotate every leaf certificate when one is
# within 90 days of expiry (P.Plan.certs_expiring decides).
def Init.certs_auto(+c: P.Cfg, st: St) -> IO(St):
  do IO<St>:
    +s1 : St <- Init.steps([P.Plan.link_kubeconfigs(), P.Plan.certs_residuals()], st)
    text : String <- Init.read(P.Plan.residuals_file())
    Init.certs_auto.go(P.Plan.certs_expiring(String.lines(text)), c, s1)

def Init.request.act(auto: Bool, +action: String, +c: P.Cfg, +out: String, +svcs: +List<S.Svc>) -> IO(St):
  match auto:
    case True{}:
      Init.certs_auto(c, St{True{}, svcs})
    case False{}:
      do IO<St>:
        +steps : +List<P.Step> = P.Plan.request(action, c, out)
        Init.steps(steps, St{Bool.not(List.is_empty(&2, P.Step, steps)), svcs})

def Init.request.run(ws: List<&2, String>, +c: P.Cfg, +svcs: +List<S.Svc>) -> IO(+List<S.Svc>):
  match ws:
    case Con{+id, Con{+action, t}}:
      do IO<+List<S.Svc>>:
        Init.say("host request " ++ id ++ ": " ++ action)
        +dir : String = P.Plan.requests_dir()
        +st : St <- Init.request.act(String.eq(action, "certs-auto"), action, c, dir ++ "/" ++ id ++ ".out", svcs)
        +s2 : St <- Init.write(dir ++ "/response", id ++ Init.request.answer(St.ok(st)), st)
        return St.svcs(s2)
    case _:
      IO.pure(+List<S.Svc>, svcs)

# A request from the host, if one waits (P.Plan.request).
def Init.request.go(empty: Bool, +text: String, +c: P.Cfg, +svcs: +List<S.Svc>) -> IO(+List<S.Svc>):
  match empty:
    case True{}:
      IO.pure(+List<S.Svc>, svcs)
    case False{}:
      do IO<+List<S.Svc>>:
        +st : St <- Init.bb(["rm", "-f", P.Plan.requests_dir() ++ "/request"], St{True{}, svcs})
        Init.request.run(String.split(String.trim(text), ' '), c, St.svcs(st))

def Init.request(+c: P.Cfg, +svcs: +List<S.Svc>) -> IO(+List<S.Svc>):
  do IO<+List<S.Svc>>:
    +text : String <- Init.read(P.Plan.requests_dir() ++ "/request")
    Init.request.go(String.is_empty(String.trim(text)), text, c, svcs)

# PID 1's life after boot: every 250 ms reap, then restart what is due,
# then serve a host request if one waits; the power button shuts the
# cluster down.
def Init.trim.go(trim: Bool, +svcs: +List<S.Svc>) -> IO(+List<S.Svc>):
  match trim:
    case True{}:
      do IO<+List<S.Svc>>:
        +st : St <- Init.steps([P.Plan.trim_logs()], St{True{}, svcs})
        return St.svcs(st)
    case False{}:
      IO.pure(+List<S.Svc>, svcs)

def Init.cert_timer.go(due: Bool, cp: Bool, +c: P.Cfg, +svcs: +List<S.Svc>) -> IO(+List<S.Svc>):
  match due cp:
    case True{} True{}:
      do IO<+List<S.Svc>>:
        +st : St <- Init.certs_auto(c, St{True{}, svcs})
        return St.svcs(st)
    case _ _:
      IO.pure(+List<S.Svc>, svcs)

def Init.next_check(due: Bool, +now: Nat, +next: Nat) -> Nat:
  match due:
    case True{}:
      Nat.add(now, P.Plan.cert_check_ms())
    case False{}:
      next

# PID 1's life after boot: every 250 ms reap, then restart what is due,
# then serve a host request if one waits, and every 24 h on the control
# plane check certificate expiry; the power button shuts the cluster down.
def Init.supervise(n: Nat, +c: P.Cfg, +cp: Bool, +next: Nat, +tick: U32, svcs: +List<S.Svc>) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+p:
      do IO<Unit>:
        IO.sleep(250)
        exits : List<(U32 & U32)> <- Proc.reap()
        +now : Nat <- IO.now()
        presses : U32 <- Sys.power()
        +s2 : +List<S.Svc> = Init.exits_noted(exits, now, svcs)
        +s3 : +List<S.Svc> <- Init.start_due(U32.to_nat(64), s2, now)
        +s4 : +List<S.Svc> <- Init.request(c, s3)
        +due : Bool = Nat.is_le(next, now)
        +s5 : +List<S.Svc> <- Init.cert_timer.go(due, cp, c, s4)
        +n2 : Nat = Init.next_check(due, now, next)
        +trim : Bool = U32.is_eq((tick % P.Plan.trim_every_ticks() : U32), 0)
        +s6 : +List<S.Svc> <- Init.trim.go(trim, s5)
        Init.supervise.go(Bool.not(U32.is_eq(presses, 0)), s6, Init.supervise(p, c, cp, n2, (tick + 1 : U32), s6))

def Init.name(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Fail{e}:
      "vk8s"
    case Done{s}:
      s

def Init.port.read(m: Maybe<&2, U32>) -> U32:
  match m:
    case None{}:
      6443
    case Some{p}:
      p

def Init.port(r: Result<&1, &1, U32 & String, String>) -> U32:
  match r:
    case Fail{e}:
      6443
    case Done{s}:
      Init.port.read(U32.read(s))

def Init.env_or(r: Result<&1, &1, U32 & String, String>, +d: String) -> String:
  match r:
    case Fail{e}:
      d
    case Done{s}:
      s

def Init.plan(worker: Bool, cache: Bool, +name: String, +port: U32, +etcd: Bool, +ip: String, +token: String) -> +List<P.Step>:
  match worker cache:
    case True{} _:
      P.Plan.worker(P.WCfg{name, ip, token})
    case False{} True{}:
      P.Plan.cache()
    case False{} False{}:
      P.Plan.boot(P.Plan.default_cfg(name, port, etcd))

def Init.finished(ok: Bool) -> String:
  match ok:
    case True{}:
      "boot finished; supervising"
    case False{}:
      "boot FAILED; supervising what started (see the console and share/logs)"

# PID 1's boot.
def Init.boot() -> IO(Unit):
  do IO<Unit>:
    Init.say("starting")
    r : Result<&1, &1, U32 & String, String> <- IO.get_env("VK8S_NAME")
    +name : String = Init.name(r)
    rp : Result<&1, &1, U32 & String, String> <- IO.get_env("VK8S_PORT")
    +port : U32 = Init.port(rp)
    rs : Result<&1, &1, U32 & String, String> <- IO.get_env("VK8S_STORE")
    +etcd : Bool = String.eq(Init.name(rs), "etcd")
    rr : Result<&1, &1, U32 & String, String> <- IO.get_env("VK8S_ROLE")
    ri : Result<&1, &1, U32 & String, String> <- IO.get_env("VK8S_NODE_IP")
    rt : Result<&1, &1, U32 & String, String> <- IO.get_env("VK8S_TOKEN")
    +role : String = Init.name(rr)
    +plan : +List<P.Step> = Init.plan(String.eq(role, "worker"), String.eq(role, "cache"), name, port, etcd, Init.env_or(ri, ""), Init.env_or(rt, ""))
    +st : St <- Init.steps(plan, St{True{}, []})
    Init.say(Init.finished(St.ok(st)))
    +t0 : Nat <- IO.now()
    Init.supervise(U32.to_nat(4294967295), P.Plan.default_cfg(name, port, etcd), String.eq(role, "") || String.eq(role, "vk8s") || String.eq(role, "control-plane"),
      Nat.add(t0, P.Plan.cert_check_ms()), 1, St.svcs(st))

def Init.args(xs: List<String>) -> +List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, t}:
      Con{x, Init.args(t)}

def Init.is_mode(+args: +List<String>, +mode: String) -> Bool:
  match args:
    case Con{a, Con{m, t}}:
      String.eq(m, mode)
    case _:
      False{}

def Init.run(kp: Bool, +args: +List<String>) -> IO(Unit):
  match kp:
    case True{}:
      KP.Kubelet.serve(KP.Kubelet.cfg(args))
    case False{}:
      Init.boot()

# `vk8s kubelet-proxy --flag=value ...` runs the fake kubelet alone
# (host/kubelet_proxy.bend), for tests, until the syncer starts it; with no
# such mode, vk8s boots the VM as PID 1.
def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<String> <- IO.args()
    +args : +List<String> = Init.args(xs)
    Init.run(Init.is_mode(args, "kubelet-proxy"), args)
