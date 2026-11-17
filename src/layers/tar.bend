import Base
import ../oci/size.bend as N
import ../lib/sha256.bend as H

# The unpack plan of an OCI image layer (a tar stream, already
# decompressed), as containerd's archive.Apply with
# archive.OverlayConvertWhiteout reads it (pkg/archive/tar.go,
# tar_opts_linux.go) over Go's archive/tar. Pure: the host reads the
# stream in 512-byte blocks and asks these defs what each block means.
#
# The host's loop:
#   st = Tar.start()
#   read a block b; step = Tar.head(st, b), then by step:
#     SMeta{st, n}  read n bytes (then up to a 512 boundary) of an
#                   extended header; step = Tar.ext(st, those n bytes)
#     SNext{st}     read the next block
#     SPut{st, es, n}  create es in order under the layer's tmp dir, each
#                   at its host path; the next n bytes (then up to 512)
#                   are the last entry's data when it is TReg, else skipped
#     SSkip{st, n}  skip n bytes (then up to 512): an ignored entry
#     SEnd{}        the archive ended (a zero block, or no more blocks)
#     SBad{why}     refuse the whole layer
# Tar.plan runs that loop over an archive held in memory (laws, tests).
#
# Names are byte strings: one Char per byte, as tar holds them.
#
# Headers: ustar (the 155-byte prefix joins the name), pax ("x": path,
# linkpath, size, uid, gid, mtime with nanoseconds, SCHILY.xattr.*; a
# pax record applies to the next entry only, a second "x" replaces the
# first, as Go's reader does), GNU long names ("L") and long link names
# ("K", both win over pax, as in Go). A global pax header ("g") is
# skipped, as containerd ignores it. Extended headers above 1 MiB are
# refused (Go's maxSpecialFileSize).
#
# Entries, as containerd applies them:
# - Type flags 0, 7 and NUL are regular files (NUL with a trailing "/" a
#   directory, as Go's reader), 1 hard links, 2 symlinks, 3 and 4 char and
#   block devices, 5 directories, 6 FIFOs. Other flags refuse the layer
#   (containerd: "unhandled tar header type").
# - Data follows regular files only (Go's header-only types have none).
# - A base name ".wh..wh..opq" makes its directory opaque (TOpq on the
#   directory); ".wh.NAME" is a whiteout of NAME (TWh: a 0,0 char device
#   in overlayfs). ".wh.", ".wh.." and ".wh..." are refused, as
#   containerd's validateWhiteout refuses a name outside its directory.
# - The root ("." or "./") is skipped (containerd: "resolved to root").
#
# Refused, so no host path ever leaves the layer's directory (containerd
# instead resolves such names inside the root; we refuse them):
# - an absolute name ("/etc/passwd"), a ".." component;
# - a name under an earlier non-directory of this layer, a symlink above
#   all (a symlink "a" then "a/b" would write through the link);
# - a hard link whose target is not an earlier non-directory entry of
#   this layer;
# - a second entry with the name of an earlier one, unless both are
#   directories (containerd merges directories; the last attributes win).
#
# A directory an entry needs but the layer does not hold is created
# (TDir, mode 0755, owner 0:0, mtime 0, as mkparent without parents).
#
# Host names: each entry gets a host path (Ent.host) apart from its
# guest path (Ent.path), so the layer can live on a case-insensitive,
# normalization-insensitive APFS volume (bend-vmm's `--share DIR,meta`
# shows guest names from .bend-meta, src/layers/meta.bend). A name keeps
# itself on the host unless one of these holds; then its host name is
# ".bend-" and the first 32 hex digits of the SHA-256 of its bytes:
# - it has a byte of 128 or more. Bend has no Unicode tables, so every
#   such name is hashed: this covers names that are not valid UTF-8 and
#   names that collide after Unicode case folding or NFD normalization;
# - it starts with ".bend-" in any case (so ".bend-meta" itself, and no
#   plain name can equal a hashed one);
# - an earlier name of the same directory equals it after ASCII case
#   folding (the earlier one keeps the plain name).
# Plain names are ASCII without "/" or NUL; hashed names are lowercase
# ASCII; two names of a directory never share a host name.
#
# Deviations from Go and containerd, all on input they accept but OCI
# image builders do not write: base-256 numbers (sizes of 8 GiB and
# more, negative times) are refused; only the unsigned header checksum is
# accepted; a single zero block ends the archive; numbers above 2^32 - 1
# (uid, gid, mode, mtime) are refused.

# Byte strings
# ------------

# The bytes of a byte string.
def Tar.b(s: String) -> +List<U32>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{Chr{c}, t}:
      Con{c, Tar.b(t)}

# The byte string of some bytes.
def Tar.s(bs: +List<U32>) -> String:
  match bs:
    case Nil{}:
      SNil{}
    case Con{c, t}:
      SCon{Chr{c}, Tar.s(t)}

def Tar.cstr.put(nul: Bool, c: U32, rest: String) -> String:
  match nul:
    case True{}:
      SNil{}
    case False{}:
      SCon{Chr{c}, rest}

# The bytes before the first NUL, as a byte string (Go: parseString).
def Tar.cstr(bs: +List<U32>) -> String:
  match bs:
    case Nil{}:
      SNil{}
    case Con{+c, t}:
      Tar.cstr.put(U32.is_eq(c, 0), c, Tar.cstr(t))

# a ++ "/" ++ b, or b when a is empty.
def Tar.join(+a: String, +b: String) -> String:
  Bool.pick(String, String.is_empty(a), b, a ++ "/" ++ b)

def Tar.beq(a: +List<U32>, b: +List<U32>) -> Bool:
  match a b:
    case Nil{} Nil{}:
      True{}
    case Nil{} Con{y, ys}:
      False{}
    case Con{x, xs} Nil{}:
      False{}
    case Con{x, xs} Con{y, ys}:
      U32.is_eq(x, y) && Tar.beq(xs, ys)

# The last byte, or 0.
def Tar.lastb(bs: +List<U32>) -> U32:
  Maybe.default(&2, U32, List.last(&2, U32, bs), 0)

# The bytes without the last one.
def Tar.dropl(+bs: +List<U32>) -> +List<U32>:
  List.take(&2, U32, bs, Nat.sub(List.length(&2, U32, bs), 1n))

# Path parts
# ----------

def Tar.last(ps: List<&2, String>) -> String:
  Maybe.default(&2, String, List.last(&2, String, ps), "")

def Tar.init.put(fin: Bool, h: String, rest: List<&2, String>) -> List<&2, String>:
  match fin:
    case True{}:
      Nil{}
    case False{}:
      Con{h, rest}

# The parts without the last one.
def Tar.init(ps: List<&2, String>) -> List<&2, String>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{h, +t}:
      Tar.init.put(List.is_empty(&2, String, t), h, Tar.init(t))

# Every prefix path of the parts, after pre: [a, b] gives ["a", "a/b"].
def Tar.prefixes(ps: List<&2, String>, +pre: String) -> List<&2, String>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{p, t}:
      +q : String = Tar.join(pre, p)
      Con{q, Tar.prefixes(t, q)}

# Map lookups
# -----------

def Tar.lk.snd(-V: Data, p: Map<&2, Maybe<&2, V>> & Maybe<&2, V>) -> Maybe<&2, V>:
  match p:
    case (m, v):
      v

def Tar.lk.get(-V: Data, m: Map<&2, Maybe<&2, V>>, key: String) -> Maybe<&2, V>:
  Tar.lk.snd(V, Map.get(Maybe<&2, V>, None{}, m, key))

def Tar.lk.put(-V: Data, m: Map<&2, Maybe<&2, V>>, key: String, x: V) -> Map<&2, Maybe<&2, V>>:
  Map.set(&2, Maybe<&2, V>, m, key, Some{x})

# Entries
# -------

# What an entry is once whiteouts are converted.
type Ty is Data:
  TReg{}
  TDir{}
  TSym{}
  TChr{}
  TBlk{}
  TFifo{}
  THard{}
  TWh{}
  TOpq{}

# An extended attribute: its name and value, byte strings.
type Xattr is Data:
  Xattr{name: String, value: String}

# One thing to create in the layer.
# path: the guest path in the layer ("etc/passwd"; "" for the root);
# host: its host path (as path, with host names); for TOpq the directory.
# link: a symlink's target as written, a hard link's target's host path.
# size: a regular file's data length (zero for every other type).
# A TWh is created as an empty regular file at host; a TOpq creates
# nothing (its directory is opaque in .bend-meta).
type Ent is Data:
  Ent{path: String, host: String, ty: Ty, mode: U32, uid: U32, gid: U32, major: U32, minor: U32, mtime: U32, nsec: U32, xattrs: List<&2, Xattr>, link: String, size: N.Size}

def Ent.path(e: Ent) -> String:
  match e:
    case Ent{p, h, t, m, u, g, ma, mi, mt, ns, xs, l, sz}:
      p

def Ent.host(e: Ent) -> String:
  match e:
    case Ent{p, h, t, m, u, g, ma, mi, mt, ns, xs, l, sz}:
      h

def Ent.ty(e: Ent) -> Ty:
  match e:
    case Ent{p, h, t, m, u, g, ma, mi, mt, ns, xs, l, sz}:
      t

def Ent.link(e: Ent) -> String:
  match e:
    case Ent{p, h, t, m, u, g, ma, mi, mt, ns, xs, l, sz}:
      l

def Ty.is_dir(t: Ty) -> Bool:
  match t:
    case TDir{}:
      True{}
    case _:
      False{}

def Ty.is_hard(t: Ty) -> Bool:
  match t:
    case THard{}:
      True{}
    case _:
      False{}

def Ty.is_reg(t: Ty) -> Bool:
  match t:
    case TReg{}:
      True{}
    case _:
      False{}

# A hard link may name an earlier file, symlink, device, FIFO or link.
def Ty.linkable(t: Ty) -> Bool:
  match t:
    case TDir{}:
      False{}
    case TWh{}:
      False{}
    case TOpq{}:
      False{}
    case _:
      True{}

# Numbers
# -------

def Tar.ltrim.put(skip: Bool, c: U32, t: +List<U32>, rest: +List<U32>) -> +List<U32>:
  match skip:
    case True{}:
      rest
    case False{}:
      Con{c, t}

# Without the leading spaces and NULs.
def Tar.ltrim(bs: +List<U32>) -> +List<U32>:
  match bs:
    case Nil{}:
      Nil{}
    case Con{+c, +t}:
      Tar.ltrim.put(U32.is_eq(c, 0) || U32.is_eq(c, 32), c, t, Tar.ltrim(t))

# Without the leading and trailing spaces and NULs (Go: bytes.Trim(b, " \x00")).
def Tar.trim(bs: +List<U32>) -> +List<U32>:
  List.reverse(&2, U32, Tar.ltrim(List.reverse(&2, U32, Tar.ltrim(bs))))

def Tar.oct.go(bs: +List<U32>, acc: N.Size) -> Maybe<&2, N.Size>:
  match bs:
    case Nil{}:
      Some{acc}
    case Con{+c, t}:
      Bool.pick(Maybe<&2, N.Size>, U32.is_ge(c, 48) && U32.is_le(c, 55),
        Tar.oct.go(t, N.Size.add(N.Size.shl(3n, acc), N.Size.of((c - 48 : U32)))), None{})

# An octal header field (Go: parseOctal); empty is 0. A base-256 field
# (first byte 128 or more) is not octal, so it is refused too.
def Tar.num(bs: +List<U32>) -> Maybe<&2, N.Size>:
  Tar.oct.go(Tar.trim(bs), N.Size.zero())

def Tar.small(m: Maybe<&2, N.Size>) -> Maybe<&2, U32>:
  match m:
    case None{}:
      None{}
    case Some{N.Size{+h, l}}:
      Bool.pick(Maybe<&2, U32>, U32.is_zero(h), Some{l}, None{})

def Tar.num32(bs: +List<U32>) -> Maybe<&2, U32>:
  Tar.small(Tar.num(bs))

# A decimal number below 2^32.
def Tar.dec32(+s: String) -> Maybe<&2, U32>:
  Tar.small(N.Size.read(s))

# Header blocks
# -------------

# One parsed header block.
type Hdr is Data:
  Hdr{name: String, mode: U32, uid: U32, gid: U32, size: N.Size, mtime: U32, flag: U32, link: String, major: U32, minor: U32}

def Hdr.flag(h: Hdr) -> U32:
  match h:
    case Hdr{n, m, u, g, s, t, f, l, ma, mi}:
      f

def Hdr.size(h: Hdr) -> N.Size:
  match h:
    case Hdr{n, m, u, g, s, t, f, l, ma, mi}:
      s

# len bytes of the block from off.
def Tar.at(+blk: +List<U32>, off: Nat, len: Nat) -> +List<U32>:
  List.take(&2, U32, List.drop(&2, U32, blk, off), len)

def Tar.sum(bs: +List<U32>, acc: U32) -> U32:
  match bs:
    case Nil{}:
      acc
    case Con{c, t}:
      Tar.sum(t, (acc + c : U32))

# The unsigned checksum: every byte, the checksum field as 8 spaces.
def Tar.cks(+blk: +List<U32>) -> U32:
  Tar.sum(List.take(&2, U32, blk, 148n), Tar.sum(List.drop(&2, U32, blk, 156n), 256))

def Tar.cks_ok.of(m: Maybe<&2, U32>, +got: U32) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{want}:
      U32.is_eq(want, got)

def Tar.cks_ok(+blk: +List<U32>) -> Bool:
  Tar.cks_ok.of(Tar.num32(Tar.at(blk, 148n, 8n)), Tar.cks(blk))

def Tar.is_zero(bs: +List<U32>) -> Bool:
  match bs:
    case Nil{}:
      True{}
    case Con{c, t}:
      U32.is_zero(c) && Tar.is_zero(t)

# POSIX ustar or pax: magic "ustar\0". Only then does the prefix field
# hold a name prefix (GNU's magic is "ustar " and keeps times there).
def Tar.ustar(+blk: +List<U32>) -> Bool:
  Tar.beq(Tar.at(blk, 257n, 6n), [117, 115, 116, 97, 114, 0])

def Tar.prefix(+blk: +List<U32>) -> String:
  Bool.pick(String, Tar.ustar(blk), Tar.cstr(Tar.at(blk, 345n, 155n)), "")

def Tar.flag(+blk: +List<U32>) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, blk, 156n), 0)

def Tar.hdr.make(name: String, link: String, flag: U32, mode: Maybe<&2, U32>, uid: Maybe<&2, U32>, gid: Maybe<&2, U32>, size: Maybe<&2, N.Size>, mtime: Maybe<&2, U32>, major: Maybe<&2, U32>, minor: Maybe<&2, U32>) -> Result<&2, &2, String, Hdr>:
  match mode uid gid size mtime major minor:
    case Some{m} Some{u} Some{g} Some{s} Some{t} Some{ma} Some{mi}:
      Done{Hdr{name, m, u, g, s, t, flag, link, ma, mi}}
    case _ _ _ _ _ _ _:
      Fail{"tar: invalid number in header"}

def Tar.hdr.fields(+blk: +List<U32>) -> Result<&2, &2, String, Hdr>:
  Tar.hdr.make(
    Tar.join(Tar.prefix(blk), Tar.cstr(Tar.at(blk, 0n, 100n))),
    Tar.cstr(Tar.at(blk, 157n, 100n)),
    Tar.flag(blk),
    Tar.num32(Tar.at(blk, 100n, 8n)),
    Tar.num32(Tar.at(blk, 108n, 8n)),
    Tar.num32(Tar.at(blk, 116n, 8n)),
    Tar.num(Tar.at(blk, 124n, 12n)),
    Tar.num32(Tar.at(blk, 136n, 12n)),
    Tar.num32(Tar.at(blk, 329n, 8n)),
    Tar.num32(Tar.at(blk, 337n, 8n)))

def Tar.hdr.check(ok: Bool, +blk: +List<U32>) -> Result<&2, &2, String, Hdr>:
  match ok:
    case True{}:
      Tar.hdr.fields(blk)
    case False{}:
      Fail{"tar: invalid header checksum"}

# A header block (512 bytes, not all zero).
def Tar.hdr(+blk: +List<U32>) -> Result<&2, &2, String, Hdr>:
  Tar.hdr.check(Tar.cks_ok(blk), blk)

# Pax records
# -----------

type Kv is Data:
  Kv{key: String, value: String}

# A byte list cut at its first sep: the bytes before, after, and whether
# sep was there.
type Cut is Data:
  Cut{before: +List<U32>, after: +List<U32>, found: Bool}

def Tar.cut.add(c: U32, r: Cut) -> Cut:
  match r:
    case Cut{b, a, f}:
      Cut{Con{c, b}, a, f}

def Tar.cut.pick(hit: Bool, c: U32, t: +List<U32>, r: Cut) -> Cut:
  match hit:
    case True{}:
      Cut{Nil{}, t, True{}}
    case False{}:
      Tar.cut.add(c, r)

def Tar.cut(bs: +List<U32>, +sep: U32) -> Cut:
  match bs:
    case Nil{}:
      Cut{Nil{}, Nil{}, False{}}
    case Con{+c, +t}:
      Tar.cut.pick(U32.is_eq(c, sep), c, t, Tar.cut(t, sep))

# The decimal length that opens a pax record, up to its space.
def Tar.pax.len(bs: +List<U32>, +acc: U32, +any: Bool) -> Maybe<&2, U32>:
  match bs:
    case Nil{}:
      None{}
    case Con{+c, t}:
      Bool.pick(Maybe<&2, U32>, U32.is_eq(c, 32),
        Bool.pick(Maybe<&2, U32>, any, Some{acc}, None{}),
        Bool.pick(Maybe<&2, U32>, U32.is_ge(c, 48) && U32.is_le(c, 57) && U32.is_lt(acc, 1048577),
          Tar.pax.len(t, (acc * 10 + c - 48 : U32), True{}), None{}))

def Tar.pax.n(m: Maybe<&2, U32>) -> Nat:
  match m:
    case None{}:
      0n
    case Some{x}:
      U32.to_nat(x)

def Tar.pax.kv.cut(c: Cut) -> Maybe<&2, Kv>:
  match c:
    case Cut{b, a, f}:
      Bool.pick(Maybe<&2, Kv>, f, Some{Kv{Tar.s(b), Tar.s(a)}}, None{})


def Cut.after(c: Cut) -> +List<U32>:
  match c:
    case Cut{b, a, f}:
      a

def Tar.pax.kv.ok(ok: Bool, rec: +List<U32>) -> Maybe<&2, Kv>:
  match ok:
    case False{}:
      None{}
    case True{}:
      Tar.pax.kv.cut(Tar.cut(Tar.dropl(Cut.after(Tar.cut(rec, 32))), 61))

# One record "LEN key=value\n" of exactly n bytes.
def Tar.pax.kv(+rec: +List<U32>, +n: Nat) -> Maybe<&2, Kv>:
  Tar.pax.kv.ok(Nat.is_gt(n, 0n) && Nat.is_eq(List.length(&2, U32, rec), n) && U32.is_eq(Tar.lastb(rec), 10), rec)

def Tar.pax.cons.rest(k: Kv, r: Maybe<&2, List<&2, Kv>>) -> Maybe<&2, List<&2, Kv>>:
  match r:
    case None{}:
      None{}
    case Some{xs}:
      Some{Con{k, xs}}

def Tar.pax.cons(done: Bool, kv: Maybe<&2, Kv>, r: Maybe<&2, List<&2, Kv>>) -> Maybe<&2, List<&2, Kv>>:
  match done kv:
    case True{} _:
      Some{Nil{}}
    case False{} None{}:
      None{}
    case False{} Some{k}:
      Tar.pax.cons.rest(k, r)

def Tar.pax.go(fuel: Nat, +bs: +List<U32>) -> Maybe<&2, List<&2, Kv>>:
  match fuel:
    case 0n:
      Bool.pick(Maybe<&2, List<&2, Kv>>, List.is_empty(&2, U32, bs), Some{Nil{}}, None{})
    case 1n+f:
      +n : Nat = Tar.pax.n(Tar.pax.len(bs, 0, False{}))
      Tar.pax.cons(List.is_empty(&2, U32, bs), Tar.pax.kv(List.take(&2, U32, bs, n), n), Tar.pax.go(f, List.drop(&2, U32, bs, n)))

# The records of a pax header's data, in order; None when one is
# malformed (Go: parsePAX).
def Tar.pax(+bs: +List<U32>) -> Maybe<&2, List<&2, Kv>>:
  Tar.pax.go(List.length(&2, U32, bs), bs)

# The value of the first record named key.
def Tar.pax.get(kvs: List<&2, Kv>, +key: String) -> Maybe<&2, String>:
  match kvs:
    case Nil{}:
      None{}
    case Con{Kv{k, v}, t}:
      Bool.pick(Maybe<&2, String>, String.eq(k, key), Some{v}, Tar.pax.get(t, key))

def Tar.xattrs.put(keep: Bool, x: Xattr, rest: List<&2, Xattr>) -> List<&2, Xattr>:
  match keep:
    case True{}:
      Con{x, rest}
    case False{}:
      rest

# The SCHILY.xattr.NAME records, in order, as extended attributes.
def Tar.xattrs(kvs: List<&2, Kv>) -> List<&2, Xattr>:
  match kvs:
    case Nil{}:
      Nil{}
    case Con{Kv{+k, v}, t}:
      Tar.xattrs.put(String.starts_with(k, "SCHILY.xattr.") && Bool.not(String.eq(k, "SCHILY.xattr.")), Xattr{String.drop(k, 13n), v}, Tar.xattrs(t))

# Times
# -----

type Time is Data:
  Time{sec: U32, nsec: U32}

# A string cut at its first sep.
type SCut is Data:
  SCut{before: String, after: String, found: Bool}

def Tar.scut.add(c: Char, r: SCut) -> SCut:
  match r:
    case SCut{b, a, f}:
      SCut{SCon{c, b}, a, f}

def Tar.scut.pick(hit: Bool, c: Char, t: String, r: SCut) -> SCut:
  match hit:
    case True{}:
      SCut{SNil{}, t, True{}}
    case False{}:
      Tar.scut.add(c, r)

def Tar.scut(s: String, +sep: Char) -> SCut:
  match s:
    case SNil{}:
      SCut{SNil{}, SNil{}, False{}}
    case SCon{+c, +t}:
      Tar.scut.pick(Char.is_eq(c, sep), c, t, Tar.scut(t, sep))

# Nanoseconds from the digits after the point: the first nine, padded
# with zeros (Go: parsePAXTime).
def Tar.ns(n: Nat, s: String, acc: U32) -> U32:
  match n s:
    case 0n _:
      acc
    case 1n+k SNil{}:
      Tar.ns(k, SNil{}, (acc * 10 : U32))
    case 1n+k SCon{c, t}:
      Tar.ns(k, t, (acc * 10 + Char.to_u32(c) - 48 : U32))

def Tar.time.make(s: Maybe<&2, U32>, ok: Bool, frac: String) -> Maybe<&2, Time>:
  match s ok:
    case Some{x} True{}:
      Some{Time{x, Tar.ns(9n, frac, 0)}}
    case _ _:
      None{}

def Tar.time.cut(c: SCut) -> Maybe<&2, Time>:
  match c:
    case SCut{b, +a, f}:
      Tar.time.make(Tar.dec32(b), N.Size.digits(a), a)

# A pax time "S" or "S.F" (seconds since 1970, F its fraction); negative
# times are refused.
def Tar.time(s: String) -> Maybe<&2, Time>:
  Tar.time.cut(Tar.scut(s, '.'))

# Merging extended headers
# ------------------------

# What extended headers left for the next entry: the last pax records
# and GNU long name and long link name.
type Pend is Data:
  Pend{pax: List<&2, Kv>, long: Maybe<&2, String>, llink: Maybe<&2, String>}

def Pend.none() -> Pend:
  Pend{Nil{}, None{}, None{}}

# A header with its extended headers applied.
type Head is Data:
  Head{name: String, link: String, flag: U32, mode: U32, uid: U32, gid: U32, size: N.Size, mtime: U32, nsec: U32, major: U32, minor: U32, xattrs: List<&2, Xattr>}

def Head.name(h: Head) -> String:
  match h:
    case Head{n, l, f, m, u, g, s, t, ns, ma, mi, xs}:
      n

def Head.link(h: Head) -> String:
  match h:
    case Head{n, l, f, m, u, g, s, t, ns, ma, mi, xs}:
      l

def Head.flag(h: Head) -> U32:
  match h:
    case Head{n, l, f, m, u, g, s, t, ns, ma, mi, xs}:
      f

def Head.size(h: Head) -> N.Size:
  match h:
    case Head{n, l, f, m, u, g, s, t, ns, ma, mi, xs}:
      s

def Tar.pick_str(a: Maybe<&2, String>, b: Maybe<&2, String>, c: String) -> String:
  match a:
    case Some{x}:
      x
    case None{}:
      Maybe.default(&2, String, b, c)

def Tar.or_num(m: Maybe<&2, String>, d: U32) -> Maybe<&2, U32>:
  match m:
    case None{}:
      Some{d}
    case Some{s}:
      Tar.dec32(s)

def Tar.or_size(m: Maybe<&2, String>, d: N.Size) -> Maybe<&2, N.Size>:
  match m:
    case None{}:
      Some{d}
    case Some{s}:
      N.Size.read(s)

def Tar.or_time(m: Maybe<&2, String>, d: U32) -> Maybe<&2, Time>:
  match m:
    case None{}:
      Some{Time{d, 0}}
    case Some{s}:
      Tar.time(s)

def Tar.head.make(name: String, link: String, flag: U32, mode: U32, uid: Maybe<&2, U32>, gid: Maybe<&2, U32>, size: Maybe<&2, N.Size>, t: Maybe<&2, Time>, major: U32, minor: U32, xs: List<&2, Xattr>) -> Result<&2, &2, String, Head>:
  match uid gid size t:
    case Some{u} Some{g} Some{s} Some{Time{sec, ns}}:
      Done{Head{name, link, flag, mode, u, g, s, sec, ns, major, minor, xs}}
    case _ _ _ _:
      Fail{"tar: invalid PAX record"}

# A header with the pending extended headers (Go: mergePAX, then the GNU
# long names over it).
def Tar.merge(h: Hdr, p: Pend) -> Result<&2, &2, String, Head>:
  match h p:
    case Hdr{name, mode, uid, gid, size, mtime, flag, link, major, minor} Pend{+pax, long, llink}:
      +rp : List<&2, Kv> = List.reverse(&2, Kv, pax)
      Tar.head.make(
        Tar.pick_str(long, Tar.pax.get(rp, "path"), name),
        Tar.pick_str(llink, Tar.pax.get(rp, "linkpath"), link),
        flag, mode,
        Tar.or_num(Tar.pax.get(rp, "uid"), uid),
        Tar.or_num(Tar.pax.get(rp, "gid"), gid),
        Tar.or_size(Tar.pax.get(rp, "size"), size),
        Tar.or_time(Tar.pax.get(rp, "mtime"), mtime),
        major, minor, Tar.xattrs(pax))

# Names
# -----

def Tar.parts.put(skip: Bool, p: String, rest: List<&2, String>) -> List<&2, String>:
  match skip:
    case True{}:
      rest
    case False{}:
      Con{p, rest}

# The parts of a name without the empty and "." ones (Go: filepath.Clean
# of a relative name, before ".." is looked at).
def Tar.parts(ps: List<&2, String>) -> List<&2, String>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{+p, t}:
      Tar.parts.put(String.is_empty(p) || String.eq(p, "."), p, Tar.parts(t))

def Tar.has_dotdot(ps: List<&2, String>) -> Bool:
  match ps:
    case Nil{}:
      False{}
    case Con{p, t}:
      String.eq(p, "..") || Tar.has_dotdot(t)

# What a name is.
type Path is Data:
  PBad{why: String}
  PRoot{}
  POk{parts: List<&2, String>}

def Tar.path.parts(+ps: List<&2, String>, +name: String) -> Path:
  Bool.pick(Path, Tar.has_dotdot(ps), PBad{"tar: path traversal: " ++ name},
    Bool.pick(Path, List.is_empty(&2, String, ps), PRoot{}, POk{ps}))

def Tar.path(+name: String) -> Path:
  Bool.pick(Path, String.starts_with(name, "/"), PBad{"tar: absolute path: " ++ name},
    Tar.path.parts(Tar.parts(String.split(name, '/')), name))

# What an entry's name means once whiteouts are read.
type Mark is Data:
  MPlain{parts: List<&2, String>}
  MWh{parts: List<&2, String>}
  MOpq{parts: List<&2, String>}
  MBad{why: String}

def Tar.mark.wh(+n: String, dir: List<&2, String>) -> Mark:
  Bool.pick(Mark, String.is_empty(n) || String.eq(n, ".") || String.eq(n, ".."), MBad{"tar: invalid whiteout name: .wh." ++ n},
    MWh{List.append(&2, String, dir, [n])})

def Tar.mark.base(+b: String, +dir: List<&2, String>) -> Mark:
  Bool.pick(Mark, String.eq(b, ".wh..wh..opq"), MOpq{dir},
    Bool.pick(Mark, String.starts_with(b, ".wh."), Tar.mark.wh(String.drop(b, 4n), dir),
      MPlain{List.append(&2, String, dir, [b])}))

def Tar.mark(+parts: List<&2, String>) -> Mark:
  Tar.mark.base(Tar.last(parts), Tar.init(parts))

# Host names
# ----------

def Tar.ascii(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{Chr{c}, t}:
      U32.is_lt(c, 128) && Tar.ascii(t)

# A name that may keep itself on the host, unless an earlier one of its
# directory folds to it.
def Tar.plain_ok(+name: String) -> Bool:
  Bool.not(String.starts_with(String.to_lower(name), ".bend-")) && Tar.ascii(name)

# The host name of a name that may not keep itself.
def Tar.hashed(name: String) -> String:
  ".bend-" ++ String.take(H.Sha256.hex(H.Sha256.digest(Tar.b(name))), 32n)

# What the layer holds so far, by guest path, and which folded names each
# directory has given out.
type Node is Data:
  Node{host: String, ty: Ty}

type Ns is Data:
  Ns{nodes: Map<&2, Maybe<&2, Node>>, names: Map<&2, Maybe<&2, String>>}

def Ns.new() -> Ns:
  Ns{Map.new(&2, Maybe<&2, Node>), Map.new(&2, Maybe<&2, String>)}

def Ns.node(ns: Ns, key: String) -> Maybe<&2, Node>:
  match ns:
    case Ns{nodes, names}:
      Tar.lk.get(Node, nodes, key)

def Ns.node.put(ns: Ns, key: String, n: Node) -> Ns:
  match ns:
    case Ns{nodes, names}:
      Ns{Tar.lk.put(Node, nodes, key, n), names}

def Ns.name(ns: Ns, key: String) -> Maybe<&2, String>:
  match ns:
    case Ns{nodes, names}:
      Tar.lk.get(String, names, key)

def Ns.name.put(ns: Ns, key: String, n: String) -> Ns:
  match ns:
    case Ns{nodes, names}:
      Ns{nodes, Tar.lk.put(String, names, key, n)}

# A host name given out, and the namespace that records it.
type Named is Data:
  Named{ns: Ns, host: String}

def Tar.assign.seen(m: Maybe<&2, String>, +name: String, ns: Ns, key: String) -> Named:
  match m:
    case None{}:
      Named{Ns.name.put(ns, key, name), name}
    case Some{g}:
      Named{ns, Bool.pick(String, String.eq(g, name), name, Tar.hashed(name))}

def Tar.assign.plain(ok: Bool, +ns: Ns, +key: String, +name: String) -> Named:
  match ok:
    case True{}:
      Tar.assign.seen(Ns.name(ns, key), name, ns, key)
    case False{}:
      Named{ns, Tar.hashed(name)}

# The host name of name in the directory dir (a guest path).
def Tar.assign(+ns: Ns, +dir: String, +name: String) -> Named:
  Tar.assign.plain(Tar.plain_ok(name), ns, dir ++ "/" ++ String.to_lower(name), name)

# Implicit directories
# --------------------

# The namespace, the host path of the last directory made sure of, and
# the directories created on the way.
type Mk is Data:
  Mk{ns: Ns, host: String, ents: List<&2, Ent>}

def Tar.implicit(path: String, host: String) -> Ent:
  Ent{path, host, TDir{}, 493, 0, 0, 0, 0, 0, 0, Nil{}, "", N.Size.zero()}

def Tar.mkdir.new(n: Named, +phost: String, +path: String, ents: List<&2, Ent>) -> Mk:
  match n:
    case Named{ns, hn}:
      +h : String = Tar.join(phost, hn)
      Mk{Ns.node.put(ns, path, Node{h, TDir{}}), h, List.append(&2, Ent, ents, [Tar.implicit(path, h)])}

def Tar.mkdir.got(m: Maybe<&2, Node>, +ns: Ns, +dir: String, +phost: String, +name: String, +path: String, ents: List<&2, Ent>) -> Mk:
  match m:
    case Some{Node{h, ty}}:
      Mk{ns, h, ents}
    case None{}:
      Tar.mkdir.new(Tar.assign(ns, dir, name), phost, path, ents)

def Tar.mkdir(mk: Mk, +dir: String, +p: String, +path: String) -> Mk:
  match mk:
    case Mk{+ns, phost, ents}:
      Tar.mkdir.got(Ns.node(ns, path), ns, dir, phost, p, path, ents)

# Makes sure every directory of the parts exists, from the root down.
def Tar.mkdirs(ps: List<&2, String>, +dir: String, mk: Mk) -> Mk:
  match ps:
    case Nil{}:
      mk
    case Con{+p, t}:
      +path : String = Tar.join(dir, p)
      Tar.mkdirs(t, path, Tar.mkdir(mk, dir, p, path))

# Whether a path in ps is in the layer as a non-directory.
def Tar.not_dir(m: Maybe<&2, Node>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{Node{h, ty}}:
      Bool.not(Ty.is_dir(ty))

def Tar.blocked(ps: List<&2, String>, +ns: Ns) -> Bool:
  match ps:
    case Nil{}:
      False{}
    case Con{p, t}:
      Tar.not_dir(Ns.node(ns, p)) || Tar.blocked(t, ns)

# The stream
# ----------

# The planner's state between blocks: what extended headers left, the
# type flag of an extended header whose data comes next, the namespace.
type St is Data:
  St{pend: Pend, want: U32, ns: Ns}

# What to do after a block or an extended header's data (see the top).
type Step is Data:
  SNext{st: St}
  SMeta{st: St, size: N.Size}
  SPut{st: St, ents: List<&2, Ent>, size: N.Size}
  SSkip{st: St, size: N.Size}
  SEnd{}
  SBad{why: String}

def Tar.start() -> St:
  St{Pend.none(), 0, Ns.new()}

def St.clear(st: St) -> St:
  match st:
    case St{p, w, ns}:
      St{Pend.none(), 0, ns}

def St.want(st: St, flag: U32) -> St:
  match st:
    case St{p, w, ns}:
      St{p, flag, ns}

def St.pend(st: St) -> Pend:
  match st:
    case St{p, w, ns}:
      p

# The data length of an entry of tar type ty (Go's header-only types:
# none).
def Tar.dsize(ty: Ty, size: N.Size) -> N.Size:
  match ty:
    case TReg{}:
      size
    case _:
      N.Size.zero()

# The entry type of a type flag (name for the NUL flag), or None.
def Tar.ty(+flag: U32, +name: String) -> Maybe<&2, Ty>:
  Bool.pick(Maybe<&2, Ty>, U32.is_eq(flag, 48) || U32.is_eq(flag, 55), Some{TReg{}},
  Bool.pick(Maybe<&2, Ty>, U32.is_eq(flag, 0), Some{Bool.pick(Ty, String.ends_with(name, "/"), TDir{}, TReg{})},
  Bool.pick(Maybe<&2, Ty>, U32.is_eq(flag, 49), Some{THard{}},
  Bool.pick(Maybe<&2, Ty>, U32.is_eq(flag, 50), Some{TSym{}},
  Bool.pick(Maybe<&2, Ty>, U32.is_eq(flag, 51), Some{TChr{}},
  Bool.pick(Maybe<&2, Ty>, U32.is_eq(flag, 52), Some{TBlk{}},
  Bool.pick(Maybe<&2, Ty>, U32.is_eq(flag, 53), Some{TDir{}},
  Bool.pick(Maybe<&2, Ty>, U32.is_eq(flag, 54), Some{TFifo{}}, None{}))))))))

# One entry from a header: path and host, its type, and its link.
def Tar.ent(path: String, host: String, +ty: Ty, link: String, hd: Head) -> Ent:
  match hd:
    case Head{n, l, f, mode, uid, gid, size, mtime, nsec, major, minor, xs}:
      Ent{path, host, ty, mode, uid, gid, major, minor, mtime, nsec, xs, link, Tar.dsize(ty, size)}

# A hard link's target, as a host path, or why it is refused.
type Lnk is Data:
  LOk{link: String}
  LBad{why: String}

def Tar.link.ty(ok: Bool, h: String) -> Lnk:
  match ok:
    case True{}:
      LOk{h}
    case False{}:
      LBad{"tar: hard link to a directory or whiteout"}

def Tar.link.node(m: Maybe<&2, Node>) -> Lnk:
  match m:
    case None{}:
      LBad{"tar: hard link target is not an earlier entry of the layer"}
    case Some{Node{h, ty}}:
      Tar.link.ty(Ty.linkable(ty), h)

def Tar.link.path(p: Path, ns: Ns) -> Lnk:
  match p:
    case PBad{why}:
      LBad{why}
    case PRoot{}:
      LBad{"tar: hard link to the root"}
    case POk{ps}:
      Tar.link.node(Ns.node(ns, String.join(ps, "/")))

def Tar.link(+ty: Ty, +raw: String, +ns: Ns) -> Lnk:
  Bool.pick(Lnk, Ty.is_hard(ty), Tar.link.path(Tar.path(raw), ns), LOk{raw})

def Tar.put.new.named(n: Named, +phost: String, +path: String, +ty: Ty, +link: String, dsz: N.Size, +hd: Head, ents: List<&2, Ent>) -> Step:
  match n:
    case Named{ns, hn}:
      +host : String = Tar.join(phost, hn)
      +node : Node = Node{Bool.pick(String, Ty.is_hard(ty), link, host), ty}
      SPut{St{Pend.none(), 0, Ns.node.put(ns, path, node)}, List.append(&2, Ent, ents, [Tar.ent(path, host, ty, link, hd)]), dsz}

# A new entry at parts: its parents made sure of, its host name given.
# A hard link's node records its target's host path, so a link to a link
# names the first file.
def Tar.put.new.mk(mk: Mk, +parts: List<&2, String>, +ty: Ty, +link: String, dsz: N.Size, +hd: Head) -> Step:
  match mk:
    case Mk{ns, phost, ents}:
      +path : String = String.join(parts, "/")
      Tar.put.new.named(Tar.assign(ns, String.join(Tar.init(parts), "/"), Tar.last(parts)), phost, path, ty, link, dsz, hd, ents)

def Tar.put.new(l: Lnk, +parts: List<&2, String>, +ty: Ty, dsz: N.Size, +hd: Head, +ns: Ns) -> Step:
  match l:
    case LBad{why}:
      SBad{why ++ ": " ++ Head.name(hd)}
    case LOk{link}:
      Tar.put.new.mk(Tar.mkdirs(Tar.init(parts), "", Mk{ns, "", Nil{}}), parts, ty, link, dsz, hd)

# A directory again: the last attributes win (the meta writer keeps the
# last entry of a host path).
def Tar.put.redir(ok: Bool, +path: String, host: String, +ty: Ty, dsz: N.Size, +hd: Head, ns: Ns) -> Step:
  match ok:
    case True{}:
      SPut{St{Pend.none(), 0, ns}, [Tar.ent(path, host, ty, Head.link(hd), hd)], dsz}
    case False{}:
      SBad{"tar: duplicate entry: " ++ Head.name(hd)}

def Tar.put.dup(m: Maybe<&2, Node>, +parts: List<&2, String>, +ty: Ty, dsz: N.Size, +hd: Head, +ns: Ns) -> Step:
  match m:
    case None{}:
      Tar.put.new(Tar.link(ty, Head.link(hd), ns), parts, ty, dsz, hd, ns)
    case Some{Node{h, oty}}:
      Tar.put.redir(Ty.is_dir(oty) && Ty.is_dir(ty), String.join(parts, "/"), h, ty, dsz, hd, ns)

def Tar.put.blocked(b: Bool, +parts: List<&2, String>, +ty: Ty, dsz: N.Size, +hd: Head, +ns: Ns) -> Step:
  match b:
    case True{}:
      SBad{"tar: entry under a non-directory or a symlink: " ++ Head.name(hd)}
    case False{}:
      Tar.put.dup(Ns.node(ns, String.join(parts, "/")), parts, ty, dsz, hd, ns)

# An entry (a plain one or a whiteout) at parts.
def Tar.put(+parts: List<&2, String>, +ty: Ty, dsz: N.Size, +hd: Head, st: St) -> Step:
  match st:
    case St{pend, want, +ns}:
      Tar.put.blocked(Tar.blocked(Tar.prefixes(Tar.init(parts), ""), ns), parts, ty, dsz, hd, ns)

def Tar.opq.mk(mk: Mk, +path: String, dsz: N.Size, +hd: Head) -> Step:
  match mk:
    case Mk{ns, host, ents}:
      SPut{St{Pend.none(), 0, ns}, List.append(&2, Ent, ents, [Tar.ent(path, host, TOpq{}, "", hd)]), dsz}

def Tar.opq.blocked(b: Bool, +parts: List<&2, String>, dsz: N.Size, +hd: Head, ns: Ns) -> Step:
  match b:
    case True{}:
      SBad{"tar: opaque marker under a non-directory or a symlink: " ++ Head.name(hd)}
    case False{}:
      Tar.opq.mk(Tar.mkdirs(parts, "", Mk{ns, "", Nil{}}), String.join(parts, "/"), dsz, hd)

# An opaque marker of the directory at parts ([] for the root).
def Tar.opq(+parts: List<&2, String>, dsz: N.Size, +hd: Head, st: St) -> Step:
  match st:
    case St{pend, want, +ns}:
      Tar.opq.blocked(Tar.blocked(Tar.prefixes(parts, ""), ns), parts, dsz, hd, ns)

def Tar.entry.mark(m: Mark, +ty: Ty, dsz: N.Size, +hd: Head, st: St) -> Step:
  match m:
    case MBad{why}:
      SBad{why}
    case MPlain{parts}:
      Tar.put(parts, ty, dsz, hd, st)
    case MWh{parts}:
      Tar.put(parts, TWh{}, dsz, hd, st)
    case MOpq{parts}:
      Tar.opq(parts, dsz, hd, st)

def Tar.entry.path(p: Path, +ty: Ty, +hd: Head, st: St) -> Step:
  match p:
    case PBad{why}:
      SBad{why}
    case PRoot{}:
      SSkip{St.clear(st), Tar.dsize(ty, Head.size(hd))}
    case POk{parts}:
      Tar.entry.mark(Tar.mark(parts), ty, Tar.dsize(ty, Head.size(hd)), hd, st)

def Tar.entry.ty(t: Maybe<&2, Ty>, +hd: Head, st: St) -> Step:
  match t:
    case None{}:
      SBad{"tar: unsupported entry type " ++ U32.show(Head.flag(hd)) ++ ": " ++ Head.name(hd)}
    case Some{ty}:
      Tar.entry.path(Tar.path(Head.name(hd)), ty, hd, st)

def Tar.entry(r: Result<&2, &2, String, Head>, st: St) -> Step:
  match r:
    case Fail{why}:
      SBad{why}
    case Done{+hd}:
      Tar.entry.ty(Tar.ty(Head.flag(hd), Head.name(hd)), hd, st)

# Headers and extended headers
# ----------------------------

# 1 MiB, Go's limit on the data of an extended header.
def Tar.ext.max() -> N.Size:
  N.Size{0, 1048576}

def Tar.head.ext(ok: Bool, st: St, flag: U32, size: N.Size) -> Step:
  match ok:
    case True{}:
      SMeta{St.want(st, flag), size}
    case False{}:
      SBad{"tar: extended header larger than 1 MiB"}

def Tar.head.kind(+h: Hdr, +st: St) -> Step:
  +f : U32 = Hdr.flag(h)
  Bool.pick(Step, U32.is_eq(f, 120) || U32.is_eq(f, 76) || U32.is_eq(f, 75),
    Tar.head.ext(Bool.not(N.Size.is_lt(Tar.ext.max(), Hdr.size(h))), st, f, Hdr.size(h)),
    Bool.pick(Step, U32.is_eq(f, 103), SSkip{st, Hdr.size(h)},
      Tar.entry(Tar.merge(h, St.pend(st)), st)))

def Tar.head.hdr(r: Result<&2, &2, String, Hdr>, st: St) -> Step:
  match r:
    case Fail{why}:
      SBad{why}
    case Done{h}:
      Tar.head.kind(h, st)

def Tar.head.zero(z: Bool, st: St, +blk: +List<U32>) -> Step:
  match z:
    case True{}:
      SEnd{}
    case False{}:
      Tar.head.hdr(Tar.hdr(blk), st)

# What a 512-byte header block means (a zero block ends the archive).
def Tar.head(st: St, +blk: +List<U32>) -> Step:
  Tar.head.zero(Tar.is_zero(blk), st, blk)

def Pend.pax(p: Pend, kvs: List<&2, Kv>) -> Pend:
  match p:
    case Pend{x, l, k}:
      Pend{kvs, l, k}

def Pend.long(p: Pend, n: String) -> Pend:
  match p:
    case Pend{x, l, k}:
      Pend{x, Some{n}, k}

def Pend.llink(p: Pend, n: String) -> Pend:
  match p:
    case Pend{x, l, k}:
      Pend{x, l, Some{n}}

def Tar.ext.pax(m: Maybe<&2, List<&2, Kv>>, p: Pend, ns: Ns) -> Step:
  match m:
    case None{}:
      SBad{"tar: invalid PAX header"}
    case Some{kvs}:
      SNext{St{Pend.pax(p, kvs), 0, ns}}

def Tar.ext.go(+want: U32, +p: Pend, +ns: Ns, +data: +List<U32>) -> Step:
  Bool.pick(Step, U32.is_eq(want, 120), Tar.ext.pax(Tar.pax(data), p, ns),
  Bool.pick(Step, U32.is_eq(want, 76), SNext{St{Pend.long(p, Tar.cstr(data)), 0, ns}},
  Bool.pick(Step, U32.is_eq(want, 75), SNext{St{Pend.llink(p, Tar.cstr(data)), 0, ns}},
    SBad{"tar: extended header data without its header"})))

# The data of the extended header SMeta asked for (its size bytes).
def Tar.ext(st: St, +data: +List<U32>) -> Step:
  match st:
    case St{p, w, ns}:
      Tar.ext.go(w, p, ns, data)

# A whole archive in memory
# -------------------------

def Tar.nat(s: N.Size) -> Nat:
  match s:
    case N.Size{h, l}:
      U32.to_nat(l)

# n rounded up to whole 512-byte blocks.
def Tar.blocks(+n: Nat) -> Nat:
  Nat.mul(Nat.div(Nat.add(n, 511n), 512n), 512n)

def Tar.run(fuel: Nat, step: Step, +bs: +List<U32>, acc: List<&2, Ent>) -> Result<&2, &2, String, List<&2, Ent>>:
  match fuel step:
    case 0n _:
      Fail{"tar: archive too long"}
    case 1n+f SNext{st}:
      Tar.run(f, Tar.head(st, List.take(&2, U32, bs, 512n)), List.drop(&2, U32, bs, 512n), acc)
    case 1n+f SMeta{st, size}:
      +n : Nat = Tar.nat(size)
      Tar.run(f, Tar.ext(st, List.take(&2, U32, bs, n)), List.drop(&2, U32, bs, Tar.blocks(n)), acc)
    case 1n+f SPut{st, es, size}:
      Tar.run(f, SNext{st}, List.drop(&2, U32, bs, Tar.blocks(Tar.nat(size))), List.append(&2, Ent, acc, es))
    case 1n+f SSkip{st, size}:
      Tar.run(f, SNext{st}, List.drop(&2, U32, bs, Tar.blocks(Tar.nat(size))), acc)
    case 1n+f SEnd{}:
      Done{acc}
    case 1n+f SBad{why}:
      Fail{why}

# The entries of an archive held in memory (the host's loop, for laws
# and tests; sizes below 4 GiB), or why the layer is refused.
def Tar.plan(+bs: +List<U32>) -> Result<&2, &2, String, List<&2, Ent>>:
  Tar.run(Nat.add(List.length(&2, U32, bs), 2n), SNext{Tar.start()}, bs, Nil{})
