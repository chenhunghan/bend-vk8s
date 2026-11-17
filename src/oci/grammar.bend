import Base

# The grammars of the OCI library (src/oci/): repository names, tags,
# digests, registry hosts and media types. Imports only Base.
#
# Sources:
# - name: distribution-spec spec.md, "Pulling manifests":
#   [a-z0-9]+((\.|_|__|-+)[a-z0-9]+)*(\/[a-z0-9]+((\.|_|__|-+)[a-z0-9]+)*)*
#   and at most 255 characters (distribution/reference NameTotalLengthMax).
# - tag: spec.md, [a-zA-Z0-9_][a-zA-Z0-9._-]{0,127}.
# - digest: image-spec descriptor.md, algorithm ":" encoded; this mirror
#   supports sha256 only, whose encoded part is [a-f0-9]{64}.
# - registry host: distribution/reference regexp.go, domain-component
#   ([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]) joined by ".", with an
#   optional ":" port of digits. IPv6 literals are not supported.
# - media type: RFC 6838 section 4.2, type "/" subtype, each a
#   restricted-name: an alphanumeric first, then up to 126 of
#   alphanumerics and !#$&-^_.+

type Cls is Data:
  CLow{}
  CDig{}
  CUp{}
  CDot{}
  CUnd{}
  CDash{}
  CSlash{}
  COther{}

def Gram.cls.pick(lower: Bool, digit: Bool, upper: Bool) -> Cls:
  match lower digit upper:
    case True{} _ _:
      CLow{}
    case False{} True{} _:
      CDig{}
    case False{} False{} True{}:
      CUp{}
    case False{} False{} False{}:
      COther{}

def Gram.cls(c: Char) -> Cls:
  match c:
    case '.':
      CDot{}
    case '_':
      CUnd{}
    case '-':
      CDash{}
    case '/':
      CSlash{}
    case +x:
      Gram.cls.pick(Char.is_lower(x), Char.is_digit(x), Char.is_upper(x))

# Where a scan stands: at the start of a component, after an alphanumeric,
# after ".", after "_", after "__", after one or more "-", or failed.
type Scan is Data:
  NStart{}
  NAl{}
  NDot{}
  NUnd1{}
  NUnd2{}
  NDash{}
  NBad{}

def Gram.is_al(s: Scan) -> Bool:
  match s:
    case NAl{}:
      True{}
    case _:
      False{}

# One character of a repository name. A separator ("." "_" "__" "-+")
# must sit between alphanumerics; "/" ends a component.
def Gram.name.step(c: Cls, s: Scan) -> Scan:
  match c s:
    case _ NBad{}:
      NBad{}
    case CLow{} _:
      NAl{}
    case CDig{} _:
      NAl{}
    case CDot{} NAl{}:
      NDot{}
    case CUnd{} NAl{}:
      NUnd1{}
    case CUnd{} NUnd1{}:
      NUnd2{}
    case CDash{} NAl{}:
      NDash{}
    case CDash{} NDash{}:
      NDash{}
    case CSlash{} NAl{}:
      NStart{}
    case _ _:
      NBad{}

def Gram.name.run(s: String, st: Scan) -> Scan:
  match s:
    case SNil{}:
      st
    case SCon{c, t}:
      Gram.name.run(t, Gram.name.step(Gram.cls(c), st))

# A valid repository name (<name> in /v2/<name>/...).
def Gram.name(+s: String) -> Bool:
  Bool.and(Gram.is_al(Gram.name.run(s, NStart{})), Nat.is_le(String.length(s), 255n))

def Gram.tag.first(c: Cls) -> Bool:
  match c:
    case CLow{}:
      True{}
    case CDig{}:
      True{}
    case CUp{}:
      True{}
    case CUnd{}:
      True{}
    case _:
      False{}

def Gram.tag.more(c: Cls) -> Bool:
  match c:
    case CDot{}:
      True{}
    case CDash{}:
      True{}
    case x:
      Gram.tag.first(x)

def Gram.tag.rest(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      Bool.and(Gram.tag.more(Gram.cls(c)), Gram.tag.rest(t))

# A valid tag.
def Gram.tag(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{c, +t}:
      Bool.and(Bool.and(Gram.tag.first(Gram.cls(c)), Gram.tag.rest(t)), Nat.is_le(String.length(t), 127n))

def Gram.hex.char(c: Char) -> Bool:
  match c:
    case Chr{+x}:
      Bool.or(Bool.and(U32.is_ge(x, 48), U32.is_le(x, 57)), Bool.and(U32.is_ge(x, 97), U32.is_le(x, 102)))

def Gram.hex.all(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      Bool.and(Gram.hex.char(c), Gram.hex.all(t))

# 64 lowercase hex digits: a sha256 encoded part.
def Gram.hex64(+s: String) -> Bool:
  Bool.and(Nat.is_eq(String.length(s), 64n), Gram.hex.all(s))

# A sha256 digest; hex holds the 64 lowercase hex digits only.
type Digest is Data:
  Sha256{hex: String}

def Gram.digest.go(ok: Bool, hex: String) -> Maybe<&2, Digest>:
  match ok:
    case True{}:
      Some{Sha256{hex}}
    case False{}:
      None{}

def Gram.digest.if(pre: Bool, s: String) -> Maybe<&2, Digest>:
  match pre:
    case True{}:
      +h = String.drop(s, 7n)
      Gram.digest.go(Gram.hex64(h), h)
    case False{}:
      None{}

# "sha256:" and 64 lowercase hex digits; anything else is None.
def Gram.digest(+s: String) -> Maybe<&2, Digest>:
  Gram.digest.if(String.starts_with(s, "sha256:"), s)

def Gram.digest.show(d: Digest) -> String:
  match d:
    case Sha256{h}:
      "sha256:" ++ h

def Gram.digest.hex(d: Digest) -> String:
  match d:
    case Sha256{h}:
      h

# What the <reference> of /v2/<name>/manifests/<reference> is.
type Ref is Data:
  RDigest{digest: Digest}
  RBadDigest{}
  RTag{}
  RBad{}

def Gram.ref.digest(m: Maybe<&2, Digest>) -> Ref:
  match m:
    case Some{d}:
      RDigest{d}
    case None{}:
      RBadDigest{}

def Gram.ref.tag(ok: Bool) -> Ref:
  match ok:
    case True{}:
      RTag{}
    case False{}:
      RBad{}

def Gram.ref.go(colon: Bool, +s: String) -> Ref:
  match colon:
    case True{}:
      Gram.ref.digest(Gram.digest(s))
    case False{}:
      Gram.ref.tag(Gram.tag(s))

# A reference with ":" is a digest (a tag never holds ":"): a sha256 one,
# or one this mirror refuses. Without ":" it is a tag, or nothing valid.
def Gram.ref(+s: String) -> Ref:
  Gram.ref.go(String.contains(s, ":"), s)

# One character of a registry host name.
def Gram.host.step(c: Cls, s: Scan) -> Scan:
  match c s:
    case _ NBad{}:
      NBad{}
    case CLow{} _:
      NAl{}
    case CDig{} _:
      NAl{}
    case CUp{} _:
      NAl{}
    case CDash{} NAl{}:
      NDash{}
    case CDash{} NDash{}:
      NDash{}
    case CDot{} NAl{}:
      NStart{}
    case _ _:
      NBad{}

def Gram.host.run(s: String, st: Scan) -> Scan:
  match s:
    case SNil{}:
      st
    case SCon{c, t}:
      Gram.host.run(t, Gram.host.step(Gram.cls(c), st))

def Gram.host(s: String) -> Bool:
  Gram.is_al(Gram.host.run(s, NStart{}))

def Gram.port.digits(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      Bool.and(Char.is_digit(c), Gram.port.digits(t))

def Gram.port(+s: String) -> Bool:
  Bool.and(Bool.not(String.is_empty(s)), Gram.port.digits(s))

def Gram.registry.parts(ps: List<&2, String>) -> Bool:
  match ps:
    case Con{h, Nil{}}:
      Gram.host(h)
    case Con{h, Con{p, Nil{}}}:
      Bool.and(Gram.host(h), Gram.port(p))
    case _:
      False{}

# A registry host, with an optional port: "docker.io", "localhost:5000".
def Gram.registry(+s: String) -> Bool:
  Bool.and(Gram.registry.parts(String.split(s, ':')), Nat.is_le(String.length(s), 255n))

def Gram.media.char(c: Char) -> Bool:
  match c:
    case '!':
      True{}
    case '#':
      True{}
    case '$':
      True{}
    case '&':
      True{}
    case '-':
      True{}
    case '^':
      True{}
    case '_':
      True{}
    case '.':
      True{}
    case '+':
      True{}
    case +x:
      Bool.or(Char.is_alpha(x), Char.is_digit(x))

def Gram.media.rest(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      Bool.and(Gram.media.char(c), Gram.media.rest(t))

def Gram.media.name(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{+c, +t}:
      Bool.and(Bool.and(Bool.or(Char.is_alpha(c), Char.is_digit(c)), Gram.media.rest(t)), Nat.is_le(String.length(t), 126n))

def Gram.media.parts(ps: List<&2, String>) -> Bool:
  match ps:
    case Con{a, Con{b, Nil{}}}:
      Bool.and(Gram.media.name(a), Gram.media.name(b))
    case _:
      False{}

# type "/" subtype, without parameters.
def Gram.media(+s: String) -> Bool:
  Gram.media.parts(String.split(s, '/'))

def Gram.before.if(cut: Bool, c: Char, rest: String) -> String:
  match cut:
    case True{}:
      SNil{}
    case False{}:
      SCon{c, rest}

# s up to (not including) the first stop character.
def Gram.before(s: String, +stop: Char) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+c, t}:
      Gram.before.if(Char.is_eq(c, stop), c, Gram.before(t, stop))

def Gram.media.or(ok: Bool, s: String) -> String:
  match ok:
    case True{}:
      s
    case False{}:
      "application/octet-stream"

# An upstream Content-Type made safe to store and send back: parameters
# dropped (spec.md: the registry SHOULD NOT include parameters), and any
# value that is not type/subtype becomes application/octet-stream, so no
# CR, LF or other byte from upstream reaches a header.
def Gram.media.clean(s: String) -> String:
  +m = String.trim(Gram.before(s, ';'))
  Gram.media.or(Gram.media(m), m)
