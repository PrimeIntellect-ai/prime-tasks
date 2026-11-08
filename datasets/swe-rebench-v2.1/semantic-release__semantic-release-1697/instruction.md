Semantic-release silently fails on v17.2.3
## Current behavior

Since the last update of semantic-release to version 17.2.3, it started silently fail in Gitlab CI. When I set the version to 17.2.2 it started to work fine as usual.

## Environment

- **semantic-release** version: 17.2.3
- CI environment: Gitlab CI, gitlab-runner 12.9.0
- Plugins used:    `@semantic-release/changelog@5`, `@semantic-release/git@9`
- **semantic-release** configuration:

```json
{
  "plugins": [
    "@semantic-release/commit-analyzer",
    "@semantic-release/release-notes-generator",
    "@semantic-release/changelog",
    "@semantic-release/npm",
    [
      "@semantic-release/git",
      {
        "message": "chore(release): ${nextRelease.version} ${nextRelease.notes}"
      }
    ]
  ]
}
```

- CI logs:
```sh
$ npm i -g semantic-release@17
 /usr/local/bin/semantic-release -> /usr/local/lib/node_modules/semantic-release/bin/semantic-release.js
 + semantic-release@17.2.3
 added 743 packages from 1050 contributors in 45.978s
 $ npm i -g @semantic-release/changelog@5
 npm WARN @semantic-release/changelog@5.0.1 requires a peer of semantic-release@>=15.8.0 <18.0.0 but none is installed. You must install peer dependencies yourself.
 + @semantic-release/changelog@5.0.1
 added 12 packages from 8 contributors in 1.643s
 $ npm i -g @semantic-release/git@9
 npm WARN @semantic-release/git@9.0.0 requires a peer of semantic-release@>=16.0.0 <18.0.0 but none is installed. You must install peer dependencies yourself.
 + @semantic-release/git@9.0.0
 added 37 packages from 36 contributors in 2.807s
 $ semantic-release
Running after_script
01:05
Uploading artifacts for failed job
00:02
 ERROR: Job failed: exit code 1
```

- CI logs on version 17.2.2:

```sh
$ npm i -g semantic-release@17.2.2
 /usr/local/bin/semantic-release -> /usr/local/lib/node_modules/semantic-release/bin/semantic-release.js
 + semantic-release@17.2.2
 added 743 packages from 1050 contributors in 30.236s
 $ npm i -g @semantic-release/changelog@5
 npm WARN @semantic-release/changelog@5.0.1 requires a peer of semantic-release@>=15.8.0 <18.0.0 but none is installed. You must install peer dependencies yourself.
 + @semantic-release/changelog@5.0.1
 added 12 packages from 8 contributors in 1.444s
 $ npm i -g @semantic-release/git@9
 npm WARN @semantic-release/git@9.0.0 requires a peer of semantic-release@>=16.0.0 <18.0.0 but none is installed. You must install peer dependencies yourself.
 + @semantic-release/git@9.0.0
 added 37 packages from 36 contributors in 2.601s
 $ semantic-release
 [8:48:14 AM] [semantic-release] › ℹ  Running semantic-release version 17.2.2
 [8:48:15 AM] [semantic-release] › ✔  Loaded plugin "verifyConditions" from "@semantic-release/changelog"
 [8:48:15 AM] [semantic-release] › ✔  Loaded plugin "verifyConditions" from "@semantic-release/npm"
 [8:48:15 AM] [semantic-release] › ✔  Loaded plugin "verifyConditions" from "@semantic-release/git"
 [8:48:15 AM] [semantic-release] › ✔  Loaded plugin "analyzeCommits" from "@semantic-release/commit-analyzer"
 [8:48:15 AM] [semantic-release] › ✔  Loaded plugin "generateNotes" from "@semantic-release/release-notes-generator"
 [8:48:15 AM] [semantic-release] › ✔  Loaded plugin "prepare" from "@semantic-release/changelog"
 [8:48:15 AM] [semantic-release] › ✔  Loaded plugin "prepare" from "@semantic-release/npm"
 [8:48:15 AM] [semantic-release] › ✔  Loaded plugin "prepare" from "@semantic-release/git"
 [8:48:15 AM] [semantic-release] › ✔  Loaded plugin "publish" from "@semantic-release/npm"
 [8:48:15 AM] [semantic-release] › ✔  Loaded plugin "addChannel" from "@semantic-release/npm"
 [8:48:15 AM] [semantic-release] › ✔  Run automated release from branch master on repository https://gitlab-ci-token:[secure]@gitlab-rnd.tcsbank.ru/pfa/libs/front/use-request.git
 [8:48:16 AM] [semantic-release] › ✔  Allowed to push to the Git repository
 [8:48:16 AM] [semantic-release] › ℹ  Start step "verifyConditions" of plugin "@semantic-release/changelog"
 [8:48:16 AM] [semantic-release] › ✔  Completed step "verifyConditions" of plugin "@semantic-release/changelog"
 [8:48:16 AM] [semantic-release] › ℹ  Start step "verifyConditions" of plugin "@semantic-release/npm"
 [8:48:16 AM] [semantic-release] [@semantic-release/npm] › ℹ  Verify authentication for registry https://npm-rnd.tcsbank.ru/
 [8:48:16 AM] [semantic-release] [@semantic-release/npm] › ℹ  Reading npm config from /root/.npmrc, /builds/pfa/libs/front/use-request/.npmrc
 [8:48:16 AM] [semantic-release] › ✔  Completed step "verifyConditions" of plugin "@semantic-release/npm"
 [8:48:16 AM] [semantic-release] › ℹ  Start step "verifyConditions" of plugin "@semantic-release/git"
 [8:48:16 AM] [semantic-release] › ✔  Completed step "verifyConditions" of plugin "@semantic-release/git"
 [8:48:16 AM] [semantic-release] › ℹ  Found git tag v1.0.0 associated with version 1.0.0 on branch master
 [8:48:16 AM] [semantic-release] › ℹ  Found 6 commits since last release
 [8:48:16 AM] [semantic-release] › ℹ  Start step "analyzeCommits" of plugin "@semantic-release/commit-analyzer"
...
 [8:48:16 AM] [semantic-release] › ✔  Completed step "analyzeCommits" of plugin "@semantic-release/commit-analyzer"
 [8:48:16 AM] [semantic-release] › ℹ  The next release version is 1.1.0
 [8:48:16 AM] [semantic-release] › ℹ  Start step "generateNotes" of plugin "@semantic-release/release-notes-generator"
 [8:48:16 AM] [semantic-release] › ✔  Completed step "generateNotes" of plugin "@semantic-release/release-notes-generator"
 [8:48:16 AM] [semantic-release] › ℹ  Start step "prepare" of plugin "@semantic-release/changelog"
 [8:48:16 AM] [semantic-release] [@semantic-release/changelog] › ℹ  Update /builds/pfa/libs/front/use-request/CHANGELOG.md
 [8:48:16 AM] [semantic-release] › ✔  Completed step "prepare" of plugin "@semantic-release/changelog"
 [8:48:16 AM] [semantic-release] › ℹ  Start step "prepare" of plugin "@semantic-release/npm"
 [8:48:16 AM] [semantic-release] [@semantic-release/npm] › ℹ  Write version 1.1.0 to package.json in /builds/pfa/libs/front/use-request
 v1.1.0
 [8:48:16 AM] [semantic-release] › ✔  Completed step "prepare" of plugin "@semantic-release/npm"
 [8:48:16 AM] [semantic-release] › ℹ  Start step "prepare" of plugin "@semantic-release/git"
 [8:48:16 AM] [semantic-release] [@semantic-release/git] › ℹ  Found 3 file(s) to commit
 [8:48:18 AM] [semantic-release] [@semantic-release/git] › ℹ  Prepared Git release: v1.1.0
 [8:48:18 AM] [semantic-release] › ✔  Completed step "prepare" of plugin "@semantic-release/git"
 [8:48:18 AM] [semantic-release] › ℹ  Start step "generateNotes" of plugin "@semantic-release/release-notes-generator"
 [8:48:18 AM] [semantic-release] › ✔  Completed step "generateNotes" of plugin "@semantic-release/release-notes-generator"
 [8:48:20 AM] [semantic-release] › ✔  Created tag v1.1.0
 [8:48:20 AM] [semantic-release] › ℹ  Start step "publish" of plugin "@semantic-release/npm"
 [8:48:20 AM] [semantic-release] [@semantic-release/npm] › ℹ  Publishing version 1.1.0 to npm registry on dist-tag latest
 npm notice
...
 npm notice
 + @pfa/use-request@1.1.0
 [8:48:21 AM] [semantic-release] [@semantic-release/npm] › ℹ  Published @pfa/use-request@1.1.0 to dist-tag @latest on https://npm-rnd.tcsbank.ru/
 [8:48:21 AM] [semantic-release] › ✔  Completed step "publish" of plugin "@semantic-release/npm"
 [8:48:21 AM] [semantic-release] › ✔  Published release 1.1.0 on default channel
Running after_script
00:01
Saving cache
00:02
Uploading artifacts for successful job
00:01
 Job succeeded
```

### Additional contract requirements

The fix must ensure that sensitive environment variable values are redacted from log output both in their raw form and in their URL-encoded (percent-encoded) form.

In particular, when a sensitive value contains characters that are special in a regular expression (for example `$`, `^`, `{`, `.`, `+`, `}`, `\`, `[`, `]`, `*`, `(`, `)`), the URL-encoded form of that value must still be matched and replaced.

The public entry point is the module `lib/hide-sensitive.js`. It exports a function that takes an environment object and returns a function that redacts sensitive values from a string. Redacted values are replaced with the `SECRET_REPLACEMENT` constant, whose value is `[secure]`.
```
