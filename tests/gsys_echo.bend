import Base
import ../host/gsys.bend as GS
import ../src/guest/sysop.bend as Y

# The guest system call effects' test program (host/effs/gsys.c,
# host/gsys.bend). tests/gsys.sh builds it and runs
#
#   gsys_echo DIR
#
# on a scratch directory the script prepared, and compares what it
# prints and leaves with what mkdir -p, test, ls, rm -f, mv -f, du -sk,
# find | wc -l and tail -c do. It never mounts, trims or sets the clock.
#
# Run with no arguments (scripts/check.sh runs it so, through `bend` on
# the JavaScript lane) it only looks at a missing path: the lane's
# stand-in fails (ENOSYS), a native build finds nothing; both mean "not a
# directory".

def Main.b(ok: Bool) -> String:
  match ok:
    case True{}:
      "yes"
    case False{}:
      "no"

def Main.usage(m: Maybe<&2, Y.Tally>) -> String:
  match m:
    case None{}:
      "none"
    case Some{+t}:
      U32.show(Y.Tally.kib(t)) ++ " " ++ U32.show(Y.Tally.count(t))

def Main.names(m: Maybe<&2, List<&2, String>>) -> String:
  match m:
    case None{}:
      "none"
    case Some{ns}:
      String.join(ns, " ")

def Main.run(+d: String) -> IO(Unit):
  do IO<Unit>:
    a : Bool <- GS.Gs.mkdirs([d ++ "/made/a/b", d ++ "/made//c/", d ++ "/link/under"])
    IO.print("mkdirs " ++ Main.b(a))
    b : Bool <- GS.Gs.mkdir_p(d ++ "/file/x")
    IO.print("mkdir_under_file " ++ Main.b(b))
    c : Bool <- GS.Gs.mkdir_p(d ++ "/made/a")
    IO.print("mkdir_again " ++ Main.b(c))
    d1 : Bool <- GS.Gs.is_dir(d ++ "/link")
    d2 : Bool <- GS.Gs.is_dir(d ++ "/file")
    d3 : Bool <- GS.Gs.is_dir(d ++ "/missing")
    IO.print("is_dir " ++ Main.b(d1) ++ " " ++ Main.b(d2) ++ " " ++ Main.b(d3))
    f1 : Bool <- GS.Gs.is_file(d ++ "/file")
    f2 : Bool <- GS.Gs.is_file(d ++ "/filelink")
    f3 : Bool <- GS.Gs.is_file(d ++ "/made")
    IO.print("is_file " ++ Main.b(f1) ++ " " ++ Main.b(f2) ++ " " ++ Main.b(f3))
    m1 : Bool <- GS.Gs.mountpoint("/")
    m2 : Bool <- GS.Gs.mountpoint(d ++ "/made")
    m3 : Bool <- GS.Gs.mountpoint(d ++ "/file")
    IO.print("mountpoint " ++ Main.b(m1) ++ " " ++ Main.b(m2) ++ " " ++ Main.b(m3))
    ns : Maybe<&2, List<&2, String>> <- GS.Gs.ls(d ++ "/tree")
    IO.print("ls " ++ Main.names(ns))
    nm : Maybe<&2, List<&2, String>> <- GS.Gs.ls(d ++ "/missing")
    IO.print("ls_missing " ++ Main.names(nm))
    u : Maybe<&2, Y.Tally> <- GS.Gs.usage(d ++ "/tree")
    IO.print("usage " ++ Main.usage(u))
    um : Maybe<&2, Y.Tally> <- GS.Gs.usage(d ++ "/missing")
    IO.print("usage_missing " ++ Main.usage(um))
    w : Bool <- GS.Gs.warm(d ++ "/tree")
    IO.print("warm " ++ Main.b(w))
    r1 : Bool <- GS.Gs.unlinks([d ++ "/gone1", d ++ "/missing", d ++ "/gone2"])
    r2 : Bool <- GS.Gs.unlinks([d ++ "/made"])
    IO.print("unlinks " ++ Main.b(r1) ++ " " ++ Main.b(r2))
    v1 : Bool <- GS.Gs.rename(d ++ "/state.tmp", d ++ "/state")
    v2 : Bool <- GS.Gs.rename(d ++ "/missing", d ++ "/state")
    IO.print("rename " ++ Main.b(v1) ++ " " ++ Main.b(v2))
    x1 : Bool <- GS.Gs.rmdir(d ++ "/empty")
    x2 : Bool <- GS.Gs.rmdir(d ++ "/tree")
    IO.print("rmdir " ++ Main.b(x1) ++ " " ++ Main.b(x2))
    y : Bool <- GS.Gs.rm_rf(d ++ "/doomed")
    IO.print("rm_rf " ++ Main.b(y))
    GS.Gs.trim_logs(d ++ "/logs")
    IO.print("done")

def Main.lane(dir: Bool) -> IO(Unit):
  match dir:
    case False{}:
      IO.print("PASS gsys_echo: a missing path is no directory")
    case True{}:
      IO.print("FAIL gsys_echo: a missing path is a directory")

def Main.args(args: List<String>) -> IO(Unit):
  match args:
    case Con{_, Con{dir, _}}:
      Main.run(dir)
    case _:
      do IO<Unit>:
        d : Bool <- GS.Gs.is_dir("/nonexistent-vk8s-gsys/missing")
        Main.lane(d)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    Main.args(args)
