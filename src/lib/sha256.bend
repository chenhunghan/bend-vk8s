import Base

# SHA-256 (FIPS 180-4) over byte lists, in pure Bend.
# A byte is a U32 in 0..255; a digest is 32 such bytes.
# vcluster hashes names with it (SafeConcatName, label-key conversion).

# The digest of a byte list.
def Sha256.digest(bs: +List<U32>) -> +List<U32>:
  ?TODO

# The UTF-8 bytes of a string (code points past 127 encode as UTF-8).
def Sha256.utf8(s: String) -> +List<U32>:
  ?TODO

# Lowercase hex of a byte list, two digits per byte.
def Sha256.hex(bs: +List<U32>) -> String:
  ?TODO

# Lowercase hex digest of a string's UTF-8 bytes (Go: hex.EncodeToString(sha256.Sum256([]byte(s)))).
def Sha256.hex_of(s: String) -> String:
  ?TODO
