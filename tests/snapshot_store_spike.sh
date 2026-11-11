#!/usr/bin/env bash
# Spike for the open-format snapshot (docs/ref/snapshot-decisions.md):
# which store tools work on Linux, with the flags vk8s would use. No vk8s
# code runs here; the script drives the official etcd v3.5 tools and a
# k3s-io/kine release, both pinned by SHA-256.
#
# 1. Embedded etcd, started with src/guest/plan.bend's Plan.etcd_args
#    (--name <cluster>, TLS, client and peer on loopback:
#    https://127.0.0.1:2379 and https://127.0.0.1:2380, token "vcluster"):
#    - etcdctl txn creates keys (create-if-absent: mod("k") = "0");
#    - etcdctl snapshot save writes the bolt database; etcdutl snapshot
#      status reports the revision of the live store;
#    - etcdutl snapshot restore into a NEW name (--name demo2, its own
#      --initial-cluster demo2=https://127.0.0.1:2380, token vcluster)
#      with --bump-revision 1000 --mark-compacted, as vcluster's
#      restoreclient.go does (RevisionBump BumpRevision=1000 for a data
#      dir with no older revision, MarkCompacted true);
#    - etcd started on the restored data dir with demo2's plan flags
#      serves every key with the same bytes, has one member demo2 with
#      peer https://127.0.0.1:2380, reports revision old+1000, refuses a
#      read at the old revision (compacted) and accepts new creates.
# 2. kine on SQLite, started with Plan.kine_args (vk8s's default store:
#    the sqlite endpoint with vcluster's SQLiteParams, a unix socket):
#    - creates go through etcdctl txn mod("k") = "0" (vcluster
#      pkg/etcd/client.go Create); a second create of the same key fails;
#      the Update shape (mod = rev, put, else get) and the Delete shape
#      (get, del) work; plain `etcdctl del` and serializable reads are
#      refused (kine pkg/server/kv.go);
#    - a count-only get of "/" --prefix returns the count and revision
#      (vcluster currentRevision);
#    - etcdctl get <start> 0 --limit 1000 [--rev R] -w json pages through
#      kine (vcluster listStream) and returns every key once, with
#      base64 keys and values that decode to the bytes written.
#
# Needs: curl, openssl, python3, Linux (amd64 or arm64).
# Usage: tests/snapshot_store_spike.sh   (ENVTEST_CACHE the download
# directory; KEEP=1 keeps the work directory; ENVTEST_TIMEOUT the bound
# of the whole run in seconds, default 600)
set -uo pipefail
cd "$(dirname "$0")/.."
export LC_ALL=C

if [ -z "${SNAPSHOT_SPIKE_BOUNDED:-}" ]; then
  SNAPSHOT_SPIKE_BOUNDED=1 timeout -k 30 "${ENVTEST_TIMEOUT:-600}" "tests/$(basename "$0")" "$@"
  rc=$?
  [ $rc -eq 124 ] && echo "FAIL snapshot store spike timed out after ${ENVTEST_TIMEOUT:-600}s"
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
# Helper scripts live apart from downloaded binaries and store data.
bin=$work/bin
data=$work/data
mkdir -p "$bin" "$data"
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
# check NAME COMMAND...: COMMAND succeeds now
check() {
  local name=$1; shift
  if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi
}
# refuses NAME COMMAND...: COMMAND fails now
refuses() {
  local name=$1; shift
  if "$@" >"$work/refused.out" 2>&1; then fail "$name (accepted)"; else pass "$name: $(head -c 200 "$work/refused.out" | tr '\n' ' ')"; fi
}
# eventually NAME SECONDS COMMAND...: COMMAND succeeds within SECONDS
eventually() {
  local name=$1 secs=$2; shift 2
  local i
  for ((i = 0; i < secs * 2; i++)); do
    if "$@" >/dev/null 2>&1; then pass "$name"; return 0; fi
    sleep 0.5
  done
  fail "$name"; return 1
}
# eq NAME GOT WANT
eq() {
  if [ "$2" = "$3" ]; then pass "$1 ($2)"; else fail "$1: got '$2', want '$3'"; fi
}
# stop PID: SIGTERM, up to 10 seconds, then SIGKILL.
stop() {
  local i
  kill "$1" 2>/dev/null
  for ((i = 0; i < 20; i++)); do kill -0 "$1" 2>/dev/null || break; sleep 0.5; done
  kill -KILL "$1" 2>/dev/null
  wait "$1" 2>/dev/null
  return 0
}

# JSON helpers over etcdctl/etcdutl -w json output (python3 -I).
PY='
import base64, json, sys
mode, args = sys.argv[1], sys.argv[2:]
def load(p):
    with open(p) as f:
        return json.load(f)
def b64(s):
    return base64.b64encode(s).decode()
if mode == "rev":
    print(load(args[0])["header"]["revision"])
elif mode == "count":
    print(load(args[0]).get("count", 0))
elif mode == "more":
    print(1 if load(args[0]).get("more") else 0)
elif mode == "nkvs":
    print(len(load(args[0]).get("kvs", [])))
elif mode == "modrev":
    print(load(args[0])["kvs"][0]["mod_revision"])
elif mode == "value":
    print(base64.b64decode(load(args[0])["kvs"][0]["value"]).decode("latin-1"))
elif mode == "fields":
    # fields FILE NAME: a value of etcdctl -w fields ("Name" : value)
    for line in open(args[0]):
        k, sep, v = line.partition(" : ")
        if sep and k.strip().strip("\"") == args[1]:
            print(v.strip())
elif mode == "status_rev":
    print(load(args[0])["revision"])
elif mode == "lastkey":
    print(base64.b64decode(load(args[0])["kvs"][-1]["key"]).decode())
elif mode == "page":
    # page FILE PREV: the "key value" lines (base64) of a page, without
    # PREV (the inclusive start key repeated from the previous page).
    prev = args[1] if len(args) > 1 else ""
    for kv in load(args[0]).get("kvs", []):
        if prev and base64.b64decode(kv["key"]).decode() == prev:
            continue
        print(kv["key"], kv.get("value", ""))
elif mode == "succeeded":
    # one JSON object per line (txn -w json); count the succeeded ones
    n = 0
    with open(args[0]) as f:
        for line in f:
            line = line.strip()
            if line and json.loads(line).get("succeeded"):
                n += 1
    print(n)
elif mode == "members":
    for m in load(args[0])["members"]:
        print(m["name"], ",".join(m["peerURLs"]))
elif mode == "expected":
    # expected N: the seeded keys as "key value" lines (base64)
    n = int(args[0])
    rows = [("/registry/spike/k%04d" % i, b"v-%04d" % i) for i in range(1, n + 1)]
    rows.append(("/registry/spike/binary", b"hello world\n\x01\xff"))
    rows.append(("/registry/spike/upd", b"two"))
    for k, v in rows:
        print(b64(k.encode()), b64(v))
'
json() { python3 -I -c "$PY" "$@"; }

echo "== binaries (etcd $ETCD, kine $KINE, $arch)"
mkdir -p "$cache"
# get URL FILE SHA256: download once, check the pin every run
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
info "$("$cache/etcdctl" version | tr '\n' ' ')"
info "$("$cache/etcdutl" version | tr '\n' ' ')"
info "$("$cache/kine" --version 2>&1 | head -1)"
pass "binaries"

echo "== certificates (one CA; server, peer and client pairs for 127.0.0.1)"
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
pass "certificates"

# etcdctl wrappers: ctl-etcd talks TLS to 127.0.0.1:2379 (Plan.etcd_servers
# True), ctl-kine to the unix socket (Plan.kine_sock).
sock=$data/kine/kine.sock
cat > "$bin/ctl-etcd" <<EOF
#!/bin/sh
exec "$cache/etcdctl" --endpoints https://127.0.0.1:2379 --cacert "$pki/ca.crt" --cert "$pki/client.crt" --key "$pki/client.key" --command-timeout 30s "\$@"
EOF
cat > "$bin/ctl-kine" <<EOF
#!/bin/sh
exec "$cache/etcdctl" --endpoints "unix://$sock" --command-timeout 30s "\$@"
EOF
chmod +x "$bin/ctl-etcd" "$bin/ctl-kine"

N=2100

# seed CTL LABEL: N keys and two more through vcluster's txn shapes.
seed() {
  local ctl=$1 l=$2 r
  # Create (pkg/etcd/client.go): If(ModRevision(key) = 0).Then(OpPut).
  seq -f '%04g' 1 "$N" | xargs -P 8 -I '{}' sh -c \
    'printf "mod(\"/registry/spike/k{}\") = \"0\"\n\nput /registry/spike/k{} v-{}\n\n\n" | "$0" txn -w json' "$ctl" \
    > "$work/$l-bulk.json" 2> "$work/$l-bulk.err"
  eq "$l: $N txn creates succeed" "$(json succeeded "$work/$l-bulk.json")" "$N"
  # etcdctl txn unquotes "..." values with Go's strconv.Unquote, so a
  # value can carry any byte.
  printf '%s\n' 'mod("/registry/spike/binary") = "0"' '' 'put /registry/spike/binary "hello world\n\x01\xff"' '' '' \
    | "$ctl" txn -w json > "$work/$l-bin.json" 2>&1
  eq "$l: txn create of a binary value" "$(json succeeded "$work/$l-bin.json")" 1
  printf '%s\n' 'mod("/registry/spike/k0001") = "0"' '' 'put /registry/spike/k0001 clobbered' '' '' \
    | "$ctl" txn -w json > "$work/$l-dup.json" 2>&1
  eq "$l: a second create of a key does not succeed (ErrConflict)" "$(json succeeded "$work/$l-dup.json")" 0
  "$ctl" get /registry/spike/k0001 -w json > "$work/$l-k1.json" 2>&1
  eq "$l: the existing value stays" "$(json value "$work/$l-k1.json")" "v-0001"
  # Update: If(ModRevision(key) = rev).Then(OpPut).Else(OpGet).
  printf '%s\n' 'mod("/registry/spike/upd") = "0"' '' 'put /registry/spike/upd one' '' '' \
    | "$ctl" txn -w json > "$work/$l-upd1.json" 2>&1
  "$ctl" get /registry/spike/upd -w json > "$work/$l-upd.json" 2>&1
  r=$(json modrev "$work/$l-upd.json")
  printf '%s\n' "mod(\"/registry/spike/upd\") = \"$r\"" '' 'put /registry/spike/upd two' '' 'get /registry/spike/upd' '' '' \
    | "$ctl" txn -w json > "$work/$l-upd2.json" 2>&1
  eq "$l: txn update at the mod revision (put, else get)" "$(json succeeded "$work/$l-upd2.json")" 1
  # Delete: Txn().Then(OpGet(key), OpDelete(key)).
  printf '%s\n' 'mod("/registry/spike/gone") = "0"' '' 'put /registry/spike/gone x' '' '' \
    | "$ctl" txn -w json > /dev/null 2>&1
  printf '%s\n' '' 'get /registry/spike/gone' 'del /registry/spike/gone' '' '' \
    | "$ctl" txn -w json > "$work/$l-del.json" 2>&1
  "$ctl" get /registry/spike/gone -w json > "$work/$l-gone.json" 2>&1
  eq "$l: txn delete (get, del) removes the key" "$(json nkvs "$work/$l-gone.json")" 0
}

# dump CTL LABEL OUT: page "/" (range end "0") at one revision with
# --limit 1000, as vcluster's listStream does; "key value" lines (base64).
# etcdctl cannot pass vcluster's next start key (last key + "\x00": argv
# holds no NUL), so a page starts at the last key and drops it.
dump() {
  local ctl=$1 l=$2 out=$3 start=/ prev="" rev="" n=0
  : > "$out"
  "$ctl" get / --prefix --count-only -w fields > "$work/$l-count.txt" 2>&1 || { fail "$l: count-only get"; return 1; }
  info "$l: count-only get: count $(json fields "$work/$l-count.txt" Count), revision $(json fields "$work/$l-count.txt" Revision)"
  while :; do
    n=$((n + 1))
    if [ $n = 1 ]; then
      "$ctl" get "$start" 0 --limit 1000 -w json > "$work/$l-p$n.json" 2>&1 || { fail "$l: page $n"; return 1; }
      rev=$(json rev "$work/$l-p$n.json")
    else
      "$ctl" get "$start" 0 --limit 1000 --rev "$rev" -w json > "$work/$l-p$n.json" 2>&1 || { fail "$l: page $n"; return 1; }
      [ "$(json rev "$work/$l-p$n.json")" = "$rev" ] || fail "$l: page $n at revision $rev"
    fi
    json page "$work/$l-p$n.json" "$prev" >> "$out"
    [ "$(json nkvs "$work/$l-p$n.json")" = 0 ] && break
    [ "$(json more "$work/$l-p$n.json")" = 1 ] || break
    prev=$(json lastkey "$work/$l-p$n.json")
    start=$prev
    [ $n -lt 50 ] || { fail "$l: paging does not end"; return 1; }
  done
  eq "$l: count-only revision equals the first page's revision" "$(json fields "$work/$l-count.txt" Revision)" "$rev"
  eq "$l: count-only count equals the keys paged" "$(json fields "$work/$l-count.txt" Count)" "$(wc -l < "$out" | tr -d ' ')"
  echo "$n" > "$work/$l-pages"
}

json expected "$N" | sort > "$work/expected"
want_keys=$((N + 2))

echo "== 1. embedded etcd: snapshot save, etcdutl restore into a new name"
# etcd_start NAME: Plan.etcd_args NAME with the data dir and certificates
# of this run.
etcd_start() {
  "$cache/etcd" --name "$1" --data-dir "$data/$1/etcd" \
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
etcd_start demo
eventually "etcd demo serves" 60 "$bin/ctl-etcd" endpoint health || { tail -20 "$work/etcd-demo.log"; exit 1; }
seed "$bin/ctl-etcd" etcd
dump "$bin/ctl-etcd" etcd "$work/etcd-before"
eq "etcd: every seeded key, once, same bytes" "$(sort "$work/etcd-before" | cmp -s - "$work/expected" && echo same || echo differs)" same
old_rev=$(json fields "$work/etcd-count.txt" Revision)

"$bin/ctl-etcd" snapshot save "$work/snap.db" > "$work/save.log" 2>&1
check "etcdctl snapshot save" test -s "$work/snap.db"
"$cache/etcdutl" snapshot status "$work/snap.db" -w json > "$work/status.json" 2> "$work/status.err"
eq "etcdutl snapshot status: revision of the live store" "$(json status_rev "$work/status.json")" "$old_rev"
stop "$etcd_pid"

"$cache/etcdutl" snapshot restore "$work/snap.db" --name demo2 --data-dir "$data/demo2/etcd" \
  --initial-cluster demo2=https://127.0.0.1:2380 --initial-cluster-token vcluster \
  --initial-advertise-peer-urls https://127.0.0.1:2380 \
  --bump-revision 1000 --mark-compacted > "$work/restore.log" 2>&1
if [ -d "$data/demo2/etcd/member" ]; then pass "etcdutl snapshot restore --name demo2 --bump-revision 1000 --mark-compacted"
else fail "etcdutl snapshot restore"; cat "$work/restore.log"; fi

etcd_start demo2
if eventually "restored etcd demo2 serves" 60 "$bin/ctl-etcd" endpoint health; then
  "$bin/ctl-etcd" member list -w json > "$work/members.json" 2>&1
  eq "restored member: name demo2, loopback peer" "$(json members "$work/members.json")" "demo2 https://127.0.0.1:2380"
  dump "$bin/ctl-etcd" etcd-restored "$work/etcd-after"
  eq "restored etcd: every key, same bytes" "$(sort "$work/etcd-after" | cmp -s - "$work/expected" && echo same || echo differs)" same
  eq "restored revision is the snapshot's plus 1000" "$(json fields "$work/etcd-restored-count.txt" Revision)" "$((old_rev + 1000))"
  refuses "a read at the snapshot revision is compacted" "$bin/ctl-etcd" get / --prefix --rev "$old_rev"
  grep -q compacted "$work/refused.out" || fail "the old-revision read error names compaction"
  printf '%s\n' 'mod("/registry/spike/after") = "0"' '' 'put /registry/spike/after x' '' '' \
    | "$bin/ctl-etcd" txn -w json > "$work/after.json" 2>&1
  eq "restored etcd: txn create" "$(json succeeded "$work/after.json")" 1
  eq "restored etcd: the create's revision follows the bump" "$(json rev "$work/after.json")" "$((old_rev + 1001))"
else
  tail -30 "$work/etcd-demo2.log"
fi
stop "$etcd_pid"

echo "== 2. kine on SQLite (vk8s's default store)"
mkdir -p "$data/kine"
# Plan.kine_args: vcluster pkg/k8s/k8s.go StartKineWithDone, SQLiteParams.
"$cache/kine" --endpoint "sqlite://$data/kine/state.db?_journal=WAL&cache=shared&_busy_timeout=30000&_txlock=immediate" \
  --metrics-bind-address 127.0.0.1:2381 --listen-address "unix://$sock" > "$work/kine.log" 2>&1 &
pids+=($!)
kine_pid=$!
if ! eventually "kine listens on its unix socket" 30 test -S "$sock"; then tail -30 "$work/kine.log"; exit 1; fi
eventually "etcdctl reaches kine" 30 "$bin/ctl-kine" get /registry/health
refuses "kine refuses a plain range delete (etcdctl del)" "$bin/ctl-kine" del /registry/spike/none
refuses "kine refuses a serializable read" "$bin/ctl-kine" get / --prefix --consistency=s
if "$bin/ctl-kine" put /registry/spike/plain x > "$work/plain.out" 2>&1; then
  info "kine $KINE accepts a plain put (vcluster does not rely on it)"
  printf '%s\n' '' 'get /registry/spike/plain' 'del /registry/spike/plain' '' '' | "$bin/ctl-kine" txn > /dev/null 2>&1
else
  info "kine $KINE refuses a plain put: $(head -c 200 "$work/plain.out")"
fi
seed "$bin/ctl-kine" kine
dump "$bin/ctl-kine" kine "$work/kine-dump"
pages=$(cat "$work/kine-pages" 2>/dev/null || echo 0)
if [ "$pages" -ge 3 ]; then pass "kine: $want_keys keys in $pages pages of 1000"; else fail "kine: $pages pages, want 3 or more"; fi
eq "kine: every seeded key, once, base64 values decode to the bytes written" \
  "$(sort "$work/kine-dump" | cmp -s - "$work/expected" && echo same || echo differs)" same
eq "kine: key count" "$(wc -l < "$work/kine-dump" | tr -d ' ')" "$want_keys"
stop "$kine_pid"

echo
if [ $fails = 0 ]; then echo "PASS snapshot store spike"; else echo "FAIL snapshot store spike: $fails failures"; exit 1; fi
