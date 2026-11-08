Make IpcWriteOptions easier to find.
Expose `arrow2::io::ipc::write::IpcWriteOptions` instead of `arrow2::io::ipc::write::common::IpcWriteOptions`, for easier access and logical meaning.

### Additional contract requirements

- `arrow2::io::ipc::write::IpcWriteOptions` provides a `default()` associated function that returns a default-initialized options value and never fails.
