import Base
import ../src/layers/ask.bend as A
import ../src/layers/snap.bend as S

# Tests for src/layers/ask.bend. Label names and values follow containerd
# v2.2.3 pkg/snapshotters/annotations.go; digests are busybox's
# (distribution/reference normalize_test.go) and image-spec manifest.md's
# and config.md's examples.

def report(name: String, got: String, want: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name ++ ": got " ++ got ++ ", want " ++ want)

def check(name: String, +got: String, +want: String) -> IO(Unit):
  report(name, got, want, String.eq(got, want))

def X.ask(m: Maybe<&2, A.Ask>) -> String:
  match m:
    case None{}:
      "<none>"
    case Some{a}:
      A.Ask.render.v2(a)

def X.reply(m: Maybe<&2, A.Reply>) -> String:
  match m:
    case None{}:
      "<none>"
    case Some{r}:
      A.Ask.reply.render.v2(r)

def X.m() -> String:
  "sha256:e6693c20186f837fc393390135d8a598a96a833917917789d63766cab6c59582"

def X.l() -> String:
  "sha256:9834876dcfb05cb167a5c24953eba58c4ac89b1adf57f28f2f9d09af107ee8f0"

def X.c() -> String:
  "sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1"

def X.tail() -> String:
  " " ++ X.m() ++ " " ++ X.l() ++ " " ++ X.c() ++ "\n"

def X.labels(ref: String) -> List<&2, S.Label>:
  [ S.Label{"containerd.io/snapshot/cri.image-ref", ref},
    S.Label{"containerd.io/snapshot/cri.manifest-digest", X.m()},
    S.Label{"containerd.io/snapshot/cri.layer-digest", X.l()},
    S.Label{"containerd.io/snapshot.ref", X.c()} ]

def X.prepare(ref: String) -> S.Op:
  S.OPrepare{"extract-1", "", X.labels(ref)}

def main() -> IO(Unit):
  do IO<Unit>:
    check("prepare asks", X.ask(A.Ask.of_labels.v2(X.prepare("docker.io/library/nginx:1.27"), False{})),
      "ask docker.io library/nginx" ++ X.tail())
    check("quay image asks", X.ask(A.Ask.of_labels.v2(X.prepare("quay.io/prometheus/node-exporter:v1.8.2"), False{})),
      "ask quay.io prometheus/node-exporter" ++ X.tail())
    check("present does not ask", X.ask(A.Ask.of_labels.v2(X.prepare("docker.io/library/nginx:1.27"), True{})), "<none>")
    check("view does not ask", X.ask(A.Ask.of_labels.v2(S.OView{"v", "p", X.labels("nginx")}, False{})), "<none>")
    check("private registry does not ask", X.ask(A.Ask.of_labels.v2(X.prepare("registry.example.com/team/app:1"), False{})), "<none>")
    check("round trip", X.ask(A.Ask.parse.v2("ask ghcr.io owner/app" ++ X.tail())), "ask ghcr.io owner/app" ++ X.tail())
    check("space in repo", X.ask(A.Ask.parse.v2("ask docker.io a b" ++ X.tail())), "<none>")
    check("trailing space", X.ask(A.Ask.parse.v2("ask docker.io library/nginx " ++ X.m() ++ " " ++ X.l() ++ " " ++ X.c() ++ " \n")), "<none>")
    check("nul byte", X.ask(A.Ask.parse.v2("ask docker.io library/nginx\0" ++ X.tail())), "<none>")
    check("long line", X.ask(A.Ask.parse.v2("ask docker.io " ++ String.repeat("a/", 300n) ++ "a" ++ X.tail())), "<none>")
    check("reply present", X.reply(A.Ask.reply.parse.v2("ok present\n")), "ok present\n")
    check("reply published", X.reply(A.Ask.reply.parse.v2("ok published\n")), "ok published\n")
    check("reply no", X.reply(A.Ask.reply.parse.v2("no manifest not found\n")), "no manifest not found\n")
    check("reply junk", X.reply(A.Ask.reply.parse.v2("yes\n")), "<none>")
    check("reply of an error", A.Ask.reply.render.v2(A.Ask.reply.v2(False{}, Some{"x\ry"})), "no x?y\n")
    check("port", U32.show(A.Ask.port.v2()), "32000")
    check("wait", U32.show(A.Ask.wait.max.v2()), "60")
