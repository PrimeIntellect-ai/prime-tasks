Close NamedTempFile without deleting
Is there a way to close the file handle without deleting the actual file? On Windows, I have a problem where a child process cannot open the temporary file for reading because the file handle is open by the parent process, resulting in a sharing violation.

The child process (which I cannot change) is opening the file with *only* `FILE_SHARE_READ`, not `FILE_SHARE_READ | FILE_SHARE_WRITE`. According to the [Microsoft docs](https://msdn.microsoft.com/en-us/library/windows/desktop/aa363858(v=vs.85).aspx), if `FILE_SHARE_WRITE` is not specified in the share mode and another process has the file open for writing, `CreateFile` will fail with a sharing violation. Thus, the only way to fix this is to close the file handle before spawning the child process.

### Additional contract requirements

- Add a public method `NamedTempFile::into_temp_path(self) -> TempPath` that consumes the `NamedTempFile` and returns a `TempPath`. The returned `TempPath` owns the temporary file's path but no longer holds an open file descriptor, and the file itself is not deleted.
- Add a public type `TempPath` in the `tempfile` crate.
- Add a public method `TempPath::persist<P: AsRef<Path>>(self, new_path: P) -> Result<(), PathPersistError>` that moves the temporary file to `new_path`, consuming `self`, and returns `Ok(())` on success.
- Add a public method `TempPath::persist_noclobber<P: AsRef<Path>>(self, new_path: P) -> Result<(), PathPersistError>` that moves the temporary file to `new_path` only when no file exists there. On failure it returns `Err(PathPersistError)` preserving the `TempPath`.
- `TempPath::persist` and `TempPath::persist_noclobber` report failures as a `PathPersistError` value whose public `error` field exposes the underlying I/O failure, and which can be converted into the `TempPath` that could not be persisted (`From<PathPersistError> for TempPath`).
