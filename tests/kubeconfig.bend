import Base
import ../src/cli/kubeconfig.bend as K

# Scenario tests for src/cli/kubeconfig.bend: the YAML subset round-trips.
# Each line prints PASS or FAIL.

def T.line(+name: String, ok: Bool) -> String:
  match ok:
    case True{}:
      "PASS " ++ name
    case False{}:
      "FAIL " ++ name

def T.done(r: Result<&2, &2, String, String>) -> String:
  match r:
    case Done{s}:
      s
    case Fail{e}:
      "error: " ++ e

def T.failed(r: Result<&2, &2, String, String>) -> Bool:
  match r:
    case Done{s}:
      False{}
    case Fail{e}:
      True{}

def T.has(+name: String, +out: String, +part: String) -> String:
  T.line(name, String.contains(out, part))

def T.eq(+name: String, +got: String, +want: String) -> String:
  T.line(name, String.eq(got, want))

# A vCluster kubeconfig with a bool, a quoted number, an exec plugin and a
# context namespace.
def T.incoming() -> String:
  "apiVersion: v1\nclusters:\n- cluster:\n    insecure-skip-tls-verify: true\n    server: https://127.0.0.1:10443\n  name: x\n"
  ++ "contexts:\n- context:\n    cluster: x\n    namespace: team-a\n    user: y\n  name: x\n"
  ++ "current-context: x\nkind: Config\npreferences: {}\n"
  ++ "users:\n- name: y\n  user:\n    exec:\n      apiVersion: client.authentication.k8s.io/v1\n      args:\n      - get-token\n      - --name\n      command: tok\n    token: \"123\"\n"

def main() -> IO(Unit):
  do IO<Unit>:
    +merged : String = T.done(K.Kubeconfig.merge("", T.incoming(), "vk8s_x", True{}))
    +printed : String = T.done(K.Kubeconfig.rename(T.incoming(), "vk8s_x"))
    IO.print(T.has("bool stays a bool", merged, "    insecure-skip-tls-verify: true\n"))
    IO.print(T.has("quoted number stays quoted", merged, "    token: \"123\"\n"))
    IO.print(T.has("exec args as a block list", merged, "      args:\n      - get-token\n      - \"--name\"\n"))
    IO.print(T.has("merge makes a fresh context", merged, "- context:\n    cluster: vk8s_x\n    user: vk8s_x\n  name: vk8s_x\n"))
    IO.print(T.has("print keeps the context namespace", printed, "    cluster: vk8s_x\n    namespace: team-a\n    user: vk8s_x\n"))
    IO.print(T.eq("merge twice is merge once", T.done(K.Kubeconfig.merge(merged, T.incoming(), "vk8s_x", True{})), merged))
    IO.print(T.eq("remove after merge into nothing is empty",
      T.done(K.Kubeconfig.remove(merged, "vk8s_x")),
      "apiVersion: v1\nclusters: null\ncontexts: null\ncurrent-context: \"\"\nkind: Config\npreferences: {}\nusers: null\n"))
    IO.print(T.line("a YAML list is not a kubeconfig", T.failed(K.Kubeconfig.merge("- a\n- b\n", T.incoming(), "vk8s_x", True{}))))
    IO.print(T.eq("plain string", K.Kubeconfig.str("vk8s_x"), "vk8s_x"))
    IO.print(T.eq("empty string quoted", K.Kubeconfig.str(""), "\"\""))
    IO.print(T.eq("bool word quoted", K.Kubeconfig.str("true"), "\"true\""))
    IO.print(T.eq("number quoted", K.Kubeconfig.str("1.5"), "\"1.5\""))
    IO.print(T.eq("space quoted", K.Kubeconfig.str("a b"), "\"a b\""))
    IO.print(T.eq("trailing colon quoted", K.Kubeconfig.str("x:"), "\"x:\""))
    IO.print(T.eq("target skips empty entries", K.Kubeconfig.target(":/tmp/b", "/h"), "/tmp/b"))
