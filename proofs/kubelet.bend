import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../laws/kubelet.bend as L
import ../src/net/kubelet.bend as K
import ../src/net/subject.bend as T

# Proofs of laws/kubelet.bend: `def L.<law>` for each law.

# Concrete laws: both sides compute.

def L.kubelet.healthz_ok():
  {==}

def L.kubelet.pods_route():
  {==}

def L.kubelet.runningpods_route():
  {==}

def L.kubelet.runningpods_node():
  {==}

def L.kubelet.pods_answer_only_node():
  {==}

def L.kubelet.logs_check_pod():
  {==}

def L.kubelet.logs_missing_pod():
  {==}

def L.kubelet.logs_valid():
  {==}

def L.kubelet.logs_valid_relay():
  {==}

def L.kubelet.logs_sidecar():
  {==}

def L.kubelet.logs_init_container():
  {==}

def L.kubelet.logs_ephemeral_container():
  {==}

def L.kubelet.logs_empty_segment():
  {==}

def L.kubelet.logs_too_short():
  {==}

def L.kubelet.logs_options():
  {==}

def L.kubelet.exec_options():
  {==}

def L.kubelet.attach_options():
  {==}

def L.kubelet.portforward_options():
  {==}

def L.kubelet.portforward_pod_exists():
  {==}

def L.kubelet.stats_route():
  {==}

def L.kubelet.stats_node():
  {==}

def L.kubelet.unknown_forwarded():
  {==}

def L.kubelet.unknown_node():
  {==}

def L.kubelet.no_node():
  {==}

def L.kubelet.metrics_blocked():
  {==}

def L.kubelet.node_by_hostname():
  {==}

def L.kubelet.node_with_dots():
  {==}

def L.kubelet.node_legacy():
  {==}

def L.kubelet.node_no_port():
  {==}

def L.kubelet.node_ipv6():
  {==}

def L.kubelet.node_unknown():
  {==}

def L.kubelet.allow_apiserver():
  {==}

def L.kubelet.allow_apiserver_no_group():
  {==}

def L.kubelet.allow_masters():
  {==}

def L.kubelet.deny_node():
  {==}

def L.kubelet.deny_answer():
  {==}

def L.kubelet.stats_rewrite():
  {==}

def L.kubelet.stats_no_volumes():
  {==}

def L.kubelet.stats_error_passes():
  {==}

# Bool helpers (as in proofs/names.bend and proofs/services.bend).

def Kl.disc(b: Bool) -> Type:
  match b:
    case False{}:
      Unit
    case True{}:
      Empty

def Kl.false_true(e: {False{} == True{} : Bool}) -> Empty:
  %e : Kl.disc(_)
  Unit{}

def Kl.absurd(-A: Type, e: {False{} == True{} : Bool}) -> A:
  Empty.absurd(A, Kl.false_true(e))

law Kl.and_l:
  for +a: Bool
  for +b: Bool
  for +h: {Bool.and(a, b) == True{} : Bool}
  {a == True{} : Bool}

def Kl.and_l(a, b, h):
  match a:
    case True{}:
      {==}
    case False{}:
      h

law Kl.and_r:
  for +a: Bool
  for +b: Bool
  for +h: {Bool.and(a, b) == True{} : Bool}
  {b == True{} : Bool}

def Kl.and_r(a, b, h):
  match a:
    case True{}:
      h
    case False{}:
      Kl.absurd({b == True{} : Bool}, h)

# A name with no "/": its first char is not "/", and neither is any of the
# rest.
law Kl.head_ok:
  for +c: Char
  for +t: String
  for +b: Bool
  for +e: {Char.is_eq(c, '/') == b : Bool}
  for +h: {K.Kubelet.clean.at(b, K.Kubelet.clean(t)) == True{} : Bool}
  {Char.is_eq(c, '/') == False{} : Bool}

def Kl.head_ok(c, t, b, e, h):
  match b:
    case True{}:
      Kl.absurd({Char.is_eq(c, '/') == False{} : Bool}, h)
    case False{}:
      e

law Kl.tail_ok:
  for +c: Char
  for +t: String
  for +b: Bool
  for +e: {Char.is_eq(c, '/') == b : Bool}
  for +h: {K.Kubelet.clean.at(b, K.Kubelet.clean(t)) == True{} : Bool}
  {K.Kubelet.clean(t) == True{} : Bool}

def Kl.tail_ok(c, t, b, e, h):
  match b:
    case True{}:
      Kl.absurd({K.Kubelet.clean(t) == True{} : Bool}, h)
    case False{}:
      h

# Cutting a name with no "/", then "/", then r, gives the name, the "/" and
# r.
law Kl.seg_clean:
  for +a: String
  for +r: String
  for +h: {K.Kubelet.clean(a) == True{} : Bool}
  {K.Kubelet.seg(a ++ SCon{'/', r}) == K.Seg{a, True{}, r} : K.Seg}

def Kl.seg_clean(a, r, h):
  match a:
    case SNil{}:
      {==}
    case SCon{+c, +t}:
      %Equal.sym(Bool, Char.is_eq(c, '/'), False{}, Kl.head_ok(c, t, Char.is_eq(c, '/'), {==}, h)) : {K.Kubelet.seg.at(_, c, t ++ SCon{'/', r}, K.Kubelet.seg(t ++ SCon{'/', r})) == K.Seg{SCon{c, t}, True{}, r} : K.Seg}
      %Equal.sym(K.Seg, K.Kubelet.seg(t ++ SCon{'/', r}), K.Seg{t, True{}, r}, Kl.seg_clean(t, r, Kl.tail_ok(c, t, Char.is_eq(c, '/'), {==}, h))) : {K.Kubelet.Seg.cons(c, _) == K.Seg{SCon{c, t}, True{}, r} : K.Seg}
      {==}

# General laws.

def L.kubelet.parse_render(r, h):
  match r:
    case K.RLogs{+ns, +pod, +c}:
      %Equal.sym(K.Seg, K.Kubelet.seg(ns ++ SCon{'/', pod ++ SCon{'/', c}}), K.Seg{ns, True{}, pod ++ SCon{'/', c}},
        Kl.seg_clean(ns, pod ++ SCon{'/', c}, Kl.and_l(K.Kubelet.clean(ns), Bool.and(K.Kubelet.clean(pod), K.Kubelet.clean(c)), h))) : {K.Kubelet.three(_, K.KLogs{}, "/containerLogs/" ++ K.Kubelet.p3(ns, pod, c)) == K.RLogs{ns, pod, c} : K.Route}
      %Equal.sym(K.Seg, K.Kubelet.seg(pod ++ SCon{'/', c}), K.Seg{pod, True{}, c},
        Kl.seg_clean(pod, c, Kl.and_l(K.Kubelet.clean(pod), K.Kubelet.clean(c), Kl.and_r(K.Kubelet.clean(ns), Bool.and(K.Kubelet.clean(pod), K.Kubelet.clean(c)), h)))) : {K.Kubelet.three.b(_, K.KLogs{}, ns, "/containerLogs/" ++ K.Kubelet.p3(ns, pod, c)) == K.RLogs{ns, pod, c} : K.Route}
      %Equal.sym(Bool, K.Kubelet.clean(c), True{},
        Kl.and_r(K.Kubelet.clean(pod), K.Kubelet.clean(c), Kl.and_r(K.Kubelet.clean(ns), Bool.and(K.Kubelet.clean(pod), K.Kubelet.clean(c)), h))) : {K.Kubelet.three.c(_, K.KLogs{}, ns, pod, c, "/containerLogs/" ++ K.Kubelet.p3(ns, pod, c)) == K.RLogs{ns, pod, c} : K.Route}
      {==}
    case K.RExec{+ns, +pod, +c}:
      %Equal.sym(K.Seg, K.Kubelet.seg(ns ++ SCon{'/', pod ++ SCon{'/', c}}), K.Seg{ns, True{}, pod ++ SCon{'/', c}},
        Kl.seg_clean(ns, pod ++ SCon{'/', c}, Kl.and_l(K.Kubelet.clean(ns), Bool.and(K.Kubelet.clean(pod), K.Kubelet.clean(c)), h))) : {K.Kubelet.three(_, K.KExec{}, "/exec/" ++ K.Kubelet.p3(ns, pod, c)) == K.RExec{ns, pod, c} : K.Route}
      %Equal.sym(K.Seg, K.Kubelet.seg(pod ++ SCon{'/', c}), K.Seg{pod, True{}, c},
        Kl.seg_clean(pod, c, Kl.and_l(K.Kubelet.clean(pod), K.Kubelet.clean(c), Kl.and_r(K.Kubelet.clean(ns), Bool.and(K.Kubelet.clean(pod), K.Kubelet.clean(c)), h)))) : {K.Kubelet.three.b(_, K.KExec{}, ns, "/exec/" ++ K.Kubelet.p3(ns, pod, c)) == K.RExec{ns, pod, c} : K.Route}
      %Equal.sym(Bool, K.Kubelet.clean(c), True{},
        Kl.and_r(K.Kubelet.clean(pod), K.Kubelet.clean(c), Kl.and_r(K.Kubelet.clean(ns), Bool.and(K.Kubelet.clean(pod), K.Kubelet.clean(c)), h))) : {K.Kubelet.three.c(_, K.KExec{}, ns, pod, c, "/exec/" ++ K.Kubelet.p3(ns, pod, c)) == K.RExec{ns, pod, c} : K.Route}
      {==}
    case K.RAttach{+ns, +pod, +c}:
      %Equal.sym(K.Seg, K.Kubelet.seg(ns ++ SCon{'/', pod ++ SCon{'/', c}}), K.Seg{ns, True{}, pod ++ SCon{'/', c}},
        Kl.seg_clean(ns, pod ++ SCon{'/', c}, Kl.and_l(K.Kubelet.clean(ns), Bool.and(K.Kubelet.clean(pod), K.Kubelet.clean(c)), h))) : {K.Kubelet.three(_, K.KAttach{}, "/attach/" ++ K.Kubelet.p3(ns, pod, c)) == K.RAttach{ns, pod, c} : K.Route}
      %Equal.sym(K.Seg, K.Kubelet.seg(pod ++ SCon{'/', c}), K.Seg{pod, True{}, c},
        Kl.seg_clean(pod, c, Kl.and_l(K.Kubelet.clean(pod), K.Kubelet.clean(c), Kl.and_r(K.Kubelet.clean(ns), Bool.and(K.Kubelet.clean(pod), K.Kubelet.clean(c)), h)))) : {K.Kubelet.three.b(_, K.KAttach{}, ns, "/attach/" ++ K.Kubelet.p3(ns, pod, c)) == K.RAttach{ns, pod, c} : K.Route}
      %Equal.sym(Bool, K.Kubelet.clean(c), True{},
        Kl.and_r(K.Kubelet.clean(pod), K.Kubelet.clean(c), Kl.and_r(K.Kubelet.clean(ns), Bool.and(K.Kubelet.clean(pod), K.Kubelet.clean(c)), h))) : {K.Kubelet.three.c(_, K.KAttach{}, ns, pod, c, "/attach/" ++ K.Kubelet.p3(ns, pod, c)) == K.RAttach{ns, pod, c} : K.Route}
      {==}
    case K.RRun{+ns, +pod, +c}:
      %Equal.sym(K.Seg, K.Kubelet.seg(ns ++ SCon{'/', pod ++ SCon{'/', c}}), K.Seg{ns, True{}, pod ++ SCon{'/', c}},
        Kl.seg_clean(ns, pod ++ SCon{'/', c}, Kl.and_l(K.Kubelet.clean(ns), Bool.and(K.Kubelet.clean(pod), K.Kubelet.clean(c)), h))) : {K.Kubelet.three(_, K.KRun{}, "/run/" ++ K.Kubelet.p3(ns, pod, c)) == K.RRun{ns, pod, c} : K.Route}
      %Equal.sym(K.Seg, K.Kubelet.seg(pod ++ SCon{'/', c}), K.Seg{pod, True{}, c},
        Kl.seg_clean(pod, c, Kl.and_l(K.Kubelet.clean(pod), K.Kubelet.clean(c), Kl.and_r(K.Kubelet.clean(ns), Bool.and(K.Kubelet.clean(pod), K.Kubelet.clean(c)), h)))) : {K.Kubelet.three.b(_, K.KRun{}, ns, "/run/" ++ K.Kubelet.p3(ns, pod, c)) == K.RRun{ns, pod, c} : K.Route}
      %Equal.sym(Bool, K.Kubelet.clean(c), True{},
        Kl.and_r(K.Kubelet.clean(pod), K.Kubelet.clean(c), Kl.and_r(K.Kubelet.clean(ns), Bool.and(K.Kubelet.clean(pod), K.Kubelet.clean(c)), h))) : {K.Kubelet.three.c(_, K.KRun{}, ns, pod, c, "/run/" ++ K.Kubelet.p3(ns, pod, c)) == K.RRun{ns, pod, c} : K.Route}
      {==}
    case K.RPortForward{+ns, +pod}:
      %Equal.sym(K.Seg, K.Kubelet.seg(ns ++ SCon{'/', pod}), K.Seg{ns, True{}, pod},
        Kl.seg_clean(ns, pod, Kl.and_l(K.Kubelet.clean(ns), K.Kubelet.clean(pod), h))) : {K.Kubelet.two(_, "/portForward/" ++ K.Kubelet.p2(ns, pod)) == K.RPortForward{ns, pod} : K.Route}
      %Equal.sym(Bool, K.Kubelet.clean(pod), True{},
        Kl.and_r(K.Kubelet.clean(ns), K.Kubelet.clean(pod), h)) : {K.Kubelet.two.b(_, ns, pod, "/portForward/" ++ K.Kubelet.p2(ns, pod)) == K.RPortForward{ns, pod} : K.Route}
      {==}
    case K.RPods{}:
      {==}
    case K.RRunningPods{}:
      {==}
    case K.RStats{}:
      {==}
    case K.RMetrics{}:
      {==}
    case K.RCadvisor{}:
      {==}
    case K.RResource{}:
      {==}
    case K.RProbes{}:
      {==}
    case K.RHealthz{}:
      {==}
    case K.RUnknown{p}:
      Kl.absurd({K.Kubelet.parse(K.Kubelet.render(K.RUnknown{p})) == K.RUnknown{p} : K.Route}, h)

def L.kubelet.host_in_target(vc, t, r, qs):
  match r:
    case K.RLogs{ns, pod, c}:
      {==}
    case K.RExec{ns, pod, c}:
      {==}
    case K.RAttach{ns, pod, c}:
      {==}
    case K.RPortForward{ns, pod}:
      {==}
    case K.RRun{ns, pod, c}:
      {==}
    case K.RPods{}:
      {==}
    case K.RRunningPods{}:
      {==}
    case K.RStats{}:
      {==}
    case K.RMetrics{}:
      {==}
    case K.RCadvisor{}:
      {==}
    case K.RResource{}:
      {==}
    case K.RProbes{}:
      {==}
    case K.RHealthz{}:
      {==}
    case K.RUnknown{p}:
      {==}
