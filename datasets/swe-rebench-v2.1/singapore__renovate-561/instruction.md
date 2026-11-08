Ignore forked repositories
e.g. for people who have installed Renovate on all repos.

If a repo is a fork, and it doesn't have a `renovate.json` in it, then ignore it.

### Additional contract requirements

- Add a public function `initRepo(repoName, token, endpoint, repoLogger)` in module `lib/api/github` that returns an object containing `privateRepo` (boolean) and `isFork` (boolean), reflecting the repository's privacy and fork status.
- The repository is identified as a fork when its `isFork` configuration field is `true`, and as lacking a `renovate.json` when its `renovateJsonPresent` configuration field is `false`.
