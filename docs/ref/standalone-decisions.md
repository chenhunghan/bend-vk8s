# Standalone and private nodes: vk8s decisions

GOAL.md section 4 asks for a record of each behavior that public sources
do not specify. Each entry says what vcluster's open code shows, what is
closed, and what vk8s does. Each one is a known divergence for
docs/STATUS.md.

## J1. The /node/join handler and its script (src/standalone/join.bend)

What the open code shows (vcluster a8ab30e):

- `vcluster token create` (cmd/vclusterctl/cmd/token/create.go) makes a
  kubeadm bootstrap token Secret `bootstrap-token-<id>` in kube-system,
  with the labels `vcluster.loft.sh/token=true` and
  `vcluster.loft.sh/token-node-type=worker|control-plane`. It prints
  `curl -fsSLk "https://<controlPlaneEndpoint>/node/join?token=<t>" | sh -`
  with no `type`. With `--kubeadm` it prints
  `kubeadm join <endpoint> --token <t> --discovery-token-ca-cert-hash <hash>`.
- The docker driver (pkg/cli/create_docker.go:741-748) fetches
  `/node/join?token=<t>&type=worker` and runs the script with
  `--bundle-path ... --force-join`. Its token is a 64-char random string
  from token.txt, not a bootstrap token.
- vcluster-docs list the script flags: `--kubernetes-version`,
  `--repository-url`, `--binaries-dir`, `--cni-binaries-dir`,
  `--skip-reset`, `--bundle-path`, `--reset-only`, `--skip-join`,
  `--node-name`, `--force-join`, `--skip-selinux-rpm`,
  `--selinux-rpm-url`, `--containerd-selinux`.

What is closed: the handler that serves /node/join (vcluster-pro), how it
checks the token, and the text of its script.

What vk8s does:

1. Request. `Join.parse_request` reads `/node/join?<query>` as Go's
   `r.URL.Query()` does: `token` is required (401 `missing token`), and
   `type` is optional and must be `worker` or `control-plane` (400). Any
   other path is 404.
2. Lookup. `Join.lookup` names the Secret `bootstrap-token-<id>` in
   kube-system. A malformed token gets no lookup.
3. Authorization. `Join.authorize` accepts the token as kube-apiserver's
   bootstrap token authenticator does (not deleted, the bootstrap token
   type, the id and the secret match, not expired,
   `usage-bootstrap-authentication=true`, valid extra groups). The node
   type is the Secret's `vcluster.loft.sh/token-node-type` label, `worker`
   when the label is absent (a plain `kubeadm token create` token). When
   the request names a type, it must be the token's type (403
   otherwise). The expiration is checked first; every check only
   refuses, so the order does not change the answer.
4. Only bootstrap tokens. vk8s does not accept the docker driver's 64-char
   token. The host code of `vk8s create --nodes N` must create a
   bootstrap token Secret for its own workers instead (not done yet).
   The request shape stays the same (`token=<t>&type=worker`).
5. Script. `Join.script` is a POSIX sh script. It accepts every
   documented flag. It acts on `--force-join`, `--skip-join`,
   `--reset-only` and `--node-name`. It ignores the download flags,
   because vk8s guests carry their binaries. Then it runs
   `kubeadm join <endpoint> --token <t> --discovery-token-ca-cert-hash
   <hash>`. A node that has joined already (it has
   /etc/kubernetes/kubelet.conf) exits 0 unless `--force-join` is given.
   Then the script runs `kubeadm reset --force` first.
6. Control-plane joins are refused: the script for a control-plane token
   exits 1 with `vk8s does not join control-plane nodes yet`. vcluster's
   control-plane path also downloads `/node/control-plane-download/<t>`,
   which is closed source.

Open points:

- kubeadm's kubelet-start phase calls systemctl. vk8s guests have no
  systemd (DESIGN.md, PID 1 supervision). The host side that serves the
  script must give kubeadm a systemctl shim, or the script must use
  `kubeadm join phase` with the kubelet started by the guest supervisor.
  This needs a spike on the VM.
- `vk8s token create --expires` needs Go's time.ParseDuration. The pure
  module takes the TTL in seconds (`Join.expiry`).
