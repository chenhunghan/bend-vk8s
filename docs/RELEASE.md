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

## Gates

- macOS: the certified runs pass on the Mac (docs/STATUS.md).
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
