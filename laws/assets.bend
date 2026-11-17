import Base
import ../src/cli/assets.bend as A

# Spec for src/cli/assets.bend. GitHub serves release assets at
# https://github.com/OWNER/REPO/releases/download/TAG/FILE.

law assets.url:
  {A.Assets.url(A.Assets.default_base(), "v1.36.6-bd3cbb56", "Image.tgz")
   == "https://github.com/chenhunghan/bend-vk8s/releases/download/v1.36.6-bd3cbb56/Image.tgz" : String}

law assets.dir:
  {A.Assets.dir("/Users/a", "v1.36.6-bd3cbb56") == "/Users/a/.vk8s/assets/v1.36.6-bd3cbb56" : String}

# Every archive is checked against its pinned SHA-256 before it is unpacked.
law assets.fetch_checks_sum:
  {A.Assets.fetch_one("http://h", "v", A.AssetFile{"Image.tgz", "abc"})
   == "curl -fL --retry 3 --progress-bar -o \"$t/Image.tgz\" 'http://h/v/Image.tgz' && echo 'abc  Image.tgz' | (cd \"$t\" && shasum -a 256 -c -s) || { echo 'vk8s: Image.tgz: download failed or SHA-256 mismatch' >&2; rm -rf \"$t\"; exit 1; }; tar -xzSf \"$t/Image.tgz\" -C \"$t\" && rm -f \"$t/Image.tgz\" || { rm -rf \"$t\"; exit 1; }; " : String}

# Strict fetch (security review F7): checksum, then exactly one regular
# member named after the archive, extracted by name.
law assets.strict_lists_members:
  {String.contains(A.Assets.fetch_one_strict("http://h", "v", A.AssetFile{"Image.tgz", "abc"}),
     "case \"$l\" in -*\" Image\") ;; *) false ;; esac") == True{} : Bool}

law assets.fetch_sh_unique_staging:
  {String.contains(A.Assets.fetch_sh("/h/.vk8s/assets/v", "http://h", "v", []), "mktemp -d") == True{} : Bool}

# Proposed: a SHA-256 check that also runs on Linux hosts without shasum
# (docs/ref/explore-linux-hosts.md, Phase 1 and contradiction 5): shasum
# when present (macOS, as before), else GNU sha256sum. assets.fetch_checks_sum
# stays as pinned; the strict fetch, which vk8s uses, takes the fallback.
law assets.sha_tool_fallback:
  {A.Assets.sha256_check() == "if command -v shasum >/dev/null 2>&1; then shasum -a 256 -c -s; else sha256sum -c --status; fi" : String}
law assets.strict_sha_tool_fallback:
  {String.contains(A.Assets.fetch_one_strict("http://h", "v", A.AssetFile{"Image.tgz", "abc"}),
     "echo 'abc  Image.tgz' | (cd \"$t\" && if command -v shasum >/dev/null 2>&1; then shasum -a 256 -c -s; else sha256sum -c --status; fi)") == True{} : Bool}

# Proposed: per-role asset sets (vk8s design, docs/GOAL.md section 9;
# docs/ref/footprint-decisions.md D1, whose tables give these values).
# Besides the base files every VM boots (Image, vk8s.cpio, base.img,
# data.img), each VM attaches one read-only squashfs disk per set of its
# role: node (kubelet, kubeadm, containerd, the shim, runc, ctr, the CNI
# plugins, the pause image), control-plane (kube-apiserver,
# kube-controller-manager, kube-scheduler, kubectl, kine, etcd, etcdctl,
# etcdutl), classic (konnectivity-server), cache (registry) and images
# (the preloaded add-on tars). The images set goes only where the image
# cache does not run (A3): with the cache, the add-ons are pulled through
# it at first use. A classic control plane runs no pods, so no images.
law assets.role_sets.standalone:
  {A.Assets.role_sets("standalone", False{}) == ["node", "control-plane", "images"] : +List<String>}
law assets.role_sets.standalone_cached:
  {A.Assets.role_sets("standalone", True{}) == ["node", "control-plane"] : +List<String>}
law assets.role_sets.classic:
  {A.Assets.role_sets("classic", False{}) == ["node", "control-plane", "classic"] : +List<String>}
law assets.role_sets.classic_cached:
  {A.Assets.role_sets("classic", True{}) == ["node", "control-plane", "classic"] : +List<String>}
law assets.role_sets.worker:
  {A.Assets.role_sets("worker", False{}) == ["node", "images"] : +List<String>}
law assets.role_sets.worker_cached:
  {A.Assets.role_sets("worker", True{}) == ["node"] : +List<String>}
law assets.role_sets.cache:
  {A.Assets.role_sets("cache", False{}) == ["cache"] : +List<String>}
law assets.role_sets.unknown:
  {A.Assets.role_sets("other", False{}) == [] : +List<String>}
# A host downloads only the archives of the sets it needs.
law assets.set_files.picks:
  {A.Assets.set_files(["node", "images"],
     [ A.SetFile{"node", A.AssetFile{"node.img.tgz", "a"}},
       A.SetFile{"control-plane", A.AssetFile{"control-plane.img.tgz", "b"}},
       A.SetFile{"images", A.AssetFile{"images.img.tgz", "c"}} ])
   == [A.AssetFile{"node.img.tgz", "a"}, A.AssetFile{"images.img.tgz", "c"}] : List<&2, A.AssetFile>}
law assets.set_paths:
  {A.Assets.set_paths("/a", ["node", "cache"]) == ["/a/node.img", "/a/cache.img"] : +List<String>}
law assets.file_paths:
  {A.Assets.file_paths("/a", [A.AssetFile{"Image.tgz", "x"}, A.AssetFile{"base.img.tgz", "y"}]) == ["/a/Image", "/a/base.img"] : +List<String>}
law assets.files_of:
  {A.Assets.files_of([A.SetFile{"cache", A.AssetFile{"cache.img.tgz", "a"}}]) == [A.AssetFile{"cache.img.tgz", "a"}] : List<&2, A.AssetFile>}
law assets.sets_named.ok:
  {A.Assets.sets_named([A.SetFile{"node", A.AssetFile{"node.img.tgz", "a"}}]) == True{} : Bool}
law assets.sets_named.bad:
  {A.Assets.sets_named([A.SetFile{"node", A.AssetFile{"images.img.tgz", "a"}}]) == False{} : Bool}
# A set joins an existing assets dir: each missing archive is fetched
# strictly (checksum, one member) into a private staging dir inside it,
# then moved into place unless another run placed it first.
law assets.fetch_into.skips_present:
  {String.contains(A.Assets.fetch_into_sh("/h/a/v", "http://h", "v", [A.AssetFile{"node.img.tgz", "abc"}]),
     "if [ ! -f '/h/a/v/node.img' ]; then curl -fL --retry 3 --progress-bar -o \"$t/node.img.tgz\" 'http://h/v/node.img.tgz'") == True{} : Bool}
law assets.fetch_into.checks_sum:
  {String.contains(A.Assets.fetch_into_sh("/h/a/v", "http://h", "v", [A.AssetFile{"node.img.tgz", "abc"}]),
     "echo 'abc  node.img.tgz' | (cd \"$t\" && if command -v shasum >/dev/null 2>&1; then shasum -a 256 -c -s; else sha256sum -c --status; fi)") == True{} : Bool}
law assets.fetch_into.staging:
  {String.contains(A.Assets.fetch_into_sh("/h/a/v", "http://h", "v", []), "t=$(mktemp -d '/h/a/v'/.fetch.XXXXXX) || exit 1") == True{} : Bool}
law assets.fetch_into.no_overwrite:
  {String.contains(A.Assets.fetch_into_sh("/h/a/v", "http://h", "v", []), "[ -e '/h/a/v'/\"$n\" ] || mv \"$f\" '/h/a/v'/\"$n\"") == True{} : Bool}

# Proposed: optional sets (docs/ref/review-bend-vk8s-pr-48.md #3; vk8s
# design, no vcluster counterpart). images (made only after
# scripts/guest/images.sh, pinned only when a release has it) and cache
# (the image cache is not fatal) are optional: a set the assets dir lacks
# after the fetch is dropped with a warning when optional, and stops vk8s
# when required. Assets.role_sets stays as pinned above.
law assets.optional.images:
  {A.Assets.optional("images") == True{} : Bool}
law assets.optional.cache:
  {A.Assets.optional("cache") == True{} : Bool}
law assets.optional.node:
  {A.Assets.optional("node") == False{} : Bool}
law assets.optional.control_plane:
  {A.Assets.optional("control-plane") == False{} : Bool}
law assets.optional.classic:
  {A.Assets.optional("classic") == False{} : Bool}
law assets.present.drops_absent:
  {A.Assets.present(["node", "control-plane", "images"], [True{}, True{}, False{}]) == ["node", "control-plane"] : +List<String>}
law assets.absent.lists_absent:
  {A.Assets.absent(["node", "control-plane", "images"], [True{}, False{}, False{}]) == ["control-plane", "images"] : +List<String>}
law assets.missing_required.no_images:
  {A.Assets.missing_required(["node", "control-plane", "images"], [True{}, True{}, False{}]) == [] : +List<String>}
law assets.missing_required.node:
  {A.Assets.missing_required(["node", "images"], [False{}, False{}]) == ["node"] : +List<String>}
law assets.missing_optional.images:
  {A.Assets.missing_optional(["node", "control-plane", "images"], [True{}, True{}, False{}]) == ["images"] : +List<String>}
law assets.missing_optional.cache:
  {A.Assets.missing_optional(["cache"], [False{}]) == ["cache"] : +List<String>}
law assets.missing_required.cache:
  {A.Assets.missing_required(["cache"], [False{}]) == [] : +List<String>}
law assets.present.all:
  {A.Assets.present(["node", "images"], [True{}, True{}]) == ["node", "images"] : +List<String>}
