import Base
import ../host/layers/unpack.bend as U
import ../host/layers/fs.bend as L
import ../src/layers/pull.bend as P
import ../src/oci/size.bend as N

# The layer unpack pipeline's test program (host/layers/unpack.bend).
# tests/layers_unpack.sh builds it and runs
#
#   layer_unpack_echo ROOT BLOB MEDIA DIFF
#
# which unpacks the layer blob BLOB (media type MEDIA, diffID DIFF, the
# first layer of its image, so its chain ID is DIFF) into the store at
# ROOT, and prints how ("published", "present") or "error " and why.
#
# Run with no arguments (scripts/check.sh runs it so, through `bend` on
# the JavaScript lane) it only makes a directory under a missing one: the
# lane's stand-in must fail with ENOSYS (38), a native build with ENOENT
# (2).

def Lane.line(+c: U32) -> String:
  Bool.pick(String, U32.is_eq(c, 38), "PASS layer_unpack_echo: LayerFs.make answers ENOSYS (JavaScript lane)",
    Bool.pick(String, U32.is_eq(c, 2), "PASS layer_unpack_echo: LayerFs.make in a missing directory answers ENOENT (native lane)",
      "FAIL layer_unpack_echo: LayerFs.make answered errno " ++ U32.show(c)))

def Lane.said(r: L.LayerFs.Res(Unit)) -> IO(Unit):
  match r:
    case Fail{(c, m)}:
      IO.print(Lane.line(c))
    case Done{u}:
      IO.print("FAIL layer_unpack_echo: made a directory under a missing one")

def Lane.check() -> IO(Unit):
  do IO<Unit>:
    r : L.LayerFs.Res(Unit) <- L.LayerFs.make(L.LayerFs.dir(), "/nonexistent-vk8s-layer-test/a/b", [])
    Lane.said(r)

def Run.done(r: U.Lu.R(String)) -> IO(Unit):
  match r:
    case Done{how}:
      IO.print(how)
    case Fail{e}:
      IO.print("error " ++ e)

def Run.go(+root: String, +blob: String, +media: String, +diff: String) -> IO(Unit):
  do IO<Unit>:
    r : U.Lu.R(String) <- U.Lu.publish(root, 1763337600, P.Fill{diff, diff, "", P.Desc{media, diff, N.Size.zero()}, P.Pull.comp(media)}, blob)
    Run.done(r)

def main.go(args: List<String>) -> IO(Unit):
  match args:
    case [p, root, blob, media, diff]:
      Run.go(root, blob, media, diff)
    case _:
      Lane.check()

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    main.go(args)
