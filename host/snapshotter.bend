import Base
import bend-kube-runtime@0.10.0.0/src/grpc.bend as G
import bend-kube-runtime@0.10.0.0/src/grpcio.bend as R
import bend-kube-runtime@0.10.0.0/src/h2io.bend as I
import bend-kube-runtime@0.10.0.0/src/sys.bend as Y
import ../src/layers/snap.bend as S
import ../src/layers/pb.bend as B
import ../src/layers/state.bend as T
import ../src/layers/ask.bend as A
import ../src/layers/store.bend as LY
import ../src/layers/fill.bend as LF
import ./snapshot_ask.bend as SA
import ../src/guest/plan.bend as PL

# The node's containerd proxy snapshotter (docs/GOAL.md section 10,
# shared image layers): `vk8s-guest snapshotter SOCKET ROOT HELD`, which
# PID 1 starts before containerd on a VM node with the layer store
# (src/guest/plan.bend Plan.snapshotter). It serves
# containerd.services.snapshots.v1.Snapshots over gRPC (h2c) on the Unix
# socket SOCKET with bend-kube-runtime's Grpc.serve, one call at a time:
# src/layers/pb.bend reads the call, src/layers/snap.bend decides it,
# and this file runs its effects, then answers (Grpc.reply, Grpc.send
# and Grpc.finish).
#
# One call at a time, as the overlay snapshotter takes its metadata
# store's lock for each: the state is a value this loop carries.
#
# The ask (docs/GOAL.md section 10, "the store fills itself"; work item
# W6 of docs/ref/explore-layers-autofill.md): a Prepare of a layer the
# store does not hold, whose labels name its image (the CRI passes them
# when disable_snapshot_annotations is false, Plan.with_layers.v3),
# asks the host's filler to put the layer in the store
# (src/layers/ask.bend Ask.of_labels.v2, host/snapshot_ask.bend) and
# waits at most Ask.wait.max.v2 (60 s). The wait must not stop the
# other calls (a Stat or Mounts of a running pod), so it does not run
# in the loop. The loop reads one channel of events (SnEv): Snapd.pump
# moves each call of the gRPC server there, and a Prepare that asks is
# handed to a computation of its own (IO.spawn, Snapd.asked), which
# asks, waits, and then puts the Prepare back on the channel
# (EvAsked). The loop goes on with the next event at once. When the
# Prepare comes back, the loop probes the store again (test -d) and
# runs the Prepare as it runs one without an ask, on the state as it is
# then: the state stays a value that only the loop changes, and the
# Prepare is answered as if it came in at that time. containerd sends
# nothing more for that key until its Prepare is answered. A "no", no
# reply in time, a refused connection, a reply that is not one, or a
# Prepare that does not ask (no CRI labels, as for `ctr images import`,
# or a registry the image cache does not serve) all end in the same
# probe, and a layer still missing is unpacked on the node as before:
# a pull never fails because of the ask. After
# a call that changes it, the state goes to ROOT/state
# (src/layers/state.bend) through ROOT/state.tmp and a rename; after
# one that takes or lets go a shared layer, the node's held layers go to
# HELD on its share for the host's store. Directories are made before
# the answer and removed after the state is saved.
#
# Shell use, all through busybox with arguments, no quoting: mkdir -p,
# rm -rf, mv -f, test -d, ls, and one `sh -c` that measures a directory
# (Spb.measure_args): Bend has no directory effects in Base, and find's
# output would be the whole tree in memory. A shared layer is not
# measured: its Usage comes from the record its fill published,
# /mnt/layers/<hex>.rec (Spb.rec.probe, Spb.uses, S.Sn.apply.v2); only a
# layer an older vk8s filled, with no such record, is. List applies its
# filters (Spb.request.v2, OWalk).

type SnCfg is Data:
  SnCfg{sock: String, root: String, held: String}

# What the loop takes, one at a time: a call off the gRPC server
# (Snapd.pump), or a Prepare back from its ask to the host's filler
# (Snapd.asked), to be probed again and answered.
type SnEv is Data:
  EvCall{call: R.GCall}
  EvAsked{op: S.Op, name: String, t0: Nat, k: R.GSink}

def Snapd.say(+s: String) -> IO(Unit):
  IO.print("vk8s-snapshotter: " ++ s)

# Timing for snapshotter.log: IO.now is a millisecond clock.
def Snapd.ms(t0: Nat, t1: Nat) -> String:
  Nat.show(Nat.sub(t1, t0))

def Snapd.last(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, Nil{}}:
      x
    case Con{x, t}:
      Snapd.last(t)

def Snapd.argv(xs: List<&2, String>) -> List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      Con{x, Snapd.argv(t)}

def Snapd.ran(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> Maybe<&2, String>:
  match r:
    case Fail{(c, m)}:
      None{}
    case Done{(st, (out, err))}:
      Bool.pick(Maybe<&2, String>, U32.is_eq(st, 0), Some{out}, None{})

# busybox with args: its output when it exits 0. Logs the applet, the
# last argument and the time the spawn took.
def Snapd.bb(+args: List<&2, String>) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    t0 : Nat <- IO.now()
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/bin/busybox", Snapd.argv(args), "", 16777216, 600000)
    t1 : Nat <- IO.now()
    Snapd.say("busybox " ++ Maybe.default(&2, String, List.head(&2, String, args), "") ++ " " ++ Snapd.last(args) ++ " ms=" ++ Snapd.ms(t0, t1))
    return Snapd.ran(r)

def Snapd.bb_ok(args: List<&2, String>) -> IO(Bool):
  do IO<Bool>:
    m : Maybe<&2, String> <- Snapd.bb(args)
    return Maybe.is_some(&2, String, m)

def Snapd.unless(ok: Bool, act: IO(Unit)) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      act

# busybox cmd on the paths, when there are any.
def Snapd.each(+cmd: List<&2, String>, ps: List<&2, String>) -> IO(Unit):
  match ps:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{p, t}:
      do IO<Unit>:
        ok : Bool <- Snapd.bb_ok(List.append(&2, String, cmd, Con{p, t}))
        Snapd.unless(ok, Snapd.say(String.join(cmd, " ") ++ " failed"))

# Files
# -----

def Snapd.read.close(p: File & Result<&1, &1, U32 & String, String>) -> IO(String):
  match p:
    case (f, Done{s}):
      do IO<String>:
        File.close(f)
        return s
    case (f, Fail{e}):
      do IO<String>:
        File.close(f)
        return ""

def Snapd.read.go(r: Result<&1, &1, U32 & String, File>) -> IO(String):
  match r:
    case Fail{e}:
      IO.pure(String, "")
    case Done{f}:
      do IO<String>:
        p : File & Result<&1, &1, U32 & String, String> <- File.read(f, 67108864)
        Snapd.read.close(p)

def Snapd.read(+path: String) -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    Snapd.read.go(r)

def Snapd.write.close(p: File & Result<&1, &1, U32 & String, Unit>) -> IO(Bool):
  match p:
    case (f, Done{u}):
      do IO<Bool>:
        File.close(f)
        return True{}
    case (f, Fail{e}):
      do IO<Bool>:
        File.close(f)
        return False{}

def Snapd.write.go(r: Result<&1, &1, U32 & String, File>, +text: String) -> IO(Bool):
  match r:
    case Fail{e}:
      IO.pure(Bool, False{})
    case Done{f}:
      do IO<Bool>:
        p : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, text)
        Snapd.write.close(p)

def Snapd.place.go(ok: Bool, +tmp: String, +path: String) -> IO(Bool):
  match ok:
    case True{}:
      Snapd.bb_ok(["mv", "-f", tmp, path])
    case False{}:
      IO.pure(Bool, False{})

# text at path, whole or not at all: written to path.tmp, renamed over it.
# Logs the size and the time of the write and the rename.
def Snapd.place(+path: String, +text: String) -> IO(Unit):
  do IO<Unit>:
    +tmp : String = path ++ ".tmp"
    t0 : Nat <- IO.now()
    r : Result<&1, &1, U32 & String, File> <- File.open(tmp, "w")
    ok : Bool <- Snapd.write.go(r, text)
    placed : Bool <- Snapd.place.go(ok, tmp, path)
    t1 : Nat <- IO.now()
    Snapd.say("wrote " ++ path ++ " bytes=" ++ Nat.show(String.length(text)) ++ " ms=" ++ Snapd.ms(t0, t1))
    Snapd.unless(placed, Snapd.say("could not write " ++ path))

# State
# -----

def Snapd.save(dirty: Bool, +c: SnCfg, sn: S.Sn) -> IO(Unit):
  match dirty c:
    case True{} SnCfg{s, +root, h}:
      do IO<Unit>:
        t0 : Nat <- IO.now()
        +text : String = T.Sst.show(sn)
        +n : Nat = String.length(text)
        t1 : Nat <- IO.now()
        Snapd.say("state rendered bytes=" ++ Nat.show(n) ++ " ms=" ++ Snapd.ms(t0, t1))
        Snapd.place(root ++ "/state", text)
    case False{} x:
      IO.pure(Unit, Unit{})

def Snapd.hold(touch: Bool, +c: SnCfg, sn: S.Sn) -> IO(Unit):
  match touch c:
    case True{} SnCfg{s, r, +held}:
      Snapd.place(held, B.Spb.held(sn))
    case False{} x:
      IO.pure(Unit, Unit{})

def SnCfg.root(c: SnCfg) -> String:
  match c:
    case SnCfg{s, r, h}:
      r

# The saved state, or a fresh one with <root>/snapshots emptied: no
# snapshot names its directories.
def Snapd.loaded(m: Maybe<&2, S.Sn>, +root: String, +node: String) -> IO(S.Sn):
  match m:
    case Some{sn}:
      do IO<S.Sn>:
        Snapd.say("state loaded from " ++ root ++ "/state")
        return sn
    case None{}:
      do IO<S.Sn>:
        Snapd.say("no state at " ++ root ++ "/state: starting afresh")
        a : Bool <- Snapd.bb_ok(["rm", "-rf", root ++ "/snapshots"])
        b : Bool <- Snapd.bb_ok(["mkdir", "-p", root ++ "/snapshots"])
        return S.Sn.new(root, node)

# Calls
# -----

def Snapd.now.of(w: U32 & (U32 & U32)) -> U32:
  match w:
    case (d, (s, us)):
      B.Spb.epoch(d, s)

def Snapd.now() -> IO(U32):
  IO.bind(U32 & (U32 & U32), U32, Y.Sys.wall(), w => IO.pure(U32, Snapd.now.of(w)))

def Snapd.found.of(m: Maybe<&2, String>) -> List<&2, String>:
  match m:
    case None{}:
      Nil{}
    case Some{out}:
      B.Spb.names(out)

# The directories under <root>/snapshots, for Cleanup.
def Snapd.found(cleanup: Bool, +root: String) -> IO(List<&2, String>):
  match cleanup:
    case True{}:
      do IO<List<&2, String>>:
        m : Maybe<&2, String> <- Snapd.bb(["ls", "-1", root ++ "/snapshots"])
        return Snapd.found.of(m)
    case False{}:
      IO.pure(List<&2, String>, Nil{})

def Snapd.uses.said(us: List<&2, S.LUse>) -> String:
  match us:
    case Con{S.LUse{c, s, n}, t}:
      "recorded"
    case _:
      "no record, measuring"

# The usage recorded for the shared layer a Usage call names (its
# record's copy in the node; none when it has none, Spb.uses).
def Snapd.uses(+m: Maybe<&2, B.SpProbe>) -> IO(List<&2, S.LUse>):
  match m:
    case None{}:
      IO.pure(List<&2, S.LUse>, Nil{})
    case Some{B.SpProbe{+c, +d}}:
      do IO<List<&2, S.LUse>>:
        text : String <- Snapd.read(Maybe.default(&2, String, LF.Fill.rec.mount.v3(c), d))
        +us : List<&2, S.LUse> = B.Spb.uses(Some{B.SpProbe{c, d}}, text)
        Snapd.say("usage of " ++ c ++ ": " ++ Snapd.uses.said(us))
        return us

# A layer image (v3, docs/ref/layers-sqfs.md): layer c mounted at
# /mnt/layers/<hex> (Lay.mount) from the store's share
# (/mnt/layers-store): its image on a loop device, or a bind of a
# directory an older store left. Whether it is mounted now.
def Snapd.ensure.dir(dir: Bool, +c: String) -> IO(Bool):
  match dir:
    case True{}:
      do IO<Bool>:
        made : Bool <- Snapd.bb_ok(["mkdir", "-p", Maybe.default(&2, String, LY.Lay.mount(c), "")])
        Snapd.bb_ok(LY.Lay.mount_dir.v3(c))
    case False{}:
      IO.pure(Bool, False{})

def Snapd.ensure.img(img: Bool, +c: String) -> IO(Bool):
  match img:
    case True{}:
      do IO<Bool>:
        made : Bool <- Snapd.bb_ok(["mkdir", "-p", Maybe.default(&2, String, LY.Lay.mount(c), "")])
        Snapd.bb_ok(LY.Lay.mount_img.v3(c))
    case False{}:
      do IO<Bool>:
        dir : Bool <- Snapd.bb_ok(["test", "-d", Maybe.default(&2, String, LY.Lay.store_dir.v3(c), "")])
        Snapd.ensure.dir(dir, c)

def Snapd.ensure.go(mounted: Bool, +c: String) -> IO(Bool):
  match mounted:
    case True{}:
      IO.pure(Bool, True{})
    case False{}:
      do IO<Bool>:
        img : Bool <- Snapd.bb_ok(["test", "-f", Maybe.default(&2, String, LY.Lay.store_img.v3(c), "")])
        Snapd.ensure.img(img, c)

def Snapd.ensure(+c: String) -> IO(Bool):
  do IO<Bool>:
    m : Bool <- Snapd.bb_ok(["mountpoint", "-q", Maybe.default(&2, String, LY.Lay.mount(c), "")])
    Snapd.ensure.go(m, c)

# Every layer the node's snapshots stand for, mounted again (a boot
# empties the tmpfs at /mnt/layers).
def Snapd.ensure.all(cs: List<&2, String>) -> IO(Unit):
  match cs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+c, t}:
      do IO<Unit>:
        ok : Bool <- Snapd.ensure(c)
        Snapd.say("layer " ++ c ++ Bool.pick(String, ok, " mounted", " not in the store"))
        Snapd.ensure.all(t)

# The shared layer a Prepare names, when the store has it: mounted at
# its directory (Snapd.ensure).
def Snapd.have(+m: Maybe<&2, B.SpProbe>) -> IO(List<&2, String>):
  match m:
    case None{}:
      IO.pure(List<&2, String>, Nil{})
    case Some{B.SpProbe{+c, +d}}:
      do IO<List<&2, String>>:
        ok : Bool <- Snapd.ensure(c)
        return B.Spb.have(Some{B.SpProbe{c, d}}, ok)

def Snapd.sends(ms: List<&2, List<&2, U32>>, k: R.GSink) -> IO(R.GSink):
  match ms:
    case Nil{}:
      IO.pure(R.GSink, k)
    case Con{m, t}:
      do IO<R.GSink>:
        k2 : R.GSink <- R.Grpc.send(k, m)
        Snapd.sends(t, k2)

# An answer that needs no measure.
def Snapd.reply(a: B.SpAns, k: R.GSink) -> IO(Unit):
  match a:
    case B.AnReply{msg}:
      R.Grpc.reply(k, Done{msg})
    case B.AnStream{msgs}:
      do IO<Unit>:
        k2 : R.GSink <- Snapd.sends(msgs, k)
        R.Grpc.finish(k2, G.GStatus{0, ""})
    case B.AnStatus{code, msg}:
      R.Grpc.finish(k, G.GStatus{code, msg})
    case B.AnMeasure{p}:
      R.Grpc.finish(k, G.GStatus{G.Grpc.internal(), "usage: measured twice"})

def Snapd.measured(m: Maybe<&2, String>) -> B.SpAns:
  match m:
    case None{}:
      B.AnStatus{G.Grpc.internal(), "usage: could not measure"}
    case Some{out}:
      B.Spb.measured(out)

def Snapd.answer(a: B.SpAns, k: R.GSink) -> IO(Unit):
  match a:
    case B.AnMeasure{+p}:
      do IO<Unit>:
        m : Maybe<&2, String> <- Snapd.bb(B.Spb.measure_args(p))
        Snapd.reply(Snapd.measured(m), k)
    case other:
      Snapd.reply(other, k)

# A call's effects, in order, then its answer: the state that follows.
def Snapd.done(o: S.Out, +dirty: Bool, k: R.GSink, +c: SnCfg) -> IO(S.Sn):
  match o:
    case S.Out{+sn, res, +acts}:
      do IO<S.Sn>:
        Snapd.each(["mkdir", "-p"], B.Spb.mkdirs(acts))
        Snapd.save(dirty, c, sn)
        Snapd.hold(B.Spb.touches(acts), c, sn)
        Snapd.each(["rm", "-rf"], B.Spb.removes(acts))
        Snapd.answer(B.Spb.answer(res), k)
        return sn

# One line per call in snapshotter.log: the method, the key, the wall
# time from the call off the channel to the answer sent, and how many
# snapshots the state holds after it.
def Snapd.log(+name: String, +key: String, t0: Nat, +sn: S.Sn) -> IO(S.Sn):
  do IO<S.Sn>:
    t1 : Nat <- IO.now()
    +count : Nat = List.length(&2, S.Snap, S.Sn.snaps(sn))
    Snapd.say("call " ++ name ++ " key=" ++ key ++ " ms=" ++ Snapd.ms(t0, t1) ++ " snaps=" ++ Nat.show(count))
    return sn

# The rest of a call once its shared layer is probed (have): Cleanup's
# directories, a Usage's record, the clock, the decision, its effects
# and its answer.
def Snapd.run(+op: S.Op, +name: String, t0: Nat, k: R.GSink, +c: SnCfg, +sn: S.Sn, have: List<&2, String>) -> IO(S.Sn):
  do IO<S.Sn>:
    found : List<&2, String> <- Snapd.found(B.Spb.is_cleanup(op), SnCfg.root(c))
    us : List<&2, S.LUse> <- Snapd.uses(B.Spb.rec.probe(sn, op))
    +now : U32 <- Snapd.now()
    +dirty : Bool = B.Spb.dirty(op)
    sn2 : S.Sn <- Snapd.done(S.Sn.apply.v2(sn, B.Spb.fill(op, found), have, us, now), dirty, k, c)
    Snapd.log(name, B.Spb.key(op), t0, sn2)

# Whether the store holds the shared layer a Prepare names (test -d);
# False for any other call.
def Snapd.present(+m: Maybe<&2, B.SpProbe>) -> IO(Bool):
  match m:
    case None{}:
      IO.pure(Bool, False{})
    case Some{B.SpProbe{c, +d}}:
      Snapd.bb_ok(["test", "-d", d])

def Snapd.env_or(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Fail{e}:
      ""
    case Done{v}:
      v

# The filler's address: VK8S_LAYERS_ASK from PID 1's environment (a node
# container's bridge gateway), else the VM's 10.0.2.2 (A.Ask.host.v3).
def Snapd.ask_host() -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env("VK8S_LAYERS_ASK")
    return A.Ask.host.v3(Snapd.env_or(r))

# The ask's own computation: ask the host's filler and wait at most
# Ask.wait.max.v2 (host/snapshot_ask.bend), log what came of it, then
# hand the Prepare back to the loop, which probes the store again and
# answers it (Snapd.resume). Whatever came of the ask, the Prepare goes
# back: a "no", no reply, a refused connection all end in the local
# unpack.
def Snapd.asked(a: A.Ask, +op: S.Op, +name: String, t0: Nat, k: R.GSink, +evs: Chan(SnEv)) -> IO(Unit):
  do IO<Unit>:
    t1 : Nat <- IO.now()
    +host : String <- Snapd.ask_host()
    r : Result<&2, &2, String, A.Reply> <- SA.SnAsk.ask(host, A.Ask.port.v2(), A.Ask.wait.ms.v2(), a)
    t2 : Nat <- IO.now()
    Snapd.say("ask for " ++ name ++ " key=" ++ B.Spb.key(op) ++ ": " ++ A.Ask.said.v2(r) ++ " ms=" ++ Snapd.ms(t1, t2))
    s : Result<&1, &1, SnEv, Unit> <- Chan.send(SnEv, evs, EvAsked{op, name, t0, k})
    return Unit{}

# A Prepare of a layer the store does not hold, with the CRI's labels
# (Ask.of_labels.v2), asks the filler in a computation of its own and
# leaves the state as it is: the loop takes the next call at once, and
# the Prepare is answered when the ask ends. Any other call goes on now,
# with the probe it has.
def Snapd.asks(m: Maybe<&2, A.Ask>, +ok: Bool, +op: S.Op, +name: String, t0: Nat, k: R.GSink, +evs: Chan(SnEv), +c: SnCfg, +sn: S.Sn) -> IO(S.Sn):
  match m:
    case None{}:
      Snapd.run(op, name, t0, k, c, sn, B.Spb.have(B.Spb.probe(op), ok))
    case Some{+a}:
      do IO<S.Sn>:
        +host : String <- Snapd.ask_host()
        Snapd.say("ask for " ++ name ++ " key=" ++ B.Spb.key(op) ++ ": " ++ String.trim(A.Ask.render.v2(a)) ++ " to "
          ++ host ++ ":" ++ U32.show(A.Ask.port.v2()))
        IO.spawn(Unit, Snapd.asked(a, op, name, t0, k, evs))
        return sn

def Snapd.apply(+op: S.Op, +name: String, t0: Nat, k: R.GSink, +evs: Chan(SnEv), +c: SnCfg, +sn: S.Sn) -> IO(S.Sn):
  do IO<S.Sn>:
    +ok : Bool <- Snapd.present(B.Spb.probe(op))
    Snapd.asks(A.Ask.of_labels.v2(op, ok), ok, op, name, t0, k, evs, c, sn)

# A Prepare back from its ask: the store probed again (test -d), then
# the call as without an ask. A layer the filler published (or another
# node's fill did) is answered AlreadyExists; any other is unpacked on
# the node.
def Snapd.resume(+op: S.Op, +name: String, t0: Nat, k: R.GSink, +c: SnCfg, +sn: S.Sn) -> IO(S.Sn):
  do IO<S.Sn>:
    have : List<&2, String> <- Snapd.have(B.Spb.probe(op))
    Snapd.run(op, name, t0, k, c, sn, have)

def Snapd.decoded(r: Result<&2, &2, String, S.Op>, +name: String, t0: Nat, k: R.GSink, +evs: Chan(SnEv), +c: SnCfg, sn: S.Sn) -> IO(S.Sn):
  match r:
    case Fail{e}:
      do IO<S.Sn>:
        R.Grpc.finish(k, G.GStatus{G.Grpc.invalid_argument(), e})
        Snapd.log(name, "(bad request)", t0, sn)
    case Done{+op}:
      Snapd.apply(op, name, t0, k, evs, c, sn)

def Snapd.call(mm: Maybe<&2, B.SpMeth>, +name: String, t0: Nat, msg: List<&2, U32>, k: R.GSink, +evs: Chan(SnEv), +c: SnCfg, sn: S.Sn) -> IO(S.Sn):
  match mm:
    case None{}:
      do IO<S.Sn>:
        R.Grpc.finish(k, G.GStatus{G.Grpc.unimplemented(), "unknown method"})
        Snapd.log(name, "(unknown method)", t0, sn)
    case Some{m}:
      Snapd.decoded(B.Spb.request.v2(m, msg), name, t0, k, evs, c, sn)

def Snapd.take(call: R.GCall, +evs: Chan(SnEv), +c: SnCfg, sn: S.Sn) -> IO(S.Sn):
  match call:
    case R.GCall{+method, md, msg, ms, k}:
      do IO<S.Sn>:
        t0 : Nat <- IO.now()
        Snapd.call(B.Spb.method(method), String.drop(method, 44n), t0, msg, k, evs, c, sn)

def Snapd.event(m: Maybe<&1, SnEv>, +evs: Chan(SnEv), +c: SnCfg, sn: S.Sn) -> IO(S.Sn):
  match m:
    case None{}:
      IO.pure(S.Sn, sn)
    case Some{EvCall{call}}:
      Snapd.take(call, evs, c, sn)
    case Some{EvAsked{op, name, t0, k}}:
      Snapd.resume(op, name, t0, k, c, sn)

# Takes the events off evs one at a time, the state carried along: the
# calls (from Snapd.pump) and the Prepares back from their asks.
def Snapd.loop(outer: Nat, fuel: Nat, +evs: Chan(SnEv), +c: SnCfg, sn: S.Sn) -> IO(Unit):
  match outer fuel:
    case 0n 0n:
      IO.pure(Unit, Unit{})
    case 1n+o 0n:
      Snapd.loop(o, I.H2io.fuel(), evs, c, sn)
    case o 1n+f:
      do IO<Unit>:
        m : Maybe<&1, SnEv> <- Chan.recv(SnEv, evs)
        +sn2 : S.Sn <- Snapd.event(m, evs, c, sn)
        Snapd.loop(o, f, evs, c, sn2)

def Snapd.pumped(m: Maybe<&1, R.GCall>, +evs: Chan(SnEv), next: IO(Unit)) -> IO(Unit):
  match m:
    case None{}:
      IO.pure(Unit, Unit{})
    case Some{call}:
      do IO<Unit>:
        s : Result<&1, &1, SnEv, Unit> <- Chan.send(SnEv, evs, EvCall{call})
        next

# Moves the gRPC server's calls onto evs, in order, so that the loop
# reads one channel for both kinds of event.
def Snapd.pump(outer: Nat, fuel: Nat, +calls: Chan(R.GCall), +evs: Chan(SnEv)) -> IO(Unit):
  match outer fuel:
    case 0n 0n:
      IO.pure(Unit, Unit{})
    case 1n+o 0n:
      Snapd.pump(o, I.H2io.fuel(), calls, evs)
    case o 1n+f:
      do IO<Unit>:
        m : Maybe<&1, R.GCall> <- Chan.recv(R.GCall, calls)
        Snapd.pumped(m, evs, Snapd.pump(o, f, calls, evs))

def Snapd.listening(r: Result<&1, &1, U32 & String, Listener>, +c: SnCfg, sn: S.Sn) -> IO(Unit):
  match r:
    case Fail{(code, m)}:
      IO.die(Unit, 1, "vk8s-snapshotter: cannot listen: " ++ m)
    case Done{l}:
      do IO<Unit>:
        +calls : Chan(R.GCall) <- Chan.new(R.GCall, 256)
        +evs : Chan(SnEv) <- Chan.new(SnEv, 256)
        IO.spawn(Unit, Snapd.pump(I.H2io.fuel(), I.H2io.fuel(), calls, evs))
        IO.spawn(Unit, Snapd.loop(I.H2io.fuel(), I.H2io.fuel(), evs, c, sn))
        Snapd.say("serving containerd.services.snapshots.v1.Snapshots")
        R.Grpc.serve(l, calls)

def Snapd.node(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Fail{e}:
      "node"
    case Done{+n}:
      Bool.pick(String, String.is_empty(n), "node", n)

# In a node container on the store (src/guest/plan.bend
# Plan.with_layers.v5), the runtime binds the host's /dev at
# PL.Plan.hostdev.v5: link /dev/loop-control and /dev/loop0..4095 to it
# (one busybox ln, argv only) before any layer is mounted, so busybox's
# mount -o loop finds the loop device the kernel gives it. A VM node has
# its own devtmpfs and no such bind: nothing to do.
def Snapd.loop_links.go(bound: Bool) -> IO(Unit):
  match bound:
    case False{}:
      IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        ok : Bool <- Snapd.bb_ok(PL.Plan.loop_links_args.v5())
        Snapd.say(Bool.pick(String, ok, "loop devices linked to the host's", "warning: could not link the host's loop devices"))

def Snapd.loop_links() -> IO(Unit):
  do IO<Unit>:
    bound : Bool <- Snapd.bb_ok(["test", "-d", PL.Plan.hostdev.v5()])
    Snapd.loop_links.go(bound)

def Snapd.start(+sock: String, +root: String, +held: String) -> IO(Unit):
  do IO<Unit>:
    Snapd.loop_links()
    made : Bool <- Snapd.bb_ok(["mkdir", "-p", root ++ "/snapshots", "/run/vk8s"])
    rn : Result<&1, &1, U32 & String, String> <- IO.get_env("VK8S_NAME")
    +node : String = Snapd.node(rn)
    text : String <- Snapd.read(root ++ "/state")
    +sn : S.Sn <- Snapd.loaded(T.Sst.read(root, node, text), root, node)
    Snapd.ensure.all(S.Sn.layers.v3(sn))
    r : Result<&1, &1, U32 & String, Listener> <- Y.Sys.unix_listen(sock, 384)
    Snapd.listening(r, SnCfg{sock, root, held}, sn)

# argv: [prog, "snapshotter", SOCKET, ROOT, HELD].
def Snapd.main(args: +List<String>) -> IO(Unit):
  match args:
    case Con{p, Con{m, Con{+sock, Con{+root, Con{+held, Nil{}}}}}}:
      Snapd.start(sock, root, held)
    case _:
      IO.die(Unit, 2, "usage: vk8s-guest snapshotter SOCKET ROOT HELD")
