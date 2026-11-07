import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/cli/kubeconfig.bend as K

# Spec for src/cli/kubeconfig.bend: `vk8s connect` and `vk8s delete
# --delete-context` on a kubeconfig (vcluster pkg/cli/connect_docker.go,
# pkg/cli/connect_helm.go writeKubeConfig, pkg/util/clihelper
# UpdateKubeConfig, pkg/cli/delete_helm.go deleteContext).

# Fixtures
# --------

# TestExchangeContextName's config (pkg/cli/connect_helm_test.go) with
# every name set to n: cluster {server: foo}, user {token: foo}, a context
# pointing at both, current-context n.
def kubeconfig.fx.go(+n: String) -> K.Kc:
  K.Kc{[K.Ent{n, J.JObj{J.JMem{"server", J.JStr{"foo"}, J.JNil{}}}}],
    [K.Ent{n, J.JObj{J.JMem{"cluster", J.JStr{n}, J.JMem{"user", J.JStr{n}, J.JNil{}}}}}],
    [K.Ent{n, J.JObj{J.JMem{"token", J.JStr{"foo"}, J.JNil{}}}}], n, J.JObj{J.JNil{}}}

# The kubeconfig a vk8s guest publishes (kubeadm's super-admin.conf with
# the server and context rewritten by Plan.publish).
def kubeconfig.fx.incoming() -> String:
  "apiVersion: v1\nclusters:\n- cluster:\n    certificate-authority-data: Q0E=\n    server: https://127.0.0.1:10443\n  name: demo\n"
  ++ "contexts:\n- context:\n    cluster: demo\n    user: kubernetes-super-admin\n  name: vk8s_demo\n"
  ++ "current-context: vk8s_demo\nkind: Config\npreferences: {}\n"
  ++ "users:\n- name: kubernetes-super-admin\n  user:\n    client-certificate-data: Q0VSVA==\n    client-key-data: S0VZ\n"

# The same, as clientcmd.Write prints it after vcluster's rename to vk8s_demo.
def kubeconfig.fx.demo() -> String:
  "apiVersion: v1\nclusters:\n- cluster:\n    certificate-authority-data: Q0E=\n    server: https://127.0.0.1:10443\n  name: vk8s_demo\n"
  ++ "contexts:\n- context:\n    cluster: vk8s_demo\n    user: vk8s_demo\n  name: vk8s_demo\n"
  ++ "current-context: vk8s_demo\nkind: Config\npreferences: {}\n"
  ++ "users:\n- name: vk8s_demo\n  user:\n    client-certificate-data: Q0VSVA==\n    client-key-data: S0VZ\n"

# clientcmd.Write of clientcmdapi.NewConfig().
def kubeconfig.fx.empty() -> String:
  "apiVersion: v1\nclusters: null\ncontexts: null\ncurrent-context: \"\"\nkind: Config\npreferences: {}\nusers: null\n"

# A user's kubeconfig with one other cluster (kind's).
def kubeconfig.fx.kind() -> String:
  "apiVersion: v1\nclusters:\n- cluster:\n    server: https://127.0.0.1:6443\n  name: kind-kind\n"
  ++ "contexts:\n- context:\n    cluster: kind-kind\n    user: kind-kind\n  name: kind-kind\n"
  ++ "current-context: kind-kind\nkind: Config\npreferences: {}\n"
  ++ "users:\n- name: kind-kind\n  user:\n    token: abc\n"

# kind's kubeconfig after connect, current-context set or not.
def kubeconfig.fx.both(+cur: String) -> String:
  "apiVersion: v1\nclusters:\n- cluster:\n    server: https://127.0.0.1:6443\n  name: kind-kind\n"
  ++ "- cluster:\n    certificate-authority-data: Q0E=\n    server: https://127.0.0.1:10443\n  name: vk8s_demo\n"
  ++ "contexts:\n- context:\n    cluster: kind-kind\n    user: kind-kind\n  name: kind-kind\n"
  ++ "- context:\n    cluster: vk8s_demo\n    user: vk8s_demo\n  name: vk8s_demo\n"
  ++ "current-context: " ++ cur ++ "\nkind: Config\npreferences: {}\n"
  ++ "users:\n- name: kind-kind\n  user:\n    token: abc\n"
  ++ "- name: vk8s_demo\n  user:\n    client-certificate-data: Q0VSVA==\n    client-key-data: S0VZ\n"

# An older vk8s_demo (another port and token) before kind's entries.
def kubeconfig.fx.stale() -> String:
  "apiVersion: v1\nclusters:\n- cluster:\n    server: https://127.0.0.1:10001\n  name: vk8s_demo\n"
  ++ "- cluster:\n    server: https://127.0.0.1:6443\n  name: kind-kind\n"
  ++ "contexts:\n- context:\n    cluster: vk8s_demo\n    user: vk8s_demo\n  name: vk8s_demo\n"
  ++ "- context:\n    cluster: kind-kind\n    user: kind-kind\n  name: kind-kind\n"
  ++ "current-context: kind-kind\nkind: Config\npreferences: {}\n"
  ++ "users:\n- name: vk8s_demo\n  user:\n    token: old\n"
  ++ "- name: kind-kind\n  user:\n    token: abc\n"

# Two contexts a and b that share the user admin.
def kubeconfig.fx.shared() -> String:
  "apiVersion: v1\nclusters:\n- cluster:\n    server: https://a:6443\n  name: a\n"
  ++ "- cluster:\n    server: https://b:6443\n  name: b\n"
  ++ "contexts:\n- context:\n    cluster: a\n    user: admin\n  name: a\n"
  ++ "- context:\n    cluster: b\n    user: admin\n  name: b\n"
  ++ "current-context: a\nkind: Config\npreferences: {}\n"
  ++ "users:\n- name: admin\n  user:\n    token: abc\n"

# fx.shared after deleteContext of a.
def kubeconfig.fx.shared_b() -> String:
  "apiVersion: v1\nclusters:\n- cluster:\n    server: https://b:6443\n  name: b\n"
  ++ "contexts:\n- context:\n    cluster: b\n    user: admin\n  name: b\n"
  ++ "current-context: b\nkind: Config\npreferences: {}\n"
  ++ "users:\n- name: admin\n  user:\n    token: abc\n"

# TestExchangeContextName (pkg/cli/connect_helm_test.go)
# --------------------------------------------------------

# "KubeConfigContextName specified"
law kubeconfig.exchange_specified:
  {K.Kubeconfig.renamed(kubeconfig.fx.go("my-vcluster"), "new-context")
    == Done{kubeconfig.fx.go("new-context")} : Result<&2, &2, String, K.Kc>}

# "KubeConfigContextName same as default"
law kubeconfig.exchange_same_name:
  {K.Kubeconfig.renamed(kubeconfig.fx.go("my-vcluster"), "my-vcluster")
    == Done{kubeconfig.fx.go("my-vcluster")} : Result<&2, &2, String, K.Kc>}

# connect (connect_docker.go, writeKubeConfig, clihelper.UpdateKubeConfig)
# ------------------------------------------------------------------------

law kubeconfig.context_name:
  {K.Kubeconfig.context_name("demo") == "vk8s_demo" : String}

# --print: the renamed kubeconfig.
law kubeconfig.print_renames:
  {K.Kubeconfig.rename(kubeconfig.fx.incoming(), "vk8s_demo") == Done{kubeconfig.fx.demo()} : Result<&2, &2, String, String>}

# No ~/.kube/config yet.
law kubeconfig.merge_into_missing:
  {K.Kubeconfig.merge("", kubeconfig.fx.incoming(), "vk8s_demo", True{})
    == Done{kubeconfig.fx.demo()} : Result<&2, &2, String, String>}

law kubeconfig.merge_into_empty:
  {K.Kubeconfig.merge(kubeconfig.fx.empty(), kubeconfig.fx.incoming(), "vk8s_demo", True{})
    == Done{kubeconfig.fx.demo()} : Result<&2, &2, String, String>}

# Other contexts are kept, in order.
law kubeconfig.merge_keeps_others:
  {K.Kubeconfig.merge(kubeconfig.fx.kind(), kubeconfig.fx.incoming(), "vk8s_demo", True{})
    == Done{kubeconfig.fx.both("vk8s_demo")} : Result<&2, &2, String, String>}

# --update-current=false leaves current-context alone.
law kubeconfig.merge_current_untouched:
  {K.Kubeconfig.merge(kubeconfig.fx.kind(), kubeconfig.fx.incoming(), "vk8s_demo", False{})
    == Done{kubeconfig.fx.both("kind-kind")} : Result<&2, &2, String, String>}

# Entries of the same name are replaced.
law kubeconfig.merge_replaces_same_name:
  {K.Kubeconfig.merge(kubeconfig.fx.stale(), kubeconfig.fx.incoming(), "vk8s_demo", True{})
    == Done{kubeconfig.fx.both("vk8s_demo")} : Result<&2, &2, String, String>}

# writeKubeConfig: "nil clusterConfig" / "nil authConfig".
law kubeconfig.merge_needs_entries:
  {K.Kubeconfig.merge("", "", "vk8s_demo", True{})
    == Fail{"kubeconfig is missing required fields"} : Result<&2, &2, String, String>}

# clientcmd's default filename.
law kubeconfig.target_default:
  {K.Kubeconfig.target("", "/Users/me") == "/Users/me/.kube/config" : String}

law kubeconfig.target_first:
  {K.Kubeconfig.target("/tmp/a:/tmp/b", "/Users/me") == "/tmp/a" : String}

# delete --delete-context (delete_docker.go deleteKubeContext, deleteContext)
# --------------------------------------------------------------------------

# The context goes with its unshared user and cluster; the first other
# context becomes current.
law kubeconfig.remove_restores:
  {K.Kubeconfig.remove(kubeconfig.fx.both("vk8s_demo"), "vk8s_demo")
    == Done{kubeconfig.fx.kind()} : Result<&2, &2, String, String>}

# "Kube context %s not found, nothing to delete".
law kubeconfig.remove_absent_unchanged:
  {K.Kubeconfig.remove(kubeconfig.fx.kind(), "vk8s_demo")
    == Done{kubeconfig.fx.kind()} : Result<&2, &2, String, String>}

law kubeconfig.remove_last:
  {K.Kubeconfig.remove(kubeconfig.fx.demo(), "vk8s_demo")
    == Done{kubeconfig.fx.empty()} : Result<&2, &2, String, String>}

# A user that another context uses stays.
law kubeconfig.remove_keeps_shared_user:
  {K.Kubeconfig.remove(kubeconfig.fx.shared(), "a")
    == Done{kubeconfig.fx.shared_b()} : Result<&2, &2, String, String>}

# General laws.
# -------------

# The result of a merge always holds the named context.
law kubeconfig.merge_has_context:
  for kc: K.Kc
  for +n: String
  for cl: J.Json
  for u: J.Json
  for set: Bool
  {K.Kubeconfig.has(K.Kubeconfig.contexts(K.Kubeconfig.upsert(kc, n, cl, u, set)), n) == True{} : Bool}

law kubeconfig.merge_sets_current:
  for kc: K.Kc
  for +n: String
  for cl: J.Json
  for u: J.Json
  {K.Kubeconfig.current(K.Kubeconfig.upsert(kc, n, cl, u, True{})) == n : String}

law kubeconfig.merge_keeps_current:
  for +kc: K.Kc
  for +n: String
  for cl: J.Json
  for u: J.Json
  {K.Kubeconfig.current(K.Kubeconfig.upsert(kc, n, cl, u, False{})) == K.Kubeconfig.current(kc) : String}

# Merge, then remove, of a fresh name (no cluster, context or user of that
# name, and no context pointing at a cluster or user of that name) gives
# back the existing entries.
law kubeconfig.merge_then_remove_fresh:
  for +cls: List<&2, K.Ent>
  for +ctxs: List<&2, K.Ent>
  for +us: List<&2, K.Ent>
  for cur: String
  for pr: J.Json
  for +n: String
  for +cl: J.Json
  for +u: J.Json
  for set: Bool
  for h1: {K.Kubeconfig.has(cls, n) == False{} : Bool}
  for h2: {K.Kubeconfig.has(ctxs, n) == False{} : Bool}
  for h3: {K.Kubeconfig.has(us, n) == False{} : Bool}
  for h4: {K.Kubeconfig.refs(ctxs, "cluster", n) == False{} : Bool}
  for h5: {K.Kubeconfig.refs(ctxs, "user", n) == False{} : Bool}
  {K.Kubeconfig.entries(K.Kubeconfig.unset(K.Kubeconfig.upsert(K.Kc{cls, ctxs, us, cur, pr}, n, cl, u, set), n))
    == K.Ents{cls, ctxs, us} : K.Ents}

# The guest boundary (security review F1): a guest-written kubeconfig is
# never used as is.

def Laws.kubeconfig.hostile() -> String:
  "apiVersion: v1\nkind: Config\nclusters:\n- name: x\n  cluster:\n    server: https://evil.example:443\n    insecure-skip-tls-verify: true\n    certificate-authority-data: QUJD\n"
  ++ "users:\n- name: x\n  user:\n    client-certificate-data: REVG\n    client-key-data: R0hJ\n    exec:\n      command: /bin/sh\n      args:\n      - -c\n      - id\n"
  ++ "contexts:\n- name: x\n  context:\n    cluster: x\n    user: x\ncurrent-context: x\n"

def Laws.kubeconfig.exec_only() -> String:
  "apiVersion: v1\nkind: Config\nclusters:\n- name: x\n  cluster:\n    server: https://10.0.2.15:6443\n    certificate-authority-data: QUJD\n"
  ++ "users:\n- name: x\n  user:\n    exec:\n      command: /bin/sh\n"
  ++ "contexts:\n- name: x\n  context:\n    cluster: x\n    user: x\ncurrent-context: x\n"

# The server, the TLS check, the exec plugin and every other field of the
# guest's file are dropped: only the three certificates are kept.
law kubeconfig.sanitize.drops_hostile_fields:
  {K.Kubeconfig.sanitize(Laws.kubeconfig.hostile(), "https://127.0.0.1:12000", "vk8s_demo")
   == Done{K.Kubeconfig.host_owned("https://127.0.0.1:12000", "QUJD", "REVG", "R0hJ", "vk8s_demo")} : Result<&2, &2, String, String>}

# A user with no embedded client certificate (an exec plugin instead) is refused.
law kubeconfig.sanitize.refuses_exec_user:
  {K.Kubeconfig.sanitize(Laws.kubeconfig.exec_only(), "https://127.0.0.1:12000", "vk8s_demo")
   == Fail{"the guest's kubeconfig lacks valid embedded certificates"} : Result<&2, &2, String, String>}
