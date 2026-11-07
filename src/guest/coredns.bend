import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J

# The CoreDNS manifests vcluster deploys in the virtual cluster (vcluster
# pkg/coredns: template.go corednsCorefile and corednsManifests,
# coredns.go getManifestVariables, pkg/constants/coredns.go). Pure: the
# host writes Coredns.default_manifest() to disk and applies it.
#
# The two templates are rendered as vcluster's text/template renders them,
# from the same inputs: `values`, vcluster's config as JSON (the subtree
# the templates read: controlPlane.coredns, controlPlane.advanced,
# networking, policies), and Vars, the template variables IMAGE,
# RUN_AS_USER, RUN_AS_GROUP and HOST_CLUSTER_DNS. A Go template's `if`
# is Coredns.truthy, `{{ x }}` is Coredns.text, `toYaml` is
# Coredns.to_yaml and `indent` is Coredns.indent. Each output is trimmed
# and loses every "<no value>" (vcluster's TrimSpace and removeNoValue).
#
# vk8s calls it with Coredns.render(Cfg): vcluster's defaults
# (Coredns.vcluster_defaults) with the cluster domain, the kube-dns
# Service IP (service.spec.clusterIP), the replica count, and vk8s's
# choices: no kubelet proxy by hostname (no rewrite rule), no resources,
# no topology spread constraints and a pod security standard (seccomp
# RuntimeDefault), as scripts/guest/coredns.yaml was rendered.
#
# vcluster quirks, as encoded here:
# - the kubernetes plugin always serves cluster.local; another cluster
#   domain is served before it, not instead of it.
# - priorityClassName is always written, as "" when unset.
# - indent pads empty lines too: the Corefile's blank line becomes four
#   spaces in the ConfigMap.
# - a toYaml'd service.spec is written as is; its selector and ports
#   replace the defaults only when set (an empty spec prints `{}`).
# - "<no value>" is removed from the whole output, user text included.
# - overwriteManifests and overwriteConfig replace everything, trimmed.
# - getManifestVariables prefixes docker.io/ when no registry is set.
# Deviations: toYaml quotes some strings that yaml.v2 would print plain
# (anything outside letters, digits and -._/+=@:, and digit-led strings
# with ':' or '-'); the YAML means the same. Map keys sort in byte order
# (yaml.v2 sorts letters before other characters at a difference). A list
# inside a list prints in JSON flow form.

# HOST_CLUSTER_DNS is the first nameserver of /etc/resolv.conf in vcluster;
# "" in a field is a missing variable.
type Vars is Data:
  Vars{image: String, run_as_user: String, run_as_group: String, host_dns: String}

# What vk8s chooses: the cluster domain, the kube-dns Service IP (kubelet's
# clusterDNS), the CoreDNS image, replicas and the container's uid and gid.
type Cfg is Data:
  Cfg{cluster_domain: String, dns_service_ip: String, image: String, replicas: U32, run_as_user: U32,
    run_as_group: U32}

# One pinned image per Kubernetes minor.
type Pin is Data:
  Pin{version: String, image: String}

# Small helpers
# -------------

def Coredns.ifs(b: Bool, s: String) -> String:
  match b:
    case True{}:
      s
    case False{}:
      ""

def Coredns.pick(b: Bool, x: String, y: String) -> String:
  match b:
    case True{}:
      x
    case False{}:
      y

def Coredns.sel(b: Bool, x: U32, y: U32) -> U32:
  match b:
    case True{}:
      x
    case False{}:
      y

def Coredns.any_eq(xs: List<&2, String>, +s: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{h, t}:
      String.eq(h, s) || Coredns.any_eq(t, s)

def Coredns.any_prefix(xs: List<&2, String>, +s: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{h, t}:
      String.starts_with(s, h) || Coredns.any_prefix(t, s)

# Text
# ----

# Whether a string starts with a pattern, and the rest: the string
# without the pattern on a hit, else the string itself.
type Cut is Data:
  Cut{hit: Bool, rest: String}

def Coredns.cut.back(c: Char, r: Cut) -> Cut:
  match r:
    case Cut{h, rest}:
      match h:
        case True{}:
          Cut{True{}, rest}
        case False{}:
          Cut{False{}, SCon{c, rest}}

# The Cut of SCon{c, t} by SCon{y, pt}, where same is whether c is y.
# It walks only the matched prefix and never copies t or the pattern:
# the kernel normalizes every copied (+) value, so a copy of the tail at
# each character makes a pass over a long string quadratic.
def Coredns.cut.go(t: String, pt: String, c: Char, same: Bool) -> Cut:
  match t pt:
    case SNil{} SNil{}:
      match same:
        case True{}:
          Cut{True{}, SNil{}}
        case False{}:
          Cut{False{}, SCon{c, SNil{}}}
    case SNil{} SCon{y, yt}:
      match same:
        case True{}:
          Cut{False{}, SCon{c, SNil{}}}
        case False{}:
          Cut{False{}, SCon{c, SNil{}}}
    case SCon{+x, xt} SNil{}:
      match same:
        case True{}:
          Cut{True{}, SCon{x, xt}}
        case False{}:
          Cut{False{}, SCon{c, SCon{x, xt}}}
    case SCon{+x, xt} SCon{y, yt}:
      match same:
        case True{}:
          Coredns.cut.back(c, Coredns.cut.go(xt, yt, x, Char.is_eq(x, y)))
        case False{}:
          Cut{False{}, SCon{c, SCon{x, xt}}}

def Coredns.cut(s: String, p: String) -> Cut:
  match s p:
    case SNil{} SNil{}:
      Cut{True{}, SNil{}}
    case SNil{} SCon{y, yt}:
      Cut{False{}, SNil{}}
    case SCon{+x, xt} SNil{}:
      Cut{True{}, SCon{x, xt}}
    case SCon{+x, xt} SCon{y, yt}:
      Coredns.cut.go(xt, yt, x, Char.is_eq(x, y))

def Coredns.cut.rest(k: Cut) -> String:
  match k:
    case Cut{h, rest}:
      rest

# k: the Cut of what is left by `from`. Each step uses at least one
# character, so the length of the string is enough fuel.
def Coredns.replace.go(fuel: Nat, k: Cut, +from: String, +to: String) -> String:
  match fuel:
    case 0n:
      Coredns.cut.rest(k)
    case 1n+f:
      match k:
        case Cut{h, rest}:
          match h:
            case True{}:
              to ++ Coredns.replace.go(f, Coredns.cut(rest, from), from, to)
            case False{}:
              match rest:
                case SNil{}:
                  SNil{}
                case SCon{c, t}:
                  SCon{c, Coredns.replace.go(f, Coredns.cut(t, from), from, to)}

# Go strings.ReplaceAll(s, from, to), for a non-empty from.
def Coredns.replace(+s: String, +from: String, +to: String) -> String:
  Coredns.replace.go(1n+String.length(s), Coredns.cut(s, from), from, to)

def Coredns.trim_last.if(+s: String, hit: Bool) -> String:
  match hit:
    case True{}:
      String.take(s, Nat.sub(String.length(s), 1n))
    case False{}:
      s

# Go strings.TrimSuffix(s, p) for a one-char p.
def Coredns.trim_last(+s: String, +p: String) -> String:
  Coredns.trim_last.if(s, String.ends_with(s, p))

def Coredns.indent.chr(c: Char, +pad: String, rest: String) -> String:
  match c:
    case '\n':
      SCon{'\n', pad ++ rest}
    case Chr{x}:
      SCon{Chr{x}, rest}

def Coredns.indent.go(s: String, +pad: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{c, t}:
      Coredns.indent.chr(c, pad, Coredns.indent.go(t, pad))

# vcluster's indent: pad, and pad after every newline (empty lines too).
def Coredns.indent(+pad: String, s: String) -> String:
  pad ++ Coredns.indent.go(s, pad)

# k: the Cut of what is left by "<no value>". Coredns.replace.go with the
# pattern as a literal at each step, so no step copies it.
def Coredns.clean.go(fuel: Nat, k: Cut) -> String:
  match fuel:
    case 0n:
      Coredns.cut.rest(k)
    case 1n+f:
      match k:
        case Cut{h, rest}:
          match h:
            case True{}:
              Coredns.clean.go(f, Coredns.cut(rest, "<no value>"))
            case False{}:
              match rest:
                case SNil{}:
                  SNil{}
                case SCon{c, t}:
                  SCon{c, Coredns.clean.go(f, Coredns.cut(t, "<no value>"))}

# vcluster's removeNoValue: every "<no value>" removed.
def Coredns.clean(+s: String) -> String:
  Coredns.clean.go(1n+String.length(s), Coredns.cut(s, "<no value>"))

# vcluster's removeNoValue(strings.TrimSpace(s)).
def Coredns.finish(s: String) -> String:
  Coredns.clean(String.trim(s))

# Go templates
# ------------

def Coredns.nonzero(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{+c, t}:
      (Char.is_digit(c) && Bool.not(Char.is_eq(c, '0'))) || Coredns.nonzero(t)

# A Go template's truth: false, 0, "", null, a missing key, [] and {} are
# false.
def Coredns.truthy(j: J.Json) -> Bool:
  match j:
    case J.JBool{b}:
      b
    case J.JNum{t}:
      Coredns.nonzero(t)
    case J.JStr{s}:
      Bool.not(String.is_empty(s))
    case J.JArr{J.JNil{}}:
      False{}
    case J.JArr{xs}:
      True{}
    case J.JObj{J.JNil{}}:
      False{}
    case J.JObj{ms}:
      True{}
    case _:
      False{}

# {{ x }}: a missing key prints "<no value>", which vcluster removes.
def Coredns.text(j: J.Json) -> String:
  match j:
    case J.JStr{s}:
      s
    case J.JNum{t}:
      t
    case J.JBool{True{}}:
      "true"
    case J.JBool{False{}}:
      "false"
    case J.JNull{}:
      ""
    case x:
      J.Json.show(x)

# toYaml (sigs.k8s.io/yaml, yaml.v2 layout)
# ----------------------------------------

def Coredns.ins.if(c: Cmp, +k: String, +v: J.Json, kk: String, vv: J.Json, t: J.Json, rec: J.Json) -> J.Json:
  match c:
    case LT{}:
      J.JMem{k, v, J.JMem{kk, vv, t}}
    case EQ{}:
      J.JMem{k, v, J.JMem{kk, vv, t}}
    case GT{}:
      J.JMem{kk, vv, rec}

# Inserts member k: v into a member chain sorted by key.
def Coredns.ins(+k: String, +v: J.Json, ms: J.Json) -> J.Json:
  match ms:
    case J.JMem{+kk, vv, +t}:
      Coredns.ins.if(String.order(k, kk), k, v, kk, vv, t, Coredns.ins(k, v, t))
    case _:
      J.JMem{k, v, J.JNil{}}

# Every object's members sorted by key, as yaml.v2 prints a map.
def Coredns.sorted(j: J.Json) -> J.Json:
  match j:
    case J.JObj{ms}:
      J.JObj{Coredns.sorted(ms)}
    case J.JArr{xs}:
      J.JArr{Coredns.sorted(xs)}
    case J.JCons{h, t}:
      J.JCons{Coredns.sorted(h), Coredns.sorted(t)}
    case J.JMem{k, v, t}:
      Coredns.ins(k, Coredns.sorted(v), Coredns.sorted(t))
    case x:
      x

def Coredns.safe_chr(c: Char) -> Bool:
  match c:
    case Chr{+x}:
      (U32.is_ge(x, 97) && U32.is_le(x, 122)) || (U32.is_ge(x, 65) && U32.is_le(x, 90))
        || (U32.is_ge(x, 48) && U32.is_le(x, 58)) || U32.is_eq(x, 45) || U32.is_eq(x, 46) || U32.is_eq(x, 95)
        || U32.is_eq(x, 47) || U32.is_eq(x, 43) || U32.is_eq(x, 61) || U32.is_eq(x, 64)

def Coredns.safe_all(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      Coredns.safe_chr(c) && Coredns.safe_all(t)

# Plain scalars yaml.v2 reads as a bool, a null, a float or a merge key,
# and "-", which plain is a list item. None is longer than 5 characters,
# so a longer string skips the list.
def Coredns.reserved(+s: String) -> Bool:
  String.is_empty(String.drop(s, 5n)) && Coredns.any_eq(["y", "Y", "yes", "Yes", "YES", "n", "N", "no", "No", "NO",
    "true", "True", "TRUE", "false", "False", "FALSE", "on", "On", "ON", "off", "Off", "OFF", "null", "Null", "NULL",
    ".nan", ".NaN", ".NAN", ".inf", ".Inf", ".INF", "+.inf", "+.Inf", "+.INF", "-.inf", "-.Inf", "-.INF", "-"], s)

# A recognizer of [-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?
# with '_' ignored (yaml.v2 resolve strips it): 0 start, 1 sign, 2 digits,
# 3 digits and '.', 4 a bare '.', 5 fraction, 6 'e', 7 exponent sign,
# 8 exponent digits, 9 dead.
def Coredns.num.digit(+st: U32) -> U32:
  Coredns.sel(U32.is_le(st, 2), 2, Coredns.sel(U32.is_le(st, 5), 5, Coredns.sel(U32.is_le(st, 8), 8, 9)))

def Coredns.num.sign(+st: U32) -> U32:
  Coredns.sel(U32.is_eq(st, 0), 1, Coredns.sel(U32.is_eq(st, 6), 7, 9))

def Coredns.num.dot(+st: U32) -> U32:
  Coredns.sel(U32.is_le(st, 1), 4, Coredns.sel(U32.is_eq(st, 2), 3, 9))

def Coredns.num.exp(+st: U32) -> U32:
  Coredns.sel(U32.is_eq(st, 2) || U32.is_eq(st, 3) || U32.is_eq(st, 5), 6, 9)

def Coredns.num.step(+st: U32, +c: Char) -> U32:
  Coredns.sel(Char.is_digit(c), Coredns.num.digit(st),
    Coredns.sel(Char.is_eq(c, '+') || Char.is_eq(c, '-'), Coredns.num.sign(st),
    Coredns.sel(Char.is_eq(c, '.'), Coredns.num.dot(st),
    Coredns.sel(Char.is_eq(c, 'e') || Char.is_eq(c, 'E'), Coredns.num.exp(st),
    Coredns.sel(Char.is_eq(c, '_'), st, 9)))))

def Coredns.num.go(s: String, +st: U32) -> U32:
  match s:
    case SNil{}:
      st
    case SCon{c, t}:
      Coredns.num.go(t, Coredns.num.step(st, c))

def Coredns.num.accept(+st: U32) -> Bool:
  U32.is_eq(st, 2) || U32.is_eq(st, 3) || U32.is_eq(st, 5) || U32.is_eq(st, 8)

def Coredns.num_head(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{+c, t}:
      Char.is_digit(c) || Char.is_eq(c, '+') || Char.is_eq(c, '-') || Char.is_eq(c, '.')

# Whether s starts with a digit, a sign, '.' or '_': the recognizer dies
# (state 9 holds) on any other first character.
def Coredns.num_lead(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{+c, t}:
      Char.is_digit(c) || Char.is_eq(c, '+') || Char.is_eq(c, '-') || Char.is_eq(c, '.') || Char.is_eq(c, '_')

# Strings yaml.v2 resolves to a number (ints with a 0x, 0o or 0b base
# too), a timestamp or a base 60 float: digit-led ones with ':' or '-'.
# Each needs Coredns.num_lead, so a string without it skips the rest.
def Coredns.numeric(+s: String) -> Bool:
  Coredns.num_lead(s) && (Coredns.num.accept(Coredns.num.go(s, 0))
    || (Coredns.num_head(s) && (String.contains(s, ":") || String.contains(String.drop(s, 1n), "-")
    || Coredns.any_prefix(["0x", "0o", "0b", "+0x", "+0o", "+0b", "-0x", "-0o", "-0b"], s))))

def Coredns.plain(+s: String) -> Bool:
  Bool.not(String.is_empty(s)) && Coredns.safe_all(s) && Bool.not(Coredns.reserved(s))
    && Bool.not(String.ends_with(s, ":")) && Bool.not(String.starts_with(s, "@")) && Bool.not(Coredns.numeric(s))

# A string scalar: plain when yaml.v2 reads it back as the same string,
# else double-quoted (JSON escapes are YAML's).
def Coredns.yaml_str(+s: String) -> String:
  Coredns.pick(Coredns.plain(s), s, J.Json.quote(s))

def Coredns.scalar(j: J.Json) -> String:
  match j:
    case J.JStr{s}:
      Coredns.yaml_str(s)
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

# Block YAML in yaml.v2's layout: a sequence at its key's indentation, a
# map in a sequence item after "- ". ind: the indentation of the lines;
# lead: what starts the first member's line.
def Coredns.y(j: J.Json, m: YM, +ind: String, +lead: String) -> String:
  match j m:
    case J.JMem{k, v, t} YMems{}:
      lead ++ Coredns.yaml_str(k) ++ ":" ++ Coredns.y(v, YVal{}, ind, "") ++ Coredns.y(t, YMems{}, ind, ind)
    case J.JObj{J.JNil{}} YVal{}:
      " {}\n"
    case J.JObj{ms} YVal{}:
      "\n" ++ Coredns.y(ms, YMems{}, ind ++ "  ", ind ++ "  ")
    case J.JArr{J.JNil{}} YVal{}:
      " []\n"
    case J.JArr{xs} YVal{}:
      "\n" ++ Coredns.y(xs, YItems{}, ind, ind)
    case J.JCons{h, t} YItems{}:
      Coredns.y(h, YItem{}, ind, ind) ++ Coredns.y(t, YItems{}, ind, ind)
    case J.JObj{J.JNil{}} YItem{}:
      ind ++ "- {}\n"
    case J.JObj{ms} YItem{}:
      Coredns.y(ms, YMems{}, ind ++ "  ", ind ++ "- ")
    case x YItem{}:
      ind ++ "- " ++ Coredns.scalar(x) ++ "\n"
    case x YVal{}:
      " " ++ Coredns.scalar(x) ++ "\n"
    case _ _:
      ""

def Coredns.to_yaml.go(j: J.Json) -> String:
  match j:
    case J.JObj{J.JNil{}}:
      "{}\n"
    case J.JObj{ms}:
      Coredns.y(ms, YMems{}, "", "")
    case J.JArr{J.JNil{}}:
      "[]\n"
    case J.JArr{xs}:
      Coredns.y(xs, YItems{}, "", "")
    case x:
      Coredns.scalar(x) ++ "\n"

# vcluster's toYaml: yaml.Marshal without its last newline.
def Coredns.to_yaml(j: J.Json) -> String:
  Coredns.trim_last(Coredns.to_yaml.go(Coredns.sorted(j)), "\n")

def Coredns.when.if(on: Bool, j: J.Json, pre: String, +pad: String) -> String:
  match on:
    case True{}:
      pre ++ Coredns.indent(pad, Coredns.to_yaml(j))
    case False{}:
      ""

# {{- if x }}pre{{ toYaml x | indent n }}{{- end }}
def Coredns.when(+j: J.Json, pre: String, +pad: String) -> String:
  Coredns.when.if(Coredns.truthy(j), j, pre, pad)

# vcluster's config
# -----------------

def Coredns.obj(fs: List<&2, J.KV>) -> J.Json:
  J.Json.obj(fs)

def Coredns.empty_obj() -> J.Json:
  J.JObj{J.JNil{}}

def Coredns.empty_arr() -> J.Json:
  J.JArr{J.JNil{}}

def Coredns.pick.json(b: Bool, x: J.Json, y: J.Json) -> J.Json:
  match b:
    case True{}:
      x
    case False{}:
      y

# The value under key in a member chain, JNull when absent, as J.Json.get
# finds it, but without a copy of the chain's rest at each member: the
# kernel normalizes every copied value, so a copy per member makes a
# lookup quadratic in the size of the config.
def Coredns.find(ms: J.Json, +key: String) -> J.Json:
  match ms:
    case J.JMem{k, x, t}:
      Coredns.pick.json(String.eq(k, key), x, Coredns.find(t, key))
    case _:
      J.JNull{}

def Coredns.get(j: J.Json, +key: String) -> J.Json:
  match j:
    case J.JObj{ms}:
      Coredns.find(ms, key)
    case _:
      J.JNull{}

def Coredns.walk(path: List<&2, String>, j: J.Json) -> J.Json:
  match path:
    case Nil{}:
      j
    case Con{k, t}:
      Coredns.walk(t, Coredns.get(j, k))

# J.Json.at: the value at a path, JNull when a key is missing.
def Coredns.at(v: J.Json, path: List<&2, String>) -> J.Json:
  Coredns.walk(path, v)

# .Values.controlPlane.coredns.<path>
def Coredns.cd(v: J.Json, path: List<&2, String>) -> J.Json:
  Coredns.walk(path, Coredns.walk(["controlPlane", "coredns"], v))

# Sets the value at a path, making the objects on the way.
def Coredns.put(path: List<&2, String>, +j: J.Json, v: J.Json) -> J.Json:
  match path:
    case Nil{}:
      v
    case Con{+k, t}:
      J.Json.set(j, k, Coredns.put(t, J.Json.get(j, k), v))

# The subtree of vcluster's config the templates read, with the values
# that differ between vcluster's defaults and vk8s's as parameters.
def Coredns.values.of(domain: J.Json, by_hostname: J.Json, pss: J.Json, spec: J.Json, replicas: J.Json,
  resources: J.Json, spread: J.Json) -> J.Json:
  Coredns.obj([
    J.KV{"controlPlane", Coredns.obj([
      J.KV{"coredns", Coredns.obj([
        J.KV{"enabled", J.JBool{True{}}},
        J.KV{"embedded", J.JBool{False{}}},
        J.KV{"overwriteManifests", J.JStr{""}},
        J.KV{"overwriteConfig", J.JStr{""}},
        J.KV{"priorityClassName", J.JStr{""}},
        J.KV{"security", Coredns.obj([
          J.KV{"podSecurityContext", Coredns.empty_obj()},
          J.KV{"containerSecurityContext", Coredns.empty_obj()}])},
        J.KV{"service", Coredns.obj([
          J.KV{"annotations", Coredns.empty_obj()},
          J.KV{"labels", Coredns.empty_obj()},
          J.KV{"spec", spec}])},
        J.KV{"deployment", Coredns.obj([
          J.KV{"annotations", Coredns.empty_obj()},
          J.KV{"labels", Coredns.empty_obj()},
          J.KV{"image", J.JStr{""}},
          J.KV{"replicas", replicas},
          J.KV{"pods", Coredns.obj([J.KV{"labels", Coredns.empty_obj()}, J.KV{"annotations", Coredns.empty_obj()}])},
          J.KV{"nodeSelector", Coredns.empty_obj()},
          J.KV{"affinity", Coredns.empty_obj()},
          J.KV{"tolerations", Coredns.empty_arr()},
          J.KV{"resources", resources},
          J.KV{"topologySpreadConstraints", spread}])}])},
      J.KV{"advanced", Coredns.obj([J.KV{"defaultImageRegistry", J.JStr{""}}])}])},
    J.KV{"networking", Coredns.obj([
      J.KV{"resolveDNS", Coredns.empty_arr()},
      J.KV{"advanced", Coredns.obj([
        J.KV{"clusterDomain", domain},
        J.KV{"fallbackHostCluster", J.JBool{False{}}},
        J.KV{"proxyKubelets", Coredns.obj([J.KV{"byHostname", by_hostname}, J.KV{"byIP", J.JBool{True{}}}])}])}])},
    J.KV{"policies", Coredns.obj([
      J.KV{"podSecurityStandard", pss},
      J.KV{"networkPolicy", Coredns.obj([J.KV{"enabled", J.JBool{False{}}}, J.KV{"fallbackDns", J.JStr{"8.8.8.8"}}])}])}])

# chart/values.yaml: controlPlane.coredns.deployment.resources.
def Coredns.default_resources() -> J.Json:
  Coredns.obj([
    J.KV{"limits", Coredns.obj([J.KV{"cpu", J.JStr{"1000m"}}, J.KV{"memory", J.JStr{"170Mi"}}])},
    J.KV{"requests", Coredns.obj([J.KV{"cpu", J.JStr{"20m"}}, J.KV{"memory", J.JStr{"64Mi"}}])}])

# chart/values.yaml: controlPlane.coredns.deployment.topologySpreadConstraints.
def Coredns.default_spread() -> J.Json:
  J.Json.arr([Coredns.obj([
    J.KV{"maxSkew", J.JNum{"1"}},
    J.KV{"topologyKey", J.JStr{"kubernetes.io/hostname"}},
    J.KV{"whenUnsatisfiable", J.JStr{"DoNotSchedule"}},
    J.KV{"labelSelector", Coredns.obj([
      J.KV{"matchLabels", Coredns.obj([J.KV{"k8s-app", J.JStr{"vcluster-kube-dns"}}])}])}])])

# config.NewDefaultConfig(), the part the templates read.
def Coredns.vcluster_defaults() -> J.Json:
  Coredns.values.of(J.JStr{"cluster.local"}, J.JBool{True{}}, J.JStr{""},
    Coredns.obj([J.KV{"type", J.JStr{"ClusterIP"}}]), J.JNum{"1"}, Coredns.default_resources(), Coredns.default_spread())

# pkg/constants/coredns.go
# ------------------------

def Coredns.label_key() -> String:
  "k8s-app"

def Coredns.label_value() -> String:
  "vcluster-kube-dns"

def Coredns.default_image() -> String:
  "coredns/coredns:1.14.2"

# CoreDNSVersionMap.
def Coredns.pins() -> List<&2, Pin>:
  [Pin{"1.36", "coredns/coredns:1.14.2"}, Pin{"1.35", "coredns/coredns:1.14.1"}, Pin{"1.34", "coredns/coredns:1.12.1"},
   Pin{"1.33", "coredns/coredns:1.12.0"}, Pin{"1.32", "coredns/coredns:1.11.3"}, Pin{"1.31", "coredns/coredns:1.11.3"},
   Pin{"1.30", "coredns/coredns:1.11.3"}]

def Coredns.pinned.if(img: String, rest: Maybe<&2, String>, hit: Bool) -> Maybe<&2, String>:
  match hit:
    case True{}:
      Some{img}
    case False{}:
      rest

def Coredns.pinned.go(ps: List<&2, Pin>, +v: String) -> Maybe<&2, String>:
  match ps:
    case Nil{}:
      None{}
    case Con{Pin{k, img}, t}:
      Coredns.pinned.if(img, Coredns.pinned.go(t, v), String.eq(k, v))

# The image pinned for Kubernetes "MAJOR.MINOR", if any.
def Coredns.pinned(+v: String) -> Maybe<&2, String>:
  Coredns.pinned.go(Coredns.pins(), v)

def Coredns.image.reg(+img: String, +reg: String, empty: Bool) -> String:
  match empty:
    case True{}:
      "docker.io/" ++ img
    case False{}:
      Coredns.trim_last(reg, "/") ++ "/" ++ img

# getManifestVariables' IMAGE: the image pinned for the virtual
# Kubernetes version (else DefaultImage), under the default image
# registry (one trailing '/' trimmed), else under docker.io.
def Coredns.image(+major: String, +minor: String, +registry: String) -> String:
  Coredns.image.reg(Maybe.default(&2, String, Coredns.pinned(major ++ "." ++ minor), Coredns.default_image()), registry,
    String.is_empty(registry))

# The Corefile (template.go corednsCorefile)
# -----------------------------------------

def Coredns.corefile.forward(fallback: Bool, netpol: Bool, host_dns: String, fallback_dns: String) -> String:
  match fallback netpol:
    case True{} _:
      "\n    forward . " ++ host_dns
    case False{} True{}:
      "\n    forward . /etc/resolv.conf " ++ fallback_dns ++ " {\n        policy sequential\n    }"
    case False{} False{}:
      "\n    forward . /etc/resolv.conf"

# {{ if and d (ne d "cluster.local") }} {{ d }}{{ end }}
def Coredns.corefile.zone(+d: J.Json) -> String:
  Coredns.ifs(Coredns.truthy(d) && Bool.not(String.eq(Coredns.text(d), "cluster.local")), " " ++ Coredns.text(d))

def Coredns.corefile.body(+v: J.Json, host_dns: String) -> String:
  +embedded = Coredns.truthy(Coredns.cd(v, ["embedded"]))
  +fallback = Coredns.truthy(Coredns.at(v, ["networking", "advanced", "fallbackHostCluster"]))
  ".:1053 {\n    errors\n    health\n    ready"
  ++ Coredns.ifs(embedded && Coredns.truthy(Coredns.at(v, ["networking", "resolveDNS"])), "\n    vcluster")
  ++ Coredns.ifs(Coredns.truthy(Coredns.at(v, ["networking", "advanced", "proxyKubelets", "byHostname"])),
    "\n    rewrite name regex .*\\.nodes\\.vcluster\\.com kubernetes.default.svc.cluster.local")
  ++ "\n    kubernetes" ++ Coredns.corefile.zone(Coredns.at(v, ["networking", "advanced", "clusterDomain"]))
  ++ " cluster.local in-addr.arpa ip6.arpa {"
  ++ Coredns.ifs(embedded, "\n        kubeconfig /data/vcluster/admin.conf")
  ++ "\n        pods insecure"
  ++ Coredns.pick(fallback, "\n        fallthrough cluster.local in-addr.arpa ip6.arpa",
    "\n        fallthrough in-addr.arpa ip6.arpa")
  ++ "\n    }\n    hosts /etc/coredns/NodeHosts {\n        ttl 60\n        reload 15s\n        fallthrough\n    }"
  ++ "\n    prometheus :9153"
  ++ Coredns.corefile.forward(fallback, Coredns.truthy(Coredns.at(v, ["policies", "networkPolicy", "enabled"])), host_dns,
    Coredns.text(Coredns.at(v, ["policies", "networkPolicy", "fallbackDns"])))
  ++ "\n    cache 30\n    loop"
  ++ Coredns.ifs(Bool.not(embedded), "\n    reload")
  ++ "\n    loadbalance\n}\n\nimport /etc/coredns/custom/*.server"

def Coredns.vars.host_dns(vs: Vars) -> String:
  match vs:
    case Vars{img, u, g, h}:
      h

def Coredns.vars.image(vs: Vars) -> String:
  match vs:
    case Vars{img, u, g, h}:
      img

# vcluster's ProcessCorefile.
def Coredns.corefile(+v: J.Json, vs: Vars) -> String:
  +ov = Coredns.cd(v, ["overwriteConfig"])
  Coredns.finish(Coredns.pick(Coredns.truthy(ov), "\n" ++ Coredns.text(ov),
    "\n" ++ Coredns.corefile.body(v, Coredns.vars.host_dns(vs))))

# The manifests (template.go corednsManifests)
# --------------------------------------------
#
# One def per document of the YAML stream: the text vcluster writes for
# it, without its "---" line. Coredns.manifests joins the documents with
# "---" lines. vcluster trims the whole stream and then removes every
# "<no value>"; per document that is the same thing: the pattern has no
# newline, so no match crosses a "---" line, and no document starts or
# ends with whitespace, so the trim has nothing to cut inside the stream.
# Each document takes the config and the variables, so the documents of
# a branch line up as calls with one shape.

def Coredns.doc.service_account(v: J.Json, vs: Vars) -> String:
  "apiVersion: v1\nkind: ServiceAccount\nmetadata:\n  name: coredns\n  namespace: kube-system"

def Coredns.doc.cluster_role(v: J.Json, vs: Vars) -> String:
  "apiVersion: rbac.authorization.k8s.io/v1\nkind: ClusterRole\nmetadata:\n  labels:\n"
  ++ "    kubernetes.io/bootstrapping: rbac-defaults\n  name: system:coredns\nrules:\n"
  ++ "  - apiGroups:\n      - \"\"\n    resources:\n      - endpoints\n      - services\n      - pods\n"
  ++ "      - namespaces\n    verbs:\n      - list\n      - watch\n"
  ++ "  - apiGroups:\n      - discovery.k8s.io\n    resources:\n      - endpointslices\n    verbs:\n"
  ++ "      - list\n      - watch"

def Coredns.doc.cluster_role_binding(v: J.Json, vs: Vars) -> String:
  "apiVersion: rbac.authorization.k8s.io/v1\nkind: ClusterRoleBinding\nmetadata:\n  annotations:\n"
  ++ "    rbac.authorization.kubernetes.io/autoupdate: \"true\"\n  labels:\n"
  ++ "    kubernetes.io/bootstrapping: rbac-defaults\n  name: system:coredns\nroleRef:\n"
  ++ "  apiGroup: rbac.authorization.k8s.io\n  kind: ClusterRole\n  name: system:coredns\nsubjects:\n"
  ++ "  - kind: ServiceAccount\n    name: coredns\n    namespace: kube-system"

# The ConfigMap with the Corefile.
def Coredns.doc.configmap(v: J.Json, vs: Vars) -> String:
  Coredns.clean("apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: coredns\n  namespace: kube-system\ndata:\n"
  ++ "  Corefile: |-\n" ++ Coredns.indent("    ", Coredns.corefile(v, vs)) ++ "\n  NodeHosts: \"\"")

def Coredns.doc.pod_security.if(on: Bool, j: J.Json, pss: Bool) -> String:
  match on:
    case True{}:
      "\n      securityContext:\n" ++ Coredns.indent("        ", Coredns.to_yaml(j))
    case False{}:
      Coredns.ifs(pss, "\n      securityContext:\n        seccompProfile:\n          type: RuntimeDefault")

def Coredns.doc.pod_security(+j: J.Json, pss: Bool) -> String:
  Coredns.doc.pod_security.if(Coredns.truthy(j), j, pss)

def Coredns.doc.container_security.if(on: Bool, j: J.Json, u: String, g: String) -> String:
  match on:
    case True{}:
      "\n          securityContext:\n" ++ Coredns.indent("            ", Coredns.to_yaml(j))
    case False{}:
      "\n          securityContext:\n            runAsNonRoot: true\n            runAsUser: " ++ u
      ++ "\n            runAsGroup: " ++ g
      ++ "\n            allowPrivilegeEscalation: false\n            capabilities:\n              add:\n"
      ++ "                - NET_BIND_SERVICE\n              drop:\n                - ALL\n"
      ++ "            readOnlyRootFilesystem: true"

def Coredns.doc.container_security(+j: J.Json, vs: Vars) -> String:
  match vs:
    case Vars{img, u, g, h}:
      Coredns.doc.container_security.if(Coredns.truthy(j), j, u, g)

def Coredns.doc.image.if(on: Bool, +reg: J.Json, +img: J.Json, iv: String) -> String:
  match on:
    case True{}:
      Coredns.pick(Coredns.truthy(reg), Coredns.text(reg) ++ "/" ++ Coredns.text(img), Coredns.text(img))
    case False{}:
      iv

# deployment.image (under defaultImageRegistry when set), else IMAGE.
def Coredns.doc.image(+v: J.Json, iv: String) -> String:
  +img = Coredns.cd(v, ["deployment", "image"])
  Coredns.doc.image.if(Coredns.truthy(img), Coredns.at(v, ["controlPlane", "advanced", "defaultImageRegistry"]), img, iv)

# The Deployment in two parts, at its containers: the Deployment and its
# pod template, then the containers and the volumes.
def Coredns.doc.deployment.pod(+v: J.Json, vs: Vars) -> String:
  Coredns.clean("apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: coredns\n  namespace: kube-system"
  ++ Coredns.when(Coredns.cd(v, ["deployment", "annotations"]), "\n  annotations:\n", "    ")
  ++ "\n  labels:\n    k8s-app: vcluster-kube-dns\n    kubernetes.io/name: \"CoreDNS\""
  ++ Coredns.when(Coredns.cd(v, ["deployment", "labels"]), "\n", "    ")
  ++ "\nspec:\n  replicas: " ++ Coredns.text(Coredns.cd(v, ["deployment", "replicas"]))
  ++ "\n  strategy:\n    type: RollingUpdate\n    rollingUpdate:\n      maxUnavailable: 1\n  selector:\n"
  ++ "    matchLabels:\n      k8s-app: vcluster-kube-dns\n  template:\n    metadata:"
  ++ Coredns.when(Coredns.cd(v, ["deployment", "pods", "annotations"]), "\n      annotations:\n", "        ")
  ++ "\n      labels:\n        k8s-app: vcluster-kube-dns"
  ++ Coredns.when(Coredns.cd(v, ["deployment", "pods", "labels"]), "\n", "        ")
  ++ "\n    spec:\n      priorityClassName: \"" ++ Coredns.text(Coredns.cd(v, ["priorityClassName"]))
  ++ "\"\n      serviceAccountName: coredns\n      nodeSelector:\n        kubernetes.io/os: linux"
  ++ Coredns.when(Coredns.cd(v, ["deployment", "nodeSelector"]), "\n", "        ")
  ++ Coredns.when(Coredns.cd(v, ["deployment", "affinity"]), "\n      affinity:\n", "        ")
  ++ Coredns.when(Coredns.cd(v, ["deployment", "tolerations"]), "\n      tolerations:\n", "        ")
  ++ Coredns.when(Coredns.cd(v, ["deployment", "topologySpreadConstraints"]), "\n      topologySpreadConstraints:\n",
    "        ")
  ++ Coredns.doc.pod_security(Coredns.cd(v, ["security", "podSecurityContext"]),
    Coredns.truthy(Coredns.at(v, ["policies", "podSecurityStandard"]))))

def Coredns.doc.deployment.containers(+v: J.Json, +vs: Vars) -> String:
  Coredns.clean("      containers:\n        - name: coredns\n          image: "
  ++ Coredns.doc.image(v, Coredns.vars.image(vs))
  ++ "\n          imagePullPolicy: IfNotPresent"
  ++ Coredns.when(Coredns.cd(v, ["deployment", "resources"]), "\n          resources:\n", "            ")
  ++ "\n          args: [ \"-conf\", \"/etc/coredns/Corefile\" ]\n          volumeMounts:\n"
  ++ "            - name: config-volume\n              mountPath: /etc/coredns\n              readOnly: true\n"
  ++ "            - name: custom-config-volume\n              mountPath: /etc/coredns/custom\n"
  ++ "              readOnly: true"
  ++ Coredns.doc.container_security(Coredns.cd(v, ["security", "containerSecurityContext"]), vs)
  ++ "\n          livenessProbe:\n            httpGet:\n              path: /health\n              port: 8080\n"
  ++ "              scheme: HTTP\n            initialDelaySeconds: 60\n            periodSeconds: 10\n"
  ++ "            timeoutSeconds: 1\n            successThreshold: 1\n            failureThreshold: 3\n"
  ++ "          readinessProbe:\n            httpGet:\n              path: /ready\n              port: 8181\n"
  ++ "              scheme: HTTP\n            initialDelaySeconds: 0\n            periodSeconds: 2\n"
  ++ "            timeoutSeconds: 1\n            successThreshold: 1\n            failureThreshold: 3\n"
  ++ "      dnsPolicy: Default\n      volumes:\n        - name: config-volume\n          configMap:\n"
  ++ "            name: coredns\n            items:\n              - key: Corefile\n                path: Corefile\n"
  ++ "              - key: NodeHosts\n                path: NodeHosts\n        - name: custom-config-volume\n"
  ++ "          configMap:\n            name: coredns-custom\n            optional: true")

# The parts render in parallel: the pod template and the containers each
# run their own lookups and toYaml.
def Coredns.doc.deployment(+v: J.Json, +vs: Vars) -> String:
  a b = Coredns.doc.deployment.pod(v, vs) Coredns.doc.deployment.containers(v, vs)
  a ++ "\n" ++ b

# The kube-dns Service's text; sel: whether the template has the default
# selector block (the embedded one has none).
def Coredns.doc.service.text(+v: J.Json, sel: Bool) -> String:
  +spec = Coredns.cd(v, ["service", "spec"])
  "apiVersion: v1\nkind: Service\nmetadata:\n  name: kube-dns\n  namespace: kube-system\n  annotations:\n"
  ++ "    prometheus.io/port: \"9153\"\n    prometheus.io/scrape: \"true\""
  ++ Coredns.when(Coredns.cd(v, ["service", "annotations"]), "\n", "    ")
  ++ "\n  labels:\n    k8s-app: vcluster-kube-dns\n    kubernetes.io/cluster-service: \"true\"\n"
  ++ "    kubernetes.io/name: \"CoreDNS\""
  ++ Coredns.when(Coredns.cd(v, ["service", "labels"]), "\n", "    ")
  ++ "\nspec:\n" ++ Coredns.indent("  ", Coredns.to_yaml(spec))
  ++ Coredns.ifs(sel && Bool.not(Coredns.truthy(Coredns.get(spec, "selector"))),
    "\n  selector:\n    k8s-app: vcluster-kube-dns")
  ++ Coredns.ifs(Bool.not(Coredns.truthy(Coredns.get(spec, "ports"))),
    "\n  ports:\n    - name: dns\n      port: 53\n      targetPort: 1053\n      protocol: UDP\n"
    ++ "    - name: dns-tcp\n      port: 53\n      targetPort: 1053\n      protocol: TCP\n"
    ++ "    - name: metrics\n      port: 9153\n      protocol: TCP")

# The kube-dns Service.
def Coredns.doc.service(v: J.Json, vs: Vars) -> String:
  Coredns.clean(Coredns.doc.service.text(v, True{}))

# The embedded branch's ConfigMap: no Corefile (CoreDNS runs in the
# vcluster process and reads its own).
def Coredns.doc.embedded_configmap(v: J.Json, vs: Vars) -> String:
  "apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: coredns\n  namespace: kube-system\ndata:\n  NodeHosts: \"\""

# The embedded branch's Service: no default selector.
def Coredns.doc.embedded_service(v: J.Json, vs: Vars) -> String:
  Coredns.clean(Coredns.doc.service.text(v, False{}))

# The overwrite branch: overwriteManifests as is, trimmed.
def Coredns.doc.overwrite(v: J.Json, vs: Vars) -> String:
  Coredns.finish(Coredns.text(Coredns.cd(v, ["overwriteManifests"])))

# Which templates processManifests writes.
type Branch is Data:
  Overwrite{}
  Embedded{}
  Full{}

def Coredns.branch.of(ov: Bool, emb: Bool) -> Branch:
  match ov emb:
    case True{} _:
      Overwrite{}
    case False{} True{}:
      Embedded{}
    case False{} False{}:
      Full{}

# overwriteManifests when set, else the embedded templates when embedded,
# else the full ones.
def Coredns.branch(+v: J.Json) -> Branch:
  Coredns.branch.of(Coredns.truthy(Coredns.cd(v, ["overwriteManifests"])), Coredns.truthy(Coredns.cd(v, ["embedded"])))

# The documents of a branch, in order. A plain list: each document is
# rendered only when the join reaches it, so two renders of one config
# compare equal after the first documents.
def Coredns.documents.of(br: Branch, +v: J.Json, +vs: Vars) -> List<&2, String>:
  match br:
    case Overwrite{}:
      [Coredns.doc.overwrite(v, vs)]
    case Embedded{}:
      [Coredns.doc.embedded_configmap(v, vs), Coredns.doc.embedded_service(v, vs)]
    case Full{}:
      [Coredns.doc.service_account(v, vs), Coredns.doc.cluster_role(v, vs), Coredns.doc.cluster_role_binding(v, vs),
       Coredns.doc.configmap(v, vs), Coredns.doc.deployment(v, vs), Coredns.doc.service(v, vs)]

def Coredns.documents(+v: J.Json, +vs: Vars) -> List<&2, String>:
  Coredns.documents.of(Coredns.branch(v), v, vs)

# A YAML stream: the documents with a "---" line between each two.
def Coredns.join(xs: List<&2, String>) -> String:
  String.join(xs, "\n---\n")

# vcluster's processManifests: the manifests as one YAML stream.
def Coredns.manifests(+v: J.Json, +vs: Vars) -> String:
  Coredns.join(Coredns.documents(v, vs))

# vk8s
# ----

def Coredns.values(cfg: Cfg) -> J.Json:
  match cfg:
    case Cfg{d, ip, img, r, u, g}:
      Coredns.values.of(J.JStr{d}, J.JBool{False{}}, J.JStr{"baseline"}, Coredns.obj([J.KV{"clusterIP", J.JStr{ip}}]),
        J.JNum{U32.show(r)}, Coredns.empty_obj(), Coredns.empty_arr())

# HOST_CLUSTER_DNS is the file itself, vcluster's choice when
# /etc/resolv.conf has no nameserver; only fallbackHostCluster reads it.
def Coredns.vars(cfg: Cfg) -> Vars:
  match cfg:
    case Cfg{d, ip, img, r, u, g}:
      Vars{img, U32.show(u), U32.show(g), "/etc/resolv.conf"}

def Coredns.render(+cfg: Cfg) -> String:
  Coredns.manifests(Coredns.values(cfg), Coredns.vars(cfg))

# The kube-dns Service at kubelet's clusterDNS 10.96.0.10, cluster.local,
# the image vk8s preloads (scripts/guest/images.sh) and uid/gid 1001
# (vcluster's for a root process).
def Coredns.default_cfg() -> Cfg:
  Cfg{"cluster.local", "10.96.0.10", "coredns/coredns:1.14.2", 1, 1001, 1001}

# The manifest vk8s applies in the guest.
def Coredns.default_manifest() -> String:
  Coredns.render(Coredns.default_cfg())
