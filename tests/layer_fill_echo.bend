import Base
import ../host/layers/unpack.bend as U
import ../host/layers/fill.bend as LF
import ../src/layers/pull.bend as P
import ../src/layers/tar.bend as T
import ../src/oci/size.bend as N

# The v2 fill and gc's test program (per-layer locks:
# host/layers/unpack.bend Lu.layer.v2, host/layers/fill.bend Lf.gc.at.v2).
# tests/layers_unpack.sh builds it and runs
#
#   layer_fill_echo fill ROOT BLOB MEDIA DIFF SIZE NOW
#
# which fills the layer blob BLOB (media type MEDIA, diffID DIFF, the
# first layer of its image, so its chain ID is DIFF; SIZE its size in
# bytes) into the store at ROOT under the layer's lock, with the clock
# fixed at NOW (seconds since 1970), and prints how ("published",
# "present") or "error " and why; and
#
#   layer_fill_echo gc ROOT NOW
#
# which runs gc v2 at NOW and prints what it said, then "ok" or "error "
# and why. The image cache is not asked: the blob is already a file.
#
# Run with no arguments (scripts/check.sh runs it so, through `bend` on
# the JavaScript lane) it fills a layer under a missing directory: the
# lane's stand-in must fail with ENOSYS (38), a native build with ENOENT
# (2).

def Lane.line(+e: String) -> String:
  Bool.pick(String, String.ends_with(e, "(errno 38)"), "PASS layer_fill_echo: Lu.layer.v2 answers ENOSYS (JavaScript lane)",
    Bool.pick(String, String.ends_with(e, "(errno 2)"), "PASS layer_fill_echo: Lu.layer.v2 under a missing directory answers ENOENT (native lane)",
      "FAIL layer_fill_echo: Lu.layer.v2 answered " ++ e))

def Lane.said(r: U.Lu.R(String)) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.print(Lane.line(e))
    case Done{how}:
      IO.print("FAIL layer_fill_echo: filled a layer under a missing directory")

def Run.fill(+d: String) -> P.Fill:
  P.Fill{d, d, "", P.Desc{"application/vnd.oci.image.layer.v1.tar+gzip", d, N.Size.zero()}, P.CGzip{}}

def Lane.check() -> IO(Unit):
  do IO<Unit>:
    r : U.Lu.R(String) <- U.Lu.layer.v2("/nonexistent-vk8s-layer-test/a/b", 7, 7,
      Run.fill("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"), IO.pure(U.Lu.R(String), Fail{"no blob"}))
    Lane.said(r)

def Run.done(r: U.Lu.R(String)) -> IO(Unit):
  match r:
    case Done{how}:
      IO.print(how)
    case Fail{e}:
      IO.print("error " ++ e)

def Run.gc.done(r: U.Lu.R(Unit)) -> IO(Unit):
  match r:
    case Done{u}:
      IO.print("ok")
    case Fail{e}:
      IO.print("error " ++ e)

def Run.num(+s: String) -> U32:
  Maybe.default(&2, U32, T.Tar.dec32(s), 0)

def Run.go(+root: String, +blob: String, +media: String, +diff: String, size: N.Size, +now: U32) -> IO(Unit):
  do IO<Unit>:
    r : U.Lu.R(String) <- U.Lu.layer.v2(root, now, now, P.Fill{diff, diff, "", P.Desc{media, diff, size}, P.Pull.comp(media)},
      IO.pure(U.Lu.R(String), Done{blob}))
    Run.done(r)

def Run.gc(+root: String, +now: U32) -> IO(Unit):
  do IO<Unit>:
    r : U.Lu.R(Unit) <- LF.Lf.gc.at.v2(root, now)
    Run.gc.done(r)

def main.go(args: List<String>) -> IO(Unit):
  match args:
    case [p, "fill", root, blob, media, diff, size, now]:
      Run.go(root, blob, media, diff, Maybe.default(&2, N.Size, N.Size.read(size), N.Size.zero()), Run.num(now))
    case [p, "gc", root, now]:
      Run.gc(root, Run.num(now))
    case _:
      Lane.check()

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    main.go(args)
