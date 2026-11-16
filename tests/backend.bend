import Base
import ../src/cli/backend.bend as B

def T.check(+name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name)

def main() -> IO(Unit):
  do IO<Unit>:
    T.check("Linux intended default", String.eq(B.Backend.default_for("Linux"), "native"))
    T.check("macOS intended default", String.eq(B.Backend.default_for("Darwin"), "container"))
    T.check("Linux effective default stays vm", String.eq(B.Backend.effective("Linux", ""), "vm"))
    T.check("macOS effective default stays vm", String.eq(B.Backend.effective("Darwin", ""), "vm"))
    T.check("explicit container", String.eq(B.Backend.effective("Linux", "container"), "container"))
    T.check("reject unknown backend", Bool.not(B.Backend.valid("docker")))
