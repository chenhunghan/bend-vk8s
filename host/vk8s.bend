import Base
import 0xeedc51d20a9b77c2ac19c4d8f57d45a6/main.bend as V

# vk8s: one binary. `vk8s vmm <bend-vmm flags>` runs the VMM in this process
# (bend-vmm as a library, one VM per process); the cluster commands start
# such processes.

def Vk8s.usage() -> String:
  "usage: vk8s vmm <bend-vmm options>\n"

@unsafe def Vk8s.command(is_vmm: Bool, rest: List<String>) -> IO(Unit):
  match is_vmm:
    case True{}:
      V.Vmm.run(["vk8s", "vmm"], rest)
    case False{}:
      IO.print_err(Vk8s.usage())

@unsafe def Vk8s.dispatch(args: List<String>) -> IO(Unit):
  match args:
    case Con{prog, Con{cmd, rest}}:
      Vk8s.command(String.eq(cmd, "vmm"), rest)
    case _:
      IO.print_err(Vk8s.usage())

@unsafe def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    Vk8s.dispatch(args)
