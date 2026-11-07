import Base
import ../src/lib/args.bend as A

# Spec for src/lib/args.bend (vcluster pkg/util/command MergeArgs and
# ContainsFlag). Each concrete law is one case of
# pkg/util/command/command_test.go, with the test's own expected value.

# TestMergeArgs

# "no extra args"
law args.merge.no_extra_args:
  {A.Args.merge(["--foo=bar"], []) == ["--foo=bar"] : +List<String>}

# "extra args"
law args.merge.extra_args:
  {A.Args.merge(["--foo=bar"], ["--baz=qux"]) == ["--foo=bar", "--baz=qux"] : +List<String>}

# "extra args with same flag" (the first of the two cases of that name)
law args.merge.same_flag_last:
  {A.Args.merge(["--foo=bar", "--baz=qux"], ["--baz=quux"]) == ["--foo=bar", "--baz=quux"] : +List<String>}

# "extra args with same flag" (the second)
law args.merge.same_flag_first:
  {A.Args.merge(["--foo=bar", "--baz=qux"], ["--foo=baz"]) == ["--baz=qux", "--foo=baz"] : +List<String>}

# "mutli args with same flag"
law args.merge.multi_same_flag:
  {A.Args.merge(["--foo=bar", "--baz=qux"], ["--foo=bax", "--foo=bay"])
    == ["--baz=qux", "--foo=bax", "--foo=bay"] : +List<String>}

# "nil extra args" (Go's nil and empty slices are both Nil here)
law args.merge.nil_extra_args:
  {A.Args.merge(["--foo=bar", "--baz=qux"], []) == ["--foo=bar", "--baz=qux"] : +List<String>}

# "no-flags"
law args.merge.no_flags:
  {A.Args.merge(["/test/path", "arg1", "arg2", "--my-flag=true"], [])
    == ["/test/path", "arg1", "arg2", "--my-flag=true"] : +List<String>}

# TestContainsFlag

# "same flag with inline value"
law args.contains.inline_value:
  {A.Args.contains_flag(["--foo=bar"], "--foo") == True{} : Bool}

# "same flag with split value"
law args.contains.split_value:
  {A.Args.contains_flag(["--foo", "bar"], "--foo") == True{} : Bool}

# "different flag"
law args.contains.different_flag:
  {A.Args.contains_flag(["--foobar=baz"], "--foo") == False{} : Bool}

# "non flag args are ignored"
law args.contains.non_flag_ignored:
  {A.Args.contains_flag(["foo"], "--foo") == False{} : Bool}

# General laws.

# MergeArgs keeps every extra arg, in order: they are the tail of the result.
law args.merge.extras_last:
  for base: +List<String>
  for extra: +List<String>
  exs pre: +List<String>
  {A.Args.merge(base, extra) == List.append(&2, String, pre, extra) : +List<String>}

# No base flag that the extras name survives: it is dropped.
law args.merge.named_dropped:
  for x: String
  for base: +List<String>
  for extra: +List<String>
  for h: {A.Args.contains_flag(extra, x) == True{} : Bool}
  {A.Args.merge(Con{x, base}, extra) == A.Args.merge(base, extra) : +List<String>}

# Every other base arg survives, in its place.
law args.merge.unnamed_kept:
  for x: String
  for base: +List<String>
  for extra: +List<String>
  for h: {A.Args.contains_flag(extra, x) == False{} : Bool}
  {A.Args.merge(Con{x, base}, extra) == Con{x, A.Args.merge(base, extra)} : +List<String>}

# Without extras, the base comes back unchanged.
law args.merge.no_extras:
  for base: +List<String>
  {A.Args.merge(base, []) == base : +List<String>}
