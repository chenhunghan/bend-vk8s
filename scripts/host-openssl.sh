#!/usr/bin/env bash
# The macOS host's OpenSSL 3, as two release archives a Mac without
# Homebrew downloads with the guest assets (docs/ref/macos-tls.md):
# libssl.3.dylib.tgz and libcrypto.3.dylib.tgz, each holding one file, as
# Assets.fetch_one_strict wants.
#
#   scripts/host-openssl.sh [OPENSSL_LIB_DIR] [OUT_DIR]
#
# OPENSSL_LIB_DIR (default: Homebrew's openssl@3, `brew --prefix
# openssl@3`/lib) holds libssl.3.dylib and libcrypto.3.dylib. OUT_DIR
# (default out/release/arm64, the arm64 release's files) gets the two
# archives and LICENSE-openssl.txt, and their SHA-256 lines in SHA256SUMS
# (replacing earlier lines of the same names). Writes nothing else.
#
# Homebrew's libssl names its libcrypto by an absolute Cellar path and
# each library's own id is its /opt/homebrew path; on a Mac without
# Homebrew dyld would not find libcrypto. So both ids become
# @loader_path/<name>, libssl's reference to libcrypto becomes
# @loader_path/libcrypto.3.dylib (the two always sit side by side), and
# both are signed again ad hoc (install_name_tool voids the signature;
# arm64 macOS refuses unsigned code). vk8s itself is ad hoc signed without
# the hardened runtime, so library validation does not apply.
#
# Its compiled-in OPENSSLDIR stays Homebrew's, where a clean Mac has no CA
# bundle: vk8s sets SSL_CERT_FILE=/etc/ssl/cert.pem (macOS's own bundle)
# when it points the loaders at these libraries (Cli.tls_env).
set -euo pipefail
cd "$(dirname "$0")/.."
src=${1:-$(brew --prefix openssl@3 2>/dev/null)/lib}
out=${2:-out/release/arm64}
[ "$(uname -s)" = Darwin ] || { echo "host-openssl: needs macOS (install_name_tool, codesign)" >&2; exit 1; }
for f in libssl.3.dylib libcrypto.3.dylib; do
  [ -f "$src/$f" ] || { echo "host-openssl: no $src/$f" >&2; exit 1; }
done
mkdir -p "$out"
out=$(cd "$out" && pwd)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp "$src/libssl.3.dylib" "$src/libcrypto.3.dylib" "$stage/"
chmod 644 "$stage/libssl.3.dylib" "$stage/libcrypto.3.dylib"
install_name_tool -id @loader_path/libcrypto.3.dylib "$stage/libcrypto.3.dylib" 2>/dev/null
install_name_tool -id @loader_path/libssl.3.dylib "$stage/libssl.3.dylib" 2>/dev/null
old=$(otool -L "$stage/libssl.3.dylib" | awk 'NR > 1 && /libcrypto\.3\.dylib/ { print $1 }' | grep -v '^@loader_path' | head -1)
[ -n "$old" ] && install_name_tool -change "$old" @loader_path/libcrypto.3.dylib "$stage/libssl.3.dylib" 2>/dev/null
codesign -s - -f "$stage/libcrypto.3.dylib" 2>/dev/null
codesign -s - -f "$stage/libssl.3.dylib" 2>/dev/null
# Nothing may still name a Homebrew (or any other absolute non-system) path.
if otool -L "$stage/libssl.3.dylib" "$stage/libcrypto.3.dylib" | awk 'NR > 1' | grep -v ':$' \
  | awk '{ print $1 }' | grep -v '^@loader_path/\|^/usr/lib/\|^/System/' >&2; then
  echo "host-openssl: a library still names a path above" >&2; exit 1
fi
codesign -v "$stage/libssl.3.dylib" "$stage/libcrypto.3.dylib"
lic=$(dirname "$src")/LICENSE.txt
if [ -f "$lic" ]; then cp "$lic" "$out/LICENSE-openssl.txt"; fi
for f in libssl.3.dylib libcrypto.3.dylib; do
  COPYFILE_DISABLE=1 tar -C "$stage" -czf "$out/$f.tgz" "$f"
done
sums=$(cd "$out" && shasum -a 256 libssl.3.dylib.tgz libcrypto.3.dylib.tgz)
touch "$out/SHA256SUMS"
{ grep -v '  libssl\.3\.dylib\.tgz$\|  libcrypto\.3\.dylib\.tgz$' "$out/SHA256SUMS" || true; echo "$sums"; } > "$stage/sums"
mv "$stage/sums" "$out/SHA256SUMS"
echo "$sums"
echo "next: upload both archives to the arm64 release and pin them in Manifest.host_darwin (src/cli/manifest.bend)"
