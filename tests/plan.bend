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
