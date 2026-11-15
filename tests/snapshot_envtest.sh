#!/usr/bin/env bash
# The open-format snapshot round trip on Linux, with the host code of
# `vk8s snapshot create --format open` and `vk8s restore` (host/
# snapshot_open.bend, built natively in tests/snapshot_open_build.bend) and
# the guest's command lines (src/guest/plan.bend), against the store tools
# of tests/snapshot_store_spike.sh (etcd v3.5.21, k3s-io/kine v0.17.5,
# pinned by SHA-256, same download cache).
#
# The guest's paths (/var/lib/vcluster, /var/lib/vk8s-host) live under a
# scratch root: the program prints the Run steps of Plan.snapshot_export
# and Plan.restore_store, this script moves /var/lib/ under the root and
# runs busybox's applets directly.
#
# For embedded etcd and for kine on SQLite:
#   1. a store gets 2100 keys (three kine pages of 1000), a binary value, a
#      ConfigMap-like protobuf value, a namespace's kube-root-ca.crt and a
#      vcluster mapping, through vcluster's txn create;
#   2. the export steps write share/snapshot/export (snapshot-export);
#   3. Open.export writes the archive (gzip -3, mode 0600); tar -tzPf shows
#      /vcluster/snapshot/db, or /vcluster/snapshot/revision first and one
#      entry per key; the archive's bytes are the database, or the revision
#      and every key with the same bytes;
#   4. Open.fmt_file finds the open format, Open.place writes the db or
#      puts file and the marker;
#   5. the restore steps run into a fresh store, which then serves every
#      key with the same bytes (kine: minus kube-root-ca.crt and the
#      mappings, which a restore into a new vCluster skips; kine's own
#      /registry/health is the new store's).
# Also: a VM-format archive (metadata.json first) and another first entry.
#
# Needs: bend, clang, curl, openssl, perl, python3, Linux (amd64 or arm64).
# Usage: tests/snapshot_envtest.sh   (ENVTEST_CACHE the download
# directory; KEEP=1 keeps the work directory; ENVTEST_TIMEOUT the bound of
# the whole run in seconds, default 900)
set -uo pipefail
cd "$(dirname "$0")/.."
export LC_ALL=C

if [ -z "${SNAPSHOT_ENVTEST_BOUNDED:-}" ]; then
  SNAPSHOT_ENVTEST_BOUNDED=1 timeout -k 30 "${ENVTEST_TIMEOUT:-900}" "tests/$(basename "$0")" "$@"
  rc=$?
  [ $rc -eq 124 ] && echo "FAIL snapshot envtest timed out after ${ENVTEST_TIMEOUT:-900}s"
  exit $rc
fi

ETCD=v3.5.21
KINE=v0.17.5
case $(uname -m) in
  x86_64)
    arch=amd64
    ETCD_SHA=adddda4b06718e68671ffabff2f8cee48488ba61ad82900e639d108f2148501c
    KINE_SHA=fc6780ff09301d3e7440c47988d8abbbd5fa380d81ce47ef69d155c82366fd48 ;;
  aarch64 | arm64)
    arch=arm64
    ETCD_SHA=95bf6918623a097c0385b96f139d90248614485e781ec9bee4768dbb6c79c53f
    KINE_SHA=c825fc4230a31db051928b8d040c753b69b56f49d2f4cb598992e09dce65a3e8 ;;
  *) echo "unsupported architecture $(uname -m)"; exit 1 ;;
esac
cache=${ENVTEST_CACHE:-$HOME/.cache/vk8s-envtest/snapshot-$ETCD-kine-$KINE-$arch}
work=$(mktemp -d)
# The guest's root: /var/lib/vcluster and /var/lib/vk8s-host.
root=$work/r
gbin=$root/var/lib/vcluster/bin
gpki=$root/var/lib/vcluster/pki
share=$root/var/lib/vk8s-host
sock=$root/var/lib/vcluster/kine.sock
data=$work/data
mkdir -p "$gbin" "$gpki/etcd" "$share" "$data" "$work/build"
pids=()

cleanup() {
  local p i alive
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done
  for ((i = 0; i < 20; i++)); do
    alive=0
    for p in "${pids[@]}"; do kill -0 "$p" 2>/dev/null && alive=1; done
    [ $alive = 0 ] && break
    sleep 0.5
  done
  for p in "${pids[@]}"; do kill -KILL "$p" 2>/dev/null; done
  wait 2>/dev/null
  if [ "${KEEP:-}" = 1 ]; then echo "work directory: $work"; else rm -rf "$work"; fi
}
trap cleanup EXIT
trap 'echo "FAIL interrupted"; exit 124' TERM INT

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
info() { echo "INFO $*"; }
check() {
  local name=$1; shift
  if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi
}
eventually() {
  local name=$1 secs=$2; shift 2
  local i
  for ((i = 0; i < secs * 2; i++)); do
    if "$@" >/dev/null 2>&1; then pass "$name"; return 0; fi
    sleep 0.5
  done
  fail "$name"; return 1
}
eq() {
  if [ "$2" = "$3" ]; then pass "$1 ($2)"; else fail "$1: got '$2', want '$3'"; fi
}
stop() {
  local i
  kill "$1" 2>/dev/null
  for ((i = 0; i < 20; i++)); do kill -0 "$1" 2>/dev/null || break; sleep 0.5; done
  kill -KILL "$1" 2>/dev/null
  wait "$1" 2>/dev/null
  return 0
}
mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

PY='
import base64, json, sys, tarfile
mode, args = sys.argv[1], sys.argv[2:]
def load(p):
    with open(p) as f:
        return json.load(f)
def b64(s):
    return base64.b64encode(s).decode()
if mode == "rev":
    print(load(args[0])["header"]["revision"])
elif mode == "more":
    print(1 if load(args[0]).get("more") else 0)
elif mode == "nkvs":
    print(len(load(args[0]).get("kvs", [])))
elif mode == "lastkey":
    print(base64.b64decode(load(args[0])["kvs"][-1]["key"]).decode())
elif mode == "status_rev":
    print(load(args[0])["revision"])
elif mode == "page":
    prev = args[1] if len(args) > 1 else ""
    for kv in load(args[0]).get("kvs", []):
        if prev and base64.b64decode(kv["key"]).decode() == prev:
            continue
        print(kv["key"], kv.get("value", ""))
elif mode == "succeeded":
    n = 0
    with open(args[0]) as f:
        for line in f:
            line = line.strip()
            if line and json.loads(line).get("succeeded"):
                n += 1
    print(n)
elif mode == "tarkv":
    # tarkv ARCHIVE: its entries but the revision, as "key value" (base64)
    with tarfile.open(args[0], "r:gz") as t:
        for m in t:
            name = m.name if m.name.startswith("/") else "/" + m.name
            if name == "/vcluster/snapshot/revision":
                continue
            print(b64(name.encode()), b64(t.extractfile(m).read()))
elif mode == "target":
    # target ARCHIVE NAME OUT: the bytes of entry NAME
    with tarfile.open(args[0], "r:gz") as t:
        for m in t:
            name = m.name if m.name.startswith("/") else "/" + m.name
            if name == args[1]:
                with open(args[2], "wb") as f:
                    f.write(t.extractfile(m).read())
elif mode == "newvc":
    # stdin "key value" lines without what a restore into a new vCluster
    # skips (restoreKeyValueSnapshot: mappings, <ns>/kube-root-ca.crt)
    for line in sys.stdin:
        k = base64.b64decode(line.split(" ")[0]).decode()
        p = k.split("/")
        if k.startswith("/vcluster/mappings/") or (len(p) == 5 and p[2] == "configmaps" and p[4] == "kube-root-ca.crt"):
            continue
        sys.stdout.write(line)
'
json() { python3 -I -c "$PY" "$@"; }

echo "== build tests/snapshot_open_build.bend"
prog=$work/build/snapshot_open_build
if ! bend tests/snapshot_open_build.bend -o "$prog" >"$work/build.log" 2>&1; then
  cat "$work/build.log"; echo "FAIL build tests/snapshot_open_build.bend"; exit 1
fi
pass "build"
out=$("$prog" 2>&1)
echo "$out" | grep '^PASS\|^FAIL'
fails=$((fails + $(grep -c '^FAIL' <<<"$out")))

echo "== binaries (etcd $ETCD, kine $KINE, $arch)"
mkdir -p "$cache"
get() {
  if [ ! -s "$cache/$2" ]; then
    curl --proto '=https' --tlsv1.2 -fsSL --retry 3 -o "$cache/$2.part" "$1" && mv "$cache/$2.part" "$cache/$2" || return 1
  fi
  echo "$3  $cache/$2" | sha256sum -c --status - || { echo "SHA-256 mismatch: $2"; rm -f "$cache/$2"; return 1; }
}
get "https://github.com/etcd-io/etcd/releases/download/$ETCD/etcd-$ETCD-linux-$arch.tar.gz" etcd.tgz "$ETCD_SHA" \
  || { echo "FAIL download etcd"; exit 1; }
get "https://github.com/k3s-io/kine/releases/download/$KINE/kine-$arch" kine "$KINE_SHA" \
  || { echo "FAIL download kine"; exit 1; }
tar -xzf "$cache/etcd.tgz" -C "$cache" --strip-components=1 \
  "etcd-$ETCD-linux-$arch/etcd" "etcd-$ETCD-linux-$arch/etcdctl" "etcd-$ETCD-linux-$arch/etcdutl"
chmod +x "$cache/etcd" "$cache/etcdctl" "$cache/etcdutl" "$cache/kine"
ln -s "$cache/etcdctl" "$gbin/etcdctl"
ln -s "$cache/etcdutl" "$gbin/etcdutl"
pass "binaries"

echo "== certificates (the guest's etcd CA and apiserver-etcd-client pair)"
pki=$work/pki
mkdir -p "$pki"
{
  openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=etcd-ca \
    -keyout "$pki/ca.key" -out "$pki/ca.crt"
  printf 'subjectAltName=IP:127.0.0.1,DNS:localhost\nextendedKeyUsage=serverAuth,clientAuth\n' > "$pki/ext"
  for n in server peer client; do
    openssl req -newkey rsa:2048 -nodes -subj "/CN=$n" -keyout "$pki/$n.key" -out "$pki/$n.csr"
    openssl x509 -req -in "$pki/$n.csr" -CA "$pki/ca.crt" -CAkey "$pki/ca.key" -CAcreateserial \
      -days 1 -extfile "$pki/ext" -out "$pki/$n.crt"
  done
} >"$work/openssl.log" 2>&1 || { cat "$work/openssl.log"; echo "FAIL certificates"; exit 1; }
cp "$pki/ca.crt" "$gpki/etcd/ca.crt"
cp "$pki/client.crt" "$gpki/apiserver-etcd-client.crt"
cp "$pki/client.key" "$gpki/apiserver-etcd-client.key"
pass "certificates"

ctl_etcd() {
  "$cache/etcdctl" --endpoints https://127.0.0.1:2379 --cacert "$pki/ca.crt" --cert "$pki/client.crt" --key "$pki/client.key" \
    --command-timeout 30s "$@"
}
ctl_kine() { "$cache/etcdctl" --endpoints "unix://$sock" --command-timeout 30s "$@"; }

# steps export|restore etcd|kine NAME: run the guest's Run steps, with
# /var/lib/ under the scratch root and busybox's applets run directly.
steps() {
  local line
  "$prog" plan "$@" > "$work/steps-$1-$2" || return 1
  [ -s "$work/steps-$1-$2" ] || return 1
  while IFS= read -r line; do
    line=${line//"/var/lib/"/"$root/var/lib/"}
    case $line in "'/bin/busybox' "*) line=${line#"'/bin/busybox' "} ;; esac
    eval "$line" || { echo "step failed: $line" | head -c 400; echo; return 1; }
  done < "$work/steps-$1-$2"
}

N=2100
# seed CTL LABEL: N keys and the rest through vcluster's txn create.
seed() {
  local ctl=$1 l=$2
  # ctl is a shell function: export it (and what it reads) to bash -c.
  export -f "$ctl"; export cache pki sock
  seq -f '%04g' 1 "$N" | xargs -P 8 -I '{}' bash -c \
    'printf "mod(\"/registry/rt/k{}\") = \"0\"\n\nput /registry/rt/k{} v-{}\n\n\n" | "$0" txn -w json' "$ctl" \
    > "$work/$l-bulk.json" 2> "$work/$l-bulk.err"
  eq "$l: $N txn creates succeed" "$(json succeeded "$work/$l-bulk.json")" "$N"
  {
    printf '%s\n' 'mod("/registry/rt/binary") = "0"' '' 'put /registry/rt/binary "hello world\n\x01\xff"' '' ''
    # A ConfigMap as the API server stores it: the k8s\0 protobuf envelope.
    printf '%s\n' 'mod("/registry/configmaps/default/app-config") = "0"' '' \
      'put /registry/configmaps/default/app-config "k8s\x00\n\x0f\n\x02v1\x12\tConfigMap\x12A\n\x1f\n\napp-config\x12\x00\x1a\x07default\"\x00*\x00\x12\x1e\n\x08game.ini\x12\x12lives=3 \"quoted\"\n\xc3\xa9\x1a\x00\"\x00"' '' ''
    printf '%s\n' 'mod("/registry/configmaps/default/kube-root-ca.crt") = "0"' '' 'put /registry/configmaps/default/kube-root-ca.crt old-ca' '' ''
    printf '%s\n' 'mod("/vcluster/mappings/v1/configmaps/x") = "0"' '' 'put /vcluster/mappings/v1/configmaps/x {}' '' ''
  } > "$work/$l-more.txn"
  : > "$work/$l-more.json"
  while IFS= read -r a && IFS= read -r b && IFS= read -r c && IFS= read -r d && IFS= read -r e; do
    printf '%s\n' "$a" "$b" "$c" "$d" "$e" | "$ctl" txn -w json >> "$work/$l-more.json" 2>&1
  done < "$work/$l-more.txn"
  eq "$l: binary, ConfigMap, kube-root-ca.crt and mapping creates succeed" "$(json succeeded "$work/$l-more.json")" 4
}

# dump CTL LABEL OUT: every key at one revision, "key value" (base64), sorted.
dump() {
  local ctl=$1 l=$2 out=$3 start=/ prev="" rev="" n=0
  : > "$out.unsorted"
  while :; do
    n=$((n + 1))
    if [ $n = 1 ]; then
      "$ctl" get "$start" 0 --limit 1000 -w json > "$work/$l-p$n.json" 2>&1 || { fail "$l: page $n"; return 1; }
      rev=$(json rev "$work/$l-p$n.json")
    else
      "$ctl" get "$start" 0 --limit 1000 --rev "$rev" -w json > "$work/$l-p$n.json" 2>&1 || { fail "$l: page $n"; return 1; }
    fi
    json page "$work/$l-p$n.json" "$prev" >> "$out.unsorted"
    [ "$(json nkvs "$work/$l-p$n.json")" = 0 ] && break
    [ "$(json more "$work/$l-p$n.json")" = 1 ] || break
    prev=$(json lastkey "$work/$l-p$n.json")
    start=$prev
    [ $n -lt 50 ] || { fail "$l: paging does not end"; return 1; }
  done
  sort "$out.unsorted" > "$out"
}

same() { if cmp -s "$1" "$2"; then echo same; else diff "$1" "$2" | head -10 >&2; echo differs; fi; }

etcd_start() { # etcd_start NAME DATA_DIR: Plan.etcd_args NAME
  "$cache/etcd" --name "$1" --data-dir "$2" \
    --listen-client-urls https://127.0.0.1:2379 --advertise-client-urls https://127.0.0.1:2379 \
    --listen-peer-urls https://127.0.0.1:2380 --initial-advertise-peer-urls https://127.0.0.1:2380 \
    --initial-cluster "$1=https://127.0.0.1:2380" --initial-cluster-token vcluster \
    --initial-cluster-state new --listen-metrics-urls http://127.0.0.1:2381 \
    --heartbeat-interval 500 --election-timeout 5000 --snapshot-count 10000 \
    --client-cert-auth=true --cert-file "$pki/server.crt" --key-file "$pki/server.key" \
    --trusted-ca-file "$pki/ca.crt" --peer-client-cert-auth=true \
    --peer-cert-file "$pki/peer.crt" --peer-key-file "$pki/peer.key" \
    --peer-trusted-ca-file "$pki/ca.crt" > "$work/etcd-$1.log" 2>&1 &
  pids+=($!)
  etcd_pid=$!
}

kine_start() { # kine_start DB: Plan.kine_args on a SQLite file
  rm -f "$sock"
  "$cache/kine" --endpoint "sqlite://$1?_journal=WAL&cache=shared&_busy_timeout=30000&_txlock=immediate" \
    --metrics-bind-address 127.0.0.1:2381 --listen-address "unix://$sock" > "$work/kine-$(basename "$1").log" 2>&1 &
  pids+=($!)
  kine_pid=$!
}

# archive LABEL ARCHIVE: the host side of both formats' checks.
archive_common() {
  local l=$1 a=$2
  eq "$l: the archive has mode 600" "$(mode "$a")" 600
  check "$l: the archive is gzip" gzip -t "$a"
  gzip -dc "$a" > "$work/$l.tar"
  eq "$l: Open.fmt_file finds the open format" "$("$prog" fmt "$work/$l.tar")" open
}

echo "== 1. embedded etcd"
etcd_start demo "$data/demo-etcd"
eventually "etcd demo serves" 60 ctl_etcd endpoint health || { tail -20 "$work/etcd-demo.log"; exit 1; }
seed ctl_etcd etcd
dump ctl_etcd etcd-before "$work/etcd-before"
check "etcd: the export steps (Plan.snapshot_export, etcdctl snapshot save)" steps export etcd demo
check "etcd: export/db is there, export.tmp is gone" test -s "$share/snapshot/export/db" -a ! -e "$share/snapshot/export.tmp"
"$cache/etcdutl" snapshot status "$share/snapshot/export/db" -w json > "$work/status.json" 2>"$work/status.err"
old_rev=$(json status_rev "$work/status.json")
mkdir -p "$work/stage-etcd"
eq "etcd: Open.export" "$("$prog" export etcd "$share/snapshot/export" "$work/stage-etcd" "$work/etcd.tar.gz" 2>&1)" "PASS export"
archive_common etcd "$work/etcd.tar.gz"
eq "etcd: tar -tzPf lists /vcluster/snapshot/db alone" "$(tar -tzPf "$work/etcd.tar.gz" | tr '\n' ' ')" "/vcluster/snapshot/db "
json target "$work/etcd.tar.gz" /vcluster/snapshot/db "$work/etcd-db-from-archive"
check "etcd: the db entry is the etcdctl snapshot save file, byte for byte" cmp "$work/etcd-db-from-archive" "$share/snapshot/export/db"
rm -rf "$share/snapshot/export"
eq "etcd: Open.place finds an etcd archive" "$("$prog" place "$work/etcd.tar" "$work/place-etcd" 2>&1)" etcd
check "etcd: the db file is the database" cmp "$work/place-etcd/db" "$work/etcd-db-from-archive"
check "etcd: the restore marker is there" test -s "$work/place-etcd/restore"
stop "$etcd_pid"
rm -rf "$share/snapshot" && cp -a "$work/place-etcd" "$share/snapshot"
check "etcd: the restore steps (Plan.restore_store, etcdutl snapshot restore as demo2)" steps restore etcd demo2
check "etcd: the restore steps remove the marker and the db" test ! -e "$share/snapshot/restore" -a ! -e "$share/snapshot/db"
etcd_start demo2 "$root/var/lib/vcluster/etcd"
if eventually "restored etcd demo2 serves" 60 ctl_etcd endpoint health; then
  dump ctl_etcd etcd-after "$work/etcd-after"
  eq "etcd: the restored store has every key with the same bytes" "$(same "$work/etcd-before" "$work/etcd-after")" same
  eq "etcd: key count" "$(wc -l < "$work/etcd-after" | tr -d ' ')" "$((N + 4))"
  ctl_etcd get / --prefix --keys-only --limit 1 -w json > "$work/etcd-after-rev.json" 2>&1
  eq "etcd: the restored revision is the snapshot's plus 1000" "$(json rev "$work/etcd-after-rev.json")" "$((old_rev + 1000))"
  info "etcd: the restored store keeps kube-root-ca.crt and the mappings (vcluster's postRestoreSnapshotDataMutation is not run yet)"
else
  tail -30 "$work/etcd-demo2.log"
fi
stop "$etcd_pid"

echo "== 2. kine on SQLite"
mkdir -p "$data/kine"
kine_start "$data/kine/source.db"
if ! eventually "kine listens" 30 test -S "$sock"; then tail -30 "$work/kine-source.db.log"; exit 1; fi
eventually "etcdctl reaches kine" 30 ctl_kine get /registry/health
seed ctl_kine kine
dump ctl_kine kine-before "$work/kine-before"
check "kine: the export steps (Plan.snapshot_export, the paging script)" steps export kine demo
pages=$(cat "$share/snapshot/export/pages" 2>/dev/null || echo 0)
if [ "$pages" -ge 3 ]; then pass "kine: the dump has $pages pages"; else fail "kine: the dump has $pages pages, want 3 or more"; fi
mkdir -p "$work/stage-kine"
eq "kine: Open.export" "$("$prog" export kine "$share/snapshot/export" "$work/stage-kine" "$work/kine.tar.gz" 2>&1)" "PASS export"
archive_common kine "$work/kine.tar.gz"
tar -tzPf "$work/kine.tar.gz" > "$work/kine-names"
eq "kine: tar -tzPf lists /vcluster/snapshot/revision first" "$(head -1 "$work/kine-names")" /vcluster/snapshot/revision
eq "kine: one entry per key, and the revision" "$(wc -l < "$work/kine-names" | tr -d ' ')" "$(($(wc -l < "$work/kine-before") + 1))"
check "kine: tar -tzPf lists the ConfigMap" grep -qx /registry/configmaps/default/app-config "$work/kine-names"
json target "$work/kine.tar.gz" /vcluster/snapshot/revision "$work/kine-rev"
eq "kine: the revision entry is the count-only get's revision" "$(cat "$work/kine-rev")" "$(tr -d '\n' < "$share/snapshot/export/revision")"
json tarkv "$work/kine.tar.gz" | sort > "$work/kine-archive"
eq "kine: the archive's records are every key with the same bytes" "$(same "$work/kine-before" "$work/kine-archive")" same
rm -rf "$share/snapshot/export"
eq "kine: Open.place finds a key/value archive" "$("$prog" place "$work/kine.tar" "$work/place-kine" 2>&1)" kine
check "kine: the puts file is there" test -s "$work/place-kine/puts"
check "kine: the restore marker is there" test -s "$work/place-kine/restore"
check "kine: the puts file leaves out kine's own /registry/health" sh -c "! grep -qx /registry/health '$work/place-kine/puts'"
stop "$kine_pid"
kine_start "$data/kine/restored.db"
if ! eventually "a fresh kine listens" 30 test -S "$sock"; then tail -30 "$work/kine-restored.db.log"; exit 1; fi
eventually "etcdctl reaches the fresh kine" 30 ctl_kine get /registry/health
rm -rf "$share/snapshot" && cp -a "$work/place-kine" "$share/snapshot"
if steps restore kine demo2 > "$work/kine-restore.out" 2>&1; then pass "kine: the restore steps (Plan.restore_store, the puts script)"
else fail "kine: the restore steps"; tail -20 "$work/kine-restore.out"; fi
grep -q 'refused compaction' "$work/kine-restore.out" && info "kine: $(grep 'refused compaction' "$work/kine-restore.out")"
check "kine: the restore steps remove the marker and the puts" test ! -e "$share/snapshot/restore" -a ! -e "$share/snapshot/puts"
dump ctl_kine kine-after "$work/kine-after"
json newvc < "$work/kine-before" > "$work/kine-want"
eq "kine: the restored store has every key with the same bytes, minus what a new vCluster skips" "$(same "$work/kine-want" "$work/kine-after")" same
eq "kine: key count" "$(wc -l < "$work/kine-after" | tr -d ' ')" "$((N + 3))"
stop "$kine_pid"

echo "== 3. the format of other archives"
mkdir -p "$work/vm"
printf '{}\n' > "$work/vm/metadata.json"
printf 'NAME=a\n' > "$work/vm/cluster.env"
printf 'disk' > "$work/vm/data.img"
tar -cf "$work/vm.tar" -C "$work/vm" metadata.json cluster.env data.img
eq "a VM snapshot (metadata.json first)" "$("$prog" fmt "$work/vm.tar")" vm
tar -cf "$work/other.tar" -C "$work/vm" data.img metadata.json
eq "another first entry" "$("$prog" fmt "$work/other.tar" | cut -c1-36)" "bad: the snapshot's first entry is \""

echo
if [ $fails = 0 ]; then echo "PASS snapshot envtest"; else echo "FAIL snapshot envtest: $fails failures"; exit 1; fi
