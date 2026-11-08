🐛 Bug: `options.bin` should have preceding `./` removed if present
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

Per https://docs.npmjs.com/cli/v11/configuring-npm/package-json#bin, the `bin` property in `package.json` doesn't need to start with `./`. It's cleaner not to, and not all other tools support a preceding `./`.

### Actual

No changes when run in transition mode right now. Example: https://github.com/JoshuaKGoldberg/github-sponsors-to-markdown/pull/749/files#diff-7ae45ad102eab3b6d7e7896acd08c427a9b25b346470d7bc6507b6481575d519R16

### Additional Info

🎁

### Additional contract requirements

- When an `options.bin` path starts with `./`, the resulting `options.bin` value omits that prefix. This applies to a string `options.bin` and to each path in an object `options.bin`. Paths without the prefix are unchanged.
