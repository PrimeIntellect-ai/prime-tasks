Conditional keep for TempDir after initialization
Hi!

I was working with some utilities on top of tempfile and I ran into an interesting issue: in some cases (e.g. tests) it's often useful to mark something as conditionally persistent (e.g. if a debugging environment variable is set).

I'm definitely aware of the ability to persist `TempDir`s via `into_path` (as discussed in #315), but that changes the type from `TempDir` to `PathBuf`. That's useful in some cases but gets in the way of others (it's annoying to have to manage your own enum just for this).

Would it be possible to expose a `keep` method, just like there is for `NamedTempFile`? Having such a method would aid this use case tremendously.

Thanks!

### Additional contract requirements

`TempDir` must provide an in-place `disable_cleanup(&mut self, disable_cleanup: bool)` operation. When passed `true`, the directory is retained after the `TempDir` is dropped; passing `false` restores automatic removal. The operation must leave the caller with the same usable `TempDir` value rather than consuming it into a path.
