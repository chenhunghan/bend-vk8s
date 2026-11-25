import Base

# `vk8s create` options for a host-integrated workload (vk8s design;
# vcluster has no VM): a VM node gets host directories at the same
# absolute path, host Unix sockets, and a setup script.
#
#   --mount HOSTDIR[:rw]              repeatable; read-only unless :rw
#   --host-socket GUESTPATH=HOSTPATH  repeatable
#   --node-setup SCRIPT               a path in the node
#
# VM mode only. As --gvisor does, main runs the program again without
# the flags and with their record in VK8S_NODE_EXTRAS; create, create
# --upgrade and restore merge it into the cluster's cluster.env (a kind
# of flag that is given replaces that kind's record; the value none
# empties it), and every VM node of the cluster (node add and CA
# rotation too) gets what cluster.env records:
#
#   MOUNT_<i>=ro:<path> | rw:<path>
#   HOST_SOCKET_<i>=<guest path>=<host path>
#   NODE_SETUP=<path>
#
# For each VM the host then adds bend-vmm flags (Extras.vmm_flags: a
# --share per mount, --vsock when there are sockets), links
# <vm dir>/vsock_<port> to each host socket (bend-vmm sends the guest's
# connection to host port P to the Unix socket <--vsock path>_P), and
# writes the node's share file (Extras.share_text; src/guest/extras.bend
# reads it). Paths never go on the kernel command line.

type HMnt is Data:
  HMnt{rw: Bool, path: String}

type HSock is Data:
  HSock{guest: String, host: String}

type Host is Data:
  Host{mounts: +List<HMnt>, socks: +List<HSock>, setup: String}

# One flag as given: kind 0 --mount, 1 --host-socket, 2 --node-setup.
type Flag is Data:
  Flag{kind: U32, value: String}

type Link is Data:
  Link{path: String, target: String}

def HMnt.path(m: HMnt) -> String:
  match m:
    case HMnt{rw, p}:
      p

def HMnt.rw(m: HMnt) -> Bool:
  match m:
    case HMnt{rw, p}:
      rw

def HSock.guest(s: HSock) -> String:
  match s:
    case HSock{g, h}:
      g

def HSock.host(s: HSock) -> String:
  match s:
    case HSock{g, h}:
      h

def Link.path(l: Link) -> String:
  match l:
    case Link{p, t}:
      p

def Link.target(l: Link) -> String:
  match l:
    case Link{p, t}:
      t

def Extras.env_name() -> String:
  "VK8S_NODE_EXTRAS"

def Extras.none() -> Host:
  Host{[], [], ""}

def Extras.mounts(h: Host) -> +List<HMnt>:
  match h:
    case Host{m, s, u}:
      m

def Extras.socks(h: Host) -> +List<HSock>:
  match h:
    case Host{m, s, u}:
      s

def Extras.setup(h: Host) -> String:
  match h:
    case Host{m, s, u}:
      u

def Extras.is_none(h: Host) -> Bool:
  match h:
    case Host{m, s, u}:
      List.is_empty(&2, HMnt, m) && List.is_empty(&2, HSock, s) && String.is_empty(u)

# bend-vmm gives a VM 8 shares (README, --share: "repeatable (up to 8)");
# the cluster share and the layer store use two.
def Extras.max_mounts() -> Nat:
  6n

def Extras.max_socks() -> Nat:
  8n

# The host vsock port of socket i: 100 + i, so the link's name
# (vsock_10N) stays shorter than a worker's longest socket path allows
# (C.Cli.paths_fit).
def Extras.port(+i: U32) -> U32:
  U32.add(100, i)

# --- The flags on the command line

# A word's kind: 0, 1, 2 a bare flag (its value is the next word); 10,
# 11, 12 a flag with =value; 20 "--"; 99 anything else.
def Extras.kind(+x: String) -> U32:
  Bool.pick(U32, String.eq(x, "--mount"), 0,
  Bool.pick(U32, String.eq(x, "--host-socket"), 1,
  Bool.pick(U32, String.eq(x, "--node-setup"), 2,
  Bool.pick(U32, String.starts_with(x, "--mount="), 10,
  Bool.pick(U32, String.starts_with(x, "--host-socket="), 11,
  Bool.pick(U32, String.starts_with(x, "--node-setup="), 12,
  Bool.pick(U32, String.eq(x, "--"), 20, 99)))))))

# The scan's state after a word of kind k: 0, 1, 2 the next word is that
# flag's value; 3 between flags; 4 after "--" (the rest is not ours).
def Extras.next(+want: U32, +k: U32) -> U32:
  Bool.pick(U32, U32.is_lt(want, 3), 3,
  Bool.pick(U32, U32.is_eq(want, 4), 4,
  Bool.pick(U32, U32.is_lt(k, 3), k,
  Bool.pick(U32, U32.is_eq(k, 20), 4, 3))))

def Extras.eq_value(+k: U32, +x: String) -> String:
  Bool.pick(String, U32.is_eq(k, 10), String.drop(x, 8n),
  Bool.pick(String, U32.is_eq(k, 11), String.drop(x, 14n), String.drop(x, 13n)))

# The flag a word completes in state want (none: []).
def Extras.emit(+want: U32, +k: U32, +x: String) -> +List<Flag>:
  Bool.pick(+List<Flag>, U32.is_lt(want, 3), [Flag{want, x}],
  Bool.pick(+List<Flag>, U32.is_eq(want, 3) && U32.is_ge(k, 10) && U32.is_le(k, 12), [Flag{U32.sub(k, 10), Extras.eq_value(k, x)}], []))

# Whether the word is one of the flags' own (a flag or its value).
def Extras.ours(+want: U32, +k: U32) -> Bool:
  U32.is_lt(want, 3) || (U32.is_eq(want, 3) && U32.is_le(k, 12))

def Extras.scan.end(+want: U32) -> +List<Flag>:
  Bool.pick(+List<Flag>, U32.is_lt(want, 3), [Flag{want, ""}], [])

def Extras.scan(xs: +List<String>, +want: U32) -> +List<Flag>:
  match xs:
    case Nil{}:
      Extras.scan.end(want)
    case Con{+x, t}:
      List.append(&2, Flag, Extras.emit(want, Extras.kind(x), x), Extras.scan(t, Extras.next(want, Extras.kind(x))))

# The three flags of an argument list, in order (a flag at the end with
# no value has the value "", which Extras.check refuses).
def Extras.flags(xs: +List<String>) -> +List<Flag>:
  Extras.scan(xs, 3)

def Extras.is_create(xs: +List<String>) -> Bool:
  match xs:
    case Con{a, Con{+c, t}}:
      String.eq(c, "create")
    case _:
      False{}

# Whether argv (program, command, ...) is a create with one of the flags.
def Extras.has_flag(+xs: +List<String>) -> Bool:
  Extras.is_create(xs) && Bool.not(List.is_empty(&2, Flag, Extras.flags(xs)))

def Extras.drop.put(drop: Bool, +x: String, rest: +List<String>) -> +List<String>:
  match drop:
    case True{}:
      rest
    case False{}:
      Con{x, rest}

def Extras.drop.go(xs: +List<String>, +want: U32) -> +List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, t}:
      Extras.drop.put(Extras.ours(want, Extras.kind(x)), x, Extras.drop.go(t, Extras.next(want, Extras.kind(x))))

# The argument list without the flags and their values.
def Extras.drop(xs: +List<String>) -> +List<String>:
  Extras.drop.go(xs, 3)

# --- Values

def Extras.chop(+v: String, n: Nat) -> String:
  String.take(v, Nat.sub(String.length(v), n))

# One trailing "/" goes (a shell completes a directory with one).
def Extras.unslash(+p: String) -> String:
  Bool.pick(String, String.ends_with(p, "/") && Bool.not(String.eq(p, "/")), Extras.chop(p, 1n), p)

# --mount's value: HOSTDIR, HOSTDIR:ro or HOSTDIR:rw.
def Extras.mount_of(+v: String) -> HMnt:
  Bool.pick(HMnt, String.ends_with(v, ":rw"), HMnt{True{}, Extras.unslash(Extras.chop(v, 3n))},
  Bool.pick(HMnt, String.ends_with(v, ":ro"), HMnt{False{}, Extras.unslash(Extras.chop(v, 3n))}, HMnt{False{}, Extras.unslash(v)}))

def Extras.sock_of.go(ps: +List<String>) -> HSock:
  match ps:
    case Nil{}:
      HSock{"", ""}
    case Con{+g, +rest}:
      HSock{g, String.join(rest, "=")}

# --host-socket's value: GUESTPATH=HOSTPATH, cut at the first "=".
def Extras.sock_of(+v: String) -> HSock:
  Extras.sock_of.go(String.split(v, '='))

def Extras.has_char(+s: String, +c: String) -> Bool:
  String.contains(s, c)

def Extras.parts_ok(ps: +List<String>) -> Bool:
  match ps:
    case Nil{}:
      True{}
    case Con{+p, t}:
      Bool.not(String.is_empty(p)) && Bool.not(String.eq(p, ".")) && Bool.not(String.eq(p, "..")) && Extras.parts_ok(t)

# An absolute path with no empty, "." or ".." part and no newline: the
# node makes and mounts it as written.
def Extras.clean(+p: String) -> Bool:
  String.starts_with(p, "/") && Bool.not(String.eq(p, "/")) && Bool.not(Extras.has_char(p, "\n"))
    && Extras.parts_ok(String.split(String.drop(p, 1n), '/'))

# The node's own directories: a mount at one, inside one or above one
# would hide what the node runs on.
def Extras.reserved() -> +List<String>:
  ["/proc", "/sys", "/dev", "/run", "/etc", "/usr", "/bin", "/sbin", "/lib", "/assets", "/opt/cni", "/var/lib", "/var/log", "/var/run"]

def Extras.is_reserved.in(rs: +List<String>, +p: String) -> Bool:
  match rs:
    case Nil{}:
      False{}
    case Con{+r, t}:
      String.eq(p, r) || String.starts_with(p, r ++ "/") || String.starts_with(r, p ++ "/") || Extras.is_reserved.in(t, p)

def Extras.is_reserved(+p: String) -> Bool:
  Extras.is_reserved.in(Extras.reserved(), p)

def Extras.err(bad: Bool, +msg: String) -> String:
  match bad:
    case True{}:
      msg
    case False{}:
      ""

# The first message that is not "".
def Extras.first(+a: String, b: String) -> String:
  Bool.pick(String, String.is_empty(a), b, a)

def Extras.is_no(+v: String) -> Bool:
  String.eq(v, "none")

def Extras.check.mount.path(+v: String, +p: String) -> String:
  Extras.first(Extras.err(Bool.not(String.starts_with(p, "/")), "vk8s create: --mount " ++ v ++ ": the directory must be an absolute path"),
  Extras.first(Extras.err(Extras.has_char(p, ",") || Extras.has_char(p, "\n"), "vk8s create: --mount " ++ v ++ ": a path with a comma or a newline cannot be shared (bend-vmm's --share splits its value at commas)"),
  Extras.first(Extras.err(Bool.not(Extras.clean(p)), "vk8s create: --mount " ++ v ++ ": the path must not be / or hold an empty, . or .. part"),
    Extras.err(Extras.is_reserved(p), "vk8s create: --mount " ++ v ++ ": the node mounts it at the same path, which is one of its own directories (" ++ String.join(Extras.reserved(), ", ") ++ ")"))))

def Extras.check.mount(+v: String) -> String:
  Bool.pick(String, Extras.is_no(v), "", Extras.check.mount.path(v, HMnt.path(Extras.mount_of(v))))

# Linux's sun_path holds 107 bytes and a NUL (unix(7)).
def Extras.check.sock.paths(+v: String, +g: String, +h: String) -> String:
  Extras.first(Extras.err(String.is_empty(g) || String.is_empty(h), "vk8s create: --host-socket " ++ v ++ ": give it as GUESTPATH=HOSTPATH"),
  Extras.first(Extras.err(Bool.not(Extras.clean(g)), "vk8s create: --host-socket " ++ v ++ ": the node's path must be absolute, with no empty, . or .. part"),
  Extras.first(Extras.err(Nat.is_gt(String.length(g), 107n), "vk8s create: --host-socket " ++ v ++ ": the node's path is longer than a Unix socket's 107 bytes"),
    Extras.err(Bool.not(String.starts_with(h, "/")) || Extras.has_char(h, "\n"), "vk8s create: --host-socket " ++ v ++ ": the host's path must be absolute, with no newline"))))

def Extras.check.sock(+v: String) -> String:
  Bool.pick(String, Extras.is_no(v), "", Extras.check.sock.paths(v, HSock.guest(Extras.sock_of(v)), HSock.host(Extras.sock_of(v))))

def Extras.check.setup(+v: String) -> String:
  Extras.err(Bool.not(Extras.is_no(v)) && Bool.not(Extras.clean(v)), "vk8s create: --node-setup " ++ v ++ ": the script must be an absolute path in the node, with no empty, . or .. part")

def Extras.check.flag(f: Flag) -> String:
  match f:
    case Flag{+k, +v}:
      Bool.pick(String, U32.is_eq(k, 0), Extras.check.mount(v), Bool.pick(String, U32.is_eq(k, 1), Extras.check.sock(v), Extras.check.setup(v)))

def Extras.check.each(fs: +List<Flag>) -> String:
  match fs:
    case Nil{}:
      ""
    case Con{+f, t}:
      Extras.first(Extras.check.flag(f), Extras.check.each(t))

def Extras.member(xs: +List<String>, +s: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{+x, t}:
      String.eq(x, s) || Extras.member(t, s)

# The first string that comes twice ("" when none does).
def Extras.dup(xs: +List<String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+x, +t}:
      Bool.pick(String, Extras.member(t, x), x, Extras.dup(t))

def Extras.mount_paths(ms: +List<HMnt>) -> +List<String>:
  match ms:
    case Nil{}:
      Nil{}
    case Con{HMnt{rw, +p}, t}:
      Con{p, Extras.mount_paths(t)}

def Extras.guest_paths(ss: +List<HSock>) -> +List<String>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{HSock{+g, h}, t}:
      Con{g, Extras.guest_paths(t)}

# --- From the flags to the extras

def Extras.of_flags.put(f: Flag, h: Host) -> Host:
  match f h:
    case Flag{+k, +v} Host{+m, +s, +u}:
      Bool.pick(Host, Extras.is_no(v), Host{m, s, u},
      Bool.pick(Host, U32.is_eq(k, 0), Host{Con{Extras.mount_of(v), m}, s, u},
      Bool.pick(Host, U32.is_eq(k, 1), Host{m, Con{Extras.sock_of(v), s}, u},
        Host{m, s, Bool.pick(String, String.is_empty(u), v, u)})))

# The extras the flags name, in their order (the value none names
# nothing; the last --node-setup counts).
def Extras.of_flags(fs: +List<Flag>) -> Host:
  match fs:
    case Nil{}:
      Extras.none()
    case Con{+f, t}:
      Extras.of_flags.put(f, Extras.of_flags(t))

def Extras.check.all(+h: Host) -> String:
  Extras.first(Extras.err(Nat.is_gt(List.length(&2, HMnt, Extras.mounts(h)), Extras.max_mounts()),
    "vk8s create: at most 6 --mount (bend-vmm gives a VM 8 shares; the cluster's share and the layer store use two)"),
  Extras.first(Extras.err(Nat.is_gt(List.length(&2, HSock, Extras.socks(h)), Extras.max_socks()), "vk8s create: at most 8 --host-socket"),
  Extras.first(Extras.err(Bool.not(String.is_empty(Extras.dup(Extras.mount_paths(Extras.mounts(h))))),
    "vk8s create: --mount " ++ Extras.dup(Extras.mount_paths(Extras.mounts(h))) ++ " is given twice"),
    Extras.err(Bool.not(String.is_empty(Extras.dup(Extras.guest_paths(Extras.socks(h))))),
    "vk8s create: --host-socket " ++ Extras.dup(Extras.guest_paths(Extras.socks(h))) ++ " is given twice"))))

# What is wrong with the flags of an argument list ("" when nothing is).
def Extras.check(+xs: +List<String>) -> String:
  Extras.first(Extras.check.each(Extras.flags(xs)), Extras.check.all(Extras.of_flags(Extras.flags(xs))))

# --- The record (cluster.env lines, and VK8S_NODE_EXTRAS)

def Extras.mode(rw: Bool) -> String:
  match rw:
    case True{}:
      "rw"
    case False{}:
      "ro"

def Extras.mount_lines(ms: +List<HMnt>, +i: U32) -> String:
  match ms:
    case Nil{}:
      ""
    case Con{HMnt{rw, +p}, t}:
      "MOUNT_" ++ U32.show(i) ++ "=" ++ Extras.mode(rw) ++ ":" ++ p ++ "\n" ++ Extras.mount_lines(t, U32.add(i, 1))

def Extras.sock_lines(ss: +List<HSock>, +i: U32) -> String:
  match ss:
    case Nil{}:
      ""
    case Con{HSock{+g, +h}, t}:
      "HOST_SOCKET_" ++ U32.show(i) ++ "=" ++ g ++ "=" ++ h ++ "\n" ++ Extras.sock_lines(t, U32.add(i, 1))

def Extras.setup_line(+u: String) -> String:
  Bool.pick(String, String.is_empty(u), "", "NODE_SETUP=" ++ u ++ "\n")

# cluster.env's lines for the extras ("" for none).
def Extras.env_lines(h: Host) -> String:
  match h:
    case Host{m, s, +u}:
      Extras.mount_lines(m, 0) ++ Extras.sock_lines(s, 0) ++ Extras.setup_line(u)

def Extras.has_kind(fs: +List<Flag>, +k: U32) -> Bool:
  match fs:
    case Nil{}:
      False{}
    case Con{Flag{+fk, v}, t}:
      U32.is_eq(fk, k) || Extras.has_kind(t, k)

# A kind that was given with no entry left (none) still says so, and
# then empties the record's.
def Extras.none_line(given: Bool, empty: Bool, +line: String) -> String:
  Bool.pick(String, given && empty, line, "")

def Extras.setting.of(+fs: +List<Flag>, +h: Host) -> String:
  Extras.env_lines(h)
    ++ Extras.none_line(Extras.has_kind(fs, 0), List.is_empty(&2, HMnt, Extras.mounts(h)), "MOUNT_NONE=\n")
    ++ Extras.none_line(Extras.has_kind(fs, 1), List.is_empty(&2, HSock, Extras.socks(h)), "HOST_SOCKET_NONE=\n")
    ++ Extras.none_line(Extras.has_kind(fs, 2), String.is_empty(Extras.setup(h)), "NODE_SETUP=\n")

# VK8S_NODE_EXTRAS's value for an argument list: the record's lines.
def Extras.setting(+xs: +List<String>) -> String:
  Extras.setting.of(Extras.flags(xs), Extras.of_flags(Extras.flags(xs)))

def Extras.value(+l: String, n: Nat) -> String:
  String.join(List.drop(&2, String, String.split(l, '='), n), "=")

def Extras.rec_mount(+v: String) -> +List<HMnt>:
  Bool.pick(+List<HMnt>, String.starts_with(v, "rw:/"), [HMnt{True{}, String.drop(v, 3n)}],
  Bool.pick(+List<HMnt>, String.starts_with(v, "ro:/"), [HMnt{False{}, String.drop(v, 3n)}], []))

def Extras.rec_sock(s: HSock) -> +List<HSock>:
  match s:
    case HSock{+g, +h}:
      Bool.pick(+List<HSock>, String.starts_with(g, "/") && String.starts_with(h, "/"), [HSock{g, h}], [])

def Extras.of_env.line(+l: String, h: Host) -> Host:
  match h:
    case Host{+m, +s, +u}:
      Bool.pick(Host, String.starts_with(l, "MOUNT_"), Host{List.append(&2, HMnt, Extras.rec_mount(Extras.value(l, 1n)), m), s, u},
      Bool.pick(Host, String.starts_with(l, "HOST_SOCKET_"), Host{m, List.append(&2, HSock, Extras.rec_sock(Extras.sock_of(Extras.value(l, 1n))), s), u},
      Bool.pick(Host, String.starts_with(l, "NODE_SETUP=/"), Host{m, s, Bool.pick(String, String.is_empty(u), Extras.value(l, 1n), u)}, Host{m, s, u})))

def Extras.of_env.lines(ls: +List<String>) -> Host:
  match ls:
    case Nil{}:
      Extras.none()
    case Con{+l, t}:
      Extras.of_env.line(l, Extras.of_env.lines(t))

# The extras a cluster.env (or a VK8S_NODE_EXTRAS value) records.
def Extras.of_env(+env: String) -> Host:
  Extras.of_env.lines(String.split(env, '\n'))

def Extras.is_line(+l: String) -> Bool:
  String.starts_with(l, "MOUNT_") || String.starts_with(l, "HOST_SOCKET_") || String.starts_with(l, "NODE_SETUP=")

def Extras.other_lines(ls: +List<String>) -> +List<String>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{+l, t}:
      Extras.drop.put(Extras.is_line(l) || String.is_empty(l), l, Extras.other_lines(t))

# A cluster.env with these extras' lines last (any old ones, and empty
# lines, gone).
def Extras.with_record(+env: String, h: Host) -> String:
  String.join(Extras.other_lines(String.split(env, '\n')), "\n") ++ "\n" ++ Extras.env_lines(h)

# The extras lines of a cluster.env, for a command that writes the file
# anew (create --upgrade, restore).
def Extras.keep(+env: String) -> String:
  Extras.env_lines(Extras.of_env(env))

def Extras.sets(+text: String, +prefix: String) -> Bool:
  String.contains("\n" ++ text, "\n" ++ prefix)

def Extras.merge.go(+sm: Bool, +ss: Bool, +su: Bool, set: Host, rec: Host) -> Host:
  match set rec:
    case Host{m1, s1, u1} Host{m0, s0, u0}:
      Host{Bool.pick(+List<HMnt>, sm, m1, m0), Bool.pick(+List<HSock>, ss, s1, s0), Bool.pick(String, su, u1, u0)}

# The cluster's extras: of each kind, the setting's (VK8S_NODE_EXTRAS,
# from the flags) when the setting names that kind, else the record's.
def Extras.merge(+setting: String, +rec: String) -> Host:
  Extras.merge.go(Extras.sets(setting, "MOUNT_"), Extras.sets(setting, "HOST_SOCKET_"), Extras.sets(setting, "NODE_SETUP="),
    Extras.of_env(setting), Extras.of_env(rec))

# --- A VM's flags, links and share file

def Extras.len(m: HMnt) -> Nat:
  match m:
    case HMnt{rw, p}:
      String.length(p)

def Extras.sort.ins(+m: HMnt, ms: +List<HMnt>) -> +List<HMnt>:
  match ms:
    case Nil{}:
      [m]
    case Con{+h, +t}:
      Bool.pick(+List<HMnt>, Nat.is_le(Extras.len(m), Extras.len(h)), Con{m, Con{h, t}}, Con{h, Extras.sort.ins(m, t)})

# The mounts by path length, shortest first (equal lengths keep their
# order): a directory is mounted before any directory inside it, so a
# writable sub-folder of a read-only mount lands on top of it.
def Extras.sorted(ms: +List<HMnt>) -> +List<HMnt>:
  match ms:
    case Nil{}:
      Nil{}
    case Con{+m, t}:
      Extras.sort.ins(m, Extras.sorted(t))

def Extras.tag(+i: U32) -> String:
  "m" ++ U32.show(i)

def Extras.ro_opt(rw: Bool) -> String:
  match rw:
    case True{}:
      ""
    case False{}:
      ",ro"

# bend-vmm's --share values (README: --share DIR[,tag=NAME][,ro]).
def Extras.shares(ms: +List<HMnt>, +i: U32) -> +List<String>:
  match ms:
    case Nil{}:
      Nil{}
    case Con{HMnt{rw, +p}, t}:
      Con{"--share", Con{p ++ ",tag=" ++ Extras.tag(i) ++ Extras.ro_opt(rw), Extras.shares(t, U32.add(i, 1))}}

def Extras.vsock(+vmdir: String) -> String:
  vmdir ++ "/vsock"

def Extras.vsock_flags(none: Bool, +vmdir: String) -> +List<String>:
  match none:
    case True{}:
      Nil{}
    case False{}:
      ["--vsock", Extras.vsock(vmdir)]

# A VM's bend-vmm flags (flag, value pairs) with its extras: a --share
# per mount, tagged m0, m1, ... in mount order, and --vsock when the
# cluster has host sockets.
def Extras.vmm_flags.go(none: Bool, h: Host, +vmdir: String, flags: +List<String>) -> +List<String>:
  match none:
    case True{}:
      flags
    case False{}:
      match h:
        case Host{m, s, u}:
          List.append(&2, String, flags, List.append(&2, String, Extras.shares(Extras.sorted(m), 0), Extras.vsock_flags(List.is_empty(&2, HSock, s), vmdir)))

def Extras.vmm_flags(+h: Host, +vmdir: String, flags: +List<String>) -> +List<String>:
  Extras.vmm_flags.go(Extras.is_none(h), h, vmdir, flags)

# bend-vmm sends a guest's connection to host port P to the Unix socket
# <--vsock path>_P (README, "virtio-vsock ... Firecracker's convention");
# that path is a link to the host socket.
def Extras.links.go(ss: +List<HSock>, +vmdir: String, +i: U32) -> +List<Link>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{HSock{g, +h}, t}:
      Con{Link{Extras.vsock(vmdir) ++ "_" ++ U32.show(Extras.port(i)), h}, Extras.links.go(t, vmdir, U32.add(i, 1))}

def Extras.links(h: Host, +vmdir: String) -> +List<Link>:
  Extras.links.go(Extras.socks(h), vmdir, 0)

def Extras.share_mounts(ms: +List<HMnt>, +i: U32) -> String:
  match ms:
    case Nil{}:
      ""
    case Con{HMnt{rw, +p}, t}:
      "mount " ++ Extras.tag(i) ++ " " ++ Extras.mode(rw) ++ " " ++ p ++ "\n" ++ Extras.share_mounts(t, U32.add(i, 1))

def Extras.share_socks(ss: +List<HSock>, +i: U32) -> String:
  match ss:
    case Nil{}:
      ""
    case Con{HSock{+g, h}, t}:
      "socket " ++ U32.show(Extras.port(i)) ++ " " ++ g ++ "\n" ++ Extras.share_socks(t, U32.add(i, 1))

def Extras.share_setup(+u: String) -> String:
  Bool.pick(String, String.is_empty(u), "", "setup " ++ u ++ "\n")

# The node's share file (src/guest/extras.bend Extras.parse reads it).
def Extras.share_text(h: Host) -> String:
  match h:
    case Host{m, s, +u}:
      Extras.share_mounts(Extras.sorted(m), 0) ++ Extras.share_socks(s, 0) ++ Extras.share_setup(u)

# The names of the node's share file and of the setup script's exit code
# in the share (src/guest/extras.bend Extras.file, Extras.exit_file).
def Extras.share_file() -> String:
  "node-extras"

def Extras.exit_file() -> String:
  "node-setup.exit"

# What another backend says to the flags.
def Extras.vm_only() -> String:
  "vk8s create: --mount, --host-socket and --node-setup need a VM node (--backend vm, not classic mode)"
