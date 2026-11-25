import Base
import bend-kube-runtime@0.12.0.0/src/sys.bend as SY
import ../../src/layers/ask.bend as A
import ../../src/layers/serve.bend as SV
import ../../src/layers/store.bend as Y
import ../../src/layers/fill.bend as F
import ../../src/layers/pull.bend as P
import ../../src/layers/tar.bend as T
import ../../src/guest/plan.bend as PL
import ./unpack.bend as U
import ./fill.bend as LF

# `vk8s layers serve`: the host's layer filler
# ============================================
#
# A hidden subcommand (work item W5 of docs/ref/explore-layers-autofill.md;
# GOAL section 10). One daemon per host listens on 127.0.0.1:Ask.port.v2
# (32000); a node's snapshotter reaches it as 10.0.2.2:32000 when the
# shared store lacks a layer it prepares. Every decision is
# src/layers/serve.bend's or src/layers/ask.bend's; this file reads,
# fills, answers and prints (to the daemon's log, ~/.vk8s/layers-serve.log
# when `vk8s create` starts it).
#
# Each connection runs in its own computation, as in host/idle_proxy.bend:
#   1. it reads one ask line, at most Ask.line_max.v2 bytes, in at most
#      Srv.reads.v2 reads of Srv.read_ms.v2 each (Srv.read.more.v2), and
#      reads it with Ask.parse.v2 only (any pod can reach the port);
#   2. a layer the store holds (its record, and lstat of its directory:
#      Fill.present.v2) is answered "ok present" at once;
#   3. else it asks the main loop, which alone keeps the state
#      (Srv.admit.v2): fill the image, wait for the fill another ask
#      started for it, or "no" when a cap is reached;
#   4. a fill fetches the manifest by its digest from the host's image
#      cache when it answers on the registry's port (plain HTTP; the
#      registry itself, host/oci/upstream.bend, when it does not, and for
#      what it does not answer) and fills every layer of the image as
#      `vk8s layers fill` does, under per-layer locks, from one queue a
#      few lanes share (Lf.layers.queue.v5), and removes each blob it published from ~/.vk8s/oci (an
#      automatic fill: Lf.fill.port.v4 with auto); then the main loop
#      wakes the asks that waited for it, when the fill's end reaches
#      it (LsFilled; no polling round in between);
#   5. the answer (Srv.reply.v2): "ok present", "ok published" when the
#      layer is there after the fill, else "no <reason>".
# The main loop counts the connections (Srv.open_max.v2) and answers "no"
# at once past the cap. It takes one event at a time from one channel
# (Ls.loop); an acceptor of its own hands it the connections.

type LsCfg is Data:
  LsCfg{root: String, arch: String, port: U32}

# What the main loop tells an ask: its turn, then (for SJoin) the end of
# the fill it waits for, with that fill's error.
type LsMsg is Data:
  LsTurn{t: SV.Turn}
  LsDone{err: Maybe<&2, String>}

# What a connection tells the main loop: an ask for image key (the main
# loop answers on back), the end of the fill of key, the end of the
# connection; and the acceptor: a connection it took.
type LsEv is Type:
  LsWant{key: String, back: Chan(LsMsg)}
  LsFilled{key: String, err: Maybe<&2, String>}
  LsEnd{}
  LsConn{sock: Socket}

type LsBack is Data:
  LsBack{id: U32, back: Chan(LsMsg)}

# The main loop's state: the pure state, the channels of the waiting
# asks, and the next ask's id.
type LsSt is Data:
  LsSt{srv: SV.Srv, backs: List<&2, LsBack>, next: U32}

def Ls.forever() -> Nat:
  U32.to_nat(4294967295)

def Ls.say(+s: String) -> IO(Unit):
  IO.print("vk8s layers serve: " ++ s)

def LsCfg.root(c: LsCfg) -> String:
  match c:
    case LsCfg{r, a, p}:
      r

def LsCfg.arch(c: LsCfg) -> String:
  match c:
    case LsCfg{r, a, p}:
      a

def LsCfg.port(c: LsCfg) -> U32:
  match c:
    case LsCfg{r, a, p}:
      p

def Ls.chain(a: A.Ask) -> String:
  match a:
    case A.Ask{r, p, m, l, c}:
      c

# Whether the store holds layer chain: its record, and lstat of its
# image or, from an older store, its directory (Fill.present.v3).
def Ls.present(+root: String, +chain: String) -> IO(Bool):
  do IO<Bool>:
    m : Maybe<&2, Y.Layer> <- U.Lu.rec.get(root, chain)
    st : F.Stat <- U.Lu.stat(Maybe.default(&2, String, Y.Lay.dir(root, chain), ""))
    si : F.Stat <- U.Lu.stat(Maybe.default(&2, String, Y.Lay.img.v3(root, chain), ""))
    return Maybe.is_some(&2, Y.Layer, F.Fill.present.v3(m, st, si))

def Ls.touch.said(r: U.Lu.R(Unit), +chain: String) -> IO(Unit):
  match r:
    case Done{u}:
      IO.pure(Unit, Unit{})
    case Fail{e}:
      Ls.say("no refresh of " ++ chain ++ "'s last use: " ++ e)

def Ls.touch.rec(m: Maybe<&2, F.Rec>, +root: String, +now: U32) -> IO(Bool):
  match m:
    case None{}:
      IO.pure(Bool, False{})
    case Some{+r}:
      do IO<Bool>:
        w : U.Lu.R(Unit) <- U.Lu.rec.put(root, now, F.Fill.rec.at.v3(r, now))
        Ls.touch.said(w, U.Lu.rec.chain(r))
        return True{}

# Present under the lock: its record written again with last use now.
def Ls.touch(p: Bool, m: Maybe<&2, F.Rec>, +root: String, +now: U32) -> IO(Bool):
  match p:
    case False{}:
      IO.pure(Bool, False{})
    case True{}:
      Ls.touch.rec(m, root, now)

def Ls.present.locked(r: U.Lu.R(Unit), +root: String, +chain: String, +now: U32, +path: String) -> IO(Bool):
  match r:
    case Fail{e}:
      do IO<Bool>:
        Ls.say("no refresh of " ++ chain ++ "'s last use: " ++ e)
        Ls.present(root, chain)
    case Done{u}:
      do IO<Bool>:
        +m : Maybe<&2, F.Rec> <- U.Lu.rec.get2(root, chain)
        st : F.Stat <- U.Lu.stat(Maybe.default(&2, String, Y.Lay.dir(root, chain), ""))
        si : F.Stat <- U.Lu.stat(Maybe.default(&2, String, Y.Lay.img.v3(root, chain), ""))
        p : Bool <- Ls.touch(Maybe.is_some(&2, Y.Layer, F.Fill.present.v3(F.Fill.rec.layer(m), st, si)), m, root, now)
        U.Lu.llock.drop(path)
        return p

def Ls.present.due(due: Bool, +root: String, +chain: String, +now: U32, plain: IO(Bool)) -> IO(Bool):
  match due:
    case False{}:
      plain
    case True{}:
      do IO<Bool>:
        +path : String = U.Lu.llock.path(root, chain)
        r : U.Lu.R(Unit) <- U.Lu.llock.wait(U32.to_nat(F.Fill.llock.polls.v2()), path, 0)
        Ls.present.locked(r, root, chain, now, path)

# Whether the store holds layer chain, refreshing its last use when it
# is a day old (Fill.rec.due.v3): then under the layer's lock, the lock
# gc rechecks under, with present asked again there, so gc either
# removed the layer first (answered absent: the node's fill brings it
# back) or sees the new last use (GOAL section 11). A layer used in the
# last day costs no write.
def Ls.present.v3(+root: String, +chain: String) -> IO(Bool):
  do IO<Bool>:
    +now : U32 <- U.Lu.now()
    +m : Maybe<&2, F.Rec> <- U.Lu.rec.get2(root, chain)
    st : F.Stat <- U.Lu.stat(Maybe.default(&2, String, Y.Lay.dir(root, chain), ""))
    si : F.Stat <- U.Lu.stat(Maybe.default(&2, String, Y.Lay.img.v3(root, chain), ""))
    +p : Bool = Maybe.is_some(&2, Y.Layer, F.Fill.present.v3(F.Fill.rec.layer(m), st, si))
    Ls.present.due(p && F.Fill.rec.due.v3(m, now), root, chain, now, IO.pure(Bool, p))

# Reading and answering
# ---------------------

def Ls.read.got(p: Socket & Poll<&1, &1, Result<&1, &1, U32 & String, Maybe<&1, List<&2, U32>>>, Unit>, +acc: List<&2, U32>,
  again: Socket -> List<&2, U32> -> IO(Socket & List<&2, U32>)) -> IO(Socket & List<&2, U32>):
  match p:
    case (s, Ready{Done{Some{bs}}}):
      again(s, List.append(&2, U32, acc, bs))
    case (s, Ready{Done{None{}}}):
      IO.pure(Socket & List<&2, U32>, (s, acc))
    case (s, Ready{Fail{e}}):
      IO.pure(Socket & List<&2, U32>, (s, acc))
    case (s, Wait{u}):
      again(s, acc)

def Ls.read.if(more: Bool, s: Socket, +acc: List<&2, U32>, again: Socket -> List<&2, U32> -> IO(Socket & List<&2, U32>)) ->
  IO(Socket & List<&2, U32>):
  match more:
    case True{}:
      do IO<Socket & List<&2, U32>>:
        r : Socket & Poll<&1, &1, Result<&1, &1, U32 & String, Maybe<&1, List<&2, U32>>>, Unit> <- TCP.try_recv_bytes(s,
          SV.Srv.read_max.v2(), SV.Srv.read_ms.v2())
        Ls.read.got(r, acc, again)
    case False{}:
      IO.pure(Socket & List<&2, U32>, (s, acc))

# The bytes of an ask: reads until a "\n", more than Ask.line_max.v2
# bytes, the peer's end, or n reads.
def Ls.read(n: Nat, s: Socket, +acc: List<&2, U32>) -> IO(Socket & List<&2, U32>):
  match n:
    case 0n:
      IO.pure(Socket & List<&2, U32>, (s, acc))
    case 1n+p:
      Ls.read.if(SV.Srv.read.more.v2(acc), s, acc, s2 => a2 => Ls.read(p, s2, a2))

def Ls.sent(q: Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit>) -> IO(Unit):
  match q:
    case (s, r):
      Socket.close(s)

def Ls.answer(s: Socket, +r: A.Reply) -> IO(Unit):
  do IO<Unit>:
    q : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send(s, A.Ask.reply.render.v2(r))
    Ls.sent(q)

# The answer to ask a, logged.
def Ls.answer.ask(s: Socket, +a: A.Ask, +r: A.Reply) -> IO(Unit):
  do IO<Unit>:
    Ls.say(Ls.chain(a) ++ " of " ++ SV.Srv.key.v2(a) ++ ": " ++ String.trim(A.Ask.reply.render.v2(r)))
    Ls.answer(s, r)

# Filling
# -------

# After a fill of image key that took ms: its line (SV.Srv.fill.line.v2,
# the phases summed over its layers) or its error, logged; its error.
def Ls.filled(r: LF.Lf.R(U32 & SV.Phases), +key: String, +ms: U32) -> IO(Maybe<&2, String>):
  match r:
    case Fail{+e}:
      do IO<Maybe<&2, String>>:
        Ls.say(key ++ ": fill failed in " ++ U32.show(ms) ++ " ms: " ++ e)
        return Some{e}
    case Done{(n, p)}:
      do IO<Maybe<&2, String>>:
        Ls.say(SV.Srv.fill.line.v2(key, n, ms, p))
        return None{}

# The fill of ask a's image, by its manifest digest, from the image
# cache, timed and logged (each layer's phases are logged as it ends:
# host/layers/fill.bend, Lf.pub); its error, or None.
def Ls.fill(a: A.Ask, +c: LsCfg) -> IO(Maybe<&2, String>):
  match a:
    case A.Ask{+r, +p, +m, l, ch}:
      do IO<Maybe<&2, String>>:
        +now : U32 <- LF.Lf.now()
        +root : String = LsCfg.root(c)
        t0 : U32 & (U32 & U32) <- SY.Sys.wall()
        x : LF.Lf.R(U32 & SV.Phases) <- U.Lu.then(Unit, U32 & SV.Phases, U.Lu.base.v2(root),
          u => LF.Lf.fill.port.v4(P.Pull.port(LF.Lf.mirrors(PL.Plan.mirrors()), r), r, p, m, LsCfg.arch(c), root, now, True{}))
        t1 : U32 & (U32 & U32) <- SY.Sys.wall()
        Ls.filled(x, r ++ "/" ++ p ++ "@" ++ m, SV.Srv.ms.v2(t0, t1))

# After the fill (its own, or the one it waited for, with that fill's
# error e): the answer from the store.
def Ls.after(s: Socket, +a: A.Ask, +c: LsCfg, +e: Maybe<&2, String>) -> IO(Unit):
  do IO<Unit>:
    after : Bool <- Ls.present(LsCfg.root(c), Ls.chain(a))
    Ls.answer.ask(s, a, SV.Srv.reply.v2(False{}, after, e))

def Ls.joined(m: Maybe<&1, LsMsg>, s: Socket, +a: A.Ask, +c: LsCfg) -> IO(Unit):
  match m:
    case Some{LsDone{e}}:
      Ls.after(s, a, c, e)
    case _:
      Ls.answer.ask(s, a, SV.Srv.busy.v2())

def Ls.turn(t: SV.Turn, s: Socket, +a: A.Ask, +c: LsCfg, +inbox: Chan(LsEv), +back: Chan(LsMsg)) -> IO(Unit):
  match t:
    case SV.SFill{}:
      do IO<Unit>:
        +e : Maybe<&2, String> <- Ls.fill(a, c)
        _ : Result<&1, &1, LsEv, Unit> <- Chan.send(LsEv, inbox, LsFilled{SV.Srv.key.v2(a), e})
        Ls.after(s, a, c, e)
    case SV.SJoin{}:
      do IO<Unit>:
        m : Maybe<&1, LsMsg> <- Chan.recv(LsMsg, back)
        Ls.joined(m, s, a, c)
    case SV.SBusy{}:
      Ls.answer.ask(s, a, SV.Srv.busy.v2())

def Ls.turned(m: Maybe<&1, LsMsg>, s: Socket, +a: A.Ask, +c: LsCfg, +inbox: Chan(LsEv), +back: Chan(LsMsg)) -> IO(Unit):
  match m:
    case Some{LsTurn{t}}:
      Ls.turn(t, s, a, c, inbox, back)
    case _:
      Ls.answer.ask(s, a, SV.Srv.busy.v2())

def Ls.had(had: Bool, s: Socket, +a: A.Ask, +c: LsCfg, +inbox: Chan(LsEv)) -> IO(Unit):
  match had:
    case True{}:
      Ls.answer.ask(s, a, SV.Srv.reply.v2(True{}, True{}, None{}))
    case False{}:
      do IO<Unit>:
        +back : Chan(LsMsg) <- Chan.new(LsMsg, 2)
        _ : Result<&1, &1, LsEv, Unit> <- Chan.send(LsEv, inbox, LsWant{SV.Srv.key.v2(a), back})
        m : Maybe<&1, LsMsg> <- Chan.recv(LsMsg, back)
        Ls.turned(m, s, a, c, inbox, back)

def Ls.asked(m: Maybe<&2, A.Ask>, s: Socket, +c: LsCfg, +inbox: Chan(LsEv)) -> IO(Unit):
  match m:
    case None{}:
      do IO<Unit>:
        Ls.say("refused a line that is not an ask")
        Ls.answer(s, SV.Srv.bad.v2())
    case Some{+a}:
      do IO<Unit>:
        had : Bool <- Ls.present.v3(LsCfg.root(c), Ls.chain(a))
        Ls.had(had, s, a, c, inbox)

# A peer that sent nothing (vk8s create's "is the port taken?" probe,
# Vk8s.layers_serve.probe) is answered as a bad line but not logged, so
# the log's refused lines are real bad asks.
def Ls.conn.bytes(s: Socket, bs: List<&2, U32>, +c: LsCfg, +inbox: Chan(LsEv)) -> IO(Unit):
  match bs:
    case Nil{}:
      Ls.answer(s, SV.Srv.bad.v2())
    case Con{h, t}:
      Ls.asked(A.Ask.parse.v2(T.Tar.s(Con{h, t})), s, c, inbox)

def Ls.conn.read(p: Socket & List<&2, U32>, +c: LsCfg, +inbox: Chan(LsEv)) -> IO(Unit):
  match p:
    case (s, bs):
      Ls.conn.bytes(s, bs, c, inbox)

# One connection: its ask read and answered, then its end reported.
def Ls.conn(sock: Socket, +c: LsCfg, +inbox: Chan(LsEv)) -> IO(Unit):
  do IO<Unit>:
    p : Socket & List<&2, U32> <- Ls.read(SV.Srv.reads.v2(), sock, [])
    Ls.conn.read(p, c, inbox)
    _ : Result<&1, &1, LsEv, Unit> <- Chan.send(LsEv, inbox, LsEnd{})
    return Unit{}

# The main loop
# -------------

def Ls.keep(t: SV.Turn, +id: U32, +back: Chan(LsMsg), bs: List<&2, LsBack>) -> List<&2, LsBack>:
  match t:
    case SV.SJoin{}:
      Con{LsBack{id, back}, bs}
    case _:
      bs

def Ls.has(ids: List<&2, U32>, +i: U32) -> Bool:
  match ids:
    case Nil{}:
      False{}
    case Con{x, t}:
      U32.is_eq(x, i) || Ls.has(t, i)

def Ls.wake.one(hit: Bool, b: LsBack, +e: Maybe<&2, String>, rest: IO(List<&2, LsBack>)) -> IO(List<&2, LsBack>):
  match hit:
    case True{}:
      match b:
        case LsBack{i, ch}:
          do IO<List<&2, LsBack>>:
            _ : Result<&1, &1, LsMsg, Unit> <- Chan.send(LsMsg, ch, LsDone{e})
            rest
    case False{}:
      IO.bind(List<&2, LsBack>, List<&2, LsBack>, rest, t => IO.pure(List<&2, LsBack>, Con{b, t}))

def Ls.bid(b: LsBack) -> U32:
  match b:
    case LsBack{i, ch}:
      i

# Each waiting ask in ids told its fill ended (with its error e); the
# others kept.
def Ls.wake(bs: List<&2, LsBack>, +ids: List<&2, U32>, +e: Maybe<&2, String>) -> IO(List<&2, LsBack>):
  match bs:
    case Nil{}:
      IO.pure(List<&2, LsBack>, Nil{})
    case Con{+b, t}:
      Ls.wake.one(Ls.has(ids, Ls.bid(b)), b, e, Ls.wake(t, ids, e))

def Ls.srv(st: LsSt) -> SV.Srv:
  match st:
    case LsSt{s, bs, i}:
      s

def Ls.opened(st: LsSt) -> LsSt:
  match st:
    case LsSt{s, bs, i}:
      LsSt{SV.Srv.opened.v2(s), bs, i}

# A connection the acceptor took: served in its own computation, or
# answered no at once past Srv.open_max.v2.
def Ls.accepted(ok: Bool, sock: Socket, +c: LsCfg, +inbox: Chan(LsEv), st: LsSt) -> IO(LsSt):
  match ok:
    case True{}:
      do IO<LsSt>:
        IO.spawn(Unit, Ls.conn(sock, c, inbox))
        return Ls.opened(st)
    case False{}:
      do IO<LsSt>:
        IO.spawn(Unit, Ls.answer(sock, SV.Srv.busy.v2()))
        return st

def Ls.took(sock: Socket, +c: LsCfg, +inbox: Chan(LsEv), +st: LsSt) -> IO(LsSt):
  Ls.accepted(SV.Srv.accept.v2(Ls.srv(st)), sock, c, inbox, st)

def Ls.ev(ev: LsEv, st: LsSt, +c: LsCfg, +inbox: Chan(LsEv)) -> IO(LsSt):
  match ev:
    case LsWant{+key, +back}:
      match st:
        case LsSt{+s, bs, +id}:
          do IO<LsSt>:
            +t : SV.Turn = SV.Srv.admit.v2(s, key)
            _ : Result<&1, &1, LsMsg, Unit> <- Chan.send(LsMsg, back, LsTurn{t})
            return LsSt{SV.Srv.take.v2(s, id, key), Ls.keep(t, id, back, bs), (id + 1 : U32)}
    case LsFilled{+key, +e}:
      match st:
        case LsSt{+s, bs, id}:
          do IO<LsSt>:
            rest : List<&2, LsBack> <- Ls.wake(bs, SV.Srv.woken.v2(SV.Srv.wait(s), key), e)
            return LsSt{SV.Srv.done.v2(s, key), rest, id}
    case LsEnd{}:
      match st:
        case LsSt{s, bs, id}:
          IO.pure(LsSt, LsSt{SV.Srv.closed.v2(s), bs, id})
    case LsConn{sock}:
      Ls.took(sock, c, inbox, st)

def Ls.loop.on(m: Maybe<&1, LsEv>, st: LsSt, +c: LsCfg, +inbox: Chan(LsEv), again: LsSt -> IO(Unit)) -> IO(Unit):
  match m:
    case None{}:
      IO.pure(Unit, Unit{})
    case Some{ev}:
      IO.bind(LsSt, Unit, Ls.ev(ev, st, c, inbox), again)

# The main loop: one event at a time, as it comes (a connection the
# acceptor took, an ask, the end of a fill, the end of a connection), as
# the image cache's (host/cache/mirror.bend Mir.loop). No event waits
# for a polling round: an ask gets its turn, and the asks that wait for
# a fill are woken, when the event arrives. (Before, the loop drained
# the events between two accepts that each waited up to 50 ms, so a turn
# and a wake each waited up to 50 ms.)
def Ls.loop(n: Nat, +c: LsCfg, +inbox: Chan(LsEv), st: LsSt) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+p:
      do IO<Unit>:
        m : Maybe<&1, LsEv> <- Chan.recv(LsEv, inbox)
        Ls.loop.on(m, st, c, inbox, s2 => Ls.loop(p, c, inbox, s2))

def Ls.tell(+inbox: Chan(LsEv), ev: LsEv) -> IO(Unit):
  do IO<Unit>:
    _ : Result<&1, &1, LsEv, Unit> <- Chan.send(LsEv, inbox, ev)
    return Unit{}

def Ls.acceptor.got(r: Listener & Poll<&1, &1, Result<&1, &1, U32 & String, Socket>, Unit>, +inbox: Chan(LsEv),
  next: Listener -> IO(Unit)) -> IO(Unit):
  match r:
    case (l, Ready{Done{sock}}):
      do IO<Unit>:
        Ls.tell(inbox, LsConn{sock})
        next(l)
    case (l, Ready{Fail{(code, msg)}}):
      do IO<Unit>:
        Ls.say("accept failed: " ++ msg)
        IO.sleep(100)
        next(l)
    case (l, Wait{u}):
      next(l)

# Accepts connections and hands each to the main loop.
def Ls.acceptor(n: Nat, l: Listener, +inbox: Chan(LsEv)) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+p:
      do IO<Unit>:
        r : Listener & Poll<&1, &1, Result<&1, &1, U32 & String, Socket>, Unit> <- TCP.try_accept(l, 1000)
        Ls.acceptor.got(r, inbox, l2 => Ls.acceptor(p, l2, inbox))

def Ls.listening(r: Result<&1, &1, U32 & String, Listener>, +c: LsCfg) -> IO(Unit):
  match r:
    case Fail{(code, msg)}:
      IO.die(Unit, 1, "vk8s layers serve: cannot listen on 127.0.0.1:" ++ U32.show(LsCfg.port(c)) ++ ": " ++ msg)
    case Done{l}:
      do IO<Unit>:
        Ls.say("127.0.0.1:" ++ U32.show(LsCfg.port(c)) ++ " fills " ++ LsCfg.root(c) ++ "/layers from the registries (at most "
          ++ U32.show(SV.Srv.cap.v2()) ++ " images at once)")
        +inbox : Chan(LsEv) <- Chan.new(LsEv, 1024)
        IO.spawn(Unit, Ls.acceptor(Ls.forever(), l, inbox))
        Ls.loop(Ls.forever(), c, inbox, LsSt{SV.Srv.start.v2(), [], 0})

def Ls.based(r: U.Lu.R(Unit), +c: LsCfg) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.die(Unit, 1, "vk8s layers serve: " ++ e)
    case Done{u}:
      do IO<Unit>:
        x : Result<&1, &1, U32 & String, Listener> <- TCP.listen("127.0.0.1", LsCfg.port(c))
        Ls.listening(x, c)

def Ls.arch(known: Bool, +c: LsCfg) -> IO(Unit):
  match known:
    case False{}:
      IO.die(Unit, 1, "vk8s layers serve: this host's architecture is not arm64 or amd64")
    case True{}:
      do IO<Unit>:
        r : U.Lu.R(Unit) <- U.Lu.base.v2(LsCfg.root(c))
        Ls.based(r, c)

# The filler for the store at root, for linux/arch, on 127.0.0.1:port.
def Ls.main(+root: String, +arch: String, +port: U32) -> IO(Unit):
  Ls.arch(String.eq(arch, "arm64") || String.eq(arch, "amd64"), LsCfg{root, arch, port})

def Serve.main.sub(ok: Bool, +arch: String, +root: String) -> IO(Unit):
  match ok:
    case True{}:
      Ls.main(root, arch, A.Ask.port.v2())
    case False{}:
      IO.die(Unit, 1, "vk8s layers: " ++ LF.Layers.usage())

def Serve.main.args(+args: +List<String>, +arch: String, +root: String) -> IO(Unit):
  match args:
    case Con{+sub, Nil{}}:
      Serve.main.sub(String.eq(sub, "serve"), arch, root)
    case _:
      IO.die(Unit, 1, "vk8s layers: " ++ LF.Layers.usage())

# argv ["vk8s", "layers", "serve"]: the store is home/.vk8s, arch the
# host's asset arch (arm64 or amd64), the port Ask.port.v2.
def Serve.main(+xs: +List<String>, +home: String, +arch: String) -> IO(Unit):
  Serve.main.args(List.drop(&2, String, xs, 2n), arch, home ++ "/.vk8s")
