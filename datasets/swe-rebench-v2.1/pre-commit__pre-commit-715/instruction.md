Support tags as well as shas
They kind-of work as-is unless tags collide across different hooks.

The simplest solution is to make the repository symlinks [HIDDEN] as they are right now.

Then anything that git understands as `git checkout {0}` will work.

### Additional contract requirements

- Repository entries in the configuration use a `rev` key for the revision. The deprecated `sha` key is still accepted, but a repository entry must not specify both `sha` and `rev`.
- Add a public class `MigrateShaToRev` in `pre_commit.clientlib` with a `check(self, dct)` method and an `apply_default(self, dct)` method.
  - `check` validates a repository entry: `local` and `meta` repositories must not specify `sha` or `rev`; any other repository must specify exactly one of `sha` or `rev`, and its value must be a string. If both are specified, raise `cfgv.ValidationError` with the message `Cannot specify both sha and rev`.
  - `apply_default` mutates the given dictionary in place, replacing a present `sha` key with an equivalent `rev` key, and leaves a dictionary without `sha` unchanged.
- Add a public function `head_rev(remote)` in `pre_commit.git` that returns the SHA-1 of the remote's HEAD reference.
- Using the same tag or other revision for different repositories must not cause their repository storage or checkout results to collide.
