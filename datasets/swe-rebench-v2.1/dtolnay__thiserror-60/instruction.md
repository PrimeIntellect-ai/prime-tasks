Parse .0 fmt arguments better
For example `#[error("{}", .0.data)]` currently works but `#[error("{}", &.0.data)]` does not. We should make the `.0` / `.var` variables work wherever possible.
