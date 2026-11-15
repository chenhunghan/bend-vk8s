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
    case C.SnapshotOpen{n, path}:
      "snapshot open " ++ n ++ " " ++ path
    case C.Exec{n, cmd}:
      "exec " ++ n ++ " " ++ String.join(cmd, " ")
    case C.Cache{a}:
      "cache " ++ a
    case C.Upgrade{n, p, cpu, mem, etcd, nodes}:
      "upgrade " ++ n
    case C.NodeAdd{n, c}:
      "node add " ++ n ++ " " ++ U32.show(c)
    case C.WithValues{c, f}:
      "values " ++ f
    case C.TokenCreate{n, e, k, c}:
      "token create " ++ n
    case C.TokenList{n, j}:
      "token list " ++ n
    case C.TokenDelete{n, i}:
      "token delete " ++ n ++ " " ++ i
    case C.NodeLoad{n, node, a}:
      "node load " ++ n ++ " " ++ node ++ " " ++ a
    case C.Certs{a, n}:
      "certs " ++ a ++ " " ++ n
    case C.Classic{c, k, ns}:
      "classic " ++ k ++ " " ++ ns
    case C.NoConnect{c}:
      "noconnect"
    case C.NodeDelete{n, node, d}:
      "node delete " ++ n ++ " " ++ node ++ " " ++ Bool.show(d)
    case C.AssetsPrune{d}:
      "assets prune " ++ Bool.show(d)

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
    T.check("snapshot create, no --format: the VM format",
      T.parses(["snapshot", "create", "demo", "/tmp/s.tar.gz"], "snapshot demo /tmp/s.tar.gz"))
    T.check("snapshot create --format vm",
      T.parses(["snapshot", "create", "demo", "file:///tmp/s.tar.gz", "--format", "vm"], "snapshot demo /tmp/s.tar.gz"))
    T.check("snapshot create --format open",
      T.parses(["snapshot", "create", "demo", "file:///tmp/s.tar.gz", "--format", "open"], "snapshot open demo /tmp/s.tar.gz"))
    T.check("snapshot create --format=open",
      T.parses(["snapshot", "create", "demo", "/tmp/s.tar.gz", "--format=open"], "snapshot open demo /tmp/s.tar.gz"))
    T.check("snapshot create --format=vm",
      T.parses(["snapshot", "create", "demo", "/tmp/s.tar.gz", "--format=vm"], "snapshot demo /tmp/s.tar.gz"))
    T.check("snapshot create --format raw",
      T.parses(["snapshot", "create", "demo", "/tmp/s.tar.gz", "--format", "raw"], "help vk8s snapshot: --format is open or vm, not \"raw\"\n"))
    T.check("snapshot create --format without a value",
      T.parses(["snapshot", "create", "demo", "/tmp/s.tar.gz", "--format"], "help vk8s snapshot: --format needs a value\n"))
    T.check("snapshot create --format open, then more",
      T.parses(["snapshot", "create", "demo", "/tmp/s.tar.gz", "--format", "open", "x"], "help vk8s snapshot: unexpected argument \"x\"\n"))
    T.check("snapshot create unknown option",
      T.parses(["snapshot", "create", "demo", "/tmp/s.tar.gz", "--bogus"], "help vk8s snapshot: unknown option --bogus\n"))
    T.check("snapshot create bad name",
      T.parses(["snapshot", "create", "Demo", "/tmp/s.tar.gz", "--format", "open"],
        "help invalid cluster name \"Demo\": use lowercase letters, digits and '-' (at most 52)\n"))
    T.check("snapshot create s3://",
      T.parses(["snapshot", "create", "demo", "s3://bucket/key", "--format", "open"], "help vk8s snapshot: s3:// is not supported yet (use a file path or file://)\n"))
    T.check("snapshot create oci://",
      T.parses(["snapshot", "create", "demo", "oci://ghcr.io/me/snap:v1"], "help vk8s snapshot: oci:// is not supported yet (use a file path or file://)\n"))
    T.check("snapshot create https://",
      T.parses(["snapshot", "create", "demo", "https://acct.blob.core.windows.net/c/s"], "help vk8s snapshot: https:// is not supported yet (use a file path or file://)\n"))
    T.check("snapshot create container://",
      T.parses(["snapshot", "create", "demo", "container:///data/s.tar.gz", "--format", "open"], "help vk8s snapshot: container:// is not supported yet (use a file path or file://)\n"))
    T.check("restore file://", T.parses(["restore", "demo2", "file:///tmp/s.tar.gz"], "restore demo2 /tmp/s.tar.gz"))
    T.check("restore bare path", T.parses(["restore", "demo2", "/tmp/s.tar.gz"], "restore demo2 /tmp/s.tar.gz"))
    T.check("restore oci://",
      T.parses(["restore", "demo2", "oci://ghcr.io/me/snap:v1"], "help vk8s restore: oci:// is not supported yet (use a file path or file://)\n"))
    T.check("restore s3://",
      T.parses(["restore", "demo2", "s3://bucket/key"], "help vk8s restore: s3:// is not supported yet (use a file path or file://)\n"))
    T.check("parse assets prune", T.parses(["assets", "prune"], "assets prune False"))
    T.check("parse assets prune --dry-run", T.parses(["assets", "prune", "--dry-run"], "assets prune True"))
    T.check_args("assets unknown command", ["assets", "list"], "help")
    T.check("assets_prune removes superseded releases only",
      String.eq(String.join(C.Cli.assets_prune(["v1.36.4-11112222", "v1.36.5-0a1b2c3d", "v1.36.6-69181a9a", "dev", ".fetch.Ab12Cd", "vx", "v1.36.6", "v1.36.5-0a1b2c3"],
        "v1.36.6-69181a9a", "v1.36.4-11112222", []), " "), "v1.36.5-0a1b2c3d"))
    T.check("assets_prune keeps what a running VM uses",
      String.eq(String.join(C.Cli.assets_prune(["v1.36.4-11112222", "v1.36.5-0a1b2c3d"], "v1.36.6-69181a9a", "",
        ["v1.36.4-11112222", "v1.36.5-0a1b2c3d"]), " "), ""))
