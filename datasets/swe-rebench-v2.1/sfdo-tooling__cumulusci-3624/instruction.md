Setting `skip_future_releases` option for `github_automerge_feature` task in cumulusci.yml to false is ignored.
### Describe the bug

Whenever I attempt to change the option `skip_future_releases` to `False` and run `github_automerge_main` it appears to be ignored. This is confirmed when I attempt to do the same in a flow like `release_beta` and run it.

### Reproduction steps

1. Create `feature/001`, `feature/002`, and `feature/003` branches.
2. Make a commit on your main branch.
3. Add the following to your `cumulusci.yml` file:
```
    github_automerge_main:
        options:
            skip_future_releases: False
```
5. Run `github_automerge_main`

Result: Not all branches are updated with commit on main.

Expected Result: All branches are updated by a commit on main.


### Your CumulusCI and Python versions

CumulusCI version: 3.75.1 (/Users/julianjoseph/.local/bin/cci)
Python version: 3.10.0 (/Users/julianjoseph/.local/pipx/venvs/cumulusci/bin/python)

### Operating System

MacOS 13.3.1 (a)

### Windows environment

_No response_

### CumulusCI installation method

pipx

### Error Gist

_No response_

### Additional information

This is very obvious when you run `github_automerge_main` task within a flow since you get CLI logs like this:

```
                    ------------------------------------------------------------
                    Running task: github_automerge_main
                    ------------------------------------------------------------

                    Options:
                      commit: e1d00d5cfa27d0fdabeb8a5e952fde8ca21732fe
                      source_branch: main
                      branch_prefix: feature.
                      skip_future_releases: True
                      update_future_releases: False
```

A workaround is running `github_automerge_main` within the command task:

```
            4:
                task: command
                options:
                    command: cci task run github_automerge_main --skip_future_releases false
```

### Additional contract requirements

When `github_automerge_main` is run as part of a flow, an explicitly configured `skip_future_releases: false` must be honored as well. Future-release feature branches must not be skipped.
