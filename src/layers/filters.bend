import Base

# containerd's filter syntax, as its snapshots service applies a
# ListSnapshots request's filters (pkg/filters: parser.go, scanner.go,
# quote.go, filter.go; core/snapshots/storage/bolt.go WalkInfo). Pure:
# Flt.parse_all reads the filters into selectors; the caller supplies
# each object's fields (src/layers/snap.bend adapts a snapshot as
# adaptSnapshot does) and Flt.test decides one selector.
#
# Grammar (parser.go):
#   selectors := selector ("," selector)*
#   selector  := fieldpath (operator value)
#   fieldpath := field ('.' field)*
#   field     := quoted | [A-Za-z0-9_]+
#   operator  := "==" | "!=" | "~="
#   value     := quoted | [^\s,]+
# A selector without an operator tests that the field is present. All
# selectors of one filter must match (comma is AND); a list of filters
# matches when any one does (ParseAll: Any); no filter, or the filter
# "", matches everything.
#
# As the scanner reads it: white space before a token is skipped, but
# not between a field and the "." or "," after it; a field is a "-quoted
# string (a /- or |-quoted one is refused, "invalid quote encountered");
# a value after "==" or "!=" is "-quoted or runs to the next comma or
# space; after "~=" it may also be quoted with / or |. Quoted strings
# take Go's escapes (\a \b \f \n \r \t \v \\, the quote, \ooo, \xhh,
# \uhhhh, \Uhhhhhhhh). Anything else is a parse error, which the
# service answers with ErrInvalidArgument (Flt.parse_all: None).
#
# Matching (filter.go selector.Match): present; "==" present and equal;
# "!=" not equal (an absent field is ""); "~=" a regular expression
# matched anywhere in the value.
#
# Deviations, both refused (None, ErrInvalidArgument) where containerd
# would answer: a "~=" pattern with a regular expression operator
# (\ . + * ? ( ) | [ ] { } ^ $), as Bend has no RE2; a pattern made of
# plain characters is matched as RE2 would, as a substring. A \x or
# \ooo escape of a byte of 128 or more, which Go keeps as a raw byte
# that no UTF-8 label holds.

type FOp is Data:
  FHas{}
  FEq{}
  FNe{}
  FRe{}

# One selector: the field path, the operator and the value ("" for FHas).
type Sel is Data:
  Sel{path: List<&2, String>, op: FOp, value: String}

# A scan's text and what follows it.
type Cut is Data:
  Cut{text: String, rest: String}

type NCut is Data:
  NCut{v: U32, rest: String}

# The next character of a quoted string: one (decoded), the closing
# quote, or an error.
type QU is Data:
  QOne{c: Char, rest: String}
  QEnd{rest: String}
  QBad{}

# After a field: a "." and more fields, or the end of the field path.
type PStep is Data:
  PDot{field: String, after: String}
  PEnd{field: String, rest: String}
  PBad{}

type PCut is Data:
  PCut{path: List<&2, String>, rest: String}

type SCut is Data:
  SCut{sel: Sel, rest: String}

# After a selector: a "," and more, or the end of the filter.
type LStep is Data:
  LMore{sel: Sel, after: String}
  LEnd{sel: Sel}
  LBad{}

# Runes (scanner.go)
# ------------------

def Flt.rng(+c: U32, +lo: U32, +hi: U32) -> Bool:
  U32.is_ge(c, lo) && U32.is_le(c, hi)

# unicode.IsSpace.
def Flt.is_space(+c: U32) -> Bool:
  U32.is_eq(c, 32) || Flt.rng(c, 9, 13) || U32.is_eq(c, 133) || U32.is_eq(c, 160) || U32.is_eq(c, 5760) || Flt.rng(c, 8192, 8202) || U32.is_eq(c, 8232) || U32.is_eq(c, 8233) || U32.is_eq(c, 8239) || U32.is_eq(c, 8287) || U32.is_eq(c, 12288)

def Flt.is_field(+c: U32) -> Bool:
  U32.is_eq(c, 95) || Flt.rng(c, 65, 90) || Flt.rng(c, 97, 122) || Flt.rng(c, 48, 57)

# "/", "|" and the double quote.
def Flt.is_quote(+c: U32) -> Bool:
  U32.is_eq(c, 47) || U32.is_eq(c, 124) || U32.is_eq(c, 34)

# "," and ".".
def Flt.is_sep(+c: U32) -> Bool:
  U32.is_eq(c, 44) || U32.is_eq(c, 46)

# "=", "!" and "~".
def Flt.is_op(+c: U32) -> Bool:
  U32.is_eq(c, 61) || U32.is_eq(c, 33) || U32.is_eq(c, 126)

# isValueRune: not ",", not space, and graphic (printable ASCII, or
# above the C1 controls).
def Flt.is_value(+c: U32) -> Bool:
  U32.is_ne(c, 44) && Bool.not(Flt.is_space(c)) && (Flt.rng(c, 33, 126) || U32.is_ge(c, 160))

# Classes for Flt.span: 0 field, 1 value, 2 space, 3 operator.
def Flt.in(+cls: U32, +c: U32) -> Bool:
  Bool.pick(Bool, U32.is_eq(cls, 0), Flt.is_field(c),
    Bool.pick(Bool, U32.is_eq(cls, 1), Flt.is_value(c),
      Bool.pick(Bool, U32.is_eq(cls, 2), Flt.is_space(c), Flt.is_op(c))))

# Whether s starts with a character of class cls.
def Flt.hd(+cls: U32, s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{c, t}:
      Flt.in(cls, Char.to_u32(c))

def Flt.cons(c: Char, x: Cut) -> Cut:
  match x:
    case Cut{a, b}:
      Cut{SCon{c, a}, b}

# The longest prefix of s of class cls (ok: whether s starts with one).
def Flt.span(s: String, ok: Bool, +cls: U32) -> Cut:
  match s ok:
    case SCon{c, +t} True{}:
      Flt.cons(c, Flt.span(t, Flt.hd(cls, t), cls))
    case x _:
      Cut{"", x}

def Flt.cut.rest(x: Cut) -> String:
  match x:
    case Cut{a, b}:
      b

# s without its leading white space.
def Flt.skip(+s: String) -> String:
  Flt.cut.rest(Flt.span(s, Flt.hd(2, s), 2))

# Quoted strings (scanner.go scanQuoted, quote.go unquote)
# ------------------------------------------------------

# A digit's value, 16 for none (digitVal).
def Flt.dval(+c: U32) -> U32:
  Bool.pick(U32, Flt.rng(c, 48, 57), (c - 48 : U32),
    Bool.pick(U32, Flt.rng(c, 97, 102), (c - 87 : U32),
      Bool.pick(U32, Flt.rng(c, 65, 70), (c - 55 : U32), 16)))

# n more digits of base after acc.
def Flt.digs(n: Nat, +base: U32, s: String, +acc: U32) -> Maybe<&2, NCut>:
  match n s:
    case 0n x:
      Some{NCut{acc, x}}
    case 1n+m SNil{}:
      None{}
    case 1n+m SCon{c, t}:
      +d : U32 = Flt.dval(Char.to_u32(c))
      Bool.pick(Maybe<&2, NCut>, U32.is_lt(d, base), Flt.digs(m, base, t, ((acc * base : U32) + d : U32)), None{})

# A numeric escape's character, refused above max.
def Flt.esc.num(m: Maybe<&2, NCut>, +max: U32) -> QU:
  match m:
    case None{}:
      QBad{}
    case Some{NCut{+v, r}}:
      Bool.pick(QU, U32.is_le(v, max), QOne{Char.from_u32(v), r}, QBad{})

# The character a one-letter escape stands for, 0 for none.
def Flt.esc.simple(+e: U32, +q: U32) -> U32:
  Bool.pick(U32, U32.is_eq(e, 97), 7,
  Bool.pick(U32, U32.is_eq(e, 98), 8,
  Bool.pick(U32, U32.is_eq(e, 102), 12,
  Bool.pick(U32, U32.is_eq(e, 110), 10,
  Bool.pick(U32, U32.is_eq(e, 114), 13,
  Bool.pick(U32, U32.is_eq(e, 116), 9,
  Bool.pick(U32, U32.is_eq(e, 118), 11,
  Bool.pick(U32, U32.is_eq(e, 92) || U32.is_eq(e, q), e, 0))))))))

# The escape after a backslash: e, then r.
def Flt.esc.at(+e: U32, +r: String, +q: U32) -> QU:
  +v : U32 = Flt.esc.simple(e, q)
  Bool.pick(QU, U32.is_ne(v, 0), QOne{Char.from_u32(v), r},
  Bool.pick(QU, Flt.rng(e, 48, 55), Flt.esc.num(Flt.digs(2n, 8, r, (e - 48 : U32)), 127),
  Bool.pick(QU, U32.is_eq(e, 120), Flt.esc.num(Flt.digs(2n, 16, r, 0), 127),
  Bool.pick(QU, U32.is_eq(e, 117), Flt.esc.num(Flt.digs(4n, 16, r, 0), 1114111),
  Bool.pick(QU, U32.is_eq(e, 85), Flt.esc.num(Flt.digs(8n, 16, r, 0), 1114111), QBad{})))))

def Flt.esc(s: String, +q: U32) -> QU:
  match s:
    case SNil{}:
      QBad{}
    case SCon{e, r}:
      Flt.esc.at(Char.to_u32(e), r, q)

# The next character of a string quoted with q: a newline, a NUL or
# the end of the input is an error.
def Flt.qu.at(+k: U32, c: Char, +t: String, +q: U32) -> QU:
  Bool.pick(QU, U32.is_eq(k, q), QEnd{t},
  Bool.pick(QU, U32.is_eq(k, 10) || U32.is_eq(k, 0), QBad{},
  Bool.pick(QU, U32.is_eq(k, 92), Flt.esc(t, q), QOne{c, t})))

def Flt.qu(s: String, +q: U32) -> QU:
  match s:
    case SNil{}:
      QBad{}
    case SCon{+c, t}:
      Flt.qu.at(Char.to_u32(c), c, t, q)

def Flt.mcons(c: Char, m: Maybe<&2, Cut>) -> Maybe<&2, Cut>:
  match m:
    case None{}:
      None{}
    case Some{x}:
      Some{Flt.cons(c, x)}

# A quoted string's text, decoded, and what follows its closing quote.
def Flt.quoted(f: Nat, u: QU, +q: U32) -> Maybe<&2, Cut>:
  match f u:
    case 0n _:
      None{}
    case 1n+g QOne{c, r}:
      Flt.mcons(c, Flt.quoted(g, Flt.qu(r, q), q))
    case 1n+g QEnd{r}:
      Some{Cut{"", r}}
    case 1n+g QBad{}:
      None{}

# s after its opening quote q.
def Flt.quote(+s: String, +q: U32) -> Maybe<&2, Cut>:
  Flt.quoted(1n+String.length(s), Flt.qu(s, q), q)

# Fields
# ------

def Flt.field.at(+k: U32, c: Char, +t: String) -> Maybe<&2, Cut>:
  Bool.pick(Maybe<&2, Cut>, U32.is_eq(k, 34), Flt.quote(t, 34),
    Bool.pick(Maybe<&2, Cut>, Flt.is_field(k) && U32.is_ne(k, 0), Some{Flt.cons(c, Flt.span(t, Flt.hd(0, t), 0))}, None{}))

def Flt.field.of(s: String) -> Maybe<&2, Cut>:
  match s:
    case SNil{}:
      None{}
    case SCon{+c, t}:
      Flt.field.at(Char.to_u32(c), c, t)

# One field (p.field): white space, then a field or a "-quoted string.
def Flt.field(+s: String) -> Maybe<&2, Cut>:
  Flt.field.of(Flt.skip(s))

def Flt.is_dot(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{c, t}:
      U32.is_eq(Char.to_u32(c), 46)

def Flt.pstep.at(dot: Bool, a: String, r: String) -> PStep:
  match dot r:
    case True{} SCon{c, t}:
      PDot{a, t}
    case _ x:
      PEnd{a, x}

def Flt.pstep(m: Maybe<&2, Cut>) -> PStep:
  match m:
    case None{}:
      PBad{}
    case Some{Cut{a, +r}}:
      Flt.pstep.at(Flt.is_dot(r), a, r)

def Flt.pcons(a: String, m: Maybe<&2, PCut>) -> Maybe<&2, PCut>:
  match m:
    case None{}:
      None{}
    case Some{PCut{p, r}}:
      Some{PCut{Con{a, p}, r}}

# A field path (p.fieldpath): fields joined by "." (no space before it).
def Flt.path(f: Nat, st: PStep) -> Maybe<&2, PCut>:
  match f st:
    case 0n _:
      None{}
    case 1n+g PDot{a, +r}:
      Flt.pcons(a, Flt.path(g, Flt.pstep(Flt.field(r))))
    case 1n+g PEnd{a, r}:
      Some{PCut{[a], r}}
    case 1n+g PBad{}:
      None{}

# Selectors
# ---------

def Flt.op.of(+s: String) -> Maybe<&2, FOp>:
  Bool.pick(Maybe<&2, FOp>, String.eq(s, "=="), Some{FEq{}},
    Bool.pick(Maybe<&2, FOp>, String.eq(s, "!="), Some{FNe{}},
      Bool.pick(Maybe<&2, FOp>, String.eq(s, "~="), Some{FRe{}}, None{})))

def Flt.is_re(op: FOp) -> Bool:
  match op:
    case FRe{}:
      True{}
    case _:
      False{}

def Flt.meta(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{c, t}:
      +k : U32 = Char.to_u32(c)
      U32.is_eq(k, 92) || U32.is_eq(k, 46) || U32.is_eq(k, 43) || U32.is_eq(k, 42) || U32.is_eq(k, 63) || U32.is_eq(k, 40) || U32.is_eq(k, 41) || U32.is_eq(k, 124) || U32.is_eq(k, 91) || U32.is_eq(k, 93) || U32.is_eq(k, 123) || U32.is_eq(k, 125) || U32.is_eq(k, 94) || U32.is_eq(k, 36) || Flt.meta(t)

# A value (p.value): white space, then a quoted string (/ and | only
# after "~="), or a value token.
def Flt.value.at(+k: U32, c: Char, +t: String, +re: Bool) -> Maybe<&2, Cut>:
  Bool.pick(Maybe<&2, Cut>, U32.is_eq(k, 34) || (re && Flt.is_quote(k)), Flt.quote(t, k),
    Bool.pick(Maybe<&2, Cut>, Flt.is_quote(k) || Flt.is_sep(k) || Flt.is_op(k) || U32.is_eq(k, 0), None{},
      Some{Flt.cons(c, Flt.span(t, Flt.hd(1, t), 1))}))

def Flt.value.of(s: String, +re: Bool) -> Maybe<&2, Cut>:
  match s:
    case SNil{}:
      None{}
    case SCon{+c, t}:
      Flt.value.at(Char.to_u32(c), c, t, re)

def Flt.sel.v(p: List<&2, String>, +op: FOp, m: Maybe<&2, Cut>) -> Maybe<&2, SCut>:
  match m:
    case None{}:
      None{}
    case Some{Cut{+v, r}}:
      Bool.pick(Maybe<&2, SCut>, Flt.is_re(op) && Flt.meta(v), None{}, Some{SCut{Sel{p, op, v}, r}})

def Flt.sel.val(p: List<&2, String>, m: Maybe<&2, FOp>, +s: String) -> Maybe<&2, SCut>:
  match m:
    case None{}:
      None{}
    case Some{+op}:
      Flt.sel.v(p, op, Flt.value.of(Flt.skip(s), Flt.is_re(op)))

def Flt.sel.opc(p: List<&2, String>, x: Cut) -> Maybe<&2, SCut>:
  match x:
    case Cut{+o, r}:
      Flt.sel.val(p, Flt.op.of(o), r)

# An operator (p.operator): white space, then a run of "=", "!" and "~".
def Flt.sel.op(p: List<&2, String>, s: String) -> Maybe<&2, SCut>:
  match s:
    case SNil{}:
      None{}
    case SCon{+c, +t}:
      Bool.pick(Maybe<&2, SCut>, Flt.is_op(Char.to_u32(c)), Flt.sel.opc(p, Flt.cons(c, Flt.span(t, Flt.hd(3, t), 3))), None{})

# After a field path: "," or the end is a presence test; anything else
# starts an operator.
def Flt.sel.after(+p: List<&2, String>, r: String) -> Maybe<&2, SCut>:
  match r:
    case SNil{}:
      Some{SCut{Sel{p, FHas{}, ""}, ""}}
    case SCon{+c, +t}:
      Bool.pick(Maybe<&2, SCut>, U32.is_eq(Char.to_u32(c), 44), Some{SCut{Sel{p, FHas{}, ""}, SCon{c, t}}}, Flt.sel.op(p, Flt.skip(SCon{c, t})))

def Flt.sel(m: Maybe<&2, PCut>) -> Maybe<&2, SCut>:
  match m:
    case None{}:
      None{}
    case Some{PCut{p, r}}:
      Flt.sel.after(p, r)

# One selector (p.selector) of s.
def Flt.selector(+s: String) -> Maybe<&2, SCut>:
  Flt.sel(Flt.path(1n+String.length(s), Flt.pstep(Flt.field(s))))

def Flt.lstep.at(s: Sel, r: String) -> LStep:
  match r:
    case SNil{}:
      LEnd{s}
    case SCon{c, t}:
      Bool.pick(LStep, U32.is_eq(Char.to_u32(c), 44), LMore{s, t}, LBad{})

def Flt.lstep(m: Maybe<&2, SCut>) -> LStep:
  match m:
    case None{}:
      LBad{}
    case Some{SCut{s, r}}:
      Flt.lstep.at(s, r)

def Flt.lcons(s: Sel, m: Maybe<&2, List<&2, Sel>>) -> Maybe<&2, List<&2, Sel>>:
  match m:
    case None{}:
      None{}
    case Some{ss}:
      Some{Con{s, ss}}

def Flt.sels(f: Nat, st: LStep) -> Maybe<&2, List<&2, Sel>>:
  match f st:
    case 0n _:
      None{}
    case 1n+g LMore{s, +r}:
      Flt.lcons(s, Flt.sels(g, Flt.lstep(Flt.selector(r))))
    case 1n+g LEnd{s}:
      Some{[s]}
    case 1n+g LBad{}:
      None{}

# One filter (Parse): its selectors, all of which must match; "" has
# none (it matches everything); None for a parse error.
def Flt.parse(+s: String) -> Maybe<&2, List<&2, Sel>>:
  Bool.pick(Maybe<&2, List<&2, Sel>>, String.is_empty(s), Some{Nil{}}, Flt.sels(1n+String.length(s), Flt.lstep(Flt.selector(s))))

def Flt.acons(m: Maybe<&2, List<&2, Sel>>, r: Maybe<&2, List<&2, List<&2, Sel>>>) -> Maybe<&2, List<&2, List<&2, Sel>>>:
  match m r:
    case Some{a} Some{t}:
      Some{Con{a, t}}
    case _ _:
      None{}

def Flt.parse_all.go(fs: List<&2, String>) -> Maybe<&2, List<&2, List<&2, Sel>>>:
  match fs:
    case Nil{}:
      Some{Nil{}}
    case Con{f, t}:
      Flt.acons(Flt.parse(f), Flt.parse_all.go(t))

# Filters (ParseAll): any one of them must match; no filter matches
# everything (one filter with no selector). None: ErrInvalidArgument.
def Flt.parse_all(fs: List<&2, String>) -> Maybe<&2, List<&2, List<&2, Sel>>>:
  match fs:
    case Nil{}:
      Some{[Nil{}]}
    case Con{f, t}:
      Flt.parse_all.go(Con{f, t})

# Matching (filter.go selector.Match)
# -----------------------------------

# Whether a selector with op and want matches a field that has the
# value got (None: the field is not present).
def Flt.test(op: FOp, +want: String, got: Maybe<&2, String>) -> Bool:
  match op got:
    case FHas{} None{}:
      False{}
    case FHas{} Some{v}:
      True{}
    case FEq{} None{}:
      False{}
    case FEq{} Some{v}:
      String.eq(v, want)
    case FNe{} None{}:
      Bool.not(String.is_empty(want))
    case FNe{} Some{v}:
      Bool.not(String.eq(v, want))
    case FRe{} None{}:
      String.is_empty(want)
    case FRe{} Some{v}:
      String.contains(v, want)
