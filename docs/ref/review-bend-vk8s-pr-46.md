## Findings

Reviewed PR #46 and PR #45 as merged, against current main `881a387116a16a21fa8395cd1bfbedec7f16aefb`. Line numbers below refer to that main revision.

1. **P1: Native shutdown can signal an unrelated host process.** `host/init.bend:997`

   ```bend
   +s2 : +List<S.Svc> <- Init.stop_each(N.Native.stop_pids(svcs), svcs)
   ```

   Shutdown snapshots the PID list, but `Init.stop_each` signals its remaining entries after `Init.stop_wait` has reaped other daemons and cleared their service records. For example, while stopping the join server, etcd exits and gets reaped; if the host reuses etcd’s PID before its turn, shutdown sends SIGTERM to the unrelated process. The numeric bounds proved by `native.shutdown_no_global_kill` do not establish ownership. **Fix:** check the updated service table before each signal, or retain process handles that cannot refer to recycled PIDs.

2. **P1: Native mode exposes the published administrator credentials to other local users.** `host/init.bend:924`

   ```bend
   def NInit.mkdir(+env: N.Env, +dir: String, s: St) -> IO(St):
     Init.run(N.Native.busybox(env), ["mkdir", "-p", dir], s)
   ```

   Native setup creates no private directory boundary, while `Plan.publish` creates its kubeconfig through ordinary shell redirection. With `VK8S_DATA=/tmp/vk8s-demo` and umask `022`, the new directories are `0755` and `share/kubeconfig.yaml` is `0644`; another local user can read the embedded `kubernetes-super-admin` private key and authenticate to the cluster. The smoke test’s enclosing `mktemp -d` hides this exposure. **Fix:** enforce private permissions on native data and share directories and create published credentials with mode `0600`.

3. **P1: Accepted native paths can expand into destructive operations outside the selected directory.** `src/standalone/native.bend:74`

   ```bend
   Bool.and(Bool.and(String.starts_with(p, "/"), Bool.not(String.eq(p, "/"))),
     Bool.not(Bool.or(Bool.or(String.contains(p, " "), String.contains(p, "'")), String.contains(p, "\""))))
   ```

   Validation accepts shell metacharacters even though relocation inserts paths into unquoted shell commands. With valid binaries and literal `VK8S_DATA='/tmp/demo$1'`, the PKI helper at `src/guest/plan.bend:256` expands `rm -rf /tmp/demo$1/pki/kubelet-serving` to `/tmp/demo/pki/kubelet-serving`, deleting another directory’s contents. **Fix:** reject shell metacharacters before executing these plans, or generate shell arguments with context-correct quoting instead of textual substitution.

4. **P2: A timed-out boot command survives native shutdown.** `host/init.bend:951`

   ```bend
   case P.Run{+prog, +args}:
     do IO<St>:
       Init.say("run " ++ prog ++ P.Plan.sh_words(args))
   ```

   This branch delegates to `Init.run`, which forgets a command’s PID after its ten-minute wait expires without terminating it or adding it to the service table. If a boot-time `kubeadm` process is stopped with SIGSTOP, the wait expires, and subsequent SIGTERM shuts down only the recorded daemons; the stopped child remains on the host after the runner exits. **Fix:** retain ownership of synchronous children until they are terminated and reaped, including on timeout.

5. **P2: SIGTERM and SIGINT do not interrupt native boot.** `host/init.bend:1052`

   ```bend
   +st : St <- NInit.steps(env, plan, s0)
   Init.say(Init.finished(St.ok(st)))
   NInit.supervise(U32.to_nat(4294967295), St.svcs(st))
   ```

   The C handler records termination signals, but boot steps and their wait loops never consume them. Sending SIGTERM while kube-apiserver fails to open port `6443` leaves the runner waiting for the remainder of the 120-second readiness timeout; synchronous commands can delay termination for ten minutes, and successful steps can continue starting services after cancellation. **Fix:** check pending termination during boot and its waits, then enter shutdown immediately.

6. **P2: Native relocation leaves kubectl’s writes in the host’s home directory.** `src/standalone/native.bend:334`

   ```bend
   Native.strip(Native.relocate(e, Native.plan(c)))
   ```

   Relocation covers explicit strings but does not override kubectl’s implicit cache directory. With `HOME=/home/alice`, no `KUBECACHEDIR`, and `VK8S_DATA=/srv/vk8s/demo`, the boot plan’s `kubectl get` and `apply` commands create discovery and HTTP cache files under `/home/alice/.kube/cache`. Kubernetes’ cache implementation explicitly creates and writes those files. **Fix:** set a per-cluster `KUBECACHEDIR` for native children or pass `--cache-dir` to every native kubectl invocation.

## Questions for the author

- **Is Linux container mode restricted to trusted workloads? Policy not verified.** PR #45 deliberately grants all capabilities, unrestricted device access, no user namespace, and no seccomp filter. A process that gains node-container root can create host block-device nodes and access host disks; `CAP_SYS_MODULE` also permits host kernel module loading where the host permits it. Read-only assets and module mounts do not contain that compromise. This matches the intended privileged Docker model, so I have not classified that design choice itself as an implementation defect.
- **Should vk8s match kind’s final read-only `/sys` mount? Intent not verified.** Kind’s entrypoint remounts `/sys` read-only before making mounts shared. Vk8s leaves it writable, and `container.mounts` pins that behavior. The private cgroup namespace isolates the cgroup view, not host-global sysfs controls.

## What was checked and how

- Read `CLAUDE.md`, `AGENTS.md`, `docs/DESIGN.md`, `docs/GOAL.md`, both complete changes, their laws, proofs, tests, CI additions, and relevant current-main integration.
- Traced native plans through `host/init.bend`, `host/effs/proc.c`, `host/effs/sys.c`, supervision, PKI, publication, and join-server configuration.
- Compared container privileges, mounts, and cgroup delegation with vcluster `3a0085b` and kind `0750810`. Current main retains PR #45’s mounts and privileges; its container shutdown exits the PID namespace without invoking VM unmount or poweroff.
- No existing laws or frozen tests were modified by either PR. The native safety proofs establish classifier and PID-range properties, not complete filesystem or process ownership.
- Found no separate defect in the sequential `Sys.term` C implementation. Native shutdown has no direct global-kill, unmount, or poweroff call.
- Ran read-only commands including `gh pr view`, `gh pr diff`, review-comment and review-thread queries, `git fetch origin main`, `git show`, `git diff`, and upstream source reads. Both PRs had no existing review threads.
- No dependencies installed, builds or tests run, working-copy edits made, or GitHub writes performed. Runtime reproduction and full Kubernetes conformance were outside this review.

## Links

- https://github.com/chenhunghan/bend-vk8s/pull/46
- https://github.com/chenhunghan/bend-vk8s/pull/45
- https://github.com/chenhunghan/bend-vk8s/tree/881a387116a16a21fa8395cd1bfbedec7f16aefb
- https://github.com/chenhunghan/bend-vk8s/blob/881a387/docs/DESIGN.md
- https://github.com/chenhunghan/bend-vk8s/blob/881a387/docs/GOAL.md
- https://github.com/chenhunghan/bend-vk8s/blob/881a387/docs/ref/explore-linux-hosts.md
- https://github.com/loft-sh/vcluster/blob/3a0085b/pkg/cli/create_docker.go
- https://github.com/kubernetes-sigs/kind/blob/0750810/pkg/cluster/internal/providers/docker/provision.go
- https://github.com/kubernetes-sigs/kind/blob/0750810/images/base/files/usr/local/bin/entrypoint
- https://github.com/kubernetes-sigs/kind/blob/0750810/images/base/files/kind/bin/create-kubelet-cgroup-v2.sh
- https://github.com/kubernetes/kubernetes/blob/v1.36.6/cmd/kubeadm/app/phases/kubeconfig/kubeconfig.go
- https://github.com/kubernetes/kubernetes/blob/v1.36.6/staging/src/k8s.io/cli-runtime/pkg/genericclioptions/config_flags.go
- https://github.com/kubernetes/kubernetes/blob/v1.36.6/staging/src/k8s.io/client-go/discovery/cached/disk/cached_discovery.go