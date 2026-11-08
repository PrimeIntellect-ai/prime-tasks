cargo-fix: --allow-dirty to imply --allow-staged?
### Problem

`cargo fix`/`clippy --fix` don't modify git's staging area, so the requirement to specify `--allow-staged` if there are any staged files is very cautious. Technically the staged files are not stored directly in the working directory, and can't be overwritten by the fix commands.

OTOH "dirty" state is much more volatile, and potentially has file changes in the working directory that haven't been saved anywhere, and which could be irreversibly lost when files are modified. This makes `--allow-dirty` a much stronger option that implies the local state is unimportant and can be lost.

This makes use of `--allow-dirty` *without* `--allow-staged` a weird edge case. It says the local changes are unimportant and can be overwritten even if they're unrecoverable, except being extra cautious about existence of local changes that are safe, and won't be overwritten. It's like having a `--force-overwrite` flag, but requiring `--allow-not-forced-non-overwrite` flag too.


### Proposed Solution

Having to add both `--allow-dirty --allow-staged` flags to the `fix` commands is verbose and a bit tedious to type. The extra `--allow-staged` flag could be avoided if the more destructive `--allow-dirty` also implied the lesser `--allow-staged`. Alternatively, maybe there could be a single option like `--force`/`-f` that implies both.


### Notes

_No response_

### Additional contract requirements

- When `cargo fix` refuses to run because of uncommitted changes, its suppression advice must say exactly: `if you'd like to suppress this error pass \`--allow-dirty\`, or commit the changes to these files:`
- The `--allow-dirty` help description must be exactly `Fix code even if the working directory is dirty or has staged changes`.
