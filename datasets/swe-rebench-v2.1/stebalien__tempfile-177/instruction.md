Support for temporary UNIX domain sockets
I have a case where I want to create a temporary socket file which should be deleted when the server shuts down. `tempfile::NamedTempFile` doesn't work for this because you can't call [`UnixListener::bind(path)`](https://doc.rust-lang.org/std/os/unix/net/struct.UnixListener.html#method.bind) on a file that already exists. It'd be great to have `tempfile` handle the file path construction, but delegate the `bind` to a callback function.

For example, the API could look something like this:
```rust
impl Builder {
    // The contract is that `F` must return `io::ErrorKind::AlreadyExists` or
    // `io::ErrorKind::AddrInUse` (in the case of sockets) to continue retrying.
    pub fn make<F, R>(&self, f: F) -> io::Result<R>
    where
        F: Fn(PathBuf) -> io::Result<R>,
    {
        self.make_in(&env::temp_dir(), f)
    }

    pub fn make_in<F, R, P>(&self, dir: P, f: F) -> io::Result<R>
    where
        F: Fn(PathBuf) -> io::Result<R>,
        P: AsRef<Path>,
    {
        util::create_helper(/* ... */)
    }
}
```

And used like this:
```rust
    let (listener, path) = tempfile::Builder::new()
        .make(|path| Ok((UnixListener::bind(&path)?, TempPath::from_path(path))))?;
```

If `NamedTempFile` gained a generic parameter (e.g., `NamedTempFile<F = File>`), then we could put the socket inside of that. I *think* this generic parameter could be a backward-compatible change, but I'm not sure. Such a change could come later, since the tuple above should work fine.
```rust
    let listener = tempfile::Builder::new().make(|path| {
        Ok(NamedTempFile::from_parts(
            UnixListener::bind(&path)?,
            TempPath::from_path(path),
        ))
    })?;
```

Let me know what you think of this idea! This is generic enough to support more use cases beyond UNIX domain sockets, but I'm not sure what they are yet. There also shouldn't be any breaking changes introduced by this.

I'm happy to implement this if it seems reasonable.

### Additional contract requirements

- `NamedTempFile` is generic over the wrapped resource type, written `NamedTempFile<F = File>`, and defaults to `std::fs::File`.
- `NamedTempFile::into_parts(self) -> (F, TempPath)` consumes the value and returns the wrapped resource together with its `TempPath`.
- `NamedTempFile::from_parts(file: F, path: TempPath) -> Self` reconstructs a `NamedTempFile<F>` from a resource and a `TempPath`.
- `Builder::make<F, R>(&self, f: F) -> io::Result<NamedTempFile<R>>`, where `F: FnMut(&Path) -> io::Result<R>`, generates a temporary path in the system temporary directory, calls `f` with it, and returns a `NamedTempFile<R>` that owns the produced resource and the temporary path.
- `Builder::make_in<F, R, P>(&self, dir: P, f: F) -> io::Result<NamedTempFile<R>>`, where `F: FnMut(&Path) -> io::Result<R>` and `P: AsRef<Path>`, behaves like `make` but generates the temporary path inside `dir`.
- When `f` returns an error whose kind is `io::ErrorKind::AlreadyExists` or `io::ErrorKind::AddrInUse`, the call is retried with a newly generated path.
- Both `make` and `make_in` honor the builder’s configured prefix and suffix when generating paths.
- The temporary path is deleted when the returned `NamedTempFile` is dropped.
