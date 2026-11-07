import Base

# SHA-256 (FIPS 180-4) over byte lists, in pure Bend.
# A byte is a U32 in 0..255; a digest is 32 such bytes.
# vcluster hashes names with it (SafeConcatName, label-key conversion).

# The eight working words a..h (also the hash value H0..H7).
type Sha256.St is Data:
  St{a: U32, b: U32, c: U32, d: U32, e: U32, f: U32, g: U32, h: U32}

# The last 16 schedule words: w0 is W[t], w15 is W[t+15].
type Sha256.Win is Data:
  Win{w0: U32, w1: U32, w2: U32, w3: U32, w4: U32, w5: U32, w6: U32, w7: U32,
      w8: U32, w9: U32, w10: U32, w11: U32, w12: U32, w13: U32, w14: U32, w15: U32}

# The initial hash value H(0) (FIPS 180-4, 5.3.3).
def Sha256.init() -> Sha256.St:
  St{1779033703, 3144134277, 1013904242, 2773480762,
     1359893119, 2600822924, 528734635, 1541459225}

# The round constants K (FIPS 180-4, 4.2.2).
def Sha256.k() -> +List<U32>:
  [1116352408, 1899447441, 3049323471, 3921009573, 961987163, 1508970993, 2453635748, 2870763221,
   3624381080, 310598401, 607225278, 1426881987, 1925078388, 2162078206, 2614888103, 3248222580,
   3835390401, 4022224774, 264347078, 604807628, 770255983, 1249150122, 1555081692, 1996064986,
   2554220882, 2821834349, 2952996808, 3210313671, 3336571891, 3584528711, 113926993, 338241895,
   666307205, 773529912, 1294757372, 1396182291, 1695183700, 1986661051, 2177026350, 2456956037,
   2730485921, 2820302411, 3259730800, 3345764771, 3516065817, 3600352804, 4094571909, 275423344,
   430227734, 506948616, 659060556, 883997877, 958139571, 1322822218, 1537002063, 1747873779,
   1955562222, 2024104815, 2227730452, 2361852424, 2428436474, 2756734187, 3204031479, 3329325298]

# Rotate right by n (0 < n < 32).
def Sha256.rotr(+x: U32, n: Nat, m: Nat) -> U32:
  U32.or(U32.shrn(x, n), U32.shln(x, m))

def Sha256.big_sigma0(+x: U32) -> U32:
  U32.xor(U32.xor(Sha256.rotr(x, 2n, 30n), Sha256.rotr(x, 13n, 19n)), Sha256.rotr(x, 22n, 10n))

def Sha256.big_sigma1(+x: U32) -> U32:
  U32.xor(U32.xor(Sha256.rotr(x, 6n, 26n), Sha256.rotr(x, 11n, 21n)), Sha256.rotr(x, 25n, 7n))

def Sha256.small_sigma0(+x: U32) -> U32:
  U32.xor(U32.xor(Sha256.rotr(x, 7n, 25n), Sha256.rotr(x, 18n, 14n)), U32.shrn(x, 3n))

def Sha256.small_sigma1(+x: U32) -> U32:
  U32.xor(U32.xor(Sha256.rotr(x, 17n, 15n), Sha256.rotr(x, 19n, 13n)), U32.shrn(x, 10n))

def Sha256.ch(+x: U32, y: U32, z: U32) -> U32:
  U32.xor(U32.and(x, y), U32.and(U32.not(x), z))

def Sha256.maj(+x: U32, +y: U32, +z: U32) -> U32:
  U32.xor(U32.xor(U32.and(x, y), U32.and(x, z)), U32.and(y, z))

# T1 = h + Σ1(e) + Ch(e, f, g) + K[t] + W[t].
def Sha256.t1(+e: U32, f: U32, g: U32, h: U32, k: U32, w: U32) -> U32:
  (h + Sha256.big_sigma1(e) + Sha256.ch(e, f, g) + k + w : U32)

# T2 = Σ0(a) + Maj(a, b, c).
def Sha256.t2(+a: U32, b: U32, c: U32) -> U32:
  (Sha256.big_sigma0(a) + Sha256.maj(a, b, c) : U32)

# One round: W[t] is w0. T1 and T2 are independent and cost about the
# same (one Σ and one bitwise choice each), so they run as a parallel let.
def Sha256.round(s: Sha256.St, k: U32, w: U32) -> Sha256.St:
  match s:
    case St{+a, +b, +c, +d, +e, +f, +g, h}:
      +x +y = Sha256.t1(e, f, g, h, k, w) Sha256.t2(a, b, c)
      St{(x + y : U32), a, b, c, (d + x : U32), e, f, g}

# The schedule window after W[t]: drop w0 and append W[t+16] =
# σ1(W[t+14]) + W[t+9] + σ0(W[t+1]) + W[t].
def Sha256.slide(win: Sha256.Win) -> Sha256.Win:
  match win:
    case Win{w0, +w1, w2, w3, w4, w5, w6, w7, w8, +w9, w10, w11, w12, w13, +w14, w15}:
      +n = (Sha256.small_sigma1(w14) + w9 + Sha256.small_sigma0(w1) + w0 : U32)
      Win{w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, w14, w15, n}

def Sha256.head(win: Sha256.Win) -> U32:
  match win:
    case Win{w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, w14, w15}:
      w0

# The 64 rounds, one per round constant.
def Sha256.rounds(ks: +List<U32>, s: Sha256.St, +win: Sha256.Win) -> Sha256.St:
  match ks:
    case Nil{}:
      s
    case k <> rest:
      Sha256.rounds(rest, Sha256.round(s, k, Sha256.head(win)), Sha256.slide(win))

# H(i) = H(i-1) + the compressed working words.
def Sha256.add_st(x: Sha256.St, y: Sha256.St) -> Sha256.St:
  match x y:
    case St{a, b, c, d, e, f, g, h} St{a2, b2, c2, d2, e2, f2, g2, h2}:
      St{(a + a2 : U32), (b + b2 : U32), (c + c2 : U32), (d + d2 : U32),
         (e + e2 : U32), (f + f2 : U32), (g + g2 : U32), (h + h2 : U32)}

def Sha256.compress(+s: Sha256.St, win: Sha256.Win) -> Sha256.St:
  Sha256.add_st(s, Sha256.rounds(Sha256.k(), s, win))

# A big-endian word of four bytes.
def Sha256.word(a: U32, b: U32, c: U32, d: U32) -> U32:
  U32.or(U32.or(U32.shln(a, 24n), U32.shln(b, 16n)), U32.or(U32.shln(c, 8n), d))

# The big-endian words of a byte list whose length is a multiple of 4.
def Sha256.words(bs: +List<U32>) -> +List<U32>:
  match bs:
    case a <> b <> c <> d <> t:
      Sha256.word(a, b, c, d) <> Sha256.words(t)
    case _:
      Nil{}

# Hash 16-word blocks into s. A short tail (never left by padding) is ignored.
def Sha256.blocks(ws: +List<U32>, s: Sha256.St) -> Sha256.St:
  match ws:
    case w0 <> w1 <> w2 <> w3 <> w4 <> w5 <> w6 <> w7 <> w8 <> w9 <> w10 <> w11 <> w12 <> w13 <> w14 <> w15 <> t:
      Sha256.blocks(t, Sha256.compress(s, Win{w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, w14, w15}))
    case _:
      s

# The byte count of a list, as U32 (inputs past 4 GiB wrap).
def Sha256.count(bs: +List<U32>, n: U32) -> U32:
  match bs:
    case Nil{}:
      n
    case b <> t:
      Sha256.count(t, (n + 1 : U32))

# Padding (FIPS 180-4, 5.1.1): 0x80, then k zero bytes with
# n + 1 + k = 56 (mod 64), then the bit length as 8 big-endian bytes.
def Sha256.tail(+n: U32) -> +List<U32>:
  +k = U32.and(U32.sub(55, n), 63)
  +hi = U32.shrn(n, 29n)
  +lo = U32.shln(n, 3n)
  128 <> List.append(&2, U32, List.replicate(U32, U32.to_nat(k), 0),
    [0, 0, 0, U32.and(hi, 255),
     U32.shrn(lo, 24n), U32.and(U32.shrn(lo, 16n), 255),
     U32.and(U32.shrn(lo, 8n), 255), U32.and(lo, 255)])

def Sha256.pad(+bs: +List<U32>) -> +List<U32>:
  List.append(&2, U32, bs, Sha256.tail(Sha256.count(bs, 0)))

# The four big-endian bytes of a word.
def Sha256.bytes(+x: U32, rest: +List<U32>) -> +List<U32>:
  U32.shrn(x, 24n) <> U32.and(U32.shrn(x, 16n), 255) <>
    U32.and(U32.shrn(x, 8n), 255) <> U32.and(x, 255) <> rest

# The 32 digest bytes of a final hash value.
def Sha256.out(s: Sha256.St) -> +List<U32>:
  match s:
    case St{a, b, c, d, e, f, g, h}:
      Sha256.bytes(a, Sha256.bytes(b, Sha256.bytes(c, Sha256.bytes(d,
        Sha256.bytes(e, Sha256.bytes(f, Sha256.bytes(g, Sha256.bytes(h, Nil{}))))))))

# The digest of a byte list.
def Sha256.digest(bs: +List<U32>) -> +List<U32>:
  Sha256.out(Sha256.blocks(Sha256.words(Sha256.pad(bs)), Sha256.init()))

# The UTF-8 bytes of one code point.
def Sha256.utf8_cont(+c: U32, n: Nat) -> U32:
  U32.or(128, U32.and(U32.shrn(c, n), 63))

def Sha256.utf8_wide(+c: U32, rest: +List<U32>, b4: Bool) -> +List<U32>:
  match b4:
    case False{}:
      U32.or(224, U32.shrn(c, 12n)) <> Sha256.utf8_cont(c, 6n) <> Sha256.utf8_cont(c, 0n) <> rest
    case True{}:
      U32.or(240, U32.shrn(c, 18n)) <> Sha256.utf8_cont(c, 12n) <> Sha256.utf8_cont(c, 6n) <>
        Sha256.utf8_cont(c, 0n) <> rest

def Sha256.utf8_mid(+c: U32, rest: +List<U32>, b2: Bool) -> +List<U32>:
  match b2:
    case True{}:
      U32.or(192, U32.shrn(c, 6n)) <> Sha256.utf8_cont(c, 0n) <> rest
    case False{}:
      Sha256.utf8_wide(c, rest, U32.is_ge(c, 65536))

def Sha256.utf8_char(+c: U32, rest: +List<U32>, b1: Bool) -> +List<U32>:
  match b1:
    case True{}:
      c <> rest
    case False{}:
      Sha256.utf8_mid(c, rest, U32.is_lt(c, 2048))

# The UTF-8 bytes of a string (code points past 127 encode as UTF-8).
def Sha256.utf8(s: String) -> +List<U32>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{Chr{+c}, t}:
      Sha256.utf8_char(c, Sha256.utf8(t), U32.is_lt(c, 128))

# The lowercase hex digit of 0..15.
def Sha256.digit(+d: U32) -> Char:
  Chr{(48 + d + 39 * Bool.to_u32(U32.is_gt(d, 9)) : U32)}

# Lowercase hex of a byte list, two digits per byte.
def Sha256.hex(bs: +List<U32>) -> String:
  match bs:
    case Nil{}:
      SNil{}
    case +b <> t:
      SCon{Sha256.digit(U32.and(U32.shrn(b, 4n), 15)),
        SCon{Sha256.digit(U32.and(b, 15)), Sha256.hex(t)}}

# Lowercase hex digest of a string's UTF-8 bytes (Go: hex.EncodeToString(sha256.Sum256([]byte(s)))).
def Sha256.hex_of(s: String) -> String:
  Sha256.hex(Sha256.digest(Sha256.utf8(s)))
