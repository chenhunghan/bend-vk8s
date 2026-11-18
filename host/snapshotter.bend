import Base
import bend-kube-runtime@0.10.0.0/src/grpc.bend as G
import bend-kube-runtime@0.10.0.0/src/grpcio.bend as R
import bend-kube-runtime@0.10.0.0/src/h2io.bend as I
import bend-kube-runtime@0.10.0.0/src/sys.bend as Y
import ../src/layers/snap.bend as S
import ../src/layers/pb.bend as B
import ../src/layers/state.bend as T

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
# store's lock for each: the state is a value this loop carries. After
# a call that changes it, the state goes to ROOT/state
# (src/layers/state.bend) through ROOT/state.tmp and a rename; after
# one that takes or lets go a shared layer, the node's held layers go to
# HELD on its share for the host's store. Directories are made before
# the answer and removed after the state is saved.
#
# Shell use, all through busybox with arguments, no quoting: mkdir -p,
# rm -rf, mv -f, test -d, ls, and one `sh -c` that measures a directory
# (Spb.measure_args): Bend has no directory effects in Base, and find's
# output would be the whole tree in memory.

type SnCfg is Data:
  SnCfg{sock: String, root: String, held: String}

def Snapd.say(+s: String) -> IO(Unit):
  IO.print("vk8s-snapshotter: " ++ s)

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

# busybox with args: its output when it exits 0.
def Snapd.bb(args: List<&2, String>) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/bin/busybox", Snapd.argv(args), "", 16777216, 600000)
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
def Snapd.place(+path: String, +text: String) -> IO(Unit):
  do IO<Unit>:
    +tmp : String = path ++ ".tmp"
    r : Result<&1, &1, U32 & String, File> <- File.open(tmp, "w")
    ok : Bool <- Snapd.write.go(r, text)
    placed : Bool <- Snapd.place.go(ok, tmp, path)
    Snapd.unless(placed, Snapd.say("could not write " ++ path))

# State
# -----

def Snapd.save(dirty: Bool, +c: SnCfg, sn: S.Sn) -> IO(Unit):
  match dirty c:
    case True{} SnCfg{s, +root, h}:
      Snapd.place(root ++ "/state", T.Sst.show(sn))
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

# The shared layer a Prepare names, when the store has it.
def Snapd.have(+m: Maybe<&2, B.SpProbe>) -> IO(List<&2, String>):
  match m:
    case None{}:
      IO.pure(List<&2, String>, Nil{})
    case Some{B.SpProbe{c, +d}}:
      do IO<List<&2, String>>:
        ok : Bool <- Snapd.bb_ok(["test", "-d", d])
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

def Snapd.apply(+op: S.Op, k: R.GSink, +c: SnCfg, sn: S.Sn) -> IO(S.Sn):
  do IO<S.Sn>:
    found : List<&2, String> <- Snapd.found(B.Spb.is_cleanup(op), SnCfg.root(c))
    have : List<&2, String> <- Snapd.have(B.Spb.probe(op))
    +now : U32 <- Snapd.now()
    +dirty : Bool = B.Spb.dirty(op)
    Snapd.done(S.Sn.apply(sn, B.Spb.fill(op, found), have, now), dirty, k, c)

def Snapd.decoded(r: Result<&2, &2, String, S.Op>, k: R.GSink, +c: SnCfg, sn: S.Sn) -> IO(S.Sn):
  match r:
    case Fail{e}:
      do IO<S.Sn>:
        R.Grpc.finish(k, G.GStatus{G.Grpc.invalid_argument(), e})
        return sn
    case Done{+op}:
      Snapd.apply(op, k, c, sn)

def Snapd.call(mm: Maybe<&2, B.SpMeth>, msg: List<&2, U32>, k: R.GSink, +c: SnCfg, sn: S.Sn) -> IO(S.Sn):
  match mm:
    case None{}:
      do IO<S.Sn>:
        R.Grpc.finish(k, G.GStatus{G.Grpc.unimplemented(), "unknown method"})
        return sn
    case Some{m}:
      Snapd.decoded(B.Spb.request(m, msg), k, c, sn)

def Snapd.take(m: Maybe<&1, R.GCall>, +c: SnCfg, sn: S.Sn) -> IO(S.Sn):
  match m:
    case None{}:
      IO.pure(S.Sn, sn)
    case Some{R.GCall{+method, md, msg, ms, k}}:
      Snapd.call(B.Spb.method(method), msg, k, c, sn)

# Takes the calls off calls one at a time, the state carried along.
def Snapd.loop(outer: Nat, fuel: Nat, +calls: Chan(R.GCall), +c: SnCfg, sn: S.Sn) -> IO(Unit):
  match outer fuel:
    case 0n 0n:
      IO.pure(Unit, Unit{})
    case 1n+o 0n:
      Snapd.loop(o, I.H2io.fuel(), calls, c, sn)
    case o 1n+f:
      do IO<Unit>:
        m : Maybe<&1, R.GCall> <- Chan.recv(R.GCall, calls)
        +sn2 : S.Sn <- Snapd.take(m, c, sn)
        Snapd.loop(o, f, calls, c, sn2)

def Snapd.listening(r: Result<&1, &1, U32 & String, Listener>, +c: SnCfg, sn: S.Sn) -> IO(Unit):
  match r:
    case Fail{(code, m)}:
      IO.die(Unit, 1, "vk8s-snapshotter: cannot listen: " ++ m)
    case Done{l}:
      do IO<Unit>:
        +calls : Chan(R.GCall) <- Chan.new(R.GCall, 256)
        IO.spawn(Unit, Snapd.loop(I.H2io.fuel(), I.H2io.fuel(), calls, c, sn))
        Snapd.say("serving containerd.services.snapshots.v1.Snapshots")
        R.Grpc.serve(l, calls)

def Snapd.node(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Fail{e}:
      "node"
    case Done{+n}:
      Bool.pick(String, String.is_empty(n), "node", n)

def Snapd.start(+sock: String, +root: String, +held: String) -> IO(Unit):
  do IO<Unit>:
    made : Bool <- Snapd.bb_ok(["mkdir", "-p", root ++ "/snapshots", "/run/vk8s"])
    rn : Result<&1, &1, U32 & String, String> <- IO.get_env("VK8S_NAME")
    +node : String = Snapd.node(rn)
    text : String <- Snapd.read(root ++ "/state")
    +sn : S.Sn <- Snapd.loaded(T.Sst.read(root, node, text), root, node)
    r : Result<&1, &1, U32 & String, Listener> <- Y.Sys.unix_listen(sock, 384)
    Snapd.listening(r, SnCfg{sock, root, held}, sn)

# argv: [prog, "snapshotter", SOCKET, ROOT, HELD].
def Snapd.main(args: +List<String>) -> IO(Unit):
  match args:
    case Con{p, Con{m, Con{+sock, Con{+root, Con{+held, Nil{}}}}}}:
      Snapd.start(sock, root, held)
    case _:
      IO.die(Unit, 2, "usage: vk8s-guest snapshotter SOCKET ROOT HELD")
