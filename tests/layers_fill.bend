import Base
import ../src/layers/fill.bend as F
import ../src/layers/tar.bend as T
import ../src/layers/store.bend as Y
import ../src/oci/size.bend as N

# Tests for src/layers/fill.bend. Offsets follow POSIX ustar (a 512-byte
# header, then the data in whole blocks).

def report(name: String, got: String, want: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name ++ ": got " ++ got ++ ", want " ++ want)

def check(name: String, +got: String, +want: String) -> IO(Unit):
  report(name, got, want, String.eq(got, want))

def X.opt(m: Maybe<&2, String>) -> String:
  match m:
    case None{}:
      "<none>"
    case Some{v}:
      v

def X.plan(r: Result<&2, &2, String, List<&2, F.Op>>) -> String:
  match r:
    case Fail{e}:
      "fail " ++ e
    case Done{os}:
      "ok" ++ F.Fill.show.ops(os)

def X.bool(b: Bool) -> String:
  match b:
    case True{}:
      "yes"
    case False{}:
      "no"

def X.layer(m: Maybe<&2, Y.Layer>) -> String:
  match m:
    case None{}:
      "<none>"
    case Some{l}:
      F.Fill.rec.render(l)

def X.halves(p: List<&2, String> & List<&2, String>) -> String:
  match p:
    case (a, b):
      String.join(a, ",") ++ "|" ++ String.join(b, ",")

def X.chains(ls: List<&2, Y.Layer>) -> String:
  match ls:
    case Nil{}:
      ""
    case Con{l, t}:
      Y.Layer.chain(l) ++ ";" ++ X.chains(t)

def main() -> IO(Unit):
  do IO<Unit>:
    check("blocks past 4 GiB", N.Size.show(F.Fill.blocks(N.Size{0, 4294967295})), "4294967296")
    check("empty archive", X.plan(F.Fill.plan("/t", [])), "ok")
    check("zero blocks", X.plan(F.Fill.plan("/t", List.replicate(U32, 1024n, 0))), "ok")
    check("part of a block", X.plan(F.Fill.plan("/t", List.replicate(U32, 100n, 1))), "fail tar: unexpected end of archive")
    check("skip a member", F.Fill.show(F.Fill.act(T.SSkip{T.Tar.start(), N.Size{0, 1025}}, N.Size{0, 512}, "/t")), "head 2048")
    check("record round trip", X.layer(F.Fill.rec.parse(F.Fill.rec.render(F.Fill.rec.new("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", 1763337600)))),
      "layer-meta 1\nchain sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\ndiff sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nparent \nlast-use 1763337600\n")
    check("record path", X.opt(F.Fill.rec.path("/home/u/.vk8s", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")),
      "/home/u/.vk8s/layer-refs/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    check("stale tmp", X.bool(F.Fill.stale("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.42.rec", 1000, 90000)), "yes")
    check("fresh tmp", X.bool(F.Fill.stale("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.42", 80000, 90000)), "no")
    check("layer lock path", X.opt(F.Fill.llock.path.v2("/home/u/.vk8s", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")),
      "/home/u/.vk8s/layer-locks/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    check("layer lock an hour old", X.bool(F.Fill.llock.stale.v2(Some{"1000\n"}, 4600)), "yes")
    check("gc v2 skips locked, keeps held", X.chains(F.Fill.gc.plan.v2([
      Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", "", [], 0},
      Y.Layer{"sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "", "", [], 0},
      Y.Layer{"sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "", "", [], 0}],
      ["sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"],
      ["sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6"], 300000)),
      "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad;")
    check("split even", X.halves(F.Fill.split.v2(["a", "b", "c", "d"])), "a,b|c,d")
    check("split odd", X.halves(F.Fill.split.v2(["a", "b", "c", "d", "e"])), "a,b|c,d,e")
    check("split empty", X.halves(F.Fill.split.v2([])), "|")
    check("present v2 dir", X.layer(F.Fill.present.v2(Some{F.Fill.rec.new("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", 7)}, F.StMode{16877})),
      "layer-meta 1\nchain sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\ndiff sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nparent \nlast-use 7\n")
    check("present v2 symlink", X.layer(F.Fill.present.v2(Some{F.Fill.rec.new("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", "", 7)}, F.StMode{41471})), "<none>")
