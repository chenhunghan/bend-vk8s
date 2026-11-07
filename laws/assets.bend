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
