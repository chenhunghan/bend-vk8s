# Review of the merged work on main: port picker, PID 1 tick, idle reclaim and compaction, snapshot tar, stripped guests, regression.sh

I found nothing that corrupts data. The most serious defects are in the reclaim guard, which can switch itself off silently or stay in back-off far longer than intended. Four more are solid: PID 1 blocks while reclaim runs, the port is reserved too late, laws pin shell text instead of behavior, and `regression.sh` deletes clusters named `st`, `vc` and `hc`. Everything is read-only. I ran the reclaim logic under `dash` on temp files. Busybox is not installed here, so busybox `ash` behavior is not verified.

## Findings

Ranked by severity.

### F1. Medium: the refault back-off only moves during idle runs

`src/guest/plan.bend:1659-1670`. The idle test is `... ] || exit 0;`. It sits before the refault read and before both state writes. The refault baseline therefore only advances on idle runs. The counter `pc` only drops on idle runs.

- Refaults during a busy period are charged to the next idle run. That run sees a delta over 2560 and backs off.
- A node that is busy half the time stays in back-off for hours of wall time.
- A node that was busy for an hour backs off for another hour the first time it goes idle, even if reclaim never ran.

Quoted from the script:
```
[ $pt -gt 0 ] && [ $dt -gt 0 ] && [ $((b*100)) -lt $((dt*10)) ] || exit 0; r=$(awk '/^workingset_refault_file / ...
```

I reproduced it. The state stayed `9000 119` after a busy window in which the counter went from 9000 to 99000.

Two comments are wrong because of this. `src/guest/plan.bend:1649` says "backs off for 120 runs (1 h)". The same comment block says the delta is "since the last run, 30 s ago".

Failure scenario: a worker with a pod burst every 20 minutes never gets its page cache reclaimed. That defeats the footprint target in docs/GOAL.md section 7. STATUS already reports "Target (<= 512 MiB) not met".

Fix: read `r` and update the baseline on every tick, before the idle test. Decrement `pc` on every run. Or drop the counter and use the wall clock.

### F2. Medium: a missing or garbled vmstat field turns the guard off silently

When `workingset_refault_file` is missing, `r` is empty. The first run writes ` 0` to `/run/vk8s-reclaim`. The next run reads `pr=0` and an empty `pc`. Then `[ $pc -gt 0 ]` errors and reclaim proceeds.

Under dash this prints `run.sh: 2: [: -gt: unexpected operator` and writes `334464K swappiness=0` on every idle run. That is the thrash the guard was added to stop. The commit measured about 215k refaults a minute.

The error text goes to the VM console. Nothing else reports it. No law or test covers it.

Corrupt state has the same effect. `/run` is a tmpfs, so a power cut cannot cause it. A pod with a hostPath mount of `/run` could.

Fix: if `r` is not a number, skip reclaim and log once. Quote and default `pc`.

### F3. Medium: reclaim blocks PID 1 and runs in the same tick as compaction and fstrim

`host/init.bend:408-413` runs `P.Run` through `Init.run`. `Init.run` waits on 20 ms polls with fuel 30000, which is up to 10 minutes (`host/init.bend:136-141`, `:185-193`).

While it waits, PID 1 serves no host request, no power button and no restart (`start_due` is not called). `Init.supervise` is at `host/init.bend:721-744`.

Compare `Plan.fstrim` at `src/guest/plan.bend:1411`. It uses `Spawn`, and its comment says "so PID 1 keeps reaping and serving requests".

A write to `memory.reclaim` with `swappiness=0` writes back dirty file pages. It can take seconds on a slow data disk, and a write to `/proc/sys/vm/compact_memory` can too. The host sends `quit` after 60 s (docs/DESIGN.md "Per-VM data disk" and "PID 1" sections). A hung child is not killed after the fuel runs out. The next run starts a second reclaimer.

Reclaim, compaction and fstrim all fall on `tick % 600 == 0`, because 30, 600 and 600 divide. They run back to back in one tick.

Failure scenario: `vk8s delete` arrives during a long compaction. `powerdown` is handled late, and etcd or kine can be cut off by the 60 s `quit`.

Fix: spawn in the background as fstrim does, with a lock file against overlap. Or stagger the offsets.

### F4. Medium: first reclaim after boot and after each back-off expiry evicts the active file set

`src/guest/plan.bend:1626-1630` and `:1669`. Since 7ed2087 the amount is `Active(file) + Inactive(file)` minus 64 MiB. The guard reacts only on the next idle run, 30 s later.

The guest binaries sit on a zstd squashfs assets disk (docs/DESIGN.md "Read-only, shared assets disks"). A refault re-reads and decompresses a 256 KiB block.

The evidence in the repo:
- 256e336 measured a control plane at 14.4% host CPU and 215k refaults a minute without the guard, and 11.7% with reclaim suppressed (docs/STATUS.md:749-760, as shown by `git show 256e336`).
- The 7ed2087 measurement reports control plane memory (1.2 GB) and "refaults over 6 min 0". It gives no CPU figure for the control plane after the change. Not verified.

The storm repeats at every back-off expiry, about every hour of idle time (see F1). After a reboot the state is gone, because `/run` is tmpfs (`src/guest/plan.bend:79`). Then `pr=$r`, so there is no refault baseline. Reclaim fires at tick 60, which is the second idle window.

Fix: reclaim `Inactive(file)` first. Add the active set only after N windows with zero refaults. Or cap each run to a fraction of the excess.

### F5. Medium: the API port is reserved after the slow steps

- Standalone: `host/vk8s.bend:690` picks the port. The cluster directory and `data.img` clone come next, and the `port` file is written after the clone, at `:694`.
- The `test -e` on the name and the later `mkdir -p` are also separate steps.
- Classic: `host/vk8s.bend:793` picks the port, then `Vk8s.host_service` at `:794` creates the host Service with it. `create_x` is entered only after that.
- Restore: `host/vk8s.bend:1661` and `:1742` have the same window.

`port_taken` only sees a recorded `port` file or a listener, so two overlapping creates can still choose the same port. With 3000 ports the chance per overlapping pair is about 1 in 3000. The consequence is a late bend-vmm forward bind failure on the second cluster.

The commit message says "two creates in the same second no longer share a port". That holds only when the creates do not overlap.

Fix: reserve first. Create the directory atomically and write `port` in the same step, then re-scan for duplicates. Or hold `~/.vk8s/.lock` around pick and record.

### F6. Low: derived ports are never probed

Only the API port is probed. The other host ports come from `Cli.konn_port`, `Cli.kubelet_port` and `Cli.join_port` (`src/cli/cli.bend:1036`, `:1039`, `:1053`): 13000, 16000 and 19000 plus `port % 3000`. They cannot collide with another vk8s cluster, because the API port is unique. They can collide with a foreign listener. The failure shows only when the VM starts.

vcluster has no derived ports, so this is a parity extension. Fix: probe all of them in `port_taken`.

### F7. Low: small gaps in `port_taken` and `random_port`

- `host/vk8s.bend:461-466`: a failed `IO.random_u32` yields seed 0, so port 10000 on all ten tries and on the final unchecked pick. This is silent.
- `host/vk8s.bend:471` uses `"$HOME"`, but `Vk8s.home()` (`:284-285`) falls back to `/tmp` when `HOME` is unset. The two can disagree.
- `host/vk8s.bend:69`: `Process.run` has a 600000 ms timeout, so a hung `nc` stalls create for 10 minutes. `nc` is in the preflight list (`src/cli/cli.bend:1622`), so a missing `nc` is caught earlier.
- vcluster binds `localhost:port` (`vcluster/pkg/util/clihelper/clihelper.go:185-199`). The merged code only connects to `127.0.0.1`. An IPv6-only listener is missed. A port that is bound but not listening is also missed.

The loop shape matches vcluster's `RandomPort` (`clihelper.go:172-182`): ten checked tries, then one unchecked random port.

### F8. Low: laws pin shell text, and amendments are in place

- `laws/plan.bend:554-556` is `{P.Plan.idle_reclaim() == P.Run{... <the whole script> ...}}`. It is a copy of the implementation. It catches a diff and nothing about behavior.
- `laws/plan.bend:605-607` does the same for compaction.
- Nothing pins `Plan.reclaim_backoff_runs` or `Plan.refault_max_pages` on their own. Only `reclaim_every_ticks`, `idle_busy_percent`, `cache_keep_kib` and `reclaim_min_kib` have separate laws.
- `tests/plan.bend:201-207` only calls `String.contains` on the script text.
- No test runs the script.
- No law covers `Cli.port_from` (`src/cli/cli.bend:1153`) or the first-free rule. The range 10000..12999 matches `clihelper.go:174` but nothing pins it.

The reclaim law was flipped three times: Active plus Inactive, then Inactive, then Active plus Inactive again. The amendment comments at `laws/plan.bend:371` and `:536-545` cite approval for the tick change and for the "trim". 7ed2087 flips the amount back to Active plus Inactive and its message records no approval. Its comment reads "Amended again 2026-11-16". CLAUDE.md rule 1 says never edit existing laws, and docs/GOAL.md says "only add laws, never weaken them". The laws sit under `# Proposed:` blocks, which softens this. Rule 8 does not apply, because vcluster has no counterpart.

### F9. Low: tick periods are tied to a number nothing pins

The laws pin tick counts: 10, 30, 600 (`laws/plan.bend:371-381`, `:492-506`, `:546-547`, `:603-604`). The tick length is the literal `IO.sleep(1000)` at `host/init.bend:684`. No law ties the two together. Changing the sleep would silently change every period.

- The real tick is the sleep plus the work of the steps (F3). Periods are therefore longer than nominal, and the laws say "periods unchanged".
- `Init.drain` (`host/init.bend:493-503`) now sleeps 1000 ms. Its comment still says "250 ms apart". It has no caller, so nothing is affected today.
- The benefit evidence is thin. docs/STATUS.md:750 reports a worker going 2.83-3.20% to 2.74-2.97% over 3 rounds, and the ranges overlap. The surrounding text says host load varies run to run.
- Latency rose from 250 ms to 1 s for host requests, power button polling and the 5 s daemon restart (the delay is `src/guest/supervise.bend:14`).

### F10. Low: console noise from the reclaim step

`host/init.bend:408-413` prints `run /bin/busybox sh -c '<about 900 bytes>'` for every `P.Run`. That is one line every 30 s for reclaim and one every 10 min for compaction. Each console byte is a serial write to the VMM. `--console-log ...max=64M,keep=2` bounds the file (`src/cli/cli.bend:1090`). At about 1 KB per 30 s that is roughly 2.9 MB a day per VM. Script stderr goes to the same console (see F2).

### F11. Low: compaction timing and cost

- `host/init.bend:914` starts `tick` at 1. The run at tick 600 only writes the baseline (`pt=0`, so `exit 0`). The first real compaction is at tick 1200, 20 minutes after boot. The comments in `src/guest/plan.bend:1677` and `docs/ref/footprint-decisions.md` M4 say "every 10 min".
- The idle test is a 10-minute average. A burst under about 60 s of full CPU qualifies as idle.
- The evidence is one run: "777 MB at 4.5 min idle, 741 MB at 12.5 min (after one compaction)", which the doc itself calls "A small gain". The cost is a full-zone compaction on one vCPU.
- The CPU-window prefix is copied into both scripts (`src/guest/plan.bend:1659-1664` and `:1687-1692`).

### F12. Low: COPYFILE_DISABLE fixes creation only

`host/vk8s.bend:1621-1626` adds `COPYFILE_DISABLE=1` to the `tar -czSf` call. Snapshots made before 927f0a4 on macOS still carry `._` entries. Restore compares the full entry list to `metadata.json cluster.env data.img` (`host/vk8s.bend:1636-1639`). It fails with `expected metadata.json as first entry, got ._metadata.json` or `the snapshot must hold exactly metadata.json, cluster.env and data.img`.

Restore already extracts by name at `:1643`. It could drop `._*` lines from the listing. No test covers `restore_sh`.

`restore_sh` lists and then extracts the same path, so the archive can change between the two.

`awk '{print $NF}'` on `tar -tv` output assumes names without spaces. The names are fixed, so this is fine.

### F13. Low: stripped guests lose diagnostics

`scripts/guest/build.sh` now passes `-s` to both `zig cc` lines. A PID 1 crash gives no symbols, and the same holds for `vk8s-guest`. I did not find where the unstripped output is kept. The size gain is real (the commit message gives 81 MB to 7.8 MB). `-s` removes `.symtab`, and `.dynsym` stays, so `dlopen` should be unaffected. Not verified by running.

### F14. Low: `scripts/regression.sh`

- `:106-107` runs `vk8s delete` on `st`, `vc` and `hc` before every run. A user cluster with one of those names is destroyed without a prompt.
- The merged 58b5bf6 version was zsh-only. It read `out/conformance/regression-focus.txt`, which is untracked. It also never set an exit code. Later commits (ef57d7c) fixed both.
- `scripts/regression-focus.txt:4-6` says the original list of 28 names and 43 tests "was never committed" and that the file is a reconstruction. It has 26 lines. Whether it matches the 43-test count in the recent commit messages is not verified.
- Smaller points: `--kubernetes-version v1.36.6` is hard-coded at `:68`. The `sonobuoy run` exit code is unchecked. Inline `python3` at `:76` is allowed as build glue.

## Contradictions

| Place A | Place B |
|---|---|
| `src/guest/plan.bend:1649` "120 runs (1 h)" | The counter only moves on idle runs (F1). |
| `src/guest/plan.bend:1626` "since the last run, 30 s ago" | The refault baseline only moves on idle runs. |
| `laws/plan.bend:538` "20 runs (10 min)" | `laws/plan.bend:543` "120 runs (1 h)", the current value. |
| `src/guest/plan.bend:1677` and `docs/ref/footprint-decisions.md` M4 "every 10 min" | The first compaction is at 20 min (F11). |
| `host/init.bend:492` "250 ms apart" | `host/init.bend:500` `IO.sleep(1000)` |
| `docs/STATUS.md:823` "2400 ticks of 250 ms" | `src/guest/plan.bend:1603` 600 ticks of 1 s |
| `docs/DESIGN.md:73` "about 78 MB" | `docs/STATUS.md:1096` "81 MB -> 7.8 MB each" |
| `docs/GOAL.md` Rules "pure Bend as far as possible" | About 30 lines of arithmetic and state logic in `sh -c` strings. |
| CLAUDE.md rule 1 and `docs/GOAL.md` "only add laws" | Three in-place amendments of the reclaim and tick laws. |

## Decisions

| # | Choice | Changes | Recommendation |
|---|---|---|---|
| D1 | Keep the reclaim shell, or move the decision into Bend | Shell fix is two small edits to the script and two law bodies. Bend means a pure `Plan.reclaim_decide(prev, stat, vmstat, meminfo)`. It returns the new state and an optional KiB amount. `host/init.bend` reads the files and writes `memory.reclaim` through the existing `Init.read` and `P.Write`. | Bend. GOAL.md asks for it, it makes F1 and F2 testable, and it removes four forks (`sh`, `head`, `awk` twice) every 30 s. The shared pure idle-window function also fixes the copy in F11. |
| D2 | Reclaim amount | Today: Active plus Inactive above the floor, guard afterwards. Alternative: Inactive first, add Active only after N quiet windows, or cap per run. | Ramp. It trades a few tens of MB of footprint for no storm at each expiry. This is a product choice on the footprint target against idle CPU. |
| D3 | Run reclaim synchronously or in the background | Background means `Spawn` as fstrim does, plus a lock file. | Background with a lock, and stagger compaction from reclaim and fstrim. |
| D4 | Port reservation | Early directory creation, `port` file and duplicate re-scan, or a lock around pick and record. | Early `mkdir` with `port` written in the same step. It also closes the name race. |
| D5 | Tick periods | Add `Plan.tick_ms()` with a law of 1000. Derive tick counts from seconds, and pin the periods. | Do it. It is small and it stops silent drift. |
| D6 | Laws for reclaim and compaction | Add behavior laws over the pure function under `# Proposed:`. Ask the architect to retire the text-equality laws. | Add and ask. Rule 1 forbids deleting them. Get approval for 7ed2087's amendment. |
| D7 | `regression.sh` cluster names | Prefix the names, for example `reg-st`, `reg-hc` and `reg-vc`. Or refuse to delete clusters it did not create. | Prefix. |
| D8 | Restore tolerance for AppleDouble entries | Ignore `._*` entries in `restore_sh`. | Do it. |
| D9 | Symbols for stripped guests | Keep the unstripped binaries as a CI artifact. | Do it. |
| D10 | Port probe | Bend `TCP.connect` (already used at `host/init.bend:344-351`) for the probe. The recorded-port check becomes a Bend directory read. | Bend. The probe is then available without a shell. |

## Unchanged

- The loop shape and range of `random_port` match vcluster's `RandomPort`.
- The reclaim and compaction scripts use no untrusted input. They read only kernel files and root-owned `/run` state. I found no injection path.
- `machine_maintenance` (`src/guest/container_host.bend:41`) keeps reclaim, compaction, fstrim and clock sync out of container mode.
- The native `NInit.supervise` already ticked every second (`host/init.bend:1014-1026`).
- `Init.wait_tcp` and `Init.pause_then` poll at 250 ms (`host/init.bend:339-352`). The 1 s tick does not touch them.
- The snapshot `umask 077` and the raw-disk check are unchanged.
- `Sup.stop_grace_ms` is unchanged.

## Candidate work items

**D1, D3 (reclaim in Bend, background, F1 to F4, F10, F11)**
- `src/guest/plan.bend:1659-1673` and `:1687-1695`: replace the scripts with a pure decide function. Tests: `tests/plan.bend:201-207`, `laws/plan.bend:546-556` and `:603-607`, `proofs/plan.bend:215-227` and `:251-257`.
- `host/init.bend:408-413`: shorten or suppress the `run` log line for chores.
- `host/init.bend:692-702` and `:681-690`: run as `Spawn` with a lock, and read `/proc` files in Bend.
- `host/init.bend:741-743`: stagger the three chores.
- `host/init.bend:914`: tick starts at 1, so compaction is at 20 min. Decide what the baseline should be.

**D2 (reclaim amount)**
- `src/guest/plan.bend:1669` and the comment at `:1626-1630`. Tests: `laws/plan.bend:536-545`, `tests/plan.bend:205-206`.

**D4, D10 (port reservation and probe)**
- `host/vk8s.bend:679-694`, `:785-794`, `:1661`, `:1742`: pick and record in one step.
- `host/vk8s.bend:461-499`: handle the `random_u32` failure, probe derived ports, align `$HOME`. Tests: none today. Add a law for `Cli.port_from` in `laws/cli.bend`, near `:285`.

**D5 (tick coupling)**
- `src/guest/plan.bend:1574-1607`, `:1631`, `:1681`: add `Plan.tick_ms` and `ticks_for`.
- `host/init.bend:684`, `:500`, `:493`: use `Plan.tick_ms`, and fix or remove `Init.drain`.
- Laws: `laws/plan.bend:371-381`, `:492-506`, `:546`, `:603`.

**D6, D8, D9**
- `host/vk8s.bend:1636-1643`: ignore `._*` lines in the listing. Tests: none today for `restore_sh`; `tests/snapshot.bend` is nearby.
- `scripts/guest/build.sh`: keep the unstripped binaries as an artifact.
- `docs/DESIGN.md:73`, `docs/STATUS.md:823`: fix the stale numbers.

**D7**
- `scripts/regression.sh:106-107`, plus the cluster names used in `:60-70` and in `.github/workflows` job `kvm-regression`.

## Links

- Reference vcluster, shallow clone at `/ref/vcluster` (3a0085b6). `RandomPort` and `checkPort` are in `pkg/util/clihelper/clihelper.go`.
- https://github.com/loft-sh/vcluster
- https://github.com/chenhunghan/bend-vk8s
- Commits reviewed: 58b5bf6, bffc050, 256e336, 7ed2087, 3935653, 927f0a4, 8a92017 on main.