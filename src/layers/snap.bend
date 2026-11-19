import Base
import ../oci/size.bend as N
import ./store.bend as Y
import ./filters.bend as F

# The snapshotter of a node, as containerd's snapshots API describes it
# (core/snapshots/snapshotter.go) and its overlay snapshotter implements
# it (plugins/snapshots/overlay/overlay.go, core/snapshots/storage/
# bolt.go), with the shared layer store (src/layers/store.bend) under
# it. Pure: the state is a value; each call answers a result and the
# effects the host runs (directories, layer references). The gRPC server
# and the IO are the host's.
#
# Snapshots are keyed by name; active and view snapshots by their key,
# committed ones by their name, in one key space. A snapshot's id numbers
# it on the node disk (<root>/snapshots/<id>, from 1); a commit keeps the
# active snapshot's id, as CommitActive does.
#
# Shared layers (the remote snapshot protocol of containerd's unpacker,
# LabelSnapshotRef): Prepare with the label containerd.io/snapshot.ref
# naming a chain ID the store has creates the committed snapshot of that
# name, standing for the layer (its files are /mnt/layers/<hex>, not on
# the node disk), takes a reference on the layer, and answers
# ErrAlreadyExists, so containerd skips fetching and unpacking it.
# Removing that snapshot lets the reference go.
#
# Mounts, as overlay.go's mounts(): no parent, a bind mount of the
# snapshot's own fs directory (rw, or ro for a view); an active snapshot
# with parents, overlay with workdir and upperdir on the node disk and
# lowerdir the parents' directories, nearest first; a view of one parent,
# a read-only bind of it; of more, overlay with only lowerdir. A
# committed snapshot's directory is /mnt/layers/<hex> when it stands for
# a shared layer, else <root>/snapshots/<id>/fs. The overlay options end
# with index=off (overlay.go adds it where the kernel has the option;
# the node kernel has it).
#
# Usage: an active snapshot's is measured on its fs directory (the host
# measures it); a committed one's is measured on its directory too (the
# same bytes overlay.go measures at commit and stores); a view's is zero.
# Sn.apply.v2 answers a committed snapshot that stands for a shared
# layer from the size its fill recorded (RUsage, from the layer's record
# in the store, src/layers/fill.bend Fill.rec.parse.v2), so Usage never
# walks the layer over the share; only a layer with no recorded size (a
# store an older vk8s filled) is measured.
#
# List (OList) answers every snapshot; OWalk applies a ListSnapshots
# request's filters as containerd's snapshots do (storage.WalkInfo:
# filters.ParseAll and adaptSnapshot, src/layers/filters.bend): fields
# kind ("active", "view", "committed"), name, parent and labels.<key>.
# Labels are a set by key: a label set to "" is removed (containerd's
# writeMap), and lists keep them in key order.

type SKind is Data:
  KActive{}
  KView{}
  KCommitted{}

type Label is Data:
  Label{key: String, value: String}

# One snapshot. layer: the chain ID of the shared layer a committed
# snapshot stands for, "" when its files are on the node disk.
type Snap is Data:
  Snap{key: String, id: U32, kd: SKind, parent: String, layer: String, labels: List<&2, Label>, created: U32, updated: U32}

# The snapshotter: its root on the node disk, the node's name (in layer
# holders), the next id, the snapshots in the order they were made.
type Sn is Data:
  Sn{root: String, node: String, next: U32, snaps: List<&2, Snap>}

# What Stat, Update and List answer of a snapshot.
type Info is Data:
  Info{kd: SKind, name: String, parent: String, labels: List<&2, Label>, created: U32, updated: U32}

type Mount is Data:
  Mount{fstype: String, source: String, options: List<&2, String>}

# containerd's errdefs.
type Err is Data:
  ENotFound{}
  EExists{}
  EPrecond{}
  EInvalid{}

type Res is Data:
  RMounts{mounts: List<&2, Mount>}
  RInfo{info: Info}
  RList{infos: List<&2, Info>}
  # measure the disk usage of path (bytes and inodes)
  RMeasure{path: String}
  # the usage, known: bytes and inodes
  RUsage{size: N.Size, inodes: U32}
  RZero{}
  RDirs{dirs: List<&2, String>}
  ROk{}
  RErr{err: Err}

# What the host does after a call.
type Act is Data:
  AMkdir{path: String}
  ARemove{path: String}
  AAcquire{chain: String, holder: String}
  ARelease{chain: String, holder: String}

# The usage a fill recorded for the shared layer chain: bytes, inodes.
type LUse is Data:
  LUse{chain: String, size: N.Size, inodes: U32}

type Out is Data:
  Out{sn: Sn, res: Res, acts: List<&2, Act>}

def Out.sn(o: Out) -> Sn:
  match o:
    case Out{s, r, a}:
      s

def Out.res(o: Out) -> Res:
  match o:
    case Out{s, r, a}:
      r

def Out.acts(o: Out) -> List<&2, Act>:
  match o:
    case Out{s, r, a}:
      a

# A fresh snapshotter.
def Sn.new(root: String, node: String) -> Sn:
  Sn{root, node, 1, Nil{}}

def Sn.snaps(sn: Sn) -> List<&2, Snap>:
  match sn:
    case Sn{r, n, x, ss}:
      ss

def Sn.root(sn: Sn) -> String:
  match sn:
    case Sn{r, n, x, ss}:
      r

def Snap.key(s: Snap) -> String:
  match s:
    case Snap{k, i, kd, p, l, ls, c, u}:
      k

def Snap.id(s: Snap) -> U32:
  match s:
    case Snap{k, i, kd, p, l, ls, c, u}:
      i

def Snap.kind(s: Snap) -> SKind:
  match s:
    case Snap{k, i, kd, p, l, ls, c, u}:
      kd

def Snap.parent(s: Snap) -> String:
  match s:
    case Snap{k, i, kd, p, l, ls, c, u}:
      p

def Snap.labels(s: Snap) -> List<&2, Label>:
  match s:
    case Snap{k, i, kd, p, l, ls, c, u}:
      ls

def Sn.is_active(k: SKind) -> Bool:
  match k:
    case KActive{}:
      True{}
    case _:
      False{}

# Active or view: a snapshot with mounts.
def Sn.is_live(k: SKind) -> Bool:
  match k:
    case KCommitted{}:
      False{}
    case _:
      True{}

def Sn.err(sn: Sn, e: Err) -> Out:
  Out{sn, RErr{e}, Nil{}}

# Labels
# ------

def Sn.lset.new(empty: Bool, k: String, v: String) -> List<&2, Label>:
  match empty:
    case True{}:
      Nil{}
    case False{}:
      [Label{k, v}]

def Sn.lset.at(c: Cmp, l: Label, +t: List<&2, Label>, +k: String, +v: String, rest: List<&2, Label>) -> List<&2, Label>:
  match c:
    case LT{}:
      List.append(&2, Label, Sn.lset.new(String.is_empty(v), k, v), Con{l, t})
    case EQ{}:
      List.append(&2, Label, Sn.lset.new(String.is_empty(v), k, v), t)
    case GT{}:
      Con{l, rest}

# The labels with k set to v (removed when v is ""), in key order.
def Sn.lset(ls: List<&2, Label>, +k: String, +v: String) -> List<&2, Label>:
  match ls:
    case Nil{}:
      Sn.lset.new(String.is_empty(v), k, v)
    case Con{Label{+a, +b}, +t}:
      Sn.lset.at(String.order(k, a), Label{a, b}, t, k, v, Sn.lset(t, k, v))

def Sn.labels.go(xs: List<&2, Label>, acc: List<&2, Label>) -> List<&2, Label>:
  match xs:
    case Nil{}:
      acc
    case Con{Label{k, v}, t}:
      Sn.labels.go(t, Sn.lset(acc, k, v))

# Labels as a set: in key order, the last of a key, none empty.
def Sn.labels(xs: List<&2, Label>) -> List<&2, Label>:
  Sn.labels.go(xs, Nil{})

# A label's value, "" when it is not set.
def Sn.lget(ls: List<&2, Label>, +k: String) -> String:
  match ls:
    case Nil{}:
      ""
    case Con{Label{a, b}, t}:
      Bool.pick(String, String.eq(a, k), b, Sn.lget(t, k))

# Lookups
# -------

def Sn.find(ss: List<&2, Snap>, +key: String) -> Maybe<&2, Snap>:
  match ss:
    case Nil{}:
      None{}
    case Con{+s, t}:
      Bool.pick(Maybe<&2, Snap>, String.eq(Snap.key(s), key), Some{s}, Sn.find(t, key))

def Sn.exists(sn: Sn, +key: String) -> Bool:
  Maybe.is_some(&2, Snap, Sn.find(Sn.snaps(sn), key))

def Sn.has_child(ss: List<&2, Snap>, +key: String) -> Bool:
  match ss:
    case Nil{}:
      False{}
    case Con{s, t}:
      String.eq(Snap.parent(s), key) || Sn.has_child(t, key)

# Bool.pick evaluates both of its arguments: a def that recurses in both
# costs 2^n. These branch with match on a Bool and recurse once.
def Sn.without.at(hit: Bool, +s: Snap, rest: List<&2, Snap>) -> List<&2, Snap>:
  match hit:
    case True{}:
      rest
    case False{}:
      Con{s, rest}

def Sn.without(ss: List<&2, Snap>, +key: String) -> List<&2, Snap>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{+s, t}:
      Sn.without.at(String.eq(Snap.key(s), key), s, Sn.without(t, key))

def Sn.replace(ss: List<&2, Snap>, +key: String, +x: Snap) -> List<&2, Snap>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{+s, t}:
      Con{Bool.pick(Snap, String.eq(Snap.key(s), key), x, s), Sn.replace(t, key, x)}

def Sn.mem(xs: List<&2, String>, +x: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{y, t}:
      String.eq(y, x) || Sn.mem(t, x)

def Sn.find.p(+ss: List<&2, Snap>, +p: String) -> Maybe<&2, Snap>:
  Bool.pick(Maybe<&2, Snap>, String.is_empty(p), None{}, Sn.find(ss, p))

# A snapshot's parents, nearest first.
def Sn.chain(fuel: Nat, +ss: List<&2, Snap>, m: Maybe<&2, Snap>) -> List<&2, Snap>:
  match fuel m:
    case 0n _:
      Nil{}
    case 1n+f None{}:
      Nil{}
    case 1n+f Some{+s}:
      Con{s, Sn.chain(f, ss, Sn.find.p(ss, Snap.parent(s)))}

def Sn.parents(+ss: List<&2, Snap>, s: Snap) -> List<&2, Snap>:
  Sn.chain(List.length(&2, Snap, ss), ss, Sn.find.p(ss, Snap.parent(s)))

# Paths
# -----

def Sn.sdir(+root: String, +id: U32) -> String:
  root ++ "/snapshots/" ++ U32.show(id)

def Sn.upper(+root: String, +id: U32) -> String:
  Sn.sdir(root, id) ++ "/fs"

def Sn.work(+root: String, +id: U32) -> String:
  Sn.sdir(root, id) ++ "/work"

# A committed snapshot's directory, as a lower directory.
def Sn.lower(+root: String, s: Snap) -> String:
  match s:
    case Snap{k, +id, kd, p, +layer, ls, c, u}:
      Bool.pick(String, String.is_empty(layer), Sn.upper(root, id), Maybe.default(&2, String, Y.Lay.mount(layer), ""))

def Sn.lowers(+root: String, ps: List<&2, Snap>) -> List<&2, String>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      Con{Sn.lower(root, s), Sn.lowers(root, t)}

# Mounts
# ------

def Sn.mounts.active(ps: List<&2, String>, +up: String, work: String) -> List<&2, Mount>:
  match ps:
    case Nil{}:
      [Mount{"bind", up, ["rw", "rbind"]}]
    case Con{p, t}:
      [Mount{"overlay", "overlay", ["workdir=" ++ work, "upperdir=" ++ up, "lowerdir=" ++ String.join(Con{p, t}, ":"), "index=off"]}]

def Sn.mounts.view(ps: List<&2, String>, up: String) -> List<&2, Mount>:
  match ps:
    case Nil{}:
      [Mount{"bind", up, ["ro", "rbind"]}]
    case Con{p, Nil{}}:
      [Mount{"bind", p, ["ro", "rbind"]}]
    case Con{p, Con{q, t}}:
      [Mount{"overlay", "overlay", ["lowerdir=" ++ String.join(Con{p, Con{q, t}}, ":"), "index=off"]}]

def Sn.mounts.go(k: SKind, ps: List<&2, String>, up: String, work: String) -> List<&2, Mount>:
  match k:
    case KActive{}:
      Sn.mounts.active(ps, up, work)
    case KView{}:
      Sn.mounts.view(ps, up)
    case KCommitted{}:
      Nil{}

# The mounts of an active or view snapshot s among ss.
def Sn.mounts.of(+root: String, +ss: List<&2, Snap>, +s: Snap) -> List<&2, Mount>:
  Sn.mounts.go(Snap.kind(s), Sn.lowers(root, Sn.parents(ss, s)), Sn.upper(root, Snap.id(s)), Sn.work(root, Snap.id(s)))

def Sn.info(s: Snap) -> Info:
  match s:
    case Snap{k, i, kd, p, l, ls, c, u}:
      Info{kd, k, p, ls, c, u}

# Prepare and View
# ----------------

type Chk is Data:
  COk{}
  CErr{err: Err}

def Sn.committed.or(k: SKind, e: Err) -> Chk:
  match k:
    case KCommitted{}:
      COk{}
    case _:
      CErr{e}

def Sn.parent.of(m: Maybe<&2, Snap>, e: Err) -> Chk:
  match m:
    case None{}:
      CErr{ENotFound{}}
    case Some{s}:
      Sn.committed.or(Snap.kind(s), e)

# A parent must be a committed snapshot; e is the error for one that is
# not (CreateSnapshot: ErrInvalidArgument, CommitActive:
# ErrFailedPrecondition); a missing one is ErrNotFound.
def Sn.parent.ok(+ss: List<&2, Snap>, +p: String, e: Err) -> Chk:
  Bool.pick(Chk, String.is_empty(p), COk{}, Sn.parent.of(Sn.find(ss, p), e))

def Sn.mkdirs(k: SKind, +root: String, +id: U32) -> List<&2, Act>:
  match k:
    case KActive{}:
      [AMkdir{Sn.upper(root, id)}, AMkdir{Sn.work(root, id)}]
    case _:
      [AMkdir{Sn.upper(root, id)}]

def Sn.local(sn: Sn, +kd: SKind, key: String, parent: String, labels: List<&2, Label>, +now: U32) -> Out:
  match sn:
    case Sn{+root, node, +next, snaps}:
      +s : Snap = Snap{key, next, kd, parent, "", Sn.labels(labels), now, now}
      +ss : List<&2, Snap> = List.append(&2, Snap, snaps, [s])
      Out{Sn{root, node, (next + 1 : U32), ss}, RMounts{Sn.mounts.of(root, ss, s)}, Sn.mkdirs(kd, root, next)}

def Sn.remote.add(sn: Sn, +target: String, parent: String, labels: List<&2, Label>, +now: U32) -> Out:
  match sn:
    case Sn{root, +node, +next, snaps}:
      Out{Sn{root, node, (next + 1 : U32), List.append(&2, Snap, snaps, [Snap{target, next, KCommitted{}, parent, target, Sn.labels(labels), now, now}])},
        RErr{EExists{}}, [AAcquire{target, node ++ "/" ++ target}]}

def Sn.remote(b: Bool, +target: String, +sn: Sn, parent: String, labels: List<&2, Label>, now: U32) -> Out:
  match b:
    case True{}:
      Sn.err(sn, EExists{})
    case False{}:
      Sn.remote.add(sn, target, parent, labels, now)

def Sn.create.remote(r: Bool, +target: String, +sn: Sn, kd: SKind, key: String, parent: String, labels: List<&2, Label>, now: U32) -> Out:
  match r:
    case True{}:
      Sn.remote(Sn.exists(sn, target), target, sn, parent, labels, now)
    case False{}:
      Sn.local(sn, kd, key, parent, labels, now)

def Sn.create.key(b: Bool, +sn: Sn, +kd: SKind, key: String, parent: String, +labels: List<&2, Label>, +have: List<&2, String>, now: U32) -> Out:
  match b:
    case True{}:
      Sn.err(sn, EExists{})
    case False{}:
      +target : String = Sn.lget(Sn.labels(labels), "containerd.io/snapshot.ref")
      Sn.create.remote(Sn.is_active(kd) && Sn.mem(have, target) && Maybe.is_some(&2, String, Y.Lay.hex(target)), target, sn, kd, key, parent, labels, now)

def Sn.create.parent(c: Chk, +sn: Sn, kd: SKind, +key: String, parent: String, labels: List<&2, Label>, have: List<&2, String>, now: U32) -> Out:
  match c:
    case CErr{e}:
      Sn.err(sn, e)
    case COk{}:
      Sn.create.key(Sn.exists(sn, key), sn, kd, key, parent, labels, have, now)

# Prepare (kind KActive) or View (KView) of key on parent ("" for none).
def Sn.create(+sn: Sn, kd: SKind, key: String, +parent: String, labels: List<&2, Label>, have: List<&2, String>, now: U32) -> Out:
  Sn.create.parent(Sn.parent.ok(Sn.snaps(sn), parent, EInvalid{}), sn, kd, key, parent, labels, have, now)

# Commit
# ------

# The parent after a commit with parent new ("": none given): an active
# snapshot without one takes it; one with another is refused.
def Sn.rebase(+old: String, +nw: String) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, String.eq(old, nw) || String.is_empty(nw), Some{old},
    Bool.pick(Maybe<&2, String>, String.is_empty(old), Some{nw}, None{}))

def Sn.commit.do(sn: Sn, s: Snap, name: String, +key: String, p: String, labels: List<&2, Label>, +now: U32) -> Out:
  match sn:
    case Sn{root, node, next, snaps}:
      Out{Sn{root, node, next, List.append(&2, Snap, Sn.without(snaps, key), [Snap{name, Snap.id(s), KCommitted{}, p, "", Sn.labels(labels), now, now}])}, ROk{}, Nil{}}

def Sn.commit.parent(c: Chk, +p: String, s: Snap, +sn: Sn, name: String, key: String, labels: List<&2, Label>, now: U32) -> Out:
  match c:
    case CErr{e}:
      Sn.err(sn, e)
    case COk{}:
      Sn.commit.do(sn, s, name, key, p, labels, now)

def Sn.commit.rebase(m: Maybe<&2, String>, s: Snap, +sn: Sn, name: String, key: String, labels: List<&2, Label>, now: U32) -> Out:
  match m:
    case None{}:
      Sn.err(sn, EInvalid{})
    case Some{+p}:
      Sn.commit.parent(Sn.parent.ok(Sn.snaps(sn), p, EPrecond{}), p, s, sn, name, key, labels, now)

def Sn.commit.kind(b: Bool, +s: Snap, +sn: Sn, name: String, key: String, parent: String, labels: List<&2, Label>, now: U32) -> Out:
  match b:
    case False{}:
      Sn.err(sn, EPrecond{})
    case True{}:
      Sn.commit.rebase(Sn.rebase(Snap.parent(s), parent), s, sn, name, key, labels, now)

def Sn.commit.name(b: Bool, +s: Snap, +sn: Sn, name: String, key: String, parent: String, labels: List<&2, Label>, now: U32) -> Out:
  match b:
    case True{}:
      Sn.err(sn, EExists{})
    case False{}:
      Sn.commit.kind(Sn.is_active(Snap.kind(s)), s, sn, name, key, parent, labels, now)

def Sn.commit.key(m: Maybe<&2, Snap>, +sn: Sn, +name: String, key: String, parent: String, labels: List<&2, Label>, now: U32) -> Out:
  match m:
    case None{}:
      Sn.err(sn, ENotFound{})
    case Some{s}:
      Sn.commit.name(Sn.exists(sn, name), s, sn, name, key, parent, labels, now)

# Commit key as name, with parent from WithParent ("" for none) and the
# committed snapshot's labels (they replace the active one's).
def Sn.commit(+sn: Sn, name: String, +key: String, parent: String, labels: List<&2, Label>, now: U32) -> Out:
  Sn.commit.key(Sn.find(Sn.snaps(sn), key), sn, name, key, parent, labels, now)

# Remove
# ------

def Sn.remove.acts(+root: String, +node: String, s: Snap) -> List<&2, Act>:
  match s:
    case Snap{k, id, kd, p, +layer, ls, c, u}:
      Bool.pick(List<&2, Act>, String.is_empty(layer), [ARemove{Sn.sdir(root, id)}], [ARelease{layer, node ++ "/" ++ k}])

def Sn.remove.do(sn: Sn, s: Snap, +key: String) -> Out:
  match sn:
    case Sn{+root, +node, next, snaps}:
      Out{Sn{root, node, next, Sn.without(snaps, key)}, ROk{}, Sn.remove.acts(root, node, s)}

def Sn.remove.child(b: Bool, s: Snap, +sn: Sn, key: String) -> Out:
  match b:
    case True{}:
      Sn.err(sn, EPrecond{})
    case False{}:
      Sn.remove.do(sn, s, key)

def Sn.remove.key(m: Maybe<&2, Snap>, +sn: Sn, +key: String) -> Out:
  match m:
    case None{}:
      Sn.err(sn, ENotFound{})
    case Some{s}:
      Sn.remove.child(Sn.has_child(Sn.snaps(sn), key), s, sn, key)

# Remove a snapshot; one with children is refused.
def Sn.remove(+sn: Sn, +key: String) -> Out:
  Sn.remove.key(Sn.find(Sn.snaps(sn), key), sn, key)

# Mounts, Stat, Usage
# -------------------

def Sn.mounts.kind(b: Bool, +s: Snap, +sn: Sn) -> Out:
  match b:
    case True{}:
      Sn.err(sn, EPrecond{})
    case False{}:
      Out{sn, RMounts{Sn.mounts.of(Sn.root(sn), Sn.snaps(sn), s)}, Nil{}}

def Sn.mounts.key(m: Maybe<&2, Snap>, +sn: Sn) -> Out:
  match m:
    case None{}:
      Sn.err(sn, ENotFound{})
    case Some{+s}:
      Sn.mounts.kind(Bool.not(Sn.is_live(Snap.kind(s))), s, sn)

# The mounts of an active or view snapshot (GetSnapshot refuses a
# committed one).
def Sn.mounts(+sn: Sn, key: String) -> Out:
  Sn.mounts.key(Sn.find(Sn.snaps(sn), key), sn)

def Sn.stat.key(m: Maybe<&2, Snap>, sn: Sn) -> Out:
  match m:
    case None{}:
      Sn.err(sn, ENotFound{})
    case Some{s}:
      Out{sn, RInfo{Sn.info(s)}, Nil{}}

def Sn.stat(+sn: Sn, key: String) -> Out:
  Sn.stat.key(Sn.find(Sn.snaps(sn), key), sn)

def Sn.use.kind(k: SKind, +root: String, +id: U32, +layer: String) -> Res:
  match k:
    case KActive{}:
      RMeasure{Sn.upper(root, id)}
    case KView{}:
      RZero{}
    case KCommitted{}:
      Bool.pick(Res, String.is_empty(layer), RMeasure{Sn.upper(root, id)}, RMeasure{Maybe.default(&2, String, Y.Lay.mount(layer), "")})

def Sn.use(+root: String, s: Snap) -> Res:
  match s:
    case Snap{k, +id, kd, p, +layer, ls, c, u}:
      Sn.use.kind(kd, root, id, layer)

def Sn.usage.key(m: Maybe<&2, Snap>, +sn: Sn) -> Out:
  match m:
    case None{}:
      Sn.err(sn, ENotFound{})
    case Some{s}:
      Out{sn, Sn.use(Sn.root(sn), s), Nil{}}

def Sn.usage(+sn: Sn, key: String) -> Out:
  Sn.usage.key(Sn.find(Sn.snaps(sn), key), sn)

# Update
# ------

# The labels after one fieldpath p: "labels.<key>" sets key from nw,
# "labels" takes nw whole, any other is None.
def Sn.relabel.step(one: Bool, all: Bool, +p: String, cur: List<&2, Label>, +nw: List<&2, Label>) -> Maybe<&2, List<&2, Label>>:
  match one all:
    case True{} _:
      Some{Sn.lset(cur, String.drop(p, 7n), Sn.lget(nw, String.drop(p, 7n)))}
    case False{} True{}:
      Some{nw}
    case False{} False{}:
      None{}

def Sn.relabel.walk(ps: List<&2, String>, m: Maybe<&2, List<&2, Label>>, +nw: List<&2, Label>) -> Maybe<&2, List<&2, Label>>:
  match ps m:
    case Nil{} x:
      x
    case Con{p, t} None{}:
      None{}
    case Con{+p, t} Some{cur}:
      Sn.relabel.walk(t, Sn.relabel.step(String.starts_with(p, "labels."), String.eq(p, "labels"), p, cur, nw), nw)

def Sn.relabel.go(ps: List<&2, String>, +cur: List<&2, Label>, +nw: List<&2, Label>) -> Maybe<&2, List<&2, Label>>:
  Sn.relabel.walk(ps, Some{cur}, nw)

# The labels after an update of fieldpaths ps (none: every mutable
# field, the labels); None for an immutable field.
def Sn.relabel(ps: List<&2, String>, cur: List<&2, Label>, +nw: List<&2, Label>) -> Maybe<&2, List<&2, Label>>:
  match ps:
    case Nil{}:
      Some{nw}
    case Con{p, t}:
      Sn.relabel.go(Con{p, t}, cur, nw)

def Sn.relabeled(s: Snap, ls: List<&2, Label>, now: U32) -> Snap:
  match s:
    case Snap{k, i, kd, p, l, x, c, u}:
      Snap{k, i, kd, p, l, ls, c, now}

def Sn.update.do(sn: Sn, +s: Snap, +name: String) -> Out:
  match sn:
    case Sn{root, node, next, snaps}:
      Out{Sn{root, node, next, Sn.replace(snaps, name, s)}, RInfo{Sn.info(s)}, Nil{}}

def Sn.update.labels(m: Maybe<&2, List<&2, Label>>, s: Snap, +sn: Sn, name: String, now: U32) -> Out:
  match m:
    case None{}:
      Sn.err(sn, EInvalid{})
    case Some{ls}:
      Sn.update.do(sn, Sn.relabeled(s, ls, now), name)

def Sn.update.key(m: Maybe<&2, Snap>, +sn: Sn, name: String, labels: List<&2, Label>, paths: List<&2, String>, now: U32) -> Out:
  match m:
    case None{}:
      Sn.err(sn, ENotFound{})
    case Some{+s}:
      Sn.update.labels(Sn.relabel(paths, Snap.labels(s), Sn.labels(labels)), s, sn, name, now)

# Update the snapshot name's labels from labels, for fieldpaths paths
# ("labels", "labels.<key>"; none: all labels); updated becomes now.
def Sn.update(+sn: Sn, +name: String, labels: List<&2, Label>, paths: List<&2, String>, now: U32) -> Out:
  Sn.update.key(Sn.find(Sn.snaps(sn), name), sn, name, labels, paths, now)

# List and Cleanup
# ----------------

def Sn.insert(+s: Snap, ss: List<&2, Snap>) -> List<&2, Snap>:
  match ss:
    case Nil{}:
      [s]
    case Con{+x, +t}:
      Bool.pick(List<&2, Snap>, String.is_le(Snap.key(s), Snap.key(x)), Con{s, Con{x, t}}, Con{x, Sn.insert(s, t)})

def Sn.sort(ss: List<&2, Snap>) -> List<&2, Snap>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      Sn.insert(s, Sn.sort(t))

def Sn.infos(ss: List<&2, Snap>) -> List<&2, Info>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      Con{Sn.info(s), Sn.infos(t)}

# Every snapshot, in key order (WalkInfo walks bolt's sorted keys).
def Sn.list(+sn: Sn) -> Out:
  Out{sn, RList{Sn.infos(Sn.sort(Sn.snaps(sn)))}, Nil{}}

def Sn.ids(ss: List<&2, Snap>) -> List<&2, String>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      Con{U32.show(Snap.id(s)), Sn.ids(t)}

def Sn.cleanup.at(known: Bool, +d: String, rest: List<&2, String>) -> List<&2, String>:
  match known:
    case True{}:
      rest
    case False{}:
      Con{d, rest}

def Sn.cleanup.go(fs: List<&2, String>, +ids: List<&2, String>, +root: String) -> List<&2, String>:
  match fs:
    case Nil{}:
      Nil{}
    case Con{+f, t}:
      Sn.cleanup.at(Sn.mem(ids, f), root ++ "/snapshots/" ++ f, Sn.cleanup.go(t, ids, root))

def Sn.removes(ds: List<&2, String>) -> List<&2, Act>:
  match ds:
    case Nil{}:
      Nil{}
    case Con{d, t}:
      Con{ARemove{d}, Sn.removes(t)}

def Sn.cleanup.dirs(+sn: Sn, +ds: List<&2, String>) -> Out:
  Out{sn, RDirs{ds}, Sn.removes(ds)}

# Cleanup: of the directories found under <root>/snapshots, the ones no
# snapshot's id names (overlay.go getCleanupDirectories).
def Sn.cleanup(+sn: Sn, found: List<&2, String>) -> Out:
  Sn.cleanup.dirs(sn, Sn.cleanup.go(found, Sn.ids(Sn.snaps(sn)), Sn.root(sn)))

# Usage of shared layers, from their records
# -------------------------------------------

def Sn.use.find(us: List<&2, LUse>, +chain: String) -> Maybe<&2, LUse>:
  match us:
    case Nil{}:
      None{}
    case Con{LUse{+c, s, n}, t}:
      Bool.pick(Maybe<&2, LUse>, String.eq(c, chain), Some{LUse{c, s, n}}, Sn.use.find(t, chain))

def Sn.use.rec(m: Maybe<&2, LUse>, +layer: String) -> Res:
  match m:
    case None{}:
      RMeasure{Maybe.default(&2, String, Y.Lay.mount(layer), "")}
    case Some{LUse{c, s, n}}:
      RUsage{s, n}

def Sn.use.kind.v2(k: SKind, +root: String, +id: U32, +layer: String, us: List<&2, LUse>) -> Res:
  match k:
    case KCommitted{}:
      Bool.pick(Res, String.is_empty(layer), RMeasure{Sn.upper(root, id)}, Sn.use.rec(Sn.use.find(us, layer), layer))
    case kd:
      Sn.use.kind(kd, root, id, layer)

# Usage: as Sn.use, but a shared layer whose size us records (its fill
# recorded it) answers that size; one without is measured.
def Sn.use.v2(+root: String, s: Snap, us: List<&2, LUse>) -> Res:
  match s:
    case Snap{k, +id, kd, p, +layer, ls, c, u}:
      Sn.use.kind.v2(kd, root, id, layer, us)

def Sn.usage.v2.key(m: Maybe<&2, Snap>, +sn: Sn, us: List<&2, LUse>) -> Out:
  match m:
    case None{}:
      Sn.err(sn, ENotFound{})
    case Some{s}:
      Out{sn, Sn.use.v2(Sn.root(sn), s, us), Nil{}}

def Sn.usage.v2(+sn: Sn, key: String, us: List<&2, LUse>) -> Out:
  Sn.usage.v2.key(Sn.find(Sn.snaps(sn), key), sn, us)

# List with filters
# -----------------

def Sn.kind.name(k: SKind) -> String:
  match k:
    case KActive{}:
      "active"
    case KView{}:
      "view"
    case KCommitted{}:
      "committed"

def Sn.label.find(ls: List<&2, Label>, +k: String) -> Maybe<&2, String>:
  match ls:
    case Nil{}:
      None{}
    case Con{Label{a, +b}, t}:
      Bool.pick(Maybe<&2, String>, String.eq(a, k), Some{b}, Sn.label.find(t, k))

# A label by the rest of the field path joined by "."; none at all when
# the snapshot has no label (adaptSnapshot: len(info.Labels) == 0).
def Sn.label.field(ls: List<&2, Label>, +k: String) -> Maybe<&2, String>:
  match ls:
    case Nil{}:
      None{}
    case Con{l, t}:
      Sn.label.find(Con{l, t}, k)

def Sn.field.of(+f: String, rest: List<&2, String>, i: Info) -> Maybe<&2, String>:
  match i:
    case Info{kd, name, parent, ls, c, u}:
      Bool.pick(Maybe<&2, String>, String.eq(f, "kind"), Some{Sn.kind.name(kd)},
        Bool.pick(Maybe<&2, String>, String.eq(f, "name"), Some{name},
          Bool.pick(Maybe<&2, String>, String.eq(f, "parent"), Some{parent},
            Bool.pick(Maybe<&2, String>, String.eq(f, "labels"), Sn.label.field(ls, String.join(rest, ".")), None{}))))

# A snapshot's field at a field path, as adaptSnapshot gives it.
def Sn.field(i: Info, path: List<&2, String>) -> Maybe<&2, String>:
  match path:
    case Nil{}:
      None{}
    case Con{f, rest}:
      Sn.field.of(f, rest, i)

def Sn.all(ss: List<&2, F.Sel>, +i: Info) -> Bool:
  match ss:
    case Nil{}:
      True{}
    case Con{F.Sel{p, op, v}, t}:
      F.Flt.test(op, v, Sn.field(i, p)) && Sn.all(t, i)

def Sn.any(xs: List<&2, List<&2, F.Sel>>, +i: Info) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{a, t}:
      Sn.all(a, i) || Sn.any(t, i)

def Sn.keep.at(hit: Bool, i: Info, rest: List<&2, Info>) -> List<&2, Info>:
  match hit:
    case True{}:
      Con{i, rest}
    case False{}:
      rest

# The infos that the filters xs match, in order.
def Sn.keep(+xs: List<&2, List<&2, F.Sel>>, ys: List<&2, Info>) -> List<&2, Info>:
  match ys:
    case Nil{}:
      Nil{}
    case Con{+i, t}:
      Sn.keep.at(Sn.any(xs, i), i, Sn.keep(xs, t))

def Sn.list.f(m: Maybe<&2, List<&2, List<&2, F.Sel>>>, +sn: Sn) -> Out:
  match m:
    case None{}:
      Sn.err(sn, EInvalid{})
    case Some{xs}:
      Out{sn, RList{Sn.keep(xs, Sn.infos(Sn.sort(Sn.snaps(sn))))}, Nil{}}

# The snapshots the filters fs match, in key order; a filter that does
# not parse is ErrInvalidArgument (filters.ParseAll).
def Sn.list.v2(+sn: Sn, fs: List<&2, String>) -> Out:
  Sn.list.f(F.Flt.parse_all(fs), sn)

# Calls
# -----

type Op is Data:
  OPrepare{key: String, parent: String, labels: List<&2, Label>}
  OView{key: String, parent: String, labels: List<&2, Label>}
  OCommit{name: String, key: String, parent: String, labels: List<&2, Label>}
  ORemove{key: String}
  OMounts{key: String}
  OStat{key: String}
  OUpdate{name: String, labels: List<&2, Label>, paths: List<&2, String>}
  OUsage{key: String}
  OList{}
  OCleanup{found: List<&2, String>}
  # List with a ListSnapshots request's filters
  OWalk{filters: List<&2, String>}

# One call at time now; have are the chain IDs the layer store holds.
def Sn.apply(sn: Sn, op: Op, +have: List<&2, String>, +now: U32) -> Out:
  match op:
    case OPrepare{k, p, ls}:
      Sn.create(sn, KActive{}, k, p, ls, have, now)
    case OView{k, p, ls}:
      Sn.create(sn, KView{}, k, p, ls, have, now)
    case OCommit{n, k, p, ls}:
      Sn.commit(sn, n, k, p, ls, now)
    case ORemove{k}:
      Sn.remove(sn, k)
    case OMounts{k}:
      Sn.mounts(sn, k)
    case OStat{k}:
      Sn.stat(sn, k)
    case OUpdate{n, ls, ps}:
      Sn.update(sn, n, ls, ps, now)
    case OUsage{k}:
      Sn.usage(sn, k)
    case OList{}:
      Sn.list(sn)
    case OCleanup{fs}:
      Sn.cleanup(sn, fs)
    case OWalk{fs}:
      Sn.list.v2(sn, fs)

def Sn.run.go(ops: List<&2, Op>, +have: List<&2, String>, +now: U32, o: Out) -> Out:
  match ops:
    case Nil{}:
      o
    case Con{op, t}:
      Sn.run.go(t, have, now, Sn.apply(Out.sn(o), op, have, now))

# Calls in order: the last one's answer, with the state after them all.
def Sn.run(sn: Sn, ops: List<&2, Op>, +have: List<&2, String>, +now: U32) -> Out:
  Sn.run.go(ops, have, now, Out{sn, ROk{}, Nil{}})

# One call, as Sn.apply, with us the usage recorded for shared layers
# (Usage answers it, Sn.use.v2).
def Sn.apply.v2(sn: Sn, op: Op, +have: List<&2, String>, us: List<&2, LUse>, +now: U32) -> Out:
  match op:
    case OUsage{k}:
      Sn.usage.v2(sn, k, us)
    case o:
      Sn.apply(sn, o, have, now)

def Sn.run.v2.go(ops: List<&2, Op>, +have: List<&2, String>, +us: List<&2, LUse>, +now: U32, o: Out) -> Out:
  match ops:
    case Nil{}:
      o
    case Con{op, t}:
      Sn.run.v2.go(t, have, us, now, Sn.apply.v2(Out.sn(o), op, have, us, now))

# Calls in order, as Sn.run, with the recorded usage us.
def Sn.run.v2(sn: Sn, ops: List<&2, Op>, +have: List<&2, String>, +us: List<&2, LUse>, +now: U32) -> Out:
  Sn.run.v2.go(ops, have, us, now, Out{sn, ROk{}, Nil{}})

# Layer images (v3, docs/ref/layers-sqfs.md)
# -----------------------------------------

def Sn.layers.v3.put(none: Bool, layer: String, rest: List<&2, String>) -> List<&2, String>:
  match none:
    case True{}:
      rest
    case False{}:
      Con{layer, rest}

def Sn.layers.v3.go(ss: List<&2, Snap>) -> List<&2, String>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{Snap{k, i, kd, p, +layer, ls, c, u}, t}:
      Sn.layers.v3.put(String.is_empty(layer), layer, Sn.layers.v3.go(t))

# The shared layers the node's snapshots stand for, in the order they were
# made: a node mounts each at /mnt/layers/<hex> when the snapshotter
# starts (the mounts do not outlive the node's boot).
def Sn.layers.v3(sn: Sn) -> List<&2, String>:
  Sn.layers.v3.go(Sn.snaps(sn))

