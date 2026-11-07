import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ./meta.bend as M
import ./names.bend as N
import ./services.bend as S

# Nodes and events (vcluster pkg/controllers/resources/nodes: syncer.go,
# translate.go, fake_syncer.go; pkg/controllers/resources/events and
# pkg/mappings/resources/events.go), as pure functions of object snapshots.
#
# Objects are bend-kube JSON values (J.Json). A step returns the writes of
# services.bend (S.Write, S.Outcome); outcomes compare in its canonical form
# (S.Svc.canon_outcome). What vcluster reads from caches or other services
# comes in as parameters:
# - vpods: the virtual pods; hpods: the host pods vcluster manages (its
#   IndexByAssigned indices, which only hold pods with a node name);
# - pods: every host pod (the pod cache of the virtual scheduler);
# - ip: the IP the node service provider gives the node (proxyKubelets.byIP);
# - for an event, the virtual object its involved object maps to (found),
#   and the virtual namespaces that exist and are not terminating (live).
#
# Kubernetes quantities are read and written as vcluster's resource package
# does (Value and MilliValue round up; DecimalSI and BinarySI canonical
# forms). The numbers are decimal digit lists, as Bend has no 64-bit
# integers.
#
# vcluster quirks kept as they are:
# - The nodes mapper is a mirror mapper, whose IsManaged is always true, so
#   the virtual scheduler never takes non-vcluster pods off the pods
#   allocatable (nodes/translate.go:181-197); their requests do count.
# - A fake node's nodeInfo.architecture is always "amd64", while its arch
#   labels carry the arch vcluster runs on (fake_syncer.go:160-166, 239).
# - Updating a fake node always sets the hostname address, even with
#   proxyKubelets.byHostname off (fake_syncer.go:110-123).
# - Events accept the kind "Endpoint", not "Endpoints"
#   (mappings/resources/events.go:22-28), so events of endpoints never sync.
# - ParseToleration(":NoSchedule op=Exists") gives key "", operator Exists
#   and effect "NoSchedule op=Exists"; an empty key with Exists tolerates
#   every taint, so it clears them all (nodes/translate.go:298-324).
# - A toleration "k=v" (no effect) has no operator and matches no taint.
#
# Not modelled: translate patches (Pro), the node service itself, the
# events of terminating namespaces beyond the live list, the resources of a
# pod's status (in-place resize) in its requests. Pod requests are rounded up
# per container (CPU to millicores, the rest to integers) before they are
# summed; Kubernetes sums exact quantities and rounds once.

# A taint: key, value, effect and timeAdded (JNull when absent).
type Taint is Data:
  Taint{key: String, value: String, effect: String, time: J.Json}

# A taint and its Go JSON text (json.Marshal of corev1.Taint).
type TS is Data:
  TS{text: String, taint: Taint}

# corev1.Toleration as toleration.ParseToleration makes it.
type Tol is Data:
  Tol{key: String, op: String, value: String, effect: String}

# sync.fromHost.nodes.selector: none (nodes a pod needs), all, or labels.
type Selector is Data:
  SelNone{}
  SelAll{}
  SelLabels{labels: List<&2, M.KV>}

# The real node syncer's configuration: the selector, the virtual scheduler
# (or hybrid scheduling), clearImageStatus, proxyKubelets byHostname and
# byIP, sync.toHost.pods.enforceTolerations, and the NODE_NAME environment
# variable (env_set says whether it is set).
type Opts is Data:
  Opts{selector: Selector, scheduler: Bool, clear_images: Bool, by_hostname: Bool, by_ip: Bool, tolerations: List<&2, String>, env_node: String, env_set: Bool}

# The fake node syncer's configuration: proxyKubelets byHostname and byIP,
# runtime.GOARCH, the time (metav1.Now) and the three random IDs of a new
# fake node (boot ID, machine ID, system UUID).
type Fake is Data:
  Fake{by_hostname: Bool, by_ip: Bool, arch: String, now: String, boot: String, machine: String, system: String}

# Resource requests: CPU in millicores, memory and ephemeral storage in
# bytes, as decimal digit lists.
type Reqs is Data:
  Reqs{cpu: List<&2, U32>, mem: List<&2, U32>, eph: List<&2, U32>}

# The fold over init containers: the sum of the restartable ones so far,
# and the largest request of one so far.
type Init is Data:
  Init{restartable: Reqs, max: Reqs}

# A parsed quantity: digits n (little-endian, the decimal point dropped)
# times 1024^k times 10^p over 10^q.
type Q is Data:
  Q{n: List<&2, U32>, k: Nat, p: Nat, q: Nat}

# A quantity suffix and its factors.
type Sfx is Data:
  Sfx{name: String, k: Nat, p: Nat, q: Nat}

# The state of strings.ReplaceAll: the output so far and how many chars of
# a match are still to skip.
type Rep is Data:
  Rep{out: String, skip: Nat}

# Configuration.

def Node.selector(o: Opts) -> Selector:
  match o:
    case Opts{sel, sch, ci, bh, bi, tols, en, es}:
      sel

def Node.scheduler(o: Opts) -> Bool:
  match o:
    case Opts{sel, sch, ci, bh, bi, tols, en, es}:
      sch

def Node.clear_images(o: Opts) -> Bool:
  match o:
    case Opts{sel, sch, ci, bh, bi, tols, en, es}:
      ci

def Node.by_hostname(o: Opts) -> Bool:
  match o:
    case Opts{sel, sch, ci, bh, bi, tols, en, es}:
      bh

def Node.by_ip(o: Opts) -> Bool:
  match o:
    case Opts{sel, sch, ci, bh, bi, tols, en, es}:
      bi

def Node.tolerations(o: Opts) -> List<&2, String>:
  match o:
    case Opts{sel, sch, ci, bh, bi, tols, en, es}:
      tols

def Node.env_node(o: Opts) -> String:
  match o:
    case Opts{sel, sch, ci, bh, bi, tols, en, es}:
      en

def Node.env_set(o: Opts) -> Bool:
  match o:
    case Opts{sel, sch, ci, bh, bi, tols, en, es}:
      es

def Node.fake_by_hostname(f: Fake) -> Bool:
  match f:
    case Fake{bh, bi, arch, now, boot, machine, system}:
      bh

def Node.fake_by_ip(f: Fake) -> Bool:
  match f:
    case Fake{bh, bi, arch, now, boot, machine, system}:
      bi

def Node.fake_arch(f: Fake) -> String:
  match f:
    case Fake{bh, bi, arch, now, boot, machine, system}:
      arch

def Node.fake_now(f: Fake) -> String:
  match f:
    case Fake{bh, bi, arch, now, boot, machine, system}:
      now

def Node.fake_boot(f: Fake) -> String:
  match f:
    case Fake{bh, bi, arch, now, boot, machine, system}:
      boot

def Node.fake_machine(f: Fake) -> String:
  match f:
    case Fake{bh, bi, arch, now, boot, machine, system}:
      machine

def Node.fake_system(f: Fake) -> String:
  match f:
    case Fake{bh, bi, arch, now, boot, machine, system}:
      system

# Constants.

# nodes.TaintsAnnotation.
def Node.taints_annotation() -> String:
  "vcluster.loft.sh/original-taints"

def Node.rancher_requests() -> String:
  "management.cattle.io/pod-requests"

def Node.rancher_limits() -> String:
  "management.cattle.io/pod-limits"

# The annotations translateUpdateBackwards does not copy from the host.
def Node.excluded() -> +List<String>:
  [Node.taints_annotation(), Node.rancher_requests(), Node.rancher_limits()]

def Node.not_ready() -> String:
  "node.kubernetes.io/not-ready"

def Node.scale_down() -> String:
  "cluster-autoscaler.kubernetes.io/scale-down-disabled"

# constants.KubeletPort.
def Node.kubelet_port() -> J.Json:
  J.JNum{"10250"}

# constants.NodeSuffix.
def Node.node_suffix() -> String:
  "nodes.vcluster.com"

# podtranslate.OwnerSetKind.
def Node.owner_set_kind() -> String:
  "vcluster.loft.sh/owner-set-kind"

# nodes.FakeNodesVersion.
def Node.fake_version() -> String:
  "v1.19.1"

# Strings.

def Node.dash(c: Char) -> Char:
  match c:
    case '.':
      '-'
    case Chr{x}:
      Chr{x}

def Node.dots(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{c, t}:
      SCon{Node.dash(c), Node.dots(t)}

# nodes.GetNodeHost: the name with every "." made "-", then
# ".nodes.vcluster.com".
def Node.host(name: String) -> String:
  Node.dots(name) ++ "." ++ Node.node_suffix()

def Node.esc_bf(+x: U32, rest: String, b: Bool, f: Bool) -> String:
  match b f:
    case True{} _:
      "\\b" ++ rest
    case False{} True{}:
      "\\f" ++ rest
    case False{} False{}:
      "\\u00" ++ SCon{J.Json.hex((x >> 4n : U32)), SCon{J.Json.hex((x .&. 15 : U32)), rest}}

def Node.esc_line(+x: U32, rest: String, line: Bool) -> String:
  match line:
    case True{}:
      "\\u202" ++ SCon{J.Json.hex((x .&. 15 : U32)), rest}
    case False{}:
      SCon{Chr{x}, rest}

def Node.esc_ctl(+x: U32, rest: String, ctl: Bool) -> String:
  match ctl:
    case True{}:
      Node.esc_bf(x, rest, U32.is_eq(x, 8), U32.is_eq(x, 12))
    case False{}:
      Node.esc_line(x, rest, Bool.or(U32.is_eq(x, 8232), U32.is_eq(x, 8233)))

# One char of Go's JSON string encoding onto the escaped rest: Go also
# escapes <, > and &, and U+2028 and U+2029.
def Node.esc_chr(c: Char, rest: String) -> String:
  match c:
    case '"':
      SCon{'\\', SCon{'"', rest}}
    case '\\':
      SCon{'\\', SCon{'\\', rest}}
    case '\n':
      SCon{'\\', SCon{'n', rest}}
    case '\r':
      SCon{'\\', SCon{'r', rest}}
    case '\t':
      SCon{'\\', SCon{'t', rest}}
    case '<':
      "\\u003c" ++ rest
    case '>':
      "\\u003e" ++ rest
    case '&':
      "\\u0026" ++ rest
    case Chr{+x}:
      Node.esc_ctl(x, rest, U32.is_lt(x, 32))

def Node.esc(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{c, t}:
      Node.esc_chr(c, Node.esc(t))

# A string as Go's encoding/json writes it.
def Node.gostr(s: String) -> String:
  "\"" ++ Node.esc(s) ++ "\""

def Node.gostrs.go(xs: +List<String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, r}:
      "," ++ Node.gostr(x) ++ Node.gostrs.go(r)

# json.Marshal of a []string.
def Node.gostrs(xs: +List<String>) -> String:
  match xs:
    case Nil{}:
      "[]"
    case Con{x, r}:
      "[" ++ Node.gostr(x) ++ Node.gostrs.go(r) ++ "]"

# Taints.

def Node.taint(+t: J.Json) -> Taint:
  Taint{S.Svc.str(J.Json.get(t, "key")), S.Svc.str(J.Json.get(t, "value")), S.Svc.str(J.Json.get(t, "effect")), J.Json.get(t, "timeAdded")}

def Node.opt_value(v: String) -> String:
  match v:
    case SNil{}:
      ""
    case SCon{c, t}:
      ",\"value\":" ++ Node.gostr(SCon{c, t})

def Node.opt_time(t: J.Json) -> String:
  match t:
    case J.JStr{s}:
      ",\"timeAdded\":" ++ Node.gostr(s)
    case _:
      ""

# json.Marshal of a corev1.Taint: key, value (omitempty), effect,
# timeAdded (omitempty).
def Node.taint_text(t: Taint) -> String:
  match t:
    case Taint{k, v, e, tm}:
      "{\"key\":" ++ Node.gostr(k) ++ Node.opt_value(v) ++ ",\"effect\":" ++ Node.gostr(e) ++ Node.opt_time(tm) ++ "}"

# A taint as a JSON object.
def Node.taint_json(t: Taint) -> J.Json:
  match t:
    case Taint{k, v, e, tm}:
      J.JObj{J.JMem{"key", J.JStr{k}, S.Svc.mem("value", S.Svc.sj(v), J.JMem{"effect", J.JStr{e}, S.Svc.mem("timeAdded", tm, J.JNil{})})}}

def Node.ts(+t: J.Json) -> TS:
  +tt = Node.taint(t)
  TS{Node.taint_text(tt), tt}

def Node.ts_text(x: TS) -> String:
  match x:
    case TS{s, t}:
      s

def Node.ts_taint(x: TS) -> Taint:
  match x:
    case TS{s, t}:
      t

def Node.key_of(+t: J.Json) -> String:
  S.Svc.str(J.Json.get(t, "key"))

# True when a taint has the key node.kubernetes.io/not-ready.
def Node.has_unready(xs: List<&2, J.Json>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{t, r}:
      Bool.or(String.eq(Node.key_of(t), Node.not_ready()), Node.has_unready(r))

def Node.tss(xs: List<&2, J.Json>) -> List<&2, TS>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{t, r}:
      Node.ts(t) <> Node.tss(r)

def Node.vtss.if(skip: Bool, +t: J.Json, rec: List<&2, TS>) -> List<&2, TS>:
  match skip:
    case True{}:
      rec
    case False{}:
      Node.ts(t) <> rec

# The virtual taints, without node.kubernetes.io/not-ready unless the host
# has it.
def Node.vtss(+unready: Bool, xs: List<&2, J.Json>) -> List<&2, TS>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+t, r}:
      Node.vtss.if(Bool.and(Bool.not(unready), String.eq(Node.key_of(t), Node.not_ready())), t, Node.vtss(unready, r))

def Node.ts_in(+s: String, xs: List<&2, TS>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{x, r}:
      Bool.or(String.eq(Node.ts_text(x), s), Node.ts_in(s, r))

def Node.texts(xs: List<&2, TS>) -> +List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, r}:
      Node.ts_text(x) <> Node.texts(r)

def Node.dedup.put(hit: Bool, x: TS, acc: List<&2, TS>) -> List<&2, TS>:
  match hit:
    case True{}:
      acc
    case False{}:
      x <> acc

# stringutil.RemoveDuplicates: the first of equal texts stays, in order.
def Node.dedup(xs: List<&2, TS>, +acc: List<&2, TS>) -> List<&2, TS>:
  match xs:
    case Nil{}:
      List.reverse(&2, TS, acc)
    case Con{+x, r}:
      Node.dedup(r, Node.dedup.put(Node.ts_in(Node.ts_text(x), acc), x, acc))

def Node.drop_old.if(drop: Bool, x: TS, rec: List<&2, TS>) -> List<&2, TS>:
  match drop:
    case True{}:
      rec
    case False{}:
      x <> rec

# Drops each taint the host had before (old) but has no more.
def Node.drop_old(xs: List<&2, TS>, +old: +List<String>, +physical: List<&2, TS>) -> List<&2, TS>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, r}:
      Node.drop_old.if(Bool.and(M.Meta.elem(Node.ts_text(x), old), Bool.not(Node.ts_in(Node.ts_text(x), physical))), x, Node.drop_old(r, old, physical))

# nodes mergeStrings(physical, virtual, oldPhysical).
def Node.merge(+physical: List<&2, TS>, virt: List<&2, TS>, +old: +List<String>) -> List<&2, TS>:
  Node.drop_old(Node.dedup(List.append(&2, TS, physical, virt), []), old, physical)

def Node.strs.put(x: J.Json, rec: +List<String>) -> +List<String>:
  match x:
    case J.JStr{s}:
      s <> rec
    case _:
      rec

def Node.strs(xs: List<&2, J.Json>) -> +List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, r}:
      Node.strs.put(x, Node.strs(r))

def Node.old_physical.r(r: Result<&2, &2, String, J.Json>) -> +List<String>:
  match r:
    case Fail{e}:
      Nil{}
    case Done{j}:
      Node.strs(J.Json.items(j))

def Node.old_physical.s(s: String) -> +List<String>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{c, t}:
      Node.old_physical.r(J.Json.parse(SCon{c, t}))

# The taint texts of the vcluster.loft.sh/original-taints annotation (a
# JSON list of strings); none when it is empty or not JSON.
def Node.old_physical(ann: +List<M.KV>) -> +List<String>:
  Node.old_physical.s(M.Meta.lookup(Node.taints_annotation(), ann))

# Tolerations.

def Node.alnum(c: Char) -> Bool:
  match c:
    case Chr{+x}:
      Bool.or(Char.is_digit(Chr{x}), Char.is_alpha(Chr{x}))

def Node.label_char(c: Char) -> Bool:
  match c:
    case Chr{+x}:
      Bool.or(Node.alnum(Chr{x}), Bool.or(U32.is_eq(x, 45), Bool.or(U32.is_eq(x, 95), U32.is_eq(x, 46))))

def Node.all_label(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      Bool.and(Node.label_char(c), Node.all_label(t))

def Node.last_alnum(t: String, c: Char) -> Bool:
  match t:
    case SNil{}:
      Node.alnum(c)
    case SCon{c2, t2}:
      Node.last_alnum(t2, c2)

def Node.label_shape(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{+c, +t}:
      Bool.and(Node.alnum(c), Bool.and(Node.all_label(t), Node.last_alnum(t, c)))

# validation.IsValidLabelValue: at most 63 chars, empty or alphanumeric at
# both ends with only alphanumerics, "-", "_" and "." between.
def Node.is_label_value(+v: String) -> Bool:
  Bool.and(String.is_empty(String.drop(v, 63n)), Node.label_shape(v))

def Node.tol.valid(ok: Bool, t: Tol) -> Maybe<&2, Tol>:
  match ok:
    case True{}:
      Some{t}
    case False{}:
      None{}

def Node.tol.eq(parts: +List<String>) -> Maybe<&2, Tol>:
  match parts:
    case Con{k, Nil{}}:
      Some{Tol{k, "", "", ""}}
    case Con{k, Con{+v, Nil{}}}:
      Node.tol.valid(Node.is_label_value(v), Tol{k, "", v, ""})
    case _:
      None{}

def Node.tol.kv(kv: +List<String>, effect: String) -> Maybe<&2, Tol>:
  match kv:
    case Con{k, Nil{}}:
      Some{Tol{k, "Exists", "", effect}}
    case Con{k, Con{+v, Nil{}}}:
      Node.tol.valid(Node.is_label_value(v), Tol{k, "Equal", v, effect})
    case _:
      None{}

def Node.tol.cl(cl: +List<String>, +s: String) -> Maybe<&2, Tol>:
  match cl:
    case Con{x, Nil{}}:
      Node.tol.eq(String.split(s, '='))
    case Con{kv, Con{effect, Nil{}}}:
      Node.tol.kv(String.split(kv, '='), effect)
    case _:
      None{}

def Node.parse_tol.if(star: Bool, +s: String) -> Maybe<&2, Tol>:
  match star:
    case True{}:
      Some{Tol{"", "Exists", "", ""}}
    case False{}:
      Node.tol.cl(String.split(s, ':'), s)

# toleration.ParseToleration; None on an error.
def Node.parse_tol(+s: String) -> Maybe<&2, Tol>:
  Node.parse_tol.if(String.eq(s, "*"), s)

def Node.tols.put(m: Maybe<&2, Tol>, rec: List<&2, Tol>) -> List<&2, Tol>:
  match m:
    case None{}:
      rec
    case Some{t}:
      t <> rec

# The enforced tolerations that parse.
def Node.tols(xs: +List<String>) -> List<&2, Tol>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, r}:
      Node.tols.put(Node.parse_tol(x), Node.tols(r))

# An empty key with operator Exists tolerates everything.
def Node.tol_all(t: Tol) -> Bool:
  match t:
    case Tol{k, op, v, e}:
      Bool.and(String.is_empty(k), String.eq(op, "Exists"))

def Node.any_all(ts: List<&2, Tol>) -> Bool:
  match ts:
    case Nil{}:
      False{}
    case Con{t, r}:
      Bool.or(Node.tol_all(t), Node.any_all(r))

def Node.tolerates(t: Tol, x: Taint) -> Bool:
  match t x:
    case Tol{+k, +op, v, +e} Taint{tk, tv, te, tm}:
      +keyed = Bool.and(String.eq(tk, k), Bool.or(String.eq(te, e), String.is_empty(e)))
      Bool.and(keyed, Bool.or(String.eq(op, "Exists"), Bool.and(String.eq(op, "Equal"), String.eq(tv, v))))

def Node.tolerated(+x: Taint, ts: List<&2, Tol>) -> Bool:
  match ts:
    case Nil{}:
      False{}
    case Con{t, r}:
      Bool.or(Node.tolerates(t, x), Node.tolerated(x, r))

def Node.untolerated.if(drop: Bool, x: TS, rec: List<&2, TS>) -> List<&2, TS>:
  match drop:
    case True{}:
      rec
    case False{}:
      x <> rec

def Node.untolerated(xs: List<&2, TS>, +ts: List<&2, Tol>) -> List<&2, TS>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, r}:
      Node.untolerated.if(Node.tolerated(Node.ts_taint(x), ts), x, Node.untolerated(r, ts))

def Node.filter.if(all: Bool, xs: List<&2, TS>, ts: List<&2, Tol>) -> List<&2, TS>:
  match all:
    case True{}:
      Nil{}
    case False{}:
      Node.untolerated(xs, ts)

# filterOutTaintsMatchingTolerations: a toleration with an empty key and
# Exists drops every taint (vcluster returns nil as soon as it meets one);
# otherwise each taint some toleration matches goes.
def Node.filter_taints(+ts: List<&2, Tol>, xs: List<&2, TS>) -> List<&2, TS>:
  Node.filter.if(Node.any_all(ts), xs, ts)

def Node.taints_json(xs: List<&2, TS>) -> List<&2, J.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, r}:
      Node.taint_json(Node.ts_taint(x)) <> Node.taints_json(r)

# The original-taints annotation: the host taints as a JSON list of their
# texts, or no annotation when the host has none.
def Node.taints_ann(physical: List<&2, TS>, ann: +List<M.KV>) -> +List<M.KV>:
  match physical:
    case Nil{}:
      M.Meta.delete(Node.taints_annotation(), ann)
    case Con{x, r}:
      M.Meta.insert(Node.taints_annotation(), Node.gostrs(Node.texts(x <> r)), ann)

def Node.scale_down.if(hit: Bool, ann: +List<M.KV>) -> +List<M.KV>:
  match hit:
    case True{}:
      M.Meta.insert(Node.scale_down(), "true", ann)
    case False{}:
      ann

# NODE_NAME set to the host node's name keeps the cluster autoscaler away.
def Node.scale_down_ann(+o: Opts, +name: String, ann: +List<M.KV>) -> +List<M.KV>:
  Node.scale_down.if(Bool.and(Node.env_set(o), String.eq(Node.env_node(o), name)), ann)

def Node.backwards.fin(+o: Opts, +h: J.Json, +v: J.Json, lm: +List<M.KV> & +List<M.KV>) -> J.Json:
  (labels, ann) = lm
  +hts = J.Json.items(J.Json.at(h, ["spec", "taints"]))
  +unready = Node.has_unready(hts)
  phys virt = Node.tss(hts) Node.vtss(unready, J.Json.items(J.Json.at(v, ["spec", "taints"])))
  +physical = phys
  merged = Node.merge(physical, virt, Node.old_physical(S.Svc.annotations(v)))
  taints = Node.filter_taints(Node.tols(Node.tolerations(o)), merged)
  ann2 = Node.scale_down_ann(o, S.Svc.name(h), Node.taints_ann(physical, ann))
  spec = S.Svc.put(J.Json.get(h, "spec"), "taints", J.Json.arr(Node.taints_json(taints)))
  S.Svc.with_meta(J.Json.set(v, "spec", spec), ann2, labels)

# nodes translateUpdateBackwards(pNode, vNode): the virtual node with the
# host spec, the host labels and annotations applied (translate.ApplyMetadata,
# without the original-taints and Rancher annotations), and the host and
# virtual taints merged.
def Node.backwards(+o: Opts, +h: J.Json, +v: J.Json) -> J.Json:
  lm = M.Meta.apply_metadata(S.Svc.annotations(h), S.Svc.annotations(v), S.Svc.labels(h), S.Svc.labels(v), Node.excluded())
  Node.backwards.fin(o, h, v, lm)

# Quantities.

def Qty.zero() -> List<&2, U32>:
  Nil{}

# a + c, c a digit or a carry below 10.
def Qty.add1(a: List<&2, U32>, +c: U32) -> List<&2, U32>:
  match a:
    case Nil{}:
      [c]
    case Con{x, r}:
      +s = U32.add(x, c)
      U32.mod(s, 10) <> Qty.add1(r, U32.div(s, 10))

def Qty.add.go(a: List<&2, U32>, b: List<&2, U32>, +c: U32) -> List<&2, U32>:
  match a b:
    case Nil{} y:
      Qty.add1(y, c)
    case Con{x, r} Nil{}:
      Qty.add1(Con{x, r}, c)
    case Con{x, r} Con{y, t}:
      +s = U32.add(U32.add(x, y), c)
      U32.mod(s, 10) <> Qty.add.go(r, t, U32.div(s, 10))

def Qty.add(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  Qty.add.go(a, b, 0)

def Qty.head(b: List<&2, U32>) -> U32:
  match b:
    case Nil{}:
      0
    case Con{y, t}:
      y

def Qty.tail(b: List<&2, U32>) -> List<&2, U32>:
  match b:
    case Nil{}:
      Nil{}
    case Con{y, t}:
      t

def Qty.sub.digit(lt: Bool, +x: U32, +d: U32) -> U32:
  match lt:
    case True{}:
      U32.sub(U32.add(x, 10), d)
    case False{}:
      U32.sub(x, d)

def Qty.sub.go(a: List<&2, U32>, +b: List<&2, U32>, +br: U32) -> List<&2, U32>:
  match a:
    case Nil{}:
      Nil{}
    case Con{+x, r}:
      +d = U32.add(Qty.head(b), br)
      +lt = U32.is_lt(x, d)
      Qty.sub.digit(lt, x, d) <> Qty.sub.go(r, Qty.tail(b), Bool.to_u32(lt))

# a - b, for a >= b.
def Qty.sub(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  Qty.sub.go(a, b, 0)

def Qty.is_zero(a: List<&2, U32>) -> Bool:
  match a:
    case Nil{}:
      True{}
    case Con{x, r}:
      Bool.and(U32.is_zero(x), Qty.is_zero(r))

def Qty.cmp.digit(d: Cmp, c: Cmp) -> Cmp:
  match d:
    case LT{}:
      LT{}
    case EQ{}:
      c
    case GT{}:
      GT{}

def Qty.cmp.rest(zero: Bool, c: Cmp, other: Cmp) -> Cmp:
  match zero:
    case True{}:
      c
    case False{}:
      other

# Compares two digit lists; c is the order of the lower digits.
def Qty.cmp.go(a: List<&2, U32>, b: List<&2, U32>, c: Cmp) -> Cmp:
  match a b:
    case Nil{} y:
      Qty.cmp.rest(Qty.is_zero(y), c, LT{})
    case Con{x, r} Nil{}:
      Qty.cmp.rest(Qty.is_zero(Con{x, r}), c, GT{})
    case Con{x, r} Con{y, t}:
      Qty.cmp.go(r, t, Qty.cmp.digit(U32.cmp(x, y), c))

def Qty.cmp(a: List<&2, U32>, b: List<&2, U32>) -> Cmp:
  Qty.cmp.go(a, b, EQ{})

def Qty.gt(a: List<&2, U32>, b: List<&2, U32>) -> Bool:
  Cmp.is_gt(Qty.cmp(a, b))

def Qty.max.if(lt: Bool, a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  match lt:
    case True{}:
      b
    case False{}:
      a

def Qty.max(+a: List<&2, U32>, +b: List<&2, U32>) -> List<&2, U32>:
  Qty.max.if(Cmp.is_lt(Qty.cmp(a, b)), a, b)

# The digits of n (ten of them, zeros on top).
def Qty.of_u32(f: Nat, +n: U32) -> List<&2, U32>:
  match f:
    case 0n:
      Nil{}
    case 1n+p:
      U32.mod(n, 10) <> Qty.of_u32(p, U32.div(n, 10))

def Qty.mul.go(a: List<&2, U32>, +k: U32, +c: U32) -> List<&2, U32>:
  match a:
    case Nil{}:
      Qty.of_u32(10n, c)
    case Con{x, r}:
      +s = U32.add(U32.mul(x, k), c)
      U32.mod(s, 10) <> Qty.mul.go(r, k, U32.div(s, 10))

# a * k.
def Qty.mul(a: List<&2, U32>, +k: U32) -> List<&2, U32>:
  Qty.mul.go(a, k, 0)

def Qty.mul1024(k: Nat, a: List<&2, U32>) -> List<&2, U32>:
  match k:
    case 0n:
      a
    case 1n+p:
      Qty.mul1024(p, Qty.mul(a, 1024))

# a * 10^p.
def Qty.zeros(p: Nat, a: List<&2, U32>) -> List<&2, U32>:
  match p:
    case 0n:
      a
    case 1n+q:
      0 <> Qty.zeros(q, a)

# ceil(a / 10^d); rem says a dropped digit was not zero.
def Qty.ceil_drop(d: Nat, a: List<&2, U32>, rem: Bool) -> List<&2, U32>:
  match d a:
    case 0n x:
      Qty.add1(x, Bool.to_u32(rem))
    case 1n+p Nil{}:
      [Bool.to_u32(rem)]
    case 1n+p Con{+x, r}:
      Qty.ceil_drop(p, r, Bool.or(rem, Bool.not(U32.is_zero(x))))

def Qty.scale.if(up: Bool, a: List<&2, U32>, +p: Nat, +q: Nat) -> List<&2, U32>:
  match up:
    case True{}:
      Qty.zeros(Nat.sub(p, q), a)
    case False{}:
      Qty.ceil_drop(Nat.sub(q, p), a, False{})

# ceil(a * 10^p / 10^q).
def Qty.scale(a: List<&2, U32>, +p: Nat, +q: Nat) -> List<&2, U32>:
  Qty.scale.if(Nat.is_le(q, p), a, p, q)

def Qty.is_dot(c: Char) -> Bool:
  Char.is_eq(c, '.')

def Qty.is_num(c: Char) -> Bool:
  match c:
    case Chr{+x}:
      Bool.or(Char.is_digit(Chr{x}), U32.is_eq(x, 46))

def Qty.num_part.if(num: Bool, c: Char, rec: String) -> String:
  match num:
    case True{}:
      SCon{c, rec}
    case False{}:
      SNil{}

# The leading digits and points.
def Qty.num_part(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+c, t}:
      Qty.num_part.if(Qty.is_num(c), c, Qty.num_part(t))

def Qty.suffix_part.if(num: Bool, s: String, rec: String) -> String:
  match num:
    case True{}:
      rec
    case False{}:
      s

# What follows the leading digits and points.
def Qty.suffix_part(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+c, +t}:
      Qty.suffix_part.if(Qty.is_num(c), SCon{c, t}, Qty.suffix_part(t))

def Qty.push.if(digit: Bool, +x: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match digit:
    case True{}:
      U32.sub(x, 48) <> acc
    case False{}:
      acc

def Qty.push(c: Char, acc: List<&2, U32>) -> List<&2, U32>:
  match c:
    case Chr{+x}:
      Qty.push.if(Char.is_digit(Chr{x}), x, acc)

# The digits of a number, little-endian, the point dropped.
def Qty.digits(s: String, acc: List<&2, U32>) -> List<&2, U32>:
  match s:
    case SNil{}:
      acc
    case SCon{c, t}:
      Qty.digits(t, Qty.push(c, acc))

def Qty.frac.if(dot: Bool, n: Nat, rec: Nat) -> Nat:
  match dot:
    case True{}:
      n
    case False{}:
      rec

# The number of chars after the point.
def Qty.frac(s: String) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{c, +t}:
      Qty.frac.if(Qty.is_dot(c), String.length(t), Qty.frac(t))

def Qty.sfx_name(x: Sfx) -> String:
  match x:
    case Sfx{n, k, p, q}:
      n

# The suffixes of resource.Quantity: decimal SI, binary SI.
def Qty.sfxs() -> List<&2, Sfx>:
  [Sfx{"", 0n, 0n, 0n}, Sfx{"n", 0n, 0n, 9n}, Sfx{"u", 0n, 0n, 6n}, Sfx{"m", 0n, 0n, 3n},
   Sfx{"k", 0n, 3n, 0n}, Sfx{"M", 0n, 6n, 0n}, Sfx{"G", 0n, 9n, 0n}, Sfx{"T", 0n, 12n, 0n},
   Sfx{"P", 0n, 15n, 0n}, Sfx{"E", 0n, 18n, 0n},
   Sfx{"Ki", 1n, 0n, 0n}, Sfx{"Mi", 2n, 0n, 0n}, Sfx{"Gi", 3n, 0n, 0n}, Sfx{"Ti", 4n, 0n, 0n},
   Sfx{"Pi", 5n, 0n, 0n}, Sfx{"Ei", 6n, 0n, 0n}]

def Qty.exp.mk(pos: Bool, n: Nat) -> Sfx:
  match pos:
    case True{}:
      Sfx{"", 0n, n, 0n}
    case False{}:
      Sfx{"", 0n, 0n, n}

def Qty.exp.num.r(r: Maybe<&2, U32>, pos: Bool) -> Maybe<&2, Sfx>:
  match r:
    case None{}:
      None{}
    case Some{n}:
      Some{Qty.exp.mk(pos, U32.to_nat(n))}

def Qty.exp.c(c: Char, r: String) -> Maybe<&2, Sfx>:
  match c:
    case '-':
      Qty.exp.num.r(U32.read(r), False{})
    case '+':
      Qty.exp.num.r(U32.read(r), True{})
    case Chr{x}:
      Qty.exp.num.r(U32.read(SCon{Chr{x}, r}), True{})

def Qty.exp.sign(t: String) -> Maybe<&2, Sfx>:
  match t:
    case SNil{}:
      None{}
    case SCon{c, r}:
      Qty.exp.c(c, r)

def Qty.exp.if(e: Bool, t: String) -> Maybe<&2, Sfx>:
  match e:
    case True{}:
      Qty.exp.sign(t)
    case False{}:
      None{}

# An exponent suffix: "e" or "E", then a signed integer.
def Qty.exp(s: String) -> Maybe<&2, Sfx>:
  match s:
    case SNil{}:
      None{}
    case SCon{+c, t}:
      Qty.exp.if(Bool.or(Char.is_eq(c, 'e'), Char.is_eq(c, 'E')), t)

def Qty.find.if(hit: Bool, x: Sfx, rec: Maybe<&2, Sfx>) -> Maybe<&2, Sfx>:
  match hit:
    case True{}:
      Some{x}
    case False{}:
      rec

def Qty.find(+s: String, xs: List<&2, Sfx>) -> Maybe<&2, Sfx>:
  match xs:
    case Nil{}:
      Qty.exp(s)
    case Con{+x, r}:
      Qty.find.if(String.eq(Qty.sfx_name(x), s), x, Qty.find(s, r))

def Qty.parse.sfx(m: Maybe<&2, Sfx>, n: List<&2, U32>, f: Nat) -> Maybe<&2, Q>:
  match m:
    case None{}:
      None{}
    case Some{Sfx{name, k, p, q}}:
      Some{Q{n, k, p, Nat.add(q, f)}}

def Qty.parse.num(+s: String) -> Maybe<&2, Q>:
  +num = Qty.num_part(s)
  Qty.parse.sfx(Qty.find(Qty.suffix_part(s), Qty.sfxs()), Qty.digits(num, []), Qty.frac(num))

def Qty.parse.c(c: Char, t: String) -> Maybe<&2, Q>:
  match c:
    case '-':
      None{}
    case '+':
      Qty.parse.num(t)
    case Chr{x}:
      Qty.parse.num(SCon{Chr{x}, t})

# resource.ParseQuantity; None on an error or a negative quantity.
def Qty.parse(s: String) -> Maybe<&2, Q>:
  match s:
    case SNil{}:
      None{}
    case SCon{c, t}:
      Qty.parse.c(c, t)

def Qty.milli3(milli: Bool) -> Nat:
  match milli:
    case True{}:
      3n
    case False{}:
      0n

def Qty.value.m(m: Maybe<&2, Q>, milli: Bool) -> List<&2, U32>:
  match m:
    case None{}:
      Nil{}
    case Some{Q{n, k, p, q}}:
      Qty.scale(Qty.mul1024(k, n), Nat.add(p, Qty.milli3(milli)), q)

# Quantity.Value() (milli false) or MilliValue() (milli true), both
# rounded up; 0 for "" or a quantity that does not parse.
def Qty.value(s: String, milli: Bool) -> List<&2, U32>:
  Qty.value.m(Qty.parse(s), milli)

def Qty.digit(d: U32) -> Char:
  Chr{U32.add(d, 48)}

def Qty.show.put(skip: Bool, +d: U32, rec: String) -> String:
  match skip:
    case True{}:
      rec
    case False{}:
      SCon{Qty.digit(d), rec}

# Big-endian digits without the leading zeros.
def Qty.show.go(xs: List<&2, U32>, +lead: Bool) -> String:
  match xs:
    case Nil{}:
      SNil{}
    case Con{+d, r}:
      +skip = Bool.and(lead, U32.is_zero(d))
      Qty.show.put(skip, d, Qty.show.go(r, skip))

def Qty.show.nonempty(s: String) -> String:
  match s:
    case SNil{}:
      "0"
    case SCon{c, t}:
      SCon{c, t}

# The decimal text of a digit list.
def Qty.show(a: List<&2, U32>) -> String:
  Qty.show.nonempty(Qty.show.go(List.reverse(&2, U32, a), True{}))

def Qty.zero3(a: List<&2, U32>) -> Bool:
  match a:
    case Con{x, Con{y, Con{z, r}}}:
      Bool.and(U32.is_zero(x), Bool.and(U32.is_zero(y), U32.is_zero(z)))
    case _:
      False{}

def Qty.groups.if(hit: Bool, rec: Nat) -> Nat:
  match hit:
    case True{}:
      1n+rec
    case False{}:
      0n

# How many groups of three zero digits end a number, at most f.
def Qty.groups(f: Nat, +a: List<&2, U32>) -> Nat:
  match f:
    case 0n:
      0n
    case 1n+p:
      Qty.groups.if(Qty.zero3(a), Qty.groups(p, List.drop(&2, U32, a, 3n)))

def Qty.dec_suffix(g: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, ["", "k", "M", "G", "T", "P", "E"], g), "")

def Qty.bin_suffix(k: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, ["", "Ki", "Mi", "Gi", "Ti", "Pi", "Ei"], k), "")

def Qty.fmt_dec.if(zero: Bool, +a: List<&2, U32>) -> String:
  match zero:
    case True{}:
      "0"
    case False{}:
      +g = Qty.groups(6n, a)
      Qty.show(List.drop(&2, U32, a, Nat.mul(3n, g))) ++ Qty.dec_suffix(g)

# A whole number as a DecimalSI quantity (resource.NewQuantity(v,
# DecimalSI).String()): the zeros at the end in groups of three become k,
# M, G, T, P or E.
def Qty.fmt_dec(+a: List<&2, U32>) -> String:
  Qty.fmt_dec.if(Qty.is_zero(a), a)

def Qty.fmt_milli.if(whole: Bool, +m: List<&2, U32>) -> String:
  match whole:
    case True{}:
      Qty.fmt_dec(List.drop(&2, U32, m, 3n))
    case False{}:
      Qty.show(m) ++ "m"

# resource.NewMilliQuantity(m, DecimalSI).String().
def Qty.fmt_milli(+m: List<&2, U32>) -> String:
  Qty.fmt_milli.if(Qty.zero3(m), m)

def Qty.div.go(xs: List<&2, U32>, +r: U32, +d: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      acc
    case Con{x, t}:
      +cur = U32.add(U32.mul(r, 10), x)
      Qty.div.go(t, U32.mod(cur, d), d, U32.div(cur, d) <> acc)

def Qty.rem.go(xs: List<&2, U32>, +r: U32, +d: U32) -> U32:
  match xs:
    case Nil{}:
      r
    case Con{x, t}:
      Qty.rem.go(t, U32.mod(U32.add(U32.mul(r, 10), x), d), d)

# a / d and a % d, d a small number.
def Qty.div(a: List<&2, U32>, +d: U32) -> List<&2, U32>:
  Qty.div.go(List.reverse(&2, U32, a), 0, d, Nil{})

def Qty.rem(a: List<&2, U32>, +d: U32) -> U32:
  Qty.rem.go(List.reverse(&2, U32, a), 0, d)

def Qty.k1024.if(hit: Bool, rec: Nat) -> Nat:
  match hit:
    case True{}:
      1n+rec
    case False{}:
      0n

# How many times 1024 divides a, at most f.
def Qty.k1024(f: Nat, +a: List<&2, U32>) -> Nat:
  match f:
    case 0n:
      0n
    case 1n+p:
      Qty.k1024.if(Bool.and(Bool.not(Qty.is_zero(a)), U32.is_zero(Qty.rem(a, 1024))), Qty.k1024(p, Qty.div(a, 1024)))

def Qty.div_k(k: Nat, a: List<&2, U32>) -> List<&2, U32>:
  match k:
    case 0n:
      a
    case 1n+p:
      Qty.div_k(p, Qty.div(a, 1024))

def Qty.fmt_bin.if(small: Bool, +a: List<&2, U32>) -> String:
  match small:
    case True{}:
      Qty.fmt_dec(a)
    case False{}:
      +k = Qty.k1024(6n, a)
      Qty.show(Qty.div_k(k, a)) ++ Qty.bin_suffix(k)

# resource.NewQuantity(v, BinarySI).String(): below 1024 as DecimalSI,
# else the factors of 1024 as Ki, Mi, Gi, Ti, Pi or Ei.
def Qty.fmt_bin(+a: List<&2, U32>) -> String:
  Qty.fmt_bin.if(Cmp.is_lt(Qty.cmp(a, Qty.of_u32(10n, 1024))), a)

# Requests.

def Qty.req_zero() -> Reqs:
  Reqs{Nil{}, Nil{}, Nil{}}

def Qty.req_cpu(r: Reqs) -> List<&2, U32>:
  match r:
    case Reqs{c, m, e}:
      c

def Qty.req_mem(r: Reqs) -> List<&2, U32>:
  match r:
    case Reqs{c, m, e}:
      m

def Qty.req_eph(r: Reqs) -> List<&2, U32>:
  match r:
    case Reqs{c, m, e}:
      e

def Qty.req_add(a: Reqs, b: Reqs) -> Reqs:
  match a b:
    case Reqs{c1, m1, e1} Reqs{c2, m2, e2}:
      Reqs{Qty.add(c1, c2), Qty.add(m1, m2), Qty.add(e1, e2)}

def Qty.req_max(a: Reqs, b: Reqs) -> Reqs:
  match a b:
    case Reqs{c1, m1, e1} Reqs{c2, m2, e2}:
      Reqs{Qty.max(c1, c2), Qty.max(m1, m2), Qty.max(e1, e2)}

# The requests of a resource list (JSON object of quantities).
def Qty.req_of(+rs: J.Json) -> Reqs:
  Reqs{Qty.value(S.Svc.str(J.Json.get(rs, "cpu")), True{}), Qty.value(S.Svc.str(J.Json.get(rs, "memory")), False{}), Qty.value(S.Svc.str(J.Json.get(rs, "ephemeral-storage")), False{})}

def Qty.container_req(+c: J.Json) -> Reqs:
  Qty.req_of(J.Json.at(c, ["resources", "requests"]))

def Qty.sum_reqs(cs: List<&2, J.Json>) -> Reqs:
  match cs:
    case Nil{}:
      Qty.req_zero()
    case Con{c, r}:
      Qty.req_add(Qty.container_req(c), Qty.sum_reqs(r))

def Qty.init_step.if(always: Bool, +rs: Reqs, mx: Reqs, +r: Reqs) -> Init:
  match always:
    case True{}:
      +rs2 = Qty.req_add(rs, r)
      Init{rs2, Qty.req_max(mx, rs2)}
    case False{}:
      Init{rs, Qty.req_max(mx, Qty.req_add(r, rs))}

def Qty.init_step(st: Init, +c: J.Json) -> Init:
  match st:
    case Init{rs, mx}:
      Qty.init_step.if(String.eq(S.Svc.str(J.Json.get(c, "restartPolicy")), "Always"), rs, mx, Qty.container_req(c))

def Qty.init_fold(cs: List<&2, J.Json>, st: Init) -> Init:
  match cs:
    case Nil{}:
      st
    case Con{c, r}:
      Qty.init_fold(r, Qty.init_step(st, c))

def Qty.init_reqs(st: Init, cs: Reqs) -> Reqs:
  match st:
    case Init{rs, mx}:
      Qty.req_max(Qty.req_add(cs, rs), mx)

def Qty.override.if(set: Bool, s: String, milli: Bool, d: List<&2, U32>) -> List<&2, U32>:
  match set:
    case True{}:
      Qty.value(s, milli)
    case False{}:
      d

def Qty.override.one(+j: J.Json, milli: Bool, d: List<&2, U32>) -> List<&2, U32>:
  Qty.override.if(Bool.not(J.Json.is_null(j)), S.Svc.str(j), milli, d)

# Pod-level requests replace the CPU and memory of the containers.
def Qty.override(+rq: J.Json, r: Reqs) -> Reqs:
  match r:
    case Reqs{c, m, e}:
      Reqs{Qty.override.one(J.Json.get(rq, "cpu"), True{}, c), Qty.override.one(J.Json.get(rq, "memory"), False{}, m), e}

# resourceutil.PodRequests: the containers' requests plus the restartable
# init containers', or the largest init container's if larger; then the
# pod-level requests and the overhead.
def Qty.pod_requests(+p: J.Json) -> Reqs:
  +spec = J.Json.get(p, "spec")
  cs st = Qty.sum_reqs(J.Json.items(J.Json.get(spec, "containers"))) Qty.init_fold(J.Json.items(J.Json.get(spec, "initContainers")), Init{Qty.req_zero(), Qty.req_zero()})
  r1 = Qty.override(J.Json.at(spec, ["resources", "requests"]), Qty.init_reqs(st, cs))
  Qty.req_add(r1, Qty.req_of(J.Json.get(spec, "overhead")))

# Pods and the nodes they need.

def Node.pod_node(+p: J.Json) -> String:
  S.Svc.str(J.Json.at(p, ["spec", "nodeName"]))

def Node.is_ds_ref(+r: J.Json) -> Bool:
  Bool.and(String.eq(S.Svc.str(J.Json.get(r, "apiVersion")), "apps/v1"), String.eq(S.Svc.str(J.Json.get(r, "kind")), "DaemonSet"))

def Node.any_ds(rs: List<&2, J.Json>) -> Bool:
  match rs:
    case Nil{}:
      False{}
    case Con{r, t}:
      Bool.or(Node.is_ds_ref(r), Node.any_ds(t))

# A virtual pod counts when it has a node and no apps/v1 DaemonSet owner
# (filterOutVirtualDaemonSets).
def Node.v_live(+p: J.Json) -> Bool:
  Bool.and(Bool.not(String.is_empty(Node.pod_node(p))), Bool.not(Node.any_ds(J.Json.items(J.Json.at(p, ["metadata", "ownerReferences"])))))

# A host pod counts when it has a node and its owner-set-kind annotation
# is not DaemonSet (filterOutPhysicalDaemonSets).
def Node.h_live(+p: J.Json) -> Bool:
  Bool.and(Bool.not(String.is_empty(Node.pod_node(p))), Bool.not(String.eq(S.Svc.annotation(Node.owner_set_kind(), p), "DaemonSet")))

def Node.any_v(+name: String, ps: List<&2, J.Json>) -> Bool:
  match ps:
    case Nil{}:
      False{}
    case Con{+p, r}:
      Bool.or(Bool.and(Node.v_live(p), String.eq(name, Node.pod_node(p))), Node.any_v(name, r))

def Node.any_h(+name: String, ps: List<&2, J.Json>) -> Bool:
  match ps:
    case Nil{}:
      False{}
    case Con{+p, r}:
      Bool.or(Bool.and(Node.h_live(p), String.eq(name, Node.pod_node(p))), Node.any_h(name, r))

# isNodeNeededByPod: a virtual pod or a managed host pod on the node, not
# counting DaemonSet pods.
def Node.needed(+name: String, vpods: List<&2, J.Json>, hpods: List<&2, J.Json>) -> Bool:
  Bool.or(Node.any_v(name, vpods), Node.any_h(name, hpods))

def Node.keep_node(b: Bool, x: String, rest: +List<String>) -> +List<String>:
  match b:
    case True{}:
      x <> rest
    case False{}:
      rest

def Node.v_nodes(ps: List<&2, J.Json>) -> +List<String>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{+p, r}:
      Node.keep_node(Node.v_live(p), Node.pod_node(p), Node.v_nodes(r))

def Node.h_nodes(ps: List<&2, J.Json>) -> +List<String>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{+p, r}:
      Node.keep_node(Node.h_live(p), Node.pod_node(p), Node.h_nodes(r))

# The node names of the synced pods that count (virtual, then host).
def Node.pod_nodes(vpods: List<&2, J.Json>, hpods: List<&2, J.Json>) -> +List<String>:
  M.Meta.cat(Node.v_nodes(vpods), Node.h_nodes(hpods))

# Real nodes.

def Node.has_value(+k: String, v: String, +labels: +List<M.KV>) -> Bool:
  M.Meta.maybe_is(M.Meta.get(k, labels), v)

# labels.Set(sel).AsSelector().Matches(labels).
def Node.sel_match(sel: +List<M.KV>, +labels: +List<M.KV>) -> Bool:
  match sel:
    case Nil{}:
      True{}
    case Con{M.KV{k, v}, r}:
      Bool.and(Node.has_value(k, v, labels), Node.sel_match(r, labels))

def Node.should_sync.labels(ls: +List<M.KV>, +h: J.Json, +vpods: List<&2, J.Json>, +hpods: List<&2, J.Json>) -> Bool:
  match ls:
    case Nil{}:
      Node.needed(S.Svc.name(h), vpods, hpods)
    case Con{x, r}:
      Node.sel_match(x <> r, S.Svc.labels(h))

def Node.should_sync.sel(sel: Selector, +h: J.Json, +vpods: List<&2, J.Json>, +hpods: List<&2, J.Json>) -> Bool:
  match sel:
    case SelNone{}:
      Node.needed(S.Svc.name(h), vpods, hpods)
    case SelAll{}:
      True{}
    case SelLabels{ls}:
      Node.should_sync.labels(ls, h, vpods, hpods)

# nodeSyncer.shouldSync: with a selector (all, or non-empty labels) the
# node syncs exactly when it matches (enforceNodeSelector is always true);
# without one, when a pod needs it.
def Node.should_sync(+o: Opts, +h: J.Json, +vpods: List<&2, J.Json>, +hpods: List<&2, J.Json>) -> Bool:
  Node.should_sync.sel(Node.selector(o), h, vpods, hpods)

def Node.addr(t: String, a: String) -> J.Json:
  J.Json.obj([J.KV{"address", J.JStr{a}}, J.KV{"type", J.JStr{t}}])

def Node.opt_addr(b: Bool, t: String, a: String) -> List<&2, J.Json>:
  match b:
    case True{}:
      [Node.addr(t, a)]
    case False{}:
      []

def Node.internal(+t: String) -> Bool:
  Bool.or(String.eq(t, "InternalIP"), Bool.or(String.eq(t, "InternalDNS"), String.eq(t, "Hostname")))

def Node.other_addrs.if(drop: Bool, a: J.Json, rec: List<&2, J.Json>) -> List<&2, J.Json>:
  match drop:
    case True{}:
      rec
    case False{}:
      a <> rec

# The addresses that are not InternalIP, InternalDNS or Hostname.
def Node.other_addrs(xs: List<&2, J.Json>) -> List<&2, J.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+a, r}:
      Node.other_addrs.if(Node.internal(S.Svc.str(J.Json.get(a, "type"))), a, Node.other_addrs(r))

def Node.daemon_endpoints() -> J.Json:
  J.Json.obj([J.KV{"kubeletEndpoint", J.Json.obj([J.KV{"Port", Node.kubelet_port()}])}])

def Node.kubelets.if(fake: Bool, +o: Opts, +ip: String, +name: String, +st: J.Json) -> J.Json:
  match fake:
    case True{}:
      +hn = Node.opt_addr(Node.by_hostname(o), "Hostname", Node.host(name))
      +ipa = Node.opt_addr(Node.by_ip(o), "InternalIP", ip)
      addrs = List.append(&2, J.Json, hn, List.append(&2, J.Json, ipa, Node.other_addrs(J.Json.items(J.Json.get(st, "addresses")))))
      S.Svc.put(S.Svc.put(st, "daemonEndpoints", Node.daemon_endpoints()), "addresses", J.Json.arr(addrs))
    case False{}:
      st

def Node.running(+p: J.Json) -> Bool:
  +phase = S.Svc.str(J.Json.at(p, ["status", "phase"]))
  Bool.not(Bool.or(String.eq(phase, "Succeeded"), String.eq(phase, "Failed")))

# A host pod in the virtual scheduler's pod cache on this node: not
# vcluster's (managed-by is not the vcluster name), running, on the node.
def Node.alloc_counts(+vc: String, +name: String, +p: J.Json) -> Bool:
  +mine = String.eq(M.Meta.lookup(M.Meta.marker_label(), S.Svc.labels(p)), vc)
  +node = Node.pod_node(p)
  Bool.and(Bool.not(mine), Bool.and(Node.running(p), Bool.and(Bool.not(String.is_empty(node)), String.eq(node, name))))

def Node.pod_req.if(b: Bool, +p: J.Json) -> Reqs:
  match b:
    case True{}:
      Qty.pod_requests(p)
    case False{}:
      Qty.req_zero()

def Node.pod_sum(+vc: String, +name: String, pods: List<&2, J.Json>) -> Reqs:
  match pods:
    case Nil{}:
      Qty.req_zero()
    case Con{+p, r}:
      Qty.req_add(Node.pod_req.if(Node.alloc_counts(vc, name, p), p), Node.pod_sum(vc, name, r))

def Node.set_if(b: Bool, k: String, v: String, m: +List<M.KV>) -> +List<M.KV>:
  match b:
    case True{}:
      M.Meta.insert(k, v, m)
    case False{}:
      m

# The allocatable left after the pods' requests, each written only when
# positive; pods are not reduced (the mirror mapper's IsManaged quirk).
def Node.apply_alloc.go(+a: +List<M.KV>, +c: List<&2, U32>, +m: List<&2, U32>, +e: List<&2, U32>) -> +List<M.KV>:
  +cpu = Qty.value(M.Meta.lookup("cpu", a), True{})
  +mem = Qty.value(M.Meta.lookup("memory", a), False{})
  +eph = Qty.value(M.Meta.lookup("ephemeral-storage", a), False{})
  +pods = Qty.value(M.Meta.lookup("pods", a), False{})
  a1 = Node.set_if(Bool.not(Qty.is_zero(pods)), "pods", Qty.fmt_dec(pods), a)
  a2 = Node.set_if(Qty.gt(cpu, c), "cpu", Qty.fmt_milli(Qty.sub(cpu, c)), a1)
  a3 = Node.set_if(Qty.gt(mem, m), "memory", Qty.fmt_bin(Qty.sub(mem, m)), a2)
  Node.set_if(Qty.gt(eph, e), "ephemeral-storage", Qty.fmt_bin(Qty.sub(eph, e)), a3)

def Node.apply_alloc(+a: +List<M.KV>, sum: Reqs) -> +List<M.KV>:
  match sum:
    case Reqs{c, m, e}:
      Node.apply_alloc.go(a, c, m, e)

def Node.alloc.if(m: Maybe<&2, List<&2, M.KV>>, sum: Reqs) -> Maybe<&2, List<&2, M.KV>>:
  match m:
    case None{}:
      None{}
    case Some{a}:
      Some{Node.apply_alloc(a, sum)}

# The virtual scheduler's capacity and allocatable: the allocatable less
# the requests of the non-vcluster pods, both merged over the virtual
# node's (host values win), allocatable keys not in capacity dropped and
# missing ones taken from capacity.
def Node.recalc(+vc: String, +name: String, +vst: J.Json, pods: List<&2, J.Json>, +st: J.Json) -> J.Json:
  a1 = Node.alloc.if(S.Svc.mmap(J.Json.get(st, "allocatable")), Node.pod_sum(vc, name, pods))
  +cap = M.Meta.union(S.Svc.map(J.Json.get(st, "capacity")), S.Svc.map(J.Json.get(vst, "capacity")))
  al = M.Meta.union(M.Meta.maybe_map(a1), S.Svc.map(J.Json.get(vst, "allocatable")))
  al2 = M.Meta.union(M.Meta.keep_in(al, M.Meta.keys(cap), []), cap)
  S.Svc.put(S.Svc.put(st, "capacity", S.Svc.render(cap)), "allocatable", S.Svc.render(al2))

def Node.sched.if(on: Bool, +vc: String, +name: String, +vst: J.Json, pods: List<&2, J.Json>, +st: J.Json) -> J.Json:
  match on:
    case True{}:
      Node.recalc(vc, name, vst, pods, st)
    case False{}:
      st

def Node.images.if(clear: Bool, +st: J.Json) -> J.Json:
  match clear:
    case True{}:
      S.Svc.put(st, "images", J.Json.arr([]))
    case False{}:
      st

# nodes translateUpdateStatus: the host status; with fake kubelets
# (byHostname or byIP) the kubelet port 10250 and the vcluster addresses
# first; with the virtual scheduler the capacity and allocatable
# recalculated; with clearImageStatus no images.
def Node.status(+c: S.Cfg, +o: Opts, +ip: String, +h: J.Json, +v: J.Json, pods: List<&2, J.Json>) -> J.Json:
  s1 = Node.kubelets.if(Bool.or(Node.by_hostname(o), Node.by_ip(o)), o, ip, S.Svc.name(v), J.Json.get(h, "status"))
  s2 = Node.sched.if(Node.scheduler(o), S.Svc.vc(c), S.Svc.name(h), J.Json.get(v, "status"), pods, s1)
  Node.images.if(Node.clear_images(o), s2)

# The virtual node Sync makes: status and backwards translation (in
# parallel, they touch different fields), then the managed-by marker label.
def Node.updated(+c: S.Cfg, +o: Opts, +ip: String, +h: J.Json, +v: J.Json, pods: List<&2, J.Json>) -> J.Json:
  st bk = Node.status(c, o, ip, h, v, pods) Node.backwards(o, h, v)
  +v1 = J.Json.set(bk, "status", st)
  S.Svc.put_in(v1, "metadata", "labels", S.Svc.render(M.Meta.insert(M.Meta.marker_label(), S.Svc.vc(c), S.Svc.labels(v1))))

def Node.sync.if(ok: Bool, +c: S.Cfg, +o: Opts, +ip: String, +h: J.Json, +v: J.Json, pods: List<&2, J.Json>) -> S.Outcome:
  match ok:
    case False{}:
      S.Svc.done([S.VirtualDelete{"", S.Svc.name(v)}])
    case True{}:
      +v2 = Node.updated(c, o, ip, h, v, pods)
      S.Svc.done(S.Svc.update.if(S.Svc.eq(v, v2), S.VirtualUpdate{v2}, []))

# nodeSyncer Sync: both nodes exist. A node that should not sync loses its
# virtual node; else the virtual node takes the host status, spec, labels,
# annotations and taints, and the managed-by label.
def Node.sync(+c: S.Cfg, +o: Opts, +ip: String, +h: J.Json, +v: J.Json, +vpods: List<&2, J.Json>, +hpods: List<&2, J.Json>, pods: List<&2, J.Json>) -> S.Outcome:
  Node.sync.if(Node.should_sync(o, h, vpods, hpods), c, o, ip, h, v, pods)

# The virtual node SyncToVirtual creates: name, host labels, host
# annotations.
def Node.new_virtual(+h: J.Json) -> J.Json:
  J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.Json.at(h, ["metadata", "name"])}, J.KV{"labels", J.Json.at(h, ["metadata", "labels"])}, J.KV{"annotations", J.Json.at(h, ["metadata", "annotations"])}])}])

def Node.stv.if(ok: Bool, +h: J.Json) -> S.Outcome:
  match ok:
    case True{}:
      S.Outcome{[S.VirtualCreate{Node.new_virtual(h)}], S.RequeueNow{}}
    case False{}:
      S.Svc.done([])

# nodeSyncer SyncToVirtual: the host node exists, the virtual one does not.
def Node.sync_to_virtual(+o: Opts, +h: J.Json, +vpods: List<&2, J.Json>, +hpods: List<&2, J.Json>) -> S.Outcome:
  Node.stv.if(Node.should_sync(o, h, vpods, hpods), h)

def Node.sth.if(del: Bool, +v: J.Json) -> S.Outcome:
  match del:
    case True{}:
      S.Svc.done([S.VirtualDelete{"", S.Svc.name(v)}])
    case False{}:
      S.Svc.done([])

# nodeSyncer SyncToHost: the virtual node exists, the host one does not.
# It goes when the host node was seen (host_old) or vcluster made it (its
# managed-by label is the vcluster name).
def Node.sync_to_host(+c: S.Cfg, host_old: Maybe<&2, J.Json>, +v: J.Json) -> S.Outcome:
  Node.sth.if(Bool.or(Maybe.is_some(&2, J.Json, host_old), String.eq(M.Meta.lookup(M.Meta.marker_label(), S.Svc.labels(v)), S.Svc.vc(c))), v)

# Fake nodes.

def Node.fake_labels(+f: Fake, +name: String) -> J.Json:
  +arch = Node.fake_arch(f)
  J.Json.obj([J.KV{"vcluster.loft.sh/fake-node", J.JStr{"true"}}, J.KV{"beta.kubernetes.io/arch", J.JStr{arch}},
    J.KV{"beta.kubernetes.io/os", J.JStr{"linux"}}, J.KV{"kubernetes.io/arch", J.JStr{arch}},
    J.KV{"kubernetes.io/hostname", J.JStr{N.Names.safe_concat(["fake", name])}}, J.KV{"kubernetes.io/os", J.JStr{"linux"}}])

def Node.fake_annotations() -> J.Json:
  J.Json.obj([J.KV{"node.alpha.kubernetes.io/ttl", J.JStr{"0"}}, J.KV{"volumes.kubernetes.io/controller-managed-attach-detach", J.JStr{"false"}}])

def Node.fake_resources() -> J.Json:
  J.Json.obj([J.KV{"cpu", J.JStr{"16"}}, J.KV{"memory", J.JStr{"32Gi"}}, J.KV{"ephemeral-storage", J.JStr{"100Gi"}},
    J.KV{"hugepages-1Gi", J.JStr{"0"}}, J.KV{"hugepages-2Mi", J.JStr{"0"}}, J.KV{"pods", J.JStr{"110"}}])

def Node.condition(+now: String, t: String, status: String, reason: String, message: String) -> J.Json:
  J.Json.obj([J.KV{"type", J.JStr{t}}, J.KV{"status", J.JStr{status}}, J.KV{"lastHeartbeatTime", J.JStr{now}},
    J.KV{"lastTransitionTime", J.JStr{now}}, J.KV{"reason", J.JStr{reason}}, J.KV{"message", J.JStr{message}}])

def Node.fake_conditions(+now: String) -> J.Json:
  J.Json.arr([Node.condition(now, "MemoryPressure", "False", "KubeletHasSufficientMemory", "kubelet has sufficient memory available"),
    Node.condition(now, "DiskPressure", "False", "KubeletHasNoDiskPressure", "kubelet has no disk pressure"),
    Node.condition(now, "PIDPressure", "False", "KubeletHasSufficientPID", "kubelet has sufficient PID available"),
    Node.condition(now, "Ready", "True", "KubeletReady", "kubelet is posting ready status")])

def Node.fake_info(+f: Fake) -> J.Json:
  J.Json.obj([J.KV{"architecture", J.JStr{"amd64"}}, J.KV{"bootID", J.JStr{Node.fake_boot(f)}},
    J.KV{"containerRuntimeVersion", J.JStr{"docker://19.3.12"}}, J.KV{"kernelVersion", J.JStr{"4.19.76-fakelinux"}},
    J.KV{"kubeProxyVersion", J.JStr{Node.fake_version()}}, J.KV{"kubeletVersion", J.JStr{Node.fake_version()}},
    J.KV{"machineID", J.JStr{Node.fake_machine(f)}}, J.KV{"systemUUID", J.JStr{Node.fake_system(f)}},
    J.KV{"operatingSystem", J.JStr{"linux"}}, J.KV{"osImage", J.JStr{"Fake Kubernetes Image"}}])

def Node.fake_status(+f: Fake, +name: String, +ip: String) -> J.Json:
  +addrs = List.append(&2, J.Json, Node.opt_addr(Node.fake_by_hostname(f), "Hostname", Node.host(name)), Node.opt_addr(Node.fake_by_ip(f), "InternalIP", ip))
  J.Json.obj([J.KV{"capacity", Node.fake_resources()}, J.KV{"allocatable", Node.fake_resources()},
    J.KV{"conditions", Node.fake_conditions(Node.fake_now(f))}, J.KV{"addresses", J.Json.arr(addrs)},
    J.KV{"daemonEndpoints", Node.daemon_endpoints()}, J.KV{"nodeInfo", Node.fake_info(f)}, J.KV{"images", J.Json.arr([])}])

# The fake node createFakeNode makes (its status and its empty taints are
# written after the create, through the status subresource and a patch).
def Node.fake_node(+f: Fake, +name: String, +ip: String) -> J.Json:
  J.Json.obj([J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{name}}, J.KV{"labels", Node.fake_labels(f, name)}, J.KV{"annotations", Node.fake_annotations()}])},
    J.KV{"spec", J.Json.obj([J.KV{"taints", J.Json.arr([])}])},
    J.KV{"status", Node.fake_status(f, name, ip)}])

# The addresses updateIfNeeded wants: the hostname always, the IP with
# byIP.
def Node.fake_addresses(+f: Fake, +name: String, +ip: String) -> J.Json:
  J.Json.arr(Node.addr("Hostname", Node.host(name)) <> Node.opt_addr(Node.fake_by_ip(f), "InternalIP", ip))

def Node.put_status(+n: J.Json, +k: String, +v: J.Json) -> J.Json:
  S.Svc.put_in(n, "status", k, v)

# fakeNodeSyncer updateIfNeeded: a status update when the addresses differ.
def Node.fake_update(+f: Fake, +name: String, +ip: String, +n: J.Json) -> S.Outcome:
  S.Svc.done(S.Svc.update.if(S.Svc.eq(J.Json.at(n, ["status", "addresses"]), Node.fake_addresses(f, name, ip)), S.VirtualUpdate{Node.put_status(n, "addresses", Node.fake_addresses(f, name, ip))}, []))

def Node.fake_step.if(needed: Bool, +f: Fake, +name: String, +ip: String, node: Maybe<&2, J.Json>) -> S.Outcome:
  match needed node:
    case True{} None{}:
      S.Svc.done([S.VirtualCreate{Node.fake_node(f, name, ip)}])
    case True{} Some{n}:
      Node.fake_update(f, name, ip, n)
    case False{} None{}:
      S.Svc.done([])
    case False{} Some{n}:
      S.Svc.done([S.VirtualDelete{"", name}])

# The fake node syncer for node `name`, whose virtual node is `node` (None
# when there is none): FakeSyncToVirtual creates the node when a pod needs
# it, FakeSync deletes it when none does, else fixes its addresses.
def Node.fake_step(+f: Fake, +name: String, +ip: String, node: Maybe<&2, J.Json>, +vpods: List<&2, J.Json>, +hpods: List<&2, J.Json>) -> S.Outcome:
  Node.fake_step.if(Node.needed(name, vpods, hpods), f, name, ip, node)

# fakeNodeSyncer FakeSyncToVirtual(name).
def Node.fake_sync_to_virtual(+f: Fake, +name: String, +ip: String, +vpods: List<&2, J.Json>, +hpods: List<&2, J.Json>) -> S.Outcome:
  Node.fake_step(f, name, ip, None{}, vpods, hpods)

# fakeNodeSyncer FakeSync(node).
def Node.fake_sync(+f: Fake, +ip: String, +n: J.Json, +vpods: List<&2, J.Json>, +hpods: List<&2, J.Json>) -> S.Outcome:
  Node.fake_step(f, S.Svc.name(n), ip, Some{n}, vpods, hpods)

def Node.hit(b: Bool, prev: Bool) -> Bool:
  match b:
    case True{}:
      True{}
    case False{}:
      prev

def Node.miss(b: Bool, prev: Bool) -> Bool:
  match b:
    case True{}:
      False{}
    case False{}:
      prev

def Node.after_one(+name: String, prev: Bool, w: S.Write) -> Bool:
  match w:
    case S.VirtualCreate{o}:
      Node.hit(String.eq(S.Svc.name(o), name), prev)
    case S.VirtualDelete{ns, n}:
      Node.miss(String.eq(n, name), prev)
    case _:
      prev

def Node.after(ws: List<&2, S.Write>, +name: String, prev: Bool) -> Bool:
  match ws:
    case Nil{}:
      prev
    case Con{w, r}:
      Node.after(r, name, Node.after_one(name, prev, w))

# Whether virtual node `name` exists after the writes of an outcome, from
# whether it existed before (node).
def Node.exists_after(+name: String, node: Maybe<&2, J.Json>, o: S.Outcome) -> Bool:
  match o:
    case S.Outcome{ws, rq}:
      Node.after(ws, name, Maybe.is_some(&2, J.Json, node))

# Events.

# constants.SyncResourceAnnotation.
def Ev.force_annotation() -> String:
  "vcluster.loft.sh/force-sync"

# resources.ForceSyncedEventNamespace.
def Ev.force_namespace() -> String:
  "default"

def Ev.kinds() -> +List<String>:
  ["Pod", "Service", "Endpoint", "Secret", "ConfigMap"]

# The involved object's kind is one of resources.AcceptedKinds: core v1
# Pod, Service, "Endpoint", Secret or ConfigMap.
def Ev.accepted(+h: J.Json) -> Bool:
  +io = J.Json.get(h, "involvedObject")
  +av = S.Svc.str(J.Json.get(io, "apiVersion"))
  Bool.and(Bool.or(String.eq(av, "v1"), String.eq(av, "/v1")), M.Meta.elem(S.Svc.str(J.Json.get(io, "kind")), Ev.kinds()))

def Ev.is_forced(+h: J.Json) -> Bool:
  String.eq(S.Svc.annotation(Ev.force_annotation(), h), "true")

def Ev.event_name.if(b: Bool, hn: String, +pin: String, vn: String) -> String:
  match b:
    case True{}:
      vn ++ String.drop(hn, String.length(pin))
    case False{}:
      hn

# HostEventNameToVirtual: a host event name that starts with the host
# involved object's name starts with the virtual one's instead.
def Ev.event_name(+hn: String, +pin: String, vn: String) -> String:
  Ev.event_name.if(String.starts_with(hn, pin), hn, pin, vn)

def Ev.interleave(s: String, +new: String) -> String:
  match s:
    case SNil{}:
      new
    case SCon{c, t}:
      new ++ SCon{c, Ev.interleave(t, new)}

def Ev.hits(s: String, +old: String) -> List<&2, Bool>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{+c, +t}:
      String.starts_with(SCon{c, t}, old) <> Ev.hits(t, old)

def Ev.rep.go2(skip: Nat, hit: Bool, out: String, c: Char, +m: Nat, +new: String) -> Rep:
  match skip hit:
    case 1n+k _:
      Rep{out, k}
    case 0n True{}:
      Rep{out ++ new, m}
    case 0n False{}:
      Rep{out ++ SCon{c, SNil{}}, 0n}

def Ev.rep.step(st: Rep, hit: Bool, c: Char, +m: Nat, +new: String) -> Rep:
  match st:
    case Rep{out, skip}:
      Ev.rep.go2(skip, hit, out, c, m, new)

def Ev.rep.out(st: Rep) -> String:
  match st:
    case Rep{out, skip}:
      out

def Ev.rep.go(cs: String, hs: List<&2, Bool>, st: Rep, +m: Nat, +new: String) -> String:
  match cs hs:
    case SCon{c, t} Con{h, r}:
      Ev.rep.go(t, r, Ev.rep.step(st, h, c, m, new), m, new)
    case _ _:
      Ev.rep.out(st)

# strings.ReplaceAll(s, old, new); an empty old puts new around every char.
def Ev.replace_all(+s: String, old: String, +new: String) -> String:
  match old:
    case SNil{}:
      Ev.interleave(s, new)
    case SCon{+o, +ot}:
      Ev.rep.go(s, Ev.hits(s, SCon{o, ot}), Rep{"", 0n}, String.length(ot), new)

# The message with "<ns>/<name>" and then <name> of the host involved
# object replaced by the virtual one's.
def Ev.message(msg: String, pns: String, +pname: String, +vns: String, +vname: String) -> String:
  Ev.replace_all(Ev.replace_all(msg, pns ++ "/" ++ pname, vns ++ "/" ++ vname), pname, vname)

def Ev.members(j: J.Json) -> J.Json:
  match j:
    case J.JObj{ms}:
      ms
    case _:
      J.JNil{}

# The members of a host event that translateEvent copies as they are.
def Ev.others(+h: J.Json) -> J.Json:
  Ev.members(S.Svc.del_all(["involvedObject", "metadata", "message", "kind", "apiVersion"], h))

# The involved object pointing at virtual object v.
def Ev.involved(+hio: J.Json, +v: J.Json) -> J.Json:
  J.JObj{J.JMem{"namespace", S.Svc.sj(S.Svc.namespace(v)), J.JMem{"name", S.Svc.sj(S.Svc.name(v)),
    J.JMem{"uid", S.Svc.sj(S.Svc.str(J.Json.at(v, ["metadata", "uid"]))), J.JMem{"resourceVersion", S.Svc.sj(S.Svc.str(J.Json.at(v, ["metadata", "resourceVersion"]))),
    Ev.members(S.Svc.del_all(["namespace", "name", "uid", "resourceVersion"], hio))}}}}}

# The metadata ResetObjectMetadata leaves of an object.
def Ev.reset(+h: J.Json) -> J.Json:
  S.Svc.del_all(S.Svc.reset_keys(), J.Json.get(h, "metadata"))

# events translateEvent(pEvent, vEvent): the host event with its involved
# object, name and message pointing at virtual object v, the metadata md
# and type meta (kind, apiVersion) of tm, in v's namespace.
def Ev.translate(+h: J.Json, md: J.Json, +tm: J.Json, +v: J.Json) -> J.Json:
  +hio = J.Json.get(h, "involvedObject")
  +pname = S.Svc.str(J.Json.get(hio, "name"))
  +vns = S.Svc.namespace(v)
  +vname = S.Svc.name(v)
  inv msg = Ev.involved(hio, v) Ev.message(S.Svc.str(J.Json.get(h, "message")), S.Svc.str(J.Json.get(hio, "namespace")), pname, vns, vname)
  md1 = S.Svc.put(S.Svc.put(md, "namespace", S.Svc.sj(vns)), "name", S.Svc.sj(Ev.event_name(S.Svc.name(h), pname, vname)))
  J.JObj{J.JMem{"involvedObject", inv, J.JMem{"metadata", md1, J.JMem{"message", S.Svc.sj(msg),
    J.JMem{"kind", J.Json.get(tm, "kind"), J.JMem{"apiVersion", J.Json.get(tm, "apiVersion"), Ev.others(h)}}}}}}

# events forceTranslateEvent: the host event in namespace default with
# the metadata md (without the force-sync annotation), the type meta of tm
# and an involved object that names only the namespace.
def Ev.forced(+h: J.Json, md: J.Json, +tm: J.Json) -> J.Json:
  +md1 = S.Svc.put(md, "namespace", J.JStr{Ev.force_namespace()})
  md2 = S.Svc.put(md1, "annotations", J.Json.del(J.Json.get(md1, "annotations"), Ev.force_annotation()))
  J.JObj{J.JMem{"involvedObject", J.Json.obj([J.KV{"namespace", J.JStr{Ev.force_namespace()}}]), J.JMem{"metadata", md2,
    J.JMem{"message", J.Json.get(h, "message"), J.JMem{"kind", J.Json.get(tm, "kind"), J.JMem{"apiVersion", J.Json.get(tm, "apiVersion"), Ev.others(h)}}}}}}

def Ev.create_if(live: Bool, e: J.Json) -> List<&2, S.Write>:
  match live:
    case True{}:
      [S.VirtualCreate{e}]
    case False{}:
      []

# The create of SyncToVirtual for involved virtual object v, made only when
# v's namespace exists and is not terminating.
def Ev.create(+h: J.Json, +v: J.Json, +live: +List<String>) -> S.Outcome:
  S.Outcome{Ev.create_if(M.Meta.elem(S.Svc.namespace(v), live), Ev.translate(h, Ev.reset(h), h, v)), S.NoRequeue{}}

def Ev.stv.force(forced: Bool, +h: J.Json, +live: +List<String>) -> S.Outcome:
  match forced:
    case True{}:
      S.Outcome{Ev.create_if(M.Meta.elem(Ev.force_namespace(), live), Ev.forced(h, Ev.reset(h), h)), S.NoRequeue{}}
    case False{}:
      S.Svc.done([])

def Ev.stv.if(ok: Bool, +h: J.Json, found: Maybe<&2, J.Json>, +live: +List<String>) -> S.Outcome:
  match ok found:
    case True{} Some{v}:
      Ev.create(h, v, live)
    case _ _:
      Ev.stv.force(Ev.is_forced(h), h, live)

# eventSyncer SyncToVirtual: a host event without a virtual one. found is
# the virtual object the involved object maps to (None when it maps to
# none or is missing); live lists the virtual namespaces that exist and are
# not terminating. An event whose kind is not accepted or whose object is
# missing is created only when it carries vcluster.loft.sh/force-sync:
# "true".
def Ev.sync_to_virtual(+h: J.Json, found: Maybe<&2, J.Json>, +live: +List<String>) -> S.Outcome:
  Ev.stv.if(Ev.accepted(h), h, found, live)

def Ev.update(+e: J.Json, +ve: J.Json) -> S.Outcome:
  S.Svc.done(S.Svc.update.if(S.Svc.eq(ve, e), S.VirtualUpdate{e}, []))

def Ev.sync.force(forced: Bool, +h: J.Json, +ve: J.Json) -> S.Outcome:
  match forced:
    case True{}:
      Ev.update(Ev.forced(h, J.Json.get(ve, "metadata"), ve), ve)
    case False{}:
      S.Svc.done([])

def Ev.sync.if(ok: Bool, +h: J.Json, found: Maybe<&2, J.Json>, +ve: J.Json) -> S.Outcome:
  match ok found:
    case True{} Some{v}:
      Ev.update(Ev.translate(h, J.Json.get(ve, "metadata"), ve, v), ve)
    case _ _:
      Ev.sync.force(Ev.is_forced(h), h, ve)

# eventSyncer Sync: host event h and its virtual event ve both exist; the
# virtual event takes the host event's fields and keeps its metadata.
def Ev.sync(+h: J.Json, found: Maybe<&2, J.Json>, +ve: J.Json) -> S.Outcome:
  Ev.sync.if(Ev.accepted(h), h, found, ve)

# eventSyncer SyncToHost: nothing (Kubernetes removes old events).
def Ev.sync_to_host() -> S.Outcome:
  S.Svc.done([])

def Ev.ref.force(forced: Bool, +h: J.Json) -> String & String:
  match forced:
    case True{}:
      (Ev.force_namespace(), S.Svc.name(h))
    case False{}:
      ("", "")

def Ev.ref.if(ok: Bool, +h: J.Json, found: Maybe<&2, J.Json>) -> String & String:
  match ok found:
    case True{} Some{+v}:
      (S.Svc.namespace(v), Ev.event_name(S.Svc.name(h), S.Svc.str(J.Json.at(h, ["involvedObject", "name"])), S.Svc.name(v)))
    case _ _:
      Ev.ref.force(Ev.is_forced(h), h)

# eventMapper HostToVirtual: the virtual (namespace, name) of a host event,
# ("", "") when it has none (the event is not managed).
def Ev.virtual_ref(+h: J.Json, found: Maybe<&2, J.Json>) -> String & String:
  Ev.ref.if(Ev.accepted(h), h, found)

def Ev.refers_one(+e: J.Json, +v: J.Json) -> Bool:
  Bool.and(String.eq(S.Svc.str(J.Json.at(e, ["involvedObject", "namespace"])), S.Svc.namespace(v)),
    String.eq(S.Svc.str(J.Json.at(e, ["involvedObject", "name"])), S.Svc.name(v)))

def Ev.refers_w(w: S.Write, +v: J.Json) -> Bool:
  match w:
    case S.VirtualCreate{e}:
      Ev.refers_one(e, v)
    case S.VirtualUpdate{e}:
      Ev.refers_one(e, v)
    case _:
      False{}

def Ev.refers_ws(ws: List<&2, S.Write>, +v: J.Json) -> Bool:
  match ws:
    case Nil{}:
      True{}
    case Con{w, r}:
      Bool.and(Ev.refers_w(w, v), Ev.refers_ws(r, v))

# True when every write of an outcome is a virtual event whose involved
# object is v (same namespace and name).
def Ev.refers(o: S.Outcome, +v: J.Json) -> Bool:
  match o:
    case S.Outcome{ws, rq}:
      Ev.refers_ws(ws, v)
