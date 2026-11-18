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

def T.labels(ls: List<&2, S.Label>) -> String:
  match ls:
    case Nil{}:
      ""
    case Con{S.Label{k, v}, t}:
      k ++ "=" ++ v ++ ";" ++ T.labels(t)

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
    case S.RInfo{S.Info{kd, n, p, ls, c, u}}:
      "labels " ++ T.labels(ls)
    case S.RDirs{ds}:
      "dirs " ++ String.join(ds, ",")
    case _:
      "other"

def T.run(have: List<&2, String>, ops: List<&2, S.Op>) -> String:
  T.res(S.Out.res(S.Sn.run(S.Sn.new("/var/lib/containerd/io.containerd.snapshotter.v1.bend", "n1"), ops, have, 1700000000)))

# Scale: an image of n layers unpacked on the node disk, as containerd's
# unpacker does it for a layer the store lacks: Prepare extract-<i> on
# the last layer, Commit it as layer-<i>. Every call is linear in the
# snapshots; a def that recurses twice per snapshot (both arguments of
# Bool.pick) makes these never finish.
def T.chain(n: Nat, +i: U32, parent: String) -> List<&2, S.Op>:
  match n:
    case 0n:
      Nil{}
    case 1n+m:
      +key : String = "extract-" ++ U32.show(i)
      +name : String = "layer-" ++ U32.show(i)
      Con{S.OPrepare{key, parent, []}, Con{S.OCommit{name, key, "", []}, T.chain(m, (i + 1 : U32), name)}}

def T.ids(n: Nat, +i: U32) -> List<&2, String>:
  match n:
    case 0n:
      Nil{}
    case 1n+m:
      Con{U32.show(i), T.ids(m, (i + 1 : U32))}

def T.paths(n: Nat) -> List<&2, String>:
  match n:
    case 0n:
      Nil{}
    case 1n+m:
      Con{"labels.a", T.paths(m)}

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
    check("remove among 40 committed layers", T.run([], List.append(&2, S.Op, T.chain(40n, 1, ""), [S.OPrepare{"ctr", "layer-40", []}, S.ORemove{"ctr"}])), "ok")
    check("cleanup among 40 layers", T.run([], List.append(&2, S.Op, T.chain(40n, 1, ""), [S.OCleanup{List.append(&2, String, T.ids(40n, 1), ["99"])}])),
      "dirs /var/lib/containerd/io.containerd.snapshotter.v1.bend/snapshots/99")
    check("update with 40 field paths", T.run([], [S.OPrepare{"k", "", [S.Label{"a", "1"}]}, S.OUpdate{"k", [S.Label{"a", "2"}], T.paths(40n)}]), "labels a=2;")
