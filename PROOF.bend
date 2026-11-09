import Base
import ./LAWS.bend as L

# The gate. Each module's proofs live in proofs/<module>.bend; this file
# gathers them. `bend PROOF.bend` prints ALL PROOFS CHECK once every law holds.

import ./proofs/sha256.bend as Proofs_sha256
import ./proofs/names.bend as Proofs_names
import ./proofs/meta.bend as Proofs_meta
import ./proofs/core.bend as Proofs_core
import ./proofs/services.bend as Proofs_services
import ./proofs/pods.bend as Proofs_pods
import ./proofs/supervise.bend as Proofs_supervise
import ./proofs/mappings.bend as Proofs_mappings
import ./proofs/args.bend as Proofs_args
import ./proofs/plan.bend as Proofs_plan
import ./proofs/cli.bend as Proofs_cli
import ./proofs/kubeconfig.bend as Proofs_kubeconfig
import ./proofs/subject.bend as Proofs_subject
import ./proofs/join.bend as Proofs_join
import ./proofs/storage.bend as Proofs_storage
import ./proofs/nodes.bend as Proofs_nodes
import ./proofs/configs.bend as Proofs_configs
import ./proofs/table.bend as Proofs_table
import ./proofs/duration.bend as Proofs_duration
import ./proofs/assets.bend as Proofs_assets
import ./proofs/manifest.bend as Proofs_manifest
import ./proofs/kubelet.bend as Proofs_kubelet
import ./proofs/endpoint.bend as Proofs_endpoint
import ./proofs/token.bend as Proofs_token
import ./proofs/certs.bend as Proofs_certs
import ./proofs/values.bend as Proofs_values
import ./proofs/config_yaml.bend as Proofs_config_yaml
import ./proofs/vcluster_config.bend as Proofs_vcluster_config
import ./proofs/snapshot.bend as Proofs_snapshot
import ./proofs/coredns.bend as Proofs_coredns
