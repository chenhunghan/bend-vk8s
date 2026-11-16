## Findings

**1. Slot allocation is racy, and `delete` removes whichever bridge the slot names, so it can destroy another cluster's network.**

`host/vk8s.bend:2171-2179`:
```
used : String <- Vk8s.run_raw("grep", ["-rh", "--include=cluster.env", "^SLOT=", home ++ "/.vk8s/clusters"])
+k : U32 = R.Ctr.slot(R.Ctr.slots(used))
...
env : Bool <- Vk8s.and_then(priv, Vk8s.ctr.write(dir ++ "/cluster.env", Vk8s.ctr.env_file(name, k, etcd, nodes, now)))
```
`host/vk8s.bend:2276`: `_ : Bool <- Vk8s.run_ok("ip", R.Ctr.ip_bridge_del(k))`

- **The defect.** A slot is "taken" only once its `cluster.env` is on disk. The read, the choice and the write are not atomic and there is no lock. The registry is also per `$HOME` (`Vk8s.home()` is `getenv("HOME")`), but bridges, veths and iptables are per host.
- **Scenario 1.** Run `vk8s create a --backend container & vk8s create b --backend container`. Both greps run before either `cluster.env` exists, so both pick `k=1`. Cluster `a` makes `vk8sbr1`. Cluster `b` fails at `ip link add vk8sbr1 type bridge` with "File exists". It dies with "vk8s delete b cleans up", and `b`'s `cluster.env` says `SLOT=1`.
- **Scenario 2.** Running `sudo vk8s create` from two different homes (for example `sudo -H` against plain `sudo`, or root against a user) hits the same collision. Each home sees only its own `SLOT=` lines.
- **Wrong result.** The user follows the message and runs `vk8s delete b`. `Vk8s.ctr.delete` reads `SLOT=1` and runs `ip link del vk8sbr1`. That removes cluster `a`'s live bridge and cuts all of `a`'s nodes off the network. It never checks that the bridge belongs to `b`.
- **Fix.** Reserve the slot atomically, for example `mkdir /run/vk8s/slots/<k>` (fails if it exists), keyed per host. Have `delete` remove a bridge only if this cluster created it. A cheap check is to confirm that the bridge's address is `10.10.k.1/24` and that no other cluster's `cluster.env` holds slot `k`.

**2. The FORWARD rules open the host's forwarding plane for every cluster, and a law pins them.**

`src/cli/ctr.bend:186-188`, pinned by `laws/ctr.bend:71`:
```
["-t", "filter", "-I", "FORWARD", "-i", br, "-m", "comment", "--comment", tag, "-j", "ACCEPT"],
["-t", "filter", "-I", "FORWARD", "-o", br, "-m", "comment", "--comment", tag, "-j", "ACCEPT"]
```
`host/vk8s.bend:2183` also sets `ip_forward=1` for the whole host and never restores it.

- **The defect.** The rules accept everything in and out of the bridge, and they are inserted at the top of FORWARD, ahead of `DOCKER-USER`, `DOCKER-ISOLATION` and any DROP policy. Nothing separates the clusters. In VM mode each cluster's LAN is private. In vcluster's Docker driver each cluster has its own Docker network, which Docker isolates.
- **Scenario.** A pod on cluster `a` (10.10.1.0/24) opens `10.10.2.2:6443` or a kubelet port on cluster `b`. The host forwards it across the two bridges and the rules accept it. A node can equally reach Docker containers on `docker0`, or any LAN behind the host, past an operator's firewall.
- **Fix.** Add per-bridge isolation. Insert `-I FORWARD -i vk8sbrA -o vk8sbrB -j DROP` between clusters, or give each bridge a `-i br ! -o <uplink>` match plus a drop for other `vk8sbr+` interfaces. Add a new law under `# Proposed:`. Do not edit `ctr.rules`.

**3. iptables runs without `-w`, and `delete` ignores every failure before it removes the only record of the slot.**

`src/cli/ctr.bend:183` and `Ctr.undo` build argv with no `-w`. The cleanup path is `host/vk8s.bend:2235-2236, 2276-2281`:
```
out : String <- Vk8s.run_raw("iptables", ["-t", t, "-S"])
Vk8s.ctr.each("iptables", R.Ctr.undo(t, tag, out))
...
_ : Bool <- Vk8s.run_ok("rm", ["-rf", "--one-file-system", dir])
```

- **The defect.** iptables(8) says that without `-w` the program exits if the xtables lock is held. Docker or firewalld commonly hold it. `run_raw` merges stderr into stdout, so the "Another app is currently holding the xtables lock" message becomes `-S` output that `Ctr.undo.lines` skips because it does not start with `-A `. `Vk8s.ctr.each` and the `ip link del` call discard every exit status. `rm -rf` then deletes `cluster.env`, which is the only place `SLOT=` lives. Delete prints "Successfully deleted" either way.
- **Scenario.** `vk8s delete demo` runs while Docker is changing rules. The tagged MASQUERADE and FORWARD ACCEPT rules stay, and so may the bridge. Slot 1 is now free in the registry. The next `vk8s create` picks `k=1`, and `ip link add vk8sbr1` fails with "File exists". The stale `-I FORWARD -i vk8sbr1 ACCEPT` rules from the dead cluster are also still active.
- **Fix.** Pass `-w` (or `-w 10`) on all iptables calls, and have `delete` check the leftovers. If any step failed, keep `cluster.env` and exit non-zero.

## Questions for the author

- **Root of `HOME` (not verified).** `Vk8s.home()` falls back to `/tmp` when `HOME` is unset. Under root, `mkdir -p`, `chmod 700` and the `cluster.env` write would then follow symlinks in a world-writable `/tmp/.vk8s`. Is a refusal when `HOME` is unset acceptable for the container backend?
- **Missing bind sources (not verified).** `Container.mounts` binds `/dev/kmsg` and `/lib/modules` from the host. Preflight checks neither. On a host without one of them, runc likely fails to start the node, and the user only sees "see console.log". Which command settles it: create a cluster on a host without `/lib/modules`, then read `console.log`.
- **`--cpus`, `--memory` and `--port` are dropped silently.** `Vk8s.ctr.run` passes only `name, etcd, nodes` to `Vk8s.ctr.create`. The container config sets no resource limits. Is that intended, and should the CLI warn?
- **Overlay option string.** `Ctr.mount_overlay` builds `ro,lowerdir=` plus a `:`-joined list of `$HOME` paths. A home path containing `,` or `:` would split or break the option string.
- **Laws without `laws/done/` markers.** `ctr` (33 laws, 33 proofs), `container_host` (17 and 17) and `backend` (6 and 6) have no marker, yet CLAUDE.md rule 4 asks for one once all laws prove. I did not run `bend`. Is the marker withheld on purpose?
- **Expected values.** The `ctr` expected values are vk8s's own choices, not vcluster's, which rule 8 asks for. The file header says so. The citation `docker_runtime.go:162-182` for the `overlay`, `bridge` and `br_netfilter` modules is not verified. The vcluster clone is absent here.
- **Rule 7 (parallelize).** `Vk8s.ctr.stop_all` stops nodes one after another, up to about 80 s each (120 polls of 500 ms, then 20 more). Delete time grows linearly with `--nodes`.
- **Host cgroup root.** `Vk8s.ctr.cgroups` writes `+<controller>` to `/sys/fs/cgroup/cgroup.subtree_control`. Delete never reverts it. Is leaving the host root changed acceptable?
- **Node count.** `Ctr.node_ip` is `10.10.k.(i+2)`. `--nodes` is not capped, so `i ≥ 253` produces an invalid address and `ip` fails mid-create.

## What was checked and how

- **Read in full:** `src/cli/ctr.bend`, `host/vk8s.bend:1858-2467` (`Vk8s.ctr.*`, `by_backend`, `ctr.run`), `src/guest/container_host.bend`, `laws/ctr.bend`, `laws/container_host.bend`, and the mounts, capabilities and linux sections of `src/guest/container.bend`.
- **Checked as intended:**
  - Cluster names reach argv only through `Cli.valid_name` (`[a-z0-9-]`, 1 to 52 chars, alnum at both ends). Every command is a no-shell argv list through `Process.run` or `Proc.start`. I found no shell injection through names or paths.
  - `Ctr.undo` matches the exact token after `--comment`, so another cluster's tag (`vk8s:demo2`) and Docker's rules are untouched. This is covered by law `ctr.net_cleanup`.
  - The flannel rewrite is inserted before the step whose joined args contain `apply -f /etc/vk8s/flannel.yaml`. `plan.bend:898` and `scripts/guest/flannel.yaml:139` match it.
  - `rm -rf` uses `--one-file-system`.
- **Not covered:**
  - I did not run `bend`, `scripts/check.sh` or any host command, as instructed. The `bend` proofs are unchecked.
  - The runc behaviours, the gVisor and KVM paths, and `host/effs/proc.c` were not read.
  - The native backend and the VM path were out of scope.
  - No review threads were read. `$PR` is 49, but I did not run `gh` for comments. The brief names the PR as already merged.

## Links

- https://github.com/chenhunghan/bend-vk8s/pull/49
- https://github.com/chenhunghan/bend-vk8s (branch `feat/container-host`)