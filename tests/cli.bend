import Base
import ../src/cli/cli.bend as C

# The vk8s command line of src/cli/cli.bend, run.

def T.check(+name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name)

def T.show(c: C.Cmd) -> String:
  match c:
    case C.Create{n, p, cpu, mem, etcd, nodes}:
      "create " ++ n ++ " " ++ U32.show(p) ++ " " ++ U32.show(cpu) ++ " " ++ U32.show(mem) ++ " "
        ++ Bool.show(etcd) ++ " " ++ U32.show(nodes)
    case C.Delete{n, d}:
      "delete " ++ n ++ " " ++ Bool.show(d)
    case C.List{}:
      "list"
    case C.Connect{n, p, u}:
      "connect " ++ n ++ " " ++ Bool.show(p) ++ " " ++ Bool.show(u)
    case C.Pause{n}:
      "pause " ++ n
    case C.Resume{n}:
      "resume " ++ n
    case C.Vmm{flags}:
      "vmm " ++ String.join(flags, " ")
    case C.Version{}:
      "version"
    case C.Help{msg}:
      "help " ++ msg
    case C.ListJson{}:
      "list json"
    case C.Describe{n, co, js}:
      "describe " ++ n ++ " " ++ Bool.show(co) ++ " " ++ Bool.show(js)
    case C.Logs{n, comp}:
      "logs " ++ n ++ " " ++ comp
    case C.Snapshot{n, path}:
      "snapshot " ++ n ++ " " ++ path
    case C.Restore{n, path}:
      "restore " ++ n ++ " " ++ path
    case C.Exec{n, cmd}:
      "exec " ++ n ++ " " ++ String.join(cmd, " ")

def T.parses(args: +List<String>, +want: String) -> Bool:
  String.eq(T.show(C.Cli.parse(args)), want)

def T.is(a: Bool, b: Bool) -> Bool:
  match a b:
    case True{} True{}:
      True{}
    case False{} False{}:
      True{}
    case _ _:
      False{}


# The connect/delete lines collapse every help message to "help".
def T.show_b(c: C.Cmd) -> String:
  match c:
    case C.Help{m}:
      "help"
    case _:
      T.show(c)

def T.check_args.go(+name: String, ok: Bool) -> String:
  match ok:
    case True{}:
      "PASS " ++ name
    case False{}:
      "FAIL " ++ name

def T.check_args(+name: String, args: +List<String>, +want: String) -> IO(Unit):
  IO.print(T.check_args.go(name, String.eq(T.show_b(C.Cli.parse(args)), want)))

def main() -> IO(Unit):
  do IO<Unit>:
    T.check("parse create demo", T.parses(["create", "demo"], "create demo 0 2 2048 False 0"))
    T.check("parse create demo --nodes 2 --backing-store etcd",
      T.parses(["create", "demo", "--nodes", "2", "--backing-store", "etcd"], "create demo 0 2 2048 True 2"))
    T.check("parse create Bad_Name",
      T.parses(["create", "Bad_Name"],
        "help invalid cluster name \"Bad_Name\": use lowercase letters, digits and '-' (at most 52)\n"))
    T.check("parse vmm --mem 512", T.parses(["vmm", "--mem", "512"], "vmm --mem 512"))
    T.check("parse list", T.parses(["list"], "list"))
    T.check("valid_name demo", T.is(C.Cli.valid_name("demo"), True{}))
    T.check("valid_name Bad_Name", T.is(C.Cli.valid_name("Bad_Name"), False{}))
    T.check("valid_name -demo", T.is(C.Cli.valid_name("-demo"), False{}))
    T.check("valid_name demo-", T.is(C.Cli.valid_name("demo-"), False{}))
    T.check("valid_name empty", T.is(C.Cli.valid_name(""), False{}))
    T.check("lan_ip 0", String.eq(C.Cli.lan_ip(0), "10.10.0.2"))
    T.check("lan_ip 1", String.eq(C.Cli.lan_ip(1), "10.10.0.3"))
    T.check("worker_name", String.eq(C.Cli.worker_name("demo", 1), "demo-worker-1"))
    T.check_args("connect defaults", ["connect", "demo"], "connect demo False True")
    T.check_args("connect --print", ["connect", "demo", "--print"], "connect demo True True")
    T.check_args("connect --update-current=false", ["connect", "demo", "--update-current=false"], "connect demo False False")
    T.check_args("connect --print=false --update-current=true", ["connect", "demo", "--print=false", "--update-current=true"],
      "connect demo False True")
    T.check_args("connect unknown option", ["connect", "demo", "--bogus"], "help")
    T.check_args("delete defaults", ["delete", "demo"], "delete demo True")
    T.check_args("delete --delete-context=false", ["delete", "demo", "--delete-context=false"], "delete demo False")
    T.check_args("delete unknown option", ["delete", "demo", "--wait"], "help")
    T.check_args("connect bad name", ["connect", "Demo"], "help")
