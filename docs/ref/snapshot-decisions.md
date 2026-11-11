# Open-format snapshot: store tools and vk8s decisions

vk8s will add an opt-in open-format snapshot next to its VM-level
snapshot. The open format is vcluster's `pkg/snapshot` archive: the
format that `vcluster snapshot --standalone` writes. `src/standalone/
snapshot.bend` encodes it already (laws/done/snapshot, docs/SNAPSHOT.md).
This document records a spike that proves which store tools work on
Linux, and the decisions for the first phase. No product code changes
with it.

Reference: loft-sh/vcluster at c5e9027e972df3f24b58137e9018929b61635641
(open code only; no vcluster-pro binary was downloaded, run or read).
Tools: etcd v3.5.21 (etcd, etcdctl, etcdutl from the release tarball) and
k3s-io/kine v0.17.5 (`kine-amd64`, cgo build with SQLite), both pinned by
SHA-256 in the spike.

## The spike: tests/snapshot_store_spike.sh

CI runs it in the `snapshot-store-spike` job of .github/workflows/ci.yml.
It downloads the tools once into `~/.cache/vk8s-envtest/snapshot-...`
(GitHub cache key `snapshot-spike-v3.5.21-kine-v0.17.5`) and checks the
SHA-256 on every run. Each check prints a PASS or FAIL line; INFO lines
record observations that are not checks. It needs curl, openssl and
python3 (`python3 -I` reads the `-w json` output). Run it with
`tests/snapshot_store_spike.sh`; `KEEP=1` keeps the work directory.

Both stores get the same data, written only through vcluster's
transaction shapes (`pkg/etcd/client.go`):

- 2100 keys `/registry/spike/kNNNN` = `v-NNNN`, created in parallel
  (`xargs -P 8`), so that a 1000-key page limit gives three pages;
- `/registry/spike/binary` = the bytes `hello world\n\x01\xff`;
- `/registry/spike/upd`, created as `one` and then updated to `two`;
- `/registry/spike/gone`, created and then deleted: first with
  vcluster's no-compare get+del delete, then (where the key stays) with
  the delete at the mod revision.

### Commands that vcluster's client sends, as etcdctl input

Create (`client.Create`: If ModRevision(key) = 0, Then OpPut):

```sh
printf '%s\n' 'mod("/k") = "0"' '' 'put /k value' '' | etcdctl txn -w json
```

The output has `"succeeded":true`. When the key exists, the field is
absent (omitempty) and the exit status is still 0: read `succeeded`, not
the exit status. That is vcluster's `ErrConflict: key exists`.

Update (`client.Update`: If ModRevision(key) = rev, Then OpPut, Else
OpGet). The else-branch get is not optional on kine (see below):

```sh
printf '%s\n' 'mod("/k") = "7"' '' 'put /k two' '' 'get /k' '' | etcdctl txn -w json
```

Delete (`client.Delete`: no compare, Then OpGet, OpDelete):

```sh
printf '%s\n' '' 'get /k' 'del /k' '' '' | etcdctl txn -w json
```

On kine this shape does not delete an existing key (see the pitfalls).
Delete at a revision (the apiserver's shape: If ModRevision(key) = rev,
Then OpDelete, Else OpGet) works on both stores:

```sh
printf '%s\n' 'mod("/k") = "7"' '' 'del /k' '' 'get /k' '' | etcdctl txn -w json
```

etcdctl reads the value of a txn `put` with Go's `strconv.Unquote` when it
is in double quotes, so `put /k "a b\n\x01\xff"` stores any byte.

Current revision (`currentRevision`: WithPrefix, WithCountOnly):

```sh
etcdctl get / --prefix --count-only -w json   # header.revision, count
```

List (`listStream`: WithRange(prefix end), WithLimit(1000), the first
page at revision 0, the next pages at the first page's revision):

```sh
etcdctl get / 0 --limit 1000 -w json                     # page 1: header.revision = R
etcdctl get <last key> 0 --limit 1000 --rev R -w json    # page 2..: drop the first kv
```

The range end of prefix `/` is `0`. Keys and values in `-w json` are
base64. `more` is absent on the last page.

### 1. Embedded etcd

etcd starts with the flags of `Plan.etcd_args` (src/guest/plan.bend):
`--name <cluster>`, client `https://127.0.0.1:2379`, peer
`https://127.0.0.1:2380`, `--initial-cluster <cluster>=https://127.0.0.1:2380`,
`--initial-cluster-token vcluster`, client and peer TLS with client
certificate checks. The spike makes one CA and server, peer and client
pairs for IP 127.0.0.1 with openssl.

```sh
E="--endpoints https://127.0.0.1:2379 --cacert ca.crt --cert client.crt --key client.key"
etcdctl $E snapshot save snap.db
etcdutl snapshot status snap.db -w json          # .revision
etcdutl snapshot restore snap.db --name demo2 --data-dir <new>/etcd \
  --initial-cluster demo2=https://127.0.0.1:2380 \
  --initial-cluster-token vcluster \
  --initial-advertise-peer-urls https://127.0.0.1:2380 \
  --bump-revision 1000 --mark-compacted
etcd <Plan.etcd_args demo2, --data-dir <new>/etcd>
```

The checks:

- the source etcd pages the 2102 keys back with the same bytes;
- `etcdutl snapshot status` gives the revision that the count-only get
  gave just before the save;
- the restored etcd has one member, `demo2`, with the peer URL
  `https://127.0.0.1:2380`;
- it serves the same 2102 keys with the same bytes;
- its revision is the snapshot's revision plus 1000 exactly
  (`modifyLatestRevision` in etcdutl/snapshot/v3_snapshot.go writes an
  empty revision key at latest+bump and schedules compaction there);
- a read at the snapshot's revision fails with "required revision has
  been compacted" (`--mark-compacted`). Watchers and informers that
  remember an older revision must list again; they cannot resume.
- a new txn create succeeds at revision snapshot+1001.

This is vcluster's own restore: `restoreclient.go` calls etcdutl's
`snapshot.NewV3(...).Restore` with `InitialClusterToken: "vcluster"`,
`SkipHashCheck: false`, `RevisionBump:
snapshotRestoreBumpRevision(latest, snapshot, 1000)` and
`MarkCompacted: true`. For a new data dir `latest` is 0, so the bump is
1000.

Pitfalls:

- `etcdctl snapshot restore` and `etcdctl snapshot status` are
  deprecated in v3.5. Use etcdutl. etcdutl does not talk to a server; it
  works on files, so it needs no certificates.
- `--bump-revision` needs `--mark-compacted` and the reverse: etcdutl
  refuses each one alone ("--mark-compacted required if --revision-bump
  > 0").
- The target data dir must not exist. etcdutl makes it with mode 0700,
  which etcd requires.
- `etcdutl snapshot restore` writes the member name and the peer URLs
  into the data. The flags of the etcd that starts on it must match
  them: `--name` and the peer URL of the new cluster, not of the source.
  `--initial-cluster` and `--initial-cluster-state` are ignored when the
  data dir exists, so `Plan.etcd_args` can stay as it is.
- `etcdctl snapshot save` needs a single endpoint.
- vcluster standalone names the member after the node IP
  (`VCLUSTER_STANDALONE_IP_ADDRESS`) with peer `https://<ip>:2380`
  (`nameAndPeerURLForConfig`). vk8s names it after the cluster with a
  loopback peer (one control-plane VM). An open archive does not carry
  the member, so both restore into either.

### 2. kine on SQLite (vk8s's default store)

kine starts with the flags of `Plan.kine_args`:

```sh
kine --endpoint 'sqlite://<dir>/state.db?_journal=WAL&cache=shared&_busy_timeout=30000&_txlock=immediate' \
  --metrics-bind-address 127.0.0.1:2381 --listen-address unix://<dir>/kine.sock
etcdctl --endpoints unix://<dir>/kine.sock ...
```

etcdctl v3.5 reaches the unix socket with `unix://` and an absolute
path. kine on SQLite has no TLS.

The checks:

- txn create, the duplicate create (not succeeded, the old value stays),
  the update with its else-get, and the delete at the mod revision
  work; the no-compare get+del delete leaves an existing key and does
  not succeed;
- the count-only get gives the count of the keys that the pages return,
  and the revision of the first page;
- the pages at one revision return every key once (2102 keys and
  kine's `/registry/health`, in 3 pages), and the base64 keys and values decode to the bytes written,
  `\x01\xff` included;
- kine refuses `etcdctl del` (DeleteRange is unsupported) and
  `etcdctl get --consistency=s` (serializable reads are unsupported).

Pitfalls (kine pkg/server, v0.17.5):

- kine accepts only fixed txn shapes (`LimitedServer.Txn`): create (one
  compare mod = 0, one put, no else), update (one compare mod = rev, one
  put, else exactly one get), delete (get then del, or compare mod = rev,
  del, else get) and compact. Any other txn gets "not supported". An
  update without the else-get is not an update to kine.
- vcluster's `client.Delete` (no compare, get then del) is a no-op for
  an existing key on kine v0.17.5: `isDelete` passes revision 0, and the
  generic driver's `insertSQL` inserts the delete row only when the key
  has no row at all (`COALESCE(MAX(id), 0) = 0`). The txn has
  `succeeded` false, which vcluster's Delete ignores. vk8s must delete at
  the mod revision (get the key, then compare mod = rev, del, else get).
- kine creates `/registry/health` = `{"health":"true"}` when it starts
  (`LogStructured.Start`), so a list of `/` has one key more than the
  keys written.
- Plain `put` works on kine v0.17.5 (`LimitedServer.Put` creates or
  updates), but the spike only reports it (INFO): vk8s's guest runs the
  kine of loft-sh/kubernetes's bundle (`v0.14.16.vcluster.4`, see
  docs/ref/vcluster-standalone.md), and vcluster does not rely on Put.
  vk8s must not either.
- Range delete is unsupported. To empty kine, delete key by key
  (vcluster `DeleteKeysWithPrefix`), or start a new database: a restore
  into a new name has an empty database, so it deletes nothing.
- Sorted reads and min/max revision filters are unsupported. A list
  must use the default sort (key order).
- `--limit N` returns `more` when there are more keys; `count` is the
  count of the whole range, not of the rest.
- vcluster's next start key is the last key plus a NUL byte
  (`nextStartKey`). A NUL byte cannot pass through argv, so the spike
  starts each next page at the last key and drops that key. Code that
  uses the etcd client directly can append the NUL byte.
- kine keeps its own `compact_rev_key` row; it is not under `/` and a
  list of `/` does not return it.
- vcluster pins the revision with a count-only get before it lists
  (`writeKeyValueSnapshot`). A write between the two reads is not
  reflected in the revision: the archive revision is a lower bound.

## Decisions

### D1. `--format open|vm` on `snapshot create`; vm stays the default

`vk8s snapshot create NAME PATH [--format open|vm]`. Without `--format`
the snapshot is the VM-level archive of today: laws/cli.bend
`cli.snapshot.file_url` (line 110) pins
`snapshot create demo file:///tmp/s.tar.gz` to `C.Snapshot{"demo",
"/tmp/s.tar.gz"}`, the VM format. `--format open` writes vcluster's
archive: an etcd archive (`/vcluster/snapshot/db`, from etcdctl snapshot
save) for embedded etcd, a key/value archive
(`/vcluster/snapshot/revision`, then one record per key) for kine.
A new law for the open form goes under `# Proposed:` in laws/cli.bend;
the existing law does not change.

### D2. restore detects the format from the first tar entry

`vk8s restore NAME PATH` has no `--format`. It gunzips the archive and
reads the first tar header:

- `metadata.json`: the VM format (host/vk8s.bend writes it first);
- a name under `/` (`/vcluster/snapshot/release`, `.../request/...`,
  `.../db`, `.../revision`, or an etcd key): the open format. Inside it,
  `getSnapshotArchiveKind` (vcluster restoreclient.go, `Snap.kind` in
  src/standalone/snapshot.bend) picks etcd or key/value;
- anything else: refuse with an error that names the entry.

An empty archive is a key/value archive with no keys, as in vcluster
(`getSnapshotArchiveKind` returns KeyValueSnapshotKind at EOF).

### D3. Phase one reads and writes only `file://` and bare paths

`file:///abs/path` and a bare path (as the VM format accepts today). The
URL parser (`Snap.parse`) already reads s3, oci, container and https
URLs; the CLI refuses them in phase one with an error that names the
scheme. Object stores come in a later phase.

### D4. Standalone clusters only; classic mode is refused

A classic cluster (`--host-kubeconfig`) is refused for `--format open`,
with an error that names classic mode. A classic restore needs the pod
transform (its pods run on host nodes, not private nodes) and vcluster's
classic flow pauses and resumes the Helm workload; phase one does
neither. The VM format stays available for classic clusters.

### D5. Restore only into a new name

`vk8s restore NAME PATH` with the open format refuses a NAME that
exists. The restore creates the cluster: it writes the store before the
control plane starts. This is vcluster's `--new-vcluster` path: the
restore also drops the namespace root CA ConfigMaps (`kube-root-ca.crt`)
and the vcluster mappings (`Snap.restore_plan` with new=True;
`postRestoreSnapshotDataMutation` for etcd archives). vcluster
standalone restores in place: it stops the service, backs up and
replaces the data dir, and starts the service again
(`restoreStandaloneVCluster`). vk8s does not.

- embedded etcd target: `etcdutl snapshot restore` into the new data
  dir with the new name, loopback peer, token vcluster, `--bump-revision
  1000 --mark-compacted` (proven above);
- kine target: kine on a new SQLite file, then each record of
  `Snap.restore_plan` through the txn create (on an empty database,
  vcluster's Get+Create is a create);
- an etcd archive into kine is converted first (`Snap.convert`; vcluster
  `needsEtcdToKeyValueConversion`): the host opens the bolt database with
  a temporary etcd (`etcdutl snapshot restore`, then `etcd` on it) and
  pages it as above. A key/value archive into embedded etcd uses the
  same txn create against the new etcd.

### D6. No pause for the open format

The VM format pauses the cluster to clone its disk. The open format reads
through the store's API while the cluster runs, as vcluster does:
`etcdctl snapshot save` is a point-in-time copy, and the key/value
archive reads every page at one revision. vcluster pauses only a classic
restore, never a snapshot.

### D7. No release entry

vcluster standalone writes no `/vcluster/snapshot/release`: CreateSnapshot
sets `snapshotOpts.Release` only when `!vCluster.IsStandalone`
(pkg/cli/snapshot_helm.go:41-42, "Standalone is not Helm-deployed; no
release metadata to include in the snapshot"). vk8s writes none. A
restore ignores a release entry when there is one (`Snap.restore_plan`
skips snapshot metadata).

### D8. Private-nodes semantics: no pod transform

vk8s clusters run real kubelets, as vcluster private nodes do. vcluster
transforms pods (clears nodeName and status) only when
`!vConfig.PrivateNodes.Enabled` (restoreclient.go:465 and 564). vk8s
restores pods as they are; the kubelets of the new cluster update them.

## Open points for the implementation

- Where the tools run: etcdctl and etcdutl are in the assets disk
  (scripts/guest/fetch-assets.sh copies them), so the guest runs them
  through the host-to-guest request channel, and the host streams the
  archive.
- The kine of the guest is loft's v0.14.16.vcluster.4; the spike used
  k3s-io v0.17.5. The spike did not run loft's build. Before the feature
  ships, run the same checks against the guest's kine (for example with
  the kine of the assets disk in place of the download).
