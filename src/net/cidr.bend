import Base

def Cidr.octet.range(ok: Bool, +v: U32) -> Maybe<&2, U32>:
  match ok:
    case True{}:
      Some{v}
    case False{}:
      None{}

def Cidr.octet.go(m: Maybe<&2, U32>, ok: Bool) -> Maybe<&2, U32>:
  match m ok:
    case Some{+v} True{}:
      Cidr.octet.range(U32.is_le(v, 255), v)
    case _ _:
      None{}

# vcluster pkg/util/servicecidr: the host cluster's service CIDR, found by
# probing (a test Service at a chosen cluster IP is accepted only inside
# the range) and binary-searching the prefix around a known service IP,
# as detectIPv4Prefix does. IPv4 only (vk8s hosts); the search is pure, the
# host runs the probes.

def Cidr.octet(+s: String) -> Maybe<&2, U32>:
  Cidr.octet.go(U32.read(s), Bool.not(String.is_empty(s)) && Nat.is_le(String.length(s), 3n))

def Cidr.join4(a: Maybe<&2, U32>, b: Maybe<&2, U32>, c: Maybe<&2, U32>, d: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match a b c d:
    case Some{+w} Some{+x} Some{+y} Some{+z}:
      Some{U32.or(U32.or(U32.shln(w, 24n), U32.shln(x, 16n)), U32.or(U32.shln(y, 8n), z))}
    case _ _ _ _:
      None{}

def Cidr.parse_ip.go(ps: List<&2, String>) -> Maybe<&2, U32>:
  match ps:
    case Con{+a, Con{+b, Con{+c, Con{+d, Nil{}}}}}:
      Cidr.join4(Cidr.octet(a), Cidr.octet(b), Cidr.octet(c), Cidr.octet(d))
    case _:
      None{}

# A dotted IPv4 address.
def Cidr.parse_ip(+s: String) -> Maybe<&2, U32>:
  Cidr.parse_ip.go(String.split(s, '.'))

def Cidr.show_ip(+u: U32) -> String:
  U32.show(U32.shrn(u, 24n)) ++ "." ++ U32.show(U32.and(U32.shrn(u, 16n), 255)) ++ "."
    ++ U32.show(U32.and(U32.shrn(u, 8n), 255)) ++ "." ++ U32.show(U32.and(u, 255))

def Cidr.mask.go(all: Bool, +k: U32) -> U32:
  match all:
    case True{}:
      4294967295
    case False{}:
      U32.shln(4294967295, U32.to_nat((32 - k : U32)))

# The mask of a /k prefix (1 <= k <= 32).
def Cidr.mask(+k: U32) -> U32:
  Cidr.mask.go(U32.is_ge(k, 32), k)

# The search: the known address and the prefix bounds [low, high].
type Search is Data:
  Search{a: U32, low: U32, high: U32}

# A probe: the prefix tried and the two addresses it tests (the first and
# last usable address of that network; a /32 tests its one address).
type Probe is Data:
  Probe{mid: U32, lo: U32, hi: U32}
  Found{k: U32}

def Cidr.start(+a: U32) -> Search:
  Search{a, 1, 32}

def Cidr.probe.ends(one: Bool, +mid: U32, +base: U32, +bcast: U32) -> Probe:
  match one:
    case True{}:
      Probe{mid, base, base}
    case False{}:
      Probe{mid, (base + 1 : U32), (bcast - 1 : U32)}

def Cidr.probe.go(more: Bool, +a: U32, +low: U32, +high: U32) -> Probe:
  match more:
    case False{}:
      Found{low}
    case True{}:
      +mid : U32 = ((low + high) / 2 : U32)
      +m : U32 = Cidr.mask(mid)
      +base : U32 = U32.and(a, m)
      +bcast : U32 = U32.or(base, U32.not(m))
      Cidr.probe.ends(U32.is_eq(mid, 32), mid, base, bcast)

def Cidr.probe(s: Search) -> Probe:
  match s:
    case Search{+a, +low, +high}:
      Cidr.probe.go(U32.is_lt(low, high), a, low, high)

# Both test addresses are in range: the network fits (high = mid);
# otherwise it is larger than the range (low = mid + 1).
def Cidr.answer(s: Search, +mid: U32, ok: Bool) -> Search:
  match s ok:
    case Search{a, low, high} True{}:
      Search{a, low, mid}
    case Search{a, low, high} False{}:
      Search{a, (mid + 1 : U32), high}

# "base/k" for the address and prefix found.
def Cidr.show(+a: U32, +k: U32) -> String:
  Cidr.show_ip(U32.and(a, Cidr.mask(k))) ++ "/" ++ U32.show(k)

# Whether ip is in base/k (a net.IPNet Contains for the laws' ranges).
def Cidr.contains(+base: U32, +k: U32, +ip: U32) -> Bool:
  U32.is_eq(U32.and(ip, Cidr.mask(k)), U32.and(base, Cidr.mask(k)))

def Cidr.detect.go(fuel: Nat, p: Probe, +s: Search, +base: U32, +k: U32) -> U32:
  match fuel p:
    case _ Found{x}:
      x
    case 0n Probe{m, l, h}:
      0
    case 1n+f Probe{+m, +l, +h}:
      +s2 : Search = Cidr.answer(s, m, Bool.and(Cidr.contains(base, k, l), Cidr.contains(base, k, h)))
      Cidr.detect.go(f, Cidr.probe(s2), s2, base, k)

# DetectPrefix with isInRange = base/k contains (servicecidr_test.go).
def Cidr.detect(+a: U32, +base: U32, +k: U32) -> String:
  +s : Search = Cidr.start(a)
  Cidr.show(a, Cidr.detect.go(8n, Cidr.probe(s), s, base, k))
