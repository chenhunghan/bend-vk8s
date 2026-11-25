import Base
import ../src/layers/place.bend as PC
import ../src/layers/snap.bend as S
import ../src/layers/store.bend as Y
import ../src/layers/fill.bend as F

# Spec for src/layers/place.bend: where a node keeps the shared layer
# store and its layers' mounts.
#
# Proposed: every law of this file is new (feat/shared-layers-2,
# docs/GOAL.md section 11, the native half). All of it is vk8s's own
# design, not vcluster's behaviour. Sources:
# - the node's own places, /mnt/layers-store and /mnt/layers/<hex>:
#   src/layers/store.bend Lay.store.v3, Lay.store_img.v3 and Lay.mount,
#   and src/layers/fill.bend Fill.rec.mount.v3 (the laws below take
#   their paths from those defs);
# - the mounts containerd is answered with: src/layers/snap.bend
#   Sn.mounts.active and Sn.mounts.view (an overlay's lowerdir option
#   joins its lower directories with ':', mount(8), "Mount options for
#   overlay");
# - a native cluster's places: the host's store, <home>/.vk8s/layers
#   (src/cli/cli.bend Cli.layers_dir), and a directory under the
#   cluster's data dir, which is all that its unit's restart and its
#   delete unmount (src/standalone/native_host.bend
#   NHost.reset_script.v2, NHost.mounts_under).

def layers_place.fx.c() -> String:
  "sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1"

def layers_place.fx.hex() -> String:
  "c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1"

def layers_place.fx.native() -> PC.Place:
  PC.Place{"/home/u/.vk8s/layers", "/var/lib/vk8s/demo/node/layers"}

def layers_place.fx.own() -> PC.Place:
  PC.Place{"/mnt/layers-store", "/mnt/layers"}

def layers_place.fx.root() -> String:
  "/var/lib/vk8s/demo/containerd/io.containerd.snapshotter.v1.bend"

# A snapshotter started without both places is a VM node's or a node
# container's; with both, a native host node's.
law layers_place.of:
  {[PC.Place.of("", ""), PC.Place.of("/home/u/.vk8s/layers", ""), PC.Place.of("", "/var/lib/vk8s/demo/node/layers"),
    PC.Place.of("/home/u/.vk8s/layers", "/var/lib/vk8s/demo/node/layers")] ==
    [layers_place.fx.own(), layers_place.fx.own(), layers_place.fx.own(), layers_place.fx.native()] : List<&2, PC.Place>}
law layers_place.native:
  {[PC.Place.native(layers_place.fx.own()), PC.Place.native(layers_place.fx.native())] == [False{}, True{}] : List<&2, Bool>}

# A native node reads a layer's image and its record in the host's
# store and mounts the layer under its data dir.
law layers_place.path.image:
  {PC.Place.path(layers_place.fx.native(), Maybe.default(&2, String, Y.Lay.store_img.v3(layers_place.fx.c()), "")) ==
    "/home/u/.vk8s/layers/" ++ layers_place.fx.hex() ++ ".sqfs" : String}
law layers_place.path.record:
  {PC.Place.path(layers_place.fx.native(), Maybe.default(&2, String, F.Fill.rec.mount.v3(layers_place.fx.c()), "")) ==
    "/home/u/.vk8s/layers/" ++ layers_place.fx.hex() ++ ".rec" : String}
law layers_place.path.old_dir:
  {PC.Place.path(layers_place.fx.native(), Maybe.default(&2, String, Y.Lay.store_dir.v3(layers_place.fx.c()), "")) ==
    "/home/u/.vk8s/layers/" ++ layers_place.fx.hex() : String}
law layers_place.path.mount:
  {PC.Place.path(layers_place.fx.native(), Maybe.default(&2, String, Y.Lay.mount(layers_place.fx.c()), "")) ==
    "/var/lib/vk8s/demo/node/layers/" ++ layers_place.fx.hex() : String}
law layers_place.path.places:
  {[PC.Place.path(layers_place.fx.native(), "/mnt/layers-store"), PC.Place.path(layers_place.fx.native(), "/mnt/layers")] ==
    ["/home/u/.vk8s/layers", "/var/lib/vk8s/demo/node/layers"] : List<&2, String>}
# Any other path stays: a snapshot's own directories, a name that only
# starts like a place, the empty path.
law layers_place.path.other:
  {[PC.Place.path(layers_place.fx.native(), layers_place.fx.root() ++ "/snapshots/7/fs"),
    PC.Place.path(layers_place.fx.native(), "/mnt/layers-stores/a"),
    PC.Place.path(layers_place.fx.native(), "/mnt/layersx/a"),
    PC.Place.path(layers_place.fx.native(), "/mnt"),
    PC.Place.path(layers_place.fx.native(), "")] ==
    [layers_place.fx.root() ++ "/snapshots/7/fs", "/mnt/layers-stores/a", "/mnt/layersx/a", "/mnt", ""] : List<&2, String>}
# A node on its own places has every path as it was.
law layers_place.path.own:
  {[PC.Place.path(layers_place.fx.own(), "/mnt/layers-store/" ++ layers_place.fx.hex() ++ ".sqfs"),
    PC.Place.path(layers_place.fx.own(), "/mnt/layers/" ++ layers_place.fx.hex()),
    PC.Place.path(layers_place.fx.own(), "/mnt/layers"),
    PC.Place.path(layers_place.fx.own(), layers_place.fx.root() ++ "/snapshots/7/fs")] ==
    ["/mnt/layers-store/" ++ layers_place.fx.hex() ++ ".sqfs", "/mnt/layers/" ++ layers_place.fx.hex(), "/mnt/layers",
     layers_place.fx.root() ++ "/snapshots/7/fs"] : List<&2, String>}

# What containerd mounts for a container on a native node: the overlay's
# lower directories that are shared layers are the node's mounts of
# them; a lower directory of the node's own, the upper and the work
# directory stay.
law layers_place.res.active:
  {PC.Place.res(layers_place.fx.native(), S.RMounts{[S.Mount{"overlay", "overlay",
      ["workdir=" ++ layers_place.fx.root() ++ "/snapshots/9/work", "upperdir=" ++ layers_place.fx.root() ++ "/snapshots/9/fs",
       "lowerdir=" ++ layers_place.fx.root() ++ "/snapshots/8/fs:/mnt/layers/bb:/mnt/layers/aa", "index=off"]}]}) ==
    S.RMounts{[S.Mount{"overlay", "overlay",
      ["workdir=" ++ layers_place.fx.root() ++ "/snapshots/9/work", "upperdir=" ++ layers_place.fx.root() ++ "/snapshots/9/fs",
       "lowerdir=" ++ layers_place.fx.root() ++ "/snapshots/8/fs:/var/lib/vk8s/demo/node/layers/bb:/var/lib/vk8s/demo/node/layers/aa",
       "index=off"]}]} : S.Res}
# A view of one shared layer is a bind of its mount.
law layers_place.res.view:
  {PC.Place.res(layers_place.fx.native(), S.RMounts{[S.Mount{"bind", "/mnt/layers/aa", ["ro", "rbind"]}]}) ==
    S.RMounts{[S.Mount{"bind", "/var/lib/vk8s/demo/node/layers/aa", ["ro", "rbind"]}]} : S.Res}
# A layer with no record is measured where the node mounted it.
law layers_place.res.measure:
  {PC.Place.res(layers_place.fx.native(), S.RMeasure{"/mnt/layers/aa"}) == S.RMeasure{"/var/lib/vk8s/demo/node/layers/aa"} : S.Res}
# The answers that name no path are the same on every node.
law layers_place.res.ok:
  for +p: PC.Place
  {PC.Place.res(p, S.ROk{}) == S.ROk{} : S.Res}
law layers_place.res.err:
  for +p: PC.Place
  for e: S.Err
  {PC.Place.res(p, S.RErr{e}) == S.RErr{e} : S.Res}
law layers_place.res.zero:
  for +p: PC.Place
  {PC.Place.res(p, S.RZero{}) == S.RZero{} : S.Res}
# A node on its own places answers the mounts as the snapshotter
# decided them.
law layers_place.res.own:
  {PC.Place.res(layers_place.fx.own(), S.RMounts{[S.Mount{"overlay", "overlay",
      ["lowerdir=/mnt/layers/bb:/mnt/layers/aa", "index=off"]}]}) ==
    S.RMounts{[S.Mount{"overlay", "overlay", ["lowerdir=/mnt/layers/bb:/mnt/layers/aa", "index=off"]}]} : S.Res}
