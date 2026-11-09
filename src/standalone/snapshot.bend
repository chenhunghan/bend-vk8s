import Base
import ../lib/sha256.bend as H

# vcluster's open snapshot and restore archive (pkg/snapshot,
# cmd/vclusterctl/cmd/snapshot, pkg/cli/snapshot_helm.go,
# pkg/cli/restore_helm.go), as pure functions over byte lists.
#
# The archive is a gzip stream (level 3) of a tar stream. Each tar entry is
# one record: its name is an etcd key or a metadata key under
# /vcluster/snapshot/, and its data is the value. This module encodes and
# decodes the tar stream byte for byte as Go's archive/tar writes and reads
# it (tar.Header{Typeflag: TypeReg, Name: key, Size: len(value), Mode: 0666},
# the USTAR format, a USTAR prefix split for long names, a PAX path record
# when USTAR cannot hold the name, two zero blocks at the end).
#
# Gzip framing needs deflate and CRC-32, so host code does it: it gunzips the
# object before Snap.Tar.decode and gzips Snap.Tar.encode's bytes at level 3.
#
# The archive layout (client.go):
# - an etcd snapshot (embedded etcd store): the optional release
#   (/vcluster/snapshot/release), the optional request
#   (/vcluster/snapshot/request/v1beta1), the raw bolt database
#   (/vcluster/snapshot/db), then the optional skip keys
#   (/vcluster/snapshot/skipkeys, a JSON object).
# - a key/value snapshot (every other store): the optional release and
#   request, the revision (/vcluster/snapshot/revision, decimal), then one
#   record per etcd key under "/", minus the metadata keys and skip keys.
# A restore reads the kind from the first entries (getSnapshotArchiveKind),
# converts an etcd archive for a store that is not embedded etcd, and puts
# the key/value records back in archive order (Snap.restore_plan).
#
# Deviations from Go's archive/tar, all on input Go itself never writes:
# - The decoder does not read base-256 sizes (sizes of 8 GiB and more) and
#   interprets only the path and size PAX records. GNU sparse files are
#   read as regular files. PAX headers have no 1 MiB limit.
# - The encoder refuses a value of 8 GiB or more (Go switches to PAX).
# - Error texts quote non-ASCII bytes as \x escapes.

# Bytes
# -----

# The UTF-8 bytes of a string.
def Snap.b(s: String) -> +List<U32>:
  H.Sha256.utf8(s)

# A string of the bytes of a list, one char per byte (Go's string(b) for
# ASCII).
def Snap.s(bs: +List<U32>) -> String:
  match bs:
    case Nil{}:
      SNil{}
    case c <> t:
      SCon{Chr{c}, Snap.s(t)}

# Go: bytes.Equal(a, b).
def Snap.beq(a: +List<U32>, b: +List<U32>) -> Bool:
  match a b:
    case Nil{} Nil{}:
      True{}
    case Nil{} Con{y, ys}:
      False{}
    case Con{x, xs} Nil{}:
      False{}
    case Con{x, xs} Con{y, ys}:
      U32.is_eq(x, y) && Snap.beq(xs, ys)

def Snap.bprefix.go(p: +List<U32>, s: +List<U32>) -> Bool:
  match p s:
    case Nil{} _:
      True{}
    case Con{x, xs} Nil{}:
      False{}
    case Con{x, xs} Con{y, ys}:
      U32.is_eq(x, y) && Snap.bprefix.go(xs, ys)

# Go: strings.HasPrefix(s, p).
def Snap.bprefix(s: +List<U32>, p: +List<U32>) -> Bool:
  Snap.bprefix.go(p, s)

# n zero bytes.
def Snap.zeros(n: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      0 <> Snap.zeros(p)

def Snap.app(a: +List<U32>, b: +List<U32>) -> +List<U32>:
  List.append(&2, U32, a, b)

def Snap.ends_slash.go(t: +List<U32>, c: U32) -> Bool:
  match t:
    case Nil{}:
      U32.is_eq(c, 47)
    case Con{d, u}:
      Snap.ends_slash.go(u, d)

# Go: s[len(s)-1] == '/' for a non-empty s.
def Snap.ends_slash(bs: +List<U32>) -> Bool:
  match bs:
    case Nil{}:
      False{}
    case Con{c, t}:
      Snap.ends_slash.go(t, c)

# Go: bytes.IndexByte(s, 0) >= 0.
def Snap.has_nul(bs: +List<U32>) -> Bool:
  match bs:
    case Nil{}:
      False{}
    case Con{c, t}:
      U32.is_eq(c, 0) || Snap.has_nul(t)

# One byte of archive/tar's isASCII: below 0x80 and not NUL.
def Snap.ascii1(+c: U32) -> Bool:
  U32.is_lt(c, 128) && Bool.not(U32.is_eq(c, 0))

# Go archive/tar isASCII(s).
def Snap.is_ascii(bs: +List<U32>) -> Bool:
  match bs:
    case Nil{}:
      True{}
    case Con{c, t}:
      Snap.ascii1(c) && Snap.is_ascii(t)

def Snap.to_ascii.put(keep: Bool, c: U32, rest: +List<U32>) -> +List<U32>:
  match keep:
    case True{}:
      c <> rest
    case False{}:
      rest

# Go archive/tar toASCII(s): s without its NUL and non-ASCII bytes.
def Snap.to_ascii(bs: +List<U32>) -> +List<U32>:
  match bs:
    case Nil{}:
      Nil{}
    case Con{+c, t}:
      Snap.to_ascii.put(Snap.ascii1(c), c, Snap.to_ascii(t))

# Octal and decimal digits
# ------------------------

# An octal digit. Numbers are little-endian lists of digits, so that a
# count is a structural increment (Snap.Oct.inc).
type Snap.Oct is Data:
  O0{}
  O1{}
  O2{}
  O3{}
  O4{}
  O5{}
  O6{}
  O7{}

def Snap.Oct.inc(ds: List<&2, Snap.Oct>) -> List<&2, Snap.Oct>:
  match ds:
    case Nil{}:
      [O1{}]
    case Con{O0{}, t}:
      O1{} <> t
    case Con{O1{}, t}:
      O2{} <> t
    case Con{O2{}, t}:
      O3{} <> t
    case Con{O3{}, t}:
      O4{} <> t
    case Con{O4{}, t}:
      O5{} <> t
    case Con{O5{}, t}:
      O6{} <> t
    case Con{O6{}, t}:
      O7{} <> t
    case Con{O7{}, t}:
      O0{} <> Snap.Oct.inc(t)

# The octal digits of the length of a list.
def Snap.Oct.count(xs: +List<U32>) -> List<&2, Snap.Oct>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      Snap.Oct.inc(Snap.Oct.count(t))

def Snap.Oct.ascii(o: Snap.Oct) -> U32:
  match o:
    case O0{}:
      48
    case O1{}:
      49
    case O2{}:
      50
    case O3{}:
      51
    case O4{}:
      52
    case O5{}:
      53
    case O6{}:
      54
    case O7{}:
      55

# n plus the digit's value.
def Snap.Oct.add(o: Snap.Oct, n: Nat) -> Nat:
  match o:
    case O0{}:
      n
    case O1{}:
      1n+n
    case O2{}:
      2n+n
    case O3{}:
      3n+n
    case O4{}:
      4n+n
    case O5{}:
      5n+n
    case O6{}:
      6n+n
    case O7{}:
      7n+n

# 8 * n.
def Snap.n8(n: Nat) -> Nat:
  match n:
    case 0n:
      0n
    case 1n+p:
      8n+Snap.n8(p)

# The value of little-endian octal digits.
def Snap.Oct.val(ds: List<&2, Snap.Oct>) -> Nat:
  match ds:
    case Nil{}:
      0n
    case Con{o, t}:
      Snap.Oct.add(o, Snap.n8(Snap.Oct.val(t)))

# The ASCII digits of little-endian digits, most significant first, before
# acc.
def Snap.Oct.rbytes(ds: List<&2, Snap.Oct>, acc: +List<U32>) -> +List<U32>:
  match ds:
    case Nil{}:
      acc
    case Con{o, t}:
      Snap.Oct.rbytes(t, Snap.Oct.ascii(o) <> acc)

def Snap.Oct.digit.if(hit: Bool, o: Snap.Oct, rest: Snap.Oct) -> Snap.Oct:
  match hit:
    case True{}:
      o
    case False{}:
      rest

# The octal digit of an ASCII byte (O0 for a byte that is no digit).
def Snap.Oct.digit(+c: U32) -> Snap.Oct:
  Snap.Oct.digit.if(U32.is_eq(c, 49), O1{},
  Snap.Oct.digit.if(U32.is_eq(c, 50), O2{},
  Snap.Oct.digit.if(U32.is_eq(c, 51), O3{},
  Snap.Oct.digit.if(U32.is_eq(c, 52), O4{},
  Snap.Oct.digit.if(U32.is_eq(c, 53), O5{},
  Snap.Oct.digit.if(U32.is_eq(c, 54), O6{},
  Snap.Oct.digit.if(U32.is_eq(c, 55), O7{}, O0{})))))))

# '0' <= c && c <= '7'.
def Snap.Oct.is_digit(+c: U32) -> Bool:
  U32.is_ge(c, 48) && U32.is_le(c, 55)

def Snap.chk(ok: Bool, r: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match ok:
    case True{}:
      r
    case False{}:
      None{}

# Go strconv.ParseUint(s, 8, 64) on a non-empty s, after acc: the value of
# the octal digits, or None.
def Snap.Oct.parse(bs: +List<U32>, acc: Nat) -> Maybe<&2, Nat>:
  match bs:
    case Nil{}:
      Some{acc}
    case Con{+c, t}:
      Snap.chk(Snap.Oct.is_digit(c), Snap.Oct.parse(t, Snap.Oct.add(Snap.Oct.digit(c), Snap.n8(acc))))

# A decimal digit, little-endian as Snap.Oct.
type Snap.Dec is Data:
  D0{}
  D1{}
  D2{}
  D3{}
  D4{}
  D5{}
  D6{}
  D7{}
  D8{}
  D9{}

def Snap.Dec.inc(ds: List<&2, Snap.Dec>) -> List<&2, Snap.Dec>:
  match ds:
    case Nil{}:
      [D1{}]
    case Con{D0{}, t}:
      D1{} <> t
    case Con{D1{}, t}:
      D2{} <> t
    case Con{D2{}, t}:
      D3{} <> t
    case Con{D3{}, t}:
      D4{} <> t
    case Con{D4{}, t}:
      D5{} <> t
    case Con{D5{}, t}:
      D6{} <> t
    case Con{D6{}, t}:
      D7{} <> t
    case Con{D7{}, t}:
      D8{} <> t
    case Con{D8{}, t}:
      D9{} <> t
    case Con{D9{}, t}:
      D0{} <> Snap.Dec.inc(t)

# The decimal digits of n (none for 0).
def Snap.Dec.of_nat(n: Nat) -> List<&2, Snap.Dec>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Snap.Dec.inc(Snap.Dec.of_nat(p))

def Snap.Dec.ascii(d: Snap.Dec) -> U32:
  match d:
    case D0{}:
      48
    case D1{}:
      49
    case D2{}:
      50
    case D3{}:
      51
    case D4{}:
      52
    case D5{}:
      53
    case D6{}:
      54
    case D7{}:
      55
    case D8{}:
      56
    case D9{}:
      57

def Snap.Dec.add(d: Snap.Dec, n: Nat) -> Nat:
  match d:
    case D0{}:
      n
    case D1{}:
      1n+n
    case D2{}:
      2n+n
    case D3{}:
      3n+n
    case D4{}:
      4n+n
    case D5{}:
      5n+n
    case D6{}:
      6n+n
    case D7{}:
      7n+n
    case D8{}:
      8n+n
    case D9{}:
      9n+n

# 10 * n.
def Snap.n10(n: Nat) -> Nat:
  match n:
    case 0n:
      0n
    case 1n+p:
      10n+Snap.n10(p)

def Snap.Dec.val(ds: List<&2, Snap.Dec>) -> Nat:
  match ds:
    case Nil{}:
      0n
    case Con{d, t}:
      Snap.Dec.add(d, Snap.n10(Snap.Dec.val(t)))

def Snap.Dec.rbytes(ds: List<&2, Snap.Dec>, acc: +List<U32>) -> +List<U32>:
  match ds:
    case Nil{}:
      acc
    case Con{d, t}:
      Snap.Dec.rbytes(t, Snap.Dec.ascii(d) <> acc)

def Snap.Dec.itoa.go(ds: List<&2, Snap.Dec>) -> +List<U32>:
  match ds:
    case Nil{}:
      [48]
    case Con{d, t}:
      Snap.Dec.rbytes(Con{d, t}, Nil{})

# Go strconv.Itoa(n) as bytes.
def Snap.Dec.itoa(n: Nat) -> +List<U32>:
  Snap.Dec.itoa.go(Snap.Dec.of_nat(n))

def Snap.Dec.digit.if(hit: Bool, d: Snap.Dec, rest: Snap.Dec) -> Snap.Dec:
  match hit:
    case True{}:
      d
    case False{}:
      rest

def Snap.Dec.digit(+c: U32) -> Snap.Dec:
  Snap.Dec.digit.if(U32.is_eq(c, 49), D1{},
  Snap.Dec.digit.if(U32.is_eq(c, 50), D2{},
  Snap.Dec.digit.if(U32.is_eq(c, 51), D3{},
  Snap.Dec.digit.if(U32.is_eq(c, 52), D4{},
  Snap.Dec.digit.if(U32.is_eq(c, 53), D5{},
  Snap.Dec.digit.if(U32.is_eq(c, 54), D6{},
  Snap.Dec.digit.if(U32.is_eq(c, 55), D7{},
  Snap.Dec.digit.if(U32.is_eq(c, 56), D8{},
  Snap.Dec.digit.if(U32.is_eq(c, 57), D9{}, D0{})))))))))

def Snap.Dec.is_digit(+c: U32) -> Bool:
  U32.is_ge(c, 48) && U32.is_le(c, 57)

# The value of decimal digits after acc, or None.
def Snap.Dec.parse(bs: +List<U32>, acc: Nat) -> Maybe<&2, Nat>:
  match bs:
    case Nil{}:
      Some{acc}
    case Con{+c, t}:
      Snap.chk(Snap.Dec.is_digit(c), Snap.Dec.parse(t, Snap.Dec.add(Snap.Dec.digit(c), Snap.n10(acc))))

def Snap.Dec.parse_int.digits(bs: +List<U32>) -> Maybe<&2, Nat>:
  match bs:
    case Nil{}:
      None{}
    case Con{c, t}:
      Snap.Dec.parse(Con{c, t}, 0n)

def Snap.Dec.parse_int.negative.n(n: Nat) -> Maybe<&2, Nat>:
  match n:
    case 0n:
      Some{0n}
    case 1n+p:
      None{}

# A negative number: only -0 is a natural number.
def Snap.Dec.parse_int.negative(m: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match m:
    case None{}:
      None{}
    case Some{n}:
      Snap.Dec.parse_int.negative.n(n)

def Snap.Dec.parse_int.neg(minus: Bool, c: U32, t: +List<U32>) -> Maybe<&2, Nat>:
  match minus:
    case True{}:
      Snap.Dec.parse_int.negative(Snap.Dec.parse_int.digits(t))
    case False{}:
      Snap.Dec.parse(Con{c, t}, 0n)

def Snap.Dec.parse_int.sign.if(plus: Bool, minus: Bool, c: U32, t: +List<U32>) -> Maybe<&2, Nat>:
  match plus:
    case True{}:
      Snap.Dec.parse_int.digits(t)
    case False{}:
      Snap.Dec.parse_int.neg(minus, c, t)

def Snap.Dec.parse_int.sign(+c: U32, t: +List<U32>) -> Maybe<&2, Nat>:
  Snap.Dec.parse_int.sign.if(U32.is_eq(c, 43), U32.is_eq(c, 45), c, t)

# Go strconv.ParseInt(s, 10, 64) when the result is a natural number:
# an optional sign, then one or more digits. A negative number other than
# -0 is None.
def Snap.Dec.parse_int(bs: +List<U32>) -> Maybe<&2, Nat>:
  match bs:
    case Nil{}:
      None{}
    case Con{c, t}:
      Snap.Dec.parse_int.sign(c, t)

def Snap.Path.segs.add(c: U32, segs: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match segs:
    case Nil{}:
      [[c]]
    case Con{s, r}:
      (c <> s) <> r

# Two byte lists.
type Snap.BB is Data:
  BB{fst: List<&2, U32>, snd: List<&2, U32>}

# Paths (Go's path package)
# -------------------------

def Snap.Path.segs.put(slash: Bool, c: U32, segs: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match slash:
    case True{}:
      Nil{} <> segs
    case False{}:
      Snap.Path.segs.add(c, segs)

# The '/'-separated elements of a path (Go strings.Split(p, "/")).
def Snap.Path.segs(bs: +List<U32>) -> List<&2, List<&2, U32>>:
  match bs:
    case Nil{}:
      [Nil{}]
    case Con{+c, t}:
      Snap.Path.segs.put(U32.is_eq(c, 47), c, Snap.Path.segs(t))

def Snap.Path.is(+s: +List<U32>, p: String) -> Bool:
  Snap.beq(s, Snap.b(p))

def Snap.Path.pop.root(rooted: Bool) -> List<&2, List<&2, U32>>:
  match rooted:
    case True{}:
      Nil{}
    case False{}:
      [Snap.b("..")]

def Snap.Path.pop.top(dotdot: Bool, top: +List<U32>, r: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match dotdot:
    case True{}:
      Snap.b("..") <> top <> r
    case False{}:
      r

def Snap.Path.pop(stack: List<&2, List<&2, U32>>, rooted: Bool) -> List<&2, List<&2, U32>>:
  match stack:
    case Nil{}:
      Snap.Path.pop.root(rooted)
    case Con{+top, r}:
      Snap.Path.pop.top(Snap.Path.is(top, ".."), top, r)

def Snap.Path.step.up(up: Bool, seg: +List<U32>, stack: List<&2, List<&2, U32>>, rooted: Bool) -> List<&2, List<&2, U32>>:
  match up:
    case True{}:
      Snap.Path.pop(stack, rooted)
    case False{}:
      seg <> stack

def Snap.Path.step.if(skip: Bool, up: Bool, seg: +List<U32>, stack: List<&2, List<&2, U32>>, rooted: Bool) -> List<&2, List<&2, U32>>:
  match skip:
    case True{}:
      stack
    case False{}:
      Snap.Path.step.up(up, seg, stack, rooted)

def Snap.Path.step(+seg: +List<U32>, stack: List<&2, List<&2, U32>>, rooted: Bool) -> List<&2, List<&2, U32>>:
  Snap.Path.step.if(List.is_empty(&2, U32, seg) || Snap.Path.is(seg, "."), Snap.Path.is(seg, ".."), seg, stack, rooted)

def Snap.Path.walk(segs: List<&2, List<&2, U32>>, stack: List<&2, List<&2, U32>>, +rooted: Bool) -> List<&2, List<&2, U32>>:
  match segs:
    case Nil{}:
      stack
    case Con{s, r}:
      Snap.Path.walk(r, Snap.Path.step(s, stack, rooted), rooted)

def Snap.Path.join.go(segs: List<&2, List<&2, U32>>, acc: +List<U32>) -> +List<U32>:
  match segs:
    case Nil{}:
      acc
    case Con{s, r}:
      Snap.Path.join.go(r, Snap.app(acc, 47 <> s))

def Snap.Path.join(segs: List<&2, List<&2, U32>>) -> +List<U32>:
  match segs:
    case Nil{}:
      Nil{}
    case Con{s, r}:
      Snap.Path.join.go(r, s)

def Snap.Path.clean.fin(rooted: Bool, body: +List<U32>) -> +List<U32>:
  match rooted body:
    case True{} _:
      47 <> body
    case False{} Nil{}:
      [46]
    case False{} Con{c, t}:
      Con{c, t}

def Snap.Path.clean.go(+bs: +List<U32>, +rooted: Bool) -> +List<U32>:
  Snap.Path.clean.fin(rooted,
    Snap.Path.join(List.reverse(&2, List<&2, U32>, Snap.Path.walk(Snap.Path.segs(bs), Nil{}, rooted))))

# Go path.Clean(p).
def Snap.Path.clean(bs: +List<U32>) -> +List<U32>:
  match bs:
    case Nil{}:
      [46]
    case Con{+c, t}:
      Snap.Path.clean.go(Con{c, t}, U32.is_eq(c, 47))

def Snap.Path.split.pick(hit: Bool, seen: +List<U32>, t: +List<U32>, cut: Maybe<&2, Snap.BB>) -> Maybe<&2, Snap.BB>:
  match hit:
    case True{}:
      Some{BB{List.reverse(&2, U32, seen), t}}
    case False{}:
      cut

def Snap.Path.split.go(bs: +List<U32>, +seen: +List<U32>, cut: Maybe<&2, Snap.BB>) -> Maybe<&2, Snap.BB>:
  match bs:
    case Nil{}:
      cut
    case Con{+c, +t}:
      Snap.Path.split.go(t, c <> seen, Snap.Path.split.pick(U32.is_eq(c, 47), c <> seen, t, cut))

def Snap.Path.split.fin(+bs: +List<U32>, cut: Maybe<&2, Snap.BB>) -> Snap.BB:
  match cut:
    case None{}:
      BB{Nil{}, bs}
    case Some{dw}:
      dw

# Go path.Split(p): the directory up to and with the last '/', and the file.
def Snap.Path.split(+bs: +List<U32>) -> Snap.BB:
  Snap.Path.split.fin(bs, Snap.Path.split.go(bs, Nil{}, None{}))

# Go path.Join(dir, "PaxHeaders.0", file).
def Snap.Path.pax_join(dir: +List<U32>, file: +List<U32>) -> +List<U32>:
  match dir:
    case Nil{}:
      Snap.Path.clean(Snap.app(Snap.b("PaxHeaders.0/"), file))
    case Con{c, t}:
      Snap.Path.clean(Snap.app(Con{c, t}, Snap.app(Snap.b("/PaxHeaders.0/"), file)))

# Tar encoding (Go archive/tar Writer)
# ------------------------------------

# A record of the archive: a tar entry's name (an etcd key or a metadata
# key) and its data.
type Snap.Rec is Data:
  Rec{key: List<&2, U32>, value: List<&2, U32>}

# A field of exactly n bytes: s, cut at n or filled with NULs (Go's
# formatter.formatString without its trailing-slash rule).
def Snap.Tar.field(n: Nat, s: +List<U32>) -> +List<U32>:
  match n s:
    case 0n _:
      Nil{}
    case 1n+p Nil{}:
      0 <> Snap.Tar.field(p, Nil{})
    case 1n+p Con{c, t}:
      c <> Snap.Tar.field(p, t)

# n '0' bytes.
def Snap.Tar.zpad(n: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      48 <> Snap.Tar.zpad(p)

# An octal field of w bytes that holds w-1 digits and a NUL (Go's
# formatter.formatOctal), for digits that fit.
def Snap.Tar.octal(w1: Nat, +ds: List<&2, Snap.Oct>) -> +List<U32>:
  +n = List.length(&2, Snap.Oct, ds)
  Snap.app(Snap.Tar.zpad(Nat.sub(w1, n)), Snap.Oct.rbytes(ds, [0]))

# "0000000\0": a zero in an 8-byte field.
def Snap.Tar.zero8() -> +List<U32>:
  [48, 48, 48, 48, 48, 48, 48, 0]

# "0000666\0": mode 0666.
def Snap.Tar.mode666() -> +List<U32>:
  [48, 48, 48, 48, 54, 54, 54, 0]

# "00000000000\0": a zero in a 12-byte field (the modification time).
def Snap.Tar.zero12() -> +List<U32>:
  [48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 0]

# The header bytes before the checksum: name, mode, uid, gid, size, mtime.
def Snap.Tar.pre(name: +List<U32>, mode: +List<U32>, size: +List<U32>) -> +List<U32>:
  Snap.app(Snap.Tar.field(100n, name),
    Snap.app(mode, Snap.app(Snap.Tar.zero8(), Snap.app(Snap.Tar.zero8(),
      Snap.app(size, Snap.Tar.zero12())))))

# The header bytes after the checksum: type flag, link name, USTAR magic
# and version, user and group names, device numbers, prefix and padding.
def Snap.Tar.post(flag: U32, +dev: +List<U32>, prefix: +List<U32>) -> +List<U32>:
  flag <> Snap.app(Snap.zeros(100n),
    Snap.app([117, 115, 116, 97, 114, 0, 48, 48],
      Snap.app(Snap.zeros(64n), Snap.app(dev, Snap.app(dev,
        Snap.app(Snap.Tar.field(155n, prefix), Snap.zeros(12n)))))))

# Eight spaces: the checksum field while the checksum is summed.
def Snap.Tar.spaces() -> +List<U32>:
  [32, 32, 32, 32, 32, 32, 32, 32]

def Snap.Tar.sum(bs: +List<U32>, acc: U32) -> U32:
  match bs:
    case Nil{}:
      acc
    case Con{b, t}:
      Snap.Tar.sum(t, (acc + b : U32))

# The unsigned checksum of a header (Go's block.computeChecksum, chksum1).
def Snap.Tar.cks(+pre: +List<U32>, +post: +List<U32>) -> U32:
  Snap.Tar.sum(Snap.app(pre, Snap.app(Snap.Tar.spaces(), post)), 0)

def Snap.Tar.odig(+c: U32, n: Nat) -> U32:
  (48 + U32.and(U32.shrn(c, n), 7) : U32)

# The checksum field: six octal digits, a NUL and a space.
def Snap.Tar.cks_field(+c: U32) -> +List<U32>:
  [Snap.Tar.odig(c, 15n), Snap.Tar.odig(c, 12n), Snap.Tar.odig(c, 9n), Snap.Tar.odig(c, 6n),
   Snap.Tar.odig(c, 3n), Snap.Tar.odig(c, 0n), 0, 32]

def Snap.Tar.block.go(+pre: +List<U32>, +post: +List<U32>) -> +List<U32>:
  Snap.app(pre, Snap.app(Snap.Tar.cks_field(Snap.Tar.cks(pre, post)), post))

# A 512-byte header block.
def Snap.Tar.block(name: +List<U32>, mode: +List<U32>, size: +List<U32>, flag: U32, dev: +List<U32>, prefix: +List<U32>) -> +List<U32>:
  Snap.Tar.block.go(Snap.Tar.pre(name, mode, size), Snap.Tar.post(flag, dev, prefix))

# The size field of a value whose length has the octal digits ds.
def Snap.Tar.size(ds: List<&2, Snap.Oct>) -> +List<U32>:
  Snap.Tar.octal(11n, ds)

# The header of a regular file in the USTAR format (Go's writeUSTARHeader).
def Snap.Tar.ustar(name: +List<U32>, prefix: +List<U32>, ds: List<&2, Snap.Oct>) -> +List<U32>:
  Snap.Tar.block(name, Snap.Tar.mode666(), Snap.Tar.size(ds), 48, Snap.Tar.zero8(), prefix)

def Snap.Tar.next.go(p: Nat) -> Nat:
  match p:
    case 0n:
      512n
    case 1n+q:
      1n+q

# The next block countdown: k bytes were left in the block before a byte.
def Snap.Tar.next(k: Nat) -> Nat:
  match k:
    case 0n:
      511n
    case 1n+p:
      Snap.Tar.next.go(p)

# The padding after data that left k bytes in its last block.
def Snap.Tar.pad(full: Bool, k: Nat) -> +List<U32>:
  match full:
    case True{}:
      Nil{}
    case False{}:
      Snap.zeros(k)

# Data, then the zeros up to the next block (k bytes left in this block).
def Snap.Tar.data(xs: +List<U32>, +k: Nat) -> +List<U32>:
  match xs:
    case Nil{}:
      Snap.Tar.pad(Nat.is_eq(k, 512n), k)
    case Con{x, t}:
      x <> Snap.Tar.data(t, Snap.Tar.next(k))

# The two zero blocks that end an archive.
def Snap.Tar.trailer() -> +List<U32>:
  Snap.zeros(1024n)

# How a name goes into a header (Go's Header.allowedFormats).
type Snap.Tar.Name is Data:
  # USTAR, the name as it is.
  NShort{}
  # USTAR, split at a '/' into the prefix and name fields.
  NSplit{prefix: List<&2, U32>, suffix: List<&2, U32>}
  # PAX: a path record before a USTAR header.
  NPax{}
  # Go refuses the header.
  NBad{msg: String}

def Snap.Tar.split.pick(hit: Bool, +seen: +List<U32>, +t: +List<U32>, cut: Maybe<&2, Snap.BB>) -> Maybe<&2, Snap.BB>:
  match hit:
    case True{}:
      Some{BB{seen, t}}
    case False{}:
      cut

# The last '/' before position lim: the bytes before it (reversed) and
# after it.
def Snap.Tar.split.go(bs: +List<U32>, +seen: +List<U32>, +pos: Nat, +lim: Nat, cut: Maybe<&2, Snap.BB>) -> Maybe<&2, Snap.BB>:
  match bs:
    case Nil{}:
      cut
    case Con{+c, +t}:
      Snap.Tar.split.go(t, c <> seen, 1n+pos, lim,
        Snap.Tar.split.pick(U32.is_eq(c, 47) && Nat.is_lt(pos, lim), seen, t, cut))

def Snap.Tar.split.ok(ok: Bool, pr: +List<U32>, s: +List<U32>) -> Maybe<&2, Snap.BB>:
  match ok:
    case True{}:
      Some{BB{List.reverse(&2, U32, pr), s}}
    case False{}:
      None{}

def Snap.Tar.split.check(cut: Maybe<&2, Snap.BB>) -> Maybe<&2, Snap.BB>:
  match cut:
    case None{}:
      None{}
    case Some{BB{+pr, +s}}:
      +np = List.length(&2, U32, pr)
      +ns = List.length(&2, U32, s)
      Snap.Tar.split.ok(Nat.is_gt(np, 0n) && Nat.is_gt(ns, 0n) && Nat.is_le(ns, 100n) && Nat.is_le(np, 155n), pr, s)

def Snap.Tar.split.lim.slash(slash: Bool, n: Nat) -> Nat:
  match slash:
    case True{}:
      Nat.sub(n, 1n)
    case False{}:
      n

def Snap.Tar.split.lim.if(long: Bool, slash: Bool, n: Nat) -> Nat:
  match long:
    case True{}:
      156n
    case False{}:
      Snap.Tar.split.lim.slash(slash, n)

def Snap.Tar.split.lim(+n: Nat, +bs: +List<U32>) -> Nat:
  Snap.Tar.split.lim.if(Nat.is_gt(n, 156n), Snap.ends_slash(bs), n)

# Go archive/tar splitUSTARPath(name) for an ASCII name longer than 100
# bytes: the prefix and the name fields.
def Snap.Tar.split(+bs: +List<U32>) -> Maybe<&2, Snap.BB>:
  Snap.Tar.split.check(Snap.Tar.split.go(bs, Nil{}, 0n, Snap.Tar.split.lim(List.length(&2, U32, bs), bs), None{}))

def Snap.Tar.hexd(+d: U32) -> U32:
  (48 + d + 39 * Bool.to_u32(U32.is_gt(d, 9)) : U32)

def Snap.Tar.quote.hex(+c: U32) -> +List<U32>:
  [92, 120, Snap.Tar.hexd(U32.shrn(c, 4n)), Snap.Tar.hexd(U32.and(c, 15))]

def Snap.Tar.quote.esc.v(v: Bool, +c: U32) -> +List<U32>:
  match v:
    case True{}:
      [92, 118]
    case False{}:
      Snap.Tar.quote.hex(c)

def Snap.Tar.quote.esc.t(t: Bool, v: Bool, +c: U32) -> +List<U32>:
  match t:
    case True{}:
      [92, 116]
    case False{}:
      Snap.Tar.quote.esc.v(v, c)

def Snap.Tar.quote.esc.r(r: Bool, t: Bool, v: Bool, +c: U32) -> +List<U32>:
  match r:
    case True{}:
      [92, 114]
    case False{}:
      Snap.Tar.quote.esc.t(t, v, c)

def Snap.Tar.quote.esc.n(n: Bool, r: Bool, t: Bool, v: Bool, +c: U32) -> +List<U32>:
  match n:
    case True{}:
      [92, 110]
    case False{}:
      Snap.Tar.quote.esc.r(r, t, v, c)

def Snap.Tar.quote.esc.f(f: Bool, n: Bool, r: Bool, t: Bool, v: Bool, +c: U32) -> +List<U32>:
  match f:
    case True{}:
      [92, 102]
    case False{}:
      Snap.Tar.quote.esc.n(n, r, t, v, c)

def Snap.Tar.quote.esc.b(b: Bool, f: Bool, n: Bool, r: Bool, t: Bool, v: Bool, +c: U32) -> +List<U32>:
  match b:
    case True{}:
      [92, 98]
    case False{}:
      Snap.Tar.quote.esc.f(f, n, r, t, v, c)

def Snap.Tar.quote.esc.if(a: Bool, b: Bool, f: Bool, n: Bool, r: Bool, t: Bool, v: Bool, +c: U32) -> +List<U32>:
  match a:
    case True{}:
      [92, 97]
    case False{}:
      Snap.Tar.quote.esc.b(b, f, n, r, t, v, c)

def Snap.Tar.quote.esc(+c: U32) -> +List<U32>:
  Snap.Tar.quote.esc.if(U32.is_eq(c, 7), U32.is_eq(c, 8), U32.is_eq(c, 12), U32.is_eq(c, 10),
    U32.is_eq(c, 13), U32.is_eq(c, 9), U32.is_eq(c, 11), c)

def Snap.Tar.quote.byte.sp(special: Bool, +c: U32) -> +List<U32>:
  match special:
    case True{}:
      [92, c]
    case False{}:
      [c]

def Snap.Tar.quote.byte.if(plain: Bool, special: Bool, +c: U32) -> +List<U32>:
  match plain:
    case True{}:
      Snap.Tar.quote.byte.sp(special, c)
    case False{}:
      Snap.Tar.quote.esc(c)

# One byte of Go's strconv.Quote; bytes past 0x7f are \x escapes.
def Snap.Tar.quote.byte(+c: U32) -> +List<U32>:
  Snap.Tar.quote.byte.if(U32.is_ge(c, 32) && U32.is_lt(c, 127),
    U32.is_eq(c, 34) || U32.is_eq(c, 92), c)

def Snap.Tar.quote.go(bs: +List<U32>) -> +List<U32>:
  match bs:
    case Nil{}:
      [34]
    case Con{+c, t}:
      Snap.app(Snap.Tar.quote.byte(c), Snap.Tar.quote.go(t))

# Go strconv.Quote(s) (%q).
def Snap.Tar.quote(bs: +List<U32>) -> +List<U32>:
  34 <> Snap.Tar.quote.go(bs)

def Snap.Tar.bad_prefix() -> String:
  "archive/tar: cannot encode header: "

def Snap.Tar.name.nul(nul: Bool, +bs: +List<U32>) -> Snap.Tar.Name:
  match nul:
    case True{}:
      NBad{Snap.Tar.bad_prefix() ++ "invalid PAX record: " ++
        Snap.s(Snap.Tar.quote(Snap.app(Snap.b("path = "), bs)))}
    case False{}:
      NPax{}

def Snap.Tar.name.split(cut: Maybe<&2, Snap.BB>, +bs: +List<U32>) -> Snap.Tar.Name:
  match cut:
    case Some{BB{p, s}}:
      NSplit{p, s}
    case None{}:
      Snap.Tar.name.nul(Snap.has_nul(bs), bs)

def Snap.Tar.name.long(ascii: Bool, +bs: +List<U32>) -> Snap.Tar.Name:
  match ascii:
    case True{}:
      Snap.Tar.name.split(Snap.Tar.split(bs), bs)
    case False{}:
      Snap.Tar.name.nul(Snap.has_nul(bs), bs)

def Snap.Tar.name.short(ascii: Bool, +bs: +List<U32>) -> Snap.Tar.Name:
  match ascii:
    case True{}:
      NShort{}
    case False{}:
      Snap.Tar.name.nul(Snap.has_nul(bs), bs)

def Snap.Tar.name.fits(short: Bool, ascii: Bool, +bs: +List<U32>) -> Snap.Tar.Name:
  match short:
    case True{}:
      Snap.Tar.name.short(ascii, bs)
    case False{}:
      Snap.Tar.name.long(ascii, bs)

def Snap.Tar.name.slash(slash: Bool, +bs: +List<U32>) -> Snap.Tar.Name:
  match slash:
    case True{}:
      NBad{Snap.Tar.bad_prefix() ++ "filename may not have trailing slash"}
    case False{}:
      Snap.Tar.name.fits(Nat.is_le(List.length(&2, U32, bs), 100n), Snap.is_ascii(bs), bs)

# How Go writes a regular file's name: a trailing '/' is refused; an ASCII
# name of at most 100 bytes is USTAR; a longer ASCII name that splits at a
# '/' is USTAR with a prefix; any other name is a PAX path record, which Go
# refuses when the name holds a NUL.
def Snap.Tar.name(+bs: +List<U32>) -> Snap.Tar.Name:
  Snap.Tar.name.slash(Snap.ends_slash(bs), bs)

def Snap.Tar.pax_rec.fix(+n: Nat, l3: Nat) -> Bool:
  Nat.is_eq(Nat.add(List.length(&2, U32, Snap.Dec.itoa(n)), l3), n)

def Snap.Tar.pax_rec.pick(fix: Bool, n: Nat) -> Nat:
  match fix:
    case True{}:
      n
    case False{}:
      1n+n

def Snap.Tar.pax_rec.if(ok: Bool, n: Nat, bs: +List<U32>) -> Maybe<&2, List<&2, U32>>:
  match ok:
    case True{}:
      Some{Snap.app(Snap.Dec.itoa(n), Snap.app([32, 112, 97, 116, 104, 61], Snap.app(bs, [10])))}
    case False{}:
      None{}

def Snap.Tar.pax_rec.n(+n: Nat, +l3: Nat, bs: +List<U32>) -> Maybe<&2, List<&2, U32>>:
  Snap.Tar.pax_rec.if(Snap.Tar.pax_rec.fix(n, l3), n, bs)

# The PAX record "<n> path=<name>\n" (Go's formatPAXRecord), whose length n
# counts its own digits. None if the length is not consistent (never, but
# checked so that the decoder's proof gets the equation).
def Snap.Tar.pax_rec(+bs: +List<U32>) -> Maybe<&2, List<&2, U32>>:
  +l3 = Nat.add(7n, List.length(&2, U32, bs))
  +n1 = Nat.add(List.length(&2, U32, Snap.Dec.itoa(l3)), l3)
  Snap.Tar.pax_rec.n(Snap.Tar.pax_rec.pick(Snap.Tar.pax_rec.fix(n1, l3), n1), l3, bs)

def Snap.trim_slash.if(drop: Bool, c: U32, rest: +List<U32>) -> +List<U32>:
  match drop:
    case True{}:
      Nil{}
    case False{}:
      c <> rest

def Snap.trim_slash.put(+c: U32, +rest: +List<U32>) -> +List<U32>:
  Snap.trim_slash.if(List.is_empty(&2, U32, rest) && U32.is_eq(c, 47), c, rest)

def Snap.trim_slash(bs: +List<U32>) -> +List<U32>:
  match bs:
    case Nil{}:
      Nil{}
    case Con{+c, t}:
      Snap.trim_slash.put(c, Snap.trim_slash(t))

def Snap.Tar.pax_hdr_name.go(dw: Snap.BB) -> +List<U32>:
  match dw:
    case BB{d, f}:
      Snap.trim_slash(List.take(&2, U32, Snap.to_ascii(Snap.Path.pax_join(d, f)), 100n))

# The name of a PAX extended header (Go's writePAXHeader and writeRawFile):
# path.Join(dir, "PaxHeaders.0", file), ASCII, cut at 100 bytes, without
# trailing slashes.
def Snap.Tar.pax_hdr_name(+bs: +List<U32>) -> +List<U32>:
  Snap.Tar.pax_hdr_name.go(Snap.Path.split(bs))

def Snap.Tar.pax_name.at(+t: +List<U32>, +s: +List<U32>, last: Bool) -> +List<U32>:
  match last:
    case True{}:
      List.set(&2, U32, t, List.length(&2, U32, Snap.trim_slash(List.take(&2, U32, s, 99n))), 0)
    case False{}:
      Snap.Tar.field(100n, t)

def Snap.Tar.pax_name.long(long: Bool, +s: +List<U32>) -> +List<U32>:
  match long:
    case True{}:
      Snap.Tar.pax_name.at(List.take(&2, U32, s, 100n), s, Snap.ends_slash(List.take(&2, U32, s, 100n)))
    case False{}:
      Snap.Tar.field(100n, s)

# The name field of the header after a PAX path record: the ASCII bytes of
# the name, cut at 100, a NUL over a cut that ends in '/' (Go's
# formatString).
def Snap.Tar.pax_name(+bs: +List<U32>) -> +List<U32>:
  +s = Snap.to_ascii(bs)
  Snap.Tar.pax_name.long(Nat.is_gt(List.length(&2, U32, s), 100n), s)

# The headers and data of a PAX entry: the extended header with the path
# record, then the file's header.
def Snap.Tar.pax(+bs: +List<U32>, rec: List<&2, U32>, +value: +List<U32>) -> +List<U32>:
  +r = rec
  # Both independent header blocks have 512 bytes. Their payloads remain
  # in archive order: the PAX path must precede the regular file header.
  +path_header +file_header = Snap.Tar.block(Snap.Tar.pax_hdr_name(bs), Snap.Tar.zero8(), Snap.Tar.size(Snap.Oct.count(r)), 120, Snap.zeros(8n), Nil{}) Snap.Tar.block(Snap.Tar.pax_name(bs), Snap.Tar.mode666(), Snap.Tar.size(Snap.Oct.count(value)), 48, Snap.Tar.zero8(), Nil{})
  Snap.app(path_header,
    Snap.app(Snap.Tar.data(r, 512n),
      Snap.app(file_header, Snap.Tar.data(value, 512n))))

# The octal digits ds fit an 11-digit size field (Go's fitsInOctal(12, n):
# n < 1<<33). Snap.Oct.count has no leading zeros.
def Snap.Tar.size_fits(+ds: List<&2, Snap.Oct>) -> Bool:
  Nat.is_le(List.length(&2, Snap.Oct, ds), 11n)

# Go's writeRawFile: formatOctal(v7.size(), len(data)) fails with
# ErrFieldTooLong when the PAX record does not fit the size field.
def Snap.Tar.entry.pax.fits(fits: Bool, +bs: +List<U32>, rec: List<&2, U32>, +value: +List<U32>) -> Result<&2, &2, String, List<&2, U32>>:
  match fits:
    case True{}:
      Done{Snap.Tar.pax(bs, rec, value)}
    case False{}:
      Fail{"archive/tar: header field too long"}

def Snap.Tar.entry.pax(r: Maybe<&2, List<&2, U32>>, +bs: +List<U32>, +value: +List<U32>) -> Result<&2, &2, String, List<&2, U32>>:
  match r:
    case None{}:
      Fail{"archive/tar: header field too long"}
    case Some{+rec}:
      Snap.Tar.entry.pax.fits(Snap.Tar.size_fits(Snap.Oct.count(rec)), bs, rec, value)

def Snap.Tar.entry.name(n: Snap.Tar.Name, +bs: +List<U32>, +value: +List<U32>) -> Result<&2, &2, String, List<&2, U32>>:
  match n:
    case NShort{}:
      Done{Snap.app(Snap.Tar.ustar(bs, Nil{}, Snap.Oct.count(value)), Snap.Tar.data(value, 512n))}
    case NSplit{p, s}:
      Done{Snap.app(Snap.Tar.ustar(s, p, Snap.Oct.count(value)), Snap.Tar.data(value, 512n))}
    case NPax{}:
      Snap.Tar.entry.pax(Snap.Tar.pax_rec(bs), bs, value)
    case NBad{msg}:
      Fail{msg}

def Snap.Tar.entry.size(fits: Bool, +bs: +List<U32>, +value: +List<U32>) -> Result<&2, &2, String, List<&2, U32>>:
  match fits:
    case True{}:
      Snap.Tar.entry.name(Snap.Tar.name(bs), bs, value)
    case False{}:
      Fail{"archive/tar: header field too long"}

# One record as Go's writeArchiveEntry writes it: tar.Header{Typeflag:
# TypeReg, Name: key, Size: len(value), Mode: 0666}, then the value.
def Snap.Tar.entry(r: Snap.Rec) -> Result<&2, &2, String, List<&2, U32>>:
  match r:
    case Rec{+k, +v}:
      Snap.Tar.entry.size(Nat.is_le(List.length(&2, Snap.Oct, Snap.Oct.count(v)), 11n), k, v)

def Snap.Tar.encode.cons(+e: List<&2, U32>, r: Result<&2, &2, String, List<&2, U32>>) -> Result<&2, &2, String, List<&2, U32>>:
  match r:
    case Fail{m}:
      Fail{m}
    case Done{t}:
      Done{Snap.app(e, t)}

def Snap.Tar.encode.step(e: Result<&2, &2, String, List<&2, U32>>, t: Result<&2, &2, String, List<&2, U32>>) -> Result<&2, &2, String, List<&2, U32>>:
  match e:
    case Fail{m}:
      Fail{m}
    case Done{bs}:
      Snap.Tar.encode.cons(bs, t)

def Snap.Tar.encode.go(rs: List<&2, Snap.Rec>) -> Result<&2, &2, String, List<&2, U32>>:
  match rs:
    case Nil{}:
      Done{Snap.Tar.trailer()}
    case Con{r, t}:
      Snap.Tar.encode.step(Snap.Tar.entry(r), Snap.Tar.encode.go(t))

# The tar stream of records, as Go's tar.Writer writes it (before gzip), or
# Go's error for the first record it refuses.
def Snap.Tar.encode(rs: List<&2, Snap.Rec>) -> Result<&2, &2, String, List<&2, U32>>:
  Snap.Tar.encode.go(rs)

# Tar decoding (Go archive/tar Reader)
# ------------------------------------

# Go: archive/tar.ErrHeader.
def Snap.Tar.err_header() -> String:
  "archive/tar: invalid tar header"

# Go: io.ErrUnexpectedEOF.
def Snap.Tar.err_eof() -> String:
  "unexpected EOF"

def Snap.Tar.split_at.cons(c: U32, r: Snap.BB) -> Snap.BB:
  match r:
    case BB{a, b}:
      BB{c <> a, b}

def Snap.Tar.split_at(n: Nat, xs: +List<U32>) -> Snap.BB:
  match n xs:
    case 0n _:
      BB{Nil{}, xs}
    case 1n+p Nil{}:
      BB{Nil{}, Nil{}}
    case 1n+p Con{c, t}:
      Snap.Tar.split_at.cons(c, Snap.Tar.split_at(p, t))

def Snap.fst(r: Snap.BB) -> +List<U32>:
  match r:
    case BB{a, b}:
      a

def Snap.snd(r: Snap.BB) -> +List<U32>:
  match r:
    case BB{a, b}:
      b

# Bytes n.. of xs, then their first m.
def Snap.Tar.slice(xs: +List<U32>, n: Nat, m: Nat) -> +List<U32>:
  List.take(&2, U32, List.drop(&2, U32, xs, n), m)

def Snap.Tar.cut_nul.if(nul: Bool, c: U32, rest: +List<U32>) -> +List<U32>:
  match nul:
    case True{}:
      Nil{}
    case False{}:
      c <> rest

# Go archive/tar parser.parseString: the bytes before the first NUL.
def Snap.Tar.cut_nul(bs: +List<U32>) -> +List<U32>:
  match bs:
    case Nil{}:
      Nil{}
    case Con{+c, t}:
      Snap.Tar.cut_nul.if(U32.is_eq(c, 0), c, Snap.Tar.cut_nul(t))

def Snap.Tar.sp_nul(+c: U32) -> Bool:
  U32.is_eq(c, 32) || U32.is_eq(c, 0)

def Snap.Tar.trim_left.if(drop: Bool, c: U32, t: +List<U32>, rest: +List<U32>) -> +List<U32>:
  match drop:
    case True{}:
      rest
    case False{}:
      c <> t

def Snap.Tar.trim_left(bs: +List<U32>) -> +List<U32>:
  match bs:
    case Nil{}:
      Nil{}
    case Con{+c, +t}:
      Snap.Tar.trim_left.if(Snap.Tar.sp_nul(c), c, t, Snap.Tar.trim_left(t))

def Snap.Tar.trim_right.put(+c: U32, +rest: +List<U32>) -> +List<U32>:
  Snap.trim_slash.if(List.is_empty(&2, U32, rest) && Snap.Tar.sp_nul(c), c, rest)

def Snap.Tar.trim_right(bs: +List<U32>) -> +List<U32>:
  match bs:
    case Nil{}:
      Nil{}
    case Con{+c, t}:
      Snap.Tar.trim_right.put(c, Snap.Tar.trim_right(t))

def Snap.Tar.octal.digits(bs: +List<U32>) -> Maybe<&2, Nat>:
  match bs:
    case Nil{}:
      None{}
    case Con{c, t}:
      Snap.Oct.parse(Con{c, t}, 0n)

def Snap.Tar.octal.parse(bs: +List<U32>) -> Maybe<&2, Nat>:
  match bs:
    case Nil{}:
      Some{0n}
    case Con{c, t}:
      Snap.Tar.octal.digits(Snap.Tar.cut_nul(Con{c, t}))

# Go archive/tar parser.parseOctal: spaces and NULs trimmed, empty is 0,
# else the octal digits up to a NUL.
def Snap.Tar.octal_value(+bs: +List<U32>) -> Maybe<&2, Nat>:
  Snap.Tar.octal.parse(Snap.Tar.trim_right(Snap.Tar.trim_left(bs)))

# A base-256 number: its value and whether it is negative.
def Snap.Tar.b256(bs: +List<U32>, acc: Nat) -> Nat:
  match bs:
    case Nil{}:
      acc
    case Con{c, t}:
      Snap.Tar.b256(t, Nat.add(Nat.mul(acc, 256n), U32.to_nat(c)))

def Snap.Tar.numeric.b256(neg: Bool, +c: U32, t: +List<U32>) -> Maybe<&2, Nat>:
  match neg:
    case True{}:
      None{}
    case False{}:
      Some{Snap.Tar.b256(t, U32.to_nat(U32.and(c, 127)))}

def Snap.Tar.numeric.if(bin: Bool, +c: U32, +t: +List<U32>) -> Maybe<&2, Nat>:
  match bin:
    case True{}:
      Snap.Tar.numeric.b256(U32.is_ne(U32.and(c, 64), 0), c, t)
    case False{}:
      Snap.Tar.octal_value(Con{c, t})

# Go archive/tar parser.parseNumeric for a field that must hold a natural
# number: None for a malformed field. A negative base-256 number is None
# too (the decoder then fails only on a negative size; see Snap.Tar.num_ok).
def Snap.Tar.numeric(bs: +List<U32>) -> Maybe<&2, Nat>:
  match bs:
    case Nil{}:
      Some{0n}
    case Con{+c, t}:
      Snap.Tar.numeric.if(U32.is_ne(U32.and(c, 128), 0), c, t)

def Snap.Tar.num_ok.m(m: Maybe<&2, Nat>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{n}:
      True{}

def Snap.Tar.is_b256(bs: +List<U32>) -> Bool:
  match bs:
    case Nil{}:
      False{}
    case Con{c, t}:
      U32.is_ne(U32.and(c, 128), 0)

def Snap.Tar.num_ok.if(bin: Bool, +bs: +List<U32>) -> Bool:
  match bin:
    case True{}:
      True{}
    case False{}:
      Snap.Tar.num_ok.m(Snap.Tar.octal_value(bs))

# A numeric field Go parses without an error (negative base-256 is fine).
def Snap.Tar.num_ok(+bs: +List<U32>) -> Bool:
  Snap.Tar.num_ok.if(Snap.Tar.is_b256(bs), bs)

def Snap.Tar.count_high.add(hi: Bool, acc: Nat) -> Nat:
  match hi:
    case True{}:
      1n+acc
    case False{}:
      acc

def Snap.Tar.count_high(bs: +List<U32>, acc: Nat) -> Nat:
  match bs:
    case Nil{}:
      acc
    case Con{+c, t}:
      Snap.Tar.count_high(t, Snap.Tar.count_high.add(U32.is_ge(c, 128), acc))

def Snap.Tar.cks_ok.m(m: Maybe<&2, Nat>, +c1: Nat, high: Nat) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{+v}:
      Nat.is_eq(v, c1) || Nat.is_eq(Nat.add(v, Nat.mul(high, 256n)), c1)

# Go's block.getFormat checksum test: the field's octal value is the
# unsigned or the signed sum. Fast path first: the field is exactly what
# the writer puts there for the unsigned sum.
def Snap.Tar.cks_ok(+field: +List<U32>, +pre: +List<U32>, +post: +List<U32>) -> Bool:
  +c1 = Snap.Tar.cks(pre, post)
  Snap.beq(field, Snap.Tar.cks_field(c1)) ||
    Snap.Tar.cks_ok.m(Snap.Tar.octal_value(field), U32.to_nat(c1),
      Snap.Tar.count_high(Snap.app(pre, post), 0n))

# A parsed header: its type flag, its name (with the USTAR prefix) and size.
type Snap.Tar.Hdr is Data:
  Hdr{flag: U32, name: List<&2, U32>, size: Nat}

# The header format by magic (Go's block.getFormat).
type Snap.Tar.Fmt is Data:
  FV7{}
  FUstar{}
  FStar{}
  FGnu{}

def Snap.Tar.fmt.star(star: Bool) -> Snap.Tar.Fmt:
  match star:
    case True{}:
      FStar{}
    case False{}:
      FUstar{}

def Snap.Tar.fmt.gnu(gnu: Bool) -> Snap.Tar.Fmt:
  match gnu:
    case True{}:
      FGnu{}
    case False{}:
      FV7{}

def Snap.Tar.fmt.if(ustar: Bool, gnu: Bool, star: Bool) -> Snap.Tar.Fmt:
  match ustar:
    case True{}:
      Snap.Tar.fmt.star(star)
    case False{}:
      Snap.Tar.fmt.gnu(gnu)

# The format of a header from the bytes after its checksum.
def Snap.Tar.fmt(+post: +List<U32>) -> Snap.Tar.Fmt:
  +magic = Snap.Tar.slice(post, 101n, 6n)
  Snap.Tar.fmt.if(Snap.beq(magic, [117, 115, 116, 97, 114, 0]),
    Snap.beq(magic, [117, 115, 116, 97, 114, 32]) && Snap.beq(Snap.Tar.slice(post, 107n, 2n), [32, 0]),
    Snap.beq(Snap.Tar.slice(post, 352n, 4n), [116, 97, 114, 0]))

def Snap.Tar.join.if(empty: Bool, prefix: +List<U32>, name: +List<U32>) -> +List<U32>:
  match empty:
    case True{}:
      name
    case False{}:
      Snap.app(prefix, 47 <> name)

# Go: if len(prefix) > 0 { name = prefix + "/" + name }.
def Snap.Tar.join(+prefix: +List<U32>, name: +List<U32>) -> +List<U32>:
  Snap.Tar.join.if(List.is_empty(&2, U32, prefix), prefix, name)

def Snap.Tar.gnu_prefix.ascii.if(ok: Bool, p: +List<U32>) -> +List<U32>:
  match ok:
    case True{}:
      p
    case False{}:
      Nil{}

def Snap.Tar.gnu_prefix.ascii(+p: +List<U32>) -> +List<U32>:
  Snap.Tar.gnu_prefix.ascii.if(Snap.is_ascii(p), p)

def Snap.Tar.gnu_prefix.if(times_ok: Bool, +post: +List<U32>) -> +List<U32>:
  match times_ok:
    case True{}:
      Nil{}
    case False{}:
      Snap.Tar.gnu_prefix.ascii(Snap.Tar.cut_nul(Snap.Tar.slice(post, 189n, 155n)))

def Snap.Tar.first_zero(bs: +List<U32>) -> Bool:
  match bs:
    case Nil{}:
      True{}
    case Con{c, t}:
      U32.is_eq(c, 0)

def Snap.Tar.gnu_time_ok.if(zero: Bool, +b: +List<U32>) -> Bool:
  match zero:
    case True{}:
      True{}
    case False{}:
      Snap.Tar.num_ok(b)

def Snap.Tar.gnu_time_ok(+b: +List<U32>) -> Bool:
  Snap.Tar.gnu_time_ok.if(Snap.Tar.first_zero(b), b)

# The USTAR prefix by format: 155 bytes for USTAR and PAX, 131 for star,
# and for GNU only the pre-Go 1.8 fallback (atime or ctime unreadable and
# the prefix field ASCII).
def Snap.Tar.prefix(f: Snap.Tar.Fmt, +post: +List<U32>) -> +List<U32>:
  match f:
    case FV7{}:
      Nil{}
    case FUstar{}:
      Snap.Tar.cut_nul(Snap.Tar.slice(post, 189n, 155n))
    case FStar{}:
      Snap.Tar.cut_nul(Snap.Tar.slice(post, 189n, 131n))
    case FGnu{}:
      Snap.Tar.gnu_prefix.if(Snap.Tar.gnu_time_ok(Snap.Tar.slice(post, 189n, 12n)) &&
        Snap.Tar.gnu_time_ok(Snap.Tar.slice(post, 201n, 12n)), post)

def Snap.Tar.is_v7(f: Snap.Tar.Fmt) -> Bool:
  match f:
    case FV7{}:
      True{}
    case FUstar{}:
      False{}
    case FStar{}:
      False{}
    case FGnu{}:
      False{}

# The numeric fields Go parses: mode, uid, gid, mtime, and for any format
# but V7 the device numbers.
def Snap.Tar.nums_ok(+v7: Bool, +pre: +List<U32>, +post: +List<U32>) -> Bool:
  Snap.Tar.num_ok(Snap.Tar.slice(pre, 100n, 8n)) && Snap.Tar.num_ok(Snap.Tar.slice(pre, 108n, 8n)) &&
    Snap.Tar.num_ok(Snap.Tar.slice(pre, 116n, 8n)) && Snap.Tar.num_ok(Snap.Tar.slice(pre, 136n, 12n)) &&
    (v7 || (Snap.Tar.num_ok(Snap.Tar.slice(post, 173n, 8n)) && Snap.Tar.num_ok(Snap.Tar.slice(post, 181n, 8n))))

def Snap.Tar.hdr.size(m: Maybe<&2, Nat>, ok: Bool, flag: U32, name: +List<U32>) -> Result<&2, &2, String, Snap.Tar.Hdr>:
  match m ok:
    case Some{n} True{}:
      Done{Hdr{flag, name, n}}
    case Some{n} False{}:
      Fail{Snap.Tar.err_header()}
    case None{} _:
      Fail{Snap.Tar.err_header()}

def Snap.Tar.hdr.flag(post: +List<U32>) -> U32:
  match post:
    case Nil{}:
      0
    case Con{c, t}:
      c

def Snap.Tar.hdr.fmt(+f: Snap.Tar.Fmt, +pre: +List<U32>, +post: +List<U32>) -> Result<&2, &2, String, Snap.Tar.Hdr>:
  +v7 = Snap.Tar.is_v7(f)
  Snap.Tar.hdr.size(Snap.Tar.numeric(Snap.Tar.slice(pre, 124n, 12n)), Snap.Tar.nums_ok(v7, pre, post),
    Snap.Tar.hdr.flag(post),
    Snap.Tar.join(Snap.Tar.prefix(f, post), Snap.Tar.cut_nul(List.take(&2, U32, pre, 100n))))

def Snap.Tar.hdr.cks(ok: Bool, +pre: +List<U32>, +post: +List<U32>) -> Result<&2, &2, String, Snap.Tar.Hdr>:
  match ok:
    case True{}:
      Snap.Tar.hdr.fmt(Snap.Tar.fmt(post), pre, post)
    case False{}:
      Fail{Snap.Tar.err_header()}

def Snap.Tar.hdr.parts(+pre: +List<U32>, r: Snap.BB) -> Result<&2, &2, String, Snap.Tar.Hdr>:
  match r:
    case BB{+field, +post}:
      Snap.Tar.hdr.cks(Snap.Tar.cks_ok(field, pre, post), pre, post)

def Snap.Tar.hdr.go(r: Snap.BB) -> Result<&2, &2, String, Snap.Tar.Hdr>:
  match r:
    case BB{+pre, rest}:
      Snap.Tar.hdr.parts(pre, Snap.Tar.split_at(8n, rest))

# A non-zero 512-byte header block (Go's Reader.readHeader).
def Snap.Tar.hdr(blk: +List<U32>) -> Result<&2, &2, String, Snap.Tar.Hdr>:
  Snap.Tar.hdr.go(Snap.Tar.split_at(148n, blk))

def Snap.Tar.all_zero(bs: +List<U32>) -> Bool:
  match bs:
    case Nil{}:
      True{}
    case Con{c, t}:
      U32.is_eq(c, 0) && Snap.Tar.all_zero(t)

# The records an extended header or GNU long name carries over to the next
# file header: the PAX path and size, and the GNU long name.
type Snap.Tar.Pend is Data:
  Pend{path: Maybe<&2, List<&2, U32>>, size: Maybe<&2, Nat>, gnu: List<&2, U32>}

def Snap.Tar.pend0() -> Snap.Tar.Pend:
  Pend{None{}, None{}, Nil{}}

# One PAX record and the bytes after it.
type Snap.Tar.PaxRec is Data:
  PaxRec{key: List<&2, U32>, value: List<&2, U32>, rest: List<&2, U32>}

def Snap.Tar.cut.cons(c: U32, r: Maybe<&2, Snap.BB>) -> Maybe<&2, Snap.BB>:
  match r:
    case None{}:
      None{}
    case Some{BB{a, b}}:
      Some{BB{c <> a, b}}

def Snap.Tar.cut.pick(hit: Bool, c: U32, t: +List<U32>, r: Maybe<&2, Snap.BB>) -> Maybe<&2, Snap.BB>:
  match hit:
    case True{}:
      Some{BB{Nil{}, t}}
    case False{}:
      Snap.Tar.cut.cons(c, r)

# Go strings.Cut(s, sep) for a one-byte sep: the bytes before and after the
# first sep, or None.
def Snap.Tar.cut(bs: +List<U32>, +sep: U32) -> Maybe<&2, Snap.BB>:
  match bs:
    case Nil{}:
      None{}
    case Con{+c, +t}:
      Snap.Tar.cut.pick(U32.is_eq(c, sep), c, t, Snap.Tar.cut(t, sep))

def Snap.Tar.px.valid.if(special: Bool, +k: +List<U32>, +v: +List<U32>) -> Bool:
  match special:
    case True{}:
      Bool.not(Snap.has_nul(v))
    case False{}:
      Bool.not(Snap.has_nul(k))

# Go archive/tar validPAXRecord(k, v) for a key without '='.
def Snap.Tar.px.valid(+k: +List<U32>, +v: +List<U32>) -> Bool:
  Bool.not(List.is_empty(&2, U32, k)) &&
    Snap.Tar.px.valid.if(Snap.Path.is(k, "path") || Snap.Path.is(k, "linkpath") ||
      Snap.Path.is(k, "uname") || Snap.Path.is(k, "gname"), k, v)

def Snap.Tar.px.kv.if(ok: Bool, k: +List<U32>, v: +List<U32>, rem: +List<U32>) -> Maybe<&2, Snap.Tar.PaxRec>:
  match ok:
    case True{}:
      Some{PaxRec{k, v, rem}}
    case False{}:
      None{}

def Snap.Tar.px.kv(kv: Maybe<&2, Snap.BB>, +rem: +List<U32>) -> Maybe<&2, Snap.Tar.PaxRec>:
  match kv:
    case None{}:
      None{}
    case Some{BB{+k, +v}}:
      Snap.Tar.px.kv.if(Snap.Tar.px.valid(k, v), k, v, rem)

def Snap.Tar.px.nl(nl: Bool, +rec: +List<U32>, +rem: +List<U32>) -> Maybe<&2, Snap.Tar.PaxRec>:
  match nl:
    case True{}:
      Snap.Tar.px.kv(Snap.Tar.cut(rec, 61), rem)
    case False{}:
      None{}

def Snap.Tar.px.body(+m: Nat, +rest: +List<U32>) -> Maybe<&2, Snap.Tar.PaxRec>:
  match m:
    case 0n:
      None{}
    case 1n+p:
      Snap.Tar.px.nl(Snap.beq(Snap.Tar.slice(rest, p, 1n), [10]),
        List.take(&2, U32, rest, p), List.drop(&2, U32, rest, 1n+p))

def Snap.Tar.px.len.if(bad: Bool, +n: Nat, +ns: +List<U32>, +rest: +List<U32>) -> Maybe<&2, Snap.Tar.PaxRec>:
  match bad:
    case True{}:
      None{}
    case False{}:
      Snap.Tar.px.body(Nat.sub(n, 1n+List.length(&2, U32, ns)), rest)

def Snap.Tar.px.len(m: Maybe<&2, Nat>, +ns: +List<U32>, +rest: +List<U32>, +total: Nat) -> Maybe<&2, Snap.Tar.PaxRec>:
  match m:
    case None{}:
      None{}
    case Some{+n}:
      Snap.Tar.px.len.if(Nat.is_lt(n, 5n) || Nat.is_gt(n, total), n, ns, rest)

def Snap.Tar.px.space(cut: Maybe<&2, Snap.BB>, +total: Nat) -> Maybe<&2, Snap.Tar.PaxRec>:
  match cut:
    case None{}:
      None{}
    case Some{BB{+ns, +rest}}:
      Snap.Tar.px.len(Snap.Dec.parse_int(ns), ns, rest, total)

# Go archive/tar parsePAXRecord(s): "<n> <key>=<value>\n", n the record's
# length in bytes.
def Snap.Tar.px.record(+s: +List<U32>) -> Maybe<&2, Snap.Tar.PaxRec>:
  Snap.Tar.px.space(Snap.Tar.cut(s, 32), List.length(&2, U32, s))

def Snap.Tar.pend.path(+v: +List<U32>, p: Snap.Tar.Pend) -> Snap.Tar.Pend:
  match p:
    case Pend{path, size, gnu}:
      Pend{Some{v}, size, gnu}

def Snap.Tar.pend.size(m: Maybe<&2, Nat>, p: Snap.Tar.Pend) -> Maybe<&2, Snap.Tar.Pend>:
  match m p:
    case None{} _:
      None{}
    case Some{n} Pend{path, size, gnu}:
      Some{Pend{path, Some{n}, gnu}}

def Snap.Tar.pend.merge.size(is_size: Bool, +v: +List<U32>, p: Snap.Tar.Pend) -> Maybe<&2, Snap.Tar.Pend>:
  match is_size:
    case True{}:
      Snap.Tar.pend.size(Snap.Dec.parse_int(v), p)
    case False{}:
      Some{p}

def Snap.Tar.pend.merge.path(is_path: Bool, +k: +List<U32>, +v: +List<U32>, p: Snap.Tar.Pend) -> Maybe<&2, Snap.Tar.Pend>:
  match is_path:
    case True{}:
      Some{Snap.Tar.pend.path(v, p)}
    case False{}:
      Snap.Tar.pend.merge.size(Snap.Path.is(k, "size"), v, p)

def Snap.Tar.pend.merge.empty(empty: Bool, +k: +List<U32>, +v: +List<U32>, p: Snap.Tar.Pend) -> Maybe<&2, Snap.Tar.Pend>:
  match empty:
    case True{}:
      Some{p}
    case False{}:
      Snap.Tar.pend.merge.path(Snap.Path.is(k, "path"), k, v, p)

# Go archive/tar mergePAX for one record: an empty value keeps the header's
# own; path sets the name and size the size (a bad size is an error).
def Snap.Tar.pend.merge(+k: +List<U32>, +v: +List<U32>, p: Snap.Tar.Pend) -> Maybe<&2, Snap.Tar.Pend>:
  Snap.Tar.pend.merge.empty(List.is_empty(&2, U32, v), k, v, p)

def Snap.Tar.px.next.merge(m: Maybe<&2, Snap.Tar.Pend>, rest: +List<U32>) -> Snap.Tar.PaxStep:
  match m:
    case None{}:
      PaxBad{}
    case Some{p}:
      PaxMore{p, rest}

def Snap.Tar.px.next(r: Maybe<&2, Snap.Tar.PaxRec>, p: Snap.Tar.Pend) -> Snap.Tar.PaxStep:
  match r:
    case None{}:
      PaxBad{}
    case Some{PaxRec{k, v, rest}}:
      Snap.Tar.px.next.merge(Snap.Tar.pend.merge(k, v, p), rest)

# One step of the PAX record loop.
type Snap.Tar.PaxStep is Data:
  PaxBad{}
  PaxMore{pend: Snap.Tar.Pend, rest: List<&2, U32>}

# Go archive/tar parsePAX, records merged into p (fuel: the bytes left).
def Snap.Tar.px.go(fuel: Nat, st: Snap.Tar.PaxStep) -> Maybe<&2, Snap.Tar.Pend>:
  match fuel st:
    case _ PaxBad{}:
      None{}
    case 0n PaxMore{p, Nil{}}:
      Some{p}
    case 0n PaxMore{p, Con{c, t}}:
      None{}
    case 1n+f PaxMore{p, Nil{}}:
      Some{p}
    case 1n+f PaxMore{p, Con{c, t}}:
      Snap.Tar.px.go(f, Snap.Tar.px.next(Snap.Tar.px.record(Con{c, t}), p))

# The pending records after the data of a PAX extended header.
def Snap.Tar.px(+s: +List<U32>, p: Snap.Tar.Pend) -> Maybe<&2, Snap.Tar.Pend>:
  Snap.Tar.px.go(List.length(&2, U32, s), PaxMore{p, s})

# What the data being read belongs to.
type Snap.Tar.What is Data:
  # A file: its data is a record's value.
  WFile{name: List<&2, U32>}
  # PAX records of an extended ('x') or a global ('g') header.
  WPax{global: Bool, name: List<&2, U32>}
  # A GNU long name ('L') or long link name ('K').
  WGnu{link: Bool}

# The decoder's state between two bytes.
type Snap.Tar.St is Data:
  # Reading a header block: k bytes left, the bytes so far (reversed).
  SHdr{k: Nat, acc: List<&2, U32>, pend: Snap.Tar.Pend}
  # Reading the block after a zero block: k bytes left, all zero so far.
  SZero{k: Nat, zero: Bool}
  # Reading data: n bytes left, the bytes so far (reversed), k bytes left
  # in the current block.
  SData{n: Nat, acc: List<&2, U32>, k: Nat, what: Snap.Tar.What, pend: Snap.Tar.Pend}
  # Skipping the padding after data: k bytes left.
  SPad{k: Nat, pend: Snap.Tar.Pend}
  # Done (two zero blocks, an error, or the limit): the rest is ignored.
  SEnd{}

# What a byte produces.
type Snap.Tar.Out is Data:
  ONone{}
  ORec{rec: Snap.Rec}
  OErr{msg: String}
  # The last record the caller asked for.
  OStop{rec: Snap.Rec}

type Snap.Tar.Step is Data:
  Step{out: Snap.Tar.Out, st: Snap.Tar.St, lim: Maybe<&2, Nat>}

def Snap.Tar.Step.out(s: Snap.Tar.Step) -> Snap.Tar.Out:
  match s:
    case Step{o, st, lim}:
      o

def Snap.Tar.Step.st(s: Snap.Tar.Step) -> Snap.Tar.St:
  match s:
    case Step{o, st, lim}:
      st

def Snap.Tar.Step.lim(s: Snap.Tar.Step) -> Maybe<&2, Nat>:
  match s:
    case Step{o, st, lim}:
      lim

def Snap.Tar.hdr0(p: Snap.Tar.Pend) -> Snap.Tar.St:
  SHdr{512n, Nil{}, p}

def Snap.Tar.after.if(full: Bool, k: Nat, p: Snap.Tar.Pend) -> Snap.Tar.St:
  match full:
    case True{}:
      Snap.Tar.hdr0(p)
    case False{}:
      SPad{k, p}

# The state after data that left k bytes in its last block.
def Snap.Tar.after(+k: Nat, p: Snap.Tar.Pend) -> Snap.Tar.St:
  Snap.Tar.after.if(Nat.is_eq(k, 512n), k, p)

def Snap.Tar.lim.last(lim: Maybe<&2, Nat>) -> Bool:
  match lim:
    case None{}:
      False{}
    case Some{n}:
      Nat.is_eq(n, 1n)

def Snap.Tar.lim.dec(lim: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match lim:
    case None{}:
      None{}
    case Some{n}:
      Some{Nat.sub(n, 1n)}

# A record, or the last one before the limit.
def Snap.Tar.rec_step(last: Bool, r: Snap.Rec, st: Snap.Tar.St, lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  match last:
    case True{}:
      Step{OStop{r}, SEnd{}, lim}
    case False{}:
      Step{ORec{r}, st, Snap.Tar.lim.dec(lim)}

def Snap.Tar.pick_name(path: Maybe<&2, List<&2, U32>>, name: +List<U32>) -> +List<U32>:
  match path:
    case None{}:
      name
    case Some{v}:
      v

def Snap.Tar.gnu_name.if(empty: Bool, gnu: +List<U32>, name: +List<U32>) -> +List<U32>:
  match empty:
    case True{}:
      name
    case False{}:
      gnu

def Snap.Tar.gnu_name(+gnu: +List<U32>, name: +List<U32>) -> +List<U32>:
  Snap.Tar.gnu_name.if(List.is_empty(&2, U32, gnu), gnu, name)

def Snap.Tar.pick_size(m: Maybe<&2, Nat>, n: Nat) -> Nat:
  match m:
    case None{}:
      n
    case Some{x}:
      x

# Go's isHeaderOnlyType: links, devices, directories and fifos have no
# data, and a legacy regular file ('\0') whose name ends in '/' is a
# directory.
def Snap.Tar.header_only(+flag: U32, +name: +List<U32>) -> Bool:
  (U32.is_ge(flag, 49) && U32.is_le(flag, 54)) || (U32.is_eq(flag, 0) && Snap.ends_slash(name))

def Snap.Tar.file.size(empty: Bool, +name: +List<U32>, n: Nat, lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  match empty:
    case True{}:
      Snap.Tar.rec_step(False{}, Rec{name, Nil{}}, Snap.Tar.hdr0(Snap.Tar.pend0()), lim)
    case False{}:
      Step{ONone{}, SData{n, Nil{}, 512n, WFile{name}, Snap.Tar.pend0()}, Snap.Tar.lim.dec(lim)}

def Snap.Tar.file.lim(last: Bool, +name: +List<U32>, +n: Nat, lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  match last:
    case True{}:
      Step{OStop{Rec{name, Nil{}}}, SEnd{}, lim}
    case False{}:
      Snap.Tar.file.size(Nat.is_eq(n, 0n), name, n, lim)

def Snap.Tar.file.ho(ho: Bool, +name: +List<U32>, n: Nat, +lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  match ho:
    case True{}:
      Snap.Tar.file.lim(Snap.Tar.lim.last(lim), name, 0n, lim)
    case False{}:
      Snap.Tar.file.lim(Snap.Tar.lim.last(lim), name, n, lim)

def Snap.Tar.file.go(+flag: U32, +name: +List<U32>, n: Nat, lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  Snap.Tar.file.ho(Snap.Tar.header_only(flag, name), name, n, lim)

# A file header: the pending PAX path and size and GNU long name apply.
def Snap.Tar.file(flag: U32, name: +List<U32>, n: Nat, p: Snap.Tar.Pend, lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  match p:
    case Pend{path, size, gnu}:
      Snap.Tar.file.go(flag, Snap.Tar.gnu_name(gnu, Snap.Tar.pick_name(path, name)),
        Snap.Tar.pick_size(size, n), lim)

def Snap.Tar.pend.gnu(link: Bool, +name: +List<U32>, p: Snap.Tar.Pend) -> Snap.Tar.Pend:
  match link p:
    case True{} _:
      p
    case False{} Pend{path, size, gnu}:
      Pend{path, size, name}

def Snap.Tar.pend.path_of(p: Snap.Tar.Pend) -> Maybe<&2, List<&2, U32>>:
  match p:
    case Pend{path, size, gnu}:
      path

def Snap.Tar.done.pax.g(global: Bool, +name: +List<U32>, +k: Nat, +p: Snap.Tar.Pend, +lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  match global:
    case True{}:
      Snap.Tar.rec_step(Snap.Tar.lim.last(lim), Rec{Snap.Tar.pick_name(Snap.Tar.pend.path_of(p), name), Nil{}},
        Snap.Tar.after(k, Snap.Tar.pend0()), lim)
    case False{}:
      Step{ONone{}, Snap.Tar.after(k, p), lim}

def Snap.Tar.done.pax(m: Maybe<&2, Snap.Tar.Pend>, global: Bool, +name: +List<U32>, +k: Nat, +lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  match m:
    case None{}:
      Step{OErr{Snap.Tar.err_header()}, SEnd{}, lim}
    case Some{+p}:
      Snap.Tar.done.pax.g(global, name, k, p, lim)

# The data of an entry is complete.
def Snap.Tar.done(what: Snap.Tar.What, +data: +List<U32>, +k: Nat, p: Snap.Tar.Pend, lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  match what:
    case WFile{name}:
      Step{ORec{Rec{name, data}}, Snap.Tar.after(k, Snap.Tar.pend0()), lim}
    case WPax{global, name}:
      Snap.Tar.done.pax(Snap.Tar.px(data, p), global, name, k, lim)
    case WGnu{link}:
      Step{ONone{}, Snap.Tar.after(k, Snap.Tar.pend.gnu(link, Snap.Tar.cut_nul(data), p)), lim}

def Snap.Tar.special.size(empty: Bool, what: Snap.Tar.What, n: Nat, p: Snap.Tar.Pend, lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  match empty:
    case True{}:
      Snap.Tar.done(what, Nil{}, 512n, p, lim)
    case False{}:
      Step{ONone{}, SData{n, Nil{}, 512n, what, p}, lim}

# A header whose data are records for the next header.
def Snap.Tar.special(what: Snap.Tar.What, +n: Nat, p: Snap.Tar.Pend, lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  Snap.Tar.special.size(Nat.is_eq(n, 0n), what, n, p, lim)

def Snap.Tar.on_flag.k(k: Bool, +flag: U32, name: +List<U32>, n: Nat, p: Snap.Tar.Pend, lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  match k:
    case True{}:
      Snap.Tar.special(WGnu{True{}}, n, p, lim)
    case False{}:
      Snap.Tar.file(flag, name, n, p, lim)

def Snap.Tar.on_flag.l(l: Bool, +flag: U32, name: +List<U32>, n: Nat, p: Snap.Tar.Pend, lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  match l:
    case True{}:
      Snap.Tar.special(WGnu{False{}}, n, p, lim)
    case False{}:
      Snap.Tar.on_flag.k(U32.is_eq(flag, 75), flag, name, n, p, lim)

def Snap.Tar.on_flag.g(g: Bool, +flag: U32, name: +List<U32>, n: Nat, p: Snap.Tar.Pend, lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  match g:
    case True{}:
      Snap.Tar.special(WPax{True{}, name}, n, Snap.Tar.pend0(), lim)
    case False{}:
      Snap.Tar.on_flag.l(U32.is_eq(flag, 76), flag, name, n, p, lim)

def Snap.Tar.on_flag.x(x: Bool, +flag: U32, name: +List<U32>, n: Nat, p: Snap.Tar.Pend, lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  match x:
    case True{}:
      Snap.Tar.special(WPax{False{}, name}, n, p, lim)
    case False{}:
      Snap.Tar.on_flag.g(U32.is_eq(flag, 103), flag, name, n, p, lim)

def Snap.Tar.on_hdr(h: Result<&2, &2, String, Snap.Tar.Hdr>, p: Snap.Tar.Pend, lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  match h:
    case Fail{m}:
      Step{OErr{m}, SEnd{}, lim}
    case Done{Hdr{+flag, name, n}}:
      Snap.Tar.on_flag.x(U32.is_eq(flag, 120), flag, name, n, p, lim)

def Snap.Tar.on_block.if(zero: Bool, +blk: +List<U32>, p: Snap.Tar.Pend, lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  match zero:
    case True{}:
      Step{ONone{}, SZero{512n, True{}}, lim}
    case False{}:
      Snap.Tar.on_hdr(Snap.Tar.hdr(blk), p, lim)

# A complete header block.
def Snap.Tar.on_block(+blk: +List<U32>, p: Snap.Tar.Pend, lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  Snap.Tar.on_block.if(Snap.Tar.all_zero(blk), blk, p, lim)

def Snap.Tar.step.hdr.q(q: Nat, acc: +List<U32>, p: Snap.Tar.Pend, lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  match q:
    case 0n:
      Snap.Tar.on_block(List.reverse(&2, U32, acc), p, lim)
    case 1n+r:
      Step{ONone{}, SHdr{1n+r, acc, p}, lim}

def Snap.Tar.step.hdr(k: Nat, acc: +List<U32>, p: Snap.Tar.Pend, lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  match k:
    case 0n:
      Snap.Tar.on_block(List.reverse(&2, U32, acc), p, lim)
    case 1n+q:
      Snap.Tar.step.hdr.q(q, acc, p, lim)

def Snap.Tar.step.zero.end(z: Bool, lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  match z:
    case True{}:
      Step{ONone{}, SEnd{}, lim}
    case False{}:
      Step{OErr{Snap.Tar.err_header()}, SEnd{}, lim}

def Snap.Tar.step.zero.q(q: Nat, z: Bool, lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  match q:
    case 0n:
      Snap.Tar.step.zero.end(z, lim)
    case 1n+r:
      Step{ONone{}, SZero{1n+r, z}, lim}

def Snap.Tar.step.zero(k: Nat, z: Bool, lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  match k:
    case 0n:
      Snap.Tar.step.zero.end(z, lim)
    case 1n+q:
      Snap.Tar.step.zero.q(q, z, lim)

def Snap.Tar.step.data.m(m: Nat, acc: +List<U32>, +k: Nat, what: Snap.Tar.What, p: Snap.Tar.Pend, lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  match m:
    case 0n:
      Snap.Tar.done(what, List.reverse(&2, U32, acc), k, p, lim)
    case 1n+r:
      Step{ONone{}, SData{1n+r, acc, k, what, p}, lim}

def Snap.Tar.step.data(n: Nat, acc: +List<U32>, +k: Nat, what: Snap.Tar.What, p: Snap.Tar.Pend, lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  match n:
    case 0n:
      Snap.Tar.done(what, List.reverse(&2, U32, acc), k, p, lim)
    case 1n+m:
      Snap.Tar.step.data.m(m, acc, k, what, p, lim)

def Snap.Tar.step.pad.q(q: Nat, p: Snap.Tar.Pend, lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  match q:
    case 0n:
      Step{ONone{}, Snap.Tar.hdr0(p), lim}
    case 1n+r:
      Step{ONone{}, SPad{1n+r, p}, lim}

def Snap.Tar.step.pad(k: Nat, p: Snap.Tar.Pend, lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  match k:
    case 0n:
      Step{ONone{}, Snap.Tar.hdr0(p), lim}
    case 1n+q:
      Snap.Tar.step.pad.q(q, p, lim)

# One byte.
def Snap.Tar.step(+x: U32, st: Snap.Tar.St, lim: Maybe<&2, Nat>) -> Snap.Tar.Step:
  match st:
    case SHdr{k, acc, p}:
      Snap.Tar.step.hdr(k, x <> acc, p, lim)
    case SZero{k, z}:
      Snap.Tar.step.zero(k, z && U32.is_eq(x, 0), lim)
    case SData{n, acc, k, what, p}:
      Snap.Tar.step.data(n, x <> acc, Snap.Tar.next(k), what, p, lim)
    case SPad{k, p}:
      Snap.Tar.step.pad(k, p, lim)
    case SEnd{}:
      Step{ONone{}, SEnd{}, lim}

def Snap.Tar.end.zero(full: Bool) -> Result<&2, &2, String, List<&2, Snap.Rec>>:
  match full:
    case True{}:
      Done{Nil{}}
    case False{}:
      Fail{Snap.Tar.err_eof()}

# The end of the input in a state: a clean end only between entries.
def Snap.Tar.end(st: Snap.Tar.St) -> Result<&2, &2, String, List<&2, Snap.Rec>>:
  match st:
    case SHdr{k, Nil{}, p}:
      Done{Nil{}}
    case SHdr{k, Con{c, t}, p}:
      Fail{Snap.Tar.err_eof()}
    case SZero{k, z}:
      Snap.Tar.end.zero(Nat.is_eq(k, 512n))
    case SData{n, acc, k, what, p}:
      Fail{Snap.Tar.err_eof()}
    case SPad{k, p}:
      Done{Nil{}}
    case SEnd{}:
      Done{Nil{}}

def Snap.Tar.emit.rec(r: Snap.Rec, rest: Result<&2, &2, String, List<&2, Snap.Rec>>) -> Result<&2, &2, String, List<&2, Snap.Rec>>:
  match rest:
    case Fail{m}:
      Fail{m}
    case Done{rs}:
      Done{r <> rs}

def Snap.Tar.emit(o: Snap.Tar.Out, rest: Result<&2, &2, String, List<&2, Snap.Rec>>) -> Result<&2, &2, String, List<&2, Snap.Rec>>:
  match o:
    case ONone{}:
      rest
    case ORec{r}:
      Snap.Tar.emit.rec(r, rest)
    case OErr{m}:
      Fail{m}
    case OStop{r}:
      Done{[r]}

def Snap.Tar.go(xs: +List<U32>, st: Snap.Tar.St, lim: Maybe<&2, Nat>) -> Result<&2, &2, String, List<&2, Snap.Rec>>:
  match xs:
    case Nil{}:
      Snap.Tar.end(st)
    case Con{x, t}:
      +s = Snap.Tar.step(x, st, lim)
      Snap.Tar.emit(Snap.Tar.Step.out(s), Snap.Tar.go(t, Snap.Tar.Step.st(s), Snap.Tar.Step.lim(s)))

# The records of a tar stream, as Go's tar.Reader and readArchiveEntry read
# them, or the first error (Go's error text).
def Snap.Tar.decode(bs: +List<U32>) -> Result<&2, &2, String, List<&2, Snap.Rec>>:
  Snap.Tar.go(bs, Snap.Tar.hdr0(Snap.Tar.pend0()), None{})

# The first n entries of a tar stream as Go's tar.Reader.Next returns their
# headers: the last one's value is not read (empty).
def Snap.Tar.heads(n: Nat, bs: +List<U32>) -> Result<&2, &2, String, List<&2, Snap.Rec>>:
  Snap.Tar.go(bs, Snap.Tar.hdr0(Snap.Tar.pend0()), Some{n})

# Streaming headers
# -----------------

def Snap.Oct.of_nat.put(top: Bool, o: Snap.Oct, rest: List<&2, Snap.Oct>) -> List<&2, Snap.Oct>:
  match top:
    case True{}:
      [o]
    case False{}:
      o <> rest

def Snap.Oct.of_rem(r: Nat) -> Snap.Oct:
  match r:
    case 0n:
      O0{}
    case 1n:
      O1{}
    case 2n:
      O2{}
    case 3n:
      O3{}
    case 4n:
      O4{}
    case 5n:
      O5{}
    case 6n:
      O6{}
    case _:
      O7{}

def Snap.Oct.of_nat.go(fuel: Nat, +n: Nat) -> List<&2, Snap.Oct>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+f:
      +q = Nat.div(n, 8n)
      Snap.Oct.of_nat.put(Nat.is_eq(q, 0n), Snap.Oct.of_rem(Nat.mod(n, 8n)), Snap.Oct.of_nat.go(f, q))

def Snap.Oct.of_nat.top(n: Nat) -> List<&2, Snap.Oct>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Snap.Oct.of_nat.go(24n, 1n+p)

# The octal digits of n (n below 8^24), little-endian, as Snap.Oct.count
# makes them: Snap.Oct.of_nat(List.length(xs)) == Snap.Oct.count(xs).
def Snap.Oct.of_nat(n: Nat) -> List<&2, Snap.Oct>:
  Snap.Oct.of_nat.top(n)

# The PAX record must fit its size field, as in Snap.Tar.entry.pax.fits.
def Snap.Tar.headers.pax.fits(fits: Bool, +bs: +List<U32>, +rec: List<&2, U32>, ds: List<&2, Snap.Oct>) -> Result<&2, &2, String, List<&2, U32>>:
  match fits:
    case True{}:
      Done{Snap.app(Snap.Tar.block(Snap.Tar.pax_hdr_name(bs), Snap.Tar.zero8(), Snap.Tar.size(Snap.Oct.count(rec)), 120, Snap.zeros(8n), Nil{}),
        Snap.app(Snap.Tar.data(rec, 512n),
          Snap.Tar.block(Snap.Tar.pax_name(bs), Snap.Tar.mode666(), Snap.Tar.size(ds), 48, Snap.Tar.zero8(), Nil{})))}
    case False{}:
      Fail{"archive/tar: header field too long"}

def Snap.Tar.headers.pax(r: Maybe<&2, List<&2, U32>>, +bs: +List<U32>, ds: List<&2, Snap.Oct>) -> Result<&2, &2, String, List<&2, U32>>:
  match r:
    case None{}:
      Fail{"archive/tar: header field too long"}
    case Some{+rec}:
      Snap.Tar.headers.pax.fits(Snap.Tar.size_fits(Snap.Oct.count(rec)), bs, rec, ds)

def Snap.Tar.headers.name(n: Snap.Tar.Name, +bs: +List<U32>, ds: List<&2, Snap.Oct>) -> Result<&2, &2, String, List<&2, U32>>:
  match n:
    case NShort{}:
      Done{Snap.Tar.ustar(bs, Nil{}, ds)}
    case NSplit{p, s}:
      Done{Snap.Tar.ustar(s, p, ds)}
    case NPax{}:
      Snap.Tar.headers.pax(Snap.Tar.pax_rec(bs), bs, ds)
    case NBad{msg}:
      Fail{msg}

def Snap.Tar.headers.size(fits: Bool, +bs: +List<U32>, ds: List<&2, Snap.Oct>) -> Result<&2, &2, String, List<&2, U32>>:
  match fits:
    case True{}:
      Snap.Tar.headers.name(Snap.Tar.name(bs), bs, ds)
    case False{}:
      Fail{"archive/tar: header field too long"}

# The header bytes of a regular file of size n, for host code that streams
# the data itself (the etcd database of an etcd snapshot): the file's data
# follows, then Snap.Tar.pad_after(n) zeros.
def Snap.Tar.file_header(key: +List<U32>, n: Nat) -> Result<&2, &2, String, List<&2, U32>>:
  +ds = Snap.Oct.of_nat(n)
  Snap.Tar.headers.size(Nat.is_le(List.length(&2, Snap.Oct, ds), 11n), key, ds)

# The zeros after n bytes of data (Go's blockPadding).
def Snap.Tar.pad_after(n: Nat) -> Nat:
  Nat.mod(Nat.sub(512n, Nat.mod(n, 512n)), 512n)

# The archive layout
# ------------------

# Go: SnapshotMetadataPrefix and the keys under it.
def Snap.meta_prefix() -> +List<U32>:
  Snap.b("/vcluster/snapshot/")

# snapshotapi.SnapshotReleaseKey: the vCluster Helm release (JSON).
def Snap.release_key() -> +List<U32>:
  Snap.b("/vcluster/snapshot/release")

# RequestStoreKey: the snapshot request (JSON) at <key>/<apiVersion>.
def Snap.request_key() -> +List<U32>:
  Snap.b("/vcluster/snapshot/request")

# DBStoreKey: the raw etcd (bolt) database of an etcd snapshot.
def Snap.db_key() -> +List<U32>:
  Snap.b("/vcluster/snapshot/db")

# SkipKeysStoreKey: the keys a restore deletes (a JSON object).
def Snap.skipkeys_key() -> +List<U32>:
  Snap.b("/vcluster/snapshot/skipkeys")

# RevisionStoreKey: the store's revision when the snapshot was taken.
def Snap.revision_key() -> +List<U32>:
  Snap.b("/vcluster/snapshot/revision")

# snapshotapi.APIVersion.
def Snap.api_version() -> String:
  "v1beta1"

# The request entry's key: RequestStoreKey + "/" + APIVersion.
def Snap.request_entry_key() -> +List<U32>:
  Snap.b("/vcluster/snapshot/request/v1beta1")

# store.MappingsPrefix: vcluster's name mappings, dropped on a restore into
# a new vCluster.
def Snap.mappings_prefix() -> +List<U32>:
  Snap.b("/vcluster/mappings/")

def Snap.pod_prefix() -> +List<U32>:
  Snap.b("/registry/pods/")

def Snap.configmap_prefix() -> +List<U32>:
  Snap.b("/registry/configmaps/")

# BumpRevision: the etcd revision bump of an etcd restore.
def Snap.bump_revision() -> Nat:
  1000n

# constants.VClusterStandaloneSnapshotNamespace: the host namespace a
# standalone snapshot or restore uses.
def Snap.standalone_namespace() -> String:
  "kube-system"

# constants.VClusterStorageOptionsEnv.
def Snap.storage_options_env() -> String:
  "VCLUSTER_STORAGE_OPTIONS"

# EtcdToKeyValueConversionLogMessage.
def Snap.conversion_message() -> String:
  "Converting etcd snapshot to key-value snapshot"

# The kind of an archive (SnapshotKind).
type Snap.Kind is Data:
  KUnknown{}
  KEtcd{}
  KKeyValue{}

def Snap.Kind.name(k: Snap.Kind) -> String:
  match k:
    case KUnknown{}:
      "Unknown"
    case KEtcd{}:
      "EtcdSnapshot"
    case KKeyValue{}:
      "KeyValueSnapshot"

def Snap.key(r: Snap.Rec) -> +List<U32>:
  match r:
    case Rec{k, v}:
      k

def Snap.value(r: Snap.Rec) -> +List<U32>:
  match r:
    case Rec{k, v}:
      v

def Snap.kind.db.if(db: Bool) -> Snap.Kind:
  match db:
    case True{}:
      KEtcd{}
    case False{}:
      KKeyValue{}

def Snap.kind.db(ks: List<&2, List<&2, U32>>) -> Snap.Kind:
  match ks:
    case Nil{}:
      KKeyValue{}
    case Con{+k, t}:
      Snap.kind.db.if(Snap.beq(k, Snap.db_key()))

def Snap.kind.req.if(req: Bool, t: List<&2, List<&2, U32>>, all: List<&2, List<&2, U32>>) -> Snap.Kind:
  match req:
    case True{}:
      Snap.kind.db(t)
    case False{}:
      Snap.kind.db(all)

def Snap.kind.req(ks: List<&2, List<&2, U32>>) -> Snap.Kind:
  match ks:
    case Nil{}:
      KKeyValue{}
    case Con{+k, +t}:
      Snap.kind.req.if(Snap.bprefix(k, Snap.request_key()), t, Con{k, t})

def Snap.kind.rel.if(rel: Bool, t: List<&2, List<&2, U32>>, all: List<&2, List<&2, U32>>) -> Snap.Kind:
  match rel:
    case True{}:
      Snap.kind.req(t)
    case False{}:
      Snap.kind.req(all)

def Snap.keys(rs: List<&2, Snap.Rec>) -> List<&2, List<&2, U32>>:
  match rs:
    case Nil{}:
      Nil{}
    case Con{r, t}:
      Snap.key(r) <> Snap.keys(t)

def Snap.kind.keys(ks: List<&2, List<&2, U32>>) -> Snap.Kind:
  match ks:
    case Nil{}:
      KKeyValue{}
    case Con{+k, +t}:
      Snap.kind.rel.if(Snap.beq(k, Snap.release_key()), t, Con{k, t})

# getSnapshotArchiveKind on the archive's entries: an optional release,
# then an optional request (any name with the request key as prefix), then
# the database key make an etcd snapshot; anything else is key/value.
def Snap.kind(rs: List<&2, Snap.Rec>) -> Snap.Kind:
  Snap.kind.keys(Snap.keys(rs))

def Snap.kind.db1(+k: +List<U32>) -> Snap.Kind:
  Snap.kind.db.if(Snap.beq(k, Snap.db_key()))

def Snap.kind_of_tar.get(r: Result<&2, &2, String, List<&2, Snap.Rec>>, n: Nat) -> Result<&2, &2, String, Maybe<&2, List<&2, U32>>>:
  match r:
    case Fail{m}:
      Fail{"failed to read tar header: " ++ m}
    case Done{rs}:
      Done{List.get(&2, List<&2, U32>, Snap.keys(rs), n)}

def Snap.kind_of_tar.db(m: Result<&2, &2, String, Maybe<&2, List<&2, U32>>>) -> Result<&2, &2, String, Snap.Kind>:
  match m:
    case Fail{e}:
      Fail{e}
    case Done{None{}}:
      Done{KKeyValue{}}
    case Done{Some{k}}:
      Done{Snap.kind.db1(k)}

def Snap.kind_of_tar.req.if(req: Bool, +k: +List<U32>, +i: Nat, +bs: +List<U32>) -> Result<&2, &2, String, Snap.Kind>:
  match req:
    case True{}:
      Snap.kind_of_tar.db(Snap.kind_of_tar.get(Snap.Tar.heads(2n+i, bs), 1n+i))
    case False{}:
      Done{Snap.kind.db1(k)}

# The entry k at index i may be the request; the one after it decides.
def Snap.kind_of_tar.req(+k: +List<U32>, +i: Nat, +bs: +List<U32>) -> Result<&2, &2, String, Snap.Kind>:
  Snap.kind_of_tar.req.if(Snap.bprefix(k, Snap.request_key()), k, i, bs)

def Snap.kind_of_tar.second(m: Result<&2, &2, String, Maybe<&2, List<&2, U32>>>, +bs: +List<U32>) -> Result<&2, &2, String, Snap.Kind>:
  match m:
    case Fail{e}:
      Fail{e}
    case Done{None{}}:
      Done{KKeyValue{}}
    case Done{Some{k}}:
      Snap.kind_of_tar.req(k, 1n, bs)

def Snap.kind_of_tar.rel(rel: Bool, +k: +List<U32>, +bs: +List<U32>) -> Result<&2, &2, String, Snap.Kind>:
  match rel:
    case True{}:
      Snap.kind_of_tar.second(Snap.kind_of_tar.get(Snap.Tar.heads(2n, bs), 1n), bs)
    case False{}:
      Snap.kind_of_tar.req(k, 0n, bs)

def Snap.kind_of_tar.first.k(+k: +List<U32>, +bs: +List<U32>) -> Result<&2, &2, String, Snap.Kind>:
  Snap.kind_of_tar.rel(Snap.beq(k, Snap.release_key()), k, bs)

def Snap.kind_of_tar.first(r: Result<&2, &2, String, List<&2, Snap.Rec>>, +bs: +List<U32>) -> Result<&2, &2, String, Snap.Kind>:
  match r:
    case Fail{m}:
      Fail{"read tar header: " ++ m}
    case Done{Nil{}}:
      Done{KKeyValue{}}
    case Done{Con{h, t}}:
      Snap.kind_of_tar.first.k(Snap.key(h), bs)

# getSnapshotArchiveKind on a tar stream (after gunzip): it reads at most
# the first three headers, with Go's error texts.
def Snap.kind_of_tar(+bs: +List<U32>) -> Result<&2, &2, String, Snap.Kind>:
  Snap.kind_of_tar.first(Snap.Tar.heads(1n, bs), bs)

# The entries written before the key/value records (archiveMetadata): the
# release JSON and the request (its entry key and JSON), each optional.
type Snap.Meta is Data:
  Meta{release: Maybe<&2, List<&2, U32>>, request: Maybe<&2, Snap.Rec>}

def Snap.meta0() -> Snap.Meta:
  Meta{None{}, None{}}

# One element of the etcd key listing: a key and value, or an error.
type Snap.Item is Data:
  IVal{key: List<&2, U32>, value: List<&2, U32>}
  IErr{msg: String}

def Snap.contains(ks: List<&2, List<&2, U32>>, +k: +List<U32>) -> Bool:
  match ks:
    case Nil{}:
      False{}
    case Con{+x, t}:
      Snap.beq(x, k) || Snap.contains(t, k)

def Snap.write.val(skip: Bool, +k: +List<U32>, +v: +List<U32>, rest: Result<&2, &2, String, List<&2, Snap.Rec>>) -> Result<&2, &2, String, List<&2, Snap.Rec>>:
  match skip:
    case True{}:
      rest
    case False{}:
      Snap.Tar.emit.rec(Rec{k, v}, rest)

def Snap.write.items(items: List<&2, Snap.Item>, +skip: List<&2, List<&2, U32>>) -> Result<&2, &2, String, List<&2, Snap.Rec>>:
  match items:
    case Nil{}:
      Done{Nil{}}
    case Con{IErr{m}, t}:
      Fail{"failed to retrieve etcd items: " ++ m}
    case Con{IVal{+k, +v}, t}:
      Snap.write.val(Snap.bprefix(k, Snap.meta_prefix()) || Snap.contains(skip, k), k, v,
        Snap.write.items(t, skip))

def Snap.write.opt(m: Maybe<&2, Snap.Rec>, rest: Result<&2, &2, String, List<&2, Snap.Rec>>) -> Result<&2, &2, String, List<&2, Snap.Rec>>:
  match m:
    case None{}:
      rest
    case Some{r}:
      Snap.Tar.emit.rec(r, rest)

def Snap.write.release(m: Maybe<&2, List<&2, U32>>) -> Maybe<&2, Snap.Rec>:
  match m:
    case None{}:
      None{}
    case Some{v}:
      Some{Rec{Snap.release_key(), v}}

def Snap.write.head(meta: Snap.Meta, +rev: Nat, rest: Result<&2, &2, String, List<&2, Snap.Rec>>) -> Result<&2, &2, String, List<&2, Snap.Rec>>:
  match meta:
    case Meta{rel, req}:
      Snap.write.opt(Snap.write.release(rel), Snap.write.opt(req,
        Snap.Tar.emit.rec(Rec{Snap.revision_key(), Snap.b(Nat.show(rev))}, rest)))

def Snap.write.cancel(cancelled: Bool, meta: Snap.Meta, +rev: Nat, items: List<&2, Snap.Item>, +skip: List<&2, List<&2, U32>>) -> Result<&2, &2, String, List<&2, Snap.Rec>>:
  match cancelled:
    case True{}:
      Fail{"context: context canceled"}
    case False{}:
      Snap.write.head(meta, rev, Snap.write.items(items, skip))

# writeKeyValueSnapshot as records: the release and request, the revision
# (decimal), then each listed key in order, minus the metadata keys (a
# stale copy a restore left in etcd) and the skip keys. Errors: the
# revision read, a listing error, a cancelled context (never a success, so
# a truncated archive is never reported as complete).
def Snap.write_kv(meta: Snap.Meta, rev: Result<&2, &2, String, Nat>, items: List<&2, Snap.Item>, +skip: List<&2, List<&2, U32>>, cancelled: Bool) -> Result<&2, &2, String, List<&2, Snap.Rec>>:
  match rev:
    case Fail{m}:
      Fail{"failed to get current revision: " ++ m}
    case Done{n}:
      Snap.write.cancel(cancelled, meta, n, items, skip)

def Snap.encode.label.skip(skip: Bool, k: +List<U32>) -> String:
  match skip:
    case True{}:
      "failed to snapshot skipKeys: "
    case False{}:
      "failed to snapshot key " ++ Snap.s(k) ++ ": "

def Snap.encode.label.rev(rev: Bool, skip: Bool, k: +List<U32>) -> String:
  match rev:
    case True{}:
      "failed to snapshot revision: "
    case False{}:
      Snap.encode.label.skip(skip, k)

def Snap.encode.label.req(req: Bool, rev: Bool, skip: Bool, k: +List<U32>) -> String:
  match req:
    case True{}:
      "failed to snapshot request: "
    case False{}:
      Snap.encode.label.rev(rev, skip, k)

def Snap.encode.label.if(rel: Bool, req: Bool, rev: Bool, skip: Bool, k: +List<U32>) -> String:
  match rel:
    case True{}:
      "failed to snapshot vCluster release: "
    case False{}:
      Snap.encode.label.req(req, rev, skip, k)

def Snap.encode.label(+k: +List<U32>) -> String:
  Snap.encode.label.if(Snap.beq(k, Snap.release_key()), Snap.bprefix(k, Snap.request_key()),
    Snap.beq(k, Snap.revision_key()), Snap.beq(k, Snap.skipkeys_key()), k)

def Snap.encode.step(e: Result<&2, &2, String, List<&2, U32>>, +k: +List<U32>, t: Result<&2, &2, String, List<&2, U32>>) -> Result<&2, &2, String, List<&2, U32>>:
  match e:
    case Fail{m}:
      Fail{Snap.encode.label(k) ++ m}
    case Done{bs}:
      Snap.Tar.encode.cons(bs, t)

def Snap.encode.go(rs: List<&2, Snap.Rec>) -> Result<&2, &2, String, List<&2, U32>>:
  match rs:
    case Nil{}:
      Done{Snap.Tar.trailer()}
    case Con{+r, t}:
      Snap.encode.step(Snap.Tar.entry(r), Snap.key(r), Snap.encode.go(t))

# The tar stream of an archive's records, with vcluster's error texts
# ("failed to snapshot key <key>: <tar error>").
def Snap.encode(rs: List<&2, Snap.Rec>) -> Result<&2, &2, String, List<&2, U32>>:
  Snap.encode.go(rs)

# JSON
# ----

def Snap.Json.hex4(+c: U32) -> +List<U32>:
  [92, 117, 48, 48, Snap.Tar.hexd(U32.shrn(c, 4n)), Snap.Tar.hexd(U32.and(c, 15))]

def Snap.Json.esc.ctl.t(t: Bool, +c: U32) -> +List<U32>:
  match t:
    case True{}:
      [92, 116]
    case False{}:
      Snap.Json.hex4(c)

def Snap.Json.esc.ctl.r(r: Bool, t: Bool, +c: U32) -> +List<U32>:
  match r:
    case True{}:
      [92, 114]
    case False{}:
      Snap.Json.esc.ctl.t(t, c)

def Snap.Json.esc.ctl(n: Bool, r: Bool, t: Bool, +c: U32) -> +List<U32>:
  match n:
    case True{}:
      [92, 110]
    case False{}:
      Snap.Json.esc.ctl.r(r, t, c)

def Snap.Json.esc.html(html: Bool, +c: U32) -> +List<U32>:
  match html:
    case True{}:
      Snap.Json.hex4(c)
    case False{}:
      [c]

def Snap.Json.esc.q(q: Bool, html: Bool, +c: U32) -> +List<U32>:
  match q:
    case True{}:
      [92, c]
    case False{}:
      Snap.Json.esc.html(html, c)

def Snap.Json.esc.if(ctl: Bool, q: Bool, html: Bool, +c: U32) -> +List<U32>:
  match ctl:
    case True{}:
      Snap.Json.esc.ctl(U32.is_eq(c, 10), U32.is_eq(c, 13), U32.is_eq(c, 9), c)
    case False{}:
      Snap.Json.esc.q(q, html, c)

# One byte of a Go encoding/json string: controls, '"', '\' and the HTML
# characters <, >, & escaped (bytes past 0x7f pass as they are).
def Snap.Json.esc(+c: U32) -> +List<U32>:
  Snap.Json.esc.if(U32.is_lt(c, 32), U32.is_eq(c, 34) || U32.is_eq(c, 92),
    U32.is_eq(c, 60) || U32.is_eq(c, 62) || U32.is_eq(c, 38), c)

def Snap.Json.str.go(bs: +List<U32>) -> +List<U32>:
  match bs:
    case Nil{}:
      [34]
    case Con{+c, t}:
      Snap.app(Snap.Json.esc(c), Snap.Json.str.go(t))

def Snap.Json.pick(-A: Data, c: Bool, a: A, b: A) -> A:
  match c:
    case True{}:
      a
    case False{}:
      b

def Snap.Json.hexv(+c: U32) -> Maybe<&2, U32>:
  Snap.Json.pick(Maybe<&2, U32>, U32.is_ge(c, 48) && U32.is_le(c, 57), Some{(c - 48 : U32)},
    Snap.Json.pick(Maybe<&2, U32>, U32.is_ge(c, 97) && U32.is_le(c, 102), Some{(c - 87 : U32)},
      Snap.Json.pick(Maybe<&2, U32>, U32.is_ge(c, 65) && U32.is_le(c, 70), Some{(c - 55 : U32)}, None{})))

def Snap.Json.utf8.if(sur: Bool, +cp: U32, acc: +List<U32>) -> +List<U32>:
  match sur:
    case True{}:
      List.reverse.go(&2, U32, H.Sha256.utf8(String.from_list([Chr{65533}])), acc)
    case False{}:
      List.reverse.go(&2, U32, H.Sha256.utf8(String.from_list([Chr{cp}])), acc)

# The UTF-8 bytes of a code point below 0x10000, reversed onto acc
# (surrogates are U+FFFD, as Go decodes a lone one).
def Snap.Json.utf8(+cp: U32, acc: +List<U32>) -> +List<U32>:
  Snap.Json.utf8.if(U32.is_ge(cp, 55296) && U32.is_le(cp, 57343), cp, acc)

def Snap.Json.kstr.u.n(n: Nat, +cp: U32, acc: +List<U32>, keys: List<&2, List<&2, U32>>) -> Snap.Json.P:
  match n:
    case 0n:
      P{JStr{Snap.Json.utf8(cp, acc), ENone{}}, keys}
    case 1n+p:
      P{JStr{acc, EU{1n+p, cp}}, keys}

def Snap.Json.kstr.u(m: Maybe<&2, U32>, +n: Nat, +cp: U32, acc: +List<U32>, keys: List<&2, List<&2, U32>>) -> Snap.Json.P:
  match m:
    case None{}:
      P{JBad{}, keys}
    case Some{d}:
      Snap.Json.kstr.u.n(n, (cp * 16 + d : U32), acc, keys)

def Snap.Json.kstr.esc(+c: U32) -> Maybe<&2, U32>:
  Snap.Json.pick(Maybe<&2, U32>, U32.is_eq(c, 34) || U32.is_eq(c, 92) || U32.is_eq(c, 47), Some{c},
    Snap.Json.pick(Maybe<&2, U32>, U32.is_eq(c, 98), Some{8},
      Snap.Json.pick(Maybe<&2, U32>, U32.is_eq(c, 102), Some{12},
        Snap.Json.pick(Maybe<&2, U32>, U32.is_eq(c, 110), Some{10},
          Snap.Json.pick(Maybe<&2, U32>, U32.is_eq(c, 114), Some{13},
            Snap.Json.pick(Maybe<&2, U32>, U32.is_eq(c, 116), Some{9}, None{}))))))

def Snap.Json.kstr.back.if(u: Bool, m: Maybe<&2, U32>, acc: +List<U32>, keys: List<&2, List<&2, U32>>) -> Snap.Json.P:
  match u m:
    case True{} _:
      P{JStr{acc, EU{4n, 0}}, keys}
    case False{} None{}:
      P{JBad{}, keys}
    case False{} Some{x}:
      P{JStr{x <> acc, ENone{}}, keys}

def Snap.Json.kstr.back(+c: U32, acc: +List<U32>, keys: List<&2, List<&2, U32>>) -> Snap.Json.P:
  Snap.Json.kstr.back.if(U32.is_eq(c, 117), Snap.Json.kstr.esc(c), acc, keys)

# The state of the skip keys parser (json.Unmarshal into
# map[string]struct{}).
type Snap.Json.St is Data:
  # Before the value: '{' or null.
  JStart{}
  # Inside a literal: the bytes still expected, then the state after it.
  JLit{rest: List<&2, U32>, top: Bool}
  # After '{' or ',': a key ('"'), or '}' right after '{'.
  JKey{first: Bool}
  # Inside a key: its bytes so far (reversed), and the escape state.
  JStr{acc: List<&2, U32>, esc: Snap.Json.Esc}
  # After a key: ':'.
  JColon{}
  # Before a member's value: '{' or null.
  JVal{}
  # Inside a member's object: depth, inside a string, after a backslash.
  JSkip{depth: Nat, str: Bool, esc: Bool}
  # After a member: ',' or '}'.
  JNext{}
  # After the whole value: only spaces.
  JEnd{}
  JBad{}

# An escape in a key: none, after '\', or \u with its hex digits so far.
type Snap.Json.Esc is Data:
  ENone{}
  EBack{}
  EU{n: Nat, cp: U32}

def Snap.Json.kstr.plain(+c: U32, +acc: +List<U32>, +keys: List<&2, List<&2, U32>>) -> Snap.Json.P:
  Snap.Json.pick(Snap.Json.P, U32.is_eq(c, 34), P{JColon{}, List.reverse(&2, U32, acc) <> keys},
    Snap.Json.pick(Snap.Json.P, U32.is_eq(c, 92), P{JStr{acc, EBack{}}, keys},
      Snap.Json.pick(Snap.Json.P, U32.is_lt(c, 32), P{JBad{}, keys}, P{JStr{c <> acc, ENone{}}, keys})))

# The parser's state and the keys so far (reversed).
type Snap.Json.P is Data:
  P{st: Snap.Json.St, keys: List<&2, List<&2, U32>>}

def Snap.Json.str(bs: +List<U32>) -> +List<U32>:
  34 <> Snap.Json.str.go(bs)

def Snap.Json.kstr(+c: U32, acc: +List<U32>, e: Snap.Json.Esc, keys: List<&2, List<&2, U32>>) -> Snap.Json.P:
  match e:
    case ENone{}:
      Snap.Json.kstr.plain(c, acc, keys)
    case EBack{}:
      Snap.Json.kstr.back(c, acc, keys)
    case EU{n, cp}:
      Snap.Json.kstr.u(Snap.Json.hexv(c), Nat.sub(n, 1n), cp, acc, keys)

# Byte order (Go's string comparison).
def Snap.ble(a: +List<U32>, b: +List<U32>) -> Bool:
  match a b:
    case Nil{} _:
      True{}
    case Con{x, xs} Nil{}:
      False{}
    case Con{+x, xs} Con{+y, ys}:
      U32.is_lt(x, y) || (U32.is_eq(x, y) && Snap.ble(xs, ys))

def Snap.sort(ks: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  List.sort(~List<&2, U32>, ~(a => b => Snap.ble(a, b)), ks)

def Snap.Json.keys.go(ks: List<&2, List<&2, U32>>) -> +List<U32>:
  match ks:
    case Nil{}:
      [125]
    case Con{k, t}:
      Snap.app([44], Snap.app(Snap.Json.str(k), Snap.app([58, 123, 125], Snap.Json.keys.go(t))))

def Snap.Json.keys.first(ks: List<&2, List<&2, U32>>) -> +List<U32>:
  match ks:
    case Nil{}:
      [123, 125]
    case Con{k, t}:
      123 <> Snap.app(Snap.Json.str(k), Snap.app([58, 123, 125], Snap.Json.keys.go(t)))

def Snap.dedup.put(same: Bool, k: +List<U32>, rest: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match same:
    case True{}:
      rest
    case False{}:
      k <> rest

def Snap.dedup.go(ks: List<&2, List<&2, U32>>, +prev: +List<U32>) -> List<&2, List<&2, U32>>:
  match ks:
    case Nil{}:
      Nil{}
    case Con{+k, t}:
      Snap.dedup.put(Snap.beq(k, prev), k, Snap.dedup.go(t, k))

def Snap.dedup(ks: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match ks:
    case Nil{}:
      Nil{}
    case Con{+k, t}:
      k <> Snap.dedup.go(t, k)

# json.Marshal(map[string]struct{}) of a key set: {"k":{},...} by key.
def Snap.skipkeys_json(ks: List<&2, List<&2, U32>>) -> +List<U32>:
  Snap.Json.keys.first(Snap.dedup(Snap.sort(ks)))

def Snap.Json.ws(+c: U32) -> Bool:
  U32.is_eq(c, 32) || U32.is_eq(c, 9) || U32.is_eq(c, 10) || U32.is_eq(c, 13)

def Snap.Json.start(+c: U32, keys: List<&2, List<&2, U32>>, +top: Bool) -> Snap.Json.P:
  P{Snap.Json.pick(Snap.Json.St, Snap.Json.ws(c), Snap.Json.pick(Snap.Json.St, top, JStart{}, JVal{}),
    Snap.Json.pick(Snap.Json.St, U32.is_eq(c, 123),
      Snap.Json.pick(Snap.Json.St, top, JKey{True{}}, JSkip{1n, False{}, False{}}),
      Snap.Json.pick(Snap.Json.St, U32.is_eq(c, 110), JLit{[117, 108, 108], top}, JBad{}))), keys}

def Snap.Json.lit.next(t: +List<U32>, top: Bool) -> Snap.Json.St:
  match t:
    case Nil{}:
      Snap.Json.pick(Snap.Json.St, top, JEnd{}, JNext{})
    case Con{x, u}:
      JLit{Con{x, u}, top}

def Snap.Json.lit(+c: U32, rest: +List<U32>, top: Bool, keys: List<&2, List<&2, U32>>) -> Snap.Json.P:
  match rest:
    case Nil{}:
      P{JBad{}, keys}
    case Con{+x, t}:
      P{Snap.Json.pick(Snap.Json.St, U32.is_eq(c, x),
        Snap.Json.lit.next(t, top), JBad{}), keys}

def Snap.Json.key(+c: U32, +first: Bool, keys: List<&2, List<&2, U32>>) -> Snap.Json.P:
  P{Snap.Json.pick(Snap.Json.St, Snap.Json.ws(c), JKey{first},
    Snap.Json.pick(Snap.Json.St, U32.is_eq(c, 34), JStr{Nil{}, ENone{}},
      Snap.Json.pick(Snap.Json.St, first && U32.is_eq(c, 125), JEnd{}, JBad{}))), keys}

def Snap.Json.colon(+c: U32) -> Snap.Json.St:
  Snap.Json.pick(Snap.Json.St, Snap.Json.ws(c), JColon{}, Snap.Json.pick(Snap.Json.St, U32.is_eq(c, 58), JVal{}, JBad{}))

def Snap.Json.skip.close.p(p: Nat) -> Snap.Json.St:
  match p:
    case 0n:
      JNext{}
    case 1n+q:
      JSkip{1n+q, False{}, False{}}

def Snap.Json.skip.close(d: Nat) -> Snap.Json.St:
  match d:
    case 0n:
      JBad{}
    case 1n+p:
      Snap.Json.skip.close.p(p)

def Snap.Json.skip(+c: U32, +d: Nat, str: Bool, esc: Bool) -> Snap.Json.St:
  match str:
    case True{}:
      Snap.Json.pick(Snap.Json.St, esc, JSkip{d, True{}, False{}},
        Snap.Json.pick(Snap.Json.St, U32.is_eq(c, 92), JSkip{d, True{}, True{}},
          Snap.Json.pick(Snap.Json.St, U32.is_eq(c, 34), JSkip{d, False{}, False{}}, JSkip{d, True{}, False{}})))
    case False{}:
      Snap.Json.pick(Snap.Json.St, U32.is_eq(c, 34), JSkip{d, True{}, False{}},
        Snap.Json.pick(Snap.Json.St, U32.is_eq(c, 123), JSkip{1n+d, False{}, False{}},
          Snap.Json.pick(Snap.Json.St, U32.is_eq(c, 125), Snap.Json.skip.close(d), JSkip{d, False{}, False{}})))

def Snap.Json.next(+c: U32) -> Snap.Json.St:
  Snap.Json.pick(Snap.Json.St, Snap.Json.ws(c), JNext{},
    Snap.Json.pick(Snap.Json.St, U32.is_eq(c, 44), JKey{False{}},
      Snap.Json.pick(Snap.Json.St, U32.is_eq(c, 125), JEnd{}, JBad{})))

def Snap.Json.step(+c: U32, p: Snap.Json.P) -> Snap.Json.P:
  match p:
    case P{JStart{}, keys}:
      Snap.Json.start(c, keys, True{})
    case P{JLit{rest, top}, keys}:
      Snap.Json.lit(c, rest, top, keys)
    case P{JKey{first}, keys}:
      Snap.Json.key(c, first, keys)
    case P{JStr{acc, e}, keys}:
      Snap.Json.kstr(c, acc, e, keys)
    case P{JColon{}, keys}:
      P{Snap.Json.colon(c), keys}
    case P{JVal{}, keys}:
      Snap.Json.start(c, keys, False{})
    case P{JSkip{d, s, e}, keys}:
      P{Snap.Json.skip(c, d, s, e), keys}
    case P{JNext{}, keys}:
      P{Snap.Json.next(c), keys}
    case P{JEnd{}, keys}:
      P{Snap.Json.pick(Snap.Json.St, Snap.Json.ws(c), JEnd{}, JBad{}), keys}
    case P{JBad{}, keys}:
      P{JBad{}, keys}

def Snap.Json.run(bs: +List<U32>, p: Snap.Json.P) -> Snap.Json.P:
  match bs:
    case Nil{}:
      p
    case Con{c, t}:
      Snap.Json.run(t, Snap.Json.step(c, p))

def Snap.Json.fin(p: Snap.Json.P) -> Result<&2, &2, String, List<&2, List<&2, U32>>>:
  match p:
    case P{JEnd{}, keys}:
      Done{List.reverse(&2, List<&2, U32>, keys)}
    case P{st, keys}:
      Fail{"invalid JSON"}

# json.Unmarshal of the skip keys entry into map[string]struct{}: the keys
# of an object whose values are objects or null (null alone is no keys).
# The error text is not Go's.
def Snap.skipkeys_parse(bs: +List<U32>) -> Result<&2, &2, String, List<&2, List<&2, U32>>>:
  Snap.Json.fin(Snap.Json.run(bs, P{JStart{}, Nil{}}))

def Snap.etcd_archive.opt(m: Maybe<&2, Snap.Rec>, rest: List<&2, Snap.Rec>) -> List<&2, Snap.Rec>:
  match m:
    case None{}:
      rest
    case Some{r}:
      r <> rest

def Snap.etcd_archive.skip(skip: Maybe<&2, List<&2, List<&2, U32>>>) -> List<&2, Snap.Rec>:
  match skip:
    case None{}:
      Nil{}
    case Some{ks}:
      [Rec{Snap.skipkeys_key(), Snap.skipkeys_json(ks)}]

# Etcd snapshots
# --------------

# writeEtcdSnapshot's records: the release and request, the database, then
# the skip keys (json.Marshal of the set) when the snapshot has a set.
def Snap.etcd_archive(meta: Snap.Meta, db: +List<U32>, skip: Maybe<&2, List<&2, List<&2, U32>>>) -> List<&2, Snap.Rec>:
  match meta:
    case Meta{rel, req}:
      Snap.etcd_archive.opt(Snap.write.release(rel), Snap.etcd_archive.opt(req,
        Rec{Snap.db_key(), db} <> Snap.etcd_archive.skip(skip)))

# A parsed etcd archive (parseEtcdSnapshotArchive): the release and request
# passed through, the database, and the skip keys.
type Snap.Etcd is Data:
  Etcd{meta: Snap.Meta, db: List<&2, U32>, skip: List<&2, List<&2, U32>>}

# The parse so far: the metadata, the database if seen, the skip keys.
type Snap.EtcdAcc is Data:
  EtcdAcc{meta: Snap.Meta, db: Maybe<&2, List<&2, U32>>, skip: List<&2, List<&2, U32>>}

def Snap.etcd.rel(+v: +List<U32>, a: Snap.EtcdAcc) -> Result<&2, &2, String, Snap.EtcdAcc>:
  match a:
    case EtcdAcc{Meta{rel, req}, db, skip}:
      Done{EtcdAcc{Meta{Some{v}, req}, db, skip}}

def Snap.etcd.req(r: Snap.Rec, a: Snap.EtcdAcc) -> Result<&2, &2, String, Snap.EtcdAcc>:
  match a:
    case EtcdAcc{Meta{rel, req}, db, skip}:
      Done{EtcdAcc{Meta{rel, Some{r}}, db, skip}}

def Snap.etcd.db(+v: +List<U32>, a: Snap.EtcdAcc) -> Result<&2, &2, String, Snap.EtcdAcc>:
  match a:
    case EtcdAcc{meta, None{}, skip}:
      Done{EtcdAcc{meta, Some{v}, skip}}
    case EtcdAcc{meta, Some{d}, skip}:
      Fail{"archive contains multiple \"/vcluster/snapshot/db\" entries"}

def Snap.etcd.skip(r: Result<&2, &2, String, List<&2, List<&2, U32>>>, a: Snap.EtcdAcc) -> Result<&2, &2, String, Snap.EtcdAcc>:
  match r a:
    case Fail{m} _:
      Fail{"failed to unmarshal skipKeys: " ++ m}
    case Done{ks} EtcdAcc{meta, db, skip}:
      Done{EtcdAcc{meta, db, ks}}

def Snap.etcd.entry.skip(skip: Bool, +v: +List<U32>, a: Snap.EtcdAcc) -> Result<&2, &2, String, Snap.EtcdAcc>:
  match skip:
    case True{}:
      Snap.etcd.skip(Snap.skipkeys_parse(v), a)
    case False{}:
      Done{a}

def Snap.etcd.entry.db(db: Bool, skip: Bool, +v: +List<U32>, a: Snap.EtcdAcc) -> Result<&2, &2, String, Snap.EtcdAcc>:
  match db:
    case True{}:
      Snap.etcd.db(v, a)
    case False{}:
      Snap.etcd.entry.skip(skip, v, a)

def Snap.etcd.entry.req(req: Bool, db: Bool, skip: Bool, r: Snap.Rec, +v: +List<U32>, a: Snap.EtcdAcc) -> Result<&2, &2, String, Snap.EtcdAcc>:
  match req:
    case True{}:
      Snap.etcd.req(r, a)
    case False{}:
      Snap.etcd.entry.db(db, skip, v, a)

def Snap.etcd.entry.if(rel: Bool, req: Bool, db: Bool, skip: Bool, r: Snap.Rec, +v: +List<U32>, a: Snap.EtcdAcc) -> Result<&2, &2, String, Snap.EtcdAcc>:
  match rel:
    case True{}:
      Snap.etcd.rel(v, a)
    case False{}:
      Snap.etcd.entry.req(req, db, skip, r, v, a)

def Snap.etcd.entry(+r: Snap.Rec, a: Snap.EtcdAcc) -> Result<&2, &2, String, Snap.EtcdAcc>:
  +k = Snap.key(r)
  +v = Snap.value(r)
  Snap.etcd.entry.if(Snap.beq(k, Snap.release_key()), Snap.bprefix(k, Snap.request_key()),
    Snap.beq(k, Snap.db_key()), Snap.beq(k, Snap.skipkeys_key()), r, v, a)

def Snap.etcd.go(rs: List<&2, Snap.Rec>, a: Result<&2, &2, String, Snap.EtcdAcc>) -> Result<&2, &2, String, Snap.EtcdAcc>:
  match rs a:
    case _ Fail{m}:
      Fail{m}
    case Nil{} Done{x}:
      Done{x}
    case Con{r, t} Done{x}:
      Snap.etcd.go(t, Snap.etcd.entry(r, x))

def Snap.etcd.fin(a: Result<&2, &2, String, Snap.EtcdAcc>) -> Result<&2, &2, String, Snap.Etcd>:
  match a:
    case Fail{m}:
      Fail{m}
    case Done{EtcdAcc{meta, None{}, skip}}:
      Fail{"failed to find etcd snapshot in source archive"}
    case Done{EtcdAcc{meta, Some{db}, skip}}:
      Done{Etcd{meta, db, skip}}

# parseEtcdSnapshotArchive on an archive's records: the last release and
# request win, a second database or bad skip keys are errors, and the
# database must be there.
def Snap.parse_etcd(rs: List<&2, Snap.Rec>) -> Result<&2, &2, String, Snap.Etcd>:
  Snap.etcd.fin(Snap.etcd.go(rs, Done{EtcdAcc{Snap.meta0(), None{}, Nil{}}}))

def Snap.live.put(keep: Bool, k: +List<U32>, v: +List<U32>, rest: List<&2, Snap.Item>) -> List<&2, Snap.Item>:
  match keep:
    case True{}:
      IVal{k, v} <> rest
    case False{}:
      rest

def Snap.live(kvs: List<&2, Snap.Rec>) -> List<&2, Snap.Item>:
  match kvs:
    case Nil{}:
      Nil{}
    case Con{Rec{+k, v}, t}:
      Snap.live.put(Snap.bprefix(k, [47]), k, v, Snap.live(t))

def Snap.convert.go(e: Result<&2, &2, String, Snap.Etcd>, kvs: List<&2, Snap.Rec>, +rev: Nat) -> Result<&2, &2, String, List<&2, Snap.Rec>>:
  match e:
    case Fail{m}:
      Fail{m}
    case Done{Etcd{meta, db, skip}}:
      Snap.write_kv(meta, Done{rev}, Snap.live(kvs), skip, False{})

def Snap.convert.kind(k: Snap.Kind, +src: List<&2, Snap.Rec>, kvs: List<&2, Snap.Rec>, +rev: Nat) -> Result<&2, &2, String, List<&2, Snap.Rec>>:
  match k:
    case KEtcd{}:
      Snap.convert.go(Snap.parse_etcd(src), kvs, rev)
    case KKeyValue{}:
      Fail{"source snapshot is not an etcd snapshot (kind: KeyValueSnapshot)"}
    case KUnknown{}:
      Fail{"source snapshot is not an etcd snapshot (kind: Unknown)"}

# ConvertEtcdSnapshotToKeyValueSnapshot: the key/value archive of an etcd
# archive (src), given the live keys of its database (kvs, in key order)
# and its revision, which host code reads from the bolt file. Keys outside
# "/" are not listed, as for a live snapshot.
def Snap.convert(+src: List<&2, Snap.Rec>, kvs: List<&2, Snap.Rec>, +rev: Nat) -> Result<&2, &2, String, List<&2, Snap.Rec>>:
  Snap.convert.kind(Snap.kind(src), src, kvs, rev)

# Restore
# -------

# vcluster's backing stores (config.StoreType).
type Snap.Store is Data:
  EmbeddedEtcd{}
  EmbeddedDatabase{}
  DeployedEtcd{}
  ExternalEtcd{}
  ExternalDatabase{}

def Snap.Store.name(s: Snap.Store) -> String:
  match s:
    case EmbeddedEtcd{}:
      "embedded-etcd"
    case EmbeddedDatabase{}:
      "embedded-database"
    case DeployedEtcd{}:
      "deployed-etcd"
    case ExternalEtcd{}:
      "external-etcd"
    case ExternalDatabase{}:
      "external-database"

# The archive Client.Run writes for a store: an etcd snapshot for embedded
# etcd, a key/value snapshot for every other store.
def Snap.snapshot_kind(s: Snap.Store) -> Snap.Kind:
  match s:
    case EmbeddedEtcd{}:
      KEtcd{}
    case EmbeddedDatabase{}:
      KKeyValue{}
    case DeployedEtcd{}:
      KKeyValue{}
    case ExternalEtcd{}:
      KKeyValue{}
    case ExternalDatabase{}:
      KKeyValue{}

# needsEtcdToKeyValueConversion: only embedded etcd restores an etcd
# archive as it is.
def Snap.needs_conversion(k: Snap.Kind, s: Snap.Store) -> Bool:
  match k s:
    case KEtcd{} EmbeddedEtcd{}:
      False{}
    case KEtcd{} _:
      True{}
    case KKeyValue{} _:
      False{}
    case KUnknown{} _:
      False{}

# How a restore proceeds (RestoreClient.Run).
type Snap.Route is Data:
  # restoreEtcdSnapshot: etcdutl restore of the database, then the
  # post-restore mutations (Snap.etcd_mutations).
  RouteEtcd{}
  # Log Snap.conversion_message, Snap.convert, then restoreKeyValueSnapshot.
  RouteConvert{}
  # restoreKeyValueSnapshot (Snap.restore_plan).
  RouteKeyValue{}

def Snap.restore_route.if(conv: Bool) -> Snap.Route:
  match conv:
    case True{}:
      RouteConvert{}
    case False{}:
      RouteKeyValue{}

def Snap.restore_route(+k: Snap.Kind, +s: Snap.Store) -> Snap.Route:
  match k s:
    case KEtcd{} EmbeddedEtcd{}:
      RouteEtcd{}
    case _ _:
      Snap.restore_route.if(Snap.needs_conversion(k, s))

# How a store's data is cleared before a key/value restore.
type Snap.DeleteMethod is Data:
  # vcluster owns the files and deletes them.
  DelNone{}
  # One etcd range delete.
  DelRange{}
  # Key by key: kine has no range delete.
  DelKeyByKey{}

def Snap.DeleteMethod.name(m: Snap.DeleteMethod) -> String:
  match m:
    case DelNone{}:
      "none"
    case DelRange{}:
      "range"
    case DelKeyByKey{}:
      "key-by-key"

# deleteMethodBeforeRestore.
def Snap.delete_method(s: Snap.Store) -> Snap.DeleteMethod:
  match s:
    case EmbeddedEtcd{}:
      DelNone{}
    case EmbeddedDatabase{}:
      DelNone{}
    case DeployedEtcd{}:
      DelRange{}
    case ExternalEtcd{}:
      DelRange{}
    case ExternalDatabase{}:
      DelKeyByKey{}

def Snap.delete_calls.m(m: Snap.DeleteMethod) -> List<&2, String>:
  match m:
    case DelNone{}:
      Nil{}
    case DelRange{}:
      ["DeletePrefix(/)"]
    case DelKeyByKey{}:
      ["DeleteKeysWithPrefix(/)"]

# deleteExistingData: the etcd client calls it makes.
def Snap.delete_calls(s: Snap.Store) -> List<&2, String>:
  Snap.delete_calls.m(Snap.delete_method(s))

def Snap.bump.if(gt: Bool, latest: Nat, snapshot: Nat, bump: Nat) -> Nat:
  match gt:
    case True{}:
      Nat.add(Nat.sub(latest, snapshot), bump)
    case False{}:
      bump

# snapshotRestoreBumpRevision(latest, snapshot, bump).
def Snap.bump(+latest: Nat, +snapshot: Nat, +bump: Nat) -> Nat:
  Snap.bump.if(Nat.is_gt(latest, snapshot), latest, snapshot, bump)

# One put of a key/value restore; a pod's value goes through transformPod
# first (node name and status reset) when pod is set.
type Snap.Put is Data:
  Put{key: List<&2, U32>, value: List<&2, U32>, pod: Bool}

# restoreKeyValueSnapshot: the puts in archive order, and whether the
# store is compacted to the last put's revision (only after a put).
type Snap.Plan is Data:
  Plan{puts: List<&2, Snap.Put>, compact: Bool}

def Snap.split_slash(+bs: +List<U32>) -> List<&2, List<&2, U32>>:
  Snap.Path.segs(bs)

def Snap.root_ca.parts(ps: List<&2, List<&2, U32>>) -> Bool:
  match ps:
    case Con{a, Con{b, Con{+c, Con{d, Con{+e, Nil{}}}}}}:
      Snap.Path.is(c, "configmaps") && Snap.Path.is(e, "kube-root-ca.crt")
    case _:
      False{}

# A new vCluster gets its own certificates: /registry/configmaps/<ns>/
# kube-root-ca.crt (exactly five '/'-parts) is skipped.
def Snap.root_ca(+k: +List<U32>) -> Bool:
  Snap.root_ca.parts(Snap.split_slash(k))

def Snap.plan.put(skip: Bool, +k: +List<U32>, +v: +List<U32>, pod: Bool, rest: List<&2, Snap.Put>) -> List<&2, Snap.Put>:
  match skip:
    case True{}:
      rest
    case False{}:
      Put{k, v, pod} <> rest

def Snap.plan.key(empty: Bool, +k: +List<U32>, +v: +List<U32>, +nv: Bool, +pn: Bool, rest: List<&2, Snap.Put>) -> List<&2, Snap.Put>:
  match empty:
    case True{}:
      Nil{}
    case False{}:
      Snap.plan.put(Snap.bprefix(k, Snap.meta_prefix()) ||
          (nv && (Snap.bprefix(k, Snap.mappings_prefix()) || Snap.root_ca(k))),
        k, v, Snap.bprefix(k, Snap.pod_prefix()) && Bool.not(pn), rest)

def Snap.plan.go(rs: List<&2, Snap.Rec>, +nv: Bool, +pn: Bool) -> List<&2, Snap.Put>:
  match rs:
    case Nil{}:
      Nil{}
    case Con{Rec{+k, +v}, t}:
      Snap.plan.key(List.is_empty(&2, U32, k), k, v, nv, pn, Snap.plan.go(t, nv, pn))

def Snap.plan.fin(+puts: List<&2, Snap.Put>) -> Snap.Plan:
  Plan{puts, Bool.not(List.is_empty(&2, Snap.Put, puts))}

# restoreKeyValueSnapshot over an archive's records, for a restore into a
# new vCluster (nv) and with private nodes (pn): records stop at the first
# empty key; metadata keys are skipped; a new vCluster skips the mappings
# and every namespace's kube-root-ca.crt; pods are transformed unless the
# nodes are private.
def Snap.restore_plan(rs: List<&2, Snap.Rec>, +nv: Bool, +pn: Bool) -> Snap.Plan:
  Snap.plan.fin(Snap.plan.go(rs, nv, pn))

# A mutation of etcd after an etcd restore (postRestoreSnapshotDataMutation).
type Snap.Mutation is Data:
  # Delete a key (a missing key is fine).
  MDelete{key: List<&2, U32>}
  # Delete every key under a prefix.
  MDeletePrefix{prefix: List<&2, U32>}
  # Reset the node name and status of every pod.
  MResetPods{}

def Snap.mut.skip(ks: List<&2, List<&2, U32>>, rest: List<&2, Snap.Mutation>) -> List<&2, Snap.Mutation>:
  match ks:
    case Nil{}:
      rest
    case Con{k, t}:
      MDelete{k} <> Snap.mut.skip(t, rest)

def Snap.mut.ca.is(+k: +List<U32>) -> Bool:
  Snap.bprefix(List.reverse(&2, U32, k), List.reverse(&2, U32, Snap.b("/kube-root-ca.crt")))

def Snap.mut.ca.put(hit: Bool, k: +List<U32>, rest: List<&2, Snap.Mutation>) -> List<&2, Snap.Mutation>:
  match hit:
    case True{}:
      MDelete{k} <> rest
    case False{}:
      rest

def Snap.mut.ca(cms: List<&2, List<&2, U32>>, rest: List<&2, Snap.Mutation>) -> List<&2, Snap.Mutation>:
  match cms:
    case Nil{}:
      rest
    case Con{+k, t}:
      Snap.mut.ca.put(Snap.mut.ca.is(k), k, Snap.mut.ca(t, rest))

def Snap.mut.new(nv: Bool, cms: List<&2, List<&2, U32>>, rest: List<&2, Snap.Mutation>) -> List<&2, Snap.Mutation>:
  match nv:
    case True{}:
      Snap.mut.ca(cms, MDeletePrefix{Snap.mappings_prefix()} <> rest)
    case False{}:
      rest

def Snap.mut.pods(pn: Bool) -> List<&2, Snap.Mutation>:
  match pn:
    case True{}:
      Nil{}
    case False{}:
      [MResetPods{}]

# The mutations after an etcd restore, in order: delete the skip keys; for
# a new vCluster, delete each configmap key ending in /kube-root-ca.crt
# (cms: the keys under /registry/configmaps/) and the mappings; then reset
# the pods unless the nodes are private.
def Snap.etcd_mutations(skip: List<&2, List<&2, U32>>, nv: Bool, cms: List<&2, List<&2, U32>>, pn: Bool) -> List<&2, Snap.Mutation>:
  Snap.mut.skip(skip, Snap.mut.new(nv, cms, Snap.mut.pods(pn)))

# The etcd member of an etcd restore (nameAndPeerURLForConfig): name and
# peer URL.
type Snap.Peer is Data:
  Peer{name: String, url: String}

def Snap.peer.ip.if(empty: Bool, ip: String) -> Result<&2, &2, String, Snap.Peer>:
  match empty:
    case True{}:
      Fail{"could not determine the IP address for the embedded etcd peer"}
    case False{}:
      +i = ip
      Done{Peer{i, "https://" ++ i ++ ":2380"}}

def Snap.peer.ip(+ip: String) -> Result<&2, &2, String, Snap.Peer>:
  Snap.peer.ip.if(String.is_empty(ip), ip)

# Standalone: the IP (VCLUSTER_STANDALONE_IP_ADDRESS) names the member.
# Otherwise <name>-0 in the headless service of the namespace.
def Snap.peer(standalone: Bool, +ip: String, +vc: String, +ns: String) -> Result<&2, &2, String, Snap.Peer>:
  match standalone:
    case True{}:
      Snap.peer.ip(ip)
    case False{}:
      Done{Peer{vc ++ "-0", "https://" ++ vc ++ "-0." ++ vc ++ "-headless." ++ ns ++ ":2380"}}

# resolveSnapshotArgs: the vCluster name and the snapshot URL.
type Snap.Args is Data:
  Args{name: String, url: String}

def Snap.resolve_args.go(standalone: Bool, +args: List<&2, String>) -> Result<&2, &2, String, Snap.Args>:
  match standalone args:
    case True{} Con{u, Nil{}}:
      Done{Args{"", u}}
    case True{} _:
      Fail{"unexpected amount of arguments: " ++ Nat.show(List.length(&2, String, args)) ++
        ", need exactly 1 argument. E.g. vcluster [snapshot|restore] s3://my-bucket/my-key/snapshot1.tar.gz --standalone"}
    case False{} Con{n, Con{u, Nil{}}}:
      Done{Args{n, u}}
    case False{} _:
      Fail{"unexpected amount of arguments: " ++ Nat.show(List.length(&2, String, args)) ++
        ", need exactly 2 arguments. E.g. vcluster [snapshot|restore] my-vcluster s3://my-bucket/my-key/snapshot1.tar.gz"}

def Snap.resolve_args(+args: List<&2, String>, standalone: Bool) -> Result<&2, &2, String, Snap.Args>:
  Snap.resolve_args.go(standalone, args)

# Base64 (Go encoding/base64.StdEncoding.DecodeString)
# ----------------------------------------------------

def Snap.B64.val.if(c: Bool, v: U32, rest: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match c:
    case True{}:
      Some{v}
    case False{}:
      rest

# The value of a base64 character.
def Snap.B64.val(+c: U32) -> Maybe<&2, U32>:
  Snap.B64.val.if(U32.is_ge(c, 65) && U32.is_le(c, 90), (c - 65 : U32),
  Snap.B64.val.if(U32.is_ge(c, 97) && U32.is_le(c, 122), (c - 71 : U32),
  Snap.B64.val.if(U32.is_ge(c, 48) && U32.is_le(c, 57), (c + 4 : U32),
  Snap.B64.val.if(U32.is_eq(c, 43), 62,
  Snap.B64.val.if(U32.is_eq(c, 47), 63, None{})))))

type Snap.B64.St is Data:
  # Sextets of the current quantum (reversed) and the bytes so far
  # (reversed).
  BQ{q: List<&2, U32>, out: List<&2, U32>}
  BDone{r: Result<&2, &2, Nat, List<&2, U32>>}

# The bytes of a quantum of 2, 3 or 4 sextets (given reversed), reversed
# onto out.
def Snap.B64.emit(q: +List<U32>, out: +List<U32>) -> +List<U32>:
  match q:
    case Con{d, Con{c, Con{b, Con{a, Nil{}}}}}:
      +v = U32.or(U32.or(U32.shln(a, 18n), U32.shln(b, 12n)), U32.or(U32.shln(c, 6n), d))
      U32.and(v, 255) <> U32.and(U32.shrn(v, 8n), 255) <> U32.shrn(v, 16n) <> out
    case Con{c, Con{b, Con{a, Nil{}}}}:
      +v = U32.or(U32.or(U32.shln(a, 18n), U32.shln(b, 12n)), U32.shln(c, 6n))
      U32.and(U32.shrn(v, 8n), 255) <> U32.shrn(v, 16n) <> out
    case Con{b, Con{a, Nil{}}}:
      U32.shrn(U32.or(U32.shln(a, 18n), U32.shln(b, 12n)), 16n) <> out
    case _:
      out

def Snap.B64.nl(+c: U32) -> Bool:
  U32.is_eq(c, 10) || U32.is_eq(c, 13)

def Snap.B64.skip_nl.if(nl: Bool, all: +List<U32>, skipped: Snap.B64.Skip, n: Nat) -> Snap.B64.Skip:
  match nl:
    case True{}:
      skipped
    case False{}:
      Skip{all, n}

# The bytes after skipping newlines, and how many were skipped.
def Snap.B64.skip_nl(bs: +List<U32>, +n: Nat) -> Snap.B64.Skip:
  match bs:
    case Nil{}:
      Skip{Nil{}, n}
    case Con{+c, +t}:
      Snap.B64.skip_nl.if(Snap.B64.nl(c), Con{c, t}, Snap.B64.skip_nl(t, 1n+n), n)

type Snap.B64.Skip is Data:
  Skip{rest: List<&2, U32>, n: Nat}

def Snap.B64.tail(s: Snap.B64.Skip, +q: +List<U32>, +out: +List<U32>) -> Snap.B64.St:
  match s:
    case Skip{Nil{}, si}:
      BDone{Done{List.reverse(&2, U32, Snap.B64.emit(q, out))}}
    case Skip{Con{c, t}, si}:
      BDone{Fail{si}}

def Snap.B64.second.if(eq: Bool, t: +List<U32>, +si: Nat, +q: +List<U32>, +out: +List<U32>) -> Snap.B64.St:
  match eq:
    case True{}:
      Snap.B64.tail(Snap.B64.skip_nl(t, 1n+si), q, out)
    case False{}:
      BDone{Fail{Nat.sub(si, 1n)}}

def Snap.B64.second(s: Snap.B64.Skip, +q: +List<U32>, +out: +List<U32>, +total: Nat) -> Snap.B64.St:
  match s:
    case Skip{Nil{}, si}:
      BDone{Fail{total}}
    case Skip{Con{+c, t}, si}:
      Snap.B64.second.if(U32.is_eq(c, 61), t, si, q, out)

# A '=' at index si-1 with j sextets in the quantum.
def Snap.B64.pad(j: Nat, +q: +List<U32>, +out: +List<U32>, t: +List<U32>, +si: Nat, +total: Nat) -> Snap.B64.St:
  match j:
    case 2n:
      Snap.B64.second(Snap.B64.skip_nl(t, si), q, out, total)
    case 3n:
      Snap.B64.tail(Snap.B64.skip_nl(t, si), q, out)
    case _:
      BDone{Fail{Nat.sub(si, 1n)}}

def Snap.B64.add.if(full: Bool, +q: +List<U32>, +out: +List<U32>) -> Snap.B64.St:
  match full:
    case True{}:
      BQ{Nil{}, Snap.B64.emit(q, out)}
    case False{}:
      BQ{q, out}

def Snap.B64.add(+q: +List<U32>, +out: +List<U32>) -> Snap.B64.St:
  Snap.B64.add.if(Nat.is_eq(List.length(&2, U32, q), 4n), q, out)

def Snap.B64.other(nl: Bool, eq: Bool, +q: +List<U32>, +out: +List<U32>, t: +List<U32>, +idx: Nat, +total: Nat) -> Snap.B64.St:
  match nl eq:
    case True{} _:
      BQ{q, out}
    case False{} False{}:
      BDone{Fail{idx}}
    case False{} True{}:
      Snap.B64.pad(List.length(&2, U32, q), q, out, t, 1n+idx, total)

def Snap.B64.char(v: Maybe<&2, U32>, +c: U32, +q: +List<U32>, +out: +List<U32>, t: +List<U32>, +idx: Nat, +total: Nat) -> Snap.B64.St:
  match v:
    case Some{x}:
      Snap.B64.add(x <> q, out)
    case None{}:
      Snap.B64.other(Snap.B64.nl(c), U32.is_eq(c, 61), q, out, t, idx, total)

def Snap.B64.next(+c: U32, t: +List<U32>, st: Snap.B64.St, +idx: Nat, +total: Nat) -> Snap.B64.St:
  match st:
    case BQ{q, out}:
      Snap.B64.char(Snap.B64.val(c), c, q, out, t, idx, total)
    case BDone{r}:
      BDone{r}

def Snap.B64.fin(st: Snap.B64.St, +idx: Nat) -> Result<&2, &2, Nat, List<&2, U32>>:
  match st:
    case BQ{Nil{}, out}:
      Done{List.reverse(&2, U32, out)}
    case BQ{Con{s, q}, out}:
      Fail{Nat.sub(idx, 1n+List.length(&2, U32, q))}
    case BDone{r}:
      r

def Snap.B64.go(bs: +List<U32>, st: Snap.B64.St, +idx: Nat, +total: Nat) -> Result<&2, &2, Nat, List<&2, U32>>:
  match bs:
    case Nil{}:
      Snap.B64.fin(st, idx)
    case Con{+c, +t}:
      Snap.B64.go(t, Snap.B64.next(c, t, st, idx, total), 1n+idx, total)

# The decoded bytes, or the index Go's CorruptInputError names.
def Snap.B64.decode(+bs: +List<U32>) -> Result<&2, &2, Nat, List<&2, U32>>:
  Snap.B64.go(bs, BQ{Nil{}, Nil{}}, 0n, List.length(&2, U32, bs))

def Snap.Url.lower.if(up: Bool, c: U32) -> U32:
  match up:
    case True{}:
      (c + 32 : U32)
    case False{}:
      c

# URLs (Go net/url)
# -----------------

def Snap.Url.lower(+c: U32) -> U32:
  Snap.Url.lower.if(U32.is_ge(c, 65) && U32.is_le(c, 90), c)

def Snap.Url.lowers(bs: +List<U32>) -> +List<U32>:
  match bs:
    case Nil{}:
      Nil{}
    case Con{+c, t}:
      Snap.Url.lower(c) <> Snap.Url.lowers(t)

# A control byte (below ' ' or DEL).
def Snap.Url.ctl(+c: U32) -> Bool:
  Bool.or(U32.is_lt(c, 32), U32.is_eq(c, 127))

def Snap.Url.has_ctl(bs: +List<U32>) -> Bool:
  match bs:
    case Nil{}:
      False{}
    case Con{+c, t}:
      Bool.or(Snap.Url.ctl(c), Snap.Url.has_ctl(t))

def Snap.Url.alpha(+c: U32) -> Bool:
  (U32.is_ge(c, 97) && U32.is_le(c, 122)) || (U32.is_ge(c, 65) && U32.is_le(c, 90))

def Snap.Url.digit(+c: U32) -> Bool:
  U32.is_ge(c, 48) && U32.is_le(c, 57)

# getScheme's outcome.
type Snap.Url.Sch is Data:
  SchNone{}
  SchErr{}
  SchCut{scheme: List<&2, U32>, rest: List<&2, U32>}

def Snap.Url.sch.cons(c: U32, r: Snap.Url.Sch) -> Snap.Url.Sch:
  match r:
    case SchCut{s, rest}:
      SchCut{c <> s, rest}
    case SchNone{}:
      SchNone{}
    case SchErr{}:
      SchErr{}

def Snap.Url.sch.colon(colon: Bool, first: Bool, t: +List<U32>) -> Snap.Url.Sch:
  match colon first:
    case True{} True{}:
      SchErr{}
    case True{} False{}:
      SchCut{Nil{}, t}
    case False{} _:
      SchNone{}

def Snap.Url.sch.mark(mark: Bool, colon: Bool, first: Bool, c: U32, t: +List<U32>, rest: Snap.Url.Sch) -> Snap.Url.Sch:
  match mark first:
    case True{} True{}:
      SchNone{}
    case True{} False{}:
      Snap.Url.sch.cons(c, rest)
    case False{} _:
      Snap.Url.sch.colon(colon, first, t)

def Snap.Url.sch.if(alpha: Bool, mark: Bool, colon: Bool, first: Bool, c: U32, t: +List<U32>, rest: Snap.Url.Sch) -> Snap.Url.Sch:
  match alpha:
    case True{}:
      Snap.Url.sch.cons(c, rest)
    case False{}:
      Snap.Url.sch.mark(mark, colon, first, c, t, rest)

def Snap.Url.sch.go(bs: +List<U32>, +first: Bool) -> Snap.Url.Sch:
  match bs:
    case Nil{}:
      SchNone{}
    case Con{+c, +t}:
      Snap.Url.sch.if(Snap.Url.alpha(c), Snap.Url.digit(c) || U32.is_eq(c, 43) || U32.is_eq(c, 45) || U32.is_eq(c, 46),
        U32.is_eq(c, 58), first, c, t, Snap.Url.sch.go(t, False{}))

# Go net/url getScheme.
def Snap.Url.scheme(+bs: +List<U32>) -> Snap.Url.Sch:
  Snap.Url.sch.go(bs, True{})

def Snap.count.add(hit: Bool, n: Nat) -> Nat:
  match hit:
    case True{}:
      1n+n
    case False{}:
      n

def Snap.count(bs: +List<U32>, +c: U32) -> Nat:
  match bs:
    case Nil{}:
      0n
    case Con{+x, t}:
      Snap.count.add(U32.is_eq(x, c), Snap.count(t, c))

def Snap.cut_or_all(m: Maybe<&2, Snap.BB>, +bs: +List<U32>) -> Snap.BB:
  match m:
    case None{}:
      BB{bs, Nil{}}
    case Some{p}:
      p

# Go strings.Cut(s, sep) when the missing case is (s, ""): before, after.
def Snap.cut(+bs: +List<U32>, +c: U32) -> Snap.BB:
  Snap.cut_or_all(Snap.Tar.cut(bs, c), bs)

def Snap.Url.ishex(+c: U32) -> Bool:
  Snap.Url.digit(c) || (U32.is_ge(c, 97) && U32.is_le(c, 102)) || (U32.is_ge(c, 65) && U32.is_le(c, 70))

def Snap.Url.unhex.if(d: Bool, lower: Bool, c: U32) -> U32:
  match d lower:
    case True{} _:
      (c - 48 : U32)
    case False{} True{}:
      (c - 87 : U32)
    case False{} False{}:
      (c - 55 : U32)

def Snap.Url.unhex(+c: U32) -> U32:
  Snap.Url.unhex.if(Snap.Url.digit(c), U32.is_ge(c, 97), c)

# The modes of unescape that the snapshot URL uses.
type Snap.Url.Mode is Data:
  MPath{}
  MHost{}
  MUser{}
  MQuery{}
  MFrag{}

def Snap.Url.is_host(m: Snap.Url.Mode) -> Bool:
  match m:
    case MHost{}:
      True{}
    case MPath{}:
      False{}
    case MUser{}:
      False{}
    case MQuery{}:
      False{}
    case MFrag{}:
      False{}

def Snap.Url.is_query(m: Snap.Url.Mode) -> Bool:
  match m:
    case MQuery{}:
      True{}
    case MPath{}:
      False{}
    case MHost{}:
      False{}
    case MUser{}:
      False{}
    case MFrag{}:
      False{}

def Snap.contains1(bs: +List<U32>, +c: U32) -> Bool:
  match bs:
    case Nil{}:
      False{}
    case Con{x, t}:
      U32.is_eq(x, c) || Snap.contains1(t, c)

# A byte a host may hold unescaped (Go's shouldEscape(c, encodeHost) is
# false).
def Snap.Url.host_ok(+c: U32) -> Bool:
  Snap.Url.alpha(c) || Snap.Url.digit(c) || Snap.contains1(Snap.b("!$&'()*+,;=:[]<>\"-_.~"), c)

# The outcome of unescape.
def Snap.Url.esc_err(bs: +List<U32>) -> String:
  "invalid URL escape " ++ Snap.s(Snap.Tar.quote(List.take(&2, U32, bs, 3n)))

# The state of unescape: plain, after '%', after '%' and a byte, failed.
type Snap.Url.U is Data:
  U0{acc: List<&2, U32>}
  U1{acc: List<&2, U32>}
  U2{acc: List<&2, U32>, h1: U32}
  UE{msg: String}

def Snap.Url.u.pct(ok: Bool, host_bad: Bool, +h1: U32, +h2: U32, +acc: +List<U32>) -> Snap.Url.U:
  match ok host_bad:
    case False{} _:
      UE{Snap.Url.esc_err([37, h1, h2])}
    case True{} True{}:
      UE{Snap.Url.esc_err([37, h1, h2])}
    case True{} False{}:
      U0{(Snap.Url.unhex(h1) * 16 + Snap.Url.unhex(h2) : U32) <> acc}

def Snap.Url.u.plain.c(bad_host: Bool, plus: Bool, +c: U32, +acc: +List<U32>) -> Snap.Url.U:
  match bad_host plus:
    case True{} _:
      UE{"invalid character " ++ Snap.s(Snap.Tar.quote([c])) ++ " in host name"}
    case False{} True{}:
      U0{32 <> acc}
    case False{} False{}:
      U0{c <> acc}

def Snap.Url.u.plain(pct: Bool, bad_host: Bool, plus: Bool, +c: U32, +acc: +List<U32>) -> Snap.Url.U:
  match pct:
    case True{}:
      U1{acc}
    case False{}:
      Snap.Url.u.plain.c(bad_host, plus, c, acc)

def Snap.Url.u.step(+c: U32, st: Snap.Url.U, +m: Snap.Url.Mode) -> Snap.Url.U:
  match st:
    case U0{acc}:
      Snap.Url.u.plain(U32.is_eq(c, 37), Snap.Url.is_host(m) && U32.is_lt(c, 128) && Bool.not(Snap.Url.host_ok(c)),
        Snap.Url.is_query(m) && U32.is_eq(c, 43), c, acc)
    case U1{acc}:
      U2{acc, c}
    case U2{acc, +h1}:
      Snap.Url.u.pct(Snap.Url.ishex(h1) && Snap.Url.ishex(c),
        Snap.Url.is_host(m) && U32.is_lt(Snap.Url.unhex(h1), 8) && Bool.not(U32.is_eq(h1, 50) && U32.is_eq(c, 53)),
        h1, c, acc)
    case UE{msg}:
      UE{msg}

def Snap.Url.u.fin(st: Snap.Url.U) -> Result<&2, &2, String, List<&2, U32>>:
  match st:
    case U0{acc}:
      Done{List.reverse(&2, U32, acc)}
    case U1{acc}:
      Fail{Snap.Url.esc_err([37])}
    case U2{acc, h1}:
      Fail{Snap.Url.esc_err([37, h1])}
    case UE{msg}:
      Fail{msg}

def Snap.Url.u.go(bs: +List<U32>, st: Snap.Url.U, +m: Snap.Url.Mode) -> Result<&2, &2, String, List<&2, U32>>:
  match bs:
    case Nil{}:
      Snap.Url.u.fin(st)
    case Con{c, t}:
      Snap.Url.u.go(t, Snap.Url.u.step(c, st, m), m)

# Go net/url unescape(s, mode): %XX decoded; '+' is a space in a query
# component; a host allows %XX only for bytes past 0x7f (and %25), and only
# its own characters. The first error from the left wins.
def Snap.Url.unescape(bs: +List<U32>, +m: Snap.Url.Mode) -> Result<&2, &2, String, List<&2, U32>>:
  Snap.Url.u.go(bs, U0{Nil{}}, m)

# The parts of a parsed URL that a snapshot location reads.
type Snap.Url is Data:
  Url{scheme: List<&2, U32>, opaque: List<&2, U32>, user: Maybe<&2, Snap.Url.User>, host: List<&2, U32>, path: List<&2, U32>, query: List<&2, U32>}

# url.Userinfo: the name, and the password if there was a ':'.
type Snap.Url.User is Data:
  User{name: List<&2, U32>, pass: Maybe<&2, List<&2, U32>>}

def Snap.last_index.pick(hit: Bool, i: Nat, found: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match hit:
    case True{}:
      Some{i}
    case False{}:
      found

def Snap.last_index(bs: +List<U32>, +c: U32, +i: Nat, found: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match bs:
    case Nil{}:
      found
    case Con{+x, t}:
      Snap.last_index(t, c, 1n+i, Snap.last_index.pick(U32.is_eq(x, c), i, found))

def Snap.index.pick(hit: Bool, i: Nat, rest: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match hit:
    case True{}:
      Some{i}
    case False{}:
      rest

def Snap.index(bs: +List<U32>, +c: U32, +i: Nat) -> Maybe<&2, Nat>:
  match bs:
    case Nil{}:
      None{}
    case Con{+x, t}:
      Snap.index.pick(U32.is_eq(x, c), i, Snap.index(t, c, 1n+i))

def Snap.take(+bs: +List<U32>, n: Nat) -> +List<U32>:
  List.take(&2, U32, bs, n)

def Snap.drop(+bs: +List<U32>, n: Nat) -> +List<U32>:
  List.drop(&2, U32, bs, n)

def Snap.all_digits(bs: +List<U32>) -> Bool:
  match bs:
    case Nil{}:
      True{}
    case Con{+c, t}:
      Snap.Url.digit(c) && Snap.all_digits(t)

# Go net/url validOptionalPort.
def Snap.Url.port_ok(bs: +List<U32>) -> Bool:
  match bs:
    case Nil{}:
      True{}
    case Con{+c, t}:
      U32.is_eq(c, 58) && Snap.all_digits(t)

def Snap.Url.port_err(+p: +List<U32>) -> String:
  "invalid port " ++ Snap.s(Snap.Tar.quote(p)) ++ " after host"

def Snap.Url.host.port(ok: Bool, +port: +List<U32>, +host: +List<U32>) -> Result<&2, &2, String, List<&2, U32>>:
  match ok:
    case True{}:
      Snap.Url.unescape(host, MHost{})
    case False{}:
      Fail{Snap.Url.port_err(port)}

def Snap.Url.host.colon(i: Maybe<&2, Nat>, +last: Maybe<&2, Nat>, +host: +List<U32>) -> Result<&2, &2, String, List<&2, U32>>:
  match i:
    case None{}:
      Snap.Url.unescape(host, MHost{})
    case Some{f}:
      +port = Snap.drop(host, Maybe.default(&2, Nat, last, f))
      Snap.Url.host.port(Snap.Url.port_ok(port), port, host)

def Snap.Url.host.bracket.name(p: Result<&2, &2, String, List<&2, U32>>, n: Result<&2, &2, String, List<&2, U32>>) -> Result<&2, &2, String, List<&2, U32>>:
  match p n:
    case Fail{m} _:
      Fail{m}
    case Done{pp} Fail{m}:
      Fail{m}
    case Done{pp} Done{nn}:
      Done{91 <> Snap.app(nn, 93 <> pp)}

def Snap.Url.host.bracket.port(ok: Bool, +port: +List<U32>, +name: +List<U32>) -> Result<&2, &2, String, List<&2, U32>>:
  match ok:
    case False{}:
      Fail{Snap.Url.port_err(port)}
    case True{}:
      Snap.Url.host.bracket.name(Snap.Url.unescape(port, MHost{}), Snap.Url.unescape(name, MHost{}))

def Snap.Url.host.bracket.close(m: Maybe<&2, Nat>, +host: +List<U32>) -> Result<&2, &2, String, List<&2, U32>>:
  match m:
    case None{}:
      Fail{"missing ']' in host"}
    case Some{+ci}:
      +port = Snap.drop(host, 1n+ci)
      Snap.Url.host.bracket.port(Snap.Url.port_ok(port), port, Snap.take(Snap.drop(host, 1n), Nat.sub(ci, 1n)))

def Snap.Url.host.last(strict: Bool, +host: +List<U32>) -> Maybe<&2, Nat>:
  match strict:
    case True{}:
      Snap.index(host, 58, 0n)
    case False{}:
      Snap.last_index(host, 58, 0n, None{})

def Snap.Url.host.bracket(i: Maybe<&2, Nat>, +scheme: +List<U32>, +host: +List<U32>) -> Result<&2, &2, String, List<&2, U32>>:
  match i:
    case None{}:
      Snap.Url.host.colon(Snap.index(host, 58, 0n),
        Snap.Url.host.last(Snap.Path.is(scheme, "http") || Snap.Path.is(scheme, "https"), host), host)
    case Some{0n}:
      Snap.Url.host.bracket.close(Snap.last_index(host, 93, 0n, None{}), host)
    case Some{1n+p}:
      Fail{"invalid IP-literal"}

# Go net/url parseHost: an IP literal in brackets (not checked to be IPv6),
# a port of digits after the last ':' (the first for http and https), and
# the host unescaped in host mode.
def Snap.Url.host(+scheme: +List<U32>, +host: +List<U32>) -> Result<&2, &2, String, List<&2, U32>>:
  Snap.Url.host.bracket(Snap.last_index(host, 91, 0n, None{}), scheme, host)

# Go net/url validUserinfo.
def Snap.Url.userinfo_ok(bs: +List<U32>) -> Bool:
  match bs:
    case Nil{}:
      True{}
    case Con{+c, t}:
      (Snap.Url.alpha(c) || Snap.Url.digit(c) || U32.is_ge(c, 128) ||
        Snap.contains1(Snap.b("-._:~!$&'()*+,;=%@"), c)) && Snap.Url.userinfo_ok(t)

def Snap.Url.user.pair(n: Result<&2, &2, String, List<&2, U32>>, p: Result<&2, &2, String, List<&2, U32>>) -> Result<&2, &2, String, Snap.Url.User>:
  match n p:
    case Fail{m} _:
      Fail{m}
    case Done{a} Fail{m}:
      Fail{m}
    case Done{a} Done{b}:
      Done{User{a, Some{b}}}

def Snap.Url.user.one(n: Result<&2, &2, String, List<&2, U32>>) -> Result<&2, &2, String, Snap.Url.User>:
  match n:
    case Fail{m}:
      Fail{m}
    case Done{a}:
      Done{User{a, None{}}}

def Snap.Url.user.split(m: Maybe<&2, Snap.BB>, +ui: +List<U32>) -> Result<&2, &2, String, Snap.Url.User>:
  match m:
    case None{}:
      Snap.Url.user.one(Snap.Url.unescape(ui, MUser{}))
    case Some{BB{a, b}}:
      Snap.Url.user.pair(Snap.Url.unescape(a, MUser{}), Snap.Url.unescape(b, MUser{}))

def Snap.Url.user(ok: Bool, +ui: +List<U32>) -> Result<&2, &2, String, Snap.Url.User>:
  match ok:
    case True{}:
      Snap.Url.user.split(Snap.Tar.cut(ui, 58), ui)
    case False{}:
      Fail{"net/url: invalid userinfo"}

# The user and host of an authority.
type Snap.Url.Auth is Data:
  Auth{user: Maybe<&2, Snap.Url.User>, host: List<&2, U32>}

def Snap.Url.auth.fin(h: Result<&2, &2, String, List<&2, U32>>, u: Maybe<&2, Result<&2, &2, String, Snap.Url.User>>) -> Result<&2, &2, String, Snap.Url.Auth>:
  match h u:
    case Fail{m} _:
      Fail{m}
    case Done{host} None{}:
      Done{Auth{None{}, host}}
    case Done{host} Some{Fail{m}}:
      Fail{m}
    case Done{host} Some{Done{user}}:
      Done{Auth{Some{user}, host}}

def Snap.Url.auth.at(i: Maybe<&2, Nat>, +scheme: +List<U32>, +a: +List<U32>) -> Result<&2, &2, String, Snap.Url.Auth>:
  match i:
    case None{}:
      Snap.Url.auth.fin(Snap.Url.host(scheme, a), None{})
    case Some{+n}:
      +ui = Snap.take(a, n)
      Snap.Url.auth.fin(Snap.Url.host(scheme, Snap.drop(a, 1n+n)), Some{Snap.Url.user(Snap.Url.userinfo_ok(ui), ui)})

# Go net/url parseAuthority: userinfo before the last '@', then the host.
def Snap.Url.authority(+scheme: +List<U32>, +a: +List<U32>) -> Result<&2, &2, String, Snap.Url.Auth>:
  Snap.Url.auth.at(Snap.last_index(a, 64, 0n, None{}), scheme, a)

def Snap.Url.path.fin(p: Result<&2, &2, String, List<&2, U32>>, scheme: +List<U32>, user: Maybe<&2, Snap.Url.User>, host: +List<U32>, q: +List<U32>) -> Result<&2, &2, String, Snap.Url>:
  match p:
    case Fail{m}:
      Fail{m}
    case Done{path}:
      Done{Url{scheme, Nil{}, user, host, path, q}}

def Snap.Url.path(+scheme: +List<U32>, +q: +List<U32>, a: Result<&2, &2, String, Snap.Url.Auth>, +rest: +List<U32>) -> Result<&2, &2, String, Snap.Url>:
  match a:
    case Fail{m}:
      Fail{m}
    case Done{Auth{user, host}}:
      Snap.Url.path.fin(Snap.Url.unescape(rest, MPath{}), scheme, user, host, q)

def Snap.Url.auth_split(+scheme: +List<U32>, +q: +List<U32>, +rest: +List<U32>) -> Result<&2, &2, String, Snap.Url>:
  +r2 = Snap.drop(rest, 2n)
  +slash = Snap.index(r2, 47, 0n)
  Snap.Url.path(scheme, q, Snap.Url.authority(scheme, Snap.take(r2, Maybe.default(&2, Nat, slash, List.length(&2, U32, r2)))),
    Snap.drop(r2, Maybe.default(&2, Nat, slash, List.length(&2, U32, r2))))

def Snap.Url.after_query.auth(auth: Bool, +scheme: +List<U32>, +q: +List<U32>, +rest: +List<U32>) -> Result<&2, &2, String, Snap.Url>:
  match auth:
    case True{}:
      Snap.Url.auth_split(scheme, q, rest)
    case False{}:
      Snap.Url.path(scheme, q, Done{Auth{None{}, Nil{}}}, rest)

def Snap.Url.after_query.colon(colon: Bool, +scheme: +List<U32>, +q: +List<U32>, +rest: +List<U32>) -> Result<&2, &2, String, Snap.Url>:
  match colon:
    case True{}:
      Fail{"first path segment in URL cannot contain colon"}
    case False{}:
      Snap.Url.after_query.auth(Snap.bprefix(rest, [47, 47]) && Bool.not(Snap.bprefix(rest, [47, 47, 47])), scheme, q, rest)

def Snap.Url.after_query.opaque(no_scheme: Bool, +scheme: +List<U32>, +q: +List<U32>, +rest: +List<U32>) -> Result<&2, &2, String, Snap.Url>:
  match no_scheme:
    case False{}:
      Done{Url{scheme, rest, None{}, Nil{}, Nil{}, q}}
    case True{}:
      Snap.Url.after_query.colon(Snap.contains1(Snap.fst(Snap.cut(rest, 47)), 58), scheme, q, rest)

def Snap.Url.after_query.rooted(rooted: Bool, +scheme: +List<U32>, +q: +List<U32>, +rest: +List<U32>) -> Result<&2, &2, String, Snap.Url>:
  match rooted:
    case True{}:
      Snap.Url.after_query.auth(Snap.bprefix(rest, [47, 47]) &&
        (Bool.not(List.is_empty(&2, U32, scheme)) || Bool.not(Snap.bprefix(rest, [47, 47, 47]))), scheme, q, rest)
    case False{}:
      Snap.Url.after_query.opaque(List.is_empty(&2, U32, scheme), scheme, q, rest)

def Snap.Url.query.cut(p: Snap.BB, +scheme: +List<U32>) -> Result<&2, &2, String, Snap.Url>:
  match p:
    case BB{+r, q}:
      Snap.Url.after_query.rooted(Snap.bprefix(r, [47]), scheme, q, r)

def Snap.Url.query.if(force: Bool, +scheme: +List<U32>, +rest: +List<U32>) -> Result<&2, &2, String, Snap.Url>:
  match force:
    case True{}:
      +r = Snap.take(rest, Nat.sub(List.length(&2, U32, rest), 1n))
      Snap.Url.after_query.rooted(Snap.bprefix(r, [47]), scheme, Nil{}, r)
    case False{}:
      Snap.Url.query.cut(Snap.cut(rest, 63), scheme)

def Snap.ends_with1.go(t: +List<U32>, c: U32, +x: U32) -> Bool:
  match t:
    case Nil{}:
      U32.is_eq(c, x)
    case Con{d, u}:
      Snap.ends_with1.go(u, d, x)

# Go: strings.HasSuffix(s, string(x)) for one byte x.
def Snap.ends_with1(bs: +List<U32>, +x: U32) -> Bool:
  match bs:
    case Nil{}:
      False{}
    case Con{c, t}:
      Snap.ends_with1.go(t, c, x)

def Snap.Url.rest(+scheme: +List<U32>, +rest: +List<U32>) -> Result<&2, &2, String, Snap.Url>:
  Snap.Url.query.if(Snap.ends_with1(rest, 63) && Nat.is_eq(Snap.count(rest, 63), 1n), Snap.Url.lowers(scheme), rest)

def Snap.Url.sch(s: Snap.Url.Sch, +bs: +List<U32>) -> Result<&2, &2, String, Snap.Url>:
  match s:
    case SchNone{}:
      Snap.Url.rest(Nil{}, bs)
    case SchErr{}:
      Fail{"missing protocol scheme"}
    case SchCut{scheme, rest}:
      Snap.Url.rest(scheme, rest)

def Snap.Url.parse.ctl(ctl: Bool, star: Bool, +bs: +List<U32>) -> Result<&2, &2, String, Snap.Url>:
  match ctl star:
    case True{} _:
      Fail{"net/url: invalid control character in URL"}
    case False{} True{}:
      Done{Url{Nil{}, Nil{}, None{}, Nil{}, [42], Nil{}}}
    case False{} False{}:
      Snap.Url.sch(Snap.Url.scheme(bs), bs)

# Go net/url parse(rawURL, false).
def Snap.Url.parse0(+bs: +List<U32>) -> Result<&2, &2, String, Snap.Url>:
  Snap.Url.parse.ctl(Snap.Url.has_ctl(bs), Snap.beq(bs, [42]), bs)

def Snap.Url.wrap(+u: +List<U32>, r: Result<&2, &2, String, Snap.Url>) -> Result<&2, &2, String, Snap.Url>:
  match r:
    case Fail{m}:
      Fail{"parse " ++ Snap.s(Snap.Tar.quote(u)) ++ ": " ++ m}
    case Done{x}:
      Done{x}

def Snap.Url.frag.check(f: Result<&2, &2, String, List<&2, U32>>, +raw: +List<U32>, x: Snap.Url) -> Result<&2, &2, String, Snap.Url>:
  match f:
    case Fail{m}:
      Fail{"parse " ++ Snap.s(Snap.Tar.quote(raw)) ++ ": " ++ m}
    case Done{y}:
      Done{x}

def Snap.Url.frag(+raw: +List<U32>, +frag: +List<U32>, r: Result<&2, &2, String, Snap.Url>) -> Result<&2, &2, String, Snap.Url>:
  match r:
    case Fail{m}:
      Fail{m}
    case Done{x}:
      Snap.Url.frag.check(Snap.Url.unescape(frag, MFrag{}), raw, x)

def Snap.Url.parse.cut(p: Snap.BB, +raw: +List<U32>) -> Result<&2, &2, String, Snap.Url>:
  match p:
    case BB{+u, +frag}:
      Snap.Url.frag(raw, frag, Snap.Url.wrap(u, Snap.Url.parse0(u)))

# Go net/url.Parse(rawURL): the fragment is cut off and checked; errors
# read `parse "<url>": <reason>`.
def Snap.Url.parse(+bs: +List<U32>) -> Result<&2, &2, String, Snap.Url>:
  Snap.Url.parse.cut(Snap.cut(bs, 35), bs)

# One query parameter.
type Snap.Param is Data:
  Param{key: List<&2, U32>, value: List<&2, U32>}

def Snap.Url.q.split.go(bs: +List<U32>) -> List<&2, List<&2, U32>>:
  match bs:
    case Nil{}:
      [Nil{}]
    case Con{+c, t}:
      Snap.Path.segs.put(U32.is_eq(c, 38), c, Snap.Url.q.split.go(t))

def Snap.Url.q.split(+bs: +List<U32>) -> List<&2, List<&2, U32>>:
  Snap.Url.q.split.go(bs)

def Snap.Url.q.pair(k: Result<&2, &2, String, List<&2, U32>>, v: Result<&2, &2, String, List<&2, U32>>, rest: List<&2, Snap.Param>) -> List<&2, Snap.Param>:
  match k v:
    case Done{a} Done{b}:
      Param{a, b} <> rest
    case _ _:
      rest

def Snap.Url.q.kv(p: Snap.BB, rest: List<&2, Snap.Param>) -> List<&2, Snap.Param>:
  match p:
    case BB{k, v}:
      Snap.Url.q.pair(Snap.Url.unescape(k, MQuery{}), Snap.Url.unescape(v, MQuery{}), rest)

def Snap.Url.q.one(skip: Bool, +chunk: +List<U32>, rest: List<&2, Snap.Param>) -> List<&2, Snap.Param>:
  match skip:
    case True{}:
      rest
    case False{}:
      Snap.Url.q.kv(Snap.cut(chunk, 61), rest)

def Snap.Url.q.go(cs: List<&2, List<&2, U32>>) -> List<&2, Snap.Param>:
  match cs:
    case Nil{}:
      Nil{}
    case Con{+c, t}:
      Snap.Url.q.one(Snap.contains1(c, 59) || List.is_empty(&2, U32, c), c, Snap.Url.q.go(t))

def Snap.Url.query.go(q: +List<U32>) -> List<&2, Snap.Param>:
  match q:
    case Nil{}:
      Nil{}
    case Con{c, t}:
      Snap.Url.q.go(Snap.Url.q.split(Con{c, t}))

# url.URL.Query(): the parameters in order; a chunk with ';' and a pair
# that does not unescape are dropped (Query ignores ParseQuery's error).
def Snap.Url.query(q: +List<U32>) -> List<&2, Snap.Param>:
  Snap.Url.query.go(q)

# Options from query parameters (options.PopulateStructFromMap)
# --------------------------------------------------------------

# A field of an options struct: its url tag key, its Go name, base64 and
# bool.
type Snap.Field is Data:
  Field{key: String, name: String, b64: Bool, bool: Bool}

# A field's value: unset, a string, or a bool.
type Snap.FV is Data:
  FVNone{}
  FVStr{s: List<&2, U32>}
  FVBool{b: Bool}

def Snap.space(+c: U32) -> Bool:
  U32.is_eq(c, 32) || (U32.is_ge(c, 9) && U32.is_le(c, 13))

def Snap.trim_space.left(bs: +List<U32>) -> +List<U32>:
  match bs:
    case Nil{}:
      Nil{}
    case Con{+c, +t}:
      Snap.Tar.trim_left.if(Snap.space(c), c, t, Snap.trim_space.left(t))

def Snap.trim_space.right.put(+c: U32, +rest: +List<U32>) -> +List<U32>:
  Snap.trim_slash.if(List.is_empty(&2, U32, rest) && Snap.space(c), c, rest)

def Snap.trim_space.right(bs: +List<U32>) -> +List<U32>:
  match bs:
    case Nil{}:
      Nil{}
    case Con{+c, +t}:
      Snap.trim_space.right.put(c, Snap.trim_space.right(t))

# Go strings.TrimSpace for ASCII white space.
def Snap.trim_space(+bs: +List<U32>) -> +List<U32>:
  Snap.trim_space.right(Snap.trim_space.left(bs))

def Snap.plus_of_space.c(sp: Bool, c: U32) -> U32:
  match sp:
    case True{}:
      43
    case False{}:
      c

def Snap.plus_of_space(bs: +List<U32>) -> +List<U32>:
  match bs:
    case Nil{}:
      Nil{}
    case Con{+c, t}:
      Snap.plus_of_space.c(U32.is_eq(c, 32), c) <> Snap.plus_of_space(t)

def Snap.parse_bool.if(t: Bool, f: Bool) -> Maybe<&2, Bool>:
  match t f:
    case True{} _:
      Some{True{}}
    case False{} True{}:
      Some{False{}}
    case False{} False{}:
      None{}

def Snap.contains_s(ss: List<&2, String>, +bs: +List<U32>) -> Bool:
  match ss:
    case Nil{}:
      False{}
    case Con{s, t}:
      Snap.beq(Snap.b(s), bs) || Snap.contains_s(t, bs)

def Snap.parse_bool(+bs: +List<U32>) -> Maybe<&2, Bool>:
  Snap.parse_bool.if(Snap.contains_s(["1", "t", "T", "TRUE", "true", "True"], bs),
    Snap.contains_s(["0", "f", "F", "FALSE", "false", "False"], bs))

def Snap.lookup.if(hit: Bool, v: +List<U32>, rest: Maybe<&2, List<&2, U32>>) -> Maybe<&2, List<&2, U32>>:
  match hit:
    case True{}:
      Some{v}
    case False{}:
      rest

def Snap.lookup(ps: List<&2, Snap.Param>, +k: +List<U32>) -> Maybe<&2, List<&2, U32>>:
  match ps:
    case Nil{}:
      None{}
    case Con{Param{+pk, pv}, t}:
      Snap.lookup.if(Snap.beq(pk, k), pv, Snap.lookup(t, k))

def Snap.field.b64(r: Result<&2, &2, Nat, List<&2, U32>>, +name: String) -> Result<&2, &2, String, Snap.FV>:
  match r:
    case Fail{i}:
      Fail{"failed to decode base64 for field " ++ name ++ ": illegal base64 data at input byte " ++ Nat.show(i)}
    case Done{bs}:
      Done{FVStr{Snap.trim_space(bs)}}

def Snap.field.bool(m: Maybe<&2, Bool>, +name: String, +v: +List<U32>) -> Result<&2, &2, String, Snap.FV>:
  match m:
    case None{}:
      Fail{"failed to parse bool for field " ++ name ++ ": strconv.ParseBool: parsing " ++ Snap.s(Snap.Tar.quote(v)) ++ ": invalid syntax"}
    case Some{b}:
      Done{FVBool{b}}

def Snap.field.value(f: Snap.Field, +v: +List<U32>) -> Result<&2, &2, String, Snap.FV>:
  match f:
    case Field{key, +name, True{}, bool}:
      Snap.field.b64(Snap.B64.decode(Snap.trim_space(Snap.plus_of_space(v))), name)
    case Field{key, +name, False{}, True{}}:
      Snap.field.bool(Snap.parse_bool(v), name, v)
    case Field{key, name, False{}, False{}}:
      Done{FVStr{Snap.trim_space(v)}}

def Snap.field.get(m: Maybe<&2, List<&2, U32>>, f: Snap.Field) -> Result<&2, &2, String, Snap.FV>:
  match m:
    case None{}:
      Done{FVNone{}}
    case Some{v}:
      Snap.field.value(f, v)

def Snap.field.key(f: Snap.Field) -> +List<U32>:
  match f:
    case Field{key, name, b, o}:
      Snap.b(key)

def Snap.fields.cons.rest(v: Snap.FV, rest: Result<&2, &2, String, List<&2, Snap.FV>>) -> Result<&2, &2, String, List<&2, Snap.FV>>:
  match rest:
    case Fail{m}:
      Fail{m}
    case Done{vs}:
      Done{v <> vs}

def Snap.fields.cons(r: Result<&2, &2, String, Snap.FV>, rest: Result<&2, &2, String, List<&2, Snap.FV>>) -> Result<&2, &2, String, List<&2, Snap.FV>>:
  match r:
    case Fail{m}:
      Fail{m}
    case Done{v}:
      Snap.fields.cons.rest(v, rest)

def Snap.fields.go(fs: List<&2, Snap.Field>, +ps: List<&2, Snap.Param>) -> Result<&2, &2, String, List<&2, Snap.FV>>:
  match fs:
    case Nil{}:
      Done{Nil{}}
    case Con{+f, t}:
      Snap.fields.cons(Snap.field.get(Snap.lookup(ps, Snap.field.key(f)), f), Snap.fields.go(t, ps))

def Snap.fields.known(fs: List<&2, Snap.Field>, +k: +List<U32>) -> Bool:
  match fs:
    case Nil{}:
      False{}
    case Con{+f, t}:
      Snap.beq(Snap.field.key(f), k) || Snap.fields.known(t, k)

def Snap.fields.unknown(ps: List<&2, Snap.Param>, +fs: List<&2, Snap.Field>) -> Maybe<&2, List<&2, U32>>:
  match ps:
    case Nil{}:
      None{}
    case Con{Param{+k, v}, t}:
      Snap.lookup.if(Bool.not(Snap.fields.known(fs, k)), k, Snap.fields.unknown(t, fs))

def Snap.fields.strict(r: Result<&2, &2, String, List<&2, Snap.FV>>, u: Maybe<&2, List<&2, U32>>) -> Result<&2, &2, String, List<&2, Snap.FV>>:
  match r u:
    case Fail{m} _:
      Fail{m}
    case Done{vs} None{}:
      Done{vs}
    case Done{vs} Some{k}:
      Fail{"unknown parameter in url: " ++ Snap.s(k)}

# PopulateStructFromMap(&opts, query, true): each field in struct order
# from its first value (base64 fields decoded after spaces become '+';
# strings trimmed; bools by strconv.ParseBool), then an unknown key is an
# error (the first in URL order; Go names one of them).
def Snap.populate(+fs: List<&2, Snap.Field>, +ps: List<&2, Snap.Param>) -> Result<&2, &2, String, List<&2, Snap.FV>>:
  Snap.fields.strict(Snap.fields.go(fs, ps), Snap.fields.unknown(ps, fs))

# The url-tagged fields of snapshotapi.S3Options, in order.
def Snap.s3_fields() -> List<&2, Snap.Field>:
  [Field{"skip-client-credentials", "SkipClientCredentials", False{}, True{}},
   Field{"access-key-id", "AccessKeyID", True{}, False{}},
   Field{"secret-access-key", "SecretAccessKey", True{}, False{}},
   Field{"session-token", "SessionToken", True{}, False{}},
   Field{"region", "Region", False{}, False{}},
   Field{"profile", "Profile", False{}, False{}},
   Field{"url", "S3URL", True{}, False{}},
   Field{"public-url", "PublicURL", True{}, False{}},
   Field{"kms-key-id", "KmsKeyID", True{}, False{}},
   Field{"tagging", "Tagging", True{}, False{}},
   Field{"force-path-style", "S3ForcePathStyle", False{}, True{}},
   Field{"insecure-skip-tls-verify", "InsecureSkipTLSVerify", False{}, True{}},
   Field{"custom-key-encryption-file", "CustomerKeyEncryptionFile", True{}, False{}},
   Field{"credentials-file", "CredentialsFile", True{}, False{}},
   Field{"server-side-encryption", "ServerSideEncryption", True{}, False{}},
   Field{"ca-cert", "CACert", True{}, False{}},
   Field{"checksum-algorithm", "ChecksumAlgorithm", False{}, False{}}]

# The url-tagged fields of snapshotapi.OCIOptions, in order.
def Snap.oci_fields() -> List<&2, Snap.Field>:
  [Field{"username", "Username", False{}, False{}},
   Field{"password", "Password", True{}, False{}},
   Field{"skip-client-credentials", "SkipClientCredentials", False{}, True{}}]

# Snapshot locations
# ------------------

# snapshotapi.S3Options.
type Snap.S3 is Data:
  S3{bucket: List<&2, U32>, key: List<&2, U32>, skip_client_credentials: Bool,
     access_key_id: List<&2, U32>, secret_access_key: List<&2, U32>, session_token: List<&2, U32>,
     region: List<&2, U32>, profile: List<&2, U32>, url: List<&2, U32>, public_url: List<&2, U32>,
     kms_key_id: List<&2, U32>, tagging: List<&2, U32>, force_path_style: Bool, insecure_skip_tls_verify: Bool,
     customer_key_encryption_file: List<&2, U32>, credentials_file: List<&2, U32>,
     server_side_encryption: List<&2, U32>, ca_cert: List<&2, U32>, checksum_algorithm: List<&2, U32>}

# snapshotapi.OCIOptions.
type Snap.Oci is Data:
  Oci{repository: List<&2, U32>, username: List<&2, U32>, password: List<&2, U32>, skip_client_credentials: Bool}

# Where a snapshot is stored (snapshotapi.Options by Type). LFile is
# vk8s's own: a file on the host that runs vk8s.
type Snap.Loc is Data:
  LS3{opts: Snap.S3}
  LContainer{path: List<&2, U32>}
  LOci{opts: Snap.Oci}
  LAzure{blob_url: List<&2, U32>}
  LFile{path: List<&2, U32>}

def Snap.fv.s(v: Snap.FV) -> +List<U32>:
  match v:
    case FVStr{s}:
      s
    case FVNone{}:
      Nil{}
    case FVBool{b}:
      Nil{}

def Snap.fv.b(v: Snap.FV) -> Bool:
  match v:
    case FVBool{b}:
      b
    case FVNone{}:
      False{}
    case FVStr{s}:
      False{}

def Snap.s3.of(bucket: +List<U32>, key: +List<U32>, vs: List<&2, Snap.FV>) -> Snap.Loc:
  match vs:
    case [scc, aki, sak, st, reg, prof, url, purl, kms, tag, fps, istv, ckef, cf, sse, ca, ca2]:
      LS3{S3{bucket, key, Snap.fv.b(scc), Snap.fv.s(aki), Snap.fv.s(sak), Snap.fv.s(st), Snap.fv.s(reg),
        Snap.fv.s(prof), Snap.fv.s(url), Snap.fv.s(purl), Snap.fv.s(kms), Snap.fv.s(tag), Snap.fv.b(fps),
        Snap.fv.b(istv), Snap.fv.s(ckef), Snap.fv.s(cf), Snap.fv.s(sse), Snap.fv.s(ca), Snap.fv.s(ca2)}}
    case _:
      LS3{S3{bucket, key, False{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, False{}, False{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}}}

def Snap.oci.pick(v: Snap.FV, d: +List<U32>) -> +List<U32>:
  match v:
    case FVStr{s}:
      s
    case FVNone{}:
      d
    case FVBool{b}:
      d

def Snap.oci.user(u: Maybe<&2, Snap.Url.User>) -> +List<U32>:
  match u:
    case None{}:
      Nil{}
    case Some{User{n, p}}:
      n

def Snap.oci.pass(u: Maybe<&2, Snap.Url.User>) -> +List<U32>:
  match u:
    case None{}:
      Nil{}
    case Some{User{n, None{}}}:
      Nil{}
    case Some{User{n, Some{p}}}:
      p

def Snap.oci.of(+repo: +List<U32>, +user: Maybe<&2, Snap.Url.User>, vs: List<&2, Snap.FV>) -> Snap.Loc:
  match vs:
    case [un, pw, scc]:
      LOci{Oci{repo, Snap.oci.pick(un, Snap.oci.user(user)), Snap.oci.pick(pw, Snap.oci.pass(user)), Snap.fv.b(scc)}}
    case _:
      LOci{Oci{repo, Nil{}, Nil{}, False{}}}

def Snap.opts_err(r: Result<&2, &2, String, List<&2, Snap.FV>>) -> Result<&2, &2, String, List<&2, Snap.FV>>:
  match r:
    case Fail{m}:
      Fail{"error parsing options: " ++ m}
    case Done{vs}:
      Done{vs}

def Snap.parse.s3.vs(r: Result<&2, &2, String, List<&2, Snap.FV>>, bucket: +List<U32>, key: +List<U32>) -> Result<&2, &2, String, Snap.Loc>:
  match r:
    case Fail{m}:
      Fail{m}
    case Done{vs}:
      Done{Snap.s3.of(bucket, key, vs)}

def Snap.trim_prefix1.if(hit: Bool, x: U32, t: +List<U32>) -> +List<U32>:
  match hit:
    case True{}:
      t
    case False{}:
      x <> t

def Snap.trim_prefix1(bs: +List<U32>, c: U32) -> +List<U32>:
  match bs:
    case Nil{}:
      Nil{}
    case Con{+x, +t}:
      Snap.trim_prefix1.if(U32.is_eq(x, c), x, t)

def Snap.parse.s3.if(no_host: Bool, no_path: Bool, host: +List<U32>, +path: +List<U32>, +q: +List<U32>) -> Result<&2, &2, String, Snap.Loc>:
  match no_host no_path:
    case True{} _:
      Fail{"bucket name is missing from url, expected format: s3://BUCKET/KEY"}
    case False{} True{}:
      Fail{"bucket key is missing from url, expected format: s3://BUCKET/KEY"}
    case False{} False{}:
      Snap.parse.s3.vs(Snap.opts_err(Snap.populate(Snap.s3_fields(), Snap.Url.query(q))), host, Snap.trim_prefix1(path, 47))

def Snap.parse.s3(u: Snap.Url) -> Result<&2, &2, String, Snap.Loc>:
  match u:
    case Url{scheme, opaque, user, +host, +path, +q}:
      Snap.parse.s3.if(List.is_empty(&2, U32, host), List.is_empty(&2, U32, path), host, path, q)

def Snap.parse.container.if(no_host: Bool, no_path: Bool, path: +List<U32>) -> Result<&2, &2, String, Snap.Loc>:
  match no_host no_path:
    case False{} _:
      Fail{"relative paths are not supported for container snapshots"}
    case True{} True{}:
      Fail{"couldn't find path for url"}
    case True{} False{}:
      Done{LContainer{path}}

def Snap.parse.container(u: Snap.Url) -> Result<&2, &2, String, Snap.Loc>:
  match u:
    case Url{scheme, opaque, user, +host, +path, q}:
      Snap.parse.container.if(List.is_empty(&2, U32, host), List.is_empty(&2, U32, path), path)

def Snap.parse.oci.vs(r: Result<&2, &2, String, List<&2, Snap.FV>>, +repo: +List<U32>, user: Maybe<&2, Snap.Url.User>) -> Result<&2, &2, String, Snap.Loc>:
  match r:
    case Fail{m}:
      Fail{m}
    case Done{vs}:
      Done{Snap.oci.of(repo, user, vs)}

def Snap.parse.oci.if(bad: Bool, +host: +List<U32>, +path: +List<U32>, user: Maybe<&2, Snap.Url.User>, +q: +List<U32>) -> Result<&2, &2, String, Snap.Loc>:
  match bad:
    case True{}:
      Fail{"unexpected format, need oci://my-registry.com/my-repo"}
    case False{}:
      Snap.parse.oci.vs(Snap.opts_err(Snap.populate(Snap.oci_fields(), Snap.Url.query(q))),
        Snap.Path.clean(Snap.app(host, 47 <> path)), user)

def Snap.parse.oci(u: Snap.Url) -> Result<&2, &2, String, Snap.Loc>:
  match u:
    case Url{scheme, opaque, user, +host, +path, +q}:
      Snap.parse.oci.if(List.is_empty(&2, U32, path) || List.is_empty(&2, U32, host), host, path, user, q)

def Snap.parse.scheme.https(https: Bool, +raw: +List<U32>) -> Result<&2, &2, String, Snap.Loc>:
  match https:
    case True{}:
      Done{LAzure{raw}}
    case False{}:
      Fail{"scheme needs to be one of oci, s3, container, https"}

def Snap.parse.scheme.oci(oci: Bool, https: Bool, u: Snap.Url, +raw: +List<U32>) -> Result<&2, &2, String, Snap.Loc>:
  match oci:
    case True{}:
      Snap.parse.oci(u)
    case False{}:
      Snap.parse.scheme.https(https, raw)

def Snap.parse.scheme.c(c: Bool, oci: Bool, https: Bool, u: Snap.Url, +raw: +List<U32>) -> Result<&2, &2, String, Snap.Loc>:
  match c:
    case True{}:
      Snap.parse.container(u)
    case False{}:
      Snap.parse.scheme.oci(oci, https, u, raw)

def Snap.parse.scheme.if(s3: Bool, c: Bool, oci: Bool, https: Bool, u: Snap.Url, +raw: +List<U32>) -> Result<&2, &2, String, Snap.Loc>:
  match s3:
    case True{}:
      Snap.parse.s3(u)
    case False{}:
      Snap.parse.scheme.c(c, oci, https, u, raw)

def Snap.parse.scheme(+s: +List<U32>, u: Snap.Url, +raw: +List<U32>) -> Result<&2, &2, String, Snap.Loc>:
  Snap.parse.scheme.if(Snap.Path.is(s, "s3"), Snap.Path.is(s, "container"), Snap.Path.is(s, "oci"), Snap.Path.is(s, "https"), u, raw)

def Snap.Url.scheme_of(u: Snap.Url) -> +List<U32>:
  match u:
    case Url{scheme, opaque, user, host, path, q}:
      scheme

def Snap.parse.url(r: Result<&2, &2, String, Snap.Url>, +raw: +List<U32>) -> Result<&2, &2, String, Snap.Loc>:
  match r:
    case Fail{m}:
      Fail{"error parsing snapshotURL " ++ Snap.s(raw) ++ ": " ++ m}
    case Done{+u}:
      Snap.parse.scheme(Snap.Url.scheme_of(u), u, raw)

# vcluster's snapshot.Parse(url): the location of an oci://, s3://,
# container:// or https:// (Azure blob) URL, with Go's error texts.
def Snap.parse_vcluster(+url: +List<U32>) -> Result<&2, &2, String, Snap.Loc>:
  Snap.parse.url(Snap.Url.parse(url), url)

def Snap.parse.file.if(no_host: Bool, no_path: Bool, path: +List<U32>) -> Result<&2, &2, String, Snap.Loc>:
  match no_host no_path:
    case False{} _:
      Fail{"relative paths are not supported for file snapshots"}
    case True{} True{}:
      Fail{"couldn't find path for url"}
    case True{} False{}:
      Done{LFile{path}}

def Snap.parse.file(u: Snap.Url) -> Result<&2, &2, String, Snap.Loc>:
  match u:
    case Url{scheme, opaque, user, +host, +path, q}:
      Snap.parse.file.if(List.is_empty(&2, U32, host), List.is_empty(&2, U32, path), path)

def Snap.parse.vk8s.url(r: Result<&2, &2, String, Snap.Url>, +raw: +List<U32>) -> Result<&2, &2, String, Snap.Loc>:
  match r:
    case Fail{m}:
      Fail{"error parsing snapshotURL " ++ Snap.s(raw) ++ ": " ++ m}
    case Done{u}:
      Snap.parse.file(u)

def Snap.parse.vk8s(file: Bool, +url: +List<U32>) -> Result<&2, &2, String, Snap.Loc>:
  match file:
    case True{}:
      Snap.parse.vk8s.url(Snap.Url.parse(url), url)
    case False{}:
      Snap.parse_vcluster(url)

# vk8s's snapshot location: vcluster's Parse, plus file:///PATH for a file
# on the host that runs vk8s (parsed like container://).
def Snap.parse(+url: +List<U32>) -> Result<&2, &2, String, Snap.Loc>:
  Snap.parse.vk8s(Snap.bprefix(Snap.Url.lowers(url), Snap.b("file:")), url)

def Snap.validate.if(bad: Bool, m: String) -> Maybe<&2, String>:
  match bad:
    case True{}:
      Some{m}
    case False{}:
      None{}

def Snap.validate.s3(no_key: Bool, no_bucket: Bool) -> Maybe<&2, String>:
  match no_key:
    case True{}:
      Some{"key must be specified via s3://BUCKET/KEY"}
    case False{}:
      Snap.validate.if(no_bucket, "bucket must be specified via s3://BUCKET/KEY")

# snapshot.Validate(opts, isList).
def Snap.validate(l: Snap.Loc, is_list: Bool) -> Maybe<&2, String>:
  match l:
    case LS3{S3{bucket, key, a, b, c, d, e, f, g, h, i, j, k, m, n, o, p, q, r}}:
      Snap.validate.s3(Bool.not(is_list) && List.is_empty(&2, U32, key), List.is_empty(&2, U32, bucket))
    case LContainer{path}:
      Snap.validate.if(List.is_empty(&2, U32, path), "path must be specified via container:///PATH")
    case LOci{Oci{repo, u, p, s}}:
      Snap.validate.if(List.is_empty(&2, U32, repo), "repository must be specified via oci://repository")
    case LAzure{url}:
      Snap.validate.if(List.is_empty(&2, U32, url), "blob URL must be specified")
    case LFile{path}:
      Snap.validate.if(List.is_empty(&2, U32, path), "path must be specified via file:///PATH")

# snapshotapi.Options.GetURL.
def Snap.get_url(l: Snap.Loc) -> +List<U32>:
  match l:
    case LS3{S3{bucket, key, a, b, c, d, e, f, g, h, i, j, k, m, n, o, p, q, r}}:
      Snap.app(Snap.b("s3://"), Snap.app(bucket, 47 <> key))
    case LContainer{path}:
      Snap.app(Snap.b("container://"), path)
    case LOci{Oci{repo, u, p, s}}:
      Snap.app(Snap.b("oci://"), repo)
    case LAzure{url}:
      url
    case LFile{path}:
      Snap.app(Snap.b("file://"), path)

def Snap.Url.plain_byte(+c: U32) -> Bool:
  Bool.and(Bool.not(U32.is_eq(c, 37)), Bool.and(Bool.not(U32.is_eq(c, 63)),
    Bool.and(Bool.not(U32.is_eq(c, 35)), Bool.not(Snap.Url.ctl(c)))))

def Snap.Url.plain_bytes(bs: +List<U32>) -> Bool:
  match bs:
    case Nil{}:
      True{}
    case Con{+c, t}:
      Snap.Url.plain_byte(c) && Snap.Url.plain_bytes(t)

# A path that a URL holds as it is: absolute, no control characters, and
# no '%', '?' or '#'.
def Snap.Url.plain_path(bs: +List<U32>) -> Bool:
  match bs:
    case Nil{}:
      False{}
    case Con{+c, +t}:
      U32.is_eq(c, 47) && Snap.Url.plain_bytes(Con{c, t})

def Snap.plan_clean.go(ps: List<&2, Snap.Put>) -> Bool:
  match ps:
    case Nil{}:
      True{}
    case Con{Put{+k, v, p}, t}:
      Bool.not(Snap.bprefix(k, Snap.meta_prefix())) && Snap.plan_clean.go(t)

# No put of a plan is a snapshot metadata key.
def Snap.plan_clean(p: Snap.Plan) -> Bool:
  match p:
    case Plan{ps, c}:
      Snap.plan_clean.go(ps)
