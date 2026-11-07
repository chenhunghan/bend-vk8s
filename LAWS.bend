import Base

# The project's spec. Each module's laws live in laws/<module>.bend; this file
# gathers them. Laws are architect-owned: agents never edit an existing law.

import ./laws/sha256.bend as Laws_sha256
import ./laws/names.bend as Laws_names
import ./laws/meta.bend as Laws_meta
import ./laws/core.bend as Laws_core
import ./laws/services.bend as Laws_services
import ./laws/supervise.bend as Laws_supervise
import ./laws/mappings.bend as Laws_mappings
import ./laws/args.bend as Laws_args
import ./laws/plan.bend as Laws_plan
import ./laws/cli.bend as Laws_cli
import ./laws/kubeconfig.bend as Laws_kubeconfig
import ./laws/subject.bend as Laws_subject
import ./laws/nodes.bend as Laws_nodes
import ./laws/configs.bend as Laws_configs
import ./laws/table.bend as Laws_table
import ./laws/duration.bend as Laws_duration
import ./laws/assets.bend as Laws_assets
