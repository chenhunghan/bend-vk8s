import Base
import bend-kube-runtime@0.10.0.0/src/unz.bend as Z
import ../../src/layers/fill.bend as F
import ../../src/layers/pull.bend as P
import ../../src/layers/store.bend as Y
import ../../src/layers/tar.bend as T
import ../../src/oci/size.bend as N
import ../oci/blob.bend as B
import ../bin_file.bend as BF
import ./fs.bend as L

# Unpacking one layer into the shared layer store
# ===============================================
#
# The IO of src/layers/fill.bend: a verified layer blob on disk becomes
# <root>/layers/<hex>, every decision being Bend's (src/layers/):
#
#   1. a new tmp directory <root>/tmp/<hex>.<now> (the next number when a
#      fill of the same layer took it);
#   2. the blob decompressed with bend-kube's Unz.file (gzip through zlib,
#      zstd through libzstd) to <tmp>.tar, or read as it is (an
#      uncompressed layer);
#   3. the tar's SHA-256 checked against the layer's diffID (OciBlob.hash),
#      so a config that lies about a diffID never puts a layer under
#      another layer's chain ID;
#   4. the unpack loop (Fill.head, Fill.ext, Fill.act) over the tar, each
#      entry made by host/layers/fs.bend, then each directory's .bend-meta
#      (Fill.sides) and an fsync of every directory (Fill.syncs);
#   5. the rename into place (LayerFs.rename_dir; a layer already there
#      means another fill published it first: the tmp directory goes),
#      an fsync of <root>/layers, then the layer's record (Fill.rec) at
#      <root>/layer-refs/<hex> and an fsync of that directory.
#
# A failure removes the tmp directory and the tar. Nothing here follows a
# symbolic link: entries are made with O_EXCL or O_NOFOLLOW, and the plan
# refuses every entry under a symlink (src/layers/tar.bend).

def Lu.R(-A: Type) -> Type:
  Result<&1, &1, String, A>

def Lu.why(+what: String, e: U32 & String) -> String:
  match e:
    case (c, m):
      what ++ ": " ++ m ++ " (errno " ++ U32.show(c) ++ ")"

def Lu.res(-A: Type, +what: String, r: Result<&1, &1, U32 & String, A>) -> Lu.R(A):
  match r:
    case Fail{e}:
      Fail{Lu.why(what, e)}
    case Done{x}:
      Done{x}

def Lu.then.go(-A: Type, -B: Type, r: Lu.R(A), k: A -> IO(Lu.R(B))) -> IO(Lu.R(B)):
  match r:
    case Fail{e}:
      IO.pure(Lu.R(B), Fail{e})
    case Done{x}:
      k(x)

# io, then k with its value; a failure skips k.
def Lu.then(-A: Type, -B: Type, io: IO(Lu.R(A)), k: A -> IO(Lu.R(B))) -> IO(Lu.R(B)):
  IO.bind(Lu.R(A), Lu.R(B), io, r => Lu.then.go(A, B, r, k))

# A LayerFs call as a step.
def Lu.fs(io: IO(L.LayerFs.Res(Unit)), +what: String) -> IO(Lu.R(Unit)):
  IO.bind(L.LayerFs.Res(Unit), Lu.R(Unit), io, r => IO.pure(Lu.R(Unit), Lu.res(Unit, what, r)))

def Lu.done() -> IO(Lu.R(Unit)):
  IO.pure(Lu.R(Unit), Done{Unit{}})

def Lu.hi(s: N.Size) -> U32:
  match s:
    case N.Size{h, l}:
      h

def Lu.lo(s: N.Size) -> U32:
  match s:
    case N.Size{h, l}:
      l

def Lu.forever() -> Nat:
  U32.to_nat(4294967295)

# Files and directories
# ---------------------

# Makes the directory at path unless it is there (0755).
def Lu.dir(+path: String) -> IO(Lu.R(Unit)):
  Lu.fs(L.LayerFs.make(L.LayerFs.dir(), path, []), "making " ++ path)

def Lu.drop.said(r: L.LayerFs.Res(Unit), +path: String) -> IO(Unit):
  match r:
    case Done{u}:
      IO.pure(Unit, Unit{})
    case Fail{e}:
      IO.print_err("vk8s layers: " ++ Lu.why("removing " ++ path, e))

# Removes path and all under it; a failure is only reported.
def Lu.drop(+path: String) -> IO(Unit):
  do IO<Unit>:
    r : L.LayerFs.Res(Unit) <- L.LayerFs.remove_tree(path)
    Lu.drop.said(r, path)

def Lu.read.got(r: BF.BinFile.Res(List<&2, U32>)) -> Maybe<&2, String>:
  match r:
    case Fail{e}:
      None{}
    case Done{bs}:
      Some{T.Tar.s(bs)}

# The text of a small file (at most 64 KiB), or None.
def Lu.read(+path: String) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    r : BF.BinFile.Res(List<&2, U32>) <- BF.BinFile.read_all(path, 65536)
    return Lu.read.got(r)

# Writes text to a new or truncated file at path (mode 0600).
def Lu.write(+path: String, text: String) -> IO(Lu.R(Unit)):
  IO.bind(BF.BinFile.Res(Unit), Lu.R(Unit), BF.BinFile.write(path, T.Tar.b(text)), r => IO.pure(Lu.R(Unit), Lu.res(Unit, "writing " ++ path, r)))

# Writes text to root/rel/name through the file tmp and one rename
# (BinFile.place), so a reader sees the old text or the new one; rel is
# made when missing.
def Lu.put(+tmp: String, +root: String, +rel: String, +name: String, text: String) -> IO(Lu.R(Unit)):
  Lu.then(Unit, Unit, Lu.write(tmp, text),
    u => IO.bind(BF.BinFile.Res(Unit), Lu.R(Unit), BF.BinFile.place(tmp, root, rel, name), r => IO.pure(Lu.R(Unit), Lu.res(Unit, "renaming " ++ tmp ++ " into " ++ root ++ "/" ++ rel, r))))

# Records
# -------

# The record of layer chain, if one this version wrote names it.
def Lu.rec.of(m: Maybe<&2, String>) -> Maybe<&2, Y.Layer>:
  match m:
    case None{}:
      None{}
    case Some{s}:
      F.Fill.rec.parse(s)

def Lu.rec.same(m: Maybe<&2, Y.Layer>, +chain: String) -> Maybe<&2, Y.Layer>:
  match m:
    case None{}:
      None{}
    case Some{+l}:
      Bool.pick(Maybe<&2, Y.Layer>, String.eq(Y.Layer.chain(l), chain), Some{l}, None{})

def Lu.rec.path(m: Maybe<&2, String>) -> String:
  Maybe.default(&2, String, m, "")

# The layer chain's record, or None.
def Lu.rec.get(+root: String, +chain: String) -> IO(Maybe<&2, Y.Layer>):
  do IO<Maybe<&2, Y.Layer>>:
    m : Maybe<&2, String> <- Lu.read(Lu.rec.path(F.Fill.rec.path(root, chain)))
    return Lu.rec.same(Lu.rec.of(m), chain)

def Lu.hex(+chain: String) -> String:
  Maybe.default(&2, String, Y.Lay.hex(chain), "")

# Writes layer l's record (through <root>/tmp), then fsyncs layer-refs/.
def Lu.rec.put(+root: String, +now: U32, l: Y.Layer) -> IO(Lu.R(Unit)):
  match l:
    case Y.Layer{+c, d, p, hs, u}:
      Lu.then(Unit, Unit, Lu.put(root ++ "/tmp/" ++ Lu.hex(c) ++ "." ++ U32.show(now) ++ ".rec", root, "layer-refs", Lu.hex(c), F.Fill.rec.render(Y.Layer{c, d, p, hs, u})),
        v => Lu.fs(L.LayerFs.fsync_dir(root ++ "/layer-refs"), "syncing " ++ root ++ "/layer-refs"))

# The tmp directory
# -----------------

def Lu.code(e: U32 & String) -> U32:
  match e:
    case (c, m):
      c

def Lu.tmp.retry(taken: Bool, e: U32 & String, +nonce: U32, left: Nat, again: U32 -> Nat -> IO(Lu.R(String))) -> IO(Lu.R(String)):
  match taken left:
    case True{} 1n+k:
      again((nonce + 1 : U32), k)
    case _ _:
      IO.pure(Lu.R(String), Fail{Lu.why("making a tmp directory", e)})

def Lu.tmp.got(r: L.LayerFs.Res(Unit), +root: String, +chain: String, +nonce: U32, +left: Nat,
  again: U32 -> Nat -> IO(Lu.R(String))) -> IO(Lu.R(String)):
  match r:
    case Done{u}:
      IO.pure(Lu.R(String), Done{Maybe.default(&2, String, Y.Lay.tmp(root, chain, nonce), "")})
    case Fail{+e}:
      Lu.tmp.retry(U32.is_eq(Lu.code(e), L.LayerFs.eexist()), e, nonce, left, again)

# A new tmp directory for layer chain: <root>/tmp/<hex>.<nonce>, the
# first nonce from now that no other fill took (64 tries).
def Lu.tmp(+root: String, +chain: String, +nonce: U32, left: Nat) -> IO(Lu.R(String)):
  do IO<Lu.R(String)>:
    r : L.LayerFs.Res(Unit) <- L.LayerFs.make(L.LayerFs.new_dir(), Maybe.default(&2, String, Y.Lay.tmp(root, chain, nonce), ""), [])
    Lu.tmp.got(r, root, chain, nonce, left, n => k => Lu.tmp(root, chain, n, k))

def Lu.rec.fresh(m: Maybe<&2, Y.Layer>, l: Y.Layer, +now: U32) -> Y.Layer:
  match m:
    case None{}:
      l
    case Some{x}:
      F.Fill.touch(x, now)

# Records a use of layer l at now: its record touched (holders kept), or
# l when it has none.
def Lu.rec.use(+root: String, +now: U32, l: Y.Layer) -> IO(Lu.R(Unit)):
  match l:
    case Y.Layer{+c, d, p, hs, u}:
      do IO<Lu.R(Unit)>:
        m : Maybe<&2, Y.Layer> <- Lu.rec.get(root, c)
        Lu.rec.put(root, now, Lu.rec.fresh(m, Y.Layer{c, d, p, hs, u}, now))

# The store's directories, made when missing.
def Lu.base(+root: String) -> IO(Lu.R(Unit)):
  Lu.then(Unit, Unit, Lu.dir(root),
    u => Lu.then(Unit, Unit, Lu.dir(root ++ "/tmp"),
      v => Lu.then(Unit, Unit, Lu.dir(root ++ "/layers"),
        w => Lu.dir(root ++ "/layer-refs"))))

# Decompressing
# -------------

def Lu.tar.unz(r: Result<&1, &1, U32 & String, U32 & U32>, +zstd: Bool, +tar: String) -> Lu.R(String & Bool):
  match r:
    case Fail{(c, m)}:
      Fail{P.Pull.unz_why(zstd, m)}
    case Done{n}:
      Done{(tar, True{})}

def Lu.tar.run(+kind: U32, +zstd: Bool, +blob: String, +tar: String) -> IO(Lu.R(String & Bool)):
  IO.bind(Result<&1, &1, U32 & String, U32 & U32>, Lu.R(String & Bool), Z.Unz.file(kind, blob, tar, 0),
    r => IO.pure(Lu.R(String & Bool), Lu.tar.unz(r, zstd, tar)))

# The tar of a blob compressed as c: its path, and whether it is a file
# this fill made (tar) rather than the blob itself.
def Lu.tar.comp(c: P.Comp, +blob: String, +tar: String) -> IO(Lu.R(String & Bool)):
  match c:
    case P.CNone{}:
      IO.pure(Lu.R(String & Bool), Done{(blob, False{})})
    case P.CGzip{}:
      Lu.tar.run(Z.Unz.gzip(), False{}, blob, tar)
    case P.CZstd{}:
      Lu.tar.run(Z.Unz.zstd(), True{}, blob, tar)
    case P.CSniff{}:
      IO.pure(Lu.R(String & Bool), Fail{"the layer's compression is still unknown"})
    case P.CBad{w}:
      IO.pure(Lu.R(String & Bool), Fail{w})

def Lu.head8.bytes(r: L.LayerFs.Res(List<&2, U32>)) -> List<&2, U32>:
  match r:
    case Fail{e}:
      Nil{}
    case Done{bs}:
      bs

def Lu.head8.got(p: File & L.LayerFs.Res(List<&2, U32>)) -> IO(List<&2, U32>):
  match p:
    case (f, r):
      do IO<List<&2, U32>>:
        File.close(f)
        return Lu.head8.bytes(r)

def Lu.head8.opened(r: Result<&1, &1, U32 & String, File>) -> IO(List<&2, U32>):
  match r:
    case Fail{e}:
      IO.pure(List<&2, U32>, Nil{})
    case Done{f}:
      do IO<List<&2, U32>>:
        p : File & L.LayerFs.Res(List<&2, U32>) <- L.LayerFs.read(f, 0, 0, 8)
        Lu.head8.got(p)

# The first 8 bytes of a file (fewer when it is shorter or unreadable).
def Lu.head8(+path: String) -> IO(List<&2, U32>):
  do IO<List<&2, U32>>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    Lu.head8.opened(r)

def Lu.tar.sniffed(c: P.Comp, +blob: String, +tar: String) -> IO(Lu.R(String & Bool)):
  match c:
    case P.CSniff{}:
      do IO<Lu.R(String & Bool)>:
        bs : List<&2, U32> <- Lu.head8(blob)
        Lu.tar.comp(P.Pull.sniff(bs), blob, tar)
    case other:
      Lu.tar.comp(other, blob, tar)

# The diffID
# ----------

def Lu.diff.got(r: B.OciBlob.Res(String), +diff: String) -> Lu.R(Unit):
  match r:
    case Fail{e}:
      Fail{Lu.why("hashing the layer's tar", e)}
    case Done{+hex}:
      Bool.pick(Lu.R(Unit), String.eq(diff, "sha256:" ++ hex), Done{Unit{}},
        Fail{"the layer's tar is sha256:" ++ hex ++ ", not its diffID " ++ diff})

# Checks that the tar is the layer's diffID (containerd checks it too).
def Lu.diff(+tar: String, +diff: String) -> IO(Lu.R(Unit)):
  IO.bind(B.OciBlob.Res(String), Lu.R(Unit), B.OciBlob.hash(tar), r => IO.pure(Lu.R(Unit), Lu.diff.got(r, diff)))

# Entries
# -------

def Lu.with(f: File, io: IO(L.LayerFs.Res(Unit)), +what: String) -> IO(File & Lu.R(Unit)):
  IO.bind(L.LayerFs.Res(Unit), File & Lu.R(Unit), io, r => IO.pure(File & Lu.R(Unit), (f, Lu.res(Unit, what, r))))

def Lu.copied(q: File & L.LayerFs.Res(Unit), +what: String) -> File & Lu.R(Unit):
  match q:
    case (f, r):
      (f, Lu.res(Unit, what, r))

# Runs one operation; f is the layer's tar, which OCopy reads.
def Lu.op(o: F.Op, f: File) -> IO(File & Lu.R(Unit)):
  match o:
    case F.ONone{}:
      IO.pure(File & Lu.R(Unit), (f, Done{Unit{}}))
    case F.OMkdir{+p}:
      Lu.with(f, L.LayerFs.make(L.LayerFs.dir(), p, []), "making " ++ p)
    case F.OEmpty{+p}:
      Lu.with(f, L.LayerFs.make(L.LayerFs.empty(), p, []), "making " ++ p)
    case F.OSymlink{+p, t}:
      Lu.with(f, L.LayerFs.make(L.LayerFs.symlink(), p, T.Tar.b(t)), "making the symlink " ++ p)
    case F.OLink{+p, t}:
      Lu.with(f, L.LayerFs.make(L.LayerFs.link(), p, T.Tar.b(t)), "making the hard link " ++ p)
    case F.OCopy{+p, +at, +sz}:
      IO.bind(File & L.LayerFs.Res(Unit), File & Lu.R(Unit), L.LayerFs.copy(f, Lu.hi(at), Lu.lo(at), Lu.hi(sz), Lu.lo(sz), p),
        q => IO.pure(File & Lu.R(Unit), Lu.copied(q, "writing " ++ p)))
    case F.OWrite{+p, t}:
      Lu.with(f, L.LayerFs.make(L.LayerFs.file(), p, T.Tar.b(t)), "writing " ++ p)

def Lu.ops.next(q: File & Lu.R(Unit), again: File -> IO(File & Lu.R(Unit))) -> IO(File & Lu.R(Unit)):
  match q:
    case (f, Done{u}):
      again(f)
    case (f, Fail{e}):
      IO.pure(File & Lu.R(Unit), (f, Fail{e}))

# Runs the operations in order; stops at the first failure.
def Lu.ops(os: List<&2, F.Op>, f: File) -> IO(File & Lu.R(Unit)):
  match os:
    case Nil{}:
      IO.pure(File & Lu.R(Unit), (f, Done{Unit{}}))
    case Con{o, t}:
      do IO<File & Lu.R(Unit)>:
        q : File & Lu.R(Unit) <- Lu.op(o, f)
        Lu.ops.next(q, g => Lu.ops(t, g))

# The loop
# --------

def Lu.loop.read(p: File & L.LayerFs.Res(List<&2, U32>),
  again: File -> List<&2, U32> -> IO(File & Lu.R(List<&2, List<&2, T.Ent>>))) -> IO(File & Lu.R(List<&2, List<&2, T.Ent>>)):
  match p:
    case (f, Fail{e}):
      IO.pure(File & Lu.R(List<&2, List<&2, T.Ent>>), (f, Fail{Lu.why("reading the layer's tar", e)}))
    case (f, Done{bs}):
      again(f, bs)

def Lu.loop.made(q: File & Lu.R(Unit),
  again: File -> IO(File & Lu.R(List<&2, List<&2, T.Ent>>))) -> IO(File & Lu.R(List<&2, List<&2, T.Ent>>)):
  match q:
    case (f, Done{u}):
      again(f)
    case (f, Fail{e}):
      IO.pure(File & Lu.R(List<&2, List<&2, T.Ent>>), (f, Fail{e}))

# The unpack loop (src/layers/fill.bend) over the tar f into dir: every
# entry made, and each step's entries, the last step first.
def Lu.loop(fuel: Nat, a: F.Act, f: File, +dir: String, acc: List<&2, List<&2, T.Ent>>) ->
  IO(File & Lu.R(List<&2, List<&2, T.Ent>>)):
  match fuel a:
    case 0n _:
      IO.pure(File & Lu.R(List<&2, List<&2, T.Ent>>), (f, Fail{"the layer's tar has too many entries"}))
    case 1n+k F.AHead{st, +at}:
      do IO<File & Lu.R(List<&2, List<&2, T.Ent>>)>:
        p : File & L.LayerFs.Res(List<&2, U32>) <- L.LayerFs.read(f, Lu.hi(at), Lu.lo(at), 512)
        Lu.loop.read(p, g => bs => Lu.loop(k, F.Fill.head(st, at, bs, dir), g, dir, acc))
    case 1n+k F.AExt{st, +at, +n, next}:
      do IO<File & Lu.R(List<&2, List<&2, T.Ent>>)>:
        p : File & L.LayerFs.Res(List<&2, U32>) <- L.LayerFs.read(f, Lu.hi(at), Lu.lo(at), n)
        Lu.loop.read(p, g => bs => Lu.loop(k, F.Fill.ext(st, n, next, bs, dir), g, dir, acc))
    case 1n+k F.AMake{st, es, ops, next}:
      do IO<File & Lu.R(List<&2, List<&2, T.Ent>>)>:
        q : File & Lu.R(Unit) <- Lu.ops(ops, f)
        Lu.loop.made(q, g => Lu.loop(k, F.AHead{st, next}, g, dir, Con{es, acc}))
    case 1n+k F.ADone{}:
      IO.pure(File & Lu.R(List<&2, List<&2, T.Ent>>), (f, Done{acc}))
    case 1n+k F.ABad{why}:
      IO.pure(File & Lu.R(List<&2, List<&2, T.Ent>>), (f, Fail{why}))

def Lu.syncs(ds: List<&2, String>) -> IO(Lu.R(Unit)):
  match ds:
    case Nil{}:
      Lu.done()
    case Con{+d, t}:
      Lu.then(Unit, Unit, Lu.fs(L.LayerFs.fsync_dir(d), "syncing " ++ d), u => Lu.syncs(t))

def Lu.unpack.synced(q: File & Lu.R(Unit), ds: List<&2, String>) -> IO(Lu.R(Unit)):
  match q:
    case (f, r):
      do IO<Lu.R(Unit)>:
        File.close(f)
        Lu.then(Unit, Unit, IO.pure(Lu.R(Unit), r), u => Lu.syncs(ds))

def Lu.unpack.meta(f: File, +es: List<&2, T.Ent>, +dir: String, +chain: String) -> IO(Lu.R(Unit)):
  do IO<Lu.R(Unit)>:
    q : File & Lu.R(Unit) <- Lu.ops(F.Fill.sides(dir, chain, es), f)
    Lu.unpack.synced(q, F.Fill.syncs(dir, es))

def Lu.unpack.sides(q: File & Lu.R(List<&2, List<&2, T.Ent>>), +dir: String, +chain: String) -> IO(Lu.R(Unit)):
  match q:
    case (f, Fail{e}):
      do IO<Lu.R(Unit)>:
        File.close(f)
        return Fail{e}
    case (f, Done{acc}):
      Lu.unpack.meta(f, List.concat(&2, T.Ent, List.reverse(&2, List<&2, T.Ent>, acc)), dir, chain)

def Lu.unpack.loop(r: Result<&1, &1, U32 & String, File>, +tar: String, +dir: String, +chain: String) -> IO(Lu.R(Unit)):
  match r:
    case Fail{e}:
      IO.pure(Lu.R(Unit), Fail{Lu.why("opening " ++ tar, e)})
    case Done{f}:
      do IO<Lu.R(Unit)>:
        q : File & Lu.R(List<&2, List<&2, T.Ent>>) <- Lu.loop(Lu.forever(), F.Fill.start(), f, dir, Nil{})
        Lu.unpack.sides(q, dir, chain)

# Unpacks the tar into the directory dir (made already) of layer chain:
# its entries, its .bend-meta files, and an fsync of every directory.
def Lu.unpack(+tar: String, +dir: String, +chain: String) -> IO(Lu.R(Unit)):
  do IO<Lu.R(Unit)>:
    r : Result<&1, &1, U32 & String, File> <- File.open(tar, "r")
    Lu.unpack.loop(r, tar, dir, chain)

# Publishing
# ----------

def Lu.placed.lost(lost: Bool, e: U32 & String, +root: String, +tmp: String, l: Y.Layer, +now: U32) -> IO(Lu.R(String)):
  match lost:
    case True{}:
      do IO<Lu.R(String)>:
        Lu.drop(tmp)
        Lu.then(Unit, String, Lu.rec.use(root, now, l), w => IO.pure(Lu.R(String), Done{"present"}))
    case False{}:
      IO.pure(Lu.R(String), Fail{Lu.why("renaming " ++ tmp ++ " into place", e)})

def Lu.placed(r: L.LayerFs.Res(Unit), +root: String, +tmp: String, l: Y.Layer, +now: U32) -> IO(Lu.R(String)):
  match r:
    case Done{u}:
      Lu.then(Unit, String, Lu.fs(L.LayerFs.fsync_dir(root ++ "/layers"), "syncing " ++ root ++ "/layers"),
        v => Lu.then(Unit, String, Lu.rec.use(root, now, l), w => IO.pure(Lu.R(String), Done{"published"})))
    case Fail{+e}:
      Lu.placed.lost(U32.is_eq(Lu.code(e), L.LayerFs.eexist()), e, root, tmp, l, now)

def Lu.publish.place(+root: String, +now: U32, +chain: String, diff: String, parent: String, +tmp: String) -> IO(Lu.R(String)):
  do IO<Lu.R(String)>:
    r : L.LayerFs.Res(Unit) <- L.LayerFs.rename_dir(tmp, Maybe.default(&2, String, Y.Lay.dir(root, chain), ""))
    Lu.placed(r, root, tmp, F.Fill.rec.new(chain, diff, parent, now), now)

def Lu.publish.tar(p: String & Bool, +root: String, +now: U32, +chain: String, +diff: String, parent: String, +tmp: String) ->
  IO(Lu.R(String)):
  match p:
    case (+tar, ours):
      Lu.then(Unit, String, Lu.diff(tar, diff),
        u => Lu.then(Unit, String, Lu.unpack(tar, tmp, chain),
          v => Lu.publish.place(root, now, chain, diff, parent, tmp)))

def Lu.publish.fail(r: Lu.R(String), +tmp: String) -> IO(Lu.R(String)):
  match r:
    case Done{x}:
      IO.pure(Lu.R(String), Done{x})
    case Fail{e}:
      do IO<Lu.R(String)>:
        Lu.drop(tmp)
        return Fail{e}

def Lu.publish.end(r: Lu.R(String), +tmp: String) -> IO(Lu.R(String)):
  do IO<Lu.R(String)>:
    Lu.drop(F.Fill.tmp.tar(tmp))
    Lu.publish.fail(r, tmp)

def Lu.publish.in(+root: String, +now: U32, +chain: String, +diff: String, parent: String, +blob: String, comp: P.Comp,
  +tmp: String) -> IO(Lu.R(String)):
  do IO<Lu.R(String)>:
    r : Lu.R(String) <- Lu.then(String & Bool, String, Lu.tar.sniffed(comp, blob, F.Fill.tmp.tar(tmp)),
      p => Lu.publish.tar(p, root, now, chain, diff, parent, tmp))
    Lu.publish.end(r, tmp)

# Unpacks layer fl (Pull.fills) from its verified blob, the file at blob,
# into the store at root, at now (the wall clock's seconds): "published",
# or "present" when another fill published it first. Either way the
# layer's record says it was used at now.
def Lu.publish(+root: String, +now: U32, fl: P.Fill, +blob: String) -> IO(Lu.R(String)):
  match fl:
    case P.Fill{+chain, +diff, +parent, desc, comp}:
      Lu.then(Unit, String, Lu.base(root),
        u => Lu.then(String, String, Lu.tmp(root, chain, now, 64n),
          tmp => Lu.publish.in(root, now, chain, diff, parent, blob, comp, tmp)))
