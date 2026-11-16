🐛 Bug: Repositories considered created while GitHub is still populating labels
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

Running `npx create-typescript-app@beta` with a logged-in `gh` user and valid data should not encounter any errors.

### Actual

I still sometimes see:

```plaintext
■  The repository-labels request failed. You should re-run it and fix its complaints.
│  HttpError: Validation Failed: {"resource":"Label","code":"already_exists","field":"name"} - https://docs.github.com/rest/issues/labels#create-a-label
│      at fetchWrapper (file:///Users/josh/repos/create-typescript-app/node_modules/.pnpm/@octokit+request@9.2.2/node_modules/@octokit/request/dist-bundle/index.js:122:11)
│      at process.processTicksAndRejections (node:internal/process/task_queues:105:5)
│      at async requestWithGraphqlErrorHandling (file:///Users/josh/repos/create-typescript-app/node_modules/.pnpm/@octokit+plugin-retry@7.1.4_@octokit+core@6.1.4/node_modules/@octokit/plugin-retry/dist-bundle/index.js:36:20)
│      at async Job.doExecute (/Users/josh/repos/create-typescript-app/node_modules/.pnpm/bottleneck@2.19.5/node_modules/bottleneck/light.js:405:18)
│
```

### Additional Info

This looks a lot like https://github.com/JoshuaKGoldberg/bingo/issues/243. My hunch is the fix in https://github.com/JoshuaKGoldberg/bingo/pull/244 didn't fully fix things: that labels are themselves made asynchronously, so just waiting for them to start to be populated isn't enough.

🎁

### Additional contract requirements

Repository setup must wait for asynchronous label population to settle; a short pause between label additions must not be treated as completion.
