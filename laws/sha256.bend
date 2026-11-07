import Base
import ../src/lib/sha256.bend as H

# Frozen spec for src/lib/sha256.bend. Vectors are FIPS 180-4 / Go crypto/sha256.

law sha256.empty:
  {H.Sha256.hex_of("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" : String}

law sha256.abc:
  {H.Sha256.hex_of("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" : String}

law sha256.vcluster:
  {H.Sha256.hex_of("vcluster") == "f689954fb7af136362b02e8784233f78128dfec4e779c95aae228115091a7bc4" : String}

law sha256.hex_bytes:
  {H.Sha256.hex([0, 15, 16, 255]) == "000f10ff" : String}

law sha256.utf8_ascii:
  {H.Sha256.utf8("Az") == [65, 122] : +List<U32>}

# General laws.

law sha256.digest_length:
  for bs: +List<U32>
  {List.length(&2, U32, H.Sha256.digest(bs)) == 32n : Nat}
