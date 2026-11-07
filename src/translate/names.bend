import Base
import ../lib/sha256.bend as H

# Host-side names of virtual objects (vcluster pkg/util/translate).
# A Kubernetes name may hold at most 63 characters; longer names are cut to
# 52, followed by "-" and the first 10 hex digits of the SHA-256 of the full
# name, and every ".-" is then replaced by "-".

# True when the next character is "-".
def Names.dash_next(t: String) -> Bool:
  match t:
    case SNil{}:
      False{}
    case SCon{c, r}:
      Char.is_eq(c, '-')

# True when `c` is a "." that a "-" follows: the "." of a ".-" match.
def Names.drop(c: Char, t: String) -> Bool:
  Bool.and(Char.is_eq(c, '.'), Names.dash_next(t))

def Names.emit(drop: Bool, c: Char, rest: String) -> String:
  match drop:
    case True{}:
      rest
    case False{}:
      SCon{c, rest}

# Go strings.ReplaceAll(s, ".-", "-"). Two ".-" matches never overlap, so
# this is the same as dropping every "." that a "-" follows.
def Names.collapse(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+c, +t}:
      Names.emit(Names.drop(c, t), c, Names.collapse(t))

# The name cut to 52 characters, "-", and 10 hex digits of its SHA-256,
# with every ".-" replaced by "-".
def Names.hashed(+s: String) -> String:
  Names.collapse(String.take(s, 52n) ++ SCon{'-', String.take(H.Sha256.hex_of(s), 10n)})

def Names.shorten.if(short: Bool, s: String) -> String:
  match short:
    case True{}:
      s
    case False{}:
      Names.hashed(s)

# A name of at most 63 characters stays; a longer one is hashed.
def Names.shorten(+s: String) -> String:
  Names.shorten.if(Nat.is_le(String.length(s), 63n), s)

# vcluster SafeConcatName: join the parts with "-", shortened as above when
# the joined name is longer than 63 characters.
def Names.safe_concat(parts: +List<String>) -> String:
  Names.shorten(String.join(parts, "-"))

# Single-namespace mode: the host name of virtual object `name` in virtual
# namespace `ns` of the vcluster `vc` is safe_concat([name, "x", ns, "x", vc]);
# the empty name stays empty.
def Names.host_name.if(empty: Bool, name: String, ns: String, vc: String) -> String:
  match empty:
    case True{}:
      ""
    case False{}:
      Names.safe_concat([name, "x", ns, "x", vc])

def Names.host_name(name: String, ns: String, vc: String) -> String:
  +n = name
  Names.host_name.if(String.is_empty(n), n, ns, vc)

# The host name of a cluster-scoped virtual object (vcluster HostNameCluster):
# safe_concat(["vcluster", name, "x", target_ns, "x", vc]); empty stays empty.
def Names.host_name_cluster.if(empty: Bool, name: String, target_ns: String, vc: String) -> String:
  match empty:
    case True{}:
      ""
    case False{}:
      Names.safe_concat(["vcluster", name, "x", target_ns, "x", vc])

def Names.host_name_cluster(name: String, target_ns: String, vc: String) -> String:
  +n = name
  Names.host_name_cluster.if(String.is_empty(n), n, target_ns, vc)

# The value of the vcluster.loft.sh/managed-by label on cluster-scoped host
# objects: safe_concat([target_ns, "x", vc]).
def Names.marker_cluster(target_ns: String, vc: String) -> String:
  Names.safe_concat([target_ns, "x", vc])
