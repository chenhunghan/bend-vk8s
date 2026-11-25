#!/usr/bin/env python3
"""The container runtime's share of a pod start, from a node's containerd.log
(scripts/bench/guest-spawns.sh keeps one per run): for each pod whose name
starts with PREFIX, the ms from containerd's "RunPodSandbox for" line to
its "StartContainer ... returns successfully" line. The kubelet reports a
started container only at its next relist, so kubectl's time to Ready
moves in steps of about 320 ms; these two lines do not.

  scripts/bench/cri-start.py containerd.log [PREFIX=warm]
Prints the times, their median and their mean.
"""
import re
import sys
from datetime import datetime

log = sys.argv[1]
prefix = sys.argv[2] if len(sys.argv) > 2 else "warm"


def stamp(line):
    m = re.match(r'time="(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)\.(\d+)Z"', line)
    if not m:
        return None
    return datetime.strptime(m.group(1), "%Y-%m-%dT%H:%M:%S").timestamp() + float("0." + m.group(2))


start, sandbox_of, ctr_of, out = {}, {}, {}, []
for line in open(log, errors="replace"):
    t = stamp(line)
    if t is None:
        continue
    line = line.replace('\\"', '"')
    m = re.search(r'msg="RunPodSandbox for name:"(%s\d+)"' % re.escape(prefix), line)
    if m and "returns sandbox id" not in line:
        start[m.group(1)] = t
    m = re.search(r'RunPodSandbox for name:"(%s\d+)".* returns sandbox id "([0-9a-f]+)"' % re.escape(prefix), line)
    if m:
        sandbox_of[m.group(2)] = m.group(1)
    m = re.search(r'CreateContainer within sandbox "([0-9a-f]+)" .*returns container id "([0-9a-f]+)"', line)
    if m and m.group(1) in sandbox_of:
        ctr_of[m.group(2)] = sandbox_of[m.group(1)]
    m = re.search(r'StartContainer for "([0-9a-f]+)" returns successfully', line)
    if m and m.group(1) in ctr_of:
        pod = ctr_of[m.group(1)]
        out.append((pod, int(round((t - start[pod]) * 1000))))

ms = [v for _, v in out]
if not ms:
    sys.exit("no pod named %s* in %s" % (prefix, log))
print("cri_start_ms=" + ",".join(str(v) for v in ms))
print("cri_start_n=%d" % len(ms))
print("cri_start_median_ms=%d" % sorted(ms)[(len(ms) - 1) // 2])
print("cri_start_mean_ms=%d" % (sum(ms) / len(ms)))
