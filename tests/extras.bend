import Base
import ../src/cli/extras.bend as X
import ../src/guest/extras.bend as G
import ../src/guest/plan.bend as P

# A VM node's extras for a host-integrated workload (src/cli/extras.bend,
# src/guest/extras.bend): the flags, the cluster.env record, a VM's
# bend-vmm flags, the node's share file and the steps PID 1 adds.

def T.check(+name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name)

def T.args() -> +List<String>:
  ["vk8s", "create", "demo", "--mount", "/Users/u", "--nodes", "1", "--mount=/Users/u/work dir:rw", "--host-socket",
    "/run/user/502/x.sock=/Users/u/Library/Application Support/app/x.sock", "--node-setup", "/Users/u/setup.sh"]

def T.host() -> X.Host:
  X.Extras.merge(X.Extras.setting(T.args()), "")

def T.step_name(st: P.Step) -> String:
  match st:
    case P.Mount{fs, src, dst, o}:
      "mount " ++ dst
    case P.Daemon{name, prog, args}:
      "daemon " ++ name
    case P.Run{prog, args}:
      "run"
    case P.Write{path, text}:
      "write " ++ path
    case _:
      "other"

def T.names(ss: +List<P.Step>) -> +List<String>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{st, t}:
      Con{T.step_name(st), T.names(t)}

# The position of the first name with this prefix (the list's length
# when none has it).
def T.index(xs: +List<String>, +p: String) -> Nat:
  match xs:
    case Nil{}:
      0n
    case Con{+x, t}:
      Bool.pick(Nat, String.starts_with(x, p), 0n, 1n+T.index(t, p))

def T.config(ss: +List<P.Step>) -> String:
  match ss:
    case Nil{}:
      ""
    case Con{P.Write{+path, +text}, t}:
      Bool.pick(String, String.eq(path, "/etc/containerd/config.toml"), text, T.config(t))
    case Con{st, t}:
      T.config(t)

def T.links(ls: +List<X.Link>) -> +List<String>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{X.Link{+p, +t}, rest}:
      Con{p ++ " -> " ++ t, T.links(rest)}

def T.guest() -> G.Extras:
  G.Extras.parse(X.Extras.share_text(T.host()))

def T.node() -> +List<String>:
  T.names(G.Extras.apply(T.guest(), P.Plan.runtime.v2()))

def main() -> IO(Unit):
  do IO<Unit>:
    T.check("a create with a flag has one", X.Extras.has_flag(T.args()))
    T.check("a create without has none", Bool.not(X.Extras.has_flag(["vk8s", "create", "demo", "--nodes", "1"])))
    T.check("another command has none", Bool.not(X.Extras.has_flag(["vk8s", "delete", "demo", "--mount", "/x"])))
    T.check("after -- is not ours", Bool.not(X.Extras.has_flag(["vk8s", "create", "demo", "--", "--mount", "/x"])))
    T.check("drop leaves the rest", String.eq(String.join(X.Extras.drop(T.args()), " "), "vk8s create demo --nodes 1"))
    T.check("drop keeps what follows --", String.eq(String.join(X.Extras.drop(["vk8s", "create", "a", "--mount", "/x", "--", "--mount", "/y"]), " "), "vk8s create a -- --mount /y"))
    T.check("the flags are fine", String.is_empty(X.Extras.check(T.args())))
    T.check("the setting", String.eq(X.Extras.setting(T.args()),
      "MOUNT_0=ro:/Users/u\nMOUNT_1=rw:/Users/u/work dir\nHOST_SOCKET_0=/run/user/502/x.sock=/Users/u/Library/Application Support/app/x.sock\nNODE_SETUP=/Users/u/setup.sh\n"))
    T.check("a relative mount is refused", String.contains(X.Extras.check(["vk8s", "create", "a", "--mount", "work"]), "absolute"))
    T.check("a comma is refused", String.contains(X.Extras.check(["vk8s", "create", "a", "--mount", "/a,b"]), "comma"))
    T.check("a newline is refused", String.contains(X.Extras.check(["vk8s", "create", "a", "--mount", "/a\nb"]), "newline"))
    T.check("/ is refused", Bool.not(String.is_empty(X.Extras.check(["vk8s", "create", "a", "--mount", "/"]))))
    T.check(".. is refused", Bool.not(String.is_empty(X.Extras.check(["vk8s", "create", "a", "--mount", "/Users/../etc"]))))
    T.check("/etc is refused", String.contains(X.Extras.check(["vk8s", "create", "a", "--mount", "/etc/x"]), "own directories"))
    T.check("/var is refused (above /var/lib)", String.contains(X.Extras.check(["vk8s", "create", "a", "--mount", "/var"]), "own directories"))
    T.check("/var/folders is fine", String.is_empty(X.Extras.check(["vk8s", "create", "a", "--mount", "/var/folders/x"])))
    T.check("a trailing slash goes", String.eq(X.Extras.setting(["vk8s", "create", "a", "--mount", "/Users/u/:rw"]), "MOUNT_0=rw:/Users/u\n"))
    T.check("a flag without a value is refused", Bool.not(String.is_empty(X.Extras.check(["vk8s", "create", "a", "--mount"]))))
    T.check("seven mounts are refused", String.contains(X.Extras.check(["vk8s", "create", "a", "--mount=/a", "--mount=/b", "--mount=/c", "--mount=/d", "--mount=/e", "--mount=/f", "--mount=/g"]), "at most 6"))
    T.check("six mounts are fine", String.is_empty(X.Extras.check(["vk8s", "create", "a", "--mount=/a", "--mount=/b", "--mount=/c", "--mount=/d", "--mount=/e", "--mount=/f"])))
    T.check("a mount twice is refused", String.contains(X.Extras.check(["vk8s", "create", "a", "--mount=/a", "--mount=/a:rw"]), "twice"))
    T.check("a socket without = is refused", String.contains(X.Extras.check(["vk8s", "create", "a", "--host-socket", "/run/x.sock"]), "GUESTPATH=HOSTPATH"))
    T.check("a relative host socket is refused", String.contains(X.Extras.check(["vk8s", "create", "a", "--host-socket", "/run/x.sock=x.sock"]), "host's path"))
    T.check("a relative setup is refused", Bool.not(String.is_empty(X.Extras.check(["vk8s", "create", "a", "--node-setup", "setup.sh"]))))
    T.check("none is fine", String.is_empty(X.Extras.check(["vk8s", "create", "a", "--mount", "none", "--host-socket=none", "--node-setup", "none"])))
    T.check("none says so", String.eq(X.Extras.setting(["vk8s", "create", "a", "--mount", "none", "--node-setup", "none"]), "MOUNT_NONE=\nNODE_SETUP=\n"))
    T.check("the record keeps a kind the setting does not name", String.eq(X.Extras.env_lines(X.Extras.merge("MOUNT_0=ro:/b\n", "NAME=a\nMOUNT_0=rw:/a\nNODE_SETUP=/a/s.sh\n")), "MOUNT_0=ro:/b\nNODE_SETUP=/a/s.sh\n"))
    T.check("none empties the record's kind", String.eq(X.Extras.env_lines(X.Extras.merge("MOUNT_NONE=\nNODE_SETUP=\n", "MOUNT_0=rw:/a\nHOST_SOCKET_0=/g=/h\nNODE_SETUP=/a/s.sh\n")), "HOST_SOCKET_0=/g=/h\n"))
    T.check("no setting keeps the record", String.eq(X.Extras.env_lines(X.Extras.merge("", "MOUNT_0=rw:/a\nHOST_SOCKET_0=/g=/h =x\nNODE_SETUP=/a/s.sh\n")), "MOUNT_0=rw:/a\nHOST_SOCKET_0=/g=/h =x\nNODE_SETUP=/a/s.sh\n"))
    T.check("with_record replaces the lines", String.eq(X.Extras.with_record("NAME=a\nMOUNT_0=rw:/old\nPORT=1\nNODE_SETUP=/old.sh\n", X.Extras.of_env("MOUNT_0=ro:/new\n")), "NAME=a\nPORT=1\nMOUNT_0=ro:/new\n"))
    T.check("with_record of none leaves no line", String.eq(X.Extras.with_record("NAME=a\nMOUNT_0=rw:/old\n", X.Extras.none()), "NAME=a\n"))
    T.check("keep", String.eq(X.Extras.keep("NAME=a\nMOUNT_0=rw:/a b\nGVISOR=1\n"), "MOUNT_0=rw:/a b\n"))
    T.check("vmm flags", String.eq(String.join(X.Extras.vmm_flags(T.host(), "/h/c/demo", ["--mem", "2048"]), "|"),
      "--mem|2048|--share|/Users/u,tag=m0,ro|--share|/Users/u/work dir,tag=m1|--vsock|/h/c/demo/vsock"))
    T.check("vmm flags of none", String.eq(String.join(X.Extras.vmm_flags(X.Extras.none(), "/h/c/demo", ["--mem", "2048"]), "|"), "--mem|2048"))
    T.check("a sub-folder given first is mounted second", String.eq(X.Extras.share_text(X.Extras.of_env("MOUNT_0=rw:/Users/u/work\nMOUNT_1=ro:/Users/u\n")), "mount m0 ro /Users/u\nmount m1 rw /Users/u/work\n"))
    T.check("the share file", String.eq(X.Extras.share_text(T.host()),
      "mount m0 ro /Users/u\nmount m1 rw /Users/u/work dir\nsocket 100 /run/user/502/x.sock\nsetup /Users/u/setup.sh\n"))
    T.check("the node reads its share file", String.eq(String.join(T.names(G.Extras.steps(T.guest())), "|"),
      "mount /Users/u|mount /Users/u/work dir|run|daemon host-sockets|run|run"))
    T.check("no file, no extras", G.Extras.is_none(G.Extras.parse("")))
    T.check("a plan without extras stays", String.eq(String.join(T.names(G.Extras.apply(G.Extras.none(), P.Plan.runtime.v2())), "|"), String.join(T.names(P.Plan.runtime.v2()), "|")))
    T.check("the mounts come before containerd", Nat.is_lt(T.index(T.node(), "mount /Users/u"), T.index(T.node(), "daemon containerd")))
    T.check("the sockets come before containerd", Nat.is_lt(T.index(T.node(), "daemon host-sockets"), T.index(T.node(), "daemon containerd")))
    T.check("containerd is still there", Nat.is_lt(T.index(T.node(), "daemon containerd"), List.length(&2, String, T.node())))
    T.check("the config imports the drop-ins first", String.starts_with(T.config(G.Extras.apply(T.guest(), P.Plan.runtime.v2())),
      "version = 3\nroot = \"/var/lib/vcluster/containerd\"\nstate = \"/run/containerd\"\nimports = [\"/etc/containerd/conf.d/*.toml\"]\n[grpc]\n"))
    T.check("no setup, no imports", Bool.not(String.contains(T.config(G.Extras.apply(G.Extras.parse("mount m0 ro /a\n"), P.Plan.runtime.v2())), "imports")))
    T.check("the link of a host socket", String.eq(String.join(T.links(X.Extras.links(T.host(), "/h/c/demo")), "|"),
      "/h/c/demo/vsock_100 -> /Users/u/Library/Application Support/app/x.sock"))
