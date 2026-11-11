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
  Upgrade{name: String, port: U32, cpus: U32, mem: U32, etcd: Bool, nodes: U32}
  NodeAdd{name: String, count: U32}
  NodeDelete{name: String, node: String, drain: Bool}
  NoConnect{c: Cmd}
  Classic{c: Cmd, kubeconfig: String, namespace: String}
  Certs{action: String, name: String}
  NodeLoad{name: String, node: String, archive: String}
  TokenCreate{name: String, expires: String, kubeadm: Bool, cp: Bool}
  TokenList{name: String, json: Bool}
  TokenDelete{name: String, id: String}
  WithValues{c: Cmd, file: String}

def Cli.usage() -> String:
  "usage: vk8s <command>\n\n"
  ++ "  create NAME [--port P] [--cpus N] [--memory MiB] [--backing-store sqlite|etcd] [--nodes N] [--upgrade]\n"
  ++ "              [--host-kubeconfig FILE [--host-namespace NS]]   classic mode: sync to a host cluster\n"
  ++ "              [-f vcluster.yaml]                   vcluster.yaml: backing store, extraArgs (docs/CONFIG.md)\n"
  ++ "              [--connect=false] [--restore PATH]   (connects, as vcluster create does, unless --connect=false)\n"
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
  ++ "  node add NAME [--count N]                         start N more worker VMs that join the cluster\n"
  ++ "  node delete NAME NODE [--drain=false]              cordon, drain and delete a worker, then stop its VM\n"
  ++ "  node load-image NAME NODE --archive FILE           import an image archive (tar or tar.gz) into a node\n"
  ++ "  certs rotate|rotate-ca|check NAME                  renew the certificates (rotate-ca: the CA too) or show their expiry\n"
  ++ "  token create NAME [--expires 1h] [--kubeadm] [--control-plane]   a join token and its join command\n"
  ++ "  token list NAME [--output json] | token delete NAME ID\n"
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

def Cli.has(xs: +List<String>, +f: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{x, t}:
      Bool.or(String.eq(x, f), Cli.has(t, f))

def Cli.without.keep(drop: Bool, +x: String, rest: +List<String>) -> +List<String>:
  match drop:
    case True{}:
      rest
    case False{}:
      Con{x, rest}

def Cli.without(xs: +List<String>, +f: String) -> +List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, t}:
      Cli.without.keep(String.eq(x, f), x, Cli.without(t, f))

# vcluster create --upgrade: recreate an existing cluster, keeping its data.
def Cli.create_or_upgrade(up: Bool, c: Cmd) -> Cmd:
  match up c:
    case True{} Create{n, p, cpu, mem, etcd, nodes}:
      Upgrade{n, p, cpu, mem, etcd, nodes}
    case _ other:
      other

def Cli.after.go(hit: Bool, +v: String, rest: Maybe<&2, String>) -> Maybe<&2, String>:
  match hit:
    case True{}:
      Some{v}
    case False{}:
      rest

# The value after flag f, if f is among xs.
def Cli.after(xs: +List<String>, +f: String) -> Maybe<&2, String>:
  match xs:
    case Nil{}:
      None{}
    case Con{+x, +t}:
      match t:
        case Nil{}:
          None{}
        case Con{+v, t2}:
          Cli.after.go(String.eq(x, f), v, Cli.after(t, f))

def Cli.drop_flag.pick(hit: Bool, +x: String, skip: +List<String>, keep: +List<String>) -> +List<String>:
  match hit:
    case True{}:
      skip
    case False{}:
      Con{x, keep}

# xs without flag f and the value after it.
def Cli.drop_flag(xs: +List<String>, +f: String) -> +List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, +t}:
      match t:
        case Nil{}:
          Cli.drop_flag.pick(String.eq(x, f), x, Nil{}, Nil{})
        case Con{+v, t2}:
          Cli.drop_flag.pick(String.eq(x, f), x, Cli.drop_flag(t2, f), Cli.drop_flag(t, f))

# vcluster create --restore URL: create the cluster from a snapshot.
def Cli.create_restore(r: Maybe<&2, String>, +n: String, +c: Cmd) -> Cmd:
  match r:
    case Some{p}:
      Restore{n, Cli.strip_file(p)}
    case None{}:
      c

def Cli.classic_ns(ns: Maybe<&2, String>, +n: String) -> String:
  match ns:
    case Some{x}:
      x
    case None{}:
      "vcluster-" ++ n

# Classic mode (vcluster on a host cluster): `--host-kubeconfig F` names
# the host cluster, `--host-namespace NS` the namespace the syncer writes
# to (vcluster's default: vcluster-NAME).
def Cli.create_classic(k: Maybe<&2, String>, ns: Maybe<&2, String>, +n: String, +c: Cmd) -> Cmd:
  match k:
    case None{}:
      c
    case Some{f}:
      Classic{c, f, Cli.classic_ns(ns, n)}

def Cli.values_file.go(a: Maybe<&2, String>, b: Maybe<&2, String>) -> Maybe<&2, String>:
  match a:
    case Some{f}:
      Some{f}
    case None{}:
      b

# vcluster create -f/--values FILE: a vcluster.yaml (one file; --set is
# not supported).
def Cli.values_file(+rest: +List<String>) -> Maybe<&2, String>:
  Cli.values_file.go(Cli.after(rest, "-f"), Cli.after(rest, "--values"))

def Cli.create_values(f: Maybe<&2, String>, set: Bool, +c: Cmd) -> Cmd:
  match f set:
    case _ True{}:
      Help{"vk8s create: --set is not supported; put the values in a vcluster.yaml and pass it with -f\n"}
    case Some{file} False{}:
      WithValues{c, file}
    case None{} False{}:
      c

# vcluster create --connect (default true): connect after creating.
def Cli.create_connect(off: Bool, +c: Cmd) -> Cmd:
  match off:
    case True{}:
      NoConnect{c}
    case False{}:
      c

def Cli.verb.pick(cr: Bool, de: Bool, co: Bool, pa: Bool, re: Bool, +v: String, +name: String,
  +rest: +List<String>) -> Cmd:
  match cr de co pa re:
    case True{} _ _ _ _:
      Cli.create_values(Cli.values_file(rest), Cli.has(rest, "--set"),
      Cli.create_classic(Cli.after(rest, "--host-kubeconfig"), Cli.after(rest, "--host-namespace"), name,
      Cli.create_connect(Cli.has(rest, "--connect=false"), Cli.create_restore(Cli.after(rest, "--restore"), name,
        Cli.create_or_upgrade(Cli.has(rest, "--upgrade"), Cli.create_opts(Cli.drop_flag(Cli.drop_flag(Cli.drop_flag(Cli.drop_flag(Cli.drop_flag(Cli.without(Cli.without(Cli.without(rest, "--upgrade"), "--connect=false"), "--connect"), "--restore"), "--host-kubeconfig"), "--host-namespace"), "-f"), "--values"), Create{name, 0, 2, 2048, False{}, 0}))))))
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

def Cli.node_usage() -> Cmd:
  Help{"usage: vk8s node add NAME [--count N] | vk8s node delete NAME NODE [--drain=false]\n"}

def Cli.node_add.pos(zero: Bool, +n: String, +c: U32) -> Cmd:
  match zero:
    case True{}:
      Cli.node_usage()
    case False{}:
      NodeAdd{n, c}

def Cli.node_add.count(ok: Bool, m: Maybe<&2, U32>, +n: String) -> Cmd:
  match ok m:
    case True{} Some{+c}:
      Cli.node_add.pos(U32.is_eq(c, 0), n, c)
    case _ _:
      Cli.node_usage()

def Cli.node_add(rest: +List<String>, +n: String) -> Cmd:
  match rest:
    case Nil{}:
      NodeAdd{n, 1}
    case Con{+k, Con{+v, Nil{}}}:
      Cli.node_add.count(String.eq(k, "--count"), U32.read(v), n)
    case _:
      Cli.node_usage()

def Cli.node_delete.drain(d: Maybe<&2, Bool>, +n: String, +node: String) -> Cmd:
  match d:
    case Some{b}:
      NodeDelete{n, node, b}
    case None{}:
      Cli.node_usage()

def Cli.node_delete(rest: +List<String>, +n: String) -> Cmd:
  match rest:
    case Con{+node, Nil{}}:
      NodeDelete{n, node, True{}}
    case Con{+node, Con{+f, Nil{}}}:
      Cli.node_delete.drain(Cli.bool_flag(f, "--drain"), n, node)
    case _:
      Cli.node_usage()

def Cli.node_load.go(archive: Bool, image: Bool, +n: String, +node: String, +a: String) -> Cmd:
  match archive image:
    case True{} _:
      NodeLoad{n, node, a}
    case False{} True{}:
      Help{"vk8s node load-image: --image needs a Docker daemon, which a vk8s host does not have; save the image to a file and use --archive\n"}
    case False{} False{}:
      Cli.node_usage()

def Cli.node_load(rest: +List<String>, +n: String) -> Cmd:
  match rest:
    case Con{+node, Con{+f, Con{+a, Nil{}}}}:
      Cli.node_load.go(String.eq(f, "--archive"), String.eq(f, "--image"), n, node, a)
    case _:
      Cli.node_usage()

def Cli.node_of.go(add: Bool, del: Bool, load: Bool, ok: Bool, +n: String, rest: +List<String>) -> Cmd:
  match add del load ok:
    case True{} _ _ True{}:
      Cli.node_add(rest, n)
    case False{} True{} _ True{}:
      Cli.node_delete(rest, n)
    case False{} False{} True{} True{}:
      Cli.node_load(rest, n)
    case _ _ _ False{}:
      Cli.bad_name(n)
    case False{} False{} False{} True{}:
      Cli.node_usage()

# `node add NAME [--count N]`, `node delete NAME NODE [--drain=false]`
# (vcluster node delete: --drain, default true).
def Cli.node_of(rest: +List<String>) -> Cmd:
  match rest:
    case Con{+sub, Con{+n, more}}:
      Cli.node_of.go(String.eq(sub, "add"), Bool.or(String.eq(sub, "delete"), String.eq(sub, "remove")), String.eq(sub, "load-image"), Cli.valid_name(n), n, more)
    case _:
      Cli.node_usage()

def Cli.certs_usage() -> Cmd:
  Help{"usage: vk8s certs rotate|check NAME\n"}

def Cli.certs_of.go(ok: Bool, named: Bool, +a: String, +n: String) -> Cmd:
  match ok named:
    case True{} True{}:
      Certs{a, n}
    case True{} False{}:
      Cli.bad_name(n)
    case False{} _:
      Cli.certs_usage()

# vcluster certs rotate NAME, vcluster certs check NAME.
def Cli.certs_of(rest: +List<String>) -> Cmd:
  match rest:
    case Con{+a, Con{+n, Nil{}}}:
      Cli.certs_of.go(String.eq(a, "rotate") || String.eq(a, "check") || String.eq(a, "rotate-ca"), Cli.valid_name(n), a, n)
    case _:
      Cli.certs_usage()

def Cli.token_usage() -> Cmd:
  Help{"usage: vk8s token create NAME [--expires 1h] [--kubeadm] [--control-plane] | token list NAME [--output json] | token delete NAME ID\n"}

def Cli.token_create.k(ka: Bool, cp: Bool, ex: Bool, +k: String, +c: Cmd, a: Cmd, b: Cmd, e: Cmd) -> Cmd:
  match ka cp ex:
    case True{} _ _:
      a
    case False{} True{} _:
      b
    case False{} False{} True{}:
      e
    case False{} False{} False{}:
      Help{"vk8s token create: unknown option " ++ k ++ "\n"}

def Cli.token_set(c: Cmd, which: Nat, +v: String) -> Cmd:
  match c which:
    case TokenCreate{n, e, ka, cp} 0n:
      TokenCreate{n, v, ka, cp}
    case TokenCreate{n, e, ka, cp} 1n:
      TokenCreate{n, e, True{}, cp}
    case TokenCreate{n, e, ka, cp} _:
      TokenCreate{n, e, ka, True{}}
    case other _:
      other

# Options of `token create` (vcluster: --expires 1h, --kubeadm, --control-plane).
def Cli.token_create(xs: +List<String>, +c: Cmd) -> Cmd:
  match xs:
    case Nil{}:
      c
    case Con{+k, +t}:
      match t:
        case Nil{}:
          Cli.token_create.k(String.eq(k, "--kubeadm"), String.eq(k, "--control-plane"), String.eq(k, "--expires"), k, c,
            Cli.token_set(c, 1n, ""), Cli.token_set(c, 2n, ""), Help{"vk8s token create: --expires needs a value\n"})
        case Con{+v, rest}:
          Cli.token_create.k(String.eq(k, "--kubeadm"), String.eq(k, "--control-plane"), String.eq(k, "--expires"), k, c,
            Cli.token_create(t, Cli.token_set(c, 1n, "")), Cli.token_create(t, Cli.token_set(c, 2n, "")),
            Cli.token_create(rest, Cli.token_set(c, 0n, v)))

def Cli.token_list(rest: +List<String>, +n: String) -> Cmd:
  match rest:
    case Nil{}:
      TokenList{n, False{}}
    case Con{+k, Con{+v, Nil{}}}:
      Cli.out_value(String.eq(v, "json"), String.eq(v, "table"), v, j => TokenList{n, j}, "token list")
    case _:
      Cli.token_usage()

def Cli.token_delete(rest: +List<String>, +n: String) -> Cmd:
  match rest:
    case Con{+id, Nil{}}:
      TokenDelete{n, id}
    case _:
      Cli.token_usage()

def Cli.token_of.sub(cr: Bool, ls: Bool, del: Bool, +n: String, rest: +List<String>) -> Cmd:
  match cr ls del:
    case True{} _ _:
      Cli.token_create(rest, TokenCreate{n, "1h", False{}, False{}})
    case False{} True{} _:
      Cli.token_list(rest, n)
    case False{} False{} True{}:
      Cli.token_delete(rest, n)
    case False{} False{} False{}:
      Cli.token_usage()

def Cli.token_of.go(+sub: String, ok: Bool, +n: String, rest: +List<String>) -> Cmd:
  match ok:
    case False{}:
      Cli.bad_name(n)
    case True{}:
      Cli.token_of.sub(String.eq(sub, "create"), String.eq(sub, "list"), String.eq(sub, "delete"), n, rest)

# `token create|list|delete NAME ...` (vcluster token, on the cluster NAME).
def Cli.token_of(rest: +List<String>) -> Cmd:
  match rest:
    case Con{+sub, Con{+n, more}}:
      Cli.token_of.go(sub, Cli.valid_name(n), n, more)
    case _:
      Cli.token_usage()

def Cli.parse.token(tok: Bool, +v: String, rest: +List<String>) -> Cmd:
  match tok:
    case True{}:
      Cli.token_of(rest)
    case False{}:
      Cli.parse.named(v, rest)

def Cli.parse.certs(certs: Bool, +v: String, rest: +List<String>) -> Cmd:
  match certs:
    case True{}:
      Cli.certs_of(rest)
    case False{}:
      Cli.parse.token(String.eq(v, "token"), v, rest)

def Cli.parse.node(node: Bool, +v: String, rest: +List<String>) -> Cmd:
  match node:
    case True{}:
      Cli.node_of(rest)
    case False{}:
      Cli.parse.certs(String.eq(v, "certs"), v, rest)

def Cli.parse.cache(cache: Bool, +v: String, rest: +List<String>) -> Cmd:
  match cache:
    case True{}:
      Cli.cache_of(rest)
    case False{}:
      Cli.parse.node(String.eq(v, "node"), v, rest)

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

# The most a guest may write to its share (bend-vmm --share quota): its
# logs (which PID 1 trims), kubeconfig, join material and requests
# (security review F6).
def Cli.share_quota() -> String:
  "1G"

# Classic mode's two more forwards, which the vcluster's host Service
# points at (Cli.host_endpoints): konnectivity's agent port (8132) and the
# fake kubelet (10250), on host ports 13000 and 16000 plus the API port's
# offset in vcluster's 10000..12999.
def Cli.konn_port(+port: U32) -> U32:
  (13000 + (port % 3000 : U32) : U32)

def Cli.kubelet_port(+port: U32) -> U32:
  (16000 + (port % 3000 : U32) : U32)

def Cli.classic_forwards(classic: Bool, +port: U32) -> String:
  match classic:
    case True{}:
      ",127.0.0.1:" ++ U32.show(Cli.konn_port(port)) ++ ":8132,127.0.0.1:" ++ U32.show(Cli.kubelet_port(port)) ++ ":10250"
    case False{}:
      ""

def Cli.vmm_flags_x(+dir: String, +assets: String, +name: String, +port: U32, +cpus: U32, +mem: U32, +etcd: Bool, +extra: String) -> +List<String>:
  [ "--kernel", assets ++ "/Image",
    "--initrd", assets ++ "/vk8s.cpio",
    "--disk", assets ++ "/assets.img:ro," ++ dir ++ "/data.img",
    "--share", dir ++ "/share,quota=" ++ Cli.share_quota(),
    "--console-log", dir ++ "/console.log,max=64M,keep=2",
    "--mem", U32.show(mem),
    "--cpus", U32.show(cpus),
    "--forward", "127.0.0.1:" ++ U32.show(port) ++ ":6443" ++ Cli.classic_forwards(String.contains(extra, " VK8S_MODE=classic"), port),
    "--lan", dir ++ "/lan,ip=" ++ Cli.lan_ip(0) ++ "/24",
    "--control", dir ++ "/ctl.sock",
    "--cmdline", "console=ttyAMA0 quiet panic=5 VK8S_NAME=" ++ name ++ " VK8S_PORT=" ++ U32.show(port) ++ " VK8S_STORE=" ++ Cli.store_name(etcd) ++ extra ]

def Cli.vmm_flags(+dir: String, +assets: String, +name: String, +port: U32, +cpus: U32, +mem: U32, +etcd: Bool) -> +List<String>:
  Cli.vmm_flags_x(dir, assets, name, port, cpus, mem, etcd, "")

# Classic mode's extra kernel command line words.
def Cli.classic_cmdline(+ns: String) -> String:
  " VK8S_MODE=classic VK8S_HOST_NAMESPACE=" ++ ns

# With the host cluster's service CIDR (vcluster gives the virtual API
# server the host's range, pkg/util/servicecidr).
def Cli.classic_cmdline_cidr(+ns: String, +cidr: String) -> String:
  Cli.classic_cmdline(ns) ++ " VK8S_SERVICE_CIDR=" ++ cidr

# And the IP of the vcluster's host Service, for the API server's SANs.
def Cli.classic_cmdline_full(+ns: String, +cidr: String, +san: String) -> String:
  Cli.classic_cmdline_cidr(ns, cidr) ++ " VK8S_EXTRA_SAN=" ++ san

# The vcluster's own Service in the host namespace (vcluster: the Service
# named after the vcluster that fronts its API server), selector-less: its
# Endpoints point at the host's loopback forward of the virtual API server,
# which host-cluster pods reach as 10.0.2.2 through bend-vmm's NAT. The
# Service's targetPort is the virtual API server's 6443 (its own kubernetes
# service controller expects it); the Endpoints carry the real port.
def Cli.host_service(+name: String, +ns: String, +port: U32) -> String:
  "{\"apiVersion\":\"v1\",\"kind\":\"Service\",\"metadata\":{\"name\":" ++ String.quote(name) ++ ",\"namespace\":" ++ String.quote(ns)
    ++ ",\"labels\":{\"app\":\"vcluster\",\"release\":" ++ String.quote(name) ++ "}},\"spec\":{\"type\":\"ClusterIP\",\"ports\":["
    ++ "{\"name\":\"https\",\"port\":443,\"targetPort\":6443,\"protocol\":\"TCP\"},"
    ++ "{\"name\":\"kubelet\",\"port\":10250,\"targetPort\":10250,\"protocol\":\"TCP\"}]}}"

# Its Endpoints: the host's loopback forwards of the VM's 6443 and 10250
# (the fake kubelet; vcluster's Service has the same kubelet port, which
# the virtual default/kubernetes drops: services.TranslateServicePorts).
def Cli.host_endpoints(+name: String, +ns: String, +port: U32) -> String:
  "{\"apiVersion\":\"v1\",\"kind\":\"Endpoints\",\"metadata\":{\"name\":" ++ String.quote(name) ++ ",\"namespace\":" ++ String.quote(ns)
    ++ "},\"subsets\":[{\"addresses\":[{\"ip\":\"10.0.2.2\"}],\"ports\":["
    ++ "{\"name\":\"https\",\"port\":" ++ U32.show(port) ++ ",\"protocol\":\"TCP\"},"
    ++ "{\"name\":\"kubelet\",\"port\":" ++ U32.show(Cli.kubelet_port(port)) ++ ",\"protocol\":\"TCP\"}]}]}"

# The konnectivity agents' Service (src/guest/plan.bend: Konnectivity), its
# own so the virtual default/kubernetes, which mirrors the vcluster's
# Service, keeps https alone; its IP joins the API server's SANs too.
def Cli.konn_name(+name: String) -> String:
  name ++ "-konnectivity"

def Cli.konn_service(+name: String, +ns: String) -> String:
  "{\"apiVersion\":\"v1\",\"kind\":\"Service\",\"metadata\":{\"name\":" ++ String.quote(Cli.konn_name(name)) ++ ",\"namespace\":" ++ String.quote(ns)
    ++ ",\"labels\":{\"app\":\"vcluster\",\"release\":" ++ String.quote(name) ++ "}},\"spec\":{\"type\":\"ClusterIP\",\"ports\":["
    ++ "{\"name\":\"konnectivity\",\"port\":8132,\"targetPort\":8132,\"protocol\":\"TCP\"}]}}"

def Cli.konn_endpoints(+name: String, +ns: String, +port: U32) -> String:
  "{\"apiVersion\":\"v1\",\"kind\":\"Endpoints\",\"metadata\":{\"name\":" ++ String.quote(Cli.konn_name(name)) ++ ",\"namespace\":" ++ String.quote(ns)
    ++ "},\"subsets\":[{\"addresses\":[{\"ip\":\"10.0.2.2\"}],\"ports\":["
    ++ "{\"name\":\"konnectivity\",\"port\":" ++ U32.show(Cli.konn_port(port)) ++ ",\"protocol\":\"TCP\"}]}]}"

# vcluster picks the docker driver's host port in 10000..12999.
def Cli.port_from(+seed: U32) -> U32:
  (10000 + (seed % 3000 : U32) : U32)

def Cli.worker_name(+name: String, +i: U32) -> String:
  name ++ "-worker-" ++ U32.show(i)

# One cluster as `list` sees it: name, VM state (running, paused or
# stopped), creation time (Unix seconds and RFC 3339), whether it is the
# current kube context.
type Entry is Data:
  Entry{name: String, status: String, created: U32, created_at: String, connected: Bool}

# bend-vmm flags for worker i of a cluster: its own data disk and share
# (holding the join material), the cluster's LAN, no port forward.
def Cli.worker_flags(+dir: String, +ndir: String, +assets: String, +node: String, +i: U32, +token: String,
  +cpus: U32, +mem: U32) -> +List<String>:
  [ "--kernel", assets ++ "/Image",
    "--initrd", assets ++ "/vk8s.cpio",
    "--disk", assets ++ "/assets.img:ro," ++ ndir ++ "/data.img",
    "--share", ndir ++ "/share,quota=" ++ Cli.share_quota(),
    "--console-log", ndir ++ "/console.log,max=64M,keep=2",
    "--mem", U32.show(mem),
    "--cpus", U32.show(cpus),
    "--lan", dir ++ "/lan,ip=" ++ Cli.lan_ip(i) ++ "/24",
    "--control", ndir ++ "/ctl.sock",
    "--cmdline", "console=ttyAMA0 quiet panic=5 VK8S_ROLE=worker VK8S_NAME=" ++ node
      ++ " VK8S_NODE_IP=" ++ Cli.lan_ip(i) ++ " VK8S_TOKEN=" ++ token ]

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
# containerd reaches it as 10.0.2.2. 1 GiB: the kernel unpacks the whole
# initramfs (183 MB) into RAM, and with 512 MiB that failed ("Initramfs
# unpacking failed: write error"), so no registry started.
def Cli.cache_flags(+dir: String, +assets: String) -> +List<String>:
  [ "--kernel", assets ++ "/Image",
    "--initrd", assets ++ "/vk8s.cpio",
    "--disk", assets ++ "/assets.img:ro," ++ dir ++ "/data.img",
    "--share", dir ++ "/share,quota=" ++ Cli.share_quota(),
    "--console-log", dir ++ "/console.log,max=64M,keep=2",
    "--mem", "1024",
    "--cpus", "1",
    "--forward", Cli.cache_forwards(P.Plan.mirrors()),
    "--control", dir ++ "/ctl.sock",
    "--cmdline", "console=ttyAMA0 quiet panic=5 VK8S_ROLE=cache VK8S_NAME=vk8s-cache" ]

def Cli.workers.keep(m: Maybe<&2, U32>, rest: List<&2, U32>) -> List<&2, U32>:
  match m:
    case Some{i}:
      Con{i, rest}
    case None{}:
      rest

# A cluster's worker indices, as cluster.env's WORKERS keeps them
# ("1 2 4"): nodes come and go, so the indices need not be dense.
def Cli.workers.parse(ws: List<&2, String>) -> List<&2, U32>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{w, t}:
      Cli.workers.keep(U32.read(w), Cli.workers.parse(t))

def Cli.workers_of(+s: String) -> List<&2, U32>:
  Cli.workers.parse(String.split(s, ' '))

def Cli.workers_show(ws: List<&2, U32>) -> String:
  match ws:
    case Nil{}:
      ""
    case Con{i, Nil{}}:
      U32.show(i)
    case Con{i, t}:
      U32.show(i) ++ " " ++ Cli.workers_show(t)

# 1..n.
def Cli.workers_upto.go(k: Nat, +i: U32) -> List<&2, U32>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      Con{i, Cli.workers_upto.go(p, (i + 1 : U32))}

def Cli.workers_upto(+n: U32) -> List<&2, U32>:
  Cli.workers_upto.go(U32.to_nat(n), 1)

def Cli.workers_max(ws: List<&2, U32>) -> U32:
  match ws:
    case Nil{}:
      0
    case Con{+i, t}:
      U32.max(i, Cli.workers_max(t))

# The indices of `count` new workers after the existing ones.
def Cli.workers_next.go(k: Nat, +i: U32) -> List<&2, U32>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      Con{i, Cli.workers_next.go(p, (i + 1 : U32))}

def Cli.workers_next(ws: List<&2, U32>, +count: U32) -> List<&2, U32>:
  Cli.workers_next.go(U32.to_nat(count), (Cli.workers_max(ws) + 1 : U32))

def Cli.workers_drop.go(same: Bool, +i: U32, rest: List<&2, U32>) -> List<&2, U32>:
  match same:
    case True{}:
      rest
    case False{}:
      Con{i, rest}

def Cli.workers_drop(ws: List<&2, U32>, +j: U32) -> List<&2, U32>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{+i, t}:
      Cli.workers_drop.go(U32.is_eq(i, j), i, Cli.workers_drop(t, j))

def Cli.worker_index.go(prefixed: Bool, +rest: String) -> Maybe<&2, U32>:
  match prefixed:
    case True{}:
      U32.read(rest)
    case False{}:
      None{}

# Which worker a node name is: GUEST-worker-<i>.
def Cli.worker_index(+guest: String, +node: String) -> Maybe<&2, U32>:
  Cli.worker_index.go(String.starts_with(node, guest ++ "-worker-"), String.drop(node, Nat.add(String.length(guest), 8n)))

def Cli.tok_chr(c: Char) -> Bool:
  match c:
    case Chr{+u}:
      (U32.is_ge(u, 97) && U32.is_le(u, 122)) || (U32.is_ge(u, 48) && U32.is_le(u, 57))

def Cli.tok_all(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      Bool.and(Cli.tok_chr(c), Cli.tok_all(t))

def Cli.token_ok.go(ps: List<&2, String>) -> Bool:
  match ps:
    case Con{+id, Con{+sec, Nil{}}}:
      Nat.is_eq(String.length(id), 6n) && Nat.is_eq(String.length(sec), 16n) && Cli.tok_all(id) && Cli.tok_all(sec)
    case _:
      False{}

# A kubeadm bootstrap token, [a-z0-9]{6}.[a-z0-9]{16} (bootstraputil's
# BootstrapTokenPattern): what the host accepts from the guest's
# share/join-token before it reaches a worker's command line.
def Cli.token_ok(+t: String) -> Bool:
  Cli.token_ok.go(String.split(t, '.'))

# One token as `token list` shows it (vcluster's Token: ID, Created, Expires).
type TokEntry is Data:
  TokEntry{id: String, expires: String, created: String}

# A kubeadm bootstrap token as its Secret (k8s.io/cluster-bootstrap,
# kubeadm's BootstrapToken encoding): what `vk8s node add` applies so new
# workers join with a short-lived token of their own (security review H2).
def Cli.token_secret(+id: String, +secret: String, +expiration: String) -> String:
  "apiVersion: v1\nkind: Secret\nmetadata:\n  name: bootstrap-token-" ++ id ++ "\n  namespace: kube-system\n"
    ++ "type: bootstrap.kubernetes.io/token\nstringData:\n  token-id: " ++ id ++ "\n  token-secret: " ++ secret
    ++ "\n  expiration: " ++ expiration ++ "\n  usage-bootstrap-authentication: \"true\"\n  usage-bootstrap-signing: \"true\"\n"
    ++ "  auth-extra-groups: system:bootstrappers:kubeadm:default-node-token\n"

def Cli.tok_row(e: TokEntry) -> +List<String>:
  match e:
    case TokEntry{i, x, c}:
      [i, x, c]

def Cli.tok_rows(es: List<&2, TokEntry>) -> +List<+List<String>>:
  match es:
    case Nil{}:
      Nil{}
    case Con{e, t}:
      Con{Cli.tok_row(e), Cli.tok_rows(t)}

# vcluster token list: ID EXPIRES CREATED.
def Cli.token_table(es: List<&2, TokEntry>) -> String:
  T.Table.render(["ID", "EXPIRES", "CREATED"], Cli.tok_rows(es))

def Cli.tok_json(e: TokEntry) -> String:
  match e:
    case TokEntry{i, x, c}:
      "    {\n        \"ID\": " ++ String.quote(i) ++ ",\n        \"Created\": " ++ String.quote(c) ++ ",\n        \"Expires\": " ++ String.quote(x) ++ "\n    }"

def Cli.tok_jsons(es: List<&2, TokEntry>) -> List<&2, String>:
  match es:
    case Nil{}:
      Nil{}
    case Con{e, t}:
      Con{Cli.tok_json(e), Cli.tok_jsons(t)}

# json.MarshalIndent(tokens, "", "    ").
def Cli.token_json(es: List<&2, TokEntry>) -> String:
  +items : List<&2, String> = Cli.tok_jsons(es)
  Cli.list_json.go(List.is_empty(&2, String, items), items)
