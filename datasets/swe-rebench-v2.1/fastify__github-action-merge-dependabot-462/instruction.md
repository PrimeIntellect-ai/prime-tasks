Major version update is auto-merged with target set to minor
### Prerequisites

- [X] I have written a descriptive issue title
- [X] I have searched existing issues to ensure the bug has not already been reported


### Fastify version

3.x.x

### Plugin version

_No response_

### Node.js version

18.x

### Operating system

Linux

### Operating system version (i.e. 20.04, 11.3, 10)

20

### Description

This is similar but not identical to the existing issue https://github.com/fastify/github-action-merge-dependabot/issues/166. I am using the v3 action in my project workflow and the target is set to `minor`.

I notice that dependabot is able to create a PR with a minor update for a dependency and a major update for its ancestor dependency, like

<img width="926" alt="Screenshot 2023-07-06 at 8 51 16 AM" src="https://github.com/fastify/github-action-merge-dependabot/assets/1726265/c59cc703-e5b9-4241-b3e0-486bf9d1437a">

It is expected that this action would ignore this PR because of the major bump. However, as the screenshot shows, the action actually merges the PR automatically. I wonder if it is an edge case for the action.

### Steps to Reproduce

This is from a private repository so I cannot share the PR but code snippet. It is a nodejs (v18) application using the [nestjs](https://nestjs.com) (v8) framework.

Here is the workflow configuration I am using

``` yaml
  automerge:
    if: ${{ github.event_name == 'pull_request' }}
    # it requires test to finish first
    needs: test
    runs-on: ubuntu-latest
    permissions:
      pull-requests: write
      contents: write
    steps:
      - uses: fastify/github-action-merge-dependabot@v3
        with:
          target: minor
```

and the PR tends to change the `package.json`, which is not desired

<img width="1450" alt="Screenshot 2023-07-06 at 9 06 12 AM" src="https://github.com/fastify/github-action-merge-dependabot/assets/1726265/702c53ae-fb7c-4cb4-88c8-ca2522b5abf5">

Here is the raw log of the action execution.

```
2023-07-05T21:12:08.1613869Z Requested labels: ubuntu-latest
2023-07-05T21:12:08.1614157Z Job defined at: my-repo/.github/workflows/main.yaml@refs/pull/410/merge
2023-07-05T21:12:08.1614273Z Waiting for a runner to pick up this job...
2023-07-05T21:12:08.3650798Z Job is waiting for a hosted runner to come online.
2023-07-05T21:12:11.3016777Z Job is about to start running on the hosted runner: GitHub Actions 2 (hosted)
2023-07-05T21:12:14.0002294Z Current runner version: '2.305.0'
2023-07-05T21:12:14.0029874Z ##[group]Operating System
2023-07-05T21:12:14.0030526Z Ubuntu
2023-07-05T21:12:14.0030824Z 22.04.2
2023-07-05T21:12:14.0031068Z LTS
2023-07-05T21:12:14.0031390Z ##[endgroup]
2023-07-05T21:12:14.0031760Z ##[group]Runner Image
2023-07-05T21:12:14.0032088Z Image: ubuntu-22.04
2023-07-05T21:12:14.0032410Z Version: 20230702.1.0
2023-07-05T21:12:14.0032931Z Included Software: https://github.com/actions/runner-images/blob/ubuntu22/20230702.1/images/linux/Ubuntu2204-Readme.md
2023-07-05T21:12:14.0033642Z Image Release: https://github.com/actions/runner-images/releases/tag/ubuntu22%2F20230702.1
2023-07-05T21:12:14.0034091Z ##[endgroup]
2023-07-05T21:12:14.0034451Z ##[group]Runner Image Provisioner
2023-07-05T21:12:14.0034803Z 2.0.238.1
2023-07-05T21:12:14.0035064Z ##[endgroup]
2023-07-05T21:12:14.0035813Z ##[group]GITHUB_TOKEN Permissions
2023-07-05T21:12:14.0036388Z Contents: write
2023-07-05T21:12:14.0036671Z Metadata: read
2023-07-05T21:12:14.0037211Z PullRequests: write
2023-07-05T21:12:14.0037652Z ##[endgroup]
2023-07-05T21:12:14.0041370Z Secret source: Dependabot
2023-07-05T21:12:14.0041892Z Prepare workflow directory
2023-07-05T21:12:14.0804118Z Prepare all required actions
2023-07-05T21:12:14.0997236Z Getting action download info
2023-07-05T21:12:14.4378869Z Download action repository 'fastify/github-action-merge-dependabot@v3' (SHA:d37100b180dfd816bb1d7e4fbb544b3c734957a1)
2023-07-05T21:12:15.3413799Z Getting action download info
2023-07-05T21:12:15.6058229Z Download action repository 'dependabot/fetch-metadata@v1' (SHA:c9c4182bf1b97f5224aee3906fd373f6b61b4526)
2023-07-05T21:12:16.4253308Z Download action repository 'actions/github-script@v6' (SHA:d7906e4ad0b1822421a7e6a35d5ca353c962f410)
2023-07-05T21:12:17.4715313Z Complete job name: automerge
2023-07-05T21:12:17.5799012Z ##[group]Run fastify/github-action-merge-dependabot@v3
2023-07-05T21:12:17.5799336Z with:
2023-07-05T21:12:17.5799533Z   target: minor
2023-07-05T21:12:17.5800018Z   github-token: ***
2023-07-05T21:12:17.5800262Z   approve-only: false
2023-07-05T21:12:17.5800486Z   merge-method: squash
2023-07-05T21:12:17.5800720Z   use-github-auto-merge: false
2023-07-05T21:12:17.5800973Z   skip-commit-verification: false
2023-07-05T21:12:17.5801224Z   skip-verification: false
2023-07-05T21:12:17.5801440Z ##[endgroup]
2023-07-05T21:12:17.6077193Z ##[group]Run dependabot/fetch-metadata@v1
2023-07-05T21:12:17.6077464Z with:
2023-07-05T21:12:17.6077697Z   skip-commit-verification: false
2023-07-05T21:12:17.6077951Z   skip-verification: false
2023-07-05T21:12:17.6078389Z   github-token: ***
2023-07-05T21:12:17.6078598Z ##[endgroup]
2023-07-05T21:12:18.3223450Z Parsing Dependabot metadata
2023-07-05T21:12:18.3334099Z ##[group]Outputting metadata for 2 updated dependencies
2023-07-05T21:12:18.3334736Z outputs.dependency-names: webpack, @nestjs/cli
2023-07-05T21:12:18.3335124Z outputs.dependency-type: direct:development
2023-07-05T21:12:18.3335447Z outputs.update-type: null
2023-07-05T21:12:18.3335830Z outputs.directory: /webpack-and-nestjs
2023-07-05T21:12:18.3336198Z outputs.package-ecosystem: npm_and_yarn
2023-07-05T21:12:18.3336510Z outputs.target-branch: master
2023-07-05T21:12:18.3336836Z outputs.previous-version:
2023-07-05T21:12:18.3337142Z outputs.new-version:
2023-07-05T21:12:18.3337449Z outputs.compatibility-score: 0
2023-07-05T21:12:18.3337918Z outputs.maintainer-changes: true
2023-07-05T21:12:18.3338208Z outputs.dependency-group:
2023-07-05T21:12:18.3338482Z outputs.alert-state:
2023-07-05T21:12:18.3338735Z outputs.ghsa-id:
2023-07-05T21:12:18.3338957Z outputs.cvss: 0
2023-07-05T21:12:18.3339432Z ##[endgroup]
2023-07-05T21:12:18.3749864Z ##[group]Run actions/github-script@v6
2023-07-05T21:12:18.3750109Z with:
2023-07-05T21:12:18.3750641Z   github-token: ***
2023-07-05T21:12:18.3751619Z   script: const script = require('/home/runner/work/_actions/fastify/github-action-merge-dependabot/v3/dist/index.js')
await script({
  github,
  context,
  inputs: {
  "target": "minor",
  "github-token": "***",
  "exclude": "",
  "approve-only": "false",
  "merge-method": "squash",
  "merge-comment": "",
  "use-github-auto-merge": "false",
  "pr-number": "",
  "skip-commit-verification": "false",
  "skip-verification": "false"
},
  dependabotMetadata: {
    updateType:  '',
    dependencyType:'direct:development',
    dependencyNames: 'webpack, @nestjs/cli',
  }
})

2023-07-05T21:12:18.3752699Z   debug: false
2023-07-05T21:12:18.3752915Z   user-agent: actions/github-script
2023-07-05T21:12:18.3753153Z   result-encoding: json
2023-07-05T21:12:18.3753357Z   retries: 0
2023-07-05T21:12:18.3753587Z   retry-exempt-status-codes: 400,401,403,404,422
2023-07-05T21:12:18.3753822Z ##[endgroup]
2023-07-05T21:12:29.4915673Z Dependabot merge completed
2023-07-05T21:12:29.5108532Z Cleaning up orphan processes
```


### Expected Behavior

_No response_
