import Base
import ./snap.bend as S

# Where a node keeps the shared layer store and its layers' mounts
# (docs/GOAL.md section 11, "Shared assets and layers off the VM", the
# native half). vk8s's own design: nothing here mirrors vcluster.
#
# A VM node and a node container see the store at /mnt/layers-store and
# mount each layer they use at /mnt/layers/<hex> (src/layers/store.bend
# Lay.store.v3, Lay.mount): both are the node's own places, in its own
# mount namespace. A native host node (Linux native mode) runs in the
# host's mount namespace, where those two names are not the cluster's
# to take. It reads the store where the host keeps it
# (<home>/.vk8s/layers) and mounts a layer under its own data dir
# (<data>/node/layers/<hex>): everything a native cluster mounts is
# under its data dir, which is what its unit's restart and its delete
# unmount.
#
# The snapshotter's decisions (src/layers/snap.bend, pb.bend, fill.bend)
# keep naming the node's places; a native node's snapshotter rewrites
# each path where it leaves the pure code: the paths it probes, mounts
# and reads, and the mounts it answers containerd with. Place.path is
# that rewrite. A path is rewritten when it is one of the two places or
# under one; any other path (a snapshot's own directories under the
# snapshotter's root) is left as it is.

type Place is Data:
  Place{store: String, mounts: String}

# The node's own places: a VM node's and a node container's.
def Place.node_store() -> String:
  "/mnt/layers-store"

def Place.node_mounts() -> String:
  "/mnt/layers"

# What follows a place in s: "" for the place itself, "/..." for a path
# under it; None for any other path (a longer name, /mnt/layers-store
# for /mnt/layers, is another path).
def Place.rest.under(sub: Bool, +r: String) -> Maybe<&2, String>:
  match sub:
    case True{}:
      Some{r}
    case False{}:
      None{}

def Place.rest.at(hit: Bool, +s: String, n: Nat) -> Maybe<&2, String>:
  match hit:
    case True{}:
      +r = String.drop(s, n)
      Place.rest.under(String.is_empty(r) || String.starts_with(r, "/"), r)
    case False{}:
      None{}

def Place.rest(+s: String, +place: String) -> Maybe<&2, String>:
  Place.rest.at(String.starts_with(s, place), s, String.length(place))

def Place.path.mounts(m: Maybe<&2, String>, +to: String, +s: String) -> String:
  match m:
    case Some{r}:
      to ++ r
    case None{}:
      s

def Place.path.store(m: Maybe<&2, String>, +p: Place, +s: String) -> String:
  match m p:
    case Some{r} Place{st, mt}:
      st ++ r
    case None{} Place{st, +mt}:
      Place.path.mounts(Place.rest(s, Place.node_mounts()), mt, s)

# One path as the node at p has it.
def Place.path(+p: Place, +s: String) -> String:
  Place.path.store(Place.rest(s, Place.node_store()), p, s)

def Place.paths(+p: Place, xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      Con{Place.path(p, x), Place.paths(p, t)}

# An overlay's lowerdir option names its lower directories, joined by
# ':' (src/layers/snap.bend Sn.mounts.active, Sn.mounts.view): each is
# rewritten. Every other option is left as it is (workdir and upperdir
# are a snapshot's own directories).
def Place.option.go(lower: Bool, +p: Place, +o: String) -> String:
  match lower:
    case True{}:
      "lowerdir=" ++ String.join(Place.paths(p, String.split(String.drop(o, 9n), ':')), ":")
    case False{}:
      o

def Place.option(+p: Place, +o: String) -> String:
  Place.option.go(String.starts_with(o, "lowerdir="), p, o)

def Place.options(+p: Place, os: List<&2, String>) -> List<&2, String>:
  match os:
    case Nil{}:
      Nil{}
    case Con{o, t}:
      Con{Place.option(p, o), Place.options(p, t)}

# A mount containerd is answered with: its source (a view of one shared
# layer is a bind of the layer's mount) and its options.
def Place.mount(+p: Place, m: S.Mount) -> S.Mount:
  match m:
    case S.Mount{fs, src, os}:
      S.Mount{fs, Place.path(p, src), Place.options(p, os)}

def Place.mount_list(+p: Place, ms: List<&2, S.Mount>) -> List<&2, S.Mount>:
  match ms:
    case Nil{}:
      Nil{}
    case Con{m, t}:
      Con{Place.mount(p, m), Place.mount_list(p, t)}

# What a call answered, as the node at p has it: the mounts, and the
# directory a Usage measures (a shared layer an older vk8s filled, which
# has no record). The other answers name no path.
def Place.res(+p: Place, r: S.Res) -> S.Res:
  match r:
    case S.RMounts{ms}:
      S.RMounts{Place.mount_list(p, ms)}
    case S.RMeasure{path}:
      S.RMeasure{Place.path(p, path)}
    case other:
      other

# A node's place from what its snapshotter was started with: both
# given, a native host node's; else the node's own.
def Place.of.go(own: Bool, +store: String, +mounts: String) -> Place:
  match own:
    case True{}:
      Place{Place.node_store(), Place.node_mounts()}
    case False{}:
      Place{store, mounts}

def Place.of(+store: String, +mounts: String) -> Place:
  Place.of.go(String.is_empty(store) || String.is_empty(mounts), store, mounts)

# Whether the node at p runs in the host's mount namespace with places
# of its own choosing (a native host node).
def Place.native(p: Place) -> Bool:
  match p:
    case Place{st, mt}:
      Bool.not(String.eq(st, Place.node_store()) && String.eq(mt, Place.node_mounts()))
