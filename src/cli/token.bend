import Base

# vcluster token create --expires: Go's time.ParseDuration over whole
# seconds (units ns, us, µs, ms, s, m, h; decimal fractions), as vcluster
# calls it. "" means a token that never expires (vcluster checks that
# first). vk8s refuses a negative duration (Go accepts it).

type Dur is Data:
  Dur{ok: Bool, secs: U32, err: String}

def Tok.digit(+c: U32) -> Bool:
  U32.is_ge(c, 48) && U32.is_le(c, 57)

def Tok.is_digit(c: Char) -> Bool:
  match c:
    case Chr{+u}:
      Tok.digit(u)

def Tok.is_dot(c: Char) -> Bool:
  match c:
    case Chr{+u}:
      U32.is_eq(u, 46)

def Tok.same(a: Bool, b: Bool) -> Bool:
  match a b:
    case True{} True{}:
      True{}
    case False{} False{}:
      True{}
    case _ _:
      False{}

type Sp is Data:
  Sp{a: String, b: String}

def Tok.span.go(keep: Bool, +c: Char, +t: String, r: Sp) -> Sp:
  match keep:
    case True{}:
      match r:
        case Sp{a, b}:
          Sp{SCon{c, a}, b}
    case False{}:
      Sp{"", SCon{c, t}}

# The leading run of number characters (digits) or of other characters
# (not digits), and the rest.
def Tok.span(s: String, +digits: Bool) -> Sp:
  match s:
    case SNil{}:
      Sp{"", ""}
    case SCon{+c, +t}:
      Tok.span.go(Tok.same(Bool.or(Tok.is_digit(c), Tok.is_dot(c)), digits), c, t, Tok.span(t, digits))

def Tok.unit_us.go(ns: Bool, us: Bool, ms: Bool, s: Bool, m: Bool, h: Bool) -> Nat:
  match ns us ms s m h:
    case True{} _ _ _ _ _:
      1n
    case False{} True{} _ _ _ _:
      2n
    case False{} False{} True{} _ _ _:
      3n
    case False{} False{} False{} True{} _ _:
      4n
    case False{} False{} False{} False{} True{} _:
      5n
    case False{} False{} False{} False{} False{} True{}:
      6n
    case _ _ _ _ _ _:
      0n

# A unit's length in nanoseconds / 10^3 (microseconds), as Go's unitMap;
# 0 for an unknown unit.
def Tok.unit_us(+u: String) -> Nat:
  Tok.unit_us.go(String.eq(u, "ns"), String.eq(u, "us") || String.eq(u, "µs") || String.eq(u, "μs"), String.eq(u, "ms"),
    String.eq(u, "s"), String.eq(u, "m"), String.eq(u, "h"))

def Tok.u32_of(s: String, +acc: U32) -> U32:
  match s:
    case SNil{}:
      acc
    case SCon{Chr{+u}, t}:
      Tok.u32_of(t, (acc * 10 + U32.sub(u, 48) : U32))

def Tok.pow10(n: Nat) -> U32:
  match n:
    case 0n:
      1
    case 1n+p:
      (10 * Tok.pow10(p) : U32)

def Tok.times.go(ps: List<&2, String>, +scale: U32) -> U32:
  match ps:
    case Con{+i, Nil{}}:
      (Tok.u32_of(i, 0) * scale : U32)
    case Con{+i, Con{+f, Nil{}}}:
      +f6 : String = String.take(f, 6n)
      (Tok.u32_of(i, 0) * scale + Tok.u32_of(f6, 0) * scale / Tok.pow10(String.length(f6)) : U32)
    case _:
      0

# "int[.frac]" times scale (fractions past 6 digits dropped), truncated.
def Tok.times(num: String, +scale: U32) -> U32:
  Tok.times.go(String.split(num, '.'), scale)

# A part's contribution: whole seconds for s, m and h; microseconds for
# ms, us and ns (carried into seconds at the end).
type Part is Data:
  Part{secs: U32, micros: U32}

def Tok.part(+k: Nat, +num: String) -> Part:
  match k:
    case 0n:
      Part{0, 0}
    case 1n:
      Part{0, (Tok.times(num, 1) / 1000 : U32)}
    case 2n:
      Part{0, Tok.times(num, 1)}
    case 3n:
      Part{0, Tok.times(num, 1000)}
    case 4n:
      Part{Tok.times(num, 1), 0}
    case 5n:
      Part{Tok.times(num, 60), 0}
    case 1n+p:
      Part{Tok.times(num, 3600), 0}

def Tok.num_ok.go(ps: List<&2, String>) -> Bool:
  match ps:
    case Con{+i, Nil{}}:
      Bool.not(String.is_empty(i))
    case Con{+i, Con{+f, Nil{}}}:
      Bool.not(Bool.and(String.is_empty(i), String.is_empty(f)))
    case _:
      False{}

def Tok.num_ok(+num: String) -> Bool:
  Tok.num_ok.go(String.split(num, '.'))

def Tok.invalid(+orig: String) -> Dur:
  Dur{False{}, 0, "time: invalid duration " ++ String.quote(orig)}

# One step of the parse: a number and its unit, then either the end (Fin)
# or what is left (More).
type Stp is Data:
  Fin{d: Dur}
  More{rest: String, secs: U32, micros: U32}

def Tok.step.fin(done: Bool, +rest: String, +sec: U32, +mic: U32) -> Stp:
  match done:
    case True{}:
      Fin{Dur{True{}, (sec + mic / 1000000 : U32), ""}}
    case False{}:
      More{rest, sec, mic}

def Tok.step.next(done: Bool, +rest: String, p: Part, +sec: U32, +mic: U32) -> Stp:
  match p:
    case Part{+ps, +pm}:
      Tok.step.fin(done, rest, (sec + ps : U32), (mic + pm : U32))

def Tok.step.known(unknown: Bool, +k: Nat, +u: String, +num: String, +rest: String, +sec: U32, +mic: U32, +orig: String) -> Stp:
  match unknown:
    case True{}:
      Fin{Dur{False{}, 0, "time: unknown unit " ++ String.quote(u) ++ " in duration " ++ String.quote(orig)}}
    case False{}:
      Tok.step.next(String.is_empty(rest), rest, Tok.part(k, num), sec, mic)

def Tok.step.add(nounit: Bool, +k: Nat, +u: String, +num: String, +rest: String, +sec: U32, +mic: U32, +orig: String) -> Stp:
  match nounit:
    case True{}:
      Fin{Dur{False{}, 0, "time: missing unit in duration " ++ String.quote(orig)}}
    case False{}:
      Tok.step.known(Nat.is_eq(k, 0n), k, u, num, rest, sec, mic, orig)

def Tok.step.unit(ok: Bool, +num: String, ur: Sp, +sec: U32, +mic: U32, +orig: String) -> Stp:
  match ok:
    case False{}:
      Fin{Tok.invalid(orig)}
    case True{}:
      match ur:
        case Sp{+u, +rest}:
          Tok.step.add(String.is_empty(u), Tok.unit_us(u), u, num, rest, sec, mic, orig)

def Tok.step.num(nr: Sp, +sec: U32, +mic: U32, +orig: String) -> Stp:
  match nr:
    case Sp{+num, +rest}:
      Tok.step.unit(Tok.num_ok(num), num, Tok.span(rest, False{}), sec, mic, orig)

def Tok.step(+s: String, +sec: U32, +mic: U32, +orig: String) -> Stp:
  Tok.step.num(Tok.span(s, True{}), sec, mic, orig)

# Parse the rest of a duration (after any sign), accumulating nanoseconds;
# each step eats at least one character, so the length is enough fuel.
def Tok.parts(fuel: Nat, st: Stp, +orig: String) -> Dur:
  match fuel st:
    case _ Fin{d}:
      d
    case 0n More{r, a, m}:
      Tok.invalid(orig)
    case 1n+f More{+r, +a, +m}:
      Tok.parts(f, Tok.step(r, a, m, orig), orig)

def Tok.negative.zero(zero: Bool, +s: String) -> Dur:
  match zero:
    case True{}:
      Dur{True{}, 0, ""}
    case False{}:
      Dur{False{}, 0, "vk8s: --expires " ++ String.quote(s) ++ " is negative"}

def Tok.negative.go(ok: Bool, +n: U32, +e: String, +s: String) -> Dur:
  match ok:
    case True{}:
      Tok.negative.zero(U32.is_eq(n, 0), s)
    case False{}:
      Dur{False{}, 0, e}

def Tok.negative(d: Dur, +s: String) -> Dur:
  match d:
    case Dur{ok, n, e}:
      Tok.negative.go(ok, n, e, s)

def Tok.signed(neg: Bool, plus: Bool, +s: String) -> Dur:
  match neg plus:
    case True{} _:
      Tok.negative(Tok.parts(String.length(s), More{String.drop(s, 1n), 0, 0}, s), s)
    case False{} True{}:
      Tok.parts(String.length(s), More{String.drop(s, 1n), 0, 0}, s)
    case False{} False{}:
      Tok.parts(String.length(s), More{s, 0, 0}, s)

def Tok.duration.go(zero: Bool, +s: String) -> Dur:
  match zero:
    case True{}:
      Dur{True{}, 0, ""}
    case False{}:
      Tok.signed(String.starts_with(s, "-"), String.starts_with(s, "+"), s)

# time.ParseDuration(s), in whole seconds. "0" alone is 0 (Go's special case).
def Tok.duration(+s: String) -> Dur:
  Tok.duration.go(String.eq(s, "0"), s)
