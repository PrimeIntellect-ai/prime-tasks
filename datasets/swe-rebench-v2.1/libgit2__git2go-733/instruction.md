Support git_remote_create_with_opts
Hello, first of all, thanks for such a great project!

It would be nice to support  https://libgit2.org/libgit2/#HEAD/group/remote/git_remote_create_with_opts , which is introduced in v0.28.0 . Thank you!

### Additional contract requirements

Expose the operation as `(*RemoteCollection).CreateWithOptions(url string, option *RemoteCreateOptions) (*Remote, error)`. The options include `Name`, `Flags`, and `FetchSpec`; a supplied fetch specification is used for the created remote. `RemoteCreateSkipInsteadof` prevents matching `url.*.insteadOf` configuration from rewriting the supplied URL. On successful creation, the returned remote has the requested name and, when this flag is set, retains the supplied URL.
