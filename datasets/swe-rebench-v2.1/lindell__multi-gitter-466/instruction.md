Feature request: Add a flag to allow only pushing the Feature Branch without creating a PR, or pushing directly to an existing branch
**Feature Branch only flag**
Add a flag to the `run` command to disable creating a pull request, to only create the feature branch.

**My use case**
In my case, I have multiple repositories which I want to run scripts against to create feature branches.
However I don't want to create a pull request to the default branch.
Instead I wish to create multiple pull requests from the feature branch to different protected branches in a sequential order.
To do this, I would like to add an option to only create the feature branch, and then create pull requests afterwards

**Implementation**
- [X] I would like to contribute this feature if it's a suitable addition to multi-gitter
- [ ] I have no intention of adding this feature myself.

### Additional contract requirements

- The `run` command accepts a boolean flag `--push-only` (default `false`). When it is set, the feature branch is created and pushed, but no pull request is opened.
- `--push-only` cannot be combined with `--fork`; using both fails with the error message `--push-only and --fork can't be used at the same time`.
- `--push-only` cannot be combined with `--skip-pr`; using both fails with the error message `--push-only and --skip-pr can't be used at the same time`.


- - On a successful `--push-only` run for `owner/example-repository`, `cmdOut` must be empty, and `out` must contain `Repositories with a successful run:` and `owner/example-repository`.
