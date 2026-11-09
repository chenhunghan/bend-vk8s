import Base
import ../src/lib/sha256.bend as H
import ../src/standalone/snapshot.bend as S

# Spec for src/standalone/snapshot.bend: vcluster's snapshot archive and
# snapshot URLs (pkg/snapshot). Concrete laws transcribe
# pkg/snapshot/options_test.go, client_test.go, convert_test.go and
# restoreclient_test.go case by case; expected values are the Go tests' own
# or the output of vcluster's code (go test in pkg/snapshot, Go 1.27.3,
# vcluster a8ab30e). Tar vectors are Go archive/tar output.

# Fixtures
# --------

def snapshot.fx.rec(k: String, v: String) -> S.Snap.Rec:
  S.Rec{S.Snap.b(k), S.Snap.b(v)}

def snapshot.fx.val(k: String, v: String) -> S.Snap.Item:
  S.IVal{S.Snap.b(k), S.Snap.b(v)}

def snapshot.fx.nz.if(drop: Bool, c: U32, rest: +List<U32>) -> +List<U32>:
  match drop:
    case True{}:
      Nil{}
    case False{}:
      c <> rest

def snapshot.fx.nz.put(+c: U32, +rest: +List<U32>) -> +List<U32>:
  snapshot.fx.nz.if(List.is_empty(&2, U32, rest) && U32.is_eq(c, 0), c, rest)

# A byte list without its trailing zeros.
def snapshot.fx.nz(bs: +List<U32>) -> +List<U32>:
  match bs:
    case Nil{}:
      Nil{}
    case Con{+c, t}:
      snapshot.fx.nz.put(c, snapshot.fx.nz(t))

# An encoding as "<length> <hex without the trailing zeros>", or the error.
def snapshot.fx.hex(r: Result<&2, &2, String, List<&2, U32>>) -> String:
  match r:
    case Fail{m}:
      m
    case Done{+bs}:
      Nat.show(List.length(&2, U32, bs)) ++ " " ++ H.Sha256.hex(snapshot.fx.nz(bs))

def snapshot.fx.hexv.if(lower: Bool, x: U32) -> U32:
  match lower:
    case True{}:
      (x - 87 : U32)
    case False{}:
      (x - 48 : U32)

def snapshot.fx.hexv(c: Char) -> U32:
  match c:
    case Chr{+x}:
      snapshot.fx.hexv.if(U32.is_ge(x, 97), x)

# The bytes of a hex string.
def snapshot.fx.unhex(s: String) -> +List<U32>:
  match s:
    case SCon{a, SCon{b, t}}:
      (snapshot.fx.hexv(a) * 16 + snapshot.fx.hexv(b) : U32) <> snapshot.fx.unhex(t)
    case _:
      Nil{}

def snapshot.fx.keys.go(rs: List<&2, S.Snap.Rec>) -> List<&2, String>:
  match rs:
    case Nil{}:
      Nil{}
    case Con{S.Rec{k, v}, t}:
      S.Snap.s(k) <> snapshot.fx.keys.go(t)

# The keys of decoded records, or the error.
def snapshot.fx.keys(r: Result<&2, &2, String, List<&2, S.Snap.Rec>>) -> Result<&2, &2, String, List<&2, String>>:
  match r:
    case Fail{m}:
      Fail{m}
    case Done{rs}:
      Done{snapshot.fx.keys.go(rs)}

def snapshot.fx.s3(bucket: String, key: String, region: String, aki: String, sak: String) -> S.Snap.Loc:
  S.LS3{S.S3{S.Snap.b(bucket), S.Snap.b(key), False{}, S.Snap.b(aki), S.Snap.b(sak), Nil{}, S.Snap.b(region),
    Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, False{}, False{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}}}

def snapshot.fx.release() -> +List<U32>:
  S.Snap.b("{\"releaseName\":\"\",\"releaseNamespace\":\"\",\"chartName\":\"\",\"chartVersion\":\"\",\"values\":null}")

def snapshot.fx.request() -> +List<U32>:
  S.Snap.b("{\"metadata\":{\"name\":\"\",\"creationTimestamp\":null},\"spec\":{},\"status\":{\"error\":{}}}")

# A key/value archive's records from a live listing, or none.
def snapshot.fx.kv(r: Result<&2, &2, String, List<&2, S.Snap.Rec>>) -> List<&2, S.Snap.Rec>:
  match r:
    case Fail{m}:
      Nil{}
    case Done{rs}:
      rs

# options_test.go TestParse
# -------------------------

# "s3": the access key and secret are base64 in the URL.
law snapshot.parse.s3:
  {S.Snap.parse_vcluster(S.Snap.b("s3://my-bucket/my-key?region=eu-west-1&access-key-id=bXktYWNjZXNzLWtleS1pZA==&secret-access-key=bXktc2VjcmV0LWFjY2Vzcy1rZXk="))
    == Done{snapshot.fx.s3("my-bucket", "my-key", "eu-west-1", "my-access-key-id", "my-secret-access-key")}
    : Result<&2, &2, String, S.Snap.Loc>}

law snapshot.parse.container:
  {S.Snap.parse_vcluster(S.Snap.b("container:///my-path")) == Done{S.LContainer{S.Snap.b("/my-path")}}
    : Result<&2, &2, String, S.Snap.Loc>}

law snapshot.parse.oci:
  {S.Snap.parse_vcluster(S.Snap.b("oci://my-registry.com/my-repo?skip-client-credentials=true"))
    == Done{S.LOci{S.Oci{S.Snap.b("my-registry.com/my-repo"), Nil{}, Nil{}, True{}}}}
    : Result<&2, &2, String, S.Snap.Loc>}

law snapshot.parse.azure:
  {S.Snap.parse_vcluster(S.Snap.b("https://mysnapshotstorage.blob.core.windows.net/my-cluster-snapshots/snap-1.tar.gz"))
    == Done{S.LAzure{S.Snap.b("https://mysnapshotstorage.blob.core.windows.net/my-cluster-snapshots/snap-1.tar.gz")}}
    : Result<&2, &2, String, S.Snap.Loc>}

law snapshot.parse.s3_unexpected_option:
  {S.Snap.parse_vcluster(S.Snap.b("s3://my-bucket/my-key?region=eu-west-1&unexpected-option=true"))
    == Fail{"error parsing options: unknown parameter in url: unexpected-option"}
    : Result<&2, &2, String, S.Snap.Loc>}

# More of snapshot.Parse, as vcluster's code answers (go test).

law snapshot.parse.container_host:
  {S.Snap.parse_vcluster(S.Snap.b("container://host/path"))
    == Fail{"relative paths are not supported for container snapshots"} : Result<&2, &2, String, S.Snap.Loc>}

law snapshot.parse.container_opaque:
  {S.Snap.parse_vcluster(S.Snap.b("container:relative")) == Fail{"couldn't find path for url"}
    : Result<&2, &2, String, S.Snap.Loc>}

law snapshot.parse.container_escape:
  {S.Snap.parse_vcluster(S.Snap.b("container:///a%20b")) == Done{S.LContainer{S.Snap.b("/a b")}}
    : Result<&2, &2, String, S.Snap.Loc>}

law snapshot.parse.bad_escape:
  {S.Snap.parse_vcluster(S.Snap.b("container:///a%zzb"))
    == Fail{"error parsing snapshotURL container:///a%zzb: parse \"container:///a%zzb\": invalid URL escape \"%zz\""}
    : Result<&2, &2, String, S.Snap.Loc>}

law snapshot.parse.query_and_fragment:
  {S.Snap.parse_vcluster(S.Snap.b("CONTAINER:///a?x=1#frag")) == Done{S.LContainer{S.Snap.b("/a")}}
    : Result<&2, &2, String, S.Snap.Loc>}

law snapshot.parse.file_refused:
  {S.Snap.parse_vcluster(S.Snap.b("file:///tmp/x.tar.gz"))
    == Fail{"scheme needs to be one of oci, s3, container, https"} : Result<&2, &2, String, S.Snap.Loc>}

law snapshot.parse.oci_userinfo:
  {S.Snap.parse_vcluster(S.Snap.b("oci://user:pa%20ss@my-registry.com/my-repo:tag"))
    == Done{S.LOci{S.Oci{S.Snap.b("my-registry.com/my-repo:tag"), S.Snap.b("user"), S.Snap.b("pa ss"), False{}}}}
    : Result<&2, &2, String, S.Snap.Loc>}

law snapshot.parse.oci_no_repo:
  {S.Snap.parse_vcluster(S.Snap.b("oci://my-registry.com"))
    == Fail{"unexpected format, need oci://my-registry.com/my-repo"} : Result<&2, &2, String, S.Snap.Loc>}

law snapshot.parse.oci_bad_base64:
  {S.Snap.parse_vcluster(S.Snap.b("oci://my-registry.com/repo?password=bad!"))
    == Fail{"error parsing options: failed to decode base64 for field Password: illegal base64 data at input byte 3"}
    : Result<&2, &2, String, S.Snap.Loc>}

law snapshot.parse.oci_bad_bool:
  {S.Snap.parse_vcluster(S.Snap.b("oci://my-registry.com/repo?skip-client-credentials=yes"))
    == Fail{"error parsing options: failed to parse bool for field SkipClientCredentials: strconv.ParseBool: parsing \"yes\": invalid syntax"}
    : Result<&2, &2, String, S.Snap.Loc>}

law snapshot.parse.s3_no_key:
  {S.Snap.parse_vcluster(S.Snap.b("s3://my-bucket"))
    == Fail{"bucket key is missing from url, expected format: s3://BUCKET/KEY"} : Result<&2, &2, String, S.Snap.Loc>}

law snapshot.parse.s3_no_bucket:
  {S.Snap.parse_vcluster(S.Snap.b("s3:///key"))
    == Fail{"bucket name is missing from url, expected format: s3://BUCKET/KEY"} : Result<&2, &2, String, S.Snap.Loc>}

law snapshot.parse.s3_first_value:
  {S.Snap.parse_vcluster(S.Snap.b("s3://b/dir/k.tar.gz?region=a&region=b"))
    == Done{snapshot.fx.s3("b", "dir/k.tar.gz", "a", "", "")} : Result<&2, &2, String, S.Snap.Loc>}

law snapshot.parse.missing_scheme:
  {S.Snap.parse_vcluster(S.Snap.b(":foo"))
    == Fail{"error parsing snapshotURL :foo: parse \":foo\": missing protocol scheme"} : Result<&2, &2, String, S.Snap.Loc>}

law snapshot.parse.http_refused:
  {S.Snap.parse_vcluster(S.Snap.b("http://example.com/x"))
    == Fail{"scheme needs to be one of oci, s3, container, https"} : Result<&2, &2, String, S.Snap.Loc>}

# vk8s: file:///PATH, the rest as vcluster.

law snapshot.parse.vk8s_file:
  {S.Snap.parse(S.Snap.b("file:///tmp/x.tar.gz")) == Done{S.LFile{S.Snap.b("/tmp/x.tar.gz")}}
    : Result<&2, &2, String, S.Snap.Loc>}

law snapshot.parse.vk8s_container:
  {S.Snap.parse(S.Snap.b("container:///data/snapshot.tar.gz")) == Done{S.LContainer{S.Snap.b("/data/snapshot.tar.gz")}}
    : Result<&2, &2, String, S.Snap.Loc>}

# snapshotapi.Options.GetURL and Validate.

law snapshot.get_url.container:
  {S.Snap.get_url(S.LContainer{S.Snap.b("/my-path")}) == S.Snap.b("container:///my-path") : List<&2, U32>}

law snapshot.get_url.s3:
  {S.Snap.get_url(snapshot.fx.s3("my-bucket", "my-key", "eu-west-1", "a", "b")) == S.Snap.b("s3://my-bucket/my-key") : List<&2, U32>}

law snapshot.validate.container_empty:
  {S.Snap.validate(S.LContainer{Nil{}}, False{}) == Some{"path must be specified via container:///PATH"} : Maybe<&2, String>}

law snapshot.validate.s3_list:
  {S.Snap.validate(snapshot.fx.s3("b", "", "", "", ""), True{}) == None{} : Maybe<&2, String>}

law snapshot.validate.s3_key:
  {S.Snap.validate(snapshot.fx.s3("b", "", "", "", ""), False{}) == Some{"key must be specified via s3://BUCKET/KEY"} : Maybe<&2, String>}

# client_test.go
# --------------

# TestWriteKeyValueSnapshot_WritesRevision: the revision first, then the
# keys; the archive is a key/value snapshot.
law snapshot.write.revision:
  {S.Snap.write_kv(S.Snap.meta0(), Done{4242n}, [snapshot.fx.val("/registry/a", "va1"), snapshot.fx.val("/registry/b", "vb1")], Nil{}, False{})
    == Done{[snapshot.fx.rec("/vcluster/snapshot/revision", "4242"), snapshot.fx.rec("/registry/a", "va1"), snapshot.fx.rec("/registry/b", "vb1")]}
    : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

law snapshot.write.revision_kind:
  {S.Snap.kind(snapshot.fx.kv(S.Snap.write_kv(S.Snap.meta0(), Done{4242n},
    [snapshot.fx.val("/registry/a", "va1"), snapshot.fx.val("/registry/b", "vb1")], Nil{}, False{}))) == S.KKeyValue{} : S.Snap.Kind}

# TestWriteKeyValueSnapshot_DetectedAsKeyValueKind_WithReleaseAndRequest:
# the revision in the third slot is not the database.
law snapshot.write.release_request_kind:
  {S.Snap.kind(snapshot.fx.kv(S.Snap.write_kv(S.Meta{Some{snapshot.fx.release()}, Some{S.Rec{S.Snap.request_entry_key(), snapshot.fx.request()}}},
    Done{7n}, [snapshot.fx.val("/registry/a", "va1")], Nil{}, False{}))) == S.KKeyValue{} : S.Snap.Kind}

# TestSnapshotMetadataKeysCarryPrefix.
law snapshot.keys.release_prefix:
  {S.Snap.bprefix(S.Snap.release_key(), S.Snap.meta_prefix()) == True{} : Bool}

law snapshot.keys.request_prefix:
  {S.Snap.bprefix(S.Snap.request_key(), S.Snap.meta_prefix()) == True{} : Bool}

law snapshot.keys.db_prefix:
  {S.Snap.bprefix(S.Snap.db_key(), S.Snap.meta_prefix()) == True{} : Bool}

law snapshot.keys.skipkeys_prefix:
  {S.Snap.bprefix(S.Snap.skipkeys_key(), S.Snap.meta_prefix()) == True{} : Bool}

law snapshot.keys.revision_prefix:
  {S.Snap.bprefix(S.Snap.revision_key(), S.Snap.meta_prefix()) == True{} : Bool}

# TestWriteKeyValueSnapshot_SkipsPollutedMetadataKey.
law snapshot.write.polluted:
  {S.Snap.write_kv(S.Snap.meta0(), Done{4242n}, [snapshot.fx.val("/registry/a", "va1"), snapshot.fx.val("/vcluster/snapshot/revision", "999")], Nil{}, False{})
    == Done{[snapshot.fx.rec("/vcluster/snapshot/revision", "4242"), snapshot.fx.rec("/registry/a", "va1")]}
    : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

# TestWriteKeyValueSnapshot_CancelledSourceNeverReportsSuccess.
law snapshot.write.cancelled:
  {S.Snap.write_kv(S.Snap.meta0(), Done{1n}, [snapshot.fx.val("/registry/a", "va1"), snapshot.fx.val("/registry/b", "vb1")], Nil{}, True{})
    == Fail{"context: context canceled"} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

# TestWriteKeyValueSnapshot_CurrentRevisionError (and
# _NoGoroutineLeakOnEarlyError's input).
law snapshot.write.revision_error:
  {S.Snap.write_kv(S.Snap.meta0(), Fail{"boom"}, Nil{}, Nil{}, False{})
    == Fail{"failed to get current revision: boom"} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

# TestWriteKeyValueSnapshot_ListStreamError.
law snapshot.write.list_error:
  {S.Snap.write_kv(S.Snap.meta0(), Done{1n}, [snapshot.fx.val("/registry/a", "va1"), S.IErr{"boom"}], Nil{}, False{})
    == Fail{"failed to retrieve etcd items: boom"} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

# The tar stream writeKeyValueSnapshot writes for WritesRevision (gunzipped
# go test output: 4096 bytes).
law snapshot.write.revision_tar_length:
  {List.length(&2, U32, S.Snap.Tar.trailer()) == 1024n : Nat}

# convert_test.go
# ---------------

# TestConvertEtcdSnapshotToKeyValueSnapshot: the live keys of the database
# (b deleted and recreated) at its revision 6.
law snapshot.convert.basic:
  {S.Snap.convert([snapshot.fx.rec("/vcluster/snapshot/db", "db-bytes")],
    [snapshot.fx.rec("/registry/a", "va1"), snapshot.fx.rec("/registry/b", "vb2-recreated"), snapshot.fx.rec("/registry/c", "vc1")], 6n)
    == Done{[snapshot.fx.rec("/vcluster/snapshot/revision", "6"), snapshot.fx.rec("/registry/a", "va1"),
      snapshot.fx.rec("/registry/b", "vb2-recreated"), snapshot.fx.rec("/registry/c", "vc1")]}
    : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

# TestConvertEtcdSnapshotToKeyValueSnapshot_SkipKeys.
law snapshot.convert.skip_keys:
  {S.Snap.convert([snapshot.fx.rec("/vcluster/snapshot/db", "db-bytes"), snapshot.fx.rec("/vcluster/snapshot/skipkeys", "{\"/registry/skip\":{}}")],
    [snapshot.fx.rec("/registry/keep", "v1"), snapshot.fx.rec("/registry/skip", "v2")], 3n)
    == Done{[snapshot.fx.rec("/vcluster/snapshot/revision", "3"), snapshot.fx.rec("/registry/keep", "v1")]}
    : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

# TestConvertEtcdSnapshotToKeyValueSnapshot_ReleaseAndRequestPassthrough.
law snapshot.convert.passthrough:
  {S.Snap.convert([snapshot.fx.rec("/vcluster/snapshot/release", "{\"name\":\"my-release\"}"),
      snapshot.fx.rec("/vcluster/snapshot/request/v1beta1", "{\"apiVersion\":\"v1beta1\"}"),
      snapshot.fx.rec("/vcluster/snapshot/db", "db-bytes")],
    [snapshot.fx.rec("/registry/a", "v1")], 2n)
    == Done{[snapshot.fx.rec("/vcluster/snapshot/release", "{\"name\":\"my-release\"}"),
      snapshot.fx.rec("/vcluster/snapshot/request/v1beta1", "{\"apiVersion\":\"v1beta1\"}"),
      snapshot.fx.rec("/vcluster/snapshot/revision", "2"), snapshot.fx.rec("/registry/a", "v1")]}
    : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

# TestConvertEtcdSnapshotToKeyValueSnapshot_SkipsPollutedMetadataKey.
law snapshot.convert.polluted:
  {S.Snap.convert([snapshot.fx.rec("/vcluster/snapshot/db", "db-bytes")],
    [snapshot.fx.rec("/registry/a", "v1"), snapshot.fx.rec("/vcluster/snapshot/revision", "999")], 3n)
    == Done{[snapshot.fx.rec("/vcluster/snapshot/revision", "3"), snapshot.fx.rec("/registry/a", "v1")]}
    : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

# TestConvertEtcdSnapshotToKeyValueSnapshot_ExcludesNonPrefixedKeys.
law snapshot.convert.non_prefixed:
  {S.Snap.convert([snapshot.fx.rec("/vcluster/snapshot/db", "db-bytes")],
    [snapshot.fx.rec("/registry/a", "v2"), snapshot.fx.rec("registry/no-leading-slash", "v1")], 3n)
    == Done{[snapshot.fx.rec("/vcluster/snapshot/revision", "3"), snapshot.fx.rec("/registry/a", "v2")]}
    : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

# TestConvertEtcdSnapshotToKeyValueSnapshot_EmptyDatabase.
law snapshot.convert.empty:
  {S.Snap.convert([snapshot.fx.rec("/vcluster/snapshot/db", "db-bytes")], Nil{}, 0n)
    == Done{[snapshot.fx.rec("/vcluster/snapshot/revision", "0")]} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

# TestConvertEtcdSnapshotToKeyValueSnapshot_AlreadyKeyValueKind.
law snapshot.convert.already_kv:
  {S.Snap.convert([snapshot.fx.rec("/registry/pods/default/foo", "bar")], Nil{}, 0n)
    == Fail{"source snapshot is not an etcd snapshot (kind: KeyValueSnapshot)"} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

# TestParseEtcdSnapshotArchive_MissingDBStoreKey.
law snapshot.convert.missing_db:
  {Result.is_fail(&2, &2, String, S.Snap.Etcd, S.Snap.parse_etcd([snapshot.fx.rec("/vcluster/snapshot/release", "{}")])) == True{} : Bool}

law snapshot.convert.missing_db_message:
  {S.Snap.parse_etcd([snapshot.fx.rec("/vcluster/snapshot/release", "{}")])
    == Fail{"failed to find etcd snapshot in source archive"} : Result<&2, &2, String, S.Snap.Etcd>}

# TestParseEtcdSnapshotArchive_CleansUpDBFileOnLaterError: bad skip keys
# after the database fail (the temp file cleanup is host code's).
law snapshot.convert.bad_skip_keys:
  {Result.is_fail(&2, &2, String, S.Snap.Etcd, S.Snap.parse_etcd([snapshot.fx.rec("/vcluster/snapshot/db", "db-bytes"),
    snapshot.fx.rec("/vcluster/snapshot/skipkeys", "not-json")])) == True{} : Bool}

# TestParseEtcdSnapshotArchive_DuplicateDBStoreKey.
law snapshot.convert.duplicate_db:
  {S.Snap.parse_etcd([snapshot.fx.rec("/vcluster/snapshot/db", "db-bytes"), snapshot.fx.rec("/vcluster/snapshot/db", "db-bytes")])
    == Fail{"archive contains multiple \"/vcluster/snapshot/db\" entries"} : Result<&2, &2, String, S.Snap.Etcd>}

# restoreclient_test.go
# ---------------------

# TestDeleteExistingData.
law snapshot.delete_calls.embedded_etcd:
  {S.Snap.delete_calls(S.EmbeddedEtcd{}) == Nil{} : List<&2, String>}

law snapshot.delete_calls.embedded_database:
  {S.Snap.delete_calls(S.EmbeddedDatabase{}) == Nil{} : List<&2, String>}

law snapshot.delete_calls.deployed_etcd:
  {S.Snap.delete_calls(S.DeployedEtcd{}) == ["DeletePrefix(/)"] : List<&2, String>}

law snapshot.delete_calls.external_etcd:
  {S.Snap.delete_calls(S.ExternalEtcd{}) == ["DeletePrefix(/)"] : List<&2, String>}

law snapshot.delete_calls.external_database:
  {S.Snap.delete_calls(S.ExternalDatabase{}) == ["DeleteKeysWithPrefix(/)"] : List<&2, String>}

# TestDeleteMethodBeforeRestore.
law snapshot.delete_method.embedded_etcd:
  {S.Snap.DeleteMethod.name(S.Snap.delete_method(S.EmbeddedEtcd{})) == "none" : String}

law snapshot.delete_method.embedded_database:
  {S.Snap.DeleteMethod.name(S.Snap.delete_method(S.EmbeddedDatabase{})) == "none" : String}

law snapshot.delete_method.deployed_etcd:
  {S.Snap.DeleteMethod.name(S.Snap.delete_method(S.DeployedEtcd{})) == "range" : String}

law snapshot.delete_method.external_etcd:
  {S.Snap.DeleteMethod.name(S.Snap.delete_method(S.ExternalEtcd{})) == "range" : String}

law snapshot.delete_method.external_database:
  {S.Snap.DeleteMethod.name(S.Snap.delete_method(S.ExternalDatabase{})) == "key-by-key" : String}

# TestNeedsEtcdToKeyValueConversion.
law snapshot.convert_needed.etcd.embedded_etcd:
  {S.Snap.needs_conversion(S.KEtcd{}, S.EmbeddedEtcd{}) == False{} : Bool}

law snapshot.convert_needed.etcd.embedded_database:
  {S.Snap.needs_conversion(S.KEtcd{}, S.EmbeddedDatabase{}) == True{} : Bool}

law snapshot.convert_needed.etcd.deployed_etcd:
  {S.Snap.needs_conversion(S.KEtcd{}, S.DeployedEtcd{}) == True{} : Bool}

law snapshot.convert_needed.etcd.external_etcd:
  {S.Snap.needs_conversion(S.KEtcd{}, S.ExternalEtcd{}) == True{} : Bool}

law snapshot.convert_needed.etcd.external_database:
  {S.Snap.needs_conversion(S.KEtcd{}, S.ExternalDatabase{}) == True{} : Bool}

law snapshot.convert_needed.kv.embedded_etcd:
  {S.Snap.needs_conversion(S.KKeyValue{}, S.EmbeddedEtcd{}) == False{} : Bool}

law snapshot.convert_needed.kv.embedded_database:
  {S.Snap.needs_conversion(S.KKeyValue{}, S.EmbeddedDatabase{}) == False{} : Bool}

law snapshot.convert_needed.kv.deployed_etcd:
  {S.Snap.needs_conversion(S.KKeyValue{}, S.DeployedEtcd{}) == False{} : Bool}

law snapshot.convert_needed.kv.external_etcd:
  {S.Snap.needs_conversion(S.KKeyValue{}, S.ExternalEtcd{}) == False{} : Bool}

law snapshot.convert_needed.kv.external_database:
  {S.Snap.needs_conversion(S.KKeyValue{}, S.ExternalDatabase{}) == False{} : Bool}

# TestSnapshotRestoreBumpRevision.
law snapshot.bump.latest_greater:
  {S.Snap.bump(1500n, 1000n, 1000n) == 1500n : Nat}

law snapshot.bump.snapshot_greater:
  {S.Snap.bump(800n, 1000n, 1000n) == 1000n : Nat}

law snapshot.bump.equal:
  {S.Snap.bump(1000n, 1000n, 1000n) == 1000n : Nat}

law snapshot.bump.zeros:
  {S.Snap.bump(0n, 0n, 1000n) == 1000n : Nat}

law snapshot.bump.snapshot_zero:
  {S.Snap.bump(500n, 0n, 1000n) == 1500n : Nat}

# TestGetSnapshotArchiveKind, on the archive's entries.
law snapshot.kind.db_first:
  {S.Snap.kind([snapshot.fx.rec("/vcluster/snapshot/db", "db-bytes")]) == S.KEtcd{} : S.Snap.Kind}

law snapshot.kind.release_db:
  {S.Snap.kind([snapshot.fx.rec("/vcluster/snapshot/release", "{}"), snapshot.fx.rec("/vcluster/snapshot/db", "db-bytes")]) == S.KEtcd{} : S.Snap.Kind}

law snapshot.kind.release_request_db:
  {S.Snap.kind([snapshot.fx.rec("/vcluster/snapshot/release", "{}"), snapshot.fx.rec("/vcluster/snapshot/request/v1", "{}"),
    snapshot.fx.rec("/vcluster/snapshot/db", "db-bytes")]) == S.KEtcd{} : S.Snap.Kind}

law snapshot.kind.request_db:
  {S.Snap.kind([snapshot.fx.rec("/vcluster/snapshot/request/v1", "{}"), snapshot.fx.rec("/vcluster/snapshot/db", "db-bytes")]) == S.KEtcd{} : S.Snap.Kind}

law snapshot.kind.registry_first:
  {S.Snap.kind([snapshot.fx.rec("/registry/pods/default/foo", "v")]) == S.KKeyValue{} : S.Snap.Kind}

law snapshot.kind.release_registry:
  {S.Snap.kind([snapshot.fx.rec("/vcluster/snapshot/release", "{}"), snapshot.fx.rec("/registry/configmaps/default/x", "v")]) == S.KKeyValue{} : S.Snap.Kind}

law snapshot.kind.request_first:
  {S.Snap.kind([snapshot.fx.rec("/vcluster/snapshot/request/v1", "{}")]) == S.KKeyValue{} : S.Snap.Kind}

law snapshot.kind.release_request:
  {S.Snap.kind([snapshot.fx.rec("/vcluster/snapshot/release", "{}"), snapshot.fx.rec("/vcluster/snapshot/request/v1", "{}")]) == S.KKeyValue{} : S.Snap.Kind}

law snapshot.kind.release_request_registry:
  {S.Snap.kind([snapshot.fx.rec("/vcluster/snapshot/release", "{}"), snapshot.fx.rec("/vcluster/snapshot/request/v1", "{}"),
    snapshot.fx.rec("/registry/pods/default/foo", "v")]) == S.KKeyValue{} : S.Snap.Kind}

law snapshot.kind.exact_request_key:
  {S.Snap.kind([snapshot.fx.rec("/vcluster/snapshot/request", "{}")]) == S.KKeyValue{} : S.Snap.Kind}

law snapshot.kind.empty:
  {S.Snap.kind(Nil{}) == S.KKeyValue{} : S.Snap.Kind}

law snapshot.kind.only_release:
  {S.Snap.kind([snapshot.fx.rec("/vcluster/snapshot/release", "{}")]) == S.KKeyValue{} : S.Snap.Kind}

# TestGetSnapshotArchiveKind on tar streams: "gzip but not tar" and
# "empty tar.gz" (Go's empty archive: two zero blocks).
law snapshot.kind.not_tar:
  {S.Snap.kind_of_tar(S.Snap.b("this is not a tar stream")) == Fail{"read tar header: unexpected EOF"}
    : Result<&2, &2, String, S.Snap.Kind>}

law snapshot.kind.empty_tar:
  {S.Snap.kind_of_tar(S.Snap.zeros(1024n)) == Done{S.KKeyValue{}} : Result<&2, &2, String, S.Snap.Kind>}

# Go archive/tar vectors
# ----------------------

# writeArchiveEntry of ("/registry/a", "va1") and the trailer.
law snapshot.tar.one:
  {snapshot.fx.hex(S.Snap.Tar.encode([snapshot.fx.rec("/registry/a", "va1")]))
    == "2048 2f72656769737472792f61000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030363636003030303030303000303030303030300030303030303030303030330030303030303030303030300030313132373400203000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000303030303030300030303030303030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000766131" : String}

# A 131-byte key: USTAR with the prefix field.
law snapshot.tar.split:
  {snapshot.fx.hex(S.Snap.Tar.encode([snapshot.fx.rec("/registry/apiextensions.k8s.io/customresourcedefinitions/ssssssssssssssssssssssssssssssssssssssssssssssssssssssssssss/x.example.com", "v")]))
    == "2048 782e6578616d706c652e636f6d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030363636003030303030303000303030303030300030303030303030303030310030303030303030303030300030343234333500203000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000303030303030300030303030303030002f72656769737472792f617069657874656e73696f6e732e6b38732e696f2f637573746f6d7265736f75726365646566696e6974696f6e732f737373737373737373737373737373737373737373737373737373737373737373737373737373737373737373737373737373737373737373737373000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}

# A 149-byte key whose last part is 120 bytes: a PAX path record.
law snapshot.tar.pax:
  {snapshot.fx.hex(S.Snap.Tar.encode([snapshot.fx.rec("/registry/configmaps/default/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc", "v")]))
    == "3072 2f72656769737472792f636f6e6669676d6170732f64656661756c742f506178486561646572732e302f636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303030303000303030303030300030303030303030003030303030303030323337003030303030303030303030003033313130340020780000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000031353920706174683d2f72656769737472792f636f6e6669676d6170732f64656661756c742f6363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363630a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f72656769737472792f636f6e6669676d6170732f64656661756c742f63636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363633030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003033323437300020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}

# A non-ASCII key: PAX, and the record's length gains a digit.
law snapshot.tar.non_ascii:
  {snapshot.fx.hex(S.Snap.Tar.encode([snapshot.fx.rec("/é", "v")]))
    == "3072 2f506178486561646572732e3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000303030303030300030303030303030303031340030303030303030303030300030313032313600207800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000313220706174683d2fc3a90a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003030303036363600303030303030300030303030303030003030303030303030303031003030303030303030303030003030373236310020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076" : String}

law snapshot.tar.trailing_slash:
  {S.Snap.Tar.encode([snapshot.fx.rec("/registry/a/", "v")])
    == Fail{"archive/tar: cannot encode header: filename may not have trailing slash"} : Result<&2, &2, String, List<&2, U32>>}

law snapshot.tar.nul:
  {S.Snap.Tar.encode([S.Rec{[47, 114, 101, 103, 105, 115, 116, 114, 121, 47, 97, 0, 98], S.Snap.b("v")}])
    == Fail{"archive/tar: cannot encode header: invalid PAX record: \"path = /registry/a\\x00b\""} : Result<&2, &2, String, List<&2, U32>>}

law snapshot.tar.empty:
  {S.Snap.Tar.encode(Nil{}) == Done{S.Snap.zeros(1024n)} : Result<&2, &2, String, List<&2, U32>>}

# Go archive/tar's Reader on Go's archives and on broken input.
law snapshot.tar.decode_one:
  {snapshot.fx.keys(S.Snap.Tar.decode(S.Snap.app(snapshot.fx.unhex("2f72656769737472792f61000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030363636003030303030303000303030303030300030303030303030303030330030303030303030303030300030313132373400203000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000303030303030300030303030303030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000766131"), S.Snap.zeros(1533n))))
    == Done{["/registry/a"]} : Result<&2, &2, String, List<&2, String>>}

law snapshot.tar.decode_not_tar:
  {S.Snap.Tar.decode(S.Snap.b("this is not a tar stream")) == Fail{"unexpected EOF"} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

law snapshot.tar.decode_one_zero_block:
  {S.Snap.Tar.decode(S.Snap.zeros(512n)) == Done{Nil{}} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

law snapshot.tar.decode_zero_then_data:
  {S.Snap.Tar.decode(S.Snap.app(S.Snap.zeros(512n), List.replicate(U32, 512n, 1))) == Fail{"archive/tar: invalid tar header"}
    : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

law snapshot.tar.decode_nothing:
  {S.Snap.Tar.decode(Nil{}) == Done{Nil{}} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

law snapshot.tar.decode_truncated_data:
  {S.Snap.Tar.decode(List.take(&2, U32, snapshot.fx.unhex("2f72656769737472792f61000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030363636003030303030303000303030303030300030303030303030303030330030303030303030303030300030313132373400203000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000303030303030300030303030303030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000766131"), 514n)) == Fail{"unexpected EOF"}
    : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

law snapshot.tar.decode_no_trailer:
  {snapshot.fx.keys(S.Snap.Tar.decode(List.take(&2, U32, S.Snap.app(snapshot.fx.unhex("2f72656769737472792f61000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030363636003030303030303000303030303030300030303030303030303030330030303030303030303030300030313132373400203000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000303030303030300030303030303030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000766131"), S.Snap.zeros(600n)), 1024n)))
    == Done{["/registry/a"]} : Result<&2, &2, String, List<&2, String>>}

law snapshot.tar.decode_bad_checksum:
  {S.Snap.Tar.decode(88 <> List.drop(&2, U32, snapshot.fx.unhex("2f72656769737472792f61000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030363636003030303030303000303030303030300030303030303030303030330030303030303030303030300030313132373400203000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000303030303030300030303030303030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000766131"), 1n)) == Fail{"archive/tar: invalid tar header"}
    : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

# General laws
# ------------

# The record stream round-trips: what Go's tar.Writer accepts, its
# tar.Reader reads back as the same records, in order.
law snapshot.tar.roundtrip:
  for rs: List<&2, S.Snap.Rec>
  for bs: List<&2, U32>
  for h: {S.Snap.Tar.encode(rs) == Done{bs} : Result<&2, &2, String, List<&2, U32>>}
  {S.Snap.Tar.decode(bs) == Done{rs} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}

# The URL of a container:// location parses back to it, for an absolute
# path without control characters, '%', '?' or '#'.
law snapshot.url.container_roundtrip:
  for p: List<&2, U32>
  for h: {S.Snap.Url.plain_path(p) == True{} : Bool}
  {S.Snap.parse(S.Snap.get_url(S.LContainer{p})) == Done{S.LContainer{p}} : Result<&2, &2, String, S.Snap.Loc>}

# The same for vk8s's file:// locations.
law snapshot.url.file_roundtrip:
  for p: List<&2, U32>
  for h: {S.Snap.Url.plain_path(p) == True{} : Bool}
  {S.Snap.parse(S.Snap.get_url(S.LFile{p})) == Done{S.LFile{p}} : Result<&2, &2, String, S.Snap.Loc>}

# A live key/value snapshot is always read back as a key/value snapshot:
# the revision comes before any key.
law snapshot.write.kv_kind:
  for rev: Nat
  for items: List<&2, S.Snap.Item>
  for skip: List<&2, List<&2, U32>>
  for rs: List<&2, S.Snap.Rec>
  for h: {S.Snap.write_kv(S.Snap.meta0(), Done{rev}, items, skip, False{}) == Done{rs} : Result<&2, &2, String, List<&2, S.Snap.Rec>>}
  {S.Snap.kind(rs) == S.KKeyValue{} : S.Snap.Kind}

# An etcd snapshot is always read back as an etcd snapshot.
law snapshot.etcd.kind:
  for db: List<&2, U32>
  for skip: Maybe<&2, List<&2, List<&2, U32>>>
  {S.Snap.kind(S.Snap.etcd_archive(S.Snap.meta0(), db, skip)) == S.KEtcd{} : S.Snap.Kind}

# A key/value restore never puts a snapshot metadata key into the store.
law snapshot.restore.no_metadata:
  for rs: List<&2, S.Snap.Rec>
  for nv: Bool
  for pn: Bool
  {S.Snap.plan_clean(S.Snap.restore_plan(rs, nv, pn)) == True{} : Bool}

# Proposed: the PAX path record must fit the 11-digit octal size field of
# its extended header. Go's writeRawFile calls formatOctal(v7.size(),
# len(data)) ("Must be < 8GiB"); fitsInOctal(12, x) holds only for
# x < 1<<33 = 8^11, and otherwise Writer.WriteHeader returns
# ErrFieldTooLong, "archive/tar: header field too long" (Go 1.27.3
# src/archive/tar/writer.go, strconv.go, common.go). Digits are
# little-endian, as Snap.Oct.count gives them.

# fitsInOctal(12, 1<<33 - 1) == true: 11 octal digits fit.
law snapshot.tar.size_fits_11_digits:
  {S.Snap.Tar.size_fits([S.O7{}, S.O7{}, S.O7{}, S.O7{}, S.O7{}, S.O7{}, S.O7{}, S.O7{}, S.O7{}, S.O7{}, S.O7{}]) == True{} : Bool}

# fitsInOctal(12, 1<<33) == false: 8^11 needs 12 octal digits.
law snapshot.tar.size_fits_12_digits:
  {S.Snap.Tar.size_fits([S.O0{}, S.O0{}, S.O0{}, S.O0{}, S.O0{}, S.O0{}, S.O0{}, S.O0{}, S.O0{}, S.O0{}, S.O0{}, S.O1{}]) == False{} : Bool}

# A PAX record whose size does not fit is refused with ErrFieldTooLong,
# as Go refuses tar.Header{Name: <8 GiB key>}.
law snapshot.tar.pax_record_too_long:
  {S.Snap.Tar.entry.pax.fits(False{}, S.Snap.b("a"), S.Snap.b("10 path=a\n"), Nil{}) == Fail{"archive/tar: header field too long"}
    : Result<&2, &2, String, List<&2, U32>>}

# The same refusal for the header-only writer of a streamed file.
law snapshot.tar.pax_header_too_long:
  {S.Snap.Tar.headers.pax.fits(False{}, S.Snap.b("a"), S.Snap.b("10 path=a\n"), Nil{}) == Fail{"archive/tar: header field too long"}
    : Result<&2, &2, String, List<&2, U32>>}
