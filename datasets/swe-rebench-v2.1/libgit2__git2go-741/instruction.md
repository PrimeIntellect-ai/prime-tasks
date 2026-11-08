Support git_remote_create_with_opts
Hello, first of all, thanks for such a great project!

It would be nice to support  https://libgit2.org/libgit2/#HEAD/group/remote/git_remote_create_with_opts , which is introduced in v0.28.0 . Thank you!

### Additional contract requirements

- Add a public method `CreateWithOptions(url string, option *RemoteCreateOptions) (*Remote, error)` on `RemoteCollection` in package `git` (remote.go). It creates a new remote in the repository using the supplied URL and extended creation options.
- Add a public type `RemoteCreateOptions` in package `git` (remote.go) with fields `Name string` (the remote name) and `Flags RemoteCreateOptionsFlag`.
- Add a public type `RemoteCreateOptionsFlag` in package `git` (remote.go) and a constant `RemoteCreateSkipInsteadof` of that type. When it is set in `RemoteCreateOptions.Flags`, the repository's `insteadOf` URL configuration is not applied when creating the remote; when it is not set, `insteadOf` rewriting is applied.
- Add a public function `DefaultRemoteCreateOptions() (*RemoteCreateOptions, error)` in package `git` (remote.go) that returns a freshly allocated `RemoteCreateOptions` populated with libgit2 defaults.
