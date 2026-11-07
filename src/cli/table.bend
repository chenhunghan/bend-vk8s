import Base

# vcluster's table output (github.com/loft-sh/log/table.PrintTable over
# olekukonko/tablewriter: no borders, left-aligned cells, centered green
# headers), each line prefixed with two spaces by the logger.

def Table.spaces(n: Nat) -> String:
  match n:
    case 0n:
      ""
    case 1n+p:
      " " ++ Table.spaces(p)

def Table.dashes(n: Nat) -> String:
  match n:
    case 0n:
      ""
    case 1n+p:
      "-" ++ Table.dashes(p)

# Column widths: the longest cell of each column, the header included.
def Table.widths.max(xs: List<&2, Nat>, ys: +List<String>) -> List<&2, Nat>:
  match xs ys:
    case Con{+x, xt} Con{y, yt}:
      Con{Nat.max(x, String.length(y)), Table.widths.max(xt, yt)}
    case Con{x, xt} Nil{}:
      Con{x, Table.widths.max(xt, Nil{})}
    case Nil{} _:
      Nil{}

def Table.lengths(xs: +List<String>) -> List<&2, Nat>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      Con{String.length(x), Table.lengths(t)}

def Table.widths(rows: +List<+List<String>>, ws: List<&2, Nat>) -> List<&2, Nat>:
  match rows:
    case Nil{}:
      ws
    case Con{r, t}:
      Table.widths(t, Table.widths.max(ws, r))

def Table.left(+s: String, +w: Nat) -> String:
  s ++ Table.spaces(Nat.sub(w, String.length(s)))

def Table.center(+s: String, +w: Nat) -> String:
  +gap : Nat = Nat.sub(w, String.length(s))
  +l : Nat = Nat.div(gap, 2n)
  Table.spaces(l) ++ s ++ Table.spaces(Nat.sub(gap, l))

def Table.green(s: String) -> String:
  "\u{1b}[32m" ++ s ++ "\u{1b}[0m"

# Missing trailing cells of a short row are empty.
def Table.cells.pad(ws: List<&2, Nat>) -> String:
  match ws:
    case Nil{}:
      ""
    case Con{+w, Nil{}}:
      Table.spaces(w)
    case Con{+w, t}:
      Table.spaces(w) ++ " | " ++ Table.cells.pad(t)

def Table.cell(head: Bool, +x: String, +w: Nat) -> String:
  match head:
    case True{}:
      Table.green(Table.center(x, w))
    case False{}:
      Table.left(x, w)

# Cells joined with " | ", each padded to its width.
def Table.cells(+head: Bool, xs: +List<String>, ws: List<&2, Nat>) -> String:
  match xs ws:
    case Con{x, Nil{}} Con{+w, wt}:
      Table.cell(head, x, w)
    case Con{x, xt} Con{+w, wt}:
      Table.cell(head, x, w) ++ " | " ++ Table.cells(head, xt, wt)
    case Nil{} Con{+w, wt}:
      Table.cells.pad(Con{w, wt})
    case _ Nil{}:
      ""

def Table.line(+s: String) -> String:
  "    " ++ s ++ "  \n"

def Table.rule.go(ws: List<&2, Nat>) -> String:
  match ws:
    case Nil{}:
      ""
    case Con{+w, Nil{}}:
      Table.dashes(Nat.add(w, 3n))
    case Con{+w, t}:
      Table.dashes(Nat.add(w, 2n)) ++ "+" ++ Table.rule.go(t)

# The rule under the header: the outer columns are one dash wider.
def Table.rule(ws: List<&2, Nat>) -> String:
  match ws:
    case Nil{}:
      ""
    case Con{+w, Nil{}}:
      Table.dashes(Nat.add(w, 4n))
    case Con{+w, t}:
      Table.dashes(Nat.add(w, 3n)) ++ "+" ++ Table.rule.go(t)

def Table.rows(rs: +List<+List<String>>, +ws: List<&2, Nat>) -> String:
  match rs:
    case Nil{}:
      ""
    case Con{r, t}:
      Table.line(Table.cells(False{}, r, ws)) ++ Table.rows(t, ws)

# table.PrintTable(header, rows) as it reaches the terminal.
def Table.render(+header: +List<String>, +rows: +List<+List<String>>) -> String:
  +ws : List<&2, Nat> = Table.widths(rows, Table.lengths(header))
  "  \n" ++ Table.line(Table.cells(True{}, header, ws)) ++ "  " ++ Table.rule(ws) ++ "\n"
    ++ Table.rows(rows, ws) ++ "  \n"
