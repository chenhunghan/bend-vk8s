// vk8s PID 1 runs only native (Linux). These stand-ins let `bend` check
// and interpret host/init.bend elsewhere: nothing starts, nothing exits.
io_eff(CID(Proc.start), function (prog, args, log) { return io_fail(38); });
io_eff(CID(Proc.reap), function () { return {$: CID(Nil)}; });
