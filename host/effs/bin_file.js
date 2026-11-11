// The binary file effects run only native (effs/bin_file.c). These
// stand-ins let `bend` check and interpret programs that use them
// elsewhere: every effect fails with ENOSYS (38), so no handle is ever
// made here. A File from Base's File.open handed to an effect comes back
// beside the failure; BinFile.close still closes it, so no descriptor
// leaks.
const BIN_FILE_ENOSYS = 38;
io_eff(CID(BinFile.open), function (path) { return io_fail(BIN_FILE_ENOSYS); });
io_eff(CID(BinFile.create), function (path) { return io_fail(BIN_FILE_ENOSYS); });
io_eff(CID(BinFile.append), function (file, data) { return io_tup(file, io_fail(BIN_FILE_ENOSYS)); });
io_eff(CID(BinFile.read), function (file, offset, max) { return io_tup(file, io_fail(BIN_FILE_ENOSYS)); });
io_eff(CID(BinFile.size), function (file) { return io_tup(file, io_fail(BIN_FILE_ENOSYS)); });
io_eff(CID(BinFile.close), function (file) {
  try {
    require("fs").closeSync(file);
  } catch (e) {
  }
  if (typeof io_file_append !== "undefined") {
    io_file_append.delete(file);
  }
  return { $: CID(Unit) };
});
