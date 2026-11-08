🐛 Bug: Script merging loses `silent` attributes on mixed-silence phases
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/bingo/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

If a phase contains both `silent` and non-`silent` scripts, they should preserve their `silent` attribute.

### Actual

Running `npx create-typescript-app@beta` on an existing repo:

```plaintext
◐  Running create-typescript-appError in script rm CONTRIBUTING.md ExecaError: Command failed with exit code 1: rm CONTRIBUTING.md

rm: CONTRIBUTING.md: No such file or directory
    at getFinalError (file:///Users/josh/repos/create-typescript-app/node_modules/.pnpm/execa@9.5.2/node_modules/execa/lib/return/final-error.js:6:9)
    at makeError (file:///Users/josh/repos/create-typescript-app/node_modules/.pnpm/execa@9.5.2/node_modules/execa/lib/return/result.js:108:16)
    at getAsyncResult (file:///Users/josh/repos/create-typescript-app/node_modules/.pnpm/execa@9.5.2/node_modules/execa/lib/methods/main-async.js:167:4)
    at handlePromise (file:///Users/josh/repos/create-typescript-app/node_modules/.pnpm/execa@9.5.2/node_modules/execa/lib/methods/main-async.js:150:17)
    at process.processTicksAndRejections (node:internal/process/task_queues:95:5)
    at async runCommand (file:///Users/josh/repos/create-typescript-app/node_modules/.pnpm/bingo@0.5.1/node_modules/bingo/lib/runners/applyScriptsToSystem.js:10:24)
    at async file:///Users/josh/repos/create-typescript-app/node_modules/.pnpm/bingo@0.5.1/node_modules/bingo/lib/runners/applyScriptsToSystem.js:22:17
    at async Promise.all (index 0)
    at async applyScriptsToSystem (file:///Users/josh/repos/create-typescript-app/node_modules/.pnpm/bingo@0.5.1/node_modules/bingo/lib/runners/applyScriptsToSystem.js:20:9)
    at async Promise.all (index 0) {
  shortMessage: 'Command failed with exit code 1: rm CONTRIBUTING.md',
  command: 'rm CONTRIBUTING.md',
  escapedCommand: 'rm CONTRIBUTING.md',
  cwd: '/Users/josh/repos/my-typescript-app',
  durationMs: 16.854666,
  failed: true,
  timedOut: false,
  isCanceled: false,
  isGracefullyCanceled: false,
  isTerminated: false,
  isMaxBuffer: false,
  isForcefullyTerminated: false,
  exitCode: 1,
  stdout: '',
  stderr: 'rm: CONTRIBUTING.md: No such file or directory',
  stdio: [ undefined, '', 'rm: CONTRIBUTING.md: No such file or directory' ],
  ipcOutput: [],
  pipedFrom: []
}
Error in script rm CODE_OF_CONDUCT.md ExecaError: Command failed with exit code 1: rm CODE_OF_CONDUCT.md
```

### Additional Info

💝
