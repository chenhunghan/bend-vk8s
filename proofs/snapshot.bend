import Base
import ../laws/snapshot.bend as L
import ../src/lib/sha256.bend as H
import ../src/standalone/snapshot.bend as S

# Proofs of laws/snapshot.bend: `def L.<law>` for each law.

def L.snapshot.parse.s3():
  {==}

def L.snapshot.parse.container():
  {==}

def L.snapshot.parse.oci():
  {==}

def L.snapshot.parse.azure():
  {==}

def L.snapshot.parse.s3_unexpected_option():
  {==}

def L.snapshot.parse.container_host():
  {==}

def L.snapshot.parse.container_opaque():
  {==}

def L.snapshot.parse.container_escape():
  {==}

def L.snapshot.parse.bad_escape():
  {==}

def L.snapshot.parse.query_and_fragment():
  {==}

def L.snapshot.parse.file_refused():
  {==}

def L.snapshot.parse.oci_userinfo():
  {==}

def L.snapshot.parse.oci_no_repo():
  {==}

def L.snapshot.parse.oci_bad_base64():
  {==}

def L.snapshot.parse.oci_bad_bool():
  {==}

def L.snapshot.parse.s3_no_key():
  {==}

def L.snapshot.parse.s3_no_bucket():
  {==}

def L.snapshot.parse.s3_first_value():
  {==}

def L.snapshot.parse.missing_scheme():
  {==}

def L.snapshot.parse.http_refused():
  {==}

def L.snapshot.parse.vk8s_file():
  {==}

def L.snapshot.parse.vk8s_container():
  {==}

def L.snapshot.get_url.container():
  {==}

def L.snapshot.get_url.s3():
  {==}

def L.snapshot.validate.container_empty():
  {==}

def L.snapshot.validate.s3_list():
  {==}

def L.snapshot.validate.s3_key():
  {==}

def L.snapshot.write.revision():
  {==}

def L.snapshot.write.revision_kind():
  {==}

def L.snapshot.write.release_request_kind():
  {==}

def L.snapshot.keys.release_prefix():
  {==}

def L.snapshot.keys.request_prefix():
  {==}

def L.snapshot.keys.db_prefix():
  {==}

def L.snapshot.keys.skipkeys_prefix():
  {==}

def L.snapshot.keys.revision_prefix():
  {==}

def L.snapshot.write.polluted():
  {==}

def L.snapshot.write.cancelled():
  {==}

def L.snapshot.write.revision_error():
  {==}

def L.snapshot.write.list_error():
  {==}

def L.snapshot.write.revision_tar_length():
  {==}

def L.snapshot.convert.basic():
  {==}

def L.snapshot.convert.skip_keys():
  {==}

def L.snapshot.convert.passthrough():
  {==}

def L.snapshot.convert.polluted():
  {==}

def L.snapshot.convert.non_prefixed():
  {==}

def L.snapshot.convert.empty():
  {==}

def L.snapshot.convert.already_kv():
  {==}

def L.snapshot.convert.missing_db():
  {==}

def L.snapshot.convert.missing_db_message():
  {==}

def L.snapshot.convert.bad_skip_keys():
  {==}

def L.snapshot.convert.duplicate_db():
  {==}

def L.snapshot.delete_calls.embedded_etcd():
  {==}

def L.snapshot.delete_calls.embedded_database():
  {==}

def L.snapshot.delete_calls.deployed_etcd():
  {==}

def L.snapshot.delete_calls.external_etcd():
  {==}

def L.snapshot.delete_calls.external_database():
  {==}

def L.snapshot.delete_method.embedded_etcd():
  {==}

def L.snapshot.delete_method.embedded_database():
  {==}

def L.snapshot.delete_method.deployed_etcd():
  {==}

def L.snapshot.delete_method.external_etcd():
  {==}

def L.snapshot.delete_method.external_database():
  {==}

def L.snapshot.convert_needed.etcd.embedded_etcd():
  {==}

def L.snapshot.convert_needed.etcd.embedded_database():
  {==}

def L.snapshot.convert_needed.etcd.deployed_etcd():
  {==}

def L.snapshot.convert_needed.etcd.external_etcd():
  {==}

def L.snapshot.convert_needed.etcd.external_database():
  {==}

def L.snapshot.convert_needed.kv.embedded_etcd():
  {==}

def L.snapshot.convert_needed.kv.embedded_database():
  {==}

def L.snapshot.convert_needed.kv.deployed_etcd():
  {==}

def L.snapshot.convert_needed.kv.external_etcd():
  {==}

def L.snapshot.convert_needed.kv.external_database():
  {==}

def L.snapshot.bump.latest_greater():
  {==}

def L.snapshot.bump.snapshot_greater():
  {==}

def L.snapshot.bump.equal():
  {==}

def L.snapshot.bump.zeros():
  {==}

def L.snapshot.bump.snapshot_zero():
  {==}

def L.snapshot.kind.db_first():
  {==}

def L.snapshot.kind.release_db():
  {==}

def L.snapshot.kind.release_request_db():
  {==}

def L.snapshot.kind.request_db():
  {==}

def L.snapshot.kind.registry_first():
  {==}

def L.snapshot.kind.release_registry():
  {==}

def L.snapshot.kind.request_first():
  {==}

def L.snapshot.kind.release_request():
  {==}

def L.snapshot.kind.release_request_registry():
  {==}

def L.snapshot.kind.exact_request_key():
  {==}

def L.snapshot.kind.empty():
  {==}

def L.snapshot.kind.only_release():
  {==}

def L.snapshot.kind.not_tar():
  {==}

def L.snapshot.kind.empty_tar():
  {==}

def L.snapshot.tar.one():
  {==}

def L.snapshot.tar.split():
  {==}

def L.snapshot.tar.trailing_slash():
  {==}

def L.snapshot.tar.nul():
  {==}

def L.snapshot.tar.empty():
  {==}

def L.snapshot.tar.decode_one():
  {==}

def L.snapshot.tar.decode_not_tar():
  {==}

def L.snapshot.tar.decode_one_zero_block():
  {==}

def L.snapshot.tar.decode_zero_then_data():
  {==}

def L.snapshot.tar.decode_nothing():
  {==}

def L.snapshot.tar.decode_truncated_data():
  {==}

def L.snapshot.tar.decode_no_trailer():
  {==}

def L.snapshot.tar.decode_bad_checksum():
  {==}

def L.snapshot.etcd.kind(db, skip):
  {==}

# Discriminators
# --------------

def snap.rdisc(r: Result<&2, &2, String, List<&2, S.Snap.Rec>>) -> Type:
  match r:
    case Fail{m}:
      Unit
    case Done{x}:
      Empty

def snap.fail_done(-A: Type, -m: String, -x: List<&2, S.Snap.Rec>, e: {Fail{m} == Done{x} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}) -> A:
  Empty.absurd(A, (%e : snap.rdisc(_); Unit{}))

def snap.done_val(r: Result<&2, &2, String, List<&2, S.Snap.Rec>>) -> List<&2, S.Snap.Rec>:
  match r:
    case Fail{m}:
      Nil{}
    case Done{x}:
      x

law snap.done_inj:
  for -a: List<&2, S.Snap.Rec>
  for -b: List<&2, S.Snap.Rec>
  for e: {Done{a} == Done{b} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
  {a == b : List<&2, S.Snap.Rec>}

def snap.done_inj(a, b, e):
  Equal.cong(Result<&2, &2, String, List<&2, S.Snap.Rec>>, List<&2, S.Snap.Rec>, snap.done_val, Done{a}, Done{b}, e)

# The key/value archive's kind
# ----------------------------

law snap.kv_kind.go:
  for x: Result<&2, &2, String, List<&2, S.Snap.Rec>>
  for -rev: Nat
  for -rs: List<&2, S.Snap.Rec>
  for h: {S.Snap.Tar.emit.rec(S.Rec{S.Snap.revision_key(), S.Snap.b(Nat.show(rev))}, x) == Done{rs} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
  {S.Snap.kind(rs) == S.KKeyValue{} : S.Snap.Kind}

def snap.kv_kind.go(x, rev, rs, h):
  match x:
    case Fail{m}:
      snap.fail_done({S.Snap.kind(rs) == S.KKeyValue{} : S.Snap.Kind}, m, rs, h)
    case Done{xs}:
      %snap.done_inj(S.Rec{S.Snap.revision_key(), S.Snap.b(Nat.show(rev))} <> xs, rs, h) : {S.Snap.kind(_) == S.KKeyValue{} : S.Snap.Kind}
      {==}

def L.snapshot.write.kv_kind(rev, items, skip, rs, h):
  snap.kv_kind.go(S.Snap.write.items(items, skip), rev, rs, h)

# A restore never puts a metadata key
# -----------------------------------

law snap.clean.put:
  for +b: Bool
  for +x: Bool
  for +k: List<&2, U32>
  for +v: List<&2, U32>
  for +pod: Bool
  for +rest: List<&2, S.Snap.Put>
  for e: {S.Snap.bprefix(k, S.Snap.meta_prefix()) == b : Bool}
  for ih: {S.Snap.plan_clean.go(rest) == True{} : Bool}
  {S.Snap.plan_clean.go(S.Snap.plan.put(Bool.or(b, x), k, v, pod, rest)) == True{} : Bool}

def snap.clean.put(b, x, k, v, pod, rest, e, ih):
  match b:
    case True{}:
      ih
    case False{}:
      match x:
        case True{}:
          ih
        case False{}:
          %Equal.sym(Bool, S.Snap.bprefix(k, S.Snap.meta_prefix()), False{}, e) : {Bool.and(Bool.not(_), S.Snap.plan_clean.go(rest)) == True{} : Bool}
          %Equal.sym(Bool, S.Snap.plan_clean.go(rest), True{}, ih) : {Bool.and(True{}, _) == True{} : Bool}
          {==}

law snap.clean.key:
  for empty: Bool
  for +k: List<&2, U32>
  for +v: List<&2, U32>
  for +nv: Bool
  for +pn: Bool
  for +rest: List<&2, S.Snap.Put>
  for ih: {S.Snap.plan_clean.go(rest) == True{} : Bool}
  {S.Snap.plan_clean.go(S.Snap.plan.key(empty, k, v, nv, pn, rest)) == True{} : Bool}

def snap.clean.key(empty, k, v, nv, pn, rest, ih):
  match empty:
    case True{}:
      {==}
    case False{}:
      snap.clean.put(S.Snap.bprefix(k, S.Snap.meta_prefix()),
        Bool.and(nv, Bool.or(S.Snap.bprefix(k, S.Snap.mappings_prefix()), S.Snap.root_ca(k))),
        k, v, Bool.and(S.Snap.bprefix(k, S.Snap.pod_prefix()), Bool.not(pn)), rest, {==}, ih)

law snap.clean:
  for rs: List<&2, S.Snap.Rec>
  for +nv: Bool
  for +pn: Bool
  {S.Snap.plan_clean.go(S.Snap.plan.go(rs, nv, pn)) == True{} : Bool}

def snap.clean(rs, nv, pn):
  match rs:
    case Nil{}:
      {==}
    case Con{S.Rec{+k, +v}, +t}:
      snap.clean.key(List.is_empty(&2, U32, k), k, v, nv, pn, S.Snap.plan.go(t, nv, pn), snap.clean(t, nv, pn))

def L.snapshot.restore.no_metadata(rs, nv, pn):
  snap.clean(rs, nv, pn)

# Bool facts
# ----------

def snap.bdisc(b: Bool) -> Type:
  match b:
    case False{}:
      Unit
    case True{}:
      Empty

# False is not True.
def snap.ft(-A: Type, e: {False{} == True{} : Bool}) -> A:
  Empty.absurd(A, (%e : snap.bdisc(_); Unit{}))

law snap.and_l:
  for a: Bool
  for -b: Bool
  for +h: {Bool.and(a, b) == True{} : Bool}
  {a == True{} : Bool}

def snap.and_l(a, b, h):
  match a:
    case False{}:
      snap.ft({False{} == True{} : Bool}, h)
    case True{}:
      {==}

law snap.and_r:
  for a: Bool
  for -b: Bool
  for +h: {Bool.and(a, b) == True{} : Bool}
  {b == True{} : Bool}

def snap.and_r(a, b, h):
  match a:
    case False{}:
      snap.ft({b == True{} : Bool}, h)
    case True{}:
      h

law snap.not_true:
  for a: Bool
  for +h: {Bool.not(a) == True{} : Bool}
  {False{} == a : Bool}

def snap.not_true(a, h):
  match a:
    case False{}:
      {==}
    case True{}:
      snap.ft({False{} == True{} : Bool}, h)

# The facts of a plain byte, as rewrites (False == test).
law snap.pb.pct:
  for +c: U32
  for +h: {S.Snap.Url.plain_byte(c) == True{} : Bool}
  {False{} == U32.is_eq(c, 37) : Bool}

def snap.pb.pct(c, h):
  snap.not_true(U32.is_eq(c, 37), snap.and_l(Bool.not(U32.is_eq(c, 37)), Bool.and(Bool.not(U32.is_eq(c, 63)),
    Bool.and(Bool.not(U32.is_eq(c, 35)), Bool.not(S.Snap.Url.ctl(c)))), h))

law snap.pb.rest1:
  for +c: U32
  for +h: {S.Snap.Url.plain_byte(c) == True{} : Bool}
  {Bool.and(Bool.not(U32.is_eq(c, 63)), Bool.and(Bool.not(U32.is_eq(c, 35)), Bool.not(S.Snap.Url.ctl(c)))) == True{} : Bool}

def snap.pb.rest1(c, h):
  snap.and_r(Bool.not(U32.is_eq(c, 37)), Bool.and(Bool.not(U32.is_eq(c, 63)),
    Bool.and(Bool.not(U32.is_eq(c, 35)), Bool.not(S.Snap.Url.ctl(c)))), h)

law snap.pb.q:
  for +c: U32
  for +h: {S.Snap.Url.plain_byte(c) == True{} : Bool}
  {False{} == U32.is_eq(c, 63) : Bool}

def snap.pb.q(c, h):
  snap.not_true(U32.is_eq(c, 63), snap.and_l(Bool.not(U32.is_eq(c, 63)),
    Bool.and(Bool.not(U32.is_eq(c, 35)), Bool.not(S.Snap.Url.ctl(c))), snap.pb.rest1(c, h)))

law snap.pb.rest2:
  for +c: U32
  for +h: {S.Snap.Url.plain_byte(c) == True{} : Bool}
  {Bool.and(Bool.not(U32.is_eq(c, 35)), Bool.not(S.Snap.Url.ctl(c))) == True{} : Bool}

def snap.pb.rest2(c, h):
  snap.and_r(Bool.not(U32.is_eq(c, 63)), Bool.and(Bool.not(U32.is_eq(c, 35)), Bool.not(S.Snap.Url.ctl(c))), snap.pb.rest1(c, h))

law snap.pb.hash:
  for +c: U32
  for +h: {S.Snap.Url.plain_byte(c) == True{} : Bool}
  {False{} == U32.is_eq(c, 35) : Bool}

def snap.pb.hash(c, h):
  snap.not_true(U32.is_eq(c, 35), snap.and_l(Bool.not(U32.is_eq(c, 35)), Bool.not(S.Snap.Url.ctl(c)), snap.pb.rest2(c, h)))

law snap.pb.ctl:
  for +c: U32
  for +h: {S.Snap.Url.plain_byte(c) == True{} : Bool}
  {False{} == S.Snap.Url.ctl(c) : Bool}

def snap.pb.ctl(c, h):
  snap.not_true(S.Snap.Url.ctl(c), snap.and_r(Bool.not(U32.is_eq(c, 35)), Bool.not(S.Snap.Url.ctl(c)), snap.pb.rest2(c, h)))

law snap.pbs.head:
  for +c: U32
  for +t: List<&2, U32>
  for +h: {S.Snap.Url.plain_bytes(Con{c, t}) == True{} : Bool}
  {S.Snap.Url.plain_byte(c) == True{} : Bool}

def snap.pbs.head(c, t, h):
  snap.and_l(S.Snap.Url.plain_byte(c), S.Snap.Url.plain_bytes(t), h)

law snap.pbs.tail:
  for +c: U32
  for +t: List<&2, U32>
  for +h: {S.Snap.Url.plain_bytes(Con{c, t}) == True{} : Bool}
  {S.Snap.Url.plain_bytes(t) == True{} : Bool}

def snap.pbs.tail(c, t, h):
  snap.and_r(S.Snap.Url.plain_byte(c), S.Snap.Url.plain_bytes(t), h)

# Plain bytes hold no '#' or '?' to cut at.
law snap.cut_hash:
  for +xs: List<&2, U32>
  for +h: {S.Snap.Url.plain_bytes(xs) == True{} : Bool}
  {S.Snap.Tar.cut(xs, 35) == None{} : Maybe<&2, S.Snap.BB>}

def snap.cut_hash(xs, h):
  match xs:
    case Nil{}:
      {==}
    case Con{+c, +t}:
      %snap.pb.hash(c, snap.pbs.head(c, t, h)) : {S.Snap.Tar.cut.pick(_, c, t, S.Snap.Tar.cut(t, 35)) == None{} : Maybe<&2, S.Snap.BB>}
      %Equal.sym(Maybe<&2, S.Snap.BB>, S.Snap.Tar.cut(t, 35), None{}, snap.cut_hash(t, snap.pbs.tail(c, t, h))) : {S.Snap.Tar.cut.pick(False{}, c, t, _) == None{} : Maybe<&2, S.Snap.BB>}
      {==}

law snap.cut_q:
  for +xs: List<&2, U32>
  for +h: {S.Snap.Url.plain_bytes(xs) == True{} : Bool}
  {S.Snap.Tar.cut(xs, 63) == None{} : Maybe<&2, S.Snap.BB>}

def snap.cut_q(xs, h):
  match xs:
    case Nil{}:
      {==}
    case Con{+c, +t}:
      %snap.pb.q(c, snap.pbs.head(c, t, h)) : {S.Snap.Tar.cut.pick(_, c, t, S.Snap.Tar.cut(t, 63)) == None{} : Maybe<&2, S.Snap.BB>}
      %Equal.sym(Maybe<&2, S.Snap.BB>, S.Snap.Tar.cut(t, 63), None{}, snap.cut_q(t, snap.pbs.tail(c, t, h))) : {S.Snap.Tar.cut.pick(False{}, c, t, _) == None{} : Maybe<&2, S.Snap.BB>}
      {==}

# Plain bytes hold no control byte.
law snap.no_ctl:
  for +xs: List<&2, U32>
  for +h: {S.Snap.Url.plain_bytes(xs) == True{} : Bool}
  {S.Snap.Url.has_ctl(xs) == False{} : Bool}

def snap.no_ctl(xs, h):
  match xs:
    case Nil{}:
      {==}
    case Con{+c, +t}:
      %snap.pb.ctl(c, snap.pbs.head(c, t, h)) : {Bool.or(_, S.Snap.Url.has_ctl(t)) == False{} : Bool}
      snap.no_ctl(t, snap.pbs.tail(c, t, h))

# Plain bytes after a byte that is no '?' do not end in '?'.
law snap.no_q_end:
  for +xs: List<&2, U32>
  for +c: U32
  for +hc: {False{} == U32.is_eq(c, 63) : Bool}
  for +h: {S.Snap.Url.plain_bytes(xs) == True{} : Bool}
  {S.Snap.ends_with1.go(xs, c, 63) == False{} : Bool}

def snap.no_q_end(xs, c, hc, h):
  match xs:
    case Nil{}:
      %hc : {_ == False{} : Bool}
      {==}
    case Con{+d, +t}:
      snap.no_q_end(t, d, snap.pb.q(d, snap.pbs.head(d, t, h)), snap.pbs.tail(d, t, h))

# Plain bytes unescape in path mode to themselves.
law snap.unescape_plain:
  for +xs: List<&2, U32>
  for +acc: List<&2, U32>
  for +h: {S.Snap.Url.plain_bytes(xs) == True{} : Bool}
  {S.Snap.Url.u.go(xs, S.U0{acc}, S.MPath{}) == Done{List.reverse.go(&2, U32, acc, xs)} : Result<&2, &2, String, List<&2, U32>>}

def snap.unescape_plain(xs, acc, h):
  match xs:
    case Nil{}:
      {==}
    case Con{+c, +t}:
      %snap.pb.pct(c, snap.pbs.head(c, t, h)) : {S.Snap.Url.u.go(t, S.Snap.Url.u.plain(_, False{}, False{}, c, acc), S.MPath{}) == Done{List.reverse.go(&2, U32, acc, Con{c, t})} : Result<&2, &2, String, List<&2, U32>>}
      snap.unescape_plain(t, c <> acc, snap.pbs.tail(c, t, h))

# The authority and path of "//" ++ p: no host, the path p.
law snap.url.auth:
  for +s: List<&2, U32>
  for +c: U32
  for +t: List<&2, U32>
  for +hc: {U32.is_eq(c, 47) == True{} : Bool}
  for +hp: {S.Snap.Url.plain_bytes(Con{c, t}) == True{} : Bool}
  {S.Snap.Url.auth_split(s, Nil{}, Con{47, Con{47, Con{c, t}}}) == Done{S.Url{s, Nil{}, None{}, Nil{}, Con{c, t}, Nil{}}} : Result<&2, &2, String, S.Snap.Url>}

def snap.url.auth(s, c, t, hc, hp):
  %Equal.sym(Bool, U32.is_eq(c, 47), True{}, hc) : {S.Snap.Url.path(s, Nil{}, S.Snap.Url.authority(s, S.Snap.take(Con{c, t}, Maybe.default(&2, Nat, S.Snap.index.pick(_, 0n, S.Snap.index(t, 47, 1n)), List.length(&2, U32, Con{c, t})))), S.Snap.drop(Con{c, t}, Maybe.default(&2, Nat, S.Snap.index.pick(_, 0n, S.Snap.index(t, 47, 1n)), List.length(&2, U32, Con{c, t})))) == Done{S.Url{s, Nil{}, None{}, Nil{}, Con{c, t}, Nil{}}} : Result<&2, &2, String, S.Snap.Url>}
  %Equal.sym(Result<&2, &2, String, List<&2, U32>>, S.Snap.Url.u.go(Con{c, t}, S.U0{Nil{}}, S.MPath{}), Done{Con{c, t}}, snap.unescape_plain(Con{c, t}, Nil{}, hp)) : {S.Snap.Url.path.fin(_, s, None{}, Nil{}, Nil{}) == Done{S.Url{s, Nil{}, None{}, Nil{}, Con{c, t}, Nil{}}} : Result<&2, &2, String, S.Snap.Url>}
  {==}

# The rest of a URL after a non-empty scheme: "//" ++ p.
law snap.url.rest:
  for +x: U32
  for +xs: List<&2, U32>
  for +c: U32
  for +t: List<&2, U32>
  for +hc: {U32.is_eq(c, 47) == True{} : Bool}
  for +hp: {S.Snap.Url.plain_bytes(Con{c, t}) == True{} : Bool}
  {S.Snap.Url.rest(Con{x, xs}, Con{47, Con{47, Con{c, t}}}) == Done{S.Url{S.Snap.Url.lowers(Con{x, xs}), Nil{}, None{}, Nil{}, Con{c, t}, Nil{}}} : Result<&2, &2, String, S.Snap.Url>}

def snap.url.rest(x, xs, c, t, hc, hp):
  %Equal.sym(Bool, S.Snap.ends_with1.go(Con{47, Con{c, t}}, 47, 63), False{}, snap.no_q_end(Con{47, Con{c, t}}, 47, {==}, hp)) : {S.Snap.Url.query.if(Bool.and(_, Nat.is_eq(S.Snap.count(Con{47, Con{47, Con{c, t}}}, 63), 1n)), S.Snap.Url.lowers(Con{x, xs}), Con{47, Con{47, Con{c, t}}}) == Done{S.Url{S.Snap.Url.lowers(Con{x, xs}), Nil{}, None{}, Nil{}, Con{c, t}, Nil{}}} : Result<&2, &2, String, S.Snap.Url>}
  %Equal.sym(Maybe<&2, S.Snap.BB>, S.Snap.Tar.cut(Con{47, Con{47, Con{c, t}}}, 63), None{}, snap.cut_q(Con{47, Con{47, Con{c, t}}}, hp)) : {S.Snap.Url.query.cut(S.Snap.cut_or_all(_, Con{47, Con{47, Con{c, t}}}), S.Snap.Url.lowers(Con{x, xs})) == Done{S.Url{S.Snap.Url.lowers(Con{x, xs}), Nil{}, None{}, Nil{}, Con{c, t}, Nil{}}} : Result<&2, &2, String, S.Snap.Url>}
  snap.url.auth(S.Snap.Url.lowers(Con{x, xs}), c, t, hc, hp)

law snap.url.parse_container:
  for +c: U32
  for +t: List<&2, U32>
  for +hc: {U32.is_eq(c, 47) == True{} : Bool}
  for +hp: {S.Snap.Url.plain_bytes(Con{c, t}) == True{} : Bool}
  {S.Snap.Url.parse(S.Snap.app(S.Snap.b("container://"), Con{c, t})) == Done{S.Url{S.Snap.b("container"), Nil{}, None{}, Nil{}, Con{c, t}, Nil{}}} : Result<&2, &2, String, S.Snap.Url>}

def snap.url.parse_container(c, t, hc, hp):
  %Equal.sym(Maybe<&2, S.Snap.BB>, S.Snap.Tar.cut(S.Snap.app(S.Snap.b("container://"), Con{c, t}), 35), None{}, snap.cut_hash(S.Snap.app(S.Snap.b("container://"), Con{c, t}), hp)) : {S.Snap.Url.parse.cut(S.Snap.cut_or_all(_, S.Snap.app(S.Snap.b("container://"), Con{c, t})), S.Snap.app(S.Snap.b("container://"), Con{c, t})) == Done{S.Url{S.Snap.b("container"), Nil{}, None{}, Nil{}, Con{c, t}, Nil{}}} : Result<&2, &2, String, S.Snap.Url>}
  %Equal.sym(Bool, S.Snap.Url.has_ctl(S.Snap.app(S.Snap.b("container://"), Con{c, t})), False{}, snap.no_ctl(S.Snap.app(S.Snap.b("container://"), Con{c, t}), hp)) : {S.Snap.Url.frag(S.Snap.app(S.Snap.b("container://"), Con{c, t}), Nil{}, S.Snap.Url.wrap(S.Snap.app(S.Snap.b("container://"), Con{c, t}), S.Snap.Url.parse.ctl(_, S.Snap.beq(S.Snap.app(S.Snap.b("container://"), Con{c, t}), [42]), S.Snap.app(S.Snap.b("container://"), Con{c, t})))) == Done{S.Url{S.Snap.b("container"), Nil{}, None{}, Nil{}, Con{c, t}, Nil{}}} : Result<&2, &2, String, S.Snap.Url>}
  %Equal.sym(Result<&2, &2, String, S.Snap.Url>, S.Snap.Url.rest(S.Snap.b("container"), Con{47, Con{47, Con{c, t}}}), Done{S.Url{S.Snap.b("container"), Nil{}, None{}, Nil{}, Con{c, t}, Nil{}}}, snap.url.rest(99, S.Snap.b("ontainer"), c, t, hc, hp)) : {S.Snap.Url.frag(S.Snap.app(S.Snap.b("container://"), Con{c, t}), Nil{}, S.Snap.Url.wrap(S.Snap.app(S.Snap.b("container://"), Con{c, t}), _)) == Done{S.Url{S.Snap.b("container"), Nil{}, None{}, Nil{}, Con{c, t}, Nil{}}} : Result<&2, &2, String, S.Snap.Url>}
  {==}

law snap.url.parse_file:
  for +c: U32
  for +t: List<&2, U32>
  for +hc: {U32.is_eq(c, 47) == True{} : Bool}
  for +hp: {S.Snap.Url.plain_bytes(Con{c, t}) == True{} : Bool}
  {S.Snap.Url.parse(S.Snap.app(S.Snap.b("file://"), Con{c, t})) == Done{S.Url{S.Snap.b("file"), Nil{}, None{}, Nil{}, Con{c, t}, Nil{}}} : Result<&2, &2, String, S.Snap.Url>}

def snap.url.parse_file(c, t, hc, hp):
  %Equal.sym(Maybe<&2, S.Snap.BB>, S.Snap.Tar.cut(S.Snap.app(S.Snap.b("file://"), Con{c, t}), 35), None{}, snap.cut_hash(S.Snap.app(S.Snap.b("file://"), Con{c, t}), hp)) : {S.Snap.Url.parse.cut(S.Snap.cut_or_all(_, S.Snap.app(S.Snap.b("file://"), Con{c, t})), S.Snap.app(S.Snap.b("file://"), Con{c, t})) == Done{S.Url{S.Snap.b("file"), Nil{}, None{}, Nil{}, Con{c, t}, Nil{}}} : Result<&2, &2, String, S.Snap.Url>}
  %Equal.sym(Bool, S.Snap.Url.has_ctl(S.Snap.app(S.Snap.b("file://"), Con{c, t})), False{}, snap.no_ctl(S.Snap.app(S.Snap.b("file://"), Con{c, t}), hp)) : {S.Snap.Url.frag(S.Snap.app(S.Snap.b("file://"), Con{c, t}), Nil{}, S.Snap.Url.wrap(S.Snap.app(S.Snap.b("file://"), Con{c, t}), S.Snap.Url.parse.ctl(_, S.Snap.beq(S.Snap.app(S.Snap.b("file://"), Con{c, t}), [42]), S.Snap.app(S.Snap.b("file://"), Con{c, t})))) == Done{S.Url{S.Snap.b("file"), Nil{}, None{}, Nil{}, Con{c, t}, Nil{}}} : Result<&2, &2, String, S.Snap.Url>}
  %Equal.sym(Result<&2, &2, String, S.Snap.Url>, S.Snap.Url.rest(S.Snap.b("file"), Con{47, Con{47, Con{c, t}}}), Done{S.Url{S.Snap.b("file"), Nil{}, None{}, Nil{}, Con{c, t}, Nil{}}}, snap.url.rest(102, S.Snap.b("ile"), c, t, hc, hp)) : {S.Snap.Url.frag(S.Snap.app(S.Snap.b("file://"), Con{c, t}), Nil{}, S.Snap.Url.wrap(S.Snap.app(S.Snap.b("file://"), Con{c, t}), _)) == Done{S.Url{S.Snap.b("file"), Nil{}, None{}, Nil{}, Con{c, t}, Nil{}}} : Result<&2, &2, String, S.Snap.Url>}
  {==}

law snap.url.parse_container.h:
  for +c: U32
  for +t: List<&2, U32>
  for +h: {S.Snap.Url.plain_path(Con{c, t}) == True{} : Bool}
  {S.Snap.Url.parse(S.Snap.app(S.Snap.b("container://"), Con{c, t})) == Done{S.Url{S.Snap.b("container"), Nil{}, None{}, Nil{}, Con{c, t}, Nil{}}} : Result<&2, &2, String, S.Snap.Url>}

def snap.url.parse_container.h(c, t, h):
  snap.url.parse_container(c, t, snap.and_l(U32.is_eq(c, 47), S.Snap.Url.plain_bytes(Con{c, t}), h), snap.and_r(U32.is_eq(c, 47), S.Snap.Url.plain_bytes(Con{c, t}), h))

law snap.url.parse_file.h:
  for +c: U32
  for +t: List<&2, U32>
  for +h: {S.Snap.Url.plain_path(Con{c, t}) == True{} : Bool}
  {S.Snap.Url.parse(S.Snap.app(S.Snap.b("file://"), Con{c, t})) == Done{S.Url{S.Snap.b("file"), Nil{}, None{}, Nil{}, Con{c, t}, Nil{}}} : Result<&2, &2, String, S.Snap.Url>}

def snap.url.parse_file.h(c, t, h):
  snap.url.parse_file(c, t, snap.and_l(U32.is_eq(c, 47), S.Snap.Url.plain_bytes(Con{c, t}), h), snap.and_r(U32.is_eq(c, 47), S.Snap.Url.plain_bytes(Con{c, t}), h))

def L.snapshot.url.container_roundtrip(p, h):
  match p:
    case Nil{}:
      snap.ft({S.Snap.parse(S.Snap.get_url(S.LContainer{Nil{}})) == Done{S.LContainer{Nil{}}} : Result<&2, &2, String, S.Snap.Loc>}, h)
    case Con{+c, +t}:
      %Equal.sym(Result<&2, &2, String, S.Snap.Url>, S.Snap.Url.parse(S.Snap.app(S.Snap.b("container://"), Con{c, t})), Done{S.Url{S.Snap.b("container"), Nil{}, None{}, Nil{}, Con{c, t}, Nil{}}}, snap.url.parse_container.h(c, t, h)) : {S.Snap.parse.url(_, S.Snap.app(S.Snap.b("container://"), Con{c, t})) == Done{S.LContainer{Con{c, t}}} : Result<&2, &2, String, S.Snap.Loc>}
      {==}

def L.snapshot.url.file_roundtrip(p, h):
  match p:
    case Nil{}:
      snap.ft({S.Snap.parse(S.Snap.get_url(S.LFile{Nil{}})) == Done{S.LFile{Nil{}}} : Result<&2, &2, String, S.Snap.Loc>}, h)
    case Con{+c, +t}:
      %Equal.sym(Result<&2, &2, String, S.Snap.Url>, S.Snap.Url.parse(S.Snap.app(S.Snap.b("file://"), Con{c, t})), Done{S.Url{S.Snap.b("file"), Nil{}, None{}, Nil{}, Con{c, t}, Nil{}}}, snap.url.parse_file.h(c, t, h)) : {S.Snap.parse.vk8s.url(_, S.Snap.app(S.Snap.b("file://"), Con{c, t})) == Done{S.LFile{Con{c, t}}} : Result<&2, &2, String, S.Snap.Loc>}
      {==}

def L.snapshot.tar.size_fits_11_digits():
  {==}

def L.snapshot.tar.size_fits_12_digits():
  {==}

def L.snapshot.tar.pax_record_too_long():
  {==}

def L.snapshot.tar.pax_header_too_long():
  {==}

# snapshot.tar.roundtrip
# ======================
#
# Snap.Tar.decode reads back every archive Snap.Tar.encode writes. The
# proof is an induction over the records (rt.enc): an encoded archive is
# the entries of the records, then the trailer. For one entry (rt.ent),
# the case analysis follows Snap.Tar.name: a USTAR header with the name
# (rt.ent_short), a USTAR header with a prefix (rt.ent_nsplit), or a PAX
# extended header with the path record before the file header
# (rt.ent_pax_main). Each header is 512 bytes (rt.len_file, rt.len_pax);
# the decoder collects them byte by byte (rt.hread) and parses them
# (rt.hdr_file, rt.hdr_pax): the checksum field is the one it computes
# (rt.cks_ok), the size field holds the value's octal length
# (rt.num_size, rt.val_count), and the name and prefix fields cut at
# their first NUL give the name back (rt.cnf, rt.split_name). The data
# is read byte by byte (rt.dread), then the padding up to the next block
# (rt.pad_k). The PAX record "<n> path=<key>\n" parses back to the key
# (rt.px_full): its decimal length is n (rt.pin) and n is the record's
# length (rt.px_len). The trailer is two zero blocks (rt.trailer).
#
# Rewrite lemmas are stated {simple == computed}: `%e : P` turns the
# right side of e into its left side. rt.F(n, s) spells a field of n
# bytes as n explicit cells, so the checker can slice a header without
# knowing the name.

# Contradictions
# --------------

def rt.bdisc(b: Bool) -> Type:
  match b:
    case False{}:
      Unit
    case True{}:
      Empty

def rt.ft(-A: Type, e: {False{} == True{} : Bool}) -> A:
  Empty.absurd(A, (%e : rt.bdisc(_); Unit{}))

def rt.tf(-A: Type, e: {True{} == False{} : Bool}) -> A:
  rt.ft(A, Equal.sym(Bool, True{}, False{}, e))

def rt.rdisc(r: Result<&2, &2, String, List<&2, U32>>) -> Type:
  match r:
    case Fail{m}:
      Unit
    case Done{x}:
      Empty

def rt.fd(-A: Type, -m: String, -x: List<&2, U32>, e: {Fail{m} == Done{x} : Result<&2, &2, String, List<&2, U32>>}) -> A:
  Empty.absurd(A, (%e : rt.rdisc(_); Unit{}))

def rt.undone(r: Result<&2, &2, String, List<&2, U32>>) -> List<&2, U32>:
  match r:
    case Fail{m}:
      Nil{}
    case Done{x}:
      x

law rt.done_inj:
  for -a: List<&2, U32>
  for -b: List<&2, U32>
  for +e: {Done{a} == Done{b} : Result<&2, &2, String, List<&2, U32>>}
  {a == b : List<&2, U32>}

def rt.done_inj(a, b, e):
  Equal.cong(Result<&2, &2, String, List<&2, U32>>, List<&2, U32>, rt.undone, Done{a}, Done{b}, e)

def rt.mdisc(m: Maybe<&2, List<&2, U32>>) -> Type:
  match m:
    case None{}:
      Unit
    case Some{x}:
      Empty

def rt.ns(-A: Type, -x: List<&2, U32>, e: {None{} == Some{x} : Maybe<&2, List<&2, U32>>}) -> A:
  Empty.absurd(A, (%e : rt.mdisc(_); Unit{}))

def rt.unsome(m: Maybe<&2, List<&2, U32>>) -> List<&2, U32>:
  match m:
    case None{}:
      Nil{}
    case Some{x}:
      x

law rt.some_inj:
  for -a: List<&2, U32>
  for -b: List<&2, U32>
  for +e: {Some{a} == Some{b} : Maybe<&2, List<&2, U32>>}
  {a == b : List<&2, U32>}

def rt.some_inj(a, b, e):
  Equal.cong(Maybe<&2, List<&2, U32>>, List<&2, U32>, rt.unsome, Some{a}, Some{b}, e)

# Bool
# ----

law rt.and_l:
  for +a: Bool
  for -b: Bool
  for +h: {Bool.and(a, b) == True{} : Bool}
  {a == True{} : Bool}

def rt.and_l(a, b, h):
  match a:
    case False{}:
      rt.ft({False{} == True{} : Bool}, h)
    case True{}:
      {==}

law rt.and_r:
  for +a: Bool
  for -b: Bool
  for +h: {Bool.and(a, b) == True{} : Bool}
  {b == True{} : Bool}

def rt.and_r(a, b, h):
  match a:
    case False{}:
      rt.ft({b == True{} : Bool}, h)
    case True{}:
      h

law rt.or_l:
  for +a: Bool
  for -b: Bool
  for +h: {Bool.or(a, b) == False{} : Bool}
  {a == False{} : Bool}

def rt.or_l(a, b, h):
  match a:
    case False{}:
      {==}
    case True{}:
      rt.tf({True{} == False{} : Bool}, h)

law rt.or_r:
  for +a: Bool
  for -b: Bool
  for +h: {Bool.or(a, b) == False{} : Bool}
  {b == False{} : Bool}

def rt.or_r(a, b, h):
  match a:
    case False{}:
      h
    case True{}:
      rt.tf({b == False{} : Bool}, h)

law rt.and_false:
  for +a: Bool
  {False{} == Bool.and(a, False{}) : Bool}

def rt.and_false(a):
  match a:
    case False{}:
      {==}
    case True{}:
      {==}

# U32 equality
# ------------

law rt.wcmp_refl:
  for +n: Nat
  for +w: Word(n)
  {EQ{} == Word.cmp(n, w, w) : Cmp}

def rt.wcmp_refl(n, w):
  match n:
    case 0n:
      {==}
    case 1n+p:
      match w:
        case WCon{b, t}:
          match b:
            case False{}:
              %rt.wcmp_refl(p, t) : {EQ{} == Word.cmp.fin(False{}, False{}, _) : Cmp}
              {==}
            case True{}:
              %rt.wcmp_refl(p, t) : {EQ{} == Word.cmp.fin(True{}, True{}, _) : Cmp}
              {==}

law rt.u32_refl:
  for +x: U32
  {True{} == U32.is_eq(x, x) : Bool}

def rt.u32_refl(x):
  match x:
    case U32{w}:
      %rt.wcmp_refl(32n, w) : {True{} == Cmp.is_eq(_) : Bool}
      {==}

law rt.fin_c:
  for -a: Bool
  for -b: Bool
  for +c: Cmp
  for +h: {Cmp.is_eq(Word.cmp.fin(a, b, c)) == True{} : Bool}
  {Cmp.is_eq(c) == True{} : Bool}

def rt.fin_c(a, b, c, h):
  match c:
    case LT{}:
      rt.ft({Cmp.is_eq(LT{}) == True{} : Bool}, h)
    case EQ{}:
      {==}
    case GT{}:
      rt.ft({Cmp.is_eq(GT{}) == True{} : Bool}, h)

law rt.fin_b:
  for +c: Cmp
  for +a: Bool
  for +b: Bool
  for +h: {Cmp.is_eq(Word.cmp.fin(a, b, c)) == True{} : Bool}
  {a == b : Bool}

def rt.fin_b(c, a, b, h):
  match c:
    case LT{}:
      rt.ft({a == b : Bool}, h)
    case EQ{}:
      match a b:
        case False{} False{}:
          {==}
        case False{} True{}:
          rt.ft({False{} == True{} : Bool}, h)
        case True{} False{}:
          rt.ft({True{} == False{} : Bool}, h)
        case True{} True{}:
          {==}
    case GT{}:
      rt.ft({a == b : Bool}, h)

law rt.weq:
  for +n: Nat
  for +x: Word(n)
  for +y: Word(n)
  for +h: {Cmp.is_eq(Word.cmp(n, x, y)) == True{} : Bool}
  {x == y : Word(n)}

def rt.weq(n, x, y, h):
  match n:
    case 0n:
      match x y:
        case WNil{} WNil{}:
          {==}
    case 1n+p:
      match x y:
        case WCon{+a, +at} WCon{+b, +bt}:
          %rt.fin_b(Word.cmp(p, at, bt), a, b, h) : {WCon{a, at} == WCon{_, bt} : Word(1n+p)}
          %rt.weq(p, at, bt, rt.fin_c(a, b, Word.cmp(p, at, bt), h)) : {WCon{a, at} == WCon{a, _} : Word(1n+p)}
          {==}

law rt.u32_eq:
  for +x: U32
  for +y: U32
  for +h: {U32.is_eq(x, y) == True{} : Bool}
  {x == y : U32}

def rt.u32_eq(x, y, h):
  match x y:
    case U32{a} U32{b}:
      %rt.weq(32n, a, b, h) : {U32{a} == U32{_} : U32}
      {==}

# Nat
# ---

def rt.ndisc(n: Nat) -> Type:
  match n:
    case 0n:
      Unit
    case 1n+p:
      Empty

def rt.zs(-A: Type, -p: Nat, e: {0n == 1n+p : Nat}) -> A:
  Empty.absurd(A, (%e : rt.ndisc(_); Unit{}))

def rt.sz(-A: Type, -p: Nat, e: {1n+p == 0n : Nat}) -> A:
  rt.zs(A, p, Equal.sym(Nat, 1n+p, 0n, e))

def rt.pred(n: Nat) -> Nat:
  match n:
    case 0n:
      0n
    case 1n+p:
      p

law rt.succ_inj:
  for -a: Nat
  for -b: Nat
  for +e: {1n+a == 1n+b : Nat}
  {a == b : Nat}

def rt.succ_inj(a, b, e):
  Equal.cong(Nat, Nat, rt.pred, 1n+a, 1n+b, e)

law rt.add_zero:
  for +n: Nat
  {n == Nat.add(n, 0n) : Nat}

def rt.add_zero(n):
  match n:
    case 0n:
      {==}
    case 1n+p:
      %rt.add_zero(p) : {1n+p == 1n+_ : Nat}
      {==}

law rt.add_succ:
  for +a: Nat
  for -b: Nat
  {1n+Nat.add(a, b) == Nat.add(a, 1n+b) : Nat}

def rt.add_succ(a, b):
  match a:
    case 0n:
      {==}
    case 1n+p:
      %rt.add_succ(p, b) : {2n+Nat.add(p, b) == 1n+_ : Nat}
      {==}

law rt.nat_eq:
  for +a: Nat
  for +b: Nat
  for +h: {Nat.is_eq(a, b) == True{} : Bool}
  {a == b : Nat}

def rt.nat_eq(a, b, h):
  match a b:
    case 0n 0n:
      {==}
    case 0n 1n+q:
      rt.ft({0n == 1n+q : Nat}, h)
    case 1n+p 0n:
      rt.ft({1n+p == 0n : Nat}, h)
    case 1n+p 1n+q:
      %rt.nat_eq(p, q, h) : {1n+p == 1n+_ : Nat}
      {==}

law rt.sub_add:
  for +n: Nat
  for +m: Nat
  for +h: {Nat.is_le(n, m) == True{} : Bool}
  {m == Nat.add(Nat.sub(m, n), n) : Nat}

def rt.sub_add(n, m, h):
  match n m:
    case 0n 0n:
      {==}
    case 0n 1n+q:
      rt.add_zero(1n+q)
    case 1n+p 0n:
      rt.ft({0n == Nat.add(Nat.sub(0n, 1n+p), 1n+p) : Nat}, h)
    case 1n+p 1n+q:
      %rt.add_succ(Nat.sub(q, p), p) : {1n+q == _ : Nat}
      %rt.sub_add(p, q, h) : {1n+q == 1n+_ : Nat}
      {==}

law rt.gt_self:
  for +n: Nat
  {False{} == Nat.is_gt(n, n) : Bool}

def rt.gt_self(n):
  match n:
    case 0n:
      {==}
    case 1n+p:
      rt.gt_self(p)

law rt.lt_succ:
  for +x: Nat
  for +m: Nat
  for +h: {False{} == Nat.is_lt(x, m) : Bool}
  {False{} == Nat.is_lt(1n+x, m) : Bool}

def rt.lt_succ(x, m, h):
  match x m:
    case 0n 0n:
      {==}
    case 0n 1n+q:
      rt.ft({False{} == Nat.is_lt(1n+0n, 1n+q) : Bool}, h)
    case 1n+p 0n:
      {==}
    case 1n+p 1n+q:
      rt.lt_succ(p, q, h)

law rt.lt_add:
  for +a: Nat
  for +c: Nat
  for +m: Nat
  for +h: {False{} == Nat.is_lt(c, m) : Bool}
  {False{} == Nat.is_lt(Nat.add(a, c), m) : Bool}

def rt.lt_add(a, c, m, h):
  match a:
    case 0n:
      h
    case 1n+p:
      rt.lt_succ(Nat.add(p, c), m, rt.lt_add(p, c, m, h))

law rt.sub_succ:
  for +a: Nat
  for +y: Nat
  {y == Nat.sub(Nat.add(a, 1n+y), 1n+a) : Nat}

def rt.sub_succ(a, y):
  match a:
    case 0n:
      match y:
        case 0n:
          {==}
        case 1n+q:
          {==}
    case 1n+p:
      rt.sub_succ(p, y)

# Lists
# -----

law rt.app_nil:
  for +a: List<&2, U32>
  {a == S.Snap.app(a, Nil{}) : List<&2, U32>}

def rt.app_nil(a):
  match a:
    case Nil{}:
      {==}
    case Con{+h, +t}:
      %rt.app_nil(t) : {Con{h, t} == Con{h, _} : List<&2, U32>}
      {==}

law rt.app_assoc:
  for +a: List<&2, U32>
  for +b: List<&2, U32>
  for +c: List<&2, U32>
  {S.Snap.app(a, S.Snap.app(b, c)) == S.Snap.app(S.Snap.app(a, b), c) : List<&2, U32>}

def rt.app_assoc(a, b, c):
  match a:
    case Nil{}:
      {==}
    case Con{+h, +t}:
      %rt.app_assoc(t, b, c) : {Con{h, S.Snap.app(t, S.Snap.app(b, c))} == Con{h, _} : List<&2, U32>}
      {==}

law rt.len_app:
  for +a: List<&2, U32>
  for +b: List<&2, U32>
  {Nat.add(List.length(&2, U32, a), List.length(&2, U32, b)) == List.length(&2, U32, S.Snap.app(a, b)) : Nat}

def rt.len_app(a, b):
  match a:
    case Nil{}:
      {==}
    case Con{+h, +t}:
      %rt.len_app(t, b) : {1n+Nat.add(List.length(&2, U32, t), List.length(&2, U32, b)) == 1n+_ : Nat}
      {==}

law rt.drop_app:
  for +a: List<&2, U32>
  for +b: List<&2, U32>
  for +m: Nat
  {List.drop(&2, U32, b, m) == List.drop(&2, U32, S.Snap.app(a, b), Nat.add(List.length(&2, U32, a), m)) : List<&2, U32>}

def rt.drop_app(a, b, m):
  match a:
    case Nil{}:
      {==}
    case Con{+h, +t}:
      rt.drop_app(t, b, m)

law rt.drop_app_n:
  for +a: List<&2, U32>
  for +b: List<&2, U32>
  for -n: Nat
  for +m: Nat
  for +h: {List.length(&2, U32, a) == n : Nat}
  {List.drop(&2, U32, b, m) == List.drop(&2, U32, S.Snap.app(a, b), Nat.add(n, m)) : List<&2, U32>}

def rt.drop_app_n(a, b, n, m, h):
  %h : {List.drop(&2, U32, b, m) == List.drop(&2, U32, S.Snap.app(a, b), Nat.add(_, m)) : List<&2, U32>}
  rt.drop_app(a, b, m)

law rt.take_app:
  for +a: List<&2, U32>
  for +b: List<&2, U32>
  {a == List.take(&2, U32, S.Snap.app(a, b), List.length(&2, U32, a)) : List<&2, U32>}

def rt.take_app(a, b):
  match a:
    case Nil{}:
      match b:
        case Nil{}:
          {==}
        case Con{x, y}:
          {==}
    case Con{+h, +t}:
      %rt.take_app(t, b) : {Con{h, t} == Con{h, _} : List<&2, U32>}
      {==}

law rt.take_app_n:
  for +a: List<&2, U32>
  for +b: List<&2, U32>
  for -n: Nat
  for +h: {List.length(&2, U32, a) == n : Nat}
  {a == List.take(&2, U32, S.Snap.app(a, b), n) : List<&2, U32>}

def rt.take_app_n(a, b, n, h):
  %h : {a == List.take(&2, U32, S.Snap.app(a, b), _) : List<&2, U32>}
  rt.take_app(a, b)

law rt.split_app:
  for +a: List<&2, U32>
  for +b: List<&2, U32>
  {S.BB{a, b} == S.Snap.Tar.split_at(List.length(&2, U32, a), S.Snap.app(a, b)) : S.Snap.BB}

def rt.split_app(a, b):
  match a:
    case Nil{}:
      {==}
    case Con{+h, +t}:
      %rt.split_app(t, b) : {S.BB{Con{h, t}, b} == S.Snap.Tar.split_at.cons(h, _) : S.Snap.BB}
      {==}

law rt.rg_app:
  for +xs: List<&2, U32>
  for +acc: List<&2, U32>
  {S.Snap.app(List.reverse.go(&2, U32, xs, Nil{}), acc) == List.reverse.go(&2, U32, xs, acc) : List<&2, U32>}

def rt.rg_app(xs, acc):
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +t}:
      %rt.rg_app(t, Con{x, acc}) : {S.Snap.app(List.reverse.go(&2, U32, t, [x]), acc) == _ : List<&2, U32>}
      %rt.rg_app(t, [x]) : {S.Snap.app(_, acc) == S.Snap.app(List.reverse.go(&2, U32, t, Nil{}), Con{x, acc}) : List<&2, U32>}
      %rt.app_assoc(List.reverse.go(&2, U32, t, Nil{}), [x], acc) : {_ == S.Snap.app(List.reverse.go(&2, U32, t, Nil{}), Con{x, acc}) : List<&2, U32>}
      {==}

law rt.rr2:
  for +xs: List<&2, U32>
  for +a: List<&2, U32>
  for +b: List<&2, U32>
  {List.reverse.go(&2, U32, a, S.Snap.app(xs, b)) == List.reverse.go(&2, U32, List.reverse.go(&2, U32, xs, a), b) : List<&2, U32>}

def rt.rr2(xs, a, b):
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +t}:
      rt.rr2(t, Con{x, a}, b)

law rt.rr:
  for +xs: List<&2, U32>
  {xs == List.reverse(&2, U32, List.reverse.go(&2, U32, xs, Nil{})) : List<&2, U32>}

def rt.rr(xs):
  %rt.rr2(xs, Nil{}, Nil{}) : {xs == _ : List<&2, U32>}
  rt.app_nil(xs)

# Octal size fields
# -----------------

def rt.asc(os: List<&2, S.Snap.Oct>) -> List<&2, U32>:
  match os:
    case Nil{}:
      Nil{}
    case Con{o, t}:
      S.Snap.Oct.ascii(o) <> rt.asc(t)

def rt.zo(j: Nat, os: List<&2, S.Snap.Oct>) -> List<&2, S.Snap.Oct>:
  match j:
    case 0n:
      os
    case 1n+p:
      S.O0{} <> rt.zo(p, os)

def rt.V(os: List<&2, S.Snap.Oct>, a: Nat) -> Nat:
  match os:
    case Nil{}:
      a
    case Con{o, t}:
      rt.V(t, S.Snap.Oct.add(o, S.Snap.n8(a)))

def rt.U(ds: List<&2, S.Snap.Oct>, a: Nat) -> Nat:
  match ds:
    case Nil{}:
      a
    case Con{d, t}:
      S.Snap.Oct.add(d, S.Snap.n8(rt.U(t, a)))

law rt.rb_asc:
  for +ds: List<&2, S.Snap.Oct>
  for +os: List<&2, S.Snap.Oct>
  for +z: List<&2, U32>
  {S.Snap.app(rt.asc(List.reverse.go(&2, S.Snap.Oct, ds, os)), z) == S.Snap.Oct.rbytes(ds, S.Snap.app(rt.asc(os), z)) : List<&2, U32>}

def rt.rb_asc(ds, os, z):
  match ds:
    case Nil{}:
      {==}
    case Con{+o, +t}:
      rt.rb_asc(t, Con{o, os}, z)

law rt.zp_asc:
  for +j: Nat
  for +os: List<&2, S.Snap.Oct>
  for +z: List<&2, U32>
  {S.Snap.app(rt.asc(rt.zo(j, os)), z) == S.Snap.app(S.Snap.Tar.zpad(j), S.Snap.app(rt.asc(os), z)) : List<&2, U32>}

def rt.zp_asc(j, os, z):
  match j:
    case 0n:
      {==}
    case 1n+p:
      %rt.zp_asc(p, os, z) : {Con{48, S.Snap.app(rt.asc(rt.zo(p, os)), z)} == Con{48, _} : List<&2, U32>}
      {==}

law rt.size_asc:
  for +ds: List<&2, S.Snap.Oct>
  {S.Snap.app(rt.asc(rt.zo(Nat.sub(11n, List.length(&2, S.Snap.Oct, ds)), List.reverse.go(&2, S.Snap.Oct, ds, Nil{}))), [0]) == S.Snap.Tar.size(ds) : List<&2, U32>}

def rt.size_asc(ds):
  %rt.rb_asc(ds, Nil{}, [0]) : {S.Snap.app(rt.asc(rt.zo(Nat.sub(11n, List.length(&2, S.Snap.Oct, ds)), List.reverse.go(&2, S.Snap.Oct, ds, Nil{}))), [0]) == S.Snap.app(S.Snap.Tar.zpad(Nat.sub(11n, List.length(&2, S.Snap.Oct, ds))), _) : List<&2, U32>}
  rt.zp_asc(Nat.sub(11n, List.length(&2, S.Snap.Oct, ds)), List.reverse.go(&2, S.Snap.Oct, ds, Nil{}), [0])

law rt.num_asc:
  for +os: List<&2, S.Snap.Oct>
  {S.Snap.Tar.octal_value(S.Snap.app(rt.asc(os), [0])) == S.Snap.Tar.numeric(S.Snap.app(rt.asc(os), [0])) : Maybe<&2, Nat>}

def rt.num_asc(os):
  match os:
    case Nil{}:
      {==}
    case Con{o, t}:
      match o:
        case S.O0{}:
          {==}
        case S.O1{}:
          {==}
        case S.O2{}:
          {==}
        case S.O3{}:
          {==}
        case S.O4{}:
          {==}
        case S.O5{}:
          {==}
        case S.O6{}:
          {==}
        case S.O7{}:
          {==}

law rt.tl_asc:
  for +o: S.Snap.Oct
  for +t: List<&2, S.Snap.Oct>
  for +z: List<&2, U32>
  {S.Snap.app(rt.asc(Con{o, t}), z) == S.Snap.Tar.trim_left(S.Snap.app(rt.asc(Con{o, t}), z)) : List<&2, U32>}

def rt.tl_asc(o, t, z):
  match o:
    case S.O0{}:
      {==}
    case S.O1{}:
      {==}
    case S.O2{}:
      {==}
    case S.O3{}:
      {==}
    case S.O4{}:
      {==}
    case S.O5{}:
      {==}
    case S.O6{}:
      {==}
    case S.O7{}:
      {==}

law rt.spn:
  for +o: S.Snap.Oct
  {False{} == S.Snap.Tar.sp_nul(S.Snap.Oct.ascii(o)) : Bool}

def rt.spn(o):
  match o:
    case S.O0{}:
      {==}
    case S.O1{}:
      {==}
    case S.O2{}:
      {==}
    case S.O3{}:
      {==}
    case S.O4{}:
      {==}
    case S.O5{}:
      {==}
    case S.O6{}:
      {==}
    case S.O7{}:
      {==}

law rt.nzo:
  for +o: S.Snap.Oct
  {False{} == U32.is_eq(S.Snap.Oct.ascii(o), 0) : Bool}

def rt.nzo(o):
  match o:
    case S.O0{}:
      {==}
    case S.O1{}:
      {==}
    case S.O2{}:
      {==}
    case S.O3{}:
      {==}
    case S.O4{}:
      {==}
    case S.O5{}:
      {==}
    case S.O6{}:
      {==}
    case S.O7{}:
      {==}

law rt.od1:
  for +o: S.Snap.Oct
  {True{} == S.Snap.Oct.is_digit(S.Snap.Oct.ascii(o)) : Bool}

def rt.od1(o):
  match o:
    case S.O0{}:
      {==}
    case S.O1{}:
      {==}
    case S.O2{}:
      {==}
    case S.O3{}:
      {==}
    case S.O4{}:
      {==}
    case S.O5{}:
      {==}
    case S.O6{}:
      {==}
    case S.O7{}:
      {==}

law rt.od2:
  for +o: S.Snap.Oct
  {o == S.Snap.Oct.digit(S.Snap.Oct.ascii(o)) : S.Snap.Oct}

def rt.od2(o):
  match o:
    case S.O0{}:
      {==}
    case S.O1{}:
      {==}
    case S.O2{}:
      {==}
    case S.O3{}:
      {==}
    case S.O4{}:
      {==}
    case S.O5{}:
      {==}
    case S.O6{}:
      {==}
    case S.O7{}:
      {==}

law rt.tr_asc:
  for +os: List<&2, S.Snap.Oct>
  {rt.asc(os) == S.Snap.Tar.trim_right(S.Snap.app(rt.asc(os), [0])) : List<&2, U32>}

def rt.tr_asc(os):
  match os:
    case Nil{}:
      {==}
    case Con{+o, +t}:
      %rt.tr_asc(t) : {Con{S.Snap.Oct.ascii(o), rt.asc(t)} == S.Snap.Tar.trim_right.put(S.Snap.Oct.ascii(o), _) : List<&2, U32>}
      %rt.spn(o) : {Con{S.Snap.Oct.ascii(o), rt.asc(t)} == S.Snap.trim_slash.if(Bool.and(List.is_empty(&2, U32, rt.asc(t)), _), S.Snap.Oct.ascii(o), rt.asc(t)) : List<&2, U32>}
      %rt.and_false(List.is_empty(&2, U32, rt.asc(t))) : {Con{S.Snap.Oct.ascii(o), rt.asc(t)} == S.Snap.trim_slash.if(_, S.Snap.Oct.ascii(o), rt.asc(t)) : List<&2, U32>}
      {==}

law rt.cn_asc:
  for +os: List<&2, S.Snap.Oct>
  {rt.asc(os) == S.Snap.Tar.cut_nul(rt.asc(os)) : List<&2, U32>}

def rt.cn_asc(os):
  match os:
    case Nil{}:
      {==}
    case Con{+o, +t}:
      %rt.cn_asc(t) : {Con{S.Snap.Oct.ascii(o), rt.asc(t)} == S.Snap.Tar.cut_nul.if(U32.is_eq(S.Snap.Oct.ascii(o), 0), S.Snap.Oct.ascii(o), _) : List<&2, U32>}
      %rt.nzo(o) : {Con{S.Snap.Oct.ascii(o), rt.asc(t)} == S.Snap.Tar.cut_nul.if(_, S.Snap.Oct.ascii(o), rt.asc(t)) : List<&2, U32>}
      {==}

law rt.op_asc:
  for +os: List<&2, S.Snap.Oct>
  for +a: Nat
  {Some{rt.V(os, a)} == S.Snap.Oct.parse(rt.asc(os), a) : Maybe<&2, Nat>}

def rt.op_asc(os, a):
  match os:
    case Nil{}:
      {==}
    case Con{+o, +t}:
      %rt.od1(o) : {Some{rt.V(t, S.Snap.Oct.add(o, S.Snap.n8(a)))} == S.Snap.chk(_, S.Snap.Oct.parse(rt.asc(t), S.Snap.Oct.add(S.Snap.Oct.digit(S.Snap.Oct.ascii(o)), S.Snap.n8(a)))) : Maybe<&2, Nat>}
      %rt.od2(o) : {Some{rt.V(t, S.Snap.Oct.add(o, S.Snap.n8(a)))} == S.Snap.chk(True{}, S.Snap.Oct.parse(rt.asc(t), S.Snap.Oct.add(_, S.Snap.n8(a)))) : Maybe<&2, Nat>}
      rt.op_asc(t, S.Snap.Oct.add(o, S.Snap.n8(a)))

law rt.ov_asc:
  for +os: List<&2, S.Snap.Oct>
  {Some{rt.V(os, 0n)} == S.Snap.Tar.octal_value(S.Snap.app(rt.asc(os), [0])) : Maybe<&2, Nat>}

def rt.ov_asc(os):
  match os:
    case Nil{}:
      {==}
    case Con{+o, +t}:
      %rt.tl_asc(o, t, [0]) : {Some{rt.V(Con{o, t}, 0n)} == S.Snap.Tar.octal.parse(S.Snap.Tar.trim_right(_)) : Maybe<&2, Nat>}
      %rt.tr_asc(Con{o, t}) : {Some{rt.V(Con{o, t}, 0n)} == S.Snap.Tar.octal.parse(_) : Maybe<&2, Nat>}
      %rt.cn_asc(Con{o, t}) : {Some{rt.V(Con{o, t}, 0n)} == S.Snap.Tar.octal.digits(_) : Maybe<&2, Nat>}
      rt.op_asc(Con{o, t}, 0n)

law rt.V_zo:
  for +j: Nat
  for +os: List<&2, S.Snap.Oct>
  {rt.V(os, 0n) == rt.V(rt.zo(j, os), 0n) : Nat}

def rt.V_zo(j, os):
  match j:
    case 0n:
      {==}
    case 1n+p:
      rt.V_zo(p, os)

law rt.V_rg:
  for +ds: List<&2, S.Snap.Oct>
  for +os: List<&2, S.Snap.Oct>
  for +a: Nat
  {rt.V(os, rt.U(ds, a)) == rt.V(List.reverse.go(&2, S.Snap.Oct, ds, os), a) : Nat}

def rt.V_rg(ds, os, a):
  match ds:
    case Nil{}:
      {==}
    case Con{+d, +t}:
      rt.V_rg(t, Con{d, os}, a)

law rt.U0:
  for +ds: List<&2, S.Snap.Oct>
  {S.Snap.Oct.val(ds) == rt.U(ds, 0n) : Nat}

def rt.U0(ds):
  match ds:
    case Nil{}:
      {==}
    case Con{+d, +t}:
      %rt.U0(t) : {S.Snap.Oct.add(d, S.Snap.n8(S.Snap.Oct.val(t))) == S.Snap.Oct.add(d, S.Snap.n8(_)) : Nat}
      {==}

law rt.num_size:
  for +ds: List<&2, S.Snap.Oct>
  {Some{S.Snap.Oct.val(ds)} == S.Snap.Tar.numeric(S.Snap.Tar.size(ds)) : Maybe<&2, Nat>}

def rt.num_size(ds):
  %rt.size_asc(ds) : {Some{S.Snap.Oct.val(ds)} == S.Snap.Tar.numeric(_) : Maybe<&2, Nat>}
  %rt.num_asc(rt.zo(Nat.sub(11n, List.length(&2, S.Snap.Oct, ds)), List.reverse.go(&2, S.Snap.Oct, ds, Nil{}))) : {Some{S.Snap.Oct.val(ds)} == _ : Maybe<&2, Nat>}
  %rt.ov_asc(rt.zo(Nat.sub(11n, List.length(&2, S.Snap.Oct, ds)), List.reverse.go(&2, S.Snap.Oct, ds, Nil{}))) : {Some{S.Snap.Oct.val(ds)} == _ : Maybe<&2, Nat>}
  %rt.V_zo(Nat.sub(11n, List.length(&2, S.Snap.Oct, ds)), List.reverse.go(&2, S.Snap.Oct, ds, Nil{})) : {Some{S.Snap.Oct.val(ds)} == Some{_} : Maybe<&2, Nat>}
  %rt.V_rg(ds, Nil{}, 0n) : {Some{S.Snap.Oct.val(ds)} == Some{_} : Maybe<&2, Nat>}
  %rt.U0(ds) : {Some{S.Snap.Oct.val(ds)} == Some{_} : Maybe<&2, Nat>}
  {==}

law rt.val_inc:
  for +ds: List<&2, S.Snap.Oct>
  {1n+S.Snap.Oct.val(ds) == S.Snap.Oct.val(S.Snap.Oct.inc(ds)) : Nat}

def rt.val_inc(ds):
  match ds:
    case Nil{}:
      {==}
    case Con{o, +t}:
      match o:
        case S.O0{}:
          {==}
        case S.O1{}:
          {==}
        case S.O2{}:
          {==}
        case S.O3{}:
          {==}
        case S.O4{}:
          {==}
        case S.O5{}:
          {==}
        case S.O6{}:
          {==}
        case S.O7{}:
          %rt.val_inc(t) : {8n+S.Snap.n8(S.Snap.Oct.val(t)) == S.Snap.n8(_) : Nat}
          {==}

law rt.val_count:
  for +xs: List<&2, U32>
  {List.length(&2, U32, xs) == S.Snap.Oct.val(S.Snap.Oct.count(xs)) : Nat}

def rt.val_count(xs):
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +t}:
      %rt.val_inc(S.Snap.Oct.count(t)) : {1n+List.length(&2, U32, t) == _ : Nat}
      %rt.val_count(t) : {1n+List.length(&2, U32, t) == 1n+_ : Nat}
      {==}

# Fixed-width fields
# ------------------

def rt.fhd(s: List<&2, U32>) -> U32:
  match s:
    case Nil{}:
      0
    case Con{c, t}:
      c

def rt.ftl(s: List<&2, U32>) -> List<&2, U32>:
  match s:
    case Nil{}:
      Nil{}
    case Con{c, t}:
      t

# The n bytes of a field, as an explicit list of n cells.
def rt.F(n: Nat, +s: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      rt.fhd(s) <> rt.F(p, rt.ftl(s))

law rt.len_field0:
  for +n: Nat
  for +s: List<&2, U32>
  {n == List.length(&2, U32, S.Snap.Tar.field(n, s)) : Nat}

def rt.len_field0(n, s):
  match n s:
    case 0n _:
      {==}
    case 1n+p Nil{}:
      %rt.len_field0(p, Nil{}) : {1n+p == 1n+_ : Nat}
      {==}
    case 1n+p Con{+c, +t}:
      %rt.len_field0(p, t) : {1n+p == 1n+_ : Nat}
      {==}

law rt.len_field:
  for +n: Nat
  for +s: List<&2, U32>
  {List.length(&2, U32, S.Snap.Tar.field(n, s)) == n : Nat}

def rt.len_field(n, s):
  Equal.sym(Nat, n, List.length(&2, U32, S.Snap.Tar.field(n, s)), rt.len_field0(n, s))

law rt.fe:
  for +n: Nat
  for +s: List<&2, U32>
  {rt.F(n, s) == S.Snap.Tar.field(n, s) : List<&2, U32>}

def rt.fe(n, s):
  match n s:
    case 0n _:
      {==}
    case 1n+p Nil{}:
      %rt.fe(p, Nil{}) : {Con{0, rt.F(p, Nil{})} == Con{0, _} : List<&2, U32>}
      {==}
    case 1n+p Con{+c, +t}:
      %rt.fe(p, t) : {Con{c, rt.F(p, t)} == Con{c, _} : List<&2, U32>}
      {==}

law rt.fid:
  for +n: Nat
  for +s: List<&2, U32>
  for +h: {List.length(&2, U32, s) == n : Nat}
  {rt.F(n, s) == s : List<&2, U32>}

def rt.fid(n, s, h):
  match n s:
    case 0n Nil{}:
      {==}
    case 0n Con{+c, +t}:
      rt.sz({rt.F(0n, Con{c, t}) == Con{c, t} : List<&2, U32>}, List.length(&2, U32, t), h)
    case 1n+p Nil{}:
      rt.zs({rt.F(1n+p, Nil{}) == Nil{} : List<&2, U32>}, p, h)
    case 1n+p Con{+c, +t}:
      %rt.fid(p, t, rt.succ_inj(List.length(&2, U32, t), p, h)) : {Con{c, rt.F(p, t)} == Con{c, _} : List<&2, U32>}
      {==}

law rt.len_rb:
  for +ds: List<&2, S.Snap.Oct>
  for +acc: List<&2, U32>
  {Nat.add(List.length(&2, S.Snap.Oct, ds), List.length(&2, U32, acc)) == List.length(&2, U32, S.Snap.Oct.rbytes(ds, acc)) : Nat}

def rt.len_rb(ds, acc):
  match ds:
    case Nil{}:
      {==}
    case Con{+o, +t}:
      %rt.len_rb(t, Con{S.Snap.Oct.ascii(o), acc}) : {1n+Nat.add(List.length(&2, S.Snap.Oct, t), List.length(&2, U32, acc)) == _ : Nat}
      rt.add_succ(List.length(&2, S.Snap.Oct, t), List.length(&2, U32, acc))

law rt.len_zpad:
  for +n: Nat
  {n == List.length(&2, U32, S.Snap.Tar.zpad(n)) : Nat}

def rt.len_zpad(n):
  match n:
    case 0n:
      {==}
    case 1n+p:
      %rt.len_zpad(p) : {1n+p == 1n+_ : Nat}
      {==}

law rt.len_size0:
  for +ds: List<&2, S.Snap.Oct>
  for +h: {Nat.is_le(List.length(&2, S.Snap.Oct, ds), 11n) == True{} : Bool}
  {12n == List.length(&2, U32, S.Snap.Tar.size(ds)) : Nat}

def rt.len_size0(ds, h):
  %rt.len_app(S.Snap.Tar.zpad(Nat.sub(11n, List.length(&2, S.Snap.Oct, ds))), S.Snap.Oct.rbytes(ds, [0])) : {12n == _ : Nat}
  %rt.len_zpad(Nat.sub(11n, List.length(&2, S.Snap.Oct, ds))) : {12n == Nat.add(_, List.length(&2, U32, S.Snap.Oct.rbytes(ds, [0]))) : Nat}
  %rt.len_rb(ds, [0]) : {12n == Nat.add(Nat.sub(11n, List.length(&2, S.Snap.Oct, ds)), _) : Nat}
  %rt.add_succ(List.length(&2, S.Snap.Oct, ds), 0n) : {12n == Nat.add(Nat.sub(11n, List.length(&2, S.Snap.Oct, ds)), _) : Nat}
  %rt.add_zero(List.length(&2, S.Snap.Oct, ds)) : {12n == Nat.add(Nat.sub(11n, List.length(&2, S.Snap.Oct, ds)), 1n+_) : Nat}
  %rt.add_succ(Nat.sub(11n, List.length(&2, S.Snap.Oct, ds)), List.length(&2, S.Snap.Oct, ds)) : {12n == _ : Nat}
  %rt.sub_add(List.length(&2, S.Snap.Oct, ds), 11n, h) : {12n == 1n+_ : Nat}
  {==}

law rt.len_size:
  for +ds: List<&2, S.Snap.Oct>
  for +h: {Nat.is_le(List.length(&2, S.Snap.Oct, ds), 11n) == True{} : Bool}
  {List.length(&2, U32, S.Snap.Tar.size(ds)) == 12n : Nat}

def rt.len_size(ds, h):
  Equal.sym(Nat, 12n, List.length(&2, U32, S.Snap.Tar.size(ds)), rt.len_size0(ds, h))

law rt.num_size12:
  for +ds: List<&2, S.Snap.Oct>
  for +h: {Nat.is_le(List.length(&2, S.Snap.Oct, ds), 11n) == True{} : Bool}
  {Some{S.Snap.Oct.val(ds)} == S.Snap.Tar.numeric(rt.F(12n, S.Snap.Tar.size(ds))) : Maybe<&2, Nat>}

def rt.num_size12(ds, h):
  %Equal.sym(List<&2, U32>, rt.F(12n, S.Snap.Tar.size(ds)), S.Snap.Tar.size(ds), rt.fid(12n, S.Snap.Tar.size(ds), rt.len_size(ds, h))) : {Some{S.Snap.Oct.val(ds)} == S.Snap.Tar.numeric(_) : Maybe<&2, Nat>}
  rt.num_size(ds)

# Header blocks
# -------------

# Snap.Tar.pre and Snap.Tar.post with the name, size and prefix fields
# already formatted.
def rt.pre2(fname: List<&2, U32>, mode: List<&2, U32>, size: List<&2, U32>) -> List<&2, U32>:
  S.Snap.app(fname, S.Snap.app(mode, S.Snap.app(S.Snap.Tar.zero8(), S.Snap.app(S.Snap.Tar.zero8(), S.Snap.app(size, S.Snap.Tar.zero12())))))

def rt.post2(flag: U32, +dev: List<&2, U32>, fprefix: List<&2, U32>) -> List<&2, U32>:
  flag <> S.Snap.app(S.Snap.zeros(100n),
    S.Snap.app([117, 115, 116, 97, 114, 0, 48, 48],
      S.Snap.app(S.Snap.zeros(64n), S.Snap.app(dev, S.Snap.app(dev,
        S.Snap.app(fprefix, S.Snap.zeros(12n)))))))

law rt.beq_refl:
  for +xs: List<&2, U32>
  {True{} == S.Snap.beq(xs, xs) : Bool}

def rt.beq_refl(xs):
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +t}:
      %rt.u32_refl(x) : {True{} == Bool.and(_, S.Snap.beq(t, t)) : Bool}
      rt.beq_refl(t)

law rt.cks_ok:
  for +pre: List<&2, U32>
  for +post: List<&2, U32>
  {True{} == S.Snap.Tar.cks_ok(S.Snap.Tar.cks_field(S.Snap.Tar.cks(pre, post)), pre, post) : Bool}

def rt.cks_ok(pre, post):
  %rt.beq_refl(S.Snap.Tar.cks_field(S.Snap.Tar.cks(pre, post))) : {True{} == Bool.or(_, S.Snap.Tar.cks_ok.m(S.Snap.Tar.octal_value(S.Snap.Tar.cks_field(S.Snap.Tar.cks(pre, post))), U32.to_nat(S.Snap.Tar.cks(pre, post)), S.Snap.Tar.count_high(S.Snap.app(pre, post), 0n))) : Bool}
  {==}

law rt.hdr_file:
  for +nm: List<&2, U32>
  for +ds: List<&2, S.Snap.Oct>
  for +h: {Nat.is_le(List.length(&2, S.Snap.Oct, ds), 11n) == True{} : Bool}
  for +flag: U32
  for +pf: List<&2, U32>
  {Done{S.Hdr{flag, S.Snap.Tar.join(S.Snap.Tar.cut_nul(rt.F(155n, pf)), S.Snap.Tar.cut_nul(rt.F(100n, nm))), S.Snap.Oct.val(ds)}} == S.Snap.Tar.hdr(S.Snap.Tar.block(nm, S.Snap.Tar.mode666(), S.Snap.Tar.size(ds), flag, S.Snap.Tar.zero8(), pf)) : Result<&2, &2, String, S.Snap.Tar.Hdr>}

def rt.hdr_file(nm, ds, h, flag, pf):
  %rt.fe(100n, nm) : {Done{S.Hdr{flag, S.Snap.Tar.join(S.Snap.Tar.cut_nul(rt.F(155n, pf)), S.Snap.Tar.cut_nul(rt.F(100n, nm))), S.Snap.Oct.val(ds)}} == S.Snap.Tar.hdr(S.Snap.Tar.block.go(rt.pre2(_, S.Snap.Tar.mode666(), S.Snap.Tar.size(ds)), rt.post2(flag, S.Snap.Tar.zero8(), S.Snap.Tar.field(155n, pf)))) : Result<&2, &2, String, S.Snap.Tar.Hdr>}
  %rt.fe(155n, pf) : {Done{S.Hdr{flag, S.Snap.Tar.join(S.Snap.Tar.cut_nul(rt.F(155n, pf)), S.Snap.Tar.cut_nul(rt.F(100n, nm))), S.Snap.Oct.val(ds)}} == S.Snap.Tar.hdr(S.Snap.Tar.block.go(rt.pre2(rt.F(100n, nm), S.Snap.Tar.mode666(), S.Snap.Tar.size(ds)), rt.post2(flag, S.Snap.Tar.zero8(), _))) : Result<&2, &2, String, S.Snap.Tar.Hdr>}
  %rt.fid(12n, S.Snap.Tar.size(ds), rt.len_size(ds, h)) : {Done{S.Hdr{flag, S.Snap.Tar.join(S.Snap.Tar.cut_nul(rt.F(155n, pf)), S.Snap.Tar.cut_nul(rt.F(100n, nm))), S.Snap.Oct.val(ds)}} == S.Snap.Tar.hdr(S.Snap.Tar.block.go(rt.pre2(rt.F(100n, nm), S.Snap.Tar.mode666(), _), rt.post2(flag, S.Snap.Tar.zero8(), rt.F(155n, pf)))) : Result<&2, &2, String, S.Snap.Tar.Hdr>}
  %rt.cks_ok(rt.pre2(rt.F(100n, nm), S.Snap.Tar.mode666(), rt.F(12n, S.Snap.Tar.size(ds))), rt.post2(flag, S.Snap.Tar.zero8(), rt.F(155n, pf))) : {Done{S.Hdr{flag, S.Snap.Tar.join(S.Snap.Tar.cut_nul(rt.F(155n, pf)), S.Snap.Tar.cut_nul(rt.F(100n, nm))), S.Snap.Oct.val(ds)}} == S.Snap.Tar.hdr.cks(_, rt.pre2(rt.F(100n, nm), S.Snap.Tar.mode666(), rt.F(12n, S.Snap.Tar.size(ds))), rt.post2(flag, S.Snap.Tar.zero8(), rt.F(155n, pf))) : Result<&2, &2, String, S.Snap.Tar.Hdr>}
  %rt.num_size12(ds, h) : {Done{S.Hdr{flag, S.Snap.Tar.join(S.Snap.Tar.cut_nul(rt.F(155n, pf)), S.Snap.Tar.cut_nul(rt.F(100n, nm))), S.Snap.Oct.val(ds)}} == S.Snap.Tar.hdr.size(_, True{}, flag, S.Snap.Tar.join(S.Snap.Tar.cut_nul(rt.F(155n, pf)), S.Snap.Tar.cut_nul(rt.F(100n, nm)))) : Result<&2, &2, String, S.Snap.Tar.Hdr>}
  {==}

law rt.hdr_pax:
  for +nm: List<&2, U32>
  for +ds: List<&2, S.Snap.Oct>
  for +h: {Nat.is_le(List.length(&2, S.Snap.Oct, ds), 11n) == True{} : Bool}
  {Done{S.Hdr{120, S.Snap.Tar.cut_nul(rt.F(100n, nm)), S.Snap.Oct.val(ds)}} == S.Snap.Tar.hdr(S.Snap.Tar.block(nm, S.Snap.Tar.zero8(), S.Snap.Tar.size(ds), 120, S.Snap.zeros(8n), Nil{})) : Result<&2, &2, String, S.Snap.Tar.Hdr>}

def rt.hdr_pax(nm, ds, h):
  %rt.fe(100n, nm) : {Done{S.Hdr{120, S.Snap.Tar.cut_nul(rt.F(100n, nm)), S.Snap.Oct.val(ds)}} == S.Snap.Tar.hdr(S.Snap.Tar.block.go(rt.pre2(_, S.Snap.Tar.zero8(), S.Snap.Tar.size(ds)), S.Snap.Tar.post(120, S.Snap.zeros(8n), Nil{}))) : Result<&2, &2, String, S.Snap.Tar.Hdr>}
  %rt.fid(12n, S.Snap.Tar.size(ds), rt.len_size(ds, h)) : {Done{S.Hdr{120, S.Snap.Tar.cut_nul(rt.F(100n, nm)), S.Snap.Oct.val(ds)}} == S.Snap.Tar.hdr(S.Snap.Tar.block.go(rt.pre2(rt.F(100n, nm), S.Snap.Tar.zero8(), _), S.Snap.Tar.post(120, S.Snap.zeros(8n), Nil{}))) : Result<&2, &2, String, S.Snap.Tar.Hdr>}
  %rt.cks_ok(rt.pre2(rt.F(100n, nm), S.Snap.Tar.zero8(), rt.F(12n, S.Snap.Tar.size(ds))), S.Snap.Tar.post(120, S.Snap.zeros(8n), Nil{})) : {Done{S.Hdr{120, S.Snap.Tar.cut_nul(rt.F(100n, nm)), S.Snap.Oct.val(ds)}} == S.Snap.Tar.hdr.cks(_, rt.pre2(rt.F(100n, nm), S.Snap.Tar.zero8(), rt.F(12n, S.Snap.Tar.size(ds))), S.Snap.Tar.post(120, S.Snap.zeros(8n), Nil{})) : Result<&2, &2, String, S.Snap.Tar.Hdr>}
  %rt.num_size12(ds, h) : {Done{S.Hdr{120, S.Snap.Tar.cut_nul(rt.F(100n, nm)), S.Snap.Oct.val(ds)}} == S.Snap.Tar.hdr.size(_, True{}, 120, S.Snap.Tar.cut_nul(rt.F(100n, nm))) : Result<&2, &2, String, S.Snap.Tar.Hdr>}
  {==}

law rt.len_file:
  for +nm: List<&2, U32>
  for +ds: List<&2, S.Snap.Oct>
  for +h: {Nat.is_le(List.length(&2, S.Snap.Oct, ds), 11n) == True{} : Bool}
  for +pf: List<&2, U32>
  {List.length(&2, U32, S.Snap.Tar.block(nm, S.Snap.Tar.mode666(), S.Snap.Tar.size(ds), 48, S.Snap.Tar.zero8(), pf)) == 1n+511n : Nat}

def rt.len_file(nm, ds, h, pf):
  %rt.fe(100n, nm) : {List.length(&2, U32, S.Snap.Tar.block.go(rt.pre2(_, S.Snap.Tar.mode666(), S.Snap.Tar.size(ds)), rt.post2(48, S.Snap.Tar.zero8(), S.Snap.Tar.field(155n, pf)))) == 1n+511n : Nat}
  %rt.fe(155n, pf) : {List.length(&2, U32, S.Snap.Tar.block.go(rt.pre2(rt.F(100n, nm), S.Snap.Tar.mode666(), S.Snap.Tar.size(ds)), rt.post2(48, S.Snap.Tar.zero8(), _))) == 1n+511n : Nat}
  %rt.fid(12n, S.Snap.Tar.size(ds), rt.len_size(ds, h)) : {List.length(&2, U32, S.Snap.Tar.block.go(rt.pre2(rt.F(100n, nm), S.Snap.Tar.mode666(), _), rt.post2(48, S.Snap.Tar.zero8(), rt.F(155n, pf)))) == 1n+511n : Nat}
  {==}

law rt.len_pax:
  for +nm: List<&2, U32>
  for +ds: List<&2, S.Snap.Oct>
  for +h: {Nat.is_le(List.length(&2, S.Snap.Oct, ds), 11n) == True{} : Bool}
  {List.length(&2, U32, S.Snap.Tar.block(nm, S.Snap.Tar.zero8(), S.Snap.Tar.size(ds), 120, S.Snap.zeros(8n), Nil{})) == 1n+511n : Nat}

def rt.len_pax(nm, ds, h):
  %rt.fe(100n, nm) : {List.length(&2, U32, S.Snap.Tar.block.go(rt.pre2(_, S.Snap.Tar.zero8(), S.Snap.Tar.size(ds)), S.Snap.Tar.post(120, S.Snap.zeros(8n), Nil{}))) == 1n+511n : Nat}
  %rt.fid(12n, S.Snap.Tar.size(ds), rt.len_size(ds, h)) : {List.length(&2, U32, S.Snap.Tar.block.go(rt.pre2(rt.F(100n, nm), S.Snap.Tar.zero8(), _), S.Snap.Tar.post(120, S.Snap.zeros(8n), Nil{}))) == 1n+511n : Nat}
  {==}

law rt.az2:
  for a: List<&2, U32>
  for +b: List<&2, U32>
  for +h: {False{} == S.Snap.Tar.all_zero(b) : Bool}
  {False{} == S.Snap.Tar.all_zero(S.Snap.app(a, b)) : Bool}

def rt.az2(a, b, h):
  match a:
    case Nil{}:
      h
    case Con{+c, +t}:
      %rt.az2(t, b, h) : {False{} == Bool.and(U32.is_eq(c, 0), _) : Bool}
      rt.and_false(U32.is_eq(c, 0))

law rt.az.h:
  for z: Bool
  for -t: List<&2, U32>
  for -b: List<&2, U32>
  for h: {False{} == Bool.and(z, S.Snap.Tar.all_zero(t)) : Bool}
  for ih: {False{} == S.Snap.Tar.all_zero(t) : Bool} -> {False{} == S.Snap.Tar.all_zero(S.Snap.app(t, b)) : Bool}
  {False{} == Bool.and(z, S.Snap.Tar.all_zero(S.Snap.app(t, b))) : Bool}

def rt.az.h(z, t, b, h, ih):
  match z:
    case False{}:
      {==}
    case True{}:
      ih(h)

law rt.az:
  for a: List<&2, U32>
  for +b: List<&2, U32>
  for h: {False{} == S.Snap.Tar.all_zero(a) : Bool}
  {False{} == S.Snap.Tar.all_zero(S.Snap.app(a, b)) : Bool}

def rt.az(a, b, h):
  match a:
    case Nil{}:
      rt.ft({False{} == S.Snap.Tar.all_zero(b) : Bool}, h)
    case Con{+c, +t}:
      rt.az.h(U32.is_eq(c, 0), t, b, h, hh => rt.az(t, b, hh))

law rt.az_file:
  for +nm: List<&2, U32>
  for +ds: List<&2, S.Snap.Oct>
  for +pf: List<&2, U32>
  {False{} == S.Snap.Tar.all_zero(S.Snap.Tar.block(nm, S.Snap.Tar.mode666(), S.Snap.Tar.size(ds), 48, S.Snap.Tar.zero8(), pf)) : Bool}

def rt.az_file(nm, ds, pf):
  rt.az(S.Snap.Tar.pre(nm, S.Snap.Tar.mode666(), S.Snap.Tar.size(ds)),
    S.Snap.app(S.Snap.Tar.cks_field(S.Snap.Tar.cks(S.Snap.Tar.pre(nm, S.Snap.Tar.mode666(), S.Snap.Tar.size(ds)), S.Snap.Tar.post(48, S.Snap.Tar.zero8(), pf))), S.Snap.Tar.post(48, S.Snap.Tar.zero8(), pf)),
    rt.az2(S.Snap.Tar.field(100n, nm), S.Snap.app(S.Snap.Tar.mode666(), S.Snap.app(S.Snap.Tar.zero8(), S.Snap.app(S.Snap.Tar.zero8(), S.Snap.app(S.Snap.Tar.size(ds), S.Snap.Tar.zero12())))), {==}))

law rt.az_pax:
  for +nm: List<&2, U32>
  for +ds: List<&2, S.Snap.Oct>
  {False{} == S.Snap.Tar.all_zero(S.Snap.Tar.block(nm, S.Snap.Tar.zero8(), S.Snap.Tar.size(ds), 120, S.Snap.zeros(8n), Nil{})) : Bool}

def rt.az_pax(nm, ds):
  rt.az(S.Snap.Tar.pre(nm, S.Snap.Tar.zero8(), S.Snap.Tar.size(ds)),
    S.Snap.app(S.Snap.Tar.cks_field(S.Snap.Tar.cks(S.Snap.Tar.pre(nm, S.Snap.Tar.zero8(), S.Snap.Tar.size(ds)), S.Snap.Tar.post(120, S.Snap.zeros(8n), Nil{}))), S.Snap.Tar.post(120, S.Snap.zeros(8n), Nil{})),
    rt.az2(S.Snap.Tar.field(100n, nm), S.Snap.app(S.Snap.Tar.zero8(), S.Snap.app(S.Snap.Tar.zero8(), S.Snap.app(S.Snap.Tar.zero8(), S.Snap.app(S.Snap.Tar.size(ds), S.Snap.Tar.zero12())))), {==}))

law rt.ob_file:
  for +nm: List<&2, U32>
  for +ds: List<&2, S.Snap.Oct>
  for +h: {Nat.is_le(List.length(&2, S.Snap.Oct, ds), 11n) == True{} : Bool}
  for +pf: List<&2, U32>
  for +p: S.Snap.Tar.Pend
  for +lim: Maybe<&2, Nat>
  {S.Snap.Tar.on_hdr(Done{S.Hdr{48, S.Snap.Tar.join(S.Snap.Tar.cut_nul(rt.F(155n, pf)), S.Snap.Tar.cut_nul(rt.F(100n, nm))), S.Snap.Oct.val(ds)}}, p, lim) == S.Snap.Tar.on_block(S.Snap.Tar.block(nm, S.Snap.Tar.mode666(), S.Snap.Tar.size(ds), 48, S.Snap.Tar.zero8(), pf), p, lim) : S.Snap.Tar.Step}

def rt.ob_file(nm, ds, h, pf, p, lim):
  %rt.az_file(nm, ds, pf) : {S.Snap.Tar.on_hdr(Done{S.Hdr{48, S.Snap.Tar.join(S.Snap.Tar.cut_nul(rt.F(155n, pf)), S.Snap.Tar.cut_nul(rt.F(100n, nm))), S.Snap.Oct.val(ds)}}, p, lim) == S.Snap.Tar.on_block.if(_, S.Snap.Tar.block(nm, S.Snap.Tar.mode666(), S.Snap.Tar.size(ds), 48, S.Snap.Tar.zero8(), pf), p, lim) : S.Snap.Tar.Step}
  %rt.hdr_file(nm, ds, h, 48, pf) : {S.Snap.Tar.on_hdr(Done{S.Hdr{48, S.Snap.Tar.join(S.Snap.Tar.cut_nul(rt.F(155n, pf)), S.Snap.Tar.cut_nul(rt.F(100n, nm))), S.Snap.Oct.val(ds)}}, p, lim) == S.Snap.Tar.on_hdr(_, p, lim) : S.Snap.Tar.Step}
  {==}

law rt.ob_pax:
  for +nm: List<&2, U32>
  for +ds: List<&2, S.Snap.Oct>
  for +h: {Nat.is_le(List.length(&2, S.Snap.Oct, ds), 11n) == True{} : Bool}
  for +p: S.Snap.Tar.Pend
  for +lim: Maybe<&2, Nat>
  {S.Snap.Tar.on_hdr(Done{S.Hdr{120, S.Snap.Tar.cut_nul(rt.F(100n, nm)), S.Snap.Oct.val(ds)}}, p, lim) == S.Snap.Tar.on_block(S.Snap.Tar.block(nm, S.Snap.Tar.zero8(), S.Snap.Tar.size(ds), 120, S.Snap.zeros(8n), Nil{}), p, lim) : S.Snap.Tar.Step}

def rt.ob_pax(nm, ds, h, p, lim):
  %rt.az_pax(nm, ds) : {S.Snap.Tar.on_hdr(Done{S.Hdr{120, S.Snap.Tar.cut_nul(rt.F(100n, nm)), S.Snap.Oct.val(ds)}}, p, lim) == S.Snap.Tar.on_block.if(_, S.Snap.Tar.block(nm, S.Snap.Tar.zero8(), S.Snap.Tar.size(ds), 120, S.Snap.zeros(8n), Nil{}), p, lim) : S.Snap.Tar.Step}
  %rt.hdr_pax(nm, ds, h) : {S.Snap.Tar.on_hdr(Done{S.Hdr{120, S.Snap.Tar.cut_nul(rt.F(100n, nm)), S.Snap.Oct.val(ds)}}, p, lim) == S.Snap.Tar.on_hdr(_, p, lim) : S.Snap.Tar.Step}
  {==}

# The byte-at-a-time decoder
# --------------------------

# The rest of Snap.Tar.go after a step.
def rt.g(+s: S.Snap.Tar.Step, rest: List<&2, U32>) -> Result<&2, &2, String, List<&2, S.Snap.Rec>>:
  S.Snap.Tar.emit(S.Snap.Tar.Step.out(s), S.Snap.Tar.go(rest, S.Snap.Tar.Step.st(s), S.Snap.Tar.Step.lim(s)))

law rt.hread:
  for +xs: List<&2, U32>
  for +q: Nat
  for +h: {List.length(&2, U32, xs) == 1n+q : Nat}
  for +acc: List<&2, U32>
  for +p: S.Snap.Tar.Pend
  for +lim: Maybe<&2, Nat>
  for +rest: List<&2, U32>
  {rt.g(S.Snap.Tar.on_block(List.reverse(&2, U32, List.reverse.go(&2, U32, xs, acc)), p, lim), rest) == S.Snap.Tar.go(S.Snap.app(xs, rest), S.SHdr{1n+q, acc, p}, lim) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

def rt.hread(xs, q, h, acc, p, lim, rest):
  match xs:
    case Nil{}:
      rt.zs({rt.g(S.Snap.Tar.on_block(List.reverse(&2, U32, acc), p, lim), rest) == S.Snap.Tar.go(rest, S.SHdr{1n+q, acc, p}, lim) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}, q, h)
    case Con{+x, +t}:
      match t:
        case Nil{}:
          match q:
            case 0n:
              {==}
            case 1n+r:
              rt.zs({rt.g(S.Snap.Tar.on_block(List.reverse(&2, U32, Con{x, acc}), p, lim), rest) == S.Snap.Tar.go(Con{x, rest}, S.SHdr{2n+r, acc, p}, lim) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}, r, rt.succ_inj(0n, 1n+r, h))
        case Con{+y, +u}:
          match q:
            case 0n:
              rt.sz({rt.g(S.Snap.Tar.on_block(List.reverse(&2, U32, List.reverse.go(&2, U32, Con{y, u}, Con{x, acc})), p, lim), rest) == S.Snap.Tar.go(Con{x, Con{y, S.Snap.app(u, rest)}}, S.SHdr{1n+0n, acc, p}, lim) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}, List.length(&2, U32, u), rt.succ_inj(1n+List.length(&2, U32, u), 0n, h))
            case 1n+r:
              rt.hread(Con{y, u}, r, rt.succ_inj(1n+List.length(&2, U32, u), 1n+r, h), Con{x, acc}, p, lim, rest)

def rt.kend(xs: List<&2, U32>, k: Nat) -> Nat:
  match xs:
    case Nil{}:
      k
    case Con{x, t}:
      rt.kend(t, S.Snap.Tar.next(k))

law rt.dread:
  for +xs: List<&2, U32>
  for +n: Nat
  for +h: {List.length(&2, U32, xs) == 1n+n : Nat}
  for +acc: List<&2, U32>
  for +k: Nat
  for +what: S.Snap.Tar.What
  for +p: S.Snap.Tar.Pend
  for +lim: Maybe<&2, Nat>
  for +rest: List<&2, U32>
  {rt.g(S.Snap.Tar.done(what, List.reverse(&2, U32, List.reverse.go(&2, U32, xs, acc)), rt.kend(xs, k), p, lim), rest) == S.Snap.Tar.go(S.Snap.app(xs, rest), S.SData{1n+n, acc, k, what, p}, lim) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

def rt.dread(xs, n, h, acc, k, what, p, lim, rest):
  match xs:
    case Nil{}:
      rt.zs({rt.g(S.Snap.Tar.done(what, List.reverse(&2, U32, acc), k, p, lim), rest) == S.Snap.Tar.go(rest, S.SData{1n+n, acc, k, what, p}, lim) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}, n, h)
    case Con{+x, +t}:
      match t:
        case Nil{}:
          match n:
            case 0n:
              {==}
            case 1n+r:
              rt.zs({rt.g(S.Snap.Tar.done(what, List.reverse(&2, U32, Con{x, acc}), S.Snap.Tar.next(k), p, lim), rest) == S.Snap.Tar.go(Con{x, rest}, S.SData{2n+r, acc, k, what, p}, lim) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}, r, rt.succ_inj(0n, 1n+r, h))
        case Con{+y, +u}:
          match n:
            case 0n:
              rt.sz({rt.g(S.Snap.Tar.done(what, List.reverse(&2, U32, List.reverse.go(&2, U32, Con{y, u}, Con{x, acc})), rt.kend(Con{y, u}, S.Snap.Tar.next(k)), p, lim), rest) == S.Snap.Tar.go(Con{x, Con{y, S.Snap.app(u, rest)}}, S.SData{1n+0n, acc, k, what, p}, lim) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}, List.length(&2, U32, u), rt.succ_inj(1n+List.length(&2, U32, u), 0n, h))
            case 1n+r:
              rt.dread(Con{y, u}, r, rt.succ_inj(1n+List.length(&2, U32, u), 1n+r, h), Con{x, acc}, S.Snap.Tar.next(k), what, p, lim, rest)

law rt.data_split:
  for +xs: List<&2, U32>
  for +k: Nat
  {S.Snap.app(xs, S.Snap.Tar.pad(Nat.is_eq(rt.kend(xs, k), 512n), rt.kend(xs, k))) == S.Snap.Tar.data(xs, k) : List<&2, U32>}

def rt.data_split(xs, k):
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +t}:
      %rt.data_split(t, S.Snap.Tar.next(k)) : {Con{x, S.Snap.app(t, S.Snap.Tar.pad(Nat.is_eq(rt.kend(t, S.Snap.Tar.next(k)), 512n), rt.kend(t, S.Snap.Tar.next(k))))} == Con{x, _} : List<&2, U32>}
      {==}

def rt.np(j: Nat) -> Nat:
  match j:
    case 0n:
      511n
    case 1n+q:
      q

law rt.next_pos:
  for +j: Nat
  {1n+rt.np(j) == S.Snap.Tar.next(1n+j) : Nat}

def rt.next_pos(j):
  match j:
    case 0n:
      {==}
    case 1n+q:
      {==}

def rt.kp(xs: List<&2, U32>, j: Nat) -> Nat:
  match xs:
    case Nil{}:
      j
    case Con{x, t}:
      rt.kp(t, rt.np(j))

law rt.kend_pos:
  for +xs: List<&2, U32>
  for +j: Nat
  {1n+rt.kp(xs, j) == rt.kend(xs, 1n+j) : Nat}

def rt.kend_pos(xs, j):
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +t}:
      %rt.next_pos(j) : {1n+rt.kp(t, rt.np(j)) == rt.kend(t, _) : Nat}
      rt.kend_pos(t, rt.np(j))

law rt.zeros_read:
  for +j: Nat
  for +rest: List<&2, U32>
  for +p: S.Snap.Tar.Pend
  for +lim: Maybe<&2, Nat>
  {S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(p), lim) == S.Snap.Tar.go(S.Snap.app(S.Snap.zeros(1n+j), rest), S.SPad{1n+j, p}, lim) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

def rt.zeros_read(j, rest, p, lim):
  match j:
    case 0n:
      {==}
    case 1n+i:
      rt.zeros_read(i, rest, p, lim)

law rt.pad_b:
  for +b: Bool
  for +j: Nat
  for +rest: List<&2, U32>
  for +p: S.Snap.Tar.Pend
  for +lim: Maybe<&2, Nat>
  {S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(p), lim) == S.Snap.Tar.go(S.Snap.app(S.Snap.Tar.pad(b, 1n+j), rest), S.Snap.Tar.after.if(b, 1n+j, p), lim) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

def rt.pad_b(b, j, rest, p, lim):
  match b:
    case True{}:
      {==}
    case False{}:
      rt.zeros_read(j, rest, p, lim)

law rt.pad_k:
  for +j: Nat
  for +rest: List<&2, U32>
  for +p: S.Snap.Tar.Pend
  for +lim: Maybe<&2, Nat>
  {S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(p), lim) == S.Snap.Tar.go(S.Snap.app(S.Snap.Tar.pad(Nat.is_eq(1n+j, 512n), 1n+j), rest), S.Snap.Tar.after(1n+j, p), lim) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

def rt.pad_k(j, rest, p, lim):
  rt.pad_b(Nat.is_eq(1n+j, 512n), j, rest, p, lim)

law rt.fdata:
  for +v: List<&2, U32>
  for +K: List<&2, U32>
  for +rest: List<&2, U32>
  {S.Snap.Tar.emit.rec(S.Rec{K, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == rt.g(S.Snap.Tar.file.size(Nat.is_eq(List.length(&2, U32, v), 0n), K, List.length(&2, U32, v), None{}), S.Snap.app(S.Snap.Tar.data(v, 512n), rest)) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

def rt.fdata(v, K, rest):
  match v:
    case Nil{}:
      {==}
    case Con{+y, +u}:
      %rt.data_split(Con{y, u}, 512n) : {S.Snap.Tar.emit.rec(S.Rec{K, Con{y, u}}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(S.Snap.app(_, rest), S.SData{1n+List.length(&2, U32, u), Nil{}, 512n, S.WFile{K}, S.Snap.Tar.pend0()}, None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
      %rt.app_assoc(Con{y, u}, S.Snap.Tar.pad(Nat.is_eq(rt.kend(Con{y, u}, 512n), 512n), rt.kend(Con{y, u}, 512n)), rest) : {S.Snap.Tar.emit.rec(S.Rec{K, Con{y, u}}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(_, S.SData{1n+List.length(&2, U32, u), Nil{}, 512n, S.WFile{K}, S.Snap.Tar.pend0()}, None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
      %rt.dread(Con{y, u}, List.length(&2, U32, u), {==}, Nil{}, 512n, S.WFile{K}, S.Snap.Tar.pend0(), None{}, S.Snap.app(S.Snap.Tar.pad(Nat.is_eq(rt.kend(Con{y, u}, 512n), 512n), rt.kend(Con{y, u}, 512n)), rest)) : {S.Snap.Tar.emit.rec(S.Rec{K, Con{y, u}}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == _ : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
      %rt.rr(Con{y, u}) : {S.Snap.Tar.emit.rec(S.Rec{K, Con{y, u}}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.emit.rec(S.Rec{K, _}, S.Snap.Tar.go(S.Snap.app(S.Snap.Tar.pad(Nat.is_eq(rt.kend(Con{y, u}, 512n), 512n), rt.kend(Con{y, u}, 512n)), rest), S.Snap.Tar.after(rt.kend(Con{y, u}, 512n), S.Snap.Tar.pend0()), None{})) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
      %rt.kend_pos(Con{y, u}, 511n) : {S.Snap.Tar.emit.rec(S.Rec{K, Con{y, u}}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.emit.rec(S.Rec{K, Con{y, u}}, S.Snap.Tar.go(S.Snap.app(S.Snap.Tar.pad(Nat.is_eq(_, 512n), _), rest), S.Snap.Tar.after(_, S.Snap.Tar.pend0()), None{})) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
      %rt.pad_k(rt.kp(Con{y, u}, 511n), rest, S.Snap.Tar.pend0(), None{}) : {S.Snap.Tar.emit.rec(S.Rec{K, Con{y, u}}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.emit.rec(S.Rec{K, Con{y, u}}, _) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
      {==}

law rt.pdata:
  for +xs: List<&2, U32>
  for +P: S.Snap.Tar.Pend
  for +hp: {Some{P} == S.Snap.Tar.px(xs, S.Snap.Tar.pend0()) : Maybe<&2, S.Snap.Tar.Pend>}
  for +J: List<&2, U32>
  for +rest: List<&2, U32>
  {S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(P), None{}) == rt.g(S.Snap.Tar.special(S.WPax{False{}, J}, List.length(&2, U32, xs), S.Snap.Tar.pend0(), None{}), S.Snap.app(S.Snap.Tar.data(xs, 512n), rest)) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

def rt.pdata(xs, P, hp, J, rest):
  match xs:
    case Nil{}:
      %hp : {S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(P), None{}) == rt.g(S.Snap.Tar.done.pax(_, False{}, J, 512n, None{}), rest) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
      {==}
    case Con{+y, +u}:
      %rt.data_split(Con{y, u}, 512n) : {S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(P), None{}) == S.Snap.Tar.go(S.Snap.app(_, rest), S.SData{1n+List.length(&2, U32, u), Nil{}, 512n, S.WPax{False{}, J}, S.Snap.Tar.pend0()}, None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
      %rt.app_assoc(Con{y, u}, S.Snap.Tar.pad(Nat.is_eq(rt.kend(Con{y, u}, 512n), 512n), rt.kend(Con{y, u}, 512n)), rest) : {S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(P), None{}) == S.Snap.Tar.go(_, S.SData{1n+List.length(&2, U32, u), Nil{}, 512n, S.WPax{False{}, J}, S.Snap.Tar.pend0()}, None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
      %rt.dread(Con{y, u}, List.length(&2, U32, u), {==}, Nil{}, 512n, S.WPax{False{}, J}, S.Snap.Tar.pend0(), None{}, S.Snap.app(S.Snap.Tar.pad(Nat.is_eq(rt.kend(Con{y, u}, 512n), 512n), rt.kend(Con{y, u}, 512n)), rest)) : {S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(P), None{}) == _ : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
      %rt.rr(Con{y, u}) : {S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(P), None{}) == rt.g(S.Snap.Tar.done.pax(S.Snap.Tar.px(_, S.Snap.Tar.pend0()), False{}, J, rt.kend(Con{y, u}, 512n), None{}), S.Snap.app(S.Snap.Tar.pad(Nat.is_eq(rt.kend(Con{y, u}, 512n), 512n), rt.kend(Con{y, u}, 512n)), rest)) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
      %hp : {S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(P), None{}) == rt.g(S.Snap.Tar.done.pax(_, False{}, J, rt.kend(Con{y, u}, 512n), None{}), S.Snap.app(S.Snap.Tar.pad(Nat.is_eq(rt.kend(Con{y, u}, 512n), 512n), rt.kend(Con{y, u}, 512n)), rest)) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
      %rt.kend_pos(Con{y, u}, 511n) : {S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(P), None{}) == S.Snap.Tar.go(S.Snap.app(S.Snap.Tar.pad(Nat.is_eq(_, 512n), _), rest), S.Snap.Tar.after(_, P), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
      rt.pad_k(rt.kp(Con{y, u}, 511n), rest, P, None{})

law rt.file_entry:
  for +nm: List<&2, U32>
  for +pf: List<&2, U32>
  for +v: List<&2, U32>
  for +hs: {Nat.is_le(List.length(&2, S.Snap.Oct, S.Snap.Oct.count(v)), 11n) == True{} : Bool}
  for +path: Maybe<&2, List<&2, U32>>
  for +K: List<&2, U32>
  for +hn: {K == S.Snap.Tar.pick_name(path, S.Snap.Tar.join(S.Snap.Tar.cut_nul(rt.F(155n, pf)), S.Snap.Tar.cut_nul(rt.F(100n, nm)))) : List<&2, U32>}
  for +rest: List<&2, U32>
  {S.Snap.Tar.emit.rec(S.Rec{K, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(S.Snap.app(S.Snap.Tar.ustar(nm, pf, S.Snap.Oct.count(v)), S.Snap.app(S.Snap.Tar.data(v, 512n), rest)), S.Snap.Tar.hdr0(S.Pend{path, None{}, Nil{}}), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

def rt.file_entry(nm, pf, v, hs, path, K, hn, rest):
  %rt.hread(S.Snap.Tar.ustar(nm, pf, S.Snap.Oct.count(v)), 511n, rt.len_file(nm, S.Snap.Oct.count(v), hs, pf), Nil{}, S.Pend{path, None{}, Nil{}}, None{}, S.Snap.app(S.Snap.Tar.data(v, 512n), rest)) : {S.Snap.Tar.emit.rec(S.Rec{K, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == _ : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
  %rt.rr(S.Snap.Tar.ustar(nm, pf, S.Snap.Oct.count(v))) : {S.Snap.Tar.emit.rec(S.Rec{K, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == rt.g(S.Snap.Tar.on_block(_, S.Pend{path, None{}, Nil{}}, None{}), S.Snap.app(S.Snap.Tar.data(v, 512n), rest)) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
  %rt.ob_file(nm, S.Snap.Oct.count(v), hs, pf, S.Pend{path, None{}, Nil{}}, None{}) : {S.Snap.Tar.emit.rec(S.Rec{K, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == rt.g(_, S.Snap.app(S.Snap.Tar.data(v, 512n), rest)) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
  %rt.val_count(v) : {S.Snap.Tar.emit.rec(S.Rec{K, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == rt.g(S.Snap.Tar.file.size(Nat.is_eq(_, 0n), S.Snap.Tar.pick_name(path, S.Snap.Tar.join(S.Snap.Tar.cut_nul(rt.F(155n, pf)), S.Snap.Tar.cut_nul(rt.F(100n, nm)))), _, None{}), S.Snap.app(S.Snap.Tar.data(v, 512n), rest)) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
  %hn : {S.Snap.Tar.emit.rec(S.Rec{K, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == rt.g(S.Snap.Tar.file.size(Nat.is_eq(List.length(&2, U32, v), 0n), _, List.length(&2, U32, v), None{}), S.Snap.app(S.Snap.Tar.data(v, 512n), rest)) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
  rt.fdata(v, K, rest)

law rt.phd:
  for +nm: List<&2, U32>
  for +rec: List<&2, U32>
  for +hs: {Nat.is_le(List.length(&2, S.Snap.Oct, S.Snap.Oct.count(rec)), 11n) == True{} : Bool}
  for +P: S.Snap.Tar.Pend
  for +hp: {Some{P} == S.Snap.Tar.px(rec, S.Snap.Tar.pend0()) : Maybe<&2, S.Snap.Tar.Pend>}
  for +rest: List<&2, U32>
  {S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(P), None{}) == S.Snap.Tar.go(S.Snap.app(S.Snap.Tar.block(nm, S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(rec)), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(rec, 512n), rest)), S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

def rt.phd(nm, rec, hs, P, hp, rest):
  %rt.hread(S.Snap.Tar.block(nm, S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(rec)), 120, S.Snap.zeros(8n), Nil{}), 511n, rt.len_pax(nm, S.Snap.Oct.count(rec), hs), Nil{}, S.Snap.Tar.pend0(), None{}, S.Snap.app(S.Snap.Tar.data(rec, 512n), rest)) : {S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(P), None{}) == _ : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
  %rt.rr(S.Snap.Tar.block(nm, S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(rec)), 120, S.Snap.zeros(8n), Nil{})) : {S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(P), None{}) == rt.g(S.Snap.Tar.on_block(_, S.Snap.Tar.pend0(), None{}), S.Snap.app(S.Snap.Tar.data(rec, 512n), rest)) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
  %rt.ob_pax(nm, S.Snap.Oct.count(rec), hs, S.Snap.Tar.pend0(), None{}) : {S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(P), None{}) == rt.g(_, S.Snap.app(S.Snap.Tar.data(rec, 512n), rest)) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
  %rt.val_count(rec) : {S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(P), None{}) == rt.g(S.Snap.Tar.special(S.WPax{False{}, S.Snap.Tar.cut_nul(rt.F(100n, nm))}, _, S.Snap.Tar.pend0(), None{}), S.Snap.app(S.Snap.Tar.data(rec, 512n), rest)) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
  rt.pdata(rec, P, hp, S.Snap.Tar.cut_nul(rt.F(100n, nm)), rest)

# Decimal PAX lengths
# -------------------

def rt.dasc(ds: List<&2, S.Snap.Dec>) -> List<&2, U32>:
  match ds:
    case Nil{}:
      Nil{}
    case Con{d, t}:
      S.Snap.Dec.ascii(d) <> rt.dasc(t)

def rt.VD(os: List<&2, S.Snap.Dec>, a: Nat) -> Nat:
  match os:
    case Nil{}:
      a
    case Con{d, t}:
      rt.VD(t, S.Snap.Dec.add(d, S.Snap.n10(a)))

def rt.UD(ds: List<&2, S.Snap.Dec>, a: Nat) -> Nat:
  match ds:
    case Nil{}:
      a
    case Con{d, t}:
      S.Snap.Dec.add(d, S.Snap.n10(rt.UD(t, a)))

law rt.d32:
  for +d: S.Snap.Dec
  {False{} == U32.is_eq(S.Snap.Dec.ascii(d), 32) : Bool}

def rt.d32(d):
  match d:
    case S.D0{}:
      {==}
    case S.D1{}:
      {==}
    case S.D2{}:
      {==}
    case S.D3{}:
      {==}
    case S.D4{}:
      {==}
    case S.D5{}:
      {==}
    case S.D6{}:
      {==}
    case S.D7{}:
      {==}
    case S.D8{}:
      {==}
    case S.D9{}:
      {==}

law rt.dd1:
  for +d: S.Snap.Dec
  {True{} == S.Snap.Dec.is_digit(S.Snap.Dec.ascii(d)) : Bool}

def rt.dd1(d):
  match d:
    case S.D0{}:
      {==}
    case S.D1{}:
      {==}
    case S.D2{}:
      {==}
    case S.D3{}:
      {==}
    case S.D4{}:
      {==}
    case S.D5{}:
      {==}
    case S.D6{}:
      {==}
    case S.D7{}:
      {==}
    case S.D8{}:
      {==}
    case S.D9{}:
      {==}

law rt.dd2:
  for +d: S.Snap.Dec
  {d == S.Snap.Dec.digit(S.Snap.Dec.ascii(d)) : S.Snap.Dec}

def rt.dd2(d):
  match d:
    case S.D0{}:
      {==}
    case S.D1{}:
      {==}
    case S.D2{}:
      {==}
    case S.D3{}:
      {==}
    case S.D4{}:
      {==}
    case S.D5{}:
      {==}
    case S.D6{}:
      {==}
    case S.D7{}:
      {==}
    case S.D8{}:
      {==}
    case S.D9{}:
      {==}

law rt.pi_dig:
  for +d: S.Snap.Dec
  for +t: List<&2, S.Snap.Dec>
  {S.Snap.Dec.parse(rt.dasc(Con{d, t}), 0n) == S.Snap.Dec.parse_int(rt.dasc(Con{d, t})) : Maybe<&2, Nat>}

def rt.pi_dig(d, t):
  match d:
    case S.D0{}:
      {==}
    case S.D1{}:
      {==}
    case S.D2{}:
      {==}
    case S.D3{}:
      {==}
    case S.D4{}:
      {==}
    case S.D5{}:
      {==}
    case S.D6{}:
      {==}
    case S.D7{}:
      {==}
    case S.D8{}:
      {==}
    case S.D9{}:
      {==}

law rt.cut_dig:
  for +ds: List<&2, S.Snap.Dec>
  for +x: List<&2, U32>
  {Some{S.BB{rt.dasc(ds), x}} == S.Snap.Tar.cut(S.Snap.app(rt.dasc(ds), Con{32, x}), 32) : Maybe<&2, S.Snap.BB>}

def rt.cut_dig(ds, x):
  match ds:
    case Nil{}:
      {==}
    case Con{+d, +t}:
      %rt.d32(d) : {Some{S.BB{Con{S.Snap.Dec.ascii(d), rt.dasc(t)}, x}} == S.Snap.Tar.cut.pick(_, S.Snap.Dec.ascii(d), S.Snap.app(rt.dasc(t), Con{32, x}), S.Snap.Tar.cut(S.Snap.app(rt.dasc(t), Con{32, x}), 32)) : Maybe<&2, S.Snap.BB>}
      %rt.cut_dig(t, x) : {Some{S.BB{Con{S.Snap.Dec.ascii(d), rt.dasc(t)}, x}} == S.Snap.Tar.cut.cons(S.Snap.Dec.ascii(d), _) : Maybe<&2, S.Snap.BB>}
      {==}

law rt.dp_dig:
  for +ds: List<&2, S.Snap.Dec>
  for +a: Nat
  {Some{rt.VD(ds, a)} == S.Snap.Dec.parse(rt.dasc(ds), a) : Maybe<&2, Nat>}

def rt.dp_dig(ds, a):
  match ds:
    case Nil{}:
      {==}
    case Con{+d, +t}:
      %rt.dd1(d) : {Some{rt.VD(t, S.Snap.Dec.add(d, S.Snap.n10(a)))} == S.Snap.chk(_, S.Snap.Dec.parse(rt.dasc(t), S.Snap.Dec.add(S.Snap.Dec.digit(S.Snap.Dec.ascii(d)), S.Snap.n10(a)))) : Maybe<&2, Nat>}
      %rt.dd2(d) : {Some{rt.VD(t, S.Snap.Dec.add(d, S.Snap.n10(a)))} == S.Snap.chk(True{}, S.Snap.Dec.parse(rt.dasc(t), S.Snap.Dec.add(_, S.Snap.n10(a)))) : Maybe<&2, Nat>}
      rt.dp_dig(t, S.Snap.Dec.add(d, S.Snap.n10(a)))

law rt.VD_rg:
  for +ds: List<&2, S.Snap.Dec>
  for +os: List<&2, S.Snap.Dec>
  for +a: Nat
  {rt.VD(os, rt.UD(ds, a)) == rt.VD(List.reverse.go(&2, S.Snap.Dec, ds, os), a) : Nat}

def rt.VD_rg(ds, os, a):
  match ds:
    case Nil{}:
      {==}
    case Con{+d, +t}:
      rt.VD_rg(t, Con{d, os}, a)

law rt.UD0:
  for +ds: List<&2, S.Snap.Dec>
  {S.Snap.Dec.val(ds) == rt.UD(ds, 0n) : Nat}

def rt.UD0(ds):
  match ds:
    case Nil{}:
      {==}
    case Con{+d, +t}:
      %rt.UD0(t) : {S.Snap.Dec.add(d, S.Snap.n10(S.Snap.Dec.val(t))) == S.Snap.Dec.add(d, S.Snap.n10(_)) : Nat}
      {==}

law rt.dval_inc:
  for +ds: List<&2, S.Snap.Dec>
  {1n+S.Snap.Dec.val(ds) == S.Snap.Dec.val(S.Snap.Dec.inc(ds)) : Nat}

def rt.dval_inc(ds):
  match ds:
    case Nil{}:
      {==}
    case Con{d, +t}:
      match d:
        case S.D0{}:
          {==}
        case S.D1{}:
          {==}
        case S.D2{}:
          {==}
        case S.D3{}:
          {==}
        case S.D4{}:
          {==}
        case S.D5{}:
          {==}
        case S.D6{}:
          {==}
        case S.D7{}:
          {==}
        case S.D8{}:
          {==}
        case S.D9{}:
          %rt.dval_inc(t) : {10n+S.Snap.n10(S.Snap.Dec.val(t)) == S.Snap.n10(_) : Nat}
          {==}

law rt.dval_of:
  for +n: Nat
  {n == S.Snap.Dec.val(S.Snap.Dec.of_nat(n)) : Nat}

def rt.dval_of(n):
  match n:
    case 0n:
      {==}
    case 1n+p:
      %rt.dval_inc(S.Snap.Dec.of_nat(p)) : {1n+p == _ : Nat}
      %rt.dval_of(p) : {1n+p == 1n+_ : Nat}
      {==}

law rt.drb:
  for +ds: List<&2, S.Snap.Dec>
  for +os: List<&2, S.Snap.Dec>
  for +z: List<&2, U32>
  {S.Snap.app(rt.dasc(List.reverse.go(&2, S.Snap.Dec, ds, os)), z) == S.Snap.Dec.rbytes(ds, S.Snap.app(rt.dasc(os), z)) : List<&2, U32>}

def rt.drb(ds, os, z):
  match ds:
    case Nil{}:
      {==}
    case Con{+d, +t}:
      rt.drb(t, Con{d, os}, z)

def rt.idig(ds: List<&2, S.Snap.Dec>) -> List<&2, S.Snap.Dec>:
  match ds:
    case Nil{}:
      [S.D0{}]
    case Con{d, t}:
      List.reverse.go(&2, S.Snap.Dec, Con{d, t}, Nil{})

law rt.app_nil_d:
  for +a: List<&2, U32>
  {S.Snap.app(a, Nil{}) == a : List<&2, U32>}

def rt.app_nil_d(a):
  Equal.sym(List<&2, U32>, a, S.Snap.app(a, Nil{}), rt.app_nil(a))

law rt.itoa_dasc:
  for +ds: List<&2, S.Snap.Dec>
  {rt.dasc(rt.idig(ds)) == S.Snap.Dec.itoa.go(ds) : List<&2, U32>}

def rt.itoa_dasc(ds):
  match ds:
    case Nil{}:
      {==}
    case Con{+d, +t}:
      %rt.drb(Con{d, t}, Nil{}, Nil{}) : {rt.dasc(List.reverse.go(&2, S.Snap.Dec, Con{d, t}, Nil{})) == _ : List<&2, U32>}
      rt.app_nil(rt.dasc(List.reverse.go(&2, S.Snap.Dec, Con{d, t}, Nil{})))

law rt.rg_ne:
  for +t: List<&2, S.Snap.Dec>
  for +d: S.Snap.Dec
  for +os: List<&2, S.Snap.Dec>
  {False{} == List.is_empty(&2, S.Snap.Dec, List.reverse.go(&2, S.Snap.Dec, t, Con{d, os})) : Bool}

def rt.rg_ne(t, d, os):
  match t:
    case Nil{}:
      {==}
    case Con{+e, +u}:
      rt.rg_ne(u, e, Con{d, os})

law rt.pi_ne:
  for +os: List<&2, S.Snap.Dec>
  for +h: {False{} == List.is_empty(&2, S.Snap.Dec, os) : Bool}
  {S.Snap.Dec.parse(rt.dasc(os), 0n) == S.Snap.Dec.parse_int(rt.dasc(os)) : Maybe<&2, Nat>}

def rt.pi_ne(os, h):
  match os:
    case Nil{}:
      rt.ft({S.Snap.Dec.parse(Nil{}, 0n) == S.Snap.Dec.parse_int(Nil{}) : Maybe<&2, Nat>}, h)
    case Con{+d, +t}:
      rt.pi_dig(d, t)

law rt.pint:
  for +ds: List<&2, S.Snap.Dec>
  {Some{S.Snap.Dec.val(ds)} == S.Snap.Dec.parse_int(rt.dasc(rt.idig(ds))) : Maybe<&2, Nat>}

def rt.pint(ds):
  match ds:
    case Nil{}:
      {==}
    case Con{+d, +t}:
      %rt.pi_ne(List.reverse.go(&2, S.Snap.Dec, Con{d, t}, Nil{}), rt.rg_ne(t, d, Nil{})) : {Some{S.Snap.Dec.val(Con{d, t})} == _ : Maybe<&2, Nat>}
      %rt.dp_dig(List.reverse.go(&2, S.Snap.Dec, Con{d, t}, Nil{}), 0n) : {Some{S.Snap.Dec.val(Con{d, t})} == _ : Maybe<&2, Nat>}
      %rt.VD_rg(Con{d, t}, Nil{}, 0n) : {Some{S.Snap.Dec.val(Con{d, t})} == Some{_} : Maybe<&2, Nat>}
      %rt.UD0(Con{d, t}) : {Some{S.Snap.Dec.val(Con{d, t})} == Some{_} : Maybe<&2, Nat>}
      {==}

law rt.pin:
  for +n: Nat
  {Some{n} == S.Snap.Dec.parse_int(rt.dasc(rt.idig(S.Snap.Dec.of_nat(n)))) : Maybe<&2, Nat>}

def rt.pin(n):
  %Equal.sym(Nat, n, S.Snap.Dec.val(S.Snap.Dec.of_nat(n)), rt.dval_of(n)) : {Some{_} == S.Snap.Dec.parse_int(rt.dasc(rt.idig(S.Snap.Dec.of_nat(n)))) : Maybe<&2, Nat>}
  rt.pint(S.Snap.Dec.of_nat(n))

# The PAX path record
# -------------------

def rt.pdisc(m: Maybe<&2, S.Snap.Tar.PaxRec>) -> Type:
  match m:
    case None{}:
      Empty
    case Some{x}:
      Unit

law rt.drop_app_s:
  for a: List<&2, U32>
  for +b: List<&2, U32>
  for +m: Nat
  {List.drop(&2, U32, b, m) == List.drop(&2, U32, S.Snap.app(a, b), Nat.add(m, List.length(&2, U32, a))) : List<&2, U32>}

def rt.drop_app_s(a, b, m):
  match a:
    case Nil{}:
      %rt.add_zero(m) : {List.drop(&2, U32, b, m) == List.drop(&2, U32, b, _) : List<&2, U32>}
      {==}
    case Con{+h, +t}:
      %rt.add_succ(m, List.length(&2, U32, t)) : {List.drop(&2, U32, b, m) == List.drop(&2, U32, Con{h, S.Snap.app(t, b)}, _) : List<&2, U32>}
      rt.drop_app_s(t, b, m)

law rt.pxgo_nil:
  for +f: Nat
  for +p: S.Snap.Tar.Pend
  {Some{p} == S.Snap.Tar.px.go(f, S.PaxMore{p, Nil{}}) : Maybe<&2, S.Snap.Tar.Pend>}

def rt.pxgo_nil(f, p):
  match f:
    case 0n:
      {==}
    case 1n+g:
      {==}

law rt.px_one:
  for +s: List<&2, U32>
  for +c: U32
  for +t: List<&2, U32>
  for +hr: {Some{S.PaxRec{[112, 97, 116, 104], Con{c, t}, Nil{}}} == S.Snap.Tar.px.record(s) : Maybe<&2, S.Snap.Tar.PaxRec>}
  {Some{S.Pend{Some{Con{c, t}}, None{}, Nil{}}} == S.Snap.Tar.px(s, S.Snap.Tar.pend0()) : Maybe<&2, S.Snap.Tar.Pend>}

def rt.px_one(s, c, t, hr):
  match s:
    case Nil{}:
      Empty.absurd({Some{S.Pend{Some{Con{c, t}}, None{}, Nil{}}} == S.Snap.Tar.px(Nil{}, S.Snap.Tar.pend0()) : Maybe<&2, S.Snap.Tar.Pend>}, (%hr : rt.pdisc(_); Unit{}))
    case Con{+a, +b}:
      %hr : {Some{S.Pend{Some{Con{c, t}}, None{}, Nil{}}} == S.Snap.Tar.px.go(List.length(&2, U32, b), S.Snap.Tar.px.next(_, S.Snap.Tar.pend0())) : Maybe<&2, S.Snap.Tar.Pend>}
      rt.pxgo_nil(List.length(&2, U32, b), S.Pend{Some{Con{c, t}}, None{}, Nil{}})

# "path=" ++ k ++ "\n": the record after its length and space.
def rt.X(k: List<&2, U32>) -> List<&2, U32>:
  Con{112, Con{97, Con{116, Con{104, Con{61, S.Snap.app(k, [10])}}}}}

law rt.px_record:
  for +ds: List<&2, S.Snap.Dec>
  for +n: Nat
  for +c: U32
  for +t: List<&2, U32>
  for +hN: {n == List.length(&2, U32, S.Snap.app(rt.dasc(ds), Con{32, rt.X(Con{c, t})})) : Nat}
  for +hP: {Some{n} == S.Snap.Dec.parse_int(rt.dasc(ds)) : Maybe<&2, Nat>}
  for +hk: {False{} == S.Snap.has_nul(Con{c, t}) : Bool}
  {Some{S.PaxRec{[112, 97, 116, 104], Con{c, t}, Nil{}}} == S.Snap.Tar.px.record(S.Snap.app(rt.dasc(ds), Con{32, rt.X(Con{c, t})})) : Maybe<&2, S.Snap.Tar.PaxRec>}

def rt.px_record(ds, n, c, t, hN, hP, hk):
  %rt.cut_dig(ds, rt.X(Con{c, t})) : {Some{S.PaxRec{[112, 97, 116, 104], Con{c, t}, Nil{}}} == S.Snap.Tar.px.space(_, List.length(&2, U32, S.Snap.app(rt.dasc(ds), Con{32, rt.X(Con{c, t})}))) : Maybe<&2, S.Snap.Tar.PaxRec>}
  %hP : {Some{S.PaxRec{[112, 97, 116, 104], Con{c, t}, Nil{}}} == S.Snap.Tar.px.len(_, rt.dasc(ds), rt.X(Con{c, t}), List.length(&2, U32, S.Snap.app(rt.dasc(ds), Con{32, rt.X(Con{c, t})}))) : Maybe<&2, S.Snap.Tar.PaxRec>}
  %hN : {Some{S.PaxRec{[112, 97, 116, 104], Con{c, t}, Nil{}}} == S.Snap.Tar.px.len.if(Bool.or(Nat.is_lt(n, 5n), Nat.is_gt(n, _)), n, rt.dasc(ds), rt.X(Con{c, t})) : Maybe<&2, S.Snap.Tar.PaxRec>}
  %rt.gt_self(n) : {Some{S.PaxRec{[112, 97, 116, 104], Con{c, t}, Nil{}}} == S.Snap.Tar.px.len.if(Bool.or(Nat.is_lt(n, 5n), _), n, rt.dasc(ds), rt.X(Con{c, t})) : Maybe<&2, S.Snap.Tar.PaxRec>}
  %Equal.sym(Nat, n, List.length(&2, U32, S.Snap.app(rt.dasc(ds), Con{32, rt.X(Con{c, t})})), hN) : {Some{S.PaxRec{[112, 97, 116, 104], Con{c, t}, Nil{}}} == S.Snap.Tar.px.len.if(Bool.or(Nat.is_lt(_, 5n), False{}), n, rt.dasc(ds), rt.X(Con{c, t})) : Maybe<&2, S.Snap.Tar.PaxRec>}
  %rt.len_app(rt.dasc(ds), Con{32, rt.X(Con{c, t})}) : {Some{S.PaxRec{[112, 97, 116, 104], Con{c, t}, Nil{}}} == S.Snap.Tar.px.len.if(Bool.or(Nat.is_lt(_, 5n), False{}), n, rt.dasc(ds), rt.X(Con{c, t})) : Maybe<&2, S.Snap.Tar.PaxRec>}
  %rt.lt_add(List.length(&2, U32, rt.dasc(ds)), List.length(&2, U32, Con{32, rt.X(Con{c, t})}), 5n, {==}) : {Some{S.PaxRec{[112, 97, 116, 104], Con{c, t}, Nil{}}} == S.Snap.Tar.px.len.if(Bool.or(_, False{}), n, rt.dasc(ds), rt.X(Con{c, t})) : Maybe<&2, S.Snap.Tar.PaxRec>}
  %Equal.sym(Nat, n, List.length(&2, U32, S.Snap.app(rt.dasc(ds), Con{32, rt.X(Con{c, t})})), hN) : {Some{S.PaxRec{[112, 97, 116, 104], Con{c, t}, Nil{}}} == S.Snap.Tar.px.body(Nat.sub(_, 1n+List.length(&2, U32, rt.dasc(ds))), rt.X(Con{c, t})) : Maybe<&2, S.Snap.Tar.PaxRec>}
  %rt.len_app(rt.dasc(ds), Con{32, rt.X(Con{c, t})}) : {Some{S.PaxRec{[112, 97, 116, 104], Con{c, t}, Nil{}}} == S.Snap.Tar.px.body(Nat.sub(_, 1n+List.length(&2, U32, rt.dasc(ds))), rt.X(Con{c, t})) : Maybe<&2, S.Snap.Tar.PaxRec>}
  %rt.sub_succ(List.length(&2, U32, rt.dasc(ds)), List.length(&2, U32, rt.X(Con{c, t}))) : {Some{S.PaxRec{[112, 97, 116, 104], Con{c, t}, Nil{}}} == S.Snap.Tar.px.body(_, rt.X(Con{c, t})) : Maybe<&2, S.Snap.Tar.PaxRec>}
  %rt.len_app(Con{c, t}, [10]) : {Some{S.PaxRec{[112, 97, 116, 104], Con{c, t}, Nil{}}} == S.Snap.Tar.px.body(5n+_, rt.X(Con{c, t})) : Maybe<&2, S.Snap.Tar.PaxRec>}
  %rt.add_succ(List.length(&2, U32, Con{c, t}), 0n) : {Some{S.PaxRec{[112, 97, 116, 104], Con{c, t}, Nil{}}} == S.Snap.Tar.px.body(5n+_, rt.X(Con{c, t})) : Maybe<&2, S.Snap.Tar.PaxRec>}
  %rt.add_zero(List.length(&2, U32, Con{c, t})) : {Some{S.PaxRec{[112, 97, 116, 104], Con{c, t}, Nil{}}} == S.Snap.Tar.px.body(6n+_, rt.X(Con{c, t})) : Maybe<&2, S.Snap.Tar.PaxRec>}
  %rt.drop_app_s(Con{c, t}, [10], 0n) : {Some{S.PaxRec{[112, 97, 116, 104], Con{c, t}, Nil{}}} == S.Snap.Tar.px.nl(S.Snap.beq(List.take(&2, U32, _, 1n), [10]), List.take(&2, U32, rt.X(Con{c, t}), 5n+List.length(&2, U32, Con{c, t})), List.drop(&2, U32, rt.X(Con{c, t}), 6n+List.length(&2, U32, Con{c, t}))) : Maybe<&2, S.Snap.Tar.PaxRec>}
  %rt.take_app(Con{c, t}, [10]) : {Some{S.PaxRec{[112, 97, 116, 104], Con{c, t}, Nil{}}} == S.Snap.Tar.px.nl(True{}, Con{112, Con{97, Con{116, Con{104, Con{61, _}}}}}, List.drop(&2, U32, rt.X(Con{c, t}), 6n+List.length(&2, U32, Con{c, t}))) : Maybe<&2, S.Snap.Tar.PaxRec>}
  %rt.drop_app_s(Con{c, t}, [10], 1n) : {Some{S.PaxRec{[112, 97, 116, 104], Con{c, t}, Nil{}}} == S.Snap.Tar.px.nl(True{}, Con{112, Con{97, Con{116, Con{104, Con{61, Con{c, t}}}}}}, _) : Maybe<&2, S.Snap.Tar.PaxRec>}
  %hk : {Some{S.PaxRec{[112, 97, 116, 104], Con{c, t}, Nil{}}} == S.Snap.Tar.px.kv.if(Bool.not(_), [112, 97, 116, 104], Con{c, t}, Nil{}) : Maybe<&2, S.Snap.Tar.PaxRec>}
  {==}

# The bytes of Go's formatPAXRecord for the path k, and its length.
def rt.REC(n: Nat, k: List<&2, U32>) -> List<&2, U32>:
  S.Snap.app(S.Snap.Dec.itoa(n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(k, [10])))

law rt.px_len:
  for +n: Nat
  for +c: U32
  for +t: List<&2, U32>
  for +hfix: {Nat.is_eq(Nat.add(List.length(&2, U32, S.Snap.Dec.itoa(n)), Nat.add(7n, List.length(&2, U32, Con{c, t}))), n) == True{} : Bool}
  {n == List.length(&2, U32, S.Snap.app(rt.dasc(rt.idig(S.Snap.Dec.of_nat(n))), Con{32, rt.X(Con{c, t})})) : Nat}

def rt.px_len(n, c, t, hfix):
  %rt.len_app(rt.dasc(rt.idig(S.Snap.Dec.of_nat(n))), Con{32, rt.X(Con{c, t})}) : {n == _ : Nat}
  %rt.len_app(Con{c, t}, [10]) : {n == Nat.add(List.length(&2, U32, rt.dasc(rt.idig(S.Snap.Dec.of_nat(n)))), 6n+_) : Nat}
  %rt.add_succ(List.length(&2, U32, Con{c, t}), 0n) : {n == Nat.add(List.length(&2, U32, rt.dasc(rt.idig(S.Snap.Dec.of_nat(n)))), 6n+_) : Nat}
  %rt.add_zero(List.length(&2, U32, Con{c, t})) : {n == Nat.add(List.length(&2, U32, rt.dasc(rt.idig(S.Snap.Dec.of_nat(n)))), 7n+_) : Nat}
  %Equal.sym(List<&2, U32>, rt.dasc(rt.idig(S.Snap.Dec.of_nat(n))), S.Snap.Dec.itoa.go(S.Snap.Dec.of_nat(n)), rt.itoa_dasc(S.Snap.Dec.of_nat(n))) : {n == Nat.add(List.length(&2, U32, _), 7n+List.length(&2, U32, Con{c, t})) : Nat}
  Equal.sym(Nat, Nat.add(List.length(&2, U32, S.Snap.Dec.itoa(n)), Nat.add(7n, List.length(&2, U32, Con{c, t}))), n, rt.nat_eq(Nat.add(List.length(&2, U32, S.Snap.Dec.itoa(n)), Nat.add(7n, List.length(&2, U32, Con{c, t}))), n, hfix))

law rt.px_full:
  for +n: Nat
  for +c: U32
  for +t: List<&2, U32>
  for +hfix: {Nat.is_eq(Nat.add(List.length(&2, U32, S.Snap.Dec.itoa(n)), Nat.add(7n, List.length(&2, U32, Con{c, t}))), n) == True{} : Bool}
  for +hk: {False{} == S.Snap.has_nul(Con{c, t}) : Bool}
  {Some{S.Pend{Some{Con{c, t}}, None{}, Nil{}}} == S.Snap.Tar.px(rt.REC(n, Con{c, t}), S.Snap.Tar.pend0()) : Maybe<&2, S.Snap.Tar.Pend>}

def rt.px_full(n, c, t, hfix, hk):
  %rt.itoa_dasc(S.Snap.Dec.of_nat(n)) : {Some{S.Pend{Some{Con{c, t}}, None{}, Nil{}}} == S.Snap.Tar.px(S.Snap.app(_, Con{32, rt.X(Con{c, t})}), S.Snap.Tar.pend0()) : Maybe<&2, S.Snap.Tar.Pend>}
  rt.px_one(S.Snap.app(rt.dasc(rt.idig(S.Snap.Dec.of_nat(n))), Con{32, rt.X(Con{c, t})}), c, t,
    rt.px_record(rt.idig(S.Snap.Dec.of_nat(n)), n, c, t, rt.px_len(n, c, t, hfix), rt.pin(n), hk))

# Names
# -----

law rt.not_true:
  for +a: Bool
  for +h: {Bool.not(a) == True{} : Bool}
  {False{} == a : Bool}

def rt.not_true(a, h):
  match a:
    case False{}:
      {==}
    case True{}:
      rt.ft({False{} == True{} : Bool}, h)

law rt.orl:
  for +a: Bool
  for -b: Bool
  for +h: {False{} == Bool.or(a, b) : Bool}
  {False{} == a : Bool}

def rt.orl(a, b, h):
  match a:
    case False{}:
      {==}
    case True{}:
      rt.ft({False{} == True{} : Bool}, h)

law rt.orr:
  for +a: Bool
  for -b: Bool
  for +h: {False{} == Bool.or(a, b) : Bool}
  {False{} == b : Bool}

def rt.orr(a, b, h):
  match a:
    case False{}:
      h
    case True{}:
      rt.ft({False{} == b : Bool}, h)

law rt.ascii_nonul:
  for +x: List<&2, U32>
  for +h: {S.Snap.is_ascii(x) == True{} : Bool}
  {False{} == S.Snap.has_nul(x) : Bool}

def rt.ascii_nonul(x, h):
  match x:
    case Nil{}:
      {==}
    case Con{+c, +t}:
      %rt.not_true(U32.is_eq(c, 0), rt.and_r(U32.is_lt(c, 128), Bool.not(U32.is_eq(c, 0)), rt.and_l(S.Snap.ascii1(c), S.Snap.is_ascii(t), h))) : {False{} == Bool.or(_, S.Snap.has_nul(t)) : Bool}
      rt.ascii_nonul(t, rt.and_r(S.Snap.ascii1(c), S.Snap.is_ascii(t), h))

law rt.asc_l:
  for +a: List<&2, U32>
  for +b: List<&2, U32>
  for +h: {S.Snap.is_ascii(S.Snap.app(a, b)) == True{} : Bool}
  {S.Snap.is_ascii(a) == True{} : Bool}

def rt.asc_l(a, b, h):
  match a:
    case Nil{}:
      {==}
    case Con{+c, +t}:
      %Equal.sym(Bool, S.Snap.ascii1(c), True{}, rt.and_l(S.Snap.ascii1(c), S.Snap.is_ascii(S.Snap.app(t, b)), h)) : {Bool.and(_, S.Snap.is_ascii(t)) == True{} : Bool}
      rt.asc_l(t, b, rt.and_r(S.Snap.ascii1(c), S.Snap.is_ascii(S.Snap.app(t, b)), h))

law rt.asc_r:
  for +a: List<&2, U32>
  for +b: List<&2, U32>
  for +h: {S.Snap.is_ascii(S.Snap.app(a, b)) == True{} : Bool}
  {S.Snap.is_ascii(b) == True{} : Bool}

def rt.asc_r(a, b, h):
  match a:
    case Nil{}:
      h
    case Con{+c, +t}:
      rt.asc_r(t, b, rt.and_r(S.Snap.ascii1(c), S.Snap.is_ascii(S.Snap.app(t, b)), h))

law rt.cnf:
  for +n: Nat
  for +x: List<&2, U32>
  for +hl: {Nat.is_le(List.length(&2, U32, x), n) == True{} : Bool}
  for +hz: {False{} == S.Snap.has_nul(x) : Bool}
  {x == S.Snap.Tar.cut_nul(rt.F(n, x)) : List<&2, U32>}

def rt.cnf(n, x, hl, hz):
  match n x:
    case 0n Nil{}:
      {==}
    case 0n Con{+c, +t}:
      rt.ft({Con{c, t} == S.Snap.Tar.cut_nul(Nil{}) : List<&2, U32>}, hl)
    case 1n+p Nil{}:
      {==}
    case 1n+p Con{+c, +t}:
      %rt.orl(U32.is_eq(c, 0), S.Snap.has_nul(t), hz) : {Con{c, t} == S.Snap.Tar.cut_nul.if(_, c, S.Snap.Tar.cut_nul(rt.F(p, t))) : List<&2, U32>}
      %rt.cnf(p, t, hl, rt.orr(U32.is_eq(c, 0), S.Snap.has_nul(t), hz)) : {Con{c, t} == S.Snap.Tar.cut_nul.if(False{}, c, _) : List<&2, U32>}
      {==}

law rt.len_rg:
  for +xs: List<&2, U32>
  for +acc: List<&2, U32>
  {Nat.add(List.length(&2, U32, xs), List.length(&2, U32, acc)) == List.length(&2, U32, List.reverse.go(&2, U32, xs, acc)) : Nat}

def rt.len_rg(xs, acc):
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +t}:
      %rt.len_rg(t, Con{x, acc}) : {1n+Nat.add(List.length(&2, U32, t), List.length(&2, U32, acc)) == _ : Nat}
      rt.add_succ(List.length(&2, U32, t), List.length(&2, U32, acc))

law rt.len_rev:
  for +xs: List<&2, U32>
  {List.length(&2, U32, xs) == List.length(&2, U32, List.reverse.go(&2, U32, xs, Nil{})) : Nat}

def rt.len_rev(xs):
  %rt.len_rg(xs, Nil{}) : {List.length(&2, U32, xs) == _ : Nat}
  rt.add_zero(List.length(&2, U32, xs))

law rt.rg_ne32:
  for +t: List<&2, U32>
  for +d: U32
  for +os: List<&2, U32>
  {False{} == List.is_empty(&2, U32, List.reverse.go(&2, U32, t, Con{d, os})) : Bool}

def rt.rg_ne32(t, d, os):
  match t:
    case Nil{}:
      {==}
    case Con{+e, +u}:
      rt.rg_ne32(u, e, Con{d, os})

def rt.Q(k: List<&2, U32>, m: Maybe<&2, S.Snap.BB>) -> Type:
  match m:
    case None{}:
      Unit
    case Some{bb}:
      match bb:
        case S.BB{pr, s}:
          {S.Snap.app(List.reverse(&2, U32, pr), Con{47, s}) == k : List<&2, U32>}

law rt.sg_pick:
  for +b: Bool
  for +c: U32
  for +pos: Nat
  for +lim: Nat
  for +seen: List<&2, U32>
  for +t: List<&2, U32>
  for +cut: Maybe<&2, S.Snap.BB>
  for +k: List<&2, U32>
  for +hb: {Bool.and(U32.is_eq(c, 47), Nat.is_lt(pos, lim)) == b : Bool}
  for hq: rt.Q(k, cut)
  for +hk: {S.Snap.app(List.reverse(&2, U32, seen), Con{c, t}) == k : List<&2, U32>}
  rt.Q(k, S.Snap.Tar.split.pick(b, seen, t, cut))

def rt.sg_pick(b, c, pos, lim, seen, t, cut, k, hb, hq, hk):
  match b:
    case False{}:
      hq
    case True{}:
      %rt.u32_eq(c, 47, rt.and_l(U32.is_eq(c, 47), Nat.is_lt(pos, lim), hb)) : {S.Snap.app(List.reverse(&2, U32, seen), Con{_, t}) == k : List<&2, U32>}
      hk

law rt.sg_hk:
  for +c: U32
  for +seen: List<&2, U32>
  for +t: List<&2, U32>
  for +k: List<&2, U32>
  for +hk: {S.Snap.app(List.reverse(&2, U32, seen), Con{c, t}) == k : List<&2, U32>}
  {S.Snap.app(List.reverse(&2, U32, Con{c, seen}), t) == k : List<&2, U32>}

def rt.sg_hk(c, seen, t, k, hk):
  %rt.rg_app(seen, [c]) : {S.Snap.app(_, t) == k : List<&2, U32>}
  %rt.app_assoc(List.reverse.go(&2, U32, seen, Nil{}), [c], t) : {_ == k : List<&2, U32>}
  hk

law rt.sg:
  for +bs: List<&2, U32>
  for +seen: List<&2, U32>
  for +pos: Nat
  for +lim: Nat
  for +cut: Maybe<&2, S.Snap.BB>
  for +k: List<&2, U32>
  for hq: rt.Q(k, cut)
  for +hk: {S.Snap.app(List.reverse(&2, U32, seen), bs) == k : List<&2, U32>}
  rt.Q(k, S.Snap.Tar.split.go(bs, seen, pos, lim, cut))

def rt.sg(bs, seen, pos, lim, cut, k, hq, hk):
  match bs:
    case Nil{}:
      hq
    case Con{+c, +t}:
      rt.sg(t, Con{c, seen}, 1n+pos, lim, S.Snap.Tar.split.pick(Bool.and(U32.is_eq(c, 47), Nat.is_lt(pos, lim)), seen, t, cut), k,
        rt.sg_pick(Bool.and(U32.is_eq(c, 47), Nat.is_lt(pos, lim)), c, pos, lim, seen, t, cut, k, {==}, hq, hk),
        rt.sg_hk(c, seen, t, k, hk))

def rt.bbdisc(m: Maybe<&2, S.Snap.BB>) -> Type:
  match m:
    case None{}:
      Unit
    case Some{x}:
      Empty

def rt.bfst(m: Maybe<&2, S.Snap.BB>) -> List<&2, U32>:
  match m:
    case None{}:
      Nil{}
    case Some{bb}:
      S.Snap.fst(bb)

def rt.bsnd(m: Maybe<&2, S.Snap.BB>) -> List<&2, U32>:
  match m:
    case None{}:
      Nil{}
    case Some{bb}:
      S.Snap.snd(bb)

law rt.asc_tr:
  for +a: List<&2, U32>
  for +k: List<&2, U32>
  for +hq: {a == k : List<&2, U32>}
  for +hasc: {S.Snap.is_ascii(k) == True{} : Bool}
  {S.Snap.is_ascii(a) == True{} : Bool}

def rt.asc_tr(a, k, hq, hasc):
  %Equal.sym(List<&2, U32>, a, k, hq) : {S.Snap.is_ascii(_) == True{} : Bool}
  hasc

law rt.split_ok:
  for +ok: Bool
  for +pr: List<&2, U32>
  for +s0: List<&2, U32>
  for +p: List<&2, U32>
  for +s: List<&2, U32>
  for +k: List<&2, U32>
  for +hok: {Nat.is_gt(List.length(&2, U32, pr), 0n) && Nat.is_gt(List.length(&2, U32, s0), 0n) && Nat.is_le(List.length(&2, U32, s0), 100n) && Nat.is_le(List.length(&2, U32, pr), 155n) == ok : Bool}
  for +hc: {S.Snap.Tar.split.ok(ok, pr, s0) == Some{S.BB{p, s}} : Maybe<&2, S.Snap.BB>}
  for +hq: {S.Snap.app(List.reverse(&2, U32, pr), Con{47, s0}) == k : List<&2, U32>}
  for +hasc: {S.Snap.is_ascii(k) == True{} : Bool}
  {k == S.Snap.Tar.join(S.Snap.Tar.cut_nul(rt.F(155n, p)), S.Snap.Tar.cut_nul(rt.F(100n, s))) : List<&2, U32>}

def rt.split_ok(ok, pr, s0, p, s, k, hok, hc, hq, hasc):
  match ok:
    case False{}:
      Empty.absurd({k == S.Snap.Tar.join(S.Snap.Tar.cut_nul(rt.F(155n, p)), S.Snap.Tar.cut_nul(rt.F(100n, s))) : List<&2, U32>}, (%hc : rt.bbdisc(_); Unit{}))
    case True{}:
      match pr:
        case Nil{}:
          rt.ft({k == S.Snap.Tar.join(S.Snap.Tar.cut_nul(rt.F(155n, p)), S.Snap.Tar.cut_nul(rt.F(100n, s))) : List<&2, U32>}, hok)
        case Con{+a, +b}:
          %Equal.cong(Maybe<&2, S.Snap.BB>, List<&2, U32>, rt.bfst, Some{S.BB{List.reverse.go(&2, U32, b, [a]), s0}}, Some{S.BB{p, s}}, hc) : {k == S.Snap.Tar.join(S.Snap.Tar.cut_nul(rt.F(155n, _)), S.Snap.Tar.cut_nul(rt.F(100n, s))) : List<&2, U32>}
          %Equal.cong(Maybe<&2, S.Snap.BB>, List<&2, U32>, rt.bsnd, Some{S.BB{List.reverse.go(&2, U32, b, [a]), s0}}, Some{S.BB{p, s}}, hc) : {k == S.Snap.Tar.join(S.Snap.Tar.cut_nul(rt.F(155n, List.reverse.go(&2, U32, b, [a]))), S.Snap.Tar.cut_nul(rt.F(100n, _))) : List<&2, U32>}
          %rt.cnf(155n, List.reverse.go(&2, U32, b, [a]),
            (%rt.len_rev(Con{a, b}) : {Nat.is_le(_, 155n) == True{} : Bool}; rt.and_r(Bool.and(Nat.is_gt(List.length(&2, U32, s0), 0n), Nat.is_le(List.length(&2, U32, s0), 100n)), Nat.is_le(List.length(&2, U32, Con{a, b}), 155n), hok)),
            rt.ascii_nonul(List.reverse.go(&2, U32, b, [a]), rt.asc_l(List.reverse.go(&2, U32, b, [a]), Con{47, s0}, rt.asc_tr(S.Snap.app(List.reverse.go(&2, U32, b, [a]), Con{47, s0}), k, hq, hasc)))) : {k == S.Snap.Tar.join(_, S.Snap.Tar.cut_nul(rt.F(100n, s0))) : List<&2, U32>}
          %rt.cnf(100n, s0,
            rt.and_r(Nat.is_gt(List.length(&2, U32, s0), 0n), Nat.is_le(List.length(&2, U32, s0), 100n), rt.and_l(Bool.and(Nat.is_gt(List.length(&2, U32, s0), 0n), Nat.is_le(List.length(&2, U32, s0), 100n)), Nat.is_le(List.length(&2, U32, Con{a, b}), 155n), hok)),
            rt.ascii_nonul(s0, rt.asc_r(List.reverse.go(&2, U32, b, [a]), Con{47, s0}, rt.asc_tr(S.Snap.app(List.reverse.go(&2, U32, b, [a]), Con{47, s0}), k, hq, hasc)))) : {k == S.Snap.Tar.join(List.reverse.go(&2, U32, b, [a]), _) : List<&2, U32>}
          %rt.rg_ne32(b, a, Nil{}) : {k == S.Snap.Tar.join.if(_, List.reverse.go(&2, U32, b, [a]), s0) : List<&2, U32>}
          Equal.sym(List<&2, U32>, S.Snap.app(List.reverse.go(&2, U32, b, [a]), Con{47, s0}), k, hq)

law rt.split_inv:
  for cut: Maybe<&2, S.Snap.BB>
  for +k: List<&2, U32>
  for +p: List<&2, U32>
  for +s: List<&2, U32>
  for hq: rt.Q(k, cut)
  for +hc: {S.Snap.Tar.split.check(cut) == Some{S.BB{p, s}} : Maybe<&2, S.Snap.BB>}
  for +hasc: {S.Snap.is_ascii(k) == True{} : Bool}
  {k == S.Snap.Tar.join(S.Snap.Tar.cut_nul(rt.F(155n, p)), S.Snap.Tar.cut_nul(rt.F(100n, s))) : List<&2, U32>}

def rt.split_inv(cut, k, p, s, hq, hc, hasc):
  match cut:
    case None{}:
      Empty.absurd({k == S.Snap.Tar.join(S.Snap.Tar.cut_nul(rt.F(155n, p)), S.Snap.Tar.cut_nul(rt.F(100n, s))) : List<&2, U32>}, (%hc : rt.bbdisc(_); Unit{}))
    case Some{bb}:
      match bb:
        case S.BB{+pr, +s0}:
          rt.split_ok(Nat.is_gt(List.length(&2, U32, pr), 0n) && Nat.is_gt(List.length(&2, U32, s0), 0n) && Nat.is_le(List.length(&2, U32, s0), 100n) && Nat.is_le(List.length(&2, U32, pr), 155n), pr, s0, p, s, k, {==}, hc, hq, hasc)

law rt.split_name:
  for +k: List<&2, U32>
  for +p: List<&2, U32>
  for +s: List<&2, U32>
  for +hc: {S.Snap.Tar.split(k) == Some{S.BB{p, s}} : Maybe<&2, S.Snap.BB>}
  for +hasc: {S.Snap.is_ascii(k) == True{} : Bool}
  {k == S.Snap.Tar.join(S.Snap.Tar.cut_nul(rt.F(155n, p)), S.Snap.Tar.cut_nul(rt.F(100n, s))) : List<&2, U32>}

def rt.split_name(k, p, s, hc, hasc):
  rt.split_inv(S.Snap.Tar.split.go(k, Nil{}, 0n, S.Snap.Tar.split.lim(List.length(&2, U32, k), k), None{}), k, p, s,
    rt.sg(k, Nil{}, 0n, S.Snap.Tar.split.lim(List.length(&2, U32, k), k), None{}, k, Unit{}, {==}), hc, hasc)

# Entries
# -------

law rt.ent_short:
  for +k: List<&2, U32>
  for +v: List<&2, U32>
  for +hsh: {Nat.is_le(List.length(&2, U32, k), 100n) == True{} : Bool}
  for +hasc: {S.Snap.is_ascii(k) == True{} : Bool}
  for +hs: {Nat.is_le(List.length(&2, S.Snap.Oct, S.Snap.Oct.count(v)), 11n) == True{} : Bool}
  for +rest: List<&2, U32>
  {S.Snap.Tar.emit.rec(S.Rec{k, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(S.Snap.app(S.Snap.app(S.Snap.Tar.ustar(k, Nil{}, S.Snap.Oct.count(v)), S.Snap.Tar.data(v, 512n)), rest), S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

def rt.ent_short(k, v, hsh, hasc, hs, rest):
  %rt.app_assoc(S.Snap.Tar.ustar(k, Nil{}, S.Snap.Oct.count(v)), S.Snap.Tar.data(v, 512n), rest) : {S.Snap.Tar.emit.rec(S.Rec{k, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(_, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
  rt.file_entry(k, Nil{}, v, hs, None{}, k, rt.cnf(100n, k, hsh, rt.ascii_nonul(k, hasc)), rest)

law rt.ent_nsplit:
  for +k: List<&2, U32>
  for +p: List<&2, U32>
  for +s: List<&2, U32>
  for +v: List<&2, U32>
  for +hc: {S.Snap.Tar.split(k) == Some{S.BB{p, s}} : Maybe<&2, S.Snap.BB>}
  for +hasc: {S.Snap.is_ascii(k) == True{} : Bool}
  for +hs: {Nat.is_le(List.length(&2, S.Snap.Oct, S.Snap.Oct.count(v)), 11n) == True{} : Bool}
  for +rest: List<&2, U32>
  {S.Snap.Tar.emit.rec(S.Rec{k, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(S.Snap.app(S.Snap.app(S.Snap.Tar.ustar(s, p, S.Snap.Oct.count(v)), S.Snap.Tar.data(v, 512n)), rest), S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

def rt.ent_nsplit(k, p, s, v, hc, hasc, hs, rest):
  %rt.app_assoc(S.Snap.Tar.ustar(s, p, S.Snap.Oct.count(v)), S.Snap.Tar.data(v, 512n), rest) : {S.Snap.Tar.emit.rec(S.Rec{k, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(_, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
  rt.file_entry(s, p, v, hs, None{}, k, rt.split_name(k, p, s, hc, hasc), rest)

law rt.ent_pax_main:
  for +c: U32
  for +t: List<&2, U32>
  for +n: Nat
  for +v: List<&2, U32>
  for +hfix: {Nat.is_eq(Nat.add(List.length(&2, U32, S.Snap.Dec.itoa(n)), Nat.add(7n, List.length(&2, U32, Con{c, t}))), n) == True{} : Bool}
  for +hk: {False{} == S.Snap.has_nul(Con{c, t}) : Bool}
  for +hsr: {Nat.is_le(List.length(&2, S.Snap.Oct, S.Snap.Oct.count(rt.REC(n, Con{c, t}))), 11n) == True{} : Bool}
  for +hs: {Nat.is_le(List.length(&2, S.Snap.Oct, S.Snap.Oct.count(v)), 11n) == True{} : Bool}
  for +rest: List<&2, U32>
  {S.Snap.Tar.emit.rec(S.Rec{Con{c, t}, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(S.Snap.app(S.Snap.Tar.pax(Con{c, t}, rt.REC(n, Con{c, t}), v), rest), S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

def rt.ent_pax_main(c, t, n, v, hfix, hk, hsr, hs, rest):
  %rt.app_assoc(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(Con{c, t}), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(rt.REC(n, Con{c, t}))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(rt.REC(n, Con{c, t}), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(Con{c, t}), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(v)), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(v, 512n))), rest) : {S.Snap.Tar.emit.rec(S.Rec{Con{c, t}, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(_, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
  %rt.app_assoc(S.Snap.Tar.data(rt.REC(n, Con{c, t}), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(Con{c, t}), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(v)), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(v, 512n)), rest) : {S.Snap.Tar.emit.rec(S.Rec{Con{c, t}, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(Con{c, t}), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(rt.REC(n, Con{c, t}))), 120, S.Snap.zeros(8n), Nil{}), _), S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
  %rt.app_assoc(S.Snap.Tar.block(S.Snap.Tar.pax_name(Con{c, t}), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(v)), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(v, 512n), rest) : {S.Snap.Tar.emit.rec(S.Rec{Con{c, t}, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(Con{c, t}), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(rt.REC(n, Con{c, t}))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(rt.REC(n, Con{c, t}), 512n), _)), S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
  %rt.phd(S.Snap.Tar.pax_hdr_name(Con{c, t}), rt.REC(n, Con{c, t}), hsr, S.Pend{Some{Con{c, t}}, None{}, Nil{}}, rt.px_full(n, c, t, hfix, hk), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(Con{c, t}), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(v)), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.app(S.Snap.Tar.data(v, 512n), rest))) : {S.Snap.Tar.emit.rec(S.Rec{Con{c, t}, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == _ : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
  rt.file_entry(S.Snap.Tar.pax_name(Con{c, t}), Nil{}, v, hs, Some{Con{c, t}}, Con{c, t}, {==}, rest)

law rt.ent_pax_fits:
  for +fits: Bool
  for +c: U32
  for +t: List<&2, U32>
  for +n: Nat
  for +v: List<&2, U32>
  for +hf: {Nat.is_le(List.length(&2, S.Snap.Oct, S.Snap.Oct.count(rt.REC(n, Con{c, t}))), 11n) == fits : Bool}
  for +hfix: {Nat.is_eq(Nat.add(List.length(&2, U32, S.Snap.Dec.itoa(n)), Nat.add(7n, List.length(&2, U32, Con{c, t}))), n) == True{} : Bool}
  for +hk: {False{} == S.Snap.has_nul(Con{c, t}) : Bool}
  for +hs: {Nat.is_le(List.length(&2, S.Snap.Oct, S.Snap.Oct.count(v)), 11n) == True{} : Bool}
  for +e: List<&2, U32>
  for +he: {S.Snap.Tar.entry.pax.fits(fits, Con{c, t}, rt.REC(n, Con{c, t}), v) == Done{e} : Result<&2, &2, String, List<&2, U32>>}
  for +rest: List<&2, U32>
  {S.Snap.Tar.emit.rec(S.Rec{Con{c, t}, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(S.Snap.app(e, rest), S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

def rt.ent_pax_fits(fits, c, t, n, v, hf, hfix, hk, hs, e, he, rest):
  match fits:
    case False{}:
      rt.fd({S.Snap.Tar.emit.rec(S.Rec{Con{c, t}, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(S.Snap.app(e, rest), S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}, "archive/tar: header field too long", e, he)
    case True{}:
      %rt.done_inj(S.Snap.Tar.pax(Con{c, t}, rt.REC(n, Con{c, t}), v), e, he) : {S.Snap.Tar.emit.rec(S.Rec{Con{c, t}, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(S.Snap.app(_, rest), S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
      rt.ent_pax_main(c, t, n, v, hfix, hk, hf, hs, rest)

law rt.ent_pax_if:
  for +ok: Bool
  for +c: U32
  for +t: List<&2, U32>
  for +n: Nat
  for +v: List<&2, U32>
  for +hok: {Nat.is_eq(Nat.add(List.length(&2, U32, S.Snap.Dec.itoa(n)), Nat.add(7n, List.length(&2, U32, Con{c, t}))), n) == ok : Bool}
  for +hk: {False{} == S.Snap.has_nul(Con{c, t}) : Bool}
  for +hs: {Nat.is_le(List.length(&2, S.Snap.Oct, S.Snap.Oct.count(v)), 11n) == True{} : Bool}
  for +e: List<&2, U32>
  for +he: {S.Snap.Tar.entry.pax(S.Snap.Tar.pax_rec.if(ok, n, Con{c, t}), Con{c, t}, v) == Done{e} : Result<&2, &2, String, List<&2, U32>>}
  for +rest: List<&2, U32>
  {S.Snap.Tar.emit.rec(S.Rec{Con{c, t}, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(S.Snap.app(e, rest), S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

def rt.ent_pax_if(ok, c, t, n, v, hok, hk, hs, e, he, rest):
  match ok:
    case False{}:
      rt.fd({S.Snap.Tar.emit.rec(S.Rec{Con{c, t}, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(S.Snap.app(e, rest), S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}, "archive/tar: header field too long", e, he)
    case True{}:
      rt.ent_pax_fits(S.Snap.Tar.size_fits(S.Snap.Oct.count(rt.REC(n, Con{c, t}))), c, t, n, v, {==}, hok, hk, hs, e, he, rest)

law rt.ent_nul:
  for +nul: Bool
  for +c: U32
  for +t: List<&2, U32>
  for +v: List<&2, U32>
  for +hn: {S.Snap.has_nul(Con{c, t}) == nul : Bool}
  for +hs: {Nat.is_le(List.length(&2, S.Snap.Oct, S.Snap.Oct.count(v)), 11n) == True{} : Bool}
  for +e: List<&2, U32>
  for +he: {S.Snap.Tar.entry.name(S.Snap.Tar.name.nul(nul, Con{c, t}), Con{c, t}, v) == Done{e} : Result<&2, &2, String, List<&2, U32>>}
  for +rest: List<&2, U32>
  {S.Snap.Tar.emit.rec(S.Rec{Con{c, t}, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(S.Snap.app(e, rest), S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

def rt.ent_nul(nul, c, t, v, hn, hs, e, he, rest):
  match nul:
    case True{}:
      rt.fd({S.Snap.Tar.emit.rec(S.Rec{Con{c, t}, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(S.Snap.app(e, rest), S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}, S.Snap.Tar.bad_prefix() ++ "invalid PAX record: " ++ S.Snap.s(S.Snap.Tar.quote(S.Snap.app(S.Snap.b("path = "), Con{c, t}))), e, he)
    case False{}:
      rt.ent_pax_if(S.Snap.Tar.pax_rec.fix(S.Snap.Tar.pax_rec.pick(S.Snap.Tar.pax_rec.fix(Nat.add(List.length(&2, U32, S.Snap.Dec.itoa(Nat.add(7n, List.length(&2, U32, Con{c, t})))), Nat.add(7n, List.length(&2, U32, Con{c, t}))), Nat.add(7n, List.length(&2, U32, Con{c, t}))), Nat.add(List.length(&2, U32, S.Snap.Dec.itoa(Nat.add(7n, List.length(&2, U32, Con{c, t})))), Nat.add(7n, List.length(&2, U32, Con{c, t})))), Nat.add(7n, List.length(&2, U32, Con{c, t}))), c, t, S.Snap.Tar.pax_rec.pick(S.Snap.Tar.pax_rec.fix(Nat.add(List.length(&2, U32, S.Snap.Dec.itoa(Nat.add(7n, List.length(&2, U32, Con{c, t})))), Nat.add(7n, List.length(&2, U32, Con{c, t}))), Nat.add(7n, List.length(&2, U32, Con{c, t}))), Nat.add(List.length(&2, U32, S.Snap.Dec.itoa(Nat.add(7n, List.length(&2, U32, Con{c, t})))), Nat.add(7n, List.length(&2, U32, Con{c, t})))), v, {==}, Equal.sym(Bool, S.Snap.has_nul(Con{c, t}), False{}, hn), hs, e, he, rest)

law rt.ent_split:
  for +cut: Maybe<&2, S.Snap.BB>
  for +c: U32
  for +t: List<&2, U32>
  for +v: List<&2, U32>
  for +hc: {S.Snap.Tar.split(Con{c, t}) == cut : Maybe<&2, S.Snap.BB>}
  for +hasc: {S.Snap.is_ascii(Con{c, t}) == True{} : Bool}
  for +hs: {Nat.is_le(List.length(&2, S.Snap.Oct, S.Snap.Oct.count(v)), 11n) == True{} : Bool}
  for +e: List<&2, U32>
  for +he: {S.Snap.Tar.entry.name(S.Snap.Tar.name.split(cut, Con{c, t}), Con{c, t}, v) == Done{e} : Result<&2, &2, String, List<&2, U32>>}
  for +rest: List<&2, U32>
  {S.Snap.Tar.emit.rec(S.Rec{Con{c, t}, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(S.Snap.app(e, rest), S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

def rt.ent_split(cut, c, t, v, hc, hasc, hs, e, he, rest):
  match cut:
    case None{}:
      rt.ent_nul(S.Snap.has_nul(Con{c, t}), c, t, v, {==}, hs, e, he, rest)
    case Some{bb}:
      match bb:
        case S.BB{+p, +s}:
          %rt.done_inj(S.Snap.app(S.Snap.Tar.ustar(s, p, S.Snap.Oct.count(v)), S.Snap.Tar.data(v, 512n)), e, he) : {S.Snap.Tar.emit.rec(S.Rec{Con{c, t}, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(S.Snap.app(_, rest), S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
          rt.ent_nsplit(Con{c, t}, p, s, v, hc, hasc, hs, rest)

law rt.ent_fits:
  for +k: List<&2, U32>
  for +sh: Bool
  for +asc: Bool
  for +v: List<&2, U32>
  for +hsh: {Nat.is_le(List.length(&2, U32, k), 100n) == sh : Bool}
  for +hasc: {S.Snap.is_ascii(k) == asc : Bool}
  for +hs: {Nat.is_le(List.length(&2, S.Snap.Oct, S.Snap.Oct.count(v)), 11n) == True{} : Bool}
  for +e: List<&2, U32>
  for +he: {S.Snap.Tar.entry.name(S.Snap.Tar.name.fits(sh, asc, k), k, v) == Done{e} : Result<&2, &2, String, List<&2, U32>>}
  for +rest: List<&2, U32>
  {S.Snap.Tar.emit.rec(S.Rec{k, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(S.Snap.app(e, rest), S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

def rt.ent_fits(k, sh, asc, v, hsh, hasc, hs, e, he, rest):
  match k:
    case Nil{}:
      match sh asc:
        case True{} True{}:
          %rt.done_inj(S.Snap.app(S.Snap.Tar.ustar(Nil{}, Nil{}, S.Snap.Oct.count(v)), S.Snap.Tar.data(v, 512n)), e, he) : {S.Snap.Tar.emit.rec(S.Rec{Nil{}, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(S.Snap.app(_, rest), S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
          rt.ent_short(Nil{}, v, hsh, hasc, hs, rest)
        case True{} False{}:
          rt.tf({S.Snap.Tar.emit.rec(S.Rec{Nil{}, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(S.Snap.app(e, rest), S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}, hasc)
        case False{} True{}:
          rt.tf({S.Snap.Tar.emit.rec(S.Rec{Nil{}, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(S.Snap.app(e, rest), S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}, hsh)
        case False{} False{}:
          rt.tf({S.Snap.Tar.emit.rec(S.Rec{Nil{}, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(S.Snap.app(e, rest), S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}, hsh)
    case Con{+c, +t}:
      match sh asc:
        case True{} True{}:
          %rt.done_inj(S.Snap.app(S.Snap.Tar.ustar(Con{c, t}, Nil{}, S.Snap.Oct.count(v)), S.Snap.Tar.data(v, 512n)), e, he) : {S.Snap.Tar.emit.rec(S.Rec{Con{c, t}, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(S.Snap.app(_, rest), S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
          rt.ent_short(Con{c, t}, v, hsh, hasc, hs, rest)
        case True{} False{}:
          rt.ent_nul(S.Snap.has_nul(Con{c, t}), c, t, v, {==}, hs, e, he, rest)
        case False{} True{}:
          rt.ent_split(S.Snap.Tar.split(Con{c, t}), c, t, v, {==}, hasc, hs, e, he, rest)
        case False{} False{}:
          rt.ent_nul(S.Snap.has_nul(Con{c, t}), c, t, v, {==}, hs, e, he, rest)

law rt.ent_slash:
  for +sl: Bool
  for +k: List<&2, U32>
  for +v: List<&2, U32>
  for +hs: {Nat.is_le(List.length(&2, S.Snap.Oct, S.Snap.Oct.count(v)), 11n) == True{} : Bool}
  for +e: List<&2, U32>
  for +he: {S.Snap.Tar.entry.name(S.Snap.Tar.name.slash(sl, k), k, v) == Done{e} : Result<&2, &2, String, List<&2, U32>>}
  for +rest: List<&2, U32>
  {S.Snap.Tar.emit.rec(S.Rec{k, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(S.Snap.app(e, rest), S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

def rt.ent_slash(sl, k, v, hs, e, he, rest):
  match sl:
    case True{}:
      rt.fd({S.Snap.Tar.emit.rec(S.Rec{k, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(S.Snap.app(e, rest), S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}, S.Snap.Tar.bad_prefix() ++ "filename may not have trailing slash", e, he)
    case False{}:
      rt.ent_fits(k, Nat.is_le(List.length(&2, U32, k), 100n), S.Snap.is_ascii(k), v, {==}, {==}, hs, e, he, rest)

law rt.ent_size:
  for +fits: Bool
  for +k: List<&2, U32>
  for +v: List<&2, U32>
  for +hf: {Nat.is_le(List.length(&2, S.Snap.Oct, S.Snap.Oct.count(v)), 11n) == fits : Bool}
  for +e: List<&2, U32>
  for +he: {S.Snap.Tar.entry.size(fits, k, v) == Done{e} : Result<&2, &2, String, List<&2, U32>>}
  for +rest: List<&2, U32>
  {S.Snap.Tar.emit.rec(S.Rec{k, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(S.Snap.app(e, rest), S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

def rt.ent_size(fits, k, v, hf, e, he, rest):
  match fits:
    case False{}:
      rt.fd({S.Snap.Tar.emit.rec(S.Rec{k, v}, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(S.Snap.app(e, rest), S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}, "archive/tar: header field too long", e, he)
    case True{}:
      rt.ent_slash(S.Snap.ends_slash(k), k, v, hf, e, he, rest)

law rt.ent:
  for +r: S.Snap.Rec
  for +e: List<&2, U32>
  for +he: {S.Snap.Tar.entry(r) == Done{e} : Result<&2, &2, String, List<&2, U32>>}
  for +rest: List<&2, U32>
  {S.Snap.Tar.emit.rec(r, S.Snap.Tar.go(rest, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{})) == S.Snap.Tar.go(S.Snap.app(e, rest), S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

def rt.ent(r, e, he, rest):
  match r:
    case S.Rec{+k, +v}:
      rt.ent_size(Nat.is_le(List.length(&2, S.Snap.Oct, S.Snap.Oct.count(v)), 11n), k, v, {==}, e, he, rest)

# The trailer
# -----------

law rt.zeros_add:
  for +a: Nat
  for +b: Nat
  {S.Snap.app(S.Snap.zeros(a), S.Snap.zeros(b)) == S.Snap.zeros(Nat.add(a, b)) : List<&2, U32>}

def rt.zeros_add(a, b):
  match a:
    case 0n:
      {==}
    case 1n+p:
      %rt.zeros_add(p, b) : {Con{0, S.Snap.app(S.Snap.zeros(p), S.Snap.zeros(b))} == Con{0, _} : List<&2, U32>}
      {==}

law rt.len_zeros0:
  for +n: Nat
  {n == List.length(&2, U32, S.Snap.zeros(n)) : Nat}

def rt.len_zeros0(n):
  match n:
    case 0n:
      {==}
    case 1n+p:
      %rt.len_zeros0(p) : {1n+p == 1n+_ : Nat}
      {==}

law rt.allz:
  for +n: Nat
  {True{} == S.Snap.Tar.all_zero(S.Snap.zeros(n)) : Bool}

def rt.allz(n):
  match n:
    case 0n:
      {==}
    case 1n+p:
      %rt.allz(p) : {True{} == Bool.and(U32.is_eq(0, 0), _) : Bool}
      {==}

law rt.zr:
  for +j: Nat
  for +lim: Maybe<&2, Nat>
  {S.Snap.Tar.go(S.Snap.zeros(1n+j), S.SZero{1n+j, True{}}, lim) == Done{Nil{}} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

def rt.zr(j, lim):
  match j:
    case 0n:
      {==}
    case 1n+i:
      rt.zr(i, lim)

law rt.trailer:
  {S.Snap.Tar.go(S.Snap.Tar.trailer(), S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) == Done{Nil{}} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

def rt.trailer():
  %rt.zeros_add(512n, 512n) : {S.Snap.Tar.go(_, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) == Done{Nil{}} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
  %rt.hread(S.Snap.zeros(512n), 511n, Equal.sym(Nat, 512n, List.length(&2, U32, S.Snap.zeros(512n)), rt.len_zeros0(512n)), Nil{}, S.Snap.Tar.pend0(), None{}, S.Snap.zeros(512n)) : {_ == Done{Nil{}} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
  %rt.rr(S.Snap.zeros(512n)) : {rt.g(S.Snap.Tar.on_block(_, S.Snap.Tar.pend0(), None{}), S.Snap.zeros(512n)) == Done{Nil{}} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
  %rt.allz(512n) : {rt.g(S.Snap.Tar.on_block.if(_, S.Snap.zeros(512n), S.Snap.Tar.pend0(), None{}), S.Snap.zeros(512n)) == Done{Nil{}} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
  rt.zr(511n, None{})

# Records
# -------

law rt.enc_step:
  for +er: Result<&2, &2, String, List<&2, U32>>
  for +tr: Result<&2, &2, String, List<&2, U32>>
  for +r: S.Snap.Rec
  for +t: List<&2, S.Snap.Rec>
  for +her: {S.Snap.Tar.entry(r) == er : Result<&2, &2, String, List<&2, U32>>}
  for +htr: {S.Snap.Tar.encode.go(t) == tr : Result<&2, &2, String, List<&2, U32>>}
  for +bs: List<&2, U32>
  for +h: {S.Snap.Tar.encode.step(er, tr) == Done{bs} : Result<&2, &2, String, List<&2, U32>>}
  for ih: @bt: List<&2, U32> -> {S.Snap.Tar.encode.go(t) == Done{bt} : Result<&2, &2, String, List<&2, U32>>} -> {S.Snap.Tar.go(bt, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) == Done{t} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
  {S.Snap.Tar.go(bs, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) == Done{Con{r, t}} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

def rt.enc_step(er, tr, r, t, her, htr, bs, h, ih):
  match er tr:
    case Fail{m} _:
      rt.fd({S.Snap.Tar.go(bs, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) == Done{Con{r, t}} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}, m, bs, h)
    case Done{e} Fail{m}:
      rt.fd({S.Snap.Tar.go(bs, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) == Done{Con{r, t}} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}, m, bs, h)
    case Done{+e} Done{+bt}:
      %rt.done_inj(S.Snap.app(e, bt), bs, h) : {S.Snap.Tar.go(_, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) == Done{Con{r, t}} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
      %rt.ent(r, e, her, bt) : {_ == Done{Con{r, t}} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
      %Equal.sym(Result<&2, &2, String, List<&2, S.Snap.Rec>>, S.Snap.Tar.go(bt, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}), Done{t}, ih(bt, htr)) : {S.Snap.Tar.emit.rec(r, _) == Done{Con{r, t}} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
      {==}

law rt.enc:
  for +rs: List<&2, S.Snap.Rec>
  for +bs: List<&2, U32>
  for +h: {S.Snap.Tar.encode.go(rs) == Done{bs} : Result<&2, &2, String, List<&2, U32>>}
  {S.Snap.Tar.go(bs, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) == Done{rs} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

def rt.enc(rs, bs, h):
  match rs:
    case Nil{}:
      %rt.done_inj(S.Snap.Tar.trailer(), bs, h) : {S.Snap.Tar.go(_, S.Snap.Tar.hdr0(S.Snap.Tar.pend0()), None{}) == Done{Nil{}} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
      rt.trailer()
    case Con{+r, +t}:
      rt.enc_step(S.Snap.Tar.entry(r), S.Snap.Tar.encode.go(t), r, t, {==}, {==}, bs, h, bt => ht => rt.enc(t, bt, ht))

def L.snapshot.tar.roundtrip(rs, bs, h):
  rt.enc(rs, bs, h)

# The PAX vectors, in parts
# =========================
#
# snapshot.tar.pax and snapshot.tar.non_ascii encode three header blocks,
# a data block and the trailer. Evaluated in one step they exceed the
# verdict kernel's fuel, so their proofs take each block's hex digits as
# a lemma of its own (the parts of the laws' expected strings) and put
# them together with the facts below.

law rt.fxhex:
  for +bs: List<&2, U32>
  {Nat.show(List.length(&2, U32, bs)) ++ " " ++ H.Sha256.hex(L.snapshot.fx.nz(bs)) == L.snapshot.fx.hex(Done{bs}) : String}

def rt.fxhex(bs):
  {==}

law rt.ne_app:
  for a: List<&2, U32>
  for +y: List<&2, U32>
  for +h: {False{} == List.is_empty(&2, U32, y) : Bool}
  {False{} == List.is_empty(&2, U32, S.Snap.app(a, y)) : Bool}

def rt.ne_app(a, y, h):
  match a:
    case Nil{}:
      h
    case Con{c, t}:
      {==}

law rt.nz_app:
  for a: List<&2, U32>
  for +b: List<&2, U32>
  for +h: {False{} == List.is_empty(&2, U32, L.snapshot.fx.nz(b)) : Bool}
  {S.Snap.app(a, L.snapshot.fx.nz(b)) == L.snapshot.fx.nz(S.Snap.app(a, b)) : List<&2, U32>}

def rt.nz_app(a, b, h):
  match a:
    case Nil{}:
      {==}
    case Con{+c, +t}:
      %rt.nz_app(t, b, h) : {Con{c, S.Snap.app(t, L.snapshot.fx.nz(b))} == L.snapshot.fx.nz.put(c, _) : List<&2, U32>}
      %rt.ne_app(t, L.snapshot.fx.nz(b), h) : {Con{c, S.Snap.app(t, L.snapshot.fx.nz(b))} == L.snapshot.fx.nz.if(Bool.and(_, U32.is_eq(c, 0)), c, S.Snap.app(t, L.snapshot.fx.nz(b))) : List<&2, U32>}
      {==}

law rt.hex_app:
  for a: List<&2, U32>
  for +b: List<&2, U32>
  {String.append(H.Sha256.hex(a), H.Sha256.hex(b)) == H.Sha256.hex(S.Snap.app(a, b)) : String}

def rt.hex_app(a, b):
  match a:
    case Nil{}:
      {==}
    case Con{+x, +t}:
      %rt.hex_app(t, b) : {SCon{H.Sha256.digit(U32.and(U32.shrn(x, 4n), 15)), SCon{H.Sha256.digit(U32.and(x, 15)), String.append(H.Sha256.hex(t), H.Sha256.hex(b))}} == SCon{H.Sha256.digit(U32.and(U32.shrn(x, 4n), 15)), SCon{H.Sha256.digit(U32.and(x, 15)), _}} : String}
      {==}

law rt.paxv.ent:
  {Done{S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n))))} == S.Snap.Tar.entry(L.snapshot.fx.rec("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc", "v")) : Result<&2, &2, String, List<&2, U32>>}

def rt.paxv.ent():
  {==}

law rt.paxv.enc:
  {Done{S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer())} == S.Snap.Tar.encode([L.snapshot.fx.rec("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc", "v")]) : Result<&2, &2, String, List<&2, U32>>}

def rt.paxv.enc():
  %rt.paxv.ent() : {Done{S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer())} == S.Snap.Tar.encode.step(_, Done{S.Snap.Tar.trailer()}) : Result<&2, &2, String, List<&2, U32>>}
  {==}

law rt.paxv.len:
  {3072n == List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer())) : Nat}

def rt.paxv.len():
  {==}

law rt.paxv.nzv:
  {[118] == L.snapshot.fx.nz(S.Snap.app(S.Snap.Tar.data(S.Snap.b("v"), 512n), S.Snap.Tar.trailer())) : List<&2, U32>}

def rt.paxv.nzv():
  {==}

law rt.paxv.h1:
  {"2f72656769737472792f636f6e6669676d6170732f64656661756c742f506178486561646572732e302f6363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636330303030303030003030303030303000303030303030300030303030303030303233370030303030303030303030300030333131303400207800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" == H.Sha256.hex(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{})) : String}

def rt.paxv.h1():
  {==}

law rt.paxv.h2:
  {"31353920706174683d2f72656769737472792f636f6e6669676d6170732f64656661756c742f6363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363630a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" == H.Sha256.hex(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n)) : String}

def rt.paxv.h2():
  {==}

law rt.paxv.h3:
  {"2f72656769737472792f636f6e6669676d6170732f64656661756c742f636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636330303030363636003030303030303000303030303030300030303030303030303030310030303030303030303030300030333234373000203000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000303030303030300030303030303030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" == H.Sha256.hex(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{})) : String}

def rt.paxv.h3():
  {==}

def L.snapshot.tar.pax():
  %rt.paxv.enc() : {L.snapshot.fx.hex(_) == "3072 2f72656769737472792f636f6e6669676d6170732f64656661756c742f506178486561646572732e302f636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303030303000303030303030300030303030303030003030303030303030323337003030303030303030303030003033313130340020780000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000031353920706174683d2f72656769737472792f636f6e6669676d6170732f64656661756c742f6363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363630a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f72656769737472792f636f6e6669676d6170732f64656661756c742f63636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003033323437300020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.fxhex(S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer())) : {_ == "3072 2f72656769737472792f636f6e6669676d6170732f64656661756c742f506178486561646572732e302f636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303030303000303030303030300030303030303030003030303030303030323337003030303030303030303030003033313130340020780000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000031353920706174683d2f72656769737472792f636f6e6669676d6170732f64656661756c742f6363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363630a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f72656769737472792f636f6e6669676d6170732f64656661756c742f63636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003033323437300020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.app_assoc(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n))), S.Snap.Tar.trailer()) : {Nat.show(List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer()))) ++ " " ++ H.Sha256.hex(L.snapshot.fx.nz(_)) == "3072 2f72656769737472792f636f6e6669676d6170732f64656661756c742f506178486561646572732e302f636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303030303000303030303030300030303030303030003030303030303030323337003030303030303030303030003033313130340020780000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000031353920706174683d2f72656769737472792f636f6e6669676d6170732f64656661756c742f6363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363630a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f72656769737472792f636f6e6669676d6170732f64656661756c742f63636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003033323437300020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.app_assoc(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)), S.Snap.Tar.trailer()) : {Nat.show(List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer()))) ++ " " ++ H.Sha256.hex(L.snapshot.fx.nz(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), _))) == "3072 2f72656769737472792f636f6e6669676d6170732f64656661756c742f506178486561646572732e302f636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303030303000303030303030300030303030303030003030303030303030323337003030303030303030303030003033313130340020780000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000031353920706174683d2f72656769737472792f636f6e6669676d6170732f64656661756c742f6363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363630a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f72656769737472792f636f6e6669676d6170732f64656661756c742f63636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003033323437300020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.app_assoc(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n), S.Snap.Tar.trailer()) : {Nat.show(List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer()))) ++ " " ++ H.Sha256.hex(L.snapshot.fx.nz(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), _)))) == "3072 2f72656769737472792f636f6e6669676d6170732f64656661756c742f506178486561646572732e302f636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303030303000303030303030300030303030303030003030303030303030323337003030303030303030303030003033313130340020780000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000031353920706174683d2f72656769737472792f636f6e6669676d6170732f64656661756c742f6363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363630a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f72656769737472792f636f6e6669676d6170732f64656661756c742f63636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003033323437300020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.nz_app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.b("v"), 512n), S.Snap.Tar.trailer()))), (%rt.nz_app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.b("v"), 512n), S.Snap.Tar.trailer())), (%rt.nz_app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.b("v"), 512n), S.Snap.Tar.trailer()), (%rt.paxv.nzv : {False{} == List.is_empty(&2, U32, _) : Bool}; {==})) : {False{} == List.is_empty(&2, U32, _) : Bool}; rt.ne_app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), L.snapshot.fx.nz(S.Snap.app(S.Snap.Tar.data(S.Snap.b("v"), 512n), S.Snap.Tar.trailer())), (%rt.paxv.nzv : {False{} == List.is_empty(&2, U32, _) : Bool}; {==})))) : {False{} == List.is_empty(&2, U32, _) : Bool}; rt.ne_app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), L.snapshot.fx.nz(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.b("v"), 512n), S.Snap.Tar.trailer()))), (%rt.nz_app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.b("v"), 512n), S.Snap.Tar.trailer()), (%rt.paxv.nzv : {False{} == List.is_empty(&2, U32, _) : Bool}; {==})) : {False{} == List.is_empty(&2, U32, _) : Bool}; rt.ne_app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), L.snapshot.fx.nz(S.Snap.app(S.Snap.Tar.data(S.Snap.b("v"), 512n), S.Snap.Tar.trailer())), (%rt.paxv.nzv : {False{} == List.is_empty(&2, U32, _) : Bool}; {==})))))) : {Nat.show(List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer()))) ++ " " ++ H.Sha256.hex(_) == "3072 2f72656769737472792f636f6e6669676d6170732f64656661756c742f506178486561646572732e302f636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303030303000303030303030300030303030303030003030303030303030323337003030303030303030303030003033313130340020780000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000031353920706174683d2f72656769737472792f636f6e6669676d6170732f64656661756c742f6363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363630a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f72656769737472792f636f6e6669676d6170732f64656661756c742f63636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003033323437300020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.nz_app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.b("v"), 512n), S.Snap.Tar.trailer())), (%rt.nz_app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.b("v"), 512n), S.Snap.Tar.trailer()), (%rt.paxv.nzv : {False{} == List.is_empty(&2, U32, _) : Bool}; {==})) : {False{} == List.is_empty(&2, U32, _) : Bool}; rt.ne_app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), L.snapshot.fx.nz(S.Snap.app(S.Snap.Tar.data(S.Snap.b("v"), 512n), S.Snap.Tar.trailer())), (%rt.paxv.nzv : {False{} == List.is_empty(&2, U32, _) : Bool}; {==})))) : {Nat.show(List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer()))) ++ " " ++ H.Sha256.hex(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), _)) == "3072 2f72656769737472792f636f6e6669676d6170732f64656661756c742f506178486561646572732e302f636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303030303000303030303030300030303030303030003030303030303030323337003030303030303030303030003033313130340020780000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000031353920706174683d2f72656769737472792f636f6e6669676d6170732f64656661756c742f6363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363630a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f72656769737472792f636f6e6669676d6170732f64656661756c742f63636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003033323437300020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.nz_app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.b("v"), 512n), S.Snap.Tar.trailer()), (%rt.paxv.nzv : {False{} == List.is_empty(&2, U32, _) : Bool}; {==})) : {Nat.show(List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer()))) ++ " " ++ H.Sha256.hex(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), _))) == "3072 2f72656769737472792f636f6e6669676d6170732f64656661756c742f506178486561646572732e302f636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303030303000303030303030300030303030303030003030303030303030323337003030303030303030303030003033313130340020780000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000031353920706174683d2f72656769737472792f636f6e6669676d6170732f64656661756c742f6363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363630a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f72656769737472792f636f6e6669676d6170732f64656661756c742f63636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003033323437300020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.paxv.nzv() : {Nat.show(List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer()))) ++ " " ++ H.Sha256.hex(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), _)))) == "3072 2f72656769737472792f636f6e6669676d6170732f64656661756c742f506178486561646572732e302f636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303030303000303030303030300030303030303030003030303030303030323337003030303030303030303030003033313130340020780000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000031353920706174683d2f72656769737472792f636f6e6669676d6170732f64656661756c742f6363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363630a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f72656769737472792f636f6e6669676d6170732f64656661756c742f63636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003033323437300020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.hex_app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), [118]))) : {Nat.show(List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer()))) ++ " " ++ _ == "3072 2f72656769737472792f636f6e6669676d6170732f64656661756c742f506178486561646572732e302f636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303030303000303030303030300030303030303030003030303030303030323337003030303030303030303030003033313130340020780000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000031353920706174683d2f72656769737472792f636f6e6669676d6170732f64656661756c742f6363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363630a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f72656769737472792f636f6e6669676d6170732f64656661756c742f63636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003033323437300020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.hex_app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), [118])) : {Nat.show(List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer()))) ++ " " ++ String.append(H.Sha256.hex(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{})), _) == "3072 2f72656769737472792f636f6e6669676d6170732f64656661756c742f506178486561646572732e302f636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303030303000303030303030300030303030303030003030303030303030323337003030303030303030303030003033313130340020780000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000031353920706174683d2f72656769737472792f636f6e6669676d6170732f64656661756c742f6363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363630a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f72656769737472792f636f6e6669676d6170732f64656661756c742f63636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003033323437300020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.hex_app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), [118]) : {Nat.show(List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer()))) ++ " " ++ String.append(H.Sha256.hex(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{})), String.append(H.Sha256.hex(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n)), _)) == "3072 2f72656769737472792f636f6e6669676d6170732f64656661756c742f506178486561646572732e302f636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303030303000303030303030300030303030303030003030303030303030323337003030303030303030303030003033313130340020780000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000031353920706174683d2f72656769737472792f636f6e6669676d6170732f64656661756c742f6363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363630a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f72656769737472792f636f6e6669676d6170732f64656661756c742f63636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003033323437300020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.paxv.h1() : {Nat.show(List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer()))) ++ " " ++ String.append(_, String.append(H.Sha256.hex(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n)), String.append(H.Sha256.hex(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{})), H.Sha256.hex([118])))) == "3072 2f72656769737472792f636f6e6669676d6170732f64656661756c742f506178486561646572732e302f636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303030303000303030303030300030303030303030003030303030303030323337003030303030303030303030003033313130340020780000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000031353920706174683d2f72656769737472792f636f6e6669676d6170732f64656661756c742f6363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363630a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f72656769737472792f636f6e6669676d6170732f64656661756c742f63636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003033323437300020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.paxv.h2() : {Nat.show(List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer()))) ++ " " ++ String.append("2f72656769737472792f636f6e6669676d6170732f64656661756c742f506178486561646572732e302f6363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636330303030303030003030303030303000303030303030300030303030303030303233370030303030303030303030300030333131303400207800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", String.append(_, String.append(H.Sha256.hex(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{})), H.Sha256.hex([118])))) == "3072 2f72656769737472792f636f6e6669676d6170732f64656661756c742f506178486561646572732e302f636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303030303000303030303030300030303030303030003030303030303030323337003030303030303030303030003033313130340020780000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000031353920706174683d2f72656769737472792f636f6e6669676d6170732f64656661756c742f6363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363630a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f72656769737472792f636f6e6669676d6170732f64656661756c742f63636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003033323437300020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.paxv.h3() : {Nat.show(List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(159n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer()))) ++ " " ++ String.append("2f72656769737472792f636f6e6669676d6170732f64656661756c742f506178486561646572732e302f6363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636330303030303030003030303030303000303030303030300030303030303030303233370030303030303030303030300030333131303400207800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", String.append("31353920706174683d2f72656769737472792f636f6e6669676d6170732f64656661756c742f6363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363630a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", String.append(_, H.Sha256.hex([118])))) == "3072 2f72656769737472792f636f6e6669676d6170732f64656661756c742f506178486561646572732e302f636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303030303000303030303030300030303030303030003030303030303030323337003030303030303030303030003033313130340020780000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000031353920706174683d2f72656769737472792f636f6e6669676d6170732f64656661756c742f6363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363630a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f72656769737472792f636f6e6669676d6170732f64656661756c742f63636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003033323437300020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.paxv.len() : {Nat.show(_) ++ " " ++ String.append("2f72656769737472792f636f6e6669676d6170732f64656661756c742f506178486561646572732e302f6363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636330303030303030003030303030303000303030303030300030303030303030303233370030303030303030303030300030333131303400207800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", String.append("31353920706174683d2f72656769737472792f636f6e6669676d6170732f64656661756c742f6363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363630a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", String.append("2f72656769737472792f636f6e6669676d6170732f64656661756c742f636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636330303030363636003030303030303000303030303030300030303030303030303030310030303030303030303030300030333234373000203000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000303030303030300030303030303030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", H.Sha256.hex([118])))) == "3072 2f72656769737472792f636f6e6669676d6170732f64656661756c742f506178486561646572732e302f636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303030303000303030303030300030303030303030003030303030303030323337003030303030303030303030003033313130340020780000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000031353920706174683d2f72656769737472792f636f6e6669676d6170732f64656661756c742f6363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363630a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f72656769737472792f636f6e6669676d6170732f64656661756c742f63636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003033323437300020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  {==}

law rt.nasc.ent:
  {Done{S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n))))} == S.Snap.Tar.entry(L.snapshot.fx.rec("/é", "v")) : Result<&2, &2, String, List<&2, U32>>}

def rt.nasc.ent():
  {==}

law rt.nasc.enc:
  {Done{S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer())} == S.Snap.Tar.encode([L.snapshot.fx.rec("/é", "v")]) : Result<&2, &2, String, List<&2, U32>>}

def rt.nasc.enc():
  %rt.nasc.ent() : {Done{S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer())} == S.Snap.Tar.encode.step(_, Done{S.Snap.Tar.trailer()}) : Result<&2, &2, String, List<&2, U32>>}
  {==}

law rt.nasc.len:
  {3072n == List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer())) : Nat}

def rt.nasc.len():
  {==}

law rt.nasc.nzv:
  {[118] == L.snapshot.fx.nz(S.Snap.app(S.Snap.Tar.data(S.Snap.b("v"), 512n), S.Snap.Tar.trailer())) : List<&2, U32>}

def rt.nasc.nzv():
  {==}

law rt.nasc.h1:
  {"2f506178486561646572732e3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000303030303030300030303030303030303031340030303030303030303030300030313032313600207800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" == H.Sha256.hex(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{})) : String}

def rt.nasc.h1():
  {==}

law rt.nasc.h2:
  {"313220706174683d2fc3a90a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" == H.Sha256.hex(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n)) : String}

def rt.nasc.h2():
  {==}

law rt.nasc.h3:
  {"2f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030363636003030303030303000303030303030300030303030303030303030310030303030303030303030300030303732363100203000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000303030303030300030303030303030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" == H.Sha256.hex(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{})) : String}

def rt.nasc.h3():
  {==}

def L.snapshot.tar.non_ascii():
  %rt.nasc.enc() : {L.snapshot.fx.hex(_) == "3072 2f506178486561646572732e3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000303030303030300030303030303030303031340030303030303030303030300030313032313600207800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000313220706174683d2fc3a90a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003030373236310020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.fxhex(S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer())) : {_ == "3072 2f506178486561646572732e3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000303030303030300030303030303030303031340030303030303030303030300030313032313600207800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000313220706174683d2fc3a90a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003030373236310020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.app_assoc(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n))), S.Snap.Tar.trailer()) : {Nat.show(List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer()))) ++ " " ++ H.Sha256.hex(L.snapshot.fx.nz(_)) == "3072 2f506178486561646572732e3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000303030303030300030303030303030303031340030303030303030303030300030313032313600207800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000313220706174683d2fc3a90a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003030373236310020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.app_assoc(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)), S.Snap.Tar.trailer()) : {Nat.show(List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer()))) ++ " " ++ H.Sha256.hex(L.snapshot.fx.nz(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), _))) == "3072 2f506178486561646572732e3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000303030303030300030303030303030303031340030303030303030303030300030313032313600207800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000313220706174683d2fc3a90a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003030373236310020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.app_assoc(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n), S.Snap.Tar.trailer()) : {Nat.show(List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer()))) ++ " " ++ H.Sha256.hex(L.snapshot.fx.nz(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), _)))) == "3072 2f506178486561646572732e3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000303030303030300030303030303030303031340030303030303030303030300030313032313600207800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000313220706174683d2fc3a90a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003030373236310020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.nz_app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.b("v"), 512n), S.Snap.Tar.trailer()))), (%rt.nz_app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.b("v"), 512n), S.Snap.Tar.trailer())), (%rt.nz_app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.b("v"), 512n), S.Snap.Tar.trailer()), (%rt.nasc.nzv : {False{} == List.is_empty(&2, U32, _) : Bool}; {==})) : {False{} == List.is_empty(&2, U32, _) : Bool}; rt.ne_app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), L.snapshot.fx.nz(S.Snap.app(S.Snap.Tar.data(S.Snap.b("v"), 512n), S.Snap.Tar.trailer())), (%rt.nasc.nzv : {False{} == List.is_empty(&2, U32, _) : Bool}; {==})))) : {False{} == List.is_empty(&2, U32, _) : Bool}; rt.ne_app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), L.snapshot.fx.nz(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.b("v"), 512n), S.Snap.Tar.trailer()))), (%rt.nz_app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.b("v"), 512n), S.Snap.Tar.trailer()), (%rt.nasc.nzv : {False{} == List.is_empty(&2, U32, _) : Bool}; {==})) : {False{} == List.is_empty(&2, U32, _) : Bool}; rt.ne_app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), L.snapshot.fx.nz(S.Snap.app(S.Snap.Tar.data(S.Snap.b("v"), 512n), S.Snap.Tar.trailer())), (%rt.nasc.nzv : {False{} == List.is_empty(&2, U32, _) : Bool}; {==})))))) : {Nat.show(List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer()))) ++ " " ++ H.Sha256.hex(_) == "3072 2f506178486561646572732e3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000303030303030300030303030303030303031340030303030303030303030300030313032313600207800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000313220706174683d2fc3a90a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003030373236310020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.nz_app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.b("v"), 512n), S.Snap.Tar.trailer())), (%rt.nz_app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.b("v"), 512n), S.Snap.Tar.trailer()), (%rt.nasc.nzv : {False{} == List.is_empty(&2, U32, _) : Bool}; {==})) : {False{} == List.is_empty(&2, U32, _) : Bool}; rt.ne_app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), L.snapshot.fx.nz(S.Snap.app(S.Snap.Tar.data(S.Snap.b("v"), 512n), S.Snap.Tar.trailer())), (%rt.nasc.nzv : {False{} == List.is_empty(&2, U32, _) : Bool}; {==})))) : {Nat.show(List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer()))) ++ " " ++ H.Sha256.hex(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), _)) == "3072 2f506178486561646572732e3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000303030303030300030303030303030303031340030303030303030303030300030313032313600207800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000313220706174683d2fc3a90a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003030373236310020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.nz_app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.b("v"), 512n), S.Snap.Tar.trailer()), (%rt.nasc.nzv : {False{} == List.is_empty(&2, U32, _) : Bool}; {==})) : {Nat.show(List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer()))) ++ " " ++ H.Sha256.hex(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), _))) == "3072 2f506178486561646572732e3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000303030303030300030303030303030303031340030303030303030303030300030313032313600207800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000313220706174683d2fc3a90a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003030373236310020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.nasc.nzv() : {Nat.show(List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer()))) ++ " " ++ H.Sha256.hex(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), _)))) == "3072 2f506178486561646572732e3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000303030303030300030303030303030303031340030303030303030303030300030313032313600207800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000313220706174683d2fc3a90a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003030373236310020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.hex_app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), [118]))) : {Nat.show(List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer()))) ++ " " ++ _ == "3072 2f506178486561646572732e3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000303030303030300030303030303030303031340030303030303030303030300030313032313600207800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000313220706174683d2fc3a90a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003030373236310020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.hex_app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), [118])) : {Nat.show(List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer()))) ++ " " ++ String.append(H.Sha256.hex(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{})), _) == "3072 2f506178486561646572732e3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000303030303030300030303030303030303031340030303030303030303030300030313032313600207800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000313220706174683d2fc3a90a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003030373236310020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.hex_app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), [118]) : {Nat.show(List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer()))) ++ " " ++ String.append(H.Sha256.hex(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{})), String.append(H.Sha256.hex(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n)), _)) == "3072 2f506178486561646572732e3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000303030303030300030303030303030303031340030303030303030303030300030313032313600207800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000313220706174683d2fc3a90a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003030373236310020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.nasc.h1() : {Nat.show(List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer()))) ++ " " ++ String.append(_, String.append(H.Sha256.hex(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n)), String.append(H.Sha256.hex(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{})), H.Sha256.hex([118])))) == "3072 2f506178486561646572732e3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000303030303030300030303030303030303031340030303030303030303030300030313032313600207800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000313220706174683d2fc3a90a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003030373236310020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.nasc.h2() : {Nat.show(List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer()))) ++ " " ++ String.append("2f506178486561646572732e3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000303030303030300030303030303030303031340030303030303030303030300030313032313600207800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", String.append(_, String.append(H.Sha256.hex(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{})), H.Sha256.hex([118])))) == "3072 2f506178486561646572732e3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000303030303030300030303030303030303031340030303030303030303030300030313032313600207800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000313220706174683d2fc3a90a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003030373236310020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.nasc.h3() : {Nat.show(List.length(&2, U32, S.Snap.app(S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_hdr_name(S.Snap.b("/é")), S.Snap.Tar.zero8(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))))), 120, S.Snap.zeros(8n), Nil{}), S.Snap.app(S.Snap.Tar.data(S.Snap.app(S.Snap.Dec.itoa(12n), S.Snap.app([32, 112, 97, 116, 104, 61], S.Snap.app(S.Snap.b("/é"), [10]))), 512n), S.Snap.app(S.Snap.Tar.block(S.Snap.Tar.pax_name(S.Snap.b("/é")), S.Snap.Tar.mode666(), S.Snap.Tar.size(S.Snap.Oct.count(S.Snap.b("v"))), 48, S.Snap.Tar.zero8(), Nil{}), S.Snap.Tar.data(S.Snap.b("v"), 512n)))), S.Snap.Tar.trailer()))) ++ " " ++ String.append("2f506178486561646572732e3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000303030303030300030303030303030303031340030303030303030303030300030313032313600207800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", String.append("313220706174683d2fc3a90a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", String.append(_, H.Sha256.hex([118])))) == "3072 2f506178486561646572732e3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000303030303030300030303030303030303031340030303030303030303030300030313032313600207800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000313220706174683d2fc3a90a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003030373236310020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  %rt.nasc.len() : {Nat.show(_) ++ " " ++ String.append("2f506178486561646572732e3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000303030303030300030303030303030303031340030303030303030303030300030313032313600207800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", String.append("313220706174683d2fc3a90a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", String.append("2f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030363636003030303030303000303030303030300030303030303030303030310030303030303030303030300030303732363100203000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000303030303030300030303030303030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", H.Sha256.hex([118])))) == "3072 2f506178486561646572732e3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000303030303030300030303030303030303031340030303030303030303030300030313032313600207800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000313220706174683d2fc3a90a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003030373236310020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}
  {==}
