import Base
import ../src/translate/names.bend as N

# Frozen spec for src/translate/names.bend (vcluster pkg/util/translate).
# Expected values were computed with vcluster's Go code.

law names.short_joins:
  {N.Names.host_name("nginx", "default", "my-vcluster") == "nginx-x-default-x-my-vcluster" : String}

law names.empty_stays_empty:
  {N.Names.host_name("", "default", "my-vcluster") == "" : String}

law names.long_is_hashed:
  {N.Names.host_name("a-very-long-deployment-name-0123456789-abcdef", "some-long-namespace-name", "vcluster")
    == "a-very-long-deployment-name-0123456789-abcdef-x-some-9eb53ab8ff" : String}

law names.dot_dash_collapses:
  {N.Names.safe_concat(["name.with.dots.and.it.is.quite.long.for.a.label.yes.long.enough-x"])
    == "name.with.dots.and.it.is.quite.long.for.a.label.yes-8f49fc3eb7" : String}

law names.cluster_scoped:
  {N.Names.host_name_cluster("standard", "vcluster-ns", "vcluster") == "vcluster-standard-x-vcluster-ns-x-vcluster" : String}

law names.marker_cluster:
  {N.Names.marker_cluster("vcluster-ns", "vcluster") == "vcluster-ns-x-vcluster" : String}

law names.root_ca:
  {N.Names.safe_concat(["vcluster", "kube-root-ca.crt", "x", "vcluster"]) == "vcluster-kube-root-ca.crt-x-vcluster" : String}

# General laws.

# Every name safe_concat makes is a valid Kubernetes name length.
law names.at_most_63:
  for parts: +List<String>
  {Nat.is_le(String.length(N.Names.safe_concat(parts)), 63n) == True{} : Bool}

law names.single_part_short:
  for s: String
  for h: {Nat.is_le(String.length(s), 63n) == True{} : Bool}
  {N.Names.safe_concat([s]) == s : String}
