import Base

# The subject of a verified client certificate, read as kube-apiserver's
# x509 authenticator reads it (k8s.io/apiserver/pkg/authentication/request/
# x509, CommonNameUserConversion): the user is the CommonName and the
# groups are the Organization values.
#
# host/effs/tls_server.c (TlsSrv.peer) renders a subject as RFC 4514 does,
# like Go's pkix.Name.String and OpenSSL's RFC 2253 form: the attributes
# last to first, each "TYPE=value", joined by ",", with any of ,+"\<>; in a
# value (and a leading "#" or space, a trailing space) escaped by a
# backslash. Reading it follows Go's pkix.Name.FillFromRDNSequence: the
# CommonName is the certificate's last CN, so the first in the string, and
# the Organization holds every O in certificate order, so string order
# reversed.

type Subject is Data:
  Subject{cn: String, orgs: +List<String>}

# How a character reads in a rendered value: the escape, the separator of
# attributes, another character the renderer escapes, or a plain one.
type Subject.Cls is Data:
  Bsl{}
  Sep{}
  Meta{}
  Lit{}

def Subject.cls(c: Char) -> Subject.Cls:
  ?TODO

# The attributes of a rendered subject, each "TYPE=value" with its escapes
# removed. An empty subject is one empty attribute.
def Subject.fields(s: String) -> +List<String>:
  ?TODO

# A value rendered with every special character escaped, as the renderer
# writes it.
def Subject.escape(s: String) -> String:
  ?TODO

def Subject.parse(s: String) -> Subject:
  ?TODO
