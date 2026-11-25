# Benchmark round 1: vk8s against k3s on this Mac

Run 2026-11-25, 14:16 to 20:15, by `scripts/bench/lightest.sh` (the steps)
under `scripts/bench/guard.sh` (stops a run when the Mac is not quiet).
This closes "Measure against lima" of GOAL section 10. The incumbent
cluster is not on this Mac, so the comparison is against fresh installs
of k3s, the lightest distribution we could install in lima and in
Apple's container runtime (plan: docs/ref/bench-plan.md, product lane).

The claim is "lowest measured among these configurations, on this Mac",
per metric. It is not a claim about other machines or other workloads.

## What ran

Mac: Apple M5 Pro, 15 cores, 48 GiB, macOS 27.2.1. One single-node
cluster at a time, nothing else running. Three passes, the order rotated
each pass. Every number below is the median of the three; the spread is
in the last section.

| Name | What | Versions | Node size |
|---|---|---|---|
| vk8s | VM mode, the default on a Mac | release v1.36.6-92057045, Kubernetes v1.36.6 | default: 2 vCPUs, 2048 MiB |
| vk8s-container | `--backend container`: containers in one node host VM | same | default: 2 vCPUs, 6144 MiB for the node host |
| lima-k3s-tuned | k3s in lima, tuned to be light: Alpine 3.24 guest, vz, no traefik, no servicelb, no metrics-server (`scripts/bench/lima-k3s-tuned.yaml`) | lima 2.3.0, k3s v1.37.2+k3s1 | 2 vCPUs, 2048 MiB |
| lima-k3s | lima's own `template:k3s`, what a user gets | lima 2.3.0, k3s v1.37.2+k3s1, Ubuntu 26.04 guest | lima's default: 4 vCPUs, 4 GiB |
| kiac-k3s | k3s in Apple's container runtime, one VM per node, no LoadBalancer, no metrics-server | kiac v0.13.0, container 1.7.1, k3s v1.37.0+k3s1 | 2 vCPUs, 2048 MiB |

vk8s ran with sleep when idle turned off (`VK8S_IDLE_SLEEP=0`): a
sleeping cluster is not compared with serving ones.

Steps, the same for each: reset (no cluster, no image cached by the
tool; the installed assets and lima's downloaded guest image stay),
create (timed until the node is Ready and until CoreDNS is Available),
10 minutes to settle, 10 minutes measured idle, a first nginx pod (image
pulled from Docker Hub), the same pod again five times (median), delete
(timed), then what is left.

Memory is the sum of `phys_footprint` over the tool's processes, the
number Activity Monitor shows. CPU is the processes' CPU time over the
idle window, as per cent of one core. Disk is the allocated size of the
tool's state directories.

## Results (medians of 3)

| | vk8s | vk8s-container | lima-k3s-tuned | lima-k3s | kiac-k3s |
|---|---|---|---|---|---|
| Create to node Ready (s) | 26.7 | 30.7 | 52.9 | **21.9** | 31.2 |
| Create to CoreDNS Available (s) | **33.2** | 39.5 | 61.9 | 38.4 | 34.8 |
| Idle memory (MiB) | **1189** | 1412 | 2100 | 3119 | 1476 |
| Idle CPU (% of one core) | 10.1 | 9.6 | **6.7** | 12.8 | 10.8 |
| First nginx pod (s) | 8.6 | 9.9 | **7.5** | 7.9 | 8.9 |
| Same pod again (s) | 0.9 | 0.9 | **0.4** | **0.4** | 0.8 |
| Memory with the pod (MiB) | **1268** | 1892 | 2209 | 3434 | 1839 |
| Delete (s) | 1.5 | 4.8 | 0.4 | **0.3** | 0.6 |
| Processes left after delete | 2 | 0 | 0 | 0 | 5 |

Disk, in MiB:

| | vk8s | vk8s-container | lima-k3s-tuned | lima-k3s | kiac-k3s |
|---|---|---|---|---|---|
| Installed, no cluster | **276** | **276** | 3845 | 3845 | 1387 |
| Added by an idle cluster | 367 | **333** | 1154 | 3706 | 848 |
| Added by cluster and nginx pod | 624 | **407** | 1363 | 3772 | 1066 |
| Total with the pod | 900 | **683** | 5208 | 7617 | 2453 |
| Left after delete | 872 | **276** | 3845 | 3845 | 1387 |

"Installed, no cluster" is what each tool keeps to create a cluster
without a download: vk8s's guest assets; lima's cached guest images
(both lima rows share one cache, 3.4 GiB of Ubuntu and 0.4 GiB of
Alpine, so the tuned one alone needs about 0.4 GiB); the k3s image in
Apple's container store.

## What it shows

vk8s uses the least memory (1189 MiB idle against 1476 for the next,
k3s in Apple's container runtime, and 2100 for the tuned k3s in lima)
and the least disk at every step. It is first to a cluster with working
DNS.

It trails k3s in six places. Each is explained here or fixed.

1. **Idle CPU: 10.1% of a core against 6.7% for the tuned k3s in lima.**
   (The default lima k3s is at 12.8%, k3s in Apple's container runtime
   at 10.8%.) All of it is in the two vCPU threads; vk8s's host
   processes (image cache, layer filler) used under 0.3% together. Inside
   the guest, per cent of one core over 180 s: kube-apiserver 1.72,
   kine 1.38, kubelet 0.95, kube-controller-manager 0.81, containerd
   0.44, vk8s's own PID 1 and guest daemon 0.36, CoreDNS 0.18, flannel
   0.12, scheduler 0.11. The idle cluster makes about one API request
   a second (two Lease renewals every 10 s, discovery), so nothing of
   ours is busy: leader election and the TTL controller are already
   off. The cost is the upstream Kubernetes binaries, one process each
   with kine beside the API server. k3s links them and kine into one
   process. vk8s keeps the upstream binaries because that is what its
   certified conformance covers. Not fixed.
2. **Create to node Ready: 26.7 s against 21.9 s for lima's default
   k3s.** (The tuned k3s takes 52.9 s; to working DNS vk8s is first.)
   The kubelet registers the node about 9 s after `vk8s create` starts.
   Ready then waits for the flannel DaemonSet's pod: the controller
   manager starts its DaemonSet controller about 5 s after it is
   launched, and the pod runs three containers in turn, two of them
   pulled, about 6 s. k3s runs flannel inside its own process, so its
   node waits for no pod. Not fixed: running flannel as a node daemon
   would save about 6 s and is a design change (see STATUS).
3. **First nginx pod: 8.6 s against 7.5 s.** The time is the download
   from Docker Hub, which varies more than the gap: vk8s took 6.8, 8.6
   and 9.3 s; the tuned k3s took 7.4, 8.0 and 7.5 s here and 13.0 s in
   a later run, with a 12.3 s pull. In one traced vk8s start of 7.2 s
   the pull was 5.9 s; the rest was 0.55 s before the sandbox, 0.2 s
   for the sandbox, 0.1 s to create and start the container, and 0.5 s
   until the Deployment reported Available. Container mode is slower
   (9.9 s; its pull took 7.8 s against 5.4 s in VM mode): its
   containerd downloads through the node host VM's user-mode network,
   where VM mode's host process downloads on the Mac. Not fixed.
4. **The same pod again: 0.9 s against 0.4 s.** vk8s's runs were 0.6,
   0.9 and 1.2 s. containerd takes the same in a fast and a slow start
   (150 ms for the sandbox, 25 ms for the container); what varies is
   the stock kubelet before it asks for the sandbox (0.22 s and 0.76
   s). Not fixed.
5. **Delete: 1.5 s (VM mode) and 4.8 s (container mode) against 0.3 to
   0.6 s.** lima and kiac kill the VM. vk8s gives the cluster the one
   second that vcluster's docker driver gives a container it deletes
   (`docker stop -t=1`), by design. Container mode gave it twice: once
   for the containers, with the request to the node host and its
   answer each waiting on a poll, and again for the node host VM.
   **Fixed after this round**: the last container cluster's delete
   stops the VM directly. Measured with the fix: 2.2 s. The other rows
   are from the release.
6. **Left after delete: two processes and 596 MiB.** They are the image
   cache and the layer filler with their stores, which serve every
   cluster on the Mac and make the next create and the next pull need
   no download. Idle, the two processes hold 60 MiB and used 6 s of CPU
   in 47 minutes. `vk8s cache prune` empties the cache. Container mode
   leaves nothing. vk8s's 872 MiB left is still less than what lima
   (3845 MiB) and Apple's container store (1387 MiB) keep installed.
   Not fixed; by design.

## Every pass

`pass,tool,cpus,mem_mib,server,ready_s,dns_s,idle_fp_mib,idle_rss_mib,idle_cpu_pct,disk_before_mib,disk_idle_mib,nginx_s,nginx_again_s,disk_pod_mib,pod_fp_mib,pod_rss_mib,delete_s,left_procs,disk_after_mib`

```
1,vk8s,default,default,v1.36.6,26.7,33.2,1189,1218,10.50,276,643,6.8,.6,900,1283,1313,1.5,2,873
1,lima-k3s-tuned,2,2048,v1.37.2+k3s1,54.3,61.9,2061,3056,6.78,3845,4999,7.4,.4,5208,2219,3360,.4,0,3845
1,kiac-k3s,2,2048,v1.37.0+k3s1,29.2,33.9,1480,2221,10.46,1387,2234,8.9,.8,2453,1839,2893,.6,5,1387
1,vk8s-container,default,default,v1.36.6,30.3,39.1,1412,1419,10.49,276,610,10.3,.9,683,1902,1909,5.2,0,276
1,lima-k3s,default,default,v1.37.2+k3s1,21.1,38.4,3175,4991,12.75,3845,7552,7.4,.4,7617,3443,5523,.3,0,3845
2,kiac-k3s,2,2048,v1.37.0+k3s1,31.2,34.8,1476,2199,11.03,1387,2235,8.9,1.1,2453,1844,2891,.6,5,1387
2,vk8s-container,default,default,v1.36.6,30.7,39.5,1413,1420,9.57,276,609,9.7,.9,683,1892,1899,4.8,0,276
2,lima-k3s,default,default,v1.37.2+k3s1,21.9,41.4,3119,4948,12.76,3845,7550,7.9,.4,7616,3420,5523,.3,0,3845
2,vk8s,default,default,v1.36.6,27.6,34.1,1188,1217,9.33,276,643,8.6,.9,900,1268,1300,1.5,2,872
2,lima-k3s-tuned,2,2048,v1.37.2+k3s1,46.5,64.8,2134,3114,6.27,3845,5052,8.0,.4,5266,2209,3350,.4,0,3845
3,kiac-k3s,2,2048,v1.37.0+k3s1,32.1,35.6,1473,2206,10.79,1387,2235,8.9,.5,2458,1833,2890,.6,5,1387
3,vk8s-container,default,default,v1.36.6,32.2,40.0,1379,1386,9.12,276,609,9.9,.9,686,1860,1867,4.8,0,276
3,lima-k3s,default,default,v1.37.2+k3s1,22.4,34.4,3104,4915,11.81,3845,7551,8.0,.4,7617,3434,5531,.3,0,3845
3,vk8s,default,default,v1.36.6,26.7,31.1,1189,1218,10.14,276,643,9.3,1.2,900,1264,1305,1.5,2,871
3,lima-k3s-tuned,2,2048,v1.37.2+k3s1,52.9,60.5,2100,3106,6.69,3845,4999,7.5,.4,5206,2209,3348,.4,0,3845
```

One run failed and was run again in its pass: the tuned k3s in pass 2,
where `limactl start` gave up waiting for the guest ("did not receive
an event with the `running` status"). The five processes left after a
kiac delete are Apple container's own daemons, which also ran before.

Not covered by this round: more than one node, hours of churn, and the
incumbent's own workload.
