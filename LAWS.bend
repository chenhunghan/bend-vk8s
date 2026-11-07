import Base

# The project's spec. Each module's laws live in laws/<module>.bend; this file
# gathers them. Laws are architect-owned: agents never edit an existing law.

import ./laws/sha256.bend as Laws_sha256
import ./laws/names.bend as Laws_names
import ./laws/meta.bend as Laws_meta
import ./laws/services.bend as Laws_services
import ./laws/supervise.bend as Laws_supervise
import ./laws/args.bend as Laws_args
import ./laws/plan.bend as Laws_plan
import ./laws/cli.bend as Laws_cli
