`cargo update --config net.git-fetch-with-cli=true` fetches using git2
### Problem

As reported in renovatebot/renovate#29277
- Private git repo dependency fetching worked on 1.77 but not 1.78
- They used `net.git-fetch-with-cli=true` on the command-line

I git bisected it to #13479, specifically f525e1f383fc0d0a7adbdfb1bac6d6228ae79b33

### Steps

```console
$ git clone https://github.com/crate-ci/cargo-release.git
$ cd cargo-release
$ rm -rf ~/.cargo/git  # avoiding the github fast path
$ cargo update --config net.git-fetch-with-cli=true
```
Notice that the fetch is done using libgit2 instead of git.  To make this more obvious, I ran from master with a `dbg!` around the `git_fetch_with_cli` check at
https://github.com/rust-lang/cargo/blob/d04355a8c42f8c173a0c02625477edd668fc0cdd/src/cargo/sources/git/utils.rs#L1008

### Possible Solution(s)

_No response_

### Notes

_No response_

### Version

_No response_

### Additional contract requirements

- The effective network configuration is exposed by the global context's `net_config()`. Its public field `git_fetch_with_cli` reflects the effective value of the `net.git-fetch-with-cli` setting (`true`, `false`, or unset), including a value supplied on the command line with `--config`.
- When `cargo update -v --config net.git-fetch-with-cli=true` fetches a Git dependency, its stderr must contain the exact substring “[RUNNING] `git fetch [..]`”.
