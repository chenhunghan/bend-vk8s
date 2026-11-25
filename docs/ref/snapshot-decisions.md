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

### D9. The CLI parse (src/cli/cli.bend)

`vk8s snapshot create NAME PATH [--format vm|open]` takes `--format V`
or `--format=V` after PATH. Without the flag, and with `vm`, the result
is `C.Snapshot{name, path}` as before (laws/cli.bend
`cli.snapshot.file_url` still proves). `open` gives the new
`C.SnapshotOpen{name, path}`. Another value, a missing value, an unknown
option or a word after the value gives help that names it. A PATH that
starts with `oci://`, `s3://`, `https://` or `container://` gives
`vk8s snapshot: <scheme>:// is not supported yet (use a file path or
file://)` (D3), for both formats. `vk8s restore NAME PATH` refuses the
same schemes with `vk8s restore: ...` and otherwise stays
`C.Restore{name, path}`. The host does not run `SnapshotOpen` yet: it
stops with "--format open is not implemented yet". The classic-mode
refusal of D4 needs the cluster's state, so the host does it.

### D10. The share's snapshot dir

The host and the guest exchange files in `share/snapshot/`
(`/var/lib/vk8s-host/snapshot` in the guest, `Plan.snapshot_dir`):

| File | Writer | Content |
| --- | --- | --- |
| `export/` | guest (snapshot-dump, D16) | the dump; written as `export.tmp/`, then renamed |
| `export/db` | guest, etcd | `etcdctl snapshot save` output |
| `export/revision` | guest, kine | the count-only get's header revision (the archive revision) |
| `export/count.txt` | guest, kine | the count-only get's `-w fields` output (D16; snapshot-export wrote `count.json`) |
| `export/page-N.json` | guest, kine | page N's `-w json` output, N = 1, 2, ... |
| `export/pages` | guest, kine | the number of pages |
| `restore` | host | the marker: restore at the next boot |
| `db` | host | the etcd database to restore (etcd target) |
| `puts` | host | the puts to apply (kine target) |

### D11. The request snapshot-export

Superseded by snapshot-dump (D16): its kine script fails against
etcdctl 3.5. The action and its laws stay; the host does not send it.

The host writes `ID snapshot-export` to the request channel
(`Plan.request`). Its steps remove `export` and `export.tmp`, make
`export.tmp`, dump the store, and rename `export.tmp` to `export`. The
host reads `export` only after the answer `ID done`. Any other action
text, `snapshot-export; rm -rf /` included, has no steps
(`plan.request.unknown` and `plan.request.snapshot_export.unsafe`).

- Embedded etcd (`Cfg.etcd`): `etcdctl --endpoints
  https://127.0.0.1:2379 --cacert pki/etcd/ca.crt --cert
  pki/apiserver-etcd-client.crt --key pki/apiserver-etcd-client.key
  snapshot save export.tmp/db`. These are the client pair that
  `Plan.etcd_client` gives the API server.
- kine: one `sh -c` script (`Plan.kine_dump_script`) with etcdctl on
  `unix:///var/lib/vcluster/kine.sock`. It runs `get / --prefix
  --count-only -w json` and writes the header revision to `revision`.
  Then it runs `get / 0 --limit 1000 -w json` (page 1, revision R). While
  a page has `"more":true`, it runs `get <last key> 0 --limit 1000 --rev
  R -w json`. The last key is the base64 `key` field of the page,
  decoded with busybox `base64 -d`. busybox has no JSON reader, so the
  guest does not parse the pages. The host decodes them and drops the
  first key of every page after the first: that key is the previous
  page's last key (see the pitfalls of section 2).

`Plan.request_mode(classic, ...)` gives no steps for a `snapshot-*`
action in classic mode (D4). PID 1 does not call it yet; the host
refuses classic first.

### D12. The restore boot

`Plan.boot_restore(c, restore)` is `Plan.boot(c)` when `restore` is
false (law `plan.boot_restore.none`). PID 1 passes true when
`share/snapshot/restore` exists at boot (the host side comes later). The
restore steps go into the control plane (`Plan.restore_store`):

- etcd: before etcd starts, `etcdutl snapshot restore share/snapshot/db
  --name <cluster> --data-dir /var/lib/vcluster/etcd --initial-cluster
  <cluster>=https://127.0.0.1:2380 --initial-cluster-token vcluster
  --initial-advertise-peer-urls https://127.0.0.1:2380 --bump-revision
  1000 --mark-compacted` (section 1), then remove the marker and `db`;
- kine: after kine listens (the WaitFile on its socket) and before the
  API server starts, the puts script (`Plan.kine_puts_script`), then
  remove the marker and `puts`.

Removing the marker makes a later reboot a normal boot. When a restore
step fails, the boot stops (a failed `Run`), and the marker stays.

### D13. The puts file and the kine restore

`share/snapshot/puts` has two lines for each put: the key, then the
value as a Go double-quoted string (`strconv.Quote`), which etcdctl txn
unquotes. The host makes it from `Snap.restore_plan` with new=true and
private nodes=true (D5, D8). A key must not hold a newline, a space or a
`"`. Kubernetes keys do not.

For each put the script sends vcluster's create
(`mod("<key>") = "0"`, then `put <key> <value>`) to `etcdctl txn -w
json`. The output must have `"succeeded":true`; otherwise the script
prints the key and the output and exits with 1, and the boot stops.
After the last put it runs `etcdctl compaction <revision of the last
put>`, as `restoreKeyValueSnapshot` does. With no put it does not
compact (Snap.Plan's `compact`). The spike did not run a compaction on
kine, so a refused compaction prints a line and does not stop the boot.

### D14. The host side (host/snapshot_open.bend)

- Export, embedded etcd: the archive is the header of
  `Snap.Tar.file_header(/vcluster/snapshot/db, size)`, the `export/db`
  file streamed (perl, O_NOFOLLOW, exactly that size), then
  `Snap.Tar.pad_after` zeros and the trailer. That is
  `Snap.Tar.encode(Snap.etcd_archive(meta0, db, None))` byte for byte
  (checked in tests/snapshot_open_build.bend) without the database in
  memory.
- Export, kine: the pages are parsed as JSON; for every page after the
  first, its first key must be the previous page's last key, and it is
  dropped. `Snap.write_kv` with the `revision` file and `Snap.encode`
  give the tar.
- Both: gzip -3 into `PATH.tmp` under umask 077, chmod 600, rename. The
  share's `export` and `export.tmp` go afterwards, also on failure.
- Restore: the gunzipped stream's first MiB gives the format (the first
  record through `Snap.Tar.heads`, or the first header alone when the
  record does not fit, as an etcd database does). For the open format
  the archive is gunzipped into a staging directory beside the cluster
  directories, and the headers of the first MiB give the kind with
  getSnapshotArchiveKind's rule. An etcd archive's database is copied out
  at its offset into `db`; a key/value archive (at most 256 MiB of tar)
  is decoded and gives `puts`. The staging `snapshot/` directory then
  moves to the new cluster's share.
- The puts leave out `/registry/health`. kine creates it when it starts
  (see the pitfalls of section 2), so the new kine already has it with
  the same value. vcluster's `Put` would read it and update it
  (`client.Put`: Get, then Create or Update); the puts script of D13 only
  creates, and a failed create stops the boot. A kine archive always
  holds the key, so without this a kine restore would always fail.
- A key the puts file cannot carry (empty, not printable ASCII, a space,
  `"` or `\`) refuses the restore by name.
- The new cluster gets the archive's store: embedded etcd for an etcd
  archive, kine for a key/value archive. Conversion (D5) is a later step.
- PID 1 reads `share/snapshot/restore` after the share's mount, on a
  standalone control plane only, and then takes the steps after the mount
  from `Plan.boot_restore(c, True)`. Requests go through
  `Plan.request_mode(classic, ...)`.

### D15. The snapshot decides the backing store

The restore takes the store kind from the archive: an etcd archive
(`/vcluster/snapshot/db`) restores into embedded etcd, a key/value
archive into kine. The `C.Restore{name, path}` contract does not change,
so it carries no store. A `--backing-store` flag would be ignored, so
the pure parser (`src/cli/cli.bend`) refuses it:

- `vk8s create NAME --restore PATH --backing-store S`, in any order,
  gives `vk8s create: --backing-store cannot be combined with
  --restore; the snapshot decides the backing store`;
- `vk8s restore NAME PATH --backing-store S` gives `vk8s restore:
  --backing-store cannot be combined with restore; the snapshot decides
  the backing store`.

The laws are `cli.create.restore_backing_store`,
`cli.create.backing_store_restore` and `cli.restore.backing_store`
(laws/cli.bend, `# Proposed:`). vcluster has no equivalent: it converts
an etcd archive for other stores and puts a key/value archive into etcd
(D5). When vk8s converts too, the flag can choose the target store.

### D16. The request snapshot-dump supersedes snapshot-export

The kine script of D11 fails at its first command. etcdctl 3.5 accepts
`--count-only` only with `-w fields`:

```
$ etcdctl get / --prefix --count-only -w json
Error: --count-only is only for `--write-out=fields`
```

Under `set -e` the script exits there, so `export.tmp` has no
`revision` and no pages, and the rename does not run
(snapshot-envtest on #39: "the dump has 0 pages"). The laws of D11
(`plan.request.snapshot_export.kine`, `plan.kine_dump_script`) pin
that script, and laws are append-only, so a new action replaces it:

- The host writes `ID snapshot-dump` (`Vk8s.snapshot_open.go`).
- Embedded etcd: the steps of snapshot-export.
- kine: `Plan.kine_dump_script.v2`. It keeps vcluster's count-only read
  of the current revision (`pkg/etcd/client.go` `currentRevision`: Get
  "/" WithPrefix WithCountOnly, the header's revision), as `get /
  --prefix --count-only -w fields > count.txt`, and reads the header
  line `"Revision" : N` into `revision`. The pages are those of D11.
- `snapshot-dump; rm -rf /` and classic mode have no steps.

The laws are `plan.request.snapshot_dump.etcd`,
`plan.request.snapshot_dump.kine`, `plan.kine_dump_script.v2`,
`plan.request.snapshot_dump.unsafe` and
`plan.request_mode.classic_snapshot_dump` (laws/plan.bend,
`# Proposed:`). `Plan.snapshot_export` stays defined so the laws of D11
keep proving.

### D17. After a restore, the Node list holds the nodes that exist

A snapshot's store holds the Node objects of the cluster it was taken
from, and vk8s names a node after its cluster (`NAME`,
`NAME-worker-I`). On 2026-11-24 the open archive of `d1` restored as
`d1c` listed `d1` and `d1-worker-1` beside `d1c`: Ready at first, then
NotReady for ever, their pods (CoreDNS among them) "Running" on them
until the eviction timeout.

vcluster does not meet this: its docker driver keeps every node name
across a restore (`pkg/cli/restore_docker.go` writes `.restore-hostname`
so that "the kubelet re-registers with the node name that matches etcd
data", and the workers come back from the snapshot's vcluster.yaml under
their own names), standalone restores in place, and its restore clients
put every key back, `/registry/minions` included
(`restoreKeyValueSnapshot` skips only the mappings and
`kube-root-ca.crt`). Where a node is not configured, its
`ensureVClusterNodes` (`pkg/cli/create_docker.go`) removes "the nodes
that are not in the config".

vk8s applies that removal to the restored store's Node objects, through
the Kubernetes client once the API answers (`Vk8s.restore.nodes`;
`C.Cli.restore_stale` decides, and each removal prints vcluster's
"Removing node N from vCluster NAME"):

- Open format: a new cluster with its own CA around the store, booting
  the control plane only, so every Node but the new control plane's
  goes.
- VM format: the restore boots the snapshot's disk under the snapshot's
  guest name and, as vcluster keeps the configured nodes, with the
  snapshot's worker indices (cluster.env `WORKERS`; it used to boot
  1..NODES, so a cluster whose workers were 1 and 3 came back with 1 and
  2 and a stale `-worker-3`). Only a worker Node of vk8s's naming that
  the restore does not boot goes (the rule of `create --upgrade`); a
  Node joined with a token stays, since the CA is the same and it can
  rejoin.

A Node's Lease (kube-node-lease) and CSINode name the Node as their
owner, so the garbage collector removes them, and the pod garbage
collector removes the pods bound to it (seen on a Mac: both gone within
seconds, the Deployment's pods Running on the new node within a
minute). Bootstrap token Secrets are per token, not per node. The
removal needs TLS on the host, so `restore` stops before any change
without it (`C.Cli.tls_needed.v2`).

The laws are `cli.nodes_stale.*`, `cli.nodes_live.*`, `cli.node_own.*`,
`cli.restore_stale.*` and `cli.removing_node` (laws/cli.bend,
`# Proposed:`).

## Open points for the implementation

- Where the tools run: etcdctl and etcdutl are in the assets disk
  (scripts/guest/fetch-assets.sh copies them), so the guest runs them
  through the host-to-guest request channel (D11) and at boot (D12),
  and the host streams the archive. The host side is D14.
- After an etcd restore into a new vCluster, vcluster deletes the skip
  keys, the namespaces' kube-root-ca.crt and the mappings
  (`postRestoreSnapshotDataMutation`). vk8s does not yet: it refuses an
  archive with skip keys and keeps the other two.
- Compaction on kine (D13) is not proven by the spike. Add it to the
  spike before the feature ships.
- The kine of the guest is loft's v0.14.16.vcluster.4; the spike used
  k3s-io v0.17.5. The spike did not run loft's build. Before the feature
  ships, run the same checks against the guest's kine (for example with
  the kine of the assets disk in place of the download).
