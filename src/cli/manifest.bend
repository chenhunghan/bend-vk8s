import Base
import ./assets.bend as A
import ./manifest_arm64.bend as MA
import ./manifest_amd64.bend as MX

# The guest assets this vk8s build runs, one pinned set per arch
# (docs/ref/explore-linux-hosts.md D2 a): scripts/release-assets.sh
# generates manifest_arm64.bend and manifest_amd64.bend, each the version
# (the GitHub release), the SHA-256 of the archives every VM boots and of
# each role set's archive (docs/ref/footprint-decisions.md D1). The host
# picks its arch by `uname -m` (Manifest.for_arch), then the sets of its
# VMs' roles (Manifest.sets_for, A.Assets.set_files).

# A pinned set: its arch (Go's GOARCH name), its release version and its
# archives. An arch with no set has "" and no archives.
type Pinned is Data:
  Pinned{arch: String, version: String, files: List<&2, A.AssetFile>}

# The macOS host's OpenSSL 3 (docs/ref/macos-tls.md): libssl.3.dylib.tgz
# and libcrypto.3.dylib.tgz of the arm64 release (scripts/host-openssl.sh
# makes them, with their SHA-256), fetched into host/ of the assets dir on
# a Mac (A.Assets.host_fetch). None until a release carries them: then a
# Mac still needs Homebrew's openssl@3. Kept by hand, not generated: the
# guest assets' version hash does not cover these files.
def Manifest.host_darwin() -> List<&2, A.AssetFile>:
  []

# The arm64 set (macOS on Apple Silicon, Linux arm64).
def Manifest.version() -> String:
  MA.ManifestArm64.version()

# (archive name, SHA-256 of the archive)
def Manifest.files() -> List<&2, A.AssetFile>:
  MA.ManifestArm64.files()

# (set, archive name, SHA-256 of the archive): the arm64 role sets
# (docs/ref/footprint-decisions.md D1).
def Manifest.sets() -> List<&2, A.SetFile>:
  MA.ManifestArm64.sets()

def Manifest.arch.pick(arm: Bool, x86: Bool) -> String:
  match arm x86:
    case True{} _:
      "arm64"
    case False{} True{}:
      "amd64"
    case False{} False{}:
      ""

def Manifest.arch.of(+u: String) -> String:
  Manifest.arch.pick(String.eq(u, "arm64") || String.eq(u, "aarch64"), String.eq(u, "x86_64") || String.eq(u, "amd64"))

# The asset arch of `uname -m`: arm64 for arm64 (macOS) and aarch64
# (Linux), amd64 for x86_64; "" for any other.
def Manifest.arch(uname: String) -> String:
  Manifest.arch.of(String.trim(uname))

def Manifest.version_for.go(arm: Bool, x86: Bool) -> String:
  match arm x86:
    case True{} _:
      MA.ManifestArm64.version()
    case False{} True{}:
      MX.ManifestAmd64.version()
    case False{} False{}:
      ""

# The release version pinned for an asset arch ("" when none is).
def Manifest.version_for(+arch: String) -> String:
  Manifest.version_for.go(String.eq(arch, "arm64"), String.eq(arch, "amd64"))

def Manifest.files_for.go(arm: Bool, x86: Bool) -> List<&2, A.AssetFile>:
  match arm x86:
    case True{} _:
      MA.ManifestArm64.files()
    case False{} True{}:
      MX.ManifestAmd64.files()
    case False{} False{}:
      []

# The archives pinned for an asset arch (none when no set is).
def Manifest.files_for(+arch: String) -> List<&2, A.AssetFile>:
  Manifest.files_for.go(String.eq(arch, "arm64"), String.eq(arch, "amd64"))

def Manifest.for_arch.of(+arch: String) -> Pinned:
  Pinned{arch, Manifest.version_for(arch), Manifest.files_for(arch)}

# The set for this host, from `uname -m`.
def Manifest.for_arch(uname: String) -> Pinned:
  Manifest.for_arch.of(Manifest.arch(uname))

def Manifest.sets_for.go(arm: Bool, x86: Bool) -> List<&2, A.SetFile>:
  match arm x86:
    case True{} _:
      MA.ManifestArm64.sets()
    case False{} True{}:
      MX.ManifestAmd64.sets()
    case False{} False{}:
      []

# The role sets' archives pinned for an asset arch (none when no set is).
def Manifest.sets_for(+arch: String) -> List<&2, A.SetFile>:
  Manifest.sets_for.go(String.eq(arch, "arm64"), String.eq(arch, "amd64"))
