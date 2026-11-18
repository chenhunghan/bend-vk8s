import Base
import ../src/layers/filters.bend as F

# Spec for src/layers/filters.bend: containerd's filter syntax as its
# snapshots service applies ListSnapshots filters. Concrete laws
# transcribe pkg/filters/filter_test.go (TestFilters: the inputs and
# their errors; the field paths and values each input yields there) and
# the parser and scanner of pkg/filters (parser.go, scanner.go,
# quote.go, filter.go), containerd commit
# 932058d3a973e0c099ba2f8619b8a2151cfff7f4.

# filter_test.go "Empty": "" matches every object (no selector).
law layers_filters.empty:
  {F.Flt.parse("") == Some{[]} : Maybe<&2, List<&2, F.Sel>>}

# filter_test.go "Present": a field alone tests presence.
law layers_filters.present:
  {F.Flt.parse("name") == Some{[F.Sel{["name"], F.FHas{}, ""}]} : Maybe<&2, List<&2, F.Sel>>}

# filter_test.go "LabelPresent": a field path.
law layers_filters.label_present:
  {F.Flt.parse("labels.foo") == Some{[F.Sel{["labels", "foo"], F.FHas{}, ""}]} : Maybe<&2, List<&2, F.Sel>>}

# filter_test.go "NameAndLabelPresent": comma is AND.
law layers_filters.and:
  {F.Flt.parse("labels.foo,name") == Some{[F.Sel{["labels", "foo"], F.FHas{}, ""}, F.Sel{["name"], F.FHas{}, ""}]} : Maybe<&2, List<&2, F.Sel>>}

# filter_test.go "LabelValue".
law layers_filters.label_value:
  {F.Flt.parse("labels.foo==true") == Some{[F.Sel{["labels", "foo"], F.FEq{}, "true"}]} : Maybe<&2, List<&2, F.Sel>>}

# filter_test.go "LabelValuePunctuated": a value runs to "," or space.
law layers_filters.value_punct:
  {F.Flt.parse("labels.foo==omg_asdf.asdf-qwer") == Some{[F.Sel{["labels", "foo"], F.FEq{}, "omg_asdf.asdf-qwer"}]} : Maybe<&2, List<&2, F.Sel>>}

# filter_test.go "LabelValueNoAltQuoting": "invalid quote encountered".
law layers_filters.no_alt_quoting:
  {F.Flt.parse("labels.|foo|==omg_asdf.asdf-qwer") == None{} : Maybe<&2, List<&2, F.Sel>>}

# filter_test.go "NameNotEqual".
law layers_filters.not_equal:
  {F.Flt.parse("name!=bar") == Some{[F.Sel{["name"], F.FNe{}, "bar"}]} : Maybe<&2, List<&2, F.Sel>>}

# filter_test.go "QuotedValue".
law layers_filters.quoted_value:
  {F.Flt.parse("other==\"too complex, yo\"") == Some{[F.Sel{["other"], F.FEq{}, "too complex, yo"}]} : Maybe<&2, List<&2, F.Sel>>}

# filter_test.go "LabelQuotedFieldPathPresent".
law layers_filters.quoted_field:
  {F.Flt.parse("name==foo,labels.\"more complex label\"") == Some{[F.Sel{["name"], F.FEq{}, "foo"}, F.Sel{["labels", "more complex label"], F.FHas{}, ""}]} : Maybe<&2, List<&2, F.Sel>>}

# filter_test.go "LabelQuotedFieldPathPresentWithQuoted": \\ and \" in a quoted field.
law layers_filters.quoted_escapes:
  {F.Flt.parse("labels.\"more complex label with \\\\ and \\\"\"==present") == Some{[F.Sel{["labels", "more complex label with \\ and \""], F.FEq{}, "present"}]} : Maybe<&2, List<&2, F.Sel>>}

# filter_test.go "LabelQuotedFieldPathPresentWithQuotedEmbed".
law layers_filters.quoted_embed:
  {F.Flt.parse("labels.\"more complex label with \\\\ and \\\"\".post==present") == Some{[F.Sel{["labels", "more complex label with \\ and \"", "post"], F.FEq{}, "present"}]} : Maybe<&2, List<&2, F.Sel>>}

# filter_test.go "LabelQuotedFieldPathPresentWithQuotedEmbedInvalid": "expected field or quoted".
law layers_filters.quoted_embed_invalid:
  {F.Flt.parse("labels.?\"more complex label with \\\\ and \\\"\".post==present") == None{} : Maybe<&2, List<&2, F.Sel>>}

# filter_test.go "TrailingComma": "expected field or quoted".
law layers_filters.trailing_comma:
  {F.Flt.parse("name==foo,") == None{} : Maybe<&2, List<&2, F.Sel>>}

# filter_test.go "TrailingFieldSeparator": "expected field or quoted".
law layers_filters.trailing_period:
  {F.Flt.parse("labels.") == None{} : Maybe<&2, List<&2, F.Sel>>}

# filter_test.go "MissingValue": "expected value or quoted".
law layers_filters.missing_value:
  {F.Flt.parse("image~=,id?=?fbaq") == None{} : Maybe<&2, List<&2, F.Sel>>}

# filter_test.go "FieldQuotedLiteralNotTerminated": "quoted literal not terminated".
law layers_filters.slash_in_field:
  {F.Flt.parse("labels.ns/key==value") == None{} : Maybe<&2, List<&2, F.Sel>>}

# filter_test.go "ValueQuotedLiteralNotTerminated": "quoted literal not terminated".
law layers_filters.slash_value:
  {F.Flt.parse("labels.key==/value") == None{} : Maybe<&2, List<&2, F.Sel>>}

# scanner.go scan: white space before a token is skipped.
law layers_filters.spaces:
  {F.Flt.parse("name == bar") == Some{[F.Sel{["name"], F.FEq{}, "bar"}]} : Maybe<&2, List<&2, F.Sel>>}

# parser.go selectors: after a value only "," or the end may follow ("unexpected input").
law layers_filters.trailing_space:
  {F.Flt.parse("name==bar ") == None{} : Maybe<&2, List<&2, F.Sel>>}

# parser.go operator: "unsupported operator".
law layers_filters.unsupported_operator:
  {F.Flt.parse("name=bar") == None{} : Maybe<&2, List<&2, F.Sel>>}

# parser.go: "~=" takes a value; a pattern of plain characters.
law layers_filters.regexp_literal:
  {F.Flt.parse("name~=fo") == Some{[F.Sel{["name"], F.FRe{}, "fo"}]} : Maybe<&2, List<&2, F.Sel>>}

# filter_test.go "RegexpQuotedValue": / quotes a "~=" value (here a plain pattern).
law layers_filters.regexp_slash_quoted:
  {F.Flt.parse("other~=/abc/,name!=foo") == Some{[F.Sel{["other"], F.FRe{}, "abc"}, F.Sel{["name"], F.FNe{}, "foo"}]} : Maybe<&2, List<&2, F.Sel>>}

# quote.go unquoteChar: \x41 is "A".
law layers_filters.hex_escape:
  {F.Flt.parse("labels.\"\\x41\"") == Some{[F.Sel{["labels", "A"], F.FHas{}, ""}]} : Maybe<&2, List<&2, F.Sel>>}

# parser.go ParseAll: no filter matches everything.
law layers_filters.all_none:
  {F.Flt.parse_all([]) == Some{[[]]} : Maybe<&2, List<&2, List<&2, F.Sel>>>}

# testsuite.go checkWalk: filters ["name==p", "name==a-np-wl"] are ORed (ParseAll: Any).
law layers_filters.all_any:
  {F.Flt.parse_all(["name==p", "name==a-np-wl"]) == Some{[[F.Sel{["name"], F.FEq{}, "p"}], [F.Sel{["name"], F.FEq{}, "a-np-wl"}]]} : Maybe<&2, List<&2, List<&2, F.Sel>>>}

# parser.go ParseAll: one bad filter fails them all (ErrInvalidArgument).
law layers_filters.all_error:
  {F.Flt.parse_all(["name==p", "name==foo,"]) == None{} : Maybe<&2, List<&2, List<&2, F.Sel>>>}

# filter.go selector.Match: operatorPresent is present.
law layers_filters.test_has_absent:
  {F.Flt.test(F.FHas{}, "", None{}) == False{} : Bool}

# filter.go: operatorEqual needs the field present.
law layers_filters.test_eq_absent:
  {F.Flt.test(F.FEq{}, "", None{}) == False{} : Bool}

# filter.go: operatorNotEqual compares the value, "" when absent.
law layers_filters.test_ne_absent:
  {F.Flt.test(F.FNe{}, "bar", None{}) == True{} : Bool}

# filter.go: operatorNotEqual, "" != "" is false.
law layers_filters.test_ne_absent_empty:
  {F.Flt.test(F.FNe{}, "", None{}) == False{} : Bool}

# filter.go: regexp MatchString matches anywhere in the value.
law layers_filters.test_re_substring:
  {F.Flt.test(F.FRe{}, "oe", Some{"fooer"}) == True{} : Bool}
