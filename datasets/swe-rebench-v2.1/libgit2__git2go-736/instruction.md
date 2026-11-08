Support git_repository_message / remove
It would be nice to support https://libgit2.org/libgit2/#HEAD/group/repository/git_repository_message , which is introduced in  v0.21.0. Thank you!

### Additional contract requirements

Expose `Repository.Message() (string, error)` to retrieve the repository’s prepared Git message, and expose `Repository.RemoveMessage() error` to remove it. After successful removal, a subsequent call to `Message` reports an error because there is no prepared message.
