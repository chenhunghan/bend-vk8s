import Base
import ./LAWS.bend as L

# The gate. Each module's proofs live in proofs/<module>.bend; this file
# gathers them. `bend PROOF.bend` prints ALL PROOFS CHECK once every law holds.

import ./proofs/sha256.bend as Proofs_sha256
import ./proofs/names.bend as Proofs_names
import ./proofs/supervise.bend as Proofs_supervise
import ./proofs/kubeconfig.bend as Proofs_kubeconfig
