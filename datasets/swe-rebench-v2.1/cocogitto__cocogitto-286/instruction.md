[FEATURE] Allow running `cog check` on a commit range
**Is your feature request related to a problem? Please describe.**

As of now, the `cog check` command can be run either on all commits, or only on commits starting from the latest tag. There is no option to run `cog check` on a commit range (say, the commits associated with a PR).

**Describe the solution you'd like**

It would be preferable if we could have an option to run the `cog check` command on a commit range as well. I did go through the code, and noticed that the necessary utilities to parse a revision range from a string are already available, so this should be a simple addition. I'd be happy to open a PR if required.

**Describe alternatives you've considered**

For the exact problem I'm trying to solve (checking commits in a PR for compliance to the conventional commit specification), the cocogitto bot is a solution. However, we also have an additional requirement that the PR title must also comply to the conventional commit specification since we do squash merging. To solve for this, I was hoping to run `cog verify` against the PR title, and `cog check` against the commit range in a single workflow. I'm open to any other solutions you may have.

**Additional context**

N/A

### Additional contract requirements

- `CocoGitto::check` takes three arguments: `check_from_latest_tag: bool`, `ignore_merge_commits: bool`, and `range: Option<String>`, and returns a `Result`. When `range` is `Some`, the commits in that revision range are checked and the `check_from_latest_tag` flag is ignored. When `range` is `None`, the previous behaviour is preserved: the whole history is checked, or, when `check_from_latest_tag` is true, only the commits from the latest tag to HEAD.
- The `cog check` subcommand accepts an optional positional `[RANGE]` argument. The `--from-latest-tag`/`-l` flag and `[RANGE]` are mutually exclusive: supplying both is rejected with the error message `the argument '--from-latest-tag' cannot be used with '[RANGE]'`. The `--ignore-merge-commits`/`-i` flag remains available.
- When `ignore_merge_commits` is true, merge commits are not validated.
- A commit range that cannot be resolved is an error: `check` returns an error instead of silently checking an empty range or falling back to the whole history.


- For `cog check`, stderr includes `No errored commits` when no non-compliant commits are found. When exactly two non-compliant commits are found, stderr includes `Found 2 non compliant commits`.
