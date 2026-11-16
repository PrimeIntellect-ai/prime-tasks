Add additional exit codes for `gh cache delete --all`
### Describe the feature or problem you’d like to solve

I use `gh cache delete --all` to purge all cache related to a workflow that stores ephemeral items in cache.

* When cache items are present and they are successfully removed, the command returns an exit code of 0.
* When no cache items are present, the command returns an exit code of 1.

Unless I parse standard error to read the message for the first case, I can't disambiguate it between an invocation that did not find any cache to remove, and one that did but failed to successfully remove it.

### Proposed solution

I propose a unique exit code for the specific case where no cache items were found. This would allow callers to treat this use case as a success and disambiguate it from any genuine errors.

This would simplify its usage for this use case significantly.

### Additional context

According to the [manual](https://cli.github.com/manual/gh_help_exit-codes), it appears this would not fall outside of the cli's existing behavior.

### Additional contract requirements

- Without any new option, `gh cache delete --all` still fails with an error when the repository has no caches to delete.
- `gh cache delete` accepts a new boolean option `--succeed-on-no-caches`. When it is given together with `--all` and the repository has no caches, the command succeeds: it returns no error and the process exits with code 0.
- When `--succeed-on-no-caches` is given together with `--all` and caches exist, they are deleted and the command succeeds.
- When `--succeed-on-no-caches` is given together with `--all` and listing the caches fails, the command still fails with an error.
- When `--succeed-on-no-caches` is given together with `--all` and a cache deletion request fails, the command still fails with an error.
