import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../laws/join.bend as L
import ../src/standalone/join.bend as JN

# Proofs of laws/join.bend: `def L.<law>` for each law.
#
# The concrete laws compute. A generated token validates because every
# char Join.pick returns is in [a-z0-9] (Join.pick.at walks an alphabet of
# such chars, or answers '0'), whatever the random value: the id part
# reduces, char by char, to the dot and the secret part, which reduces to
# True. The expiry law rewrites the expiration check, which
# Join.authorize makes first.

# Concrete laws: both sides compute.

def L.join.rand_bytes_0():
  {==}

def L.join.rand_bytes_1():
  {==}

def L.join.rand_bytes_2():
  {==}

def L.join.rand_bytes_3():
  {==}

def L.join.rand_bytes_100():
  {==}

def L.join.token_from.foo_bar():
  {==}

def L.join.token_from.abcdef():
  {==}

def L.join.token_from.h_b():
  {==}

def L.join.valid_token.empty():
  {==}

def L.join.valid_token.dot():
  {==}

def L.join.valid_token.no_dot():
  {==}

def L.join.valid_token.short_id():
  {==}

def L.join.valid_token.no_id():
  {==}

def L.join.valid_token.no_secret():
  {==}

def L.join.valid_token.colon_and_dot():
  {==}

def L.join.valid_token.colon():
  {==}

def L.join.valid_token.upper_id():
  {==}

def L.join.valid_token.upper_secret():
  {==}

def L.join.valid_token.dash():
  {==}

def L.join.valid_token.star():
  {==}

def L.join.valid_token.letters_digits():
  {==}

def L.join.valid_token.digits_letters():
  {==}

def L.join.valid_token.all_upper_id():
  {==}

def L.join.valid_token.mixed():
  {==}

def L.join.valid_token.digits():
  {==}

def L.join.valid_id.empty():
  {==}

def L.join.valid_id.long():
  {==}

def L.join.valid_id.short():
  {==}

def L.join.valid_id.upper_first():
  {==}

def L.join.valid_id.upper():
  {==}

def L.join.valid_id.trailing_dot():
  {==}

def L.join.valid_id.letters():
  {==}

def L.join.valid_id.digits():
  {==}

def L.join.secret_name.foo():
  {==}

def L.join.secret_name.bar():
  {==}

def L.join.secret_name.empty():
  {==}

def L.join.secret_name.abcdef():
  {==}

def L.join.group.valid():
  {==}

def L.join.group.valid_nested():
  {==}

def L.join.group.dashes_number():
  {==}

def L.join.group.uppercase():
  {==}

def L.join.group.missing_prefix():
  {==}

def L.join.group.no_body():
  {==}

def L.join.group.spaces():
  {==}

def L.join.group.asterisk():
  {==}

def L.join.group.trailing_colon():
  {==}

def L.join.group.trailing_dash():
  {==}

def L.join.group.script_tags():
  {==}

def L.join.group.too_long():
  {==}

def L.join.usages.signing():
  {==}

def L.join.usages.authentication():
  {==}

def L.join.usages.all_valid():
  {==}

def L.join.usages.single_invalid():
  {==}

def L.join.usages.all_invalid():
  {==}

def L.join.data.existing_key():
  {==}

def L.join.data.missing_key():
  {==}

def L.join.data.no_data():
  {==}

def L.join.parse_name.valid():
  {==}

def L.join.parse_name.blank():
  {==}

def L.join.parse_name.no_prefix():
  {==}

def L.join.parse_name.no_id():
  {==}

def L.join.parse_name.short_id():
  {==}

def L.join.parse_name.long_id():
  {==}

def L.join.parse_name.invalid_id():
  {==}

def L.join.groups.not_set():
  {==}

def L.join.groups.empty():
  {==}

def L.join.groups.invalid_prefix():
  {==}

def L.join.groups.valid():
  {==}

def L.join.authn.valid_token():
  {==}

def L.join.authn.extra_group():
  {==}

def L.join.authn.invalid_group():
  {==}

def L.join.authn.invalid_secret_name():
  {==}

def L.join.authn.no_usage():
  {==}

def L.join.authn.wrong_token():
  {==}

def L.join.authn.deleted_token():
  {==}

def L.join.authn.expired_token():
  {==}

def L.join.authn.not_expired_token():
  {==}

def L.join.authn.short_id():
  {==}


def L.join.query_escape.empty():
  {==}

def L.join.query_escape.abc():
  {==}

def L.join.query_escape.space():
  {==}

def L.join.query_escape.percent():
  {==}

def L.join.query_escape.reserved():
  {==}

def L.join.query_roundtrip.empty():
  {==}

def L.join.query_roundtrip.abc():
  {==}

def L.join.query_roundtrip.space():
  {==}

def L.join.query_roundtrip.percent():
  {==}

def L.join.query_roundtrip.reserved():
  {==}

def L.join.unescape.empty():
  {==}

def L.join.unescape.abc():
  {==}

def L.join.unescape.one():
  {==}

def L.join.unescape.three():
  {==}

def L.join.unescape.lower_hex():
  {==}

def L.join.unescape.upper_hex():
  {==}

def L.join.unescape.bare_percent():
  {==}

def L.join.unescape.one_hex():
  {==}

def L.join.unescape.one_digit():
  {==}

def L.join.unescape.short_tail():
  {==}

def L.join.unescape.bad_hex():
  {==}

def L.join.unescape.plus():
  {==}

def L.join.unescape.pct20():
  {==}

def L.join.parse_query.one():
  {==}

def L.join.parse_query.two():
  {==}

def L.join.parse_query.repeated():
  {==}

def L.join.parse_query.escaped():
  {==}

def L.join.parse_query.semicolon():
  {==}

def L.join.parse_query.semicolon_key():
  {==}

def L.join.parse_query.escaped_semicolon():
  {==}

def L.join.parse_query.escaped_semicolon_key():
  {==}

def L.join.parse_query.semicolon_after():
  {==}

def L.join.parse_query.semicolon_first():
  {==}

def L.join.parse_query.semicolon_middle():
  {==}

def L.join.parse_query.semicolon_last():
  {==}

def L.join.parse_query.only_semicolon():
  {==}

def L.join.parse_query.trailing_semicolon():
  {==}

def L.join.parse_query.semicolon_segment():
  {==}

def L.join.parse_query.leading_semicolon():
  {==}

def L.join.parse_query.semicolon_end():
  {==}

def L.join.query_get.foo():
  {==}

def L.join.query_get.case_sensitive():
  {==}

def L.join.query_get.first():
  {==}

def L.join.query_get.no_value():
  {==}

def L.join.time.utc():
  {==}

def L.join.time.east():
  {==}

def L.join.time.west_next_day():
  {==}

def L.join.time.leap_day():
  {==}

def L.join.time.no_leap_day():
  {==}

def L.join.time.space():
  {==}

def L.join.time.no_zone():
  {==}

def L.join.time.expiry_format():
  {==}

def L.join.token_secret.worker():
  {==}

def L.join.token_secret.control_plane():
  {==}

def L.join.command.api_endpoint():
  {==}

def L.join.command.platform_endpoint():
  {==}

def L.join.command.kubeadm():
  {==}

def L.join.command.docker_worker():
  {==}

def L.join.request.docker_worker():
  {==}

def L.join.request.token_create():
  {==}

# Bool helpers (as in proofs/services.bend).

def join.bdisc(b: Bool) -> Type:
  match b:
    case False{}:
      Empty
    case True{}:
      Unit

def join.tf_absurd(-A: Type, e: {True{} == False{} : Bool}) -> A:
  Empty.absurd(A, (%e : join.bdisc(_); Unit{}))

law join.and_l:
  for a: Bool
  for b: Bool
  for h: {Bool.and(a, b) == True{} : Bool}
  {a == True{} : Bool}

def join.and_l(a, b, h):
  match a:
    case True{}:
      {==}
    case False{}:
      h

law join.and_r:
  for a: Bool
  for b: Bool
  for h: {Bool.and(a, b) == True{} : Bool}
  {b == True{} : Bool}

def join.and_r(a, b, h):
  match a:
    case True{}:
      h
    case False{}:
      join.tf_absurd({b == True{} : Bool}, Equal.sym(Bool, False{}, True{}, h))

law join.and_i:
  for a: Bool
  for b: Bool
  for ha: {a == True{} : Bool}
  for hb: {b == True{} : Bool}
  {Bool.and(a, b) == True{} : Bool}

def join.and_i(a, b, ha, hb):
  %Equal.sym(Bool, a, True{}, ha) : {Bool.and(_, b) == True{} : Bool}
  hb

# Every char Join.pick returns is a token char.

law join.sel_ok:
  for b: Bool
  for +c: Char
  for +r: Char
  for hc: {JN.Join.tok_char(c) == True{} : Bool}
  for hr: {JN.Join.tok_char(r) == True{} : Bool}
  {JN.Join.tok_char(JN.Join.pick.sel(b, c, r)) == True{} : Bool}

def join.sel_ok(b, c, r, hc, hr):
  match b:
    case True{}:
      hc
    case False{}:
      hr

law join.pick_at_ok:
  for +s: String
  for +k: U32
  for +h: {JN.Join.all_tok(s) == True{} : Bool}
  {JN.Join.tok_char(JN.Join.pick.at(s, k)) == True{} : Bool}

def join.pick_at_ok(s, k, h):
  match s:
    case SNil{}:
      {==}
    case SCon{+c, +t}:
      join.sel_ok(U32.is_eq(k, 0), c, JN.Join.pick.at(t, U32.sub(k, 1)),
        join.and_l(JN.Join.tok_char(c), JN.Join.all_tok(t), h),
        join.pick_at_ok(t, U32.sub(k, 1), join.and_r(JN.Join.tok_char(c), JN.Join.all_tok(t), h)))

law join.pick_ok:
  for +x: U32
  {JN.Join.tok_char(JN.Join.pick(x)) == True{} : Bool}

def join.pick_ok(x):
  join.pick_at_ok(JN.Join.alphabet(), U32.mod(x, 36), {==})

# n picked chars are n token chars ...

law join.sec_ok:
  for +n: Nat
  for +rs: +List<U32>
  {JN.Join.valid.sec(n, JN.Join.chars(n, rs, SNil{})) == True{} : Bool}

def join.sec_ok(n, rs):
  match n:
    case 0n:
      {==}
    case 1n+p:
      join.and_i(JN.Join.tok_char(JN.Join.pick(JN.Join.head0(rs))),
        JN.Join.valid.sec(p, JN.Join.chars(p, JN.Join.tail0(rs), SNil{})),
        join.pick_ok(JN.Join.head0(rs)), join.sec_ok(p, JN.Join.tail0(rs)))

# ... and the id check passes over them to what follows.

law join.id_ok:
  for +n: Nat
  for +rs: +List<U32>
  for +t: String
  {JN.Join.valid.id(n, JN.Join.chars(n, rs, t)) == JN.Join.valid.id(0n, t) : Bool}

def join.id_ok(n, rs, t):
  match n:
    case 0n:
      {==}
    case 1n+p:
      %Equal.sym(Bool, JN.Join.tok_char(JN.Join.pick(JN.Join.head0(rs))), True{}, join.pick_ok(JN.Join.head0(rs))) : {Bool.and(_, JN.Join.valid.id(p, JN.Join.chars(p, JN.Join.tail0(rs), t))) == JN.Join.valid.id(0n, t) : Bool}
      join.id_ok(p, JN.Join.tail0(rs), t)

# General laws.

def L.join.generated_valid(rs):
  %Equal.sym(Bool, JN.Join.valid.id(6n, JN.Join.chars(6n, rs, SCon{'.', JN.Join.chars(16n, List.drop(&2, U32, rs, 6n), SNil{})})),
    JN.Join.valid.id(0n, SCon{'.', JN.Join.chars(16n, List.drop(&2, U32, rs, 6n), SNil{})}),
    join.id_ok(6n, rs, SCon{'.', JN.Join.chars(16n, List.drop(&2, U32, rs, 6n), SNil{})})) : {_ == True{} : Bool}
  join.sec_ok(16n, List.drop(&2, U32, rs, 6n))

def L.join.chars_length(n, rs):
  match n:
    case 0n:
      {==}
    case 1n+p:
      %L.join.chars_length(p, JN.Join.tail0(rs)) : {1n+String.length(JN.Join.chars(p, JN.Join.tail0(rs), SNil{})) == 1n+_ : Nat}
      {==}

def L.join.expired_never_authorizes(q, s, now, h):
  %Equal.sym(Bool, JN.Join.expired(s, now), True{}, h) : {JN.Join.allowed(JN.Join.authorize.exp(_, q, s, now)) == False{} : Bool}
  {==}
