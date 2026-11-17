import Base

# OCI pull-through mirror, upstream side: token auth and redirects. Pure.
# Part of the self-contained OCI library (src/oci/, host/oci/): it imports
# Base only, never the rest of vk8s.
#
# - WWW-Authenticate challenges, parsed as containerd's
#   core/remotes/docker/auth/parse.go parseValueAndParams does (one
#   challenge per header value; scheme and keys lowercased; a value is a
#   token or a quoted string with backslash escapes; the parse stops at the
#   first thing it does not expect and keeps what it has).
# - The anonymous token request URL, as containerd's auth/fetch.go
#   FetchToken builds it: the realm, then service and every scope, encoded
#   as Go's url.Values.Encode (keys sorted: scope before service; values
#   escaped as url.QueryEscape).
# - The token response (distribution docs/spec/auth/token.md): token or
#   access_token (access_token wins when both are set, as containerd and
#   distribution do), expires_in defaulting to and at least 60 seconds
#   (distribution internal/client/auth/session.go).
# - Realm restrictions, as distribution's registry/proxy/proxyauth.go
#   realmAllowed: the same Host, or the same registrable domain when
#   neither host is an IP literal or localhost.
# - Redirects (registry.k8s.io and others send blobs to object storage):
#   https only, at most 10 hops (containerd's CheckRedirect), never to a
#   private, loopback or local host, and Authorization kept only for the
#   same origin (scheme, host, effective port), as containerd's
#   isRegistryOrigin and stripSensitiveHeadersForExternalURLs.

# Types
# -----

type Param is Data:
  Param{key: String, value: String}

# A challenge: its scheme (lowercase, "" when the header has none) and its
# parameters in header order (keys lowercase; a repeated key: the last wins).
type Challenge is Data:
  Challenge{scheme: String, params: List<&2, Param>}

# A Bearer challenge, ready for a token request.
type Bearer is Data:
  Bearer{realm: String, service: String, scopes: +List<String>}

# A token response: the token and its lifetime in seconds.
type Token is Data:
  Token{token: String, expires_in: U32}

# A redirect decision: follow url (auth: keep the Authorization header,
# same origin only), or refuse with a reason.
type Hop is Data:
  Follow{url: String, auth: Bool}
  Refuse{why: String}

type ASp is Data:
  ASp{a: String, b: String}

# A URL cut in three: scheme (lowercase; "" when there is no "scheme://"),
# authority (userinfo, host and port, as written) and the rest (path,
# query, fragment).
type Url is Data:
  Url{scheme: String, auth: String, rest: String}

# The challenge parser's state: the mode, then the scheme, key and value
# so far (reversed), then the parameters so far (reversed).
type Ch is Data:
  Ch{mode: Nat, scheme: String, key: String, val: String, ps: List<&2, Param>}

# What the token parser kept: token, access_token, expires_in.
type Got is Data:
  Got{tok: String, acc: String, exp: U32}

# The token parser's state: the mode, the nesting depth inside a skipped
# value, the key and the value so far (reversed), and what it kept.
type Js is Data:
  Js{mode: Nat, depth: U32, key: String, cur: String, got: Got}

# Characters
# ----------

def Auth.in(+u: U32, +lo: U32, +hi: U32) -> Bool:
  Bool.and(U32.is_ge(u, lo), U32.is_le(u, hi))

def Auth.code(c: Char) -> U32:
  match c:
    case Chr{u}:
      u

# RFC 2616 separators, as containerd's octetTypes: ( ) < > @ , ; : \ " / [ ] ? = { } SP HT.
def Auth.is_sep(+u: U32) -> Bool:
  U32.is_eq(u, 32) || U32.is_eq(u, 9) || U32.is_eq(u, 34) || U32.is_eq(u, 40) || U32.is_eq(u, 41) || U32.is_eq(u, 44) || U32.is_eq(u, 47) || Auth.in(u, 58, 64) || Auth.in(u, 91, 93) || U32.is_eq(u, 123) || U32.is_eq(u, 125)

# token = 1*<any CHAR except CTLs or separators>
def Auth.is_tok(+u: U32) -> Bool:
  Bool.and(Auth.in(u, 33, 126), Bool.not(Auth.is_sep(u)))

# containerd's isSpace: SP, HT, CR, LF.
def Auth.is_sp(+u: U32) -> Bool:
  U32.is_eq(u, 32) || U32.is_eq(u, 9) || U32.is_eq(u, 13) || U32.is_eq(u, 10)

def Auth.is_digit(+u: U32) -> Bool:
  Auth.in(u, 48, 57)

def Auth.lower.go(up: Bool, +u: U32) -> U32:
  match up:
    case True{}:
      (u + 32 : U32)
    case False{}:
      u

def Auth.lower(+u: U32) -> U32:
  Auth.lower.go(Auth.in(u, 65, 90), u)

def Auth.all_digits(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{Chr{+u}, t}:
      Bool.and(Auth.is_digit(u), Auth.all_digits(t))

def Auth.has(xs: +List<String>, +x: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{+h, t}:
      String.eq(h, x) || Auth.has(t, x)

# WWW-Authenticate
# ----------------

def Auth.commit(k: String, v: String, ps: List<&2, Param>) -> List<&2, Param>:
  Con{Param{String.reverse(k), String.reverse(v)}, ps}

def Auth.add(+u: U32, s: String) -> String:
  SCon{Chr{u}, s}

# Modes: 0 scheme, 1 before a key, 2 key, 3 value start, 4 token value,
# 5 quoted value, 6 after a backslash in a quoted value, 7 after a value,
# 8 done (the rest is ignored).

def Auth.ch.m0(tok: Bool, sp: Bool, +u: U32, sc: String, ps: List<&2, Param>) -> Ch:
  match tok sp:
    case True{} _:
      Ch{0n, Auth.add(Auth.lower(u), sc), "", "", ps}
    case False{} True{}:
      Ch{1n, sc, "", "", ps}
    case False{} False{}:
      Ch{8n, sc, "", "", ps}

def Auth.ch.m1(sp: Bool, tok: Bool, +u: U32, sc: String, ps: List<&2, Param>) -> Ch:
  match sp tok:
    case True{} _:
      Ch{1n, sc, "", "", ps}
    case False{} True{}:
      Ch{2n, sc, Auth.add(Auth.lower(u), ""), "", ps}
    case False{} False{}:
      Ch{8n, sc, "", "", ps}

def Auth.ch.m2(tok: Bool, eq: Bool, +u: U32, sc: String, k: String, ps: List<&2, Param>) -> Ch:
  match tok eq:
    case True{} _:
      Ch{2n, sc, Auth.add(Auth.lower(u), k), "", ps}
    case False{} True{}:
      Ch{3n, sc, k, "", ps}
    case False{} False{}:
      Ch{8n, sc, "", "", ps}

def Auth.ch.m3(quote: Bool, tok: Bool, sp: Bool, comma: Bool, +u: U32, sc: String, k: String,
  ps: List<&2, Param>) -> Ch:
  match quote tok sp comma:
    case True{} _ _ _:
      Ch{5n, sc, k, "", ps}
    case False{} True{} _ _:
      Ch{4n, sc, k, Auth.add(u, ""), ps}
    case False{} False{} True{} _:
      Ch{7n, sc, "", "", Auth.commit(k, "", ps)}
    case False{} False{} False{} True{}:
      Ch{1n, sc, "", "", Auth.commit(k, "", ps)}
    case False{} False{} False{} False{}:
      Ch{8n, sc, "", "", Auth.commit(k, "", ps)}

def Auth.ch.m4(tok: Bool, sp: Bool, comma: Bool, +u: U32, sc: String, k: String, v: String,
  ps: List<&2, Param>) -> Ch:
  match tok sp comma:
    case True{} _ _:
      Ch{4n, sc, k, Auth.add(u, v), ps}
    case False{} True{} _:
      Ch{7n, sc, "", "", Auth.commit(k, v, ps)}
    case False{} False{} True{}:
      Ch{1n, sc, "", "", Auth.commit(k, v, ps)}
    case False{} False{} False{}:
      Ch{8n, sc, "", "", Auth.commit(k, v, ps)}

def Auth.ch.m5(quote: Bool, bs: Bool, +u: U32, sc: String, k: String, v: String, ps: List<&2, Param>) -> Ch:
  match quote bs:
    case True{} _:
      Ch{7n, sc, "", "", Auth.commit(k, v, ps)}
    case False{} True{}:
      Ch{6n, sc, k, v, ps}
    case False{} False{}:
      Ch{5n, sc, k, Auth.add(u, v), ps}

def Auth.ch.m7(sp: Bool, comma: Bool, sc: String, ps: List<&2, Param>) -> Ch:
  match sp comma:
    case True{} _:
      Ch{7n, sc, "", "", ps}
    case False{} True{}:
      Ch{1n, sc, "", "", ps}
    case False{} False{}:
      Ch{8n, sc, "", "", ps}

def Auth.ch.step(st: Ch, +u: U32) -> Ch:
  match st:
    case Ch{m, sc, k, v, ps}:
      match m:
        case 0n:
          Auth.ch.m0(Auth.is_tok(u), Auth.is_sp(u), u, sc, ps)
        case 1n:
          Auth.ch.m1(Auth.is_sp(u), Auth.is_tok(u), u, sc, ps)
        case 2n:
          Auth.ch.m2(Auth.is_tok(u), U32.is_eq(u, 61), u, sc, k, ps)
        case 3n:
          Auth.ch.m3(U32.is_eq(u, 34), Auth.is_tok(u), Auth.is_sp(u), U32.is_eq(u, 44), u, sc, k, ps)
        case 4n:
          Auth.ch.m4(Auth.is_tok(u), Auth.is_sp(u), U32.is_eq(u, 44), u, sc, k, v, ps)
        case 5n:
          Auth.ch.m5(U32.is_eq(u, 34), U32.is_eq(u, 92), u, sc, k, v, ps)
        case 6n:
          Ch{5n, sc, k, Auth.add(u, v), ps}
        case 7n:
          Auth.ch.m7(Auth.is_sp(u), U32.is_eq(u, 44), sc, ps)
        case _:
          Ch{8n, sc, k, v, ps}

def Auth.ch.run(s: String, st: Ch) -> Ch:
  match s:
    case SNil{}:
      st
    case SCon{Chr{u}, t}:
      Auth.ch.run(t, Auth.ch.step(st, u))

# At the end of the header: a pending value is kept; an open quoted value
# is "" (containerd's expectTokenOrQuoted answers "" for it).
def Auth.ch.flush(m: Nat, k: String, v: String, ps: List<&2, Param>) -> List<&2, Param>:
  match m:
    case 0n:
      ps
    case 1n:
      ps
    case 2n:
      ps
    case 3n:
      Auth.commit(k, "", ps)
    case 4n:
      Auth.commit(k, v, ps)
    case 5n:
      Auth.commit(k, "", ps)
    case 6n:
      Auth.commit(k, "", ps)
    case _:
      ps

def Auth.ch.fin(st: Ch) -> Challenge:
  match st:
    case Ch{m, sc, k, v, ps}:
      Challenge{String.reverse(sc), List.reverse(&2, Param, Auth.ch.flush(m, k, v, ps))}

# Parse one WWW-Authenticate header value.
def Auth.challenge(h: String) -> Challenge:
  Auth.ch.fin(Auth.ch.run(h, Ch{0n, "", "", "", []}))

def Auth.get.pick(later: Maybe<&2, String>, hit: Bool, v: String) -> Maybe<&2, String>:
  match later hit:
    case Some{x} _:
      Some{x}
    case None{} True{}:
      Some{v}
    case None{} False{}:
      None{}

# A parameter's value (the last one when the key repeats).
def Auth.get(ps: List<&2, Param>, +key: String) -> Maybe<&2, String>:
  match ps:
    case Nil{}:
      None{}
    case Con{Param{k, v}, t}:
      Auth.get.pick(Auth.get(t, key), String.eq(k, key), v)

def Auth.param(ps: List<&2, Param>, +key: String) -> String:
  Maybe.default(&2, String, Auth.get(ps, key), "")

def Auth.words.put(drop: Bool, x: String, rest: List<&2, String>) -> List<&2, String>:
  match drop:
    case True{}:
      rest
    case False{}:
      Con{x, rest}

def Auth.words.keep(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, t}:
      Auth.words.put(String.is_empty(x), x, Auth.words.keep(t))

# The space-separated words of s (containerd splits scope on " ").
def Auth.words(s: String) -> List<&2, String>:
  Auth.words.keep(String.split(s, Chr{32}))

def Auth.bearer.mk(empty: Bool, r: String, +ps: List<&2, Param>) -> Maybe<&2, Bearer>:
  match empty:
    case True{}:
      None{}
    case False{}:
      Some{Bearer{r, Auth.param(ps, "service"), Auth.words(Auth.param(ps, "scope"))}}

def Auth.bearer.go(is_bearer: Bool, realm: Maybe<&2, String>, +ps: List<&2, Param>) -> Maybe<&2, Bearer>:
  match is_bearer realm:
    case True{} Some{+r}:
      Auth.bearer.mk(String.is_empty(r), r, ps)
    case _ _:
      None{}

def Auth.bearer.of(c: Challenge) -> Maybe<&2, Bearer>:
  match c:
    case Challenge{sc, +ps}:
      Auth.bearer.go(String.eq(sc, "bearer"), Auth.get(ps, "realm"), ps)

# The Bearer challenge of one WWW-Authenticate value: None for another
# scheme, or without a realm (containerd: "no realm specified").
def Auth.bearer(h: String) -> Maybe<&2, Bearer>:
  Auth.bearer.of(Auth.challenge(h))

def Auth.realm(b: Bearer) -> String:
  match b:
    case Bearer{r, s, sc}:
      r

# URLs
# ----

# Character classes for Url.span: 0 scheme, 1 authority (up to / ? #),
# 2 not ":", 3 not "]", 4 path (up to ? #), 5 not "@", 6 not "/", 7 not ".".
def Url.cls(+k: Nat, +u: U32) -> Bool:
  match k:
    case 0n:
      Auth.in(u, 97, 122) || Auth.in(u, 65, 90) || Auth.in(u, 48, 57) || U32.is_eq(u, 43) || U32.is_eq(u, 45) || U32.is_eq(u, 46)
    case 1n:
      Bool.not(U32.is_eq(u, 47) || U32.is_eq(u, 63) || U32.is_eq(u, 35))
    case 2n:
      Bool.not(U32.is_eq(u, 58))
    case 3n:
      Bool.not(U32.is_eq(u, 93))
    case 4n:
      Bool.not(U32.is_eq(u, 63) || U32.is_eq(u, 35))
    case 5n:
      Bool.not(U32.is_eq(u, 64))
    case 6n:
      Bool.not(U32.is_eq(u, 47))
    case 7n:
      Bool.not(U32.is_eq(u, 46))
    case _:
      False{}

def Url.span.go(keep: Bool, +c: Char, +t: String, r: ASp) -> ASp:
  match keep:
    case True{}:
      match r:
        case ASp{a, b}:
          ASp{SCon{c, a}, b}
    case False{}:
      ASp{"", SCon{c, t}}

# The leading run of s in class k, and the rest.
def Url.span(s: String, +k: Nat) -> ASp:
  match s:
    case SNil{}:
      ASp{"", ""}
    case SCon{+c, +t}:
      Url.span.go(Url.cls(k, Auth.code(c)), c, t, Url.span(t, k))

def Url.fst(sp: ASp) -> String:
  match sp:
    case ASp{a, b}:
      a

def Url.snd(sp: ASp) -> String:
  match sp:
    case ASp{a, b}:
      b

def Url.parse.fin(sc: String, sp: ASp) -> Url:
  match sp:
    case ASp{a, r}:
      Url{sc, a, r}

def Url.parse.auth(ok: Bool, sc: String, rest: String, s: String) -> Url:
  match ok:
    case True{}:
      Url.parse.fin(String.to_lower(sc), Url.span(String.drop(rest, 3n), 1n))
    case False{}:
      Url{"", "", s}

def Url.parse.go(sp: ASp, s: String) -> Url:
  match sp:
    case ASp{+sc, +rest}:
      Url.parse.auth(Bool.and(Bool.not(String.is_empty(sc)), String.starts_with(rest, "://")), sc, rest, s)

def Url.parse(+s: String) -> Url:
  Url.parse.go(Url.span(s, 0n), s)

# The authority less its userinfo: Go's URL.Host.
def Url.hostport(au: String) -> String:
  String.reverse(Url.fst(Url.span(String.reverse(au), 5n)))

def Url.hostname.go(v6: Bool, +hp: String) -> String:
  match v6:
    case True{}:
      Url.fst(Url.span(String.drop(hp, 1n), 3n))
    case False{}:
      Url.fst(Url.span(hp, 2n))

# Go's URL.Hostname over a Host (brackets stripped), lowercased.
def Url.hostname(+hp: String) -> String:
  String.to_lower(Url.hostname.go(String.starts_with(hp, "["), hp))

def Url.port.go(v6: Bool, +hp: String) -> String:
  match v6:
    case True{}:
      String.drop(Url.snd(Url.span(hp, 3n)), 2n)
    case False{}:
      String.drop(Url.snd(Url.span(hp, 2n)), 1n)

# Go's URL.Port over a Host: "" when there is none.
def Url.port(+hp: String) -> String:
  Url.port.go(String.starts_with(hp, "["), hp)

# The hostname of an authority.
def Url.host(au: String) -> String:
  Url.hostname(Url.hostport(au))

def Url.eport.go(empty: Bool, https: Bool, http: Bool, p: String) -> String:
  match empty https http:
    case False{} _ _:
      p
    case True{} True{} _:
      "443"
    case True{} False{} True{}:
      "80"
    case True{} False{} False{}:
      ""

# The port, or the scheme's default (containerd's effectivePort).
def Url.eport(+sc: String, +p: String) -> String:
  Url.eport.go(String.is_empty(p), String.eq(sc, "https"), String.eq(sc, "http"), p)

def Url.origin_key.go(+hp: String, +sc: String) -> String:
  Url.hostname(hp) ++ ":" ++ Url.eport(sc, Url.port(hp))

# scheme://host:port, for origin comparisons.
def Url.origin_key(u: Url) -> String:
  match u:
    case Url{+sc, au, r}:
      sc ++ "://" ++ Url.origin_key.go(Url.hostport(au), sc)

def Url.origin(u: Url) -> String:
  match u:
    case Url{sc, au, r}:
      sc ++ "://" ++ au

def Url.origin_scheme(u: Url) -> String:
  match u:
    case Url{sc, au, r}:
      sc

def Url.path(u: Url) -> String:
  match u:
    case Url{sc, au, r}:
      Url.fst(Url.span(r, 4n))

def Url.origin_path(+u: Url) -> String:
  Url.origin(u) ++ Url.path(u)

def Url.dir.go(empty: Bool, d: String) -> String:
  match empty:
    case True{}:
      "/"
    case False{}:
      d

def Url.dir.go2(+d: String) -> String:
  Url.dir.go(String.is_empty(d), d)

# The path up to and including its last "/" ("/" when it has none).
def Url.dir(p: String) -> String:
  Url.dir.go2(String.reverse(Url.snd(Url.span(String.reverse(p), 6n))))

def Url.origin_dir(+u: Url) -> String:
  Url.origin(u) ++ Url.dir(Url.path(u))

# Same scheme, hostname and effective port.
def Auth.same_origin(+a: String, +b: String) -> Bool:
  String.eq(Url.origin_key(Url.parse(a)), Url.origin_key(Url.parse(b)))

# Hosts
# -----

def Auth.octet.le(ok: Bool, x: U32) -> Maybe<&2, U32>:
  match ok:
    case True{}:
      Some{x}
    case False{}:
      None{}

def Auth.octet.max(m: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match m:
    case Some{+x}:
      Auth.octet.le(U32.is_le(x, 255), x)
    case None{}:
      None{}

def Auth.octet.go(ok: Bool, s: String) -> Maybe<&2, U32>:
  match ok:
    case True{}:
      Auth.octet.max(U32.read(s))
    case False{}:
      None{}

# One decimal octet as Go's net.ParseIP takes it: 1 to 3 digits, no
# leading zero, at most 255.
def Auth.octet(+s: String) -> Maybe<&2, U32>:
  Auth.octet.go(Auth.all_digits(s) && Nat.is_ge(String.length(s), 1n) && Nat.is_le(String.length(s), 3n) && Bool.not(Bool.and(Nat.is_gt(String.length(s), 1n), String.starts_with(s, "0"))), s)

def Auth.ipv4.all(a: Maybe<&2, U32>, b: Maybe<&2, U32>, c: Maybe<&2, U32>, d: Maybe<&2, U32>) ->
  Maybe<&2, List<&2, U32>>:
  match a b c d:
    case Some{x} Some{y} Some{z} Some{w}:
      Some{[x, y, z, w]}
    case _ _ _ _:
      None{}

def Auth.ipv4.go(ps: List<&2, String>) -> Maybe<&2, List<&2, U32>>:
  match ps:
    case Con{a, Con{b, Con{c, Con{d, Nil{}}}}}:
      Auth.ipv4.all(Auth.octet(a), Auth.octet(b), Auth.octet(c), Auth.octet(d))
    case _:
      None{}

# A dotted-quad IPv4 literal, as its four octets.
def Auth.ipv4(h: String) -> Maybe<&2, List<&2, U32>>:
  Auth.ipv4.go(String.split(h, Chr{46}))

# Not public: this network (0/8), private (10/8, 172.16/12, 192.168/16),
# shared (100.64/10), loopback (127/8), link-local (169.254/16), IETF
# (192.0.0/24), benchmarking (198.18/15), multicast and reserved (224/3).
def Auth.ip_private(+a: U32, +b: U32, +c: U32) -> Bool:
  U32.is_eq(a, 0) || U32.is_eq(a, 10) || U32.is_eq(a, 127) || U32.is_ge(a, 224) || Bool.and(U32.is_eq(a, 100), Auth.in(b, 64, 127)) || Bool.and(U32.is_eq(a, 169), U32.is_eq(b, 254)) || Bool.and(U32.is_eq(a, 172), Auth.in(b, 16, 31)) || Bool.and(U32.is_eq(a, 192), U32.is_eq(b, 168)) || Bool.and(U32.is_eq(a, 192), Bool.and(U32.is_eq(b, 0), U32.is_eq(c, 0))) || Bool.and(U32.is_eq(a, 198), Auth.in(b, 18, 19))

# May the mirror connect to this IPv4 address? The host layer asks this
# for every address a redirect target resolves to (DNS can point a public
# name at a private address).
def Auth.addr_allowed(os: List<&2, U32>) -> Bool:
  match os:
    case Con{a, Con{b, Con{c, Con{d, Nil{}}}}}:
      Bool.not(Auth.ip_private(a, b, c))
    case _:
      False{}

def Auth.blocked.v4(m: Maybe<&2, List<&2, U32>>) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{os}:
      Bool.not(Auth.addr_allowed(os))

def Auth.blocked.num(num: Bool, h: String) -> Bool:
  match num:
    case True{}:
      Auth.blocked.v4(Auth.ipv4(h))
    case False{}:
      False{}

def Auth.last_label(h: String) -> String:
  String.reverse(Url.fst(Url.span(String.reverse(h), 7n)))

def Auth.starts_digit(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{Chr{+u}, t}:
      Auth.is_digit(u)

def Auth.trim_dot.go(dot: Bool, +h: String) -> String:
  match dot:
    case True{}:
      String.take(h, Nat.sub(String.length(h), 1n))
    case False{}:
      h

def Auth.trim_dot(+h: String) -> String:
  Auth.trim_dot.go(String.ends_with(h, "."), h)

def Auth.blocked.go(+h: String) -> Bool:
  String.is_empty(h) || Bool.not(String.contains(h, ".")) || String.contains(h, ":") || String.ends_with(h, ".localhost") || String.ends_with(h, ".local") || String.ends_with(h, ".internal") || String.ends_with(h, ".localdomain") || String.ends_with(h, ".home.arpa") || Auth.blocked.num(Auth.starts_digit(Auth.last_label(h)), h)

# A redirect target the mirror refuses: no host, a single label (localhost,
# metadata and other local names), a local suffix, an IPv6 literal, or a
# numeric host that is not a public dotted quad (inet_aton forms such as
# 0x7f.1 or 2130706433 included: a real top-level label never starts with
# a digit).
def Auth.blocked_host(h: String) -> Bool:
  Auth.blocked.go(Auth.trim_dot(h))

# Realms
# ------

# Public suffixes of two labels that the registrable-domain check knows:
# a few private ones from the Public Suffix List where anyone can own a
# subdomain.
def Auth.suffixes() -> List<&2, String>:
  ["github.io", "gitlab.io", "herokuapp.com", "appspot.com", "cloudfront.net", "azurewebsites.net",
    "pages.dev", "workers.dev", "netlify.app", "vercel.app", "web.app", "firebaseapp.com", "blogspot.com"]

# Second-level labels that country-code registries sell under (co.uk,
# com.au, ne.jp, ...).
def Auth.cc_second() -> List<&2, String>:
  ["co", "com", "net", "org", "gov", "edu", "ac", "or", "ne", "go", "gob", "mil", "nic", "ltd", "plc",
    "sch", "nom", "gen"]

def Auth.two_label(+sld: String, +tld: String) -> Bool:
  Auth.has(Auth.suffixes(), sld ++ "." ++ tld) || Bool.and(Nat.is_eq(String.length(tld), 2n), Auth.has(Auth.cc_second(), sld))

def Auth.suffix_n.pick(two: Bool) -> Nat:
  match two:
    case True{}:
      2n
    case False{}:
      1n

# How many labels the public suffix of a host has, given its labels last
# first.
def Auth.suffix_n(rev: List<&2, String>) -> Nat:
  match rev:
    case Con{tld, Con{sld, t}}:
      Auth.suffix_n.pick(Auth.two_label(sld, tld))
    case _:
      1n

def Auth.etld1.cut(short: Bool, rev: List<&2, String>, n: Nat) -> List<&2, String>:
  match short:
    case True{}:
      Nil{}
    case False{}:
      List.take(&2, String, rev, n)

def Auth.etld1.go(+rev: List<&2, String>, +n: Nat) -> List<&2, String>:
  Auth.etld1.cut(Nat.is_lt(List.length(&2, String, rev), n), rev, n)

def Auth.etld1.rev(+rev: List<&2, String>) -> List<&2, String>:
  Auth.etld1.go(rev, Nat.add(Auth.suffix_n(rev), 1n))

# The registrable domain (eTLD+1) of a hostname, "" when it has none. Go
# uses publicsuffix.EffectiveTLDPlusOne over the whole Public Suffix List;
# this knows the two-label suffixes above and the country-code second
# levels of Auth.cc_second, and takes every other suffix to be one label.
def Auth.etld1(h: String) -> String:
  String.join(List.reverse(&2, String, Auth.etld1.rev(List.reverse(&2, String, String.split(h, Chr{46})))), ".")

def Auth.all_digits_dots(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{Chr{+u}, t}:
      Bool.and(Bool.or(Auth.is_digit(u), U32.is_eq(u, 46)), Auth.all_digits_dots(t))

# distribution's isLiteralOrLocal: localhost or an IP literal (any host
# with a ":" is IPv6; any numeric host counts, stricter than ParseIP).
def Auth.literal_or_local(+h: String) -> Bool:
  String.eq(h, "localhost") || String.contains(h, ":") || Bool.and(Bool.not(String.is_empty(h)), Auth.all_digits_dots(h))

def Auth.same_domain(+a: String, +b: String) -> Bool:
  Bool.and(Bool.not(String.is_empty(a)), String.eq(a, b))

def Auth.ra.domains(lit: Bool, rn: String, mn: String) -> Bool:
  match lit:
    case True{}:
      False{}
    case False{}:
      Auth.same_domain(Auth.etld1(rn), Auth.etld1(mn))

def Auth.ra.cmp(empty: Bool, same: Bool, +rn: String, +mn: String) -> Bool:
  match empty same:
    case True{} _:
      False{}
    case False{} True{}:
      True{}
    case False{} False{}:
      Auth.ra.domains(Bool.or(Auth.literal_or_local(rn), Auth.literal_or_local(mn)), rn, mn)

def Auth.ra.hosts(+rh: String, +mh: String) -> Bool:
  Auth.ra.cmp(Bool.or(String.is_empty(rh), String.is_empty(mh)), String.eq(rh, mh), Url.hostname(rh), Url.hostname(mh))

def Auth.ra.go(r: Url, m: Url) -> Bool:
  match r m:
    case Url{rs, ra, rr} Url{ms, ma, mr}:
      Auth.ra.hosts(String.to_lower(Url.hostport(ra)), String.to_lower(Url.hostport(ma)))

# distribution's realmAllowed(remote, realm): the realm's Host is the
# remote's (case-insensitive), or both hostnames share a registrable
# domain and neither is an IP literal or localhost.
def Auth.realm_allowed(+remote: String, +realm: String) -> Bool:
  Auth.ra.go(Url.parse(remote), Url.parse(realm))

def Auth.is_https(+u: String) -> Bool:
  String.eq(Url.origin_scheme(Url.parse(u)), "https")

# The mirror sends a token request only to an allowed https realm.
def Auth.realm_ok(+remote: String, +realm: String) -> Bool:
  Bool.and(Auth.is_https(realm), Auth.realm_allowed(remote, realm))

def Auth.pick.ok(ok: Bool, b: Bearer, rest: Maybe<&2, Bearer>) -> Maybe<&2, Bearer>:
  match ok:
    case True{}:
      Some{b}
    case False{}:
      rest

def Auth.pick.one(m: Maybe<&2, Bearer>, +remote: String, rest: Maybe<&2, Bearer>) -> Maybe<&2, Bearer>:
  match m:
    case None{}:
      rest
    case Some{+b}:
      Auth.pick.ok(Auth.realm_ok(remote, Auth.realm(b)), b, rest)

# The first Bearer challenge of a 401's WWW-Authenticate values whose realm
# is allowed for the remote (distribution's filtering challenge manager
# drops the others).
def Auth.pick(+remote: String, hs: List<&2, String>) -> Maybe<&2, Bearer>:
  match hs:
    case Nil{}:
      None{}
    case Con{h, t}:
      Auth.pick.one(Auth.bearer(h), remote, Auth.pick(remote, t))

# Token request
# -------------

def Auth.hexd.go(lt: Bool, +d: U32) -> U32:
  match lt:
    case True{}:
      (d + 48 : U32)
    case False{}:
      (d + 55 : U32)

def Auth.hexd(+d: U32) -> Char:
  Chr{Auth.hexd.go(U32.is_lt(d, 10), d)}

def Auth.pct(+b: U32) -> String:
  SCon{Chr{37}, SCon{Auth.hexd((b / 16 : U32)), SCon{Auth.hexd((b % 16 : U32)), SNil{}}}}

def Auth.pcts(bs: List<&2, U32>) -> String:
  match bs:
    case Nil{}:
      SNil{}
    case Con{b, t}:
      String.append(Auth.pct(b), Auth.pcts(t))

def Auth.utf8.go(a: Bool, b: Bool, c: Bool, +u: U32) -> List<&2, U32>:
  match a b c:
    case True{} _ _:
      [u]
    case False{} True{} _:
      [(192 + (u / 64 : U32) : U32), (128 + (u % 64 : U32) : U32)]
    case False{} False{} True{}:
      [(224 + (u / 4096 : U32) : U32), (128 + ((u / 64 : U32) % 64 : U32) : U32), (128 + (u % 64 : U32) : U32)]
    case False{} False{} False{}:
      [(240 + (u / 262144 : U32) : U32), (128 + ((u / 4096 : U32) % 64 : U32) : U32),
        (128 + ((u / 64 : U32) % 64 : U32) : U32), (128 + (u % 64 : U32) : U32)]

# The UTF-8 bytes of a code point.
def Auth.utf8(+u: U32) -> List<&2, U32>:
  Auth.utf8.go(U32.is_lt(u, 128), U32.is_lt(u, 2048), U32.is_lt(u, 65536), u)

# RFC 3986 unreserved: ALPHA / DIGIT / "-" / "." / "_" / "~".
def Auth.unreserved(+u: U32) -> Bool:
  Auth.in(u, 65, 90) || Auth.in(u, 97, 122) || Auth.in(u, 48, 57) || U32.is_eq(u, 45) || U32.is_eq(u, 46) || U32.is_eq(u, 95) || U32.is_eq(u, 126)

def Auth.qesc.c(unres: Bool, sp: Bool, +u: U32) -> String:
  match unres sp:
    case True{} _:
      SCon{Chr{u}, SNil{}}
    case False{} True{}:
      "+"
    case False{} False{}:
      Auth.pcts(Auth.utf8(u))

# Go's url.QueryEscape.
def Auth.qesc(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{Chr{+u}, t}:
      String.append(Auth.qesc.c(Auth.unreserved(u), U32.is_eq(u, 32), u), Auth.qesc(t))

def Auth.scope_qs(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      Con{"scope=" ++ Auth.qesc(x), Auth.scope_qs(t)}

def Auth.service_qs.go(empty: Bool, sv: String) -> List<&2, String>:
  match empty:
    case True{}:
      Nil{}
    case False{}:
      ["service=" ++ Auth.qesc(sv)]

def Auth.service_qs(+sv: String) -> List<&2, String>:
  Auth.service_qs.go(String.is_empty(sv), sv)

def Auth.token_url.fin(nq: Bool, hasq: Bool, q: String, r: String) -> String:
  match nq hasq:
    case True{} _:
      r
    case False{} True{}:
      r ++ "&" ++ q
    case False{} False{}:
      r ++ "?" ++ q

def Auth.token_url.go(+q: String, +r: String) -> String:
  Auth.token_url.fin(String.is_empty(q), String.contains(r, "?"), q, r)

# The anonymous token request: GET this URL (containerd's FetchToken with
# no secret and no refresh token). A realm that has a query keeps it, and
# the parameters follow it.
def Auth.token_url(b: Bearer) -> String:
  match b:
    case Bearer{r, sv, sc}:
      Auth.token_url.go(String.join(List.append(&2, String, Auth.scope_qs(sc), Auth.service_qs(sv)), "&"), r)

# Token response
# --------------

# The token's lifetime: expires_in, at least 60 seconds (a missing
# expires_in counts as 0).
def Auth.lifetime.go(short: Bool, e: U32) -> U32:
  match short:
    case True{}:
      60
    case False{}:
      e

def Auth.lifetime(+e: U32) -> U32:
  Auth.lifetime.go(U32.is_lt(e, 60), e)

def Auth.js.ws(+u: U32) -> Bool:
  U32.is_eq(u, 32) || U32.is_eq(u, 9) || U32.is_eq(u, 10) || U32.is_eq(u, 13)

def Auth.js.bad(g: Got) -> Js:
  Js{15n, 0, "", "", g}

# Modes: 0 start, 1 in the object (before a key), 2 key, 3 key escape,
# 4 before ":", 5 before a value, 6 string value, 7 string escape, 8 number,
# 9 nested value, 10 string in a nested value, 11 escape there, 12 literal
# (true, false, null), 13 after a value, 14 end, 15 bad.

def Auth.js.m0(ws: Bool, open: Bool, g: Got) -> Js:
  match ws open:
    case True{} _:
      Js{0n, 0, "", "", g}
    case False{} True{}:
      Js{1n, 0, "", "", g}
    case False{} False{}:
      Auth.js.bad(g)

def Auth.js.m1(ws: Bool, quote: Bool, close: Bool, comma: Bool, g: Got) -> Js:
  match ws quote close comma:
    case True{} _ _ _:
      Js{1n, 0, "", "", g}
    case False{} True{} _ _:
      Js{2n, 0, "", "", g}
    case False{} False{} True{} _:
      Js{14n, 0, "", "", g}
    case False{} False{} False{} True{}:
      Js{1n, 0, "", "", g}
    case False{} False{} False{} False{}:
      Auth.js.bad(g)

def Auth.js.m2(quote: Bool, bs: Bool, +u: U32, k: String, g: Got) -> Js:
  match quote bs:
    case True{} _:
      Js{4n, 0, k, "", g}
    case False{} True{}:
      Js{3n, 0, k, "", g}
    case False{} False{}:
      Js{2n, 0, Auth.add(u, k), "", g}

def Auth.js.m4(ws: Bool, colon: Bool, k: String, g: Got) -> Js:
  match ws colon:
    case True{} _:
      Js{4n, 0, k, "", g}
    case False{} True{}:
      Js{5n, 0, k, "", g}
    case False{} False{}:
      Auth.js.bad(g)

def Auth.js.m5(ws: Bool, quote: Bool, num: Bool, nest: Bool, lit: Bool, +u: U32, k: String, g: Got) -> Js:
  match ws quote num nest lit:
    case True{} _ _ _ _:
      Js{5n, 0, k, "", g}
    case False{} True{} _ _ _:
      Js{6n, 0, k, "", g}
    case False{} False{} True{} _ _:
      Js{8n, 0, k, Auth.add(u, ""), g}
    case False{} False{} False{} True{} _:
      Js{9n, 1, k, "", g}
    case False{} False{} False{} False{} True{}:
      Js{12n, 0, k, "", g}
    case False{} False{} False{} False{} False{}:
      Auth.js.bad(g)

# A string value ends: keep it under token or access_token; a string
# expires_in is a type error (Go's decoder fails), the rest is skipped.
def Auth.js.cs.go(is_t: Bool, is_a: Bool, is_e: Bool, v: String, t: String, a: String, e: U32) -> Js:
  match is_t is_a is_e:
    case True{} _ _:
      Js{13n, 0, "", "", Got{v, a, e}}
    case False{} True{} _:
      Js{13n, 0, "", "", Got{t, v, e}}
    case False{} False{} True{}:
      Js{15n, 0, "", "", Got{t, a, e}}
    case False{} False{} False{}:
      Js{13n, 0, "", "", Got{t, a, e}}

def Auth.js.cs(+k: String, v: String, g: Got) -> Js:
  match g:
    case Got{t, a, e}:
      Auth.js.cs.go(String.eq(k, "token"), String.eq(k, "access_token"), String.eq(k, "expires_in"), v, t, a, e)

def Auth.js.m6(quote: Bool, bs: Bool, +u: U32, k: String, v: String, g: Got) -> Js:
  match quote bs:
    case True{} _:
      Auth.js.cs(String.reverse(k), String.reverse(v), g)
    case False{} True{}:
      Js{7n, 0, k, v, g}
    case False{} False{}:
      Js{6n, 0, k, Auth.add(u, v), g}

def Auth.js.unesc.go(n: Bool, t: Bool, r: Bool, b: Bool, f: Bool, +u: U32) -> U32:
  match n t r b f:
    case True{} _ _ _ _:
      10
    case False{} True{} _ _ _:
      9
    case False{} False{} True{} _ _:
      13
    case False{} False{} False{} True{} _:
      8
    case False{} False{} False{} False{} True{}:
      12
    case False{} False{} False{} False{} False{}:
      u

# The character a JSON escape stands for (\uXXXX is kept as "u" and its
# digits: tokens are base64url and never carry one).
def Auth.js.unesc(+u: U32) -> U32:
  Auth.js.unesc.go(U32.is_eq(u, 110), U32.is_eq(u, 116), U32.is_eq(u, 114), U32.is_eq(u, 98), U32.is_eq(u, 102), u)

def Auth.js.int.go(ok: Bool, neg: Bool, b: String) -> Maybe<&2, U32>:
  match ok neg:
    case False{} _:
      None{}
    case True{} True{}:
      Some{0}
    case True{} False{}:
      U32.read(b)

def Auth.js.int.body(neg: Bool, +b: String) -> Maybe<&2, U32>:
  Auth.js.int.go(Bool.and(Bool.not(String.is_empty(b)), Auth.all_digits(b)), neg, b)

def Auth.js.int.sign(neg: Bool, +s: String) -> Maybe<&2, U32>:
  match neg:
    case True{}:
      Auth.js.int.body(True{}, String.drop(s, 1n))
    case False{}:
      Auth.js.int.body(False{}, s)

# A JSON integer for an int field: a negative one counts as 0 (the
# lifetime floor lifts it); a fraction, an exponent or more than U32 holds
# is None.
def Auth.js.int(+s: String) -> Maybe<&2, U32>:
  Auth.js.int.sign(String.starts_with(s, "-"), s)

def Auth.js.cn.go(is_tok: Bool, is_e: Bool, n: Maybe<&2, U32>, next: Nat, t: String, a: String, e: U32) -> Js:
  match is_tok is_e n:
    case True{} _ _:
      Js{15n, 0, "", "", Got{t, a, e}}
    case False{} True{} None{}:
      Js{15n, 0, "", "", Got{t, a, e}}
    case False{} True{} Some{x}:
      Js{next, 0, "", "", Got{t, a, x}}
    case False{} False{} _:
      Js{next, 0, "", "", Got{t, a, e}}

# A number value ends; next is the mode after it.
def Auth.js.cn(next: Nat, +k: String, v: String, g: Got) -> Js:
  match g:
    case Got{t, a, e}:
      Auth.js.cn.go(Bool.or(String.eq(k, "token"), String.eq(k, "access_token")), String.eq(k, "expires_in"),
        Auth.js.int(v), next, t, a, e)

def Auth.js.numc(+u: U32) -> Bool:
  Auth.is_digit(u) || U32.is_eq(u, 46) || U32.is_eq(u, 101) || U32.is_eq(u, 69) || U32.is_eq(u, 43) || U32.is_eq(u, 45)

def Auth.js.m8(numc: Bool, ws: Bool, comma: Bool, close: Bool, +u: U32, k: String, v: String, g: Got) -> Js:
  match numc ws comma close:
    case True{} _ _ _:
      Js{8n, 0, k, Auth.add(u, v), g}
    case False{} True{} _ _:
      Auth.js.cn(13n, String.reverse(k), String.reverse(v), g)
    case False{} False{} True{} _:
      Auth.js.cn(1n, String.reverse(k), String.reverse(v), g)
    case False{} False{} False{} True{}:
      Auth.js.cn(14n, String.reverse(k), String.reverse(v), g)
    case False{} False{} False{} False{}:
      Auth.js.bad(g)

def Auth.js.m9.close(last: Bool, d: U32, g: Got) -> Js:
  match last:
    case True{}:
      Js{13n, 0, "", "", g}
    case False{}:
      Js{9n, (d - 1 : U32), "", "", g}

def Auth.js.m9(quote: Bool, open: Bool, close: Bool, +d: U32, g: Got) -> Js:
  match quote open close:
    case True{} _ _:
      Js{10n, d, "", "", g}
    case False{} True{} _:
      Js{9n, (d + 1 : U32), "", "", g}
    case False{} False{} True{}:
      Auth.js.m9.close(U32.is_le(d, 1), d, g)
    case False{} False{} False{}:
      Js{9n, d, "", "", g}

def Auth.js.m10(quote: Bool, bs: Bool, d: U32, g: Got) -> Js:
  match quote bs:
    case True{} _:
      Js{9n, d, "", "", g}
    case False{} True{}:
      Js{11n, d, "", "", g}
    case False{} False{}:
      Js{10n, d, "", "", g}

def Auth.js.m12(letter: Bool, ws: Bool, comma: Bool, close: Bool, g: Got) -> Js:
  match letter ws comma close:
    case True{} _ _ _:
      Js{12n, 0, "", "", g}
    case False{} True{} _ _:
      Js{13n, 0, "", "", g}
    case False{} False{} True{} _:
      Js{1n, 0, "", "", g}
    case False{} False{} False{} True{}:
      Js{14n, 0, "", "", g}
    case False{} False{} False{} False{}:
      Auth.js.bad(g)

def Auth.js.m13(ws: Bool, comma: Bool, close: Bool, g: Got) -> Js:
  match ws comma close:
    case True{} _ _:
      Js{13n, 0, "", "", g}
    case False{} True{} _:
      Js{1n, 0, "", "", g}
    case False{} False{} True{}:
      Js{14n, 0, "", "", g}
    case False{} False{} False{}:
      Auth.js.bad(g)

def Auth.js.step(st: Js, +u: U32) -> Js:
  match st:
    case Js{m, d, k, v, g}:
      match m:
        case 0n:
          Auth.js.m0(Auth.js.ws(u), U32.is_eq(u, 123), g)
        case 1n:
          Auth.js.m1(Auth.js.ws(u), U32.is_eq(u, 34), U32.is_eq(u, 125), U32.is_eq(u, 44), g)
        case 2n:
          Auth.js.m2(U32.is_eq(u, 34), U32.is_eq(u, 92), u, k, g)
        case 3n:
          Js{2n, 0, Auth.add(u, k), "", g}
        case 4n:
          Auth.js.m4(Auth.js.ws(u), U32.is_eq(u, 58), k, g)
        case 5n:
          Auth.js.m5(Auth.js.ws(u), U32.is_eq(u, 34), Bool.or(Auth.is_digit(u), U32.is_eq(u, 45)),
            Bool.or(U32.is_eq(u, 123), U32.is_eq(u, 91)), Auth.in(u, 97, 122), u, k, g)
        case 6n:
          Auth.js.m6(U32.is_eq(u, 34), U32.is_eq(u, 92), u, k, v, g)
        case 7n:
          Js{6n, 0, k, Auth.add(Auth.js.unesc(u), v), g}
        case 8n:
          Auth.js.m8(Auth.js.numc(u), Auth.js.ws(u), U32.is_eq(u, 44), U32.is_eq(u, 125), u, k, v, g)
        case 9n:
          Auth.js.m9(U32.is_eq(u, 34), Bool.or(U32.is_eq(u, 123), U32.is_eq(u, 91)),
            Bool.or(U32.is_eq(u, 125), U32.is_eq(u, 93)), d, g)
        case 10n:
          Auth.js.m10(U32.is_eq(u, 34), U32.is_eq(u, 92), d, g)
        case 11n:
          Js{10n, d, "", "", g}
        case 12n:
          Auth.js.m12(Auth.in(u, 97, 122), Auth.js.ws(u), U32.is_eq(u, 44), U32.is_eq(u, 125), g)
        case 13n:
          Auth.js.m13(Auth.js.ws(u), U32.is_eq(u, 44), U32.is_eq(u, 125), g)
        case 14n:
          Js{14n, 0, "", "", g}
        case _:
          Auth.js.bad(g)

def Auth.js.run(s: String, st: Js) -> Js:
  match s:
    case SNil{}:
      st
    case SCon{Chr{u}, t}:
      Auth.js.run(t, Auth.js.step(st, u))

def Auth.token.mk(empty: Bool, tok: String, e: U32) -> Maybe<&2, Token>:
  match empty:
    case True{}:
      None{}
    case False{}:
      Some{Token{tok, Auth.lifetime(e)}}

def Auth.token.pick(no_acc: Bool, a: String, t: String) -> String:
  match no_acc:
    case True{}:
      t
    case False{}:
      a

def Auth.token.got(+tok: String, e: U32) -> Maybe<&2, Token>:
  Auth.token.mk(String.is_empty(tok), tok, e)

def Auth.token.end(ok: Bool, g: Got) -> Maybe<&2, Token>:
  match ok:
    case True{}:
      match g:
        case Got{t, +a, e}:
          Auth.token.got(Auth.token.pick(String.is_empty(a), a, t), e)
    case False{}:
      None{}

def Auth.token.fin(st: Js) -> Maybe<&2, Token>:
  match st:
    case Js{m, d, k, v, g}:
      Auth.token.end(Nat.is_eq(m, 14n), g)

# Parse a token response body (one JSON object; what follows it is
# ignored, as Go's json.Decoder does): None when it is not a complete
# object, a field has the wrong type, or it carries no token.
def Auth.token(body: String) -> Maybe<&2, Token>:
  Auth.token.fin(Auth.js.run(body, Js{0n, 0, "", "", Got{"", "", 0}}))

# Redirects
# ---------

# RFC 9110 section 15.4: the redirections that carry a Location.
def Auth.is_redirect(+status: U32) -> Bool:
  U32.is_eq(status, 301) || U32.is_eq(status, 302) || U32.is_eq(status, 303) || U32.is_eq(status, 307) || U32.is_eq(status, 308)

# containerd's CheckRedirect: "stopped after 10 redirects".
def Auth.max_hops() -> U32:
  10

def Auth.has_scheme.go(sp: ASp) -> Bool:
  match sp:
    case ASp{a, b}:
      Bool.and(Bool.not(String.is_empty(a)), String.starts_with(b, ":"))

def Auth.has_scheme(+s: String) -> Bool:
  Auth.has_scheme.go(Url.span(s, 0n))

def Auth.resolve.go(abs: Bool, net: Bool, root: Bool, query: Bool, u: Url, loc: String) -> String:
  match abs net root query:
    case True{} _ _ _:
      loc
    case False{} True{} _ _:
      Url.origin_scheme(u) ++ ":" ++ loc
    case False{} False{} True{} _:
      Url.origin(u) ++ loc
    case False{} False{} False{} True{}:
      Url.origin_path(u) ++ loc
    case False{} False{} False{} False{}:
      Url.origin_dir(u) ++ loc

# A Location resolved against the URL that sent it (RFC 3986 section 5.2:
# absolute, network-path, absolute-path, query-only and relative-path
# references; dot segments are left to the server).
def Auth.resolve(+from: String, +loc: String) -> String:
  Auth.resolve.go(Auth.has_scheme(loc), String.starts_with(loc, "//"), String.starts_with(loc, "/"),
    String.starts_with(loc, "?"), Url.parse(from), loc)

def Auth.redirect.verdict(https: Bool, userinfo: Bool, blocked: Bool, same: Bool, to: String) -> Hop:
  match https userinfo blocked:
    case False{} _ _:
      Refuse{"redirect to a non-https URL"}
    case True{} True{} _:
      Refuse{"redirect URL carries credentials"}
    case True{} False{} True{}:
      Refuse{"redirect to a private, loopback or local host"}
    case True{} False{} False{}:
      Follow{to, same}

def Auth.redirect.check.go(u: Url, +from: String, +to: String) -> Hop:
  match u:
    case Url{sc, +au, r}:
      Auth.redirect.verdict(String.eq(sc, "https"), String.contains(au, "@"), Auth.blocked_host(Url.host(au)),
        Auth.same_origin(from, to), to)

def Auth.redirect.check(+from: String, +to: String) -> Hop:
  Auth.redirect.check.go(Url.parse(to), from, to)

def Auth.redirect.to(empty: Bool, +from: String, +loc: String) -> Hop:
  match empty:
    case True{}:
      Refuse{"redirect without a Location"}
    case False{}:
      Auth.redirect.check(from, Auth.resolve(from, loc))

def Auth.redirect.lim(over: Bool, +from: String, +loc: String) -> Hop:
  match over:
    case True{}:
      Refuse{"stopped after 10 redirects"}
    case False{}:
      Auth.redirect.to(String.is_empty(loc), from, loc)

# Follow a redirect? hops: redirects already followed for this request;
# from: the URL that answered 3xx; loc: its Location header.
def Auth.redirect(+hops: U32, +from: String, +loc: String) -> Hop:
  Auth.redirect.lim(U32.is_ge(hops, Auth.max_hops()), from, loc)
