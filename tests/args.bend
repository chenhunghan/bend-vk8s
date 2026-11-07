import Base
import ../src/lib/args.bend as A

# vcluster pkg/util/command/command_test.go, run: one PASS/FAIL line per
# case of TestMergeArgs and TestContainsFlag.

def T.check(+name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name)

def T.same(xs: +List<String>, ys: +List<String>) -> Bool:
  String.eq(String.join(xs, "\n"), String.join(ys, "\n"))

def T.is(a: Bool, b: Bool) -> Bool:
  match a b:
    case True{} True{}:
      True{}
    case False{} False{}:
      True{}
    case _ _:
      False{}

def main() -> IO(Unit):
  do IO<Unit>:
    T.check("MergeArgs: no extra args",
      T.same(A.Args.merge(["--foo=bar"], []), ["--foo=bar"]))
    T.check("MergeArgs: extra args",
      T.same(A.Args.merge(["--foo=bar"], ["--baz=qux"]), ["--foo=bar", "--baz=qux"]))
    T.check("MergeArgs: extra args with same flag (last)",
      T.same(A.Args.merge(["--foo=bar", "--baz=qux"], ["--baz=quux"]), ["--foo=bar", "--baz=quux"]))
    T.check("MergeArgs: extra args with same flag (first)",
      T.same(A.Args.merge(["--foo=bar", "--baz=qux"], ["--foo=baz"]), ["--baz=qux", "--foo=baz"]))
    T.check("MergeArgs: mutli args with same flag",
      T.same(A.Args.merge(["--foo=bar", "--baz=qux"], ["--foo=bax", "--foo=bay"]),
        ["--baz=qux", "--foo=bax", "--foo=bay"]))
    T.check("MergeArgs: nil extra args",
      T.same(A.Args.merge(["--foo=bar", "--baz=qux"], []), ["--foo=bar", "--baz=qux"]))
    T.check("MergeArgs: no-flags",
      T.same(A.Args.merge(["/test/path", "arg1", "arg2", "--my-flag=true"], []),
        ["/test/path", "arg1", "arg2", "--my-flag=true"]))
    T.check("ContainsFlag: same flag with inline value",
      T.is(A.Args.contains_flag(["--foo=bar"], "--foo"), True{}))
    T.check("ContainsFlag: same flag with split value",
      T.is(A.Args.contains_flag(["--foo", "bar"], "--foo"), True{}))
    T.check("ContainsFlag: different flag",
      T.is(A.Args.contains_flag(["--foobar=baz"], "--foo"), False{}))
    T.check("ContainsFlag: non flag args are ignored",
      T.is(A.Args.contains_flag(["foo"], "--foo"), False{}))
