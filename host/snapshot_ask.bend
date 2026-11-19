import Base
import ../src/layers/ask.bend as A

# The node snapshotter's ask to the host's layer filler (docs/GOAL.md
# section 10, "the store fills itself"; work item W6 of
# docs/ref/explore-layers-autofill.md; the protocol is
# src/layers/ask.bend). One ask is one TCP connection to the filler
# (10.0.2.2:32000 from a VM node, Ask.host.v2 and Ask.port.v2): the
# guest sends the ask's line (Ask.render.v2), reads one reply line of at
# most Ask.reply_max.v2 bytes (Ask.reply.whole.v2) and closes.
#
# SnAsk.ask bounds the whole ask, connect included, with IO.within: a
# filler that does not answer, or a connect that does not end, gives up
# after ms milliseconds. IO.within does not cancel the loser: that
# computation keeps its socket until the filler answers or closes, and
# then closes it; the guest has already gone on. Bend effects only
# (TCP.connect, TCP.send, TCP.recv), no shell. tests/snapshot_ask.sh
# runs it against a fake filler (tests/snapshot_ask_echo.bend).

def SnAsk.close(s: Socket, r: Result<&2, &2, String, A.Reply>) -> IO(Result<&2, &2, String, A.Reply>):
  do IO<Result<&2, &2, String, A.Reply>>:
    Socket.close(s)
    return r

def SnAsk.read.if(whole: Bool, s: Socket, +all: String,
  again: Socket -> String -> IO(Socket & String)) -> IO(Socket & String):
  match whole:
    case True{}:
      IO.pure(Socket & String, (s, all))
    case False{}:
      again(s, all)

def SnAsk.read.more(s: Socket, +all: String,
  again: Socket -> String -> IO(Socket & String)) -> IO(Socket & String):
  SnAsk.read.if(A.Ask.reply.whole.v2(all), s, all, again)

def SnAsk.read.got(p: Socket & Result<&1, &1, U32 & String, Maybe<&1, String>>, +acc: String,
  again: Socket -> String -> IO(Socket & String)) -> IO(Socket & String):
  match p:
    case (s, Fail{e}):
      IO.pure(Socket & String, (s, acc))
    case (s, Done{None{}}):
      IO.pure(Socket & String, (s, acc))
    case (s, Done{Some{t}}):
      SnAsk.read.more(s, acc ++ t, again)

# Reads the reply: until a "\n" comes, Ask.reply_max.v2 bytes are in,
# the filler closes, or a receive fails. fuel bounds the receives.
def SnAsk.read(fuel: Nat, s: Socket, +acc: String) -> IO(Socket & String):
  match fuel:
    case 0n:
      IO.pure(Socket & String, (s, acc))
    case 1n+k:
      do IO<Socket & String>:
        p : Socket & Result<&1, &1, U32 & String, Maybe<&1, String>> <- TCP.recv(s, 128)
        SnAsk.read.got(p, acc, s2 => a2 => SnAsk.read(k, s2, a2))

def SnAsk.heard(q: Socket & String) -> IO(Result<&2, &2, String, A.Reply>):
  match q:
    case (s, text):
      SnAsk.close(s, A.Ask.heard.v2(text))

def SnAsk.why(e: U32 & String) -> String:
  match e:
    case (c, m):
      m

def SnAsk.sent(p: Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit>) -> IO(Result<&2, &2, String, A.Reply>):
  match p:
    case (s, Fail{(e, rest)}):
      SnAsk.close(s, Fail{"sending the ask: " ++ SnAsk.why(e)})
    case (s, Done{u}):
      do IO<Result<&2, &2, String, A.Reply>>:
        q : Socket & String <- SnAsk.read(96n, s, "")
        SnAsk.heard(q)

def SnAsk.conn(r: Result<&1, &1, U32 & String, Socket>, +line: String) -> IO(Result<&2, &2, String, A.Reply>):
  match r:
    case Fail{(c, m)}:
      IO.pure(Result<&2, &2, String, A.Reply>, Fail{"connecting to the filler: " ++ m})
    case Done{s}:
      do IO<Result<&2, &2, String, A.Reply>>:
        p : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send(s, line)
        SnAsk.sent(p)

# One ask with no bound in time: connect, send its line, read the reply.
def SnAsk.go(+host: String, +port: U32, a: A.Ask) -> IO(Result<&2, &2, String, A.Reply>):
  do IO<Result<&2, &2, String, A.Reply>>:
    r : Result<&1, &1, U32 & String, Socket> <- TCP.connect(host, port)
    SnAsk.conn(r, A.Ask.render.v2(a))

def SnAsk.late(m: Maybe<&1, Result<&2, &2, String, A.Reply>>, +ms: U32) -> Result<&2, &2, String, A.Reply>:
  match m:
    case None{}:
      Fail{"no reply within " ++ U32.show(ms) ++ " ms"}
    case Some{r}:
      r

# The ask a to the filler at host:port, waiting at most ms milliseconds:
# its reply, or why there is none (a refused or failed connection, a
# line that is not a reply, no reply in time).
def SnAsk.ask(+host: String, +port: U32, +ms: U32, a: A.Ask) -> IO(Result<&2, &2, String, A.Reply>):
  do IO<Result<&2, &2, String, A.Reply>>:
    m : Maybe<&1, Result<&2, &2, String, A.Reply>> <- IO.within(Result<&2, &2, String, A.Reply>, ms, SnAsk.go(host, port, a))
    return SnAsk.late(m, ms)
