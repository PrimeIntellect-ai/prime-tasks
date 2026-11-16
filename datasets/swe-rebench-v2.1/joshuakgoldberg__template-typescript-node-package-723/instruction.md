🐛 Bug: Initialization in newly created repo: no git remotes found from gh label list --json name
### Bug Report Checklist

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/template-typescript-node-package/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

After running `npx template-typescript-node-package --skip-github-api`, you're suggested to run the `npx template-typescript-node-package --mode initialize` command in the new repo. That should pass.

### Actual

First I get this error about `no git remotes found`:

```plaintext
Error: Failed initializing GitHub repository
    at withSpinner (file:///Users/josh/.npm/_npx/b39740db704b12a5/node_modules/template-typescript-node-package/lib/shared/cli/spinners.js:16:11)
    at process.processTicksAndRejections (node:internal/process/task_queues:95:5)
    at async initializeWithOptions (file:///Users/josh/.npm/_npx/b39740db704b12a5/node_modules/template-typescript-node-package/lib/initialize/initializeWithOptions.js:39:5)
    at async run (file:///Users/josh/.npm/_npx/b39740db704b12a5/node_modules/template-typescript-node-package/lib/initialize/index.js:11:7)
    at async runOrRestore (file:///Users/josh/.npm/_npx/b39740db704b12a5/node_modules/template-typescript-node-package/lib/shared/runOrRestore.js:7:5)
    at async Object.initialize (file:///Users/josh/.npm/_npx/b39740db704b12a5/node_modules/template-typescript-node-package/lib/initialize/index.js:9:10)
    at async bin (file:///Users/josh/.npm/_npx/b39740db704b12a5/node_modules/template-typescript-node-package/lib/bin/index.js:47:10)
    at async file:///Users/josh/.npm/_npx/b39740db704b12a5/node_modules/template-typescript-node-package/bin/index.js:4:20 {
  [cause]: Error: Command failed with exit code 1: gh label list --json name
  no git remotes found
      at makeError (file:///Users/josh/.npm/_npx/b39740db704b12a5/node_modules/execa/lib/error.js:60:11)
      at handlePromise (file:///Users/josh/.npm/_npx/b39740db704b12a5/node_modules/execa/index.js:124:26)
      at process.processTicksAndRejections (node:internal/process/task_queues:95:5)
      at async initializeRepositoryLabels (file:///Users/josh/.npm/_npx/b39740db704b12a5/node_modules/template-typescript-node-package/lib/steps/initializeGitHubRepository/labels/initializeRepositoryLabels.js:7:6)
      at async initializeGitHubRepository (file:///Users/josh/.npm/_npx/b39740db704b12a5/node_modules/template-typescript-node-package/lib/steps/initializeGitHubRepository/index.js:6:3)
      at async file:///Users/josh/.npm/_npx/b39740db704b12a5/node_modules/template-typescript-node-package/lib/initialize/initializeWithOptions.js:40:7
      at async withSpinner (file:///Users/josh/.npm/_npx/b39740db704b12a5/node_modules/template-typescript-node-package/lib/shared/cli/spinners.js:11:20)
      at async initializeWithOptions (file:///Users/josh/.npm/_npx/b39740db704b12a5/node_modules/template-typescript-node-package/lib/initialize/initializeWithOptions.js:39:5)
      at async run (file:///Users/josh/.npm/_npx/b39740db704b12a5/node_modules/template-typescript-node-package/lib/initialize/index.js:11:7)
      at async runOrRestore (file:///Users/josh/.npm/_npx/b39740db704b12a5/node_modules/template-typescript-node-package/lib/shared/runOrRestore.js:7:5) {
    shortMessage: 'Command failed with exit code 1: gh label list --json name',
    command: 'gh label list --json name',
    escapedCommand: 'gh label list --json name',
    exitCode: 1,
    signal: undefined,
    signalDescription: undefined,
    stdout: '',
    stderr: 'no git remotes found',
    cwd: '/Users/josh/repos/temp/testing-cta-6',
    failed: true,
    timedOut: false,
    isCanceled: false,
    killed: false
  }
}
```

### Additional Info

_No response_

### Additional contract requirements

- Add a public function `createRerunSuggestion(mode: Mode, options: Options): string` in `src/create/createRerunSuggestion.ts`. It returns a single `npx template-typescript-node-package --mode <mode> ...` command string that reflects the supplied options.
- The `Options` type in `src/shared/types.ts` exposes the GitHub-API-skip setting as `skipGitHubApi` (replacing `skipApi`).
- Only truthy option entries are rendered. Each option key is mapped to its original CLI argument name (for example `skipGitHubApi` maps to `--skip-github-api`). Arguments appear in the order of their entries in `options`, and string values containing spaces are wrapped in double quotes.
- When a project is created without GitHub API access, the suggested command for initializing the new repository must not carry over the GitHub-API-skip setting.
