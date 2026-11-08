Support git_repository_set_config
It would be nice to support https://github.com/libgit2/libgit2/blob/v1.1.0/include/git2/sys/repository.h#L86 which is introduced in v0.16.0 . Thank you!

### Additional contract requirements

Add a public method `func (v *Repository) SetConfig(c *Config) error` on the `Repository` type in package `github.com/libgit2/git2go/v30`. Calling it replaces the configuration associated with the repository with `c`, so that subsequent configuration queries on that repository use `c`.
