import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J

# A pure block-YAML subset reader. No IO, anchors, tags, block scalars or
# multi-document streams. Flow values must be JSON. A stack holds open
# maps/sequences; closing a child gives its value to its parent's pending
# key/item. Fuel comes from stack length, not a fixed nesting limit.
# Syntax errors are subset diagnostics, not libyaml's line/column messages.

type Frame is Data:
  Mapping{indent: U32, members: J.Json, pending: Maybe<&2, String>}
  Sequence{indent: U32, items: J.Json, pending: Bool}
  Root{value: J.Json}

type Quote is Data:
  Plain{}
  Single{}
  Double{}

type Entry is Data:
  Entry{key: String, rest: String}

def Yaml.indent(s: String, n: U32) -> U32:
  match s:
    case SCon{' ', t}:
      Yaml.indent(t, (n + 1 : U32))
    case _:
      n

# Quote state tracks plain, single and double quotes. Escapes apply in double
# quotes. A doubled single quote leaves the state unchanged after the pair.
def Yaml.next(q: Quote, c: Char) -> Quote:
  match q c:
    case Plain{} '\'':
      Single{}
    case Plain{} '"':
      Double{}
    case Single{} '\'':
      Plain{}
    case Double{} '"':
      Plain{}
    case x _:
      x

def Yaml.quote_at(q: Quote, c: Char, start: Bool) -> Quote:
  match q start:
    case Plain{} False{}:
      Plain{}
    case x _:
      Yaml.next(x, c)

def Yaml.double(q: Quote) -> Bool:
  match q:
    case Double{}:
      True{}
    case _:
      False{}

def Yaml.clean(s: String, +q: Quote, esc: Bool, prev_space: Bool) -> String:
  match s q esc prev_space:
    case SNil{} _ _ _:
      ""
    case SCon{c, t} q True{} _:
      SCon{c, Yaml.clean(t, q, False{}, False{})}
    case SCon{'#', t} Plain{} False{} True{}:
      ""
    case SCon{+c, t} +q False{} sp:
      SCon{c, Yaml.clean(t, Yaml.quote_at(q, c, sp), Bool.and(Yaml.double(q), Char.is_eq(c, '\\')), Char.is_space(c))}

def Yaml.unsingle(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{'\'', SCon{'\'', t}}:
      SCon{'\'', Yaml.unsingle(t)}
    case SCon{c, t}:
      SCon{c, Yaml.unsingle(t)}

def Yaml.single_ok(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{'\'', SCon{'\'', t}}:
      Yaml.single_ok(t)
    case SCon{'\'', t}:
      False{}
    case SCon{c, t}:
      Yaml.single_ok(t)

def Yaml.single_value(s: String, valid: Bool) -> Result<&2, &2, String, J.Json>:
  match valid:
    case True{}:
      Done{J.JStr{Yaml.unsingle(s)}}
    case False{}:
      Fail{"yaml: invalid single-quoted string"}

def Yaml.single(+s: String, closed: Bool) -> Result<&2, &2, String, J.Json>:
  match closed:
    case True{}:
      Yaml.single_value(s, Yaml.single_ok(s))
    case False{}:
      Fail{"yaml: unterminated single-quoted string"}

def Yaml.plain_result(s: String, r: Result<&2, &2, String, J.Json>) -> Result<&2, &2, String, J.Json>:
  match r:
    case Done{v}:
      Done{v}
    case Fail{e}:
      Done{J.JStr{s}}

def Yaml.scalar(+s: String) -> Result<&2, &2, String, J.Json>:
  match s:
    case SNil{}:
      Done{J.JNull{}}
    case SCon{'\'', +t}:
      Yaml.single(String.take(t, Nat.sub(String.length(t), 1n)), String.ends_with(t, "'"))
    case SCon{'"', t}:
      J.Json.parse(s)
    case SCon{'[', t}:
      J.Json.parse(s)
    case SCon{'{', t}:
      J.Json.parse(s)
    case SCon{'&', t}:
      Fail{"yaml: anchors are outside the supported subset"}
    case SCon{'*', t}:
      Fail{"yaml: aliases are outside the supported subset"}
    case SCon{'!', t}:
      Fail{"yaml: tags are outside the supported subset"}
    case SCon{'|', t}:
      Fail{"yaml: block scalars are outside the supported subset"}
    case SCon{'>', t}:
      Fail{"yaml: block scalars are outside the supported subset"}
    case "~":
      Done{J.JNull{}}
    case "Null":
      Done{J.JNull{}}
    case "NULL":
      Done{J.JNull{}}
    case "True":
      Done{J.JBool{True{}}}
    case "TRUE":
      Done{J.JBool{True{}}}
    case "yes":
      Done{J.JBool{True{}}}
    case "on":
      Done{J.JBool{True{}}}
    case "False":
      Done{J.JBool{False{}}}
    case "FALSE":
      Done{J.JBool{False{}}}
    case "no":
      Done{J.JBool{False{}}}
    case "off":
      Done{J.JBool{False{}}}
    case x:
      Yaml.plain_result(x, J.Json.parse(x))

def Yaml.key_string(r: Result<&2, &2, String, J.Json>) -> Result<&2, &2, String, String>:
  match r:
    case Done{J.JStr{s}}:
      Done{s}
    case Done{v}:
      Done{J.Json.show(v)}
    case Fail{e}:
      Fail{e}

# The colon delimiter must be outside quotes and followed by whitespace
# or end-of-line. Colons inside flag values, URLs and quoted keys survive.
def Yaml.key(s: String, +q: Quote, esc: Bool, +acc: String) -> Maybe<&2, Entry>:
  match s q esc:
    case SNil{} _ _:
      None{}
    case SCon{':', SNil{}} Plain{} False{}:
      Some{Entry{String.trim(String.reverse(acc)), ""}}
    case SCon{':', SCon{' ', t}} Plain{} False{}:
      Some{Entry{String.trim(String.reverse(acc)), String.trim(t)}}
    case SCon{':', SCon{'\t', t}} Plain{} False{}:
      Some{Entry{String.trim(String.reverse(acc)), String.trim(t)}}
    case SCon{c, t} +q True{}:
      Yaml.key(t, q, False{}, SCon{c, acc})
    case SCon{+c, t} +q False{}:
      Yaml.key(t, Yaml.quote_at(q, c, String.is_empty(acc)), Bool.and(Yaml.double(q), Char.is_eq(c, '\\')), SCon{c, acc})

def Yaml.reverse(ms: J.Json, acc: J.Json) -> J.Json:
  match ms:
    case J.JMem{k, v, t}:
      Yaml.reverse(t, J.JMem{k, v, acc})
    case J.JCons{v, t}:
      Yaml.reverse(t, J.JCons{v, acc})
    case _:
      acc

def Yaml.pending(ms: J.Json, p: Maybe<&2, String>) -> J.Json:
  match p:
    case None{}:
      ms
    case Some{k}:
      J.JMem{k, J.JNull{}, ms}

def Yaml.pending_item(xs: J.Json, p: Bool) -> J.Json:
  match p:
    case False{}:
      xs
    case True{}:
      J.JCons{J.JNull{}, xs}

def Yaml.value(f: Frame) -> J.Json:
  match f:
    case Mapping{i, ms, p}:
      J.JObj{Yaml.reverse(Yaml.pending(ms, p), J.JNil{})}
    case Sequence{i, xs, p}:
      J.JArr{Yaml.reverse(Yaml.pending_item(xs, p), J.JNil{})}
    case Root{v}:
      v

def Yaml.give(v: J.Json, st: List<&2, Frame>) -> Result<&2, &2, String, List<&2, Frame>>:
  match st:
    case Nil{}:
      Done{[Root{v}]}
    case Con{Mapping{i, ms, Some{k}}, t}:
      Done{Mapping{i, J.JMem{k, v, ms}, None{}} <> t}
    case Con{Sequence{i, xs, True{}}, t}:
      Done{Sequence{i, J.JCons{v, xs}, False{}} <> t}
    case _:
      Fail{"yaml: unexpected nested value"}

def Yaml.ends(st: List<&2, Frame>, +i: U32, dash: Bool) -> Bool:
  match st:
    case Con{Mapping{j, ms, p}, t}:
      U32.is_gt(j, i)
    case Con{Sequence{+j, xs, p}, t}:
      Bool.or(U32.is_gt(j, i), Bool.and(U32.is_eq(j, i), Bool.not(dash)))
    case _:
      False{}

def Yaml.pop(st: List<&2, Frame>) -> Result<&2, &2, String, List<&2, Frame>>:
  match st:
    case Con{f, t}:
      Yaml.give(Yaml.value(f), t)
    case Nil{}:
      Done{Nil{}}

def Yaml.close(fuel: Nat, +st: List<&2, Frame>, +i: U32, +dash: Bool, ends: Bool) -> Result<&2, &2, String, List<&2, Frame>>:
  match fuel ends:
    case 1n+f True{}:
      do Result<&2, &2, String, List<&2, Frame>>:
        +next : List<&2, Frame> <- Yaml.pop(st)
        Yaml.close(f, next, i, dash, Yaml.ends(next, i, dash))
    case _ _:
      Done{st}

def Yaml.has(ms: J.Json, +k: String) -> Bool:
  match ms:
    case J.JMem{n, v, t}:
      Bool.or(String.eq(n, k), Yaml.has(t, k))
    case _:
      False{}

def Yaml.member(+i: U32, ms: J.Json, +k: String, r: String, empty: Bool, duplicate: Bool, tail: List<&2, Frame>) -> Result<&2, &2, String, List<&2, Frame>>:
  match empty duplicate:
    case _ True{}:
      Fail{"yaml: duplicate key " ++ k}
    case True{} False{}:
      Done{Mapping{i, ms, Some{k}} <> tail}
    case False{} False{}:
      do Result<&2, &2, String, List<&2, Frame>>:
        v : J.Json <- Yaml.scalar(r)
        return Mapping{i, J.JMem{k, v, ms}, None{}} <> tail

def Yaml.parent(st: List<&2, Frame>, +i: U32, dash: Bool) -> Bool:
  match st:
    case Nil{}:
      True{}
    case Con{Mapping{j, ms, Some{k}}, t}:
      Bool.or(U32.is_gt(i, j), Bool.and(dash, U32.is_eq(i, j)))
    case Con{Sequence{j, xs, True{}}, t}:
      U32.is_gt(i, j)
    case _:
      False{}

def Yaml.new_map(st: List<&2, Frame>, i: U32, k: String, +r: String, allowed: Bool) -> Result<&2, &2, String, List<&2, Frame>>:
  match allowed:
    case True{}:
      Yaml.member(i, J.JNil{}, k, r, String.is_empty(r), False{}, st)
    case False{}:
      Fail{"yaml: invalid mapping indentation"}

def Yaml.map_at(st: List<&2, Frame>, +i: U32) -> Bool:
  match st:
    case Con{Mapping{j, ms, p}, t}:
      U32.is_eq(j, i)
    case _:
      False{}

def Yaml.map_put(st: List<&2, Frame>, i: U32, +k: String, +r: String, here: Bool, allowed: Bool) -> Result<&2, &2, String, List<&2, Frame>>:
  match st here:
    case Con{Mapping{j, +ms, +p}, t} True{}:
      Yaml.member(i, Yaml.pending(ms, p), k, r, String.is_empty(r), Yaml.has(Yaml.pending(ms, p), k), t)
    case s _:
      Yaml.new_map(s, i, k, r, allowed)

def Yaml.map_entry(+st: List<&2, Frame>, +i: U32, e: Entry) -> Result<&2, &2, String, List<&2, Frame>>:
  match e:
    case Entry{k, r}:
      do Result<&2, &2, String, List<&2, Frame>>:
        name : String <- Yaml.key_string(Yaml.scalar(k))
        Yaml.map_put(st, i, name, r, Yaml.map_at(st, i), Yaml.parent(st, i, False{}))

def Yaml.seq_at(st: List<&2, Frame>, +i: U32) -> Bool:
  match st:
    case Con{Sequence{j, xs, p}, t}:
      U32.is_eq(j, i)
    case _:
      False{}

def Yaml.seq_open(st: List<&2, Frame>, i: U32, here: Bool, allowed: Bool) -> Result<&2, &2, String, List<&2, Frame>>:
  match st here allowed:
    case Con{Sequence{j, xs, p}, t} True{} _:
      Done{Sequence{j, Yaml.pending_item(xs, p), True{}} <> t}
    case s False{} True{}:
      Done{Sequence{i, J.JNil{}, True{}} <> s}
    case _ _ _:
      Fail{"yaml: invalid sequence indentation"}

def Yaml.seq_scalar(st: List<&2, Frame>, r: String, empty: Bool) -> Result<&2, &2, String, List<&2, Frame>>:
  match empty:
    case True{}:
      Done{st}
    case False{}:
      do Result<&2, &2, String, List<&2, Frame>>:
        v : J.Json <- Yaml.scalar(r)
        Yaml.give(v, st)

def Yaml.item(st: List<&2, Frame>, i: U32, +r: String, e: Maybe<&2, Entry>) -> Result<&2, &2, String, List<&2, Frame>>:
  match e:
    case Some{x}:
      Yaml.map_entry(st, (i + 2 : U32), x)
    case None{}:
      Yaml.seq_scalar(st, r, String.is_empty(r))

def Yaml.dash(t: String) -> Bool:
  match t:
    case "-":
      True{}
    case SCon{'-', SCon{' ', r}}:
      True{}
    case _:
      False{}

def Yaml.entry(st: List<&2, Frame>, i: U32, t: String, e: Maybe<&2, Entry>) -> Result<&2, &2, String, List<&2, Frame>>:
  match e:
    case Some{x}:
      Yaml.map_entry(st, i, x)
    case None{}:
      do Result<&2, &2, String, List<&2, Frame>>:
        v : J.Json <- Yaml.scalar(t)
        Yaml.give(v, st)

def Yaml.line(+st: List<&2, Frame>, +i: U32, +t: String, dash: Bool) -> Result<&2, &2, String, List<&2, Frame>>:
  match dash:
    case True{}:
      do Result<&2, &2, String, List<&2, Frame>>:
        next : List<&2, Frame> <- Yaml.seq_open(st, i, Yaml.seq_at(st, i), Yaml.parent(st, i, True{}))
        Yaml.item(next, i, String.trim(String.drop(t, 1n)), Yaml.key(String.trim(String.drop(t, 1n)), Plain{}, False{}, ""))
    case False{}:
      Yaml.entry(st, i, t, Yaml.key(t, Plain{}, False{}, ""))

def Yaml.step(+st: List<&2, Frame>, +i: U32, +t: String, skip: Bool) -> Result<&2, &2, String, List<&2, Frame>>:
  match skip:
    case True{}:
      Done{st}
    case False{}:
      do Result<&2, &2, String, List<&2, Frame>>:
        next : List<&2, Frame> <- Yaml.close(List.length(&2, Frame, st), st, i, Yaml.dash(t), Yaml.ends(st, i, Yaml.dash(t)))
        Yaml.line(next, i, t, Yaml.dash(t))

def Yaml.document_line(+st: List<&2, Frame>, +i: U32, +t: String) -> Result<&2, &2, String, List<&2, Frame>>:
  match st t:
    case Nil{} "---":
      Done{Nil{}}
    case _ "---":
      Fail{"yaml: multiple documents are outside the supported subset"}
    case _ "...":
      Fail{"yaml: document end markers are outside the supported subset"}
    case +stack +text:
      Yaml.step(stack, i, text, String.is_empty(text))

def Yaml.spaces(s: String) -> Bool:
  match s:
    case SCon{' ', t}:
      Yaml.spaces(t)
    case SCon{'\t', t}:
      False{}
    case _:
      True{}

def Yaml.checked_line(st: List<&2, Frame>, i: U32, t: String, spaces: Bool) -> Result<&2, &2, String, List<&2, Frame>>:
  match spaces:
    case True{}:
      Yaml.document_line(st, i, t)
    case False{}:
      Fail{"yaml: tab indentation is outside the supported subset"}

def Yaml.feed(ls: List<&2, String>, st: List<&2, Frame>) -> Result<&2, &2, String, List<&2, Frame>>:
  match ls:
    case Nil{}:
      Done{st}
    case Con{+l, t}:
      do Result<&2, &2, String, List<&2, Frame>>:
        +clean : String = String.trim(Yaml.clean(l, Plain{}, False{}, True{}))
        next : List<&2, Frame> <- Yaml.checked_line(st, Yaml.indent(l, 0), clean, Yaml.spaces(l))
        Yaml.feed(t, next)

def Yaml.finish(fuel: Nat, st: List<&2, Frame>) -> Result<&2, &2, String, J.Json>:
  match fuel st:
    case _ Nil{}:
      Done{J.JObj{J.JNil{}}}
    case _ Con{f, Nil{}}:
      Done{Yaml.value(f)}
    case 1n+f s:
      do Result<&2, &2, String, J.Json>:
        next : List<&2, Frame> <- Yaml.pop(s)
        Yaml.finish(f, next)
    case _ _:
      Fail{"yaml: unclosed container"}

def Yaml.block(s: String) -> Result<&2, &2, String, J.Json>:
  do Result<&2, &2, String, J.Json>:
    +st : List<&2, Frame> <- Yaml.feed(String.lines(s), Nil{})
    Yaml.finish(List.length(&2, Frame, st), st)

def Yaml.parse(+s: String) -> Result<&2, &2, String, J.Json>:
  match s:
    case SCon{'{', t}:
      J.Json.parse(s)
    case SCon{'[', t}:
      J.Json.parse(s)
    case x:
      Yaml.block(x)
