import Base
import ../oci/size.bend as N
import ./tar.bend as T

# Sqfs
# ====
#
# One read-only squashfs 4.0 image per layer of the shared layer store
# (docs/ref/layers-sqfs.md): the layer's tar entries (src/layers/tar.bend
# Ent, tar order) become the image's tables; the host copies each regular
# file's data into the image and writes these bytes around it. Pure.
#
# Format: Linux v6.12 fs/squashfs/squashfs_fs.h and xattr.h. Everything
# is stored uncompressed: data blocks carry SQUASHFS_COMPRESSED_BIT_BLOCK
# (1 << 24), metadata blocks a header with SQUASHFS_COMPRESSED_BIT
# (1 << 15), and there are no fragments (each file's last block is a
# short data block). The layout, as squashfs-tools 4.7.5's sqfstar
# -noI -noD -noF -noX -no-fragments writes it:
#
#   0     super block (96 bytes)
#   96    each regular file's data, in tar order, block after block
#   E     inode table        (metadata blocks)
#         directory table    (metadata blocks)
#         id table           (metadata blocks, then their le64 starts)
#         xattr tables       (key/value blocks, id blocks, then the
#                             xattr id table header and le64 starts)
#   end   zero padding to a multiple of 4096
#
# Because every metadata block holds 8192 bytes (the last one fewer) and
# is stored with its 2-byte header, the block holding byte p of a table
# starts at (p / 8192) * 8194 in it: every inode reference and directory
# position is known before any byte is written.
#
# v1 limit: a layer whose image would pass 4 GiB is not stored (the node
# unpacks it itself), so every offset fits a U32.

# Constants (squashfs_fs.h)
# -------------------------

# s_magic: SQUASHFS_MAGIC 0x73717368 ("hsqs" little-endian).
def Sqfs.magic() -> U32:
  1936814952

# The data block size (128 KiB, SQUASHFS_FILE_SIZE) and its log.
def Sqfs.block() -> U32:
  131072

def Sqfs.block_log() -> U32:
  17

# SQUASHFS_METADATA_SIZE.
def Sqfs.meta() -> U32:
  8192

# A metadata block's header bit for "stored uncompressed".
def Sqfs.meta_raw() -> U32:
  32768

# A data block size's bit for "stored uncompressed".
def Sqfs.block_raw() -> U32:
  16777216

# SQUASHFS_INVALID_FRAG and the low half of SQUASHFS_INVALID_BLK.
def Sqfs.none() -> U32:
  4294967295

# ZLIB_COMPRESSION: an image must name a compressor; nothing is compressed.
def Sqfs.zlib() -> U32:
  1

# Inode types (SQUASHFS_*_TYPE).
def Sqfs.t_dir() -> U32:
  1

def Sqfs.t_reg() -> U32:
  2

def Sqfs.t_sym() -> U32:
  3

def Sqfs.t_blk() -> U32:
  4

def Sqfs.t_chr() -> U32:
  5

def Sqfs.t_fifo() -> U32:
  6

def Sqfs.t_sock() -> U32:
  7

# The extended type of a basic one (SQUASHFS_LDIR_TYPE = 8, ... 14).
def Sqfs.t_ext(t: U32) -> U32:
  (t + 7 : U32)

# Super block flags: NOI, NOD, NOF and NO_FRAG (bits 0, 1, 3, 4), and
# squashfs-tools' NOX (bit 8); NO_XATTR (bit 9) when there are none.
def Sqfs.flags(xattrs: Bool) -> U32:
  Bool.pick(U32, xattrs, 283, 795)

# xattr name prefixes (SQUASHFS_XATTR_USER, _TRUSTED, _SECURITY).
def Sqfs.x_user() -> U32:
  0

def Sqfs.x_trusted() -> U32:
  1

def Sqfs.x_security() -> U32:
  2

# Bytes
# -----

def Sqfs.b(x: U32, n: Nat) -> U32:
  U32.and(U32.shrn(x, n), 255)

def Sqfs.le16(+x: U32) -> +List<U32>:
  [Sqfs.b(x, 0n), Sqfs.b(x, 8n)]

def Sqfs.le32(+x: U32) -> +List<U32>:
  [Sqfs.b(x, 0n), Sqfs.b(x, 8n), Sqfs.b(x, 16n), Sqfs.b(x, 24n)]

def Sqfs.le64(hi: U32, lo: U32) -> +List<U32>:
  List.append(&2, U32, Sqfs.le32(lo), Sqfs.le32(hi))

# SQUASHFS_INVALID_BLK (-1 as le64).
def Sqfs.le64_none() -> +List<U32>:
  Sqfs.le64(Sqfs.none(), Sqfs.none())

def Sqfs.cat(xss: List<&2, +List<U32>>) -> +List<U32>:
  List.concat(&2, U32, xss)

def Sqfs.zeros(n: U32) -> +List<U32>:
  List.replicate(U32, U32.to_nat(n), 0)

# Metadata blocks
# ---------------

# Where the block holding byte p of a table starts, in the table.
def Sqfs.at_block(p: U32) -> U32:
  (U32.div(p, Sqfs.meta()) * 8194 : U32)

def Sqfs.at_offset(p: U32) -> U32:
  U32.mod(p, Sqfs.meta())

# A table's length once its n bytes are framed in metadata blocks.
def Sqfs.framed_len(+n: U32) -> U32:
  (n + (2 * U32.div((n + 8191 : U32), Sqfs.meta()) : U32) : U32)

# A reference to byte p of a table (an inode reference, a directory
# position): the block's start << 16 | the offset in the block, as le64
# halves.
def Sqfs.ref_hi(p: U32) -> U32:
  U32.shrn(Sqfs.at_block(p), 16n)

def Sqfs.ref_lo(+p: U32) -> U32:
  U32.or(U32.shln(Sqfs.at_block(p), 16n), Sqfs.at_offset(p))

def Sqfs.frame.head(+bs: +List<U32>) -> +List<U32>:
  Sqfs.le16(U32.or(Sqfs.meta_raw(), U32.from_nat(Nat.min(List.length(&2, U32, bs), 8192n))))

def Sqfs.frame.go(fuel: Nat, +bs: +List<U32>) -> List<&2, +List<U32>>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+f:
      match bs:
        case Nil{}:
          Nil{}
        case Con{h, t}:
          Con{List.append(&2, U32, Sqfs.frame.head(Con{h, t}), List.take(&2, U32, Con{h, t}, 8192n)),
            Sqfs.frame.go(f, List.drop(&2, U32, Con{h, t}, 8192n))}

# A table's bytes as uncompressed metadata blocks: each 8192 bytes (the
# last fewer) after a le16 header of its length | 0x8000.
def Sqfs.frame(+bs: +List<U32>) -> +List<U32>:
  Sqfs.cat(Sqfs.frame.go(Nat.add(Nat.div(List.length(&2, U32, bs), 8192n), 1n), bs))

# Nodes
# -----

# A tar entry and, for a regular file, where its data starts in the image.
type Put is Data:
  Put{ent: T.Ent, start: U32}

# An entry of the image: key (parent "\0" name, the sort order: a
# directory's children together, by name as strcmp orders them), its
# guest path, parent and name, its host path (hard links name it), and
# what its inode holds. rdev is Linux's new_encode_dev(major, minor).
type Nd is Data:
  Nd{key: String, path: String, parent: String, name: String, host: String, ty: T.Ty, mode: U32, uid: U32, gid: U32, rdev: U32, mtime: U32, xs: List<&2, T.Xattr>, link: String, size: U32, start: U32}

def Sqfs.rdev(+major: U32, +minor: U32) -> U32:
  U32.or(U32.or(U32.and(minor, 255), U32.shln(major, 8n)), U32.shln(U32.and(minor, 4294967040), 12n))

def Sqfs.split.go(rs: List<&2, String>) -> String & String:
  match rs:
    case Nil{}:
      ("", "")
    case Con{n, t}:
      (String.join(List.reverse(&2, String, t), "/"), n)

# A path's parent and name: "etc/hi" is ("etc", "hi"), "etc" is ("", "etc").
def Sqfs.split(path: String) -> String & String:
  Sqfs.split.go(List.reverse(&2, String, String.split(path, '/')))

def Sqfs.key(+parent: String, +name: String) -> String:
  parent ++ "\0" ++ name

def Sqfs.nd.at(pn: String & String, +path: String, +host: String, ty: T.Ty, mode: U32, uid: U32, gid: U32, rdev: U32, mtime: U32, xs: List<&2, T.Xattr>, link: String, size: U32, start: U32) -> Nd:
  match pn:
    case (+p, +n):
      Nd{Sqfs.key(p, n), path, p, n, host, ty, mode, uid, gid, rdev, mtime, xs, link, size, start}

def Sqfs.nd(p: Put) -> Nd:
  match p:
    case Put{T.Ent{+path, host, ty, mode, uid, gid, +major, +minor, mtime, ns, xs, link, N.Size{hi, lo}}, start}:
      Sqfs.nd.at(Sqfs.split(path), path, host, ty, mode, uid, gid, Sqfs.rdev(major, minor), mtime, xs, link, lo, start)

def Nd.key(n: Nd) -> String:
  match n:
    case Nd{k, p, pa, nm, h, t, m, u, g, r, mt, xs, l, s, st}:
      k

def Nd.le(a: Nd, b: Nd) -> Bool:
  String.is_le(Nd.key(a), Nd.key(b))

def Sqfs.sort(ns: List<&2, Nd>) -> List<&2, Nd>:
  List.sort(Nd, Nd.le, ns)

# Counts
# ------

def Sqfs.bump.go(r: Map<&2, U32> & U32, +key: String, by: U32) -> Map<&2, U32>:
  match r:
    case (m, v):
      Map.set(&2, U32, m, key, (v + by : U32))

def Sqfs.bump(m: Map<&2, U32>, +key: String, by: U32) -> Map<&2, U32>:
  Sqfs.bump.go(Map.get(U32, 0, m, key), key, by)

def Sqfs.look.go(r: Map<&2, U32> & U32) -> Map<&2, U32> & U32:
  r

def Sqfs.look(m: Map<&2, U32>, +key: String) -> Map<&2, U32> & U32:
  Map.get(U32, 0, m, key)

# The basic inode type of an entry (a whiteout is overlayfs's character
# device 0:0); 0 for a hard link (it shares its target's inode) and an
# opaque marker (an xattr on its directory).
def Sqfs.code(t: T.Ty) -> U32:
  match t:
    case T.TReg{}:
      2
    case T.TDir{}:
      1
    case T.TSym{}:
      3
    case T.TBlk{}:
      4
    case T.TChr{}:
      5
    case T.TWh{}:
      5
    case T.TFifo{}:
      6
    case _:
      0

# An xattr name's squashfs prefix type and the name after the prefix;
# 255 for a prefix squashfs cannot hold (the xattr is left out, as
# mksquashfs does).
def Sqfs.xtype(+name: String) -> U32:
  Bool.pick(U32, String.starts_with(name, "user."), 0,
    Bool.pick(U32, String.starts_with(name, "trusted."), 1,
      Bool.pick(U32, String.starts_with(name, "security."), 2, 255)))

def Sqfs.xname(+name: String) -> String:
  Bool.pick(String, String.starts_with(name, "user."), String.drop(name, 5n),
    Bool.pick(String, String.starts_with(name, "trusted."), String.drop(name, 8n),
      String.drop(name, 9n)))

def Sqfs.xkept.put(skip: Bool, x: T.Xattr, rest: List<&2, T.Xattr>) -> List<&2, T.Xattr>:
  match skip:
    case True{}:
      rest
    case False{}:
      Con{x, rest}

def Sqfs.xkept(xs: List<&2, T.Xattr>) -> List<&2, T.Xattr>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{T.Xattr{+n, v}, t}:
      Sqfs.xkept.put(U32.is_eq(Sqfs.xtype(n), 255), T.Xattr{n, v}, Sqfs.xkept(t))

# The xattrs an inode holds: the tar's (those squashfs can hold) and, for
# an opaque directory, trusted.overlay.opaque=y.
def Sqfs.xs.put(opaque: Bool, kept: List<&2, T.Xattr>) -> List<&2, T.Xattr>:
  match opaque:
    case True{}:
      List.append(&2, T.Xattr, kept, [T.Xattr{"trusted.overlay.opaque", "y"}])
    case False{}:
      kept

def Sqfs.xs(xs: List<&2, T.Xattr>, opaque: Bool) -> List<&2, T.Xattr>:
  Sqfs.xs.put(opaque, Sqfs.xkept(xs))

# The counts of one pass: hard links per target host path (hl), and per
# directory its subdirectories (sub), a bound on its listing's bytes
# (bnd: every entry with a header of its own) and whether it is opaque
# (opq).
type Cnt is Data:
  Cnt{hl: Map<&2, U32>, sub: Map<&2, U32>, bnd: Map<&2, U32>, opq: Map<&2, U32>}

def Sqfs.count.one(c: Cnt, +n: Nd) -> Cnt:
  match c:
    case Cnt{hl, sub, bnd, opq}:
      match n:
        case Nd{k, +path, +parent, +name, h, t, m, u, g, r, mt, xs, +link, s, st}:
          match t:
            case T.THard{}:
              Cnt{Sqfs.bump(hl, link, 1), sub, Sqfs.bump(bnd, parent, (20 + U32.from_nat(String.length(name)) : U32)), opq}
            case T.TDir{}:
              Cnt{hl, Sqfs.bump(sub, parent, 1), Sqfs.bump(bnd, parent, (20 + U32.from_nat(String.length(name)) : U32)), opq}
            case T.TOpq{}:
              Cnt{hl, sub, bnd, Sqfs.bump(opq, path, 1)}
            case _:
              Cnt{hl, sub, Sqfs.bump(bnd, parent, (20 + U32.from_nat(String.length(name)) : U32)), opq}

def Sqfs.count(ns: List<&2, Nd>, c: Cnt) -> Cnt:
  match ns:
    case Nil{}:
      c
    case Con{+n, t}:
      Sqfs.count(t, Sqfs.count.one(c, n))

# Inode sizes
# -----------

def Sqfs.blocks(+size: U32) -> U32:
  U32.div((size + 131071 : U32), Sqfs.block())

# Whether a directory needs the extended inode: xattrs, or a listing that
# may pass the basic inode's 16-bit size.
def Sqfs.dir_ext(x: Bool, bound: U32) -> Bool:
  Bool.or(x, U32.is_gt(bound, 65000))

# An inode's bytes, by basic type: x (it has xattrs), nlink (a regular
# file's links), big (a directory needs the extended inode), the symlink
# target's length, the file's size.
def Sqfs.isize(+code: U32, +x: Bool, +nlink: U32, +big: Bool, +llen: U32, +size: U32) -> U32:
  Bool.pick(U32, U32.is_eq(code, 1), Bool.pick(U32, big, 40, 32),
    Bool.pick(U32, U32.is_eq(code, 2), (Bool.pick(U32, Bool.or(x, U32.is_gt(nlink, 1)), 56, 32) + (4 * Sqfs.blocks(size) : U32) : U32),
      Bool.pick(U32, U32.is_eq(code, 3), (Bool.pick(U32, x, 28, 24) + llen : U32),
        Bool.pick(U32, U32.is_eq(code, 6), Bool.pick(U32, x, 24, 20),
          Bool.pick(U32, x, 28, 24)))))

# Inode numbers and positions
# ---------------------------

# The root directory: the tar's own entry for it, or 0755 root:root.
def Sqfs.root.default() -> Nd:
  Nd{"", "", "", "", "", T.TDir{}, 493, 0, 0, 0, 0, Nil{}, "", 0, 0}

def Nd.is_root(n: Nd) -> Bool:
  match n:
    case Nd{k, p, pa, nm, h, t, m, u, g, r, mt, xs, l, s, st}:
      String.is_empty(p)

def Nd.code(n: Nd) -> U32:
  match n:
    case Nd{k, p, pa, nm, h, t, m, u, g, r, mt, xs, l, s, st}:
      Sqfs.code(t)

def Nd.is_hard(n: Nd) -> Bool:
  match n:
    case Nd{k, p, pa, nm, h, t, m, u, g, r, mt, xs, l, s, st}:
      match t:
        case T.THard{}:
          True{}
        case _:
          False{}

def Nd.is_opq(n: Nd) -> Bool:
  match n:
    case Nd{k, p, pa, nm, h, t, m, u, g, r, mt, xs, l, s, st}:
      match t:
        case T.TOpq{}:
          True{}
        case _:
          False{}

def Sqfs.root.pick(rs: List<&2, Nd>) -> Nd:
  match rs:
    case Nil{}:
      Sqfs.root.default()
    case Con{r, t}:
      r

# The inodes, in table order: the root first, then every entry but hard
# links and opaque markers, in key order.
def Sqfs.inodes(+ns: List<&2, Nd>) -> List<&2, Nd>:
  Con{Sqfs.root.pick(List.filter(Nd, Nd.is_root, ns)),
    List.filter(Nd, n => Bool.and(Bool.not(Nd.is_root(n)), U32.is_gt(Nd.code(n), 0)), ns)}

# The entries of directory listings: all but the root and opaque markers.
def Sqfs.listed(+ns: List<&2, Nd>) -> List<&2, Nd>:
  List.filter(Nd, n => Bool.and(Bool.not(Nd.is_root(n)), Bool.not(Nd.is_opq(n))), ns)

def Sqfs.has_x(+no: U32, xs: List<&2, T.Xattr>) -> Bool:
  Bool.or(U32.is_gt(no, 0), Bool.not(List.is_empty(&2, T.Xattr, Sqfs.xkept(xs))))

# What the position pass learns of each inode, under "p" and its guest
# path and under "h" and its host path (hard links name their target's):
# its number, table position, basic type, whether it is the extended
# inode, whether it has xattrs, and its link count.
type Inf is Data:
  Inf{num: U32, pos: U32, code: U32, ext: Bool, x: Bool, nlink: U32, opq: Bool}

def Inf.none() -> Inf:
  Inf{0, 0, 0, False{}, False{}, 1, False{}}

def Sqfs.inf(m: Map<&2, Inf>, +key: String) -> Map<&2, Inf> & Inf:
  Map.get(Inf, Inf.none(), m, key)

type Ps is Data:
  Ps{cnt: Cnt, info: Map<&2, Inf>, num: U32, pos: U32}

# Whether an inode is the extended one: a directory with xattrs or a big
# listing, a regular file with xattrs or more than one link, any other
# with xattrs.
def Sqfs.ext(+code: U32, +x: Bool, +nh: U32, +bound: U32) -> Bool:
  Bool.pick(Bool, U32.is_eq(code, 1), Sqfs.dir_ext(x, bound),
    Bool.pick(Bool, U32.is_eq(code, 2), Bool.or(x, U32.is_gt(nh, 0)), x))

def Sqfs.nlink(+code: U32, +nh: U32, +ns: U32) -> U32:
  Bool.pick(U32, U32.is_eq(code, 1), (ns + 2 : U32), Bool.pick(U32, U32.is_eq(code, 2), (nh + 1 : U32), 1))

def Sqfs.pos.e(r: Map<&2, U32> & U32, hl: Map<&2, U32>, +nh: U32, bnd: Map<&2, U32>, +bound: U32, opq: Map<&2, U32>, +no: U32, info: Map<&2, Inf>, +num: U32, +pos: U32, +path: String, +host: String, +code: U32, xs: List<&2, T.Xattr>, +llen: U32, +size: U32) -> Ps:
  match r:
    case (sub, +ns):
      +x : Bool = Sqfs.has_x(no, xs)
      +ext : Bool = Sqfs.ext(code, x, nh, bound)
      +isz : U32 = Sqfs.isize(code, x, (nh + 1 : U32), Sqfs.dir_ext(x, bound), llen, size)
      +inf : Inf = Inf{num, pos, code, ext, x, Sqfs.nlink(code, nh, ns), U32.is_gt(no, 0)}
      Ps{Cnt{hl, sub, bnd, opq}, Map.set(&2, Inf, Map.set(&2, Inf, info, "p" ++ path, inf), "h" ++ host, inf),
        (num + 1 : U32), (pos + isz : U32)}

def Sqfs.pos.d(r: Map<&2, U32> & U32, sub: Map<&2, U32>, hl: Map<&2, U32>, +nh: U32, opq: Map<&2, U32>, +no: U32, info: Map<&2, Inf>, +num: U32, +pos: U32, +path: String, +host: String, +code: U32, xs: List<&2, T.Xattr>, +llen: U32, +size: U32) -> Ps:
  match r:
    case (bnd, +bound):
      Sqfs.pos.e(Sqfs.look(sub, path), hl, nh, bnd, bound, opq, no, info, num, pos, path, host, code, xs, llen, size)

def Sqfs.pos.c(r: Map<&2, U32> & U32, bnd: Map<&2, U32>, sub: Map<&2, U32>, hl: Map<&2, U32>, +nh: U32, info: Map<&2, Inf>, +num: U32, +pos: U32, +path: String, +host: String, +code: U32, xs: List<&2, T.Xattr>, +llen: U32, +size: U32) -> Ps:
  match r:
    case (opq, +no):
      Sqfs.pos.d(Sqfs.look(bnd, path), sub, hl, nh, opq, no, info, num, pos, path, host, code, xs, llen, size)

def Sqfs.pos.b(r: Map<&2, U32> & U32, opq: Map<&2, U32>, bnd: Map<&2, U32>, sub: Map<&2, U32>, info: Map<&2, Inf>, +num: U32, +pos: U32, +path: String, +host: String, +code: U32, xs: List<&2, T.Xattr>, +llen: U32, +size: U32) -> Ps:
  match r:
    case (hl, +nh):
      Sqfs.pos.c(Sqfs.look(opq, path), bnd, sub, hl, nh, info, num, pos, path, host, code, xs, llen, size)

def Sqfs.pos.one(s: Ps, +n: Nd) -> Ps:
  match s:
    case Ps{Cnt{hl, sub, bnd, opq}, info, +num, +pos}:
      match n:
        case Nd{k, +path, p, nm, +host, t, m, u, g, r, mt, xs, +link, +size, st}:
          Sqfs.pos.b(Sqfs.look(hl, host), opq, bnd, sub, info, num, pos, path, host, Sqfs.code(t), xs,
            U32.from_nat(String.length(link)), size)

def Sqfs.pos(ns: List<&2, Nd>, s: Ps) -> Ps:
  match ns:
    case Nil{}:
      s
    case Con{+n, t}:
      Sqfs.pos(t, Sqfs.pos.one(s, n))

# Directory listings
# ------------------

# One listing entry: the child's inode number, inode table position,
# basic type and name.
type Ch is Data:
  Ch{num: U32, pos: U32, code: U32, name: String}

# An inode number's distance from a header's base fits the entry's
# signed 16 bits.
def Sqfs.near(+d: U32) -> Bool:
  Bool.or(U32.is_le(d, 32767), U32.is_ge(d, 4294934528))

def Sqfs.dir.header(+count: U32, +blk: U32, +base: U32) -> +List<U32>:
  Sqfs.cat([Sqfs.le32((count - 1 : U32)), Sqfs.le32(blk), Sqfs.le32(base)])

def Sqfs.dir.entry(+c: Ch, +base: U32) -> +List<U32>:
  match c:
    case Ch{+num, +pos, +code, +name}:
      Sqfs.cat([Sqfs.le16(Sqfs.at_offset(pos)), Sqfs.le16(U32.and((num - base : U32), 65535)), Sqfs.le16(code),
        Sqfs.le16((U32.from_nat(String.length(name)) - 1 : U32)), T.Tar.b(name)])

# A run under one header: its block, base number, count and entries
# (reversed).
type Run is Data:
  Run{open: Bool, blk: U32, base: U32, count: U32, ents: List<&2, +List<U32>>}

def Sqfs.run.flush(r: Run) -> +List<U32>:
  match r:
    case Run{open, +blk, +base, +count, ents}:
      match open:
        case True{}:
          List.append(&2, U32, Sqfs.dir.header(count, blk, base), Sqfs.cat(List.reverse(&2, +List<U32>, ents)))
        case False{}:
          Nil{}

def Sqfs.run.fresh(r: Run) -> Bool:
  match r:
    case Run{open, b, n, c, e}:
      Bool.not(open)

def Sqfs.run.needs(+r: Run, +c: Ch) -> Bool:
  match r:
    case Run{open, +blk, +base, +count, ents}:
      match c:
        case Ch{+num, +pos, code, name}:
          Bool.or(Bool.not(open), Bool.or(U32.is_eq(count, 256),
            Bool.or(Bool.not(U32.is_eq(Sqfs.at_block(pos), blk)), Bool.not(Sqfs.near((num - base : U32))))))

def Sqfs.run.start(+c: Ch) -> Run:
  match c:
    case Ch{+num, +pos, code, name}:
      Run{True{}, Sqfs.at_block(pos), num, 0, Nil{}}

def Sqfs.run.add(r: Run, +c: Ch) -> Run:
  match r:
    case Run{open, blk, +base, +count, ents}:
      Run{open, blk, base, (count + 1 : U32), Con{Sqfs.dir.entry(c, base), ents}}

def Sqfs.run.step(split: Bool, +r: Run, +c: Ch, out: List<&2, +List<U32>>) -> Run & List<&2, +List<U32>>:
  match split:
    case True{}:
      (Sqfs.run.add(Sqfs.run.start(c), c), Con{Sqfs.run.flush(r), out})
    case False{}:
      (Sqfs.run.add(r, c), out)

def Sqfs.run.next(p: Run & List<&2, +List<U32>>, +c: Ch) -> Run & List<&2, +List<U32>>:
  match p:
    case (+r, out):
      Sqfs.run.step(Sqfs.run.needs(r, c), r, c, out)

def Sqfs.run.end(p: Run & List<&2, +List<U32>>) -> +List<U32>:
  match p:
    case (r, out):
      Sqfs.cat(List.reverse(&2, +List<U32>, Con{Sqfs.run.flush(r), out}))

# A directory's listing: its children in name order, under headers that
# split at 256 entries, at a new inode block, and where a number is too
# far from the header's base.
def Sqfs.run.go(cs: List<&2, Ch>, p: Run & List<&2, +List<U32>>) -> +List<U32>:
  match cs:
    case Nil{}:
      Sqfs.run.end(p)
    case Con{+c, t}:
      Sqfs.run.go(t, Sqfs.run.next(p, c))

def Sqfs.listing(cs: List<&2, Ch>) -> +List<U32>:
  Sqfs.run.go(cs, (Run{False{}, 0, 0, 0, Nil{}}, Nil{}))

# A directory's listing: its position in the directory table and size.
type Lst is Data:
  Lst{pos: U32, size: U32}

def Sqfs.lst(m: Map<&2, Lst>, +key: String) -> Map<&2, Lst> & Lst:
  Map.get(Lst, Lst{0, 0}, m, key)

def Sqfs.ch.of(r: Map<&2, Inf> & Inf, +name: String) -> Map<&2, Inf> & Ch:
  match r:
    case (m, Inf{num, pos, code, e, x, l, o}):
      (m, Ch{num, pos, code, name})

# A listing entry for node n: its own inode, or a hard link's target's.
def Sqfs.ch(m: Map<&2, Inf>, +n: Nd) -> Map<&2, Inf> & Ch:
  match n:
    case Nd{k, +path, p, +name, h, t, md, u, g, r, mt, xs, +link, s, st}:
      match t:
        case T.THard{}:
          Sqfs.ch.of(Sqfs.inf(m, "h" ++ link), name)
        case _:
          Sqfs.ch.of(Sqfs.inf(m, "p" ++ path), name)

# The listing pass: the current parent, its children so far (reversed),
# the directory table so far (reversed chunks) and its length, and each
# listed directory's Lst.
type Ls is Data:
  Ls{info: Map<&2, Inf>, cur: String, open: Bool, chs: List<&2, Ch>, out: List<&2, +List<U32>>, len: U32, lst: Map<&2, Lst>}

def Sqfs.ls.flush(s: Ls) -> Ls:
  match s:
    case Ls{info, +cur, open, chs, out, +len, lst}:
      match open:
        case True{}:
          +bs : +List<U32> = Sqfs.listing(List.reverse(&2, Ch, chs))
          +n : U32 = U32.from_nat(List.length(&2, U32, bs))
          Ls{info, cur, False{}, Nil{}, Con{bs, out}, (len + n : U32), Map.set(&2, Lst, lst, cur, Lst{len, n})}
        case False{}:
          Ls{info, cur, False{}, chs, out, len, lst}

def Sqfs.ls.same(+s: Ls, +parent: String) -> Bool:
  match s:
    case Ls{info, +cur, open, chs, out, len, lst}:
      Bool.and(open, String.eq(cur, parent))

def Sqfs.ls.begin.at(s: Ls, +parent: String) -> Ls:
  match s:
    case Ls{info, cur, open, chs, out, len, lst}:
      Ls{info, parent, True{}, Nil{}, out, len, lst}

def Sqfs.ls.begin(same: Bool, s: Ls, +parent: String) -> Ls:
  match same:
    case True{}:
      s
    case False{}:
      Sqfs.ls.begin.at(Sqfs.ls.flush(s), parent)

def Sqfs.ls.add.at(r: Map<&2, Inf> & Ch, cur: String, open: Bool, chs: List<&2, Ch>, out: List<&2, +List<U32>>, len: U32, lst: Map<&2, Lst>) -> Ls:
  match r:
    case (info, c):
      Ls{info, cur, open, Con{c, chs}, out, len, lst}

def Sqfs.ls.add(s: Ls, +n: Nd) -> Ls:
  match s:
    case Ls{info, cur, open, chs, out, len, lst}:
      Sqfs.ls.add.at(Sqfs.ch(info, n), cur, open, chs, out, len, lst)

def Nd.parent(n: Nd) -> String:
  match n:
    case Nd{k, p, pa, nm, h, t, m, u, g, r, mt, xs, l, s, st}:
      pa

def Sqfs.ls.one(+s: Ls, +n: Nd) -> Ls:
  Sqfs.ls.add(Sqfs.ls.begin(Sqfs.ls.same(s, Nd.parent(n)), s, Nd.parent(n)), n)

def Sqfs.ls(ns: List<&2, Nd>, +s: Ls) -> Ls:
  match ns:
    case Nil{}:
      Sqfs.ls.flush(s)
    case Con{+n, t}:
      Sqfs.ls(t, Sqfs.ls.one(s, n))

# Inode bytes
# -----------

# The id table: each uid or gid once, in first-use order; m maps its
# decimal to its index + 1.
type Ids is Data:
  Ids{m: Map<&2, U32>, list: List<&2, U32>, n: U32}

def Sqfs.id.got(isnew: Bool, m: Map<&2, U32>, list: List<&2, U32>, +n: U32, +v: U32, +i: U32) -> Ids & U32:
  match isnew:
    case True{}:
      (Ids{Map.set(&2, U32, m, U32.show(v), (n + 1 : U32)), Con{v, list}, (n + 1 : U32)}, n)
    case False{}:
      (Ids{m, list, n}, (i - 1 : U32))

def Sqfs.id.at(r: Map<&2, U32> & U32, list: List<&2, U32>, +n: U32, +v: U32) -> Ids & U32:
  match r:
    case (m, +i):
      Sqfs.id.got(U32.is_eq(i, 0), m, list, n, v, i)

# The index of id v, added at the end when new.
def Sqfs.id(s: Ids, +v: U32) -> Ids & U32:
  match s:
    case Ids{m, list, +n}:
      Sqfs.id.at(Map.get(U32, 0, m, U32.show(v)), list, n, v)

# The xattr tables so far: the key/value bytes (reversed chunks) and
# their length, the xattr id entries (reversed) and their count.
type Xa is Data:
  Xa{kv: List<&2, +List<U32>>, kvlen: U32, ents: List<&2, +List<U32>>, n: U32}

# One xattr as squashfs_xattr_entry and squashfs_xattr_val.
def Sqfs.xa.one(+x: T.Xattr) -> +List<U32>:
  match x:
    case T.Xattr{+name, +value}:
      Sqfs.cat([Sqfs.le16(Sqfs.xtype(name)), Sqfs.le16(U32.from_nat(String.length(Sqfs.xname(name)))), T.Tar.b(Sqfs.xname(name)),
        Sqfs.le32(U32.from_nat(String.length(value))), T.Tar.b(value)])

def Sqfs.xa.kv(xs: List<&2, T.Xattr>) -> +List<U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, t}:
      List.append(&2, U32, Sqfs.xa.one(x), Sqfs.xa.kv(t))

# An inode's xattrs added: its xattr id, and a squashfs_xattr_id entry
# (where its key/values start, how many, their bytes).
def Sqfs.xa.add(s: Xa, +xs: List<&2, T.Xattr>) -> Xa & U32:
  match s:
    case Xa{kv, +kvlen, ents, +n}:
      +bs : +List<U32> = Sqfs.xa.kv(xs)
      +sz : U32 = U32.from_nat(List.length(&2, U32, bs))
      +ent : +List<U32> = Sqfs.cat([Sqfs.le64(Sqfs.ref_hi(kvlen), Sqfs.ref_lo(kvlen)),
        Sqfs.le32(U32.from_nat(List.length(&2, T.Xattr, xs))), Sqfs.le32(sz)])
      (Xa{Con{bs, kv}, (kvlen + sz : U32), Con{ent, ents}, (n + 1 : U32)}, n)

def Sqfs.xa.maybe(has: Bool, s: Xa, +xs: List<&2, T.Xattr>) -> Xa & U32:
  match has:
    case True{}:
      Sqfs.xa.add(s, xs)
    case False{}:
      (s, Sqfs.none())

# A regular file's block list: each block's size (the last one short)
# with the uncompressed bit.
def Sqfs.blist(fuel: Nat, +left: U32) -> +List<U32>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+f:
      List.append(&2, U32, Sqfs.le32(U32.or(U32.min(left, Sqfs.block()), Sqfs.block_raw())),
        Sqfs.blist(f, (left - U32.min(left, Sqfs.block()) : U32)))

def Sqfs.blocks_of(+size: U32) -> +List<U32>:
  Sqfs.blist(U32.to_nat(Sqfs.blocks(size)), size)

# squashfs_base_inode.
def Sqfs.base(+code: U32, +mode: U32, +uid: U32, +gid: U32, +mtime: U32, +num: U32) -> +List<U32>:
  Sqfs.cat([Sqfs.le16(code), Sqfs.le16(U32.and(mode, 4095)), Sqfs.le16(uid), Sqfs.le16(gid), Sqfs.le32(mtime), Sqfs.le32(num)])

# What one inode's bytes need beyond its base.
type Ib is Data:
  Ib{code: U32, ext: Bool, xid: U32, nlink: U32, lpos: U32, lsize: U32, parent: U32, start: U32, size: U32, link: String, rdev: U32}

def Sqfs.ib.dir(+b: Ib) -> +List<U32>:
  match b:
    case Ib{c, +ext, +xid, +nlink, +lpos, +lsize, +parent, s, sz, l, r}:
      match ext:
        case False{}:
          Sqfs.cat([Sqfs.le32(Sqfs.at_block(lpos)), Sqfs.le32(nlink), Sqfs.le16((lsize + 3 : U32)), Sqfs.le16(Sqfs.at_offset(lpos)), Sqfs.le32(parent)])
        case True{}:
          Sqfs.cat([Sqfs.le32(nlink), Sqfs.le32((lsize + 3 : U32)), Sqfs.le32(Sqfs.at_block(lpos)), Sqfs.le32(parent),
            Sqfs.le16(0), Sqfs.le16(Sqfs.at_offset(lpos)), Sqfs.le32(xid)])

def Sqfs.ib.reg(+b: Ib) -> +List<U32>:
  match b:
    case Ib{c, +ext, +xid, +nlink, lp, ls, pa, +start, +size, l, r}:
      match ext:
        case False{}:
          Sqfs.cat([Sqfs.le32(start), Sqfs.le32(Sqfs.none()), Sqfs.le32(0), Sqfs.le32(size), Sqfs.blocks_of(size)])
        case True{}:
          Sqfs.cat([Sqfs.le64(0, start), Sqfs.le64(0, size), Sqfs.le64(0, 0), Sqfs.le32(nlink), Sqfs.le32(Sqfs.none()),
            Sqfs.le32(0), Sqfs.le32(xid), Sqfs.blocks_of(size)])

def Sqfs.ib.xid(ext: Bool, +xid: U32) -> +List<U32>:
  match ext:
    case True{}:
      Sqfs.le32(xid)
    case False{}:
      Nil{}

def Sqfs.ib.sym(+b: Ib) -> +List<U32>:
  match b:
    case Ib{c, +ext, +xid, +nlink, lp, ls, pa, st, sz, +link, r}:
      Sqfs.cat([Sqfs.le32(nlink), Sqfs.le32(U32.from_nat(String.length(link))), T.Tar.b(link), Sqfs.ib.xid(ext, xid)])

def Sqfs.ib.dev(+b: Ib) -> +List<U32>:
  match b:
    case Ib{c, +ext, +xid, +nlink, lp, ls, pa, st, sz, l, +rdev}:
      Sqfs.cat([Sqfs.le32(nlink), Sqfs.le32(rdev), Sqfs.ib.xid(ext, xid)])

def Sqfs.ib.ipc(+b: Ib) -> +List<U32>:
  match b:
    case Ib{c, +ext, +xid, +nlink, lp, ls, pa, st, sz, l, r}:
      Sqfs.cat([Sqfs.le32(nlink), Sqfs.ib.xid(ext, xid)])

def Sqfs.ib.code(+b: Ib) -> U32:
  match b:
    case Ib{+code, +ext, x, n, lp, ls, pa, st, sz, l, r}:
      Bool.pick(U32, ext, Sqfs.t_ext(code), code)

# The type-specific part of an inode.
def Sqfs.ib.tail(+b: Ib) -> +List<U32>:
  match b:
    case Ib{+code, e, x, n, lp, ls, pa, st, sz, l, r}:
      Bool.pick(+List<U32>, U32.is_eq(code, 1), Sqfs.ib.dir(b),
        Bool.pick(+List<U32>, U32.is_eq(code, 2), Sqfs.ib.reg(b),
          Bool.pick(+List<U32>, U32.is_eq(code, 3), Sqfs.ib.sym(b),
            Bool.pick(+List<U32>, U32.is_eq(code, 6), Sqfs.ib.ipc(b), Sqfs.ib.dev(b)))))

# The inode pass: what it looks up, the id and xattr tables, the inode
# table so far (reversed chunks), and the number of inodes.
type Es is Data:
  Es{info: Map<&2, Inf>, lst: Map<&2, Lst>, ids: Ids, xa: Xa, out: List<&2, +List<U32>>, total: U32}

def Sqfs.e.g(r: Xa & U32, info: Map<&2, Inf>, lst: Map<&2, Lst>, ids: Ids, out: List<&2, +List<U32>>, +total: U32, +bs0: Ib, +mode: U32, +uidx: U32, +gidx: U32, +mtime: U32, +num: U32) -> Es:
  match r:
    case (xa, +xid):
      match bs0:
        case Ib{+c, +e, x, +nl, +lp, +ls, +pa, +st, +sz, +l, +rd}:
          +b : Ib = Ib{c, e, xid, nl, lp, ls, pa, st, sz, l, rd}
          Es{info, lst, ids, xa, Con{List.append(&2, U32, Sqfs.base(Sqfs.ib.code(b), mode, uidx, gidx, mtime, num), Sqfs.ib.tail(b)), out}, total}

def Sqfs.e.f(r: Ids & U32, info: Map<&2, Inf>, lst: Map<&2, Lst>, xa: Xa, out: List<&2, +List<U32>>, +total: U32, +b: Ib, +x: Bool, +xs: List<&2, T.Xattr>, +mode: U32, +uidx: U32, +mtime: U32, +num: U32) -> Es:
  match r:
    case (ids, +gidx):
      Sqfs.e.g(Sqfs.xa.maybe(x, xa, xs), info, lst, ids, out, total, b, mode, uidx, gidx, mtime, num)

def Sqfs.e.e(r: Ids & U32, info: Map<&2, Inf>, lst: Map<&2, Lst>, xa: Xa, out: List<&2, +List<U32>>, +total: U32, +b: Ib, +x: Bool, +xs: List<&2, T.Xattr>, +mode: U32, +gid: U32, +mtime: U32, +num: U32) -> Es:
  match r:
    case (ids, +uidx):
      Sqfs.e.f(Sqfs.id(ids, gid), info, lst, xa, out, total, b, x, xs, mode, uidx, mtime, num)

def Sqfs.e.d(r: Map<&2, Lst> & Lst, info: Map<&2, Inf>, ids: Ids, xa: Xa, out: List<&2, +List<U32>>, +total: U32, +inf: Inf, +pnum: U32, +n: Nd) -> Es:
  match r:
    case (lst, Lst{+lpos, +lsize}):
      match inf:
        case Inf{+num, ip, +code, +ext, +x, +nlink, +opq}:
          match n:
            case Nd{k, p, pa, nm, h, t, +mode, +uid, +gid, +rdev, +mtime, xs, +link, +size, +start}:
              +b : Ib = Ib{code, ext, Sqfs.none(), nlink, lpos, lsize, pnum, start, size, link, rdev}
              Sqfs.e.e(Sqfs.id(ids, uid), info, lst, xa, out, total, b, x, Sqfs.xs(xs, opq), mode, gid, mtime, num)

def Sqfs.e.c(r: Map<&2, Inf> & Inf, lst: Map<&2, Lst>, ids: Ids, xa: Xa, out: List<&2, +List<U32>>, +total: U32, +inf: Inf, +n: Nd, +path: String) -> Es:
  match r:
    case (info, Inf{+pn, a, b, c, d, e, f}):
      Sqfs.e.d(Sqfs.lst(lst, path), info, ids, xa, out, total, inf,
        Bool.pick(U32, String.is_empty(path), (total + 1 : U32), pn), n)

def Sqfs.e.b(r: Map<&2, Inf> & Inf, lst: Map<&2, Lst>, ids: Ids, xa: Xa, out: List<&2, +List<U32>>, +total: U32, +n: Nd, +path: String, +parent: String) -> Es:
  match r:
    case (info, +inf):
      Sqfs.e.c(Sqfs.inf(info, "p" ++ parent), lst, ids, xa, out, total, inf, n, path)

def Sqfs.e.one(s: Es, +n: Nd) -> Es:
  match s:
    case Es{info, lst, ids, xa, out, +total}:
      match n:
        case Nd{k, +path, +parent, nm, h, t, m, u, g, r, mt, xs, l, sz, st}:
          Sqfs.e.b(Sqfs.inf(info, "p" ++ path), lst, ids, xa, out, total, n, path, parent)

def Sqfs.e(ns: List<&2, Nd>, s: Es) -> Es:
  match ns:
    case Nil{}:
      s
    case Con{+n, t}:
      Sqfs.e(t, Sqfs.e.one(s, n))

# The image
# ---------

# What the host writes around the data: the tables after the data (tail,
# from offset E, zero-padded to a multiple of 4096) and the super block
# (96 bytes at offset 0); end is bytes_used.
type Img is Data:
  Img{tail: +List<U32>, sb: +List<U32>, end: U32}

# The le64 starts of n metadata blocks from at (an id or xattr index).
def Sqfs.index(fuel: Nat, +at: U32) -> +List<U32>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+f:
      List.append(&2, U32, Sqfs.le64(0, at), Sqfs.index(f, (at + 8194 : U32)))

def Sqfs.nblocks(+bytes: U32) -> Nat:
  U32.to_nat(U32.div((bytes + 8191 : U32), Sqfs.meta()))

def Sqfs.len(+bs: +List<U32>) -> U32:
  U32.from_nat(List.length(&2, U32, bs))

def Sqfs.ids.bytes(xs: List<&2, U32>) -> +List<U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      List.append(&2, U32, Sqfs.le32(x), Sqfs.ids.bytes(t))

# The xattr tables at at: the key/values, the ids, then the
# squashfs_xattr_id_table header and the ids' block starts; and where
# that header starts.
def Sqfs.xtables(+kv: +List<U32>, +ents: +List<U32>, +n: U32, +at: U32) -> +List<U32> & U32:
  +kvf : +List<U32> = Sqfs.frame(kv)
  +entf : +List<U32> = Sqfs.frame(ents)
  +x2 : U32 = (at + Sqfs.len(kvf) : U32)
  +hdr : U32 = (x2 + Sqfs.len(entf) : U32)
  (Sqfs.cat([kvf, entf, Sqfs.le64(0, at), Sqfs.le32(n), Sqfs.le32(0), Sqfs.index(Sqfs.nblocks(Sqfs.len(ents)), x2)]), hdr)

def Sqfs.img.end(has: Bool, +xbytes: +List<U32>, +after: U32) -> U32:
  match has:
    case True{}:
      (after + Sqfs.len(xbytes) : U32)
    case False{}:
      after

def Sqfs.img.fin(+has: Bool, xt: +List<U32> & U32, +e0: U32, +total: U32, +nids: U32, +dstart: U32, +fstart: U32, +idstart: U32, +after: U32, +head: +List<U32>) -> Img:
  match xt:
    case (+xbytes, +xstart):
      +end : U32 = Sqfs.img.end(has, xbytes, after)
      +pad : U32 = U32.mod((4096 - U32.mod(end, 4096) : U32), 4096)
      +sb : +List<U32> = Sqfs.cat([Sqfs.le32(Sqfs.magic()), Sqfs.le32(total), Sqfs.le32(0), Sqfs.le32(Sqfs.block()), Sqfs.le32(0),
        Sqfs.le16(Sqfs.zlib()), Sqfs.le16(Sqfs.block_log()), Sqfs.le16(Sqfs.flags(has)), Sqfs.le16(nids), Sqfs.le16(4), Sqfs.le16(0),
        Sqfs.le64(0, 0), Sqfs.le64(0, end), Sqfs.le64(0, idstart),
        Bool.pick(+List<U32>, has, Sqfs.le64(0, xstart), Sqfs.le64_none()),
        Sqfs.le64(0, e0), Sqfs.le64(0, dstart), Sqfs.le64(0, fstart), Sqfs.le64_none()])
      Img{Sqfs.cat([head, Bool.pick(+List<U32>, has, xbytes, Nil{}), Sqfs.zeros(pad)]), sb, end}

def Sqfs.img.at(+e0: U32, +total: U32, +inodes: +List<U32>, +dirs: +List<U32>, +ids: +List<U32>, +nids: U32, x: Xa) -> Img:
  match x:
    case Xa{kv, kl, ents, +xn}:
      +it : +List<U32> = Sqfs.frame(inodes)
      +dt : +List<U32> = Sqfs.frame(dirs)
      +idt : +List<U32> = Sqfs.frame(ids)
      +dstart : U32 = (e0 + Sqfs.len(it) : U32)
      +fstart : U32 = (dstart + Sqfs.len(dt) : U32)
      +idstart : U32 = (fstart + Sqfs.len(idt) : U32)
      +idx : +List<U32> = Sqfs.index(Sqfs.nblocks(Sqfs.len(ids)), fstart)
      +after : U32 = (idstart + Sqfs.len(idx) : U32)
      +has : Bool = U32.is_gt(xn, 0)
      xt : +List<U32> & U32 = Sqfs.xtables(Sqfs.cat(List.reverse(&2, +List<U32>, kv)), Sqfs.cat(List.reverse(&2, +List<U32>, ents)), xn, after)
      Sqfs.img.fin(has, xt, e0, total, nids, dstart, fstart, idstart, after, Sqfs.cat([it, dt, idt, idx]))

def Sqfs.image.es(s: Es, +dirs: +List<U32>, +total: U32, +e0: U32) -> Img:
  match s:
    case Es{info, lst, Ids{m, list, +nids}, xa, out, t}:
      Sqfs.img.at(e0, total, Sqfs.cat(List.reverse(&2, +List<U32>, out)), dirs, Sqfs.ids.bytes(List.reverse(&2, U32, list)), nids, xa)

def Sqfs.image.ls(s: Ls, +ino: List<&2, Nd>, +total: U32, +e0: U32) -> Img:
  match s:
    case Ls{info, c, o, chs, out, l, lst}:
      Sqfs.image.es(Sqfs.e(ino, Es{info, lst, Ids{Map.new(&2, U32), Nil{}, 0}, Xa{Nil{}, 0, Nil{}, 0}, Nil{}, total}),
        Sqfs.cat(List.reverse(&2, +List<U32>, out)), total, e0)

def Sqfs.image.ps(s: Ps, +ns: List<&2, Nd>, +ino: List<&2, Nd>, +e0: U32) -> Img:
  match s:
    case Ps{cnt, info, +num, pos}:
      Sqfs.image.ls(Sqfs.ls(Sqfs.listed(ns), Ls{info, "", False{}, Nil{}, Nil{}, 0, Map.new(&2, Lst)}), ino, (num - 1 : U32), e0)
def Sqfs.nds(ps: List<&2, Put>) -> List<&2, Nd>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{p, t}:
      Con{Sqfs.nd(p), Sqfs.nds(t)}

# The image of a layer: its entries (each regular file with where the host
# put its data), the data ending at e0.
def Sqfs.image(puts: List<&2, Put>, +e0: U32) -> Img:
  +ns : List<&2, Nd> = Sqfs.sort(Sqfs.nds(puts))
  +cnt : Cnt = Sqfs.count(ns, Cnt{Map.new(&2, U32), Map.new(&2, U32), Map.new(&2, U32), Map.new(&2, U32)})
  +ino : List<&2, Nd> = Sqfs.inodes(ns)
  Sqfs.image.ps(Sqfs.pos(ino, Ps{cnt, Map.new(&2, Inf), 1, 0}), ns, ino, e0)
