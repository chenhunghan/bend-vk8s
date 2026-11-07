import Base

def Dur.with.go(zero: Bool, +a: U32, +ua: String, +b: U32, +ub: String) -> String:
  match zero:
    case True{}:
      U32.show(a) ++ ua
    case False{}:
      U32.show(a) ++ ua ++ U32.show(b) ++ ub

# k8s.io/apimachinery/pkg/util/duration.HumanDuration over whole seconds
# (vcluster list's AGE column). Ages are never negative here.

def Dur.with(+a: U32, +ua: String, +b: U32, +ub: String) -> String:
  Dur.with.go(U32.is_eq(b, 0), a, ua, b, ub)

def Dur.years.go(under8: Bool, +days: U32) -> String:
  match under8:
    case True{}:
      Dur.with((days / 365 : U32), "y", (days % 365 : U32), "d")
    case False{}:
      U32.show((days / 365 : U32)) ++ "y"

def Dur.years(+hours: U32) -> String:
  +days : U32 = (hours / 24 : U32)
  Dur.years.go(U32.is_lt(hours, 70080), days)

def Dur.days.go(under8d: Bool, under2y: Bool, +hours: U32) -> String:
  match under8d under2y:
    case True{} _:
      Dur.with((hours / 24 : U32), "d", (hours % 24 : U32), "h")
    case False{} True{}:
      U32.show((hours / 24 : U32)) ++ "d"
    case False{} False{}:
      Dur.years(hours)

def Dur.days(+hours: U32) -> String:
  Dur.days.go(U32.is_lt(hours, 192), U32.is_lt(hours, 17520), hours)

def Dur.hours.go(under8: Bool, under48: Bool, +hours: U32, +s: U32) -> String:
  match under8 under48:
    case True{} _:
      Dur.with(hours, "h", ((s / 60 : U32) % 60 : U32), "m")
    case False{} True{}:
      U32.show(hours) ++ "h"
    case False{} False{}:
      Dur.days(hours)

def Dur.hours(+s: U32) -> String:
  +hours : U32 = (s / 3600 : U32)
  Dur.hours.go(U32.is_lt(hours, 8), U32.is_lt(hours, 48), hours, s)

def Dur.minutes.go(under10: Bool, under3h: Bool, +minutes: U32, +s: U32) -> String:
  match under10 under3h:
    case True{} _:
      Dur.with(minutes, "m", (s % 60 : U32), "s")
    case False{} True{}:
      U32.show(minutes) ++ "m"
    case False{} False{}:
      Dur.hours(s)

def Dur.minutes(+s: U32) -> String:
  +minutes : U32 = (s / 60 : U32)
  Dur.minutes.go(U32.is_lt(minutes, 10), U32.is_lt(minutes, 180), minutes, s)

def Dur.human.go(short: Bool, +s: U32) -> String:
  match short:
    case True{}:
      U32.show(s) ++ "s"
    case False{}:
      Dur.minutes(s)

# HumanDuration(s seconds).
def Dur.human(+s: U32) -> String:
  Dur.human.go(U32.is_lt(s, 120), s)
