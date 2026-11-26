import Base
import ./duration.bend as D
import ./table.bend as T
import ../guest/plan.bend as P
import bend-kube-runtime@0.12.0.0/src/time.bend as TM

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
  # snapshot create --format open: vcluster's archive (pkg/snapshot), not
  # the VM-level snapshot (docs/ref/snapshot-decisions.md D1)
  SnapshotOpen{name: String, path: String}
  AssetsPrune{dry: Bool}
  # cache prune [REGISTRY]: the registries whose cached blobs go
  CachePrune{registries: +List<String>}

def Cli.usage() -> String:
  "usage: vk8s <command>\n\n"
  ++ "  create NAME [--port P] [--cpus N] [--memory MiB] [--backing-store sqlite|etcd] [--nodes N] [--upgrade]\n"
  ++ "              [--host-kubeconfig FILE [--host-namespace NS]]   classic mode: sync to a host cluster\n"
  ++ "              [-f vcluster.yaml]                   vcluster.yaml: backing store, extraArgs (docs/CONFIG.md)\n"
  ++ "              [--connect=false] [--restore PATH]   (connects, as vcluster create does, unless --connect=false)\n"
  ++ "              [--gvisor]                           the gvisor RuntimeClass (gVisor's runsc set, fetched\n"
  ++ "                                                     only then; kept by --upgrade, node add and restore)\n"
  ++ "                                                     --backing-store etcd fetches the etcd set likewise\n"
  ++ "              [--mount HOSTDIR[:rw]]...            VM nodes: a host directory at the same path in each node,\n"
  ++ "                                                     read-only unless :rw (at most 6)\n"
  ++ "              [--host-socket GUESTPATH=HOSTPATH]...  VM nodes: a Unix socket of the node that reaches one of the host\n"
  ++ "              [--node-setup SCRIPT]                VM nodes: a script in the node (under a mount) that PID 1 runs as\n"
  ++ "                                                     root at every boot, before containerd (drop-ins in\n"
  ++ "                                                     /etc/containerd/conf.d, shims in /usr/local/bin)\n"
  ++ "                                                     (the three are kept by --upgrade, node add and restore)\n"
  ++ "              [--idle-sleep D]                     pause after D without API traffic, resume on the next request\n"
  ++ "                                                     (minutes, or 90s, 1h30m; 0: never; VK8S_IDLE_SLEEP; default 15)\n"
  ++ "                                                     VK8S_LAYERS=0: no shared layer store (VM nodes and node\n"
  ++ "                                                     containers share image layers through ~/.vk8s/layers\n"
  ++ "                                                     by default; a native host node with VK8S_LAYERS=1)\n"
  ++ "                                                     start a virtual cluster in a bend-vmm VM\n"
  ++ "  connect NAME [--print] [--update-current=false]    add context vk8s_NAME to $KUBECONFIG or ~/.kube/config\n"
  ++ "  connect NAME -- COMMAND [ARGS...]                  run a command against the cluster (KUBECONFIG set)\n"
  ++ "  list [--output json]                               list virtual clusters\n"
  ++ "  describe NAME [--config-only] [--output json]      describe a virtual cluster\n"
  ++ "  logs NAME [COMPONENT]                              print a component's log (no component: list them)\n"
  ++ "  snapshot create NAME PATH [--format vm|open]       write a snapshot (tar.gz) to a path or file:// URL\n"
  ++ "                                                     vm (default): pause the cluster and copy its VM disk\n"
  ++ "                                                     open: vcluster's snapshot archive (standalone clusters)\n"
  ++ "  restore NAME PATH                                  create cluster NAME from a snapshot (either format)\n"
  ++ "                                                     (the snapshot decides the backing store; so does --restore)\n"
  ++ "  pause NAME | resume NAME                           pause or resume a cluster's VM\n"
  ++ "  delete NAME [--delete-context=false]               stop a cluster, delete its state and its kube context\n"
  ++ "  node add NAME [--count N]                         start N more worker VMs that join the cluster\n"
  ++ "  node delete NAME NODE [--drain=false]              cordon, drain and delete a worker, then stop its VM\n"
  ++ "  node load-image NAME NODE --archive FILE           import an image archive (tar or tar.gz) into a node\n"
  ++ "  certs rotate|rotate-ca|check NAME                  renew the certificates (rotate-ca: the CA too) or show their expiry\n"
  ++ "  token create NAME [--expires 1h] [--kubeadm] [--control-plane]   a join token and its join command\n"
  ++ "                                                     (the curl command is for nodes on the VM LAN, 10.10.0.2:8443;\n"
  ++ "                                                     from this host the join server is 127.0.0.1:19000+PORT%3000)\n"
  ++ "  token list NAME [--output json] | token delete NAME ID\n"
  ++ "  cache start|stop|status                           the shared image cache VM (pull-through registries)\n"
  ++ "                                                     status: size per registry, data.img on the host, expiry\n"
  ++ "  cache prune [docker.io|registry.k8s.io|ghcr.io|quay.io]   empty the whole cache (every blob, any age;\n"
  ++ "                                                     a REGISTRY: only that one) and\n"
  ++ "                                                     give the space back to the host; no size cap otherwise:\n"
  ++ "                                                     an image expires 7 days after it was cached (not after\n"
  ++ "                                                     its last pull)\n"
  ++ "  assets prune [--dry-run]                          remove superseded guest asset versions from ~/.vk8s/assets\n"
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

# vcluster's other snapshot URLs (pkg/snapshot/options.go): oci, s3,
# container and https (Azure). Phase one refuses them by name
# (docs/ref/snapshot-decisions.md D3). "" for a local path.
def Cli.remote.pick(oci: Bool, s3: Bool, https: Bool, cont: Bool) -> String:
  match oci s3 https cont:
    case True{} _ _ _:
      "oci"
    case False{} True{} _ _:
      "s3"
    case False{} False{} True{} _:
      "https"
    case False{} False{} False{} True{}:
      "container"
    case False{} False{} False{} False{}:
      ""

def Cli.remote(+p: String) -> String:
  Cli.remote.pick(String.starts_with(p, "oci://"), String.starts_with(p, "s3://"), String.starts_with(p, "https://"),
    String.starts_with(p, "container://"))

def Cli.unsupported(+verb: String, +scheme: String) -> Cmd:
  Help{"vk8s " ++ verb ++ ": " ++ scheme ++ ":// is not supported yet (use a file path or file://)\n"}

def Cli.restore_of.go(is_local: Bool, +scheme: String, +n: String, +p: String) -> Cmd:
  match is_local:
    case True{}:
      Restore{n, Cli.strip_file(p)}
    case False{}:
      Cli.unsupported("restore", scheme)

# restore takes no --format: the host reads the archive's first entry
# (docs/ref/snapshot-decisions.md D2).
def Cli.restore_of.url(+scheme: String, +n: String, +p: String) -> Cmd:
  Cli.restore_of.go(String.is_empty(scheme), scheme, n, p)

def Cli.restore_of.path(rest: +List<String>, +n: String) -> Cmd:
  match rest:
    case Nil{}:
      Help{"vk8s restore: missing snapshot path\n"}
    case Con{+p, more}:
      Cli.restore_of.url(Cli.remote(p), n, p)

def Cli.has(xs: +List<String>, +f: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{x, t}:
      Bool.or(String.eq(x, f), Cli.has(t, f))

# The snapshot decides the backing store (docs/ref/snapshot-decisions.md
# D15): with --backing-store the parse gives msg, not c.
def Cli.refuse_store(hit: Bool, +msg: String, c: Cmd) -> Cmd:
  match hit:
    case True{}:
      Help{msg}
    case False{}:
      c

def Cli.restore_of(+rest: +List<String>, +n: String) -> Cmd:
  Cli.refuse_store(Cli.has(rest, "--backing-store"),
    "vk8s restore: --backing-store cannot be combined with restore; the snapshot decides the backing store\n",
    Cli.restore_of.path(rest, n))

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
      Cli.refuse_store(Cli.has(rest, "--restore") && Cli.has(rest, "--backing-store"),
      "vk8s create: --backing-store cannot be combined with --restore; the snapshot decides the backing store\n",
      Cli.create_values(Cli.values_file(rest), Cli.has(rest, "--set"),
      Cli.create_classic(Cli.after(rest, "--host-kubeconfig"), Cli.after(rest, "--host-namespace"), name,
      Cli.create_connect(Cli.has(rest, "--connect=false"), Cli.create_restore(Cli.after(rest, "--restore"), name,
        Cli.create_or_upgrade(Cli.has(rest, "--upgrade"), Cli.create_opts(Cli.drop_flag(Cli.drop_flag(Cli.drop_flag(Cli.drop_flag(Cli.drop_flag(Cli.without(Cli.without(Cli.without(rest, "--upgrade"), "--connect=false"), "--connect"), "--restore"), "--host-kubeconfig"), "--host-namespace"), "-f"), "--values"), Create{name, 0, 2, 2048, False{}, 0})))))))
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

def Cli.snapshot.fmt.go(is_open: Bool, is_vm: Bool, +f: String, +name: String, +path: String) -> Cmd:
  match is_open is_vm:
    case True{} _:
      SnapshotOpen{name, Cli.strip_file(path)}
    case False{} True{}:
      Snapshot{name, Cli.strip_file(path)}
    case False{} False{}:
      Help{"vk8s snapshot: --format is open or vm, not " ++ String.quote(f) ++ "\n"}

# --format open|vm (docs/ref/snapshot-decisions.md D1); nothing may follow.
def Cli.snapshot.fmt(rest: +List<String>, +f: String, +name: String, +path: String) -> Cmd:
  match rest:
    case Nil{}:
      Cli.snapshot.fmt.go(String.eq(f, "open"), String.eq(f, "vm"), f, name, path)
    case Con{+x, t}:
      Help{"vk8s snapshot: unexpected argument " ++ String.quote(x) ++ "\n"}

def Cli.snapshot.opt(sep: Bool, joined: Bool, +k: String, rest: +List<String>, +name: String, +path: String) -> Cmd:
  match sep joined:
    case True{} _:
      match rest:
        case Nil{}:
          Help{"vk8s snapshot: --format needs a value\n"}
        case Con{+v, t}:
          Cli.snapshot.fmt(t, v, name, path)
    case False{} True{}:
      Cli.snapshot.fmt(rest, String.drop(k, 9n), name, path)
    case False{} False{}:
      Help{"vk8s snapshot: unknown option " ++ k ++ "\n"}

# Options after PATH: none (the VM format) or --format.
def Cli.snapshot.opts(more: +List<String>, +name: String, +path: String) -> Cmd:
  match more:
    case Nil{}:
      Snapshot{name, Cli.strip_file(path)}
    case Con{+k, rest}:
      Cli.snapshot.opt(String.eq(k, "--format"), String.starts_with(k, "--format="), k, rest, name, path)

def Cli.snapshot.local(is_local: Bool, +scheme: String, +name: String, +path: String, more: +List<String>) -> Cmd:
  match is_local:
    case True{}:
      Cli.snapshot.opts(more, name, path)
    case False{}:
      Cli.unsupported("snapshot", scheme)

def Cli.snapshot.url(+scheme: String, +name: String, +path: String, more: +List<String>) -> Cmd:
  Cli.snapshot.local(String.is_empty(scheme), scheme, name, path, more)

def Cli.snapshot.go(ok: Bool, +name: String, +path: String, more: +List<String>) -> Cmd:
  match ok:
    case True{}:
      Cli.snapshot.url(Cli.remote(path), name, path, more)
    case False{}:
      Cli.bad_name(name)

def Cli.snapshot.sub(create: Bool, +sub: String, +name: String, +path: String, more: +List<String>) -> Cmd:
  match create:
    case True{}:
      Cli.snapshot.go(Cli.valid_name(name), name, path, more)
    case False{}:
      Help{"vk8s snapshot: unknown command " ++ String.quote(sub) ++ " (use create)\n"}

# `snapshot create NAME PATH [--format vm|open]` (vcluster snapshot create
# NAME URL).
def Cli.snapshot(rest: +List<String>) -> Cmd:
  match rest:
    case Con{+sub, Con{+name, Con{+path, more}}}:
      Cli.snapshot.sub(String.eq(sub, "create"), sub, name, path, more)
    case _:
      Help{"usage: vk8s snapshot create NAME PATH [--format vm|open]\n"}

def Cli.cache_of.go(ok: Bool, +a: String) -> Cmd:
  match ok:
    case True{}:
      Cache{a}
    case False{}:
      Help{"usage: vk8s cache start|stop|status\n"}

def Cli.cache_of.one(rest: +List<String>) -> Cmd:
  match rest:
    case Con{+a, Nil{}}:
      Cli.cache_of.go(String.eq(a, "start") || String.eq(a, "stop") || String.eq(a, "status"), a)
    case _:
      Help{"usage: vk8s cache start|stop|status\n"}

def Cli.cache_prune.one(known: Bool, +r: String) -> Cmd:
  match known:
    case True{}:
      CachePrune{[r]}
    case False{}:
      Help{"vk8s cache prune: unknown registry " ++ String.quote(r) ++ " (use docker.io, registry.k8s.io, ghcr.io or quay.io)\n"}

# `cache prune [REGISTRY]` (vk8s design): one registry the cache serves,
# or none for all of them.
def Cli.cache_prune(rest: +List<String>) -> Cmd:
  match rest:
    case Nil{}:
      CachePrune{P.Plan.cache_registries()}
    case Con{+r, Nil{}}:
      Cli.cache_prune.one(P.Plan.mirror_known(P.Plan.mirrors(), r), r)
    case _:
      Help{"usage: vk8s cache prune [docker.io|registry.k8s.io|ghcr.io|quay.io]\n"}

def Cli.cache_of.sub(prune: Bool, +a: String, t: +List<String>) -> Cmd:
  match prune:
    case True{}:
      Cli.cache_prune(t)
    case False{}:
      Cli.cache_of.one(Con{a, t})

def Cli.cache_of(rest: +List<String>) -> Cmd:
  match rest:
    case Con{+a, t}:
      Cli.cache_of.sub(String.eq(a, "prune"), a, t)
    case Nil{}:
      Help{"usage: vk8s cache start|stop|status\n"}

# `assets prune [--dry-run]` (vk8s design; vcluster has no equivalent).
def Cli.assets_usage() -> Cmd:
  Help{"usage: vk8s assets prune [--dry-run]\n"}

def Cli.assets_of.dry(dry: Bool) -> Cmd:
  match dry:
    case True{}:
      AssetsPrune{True{}}
    case False{}:
      Cli.assets_usage()

def Cli.assets_of.opts(rest: +List<String>) -> Cmd:
  match rest:
    case Nil{}:
      AssetsPrune{False{}}
    case Con{+k, Nil{}}:
      Cli.assets_of.dry(String.eq(k, "--dry-run"))
    case _:
      Cli.assets_usage()

def Cli.assets_of.go(prune: Bool, rest: +List<String>) -> Cmd:
  match prune:
    case True{}:
      Cli.assets_of.opts(rest)
    case False{}:
      Cli.assets_usage()

def Cli.assets_of(rest: +List<String>) -> Cmd:
  match rest:
    case Con{+a, more}:
      Cli.assets_of.go(String.eq(a, "prune"), more)
    case _:
      Cli.assets_usage()

# A release version dir, as vk8s downloads it: scripts/release-assets.sh
# names a release vK8S-HASH ("v", a digit, then "-" and 8 lowercase hex
# digits last; Manifest.version, e.g. v1.36.6-69181a9a). Local builds
# (scripts/guest/build.sh installs v1.36.6, or dev) and the staging dirs of
# a download (.fetch.XXXXXX) are not.
def Cli.v_digit(s: String) -> Bool:
  match s:
    case SCon{Chr{+v}, SCon{Chr{+d}, t}}:
      U32.is_eq(v, 118) && U32.is_ge(d, 48) && U32.is_le(d, 57)
    case _:
      False{}

def Cli.hex_all(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{Chr{+c}, t}:
      ((U32.is_ge(c, 48) && U32.is_le(c, 57)) || (U32.is_ge(c, 97) && U32.is_le(c, 102))) && Cli.hex_all(t)

def Cli.release_tail(+tail: String) -> Bool:
  Nat.is_eq(String.length(tail), 9n) && String.starts_with(tail, "-") && Cli.hex_all(String.drop(tail, 1n))

def Cli.release_name(+s: String) -> Bool:
  Cli.v_digit(s) && Cli.release_tail(String.drop(s, Nat.sub(String.length(s), 9n)))

def Cli.member(+x: String, ys: +List<String>) -> Bool:
  match ys:
    case Nil{}:
      False{}
    case Con{y, t}:
      String.eq(x, y) || Cli.member(x, t)

def Cli.asset_prunable(+pinned: String, +override: String, +in_use: +List<String>, +name: String) -> Bool:
  Cli.release_name(name) && Bool.not(String.eq(name, pinned)) && Bool.not(String.eq(name, override))
    && Bool.not(Cli.member(name, in_use))

def Cli.assets_prune.keep(go: Bool, +name: String, +rest: +List<String>) -> +List<String>:
  match go:
    case True{}:
      Con{name, rest}
    case False{}:
      rest

# The dirs of ~/.vk8s/assets (names) that `vk8s assets prune` removes:
# release versions other than the one this binary pins, the one
# VK8S_ASSETS names (override, a name or ""), and the ones a running VM
# boots from (in_use). A cluster's data disk is a copy of the template,
# so a stopped cluster needs no assets dir: it boots on the pinned one.
def Cli.assets_prune(names: +List<String>, +pinned: String, +override: String, +in_use: +List<String>) -> +List<String>:
  match names:
    case Nil{}:
      Nil{}
    case Con{+n, t}:
      Cli.assets_prune.keep(Cli.asset_prunable(pinned, override, in_use, n), n, Cli.assets_prune(t, pinned, override, in_use))

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

def Cli.parse.assets(assets: Bool, +v: String, rest: +List<String>) -> Cmd:
  match assets:
    case True{}:
      Cli.assets_of(rest)
    case False{}:
      Cli.parse.cache(String.eq(v, "cache"), v, rest)

def Cli.parse.more(snap: Bool, +v: String, rest: +List<String>) -> Cmd:
  match snap:
    case True{}:
      Cli.snapshot(rest)
    case False{}:
      Cli.parse.assets(String.eq(v, "assets"), v, rest)

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

# v2: also a cap on the entries a guest may create in its share (files,
# directories, symlinks), bend-vmm --share inodes (security review
# 2026-11-18 F4: the byte quota alone let a guest exhaust host inodes).
def Cli.share_quota.v2() -> String:
  "1G,inodes=100000"

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

# A standalone VM's join server (guest 8443, host/join_server.bend) on
# host port 19000 plus the API port's offset: 19000..21999, clear of
# classic's 13000.. and 16000.. ranges. vk8s design: vcluster serves the
# API and /node/join on one port; vk8s keeps the API on 6443.
def Cli.join_port(+port: U32) -> U32:
  (19000 + (port % 3000 : U32) : U32)

# Where nodes on the VM LAN reach the join server and the API server (the
# kubeadm controlPlaneEndpoint).
def Cli.join_endpoint() -> String:
  Cli.lan_ip(0) ++ ":8443"

def Cli.api_endpoint() -> String:
  Cli.lan_ip(0) ++ ":6443"

# The control-plane VM's port forwards: the API, then classic mode's two
# or a standalone VM's join server.
def Cli.forwards(classic: Bool, +port: U32) -> String:
  match classic:
    case True{}:
      "127.0.0.1:" ++ U32.show(port) ++ ":6443" ++ Cli.classic_forwards(True{}, port)
    case False{}:
      "127.0.0.1:" ++ U32.show(port) ++ ":6443,127.0.0.1:" ++ U32.show(Cli.join_port(port)) ++ ":8443"
# bend-vmm's automatic virtio-balloon (bend-vmm ea30ce3; docs/ref/
# footprint-decisions.md M1): free page reporting returns the pages the
# guest frees, and from 30 s after boot bend-vmm reads the guest's balloon
# stats every 2 s and inflates down to a floor of max(256 MiB, RAM/10)
# free (at most half of RAM), deflating at once below it. Every VM
# (control plane, workers, image cache) gets it, after its other flags.
# It is bend-vmm's default; vk8s still names it.
# The read-only assets disk is opened with nocache (F_NOCACHE): the guest
# caches it, so macOS need not cache the same blocks.
def Cli.balloon_flags() -> +List<String>:
  ["--balloon", "auto"]

def Cli.vmm_flags_x(+dir: String, +assets: String, +name: String, +port: U32, +cpus: U32, +mem: U32, +etcd: Bool, +extra: String) -> +List<String>:
  List.append(&2, String,
  [ "--kernel", assets ++ "/Image",
    "--initrd", assets ++ "/vk8s.cpio",
    "--disk", assets ++ "/assets.img:ro:nocache," ++ dir ++ "/data.img",
    "--share", dir ++ "/share,quota=" ++ Cli.share_quota.v2(),
    "--console-log", dir ++ "/console.log,max=64M,keep=2",
    "--mem", U32.show(mem),
    "--cpus", U32.show(cpus),
    "--forward", Cli.forwards(String.contains(extra, " VK8S_MODE=classic"), port),
    "--lan", dir ++ "/lan,ip=" ++ Cli.lan_ip(0) ++ "/24",
    "--control", dir ++ "/ctl.sock",
    "--cmdline", "console=ttyAMA0 quiet panic=5 VK8S_NAME=" ++ name ++ " VK8S_PORT=" ++ U32.show(port) ++ " VK8S_STORE=" ++ Cli.store_name(etcd) ++ extra ],
    Cli.balloon_flags())

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

# Every host port a cluster on API port `port` may forward: the API port,
# classic mode's konnectivity and kubelet forwards, and the standalone
# join server's. create probes them all, since a foreign listener on a
# derived port fails only when the VM starts
# (docs/ref/review-direct-commits-main.md F6).
def Cli.host_ports(+port: U32) -> List<&2, U32>:
  [port, Cli.konn_port(port), Cli.kubelet_port(port), Cli.join_port(port)]

# The seed of a port pick when the OS gives no random number (review
# F7): the clock in seconds, spread by the try's index, so the ten tries
# differ (997 and 3000 share no factor).
def Cli.fallback_seed(+secs: U32, +i: U32) -> U32:
  U32.add(secs, U32.mul(i, 997))

def Cli.recorded_elsewhere.line(+l: String, +self: String) -> Bool:
  Bool.not(String.is_empty(l)) && Bool.not(String.starts_with(l, self ++ ":"))

def Cli.recorded_elsewhere.go(ls: List<&2, String>, +self: String) -> Bool:
  match ls:
    case Nil{}:
      False{}
    case Con{l, t}:
      Cli.recorded_elsewhere.line(String.trim(l), self) || Cli.recorded_elsewhere.go(t, self)

# Whether `grep -rsHx --include=port PORT CLUSTERS` output (one
# "FILE:PORT" line per cluster that records PORT) names a port file
# other than self. Two creates that picked the same port at once both
# see the other's file and pick again (review F5).
def Cli.recorded_elsewhere(text: String, +self: String) -> Bool:
  Cli.recorded_elsewhere.go(String.lines(text), self)

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
  List.append(&2, String,
  [ "--kernel", assets ++ "/Image",
    "--initrd", assets ++ "/vk8s.cpio",
    "--disk", assets ++ "/assets.img:ro:nocache," ++ ndir ++ "/data.img",
    "--share", ndir ++ "/share,quota=" ++ Cli.share_quota.v2(),
    "--console-log", ndir ++ "/console.log,max=64M,keep=2",
    "--mem", U32.show(mem),
    "--cpus", U32.show(cpus),
    "--lan", dir ++ "/lan,ip=" ++ Cli.lan_ip(i) ++ "/24",
    "--control", ndir ++ "/ctl.sock",
    "--cmdline", "console=ttyAMA0 quiet panic=5 VK8S_ROLE=worker VK8S_NAME=" ++ node
      ++ " VK8S_NODE_IP=" ++ Cli.lan_ip(i) ++ " VK8S_TOKEN=" ++ token ],
    Cli.balloon_flags())

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
  List.append(&2, String,
  [ "--kernel", assets ++ "/Image",
    "--initrd", assets ++ "/vk8s.cpio",
    "--disk", assets ++ "/assets.img:ro:nocache," ++ dir ++ "/data.img",
    "--share", dir ++ "/share,quota=" ++ Cli.share_quota.v2(),
    "--console-log", dir ++ "/console.log,max=64M,keep=2",
    "--mem", "1024",
    "--cpus", "1",
    "--forward", Cli.cache_forwards(P.Plan.mirrors()),
    "--control", dir ++ "/ctl.sock",
    "--cmdline", "console=ttyAMA0 quiet panic=5 VK8S_ROLE=cache VK8S_NAME=vk8s-cache" ],
    Cli.balloon_flags())

# --- vk8s cache status|prune (vk8s design; vcluster has no image cache).
# The cache VM measures each registry's storage with `du -sk`
# (P.Plan.cache_usage: "KiB<TAB>registry" lines); the host measures
# data.img's allocated blocks with `du -k`. There is no size cap (user
# decision 2026-11-17): the cache expires an image 7 days after it was
# cached (P.Plan.cache_root's note), and the user prunes.

# A size in KiB as people read it, to a tenth (rounded down).
def Cli.size.tenths(+t: U32, +unit: String) -> String:
  U32.show((t / 10 : U32)) ++ "." ++ U32.show((t % 10 : U32)) ++ unit

def Cli.size.pick(kib: Bool, mib: Bool, +k: U32) -> String:
  match kib mib:
    case True{} _:
      U32.show(k) ++ " KiB"
    case False{} True{}:
      Cli.size.tenths(((k * 10 : U32) / 1024 : U32), " MiB")
    case False{} False{}:
      Cli.size.tenths((((k / 1024 : U32) * 10 : U32) / 1024 : U32), " GiB")

def Cli.size_kib(+k: U32) -> String:
  Cli.size.pick(U32.is_lt(k, 1024), U32.is_lt(k, 1048576), k)

def Cli.du_pick(hit: Bool, +k: String, more: U32) -> U32:
  match hit:
    case True{}:
      Cli.num(U32.read(String.trim(k)), 0)
    case False{}:
      more

def Cli.du_line(ws: List<&2, String>, +r: String, more: U32) -> U32:
  match ws:
    case Con{+k, Con{+n, Nil{}}}:
      Cli.du_pick(String.eq(String.trim(n), r), k, more)
    case _:
      more

# A registry's KiB in du's lines; 0 when it has no line.
def Cli.du_kib(ls: +List<String>, +r: String) -> U32:
  match ls:
    case Nil{}:
      0
    case Con{+l, t}:
      Cli.du_line(String.split(l, '\t'), r, Cli.du_kib(t, r))

def Cli.cache_rows(regs: +List<String>, +ls: +List<String>) -> String:
  match regs:
    case Nil{}:
      ""
    case Con{+r, t}:
      "  " ++ r ++ ": " ++ Cli.size_kib(Cli.du_kib(ls, r)) ++ "\n" ++ Cli.cache_rows(t, ls)

def Cli.cache_total(regs: +List<String>, +ls: +List<String>) -> U32:
  match regs:
    case Nil{}:
      0
    case Con{+r, t}:
      (Cli.du_kib(ls, r) + Cli.cache_total(t, ls) : U32)

# One line per registry the cache serves, then the total.
def Cli.cache_sizes(+text: String) -> String:
  +ls = String.lines(text)
  Cli.cache_rows(P.Plan.cache_registries(), ls) ++ "  total: " ++ Cli.size_kib(Cli.cache_total(P.Plan.cache_registries(), ls)) ++ "\n"

def Cli.cache_state(running: Bool) -> String:
  match running:
    case True{}:
      "running on 127.0.0.1:15001-15004"
    case False{}:
      "stopped"

def Cli.cache_status.sizes(none: Bool, fresh: Bool, +text: String) -> String:
  match none fresh:
    case True{} _:
      "  size per registry: not measured yet (the cache measures it while it runs)\n"
    case False{} True{}:
      Cli.cache_sizes(text)
    case False{} False{}:
      "  size per registry, as last measured while the cache ran:\n" ++ Cli.cache_sizes(text)

# distribution v3.1.2 schedules a blob's or manifest's expiry once, when
# it is fetched from the upstream (registry/proxy/proxyblobstore.go,
# proxymanifeststore.go); a pull served from the cache does not extend it.
def Cli.cache_expiry() -> String:
  "  expiry: a cached image is removed 7 days (168h) after it was cached;\n"
  ++ "  pulls from the cache do not extend it ('vk8s cache prune' removes it now)\n"

# vk8s cache status. text: the cache VM's du lines (fresh: measured now);
# img_kib: data.img's allocated KiB on the host, at path img.
def Cli.cache_status(running: Bool, fresh: Bool, +text: String, img_kib: U32, +img: String) -> String:
  "image cache: " ++ Cli.cache_state(running) ++ "\n"
    ++ Cli.cache_status.sizes(String.is_empty(String.trim(text)), fresh, text)
    ++ "  data.img on the host: " ++ Cli.size_kib(img_kib) ++ " allocated (" ++ img ++ ")\n"
    ++ Cli.cache_expiry()

# The host request that prunes these registries (P.Plan.cache_prune).
def Cli.cache_prune_action(regs: +List<String>) -> String:
  "cache-prune:" ++ String.join(regs, ",")

def Cli.minus.go(ok: Bool, +a: U32, +b: U32) -> U32:
  match ok:
    case True{}:
      (a - b : U32)
    case False{}:
      0

# a - b, or 0 when b is larger (data.img can grow while a cluster pulls).
def Cli.minus(+a: U32, +b: U32) -> U32:
  Cli.minus.go(U32.is_le(b, a), a, b)

def Cli.cache_pruned.list(regs: +List<String>, +ls: +List<String>) -> String:
  match regs:
    case Nil{}:
      ""
    case Con{+r, Nil{}}:
      r ++ " (" ++ Cli.size_kib(Cli.du_kib(ls, r)) ++ ")"
    case Con{+r, t}:
      r ++ " (" ++ Cli.size_kib(Cli.du_kib(ls, r)) ++ "), " ++ Cli.cache_pruned.list(t, ls)

# What vk8s cache prune freed: each registry's size before (before: the
# du lines measured then) and data.img's allocated KiB before and after.
def Cli.cache_pruned(regs: +List<String>, +before: String, +img0: U32, +img1: U32) -> String:
  "pruned " ++ Cli.cache_pruned.list(regs, String.lines(before)) ++ "\n"
    ++ "freed " ++ Cli.size_kib(Cli.minus(img0, img1)) ++ " on the host (data.img: " ++ Cli.size_kib(img0) ++ " -> "
    ++ Cli.size_kib(img1) ++ " allocated)\n"

# --- The image cache on the host (`vk8s cache serve`, host/cache/mirror.bend;
# vk8s design, vcluster has no image cache). It replaced the image cache
# VM: the same ports and commands, its store a host directory.

# The store's expiry (src/oci/store.bend Store.ttl: 72 h after the last
# use; user decision 2026-11-17: "3 days from last use comes later with a
# Bend registry").
def Cli.cache_expiry.v2() -> String:
  "  expiry: a cached blob is removed 72 hours (3 days) after its last use;\n"
  ++ "  every pull from the cache is a use ('vk8s cache prune' removes it now)\n"

# The disk an image cache VM of an older vk8s left (kib allocated).
def Cli.cache_old.v2(+kib: U32, +img: String) -> String:
  Bool.pick(String, U32.is_zero(kib), "", "  left by the old image cache VM: " ++ img ++ " (" ++ Cli.size_kib(kib)
    ++ " allocated; 'vk8s cache prune' removes it)\n")

# vk8s cache status, v2: the state, each registry's size in the store
# (text: "KiB<TAB>registry" lines, measured now), the store's path, an
# old cache VM's disk while it is there, and the expiry.
def Cli.cache_status.v2(running: Bool, +text: String, +store: String, +old_kib: U32, +old: String) -> String:
  "image cache: " ++ Cli.cache_state(running) ++ "\n"
    ++ "  size per registry:\n" ++ Cli.cache_sizes(text)
    ++ "  store on the host: " ++ store ++ "\n"
    ++ Cli.cache_old.v2(old_kib, old)
    ++ Cli.cache_expiry.v2()

# What vk8s cache prune freed, v2: each pruned registry's size before
# (before: its "KiB<TAB>registry" lines) and the sum, with the old cache
# VM's disk when it went too (old_kib, else 0).
def Cli.cache_pruned.v2(+regs: +List<String>, +before: String, +old_kib: U32) -> String:
  +ls = String.lines(before)
  "pruned " ++ Cli.cache_pruned.list(regs, ls) ++ "\n"
    ++ "freed " ++ Cli.size_kib((Cli.cache_total(regs, ls) + old_kib : U32)) ++ " on the host\n"

# --- Per-role asset sets (docs/ref/footprint-decisions.md D1).

# A control plane's role: classic with VK8S_MODE=classic on its command
# line, else standalone.
def Cli.cp_role.of(classic: Bool) -> String:
  match classic:
    case True{}:
      "classic"
    case False{}:
      "standalone"

def Cli.cp_role(+extra: String) -> String:
  Cli.cp_role.of(String.contains(extra, " VK8S_MODE=classic"))

def Cli.set_disks(+assets: String, sets: +List<String>) -> String:
  match sets:
    case Nil{}:
      ""
    case Con{s, t}:
      "," ++ assets ++ "/" ++ s ++ ".img:ro:nocache" ++ Cli.set_disks(assets, t)

# bend-vmm's --disk value: the base disk (/dev/vda), the VM's data disk
# (/dev/vdb), then one read-only disk per set (/dev/vdc onward). Read-only
# disks are nocache, as the single assets disk was: the guest caches them.
def Cli.disks_v3(+assets: String, +data: String, sets: +List<String>) -> String:
  assets ++ "/base.img:ro:nocache," ++ data ++ Cli.set_disks(assets, sets)

# The kernel command line's word that names the sets, in disk order.
def Cli.sets_word(sets: +List<String>) -> String:
  " VK8S_SETS=" ++ String.join(sets, ",")

def Cli.with_sets.pick(d: Bool, c: Bool, +v: String, +disks: String, +word: String) -> String:
  match d c:
    case True{} _:
      disks
    case False{} True{}:
      v ++ word
    case False{} False{}:
      v

# bend-vmm flags (flag, value pairs) with --disk's value replaced and
# word added to --cmdline's.
def Cli.with_sets(xs: +List<String>, +disks: String, +word: String) -> +List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, t}:
      match t:
        case Nil{}:
          [x]
        case Con{+v, t2}:
          Con{x, Con{Cli.with_sets.pick(String.eq(x, "--disk"), String.eq(x, "--cmdline"), v, disks, word), Cli.with_sets(t2, disks, word)}}

# A VM's flags with its role's sets (on: the assets dir is per-role, it
# has base.img); off, as they are (an older, single assets.img).
def Cli.role_flags(on: Bool, +flags: +List<String>, +assets: String, +data: String, +sets: +List<String>) -> +List<String>:
  match on:
    case True{}:
      Cli.with_sets(flags, Cli.disks_v3(assets, data, sets), Cli.sets_word(sets))
    case False{}:
      flags

# The kernel command line per arch (docs/ref/explore-linux-hosts.md
# Phase 2). The flag builders above write arm64's PL011 console
# (ttyAMA0). bend-vmm's x86_64 guests have COM1 (console=ttyS0), so on
# amd64 the --cmdline value names ttyS0 and ends in VK8S_ARCH=amd64, which
# PID 1 reads for its image import platform (P.Plan.arch_args). Nothing
# else moves, so the balloon flags stay last. Other arches pass unchanged.
def Cli.arch_word.go(hit: Bool, +w: String) -> String:
  match hit:
    case True{}:
      "console=ttyS0" ++ String.drop(w, 15n) ++ " VK8S_ARCH=amd64"
    case False{}:
      w

def Cli.arch_word(+w: String) -> String:
  Cli.arch_word.go(String.starts_with(w, "console=ttyAMA0 "), w)

def Cli.arch_words(xs: +List<String>) -> +List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      Con{Cli.arch_word(x), Cli.arch_words(rest)}

def Cli.arch_flags.go(amd64: Bool, flags: +List<String>) -> +List<String>:
  match amd64:
    case True{}:
      Cli.arch_words(flags)
    case False{}:
      flags

def Cli.arch_flags(+arch: String, flags: +List<String>) -> +List<String>:
  Cli.arch_flags.go(String.eq(arch, "amd64"), flags)

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

# Portable host strings (docs/ref/explore-linux-hosts.md, Phase 1): what the
# host runs works with the BSD userland of macOS and the GNU one of Linux.

# Copy a disk image or archive (D3 a) with cp and an argument list (no
# shell). GNU cp first: it clones where the file system can (btrfs, xfs)
# and keeps holes elsewhere. BSD cp rejects --reflink, so the host then
# runs cp with Cli.clone_bsd: the APFS clone macOS always made.
def Cli.clone_gnu(+src: String, +dst: String) -> +List<String>:
  ["--reflink=auto", "--sparse=always", src, dst]

def Cli.clone_bsd(+src: String, +dst: String) -> +List<String>:
  ["-c", src, dst]

# Dates. GNU and BSD date share +%s and +%z only, so the host reads those
# and Bend renders the rest (bend-kube's civil calendar).

def Cli.zone_ok(+z: String) -> Bool:
  Nat.is_eq(String.length(z), 5n) && (String.eq(String.take(z, 1n), "+") || String.eq(String.take(z, 1n), "-"))

def Cli.zone_secs.go(ok: Bool, h: Maybe<&2, U32>, m: Maybe<&2, U32>) -> U32:
  match ok h m:
    case True{} Some{+hh} Some{+mm}:
      ((hh * 60 + mm) * 60 : U32)
    case _ _ _:
      0

# The offset of a zone as `date +%z` prints it ("+0900", "-0530") in
# seconds; 0 (UTC) for anything else.
def Cli.zone_secs(+z: String) -> U32:
  Cli.zone_secs.go(Cli.zone_ok(z), U32.read(String.take(String.drop(z, 1n), 2n)), U32.read(String.drop(z, 3n)))

def Cli.local_secs.go(west: Bool, +secs: U32, +off: U32) -> U32:
  match west:
    case True{}:
      (secs - off : U32)
    case False{}:
      (secs + off : U32)

# A Unix time as the wall clock of zone z reads it, in seconds.
def Cli.local_secs(+secs: U32, +z: String) -> U32:
  Cli.local_secs.go(String.eq(String.take(z, 1n), "-"), secs, Cli.zone_secs(z))

def Cli.pick_str(b: Bool, +yes: String, +no: String) -> String:
  match b:
    case True{}:
      yes
    case False{}:
      no

# Go's "Z07:00": Z at offset zero, else -07:00.
def Cli.zone_colon(+z: String) -> String:
  Cli.pick_str(U32.is_eq(Cli.zone_secs(z), 0), "Z", String.take(z, 3n) ++ ":" ++ String.drop(z, 3n))

# Go's "-0700": +0000 at offset zero.
def Cli.zone_plain(+z: String) -> String:
  Cli.pick_str(U32.is_eq(Cli.zone_secs(z), 0), "+0000", z)

# time.RFC3339 ("2006-01-02T15:04:05Z07:00") of a Unix time in zone z.
def Cli.rfc3339_in(+secs: U32, +z: String) -> String:
  TM.Time.stamp(Cli.local_secs(secs, z)) ++ Cli.zone_colon(z)

# A bootstrap token's expiration, one hour after now (time.RFC3339, UTC).
def Cli.rfc3339_in_one_hour(+now: U32) -> String:
  TM.Time.rfc3339((now + 3600 : U32))

# The i-th three-letter name of a run of them.
def Cli.abbr(+names: String, +i: U32) -> String:
  String.take(String.drop(names, U32.to_nat((i * 3 : U32))), 3n)

def Cli.rfc1123z.of(+local: U32, c: TM.Civil, +z: String) -> String:
  match c:
    case TM.Civil{y, m, d}:
      Cli.abbr("ThuFriSatSunMonTueWed", ((local / 86400) % 7 : U32)) ++ ", " ++ TM.Time.pad(d, 2n) ++ " "
        ++ Cli.abbr("JanFebMarAprMayJunJulAugSepOctNovDec", (m - 1 : U32)) ++ " " ++ TM.Time.pad(y, 4n) ++ " "
        ++ TM.Time.clock((local % 86400 : U32)) ++ " " ++ Cli.zone_plain(z)

# time.RFC1123Z ("Mon, 02 Jan 2006 15:04:05 -0700") of a Unix time in zone
# z (1970-01-01 was a Thursday).
def Cli.rfc1123z(+secs: U32, +z: String) -> String:
  +local : U32 = Cli.local_secs(secs, z)
  Cli.rfc1123z.of(local, TM.Time.civil((local / 86400 : U32)), z)

# The creation time, in Unix seconds, of the cluster in "$d" into $c when
# its cluster.env has no CREATED: the directory's birth time, from GNU
# stat (BSD stat rejects -c) or BSD stat -f %B (GNU reads -f as file
# system status); 0 (no birth time on this file system) falls back to the
# modification time.
def Cli.created_sh() -> String:
  "[ -n \"$c\" ] || c=$(stat -c %W \"$d\" 2>/dev/null) || c=$(stat -f %B \"$d\"); [ \"$c\" != 0 ] || c=$(stat -c %Y \"$d\"); "

# Preflight (D4 a): the host tools vk8s runs, and for the VM backend on
# Linux read and write access to /dev/kvm (macOS uses Hypervisor.framework).
# The host looks each tool up through Bend file effects, with no shell.
def Cli.preflight_tools() -> +List<String>:
  ["nc", "curl", "kubectl", "tar"]

# A PATH entry; an empty one is the current directory (POSIX).
def Cli.path_dir(+d: String) -> String:
  Cli.pick_str(String.is_empty(d), ".", d)

def Cli.path_candidates.go(ds: +List<String>, +t: String) -> +List<String>:
  match ds:
    case Nil{}:
      Nil{}
    case Con{+d, rest}:
      Con{Cli.path_dir(d) ++ "/" ++ t, Cli.path_candidates.go(rest, t)}

# Where `command -v t` looks for tool t: each entry of PATH, in order.
def Cli.path_candidates(+path: String, +t: String) -> +List<String>:
  Cli.path_candidates.go(String.split(path, ':'), t)

# The PATH a root tool is looked up in: the user's PATH, then the sbin
# directories, which a regular user's PATH lacks on Debian while the tools
# there (iptables-save, modprobe) run through sudo, whose secure_path has
# them.
def Cli.root_path(+path: String) -> String:
  path ++ ":/usr/local/sbin:/usr/sbin:/sbin"

# Whether the VM backend needs /dev/kvm: on Linux only, which the host
# knows from /proc/sys/kernel/ostype ("" where there is no /proc).
def Cli.kvm_needed(vm: Bool, +ostype: String) -> Bool:
  vm && String.eq(String.trim(ostype), "Linux")

def Cli.tool_hint.go(nc: Bool, kvm: Bool, +t: String) -> String:
  match nc kvm:
    case True{} _:
      "nc (netcat-openbsd: vk8s uses nc -U)"
    case False{} True{}:
      "/dev/kvm (read and write access: sudo usermod -aG kvm \"$USER\", then log in again)"
    case False{} False{}:
      t

def Cli.tool_hint(+t: String) -> String:
  Cli.tool_hint.go(String.eq(t, "nc"), String.eq(t, "/dev/kvm"), t)

def Cli.tool_hints.keep(blank: Bool, +t: String, +rest: +List<String>) -> +List<String>:
  match blank:
    case True{}:
      rest
    case False{}:
      Con{Cli.tool_hint(t), rest}

def Cli.tool_hints(ts: +List<String>) -> +List<String>:
  match ts:
    case Nil{}:
      Nil{}
    case Con{+t, rest}:
      Cli.tool_hints.keep(String.is_empty(String.trim(t)), String.trim(t), Cli.tool_hints(rest))

def Cli.preflight.go(none: Bool, +hints: +List<String>) -> String:
  match none:
    case True{}:
      ""
    case False{}:
      "vk8s: missing on this host: " ++ String.join(hints, ", ") ++ "\n"

# The message for the missing names the preflight found ("" when none
# is missing).
def Cli.preflight(missing: +List<String>) -> String:
  +hints : +List<String> = Cli.tool_hints(missing)
  Cli.preflight.go(List.is_empty(&2, String, hints), hints)

# VK8S_WAIT_SCALE (vk8s design): how many times longer vk8s waits for its
# VMs. A whole number from 1 to 100; anything else, unset included, is 1.
# CI's emulated KVM host (QEMU TCG with EL2) runs guests tens of times
# slower than KVM.
def Cli.wait_scale.keep(ok: Bool, +v: U32) -> U32:
  match ok:
    case True{}:
      v
    case False{}:
      1

def Cli.wait_scale.of(m: Maybe<&2, U32>) -> U32:
  match m:
    case None{}:
      1
    case Some{+v}:
      Cli.wait_scale.keep(U32.is_ge(v, 1) && U32.is_le(v, 100), v)

def Cli.wait_scale(+s: String) -> U32:
  Cli.wait_scale.of(U32.read(s))

# n tries of a wait, times the scale s (VK8S_WAIT_SCALE).
def Cli.wait_tries(n: Nat, +s: String) -> Nat:
  Nat.mul(n, U32.to_nat(Cli.wait_scale(s)))

# The kernel command line word for a scale s (VK8S_WAIT_SCALE): none at
# scale 1, else " VK8S_WAIT_SCALE=<n>", which PID 1 reads to scale the
# guest plan's waits.
def Cli.scale_word.go(one: Bool, +n: U32) -> String:
  match one:
    case True{}:
      ""
    case False{}:
      " VK8S_WAIT_SCALE=" ++ U32.show(n)

def Cli.scale_word(+s: String) -> String:
  +n = Cli.wait_scale(s)
  Cli.scale_word.go(U32.is_eq(n, 1), n)

def Cli.cmdline_add.pick(c: Bool, +v: String, +word: String) -> String:
  match c:
    case True{}:
      v ++ word
    case False{}:
      v

# bend-vmm flags (flag, value pairs) with word added to --cmdline's value.
def Cli.cmdline_add(xs: +List<String>, +word: String) -> +List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, t}:
      match t:
        case Nil{}:
          [x]
        case Con{+v, t2}:
          Con{x, Con{Cli.cmdline_add.pick(String.eq(x, "--cmdline"), v, word), Cli.cmdline_add(t2, word)}}

# A VM's flags with the scale s (VK8S_WAIT_SCALE) on its kernel command
# line, so the guest waits as much longer as the host does.
def Cli.scale_flags(+s: String, flags: +List<String>) -> +List<String>:
  Cli.cmdline_add(flags, Cli.scale_word(s))

# --- The shared read-only layer store (docs/GOAL.md section 10): VM
# nodes get the host store as a second 9p share, read-only with Linux
# metadata from .bend-meta (bend-vmm's meta share), tagged layers, and
# VK8S_LAYERS=1 on the kernel command line (src/guest/plan.bend
# Plan.layers_on). On by default since Cli.layers_on.v2 (VK8S_LAYERS=0
# turns it off); Cli.layers_on was the opt-in. The image cache VM has no
# containerd and never gets it.

def Cli.layers_dir(+home: String) -> String:
  home ++ "/layers"

def Cli.layers_share(+dir: String) -> String:
  dir ++ ",tag=layers,meta,ro"

def Cli.layers_on(+env: String, +role: String) -> Bool:
  String.eq(env, "1") && Bool.not(String.eq(role, "cache"))

# The store on by default (v2, GOAL section 10: measured better on the
# Mac, regression 43/0, a certified run and a soak with it on):
# VK8S_LAYERS=0 is the opt-out; any other value, or none, is on. The
# image cache VM still never gets it.
def Cli.layers_on.v2(+env: String, +role: String) -> Bool:
  Bool.not(String.eq(env, "0")) && Bool.not(String.eq(role, "cache"))

def Cli.share_add.pick(hit: Bool, +x: String, +v: String, +share: String, rest: +List<String>) -> +List<String>:
  match hit:
    case True{}:
      Con{x, Con{v, Con{"--share", Con{share, rest}}}}
    case False{}:
      Con{x, Con{v, rest}}

# bend-vmm flags (flag, value pairs) with another --share after each
# --share (a VM has one, its cluster share, which keeps the first tag).
def Cli.share_add(xs: +List<String>, +share: String) -> +List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, t}:
      match t:
        case Nil{}:
          [x]
        case Con{+v, t2}:
          Cli.share_add.pick(String.eq(x, "--share"), x, v, share, Cli.share_add(t2, share))

# A VM's flags on the layer store at dir (on), or as they are (off).
def Cli.with_layers(on: Bool, +dir: String, flags: +List<String>) -> +List<String>:
  match on:
    case True{}:
      Cli.cmdline_add(Cli.share_add(flags, Cli.layers_share(dir)), " VK8S_LAYERS=1")
    case False{}:
      flags

# --- Host TLS (vk8s design; vcluster has no equivalent: Go links its own
# TLS). Every TLS path of a vk8s host dlopens OpenSSL 3 (or 1.1.1) at run
# time: bend-kube-runtime's Kubernetes client (src/effs/tls.c), the
# registry client of the image cache and the layer filler
# (host/effs/tls_server.c, TlsSrv.secure) and their SHA-256
# (host/oci/effs/oci_blob.c). All three search the same names, and
# BEND_KUBE_LIBSSL and BEND_KUBE_LIBCRYPTO replace the search. The host
# probes once (TlsSrv.listen on 127.0.0.1:0, which loads OpenSSL before
# it binds) and these decide what to say.

# Whether the host is macOS (`uname -s`).
def Cli.host_mac(+uname_s: String) -> Bool:
  String.eq(String.trim(uname_s), "Darwin")

# Whether the probe's failure text says OpenSSL could not be loaded (the
# loaders' texts start "TLS: "); "" (it loaded) and a socket error do not.
def Cli.tls_absent(+why: String) -> Bool:
  String.starts_with(why, "TLS: ")

# How to make OpenSSL 3 loadable, per host OS.
def Cli.tls_fix(mac: Bool) -> String:
  match mac:
    case True{}:
      "brew install openssl@3, or set BEND_KUBE_LIBSSL and BEND_KUBE_LIBCRYPTO to the paths of libssl.3.dylib and libcrypto.3.dylib"
    case False{}:
      "install OpenSSL 3 (the libssl3 package), or set BEND_KUBE_LIBSSL and BEND_KUBE_LIBCRYPTO to the paths of libssl.so.3 and libcrypto.so.3"

def Cli.tls_cause(+why: String) -> String:
  "OpenSSL 3 could not be loaded on this host (" ++ why ++ ")"

# A command that talks to a Kubernetes API through bend-kube-runtime's
# client cannot work without TLS: it stops before any change, with this.
def Cli.tls_needed(+what: String, mac: Bool, +why: String) -> String:
  what ++ " needs TLS to reach the Kubernetes API, but " ++ Cli.tls_cause(why) ++ ". Fix: " ++ Cli.tls_fix(mac)

def Cli.tls_degraded.text(cache: Bool, layers: Bool) -> String:
  match cache layers:
    case True{} True{}:
      "the image cache and the shared layer store cannot reach the registries over TLS: the image cache serves only images already in its store, and nodes pull and unpack the rest themselves (slower)"
    case True{} False{}:
      "the image cache cannot reach the registries over TLS: it serves only images already in its store, and nodes pull the rest themselves (slower)"
    case False{} True{}:
      "the shared layer store cannot reach the registries over TLS: nodes pull and unpack images themselves (slower)"
    case False{} False{}:
      ""

def Cli.tls_degraded.some(none: Bool, +what: String, mac: Bool, +why: String) -> String:
  match none:
    case True{}:
      ""
    case False{}:
      "warning: " ++ Cli.tls_cause(why) ++ ", so " ++ what ++ ". Fix: " ++ Cli.tls_fix(mac)

def Cli.tls_degraded.go(absent: Bool, +what: String, mac: Bool, +why: String) -> String:
  match absent:
    case False{}:
      ""
    case True{}:
      Cli.tls_degraded.some(String.is_empty(what), what, mac, why)

# The image cache and the shared layer store degrade instead: the warning
# for those that are on ("" when TLS loads or neither is on).
def Cli.tls_degraded(absent: Bool, cache: Bool, layers: Bool, mac: Bool, +why: String) -> String:
  Cli.tls_degraded.go(absent, Cli.tls_degraded.text(cache, layers), mac, why)

# The fix when a loader variable is set. A set BEND_KUBE_LIBSSL or
# BEND_KUBE_LIBCRYPTO is the only file a loader tries (no search), so
# "brew install openssl@3" or "set BEND_KUBE_LIBSSL and
# BEND_KUBE_LIBCRYPTO" (Cli.tls_fix) misleads there: on 2026-11-25
# `BEND_KUBE_LIBCRYPTO=/nonexistent vk8s create` on a Mac with Homebrew's
# openssl@3 said to install it. The fix names what is set, as the loaders
# see it (the user's value, or the release's host/ files that vk8s named).
def Cli.tls_named.go(no_ssl: Bool, no_crypto: Bool, +ssl: String, +crypto: String) -> String:
  match no_ssl no_crypto:
    case True{} True{}:
      ""
    case False{} True{}:
      "BEND_KUBE_LIBSSL=" ++ ssl
    case True{} False{}:
      "BEND_KUBE_LIBCRYPTO=" ++ crypto
    case False{} False{}:
      "BEND_KUBE_LIBSSL=" ++ ssl ++ " and BEND_KUBE_LIBCRYPTO=" ++ crypto

# The loader variables that are set, with their values ("" when neither).
def Cli.tls_named(+ssl: String, +crypto: String) -> String:
  Cli.tls_named.go(String.is_empty(ssl), String.is_empty(crypto), ssl, crypto)

def Cli.tls_libs(mac: Bool) -> String:
  match mac:
    case True{}:
      "a libssl.3.dylib and a libcrypto.3.dylib"
    case False{}:
      "a libssl.so.3 and a libcrypto.so.3"

def Cli.tls_fix.v2.go(none: Bool, mac: Bool, +named: String) -> String:
  match none:
    case True{}:
      Cli.tls_fix(mac)
    case False{}:
      "the search for OpenSSL is replaced by " ++ named ++ "; make BEND_KUBE_LIBSSL and BEND_KUBE_LIBCRYPTO name " ++ Cli.tls_libs(mac)
        ++ " that load, or unset them"

# How to make OpenSSL 3 loadable, given the loader variables' values.
def Cli.tls_fix.v2(mac: Bool, +ssl: String, +crypto: String) -> String:
  Cli.tls_fix.v2.go(String.is_empty(ssl) && String.is_empty(crypto), mac, Cli.tls_named(ssl, crypto))

def Cli.tls_needed.v2(+what: String, mac: Bool, +why: String, +ssl: String, +crypto: String) -> String:
  what ++ " needs TLS to reach the Kubernetes API, but " ++ Cli.tls_cause(why) ++ ". Fix: " ++ Cli.tls_fix.v2(mac, ssl, crypto)

def Cli.tls_degraded.v2.some(none: Bool, +what: String, +why: String, +fix: String) -> String:
  match none:
    case True{}:
      ""
    case False{}:
      "warning: " ++ Cli.tls_cause(why) ++ ", so " ++ what ++ ". Fix: " ++ fix

def Cli.tls_degraded.v2.go(absent: Bool, +what: String, +why: String, +fix: String) -> String:
  match absent:
    case False{}:
      ""
    case True{}:
      Cli.tls_degraded.v2.some(String.is_empty(what), what, why, fix)

def Cli.tls_degraded.v2(absent: Bool, cache: Bool, layers: Bool, mac: Bool, +why: String, +ssl: String, +crypto: String) -> String:
  Cli.tls_degraded.v2.go(absent, Cli.tls_degraded.text(cache, layers), why, Cli.tls_fix.v2(mac, ssl, crypto))

# --- The release's OpenSSL 3 on a Mac (docs/ref/macos-tls.md). When host/
# of the assets dir holds it (have) and neither BEND_KUBE_LIBSSL nor
# BEND_KUBE_LIBCRYPTO is set, vk8s points the loaders at it before its
# first TLS call (each loader reads them when it first loads), and every
# process it starts inherits them. Its compiled-in OPENSSLDIR is
# Homebrew's, where a clean Mac has no CA bundle, so SSL_CERT_FILE names
# macOS's own unless SSL_CERT_FILE or SSL_CERT_DIR is set. The result is
# name, value, name, value...; [] leaves the environment as it is (a
# variable set by the user wins, and so does a whole OpenSSL they named).
def Cli.tls_env.certs(set: Bool) -> +List<String>:
  match set:
    case True{}:
      Nil{}
    case False{}:
      ["SSL_CERT_FILE", "/etc/ssl/cert.pem"]

def Cli.tls_env.go(on: Bool, certs: Bool, +dir: String) -> +List<String>:
  match on:
    case False{}:
      Nil{}
    case True{}:
      List.append(&2, String, ["BEND_KUBE_LIBSSL", dir ++ "/libssl.3.dylib", "BEND_KUBE_LIBCRYPTO", dir ++ "/libcrypto.3.dylib"], Cli.tls_env.certs(certs))

def Cli.tls_env(have: Bool, +ssl: String, +crypto: String, +cert_file: String, +cert_dir: String, +dir: String) -> +List<String>:
  Cli.tls_env.go(have && String.is_empty(ssl) && String.is_empty(crypto),
    Bool.not(String.is_empty(cert_file) && String.is_empty(cert_dir)), dir)

# A VM-format snapshot's metadata.json, the archive's first entry (vk8s's
# format; restore takes the first entry's name as the kind): the cluster's
# name and its cluster.env settings GUEST, KUBERNETES, STORE and NODES,
# spliced as they are, as the printf it replaces did.
def Cli.snapshot_meta(+name: String, +guest: String, +k8s: String, +store: String, +nodes: String) -> String:
  "{\"name\":\"" ++ name ++ "\",\"guest\":\"" ++ guest ++ "\",\"kubernetesVersion\":\"" ++ k8s ++ "\",\"backingStore\":\"" ++ store
    ++ "\",\"nodes\":" ++ nodes ++ ",\"vk8s\":\"0.1.0\"}\n"

# A cluster.env with new NODES and WORKERS settings (vk8s's format; no
# grep, printf or mv process, docs/GOAL.md section 11): every line but a
# NODES= or WORKERS= one, in order and each ended by a newline (a last
# line without one gets it, as grep printed it), then NODES=count and
# WORKERS=shown.
def Cli.env_workers.keep(+l: String) -> String:
  Bool.pick(String, String.starts_with(l, "WORKERS=") || String.starts_with(l, "NODES="), "", l ++ "\n")

def Cli.env_workers.one(+l: String, last: Bool) -> String:
  match last:
    case True{}:
      Bool.pick(String, String.is_empty(l), "", Cli.env_workers.keep(l))
    case False{}:
      Cli.env_workers.keep(l)

def Cli.env_workers.lines(ls: List<&2, String>) -> String:
  match ls:
    case Nil{}:
      ""
    case Con{+l, +t}:
      Cli.env_workers.one(l, List.is_empty(&2, String, t)) ++ Cli.env_workers.lines(t)

def Cli.env_workers(+env: String, +count: U32, +shown: String) -> String:
  Cli.env_workers.lines(String.lines(env)) ++ "NODES=" ++ U32.show(count) ++ "\nWORKERS=" ++ shown ++ "\n"

# The CA of a vk8s kubeconfig as `token create --kubeadm` hashes it (no
# sed or base64 process, docs/GOAL.md section 11): the base64 text after
# the first `certificate-authority-data:` key at the start of a line
# (only spaces before it, spaces after the colon dropped), as
#   sed -n 's/^ *certificate-authority-data: *//p' | head -1
# printed it; "" when there is none. The host decodes it.
def Cli.ca_data.sp(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+h, +t}:
      Bool.pick(String, Char.is_eq(h, ' '), Cli.ca_data.sp(t), SCon{h, t})

def Cli.ca_data.hit(+l: String) -> Bool:
  String.starts_with(Cli.ca_data.sp(l), "certificate-authority-data:")

def Cli.ca_data.val(+l: String) -> String:
  Cli.ca_data.sp(String.drop(Cli.ca_data.sp(l), 27n))

def Cli.ca_data.go(ls: List<&2, String>) -> String:
  match ls:
    case Nil{}:
      ""
    case Con{+l, t}:
      Bool.pick(String, Cli.ca_data.hit(l), Cli.ca_data.val(l), Cli.ca_data.go(t))

def Cli.ca_data(+kc: String) -> String:
  Cli.ca_data.go(String.lines(kc))

# --- Classic-mode delete on the host cluster (no kubectl, docs/GOAL.md
# section 11): what vk8s delete removes from the host namespace and the
# host cluster through bend-kube-runtime's client on the host kubeconfig,
# after the VMs stop (so the syncer cannot make them again). vcluster
# delete uninstalls its helm release, whose objects these stand for, and
# the syncer's objects carry translate.MarkerLabel.

# A resource to delete: API group, version, kind, plural.
type CleanKind is Data:
  CleanKind{group: String, version: String, kind: String, plural: String}

# The Services vk8s made for the cluster in the host namespace.
def Cli.cleanup.services(+name: String) -> +List<String>:
  [name, name ++ "-konnectivity", name ++ "-kubelet"]

# vcluster's leader election lease (pkg/leaderelection:
# SafeConcatName("vcluster", VClusterName, "controller")).
def Cli.cleanup.lease(+name: String) -> String:
  "vcluster-" ++ name ++ "-controller"

# The syncer's objects (pkg/util/translate MarkerLabel
# "vcluster.loft.sh/managed-by").
def Cli.cleanup.selector(+name: String) -> String:
  "vcluster.loft.sh/managed-by=" ++ name

# The kinds deleted by that label in the host namespace, in this order.
def Cli.cleanup.ns_kinds() -> List<&2, CleanKind>:
  [CleanKind{"", "v1", "Pod", "pods"}, CleanKind{"", "v1", "Service", "services"},
    CleanKind{"", "v1", "Endpoints", "endpoints"}, CleanKind{"", "v1", "ConfigMap", "configmaps"},
    CleanKind{"", "v1", "Secret", "secrets"}, CleanKind{"", "v1", "ServiceAccount", "serviceaccounts"},
    CleanKind{"", "v1", "PersistentVolumeClaim", "persistentvolumeclaims"}]

# The cluster-wide kinds deleted by that label, in this order.
def Cli.cleanup.cluster_kinds() -> List<&2, CleanKind>:
  [CleanKind{"", "v1", "PersistentVolume", "persistentvolumes"},
    CleanKind{"storage.k8s.io", "v1", "StorageClass", "storageclasses"},
    CleanKind{"scheduling.k8s.io", "v1", "PriorityClass", "priorityclasses"}]

# The host namespace goes when vcluster created it (pkg/cli/delete_helm.go:
# the annotation CreatedByVClusterAnnotation "vcluster.loft.sh/created" is
# "true") and no other vcluster is left in it (delete_helm.go: len(vClusters)
# > 0 keeps it; find.VirtualClusterSelector "app=vcluster", here on the
# host Services classic clusters make).
def Cli.cleanup.drop_ns(+created: String, left: Bool) -> Bool:
  String.eq(created, "true") && Bool.not(left)

# What delete says once the namespace is gone (delete_helm.go Donef).
def Cli.cleanup.ns_done(+ns: String) -> String:
  "Successfully deleted virtual cluster namespace " ++ ns

# --- Optional sets on demand (docs/GOAL.md section 11). gVisor is off
# unless a cluster is made with --gvisor (--gvisor=true; --gvisor=false
# turns it off on --upgrade): its nodes then attach the gvisor set and
# get the gvisor RuntimeClass. As --idle-sleep does, the flag becomes an
# environment variable for one run (main runs vk8s again without it and
# with VK8S_GVISOR set), so every create path reads one setting; the
# cluster's cluster.env keeps the choice (GVISOR=1 or 0), so upgrade,
# node add and restore attach the same sets. Cert rotation boots no VM
# and leaves cluster.env as it is.

def Cli.gvisor.env_name() -> String:
  "VK8S_GVISOR"

def Cli.gvisor.is_flag(+x: String) -> Bool:
  String.eq(x, "--gvisor") || String.eq(x, "--gvisor=true") || String.eq(x, "--gvisor=false")

# Whether the arguments before "--" (a command connect runs) hold the flag.
def Cli.gvisor.has_flag(xs: +List<String>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{+x, t}:
      Bool.not(String.eq(x, "--")) && (Cli.gvisor.is_flag(x) || Cli.gvisor.has_flag(t))

def Cli.gvisor.show(b: Bool) -> String:
  match b:
    case True{}:
      "1"
    case False{}:
      "0"

def Cli.gvisor.value.pick(dash: Bool, m: Maybe<&2, Bool>, +rest: String) -> String:
  match dash m:
    case True{} _:
      ""
    case False{} Some{b}:
      Cli.gvisor.show(b)
    case False{} None{}:
      rest

# The flag's value as VK8S_GVISOR takes it: "1" (--gvisor, --gvisor=true),
# "0" (--gvisor=false), "" (no flag); the first one counts.
def Cli.gvisor.value(xs: +List<String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+x, t}:
      Cli.gvisor.value.pick(String.eq(x, "--"), Cli.bool_flag(x, "--gvisor"), Cli.gvisor.value(t))

def Cli.gvisor.drop.pick(dash: Bool, hit: Bool, +x: String, +t: +List<String>, rest: +List<String>) -> +List<String>:
  match dash hit:
    case True{} _:
      Con{x, t}
    case False{} True{}:
      rest
    case False{} False{}:
      Con{x, rest}

# The arguments without the flag (before "--").
def Cli.gvisor.drop(xs: +List<String>) -> +List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, +t}:
      Cli.gvisor.drop.pick(String.eq(x, "--"), Cli.gvisor.is_flag(x), x, t, Cli.gvisor.drop(t))

def Cli.gvisor.yes(+s: String) -> Bool:
  String.eq(s, "1") || String.eq(s, "true")

def Cli.gvisor.no(+s: String) -> Bool:
  String.eq(s, "0") || String.eq(s, "false")

def Cli.gvisor.on.pick(yes: Bool, no: Bool, rec: Bool) -> Bool:
  match yes no:
    case True{} _:
      True{}
    case False{} True{}:
      False{}
    case False{} False{}:
      rec

# Whether a cluster runs gVisor: the setting (VK8S_GVISOR, from --gvisor)
# when it says yes or no, else the cluster's record (cluster.env GVISOR),
# else off.
def Cli.gvisor.on(+setting: String, +rec: String) -> Bool:
  Cli.gvisor.on.pick(Cli.gvisor.yes(setting), Cli.gvisor.no(setting), Cli.gvisor.yes(rec))

# cluster.env's record of the choice.
def Cli.gvisor.env_line(on: Bool) -> String:
  "GVISOR=" ++ Cli.gvisor.show(on) ++ "\n"

def Cli.gvisor.drop_record(ls: +List<String>) -> +List<String>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{+l, t}:
      Cli.without.keep(String.starts_with(l, "GVISOR=") || String.is_empty(l), l, Cli.gvisor.drop_record(t))

# A cluster.env with its GVISOR line (any old one, and empty lines, gone)
# last.
def Cli.gvisor.with_record(+env: String, on: Bool) -> String:
  String.join(Cli.gvisor.drop_record(String.split(env, '\n')), "\n") ++ "\n" ++ Cli.gvisor.env_line(on)

# A record carried into a rewritten cluster.env (upgrade, restore): none
# when there was none.
def Cli.gvisor.keep.go(none: Bool, +rec: String) -> String:
  match none:
    case True{}:
      ""
    case False{}:
      "GVISOR=" ++ rec ++ "\n"

def Cli.gvisor.keep(+rec: String) -> String:
  Cli.gvisor.keep.go(String.is_empty(rec), rec)

# A VM's flags with gVisor on (VK8S_GVISOR=1 on its kernel command line:
# PID 1 then writes the runsc runtime and the gvisor RuntimeClass,
# P.Plan.with_gvisor), or as they are.
def Cli.gvisor_flags(on: Bool, flags: +List<String>) -> +List<String>:
  match on:
    case True{}:
      Cli.cmdline_add(flags, " VK8S_GVISOR=1")
    case False{}:
      flags

# The line create prints: the optional features that are off, each with
# the flag that turns it on; nothing when all are on.
def Cli.optional_off(gvisor: Bool, etcd: Bool) -> String:
  match gvisor etcd:
    case True{} True{}:
      ""
    case False{} True{}:
      "Optional features off: gVisor (--gvisor)"
    case True{} False{}:
      "Optional features off: etcd (--backing-store etcd)"
    case False{} False{}:
      "Optional features off: gVisor (--gvisor), etcd (--backing-store etcd)"

# --- Fewer shell-outs, batch 10 (docs/GOAL.md section 11): the decisions
# that replace uname, grep, and sh's dirname, basename, cd and pwd.

# `uname -m` from bend-vmm's Hvf.arch: 0 for an arm64 build, 1 for an
# x86_64 one. vk8s runs natively, so its own arch is the host's (on Linux
# arm64 uname said aarch64; M.Manifest.arch reads both as arm64).
def Cli.machine(+code: U32) -> String:
  Cli.pick_str(U32.is_zero(code), "arm64", Cli.pick_str(U32.is_eq(code, 1), "x86_64", ""))

# `uname -s` from bend-vmm's Hvf.sock_path_max, the bytes of a Unix socket
# path less its closing 0: macOS's sockaddr_un holds 104 (sys/un.h: char
# sun_path[104]), Linux's 108 (linux/un.h: UNIX_PATH_MAX 108). Any other
# answer names no OS vk8s knows ("": the VM backend by default, as an
# unknown uname -s was).
def Cli.os_of(+sock_max: U32) -> String:
  Cli.pick_str(U32.is_eq(sock_max, 103), "Darwin", Cli.pick_str(U32.is_eq(sock_max, 107), "Linux", ""))

# A cluster's port file as create's port pick reads it: its path and text.
type PortFile is Data:
  PortFile{path: String, text: String}

def Cli.has_line(ls: List<&2, String>, +want: String) -> Bool:
  match ls:
    case Nil{}:
      False{}
    case Con{l, t}:
      String.eq(l, want) || Cli.has_line(t, want)

# Whether a port file other than self records port p: one of its lines is
# exactly the port (grep -x), as `grep -rsHx --include=port -e P` found it
# (Cli.recorded_elsewhere read that grep's output).
def Cli.port_in(fs: List<&2, PortFile>, +self: String, +p: U32) -> Bool:
  match fs:
    case Nil{}:
      False{}
    case Con{f, t}:
      match f:
        case PortFile{path, text}:
          (Bool.not(String.eq(path, self)) && Cli.has_line(String.lines(text), U32.show(p))) || Cli.port_in(t, self, p)

# A path's pieces, last first, with the empty ones a trailing slash
# leaves dropped: POSIX dirname and basename ignore trailing slashes.
def Cli.path.drop_empty(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      match x:
        case SNil{}:
          Cli.path.drop_empty(t)
        case SCon{c, r}:
          Con{SCon{c, r}, t}

def Cli.path.rev(+p: String) -> List<&2, String>:
  Cli.path.drop_empty(List.reverse(&2, String, String.split(p, '/')))

def Cli.path.tail(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      t

def Cli.path.none(+p: String, +abs: String) -> String:
  Cli.pick_str(String.is_empty(p), ".", abs)

def Cli.path.dir_of(ys: List<&2, String>, +abs: Bool) -> String:
  match ys:
    case Nil{}:
      Cli.pick_str(abs, "/", ".")
    case Con{y, t}:
      String.join(List.reverse(&2, String, Con{y, t}), "/")

def Cli.dirname.go(xs: List<&2, String>, +p: String) -> String:
  match xs:
    case Nil{}:
      Cli.path.none(p, "/")
    case Con{x, t}:
      Cli.path.dir_of(Cli.path.drop_empty(t), String.starts_with(p, "/"))

# POSIX dirname: "/a/b/" is "/a", "a" is ".", "/a" and "/" are "/".
def Cli.dirname(+p: String) -> String:
  Cli.dirname.go(Cli.path.rev(p), p)

def Cli.basename.go(xs: List<&2, String>, +p: String) -> String:
  match xs:
    case Nil{}:
      Cli.pick_str(String.is_empty(p), "", "/")
    case Con{x, t}:
      x

# POSIX basename: "/a/b/" is "b", "/" is "/".
def Cli.basename(+p: String) -> String:
  Cli.basename.go(Cli.path.rev(p), p)

# One piece of a path as `cd -L` (sh's default) takes it: "" and "." stay
# put, ".." goes up a level (lexically, never past /), a name goes down.
def Cli.path.step(stay: Bool, up: Bool, +c: String, st: List<&2, String>) -> List<&2, String>:
  match stay up:
    case True{} _:
      st
    case False{} True{}:
      Cli.path.tail(st)
    case False{} False{}:
      Con{c, st}

def Cli.path.canon.go(cs: List<&2, String>, st: List<&2, String>) -> List<&2, String>:
  match cs:
    case Nil{}:
      st
    case Con{+c, t}:
      Cli.path.canon.go(t, Cli.path.step(String.is_empty(c) || String.eq(c, "."), String.eq(c, ".."), c, st))

# The directory `cd D && pwd` prints for an absolute D (logical: a
# symbolic link stays a name, as sh's cd and pwd keep $PWD).
def Cli.path.canon(+d: String) -> String:
  "/" ++ String.join(List.reverse(&2, String, Cli.path.canon.go(String.split(d, '/'), Nil{})), "/")

def Cli.abs_path.go(abs: Bool, rel: Bool, +pwd: String, +f: String) -> String:
  match abs rel:
    case True{} _:
      Cli.path.canon(Cli.dirname(f)) ++ "/" ++ Cli.basename(f)
    case False{} True{}:
      Cli.path.canon(pwd ++ "/" ++ Cli.dirname(f)) ++ "/" ++ Cli.basename(f)
    case False{} False{}:
      f

# A file's absolute path as classic create recorded the host kubeconfig's:
#   printf '%s/%s' "$(cd "$(dirname "$f")" && pwd)" "$(basename "$f")"
# A relative f is taken from pwd ($PWD, which sh's pwd prints); with no
# absolute pwd, f stays as it is.
def Cli.abs_path(+pwd: String, +f: String) -> String:
  Cli.abs_path.go(String.starts_with(f, "/"), String.starts_with(pwd, "/"), pwd, f)

# --- The Nodes a restore leaves behind. A snapshot's store holds the Node
# objects of the cluster it was taken from, and vk8s names a node after
# its cluster (NAME, NAME-worker-I). vcluster's docker driver keeps every
# node name across a restore (pkg/cli/restore_docker.go writes
# .restore-hostname so "the kubelet re-registers with the node name that
# matches etcd data", and the workers come back from the snapshot's
# vcluster.yaml under their own names), and its ensureVClusterNodes
# (pkg/cli/create_docker.go) removes "the nodes that are not in the
# config": each node found whose name no configured node has, in the
# order found. vk8s applies that to the store's Node objects after a
# restore, with the nodes it boots as the configured ones.

# Whether n is one of xs.
def Cli.name_in(xs: List<&2, String>, +n: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{x, t}:
      Bool.or(String.eq(x, n), Cli.name_in(t, n))

def Cli.nodes_live.workers(+guest: String, ws: List<&2, U32>) -> List<&2, String>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{i, t}:
      Con{Cli.worker_name(guest, i), Cli.nodes_live.workers(guest, t)}

# The nodes a cluster's VMs register: the control plane (the guest name)
# and one per worker index.
def Cli.nodes_live(+guest: String, ws: List<&2, U32>) -> List<&2, String>:
  Con{guest, Cli.nodes_live.workers(guest, ws)}

def Cli.nodes_stale.keep(live: Bool, +n: String, rest: List<&2, String>) -> List<&2, String>:
  match live:
    case True{}:
      rest
    case False{}:
      Con{n, rest}

# The store's Nodes that no live node has the name of, in the store's
# order (ensureVClusterNodes: `if !found` -> remove).
def Cli.nodes_stale(store: List<&2, String>, +live: List<&2, String>) -> List<&2, String>:
  match store:
    case Nil{}:
      Nil{}
    case Con{+n, t}:
      Cli.nodes_stale.keep(Cli.name_in(live, n), n, Cli.nodes_stale(t, live))

def Cli.digits(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{Chr{+c}, t}:
      Bool.and(U32.is_ge(c, 48) && U32.is_le(c, 57), Cli.digits(t))

# Whether n is a worker name of vk8s's making for guest: GUEST-worker-
# and a number.
def Cli.node_own.rest(pre: Bool, +rest: String) -> Bool:
  match pre:
    case False{}:
      False{}
    case True{}:
      Bool.not(String.is_empty(rest)) && Cli.digits(rest)

def Cli.node_own(+guest: String, +n: String) -> Bool:
  Cli.node_own.rest(String.starts_with(n, guest ++ "-worker-"), String.drop(n, String.length(guest ++ "-worker-")))

def Cli.nodes_own.keep(own: Bool, +n: String, rest: List<&2, String>) -> List<&2, String>:
  match own:
    case True{}:
      Con{n, rest}
    case False{}:
      rest

def Cli.nodes_own(ns: List<&2, String>, +guest: String) -> List<&2, String>:
  match ns:
    case Nil{}:
      Nil{}
    case Con{+n, t}:
      Cli.nodes_own.keep(Cli.node_own(guest, n), n, Cli.nodes_own(t, guest))

# The Node objects a restore deletes, given the store's Node names, the
# guest name and the worker indices it boots. An open-format restore
# makes a new cluster with its own CA around the store, so no node of the
# snapshotted cluster can come back: every Node that is not live goes. A
# VM-format restore boots the snapshot's disk (same CA, same guest name),
# so only vk8s's own worker Nodes that it does not boot go (the rule of
# create --upgrade); a Node joined with a token stays, as it can rejoin.
def Cli.restore_stale(open: Bool, store: List<&2, String>, +guest: String, ws: List<&2, U32>) -> List<&2, String>:
  match open:
    case True{}:
      Cli.nodes_stale(store, Cli.nodes_live(guest, ws))
    case False{}:
      Cli.nodes_own(Cli.nodes_stale(store, Cli.nodes_live(guest, ws)), guest)

# What vcluster logs for each (ensureVClusterNodes:
# log.Infof("Removing node %s from vCluster %s", node.Name, vClusterName)).
def Cli.removing_node(+node: String, +name: String) -> String:
  "Removing node " ++ node ++ " from vCluster " ++ name
