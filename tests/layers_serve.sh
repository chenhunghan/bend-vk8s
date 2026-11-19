#!/usr/bin/env bash
# The layer filler daemon (host/layers/serve.bend, `vk8s layers serve`)
# end to end on Linux, no VM. It builds tests/layer_serve_echo.bend
# natively, writes small OCI images with Python (gzip layers, a config,
# an image manifest), serves them from a stub registry on 127.0.0.1:15001
# (the image cache's docker.io port, Plan.mirrors), runs the filler on a
# free port, and asks it with bash's /dev/tcp as a node's snapshotter
# would (src/layers/ask.bend's line protocol):
#
# - a line that is not an ask, an ask for a registry the cache does not
#   serve, and a line over 512 bytes are answered "no not a valid ask";
# - three asks at once for one layer: one fill (the manifest fetched
#   once), all three answered "ok published", both layers of the image
#   in the store, their blobs not kept in ROOT/oci;
# - the same ask again: "ok present", and the registry is not asked;
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
# Needs bend, clang, python3, sha256sum (or shasum), and the ports 15001
# and LAYERS_SERVE_PORT (default 32123) free. Prints PASS/FAIL lines;
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

echo "== build"
if ! bend tests/layer_serve_echo.bend -o "$tmp/secho" >"$tmp/build.log" 2>&1; then
  cat "$tmp/build.log"
  echo "FAIL build tests/layer_serve_echo.bend"
  exit 1
fi
pass "build"

echo "== images"
# Six images of library/busybox: img0 has two layers, img1..img5 one each.
# For each: reg/<digest> files (manifest, config, layers), and a line
# "manifest-digest chain-of-last-layer hex-of-each-chain..." in imgN.
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

for n in range(6):
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
    open(f"{tmp}/img{n}", "w").write(" ".join([md, chains[0]] + [c[7:] for c in chains] + ["blobs"] + blobs) + "\n")
PY

echo "== stub registry"
# Serves /v2/library/busybox/{manifests,blobs}/<digest> from reg/, logs
# each path to reg.log, and waits $tmp/delay seconds (when that file
# exists) before each blob.
cat >"$tmp/registry.py" <<'PY'
import http.server, os, sys, time
tmp = sys.argv[1]

class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a):
        pass
    def do_GET(self):
        with open(f"{tmp}/reg.log", "a") as f:
            f.write(self.path + "\n")
        parts = self.path.split("/")
        body = None
        if len(parts) == 6 and parts[:4] == ["", "v2", "library", "busybox"] and parts[4] in ("manifests", "blobs"):
            p = f"{tmp}/reg/{parts[5]}"
            if "/" not in parts[5] and os.path.isfile(p):
                body = open(p, "rb").read()
        if parts[4:5] == ["blobs"] and os.path.exists(f"{tmp}/delay"):
            time.sleep(float(open(f"{tmp}/delay").read()))
        if body is None:
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.send_header("Connection", "close")
            self.end_headers()
            return
        self.send_response(200)
        kind = "application/vnd.oci.image.manifest.v1+json" if parts[4] == "manifests" else "application/octet-stream"
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

http.server.ThreadingHTTPServer(("127.0.0.1", 15001), H).serve_forever()
PY
python3 -I "$tmp/registry.py" "$tmp" >"$tmp/registry.err" 2>&1 &
pids+=($!)

root="$tmp/root"
mkdir -p "$root"
"$tmp/secho" serve "$root" "$port" amd64 >"$tmp/serve.log" 2>&1 &
pids+=($!)

up() { # up PORT: something listens on 127.0.0.1:PORT
  (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}
ok=0
for _ in $(seq 100); do
  if up 15001 && up "$port"; then ok=1; break; fi
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

echo "== three asks at once for one layer"
: >"$tmp/reg.log"
line="ask docker.io library/busybox $m0 $blob1 $chain1\\n"
asks=()
for i in 1 2 3; do ask "$line" >"$tmp/a.$i" & asks+=($!); done
wait "${asks[@]}"
cat "$tmp"/a.[123]
check "three asks at once are each answered ok published" test "$(cat "$tmp"/a.[123] | grep -cx 'ok published')" = 3
check "one fill for the three asks (the manifest fetched once)" test "$(grep -c "/manifests/$m0" "$tmp/reg.log")" = 1
check "the asked layer is in the store" test "$(cat "$root/layers/$(field 0 4)/etc/second")" = "second layer"
check "the image's other layer is in the store" test "$(cat "$root/layers/$(field 0 3)/etc/img0")" = "image 0"
check "the records of both layers" test -f "$root/layer-refs/$(field 0 3)" -a -f "$root/layer-refs/$(field 0 4)"
check "an automatic fill keeps no blob in ROOT/oci" test -z "$(find "$root/oci" -type f -name "${blob1#sha256:}*" 2>/dev/null)"
check "no layer lock left" test -z "$(ls -A "$root/layer-locks")"

echo "== the same ask again"
: >"$tmp/reg.log"
check "a layer in the store is answered ok present" test "$(ask "$line")" = "ok present"
check "a layer in the store is not fetched" test ! -s "$tmp/reg.log"

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

echo "== $fails failed"
[ "$fails" = 0 ]
