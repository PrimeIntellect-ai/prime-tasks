Outdated package.json "repository" field fails when creating release
I’ve had this issue twice already, so posting here to share and potentially fix the issue in here, or maybe (most likely?) it’s an issue with the GitHub API.

If you rename a repository, and forget to update the `repository` field in package.json, this plugin fails when creating a release with the following error:

```
[9:38:17 AM] [semantic-release] › ℹ  Start step "publish" of plugin "@semantic-release/github"
[9:38:32 AM] [semantic-release] › ✘  Failed step "publish" of plugin "@semantic-release/github"
[9:38:32 AM] [semantic-release] › ✘  An error occurred while running semantic-release: RequestError [HttpError]: fetch failed
    at /home/runner/work/serverless-plugin-env-stage-config/serverless-plugin-env-stage-config/node_modules/.pnpm/@octokit+request@8.1.1/node_modules/@octokit/request/dist-node/index.js:136:11
    at async requestWithGraphqlErrorHandling (/home/runner/work/serverless-plugin-env-stage-config/serverless-plugin-env-stage-config/node_modules/.pnpm/@octokit+plugin-retry@6.0.0_@octokit+core@5.0.0/node_modules/@octokit/plugin-retry/dist-node/index.js:71:20)
    at async Job.doExecute (/home/runner/work/serverless-plugin-env-stage-config/serverless-plugin-env-stage-config/node_modules/.pnpm/bottleneck@2.19.5/node_modules/bottleneck/light.js:405:18) {
  status: 500,
  request: {
    method: 'POST',
    url: 'https://api.github.com/repos/bizon/serverless-plugin-stage-config/releases',
    headers: {
      accept: 'application/vnd.github.v3+json',
      'user-agent': '@semantic-release/github v9.0.4 octokit-core.js/5.0.0 Node.js/20.11.1 (linux; x64)',
      authorization: 'token [REDACTED]',
      'content-type': 'application/json; charset=utf-8'
    },
    body: '{"tag_name":"v1.3.7","target_commitish":"master","name":"v1.3.7","body":"## [1.3.7](https://github.com/bizon/serverless-plugin-stage-config/compare/v1.3.6...v1.3.7) (2024-03-29)\\n\\n\\n### Bug Fixes\\n\\n* re-release ([3a067ca](https://github.com/bizon/serverless-plugin-stage-config/commit/3a067ca38cc[60](https://github.com/bizon/serverless-plugin-env-stage-config/actions/runs/8479540859/job/23233712289#step:6:61)c8fa862cddc20a32b8673a79cd0))\\n\\n\\n\\n","prerelease":false}',
    request: {
      agent: undefined,
      hook: [Function: bound bound register],
      retryCount: 3,
      retries: 3,
      retryAfter: 16
    }
  },
  pluginName: '@semantic-release/github'
}
```

The package was renamed from `serverless-plugin-stage-config` to `serverless-plugin-env-stage-config`. The redirections are still active, but POSTing a new release fails with a 500 error.

### Additional contract requirements

- During verification, if GitHub's `clone_url` for the repository does not match the configured `repositoryUrl`, reject with a `SemanticReleaseError` whose code is `EMISMATCHGITHUBURL`.
