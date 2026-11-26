# Releasing vk8s

The maintainer publishes releases. Scripts here prepare files and print
hashes; none of them uploads anything.

## One release per asset arch

A release is a GitHub release whose tag is the asset version that
`scripts/release-assets.sh` computes (`v1.36.6-<8 hex>`, a hash of the
archives). Each arch has its own assets, so its own version and its own
release (docs/ref/explore-linux-hosts.md D2 a). Each binary pins its
arch's version and SHA-256 hashes in `src/cli/manifest_<arch>.bend` and
downloads its assets from the release of that version.

| Release | Binaries | Guest assets |
|---|---|---|
| arm64 (`manifest_arm64.bend`) | `vk8s-darwin-arm64`, `vk8s-linux-arm64` | arm64 base files and role sets |
| amd64 (`manifest_amd64.bend`) | `vk8s-linux-amd64` | amd64 base files and role sets |

`vk8s-linux-arm64` uses the same arm64 assets and role sets as
`vk8s-darwin-arm64`, so both go on the arm64 release.

## Pinned build inputs and their mirror

The guest build downloads third-party files, each pinned by a hash
(`scripts/guest/pins.sh`, `debs.lock`, `fetch-assets.sh`, `kernel.sh`).
An origin does not keep a pinned file for ever. Alpine keeps only the
newest build of a package in a branch, so the pinned `linux-virt` and
`busybox-static` packages leave Alpine's mirrors some days after they are
pinned (this broke every build in November 2026, when 6.18.65 replaced
6.18.64). deb.debian.org drops a package at a point release. The
Kubernetes bundle, gVisor and kube-router each come from one third-party
GitHub release, which its owner can remove. So the release
[`guest-inputs`](https://github.com/chenhunghan/bend-vk8s/releases/tag/guest-inputs)
holds a copy of each. It is a pre-release, never "latest", and not a vk8s
release: it only holds build inputs, and its text lists the license and
the source of each. Each download tries its origin first and takes the
copy when the origin does not answer. The pinned SHA-256 holds for
either, and a source that answers with other bytes fails the build: the
other source is not tried then.

| Files | Name in the release | Pinned in | Origin (override) |
|---|---|---|---|
| Alpine `linux-virt`, `busybox-static` (aarch64, x86_64) | `<arch>-<file>.apk` | `pins.sh` | Alpine's CDN (`ALPINE`) |
| CA bundle | `cacert-<date>.pem` | `pins.sh` | curl.se (`CACERT_URL`) |
| Debian packages (arm64, amd64) | `deb-<pool file>`, `~` and `+` as `_` | `debs.lock` | deb.debian.org (`DEBIAN_MIRROR`); after the copy, snapshot.debian.org |
| Kubernetes bundle, gVisor, kube-router (arm64, amd64) | `kubernetes-<ver>-<arch>-full.tar.gz`, `gvisor-<ver>-<arch>.tar.bz2`, `kube-router_<ver>_linux_<arch>.tar.gz` | `fetch-assets.sh` | github.com (`ASSETS_UPSTREAM`) |

`VK8S_INPUTS_MIRROR` names another copy than the release.

Not in the release, each with one source: the kernel.org tarball and
patch and the aports kernel config of `kernel.sh` (kernel.org keeps old
versions; the config is named by its commit), the add-on images of
`pins.sh` and the Debian image `kernel.sh` builds in (by digest, from
their registries).

A pin bump of any of these files:

1. Change the pin where it lives: `alpine_pin` or `CACERT_FILE` in
   `scripts/guest/pins.sh` (and, for `linux-virt`,
   `scripts/guest/kernel.sh`: `KVER`, the patch's SHA-512 and the aports
   commit and its time), as the "Bumping" comment there says;
   `scripts/guest/debs.py --lock` for `debs.lock`; the versions and
   SHA-256 in `scripts/guest/fetch-assets.sh`.
2. Run `scripts/guest/mirror-inputs.sh` (needs `gh` with write access).
   It uploads the newly pinned files and leaves the others, so older
   commits still build. It never replaces a file: a name that is there
   with other bytes is reported and fails the run. It is the one script
   here that uploads. For a new component, add its license and source to
   the release text in that script.
3. CI's `check` job runs `scripts/guest/mirror-inputs.sh --check`: a pin
   whose file is not in the release fails it.

## Gates

- Every push: `scripts/gate.sh` prints GATE PASS. It runs
  `bend PROOF.bend`, `scripts/check.sh` and the kernel's verdict on the
  modules whose laws or proofs differ from origin/main (CI's verdict job
  runs it on every module; a6ccf81 went red there on a law the checker
  accepted, which the push gate did not run then).
- macOS, every release: the push gate and the regression subset
  (scripts/regression.sh, both modes) pass on the release candidate.
- macOS, a release that changes what Kubernetes sees (decided by the
  owner 2026-11-25): certified conformance in both modes
  (scripts/conformance.sh) and the soak (`scripts/soak.sh 10 20`: 10
  create/delete cycles, then a 20-minute workload) pass on the release
  candidate. A release counts when its diff since the last certified
  release touches any of: the guest assets or anything that builds them
  (scripts/guest, host/init.bend, host/snapshotter.bend, src/guest,
  src/layers), control-plane or kubelet flags, networking, the syncer
  (classic mode), the bend-vmm or bend-kube-runtime pins, port
  forwarding, the image cache or the layer filler (host/cache, host/oci,
  host/layers). The diff decides, not the intent of the change.
- macOS, any other release (host-only): no certified run and no soak.
  Its guest assets must be the files a certified release shipped, byte
  for byte (the same asset version; check SHA256SUMS), and its notes
  name that release and its certified runs.
- Once per major change to the guest or to a long-running host process
  (not per release): a 24-hour uptime run of one cluster that idles,
  sleeps, wakes and runs a small workload, with memory, disk and
  restarts recorded in docs/STATUS.md (`scripts/uptime.sh`). The paths
  decide, as for the certified run. A release needs a new run when its
  diff since the commit the last run was built from touches any of:
  what runs in the guest for the cluster's whole life (host/init.bend,
  src/guest, host/gsys.bend, host/host_socket.bend, the guest C effects
  under host/effs, the kernel or its config under scripts/guest), the
  snapshotter as VM nodes use it (host/snapshotter.bend, src/layers),
  the host processes that outlive a command (host/idle_proxy.bend and sleep
  and wake, port forwarding, the layer filler under host/layers and
  host/cache), or the bend-vmm pin. The same list decides whether a
  change that lands while a run is going ends its worth: if it touches
  one of these for VM nodes, the run starts again on the new build; a
  change that only adds a path VM nodes do not take (a container or
  native node's branch, a flag not passed) does not, and STATUS names
  the commit the run was built from and why the later ones do not count.
  The run goes on the release candidate where it can; started earlier,
  it holds only under that rule.
- linux-arm64: the arm64 KVM smoke passes on the emulated KVM host
  (workflow `emulated-kvm`, scripts/smoke-emulated-kvm.sh; GitHub's arm64
  runners have no /dev/kvm, so it runs under QEMU TCG with EL2).
- linux-amd64: CI jobs `kvm-smoke` and `kvm-regression` pass on real KVM.

## Steps, per arch

1. Build the guest assets: `scripts/guest/fetch-assets.sh`, then
   `scripts/guest/build.sh` (with `ARCH=amd64` for amd64). They go to
   `~/.vk8s/assets/v1.36.6` (arm64) or `~/.vk8s/assets/v1.36.6-amd64`.
2. Pack them and pin them: `scripts/release-assets.sh [DIR] ARCH`. This
   writes `out/release/<arch>/` (the archives, `SHA256SUMS`, `VERSION`)
   and `src/cli/manifest_<arch>.bend`. Commit the manifest.
   arm64 only, on the Mac: `scripts/host-openssl.sh "$(brew --prefix
   openssl@3)/lib" out/release/arm64` writes `libssl.3.dylib.tgz` and
   `libcrypto.3.dylib.tgz` (install names relative, ad hoc signed;
   docs/ref/macos-tls.md) and prints their SHA-256. Pin both in
   `Manifest.host_darwin` (src/cli/manifest.bend, by hand) and commit it
   with the manifest; add OpenSSL's `LICENSE.txt` to the release notes or
   files. A Mac then needs no Homebrew.
3. From that commit, build each binary of the arch:
   - `vk8s-darwin-arm64`: `scripts/build-mac.sh` on the Mac (ad-hoc signed
     with the Hypervisor entitlement).
   - `vk8s-linux-arm64`: `scripts/build-linux.sh out/vk8s-linux-arm64
     aarch64` on Linux arm64 (or CI job `linux-build`).
   - `vk8s-linux-amd64`: `scripts/build-linux.sh out/vk8s-linux-amd64
     x86_64` on Linux x86_64.
4. Add each binary: `scripts/release-assets.sh --binary OS FILE ARCH`, for
   example `scripts/release-assets.sh --binary linux out/vk8s-linux-arm64
   arm64`. It checks the file's header (ELF or Mach-O, the arch), checks
   that the tree's manifest pins `out/release/<arch>/VERSION`, copies the
   file to `out/release/<arch>/vk8s-<os>-<arch>` and adds its SHA-256 to
   `SHA256SUMS`.
5. Test from the files: with no local assets of that version, the binary
   fetches the archives, checks each SHA-256 and creates a cluster.
6. The maintainer creates the release named by `VERSION` and uploads
   `out/release/<arch>/*`, for example
   `gh release create "$(cat out/release/arm64/VERSION)" out/release/arm64/*`.
   Then record it in docs/STATUS.md and update the install lines in
   README.md.
