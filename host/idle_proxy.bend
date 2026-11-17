import Base
import ../src/cli/idle.bend as I
import ./tls_server.bend as S

# Sleep when idle (docs/GOAL.md section 10): the cluster's API forward.
# Every decision is src/cli/idle.bend's; this file only moves bytes.
#
# `vk8s idle-proxy NAME PORT HOST UP LIMIT` listens on 127.0.0.1:PORT, the
# port the cluster's kubeconfig names, and relays each connection to
# HOST:UP (a VM's private loopback forward of its 6443, or a container
# control plane's address). After LIMIT seconds with no connection open
# it runs `vk8s pause NAME` (bend-vmm pause, or the cgroup freezer for
# container nodes, after the control plane's PID 1 has stopped its
# controllers). The next connection waits while `vk8s resume NAME`
# resumes the nodes and PID 1 restarts the controllers (src/guest/plan.bend
# Plan.idle_wake); then it is relayed. Each connection runs in its own
# computation and reports its end on a channel; the main loop alone keeps
# the idle clock (Idle.step), ticking each second.

type IdleCfg is Data:
  IdleCfg{self: String, name: String, port: U32, host: String, up: U32, limit: U32}

def IdleP.forever() -> Nat:
  U32.to_nat(4294967295)

def IdleP.say(+s: String) -> IO(Unit):
  IO.print("idle-proxy: " ++ s)

# The idle clock's time: seconds on the IO clock (monotonic).
def IdleP.now() -> IO(U32):
  do IO<U32>:
    ms : Nat <- IO.now()
    return U32.from_nat(Nat.div(ms, 1000n))

def IdleCfg.self(c: IdleCfg) -> String:
  match c:
    case IdleCfg{s, n, p, h, u, l}:
      s

def IdleCfg.name(c: IdleCfg) -> String:
  match c:
    case IdleCfg{s, n, p, h, u, l}:
      n

def IdleCfg.port(c: IdleCfg) -> U32:
  match c:
    case IdleCfg{s, n, p, h, u, l}:
      p

def IdleCfg.host(c: IdleCfg) -> String:
  match c:
    case IdleCfg{s, n, p, h, u, l}:
      h

def IdleCfg.up(c: IdleCfg) -> U32:
  match c:
    case IdleCfg{s, n, p, h, u, l}:
      u

def IdleCfg.limit(c: IdleCfg) -> U32:
  match c:
    case IdleCfg{s, n, p, h, u, l}:
      l

def IdleP.nth(xs: +List<String>, n: Nat) -> String:
  match xs n:
    case Nil{} _:
      ""
    case Con{+x, t} 0n:
      x
    case Con{x, t} 1n+p:
      IdleP.nth(t, p)

def IdleP.num(+s: String) -> U32:
  Maybe.default(&2, U32, U32.read(s), 0)

# argv: vk8s idle-proxy NAME PORT HOST UP LIMIT
def IdleP.cfg(+xs: +List<String>) -> IdleCfg:
  IdleCfg{IdleP.nth(xs, 0n), IdleP.nth(xs, 2n), IdleP.num(IdleP.nth(xs, 3n)), IdleP.nth(xs, 4n), IdleP.num(IdleP.nth(xs, 5n)),
    IdleP.num(IdleP.nth(xs, 6n))}

# vk8s pause NAME or vk8s resume NAME, as a child (its output goes to the
# proxy's log).
def IdleP.vk8s.got(r: Result<&1, &1, U32 & String, U32 & (String & String)>, +verb: String) -> IO(Unit):
  match r:
    case Fail{(code, msg)}:
      IdleP.say(verb ++ " did not run: " ++ msg)
    case Done{(st, (out, err))}:
      IdleP.say(verb ++ " (exit " ++ U32.show(st) ++ "): " ++ String.trim(out) ++ " " ++ String.trim(err))

def IdleP.vk8s(+c: IdleCfg, +verb: String) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run(IdleCfg.self(c), [verb, IdleCfg.name(c)], "", 1048576, 900000)
    IdleP.vk8s.got(r, verb)

def IdleP.act(a: I.Idle.Act, +c: IdleCfg) -> IO(Unit):
  match a:
    case I.IdleStay{}:
      IO.pure(Unit, Unit{})
    case I.IdleSleep{}:
      do IO<Unit>:
        IdleP.say("no API traffic for " ++ U32.show(IdleCfg.limit(c)) ++ " s: pausing " ++ IdleCfg.name(c))
        IdleP.vk8s(c, "pause")
    case I.IdleWake{}:
      do IO<Unit>:
        IdleP.say("a connection came: resuming " ++ IdleCfg.name(c))
        IdleP.vk8s(c, "resume")

# The upstream: a few tries, 500 ms apart (a resumed node may take a
# moment to accept).
def IdleP.connect.go(r: Result<&1, &1, U32 & String, Socket>, again: IO(Result<&1, &1, U32 & String, Socket>)) ->
  IO(Result<&1, &1, U32 & String, Socket>):
  match r:
    case Done{s}:
      IO.pure(Result<&1, &1, U32 & String, Socket>, Done{s})
    case Fail{e}:
      again

def IdleP.connect(n: Nat, +host: String, +up: U32) -> IO(Result<&1, &1, U32 & String, Socket>):
  match n:
    case 0n:
      TCP.connect(host, up)
    case 1n+p:
      do IO<Result<&1, &1, U32 & String, Socket>>:
        r : Result<&1, &1, U32 & String, Socket> <- TCP.connect(host, up)
        IdleP.connect.go(r, IO.bind(Unit, Result<&1, &1, U32 & String, Socket>, IO.sleep(500), u => IdleP.connect(p, host, up)))

def IdleP.relay(r: Result<&1, &1, U32 & String, Socket>, sock: Socket) -> IO(Unit):
  match r:
    case Done{up}:
      S.TlsSrv.splice(sock, up)
    case Fail{(code, msg)}:
      do IO<Unit>:
        IdleP.say("the API did not accept: " ++ msg)
        Socket.close(sock)

# One connection: relay it, then report its end.
def IdleP.serve(sock: Socket, +host: String, +up: U32, +ch: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, Socket> <- IdleP.connect(20n, host, up)
    IdleP.relay(r, sock)
    _ : Result<&1, &1, Unit, Unit> <- Chan.send(Unit, ch, Unit{})
    return Unit{}

# The ends reported since the last round (at most n), each a Close event.
def IdleP.drain.go(p: Poll<&1, &1, Maybe<&1, Unit>, Unit>, +limit: U32, +st: I.Idle.St, +now: U32, more: I.Idle.St -> IO(I.Idle.St)) ->
  IO(I.Idle.St):
  match p:
    case Ready{Some{u}}:
      more(I.Idle.Out.st(I.Idle.step(limit, st, I.IdleClose{now})))
    case Ready{None{}}:
      IO.pure(I.Idle.St, st)
    case Wait{u}:
      IO.pure(I.Idle.St, st)

def IdleP.drain(n: Nat, +ch: Chan(Unit), +limit: U32, +st: I.Idle.St, +now: U32) -> IO(I.Idle.St):
  match n:
    case 0n:
      IO.pure(I.Idle.St, st)
    case 1n+p:
      do IO<I.Idle.St>:
        r : Poll<&1, &1, Maybe<&1, Unit>, Unit> <- Chan.try_recv(Unit, ch, 0)
        IdleP.drain.go(r, limit, st, now, s => IdleP.drain(p, ch, limit, s, now))

# What a round brings: a connection, an accept that failed, or nothing
# within a tick.
def IdleP.got(r: Listener & Poll<&1, &1, Result<&1, &1, U32 & String, Socket>, Unit>, +c: IdleCfg, +ch: Chan(Unit),
  +st: I.Idle.St, +now: U32, next: Listener -> I.Idle.St -> IO(Unit)) -> IO(Unit):
  match r:
    case (l, Ready{Done{sock}}):
      do IO<Unit>:
        +o : I.Idle.Out = I.Idle.step(IdleCfg.limit(c), st, I.IdleOpen{now})
        IdleP.act(I.Idle.Out.act(o), c)
        IO.spawn(Unit, IdleP.serve(sock, IdleCfg.host(c), IdleCfg.up(c), ch))
        next(l, I.Idle.Out.st(o))
    case (l, Ready{Fail{(code, msg)}}):
      do IO<Unit>:
        IdleP.say("accept failed: " ++ msg)
        IO.sleep(100)
        next(l, st)
    case (l, Wait{u}):
      do IO<Unit>:
        +o : I.Idle.Out = I.Idle.step(IdleCfg.limit(c), st, I.IdleTick{now})
        IdleP.act(I.Idle.Out.act(o), c)
        next(l, I.Idle.Out.st(o))

def IdleP.loop(n: Nat, l: Listener, +c: IdleCfg, +ch: Chan(Unit), +st: I.Idle.St) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+p:
      do IO<Unit>:
        +t0 : U32 <- IdleP.now()
        +s1 : I.Idle.St <- IdleP.drain(64n, ch, IdleCfg.limit(c), st, t0)
        r : Listener & Poll<&1, &1, Result<&1, &1, U32 & String, Socket>, Unit> <- TCP.try_accept(l, I.Idle.tick_ms())
        +t1 : U32 <- IdleP.now()
        IdleP.got(r, c, ch, s1, t1, l2 => s2 => IdleP.loop(p, l2, c, ch, s2))

def IdleP.listening(r: Result<&1, &1, U32 & String, Listener>, +c: IdleCfg) -> IO(Unit):
  match r:
    case Fail{(code, msg)}:
      IO.die(Unit, 1, "idle-proxy: cannot listen on 127.0.0.1:" ++ U32.show(IdleCfg.port(c)) ++ ": " ++ msg)
    case Done{l}:
      do IO<Unit>:
        IdleP.say("127.0.0.1:" ++ U32.show(IdleCfg.port(c)) ++ " -> " ++ IdleCfg.host(c) ++ ":" ++ U32.show(IdleCfg.up(c)) ++ ", sleep after "
          ++ U32.show(IdleCfg.limit(c)) ++ " s idle")
        ch : Chan(Unit) <- Chan.new(Unit, 1024)
        +now : U32 <- IdleP.now()
        IdleP.loop(IdleP.forever(), l, c, ch, I.Idle.start(now))

def IdleP.main(+xs: +List<String>) -> IO(Unit):
  do IO<Unit>:
    +c : IdleCfg = IdleP.cfg(xs)
    r : Result<&1, &1, U32 & String, Listener> <- TCP.listen("127.0.0.1", IdleCfg.port(c))
    IdleP.listening(r, c)
