import Base
import ../laws/oci_fill.bend as L
import ../src/oci/fill.bend as F

# Proofs of laws/oci_fill.bend: `def L.<law>` for each law.

def L.oci_fill.first_miss_fetches():
  {==}

def L.oci_fill.second_follows():
  {==}

def L.oci_fill.headers_to_all():
  {==}

def L.oci_fill.late_follower():
  {==}

def L.oci_fill.commit_on_match():
  {==}

def L.oci_fill.commit_clears():
  {==}

def L.oci_fill.discard_on_mismatch():
  {==}

def L.oci_fill.refetch_after_discard():
  {==}

def L.oci_fill.cached():
  {==}

def L.oci_fill.ranged_miss_passes():
  {==}

def L.oci_fill.upstream_404_blob():
  {==}

def L.oci_fill.upstream_404_manifest():
  {==}

def L.oci_fill.upstream_401():
  {==}

def L.oci_fill.upstream_403():
  {==}

def L.oci_fill.upstream_429():
  {==}

def L.oci_fill.upstream_500():
  {==}

def L.oci_fill.upstream_503():
  {==}

def L.oci_fill.upstream_no_response():
  {==}

def L.oci_fill.no_length():
  {==}

def L.oci_fill.broke_streaming():
  {==}

def L.oci_fill.broke_waiting():
  {==}

def L.oci_fill.wait_24s():
  {==}

def L.oci_fill.timeout_25s():
  {==}

def L.oci_fill.timeout_keeps_fill():
  {==}

def L.oci_fill.no_timeout_streaming():
  {==}

def L.oci_fill.cap_per_digest():
  {==}

def L.oci_fill.cap_fills():
  {==}

def L.oci_fill.cap_conns():
  {==}

def L.oci_fill.gone():
  {==}

def L.oci_fill.gone_still_commits():
  {==}

def L.oci_fill.unknown_digest():
  {==}

def L.oci_fill.two_digests():
  {==}

def L.oci_fill.cached_serves(lim, es, c, d, b, r, n):
  {==}

def L.oci_fill.gone_silent(lim, es, c):
  {==}

# A clash between True{} and False{} proves anything.

def Fl.disc_t(b: Bool) -> Type:
  match b:
    case True{}:
      Empty
    case False{}:
      Unit

def Fl.disc_f(b: Bool) -> Type:
  match b:
    case True{}:
      Unit
    case False{}:
      Empty

law Fl.false_ne_true:
  for h: {False{} == True{} : Bool}
  Empty

def Fl.false_ne_true(h):
  %h : Fl.disc_t(_)
  Unit{}

law Fl.true_ne_false:
  for h: {True{} == False{} : Bool}
  Empty

def Fl.true_ne_false(h):
  %h : Fl.disc_f(_)
  Unit{}

law Fl.absurd_v:
  for -a: F.Verdict
  for -b: F.Verdict
  for e: Empty
  {a == b : F.Verdict}

def Fl.absurd_v(a, b, e):
  match e:

# The verdict on a known comparison, stated {simple == computed}.
law Fl.drop:
  for c: Bool
  for h: {c == False{} : Bool}
  {F.Drop{} == F.Fill.verdict.go(c) : F.Verdict}

def Fl.drop(c, h):
  match c:
    case True{}:
      Fl.absurd_v(F.Drop{}, F.Fill.verdict.go(True{}), Fl.true_ne_false(h))
    case False{}:
      {==}

law Fl.keep:
  for c: Bool
  for h: {c == True{} : Bool}
  {F.Keep{} == F.Fill.verdict.go(c) : F.Verdict}

def Fl.keep(c, h):
  match c:
    case True{}:
      {==}
    case False{}:
      Fl.absurd_v(F.Keep{}, F.Fill.verdict.go(False{}), Fl.false_ne_true(h))

def L.oci_fill.mismatch_never_commits(d, got, blob, len, ws, es, h):
  %Fl.drop(String.eq(d, got), h) : {F.Fill.ended.on(True{}, _, blob, ws, es, d)
    == F.Out{F.Fill.without(es, d), List.append(&2, F.Act, F.Fill.aborts(ws), [F.Discard{d}])} : F.Out}
  {==}

def L.oci_fill.match_commits(d, got, blob, len, ws, es, h):
  %Fl.keep(String.eq(d, got), h) : {F.Fill.ended.on(True{}, _, blob, ws, es, d)
    == F.Out{F.Fill.without(es, d), [F.Commit{d}]} : F.Out}
  {==}
