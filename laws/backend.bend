import Base
import ../src/cli/backend.bend as B
import ../src/cli/cli.bend as C

# Proposed: user decisions in docs/GOAL.md section 8. These are vk8s
# policy, not defaults inferred from vcluster or from implementation.
law backend.linux_default:
  {B.Backend.default_for("Linux") == "native" : String}

law backend.mac_default:
  {B.Backend.default_for("Darwin") == "container" : String}

law backend.effective_vm:
  for os: String
  {B.Backend.effective(os, "") == "vm" : String}

law backend.explicit_container:
  {B.Backend.parse(["create", "demo", "--backend", "container", "--nodes", "1"]) ==
    B.Selected{"container", C.Create{"demo", 0, 2, 2048, False{}, 1}} : B.Selection}

law backend.missing_value:
  {B.Backend.parse(["create", "demo", "--backend"]) ==
    B.Selected{"vm", C.Help{"vk8s: --backend needs a value (vm, container or native)\n"}} : B.Selection}

law backend.invalid_value:
  {B.Backend.parse(["create", "demo", "--backend", "docker"]) ==
    B.Selected{"vm", C.Help{"vk8s: --backend must be vm, container or native\n"}} : B.Selection}
