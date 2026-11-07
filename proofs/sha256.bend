import Base
import ../laws/sha256.bend as L
import ../src/lib/sha256.bend as H

# Proofs of laws/sha256.bend: `def L.<law>` for each law.

def L.sha256.empty():
  {==}

def L.sha256.abc():
  {==}

def L.sha256.vcluster():
  {==}

def L.sha256.hex_bytes():
  {==}

def L.sha256.utf8_ascii():
  {==}

# The output is eight words of four bytes, whatever the hash value.
law sha256.out_length:
  for s: H.Sha256.St
  {List.length(&2, U32, H.Sha256.out(s)) == 32n : Nat}

def sha256.out_length(s):
  match s:
    case H.St{a, b, c, d, e, f, g, h}:
      {==}

def L.sha256.digest_length(bs):
  sha256.out_length(H.Sha256.blocks(H.Sha256.words(H.Sha256.pad(bs)), H.Sha256.init()))
