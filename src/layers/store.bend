import Base
import ../lib/sha256.bend as H
import ../oci/grammar.bend as G

# The shared read-only layer store on the host: one unpacked layer per
# chain ID, shared by every node of every cluster through bend-vmm's
# `--share DIR,meta` (src/layers/meta.bend). Pure: the host lists, reads
# and writes; these defs decide paths, the publish protocol, references
# and garbage collection.
#
# Layout under the store's root:
#   <root>/layers/<hex>        a published layer (<hex>: its chain ID's
#                              hex; a ":" would split overlayfs' lowerdir)
#   <root>/tmp/<hex>.<nonce>   a layer being unpacked
# In a node the layers share is mounted at /mnt/layers, so a layer is
# /mnt/layers/<hex> there.
#
# Content addressing (image-spec config.md): a layer's diffID is the
# digest of its uncompressed tar; its chain ID is its diffID for the
# first layer, else sha256 of "<parent chain ID> <diffID>". Two images
# that share a base share its chain IDs, so its layers are stored once.
#
# Publish: unpack into tmp, fsync every file and directory, rename into
# place, fsync layers/. A crash leaves at most a tmp directory (`vk8s
# layers gc` removes tmp entries a day old, Fill.stale); a rename that
# finds the layer in place lost a race and removes its tmp directory.
#
# References: a holder ("<node>/<snapshot>", src/layers/snap.bend) holds
# a layer while a committed snapshot of a node stands on it. A snapshot's
# lower layers are held through its parents, which containerd does not
# remove while they have children. On the host, holders reach gc
# through each node's share/layers.held (Spb.held), which gc reads
# before it decides (Fill.hold, src/layers/fill.bend); records on disk
# keep no holder.
#
# Expiry (user decision, 72 h, as the OCI mirror's): a layer no holder
# holds is removed 72 h after its last use (publish, acquire or release).
# A held layer is never removed.

type Layer is Data:
  Layer{chain: String, diff: String, parent: String, holders: List<&2, String>, used: U32}

# 72 hours, in seconds.
def Lay.ttl() -> U32:
  259200

# Content addressing
# ------------------

# The chain ID of a layer with diffID diff on the chain parent ("" for
# the first layer).
def Lay.chain(+parent: String, +diff: String) -> String:
  Bool.pick(String, String.is_empty(parent), diff, "sha256:" ++ H.Sha256.hex_of(parent ++ " " ++ diff))

# The chain IDs of an image's layers, from its rootfs.diff_ids in order.
def Lay.chains.go(ds: List<&2, String>, +prev: String) -> List<&2, String>:
  match ds:
    case Nil{}:
      Nil{}
    case Con{d, t}:
      +c : String = Lay.chain(prev, d)
      Con{c, Lay.chains.go(t, c)}

def Lay.chains(ds: List<&2, String>) -> List<&2, String>:
  Lay.chains.go(ds, "")

def Lay.hex.of(m: Maybe<&2, G.Digest>) -> Maybe<&2, String>:
  match m:
    case None{}:
      None{}
    case Some{d}:
      Some{G.Gram.digest.hex(d)}

# The hex of a chain ID, or None unless it is "sha256:" and 64 lowercase
# hex digits (no other name ever becomes a path).
def Lay.hex(chain: String) -> Maybe<&2, String>:
  Lay.hex.of(G.Gram.digest(chain))

def Lay.under(m: Maybe<&2, String>, pre: String, post: String) -> Maybe<&2, String>:
  match m:
    case None{}:
      None{}
    case Some{h}:
      Some{pre ++ h ++ post}

# Where a published layer is on the host.
def Lay.dir(root: String, chain: String) -> Maybe<&2, String>:
  Lay.under(Lay.hex(chain), root ++ "/layers/", "")

# Where a layer is unpacked before it is published.
def Lay.tmp(root: String, chain: String, nonce: U32) -> Maybe<&2, String>:
  Lay.under(Lay.hex(chain), root ++ "/tmp/", "." ++ U32.show(nonce))

# Where a node sees a layer.
def Lay.mount(chain: String) -> Maybe<&2, String>:
  Lay.under(Lay.hex(chain), "/mnt/layers/", "")

# Publishing
# ----------

# One step of the publish protocol, for the host to run in order.
type Io is Data:
  # make the directory
  IoMkdir{path: String}
  # unpack the layer's tar into the directory: Tar.head and Tar.ext over
  # its blocks, every entry at its host path, then Meta.sides' files
  IoUnpack{dir: String}
  # fsync every file and directory under path, then path
  IoFsync{path: String}
  # rename(2); when to already exists, the layer is published: remove from
  IoRename{from: String, to: String}
  # fsync a directory, so a rename in it is durable
  IoFsyncDir{path: String}
  # remove the tree
  IoRemove{path: String}

def Lay.publish.of(t: Maybe<&2, String>, d: Maybe<&2, String>, +root: String) -> Maybe<&2, List<&2, Io>>:
  match t d:
    case Some{+tmp} Some{dir}:
      Some{[IoMkdir{tmp}, IoUnpack{tmp}, IoFsync{tmp}, IoRename{tmp, dir}, IoFsyncDir{root ++ "/layers"}]}
    case _ _:
      None{}

# The steps that publish layer chain from a tmp directory named with
# nonce (one per publish), or None for a chain ID that is not one.
def Lay.publish(+root: String, +chain: String, nonce: U32) -> Maybe<&2, List<&2, Io>>:
  Lay.publish.of(Lay.tmp(root, chain, nonce), Lay.dir(root, chain), root)

def Layer.chain(l: Layer) -> String:
  match l:
    case Layer{c, d, p, hs, u}:
      c

def Layer.holders(l: Layer) -> List<&2, String>:
  match l:
    case Layer{c, d, p, hs, u}:
      hs

# What the store holds of a chain ID.
def Lay.find(ls: List<&2, Layer>, +chain: String) -> Maybe<&2, Layer>:
  match ls:
    case Nil{}:
      None{}
    case Con{+l, t}:
      Bool.pick(Maybe<&2, Layer>, String.eq(Layer.chain(l), chain), Some{l}, Lay.find(t, chain))

def Lay.has(+ls: List<&2, Layer>, +chain: String) -> Bool:
  Maybe.is_some(&2, Layer, Lay.find(ls, chain))

def Lay.add.if(have: Bool, ls: List<&2, Layer>, l: Layer) -> List<&2, Layer>:
  match have:
    case True{}:
      ls
    case False{}:
      List.append(&2, Layer, ls, [l])

# The store once layer chain (diffID diff, parent chain parent) is
# published at now; a layer already there stays as it is.
def Lay.add(+ls: List<&2, Layer>, +chain: String, diff: String, parent: String, now: U32) -> List<&2, Layer>:
  Lay.add.if(Lay.has(ls, chain), ls, Layer{chain, diff, parent, Nil{}, now})

# References
# ----------

def Lay.holds(hs: List<&2, String>, +h: String) -> Bool:
  match hs:
    case Nil{}:
      False{}
    case Con{x, t}:
      String.eq(x, h) || Lay.holds(t, h)

# Keep x in front of rest unless it is the dropped name (one recursion a
# step: Bool.pick computes both its arguments).
def Lay.without.put(hit: Bool, +x: String, rest: List<&2, String>) -> List<&2, String>:
  match hit:
    case True{}:
      rest
    case False{}:
      Con{x, rest}

def Lay.without(hs: List<&2, String>, +h: String) -> List<&2, String>:
  match hs:
    case Nil{}:
      Nil{}
    case Con{+x, t}:
      Lay.without.put(String.eq(x, h), x, Lay.without(t, h))

def Lay.hold(+hs: List<&2, String>, +h: String) -> List<&2, String>:
  Bool.pick(List<&2, String>, Lay.holds(hs, h), hs, List.append(&2, String, hs, [h]))

def Lay.acq.one(l: Layer, +chain: String, +holder: String, +now: U32) -> Layer:
  match l:
    case Layer{+c, +d, +p, +hs, +u}:
      Bool.pick(Layer, String.eq(c, chain), Layer{c, d, p, Lay.hold(hs, holder), now}, Layer{c, d, p, hs, u})

def Lay.acq.all(ls: List<&2, Layer>, +chain: String, +holder: String, +now: U32) -> List<&2, Layer>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{l, t}:
      Con{Lay.acq.one(l, chain, holder, now), Lay.acq.all(t, chain, holder, now)}

def Lay.acquire.if(have: Bool, ls: List<&2, Layer>, chain: String, holder: String, now: U32) -> Maybe<&2, List<&2, Layer>>:
  match have:
    case True{}:
      Some{Lay.acq.all(ls, chain, holder, now)}
    case False{}:
      None{}

# holder takes layer chain at now (taking it twice holds it once); None
# when the store does not have it.
def Lay.acquire(+ls: List<&2, Layer>, +chain: String, holder: String, now: U32) -> Maybe<&2, List<&2, Layer>>:
  Lay.acquire.if(Lay.has(ls, chain), ls, chain, holder, now)

def Lay.rel.one(l: Layer, +chain: String, +holder: String, +now: U32) -> Layer:
  match l:
    case Layer{+c, +d, +p, +hs, +u}:
      Bool.pick(Layer, String.eq(c, chain), Layer{c, d, p, Lay.without(hs, holder), now}, Layer{c, d, p, hs, u})

# holder lets layer chain go at now, its last use.
def Lay.release(ls: List<&2, Layer>, +chain: String, +holder: String, +now: U32) -> List<&2, Layer>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{l, t}:
      Con{Lay.rel.one(l, chain, holder, now), Lay.release(t, chain, holder, now)}

# Garbage collection
# ------------------

# At least 72 h since the last use; a clock that went back expires
# nothing.
def Lay.expired(+used: U32, +now: U32) -> Bool:
  U32.is_ge(now, used) && U32.is_ge((now - used : U32), Lay.ttl())

def Lay.gc.free(hs: List<&2, String>, +used: U32, +now: U32) -> Bool:
  match hs:
    case Nil{}:
      Lay.expired(used, now)
    case Con{h, t}:
      False{}

# Whether the collector removes a layer at now: no holder, and expired.
def Lay.gc.drops(l: Layer, +now: U32) -> Bool:
  match l:
    case Layer{c, d, p, hs, u}:
      Lay.gc.free(hs, u, now)

def Lay.gc.drop.put(d: Bool, l: Layer, rest: List<&2, Layer>) -> List<&2, Layer>:
  match d:
    case True{}:
      Con{l, rest}
    case False{}:
      rest

def Lay.gc.keep.put(d: Bool, l: Layer, rest: List<&2, Layer>) -> List<&2, Layer>:
  match d:
    case True{}:
      rest
    case False{}:
      Con{l, rest}

# The layers the collector removes at now.
def Lay.gc.drop(ls: List<&2, Layer>, +now: U32) -> List<&2, Layer>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{+l, t}:
      Lay.gc.drop.put(Lay.gc.drops(l, now), l, Lay.gc.drop(t, now))

# The store after the collector ran at now.
def Lay.gc.keep(ls: List<&2, Layer>, +now: U32) -> List<&2, Layer>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{+l, t}:
      Lay.gc.keep.put(Lay.gc.drops(l, now), l, Lay.gc.keep(t, now))

# Whether no holder holds the layer.
def Lay.free(l: Layer) -> Bool:
  match l:
    case Layer{c, d, p, hs, u}:
      List.is_empty(&2, String, hs)

def Lay.all_free(ls: List<&2, Layer>) -> Bool:
  match ls:
    case Nil{}:
      True{}
    case Con{l, t}:
      Bool.and(Lay.free(l), Lay.all_free(t))

def Lay.gc.path.of(m: Maybe<&2, String>) -> List<&2, String>:
  match m:
    case None{}:
      Nil{}
    case Some{x}:
      [x]

def Lay.gc.path(+root: String, l: Layer) -> List<&2, String>:
  match l:
    case Layer{c, d, p, hs, u}:
      Lay.gc.path.of(Lay.dir(root, c))

# The directories the collector removes at now.
def Lay.gc.paths(+root: String, ls: List<&2, Layer>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{l, t}:
      List.append(&2, String, Lay.gc.path(root, l), Lay.gc.paths(root, t))

# Layer images (v3, docs/ref/layers-sqfs.md)
# -----------------------------------------

# A layer's squashfs image in the store: <root>/layers/<hex>.sqfs.
def Lay.img.v3(root: String, chain: String) -> Maybe<&2, String>:
  Lay.under(Lay.hex(chain), root ++ "/layers/", ".sqfs")

# In a node (v3), the store's share is at /mnt/layers-store and each
# layer it uses is mounted at /mnt/layers/<hex> (Lay.mount), from its
# image or, from an older store, its directory.
def Lay.store.v3() -> String:
  "/mnt/layers-store"

def Lay.store_img.v3(chain: String) -> Maybe<&2, String>:
  Lay.under(Lay.hex(chain), "/mnt/layers-store/", ".sqfs")

def Lay.store_dir.v3(chain: String) -> Maybe<&2, String>:
  Lay.under(Lay.hex(chain), "/mnt/layers-store/", "")

# busybox's argv to mount a layer at Lay.mount: its image (a loop device,
# read-only, nosuid) or, from an older store, a bind of its directory.
def Lay.mount_img.v3(+chain: String) -> List<&2, String>:
  ["mount", "-t", "squashfs", "-o", "loop,ro,nosuid", Maybe.default(&2, String, Lay.store_img.v3(chain), ""),
    Maybe.default(&2, String, Lay.mount(chain), "")]

def Lay.mount_dir.v3(+chain: String) -> List<&2, String>:
  ["mount", "-o", "bind", Maybe.default(&2, String, Lay.store_dir.v3(chain), ""), Maybe.default(&2, String, Lay.mount(chain), "")]


# Warm (v6): a small layer image just mounted, read once
# ------------------------------------------------------
#
# A node reads a layer image through its loop device from the store's 9p
# share, and nothing of it is in the node's page cache until a container
# reads it: the first exec from a fresh mount waits for its program and
# libraries (measured on a Mac VM node: 9 to 30 ms per MiB through the
# share; busybox's `sh -c 'echo ..'` 10 to 36 ms after the mount, 0.5 ms
# once read), and the kubelet reports the container Running before it
# has run. So the node's snapshotter reads a small layer it has just
# mounted before it answers the Prepare (src/layers/pb.bend Spb.warm.v6
# says which).
#
# busybox's argv, no shell: tar reads every regular file of the mounted
# layer (hard links once) through squashfs, whose page cache an exec
# then maps, and writes the archive to /dev/null (busybox's tar has no
# shortcut for /dev/null, as GNU tar has).
def Lay.warm_args.v6(chain: String) -> List<&2, String>:
  ["tar", "-cf", "/dev/null", "-C", Maybe.default(&2, String, Lay.mount(chain), ""), "."]
