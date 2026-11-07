import Base
import ../laws/certs.bend as L
import ../src/standalone/certs.bend as C

# Proofs of laws/certs.bend: `def L.<law>` for each law.
#
# The concrete laws compute. Monotonicity goes by induction on the time
# added, with a <= m implies a <= m + 1 (as in proofs/names.bend). The CN
# laws take the node name apart: an empty one contradicts the hypothesis,
# a non-empty one heads the DNS SANs, and String.order(a, a) == EQ (as in
# proofs/services.bend) finds it there.

# Concrete laws: both sides compute.

def L.certs.expiring.all_valid():
  {==}

def L.certs.expiring.leaf_60_days():
  {==}

def L.certs.expiring.leaf_expired():
  {==}

def L.certs.expiring.ca_expiring():
  {==}

def L.certs.expiring.ca_expired():
  {==}

def L.certs.expiring.front_proxy_client():
  {==}

def L.certs.expiring.missing_leaf():
  {==}

def L.certs.expiring.missing_ca():
  {==}

def L.certs.expiring.invalid_pem():
  {==}

def L.certs.expiring.empty_pem():
  {==}

def L.certs.is_ca_file.ca():
  {==}

def L.certs.is_ca_file.server_ca():
  {==}

def L.certs.is_ca_file.client_ca():
  {==}

def L.certs.is_ca_file.front_proxy_ca():
  {==}

def L.certs.is_ca_file.etcd_ca():
  {==}

def L.certs.is_ca_file.apiserver():
  {==}

def L.certs.is_ca_file.kubelet_client():
  {==}

def L.certs.is_ca_file.etcd_client():
  {==}

def L.certs.is_ca_file.front_proxy_client():
  {==}

def L.certs.is_ca_file.etcd_server():
  {==}

def L.certs.is_ca_file.etcd_peer():
  {==}

def L.certs.is_ca_file.etcd_healthcheck():
  {==}

def L.certs.warn.all_valid():
  {==}

def L.certs.warn.ca_expiring():
  {==}

def L.certs.warn.ca_empty():
  {==}

def L.certs.warn.ca_missing():
  {==}

def L.certs.warn.message():
  {==}

def L.certs.split_ca.preserves_aliases():
  {==}

def L.certs.split_ca.creates_aliases():
  {==}

def L.certs.serving.split():
  {==}

def L.certs.serving.not_split():
  {==}

def L.certs.generate.split():
  {==}

def L.certs.generate.not_split():
  {==}

def L.certs.split.same():
  {==}

def L.certs.split.different():
  {==}

def L.certs.trust_ca.clears_path():
  {==}

def L.certs.disk.valid():
  {==}

def L.certs.disk.expiring():
  {==}

def L.certs.disk.ca_only():
  {==}

def L.certs.rollout.statefulset():
  {==}

def L.certs.rollout.deployment():
  {==}

def L.certs.rollout.etcd_not_found():
  {==}

def L.certs.renewal.at_90_days():
  {==}

def L.certs.renewal.after_90_days():
  {==}

def L.certs.renewal.expired():
  {==}

def L.certs.renew_hours():
  {==}

def L.certs.check_interval():
  {==}

def L.certs.jitter():
  {==}

def L.certs.exit_delay():
  {==}

def L.certs.validity():
  {==}

def L.certs.key_bits():
  {==}

def L.certs.etcd_extra_sans():
  {==}

def L.certs.plan():
  {==}

def L.certs.plan.test_config_apiserver():
  {==}

def L.certs.final.apiserver_dns():
  {==}

def L.certs.final.apiserver_ips():
  {==}

def L.certs.final.etcd_server_dns():
  {==}

def L.certs.final.etcd_server_ips():
  {==}

def L.certs.sans.ips():
  {==}

def L.certs.sans.dns():
  {==}

def L.certs.cn_in_san.plan():
  {==}

def L.certs.kubeconfigs():
  {==}

def L.certs.kubeconfig.context():
  {==}

def L.certs.rewritten_kubeconfigs():
  {==}

def L.certs.leaf_secret_keys():
  {==}

def L.certs.leaf_files():
  {==}

def L.certs.ca_secret_keys():
  {==}

def L.certs.removed.leaf():
  {==}

def L.certs.removed.with_ca():
  {==}

def L.certs.ensure.no_ca_key():
  {==}

def L.certs.ensure.expiring():
  {==}

def L.certs.ensure.valid():
  {==}

def L.certs.rotate.leaf():
  {==}

def L.certs.rotate.with_ca():
  {==}

def L.certs.watcher.valid():
  {==}

def L.certs.watcher.expiring():
  {==}
# Lemmas.

def certs.disc(b: Bool) -> Type:
  match b:
    case True{}:
      Unit
    case False{}:
      Empty

# True is not False.
def certs.true_false(e: {True{} == False{} : Bool}) -> Empty:
  %e : certs.disc(_)
  Unit{}

def certs.absurd_tf(-A: Type, e: {True{} == False{} : Bool}) -> A:
  Empty.absurd(A, certs.true_false(e))

def certs.ndisc(b: Bool) -> Type:
  match b:
    case False{}:
      Unit
    case True{}:
      Empty

# False is not True.
def certs.false_true(e: {False{} == True{} : Bool}) -> Empty:
  %e : certs.ndisc(_)
  Unit{}

def certs.absurd_ft(-A: Type, e: {False{} == True{} : Bool}) -> A:
  Empty.absurd(A, certs.false_true(e))

# a <= m implies a <= m + 1.
law certs.le_succ:
  for a: Nat
  for m: Nat
  for h: {Nat.is_le(a, m) == True{} : Bool}
  {Nat.is_le(a, 1n+m) == True{} : Bool}

def certs.le_succ(a, m, h):
  match a m:
    case 0n _:
      {==}
    case 1n+ap 0n:
      certs.absurd_ft({Nat.is_le(1n+ap, 1n) == True{} : Bool}, h)
    case 1n+ap 1n+mp:
      certs.le_succ(ap, mp, h)

# String.order(a, a) == EQ (as in proofs/services.bend).

law certs.bool_refl:
  for a: Bool
  {Bool.cmp(a, a) == EQ{} : Cmp}

def certs.bool_refl(a):
  match a:
    case False{}:
      {==}
    case True{}:
      {==}

law certs.word_refl:
  for +n: Nat
  for +a: Word(n)
  {Word.cmp(n, a, a) == EQ{} : Cmp}

def certs.word_refl(n, a):
  match n:
    case 0n:
      {==}
    case 1n+p:
      match a:
        case WCon{ab, at}:
          %Equal.sym(Cmp, Word.cmp(p, at, at), EQ{}, certs.word_refl(p, at)) : {Word.cmp.fin(ab, ab, _) == EQ{} : Cmp}
          certs.bool_refl(ab)

law certs.u32_refl:
  for a: U32
  {U32.cmp(a, a) == EQ{} : Cmp}

def certs.u32_refl(a):
  match a:
    case U32{x}:
      certs.word_refl(32n, x)

law certs.str_refl:
  for +a: String
  {String.order(a, a) == EQ{} : Cmp}

def certs.str_refl(a):
  match a:
    case SNil{}:
      {==}
    case SCon{Chr{x}, t}:
      %Equal.sym(Cmp, U32.cmp(x, x), EQ{}, certs.u32_refl(x)) : {String.order.go(t, t, _) == EQ{} : Cmp}
      certs.str_refl(t)

# k is a member of k <> a.
law certs.elem_self:
  for +k: String
  for +a: +List<String>
  {C.Certs.elem(k, k <> a) == True{} : Bool}

def certs.elem_self(k, a):
  %Equal.sym(Cmp, String.order(k, k), EQ{}, certs.str_refl(k)) : {Bool.or(Cmp.is_eq(_), C.Certs.elem(k, a)) == True{} : Bool}
  {==}

# A node name that is set heads the etcd DNS SANs.
law certs.node_dns_has:
  for +name: String
  for +rest: +List<String>
  for h: {String.is_empty(name) == False{} : Bool}
  {C.Certs.elem(name, List.append(&2, String, C.Certs.node_dns(name), rest)) == True{} : Bool}

def certs.node_dns_has(name, rest, h):
  match name:
    case SNil{}:
      certs.absurd_tf({C.Certs.elem(SNil{}, List.append(&2, String, C.Certs.node_dns(SNil{}), rest)) == True{} : Bool}, h)
    case SCon{+x, +t}:
      certs.elem_self(SCon{x, t}, List.append(&2, String, ["localhost"], rest))

# General laws.

def L.certs.needs_renewal_monotone(now, d, not_after, h):
  match d:
    case 0n:
      h
    case 1n+p:
      certs.le_succ(not_after, Nat.add(Nat.add(p, now), C.Certs.renew_hours()),
        L.certs.needs_renewal_monotone(now, p, not_after, h))

def L.certs.etcd_server_cn_in_san(c, h):
  match c:
    case C.Cfg{name, adv, ep, vip, dom, api, etcd}:
      certs.node_dns_has(name, C.Certs.san_dns(etcd), h)

def L.certs.etcd_peer_cn_in_san(c, h):
  match c:
    case C.Cfg{name, adv, ep, vip, dom, api, etcd}:
      certs.node_dns_has(name, C.Certs.san_dns(etcd), h)
