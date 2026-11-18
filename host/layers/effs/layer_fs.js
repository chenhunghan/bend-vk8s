// The layer file effects run only native (layer_fs.c). These stand-ins
// let `bend` check and interpret programs that use them elsewhere: every
// effect fails with ENOSYS (38), so no file is ever made here. A File
// handed to an effect comes back beside the failure.
const LAYER_FS_ENOSYS = 38;
io_eff(CID(LayerFs.read), function (file, off_hi, off_lo, max) { return io_tup(file, io_fail(LAYER_FS_ENOSYS)); });
io_eff(CID(LayerFs.copy), function (file, off_hi, off_lo, len_hi, len_lo, dst) {
  return io_tup(file, io_fail(LAYER_FS_ENOSYS));
});
io_eff(CID(LayerFs.make), function (kind, path, arg) { return io_fail(LAYER_FS_ENOSYS); });
io_eff(CID(LayerFs.fsync_dir), function (path) { return io_fail(LAYER_FS_ENOSYS); });
io_eff(CID(LayerFs.rename_dir), function (from, to) { return io_fail(LAYER_FS_ENOSYS); });
io_eff(CID(LayerFs.remove_tree), function (path) { return io_fail(LAYER_FS_ENOSYS); });
