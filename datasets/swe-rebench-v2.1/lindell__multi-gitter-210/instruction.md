Add flag to update a pull request thats already opened
After I've run multi-gitter and opened my prs, it would be great to have the ability to update my pr in the scenario where maybe I've missed something, or make a mistake and need to update.

Something like a 'multi-gitter run --update-pr`

### Additional contract requirements

The `run` command accepts a `--conflict-strategy` flag that controls what happens when the feature branch already exists. It accepts the values `skip` and `replace`, and defaults to `skip`. A value that is neither `skip` nor `replace` is rejected with an error.

- `skip`: if the feature branch already exists, no changes are made to it and no pull request is created.
- `replace`: if the feature branch already exists, the new changes replace the existing branch content (the branch is force pushed) and an already open pull request for that branch is reused instead of creating a new one. If no open pull request exists, a new one is created.

Add a public method `GetOpenPullRequest(ctx context.Context, repo scm.Repository, branchName string) (scm.PullRequest, error)` on the version controllers `Github` (package `internal/scm/github`), `Gitea` (package `internal/scm/gitea`), `Gitlab` (package `internal/scm/gitlab`) and `BitbucketServer` (package `internal/scm/bitbucketserver`). It returns the open pull request for the given repository and branch, or nil when none exists.
