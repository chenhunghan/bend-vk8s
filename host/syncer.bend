import Base
import bend-kube-runtime@0.4.0.0/src/json.bend as J
import bend-kube-runtime@0.4.0.0/src/core.bend as C
import bend-kube-runtime@0.4.0.0/src/config.bend as K
import bend-kube-runtime@0.4.0.0/src/client.bend as Cl
import bend-kube-runtime@0.4.0.0/src/watcher.bend as W
import bend-kube-runtime@0.4.0.0/src/store.bend as St
import bend-kube-runtime@0.4.0.0/src/queue.bend as Q
import bend-kube-runtime@0.4.0.0/src/runtime.bend as R
import bend-kube-runtime@0.4.0.0/src/leader.bend as E
import bend-kube-runtime@0.4.0.0/src/log.bend as L
import bend-kube-runtime@0.4.0.0/src/kube.bend as Kb
import bend-kube-runtime@0.2.0.0/src/json.bend as J2
import ../src/sync/runtime.bend as RT
import ../src/translate/services.bend as S

# The classic-mode syncer (vcluster's syncer pod), run as
# `vk8s-init syncer --host-kubeconfig F --host-namespace NS --name VC
# --service-cidr CIDR [--kubeconfig VIRTUAL]`.
#
# bend-kube-runtime@0.4.0.0 (BendHub hash 0xd9e5cff93d88385a2d6e80af4f4859e0)
# supplies the pieces: one watcher driver (R.Ctl.watch.subs) per resource
# and cluster, all feeding one inbox; the stores (St) and the work queue (Q)
# are pure values this loop owns. The virtual watches are primary; the host
# watches cover the host namespace with the managed-by label, and a host
# object queues the virtual key its object-name/object-namespace
# annotations name. Deletions, and objects that vanished across a relist,
# queue their key too, so a reconcile sees the object gone.
#
# One Lease (virtual kube-system, vcluster-syncer-<vc>) gates everything:
# the watches start only on the leader, and losing the Lease exits the
# process. Reconciles run one at a time; each reads both stores and the
# snapshots of its last successful reconcile, calls the pure step
# (src/sync/runtime.bend) and makes its writes in order, stopping at the
# first error.
#
# The pure translators use bend-kube-runtime@0.2.0.0's JSON; objects cross
# that boundary as JSON text.

# Both clusters, the translator config and the host namespace.
type Env is Data:
  Env{v: K.Config, h: K.Config, c: S.Cfg, ns: String}

def Env.v(e: Env) -> K.Config:
  match e:
    case Env{v, h, c, ns}:
      v

def Env.h(e: Env) -> K.Config:
  match e:
    case Env{v, h, c, ns}:
      h

def Env.c(e: Env) -> S.Cfg:
  match e:
    case Env{v, h, c, ns}:
      c

def Env.ns(e: Env) -> String:
  match e:
    case Env{v, h, c, ns}:
      ns

def Env.cfg(host: Bool, +e: Env) -> K.Config:
  match host:
    case True{}:
      Env.h(e)
    case False{}:
      Env.v(e)

# The loop's state: one store per watch source, the queue of virtual keys,
# and per key the virtual and host objects of its last successful
# reconcile (JNull: none).
type SSt is Data:
  SSt{stores: List<&2, St.Store>, q: Q.Queue, vlast: Map<&2, J2.Json>, hlast: Map<&2, J2.Json>}

# What a reconcile did: the queue action, the snapshots it used, and
# whether every write landed.
type Rec is Data:
  Rec{act: Q.Action, v: J2.Json, h: J2.Json, ok: Bool}

# JSON across the package boundary.

def Sync.to2.r(r: Result<&2, &2, String, J2.Json>) -> J2.Json:
  match r:
    case Done{x}:
      x
    case Fail{e}:
      J2.JNull{}

def Sync.to2(x: J.Json) -> J2.Json:
  Sync.to2.r(J2.Json.parse(J.Json.show(x)))

def Sync.to4.r(r: Result<&2, &2, String, J.Json>) -> J.Json:
  match r:
    case Done{x}:
      x
    case Fail{e}:
      J.JNull{}

def Sync.to4(x: J2.Json) -> J.Json:
  Sync.to4.r(J.Json.parse(J2.Json.show(x)))

def Sync.some2(m: Maybe<&2, J.Json>) -> Maybe<&2, J2.Json>:
  match m:
    case None{}:
      None{}
    case Some{x}:
      Some{Sync.to2(x)}

def Sync.all2(xs: List<&2, J.Json>) -> List<&2, J2.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      Sync.to2(x) <> Sync.all2(t)

def Sync.or_null(m: Maybe<&2, J2.Json>) -> J2.Json:
  match m:
    case None{}:
      J2.JNull{}
    case Some{x}:
      x

def Sync.of_null(x: J2.Json) -> Maybe<&2, J2.Json>:
  match x:
    case J2.JNull{}:
      None{}
    case y:
      Some{y}

def Sync.last.fin(r: Map<&2, J2.Json> & J2.Json) -> Maybe<&2, J2.Json>:
  match r:
    case (m, x):
      Sync.of_null(x)

def Sync.last(+m: Map<&2, J2.Json>, key: String) -> Maybe<&2, J2.Json>:
  Sync.last.fin(Map.get(J2.Json, J2.JNull{}, m, key))

# Resources.

def Sync.config_res(r: RT.ConfigResource) -> C.Res:
  match r:
    case RT.ConfigMapResource{}:
      C.Res.config_maps()
    case RT.SecretResource{}:
      C.Res.secrets()
    case RT.ServiceAccountResource{}:
      C.Res.core("ServiceAccount", "serviceaccounts", True{})

def Sync.res(k: RT.Kind) -> C.Res:
  match k:
    case RT.KServices{}:
      C.Res.services()
    case RT.KConfigs{r}:
      Sync.config_res(r)

def Sync.api(k: RT.Kind, +ns: String) -> C.Api:
  C.Api{Sync.res(k), C.InNs{ns}}

# Watch sources: 2i and 2i+1 for kind i of RT.Runtime.wired (virtual,
# host), then the virtual pods.
def Sync.pods_src() -> U32:
  (U32.from_nat(List.length(&2, RT.Kind, RT.Runtime.wired())) * 2 : U32)

def Sync.nsrc() -> Nat:
  Nat.add(U32.to_nat(Sync.pods_src()), 1n)

def Sync.watch(+cfg: K.Config, api: C.Api, label: String, +chan: Chan(R.Msg), +src: U32) -> IO(Unit):
  R.Ctl.watch.subs(cfg, api, label, "", [R.Sub{chan, src}])

def Sync.watches(ks: List<&2, RT.Kind>, +e: Env, +chan: Chan(R.Msg), +i: U32) -> IO(Unit):
  match ks:
    case Nil{}:
      Sync.watch(Env.v(e), C.Api{C.Res.pods(), C.AllNs{}}, "", chan, i)
    case Con{+k, t}:
      do IO<Unit>:
        Sync.watch(Env.v(e), C.Api{Sync.res(k), C.AllNs{}}, "", chan, i)
        Sync.watch(Env.h(e), Sync.api(k, Env.ns(e)), RT.Runtime.selector(S.Svc.vc(Env.c(e))), chan, (i + 1 : U32))
        Sync.watches(t, e, chan, (i + 2 : U32))

# Keys a batch of watch outputs queues.

def Sync.kind_keys(m: Maybe<&2, RT.Kind>, host: Bool, +c: S.Cfg, +y: J2.Json) -> List<&2, String>:
  match m:
    case None{}:
      Nil{}
    case Some{k}:
      RT.Runtime.obj_key(k, host, c, y)

def Sync.obj_keys.go(pod: Bool, +src: U32, +c: S.Cfg, +y: J2.Json) -> List<&2, String>:
  match pod:
    case True{}:
      RT.Runtime.pod_keys(c, y)
    case False{}:
      Sync.kind_keys(RT.Runtime.kind_nth(U32.to_nat((src / 2 : U32))), U32.is_eq((src % 2 : U32), 1), c, y)

def Sync.obj_keys(+src: U32, +c: S.Cfg, x: J.Json) -> List<&2, String>:
  Sync.obj_keys.go(U32.is_eq(src, Sync.pods_src()), src, c, Sync.to2(x))

def Sync.dropped_key(+src: U32, +c: S.Cfg, m: Maybe<&2, J.Json>, rest: List<&2, String>) -> List<&2, String>:
  match m:
    case None{}:
      rest
    case Some{x}:
      List.append(&2, String, Sync.obj_keys(src, c, x), rest)

# The objects a relist is about to drop are still in the store: their
# keys come from them as cached.
def Sync.dropped_keys(+src: U32, +c: S.Cfg, +s: St.Store, ks: List<&2, String>) -> List<&2, String>:
  match ks:
    case Nil{}:
      Nil{}
    case Con{k, t}:
      Sync.dropped_key(src, c, St.Store.get(s, k), Sync.dropped_keys(src, c, s, t))

def Sync.out_keys(+src: U32, +c: S.Cfg, +s: St.Store, o: W.Out) -> List<&2, String>:
  match o:
    case W.OInit{}:
      Nil{}
    case W.OInitApply{x}:
      Sync.obj_keys(src, c, x)
    case W.OApply{x}:
      Sync.obj_keys(src, c, x)
    case W.ODelete{x}:
      Sync.obj_keys(src, c, x)
    case W.OInitDone{}:
      Sync.dropped_keys(src, c, s, St.Store.dropped(s))

def Sync.fold(outs: List<&2, W.Out>, +src: U32, +c: S.Cfg, +s: St.Store, keys: List<&2, String>) ->
  St.Store & List<&2, String>:
  match outs:
    case Nil{}:
      (s, keys)
    case Con{+o, t}:
      Sync.fold(t, src, c, St.Store.apply(s, o), List.append(&2, String, Sync.out_keys(src, c, s, o), keys))

def Sync.on_outs.put(ss: List<&2, St.Store>, +src: U32, q: Q.Queue, vl: Map<&2, J2.Json>,
  hl: Map<&2, J2.Json>, r: St.Store & List<&2, String>) -> SSt:
  match r:
    case (s, ks):
      SSt{R.Caches.set(ss, U32.to_nat(src), s), Q.Queue.add_all(ks, q), vl, hl}

def Sync.on_outs(st: SSt, +src: U32, outs: List<&2, W.Out>, +c: S.Cfg) -> SSt:
  match st:
    case SSt{+ss, q, vl, hl}:
      Sync.on_outs.put(ss, src, q, vl, hl, Sync.fold(outs, src, c, R.Caches.nth(ss, U32.to_nat(src)), Nil{}))

def Sync.on_wake(st: SSt, +key: String, +gen: U32) -> SSt:
  match st:
    case SSt{ss, q, vl, hl}:
      SSt{ss, Q.Queue.wake(q, key, gen), vl, hl}

# Every store has listed: reconciles may start.
def Sync.ready(st: SSt) -> Bool:
  match st:
    case SSt{ss, q, vl, hl}:
      R.Caches.ready(ss)

# Writes.

def Sync.gone_ok.if(gone: Bool, e: Cl.KErr) -> Result<&2, &2, Cl.KErr, J.Json>:
  match gone:
    case True{}:
      Done{J.JNull{}}
    case False{}:
      Fail{e}

def Sync.gone_ok(r: Result<&2, &2, Cl.KErr, J.Json>) -> Result<&2, &2, Cl.KErr, J.Json>:
  match r:
    case Done{x}:
      Done{x}
    case Fail{+e}:
      Sync.gone_ok.if(Cl.KErr.is_not_found(e), e)

def Sync.call(c: RT.Call, +e: Env, +k: RT.Kind) -> IO(Result<&2, &2, Cl.KErr, J.Json>):
  match c:
    case RT.CCreate{host, ns, o}:
      Cl.Client.create(Env.cfg(host, e), Sync.api(k, ns), Sync.to4(o))
    case RT.CUpdate{host, ns, name, o}:
      Cl.Client.replace(Env.cfg(host, e), Sync.api(k, ns), name, Sync.to4(o))
    case RT.CDelete{host, ns, name}:
      IO.bind(Result<&2, &2, Cl.KErr, J.Json>, Result<&2, &2, Cl.KErr, J.Json>,
        Cl.Client.delete(Env.cfg(host, e), Sync.api(k, ns), name),
        r => IO.pure(Result<&2, &2, Cl.KErr, J.Json>, Sync.gone_ok(r)))

# The writes in order; the first failure stops the rest.
def Sync.apply(ws: List<&2, S.Write>, r: Result<&2, &2, Cl.KErr, J.Json>, +e: Env, +k: RT.Kind) ->
  IO(Result<&2, &2, Cl.KErr, Unit>):
  match ws r:
    case w Fail{err}:
      IO.pure(Result<&2, &2, Cl.KErr, Unit>, Fail{err})
    case Nil{} Done{x}:
      IO.pure(Result<&2, &2, Cl.KErr, Unit>, Done{Unit{}})
    case Con{w, t} Done{x}:
      IO.bind(Result<&2, &2, Cl.KErr, J.Json>, Result<&2, &2, Cl.KErr, Unit>,
        Sync.call(RT.Runtime.call(w), e, k), r2 => Sync.apply(t, r2, e, k))

def Sync.action(rq: S.Requeue) -> Q.Action:
  match rq:
    case S.NoRequeue{}:
      Q.AwaitChange{}
    case S.RequeueNow{}:
      Q.Requeue{0}
    case S.RequeueAfter{s}:
      Q.Requeue{RT.Runtime.delay(S.RequeueAfter{s})}

def Sync.rec_of(r: Result<&2, &2, Cl.KErr, Unit>, +rq: S.Requeue, +v: J2.Json, +h: J2.Json) -> Rec:
  match r:
    case Done{u}:
      Rec{Sync.action(rq), v, h, True{}}
    case Fail{+err}:
      Rec{Cl.KErr.action(err), v, h, False{}}

def Sync.report(+key: String, r: Rec) -> IO(Rec):
  match r:
    case Rec{Q.Retry{+m}, v, h, ok}:
      IO.bind(Unit, Rec, L.Log.warn("sync failed", [L.Log.kv("key", key), L.Log.kv("error", m)]),
        u => IO.pure(Rec, Rec{Q.Retry{m}, v, h, ok}))
    case Rec{Q.RetryIn{+m, ms}, v, h, ok}:
      IO.bind(Unit, Rec, L.Log.warn("sync failed", [L.Log.kv("key", key), L.Log.kv("error", m)]),
        u => IO.pure(Rec, Rec{Q.RetryIn{m, ms}, v, h, ok}))
    case x:
      IO.pure(Rec, x)

def Sync.run_out(out: S.Outcome, +key: String, +e: Env, +k: RT.Kind, +v: J2.Json, +h: J2.Json) -> IO(Rec):
  match out:
    case S.Outcome{ws, +rq}:
      IO.bind(Result<&2, &2, Cl.KErr, Unit>, Rec, Sync.apply(ws, Done{J.JNull{}}, e, k),
        r => Sync.report(key, Sync.rec_of(r, rq, v, h)))

def Sync.store(st: SSt, n: Nat) -> St.Store:
  match st:
    case SSt{ss, q, vl, hl}:
      R.Caches.nth(ss, n)

def Sync.vlast(st: SSt, key: String) -> Maybe<&2, J2.Json>:
  match st:
    case SSt{ss, q, vl, hl}:
      Sync.last(vl, key)

def Sync.hlast(st: SSt, key: String) -> Maybe<&2, J2.Json>:
  match st:
    case SSt{ss, q, vl, hl}:
      Sync.last(hl, key)

def Sync.reconcile.snap(+st: SSt, +k: RT.Kind, +ns: String, +name: String, +key: String, +e: Env,
  +v: Maybe<&2, J2.Json>, +h: Maybe<&2, J2.Json>) -> IO(Rec):
  Sync.run_out(
    RT.Runtime.step(k, Env.c(e), RT.Runtime.refs(k, Env.c(e), Sync.all2(St.Store.values(Sync.store(st, U32.to_nat(Sync.pods_src()))))),
      RT.Runtime.managed(k, Env.c(e), ns, name, h), Sync.vlast(st, key), v, Sync.hlast(st, key), h),
    key, e, k, Sync.or_null(v), Sync.or_null(h))

def Sync.reconcile.ref(+st: SSt, +k: RT.Kind, +ns: String, +name: String, +key: String, +e: Env,
  r: String & String) -> IO(Rec):
  match r:
    case (hns, hname):
      Sync.reconcile.snap(st, k, ns, name, key, e,
        Sync.some2(St.Store.get(Sync.store(st, U32.to_nat((RT.Runtime.kind_index(k) * 2 : U32))), ns ++ "/" ++ name)),
        Sync.some2(St.Store.get(Sync.store(st, U32.to_nat((RT.Runtime.kind_index(k) * 2 + 1 : U32))), hns ++ "/" ++ hname)))

def Sync.reconcile.kind(+st: SSt, m: Maybe<&2, RT.Kind>, +ns: String, +name: String, +key: String, +e: Env) -> IO(Rec):
  match m:
    case None{}:
      IO.pure(Rec, Rec{Q.AwaitChange{}, J2.JNull{}, J2.JNull{}, False{}})
    case Some{+k}:
      Sync.reconcile.ref(st, k, ns, name, key, e, RT.Runtime.host_ref(k, Env.c(e), ns, name))

def Sync.reconcile.key(+st: SSt, m: Maybe<&2, RT.Key>, +key: String, +e: Env) -> IO(Rec):
  match m:
    case None{}:
      IO.pure(Rec, Rec{Q.AwaitChange{}, J2.JNull{}, J2.JNull{}, False{}})
    case Some{RT.Key{id, +ns, +name}}:
      Sync.reconcile.kind(st, RT.Runtime.kind_of(id), ns, name, key, e)

def Sync.reconcile(+st: SSt, +key: String, +e: Env) -> IO(Rec):
  Sync.reconcile.key(st, RT.Runtime.parse_key(key), key, e)

# After a reconcile: the snapshots it used become the key's last ones if
# it succeeded; the queue arms the timers its action asks for.

def Sync.lasts(ok: Bool, m: Map<&2, J2.Json>, +key: String, x: J2.Json) -> Map<&2, J2.Json>:
  match ok:
    case True{}:
      Map.set(&2, J2.Json, m, key, x)
    case False{}:
      m

def Sync.sleeps(ts: List<&2, Q.Timer>, +chan: Chan(R.Msg)) -> IO(Unit):
  match ts:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{Q.Timer{key, gen, ms}, t}:
      IO.bind(Unit, Unit,
        IO.spawn(Result<&1, &1, R.Msg, Unit>,
          IO.bind(Unit, Result<&1, &1, R.Msg, Unit>, IO.sleep(ms),
            u => Chan.send(R.Msg, chan, R.MWake{key, gen}))),
        u => Sync.sleeps(t, chan))

def Sync.finish.go(ss: List<&2, St.Store>, vl: Map<&2, J2.Json>, hl: Map<&2, J2.Json>,
  r: Q.Queue & List<&2, Q.Timer>, +chan: Chan(R.Msg)) -> IO(SSt):
  match r:
    case (q, ts):
      IO.bind(Unit, SSt, Sync.sleeps(ts, chan), u => IO.pure(SSt, SSt{ss, q, vl, hl}))

def Sync.finish(st: SSt, +key: String, rec: Rec, +chan: Chan(R.Msg)) -> IO(SSt):
  match st rec:
    case SSt{ss, q, vl, hl} Rec{a, v, h, +ok}:
      Sync.finish.go(ss, Sync.lasts(ok, vl, key, v), Sync.lasts(ok, hl, key, h), Q.Queue.done(q, key, a), chan)

def Sync.pop.put(ss: List<&2, St.Store>, vl: Map<&2, J2.Json>, hl: Map<&2, J2.Json>,
  r: Q.Queue & Maybe<&2, String>) -> SSt & Maybe<&2, String>:
  match r:
    case (q, m):
      (SSt{ss, q, vl, hl}, m)

def Sync.pop(st: SSt) -> SSt & Maybe<&2, String>:
  match st:
    case SSt{ss, q, vl, hl}:
      Sync.pop.put(ss, vl, hl, Q.Queue.pop(q))

def Sync.fst(r: SSt & Maybe<&2, String>) -> SSt:
  match r:
    case (st, m):
      st

def Sync.snd(r: SSt & Maybe<&2, String>) -> Maybe<&2, String>:
  match r:
    case (st, m):
      m

# Reconciles the queued keys, one at a time, while every store is ready.
def Sync.drain(fuel: Nat, ready: Bool, +st: SSt, m: Maybe<&2, String>, +e: Env, +chan: Chan(R.Msg)) -> IO(SSt):
  match fuel ready m:
    case 0n x y:
      IO.pure(SSt, st)
    case 1n+p False{} y:
      IO.pure(SSt, st)
    case 1n+p True{} None{}:
      IO.pure(SSt, st)
    case 1n+p True{} Some{+key}:
      do IO<SSt>:
        +rec : Rec <- Sync.reconcile(st, key, e)
        +st2 : SSt <- Sync.finish(st, key, rec, chan)
        Sync.drain(p, True{}, Sync.fst(Sync.pop(st2)), Sync.snd(Sync.pop(st2)), e, chan)

def Sync.drain_all(+st: SSt, +e: Env, +chan: Chan(R.Msg)) -> IO(SSt):
  Sync.drain(4294967295n, Sync.ready(st), Sync.fst(Sync.pop(st)), Sync.snd(Sync.pop(st)), e, chan)

# The loop: fold what the watches saw into the stores and the queue, then
# reconcile; a timer that wakes queues its key again.
def Sync.loop(outer: Nat, fuel: Nat, m: Maybe<&1, R.Msg>, +st: SSt, +e: Env, +chan: Chan(R.Msg)) -> IO(Unit):
  match outer fuel m:
    case 0n 0n x:
      R.Loop.spent("Sync.loop")
    case 1n+o 0n x:
      Sync.loop(o, 4294967295n, x, st, e, chan)
    case o 1n+f None{}:
      IO.pure(Unit, Unit{})
    case o 1n+f Some{R.MOuts{src, outs}}:
      do IO<Unit>:
        +st2 : SSt <- Sync.drain_all(Sync.on_outs(st, src, outs, Env.c(e)), e, chan)
        x : Maybe<&1, R.Msg> <- Chan.recv(R.Msg, chan)
        Sync.loop(o, f, x, st2, e, chan)
    case o 1n+f Some{R.MWake{key, gen}}:
      do IO<Unit>:
        +st2 : SSt <- Sync.drain_all(Sync.on_wake(st, key, gen), e, chan)
        x : Maybe<&1, R.Msg> <- Chan.recv(R.Msg, chan)
        Sync.loop(o, f, x, st2, e, chan)
    case o 1n+f Some{other}:
      do IO<Unit>:
        x : Maybe<&1, R.Msg> <- Chan.recv(R.Msg, chan)
        Sync.loop(o, f, x, st, e, chan)

def Sync.init() -> SSt:
  SSt{List.replicate(St.Store, Sync.nsrc(), St.Store.new()), Q.Queue.new(1), Map.new(&2, J2.Json),
    Map.new(&2, J2.Json)}

# The host namespace (vk8s create --host-namespace); the syncer makes it
# when it is missing.
def Sync.ns_obj(+ns: String) -> J.Json:
  J.Json.obj([J.KV{"apiVersion", J.JStr{"v1"}}, J.KV{"kind", J.JStr{"Namespace"}},
    J.KV{"metadata", J.Json.obj([J.KV{"name", J.JStr{ns}}])}])

def Sync.ns_made.err(exists: Bool, e: Cl.KErr) -> IO(Unit):
  match exists:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      L.Log.warn("cannot create the host namespace", [L.Log.kv("error", Cl.KErr.show(e))])

def Sync.ns_made(r: Result<&2, &2, Cl.KErr, J.Json>) -> IO(Unit):
  match r:
    case Done{x}:
      L.Log.info("created the host namespace", Nil{})
    case Fail{+e}:
      Sync.ns_made.err(Cl.KErr.is_already_exists(e), e)

def Sync.ensure_ns(+e: Env) -> IO(Unit):
  IO.bind(Result<&2, &2, Cl.KErr, J.Json>, Unit,
    Cl.Client.create(Env.h(e), C.Api{C.Res.namespaces(), C.Cluster{}}, Sync.ns_obj(Env.ns(e))), Sync.ns_made)

# The leader's work.
def Sync.start(+e: Env) -> IO(Unit):
  do IO<Unit>:
    Sync.ensure_ns(e)
    +chan : Chan(R.Msg) <- Chan.new(R.Msg, 4096)
    Sync.watches(RT.Runtime.wired(), e, chan, 0)
    x : Maybe<&1, R.Msg> <- Chan.recv(R.Msg, chan)
    Sync.loop(4294967295n, 4294967295n, x, Sync.init(), e, chan)

# Only the holder of the virtual cluster's Lease syncs; a standby waits.
# SIGTERM releases the Lease and exits.
def Sync.elect(+e: Env, +me: String) -> IO(Unit):
  do IO<Unit>:
    L.Log.info("syncer starting", [L.Log.kv("id", me), L.Log.kv("host-namespace", Env.ns(e)),
      L.Log.kv("host", K.Config.host(Env.h(e))), L.Log.kv("virtual", K.Config.host(Env.v(e)))])
    E.Leader.elect(Env.v(e), E.LOpts.default("kube-system", RT.Runtime.lease_name(S.Svc.vc(Env.c(e))), me),
      IO.pure(Bool, True{}), Sync.start(e))

def Sync.configs(rv: Result<&2, &2, String, K.Config>, rh: Result<&2, &2, String, K.Config>, +f: RT.Flags) -> IO(Unit):
  match rv rh:
    case Done{v} Done{h}:
      do IO<Unit>:
        +me : String <- Kb.Kube.ident()
        Sync.elect(Env{v, h, RT.Flags.cfg(f), RT.Flags.host_namespace(f)}, me)
    case Fail{m} x:
      do IO<Unit>:
        L.Log.error("virtual kubeconfig", [L.Log.kv("path", RT.Flags.kubeconfig(f)), L.Log.kv("error", m)])
        IO.exit(1)
    case Done{v} Fail{m}:
      do IO<Unit>:
        L.Log.error("host kubeconfig", [L.Log.kv("path", RT.Flags.host_kubeconfig(f)), L.Log.kv("error", m)])
        IO.exit(1)

def Syncer.main(+args: +List<String>) -> IO(Unit):
  do IO<Unit>:
    +f : RT.Flags = RT.Runtime.flags(args)
    rv : Result<&2, &2, String, K.Config> <- Cl.Config.from_kubeconfig(RT.Flags.kubeconfig(f), "")
    rh : Result<&2, &2, String, K.Config> <- Cl.Config.from_kubeconfig(RT.Flags.host_kubeconfig(f), "")
    Sync.configs(rv, rh, f)
