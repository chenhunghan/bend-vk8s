import Base
import ../src/guest/supervise.bend as S

# Frozen spec for src/guest/supervise.bend: vk8s as PID 1 restarts daemons
# as vcluster standalone's systemd unit does (Restart=always, RestartSec=5s).

law supervise.restart_after_5s:
  {S.Sup.exited([S.Svc{"kubelet", "/k", [], "/l", 42, 0, 0n}], 42, 1000n)
    == [S.Svc{"kubelet", "/k", [], "/l", 0, 1, 6000n}] : +List<S.Svc>}

law supervise.orphan_ignored:
  {S.Sup.exited([S.Svc{"kubelet", "/k", [], "/l", 42, 0, 0n}], 77, 1000n)
    == [S.Svc{"kubelet", "/k", [], "/l", 42, 0, 0n}] : +List<S.Svc>}

law supervise.due_after_delay:
  {S.Sup.is_due(S.Svc{"kubelet", "/k", [], "/l", 0, 1, 6000n}, 5999n) == False{} : Bool}

law supervise.due_at_delay:
  {S.Sup.is_due(S.Svc{"kubelet", "/k", [], "/l", 0, 1, 6000n}, 6000n) == True{} : Bool}

law supervise.running_not_due:
  {S.Sup.is_due(S.Svc{"kubelet", "/k", [], "/l", 9, 0, 0n}, 99999n) == False{} : Bool}

# General laws.

# An exit never changes how many daemons there are.
law supervise.exited_length:
  for svcs: +List<S.Svc>
  for pid: U32
  for now: Nat
  {List.length(&2, S.Svc, S.Sup.exited(svcs, pid, now)) == List.length(&2, S.Svc, svcs) : Nat}

# The exit of pid 0 (no process) changes nothing.
law supervise.pid0_noop:
  for svcs: +List<S.Svc>
  for now: Nat
  {S.Sup.exited(svcs, 0, now) == svcs : +List<S.Svc>}

# A running daemon is never started a second time.
law supervise.running_never_due:
  for s: S.Svc
  for now: Nat
  for h: {Bool.not(U32.is_eq(S.Sup.pid(s), 0)) == True{} : Bool}
  {S.Sup.is_due(s, now) == False{} : Bool}

# Shutdown.

# Daemons stop last started first; stopped ones are skipped.
law supervise.stop_order_reverse:
  {S.Sup.stop_order([S.Svc{"etcd", "/e", [], "/l", 3, 0, 0n}, S.Svc{"apiserver", "/a", [], "/l", 0, 1, 0n},
     S.Svc{"kubelet", "/k", [], "/l", 7, 0, 0n}]) == [7, 3] : List<&2, U32>}

# A stopped daemon adds nothing to the stop order.
law supervise.stop_order_skips_stopped:
  for svcs: +List<S.Svc>
  for s: S.Svc
  for h: {U32.is_eq(S.Sup.pid(s), 0) == True{} : Bool}
  {S.Sup.stop_order(Con{s, svcs}) == S.Sup.stop_order(svcs) : List<&2, U32>}

# A running daemon stops after every daemon started after it.
law supervise.stop_order_running_last:
  for svcs: +List<S.Svc>
  for s: S.Svc
  for h: {U32.is_eq(S.Sup.pid(s), 0) == False{} : Bool}
  {S.Sup.stop_order(Con{s, svcs}) == List.append(&2, U32, S.Sup.stop_order(svcs), [S.Sup.pid(s)]) : List<&2, U32>}

# A daemon that exited is no longer alive.
law supervise.exited_not_alive:
  {S.Sup.alive(S.Sup.exited([S.Svc{"kube-apiserver", "/a", [], "/l", 7, 0, 0n}], 7, 100n), 7) == False{} : Bool}

law supervise.running_alive:
  {S.Sup.alive([S.Svc{"etcd", "/e", [], "/l", 3, 0, 0n}, S.Svc{"kube-apiserver", "/a", [], "/l", 7, 0, 0n}], 7) == True{} : Bool}
