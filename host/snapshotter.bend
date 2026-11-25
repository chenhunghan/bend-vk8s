import Base
import bend-kube-runtime@0.12.0.0/src/grpc.bend as G
import bend-kube-runtime@0.12.0.0/src/grpcio.bend as R
import bend-kube-runtime@0.12.0.0/src/h2io.bend as I
import bend-kube-runtime@0.12.0.0/src/sys.bend as Y
import ../src/layers/snap.bend as S
import ../src/layers/pb.bend as B
import ../src/layers/state.bend as T
import ../src/layers/ask.bend as A
import ../src/layers/store.bend as LY
import ../src/layers/fill.bend as LF
import ./snapshot_ask.bend as SA
import ../src/guest/plan.bend as PL
import ../src/layers/pack.bend as K
import ../src/layers/place.bend as PC
import ./gsys.bend as GS
import ../src/guest/sysop.bend as SO

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
# a pull never fails because of the ask. A small layer image the
# Prepare mounts is read once before the Prepare is answered
# (Snapd.warm; src/layers/pb.bend Spb.warm.v6), in a computation of its
# own, and the Prepare comes back on the channel with the layer it holds
# (EvWarmed), to be answered at once. After
# a call that changes it, the state goes to ROOT/state
# (src/layers/state.bend) through ROOT/state.tmp and a rename; after
# one that takes or lets go a shared layer, the node's held layers go to
# HELD on its share for the host's store. Directories are made before
# the answer and removed after the state is saved.
#
# The pack (src/layers/pack.bend; docs/STATUS.md "The pack disk"): on a
# VM the host started with a pack (VK8S_PACK=<vm> in the environment, a
# virtio-blk disk whose serial is K.Pack.name.v7, a key in the share), a
# layer image the store holds is not mounted from the share: the
# snapshotter asks the filler to put it on the VM's pack (one line, at
# most K.Pack.wait.ms.v7; Snapd.pack.mount) and mounts the place it is
# told through a loop device with that offset and size limit
# (PackDev.mount, host/effs/pack_loop.c). No answer, a no (an older
# filler, a VM without a pack), or a failed mount ends in the mount from
# the share. The share stays for the store's probes (test -f), the
# layers' records and that fall back. When a call lets a layer go and no
# snapshot stands on it any more (K.Pack.gone.v7), the layer is
# unmounted, its mount point removed, and the filler told to end its
# entry (a line sent in a computation of its own; the filler drops only
# what this VM's key asks for). A Prepare that mounted a layer and then
# did not take it (its parent was missing) unmounts it the same way.
# Without a pack none of this runs, and a layer stays mounted until the
# node stops, as before.
#
# No process per call (docs/GOAL.md section 11, "Fewer shell-outs"). What
# was a busybox process each time (mkdir -p, rm -rf, mv -f, test -d,
# test -f, ls, mount, mountpoint, umount, rmdir, the tar that read a
# small layer image to /dev/null, and the `sh -c` of du and find that
# measured a directory) is now the guest's system calls
# (host/gsys.bend; src/guest/sysop.bend decides): a pod start, a Usage
# and a Remove spawn nothing. busybox stays for two things: the loop
# links of a node container, once when the snapshotter starts
# (Snapd.loop_links: 4097 links in one process), and the mount of a
# layer image from the share when the kernel refuses the loop effect
# (LoopDev.mount needs LOOP_CONFIGURE, Linux 5.8). A shared layer is not
# measured: its Usage comes from the record its fill published,
# /mnt/layers/<hex>.rec (Spb.rec.probe, Spb.uses, S.Sn.apply.v2); only a
# layer an older vk8s filled, with no such record, is. List applies its
# filters (Spb.request.v2, OWalk).

type SnCfg is Data:
  SnCfg{sock: String, root: String, held: String, vm: String, key: String, dev: String, place: PC.Place}

# Mounts length bytes at offset (decimal) of the block device dev as a
# read-only squashfs at target, through a loop device with that offset
# and size limit: 0, or the errno (host/effs/pack_loop.c).
def PackDev.mount(dev: String, off: String, len: String, target: String) -> IO(U32):
  import "./effs/pack_loop.c"
  import "./effs/pack_loop.js"

# Mounts the regular file image, whole, as a read-only, nosuid squashfs
# at target through a free loop device (autoclear), as busybox's `mount
# -t squashfs -o loop,ro,nosuid` does: 0, or the errno
# (host/effs/pack_loop.c).
def LoopDev.mount(image: String, target: String) -> IO(U32):
  import "./effs/pack_loop.c"
  import "./effs/pack_loop.js"

# What the loop takes, one at a time: a call off the gRPC server
# (Snapd.pump), or a Prepare back from its ask to the host's filler
# (Snapd.asked), to be probed again and answered, or a Prepare back from
# the read of the layer it mounted (Snapd.warm.back), to be answered.
type SnEv is Data:
  EvCall{call: R.GCall}
  EvAsked{op: S.Op, name: String, t0: Nat, k: R.GSink}
  EvWarmed{op: S.Op, name: String, t0: Nat, k: R.GSink, have: List<&2, String>}

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

# mkdir -p of the paths (GS.Gs.mkdirs), when there are any.
def Snapd.mkdirs(ps: List<&2, String>) -> IO(Unit):
  match ps:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{p, t}:
      do IO<Unit>:
        ok : Bool <- GS.Gs.mkdirs(Con{p, t})
        Snapd.unless(ok, Snapd.say("mkdir -p failed"))

# rm -rf of the paths (GS.Gs.rm_rf), each whatever the others answer.
def Snapd.removes(ps: List<&2, String>) -> IO(Unit):
  match ps:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+p, t}:
      do IO<Unit>:
        ok : Bool <- GS.Gs.rm_rf(p)
        Snapd.unless(ok, Snapd.say("rm -rf " ++ p ++ " failed"))
        Snapd.removes(t)

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
      GS.Gs.rename(tmp, path)
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
    case True{} SnCfg{s, +root, h, vm, key, dev, pl}:
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
    case True{} SnCfg{s, r, +held, vm, key, dev, pl}:
      Snapd.place(held, B.Spb.held(sn))
    case False{} x:
      IO.pure(Unit, Unit{})

def SnCfg.root(c: SnCfg) -> String:
  match c:
    case SnCfg{s, r, h, vm, key, dev, pl}:
      r

# The VM's name for the pack; "" on a node without one.
def SnCfg.vm(c: SnCfg) -> String:
  match c:
    case SnCfg{s, r, h, vm, key, dev, pl}:
      vm

def SnCfg.packed(c: SnCfg) -> Bool:
  Bool.not(String.is_empty(SnCfg.vm(c)))

# Where this node keeps the store and its layers' mounts
# (src/layers/place.bend): a VM node's and a node container's own
# /mnt/layers-store and /mnt/layers, or a native host node's.
def SnCfg.place(c: SnCfg) -> PC.Place:
  match c:
    case SnCfg{s, r, h, vm, key, dev, pl}:
      pl

# A path the pure code names (LY.Lay.mount, LY.Lay.store_img.v3, ...),
# as this node has it; "" when it names none.
def Snapd.at(+pl: PC.Place, m: Maybe<&2, String>) -> String:
  PC.Place.path(pl, Maybe.default(&2, String, m, ""))

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
        a : Bool <- GS.Gs.rm_rf(root ++ "/snapshots")
        b : Bool <- GS.Gs.mkdir_p(root ++ "/snapshots")
        return S.Sn.new(root, node)

# Calls
# -----

def Snapd.now.of(w: U32 & (U32 & U32)) -> U32:
  match w:
    case (d, (s, us)):
      B.Spb.epoch(d, s)

def Snapd.now() -> IO(U32):
  IO.bind(U32 & (U32 & U32), U32, Y.Sys.wall(), w => IO.pure(U32, Snapd.now.of(w)))

# The names `ls -1` printed: not those that start with a dot
# (SO.Sysop.listed).
def Snapd.found.names(ns: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}:
      Nil{}
    case Con{+n, t}:
      Bool.pick(List<&2, String> -> List<&2, String>, SO.Sysop.listed(n), r => Con{n, r}, r => r)(Snapd.found.names(t))

def Snapd.found.of(m: Maybe<&2, List<&2, String>>) -> List<&2, String>:
  match m:
    case None{}:
      Nil{}
    case Some{ns}:
      Snapd.found.names(ns)

# The directories under <root>/snapshots, for Cleanup.
def Snapd.found(cleanup: Bool, +root: String) -> IO(List<&2, String>):
  match cleanup:
    case True{}:
      do IO<List<&2, String>>:
        m : Maybe<&2, List<&2, String>> <- GS.Gs.ls(root ++ "/snapshots")
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
def Snapd.uses(+pl: PC.Place, +m: Maybe<&2, B.SpProbe>) -> IO(List<&2, S.LUse>):
  match m:
    case None{}:
      IO.pure(List<&2, S.LUse>, Nil{})
    case Some{B.SpProbe{+c, +d}}:
      do IO<List<&2, S.LUse>>:
        text : String <- Snapd.read(PC.Place.path(pl, Maybe.default(&2, String, LF.Fill.rec.mount.v3(c), d)))
        +us : List<&2, S.LUse> = B.Spb.uses(Some{B.SpProbe{c, d}}, text)
        Snapd.say("usage of " ++ c ++ ": " ++ Snapd.uses.said(us))
        return us

# The pack
# --------

def Snapd.pack.env(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Fail{e}:
      ""
    case Done{v}:
      v

# One line to the host's filler (the address the ask uses), its answer
# awaited at most K.Pack.wait.ms.v7.
def Snapd.pack.line(+line: String) -> IO(Result<&2, &2, String, String>):
  do IO<Result<&2, &2, String, String>>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env("VK8S_LAYERS_ASK")
    SA.SnAsk.text(A.Ask.host.v3(Snapd.pack.env(r)), A.Ask.port.v2(), K.Pack.wait.ms.v7(), line)

def Snapd.pack.said(r: Result<&2, &2, String, String>) -> String:
  match r:
    case Fail{e}:
      "no reply: " ++ e
    case Done{t}:
      String.trim(t)

def Snapd.pack.reply(r: Result<&2, &2, String, String>) -> Maybe<&2, K.PkReply>:
  match r:
    case Fail{e}:
      None{}
    case Done{+t}:
      K.Pack.reply.parse.v7(t)

def Snapd.pack.mounted(+code: U32, +ch: String) -> IO(Bool):
  do IO<Bool>:
    Snapd.say("layer " ++ ch ++ Bool.pick(String, U32.is_zero(code), " mounted from the pack", " not mounted from the pack: errno " ++ U32.show(code)))
    return U32.is_zero(code)

def Snapd.pack.at(m: Maybe<&2, K.PkReply>, +ch: String, +dev: String) -> IO(Bool):
  match m:
    case Some{K.PkAt{off, len}}:
      do IO<Bool>:
        +code : U32 <- PackDev.mount(dev, off, len, Maybe.default(&2, String, LY.Lay.mount(ch), ""))
        Snapd.pack.mounted(code, ch)
    case _:
      IO.pure(Bool, False{})

# Layer ch's image from the pack: the filler asked to put it there, then
# mounted where it says. False: the caller mounts it from the share.
def Snapd.pack.mount(+ch: String, c: SnCfg) -> IO(Bool):
  match c:
    case SnCfg{s, r, h, vm, key, +dev, pl}:
      do IO<Bool>:
        t0 : Nat <- IO.now()
        +a : Result<&2, &2, String, String> <- Snapd.pack.line(K.Pack.ask.render.v7(K.PkAdd{vm, key, ch}))
        t1 : Nat <- IO.now()
        Snapd.say("pack " ++ ch ++ ": " ++ Snapd.pack.said(a) ++ " ms=" ++ Snapd.ms(t0, t1))
        Snapd.pack.at(Snapd.pack.reply(a), ch, dev)

def Snapd.pack.try(on: Bool, +ch: String, c: SnCfg) -> IO(Bool):
  match on:
    case True{}:
      Snapd.pack.mount(ch, c)
    case False{}:
      IO.pure(Bool, False{})

# The filler told that this node unmounted layer ch (in a computation of
# its own: nothing waits for it; an entry it does not end stays until
# the VM stops, and gc keeps its layer meanwhile).
def Snapd.pack.drop(+ch: String, c: SnCfg) -> IO(Unit):
  match c:
    case SnCfg{s, r, h, vm, key, dev, pl}:
      do IO<Unit>:
        a : Result<&2, &2, String, String> <- Snapd.pack.line(K.Pack.ask.render.v7(K.PkDrop{vm, key, ch}))
        Snapd.say("drop " ++ ch ++ ": " ++ Snapd.pack.said(a))

def Snapd.unmount.done(ok: Bool, +ch: String, +c: SnCfg) -> IO(Unit):
  match ok:
    case True{}:
      do IO<Unit>:
        gone : Bool <- GS.Gs.rmdir(Snapd.last(K.Pack.rmdir_args.v7(ch)))
        Snapd.say("layer " ++ ch ++ " unmounted")
        IO.spawn(Unit, Snapd.pack.drop(ch, c))
    case False{}:
      Snapd.say("layer " ++ ch ++ " stays mounted: umount failed")

# Each layer unmounted, its mount point removed and its pack entry
# ended. One whose unmount fails keeps all three.
def Snapd.unmount(chs: List<&2, String>, +c: SnCfg) -> IO(Unit):
  match chs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+ch, t}:
      do IO<Unit>:
        ok : Bool <- GS.Gs.umount(Snapd.last(K.Pack.umount_args.v7(ch)))
        Snapd.unmount.done(ok, ch, c)
        Snapd.unmount(t, c)

# On a node with a pack: the layers the acts let go that no snapshot of
# sn stands on, unmounted.
def Snapd.gone(on: Bool, acts: List<&2, S.Act>, sn: S.Sn, +c: SnCfg) -> IO(Unit):
  match on:
    case True{}:
      Snapd.unmount(K.Pack.gone.v7(acts, S.Sn.layers.v3(sn)), c)
    case False{}:
      IO.pure(Unit, Unit{})

def Snapd.pack.disk.is(hit: Bool, +d: String, rest: IO(String)) -> IO(String):
  match hit:
    case True{}:
      IO.pure(String, K.Pack.dev.v7(d))
    case False{}:
      rest

# The pack's device: the first virtio-blk disk whose serial is the
# pack's name; "" when there is none.
def Snapd.pack.disk(ds: List<&2, String>) -> IO(String):
  match ds:
    case Nil{}:
      IO.pure(String, "")
    case Con{+d, t}:
      do IO<String>:
        text : String <- Snapd.read(K.Pack.serial_file.v7(d))
        Snapd.pack.disk.is(K.Pack.serial_is.v7(text), d, Snapd.pack.disk(t))

def Snapd.pack.cfg.say(on: Bool, +vm: String, +dev: String, keyed: Bool) -> IO(Unit):
  match on:
    case True{}:
      Snapd.say("pack: " ++ dev ++ " for " ++ vm)
    case False{}:
      Snapd.say("pack: none (" ++ Bool.pick(String, String.is_empty(vm), "no " ++ K.Pack.env.v7(),
        Bool.pick(String, String.is_empty(dev), "no disk with the serial " ++ K.Pack.name.v7(),
          Bool.pick(String, keyed, "", "no key in the share"))) ++ "): layers mount from the share")

def Snapd.pack.cfg.go(named: Bool, +sock: String, +root: String, +held: String, +vm: String, +pl: PC.Place) -> IO(SnCfg):
  match named:
    case False{}:
      do IO<SnCfg>:
        Snapd.pack.cfg.say(False{}, "", "", False{})
        return SnCfg{sock, root, held, "", "", "", pl}
    case True{}:
      do IO<SnCfg>:
        +dev : String <- Snapd.pack.disk(K.Pack.disks.v7())
        text : String <- Snapd.read(PL.Plan.host_dir() ++ "/" ++ K.Pack.key_name.v7())
        +key : String = String.trim(text)
        +on : Bool = Bool.not(String.is_empty(dev)) && K.Pack.key_ok.v7(key)
        Snapd.pack.cfg.say(on, vm, dev, K.Pack.key_ok.v7(key))
        return SnCfg{sock, root, held, Bool.pick(String, on, vm, ""), key, dev, pl}

# The snapshotter's configuration: with the pack when VK8S_PACK names
# this VM (K.Pack.guest.v7), the pack's disk is there and the share
# holds a key; else without (vm ""), and layers mount from the share.
def Snapd.pack.cfg(+sock: String, +root: String, +held: String, +pl: PC.Place) -> IO(SnCfg):
  do IO<SnCfg>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env(K.Pack.env.v7())
    +vm : String = K.Pack.guest.v7(Snapd.pack.env(r))
    Snapd.pack.cfg.go(Bool.not(String.is_empty(vm)) && Bool.not(PC.Place.native(pl)), sock, root, held, vm, pl)

# A layer image (v3, docs/ref/layers-sqfs.md): layer c mounted at
# /mnt/layers/<hex> (Lay.mount) from the store's share
# (/mnt/layers-store): its image on a loop device, or a bind of a
# directory an older store left. Whether it is mounted now.
def Snapd.ensure.dir(dir: Bool, +c: String, +pl: PC.Place) -> IO(Bool):
  match dir:
    case True{}:
      do IO<Bool>:
        made : Bool <- GS.Gs.mkdir_p(Snapd.at(pl, LY.Lay.mount(c)))
        GS.Gs.bind(Snapd.at(pl, LY.Lay.store_dir.v3(c)), Snapd.at(pl, LY.Lay.mount(c)))
    case False{}:
      IO.pure(Bool, False{})

# What Snapd.mount found of a layer: not in the store; mounted before
# this call, or the directory of an older store; or its image, mounted
# by this call.
type SnMount is Data:
  MtNo{}
  MtOld{}
  MtNew{}

def SnMount.ok(m: SnMount) -> Bool:
  match m:
    case MtNo{}:
      False{}
    case MtOld{}:
      True{}
    case MtNew{}:
      True{}

# The image's mount, done or not. One that failed leaves no directory at
# the layer's place: a later Prepare takes a directory there for the
# layer (Snapd.present).
def Snapd.ensure.mounted(ok: Bool, +c: String, +pl: PC.Place) -> IO(SnMount):
  match ok:
    case True{}:
      IO.pure(SnMount, MtNew{})
    case False{}:
      do IO<SnMount>:
        gone : Bool <- GS.Gs.rmdir(Snapd.at(pl, LY.Lay.mount(c)))
        return MtNo{}

# The loop effect's answer; one it could not give (a kernel without
# LOOP_CONFIGURE, no loop device it can open) ends in busybox's mount,
# as before.
def Snapd.ensure.looped(ok: Bool, +code: U32, +c: String, +pl: PC.Place) -> IO(Bool):
  match ok:
    case True{}:
      IO.pure(Bool, True{})
    case False{}:
      do IO<Bool>:
        Snapd.say("layer " ++ c ++ ": loop mount errno " ++ U32.show(code) ++ ", trying busybox mount")
        Snapd.bb_ok(PC.Place.paths(pl, LY.Lay.mount_img.v3(c)))

# The image from the share (LY.Lay.mount_img.v3: its image on a loop
# device, read-only, nosuid), unless the pack gave it (packed).
def Snapd.ensure.share(packed: Bool, +c: String, +pl: PC.Place) -> IO(Bool):
  match packed:
    case True{}:
      IO.pure(Bool, True{})
    case False{}:
      do IO<Bool>:
        +code : U32 <- LoopDev.mount(Snapd.at(pl, LY.Lay.store_img.v3(c)), Snapd.at(pl, LY.Lay.mount(c)))
        Snapd.ensure.looped(U32.is_zero(code), code, c, pl)

def Snapd.ensure.img(img: Bool, +c: String, +cfg: SnCfg) -> IO(SnMount):
  match img:
    case True{}:
      do IO<SnMount>:
        made : Bool <- GS.Gs.mkdir_p(Snapd.at(SnCfg.place(cfg), LY.Lay.mount(c)))
        packed : Bool <- Snapd.pack.try(SnCfg.packed(cfg), c, cfg)
        ok : Bool <- Snapd.ensure.share(packed, c, SnCfg.place(cfg))
        Snapd.ensure.mounted(ok, c, SnCfg.place(cfg))
    case False{}:
      do IO<SnMount>:
        dir : Bool <- GS.Gs.is_dir(Snapd.at(SnCfg.place(cfg), LY.Lay.store_dir.v3(c)))
        # not on a native host node: the store there is the host's own
        # directory, writable, and a bind of a part of it under the
        # cluster's data dir is not made (only read-only images are
        # mounted there); such a layer is unpacked by the node
        ok : Bool <- Snapd.ensure.dir(dir && Bool.not(PC.Place.native(SnCfg.place(cfg))), c, SnCfg.place(cfg))
        return Bool.pick(SnMount, ok, MtOld{}, MtNo{})

def Snapd.ensure.go(mounted: Bool, +c: String, +cfg: SnCfg) -> IO(SnMount):
  match mounted:
    case True{}:
      IO.pure(SnMount, MtOld{})
    case False{}:
      do IO<SnMount>:
        img : Bool <- GS.Gs.is_file(Snapd.at(SnCfg.place(cfg), LY.Lay.store_img.v3(c)))
        Snapd.ensure.img(img, c, cfg)

def Snapd.mount(+c: String, +cfg: SnCfg) -> IO(SnMount):
  do IO<SnMount>:
    m : Bool <- GS.Gs.mountpoint(Snapd.at(SnCfg.place(cfg), LY.Lay.mount(c)))
    Snapd.ensure.go(m, c, cfg)

def Snapd.ensure(+c: String, +cfg: SnCfg) -> IO(Bool):
  do IO<Bool>:
    m : SnMount <- Snapd.mount(c, cfg)
    return SnMount.ok(m)

# Every layer the node's snapshots stand for, mounted again (a boot
# empties the tmpfs at /mnt/layers).
def Snapd.ensure.all(cs: List<&2, String>, +cfg: SnCfg) -> IO(Unit):
  match cs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+c, t}:
      do IO<Unit>:
        ok : Bool <- Snapd.ensure(c, cfg)
        Snapd.say("layer " ++ c ++ Bool.pick(String, ok, " mounted", " not in the store"))
        Snapd.ensure.all(t, cfg)

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

# Usage's answer from the walk of its directory: what `du -sk` and
# `find -xdev | wc -l` printed (B.Spb.measure_args, B.Spb.measured), as
# SO.Sysop.tally counts them.
def Snapd.measured(m: Maybe<&2, SO.Tally>) -> B.SpAns:
  match m:
    case None{}:
      B.AnStatus{G.Grpc.internal(), "usage: could not measure"}
    case Some{+t}:
      B.AnReply{B.Spb.usage(SO.Tally.kib(t), SO.Tally.count(t))}

def Snapd.answer(a: B.SpAns, k: R.GSink) -> IO(Unit):
  match a:
    case B.AnMeasure{+p}:
      do IO<Unit>:
        m : Maybe<&2, SO.Tally> <- GS.Gs.usage(p)
        Snapd.reply(Snapd.measured(m), k)
    case other:
      Snapd.reply(other, k)

# A call's effects, in order, then its answer: the state that follows.
def Snapd.done(o: S.Out, +dirty: Bool, k: R.GSink, +c: SnCfg) -> IO(S.Sn):
  match o:
    case S.Out{+sn, res, +acts}:
      do IO<S.Sn>:
        Snapd.mkdirs(B.Spb.mkdirs(acts))
        Snapd.save(dirty, c, sn)
        Snapd.hold(B.Spb.touches(acts), c, sn)
        Snapd.removes(B.Spb.removes(acts))
        Snapd.gone(SnCfg.packed(c) && B.Spb.touches(acts), acts, sn, c)
        Snapd.answer(B.Spb.answer(PC.Place.res(SnCfg.place(c), res)), k)
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
    us : List<&2, S.LUse> <- Snapd.uses(SnCfg.place(c), B.Spb.rec.probe(sn, op))
    +now : U32 <- Snapd.now()
    +dirty : Bool = B.Spb.dirty(op)
    sn2 : S.Sn <- Snapd.done(S.Sn.apply.v2(sn, B.Spb.fill(op, found), have, us, now), dirty, k, c)
    Snapd.log(name, B.Spb.key(op), t0, sn2)

def Snapd.owned.left(m: Maybe<&2, B.SpProbe>, sn: S.Sn, +c: SnCfg) -> IO(Unit):
  match m:
    case None{}:
      IO.pure(Unit, Unit{})
    case Some{B.SpProbe{ch, d}}:
      Snapd.gone(SnCfg.packed(c), [S.ARelease{ch, ""}], sn, c)

# Snapd.run for the Prepare that mounted its layer (have): on a node
# with a pack, a layer the call then did not take (no snapshot stands on
# it) is unmounted again, so nothing stays on the pack that the node's
# held layers do not name.
def Snapd.owned(+op: S.Op, +name: String, t0: Nat, k: R.GSink, +c: SnCfg, +sn: S.Sn, have: List<&2, String>) -> IO(S.Sn):
  do IO<S.Sn>:
    +sn2 : S.Sn <- Snapd.run(op, name, t0, k, c, sn, have)
    Snapd.owned.left(B.Spb.probe(op), sn2, c)
    return sn2

# Whether the store holds the shared layer a Prepare names (test -d);
# False for any other call.
def Snapd.present(+pl: PC.Place, +m: Maybe<&2, B.SpProbe>) -> IO(Bool):
  match m:
    case None{}:
      IO.pure(Bool, False{})
    case Some{B.SpProbe{c, +d}}:
      GS.Gs.is_dir(PC.Place.path(pl, d))

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
    +ok : Bool <- Snapd.present(SnCfg.place(c), B.Spb.probe(op))
    Snapd.asks(A.Ask.of_labels.v2(op, ok), ok, op, name, t0, k, evs, c, sn)

# A small layer image this call mounted, read once (what LY.Lay.warm_args.v6's
# tar to /dev/null did, as GS.Gs.warm: every regular file under the
# mount read to its end; the first exec from it then finds its files in
# the page cache, and does not wait for the store's share after the
# kubelet has reported the container Running). Logs the time the read
# took.
def Snapd.warm(+ch: String, +pl: PC.Place) -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    ok : Bool <- GS.Gs.warm(Snapd.at(pl, LY.Lay.mount(ch)))
    t1 : Nat <- IO.now()
    Snapd.say("layer " ++ ch ++ Bool.pick(String, ok, " read", " not read (a file could not be read)") ++ " ms=" ++ Snapd.ms(t0, t1))

# The read a Prepare waits for, in a computation of its own, as the ask
# is (the loop takes the next call at once): then the Prepare goes back
# to the loop with the layer it holds (EvWarmed), and the loop answers
# it without probing or mounting again. It must not come back as
# EvAsked: in a node container `mountpoint -q` did not report the mount the
# call had just made, so each return mounted the image once more and
# read it again, until no loop device was left (CI run 45447343443,
# container-smoke: 4093 loop devices on 15 layer images).
def Snapd.warm.back(+ch: String, +d: String, +op: S.Op, +name: String, t0: Nat, k: R.GSink, +evs: Chan(SnEv), +pl: PC.Place) -> IO(Unit):
  do IO<Unit>:
    Snapd.warm(ch, pl)
    s : Result<&1, &1, SnEv, Unit> <- Chan.send(SnEv, evs, EvWarmed{op, name, t0, k, B.Spb.have(Some{B.SpProbe{ch, d}}, True{})})
    return Unit{}

def Snapd.warmed(w: Bool, +ch: String, +d: String, +op: S.Op, +name: String, t0: Nat, k: R.GSink, +evs: Chan(SnEv), +c: SnCfg, +sn: S.Sn) -> IO(S.Sn):
  match w:
    case True{}:
      do IO<S.Sn>:
        IO.spawn(Unit, Snapd.warm.back(ch, d, op, name, t0, k, evs, SnCfg.place(c)))
        return sn
    case False{}:
      Snapd.owned(op, name, t0, k, c, sn, B.Spb.have(Some{B.SpProbe{ch, d}}, True{}))

# The Prepare's layer as Snapd.mount found it. A small image mounted
# now (B.Spb.warm.v6 of its recorded size) is read once before the
# Prepare is answered.
def Snapd.resume.mounted(m: SnMount, +ch: String, +d: String, +op: S.Op, +name: String, t0: Nat, k: R.GSink, +evs: Chan(SnEv), +c: SnCfg, +sn: S.Sn) -> IO(S.Sn):
  match m:
    case MtNew{}:
      do IO<S.Sn>:
        text : String <- Snapd.read(PC.Place.path(SnCfg.place(c), Maybe.default(&2, String, LF.Fill.rec.mount.v3(ch), d)))
        Snapd.warmed(B.Spb.warm.v6(B.Spb.uses(Some{B.SpProbe{ch, d}}, text)), ch, d, op, name, t0, k, evs, c, sn)
    case MtOld{}:
      Snapd.run(op, name, t0, k, c, sn, B.Spb.have(Some{B.SpProbe{ch, d}}, True{}))
    case MtNo{}:
      Snapd.run(op, name, t0, k, c, sn, Nil{})

def Snapd.resume.probed(m: Maybe<&2, B.SpProbe>, +op: S.Op, +name: String, t0: Nat, k: R.GSink, +evs: Chan(SnEv), +c: SnCfg, +sn: S.Sn) -> IO(S.Sn):
  match m:
    case None{}:
      Snapd.run(op, name, t0, k, c, sn, Nil{})
    case Some{B.SpProbe{+ch, +d}}:
      do IO<S.Sn>:
        mt : SnMount <- Snapd.mount(ch, c)
        Snapd.resume.mounted(mt, ch, d, op, name, t0, k, evs, c, sn)

# A Prepare back from its ask: the store probed again and the layer mounted (Snapd.mount), then the
# call as without an ask. A layer the filler published (or another
# node's fill did) is answered AlreadyExists; any other is unpacked on
# the node.
def Snapd.resume(+op: S.Op, +name: String, t0: Nat, k: R.GSink, +evs: Chan(SnEv), +c: SnCfg, +sn: S.Sn) -> IO(S.Sn):
  Snapd.resume.probed(B.Spb.probe(op), op, name, t0, k, evs, c, sn)

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
      Snapd.resume(op, name, t0, k, evs, c, sn)
    case Some{EvWarmed{op, name, t0, k, have}}:
      Snapd.owned(op, name, t0, k, c, sn, have)

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
    bound : Bool <- GS.Gs.is_dir(PL.Plan.hostdev.v5())
    Snapd.loop_links.go(bound)

def Snapd.start(+sock: String, +root: String, +held: String, +pl: PC.Place) -> IO(Unit):
  do IO<Unit>:
    Snapd.loop_links()
    # a native host node's socket directory is its plan's to make (under
    # the cluster's data dir): nothing of the host's /run is touched
    made : Bool <- GS.Gs.mkdirs(Con{root ++ "/snapshots", Bool.pick(List<&2, String>, PC.Place.native(pl), Nil{}, ["/run/vk8s"])})
    Snapd.say(Bool.pick(String, PC.Place.native(pl), "native host node: the store is " ++ PC.Place.path(pl, PC.Place.node_store())
      ++ ", layers mount under " ++ PC.Place.path(pl, PC.Place.node_mounts()), "the store is " ++ PC.Place.node_store()))
    rn : Result<&1, &1, U32 & String, String> <- IO.get_env("VK8S_NAME")
    +node : String = Snapd.node(rn)
    text : String <- Snapd.read(root ++ "/state")
    +sn : S.Sn <- Snapd.loaded(T.Sst.read(root, node, text), root, node)
    +cfg : SnCfg <- Snapd.pack.cfg(sock, root, held, pl)
    # the held layers of the state as loaded, before any is mounted: a
    # node restored under another name has a share without the file, and
    # the host's gc reads it
    Snapd.hold(True{}, cfg, sn)
    Snapd.ensure.all(S.Sn.layers.v3(sn), cfg)
    r : Result<&1, &1, U32 & String, Listener> <- Y.Sys.unix_listen(sock, 384)
    Snapd.listening(r, cfg, sn)

# argv: [prog, "snapshotter", SOCKET, ROOT, HELD], and on a native host
# node (src/standalone/native_host.bend NHost.layers_steps.v3) the
# host's store and the directory its layers mount under, STORE MOUNTS.
def Snapd.main(args: +List<String>) -> IO(Unit):
  match args:
    case Con{p, Con{m, Con{+sock, Con{+root, Con{+held, Nil{}}}}}}:
      Snapd.start(sock, root, held, PC.Place.of("", ""))
    case Con{p, Con{m, Con{+sock, Con{+root, Con{+held, Con{+store, Con{+mounts, Nil{}}}}}}}}:
      Snapd.start(sock, root, held, PC.Place.of(store, mounts))
    case _:
      IO.die(Unit, 2, "usage: vk8s-guest snapshotter SOCKET ROOT HELD [STORE MOUNTS]")
