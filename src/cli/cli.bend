import Base
import ./duration.bend as D
import ./table.bend as T
import ../guest/plan.bend as P

# The vk8s command line, as data (vcluster's `vcluster ... --driver docker`
# verbs, pkg/cli/*_docker.go), and the bend-vmm command line of a cluster's
# control-plane VM. Pure: host/vk8s.bend performs it.

type Cmd is Data:
  Create{name: String, port: U32, cpus: U32, mem: U32, etcd: Bool, nodes: U32}
  Delete{name: String, ctx: Bool}
  List{}
  Connect{name: String, print: Bool, update_current: Bool}
  Pause{name: String}
  Resume{name: String}
  Vmm{flags: +List<String>}
  Version{}
  Help{msg: String}
  ListJson{}
  Describe{name: String, config_only: Bool, json: Bool}
  Logs{name: String, component: String}
  Snapshot{name: String, path: String}
  Restore{name: String, path: String}
  Exec{name: String, cmd: +List<String>}
  Cache{action: String}

def Cli.usage() -> String:
  "usage: vk8s <command>\n\n"
  ++ "  create NAME [--port P] [--cpus N] [--memory MiB] [--backing-store sqlite|etcd] [--nodes N]\n"
  ++ "                                                     start a virtual cluster in a bend-vmm VM\n"
  ++ "  connect NAME [--print] [--update-current=false]    add context vk8s_NAME to $KUBECONFIG or ~/.kube/config\n"
  ++ "  connect NAME -- COMMAND [ARGS...]                  run a command against the cluster (KUBECONFIG set)\n"
  ++ "  list [--output json]                               list virtual clusters\n"
  ++ "  describe NAME [--config-only] [--output json]      describe a virtual cluster\n"
  ++ "  logs NAME [COMPONENT]                              print a component's log (no component: list them)\n"
  ++ "  snapshot create NAME PATH                          pause the cluster and write its snapshot (tar.gz)\n"
  ++ "  restore NAME PATH                                  create cluster NAME from a snapshot\n"
  ++ "  pause NAME | resume NAME                           pause or resume a cluster's VM\n"
  ++ "  delete NAME [--delete-context=false]               stop a cluster, delete its state and its kube context\n"
  ++ "  cache start|stop|status                           the shared image cache VM (pull-through registries)\n"
  ++ "  vmm <bend-vmm options>                             run bend-vmm in this process\n"
  ++ "  version\n"

# vcluster validates names as DNS labels; so do we: [a-z0-9-], 1..52 chars,
# starting and ending alphanumeric.
def Cli.name_char(+c: U32) -> Bool:
  (U32.is_ge(c, 97) && U32.is_le(c, 122)) || (U32.is_ge(c, 48) && U32.is_le(c, 57)) || U32.is_eq(c, 45)

def Cli.alnum(+c: U32) -> Bool:
  (U32.is_ge(c, 97) && U32.is_le(c, 122)) || (U32.is_ge(c, 48) && U32.is_le(c, 57))

def Cli.all_name(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{Chr{c}, t}:
      Cli.name_char(c) && Cli.all_name(t)

def Cli.ends_ok(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{Chr{c}, t}:
      Cli.alnum(c)

def Cli.valid_name(+s: String) -> Bool:
  Cli.all_name(s) && Cli.ends_ok(s) && Cli.ends_ok(String.reverse(s))
    && Nat.is_le(String.length(s), 52n)

def Cli.num(m: Maybe<&2, U32>, +dflt: U32) -> U32:
  match m:
    case None{}:
      dflt
    case Some{n}:
      n

def Cli.create_opt.num.go(is_port: Bool, is_cpus: Bool, is_mem: Bool, is_nodes: Bool, +k: String, m: Maybe<&2, U32>,
  +n: String, +p: U32, +cpu: U32, +mem: U32, +etcd: Bool, +nodes: U32) -> Cmd:
  match is_port is_cpus is_mem is_nodes:
    case True{} _ _ _:
      Create{n, Cli.num(m, p), cpu, mem, etcd, nodes}
    case False{} True{} _ _:
      Create{n, p, Cli.num(m, cpu), mem, etcd, nodes}
    case False{} False{} True{} _:
      Create{n, p, cpu, Cli.num(m, mem), etcd, nodes}
    case False{} False{} False{} True{}:
      Create{n, p, cpu, mem, etcd, Cli.num(m, nodes)}
    case False{} False{} False{} False{}:
      Help{"vk8s create: unknown option " ++ k ++ "\n"}

# One option of `create`: a number (--port, --cpus, --memory, --nodes) or
# --backing-store sqlite|etcd (vcluster: controlPlane.backingStore).
def Cli.create_opt.num(+k: String, m: Maybe<&2, U32>, +n: String, +p: U32, +cpu: U32, +mem: U32, +etcd: Bool,
  +nodes: U32) -> Cmd:
  Cli.create_opt.num.go(String.eq(k, "--port"), String.eq(k, "--cpus"), String.eq(k, "--memory"),
    String.eq(k, "--nodes"), k, m, n, p, cpu, mem, etcd, nodes)

def Cli.create_opt.store(is_etcd: Bool, is_sqlite: Bool, +v: String, +n: String, +p: U32, +cpu: U32, +mem: U32,
  +nodes: U32) -> Cmd:
  match is_etcd is_sqlite:
    case True{} _:
      Create{n, p, cpu, mem, True{}, nodes}
    case False{} True{}:
      Create{n, p, cpu, mem, False{}, nodes}
    case False{} False{}:
      Help{"vk8s create: --backing-store is sqlite or etcd, not " ++ String.quote(v) ++ "\n"}

def Cli.create_opt.which(is_store: Bool, +k: String, +v: String, +n: String, +p: U32, +cpu: U32, +mem: U32,
  +etcd: Bool, +nodes: U32) -> Cmd:
  match is_store:
    case True{}:
      Cli.create_opt.store(String.eq(v, "etcd"), String.eq(v, "sqlite"), v, n, p, cpu, mem, nodes)
    case False{}:
      Cli.create_opt.num(k, U32.read(v), n, p, cpu, mem, etcd, nodes)

def Cli.create_opt(+k: String, +v: String, +c: Cmd) -> Cmd:
  match c:
    case Create{+n, +p, +cpu, +mem, +etcd, +nodes}:
      Cli.create_opt.which(String.eq(k, "--backing-store"), k, v, n, p, cpu, mem, etcd, nodes)
    case other:
      other

# Options after the name of `create`.
def Cli.create_opts(xs: +List<String>, +c: Cmd) -> Cmd:
  match xs:
    case Nil{}:
      c
    case Con{+k, Con{+v, rest}}:
      Cli.create_opts(rest, Cli.create_opt(k, v, c))
    case Con{+k, Nil{}}:
      Help{"vk8s create: " ++ k ++ " needs a value\n"}

# A cobra bool flag: "--f" or "--f=true" is True, "--f=false" is False;
# None when arg is not flag f.
def Cli.bool_flag.go(bare: Bool, yes: Bool, no: Bool) -> Maybe<&2, Bool>:
  match bare yes no:
    case True{} _ _:
      Some{True{}}
    case False{} True{} _:
      Some{True{}}
    case False{} False{} True{}:
      Some{False{}}
    case False{} False{} False{}:
      None{}

def Cli.bool_flag(+arg: String, +f: String) -> Maybe<&2, Bool>:
  Cli.bool_flag.go(String.eq(arg, f), String.eq(arg, f ++ "=true"), String.eq(arg, f ++ "=false"))

# Options of `connect` (vcluster: --print false, --update-current true).
def Cli.connect_opt.go(p: Maybe<&2, Bool>, u: Maybe<&2, Bool>, +k: String, +n: String, +pr: Bool, +up: Bool) -> Cmd:
  match p u:
    case Some{b} _:
      Connect{n, b, up}
    case None{} Some{b}:
      Connect{n, pr, b}
    case None{} None{}:
      Help{"vk8s connect: unknown option " ++ k ++ "\n"}

def Cli.connect_opt(+k: String, +c: Cmd) -> Cmd:
  match c:
    case Connect{+n, +pr, +up}:
      Cli.connect_opt.go(Cli.bool_flag(k, "--print"), Cli.bool_flag(k, "--update-current"), k, n, pr, up)
    case other:
      other

def Cli.connect_exec.go(empty: Bool, +n: String, +cmd: +List<String>) -> Cmd:
  match empty:
    case True{}:
      Help{"vk8s connect: -- needs a command\n"}
    case False{}:
      Exec{n, cmd}

def Cli.connect_exec(+c: Cmd, +cmd: +List<String>) -> Cmd:
  match c:
    case Connect{n, pr, up}:
      Cli.connect_exec.go(List.is_empty(&2, String, cmd), n, cmd)
    case other:
      other

def Cli.connect_opts.next(dash: Bool, rest: +List<String>, +c: Cmd, later: Cmd) -> Cmd:
  match dash:
    case True{}:
      Cli.connect_exec(c, rest)
    case False{}:
      later

# Options of `connect`; "--" ends them and starts the command to run
# (vcluster connect NAME -- kubectl get ns).
def Cli.connect_opts(xs: +List<String>, +c: Cmd) -> Cmd:
  match xs:
    case Nil{}:
      c
    case Con{+k, +rest}:
      Cli.connect_opts.next(String.eq(k, "--"), rest, c, Cli.connect_opts(rest, Cli.connect_opt(k, c)))

# Options of `delete` (vcluster: --delete-context true).
def Cli.delete_opt.go(d: Maybe<&2, Bool>, +k: String, +n: String) -> Cmd:
  match d:
    case Some{b}:
      Delete{n, b}
    case None{}:
      Help{"vk8s delete: unknown option " ++ k ++ "\n"}

def Cli.delete_opt(+k: String, +c: Cmd) -> Cmd:
  match c:
    case Delete{+n, d}:
      Cli.delete_opt.go(Cli.bool_flag(k, "--delete-context"), k, n)
    case other:
      other

def Cli.delete_opts(xs: +List<String>, +c: Cmd) -> Cmd:
  match xs:
    case Nil{}:
      c
    case Con{+k, rest}:
      Cli.delete_opts(rest, Cli.delete_opt(k, c))

def Cli.named(+verb: String, +name: String, ok: Bool) -> Maybe<&2, String>:
  match ok:
    case True{}:
      Some{name}
    case False{}:
      None{}

def Cli.bad_name(+name: String) -> Cmd:
  Help{"invalid cluster name " ++ String.quote(name) ++ ": use lowercase letters, digits and '-' (at most 52)\n"}

# `--output` / `-o`.
def Cli.is_output(+k: String) -> Bool:
  Bool.or(String.eq(k, "--output"), String.eq(k, "-o"))

def Cli.out_value(json: Bool, table: Bool, +v: String, ok: Bool -> Cmd, +verb: String) -> Cmd:
  match json table:
    case True{} _:
      ok(True{})
    case False{} True{}:
      ok(False{})
    case False{} False{}:
      Help{"vk8s " ++ verb ++ ": --output is table or json, not " ++ String.quote(v) ++ "\n"}

def Cli.describe_opts.pick(co: Bool, out: Bool, +k: String, +v: String, +n: String, +js: Bool, flag: Cmd, valued: Cmd) -> Cmd:
  match co out:
    case True{} _:
      flag
    case False{} True{}:
      valued
    case False{} False{}:
      Help{"vk8s describe: unknown option " ++ k ++ "\n"}

def Cli.describe_opts.last(co: Bool, out: Bool, +k: String, +n: String, +js: Bool) -> Cmd:
  match co out:
    case True{} _:
      Describe{n, True{}, js}
    case False{} True{}:
      Help{"vk8s describe: " ++ k ++ " needs a value\n"}
    case False{} False{}:
      Help{"vk8s describe: unknown option " ++ k ++ "\n"}

def Cli.describe_opts.set_json(+c: Cmd, j: Bool) -> Cmd:
  match c:
    case Describe{n, co, js}:
      Describe{n, co, j}
    case other:
      other

# Options of `describe` (vcluster: --config-only, --output table|json).
def Cli.describe_opts(xs: +List<String>, +n: String, +co: Bool, +js: Bool) -> Cmd:
  match xs:
    case Nil{}:
      Describe{n, co, js}
    case Con{+k, +tail}:
      match tail:
        case Nil{}:
          Cli.describe_opts.last(String.eq(k, "--config-only"), Cli.is_output(k), k, n, js)
        case Con{+v, rest}:
          Cli.describe_opts.pick(String.eq(k, "--config-only"), Cli.is_output(k), k, v, n, js,
            Cli.describe_opts(tail, n, True{}, js),
            Cli.out_value(String.eq(v, "json"), String.eq(v, "table"), v,
              j => Cli.describe_opts.set_json(Cli.describe_opts(rest, n, co, js), j), "describe"))

def Cli.list_opts.pick(out: Bool, +k: String, valued: Cmd) -> Cmd:
  match out:
    case True{}:
      valued
    case False{}:
      Help{"vk8s list: unknown option " ++ k ++ "\n"}

def Cli.list_of(json: Bool) -> Cmd:
  match json:
    case True{}:
      ListJson{}
    case False{}:
      List{}

# Options of `list` (vcluster: --output table|json).
def Cli.list_opts(xs: +List<String>, +json: Bool) -> Cmd:
  match xs:
    case Nil{}:
      Cli.list_of(json)
    case Con{+k, +tail}:
      match tail:
        case Nil{}:
          Help{"vk8s list: " ++ k ++ " needs a value\n"}
        case Con{+v, rest}:
          Cli.list_opts.pick(String.eq(k, "--output"), k,
            Cli.out_value(String.eq(v, "json"), String.eq(v, "table"), v, j => Cli.list_opts(rest, j), "list"))

def Cli.logs_of(rest: +List<String>, +n: String) -> Cmd:
  match rest:
    case Nil{}:
      Logs{n, ""}
    case Con{+c, more}:
      Logs{n, c}

# vcluster takes snapshot URLs; vk8s writes local files: "file://" is
# dropped, a bare path is taken as is.
def Cli.strip_file.go(url: Bool, +p: String) -> String:
  match url:
    case True{}:
      String.drop(p, 7n)
    case False{}:
      p

def Cli.strip_file(+p: String) -> String:
  Cli.strip_file.go(String.starts_with(p, "file://"), p)

def Cli.restore_of(rest: +List<String>, +n: String) -> Cmd:
  match rest:
    case Nil{}:
      Help{"vk8s restore: missing snapshot path\n"}
    case Con{+p, more}:
      Restore{n, Cli.strip_file(p)}

def Cli.verb.more(de: Bool, lo: Bool, re: Bool, +v: String, +name: String, rest: +List<String>) -> Cmd:
  match de lo re:
    case True{} _ _:
      Cli.describe_opts(rest, name, False{}, False{})
    case False{} True{} _:
      Cli.logs_of(rest, name)
    case False{} False{} True{}:
      Cli.restore_of(rest, name)
    case False{} False{} False{}:
      Help{"unknown command " ++ String.quote(v) ++ "\n" ++ Cli.usage()}

def Cli.verb.pick(cr: Bool, de: Bool, co: Bool, pa: Bool, re: Bool, +v: String, +name: String,
  rest: +List<String>) -> Cmd:
  match cr de co pa re:
    case True{} _ _ _ _:
      Cli.create_opts(rest, Create{name, 0, 2, 2048, False{}, 0})
    case False{} True{} _ _ _:
      Cli.delete_opts(rest, Delete{name, True{}})
    case False{} False{} True{} _ _:
      Cli.connect_opts(rest, Connect{name, False{}, True{}})
    case False{} False{} False{} True{} _:
      Pause{name}
    case False{} False{} False{} False{} True{}:
      Resume{name}
    case False{} False{} False{} False{} False{}:
      Cli.verb.more(String.eq(v, "describe"), String.eq(v, "logs"), String.eq(v, "restore"), v, name, rest)

def Cli.verb.go(ok: Bool, +v: String, +name: String, rest: +List<String>) -> Cmd:
  match ok:
    case False{}:
      Cli.bad_name(name)
    case True{}:
      Cli.verb.pick(String.eq(v, "create"), String.eq(v, "delete"), String.eq(v, "connect"),
        String.eq(v, "pause"), String.eq(v, "resume"), v, name, rest)

def Cli.verb(+v: String, +name: String, rest: +List<String>) -> Cmd:
  Cli.verb.go(Cli.valid_name(name), v, name, rest)

def Cli.parse.named(+v: String, rest: +List<String>) -> Cmd:
  match rest:
    case Nil{}:
      Help{"vk8s " ++ v ++ ": missing cluster name\n" ++ Cli.usage()}
    case Con{+name, more}:
      Cli.verb(v, name, more)

def Cli.snapshot.go(ok: Bool, +name: String, +path: String) -> Cmd:
  match ok:
    case True{}:
      Snapshot{name, Cli.strip_file(path)}
    case False{}:
      Cli.bad_name(name)

def Cli.snapshot.sub(create: Bool, +sub: String, +name: String, +path: String) -> Cmd:
  match create:
    case True{}:
      Cli.snapshot.go(Cli.valid_name(name), name, path)
    case False{}:
      Help{"vk8s snapshot: unknown command " ++ String.quote(sub) ++ " (use create)\n"}

# `snapshot create NAME PATH` (vcluster snapshot create NAME URL).
def Cli.snapshot(rest: +List<String>) -> Cmd:
  match rest:
    case Con{+sub, Con{+name, Con{+path, more}}}:
      Cli.snapshot.sub(String.eq(sub, "create"), sub, name, path)
    case _:
      Help{"usage: vk8s snapshot create NAME PATH\n"}

def Cli.cache_of.go(ok: Bool, +a: String) -> Cmd:
  match ok:
    case True{}:
      Cache{a}
    case False{}:
      Help{"usage: vk8s cache start|stop|status\n"}

def Cli.cache_of(rest: +List<String>) -> Cmd:
  match rest:
    case Con{+a, Nil{}}:
      Cli.cache_of.go(String.eq(a, "start") || String.eq(a, "stop") || String.eq(a, "status"), a)
    case _:
      Help{"usage: vk8s cache start|stop|status\n"}

def Cli.parse.cache(cache: Bool, +v: String, rest: +List<String>) -> Cmd:
  match cache:
    case True{}:
      Cli.cache_of(rest)
    case False{}:
      Cli.parse.named(v, rest)

def Cli.parse.more(snap: Bool, +v: String, rest: +List<String>) -> Cmd:
  match snap:
    case True{}:
      Cli.snapshot(rest)
    case False{}:
      Cli.parse.cache(String.eq(v, "cache"), v, rest)

def Cli.parse.verb(vmm: Bool, ls: Bool, ver: Bool, +v: String, rest: +List<String>) -> Cmd:
  match vmm ls ver:
    case True{} _ _:
      Vmm{rest}
    case False{} True{} _:
      Cli.list_opts(rest, False{})
    case False{} False{} True{}:
      Version{}
    case False{} False{} False{}:
      Cli.parse.more(String.eq(v, "snapshot"), v, rest)

# argv without the program name.
def Cli.parse(args: +List<String>) -> Cmd:
  match args:
    case Nil{}:
      Help{Cli.usage()}
    case Con{+v, rest}:
      Cli.parse.verb(String.eq(v, "vmm"), String.eq(v, "list"), String.eq(v, "version"), v, rest)

# Where a cluster lives on the host.
type Paths is Data:
  Paths{dir: String, assets: String}

def Cli.dir(+home: String, +name: String) -> String:
  home ++ "/.vk8s/clusters/" ++ name

# bend-vmm flags for a cluster's control-plane VM (vcluster docker driver:
# runControlPlaneContainer). vda: the read-only assets disk; vdb: the data
# disk; the cluster dir is shared over 9p (the guest publishes its
# kubeconfig there); 6443 is forwarded to 127.0.0.1:<port>.
def Cli.store_name(etcd: Bool) -> String:
  match etcd:
    case True{}:
      "etcd"
    case False{}:
      "sqlite"

# The cluster's LAN (bend-vmm --lan): the control plane is 10.10.0.2, worker
# i (1-based) is 10.10.0.(2+i).
def Cli.lan_ip(+i: U32) -> String:
  "10.10.0." ++ U32.show((i + 2 : U32))

def Cli.vmm_flags(+dir: String, +assets: String, +name: String, +port: U32, +cpus: U32, +mem: U32, +etcd: Bool) -> +List<String>:
  [ "--kernel", assets ++ "/Image",
    "--initrd", assets ++ "/vk8s.cpio",
    "--disk", assets ++ "/assets.img:ro," ++ dir ++ "/data.img",
    "--share", dir ++ "/share",
    "--mem", U32.show(mem),
    "--cpus", U32.show(cpus),
    "--forward", "127.0.0.1:" ++ U32.show(port) ++ ":6443",
    "--lan", dir ++ "/lan,ip=" ++ Cli.lan_ip(0) ++ "/24",
    "--control", dir ++ "/ctl.sock",
    "--cmdline", "console=ttyAMA0 quiet panic=5 VK8S_NAME=" ++ name ++ " VK8S_PORT=" ++ U32.show(port) ++ " VK8S_STORE=" ++ Cli.store_name(etcd) ]

# vcluster picks the docker driver's host port in 10000..12999.
def Cli.port_from(+seed: U32) -> U32:
  (10000 + (seed % 3000 : U32) : U32)

def Cli.worker_name(+name: String, +i: U32) -> String:
  name ++ "-worker-" ++ U32.show(i)

# bend-vmm flags for worker i of a cluster: its own data disk and share
# (holding the join material), the cluster's LAN, no port forward.
def Cli.worker_flags(+dir: String, +ndir: String, +assets: String, +node: String, +i: U32, +token: String,
  +cpus: U32, +mem: U32) -> +List<String>:
  [ "--kernel", assets ++ "/Image",
    "--initrd", assets ++ "/vk8s.cpio",
    "--disk", assets ++ "/assets.img:ro," ++ ndir ++ "/data.img",
    "--share", ndir ++ "/share",
    "--mem", U32.show(mem),
    "--cpus", U32.show(cpus),
    "--lan", dir ++ "/lan,ip=" ++ Cli.lan_ip(i) ++ "/24",
    "--control", ndir ++ "/ctl.sock",
    "--cmdline", "console=ttyAMA0 quiet panic=5 VK8S_ROLE=worker VK8S_NAME=" ++ node
      ++ " VK8S_NODE_IP=" ++ Cli.lan_ip(i) ++ " VK8S_TOKEN=" ++ token ]

# One cluster as `list` sees it: name, VM state (running, paused or
# stopped), creation time (Unix seconds and RFC 3339), whether it is the
# current kube context.
type Entry is Data:
  Entry{name: String, status: String, created: U32, created_at: String, connected: Bool}

def Cli.yes(b: Bool) -> String:
  match b:
    case True{}:
      "True"
    case False{}:
      ""

def Cli.json_bool(b: Bool) -> String:
  match b:
    case True{}:
      "true"
    case False{}:
      "false"

# A table row (vcluster dockerVClustersToValues): NAME STATUS CONNECTED AGE.
def Cli.row(e: Entry, +now: U32) -> +List<String>:
  match e:
    case Entry{n, s, +c, at, con}:
      [n, s, Cli.yes(con), D.Dur.human(U32.sub(now, c))]

def Cli.rows(es: List<&2, Entry>, +now: U32) -> +List<+List<String>>:
  match es:
    case Nil{}:
      Nil{}
    case Con{e, t}:
      Con{Cli.row(e, now), Cli.rows(t, now)}

def Cli.list_table(es: List<&2, Entry>, +now: U32) -> String:
  T.Table.render(["NAME", "STATUS", "CONNECTED", "AGE"], Cli.rows(es, now))

# One element of `list --output json` (vcluster ListVCluster, namespace
# "vk8s" where the docker driver writes "docker").
def Cli.entry_json(e: Entry, +now: U32) -> String:
  match e:
    case Entry{n, s, +c, at, con}:
      "    {\n        \"Created\": " ++ String.quote(at) ++ ",\n        \"Name\": " ++ String.quote(n)
        ++ ",\n        \"Namespace\": \"vk8s\",\n        \"Version\": \"\",\n        \"Status\": " ++ String.quote(s)
        ++ ",\n        \"AgeSeconds\": " ++ U32.show(U32.sub(now, c)) ++ ",\n        \"Connected\": " ++ Cli.json_bool(con) ++ "\n    }"

def Cli.entries_json(es: List<&2, Entry>, +now: U32) -> List<&2, String>:
  match es:
    case Nil{}:
      Nil{}
    case Con{e, t}:
      Con{Cli.entry_json(e, now), Cli.entries_json(t, now)}

def Cli.list_json.go(empty: Bool, +items: List<&2, String>) -> String:
  match empty:
    case True{}:
      "[]\n"
    case False{}:
      "[\n" ++ String.join(items, ",\n") ++ "\n]\n"

# json.MarshalIndent(output, "", "    ").
def Cli.list_json(es: List<&2, Entry>, +now: U32) -> String:
  +items : List<&2, String> = Cli.entries_json(es, now)
  Cli.list_json.go(List.is_empty(&2, String, items), items)

# A worker VM's directory: short, as its sockets live there.
def Cli.node_dir(+dir: String, +i: U32) -> String:
  dir ++ "/nodes/worker-" ++ U32.show(i)

# macOS limits a Unix socket path to 103 bytes. The longest a cluster
# creates is a LAN socket, DIR/lan/xx-xx-xx-xx-xx-xx.sock (bend-vmm), 27
# bytes past DIR; worker control sockets (DIR/nodes/worker-N/ctl.sock)
# stay shorter for N < 1000.
def Cli.paths_fit(+dir: String) -> Bool:
  Nat.is_le(Nat.add(String.length(dir), 27n), 103n)

def Cli.cache_forwards(ms: +List<P.Mirror>) -> String:
  match ms:
    case Nil{}:
      ""
    case Con{P.Mirror{r, u, +port}, Nil{}}:
      "127.0.0.1:" ++ U32.show(port) ++ ":" ++ U32.show(port)
    case Con{P.Mirror{r, u, +port}, rest}:
      "127.0.0.1:" ++ U32.show(port) ++ ":" ++ U32.show(port) ++ "," ++ Cli.cache_forwards(rest)

# bend-vmm flags for the image cache VM (~/.vk8s/cache): NAT only, each
# registry's port forwarded from the host's loopback, where every cluster's
# containerd reaches it as 10.0.2.2.
def Cli.cache_flags(+dir: String, +assets: String) -> +List<String>:
  [ "--kernel", assets ++ "/Image",
    "--initrd", assets ++ "/vk8s.cpio",
    "--disk", assets ++ "/assets.img:ro," ++ dir ++ "/data.img",
    "--share", dir ++ "/share",
    "--mem", "512",
    "--cpus", "1",
    "--forward", Cli.cache_forwards(P.Plan.mirrors()),
    "--control", dir ++ "/ctl.sock",
    "--cmdline", "console=ttyAMA0 quiet panic=5 VK8S_ROLE=cache VK8S_NAME=vk8s-cache" ]
