import Base

# Byte counts and offsets of OCI content as unsigned 64-bit numbers.
# Bend has no U64 and a Nat is unary, so a size is two U32 words. Layers
# above 4 GiB exist, and RFC 9110 byte positions have no upper bound.
# Part of the self-contained OCI library (src/oci/): it imports only Base.

type Size is Data:
  Size{hi: U32, lo: U32}

def Size.zero() -> Size:
  Size{0, 0}

def Size.of(lo: U32) -> Size:
  Size{0, lo}

def Size.is_zero(x: Size) -> Bool:
  match x:
    case Size{h, l}:
      Bool.and(U32.is_zero(h), U32.is_zero(l))

def Size.cmp.lo(c: Cmp, al: U32, bl: U32) -> Cmp:
  match c:
    case LT{}:
      LT{}
    case EQ{}:
      U32.cmp(al, bl)
    case GT{}:
      GT{}

def Size.cmp(a: Size, b: Size) -> Cmp:
  match a b:
    case Size{ah, al} Size{bh, bl}:
      Size.cmp.lo(U32.cmp(ah, bh), al, bl)

def Size.is_lt(a: Size, b: Size) -> Bool:
  Cmp.is_lt(Size.cmp(a, b))

def Size.is_eq(a: Size, b: Size) -> Bool:
  Cmp.is_eq(Size.cmp(a, b))

# a + b, modulo 2^64.
def Size.add(a: Size, b: Size) -> Size:
  match a b:
    case Size{ah, +al} Size{bh, bl}:
      +lo = U32.add(al, bl)
      Size{U32.add(U32.add(ah, bh), Bool.to_u32(U32.is_lt(lo, al))), lo}

# a - b, modulo 2^64 (callers keep b <= a).
def Size.sub(a: Size, b: Size) -> Size:
  match a b:
    case Size{ah, +al} Size{bh, +bl}:
      Size{U32.sub(U32.sub(ah, bh), Bool.to_u32(U32.is_lt(al, bl))), U32.sub(al, bl)}

def Size.inc(x: Size) -> Size:
  Size.add(x, Size{0, 1})

def Size.dec(x: Size) -> Size:
  Size.sub(x, Size{0, 1})

def Size.min.if(lt: Bool, a: Size, b: Size) -> Size:
  match lt:
    case True{}:
      a
    case False{}:
      b

def Size.min(+a: Size, +b: Size) -> Size:
  Size.min.if(Size.is_lt(a, b), a, b)

def Size.shl1(x: Size) -> Size:
  match x:
    case Size{h, +l}:
      Size{U32.or(U32.shln(h, 1n), U32.shrn(l, 31n)), U32.shln(l, 1n)}

# x * 2^n.
def Size.shl(n: Nat, x: Size) -> Size:
  match n:
    case 0n:
      x
    case 1n+p:
      Size.shl(p, Size.shl1(x))

def Size.mul10(+x: Size) -> Size:
  Size.add(Size.shl(3n, x), Size.shl(1n, x))

# Decimal digits only (checked by Size.read before folding).
def Size.digits(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      Bool.and(Char.is_digit(c), Size.digits(t))

def Size.fold(s: String, acc: Size) -> Size:
  match s:
    case SNil{}:
      acc
    case SCon{c, t}:
      Size.fold(t, Size.add(Size.mul10(acc), Size{0, U32.sub(Char.to_u32(c), 48)}))

def Size.read.if(ok: Bool, s: String) -> Maybe<&2, Size>:
  match ok:
    case True{}:
      Some{Size.fold(s, Size{0, 0})}
    case False{}:
      None{}

# A decimal number of 1 to 18 digits (RFC 9110 1*DIGIT; leading zeros
# allowed). 18 digits stay below 2^63, Go's int64 limit for byte positions;
# longer values are refused rather than wrapped.
def Size.read(+s: String) -> Maybe<&2, Size>:
  Size.read.if(Bool.and(Bool.and(Size.digits(s), Bool.not(String.is_empty(s))), Nat.is_le(String.length(s), 18n)), s)

# x divided by 10 and the remainder, by long division over 16-bit halves.
def Size.divmod10(x: Size) -> Size & U32:
  match x:
    case Size{+h, +l}:
      +t1 = U32.or(U32.shln(U32.mod(h, 10), 16n), U32.shrn(l, 16n))
      +t2 = U32.or(U32.shln(U32.mod(t1, 10), 16n), U32.and(l, 65535))
      (Size{U32.div(h, 10), U32.or(U32.shln(U32.div(t1, 10), 16n), U32.div(t2, 10))}, U32.mod(t2, 10))

# The two halves of Size.divmod10, each through its own def: a match
# cannot scrutinize the computed pair in place.
def Size.div10.of(p: Size & U32) -> Size:
  match p:
    case (q, r):
      q

def Size.mod10.of(p: Size & U32) -> U32:
  match p:
    case (q, r):
      r

def Size.div10(x: Size) -> Size:
  Size.div10.of(Size.divmod10(x))

def Size.mod10(x: Size) -> U32:
  Size.mod10.of(Size.divmod10(x))

# Exactly f decimal digits (leading zeros kept) in front of acc.
def Size.show.go(f: Nat, +x: Size, acc: String) -> String:
  match f:
    case 0n:
      acc
    case 1n+g:
      Size.show.go(g, Size.div10(x), SCon{Chr{U32.add(48, Size.mod10(x))}, acc})

def Size.strip(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{'0', t}:
      Size.strip(t)
    case SCon{c, t}:
      SCon{c, t}

def Size.nonempty(s: String) -> String:
  match s:
    case SNil{}:
      "0"
    case SCon{c, t}:
      SCon{c, t}

def Size.show.if(small: Bool, h: U32, l: U32) -> String:
  match small:
    case True{}:
      U32.show(l)
    case False{}:
      Size.nonempty(Size.strip(Size.show.go(20n, Size{h, l}, SNil{})))

# Decimal, without leading zeros.
def Size.show(x: Size) -> String:
  match x:
    case Size{+h, l}:
      Size.show.if(U32.is_zero(h), h, l)
