🚀 Feature: Allow customizing ncc build entry point
### Feature Request Checklist

- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Overview

Coming over from https://github.com/JoshuaKGoldberg/release-it-action/pull/479/files#r2029276151: not every ncc-built project has the same `src/index.ts` entry point. They'll need to be customizable.

### Additional Info

🎁

### Additional contract requirements

Callers can customize the ncc build entry point with the `entry` property in the `blockNcc` add-on. The generated release build must use the supplied entry point. When `entry` is omitted, the build continues to use `src/index.ts`.
