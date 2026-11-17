import Base

# OCI pull-through mirror: fill and follow. Pure. Part of the
# self-contained OCI library (src/oci/, host/oci/): it imports Base only.
#
# A request for content by digest (a blob, or a manifest by digest) that
# the cache does not hold starts one upstream fetch, the fill. The host
# writes the fill to a temporary file while it hashes it, and every client
# that asked for the digest reads that file as it grows: the first one and
# every later one (they follow the fill). Nothing waits for the whole body:
# each client gets its headers as soon as the upstream's arrive, because
# containerd gives a mirror 30 s to answer.
#
# The machine sees events (Ev) and answers actions (Act) for the host:
#
# - Get: a client asks for a digest. Cached: the host serves it from the
#   cache. A Range request for a digest the cache does not hold goes
#   straight upstream, uncached (Pass). Otherwise the client follows the
#   fill in progress, or starts one (Fetch).
# - Head: the upstream answered (after token auth and redirects, see
#   auth.bend). 200 with a Content-Length: every waiting client gets a 200
#   with that length (Send) and streams the fill. Anything else: every
#   waiting client gets the mapped error (Reply) and the fill ends.
# - Ended: the upstream body ended and the host computed its digest. The
#   fill is committed to the cache only when that digest is the one asked
#   for (Commit). Otherwise it is discarded and every client that streams
#   it is cut off (Abort) before its last byte, so its own digest check
#   fails too: the OCI spec's clients MUST verify a blob's digest.
# - Broke: the upstream connection failed before the end: discard; cut off
#   streaming clients, answer waiting ones with 502.
# - Gone: a client closed its connection; the fill goes on for the cache.
# - Tick: a client that has waited header_s seconds for headers gets 504
#   (below containerd's 30 s, so it falls back to the next host in time);
#   the fill goes on, and later requests follow it.
#
# Caps (Limits): at most `fills` fills at once and `conns` clients waiting
# or streaming in all, and at most `per_digest` clients on one fill; a
# request over a cap gets 429 TOOMANYREQUESTS.
#
# Upstream statuses map to client responses (OCI distribution-spec error
# codes; RFC 9110 for 502 and 504): 404 -> 404 BLOB_UNKNOWN (or
# MANIFEST_UNKNOWN); 401 and 403 (the anonymous token did not grant the
# pull) -> 403 DENIED, so that the client never tries to log in to the
# mirror; 429 -> 429 TOOMANYREQUESTS; anything else, no response (status
# 0), or a 200 without a usable Content-Length -> 502 with no body.
# containerd treats every one of these as "try the next host".

# Types
# -----

type Limits is Data:
  Limits{fills: U32, per_digest: U32, conns: U32, header_s: U32}

# A client on a fill: its connection and when it asked (seconds).
type Wt is Data:
  Wt{conn: U32, since: U32}

# A fill: the digest, blob (False: a manifest by digest), body (the
# upstream's 200 is in, clients stream), the Content-Length as the
# upstream sent it, and its clients in arrival order.
type Entry is Data:
  Entry{digest: String, blob: Bool, body: Bool, len: String, conns: List<&2, Wt>}

type Ev is Data:
  Get{conn: U32, digest: String, blob: Bool, cached: Bool, ranged: Bool, now: U32}
  Head{digest: String, status: U32, len: String}
  Ended{digest: String, got: String}
  Broke{digest: String}
  Gone{conn: U32}
  Tick{now: U32}

type Act is Data:
  # serve conn from the cache
  Cache{conn: U32}
  # proxy conn's request upstream, uncached
  Pass{conn: U32}
  # start the upstream fetch of digest into its fill file
  Fetch{digest: String}
  # answer conn 200 (Content-Length len, Docker-Content-Digest digest) and
  # stream the fill file to it as it grows
  Send{conn: U32, digest: String, len: String}
  # answer conn with an error status and OCI error code ("": no body)
  Reply{conn: U32, status: U32, code: String}
  # move the fill file into the cache
  Commit{digest: String}
  # delete the fill file
  Discard{digest: String}
  # close conn before its body is complete
  Abort{conn: U32}

type Out is Data:
  Out{es: List<&2, Entry>, acts: List<&2, Act>}

type Verdict is Data:
  Keep{}
  Drop{}

# 8 upstream fetches, 128 clients, 32 per digest; 25 s for headers.
def Fill.limits() -> Limits:
  Limits{8, 32, 128, 25}

# Entries
# -------

def Fill.digest(e: Entry) -> String:
  match e:
    case Entry{d, b, body, len, ws}:
      d

def Fill.wlen(ws: List<&2, Wt>) -> U32:
  match ws:
    case Nil{}:
      0
    case Con{w, t}:
      (1 + Fill.wlen(t) : U32)

def Fill.entry_conns(e: Entry) -> U32:
  match e:
    case Entry{d, b, body, len, ws}:
      Fill.wlen(ws)

# Clients on every fill.
def Fill.nconns(es: List<&2, Entry>) -> U32:
  match es:
    case Nil{}:
      0
    case Con{e, t}:
      (Fill.entry_conns(e) + Fill.nconns(t) : U32)

# Fills in progress.
def Fill.count(es: List<&2, Entry>) -> U32:
  match es:
    case Nil{}:
      0
    case Con{e, t}:
      (1 + Fill.count(t) : U32)

def Fill.find.pick(hit: Bool, e: Entry, rest: Maybe<&2, Entry>) -> Maybe<&2, Entry>:
  match hit:
    case True{}:
      Some{e}
    case False{}:
      rest

def Fill.find(es: List<&2, Entry>, +d: String) -> Maybe<&2, Entry>:
  match es:
    case Nil{}:
      None{}
    case Con{+e, t}:
      Fill.find.pick(String.eq(Fill.digest(e), d), e, Fill.find(t, d))

def Fill.without.put(hit: Bool, e: Entry, rest: List<&2, Entry>) -> List<&2, Entry>:
  match hit:
    case True{}:
      rest
    case False{}:
      Con{e, rest}

# The fills less the one for d.
def Fill.without(es: List<&2, Entry>, +d: String) -> List<&2, Entry>:
  match es:
    case Nil{}:
      Nil{}
    case Con{+e, t}:
      Fill.without.put(String.eq(Fill.digest(e), d), e, Fill.without(t, d))

def Fill.replace.one(hit: Bool, e: Entry, n: Entry) -> Entry:
  match hit:
    case True{}:
      n
    case False{}:
      e

# The fills with the one for n's digest replaced by n.
def Fill.replace(es: List<&2, Entry>, +n: Entry) -> List<&2, Entry>:
  match es:
    case Nil{}:
      Nil{}
    case Con{+e, t}:
      Con{Fill.replace.one(String.eq(Fill.digest(e), Fill.digest(n)), e, n), Fill.replace(t, n)}

# Responses
# ---------

def Fill.busy(conn: U32) -> Act:
  Reply{conn, 429, "TOOMANYREQUESTS"}

def Fill.status.go(nf: Bool, denied: Bool, many: Bool) -> U32:
  match nf denied many:
    case True{} _ _:
      404
    case False{} True{} _:
      403
    case False{} False{} True{}:
      429
    case False{} False{} False{}:
      502

# The client's status for an upstream status that is not a usable 200.
def Fill.status(+s: U32) -> U32:
  Fill.status.go(U32.is_eq(s, 404), Bool.or(U32.is_eq(s, 401), U32.is_eq(s, 403)), U32.is_eq(s, 429))

def Fill.code.go(nf: Bool, denied: Bool, many: Bool, blob: Bool) -> String:
  match nf denied many blob:
    case True{} _ _ True{}:
      "BLOB_UNKNOWN"
    case True{} _ _ False{}:
      "MANIFEST_UNKNOWN"
    case False{} True{} _ _:
      "DENIED"
    case False{} False{} True{} _:
      "TOOMANYREQUESTS"
    case False{} False{} False{} _:
      ""

# The OCI error code that goes with it ("": a 502 has no body).
def Fill.code(+s: U32, blob: Bool) -> String:
  Fill.code.go(U32.is_eq(s, 404), Bool.or(U32.is_eq(s, 401), U32.is_eq(s, 403)), U32.is_eq(s, 429), blob)

def Fill.reply(+s: U32, +blob: Bool, conn: U32) -> Act:
  Reply{conn, Fill.status(s), Fill.code(s, blob)}

def Fill.replies(ws: List<&2, Wt>, +s: U32, +blob: Bool) -> List<&2, Act>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{Wt{c, t0}, t}:
      Con{Fill.reply(s, blob, c), Fill.replies(t, s, blob)}

def Fill.sends(ws: List<&2, Wt>, +d: String, +len: String) -> List<&2, Act>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{Wt{c, t0}, t}:
      Con{Send{c, d, len}, Fill.sends(t, d, len)}

def Fill.aborts(ws: List<&2, Wt>) -> List<&2, Act>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{Wt{c, t0}, t}:
      Con{Abort{c}, Fill.aborts(t)}

def Fill.digits(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{Chr{+u}, t}:
      Bool.and(Bool.and(U32.is_ge(u, 48), U32.is_le(u, 57)), Fill.digits(t))

# A Content-Length the mirror can repeat: decimal digits only.
def Fill.len_ok(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{h, t}:
      Fill.digits(SCon{h, t})

# Commit only when the digest the host computed is the one asked for.
def Fill.verdict.go(same: Bool) -> Verdict:
  match same:
    case True{}:
      Keep{}
    case False{}:
      Drop{}

def Fill.verdict(want: String, got: String) -> Verdict:
  Fill.verdict.go(String.eq(want, got))

# Get
# ---

def Fill.start.go(full: Bool, es: List<&2, Entry>, conn: U32, +d: String, blob: Bool, now: U32) -> Out:
  match full:
    case True{}:
      Out{es, [Fill.busy(conn)]}
    case False{}:
      Out{List.append(&2, Entry, es, [Entry{d, blob, False{}, "", [Wt{conn, now}]}]), [Fetch{d}]}

# A miss with no fill in progress: start one, under the caps.
def Fill.start(lim: Limits, +es: List<&2, Entry>, conn: U32, d: String, blob: Bool, now: U32) -> Out:
  match lim:
    case Limits{f, pd, cs, hs}:
      Fill.start.go(Bool.or(U32.is_ge(Fill.count(es), f), U32.is_ge(Fill.nconns(es), cs)), es, conn, d, blob, now)

def Fill.join.out(body: Bool, es: List<&2, Entry>, conn: U32, d: String, len: String) -> Out:
  match body:
    case True{}:
      Out{es, [Send{conn, d, len}]}
    case False{}:
      Out{es, []}

def Fill.join.add(e: Entry, es: List<&2, Entry>, +conn: U32, now: U32) -> Out:
  match e:
    case Entry{+d, blob, +body, +len, ws}:
      Fill.join.out(body, Fill.replace(es, Entry{d, blob, body, len, List.append(&2, Wt, ws, [Wt{conn, now}])}), conn, d, len)

def Fill.join.go(full: Bool, es: List<&2, Entry>, e: Entry, conn: U32, now: U32) -> Out:
  match full:
    case True{}:
      Out{es, [Fill.busy(conn)]}
    case False{}:
      Fill.join.add(e, es, conn, now)

# A miss with a fill in progress: follow it, under the caps.
def Fill.join(lim: Limits, +es: List<&2, Entry>, +e: Entry, conn: U32, now: U32) -> Out:
  match lim:
    case Limits{f, pd, cs, hs}:
      Fill.join.go(Bool.or(U32.is_ge(Fill.entry_conns(e), pd), U32.is_ge(Fill.nconns(es), cs)), es, e, conn, now)

def Fill.get.find(m: Maybe<&2, Entry>, ranged: Bool, lim: Limits, es: List<&2, Entry>, conn: U32, d: String,
  blob: Bool, now: U32) -> Out:
  match m ranged:
    case _ True{}:
      Out{es, [Pass{conn}]}
    case Some{e} False{}:
      Fill.join(lim, es, e, conn, now)
    case None{} False{}:
      Fill.start(lim, es, conn, d, blob, now)

def Fill.get(cached: Bool, lim: Limits, +es: List<&2, Entry>, conn: U32, +d: String, blob: Bool, ranged: Bool,
  now: U32) -> Out:
  match cached:
    case True{}:
      Out{es, [Cache{conn}]}
    case False{}:
      Fill.get.find(Fill.find(es, d), ranged, lim, es, conn, d, blob, now)

# Head, Ended, Broke
# ------------------

# The fill ends without a commit: streaming clients are cut off, waiting
# ones get status s mapped, and the fill file goes.
def Fill.broken(body: Bool, +s: U32, blob: Bool, ws: List<&2, Wt>, es: List<&2, Entry>, +d: String) -> Out:
  match body:
    case True{}:
      Out{Fill.without(es, d), List.append(&2, Act, Fill.aborts(ws), [Discard{d}])}
    case False{}:
      Out{Fill.without(es, d), List.append(&2, Act, Fill.replies(ws, s, blob), [Discard{d}])}

def Fill.head.ok(body: Bool, ok: Bool, +s: U32, blob: Bool, +ws: List<&2, Wt>, +es: List<&2, Entry>, +d: String,
  +len: String) -> Out:
  match body ok:
    case True{} _:
      Out{es, []}
    case False{} True{}:
      Out{Fill.replace(es, Entry{d, blob, True{}, len, ws}), Fill.sends(ws, d, len)}
    case False{} False{}:
      Fill.broken(False{}, s, blob, ws, es, d)

def Fill.head.on(e: Entry, es: List<&2, Entry>, d: String, +s: U32, +len: String) -> Out:
  match e:
    case Entry{ed, blob, body, elen, ws}:
      Fill.head.ok(body, Bool.and(U32.is_eq(s, 200), Fill.len_ok(len)), s, blob, ws, es, d, len)

def Fill.head.go(m: Maybe<&2, Entry>, es: List<&2, Entry>, d: String, s: U32, len: String) -> Out:
  match m:
    case None{}:
      Out{es, []}
    case Some{e}:
      Fill.head.on(e, es, d, s, len)

def Fill.head(+es: List<&2, Entry>, +d: String, s: U32, len: String) -> Out:
  Fill.head.go(Fill.find(es, d), es, d, s, len)

def Fill.ended.on(body: Bool, v: Verdict, blob: Bool, ws: List<&2, Wt>, +es: List<&2, Entry>, +d: String) -> Out:
  match body v:
    case True{} Keep{}:
      Out{Fill.without(es, d), [Commit{d}]}
    case True{} Drop{}:
      Out{Fill.without(es, d), List.append(&2, Act, Fill.aborts(ws), [Discard{d}])}
    case False{} _:
      Fill.broken(False{}, 0, blob, ws, es, d)

def Fill.ended.e(e: Entry, es: List<&2, Entry>, +d: String, got: String) -> Out:
  match e:
    case Entry{ed, blob, body, len, ws}:
      Fill.ended.on(body, Fill.verdict(d, got), blob, ws, es, d)

def Fill.ended.go(m: Maybe<&2, Entry>, es: List<&2, Entry>, d: String, got: String) -> Out:
  match m:
    case None{}:
      Out{es, []}
    case Some{e}:
      Fill.ended.e(e, es, d, got)

def Fill.ended(+es: List<&2, Entry>, +d: String, got: String) -> Out:
  Fill.ended.go(Fill.find(es, d), es, d, got)

def Fill.broke.e(e: Entry, es: List<&2, Entry>, d: String) -> Out:
  match e:
    case Entry{ed, blob, body, len, ws}:
      Fill.broken(body, 0, blob, ws, es, d)

def Fill.broke.go(m: Maybe<&2, Entry>, es: List<&2, Entry>, d: String) -> Out:
  match m:
    case None{}:
      Out{es, []}
    case Some{e}:
      Fill.broke.e(e, es, d)

def Fill.broke(+es: List<&2, Entry>, +d: String) -> Out:
  Fill.broke.go(Fill.find(es, d), es, d)

# Gone, Tick
# ----------

def Fill.drop_conn.put(hit: Bool, w: Wt, rest: List<&2, Wt>) -> List<&2, Wt>:
  match hit:
    case True{}:
      rest
    case False{}:
      Con{w, rest}

def Fill.wconn(w: Wt) -> U32:
  match w:
    case Wt{c, s}:
      c

def Fill.drop_conn(ws: List<&2, Wt>, +conn: U32) -> List<&2, Wt>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{+w, t}:
      Fill.drop_conn.put(U32.is_eq(Fill.wconn(w), conn), w, Fill.drop_conn(t, conn))

def Fill.gone.e(e: Entry, +conn: U32) -> Entry:
  match e:
    case Entry{d, b, body, len, ws}:
      Entry{d, b, body, len, Fill.drop_conn(ws, conn)}

# The fills less a client that closed its connection.
def Fill.gone(es: List<&2, Entry>, +conn: U32) -> List<&2, Entry>:
  match es:
    case Nil{}:
      Nil{}
    case Con{e, t}:
      Con{Fill.gone.e(e, conn), Fill.gone(t, conn)}

def Fill.late.put(late: Bool, c: U32, rest: List<&2, Act>) -> List<&2, Act>:
  match late:
    case True{}:
      Con{Reply{c, 504, ""}, rest}
    case False{}:
      rest

def Fill.is_late(+since: U32, +hs: U32, +now: U32) -> Bool:
  U32.is_ge((now - since : U32), hs)

# 504 for every client that has waited hs seconds or more.
def Fill.late(ws: List<&2, Wt>, +hs: U32, +now: U32) -> List<&2, Act>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{Wt{c, s}, t}:
      Fill.late.put(Fill.is_late(s, hs, now), c, Fill.late(t, hs, now))

def Fill.fresh.put(late: Bool, w: Wt, rest: List<&2, Wt>) -> List<&2, Wt>:
  match late:
    case True{}:
      rest
    case False{}:
      Con{w, rest}

def Fill.wsince(w: Wt) -> U32:
  match w:
    case Wt{c, s}:
      s

# The clients that have waited less than hs seconds.
def Fill.fresh(ws: List<&2, Wt>, +hs: U32, +now: U32) -> List<&2, Wt>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{+w, t}:
      Fill.fresh.put(Fill.is_late(Fill.wsince(w), hs, now), w, Fill.fresh(t, hs, now))

def Fill.tick.body(body: Bool, d: String, b: Bool, len: String, +ws: List<&2, Wt>, +hs: U32, +now: U32) -> Out:
  match body:
    case True{}:
      Out{[Entry{d, b, True{}, len, ws}], []}
    case False{}:
      Out{[Entry{d, b, False{}, len, Fill.fresh(ws, hs, now)}], Fill.late(ws, hs, now)}

def Fill.tick.e(e: Entry, +hs: U32, +now: U32) -> Out:
  match e:
    case Entry{d, b, body, len, ws}:
      Fill.tick.body(body, d, b, len, ws, hs, now)

def Fill.tick.join(a: Out, b: Out) -> Out:
  match a b:
    case Out{e1, a1} Out{e2, a2}:
      Out{List.append(&2, Entry, e1, e2), List.append(&2, Act, a1, a2)}

def Fill.tick.go(es: List<&2, Entry>, +hs: U32, +now: U32) -> Out:
  match es:
    case Nil{}:
      Out{[], []}
    case Con{e, t}:
      Fill.tick.join(Fill.tick.e(e, hs, now), Fill.tick.go(t, hs, now))

def Fill.tick(lim: Limits, es: List<&2, Entry>, +now: U32) -> Out:
  match lim:
    case Limits{f, pd, cs, hs}:
      Fill.tick.go(es, hs, now)

# The machine
# -----------

# One event: the fills after it, and what the host must do, in order.
def Fill.step(lim: Limits, es: List<&2, Entry>, ev: Ev) -> Out:
  match ev:
    case Get{c, d, b, ca, r, n}:
      Fill.get(ca, lim, es, c, d, b, r, n)
    case Head{d, s, len}:
      Fill.head(es, d, s, len)
    case Ended{d, got}:
      Fill.ended(es, d, got)
    case Broke{d}:
      Fill.broke(es, d)
    case Gone{c}:
      Out{Fill.gone(es, c), []}
    case Tick{n}:
      Fill.tick(lim, es, n)

def Fill.run.cat(acc: List<&2, Act>, o: Out) -> Out:
  match o:
    case Out{es, acts}:
      Out{es, List.append(&2, Act, acc, acts)}

def Fill.run.one(+lim: Limits, o: Out, ev: Ev) -> Out:
  match o:
    case Out{es, acts}:
      Fill.run.cat(acts, Fill.step(lim, es, ev))

def Fill.run.more(evs: List<&2, Ev>, +lim: Limits, o: Out) -> Out:
  match evs:
    case Nil{}:
      o
    case Con{ev, t}:
      Fill.run.more(t, lim, Fill.run.one(lim, o, ev))

# Several events in order, from no fills: the fills after them, and every
# action in order. For tests and laws.
def Fill.run(+lim: Limits, evs: List<&2, Ev>) -> Out:
  Fill.run.more(evs, lim, Out{[], []})

def Fill.acts(o: Out) -> List<&2, Act>:
  match o:
    case Out{es, acts}:
      acts

def Fill.es(o: Out) -> List<&2, Entry>:
  match o:
    case Out{es, acts}:
      es
