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

def Subject.cls.meta(meta: Bool) -> Subject.Cls:
  match meta:
    case True{}:
      Meta{}
    case False{}:
      Lit{}

def Subject.cls.sep(sep: Bool, meta: Bool) -> Subject.Cls:
  match sep:
    case True{}:
      Sep{}
    case False{}:
      Subject.cls.meta(meta)

def Subject.cls.bsl(bsl: Bool, sep: Bool, meta: Bool) -> Subject.Cls:
  match bsl:
    case True{}:
      Bsl{}
    case False{}:
      Subject.cls.sep(sep, meta)

# + " < > ; (a backslash and a comma have their own classes).
def Subject.is_meta(+x: U32) -> Bool:
  U32.is_eq(x, 43) || U32.is_eq(x, 34) || U32.is_eq(x, 60) || U32.is_eq(x, 62)
    || U32.is_eq(x, 59)

def Subject.cls(c: Char) -> Subject.Cls:
  match c:
    case Chr{+x}:
      Subject.cls.bsl(U32.is_eq(x, 92), U32.is_eq(x, 44), Subject.is_meta(x))

# A string read in two ways at once: plain, and with its first character
# escaped (taken as it is, the backslash before it already dropped).
type Subject.Cut is Data:
  Cut{plain: +List<String>, esc: +List<String>}

def Subject.Cut.plain(r: Subject.Cut) -> +List<String>:
  match r:
    case Cut{p, e}:
      p

def Subject.Cut.esc(r: Subject.Cut) -> +List<String>:
  match r:
    case Cut{p, e}:
      e

# c onto the first attribute.
def Subject.push(c: Char, ps: +List<String>) -> +List<String>:
  match ps:
    case Nil{}:
      [SCon{c, SNil{}}]
    case Con{h, t}:
      Con{SCon{c, h}, t}

# h in front of a string read as r. Escaped, h is always a character of
# the value; plain, a backslash takes the next character as it is and a
# comma starts a new attribute.
def Subject.cut.at(k: Subject.Cls, +h: Char, +r: Subject.Cut) -> Subject.Cut:
  match k:
    case Bsl{}:
      Cut{Subject.Cut.esc(r), Subject.push(h, Subject.Cut.plain(r))}
    case Sep{}:
      Cut{Con{SNil{}, Subject.Cut.plain(r)}, Subject.push(h, Subject.Cut.plain(r))}
    case Meta{}:
      Cut{Subject.push(h, Subject.Cut.plain(r)), Subject.push(h, Subject.Cut.plain(r))}
    case Lit{}:
      Cut{Subject.push(h, Subject.Cut.plain(r)), Subject.push(h, Subject.Cut.plain(r))}

def Subject.cut(s: String) -> Subject.Cut:
  match s:
    case SNil{}:
      Cut{[SNil{}], [SNil{}]}
    case SCon{+h, t}:
      Subject.cut.at(Subject.cls(h), h, Subject.cut(t))

# The attributes of a rendered subject, each "TYPE=value" with its escapes
# removed. An empty subject is one empty attribute.
def Subject.fields(s: String) -> +List<String>:
  Subject.Cut.plain(Subject.cut(s))

# A value rendered with every special character escaped, as the renderer
# writes it.
def Subject.esc.at(k: Subject.Cls, +h: Char, t: String) -> String:
  match k:
    case Bsl{}:
      SCon{'\\', SCon{h, t}}
    case Sep{}:
      SCon{'\\', SCon{h, t}}
    case Meta{}:
      SCon{'\\', SCon{h, t}}
    case Lit{}:
      SCon{h, t}

def Subject.escape(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+h, t}:
      Subject.esc.at(Subject.cls(h), h, Subject.escape(t))

# An attribute split at its first "=": the type, then the value.
type Subject.KV is Data:
  KV{key: String, val: String}

def Subject.kv.at(eq: Bool, +h: Char, +t: String, r: Subject.KV) -> Subject.KV:
  match eq r:
    case True{} KV{k, v}:
      KV{SNil{}, t}
    case False{} KV{k, v}:
      KV{SCon{h, k}, v}

def Subject.kv(s: String) -> Subject.KV:
  match s:
    case SNil{}:
      KV{SNil{}, SNil{}}
    case SCon{+h, +t}:
      Subject.kv.at(Char.is_eq(h, '='), h, t, Subject.kv(t))

def Subject.add.o(o: Bool, +v: String, s: Subject) -> Subject:
  match o s:
    case True{} Subject{cn, orgs}:
      Subject{cn, List.append(&2, String, orgs, [v])}
    case False{} Subject{cn, orgs}:
      Subject{cn, orgs}

def Subject.add.cn(cn: Bool, o: Bool, +v: String, s: Subject) -> Subject:
  match cn s:
    case True{} Subject{c, orgs}:
      Subject{v, orgs}
    case False{} Subject{c, orgs}:
      Subject.add.o(o, v, Subject{c, orgs})

def Subject.add(a: Subject.KV, s: Subject) -> Subject:
  match a:
    case KV{+k, +v}:
      Subject.add.cn(String.eq(k, "CN"), String.eq(k, "O"), v, s)

# Folded from the last attribute back: an earlier CN replaces a later one,
# and each O goes after those that follow it in the string.
def Subject.build(fs: +List<String>) -> Subject:
  match fs:
    case Nil{}:
      Subject{SNil{}, []}
    case Con{f, rest}:
      Subject.add(Subject.kv(f), Subject.build(rest))

def Subject.parse(s: String) -> Subject:
  Subject.build(Subject.fields(s))
