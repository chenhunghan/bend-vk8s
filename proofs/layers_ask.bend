import Base
import ../laws/layers_ask.bend as L
import ../src/layers/snap.bend as S
import ../src/layers/ask.bend as A

# Proofs of laws/layers_ask.bend: the concrete laws compute to the same
# value on both sides; present_never splits on the call.

def L.layers_ask.label.ref():
  {==}

def L.layers_ask.label.manifest():
  {==}

def L.layers_ask.label.layer():
  {==}

def L.layers_ask.label.chain():
  {==}

def L.layers_ask.of_labels.prepare():
  {==}

def L.layers_ask.of_labels.short_ref():
  {==}

def L.layers_ask.of_labels.by_digest():
  {==}

def L.layers_ask.of_labels.present():
  {==}

def L.layers_ask.of_labels.view():
  {==}

def L.layers_ask.of_labels.commit():
  {==}

def L.layers_ask.of_labels.no_labels():
  {==}

def L.layers_ask.of_labels.no_manifest():
  {==}

def L.layers_ask.of_labels.no_layer():
  {==}

def L.layers_ask.of_labels.no_chain():
  {==}

def L.layers_ask.of_labels.no_ref():
  {==}

def L.layers_ask.of_labels.other_registry():
  {==}

def L.layers_ask.of_labels.present_never(op):
  match op:
    case S.OPrepare{k, p, ls}:
      {==}
    case S.OView{k, p, ls}:
      {==}
    case S.OCommit{n, k, p, ls}:
      {==}
    case S.ORemove{k}:
      {==}
    case S.OMounts{k}:
      {==}
    case S.OStat{k}:
      {==}
    case S.OUpdate{n, ls, ps}:
      {==}
    case S.OUsage{k}:
      {==}
    case S.OList{}:
      {==}
    case S.OCleanup{f}:
      {==}
    case S.OWalk{fs}:
      {==}

def L.layers_ask.of_labels.view_never(k, p, ls, b):
  {==}

def L.layers_ask.line_max():
  {==}

def L.layers_ask.render():
  {==}

def L.layers_ask.parse.line():
  {==}

def L.layers_ask.parse.each_mirror():
  {==}

def L.layers_ask.parse.ghcr():
  {==}

def L.layers_ask.parse.quay():
  {==}

def L.layers_ask.parse.other_registry():
  {==}

def L.layers_ask.parse.registry_port():
  {==}

def L.layers_ask.parse.upper_repo():
  {==}

def L.layers_ask.parse.dot_dot_repo():
  {==}

def L.layers_ask.parse.empty_repo():
  {==}

def L.layers_ask.parse.short_digest():
  {==}

def L.layers_ask.parse.upper_hex():
  {==}

def L.layers_ask.parse.other_algorithm():
  {==}

def L.layers_ask.parse.bad_chain():
  {==}

def L.layers_ask.parse.word():
  {==}

def L.layers_ask.parse.extra_field():
  {==}

def L.layers_ask.parse.two_spaces():
  {==}

def L.layers_ask.parse.no_newline():
  {==}

def L.layers_ask.parse.crlf():
  {==}

def L.layers_ask.parse.two_lines():
  {==}

def L.layers_ask.parse.empty():
  {==}

def L.layers_ask.parse.longest():
  {==}

def L.layers_ask.parse.repo_256():
  {==}

def L.layers_ask.parse.too_long():
  {==}

def L.layers_ask.reply.render.present():
  {==}

def L.layers_ask.reply.render.published():
  {==}

def L.layers_ask.reply.render.no():
  {==}

def L.layers_ask.reply.parse.present():
  {==}

def L.layers_ask.reply.parse.published():
  {==}

def L.layers_ask.reply.parse.no():
  {==}

def L.layers_ask.reply.parse.ok_alone():
  {==}

def L.layers_ask.reply.parse.ok_other():
  {==}

def L.layers_ask.reply.parse.upper():
  {==}

def L.layers_ask.reply.parse.no_reason():
  {==}

def L.layers_ask.reply.parse.no_newline():
  {==}

def L.layers_ask.reply.parse.control():
  {==}

def L.layers_ask.reply.parse.reason_80():
  {==}

def L.layers_ask.reply.parse.reason_81():
  {==}

def L.layers_ask.reply.had(e):
  {==}

def L.layers_ask.reply.published():
  {==}

def L.layers_ask.reply.failed():
  {==}

def L.layers_ask.reply.failed_newline():
  {==}

def L.layers_ask.reply.failed_empty():
  {==}

def L.layers_ask.reply.failed_long():
  {==}

def L.layers_ask.reply.round_failed():
  {==}

def L.layers_ask.host():
  {==}

def L.layers_ask.port():
  {==}

def L.layers_ask.wait_max():
  {==}


def L.layers_ask.wait_ms_v2():
  {==}

def L.layers_ask.reply_whole_line_v2():
  {==}

def L.layers_ask.reply_whole_partial_v2():
  {==}

def L.layers_ask.reply_whole_long_v2():
  {==}

def L.layers_ask.heard_no_v2():
  {==}

def L.layers_ask.heard_present_v2():
  {==}

def L.layers_ask.heard_junk_v2():
  {==}

def L.layers_ask.host_v3_unset():
  {==}

def L.layers_ask.host_v3_env():
  {==}

def L.layers_ask.nowait_v4():
  {==}

def L.layers_ask.waits_v4():
  {==}

def L.layers_ask.waits_v4_vm(stored):
  {==}

def L.layers_ask.nowait_said_v4():
  {==}

def L.layers_ask.quiet_ms_v4():
  {==}

def L.layers_ask.later_new_v4():
  {==}

def L.layers_ask.later_new_pending_v4():
  {==}

def L.layers_ask.later_add_v4():
  {==}

def L.layers_ask.later_add_pending_v4(l, a):
  match l:
    case A.Later{g, as}:
      match as:
        case Nil{}:
          {==}
        case Con{x, t}:
          {==}

def L.layers_ask.later_busy_v4():
  {==}

def L.layers_ask.later_busy_none_v4(g):
  {==}

def L.layers_ask.later_due_v4():
  {==}

def L.layers_ask.later_sent_v4():
  {==}

def L.layers_ask.later_again_done_v4():
  {==}

def L.layers_ask.later_due_stale_v4():
  {==}

def L.layers_ask.later_sent_stale_v4():
  {==}

def L.layers_ask.later_again_stale_v4():
  {==}

def L.layers_ask.later_due_unpacking_v4():
  {==}

def L.layers_ask.later_sent_unpacking_v4():
  {==}

def L.layers_ask.later_again_unpacking_v4():
  {==}

def L.layers_ask.later_again_none_v4():
  {==}

def L.layers_ask.unpacking_v4():
  {==}

def L.layers_ask.unpacking_committed_v4():
  {==}

def L.layers_ask.unpacking_fresh_v4():
  {==}

def L.layers_ask.unpacking_shared_v4():
  {==}
