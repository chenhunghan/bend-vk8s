import Base
import ../host/snapshot_ask.bend as SA
import ../src/layers/ask.bend as A
import ../src/layers/snap.bend as S

# The node snapshotter's ask (host/snapshot_ask.bend) as a test program.
# tests/snapshot_ask.sh builds it and runs
#
#   snapshot_ask_echo HOST PORT MS
#
# against a fake filler on HOST:PORT: it builds the ask of an nginx
# layer's Prepare from containerd's CRI labels (Ask.of_labels.v2),
# sends it, waits at most MS milliseconds, and prints `said: ` and what
# came of it (Ask.said.v2).
#
# Run with no arguments (scripts/check.sh runs it so, through `bend` on
# the JavaScript lane) it asks 127.0.0.1:1, where nothing listens: a
# refused connection must come back as no reply, which the snapshotter
# then treats as a "no" (it probes the store again and unpacks on the
# node).

def Echo.m() -> String:
  "sha256:e6693c20186f837fc393390135d8a598a96a833917917789d63766cab6c59582"

def Echo.l() -> String:
  "sha256:9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0"

def Echo.c() -> String:
  "sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1"

def Echo.prepare() -> S.Op:
  S.OPrepare{"extract-1", "", [ S.Label{"containerd.io/snapshot/cri.image-ref", "docker.io/library/nginx:1.27"},
    S.Label{"containerd.io/snapshot/cri.manifest-digest", Echo.m()},
    S.Label{"containerd.io/snapshot/cri.layer-digest", Echo.l()},
    S.Label{"containerd.io/snapshot.ref", Echo.c()} ]}

def Echo.ask(+host: String, +port: U32, +ms: U32, m: Maybe<&2, A.Ask>) -> IO(Result<&2, &2, String, A.Reply>):
  match m:
    case None{}:
      IO.pure(Result<&2, &2, String, A.Reply>, Fail{"the Prepare does not ask"})
    case Some{a}:
      SA.SnAsk.ask(host, port, ms, a)

def Echo.run(+host: String, +port: U32, +ms: U32) -> IO(String):
  do IO<String>:
    r : Result<&2, &2, String, A.Reply> <- Echo.ask(host, port, ms, A.Ask.of_labels.v2(Echo.prepare(), False{}))
    return A.Ask.said.v2(r)

def Lane.line(+s: String) -> String:
  Bool.pick(String, String.starts_with(s, "no reply: connecting to the filler: "),
    "PASS snapshot_ask_echo: a refused ask comes back as no reply",
    "FAIL snapshot_ask_echo: a refused ask said: " ++ s)

def Lane.check() -> IO(Unit):
  do IO<Unit>:
    s : String <- Echo.run("127.0.0.1", 1, 2000)
    IO.print(Lane.line(s))

def main.go(args: List<String>) -> IO(Unit):
  match args:
    case [p, host, port, ms]:
      do IO<Unit>:
        s : String <- Echo.run(host, Maybe.default(&2, U32, U32.read(port), 0), Maybe.default(&2, U32, U32.read(ms), 1000))
        IO.print("said: " ++ s)
    case _:
      Lane.check()

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    main.go(args)
