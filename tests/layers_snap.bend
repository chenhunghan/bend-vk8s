import Base
import ../src/layers/snap.bend as S

# Tests for src/layers/snap.bend: containerd overlay snapshotter
# behaviour (overlay_test.go) over the shared layer store.

def report(name: String, got: String, want: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name ++ ": got " ++ got ++ ", want " ++ want)

def check(name: String, +got: String, +want: String) -> IO(Unit):
  report(name, got, want, String.eq(got, want))

def T.err(e: S.Err) -> String:
  match e:
    case S.ENotFound{}:
      "not found"
    case S.EExists{}:
      "already exists"
    case S.EPrecond{}:
      "failed precondition"
    case S.EInvalid{}:
      "invalid argument"

def T.mounts(ms: List<&2, S.Mount>) -> String:
  match ms:
    case Nil{}:
      ""
    case Con{S.Mount{t, s, os}, rest}:
      t ++ " " ++ s ++ " " ++ String.join(os, ",") ++ ";" ++ T.mounts(rest)

def T.res(r: S.Res) -> String:
  match r:
    case S.RMounts{ms}:
      T.mounts(ms)
    case S.RErr{e}:
      T.err(e)
    case S.ROk{}:
      "ok"
    case S.RMeasure{p}:
      "measure " ++ p
    case _:
      "other"

def T.run(have: List<&2, String>, ops: List<&2, S.Op>) -> String:
  T.res(S.Out.res(S.Sn.run(S.Sn.new("/var/lib/containerd/io.containerd.snapshotter.v1.bend", "n1"), ops, have, 1700000000)))

def main() -> IO(Unit):
  do IO<Unit>:
    check("bind without parent", T.run([], [S.OPrepare{"k", "", []}]),
      "bind /var/lib/containerd/io.containerd.snapshotter.v1.bend/snapshots/1/fs rw,rbind;")
    check("overlay on a committed parent", T.run([], [S.OPrepare{"k", "", []}, S.OCommit{"base", "k", "", []}, S.OPrepare{"c", "base", []}]),
      "overlay overlay workdir=/var/lib/containerd/io.containerd.snapshotter.v1.bend/snapshots/2/work,upperdir=/var/lib/containerd/io.containerd.snapshotter.v1.bend/snapshots/2/fs,lowerdir=/var/lib/containerd/io.containerd.snapshotter.v1.bend/snapshots/1/fs,index=off;")
    check("shared layer skips unpacking", T.run(["sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"],
      [S.OPrepare{"extract-1", "", [S.Label{"containerd.io/snapshot.ref", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}]}]),
      "already exists")
    check("container on a shared layer", T.run(["sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"],
      [S.OPrepare{"extract-1", "", [S.Label{"containerd.io/snapshot.ref", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}]},
       S.OPrepare{"ctr", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", []}]),
      "overlay overlay workdir=/var/lib/containerd/io.containerd.snapshotter.v1.bend/snapshots/2/work,upperdir=/var/lib/containerd/io.containerd.snapshotter.v1.bend/snapshots/2/fs,lowerdir=/mnt/layers/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855,index=off;")
    check("commit a view", T.run([], [S.OView{"v", "", []}, S.OCommit{"c", "v", "", []}]), "failed precondition")
    check("remove a parent", T.run([], [S.OPrepare{"k", "", []}, S.OCommit{"base", "k", "", []}, S.OPrepare{"c", "base", []}, S.ORemove{"base"}]), "failed precondition")
    check("usage of an active snapshot", T.run([], [S.OPrepare{"k", "", []}, S.OUsage{"k"}]),
      "measure /var/lib/containerd/io.containerd.snapshotter.v1.bend/snapshots/1/fs")
