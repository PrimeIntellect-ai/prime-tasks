🛠 Tooling: replace strip-ansi package with node's stripVTControlCharacters
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/TypeStat/issues?q=is%3Aissue) and found none that matched my issue.

### Overview

We could replace `strip-ansi` package with node's `stripVTControlCharacters`. strip-ansi is used only in one place (`createProcessOutput.ts`), so it should be easy task.

### Additional Info

_No response_

### Additional contract requirements

- Process-output sanitization must use Node's `stripVTControlCharacters` (from the built-in `util` module) in place of the `strip-ansi` package.
- The `strip-ansi` package must no longer be a runtime dependency of the project.
