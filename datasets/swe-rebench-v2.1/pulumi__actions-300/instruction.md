Commenting the diff on Pull requests fails silently since v3.2.0
Since the release of v3.2.0 the pulumi action silently fails when putting the comment showing the diff.

## Steps to reproduce

1. using the following workflow yaml

```
    - uses: actions/setup-node@v2
      with:
        node-version: 16.x
    - name: Run Pulumi
      uses: pulumi/actions@v3
      with:
        command: preview
        comment-on-pr: true
        github-token: ${{ secrets.GITHUB_TOKEN }}
        stack-name: test
        diff: true
```

Expected: A comment showing the diff on the pull request
Actual:
```
(node:1908) UnhandledPromiseRejectionWarning: HttpError: Bad credentials
    at /home/runner/work/_actions/pulumi/actions/v3/webpack:/pulumi-github-action/node_modules/@octokit/request/dist-node/index.js:66:1
    at processTicksAndRejections (internal/process/task_queues.js:93:5)
(node:1908) UnhandledPromiseRejectionWarning: Unhandled promise rejection. This error originated either by throwing inside of an async function without a catch block, or by rejecting a promise which was not handled with .catch(). (rejection id: 1)
(node:1908) [DEP0018] DeprecationWarning: Unhandled promise rejections are deprecated. In the future, promise rejections that are not handled will terminate the Node.js process with a non-zero exit code.
```

Workaround: Downgrading to v3.1.0
```
   - name: Run Pulumi
      uses: pulumi/actions@v3.1.0
      with:
        command: preview
        comment-on-pr: true
        github-token: ${{ secrets.GITHUB_TOKEN }}
        stack-name: test
        diff: true
```
