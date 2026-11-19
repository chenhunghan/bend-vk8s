import Base
import ../../src/layers/fill.bend as F
import ../../src/layers/pull.bend as P
import ../../src/layers/sqfs.bend as Q
import ../../src/layers/store.bend as Y
import ../../src/layers/tar.bend as T
import ../../src/oci/size.bend as N
import ./fs.bend as L
import ./unpack.bend as U

# Layer images (v3)
# =================
#
# A layer of the shared store as one read-only squashfs image,
# <root>/layers/<hex>.sqfs (src/layers/sqfs.bend, docs/ref/layers-sqfs.md),
# instead of a directory tree: a fill makes about a dozen host files
# whatever the layer holds, so a host that records every file it sees
# made, renamed or removed (endpoint security) is not flooded.
#
#   1. the image <root>/tmp/<hex>.<nonce>.sqfs made with O_EXCL (the next
#      nonce when another fill took it), open for the whole fill;
#   2. the blob decompressed to <root>/tmp/<hex>.<nonce>.tar and its
#      SHA-256 checked against the diffID (as the v2 unpack does);
#   3. the unpack loop over the tar (Fill.head, Fill.ext), each regular
#      file's data copied into the image after the 96 bytes of the super
#      block, file after file (LayerFs.copy_at); nothing else is made;
#   4. the tables after the data and the super block at 0
#      (Sqfs.image), an fsync, the image closed;
#   5. the records (as v2), the rename into <root>/layers/<hex>.sqfs and
#      one F_FULLFSYNC of <root>/layers; the tar removed.
#
# A layer whose image would pass Li.max() is refused: the node unpacks
# it itself.

# The most bytes of file data an image holds (3.5 GiB), so the image and
# its tables stay below 4 GiB (src/layers/sqfs.bend's v1 limit).
def Li.max() -> U32:
  3758096384

# What the loop carries: the tar and the image, and what it has so far.
def Li.R(-A: Type) -> Type:
  (File & File) & U.Lu.R(A)

def Li.fail(-A: Type, f: File, g: File, +why: String) -> IO(Li.R(A)):
  IO.pure(Li.R(A), ((f, g), Fail{why}))

# One copy done: the next entries, or the failure.
def Li.copied.r(r: L.LayerFs.Res(Unit), f: File, g: File,
  again: File -> File -> IO(Li.R(List<&2, Q.Put> & U32))) -> IO(Li.R(List<&2, Q.Put> & U32)):
  match r:
    case Done{u}:
      again(f, g)
    case Fail{e}:
      Li.fail(List<&2, Q.Put> & U32, f, g, U.Lu.why("copying a file's data into the image", e))

def Li.copied.g(p: File & L.LayerFs.Res(Unit), f: File,
  again: File -> File -> IO(Li.R(List<&2, Q.Put> & U32))) -> IO(Li.R(List<&2, Q.Put> & U32)):
  match p:
    case (g, r):
      Li.copied.r(r, f, g, again)

def Li.copied(q: File & (File & L.LayerFs.Res(Unit)),
  again: File -> File -> IO(Li.R(List<&2, Q.Put> & U32))) -> IO(Li.R(List<&2, Q.Put> & U32)):
  match q:
    case (f, p):
      Li.copied.g(p, f, again)

# Whether a file of size s still fits after cur.
def Li.fits(+cur: U32, +s: N.Size) -> Bool:
  match s:
    case N.Size{+hi, +lo}:
      Bool.and(U32.is_eq(hi, 0), Bool.and(U32.is_le(lo, Li.max()), U32.is_le(cur, (Li.max() - lo : U32))))

def Li.copy(fits: Bool, f: File, g: File, +at: N.Size, +size: N.Size, +cur: U32,
  again: File -> File -> IO(Li.R(List<&2, Q.Put> & U32))) -> IO(Li.R(List<&2, Q.Put> & U32)):
  match fits:
    case False{}:
      Li.fail(List<&2, Q.Put> & U32, f, g, "the layer's image would pass " ++ U32.show(Li.max()) ++ " bytes of data")
    case True{}:
      do IO<Li.R(List<&2, Q.Put> & U32)>:
        q : File & (File & L.LayerFs.Res(Unit)) <- L.LayerFs.copy_at(f, U.Lu.hi(at), U.Lu.lo(at), U.Lu.hi(size), U.Lu.lo(size), g, 0, cur)
        Li.copied(q, again)

def Li.size.lo(+s: N.Size) -> U32:
  match s:
    case N.Size{hi, lo}:
      lo

# One step's entries (es, with Fill.ops' operation for each, in order):
# a regular file's data copied to the image at cur (OCopy), every entry
# kept with where its data went.
def Li.put(es: List<&2, T.Ent>, ops: List<&2, F.Op>, f: File, g: File, +cur: U32, acc: List<&2, Q.Put>) ->
  IO(Li.R(List<&2, Q.Put> & U32)):
  match es:
    case Nil{}:
      IO.pure(Li.R(List<&2, Q.Put> & U32), ((f, g), Done{(acc, cur)}))
    case Con{+e, et}:
      match ops:
        case Nil{}:
          IO.pure(Li.R(List<&2, Q.Put> & U32), ((f, g), Done{(Con{Q.Put{e, 0}, acc}, cur)}))
        case Con{o, ot}:
          match o:
            case F.OCopy{p, +at, +size}:
              Li.copy(Li.fits(cur, size), f, g, at, size, cur,
                f2 => g2 => Li.put(et, ot, f2, g2, (cur + Li.size.lo(size) : U32), Con{Q.Put{e, cur}, acc}))
            case _:
              Li.put(et, ot, f, g, cur, Con{Q.Put{e, 0}, acc})

def Li.loop.read(p: File & L.LayerFs.Res(List<&2, U32>), g: File,
  again: File -> File -> List<&2, U32> -> IO(Li.R(List<&2, Q.Put> & U32))) -> IO(Li.R(List<&2, Q.Put> & U32)):
  match p:
    case (f, Fail{e}):
      Li.fail(List<&2, Q.Put> & U32, f, g, U.Lu.why("reading the layer's tar", e))
    case (f, Done{bs}):
      again(f, g, bs)

def Li.loop.got(p: List<&2, Q.Put> & U32, f: File, g: File,
  again: File -> File -> List<&2, Q.Put> -> U32 -> IO(Li.R(List<&2, Q.Put> & U32))) -> IO(Li.R(List<&2, Q.Put> & U32)):
  match p:
    case (acc, cur):
      again(f, g, acc, cur)

def Li.loop.res(r: U.Lu.R(List<&2, Q.Put> & U32), f: File, g: File,
  again: File -> File -> List<&2, Q.Put> -> U32 -> IO(Li.R(List<&2, Q.Put> & U32))) -> IO(Li.R(List<&2, Q.Put> & U32)):
  match r:
    case Done{p}:
      Li.loop.got(p, f, g, again)
    case Fail{e}:
      IO.pure(Li.R(List<&2, Q.Put> & U32), ((f, g), Fail{e}))

def Li.loop.files(fg: File & File, r: U.Lu.R(List<&2, Q.Put> & U32),
  again: File -> File -> List<&2, Q.Put> -> U32 -> IO(Li.R(List<&2, Q.Put> & U32))) -> IO(Li.R(List<&2, Q.Put> & U32)):
  match fg:
    case (f, g):
      Li.loop.res(r, f, g, again)

def Li.loop.made(q: Li.R(List<&2, Q.Put> & U32),
  again: File -> File -> List<&2, Q.Put> -> U32 -> IO(Li.R(List<&2, Q.Put> & U32))) -> IO(Li.R(List<&2, Q.Put> & U32)):
  match q:
    case (fg, r):
      Li.loop.files(fg, r, again)

def Li.loop.make(over: Bool, es: List<&2, T.Ent>, ops: List<&2, F.Op>, f: File, g: File, +cur: U32, acc: List<&2, Q.Put>,
  again: File -> File -> List<&2, Q.Put> -> U32 -> IO(Li.R(List<&2, Q.Put> & U32))) -> IO(Li.R(List<&2, Q.Put> & U32)):
  match over:
    case True{}:
      Li.fail(List<&2, Q.Put> & U32, f, g, "the layer's tar has more than " ++ U32.show(F.Fill.max_ents()) ++ " entries")
    case False{}:
      do IO<Li.R(List<&2, Q.Put> & U32)>:
        q : Li.R(List<&2, Q.Put> & U32) <- Li.put(es, ops, f, g, cur, acc)
        Li.loop.made(q, again)

# The unpack loop (src/layers/fill.bend) over the tar f, each regular
# file's data copied into the image g from cur: every entry with where
# its data went (reversed), and where the data ends.
def Li.loop(fuel: Nat, a: F.Act, f: File, g: File, acc: List<&2, Q.Put>, +cur: U32, +seen: U32) ->
  IO(Li.R(List<&2, Q.Put> & U32)):
  match fuel a:
    case 0n _:
      Li.fail(List<&2, Q.Put> & U32, f, g, "the layer's tar has too many entries")
    case 1n+k F.AHead{st, +at}:
      do IO<Li.R(List<&2, Q.Put> & U32)>:
        p : File & L.LayerFs.Res(List<&2, U32>) <- L.LayerFs.read(f, U.Lu.hi(at), U.Lu.lo(at), 512)
        Li.loop.read(p, g, f2 => g2 => bs => Li.loop(k, F.Fill.head(st, at, bs, ""), f2, g2, acc, cur, seen))
    case 1n+k F.AExt{st, +at, +n, next}:
      do IO<Li.R(List<&2, Q.Put> & U32)>:
        p : File & L.LayerFs.Res(List<&2, U32>) <- L.LayerFs.read(f, U.Lu.hi(at), U.Lu.lo(at), n)
        Li.loop.read(p, g, f2 => g2 => bs => Li.loop(k, F.Fill.ext(st, n, next, bs, ""), f2, g2, acc, cur, seen))
    case 1n+k F.AMake{st, +es, ops, next}:
      Li.loop.make(F.Fill.too_many(F.Fill.ents(seen, es)), es, ops, f, g, cur, acc,
        f2 => g2 => acc2 => cur2 => Li.loop(k, F.AHead{st, next}, f2, g2, acc2, cur2, F.Fill.ents(seen, es)))
    case 1n+k F.ADone{}:
      IO.pure(Li.R(List<&2, Q.Put> & U32), ((f, g), Done{(acc, cur)}))
    case 1n+k F.ABad{why}:
      Li.fail(List<&2, Q.Put> & U32, f, g, why)

# The image's tables and super block written, then an fsync.
def Li.write.synced(q: File & L.LayerFs.Res(Unit)) -> File & U.Lu.R(Unit):
  match q:
    case (g, Fail{e}):
      (g, Fail{U.Lu.why("syncing the image", e)})
    case (g, Done{u}):
      (g, Done{Unit{}})

def Li.write.sync(q: File & L.LayerFs.Res(Unit)) -> IO(File & U.Lu.R(Unit)):
  match q:
    case (g, Fail{e}):
      IO.pure(File & U.Lu.R(Unit), (g, Fail{U.Lu.why("writing the image's super block", e)}))
    case (g, Done{u}):
      do IO<File & U.Lu.R(Unit)>:
        r : File & L.LayerFs.Res(Unit) <- L.LayerFs.sync_file(g)
        return Li.write.synced(r)

def Li.write.sb(q: File & L.LayerFs.Res(Unit), +sb: +List<U32>) -> IO(File & U.Lu.R(Unit)):
  match q:
    case (g, Fail{e}):
      IO.pure(File & U.Lu.R(Unit), (g, Fail{U.Lu.why("writing the image's tables", e)}))
    case (g, Done{u}):
      do IO<File & U.Lu.R(Unit)>:
        r : File & L.LayerFs.Res(Unit) <- L.LayerFs.put_at(g, 0, 0, sb)
        Li.write.sync(r)

def Li.write(g: File, i: Q.Img, +cur: U32) -> IO(File & U.Lu.R(Unit)):
  match i:
    case Q.Img{tail, +sb, end}:
      do IO<File & U.Lu.R(Unit)>:
        q : File & L.LayerFs.Res(Unit) <- L.LayerFs.put_at(g, 0, cur, tail)
        Li.write.sb(q, sb)

def Li.ents(ps: List<&2, Q.Put>) -> List<&2, T.Ent>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{Q.Put{e, s}, t}:
      Con{e, Li.ents(t)}

# What the image held: the regular files' bytes and the inodes.
def Li.use(+puts: List<&2, Q.Put>) -> F.Use:
  F.Fill.use.of(Li.ents(puts))

def Li.closed(q: File & U.Lu.R(Unit), +use: F.Use) -> IO(U.Lu.R(F.Use)):
  match q:
    case (g, r):
      do IO<U.Lu.R(F.Use)>:
        File.close(g)
        return U.Lu.used(r, use)

def Li.tables.got(p: List<&2, Q.Put> & U32, g: File) -> IO(U.Lu.R(F.Use)):
  match p:
    case (acc, +cur):
      do IO<U.Lu.R(F.Use)>:
        +puts : List<&2, Q.Put> = List.reverse(&2, Q.Put, acc)
        w : File & U.Lu.R(Unit) <- Li.write(g, Q.Sqfs.image(puts, cur), cur)
        Li.closed(w, Li.use(puts))

def Li.tables.res(r: U.Lu.R(List<&2, Q.Put> & U32), f: File, g: File) -> IO(U.Lu.R(F.Use)):
  match r:
    case Fail{e}:
      do IO<U.Lu.R(F.Use)>:
        File.close(f)
        File.close(g)
        return Fail{e}
    case Done{p}:
      do IO<U.Lu.R(F.Use)>:
        File.close(f)
        Li.tables.got(p, g)

def Li.tables.files(fg: File & File, r: U.Lu.R(List<&2, Q.Put> & U32)) -> IO(U.Lu.R(F.Use)):
  match fg:
    case (f, g):
      Li.tables.res(r, f, g)

def Li.tables(q: Li.R(List<&2, Q.Put> & U32)) -> IO(U.Lu.R(F.Use)):
  match q:
    case (fg, r):
      Li.tables.files(fg, r)

def Li.of_tar.open(r: Result<&1, &1, U32 & String, File>, s: L.LayerFs.Res(File), +tar: String) -> IO(U.Lu.R(F.Use)):
  match r s:
    case Fail{e} Fail{x}:
      IO.pure(U.Lu.R(F.Use), Fail{U.Lu.why("opening " ++ tar, e)})
    case Fail{e} Done{g}:
      do IO<U.Lu.R(F.Use)>:
        File.close(g)
        return Fail{U.Lu.why("opening " ++ tar, e)}
    case Done{f} Fail{x}:
      do IO<U.Lu.R(F.Use)>:
        File.close(f)
        return Fail{U.Lu.why("making the layer's image", x)}
    case Done{f} Done{g}:
      do IO<U.Lu.R(F.Use)>:
        q : Li.R(List<&2, Q.Put> & U32) <- Li.loop(U.Lu.forever(), F.AHead{T.Tar.start(), N.Size.zero()}, f, g, Nil{}, 96, 0)
        Li.tables(q)

# The image of the layer tar at tar, written to a new file at img (made
# here with O_EXCL): what it holds (Fill.use.of), or why not. A failure
# may leave a partial file at img; the caller removes it.
def Li.of_tar(+tar: String, +img: String) -> IO(U.Lu.R(F.Use)):
  do IO<U.Lu.R(F.Use)>:
    s : L.LayerFs.Res(File) <- L.LayerFs.create(img)
    r : Result<&1, &1, U32 & String, File> <- File.open(tar, "r")
    Li.of_tar.open(r, s, tar)
