import Base
import ./bin_file.bend as B
import ../src/standalone/snapshot.bend as S
import bend-kube-runtime@0.12.0.0/src/json.bend as J

# The host side of the opt-in open-format snapshot
# =================================================
#
# vcluster's archive (pkg/snapshot: gzip -3 around a tar stream, one entry
# per record) made from and turned into the files that the guest and the
# host exchange in a cluster's share/snapshot/ (docs/ref/snapshot-decisions.md
# D10-D13). Every tar byte comes from the proven codec of
# src/standalone/snapshot.bend:
#
# - export, embedded etcd: Snap.Tar.file_header of /vcluster/snapshot/db for
#   the size of the guest's `etcdctl snapshot save` file, the file itself
#   streamed (perl, O_NOFOLLOW, exactly that size), then Snap.Tar.pad_after
#   zeros and the trailer. That is Snap.Tar.encode(Snap.etcd_archive(meta0,
#   db, None)) without holding the database in memory (Open.check).
# - export, kine: the guest's -w json pages decoded (base64), the first key
#   of every page after the first dropped (it repeats the previous page's
#   last key), then Snap.write_kv with the count-only revision and
#   Snap.encode.
# - restore: the first tar entry tells the VM format (metadata.json) from
#   the open one (D2). An etcd archive (getSnapshotArchiveKind: an optional
#   release, an optional request, then /vcluster/snapshot/db) gives the db
#   file, copied out of the tar at its offset; a key/value archive gives the
#   puts file of Snap.restore_plan(new vCluster, private nodes) (D13).
#
# The share is the guest's: files are opened with O_NOFOLLOW and must be
# regular (security review F4). vk8s writes no release, request or skip
# keys (D7). host/vk8s.bend and tests/snapshot_open_build.bend use this
# module.

def Open.R(-A: Data) -> Type:
  Result<&2, &2, String, A>

# Shell
# -----

def Open.sh.status(ok: Bool, out: String, err: String) -> Open.R(String):
  match ok:
    case True{}:
      Done{out}
    case False{}:
      Fail{String.trim(err ++ out)}

def Open.sh.got(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> Open.R(String):
  match r:
    case Fail{(c, m)}:
      Fail{m}
    case Done{(st, (out, err))}:
      Open.sh.status(U32.is_eq(st, 0), out, err)

# A /bin/sh script with positional arguments $1.. (never spliced into the
# script text), up to an hour.
def Open.sh(script: String, args: List<String>) -> IO(Open.R(String)):
  do IO<Open.R(String)>:
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/bin/sh",
      Con{"-c", Con{script, Con{"sh", args}}}, "", 1048576, 3600000)
    return Open.sh.got(r)

# perl PATH OFFSET N: exactly N bytes of the regular file PATH from OFFSET
# to stdout, opened with O_NOFOLLOW; fails on a short file.
def Open.perl_copy() -> String:
  "use Fcntl; my ($p, $o, $n) = @ARGV; sysopen(my $f, $p, O_RDONLY | O_NOFOLLOW) or die \"open $p: $!\\n\"; "
  ++ "-f $f or die \"$p is not a regular file\\n\"; binmode $f; binmode STDOUT; sysseek($f, $o, 0) or die \"seek $p: $!\\n\"; "
  ++ "while ($n > 0) { my $r = sysread($f, my $b, $n < 1048576 ? $n : 1048576); die \"$p is shorter than expected\\n\" unless $r; "
  ++ "print $b or die \"write: $!\\n\"; $n -= $r; } close STDOUT or die \"write: $!\\n\";"

# Results
# -------

def Open.bin.r(-A: Data, r: B.BinFile.Res(A), +what: String) -> Open.R(A):
  match r:
    case Fail{(c, m)}:
      Fail{what ++ ": " ++ m}
    case Done{x}:
      Done{x}

# Runs next when r succeeded.
def Open.then(-A: Data, r: Open.R(Unit), next: IO(Open.R(A))) -> IO(Open.R(A)):
  match r:
    case Fail{m}:
      IO.pure(Open.R(A), Fail{m})
    case Done{u}:
      next

def Open.bin_then(-A: Data, r: B.BinFile.Res(Unit), +what: String, next: IO(Open.R(A))) -> IO(Open.R(A)):
  Open.then(A, Open.bin.r(Unit, r, what), next)

def Open.unit(r: Open.R(String)) -> Open.R(Unit):
  match r:
    case Fail{m}:
      Fail{m}
    case Done{s}:
      Done{Unit{}}

# The whole regular file at path (O_NOFOLLOW), at most max bytes.
def Open.read(+path: String, +max: U32) -> IO(Open.R(List<&2, U32>)):
  do IO<Open.R(List<&2, U32>)>:
    r : B.BinFile.Res(List<&2, U32>) <- B.BinFile.read_all(path, max)
    return Open.bin.r(List<&2, U32>, r, "could not read " ++ path)

def Open.text.of(r: Open.R(List<&2, U32>)) -> Open.R(String):
  match r:
    case Fail{m}:
      Fail{m}
    case Done{bs}:
      Done{S.Snap.s(bs)}

def Open.text(+path: String, +max: U32) -> IO(Open.R(String)):
  do IO<Open.R(String)>:
    r : Open.R(List<&2, U32>) <- Open.read(path, max)
    return Open.text.of(r)

def Open.size.got(p: File & B.BinFile.Res(U32)) -> IO(B.BinFile.Res(U32)):
  B.BinFile.end(U32, p)

def Open.size.opened(r: B.BinFile.Res(File)) -> IO(B.BinFile.Res(U32)):
  match r:
    case Fail{e}:
      IO.pure(B.BinFile.Res(U32), Fail{e})
    case Done{f}:
      do IO<B.BinFile.Res(U32)>:
        p : File & B.BinFile.Res(U32) <- B.BinFile.size(f)
        Open.size.got(p)

# The size of the regular file at path (O_NOFOLLOW; under 4 GiB).
def Open.size(+path: String) -> IO(Open.R(U32)):
  do IO<Open.R(U32)>:
    r : B.BinFile.Res(File) <- B.BinFile.open(path)
    s : B.BinFile.Res(U32) <- Open.size.opened(r)
    return Open.bin.r(U32, s, "could not read " ++ path)

def Open.range.opened(r: B.BinFile.Res(File), +at: U32, +n: U32) -> IO(B.BinFile.Res(List<&2, U32>)):
  match r:
    case Fail{e}:
      IO.pure(B.BinFile.Res(List<&2, U32>), Fail{e})
    case Done{f}:
      do IO<B.BinFile.Res(List<&2, U32>)>:
        p : File & B.BinFile.Res(List<&2, U32>) <- B.BinFile.read(f, at, n)
        B.BinFile.end(List<&2, U32>, p)

# Up to n bytes (at most 16 MiB) of the regular file at path from at;
# fewer only at its end.
def Open.range(+path: String, +at: U32, +n: U32) -> IO(Open.R(List<&2, U32>)):
  do IO<Open.R(List<&2, U32>)>:
    r : B.BinFile.Res(File) <- B.BinFile.open(path)
    p : B.BinFile.Res(List<&2, U32>) <- Open.range.opened(r, at, n)
    return Open.bin.r(List<&2, U32>, p, "could not read " ++ path)

def Open.nat.of(m: Maybe<&2, Nat>, +what: String, +s: String) -> Open.R(Nat):
  match m:
    case None{}:
      Fail{what ++ " is not a number: " ++ String.quote(s)}
    case Some{n}:
      Done{n}

# A decimal file's number (the guest's revision and pages files).
def Open.nat.trimmed(+what: String, +t: String) -> Open.R(Nat):
  Open.nat.of(S.Snap.Dec.parse_int(S.Snap.b(t)), what, t)

def Open.nat(+what: String, s: String) -> Open.R(Nat):
  Open.nat.trimmed(what, String.trim(s))

# Export, embedded etcd
# ---------------------

# The bytes after the database: its padding to the next block and the two
# zero blocks that end the archive.
def Open.etcd_tail(+n: Nat) -> List<&2, U32>:
  S.Snap.app(S.Snap.zeros(S.Snap.Tar.pad_after(n)), S.Snap.Tar.trailer())

# The header of the database entry: Snap.Tar.file_header of
# /vcluster/snapshot/db for n bytes (writeEtcdSnapshot's only entry).
def Open.etcd_head(n: Nat) -> Open.R(List<&2, U32>):
  S.Snap.Tar.file_header(S.Snap.db_key(), n)

# The archive of a database held in memory, as the streamed export writes
# it: header, data, tail. Open.check compares it with Snap.Tar.encode.
def Open.etcd_bytes.go(h: Open.R(List<&2, U32>), +db: List<&2, U32>) -> Open.R(List<&2, U32>):
  match h:
    case Fail{m}:
      Fail{m}
    case Done{hd}:
      Done{S.Snap.app(hd, S.Snap.app(db, Open.etcd_tail(List.length(&2, U32, db))))}

def Open.etcd_bytes(+db: List<&2, U32>) -> Open.R(List<&2, U32>):
  Open.etcd_bytes.go(Open.etcd_head(List.length(&2, U32, db)), db)

# head, the database (exactly n bytes) and tail through gzip -3 into out,
# mode 0600, written aside and renamed.
def Open.gz_etcd_sh() -> String:
  "h=$1; db=$2; n=$3; t=$4; out=$5; e=$6; rm -f \"$out.tmp\" \"$e\"; "
  ++ "(umask 077; { cat \"$h\" && perl -e \"$7\" \"$db\" 0 \"$n\" && cat \"$t\" || echo failed > \"$e\"; } | gzip -3 > \"$out.tmp\") "
  ++ "&& [ ! -e \"$e\" ] && chmod 600 \"$out.tmp\" && mv -f \"$out.tmp\" \"$out\" || { rm -f \"$out.tmp\"; echo \"could not write $out\" >&2; exit 1; }"

def Open.export_etcd.gz(+exp: String, +stage: String, +out: String, +n: U32) -> IO(Open.R(Unit)):
  do IO<Open.R(Unit)>:
    r : Open.R(String) <- Open.sh(Open.gz_etcd_sh(), [stage ++ "/head.bin", exp ++ "/db", U32.show(n), stage ++ "/tail.bin", out,
      stage ++ "/gz.failed", Open.perl_copy()])
    return Open.unit(r)

def Open.export_etcd.head(h: Open.R(List<&2, U32>), +exp: String, +stage: String, +out: String, +n: U32) -> IO(Open.R(Unit)):
  match h:
    case Fail{m}:
      IO.pure(Open.R(Unit), Fail{"could not write the archive header: " ++ m})
    case Done{hd}:
      do IO<Open.R(Unit)>:
        a : B.BinFile.Res(Unit) <- B.BinFile.write(stage ++ "/head.bin", hd)
        b : B.BinFile.Res(Unit) <- B.BinFile.write(stage ++ "/tail.bin", Open.etcd_tail(U32.to_nat(n)))
        Open.bin_then(Unit, a, "could not write " ++ stage ++ "/head.bin",
          Open.bin_then(Unit, b, "could not write " ++ stage ++ "/tail.bin", Open.export_etcd.gz(exp, stage, out, n)))

def Open.export_etcd.sized(s: Open.R(U32), +exp: String, +stage: String, +out: String) -> IO(Open.R(Unit)):
  match s:
    case Fail{m}:
      IO.pure(Open.R(Unit), Fail{m})
    case Done{+n}:
      Open.export_etcd.head(Open.etcd_head(U32.to_nat(n)), exp, stage, out, n)

def Open.export_etcd(+exp: String, +stage: String, +out: String) -> IO(Open.R(Unit)):
  do IO<Open.R(Unit)>:
    s : Open.R(U32) <- Open.size(exp ++ "/db")
    Open.export_etcd.sized(s, exp, stage, out)

# Export, kine
# ------------


def Open.kv.go(k: Result<&2, &2, Nat, List<&2, U32>>, v: Result<&2, &2, Nat, List<&2, U32>>) -> S.Snap.Item:
  match k v:
    case Done{kb} Done{vb}:
      S.IVal{kb, vb}
    case Fail{i} _:
      S.IErr{"a listed key is not base64 (byte " ++ Nat.show(i) ++ ")"}
    case _ Fail{i}:
      S.IErr{"a listed value is not base64 (byte " ++ Nat.show(i) ++ ")"}

def Open.b64(+j: J.Json, +field: String) -> Result<&2, &2, Nat, List<&2, U32>>:
  S.Snap.B64.decode(S.Snap.b(J.Json.str_or(J.Json.get(j, field), "")))

# One kv of etcdctl -w json: base64 key and value (an empty value is
# absent: omitempty).
def Open.kv(+j: J.Json) -> S.Snap.Item:
  Open.kv.go(Open.b64(j, "key"), Open.b64(j, "value"))

def Open.kvs(js: List<&2, J.Json>) -> List<&2, S.Snap.Item>:
  match js:
    case Nil{}:
      Nil{}
    case Con{+j, t}:
      Con{Open.kv(j), Open.kvs(t)}

def Open.item_key(+i: S.Snap.Item) -> List<&2, U32>:
  match i:
    case S.IVal{k, v}:
      k
    case S.IErr{m}:
      Nil{}

# The key of the last item, or prev when there is none.
def Open.last_key(xs: List<&2, S.Snap.Item>, +prev: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      prev
    case Con{+i, t}:
      Open.last_key(t, Open.item_key(i))

def Open.drop_first.if(same: Bool, t: List<&2, S.Snap.Item>) -> List<&2, S.Snap.Item>:
  match same:
    case True{}:
      t
    case False{}:
      [S.IErr{"a page does not start at the previous page's last key"}]

# A page after the first starts at the previous page's last key (the guest
# cannot pass vcluster's last key + NUL through argv): that key goes.
def Open.drop_first(first: Bool, +prev: List<&2, U32>, xs: List<&2, S.Snap.Item>) -> List<&2, S.Snap.Item>:
  match first xs:
    case True{} ys:
      ys
    case False{} Nil{}:
      [S.IErr{"a page after the first is empty"}]
    case False{} Con{+i, t}:
      Open.drop_first.if(S.Snap.beq(Open.item_key(i), prev), t)

def Open.items.kvs(first: Bool, +prev: List<&2, U32>, +xs: List<&2, S.Snap.Item>,
  more: List<&2, U32> -> List<&2, S.Snap.Item>) -> List<&2, S.Snap.Item>:
  List.append(&2, S.Snap.Item, Open.drop_first(first, prev, xs), more(Open.last_key(xs, prev)))

def Open.items.page(r: Open.R(J.Json), first: Bool, +prev: List<&2, U32>,
  more: List<&2, U32> -> List<&2, S.Snap.Item>) -> List<&2, S.Snap.Item>:
  match r:
    case Fail{m}:
      [S.IErr{"a page is not JSON: " ++ m}]
    case Done{j}:
      Open.items.kvs(first, prev, Open.kvs(J.Json.items(J.Json.get(j, "kvs"))), more)

# The listed keys of the pages, in order (vcluster's listStream); prev is
# the previous page's last key.
def Open.items(pages: List<&2, String>, first: Bool, +prev: List<&2, U32>) -> List<&2, S.Snap.Item>:
  match pages:
    case Nil{}:
      Nil{}
    case Con{p, t}:
      Open.items.page(J.Json.parse(p), first, prev, k => Open.items(t, False{}, k))

def Open.kv_archive.go(r: Open.R(List<&2, S.Snap.Rec>)) -> Open.R(List<&2, U32>):
  match r:
    case Fail{m}:
      Fail{m}
    case Done{rs}:
      S.Snap.encode(rs)

# The tar of a key/value archive (writeKeyValueSnapshot): the count-only
# get's revision (the revision file), then every listed key. No release,
# no request, no skip keys (D7).
def Open.kv_archive(rev: String, pages: List<&2, String>) -> Open.R(List<&2, U32>):
  Open.kv_archive.go(S.Snap.write_kv(S.Snap.meta0(), Open.nat("the revision", rev), Open.items(pages, True{}, Nil{}), Nil{}, False{}))

def Open.pages.next(r: Open.R(String), acc: List<&2, String>, again: List<&2, String> -> IO(Open.R(List<&2, String>))) ->
  IO(Open.R(List<&2, String>)):
  match r:
    case Fail{m}:
      IO.pure(Open.R(List<&2, String>), Fail{m})
    case Done{s}:
      again(Con{s, acc})

# fuel pages from page-i.json; acc holds those read, the last first.
def Open.pages(fuel: Nat, +i: Nat, +exp: String, acc: List<&2, String>) -> IO(Open.R(List<&2, String>)):
  match fuel:
    case 0n:
      IO.pure(Open.R(List<&2, String>), Done{List.reverse(&2, String, acc)})
    case 1n+p:
      do IO<Open.R(List<&2, String>)>:
        r : Open.R(String) <- Open.text(exp ++ "/page-" ++ Nat.show(i) ++ ".json", 268435456)
        Open.pages.next(r, acc, a => Open.pages(p, Nat.add(i, 1n), exp, a))

def Open.write_gz_sh() -> String:
  "t=$1; out=$2; rm -f \"$out.tmp\"; (umask 077; gzip -3 -c \"$t\" > \"$out.tmp\") && chmod 600 \"$out.tmp\" && mv -f \"$out.tmp\" \"$out\" "
  ++ "|| { rm -f \"$out.tmp\"; echo \"could not write $out\" >&2; exit 1; }"

def Open.export_kine.gz(+stage: String, +out: String) -> IO(Open.R(Unit)):
  do IO<Open.R(Unit)>:
    r : Open.R(String) <- Open.sh(Open.write_gz_sh(), [stage ++ "/snapshot.tar", out])
    return Open.unit(r)

def Open.export_kine.tar(t: Open.R(List<&2, U32>), +stage: String, +out: String) -> IO(Open.R(Unit)):
  match t:
    case Fail{m}:
      IO.pure(Open.R(Unit), Fail{m})
    case Done{bs}:
      do IO<Open.R(Unit)>:
        w : B.BinFile.Res(Unit) <- B.BinFile.write(stage ++ "/snapshot.tar", bs)
        Open.bin_then(Unit, w, "could not write " ++ stage ++ "/snapshot.tar", Open.export_kine.gz(stage, out))

def Open.export_kine.paged(r: Open.R(List<&2, String>), rev: String, +stage: String, +out: String) -> IO(Open.R(Unit)):
  match r:
    case Fail{m}:
      IO.pure(Open.R(Unit), Fail{m})
    case Done{ps}:
      Open.export_kine.tar(Open.kv_archive(rev, ps), stage, out)

def Open.export_kine.count(n: Open.R(Nat), rev: String, +exp: String, +stage: String, +out: String) -> IO(Open.R(Unit)):
  match n:
    case Fail{m}:
      IO.pure(Open.R(Unit), Fail{m})
    case Done{k}:
      do IO<Open.R(Unit)>:
        ps : Open.R(List<&2, String>) <- Open.pages(k, 1n, exp, Nil{})
        Open.export_kine.paged(ps, rev, stage, out)

def Open.export_kine.read(rv: Open.R(String), pg: Open.R(String), +exp: String, +stage: String, +out: String) -> IO(Open.R(Unit)):
  match rv pg:
    case Fail{m} _:
      IO.pure(Open.R(Unit), Fail{m})
    case _ Fail{m}:
      IO.pure(Open.R(Unit), Fail{m})
    case Done{rev} Done{pages}:
      Open.export_kine.count(Open.nat("the page count", pages), rev, exp, stage, out)

def Open.export_kine(+exp: String, +stage: String, +out: String) -> IO(Open.R(Unit)):
  do IO<Open.R(Unit)>:
    rv : Open.R(String) <- Open.text(exp ++ "/revision", 64)
    pg : Open.R(String) <- Open.text(exp ++ "/pages", 64)
    Open.export_kine.read(rv, pg, exp, stage, out)

# The archive of the guest's dump in exp (share/snapshot/export, D10),
# gzip -3, mode 0600, at out; stage is a private scratch directory.
def Open.export(etcd: Bool, +exp: String, +stage: String, +out: String) -> IO(Open.R(Unit)):
  match etcd:
    case True{}:
      Open.export_etcd(exp, stage, out)
    case False{}:
      Open.export_kine(exp, stage, out)

# Restore: which format
# ---------------------

type Open.Fmt is Data:
  # host/vk8s.bend's VM-level snapshot: metadata.json first
  FmtVm{}
  # vcluster's archive: a name under "/" first, or no entry at all
  FmtOpen{}
  FmtBad{msg: String}

def Open.fmt.name.if(vm: Bool, root: Bool, +name: List<&2, U32>) -> Open.Fmt:
  match vm root:
    case True{} _:
      FmtVm{}
    case False{} True{}:
      FmtOpen{}
    case False{} False{}:
      FmtBad{"the snapshot's first entry is " ++ String.quote(S.Snap.s(name))
        ++ ": neither a vk8s VM snapshot (metadata.json) nor vcluster's archive (/vcluster/snapshot/...)"}

def Open.fmt.name(+name: List<&2, U32>) -> Open.Fmt:
  Open.fmt.name.if(S.Snap.beq(name, S.Snap.b("metadata.json")), S.Snap.bprefix(name, [47]), name)

def Open.fmt.hdr.regular(reg: Bool, +name: List<&2, U32>, +why: String) -> Open.Fmt:
  match reg:
    case True{}:
      Open.fmt.name(name)
    case False{}:
      FmtBad{"cannot read the snapshot: " ++ why}

# The first header alone, when the first record does not fit the prefix
# (an etcd database): a regular file under "/".
def Open.fmt.hdr(h: Open.R(S.Snap.Tar.Hdr), +why: String) -> Open.Fmt:
  match h:
    case Fail{m}:
      FmtBad{"cannot read the snapshot: " ++ m}
    case Done{S.Hdr{+flag, name, size}}:
      Open.fmt.hdr.regular(U32.is_eq(flag, 48) || U32.is_eq(flag, 0), name, why)

def Open.fmt.first(r: Open.R(List<&2, S.Snap.Rec>), blk: List<&2, U32>) -> Open.Fmt:
  match r:
    case Done{Nil{}}:
      FmtOpen{}
    case Done{Con{S.Rec{k, v}, t}}:
      Open.fmt.name(k)
    case Fail{m}:
      Open.fmt.hdr(S.Snap.Tar.hdr(blk), m)

def Open.fmt.sized(short: Bool, +pre: List<&2, U32>) -> Open.Fmt:
  match short:
    case True{}:
      FmtBad{"cannot read the snapshot: not a gzip-compressed tar archive"}
    case False{}:
      Open.fmt.first(S.Snap.Tar.heads(1n, pre), List.take(&2, U32, pre, 512n))

# The format of a snapshot from a prefix of its tar stream (after gunzip;
# host/vk8s.bend reads 1 MiB): the first record's name, read with the
# proven decoder (PAX and GNU names included). An etcd database does not
# fit the prefix; then the first header alone decides. An archive with no
# entry is a key/value archive with no keys (D2, getSnapshotArchiveKind).
def Open.fmt(+pre: List<&2, U32>) -> Open.Fmt:
  Open.fmt.sized(Nat.is_gt(512n, List.length(&2, U32, pre)), pre)

def Open.fmt_file.of(r: Open.R(List<&2, U32>)) -> Open.Fmt:
  match r:
    case Fail{m}:
      FmtBad{"cannot read the snapshot: " ++ m}
    case Done{bs}:
      Open.fmt(bs)

def Open.fmt_file(+path: String) -> IO(Open.Fmt):
  do IO<Open.Fmt>:
    r : Open.R(List<&2, U32>) <- Open.range(path, 0, 1048576)
    return Open.fmt_file.of(r)

# Restore: the kind of an open archive
# ------------------------------------

type Open.Loc is Data:
  # an etcd archive: the database's data offset and size in the tar
  LocDb{off: Nat, size: Nat}
  LocKv{}
  LocErr{msg: String}

def Open.blk(+bs: List<&2, U32>, +off: Nat) -> List<&2, U32>:
  List.take(&2, U32, List.drop(&2, U32, bs, off), 512n)

def Open.next_off(+off: Nat, +n: Nat) -> Nat:
  Nat.add(Nat.add(off, 512n), Nat.add(n, S.Snap.Tar.pad_after(n)))

def Open.loc.meta(rel: Bool, req: Bool, +next: Nat, again: Bool -> Bool -> Nat -> Open.Loc) -> Open.Loc:
  match rel req:
    case True{} _:
      again(False{}, True{}, next)
    case False{} True{}:
      again(False{}, False{}, next)
    case False{} False{}:
      LocKv{}

def Open.loc.file.db(db: Bool, +data: Nat, +n: Nat, rel: Bool, req: Bool, +next: Nat,
  again: Bool -> Bool -> Nat -> Open.Loc) -> Open.Loc:
  match db:
    case True{}:
      LocDb{data, n}
    case False{}:
      Open.loc.meta(rel, req, next, again)

def Open.loc.file(+name: List<&2, U32>, +off: Nat, +n: Nat, rel_ok: Bool, req_ok: Bool,
  again: Bool -> Bool -> Nat -> Open.Loc) -> Open.Loc:
  Open.loc.file.db(S.Snap.beq(name, S.Snap.db_key()), Nat.add(off, 512n), n,
    rel_ok && S.Snap.beq(name, S.Snap.release_key()), req_ok && S.Snap.bprefix(name, S.Snap.request_key()),
    Open.next_off(off, n), again)

def Open.loc.reg(reg: Bool, +name: List<&2, U32>, +off: Nat, +n: Nat, rel_ok: Bool, req_ok: Bool,
  again: Bool -> Bool -> Nat -> Open.Loc) -> Open.Loc:
  match reg:
    case True{}:
      Open.loc.file(name, off, n, rel_ok, req_ok, again)
    case False{}:
      LocKv{}

def Open.loc.hdr(h: Open.R(S.Snap.Tar.Hdr), +off: Nat, rel_ok: Bool, req_ok: Bool,
  again: Bool -> Bool -> Nat -> Open.Loc) -> Open.Loc:
  match h:
    case Fail{m}:
      LocErr{"cannot read the snapshot: " ++ m}
    case Done{S.Hdr{+flag, name, n}}:
      Open.loc.reg(U32.is_eq(flag, 48) || U32.is_eq(flag, 0), name, off, n, rel_ok, req_ok, again)

def Open.loc.blk.go(short: Bool, zero: Bool, +blk: List<&2, U32>, +off: Nat, rel_ok: Bool, req_ok: Bool,
  again: Bool -> Bool -> Nat -> Open.Loc) -> Open.Loc:
  match short zero:
    case True{} _:
      LocErr{"the snapshot's metadata entries do not fit in its first MiB"}
    case False{} True{}:
      LocKv{}
    case False{} False{}:
      Open.loc.hdr(S.Snap.Tar.hdr(blk), off, rel_ok, req_ok, again)

def Open.loc.blk(+blk: List<&2, U32>, +off: Nat, rel_ok: Bool, req_ok: Bool,
  again: Bool -> Bool -> Nat -> Open.Loc) -> Open.Loc:
  Open.loc.blk.go(Nat.is_gt(512n, List.length(&2, U32, blk)), S.Snap.Tar.all_zero(blk), blk, off, rel_ok, req_ok, again)

# getSnapshotArchiveKind (vcluster restoreclient.go, Snap.kind) on the
# headers of a prefix of the tar: an optional release, then an optional
# request (any name under the request key), then the database make an
# etcd archive; anything else a key/value archive. The etcd database's
# offset and size come with it.
def Open.loc.go(fuel: Nat, rel_ok: Bool, req_ok: Bool, +off: Nat, +bs: List<&2, U32>) -> Open.Loc:
  match fuel:
    case 0n:
      LocKv{}
    case 1n+p:
      Open.loc.blk(Open.blk(bs, off), off, rel_ok, req_ok, a => b => o => Open.loc.go(p, a, b, o, bs))

def Open.loc(+pre: List<&2, U32>) -> Open.Loc:
  Open.loc.go(3n, True{}, True{}, 0n, pre)

# Restore: the files for the guest
# --------------------------------

# A key the puts file can carry: printable ASCII without space, '"' or
# '\' (the guest's script reads it as one line and splices it into
# etcdctl txn input). Kubernetes keys are such.
def Open.key_ok(bs: List<&2, U32>) -> Bool:
  match bs:
    case Nil{}:
      True{}
    case Con{+c, t}:
      U32.is_gt(c, 32) && U32.is_lt(c, 127) && Bool.not(U32.is_eq(c, 34)) && Bool.not(U32.is_eq(c, 92)) && Open.key_ok(t)

# kine creates /registry/health when it starts, so the new kine already
# holds it: vcluster's Put (Get, then Update) would update it to the same
# value; the puts script only creates (D13), so vk8s leaves it out (D14).
def Open.kine_own(+k: List<&2, U32>) -> Bool:
  S.Snap.beq(k, S.Snap.b("/registry/health"))

def Open.puts.put(ok: Bool, own: Bool, +k: List<&2, U32>, +v: List<&2, U32>, rest: Open.R(List<&2, U32>)) -> Open.R(List<&2, U32>):
  match ok own rest:
    case False{} _ _:
      Fail{"the snapshot holds a key the restore cannot carry: " ++ String.quote(S.Snap.s(k))}
    case True{} True{} r:
      r
    case True{} False{} Fail{m}:
      Fail{m}
    case True{} False{} Done{bs}:
      Done{S.Snap.app(k, Con{10, S.Snap.app(S.Snap.Tar.quote(v), Con{10, bs})})}

def Open.puts.go(ps: List<&2, S.Snap.Put>) -> Open.R(List<&2, U32>):
  match ps:
    case Nil{}:
      Done{Nil{}}
    case Con{S.Put{+k, +v, pod}, t}:
      Open.puts.put(Bool.not(List.is_empty(&2, U32, k)) && Open.key_ok(k), Open.kine_own(k), k, v, Open.puts.go(t))

def Open.puts.plan(p: S.Snap.Plan) -> Open.R(List<&2, U32>):
  match p:
    case S.Plan{ps, compact}:
      Open.puts.go(ps)

# The puts file (D13): two lines a put, the key, then the value as a Go
# double-quoted string (Snap.Tar.quote: strconv.Quote, bytes past 0x7f
# as \x escapes), from Snap.restore_plan for a new vCluster with private
# nodes (D5, D8: no pod transform).
def Open.puts(rs: List<&2, S.Snap.Rec>) -> Open.R(List<&2, U32>):
  Open.puts.plan(S.Snap.restore_plan(rs, True{}, True{}))

def Open.kv_puts.kind(k: S.Snap.Kind, rs: List<&2, S.Snap.Rec>) -> Open.R(List<&2, U32>):
  match k:
    case S.KKeyValue{}:
      Open.puts(rs)
    case S.KEtcd{}:
      Fail{"the snapshot is an etcd archive whose metadata does not fit in its first MiB"}
    case S.KUnknown{}:
      Fail{"the snapshot's kind is unknown"}

def Open.kv_puts.dec(r: Open.R(List<&2, S.Snap.Rec>)) -> Open.R(List<&2, U32>):
  match r:
    case Fail{m}:
      Fail{"cannot read the snapshot: " ++ m}
    case Done{+rs}:
      Open.kv_puts.kind(S.Snap.kind(rs), rs)

# The puts file of a key/value archive's tar bytes.
def Open.kv_puts(bs: List<&2, U32>) -> Open.R(List<&2, U32>):
  Open.kv_puts.dec(S.Snap.Tar.decode(bs))

def Open.marked(m: Open.R(Unit), etcd: Bool) -> Open.R(Bool):
  match m:
    case Fail{e}:
      Fail{e}
    case Done{u}:
      Done{etcd}

# The marker: the next boot restores (Plan.restore_marker).
def Open.mark(+dir: String, etcd: Bool) -> IO(Open.R(Bool)):
  do IO<Open.R(Bool)>:
    w : B.BinFile.Res(Unit) <- B.BinFile.write(dir ++ "/restore", S.Snap.b("restore\n"))
    return Open.marked(Open.bin.r(Unit, w, "could not write " ++ dir ++ "/restore"), etcd)

def Open.place_kv.got(r: Open.R(List<&2, U32>), +dir: String) -> IO(Open.R(Bool)):
  match r:
    case Fail{m}:
      IO.pure(Open.R(Bool), Fail{m})
    case Done{bs}:
      do IO<Open.R(Bool)>:
        w : B.BinFile.Res(Unit) <- B.BinFile.write(dir ++ "/puts", bs)
        Open.bin_then(Bool, w, "could not write " ++ dir ++ "/puts", Open.mark(dir, False{}))

def Open.place_kv.read(r: Open.R(List<&2, U32>), +dir: String) -> IO(Open.R(Bool)):
  match r:
    case Fail{m}:
      IO.pure(Open.R(Bool), Fail{m})
    case Done{bs}:
      Open.place_kv.got(Open.kv_puts(bs), dir)

# A key/value archive: the puts and the marker; at most 256 MiB of tar.
def Open.place_kv(+tar: String, +dir: String) -> IO(Open.R(Bool)):
  do IO<Open.R(Bool)>:
    r : Open.R(List<&2, U32>) <- Open.read(tar, 268435456)
    Open.place_kv.read(r, dir)

def Open.after_db.skip(skip: Bool) -> Open.R(Unit):
  match skip:
    case True{}:
      Fail{"the snapshot has skip keys (/vcluster/snapshot/skipkeys); vk8s cannot restore them yet"}
    case False{}:
      Done{Unit{}}

def Open.after_db.hdr(h: Open.R(S.Snap.Tar.Hdr)) -> Open.R(Unit):
  match h:
    case Fail{m}:
      Done{Unit{}}
    case Done{S.Hdr{flag, name, n}}:
      Open.after_db.skip(S.Snap.beq(name, S.Snap.skipkeys_key()))

def Open.after_db.blk(end: Bool, +blk: List<&2, U32>) -> Open.R(Unit):
  match end:
    case True{}:
      Done{Unit{}}
    case False{}:
      Open.after_db.hdr(S.Snap.Tar.hdr(blk))

# The entry after the database: vk8s cannot delete skip keys after an etcd
# restore yet (postRestoreSnapshotDataMutation), so it refuses them.
def Open.after_db(r: Open.R(List<&2, U32>)) -> Open.R(Unit):
  match r:
    case Fail{m}:
      Fail{m}
    case Done{+blk}:
      Open.after_db.blk(Nat.is_gt(512n, List.length(&2, U32, blk)) || S.Snap.Tar.all_zero(blk), blk)

def Open.copy_sh() -> String:
  "rm -f \"$4\"; (umask 077; perl -e \"$5\" \"$1\" \"$2\" \"$3\" > \"$4\") || { rm -f \"$4\"; exit 1; }"

def Open.place_db.copy(+tar: String, +dir: String, +off: Nat, +n: Nat) -> IO(Open.R(Bool)):
  do IO<Open.R(Bool)>:
    c : Open.R(String) <- Open.sh(Open.copy_sh(), [tar, Nat.show(off), Nat.show(n), dir ++ "/db", Open.perl_copy()])
    Open.then(Bool, Open.unit(c), Open.mark(dir, True{}))

def Open.place_db(+tar: String, +dir: String, +off: Nat, +n: Nat) -> IO(Open.R(Bool)):
  do IO<Open.R(Bool)>:
    nx : Open.R(List<&2, U32>) <- Open.range(tar, U32.from_nat(Open.next_off(Nat.sub(off, 512n), n)), 512)
    Open.then(Bool, Open.after_db(nx), Open.place_db.copy(tar, dir, off, n))

def Open.place.loc(l: Open.Loc, +tar: String, +dir: String) -> IO(Open.R(Bool)):
  match l:
    case LocErr{m}:
      IO.pure(Open.R(Bool), Fail{m})
    case LocDb{off, n}:
      Open.place_db(tar, dir, off, n)
    case LocKv{}:
      Open.place_kv(tar, dir)

def Open.place.pre(r: Open.R(List<&2, U32>), +tar: String, +dir: String) -> IO(Open.R(Bool)):
  match r:
    case Fail{m}:
      IO.pure(Open.R(Bool), Fail{m})
    case Done{pre}:
      Open.place.loc(Open.loc(pre), tar, dir)

# The files of a restore boot (D10, D12) from an open archive's tar (after
# gunzip) into dir (the new cluster's share/snapshot, or a directory moved
# there): db or puts, then the marker. True for an etcd archive (the new
# cluster needs embedded etcd), False for a key/value archive (kine).
def Open.place(+tar: String, +dir: String) -> IO(Open.R(Bool)):
  do IO<Open.R(Bool)>:
    mk : Open.R(String) <- Open.sh("umask 077; mkdir -p \"$1\"", [dir])
    r : Open.R(List<&2, U32>) <- Open.then(List<&2, U32>, Open.unit(mk), Open.range(tar, 0, 1048576))
    Open.place.pre(r, tar, dir)
