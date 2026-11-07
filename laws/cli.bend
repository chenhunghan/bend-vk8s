import Base
import ../src/cli/cli.bend as C
import ../src/guest/plan.bend as P

# Spec for src/cli/cli.bend: the vk8s command line (vcluster's
# `vcluster ... --driver docker` verbs) and the cluster LAN's names.

# Cli.parse: argv without the program name.

# `create NAME` with every default: port 0 (picked later), 2 CPUs,
# 2048 MiB, SQLite (vcluster standalone's default backing store), no
# worker VMs.
law cli.parse.create:
  {C.Cli.parse(["create", "demo"]) == C.Create{"demo", 0, 2, 2048, False{}, 0} : C.Cmd}

law cli.parse.create_nodes_etcd:
  {C.Cli.parse(["create", "demo", "--nodes", "2", "--backing-store", "etcd"])
    == C.Create{"demo", 0, 2, 2048, True{}, 2} : C.Cmd}

# A name that is not a DNS label is refused with help.
law cli.parse.create_bad_name:
  {C.Cli.parse(["create", "Bad_Name"])
    == C.Help{"invalid cluster name \"Bad_Name\": use lowercase letters, digits and '-' (at most 52)\n"} : C.Cmd}

# `vmm` hands every later word to bend-vmm unchanged.
law cli.parse.vmm:
  {C.Cli.parse(["vmm", "--mem", "512"]) == C.Vmm{["--mem", "512"]} : C.Cmd}

law cli.parse.list:
  {C.Cli.parse(["list"]) == C.List{} : C.Cmd}

# Cli.valid_name: a DNS label, as vcluster's name pattern
# ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ (config/config.go, Name), and at most 52
# characters (vk8s's limit).

law cli.valid_name.plain:
  {C.Cli.valid_name("demo") == True{} : Bool}

law cli.valid_name.one_char:
  {C.Cli.valid_name("a") == True{} : Bool}

law cli.valid_name.dashes_digits:
  {C.Cli.valid_name("my-vcluster-1") == True{} : Bool}

law cli.valid_name.leading_digit:
  {C.Cli.valid_name("1abc") == True{} : Bool}

law cli.valid_name.empty:
  {C.Cli.valid_name("") == False{} : Bool}

law cli.valid_name.upper_underscore:
  {C.Cli.valid_name("Bad_Name") == False{} : Bool}

law cli.valid_name.leading_dash:
  {C.Cli.valid_name("-demo") == False{} : Bool}

law cli.valid_name.trailing_dash:
  {C.Cli.valid_name("demo-") == False{} : Bool}

law cli.valid_name.dot:
  {C.Cli.valid_name("a.b") == False{} : Bool}

law cli.valid_name.len_52:
  {C.Cli.valid_name("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") == True{} : Bool}

law cli.valid_name.len_53:
  {C.Cli.valid_name("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") == False{} : Bool}

# Cli.lan_ip: the control plane is 10.10.0.2, worker i is 10.10.0.(2+i).

law cli.lan_ip.control_plane:
  {C.Cli.lan_ip(0) == "10.10.0.2" : String}

law cli.lan_ip.worker_1:
  {C.Cli.lan_ip(1) == "10.10.0.3" : String}

law cli.lan_ip.worker_2:
  {C.Cli.lan_ip(2) == "10.10.0.4" : String}

# Cli.worker_name: NAME-worker-i.

law cli.worker_name.first:
  {C.Cli.worker_name("demo", 1) == "demo-worker-1" : String}

law cli.worker_name.tenth:
  {C.Cli.worker_name("demo", 10) == "demo-worker-10" : String}

# vcluster's docker-driver commands (cmd/vclusterctl/cmd: list.go --output
# table|json, describe.go --config-only and --output/-o, connect.go
# "-- COMMAND", snapshot create NAME URL, restore NAME URL).

law cli.list.json:
  {C.Cli.parse(["list", "--output", "json"]) == C.ListJson{} : C.Cmd}

law cli.list.table:
  {C.Cli.parse(["list", "--output", "table"]) == C.List{} : C.Cmd}

law cli.describe.plain:
  {C.Cli.parse(["describe", "demo"]) == C.Describe{"demo", False{}, False{}} : C.Cmd}

law cli.describe.config_only:
  {C.Cli.parse(["describe", "demo", "--config-only"]) == C.Describe{"demo", True{}, False{}} : C.Cmd}

law cli.describe.json:
  {C.Cli.parse(["describe", "demo", "-o", "json"]) == C.Describe{"demo", False{}, True{}} : C.Cmd}

law cli.connect.exec:
  {C.Cli.parse(["connect", "demo", "--", "kubectl", "get", "ns"]) == C.Exec{"demo", ["kubectl", "get", "ns"]} : C.Cmd}

law cli.snapshot.file_url:
  {C.Cli.parse(["snapshot", "create", "demo", "file:///tmp/s.tar.gz"]) == C.Snapshot{"demo", "/tmp/s.tar.gz"} : C.Cmd}

law cli.restore.path:
  {C.Cli.parse(["restore", "demo2", "/tmp/s.tar.gz"]) == C.Restore{"demo2", "/tmp/s.tar.gz"} : C.Cmd}

law cli.logs.component:
  {C.Cli.parse(["logs", "demo", "kube-apiserver"]) == C.Logs{"demo", "kube-apiserver"} : C.Cmd}

# `list --output json`: json.MarshalIndent of vcluster's ListVCluster
# (expected text from running encoding/json on the same values).

law cli.list_json.one:
  {C.Cli.list_json([C.Entry{"demo", "running", 1000, "2026-11-07T16:00:00+08:00", True{}}], 1300)
   == "[\n    {\n        \"Created\": \"2026-11-07T16:00:00+08:00\",\n        \"Name\": \"demo\",\n        \"Namespace\": \"vk8s\",\n        \"Version\": \"\",\n        \"Status\": \"running\",\n        \"AgeSeconds\": 300,\n        \"Connected\": true\n    }\n]\n" : String}

law cli.list_json.empty:
  {C.Cli.list_json([], 1300) == "[]\n" : String}

# `list`: the AGE column is HumanDuration of now - created.
law cli.list_table.age:
  {C.Cli.list_table([C.Entry{"demo", "running", 1000, "", True{}}], 1300)
   == "  \n    \u{1b}[32mNAME\u{1b}[0m | \u{1b}[32mSTATUS \u{1b}[0m | \u{1b}[32mCONNECTED\u{1b}[0m | \u{1b}[32mAGE\u{1b}[0m  \n  -------+---------+-----------+------\n    demo | running | True      | 5m   \n  \n" : String}

# Socket paths (sockaddr_un.sun_path is 104 bytes on macOS, NUL included).

law cli.paths_fit.home:
  {C.Cli.paths_fit("/Users/chh/.vk8s/clusters/demo") == True{} : Bool}

law cli.paths_fit.edge:
  {C.Cli.paths_fit("/Users/chh/.vk8s/clusters/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") == True{} : Bool}

law cli.paths_fit.too_long:
  {C.Cli.paths_fit("/Users/chh/.vk8s/clusters/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") == False{} : Bool}

law cli.node_dir:
  {C.Cli.node_dir("/h/.vk8s/clusters/demo", 2) == "/h/.vk8s/clusters/demo/nodes/worker-2" : String}

# The image cache VM.

law cli.cache.start:
  {C.Cli.parse(["cache", "start"]) == C.Cache{"start"} : C.Cmd}

law cli.cache.bad:
  {C.Cli.parse(["cache", "go"]) == C.Help{"usage: vk8s cache start|stop|status\n"} : C.Cmd}

# One bend-vmm --forward value, every registry's port from the loopback.
law cli.cache_forwards:
  {C.Cli.cache_forwards(P.Plan.mirrors())
   == "127.0.0.1:15001:15001,127.0.0.1:15002:15002,127.0.0.1:15003:15003,127.0.0.1:15004:15004" : String}

# vcluster create --upgrade (cmd/vclusterctl/cmd/create.go: a bare flag,
# anywhere among the options).
law cli.create.upgrade:
  {C.Cli.parse(["create", "demo", "--upgrade", "--nodes", "2"]) == C.Upgrade{"demo", 0, 2, 2048, False{}, 2} : C.Cmd}

# Nodes (vcluster node delete NODE, --drain default true; vk8s node add).

law cli.node.add_default:
  {C.Cli.parse(["node", "add", "demo"]) == C.NodeAdd{"demo", 1} : C.Cmd}

law cli.node.add_count:
  {C.Cli.parse(["node", "add", "demo", "--count", "3"]) == C.NodeAdd{"demo", 3} : C.Cmd}

law cli.node.delete:
  {C.Cli.parse(["node", "delete", "demo", "demo-worker-2"]) == C.NodeDelete{"demo", "demo-worker-2", True{}} : C.Cmd}

law cli.node.delete_no_drain:
  {C.Cli.parse(["node", "delete", "demo", "demo-worker-2", "--drain=false"]) == C.NodeDelete{"demo", "demo-worker-2", False{}} : C.Cmd}

# Worker indices need not be dense: new ones go after the highest.
law cli.workers.next:
  {C.Cli.workers_next(C.Cli.workers_of("1 4"), 2) == [5, 6] : List<&2, U32>}

law cli.workers.drop:
  {C.Cli.workers_show(C.Cli.workers_drop(C.Cli.workers_of("1 2 4"), 2)) == "1 4" : String}

law cli.workers.upto:
  {C.Cli.workers_show(C.Cli.workers_upto(3)) == "1 2 3" : String}

law cli.worker_index:
  {C.Cli.worker_index("demo", "demo-worker-12") == Some{12} : Maybe<&2, U32>}

law cli.worker_index.other:
  {C.Cli.worker_index("demo", "demo") == None{} : Maybe<&2, U32>}

# Bootstrap tokens from the guest (security review F4), kubeadm's pattern
# [a-z0-9]{6}.[a-z0-9]{16}.

law cli.token_ok.valid:
  {C.Cli.token_ok("abcdef.0123456789abcdef") == True{} : Bool}

law cli.token_ok.shell:
  {C.Cli.token_ok("abcdef.0123456789abcde;") == False{} : Bool}

law cli.token_ok.short:
  {C.Cli.token_ok("abcde.0123456789abcdef") == False{} : Bool}

# vk8s node add's short-lived join token, encoded as kubeadm encodes a
# BootstrapToken (cmd/kubeadm/app/apis/bootstraptoken/v1 ToSecret, the
# cluster-bootstrap key names).
law cli.token_secret:
  {C.Cli.token_secret("abcdef", "0123456789abcdef", "2026-11-07T12:00:00Z")
   == "apiVersion: v1\nkind: Secret\nmetadata:\n  name: bootstrap-token-abcdef\n  namespace: kube-system\ntype: bootstrap.kubernetes.io/token\nstringData:\n  token-id: abcdef\n  token-secret: 0123456789abcdef\n  expiration: 2026-11-07T12:00:00Z\n  usage-bootstrap-authentication: \"true\"\n  usage-bootstrap-signing: \"true\"\n  auth-extra-groups: system:bootstrappers:kubeadm:default-node-token\n" : String}

# vcluster create --connect (default true; pkg/cli/flags/create/create.go)
# and --restore URL.
law cli.create.no_connect:
  {C.Cli.parse(["create", "demo", "--connect=false", "--nodes", "1"]) == C.NoConnect{C.Create{"demo", 0, 2, 2048, False{}, 1}} : C.Cmd}

law cli.create.connect_default:
  {C.Cli.parse(["create", "demo", "--nodes", "1"]) == C.Create{"demo", 0, 2, 2048, False{}, 1} : C.Cmd}

law cli.create.restore:
  {C.Cli.parse(["create", "demo", "--restore", "file:///tmp/s.tgz"]) == C.Restore{"demo", "/tmp/s.tgz"} : C.Cmd}

# Classic mode: vcluster's default host namespace is vcluster-NAME
# (pkg/cli/create_helm.go).
law cli.create.classic_default_ns:
  {C.Cli.parse(["create", "demo", "--host-kubeconfig", "/k"]) == C.Classic{C.Create{"demo", 0, 2, 2048, False{}, 0}, "/k", "vcluster-demo"} : C.Cmd}

law cli.create.classic_ns:
  {C.Cli.parse(["create", "demo", "--host-kubeconfig", "/k", "--host-namespace", "team-a"]) == C.Classic{C.Create{"demo", 0, 2, 2048, False{}, 0}, "/k", "team-a"} : C.Cmd}

# vcluster certs rotate NAME / certs check NAME.
law cli.certs.rotate:
  {C.Cli.parse(["certs", "rotate", "demo"]) == C.Certs{"rotate", "demo"} : C.Cmd}

law cli.certs.bad:
  {C.Cli.parse(["certs", "renew", "demo"]) == C.Help{"usage: vk8s certs rotate|check NAME\n"} : C.Cmd}

# vcluster node load-image NODE --archive F (--image needs Docker).
law cli.node.load_archive:
  {C.Cli.parse(["node", "load-image", "demo", "demo-worker-1", "--archive", "/tmp/app.tar"]) == C.NodeLoad{"demo", "demo-worker-1", "/tmp/app.tar"} : C.Cmd}

law cli.certs.rotate_ca:
  {C.Cli.parse(["certs", "rotate-ca", "demo"]) == C.Certs{"rotate-ca", "demo"} : C.Cmd}

# vcluster token create|list|delete (cmd/vclusterctl/cmd/token): --expires
# defaults to 1h; --kubeadm, --control-plane; list --output table|json.
law cli.token.create_default:
  {C.Cli.parse(["token", "create", "demo"]) == C.TokenCreate{"demo", "1h", False{}, False{}} : C.Cmd}

law cli.token.create_flags:
  {C.Cli.parse(["token", "create", "demo", "--expires", "24h", "--kubeadm"]) == C.TokenCreate{"demo", "24h", True{}, False{}} : C.Cmd}

law cli.token.list_json:
  {C.Cli.parse(["token", "list", "demo", "--output", "json"]) == C.TokenList{"demo", True{}} : C.Cmd}

law cli.token.delete:
  {C.Cli.parse(["token", "delete", "demo", "abcdef"]) == C.TokenDelete{"demo", "abcdef"} : C.Cmd}
