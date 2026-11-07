import Base

# vcluster pkg/util/command: MergeArgs and ContainsFlag, which vcluster uses
# to lay a component's extraArgs over its base command line.

# Go: strings.HasPrefix(s, "--").
def Args.is_flag(s: String) -> Bool:
  String.starts_with(s, "--")

def Args.key.cut(at_eq: Bool, c: Char, rest: String) -> String:
  match at_eq:
    case True{}:
      SNil{}
    case False{}:
      SCon{c, rest}

# Go: before, _, _ := strings.Cut(s, "="): s up to its first '='.
def Args.key(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+c, t}:
      Args.key.cut(Char.is_eq(c, '='), c, Args.key(t))

# One iteration of ContainsFlag's loop: both are flags and name the same key.
def Args.same(+arg: String, +flag: String) -> Bool:
  Args.is_flag(arg) && Args.is_flag(flag) && String.eq(Args.key(arg), Args.key(flag))

# Go: ContainsFlag(args, flag): some arg of args is a flag with flag's key.
# Non-flag args (no "--") never match, and neither does a non-flag flag.
def Args.contains_flag(args: +List<String>, +flag: String) -> Bool:
  match args:
    case Nil{}:
      False{}
    case Con{+a, t}:
      Args.same(a, flag) || Args.contains_flag(t, flag)

def Args.keep.put(named: Bool, b: String, rest: +List<String>) -> +List<String>:
  match named:
    case True{}:
      rest
    case False{}:
      Con{b, rest}

# The base args that no extra arg names, in order.
def Args.keep(base: +List<String>, +extra: +List<String>) -> +List<String>:
  match base:
    case Nil{}:
      Nil{}
    case Con{+b, t}:
      Args.keep.put(Args.contains_flag(extra, b), b, Args.keep(t, extra))

# Go: MergeArgs(baseArgs, extraArgs): every base arg whose flag the extras
# do not name, then every extra arg, in order.
def Args.merge(base: +List<String>, +extra: +List<String>) -> +List<String>:
  List.append(&2, String, Args.keep(base, extra), extra)
