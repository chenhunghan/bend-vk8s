import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/config/yaml.bend as Y

# Proposed: supported YAML block subset, per YAML scalar and block syntax.

def T.eq(+n: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ n)
    case False{}:
      IO.print("FAIL " ++ n)

def T.check(+n: String, r: Result<&2, &2, String, J.Json>, expected: String) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.print("FAIL " ++ n ++ ": " ++ e)
    case Done{j}:
      T.eq(n, String.eq(J.Json.show(j), expected))

def main() -> IO(Unit):
  do IO<Unit>:
    T.check("empty", Y.Yaml.parse(""), "{}")
    T.check("block_maps", Y.Yaml.parse("a:\n  b: value\n"), "{\"a\":{\"b\":\"value\"}}")
    T.check("sequence", Y.Yaml.parse("args:\n  - one\n  - two\n"), "{\"args\":[\"one\",\"two\"]}")
    T.check("indentless_sequence", Y.Yaml.parse("args:\n- one\n- two\nend: true\n"), "{\"args\":[\"one\",\"two\"],\"end\":true}")
    T.check("scalars", Y.Yaml.parse("a: true\nb: false\nc: null\nd: 12\ne: text\n"), "{\"a\":true,\"b\":false,\"c\":null,\"d\":12,\"e\":\"text\"}")
    T.check("quotes", Y.Yaml.parse("a: 'it''s # literal'\nb: \"line\\nnext\" # comment\n"), "{\"a\":\"it's # literal\",\"b\":\"line\\nnext\"}")
    T.check("comments", Y.Yaml.parse("# header\na: value # tail\nb: x#y\n"), "{\"a\":\"value\",\"b\":\"x#y\"}")
    T.check("empty_containers", Y.Yaml.parse("a: {}\nb: []\n"), "{\"a\":{},\"b\":[]}")
    T.check("json", Y.Yaml.parse("{\"a\": [\"one\", \"two\"]}"), "{\"a\":[\"one\",\"two\"]}")
    T.check("null_entry", Y.Yaml.parse("a:\nb: x\n"), "{\"a\":null,\"b\":\"x\"}")
