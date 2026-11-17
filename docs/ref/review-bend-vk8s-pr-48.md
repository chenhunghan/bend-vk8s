## Findings

I reviewed the merged #48 (and #42) on `origin/main` (881a387). I read the code only. I did not build, run or install anything. I found three defects. The asset fetch and staging code itself is sound.

### 1. The container backend never downloads the role sets, so a fresh release install cannot create a container cluster

`host/vk8s.bend:2131-2132` and `2166-2169`:
```
Vk8s.run_ok("test", ["-f", assets ++ "/vk8s.cpio", "-a", "-f", assets ++ "/base.img",
  "-a", "-f", assets ++ "/node.img", "-a", "-f", assets ++ "/control-plane.img"])
...
have : Bool <- Vk8s.ctr.have(per, assets)
Vk8s.unless(have, Vk8s.die("vk8s assets not found in " ++ assets ++ " (set VK8S_ASSETS)"))
```
- `Vk8s.ctr.create` takes its assets from `Vk8s.assets(home)`.
- That function fetches only `Manifest.files()`: Image, vk8s.cpio, base.img and data.img.
- Only the VM path fetches sets, through `Vk8s.sets_ensure` (`host/vk8s.bend:400`). That function is called only from `Vk8s.role_flags` (`:420`).
- The container path never calls it.
- The sets are `node.img`, `control-plane.img` and `images.img`.
- Failure scenario: the next release pins `base.img` and the sets.
  - A Linux user runs `vk8s create c1 --backend container` on a clean `~/.vk8s`.
  - base.img is downloaded, but node.img and control-plane.img are not.
  - `ctr.have` returns false.
  - The user sees "vk8s assets not found ... (set VK8S_ASSETS)". The real cause is a set that was never fetched.
- The images set is never fetched either, so a container cluster never gets preloaded add-ons even when the release has them.
- The shipped pin is still the pre-set release, so this is hidden today. It breaks the moment the release is bumped.
- Fix: call `Vk8s.sets_ensure(home, assets, R.Ctr.sets(images))` in `Vk8s.ctr.create` before `ctr.have`. Fetch `images` too when the release pins it.

### 2. The guest base image is built from unpinned downloads, and only the output is hashed

- `scripts/guest/alpine-kernel.sh:23-26` fetches the kernel and its modules from `https://dl-cdn.alpinelinux.org/alpine/latest-stable/main/...`. It picks the file name by scraping the directory listing. It has no checksum and no signature check.
- `scripts/guest/build.sh:55-58` does the same for busybox-static.
- `scripts/guest/build.sh:77` is `curl -fsSL -o out/build/cacert.pem https://curl.se/ca/cacert.pem`. The CA bundle goes into every guest at `etc/ssl/certs/ca-certificates.crt`, and it has no hash check.
- `scripts/guest/debs.py:22` downloads Debian packages with `urllib.request.urlopen`. The code reads `Packages.gz` only for `Filename` and never uses the `SHA256` field. It does not check `InRelease`. This brings in glibc, libssl3, iptables and conntrack.
- `scripts/guest/images.sh:18-21` builds the images set by pulling tags (`flannel:v0.28.10`, `coredns:1.14.2`, ...) through a live cluster. It records no digests.
- `scripts/guest/fetch-assets.sh` pins the Kubernetes bundle, the registry and gVisor correctly. The kernel, libc, libssl, CA roots and add-on images are the exceptions.
- Failure scenario: a MITM of curl.se, a bad CDN node, or a changed `latest-stable` makes `build.sh` embed a malicious CA bundle or libssl.
  - `release-assets.sh` then hashes the result.
  - The pin makes the malicious build the trusted one on every user's machine.
  - Two builds of the same commit on different days also produce different `base.img` bytes.
  - The "same bytes" claim in `mksqfs.sh` and `disktar.py` holds only for identical inputs.
- Fix: pin a SHA-256 for each of these inputs in the scripts. For Debian, check the package against the `SHA256` in a signature-verified `Packages` index. For the images, build from `name@sha256:` digests.

### 3. Optional sets are mandatory on the host, so the cache-down fallback can abort `create`

`host/vk8s.bend:403-407`:
```
have : Bool <- Vk8s.have_all(A.Assets.set_paths(assets, sets))
Vk8s.sets_fetch(have, String.eq(assets, A.Assets.dir(home, M.Manifest.version_for(arch))), arch, assets, sets)
ok : Bool <- Vk8s.have_all(A.Assets.set_paths(assets, sets))
Vk8s.unless(ok, Vk8s.die("the vk8s assets in " ++ assets ++ " lack a set of " ...
```
- The build treats `images` as optional.
  - `scripts/guest/mksets.sh` skips a set whose entries are absent.
  - `scripts/release-assets.sh` pins only the sets whose `.img` exists.
- The image cache is "not fatal" by design. `Vk8s.cache_ensure.go` prints a warning and carries on.
- `Assets.role_sets(role, cached=False)` always lists `images`, and `sets_ensure` dies if any listed set is missing.
- Failure scenario 1: a release or local build has no `images.img`, and the user runs `VK8S_CACHE=off vk8s create c1`.
  - The cache is not running, so `cached` is false.
  - The standalone role asks for `images`.
  - `create` dies with "lack a set of node, control-plane, images".
  - A pinned release that has no `images` entry fails the same way.
- Failure scenario 2: an assets dir has no `cache.img`. `cache_boot` calls `role_flags` at `host/vk8s.bend:510` for role "cache". The `die` ends the whole `create` instead of printing the "pulling from the registries directly" warning.
- Fix: in `sets_ensure`, drop an optional set (`images`, and `cache` for the cache VM) when the release does not pin it and the file is absent. Warn instead of dying, so the VM boots with kubelet pulling from upstream.

## Questions for the author

- **Interrupted downloads leak staging dirs.** Verified, lower severity.
  - `Assets.fetch_sh` and `Assets.fetch_into_sh` (`src/cli/assets.bend:69`, `189`) create `.fetch.XXXXXX` and only `rm -rf "$t"` on the error paths. There is no `trap` for INT or TERM.
  - Ctrl-C during a download of hundreds of MB leaves the partial staging dir.
  - `Vk8s.assets_names_sh` (`host/vk8s.bend:1127`) globs `*/`, which skips dot dirs, so `vk8s assets prune` never lists or removes them.
  - Should the script add `trap 'rm -rf "$t"' EXIT INT TERM`, and should prune clear `.fetch.*`?
- **Offline first boot regressed.** Verified by reading, and it is the A3 design.
  - `Plan.hosts_toml_pull` (`src/guest/plan.bend:729`) gives the cache `capabilities = ["pull"]` only. containerd resolves tags at the upstream and uses the cache for blobs.
  - With the cache up, no `images` disk is attached, so the first boot with no internet cannot pull flannel, CoreDNS or kube-proxy. Before #48 it worked offline.
  - Is that accepted?
  - `cache_running` (`host/vk8s.bend:325`) probes only the 15002 registry, and only at VM start.
- **`mksets.sh` fails on a missing entry only if the whole set is empty.** `:29` is `if [ -e "$a/$f" ]; then cp ...; any=1; fi`. If a renamed binary such as `containerd-shim-runc-v2` is missing from `ASSETS_BIN`, the `node` set is still built without it. The boot test would catch it only in CI. Should every entry of `node`, `control-plane`, `classic` and `cache` be required?
- **Laws.** I found no edited or weakened law in #48, and the expected values are explicitly vk8s-only.
  - `assets.fetch_into.skips_present` pins `[ ! -f ... ]`. A set already in the dir is trusted without a hash re-check at boot. Only existence is checked (`Vk8s.have_all` uses `can_open`). That is acceptable if `~/.vk8s` is user-private. Is that the intent?
  - `plan.with_sets.cache` and `plan.with_sets.worker_disks` use the magic indices 19, 21 and 26. They break on any plan edit before the disks step, but they do not pin wrong behavior.
- **Classic upgrade (not verified).** `Vk8s.upgrade.go` calls `boot_ws(..., "")`, and `Cli.cp_role("")` is "standalone". A classic cluster upgraded with `create --upgrade` would get standalone sets and flags. I think this predates #48. Command to settle it: `vk8s create --upgrade` on a classic cluster, then check `VK8S_SETS` in the VM's `--cmdline`.

## What was checked and how

- **Read:**
  - `CLAUDE.md` and `docs/DESIGN.md`.
  - `src/cli/assets.bend`, `src/cli/manifest*.bend`, `src/cli/cli.bend` (`role_flags`, `cp_role`, `with_sets`).
  - `src/guest/plan.bend` (`disks.v3`, `with_sets`, every `bin()` use, `runtime`, the cache, worker and classic plans).
  - `host/init.bend` (`VK8S_SETS`).
  - `host/vk8s.bend` (asset fetch, `sets_ensure`, `role_flags`, the cache, boot, workers, upgrade, restore, node add, rotate-ca, prune, container create).
  - `scripts/guest/{sets.txt,mksets.sh,mksqfs.sh,disktar.py,pack.sh,build.sh,fetch-assets.sh,images.sh,alpine-kernel.sh,debs.py}`, `scripts/release-assets.sh`, the CI workflow, and the new laws.
- **Diff and reviews:** I ran `git diff` over #48's commits and read the PR description. It has no review threads.
- **Fetch path:**
  - Archives are SHA-256-checked in a private `mktemp` staging dir.
  - The archive is listed to confirm exactly one regular file with the expected name, then unpacked from that same dir.
  - Moves are same-filesystem renames, and a file already present is not overwritten.
  - I found no partial-file or TOCTOU defect in this path.
  - A bad archive aborts before anything is moved.
- **Per-role selection:**
  - I traced each binary a plan runs against its set. This covered standalone, classic, worker, cache, restore (`etcdutl`), upgrade, node add, rotate-ca and `kubeadm certs`.
  - No VM misses a binary in the VM backend.
  - `kubectl` is only in standalone and classic, and workers never use it.
  - The only gap is the container backend (finding 1).
- **Reproducibility:** `disktar.py` sorts entries and fixes owner, mode and mtime. `mksqfs.sh` uses `-reproducible`. Output depends on the sqfstar and zstd versions (not verified across builders). The inputs are the problem (finding 2).
- **Not covered:**
  - bend-vmm disk order.
  - `tests/kernel16k_boot.sh` internals.
  - The native backend.
  - Anything that needs a run, such as `bend PROOF.bend` or `scripts/check.sh`.
  - The container path with a real `mount`.

## Links

- https://github.com/chenhunghan/bend-vk8s/pull/48
- https://github.com/chenhunghan/bend-vk8s/pull/42
- https://github.com/chenhunghan/bend-vk8s/tree/main/docs/ref/footprint-decisions.md