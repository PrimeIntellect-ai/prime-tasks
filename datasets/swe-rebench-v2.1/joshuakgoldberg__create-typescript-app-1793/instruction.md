🐛 Bug: Don't offer to restore repository with --mode create
### Bug Report Checklist

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

When running `npx create-typescript-app --mode create`, if the CLI crashes for some reason, you should get the standard error message + call stack but shouldn't be offered to _"restore the repository to how it was"_. That offer doesn't make sense - the repository never existed to begin with!

### Actual

I had a bug in #1000 and got:

```plaintext
│
◇  ❌ Error initializing GitHub repository.
│
Error: Failed initializing GitHub repository
    at withSpinner (file:///Users/josh/repos/create-typescript-app/lib/shared/cli/spinners.js:16:11)
    at async createWithOptions (file:///Users/josh/repos/create-typescript-app/lib/create/createWithOptions.js:43:5)
    at async run (file:///Users/josh/repos/create-typescript-app/lib/create/index.js:31:34)
    at async runOrRestore (file:///Users/josh/repos/create-typescript-app/lib/shared/runOrRestore.js:7:5)
    at async Object.create (file:///Users/josh/repos/create-typescript-app/lib/create/index.js:29:11)
    at async bin (file:///Users/josh/repos/create-typescript-app/lib/bin/index.js:67:36)
    at async file:///Users/josh/repos/create-typescript-app/bin/index.js:4:20 {
  [cause]: RequestError [HttpError]: Not Found
      at /Users/josh/repos/create-typescript-app/node_modules/.pnpm/@octokit+request@8.1.0/node_modules/@octokit/request/dist-node/index.js:112:21
      at process.processTicksAndRejections (node:internal/process/task_queues:95:5)
      at async requestWithGraphqlErrorHandling (/Users/josh/repos/create-typescript-app/node_modules/.pnpm/@octokit+plugin-retry@6.0.0_@octokit+core@5.0.0/node_modules/@octokit/plugin-retry/dist-node/index.js:71:20)
      at async Job.doExecute (/Users/josh/repos/create-typescript-app/node_modules/.pnpm/bottleneck@2.19.5/node_modules/bottleneck/light.js:405:18) {
    status: 404,
    response: {
      url: 'https://api.github.com/repos/OWNER/REPO/labels',
      status: 404,
      headers: [Object],
      data: [Object]
    },
    request: {
      method: 'GET',
      url: 'https://api.github.com/repos/OWNER/REPO/labels',
      headers: [Object],
      request: [Object]
    }
  }
}
│
◆  Do you want to restore the repository to how it was?
│  ● Yes / ○ No
└
```

### Additional Info

_No response_
