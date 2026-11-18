import Base
import ../oci/size.bend as N
import ../oci/grammar.bend as G
import ./tar.bend as T
import ./meta.bend as M
import ./store.bend as Y

# Filling the shared layer store (src/layers/store.bend) with one layer:
# the host's unpack loop over a decompressed layer tar on disk, the
# files it creates, the layer's record, and what `vk8s layers gc`
# removes. Pure: the host (host/layers/fill.bend) reads byte ranges and
# runs host/layers/fs.bend's effects; these defs say which.
#
# The unpack loop (Tar.head and Tar.ext over the tar's 512-byte blocks,
# src/layers/tar.bend, with 64-bit offsets so a tar past 4 GiB unpacks):
#   a = AHead{Tar.start(), 0}
#   AHead{st, at}         read up to 512 bytes at `at`; a = Fill.head(...)
#   AExt{st, at, n, next} read n bytes at `at`; a = Fill.ext(...)
#   AMake{st, es, ops, next}  run ops in order (es are Tar's entries, for
#                         the .bend-meta files); a = AHead{st, next}
#   ADone{}               the archive ended
#   ABad{why}             refuse the layer
# Fill.plan runs the same loop over a tar held in memory (laws, tests).
#
# As Go's archive/tar reads (reader.go readHeader: io.ReadFull of a
# block), no byte at a header's place ends the archive, and a part of a
# block refuses it ("unexpected EOF"), as does an extended header's data
# that the file does not hold. A regular file's data is its header's
# next byte on, and every entry takes whole 512-byte blocks (POSIX
# ustar).
#
# What each entry becomes on the host, under the layer's tmp directory
# at its host path (Ent.host): a regular file, its data range copied out
# of the tar (OCopy); a directory (OMkdir); a symbolic link to its target
# as written (OSymlink); a hard link to its target's host path (OLink);
# a device, a FIFO or a whiteout, an empty regular file (OEmpty: the
# guest sees its type, mode and device numbers in .bend-meta, bend-vmm's
# meta share); an opaque marker, nothing (ONone: .bend-meta marks the
# directory). Then each directory's .bend-meta (Meta.sides) is written
# (OWrite), every directory is fsynced, deepest first (Fill.syncs), and
# the directory is renamed into place (Lay.publish).
#
# The record: <root>/layer-refs/<hex> holds what the store keeps of a
# layer (src/layers/store.bend Layer), outside <root>/layers, which the
# nodes see:
#   layer-meta 1
#   chain <chain ID>
#   diff <diffID>
#   parent <parent chain ID, empty for the first layer>
#   last-use <unix seconds>
#   holder <holder>        one line per holder, in order
# A fill writes it before the rename that publishes the layer, and again
# on every later fill of the same layer (a use).
#
# Version 2 (Fill.rec.render.v2, Fill.rec.parse.v2) adds, after
# last-use, what the fill unpacked (Fill.use.of):
#   size <bytes>           the regular files' bytes
#   inodes <n>             the layer's inodes, its directory too
# A record of version 1 still parses (its size unknown: Rec{l, None}),
# and a use keeps the version it had (Fill.rec.use, Fill.rec.render.of).
# The fill also publishes the record as it wrote it at publish to
# <root>/layers/<hex>.rec (Fill.rec.share), before the rename: the nodes
# see <root>/layers only, and a node's snapshotter answers Usage of the
# layer from it (/mnt/layers/<hex>.rec, Fill.rec.mount) instead of
# walking the layer over the share. gc removes it with the layer. A fill finds a layer
# only when its record and its directory are both there (Fill.present).
# gc treats a layer whose record is missing or unreadable as unheld and
# unused since 1970, so it removes it, unless a node's layers.held names
# it (Fill.hold, below). fill and gc never run at once (the lock, below).
#
# Limits (Fill.unz.mib, Fill.max_ents): the decompressed tar is at most
# 50 times the compressed layer and at most 64 GiB, and a layer has at
# most 2,000,000 entries; past either the fill fails and its tmp entries
# go.
#
# tmp: <root>/tmp/<hex>.<nonce> is a layer being unpacked, with
# <hex>.<nonce>.tar its decompressed tar and <hex>.<nonce>.rec its
# record before the rename; the nonce is the wall clock's seconds when
# the fill made it (the next free number, if a fill of the same layer
# took it). gc removes an entry of a tmp directory whose name is one of
# these once the time in its name is a day old (a fill in progress is
# never that old; a crashed one leaves only these).

# Offsets
# -------

def Fill.blocks.go(s: N.Size) -> N.Size:
  match s:
    case N.Size{h, l}:
      N.Size{h, U32.and(l, 4294966784)}

# n rounded up to whole 512-byte blocks.
def Fill.blocks(n: N.Size) -> N.Size:
  Fill.blocks.go(N.Size.add(n, N.Size{0, 511}))

# The offset after n bytes at `at`, rounded up to a block.
def Fill.after(at: N.Size, n: N.Size) -> N.Size:
  N.Size.add(at, Fill.blocks(n))

def Fill.lo(s: N.Size) -> U32:
  match s:
    case N.Size{h, l}:
      l

# How many bytes, as a U32.
def Fill.count(bs: +List<U32>, +n: U32) -> U32:
  match bs:
    case Nil{}:
      n
    case Con{c, t}:
      Fill.count(t, (n + 1 : U32))

# Operations
# ----------

# One thing the host does to the layer's tmp directory. Paths are full
# host paths; a symlink's target is its bytes, one Char each.
type Op is Data:
  ONone{}
  OMkdir{path: String}
  OEmpty{path: String}
  OSymlink{path: String, target: String}
  OLink{path: String, target: String}
  OCopy{path: String, at: N.Size, size: N.Size}
  OWrite{path: String, text: String}

def Fill.op.ty(t: T.Ty, +path: String, link: String, +dir: String, at: N.Size, size: N.Size) -> Op:
  match t:
    case T.TReg{}:
      OCopy{path, at, size}
    case T.TDir{}:
      OMkdir{path}
    case T.TSym{}:
      OSymlink{path, link}
    case T.THard{}:
      OLink{path, dir ++ "/" ++ link}
    case T.TOpq{}:
      ONone{}
    case _:
      OEmpty{path}

# What entry e becomes under dir; a regular file's data starts at `at`.
def Fill.op(+dir: String, at: N.Size, e: T.Ent) -> Op:
  match e:
    case T.Ent{p, h, t, m, u, g, ma, mi, mt, ns, xs, l, sz}:
      Fill.op.ty(t, dir ++ "/" ++ h, l, dir, at, sz)

def Fill.ops(es: List<&2, T.Ent>, +dir: String, +at: N.Size) -> List<&2, Op>:
  match es:
    case Nil{}:
      Nil{}
    case Con{e, t}:
      Con{Fill.op(dir, at, e), Fill.ops(t, dir, at)}

# The loop
# --------

# What the host does next (see the top).
type Act is Data:
  AHead{st: T.St, at: N.Size}
  AExt{st: T.St, at: N.Size, n: U32, next: N.Size}
  AMake{st: T.St, ents: List<&2, T.Ent>, ops: List<&2, Op>, next: N.Size}
  ADone{}
  ABad{why: String}

# What Tar's step means at `at`, the offset after the block or the data
# that gave it, for a layer unpacked at dir.
def Fill.act(step: T.Step, +at: N.Size, +dir: String) -> Act:
  match step:
    case T.SNext{st}:
      AHead{st, at}
    case T.SMeta{st, +size}:
      AExt{st, at, Fill.lo(size), Fill.after(at, size)}
    case T.SPut{st, +es, +size}:
      AMake{st, es, Fill.ops(es, dir, at), Fill.after(at, size)}
    case T.SSkip{st, size}:
      AHead{st, Fill.after(at, size)}
    case T.SEnd{}:
      ADone{}
    case T.SBad{why}:
      ABad{why}

def Fill.head.go(full: Bool, st: T.St, +at: N.Size, +bs: +List<U32>, +dir: String) -> Act:
  match full:
    case True{}:
      Fill.act(T.Tar.head(st, bs), N.Size.add(at, N.Size{0, 512}), dir)
    case False{}:
      Bool.pick(Act, List.is_empty(&2, U32, bs), ADone{}, ABad{"tar: unexpected end of archive"})

# What a header read at `at` gave: bs, up to 512 bytes.
def Fill.head(st: T.St, +at: N.Size, +bs: +List<U32>, +dir: String) -> Act:
  Fill.head.go(U32.is_eq(Fill.count(bs, 0), 512), st, at, bs, dir)

def Fill.ext.go(full: Bool, st: T.St, +next: N.Size, +bs: +List<U32>, +dir: String) -> Act:
  match full:
    case True{}:
      Fill.act(T.Tar.ext(st, bs), next, dir)
    case False{}:
      ABad{"tar: unexpected end of archive"}

# What an extended header's data read for AExt{st, at, n, next} gave.
def Fill.ext(st: T.St, +n: U32, +next: N.Size, +bs: +List<U32>, +dir: String) -> Act:
  Fill.ext.go(U32.is_eq(Fill.count(bs, 0), n), st, next, bs, dir)

# The loop's first step.
def Fill.start() -> Act:
  AHead{T.Tar.start(), N.Size.zero()}

def Fill.show.op(o: Op) -> String:
  match o:
    case ONone{}:
      "none"
    case OMkdir{p}:
      "mkdir " ++ p
    case OEmpty{p}:
      "empty " ++ p
    case OSymlink{p, t}:
      "symlink " ++ p ++ " " ++ t
    case OLink{p, t}:
      "link " ++ p ++ " " ++ t
    case OCopy{p, a, s}:
      "copy " ++ p ++ " " ++ N.Size.show(a) ++ " " ++ N.Size.show(s)
    case OWrite{p, t}:
      "write " ++ p

def Fill.show.ops(os: List<&2, Op>) -> String:
  match os:
    case Nil{}:
      ""
    case Con{o, t}:
      "; " ++ Fill.show.op(o) ++ Fill.show.ops(t)

# An act as text, without the planner's state (laws, tests, logs).
def Fill.show(a: Act) -> String:
  match a:
    case AHead{st, at}:
      "head " ++ N.Size.show(at)
    case AExt{st, at, n, next}:
      "ext " ++ N.Size.show(at) ++ " " ++ U32.show(n) ++ " " ++ N.Size.show(next)
    case AMake{st, es, ops, next}:
      "make " ++ N.Size.show(next) ++ Fill.show.ops(ops)
    case ADone{}:
      "done"
    case ABad{why}:
      "bad " ++ why

# A whole tar in memory
# ---------------------

def Fill.nat(s: N.Size) -> Nat:
  U32.to_nat(Fill.lo(s))

# n bytes of bs from `at` (sizes below 4 GiB).
def Fill.slice(+bs: +List<U32>, at: N.Size, n: Nat) -> +List<U32>:
  List.take(&2, U32, List.drop(&2, U32, bs, Fill.nat(at)), n)

def Fill.run(fuel: Nat, a: Act, +bs: +List<U32>, +dir: String, acc: List<&2, Op>) -> Result<&2, &2, String, List<&2, Op>>:
  match fuel a:
    case 0n _:
      Fail{"tar: archive too long"}
    case 1n+f AHead{st, +at}:
      Fill.run(f, Fill.head(st, at, Fill.slice(bs, at, 512n), dir), bs, dir, acc)
    case 1n+f AExt{st, at, +n, next}:
      Fill.run(f, Fill.ext(st, n, next, Fill.slice(bs, at, U32.to_nat(n)), dir), bs, dir, acc)
    case 1n+f AMake{st, es, ops, next}:
      Fill.run(f, AHead{st, next}, bs, dir, List.append(&2, Op, acc, ops))
    case 1n+f ADone{}:
      Done{acc}
    case 1n+f ABad{why}:
      Fail{why}

# The operations of the host's loop over a tar held in memory, for a
# layer unpacked at dir (no .bend-meta writes), or why it is refused.
def Fill.plan(+dir: String, +bs: +List<U32>) -> Result<&2, &2, String, List<&2, Op>>:
  Fill.run(Nat.add(List.length(&2, U32, bs), 2n), Fill.start(), bs, dir, Nil{})

# After the loop
# --------------

def Fill.side(+dir: String, s: M.Side) -> Op:
  match s:
    case M.Side{p, t}:
      OWrite{dir ++ "/" ++ p, t}

def Fill.sides.go(ss: List<&2, M.Side>, +dir: String) -> List<&2, Op>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      Con{Fill.side(dir, s), Fill.sides.go(t, dir)}

def Fill.seed(m: Maybe<&2, String>) -> U32:
  match m:
    case None{}:
      0
    case Some{h}:
      M.Meta.seed(h)

# The .bend-meta writes of layer chain unpacked at dir, from all of
# Tar's entries in order.
def Fill.sides(+dir: String, chain: String, +es: List<&2, T.Ent>) -> List<&2, Op>:
  Fill.sides.go(M.Meta.sides(Fill.seed(Y.Lay.hex(chain)), es), dir)

def Fill.dirs.put(d: Bool, p: String, rest: List<&2, String>) -> List<&2, String>:
  match d:
    case True{}:
      Con{p, rest}
    case False{}:
      rest

def Fill.dirs(es: List<&2, T.Ent>, +dir: String) -> List<&2, String>:
  match es:
    case Nil{}:
      Nil{}
    case Con{+e, t}:
      Fill.dirs.put(T.Ty.is_dir(T.Ent.ty(e)), dir ++ "/" ++ T.Ent.host(e), Fill.dirs(t, dir))

# The directories to fsync before the rename: the layer's directories,
# the last made first, then dir itself.
def Fill.syncs(+dir: String, es: List<&2, T.Ent>) -> List<&2, String>:
  List.append(&2, String, List.reverse(&2, String, Fill.dirs(es, dir)), [dir])

# Records
# -------

# Where a layer's record is.
def Fill.rec.path(+root: String, chain: String) -> Maybe<&2, String>:
  Y.Lay.under(Y.Lay.hex(chain), root ++ "/layer-refs/", "")

def Fill.rec.holders(hs: List<&2, String>) -> String:
  match hs:
    case Nil{}:
      ""
    case Con{h, t}:
      "holder " ++ h ++ "\n" ++ Fill.rec.holders(t)

# A record's text.
def Fill.rec.render(l: Y.Layer) -> String:
  match l:
    case Y.Layer{c, d, p, hs, u}:
      "layer-meta 1\nchain " ++ c ++ "\ndiff " ++ d ++ "\nparent " ++ p ++ "\nlast-use " ++ U32.show(u) ++ "\n" ++ Fill.rec.holders(hs)

def Fill.field.if(ok: Bool, +n: Nat, line: String) -> Maybe<&2, String>:
  match ok:
    case True{}:
      Some{String.drop(line, n)}
    case False{}:
      None{}

def Fill.field(+key: String, +line: String) -> Maybe<&2, String>:
  Fill.field.if(String.starts_with(line, key), String.length(key), line)

def Fill.digest_ok(+s: String) -> Bool:
  Maybe.is_some(&2, G.Digest, G.Gram.digest(s))

def Fill.num(m: Maybe<&2, String>) -> Maybe<&2, N.Size>:
  match m:
    case None{}:
      None{}
    case Some{s}:
      N.Size.read(s)

def Fill.rec.hs.cons(m: Maybe<&2, String>, r: Maybe<&2, List<&2, String>>) -> Maybe<&2, List<&2, String>>:
  match m r:
    case Some{+h} Some{hs}:
      Bool.pick(Maybe<&2, List<&2, String>>, String.is_empty(h), None{}, Some{Con{h, hs}})
    case _ _:
      None{}

def Fill.rec.hs.line(last: Bool, +l: String, rest: Maybe<&2, List<&2, String>>) -> Maybe<&2, List<&2, String>>:
  match last:
    case True{}:
      Bool.pick(Maybe<&2, List<&2, String>>, String.is_empty(l), Some{Nil{}}, None{})
    case False{}:
      Fill.rec.hs.cons(Fill.field("holder ", l), rest)

# The holder lines, then the empty string after the last newline.
def Fill.rec.hs(ls: List<&2, String>) -> Maybe<&2, List<&2, String>>:
  match ls:
    case Nil{}:
      None{}
    case Con{+l, +t}:
      Fill.rec.hs.line(List.is_empty(&2, String, t), l, Fill.rec.hs(t))

def Fill.rec.make(c: Maybe<&2, String>, d: Maybe<&2, String>, p: Maybe<&2, String>, u: Maybe<&2, U32>, hs: Maybe<&2, List<&2, String>>) -> Maybe<&2, Y.Layer>:
  match c d p u hs:
    case Some{+c1} Some{+d1} Some{+p1} Some{u1} Some{hs1}:
      Bool.pick(Maybe<&2, Y.Layer>, Fill.digest_ok(c1) && Fill.digest_ok(d1) && (String.is_empty(p1) || Fill.digest_ok(p1)),
        Some{Y.Layer{c1, d1, p1, hs1, u1}}, None{})
    case _ _ _ _ _:
      None{}

def Fill.rec.check(ok: Bool, c: String, d: String, p: String, u: String, rest: List<&2, String>) -> Maybe<&2, Y.Layer>:
  match ok:
    case False{}:
      None{}
    case True{}:
      Fill.rec.make(Fill.field("chain ", c), Fill.field("diff ", d), Fill.field("parent ", p), T.Tar.small(Fill.num(Fill.field("last-use ", u))), Fill.rec.hs(rest))

def Fill.rec.lines(ls: List<&2, String>) -> Maybe<&2, Y.Layer>:
  match ls:
    case Con{v, Con{c, Con{d, Con{p, Con{u, rest}}}}}:
      Fill.rec.check(String.eq(v, "layer-meta 1"), c, d, p, u, rest)
    case _:
      None{}

# A record's layer, or None when it is not one this version wrote.
def Fill.rec.parse(s: String) -> Maybe<&2, Y.Layer>:
  Fill.rec.lines(String.lines(s))

# A new layer's record: published at now, no holder.
def Fill.rec.new(chain: String, diff: String, parent: String, now: U32) -> Y.Layer:
  Y.Layer{chain, diff, parent, Nil{}, now}

# A layer filled again at now: a use.
def Fill.touch(l: Y.Layer, now: U32) -> Y.Layer:
  match l:
    case Y.Layer{c, d, p, hs, u}:
      Y.Layer{c, d, p, hs, now}

# Garbage collection
# ------------------

# The chain ID of a name in <root>/layers, or None for a name the store
# never makes (gc leaves it alone).
def Fill.chain_of(+name: String) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, G.Gram.hex64(name), Some{"sha256:" ++ name}, None{})

def Fill.or.same(same: Bool, l: Y.Layer, +chain: String) -> Y.Layer:
  match same:
    case True{}:
      l
    case False{}:
      Y.Layer{chain, "", "", Nil{}, 0}

def Fill.or.parse(m: Maybe<&2, String>) -> Maybe<&2, Y.Layer>:
  match m:
    case None{}:
      None{}
    case Some{s}:
      Fill.rec.parse(s)

def Fill.or.of(+chain: String, m: Maybe<&2, Y.Layer>) -> Y.Layer:
  match m:
    case None{}:
      Y.Layer{chain, "", "", Nil{}, 0}
    case Some{+l}:
      Fill.or.same(String.eq(Y.Layer.chain(l), chain), l, chain)

# What gc knows of the published layer chain from its record's text
# (None: no record): a record that is unreadable or names another layer
# counts as no holder and no use since 1970.
def Fill.or(+chain: String, m: Maybe<&2, String>) -> Y.Layer:
  Fill.or.of(chain, Fill.or.parse(m))

# One day, in seconds.
def Fill.tmp_ttl() -> U32:
  86400

# Whether gc removes the entry name of <root>/tmp, made at mtime: a name
# the store makes, a day old. A clock that went back removes nothing.
def Fill.stale(+name: String, +mtime: U32, +now: U32) -> Bool:
  G.Gram.hex64(String.take(name, 64n)) && String.starts_with(String.drop(name, 64n), ".") && U32.is_ge(now, mtime) && U32.is_ge((now - mtime : U32), Fill.tmp_ttl())

def Fill.born.cut(c: T.SCut) -> Maybe<&2, U32>:
  match c:
    case T.SCut{b, a, f}:
      T.Tar.dec32(b)

# When a tmp entry was made: the nonce of a name the store makes (64 hex
# digits, ".", the nonce, then nothing or "." and more), which a fill
# sets to the wall clock's seconds. None for any other name.
def Fill.born(+name: String) -> Maybe<&2, U32>:
  Bool.pick(Maybe<&2, U32>, G.Gram.hex64(String.take(name, 64n)) && String.starts_with(String.drop(name, 64n), "."),
    Fill.born.cut(T.Tar.scut(String.drop(name, 65n), '.')), None{})

def Fill.stale.of(m: Maybe<&2, U32>, +name: String, +now: U32) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{b}:
      Fill.stale(name, b, now)

# Whether gc removes the entry name of a tmp directory at now, by the
# time in its name.
def Fill.stale.name(+name: String, +now: U32) -> Bool:
  Fill.stale.of(Fill.born(name), name, now)

# The decompressed tar and the record of a fill unpacking at tmp.
def Fill.tmp.tar(tmp: String) -> String:
  tmp ++ ".tar"

def Fill.tmp.rec(tmp: String) -> String:
  tmp ++ ".rec"

# Present
# -------

# What a fill finds of a layer: its record, kept only when the layer's
# directory <root>/layers/<hex> is there too (there). A record without a
# directory (a gc that crashed between the two, or a fill that failed
# after it wrote the record) is no layer: the fill unpacks it again.
def Fill.present(m: Maybe<&2, Y.Layer>, there: Bool) -> Maybe<&2, Y.Layer>:
  match there:
    case True{}:
      m
    case False{}:
      None{}

# Unpack limits
# -------------

# The decompressed tar may be at most this many times the compressed
# layer (a gzip or zstd bomb) ...
def Fill.unz.ratio() -> U32:
  50

# ... and at most 64 GiB, in MiB.
def Fill.unz.max_mib() -> U32:
  65536

# ratio * lo bytes in MiB, rounded up (lo below 2^32: no U32 overflows).
def Fill.unz.lo(+lo: U32) -> U32:
  +whole : U32 = (lo / 1048576 : U32)
  +part : U32 = (lo % 1048576 : U32)
  +up : U32 = (((part * Fill.unz.ratio() : U32) + 1048575 : U32) / 1048576 : U32)
  ((whole * Fill.unz.ratio() : U32) + up : U32)

def Fill.unz.clamp(+m: U32) -> U32:
  Bool.pick(U32, U32.is_zero(m), 1, Bool.pick(U32, U32.is_gt(m, Fill.unz.max_mib()), Fill.unz.max_mib(), m))

# The max_mib that Unz.file gets for a layer blob of size s: ratio times
# s in MiB, rounded up, at most max_mib, at least 1 (Unz.file reads 0 as
# no limit; MiB is its unit, so a blob below 21 KiB may expand to 1 MiB).
def Fill.unz.mib(s: N.Size) -> U32:
  match s:
    case N.Size{+h, +l}:
      Bool.pick(U32, U32.is_zero(h), Fill.unz.clamp(Fill.unz.lo(l)), Fill.unz.max_mib())

# The decompression error with the cap, when the cap is what stopped it
# (bend-kube's unz.c: "unz: the output is past its limit").
def Fill.unz.why(+mib: U32, +msg: String) -> String:
  Bool.pick(String, String.contains(msg, "past its limit"),
    msg ++ " (the cap is " ++ U32.show(mib) ++ " MiB: 50 times the compressed layer, at most 64 GiB)", msg)

# A layer may have at most this many tar entries; the host keeps every
# entry in memory until the .bend-meta files are written.
def Fill.max_ents() -> U32:
  2000000

def Fill.ents.go(es: List<&2, T.Ent>, +n: U32) -> U32:
  match es:
    case Nil{}:
      n
    case Con{e, t}:
      Fill.ents.go(t, (n + 1 : U32))

# The entries seen once es (one step's) follow n.
def Fill.ents(+n: U32, es: List<&2, T.Ent>) -> U32:
  Fill.ents.go(es, n)

# Whether n entries pass the cap.
def Fill.too_many(+n: U32) -> Bool:
  U32.is_gt(n, Fill.max_ents())

# Held layers
# -----------
#
# A node's snapshotter writes the shared layers it holds to its share
# (Spb.held, src/layers/pb.bend): one "<chain ID> <holder>" line per
# snapshot that stands on one. gc reads every node's file under
# ~/.vk8s/clusters (<cluster>/share/layers.held and
# <cluster>/nodes/<worker>/share/layers.held) and never removes a layer
# one of them names. The guest wrote it, so it is untrusted: the host
# reads at most Fill.held.max() bytes, never through a symlink, and keeps
# only lines that are exactly "sha256:", 64 lowercase hex digits, a space
# and a holder that is not empty. Other lines are ignored. A guest can
# only keep layers (its own, or ones it names); it never makes gc remove
# one. The holder text is never written to a record.

# The most bytes gc reads of one layers.held.
def Fill.held.max() -> U32:
  4194304

# The holder gc gives a layer that a layers.held names.
def Fill.held.holder() -> String:
  "layers.held"

def Fill.held.nonempty(+s: String) -> Bool:
  Bool.not(String.is_empty(s))

# The chain ID of one line of a layers.held, or None for a bad line.
def Fill.held.line(+line: String) -> Maybe<&2, String>:
  +c : String = String.take(line, 71n)
  +rest : String = String.drop(line, 71n)
  Bool.pick(Maybe<&2, String>, Fill.digest_ok(c) && String.starts_with(rest, " ") && Fill.held.nonempty(String.drop(rest, 1n)), Some{c}, None{})

def Fill.held.put(m: Maybe<&2, String>, rest: List<&2, String>) -> List<&2, String>:
  match m:
    case None{}:
      rest
    case Some{c}:
      Con{c, rest}

def Fill.held.lines(ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{+l, t}:
      Fill.held.put(Fill.held.line(l), Fill.held.lines(t))

# The chain IDs a layers.held names, in order (bad lines ignored).
def Fill.held.parse(s: String) -> List<&2, String>:
  Fill.held.lines(String.lines(s))

def Fill.hold.one(l: Y.Layer, +held: List<&2, String>) -> Y.Layer:
  match l:
    case Y.Layer{+c, +d, +p, +hs, +u}:
      Bool.pick(Y.Layer, Y.Lay.holds(held, c), Y.Layer{c, d, p, Y.Lay.hold(hs, Fill.held.holder()), u}, Y.Layer{c, d, p, hs, u})

# The layers gc read, each one that held names held by
# Fill.held.holder(), so Lay.gc.drop keeps it.
def Fill.hold(ls: List<&2, Y.Layer>, +held: List<&2, String>) -> List<&2, Y.Layer>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{l, t}:
      Con{Fill.hold.one(l, held), Fill.hold(t, held)}

# The lock
# --------
#
# fill and gc each hold <root>/layers.lock while they run, so gc never
# removes a layer that a fill is about to use or publish. The lock is
# made with O_EXCL and holds the wall clock's seconds when it was taken
# (a fill writes the time again before each layer). A lock
# Fill.lock.ttl() old, or one that went away, is taken over; a lock whose
# text is not a time (one being written) is not.

def Fill.lock.path(+root: String) -> String:
  root ++ "/layers.lock"

# 60 minutes, in seconds.
def Fill.lock.ttl() -> U32:
  3600

def Fill.lock.text(+now: U32) -> String:
  U32.show(now) ++ "\n"

def Fill.lock.at(m: Maybe<&2, U32>, +now: U32) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{+t}:
      U32.is_ge(now, t) && U32.is_ge((now - t : U32), Fill.lock.ttl())

def Fill.lock.first(ls: List<&2, String>) -> Maybe<&2, U32>:
  match ls:
    case Nil{}:
      None{}
    case Con{+l, t}:
      T.Tar.dec32(l)

# Whether a lock with this text is stale at now. A clock that went back
# makes no lock stale.
def Fill.lock.stale(s: String, +now: U32) -> Bool:
  Fill.lock.at(Fill.lock.first(String.lines(s)), now)

# Whether a lock that a new lock found (its text; None: it went away or
# cannot be read) may be taken over at now.
def Fill.lock.stale.of(m: Maybe<&2, String>, +now: U32) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{s}:
      Fill.lock.stale(s, now)

# Records, version 2
# ------------------

# What a fill unpacked of a layer: the bytes of its regular files and its
# inodes (as containerd's fs.DiskUsage counts them: every file,
# directory, symlink, device, FIFO and whiteout once, the layer's own
# directory too; a hard link is its target's inode; an opaque marker is
# none). size is the files' length, not the blocks they take. A
# directory a tar names twice counts twice.
type Use is Data:
  Use{size: N.Size, inodes: U32}

# A record: the layer, and what its fill unpacked (None: a record of
# version 1, which does not say).
type Rec is Data:
  Rec{layer: Y.Layer, use: Maybe<&2, Use>}

def Fill.use.step(t: T.Ty, sz: N.Size, acc: Use) -> Use:
  match t acc:
    case T.TReg{} Use{s, n}:
      Use{N.Size.add(s, sz), (n + 1 : U32)}
    case T.THard{} a:
      a
    case T.TOpq{} a:
      a
    case _ Use{s, n}:
      Use{s, (n + 1 : U32)}

def Fill.use.go(es: List<&2, T.Ent>, acc: Use) -> Use:
  match es:
    case Nil{}:
      acc
    case Con{T.Ent{p, h, ty, m, u, g, ma, mi, mt, ns, xs, l, sz}, t}:
      Fill.use.go(t, Fill.use.step(ty, sz, acc))

# The usage of a layer unpacked from the entries es (Tar.plan's, every
# step's in order).
def Fill.use.of(es: List<&2, T.Ent>) -> Use:
  Fill.use.go(es, Use{N.Size.zero(), 1})

# A record's text, version 2.
def Fill.rec.render.v2(l: Y.Layer, u: Use) -> String:
  match l u:
    case Y.Layer{c, d, p, hs, t} Use{s, n}:
      "layer-meta 2\nchain " ++ c ++ "\ndiff " ++ d ++ "\nparent " ++ p ++ "\nlast-use " ++ U32.show(t) ++ "\nsize " ++ N.Size.show(s) ++ "\ninodes " ++ U32.show(n) ++ "\n" ++ Fill.rec.holders(hs)

# A record's text in the version it has: 2 when its usage is known.
def Fill.rec.render.of(r: Rec) -> String:
  match r:
    case Rec{l, None{}}:
      Fill.rec.render(l)
    case Rec{l, Some{u}}:
      Fill.rec.render.v2(l, u)

def Fill.rec.v1.of(m: Maybe<&2, Y.Layer>) -> Maybe<&2, Rec>:
  match m:
    case None{}:
      None{}
    case Some{l}:
      Some{Rec{l, None{}}}

def Fill.rec.v2.of(m: Maybe<&2, Y.Layer>, u: Maybe<&2, N.Size>, n: Maybe<&2, U32>) -> Maybe<&2, Rec>:
  match m u n:
    case Some{l} Some{s} Some{k}:
      Some{Rec{l, Some{Use{s, k}}}}
    case _ _ _:
      None{}

def Fill.rec.check.v2(ok: Bool, c: String, d: String, p: String, u: String, sz: String, n: String, rest: List<&2, String>) -> Maybe<&2, Rec>:
  match ok:
    case False{}:
      None{}
    case True{}:
      Fill.rec.v2.of(Fill.rec.check(True{}, c, d, p, u, rest), Fill.num(Fill.field("size ", sz)), T.Tar.small(Fill.num(Fill.field("inodes ", n))))

def Fill.rec.lines.v2(ls: List<&2, String>) -> Maybe<&2, Rec>:
  match ls:
    case Con{v, Con{c, Con{d, Con{p, Con{u, Con{sz, Con{n, rest}}}}}}}:
      Fill.rec.check.v2(String.eq(v, "layer-meta 2"), c, d, p, u, sz, n, rest)
    case _:
      None{}

# A record of version 2, or of version 1 (its usage None); None for
# any other text.
def Fill.rec.parse.v2(+s: String) -> Maybe<&2, Rec>:
  Bool.pick(Maybe<&2, Rec>, String.starts_with(s, "layer-meta 1\n"), Fill.rec.v1.of(Fill.rec.parse(s)), Fill.rec.lines.v2(String.lines(s)))

def Fill.rec.layer(m: Maybe<&2, Rec>) -> Maybe<&2, Y.Layer>:
  match m:
    case None{}:
      None{}
    case Some{Rec{l, u}}:
      Some{l}

def Fill.use.or(a: Maybe<&2, Use>, b: Maybe<&2, Use>) -> Maybe<&2, Use>:
  match a:
    case Some{x}:
      Some{x}
    case None{}:
      b

# The record after a use of layer l at now (m: the record the store has,
# u: the usage, when this fill unpacked it): the old record touched, its
# usage kept unless u is known; l with u when there is none.
def Fill.rec.use(m: Maybe<&2, Rec>, l: Y.Layer, u: Maybe<&2, Use>, +now: U32) -> Rec:
  match m:
    case None{}:
      Rec{l, u}
    case Some{Rec{x, v}}:
      Rec{Fill.touch(x, now), Fill.use.or(u, v)}

# The copy of a layer's record that nodes see: <root>/layers/<hex>.rec.
def Fill.rec.share(+root: String, chain: String) -> Maybe<&2, String>:
  Y.Lay.under(Y.Lay.hex(chain), root ++ "/layers/", ".rec")

# Where a node reads that copy.
def Fill.rec.mount(chain: String) -> Maybe<&2, String>:
  Y.Lay.under(Y.Lay.hex(chain), "/mnt/layers/", ".rec")

def Fill.or.parse.v2(m: Maybe<&2, String>) -> Maybe<&2, Y.Layer>:
  match m:
    case None{}:
      None{}
    case Some{s}:
      Fill.rec.layer(Fill.rec.parse.v2(s))

# As Fill.or, for records of version 1 or 2.
def Fill.or.v2(+chain: String, m: Maybe<&2, String>) -> Y.Layer:
  Fill.or.of(chain, Fill.or.parse.v2(m))
