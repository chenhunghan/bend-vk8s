import Base
import ../guest/plan.bend as P
import ../guest/supervise.bend as S

# Native mode on a Linux host (docs/GOAL.md section 8,
# docs/ref/explore-linux-hosts.md Phase 5, N1 and N2): the control plane
# runs on the host as one process that supervises its children, as
# vcluster standalone's vcluster.service does, with no VM. The plan is the
# VM's cluster layer (src/guest/plan.bend: PKI, kubeadm config, the store,
# the control plane, the join server, the cluster add-ons, the join
# material and the kubeconfig), relocated under a per-cluster data dir.
# The machine layer (base system mounts, modules, sysctls, network, disks
# and the 9p share) belongs to the VM and never runs on a host. vcluster's
# standalone runtime is closed source (pkg/pro/standalone.go); this is
# vk8s design.
#
# A control plane only (D8 a): no containerd, kubelet or CNI on the host,
# so no host iptables either; nodes join it with bootstrap tokens.

# Where a native cluster lives. data: its data dir (the VM's
# /var/lib/vcluster); bin: the Kubernetes binaries (the VM's assets disk
# at /var/lib/vcluster/bin); share: what the host reads (the VM's 9p
# share: logs, kubeconfig, join material); etc: the files the guest image
# has in /etc/vk8s (flannel.yaml) and the plan writes there; self: the
# vk8s binary (the guest's /usr/bin/vk8s-guest); busybox: the shell
# helpers' busybox (the guest's /bin/busybox).
type Env is Data:
  Env{data: String, bin: String, share: String, etc: String, self: String, busybox: String}

# A VM path and what it becomes on the host.
type Rule is Data:
  Rule{from: String, to: String}

def Native.or.go(empty: Bool, +v: String, +d: String) -> String:
  match empty:
    case True{}:
      d
    case False{}:
      v

def Native.or(+v: String, +d: String) -> String:
  Native.or.go(String.is_empty(v), v, d)

# An Env from the data dir; an empty path takes its default: bin, share,
# etc and busybox in the data dir, and the running program as self.
def Native.env_of(+data: String, +bin: String, +share: String, +etc: String, +self: String, +busybox: String) -> Env:
  Env{data, Native.or(bin, data ++ "/bin"), Native.or(share, data ++ "/share"), Native.or(etc, data ++ "/etc"),
    Native.or(self, "/proc/self/exe"), Native.or(busybox, data ++ "/busybox")}

def Native.data(e: Env) -> String:
  match e:
    case Env{d, b, s, t, x, y}:
      d

def Native.share(e: Env) -> String:
  match e:
    case Env{d, b, s, t, x, y}:
      s

def Native.busybox(e: Env) -> String:
  match e:
    case Env{d, b, s, t, x, y}:
      y

# The daemons' logs, as the VM writes them to the share.
def Native.logs(+e: Env) -> String:
  Native.share(e) ++ "/logs"

def Native.log(+e: Env, +name: String) -> String:
  Native.logs(e) ++ "/" ++ name ++ ".log"

# An absolute path, not /, that is safe in a shell word.
def Native.abs_ok(+p: String) -> Bool:
  Bool.and(Bool.and(String.starts_with(p, "/"), Bool.not(String.eq(p, "/"))),
    Bool.not(Bool.or(Bool.or(String.contains(p, " "), String.contains(p, "'")), String.contains(p, "\""))))

def Native.env_ok(e: Env) -> Bool:
  match e:
    case Env{+d, +b, +s, +t, +x, +y}:
      Bool.and(Bool.and(Bool.and(Native.abs_ok(d), Native.abs_ok(b)), Bool.and(Native.abs_ok(s), Native.abs_ok(t))),
        Bool.and(Native.abs_ok(x), Native.abs_ok(y)))

# The native cluster's settings: vk8s's defaults, the API on the host's
# own 6443 (no port forward), and the host's address as the node IP.
def Native.cfg.ip(c: P.Cfg, +ip: String) -> P.Cfg:
  match c:
    case P.Cfg{name, old, svc, pod, dom, port, etcd}:
      P.Cfg{name, ip, svc, pod, dom, port, etcd}

def Native.cfg(+name: String, +ip: String, etcd: Bool) -> P.Cfg:
  Native.cfg.ip(P.Plan.default_cfg(name, 6443, etcd), ip)

# --- Relocation

# The VM paths, longest first where one holds another (the assets dir is
# in the data dir).
def Native.rules(e: Env) -> +List<Rule>:
  match e:
    case Env{+d, +b, +s, +t, +x, +y}:
      [ Rule{P.Plan.bin(), b},
        Rule{P.Plan.data(), d},
        Rule{P.Plan.host_dir(), s},
        Rule{"/etc/vk8s", t},
        Rule{P.Plan.guest_bin(), x},
        Rule{P.Plan.busybox(), y} ]

def Native.rule_from(r: Rule) -> String:
  match r:
    case Rule{f, t}:
      f

def Native.rule_to(r: Rule) -> String:
  match r:
    case Rule{f, t}:
      t

def Native.hit.pick(m: Bool, +r: Rule, later: Maybe<&2, Rule>) -> Maybe<&2, Rule>:
  match m:
    case True{}:
      Some{r}
    case False{}:
      later

# The first rule whose VM path starts s, if any.
def Native.hit(rs: +List<Rule>, +s: String) -> Maybe<&2, Rule>:
  match rs:
    case Nil{}:
      None{}
    case Con{+r, t}:
      Native.hit.pick(String.starts_with(s, Native.rule_from(r)), r, Native.hit(t, s))

# What a step of the rewrite writes: the rule's host path, or the
# character itself.
def Native.emit(m: Maybe<&2, Rule>, +s: String) -> String:
  match m:
    case Some{r}:
      Native.rule_to(r)
    case None{}:
      String.take(s, 1n)

# How much of s that step consumes.
def Native.skip(m: Maybe<&2, Rule>) -> Nat:
  match m:
    case Some{r}:
      String.length(Native.rule_from(r))
    case None{}:
      1n

# Rewrite every VM path in s, left to right (n: fuel, the length of s:
# each step consumes at least one character).
def Native.sub(n: Nat, +rs: +List<Rule>, +s: String) -> String:
  match n:
    case 0n:
      s
    case 1n+p:
      Native.emit(Native.hit(rs, s), s) ++ Native.sub(p, rs, String.drop(s, Native.skip(Native.hit(rs, s))))

def Native.str(+e: Env, +s: String) -> String:
  Native.sub(String.length(s), Native.rules(e), s)

def Native.strs(+e: Env, xs: +List<String>) -> +List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      Con{Native.str(e, x), Native.strs(e, t)}

# One step on the host: every path in it relocated. Daemon names, hosts
# and log lines stay.
def Native.relocate.step(+e: Env, s: P.Step) -> P.Step:
  match s:
    case P.Mount{fs, src, dst, opts}:
      P.Mount{fs, Native.str(e, src), Native.str(e, dst), opts}
    case P.Write{path, text}:
      P.Write{Native.str(e, path), Native.str(e, text)}
    case P.Run{prog, args}:
      P.Run{Native.str(e, prog), Native.strs(e, args)}
    case P.Daemon{name, prog, args}:
      P.Daemon{name, Native.str(e, prog), Native.strs(e, args)}
    case P.Spawn{name, prog, args}:
      P.Spawn{name, Native.str(e, prog), Native.strs(e, args)}
    case P.WaitTcp{host, port, ms}:
      P.WaitTcp{host, port, ms}
    case P.Stop{names}:
      P.Stop{names}
    case P.WaitFile{path, ms}:
      P.WaitFile{Native.str(e, path), ms}
    case P.Modules{path}:
      P.Modules{Native.str(e, path)}
    case P.Log{text}:
      P.Log{text}

def Native.relocate(+e: Env, ss: +List<P.Step>) -> +List<P.Step>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      Con{Native.relocate.step(e, s), Native.relocate(e, t)}

# --- The machine layer

# Helpers that change the machine, not the cluster.
def Native.machine_cmds() -> +List<String>:
  ["--install", "hostname", "ip", "mount", "umount", "insmod", "modprobe", "rmmod", "sysctl", "swapon", "swapoff", "fstrim",
   "poweroff", "reboot", "halt"]

# System directories a helper may not touch.
def Native.machine_dirs() -> +List<String>:
  ["/", "/sbin", "/bin", "/usr", "/usr/bin", "/usr/sbin", "/lib", "/etc", "/proc", "/sys", "/dev", "/run", "/tmp"]

def Native.first_in(xs: +List<String>, +set: +List<String>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{x, t}:
      S.Sup.member(set, x)

def Native.any_in(xs: +List<String>, +set: +List<String>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{x, t}:
      Bool.or(S.Sup.member(set, x), Native.any_in(t, set))

def Native.machine_path(+p: String) -> Bool:
  Bool.or(Bool.or(String.starts_with(p, "/proc/"), String.starts_with(p, "/sys/")),
    Bool.or(String.starts_with(p, "/dev/"), S.Sup.member(["/etc/hosts", "/etc/resolv.conf", "/etc/hostname"], p)))

def Native.machine_run(+args: +List<String>) -> Bool:
  Bool.or(Native.first_in(args, Native.machine_cmds()), Native.any_in(args, Native.machine_dirs()))

# Is this step part of the VM's machine layer? Mounts, modules, writes to
# the kernel's files or the system's name and resolver, and helpers that
# change the machine.
def Native.machine(s: P.Step) -> Bool:
  match s:
    case P.Mount{fs, src, dst, opts}:
      True{}
    case P.Modules{path}:
      True{}
    case P.Write{path, text}:
      Native.machine_path(path)
    case P.Run{prog, args}:
      Native.machine_run(args)
    case _:
      False{}

def Native.count.go(m: Bool, n: Nat) -> Nat:
  match m:
    case True{}:
      1n+n
    case False{}:
      n

def Native.machine_count(ss: +List<P.Step>) -> Nat:
  match ss:
    case Nil{}:
      0n
    case Con{s, t}:
      Native.count.go(Native.machine(s), Native.machine_count(t))

def Native.strip.go(m: Bool, s: P.Step, rest: +List<P.Step>) -> +List<P.Step>:
  match m:
    case True{}:
      rest
    case False{}:
      Con{s, rest}

# Drop every machine step.
def Native.strip(ss: +List<P.Step>) -> +List<P.Step>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{+s, t}:
      Native.strip.go(Native.machine(s), s, Native.strip(t))

# --- The native plans

# The join server (host/join_server.bend) with its paths and endpoint as
# flags: in the VM it takes the guest's defaults (the PKI in
# /var/lib/vcluster/pki, the endpoint 10.10.0.2:6443); here relocation
# moves the PKI and joining nodes reach the host's address.
def Native.join_server(+c: P.Cfg) -> P.Step:
  match c:
    case P.Cfg{name, ip, svc, pod, dom, port, etcd}:
      P.Daemon{"join-server", P.Plan.guest_bin(),
        [ "join-server",
          "--cert=" ++ P.Plan.p("apiserver.crt"),
          "--key=" ++ P.Plan.p("apiserver.key"),
          "--ca=" ++ P.Plan.p("ca.crt"),
          "--endpoint=" ++ ip ++ ":6443",
          "--api-ca=" ++ P.Plan.p("ca.crt"),
          "--api-cert=" ++ P.Plan.p("front-proxy-client.crt"),
          "--api-key=" ++ P.Plan.p("front-proxy-client.key") ]}

def Native.join.daemon(hit: Bool, +c: P.Cfg, +name: String, +prog: String, +args: +List<String>) -> P.Step:
  match hit:
    case True{}:
      Native.join_server(c)
    case False{}:
      P.Daemon{name, prog, args}

def Native.join.step(+c: P.Cfg, s: P.Step) -> P.Step:
  match s:
    case P.Daemon{+name, +prog, +args}:
      Native.join.daemon(String.eq(name, "join-server"), c, name, prog, args)
    case other:
      other

def Native.with_join_args(+c: P.Cfg, ss: +List<P.Step>) -> +List<P.Step>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      Con{Native.join.step(c, s), Native.with_join_args(c, t)}

# The cluster layer of Plan.node without the node: after the container
# runtime (Plan.runtime) and the kubelet's four steps (its config, its
# kubeconfig, its state wipe, its daemon) come upload-config, the
# bootstrap token, kube-proxy for joining nodes, the RBAC objects, the
# join server's Role, flannel, CoreDNS and the join material.
def Native.cluster(+c: P.Cfg) -> +List<P.Step>:
  List.drop(&2, P.Step, P.Plan.node(c), Nat.add(List.length(&2, P.Step, P.Plan.runtime()), 4n))

# The VM's boot plan (Plan.boot) from the PKI on, as data with VM paths.
def Native.plan(+c: P.Cfg) -> +List<P.Step>:
  List.append(&2, P.Step, P.Plan.pki_steps(c),
  List.append(&2, P.Step, Native.with_join_args(c, P.Plan.control_plane(c)),
  List.append(&2, P.Step, Native.cluster(c), P.Plan.publish(c))))

# The native boot plan: relocated, and with no machine step left whatever
# the paths (a data dir in /proc cannot bring one back).
def Native.boot(+e: Env, +c: P.Cfg) -> +List<P.Step>:
  Native.strip(Native.relocate(e, Native.plan(c)))

# A reduced plan for Linux CI (envtest has etcd and kube-apiserver, not
# the controller manager or the scheduler): the PKI, the store, the API
# server, the join server and the kubeconfig.
def Native.smoke_plan(+c: P.Cfg) -> +List<P.Step>:
  match c:
    case P.Cfg{+name, +ip, +svc, +pod, +dom, +port, +etcd}:
      +cfg : P.Cfg = P.Cfg{name, ip, svc, pod, dom, port, etcd}
      List.append(&2, P.Step, P.Plan.pki_steps(cfg),
      List.append(&2, P.Step, P.Plan.store(etcd, name),
      List.append(&2, P.Step,
        [ P.Daemon{"kube-apiserver", P.Plan.bin() ++ "/kube-apiserver", P.Plan.apiserver_args_ep(cfg)},
          P.WaitTcp{"127.0.0.1", 6443, 120000},
          Native.join_server(cfg),
          P.WaitTcp{"127.0.0.1", 8443, 30000} ],
      List.append(&2, P.Step, P.Plan.publish(cfg), [P.Log{"vk8s: native smoke up"}]))))

def Native.smoke(+e: Env, +c: P.Cfg) -> +List<P.Step>:
  Native.strip(Native.relocate(e, Native.smoke_plan(c)))

# --- What a plan runs

def Native.daemon_name(s: P.Step) -> +List<String>:
  match s:
    case P.Daemon{n, prog, args}:
      [n]
    case _:
      []

def Native.daemon_names(ss: +List<P.Step>) -> +List<String>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      List.append(&2, String, Native.daemon_name(s), Native.daemon_names(t))

def Native.prog(s: P.Step) -> +List<String>:
  match s:
    case P.Run{prog, args}:
      [prog]
    case P.Daemon{n, prog, args}:
      [prog]
    case P.Spawn{n, prog, args}:
      [prog]
    case _:
      []

def Native.progs(ss: +List<P.Step>) -> +List<String>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      List.append(&2, String, Native.prog(s), Native.progs(t))

# The directory of a file: "/a/b/c" is "/a/b", "/c" is "/".
def Native.dirname.or(empty: Bool, +d: String) -> String:
  match empty:
    case True{}:
      "/"
    case False{}:
      d

def Native.dirname.cut(slash: Bool, +t: String, more: String) -> String:
  match slash:
    case True{}:
      t
    case False{}:
      more

# s reversed: everything after its first '/'.
def Native.dirname.go(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{Chr{+c}, +t}:
      Native.dirname.cut(U32.is_eq(c, 47), t, Native.dirname.go(t))

def Native.dirname(+path: String) -> String:
  +d = String.reverse(Native.dirname.go(String.reverse(path)))
  Native.dirname.or(String.is_empty(d), d)

# --- Shutdown (N2)

# A pid the native runner may signal: one of its own children, so above 1
# (init) and below 2^31 (kill(2) reads larger values as negative: -1 is
# every process, the VM's PID 1 sends it; other negatives are process
# groups). 0 is the caller's own process group.
def Native.safe(+p: U32) -> Bool:
  Bool.and(U32.is_lt(1, p), U32.is_lt(p, 2147483648))

def Native.keep.go(ok: Bool, +p: U32, rest: List<&2, U32>) -> List<&2, U32>:
  match ok:
    case True{}:
      Con{p, rest}
    case False{}:
      rest

def Native.safe_pids(ps: List<&2, U32>) -> List<&2, U32>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{+p, t}:
      Native.keep.go(Native.safe(p), p, Native.safe_pids(t))

def Native.all_safe(ps: List<&2, U32>) -> Bool:
  match ps:
    case Nil{}:
      True{}
    case Con{+p, t}:
      Bool.and(Native.safe(p), Native.all_safe(t))

# The pids native shutdown signals: its running daemons, last started
# first (Sup.stop_order), and nothing else.
def Native.stop_pids(svcs: +List<S.Svc>) -> List<&2, U32>:
  Native.safe_pids(S.Sup.stop_order(svcs))

def Native.name_if(ok: Bool, +n: String) -> +List<String>:
  match ok:
    case True{}:
      [n]
    case False{}:
      []

# Their names, in the same order (for the log).
def Native.stop_names(svcs: +List<S.Svc>) -> +List<String>:
  match svcs:
    case Nil{}:
      Nil{}
    case Con{+s, t}:
      List.append(&2, String, Native.stop_names(t), Native.name_if(Native.safe(S.Sup.pid(s)), S.Sup.name(s)))
