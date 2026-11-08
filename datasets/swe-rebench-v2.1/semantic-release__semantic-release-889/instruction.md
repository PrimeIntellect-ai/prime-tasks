repositoryUrl is forcefully transformed
## Current behavior

According to error messages semantic-release forcefully transforms the repositoryUrl to https as described in #667. I'm using git/ssl to interact with the repo on my gitlabserver. running the failing git push --dry-run from commandline works just fine (see the very end of the logs below). GITLAB_TOKEN is set as envrionment var to a personal access token with api scope in GitLab.

## Expected behavior

semantic-release uses the same git/ssl configuration for pushing tags.

## Environment

- **semantic-release** version: 15.9.5
- CI environment: local with --noCI switch
- Plugins used: changelog, npm, git, gitlab
- **semantic-release** configuration:
   ```
  "release": {
    "verifyConditions": [
      "@semantic-release/changelog",
      "@semantic-release/npm",
      "@semantic-release/git",
      {
        "path": "@semantic-release/gitlab",
        "gitlabUrl": "http://gitlabserver:10080"
      }
    ],
    "prepare": [
      {
        "path": "@semantic-release/changelog",
        "changelogFile": "CHANGELOG.md"
      },
      "@semantic-release/npm"
    ],
    "publish": [
      "@semantic-release/npm",
      {
        "path": "@semantic-release/gitlab",
        "gitlabUrl": "http://gitlabserver:10080"
      }
    ],
    "success": false,
    "fail": false,
    "branch": "develop",
    "pkgRoot": "dist",
    "repositoryUrl": "ssh://git@gitlabserver:10022/myGroup/myProject.git"
  }
```
- CI logs:
C:\Users\...\myProject [semantic-release ≡ +1 ~62 -7 ~]> npm run release -- --no-ci --branch=semantic-release --debug --dry-run

> myProject@1.0.0-semantically-released release C:\Users\...\myProject
> semantic-release "--no-ci" "--branch=semantic-release" "--debug" "--dry-run"

[16:02:46] [semantic-release] » i  Running semantic-release version 15.9.5
  semantic-release:config options values: { branch: 'semantic-release',
  semantic-release:config   repositoryUrl: 'ssh://git@gitlabserver:10022/myGroup/myProject.git',
  semantic-release:config   tagFormat: 'v${version}',
  semantic-release:config   verifyConditions:
  semantic-release:config    [ '@semantic-release/changelog',
  semantic-release:config      '@semantic-release/npm',
  semantic-release:config      '@semantic-release/git',
  semantic-release:config      { path: '@semantic-release/gitlab',
  semantic-release:config        gitlabUrl: 'http://gitlabserver:10080' } ],
  semantic-release:config   prepare:
  semantic-release:config    [ { path: '@semantic-release/changelog',
  semantic-release:config        changelogFile: 'CHANGELOG.md' },
  semantic-release:config      '@semantic-release/npm' ],
  semantic-release:config   publish:
  semantic-release:config    [ '@semantic-release/npm',
  semantic-release:config      { path: '@semantic-release/gitlab',
  semantic-release:config        gitlabUrl: 'http://gitlabserver:10080' } ],
  semantic-release:config   success: false,
  semantic-release:config   fail: false,
  semantic-release:config   pkgRoot: 'dist',
  semantic-release:config   _: [],
  semantic-release:config   ci: false,
  semantic-release:config   b: 'semantic-release',
  semantic-release:config   debug: true,
  semantic-release:config   'dry-run': true,
  semantic-release:config   d: true,
  semantic-release:config   dryRun: true,
  semantic-release:config   '$0': 'node_modules\\semantic-release\\bin\\semantic-release.js',
  semantic-release:config   noCi: true } +0ms
[16:02:47] [semantic-release] » √  Loaded plugin "verifyConditions" from "@semantic-release/changelog"
[16:02:47] [semantic-release] » √  Loaded plugin "verifyConditions" from "@semantic-release/npm"
[16:02:48] [semantic-release] » √  Loaded plugin "verifyConditions" from "@semantic-release/git"
[16:02:48] [semantic-release] » √  Loaded plugin "verifyConditions" from "@semantic-release/gitlab"
[16:02:48] [semantic-release] » √  Loaded plugin "analyzeCommits" from "@semantic-release/commit-analyzer"
[16:02:48] [semantic-release] » √  Loaded plugin "generateNotes" from "@semantic-release/release-notes-generator"
[16:02:48] [semantic-release] » √  Loaded plugin "prepare" from "@semantic-release/changelog"
[16:02:48] [semantic-release] » √  Loaded plugin "prepare" from "@semantic-release/npm"
[16:02:48] [semantic-release] » √  Loaded plugin "publish" from "@semantic-release/npm"
[16:02:48] [semantic-release] » √  Loaded plugin "publish" from "@semantic-release/gitlab"
[16:02:48] [semantic-release] » √  Run automated release from branch semantic-release
  semantic-release:git Error: Command failed: git push --dry-run ssh://git@gitlabserver:10022/myGroup/myProject.git HEAD:semantic-release
  semantic-release:git error: cannot spawn .git/hooks/pre-push: No such file or directory
  semantic-release:git error: waitpid for .git/hooks/pre-push failed: No child processes
  semantic-release:git error: failed to push some refs to 'ssh://git@gitlabserver:10022/myGroup/myProject.git'
  semantic-release:git
  semantic-release:git
  semantic-release:git     at makeError (C:\Users\...\myProject\node_modules\semantic-release\node_modules\execa\index.js:172:9)
  semantic-release:git     at Promise.all.then.arr (C:\Users\...\myProject\node_modules\semantic-release\node_modules\execa\index.js:277:16)
  semantic-release:git     at <anonymous>
  semantic-release:git     at process._tickCallback (internal/process/next_tick.js:188:7) +0ms
  semantic-release:git Error: Command failed: git push --dry-run https://[secure]@gitlabserver:10022/myGroup/myProject.git HEAD:semantic-release
  semantic-release:git fatal: unable to access 'https://[secure]@gitlabserver:10022/myGroup/myProject.git/': schannel: next InitializeSecurityContext failed: SEC_E_INVALID_TOKEN (0x80090308) - The token supplied to the function is invalid
  semantic-release:git
  semantic-release:git
  semantic-release:git     at makeError (C:\Users\...\myProject\node_modules\semantic-release\node_modules\execa\index.js:172:9)
  semantic-release:git     at Promise.all.then.arr (C:\Users\...\myProject\node_modules\semantic-release\node_modules\execa\index.js:277:16)
  semantic-release:git     at <anonymous>
  semantic-release:git     at process._tickCallback (internal/process/next_tick.js:188:7) +578ms
[16:02:51] [semantic-release] » ×  The command "git push --dry-run https://[secure]@gitlabserver:10022/myGroup/myProject.git HEAD:semantic-release" failed with the error message fatal: unable to access 'https://[secure]@gitlabserver:10022/myGroup/myProject.git/': schannel: next InitializeSecurityContext failed: SEC_E_INVALID_TOKEN (0x80090308) - The token supplied to the function is invalid
.
[16:02:51] [semantic-release] » ×  EGITNOPERMISSION The push permission to the Git repository is required.
semantic-release cannot push the version tag to the branch semantic-release on remote Git repository with URL https://[secure]@gitlabserver:10022/myGroup/myProject.git.

Please refer to the authentication configuration documentation (https://github.com/semantic-release/semantic-release/blob/caribou/docs/usage/ci-configuration.md#authentication) to configure the Git credentials on your CI
environment and make sure the repositoryUrl (https://github.com/semantic-release/semantic-release/blob/caribou/docs/usage/configuration.md#repositoryurl) is configured with a valid Git URL (https://git-scm.com/book/en/v2/Git-on-the-Server-The-Protocols).

{ SemanticReleaseError: The push permission to the Git repository is required.
    at module.exports (C:\Users\...\myProject\node_modules\semantic-release\lib\get-error.js:6:10)
    at run (C:\Users\...\myProject\node_modules\semantic-release\index.js:71:11)
    at <anonymous>
    at process._tickCallback (internal/process/next_tick.js:188:7)
  name: 'SemanticReleaseError',
  code: 'EGITNOPERMISSION',
  details: '**semantic-release** cannot push the version tag to the branch `semantic-release` on remote Git repository with URL `https://[secure]@gitlabserver:10022/myGroup/myProject.git`.\n\nPlease refer
to the [authentication configuration documentation](https://github.com/semantic-release/semantic-release/blob/caribou/docs/usage/ci-configuration.md#authentication) to configure the Git credentials on your CI environment
and make sure the [repositoryUrl](https://github.com/semantic-release/semantic-release/blob/caribou/docs/usage/configuration.md#repositoryurl) is configured with a [valid Git URL](https://git-scm.com/book/en/v2/Git-on-the-Server-The-Protocols).',
  semanticRelease: true }npm ERR! code ELIFECYCLE
npm ERR! errno 1
npm ERR! myProject@1.0.0-semantically-released release: `semantic-release "--no-ci" "--branch=semantic-release" "--debug" "--dry-run"`
npm ERR! Exit status 1
npm ERR!
npm ERR! Failed at the myProject@1.0.0-semantically-released release script.
npm ERR! This is probably not a problem with npm. There is likely additional logging output above.

npm ERR! A complete log of this run can be found in:
npm ERR!     C:\Users\...\AppData\Roaming\npm-cache\_logs\2018-08-08T14_02_51_133Z-debug.log
C:\Users\...\myProject [semantic-release ≡ +1 ~62 -7 ~]> git push --dry-run ssh://git@gitlabserver:10022/myGroup/myProject.git HEAD:semantic-release
Everything up-to-date
