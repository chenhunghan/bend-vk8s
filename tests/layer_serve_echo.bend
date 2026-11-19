import Base
import ../host/layers/serve.bend as LS
import ../src/layers/serve.bend as SV
import ../src/layers/ask.bend as A
import ../src/layers/tar.bend as T

# The layer filler's test program (host/layers/serve.bend, the daemon of
# `vk8s layers serve`). tests/layers_serve.sh builds it and runs
#
#   layer_serve_echo serve ROOT PORT ARCH
#
# which serves the store at ROOT on 127.0.0.1:PORT for linux/ARCH, as
# `vk8s layers serve` does on Ask.port.v2 with ROOT ~/.vk8s; the image
# cache is asked on its usual ports (Plan.mirrors: 15001 for docker.io).
#
# Run with no arguments (scripts/check.sh runs it so, on the JavaScript
# lane), it checks that the daemon's own answers read back as replies.

def Lane.line(ok: Bool) -> String:
  match ok:
    case True{}:
      "PASS layer_serve_echo: the filler's busy and bad answers read back as replies"
    case False{}:
      "FAIL layer_serve_echo: the filler's busy or bad answer does not read back"

def Lane.ok(m: Maybe<&2, A.Reply>) -> Bool:
  match m:
    case Some{A.RNo{w}}:
      True{}
    case _:
      False{}

def Lane.check() -> IO(Unit):
  IO.print(Lane.line(Lane.ok(A.Ask.reply.parse.v2(A.Ask.reply.render.v2(SV.Srv.busy.v2())))
    && Lane.ok(A.Ask.reply.parse.v2(A.Ask.reply.render.v2(SV.Srv.bad.v2())))))

def main.go(args: List<String>) -> IO(Unit):
  match args:
    case [p, "serve", root, port, arch]:
      LS.Ls.main(root, arch, Maybe.default(&2, U32, T.Tar.dec32(port), 0))
    case _:
      Lane.check()

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    main.go(args)
