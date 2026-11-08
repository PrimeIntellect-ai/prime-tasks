Use own unix::JoinHandleExt trait
The standard library's extension traits are not intended to be implemented for types other than the standard library.
Actually, there are discussions about sealing them: rust-lang/rust#81213, rust-lang/rust#80634
As long as we actually have a crate that depends on it, the standard library won't seal it, but it seems preferable to use our own extension trait anyway.

https://github.com/crossbeam-rs/crossbeam/blob/a95c02ea75d236a3560cd85075f71f8982bbf307/crossbeam-utils/src/thread.rs#L550
