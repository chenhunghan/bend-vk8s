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
# A fill writes it before the rename and again on every later fill of
# the same layer (a use). gc treats a layer whose record is missing or
# unreadable as unheld and unused since 1970, so it removes it.
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
