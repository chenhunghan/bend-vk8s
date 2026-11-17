import Base
import ../src/layers/store.bend as Y

# Tests for src/layers/store.bend. Chain IDs are Python hashlib sha256
# hex digests (image-spec: sha256 of "<parent chain ID> <diffID>").

def report(name: String, got: String, want: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name ++ ": got " ++ got ++ ", want " ++ want)

def check(name: String, +got: String, +want: String) -> IO(Unit):
  report(name, got, want, String.eq(got, want))

def T.opt(m: Maybe<&2, String>) -> String:
  match m:
    case None{}:
      "<none>"
    case Some{v}:
      v

def T.chains(ls: List<&2, Y.Layer>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{l, t}:
      Con{Y.Layer.chain(l), T.chains(t)}

def T.store() -> List<&2, Y.Layer>:
  [Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", ["n1/a"], 0},
   Y.Layer{"sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", [], 100},
   Y.Layer{"sha256:1fa549a8dd45ed584c6f33a2e664a8438cf281cc00aa267fe128f267eef4828e", "sha256:f689954fb7af136362b02e8784233f78128dfec4e779c95aae228115091a7bc4", "sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", [], 200000}]

def main() -> IO(Unit):
  do IO<Unit>:
    check("chain ids", String.join(Y.Lay.chains(["sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"]), " "),
      "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6")
    check("layer dir", T.opt(Y.Lay.dir("/var/lib/vk8s/layers-store", "sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6")),
      "/var/lib/vk8s/layers-store/layers/a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6")
    check("bad chain", T.opt(Y.Lay.mount("sha256:../x")), "<none>")
    check("gc drops the old free layer only", String.join(Y.Lay.gc.paths("/s", Y.Lay.gc.drop(T.store(), 300000)), " "),
      "/s/layers/a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6")
    check("gc keeps the held and the fresh", String.join(T.chains(Y.Lay.gc.keep(T.store(), 300000)), " "),
      "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 sha256:1fa549a8dd45ed584c6f33a2e664a8438cf281cc00aa267fe128f267eef4828e")
    check("released layer expires from its release", String.join(Y.Lay.gc.paths("/s", Y.Lay.gc.drop(Y.Lay.release(T.store(), "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "n1/a", 250000), 300000)), " "),
      "/s/layers/a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6")
