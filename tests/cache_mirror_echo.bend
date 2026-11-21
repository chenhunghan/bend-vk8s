import Base
import ../host/cache/mirror.bend as MR
import ../src/oci/serve.bend as SV
import ../src/oci/size.bend as N

# The image cache's test program (host/cache/mirror.bend, the daemon of
# `vk8s cache serve`). tests/cache_mirror.sh builds it and runs
#
#   cache_mirror_echo serve ROOT
#
# which serves the store at ROOT on 127.0.0.1:15001-15004, as `vk8s
# cache serve` does with ROOT ~/.vk8s/cache/store, until the file
# ROOT.stop appears; VK8S_UPSTREAM points every registry at the test's
# stub.
#
# Run with no arguments (scripts/check.sh runs it so, on the JavaScript
# lane), it checks that a follower holds back the last byte of a fill
# that is not committed.

def Lane.line(ok: Bool) -> String:
  match ok:
    case True{}:
      "PASS cache_mirror_echo: a follower holds back the last byte until the fill is committed"
    case False{}:
      "FAIL cache_mirror_echo: a follower does not hold back the last byte"

def Lane.held(w: SV.Fw) -> Bool:
  match w:
    case SV.FwSend{N.Size{h, l}}:
      U32.is_eq(l, 9)
    case _:
      False{}

def Lane.check() -> IO(Unit):
  IO.print(Lane.line(Lane.held(SV.Serve.follow(N.Size.zero(), N.Size.of(10), N.Size.of(10), False{}))))

def main.go(args: List<String>) -> IO(Unit):
  match args:
    case [p, "serve", +root]:
      MR.Mir.main(root, root ++ ".stop")
    case _:
      Lane.check()

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    main.go(args)
