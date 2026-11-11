import Base
import bend-kube-runtime@0.8.1.0/src/json.bend as J
import bend-kube-runtime@0.8.1.0/src/core.bend as C
import bend-kube-runtime@0.8.1.0/src/config.bend as K
import bend-kube-runtime@0.8.1.0/src/client.bend as Cl
import bend-kube-runtime@0.8.1.0/src/watcher.bend as W
import bend-kube-runtime@0.8.1.0/src/store.bend as St
import bend-kube-runtime@0.8.1.0/src/queue.bend as Q
import bend-kube-runtime@0.8.1.0/src/runtime.bend as R
import bend-kube-runtime@0.8.1.0/src/http.bend as H
import bend-kube-runtime@0.8.1.0/src/net.bend as N
import bend-kube-runtime@0.8.1.0/src/leader.bend as E
import bend-kube-runtime@0.8.1.0/src/log.bend as L
import bend-kube-runtime@0.8.1.0/src/kube.bend as Kb
import bend-kube-runtime@0.2.0.0/src/json.bend as J2
import ../src/sync/runtime.bend as RT
import ../src/translate/services.bend as S
import ../src/config/vcluster.bend as V
import ../src/sync/classic.bend as CL
import ../src/translate/pods.bend as P
import ./kubelet_proxy.bend as KP
import bend-kube-runtime@0.8.1.0/src/sys.bend as Y
import bend-kube-runtime@0.8.1.0/src/time.bend as T

# The classic-mode syncer (vcluster's syncer pod), run as
# `vk8s-guest syncer --host-kubeconfig F --host-namespace NS --name VC
# --service-cidr CIDR [--kubeconfig VIRTUAL] [--config VCLUSTER_YAML]`.
#
# bend-kube-runtime@0.8.1.0 (BendHub hash 0x4c2d28cc22034a4133c2ab77cd30309e)
# supplies the pieces: one watcher driver (R.Ctl.watch.subs) per resource
# and cluster, all feeding one inbox; the stores (St) and the work queue (Q)
# are pure values this loop owns. The virtual watches are primary; the host
# watches cover the host namespace with the managed-by label, and a host
# object queues the virtual key its object-name/object-namespace
# annotations name. Deletions, and objects that vanished across a relist,
# queue their key too, so a reconcile sees the object gone.
#
# One Lease (vcluster's: host namespace, vcluster-<vc>-controller) gates everything:
# the watches start only on the leader, and losing the Lease exits the
# process. Reconciles run one at a time; each reads both objects from the
# API server (Sync.reconcile.ref) and the snapshots of its last successful
# reconcile, calls the pure step
# (src/sync/runtime.bend) and makes its writes in order, stopping at the
# first error.
#
# The pure translators use bend-kube-runtime@0.2.0.0's JSON; objects cross
# that boundary as JSON text.

# Both clusters, the translator config, the host namespace, the parsed
# vcluster.yaml (which kinds run: CL.Classic.id_on) and the fake
# kubelet's flags.
type Env is Data:
  Env{v: K.Config, h: K.Config, c: S.Cfg, ns: String, on: J2.Json, kf: CL.KFlags, hv: String}

def Env.v(e: Env) -> K.Config:
  match e:
    case Env{v, h, c, ns, on, kf, hv}:
      v

def Env.h(e: Env) -> K.Config:
  match e:
    case Env{v, h, c, ns, on, kf, hv}:
      h

def Env.c(e: Env) -> S.Cfg:
  match e:
    case Env{v, h, c, ns, on, kf, hv}:
      c

def Env.ns(e: Env) -> String:
  match e:
    case Env{v, h, c, ns, on, kf, hv}:
      ns

def Env.on(e: Env) -> J2.Json:
  match e:
    case Env{v, h, c, ns, on, kf, hv}:
      on

def Env.kf(e: Env) -> CL.KFlags:
  match e:
    case Env{v, h, c, ns, on, kf, hv}:
      kf

# The host's gitVersion, read once at start ("" when unknown).
def Env.hv(e: Env) -> String:
  match e:
    case Env{v, h, c, ns, on, kf, hv}:
      hv

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

def Sync.res(k: RT.Resource) -> C.Res:
  match k:
    case RT.KServices{}:
      C.Res.services()
    case RT.KConfigs{r}:
      Sync.config_res(r)

def Sync.api(k: RT.Resource, +ns: String) -> C.Api:
  C.Api{Sync.res(k), C.InNs{ns}}

# The loop: fold what the watches saw into the stores and the queue, then
# reconcile; a timer that wakes queues its key again.
# Every 30 s the loop requeues each virtual pod that has no host pod yet: a
# safety net for a pod event the queue did not act on (classic conformance
# runs saw a scheduled pod never reach the host, with no error).
# Watches end after 60 s (bend-kube's driver asks for 290): a watch that
# stops delivering events without closing (classic conformance saw pods
# missed for minutes) is replaced within a minute, resuming from its
# resourceVersion.
def Sync.watch_req(c: R.WCtx, +rv: String) -> H.Req:
  match c:
    case R.WCtx{cfg, api, l, fs, subs}:
      C.Req.watch(api, C.WatchParams{l, fs, 60, True{}}, rv)

# The 0.5.1.0 Drv.run IO loop, with success logs at the list return
# and watch open boundaries. Keep the runtime's state machine, pagination,
# backoff and socket ownership. Ctl.watch.subs already spawns one driver;
# this wrapper does the same, so the inbox can drain while watches run.
def Sync.drive(outer: Nat, fuel: Nat, ev: R.DEv, +st: W.WState, +resp: H.Resp, +carry: List<&2, U32>,
  +ctx: R.WCtx) -> IO(Unit):
  match outer fuel ev:
    case 0n 0n e:
      R.Loop.spent("Sync.drive")
    case 1n+o 0n e:
      Sync.drive(o, 4294967295n, e, st, resp, carry, ctx)
    case o 1n+f R.DStart{}:
      match st:
        case W.WState{W.WList{+c}, +fl, +first}:
          IO.bind(Unit, Unit, R.Drv.note_list(first, R.WCtx.path(ctx), R.WCtx.server(ctx)),
            u => IO.bind(Result<&2, &2, Cl.KErr, J.Json>, Unit,
              Cl.Client.json(R.WCtx.cfg(ctx), R.WCtx.list_req(ctx, c)),
              r => Sync.drive(o, f, R.DListed{r}, W.WState{W.WList{c}, fl, first}, resp, carry, ctx)))
        case W.WState{W.WWatch{+rv}, +fl, +first}:
          IO.bind(Result<&1, &1, U32 & String, N.Tls>, Unit,
            Cl.Conn.open(R.WCtx.cfg(ctx), Sync.watch_req(ctx, rv), False{}),
            r => Sync.drive(o, f, R.DOpened{r}, W.WState{W.WWatch{rv}, fl, first}, resp, carry, ctx))
    case o 1n+f R.DListed{Done{+j}}:
      IO.bind(Unit, Unit, L.Log.info("listed", [L.Log.kv("path", R.WCtx.path(ctx))]),
        u => Sync.drive(o, f, R.DStepped{W.Watcher.step(st, W.IPage{C.Page.of(j)}), None{}, False{}}, st, resp,
          carry, ctx))
    case o 1n+f R.DListed{Fail{+e}}:
      IO.bind(Unit, Unit, L.Log.warn("list failed",
        [L.Log.kv("path", R.WCtx.path(ctx)), L.Log.kv("error", Cl.KErr.show(e))]),
        u => Sync.drive(o, f, R.DStepped{W.Watcher.step(st, W.IListErr{Cl.KErr.code(e)}), None{}, False{}}, st,
          resp, carry, ctx))
    case o 1n+f R.DOpened{Done{N.Tls{s}}}:
      IO.bind(Unit, Unit, L.Log.info("watching", [L.Log.kv("path", R.WCtx.path(ctx))]),
        u => IO.bind(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, Unit,
          N.Tls.recv(s, 65536, 350000),
          p => Sync.drive(o, f, R.DEv.recv(p), st, H.Http.resp.init(), Nil{}, ctx)))
    case o 1n+f R.DOpened{Fail{e}}:
      IO.bind(Unit, Unit, L.Log.warn("watch failed to open",
        [L.Log.kv("path", R.WCtx.path(ctx)), L.Log.kv("error", R.Drv.why(e))]),
        u => Sync.drive(o, f, R.DStepped{W.Watcher.step(st, W.IWatchErr{0}), None{}, False{}}, st, resp, carry,
          ctx))
    case o 1n+f R.DRecv{s, Done{+bs}}:
      Sync.drive(o, f, R.DDig{s, R.Drv.digest(st, H.Http.feed(bs, resp), carry,
        List.is_empty(&2, U32, bs))}, st, resp, carry, ctx)
    case o 1n+f R.DDig{s, R.Dig{step, r2, c2, more, ""}}:
      Sync.drive(o, f, R.DStepped{step, Some{s}, more}, st, r2, c2, ctx)
    case o 1n+f R.DDig{s, R.Dig{step, r2, c2, more, why}}:
      # the server answered the watch with an error status (bend-kube 0.8.1)
      IO.bind(Unit, Unit, L.Log.warn("watch refused",
        [L.Log.kv("path", R.WCtx.path(ctx)), L.Log.kv("status", why)]),
        u => Sync.drive(o, f, R.DStepped{step, Some{s}, more}, st, r2, c2, ctx))
    case o 1n+f R.DRecv{s, Fail{e}}:
      IO.bind(Unit, Unit, L.Log.warn("watch read failed",
        [L.Log.kv("path", R.WCtx.path(ctx)), L.Log.kv("error", R.Drv.why(e))]),
        u => Sync.drive(o, f, R.DStepped{W.Watcher.step(st, W.IWatchErr{0}), Some{s}, False{}}, st, resp,
          carry, ctx))
    case o 1n+f R.DStepped{W.Step{st2, outs, wait}, s, more}:
      IO.bind(Unit, Unit, R.Drv.send_all(R.WCtx.subs(ctx), outs),
        u => Sync.drive(o, f, R.DNext{s, wait, more}, st2, resp, carry, ctx))
    case o 1n+f R.DNext{Some{s}, False{}, True{}}:
      IO.bind(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, Unit,
        N.Tls.recv(s, 65536, 350000), p => Sync.drive(o, f, R.DEv.recv(p), st, resp, carry, ctx))
    case o 1n+f R.DNext{s, wait, more}:
      IO.bind(Unit, Unit, R.Drv.close(s),
        u => IO.bind(Unit, Unit, R.Drv.pause(wait, R.WState.fails(st), R.WCtx.path(ctx), R.WCtx.server(ctx)),
          u2 => Sync.drive(o, f, R.DStart{}, st, H.Http.resp.init(), Nil{}, ctx)))

def Sync.watch.field(+cfg: K.Config, api: C.Api, label: String, field: String, +chan: Chan(R.Msg), +src: U32) -> IO(Unit):
  IO.spawn(Unit, Sync.drive(4294967295n, 4294967295n, R.DStart{}, W.WState.init(),
    H.Http.resp.init(), Nil{}, R.WCtx{cfg, api, label, field, [R.Sub{chan, src}]}))

def Sync.watch(+cfg: K.Config, api: C.Api, label: String, +chan: Chan(R.Msg), +src: U32) -> IO(Unit):
  Sync.watch.field(cfg, api, label, "", chan, src)

# The resource of a kind id (CL.Op res, CL.Source id).
def Sync.res_of(id: String) -> C.Res:
  match id:
    case "services":
      C.Res.services()
    case "configmaps":
      C.Res.config_maps()
    case "secrets":
      C.Res.secrets()
    case "serviceaccounts":
      C.Res.core("ServiceAccount", "serviceaccounts", True{})
    case "pods":
      C.Res.pods()
    case "nodes":
      C.Res.core("Node", "nodes", False{})
    case "events":
      C.Res.core("Event", "events", True{})
    case "persistentvolumeclaims":
      C.Res.core("PersistentVolumeClaim", "persistentvolumeclaims", True{})
    case "persistentvolumes":
      C.Res.core("PersistentVolume", "persistentvolumes", False{})
    case "namespaces":
      C.Res.namespaces()
    case "storageclasses":
      C.Res{"storage.k8s.io", "v1", "StorageClass", "storageclasses", False{}}
    case "priorityclasses":
      C.Res{"scheduling.k8s.io", "v1", "PriorityClass", "priorityclasses", False{}}
    case "csinodes":
      C.Res{"storage.k8s.io", "v1", "CSINode", "csinodes", False{}}
    case "endpoints":
      C.Res.core("Endpoints", "endpoints", True{})
    case "endpointslices":
      C.Res{"discovery.k8s.io", "v1", "EndpointSlice", "endpointslices", True{}}
    case _:
      C.Res.core("Unknown", "unknown", True{})

# A resource in a namespace (ignored for cluster-scoped ones).
def Sync.rapi(+id: String, +ns: String) -> C.Api:
  C.Api{Sync.res_of(id), C.InNs{ns}}

# A virtual watch covers every namespace, a host watch the host namespace.
def Sync.src_api(host: Bool, +id: String, +ns: String) -> C.Api:
  match host:
    case True{}:
      C.Api{Sync.res_of(id), C.InNs{ns}}
    case False{}:
      C.Api{Sync.res_of(id), C.AllNs{}}

def Sync.src_label(labeled: Bool, +vc: String) -> String:
  match labeled:
    case True{}:
      RT.Runtime.selector(vc)
    case False{}:
      ""

def Sync.watch.go(s: CL.Source, +e: Env, +chan: Chan(R.Msg), +i: U32) -> IO(Unit):
  match s:
    case CL.Source{+id, +host, l}:
      Sync.watch(Env.cfg(host, e), Sync.src_api(host, id, Env.ns(e)), Sync.src_label(l, S.Svc.vc(Env.c(e))), chan, i)

# A source that vcluster.yaml leaves off is not watched; its store starts
# ready and empty (Sync.init).
def Sync.watch.src(on: Bool, s: CL.Source, +e: Env, +chan: Chan(R.Msg), +i: U32) -> IO(Unit):
  match on:
    case True{}:
      Sync.watch.go(s, e, chan, i)
    case False{}:
      IO.pure(Unit, Unit{})

# Source i of CL.Classic.sources feeds store i.
def Sync.watches(ss: List<&2, CL.Source>, +e: Env, +chan: Chan(R.Msg), +i: U32) -> IO(Unit):
  match ss:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+s, t}:
      do IO<Unit>:
        Sync.watch.src(CL.Classic.source_on(Env.on(e), s), s, e, chan, i)
        Sync.watches(t, e, chan, (i + 1 : U32))

# The vcluster's own host Service, by name (CL.Classic.kube_field): it
# has no managed-by label. It feeds store CL.Classic.kube_store and queues
# default/kubernetes. It runs when Services sync.
def Sync.watch.kube(on: Bool, +e: Env, +chan: Chan(R.Msg)) -> IO(Unit):
  match on:
    case True{}:
      Sync.watch.field(Env.cfg(True{}, e), Sync.src_api(True{}, "services", Env.ns(e)), "",
        CL.Classic.kube_field(S.Svc.vc(Env.c(e))), chan, CL.Classic.kube_store())
    case False{}:
      IO.pure(Unit, Unit{})

# The Endpoints and EndpointSlices table (CL.Classic.eps_sources): source
# i feeds store CL.Classic.eps_base() + i.
def Sync.eps_watch.src(on: Bool, s: CL.Source, +e: Env, +chan: Chan(R.Msg), +i: U32) -> IO(Unit):
  match on:
    case True{}:
      Sync.watch.go(s, e, chan, i)
    case False{}:
      IO.pure(Unit, Unit{})

def Sync.eps_watches(ss: List<&2, CL.Source>, +e: Env, +chan: Chan(R.Msg), +i: U32) -> IO(Unit):
  match ss:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+s, t}:
      do IO<Unit>:
        Sync.eps_watch.src(CL.Classic.eps_source_on(Env.on(e), s), s, e, chan, i)
        Sync.eps_watches(t, e, chan, (i + 1 : U32))

# Keys a batch of watch outputs queues.

def Sync.obj_keys(+src: U32, +c: S.Cfg, x: J.Json) -> List<&2, String>:
  CL.Classic.watch_keys(src, c, Sync.to2(x))

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

def Sync.on_outs.filter(+real: Bool, +src: U32, r: St.Store & List<&2, String>) -> St.Store & List<&2, String>:
  match r:
    case (s, ks):
      (s, CL.Classic.drop_pod_node_keys(real, src, ks))

def Sync.on_outs(st: SSt, +src: U32, outs: List<&2, W.Out>, +c: S.Cfg, +real: Bool) -> SSt:
  match st:
    case SSt{+ss, q, vl, hl}:
      Sync.on_outs.put(ss, src, q, vl, hl,
        Sync.on_outs.filter(real, src, Sync.fold(outs, src, c, R.Caches.nth(ss, U32.to_nat(src)), Nil{})))

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

def Sync.svc_retry.if(again: Bool, +err: Cl.KErr, +e: Env, +k: RT.Resource, +ns: String, +o: J2.Json) -> IO(Result<&2, &2, Cl.KErr, J.Json>):
  match again:
    case True{}:
      Cl.Client.create(Env.cfg(True{}, e), Sync.api(k, ns), Sync.to4(o))
    case False{}:
      IO.pure(Result<&2, &2, Cl.KErr, J.Json>, Fail{err})

# A host Service's create (Classic.svc_prefer): first with the virtual
# Service's cluster IP and node ports, then, if the host refuses them
# (422), as translated.
def Sync.svc_retry(r: Result<&2, &2, Cl.KErr, J.Json>, +e: Env, +k: RT.Resource, +ns: String, +o: J2.Json) -> IO(Result<&2, &2, Cl.KErr, J.Json>):
  match r:
    case Done{x}:
      IO.pure(Result<&2, &2, Cl.KErr, J.Json>, Done{x})
    case Fail{+err}:
      Sync.svc_retry.if(U32.is_eq(Cl.KErr.code(err), 422), err, e, k, ns, o)

def Sync.svc_create.got(m: Maybe<&2, J2.Json>, +e: Env, +k: RT.Resource, +ns: String, +o: J2.Json) -> IO(Result<&2, &2, Cl.KErr, J.Json>):
  match m:
    case None{}:
      Cl.Client.create(Env.cfg(True{}, e), Sync.api(k, ns), Sync.to4(o))
    case Some{+v}:
      IO.bind(Result<&2, &2, Cl.KErr, J.Json>, Result<&2, &2, Cl.KErr, J.Json>,
        Cl.Client.create(Env.cfg(True{}, e), Sync.api(k, ns), Sync.to4(CL.Classic.svc_prefer(o, v))),
        r => Sync.svc_retry(r, e, k, ns, o))

# A reconcile reads its two objects from the API server, not from the
# stores. The stores lag the syncer's own writes: after services Sync
# recreates a virtual service (delete, then create with the host cluster
# IP), a wake or the delete event can run the key before the create
# event arrives. A store read then shows the virtual service gone while
# the last snapshot has it, and SyncToVirtual deletes the host service
# (vcluster's informer has both events by then). The stores still queue
# the keys and hold the pods whose references gate configs.
def Sync.get.fail(gone: Bool, e: Cl.KErr) -> Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>:
  match gone:
    case True{}:
      Done{None{}}
    case False{}:
      Fail{e}

# A 404 is an absent object; any other error fails the reconcile.
def Sync.get.r(r: Result<&2, &2, Cl.KErr, J.Json>) -> Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>:
  match r:
    case Done{x}:
      Done{Some{Sync.to2(x)}}
    case Fail{+e}:
      Sync.get.fail(Cl.KErr.is_not_found(e), e)

def Sync.get.if(empty: Bool, +cfg: K.Config, a: C.Api, name: String) -> IO(Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>):
  match empty:
    case True{}:
      IO.pure(Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>, Done{None{}})
    case False{}:
      IO.bind(Result<&2, &2, Cl.KErr, J.Json>, Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>,
        Cl.Client.get(cfg, a, name),
        r => IO.pure(Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>, Sync.get.r(r)))

# The live object, or None when it does not exist. An empty name (an
# unmapped key) reads nothing: a GET without a name is a list.
def Sync.get(+cfg: K.Config, a: C.Api, +name: String) -> IO(Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>):
  Sync.get.if(String.is_empty(name), cfg, a, name)

def Sync.mget(+cfg: K.Config, +id: String, +ns: String, +name: String) -> IO(Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>):
  Sync.get(cfg, Sync.rapi(id, ns), name)

# An optional read: a failure reads as absent.
def Sync.opt(r: Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>) -> Maybe<&2, J2.Json>:
  match r:
    case Done{m}:
      m
    case Fail{e}:
      None{}

def Sync.create(svc: Bool, host: Bool, +e: Env, +k: RT.Resource, +ns: String, +o: J2.Json) -> IO(Result<&2, &2, Cl.KErr, J.Json>):
  match svc:
    case True{}:
      IO.bind(Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>, Result<&2, &2, Cl.KErr, J.Json>,
        Sync.mget(Env.v(e), "services", CL.Classic.svc_vns(o), CL.Classic.svc_vname(o)),
        vr => Sync.svc_create.got(Sync.opt(vr), e, k, ns, o))
    case False{}:
      Cl.Client.create(Env.cfg(host, e), Sync.api(k, ns), Sync.to4(o))

def Sync.upd_retry.if(again: Bool, +err: Cl.KErr, +e: Env, +k: RT.Resource, +ns: String, +name: String, +o: J2.Json) -> IO(Result<&2, &2, Cl.KErr, J.Json>):
  match again:
    case True{}:
      Cl.Client.replace(Env.cfg(True{}, e), Sync.api(k, ns), name, Sync.to4(o))
    case False{}:
      IO.pure(Result<&2, &2, Cl.KErr, J.Json>, Fail{err})

def Sync.upd_retry(r: Result<&2, &2, Cl.KErr, J.Json>, +e: Env, +k: RT.Resource, +ns: String, +name: String, +o: J2.Json) -> IO(Result<&2, &2, Cl.KErr, J.Json>):
  match r:
    case Done{x}:
      IO.pure(Result<&2, &2, Cl.KErr, J.Json>, Done{x})
    case Fail{+err}:
      Sync.upd_retry.if(U32.is_eq(Cl.KErr.code(err), 422), err, e, k, ns, name, o)

def Sync.svc_update.got(m: Maybe<&2, J2.Json>, +e: Env, +k: RT.Resource, +ns: String, +name: String, +o: J2.Json) -> IO(Result<&2, &2, Cl.KErr, J.Json>):
  match m:
    case None{}:
      Cl.Client.replace(Env.cfg(True{}, e), Sync.api(k, ns), name, Sync.to4(o))
    case Some{+v}:
      IO.bind(Result<&2, &2, Cl.KErr, J.Json>, Result<&2, &2, Cl.KErr, J.Json>,
        Cl.Client.replace(Env.cfg(True{}, e), Sync.api(k, ns), name, Sync.to4(CL.Classic.svc_prefer(o, v))),
        r => Sync.upd_retry(r, e, k, ns, name, o))

def Sync.update(svc: Bool, host: Bool, +e: Env, +k: RT.Resource, +ns: String, +name: String, +o: J2.Json) -> IO(Result<&2, &2, Cl.KErr, J.Json>):
  match svc:
    case True{}:
      IO.bind(Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>, Result<&2, &2, Cl.KErr, J.Json>,
        Sync.mget(Env.v(e), "services", CL.Classic.svc_vns(o), CL.Classic.svc_vname(o)),
        vr => Sync.svc_update.got(Sync.opt(vr), e, k, ns, name, o))
    case False{}:
      Cl.Client.replace(Env.cfg(host, e), Sync.api(k, ns), name, Sync.to4(o))

def Sync.call(c: RT.Call, +e: Env, +k: RT.Resource) -> IO(Result<&2, &2, Cl.KErr, J.Json>):
  match c:
    case RT.CCreate{+host, ns, o}:
      Sync.create(Bool.and(host, CL.Classic.is_services(k)), host, e, k, ns, o)
    case RT.CUpdate{+host, ns, name, +o}:
      Sync.update(Bool.and(Bool.and(host, CL.Classic.is_services(k)), CL.Classic.svc_wants_ip(o)), host, e, k, ns, name, o)
    case RT.CDelete{host, ns, name}:
      IO.bind(Result<&2, &2, Cl.KErr, J.Json>, Result<&2, &2, Cl.KErr, J.Json>,
        Cl.Client.delete(Env.cfg(host, e), Sync.api(k, ns), name),
        r => IO.pure(Result<&2, &2, Cl.KErr, J.Json>, Sync.gone_ok(r)))

# The writes in order; the first failure stops the rest.
def Sync.apply(ws: List<&2, S.Write>, r: Result<&2, &2, Cl.KErr, J.Json>, +e: Env, +k: RT.Resource) ->
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

def Sync.run_out(out: S.Outcome, +key: String, +e: Env, +k: RT.Resource, +v: J2.Json, +h: J2.Json) -> IO(Rec):
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

# The special sync of default/kubernetes logs what it does, with the
# host Service it follows and that Service's cluster IP.
def Sync.special_log(special: Bool, +e: Env, +v: Maybe<&2, J2.Json>, +h: Maybe<&2, J2.Json>, +out: S.Outcome) -> IO(Unit):
  match special:
    case False{}:
      IO.pure(Unit, Unit{})
    case True{}:
      L.Log.info("kubernetes service", [
        L.Log.kv("action", RT.Runtime.special_outcome(Maybe.is_some(&2, J2.Json, h), Maybe.is_some(&2, J2.Json, v),
          RT.Runtime.writes(out))),
        L.Log.kv("host", Env.ns(e) ++ "/" ++ S.Svc.vc(Env.c(e))),
        L.Log.kv("clusterIP", CL.Classic.cluster_ip(h))])

def Sync.reconcile.out(+k: RT.Resource, +ns: String, +name: String, +key: String, +e: Env,
  +v: Maybe<&2, J2.Json>, +h: Maybe<&2, J2.Json>, +out: S.Outcome) -> IO(Rec):
  IO.bind(Unit, Rec, Sync.special_log(RT.Runtime.special(k, ns, name), e, v, h, out),
    u => Sync.run_out(out, key, e, k, Sync.or_null(v), Sync.or_null(h)))

def Sync.items(r: Result<&2, &2, Cl.KErr, J.Json>) -> List<&2, J2.Json>:
  match r:
    case Done{x}:
      J2.Json.items(J2.Json.get(Sync.to2(x), "items"))
    case Fail{e}:
      []

# A ConfigMap or Secret is synced while a virtual pod refers to it. The
# pods are read fresh from the namespace, not from the pod store: a pod
# missing from the store left its ConfigMap unsynced (FailedMount on the
# host) in classic conformance.
def Sync.ns_pods(refs: Bool, +e: Env, +ns: String) -> IO(List<&2, J2.Json>):
  match refs:
    case True{}:
      IO.bind(Result<&2, &2, Cl.KErr, J.Json>, List<&2, J2.Json>,
        Cl.Client.list(Env.v(e), C.Api{C.Res.pods(), C.InNs{ns}}, C.ListParams.default()),
        r => IO.pure(List<&2, J2.Json>, Sync.items(r)))
    case False{}:
      IO.pure(List<&2, J2.Json>, [])

def Sync.pick_pods(known: Bool, +stored: List<&2, J2.Json>, +fresh: List<&2, J2.Json>) -> List<&2, J2.Json>:
  match known:
    case True{}:
      stored
    case False{}:
      fresh

def Sync.reconcile.snap(+st: SSt, +k: RT.Resource, +ns: String, +name: String, +key: String, +e: Env,
  +v: Maybe<&2, J2.Json>, +h: Maybe<&2, J2.Json>) -> IO(Rec):
  do IO<Rec>:
    +stored : List<&2, J2.Json> = Sync.all2(St.Store.values(Sync.store(st, CL.Classic.vpods())))
    +known : Bool = Bool.or(CL.Classic.is_services(k), RT.Runtime.refs_has(RT.Runtime.refs(k, Env.c(e), stored), ns, name))
    +fresh : List<&2, J2.Json> <- Sync.ns_pods(Bool.not(known), e, ns)
    +pods : List<&2, J2.Json> = Sync.pick_pods(known, stored, fresh)
    Sync.reconcile.out(k, ns, name, key, e, v, h,
      RT.Runtime.step(k, Env.c(e), RT.Runtime.refs(k, Env.c(e), pods),
        RT.Runtime.managed(k, Env.c(e), ns, name, h), Sync.vlast(st, key), v, Sync.hlast(st, key), h))

def Sync.reconcile.read(+st: SSt, +k: RT.Resource, +ns: String, +name: String, +key: String, +e: Env,
  vr: Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>, hr: Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>) -> IO(Rec):
  match vr hr:
    case Fail{err} y:
      Sync.report(key, Rec{Cl.KErr.action(err), J2.JNull{}, J2.JNull{}, False{}})
    case Done{v} Fail{err}:
      Sync.report(key, Rec{Cl.KErr.action(err), J2.JNull{}, J2.JNull{}, False{}})
    case Done{v} Done{h}:
      Sync.reconcile.snap(st, k, ns, name, key, e, v, h)

def Sync.reconcile.ref(+st: SSt, +k: RT.Resource, +ns: String, +name: String, +key: String, +e: Env,
  r: String & String) -> IO(Rec):
  match r:
    case (hns, hname):
      IO.bind(Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>, Rec,
        Sync.get(Env.cfg(False{}, e), Sync.api(k, ns), name),
        vr => IO.bind(Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>, Rec,
          Sync.get(Env.cfg(True{}, e), Sync.api(k, hns), hname),
          hr => Sync.reconcile.read(st, k, ns, name, key, e, vr, hr)))

# The kinds of src/sync/classic.bend
# ----------------------------------

def Sync.nothing() -> Rec:
  Rec{Q.AwaitChange{}, J2.JNull{}, J2.JNull{}, False{}}

def Sync.failed(+key: String, +err: Cl.KErr) -> IO(Rec):
  Sync.report(key, Rec{Cl.KErr.action(err), J2.JNull{}, J2.JNull{}, False{}})

def Sync.values(+st: SSt, n: Nat) -> List<&2, J2.Json>:
  Sync.all2(St.Store.values(Sync.store(st, n)))

def Sync.seed(r: Result<&1, &1, U32 & String, U32>) -> U32:
  match r:
    case Done{x}:
      x
    case Fail{e}:
      2463534242

def Sync.now(w: U32 & (U32 & U32)) -> String:
  T.Wall.rfc3339(T.Wall.of(w))

# Calls.

def Sync.grace(g: J2.Json) -> Maybe<&2, U32>:
  match g:
    case J2.JNum{t}:
      U32.read(t)
    case _:
      None{}

# A host update that lost a race (409: the object changed since it was
# read, as a pod's status does while its kubelet works) is sent once more
# with the object's current resourceVersion, so a busy object still makes
# progress instead of conflicting on every retry. Host objects only: the
# syncer owns their spec. A virtual object's conflict means a user changed
# it (a test's node taint), so the key is reconciled again from scratch.
def Sync.op.fresh(r: Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>, +host: Bool, +res: String, +x: J2.Json, +err: Cl.KErr, +e: Env) -> IO(Result<&2, &2, Cl.KErr, J.Json>):
  match r:
    case Done{Some{cur}}:
      Cl.Client.replace(Env.cfg(host, e), Sync.rapi(res, S.Svc.namespace(x)), S.Svc.name(x),
        Sync.to4(CL.Classic.with_rv(x, CL.Classic.rv(cur))))
    case _:
      IO.pure(Result<&2, &2, Cl.KErr, J.Json>, Fail{err})

def Sync.op.conflict.if(again: Bool, +err: Cl.KErr, +host: Bool, +res: String, +x: J2.Json, +e: Env) -> IO(Result<&2, &2, Cl.KErr, J.Json>):
  match again:
    case True{}:
      IO.bind(Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>, Result<&2, &2, Cl.KErr, J.Json>,
        Sync.mget(Env.cfg(host, e), res, S.Svc.namespace(x), S.Svc.name(x)),
        g => Sync.op.fresh(g, host, res, x, err, e))
    case False{}:
      IO.pure(Result<&2, &2, Cl.KErr, J.Json>, Fail{err})

def Sync.op.conflict(r: Result<&2, &2, Cl.KErr, J.Json>, +host: Bool, +res: String, +x: J2.Json, +e: Env) -> IO(Result<&2, &2, Cl.KErr, J.Json>):
  match r:
    case Done{y}:
      IO.pure(Result<&2, &2, Cl.KErr, J.Json>, Done{y})
    case Fail{+err}:
      Sync.op.conflict.if(Bool.and(host, Cl.KErr.is_conflict(err)), err, host, res, x, e)

def Sync.op(o: CL.Op, +e: Env) -> IO(Result<&2, &2, Cl.KErr, J.Json>):
  match o:
    case CL.OCreate{host, res, +x}:
      Cl.Client.create(Env.cfg(host, e), Sync.rapi(res, S.Svc.namespace(x)), Sync.to4(x))
    case CL.OUpdate{+host, +res, +x}:
      IO.bind(Result<&2, &2, Cl.KErr, J.Json>, Result<&2, &2, Cl.KErr, J.Json>,
        Cl.Client.replace(Env.cfg(host, e), Sync.rapi(res, S.Svc.namespace(x)), S.Svc.name(x), Sync.to4(x)),
        r => Sync.op.conflict(r, host, res, x, e))
    case CL.OStatus{host, res, +x}:
      Cl.Client.patch_status(Env.cfg(host, e), Sync.rapi(res, S.Svc.namespace(x)), S.Svc.name(x), C.PMerge{},
        Sync.to4(CL.Classic.status_patch(x)))
    case CL.ODelete{host, res, ns, name, g, u}:
      IO.bind(Result<&2, &2, Cl.KErr, J.Json>, Result<&2, &2, Cl.KErr, J.Json>,
        Cl.Client.delete_with(Env.cfg(host, e), Sync.rapi(res, ns), name, C.DeleteOpts{"", Sync.grace(g), u, ""}),
        r => IO.pure(Result<&2, &2, Cl.KErr, J.Json>, Sync.gone_ok(r)))
    case CL.OSub{host, res, ns, name, m, sub, ct, body}:
      Cl.Client.json(Env.cfg(host, e), H.Req{m, C.Api.item(Sync.rapi(res, ns), name) ++ "/" ++ sub, C.Req.body_headers(ct),
        J2.Json.show(body)})
    case CL.ONote{m}:
      IO.bind(Unit, Result<&2, &2, Cl.KErr, J.Json>, L.Log.warn("pod event", [L.Log.kv("message", m)]),
        u => IO.pure(Result<&2, &2, Cl.KErr, J.Json>, Done{J.JNull{}}))

# The calls in order; the first failure stops the rest.
def Sync.run_ops(os: List<&2, CL.Op>, r: Result<&2, &2, Cl.KErr, J.Json>, +e: Env) -> IO(Result<&2, &2, Cl.KErr, Unit>):
  match os r:
    case w Fail{err}:
      IO.pure(Result<&2, &2, Cl.KErr, Unit>, Fail{err})
    case Nil{} Done{x}:
      IO.pure(Result<&2, &2, Cl.KErr, Unit>, Done{Unit{}})
    case Con{o, t} Done{x}:
      IO.bind(Result<&2, &2, Cl.KErr, J.Json>, Result<&2, &2, Cl.KErr, Unit>,
        Sync.op(o, e), r2 => Sync.run_ops(t, r2, e))

def Sync.rec_err(ok: Bool, +rq: S.Requeue, +err: String, +v: J2.Json, +h: J2.Json) -> Rec:
  match ok:
    case True{}:
      Rec{Sync.action(rq), v, h, True{}}
    case False{}:
      Rec{Q.Retry{err}, v, h, False{}}

def Sync.rec_act(r: Result<&2, &2, Cl.KErr, Unit>, +rq: S.Requeue, +err: String, +v: J2.Json, +h: J2.Json) -> Rec:
  match r:
    case Done{u}:
      Sync.rec_err(String.is_empty(err), rq, err, v, h)
    case Fail{+x}:
      Rec{Cl.KErr.action(x), v, h, False{}}

# Makes a step's calls; the snapshots v and h become the key's last ones
# when every call landed and the step had no error.
def Sync.run_act(a: CL.Act, +key: String, +e: Env, +v: J2.Json, +h: J2.Json) -> IO(Rec):
  match a:
    case CL.Act{+os, +rq, +err}:
      IO.bind(Result<&2, &2, Cl.KErr, Unit>, Rec, Sync.run_ops(os, Done{J.JNull{}}, e),
        r => Sync.report(key, Sync.rec_act(r, rq, err, CL.Classic.written(False{}, os, v), CL.Classic.written(True{}, os, h))))

# Pods: the virtual and the host pod, then (with a virtual pod) what
# Translate reads: the namespace, its services, the host kube-dns service,
# the vcluster's host Service (pods translate.go findKubernetesIP: its
# cluster IP is KUBERNETES_SERVICE_HOST), and (only before the host pod exists)
# one TokenRequest per projected service account token.

def Sync.token.req(+r: J2.Json) -> H.Req:
  H.Req{"POST", C.Api.item(Sync.rapi("serviceaccounts", S.Svc.str(J2.Json.get(r, "namespace"))),
    S.Svc.str(J2.Json.get(r, "serviceAccountName"))) ++ "/token", C.Req.body_headers("application/json"),
    J2.Json.show(J2.Json.get(r, "request"))}

def Sync.token.of(r: Result<&2, &2, Cl.KErr, J.Json>) -> String:
  match r:
    case Done{x}:
      CL.Classic.token_of(Sync.to2(x))
    case Fail{e}:
      ""

def Sync.tokens.go(rs: List<&2, J2.Json>, +e: Env, +seed: U32) -> IO(List<&2, P.Tok>):
  match rs:
    case Nil{}:
      IO.pure(List<&2, P.Tok>, [])
    case Con{r, t}:
      do IO<List<&2, P.Tok>>:
        x : Result<&2, &2, Cl.KErr, J.Json> <- Cl.Client.json(Env.v(e), Sync.token.req(r))
        rest : List<&2, P.Tok> <- Sync.tokens.go(t, e, CL.Classic.next(seed))
        IO.pure(List<&2, P.Tok>, P.Tok{CL.Classic.rand_str(8n, seed), Sync.token.of(x)} <> rest)

def Sync.tokens(need: Bool, +e: Env, +pc: P.Cfg, +v: J2.Json) -> IO(List<&2, P.Tok>):
  match need:
    case False{}:
      IO.pure(List<&2, P.Tok>, [])
    case True{}:
      do IO<List<&2, P.Tok>>:
        r : Result<&1, &1, U32 & String, U32> <- IO.random_u32()
        Sync.tokens.go(P.Pods.token_requests(pc, v), e, Sync.seed(r))

# A step that leaves a scheduled virtual pod without a host pod, with no
# write and no error, is logged with what it saw (classic conformance
# found such pods with no trace).
def Sync.pods.idle(idle: Bool, +key: String, +a: CL.Act, +v: Maybe<&2, J2.Json>, +h: Maybe<&2, J2.Json>) -> IO(Unit):
  match idle:
    case True{}:
      L.Log.warn("pod step idle", [L.Log.kv("key", key), L.Log.kv("why", CL.Classic.idle_why(a, v, h))])
    case False{}:
      IO.pure(Unit, Unit{})

def Sync.pods.step(+st: SSt, +ns: String, +name: String, +hname: String, +key: String, +e: Env, +sin: P.SInp, +why: String,
  +v: Maybe<&2, J2.Json>, +h: Maybe<&2, J2.Json>) -> IO(Rec):
  do IO<Rec>:
    +a : CL.Act = CL.Classic.hold(why, CL.Classic.pods_g(CL.Classic.pod_cfg_v(Env.c(e), Env.on(e), Env.hv(e)), Env.c(e), sin, ns, name, hname,
      Sync.vlast(st, key), v, Sync.hlast(st, key), h))
    Sync.pods.idle(CL.Classic.idle(a, v, h), key, a, v, h)
    Sync.run_act(a, key, e, Sync.or_null(v), Sync.or_null(h))

def Sync.pods.inputs(+st: SSt, +ns: String, +name: String, +hname: String, +key: String, +e: Env,
  v: Maybe<&2, J2.Json>, +h: Maybe<&2, J2.Json>) -> IO(Rec):
  match v:
    case None{}:
      Sync.pods.step(st, ns, name, hname, key, e, CL.Classic.pod_inp([], [], "", "", [], []), "", None{}, h)
    case Some{+x}:
      do IO<Rec>:
        nsr : Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>> <- Sync.mget(Env.v(e), "namespaces", "", ns)
        sv : Result<&2, &2, Cl.KErr, J.Json> <- Cl.Client.list(Env.v(e), Sync.rapi("services", ns), C.ListParams.default())
        dns : Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>> <- Sync.mget(Env.h(e), "services", Env.ns(e),
          CL.Classic.dns_host_name(S.Svc.vc(Env.c(e))))
        +kube : Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>> <- Sync.mget(Env.h(e), "services", Env.ns(e), S.Svc.vc(Env.c(e)))
        +gone : Bool = Bool.or(Maybe.is_some(&2, J2.Json, h), CL.Classic.pod_deletes(x))
        +toks : List<&2, P.Tok> <- Sync.tokens(Bool.not(gone), e,
          CL.Classic.pod_cfg_v(Env.c(e), Env.on(e), Env.hv(e)), x)
        Sync.pods.step(st, ns, name, hname, key, e,
          CL.Classic.pod_inp(CL.Classic.ns_labels(Sync.opt(nsr)), Sync.items(sv), CL.Classic.cluster_ip(Sync.opt(dns)),
            CL.Classic.cluster_ip(Sync.opt(kube)), toks, CL.Classic.names(Sync.values(st, CL.Classic.vnodes()))),
          CL.Classic.wait_reason(CL.Classic.toks_ok(toks),
            Bool.or(Maybe.is_some(&2, J2.Json, Sync.opt(kube)), gone)), Some{x}, h)

def Sync.pods.read(+st: SSt, +ns: String, +name: String, +hname: String, +key: String, +e: Env,
  vr: Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>, hr: Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>) -> IO(Rec):
  match vr hr:
    case Fail{err} y:
      Sync.failed(key, err)
    case Done{v} Fail{err}:
      Sync.failed(key, err)
    case Done{v} Done{h}:
      Sync.pods.inputs(st, ns, name, hname, key, e, v, h)

def Sync.pods(+st: SSt, +ns: String, +name: String, +key: String, +e: Env) -> IO(Rec):
  do IO<Rec>:
    +hname : String = RT.Runtime.host_name(S.Svc.vc(Env.c(e)), ns, name)
    vr : Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>> <- Sync.mget(Env.v(e), "pods", ns, name)
    hr : Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>> <- Sync.mget(Env.h(e), "pods", Env.ns(e), hname)
    Sync.pods.read(st, ns, name, hname, key, e, vr, hr)

# Fake nodes: the virtual node and the pods in the stores (the indices
# vcluster reads from its caches).
def Sync.nodes.read(+st: SSt, +name: String, +key: String, +e: Env, vr: Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>,
  +now: String, +seed: U32) -> IO(Rec):
  match vr:
    case Fail{err}:
      Sync.failed(key, err)
    case Done{+node}:
      Sync.run_act(CL.Classic.nodes(CL.Classic.fake(now, seed), name, CL.KFlags.ip(Env.kf(e)), node,
        Sync.values(st, CL.Classic.vpods()), Sync.values(st, CL.Classic.hpods())), key, e, Sync.or_null(node), J2.JNull{})

def Sync.nodes(+st: SSt, +name: String, +key: String, +e: Env) -> IO(Rec):
  do IO<Rec>:
    vr : Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>> <- Sync.mget(Env.v(e), "nodes", "", name)
    w : U32 & (U32 & U32) <- Y.Sys.wall()
    r : Result<&1, &1, U32 & String, U32> <- IO.random_u32()
    Sync.nodes.read(st, name, key, e, vr, Sync.now(w), Sync.seed(r))

# Fake persistent volumes: the virtual volume and the claims in the store.
def Sync.pvs.read(+st: SSt, +name: String, +key: String, +e: Env, r: Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>) -> IO(Rec):
  match r:
    case Fail{err}:
      Sync.failed(key, err)
    case Done{+pv}:
      Sync.run_act(CL.Classic.pvs(name, pv, Sync.values(st, CL.Classic.vpvcs())), key, e, Sync.or_null(pv), J2.JNull{})

def Sync.pvs(+st: SSt, +name: String, +key: String, +e: Env) -> IO(Rec):
  do IO<Rec>:
    r : Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>> <- Sync.mget(Env.v(e), "persistentvolumes", "", name)
    Sync.pvs.read(st, name, key, e, r)

# Persistent volume claims: both claims, and the virtual volume the host
# claim names.
def Sync.pvcs.fake(+st: SSt, +hname: String, +key: String, +e: Env, +now: String, +v: Maybe<&2, J2.Json>,
  +h: Maybe<&2, J2.Json>) -> IO(Rec):
  do IO<Rec>:
    pr : Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>> <- Sync.mget(Env.v(e), "persistentvolumes", "", CL.Classic.volume_of(h))
    Sync.run_act(CL.Classic.pvcs(Env.c(e), Env.on(e), CL.Classic.pvc_look(Sync.opt(pr), now), hname,
      Sync.vlast(st, key), v, Sync.hlast(st, key), h), key, e, Sync.or_null(v), Sync.or_null(h))

# Real volumes: the host volume the host claim names gives the virtual
# volume's name (persistentVolumeMapper.HostToVirtual).
def Sync.pvcs.real(+st: SSt, +hname: String, +key: String, +e: Env, +now: String, +v: Maybe<&2, J2.Json>,
  +h: Maybe<&2, J2.Json>) -> IO(Rec):
  do IO<Rec>:
    +hvol : String = CL.Classic.volume_of(h)
    hr : Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>> <- Sync.mget(Env.h(e), "persistentvolumes", "", hvol)
    +pvn : String = CL.Classic.pv_vname_of(hvol, Sync.opt(hr))
    pr : Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>> <- Sync.mget(Env.v(e), "persistentvolumes", "", pvn)
    Sync.run_act(CL.Classic.pvcs(Env.c(e), Env.on(e), CL.Classic.pvc_look_real(Sync.opt(pr), pvn, now), hname,
      Sync.vlast(st, key), v, Sync.hlast(st, key), h), key, e, Sync.or_null(v), Sync.or_null(h))

def Sync.pvcs.pv.mode(real: Bool, +st: SSt, +hname: String, +key: String, +e: Env, +now: String, +v: Maybe<&2, J2.Json>,
  +h: Maybe<&2, J2.Json>) -> IO(Rec):
  match real:
    case True{}:
      Sync.pvcs.real(st, hname, key, e, now, v, h)
    case False{}:
      Sync.pvcs.fake(st, hname, key, e, now, v, h)

def Sync.pvcs.pv(+st: SSt, +hname: String, +key: String, +e: Env, +now: String, +v: Maybe<&2, J2.Json>,
  +h: Maybe<&2, J2.Json>) -> IO(Rec):
  Sync.pvcs.pv.mode(CL.Classic.real_pvs(Env.on(e)), st, hname, key, e, now, v, h)

def Sync.pvcs.read(+st: SSt, +hname: String, +key: String, +e: Env, +now: String,
  vr: Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>, hr: Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>) -> IO(Rec):
  match vr hr:
    case Fail{err} y:
      Sync.failed(key, err)
    case Done{v} Fail{err}:
      Sync.failed(key, err)
    case Done{v} Done{h}:
      Sync.pvcs.pv(st, hname, key, e, now, v, h)

def Sync.pvcs(+st: SSt, +ns: String, +name: String, +key: String, +e: Env) -> IO(Rec):
  do IO<Rec>:
    +hname : String = RT.Runtime.host_name(S.Svc.vc(Env.c(e)), ns, name)
    vr : Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>> <- Sync.mget(Env.v(e), "persistentvolumeclaims", ns, name)
    hr : Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>> <- Sync.mget(Env.h(e), "persistentvolumeclaims", Env.ns(e), hname)
    w : U32 & (U32 & U32) <- Y.Sys.wall()
    Sync.pvcs.read(st, hname, key, e, Sync.now(w), vr, hr)

# Events from the host: the host event, the virtual object its involved
# object maps to (through the host object's annotations), whether that
# namespace is live, and the virtual event.
def Sync.events.fin(+key: String, +e: Env, +h: J2.Json, +found: Maybe<&2, J2.Json>, +live: +List<String>,
  ver: Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>) -> IO(Rec):
  match ver:
    case Fail{err}:
      Sync.failed(key, err)
    case Done{+ve}:
      Sync.run_act(CL.Classic.events(Some{h}, found, live, ve), key, e, Sync.or_null(ve), h)

def Sync.events.got(+key: String, +e: Env, +h: J2.Json) -> IO(Rec):
  do IO<Rec>:
    +res : String = CL.Classic.ev_res(h)
    hr : Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>> <- Sync.mget(Env.h(e), res, Env.ns(e), CL.Classic.ev_hname(h))
    +ho : Maybe<&2, J2.Json> = Sync.opt(hr)
    fr : Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>> <- Sync.mget(Env.v(e), res, CL.Classic.obj_ns(ho), CL.Classic.obj_name(ho))
    +found : Maybe<&2, J2.Json> = Sync.opt(fr)
    nr : Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>> <- Sync.mget(Env.v(e), "namespaces", "", CL.Classic.event_ns(found))
    ver : Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>> <- Sync.mget(Env.v(e), "events", CL.Classic.event_vns(h, found), CL.Classic.event_vname(h, found))
    Sync.events.fin(key, e, h, found, CL.Classic.live(CL.Classic.event_ns(found), Sync.opt(nr)), ver)

def Sync.events.read(+key: String, +e: Env, r: Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>) -> IO(Rec):
  match r:
    case Fail{err}:
      Sync.failed(key, err)
    case Done{None{}}:
      IO.pure(Rec, Rec{Q.AwaitChange{}, J2.JNull{}, J2.JNull{}, True{}})
    case Done{Some{h}}:
      Sync.events.got(key, e, h)

def Sync.events(+ns: String, +name: String, +key: String, +e: Env) -> IO(Rec):
  do IO<Rec>:
    r : Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>> <- Sync.mget(Env.h(e), "events", ns, name)
    Sync.events.read(key, e, r)

# Real nodes (sync.fromHost.nodes.enabled): the virtual and the host node,
# and with the virtual scheduler every host pod on the node (vcluster's
# unmanaged pod cache, IndexRunningNonVClusterPodsByNode).
# The host pods on a node that count against the virtual scheduler's
# allocatable: only those not managed by this vcluster (Node.alloc_counts),
# so the API server filters them (listing every pod on the node and
# parsing it made real-node reconciles take 0.5-4 s and starved the
# single worker under load).
def Sync.host_pods(sched: Bool, +e: Env, +name: String) -> IO(List<&2, J2.Json>):
  match sched:
    case True{}:
      IO.bind(Result<&2, &2, Cl.KErr, J.Json>, List<&2, J2.Json>,
        Cl.Client.list(Env.h(e), C.Api{C.Res.pods(), C.AllNs{}},
          C.ListParams{RT.Runtime.not_mine(S.Svc.vc(Env.c(e))), "spec.nodeName=" ++ name, 500, "", ""}),
        r => IO.pure(List<&2, J2.Json>, Sync.items(r)))
    case False{}:
      IO.pure(List<&2, J2.Json>, [])

def Sync.rnodes.got(+st: SSt, +key: String, +e: Env, vr: Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>,
  hr: Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>, +pods: List<&2, J2.Json>) -> IO(Rec):
  match vr hr:
    case Fail{err} y:
      Sync.failed(key, err)
    case Done{v} Fail{err}:
      Sync.failed(key, err)
    case Done{+v} Done{+h}:
      Sync.run_act(CL.Classic.rnodes_k(Env.c(e), Env.on(e), CL.KFlags.ip(Env.kf(e)), Sync.vlast(st, key), v, Sync.hlast(st, key), h,
        Sync.values(st, CL.Classic.vpods()), Sync.values(st, CL.Classic.hpods()), pods), key, e, Sync.or_null(v), Sync.or_null(h))

def Sync.rnodes(+st: SSt, +name: String, +key: String, +e: Env) -> IO(Rec):
  do IO<Rec>:
    vr : Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>> <- Sync.mget(Env.v(e), "nodes", "", name)
    hr : Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>> <- Sync.mget(Env.h(e), "nodes", "", name)
    +pods : List<&2, J2.Json> <- Sync.host_pods(V.Config.virtual_scheduler(Env.on(e)), e, name)
    Sync.rnodes.got(st, key, e, vr, hr, pods)

def Sync.nodes.mode(real: Bool, +st: SSt, +name: String, +key: String, +e: Env) -> IO(Rec):
  match real:
    case True{}:
      Sync.rnodes(st, name, key, e)
    case False{}:
      Sync.nodes(st, name, key, e)

# Real volumes (sync.toHost.persistentVolumes.enabled): the virtual volume
# names its host volume (Classic.pv_host_name); the virtual claims are the
# store's.
def Sync.rpvs.host(+st: SSt, +key: String, +e: Env, +v: Maybe<&2, J2.Json>, hr: Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>) -> IO(Rec):
  match hr:
    case Fail{err}:
      Sync.failed(key, err)
    case Done{+h}:
      Sync.run_act(CL.Classic.rpvs(Env.c(e), Env.on(e), Sync.vlast(st, key), v, Sync.hlast(st, key), h,
        Sync.values(st, CL.Classic.vpvcs())), key, e, Sync.or_null(v), Sync.or_null(h))

def Sync.rpvs.virt(+st: SSt, +name: String, +key: String, +e: Env, vr: Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>) -> IO(Rec):
  match vr:
    case Fail{err}:
      Sync.failed(key, err)
    case Done{+v}:
      IO.bind(Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>, Rec,
        Sync.mget(Env.h(e), "persistentvolumes", "", CL.Classic.pv_host_name(Env.c(e), name, v)),
        hr => Sync.rpvs.host(st, key, e, v, hr))

def Sync.rpvs(+st: SSt, +name: String, +key: String, +e: Env) -> IO(Rec):
  IO.bind(Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>, Rec, Sync.mget(Env.v(e), "persistentvolumes", "", name),
    vr => Sync.rpvs.virt(st, name, key, e, vr))

def Sync.pvs.mode(real: Bool, +st: SSt, +name: String, +key: String, +e: Env) -> IO(Rec):
  match real:
    case True{}:
      Sync.rpvs(st, name, key, e)
    case False{}:
      Sync.pvs(st, name, key, e)

# Storage and priority classes to the host: the host class is named
# HostNameCluster.
def Sync.classes.read(+st: SSt, +id: String, +name: String, +key: String, +e: Env,
  vr: Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>, hr: Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>) -> IO(Rec):
  match vr hr:
    case Fail{err} y:
      Sync.failed(key, err)
    case Done{v} Fail{err}:
      Sync.failed(key, err)
    case Done{+v} Done{+h}:
      Sync.run_act(CL.Classic.class_step(id, Env.c(e), Env.on(e), name, Sync.vlast(st, key), v, Sync.hlast(st, key), h),
        key, e, Sync.or_null(v), Sync.or_null(h))

def Sync.classes(+st: SSt, +id: String, +name: String, +key: String, +e: Env) -> IO(Rec):
  do IO<Rec>:
    vr : Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>> <- Sync.mget(Env.v(e), id, "", name)
    hr : Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>> <- Sync.mget(Env.h(e), id, "", CL.Classic.cluster_host_name(Env.c(e), name))
    Sync.classes.read(st, id, name, key, e, vr, hr)

# CSINodes from the host: both CSINodes, and whether the virtual cluster
# has the node.
def Sync.csinodes.read(+st: SSt, +key: String, +e: Env, vr: Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>,
  hr: Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>, nr: Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>) -> IO(Rec):
  match vr hr:
    case Fail{err} y:
      Sync.failed(key, err)
    case Done{v} Fail{err}:
      Sync.failed(key, err)
    case Done{+v} Done{+h}:
      Sync.run_act(CL.Classic.csinodes(Env.c(e), Maybe.is_some(&2, J2.Json, Sync.opt(nr)), Sync.vlast(st, key), v, Sync.hlast(st, key), h),
        key, e, Sync.or_null(v), Sync.or_null(h))

def Sync.csinodes(+st: SSt, +name: String, +key: String, +e: Env) -> IO(Rec):
  do IO<Rec>:
    vr : Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>> <- Sync.mget(Env.v(e), "csinodes", "", name)
    hr : Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>> <- Sync.mget(Env.h(e), "csinodes", "", name)
    nr : Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>> <- Sync.mget(Env.v(e), "nodes", "", name)
    Sync.csinodes.read(st, key, e, vr, hr, nr)

# Endpoints (sl False) and EndpointSlices (sl True): the virtual and the
# host object, then the virtual Service ReconcileStart reads (the
# request's name, or the slice's kubernetes.io/service-name label). A
# skipping ReconcileStart keeps the key's old snapshots; one that deleted
# the host object keeps none for the host.
def Sync.uncache(r: Rec) -> Rec:
  match r:
    case Rec{a, v, h, ok}:
      Rec{a, v, h, False{}}

def Sync.run_act.cache(cache: Bool, a: CL.Act, +key: String, +e: Env, +v: J2.Json, +h: J2.Json) -> IO(Rec):
  match cache:
    case True{}:
      Sync.run_act(a, key, e, v, h)
    case False{}:
      IO.bind(Rec, Rec, Sync.run_act(a, key, e, v, h), r => IO.pure(Rec, Sync.uncache(r)))

def Sync.eps.run(+s: S.Start, +sl: Bool, +st: SSt, +hname: String, +key: String, +e: Env, +v: Maybe<&2, J2.Json>,
  +h: Maybe<&2, J2.Json>) -> IO(Rec):
  Sync.run_act.cache(CL.Classic.eps_cache(s),
    CL.Classic.eps(sl, s, Env.c(e), hname, Sync.vlast(st, key), v, Sync.hlast(st, key), h),
    key, e, Sync.or_null(v), Sync.or_null(CL.Classic.eps_snap(s, h)))

def Sync.eps.fin(+sl: Bool, +st: SSt, +ns: String, +name: String, +hname: String, +key: String, +e: Env,
  +v: Maybe<&2, J2.Json>, +h: Maybe<&2, J2.Json>, sr: Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>) -> IO(Rec):
  match sr:
    case Fail{err}:
      Sync.failed(key, err)
    case Done{svc}:
      Sync.eps.run(CL.Classic.eps_begin(sl, ns, name, v, svc, h), sl, st, hname, key, e, v, h)

def Sync.eps.read(+sl: Bool, +st: SSt, +ns: String, +name: String, +hname: String, +key: String, +e: Env,
  vr: Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>, hr: Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>) -> IO(Rec):
  match vr hr:
    case Fail{err} y:
      Sync.failed(key, err)
    case Done{v} Fail{err}:
      Sync.failed(key, err)
    case Done{+v} Done{+h}:
      IO.bind(Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>>, Rec,
        Sync.mget(Env.v(e), "services", ns, CL.Classic.eps_svc_name(sl, name, v)),
        sr => Sync.eps.fin(sl, st, ns, name, hname, key, e, v, h, sr))

def Sync.eps(+sl: Bool, +st: SSt, +ns: String, +name: String, +key: String, +e: Env) -> IO(Rec):
  do IO<Rec>:
    +res : String = CL.Classic.eps_res(sl)
    +hname : String = RT.Runtime.host_name(S.Svc.vc(Env.c(e)), ns, name)
    vr : Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>> <- Sync.mget(Env.v(e), res, ns, name)
    hr : Result<&2, &2, Cl.KErr, Maybe<&2, J2.Json>> <- Sync.mget(Env.h(e), res, Env.ns(e), hname)
    Sync.eps.read(sl, st, ns, name, hname, key, e, vr, hr)

def Sync.reconcile.id(+st: SSt, id: String, +ns: String, +name: String, +key: String, +e: Env) -> IO(Rec):
  match id:
    case "endpoints":
      Sync.eps(False{}, st, ns, name, key, e)
    case "endpointslices":
      Sync.eps(True{}, st, ns, name, key, e)
    case "pods":
      Sync.pods(st, ns, name, key, e)
    case "nodes":
      Sync.nodes.mode(CL.Classic.real_nodes(Env.on(e)), st, name, key, e)
    case "events":
      Sync.events(ns, name, key, e)
    case "persistentvolumeclaims":
      Sync.pvcs(st, ns, name, key, e)
    case "persistentvolumes":
      Sync.pvs.mode(CL.Classic.real_pvs(Env.on(e)), st, name, key, e)
    case "storageclasses":
      Sync.classes(st, "storageclasses", name, key, e)
    case "priorityclasses":
      Sync.classes(st, "priorityclasses", name, key, e)
    case "csinodes":
      Sync.csinodes(st, name, key, e)
    case _:
      IO.pure(Rec, Sync.nothing())

# A key of a kind vcluster.yaml leaves off reconciles to nothing.
def Sync.reconcile.new(on: Bool, +st: SSt, +id: String, +ns: String, +name: String, +key: String, +e: Env) -> IO(Rec):
  match on:
    case True{}:
      Sync.reconcile.id(st, id, ns, name, key, e)
    case False{}:
      IO.pure(Rec, Sync.nothing())

# A pod's references queue ConfigMap and Secret keys even when that kind
# is disabled; such a key reconciles to nothing.
def Sync.reconcile.on(on: Bool, +st: SSt, +k: RT.Resource, +ns: String, +name: String, +key: String, +e: Env) -> IO(Rec):
  match on:
    case True{}:
      Sync.reconcile.ref(st, k, ns, name, key, e, RT.Runtime.host_ref(k, Env.c(e), ns, name))
    case False{}:
      IO.pure(Rec, Rec{Q.AwaitChange{}, J2.JNull{}, J2.JNull{}, False{}})

def Sync.reconcile.kind(+st: SSt, m: Maybe<&2, RT.Resource>, +id: String, +ns: String, +name: String, +key: String,
  +e: Env) -> IO(Rec):
  match m:
    case None{}:
      Sync.reconcile.new(CL.Classic.any_on(Env.on(e), id), st, id, ns, name, key, e)
    case Some{+k}:
      Sync.reconcile.on(RT.Runtime.enabled(Env.on(e), k), st, k, ns, name, key, e)

def Sync.reconcile.key(+st: SSt, m: Maybe<&2, RT.SyncKey>, +key: String, +e: Env) -> IO(Rec):
  match m:
    case None{}:
      IO.pure(Rec, Rec{Q.AwaitChange{}, J2.JNull{}, J2.JNull{}, False{}})
    case Some{RT.SyncKey{+id, +ns, +name}}:
      Sync.reconcile.kind(st, RT.Runtime.kind_of(id), id, ns, name, key, e)

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

# Queue.pop marks a key running. Do not pop until every initial list
# has finished, or the sole worker is consumed without a matching done.
def Sync.pop_ready(ready: Bool, st: SSt) -> SSt & Maybe<&2, String>:
  match ready:
    case True{}:
      Sync.pop(st)
    case False{}:
      (st, None{})

def Sync.fst(r: SSt & Maybe<&2, String>) -> SSt:
  match r:
    case (st, m):
      st

def Sync.snd(r: SSt & Maybe<&2, String>) -> Maybe<&2, String>:
  match r:
    case (st, m):
      m

# Reconciles the queued keys, one at a time, while every store is ready.
# A reconcile that took over 3 s holds up every key behind it (the loop
# is one worker): logged with its key and duration.
def Sync.slow(slow: Bool, +key: String, +ms: Nat) -> IO(Unit):
  match slow:
    case True{}:
      L.Log.warn("slow reconcile", [L.Log.kv("key", key), L.Log.kv("ms", U32.show(U32.from_nat(ms)))])
    case False{}:
      IO.pure(Unit, Unit{})

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
        +t0 : Nat <- IO.now()
        +rec : Rec <- Sync.reconcile(st, key, e)
        +t1 : Nat <- IO.now()
        Sync.slow(Nat.is_gt(Nat.sub(t1, t0), 500n), key, Nat.sub(t1, t0))
        +st2 : SSt <- Sync.finish(st, key, rec, chan)
        Sync.drain(p, True{}, Sync.fst(Sync.pop(st2)), Sync.snd(Sync.pop(st2)), e, chan)

def Sync.drain_all.go(p: SSt & Maybe<&2, String>, +e: Env, +chan: Chan(R.Msg)) -> IO(SSt):
  match p:
    case (s2, k):
      Sync.drain(4294967295n, True{}, s2, k, e, chan)

def Sync.drain_all(+st: SSt, +e: Env, +chan: Chan(R.Msg)) -> IO(SSt):
  Sync.drain_all.go(Sync.pop_ready(Sync.ready(st), st), e, chan)

# Seconds since the epoch, modulo 2^32 (the resync tick's stamp).
def Sync.secs(+t: Nat) -> U32:
  U32.from_nat(Nat.div(t, 1000n))

def Sync.ticker(n: Nat, +chan: Chan(R.Msg)) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+p:
      do IO<Unit>:
        IO.sleep(30000)
        t : Nat <- IO.now()
        _ : Result<&1, &1, R.Msg, Unit> <- Chan.send(R.Msg, chan, R.MWake{CL.Classic.resync_key(), Sync.secs(t)})
        Sync.ticker(p, chan)

# The resync reads fresh LISTs, not the watch stores, so it also catches a
# pod whose event never reached a store.
def Sync.resync.add(st: SSt, +ks: List<&2, String>) -> SSt:
  match st:
    case SSt{ss, q, vl, hl}:
      SSt{ss, Q.Queue.add_all(ks, q), vl, hl}

# The resync's counts, and the pods it queues for lack of a host pod.
def Sync.resync.log(+nv: Nat, +nh: Nat, +miss: List<&2, String>) -> IO(Unit):
  L.Log.info("resync", [L.Log.kv("virtual-pods", U32.show(U32.from_nat(nv))), L.Log.kv("host-pods", U32.show(U32.from_nat(nh))),
    L.Log.kv("missing", String.join(miss, ","))])

def Sync.resync(+st: SSt, +e: Env) -> IO(SSt):
  do IO<SSt>:
    vr : Result<&2, &2, Cl.KErr, J.Json> <- Cl.Client.list(Env.v(e), C.Api{C.Res.pods(), C.AllNs{}}, C.ListParams.default())
    hr : Result<&2, &2, Cl.KErr, J.Json> <- Cl.Client.list(Env.h(e), C.Api{C.Res.pods(), C.InNs{Env.ns(e)}},
      C.ListParams{RT.Runtime.selector(S.Svc.vc(Env.c(e))), "", 0, "", ""})
    +vs : List<&2, J2.Json> = Sync.items(vr)
    +hs : List<&2, J2.Json> = Sync.items(hr)
    cr : Result<&2, &2, Cl.KErr, J.Json> <- Cl.Client.list(Env.h(e), C.Api{C.Res.config_maps(), C.InNs{Env.ns(e)}},
      C.ListParams{RT.Runtime.selector(S.Svc.vc(Env.c(e))), "", 0, "", ""})
    sr : Result<&2, &2, Cl.KErr, J.Json> <- Cl.Client.list(Env.h(e), C.Api{C.Res.secrets(), C.InNs{Env.ns(e)}},
      C.ListParams{RT.Runtime.selector(S.Svc.vc(Env.c(e))), "", 0, "", ""})
    +miss : List<&2, String> = CL.Classic.unsynced_pods(S.Svc.vc(Env.c(e)), vs, hs)
    Sync.resync.log(List.length(&2, J2.Json, vs), List.length(&2, J2.Json, hs), miss)
    return Sync.resync.add(st, List.append(&2, String, miss,
      List.append(&2, String, CL.Classic.lagging_pods(S.Svc.vc(Env.c(e)), vs, hs),
        CL.Classic.missing_refs(S.Svc.vc(Env.c(e)), CL.Classic.ref_keys_all(Env.c(e), vs), Sync.items(cr), Sync.items(sr)))))

# A resync tick that waited over 20 s in a busy loop is dropped: running
# every queued tick back to back added load to an already late loop.
def Sync.resync.fresh(fresh: Bool, +st: SSt, +e: Env) -> IO(SSt):
  match fresh:
    case True{}:
      Sync.resync(st, e)
    case False{}:
      IO.pure(SSt, st)

def Sync.wake_or_resync(resync: Bool, +st: SSt, +key: String, +gen: U32, +e: Env) -> IO(SSt):
  match resync:
    case True{}:
      do IO<SSt>:
        t : Nat <- IO.now()
        +now : U32 = Sync.secs(t)
        Sync.resync.fresh(U32.is_le(U32.sub(now, gen), 20), st, e)
    case False{}:
      IO.pure(SSt, Sync.on_wake(st, key, gen))

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
        +st2 : SSt <- Sync.drain_all(Sync.on_outs(st, src, outs, Env.c(e), CL.Classic.real_nodes(Env.on(e))), e, chan)
        x : Maybe<&1, R.Msg> <- Chan.recv(R.Msg, chan)
        Sync.loop(o, f, x, st2, e, chan)
    case o 1n+f Some{R.MWake{+key, gen}}:
      do IO<Unit>:
        +st1 : SSt <- Sync.wake_or_resync(String.eq(key, CL.Classic.resync_key()), st, key, gen, e)
        +st2 : SSt <- Sync.drain_all(st1, e, chan)
        x : Maybe<&1, R.Msg> <- Chan.recv(R.Msg, chan)
        Sync.loop(o, f, x, st2, e, chan)
    case o 1n+f Some{other}:
      do IO<Unit>:
        x : Maybe<&1, R.Msg> <- Chan.recv(R.Msg, chan)
        Sync.loop(o, f, x, st, e, chan)

# One store per watch source: two per wired kind (virtual, host), then
# the virtual pods. A disabled kind's stores are ready and stay empty.
def Sync.init.store(on: Bool) -> St.Store:
  match on:
    case True{}:
      St.Store.new()
    case False{}:
      St.Store.apply(St.Store.new(), W.OInitDone{})

def Sync.init.stores(ss: List<&2, CL.Source>, +on: J2.Json) -> List<&2, St.Store>:
  match ss:
    case Nil{}:
      []
    case Con{s, t}:
      Sync.init.store(CL.Classic.source_on(on, s)) <> Sync.init.stores(t, on)

def Sync.init.eps(ss: List<&2, CL.Source>, +on: J2.Json) -> List<&2, St.Store>:
  match ss:
    case Nil{}:
      []
    case Con{s, t}:
      Sync.init.store(CL.Classic.eps_source_on(on, s)) <> Sync.init.eps(t, on)

# After the source table: the vcluster's host Service's store
# (CL.Classic.kube_store), then the Endpoints and EndpointSlices table
# (CL.Classic.eps_base).
def Sync.init(+on: J2.Json) -> SSt:
  SSt{List.append(&2, St.Store, Sync.init.stores(CL.Classic.all_sources(), on),
      Sync.init.store(RT.Runtime.enabled(on, RT.KServices{})) <> Sync.init.eps(CL.Classic.eps_sources(), on)),
    Q.Queue.new(1), Map.new(&2, J2.Json), Map.new(&2, J2.Json)}

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

# vcluster's workload service account in the host namespace: host pods
# use it when service accounts do not sync (an existing one is kept).
def Sync.ensure_sa(+e: Env) -> IO(Unit):
  IO.bind(Result<&2, &2, Cl.KErr, J.Json>, Unit,
    Cl.Client.create(Env.h(e), Sync.rapi("serviceaccounts", Env.ns(e)), Sync.to4(CL.Classic.workload_sa(Env.c(e)))),
    r => IO.pure(Unit, Unit{}))

# The fake kubelet (host/kubelet_proxy.bend) calls both API servers with
# the syncer's own credentials. It takes PEM files: a kubeconfig's file
# paths as they are, inline data written under --kubelet-dir.
def Sync.write.close(p: File & Result<&1, &1, U32 & String, Unit>, +path: String) -> IO(String):
  match p:
    case (f, Done{u}):
      IO.bind(Unit, String, File.close(f), x => IO.pure(String, path))
    case (f, Fail{e}):
      IO.bind(Unit, String, File.close(f), x => IO.pure(String, ""))

def Sync.write.go(r: Result<&1, &1, U32 & String, File>, +path: String, text: String) -> IO(String):
  match r:
    case Fail{e}:
      IO.pure(String, "")
    case Done{f}:
      IO.bind(File & Result<&1, &1, U32 & String, Unit>, String, File.write(f, text), p => Sync.write.close(p, path))

def Sync.write(+path: String, text: String) -> IO(String):
  IO.bind(Result<&1, &1, U32 & String, File>, String, File.open(path, "w"), r => Sync.write.go(r, path, text))

def Sync.src_path(s: K.Src, +path: String) -> IO(String):
  match s:
    case K.FromFile{p}:
      IO.pure(String, p)
    case K.Inline{t}:
      Sync.write(path, t)
    case K.FromExec{c, a}:
      IO.pure(String, "")
    case K.NoSrc{}:
      IO.pure(String, "")
    case K.BadSrc{m}:
      IO.pure(String, "")

def Sync.text_of(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Done{t}:
      String.trim(t)
    case Fail{e}:
      ""

def Sync.src_text(s: K.Src) -> IO(String):
  match s:
    case K.Inline{t}:
      IO.pure(String, String.trim(t))
    case K.FromFile{p}:
      IO.bind(Result<&1, &1, U32 & String, String>, String, Cl.Fs.read(p), r => IO.pure(String, Sync.text_of(r)))
    case K.FromExec{c, a}:
      IO.pure(String, "")
    case K.NoSrc{}:
      IO.pure(String, "")
    case K.BadSrc{m}:
      IO.pure(String, "")

def Sync.up(cfg: K.Config, +dir: String, +pre: String, +extra: String) -> IO(KP.Up):
  match cfg:
    case K.Config{h, p, b, ca, ce, k, t, ns, pl, lm, sn, fc}:
      do IO<KP.Up>:
        a : String <- Sync.src_path(ca, dir ++ "/" ++ pre ++ "-ca.crt")
        c : String <- Sync.src_path(ce, dir ++ "/" ++ pre ++ ".crt")
        y : String <- Sync.src_path(k, dir ++ "/" ++ pre ++ ".key")
        tok : String <- Sync.src_text(t)
        IO.pure(KP.Up, KP.Up{h, p, sn, a, c, y, tok, extra})

def Sync.kubelet.cfg(+e: Env, h: KP.Up, v: KP.Up) -> KP.KCfg:
  KP.KCfg{"0.0.0.0", CL.Classic.kubelet_port(), CL.KFlags.cert(Env.kf(e)), CL.KFlags.key(Env.kf(e)), CL.KFlags.ca(Env.kf(e)),
    S.Svc.vc(Env.c(e)), Env.ns(e), Env.ns(e), h, v}

# Starts the fake kubelet on :10250 (vcluster serves it from the syncer).
def Sync.kubelet(+e: Env) -> IO(Unit):
  do IO<Unit>:
    h : KP.Up <- Sync.up(Env.h(e), CL.KFlags.dir(Env.kf(e)), "kubelet-proxy-host", "")
    v : KP.Up <- Sync.up(Env.v(e), CL.KFlags.dir(Env.kf(e)), "kubelet-proxy-virtual", "")
    IO.spawn(Unit, KP.Kubelet.serve(Sync.kubelet.cfg(e, h, v)))

# The leader's work: the fake kubelet, then the watches and the loop.
def Sync.start(+e: Env) -> IO(Unit):
  do IO<Unit>:
    Sync.kubelet(e)
    +chan : Chan(R.Msg) <- Chan.new(R.Msg, 4096)
    Sync.watches(CL.Classic.all_sources(), e, chan, 0)
    Sync.watch.kube(RT.Runtime.enabled(Env.on(e), RT.KServices{}), e, chan)
    Sync.eps_watches(CL.Classic.eps_sources(), e, chan, CL.Classic.eps_base())
    IO.spawn(Unit, Sync.ticker(4294967295n, chan))
    x : Maybe<&1, R.Msg> <- Chan.recv(R.Msg, chan)
    Sync.loop(4294967295n, 4294967295n, x, Sync.init(Env.on(e)), e, chan)

# Only the holder of the Lease syncs; a standby waits. The Lease lives in
# the host namespace (vcluster pkg/leaderelection), so every replica makes
# sure that namespace exists first.
# SIGTERM releases the Lease and exits. The timing is LOpts.default, the
# one Opts.with_election uses (15 s lease, 10 s renew deadline, 2 s
# retry); Leader.elect checks it at startup (Lease.timing, 0.5.1.0).
def Sync.elect(+e: Env, +me: String) -> IO(Unit):
  do IO<Unit>:
    L.Log.info("syncer starting", [L.Log.kv("id", me), L.Log.kv("host-namespace", Env.ns(e)),
      L.Log.kv("host", K.Config.host(Env.h(e))), L.Log.kv("virtual", K.Config.host(Env.v(e))),
      L.Log.kv("sync", String.join(CL.Classic.sync_ids(Env.on(e)), ",")),
      L.Log.kv("kubelet-ip", CL.KFlags.ip(Env.kf(e))), L.Log.kv("host-version", Env.hv(e))])
    Sync.ensure_ns(e)
    Sync.ensure_sa(e)
    E.Leader.elect(Env.h(e), E.LOpts.default(Env.ns(e), RT.Runtime.lease_name(S.Svc.vc(Env.c(e))), me),
      IO.pure(Bool, True{}), Sync.start(e))

def Sync.git_version(r: Result<&2, &2, Cl.KErr, J.Json>) -> String:
  match r:
    case Done{x}:
      CL.Classic.git_version(Sync.to2(x))
    case Fail{e}:
      ""

def Sync.configs(rv: Result<&2, &2, String, K.Config>, rh: Result<&2, &2, String, K.Config>,
  rc: Result<&2, &2, String, J2.Json>, +f: RT.Flags, +kf: CL.KFlags) -> IO(Unit):
  match rv rh rc:
    case Done{v} Done{+h} Done{on}:
      do IO<Unit>:
        +me : String <- Kb.Kube.ident()
        vr : Result<&2, &2, Cl.KErr, J.Json> <- Cl.Client.json(h, H.Req{"GET", "/version", [], ""})
        Sync.elect(Env{v, h, RT.Flags.cfg(f), RT.Flags.host_namespace(f), on, kf, Sync.git_version(vr)}, me)
    case Fail{m} x y:
      do IO<Unit>:
        L.Log.error("virtual kubeconfig", [L.Log.kv("path", RT.Flags.kubeconfig(f)), L.Log.kv("error", m)])
        IO.exit(1)
    case Done{v} Fail{m} y:
      do IO<Unit>:
        L.Log.error("host kubeconfig", [L.Log.kv("path", RT.Flags.host_kubeconfig(f)), L.Log.kv("error", m)])
        IO.exit(1)
    case Done{v} Done{h} Fail{m}:
      do IO<Unit>:
        L.Log.error("vcluster.yaml", [L.Log.kv("path", RT.Flags.config(f)), L.Log.kv("error", m)])
        IO.exit(1)

# The vcluster.yaml the syncer runs with: --config, or the chart defaults.
def Sync.read.close(p: File & Result<&1, &1, U32 & String, String>) -> IO(Maybe<&2, String>):
  match p:
    case (f, Done{s}):
      IO.bind(Unit, Maybe<&2, String>, File.close(f), u => IO.pure(Maybe<&2, String>, Some{s}))
    case (f, Fail{e}):
      IO.bind(Unit, Maybe<&2, String>, File.close(f), u => IO.pure(Maybe<&2, String>, None{}))

def Sync.read.go(r: Result<&1, &1, U32 & String, File>) -> IO(Maybe<&2, String>):
  match r:
    case Fail{e}:
      IO.pure(Maybe<&2, String>, None{})
    case Done{f}:
      IO.bind(File & Result<&1, &1, U32 & String, String>, Maybe<&2, String>, File.read(f, 1048576), Sync.read.close)

def Sync.read(+path: String) -> IO(Maybe<&2, String>):
  IO.bind(Result<&1, &1, U32 & String, File>, Maybe<&2, String>, File.open(path, "r"), Sync.read.go)

def Sync.vconfig.text(m: Maybe<&2, String>) -> Result<&2, &2, String, J2.Json>:
  match m:
    case None{}:
      Fail{"cannot read the file"}
    case Some{s}:
      V.Config.parse(s)

def Sync.vconfig(none: Bool, +path: String) -> IO(Result<&2, &2, String, J2.Json>):
  match none:
    case True{}:
      IO.pure(Result<&2, &2, String, J2.Json>, V.Config.parse(""))
    case False{}:
      IO.bind(Maybe<&2, String>, Result<&2, &2, String, J2.Json>, Sync.read(path),
        m => IO.pure(Result<&2, &2, String, J2.Json>, Sync.vconfig.text(m)))

def Syncer.main(+args: +List<String>) -> IO(Unit):
  do IO<Unit>:
    +f : RT.Flags = RT.Runtime.flags(args)
    rv : Result<&2, &2, String, K.Config> <- Cl.Config.from_kubeconfig(RT.Flags.kubeconfig(f), "")
    rh : Result<&2, &2, String, K.Config> <- Cl.Config.from_kubeconfig(RT.Flags.host_kubeconfig(f), "")
    rc : Result<&2, &2, String, J2.Json> <- Sync.vconfig(String.is_empty(RT.Flags.config(f)), RT.Flags.config(f))
    Sync.configs(rv, rh, rc, f, CL.Classic.kflags(args))
