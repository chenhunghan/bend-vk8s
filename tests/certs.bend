import Base
import ../src/standalone/certs.bend as C

# Tests for src/standalone/certs.bend. The laws in laws/certs.bend
# transcribe vcluster's pkg/certs tests; these cover the rest: renewal at
# real Unix hours, SAN classification, vk8s's own configuration (advertise
# address 10.10.0.2, API server SANs), the file layout and the copy steps.
# Expected values follow vcluster's and the vendored kubeadm's Go code.

def T.check(+name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name)

def T.same(xs: +List<String>, ys: +List<String>) -> Bool:
  String.eq(String.join(xs, "\n"), String.join(ys, "\n"))

def T.bools(xs: +List<Bool>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{True{}, t}:
      "T" ++ T.bools(t)
    case Con{False{}, t}:
      "F" ++ T.bools(t)

# vk8s's control plane: node IP 10.10.0.2 on the cluster LAN, endpoint
# 10.10.0.2, API server SANs as src/guest/plan.bend's kubeadm config.
def T.vk8s() -> C.Cfg:
  C.Cfg{"demo", "10.10.0.2", "10.10.0.2", "10.96.0.1", "cluster.local",
    ["127.0.0.1", "localhost", "10.0.2.15", "demo"], C.Certs.etcd_extra_sans([])}

def T.spec_dns(s: C.Spec) -> +List<String>:
  C.Certs.Spec.dns(s)

def T.spec_ips(s: C.Spec) -> +List<String>:
  C.Certs.Spec.ips(s)

def T.is_ips(xs: +List<String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+x, t}:
      T.bools([C.Certs.is_ip(x)]) ++ T.is_ips(t)

def T.is_dns(xs: +List<String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+x, t}:
      T.bools([Bool.or(C.Certs.is_dns(x), C.Certs.is_wildcard(x))]) ++ T.is_dns(t)

def T.rollout(r: C.Rollout) -> String:
  match r:
    case C.PatchStatefulSet{ns, n, k, v}:
      "sts " ++ ns ++ "/" ++ n
    case C.PatchDeployment{ns, n, k, v}:
      "deploy " ++ ns ++ "/" ++ n
    case C.RolloutError{m}:
      m
    case C.NoRollout{}:
      "none"

# 2026-11-07 00:00 UTC is hour 498336 of the Unix epoch.
def main() -> IO(Unit):
  do IO<Unit>:
    T.check("renew: 365 days left", Bool.not(C.Certs.needs_renewal(498336n, 507096n)))
    T.check("renew: 91 days left", Bool.not(C.Certs.needs_renewal(498336n, 500520n)))
    T.check("renew: exactly 90 days left", C.Certs.needs_renewal(498336n, 500496n))
    T.check("renew: 89 days left", C.Certs.needs_renewal(498336n, 500472n))
    T.check("renew: expired", C.Certs.needs_renewal(498336n, 400000n))
    T.check("ParseIPSloppy-like classification",
      String.eq(T.is_ips(["10.0.0.1", "010.000.000.001", "fe80::1", "::ffff:10.0.0.1", "256.0.0.1", "1.2.3", "a.b.c.d", "localhost", ""]), "TTTTFFFFF"))
    T.check("DNS-1123 subdomains and wildcards",
      String.eq(T.is_dns(["localhost", "a.b-c.d", "*.svc.local", "-a", "a-", "A", "a..b", "a_b", "*", ""]), "TTTFFFFFFF"))
    T.check("vk8s apiserver DNS SANs",
      T.same(T.spec_dns(C.Certs.apiserver(T.vk8s(), "ca")),
        ["demo", "kubernetes", "kubernetes.default", "kubernetes.default.svc", "kubernetes.default.svc.cluster.local", "localhost", "demo"]))
    T.check("vk8s apiserver IP SANs",
      T.same(T.spec_ips(C.Certs.apiserver(T.vk8s(), "ca")), ["10.96.0.1", "10.10.0.2", "10.10.0.2", "127.0.0.1", "10.0.2.15"]))
    T.check("vk8s apiserver final SANs",
      T.same(C.Certs.final_dns(C.Certs.apiserver(T.vk8s(), "ca")),
        ["demo", "kubernetes", "kubernetes.default", "kubernetes.default.svc", "kubernetes.default.svc.cluster.local", "localhost"]))
    T.check("vk8s apiserver final IPs",
      T.same(C.Certs.final_ips(C.Certs.apiserver(T.vk8s(), "ca")), ["10.96.0.1", "10.10.0.2", "127.0.0.1", "10.0.2.15"]))
    T.check("vk8s etcd server IPs",
      T.same(C.Certs.final_ips(C.Certs.etcd_server(T.vk8s())), ["10.10.0.2", "127.0.0.1", "::1", "0.0.0.0"]))
    T.check("vk8s admin kubeconfig context",
      String.eq(C.Certs.context(C.Certs.kubeconfig(T.vk8s(), "admin.conf", "kubernetes-super-admin", ["system:masters"], False{})),
        "kubernetes-super-admin@demo"))
    T.check("empty node name: localhost only",
      T.same(C.Certs.node_dns(""), ["localhost"]))
    T.check("empty DNS domain: no kubernetes.default.svc.<domain>",
      T.same(T.spec_dns(C.Certs.apiserver(C.Cfg{"n", "127.0.0.1", "", "10.96.0.1", "", [], []}, "ca")),
        ["n", "kubernetes", "kubernetes.default", "kubernetes.default.svc"]))
    T.check("DNS endpoint goes to the DNS SANs",
      T.same(T.spec_dns(C.Certs.apiserver(C.Cfg{"n", "127.0.0.1", "cp.example.com", "10.96.0.1", "", [], []}, "ca")),
        ["n", "kubernetes", "kubernetes.default", "kubernetes.default.svc", "cp.example.com"]))
    T.check("secret keys", String.eq(C.Certs.secret_key("etcd/healthcheck-client.key"), "etcd-healthcheck-client.key"))
    T.check("base names", T.same([C.Certs.basename("etcd/ca.crt"), C.Certs.basename("ca.key"), C.Certs.basename("a/b/c")], ["ca.crt", "ca.key", "c"]))
    T.check("keep: CA and SA files",
      String.eq(T.bools([C.Certs.keep("ca.crt", True{}), C.Certs.keep("front-proxy-ca.key", True{}), C.Certs.keep("sa.pub", False{}),
        C.Certs.keep("ca.crt", False{}), C.Certs.keep("apiserver.crt", True{}), C.Certs.keep("kubelet.conf", True{})]), "TTTFFF"))
    T.check("sort without duplicates", T.same(C.Certs.sort_uniq(["b", "a", "c", "a", "b"]), ["a", "b", "c"]))
    T.check("first of each", T.same(C.Certs.uniq(["b", "a", "b", "c", "a"]), ["b", "a", "c"]))
    T.check("CA warning, expired bundle second cert",
      T.same(C.Certs.ca_expiring(100n, [C.Entry{"ca.crt", C.Bundle{[C.Cert{"a", 9000n}, C.Cert{"b", 50n}]}}]), ["b"]))
    T.check("a bundle without certificates needs renewal",
      C.Certs.secret_expiring(100n, [C.Entry{"apiserver.crt", C.Bundle{[]}}]))
    T.check("rotate-ca copies server-ca and client-ca from the new CA",
      T.same([C.Certs.fs_read(C.Certs.run(C.Certs.split_ca_steps(),
          [C.PkiFile{"/var/lib/vcluster/pki/ca.crt", "new"}, C.PkiFile{"/var/lib/vcluster/pki/ca.key", "new-key"}]),
          "/var/lib/vcluster/pki/client-ca.crt")], ["new"]))
    T.check("rollout: no workload",
      String.eq(T.rollout(C.Certs.rollout_control_plane(False{}, False{}, "ns", "test", "x")), "control-plane workload ns/test not found"))
    T.check("rollout: etcd statefulset",
      String.eq(T.rollout(C.Certs.rollout_etcd(True{}, "ns", "test", "x")), "sts ns/test-etcd"))
