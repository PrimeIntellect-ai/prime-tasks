🐛 Bug:  At least one dependency name should be specified for removal after --mode initialization
### Bug Report Checklist

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/template-typescript-node-package/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

After fixing #722, we should pass with no errors.

### Actual

```plaintext
Error: Failed uninstalling initialization-only packages
    at withSpinner (file:///Users/josh/repos/template-typescript-node-package/lib/shared/cli/spinners.js:16:11)
    at process.processTicksAndRejections (node:internal/process/task_queues:95:5)
    at async initializeWithOptions (file:///Users/josh/repos/template-typescript-node-package/lib/initialize/initializeWithOptions.js:47:5)
    ... 2 lines matching cause stack trace ...
    at async Object.initialize (file:///Users/josh/repos/template-typescript-node-package/lib/initialize/index.js:9:10)
    at async bin (file:///Users/josh/repos/template-typescript-node-package/lib/bin/index.js:47:10)
    at async file:///Users/josh/repos/template-typescript-node-package/bin/index.js:4:20 {
  [cause]: Error: Command failed with exit code 1: pnpm remove
   ERR_PNPM_MUST_REMOVE_SOMETHING  At least one dependency name should be specified for removal
      at makeError (file:///Users/josh/repos/template-typescript-node-package/node_modules/.pnpm/execa@8.0.1/node_modules/execa/lib/error.js:60:11)
      at handlePromise (file:///Users/josh/repos/template-typescript-node-package/node_modules/.pnpm/execa@8.0.1/node_modules/execa/index.js:124:26)
      at process.processTicksAndRejections (node:internal/process/task_queues:95:5)
      at async removeDependencies (file:///Users/josh/repos/template-typescript-node-package/lib/shared/packages.js:9:3)
      at async uninstallPackages (file:///Users/josh/repos/template-typescript-node-package/lib/steps/uninstallPackages.js:9:3)
      at async withSpinner (file:///Users/josh/repos/template-typescript-node-package/lib/shared/cli/spinners.js:11:20)
      at async initializeWithOptions (file:///Users/josh/repos/template-typescript-node-package/lib/initialize/initializeWithOptions.js:47:5)
      at async run (file:///Users/josh/repos/template-typescript-node-package/lib/initialize/index.js:11:7)
      at async runOrRestore (file:///Users/josh/repos/template-typescript-node-package/lib/shared/runOrRestore.js:7:5)
      at async Object.initialize (file:///Users/josh/repos/template-typescript-node-package/lib/initialize/index.js:9:10) {
    shortMessage: 'Command failed with exit code 1: pnpm remove',
    command: 'pnpm remove',
    escapedCommand: 'pnpm remove',
    exitCode: 1,
    signal: undefined,
    signalDescription: undefined,
    stdout: ' ERR_PNPM_MUST_REMOVE_SOMETHING  At least one dependency name should be specified for removal',
    stderr: '',
    cwd: '/Users/josh/repos/temp/testing-cta-6',
    failed: true,
    timedOut: false,
    isCanceled: false,
    killed: false
  }
}
```



### Additional Info

😂 it never ends...

### Additional contract requirements

- During initialization, when none of the initialization-only packages are present, cleanup must not run a dependency-removal command without package names, so the reported pnpm error does not occur.
