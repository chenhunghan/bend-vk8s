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

# Starting the daemon
# -----------

law layers_serve.spawn.on:
  {V.Srv.spawn.v2("1", False{}) == True{} : Bool}

law layers_serve.spawn.taken:
  {V.Srv.spawn.v2("1", True{}) == False{} : Bool}

law layers_serve.spawn.unset:
  {V.Srv.spawn.v2("", False{}) == False{} : Bool}

law layers_serve.spawn.zero:
  {V.Srv.spawn.v2("0", False{}) == False{} : Bool}

# Whatever the port, the store off starts nothing.
law layers_serve.spawn.off:
  for taken: Bool
  {V.Srv.spawn.v2("", taken) == False{} : Bool}

law layers_serve.log:
  {V.Srv.log.v2("/home/u/.vk8s") == "/home/u/.vk8s/layers-serve.log" : String}

# Proposed: per-phase times of a fill (feat/layers-kvm-guard, work item
# W7 of docs/ref/explore-layers-autofill.md). The expected values follow
# the log format this item defines (src/layers/serve.bend, "Per-phase
# times of a fill"): ms between two Sys.wall readings (days, seconds of
# the day, microseconds), each read in whole ms, 0 when the clock went
# back; the phases fetch, decompress, unpack, fsync, rename in that
# order. A design of W7, not upstream behaviour.
# -----------

def layers_serve.fx.ph() -> V.Phases:
  V.Phases{1200, 35, 410, 18, 3}

# 1 s and 500 ms: 1000 + 750 - 250.
law layers_serve.ms.same_day:
  {V.Srv.ms.v2((20411, (3600, 250000)), (20411, (3601, 750000))) == 1500 : U32}

# Across midnight: 86399.9 s of day 20411 to 0.1 s of day 20412.
law layers_serve.ms.next_day:
  {V.Srv.ms.v2((20411, (86399, 900000)), (20412, (0, 100000))) == 200 : U32}

law layers_serve.ms.same:
  {V.Srv.ms.v2((20411, (3600, 250000)), (20411, (3600, 250000))) == 0 : U32}

# Each reading counts in whole ms: 5.999999 s to 6 s is 6000 - 5999.
law layers_serve.ms.whole_ms:
  {V.Srv.ms.v2((0, (5, 999999)), (0, (6, 0))) == 1 : U32}

# The clock set back gives 0, by seconds or within one second.
law layers_serve.ms.back_secs:
  {V.Srv.ms.v2((20411, (10, 0)), (20411, (9, 0))) == 0 : U32}

law layers_serve.ms.back_ms:
  {V.Srv.ms.v2((20411, (10, 500000)), (20411, (10, 400000))) == 0 : U32}

law layers_serve.ms.back_day:
  {V.Srv.ms.v2((20412, (0, 0)), (20411, (86399, 0))) == 0 : U32}

law layers_serve.phases.render:
  {V.Srv.phases.render.v2(layers_serve.fx.ph()) == "fetch 1200 ms, decompress 35 ms, unpack 410 ms, fsync 18 ms, rename 3 ms" : String}

law layers_serve.phases.zero_render:
  {V.Srv.phases.render.v2(V.Srv.phases.zero.v2()) == "fetch 0 ms, decompress 0 ms, unpack 0 ms, fsync 0 ms, rename 0 ms" : String}

law layers_serve.phases.total:
  {V.Srv.phases.total.v2(layers_serve.fx.ph()) == 1666 : U32}

law layers_serve.phases.add:
  {V.Srv.phases.add.v2(V.Phases{1, 2, 3, 4, 5}, V.Phases{10, 20, 30, 40, 50}) == V.Phases{11, 22, 33, 44, 55} : V.Phases}

law layers_serve.phases.add_zero:
  {V.Srv.phases.add.v2(V.Srv.phases.zero.v2(), layers_serve.fx.ph()) == layers_serve.fx.ph() : V.Phases}

law layers_serve.phases.line:
  {V.Srv.phases.line.v2(layers_serve.fx.l(), "published", layers_serve.fx.ph())
    == "sha256:9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0 published in 1666 ms: fetch 1200 ms, decompress 35 ms, unpack 410 ms, fsync 18 ms, rename 3 ms" : String}

law layers_serve.fill.line:
  {V.Srv.fill.line.v2(layers_serve.fx.k(), 2, 2500, layers_serve.fx.ph())
    == "docker.io/library/busybox@sha256:e6693c20186f837fc393390135d8a598a96a833917917789d63766cab6c59582: 2 layers in 2500 ms; summed over its layers: fetch 1200 ms, decompress 35 ms, unpack 410 ms, fsync 18 ms, rename 3 ms" : String}

# Proposed: the filler starts by default (v3, Cli.layers_on.v2).
law layers_serve.spawn_v3_unset:
  {V.Srv.spawn.v3("", False{}) == True{} : Bool}
law layers_serve.spawn_v3_zero:
  {V.Srv.spawn.v3("0", False{}) == False{} : Bool}
law layers_serve.spawn_v3_taken:
  {V.Srv.spawn.v3("", True{}) == False{} : Bool}
