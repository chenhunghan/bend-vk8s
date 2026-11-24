import Base
import ../src/layers/ask.bend as A
import ../src/layers/snap.bend as S

# Spec for src/layers/ask.bend: the ask of a node's snapshotter to the
# host's layer filler, its line on the wire, and the filler's reply.
#
# Proposed: every law of this file is new (feat/layers-ask, work item W1
# of explore-layers-autofill-pull). Sources:
# - label names: containerd v2.2.3 pkg/snapshotters/annotations.go
#   (TargetRefLabel, TargetManifestDigestLabel, TargetLayerDigestLabel)
#   and core/snapshots/snapshotter.go (labelSnapshotRef);
# - label values: AppendInfoHandlerWrapper sets the image reference, the
#   manifest's digest and the layer's digest (Digest.String()); CRI
#   passes the normalized reference (docker.io/library/busybox:latest);
#   the registry and repository of a reference: distribution/reference
#   normalize_test.go TestParseDockerRef;
# - digests: busybox's from TestParseDockerRef, the layer from image-spec
#   manifest.md's example, the chain ID (the first layer's diffID) from
#   image-spec config.md's example;
# - registries: vk8s's image cache (src/guest/plan.bend Plan.mirrors);
#   repository grammar: distribution-spec spec.md;
# - the line protocol, its bounds, the port and the wait: design of W1
#   (user decision), not upstream behaviour.

def layers_ask.fx.m() -> String:
  "sha256:e6693c20186f837fc393390135d8a598a96a833917917789d63766cab6c59582"

def layers_ask.fx.l() -> String:
  "sha256:9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0"

def layers_ask.fx.c() -> String:
  "sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1"

def layers_ask.fx.ask() -> A.Ask:
  A.Ask{"docker.io", "library/busybox", layers_ask.fx.m(), layers_ask.fx.l(), layers_ask.fx.c()}

# The labels containerd's unpacker puts on a layer's Prepare (unsorted, as
# a request carries them).
def layers_ask.fx.labels(ref: String) -> List<&2, S.Label>:
  [ S.Label{"containerd.io/snapshot.ref", layers_ask.fx.c()},
    S.Label{"containerd.io/snapshot/cri.layer-digest", layers_ask.fx.l()},
    S.Label{"containerd.io/snapshot/cri.image-ref", ref},
    S.Label{"containerd.io/snapshot/cri.manifest-digest", layers_ask.fx.m()} ]

def layers_ask.fx.prepare(ls: List<&2, S.Label>) -> S.Op:
  S.OPrepare{"default/1/extract-1 sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1", "", ls}

def layers_ask.fx.line() -> String:
  "ask docker.io library/busybox sha256:e6693c20186f837fc393390135d8a598a96a833917917789d63766cab6c59582 sha256:9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0 sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1\n"

# The digests part of a line, after the repository.
def layers_ask.fx.tail() -> String:
  " sha256:e6693c20186f837fc393390135d8a598a96a833917917789d63766cab6c59582 sha256:9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0 sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1\n"

# Label names (annotations.go, snapshotter.go)
# -----------

law layers_ask.label.ref:
  {A.Ask.label.ref.v2() == "containerd.io/snapshot/cri.image-ref" : String}

law layers_ask.label.manifest:
  {A.Ask.label.manifest.v2() == "containerd.io/snapshot/cri.manifest-digest" : String}

law layers_ask.label.layer:
  {A.Ask.label.layer.v2() == "containerd.io/snapshot/cri.layer-digest" : String}

law layers_ask.label.chain:
  {A.Ask.label.chain.v2() == "containerd.io/snapshot.ref" : String}

# The ask from labels
# -----------

law layers_ask.of_labels.prepare:
  {A.Ask.of_labels.v2(layers_ask.fx.prepare(layers_ask.fx.labels("docker.io/library/busybox:latest")), False{}) == Some{layers_ask.fx.ask()} : Maybe<&2, A.Ask>}

# A short reference names the same image (TestParseDockerRef "nothing").
law layers_ask.of_labels.short_ref:
  {A.Ask.of_labels.v2(layers_ask.fx.prepare(layers_ask.fx.labels("busybox")), False{}) == Some{layers_ask.fx.ask()} : Maybe<&2, A.Ask>}

# A reference by digest: the repository only.
law layers_ask.of_labels.by_digest:
  {A.Ask.of_labels.v2(layers_ask.fx.prepare(layers_ask.fx.labels("registry.k8s.io/pause@sha256:e6693c20186f837fc393390135d8a598a96a833917917789d63766cab6c59582")), False{})
    == Some{A.Ask{"registry.k8s.io", "pause", layers_ask.fx.m(), layers_ask.fx.l(), layers_ask.fx.c()}} : Maybe<&2, A.Ask>}

# A layer the store holds needs no ask.
law layers_ask.of_labels.present:
  {A.Ask.of_labels.v2(layers_ask.fx.prepare(layers_ask.fx.labels("docker.io/library/busybox:latest")), True{}) == None{} : Maybe<&2, A.Ask>}

law layers_ask.of_labels.view:
  {A.Ask.of_labels.v2(S.OView{"v", "p", layers_ask.fx.labels("docker.io/library/busybox:latest")}, False{}) == None{} : Maybe<&2, A.Ask>}

law layers_ask.of_labels.commit:
  {A.Ask.of_labels.v2(S.OCommit{"n", "k", "", layers_ask.fx.labels("docker.io/library/busybox:latest")}, False{}) == None{} : Maybe<&2, A.Ask>}

# A Prepare without the remote snapshot labels (a container's rootfs).
law layers_ask.of_labels.no_labels:
  {A.Ask.of_labels.v2(layers_ask.fx.prepare(Nil{}), False{}) == None{} : Maybe<&2, A.Ask>}

law layers_ask.of_labels.no_manifest:
  {A.Ask.of_labels.v2(layers_ask.fx.prepare(
      [ S.Label{"containerd.io/snapshot.ref", layers_ask.fx.c()},
        S.Label{"containerd.io/snapshot/cri.layer-digest", layers_ask.fx.l()},
        S.Label{"containerd.io/snapshot/cri.image-ref", "docker.io/library/busybox:latest"} ]), False{}) == None{} : Maybe<&2, A.Ask>}

law layers_ask.of_labels.no_layer:
  {A.Ask.of_labels.v2(layers_ask.fx.prepare(
      [ S.Label{"containerd.io/snapshot.ref", layers_ask.fx.c()},
        S.Label{"containerd.io/snapshot/cri.image-ref", "docker.io/library/busybox:latest"},
        S.Label{"containerd.io/snapshot/cri.manifest-digest", layers_ask.fx.m()} ]), False{}) == None{} : Maybe<&2, A.Ask>}

law layers_ask.of_labels.no_chain:
  {A.Ask.of_labels.v2(layers_ask.fx.prepare(
      [ S.Label{"containerd.io/snapshot/cri.layer-digest", layers_ask.fx.l()},
        S.Label{"containerd.io/snapshot/cri.image-ref", "docker.io/library/busybox:latest"},
        S.Label{"containerd.io/snapshot/cri.manifest-digest", layers_ask.fx.m()} ]), False{}) == None{} : Maybe<&2, A.Ask>}

law layers_ask.of_labels.no_ref:
  {A.Ask.of_labels.v2(layers_ask.fx.prepare(
      [ S.Label{"containerd.io/snapshot.ref", layers_ask.fx.c()},
        S.Label{"containerd.io/snapshot/cri.layer-digest", layers_ask.fx.l()},
        S.Label{"containerd.io/snapshot/cri.manifest-digest", layers_ask.fx.m()} ]), False{}) == None{} : Maybe<&2, A.Ask>}

# The image cache does not serve gcr.io: the filler could not fetch it.
law layers_ask.of_labels.other_registry:
  {A.Ask.of_labels.v2(layers_ask.fx.prepare(layers_ask.fx.labels("gcr.io/library/busybox:latest")), False{}) == None{} : Maybe<&2, A.Ask>}

# Every call asks nothing when the store holds the layer.
law layers_ask.of_labels.present_never:
  for op: S.Op
  {A.Ask.of_labels.v2(op, True{}) == None{} : Maybe<&2, A.Ask>}

# A View never asks.
law layers_ask.of_labels.view_never:
  for k: String
  for p: String
  for ls: List<&2, S.Label>
  for b: Bool
  {A.Ask.of_labels.v2(S.OView{k, p, ls}, b) == None{} : Maybe<&2, A.Ask>}

# The line
# -----------

law layers_ask.line_max:
  {A.Ask.line_max.v2() == 512n : Nat}

law layers_ask.render:
  {A.Ask.render.v2(layers_ask.fx.ask()) == layers_ask.fx.line() : String}

law layers_ask.parse.line:
  {A.Ask.parse.v2(layers_ask.fx.line()) == Some{layers_ask.fx.ask()} : Maybe<&2, A.Ask>}

law layers_ask.parse.each_mirror:
  {A.Ask.parse.v2("ask registry.k8s.io pause" ++ layers_ask.fx.tail()) == Some{A.Ask{"registry.k8s.io", "pause", layers_ask.fx.m(), layers_ask.fx.l(), layers_ask.fx.c()}} : Maybe<&2, A.Ask>}

law layers_ask.parse.ghcr:
  {A.Ask.parse.v2("ask ghcr.io a/b-c/d_e.f" ++ layers_ask.fx.tail()) == Some{A.Ask{"ghcr.io", "a/b-c/d_e.f", layers_ask.fx.m(), layers_ask.fx.l(), layers_ask.fx.c()}} : Maybe<&2, A.Ask>}

law layers_ask.parse.quay:
  {A.Ask.parse.v2("ask quay.io x/y" ++ layers_ask.fx.tail()) == Some{A.Ask{"quay.io", "x/y", layers_ask.fx.m(), layers_ask.fx.l(), layers_ask.fx.c()}} : Maybe<&2, A.Ask>}

law layers_ask.parse.other_registry:
  {A.Ask.parse.v2("ask gcr.io library/busybox" ++ layers_ask.fx.tail()) == None{} : Maybe<&2, A.Ask>}

law layers_ask.parse.registry_port:
  {A.Ask.parse.v2("ask docker.io:443 library/busybox" ++ layers_ask.fx.tail()) == None{} : Maybe<&2, A.Ask>}

law layers_ask.parse.upper_repo:
  {A.Ask.parse.v2("ask docker.io library/BusyBox" ++ layers_ask.fx.tail()) == None{} : Maybe<&2, A.Ask>}

law layers_ask.parse.dot_dot_repo:
  {A.Ask.parse.v2("ask docker.io ../etc" ++ layers_ask.fx.tail()) == None{} : Maybe<&2, A.Ask>}

law layers_ask.parse.empty_repo:
  {A.Ask.parse.v2("ask docker.io " ++ layers_ask.fx.tail()) == None{} : Maybe<&2, A.Ask>}

law layers_ask.parse.short_digest:
  {A.Ask.parse.v2("ask docker.io library/busybox sha256:e6693c20186f837fc393390135d8a598a96a833917917789d63766cab6c5958 sha256:9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0 sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1\n") == None{} : Maybe<&2, A.Ask>}

law layers_ask.parse.upper_hex:
  {A.Ask.parse.v2("ask docker.io library/busybox sha256:E6693c20186f837fc393390135d8a598a96a833917917789d63766cab6c59582 sha256:9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0 sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1\n") == None{} : Maybe<&2, A.Ask>}

law layers_ask.parse.other_algorithm:
  {A.Ask.parse.v2("ask docker.io library/busybox sha512:e6693c20186f837fc393390135d8a598a96a833917917789d63766cab6c59582 sha256:9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0 sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1\n") == None{} : Maybe<&2, A.Ask>}

law layers_ask.parse.bad_chain:
  {A.Ask.parse.v2("ask docker.io library/busybox sha256:e6693c20186f837fc393390135d8a598a96a833917917789d63766cab6c59582 sha256:9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0 ../../x\n") == None{} : Maybe<&2, A.Ask>}

law layers_ask.parse.word:
  {A.Ask.parse.v2("ASK docker.io library/busybox" ++ layers_ask.fx.tail()) == None{} : Maybe<&2, A.Ask>}

law layers_ask.parse.extra_field:
  {A.Ask.parse.v2("ask docker.io library/busybox x" ++ layers_ask.fx.tail()) == None{} : Maybe<&2, A.Ask>}

law layers_ask.parse.two_spaces:
  {A.Ask.parse.v2("ask  docker.io library/busybox" ++ layers_ask.fx.tail()) == None{} : Maybe<&2, A.Ask>}

law layers_ask.parse.no_newline:
  {A.Ask.parse.v2("ask docker.io library/busybox sha256:e6693c20186f837fc393390135d8a598a96a833917917789d63766cab6c59582 sha256:9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0 sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1") == None{} : Maybe<&2, A.Ask>}

law layers_ask.parse.crlf:
  {A.Ask.parse.v2("ask docker.io library/busybox sha256:e6693c20186f837fc393390135d8a598a96a833917917789d63766cab6c59582 sha256:9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0 sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1\r\n") == None{} : Maybe<&2, A.Ask>}

law layers_ask.parse.two_lines:
  {A.Ask.parse.v2(layers_ask.fx.line() ++ layers_ask.fx.line()) == None{} : Maybe<&2, A.Ask>}

law layers_ask.parse.empty:
  {A.Ask.parse.v2("") == None{} : Maybe<&2, A.Ask>}

# The longest valid ask (registry.k8s.io and a 255-character repository)
# fits the bound.
law layers_ask.parse.longest:
  {A.Ask.parse.v2("ask registry.k8s.io " ++ String.repeat("a", 255n) ++ layers_ask.fx.tail()) == Some{A.Ask{"registry.k8s.io", String.repeat("a", 255n), layers_ask.fx.m(), layers_ask.fx.l(), layers_ask.fx.c()}} : Maybe<&2, A.Ask>}

law layers_ask.parse.repo_256:
  {A.Ask.parse.v2("ask docker.io " ++ String.repeat("a", 256n) ++ layers_ask.fx.tail()) == None{} : Maybe<&2, A.Ask>}

# Over Ask.line_max.v2 bytes, nothing is read.
law layers_ask.parse.too_long:
  {A.Ask.parse.v2(String.repeat("a", 513n) ++ "\n") == None{} : Maybe<&2, A.Ask>}

# Replies
# -----------

law layers_ask.reply.render.present:
  {A.Ask.reply.render.v2(A.RPresent{}) == "ok present\n" : String}

law layers_ask.reply.render.published:
  {A.Ask.reply.render.v2(A.RPublished{}) == "ok published\n" : String}

law layers_ask.reply.render.no:
  {A.Ask.reply.render.v2(A.RNo{"cache unreachable"}) == "no cache unreachable\n" : String}

law layers_ask.reply.parse.present:
  {A.Ask.reply.parse.v2("ok present\n") == Some{A.RPresent{}} : Maybe<&2, A.Reply>}

law layers_ask.reply.parse.published:
  {A.Ask.reply.parse.v2("ok published\n") == Some{A.RPublished{}} : Maybe<&2, A.Reply>}

law layers_ask.reply.parse.no:
  {A.Ask.reply.parse.v2("no cache unreachable\n") == Some{A.RNo{"cache unreachable"}} : Maybe<&2, A.Reply>}

law layers_ask.reply.parse.ok_alone:
  {A.Ask.reply.parse.v2("ok\n") == None{} : Maybe<&2, A.Reply>}

law layers_ask.reply.parse.ok_other:
  {A.Ask.reply.parse.v2("ok maybe\n") == None{} : Maybe<&2, A.Reply>}

law layers_ask.reply.parse.upper:
  {A.Ask.reply.parse.v2("OK present\n") == None{} : Maybe<&2, A.Reply>}

law layers_ask.reply.parse.no_reason:
  {A.Ask.reply.parse.v2("no \n") == None{} : Maybe<&2, A.Reply>}

law layers_ask.reply.parse.no_newline:
  {A.Ask.reply.parse.v2("ok present") == None{} : Maybe<&2, A.Reply>}

law layers_ask.reply.parse.control:
  {A.Ask.reply.parse.v2("no a\tb\n") == None{} : Maybe<&2, A.Reply>}

law layers_ask.reply.parse.reason_80:
  {A.Ask.reply.parse.v2("no " ++ String.repeat("x", 80n) ++ "\n") == Some{A.RNo{String.repeat("x", 80n)}} : Maybe<&2, A.Reply>}

law layers_ask.reply.parse.reason_81:
  {A.Ask.reply.parse.v2("no " ++ String.repeat("x", 81n) ++ "\n") == None{} : Maybe<&2, A.Reply>}

law layers_ask.reply.had:
  for e: Maybe<&2, String>
  {A.Ask.reply.v2(True{}, e) == A.RPresent{} : A.Reply}

law layers_ask.reply.published:
  {A.Ask.reply.v2(False{}, None{}) == A.RPublished{} : A.Reply}

law layers_ask.reply.failed:
  {A.Ask.reply.v2(False{}, Some{"dial tcp 127.0.0.1:15001: connection refused"}) == A.RNo{"dial tcp 127.0.0.1:15001: connection refused"} : A.Reply}

# A reason is made fit for the wire: control characters become "?".
law layers_ask.reply.failed_newline:
  {A.Ask.reply.v2(False{}, Some{"a\nb"}) == A.RNo{"a?b"} : A.Reply}

law layers_ask.reply.failed_empty:
  {A.Ask.reply.v2(False{}, Some{""}) == A.RNo{"fill failed"} : A.Reply}

law layers_ask.reply.failed_long:
  {A.Ask.reply.v2(False{}, Some{String.repeat("x", 100n)}) == A.RNo{String.repeat("x", 80n)} : A.Reply}

# What the filler chooses reads back the same.
law layers_ask.reply.round_failed:
  {A.Ask.reply.parse.v2(A.Ask.reply.render.v2(A.Ask.reply.v2(False{}, Some{"a\nb"}))) == Some{A.RNo{"a?b"}} : Maybe<&2, A.Reply>}

# Where and how long
# -----------

law layers_ask.host:
  {A.Ask.host.v2() == "10.0.2.2" : String}

law layers_ask.port:
  {A.Ask.port.v2() == 32000 : U32}

law layers_ask.wait_max:
  {A.Ask.wait.max.v2() == 60 : U32}

# Proposed: the guest's side of the ask (work item W6 of docs/ref/
# explore-layers-autofill.md). The node's snapshotter waits Ask.wait.max.v2
# seconds as milliseconds, reads a reply until its "\n" or
# Ask.reply_max.v2 bytes, and logs what came of the ask; every outcome
# ends in a second probe of the store (host/snapshotter.bend).
law layers_ask.wait_ms_v2:
  {A.Ask.wait.ms.v2() == 60000 : U32}
law layers_ask.reply_whole_line_v2:
  {A.Ask.reply.whole.v2("ok published\n") == True{} : Bool}
law layers_ask.reply_whole_partial_v2:
  {A.Ask.reply.whole.v2("ok publ") == False{} : Bool}
law layers_ask.reply_whole_long_v2:
  {A.Ask.reply.whole.v2("nnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnn") == True{} : Bool}
law layers_ask.heard_no_v2:
  {A.Ask.said.v2(A.Ask.heard.v2("no store full\n")) == "no store full" : String}
law layers_ask.heard_present_v2:
  {A.Ask.said.v2(A.Ask.heard.v2("ok present\n")) == "ok present" : String}
law layers_ask.heard_junk_v2:
  {A.Ask.said.v2(A.Ask.heard.v2("HTTP/1.1 400 Bad Request\n")) == "no reply: the filler's answer is not a reply line" : String}

# Proposed: the filler's address from the node's environment (docs/GOAL.md
# section 11, the container half; vk8s's design): VK8S_LAYERS_ASK names
# it (a node container's bridge gateway, Ctr.layers_env); unset, a VM
# node's 10.0.2.2.
law layers_ask.host_v3_unset:
  {A.Ask.host.v3("") == "10.0.2.2" : String}
law layers_ask.host_v3_env:
  {A.Ask.host.v3("10.10.3.1") == "10.10.3.1" : String}
