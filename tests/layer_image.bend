import Base
import ../host/layers/image.bend as LI
import ../src/layers/fill.bend as F
import ../src/layers/sqfs.bend as Q
import ../src/oci/size.bend as N

# The layer image's test program (host/layers/image.bend). tests/layers_sqfs.sh
# builds it and runs
#
#   layer_image TAR IMG
#
# which writes the squashfs image of the layer tar TAR to the new file
# IMG, as a v3 fill does, and prints "OK <bytes> <inodes>" or
# "FAIL <why>". Run with no arguments (scripts/check.sh runs it so), it
# checks that an image's super block starts with the squashfs magic.

def Lane.line(ok: Bool) -> String:
  match ok:
    case True{}:
      "PASS layer_image: an image's super block starts with hsqs"
    case False{}:
      "FAIL layer_image: an image's super block does not start with hsqs"

def Lane.hsqs(bs: +List<U32>) -> Bool:
  match bs:
    case Con{a, Con{b, Con{c, Con{d, t}}}}:
      U32.is_eq(a, 104) && U32.is_eq(b, 115) && U32.is_eq(c, 113) && U32.is_eq(d, 115)
    case _:
      False{}

def Lane.sb(i: Q.Img) -> Bool:
  match i:
    case Q.Img{t, sb, e}:
      Lane.hsqs(sb)

def Lane.said(r: Result<&1, &1, String, F.Use>) -> String:
  match r:
    case Done{F.Use{N.Size{hi, lo}, n}}:
      "OK " ++ U32.show(lo) ++ " " ++ U32.show(n)
    case Fail{e}:
      "FAIL " ++ e

def main.go(args: List<String>) -> IO(Unit):
  match args:
    case [p, tar, img]:
      do IO<Unit>:
        r : Result<&1, &1, String, F.Use> <- LI.Li.of_tar(tar, img)
        IO.print(Lane.said(r))
    case _:
      IO.print(Lane.line(Lane.sb(Q.Sqfs.image([], 96))))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    main.go(args)
