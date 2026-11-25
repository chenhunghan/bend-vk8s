// Stand-in for interpreting host/init.bend off Linux.
io_eff(CID(PackDev.mount), function (dev, off, len, target) { return 38; });
io_eff(CID(LoopDev.mount), function (image, target) { return 38; });
