import Base
import ../src/guest/plan.bend as P

# The control-plane command lines of src/guest/plan.bend, run: vcluster's
# base flags (pkg/k8s/k8s.go) merged with vk8s's apiserver overrides.

def T.check(+name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name)

def T.same(xs: +List<String>, ys: +List<String>) -> Bool:
  String.eq(String.join(xs, "\n"), String.join(ys, "\n"))

def T.pki(+f: String) -> String:
  "/var/lib/vcluster/pki/" ++ f

# The apiserver's flags after the merge; etcd: the store's flags.
def T.apiserver(store: +List<String>) -> +List<String>:
  List.append(&2, String,
    [ "--service-cluster-ip-range=10.96.0.0/12",
      "--allow-privileged=true",
      "--authorization-mode=Node,RBAC",
      "--client-ca-file=" ++ T.pki("client-ca.crt"),
      "--enable-bootstrap-token-auth=true" ],
  List.append(&2, String, store,
    [ "--proxy-client-cert-file=" ++ T.pki("front-proxy-client.crt"),
      "--proxy-client-key-file=" ++ T.pki("front-proxy-client.key"),
      "--requestheader-allowed-names=front-proxy-client",
      "--requestheader-client-ca-file=" ++ T.pki("front-proxy-ca.crt"),
      "--requestheader-extra-headers-prefix=X-Remote-Extra-",
      "--requestheader-group-headers=X-Remote-Group",
      "--requestheader-username-headers=X-Remote-User",
      "--secure-port=6443",
      "--service-account-issuer=https://kubernetes.default.svc.cluster.local",
      "--service-account-key-file=" ++ T.pki("sa.pub"),
      "--service-account-signing-key-file=" ++ T.pki("sa.key"),
      "--tls-cert-file=" ++ T.pki("apiserver.crt"),
      "--tls-private-key-file=" ++ T.pki("apiserver.key"),
      "--profiling=false",
      "--kubelet-client-certificate=" ++ T.pki("apiserver-kubelet-client.crt"),
      "--kubelet-client-key=" ++ T.pki("apiserver-kubelet-client.key"),
      "--enable-admission-plugins=NodeRestriction",
      "--kubelet-preferred-address-types=InternalDNS,InternalIP,Hostname,ExternalDNS,ExternalIP",
      "--bind-address=0.0.0.0",
      "--advertise-address=10.10.0.2",
      "--endpoint-reconciler-type=lease" ]))

# A step as one line, for comparisons.
def T.step(s: P.Step) -> String:
  match s:
    case P.Run{prog, args}:
      "run " ++ prog ++ " " ++ String.join(args, " ")
    case P.Daemon{n, prog, args}:
      "daemon " ++ n
    case P.WaitFile{path, ms}:
      "waitfile " ++ path
    case P.Log{t}:
      "log " ++ t
    case _:
      "other"

def T.steps(ss: +List<P.Step>) -> +List<String>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      Con{T.step(s), T.steps(t)}

def T.lines(ss: +List<P.Step>) -> String:
  String.join(T.steps(ss), "\n")

def main() -> IO(Unit):
  do IO<Unit>:
    T.check("add_sans on the real kubeadm config puts the SAN first",
      String.contains(P.Plan.add_sans(P.Plan.kubeadm_config(P.Plan.classic_cfg("vc", 12000, False{}, "10.96.0.0/12")), ["10.100.0.5"]),
        "certSANs:\n  - 10.100.0.5\n  - 127.0.0.1\n"))
    T.check("add_sans with no SANs leaves the real kubeadm config alone",
      String.eq(P.Plan.add_sans(P.Plan.kubeadm_config(P.Plan.default_cfg("demo", 12000, False{})), []), P.Plan.kubeadm_config(P.Plan.default_cfg("demo", 12000, False{}))))
    T.check("apiserver flags, kine",
      T.same(P.Plan.apiserver_args(P.Plan.default_cfg("demo", 6443, False{})),
        T.apiserver(["--etcd-servers=unix:///var/lib/vcluster/kine.sock"])))
    T.check("apiserver flags, etcd",
      T.same(P.Plan.apiserver_args(P.Plan.default_cfg("demo", 6443, True{})),
        T.apiserver([ "--etcd-servers=https://127.0.0.1:2379",
          "--etcd-cafile=" ++ T.pki("etcd/ca.crt"),
          "--etcd-certfile=" ++ T.pki("apiserver-etcd-client.crt"),
          "--etcd-keyfile=" ++ T.pki("apiserver-etcd-client.key") ])))
    T.check("controller-manager flags end with the private-nodes flags",
      T.same(List.drop(&2, String, P.Plan.controller_manager_args(P.Plan.default_cfg("demo", 6443, False{})), 12n),
        [ "--cluster-signing-cert-file=" ++ T.pki("server-ca.crt"),
          "--cluster-signing-key-file=" ++ T.pki("server-ca.key"),
          "--controllers=*,bootstrapsigner,tokencleaner",
          "--allocate-node-cidrs=true",
          "--cluster-cidr=10.244.0.0/16",
          "--cloud-provider=external" ]))
    T.check("scheduler flags",
      T.same(P.Plan.scheduler_args(),
        [ "--authentication-kubeconfig=" ++ T.pki("scheduler.conf"),
          "--authorization-kubeconfig=" ++ T.pki("scheduler.conf"),
          "--bind-address=127.0.0.1",
          "--kubeconfig=" ++ T.pki("scheduler.conf"),
          "--leader-elect=true" ]))
    T.check("kine flags",
      T.same(P.Plan.kine_args(),
        [ "--endpoint=sqlite:///var/lib/vcluster/state.db?_journal=WAL&cache=shared&_busy_timeout=30000&_txlock=immediate",
          "--metrics-bind-address=127.0.0.1:2381",
          "--listen-address=unix:///var/lib/vcluster/kine.sock" ]))
    T.check("sh_quote empty", String.eq(P.Plan.sh_quote(""), "''"))
    T.check("sh_quote plain", String.eq(P.Plan.sh_quote("abc"), "'abc'"))
    T.check("sh_quote single quote", String.eq(P.Plan.sh_quote("it's"), "'it'\\''s'"))
    T.check("snapshot-export, etcd: etcdctl snapshot save into export.tmp, then export",
      T.same(T.steps(P.Plan.request("snapshot-export", P.Plan.default_cfg("demo", 12000, True{}), "/o")),
        [ "run /bin/busybox rm -rf /var/lib/vk8s-host/snapshot/export /var/lib/vk8s-host/snapshot/export.tmp",
          "run /bin/busybox mkdir -p /var/lib/vk8s-host/snapshot/export.tmp",
          "run /var/lib/vcluster/bin/etcdctl --endpoints https://127.0.0.1:2379 --cacert " ++ T.pki("etcd/ca.crt")
            ++ " --cert " ++ T.pki("apiserver-etcd-client.crt") ++ " --key " ++ T.pki("apiserver-etcd-client.key")
            ++ " snapshot save /var/lib/vk8s-host/snapshot/export.tmp/db",
          "run /bin/busybox mv /var/lib/vk8s-host/snapshot/export.tmp /var/lib/vk8s-host/snapshot/export" ]))
    T.check("snapshot-export, kine: count-only get, then pages at one revision",
      T.same(T.steps(P.Plan.request("snapshot-export", P.Plan.default_cfg("demo", 12000, False{}), "/o")),
        [ "run /bin/busybox rm -rf /var/lib/vk8s-host/snapshot/export /var/lib/vk8s-host/snapshot/export.tmp",
          "run /bin/busybox mkdir -p /var/lib/vk8s-host/snapshot/export.tmp",
          "run /bin/busybox sh -c " ++ P.Plan.kine_dump_script(),
          "run /bin/busybox mv /var/lib/vk8s-host/snapshot/export.tmp /var/lib/vk8s-host/snapshot/export" ]))
    T.check("kine dump: the count-only get comes first",
      String.contains(P.Plan.kine_dump_script(), "c get / --prefix --count-only -w json > $d/count.json; rv $d/count.json > $d/revision;"))
    T.check("kine dump: later pages at the first page's revision",
      String.contains(P.Plan.kine_dump_script(), "c get \"$k\" 0 --limit 1000 --rev \"$r\" -w json > $d/page-$n.json"))
    T.check("snapshot-export with more words has no steps",
      List.is_empty(&2, P.Step, P.Plan.request("snapshot-export; rm -rf /", P.Plan.default_cfg("demo", 12000, True{}), "/o")))
    T.check("snapshot-export in classic mode has no steps",
      List.is_empty(&2, P.Step, P.Plan.request_mode(True{}, "snapshot-export", P.Plan.default_cfg("demo", 12000, True{}), "/o")))
    T.check("snapshot-dump, etcd: the steps of snapshot-export",
      T.same(T.steps(P.Plan.request("snapshot-dump", P.Plan.default_cfg("demo", 12000, True{}), "/o")),
        T.steps(P.Plan.request("snapshot-export", P.Plan.default_cfg("demo", 12000, True{}), "/o"))))
    T.check("snapshot-dump, kine: the v2 paging script",
      T.same(T.steps(P.Plan.request("snapshot-dump", P.Plan.default_cfg("demo", 12000, False{}), "/o")),
        [ "run /bin/busybox rm -rf /var/lib/vk8s-host/snapshot/export /var/lib/vk8s-host/snapshot/export.tmp",
          "run /bin/busybox mkdir -p /var/lib/vk8s-host/snapshot/export.tmp",
          "run /bin/busybox sh -c " ++ P.Plan.kine_dump_script.v2(),
          "run /bin/busybox mv /var/lib/vk8s-host/snapshot/export.tmp /var/lib/vk8s-host/snapshot/export" ]))
    T.check("kine dump v2: the count-only get writes -w fields (etcdctl 3.5 refuses -w json)",
      String.contains(P.Plan.kine_dump_script.v2(), "c get / --prefix --count-only -w fields > $d/count.txt;"))
    T.check("kine dump v2: no count-only get with -w json",
      Bool.not(String.contains(P.Plan.kine_dump_script.v2(), "--count-only -w json")))
    T.check("snapshot-dump with more words has no steps",
      List.is_empty(&2, P.Step, P.Plan.request("snapshot-dump; rm -rf /", P.Plan.default_cfg("demo", 12000, True{}), "/o")))
    T.check("snapshot-dump in classic mode has no steps",
      List.is_empty(&2, P.Step, P.Plan.request_mode(True{}, "snapshot-dump", P.Plan.default_cfg("demo", 12000, True{}), "/o")))
    T.check("boot without the restore marker is the boot, kine",
      String.eq(T.lines(P.Plan.boot_restore(P.Plan.default_cfg("demo", 12000, False{}), False{})),
        T.lines(P.Plan.boot(P.Plan.default_cfg("demo", 12000, False{})))))
    T.check("boot without the restore marker is the boot, etcd",
      String.eq(T.lines(P.Plan.boot_restore(P.Plan.default_cfg("demo", 12000, True{}), False{})),
        T.lines(P.Plan.boot(P.Plan.default_cfg("demo", 12000, True{})))))
    T.check("restore boot, etcd: etcdutl restore right before etcd starts",
      String.contains(T.lines(P.Plan.boot_restore(P.Plan.default_cfg("demo", 12000, True{}), True{})),
        "log vk8s: restoring etcd from the snapshot\nrun /var/lib/vcluster/bin/etcdutl snapshot restore /var/lib/vk8s-host/snapshot/db --name demo"
        ++ " --data-dir /var/lib/vcluster/etcd --initial-cluster demo=https://127.0.0.1:2380 --initial-cluster-token vcluster"
        ++ " --initial-advertise-peer-urls https://127.0.0.1:2380 --bump-revision 1000 --mark-compacted\n"
        ++ "run /bin/busybox rm -f /var/lib/vk8s-host/snapshot/restore /var/lib/vk8s-host/snapshot/db\ndaemon etcd\n"))
    T.check("restore boot, kine: the puts after kine starts, before kube-apiserver",
      String.contains(T.lines(P.Plan.boot_restore(P.Plan.default_cfg("demo", 12000, False{}), True{})),
        "daemon kine\nwaitfile /var/lib/vcluster/kine.sock\nlog vk8s: restoring kine from the snapshot\nrun /bin/busybox sh -c "
        ++ P.Plan.kine_puts_script() ++ "\nrun /bin/busybox rm -f /var/lib/vk8s-host/snapshot/restore /var/lib/vk8s-host/snapshot/puts\ndaemon kube-apiserver\n"))
    T.check("restore boot adds three steps, etcd",
      Nat.is_eq(List.length(&2, P.Step, P.Plan.boot_restore(P.Plan.default_cfg("demo", 12000, True{}), True{})),
        Nat.add(List.length(&2, P.Step, P.Plan.boot(P.Plan.default_cfg("demo", 12000, True{}))), 3n)))
    T.check("restore boot adds three steps, kine",
      Nat.is_eq(List.length(&2, P.Step, P.Plan.boot_restore(P.Plan.default_cfg("demo", 12000, False{}), True{})),
        Nat.add(List.length(&2, P.Step, P.Plan.boot(P.Plan.default_cfg("demo", 12000, False{}))), 3n)))
    T.check("kine puts: vcluster's txn create shape",
      String.contains(P.Plan.kine_puts_script(), "printf 'mod(\"%s\") = \"0\"\\n\\nput %s %s\\n\\n\\n' \"$k\" \"$k\" \"$v\" | c txn -w json"))
    T.check("the control plane's kubelet removes images unused for 1h",
      String.ends_with(P.Plan.kubelet_config("cluster.local"), "staticPodPath: /etc/kubernetes/manifests\nimageMaximumGCAge: 1h\n"))
    T.check("workers' kubelet-config (kubeadm upload-config) removes images unused for 1h",
      String.ends_with(P.Plan.kubeadm_config(P.Plan.default_cfg("demo", 6443, False{})), "kind: KubeletConfiguration\ncgroupDriver: cgroupfs\nfailSwapOn: false\nresolvConf: /etc/resolv.conf\nimageMaximumGCAge: 1h\n"))
    T.check("fstrim runs every 10 min of 250 ms ticks",
      Bool.and(Bool.and(P.Plan.fstrim_due(2400), P.Plan.fstrim_due(7200)), Bool.not(Bool.or(P.Plan.fstrim_due(1), P.Plan.fstrim_due(2401)))))
    T.check("every VM mounts its data disk where fstrim trims it",
      String.eq(P.Plan.data(), "/var/lib/vcluster"))
    T.check("idle reclaim writes the root cgroup's memory.reclaim, file pages only",
      String.contains(P.Plan.idle_reclaim_script(), "\"${k}K swappiness=0\" > /sys/fs/cgroup/memory.reclaim"))
    T.check("idle reclaim needs a busy share under 10% of the window",
      String.contains(P.Plan.idle_reclaim_script(), "[ $((b*100)) -lt $((dt*10)) ] || exit 0"))
    T.check("idle reclaim keeps 64 MiB of file cache",
      String.contains(P.Plan.idle_reclaim_script(), "END { print s - 65536 }"))
    T.check("idle reclaim runs every 30 s", U32.is_eq(P.Plan.reclaim_every_ticks(), 120))
