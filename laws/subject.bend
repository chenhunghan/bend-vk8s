import Base
import ../src/net/subject.bend as T

# Spec for src/net/subject.bend: the subject TlsSrv.peer reports for a
# client certificate (fake kubelet API, proxy), read as kube-apiserver reads
# it: user = CommonName, groups = Organization. Expected values follow Go's
# crypto/x509/pkix (Name.String renders RFC 4514, attributes last to first;
# FillFromRDNSequence keeps the last CN and appends every O in order) and
# vcluster's PKI (pkg/certs/constants.go: APIServerKubeletClientCertCommonName
# "kube-apiserver-kubelet-client", SystemPrivilegedGroup "system:masters").

# Go: pkix.Name{CommonName: "kube-apiserver-kubelet-client",
#   Organization: ["system:masters"]}.String()
law subject.kubelet_client:
  {T.Subject.parse("CN=kube-apiserver-kubelet-client,O=system:masters")
    == T.Subject{"kube-apiserver-kubelet-client", ["system:masters"]} : T.Subject}

# A certificate whose RDN sequence is O=o1, CN=a, O=o2, CN=b renders as
# below; Go fills CommonName "b" (the last CN) and Organization [o1, o2].
law subject.go_order:
  {T.Subject.parse("CN=b,O=o2,CN=a,O=o1") == T.Subject{"b", ["o1", "o2"]} : T.Subject}

# Escaped specials belong to the value.
law subject.escapes:
  {T.Subject.parse("CN=a\\,b,O=x\\+y\\\\z") == T.Subject{"a,b", ["x+y\\z"]} : T.Subject}

# Other attributes are ignored; a value may hold "=".
law subject.other_attributes:
  {T.Subject.parse("CN=admin,OU=ops,O=system:masters,O=a=b,C=US")
    == T.Subject{"admin", ["a=b", "system:masters"]} : T.Subject}

law subject.no_cn:
  {T.Subject.parse("O=system:nodes") == T.Subject{"", ["system:nodes"]} : T.Subject}

law subject.empty:
  {T.Subject.parse("") == T.Subject{"", []} : T.Subject}

# General laws.

# An escaped value is one attribute, the value itself: no separator inside
# a value splits it, whatever the value holds.
law subject.escape_one_field:
  for s: String
  {T.Subject.fields(T.Subject.escape(s)) == [s] : +List<String>}
