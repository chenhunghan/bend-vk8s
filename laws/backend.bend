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

# Proposed: v2 defaults (docs/GOAL.md section 8, user decision 2026-11-16):
# native on Linux once it is certified; macOS stays vm until container
# mode measures lighter. An explicit --backend still wins.
law backend.default_v2_linux:
  {B.Backend.default.v2("Linux") == "native" : String}

law backend.default_v2_mac:
  {B.Backend.default.v2("Darwin") == "vm" : String}

law backend.parse_v2_linux_default:
  {B.Backend.parse.v2("Linux", ["create", "demo", "--nodes", "1"]) ==
    B.Selected{"native", C.Create{"demo", 0, 2, 2048, False{}, 1}} : B.Selection}

law backend.parse_v2_mac_default:
  {B.Backend.parse.v2("Darwin", ["create", "demo", "--nodes", "1"]) ==
    B.Selected{"vm", C.Create{"demo", 0, 2, 2048, False{}, 1}} : B.Selection}

law backend.parse_v2_linux_explicit_vm:
  {B.Backend.parse.v2("Linux", ["create", "demo", "--backend", "vm", "--nodes", "1"]) ==
    B.Selected{"vm", C.Create{"demo", 0, 2, 2048, False{}, 1}} : B.Selection}
