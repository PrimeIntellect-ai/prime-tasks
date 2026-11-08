`gh secret` subcommands don't work anymore if called outside of Git repository
### Describe the bug

After upgrading to GitHub CLI `2.67.0` all `gh secret set` commands that are run outside of git repository fails with this message:

```
failed to run git: fatal: not a git repository (or any parent up to mount point /)
Stopping at filesystem boundary (GIT_DISCOVERY_ACROSS_FILESYSTEM not set).
```

Actions like [this](https://github.com/AnimMouse/setup-rclone/blob/main/update-config/action.yaml#L20) are now failing if they are run without using `actions/checkout`.

Related: #4688 #10209

Maybe related: #10352

### Affected version

`2.67.0` `2.66.1` `2.66.0`

### Steps to reproduce the behavior

1. Upgrade to GitHub CLI 2.67.0
2. Run `GH_REPO=AnimMouse/test-repo gh secret set test_secret`
3. See error:

```
failed to run git: fatal: not a git repository (or any parent up to mount point /)
Stopping at filesystem boundary (GIT_DISCOVERY_ACROSS_FILESYSTEM not set).
```

### Expected vs actual behavior

Earlier version of `gh secret` worked without checking out the repository.

```
GH_REPO=AnimMouse/test-repo gh secret set test_secret
? Paste your secret:
```
