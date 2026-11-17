import Base
import ../laws/oci_auth.bend as L
import ../src/oci/auth.bend as A

# Proofs of laws/oci_auth.bend: `def L.<law>` for each law.

def L.oci_auth.challenge.single_scope():
  {==}

def L.oci_auth.challenge.multiple_scopes():
  {==}

def L.oci_auth.challenge.empty_param():
  {==}

def L.oci_auth.challenge.token_md():
  {==}

def L.oci_auth.challenge.scheme_case():
  {==}

def L.oci_auth.challenge.token_values():
  {==}

def L.oci_auth.challenge.quoted_escape():
  {==}

def L.oci_auth.challenge.stops_at_junk():
  {==}

def L.oci_auth.challenge.basic_not_bearer():
  {==}

def L.oci_auth.challenge.no_realm():
  {==}

def L.oci_auth.token_url.token_md():
  {==}

def L.oci_auth.token_url.scopes():
  {==}

def L.oci_auth.token_url.no_service():
  {==}

def L.oci_auth.token_url.escape():
  {==}

def L.oci_auth.token.token_md():
  {==}

def L.oci_auth.token.access_token():
  {==}

def L.oci_auth.token.access_token_wins():
  {==}

def L.oci_auth.token.default_lifetime():
  {==}

def L.oci_auth.token.min_lifetime():
  {==}

def L.oci_auth.token.skips_other_fields():
  {==}

def L.oci_auth.token.no_token():
  {==}

def L.oci_auth.token.empty_token():
  {==}

def L.oci_auth.token.not_json():
  {==}

def L.oci_auth.token.truncated():
  {==}

def L.oci_auth.token.expires_string():
  {==}

def L.oci_auth.realm.docker_hub():
  {==}

def L.oci_auth.realm.same_authority():
  {==}

def L.oci_auth.realm.loopback_other_authority():
  {==}

def L.oci_auth.realm.off_origin():
  {==}

def L.oci_auth.realm.no_host():
  {==}

def L.oci_auth.realm.pick_filters():
  {==}

def L.oci_auth.realm.pick_evil_first():
  {==}

def L.oci_auth.redirect.status_301():
  {==}

def L.oci_auth.redirect.status_302():
  {==}

def L.oci_auth.redirect.status_303():
  {==}

def L.oci_auth.redirect.status_304():
  {==}

def L.oci_auth.redirect.status_307():
  {==}

def L.oci_auth.redirect.status_308():
  {==}

def L.oci_auth.redirect.status_200():
  {==}

def L.oci_auth.redirect.to_storage():
  {==}

def L.oci_auth.redirect.hop_9():
  {==}

def L.oci_auth.redirect.hop_10():
  {==}

def L.oci_auth.redirect.http():
  {==}

def L.oci_auth.redirect.refuse_loopback():
  {==}

def L.oci_auth.redirect.refuse_metadata():
  {==}

def L.oci_auth.redirect.refuse_localhost():
  {==}

def L.oci_auth.redirect.refuse_ipv6_loopback():
  {==}

def L.oci_auth.redirect.refuse_private():
  {==}

def L.oci_auth.redirect.refuse_private_172():
  {==}

def L.oci_auth.redirect.refuse_private_192():
  {==}

def L.oci_auth.redirect.refuse_cgnat():
  {==}

def L.oci_auth.redirect.refuse_numeric():
  {==}

def L.oci_auth.redirect.refuse_hex():
  {==}

def L.oci_auth.redirect.refuse_single_label():
  {==}

def L.oci_auth.redirect.refuse_internal():
  {==}

def L.oci_auth.redirect.public_ip():
  {==}

def L.oci_auth.redirect.userinfo():
  {==}

def L.oci_auth.redirect.empty():
  {==}

def L.oci_auth.redirect.absolute_path():
  {==}

def L.oci_auth.redirect.default_port():
  {==}

def L.oci_auth.redirect.other_port():
  {==}

def L.oci_auth.redirect.network_path():
  {==}

def L.oci_auth.redirect.relative_path():
  {==}

def L.oci_auth.redirect.query_only():
  {==}

def L.oci_auth.addr.public():
  {==}

def L.oci_auth.addr.loopback():
  {==}

def L.oci_auth.addr.link_local():
  {==}

def L.oci_auth.addr.private():
  {==}

def L.oci_auth.addr.after_private():
  {==}

# A clash between True{} and False{} proves anything.

def Au.disc_t(b: Bool) -> Type:
  match b:
    case True{}:
      Empty
    case False{}:
      Unit

def Au.disc_f(b: Bool) -> Type:
  match b:
    case True{}:
      Unit
    case False{}:
      Empty

law Au.false_ne_true:
  for h: {False{} == True{} : Bool}
  Empty

def Au.false_ne_true(h):
  %h : Au.disc_t(_)
  Unit{}

law Au.true_ne_false:
  for h: {True{} == False{} : Bool}
  Empty

def Au.true_ne_false(h):
  %h : Au.disc_f(_)
  Unit{}

law Au.absurd_hop:
  for -a: A.Hop
  for -b: A.Hop
  for e: Empty
  {a == b : A.Hop}

def Au.absurd_hop(a, b, e):
  match e:

law Au.absurd_u32:
  for -a: U32
  for -b: U32
  for e: Empty
  {a == b : U32}

def Au.absurd_u32(a, b, e):
  match e:

# redirect.lim on a known answer, stated {simple == computed} so that %
# puts the simple form in place.
law Au.lim:
  for c: Bool
  for -from: String
  for -loc: String
  for h: {c == True{} : Bool}
  {A.Refuse{"stopped after 10 redirects"} == A.Auth.redirect.lim(c, from, loc) : A.Hop}

def Au.lim(c, from, loc, h):
  match c:
    case True{}:
      {==}
    case False{}:
      Au.absurd_hop(A.Refuse{"stopped after 10 redirects"}, A.Auth.redirect.lim(False{}, from, loc), Au.false_ne_true(h))

def L.oci_auth.redirect.hop_limit(hops, from, loc, h):
  %Au.lim(U32.is_ge(hops, 10), from, loc, h) : {_ == A.Refuse{"stopped after 10 redirects"} : A.Hop}
  {==}

law Au.short:
  for c: Bool
  for -e: U32
  for h: {c == True{} : Bool}
  {60 == A.Auth.lifetime.go(c, e) : U32}

def Au.short(c, e, h):
  match c:
    case True{}:
      {==}
    case False{}:
      Au.absurd_u32(60, A.Auth.lifetime.go(False{}, e), Au.false_ne_true(h))

law Au.long:
  for c: Bool
  for -e: U32
  for h: {c == False{} : Bool}
  {e == A.Auth.lifetime.go(c, e) : U32}

def Au.long(c, e, h):
  match c:
    case True{}:
      Au.absurd_u32(e, A.Auth.lifetime.go(True{}, e), Au.true_ne_false(h))
    case False{}:
      {==}

def L.oci_auth.lifetime.floor(e, h):
  %Au.short(U32.is_lt(e, 60), e, h) : {_ == 60 : U32}
  {==}

def L.oci_auth.lifetime.keep(e, h):
  %Au.long(U32.is_lt(e, 60), e, h) : {_ == e : U32}
  {==}
