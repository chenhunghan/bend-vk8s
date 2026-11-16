import Base
import ./cli.bend as C

# docs/GOAL.md section 8: intended OS defaults. The effective default
# stays vm until the backend's regression and certified runs pass.
def Backend.default_for.go(linux: Bool) -> String:
  match linux:
    case True{}:
      "native"
    case False{}:
      "container"

def Backend.default_for(os: String) -> String:
  Backend.default_for.go(String.eq(os, "Linux"))

def Backend.effective.go(empty: Bool, requested: String) -> String:
  match empty:
    case True{}:
      "vm"
    case False{}:
      requested

def Backend.effective(os: String, +requested: String) -> String:
  Backend.effective.go(String.is_empty(requested), requested)

def Backend.valid(+name: String) -> Bool:
  String.eq(name, "vm") || String.eq(name, "container") || String.eq(name, "native")

type Selection is Data:
  Selected{backend: String, command: C.Cmd}

def Backend.pick.valid(ok: Bool, backend: String, args: +List<String>) -> Selection:
  match ok:
    case True{}:
      Selected{backend, C.Cli.parse(args)}
    case False{}:
      Selected{"vm", C.Help{"vk8s: --backend must be vm, container or native\n"}}

def Backend.pick(has: Bool, value: Maybe<&2, String>, args: +List<String>) -> Selection:
  match has value:
    case False{} _:
      Selected{"vm", C.Cli.parse(args)}
    case True{} Some{+backend}:
      Backend.pick.valid(Backend.valid(backend), backend, C.Cli.drop_flag(args, "--backend"))
    case True{} None{}:
      Selected{"vm", C.Help{"vk8s: --backend needs a value (vm, container or native)\n"}}

# A separate entry preserves the parser contract used by existing laws.
def Backend.parse(+args: +List<String>) -> Selection:
  Backend.pick(C.Cli.has(args, "--backend"), C.Cli.after(args, "--backend"), args)
