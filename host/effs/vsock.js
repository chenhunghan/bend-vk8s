// Stand-ins for interpreting host/init.bend off Linux.
io_eff(CID(VSock.connect), (cid, port) => io_fail(4000, "AF_VSOCK needs the native lane on Linux"));
io_eff(CID(VSock.shut_wr), (fd) => fd);
