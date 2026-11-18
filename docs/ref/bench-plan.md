# Benchmark plan: vk8s against other Kubernetes on this Mac

Status: plan, revised 2026-11-18 after two independent reviews
(review-bench-plan-codex2, codex; review-bench-plan-pi2, pi). Serves GOAL
section 10, "Measure against lima" and "Shared image layers on by default".
No result here yet.

## Claim scope

The claim is "lowest measured among these configurations, on this Mac, in
this operating state", per metric and topology, never a bare "lightest".
Results name the Mac, macOS, and every tool's exact version. A paused
vk8s is reported as a suspended cluster, not ranked against serving ones.

## Lanes

1. **Incumbent lane (migration question).** A copy of the lns-factory's
   lima VM: k0s (`base: template:k0s`, 2 vCPU, 3 GiB, lns-factory
   lima/factory.yaml), with its own writable state, ports and sockets; the
   live factory VM is stopped and never measured. vk8s runs the same
   factory replay at the same capacity, with equivalent dependencies, and
   their host cost counts on both sides. Copy startup is reported as a
   restart, not a create.
2. **Product lane (clean installs).** Fresh installs of:
   - vk8s (VM mode; also container mode, the shared node-host VM)
   - k0s in lima (fresh, lima's k0s template)
   - kiac `--distro k3s` (one Apple container VM per node)
   Round 2 if any metric is close: Apple `container cluster`
   (kindest/node), kiac kubeadm, k3s in lima.

Each product lane runs two profiles: **shipped defaults** (what a user
gets) and **matched capacity** (equal effective node RAM and vCPUs,
recorded as guest memory, allocatable, taints and placement; helper VMs
such as vk8s's image cache are not resized but are counted).

## Stack inventory (recorded per tool, per run)

Exact versions; Kubernetes distro and components; datastore; container
runtime; CNI; NetworkPolicy (kiac k3s passes --disable-network-policy);
DNS; storage provisioner; metrics; ingress/LB; add-ons. A missing
capability is marked, not hidden.

## Host accounting

- **Memory.** Process set found by before/after inventories (VMM and XPC
  services, network helpers, proxies, daemons, the vk8s cache VM, lima's
  hostagent, apple/container's daemons). Report summed phys_footprint,
  RSS and compressed memory per process, and whole-host wired, compressor,
  swap and memory pressure against a matched quiet-host baseline. A
  calibration run per stack: a guest allocation that touches every page,
  holds it, frees it, then shuts down. If process and host totals rank
  the stacks differently, report both and leave memory unresolved.
  Known caveat: guest pages can be charged twice to phys_footprint while
  mapped (STATUS.md, section 7 memory notes).
- **CPU.** Summed CPU time of the whole process set, short-lived helpers
  included, over fixed windows; plus host package power where available.
- **Disk.** APFS container allocation before, at peak and after, on a
  quiet volume, plus per-directory allocation; clones, snapshots and
  shared assets listed. Caches, blobs and layer stores are counted, also
  after the cluster is deleted.
- **Observer cost.** The benchmark's own CPU and logging are measured, and
  no observer holds an API connection during sleep windows.

## Cache states

Pinned arm64 image digests and pull policy. A controlled local registry
for the primary timings; public-registry trials reported separately. Per
run, one of: (1) fresh tool install and asset download; (2) create with
installed assets; (3) image absent from every tool-owned cache; (4)
registry cache or layer store warm, node cold; (5) node warm. Cache hits,
bytes transferred and the snapshotter or lowerdir used are verified.
Manual fills and pre-pulls are charged to setup. The vk8s cache VM is
charged in full to the first cluster; a second cluster reports its
incremental cost.

## Scenarios

Every timing stops at useful service, with each milestone kept: nodes
Ready, DNS answering, Deployment Available, Service answering by HTTP,
exec working.

1. Create: to all milestones above (monotonic clock).
2. Always-on idle, sleep off: 10 min settle, then 10 min measure.
3. First pod (nginx), each cache state: to Ready and first HTTP 200.
4. Memory recovery: a Job that writes every page of 1 GiB, holds 60 s and
   exits 0, pinned to one worker with fixed requests and limits; then 30
   nginx pods; then both together. Peak, recovery at 1, 5, 10 and 30 min,
   time back near baseline; OOM kills, evictions, pending pods, guest
   available memory, balloon activity where exposed.
5. Churn at a fixed offered rate (Deployments created, scaled, deleted;
   ConfigMap writes): completed operations, backlog, API and pod-ready
   latency, errors, restarts, CPU-seconds per completed operation; 1 h in
   round 1, several hours plus one overnight in round 2.
6. Disk give-back, two tests with a common deadline of 90 min after last
   use: (a) write then delete the same known bytes inside the guest
   (block return); (b) the same image set pulled, run, deleted (retention
   policy: kubelet GC, runtime cleanup, trim, host return). Report bytes
   still held at the deadline; documented manual cleanup (e.g. `container
   clean`) measured separately, never merged with automatic. Re-pull cost
   after GC reported.
7. Default-policy idle (vk8s sleep on): the trace starts when the last API
   connection closes; pause confirmed out of band. Pre-pause, paused and
   wake costs (proxy and cache VM included), first API request latency,
   time to a healthy endpoint, timeouts, evictions; a direct Service probe
   during the quiet period and a held watch, each in its own run;
   repeated sleep/wake cycles.
8. Delete: time, leftover processes, files and allocated disk.
9. Storage: a PVC written and read back, and after cleanup.
10. Layer store (vk8s on vs off, one setting changed at a time): 1, 3 and
    10 nodes and 2 clusters; disk, memory, cold and warm time to a usable
    pod, idle CPU; checked against GOAL's default-on gates (10% cold-pull
    limit, conformance, soak).

## Statistics and conditions

AC power, recorded power mode, thermal state and memory pressure; a fixed
reset between runs. Round 1 starts as a 3-run pilot to estimate variance,
then balanced or randomized order within blocks and enough independent
repetitions that paired differences are within a margin declared before
the runs. Every run, failure and timeout is published with paired
differences; intra-run samples are not counted as repetitions.

## Deliverables

scripts/bench/ (a driver with one adapter per tool: create, delete,
kubectl, process set, state dirs; shared manifests in workload/), raw CSV
per run, docs/ref/bench-round1.md with versions, commands, raw data and
winners per metric, topology and state. STATUS links it; GOAL's "Measure
against lima" closes from the incumbent lane's factory replay.
