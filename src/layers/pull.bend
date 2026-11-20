import Base
import ../oci/size.bend as N
import ../oci/grammar.bend as G
import ../lib/sha256.bend as H
import ./tar.bend as T
import ./store.bend as Y
import bend-kube-runtime@0.10.0.0/src/json.bend as J
import bend-kube-runtime@0.10.0.0/src/http.bend as HT

# Pulling an image's layers for the shared layer store
# (src/layers/store.bend): which image a reference names, what to ask
# the registry, and what its answers mean. Pure: the host
# (host/layers/fill.bend) connects, sends and receives; these defs build
# every request and read every answer.
#
# The path: vk8s's image cache (a pull-through registry per upstream in
# the cache VM, on 127.0.0.1:15001-15004, src/guest/plan.bend
# Plan.mirrors) does the upstream's TLS, token auth and redirects. The
# host asks it over plain HTTP/1.1 and writes each layer blob into the
# OCI blob cache (src/oci/store.bend, host/oci/blob.bend), where its
# digest is checked as the bytes pass.
#
# - References are normalized as distribution/reference ParseDockerRef
#   (normalize.go): a first component that is "localhost", holds "." or
#   ":", or has an uppercase letter is the registry, else the registry is
#   docker.io ("index.docker.io" is docker.io too), and a docker.io
#   repository without "/" gets "library/". No tag means "latest"; with a
#   digest, the tag is dropped. A 64-hex name is refused (Go:
#   anchoredIdentifierRegexp).
# - A manifest request accepts what containerd's resolver asks for
#   (core/remotes/docker/resolver.go): Docker schema 2 manifest and list,
#   OCI manifest and index, then */*.
# - An index (or Docker manifest list) gives the first manifest for
#   linux and the host's architecture, the variant normalized as
#   containerd's platforms.Normalize (arm64: "", "8", "v8", "v8.0";
#   amd64: "", "v1").
# - An image manifest gives its config and layer descriptors; the config
#   gives rootfs.diff_ids (rootfs.type must be "layers", image-spec
#   config.md), one per layer, as containerd checks.
# - A layer's compression is containerd's DiffCompression
#   (core/images/mediatypes.go); "unknown" (a Docker layer whose type
#   says no compression) is read from the blob's first bytes, as
#   pkg/archive/compression DetectCompression (gzip 1f 8b 08; zstd
#   28 b5 2f fd, or a skippable frame 50..5f 2a 4d 18). Encrypted layers
#   are refused.

# Image references
# ----------------

# A normalized reference: the registry, the repository, and the tag or
# the digest (digest True) to fetch.
type Img is Data:
  Img{registry: String, repo: String, ref: String, digest: Bool}

def Img.registry(i: Img) -> String:
  match i:
    case Img{r, p, f, d}:
      r

def Img.repo(i: Img) -> String:
  match i:
    case Img{r, p, f, d}:
      p

def Img.ref(i: Img) -> String:
  match i:
    case Img{r, p, f, d}:
      f

def Pull.show.sep(d: Bool) -> String:
  match d:
    case True{}:
      "@"
    case False{}:
      ":"

# The reference in full, as ParseDockerRef's answer prints.
def Pull.show(i: Img) -> String:
  match i:
    case Img{r, p, f, d}:
      r ++ "/" ++ p ++ Pull.show.sep(d) ++ f

# A domain and the rest of the name.
type Split is Data:
  Split{domain: String, rest: String}

# Whether a first component names a registry (splitDockerDomain).
def Pull.is_domain(+first: String) -> Bool:
  String.eq(first, "localhost") || String.contains(first, ".") || String.contains(first, ":") || Bool.not(String.eq(String.to_lower(first), first))

def Pull.split.found(found: Bool, +first: String, +rest: String, +name: String) -> Split:
  match found:
    case False{}:
      Split{"docker.io", name}
    case True{}:
      Bool.pick(Split, String.eq(first, "index.docker.io"), Split{"docker.io", rest},
        Bool.pick(Split, Pull.is_domain(first), Split{first, rest}, Split{"docker.io", name}))

def Pull.split.cut(c: T.SCut, +name: String) -> Split:
  match c:
    case T.SCut{first, rest, found}:
      Pull.split.found(found, first, rest, name)

# Docker Hub's official images live under library/.
def Pull.split.fix(s: Split) -> Split:
  match s:
    case Split{+d, +r}:
      Bool.pick(Split, String.eq(d, "docker.io") && Bool.not(String.contains(r, "/")), Split{d, "library/" ++ r}, Split{d, r})

def Pull.parse.pick(ok: Bool, +d: String, +repo: String, +tag: String, +hast: Bool, +dg: String, +hasd: Bool) -> Maybe<&2, Img>:
  match ok:
    case False{}:
      None{}
    case True{}:
      Some{Bool.pick(Img, hasd, Img{d, repo, dg, True{}}, Img{d, repo, Bool.pick(String, hast, tag, "latest"), False{}})}

def Pull.digest_ok(+s: String) -> Bool:
  Maybe.is_some(&2, G.Digest, G.Gram.digest(s))

def Pull.parse.tag(c: T.SCut, +d: String, +dg: String, +hasd: Bool) -> Maybe<&2, Img>:
  match c:
    case T.SCut{+repo, +tag, +hast}:
      Pull.parse.pick(G.Gram.registry(d) && G.Gram.name(repo) && (Bool.not(hast) || G.Gram.tag(tag)) && (Bool.not(hasd) || Pull.digest_ok(dg)),
        d, repo, tag, hast, dg, hasd)

def Pull.parse.at(c: T.SCut, +d: String) -> Maybe<&2, Img>:
  match c:
    case T.SCut{nt, dg, hasd}:
      Pull.parse.tag(T.Tar.scut(nt, ':'), d, dg, hasd)

def Pull.parse.split(s: Split) -> Maybe<&2, Img>:
  match s:
    case Split{d, r}:
      Pull.parse.at(T.Tar.scut(r, '@'), d)

def Pull.ref.go(hex: Bool, +s: String) -> Maybe<&2, Img>:
  match hex:
    case True{}:
      None{}
    case False{}:
      Pull.parse.split(Pull.split.fix(Pull.split.cut(T.Tar.scut(s, '/'), s)))

# The image a reference names, or None when it is not a valid one.
def Pull.ref(+s: String) -> Maybe<&2, Img>:
  Pull.ref.go(G.Gram.hex64(s), s)

# The image cache
# ---------------

# A registry the image cache serves, and its port on 127.0.0.1.
type Mirror is Data:
  Mirror{registry: String, port: U32}

# The port of registry's pull-through cache, or None when the cache does
# not serve it.
def Pull.port(ms: List<&2, Mirror>, +reg: String) -> Maybe<&2, U32>:
  match ms:
    case Nil{}:
      None{}
    case Con{Mirror{r, p}, t}:
      Bool.pick(Maybe<&2, U32>, String.eq(r, reg), Some{p}, Pull.port(t, reg))

# Requests
# --------

def Pull.accept() -> String:
  "application/vnd.docker.distribution.manifest.v2+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.oci.image.index.v1+json, */*"

def Pull.get(+port: U32, repo: String, kind: String, ref: String, accept: String) -> String:
  "GET /v2/" ++ repo ++ "/" ++ kind ++ "/" ++ ref ++ " HTTP/1.1\r\nHost: 127.0.0.1:" ++ U32.show(port) ++ "\r\nUser-Agent: vk8s\r\nAccept: " ++ accept ++ "\r\nConnection: close\r\n\r\n"

# The request for a manifest (by tag or digest) of repo, to the cache on
# port.
def Pull.get.manifest(+port: U32, repo: String, ref: String) -> String:
  Pull.get(port, repo, "manifests", ref, Pull.accept())

# The request for a blob (a config or a layer) of repo.
def Pull.get.blob(+port: U32, repo: String, digest: String) -> String:
  Pull.get(port, repo, "blobs", digest, "*/*")

# Responses
# ---------

# The bytes of a response so far, cut after the head's CRLF CRLF.
type Halves is Data:
  Halves{head: +List<U32>, body: +List<U32>, found: Bool}

def Pull.crlf2(bs: +List<U32>) -> Bool:
  match bs:
    case Con{a, Con{b, Con{c, Con{d, t}}}}:
      U32.is_eq(a, 13) && U32.is_eq(b, 10) && U32.is_eq(c, 13) && U32.is_eq(d, 10)
    case _:
      False{}

def Pull.halves.cons(c: U32, r: Halves) -> Halves:
  match r:
    case Halves{h, b, f}:
      Halves{Con{c, h}, b, f}

def Pull.halves.at(hit: Bool, c: U32, +t: +List<U32>, r: Halves) -> Halves:
  match hit:
    case True{}:
      Halves{Nil{}, List.drop(&2, U32, t, 3n), True{}}
    case False{}:
      Pull.halves.cons(c, r)

def Pull.halves(bs: +List<U32>) -> Halves:
  match bs:
    case Nil{}:
      Halves{Nil{}, Nil{}, False{}}
    case Con{+c, +t}:
      Pull.halves.at(Pull.crlf2(Con{c, t}), c, t, Pull.halves(t))

# What the bytes of a response so far are.
type Got is Data:
  # the head has not ended yet: read more
  GMore{}
  GBad{why: String}
  # the status, the Content-Length, and the body bytes that came along
  GHead{status: U32, length: Maybe<&2, N.Size>, body: +List<U32>}

def Pull.length(m: Maybe<&2, String>) -> Maybe<&2, N.Size>:
  match m:
    case None{}:
      None{}
    case Some{s}:
      N.Size.read(String.trim(s))

def Pull.got.head(m: Maybe<&2, HT.Head>, body: +List<U32>) -> Got:
  match m:
    case None{}:
      GBad{"the image cache sent a malformed response head"}
    case Some{HT.Head{st, r, hs}}:
      GHead{st, Pull.length(HT.Http.find(hs, "content-length")), body}

def Pull.got.cut(h: Halves) -> Got:
  match h:
    case Halves{head, body, found}:
      Bool.pick(Got, found, Pull.got.head(HT.Http.parse_head(T.Tar.s(head)), body), GMore{})

# The bytes of a response received so far.
def Pull.got(bs: +List<U32>) -> Got:
  Pull.got.cut(Pull.halves(bs))

# The most a head may take before the host gives up (64 KiB).
def Pull.head_max() -> U32:
  65536

# The most a manifest or a config may take (4 MiB, containerd's
# limit on manifests, core/remotes/docker/fetcher.go).
def Pull.doc_max() -> U32:
  4194304

# Whether bytes hash to digest ("sha256:" and the hex).
def Pull.verified(+digest: String, bs: +List<U32>) -> Bool:
  String.eq(digest, "sha256:" ++ H.Sha256.hex(H.Sha256.digest(bs)))

# Manifests
# ---------

# A content descriptor: media type, digest and size.
type Desc is Data:
  Desc{media: String, digest: String, size: N.Size}

def Desc.media(d: Desc) -> String:
  match d:
    case Desc{m, g, s}:
      m

def Desc.digest(d: Desc) -> String:
  match d:
    case Desc{m, g, s}:
      g

def Desc.size(d: Desc) -> N.Size:
  match d:
    case Desc{m, g, s}:
      s

# What a manifest says.
type Man is Data:
  # an index: fetch this manifest (by digest) next
  MIndex{digest: String}
  MImage{config: Desc, layers: List<&2, Desc>}
  MBad{why: String}

def Pull.num(j: J.Json) -> Maybe<&2, N.Size>:
  match j:
    case J.JNum{t}:
      N.Size.read(t)
    case _:
      None{}

def Pull.desc.make(m: Maybe<&2, String>, d: Maybe<&2, String>, s: Maybe<&2, N.Size>) -> Maybe<&2, Desc>:
  match m d s:
    case Some{mt} Some{+dg} Some{sz}:
      Bool.pick(Maybe<&2, Desc>, Pull.digest_ok(dg), Some{Desc{mt, dg, sz}}, None{})
    case _ _ _:
      None{}

def Pull.desc(+j: J.Json) -> Maybe<&2, Desc>:
  Pull.desc.make(J.Json.as_str(J.Json.get(j, "mediaType")), J.Json.as_str(J.Json.get(j, "digest")), Pull.num(J.Json.get(j, "size")))

def Pull.descs.cons(m: Maybe<&2, Desc>, r: Maybe<&2, List<&2, Desc>>) -> Maybe<&2, List<&2, Desc>>:
  match m r:
    case Some{d} Some{ds}:
      Some{Con{d, ds}}
    case _ _:
      None{}

def Pull.descs(js: List<&2, J.Json>) -> Maybe<&2, List<&2, Desc>>:
  match js:
    case Nil{}:
      Some{Nil{}}
    case Con{j, t}:
      Pull.descs.cons(Pull.desc(j), Pull.descs(t))

# A variant that platforms.Normalize turns into none for arch.
def Pull.variant(+arch: String, +v: String) -> Bool:
  String.is_empty(v) || (String.eq(arch, "arm64") && (String.eq(v, "v8") || String.eq(v, "8") || String.eq(v, "v8.0"))) || (String.eq(arch, "amd64") && String.eq(v, "v1"))

# Whether an index entry is for linux on arch.
def Pull.plat(+arch: String, +j: J.Json) -> Bool:
  String.eq(J.Json.str_or(J.Json.at(j, ["platform", "os"]), ""), "linux") && String.eq(J.Json.str_or(J.Json.at(j, ["platform", "architecture"]), ""), arch) && Pull.variant(arch, J.Json.str_or(J.Json.at(j, ["platform", "variant"]), ""))

def Pull.index.child(m: Maybe<&2, String>) -> Man:
  match m:
    case None{}:
      MBad{"image index: an entry without a digest"}
    case Some{+d}:
      Bool.pick(Man, Pull.digest_ok(d), MIndex{d}, MBad{"image index: invalid digest " ++ d})

def Pull.index.pick(ok: Bool, +j: J.Json, rest: Man) -> Man:
  match ok:
    case True{}:
      Pull.index.child(J.Json.as_str(J.Json.get(j, "digest")))
    case False{}:
      rest

def Pull.index(js: List<&2, J.Json>, +arch: String) -> Man:
  match js:
    case Nil{}:
      MBad{"no linux/" ++ arch ++ " image in the image index"}
    case Con{+j, t}:
      Pull.index.pick(Pull.plat(arch, j), j, Pull.index(t, arch))

def Pull.image.make(c: Maybe<&2, Desc>, ls: Maybe<&2, List<&2, Desc>>) -> Man:
  match c ls:
    case Some{cd} Some{ds}:
      MImage{cd, ds}
    case _ _:
      MBad{"image manifest: an invalid config or layer descriptor"}

def Pull.manifest.json(+arch: String, +j: J.Json) -> Man:
  Bool.pick(Man, J.Json.is_null(J.Json.get(j, "manifests")),
    Bool.pick(Man, J.Json.is_null(J.Json.get(j, "layers")), MBad{"neither an image index nor an image manifest"},
      Pull.image.make(Pull.desc(J.Json.get(j, "config")), Pull.descs(J.Json.items(J.Json.get(j, "layers"))))),
    Pull.index(J.Json.items(J.Json.get(j, "manifests")), arch))

def Pull.manifest.parsed(r: Result<&2, &2, String, J.Json>, +arch: String) -> Man:
  match r:
    case Fail{e}:
      MBad{"manifest: " ++ e}
    case Done{+j}:
      Pull.manifest.json(arch, j)

# What a manifest's body says, for a host of arch ("arm64", "amd64").
def Pull.manifest(+arch: String, body: String) -> Man:
  Pull.manifest.parsed(J.Json.parse(body), arch)

# Configs
# -------

def Pull.diff(m: Maybe<&2, String>) -> Maybe<&2, String>:
  match m:
    case None{}:
      None{}
    case Some{+d}:
      Bool.pick(Maybe<&2, String>, Pull.digest_ok(d), Some{d}, None{})

def Pull.diffs.cons(m: Maybe<&2, String>, r: Maybe<&2, List<&2, String>>) -> Maybe<&2, List<&2, String>>:
  match m r:
    case Some{d} Some{ds}:
      Some{Con{d, ds}}
    case _ _:
      None{}

def Pull.diffs(js: List<&2, J.Json>) -> Maybe<&2, List<&2, String>>:
  match js:
    case Nil{}:
      Some{Nil{}}
    case Con{j, t}:
      Pull.diffs.cons(Pull.diff(J.Json.as_str(j)), Pull.diffs(t))

def Pull.config.json(+j: J.Json) -> Maybe<&2, List<&2, String>>:
  Bool.pick(Maybe<&2, List<&2, String>>, String.eq(J.Json.str_or(J.Json.at(j, ["rootfs", "type"]), ""), "layers"),
    Pull.diffs(J.Json.items(J.Json.at(j, ["rootfs", "diff_ids"]))), None{})

def Pull.config.parsed(r: Result<&2, &2, String, J.Json>) -> Maybe<&2, List<&2, String>>:
  match r:
    case Fail{e}:
      None{}
    case Done{+j}:
      Pull.config.json(j)

# The diffIDs of an image config's body, in order, or None.
def Pull.config(body: String) -> Maybe<&2, List<&2, String>>:
  Pull.config.parsed(J.Json.parse(body))

# Compression
# -----------

type Comp is Data:
  CNone{}
  CGzip{}
  CZstd{}
  # containerd's "unknown": read the blob's first bytes (Pull.sniff)
  CSniff{}
  CBad{why: String}

def Pull.comp.docker(+ext: String, +bare: Comp) -> Comp:
  Bool.pick(Comp, String.is_empty(ext), bare, CNone{})

def Pull.comp.oci(+ext: String) -> Comp:
  Bool.pick(Comp, String.is_empty(ext), CNone{},
    Bool.pick(Comp, String.eq(ext, "gzip"), CGzip{},
      Bool.pick(Comp, String.eq(ext, "zstd"), CZstd{}, CBad{"unsupported layer media type suffix +" ++ ext})))

def Pull.comp.base(+base: String, +ext: String, +mt: String) -> Comp:
  Bool.pick(Comp, String.eq(base, "application/vnd.docker.image.rootfs.diff.tar") || String.eq(base, "application/vnd.docker.image.rootfs.foreign.diff.tar"), Pull.comp.docker(ext, CSniff{}),
  Bool.pick(Comp, String.eq(base, "application/vnd.docker.image.rootfs.diff.tar.gzip") || String.eq(base, "application/vnd.docker.image.rootfs.foreign.diff.tar.gzip"), Pull.comp.docker(ext, CGzip{}),
  Bool.pick(Comp, String.eq(base, "application/vnd.docker.image.rootfs.diff.tar.zstd"), Pull.comp.docker(ext, CZstd{}),
  Bool.pick(Comp, String.eq(base, "application/vnd.oci.image.layer.v1.tar") || String.eq(base, "application/vnd.oci.image.layer.nondistributable.v1.tar"), Pull.comp.oci(ext),
    CBad{"unrecognised layer media type " ++ mt}))))

def Pull.comp.cut(c: T.SCut, +mt: String) -> Comp:
  match c:
    case T.SCut{base, +ext, found}:
      Bool.pick(Comp, String.contains(ext, "encrypted"), CBad{"encrypted layers are not supported: " ++ mt}, Pull.comp.base(base, ext, mt))

# How a layer of media type mt is compressed (DiffCompression).
def Pull.comp(+mt: String) -> Comp:
  Pull.comp.cut(T.Tar.scut(mt, '+'), mt)

def Pull.starts(bs: +List<U32>, +pre: +List<U32>) -> Bool:
  T.Tar.beq(List.take(&2, U32, bs, List.length(&2, U32, pre)), pre)

# A zstd skippable frame: magic 0x184D2A50 to 0x184D2A5F, little-endian,
# in a source of at least 8 bytes.
def Pull.skippable(+bs: +List<U32>) -> Bool:
  Nat.is_ge(List.length(&2, U32, bs), 8n) && U32.is_eq(U32.and(Maybe.default(&2, U32, List.get(&2, U32, bs, 0n), 0), 240), 80) && Pull.starts(List.drop(&2, U32, bs, 1n), [42, 77, 24])

# The compression of a blob from its first bytes (at least 8 when the
# blob has them).
def Pull.sniff(+bs: +List<U32>) -> Comp:
  Bool.pick(Comp, Pull.starts(bs, [31, 139, 8]), CGzip{},
    Bool.pick(Comp, Pull.starts(bs, [40, 181, 47, 253]) || Pull.skippable(bs), CZstd{}, CNone{}))

# The message when a layer does not decompress: Unz's own, but for a
# zstd layer on a host without libzstd (bend-kube's unz.c answers "unz:
# zstd (libzstd) is not installed"), the fix.
def Pull.unz_why(+zstd: Bool, +msg: String) -> String:
  Bool.pick(String, zstd && String.contains(msg, "libzstd"),
    "the layer is zstd-compressed and libzstd is not installed: install it (macOS: brew install zstd; Debian or Ubuntu: apt install libzstd1), or set UNZ_ZSTD to the library's path",
    "decompressing the layer failed: " ++ msg)

# Layers
# ------

# One layer to fill: its chain ID, diffID and parent chain ID ("" for the
# first), its blob, and how the blob is compressed.
type Fill is Data:
  Fill{chain: String, diff: String, parent: String, blob: Desc, comp: Comp}

def Pull.fills.cons(f: Fill, r: Maybe<&2, List<&2, Fill>>) -> Maybe<&2, List<&2, Fill>>:
  match r:
    case None{}:
      None{}
    case Some{fs}:
      Some{Con{f, fs}}

def Pull.fills.go(ds: List<&2, String>, bs: List<&2, Desc>, +parent: String) -> Maybe<&2, List<&2, Fill>>:
  match ds bs:
    case Nil{} Nil{}:
      Some{Nil{}}
    case Con{+d, dt} Con{+b, bt}:
      +c : String = Y.Lay.chain(parent, d)
      Pull.fills.cons(Fill{c, d, parent, b, Pull.comp(Desc.media(b))}, Pull.fills.go(dt, bt, c))
    case _ _:
      None{}

# The layers of an image: the config's diffIDs with the manifest's layer
# descriptors, in order, chain IDs computed (Lay.chains). None when the
# counts differ (containerd: "mismatched image rootfs and manifest
# layers").
def Pull.fills(ds: List<&2, String>, bs: List<&2, Desc>) -> Maybe<&2, List<&2, Fill>>:
  Pull.fills.go(ds, bs, "")
