import Base
import ../src/layers/snap.bend as S
import ../src/layers/pb.bend as B

# Spec for src/layers/pb.bend: containerd's snapshots API on the wire for
# the node's proxy snapshotter. Method paths are snapshots.proto's
# service (api/services/snapshots/v1/snapshots.proto, package
# containerd.services.snapshots.v1, service Snapshots). Request and
# response bytes are the encodings of protobufjs 7 loading
# snapshots.proto and types/mount.proto from containerd's api/ (fields
# that hold their default left out, as Go's proto3 marshalling does).
# Status codes are errgrpc's map of errdefs (gRPC NotFound 5,
# AlreadyExists 6, FailedPrecondition 9, InvalidArgument 3). Shared
# layers are /mnt/layers/<hex>/fs in the node (the host store's layout,
# docs/GOAL.md section 10 part 1). Chain IDs are layers_store's.

def layers_pb.fx.chain() -> String:
  "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

def layers_pb.fx.ref() -> List<&2, S.Label>:
  [S.Label{"containerd.io/snapshot.ref", layers_pb.fx.chain()}]

# A node that prepared the shared layer (the unpacker's remote snapshot).
def layers_pb.fx.shared() -> S.Out:
  S.Sn.run(S.Sn.new("/r", "n1"), [S.OPrepare{"extract-1 sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", layers_pb.fx.ref()}], [layers_pb.fx.chain()], 100)

# Methods
# -------

law layers_pb.method_prepare:
  {B.Spb.method("/containerd.services.snapshots.v1.Snapshots/Prepare") == Some{B.SmPrepare{}} : Maybe<&2, B.SpMeth>}

law layers_pb.method_view:
  {B.Spb.method("/containerd.services.snapshots.v1.Snapshots/View") == Some{B.SmView{}} : Maybe<&2, B.SpMeth>}

law layers_pb.method_list:
  {B.Spb.method("/containerd.services.snapshots.v1.Snapshots/List") == Some{B.SmList{}} : Maybe<&2, B.SpMeth>}

law layers_pb.method_cleanup:
  {B.Spb.method("/containerd.services.snapshots.v1.Snapshots/Cleanup") == Some{B.SmCleanup{}} : Maybe<&2, B.SpMeth>}

law layers_pb.method_unknown:
  {B.Spb.method("/containerd.services.snapshots.v1.Snapshots/Walk") == None{} : Maybe<&2, B.SpMeth>}

law layers_pb.method_other_service:
  {B.Spb.method("/containerd.services.content.v1.Content/Info") == None{} : Maybe<&2, B.SpMeth>}

# Requests
# --------

# PrepareSnapshotRequest{snapshotter: "bend", key: "k", parent: "p", labels: {a: "1"}}
law layers_pb.request_prepare:
  {B.Spb.request(B.SmPrepare{}, [10, 4, 98, 101, 110, 100, 18, 1, 107, 26, 1, 112, 34, 6, 10, 1, 97, 18, 1, 49])
    == Done{S.OPrepare{"k", "p", [S.Label{"a", "1"}]}} : Result<&2, &2, String, S.Op>}

# PrepareSnapshotRequest{key: "k", labels: {b: "2", a: "1"}}: labels in
# wire order (the snapshotter keeps them as a set).
law layers_pb.request_prepare_labels:
  {B.Spb.request(B.SmPrepare{}, [18, 1, 107, 34, 6, 10, 1, 98, 18, 1, 50, 34, 6, 10, 1, 97, 18, 1, 49])
    == Done{S.OPrepare{"k", "", [S.Label{"b", "2"}, S.Label{"a", "1"}]}} : Result<&2, &2, String, S.Op>}

# ViewSnapshotRequest{snapshotter: "bend", key: "v", parent: "base"}
law layers_pb.request_view:
  {B.Spb.request(B.SmView{}, [10, 4, 98, 101, 110, 100, 18, 1, 118, 26, 4, 98, 97, 115, 101])
    == Done{S.OView{"v", "base", []}} : Result<&2, &2, String, S.Op>}

# CommitSnapshotRequest{snapshotter: "bend", name: "n", key: "k", labels: {x: "y"}, parent: "base"}
law layers_pb.request_commit:
  {B.Spb.request(B.SmCommit{}, [10, 4, 98, 101, 110, 100, 18, 1, 110, 26, 1, 107, 34, 6, 10, 1, 120, 18, 1, 121, 42, 4, 98, 97, 115, 101])
    == Done{S.OCommit{"n", "k", "base", [S.Label{"x", "y"}]}} : Result<&2, &2, String, S.Op>}

# RemoveSnapshotRequest, MountsRequest, StatSnapshotRequest and
# UsageRequest {snapshotter: "bend", key: "k"} have the same bytes.
law layers_pb.request_remove:
  {B.Spb.request(B.SmRemove{}, [10, 4, 98, 101, 110, 100, 18, 1, 107]) == Done{S.ORemove{"k"}} : Result<&2, &2, String, S.Op>}

law layers_pb.request_mounts:
  {B.Spb.request(B.SmMounts{}, [10, 4, 98, 101, 110, 100, 18, 1, 107]) == Done{S.OMounts{"k"}} : Result<&2, &2, String, S.Op>}

law layers_pb.request_stat:
  {B.Spb.request(B.SmStat{}, [10, 4, 98, 101, 110, 100, 18, 1, 107]) == Done{S.OStat{"k"}} : Result<&2, &2, String, S.Op>}

law layers_pb.request_usage:
  {B.Spb.request(B.SmUsage{}, [10, 4, 98, 101, 110, 100, 18, 1, 107]) == Done{S.OUsage{"k"}} : Result<&2, &2, String, S.Op>}

# ListSnapshotsRequest and CleanupRequest {snapshotter: "bend"}.
law layers_pb.request_list:
  {B.Spb.request(B.SmList{}, [10, 4, 98, 101, 110, 100]) == Done{S.OList{}} : Result<&2, &2, String, S.Op>}

law layers_pb.request_cleanup:
  {B.Spb.request(B.SmCleanup{}, [10, 4, 98, 101, 110, 100]) == Done{S.OCleanup{[]}} : Result<&2, &2, String, S.Op>}

# UpdateSnapshotRequest{snapshotter: "bend", info: {name: "n", labels: {x: "y"}}, update_mask: {paths: ["labels.x"]}}
law layers_pb.request_update:
  {B.Spb.request(B.SmUpdate{}, [10, 4, 98, 101, 110, 100, 18, 11, 10, 1, 110, 50, 6, 10, 1, 120, 18, 1, 121, 26, 10, 10, 8, 108, 97, 98, 101, 108, 115, 46, 120])
    == Done{S.OUpdate{"n", [S.Label{"x", "y"}], ["labels.x"]}} : Result<&2, &2, String, S.Op>}

# A key of 5 bytes cut after 1: InvalidArgument.
law layers_pb.request_bad:
  {B.Spb.is_bad(B.Spb.request(B.SmStat{}, [18, 5, 107])) == True{} : Bool}

# Answers
# -------

# MountsResponse{mounts: [{type: "bind", source: "/r/snapshots/1/fs", options: ["rw", "rbind"]}]}
law layers_pb.answer_bind:
  {B.Spb.answer(S.RMounts{[S.Mount{"bind", "/r/snapshots/1/fs", ["rw", "rbind"]}]})
    == B.AnReply{[10, 36, 10, 4, 98, 105, 110, 100, 18, 17, 47, 114, 47, 115, 110, 97, 112, 115, 104, 111, 116, 115, 47, 49, 47, 102, 115, 34, 2, 114, 119, 34, 5, 114, 98, 105, 110, 100]} : B.SpAns}

# A container on a shared layer: PrepareSnapshotResponse{mounts: [{type:
# "overlay", source: "overlay", options: [workdir, upperdir on the node
# disk, "lowerdir=/mnt/layers/<hex>/fs", "index=off"]}]}.
law layers_pb.answer_shared:
  {B.Spb.answer(S.Out.res(S.Sn.run(S.Out.sn(layers_pb.fx.shared()), [S.OPrepare{"/tmp/c", layers_pb.fx.chain(), []}], [], 100)))
    == B.AnReply{[10, 176, 1, 10, 7, 111, 118, 101, 114, 108, 97, 121, 18, 7, 111, 118, 101, 114, 108, 97, 121, 34, 27, 119, 111, 114, 107, 100, 105, 114, 61, 47, 114, 47, 115, 110, 97, 112, 115, 104, 111, 116, 115, 47, 50, 47, 119, 111, 114, 107, 34, 26, 117, 112, 112, 101, 114, 100, 105, 114, 61, 47, 114, 47, 115, 110, 97, 112, 115, 104, 111, 116, 115, 47, 50, 47, 102, 115, 34, 88, 108, 111, 119, 101, 114, 100, 105, 114, 61, 47, 109, 110, 116, 47, 108, 97, 121, 101, 114, 115, 47, 101, 51, 98, 48, 99, 52, 52, 50, 57, 56, 102, 99, 49, 99, 49, 52, 57, 97, 102, 98, 102, 52, 99, 56, 57, 57, 54, 102, 98, 57, 50, 52, 50, 55, 97, 101, 52, 49, 101, 52, 54, 52, 57, 98, 57, 51, 52, 99, 97, 52, 57, 53, 57, 57, 49, 98, 55, 56, 53, 50, 98, 56, 53, 53, 47, 102, 115, 34, 9, 105, 110, 100, 101, 120, 61, 111, 102, 102]} : B.SpAns}

# The unpacker's Prepare of a layer the store has: AlreadyExists.
law layers_pb.answer_shared_exists:
  {B.Spb.answer(S.Out.res(layers_pb.fx.shared())) == B.AnStatus{6, "already exists"} : B.SpAns}

# StatSnapshotResponse{info: {name: "base", kind: COMMITTED, created_at: {seconds: 100}, updated_at: {seconds: 200}, labels: {a: "1"}}}
law layers_pb.answer_stat:
  {B.Spb.answer(S.RInfo{S.Info{S.KCommitted{}, "base", "", [S.Label{"a", "1"}], 100, 200}})
    == B.AnReply{[10, 25, 10, 4, 98, 97, 115, 101, 24, 3, 34, 2, 8, 100, 42, 3, 8, 200, 1, 50, 6, 10, 1, 97, 18, 1, 49]} : B.SpAns}

# ListSnapshotsResponse{info: [{name: "a", kind: ACTIVE, ...100}, {name: "v", parent: "a", kind: VIEW, ...100}]}
law layers_pb.answer_list:
  {B.Spb.answer(S.RList{[S.Info{S.KActive{}, "a", "", [], 100, 100}, S.Info{S.KView{}, "v", "a", [], 100, 100}]})
    == B.AnStream{[[10, 13, 10, 1, 97, 24, 2, 34, 2, 8, 100, 42, 2, 8, 100, 10, 16, 10, 1, 118, 18, 1, 97, 24, 1, 34, 2, 8, 100, 42, 2, 8, 100]]} : B.SpAns}

# No snapshot: no message, then OK (containerd's service sends no empty block).
law layers_pb.answer_list_empty:
  {B.Spb.answer(S.RList{[]}) == B.AnStream{[]} : B.SpAns}

law layers_pb.answer_not_found:
  {B.Spb.answer(S.RErr{S.ENotFound{}}) == B.AnStatus{5, "not found"} : B.SpAns}

law layers_pb.answer_exists:
  {B.Spb.answer(S.RErr{S.EExists{}}) == B.AnStatus{6, "already exists"} : B.SpAns}

law layers_pb.answer_precondition:
  {B.Spb.answer(S.RErr{S.EPrecond{}}) == B.AnStatus{9, "failed precondition"} : B.SpAns}

law layers_pb.answer_invalid:
  {B.Spb.answer(S.RErr{S.EInvalid{}}) == B.AnStatus{3, "invalid argument"} : B.SpAns}

# Commit, Remove and Cleanup answer google.protobuf.Empty; a view's
# Usage is UsageResponse{}: no bytes.
law layers_pb.answer_ok:
  {B.Spb.answer(S.ROk{}) == B.AnReply{[]} : B.SpAns}

law layers_pb.answer_zero:
  {B.Spb.answer(S.RZero{}) == B.AnReply{[]} : B.SpAns}

law layers_pb.answer_dirs:
  {B.Spb.answer(S.RDirs{["/r/snapshots/7"]}) == B.AnReply{[]} : B.SpAns}

law layers_pb.answer_measure:
  {B.Spb.answer(S.RMeasure{"/r/snapshots/1/fs"}) == B.AnMeasure{"/r/snapshots/1/fs"} : B.SpAns}

law layers_pb.answer_measure_shared:
  {B.Spb.answer(S.RMeasure{"/mnt/layers/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}) == B.AnMeasure{"/mnt/layers/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855/fs"} : B.SpAns}

# Usage
# -----

# UsageResponse{size: 8192, inodes: 3}
law layers_pb.measured_small:
  {B.Spb.measured("8\t/r/snapshots/1/fs\n3\n") == B.AnReply{[8, 128, 64, 16, 3]} : B.SpAns}

# UsageResponse{size: 5368709120, inodes: 70000}: past 32 bits.
law layers_pb.measured_big:
  {B.Spb.measured("5242880\t/mnt/layers/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855/fs\n70000\n") == B.AnReply{[8, 128, 128, 128, 128, 20, 16, 240, 162, 4]} : B.SpAns}

law layers_pb.measured_bad:
  {B.Spb.measured("") == B.AnStatus{13, "usage: could not measure"} : B.SpAns}

# Shared layers
# -------------

law layers_pb.fs_path_layer:
  {B.Spb.fs_path("/mnt/layers/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == "/mnt/layers/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855/fs" : String}

law layers_pb.fs_path_node:
  {B.Spb.fs_path("/r/snapshots/1/fs") == "/r/snapshots/1/fs" : String}

law layers_pb.fs_opt:
  {B.Spb.fs_opt("lowerdir=/mnt/layers/a:/r/snapshots/1/fs") == "lowerdir=/mnt/layers/a/fs:/r/snapshots/1/fs" : String}

law layers_pb.fs_opt_other:
  {B.Spb.fs_opt("upperdir=/r/snapshots/2/fs") == "upperdir=/r/snapshots/2/fs" : String}

law layers_pb.probe:
  {B.Spb.probe(S.OPrepare{"extract-1 sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", layers_pb.fx.ref()})
    == Some{B.SpProbe{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "/mnt/layers/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855/fs"}} : Maybe<&2, B.SpProbe>}

law layers_pb.probe_no_label:
  {B.Spb.probe(S.OPrepare{"k", "", []}) == None{} : Maybe<&2, B.SpProbe>}

law layers_pb.probe_bad_chain:
  {B.Spb.probe(S.OPrepare{"k", "", [S.Label{"containerd.io/snapshot.ref", "sha256:../../etc"}]}) == None{} : Maybe<&2, B.SpProbe>}

law layers_pb.probe_view:
  {B.Spb.probe(S.OView{"k", "", layers_pb.fx.ref()}) == None{} : Maybe<&2, B.SpProbe>}

law layers_pb.have_found:
  {B.Spb.have(Some{B.SpProbe{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "/x"}}, True{}) == ["sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"] : List<&2, String>}

law layers_pb.have_missing:
  {B.Spb.have(Some{B.SpProbe{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "/x"}}, False{}) == [] : List<&2, String>}

# The held file: the remote snapshot holds its layer as <node>/<chain>.
law layers_pb.held:
  {B.Spb.held(S.Out.sn(layers_pb.fx.shared())) == "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 n1/sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\n" : String}

law layers_pb.held_none:
  {B.Spb.held(S.Out.sn(S.Sn.run(S.Sn.new("/r", "n1"), [S.OPrepare{"k", "", []}], [], 100))) == "" : String}

law layers_pb.touches_acquire:
  {B.Spb.touches(S.Out.acts(layers_pb.fx.shared())) == True{} : Bool}

law layers_pb.touches_dirs:
  {B.Spb.touches([S.AMkdir{"/a"}, S.ARemove{"/b"}]) == False{} : Bool}

law layers_pb.mkdirs:
  {B.Spb.mkdirs([S.AMkdir{"/a"}, S.ARemove{"/b"}, S.AMkdir{"/c"}]) == ["/a", "/c"] : List<&2, String>}

law layers_pb.removes:
  {B.Spb.removes([S.AMkdir{"/a"}, S.ARemove{"/b"}, S.AMkdir{"/c"}]) == ["/b"] : List<&2, String>}

# Host side
# ---------

law layers_pb.names:
  {B.Spb.names("1\n2\n\n10\n") == ["1", "2", "10"] : List<&2, String>}

law layers_pb.fill:
  {B.Spb.fill(S.OCleanup{[]}, ["1", "9"]) == S.OCleanup{["1", "9"]} : S.Op}

law layers_pb.fill_other:
  {B.Spb.fill(S.OStat{"k"}, ["1"]) == S.OStat{"k"} : S.Op}

law layers_pb.dirty_commit:
  {B.Spb.dirty(S.OCommit{"n", "k", "", []}) == True{} : Bool}

law layers_pb.dirty_stat:
  {B.Spb.dirty(S.OStat{"k"}) == False{} : Bool}

# 2024-10-04T01:00:00Z: day 20000 since 1970, second 3600.
law layers_pb.epoch:
  {B.Spb.epoch(20000, 3600) == 1728003600 : U32}
