// Stand-ins for interpreting host/init.bend off Linux.
io_eff(CID(Proc.signal), function (pid, sig) { return 38; });
io_eff(CID(Sys.power), function () { return 0; });
io_eff(CID(Sys.poweroff), function () { return 38; });
