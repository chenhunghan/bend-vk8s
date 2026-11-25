// The guest's system calls run only native (gsys.c). These stand-ins let
// `bend` check and interpret programs that use them elsewhere: every
// effect fails with ENOSYS (38), so nothing is made, removed, mounted or
// set here.
const GSYS_ENOSYS = 38;
io_eff(CID(Gsys.mkdir), function (path, mode) { return GSYS_ENOSYS; });
io_eff(CID(Gsys.stat), function (path, follow) { return io_fail(GSYS_ENOSYS); });
io_eff(CID(Gsys.ls), function (dir) { return io_fail(GSYS_ENOSYS); });
io_eff(CID(Gsys.rename), function (from, to) { return GSYS_ENOSYS; });
io_eff(CID(Gsys.unlink), function (path) { return GSYS_ENOSYS; });
io_eff(CID(Gsys.rmdir), function (path) { return GSYS_ENOSYS; });
io_eff(CID(Gsys.mount), function (source, target, fstype, flags, data) { return GSYS_ENOSYS; });
io_eff(CID(Gsys.umount), function (target, flags) { return GSYS_ENOSYS; });
io_eff(CID(Gsys.settime), function (seconds) { return GSYS_ENOSYS; });
io_eff(CID(Gsys.fitrim), function (path) { return io_fail(GSYS_ENOSYS); });
io_eff(CID(Gsys.drain), function (path) { return io_fail(GSYS_ENOSYS); });
