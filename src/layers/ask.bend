import Base
import ../guest/plan.bend as PL
import ../oci/grammar.bend as G
import ./pull.bend as P
import ./snap.bend as S

# The ask of a node's snapshotter to the host's layer filler (GOAL
# section 10, "the store fills itself"; work item W1 of
# explore-layers-autofill-pull). On a Prepare of a layer the shared store
# (src/layers/store.bend) does not hold, the guest snapshotter asks a
# host-global filler daemon over TCP (10.0.2.2:Ask.port.v2, the host's
# loopback through the VM's NAT) to fill the store from the image cache,
# waits at most Ask.wait.max.v2, then probes the store again and, when the
# layer is still missing, falls back to containerd's local unpack. Pure:
# these defs build the ask from containerd's labels, put it on the wire,
# read it back strictly, and choose and read the answer; the host does
# the IO.
#
# The labels: containerd's unpacker passes a layer's descriptor
# annotations to Prepare as labels (containerd v2.2.3
# pkg/snapshotters/annotations.go, AppendInfoHandlerWrapper):
#   containerd.io/snapshot/cri.image-ref        (TargetRefLabel)
#   containerd.io/snapshot/cri.manifest-digest  (TargetManifestDigestLabel)
#   containerd.io/snapshot/cri.layer-digest     (TargetLayerDigestLabel)
# and the chain ID of the snapshot it wants in
#   containerd.io/snapshot.ref                  (core/snapshots/
#                                                snapshotter.go,
#                                                labelSnapshotRef).
#
# The wire: one line each way, ASCII, fields split by one space, ended by
# one "\n":
#   guest: ask <registry> <repository> <manifest> <layer> <chain>
#   host:  ok present | ok published | no <reason>
#
# Everything the guest sends is untrusted: any pod can reach 10.0.2.2,
# so the filler reads an ask with Ask.parse.v2 only, which takes at most
# Ask.line_max.v2 bytes; only a registry the image cache serves
# (src/guest/plan.bend Plan.mirrors), a repository of the distribution
# grammar (src/oci/grammar.bend Gram.name, at most 255 characters) and
# sha256 digests of exactly 71 characters ("sha256:" and 64 lowercase
# hex digits). Parsing does not make an ask true: the filler fetches the
# manifest by its digest, checks every blob against its digest, and
# publishes a layer only under the chain ID it computes itself.

# One ask: the registry and repository of the image (the image-ref
# label, normalized as distribution/reference ParseDockerRef; a tag or
# digest in it is dropped, the manifest digest names the image), the
# manifest's digest, the layer blob's digest and the layer's chain ID.
type Ask is Data:
  Ask{registry: String, repo: String, manifest: String, layer: String, chain: String}

# The labels
# ----------

def Ask.label.ref.v2() -> String:
  "containerd.io/snapshot/cri.image-ref"

def Ask.label.manifest.v2() -> String:
  "containerd.io/snapshot/cri.manifest-digest"

def Ask.label.layer.v2() -> String:
  "containerd.io/snapshot/cri.layer-digest"

def Ask.label.chain.v2() -> String:
  "containerd.io/snapshot.ref"

# Checks
# ------

def Ask.mirror(ms: +List<PL.Mirror>, +r: String) -> Bool:
  match ms:
    case Nil{}:
      False{}
    case Con{m, t}:
      String.eq(PL.Plan.mirror_name(m), r) || Ask.mirror(t, r)

# A registry the image cache serves.
def Ask.registry_ok.v2(+r: String) -> Bool:
  Ask.mirror(PL.Plan.mirrors(), r)

# A repository name of the distribution grammar, at most 255 characters.
def Ask.repo_ok.v2(+p: String) -> Bool:
  Bool.not(String.is_empty(p)) && G.Gram.name(p)

# A sha256 digest: "sha256:" and 64 lowercase hex digits, 71 characters.
def Ask.digest_ok.v2(+d: String) -> Bool:
  Nat.is_eq(String.length(d), 71n) && Maybe.is_some(&2, G.Digest, G.Gram.digest(d))

# Every field of an ask is well formed.
def Ask.valid.v2(a: Ask) -> Bool:
  match a:
    case Ask{r, p, m, l, c}:
      Ask.registry_ok.v2(r) && Ask.repo_ok.v2(p) && Ask.digest_ok.v2(m) && Ask.digest_ok.v2(l) && Ask.digest_ok.v2(c)

def Ask.keep(ok: Bool, a: Ask) -> Maybe<&2, Ask>:
  match ok:
    case True{}:
      Some{a}
    case False{}:
      None{}

def Ask.check(+a: Ask) -> Maybe<&2, Ask>:
  Ask.keep(Ask.valid.v2(a), a)

# From labels
# -----------

def Ask.of_img(m: Maybe<&2, P.Img>, +man: String, +lay: String, +chain: String) -> Maybe<&2, Ask>:
  match m:
    case None{}:
      None{}
    case Some{P.Img{r, p, f, d}}:
      Ask.check(Ask{r, p, man, lay, chain})

def Ask.of_set(+ls: List<&2, S.Label>) -> Maybe<&2, Ask>:
  Ask.of_img(P.Pull.ref(S.Sn.lget(ls, Ask.label.ref.v2())), S.Sn.lget(ls, Ask.label.manifest.v2()),
    S.Sn.lget(ls, Ask.label.layer.v2()), S.Sn.lget(ls, Ask.label.chain.v2()))

# The ask for a snapshotter call: only a Prepare of a layer the store
# does not hold (present is the host's probe, src/layers/pb.bend
# Spb.probe) asks. None for any other call (a View never unpacks a
# layer), when the store has the layer, and when a label is missing or
# not well formed, or the image's registry is not one the image cache
# serves; then the snapshotter goes straight to the local unpack.
def Ask.of_labels.v2(op: S.Op, present: Bool) -> Maybe<&2, Ask>:
  match op present:
    case S.OPrepare{k, p, ls} False{}:
      Ask.of_set(S.Sn.labels(ls))
    case _ _:
      None{}

# The wire
# --------

# The most bytes an ask line takes, its "\n" included. The longest valid
# ask is 492: "ask " 4, registry 15 ("registry.k8s.io"), repository 255,
# three digests of 71, four spaces and the "\n".
def Ask.line_max.v2() -> Nat:
  512n

# The ask's line, "\n" included.
def Ask.render.v2(a: Ask) -> String:
  match a:
    case Ask{r, p, m, l, c}:
      "ask " ++ r ++ " " ++ p ++ " " ++ m ++ " " ++ l ++ " " ++ c ++ "\n"

def Ask.parse.word(ok: Bool, +a: Ask) -> Maybe<&2, Ask>:
  match ok:
    case True{}:
      Ask.check(a)
    case False{}:
      None{}

def Ask.parse.fields(fs: List<&2, String>) -> Maybe<&2, Ask>:
  match fs:
    case Con{+w, Con{r, Con{p, Con{m, Con{l, Con{c, Nil{}}}}}}}:
      Ask.parse.word(String.eq(w, "ask"), Ask{r, p, m, l, c})
    case _:
      None{}

def Ask.line.end(ok: Bool, l: String) -> Maybe<&2, String>:
  match ok:
    case True{}:
      Some{l}
    case False{}:
      None{}

# The text of a line that is exactly one "\n"-ended line.
def Ask.line.cut(ls: List<&2, String>) -> Maybe<&2, String>:
  match ls:
    case Con{l, Con{+e, Nil{}}}:
      Ask.line.end(String.is_empty(e), l)
    case _:
      None{}

def Ask.line.if(ok: Bool, s: String) -> Maybe<&2, String>:
  match ok:
    case True{}:
      Ask.line.cut(String.split(s, '\n'))
    case False{}:
      None{}

# The text of one "\n"-ended line of at most max bytes, else None.
def Ask.line(+max: Nat, +s: String) -> Maybe<&2, String>:
  Ask.line.if(Nat.is_le(String.length(s), max), s)

def Ask.parse.line(m: Maybe<&2, String>) -> Maybe<&2, Ask>:
  match m:
    case None{}:
      None{}
    case Some{l}:
      Ask.parse.fields(String.split(l, ' '))

# An ask read from the guest, strictly: one "\n"-ended line of at most
# Ask.line_max.v2 bytes, the word "ask" and five fields that pass
# Ask.valid.v2, one space apart. Anything else is None.
def Ask.parse.v2(+s: String) -> Maybe<&2, Ask>:
  Ask.parse.line(Ask.line(Ask.line_max.v2(), s))

# Replies
# -------

# The filler's answer: the store already held the layer, the filler
# published it, or it did not (a short reason, for the node's log).
type Reply is Data:
  RPresent{}
  RPublished{}
  RNo{why: String}

# The most characters of a reason.
def Ask.why_max.v2() -> Nat:
  80n

# The most bytes a reply line takes, its "\n" included.
def Ask.reply_max.v2() -> Nat:
  84n

# A printable ASCII character (space to "~").
def Ask.printable(c: Char) -> Bool:
  match c:
    case Chr{+x}:
      U32.is_ge(x, 32) && U32.is_le(x, 126)

def Ask.clean.char(ok: Bool, c: Char) -> Char:
  match ok:
    case True{}:
      c
    case False{}:
      '?'

def Ask.clean(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+c, t}:
      SCon{Ask.clean.char(Ask.printable(c), c), Ask.clean(t)}

def Ask.why.or(e: Bool, +s: String) -> String:
  match e:
    case True{}:
      "fill failed"
    case False{}:
      s

# A reason fit for the wire: printable ASCII (anything else becomes
# "?"), at most Ask.why_max.v2 characters, never empty.
def Ask.why.v2(+e: String) -> String:
  +s : String = String.take(Ask.clean(e), Ask.why_max.v2())
  Ask.why.or(String.is_empty(s), s)

def Ask.reply.err(m: Maybe<&2, String>) -> Reply:
  match m:
    case None{}:
      RPublished{}
    case Some{e}:
      RNo{Ask.why.v2(e)}

# The filler's answer to an ask: had is whether the store held the
# layer before the fill; err is the fill's error, None when it
# published the layer.
def Ask.reply.v2(had: Bool, err: Maybe<&2, String>) -> Reply:
  match had:
    case True{}:
      RPresent{}
    case False{}:
      Ask.reply.err(err)

# The reply's line, "\n" included.
def Ask.reply.render.v2(r: Reply) -> String:
  match r:
    case RPresent{}:
      "ok present\n"
    case RPublished{}:
      "ok published\n"
    case RNo{w}:
      "no " ++ w ++ "\n"

def Ask.printable_all(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      Ask.printable(c) && Ask.printable_all(t)

def Ask.reply.no(ok: Bool, w: String) -> Maybe<&2, Reply>:
  match ok:
    case True{}:
      Some{RNo{w}}
    case False{}:
      None{}

def Ask.reply.why(+w: String) -> Maybe<&2, Reply>:
  Ask.reply.no(Bool.not(String.is_empty(w)) && Nat.is_le(String.length(w), Ask.why_max.v2()) && Ask.printable_all(w), w)

def Ask.reply.text(+l: String) -> Maybe<&2, Reply>:
  Bool.pick(Maybe<&2, Reply>, String.eq(l, "ok present"), Some{RPresent{}},
    Bool.pick(Maybe<&2, Reply>, String.eq(l, "ok published"), Some{RPublished{}},
      Bool.pick(Maybe<&2, Reply>, String.starts_with(l, "no "), Ask.reply.why(String.drop(l, 3n)), None{})))

def Ask.reply.line(m: Maybe<&2, String>) -> Maybe<&2, Reply>:
  match m:
    case None{}:
      None{}
    case Some{l}:
      Ask.reply.text(l)

# A reply read from the filler, strictly: one "\n"-ended line of at most
# Ask.reply_max.v2 bytes, "ok present", "ok published", or "no " and a
# reason of 1 to Ask.why_max.v2 printable ASCII characters. Anything
# else is None, and the guest treats None as a "no".
def Ask.reply.parse.v2(+s: String) -> Maybe<&2, Reply>:
  Ask.reply.line(Ask.line(Ask.reply_max.v2(), s))

# Where and how long
# ------------------

# The address a guest reaches the host's loopback on (bend-vmm's NAT
# gateway; the image cache's mirrors use it too, Plan.hosts_toml).
def Ask.host.v2() -> String:
  "10.0.2.2"

def Ask.host.pick(empty: Bool, +env: String) -> String:
  match empty:
    case True{}:
      Ask.host.v2()
    case False{}:
      env

# The filler's address as the node's PID 1 environment gives it
# (VK8S_LAYERS_ASK; v3): a node container on a Linux host reaches the
# filler at its bridge's gateway (src/cli/ctr.bend Ctr.layers_env); a VM
# names none and keeps Ask.host.v2.
def Ask.host.v3(+env: String) -> String:
  Ask.host.pick(String.is_empty(env), env)

# The filler's port on the host's loopback, one for every cluster (the
# daemon is host-global). Fixed, so a guest needs no configuration, and
# clear of every port vk8s uses: the image cache's 15001-15004, the
# API's 10000..12999 (Cli.port_from) and the ranges derived from it,
# 13000.. and 16000.. (classic), 16400.. (node host), 19000.. (join),
# 22000.., 25000.. and 28000..30999 (idle proxy, native host). It is
# below the ephemeral ranges the OS hands out to outgoing connections
# (Linux 32768-60999, macOS 49152-65535), so no client socket holds it.
def Ask.port.v2() -> U32:
  32000

# The longest a guest waits for a reply, in seconds; then it probes the
# store once more and unpacks locally when the layer is still missing. A
# fill of a large layer from a warm image cache takes seconds; a cold
# one is bounded so that a pull is never stuck behind the filler.
def Ask.wait.max.v2() -> U32:
  60

# The guest's side (work item W6)
# --------------------------------
#
# The node's snapshotter (host/snapshotter.bend, host/snapshot_ask.bend)
# asks for a Prepare that Ask.of_labels.v2 names, waits at most
# Ask.wait.ms.v2 for the reply, then probes the store again and goes on
# as it does without an ask: a layer the store now holds is answered
# AlreadyExists, any other is unpacked on the node. Every outcome (a
# reply, a "no", no reply in time, a refused connection, a line that is
# not a reply) ends in that probe, so a pull never fails because of the
# ask.

# The longest wait, in milliseconds, as IO.within takes it.
def Ask.wait.ms.v2() -> U32:
  (Ask.wait.max.v2() * 1000 : U32)

# Whether the guest has read all of a reply it will read: a "\n" came,
# or it holds Ask.reply_max.v2 bytes or more (then Ask.reply.parse.v2
# refuses it, and the guest stops reading).
def Ask.reply.whole.v2(+s: String) -> Bool:
  String.contains(s, "\n") || Nat.is_ge(String.length(s), Ask.reply_max.v2())

# What came of an ask, for the node's log: the reply's line without its
# "\n", or why there was none.
def Ask.said.v2(r: Result<&2, &2, String, Reply>) -> String:
  match r:
    case Fail{e}:
      "no reply: " ++ e
    case Done{RPresent{}}:
      "ok present"
    case Done{RPublished{}}:
      "ok published"
    case Done{RNo{w}}:
      "no " ++ w

def Ask.heard.of(m: Maybe<&2, Reply>) -> Result<&2, &2, String, Reply>:
  match m:
    case None{}:
      Fail{"the filler's answer is not a reply line"}
    case Some{r}:
      Done{r}

# The reply read from the filler, or why there is none (the line is not
# a reply).
def Ask.heard.v2(+text: String) -> Result<&2, &2, String, Reply>:
  Ask.heard.of(Ask.reply.parse.v2(text))
