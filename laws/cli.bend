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

# vcluster create -f/--values FILE.
law cli.create.values:
  {C.Cli.parse(["create", "demo", "-f", "vcluster.yaml", "--nodes", "1"]) == C.WithValues{C.Create{"demo", 0, 2, 2048, False{}, 1}, "vcluster.yaml"} : C.Cmd}

# Proposed: classic mode's extra forwards (vk8s design, not vcluster's: the
# VM is outside the host network). Konnectivity's agent port and the fake
# kubelet sit on 13000.. and 16000.. at the API port's offset.
law cli.konn_port:
  {C.Cli.konn_port(10001) == 14001 : U32}
law cli.kubelet_port:
  {C.Cli.kubelet_port(12999) == 16999 : U32}
law cli.classic_forwards.on:
  {C.Cli.classic_forwards(True{}, 10001) == ",127.0.0.1:14001:8132,127.0.0.1:17001:10250" : String}
law cli.classic_forwards.off:
  for p: U32
  {C.Cli.classic_forwards(False{}, p) == "" : String}
law cli.konn_name:
  {C.Cli.konn_name("vc") == "vc-konnectivity" : String}


# Proposed: the standalone join server's forward (vk8s design, not
# vcluster's, which serves the API and /node/join on one port 8443). The
# guest's 8443 sits on host port 19000 plus the API port's offset in
# 10000..12999, so 19000..21999, clear of classic's 13000.. and 16000..
# ranges. The printed curl command is for nodes on the VM LAN.
law cli.join_port:
  {C.Cli.join_port(10001) == 20001 : U32}
law cli.join_port.low:
  {C.Cli.join_port(12000) == 19000 : U32}
law cli.join_port.high:
  {C.Cli.join_port(11999) == 21999 : U32}
law cli.forwards.standalone:
  {C.Cli.forwards(False{}, 10001) == "127.0.0.1:10001:6443,127.0.0.1:20001:8443" : String}
law cli.forwards.classic:
  {C.Cli.forwards(True{}, 10001) == "127.0.0.1:10001:6443,127.0.0.1:14001:8132,127.0.0.1:17001:10250" : String}
law cli.join_endpoint:
  {C.Cli.join_endpoint() == "10.10.0.2:8443" : String}
law cli.api_endpoint:
  {C.Cli.api_endpoint() == "10.10.0.2:6443" : String}

# Proposed: the opt-in open-format snapshot (docs/ref/snapshot-decisions.md
# D1, D3). Without --format, and with --format vm, `snapshot create` stays
# the VM-level snapshot (cli.snapshot.file_url above); --format open writes
# vcluster's archive (pkg/snapshot). Phase one reads and writes local
# files only: vcluster's other schemes (pkg/snapshot/options.go: oci, s3,
# container, https) are refused with an error that names the scheme.
# The messages are vk8s design.
law cli.snapshot.open:
  {C.Cli.parse(["snapshot", "create", "demo", "file:///tmp/s.tar.gz", "--format", "open"])
    == C.SnapshotOpen{"demo", "/tmp/s.tar.gz"} : C.Cmd}
law cli.snapshot.open_eq:
  {C.Cli.parse(["snapshot", "create", "demo", "/tmp/s.tar.gz", "--format=open"])
    == C.SnapshotOpen{"demo", "/tmp/s.tar.gz"} : C.Cmd}
law cli.snapshot.vm:
  {C.Cli.parse(["snapshot", "create", "demo", "file:///tmp/s.tar.gz", "--format", "vm"])
    == C.Snapshot{"demo", "/tmp/s.tar.gz"} : C.Cmd}
law cli.snapshot.bad_format:
  {C.Cli.parse(["snapshot", "create", "demo", "/tmp/s.tar.gz", "--format", "raw"])
    == C.Help{"vk8s snapshot: --format is open or vm, not \"raw\"\n"} : C.Cmd}
law cli.snapshot.format_no_value:
  {C.Cli.parse(["snapshot", "create", "demo", "/tmp/s.tar.gz", "--format"])
    == C.Help{"vk8s snapshot: --format needs a value\n"} : C.Cmd}
law cli.snapshot.unknown_option:
  {C.Cli.parse(["snapshot", "create", "demo", "/tmp/s.tar.gz", "--bogus"])
    == C.Help{"vk8s snapshot: unknown option --bogus\n"} : C.Cmd}
law cli.snapshot.s3:
  {C.Cli.parse(["snapshot", "create", "demo", "s3://bucket/key", "--format", "open"])
    == C.Help{"vk8s snapshot: s3:// is not supported yet (use a file path or file://)\n"} : C.Cmd}
law cli.snapshot.oci:
  {C.Cli.parse(["snapshot", "create", "demo", "oci://ghcr.io/me/snap:v1", "--format", "open"])
    == C.Help{"vk8s snapshot: oci:// is not supported yet (use a file path or file://)\n"} : C.Cmd}
law cli.snapshot.https:
  {C.Cli.parse(["snapshot", "create", "demo", "https://acct.blob.core.windows.net/c/s.tar.gz"])
    == C.Help{"vk8s snapshot: https:// is not supported yet (use a file path or file://)\n"} : C.Cmd}
law cli.snapshot.container:
  {C.Cli.parse(["snapshot", "create", "demo", "container:///data/s.tar.gz"])
    == C.Help{"vk8s snapshot: container:// is not supported yet (use a file path or file://)\n"} : C.Cmd}
# restore takes no --format (D2: it reads the archive's first entry).
law cli.restore.file_url:
  {C.Cli.parse(["restore", "demo2", "file:///tmp/s.tar.gz"]) == C.Restore{"demo2", "/tmp/s.tar.gz"} : C.Cmd}
law cli.restore.s3:
  {C.Cli.parse(["restore", "demo2", "s3://bucket/key"])
    == C.Help{"vk8s restore: s3:// is not supported yet (use a file path or file://)\n"} : C.Cmd}

# Proposed: vk8s assets prune [--dry-run] (vk8s design, docs/STATUS.md known
# divergences; vcluster has no equivalent). Of the dirs in ~/.vk8s/assets
# it removes release versions (scripts/release-assets.sh names them
# vK8S-HASH: "v", a digit, and "-" with 8 hex digits last) that are not the
# version this binary pins (Manifest.version), not the dir VK8S_ASSETS
# names, and not the assets of a running VM. Local builds (scripts/guest/
# build.sh installs v1.36.6, or dev) and download staging dirs (.fetch.*)
# stay.
law cli.assets.prune:
  {C.Cli.parse(["assets", "prune"]) == C.AssetsPrune{False{}} : C.Cmd}
law cli.assets.prune_dry_run:
  {C.Cli.parse(["assets", "prune", "--dry-run"]) == C.AssetsPrune{True{}} : C.Cmd}
law cli.assets.bad:
  {C.Cli.parse(["assets", "rm"]) == C.Help{"usage: vk8s assets prune [--dry-run]\n"} : C.Cmd}
law cli.assets_prune.superseded:
  {C.Cli.assets_prune(["v1.36.5-0a1b2c3d", "v1.36.6-69181a9a", "dev", ".fetch.Ab12Cd"], "v1.36.6-69181a9a", "", [])
    == ["v1.36.5-0a1b2c3d"] : +List<String>}
law cli.assets_prune.in_use:
  {C.Cli.assets_prune(["v1.36.5-0a1b2c3d", "v1.36.4-11112222"], "v1.36.6-69181a9a", "", ["v1.36.5-0a1b2c3d"])
    == ["v1.36.4-11112222"] : +List<String>}
law cli.assets_prune.override:
  {C.Cli.assets_prune(["v1.36.5-0a1b2c3d"], "v1.36.6-69181a9a", "v1.36.5-0a1b2c3d", []) == [] : +List<String>}
law cli.assets_prune.pinned_only:
  {C.Cli.assets_prune(["v1.36.6-69181a9a"], "v1.36.6-69181a9a", "", []) == [] : +List<String>}
law cli.assets_prune.local_build:
  {C.Cli.assets_prune(["v1.36.6", "v1.36.5-0a1b2c3d", "v1.36.5-0A1B2C3D"], "v1.36.6-69181a9a", "", []) == ["v1.36.5-0a1b2c3d"] : +List<String>}
# Proposed: memory give-back (vk8s design with bend-vmm e4b1bdf,
# docs/ref/footprint-decisions.md M1). Every VM, the control plane, the
# workers and the image cache, gets bend-vmm's virtio-balloon, after its
# other flags. Amended 2026-11-15 with the user's approval (was
# free-page-reporting): bend-vmm ea30ce3's automatic balloon (stats-driven
# inflate/deflate plus free page reporting), its default mode.
law cli.balloon_flags:
  {C.Cli.balloon_flags() == ["--balloon", "auto"] : +List<String>}
law cli.vmm_flags.balloon:
  {List.drop(&2, String, C.Cli.vmm_flags("/d", "/a", "demo", 10001, 2, 2048, False{}), 22n) == ["--balloon", "auto"] : +List<String>}
law cli.worker_flags.balloon:
  {List.drop(&2, String, C.Cli.worker_flags("/d", "/d/nodes/worker-1", "/a", "demo-worker-1", 1, "abcdef.0123456789abcdef", 2, 2048), 20n)
    == ["--balloon", "auto"] : +List<String>}
law cli.cache_flags.balloon:
  {List.drop(&2, String, C.Cli.cache_flags("/c", "/a"), 20n) == ["--balloon", "auto"] : +List<String>}
# Proposed: the snapshot decides the backing store (vk8s design,
# docs/ref/snapshot-decisions.md D15; vcluster has no equivalent). An open
# etcd archive restores into embedded etcd and a key/value archive into
# kine, and C.Restore carries no store. So `create --restore` and
# `restore` refuse --backing-store instead of ignoring it.
law cli.create.restore_backing_store:
  {C.Cli.parse(["create", "demo", "--restore", "/tmp/s.tgz", "--backing-store", "etcd"])
    == C.Help{"vk8s create: --backing-store cannot be combined with --restore; the snapshot decides the backing store\n"} : C.Cmd}
law cli.create.backing_store_restore:
  {C.Cli.parse(["create", "demo", "--backing-store", "sqlite", "--connect=false", "--restore", "file:///tmp/s.tgz"])
    == C.Help{"vk8s create: --backing-store cannot be combined with --restore; the snapshot decides the backing store\n"} : C.Cmd}
law cli.restore.backing_store:
  {C.Cli.parse(["restore", "demo2", "/tmp/s.tgz", "--backing-store", "etcd"])
    == C.Help{"vk8s restore: --backing-store cannot be combined with restore; the snapshot decides the backing store\n"} : C.Cmd}
# Proposed: portable host copies (docs/ref/explore-linux-hosts.md, Phase 1
# and D3; vcluster has no equivalent). One copy-on-write copy for disk
# images and archives, run as cp with an argument list (no shell): GNU cp
# first, which reflinks where the file system can and keeps holes; BSD cp
# rejects --reflink, so macOS then clones with APFS cp -c as before.
law cli.clone_gnu.args:
  {C.Cli.clone_gnu("/a b/data.img", "/d/data.img")
    == ["--reflink=auto", "--sparse=always", "/a b/data.img", "/d/data.img"] : +List<String>}
law cli.clone_bsd.args:
  {C.Cli.clone_bsd("/a b/data.img", "/d/data.img") == ["-c", "/a b/data.img", "/d/data.img"] : +List<String>}
# Proposed: dates are rendered in Bend (no BSD `date -r` or `date -v`). A
# bootstrap token of `node add` expires one hour after now, in time.RFC3339
# UTC. Expected values are Go's reference time (time package docs: Unix
# 1136239445 is "Mon Jan 2 15:04:05 MST 2006", MST = -0700).
law cli.rfc3339_in_one_hour:
  {C.Cli.rfc3339_in_one_hour(1136239445) == "2006-01-02T23:04:05Z" : String}
# describe's Created line (vcluster pkg/cli/describe_docker.go:41,
# time.RFC1123Z = "Mon, 02 Jan 2006 15:04:05 -0700"), in the zone that
# `date +%z` prints.
law cli.created_text:
  {C.Cli.rfc1123z(1136239445, "-0700") == "Mon, 02 Jan 2006 15:04:05 -0700" : String}
law cli.created_text.utc:
  {C.Cli.rfc1123z(1136239445, "+0000") == "Mon, 02 Jan 2006 22:04:05 +0000" : String}
# list's Created (time.RFC3339 = "2006-01-02T15:04:05Z07:00": Z when the
# offset is zero).
law cli.created_rfc3339:
  {C.Cli.rfc3339_in(1136239445, "-0700") == "2006-01-02T15:04:05-07:00" : String}
law cli.created_rfc3339.utc:
  {C.Cli.rfc3339_in(1136239445, "+0000") == "2006-01-02T22:04:05Z" : String}
# A cluster without CREATED takes its directory's birth time: GNU stat
# first (BSD stat rejects -c), then BSD stat -f %B.
law cli.created_sh.gnu_first:
  {String.contains(C.Cli.created_sh(), "c=$(stat -c %W \"$d\" 2>/dev/null) || c=$(stat -f %B \"$d\")") == True{} : Bool}
# Proposed: a preflight names every missing host tool (D4 a: nc from
# netcat-openbsd), and /dev/kvm for the VM backend on Linux.
law cli.preflight.names_missing:
  {C.Cli.preflight(["nc", "kubectl", "/dev/kvm"])
    == "vk8s: missing on this host: nc (netcat-openbsd: vk8s uses nc -U), kubectl, /dev/kvm (read and write access: sudo usermod -aG kvm \"$USER\", then log in again)\n" : String}
law cli.preflight.none:
  {C.Cli.preflight([]) == "" : String}
# The preflight runs in Bend, with no shell: each tool is looked up in
# every PATH entry (an empty entry is the current directory, as POSIX
# says), and /dev/kvm must open for reading and writing on Linux only
# (/proc/sys/kernel/ostype reads "Linux"; macOS has no /proc and uses
# Hypervisor.framework).
law cli.preflight_tools:
  {C.Cli.preflight_tools() == ["nc", "curl", "kubectl", "tar"] : +List<String>}
law cli.path_candidates:
  {C.Cli.path_candidates("/usr/local/bin::/usr/bin", "nc")
    == ["/usr/local/bin/nc", "./nc", "/usr/bin/nc"] : +List<String>}
law cli.kvm_needed.linux:
  {C.Cli.kvm_needed(True{}, "Linux\n") == True{} : Bool}
law cli.kvm_needed.macos:
  {C.Cli.kvm_needed(True{}, "") == False{} : Bool}
law cli.kvm_needed.no_vm:
  {C.Cli.kvm_needed(False{}, "Linux\n") == False{} : Bool}
# Proposed: per-role asset sets (docs/ref/footprint-decisions.md D1). With
# a per-role assets dir, each VM's --disk is base.img (/dev/vda), its data
# disk (/dev/vdb), then one read-only, nocache disk per set of its role,
# and its kernel command line names the sets (VK8S_SETS) in that order.
# The flag count before --balloon stays as cli.*_flags.balloon pin it.
law cli.disks_v3:
  {C.Cli.disks_v3("/a", "/d/data.img", ["node", "control-plane"])
    == "/a/base.img:ro:nocache,/d/data.img,/a/node.img:ro:nocache,/a/control-plane.img:ro:nocache" : String}
law cli.sets_word:
  {C.Cli.sets_word(["node", "control-plane"]) == " VK8S_SETS=node,control-plane" : String}
law cli.role_flags.off:
  for f: +List<String>
  for a: String
  for d: String
  for s: +List<String>
  {C.Cli.role_flags(False{}, f, a, d, s) == f : +List<String>}
law cli.role_flags.worker_disk:
  {List.take(&2, String, List.drop(&2, String, C.Cli.role_flags(True{},
      C.Cli.worker_flags("/d", "/d/nodes/worker-1", "/a", "demo-worker-1", 1, "abcdef.0123456789abcdef", 2, 2048),
      "/a", "/d/nodes/worker-1/data.img", ["node"]), 4n), 2n)
    == ["--disk", "/a/base.img:ro:nocache,/d/nodes/worker-1/data.img,/a/node.img:ro:nocache"] : +List<String>}
law cli.role_flags.worker_cmdline:
  {List.drop(&2, String, C.Cli.role_flags(True{},
      C.Cli.worker_flags("/d", "/d/nodes/worker-1", "/a", "demo-worker-1", 1, "abcdef.0123456789abcdef", 2, 2048),
      "/a", "/d/nodes/worker-1/data.img", ["node"]), 18n)
    == ["--cmdline", "console=ttyAMA0 quiet panic=5 VK8S_ROLE=worker VK8S_NAME=demo-worker-1 VK8S_NODE_IP=10.10.0.3 VK8S_TOKEN=abcdef.0123456789abcdef VK8S_SETS=node",
        "--balloon", "auto"] : +List<String>}
law cli.role_flags.cache:
  {List.drop(&2, String, C.Cli.role_flags(True{}, C.Cli.cache_flags("/c", "/a"), "/a", "/c/data.img", ["cache"]), 18n)
    == ["--cmdline", "console=ttyAMA0 quiet panic=5 VK8S_ROLE=cache VK8S_NAME=vk8s-cache VK8S_SETS=cache", "--balloon", "auto"] : +List<String>}
law cli.role_flags.vmm_balloon:
  {List.drop(&2, String, C.Cli.role_flags(True{}, C.Cli.vmm_flags("/d", "/a", "demo", 10001, 2, 2048, False{}), "/a", "/d/data.img",
      ["node", "control-plane"]), 22n) == ["--balloon", "auto"] : +List<String>}
law cli.cp_role.classic:
  {C.Cli.cp_role(" VK8S_MODE=classic VK8S_HOST_NAMESPACE=vcluster-demo") == "classic" : String}
law cli.cp_role.standalone:
  {C.Cli.cp_role("") == "standalone" : String}
