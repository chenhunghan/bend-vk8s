import Base
import ./ask.bend as A
import ./store.bend as Y

# The host's layer filler, `vk8s layers serve` (GOAL section 10, "the
# store fills itself"; work item W5 of docs/ref/explore-layers-autofill.md).
# One daemon per host listens on 127.0.0.1:Ask.port.v2 (a guest reaches it
# as 10.0.2.2, src/layers/ask.bend), reads one ask a connection
# (Ask.parse.v2), and fills the layers of the asked image, by its
# manifest digest, from the image cache (host/layers/fill.bend, per-layer
# locks). Pure: these defs choose; host/layers/serve.bend does the IO.
#
# Its main loop keeps one Srv: the connections open, the images a fill
# runs for, and the asks that wait for one of those fills. An ask names
# its image by Srv.key.v2 (registry, repository, manifest digest). Two
# asks for one image at once fill it once: the second one waits for the
# first one's fill (Srv.admit.v2 says SJoin), then answers from the store
# (dedupe in the daemon; across processes, the per-layer locks do it).
# Every bound is a cap on what any pod can make the host do: at most
# Srv.open_max.v2 connections, Srv.cap.v2 fills and Srv.wait_max.v2
# waiting asks at once; past a cap the answer is a "no" at once and the
# node unpacks the layer itself.

# The state of the filler's main loop: connections open, the keys of the
# images a fill runs for, and the asks waiting for one of those fills.
type Waiter is Data:
  Waiter{id: U32, key: String}

type Srv is Data:
  Srv{open: U32, run: List<&2, String>, wait: List<&2, Waiter>}

# What the main loop says to an ask for an image the store lacks a layer
# of: fill the image, wait for the fill that runs for it, or answer no
# (a cap is reached).
type Turn is Data:
  SFill{}
  SJoin{}
  SBusy{}

# Bounds
# ------

# Image fills at once (each fills its layers in two halves at once:
# Fill.split.v2).
def Srv.cap.v2() -> U32:
  4

# Asks waiting at once for a fill another ask started.
def Srv.wait_max.v2() -> U32:
  64

# Connections open at once.
def Srv.open_max.v2() -> U32:
  128

# Reads of an ask line, and how long each waits, in ms: a peer that has
# not sent its line within Srv.reads.v2 reads of Srv.read_ms.v2 each is
# answered no.
def Srv.reads.v2() -> Nat:
  10n

def Srv.read_ms.v2() -> U32:
  1000

# The bytes one read of an ask takes: one more than Ask.line_max.v2, so a
# line that is too long is seen to be too long.
def Srv.read_max.v2() -> U32:
  513

# Whether to read more of an ask: no "\n" (10) yet and at most
# Ask.line_max.v2 bytes so far.
def Srv.newline(bs: List<&2, U32>) -> Bool:
  match bs:
    case Nil{}:
      False{}
    case Con{b, t}:
      U32.is_eq(b, 10) || Srv.newline(t)

def Srv.read.more.v2(+bs: List<&2, U32>) -> Bool:
  Bool.not(Srv.newline(bs)) && Nat.is_le(List.length(&2, U32, bs), A.Ask.line_max.v2())

# The state
# ---------

def Srv.start.v2() -> Srv:
  Srv{0, [], []}

def Srv.open(s: Srv) -> U32:
  match s:
    case Srv{o, r, w}:
      o

def Srv.run(s: Srv) -> List<&2, String>:
  match s:
    case Srv{o, r, w}:
      r

def Srv.wait(s: Srv) -> List<&2, Waiter>:
  match s:
    case Srv{o, r, w}:
      w

# The image an ask fills: registry, repository and manifest digest.
def Srv.key.v2(a: A.Ask) -> String:
  match a:
    case A.Ask{r, p, m, l, c}:
      r ++ "/" ++ p ++ "@" ++ m

# Whether one more connection may be served (else it is answered no).
def Srv.accept.v2(s: Srv) -> Bool:
  U32.is_lt(Srv.open(s), Srv.open_max.v2())

def Srv.opened.v2(s: Srv) -> Srv:
  match s:
    case Srv{o, r, w}:
      Srv{(o + 1 : U32), r, w}

def Srv.dec(+o: U32) -> U32:
  Bool.pick(U32, U32.is_zero(o), 0, (o - 1 : U32))

def Srv.closed.v2(s: Srv) -> Srv:
  match s:
    case Srv{o, r, w}:
      Srv{Srv.dec(o), r, w}

def Srv.join(full: Bool) -> Turn:
  match full:
    case True{}:
      SBusy{}
    case False{}:
      SJoin{}

def Srv.fill(room: Bool) -> Turn:
  match room:
    case True{}:
      SFill{}
    case False{}:
      SBusy{}

def Srv.admit.go(running: Bool, +s: Srv) -> Turn:
  match running:
    case True{}:
      Srv.join(Nat.is_le(U32.to_nat(Srv.wait_max.v2()), List.length(&2, Waiter, Srv.wait(s))))
    case False{}:
      Srv.fill(Nat.is_lt(List.length(&2, String, Srv.run(s)), U32.to_nat(Srv.cap.v2())))

# What an ask for image key gets: SJoin when a fill runs for it (SBusy
# when Srv.wait_max.v2 asks wait already), else SFill when fewer than
# Srv.cap.v2 fills run, else SBusy.
def Srv.admit.v2(+s: Srv, +key: String) -> Turn:
  Srv.admit.go(Y.Lay.holds(Srv.run(s), key), s)

def Srv.took(t: Turn, s: Srv, +id: U32, +key: String) -> Srv:
  match t:
    case SFill{}:
      match s:
        case Srv{o, r, w}:
          Srv{o, Con{key, r}, w}
    case SJoin{}:
      match s:
        case Srv{o, r, w}:
          Srv{o, r, List.append(&2, Waiter, w, [Waiter{id, key}])}
    case SBusy{}:
      s

# The state after ask id for image key got Srv.admit.v2: its fill runs,
# or it waits (after those that wait already), or nothing changed.
def Srv.take.v2(+s: Srv, +id: U32, +key: String) -> Srv:
  Srv.took(Srv.admit.v2(s, key), s, id, key)

def Srv.drop.put(hit: Bool, +x: String, rest: List<&2, String>) -> List<&2, String>:
  match hit:
    case True{}:
      rest
    case False{}:
      Con{x, rest}

def Srv.drop(xs: List<&2, String>, +key: String) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, t}:
      Srv.drop.put(String.eq(x, key), x, Srv.drop(t, key))

def Srv.unwait.put(hit: Bool, w: Waiter, rest: List<&2, Waiter>) -> List<&2, Waiter>:
  match hit:
    case True{}:
      rest
    case False{}:
      Con{w, rest}

def Srv.wkey(w: Waiter) -> String:
  match w:
    case Waiter{i, k}:
      k

def Srv.wid(w: Waiter) -> U32:
  match w:
    case Waiter{i, k}:
      i

def Srv.unwait(ws: List<&2, Waiter>, +key: String) -> List<&2, Waiter>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{+w, t}:
      Srv.unwait.put(String.eq(Srv.wkey(w), key), w, Srv.unwait(t, key))

def Srv.woken.put(hit: Bool, +i: U32, rest: List<&2, U32>) -> List<&2, U32>:
  match hit:
    case True{}:
      Con{i, rest}
    case False{}:
      rest

# The asks that wait for the fill of image key, in the order they came.
def Srv.woken.v2(ws: List<&2, Waiter>, +key: String) -> List<&2, U32>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{+w, t}:
      Srv.woken.put(String.eq(Srv.wkey(w), key), Srv.wid(w), Srv.woken.v2(t, key))

# The state after the fill of image key ended: it runs no more and its
# waiting asks (Srv.woken.v2, read before) wait no more.
def Srv.done.v2(s: Srv, +key: String) -> Srv:
  match s:
    case Srv{o, r, w}:
      Srv{o, Srv.drop(r, key), Srv.unwait(w, key)}

# Replies
# -------

# A line that is not an ask.
def Srv.bad.v2() -> A.Reply:
  A.RNo{"not a valid ask"}

# A cap is reached.
def Srv.busy.v2() -> A.Reply:
  A.RNo{"the filler is busy"}

def Srv.why(e: Maybe<&2, String>) -> Maybe<&2, String>:
  match e:
    case None{}:
      Some{"the image has no such layer"}
    case Some{w}:
      Some{w}

def Srv.err(after: Bool, e: Maybe<&2, String>) -> Maybe<&2, String>:
  match after:
    case True{}:
      None{}
    case False{}:
      Srv.why(e)

# The answer to an ask: had is whether the store held the layer before,
# after whether it holds it after the fill (its own or the one it waited
# for), err the fill's error. The layer there after is published, even
# when another layer of the image failed; a layer still missing after a
# fill that ended well is not one of the image's.
def Srv.reply.v2(had: Bool, after: Bool, err: Maybe<&2, String>) -> A.Reply:
  A.Ask.reply.v2(had, Srv.err(after, err))

# Starting the daemon
# -------------------

# Whether `vk8s create` starts the filler: the store is on (VK8S_LAYERS=1,
# as Cli.layers_on reads it) and nothing listens on Ask.port.v2 yet (the
# daemon is host-global: one that runs, or any program that holds the
# port, is left alone).
def Srv.spawn.v2(+env: String, taken: Bool) -> Bool:
  String.eq(env, "1") && Bool.not(taken)

# The daemon's log, under the store's root (~/.vk8s).
def Srv.log.v2(+root: String) -> String:
  root ++ "/layers-serve.log"
