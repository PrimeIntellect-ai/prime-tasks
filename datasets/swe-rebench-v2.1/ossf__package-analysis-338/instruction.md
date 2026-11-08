Parse unlink from strace output to capture file deletion
Currently we don't record when "unlink" is run during execution.

This may be helpful when detecting malicious activity.

### Additional contract requirements

- Parse the `unlink` syscall from strace output and record the deleted file.
- Parse the `unlinkat` syscall from strace output and record the deleted file. For `unlinkat`, the recorded path is the directory path joined with the relative file name (for example `unlinkat(0x3 /tmp/dir, 0x... name, 0x0)` records `/tmp/dir/name`).
- The deleted file is recorded in the existing `strace.FileInfo` struct via a `Delete bool` field set to true.
