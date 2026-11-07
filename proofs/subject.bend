import Base
import ../laws/subject.bend as L
import ../src/net/subject.bend as T

def L.subject.kubelet_client():
  {==}

def L.subject.go_order():
  {==}

def L.subject.escapes():
  {==}

def L.subject.other_attributes():
  {==}

def L.subject.no_cn():
  {==}

def L.subject.empty():
  {==}

# Escaping h in front of t, then reading it plain, puts h in front of the
# plain reading of t, whatever class h has.
law Sj.esc_step:
  for +h: Char
  for +t: String
  for k: T.Subject.Cls
  for e: {T.Subject.cls(h) == k : T.Subject.Cls}
  {T.Subject.fields(T.Subject.esc.at(k, h, t)) == T.Subject.push(h, T.Subject.fields(t)) : +List<String>}

def Sj.esc_step(h, t, k, e):
  match k:
    case T.Bsl{}:
      %Equal.sym(T.Subject.Cls, T.Subject.cls(h), T.Bsl{}, e) : {T.Subject.Cut.esc(T.Subject.cut.at(_, h, T.Subject.cut(t))) == T.Subject.push(h, T.Subject.fields(t)) : +List<String>}
      {==}
    case T.Sep{}:
      %Equal.sym(T.Subject.Cls, T.Subject.cls(h), T.Sep{}, e) : {T.Subject.Cut.esc(T.Subject.cut.at(_, h, T.Subject.cut(t))) == T.Subject.push(h, T.Subject.fields(t)) : +List<String>}
      {==}
    case T.Meta{}:
      %Equal.sym(T.Subject.Cls, T.Subject.cls(h), T.Meta{}, e) : {T.Subject.Cut.esc(T.Subject.cut.at(_, h, T.Subject.cut(t))) == T.Subject.push(h, T.Subject.fields(t)) : +List<String>}
      {==}
    case T.Lit{}:
      %Equal.sym(T.Subject.Cls, T.Subject.cls(h), T.Lit{}, e) : {T.Subject.Cut.plain(T.Subject.cut.at(_, h, T.Subject.cut(t))) == T.Subject.push(h, T.Subject.fields(t)) : +List<String>}
      {==}

def L.subject.escape_one_field(s):
  match s:
    case SNil{}:
      {==}
    case SCon{+h, +t}:
      %Equal.sym(+List<String>, T.Subject.fields(T.Subject.esc.at(T.Subject.cls(h), h, T.Subject.escape(t))),
        T.Subject.push(h, T.Subject.fields(T.Subject.escape(t))),
        Sj.esc_step(h, T.Subject.escape(t), T.Subject.cls(h), {==})) : {_ == [SCon{h, t}] : +List<String>}
      %Equal.sym(+List<String>, T.Subject.fields(T.Subject.escape(t)), [t], L.subject.escape_one_field(t)) : {T.Subject.push(h, _) == [SCon{h, t}] : +List<String>}
      {==}
