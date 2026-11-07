import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import bend-kube-runtime@0.2.0.0/src/yaml.bend as Y

# `vk8s connect` and `vk8s delete --delete-context` on a kubeconfig
# (vcluster pkg/cli/connect_docker.go exchangeContextName and
# writeKubeConfig, pkg/util/clihelper UpdateKubeConfig, pkg/cli/delete_helm.go
# deleteContext). Pure: host/vk8s.bend reads and writes the files.
#
# A kubeconfig is read with bend-kube's YAML reader into Kc: its clusters,
# contexts and users as named entries (each entry's body is the inner
# cluster, context or user object), its current-context and its
# preferences. Every other top-level field is dropped. It is written back
# in clientcmd.Write's layout: apiVersion, clusters, contexts,
# current-context, kind, preferences, users; an empty list is `null`.
#
# vcluster quirks, as encoded here:
# - connect uses the first cluster and the first user of the vCluster's
#   kubeconfig (vcluster: whichever its map iteration picks) and makes a
#   new context {cluster: NAME, user: NAME} (clientcmdapi.NewContext).
# - an entry of the same name is replaced, the others are kept in order;
#   the new entry goes last (clientcmd.Write sorts by name instead).
# - delete-context removes the context, then its user and its cluster when
#   no other context uses them; when it was the current context, the first
#   remaining context becomes current (vcluster: a random one), or "".

type Ent is Data:
  Ent{name: String, body: J.Json}

type Kc is Data:
  Kc{clusters: List<&2, Ent>, contexts: List<&2, Ent>, users: List<&2, Ent>, current: String, preferences: J.Json}

type Ents is Data:
  Ents{clusters: List<&2, Ent>, contexts: List<&2, Ent>, users: List<&2, Ent>}

# vcluster's docker driver names the context vcluster-docker_NAME; vk8s
# names it vk8s_NAME.
def Kubeconfig.context_name(+name: String) -> String:
  "vk8s_" ++ name

# Entry lists
# -----------

def Kubeconfig.has(xs: List<&2, Ent>, +n: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{Ent{k, b}, t}:
      Bool.or(String.eq(k, n), Kubeconfig.has(t, n))

def Kubeconfig.del.if(+k: String, b: J.Json, rest: List<&2, Ent>, hit: Bool) -> List<&2, Ent>:
  match hit:
    case True{}:
      rest
    case False{}:
      Ent{k, b} <> rest

# Removes every entry named n.
def Kubeconfig.del(xs: List<&2, Ent>, +n: String) -> List<&2, Ent>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{Ent{+k, b}, t}:
      Kubeconfig.del.if(k, b, Kubeconfig.del(t, n), String.eq(k, n))

# Sets entry n: the old one goes, the new one is last.
def Kubeconfig.put(xs: List<&2, Ent>, +n: String, b: J.Json) -> List<&2, Ent>:
  List.append(&2, Ent, Kubeconfig.del(xs, n), [Ent{n, b}])

def Kubeconfig.find.if(b: J.Json, rest: Maybe<&2, J.Json>, hit: Bool) -> Maybe<&2, J.Json>:
  match hit:
    case True{}:
      Some{b}
    case False{}:
      rest

# The body of the first entry named n.
def Kubeconfig.find(xs: List<&2, Ent>, +n: String) -> Maybe<&2, J.Json>:
  match xs:
    case Nil{}:
      None{}
    case Con{Ent{k, b}, t}:
      Kubeconfig.find.if(b, Kubeconfig.find(t, n), String.eq(k, n))

# A string field of an entry body ("" when absent).
def Kubeconfig.ref(b: J.Json, +f: String) -> String:
  J.Json.str_or(J.Json.get(b, f), "")

# Whether some context's field f (cluster or user) is v.
def Kubeconfig.refs(xs: List<&2, Ent>, +f: String, +v: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{Ent{k, b}, t}:
      Bool.or(String.eq(Kubeconfig.ref(b, f), v), Kubeconfig.refs(t, f, v))

def Kubeconfig.first(xs: List<&2, Ent>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{Ent{k, b}, t}:
      k

# The structured core
# -------------------

def Kubeconfig.empty() -> Kc:
  Kc{Nil{}, Nil{}, Nil{}, "", J.JObj{J.JNil{}}}

def Kubeconfig.contexts(kc: Kc) -> List<&2, Ent>:
  match kc:
    case Kc{cls, ctxs, us, cur, pr}:
      ctxs

def Kubeconfig.current(kc: Kc) -> String:
  match kc:
    case Kc{cls, ctxs, us, cur, pr}:
      cur

def Kubeconfig.entries(kc: Kc) -> Ents:
  match kc:
    case Kc{cls, ctxs, us, cur, pr}:
      Ents{cls, ctxs, us}

# clientcmdapi.NewContext with Cluster and AuthInfo set to n.
def Kubeconfig.ctx_body(+n: String) -> J.Json:
  J.JObj{J.JMem{"cluster", J.JStr{n}, J.JMem{"user", J.JStr{n}, J.JNil{}}}}

def Kubeconfig.cur_set(set: Bool, cur: String, +n: String) -> String:
  match set:
    case True{}:
      n
    case False{}:
      cur

# clihelper.UpdateKubeConfig: cluster n, user n and context n (pointing at
# both) replace any entries named n; current-context becomes n when set.
def Kubeconfig.upsert(kc: Kc, +n: String, cl: J.Json, u: J.Json, set: Bool) -> Kc:
  match kc:
    case Kc{cls, ctxs, us, cur, pr}:
      Kc{Kubeconfig.put(cls, n, cl), Kubeconfig.put(ctxs, n, Kubeconfig.ctx_body(n)), Kubeconfig.put(us, n, u),
        Kubeconfig.cur_set(set, cur, n), pr}

def Kubeconfig.keep_if(used: Bool, xs: List<&2, Ent>, +k: String) -> List<&2, Ent>:
  match used:
    case True{}:
      xs
    case False{}:
      Kubeconfig.del(xs, k)

def Kubeconfig.cur_after(hit: Bool, cur: String, rest: List<&2, Ent>) -> String:
  match hit:
    case True{}:
      Kubeconfig.first(rest)
    case False{}:
      cur

def Kubeconfig.unset.do(+c: String, +u: String, cls: List<&2, Ent>, +rest: List<&2, Ent>, us: List<&2, Ent>,
  +cur: String, pr: J.Json, +n: String) -> Kc:
  Kc{Kubeconfig.keep_if(Kubeconfig.refs(rest, "cluster", c), cls, c), rest,
    Kubeconfig.keep_if(Kubeconfig.refs(rest, "user", u), us, u), Kubeconfig.cur_after(String.eq(cur, n), cur, rest), pr}

def Kubeconfig.unset.go(f: Maybe<&2, J.Json>, cls: List<&2, Ent>, ctxs: List<&2, Ent>, us: List<&2, Ent>,
  cur: String, pr: J.Json, +n: String) -> Kc:
  match f:
    case None{}:
      Kc{cls, ctxs, us, cur, pr}
    case Some{+b}:
      Kubeconfig.unset.do(Kubeconfig.ref(b, "cluster"), Kubeconfig.ref(b, "user"), cls, Kubeconfig.del(ctxs, n), us,
        cur, pr, n)

# vcluster deleteContext (with no other context to switch to).
def Kubeconfig.unset(kc: Kc, +n: String) -> Kc:
  match kc:
    case Kc{cls, +ctxs, us, cur, pr}:
      Kubeconfig.unset.go(Kubeconfig.find(ctxs, n), cls, ctxs, us, cur, pr, n)

# The connect-side rename (vcluster exchangeContextName): the first
# cluster, context and user, all named n; the context points at cluster n
# and user n; current-context is n.
def Kubeconfig.point(b: J.Json, +n: String) -> J.Json:
  J.Json.set(J.Json.set(b, "cluster", J.JStr{n}), "user", J.JStr{n})

def Kubeconfig.renamed.pick(c: Maybe<&2, Ent>, x: Maybe<&2, Ent>, u: Maybe<&2, Ent>, pr: J.Json, +n: String) ->
  Result<&2, &2, String, Kc>:
  match c x u:
    case Some{Ent{cn, cb}} Some{Ent{xn, xb}} Some{Ent{un, ub}}:
      Done{Kc{[Ent{n, cb}], [Ent{n, Kubeconfig.point(xb, n)}], [Ent{n, ub}], n, pr}}
    case _ _ _:
      Fail{"kubeconfig is missing required fields"}

def Kubeconfig.renamed(kc: Kc, +n: String) -> Result<&2, &2, String, Kc>:
  match kc:
    case Kc{cls, ctxs, us, cur, pr}:
      Kubeconfig.renamed.pick(List.head(&2, Ent, cls), List.head(&2, Ent, ctxs), List.head(&2, Ent, us), pr, n)

# Reading
# -------

def Kubeconfig.ent(+j: J.Json, +f: String) -> Ent:
  Ent{J.Json.str_or(J.Json.get(j, "name"), ""), J.Json.get(j, f)}

def Kubeconfig.ents(xs: List<&2, J.Json>, +f: String) -> List<&2, Ent>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+j, t}:
      Kubeconfig.ent(j, f) <> Kubeconfig.ents(t, f)

def Kubeconfig.prefs(j: J.Json) -> J.Json:
  match j:
    case J.JObj{ms}:
      J.JObj{ms}
    case _:
      J.JObj{J.JNil{}}

def Kubeconfig.of_json(+j: J.Json) -> Kc:
  cls us = Kubeconfig.ents(J.Json.items(J.Json.get(j, "clusters")), "cluster") Kubeconfig.ents(J.Json.items(J.Json.get(j, "users")), "user")
  Kc{cls, Kubeconfig.ents(J.Json.items(J.Json.get(j, "contexts")), "context"), us,
    J.Json.str_or(J.Json.get(j, "current-context"), ""), Kubeconfig.prefs(J.Json.get(j, "preferences"))}

def Kubeconfig.read.of(j: J.Json) -> Result<&2, &2, String, Kc>:
  match j:
    case J.JNull{}:
      Done{Kubeconfig.empty()}
    case J.JObj{ms}:
      Done{Kubeconfig.of_json(J.JObj{ms})}
    case _:
      Fail{"kubeconfig is not a YAML mapping"}

# An empty or missing kubeconfig ("") is an empty one.
def Kubeconfig.read(s: String) -> Result<&2, &2, String, Kc>:
  Kubeconfig.read.of(Y.Yaml.parse(s))

# Writing
# -------

def Kubeconfig.plain_chr(c: Char) -> Bool:
  match c:
    case Chr{+x}:
      (U32.is_ge(x, 97) && U32.is_le(x, 122)) || (U32.is_ge(x, 65) && U32.is_le(x, 90))
        || (U32.is_ge(x, 48) && U32.is_le(x, 58)) || U32.is_eq(x, 45) || U32.is_eq(x, 46) || U32.is_eq(x, 95)
        || U32.is_eq(x, 47) || U32.is_eq(x, 43) || U32.is_eq(x, 61) || U32.is_eq(x, 64)

def Kubeconfig.plain_all(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      Kubeconfig.plain_chr(c) && Kubeconfig.plain_all(t)

def Kubeconfig.plain_head(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{c, t}:
      Char.is_alpha(c)

# Words a YAML reader would take for a bool or a null.
def Kubeconfig.reserved.go(+l: String) -> Bool:
  String.eq(l, "true") || String.eq(l, "false") || String.eq(l, "null") || String.eq(l, "yes")
    || String.eq(l, "no") || String.eq(l, "on") || String.eq(l, "off") || String.eq(l, "y") || String.eq(l, "n")

def Kubeconfig.reserved(s: String) -> Bool:
  Kubeconfig.reserved.go(String.to_lower(s))

def Kubeconfig.str.go(+s: String, plain: Bool) -> String:
  match plain:
    case True{}:
      s
    case False{}:
      J.Json.quote(s)

# A string scalar: plain when it starts with a letter and holds only
# letters, digits and -._/+=@: (not last), else double-quoted (JSON
# escapes are YAML's).
def Kubeconfig.str(+s: String) -> String:
  Kubeconfig.str.go(s, Kubeconfig.plain_head(s) && Kubeconfig.plain_all(s) && Bool.not(Kubeconfig.reserved(s))
    && Bool.not(String.ends_with(s, ":")))

def Kubeconfig.scalar(j: J.Json) -> String:
  match j:
    case J.JStr{s}:
      Kubeconfig.str(s)
    case J.JNum{t}:
      t
    case J.JBool{True{}}:
      "true"
    case J.JBool{False{}}:
      "false"
    case J.JNull{}:
      "null"
    case x:
      J.Json.show(x)

# Where a value sits: after "key:", a member chain, an item chain, or one
# sequence item.
type YM is Data:
  YVal{}
  YMems{}
  YItems{}
  YItem{}

# Block YAML, kubectl's style (a sequence at its key's indentation). ind:
# the indentation of the lines; lead: what starts the first member's line
# ("- " for the first member of a sequence item).
def Kubeconfig.y(j: J.Json, m: YM, +ind: String, +lead: String) -> String:
  match j m:
    case J.JMem{k, v, t} YMems{}:
      lead ++ Kubeconfig.str(k) ++ ":" ++ Kubeconfig.y(v, YVal{}, ind, "") ++ Kubeconfig.y(t, YMems{}, ind, ind)
    case J.JObj{J.JNil{}} YVal{}:
      " {}\n"
    case J.JObj{ms} YVal{}:
      "\n" ++ Kubeconfig.y(ms, YMems{}, ind ++ "  ", ind ++ "  ")
    case J.JArr{J.JNil{}} YVal{}:
      " []\n"
    case J.JArr{xs} YVal{}:
      "\n" ++ Kubeconfig.y(xs, YItems{}, ind, ind)
    case J.JCons{h, t} YItems{}:
      Kubeconfig.y(h, YItem{}, ind, ind) ++ Kubeconfig.y(t, YItems{}, ind, ind)
    case J.JObj{J.JNil{}} YItem{}:
      ind ++ "- {}\n"
    case J.JObj{ms} YItem{}:
      Kubeconfig.y(ms, YMems{}, ind ++ "  ", ind ++ "- ")
    case x YItem{}:
      ind ++ "- " ++ Kubeconfig.scalar(x) ++ "\n"
    case x YVal{}:
      " " ++ Kubeconfig.scalar(x) ++ "\n"
    case _ _:
      ""

def Kubeconfig.item(+f: String, e: Ent) -> J.Json:
  match e:
    case Ent{n, b}:
      J.JObj{J.JMem{f, b, J.JMem{"name", J.JStr{n}, J.JNil{}}}}

def Kubeconfig.user_item(e: Ent) -> J.Json:
  match e:
    case Ent{n, b}:
      J.JObj{J.JMem{"name", J.JStr{n}, J.JMem{"user", b, J.JNil{}}}}

def Kubeconfig.chain(xs: List<&2, Ent>, +f: String) -> J.Json:
  match xs:
    case Nil{}:
      J.JNil{}
    case Con{e, t}:
      J.JCons{Kubeconfig.item(f, e), Kubeconfig.chain(t, f)}

def Kubeconfig.user_chain(xs: List<&2, Ent>) -> J.Json:
  match xs:
    case Nil{}:
      J.JNil{}
    case Con{e, t}:
      J.JCons{Kubeconfig.user_item(e), Kubeconfig.user_chain(t)}

# An empty list is null, as clientcmd.Write prints a nil slice.
def Kubeconfig.list(c: J.Json) -> J.Json:
  match c:
    case J.JNil{}:
      J.JNull{}
    case x:
      J.JArr{x}

def Kubeconfig.doc(kc: Kc) -> J.Json:
  match kc:
    case Kc{cls, ctxs, us, cur, pr}:
      a b = Kubeconfig.chain(cls, "cluster") Kubeconfig.user_chain(us)
      J.JMem{"apiVersion", J.JStr{"v1"},
        J.JMem{"clusters", Kubeconfig.list(a),
        J.JMem{"contexts", Kubeconfig.list(Kubeconfig.chain(ctxs, "context")),
        J.JMem{"current-context", J.JStr{cur},
        J.JMem{"kind", J.JStr{"Config"},
        J.JMem{"preferences", pr,
        J.JMem{"users", Kubeconfig.list(b), J.JNil{}}}}}}}}

def Kubeconfig.render(kc: Kc) -> String:
  Kubeconfig.y(Kubeconfig.doc(kc), YMems{}, "", "")

# The commands
# ------------

def Kubeconfig.merge.pick(c: Maybe<&2, Ent>, u: Maybe<&2, Ent>, some_ctx: Bool, k: Kc, +n: String, set: Bool) ->
  Result<&2, &2, String, String>:
  match c u some_ctx:
    case Some{Ent{cn, cb}} Some{Ent{un, ub}} True{}:
      Done{Kubeconfig.render(Kubeconfig.upsert(k, n, cb, ub, set))}
    case _ _ _:
      Fail{"kubeconfig is missing required fields"}

def Kubeconfig.merge.kc(k: Kc, i: Kc, +n: String, set: Bool) -> Result<&2, &2, String, String>:
  match i:
    case Kc{cls, ctxs, us, cur, pr}:
      Kubeconfig.merge.pick(List.head(&2, Ent, cls), List.head(&2, Ent, us), Bool.not(List.is_empty(&2, Ent, ctxs)), k,
        n, set)

def Kubeconfig.merge.go(ex: Result<&2, &2, String, Kc>, inc: Result<&2, &2, String, Kc>, +n: String, set: Bool) ->
  Result<&2, &2, String, String>:
  match ex inc:
    case Fail{e} _:
      Fail{"existing kubeconfig: " ++ e}
    case Done{k} Fail{e}:
      Fail{"vCluster kubeconfig: " ++ e}
    case Done{k} Done{i}:
      Kubeconfig.merge.kc(k, i, n, set)

# `vk8s connect`: the vCluster's kubeconfig (incoming) merged into the
# user's (existing) under context, cluster and user `name`; current-context
# becomes `name` when update_current.
def Kubeconfig.merge(existing: String, incoming: String, +name: String, update_current: Bool) ->
  Result<&2, &2, String, String>:
  Kubeconfig.merge.go(Kubeconfig.read(existing), Kubeconfig.read(incoming), name, update_current)

def Kubeconfig.rendered(r: Result<&2, &2, String, Kc>) -> Result<&2, &2, String, String>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{k}:
      Done{Kubeconfig.render(k)}

def Kubeconfig.rename.go(r: Result<&2, &2, String, Kc>, +n: String) -> Result<&2, &2, String, String>:
  match r:
    case Fail{e}:
      Fail{"vCluster kubeconfig: " ++ e}
    case Done{k}:
      Kubeconfig.rendered(Kubeconfig.renamed(k, n))

# `vk8s connect --print`: the vCluster's kubeconfig renamed to `name`.
def Kubeconfig.rename(incoming: String, +name: String) -> Result<&2, &2, String, String>:
  Kubeconfig.rename.go(Kubeconfig.read(incoming), name)

def Kubeconfig.remove.if(hit: Bool, k: Kc, existing: String, +n: String) -> Result<&2, &2, String, String>:
  match hit:
    case True{}:
      Done{Kubeconfig.render(Kubeconfig.unset(k, n))}
    case False{}:
      Done{existing}

def Kubeconfig.remove.go(r: Result<&2, &2, String, Kc>, existing: String, +n: String) -> Result<&2, &2, String, String>:
  match r:
    case Fail{e}:
      Fail{"existing kubeconfig: " ++ e}
    case Done{+k}:
      Kubeconfig.remove.if(Kubeconfig.has(Kubeconfig.contexts(k), n), k, existing, n)

# `vk8s delete --delete-context`: context `name` removed, with its user and
# cluster when no other context uses them. Without that context, the
# kubeconfig comes back as it was, byte for byte.
def Kubeconfig.remove(+existing: String, +name: String) -> Result<&2, &2, String, String>:
  Kubeconfig.remove.go(Kubeconfig.read(existing), existing, name)

def Kubeconfig.nonempty.if(empty: Bool, p: String, rest: List<&2, String>) -> List<&2, String>:
  match empty:
    case True{}:
      rest
    case False{}:
      p <> rest

def Kubeconfig.nonempty(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+p, t}:
      Kubeconfig.nonempty.if(String.is_empty(p), p, Kubeconfig.nonempty(t))

def Kubeconfig.target.of(m: Maybe<&2, String>, +home: String) -> String:
  match m:
    case None{}:
      home ++ "/.kube/config"
    case Some{p}:
      p

# The file connect writes (clientcmd's default filename): the first entry
# of $KUBECONFIG, else ~/.kube/config.
def Kubeconfig.target(env: String, +home: String) -> String:
  Kubeconfig.target.of(List.head(&2, String, Kubeconfig.nonempty(String.split(env, ':'))), home)

# The guest boundary
# ------------------
# The guest writes share/kubeconfig.yaml, and the guest is untrusted: its
# file may name an exec plugin, an auth provider, another server, a proxy
# or skip TLS verification. vk8s never uses it as is. It takes only the
# three base64 fields (CA, client certificate, client key) and builds a
# kubeconfig of its own with the server the host chose.

def Kubeconfig.b64_chr(c: Char) -> Bool:
  match c:
    case Chr{+u}:
      (U32.is_ge(u, 65) && U32.is_le(u, 90)) || (U32.is_ge(u, 97) && U32.is_le(u, 122)) || (U32.is_ge(u, 48) && U32.is_le(u, 57))
        || U32.is_eq(u, 43) || U32.is_eq(u, 47) || U32.is_eq(u, 61)

def Kubeconfig.b64_all(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      Bool.and(Kubeconfig.b64_chr(c), Kubeconfig.b64_all(t))

# Non-empty base64 of at most 64 KiB.
def Kubeconfig.b64(+s: String) -> Bool:
  Bool.not(String.is_empty(s)) && Kubeconfig.b64_all(s) && Nat.is_le(String.length(s), 65536n)

def Kubeconfig.host_owned(+server: String, +ca: String, +cert: String, +key: String, +n: String) -> String:
  Kubeconfig.render(Kubeconfig.upsert(Kubeconfig.empty(), n,
    J.JObj{J.JMem{"certificate-authority-data", J.JStr{ca}, J.JMem{"server", J.JStr{server}, J.JNil{}}}},
    J.JObj{J.JMem{"client-certificate-data", J.JStr{cert}, J.JMem{"client-key-data", J.JStr{key}, J.JNil{}}}}, True{}))

def Kubeconfig.sanitize.ok(ok: Bool, +server: String, +ca: String, +cert: String, +key: String, +n: String) -> Result<&2, &2, String, String>:
  match ok:
    case True{}:
      Done{Kubeconfig.host_owned(server, ca, cert, key, n)}
    case False{}:
      Fail{"the guest's kubeconfig lacks valid embedded certificates"}

def Kubeconfig.sanitize.pick(c: Maybe<&2, Ent>, u: Maybe<&2, Ent>, +server: String, +n: String) -> Result<&2, &2, String, String>:
  match c u:
    case Some{Ent{cn, cb}} Some{Ent{un, +ub}}:
      +ca : String = Kubeconfig.ref(cb, "certificate-authority-data")
      +cert : String = Kubeconfig.ref(ub, "client-certificate-data")
      +key : String = Kubeconfig.ref(ub, "client-key-data")
      Kubeconfig.sanitize.ok(Kubeconfig.b64(ca) && Kubeconfig.b64(cert) && Kubeconfig.b64(key), server, ca, cert, key, n)
    case _ _:
      Fail{"the guest's kubeconfig has no cluster or user"}

def Kubeconfig.sanitize.go(r: Result<&2, &2, String, Kc>, +server: String, +n: String) -> Result<&2, &2, String, String>:
  match r:
    case Fail{e}:
      Fail{"the guest's kubeconfig: " ++ e}
    case Done{Kc{cls, ctxs, us, cur, pr}}:
      Kubeconfig.sanitize.pick(List.head(&2, Ent, cls), List.head(&2, Ent, us), server, n)

# A host-owned kubeconfig for context `name` at `server`, from the guest's
# kubeconfig text: only its CA and client certificate and key survive.
def Kubeconfig.sanitize(incoming: String, +server: String, +name: String) -> Result<&2, &2, String, String>:
  Kubeconfig.sanitize.go(Kubeconfig.read(incoming), server, name)

def Kubeconfig.discovery.of(+ca: String, ok: Bool, +server: String) -> Result<&2, &2, String, String>:
  match ok:
    case True{}:
      Done{Kubeconfig.render(Kubeconfig.upsert(Kubeconfig.empty(), "default",
        J.JObj{J.JMem{"certificate-authority-data", J.JStr{ca}, J.JMem{"server", J.JStr{server}, J.JNil{}}}},
        J.JObj{J.JNil{}}, True{}))}
    case False{}:
      Fail{"the guest's kubeconfig lacks a valid CA"}

def Kubeconfig.discovery.cl(c: Maybe<&2, Ent>, +server: String) -> Result<&2, &2, String, String>:
  match c:
    case Some{Ent{cn, cb}}:
      +ca : String = Kubeconfig.ref(cb, "certificate-authority-data")
      Kubeconfig.discovery.of(ca, Kubeconfig.b64(ca), server)
    case None{}:
      Fail{"the guest's kubeconfig has no cluster"}

def Kubeconfig.discovery.go(r: Result<&2, &2, String, Kc>, +server: String) -> Result<&2, &2, String, String>:
  match r:
    case Fail{e}:
      Fail{"the guest's kubeconfig: " ++ e}
    case Done{Kc{cls, ctxs, us, cur, pr}}:
      Kubeconfig.discovery.cl(List.head(&2, Ent, cls), server)

# kubeadm join's discovery file for workers (cluster CA and the control
# plane's LAN address, an empty user), built by the host from the CA in the
# guest's kubeconfig rather than copied from the guest.
def Kubeconfig.discovery(incoming: String, +server: String) -> Result<&2, &2, String, String>:
  Kubeconfig.discovery.go(Kubeconfig.read(incoming), server)
