import Base
import ../src/guest/plan.bend as P

# vk8s as PID 1 in the control-plane VM: runs the boot plan of
# src/guest/plan.bend, then stays alive (PID 1 must never exit).

def Init.say(+s: String) -> IO(Unit):
  IO.print("vk8s-init: " ++ s)

def Init.fail(+what: String, +why: String) -> IO(Unit):
  do IO<Unit>:
    Init.say("FAILED " ++ what ++ ": " ++ why)
    _ : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/bin/busybox", ["sh"], "", 1024, 2147483647)
    return Unit{}

def Init.ran.status(+what: String, ok: Bool, st: U32, +text: String) -> IO(Bool):
  match ok:
    case True{}:
      IO.pure(Bool, True{})
    case False{}:
      do IO<Bool>:
        Init.fail(what, "exit " ++ U32.show(st) ++ "\n" ++ text)
        return False{}

# Run a program; report its output and status when it fails.
def Init.ran(+what: String, r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> IO(Bool):
  match r:
    case Fail{(code, msg)}:
      do IO<Bool>:
        Init.fail(what, msg)
        return False{}
    case Done{(+st, (out, err))}:
      Init.ran.status(what, U32.is_eq(st, 0), st, out ++ err)

# A reusable list, as the affine list Process.run takes.
def Init.lin(xs: +List<String>) -> List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      Con{x, Init.lin(t)}

def Init.run(+prog: String, +args: +List<String>) -> IO(Bool):
  do IO<Bool>:
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run(prog, Init.lin(args), "", 1048576, 600000)
    Init.ran(prog ++ P.Plan.sh_words(args), r)

def Init.bb(args: +List<String>) -> IO(Bool):
  Init.run("/bin/busybox", args)

def Init.write.close(p: File & Result<&1, &1, U32 & String, Unit>) -> IO(Bool):
  match p:
    case (f, r):
      do IO<Bool>:
        File.close(f)
        return True{}

def Init.write.go(r: Result<&1, &1, U32 & String, File>, +text: String) -> IO(Bool):
  match r:
    case Fail{(code, msg)}:
      IO.pure(Bool, False{})
    case Done{f}:
      do IO<Bool>:
        p : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, text)
        Init.write.close(p)

def Init.write(+path: String, +text: String) -> IO(Bool):
  do IO<Bool>:
    _ : Bool <- Init.bb(["sh", "-c", "mkdir -p \"$(dirname " ++ P.Plan.sh_quote(path) ++ ")\""])
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "w")
    Init.write.go(r, text)

def Init.read.close(p: File & Result<&1, &1, U32 & String, String>) -> IO(String):
  match p:
    case (f, Done{s}):
      do IO<String>:
        File.close(f)
        return s
    case (f, Fail{e}):
      do IO<String>:
        File.close(f)
        return ""

def Init.read.go(r: Result<&1, &1, U32 & String, File>) -> IO(String):
  match r:
    case Fail{e}:
      IO.pure(String, "")
    case Done{f}:
      do IO<String>:
        p : File & Result<&1, &1, U32 & String, String> <- File.read(f, 1048576)
        Init.read.close(p)

def Init.read(+path: String) -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    Init.read.go(r)

def Init.insmod.one(empty: Bool, +m: String) -> IO(Bool):
  match empty:
    case True{}:
      IO.pure(Bool, True{})
    case False{}:
      Init.bb(["insmod", String.trim(m)])

def Init.insmods(ms: List<&2, String>) -> IO(Bool):
  match ms:
    case Nil{}:
      IO.pure(Bool, True{})
    case Con{+m, t}:
      do IO<Bool>:
        _ : Bool <- Init.insmod.one(String.is_empty(String.trim(m)), m)
        Init.insmods(t)

# ok: stop with True; else run the retry.
def Init.or_retry(ok: Bool, retry: IO(Bool)) -> IO(Bool):
  match ok:
    case True{}:
      IO.pure(Bool, True{})
    case False{}:
      retry

# ok: go on with next; else stop with False.
def Init.and_then(ok: Bool, next: IO(Bool)) -> IO(Bool):
  match ok:
    case True{}:
      next
    case False{}:
      IO.pure(Bool, False{})

def Init.sleep_then(next: IO(Bool)) -> IO(Bool):
  do IO<Bool>:
    IO.sleep(500)
    next

def Init.connected(r: Result<&1, &1, U32 & String, Socket>) -> IO(Bool):
  match r:
    case Fail{e}:
      IO.pure(Bool, False{})
    case Done{s}:
      do IO<Bool>:
        Socket.close(s)
        return True{}

def Init.wait_tcp(n: Nat, +host: String, +port: U32) -> IO(Bool):
  match n:
    case 0n:
      IO.pure(Bool, False{})
    case 1n+p:
      do IO<Bool>:
        r : Result<&1, &1, U32 & String, Socket> <- TCP.connect(host, port)
        ok : Bool <- Init.connected(r)
        Init.or_retry(ok, Init.sleep_then(Init.wait_tcp(p, host, port)))

def Init.exists(r: Result<&1, &1, U32 & String, File>) -> IO(Bool):
  match r:
    case Fail{e}:
      IO.pure(Bool, False{})
    case Done{f}:
      do IO<Bool>:
        File.close(f)
        return True{}

def Init.wait_file(n: Nat, +path: String) -> IO(Bool):
  match n:
    case 0n:
      IO.pure(Bool, False{})
    case 1n+p:
      do IO<Bool>:
        ok : Bool <- Init.bb(["test", "-e", path])
        Init.or_retry(ok, Init.sleep_then(Init.wait_file(p, path)))

def Init.tries(ms: U32) -> Nat:
  U32.to_nat((ms / 500 : U32))

def Init.waited(ok: Bool, +what: String) -> IO(Bool):
  match ok:
    case True{}:
      IO.pure(Bool, True{})
    case False{}:
      do IO<Bool>:
        Init.fail("wait", "timed out waiting for " ++ what)
        return False{}

def Init.step(s: P.Step) -> IO(Bool):
  match s:
    case P.Mount{+fs, +src, +dst, +opts}:
      do IO<Bool>:
        _ : Bool <- Init.bb(["mkdir", "-p", dst])
        Init.bb(["mount", "-t", fs, "-o", opts, src, dst])
    case P.Write{+path, +text}:
      Init.write(path, text)
    case P.Run{+prog, +args}:
      do IO<Bool>:
        Init.say("run " ++ prog ++ P.Plan.sh_words(args))
        Init.run(prog, args)
    case P.Daemon{+name, +prog, +args}:
      do IO<Bool>:
        Init.say("start " ++ name)
        _ : Bool <- Init.bb(["mkdir", "-p", "/var/log"])
        Init.bb(["sh", "-c", P.Plan.daemon_cmd(name, prog, args)])
    case P.WaitTcp{+host, +port, +ms}:
      do IO<Bool>:
        ok : Bool <- Init.wait_tcp(Init.tries(ms), host, port)
        Init.waited(ok, host ++ ":" ++ U32.show(port))
    case P.WaitFile{+path, +ms}:
      do IO<Bool>:
        ok : Bool <- Init.wait_file(Init.tries(ms), path)
        Init.waited(ok, path)
    case P.Modules{+path}:
      do IO<Bool>:
        text : String <- Init.read(path)
        Init.insmods(String.lines(text))
    case P.Log{+text}:
      do IO<Bool>:
        Init.say(text)
        return True{}

def Init.steps(ss: List<&2, P.Step>) -> IO(Bool):
  match ss:
    case Nil{}:
      IO.pure(Bool, True{})
    case Con{s, t}:
      do IO<Bool>:
        ok : Bool <- Init.step(s)
        Init.and_then(ok, Init.steps(t))

# PID 1 never exits: sleep forever (fuel large enough for decades).
def Init.idle(n: Nat) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+p:
      do IO<Unit>:
        IO.sleep(3600000)
        Init.idle(p)

def Init.name(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Fail{e}:
      "vk8s"
    case Done{s}:
      s

def Init.port.read(m: Maybe<&2, U32>) -> U32:
  match m:
    case None{}:
      6443
    case Some{p}:
      p

def Init.port(r: Result<&1, &1, U32 & String, String>) -> U32:
  match r:
    case Fail{e}:
      6443
    case Done{s}:
      Init.port.read(U32.read(s))

def main() -> IO(Unit):
  do IO<Unit>:
    Init.say("starting")
    r : Result<&1, &1, U32 & String, String> <- IO.get_env("VK8S_NAME")
    +name : String = Init.name(r)
    rp : Result<&1, &1, U32 & String, String> <- IO.get_env("VK8S_PORT")
    +port : U32 = Init.port(rp)
    ok : Bool <- Init.steps(P.Plan.boot(P.Plan.default_cfg(name, port)))
    Init.say("boot finished; shell on console")
    _ : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/bin/busybox", ["sh"], "", 1024, 2147483647)
    Init.idle(U32.to_nat(4294967295))
