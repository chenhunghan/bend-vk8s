# Open snapshot archive

Reference: loft-sh/vcluster at a8ab30eab6f27b183a80783f4e5854c1a2eb6ef5.
Implementation: `src/standalone/snapshot.bend`. This is a pure library;
it does not connect the CLI to a store or replace the VM snapshot format.

## Format and host boundary

`pkg/snapshot/client.go` writes gzip at level 3 around a tar stream.
There is no second binary key/value framing inside tar. Each regular file
is one record: the tar name is the key and the file bytes are the value.
`writeArchiveEntry` uses mode 0666. Go chooses USTAR, a USTAR prefix, or
PAX for long or non-ASCII names. Headers and payloads use 512-byte blocks.
The writer closes with two zero blocks. Values can contain arbitrary bytes.

The order is:

1. Optional `/vcluster/snapshot/release`: JSON of `HelmRelease`. It includes
   release name/namespace, chart name/version, and `values`. The latter is
   a Go `[]byte`, hence base64 in JSON. There is no separate config file.
2. Optional `/vcluster/snapshot/request/v1beta1`: snapshot request JSON.
3. Embedded etcd: `/vcluster/snapshot/db`, the raw etcd database snapshot,
   then optional `/vcluster/snapshot/skipkeys`, a JSON object whose keys
   identify records to omit during restore.
4. Other stores: `/vcluster/snapshot/revision`, a decimal revision, then
   each key/value record from the source. Skip keys and keys under
   `/vcluster/snapshot/` are omitted.

`Snap.Tar.encode` and `decode` operate on the uncompressed tar bytes.
`Snap.Tar.file_header` permits a host to stream a large database payload.
The host must supply gzip/deflate, CRC checking, object storage, file
cleanup, database reads, cancellation, and write-error propagation.
`Snap.convert` takes the live records and revision of a database already
opened by the host. It does not decode Bolt database bytes.

The byte representation is `+List<U32>`; callers must supply bytes.
The implementation rejects payloads of 8 GiB or more. The decoder lacks
base-256 sizes and sparse-file semantics. It reads PAX path and size;
other PAX fields do not change the record model. These are compatibility
limits, not claims of a complete general-purpose tar implementation.

## URLs and quirks

`Snap.parse_vcluster` follows `pkg/snapshot/options.go`: `oci`, `s3`,
`container`, and `https` (Azure). Literal `azure://` and `file://` are
not accepted by that upstream parser. `Snap.parse` adds vk8s `file:///PATH`.
`container:///PATH` refers to a path where the snapshot process runs;
`file:///PATH` refers to the vk8s host. Transport IO remains a host task.

S3 and OCI query fields follow the vendored API field tags, including
base64 credentials and Go boolean spellings. Unknown fields fail. OCI
repository paths use `path.Join`. Container URLs reject a host, discard
query/fragment, and percent-decode their path. HTTPS retains the complete
URL. No Pro binary or Pro implementation is used.

`Snap.get_url` deliberately follows upstream `Options.GetURL`, which
returns only S3 bucket/key or OCI repository, dropping options and
credentials. Even a container path containing `?`, `#`, or `%` cannot
round-trip through upstream GetURL unchanged. The two general URL laws
therefore cover plain absolute file/container paths only. A lossless
options serializer and its general law remain outstanding; GetURL must
retain its upstream behavior.

## Restore order

The CLI stops the standalone service before restore and restarts it even
when restore fails (`pkg/cli/restore_helm.go`). The host must enforce this.
The archive discriminator skips an optional release and request, then
checks for the database key. Other entries mean a key/value archive.

An etcd archive restored to embedded etcd uses the native restore route.
Other stores first convert an etcd archive to live key/value records.
Embedded stores remove files; deployed/external etcd delete a range;
external databases delete keys separately because kine lacks range delete.

`Snap.restore_plan` returns ordered puts, skips snapshot metadata, and
stops at an empty key. For a new vcluster it also skips mappings and the
namespace root CA ConfigMaps. Pods require node/status transformation
unless private nodes are used. The host must perform that transformation;
the plan marks those puts. Compact only after at least one put.

Native etcd restore bumps the revision by at least 1000, or
`latest - snapshot + 1000` when latest is higher, and marks it compacted.
After restore, delete skip keys, then new-cluster root CA ConfigMaps and
mappings, then reset pods unless private nodes are used.

## Verification and remaining work

This branch carries the three existing snapshot commits from
`origin/feat/snapshot-archive` onto main without rewriting that branch.
The original test commit precedes the implementation. Its fixture comments
record Go 1.27.3 and upstream a8ab30e as the source. This round checked the
source and kept those fixed vectors; it did not rerun Go or Bend tests.
The factory rules prohibit local builds and tests. CI is the oracle.

There are 109 concrete laws and six general laws. All of them prove,
also under `bend proofs/snapshot.bend --verdict`, and
`laws/done/snapshot` marks the module done.

The law was false for the earlier encoder. `Snap.Tar.pax` writes the
size of the PAX path record with `Snap.Tar.octal(11n, Snap.Oct.count(r))`,
and no check limited that count to 11 octal digits. Go's `writeRawFile`
calls `formatOctal(v7.size(), len(data))` ("Must be < 8GiB") and returns
`ErrFieldTooLong` when the record does not fit.

Counterexample for the earlier encoder: one record whose key is 8^11 =
8589934592 bytes of `a`, with an empty value. The key is longer than 100
bytes and has no '/', so `Snap.Tar.name` gives `NPax{}`. The PAX record
is 8589934609 bytes, which needs 12 octal digits. `Snap.Tar.octal` writes
13 bytes, and the extended header has 513 bytes. `Snap.Tar.encode`
returned `Done{bs}`, but the decoder reads the checksum field one byte
late, and `Snap.Tar.decode(bs)` is `Fail{"archive/tar: invalid tar
header"}`.

The encoder now matches Go. `Snap.Tar.entry.pax` and
`Snap.Tar.headers.pax` check the record digits with `Snap.Tar.size_fits`
(Go's `fitsInOctal(12, n)`) and fail with "archive/tar: header field too
long" when the record does not fit. The proposed concrete laws
`snapshot.tar.size_fits_11_digits`, `size_fits_12_digits`,
`pax_record_too_long` and `pax_header_too_long` record this. The law
`snapshot.tar.roundtrip` did not change.

`proofs/snapshot.bend` proves `snapshot.tar.roundtrip` by induction over
the records (`rt.enc`). An encoded archive is the entries of the records,
then the trailer. For one entry (`rt.ent`), the proof follows
`Snap.Tar.name`: a USTAR header with the name, a USTAR header with a
prefix, or a PAX extended header whose path record precedes the file
header. Its lemmas:

- Each header is 512 bytes (`rt.len_file`, `rt.len_pax`). `rt.F(n, s)`
  writes a field of n bytes as n explicit cells, so the checker slices a
  header without knowing the name.
- The decoder collects a header byte by byte (`rt.hread`) and parses it
  (`rt.hdr_file`, `rt.hdr_pax`). The checksum field is the one the
  decoder computes, so its fast path holds (`rt.cks_ok`). The size field
  holds the value's octal length (`rt.num_size`, `rt.val_count`).
- The name and prefix fields, cut at their first NUL, give the key back
  (`rt.cnf`). A USTAR prefix split joins back to the key
  (`rt.split_name`, from the invariant `rt.sg` of `Snap.Tar.split.go`).
- The data is read byte by byte (`rt.dread`), then the padding to the
  next block (`rt.pad_k`).
- The PAX record "<n> path=<key>\n" parses back to the key
  (`rt.px_full`): its decimal length is n (`rt.pin`), and n is the
  record's length (`rt.px_len`).
- The trailer is two zero blocks (`rt.trailer`).

The concrete laws `snapshot.tar.pax` and `snapshot.tar.non_ascii` ran
out of the verdict kernel's fuel when evaluated in one step. Their laws
did not change. Their proofs now take the hex digits of each block as
a lemma of its own (parts of the laws' expected strings) and join them
with `rt.fxhex`, `rt.nz_app` and `rt.hex_app`.

The following table records coverage, including gaps. A pure result law
cannot establish goroutine lifetime, file cleanup, SQL effects, or network
credential handling. Those require host tests in addition to pure laws.
All law names below have the prefix `snapshot.`.

| Upstream test or cases | Laws or remaining coverage |
| --- | --- |
| options `TestParse`: s3, container, oci, azure, s3 unexpected option | `parse.s3`, `parse.container`, `parse.oci`, `parse.azure`, `parse.s3_unexpected_option` |
| client `WritesRevision` | `write.revision`, `write.revision_kind`; executable tar digest |
| client `DetectedAsKeyValueKind_WithReleaseAndRequest` | `write.release_request_kind` |
| client `SnapshotMetadataKeysCarryPrefix`: release, request, db, skipkeys, revision | `keys.release_prefix`, `keys.request_prefix`, `keys.db_prefix`, `keys.skipkeys_prefix`, `keys.revision_prefix` |
| client `SkipsPollutedMetadataKey` | `write.polluted` |
| client `CancelledSourceNeverReportsSuccess` | `write.cancelled`; host upload cancellation untested |
| client `CurrentRevisionError` | `write.revision_error` |
| client `ListStreamError` | `write.list_error` |
| client `NoGoroutineLeakOnEarlyError` | Error input: `write.revision_error`; goroutine cleanup untested |
| convert `ConvertEtcdSnapshotToKeyValueSnapshot` | `convert.basic`; host database extraction untested |
| convert `SkipKeys` | `convert.skip_keys` |
| convert `ReleaseAndRequestPassthrough` | `convert.passthrough` |
| convert `SkipsPollutedMetadataKey` | `convert.polluted` |
| convert `ExcludesNonPrefixedKeys` | `convert.non_prefixed` |
| convert `EmptyDatabase` | `convert.empty` |
| convert `AlreadyKeyValueKind` | `convert.already_kv` |
| convert `ParseEtcdSnapshotArchive_MissingDBStoreKey` | `convert.missing_db`, `convert.missing_db_message` |
| convert `Pagination`: limit-1, limit, limit+1 | Not covered: host source pagination |
| convert `CleansUpDBFileOnLaterError` | `convert.bad_skip_keys`; cleanup untested |
| convert `DuplicateDBStoreKey` | `convert.duplicate_db` |
| convert `SinkFailureDoesNotOutliveStore` | Not covered: host sink lifetime |
| restore `DeleteExistingData`: embedded etcd, embedded database, deployed etcd, external etcd, external database | `delete_calls.embedded_etcd`, `.embedded_database`, `.deployed_etcd`, `.external_etcd`, `.external_database` |
| restore `DeleteExistingData_Error` | Not covered: host effect result |
| restore `DeleteMethodBeforeRestore`: same five stores | `delete_method.embedded_etcd`, `.embedded_database`, `.deployed_etcd`, `.external_etcd`, `.external_database` |
| restore `NeedsEtcdToKeyValueConversion`: etcd archive, all five stores | `convert_needed.etcd.embedded_etcd`, `.embedded_database`, `.deployed_etcd`, `.external_etcd`, `.external_database` |
| restore `NeedsEtcdToKeyValueConversion`: key/value archive, all five stores | `convert_needed.kv.embedded_etcd`, `.embedded_database`, `.deployed_etcd`, `.external_etcd`, `.external_database` |
| restore `SnapshotRestoreBumpRevision`: latest greater, snapshot greater, equal, all zeros, snapshot and bump zero | `bump.latest_greater`, `.snapshot_greater`, `.equal`, `.zeros`, `.snapshot_zero` |
| kind: DB first; release/DB; release/request/DB; request/DB | `kind.db_first`, `.release_db`, `.release_request_db`, `.request_db` |
| kind: registry first; release/registry; request first; only request; release/request; release/request/registry | `kind.registry_first`, `.release_registry`, `.request_first` (both request-only cases), `.release_request`, `.release_request_registry` |
| kind: exact RequestStoreKey; gzip but not tar; empty tar; only release | `kind.exact_request_key`, `.not_tar`, `.empty_tar`, `.only_release` |
| kind: missing file; not gzip; empty file | Not covered: host file and gzip reader |
| SQLite latest revision: missing file; no schema; empty table; three keys; corrupt file | Not covered: host SQL |
| SQLite write revision: empty table; populated table | Not covered: host SQL |
| SQLite schema: absent; present; corrupt file | Not covered: host SQL |
| `NewRestoreEtcdClientRefusesServingEmbeddedDatabase` | Not covered: host reachability and file effects |
| controller `CancelPreviousRequests`: five cases | Not covered: request controller |
| controller `ResolveSnapshotOptions_*`: all credential, overlay, and fallback cases | Not covered: controller/Pro seam; Pro features remain no-ops |

Additional `parse.*`, `get_url.*`, `validate.*`, `tar.*` laws encode source
quirks and Go archive/tar vectors. `tests/snapshot.bend` also checks payload
block boundaries, PAX length boundaries, mixed tar entries, restore plans,
mutation order, peer URLs, argument errors, and streamed file headers.
