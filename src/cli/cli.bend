import Base

# The vk8s command line, as data (vcluster's `vcluster ... --driver docker`
# verbs, pkg/cli/*_docker.go), and the bend-vmm command line of a cluster's
# control-plane VM. Pure: host/vk8s.bend performs it.

type Cmd is Data:
  Create{name: String, port: U32, cpus: U32, mem: U32, etcd: Bool}
  Delete{name: String}
  List{}
  Connect{name: String}
  Pause{name: String}
  Resume{name: String}
  Vmm{flags: +List<String>}
  Version{}
  Help{msg: String}

def Cli.usage() -> String:
  "usage: vk8s <command>\n\n"
  ++ "  create NAME [--port P] [--cpus N] [--memory MiB] [--backing-store sqlite|etcd]\n"
  ++ "                                                     start a virtual cluster in a bend-vmm VM\n"
  ++ "  connect NAME                                       print the kubeconfig path and context\n"
  ++ "  list                                               list virtual clusters\n"
  ++ "  pause NAME | resume NAME                           pause or resume a cluster's VM\n"
  ++ "  delete NAME                                        stop a cluster and delete its state\n"
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

def Cli.create_opt.set(is_port: Bool, is_cpus: Bool, is_mem: Bool, +k: String, m: Maybe<&2, U32>,
  +n: String, +p: U32, +cpu: U32, +mem: U32, +etcd: Bool) -> Cmd:
  match is_port is_cpus is_mem:
    case True{} _ _:
      Create{n, Cli.num(m, p), cpu, mem, etcd}
    case False{} True{} _:
      Create{n, p, Cli.num(m, cpu), mem, etcd}
    case False{} False{} True{}:
      Create{n, p, cpu, Cli.num(m, mem), etcd}
    case False{} False{} False{}:
      Help{"vk8s create: unknown option " ++ k ++ "\n"}

def Cli.create_opt.store.pick(is_etcd: Bool, is_sqlite: Bool, +v: String, +n: String, +p: U32, +cpu: U32, +mem: U32) -> Cmd:
  match is_etcd is_sqlite:
    case True{} _:
      Create{n, p, cpu, mem, True{}}
    case False{} True{}:
      Create{n, p, cpu, mem, False{}}
    case False{} False{}:
      Help{"vk8s create: --backing-store is sqlite or etcd, not " ++ String.quote(v) ++ "\n"}

# --backing-store sqlite|etcd (vcluster: controlPlane.backingStore) or a
# numeric option.
def Cli.create_opt.which(is_store: Bool, +k: String, +v: String, +n: String, +p: U32, +cpu: U32, +mem: U32,
  +etcd: Bool) -> Cmd:
  match is_store:
    case True{}:
      Cli.create_opt.store.pick(String.eq(v, "etcd"), String.eq(v, "sqlite"), v, n, p, cpu, mem)
    case False{}:
      Cli.create_opt.set(String.eq(k, "--port"), String.eq(k, "--cpus"), String.eq(k, "--memory"),
        k, U32.read(v), n, p, cpu, mem, etcd)

def Cli.create_opt(+k: String, +v: String, +c: Cmd) -> Cmd:
  match c:
    case Create{+n, +p, +cpu, +mem, +etcd}:
      Cli.create_opt.which(String.eq(k, "--backing-store"), k, v, n, p, cpu, mem, etcd)
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
      Cli.create_opts(rest, Create{name, 0, 2, 2048, False{}})
    case False{} True{} _ _ _:
      Delete{name}
    case False{} False{} True{} _ _:
      Connect{name}
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

def Cli.vmm_flags(+dir: String, +assets: String, +name: String, +port: U32, +cpus: U32, +mem: U32, +etcd: Bool) -> +List<String>:
  [ "--kernel", assets ++ "/Image",
    "--initrd", assets ++ "/vk8s.cpio",
    "--disk", assets ++ "/assets.img:ro," ++ dir ++ "/data.img",
    "--share", dir ++ "/share",
    "--mem", U32.show(mem),
    "--cpus", U32.show(cpus),
    "--forward", "127.0.0.1:" ++ U32.show(port) ++ ":6443",
    "--control", dir ++ "/ctl.sock",
    "--cmdline", "console=ttyAMA0 quiet panic=5 VK8S_NAME=" ++ name ++ " VK8S_PORT=" ++ U32.show(port) ++ " VK8S_STORE=" ++ Cli.store_name(etcd) ]

# vcluster picks the docker driver's host port in 10000..12999.
def Cli.port_from(+seed: U32) -> U32:
  (10000 + (seed % 3000 : U32) : U32)
