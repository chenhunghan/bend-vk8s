import Base
import ../src/layers/pack.bend as K
import ../src/layers/snap.bend as S

# Tests for src/layers/pack.bend (vk8s's own design; the control lines
# and the table follow bend-vmm's README, "Packs: host files as one
# growing disk").

def report(name: String, got: String, want: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name ++ ": got " ++ got ++ ", want " ++ want)

def check(name: String, +got: String, +want: String) -> IO(Unit):
  report(name, got, want, String.eq(got, want))

def X.c() -> String:
  "sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1"

def X.d() -> String:
  "sha256:9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0"

def X.key() -> String:
  "k4082213511k27k3999000111"

def X.ask(m: Maybe<&2, K.PkAsk>) -> String:
  match m:
    case None{}:
      "<none>"
    case Some{a}:
      K.Pack.ask.render.v7(a)

def X.reply(m: Maybe<&2, K.PkReply>) -> String:
  match m:
    case None{}:
      "<none>"
    case Some{r}:
      K.Pack.reply.render.v7(r)

def X.json() -> String:
  "{\"state\":\"running\",\"exits\":[{\"cpu\":0,\"wfi\":3}],\"pack\":{\"name\":\"layers\",\"size\":3145728,\"entries\":["
    ++ "{\"offset\":0,\"length\":4096,\"path\":\"/h/.vk8s/layers/c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1.sqfs\",\"live\":true},"
    ++ "{\"offset\":1048576,\"length\":8192,\"path\":\"/h/.vk8s/layers/9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0.sqfs\",\"live\":false},"
    ++ "{\"offset\":2097152,\"length\":4096,\"path\":\"/h/.vk8s/layers/c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1.sqfs\",\"live\":true}]}}"

def main() -> IO(Unit):
  do IO<Unit>:
    check("vm of a control plane", K.Pack.vm.v7("/h/.vk8s", "/h/.vk8s/clusters/a-1/data.img"), "a-1")
    check("vm of a worker", K.Pack.vm.v7("/h/.vk8s", "/h/.vk8s/clusters/a-1/nodes/worker-3/data.img"), "a-1/nodes/worker-3")
    check("vm of another store", K.Pack.vm.v7("/h/.vk8s", "/other/.vk8s/clusters/a-1/data.img"), "")
    check("flags", String.join(K.Pack.flags.v7(True{}, "a", ["--mem", "2048", "--cmdline", "quiet VK8S_LAYERS=1", "--balloon", "auto"]), "|"),
      "--mem|2048|--pack|layers|--cmdline|quiet VK8S_LAYERS=1 VK8S_PACK=a|--balloon|auto")
    check("flags off", String.join(K.Pack.flags.v7(False{}, "a", ["--mem", "2048", "--cmdline", "quiet"]), "|"), "--mem|2048|--cmdline|quiet")
    check("pack round trip", X.ask(K.Pack.ask.parse.v7("pack a-1 " ++ X.key() ++ " " ++ X.c() ++ "\n")), "pack a-1 " ++ X.key() ++ " " ++ X.c() ++ "\n")
    check("drop round trip", X.ask(K.Pack.ask.parse.v7("drop a-1/nodes/worker-3 " ++ X.key() ++ " " ++ X.c() ++ "\n")),
      "drop a-1/nodes/worker-3 " ++ X.key() ++ " " ++ X.c() ++ "\n")
    check("vm with a slash at the end", X.ask(K.Pack.ask.parse.v7("pack a-1/ " ++ X.key() ++ " " ++ X.c() ++ "\n")), "<none>")
    check("vm that climbs", X.ask(K.Pack.ask.parse.v7("pack a-1/nodes/../.. " ++ X.key() ++ " " ++ X.c() ++ "\n")), "<none>")
    check("two spaces", X.ask(K.Pack.ask.parse.v7("pack a-1  " ++ X.key() ++ " " ++ X.c() ++ "\n")), "<none>")
    check("nul byte", X.ask(K.Pack.ask.parse.v7("pack a-1\0 " ++ X.key() ++ " " ++ X.c() ++ "\n")), "<none>")
    check("long line", X.ask(K.Pack.ask.parse.v7("pack " ++ String.repeat("a", 300n) ++ " " ++ X.key() ++ " " ++ X.c() ++ "\n")), "<none>")
    check("key of 65", X.ask(K.Pack.ask.parse.v7("pack a-1 " ++ String.repeat("k", 65n) ++ " " ++ X.c() ++ "\n")), "<none>")
    check("reply at", X.reply(K.Pack.reply.parse.v7("at 0 4096\n")), "at 0 4096\n")
    check("reply at, three numbers", X.reply(K.Pack.reply.parse.v7("at 0 4096 1\n")), "<none>")
    check("reply dropped", X.reply(K.Pack.reply.parse.v7("ok dropped\n")), "ok dropped\n")
    check("reply no", X.reply(K.Pack.reply.parse.v7("no pack add: error: no pack (start the VM with --pack NAME)\n")),
      "no pack add: error: no pack (start the VM with --pack NAME)\n")
    check("reply junk", X.reply(K.Pack.reply.parse.v7("yes\n")), "<none>")
    check("a reason with a line end", K.Pack.reply.render.v7(K.Pack.no.v7("a\nb")), "no a?b\n")
    check("added", X.reply(K.Pack.ctl.added.v7("3145728 4096")), "at 3145728 4096\n")
    check("added, an error", X.reply(K.Pack.ctl.added.v7("error: cannot open /x (errno 13)")), "<none>")
    check("drop offsets", String.join(K.Pack.offsets.v7(K.Pack.table.v7(X.json()), "/h/.vk8s/layers/c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1.sqfs"), ","), "0,2097152")
    check("drop offsets of a dropped one", String.join(K.Pack.offsets.v7(K.Pack.table.v7(X.json()), "/h/.vk8s/layers/9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0.sqfs"), ","), "")
    check("live chains", String.join(K.Pack.chains.v7(K.Pack.table.v7(X.json()), "/h/.vk8s"), ","), X.c() ++ "," ++ X.c())
    check("live chains of another store", String.join(K.Pack.chains.v7(K.Pack.table.v7(X.json()), "/g/.vk8s"), ","), "")
    check("gone", String.join(K.Pack.gone.v7([S.ARelease{X.c(), "n/a"}, S.ARelease{X.d(), "n/b"}], [X.d()]), ","), X.c())
    check("guest", K.Pack.guest.v7("a-1/nodes/worker-3"), "a-1/nodes/worker-3")
    check("guest, a path", K.Pack.guest.v7("a-1/../b"), "")
