import Base
import ../src/layers/ask.bend as A
import ../src/layers/serve.bend as V

# Spec for src/layers/serve.bend: the choices of the host's layer
# filler, `vk8s layers serve`.
#
# Proposed: every law of this file is new (feat/layers-serve, work item
# W5 of docs/ref/explore-layers-autofill.md). Sources:
# - the ask, its bounds and the reply lines: the protocol of
#   src/layers/ask.bend as laws/layers_ask.bend pins it (Ask.line_max.v2
#   512, "ok present", "ok published", "no <reason>"), and the ask of
#   laws/layers_ask.bend's fixture;
# - the caps (4 fills, 64 waiting asks, 128 connections, 10 reads of
#   1000 ms), the image key and the two reasons of the filler's own: the
#   design of W5 (user decision), not upstream behaviour.

def layers_serve.fx.m() -> String:
  "sha256:e6693c20186f837fc393390135d8a598a96a833917917789d63766cab6c59582"

def layers_serve.fx.l() -> String:
  "sha256:9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0"

def layers_serve.fx.c() -> String:
  "sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1"

def layers_serve.fx.ask() -> A.Ask:
  A.Ask{"docker.io", "library/busybox", layers_serve.fx.m(), layers_serve.fx.l(), layers_serve.fx.c()}

def layers_serve.fx.k() -> String:
  "docker.io/library/busybox@sha256:e6693c20186f837fc393390135d8a598a96a833917917789d63766cab6c59582"

def layers_serve.fx.k2() -> String:
  "registry.k8s.io/pause@sha256:9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0"

# n asks (ids n-1 .. 0) waiting for the fill of key.
def layers_serve.fx.waits(n: Nat, +key: String) -> List<&2, V.Waiter>:
  match n:
    case 0n:
      Nil{}
    case 1n+(+p):
      Con{V.Waiter{U32.from_nat(p), key}, layers_serve.fx.waits(p, key)}

# Four fills run (the cap).
def layers_serve.fx.full() -> V.Srv:
  V.Srv{4, ["a", "b", "c", "d"], []}

# Three asks for one image: the first fills it, the two others wait.
def layers_serve.fx.three() -> V.Srv:
  V.Srv.take.v2(V.Srv.take.v2(V.Srv.take.v2(V.Srv.start.v2(), 1, layers_serve.fx.k()), 2, layers_serve.fx.k()), 3, layers_serve.fx.k())

# Bounds
# -----------

law layers_serve.cap:
  {V.Srv.cap.v2() == 4 : U32}

law layers_serve.wait_max:
  {V.Srv.wait_max.v2() == 64 : U32}

law layers_serve.open_max:
  {V.Srv.open_max.v2() == 128 : U32}

law layers_serve.reads:
  {V.Srv.reads.v2() == 10n : Nat}

law layers_serve.read_ms:
  {V.Srv.read_ms.v2() == 1000 : U32}

# One read takes one byte more than the longest ask line.
law layers_serve.read_max:
  {U32.to_nat(V.Srv.read_max.v2()) == 1n+A.Ask.line_max.v2() : Nat}

# Reading an ask
# -----------

law layers_serve.read.empty:
  {V.Srv.read.more.v2([]) == True{} : Bool}

law layers_serve.read.part:
  {V.Srv.read.more.v2([97, 115, 107, 32]) == True{} : Bool}

law layers_serve.read.newline:
  {V.Srv.read.more.v2([97, 115, 107, 10]) == False{} : Bool}

law layers_serve.read.newline_first:
  {V.Srv.read.more.v2([10, 97]) == False{} : Bool}

law layers_serve.read.at_max:
  {V.Srv.read.more.v2(List.replicate(U32, 512n, 97)) == True{} : Bool}

law layers_serve.read.over_max:
  {V.Srv.read.more.v2(List.replicate(U32, 513n, 97)) == False{} : Bool}

# The image of an ask
# -----------

law layers_serve.key:
  {V.Srv.key.v2(layers_serve.fx.ask()) == layers_serve.fx.k() : String}

# Asks for two layers of one image have one key.
law layers_serve.key.layer:
  for l: String
  for c: String
  {V.Srv.key.v2(A.Ask{"docker.io", "library/busybox", layers_serve.fx.m(), l, c}) == layers_serve.fx.k() : String}

# Connections
# -----------

law layers_serve.accept.start:
  {V.Srv.accept.v2(V.Srv.start.v2()) == True{} : Bool}

law layers_serve.accept.last:
  {V.Srv.accept.v2(V.Srv{127, [], []}) == True{} : Bool}

law layers_serve.accept.full:
  {V.Srv.accept.v2(V.Srv{128, [], []}) == False{} : Bool}

law layers_serve.accept.opened:
  {V.Srv.opened.v2(V.Srv.start.v2()) == V.Srv{1, [], []} : V.Srv}

law layers_serve.accept.closed:
  {V.Srv.closed.v2(V.Srv.opened.v2(V.Srv.start.v2())) == V.Srv.start.v2() : V.Srv}

law layers_serve.accept.closed_zero:
  {V.Srv.closed.v2(V.Srv.start.v2()) == V.Srv.start.v2() : V.Srv}

# Admission and dedupe
# -----------

# With nothing running, any ask fills its image.
law layers_serve.admit.start:
  for k: String
  {V.Srv.admit.v2(V.Srv.start.v2(), k) == V.SFill{} : V.Turn}

law layers_serve.admit.same_image:
  {V.Srv.admit.v2(V.Srv.take.v2(V.Srv.start.v2(), 1, layers_serve.fx.k()), layers_serve.fx.k()) == V.SJoin{} : V.Turn}

law layers_serve.admit.other_image:
  {V.Srv.admit.v2(V.Srv.take.v2(V.Srv.start.v2(), 1, layers_serve.fx.k()), layers_serve.fx.k2()) == V.SFill{} : V.Turn}

law layers_serve.admit.cap:
  {V.Srv.admit.v2(layers_serve.fx.full(), "e") == V.SBusy{} : V.Turn}

# At the cap, an ask for an image that a fill runs for still waits.
law layers_serve.admit.cap_join:
  {V.Srv.admit.v2(layers_serve.fx.full(), "c") == V.SJoin{} : V.Turn}

law layers_serve.admit.below_cap:
  {V.Srv.admit.v2(V.Srv{0, ["a", "b", "c"], []}, "e") == V.SFill{} : V.Turn}

law layers_serve.admit.wait_full:
  {V.Srv.admit.v2(V.Srv{0, ["a"], layers_serve.fx.waits(64n, "a")}, "a") == V.SBusy{} : V.Turn}

law layers_serve.admit.wait_last:
  {V.Srv.admit.v2(V.Srv{0, ["a"], layers_serve.fx.waits(63n, "a")}, "a") == V.SJoin{} : V.Turn}

law layers_serve.take.busy:
  {V.Srv.take.v2(layers_serve.fx.full(), 9, "e") == layers_serve.fx.full() : V.Srv}

law layers_serve.take.three:
  {layers_serve.fx.three() == V.Srv{0, [layers_serve.fx.k()], [V.Waiter{2, layers_serve.fx.k()}, V.Waiter{3, layers_serve.fx.k()}]} : V.Srv}

law layers_serve.woken.three:
  {V.Srv.woken.v2(V.Srv.wait(layers_serve.fx.three()), layers_serve.fx.k()) == [2, 3] : List<&2, U32>}

law layers_serve.woken.other:
  {V.Srv.woken.v2(V.Srv.wait(layers_serve.fx.three()), layers_serve.fx.k2()) == [] : List<&2, U32>}

law layers_serve.done.three:
  {V.Srv.done.v2(layers_serve.fx.three(), layers_serve.fx.k()) == V.Srv.start.v2() : V.Srv}

# After its fill ended, the next ask for the image fills it again.
law layers_serve.done.again:
  {V.Srv.admit.v2(V.Srv.done.v2(layers_serve.fx.three(), layers_serve.fx.k()), layers_serve.fx.k()) == V.SFill{} : V.Turn}

law layers_serve.done.others:
  {V.Srv.done.v2(V.Srv{2, ["a", "b"], [V.Waiter{1, "b"}, V.Waiter{2, "a"}, V.Waiter{3, "b"}]}, "b")
    == V.Srv{2, ["a"], [V.Waiter{2, "a"}]} : V.Srv}

law layers_serve.done.others_woken:
  {V.Srv.woken.v2([V.Waiter{1, "b"}, V.Waiter{2, "a"}, V.Waiter{3, "b"}], "b") == [1, 3] : List<&2, U32>}

# Replies
# -----------

law layers_serve.reply.had:
  for after: Bool
  for e: Maybe<&2, String>
  {V.Srv.reply.v2(True{}, after, e) == A.RPresent{} : A.Reply}

law layers_serve.reply.after:
  for e: Maybe<&2, String>
  {V.Srv.reply.v2(False{}, True{}, e) == A.RPublished{} : A.Reply}

law layers_serve.reply.failed:
  {V.Srv.reply.v2(False{}, False{}, Some{"dial tcp 127.0.0.1:15001: connection refused"}) == A.RNo{"dial tcp 127.0.0.1:15001: connection refused"} : A.Reply}

law layers_serve.reply.not_in_image:
  {V.Srv.reply.v2(False{}, False{}, None{}) == A.RNo{"the image has no such layer"} : A.Reply}

law layers_serve.reply.failed_long:
  {V.Srv.reply.v2(False{}, False{}, Some{String.repeat("x", 100n)}) == A.RNo{String.repeat("x", 80n)} : A.Reply}

law layers_serve.reply.bad:
  {A.Ask.reply.render.v2(V.Srv.bad.v2()) == "no not a valid ask\n" : String}

law layers_serve.reply.busy:
  {A.Ask.reply.render.v2(V.Srv.busy.v2()) == "no the filler is busy\n" : String}

# A guest reads each of the filler's own answers back (Ask.reply.parse.v2).
law layers_serve.reply.bad_reads:
  {A.Ask.reply.parse.v2(A.Ask.reply.render.v2(V.Srv.bad.v2())) == Some{V.Srv.bad.v2()} : Maybe<&2, A.Reply>}

law layers_serve.reply.busy_reads:
  {A.Ask.reply.parse.v2(A.Ask.reply.render.v2(V.Srv.busy.v2())) == Some{V.Srv.busy.v2()} : Maybe<&2, A.Reply>}

law layers_serve.reply.not_in_image_reads:
  {A.Ask.reply.parse.v2(A.Ask.reply.render.v2(V.Srv.reply.v2(False{}, False{}, None{}))) == Some{A.RNo{"the image has no such layer"}} : Maybe<&2, A.Reply>}
