False positives with hide-sensitive [secure] output
## Current behavior

One example: the [toReplace function](https://github.com/semantic-release/semantic-release/blob/0ef52e7a5f4f4c2bc3daecf7d71eeb1323491374/lib/hide-sensitive.js#L6) will match on the env var [`GOPRIVATE`](https://golang.org/cmd/go/#hdr-Module_configuration_for_non_public_modules) when using semantic-release on Go projects with that setting configured.  `GOPRIVATE` will typically have the same hostname as `repositoryUrl` in internal corporate networks.

If `GOPRIVATE=host.com` and `repositoryUrl=https://host.com/owner/repo.git` for example, then this breaks the links generated in release notes and changelog:

```
# [1.1.0](https://[secure]/owner/repo/compare/v1.0.0...v1.1.0) (2020-05-19)

### Features

* my feature ([d6c2e99a](https://[secure]/owner/repo/commit/d6c2e99aa27324878e7068a2c84229738b483794))
f502ba0a

```



## Expected behavior

In this scenario, `host.com` should not be replaced with `[secure]`:

```
# [1.1.0](https://host.com/owner/repo/compare/v1.0.0...v1.1.0) (2020-05-19)

### Features

* my feature ([d6c2e99a](https://host.com/owner/repo/commit/d6c2e99aa27324878e7068a2c84229738b483794))
f502ba0a

```

## Environment

- **semantic-release** version: 17.0.7
- CI environment: hosted Gitlab
- Plugins used: commit-analyzer,release-notes-generator,exec,changelog,git,gitlab
- **semantic-release** configuration: <!-- link to your repository or relevant part of the semantic-release config -->
- CI logs: <!-- link to your CI logs or semantic-release logs -->
