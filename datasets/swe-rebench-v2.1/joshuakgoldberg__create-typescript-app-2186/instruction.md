🚀 Feature: Run build --no-dts before eslint-doc-generator in blockESLintPlugin
### Feature Request Checklist

- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Overview

Coming over from https://github.com/JoshuaKGoldberg/eslint-plugin-package-json/pull/993#discussion_r2032073911, `eslint-doc-generator` builds require having built source code first. We've resolved to have `blockESLintPlugin` run `pnpm build --no-dts` before `eslint-doc-generator` in its build task.

### Additional Info

🎁

Co-authored-by: @michaelfaith
