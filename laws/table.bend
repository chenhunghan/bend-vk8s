import Base
import ../src/cli/table.bend as T

# Spec for src/cli/table.bend: vcluster's list table. Expected text comes
# from running github.com/loft-sh/log/table.PrintTable (vendored in
# vcluster a8ab30e) with a stream logger: header NAME STATUS CONNECTED AGE.

def Laws.table.header() -> +List<String>:
  ["NAME", "STATUS", "CONNECTED", "AGE"]

law table.two_rows:
  {T.Table.render(Laws.table.header(), [["demo", "running", "True", "5m"], ["conformance-x", "paused", "", "2d1h"]])
   == "  \n    \u{1b}[32m    NAME     \u{1b}[0m | \u{1b}[32mSTATUS \u{1b}[0m | \u{1b}[32mCONNECTED\u{1b}[0m | \u{1b}[32mAGE \u{1b}[0m  \n  ----------------+---------+-----------+-------\n    demo          | running | True      | 5m    \n    conformance-x | paused  |           | 2d1h  \n  \n" : String}

law table.empty:
  {T.Table.render(Laws.table.header(), [])
   == "  \n    \u{1b}[32mNAME\u{1b}[0m | \u{1b}[32mSTATUS\u{1b}[0m | \u{1b}[32mCONNECTED\u{1b}[0m | \u{1b}[32mAGE\u{1b}[0m  \n  -------+--------+-----------+------\n  \n" : String}
