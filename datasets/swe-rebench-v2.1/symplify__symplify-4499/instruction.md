[Easy-CI] check-conflicts regex will miss some conflicts
The check-conflicts command uses a regex to check for merge conflicts in your code.
It has a regex for 8 `<` characters:

https://github.com/symplify/easy-ci/blob/d08571ff4083f766ab2d376ccd4e4df2c2514a69/src/Git/ConflictResolver.php#L13-L17

However, when using using Atlassian SourceTree, a merge conflict is produced as follows: [(atlassian documentation)](https://www.atlassian.com/git/tutorials/using-branches/merge-conflicts)

```
<<<<<<< HEAD
this is some content to mess with
content to append
=======
totally different content to merge later
>>>>>>> new_branch_to_merge_later
```

This produces a a string of 7 `<` characters and will fail to be spotted by the check-conflicts command.

I'm not familiar if this is a particular git implementation or a general typo, but a Github also produces a 7 `<`'s [(github documentation)](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/addressing-merge-conflicts/resolving-a-merge-conflict-using-the-command-line)
