🐛 Bug: blockESLint's intake removes newlines in multi-line comments
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

Comments with multiple lines of `// ...` should be taken in as `\n`-separated strings in `blockESLint`'s `intake`.

### Actual

The `\n`s are being removed.

### Additional Info

Seen in the wild: https://github.com/JoshuaKGoldberg/package-json-validator/pull/191#discussion_r2033412701
