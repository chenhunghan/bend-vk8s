import Base
import ../laws/snapshot.bend as L
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

def L.snapshot.tar.pax():
  {==}

def L.snapshot.tar.non_ascii():
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
