import Base
import ../src/layers/snap.bend as S
import ../src/layers/ask.bend as A

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

# The ask of a Prepare (work item W6, src/layers/ask.bend): containerd's
# CRI labels (containerd v2.2.3 pkg/snapshotters/annotations.go, passed
# when disable_snapshot_annotations is false) on the unpacker's Prepare
# of a layer. Digests as tests/layers_ask.bend.
def W.m() -> String:
  "sha256:e6693c20186f837fc393390135d8a598a96a833917917789d63766cab6c59582"

def W.l() -> String:
  "sha256:9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0"

def W.c() -> String:
  "sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1"

def W.prepare() -> S.Op:
  S.OPrepare{"extract-1", "", [ S.Label{"containerd.io/snapshot/cri.image-ref", "docker.io/library/nginx:1.27"},
    S.Label{"containerd.io/snapshot/cri.manifest-digest", W.m()},
    S.Label{"containerd.io/snapshot/cri.layer-digest", W.l()},
    S.Label{"containerd.io/snapshot.ref", W.c()} ]}

# A Prepare as `ctr images import` sends it: the chain ID only.
def W.imported() -> S.Op:
  S.OPrepare{"extract-1", "", [S.Label{"containerd.io/snapshot.ref", W.c()}]}

def W.ask(m: Maybe<&2, A.Ask>) -> String:
  match m:
    case None{}:
      "<none>"
    case Some{a}:
      A.Ask.render.v2(a)

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
    check("a Prepare of a missing layer with the CRI labels asks the filler", W.ask(A.Ask.of_labels.v2(W.prepare(), False{})),
      "ask docker.io library/nginx " ++ W.m() ++ " " ++ W.l() ++ " " ++ W.c() ++ "\n")
    check("a Prepare of a layer the store holds does not ask", W.ask(A.Ask.of_labels.v2(W.prepare(), True{})), "<none>")
    check("a Prepare from ctr images import (no CRI labels) does not ask", W.ask(A.Ask.of_labels.v2(W.imported(), False{})), "<none>")
    check("a View does not ask", W.ask(A.Ask.of_labels.v2(S.OView{"v", "", []}, False{})), "<none>")
    check("after the ask, a layer the filler published is not unpacked", T.run([W.c()], [W.prepare()]), "already exists")
    check("after a no, a timeout or a refused ask, the layer is unpacked on the node", T.run([], [W.prepare()]),
      "bind /var/lib/containerd/io.containerd.snapshotter.v1.bend/snapshots/1/fs rw,rbind;")
    check("the guest waits at most 60 s for the filler", U32.show(A.Ask.wait.ms.v2()), "60000")
    check("the guest asks the host's loopback on port 32000", A.Ask.host.v2() ++ ":" ++ U32.show(A.Ask.port.v2()), "10.0.2.2:32000")
    check("a reply ends at its newline", A.Ask.said.v2(A.Ask.heard.v2("ok published\n")), "ok published")
    check("a no is logged with its reason", A.Ask.said.v2(A.Ask.heard.v2("no store full\n")), "no store full")
    check("a line that is not a reply falls through", A.Ask.said.v2(A.Ask.heard.v2("ok maybe\n")),
      "no reply: the filler's answer is not a reply line")
    check("a partial reply is read further", Bool.show(A.Ask.reply.whole.v2("ok pub")), "False")
