import Base
import ../src/layers/snap.bend as S
import ../src/layers/state.bend as T

# Spec for src/layers/state.bend: the node snapshotter's state file
# (vk8s design; the format is stated in the module's head). A state
# reads back as itself, so a restarted snapshotter answers as the one
# before it.

def layers_state.fx.run(have: List<&2, String>, ops: List<&2, S.Op>) -> S.Sn:
  S.Out.sn(S.Sn.run(S.Sn.new("/r", "n1"), ops, have, 100))

# A key with a space, a label value with a percent sign.
def layers_state.fx.one() -> S.Sn:
  layers_state.fx.run([], [S.OPrepare{"a b", "", [S.Label{"k", "v%1"}]}])

def layers_state.fx.one_text() -> String:
  "bend-snap 1\nnext 2\n=a%sb =1 =active = = =100 =100 =k =v%p1\n"

# A committed parent with a tab and a newline in a label, and an active
# child named with a space.
def layers_state.fx.commit() -> S.Sn:
  layers_state.fx.run([], [S.OPrepare{"/tmp/test", "", []}, S.OCommit{"base", "/tmp/test", "", [S.Label{"x", "a\tb\nc"}]}, S.OPrepare{"c d", "base", []}])

# The unpacker's remote snapshot of a shared layer.
def layers_state.fx.shared() -> S.Sn:
  layers_state.fx.run(["sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"], [S.OPrepare{"extract-1 sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", [S.Label{"containerd.io/snapshot.ref", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}]}])

law layers_state.show_new:
  {T.Sst.show(S.Sn.new("/r", "n1")) == "bend-snap 1\nnext 1\n" : String}

law layers_state.show_one:
  {T.Sst.show(layers_state.fx.one()) == layers_state.fx.one_text() : String}

law layers_state.show_shared:
  {T.Sst.show(layers_state.fx.shared())
    == "bend-snap 1\nnext 2\n=sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 =1 =committed = =sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 =100 =100 =containerd.io/snapshot.ref =sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\n" : String}

law layers_state.read_new:
  {T.Sst.read("/r", "n1", "bend-snap 1\nnext 1\n") == Some{S.Sn.new("/r", "n1")} : Maybe<&2, S.Sn>}

law layers_state.read_one:
  {T.Sst.read("/r", "n1", layers_state.fx.one_text())
    == Some{S.Sn{"/r", "n1", 2, [S.Snap{"a b", 1, S.KActive{}, "", "", [S.Label{"k", "v%1"}], 100, 100}]}} : Maybe<&2, S.Sn>}

law layers_state.round_trip_one:
  {T.Sst.read("/r", "n1", T.Sst.show(layers_state.fx.one())) == Some{layers_state.fx.one()} : Maybe<&2, S.Sn>}

law layers_state.round_trip_commit:
  {T.Sst.read("/r", "n1", T.Sst.show(layers_state.fx.commit())) == Some{layers_state.fx.commit()} : Maybe<&2, S.Sn>}

law layers_state.round_trip_shared:
  {T.Sst.read("/r", "n1", T.Sst.show(layers_state.fx.shared())) == Some{layers_state.fx.shared()} : Maybe<&2, S.Sn>}

# No file, another version, a field that is not a number, a label
# without its value: not a state.
law layers_state.read_empty:
  {T.Sst.read("/r", "n1", "") == None{} : Maybe<&2, S.Sn>}

law layers_state.read_version:
  {T.Sst.read("/r", "n1", "bend-snap 2\nnext 1\n") == None{} : Maybe<&2, S.Sn>}

law layers_state.read_bad_id:
  {T.Sst.read("/r", "n1", "bend-snap 1\nnext 2\n=a =x =active = = =1 =1\n") == None{} : Maybe<&2, S.Sn>}

law layers_state.read_odd_labels:
  {T.Sst.read("/r", "n1", "bend-snap 1\nnext 2\n=a =1 =active = = =1 =1 =k\n") == None{} : Maybe<&2, S.Sn>}

law layers_state.read_bad_kind:
  {T.Sst.read("/r", "n1", "bend-snap 1\nnext 2\n=a =1 =frozen = = =1 =1\n") == None{} : Maybe<&2, S.Sn>}

law layers_state.esc:
  {T.Sst.esc("a%b c\nd\re\tf") == "a%pb%sc%nd%re%tf" : String}

law layers_state.unesc:
  {T.Sst.unesc("a%pb%sc%nd%re%tf") == "a%b c\nd\re\tf" : String}
