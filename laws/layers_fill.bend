import Base
import ../src/layers/fill.bend as F
import ../src/layers/tar.bend as T
import ../src/layers/store.bend as Y
import ../src/oci/size.bend as N

# Spec for src/layers/fill.bend: the host's unpack loop over a layer tar
# on disk, what each entry becomes, the layer's record and what gc
# removes.
#
# Proposed: every law of this file is new (feat/layers-fill). Sources:
# - offsets: POSIX ustar (pax(1)): a header is one 512-byte block, a
#   regular file's data follows it, and every member takes whole blocks;
# - the end of an archive: Go archive/tar reader.go (readHeader reads a
#   whole block with io.ReadFull: no byte is the end, part of a block is
#   io.ErrUnexpectedEOF);
# - the tar vectors: the Python 3 tarfile blocks of laws/layers_tar.bend
#   (USTAR and PAX), as hex without their trailing zeros;
# - what entries become: containerd's archive.Apply (pkg/archive/tar.go
#   createTarFile) for files, directories, symlinks and hard links;
#   devices, FIFOs and whiteouts are empty files whose guest type is in
#   .bend-meta (bend-vmm src/fs/meta.bend, `--share DIR,meta`);
# - .bend-meta text: bend-vmm's format (src/fs/meta.bend);
# - the record's format, the 72 h expiry's store and the one-day age of
#   a stale tmp entry: user decisions (docs/STATUS.md section 10);
#   chain IDs are Python hashlib sha256 hex digests.

# Fixtures
# --------

def layers_fill.fx.hexv.if(lower: Bool, x: U32) -> U32:
  match lower:
    case True{}:
      (x - 87 : U32)
    case False{}:
      (x - 48 : U32)

def layers_fill.fx.hexv(c: Char) -> U32:
  match c:
    case Chr{+x}:
      layers_fill.fx.hexv.if(U32.is_ge(x, 97), x)

# The bytes of a hex string.
def layers_fill.fx.unhex(s: String) -> +List<U32>:
  match s:
    case SCon{a, SCon{b, t}}:
      (layers_fill.fx.hexv(a) * 16 + layers_fill.fx.hexv(b) : U32) <> layers_fill.fx.unhex(t)
    case _:
      Nil{}

# A 512-byte block: the bytes, then zeros.
def layers_fill.fx.pad(+bs: +List<U32>) -> +List<U32>:
  List.append(&2, U32, bs, List.replicate(U32, Nat.sub(512n, List.length(&2, U32, bs)), 0))

def layers_fill.fx.tar(bs: List<&2, String>) -> +List<U32>:
  match bs:
    case Nil{}:
      Nil{}
    case Con{b, t}:
      List.append(&2, U32, layers_fill.fx.pad(layers_fill.fx.unhex(b)), layers_fill.fx.tar(t))

# A directory created because an entry needs it.
def layers_fill.fx.implicit(+path: String) -> T.Ent:
  T.Ent{path, path, T.TDir{}, 493, 0, 0, 0, 0, 0, 0, Nil{}, "", N.Size{0, 0}}

# A regular file of n bytes.
def layers_fill.fx.file(+path: String, +n: U32) -> T.Ent:
  T.Ent{path, path, T.TReg{}, 420, 0, 0, 0, 0, 0, 0, Nil{}, "", N.Size{0, n}}

# etc/, 0755 (USTAR header).
def layers_fill.fx.b.etc() -> String:
  "6574632f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000303030303735350030303030303030003030303030303000303030303030303030303000313435323437373034303000303036353632002035000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007573746172003030"

# etc/hosts, 0644, 20 bytes (USTAR header).
def layers_fill.fx.b.hosts() -> String:
  "6574632f686f73747300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000303030303634340030303030303030003030303030303000303030303030303030323400313435323437373034303000303037363431002030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007573746172003030"

# The 20 bytes of etc/hosts.
def layers_fill.fx.b.hosts_data() -> String:
  "3132372e302e302e31206c6f63616c686f73740a"

# Symlink etc/mtab -> /proc/mounts (USTAR header).
def layers_fill.fx.b.mtab() -> String:
  "6574632f6d74616200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003030303037373700303030303030300030303030303030003030303030303030303030003134353234373730343030003031313731370020322f70726f632f6d6f756e7473000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007573746172003030"

# Hard link etc/hosts2 -> etc/hosts (USTAR header).
def layers_fill.fx.b.hosts2() -> String:
  "6574632f686f737473320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003030303036343400303030303030300030303030303030003030303030303030303030003134353234373730343030003031313535320020316574632f686f737473000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007573746172003030"

# Char device dev/null 1,3 (USTAR header).
def layers_fill.fx.b.null() -> String:
  "6465762f6e756c6c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030363636003030303030303000303030303030300030303030303030303030300031343532343737303430300030313037323300203300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000757374617200303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000303030303030310030303030303033"

# The first 100 bytes of etc/hosts' header block.
def layers_fill.fx.b.hosts_part() -> String:
  "6574632f686f73747300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"

# Header blocks
# -------------

law layers_fill.blocks_zero:
  {F.Fill.blocks(N.Size{0, 0}) == N.Size{0, 0} : N.Size}

law layers_fill.blocks_one:
  {F.Fill.blocks(N.Size{0, 1}) == N.Size{0, 512} : N.Size}

law layers_fill.blocks_whole:
  {F.Fill.blocks(N.Size{0, 512}) == N.Size{0, 512} : N.Size}

law layers_fill.blocks_next:
  {F.Fill.blocks(N.Size{0, 513}) == N.Size{0, 1024} : N.Size}

# 2^32 - 1 rounds up to 2^32.
law layers_fill.blocks_4gib:
  {F.Fill.blocks(N.Size{0, 4294967295}) == N.Size{1, 0} : N.Size}

law layers_fill.blocks_past_4gib:
  {F.Fill.blocks(N.Size{1, 1}) == N.Size{1, 512} : N.Size}

# No byte where a header would be: the archive ended.
law layers_fill.head_none:
  {F.Fill.show(F.Fill.head(T.Tar.start(), N.Size{0, 1024}, [], "/t")) == "done" : String}

# Part of a header block: unexpected EOF.
law layers_fill.head_part:
  {F.Fill.show(F.Fill.head(T.Tar.start(), N.Size{0, 1024}, [0, 0, 0], "/t")) == "bad tar: unexpected end of archive" : String}

# A zero block ends the archive.
law layers_fill.head_zero:
  {F.Fill.show(F.Fill.head(T.Tar.start(), N.Size{0, 0}, List.replicate(U32, 512n, 0), "/t")) == "done" : String}

# A skipped member (a global pax header, the root) of 1 byte: one block.
law layers_fill.act_skip:
  {F.Fill.show(F.Fill.act(T.SSkip{T.Tar.start(), N.Size{0, 1}}, N.Size{0, 512}, "/t")) == "head 1024" : String}

# An extended header's 51 bytes at 512; the next header at 1024.
law layers_fill.act_ext:
  {F.Fill.show(F.Fill.act(T.SMeta{T.Tar.start(), N.Size{0, 51}}, N.Size{0, 512}, "/t")) == "ext 512 51 1024" : String}

# Offsets past 4 GiB: a 4 GiB member after the header at 0.
law layers_fill.act_skip_4gib:
  {F.Fill.show(F.Fill.act(T.SSkip{T.Tar.start(), N.Size{1, 0}}, N.Size{0, 512}, "/t")) == "head 4294967808" : String}

law layers_fill.act_end:
  {F.Fill.show(F.Fill.act(T.SEnd{}, N.Size{0, 512}, "/t")) == "done" : String}

law layers_fill.act_bad:
  {F.Fill.show(F.Fill.act(T.SBad{"tar: absolute path: /etc/passwd"}, N.Size{0, 512}, "/t")) == "bad tar: absolute path: /etc/passwd" : String}

# Entries
# -------

law layers_fill.op_dir:
  {F.Fill.op("/t", N.Size{0, 512}, layers_fill.fx.implicit("etc")) == F.OMkdir{"/t/etc"} : F.Op}

law layers_fill.op_file:
  {F.Fill.op("/t", N.Size{1, 512}, layers_fill.fx.file("big", 7)) == F.OCopy{"/t/big", N.Size{1, 512}, N.Size{0, 7}} : F.Op}

law layers_fill.op_whiteout:
  {F.Fill.op("/t", N.Size{0, 512}, T.Ent{"a/gone", "a/gone", T.TWh{}, 0, 0, 0, 0, 0, 0, 0, Nil{}, "", N.Size{0, 0}}) == F.OEmpty{"/t/a/gone"} : F.Op}

law layers_fill.op_opaque:
  {F.Fill.op("/t", N.Size{0, 512}, T.Ent{"a", "a", T.TOpq{}, 0, 0, 0, 0, 0, 0, 0, Nil{}, "", N.Size{0, 0}}) == F.ONone{} : F.Op}

law layers_fill.op_fifo:
  {F.Fill.op("/t", N.Size{0, 512}, T.Ent{"run/initctl", "run/initctl", T.TFifo{}, 384, 0, 0, 0, 0, 0, 0, Nil{}, "", N.Size{0, 0}}) == F.OEmpty{"/t/run/initctl"} : F.Op}

# The loop over a whole tar
# -------------------------

law layers_fill.plan_file:
  {F.Fill.plan("/t", layers_fill.fx.tar([layers_fill.fx.b.etc(), layers_fill.fx.b.hosts(), layers_fill.fx.b.hosts_data()])) == Done{[
    F.OMkdir{"/t/etc"},
    F.OCopy{"/t/etc/hosts", N.Size{0, 1024}, N.Size{0, 20}}]}
    : Result<&2, &2, String, List<&2, F.Op>>}

law layers_fill.plan_symlink:
  {F.Fill.plan("/t", layers_fill.fx.tar([layers_fill.fx.b.etc(), layers_fill.fx.b.mtab()])) == Done{[
    F.OMkdir{"/t/etc"},
    F.OSymlink{"/t/etc/mtab", "/proc/mounts"}]}
    : Result<&2, &2, String, List<&2, F.Op>>}

# etc/hosts first: its directory is made before it; then the hard link.
law layers_fill.plan_hard:
  {F.Fill.plan("/t", layers_fill.fx.tar([layers_fill.fx.b.hosts(), layers_fill.fx.b.hosts_data(), layers_fill.fx.b.hosts2()])) == Done{[
    F.OMkdir{"/t/etc"},
    F.OCopy{"/t/etc/hosts", N.Size{0, 512}, N.Size{0, 20}},
    F.OLink{"/t/etc/hosts2", "/t/etc/hosts"}]}
    : Result<&2, &2, String, List<&2, F.Op>>}

law layers_fill.plan_device:
  {F.Fill.plan("/t", layers_fill.fx.tar([layers_fill.fx.b.null()])) == Done{[
    F.OMkdir{"/t/dev"},
    F.OEmpty{"/t/dev/null"}]}
    : Result<&2, &2, String, List<&2, F.Op>>}

# A pax header of 51 bytes, then a.bin (3 bytes): its data at 1536.
law layers_fill.plan_pax:
  {F.Fill.plan("/t", layers_fill.fx.tar([
    "2e2f2e2f405061784865616465720000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000303030303030300030303030303030003030303030303000303030303030303030363300303030303030303030303000303130323134002078000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007573746172003030",
    "3232206d74696d653d313730303030303030302e350a323920534348494c592e78617474722e757365722e746573743d68690a",
    "612e62696e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000303030303634340030303031373530003030303137353000303030303030303030303300313435323437373034303000303036373434002030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007573746172003030",
    "616263"])) == Done{[
    F.OCopy{"/t/a.bin", N.Size{0, 1536}, N.Size{0, 3}}]}
    : Result<&2, &2, String, List<&2, F.Op>>}

# etc/, then 100 bytes of a header: unexpected EOF.
law layers_fill.plan_truncated:
  {F.Fill.plan("/t", List.append(&2, U32, layers_fill.fx.tar([layers_fill.fx.b.etc()]), layers_fill.fx.unhex(layers_fill.fx.b.hosts_part()))) == Fail{"tar: unexpected end of archive"}
    : Result<&2, &2, String, List<&2, F.Op>>}

# After the loop
# --------------

law layers_fill.sides:
  {F.Fill.sides("/t", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", [layers_fill.fx.implicit("etc")]) == [
    F.OWrite{"/t/.bend-meta", "bend-meta 1\nname=etc host=etc type=d mode=755 uid=0 gid=0 mtime=0\n"}] : List<&2, F.Op>}

# Deepest directory first, the layer's own directory last.
law layers_fill.syncs:
  {F.Fill.syncs("/t", [layers_fill.fx.implicit("a"), layers_fill.fx.implicit("a/b"), layers_fill.fx.file("a/b/c", 1)]) == ["/t/a/b", "/t/a", "/t"] : List<&2, String>}

# Records
# -------

law layers_fill.rec_path:
  {F.Fill.rec.path("/r", "sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6") == Some{"/r/layer-refs/a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6"} : Maybe<&2, String>}

law layers_fill.rec_path_refused:
  {F.Fill.rec.path("/r", "sha256:../x") == None{} : Maybe<&2, String>}

law layers_fill.rec_render:
  {F.Fill.rec.render(Y.Layer{"sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", ["n1/a"], 1763337600}) == "layer-meta 1\nchain sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6\ndiff sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\nparent sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nlast-use 1763337600\nholder n1/a\n" : String}

law layers_fill.rec_parse:
  {F.Fill.rec.parse("layer-meta 1\nchain sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6\ndiff sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\nparent sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nlast-use 1763337600\nholder n1/a\n") == Some{Y.Layer{"sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", ["n1/a"], 1763337600}} : Maybe<&2, Y.Layer>}

# The first layer: no parent, no holder.
law layers_fill.rec_parse_first:
  {F.Fill.rec.parse("layer-meta 1\nchain sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\ndiff sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nparent \nlast-use 7\n") == Some{Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", [], 7}} : Maybe<&2, Y.Layer>}

law layers_fill.rec_parse_other_version:
  {F.Fill.rec.parse("layer-meta 2\nchain sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\ndiff sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nparent \nlast-use 7\n") == None{} : Maybe<&2, Y.Layer>}

law layers_fill.rec_parse_bad_chain:
  {F.Fill.rec.parse("layer-meta 1\nchain sha256:x\ndiff sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nparent \nlast-use 7\n") == None{} : Maybe<&2, Y.Layer>}

law layers_fill.rec_parse_time_overflow:
  {F.Fill.rec.parse("layer-meta 1\nchain sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\ndiff sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nparent \nlast-use 4294967296\n") == None{} : Maybe<&2, Y.Layer>}

law layers_fill.rec_parse_empty:
  {F.Fill.rec.parse("") == None{} : Maybe<&2, Y.Layer>}

law layers_fill.rec_new:
  {F.Fill.rec.new("sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", 9) == Y.Layer{"sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", [], 9} : Y.Layer}

law layers_fill.touch:
  {F.Fill.touch(Y.Layer{"sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", ["n1/a"], 9}, 10) == Y.Layer{"sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", ["n1/a"], 10} : Y.Layer}

# Garbage collection
# ------------------

law layers_fill.chain_of:
  {F.Fill.chain_of("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == Some{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"} : Maybe<&2, String>}

law layers_fill.chain_of_other:
  {F.Fill.chain_of("notes") == None{} : Maybe<&2, String>}

# No record: no holder, no use since 1970.
law layers_fill.or_missing:
  {F.Fill.or("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", None{}) == Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", "", [], 0} : Y.Layer}

law layers_fill.or_record:
  {F.Fill.or("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", Some{"layer-meta 1\nchain sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\ndiff sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nparent \nlast-use 7\nholder n1/a\n"}) == Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", ["n1/a"], 7} : Y.Layer}

# A record of another layer counts as none.
law layers_fill.or_other:
  {F.Fill.or("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", Some{"layer-meta 1\nchain sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6\ndiff sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\nparent sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nlast-use 7\nholder n1/a\n"}) == Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", "", [], 0} : Y.Layer}

law layers_fill.stale:
  {F.Fill.stale("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.7", 0, 86400) == True{} : Bool}

law layers_fill.stale_tar:
  {F.Fill.stale("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.7.tar", 100, 86500) == True{} : Bool}

law layers_fill.stale_young:
  {F.Fill.stale("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.7", 1, 86400) == False{} : Bool}

law layers_fill.stale_other_name:
  {F.Fill.stale("notes.txt", 0, 999999) == False{} : Bool}

law layers_fill.stale_clock_back:
  {F.Fill.stale("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.7", 100, 50) == False{} : Bool}

law layers_fill.tmp_tar:
  {F.Fill.tmp.tar("/r/tmp/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.7") == "/r/tmp/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.7.tar" : String}

law layers_fill.born:
  {F.Fill.born("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.1763337600.tar") == Some{1763337600} : Maybe<&2, U32>}

law layers_fill.born_plain:
  {F.Fill.born("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.7") == Some{7} : Maybe<&2, U32>}

law layers_fill.born_other:
  {F.Fill.born("notes.txt") == None{} : Maybe<&2, U32>}

law layers_fill.stale_name:
  {F.Fill.stale.name("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.100.rec", 86500) == True{} : Bool}

law layers_fill.stale_name_young:
  {F.Fill.stale.name("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.100", 86499) == False{} : Bool}

# Proposed: security review 2026-11-18 (docs/ref/review-security-boundary-delta.md)
# F3, F5 and F6, feat/sec-layers-gc. The values are the owner's choices
# in the brief: a gzip/zstd output cap of 50 times the compressed layer
# and at most 64 GiB (bend-kube 0.10.0 Unz.file counts it in MiB, 0 is no
# limit), at most 2,000,000 tar entries, a layers.held line is
# "sha256:<64 hex> <holder>" (Spb.held), and a lock 60 minutes old is
# stale.

# F5: a record without its directory is no layer.
law layers_fill.present_both:
  {F.Fill.present(Some{Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", [], 7}}, True{}) == Some{Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", [], 7}} : Maybe<&2, Y.Layer>}

law layers_fill.present_no_dir:
  {F.Fill.present(Some{Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", [], 7}}, False{}) == None{} : Maybe<&2, Y.Layer>}

law layers_fill.present_no_record:
  {F.Fill.present(None{}, True{}) == None{} : Maybe<&2, Y.Layer>}

# F6: the decompressed size cap, in MiB.
law layers_fill.unz_mib_ratio:
  {F.Fill.unz.mib(N.Size{0, 10485760}) == 500 : U32}

law layers_fill.unz_mib_round_up:
  {F.Fill.unz.mib(N.Size{0, 1048577}) == 51 : U32}

law layers_fill.unz_mib_small:
  {F.Fill.unz.mib(N.Size{0, 1024}) == 1 : U32}

# Unz.file reads 0 as no limit: never 0.
law layers_fill.unz_mib_zero:
  {F.Fill.unz.mib(N.Size{0, 0}) == 1 : U32}

law layers_fill.unz_mib_below_cap:
  {F.Fill.unz.mib(N.Size{0, 1342177280}) == 64000 : U32}

law layers_fill.unz_mib_cap:
  {F.Fill.unz.mib(N.Size{0, 2147483648}) == 65536 : U32}

law layers_fill.unz_mib_cap_big:
  {F.Fill.unz.mib(N.Size{1, 0}) == 65536 : U32}

law layers_fill.unz_why_cap:
  {F.Fill.unz.why(4, "decompressing the layer failed: unz: the output is past its limit") == "decompressing the layer failed: unz: the output is past its limit (the cap is 4 MiB: 50 times the compressed layer, at most 64 GiB)" : String}

law layers_fill.unz_why_other:
  {F.Fill.unz.why(4, "decompressing the layer failed: bad data") == "decompressing the layer failed: bad data" : String}

# F6: the entry cap.
law layers_fill.max_ents:
  {F.Fill.max_ents() == 2000000 : U32}

law layers_fill.too_many_at_cap:
  {F.Fill.too_many(2000000) == False{} : Bool}

law layers_fill.too_many_past_cap:
  {F.Fill.too_many(2000001) == True{} : Bool}

law layers_fill.ents_none:
  {F.Fill.ents(7, []) == 7 : U32}

# F3: layers.held, untrusted, parsed strictly.
law layers_fill.held_line:
  {F.Fill.held.line("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 n1/k8s.io/3/sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6") == Some{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"} : Maybe<&2, String>}

law layers_fill.held_line_upper:
  {F.Fill.held.line("sha256:E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855 n1/a") == None{} : Maybe<&2, String>}

law layers_fill.held_line_short:
  {F.Fill.held.line("sha256:e3b0c44298fc n1/a") == None{} : Maybe<&2, String>}

law layers_fill.held_line_no_holder:
  {F.Fill.held.line("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 ") == None{} : Maybe<&2, String>}

law layers_fill.held_line_bare:
  {F.Fill.held.line("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == None{} : Maybe<&2, String>}

law layers_fill.held_line_long_hex:
  {F.Fill.held.line("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b8550 n1/a") == None{} : Maybe<&2, String>}

law layers_fill.held_line_path:
  {F.Fill.held.line("../../etc/passwd n1/a") == None{} : Maybe<&2, String>}

law layers_fill.held_parse:
  {F.Fill.held.parse("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 n1/a\nbad line\n\nsha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6 n1/b\n") == ["sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6"] : List<&2, String>}

law layers_fill.held_parse_empty:
  {F.Fill.held.parse("") == [] : List<&2, String>}

law layers_fill.hold:
  {F.Fill.hold([Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", "", [], 0}, Y.Layer{"sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "", "", [], 0}], ["sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"]) == [Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", "", ["layers.held"], 0}, Y.Layer{"sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "", "", [], 0}] : List<&2, Y.Layer>}

# gc keeps an expired layer that a node holds and removes the other.
law layers_fill.gc_keeps_held:
  {Y.Lay.gc.drop(F.Fill.hold([Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", "", [], 0}, Y.Layer{"sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "", "", [], 0}], F.Fill.held.parse("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 n1/a\n")), 259200) == [Y.Layer{"sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "", "", [], 0}] : List<&2, Y.Layer>}

# A layer without a record (Fill.or) is kept while a node holds it.
law layers_fill.gc_keeps_held_no_record:
  {Y.Lay.gc.drop(F.Fill.hold([F.Fill.or("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", None{})], ["sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"]), 999999) == [] : List<&2, Y.Layer>}

# F5: the lock between fill and gc.
law layers_fill.lock_path:
  {F.Fill.lock.path("/h/.vk8s") == "/h/.vk8s/layers.lock" : String}

law layers_fill.lock_text:
  {F.Fill.lock.text(1763337600) == "1763337600\n" : String}

law layers_fill.lock_stale:
  {F.Fill.lock.stale("100\n", 3700) == True{} : Bool}

law layers_fill.lock_young:
  {F.Fill.lock.stale("100\n", 3699) == False{} : Bool}

law layers_fill.lock_clock_back:
  {F.Fill.lock.stale("5000\n", 100) == False{} : Bool}

# A lock being written (no time yet) is not taken over.
law layers_fill.lock_empty:
  {F.Fill.lock.stale("", 999999) == False{} : Bool}

law layers_fill.lock_junk:
  {F.Fill.lock.stale("pid 7\n", 999999) == False{} : Bool}

law layers_fill.lock_gone:
  {F.Fill.lock.stale.of(None{}, 0) == True{} : Bool}

law layers_fill.lock_found_young:
  {F.Fill.lock.stale.of(Some{"100\n"}, 200) == False{} : Bool}

# Proposed: W2 of factory report explore-layers-autofill-pull,
# feat/layers-locks: per-layer locks so gc runs beside automatic fills
# (docs/GOAL.md section 10, "runs safely beside a fill (F5)"). The lock
# directory <root>/layer-locks, the 60-minute takeover (as layers.lock)
# and the 72 h expiry are the owner's choices in the brief; S_IFMT
# (0170000) and S_IFDIR (0040000) are POSIX <sys/stat.h>.

law layers_fill.llock_path_v2:
  {F.Fill.llock.path.v2("/h/.vk8s", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == Some{"/h/.vk8s/layer-locks/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"} : Maybe<&2, String>}

law layers_fill.llock_path_refused_v2:
  {F.Fill.llock.path.v2("/h/.vk8s", "sha256:../x") == None{} : Maybe<&2, String>}

law layers_fill.llock_stale_v2:
  {F.Fill.llock.stale.v2(Some{"100\n"}, 3700) == True{} : Bool}

law layers_fill.llock_young_v2:
  {F.Fill.llock.stale.v2(Some{"100\n"}, 3699) == False{} : Bool}

law layers_fill.llock_gone_v2:
  {F.Fill.llock.stale.v2(None{}, 0) == True{} : Bool}

law layers_fill.llock_writing_v2:
  {F.Fill.llock.stale.v2(Some{""}, 999999) == False{} : Bool}

# gc keeps an expired layer that a node holds and removes the other (the
# cases of layers_fill.gc_keeps_held and gc_keeps_held_no_record).
law layers_fill.gc_keeps_held_v2:
  {F.Fill.gc.plan.v2([Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", "", [], 0}, Y.Layer{"sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "", "", [], 0}], F.Fill.held.parse("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 n1/a\n"), [], 259200) == [Y.Layer{"sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "", "", [], 0}] : List<&2, Y.Layer>}

law layers_fill.gc_keeps_held_no_record_v2:
  {F.Fill.gc.plan.v2([F.Fill.or("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", None{})], ["sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"], [], 999999) == [] : List<&2, Y.Layer>}

# gc skips an expired, unheld layer whose lock a fill holds, and removes
# the other.
law layers_fill.gc_skips_locked_v2:
  {F.Fill.gc.plan.v2([Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", "", [], 0}, Y.Layer{"sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "", "", [], 0}], [], ["sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6"], 259200) == [Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", "", [], 0}] : List<&2, Y.Layer>}

# A layer used less than 72 h ago stays (1 s short of 259200).
law layers_fill.gc_keeps_young_v2:
  {F.Fill.gc.plan.v2([Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", "", [], 1}], [], [], 259200) == [] : List<&2, Y.Layer>}

# Split checks: the lengths differ by at most one, and the halves, in
# order, are the list.
def layers_fill.fx.zero(n: Nat) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+k:
      False{}

def layers_fill.fx.le1(n: Nat) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+k:
      layers_fill.fx.zero(k)

def layers_fill.fx.eq(xs: List<&2, String>, ys: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      List.is_empty(&2, String, ys)
    case Con{x, t}:
      match ys:
        case Nil{}:
          False{}
        case Con{y, u}:
          String.eq(x, y) && layers_fill.fx.eq(t, u)

def layers_fill.fx.halves(+a: List<&2, String>, +b: List<&2, String>, xs: List<&2, String>) -> Bool:
  +la : Nat = List.length(&2, String, a)
  +lb : Nat = List.length(&2, String, b)
  layers_fill.fx.le1(Nat.sub(la, lb)) && layers_fill.fx.le1(Nat.sub(lb, la)) && layers_fill.fx.eq(List.append(&2, String, a, b), xs)

def layers_fill.fx.split_ok.of(p: List<&2, String> & List<&2, String>, xs: List<&2, String>) -> Bool:
  match p:
    case (a, b):
      layers_fill.fx.halves(a, b, xs)

def layers_fill.fx.split_ok(+xs: List<&2, String>) -> Bool:
  layers_fill.fx.split_ok.of(F.Fill.split.v2(xs), xs)

# Lists of 0, 1, 2, 3 and 7 items.
def layers_fill.fx.split_all() -> Bool:
  layers_fill.fx.split_ok([]) && layers_fill.fx.split_ok(["a"]) && layers_fill.fx.split_ok(["a", "b"]) && layers_fill.fx.split_ok(["a", "b", "c"]) && layers_fill.fx.split_ok(["a", "b", "c", "d", "e", "f", "g"])

law layers_fill.split_balanced_v2:
  {layers_fill.fx.split_all() == True{} : Bool}

# The checks above refuse a split that is not balanced or loses an item.
def layers_fill.fx.split_bad() -> Bool:
  layers_fill.fx.split_ok.of((["a", "b", "c"], []), ["a", "b", "c"]) || layers_fill.fx.split_ok.of((["a"], ["c"]), ["a", "b", "c"])

law layers_fill.split_check_refuses_v2:
  {layers_fill.fx.split_bad() == False{} : Bool}

# A record counts only with a directory there: lstat's st_mode is
# 0040755 (a directory), not 0100644 (a file) or 0120777 (a symlink).
law layers_fill.present_v2_needs_dir:
  {F.Fill.present.v2(Some{Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", [], 7}}, F.StMode{16877}) == Some{Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", [], 7}} : Maybe<&2, Y.Layer>}

law layers_fill.present_v2_file:
  {F.Fill.present.v2(Some{Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", "", [], 7}}, F.StMode{33188}) == None{} : Maybe<&2, Y.Layer>}

law layers_fill.present_v2_symlink:
  {F.Fill.present.v2(Some{Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", "", [], 7}}, F.StMode{41471}) == None{} : Maybe<&2, Y.Layer>}

law layers_fill.present_v2_missing:
  {F.Fill.present.v2(Some{Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", "", [], 7}}, F.StNone{}) == None{} : Maybe<&2, Y.Layer>}

law layers_fill.present_v2_no_record:
  {F.Fill.present.v2(None{}, F.StMode{16877}) == None{} : Maybe<&2, Y.Layer>}

# Proposed:
# Records of version 2 (user decision 2026-11-18, GOAL section 10: the
# size a fill unpacked, so a node's Usage of a shared layer needs no
# walk over the share): "layer-meta 2", then after last-use "size
# <bytes>" and "inodes <n>"; a record of version 1 still parses, its
# size unknown. Inodes count as containerd's fs.DiskUsage does (every
# file once, the root too; hard links share their target's).

# The text of a record of version 2.
law layers_fill.rec_render_v2:
  {F.Fill.rec.render.v2(Y.Layer{"sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", ["n1/a"], 1763337600}, F.Use{N.Size{1, 1073741824}, 70000})
    == "layer-meta 2\nchain sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6\ndiff sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\nparent sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nlast-use 1763337600\nsize 5368709120\ninodes 70000\nholder n1/a\n" : String}

# A record of version 2 reads back as written, past 32 bits.
law layers_fill.rec_v2_roundtrip:
  {F.Fill.rec.parse.v2(F.Fill.rec.render.v2(Y.Layer{"sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", ["n1/a"], 1763337600}, F.Use{N.Size{1, 1073741824}, 70000}))
    == Some{F.Rec{Y.Layer{"sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", ["n1/a"], 1763337600}, Some{F.Use{N.Size{1, 1073741824}, 70000}}}} : Maybe<&2, F.Rec>}

# A record of version 1 (an older vk8s) still parses, its size unknown.
law layers_fill.rec_v1_parses_v2:
  {F.Fill.rec.parse.v2("layer-meta 1\nchain sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6\ndiff sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\nparent sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nlast-use 1763337600\nholder n1/a\n")
    == Some{F.Rec{Y.Layer{"sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", ["n1/a"], 1763337600}, None{}}} : Maybe<&2, F.Rec>}

# A size that is not a number: no record.
law layers_fill.rec_v2_bad_size:
  {F.Fill.rec.parse.v2("layer-meta 2\nchain sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6\ndiff sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\nparent sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nlast-use 1763337600\nsize 5x\ninodes 70000\nholder n1/a\n")
    == None{} : Maybe<&2, F.Rec>}

# Inodes past 32 bits: no record.
law layers_fill.rec_v2_inodes_overflow:
  {F.Fill.rec.parse.v2("layer-meta 2\nchain sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6\ndiff sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\nparent sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nlast-use 1763337600\nsize 5368709120\ninodes 4294967296\nholder n1/a\n")
    == None{} : Maybe<&2, F.Rec>}

# A record of version 2 without its inodes line: no record.
law layers_fill.rec_v2_missing_inodes:
  {F.Fill.rec.parse.v2("layer-meta 2\nchain sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6\ndiff sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\nparent sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nlast-use 1763337600\nsize 5368709120\nholder n1/b\nholder n1/a\n")
    == None{} : Maybe<&2, F.Rec>}

# Another version: no record.
law layers_fill.rec_v3:
  {F.Fill.rec.parse.v2("layer-meta 3\nchain sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6\ndiff sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\nparent sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nlast-use 1763337600\nsize 5368709120\ninodes 70000\nholder n1/a\n")
    == None{} : Maybe<&2, F.Rec>}

# A record whose size is unknown keeps version 1.
law layers_fill.rec_render_of_v1:
  {F.Fill.rec.render.of(F.Rec{Y.Layer{"sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", ["n1/a"], 1763337600}, None{}})
    == "layer-meta 1\nchain sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6\ndiff sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\nparent sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nlast-use 1763337600\nholder n1/a\n" : String}

# A use of a layer touches its record and keeps its size.
law layers_fill.rec_use_keeps_size:
  {F.Fill.rec.use(Some{F.Rec{Y.Layer{"sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", ["n1/a"], 1763337600}, Some{F.Use{N.Size{1, 1073741824}, 70000}}}}, F.Fill.rec.new("sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", 9), None{}, 1763337700)
    == F.Rec{Y.Layer{"sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", ["n1/a"], 1763337700}, Some{F.Use{N.Size{1, 1073741824}, 70000}}} : F.Rec}

# A fill that publishes a layer records what it unpacked.
law layers_fill.rec_use_new:
  {F.Fill.rec.use(None{}, F.Fill.rec.new("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", 9), Some{F.Use{N.Size{0, 10}, 3}}, 9)
    == F.Rec{Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", [], 9}, Some{F.Use{N.Size{0, 10}, 3}}} : F.Rec}

# A use of a layer an older vk8s filled keeps its record of version 1.
law layers_fill.rec_use_v1_old:
  {F.Fill.rec.render.of(F.Fill.rec.use(F.Fill.rec.parse.v2("layer-meta 1\nchain sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6\ndiff sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\nparent sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nlast-use 1763337600\nholder n1/a\n"), F.Fill.rec.new("sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "x", "y", 9), None{}, 1763337600))
    == "layer-meta 1\nchain sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6\ndiff sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\nparent sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nlast-use 1763337600\nholder n1/a\n" : String}

# The nodes' copy of a record: beside the layer, in the share.
law layers_fill.rec_share:
  {F.Fill.rec.share("/r", "sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6")
    == Some{"/r/layers/a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6.rec"} : Maybe<&2, String>}

# No copy for a name that is not a chain ID.
law layers_fill.rec_share_refused:
  {F.Fill.rec.share("/r", "sha256:../x")
    == None{} : Maybe<&2, String>}

# Where a node reads it.
law layers_fill.rec_mount:
  {F.Fill.rec.mount("sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6")
    == Some{"/mnt/layers/a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6.rec"} : Maybe<&2, String>}

# gc never takes the copy for a layer.
law layers_fill.rec_share_not_a_layer:
  {F.Fill.chain_of("a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6.rec")
    == None{} : Maybe<&2, String>}

# gc reads a record of version 2.
law layers_fill.or_v2:
  {F.Fill.or.v2("sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", Some{"layer-meta 2\nchain sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6\ndiff sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\nparent sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nlast-use 1763337600\nsize 5368709120\ninodes 70000\nholder n1/a\n"})
    == Y.Layer{"sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", ["n1/a"], 1763337600} : Y.Layer}

# gc reads a record of version 1.
law layers_fill.or_v2_v1:
  {F.Fill.or.v2("sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", Some{"layer-meta 1\nchain sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6\ndiff sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\nparent sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nlast-use 1763337600\nholder n1/a\n"})
    == Y.Layer{"sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", ["n1/a"], 1763337600} : Y.Layer}

# No record: no holder, no use since 1970.
law layers_fill.or_v2_none:
  {F.Fill.or.v2("sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", None{})
    == Y.Layer{"sha256:a893da35bd22286079f2f3931516d3423eb9b4945f2379e0f8a501ec3d665dd6", "", "", [], 0} : Y.Layer}

# etc/, etc/hosts (10 bytes), its hard link etc/h2, a symlink and an opaque marker: the root, etc, hosts and the symlink, 10 bytes.
law layers_fill.use_of:
  {F.Fill.use.of([T.Ent{"etc", "etc", T.TDir{}, 420, 0, 0, 0, 0, 0, 0, [], "", N.Size{0, 0}}, T.Ent{"etc/hosts", "etc/hosts", T.TReg{}, 420, 0, 0, 0, 0, 0, 0, [], "", N.Size{0, 10}}, T.Ent{"etc/h2", "etc/h2", T.THard{}, 420, 0, 0, 0, 0, 0, 0, [], "etc/hosts", N.Size{0, 0}}, T.Ent{"lib", "lib", T.TSym{}, 420, 0, 0, 0, 0, 0, 0, [], "usr/lib", N.Size{0, 0}}, T.Ent{"etc", "etc", T.TOpq{}, 420, 0, 0, 0, 0, 0, 0, [], "", N.Size{0, 0}}])
    == F.Use{N.Size{0, 10}, 4} : F.Use}

# An empty layer: its directory, no byte.
law layers_fill.use_of_empty:
  {F.Fill.use.of([])
    == F.Use{N.Size{0, 0}, 1} : F.Use}

# Sizes add past 32 bits.
law layers_fill.use_of_big:
  {F.Fill.use.of([T.Ent{"a", "a", T.TReg{}, 420, 0, 0, 0, 0, 0, 0, [], "", N.Size{0, 4294967295}}, T.Ent{"b", "b", T.TReg{}, 420, 0, 0, 0, 0, 0, 0, [], "", N.Size{0, 1}}, T.Ent{"c", "c", T.TWh{}, 420, 0, 0, 0, 0, 0, 0, [], "", N.Size{0, 0}}])
    == F.Use{N.Size{1, 0}, 4} : F.Use}

# Proposed: W4 of docs/ref/explore-layers-autofill.md
# (feat/layers-host-fill): the host's fill and gc with per-layer locks.
# Hvf.path_facts' words are bend-vmm's (host/hvf.c: lstat, [there,
# st_mode, size hi, size lo, mtime hi, mtime lo]); S_IFDIR (0040000) is
# POSIX <sys/stat.h>; the 72 h expiry and the blob drop for automatic
# fills only are the brief's.

# lstat found a directory (st_mode 040755).
law layers_fill.stat_of_dir_v2:
  {F.Fill.stat.of.v2([1, 16877, 0, 4096, 0, 1763337600]) == F.StMode{16877} : F.Stat}

# Nothing there.
law layers_fill.stat_of_none_v2:
  {F.Fill.stat.of.v2([0, 0, 0, 0, 0, 0]) == F.StNone{} : F.Stat}

# A short answer is nothing there.
law layers_fill.stat_of_short_v2:
  {F.Fill.stat.of.v2([1]) == F.StNone{} : F.Stat}

# A symlink to a directory is no layer.
law layers_fill.stat_of_symlink_v2:
  {F.Fill.present.v2(Some{Y.Layer{"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "", "", [], 7}}, F.Fill.stat.of.v2([1, 41471, 0, 10, 0, 7])) == None{} : Maybe<&2, Y.Layer>}

# A record unused for 72 h, held by no node: gc removes it.
law layers_fill.gc_recheck_old_v2:
  {F.Fill.gc.recheck.v2("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", Some{"layer-meta 1\nchain sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\ndiff sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nparent \nlast-use 100\n"}, [], 259300) == True{} : Bool}

# A fill used the layer while gc waited for nothing (it read the record
# again under the lock): gc keeps it.
law layers_fill.gc_recheck_touched_v2:
  {F.Fill.gc.recheck.v2("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", Some{"layer-meta 1\nchain sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\ndiff sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nparent \nlast-use 259000\n"}, [], 259300) == False{} : Bool}

# A node's layers.held, read again under the lock, names it: gc keeps it.
law layers_fill.gc_recheck_held_v2:
  {F.Fill.gc.recheck.v2("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", None{}, ["sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"], 259300) == False{} : Bool}

# No record at all and no holder: gc removes it (as Fill.or).
law layers_fill.gc_recheck_no_record_v2:
  {F.Fill.gc.recheck.v2("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", None{}, [], 259200) == True{} : Bool}

# An automatic fill that published the layer drops its blob.
law layers_fill.blob_drop_auto_v2:
  {F.Fill.blob.drop.v2(True{}, "published") == True{} : Bool}

# `vk8s layers fill` keeps it.
law layers_fill.blob_keep_manual_v2:
  {F.Fill.blob.drop.v2(False{}, "published") == False{} : Bool}

# A layer another fill published keeps the blob (this fill did not use it).
law layers_fill.blob_keep_present_v2:
  {F.Fill.blob.drop.v2(True{}, "present") == False{} : Bool}

# A fill waits a minute past the lock's 60 minutes: 14640 polls of 250 ms.
law layers_fill.llock_polls_v2:
  {F.Fill.llock.polls.v2() == 14640 : U32}

# Proposed: layer images (v3, feat/layers-sqfs, docs/ref/layers-sqfs.md).
# S_IFREG and S_IFDIR: POSIX <sys/stat.h> (0100000, 0040000); the rest is
# vk8s's design.
def layers_fill.fx.layer() -> Y.Layer:
  Y.Layer{"sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1", "sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1", "", Nil{}, 0}

law layers_fill.ifreg_v3:
  {F.Fill.stat.ifreg.v3() == 32768 : U32}
law layers_fill.file_v3_regular:
  {F.Fill.stat.file.v3(F.StMode{33188}) == True{} : Bool}
law layers_fill.file_v3_dir:
  {F.Fill.stat.file.v3(F.StMode{16877}) == False{} : Bool}
law layers_fill.file_v3_none:
  {F.Fill.stat.file.v3(F.StNone{}) == False{} : Bool}
law layers_fill.present_v3_image:
  {F.Fill.present.v3(Some{layers_fill.fx.layer()}, F.StNone{}, F.StMode{33188}) == Some{layers_fill.fx.layer()} : Maybe<&2, Y.Layer>}
law layers_fill.present_v3_old_dir:
  {F.Fill.present.v3(Some{layers_fill.fx.layer()}, F.StMode{16877}, F.StNone{}) == Some{layers_fill.fx.layer()} : Maybe<&2, Y.Layer>}
law layers_fill.present_v3_neither:
  {F.Fill.present.v3(Some{layers_fill.fx.layer()}, F.StNone{}, F.StNone{}) == None{} : Maybe<&2, Y.Layer>}
law layers_fill.present_v3_no_record:
  {F.Fill.present.v3(None{}, F.StMode{16877}, F.StMode{33188}) == None{} : Maybe<&2, Y.Layer>}
law layers_fill.present_v3_image_is_a_dir:
  {F.Fill.present.v3(Some{layers_fill.fx.layer()}, F.StNone{}, F.StMode{16877}) == None{} : Maybe<&2, Y.Layer>}
law layers_fill.tmp_img_v3:
  {F.Fill.tmp.img.v3("/h/.vk8s/tmp/abc.7") == "/h/.vk8s/tmp/abc.7.sqfs" : String}
law layers_fill.rec_mount_v3:
  {F.Fill.rec.mount.v3("sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1")
    == Some{"/mnt/layers-store/c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1.rec"} : Maybe<&2, String>}


# Proposed: serve refreshes a layer's last use (v3, GOAL section 11). The
# 72 h expiry is Lay.ttl; the 24 h refresh age is vk8s's design.
def layers_fill.fx.rec(t: U32) -> F.Rec:
  F.Rec{Y.Layer{"sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1", "sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1", "", ["n1"], t}, Some{F.Use{N.Size.zero(), 7}}}

law layers_fill.touch_age_v3:
  {F.Fill.touch.age.v3() == 86400 : U32}
law layers_fill.touch_due_v3_day:
  {F.Fill.touch.due.v3(1000, 87400) == True{} : Bool}
law layers_fill.touch_due_v3_under_a_day:
  {F.Fill.touch.due.v3(1000, 87399) == False{} : Bool}
law layers_fill.touch_due_v3_clock_behind:
  {F.Fill.touch.due.v3(87400, 1000) == False{} : Bool}
law layers_fill.touch_before_expiry_v3:
  {Y.Lay.expired(1000, (1000 + F.Fill.touch.age.v3() : U32)) == False{} : Bool}
law layers_fill.rec_at_v3:
  {F.Fill.rec.at.v3(layers_fill.fx.rec(1000), 90000) == layers_fill.fx.rec(90000) : F.Rec}
law layers_fill.rec_at_v3_render:
  {F.Fill.rec.render.of(F.Fill.rec.at.v3(layers_fill.fx.rec(5), 90000))
    == "layer-meta 2\nchain sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1\ndiff sha256:c6f988f4874bb0add23a778f753c65efe992244e148a1d2ec2a8b664fb66bbd1\nparent \nlast-use 90000\nsize 0\ninodes 7\nholder n1\n" : String}
law layers_fill.rec_due_v3_old:
  {F.Fill.rec.due.v3(Some{layers_fill.fx.rec(1000)}, 90000) == True{} : Bool}
law layers_fill.rec_due_v3_fresh:
  {F.Fill.rec.due.v3(Some{layers_fill.fx.rec(80000)}, 90000) == False{} : Bool}
law layers_fill.rec_due_v3_none:
  {F.Fill.rec.due.v3(None{}, 90000) == False{} : Bool}
