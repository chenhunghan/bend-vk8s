#!/usr/bin/env bash
# The layer filler daemon (host/layers/serve.bend, `vk8s layers serve`)
# end to end on Linux, no VM. It builds tests/layer_serve_echo.bend
# natively, writes small OCI images with Python (gzip layers, a config,
# an image manifest), serves them from a stub registry over TLS on
# 127.0.0.1:STUB_PORT (default 15443; a test CA, which the filler trusts
# through SSL_CERT_FILE, and VK8S_UPSTREAM points every registry at the
# stub), runs the filler on a free port, and asks it with bash's /dev/tcp
# as a node's snapshotter would (src/layers/ask.bend's line protocol).
# The stub asks for a token as Docker Hub does (/v2/ and every repository
# request answer 401 with a Bearer challenge until the request carries
# the token of its repository's pull scope), so the filler's registry
# client (host/oci/upstream.bend) is tested end to end. (Redirects are
# not: src/oci/auth.bend refuses one to a loopback host, the stub's;
# laws/oci_upstream.bend covers them.)
#
# - the filler got a token before its first request (the ping of /v2/),
#   and every repository request carried it;
# - a line that is not an ask, an ask for a registry the cache does not
#   serve, and a line over 512 bytes are answered "no not a valid ask";
# - three asks at once for one layer: one fill (the manifest fetched
#   once), all three answered "ok published", both layers of the image
#   in the store, their blobs not kept in ROOT/oci;
# - the same ask again: "ok present", and the registry is not asked; a
#   layer used in the last day is not written again, a day-old one has
#   its record's last use refreshed under its lock (Fill.rec.due.v3);
# - an ask whose chain ID is not one of the image's: "no the image has
#   no such layer";
# - an ask for a manifest the registry does not have: "no " and a
#   reason;
# - five asks at once for five images while the registry is slow: four
#   fill (Srv.cap.v2), one is answered "no the filler is busy";
# - the log has each published layer's phases (fetch, decompress,
#   unpack, fsync, rename, in ms) and each image fill's line, and the
#   layers fetched from the slow registry log a fetch of 2 s or more.
#
# Needs bend, clang, python3, openssl, sha256sum (or shasum), and the
# ports STUB_PORT and LAYERS_SERVE_PORT (default 32123) free. Prints PASS/FAIL lines;
# exits 1 on any FAIL.
set -uo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done
  wait 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
check() { # check NAME CONDITION-COMMAND...
  local name=$1; shift
  if "$@"; then pass "$name"; else fail "$name"; fi
}
port=${LAYERS_SERVE_PORT:-32123}
sport=${STUB_PORT:-15443}

echo "== build"
if ! bend tests/layer_serve_echo.bend -o "$tmp/secho" >"$tmp/build.log" 2>&1; then
  cat "$tmp/build.log"
  echo "FAIL build tests/layer_serve_echo.bend"
  exit 1
fi
if ! bend tests/cache_mirror_echo.bend -o "$tmp/mecho" >"$tmp/build.log" 2>&1; then
  cat "$tmp/build.log"
  echo "FAIL build tests/cache_mirror_echo.bend"
  exit 1
fi
pass "build"

echo "== images"
# Eight images of library/busybox: img0 has two layers, img1..img7 one
# each. For each: reg/<digest> files (manifest, config, layers), and a
# line "manifest-digest chain-of-first-layer hex-of-each-chain... blobs
# blob-digest-of-each-layer... config-digest" in imgN.
mkdir -p "$tmp/reg"
python3 -I - "$tmp" <<'PY'
import gzip, hashlib, io, json, sys, tarfile
tmp = sys.argv[1]

def sha(b):
    return "sha256:" + hashlib.sha256(b).hexdigest()

def put(b):
    d = sha(b)
    open(f"{tmp}/reg/{d}", "wb").write(b)
    return d

def layer(files):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.PAX_FORMAT) as t:
        for name, data in files:
            i = tarfile.TarInfo(name)
            i.mtime = 1700000000
            i.mode = 0o644
            i.size = len(data)
            t.addfile(i, io.BytesIO(data))
    tar = buf.getvalue()
    gz = gzip.compress(tar, mtime=0)
    return sha(tar), put(gz), len(gz)

for n in range(8):
    ls = [layer([(f"etc/img{n}", f"image {n}\n".encode())])]
    if n == 0:
        ls.append(layer([("etc/second", b"second layer\n")]))
    diffs = [d for d, _, _ in ls]
    config = json.dumps({"architecture": "amd64", "os": "linux",
                         "rootfs": {"type": "layers", "diff_ids": diffs}}).encode()
    cd = put(config)
    manifest = json.dumps({
        "schemaVersion": 2,
        "mediaType": "application/vnd.oci.image.manifest.v1+json",
        "config": {"mediaType": "application/vnd.oci.image.config.v1+json", "digest": cd, "size": len(config)},
        "layers": [{"mediaType": "application/vnd.oci.image.layer.v1.tar+gzip", "digest": b, "size": s}
                   for _, b, s in ls],
    }).encode()
    md = put(manifest)
    # Chain IDs (image-spec config.md): the first is the first diffID,
    # each next one sha256 of "<parent chain> <diffID>".
    chains = [diffs[0]]
    for d in diffs[1:]:
        chains.append(sha(f"{chains[-1]} {d}".encode()))
    blobs = [b for _, b, _ in ls]
    open(f"{tmp}/img{n}", "w").write(" ".join([md, chains[0]] + [c[7:] for c in chains] + ["blobs"] + blobs + [cd]) + "\n")
PY

echo "== stub registry"
# shellcheck source=tests/stub_registry.sh
. tests/stub_registry.sh
stub_registry "$tmp" "$sport" || exit 1
pids+=("$stub_pid")

root="$tmp/root"
mkdir -p "$root"
VK8S_UPSTREAM="https://127.0.0.1:$sport" SSL_CERT_FILE="$tmp/ca.pem" \
  "$tmp/secho" serve "$root" "$port" amd64 >"$tmp/serve.log" 2>&1 &
pids+=($!)

up() { # up PORT: something listens on 127.0.0.1:PORT
  (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}
ok=0
for _ in $(seq 100); do
  if up "$sport" && up "$port"; then ok=1; break; fi
  sleep 0.1
done
check "the stub registry and the filler listen" test "$ok" = 1
if [ "$ok" != 1 ]; then cat "$tmp/serve.log" "$tmp/registry.err"; echo "== $((fails)) failed"; exit 1; fi

ask() { # ask LINE: send LINE (printf %b) to the filler, print its reply line
  timeout 60 bash -c 'exec 3<>"/dev/tcp/127.0.0.1/$1" || exit 1; printf "%b" "$2" >&3; IFS= read -r l <&3; printf "%s\n" "$l"' _ "$port" "$1"
}
field() { # field IMG N: the Nth word of imgIMG
  cut -d' ' -f"$2" <"$tmp/img$1"
}
blob0=$(field 0 6)
blob1=$(field 0 7)
chain0="sha256:$(field 0 3)"
chain1="sha256:$(field 0 4)"
m0=$(field 0 1)

echo "== asks that are not asks"
check "a line that is not an ask" test "$(ask 'hello\n')" = "no not a valid ask"
check "a registry the image cache does not serve" \
  test "$(ask "ask gcr.io library/busybox $m0 $blob0 $chain0\\n")" = "no not a valid ask"
check "a line over 512 bytes" test "$(ask "$(printf 'a%.0s' $(seq 600))\\n")" = "no not a valid ask"
# The readiness probes above (up) connected and sent nothing: not
# logged. Only the three bad lines are.
(exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null
sleep 0.5
check "a peer that sends nothing is not logged as refused (3 bad lines only)" \
  test "$(grep -c 'refused a line that is not an ask' "$tmp/serve.log")" = 3

echo "== three asks at once for one layer"
: >"$tmp/reg.log"
touch "$tmp/before-fill"; sleep 1
line="ask docker.io library/busybox $m0 $blob1 $chain1\\n"
asks=()
for i in 1 2 3; do ask "$line" >"$tmp/a.$i" & asks+=($!); done
wait "${asks[@]}"
cat "$tmp"/a.[123]
check "three asks at once are each answered ok published" test "$(cat "$tmp"/a.[123] | grep -cx 'ok published')" = 3
check "one fill for the three asks (the manifest fetched once)" test "$(grep -c "/manifests/$m0" "$tmp/reg.log")" = 1
check "the filler pinged /v2/ and got one token before the pull" \
  test "$(grep -cx '/v2/' "$tmp/reg.log"),$(grep -c '^/token?scope=repository%3Alibrary%2Fbusybox%3Apull&service=stub$' "$tmp/reg.log")" = 1,1
check "every repository request carried the token" test "$(grep -cvx 'Bearer t-repository:library/busybox:pull' "$tmp/auth.log")" = 0
check "the asked layer is in the store, one image" test "$(unsquashfs -cat "$root/layers/$(field 0 4).sqfs" etc/second)" = "second layer"
check "the image's other layer is in the store" test "$(unsquashfs -cat "$root/layers/$(field 0 3).sqfs" etc/img0)" = "image 0"
check "no layer directory (one image file per layer)" test -z "$(find "$root/layers" -mindepth 1 -type d)"
# Host files the fill of this 2-layer image left under ROOT (made, not
# removed), and every file it made at all would be the same set plus the
# tmp tar, nonce directory and lock it removed: one image and two records
# a layer (docs/ref/layers-sqfs.md). The tar entries are not host files.
made=$(find "$root" -newer "$tmp/before-fill" -type f | grep -vc '/oci/')
find "$root" -newer "$tmp/before-fill" -type f | sed "s|$root/||" | sort
check "the fill left 3 files a layer: the image and two records ($made)" test "$made" = 6
check "the records of both layers" test -f "$root/layer-refs/$(field 0 3)" -a -f "$root/layer-refs/$(field 0 4)"
check "an automatic fill keeps no blob in ROOT/oci" test -z "$(find "$root/oci" -type f -name "${blob1#sha256:}*" 2>/dev/null)"
check "no layer lock left" test -z "$(ls -A "$root/layer-locks")"

echo "== the same ask again"
: >"$tmp/reg.log"
check "a layer in the store is answered ok present" test "$(ask "$line")" = "ok present"
check "a layer in the store is not fetched" test ! -s "$tmp/reg.log"
rec1=$root/layer-refs/$(field 0 4)
use() { awk '/^last-use /{print $2}' "$rec1"; }
u0=$(use)
ask "$line" >/dev/null
check "a layer used in the last day is not written again" test "$(use)" = "$u0"
old=$(( $(date +%s) - 90000 ))
sed -i "s/^last-use .*/last-use $old/" "$rec1"
grep -v '^last-use ' "$rec1" >"$tmp/rec1.rest"
check "a day-old layer is answered ok present" test "$(ask "$line")" = "ok present"
check "a day-old layer's last use is refreshed (gc cannot take it before the node holds it)" test "$(use)" -ge $(( $(date +%s) - 60 ))
check "the refresh keeps the rest of the record" diff "$tmp/rec1.rest" <(grep -v '^last-use ' "$rec1")
check "no layer lock left after the refresh" test -z "$(ls -A "$root/layer-locks")"

echo "== a layer that is not the image's"
check "a chain ID that is not one of the image's" \
  test "$(ask "ask docker.io library/busybox $m0 $blob1 sha256:$(printf '0%.0s' $(seq 64))\\n")" = "no the image has no such layer"

echo "== a manifest the registry does not have"
r=$(ask "ask docker.io library/busybox sha256:$(printf '1%.0s' $(seq 64)) $blob1 sha256:$(printf '2%.0s' $(seq 64))\\n")
echo "$r"
check "a missing manifest is answered no" grep -q '^no .' <<<"$r"

echo "== the cap"
printf '2' >"$tmp/delay"
asks=()
for n in 1 2 3 4 5; do
  ask "ask docker.io library/busybox $(field "$n" 1) $(field "$n" 5) $(field "$n" 2)\\n" >"$tmp/c.$n" &
  asks+=($!)
  sleep 0.2
done
wait "${asks[@]}"
rm -f "$tmp/delay"
cat "$tmp"/c.[1-5]
check "four images fill at once" test "$(cat "$tmp"/c.[1-5] | grep -cx 'ok published')" = 4
check "the fifth is answered busy" test "$(cat "$tmp"/c.[1-5] | grep -cx 'no the filler is busy')" = 1

echo "== the daemon's log"
cat "$tmp/serve.log"
check "the filler logs each answer" grep -q "^vk8s layers serve: $chain1 of docker.io/library/busybox@$m0: ok present" "$tmp/serve.log"
# Per-phase times (W7, Srv.phases.line.v2 and Srv.fill.line.v2).
ph='fetch [0-9]+ ms, decompress [0-9]+ ms, unpack [0-9]+ ms, fsync [0-9]+ ms, rename [0-9]+ ms'
for c in "$chain0" "$chain1"; do
  check "the filler logs the phases of $c" grep -Eq "^vk8s layers: $c published in [0-9]+ ms: $ph\$" "$tmp/serve.log"
done
check "the filler logs the image's fill, its phases summed" \
  grep -Eq "^vk8s layers serve: docker.io/library/busybox@$m0: 2 layers in [0-9]+ ms; summed over its layers: $ph\$" "$tmp/serve.log"
# The registry waited 2 s before each blob of the four images of the cap.
slow=$(grep -E "^vk8s layers: sha256:[0-9a-f]{64} published in [0-9]+ ms: $ph\$" "$tmp/serve.log" |
  sed -E 's/.*: fetch ([0-9]+) ms,.*/\1/' | awk '$1 >= 2000' | wc -l | tr -d ' ')
check "four layers fetched from the slow registry log fetch >= 2000 ms (got $slow)" test "$slow" = 4

echo "== through the image cache"
# Every fill above ran with no image cache: the filler pinged it, got no
# answer, and went to the registry with a token got ahead. Now the image
# cache runs (tests/cache_mirror_echo.bend, as `vk8s cache serve`: the
# mirrors on 127.0.0.1:15001-15004, the store at ROOT/cache/store where
# vk8s keeps it, VK8S_UPSTREAM the same stub). A fill pings it and asks
# it first, over plain HTTP (host/layers/fill.bend, Lf.fill.port.v4).
VK8S_UPSTREAM="https://127.0.0.1:$sport" SSL_CERT_FILE="$tmp/ca.pem" \
  "$tmp/mecho" serve "$root/cache/store" >"$tmp/mirror.log" 2>&1 &
pids+=($!)
ok=0
for _ in $(seq 100); do
  if up 15001 && up 15004; then ok=1; break; fi
  sleep 0.1
done
check "the image cache listens" test "$ok" = 1
cbase=http://127.0.0.1:15001/v2/library/busybox
cget() { # cget KIND/DIGEST OUT: a node's GET through the cache; prints the status
  curl -s -o "$2" -w '%{http_code}' "$cbase/$1?ns=docker.io"
}
sha() { # sha FILE: its hex SHA-256
  if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
cpath() { # cpath DIGEST: where the cache's store keeps it
  printf '%s' "$root/cache/store/docker.io/blobs/sha256/${1:7:2}/${1#sha256:}"
}

# Cold-pull state 4 (the cache warm, the store cold): a node pulled img6
# through the cache (manifest, config and layer, by digest). The filler
# then fills img6 and the registry is asked nothing.
m6=$(field 6 1); b6=$(field 6 5); c6=$(field 6 6)
r=$(cget "manifests/$m6" "$tmp/n6m")$(cget "blobs/$c6" "$tmp/n6c")$(cget "blobs/$b6" "$tmp/n6b")
check "a node pulls img6 through the cache ($r)" test "$r" = 200200200
: >"$tmp/reg.log"
r=$(ask "ask docker.io library/busybox $m6 $b6 $(field 6 2)\\n")
check "a fill of an image the cache holds: ok published ($r)" test "$r" = "ok published"
check "a fill of an image the cache holds asks the registry nothing" test ! -s "$tmp/reg.log"
check "its layer is in the store" test -s "$root/layers/$(field 6 3).sqfs"
check "the filler logs that it goes through the cache" \
  grep -q '^vk8s layers: docker.io/library/busybox: via the image cache at http://127.0.0.1:15001 ' "$tmp/serve.log"
check "the cache keeps its blob; the filler linked it, and its link went with the automatic drop" \
  test "$(stat -c %h "$(cpath "$b6")" 2>/dev/null)" = 1
check "and no copy of it is left in ROOT/oci" test -z "$(find "$root/oci" -type f -name "${b6#sha256:}*" 2>/dev/null)"

# Cold-pull state 3 (all cold): a node pulls img7's layer through the
# cache while the registry is slow, and the filler fills img7 meanwhile.
# Each object is fetched from the registry once (two lines each in the
# stub's log: the 401, then the cache's request with its token), and the
# filler sends the registry nothing of its own (no ping of /v2/).
m7=$(field 7 1); b7=$(field 7 5); c7=$(field 7 6)
: >"$tmp/reg.log"
printf '2' >"$tmp/delay"
cget "blobs/$b7" "$tmp/n7b" >"$tmp/n7.st" &
np=$!
sleep 0.3
r=$(ask "ask docker.io library/busybox $m7 $b7 $(field 7 2)\\n")
wait "$np"
rm -f "$tmp/delay"
cat "$tmp/reg.log"
check "a cold fill beside a node's pull: ok published ($r)" test "$r" = "ok published"
check "the node got the layer whole" test "$(cat "$tmp/n7.st") sha256:$(sha "$tmp/n7b")" = "200 $b7"
for d in "$m7" "$c7" "$b7"; do
  check "one registry fetch of $d" test "$(grep -c "/$d\$" "$tmp/reg.log")" = 2
done
check "no request of the filler's own to the registry" test "$(grep -cx '/v2/' "$tmp/reg.log")" = 0
check "img7's layer is in the store" test -s "$root/layers/$(field 7 3).sqfs"

# What the cache does not have and cannot get: the filler asks the
# registry itself, and answers no.
: >"$tmp/reg.log"
r=$(ask "ask docker.io library/busybox sha256:$(printf '3%.0s' $(seq 64)) $b7 sha256:$(printf '4%.0s' $(seq 64))\\n")
check "a manifest neither has: no ($r)" grep -q '^no .' <<<"$r"
check "the cache asked the registry, then the filler did ($(grep -c manifests "$tmp/reg.log") manifest requests)" \
  test "$(grep -c "/manifests/sha256:3333" "$tmp/reg.log")" = 4
check "the filler logs that it went to the registry" \
  grep -q '^vk8s layers: the manifest sha256:3333.*: from the registry (the image cache answered HTTP 404)$' "$tmp/serve.log"

echo "== the image cache's log"
cat "$tmp/mirror.log"

echo "== $fails failed"
[ "$fails" = 0 ]
