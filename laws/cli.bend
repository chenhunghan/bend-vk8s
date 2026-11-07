import Base
import ../src/cli/cli.bend as C

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
