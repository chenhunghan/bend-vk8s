import Base
import ../src/lib/sha256.bend as H

# Tests for src/lib/sha256.bend. Expected digests are FIPS 180-4 / NIST
# vectors and Go crypto/sha256 (hex.EncodeToString(sha256.Sum256(b))).

def report(name: String, got: String, want: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.print("FAIL " ++ name ++ ": got " ++ got ++ ", want " ++ want)

def check(name: String, +got: String, +want: String) -> IO(Unit):
  report(name, got, want, String.eq(got, want))

def check_bytes(name: String, got: +List<U32>, want: +List<U32>) -> IO(Unit):
  check(name, H.Sha256.hex(got), H.Sha256.hex(want))

def a_times(n: Nat) -> String:
  String.repeat("a", n)

def main() -> IO(Unit):
  do IO<Unit>:
    check("empty", H.Sha256.hex_of(""),
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    check("abc", H.Sha256.hex_of("abc"),
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    check("vcluster", H.Sha256.hex_of("vcluster"),
      "f689954fb7af136362b02e8784233f78128dfec4e779c95aae228115091a7bc4")
    check("nist 56 bytes (two blocks)",
      H.Sha256.hex_of("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
      "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    check("nist 112 bytes (two blocks)",
      H.Sha256.hex_of("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"),
      "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1")
    check("55 x a (one block)", H.Sha256.hex_of(a_times(55n)),
      "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318")
    check("56 x a", H.Sha256.hex_of(a_times(56n)),
      "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a")
    check("63 x a", H.Sha256.hex_of(a_times(63n)),
      "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34")
    check("64 x a", H.Sha256.hex_of(a_times(64n)),
      "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb")
    check("65 x a", H.Sha256.hex_of(a_times(65n)),
      "635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0")
    check("200 x a (four blocks)", H.Sha256.hex_of(a_times(200n)),
      "c2a908d98f5df987ade41b5fce213067efbcc21ef2240212a41e54b5e7c28ae5")
    check("utf8 multibyte digest",
      H.Sha256.hex_of(String.from_list([Chr{233}, Chr{8364}, Chr{128512}])),
      "df9226927fd572c1ee66eec85de1bb139497614899f36e4e90474cb71f6ef9d0")
    check_bytes("utf8 multibyte bytes",
      H.Sha256.utf8(String.from_list([Chr{233}, Chr{8364}, Chr{128512}])),
      [195, 169, 226, 130, 172, 240, 159, 152, 128])
    check_bytes("utf8 ascii", H.Sha256.utf8("Az"), [65, 122])
    check("hex", H.Sha256.hex([0, 15, 16, 255]), "000f10ff")
    check("digest bytes", H.Sha256.hex(H.Sha256.digest([97, 98, 99])),
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
