import Base
import ./plan.bend as P

# A VM node's extras for a host-integrated workload (vk8s design; vcluster
# has no VM): host directories mounted at the same absolute path, host
# Unix sockets reached through Unix sockets of the node, and a setup
# script that PID 1 runs at every boot before containerd starts.
#
# The host (src/cli/extras.bend) writes them to the file node-extras in
# the node's share, one per line, a path last so it may hold spaces:
#   mount TAG ro|rw PATH     a bend-vmm share tagged TAG, mounted at PATH
#   socket PORT PATH         the Unix socket PATH; each connection goes
#                            to the host's vsock port PORT
#   setup PATH               the script
# PID 1 reads the file once the share is mounted and puts the steps
# before the plan's containerd daemon (Extras.apply); the kubelet starts
# after containerd in every node plan.

type Mnt is Data:
  Mnt{tag: String, rw: Bool, path: String}

type Sock is Data:
  Sock{port: U32, path: String}

type Extras is Data:
  Extras{mounts: +List<Mnt>, socks: +List<Sock>, setup: String}

def Extras.none() -> Extras:
  Extras{[], [], ""}

# The file's name in the node's share.
def Extras.file() -> String:
  "node-extras"

def Extras.path() -> String:
  P.Plan.host_dir() ++ "/node-extras"

def Extras.mounts(e: Extras) -> +List<Mnt>:
  match e:
    case Extras{m, s, u}:
      m

def Extras.socks(e: Extras) -> +List<Sock>:
  match e:
    case Extras{m, s, u}:
      s

def Extras.setup(e: Extras) -> String:
  match e:
    case Extras{m, s, u}:
      u

def Extras.is_none(e: Extras) -> Bool:
  match e:
    case Extras{m, s, u}:
      List.is_empty(&2, Mnt, m) && List.is_empty(&2, Sock, s) && String.is_empty(u)

# --- The file

def Extras.with_mount(e: Extras, +m: Mnt) -> Extras:
  match e:
    case Extras{ms, s, u}:
      Extras{Con{m, ms}, s, u}

def Extras.with_sock(e: Extras, +k: Sock) -> Extras:
  match e:
    case Extras{m, ss, u}:
      Extras{m, Con{k, ss}, u}

def Extras.with_setup(e: Extras, +p: String) -> Extras:
  match e:
    case Extras{m, s, u}:
      Extras{m, s, p}

def Extras.keep(ok: Bool, +next: Extras, +e: Extras) -> Extras:
  match ok:
    case True{}:
      next
    case False{}:
      e

# "mount TAG ro|rw PATH": the words after "mount".
def Extras.line.mount(ws: +List<String>, +e: Extras) -> Extras:
  match ws:
    case Con{+tag, Con{+mode, +rest}}:
      +path = String.join(rest, " ")
      Extras.keep((String.eq(mode, "ro") || String.eq(mode, "rw")) && String.starts_with(path, "/") && Bool.not(String.is_empty(tag)),
        Extras.with_mount(e, Mnt{tag, String.eq(mode, "rw"), path}), e)
    case _:
      e

def Extras.line.sock.go(m: Maybe<&2, U32>, +path: String, +e: Extras) -> Extras:
  match m:
    case Some{+port}:
      Extras.keep(String.starts_with(path, "/") && U32.is_ne(port, 0), Extras.with_sock(e, Sock{port, path}), e)
    case None{}:
      e

# "socket PORT PATH": the words after "socket".
def Extras.line.sock(ws: +List<String>, +e: Extras) -> Extras:
  match ws:
    case Con{+port, +rest}:
      Extras.line.sock.go(U32.read(port), String.join(rest, " "), e)
    case _:
      e

# One line onto the extras read from the lines after it; a line that is
# none of the three, or malformed, changes nothing.
def Extras.line(ws: +List<String>, +e: Extras) -> Extras:
  match ws:
    case Con{+w, +rest}:
      Bool.pick(Extras, String.eq(w, "mount"), Extras.line.mount(rest, e),
      Bool.pick(Extras, String.eq(w, "socket"), Extras.line.sock(rest, e),
      Bool.pick(Extras, String.eq(w, "setup") && String.starts_with(String.join(rest, " "), "/"), Extras.with_setup(e, String.join(rest, " ")), e)))
    case _:
      e

def Extras.parse.lines(ls: +List<String>) -> Extras:
  match ls:
    case Nil{}:
      Extras.none()
    case Con{+l, t}:
      Extras.line(String.split(l, ' '), Extras.parse.lines(t))

# The extras a node-extras text names, in the file's order ("" and a
# missing file: none).
def Extras.parse(+text: String) -> Extras:
  Extras.parse.lines(String.split(text, '\n'))

# --- The steps

# A share's mount: 9P2000.L over virtio, as the cluster share
# (Plan.host_dir) and with the layer store's msize; ro where the host
# share is read-only too (bend-vmm --share DIR,ro answers EROFS anyway).
def Extras.mount_opts(rw: Bool) -> String:
  match rw:
    case True{}:
      "trans=virtio,version=9p2000.L,msize=524288"
    case False{}:
      "trans=virtio,version=9p2000.L,msize=524288,ro"

def Extras.mount_steps(ms: +List<Mnt>) -> +List<P.Step>:
  match ms:
    case Nil{}:
      Nil{}
    case Con{Mnt{+tag, rw, +path}, t}:
      Con{P.Mount{"9p", tag, path, Extras.mount_opts(rw)}, Extras.mount_steps(t)}

# The proxy's arguments: PATH PORT for each socket.
def Extras.sock_args(ss: +List<Sock>) -> +List<String>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{Sock{+port, +path}, t}:
      Con{path, Con{U32.show(port), Extras.sock_args(t)}}

def Extras.sock_paths(ss: +List<Sock>) -> +List<String>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{Sock{port, +path}, t}:
      Con{path, Extras.sock_paths(t)}

# The guest binary's mode that serves the sockets (host/host_socket.bend).
def Extras.proxy_mode() -> String:
  "host-sockets"

def Extras.proxy_prog() -> String:
  "/sbin/vk8s-init"

# The sockets' parent directories, the proxy as a supervised daemon, then
# a wait of up to 5 s for each socket (a node whose proxy does not listen
# still boots: pods that mount the socket then fail, and say so).
def Extras.sock_steps.go(none: Bool, +ss: +List<Sock>) -> +List<P.Step>:
  match none:
    case True{}:
      Nil{}
    case False{}:
      [ P.Plan.bb(List.append(&2, String, ["sh", "-c", "for p; do mkdir -p \"${p%/*}\"; done", "sh"], Extras.sock_paths(ss))),
        P.Daemon{"host-sockets", Extras.proxy_prog(), Con{Extras.proxy_mode(), Extras.sock_args(ss)}},
        P.Plan.bb(List.append(&2, String, ["sh", "-c",
          "for p; do i=0; while [ $i -lt 50 ] && [ ! -S \"$p\" ]; do i=$((i+1)); sleep 0.1; done; [ -S \"$p\" ] || echo \"vk8s: no host socket at $p\"; done; exit 0", "sh"],
          Extras.sock_paths(ss))) ]

def Extras.sock_steps(+ss: +List<Sock>) -> +List<P.Step>:
  Extras.sock_steps.go(List.is_empty(&2, Sock, ss), ss)

# containerd's drop-in directory, which the config imports once a node
# has a setup script (Extras.with_imports).
def Extras.conf_dir() -> String:
  "/etc/containerd/conf.d"

# The PATH of PID 1's children once a node has a setup script:
# /usr/local/bin first, so containerd finds a shim the script put there
# (containerd looks a runtime_type io.containerd.NAME.v2 up as
# containerd-shim-NAME-v2 on its PATH, containerd docs/cri/config.md).
def Extras.env_path() -> String:
  "/usr/local/bin:" ++ P.Plan.path()

def Extras.exit_file() -> String:
  P.Plan.host_dir() ++ "/node-setup.exit"

def Extras.setup_log() -> String:
  P.Plan.host_dir() ++ "/logs/node-setup.log"

# The script under /bin/sh as root, its output in the node's logs and its
# exit code in the share for the host (vk8s create warns when it is not
# 0). The step itself always succeeds: the node starts whatever the
# script did.
def Extras.setup_cmd() -> String:
  "mkdir -p " ++ Extras.conf_dir() ++ " /usr/local/bin " ++ P.Plan.host_dir() ++ "/logs; rm -f " ++ Extras.exit_file()
  ++ "; echo \"== node setup $1\" >>" ++ Extras.setup_log() ++ "; PATH=" ++ Extras.env_path() ++ " /bin/sh \"$1\" >>" ++ Extras.setup_log()
  ++ " 2>&1 </dev/null; rc=$?; echo \"$rc\" >" ++ Extras.exit_file()
  ++ "; [ \"$rc\" = 0 ] || echo \"vk8s: node setup $1 exited $rc (logs/node-setup.log)\"; exit 0"

def Extras.setup_steps.go(none: Bool, +script: String) -> +List<P.Step>:
  match none:
    case True{}:
      Nil{}
    case False{}:
      [P.Plan.bb(["sh", "-c", Extras.setup_cmd(), "sh", script])]

def Extras.setup_steps(+script: String) -> +List<P.Step>:
  Extras.setup_steps.go(String.is_empty(script), script)

# Every extra step, in the order the node needs them: the mounts (the
# script and the sockets may live under one), the sockets (the script
# may use one), the script.
def Extras.steps(e: Extras) -> +List<P.Step>:
  match e:
    case Extras{m, s, u}:
      List.append(&2, P.Step, Extras.mount_steps(m), List.append(&2, P.Step, Extras.sock_steps(s), Extras.setup_steps(u)))

# --- containerd's config

def Extras.imports_line() -> String:
  "imports = [\"" ++ Extras.conf_dir() ++ "/*.toml\"]"

# The lines with the imports key before the first table header: a
# top-level key after a header would belong to that table (TOML v1.0.0,
# "Table"), and containerd reads imports at the top level only
# (containerd docs/man/containerd-config.toml.5.md, "imports").
def Extras.imports_lines(ls: +List<String>) -> +List<String>:
  match ls:
    case Nil{}:
      [Extras.imports_line()]
    case Con{+l, +t}:
      Bool.pick(+List<String>, String.starts_with(l, "["), Con{Extras.imports_line(), Con{l, t}}, Con{l, Extras.imports_lines(t)})

def Extras.with_imports.go(has: Bool, +text: String) -> String:
  match has:
    case True{}:
      text
    case False{}:
      String.join(Extras.imports_lines(String.split(text, '\n')), "\n")

# A containerd config that imports the drop-in directory (one that has
# an imports key already stays as it is).
def Extras.with_imports(+text: String) -> String:
  Extras.with_imports.go(String.contains("\n" ++ text, "\nimports = "), text)

def Extras.config_step(on: Bool, st: P.Step) -> P.Step:
  match on:
    case False{}:
      st
    case True{}:
      match st:
        case P.Write{+path, +text}:
          Bool.pick(P.Step, String.eq(path, P.Plan.containerd_config_path()), P.Write{path, Extras.with_imports(text)}, P.Write{path, text})
        case other:
          other

def Extras.is_containerd(st: P.Step) -> Bool:
  match st:
    case P.Daemon{+name, prog, args}:
      String.eq(name, "containerd")
    case _:
      False{}

def Extras.insert.put(hit: Bool, +extra: +List<P.Step>, +st: P.Step, rest: +List<P.Step>) -> +List<P.Step>:
  match hit:
    case True{}:
      List.append(&2, P.Step, extra, Con{st, rest})
    case False{}:
      Con{st, rest}

# The plan with the extra steps before each containerd daemon step (a
# plan has one; a plan without containerd, a control plane with no node,
# gets none), and with containerd's config importing the drop-in
# directory when imports is on.
def Extras.insert(steps: +List<P.Step>, +extra: +List<P.Step>, +imports: Bool) -> +List<P.Step>:
  match steps:
    case Nil{}:
      Nil{}
    case Con{+st, t}:
      Extras.insert.put(Extras.is_containerd(st), extra, Extras.config_step(imports, st), Extras.insert(t, extra, imports))

def Extras.apply.go(none: Bool, +e: Extras, steps: +List<P.Step>) -> +List<P.Step>:
  match none:
    case True{}:
      steps
    case False{}:
      Extras.insert(steps, Extras.steps(e), Bool.not(String.is_empty(Extras.setup(e))))

# A node's plan (the steps after the share's mount) with its extras; a
# node without any keeps its plan as it is.
def Extras.apply(+e: Extras, steps: +List<P.Step>) -> +List<P.Step>:
  Extras.apply.go(Extras.is_none(e), e, steps)
