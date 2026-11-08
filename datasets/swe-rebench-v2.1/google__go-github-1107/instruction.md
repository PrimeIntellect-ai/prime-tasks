RepositoryContent target field for symlinks
Per the [API docs](https://developer.github.com/v3/repos/contents/#response-if-content-is-a-symlink), when retrieving repository contents and the file is a symlink that doesn't point to a normal file (for example, a directory), the target field is set. The target field is currently missing from [RepositoryContent](https://github.com/google/go-github/blob/master/github/repos_contents.go#L23).

I will open a PR shortly to add the Target field.
