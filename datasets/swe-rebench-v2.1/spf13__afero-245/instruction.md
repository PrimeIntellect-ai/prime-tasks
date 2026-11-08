MemMapFs does not respect os.O_EXCL
If `OpenFile` is called with `os.O_CREATE` and a file with the given path already exists, an `ErrFileExists` error should be returned.

While `OsFs` does support this, `MemMapFs` does not fail.
