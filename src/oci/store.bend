import Base
import ./size.bend as N
import ./grammar.bend as G

# Store policy of the pull-through OCI mirror: where objects live on disk,
# what their sidecar records, when they expire, and what a prune removes.
# Pure: the host (host/oci/) lists directories, reads and writes files,
# and asks these defs for every path and every decision. Part of the
# self-contained OCI library: it imports only Base and src/oci/.
#
# Layout under the cache root (the mirror's own; user decision 2026-11-17):
#   <root>/<registry>/blobs/sha256/<ab>/<hex>        the object's bytes
#   <root>/<registry>/blobs/sha256/<ab>/<hex>.meta   its sidecar
#   <root>/tmp/<hex>.<nonce>                         a fill in progress
# <ab> is the first two hex digits, as CNCF distribution's storage driver
# lays out blobs. Manifests by digest are stored the same way. tmp/ is on
# the same file system, so a verified fill is renamed into place.
#
# Every path is built from a registry and a digest that passed their
# grammar (src/oci/grammar.bend): a registry is a host[:port] made of
# alphanumerics, "-" and ".", never "." or ".." alone, never with "/";
# a digest is "sha256:" and 64 lowercase hex digits. Anything else gives
# no path at all.
#
# Expiry (user decision 2026-11-17): an object expires 72 h after its last
# use; every hit records the time of use in the sidecar. There is no size
# cap. `cache prune` removes everything.

type Meta is Data:
  Meta{media: String, size: N.Size, used: U32}

# 72 hours, in seconds.
def Store.ttl() -> U32:
  259200

def Store.registry.go(ok: Bool, s: String) -> Maybe<&2, String>:
  match ok:
    case True{}:
      Some{String.to_lower(s)}
    case False{}:
      None{}

# A registry's directory name: the validated host[:port], lowercased (host
# names are case-insensitive), or None.
def Store.registry(+s: String) -> Maybe<&2, String>:
  Store.registry.go(G.Gram.registry(s), s)

def Store.at(+root: String, reg: String, +hex: String) -> String:
  root ++ "/" ++ reg ++ "/blobs/sha256/" ++ String.take(hex, 2n) ++ "/" ++ hex

# The paths of one object: its bytes, its sidecar, and a fill's tmp file.
type Paths is Data:
  Paths{blob: String, meta: String, tmp: String}

def Store.paths.make(+root: String, reg: String, +hex: String, nonce: U32) -> Paths:
  +blob = Store.at(root, reg, hex)
  Paths{blob, blob ++ ".meta", root ++ "/tmp/" ++ hex ++ "." ++ U32.show(nonce)}

def Store.paths.digest(d: Maybe<&2, G.Digest>, root: String, reg: String, nonce: U32) -> Maybe<&2, Paths>:
  match d:
    case None{}:
      None{}
    case Some{x}:
      Some{Store.paths.make(root, reg, G.Gram.digest.hex(x), nonce)}

def Store.paths.reg(r: Maybe<&2, String>, root: String, digest: String, nonce: U32) -> Maybe<&2, Paths>:
  match r:
    case None{}:
      None{}
    case Some{reg}:
      Store.paths.digest(G.Gram.digest(digest), root, reg, nonce)

# The paths of the object digest ("sha256:<hex>") from registry, the tmp
# file named with nonce (the host picks one per fill); None unless both
# names are valid.
def Store.paths(root: String, registry: String, digest: String, nonce: U32) -> Maybe<&2, Paths>:
  Store.paths.reg(Store.registry(registry), root, digest, nonce)

def Store.blob.of(m: Maybe<&2, Paths>) -> Maybe<&2, String>:
  match m:
    case None{}:
      None{}
    case Some{Paths{b, x, t}}:
      Some{b}

def Store.meta.of(m: Maybe<&2, Paths>) -> Maybe<&2, String>:
  match m:
    case None{}:
      None{}
    case Some{Paths{b, x, t}}:
      Some{x}

# Where an object's bytes are, or None.
def Store.blob_path(root: String, registry: String, digest: String) -> Maybe<&2, String>:
  Store.blob.of(Store.paths(root, registry, digest, 0))

# Where an object's sidecar is, or None.
def Store.meta_path(root: String, registry: String, digest: String) -> Maybe<&2, String>:
  Store.meta.of(Store.paths(root, registry, digest, 0))

# The directory of fills in progress; the host empties it at start.
def Store.tmp_dir(root: String) -> String:
  root ++ "/tmp"

# A fill is kept only when the bytes hash to the digest asked for and, if
# upstream declared a length, the count matches it (spec.md: clients and
# so the mirror verify content against the digest).
def Store.verified.size(m: Maybe<&2, N.Size>, got: N.Size) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{want}:
      N.Size.is_eq(want, got)

def Store.verified(digest: String, got_hex: String, declared: Maybe<&2, N.Size>, got: N.Size) -> Bool:
  Bool.and(String.eq(digest, "sha256:" ++ got_hex), Store.verified.size(declared, got))

# The sidecar: four lines, so a reader can refuse what it does not know.
#   oci-cache-meta 1
#   media-type <type/subtype>
#   size <bytes>
#   last-use <unix seconds>
def Store.meta.render(m: Meta) -> String:
  match m:
    case Meta{media, size, used}:
      "oci-cache-meta 1\nmedia-type " ++ media ++ "\nsize " ++ N.Size.show(size) ++ "\nlast-use " ++ U32.show(used) ++ "\n"

def Store.field.if(ok: Bool, n: Nat, line: String) -> Maybe<&2, String>:
  match ok:
    case True{}:
      Some{String.drop(line, n)}
    case False{}:
      None{}

def Store.field(+key: String, +line: String) -> Maybe<&2, String>:
  Store.field.if(String.starts_with(line, key), String.length(key), line)

def Store.u32.if(ok: Bool, v: U32) -> Maybe<&2, U32>:
  match ok:
    case True{}:
      Some{v}
    case False{}:
      None{}

def Store.u32.of(m: Maybe<&2, N.Size>) -> Maybe<&2, U32>:
  match m:
    case Some{N.Size{+h, l}}:
      Store.u32.if(U32.is_zero(h), l)
    case None{}:
      None{}

def Store.meta.make(ok: Bool, media: String, size: Maybe<&2, N.Size>, used: Maybe<&2, U32>) -> Maybe<&2, Meta>:
  match ok size used:
    case True{} Some{s} Some{u}:
      Some{Meta{media, s, u}}
    case _ _ _:
      None{}

def Store.meta.fields(mt: Maybe<&2, String>, sz: Maybe<&2, String>, lu: Maybe<&2, String>) -> Maybe<&2, Meta>:
  match mt sz lu:
    case Some{+m} Some{s} Some{u}:
      Store.meta.make(G.Gram.media(m), m, N.Size.read(s), Store.u32.of(N.Size.read(u)))
    case _ _ _:
      None{}

def Store.meta.check(ok: Bool, mt: String, sz: String, lu: String) -> Maybe<&2, Meta>:
  match ok:
    case True{}:
      Store.meta.fields(Store.field("media-type ", mt), Store.field("size ", sz), Store.field("last-use ", lu))
    case False{}:
      None{}

def Store.meta.lines(ls: List<&2, String>) -> Maybe<&2, Meta>:
  match ls:
    case Con{v, Con{mt, Con{sz, Con{lu, Con{e, Nil{}}}}}}:
      Store.meta.check(Bool.and(String.eq(v, "oci-cache-meta 1"), String.is_empty(e)), mt, sz, lu)
    case _:
      None{}

# A sidecar's record, or None when it is not one this version wrote (the
# host then treats the object as missing and fills it again).
def Store.meta.parse(s: String) -> Maybe<&2, Meta>:
  Store.meta.lines(String.lines(s))

# The record of a fresh fill: the cleaned upstream media type (manifests
# need theirs back as Content-Type), the size and the time of the fill.
def Store.meta.new(media: String, size: N.Size, now: U32) -> Meta:
  Meta{G.Gram.media.clean(media), size, now}

# A hit records its time of use.
def Store.touch(m: Meta, now: U32) -> Meta:
  match m:
    case Meta{media, size, used}:
      Meta{media, size, now}

def Store.hit.of(m: Maybe<&2, Meta>, now: U32) -> Maybe<&2, Meta>:
  match m:
    case None{}:
      None{}
    case Some{x}:
      Some{Store.touch(x, now)}

# A request found the sidecar s: the record to serve from and write back,
# its last use now; None when the sidecar is unreadable (a miss). A hit
# serves an object even past its expiry: the bytes are still the digest's,
# and the hit renews them.
def Store.hit(s: String, now: U32) -> Maybe<&2, Meta>:
  Store.hit.of(Store.meta.parse(s), now)

# Expired: at least 72 h since the last use. A clock that went back (now
# before the last use) expires nothing.
def Store.expired(m: Meta, +now: U32) -> Bool:
  match m:
    case Meta{media, size, +used}:
      Bool.and(U32.is_ge(now, used), U32.is_ge(U32.sub(now, used), Store.ttl()))

# One stored object the host found while walking the store: its registry
# directory, its digest ("sha256:" and the file name) and its sidecar's
# text, if it could read one.
type Item is Data:
  Item{registry: String, digest: String, sidecar: Maybe<&2, String>}

def Store.drop.if(gone: Bool, ps: Paths) -> List<&2, String>:
  match gone ps:
    case True{} Paths{b, m, t}:
      [b, m]
    case False{} _:
      []

def Store.drop.meta(m: Maybe<&2, Meta>, ps: Paths, +now: U32) -> List<&2, String>:
  match m:
    case None{}:
      Store.drop.if(True{}, ps)
    case Some{x}:
      Store.drop.if(Store.expired(x, now), ps)

def Store.drop.paths(p: Maybe<&2, Paths>, s: Maybe<&2, String>, +now: U32) -> List<&2, String>:
  match p s:
    case None{} _:
      []
    case Some{ps} None{}:
      Store.drop.if(True{}, ps)
    case Some{ps} Some{text}:
      Store.drop.meta(Store.meta.parse(text), ps, now)

# What the expiry sweep deletes for one object: its bytes and its sidecar
# when it expired or its sidecar is missing or unreadable; nothing for a
# file whose names are not valid (no path is built from them).
def Store.sweep.one(+root: String, +now: U32, it: Item) -> List<&2, String>:
  match it:
    case Item{r, d, s}:
      Store.drop.paths(Store.paths(root, r, d, 0), s, now)

def Store.sweep.seq(items: List<&2, Item>, +root: String, +now: U32) -> List<&2, String>:
  match items:
    case Nil{}:
      []
    case Con{it, t}:
      List.append(&2, String, Store.sweep.one(root, now, it), Store.sweep.seq(t, root, now))

# The items at even positions (0, 2, 4, ...).
def Store.evens(xs: List<&2, Item>) -> List<&2, Item>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, Nil{}}:
      Con{h, Nil{}}
    case Con{h, Con{o, t}}:
      Con{h, Store.evens(t)}

# The items at odd positions (1, 3, 5, ...).
def Store.odds(xs: List<&2, Item>) -> List<&2, Item>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      Store.evens(t)

# The objects are independent, so the sweep splits them into 2^depth even
# parts and decides each part in parallel.
def Store.sweep.par(depth: Nat, +items: List<&2, Item>, +root: String, +now: U32) -> List<&2, String>:
  match depth:
    case 0n:
      Store.sweep.seq(items, root, now)
    case 1n+d:
      +e = d
      x y = Store.sweep.par(e, Store.evens(items), root, now) Store.sweep.par(e, Store.odds(items), root, now)
      List.append(&2, String, x, y)

# The paths the expiry sweep deletes at time now.
def Store.sweep(+root: String, +now: U32, items: List<&2, Item>) -> List<&2, String>:
  Store.sweep.par(3n, items, root, now)

def Store.prune.keep(m: Maybe<&2, String>, +root: String, rest: List<&2, String>) -> List<&2, String>:
  match m:
    case None{}:
      rest
    case Some{reg}:
      Con{root ++ "/" ++ reg, rest}

def Store.prune.dirs(rs: List<&2, String>, +root: String) -> List<&2, String>:
  match rs:
    case Nil{}:
      []
    case Con{r, t}:
      Store.prune.keep(Store.registry(r), root, Store.prune.dirs(t, root))

# `cache prune`: everything goes. The tmp directory first, then the
# directory of every registry the host found under the root; a directory
# whose name is not a valid registry is left alone (vk8s never made it).
def Store.prune(+root: String, registries: List<&2, String>) -> List<&2, String>:
  Con{root ++ "/tmp", Store.prune.dirs(registries, root)}
