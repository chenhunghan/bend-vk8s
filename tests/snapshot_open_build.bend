import Base
import ../src/standalone/snapshot.bend as S
import ../src/guest/plan.bend as P
import ../host/snapshot_open.bend as O

# The host side of the open-format snapshot (host/snapshot_open.bend).
#
# With no arguments (scripts/check.sh) it checks the pure parts: the
# streamed etcd archive is Snap.Tar.encode(Snap.etcd_archive(...)) byte for
# byte, the format and kind of an archive from its first bytes, the
# key/value archive of etcdctl -w json pages, and the puts file of a
# key/value archive.
#
# tests/snapshot_envtest.sh builds it natively and runs the same host code
# as `vk8s snapshot create --format open` and `vk8s restore`:
#
#   snapshot_open_build plan export|restore etcd|kine NAME
#       the Run steps of the request snapshot-dump or Plan.restore_store, one
#       shell line each (the guest's command lines, src/guest/plan.bend)
#   snapshot_open_build export etcd|kine EXPORT_DIR STAGE OUT
#       Open.export: the archive of the guest's dump, gzip -3, mode 0600
#   snapshot_open_build fmt TAR
#       Open.fmt_file: vm, open or bad: MESSAGE
#   snapshot_open_build place TAR DIR
#       Open.place: the db or puts file and the marker; prints the kind

def T.report(name: String, got: String, want: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name ++ ": got " ++ got ++ ", want " ++ want)

def T.check(name: String, +got: String, +want: String) -> IO(Unit):
  T.report(name, got, want, String.eq(got, want))

def T.starts(name: String, +got: String, +want: String) -> IO(Unit):
  T.report(name, got, want ++ "...", String.starts_with(got, want))

def T.rec(k: String, v: String) -> S.Snap.Rec:
  S.Rec{S.Snap.b(k), S.Snap.b(v)}

def T.bytes(r: O.Open.R(List<&2, U32>)) -> String:
  match r:
    case Fail{m}:
      "error: " ++ m
    case Done{bs}:
      S.Snap.s(bs)

def T.same.if(eq: Bool) -> String:
  match eq:
    case True{}:
      "same"
    case False{}:
      "differs"

def T.same(a: O.Open.R(List<&2, U32>), b: O.Open.R(List<&2, U32>)) -> String:
  match a b:
    case Fail{m} _:
      "error: " ++ m
    case _ Fail{m}:
      "error (want): " ++ m
    case Done{+x} Done{+y}:
      T.same.if(S.Snap.beq(x, y) && Nat.is_eq(List.length(&2, U32, x), List.length(&2, U32, y)))

def T.fmt(f: O.Open.Fmt) -> String:
  match f:
    case O.FmtVm{}:
      "vm"
    case O.FmtOpen{}:
      "open"
    case O.FmtBad{m}:
      "bad: " ++ m

def T.loc(l: O.Open.Loc) -> String:
  match l:
    case O.LocDb{off, n}:
      "db " ++ Nat.show(off) ++ " " ++ Nat.show(n)
    case O.LocKv{}:
      "kv"
    case O.LocErr{m}:
      "error: " ++ m

def T.tar(r: O.Open.R(List<&2, U32>)) -> List<&2, U32>:
  match r:
    case Fail{m}:
      Nil{}
    case Done{bs}:
      bs

def T.db() -> List<&2, U32>:
  S.Snap.app(S.Snap.b("not a bolt database\n"), List.replicate(U32, 700n, 7))

def T.etcd_tar() -> List<&2, U32>:
  T.tar(S.Snap.Tar.encode(S.Snap.etcd_archive(S.Snap.meta0(), T.db(), None{})))

def T.etcd_meta_tar() -> List<&2, U32>:
  T.tar(S.Snap.Tar.encode(S.Snap.etcd_archive(S.Meta{Some{S.Snap.b("{}")}, Some{S.Rec{S.Snap.request_entry_key(), S.Snap.b("{}")}}},
    T.db(), None{})))

# etcdctl get / 0 --limit 1000 -w json, then the next page from its last
# key (/b) at the same revision: /b again, then /c with an empty value.
def T.page1() -> String:
  "{\"header\":{\"cluster_id\":14841639068965178418,\"revision\":5},\"kvs\":[{\"key\":\"L2E=\",\"create_revision\":2,\"mod_revision\":2,\"version\":1,\"value\":\"MQ==\"},"
  ++ "{\"key\":\"L2I=\",\"create_revision\":3,\"mod_revision\":3,\"version\":1,\"value\":\"Mg==\"}],\"more\":true,\"count\":3}\n"

def T.page2() -> String:
  "{\"header\":{\"cluster_id\":14841639068965178418,\"revision\":5},\"kvs\":[{\"key\":\"L2I=\",\"create_revision\":3,\"mod_revision\":3,\"version\":1,\"value\":\"Mg==\"},"
  ++ "{\"key\":\"L2M=\",\"create_revision\":4,\"mod_revision\":4,\"version\":1}],\"count\":2}\n"

def T.kv_tar() -> List<&2, U32>:
  T.tar(S.Snap.Tar.encode([T.rec("/vcluster/snapshot/revision", "9"), T.rec("/registry/health", "{\"health\":\"true\"}"),
    S.Rec{S.Snap.b("/registry/configmaps/default/cm"), S.Snap.app(S.Snap.b("a b\n"), [1, 255])},
    T.rec("/registry/configmaps/default/kube-root-ca.crt", "ca"), T.rec("/vcluster/mappings/x", "m"),
    T.rec("/registry/pods/default/p", "pod")]))

def T.pure() -> IO(Unit):
  do IO<Unit>:
    T.check("etcd archive: streamed header, data and tail are Snap.Tar.encode(Snap.etcd_archive)",
      T.same(O.Open.etcd_bytes(T.db()), S.Snap.Tar.encode(S.Snap.etcd_archive(S.Snap.meta0(), T.db(), None{}))), "same")
    T.check("etcd archive of an empty database",
      T.same(O.Open.etcd_bytes(Nil{}), S.Snap.Tar.encode(S.Snap.etcd_archive(S.Snap.meta0(), Nil{}, None{}))), "same")
    T.check("etcd archive of 512 bytes",
      T.same(O.Open.etcd_bytes(List.replicate(U32, 512n, 1)), S.Snap.Tar.encode(S.Snap.etcd_archive(S.Snap.meta0(), List.replicate(U32, 512n, 1), None{}))), "same")
    T.check("fmt: VM snapshot (metadata.json first)", T.fmt(O.Open.fmt(T.tar(S.Snap.Tar.encode([T.rec("metadata.json", "{}"), T.rec("cluster.env", "NAME=a\n")])))), "vm")
    T.check("fmt: key/value archive", T.fmt(O.Open.fmt(T.tar(S.Snap.Tar.encode([T.rec("/vcluster/snapshot/revision", "9")])))), "open")
    T.check("fmt: etcd archive", T.fmt(O.Open.fmt(T.etcd_tar())), "open")
    T.check("fmt: an etcd database larger than the prefix",
      T.fmt(O.Open.fmt(List.take(&2, U32, S.Snap.app(T.tar(O.Open.etcd_head(5000000n)), List.replicate(U32, 4096n, 3)), 2048n))), "open")
    T.check("fmt: empty archive", T.fmt(O.Open.fmt(S.Snap.Tar.trailer())), "open")
    T.check("fmt: other first entry", T.fmt(O.Open.fmt(T.tar(S.Snap.Tar.encode([T.rec("data.img", "x")])))),
      "bad: the snapshot's first entry is \"data.img\": neither a vk8s VM snapshot (metadata.json) nor vcluster's archive (/vcluster/snapshot/...)")
    T.check("fmt: not a tar", T.fmt(O.Open.fmt(S.Snap.b("hello"))), "bad: cannot read the snapshot: not a gzip-compressed tar archive")
    T.check("loc: etcd archive", T.loc(O.Open.loc(T.etcd_tar())), "db 512 720")
    T.check("loc: release, request, db", T.loc(O.Open.loc(T.etcd_meta_tar())), "db 2560 720")
    T.check("loc: release, db", T.loc(O.Open.loc(T.tar(S.Snap.Tar.encode([T.rec("/vcluster/snapshot/release", "{}"), T.rec("/vcluster/snapshot/db", "db")])))), "db 1536 2")
    T.check("loc: request, then a key", T.loc(O.Open.loc(T.tar(S.Snap.Tar.encode([T.rec("/vcluster/snapshot/request/v1beta1", "{}"), T.rec("/registry/a", "1")])))), "kv")
    T.check("loc: key/value archive", T.loc(O.Open.loc(T.kv_tar())), "kv")
    T.check("loc: empty archive", T.loc(O.Open.loc(S.Snap.Tar.trailer())), "kv")
    T.check("kv archive: revision, then each key once across pages",
      T.same(O.Open.kv_archive("4\n", [T.page1(), T.page2()]),
        S.Snap.encode([T.rec("/vcluster/snapshot/revision", "4"), T.rec("/a", "1"), T.rec("/b", "2"), T.rec("/c", "")])), "same")
    T.check("kv archive: a page that does not start at the last key", T.bytes(O.Open.kv_archive("4", [T.page1(), T.page1()])),
      "error: failed to retrieve etcd items: a page does not start at the previous page's last key")
    T.starts("kv archive: a bad revision", T.bytes(O.Open.kv_archive("x", [T.page1()])), "error: failed to get current revision: ")
    T.check("puts: restore plan for a new vCluster, Go-quoted values, kine's own key left out", T.bytes(O.Open.kv_puts(T.kv_tar())),
      "/registry/configmaps/default/cm\n\"a b\\n\\x01\\xff\"\n/registry/pods/default/p\n\"pod\"\n")
    T.check("puts: empty archive", T.bytes(O.Open.kv_puts(S.Snap.Tar.trailer())), "")
    T.starts("puts: a key with a space", T.bytes(O.Open.kv_puts(T.tar(S.Snap.Tar.encode([T.rec("/registry/a b", "1")])))),
      "error: the snapshot holds a key the restore cannot carry")
    T.starts("puts: an etcd archive", T.bytes(O.Open.kv_puts(T.etcd_tar())), "error: the snapshot is an etcd archive")

# Modes
# -----

def Main.usage() -> IO(Unit):
  do IO<Unit>:
    IO.print_err("usage: snapshot_open_build [plan export|restore etcd|kine NAME | export etcd|kine EXPORT_DIR STAGE OUT | fmt TAR | place TAR DIR]")
    IO.exit(2)

def Main.fail(+m: String) -> IO(Unit):
  do IO<Unit>:
    IO.print("FAIL " ++ m)
    IO.exit(1)

def Main.step(s: P.Step) -> IO(Unit):
  match s:
    case P.Run{prog, args}:
      IO.print(P.Plan.sh_quote(prog) ++ P.Plan.sh_words(args))
    case _:
      IO.pure(Unit, Unit{})

def Main.steps(ss: +List<P.Step>) -> IO(Unit):
  match ss:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{s, t}:
      do IO<Unit>:
        Main.step(s)
        Main.steps(t)

def Main.plan.pick(exp: Bool, etcd: Bool, +name: String) -> +List<P.Step>:
  match exp:
    case True{}:
      P.Plan.request("snapshot-dump", P.Plan.default_cfg(name, 6443, etcd), "")
    case False{}:
      P.Plan.restore_store(etcd, name, Nil{})

def Main.plan(rest: +List<String>) -> IO(Unit):
  match rest:
    case Con{+what, Con{+store, Con{+name, Nil{}}}}:
      Main.steps(Main.plan.pick(String.eq(what, "export"), String.eq(store, "etcd"), name))
    case _:
      Main.usage()

def Main.exported(r: O.Open.R(Unit)) -> IO(Unit):
  match r:
    case Fail{m}:
      Main.fail("export: " ++ m)
    case Done{u}:
      IO.print("PASS export")

def Main.export(rest: +List<String>) -> IO(Unit):
  match rest:
    case Con{+store, Con{+exp, Con{+stage, Con{+out, Nil{}}}}}:
      do IO<Unit>:
        r : O.Open.R(Unit) <- O.Open.export(String.eq(store, "etcd"), exp, stage, out)
        Main.exported(r)
    case _:
      Main.usage()

def Main.kind(etcd: Bool) -> String:
  match etcd:
    case True{}:
      "etcd"
    case False{}:
      "kine"

def Main.placed(r: O.Open.R(Bool)) -> IO(Unit):
  match r:
    case Fail{m}:
      Main.fail("place: " ++ m)
    case Done{etcd}:
      IO.print(Main.kind(etcd))

def Main.place(rest: +List<String>) -> IO(Unit):
  match rest:
    case Con{+t, Con{+dir, Nil{}}}:
      do IO<Unit>:
        r : O.Open.R(Bool) <- O.Open.place(t, dir)
        Main.placed(r)
    case _:
      Main.usage()

def Main.fmt(rest: +List<String>) -> IO(Unit):
  match rest:
    case Con{+t, Nil{}}:
      do IO<Unit>:
        f : O.Open.Fmt <- O.Open.fmt_file(t)
        IO.print(T.fmt(f))
    case _:
      Main.usage()

def Main.mode(pl: Bool, ex: Bool, pc: Bool, fm: Bool, rest: +List<String>) -> IO(Unit):
  match pl ex pc fm:
    case True{} _ _ _:
      Main.plan(rest)
    case False{} True{} _ _:
      Main.export(rest)
    case False{} False{} True{} _:
      Main.place(rest)
    case False{} False{} False{} True{}:
      Main.fmt(rest)
    case False{} False{} False{} False{}:
      Main.usage()

def Main.run(args: +List<String>) -> IO(Unit):
  match args:
    case Nil{}:
      T.pure()
    case Con{+m, rest}:
      Main.mode(String.eq(m, "plan"), String.eq(m, "export"), String.eq(m, "place"), String.eq(m, "fmt"), rest)

def Main.plus(xs: List<String>) -> +List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      Con{x, Main.plus(t)}

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    Main.run(List.drop(&2, String, Main.plus(args), 1n))
