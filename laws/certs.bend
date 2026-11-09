import Base
import ../src/standalone/certs.bend as C

# Spec for src/standalone/certs.bend: vcluster's certificate management in
# standalone mode (vcluster pkg/certs, a8ab30e; kubeadm v1.36.3 as
# vendored).
#
# The concrete laws transcribe every case of pkg/certs/ensure_test.go and
# pkg/certs/watcher_test.go; the rest come from reading vcluster's Go code
# (pkg/certs, pkg/util/certhelper, pkg/kubeadm) and the vendored kubeadm
# (phases/certs/certlist.go, phases/kubeconfig/kubeconfig.go,
# util/pkiutil/pki_helpers.go, constants/constants.go).
#
# Time is in hours. The tests' certificates expire at now + 365 days
# (valid), now + 60 days (expiring soon) and now - 24 h (already expired);
# with now = 100 h they are 8860, 1540 and 76.

# Fixtures.

def Laws.certs.now() -> Nat:
  100n

def Laws.certs.pem(+cn: String, +not_after: Nat) -> C.Pem:
  C.Bundle{[C.Cert{cn, not_after}]}

# newSelfSignedCertPEM(t, "valid-cert", time.Now().Add(365*24*time.Hour)).
def Laws.certs.valid() -> C.Pem:
  Laws.certs.pem("valid-cert", 8860n)

# newSelfSignedCertPEM(t, "expiring-soon", time.Now().Add(60*24*time.Hour)).
def Laws.certs.soon() -> C.Pem:
  Laws.certs.pem("expiring-soon", 1540n)

# newSelfSignedCertPEM(t, "already-expired", time.Now().Add(-24*time.Hour)).
def Laws.certs.expired() -> C.Pem:
  Laws.certs.pem("already-expired", 76n)

def Laws.certs.ent(+k: String, +p: C.Pem) -> C.Entry:
  C.Entry{k, p}

# buildSecretData(crt): every certMap value; .crt entries hold crt, the
# .key, .pub and .conf entries placeholder bytes (no PEM).
def Laws.certs.secret(+crt: C.Pem) -> +List<C.Entry>:
  [ Laws.certs.ent("admin.conf", C.Unparsable{}),
    Laws.certs.ent("controller-manager.conf", C.Unparsable{}),
    Laws.certs.ent("scheduler.conf", C.Unparsable{}),
    Laws.certs.ent("apiserver.crt", crt),
    Laws.certs.ent("apiserver.key", C.Unparsable{}),
    Laws.certs.ent("apiserver-etcd-client.crt", crt),
    Laws.certs.ent("apiserver-etcd-client.key", C.Unparsable{}),
    Laws.certs.ent("apiserver-kubelet-client.crt", crt),
    Laws.certs.ent("apiserver-kubelet-client.key", C.Unparsable{}),
    Laws.certs.ent("ca.crt", crt),
    Laws.certs.ent("ca.key", C.Unparsable{}),
    Laws.certs.ent("server-ca.crt", crt),
    Laws.certs.ent("server-ca.key", C.Unparsable{}),
    Laws.certs.ent("client-ca.crt", crt),
    Laws.certs.ent("client-ca.key", C.Unparsable{}),
    Laws.certs.ent("front-proxy-ca.crt", crt),
    Laws.certs.ent("front-proxy-ca.key", C.Unparsable{}),
    Laws.certs.ent("front-proxy-client.crt", crt),
    Laws.certs.ent("front-proxy-client.key", C.Unparsable{}),
    Laws.certs.ent("sa.key", C.Unparsable{}),
    Laws.certs.ent("sa.pub", C.Unparsable{}),
    Laws.certs.ent("etcd-ca.crt", crt),
    Laws.certs.ent("etcd-ca.key", C.Unparsable{}),
    Laws.certs.ent("etcd-healthcheck-client.crt", crt),
    Laws.certs.ent("etcd-healthcheck-client.key", C.Unparsable{}),
    Laws.certs.ent("etcd-peer.crt", crt),
    Laws.certs.ent("etcd-peer.key", C.Unparsable{}),
    Laws.certs.ent("etcd-server.crt", crt),
    Laws.certs.ent("etcd-server.key", C.Unparsable{}) ]

# The watcher tests' PKI directory: every certMap key as a file; a file
# whose secret key ends in .crt holds crt, the others "placeholder".
def Laws.certs.disk(+crt: C.Pem, +ca_crt: C.Pem, +api_crt: C.Pem) -> +List<C.Entry>:
  [ Laws.certs.ent("admin.conf", C.Unparsable{}),
    Laws.certs.ent("controller-manager.conf", C.Unparsable{}),
    Laws.certs.ent("scheduler.conf", C.Unparsable{}),
    Laws.certs.ent("apiserver.crt", api_crt),
    Laws.certs.ent("apiserver.key", C.Unparsable{}),
    Laws.certs.ent("apiserver-etcd-client.crt", crt),
    Laws.certs.ent("apiserver-etcd-client.key", C.Unparsable{}),
    Laws.certs.ent("apiserver-kubelet-client.crt", crt),
    Laws.certs.ent("apiserver-kubelet-client.key", C.Unparsable{}),
    Laws.certs.ent("ca.crt", ca_crt),
    Laws.certs.ent("ca.key", C.Unparsable{}),
    Laws.certs.ent("server-ca.crt", crt),
    Laws.certs.ent("server-ca.key", C.Unparsable{}),
    Laws.certs.ent("client-ca.crt", crt),
    Laws.certs.ent("client-ca.key", C.Unparsable{}),
    Laws.certs.ent("front-proxy-ca.crt", crt),
    Laws.certs.ent("front-proxy-ca.key", C.Unparsable{}),
    Laws.certs.ent("front-proxy-client.crt", crt),
    Laws.certs.ent("front-proxy-client.key", C.Unparsable{}),
    Laws.certs.ent("sa.key", C.Unparsable{}),
    Laws.certs.ent("sa.pub", C.Unparsable{}),
    Laws.certs.ent("etcd/ca.crt", crt),
    Laws.certs.ent("etcd/ca.key", C.Unparsable{}),
    Laws.certs.ent("etcd/healthcheck-client.crt", crt),
    Laws.certs.ent("etcd/healthcheck-client.key", C.Unparsable{}),
    Laws.certs.ent("etcd/peer.crt", crt),
    Laws.certs.ent("etcd/peer.key", C.Unparsable{}),
    Laws.certs.ent("etcd/server.crt", crt),
    Laws.certs.ent("etcd/server.key", C.Unparsable{}) ]

def Laws.certs.set.if(hit: Bool, +k: String, +old: C.Pem, +new: C.Pem) -> C.Entry:
  match hit:
    case True{}:
      C.Entry{k, new}
    case False{}:
      C.Entry{k, old}

# data[k] = p.
def Laws.certs.set(es: +List<C.Entry>, +k: String, +p: C.Pem) -> +List<C.Entry>:
  match es:
    case Nil{}:
      Nil{}
    case Con{C.Entry{+key, +old}, t}:
      Laws.certs.set.if(String.eq(key, k), key, old, p) <> Laws.certs.set(t, k, p)

def Laws.certs.del.if(hit: Bool, +key: String, +old: C.Pem, rest: +List<C.Entry>) -> +List<C.Entry>:
  match hit:
    case True{}:
      rest
    case False{}:
      C.Entry{key, old} <> rest

# delete(data, k).
def Laws.certs.del(es: +List<C.Entry>, +k: String) -> +List<C.Entry>:
  match es:
    case Nil{}:
      Nil{}
    case Con{C.Entry{+key, +old}, t}:
      Laws.certs.del.if(String.eq(key, k), key, old, Laws.certs.del(t, k))

def Laws.certs.expiring(+es: +List<C.Entry>) -> Bool:
  C.Certs.secret_expiring(Laws.certs.now(), es)

# vcluster standalone named my-vcluster, default service CIDR
# 10.96.0.0/12 (first IP 10.96.0.1), cluster domain cluster.local, no
# proxy extra SANs.
def Laws.certs.cfg() -> C.Cfg:
  C.Certs.vcluster_cfg("my-vcluster", "10.96.0.1", "cluster.local", [])

# ensure_test.go testKubeadmConfig: node test-node, service subnet
# 10.96.0.0/12, DNS domain cluster.local, advertise address 127.0.0.1, no
# control-plane endpoint.
def Laws.certs.test_cfg() -> C.Cfg:
  C.Cfg{"test-node", "127.0.0.1", "", "10.96.0.1", "cluster.local", [], []}

def Laws.certs.p(+f: String) -> String:
  "/var/lib/vcluster/pki/" ++ f

def Laws.certs.apiserver(+signer: String) -> C.Spec:
  C.Spec{"apiserver", "kube-apiserver", [], signer, [C.ServerAuth{}],
    ["my-vcluster", "kubernetes", "kubernetes.default", "kubernetes.default.svc", "kubernetes.default.svc.cluster.local"],
    ["10.96.0.1", "127.0.0.1", "127.0.0.1"], 365n}

def Laws.certs.etcd_node(+base: String) -> C.Spec:
  C.Spec{base, "my-vcluster", [], "etcd-ca", [C.ServerAuth{}, C.ClientAuth{}],
    ["my-vcluster", "localhost", "localhost"],
    ["127.0.0.1", "127.0.0.1", "::1", "127.0.0.1", "0.0.0.0"], 365n}

# CreatePKIAssets for Laws.certs.cfg (GetDefaultCertList).
def Laws.certs.plan() -> +List<C.Spec>:
  [ C.Spec{"ca", "kubernetes", [], "", [], [], [], 3650n},
    Laws.certs.apiserver("ca"),
    C.Spec{"apiserver-kubelet-client", "kube-apiserver-kubelet-client", [], "ca", [C.ClientAuth{}], [], [], 365n},
    C.Spec{"front-proxy-ca", "front-proxy-ca", [], "", [], [], [], 3650n},
    C.Spec{"front-proxy-client", "front-proxy-client", [], "front-proxy-ca", [C.ClientAuth{}], [], [], 365n},
    C.Spec{"etcd/ca", "etcd-ca", [], "", [], [], [], 3650n},
    Laws.certs.etcd_node("etcd/server"),
    Laws.certs.etcd_node("etcd/peer"),
    C.Spec{"etcd/healthcheck-client", "kube-etcd-healthcheck-client", [], "etcd-ca", [C.ClientAuth{}], [], [], 365n},
    C.Spec{"apiserver-etcd-client", "kube-apiserver-etcd-client", [], "etcd-ca", [C.ClientAuth{}], [], [], 365n} ]

def Laws.certs.kc(+file: String, +user: String, +orgs: +List<String>) -> C.Kconf:
  C.Kconf{file, user, orgs, "https://127.0.0.1:6443", "my-vcluster", 365n}

# generateCertificates for Laws.certs.cfg; split adds the split-CA steps.
def Laws.certs.generated(split: +List<C.Step>) -> +List<C.Step>:
  List.append(&2, C.Step,
    [ C.CreateCert{C.Spec{"ca", "kubernetes", [], "", [], [], [], 3650n}},
      C.CreateCert{Laws.certs.apiserver("ca")},
      C.CreateCert{C.Spec{"apiserver-kubelet-client", "kube-apiserver-kubelet-client", [], "ca", [C.ClientAuth{}], [], [], 365n}},
      C.CreateCert{C.Spec{"front-proxy-ca", "front-proxy-ca", [], "", [], [], [], 3650n}},
      C.CreateCert{C.Spec{"front-proxy-client", "front-proxy-client", [], "front-proxy-ca", [C.ClientAuth{}], [], [], 365n}},
      C.CreateCert{C.Spec{"etcd/ca", "etcd-ca", [], "", [], [], [], 3650n}},
      C.CreateCert{Laws.certs.etcd_node("etcd/server")},
      C.CreateCert{Laws.certs.etcd_node("etcd/peer")},
      C.CreateCert{C.Spec{"etcd/healthcheck-client", "kube-etcd-healthcheck-client", [], "etcd-ca", [C.ClientAuth{}], [], [], 365n}},
      C.CreateCert{C.Spec{"apiserver-etcd-client", "kube-apiserver-etcd-client", [], "etcd-ca", [C.ClientAuth{}], [], [], 365n}},
      C.CreateSAKeys{},
      C.CreateKubeconfig{Laws.certs.kc("admin.conf", "kubernetes-admin", ["kubeadm:cluster-admins"])},
      C.CreateKubeconfig{Laws.certs.kc("controller-manager.conf", "system:kube-controller-manager", [])},
      C.CreateKubeconfig{Laws.certs.kc("scheduler.conf", "system:kube-scheduler", [])},
      C.CreateKubeconfig{Laws.certs.kc("super-admin.conf", "kubernetes-super-admin", ["system:masters"])},
      C.Rename{Laws.certs.p("super-admin.conf"), Laws.certs.p("admin.conf")},
      C.CopyCertIfMissing{Laws.certs.p("ca.crt"), Laws.certs.p("server-ca.crt")},
      C.CopyIfMissing{Laws.certs.p("ca.key"), Laws.certs.p("server-ca.key")},
      C.CopyCertIfMissing{Laws.certs.p("ca.crt"), Laws.certs.p("client-ca.crt")},
      C.CopyIfMissing{Laws.certs.p("ca.key"), Laws.certs.p("client-ca.key")} ],
    split)

def Laws.certs.etcd_removals() -> +List<C.Step>:
  [ C.Remove{Laws.certs.p("etcd/peer.crt")}, C.Remove{Laws.certs.p("etcd/peer.key")},
    C.Remove{Laws.certs.p("etcd/server.crt")}, C.Remove{Laws.certs.p("etcd/server.key")} ]

def Laws.certs.fs(+path: String, +data: String) -> C.PkiFile:
  C.PkiFile{Laws.certs.p(path), data}

# The four aliases splitCACert writes, as read back.
def Laws.certs.aliases(+fs: +List<C.PkiFile>) -> +List<String>:
  [ C.Certs.fs_read(fs, Laws.certs.p("server-ca.crt")), C.Certs.fs_read(fs, Laws.certs.p("server-ca.key")),
    C.Certs.fs_read(fs, Laws.certs.p("client-ca.crt")), C.Certs.fs_read(fs, Laws.certs.p("client-ca.key")) ]

# ensure_test.go TestCertsExpiringSoon.

# "all certs valid"
law certs.expiring.all_valid:
  {Laws.certs.expiring(Laws.certs.secret(Laws.certs.valid())) == False{} : Bool}

# "leaf cert expiring in 60 days"
law certs.expiring.leaf_60_days:
  {Laws.certs.expiring(Laws.certs.set(Laws.certs.secret(Laws.certs.valid()), "apiserver.crt", Laws.certs.soon()))
    == True{} : Bool}

# "leaf cert already expired"
law certs.expiring.leaf_expired:
  {Laws.certs.expiring(Laws.certs.set(Laws.certs.secret(Laws.certs.valid()), "apiserver.crt", Laws.certs.expired()))
    == True{} : Bool}

# "CA cert expiring does not trigger renewal"
law certs.expiring.ca_expiring:
  {Laws.certs.expiring(Laws.certs.set(Laws.certs.secret(Laws.certs.valid()), "ca.crt", Laws.certs.soon()))
    == False{} : Bool}

# "CA cert already expired does not trigger renewal"
law certs.expiring.ca_expired:
  {Laws.certs.expiring(
     Laws.certs.set(Laws.certs.set(Laws.certs.set(Laws.certs.set(Laws.certs.set(Laws.certs.secret(Laws.certs.valid()),
       "ca.crt", Laws.certs.expired()), "server-ca.crt", Laws.certs.expired()), "client-ca.crt", Laws.certs.expired()),
       "front-proxy-ca.crt", Laws.certs.expired()), "etcd-ca.crt", Laws.certs.expired()))
    == False{} : Bool}

# "leaf cert expiring while CA valid triggers renewal"
law certs.expiring.front_proxy_client:
  {Laws.certs.expiring(Laws.certs.set(Laws.certs.secret(Laws.certs.valid()), "front-proxy-client.crt", Laws.certs.soon()))
    == True{} : Bool}

# "missing leaf crt entry in secret data"
law certs.expiring.missing_leaf:
  {Laws.certs.expiring(Laws.certs.del(Laws.certs.secret(Laws.certs.valid()), "apiserver.crt")) == True{} : Bool}

# "missing CA crt entry does not trigger renewal"
law certs.expiring.missing_ca:
  {Laws.certs.expiring(Laws.certs.del(Laws.certs.secret(Laws.certs.valid()), "front-proxy-ca.crt")) == False{} : Bool}

# "invalid PEM data in leaf cert"
law certs.expiring.invalid_pem:
  {Laws.certs.expiring(Laws.certs.set(Laws.certs.secret(Laws.certs.valid()), "apiserver.crt", C.Unparsable{}))
    == True{} : Bool}

# "empty PEM data in leaf cert"
law certs.expiring.empty_pem:
  {Laws.certs.expiring(Laws.certs.set(Laws.certs.secret(Laws.certs.valid()), "apiserver.crt", C.Absent{}))
    == True{} : Bool}

# ensure_test.go TestIsCAFile.

law certs.is_ca_file.ca:
  {C.Certs.is_ca_file("ca.crt") == True{} : Bool}

law certs.is_ca_file.server_ca:
  {C.Certs.is_ca_file("server-ca.crt") == True{} : Bool}

law certs.is_ca_file.client_ca:
  {C.Certs.is_ca_file("client-ca.crt") == True{} : Bool}

law certs.is_ca_file.front_proxy_ca:
  {C.Certs.is_ca_file("front-proxy-ca.crt") == True{} : Bool}

law certs.is_ca_file.etcd_ca:
  {C.Certs.is_ca_file("etcd-ca.crt") == True{} : Bool}

law certs.is_ca_file.apiserver:
  {C.Certs.is_ca_file("apiserver.crt") == False{} : Bool}

law certs.is_ca_file.kubelet_client:
  {C.Certs.is_ca_file("apiserver-kubelet-client.crt") == False{} : Bool}

law certs.is_ca_file.etcd_client:
  {C.Certs.is_ca_file("apiserver-etcd-client.crt") == False{} : Bool}

law certs.is_ca_file.front_proxy_client:
  {C.Certs.is_ca_file("front-proxy-client.crt") == False{} : Bool}

law certs.is_ca_file.etcd_server:
  {C.Certs.is_ca_file("etcd-server.crt") == False{} : Bool}

law certs.is_ca_file.etcd_peer:
  {C.Certs.is_ca_file("etcd-peer.crt") == False{} : Bool}

law certs.is_ca_file.etcd_healthcheck:
  {C.Certs.is_ca_file("etcd-healthcheck-client.crt") == False{} : Bool}

# ensure_test.go TestWarnIfCAExpiring: the test checks that each call
# returns; the laws state what it warns about (CNs of CA certificates
# within 90 days).

def Laws.certs.ca_secret() -> +List<C.Entry>:
  Laws.certs.secret(Laws.certs.pem("valid-ca", 8860n))

law certs.warn.all_valid:
  {C.Certs.ca_expiring(Laws.certs.now(), Laws.certs.ca_secret()) == [] : +List<String>}

law certs.warn.ca_expiring:
  {C.Certs.ca_expiring(Laws.certs.now(),
     Laws.certs.set(Laws.certs.ca_secret(), "ca.crt", Laws.certs.pem("expiring-ca", 1540n)))
    == ["expiring-ca"] : +List<String>}

law certs.warn.ca_empty:
  {C.Certs.ca_expiring(Laws.certs.now(), Laws.certs.set(Laws.certs.ca_secret(), "ca.crt", C.Absent{}))
    == [] : +List<String>}

law certs.warn.ca_missing:
  {C.Certs.ca_expiring(Laws.certs.now(), Laws.certs.del(Laws.certs.ca_secret(), "ca.crt")) == [] : +List<String>}

# The warning text (warnIfCAExpiring's klog.Warningf).
law certs.warn.message:
  {C.Certs.ca_warning("kubernetes", "2036-11-05T10:00:00Z")
    == "CA certificate (CN=kubernetes) expires at 2036-11-05T10:00:00Z; run \"vcluster certs rotate-ca\" to renew" : String}

# ensure_test.go TestSplitCACertPreservesExistingAliases.
law certs.split_ca.preserves_aliases:
  {Laws.certs.aliases(C.Certs.run(C.Certs.split_ca_steps(),
     [ Laws.certs.fs("ca.crt", "ca"), Laws.certs.fs("ca.key", "ca-key"),
       Laws.certs.fs("server-ca.crt", "server-ca"), Laws.certs.fs("server-ca.key", "server-key"),
       Laws.certs.fs("client-ca.crt", "client-ca"), Laws.certs.fs("client-ca.key", "client-key") ]))
    == ["server-ca", "server-key", "client-ca", "client-key"] : +List<String>}

# ensure_test.go TestSplitCACertCreatesMissingAliases.
law certs.split_ca.creates_aliases:
  {Laws.certs.aliases(C.Certs.run(C.Certs.split_ca_steps(),
     [ Laws.certs.fs("ca.crt", "ca"), Laws.certs.fs("ca.key", "ca-key") ]))
    == ["ca", "ca-key", "ca", "ca-key"] : +List<String>}

# ensure_test.go TestEnsureAPIServerServingCertSignedByServerCA: with split
# CAs the API server certificate is made again, signed by server-ca, for
# the test's kubeadm configuration.
law certs.serving.split:
  {C.Certs.serving_steps(Laws.certs.test_cfg(), True{}) ==
    [ C.Remove{Laws.certs.p("apiserver.crt")}, C.Remove{Laws.certs.p("apiserver.key")},
      C.CreateCert{C.Spec{"apiserver", "kube-apiserver", [], "server-ca", [C.ServerAuth{}],
        ["test-node", "kubernetes", "kubernetes.default", "kubernetes.default.svc", "kubernetes.default.svc.cluster.local"],
        ["10.96.0.1", "127.0.0.1"], 365n}} ] : +List<C.Step>}

# equalFirstPEMCertificate(ca.crt, server-ca.crt): nothing to do.
law certs.serving.not_split:
  {C.Certs.serving_steps(Laws.certs.test_cfg(), False{}) == [] : +List<C.Step>}

# ensure_test.go TestGenerateCertificatesPreservesSplitCA: the API server
# certificate is signed by server-ca, the kubelet client certificate and
# the kubeconfigs' client certificates by ca, and the kubeconfigs trust
# server-ca.
law certs.generate.split:
  {C.Certs.generate_steps(Laws.certs.cfg(), True{}) ==
    Laws.certs.generated(
      [ C.Remove{Laws.certs.p("apiserver.crt")}, C.Remove{Laws.certs.p("apiserver.key")},
        C.CreateCert{Laws.certs.apiserver("server-ca")},
        C.TrustCA{Laws.certs.p("admin.conf"), Laws.certs.p("server-ca.crt")},
        C.TrustCA{Laws.certs.p("controller-manager.conf"), Laws.certs.p("server-ca.crt")},
        C.TrustCA{Laws.certs.p("scheduler.conf"), Laws.certs.p("server-ca.crt")} ]) : +List<C.Step>}

law certs.generate.not_split:
  {C.Certs.generate_steps(Laws.certs.cfg(), False{}) == Laws.certs.generated([]) : +List<C.Step>}

# ensure_test.go TestHasSplitClusterSigningCA.
law certs.split.same:
  {C.Certs.split_ca("server-ca", "server-ca") == False{} : Bool}

law certs.split.different:
  {C.Certs.split_ca("server-ca", "client-ca") == True{} : Bool}

# ensure_test.go TestEnsureKubeConfigTrustsCAClearsCAPath.
law certs.trust_ca.clears_path:
  {C.Certs.trust_ca(C.Cluster{"https://127.0.0.1:6443", "/old/ca.crt", "old-ca"}, "server-ca")
    == C.Cluster{"https://127.0.0.1:6443", "", "server-ca"} : C.Cluster}

# watcher_test.go TestCheckCertsExpiring_DiskValid.
law certs.disk.valid:
  {C.Certs.disk_expiring(Laws.certs.now(), Laws.certs.disk(Laws.certs.valid(), Laws.certs.valid(), Laws.certs.valid()))
    == False{} : Bool}

# watcher_test.go TestCheckCertsExpiring_DiskExpiring.
law certs.disk.expiring:
  {C.Certs.disk_expiring(Laws.certs.now(),
     Laws.certs.disk(Laws.certs.valid(), Laws.certs.valid(), Laws.certs.pem("expiring-cert", 1540n)))
    == True{} : Bool}

# watcher_test.go TestCheckCertsExpiring_DiskCAOnlyExpiring.
law certs.disk.ca_only:
  {C.Certs.disk_expiring(Laws.certs.now(),
     Laws.certs.disk(Laws.certs.valid(), Laws.certs.pem("expiring-ca", 1540n), Laws.certs.valid()))
    == False{} : Bool}

# watcher_test.go TestRolloutControlPlaneWithRetry_StatefulSet.
law certs.rollout.statefulset:
  {C.Certs.rollout_control_plane(True{}, False{}, "ns", "test", "ts-rollout")
    == C.PatchStatefulSet{"ns", "test", "vcluster.loft.sh/cert-rotation-at", "ts-rollout"} : C.Rollout}

# watcher_test.go TestRolloutControlPlaneWithRetry_DeploymentFallback.
law certs.rollout.deployment:
  {C.Certs.rollout_control_plane(False{}, True{}, "ns", "test", "deploy-rollout")
    == C.PatchDeployment{"ns", "test", "vcluster.loft.sh/cert-rotation-at", "deploy-rollout"} : C.Rollout}

# watcher_test.go TestRolloutDeployedEtcdWithRetry_NotFoundIsIgnored.
law certs.rollout.etcd_not_found:
  {C.Certs.rollout_etcd(False{}, "ns", "test", "etcd-rollout") == C.NoRollout{} : C.Rollout}

# From the Go code.

# certhelper.IsCertExpired: diffDays <= 90.
law certs.renewal.at_90_days:
  {C.Certs.needs_renewal(100n, 2260n) == True{} : Bool}

law certs.renewal.after_90_days:
  {C.Certs.needs_renewal(100n, 2261n) == False{} : Bool}

law certs.renewal.expired:
  {C.Certs.needs_renewal(100n, 76n) == True{} : Bool}

law certs.renew_hours:
  {C.Certs.renew_hours() == 2160n : Nat}

# DefaultCheckInterval = 24 * time.Hour; jitter up to interval / 10.
law certs.check_interval:
  {C.Certs.check_interval_s() == 86400 : U32}

law certs.jitter:
  {C.Certs.jitter_max_s() == 8640 : U32}

# certRotationExitDelayMin and certRotationExitDelayMax.
law certs.exit_delay:
  {[C.Certs.exit_delay_min_s(), C.Certs.exit_delay_max_s()] == [5, 300] : +List<U32>}

# kubeadm CertificateValidityPeriod and CACertificateValidityPeriod.
law certs.validity:
  {[C.Certs.leaf_days(), C.Certs.ca_days()] == [365n, 3650n] : +List<Nat>}

law certs.key_bits:
  {C.Certs.key_bits() == 2048 : U32}

# GetEtcdExtraSANs in standalone mode.
law certs.etcd_extra_sans:
  {C.Certs.etcd_extra_sans(["vc.example.com"]) == ["localhost", "127.0.0.1", "0.0.0.0", "vc.example.com"] : +List<String>}

# CreatePKIAssets for vcluster standalone's configuration.
law certs.plan:
  {C.Certs.plan(Laws.certs.cfg()) == Laws.certs.plan() : +List<C.Spec>}

# GetAPIServerAltNames for ensure_test.go's kubeadm configuration (no
# control-plane endpoint).
law certs.plan.test_config_apiserver:
  {C.Certs.apiserver(Laws.certs.test_cfg(), "ca") ==
    C.Spec{"apiserver", "kube-apiserver", [], "ca", [C.ServerAuth{}],
      ["test-node", "kubernetes", "kubernetes.default", "kubernetes.default.svc", "kubernetes.default.svc.cluster.local"],
      ["10.96.0.1", "127.0.0.1"], 365n} : C.Spec}

# The signed certificates' SANs (RemoveDuplicateAltNames: DNS names sorted
# without duplicates, IPs without duplicates).
law certs.final.apiserver_dns:
  {C.Certs.final_dns(Laws.certs.apiserver("ca")) ==
    ["kubernetes", "kubernetes.default", "kubernetes.default.svc", "kubernetes.default.svc.cluster.local", "my-vcluster"] : +List<String>}

law certs.final.apiserver_ips:
  {C.Certs.final_ips(Laws.certs.apiserver("ca")) == ["10.96.0.1", "127.0.0.1"] : +List<String>}

law certs.final.etcd_server_dns:
  {C.Certs.final_dns(Laws.certs.etcd_node("etcd/server")) == ["localhost", "my-vcluster"] : +List<String>}

law certs.final.etcd_server_ips:
  {C.Certs.final_ips(Laws.certs.etcd_node("etcd/server")) == ["127.0.0.1", "::1", "0.0.0.0"] : +List<String>}

# appendSANsToAltNames: IPs, DNS names and wildcards; anything else is
# left out.
law certs.sans.ips:
  {C.Certs.san_ips(["localhost", "127.0.0.1", "0.0.0.0", "::1", "*.my-vcluster-headless", "Bad_Name"])
    == ["127.0.0.1", "0.0.0.0", "::1"] : +List<String>}

law certs.sans.dns:
  {C.Certs.san_dns(["localhost", "127.0.0.1", "0.0.0.0", "::1", "*.my-vcluster-headless", "Bad_Name"])
    == ["localhost", "*.my-vcluster-headless"] : +List<String>}

# Only etcd's server and peer certificates name their CN in their SANs.
law certs.cn_in_san.plan:
  {C.Certs.cn_in_san_all(C.Certs.plan(Laws.certs.cfg()))
    == [False{}, False{}, False{}, False{}, False{}, False{}, True{}, True{}, False{}, False{}] : +List<Bool>}

# The kubeconfigs left in the PKI directory (admin.conf is the renamed
# super-admin.conf).
law certs.kubeconfigs:
  {C.Certs.kubeconfigs(Laws.certs.cfg()) ==
    [ Laws.certs.kc("admin.conf", "kubernetes-super-admin", ["system:masters"]),
      Laws.certs.kc("controller-manager.conf", "system:kube-controller-manager", []),
      Laws.certs.kc("scheduler.conf", "system:kube-scheduler", []) ] : +List<C.Kconf>}

law certs.kubeconfig.context:
  {C.Certs.context(Laws.certs.kc("admin.conf", "kubernetes-super-admin", ["system:masters"]))
    == "kubernetes-super-admin@my-vcluster" : String}

law certs.rewritten_kubeconfigs:
  {C.Certs.rewritten_kubeconfigs() ==
    [ "/var/lib/vcluster/pki/admin.conf", "/var/lib/vcluster/pki/controller-manager.conf",
      "/var/lib/vcluster/pki/scheduler.conf", "/var/lib/vcluster/kubeconfig.yaml" ] : +List<String>}

# certMap: the leaf certificates' secret keys and files, the CA
# certificates' secret keys.
law certs.leaf_secret_keys:
  {C.Certs.leaf_secret_keys() ==
    [ "apiserver.crt", "apiserver-etcd-client.crt", "apiserver-kubelet-client.crt", "front-proxy-client.crt",
      "etcd-healthcheck-client.crt", "etcd-peer.crt", "etcd-server.crt" ] : +List<String>}

law certs.leaf_files:
  {C.Certs.leaf_files() ==
    [ "apiserver.crt", "apiserver-etcd-client.crt", "apiserver-kubelet-client.crt", "front-proxy-client.crt",
      "etcd/healthcheck-client.crt", "etcd/peer.crt", "etcd/server.crt" ] : +List<String>}

law certs.ca_secret_keys:
  {C.Certs.ca_secret_keys() == ["ca.crt", "server-ca.crt", "client-ca.crt", "front-proxy-ca.crt", "etcd-ca.crt"] : +List<String>}

# removeFiles with excludeSAFiles and excludeCAFiles (leaf rotation): the
# kubeconfigs and the leaf certificates and keys go.
law certs.removed.leaf:
  {C.Certs.removed(C.Certs.files(), True{}) ==
    [ "admin.conf", "controller-manager.conf", "scheduler.conf",
      "apiserver.crt", "apiserver.key", "apiserver-etcd-client.crt", "apiserver-etcd-client.key",
      "apiserver-kubelet-client.crt", "apiserver-kubelet-client.key",
      "front-proxy-client.crt", "front-proxy-client.key",
      "etcd/healthcheck-client.crt", "etcd/healthcheck-client.key",
      "etcd/peer.crt", "etcd/peer.key", "etcd/server.crt", "etcd/server.key" ] : +List<String>}

# removeFiles with excludeSAFiles only (rotate-ca): all but sa.key, sa.pub.
law certs.removed.with_ca:
  {C.Certs.removed(C.Certs.files(), False{}) ==
    [ "admin.conf", "controller-manager.conf", "scheduler.conf",
      "apiserver.crt", "apiserver.key", "apiserver-etcd-client.crt", "apiserver-etcd-client.key",
      "apiserver-kubelet-client.crt", "apiserver-kubelet-client.key",
      "ca.crt", "ca.key", "server-ca.crt", "server-ca.key", "client-ca.crt", "client-ca.key",
      "front-proxy-ca.crt", "front-proxy-ca.key", "front-proxy-client.crt", "front-proxy-client.key",
      "etcd/ca.crt", "etcd/ca.key", "etcd/healthcheck-client.crt", "etcd/healthcheck-client.key",
      "etcd/peer.crt", "etcd/peer.key", "etcd/server.crt", "etcd/server.key" ] : +List<String>}

# EnsureCerts in standalone mode.
law certs.ensure.no_ca_key:
  {C.Certs.ensure_steps(False{}, True{}, Laws.certs.cfg(), False{}) == Laws.certs.generated([]) : +List<C.Step>}

law certs.ensure.expiring:
  {C.Certs.ensure_steps(True{}, True{}, Laws.certs.cfg(), False{}) ==
    (C.RemoveFiles{"/var/lib/vcluster/pki", True{}} <> Laws.certs.generated([])) : +List<C.Step>}

law certs.ensure.valid:
  {C.Certs.ensure_steps(True{}, False{}, Laws.certs.cfg(), False{}) == [] : +List<C.Step>}

# Rotate in standalone mode at Unix time 1794000000.
law certs.rotate.leaf:
  {C.Certs.rotation_steps(Laws.certs.cfg(), False{}, "1794000000", False{}) ==
    List.concat(&2, C.Step,
      [ [ C.Backup{"/var/lib/vcluster/pki", "/var/lib/vcluster/pki.bak/1794000000"},
          C.RemoveFiles{"/var/lib/vcluster/pki", True{}} ],
        Laws.certs.generated([]), Laws.certs.etcd_removals() ]) : +List<C.Step>}

law certs.rotate.with_ca:
  {C.Certs.rotation_steps(Laws.certs.cfg(), True{}, "1794000000", False{}) ==
    List.concat(&2, C.Step,
      [ [ C.Backup{"/var/lib/vcluster/pki", "/var/lib/vcluster/pki.bak/1794000000"},
          C.RemoveFiles{"/var/lib/vcluster/pki", False{}} ],
        Laws.certs.generated([]), Laws.certs.etcd_removals() ]) : +List<C.Step>}

# The cert watcher in standalone mode.
law certs.watcher.valid:
  {C.Certs.watcher_steps(False{}, Laws.certs.cfg(), "1794000000", False{}) == [] : +List<C.Step>}

law certs.watcher.expiring:
  {C.Certs.watcher_steps(True{}, Laws.certs.cfg(), "1794000000", False{}) ==
    List.concat(&2, C.Step,
      [ [ C.Backup{"/var/lib/vcluster/pki", "/var/lib/vcluster/pki.bak/1794000000"},
          C.RemoveFiles{"/var/lib/vcluster/pki", True{}} ],
        Laws.certs.generated([]), Laws.certs.etcd_removals(), [C.ExitAfter{5, 300}] ]) : +List<C.Step>}

# General laws.

# Renewal is monotone in time: once a certificate needs renewal, it needs
# it later too.
law certs.needs_renewal_monotone:
  for +now: Nat
  for +d: Nat
  for +not_after: Nat
  for h: {C.Certs.needs_renewal(now, not_after) == True{} : Bool}
  {C.Certs.needs_renewal(Nat.add(d, now), not_after) == True{} : Bool}

# etcd's server and peer certificates have their CN (the node name) among
# their DNS SANs, whatever the configuration, when the node name is set.
law certs.etcd_server_cn_in_san:
  for +c: C.Cfg
  for h: {String.is_empty(C.Certs.Cfg.name(c)) == False{} : Bool}
  {C.Certs.cn_in_san(C.Certs.etcd_server(c)) == True{} : Bool}

law certs.etcd_peer_cn_in_san:
  for +c: C.Cfg
  for h: {String.is_empty(C.Certs.Cfg.name(c)) == False{} : Bool}
  {C.Certs.cn_in_san(C.Certs.etcd_peer(c)) == True{} : Bool}
