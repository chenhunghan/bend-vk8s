import Base

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

def Cli.usage() -> String:
  "usage: vk8s <command>\n\n"
  ++ "  create NAME [--port P] [--cpus N] [--memory MiB] [--backing-store sqlite|etcd] [--nodes N]\n"
  ++ "                                                     start a virtual cluster in a bend-vmm VM\n"
  ++ "  connect NAME [--print] [--update-current=false]    add context vk8s_NAME to $KUBECONFIG or ~/.kube/config\n"
  ++ "  list                                               list virtual clusters\n"
  ++ "  pause NAME | resume NAME                           pause or resume a cluster's VM\n"
  ++ "  delete NAME [--delete-context=false]               stop a cluster, delete its state and its kube context\n"
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

def Cli.connect_opts(xs: +List<String>, +c: Cmd) -> Cmd:
  match xs:
    case Nil{}:
      c
    case Con{+k, rest}:
      Cli.connect_opts(rest, Cli.connect_opt(k, c))

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
      Help{"unknown command " ++ String.quote(v) ++ "\n" ++ Cli.usage()}

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

def Cli.parse.verb(vmm: Bool, ls: Bool, ver: Bool, +v: String, rest: +List<String>) -> Cmd:
  match vmm ls ver:
    case True{} _ _:
      Vmm{rest}
    case False{} True{} _:
      List{}
    case False{} False{} True{}:
      Version{}
    case False{} False{} False{}:
      Cli.parse.named(v, rest)

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
