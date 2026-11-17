import Base
import ../src/layers/tar.bend as T
import ../src/layers/meta.bend as M
import ../src/oci/size.bend as N

# Spec for src/layers/meta.bend: the .bend-meta files of an unpacked
# layer. The format is bend-vmm's (`--share DIR,meta`, its src/fs/meta.bend
# and README: "bend-meta 1", then name, host, type, mode in octal, uid,
# gid, rdev=MAJ,MIN, mtime=S[.NS], xattr.NAME=HEX, ino, nlink); what a
# whiteout and an opaque directory are is containerd's
# OverlayConvertWhiteout (a 0,0 char device with mode 0;
# trusted.overlay.opaque = "y", hex 79). The entries are those
# laws/layers_tar.bend expects of its Python tarfile vectors.

def layers_meta.fx.e(path: String, host: String, ty: T.Ty, mode: U32, uid: U32, gid: U32, mtime: U32) -> T.Ent:
  T.Ent{path, host, ty, mode, uid, gid, 0, 0, mtime, 0, Nil{}, "", N.Size{0, 0}}

# Encodings
# ---------

law layers_meta.pct:
  {M.Meta.pct("a b/c%~-_.Z9") == "a%20b%2Fc%25~-_.Z9" : String}

law layers_meta.pct_equals:
  {M.Meta.pct("k=v") == "k%3Dv" : String}

# A name's bytes are encoded one by one, also those that are not UTF-8.
law layers_meta.pct_byte:
  {M.Meta.pct(SCon{Chr{255}, "x"}) == "%FFx" : String}

law layers_meta.oct_setuid:
  {M.Meta.oct(2541) == "4755" : String}

law layers_meta.oct_zero:
  {M.Meta.oct(0) == "0" : String}

law layers_meta.seed:
  {M.Meta.seed("beda42571c095172ab63437d050612a5") == 3201974871 : U32}

# Files
# -----

# One file per directory, in the order of their first records; a hard
# link and its file share ino (7 * 2^32 + 1) and nlink 2; a char device
# has rdev; implicit directories have mtime 0.
law layers_meta.basic:
  {M.Meta.sides(7, [
    layers_meta.fx.e("etc", "etc", T.TDir{}, 493, 0, 0, 1700000000),
    T.Ent{"etc/hosts", "etc/hosts", T.TReg{}, 420, 0, 0, 0, 0, 1700000000, 0, Nil{}, "", N.Size{0, 20}},
    T.Ent{"etc/mtab", "etc/mtab", T.TSym{}, 511, 0, 0, 0, 0, 1700000000, 0, Nil{}, "/proc/mounts", N.Size{0, 0}},
    T.Ent{"etc/hosts2", "etc/hosts2", T.THard{}, 420, 0, 0, 0, 0, 1700000000, 0, Nil{}, "etc/hosts", N.Size{0, 0}},
    layers_meta.fx.e("dev", "dev", T.TDir{}, 493, 0, 0, 0),
    T.Ent{"dev/null", "dev/null", T.TChr{}, 438, 0, 0, 1, 3, 1700000000, 0, Nil{}, "", N.Size{0, 0}},
    layers_meta.fx.e("run", "run", T.TDir{}, 493, 0, 0, 0),
    layers_meta.fx.e("run/initctl", "run/initctl", T.TFifo{}, 384, 0, 0, 1700000000)]) == [
    M.Side{".bend-meta", "bend-meta 1\nname=etc host=etc type=d mode=755 uid=0 gid=0 mtime=1700000000\nname=dev host=dev type=d mode=755 uid=0 gid=0 mtime=0\nname=run host=run type=d mode=755 uid=0 gid=0 mtime=0\n"},
    M.Side{"etc/.bend-meta", "bend-meta 1\nname=hosts host=hosts type=f mode=644 uid=0 gid=0 mtime=1700000000 ino=30064771073 nlink=2\nname=mtab host=mtab type=l mode=777 uid=0 gid=0 mtime=1700000000\nname=hosts2 host=hosts2 type=f mode=644 uid=0 gid=0 mtime=1700000000 ino=30064771073 nlink=2\n"},
    M.Side{"dev/.bend-meta", "bend-meta 1\nname=null host=null type=c mode=666 uid=0 gid=0 rdev=1,3 mtime=1700000000\n"},
    M.Side{"run/.bend-meta", "bend-meta 1\nname=initctl host=initctl type=p mode=600 uid=0 gid=0 mtime=1700000000\n"}]
    : List<&2, M.Side>}

# A whiteout is a 0,0 char device with mode 0 and the whiteout file's
# owner; an opaque directory has trusted.overlay.opaque = "y".
law layers_meta.whiteouts:
  {M.Meta.sides(7, [
    layers_meta.fx.e("a", "a", T.TDir{}, 493, 0, 0, 1700000000),
    layers_meta.fx.e("a", "a", T.TOpq{}, 420, 0, 0, 1700000000),
    layers_meta.fx.e("gone", "gone", T.TWh{}, 420, 7, 8, 1700000000)]) == [
    M.Side{".bend-meta", "bend-meta 1\nname=a host=a type=d mode=755 uid=0 gid=0 mtime=1700000000 xattr.trusted.overlay.opaque=79\nname=gone host=gone type=c mode=0 uid=7 gid=8 rdev=0,0 mtime=1700000000\n"}]
    : List<&2, M.Side>}

# Guest and host names apart (hashlib: sha256 of "makefile" and ".bend-meta").
law layers_meta.host_names:
  {M.Meta.sides(7, [
    layers_meta.fx.e("Makefile", "Makefile", T.TReg{}, 420, 0, 0, 1700000000),
    layers_meta.fx.e("makefile", ".bend-beda42571c095172ab63437d050612a5", T.TReg{}, 420, 0, 0, 1700000000),
    layers_meta.fx.e(".bend-meta", ".bend-10fef46313d579fa57f0a0237c69a572", T.TReg{}, 420, 0, 0, 1700000000)]) == [
    M.Side{".bend-meta", "bend-meta 1\nname=Makefile host=Makefile type=f mode=644 uid=0 gid=0 mtime=1700000000\nname=makefile host=.bend-beda42571c095172ab63437d050612a5 type=f mode=644 uid=0 gid=0 mtime=1700000000\nname=.bend-meta host=.bend-10fef46313d579fa57f0a0237c69a572 type=f mode=644 uid=0 gid=0 mtime=1700000000\n"}]
    : List<&2, M.Side>}

# Nanoseconds as a number after the point (bend-vmm reads mtime=S.NS);
# an xattr's value as hex ("hi" is 6869).
law layers_meta.pax:
  {M.Meta.sides(7, [
    T.Ent{"a.bin", "a.bin", T.TReg{}, 420, 1000, 1000, 0, 0, 1700000000, 500000000, [T.Xattr{"user.test", "hi"}], "", N.Size{0, 3}}]) == [
    M.Side{".bend-meta", "bend-meta 1\nname=a.bin host=a.bin type=f mode=644 uid=1000 gid=1000 mtime=1700000000.500000000 xattr.user.test=6869\n"}]
    : List<&2, M.Side>}

# A directory given twice keeps its last attributes.
law layers_meta.dir_twice:
  {M.Meta.sides(7, [
    layers_meta.fx.e("d", "d", T.TDir{}, 493, 0, 0, 1700000000),
    layers_meta.fx.e("d", "d", T.TDir{}, 448, 0, 0, 1700000001)]) == [
    M.Side{".bend-meta", "bend-meta 1\nname=d host=d type=d mode=700 uid=0 gid=0 mtime=1700000001\n"}]
    : List<&2, M.Side>}

# The layer's root has no record, so an opaque marker there goes.
law layers_meta.root_opaque:
  {M.Meta.sides(7, [
    layers_meta.fx.e("", "", T.TOpq{}, 420, 0, 0, 0),
    layers_meta.fx.e("x", "x", T.TReg{}, 420, 0, 0, 1)]) == [
    M.Side{".bend-meta", "bend-meta 1\nname=x host=x type=f mode=644 uid=0 gid=0 mtime=1\n"}]
    : List<&2, M.Side>}

law layers_meta.name_escaped:
  {M.Meta.sides(7, [layers_meta.fx.e("a b", "a b", T.TReg{}, 420, 0, 0, 1)]) == [
    M.Side{".bend-meta", "bend-meta 1\nname=a%20b host=a%20b type=f mode=644 uid=0 gid=0 mtime=1\n"}]
    : List<&2, M.Side>}

# An empty layer has no .bend-meta at all.
law layers_meta.empty:
  for seed: U32
  {M.Meta.sides(seed, []) == [] : List<&2, M.Side>}
