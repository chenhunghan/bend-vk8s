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
   token. vk8s's own workers do not use /node/join: `Plan.worker`
   (src/guest/plan.bend) runs `kubeadm join --discovery-file
   --tls-bootstrap-token` and starts the kubelet under the guest
   supervisor, without systemd. Each boot mints its own 1 h bootstrap
   token Secret for them, and `vk8s node add` mints its own (STATUS.md
   section 6, H2). The request shape stays the same
   (`token=<t>&type=worker`) for machines that do use /node/join.
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

7. Answer. `Join.respond` chains `Join.parse_request`, `Join.lookup`,
   `Join.authorize`, `Join.ca_hash` and `Join.script` into one HTTP
   answer (status, content type, body). Its inputs are the method, the
   request target, the token Secret the server found (or none), the CA
   PEM, the kubeadm endpoint (host:port) and the time.
   - The path is checked first, as Go's ServeMux does: any path but
     `/node/join` is 404 with the body `404 page not found` (Go's
     http.NotFound), whatever the method.
   - Only GET is served. Any other method on `/node/join` is 405 `Method
     Not Allowed` with `Allow: GET`. Go's ServeMux also serves HEAD for a
     GET pattern; vk8s does not, because a script has no use without its
     body.
   - An error body is readable plain text (`text/plain; charset=utf-8`),
     as Go's http.Error writes it: the message and a newline.
     vcluster-docs troubleshooting.mdx tells users to read this body. The
     status and the message are the ones `Join.parse_request` and
     `Join.authorize` choose: 400 for a bad `type`; 401 for a missing,
     malformed, unknown, expired or invalid token; 403 for the wrong node
     type. A malformed token gets 401 `malformed token` without a lookup.
     The messages name the check that failed, never the token secret. The
     token id is public by kubeadm's design, so `unknown token` and
     `invalid token` reveal nothing secret.
   - The CA hash is computed only for an allowed token. A CA PEM that
     does not give one (no certificate, two, or a malformed one) is 500
     with `Join.ca_hash`'s message.
   - Success is 200 `text/x-shellscript` with `Join.script`'s text. The
     type names what the body is; `curl | sh` ignores it.
   - `Join.reason` gives Go's http.StatusText for 200, 400, 401, 403,
     404, 405 and 500 (401 is `Unauthorized`), and `Error` for any other.
     `Join.render` writes the whole HTTP/1.1 response: the status line,
     Content-Type, Content-Length (the body's UTF-8 bytes), Allow for a
     405, `Connection: close`, and the body. The server closes the
     connection after it.

Open points:

- Serving /node/join. A guest join server (a separate change) listens on
  8443 in the control-plane VM, reads the request, gets the Secret that
  `Join.lookup` names, and writes `Join.render(Join.respond(...))`. The
  script runs `kubeadm join`, whose kubelet-start phase calls systemctl,
  so it is for machines with systemd. vk8s's own workers join without
  systemd through `Plan.worker` (item 4) and need no join server.
