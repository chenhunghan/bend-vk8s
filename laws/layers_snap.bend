import Base
import ../src/layers/snap.bend as S

# Spec for src/layers/snap.bend: a node's snapshotter over the shared
# layer store, with containerd's snapshots API semantics. Concrete laws
# transcribe containerd's overlay snapshotter tests
# (plugins/snapshots/overlay/overlay_test.go: testOverlayMounts,
# testOverlayCommit, testOverlayOverlayMount, testOverlayView) and its
# snapshotter test suite (core/snapshots/testsuite/testsuite.go), with
# the errdefs that core/snapshots/storage/bolt.go answers. Mount options
# end with index=off, as overlay.go adds where the kernel supports it.
# Shared layers follow the remote snapshot protocol of
# core/snapshots/snapshotter.go (LabelSnapshotRef: the target committed,
# ErrAlreadyExists), with lower directories under /mnt/layers (user
# decision 2026-11-17). Chain IDs are those of laws/layers_store.bend.

def layers_snap.fx.run(have: List<&2, String>, ops: List<&2, S.Op>) -> S.Out:
  S.Sn.run(S.Sn.new("/r", "n1"), ops, have, 100)

# The answer to the last call.
def layers_snap.fx.res(ops: List<&2, S.Op>) -> S.Res:
  S.Out.res(layers_snap.fx.run([], ops))

def layers_snap.fx.hres(have: List<&2, String>, ops: List<&2, S.Op>) -> S.Res:
  S.Out.res(layers_snap.fx.run(have, ops))

def layers_snap.fx.hacts(have: List<&2, String>, ops: List<&2, S.Op>) -> List<&2, S.Act>:
  S.Out.acts(layers_snap.fx.run(have, ops))

def layers_snap.fx.ref(chain: String) -> List<&2, S.Label>:
  [S.Label{"containerd.io/snapshot.ref", chain}]

# The setup of testOverlayCommit: base committed, active-parent active.
def layers_snap.fx.commit_setup() -> List<&2, S.Op>:
  [S.OPrepare{"/tmp/test", "", []}, S.OCommit{"base", "/tmp/test", "", []}, S.OPrepare{"active-parent", "", []}]

def layers_snap.fx.rebase(old: String, new: String) -> S.Res:
  layers_snap.fx.res(List.append(&2, S.Op, layers_snap.fx.commit_setup(), [S.OPrepare{"/tmp/test-x", old, []}, S.OCommit{"test-x", "/tmp/test-x", new, []}]))

# The setup of testOverlayView: base, and top on it, both committed.
def layers_snap.fx.view_setup() -> List<&2, S.Op>:
  [S.OPrepare{"/tmp/base", "", []}, S.OCommit{"base", "/tmp/base", "", []}, S.OPrepare{"/tmp/top", "base", []}, S.OCommit{"top", "/tmp/top", "", []}]

# Mounts (overlay_test.go)
# ------------------------

# testOverlayMounts: no parent, a bind mount of <root>/snapshots/1/fs, rw.
law layers_snap.mounts_no_parent:
  {layers_snap.fx.res([S.OPrepare{"/tmp/test", "", []}]) == S.RMounts{[S.Mount{"bind", "/r/snapshots/1/fs", ["rw", "rbind"]}]} : S.Res}

# testOverlayOverlayMount: overlay, source "overlay", workdir, upperdir,
# lowerdir, then the snapshotter's options.
law layers_snap.mounts_overlay:
  {layers_snap.fx.res([S.OPrepare{"/tmp/test", "", []}, S.OCommit{"base", "/tmp/test", "", []}, S.OPrepare{"/tmp/layer2", "base", []}])
    == S.RMounts{[S.Mount{"overlay", "overlay", ["workdir=/r/snapshots/2/work", "upperdir=/r/snapshots/2/fs", "lowerdir=/r/snapshots/1/fs", "index=off"]}]} : S.Res}

# testOverlayView: a view of one parent is a read-only bind of it.
law layers_snap.view_one_parent:
  {layers_snap.fx.res(List.append(&2, S.Op, layers_snap.fx.view_setup(), [S.OView{"/tmp/view1", "base", []}]))
    == S.RMounts{[S.Mount{"bind", "/r/snapshots/1/fs", ["ro", "rbind"]}]} : S.Res}

# testOverlayView: a view of two is overlay with lowerdir, nearest first.
law layers_snap.view_two_parents:
  {layers_snap.fx.res(List.append(&2, S.Op, layers_snap.fx.view_setup(), [S.OView{"/tmp/view2", "top", []}]))
    == S.RMounts{[S.Mount{"overlay", "overlay", ["lowerdir=/r/snapshots/2/fs:/r/snapshots/1/fs", "index=off"]}]} : S.Res}

# overlay.go mounts(): a view without a parent binds its own fs, ro.
law layers_snap.view_no_parent:
  {layers_snap.fx.res([S.OView{"v", "", []}]) == S.RMounts{[S.Mount{"bind", "/r/snapshots/1/fs", ["ro", "rbind"]}]} : S.Res}

# Mounts can recover the mounts of an active snapshot.
law layers_snap.mounts_again:
  {layers_snap.fx.res([S.OPrepare{"/tmp/test", "", []}, S.OMounts{"/tmp/test"}]) == S.RMounts{[S.Mount{"bind", "/r/snapshots/1/fs", ["rw", "rbind"]}]} : S.Res}

# GetSnapshot: a committed snapshot has no mounts (ErrFailedPrecondition).
law layers_snap.mounts_committed:
  {layers_snap.fx.res([S.OPrepare{"a", "", []}, S.OCommit{"c", "a", "", []}, S.OMounts{"c"}]) == S.RErr{S.EPrecond{}} : S.Res}

law layers_snap.mounts_missing:
  {layers_snap.fx.res([S.OMounts{"nope"}]) == S.RErr{S.ENotFound{}} : S.Res}

# Prepare creates the active snapshot's fs and work directories.
law layers_snap.prepare_dirs:
  {layers_snap.fx.hacts([], [S.OPrepare{"/tmp/test", "", []}]) == [S.AMkdir{"/r/snapshots/1/fs"}, S.AMkdir{"/r/snapshots/1/work"}] : List<&2, S.Act>}

# Commit and rebase (testOverlayCommit)
# -------------------------------------

law layers_snap.commit_no_parent:
  {layers_snap.fx.rebase("", "") == S.ROk{} : S.Res}

law layers_snap.commit_rebase_onto_base:
  {layers_snap.fx.rebase("", "base") == S.ROk{} : S.Res}

law layers_snap.commit_same_parent:
  {layers_snap.fx.rebase("base", "base") == S.ROk{} : S.Res}

law layers_snap.commit_keeps_parent:
  {layers_snap.fx.rebase("base", "") == S.ROk{} : S.Res}

# CommitActive: "cannot change parent of active snapshot" (ErrInvalidArgument).
law layers_snap.commit_other_parent:
  {layers_snap.fx.rebase("base", "new") == S.RErr{S.EInvalid{}} : S.Res}

# CommitActive: "parent is not committed" (ErrFailedPrecondition).
law layers_snap.commit_active_parent:
  {layers_snap.fx.rebase("", "active-parent") == S.RErr{S.EPrecond{}} : S.Res}

# A rebased snapshot's parent is the one given at commit.
law layers_snap.commit_rebased_parent:
  {layers_snap.fx.res(List.append(&2, S.Op, layers_snap.fx.commit_setup(), [S.OPrepare{"/tmp/test-1", "", []}, S.OCommit{"test-1", "/tmp/test-1", "base", []}, S.OStat{"test-1"}]))
    == S.RInfo{S.Info{S.KCommitted{}, "test-1", "base", [], 100, 100}} : S.Res}

# Commit: GetInfo first (ErrNotFound), then the name (ErrAlreadyExists),
# then the kind (a view is not active: ErrFailedPrecondition).
law layers_snap.commit_missing:
  {layers_snap.fx.res([S.OCommit{"c", "nope", "", []}]) == S.RErr{S.ENotFound{}} : S.Res}

law layers_snap.commit_name_taken:
  {layers_snap.fx.res([S.OPrepare{"a", "", []}, S.OCommit{"c", "a", "", []}, S.OPrepare{"b", "", []}, S.OCommit{"c", "b", "", []}]) == S.RErr{S.EExists{}} : S.Res}

law layers_snap.commit_view:
  {layers_snap.fx.res([S.OView{"v", "", []}, S.OCommit{"c", "v", "", []}]) == S.RErr{S.EPrecond{}} : S.Res}

# Stat (testsuite.go)
# -------------------

# checkSnapshotterStatActive.
law layers_snap.stat_active:
  {layers_snap.fx.res([S.OPrepare{"preparing", "", []}, S.OStat{"preparing"}]) == S.RInfo{S.Info{S.KActive{}, "preparing", "", [], 100, 100}} : S.Res}

# checkSnapshotterStatCommitted.
law layers_snap.stat_committed:
  {layers_snap.fx.res([S.OPrepare{"preparing", "", []}, S.OCommit{"committed", "preparing", "", []}, S.OStat{"committed"}]) == S.RInfo{S.Info{S.KCommitted{}, "committed", "", [], 100, 100}} : S.Res}

# checkSnapshotterTransitivity: snapB's parent is snapA.
law layers_snap.stat_transitivity:
  {layers_snap.fx.res([S.OPrepare{"preparing", "", []}, S.OCommit{"snapA", "preparing", "", []}, S.OPrepare{"next", "snapA", []}, S.OCommit{"snapB", "next", "", []}, S.OStat{"snapB"}])
    == S.RInfo{S.Info{S.KCommitted{}, "snapB", "snapA", [], 100, 100}} : S.Res}

law layers_snap.stat_missing:
  {layers_snap.fx.res([S.OStat{"nope"}]) == S.RErr{S.ENotFound{}} : S.Res}

# Prepare and View (testsuite.go checkSnapshotterPrepareView)
# ------------------------------------------------------------

law layers_snap.prepare_then_view_same_key:
  {layers_snap.fx.res([S.OPrepare{"p", "", []}, S.OCommit{"snapA", "p", "", []}, S.OPrepare{"newlayer", "snapA", []}, S.OView{"newlayer", "snapA", []}]) == S.RErr{S.EExists{}} : S.Res}

law layers_snap.prepare_twice:
  {layers_snap.fx.res([S.OPrepare{"p", "", []}, S.OCommit{"snapA", "p", "", []}, S.OPrepare{"prepLayer", "snapA", []}, S.OPrepare{"prepLayer", "snapA", []}]) == S.RErr{S.EExists{}} : S.Res}

law layers_snap.view_twice:
  {layers_snap.fx.res([S.OPrepare{"p", "", []}, S.OCommit{"snapA", "p", "", []}, S.OView{"viewLayer", "snapA", []}, S.OView{"viewLayer", "snapA", []}]) == S.RErr{S.EExists{}} : S.Res}

# CreateSnapshot: a missing parent is ErrNotFound, one that is not
# committed ErrInvalidArgument.
law layers_snap.prepare_missing_parent:
  {layers_snap.fx.res([S.OPrepare{"a", "nope", []}]) == S.RErr{S.ENotFound{}} : S.Res}

law layers_snap.prepare_active_parent:
  {layers_snap.fx.res([S.OPrepare{"a", "", []}, S.OPrepare{"b", "a", []}]) == S.RErr{S.EInvalid{}} : S.Res}

# Update (testsuite.go checkUpdate)
# ---------------------------------

law layers_snap.update_labels:
  {layers_snap.fx.res([S.OPrepare{"a1", "", []}, S.OUpdate{"a1", [S.Label{"l1", "v1"}, S.Label{"l2", "v2"}, S.Label{"l3", "v3"}], []}])
    == S.RInfo{S.Info{S.KActive{}, "a1", "", [S.Label{"l1", "v1"}, S.Label{"l2", "v2"}, S.Label{"l3", "v3"}], 100, 100}} : S.Res}

# "labels.l1" and "labels.l2": l1 updated, l2 gone (it is not in the
# update), l3 kept, l4 not taken.
law layers_snap.update_label_paths:
  {layers_snap.fx.res([S.OPrepare{"a1", "", []}, S.OUpdate{"a1", [S.Label{"l1", "v1"}, S.Label{"l2", "v2"}, S.Label{"l3", "v3"}], []},
      S.OUpdate{"a1", [S.Label{"l1", "updated"}, S.Label{"l4", "v4"}], ["labels.l1", "labels.l2"]}])
    == S.RInfo{S.Info{S.KActive{}, "a1", "", [S.Label{"l1", "updated"}, S.Label{"l3", "v3"}], 100, 100}} : S.Res}

law layers_snap.update_all_labels:
  {layers_snap.fx.res([S.OPrepare{"a1", "", []}, S.OUpdate{"a1", [S.Label{"l1", "v1"}], []}, S.OUpdate{"a1", [S.Label{"l4", "v4"}], ["labels"]}])
    == S.RInfo{S.Info{S.KActive{}, "a1", "", [S.Label{"l4", "v4"}], 100, 100}} : S.Res}

# An immutable field path is ErrInvalidArgument.
law layers_snap.update_parent_refused:
  {layers_snap.fx.res([S.OPrepare{"a1", "", []}, S.OUpdate{"a1", [], ["parent"]}]) == S.RErr{S.EInvalid{}} : S.Res}

# Remove (storage/bolt.go Remove)
# -------------------------------

law layers_snap.remove_with_child:
  {layers_snap.fx.res([S.OPrepare{"a", "", []}, S.OCommit{"c", "a", "", []}, S.OPrepare{"b", "c", []}, S.ORemove{"c"}]) == S.RErr{S.EPrecond{}} : S.Res}

law layers_snap.remove_missing:
  {layers_snap.fx.res([S.ORemove{"nope"}]) == S.RErr{S.ENotFound{}} : S.Res}

law layers_snap.remove_dir:
  {layers_snap.fx.hacts([], [S.OPrepare{"a", "", []}, S.ORemove{"a"}]) == [S.ARemove{"/r/snapshots/1"}] : List<&2, S.Act>}

law layers_snap.removed_is_gone:
  {layers_snap.fx.res([S.OPrepare{"a", "", []}, S.ORemove{"a"}, S.OStat{"a"}]) == S.RErr{S.ENotFound{}} : S.Res}

# Usage, List, Cleanup
# --------------------

law layers_snap.usage_active:
  {layers_snap.fx.res([S.OPrepare{"a", "", []}, S.OUsage{"a"}]) == S.RMeasure{"/r/snapshots/1/fs"} : S.Res}

law layers_snap.usage_view:
  {layers_snap.fx.res([S.OView{"v", "", []}, S.OUsage{"v"}]) == S.RZero{} : S.Res}

# checkWalk: every snapshot, in key order.
law layers_snap.list_sorted:
  {layers_snap.fx.res([S.OPrepare{"b", "", []}, S.OPrepare{"a", "", []}, S.OList{}])
    == S.RList{[S.Info{S.KActive{}, "a", "", [], 100, 100}, S.Info{S.KActive{}, "b", "", [], 100, 100}]} : S.Res}

# getCleanupDirectories: the directories no snapshot's id names.
law layers_snap.cleanup:
  {layers_snap.fx.res([S.OPrepare{"a", "", []}, S.OCleanup{["1", "2", "7"]}]) == S.RDirs{["/r/snapshots/2", "/r/snapshots/7"]} : S.Res}

# Shared layers (LabelSnapshotRef, user decision 2026-11-17)
# -----------------------------------------------------------

# The store has the layer: the target is committed, the layer held, and
# the answer is ErrAlreadyExists, so containerd does not unpack it.
law layers_snap.remote_layer:
  {layers_snap.fx.hres(["sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"], [S.OPrepare{"extract-1 sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", layers_snap.fx.ref("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")}]) == S.RErr{S.EExists{}} : S.Res}

law layers_snap.remote_layer_held:
  {layers_snap.fx.hacts(["sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"], [S.OPrepare{"extract-1 sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", layers_snap.fx.ref("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")}]) == [S.AAcquire{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "n1/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}] : List<&2, S.Act>}

law layers_snap.remote_layer_committed:
  {layers_snap.fx.hres(["sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"], [S.OPrepare{"extract-1 sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", layers_snap.fx.ref("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")}, S.OStat{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}])
    == S.RInfo{S.Info{S.KCommitted{}, "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", layers_snap.fx.ref("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"), 100, 100}} : S.Res}

# The extraction key itself is not created.
law layers_snap.remote_key_not_created:
  {layers_snap.fx.hres(["sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"], [S.OPrepare{"extract-1 sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", layers_snap.fx.ref("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")}, S.OStat{"extract-1 sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}]) == S.RErr{S.ENotFound{}} : S.Res}

# A container on two shared layers: lowerdir from /mnt/layers, nearest
# first; upperdir and workdir on the node disk.
law layers_snap.container_on_shared_layers:
  {layers_snap.fx.hres(["sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6"], [
      S.OPrepare{"extract-1 sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", layers_snap.fx.ref("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")},
      S.OPrepare{"extract-2 sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", layers_snap.fx.ref("sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6")},
      S.OPrepare{"ctr", "sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", []}])
    == S.RMounts{[S.Mount{"overlay", "overlay", ["workdir=/r/snapshots/3/work", "upperdir=/r/snapshots/3/fs", "lowerdir=/mnt/layers/a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6:/mnt/layers/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "index=off"]}]} : S.Res}

# A view of one shared layer binds it read-only.
law layers_snap.view_shared_layer:
  {layers_snap.fx.hres(["sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"], [S.OPrepare{"extract-1 sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", layers_snap.fx.ref("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")}, S.OView{"v", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", []}])
    == S.RMounts{[S.Mount{"bind", "/mnt/layers/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", ["ro", "rbind"]}]} : S.Res}

# A layer the store does not have is unpacked as usual.
law layers_snap.remote_layer_missing:
  {layers_snap.fx.hres([], [S.OPrepare{"extract-1 sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", layers_snap.fx.ref("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")}]) == S.RMounts{[S.Mount{"bind", "/r/snapshots/1/fs", ["rw", "rbind"]}]} : S.Res}

# A target already there: ErrAlreadyExists, and nothing is held again.
law layers_snap.remote_layer_again:
  {layers_snap.fx.hacts(["sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"], [S.OPrepare{"extract-1 sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", layers_snap.fx.ref("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")}, S.OPrepare{"extract-2 sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", layers_snap.fx.ref("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")}]) == [] : List<&2, S.Act>}

# Removing the layer's snapshot lets the layer go; no node directory.
law layers_snap.remote_layer_released:
  {layers_snap.fx.hacts(["sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"], [S.OPrepare{"extract-1 sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", layers_snap.fx.ref("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")}, S.ORemove{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}]) == [S.ARelease{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "n1/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}] : List<&2, S.Act>}

# A shared layer under a container cannot be removed.
law layers_snap.remote_layer_in_use:
  {layers_snap.fx.hres(["sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"], [S.OPrepare{"extract-1 sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", layers_snap.fx.ref("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")}, S.OPrepare{"ctr", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", []}, S.ORemove{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}]) == S.RErr{S.EPrecond{}} : S.Res}

law layers_snap.usage_shared_layer:
  {layers_snap.fx.hres(["sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"], [S.OPrepare{"extract-1 sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", layers_snap.fx.ref("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")}, S.OUsage{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}]) == S.RMeasure{"/mnt/layers/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"} : S.Res}
