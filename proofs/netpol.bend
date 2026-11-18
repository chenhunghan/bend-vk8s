import Base
import ../laws/netpol.bend as L
import ../src/guest/plan.bend as P
import ../src/guest/netpol.bend as NP
import ../src/standalone/native.bend as N
import ../src/standalone/native_host.bend as NH

def L.netpol.version():
  {==}

def L.netpol.bin():
  {==}

def L.netpol.args():
  {==}

def L.netpol.daemon_from_kubelet():
  {==}

def L.netpol.gate_rules():
  {==}

def L.netpol.open_rules():
  {==}

def L.netpol.close():
  {==}

def L.netpol.open_in():
  {==}

def L.netpol.pending_closed():
  {==}

def L.netpol.pending_open():
  {==}

def L.netpol.pending_none():
  {==}

def L.netpol.probe():
  {==}

def L.netpol.synced_after_full_sync():
  {==}

def L.netpol.not_synced_empty_chain():
  {==}

def L.netpol.not_synced_no_chain():
  {==}

def L.netpol.not_synced_other_chain():
  {==}

def L.netpol.worker_order():
  {==}

def L.netpol.cp_rbac():
  {==}

def L.netpol.with_nil(cp, pod, svc):
  {==}

def L.netpol.other_daemon_kept(cp, pod, svc, name, prog, args, ss, h):
  %Equal.sym(Bool, String.eq(name, "kubelet"), False{}, h) : {List.append(&2, P.Step, NP.Netpol.kubelet(_, cp, pod, svc, name, prog, args), NP.Netpol.with(cp, pod, svc, ss))
    == Con{P.Daemon{name, prog, args}, NP.Netpol.with(cp, pod, svc, ss)} : +List<P.Step>}
  {==}

def L.netpol.run_kept(cp, pod, svc, prog, args, ss):
  {==}

def L.netpol.write_kept(cp, pod, svc, path, text, ss):
  {==}

def L.netpol.restarts():
  {==}

def L.netpol.native_no_node(e, o, c, h):
  %Equal.sym(Bool, NH.NHost.node(o), False{}, h) : {NP.Netpol.native_boot.go(_, e, o, c) == NH.NHost.boot.go(_, e, o, c) : +List<P.Step>}
  {==}

def L.netpol.modules():
  {==}

def L.netpol.ctr_modules():
  {==}

def L.netpol.native_modules():
  {==}

def L.netpol.native_tools():
  {==}

def L.netpol.ipt_clean():
  {==}

def L.netpol.ipset_destroy():
  {==}

def L.netpol.native_clean_script():
  {==}

def L.netpol.native_clean():
  {==}

def L.netpol.native_boot.v2.no_node(e, o, c, h):
  %Equal.sym(Bool, NH.NHost.node(o), False{}, h) : {NP.Netpol.native_boot.v2.go(_, e, o, c) == NH.NHost.boot.go(_, e, o, c) : +List<P.Step>}
  {==}
