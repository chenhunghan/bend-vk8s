import Base
import ../src/cli/cli.bend as C

# The connect and delete flags of src/cli/cli.bend, with vcluster's
# defaults (pkg/cli/flags/connect: --print false, --update-current true;
# pkg/cli/flags/delete: --delete-context true). Each line prints PASS or FAIL.

def T.show(c: C.Cmd) -> String:
  match c:
    case C.Connect{n, p, u}:
      "connect " ++ n ++ " " ++ Bool.show(p) ++ " " ++ Bool.show(u)
    case C.Delete{n, d}:
      "delete " ++ n ++ " " ++ Bool.show(d)
    case C.Help{m}:
      "help"
    case _:
      "other"

def T.check.go(+name: String, ok: Bool) -> String:
  match ok:
    case True{}:
      "PASS " ++ name
    case False{}:
      "FAIL " ++ name

def T.check(+name: String, args: +List<String>, +want: String) -> String:
  T.check.go(name, String.eq(T.show(C.Cli.parse(args)), want))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(T.check("connect defaults", ["connect", "demo"], "connect demo False True"))
    IO.print(T.check("connect --print", ["connect", "demo", "--print"], "connect demo True True"))
    IO.print(T.check("connect --update-current=false", ["connect", "demo", "--update-current=false"], "connect demo False False"))
    IO.print(T.check("connect --print=false --update-current=true", ["connect", "demo", "--print=false", "--update-current=true"],
      "connect demo False True"))
    IO.print(T.check("connect unknown option", ["connect", "demo", "--bogus"], "help"))
    IO.print(T.check("delete defaults", ["delete", "demo"], "delete demo True"))
    IO.print(T.check("delete --delete-context=false", ["delete", "demo", "--delete-context=false"], "delete demo False"))
    IO.print(T.check("delete unknown option", ["delete", "demo", "--wait"], "help"))
    IO.print(T.check("connect bad name", ["connect", "Demo"], "help"))
