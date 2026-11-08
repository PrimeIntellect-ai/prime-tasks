Support git_repository_message / remove
It would be nice to support https://libgit2.org/libgit2/#HEAD/group/repository/git_repository_message , which is introduced in  v0.21.0. Thank you!

### Additional contract requirements

- Add a method `Message() (string, error)` on `Repository` that returns the contents of Git's prepared message file (for example `.git/MERGE_MSG`) after operations such as merge, revert or cherry-pick. The caller is responsible for removing the message after creating the commit.
- Add a method `RemoveMessage() error` on `Repository` that removes Git's prepared message file. After it succeeds, reading the prepared message again reports that no message is present.


- When merging the repository's `master` branch with itself, `Message()` must return exactly `Merge branch 'master'\n`.
