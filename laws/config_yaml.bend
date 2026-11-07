import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/config/yaml.bend as Y

# Proposed: supported YAML block subset, per YAML scalar and block syntax.

law config_yaml.empty:
  {Y.Yaml.parse("") == Done{J.Json.obj([])} : Result<&2, &2, String, J.Json>}

law config_yaml.block_maps:
  {Y.Yaml.parse("a:\n  b: value\n") == Done{J.Json.obj([J.KV{"a", J.Json.obj([J.KV{"b", J.JStr{"value"}}])}])} : Result<&2, &2, String, J.Json>}

law config_yaml.sequence:
  {Y.Yaml.parse("args:\n  - one\n  - two\n") == Done{J.Json.obj([J.KV{"args", J.Json.arr([J.JStr{"one"}, J.JStr{"two"}])}])} : Result<&2, &2, String, J.Json>}

law config_yaml.indentless_sequence:
  {Y.Yaml.parse("args:\n- one\n- two\nend: true\n") == Done{J.Json.obj([J.KV{"args", J.Json.arr([J.JStr{"one"}, J.JStr{"two"}])}, J.KV{"end", J.JBool{True{}}}])} : Result<&2, &2, String, J.Json>}

law config_yaml.scalars:
  {Y.Yaml.parse("a: true\nb: false\nc: null\nd: 12\ne: text\n") == Done{J.Json.obj([J.KV{"a", J.JBool{True{}}}, J.KV{"b", J.JBool{False{}}}, J.KV{"c", J.JNull{}}, J.KV{"d", J.JNum{"12"}}, J.KV{"e", J.JStr{"text"}}])} : Result<&2, &2, String, J.Json>}

law config_yaml.quotes:
  {Y.Yaml.parse("a: 'it''s # literal'\nb: \"line\\nnext\" # comment\n") == Done{J.Json.obj([J.KV{"a", J.JStr{"it's # literal"}}, J.KV{"b", J.JStr{"line\nnext"}}])} : Result<&2, &2, String, J.Json>}

law config_yaml.comments:
  {Y.Yaml.parse("# header\na: value # tail\nb: x#y\n") == Done{J.Json.obj([J.KV{"a", J.JStr{"value"}}, J.KV{"b", J.JStr{"x#y"}}])} : Result<&2, &2, String, J.Json>}

law config_yaml.empty_containers:
  {Y.Yaml.parse("a: {}\nb: []\n") == Done{J.Json.obj([J.KV{"a", J.Json.obj([])}, J.KV{"b", J.Json.arr([])}])} : Result<&2, &2, String, J.Json>}

law config_yaml.json:
  {Y.Yaml.parse("{\"a\": [\"one\", \"two\"]}") == Done{J.Json.obj([J.KV{"a", J.Json.arr([J.JStr{"one"}, J.JStr{"two"}])}])} : Result<&2, &2, String, J.Json>}

law config_yaml.null_entry:
  {Y.Yaml.parse("a:\nb: x\n") == Done{J.Json.obj([J.KV{"a", J.JNull{}}, J.KV{"b", J.JStr{"x"}}])} : Result<&2, &2, String, J.Json>}

# Proposed: reject syntax outside the supported subset rather than drop it.
law config_yaml.duplicate_key:
  {Y.Yaml.parse("a: one\na: two\n") == Fail{"yaml: duplicate key a"} : Result<&2, &2, String, J.Json>}

law config_yaml.bad_indent:
  {Y.Yaml.parse("a: one\n  b: two\n") == Fail{"yaml: invalid mapping indentation"} : Result<&2, &2, String, J.Json>}

law config_yaml.multiple_documents:
  {Y.Yaml.parse("a: one\n---\nb: two\n") == Fail{"yaml: multiple documents are outside the supported subset"} : Result<&2, &2, String, J.Json>}

law config_yaml.unclosed_single:
  {Y.Yaml.parse("a: 'one\n") == Fail{"yaml: unterminated single-quoted string"} : Result<&2, &2, String, J.Json>}

law config_yaml.block_scalar_rejected:
  {Y.Yaml.parse("a: |\n  text\n") == Fail{"yaml: block scalars are outside the supported subset"} : Result<&2, &2, String, J.Json>}

law config_yaml.quoted_key:
  {Y.Yaml.parse("'a: b': value\n") == Done{J.Json.obj([J.KV{"a: b", J.JStr{"value"}}])} : Result<&2, &2, String, J.Json>}

law config_yaml.sequence_maps:
  {Y.Yaml.parse("items:\n  - name: first\n    enabled: true\n  - name: second\n") == Done{J.Json.obj([J.KV{"items", J.Json.arr([J.Json.obj([J.KV{"name", J.JStr{"first"}}, J.KV{"enabled", J.JBool{True{}}}]), J.Json.obj([J.KV{"name", J.JStr{"second"}}])])}])} : Result<&2, &2, String, J.Json>}

# Proposed: single quotes may appear inside a quoted scalar only doubled.
law config_yaml.invalid_single_escape:
  {Y.Yaml.parse("a: 'one'two'\n") == Fail{"yaml: invalid single-quoted string"} : Result<&2, &2, String, J.Json>}

law config_yaml.tab_indentation:
  {Y.Yaml.parse("a:\n\tb: value\n") == Fail{"yaml: tab indentation is outside the supported subset"} : Result<&2, &2, String, J.Json>}

law config_yaml.apostrophe_plain:
  {Y.Yaml.parse("a: it's fine # comment\n") == Done{J.Json.obj([J.KV{"a", J.JStr{"it's fine"}}])} : Result<&2, &2, String, J.Json>}
