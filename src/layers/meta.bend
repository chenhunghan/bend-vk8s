import Base
import ./tar.bend as T
import ../oci/size.bend as N
import ../lib/sha256.bend as H

# The .bend-meta files of an unpacked layer: what bend-vmm's
# `--share DIR,meta` (src/fs/meta.bend in bend-vmm) reads to show the
# guest Linux metadata that a macOS volume cannot hold. Pure: the host
# writes each Side's text to its path under the layer's tmp directory.
#
# One file per directory that holds an entry, its first line
# "bend-meta 1", then one record per entry, as space-separated key=value
# tokens in this order:
#   name=NAME        the guest name (percent-encoded)
#   host=NAME        the host name (percent-encoded; src/layers/tar.bend)
#   type=f|d|l|c|b|p regular, directory, symlink, char, block, FIFO
#   mode=OCTAL       permission bits with setuid, setgid and sticky
#   uid=N gid=N
#   rdev=MAJ,MIN     char and block devices only
#   mtime=S[.N]      N the nanoseconds, as a number (absent when 0)
#   xattr.NAME=HEX   each extended attribute (NAME percent-encoded)
#   ino=N nlink=N    files with hard links only
# Percent-encoding keeps A-Z, a-z, 0-9, "-", ".", "_" and "~" and writes
# every other byte as %XX (uppercase hex); values are lowercase hex.
#
# Overlayfs, as containerd's OverlayConvertWhiteout writes it:
# - a whiteout is a 0,0 char device: type=c mode=0 rdev=0,0, with the
#   whiteout file's owner and time;
# - an opaque directory has xattr.trusted.overlay.opaque=79 ("y"), after
#   its own attributes. An opaque marker at the layer's root has no
#   record to go to and is dropped (overlayfs does not look up a layer's
#   root for it).
# Hard links: every name of one file shares its record (the first
# file's attributes), ino=N with N = seed * 2^32 + k (k numbers the
# layer's linked files from 1; the host passes Meta.seed of the chain ID,
# so two layers in one share do not reuse an inode), and nlink the
# number of names.
# A directory given twice keeps its last attributes, in the place of its
# first record.

type Grp is Data:
  Grp{links: U32, idx: U32}

# What a first pass over the entries learns: the index of each host
# path's last entry, that entry, the opaque directories, the hard-linked
# files (by host path) and how many there are.
type Pre is Data:
  Pre{last: Map<&2, Maybe<&2, U32>>, ents: Map<&2, Maybe<&2, T.Ent>>, opq: Map<&2, Maybe<&2, U32>>, grp: Map<&2, Maybe<&2, Grp>>, n: U32}

def Pre.new() -> Pre:
  Pre{Map.new(&2, Maybe<&2, U32>), Map.new(&2, Maybe<&2, T.Ent>), Map.new(&2, Maybe<&2, U32>), Map.new(&2, Maybe<&2, Grp>), 0}

def Pre.last(p: Pre) -> Map<&2, Maybe<&2, U32>>:
  match p:
    case Pre{l, e, o, g, n}:
      l

def Pre.ents(p: Pre) -> Map<&2, Maybe<&2, T.Ent>>:
  match p:
    case Pre{l, e, o, g, n}:
      e

def Pre.opq(p: Pre) -> Map<&2, Maybe<&2, U32>>:
  match p:
    case Pre{l, e, o, g, n}:
      o

def Pre.grp(p: Pre) -> Map<&2, Maybe<&2, Grp>>:
  match p:
    case Pre{l, e, o, g, n}:
      g

def Meta.pre.grp(m: Maybe<&2, Grp>, key: String, last: Map<&2, Maybe<&2, U32>>, ents: Map<&2, Maybe<&2, T.Ent>>, opq: Map<&2, Maybe<&2, U32>>, grp: Map<&2, Maybe<&2, Grp>>, +n: U32) -> Pre:
  match m:
    case None{}:
      Pre{last, ents, opq, T.Tar.lk.put(Grp, grp, key, Grp{1, (n + 1 : U32)}), (n + 1 : U32)}
    case Some{Grp{k, x}}:
      Pre{last, ents, opq, T.Tar.lk.put(Grp, grp, key, Grp{(k + 1 : U32), x}), n}

def Meta.pre.ty(ty: T.Ty, +i: U32, +e: T.Ent, last: Map<&2, Maybe<&2, U32>>, ents: Map<&2, Maybe<&2, T.Ent>>, opq: Map<&2, Maybe<&2, U32>>, +grp: Map<&2, Maybe<&2, Grp>>, n: U32) -> Pre:
  match ty:
    case T.TOpq{}:
      Pre{last, ents, T.Tar.lk.put(U32, opq, T.Ent.host(e), 1), grp, n}
    case T.THard{}:
      Meta.pre.grp(T.Tar.lk.get(Grp, grp, T.Ent.link(e)), T.Ent.link(e),
        T.Tar.lk.put(U32, last, T.Ent.host(e), i), T.Tar.lk.put(T.Ent, ents, T.Ent.host(e), e), opq, grp, n)
    case _:
      Pre{T.Tar.lk.put(U32, last, T.Ent.host(e), i), T.Tar.lk.put(T.Ent, ents, T.Ent.host(e), e), opq, grp, n}

def Meta.pre.one(p: Pre, +i: U32, +e: T.Ent) -> Pre:
  match p:
    case Pre{last, ents, opq, grp, n}:
      Meta.pre.ty(T.Ent.ty(e), i, e, last, ents, opq, grp, n)

def Meta.pre.go(es: List<&2, T.Ent>, +i: U32, p: Pre) -> Pre:
  match es:
    case Nil{}:
      p
    case Con{+e, t}:
      Meta.pre.go(t, (i + 1 : U32), Meta.pre.one(p, i, e))

# Encodings
# ---------

# The bytes a percent-encoded name keeps as they are.
def Meta.safe(+c: U32) -> Bool:
  (U32.is_ge(c, 97) && U32.is_le(c, 122)) || (U32.is_ge(c, 65) && U32.is_le(c, 90)) || (U32.is_ge(c, 48) && U32.is_le(c, 57)) || U32.is_eq(c, 45) || U32.is_eq(c, 46) || U32.is_eq(c, 95) || U32.is_eq(c, 126)

# The uppercase hex digit of 0..15.
def Meta.hexd(+d: U32) -> Char:
  Chr{(48 + d + 7 * Bool.to_u32(U32.is_gt(d, 9)) : U32)}

def Meta.pct.put(safe: Bool, +c: U32, rest: String) -> String:
  match safe:
    case True{}:
      SCon{Chr{c}, rest}
    case False{}:
      SCon{'%', SCon{Meta.hexd(U32.and(U32.shrn(c, 4n), 15)), SCon{Meta.hexd(U32.and(c, 15)), rest}}}

# A byte string, percent-encoded.
def Meta.pct(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{Chr{+c}, t}:
      Meta.pct.put(Meta.safe(c), c, Meta.pct(t))

def Meta.oct.go(n: Nat, +x: U32, acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n+k:
      Meta.oct.go(k, U32.shrn(x, 3n), SCon{Chr{(48 + U32.and(x, 7) : U32)}, acc})

# Octal, without leading zeros ("0" for 0).
def Meta.oct(+x: U32) -> String:
  N.Size.nonempty(N.Size.strip(Meta.oct.go(11n, x, "")))

def Meta.hexv(+c: U32) -> U32:
  Bool.pick(U32, U32.is_ge(c, 48) && U32.is_le(c, 57), (c - 48 : U32),
    Bool.pick(U32, U32.is_ge(c, 97) && U32.is_le(c, 102), (c - 87 : U32), 0))

def Meta.seed.go(n: Nat, s: String, acc: U32) -> U32:
  match n s:
    case 0n _:
      acc
    case 1n+k SNil{}:
      acc
    case 1n+k SCon{Chr{c}, t}:
      Meta.seed.go(k, t, (acc * 16 + Meta.hexv(c) : U32))

# The seed of a layer's inode numbers: the first 8 hex digits of its
# chain ID's hex.
def Meta.seed(hex: String) -> U32:
  Meta.seed.go(8n, hex, 0)

# Records
# -------

def Meta.letter(t: T.Ty) -> String:
  match t:
    case T.TReg{}:
      "f"
    case T.TDir{}:
      "d"
    case T.TSym{}:
      "l"
    case T.TChr{}:
      "c"
    case T.TBlk{}:
      "b"
    case T.TFifo{}:
      "p"
    case T.THard{}:
      "f"
    case T.TWh{}:
      "c"
    case T.TOpq{}:
      "d"

def Meta.mode(t: T.Ty, +m: U32) -> U32:
  match t:
    case T.TWh{}:
      0
    case _:
      U32.and(m, 4095)

def Meta.rdev(t: T.Ty, +ma: U32, +mi: U32) -> String:
  match t:
    case T.TChr{}:
      " rdev=" ++ U32.show(ma) ++ "," ++ U32.show(mi)
    case T.TBlk{}:
      " rdev=" ++ U32.show(ma) ++ "," ++ U32.show(mi)
    case T.TWh{}:
      " rdev=0,0"
    case _:
      ""

def Meta.nsec(+ns: U32) -> String:
  Bool.pick(String, U32.is_zero(ns), "", "." ++ U32.show(ns))

def Meta.xattrs(xs: List<&2, T.Xattr>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{T.Xattr{n, v}, t}:
      " xattr." ++ Meta.pct(n) ++ "=" ++ H.Sha256.hex(T.Tar.b(v)) ++ Meta.xattrs(t)

def Meta.opaque(b: Bool) -> String:
  match b:
    case True{}:
      " xattr.trusted.overlay.opaque=79"
    case False{}:
      ""

def Meta.ino(g: Maybe<&2, Grp>, seed: U32) -> String:
  match g:
    case None{}:
      ""
    case Some{Grp{k, x}}:
      " ino=" ++ N.Size.show(N.Size{seed, x}) ++ " nlink=" ++ U32.show((k + 1 : U32))

def Meta.is_set(m: Maybe<&2, U32>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{x}:
      True{}

# The last part of a path.
def Meta.base(p: String) -> String:
  T.Tar.last(String.split(p, '/'))

# The directory of a path ("" at the root).
def Meta.dir(p: String) -> String:
  String.join(T.Tar.init(String.split(p, '/')), "/")

# One record: the names of the entry, the attributes of a (the entry
# itself, or a hard link's first file).
def Meta.rec(path: String, host: String, a: T.Ent, opq: Bool, g: Maybe<&2, Grp>, seed: U32) -> String:
  match a:
    case T.Ent{ap, ah, +ty, mode, uid, gid, major, minor, mtime, nsec, xs, link, size}:
      "name=" ++ Meta.pct(Meta.base(path)) ++ " host=" ++ Meta.pct(Meta.base(host)) ++ " type=" ++ Meta.letter(ty) ++ " mode=" ++ Meta.oct(Meta.mode(ty, mode)) ++ " uid=" ++ U32.show(uid) ++ " gid=" ++ U32.show(gid) ++ Meta.rdev(ty, major, minor) ++ " mtime=" ++ U32.show(mtime) ++ Meta.nsec(nsec) ++ Meta.xattrs(xs) ++ Meta.opaque(opq) ++ Meta.ino(g, seed)

def Meta.src(m: Maybe<&2, T.Ent>, e: T.Ent) -> T.Ent:
  match m:
    case None{}:
      e
    case Some{x}:
      x

# The record of entry e.
def Meta.line(+p: Pre, +seed: U32, +e: T.Ent) -> String:
  +hard : Bool = T.Ty.is_hard(T.Ent.ty(e))
  +key : String = Bool.pick(String, hard, T.Ent.link(e), T.Ent.host(e))
  +a : T.Ent = Bool.pick(T.Ent, hard, Meta.src(T.Tar.lk.get(T.Ent, Pre.ents(p), key), e), e)
  Meta.rec(T.Ent.path(e), T.Ent.host(e), a, Meta.is_set(T.Tar.lk.get(U32, Pre.opq(p), T.Ent.host(e))), T.Tar.lk.get(Grp, Pre.grp(p), key), seed)

def Meta.is_last(m: Maybe<&2, U32>, +i: U32) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{x}:
      U32.is_eq(x, i)

def Meta.is_opq(t: T.Ty) -> Bool:
  match t:
    case T.TOpq{}:
      True{}
    case _:
      False{}

# Whether entry i gets a record: not an opaque marker, and the last entry
# of its host path.
def Meta.keep(+p: Pre, +i: U32, +e: T.Ent) -> Bool:
  Bool.not(Meta.is_opq(T.Ent.ty(e))) && Meta.is_last(T.Tar.lk.get(U32, Pre.last(p), T.Ent.host(e)), i)

# Files
# -----

# The directories in the order of their first record, and each one's
# records, last first.
type W is Data:
  W{dirs: List<&2, String>, lines: Map<&2, Maybe<&2, List<&2, String>>>}

def W.lines(w: W) -> Map<&2, Maybe<&2, List<&2, String>>>:
  match w:
    case W{d, l}:
      l

def Meta.w.put(m: Maybe<&2, List<&2, String>>, +dir: String, line: String, dirs: List<&2, String>, lines: Map<&2, Maybe<&2, List<&2, String>>>) -> W:
  match m:
    case None{}:
      W{Con{dir, dirs}, T.Tar.lk.put(List<&2, String>, lines, dir, [line])}
    case Some{ls}:
      W{dirs, T.Tar.lk.put(List<&2, String>, lines, dir, Con{line, ls})}

def Meta.w.add(m: Maybe<&2, List<&2, String>>, +dir: String, line: String, w: W) -> W:
  match w:
    case W{dirs, lines}:
      Meta.w.put(m, dir, line, dirs, lines)

def Meta.step(k: Bool, +p: Pre, +seed: U32, +e: T.Ent, +w: W) -> W:
  match k:
    case False{}:
      w
    case True{}:
      +dir : String = Meta.dir(T.Ent.host(e))
      Meta.w.add(T.Tar.lk.get(List<&2, String>, W.lines(w), dir), dir, Meta.line(p, seed, e), w)

def Meta.go(es: List<&2, T.Ent>, +i: U32, +p: Pre, +seed: U32, w: W) -> W:
  match es:
    case Nil{}:
      w
    case Con{+e, t}:
      Meta.go(t, (i + 1 : U32), p, seed, Meta.step(Meta.keep(p, i, e), p, seed, e, w))

# One .bend-meta file to write.
type Side is Data:
  Side{path: String, text: String}

def Meta.side(+dir: String, ls: List<&2, String>) -> Side:
  Side{T.Tar.join(dir, ".bend-meta"), "bend-meta 1\n" ++ String.join(List.reverse(&2, String, ls), "\n") ++ "\n"}

def Meta.sides.seq(ds: List<&2, String>, +lines: Map<&2, Maybe<&2, List<&2, String>>>) -> List<&2, Side>:
  match ds:
    case Nil{}:
      Nil{}
    case Con{+d, t}:
      Con{Meta.side(d, Maybe.default(&2, List<&2, String>, T.Tar.lk.get(List<&2, String>, lines, d), Nil{})), Meta.sides.seq(t, lines)}

# The directories are independent: each half is rendered in parallel,
# depth times over, and the halves keep their order.
def Meta.sides.par(depth: Nat, +ds: List<&2, String>, +lines: Map<&2, Maybe<&2, List<&2, String>>>) -> List<&2, Side>:
  match depth:
    case 0n:
      Meta.sides.seq(ds, lines)
    case 1n+k:
      +e : Nat = k
      +h : Nat = Nat.div(List.length(&2, String, ds), 2n)
      +a : List<&2, String> = List.take(&2, String, ds, h)
      +b : List<&2, String> = List.drop(&2, String, ds, h)
      x y = Meta.sides.par(e, a, lines) Meta.sides.par(e, b, lines)
      List.append(&2, Side, x, y)

def Meta.sides.w(w: W) -> List<&2, Side>:
  match w:
    case W{dirs, +lines}:
      Meta.sides.par(3n, List.reverse(&2, String, dirs), lines)

# The .bend-meta files of a layer: es are Tar.plan's entries (in their
# order), seed is Meta.seed of the layer's chain ID hex. Paths are
# relative to the layer's directory.
def Meta.sides(+seed: U32, +es: List<&2, T.Ent>) -> List<&2, Side>:
  +p : Pre = Meta.pre.go(es, 0, Pre.new())
  Meta.sides.w(Meta.go(es, 0, p, seed, W{Nil{}, Map.new(&2, Maybe<&2, List<&2, String>>)}))
