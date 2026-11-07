import Base

# vcluster pkg/util/command: MergeArgs and ContainsFlag, which vcluster uses
# to lay a component's extraArgs over its base command line.

# Go: strings.HasPrefix(s, "--").
def Args.is_flag(s: String) -> Bool:
  ?TODO

def Args.key.cut(at_eq: Bool, c: Char, rest: String) -> String:
  ?TODO

# Go: before, _, _ := strings.Cut(s, "="): s up to its first '='.
def Args.key(s: String) -> String:
  ?TODO

# One iteration of ContainsFlag's loop: both are flags and name the same key.
def Args.same(+arg: String, +flag: String) -> Bool:
  ?TODO

# Go: ContainsFlag(args, flag): some arg of args is a flag with flag's key.
# Non-flag args (no "--") never match, and neither does a non-flag flag.
def Args.contains_flag(args: +List<String>, +flag: String) -> Bool:
  ?TODO

def Args.keep.put(named: Bool, b: String, rest: +List<String>) -> +List<String>:
  ?TODO

# The base args that no extra arg names, in order.
def Args.keep(base: +List<String>, +extra: +List<String>) -> +List<String>:
  ?TODO

# Go: MergeArgs(baseArgs, extraArgs): every base arg whose flag the extras
# do not name, then every extra arg, in order.
def Args.merge(base: +List<String>, +extra: +List<String>) -> +List<String>:
  ?TODO
