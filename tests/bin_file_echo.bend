import Base
import ../host/bin_file.bend as B

# The binary file effects' test program. tests/bin_file.sh builds it and
# runs
#
#   bin_file_echo DIR
#
# which writes, with BinFile.create and BinFile.append:
# - DIR/all256.bin: every byte value 0..255, in two chunks;
# - DIR/big.bin: 3 MiB (3145728 bytes), byte i = i mod 251, in 48 chunks
#   of 64 KiB;
# - DIR/pre.bin: the bytes 1, 2, 3, over the file the script left there;
# then reads them back (size, byte ranges across a 1 MiB boundary and past
# the end), copies all256.bin and big.bin to DIR/all256.copy and
# DIR/big.copy with BinFile.read_all and BinFile.write, checks the error
# answers, and prints PASS/FAIL lines and "done". The script compares the
# files with cmp and sha256sum and checks their mode (0600).
#
# Run with no arguments (scripts/check.sh runs it so, through `bend` on
# the JavaScript lane) it only opens a missing file: the lane's stand-in
# must fail with ENOSYS (38), a native build with ENOENT (2).

def Res(-A: Type) -> Type:
  Result<&1, &1, U32 & String, A>

# Bytes
# -----

# n bytes: i, i+1, ...
def Gen.seq(n: Nat, +i: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Con{i, Gen.seq(p, (i + 1 : U32))}

# n bytes of big.bin from offset i: (i mod 251), ...
def Gen.big(n: Nat, +i: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Con{(i % 251 : U32), Gen.big(p, (i + 1 : U32))}

def Bytes.eq(xs: List<&2, U32>, ys: List<&2, U32>) -> Bool:
  match xs ys:
    case Nil{} Nil{}:
      True{}
    case Con{x, xt} Con{y, yt}:
      Bool.and(U32.is_eq(x, y), Bytes.eq(xt, yt))
    case _ _:
      False{}

# Reporting
# ---------

def Main.ok(b: Bool, what: String) -> IO(Unit):
  match b:
    case True{}:
      IO.print("PASS " ++ what)
    case False{}:
      IO.print("FAIL " ++ what)

def Main.file(r: Res(File), what: String) -> IO(File):
  match r:
    case Done{f}:
      IO.pure(File, f)
    case Fail{(c, m)}:
      IO.die(File, 1, "FAIL " ++ what ++ ": " ++ m)

def Main.done(r: Res(Unit), what: String) -> IO(Unit):
  match r:
    case Done{u}:
      IO.print("PASS " ++ what)
    case Fail{(c, m)}:
      IO.print("FAIL " ++ what ++ ": " ++ m)

def Main.step(r: File & Res(Unit), what: String) -> IO(File):
  match r:
    case (f, Done{u}):
      IO.pure(File, f)
    case (f, Fail{(c, m)}):
      IO.die(File, 1, "FAIL " ++ what ++ ": " ++ m)

def Check.size(r: File & Res(U32), +want: U32, +what: String) -> IO(File):
  match r:
    case (f, Done{+n}):
      do IO<File>:
        Main.ok(U32.is_eq(n, want), what ++ " is " ++ U32.show(want) ++ " bytes (got " ++ U32.show(n) ++ ")")
        return f
    case (f, Fail{(c, m)}):
      do IO<File>:
        IO.print("FAIL " ++ what ++ " size: " ++ m)
        return f

def Check.read(r: File & Res(List<&2, U32>), want: List<&2, U32>, what: String) -> IO(File):
  match r:
    case (f, Done{bs}):
      do IO<File>:
        Main.ok(Bytes.eq(bs, want), what)
        return f
    case (f, Fail{(c, m)}):
      do IO<File>:
        IO.print("FAIL " ++ what ++ ": " ++ m)
        return f

# A failure with errno code, as expected.
def Check.fail(r: Res(File), +code: U32, +what: String) -> IO(Unit):
  match r:
    case Fail{(+c, m)}:
      Main.ok(U32.is_eq(c, code), what ++ " fails with errno " ++ U32.show(code) ++ " (got " ++ U32.show(c) ++ ": " ++ m ++ ")")
    case Done{f}:
      do IO<Unit>:
        B.BinFile.close(f)
        IO.print("FAIL " ++ what ++ " succeeded")

def Check.append_fail(r: File & Res(Unit), +code: U32, +what: String) -> IO(File):
  match r:
    case (f, Fail{(+c, m)}):
      do IO<File>:
        Main.ok(U32.is_eq(c, code), what ++ " fails with errno " ++ U32.show(code) ++ " (got " ++ U32.show(c) ++ ")")
        return f
    case (f, Done{u}):
      do IO<File>:
        IO.print("FAIL " ++ what ++ " succeeded")
        return f

def Check.all_fail(r: Res(List<&2, U32>), +code: U32, +what: String) -> IO(Unit):
  match r:
    case Fail{(+c, m)}:
      Main.ok(U32.is_eq(c, code), what ++ " fails with errno " ++ U32.show(code) ++ " (got " ++ U32.show(c) ++ ")")
    case Done{bs}:
      IO.print("FAIL " ++ what ++ " succeeded")

# Writing
# -------

def Write.all256(path: String) -> IO(Unit):
  do IO<Unit>:
    r : Res(File) <- B.BinFile.create(path)
    f : File <- Main.file(r, "create all256.bin")
    a : File & Res(Unit) <- B.BinFile.append_all(f, [Gen.seq(128n, 0), Gen.seq(128n, 128)])
    f2 : File <- Main.step(a, "append all256.bin")
    B.BinFile.close(f2)
    IO.print("PASS write all256.bin in two chunks")

def Write.big.next(r: File & Res(Unit), again: File -> IO(File & Res(Unit))) -> IO(File & Res(Unit)):
  match r:
    case (f, Done{u}):
      again(f)
    case (f, Fail{e}):
      IO.pure(File & Res(Unit), (f, Fail{e}))

# n chunks of 64 KiB, the k-th first.
def Write.big.loop(n: Nat, f: File, +k: U32) -> IO(File & Res(Unit)):
  match n:
    case 0n:
      IO.pure(File & Res(Unit), (f, Done{Unit{}}))
    case 1n+p:
      do IO<File & Res(Unit)>:
        r : File & Res(Unit) <- B.BinFile.append(f, Gen.big(65536n, (k * 65536 : U32)))
        Write.big.next(r, f2 => Write.big.loop(p, f2, (k + 1 : U32)))

def Write.big(path: String) -> IO(Unit):
  do IO<Unit>:
    r : Res(File) <- B.BinFile.create(path)
    f : File <- Main.file(r, "create big.bin")
    a : File & Res(Unit) <- Write.big.loop(48n, f, 0)
    f2 : File <- Main.step(a, "append big.bin")
    B.BinFile.close(f2)
    IO.print("PASS write big.bin in 48 chunks of 64 KiB")

# Over an existing, longer 0644 file: create truncates it and makes it 0600.
def Write.pre(path: String) -> IO(Unit):
  do IO<Unit>:
    r : Res(Unit) <- B.BinFile.write(path, [1, 2, 3])
    Main.done(r, "write pre.bin over an existing file")

# Reading
# -------

def Check.all256(path: String) -> IO(Unit):
  do IO<Unit>:
    r : Res(File) <- B.BinFile.open(path)
    f : File <- Main.file(r, "open all256.bin")
    s : File & Res(U32) <- B.BinFile.size(f)
    f1 : File <- Check.size(s, 256, "all256.bin")
    a : File & Res(List<&2, U32>) <- B.BinFile.read(f1, 0, 256)
    f2 : File <- Check.read(a, Gen.seq(256n, 0), "all256.bin reads back 0..255")
    b : File & Res(List<&2, U32>) <- B.BinFile.read(f2, 250, 100)
    f3 : File <- Check.read(b, Gen.seq(6n, 250), "a range past the end stops at the end")
    c : File & Res(List<&2, U32>) <- B.BinFile.read(f3, 256, 10)
    f4 : File <- Check.read(c, [], "a range at the end is empty")
    d : File & Res(List<&2, U32>) <- B.BinFile.read(f4, 7, 3)
    f5 : File <- Check.read(d, [7, 8, 9], "a 3-byte range at offset 7")
    B.BinFile.close(f5)

def Check.big(path: String) -> IO(Unit):
  do IO<Unit>:
    r : Res(File) <- B.BinFile.open(path)
    f : File <- Main.file(r, "open big.bin")
    s : File & Res(U32) <- B.BinFile.size(f)
    f1 : File <- Check.size(s, 3145728, "big.bin")
    a : File & Res(List<&2, U32>) <- B.BinFile.read(f1, 1048570, 12)
    f2 : File <- Check.read(a, Gen.big(12n, 1048570), "big.bin: a range across the 1 MiB mark")
    b : File & Res(List<&2, U32>) <- B.BinFile.read(f2, 3145720, 100)
    f3 : File <- Check.read(b, Gen.big(8n, 3145720), "big.bin: the last 8 bytes")
    c : File & Res(List<&2, U32>) <- B.BinFile.read(f3, 2097152, 65536)
    f4 : File <- Check.read(c, Gen.big(65536n, 2097152), "big.bin: 64 KiB at 2 MiB")
    B.BinFile.close(f4)

def Copy.got(r: Res(List<&2, U32>), dst: String, what: String) -> IO(Unit):
  match r:
    case Done{bs}:
      do IO<Unit>:
        w : Res(Unit) <- B.BinFile.write(dst, bs)
        Main.done(w, what)
    case Fail{(c, m)}:
      IO.print("FAIL " ++ what ++ ": " ++ m)

# src to dst through BinFile.read_all and BinFile.write.
def Copy(src: String, dst: String, what: String) -> IO(Unit):
  do IO<Unit>:
    r : Res(List<&2, U32>) <- B.BinFile.read_all(src, 4194304)
    Copy.got(r, dst, what)

# Errors
# ------

def Check.errors(+dir: String) -> IO(Unit):
  do IO<Unit>:
    m : Res(File) <- B.BinFile.open(dir ++ "/missing.bin")
    Check.fail(m, 2, "open of a missing file")
    d : Res(File) <- B.BinFile.open(dir)
    Check.fail(d, 22, "open of a directory")
    r : Res(File) <- B.BinFile.create(dir ++ "/bad.bin")
    f : File <- Main.file(r, "create bad.bin")
    a : File & Res(Unit) <- B.BinFile.append(f, [1, 256, 2])
    f1 : File <- Check.append_fail(a, 22, "append of a value past 255")
    s : File & Res(U32) <- B.BinFile.size(f1)
    f2 : File <- Check.size(s, 0, "bad.bin after the refused append")
    B.BinFile.close(f2)
    t : Res(List<&2, U32>) <- B.BinFile.read_all(dir ++ "/all256.bin", 255)
    Check.all_fail(t, 27, "read_all of a file past max")

# Main
# ----

def Main.run(+dir: String) -> IO(Unit):
  do IO<Unit>:
    Write.all256(dir ++ "/all256.bin")
    Write.big(dir ++ "/big.bin")
    Write.pre(dir ++ "/pre.bin")
    Check.all256(dir ++ "/all256.bin")
    Check.big(dir ++ "/big.bin")
    Copy(dir ++ "/all256.bin", dir ++ "/all256.copy", "copy all256.bin with read_all and write")
    Copy(dir ++ "/big.bin", dir ++ "/big.copy", "copy big.bin with read_all and write")
    Check.errors(dir)
    IO.print("done")

def Main.lane.say(enosys: Bool, enoent: Bool, m: String) -> IO(Unit):
  match enosys enoent:
    case True{} _:
      IO.print("PASS bin_file_echo: the JavaScript stand-in fails with ENOSYS")
    case False{} True{}:
      IO.print("PASS bin_file_echo: BinFile.open answers ENOENT (native lane)")
    case False{} False{}:
      IO.print("FAIL bin_file_echo: BinFile.open: " ++ m)

def Main.lane.code(+c: U32, m: String) -> IO(Unit):
  Main.lane.say(U32.is_eq(c, 38), U32.is_eq(c, 2), m)

def Main.lane(r: Res(File)) -> IO(Unit):
  match r:
    case Fail{(c, m)}:
      Main.lane.code(c, m)
    case Done{f}:
      do IO<Unit>:
        B.BinFile.close(f)
        IO.print("FAIL bin_file_echo: a missing file opened")

def Main.args(args: List<String>) -> IO(Unit):
  match args:
    case Con{_, Con{dir, _}}:
      Main.run(dir)
    case _:
      do IO<Unit>:
        r : Res(File) <- B.BinFile.open("/nonexistent-vk8s-bin-file/missing")
        Main.lane(r)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    Main.args(args)
