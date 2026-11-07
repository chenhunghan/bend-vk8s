import Base
import ../lib/sha256.bend as H

# Host-side names of virtual objects (vcluster pkg/util/translate).
# A Kubernetes name may hold at most 63 characters; longer names are cut to
# 52, followed by "-" and the first 10 hex digits of the SHA-256 of the full
# name, and every ".-" is then replaced by "-".

# vcluster SafeConcatName: join the parts with "-", shortened as above when
# the joined name is longer than 63 characters.
def Names.safe_concat(parts: +List<String>) -> String:
  ?TODO

# Single-namespace mode: the host name of virtual object `name` in virtual
# namespace `ns` of the vcluster `vc` is safe_concat([name, "x", ns, "x", vc]);
# the empty name stays empty.
def Names.host_name(name: String, ns: String, vc: String) -> String:
  ?TODO

# The host name of a cluster-scoped virtual object (vcluster HostNameCluster):
# safe_concat(["vcluster", name, "x", target_ns, "x", vc]); empty stays empty.
def Names.host_name_cluster(name: String, target_ns: String, vc: String) -> String:
  ?TODO

# The value of the vcluster.loft.sh/managed-by label on cluster-scoped host
# objects: safe_concat([target_ns, "x", vc]).
def Names.marker_cluster(target_ns: String, vc: String) -> String:
  ?TODO
