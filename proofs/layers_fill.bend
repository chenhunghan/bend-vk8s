import Base
import ../laws/layers_fill.bend as L

# Proofs of laws/layers_fill.bend: every law is concrete, so each side
# computes to the same value.

def L.layers_fill.blocks_zero():
  {==}

def L.layers_fill.blocks_one():
  {==}

def L.layers_fill.blocks_whole():
  {==}

def L.layers_fill.blocks_next():
  {==}

def L.layers_fill.blocks_4gib():
  {==}

def L.layers_fill.blocks_past_4gib():
  {==}

def L.layers_fill.head_none():
  {==}

def L.layers_fill.head_part():
  {==}

def L.layers_fill.head_zero():
  {==}

def L.layers_fill.act_skip():
  {==}

def L.layers_fill.act_ext():
  {==}

def L.layers_fill.act_skip_4gib():
  {==}

def L.layers_fill.act_end():
  {==}

def L.layers_fill.act_bad():
  {==}

def L.layers_fill.op_dir():
  {==}

def L.layers_fill.op_file():
  {==}

def L.layers_fill.op_whiteout():
  {==}

def L.layers_fill.op_opaque():
  {==}

def L.layers_fill.op_fifo():
  {==}

def L.layers_fill.plan_file():
  {==}

def L.layers_fill.plan_symlink():
  {==}

def L.layers_fill.plan_hard():
  {==}

def L.layers_fill.plan_device():
  {==}

def L.layers_fill.plan_pax():
  {==}

def L.layers_fill.plan_truncated():
  {==}

def L.layers_fill.sides():
  {==}

def L.layers_fill.syncs():
  {==}

def L.layers_fill.rec_path():
  {==}

def L.layers_fill.rec_path_refused():
  {==}

def L.layers_fill.rec_render():
  {==}

def L.layers_fill.rec_parse():
  {==}

def L.layers_fill.rec_parse_first():
  {==}

def L.layers_fill.rec_parse_other_version():
  {==}

def L.layers_fill.rec_parse_bad_chain():
  {==}

def L.layers_fill.rec_parse_time_overflow():
  {==}

def L.layers_fill.rec_parse_empty():
  {==}

def L.layers_fill.rec_new():
  {==}

def L.layers_fill.touch():
  {==}

def L.layers_fill.chain_of():
  {==}

def L.layers_fill.chain_of_other():
  {==}

def L.layers_fill.or_missing():
  {==}

def L.layers_fill.or_record():
  {==}

def L.layers_fill.or_other():
  {==}

def L.layers_fill.stale():
  {==}

def L.layers_fill.stale_tar():
  {==}

def L.layers_fill.stale_young():
  {==}

def L.layers_fill.stale_other_name():
  {==}

def L.layers_fill.stale_clock_back():
  {==}

def L.layers_fill.tmp_tar():
  {==}

def L.layers_fill.born():
  {==}

def L.layers_fill.born_plain():
  {==}

def L.layers_fill.born_other():
  {==}

def L.layers_fill.stale_name():
  {==}

def L.layers_fill.stale_name_young():
  {==}

# Proposed laws (feat/sec-layers-gc).

def L.layers_fill.present_both():
  {==}

def L.layers_fill.present_no_dir():
  {==}

def L.layers_fill.present_no_record():
  {==}

def L.layers_fill.unz_mib_ratio():
  {==}

def L.layers_fill.unz_mib_round_up():
  {==}

def L.layers_fill.unz_mib_small():
  {==}

def L.layers_fill.unz_mib_zero():
  {==}

def L.layers_fill.unz_mib_below_cap():
  {==}

def L.layers_fill.unz_mib_cap():
  {==}

def L.layers_fill.unz_mib_cap_big():
  {==}

def L.layers_fill.unz_why_cap():
  {==}

def L.layers_fill.unz_why_other():
  {==}

def L.layers_fill.max_ents():
  {==}

def L.layers_fill.too_many_at_cap():
  {==}

def L.layers_fill.too_many_past_cap():
  {==}

def L.layers_fill.ents_none():
  {==}

def L.layers_fill.held_line():
  {==}

def L.layers_fill.held_line_upper():
  {==}

def L.layers_fill.held_line_short():
  {==}

def L.layers_fill.held_line_no_holder():
  {==}

def L.layers_fill.held_line_bare():
  {==}

def L.layers_fill.held_line_long_hex():
  {==}

def L.layers_fill.held_line_path():
  {==}

def L.layers_fill.held_parse():
  {==}

def L.layers_fill.held_parse_empty():
  {==}

def L.layers_fill.hold():
  {==}

def L.layers_fill.gc_keeps_held():
  {==}

def L.layers_fill.gc_keeps_held_no_record():
  {==}

def L.layers_fill.lock_path():
  {==}

def L.layers_fill.lock_text():
  {==}

def L.layers_fill.lock_stale():
  {==}

def L.layers_fill.lock_young():
  {==}

def L.layers_fill.lock_clock_back():
  {==}

def L.layers_fill.lock_empty():
  {==}

def L.layers_fill.lock_junk():
  {==}

def L.layers_fill.lock_gone():
  {==}

def L.layers_fill.lock_found_young():
  {==}

def L.layers_fill.llock_path_v2():
  {==}

def L.layers_fill.llock_path_refused_v2():
  {==}

def L.layers_fill.llock_stale_v2():
  {==}

def L.layers_fill.llock_young_v2():
  {==}

def L.layers_fill.llock_gone_v2():
  {==}

def L.layers_fill.llock_writing_v2():
  {==}

def L.layers_fill.gc_keeps_held_v2():
  {==}

def L.layers_fill.gc_keeps_held_no_record_v2():
  {==}

def L.layers_fill.gc_skips_locked_v2():
  {==}

def L.layers_fill.gc_keeps_young_v2():
  {==}

def L.layers_fill.split_balanced_v2():
  {==}

def L.layers_fill.split_check_refuses_v2():
  {==}

def L.layers_fill.present_v2_needs_dir():
  {==}

def L.layers_fill.present_v2_file():
  {==}

def L.layers_fill.present_v2_symlink():
  {==}

def L.layers_fill.present_v2_missing():
  {==}

def L.layers_fill.present_v2_no_record():
  {==}
