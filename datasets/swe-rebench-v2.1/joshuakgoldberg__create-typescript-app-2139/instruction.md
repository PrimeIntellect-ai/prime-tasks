🐛 Bug: ESLint config groups should be deduplicated by comment
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

If two `rules` objects from `blockESLint`'s Addons have the same `comment`, they should be merged together. This will allow end-users to add to the default `// Stylistic concerns that don't interfere with Prettier` group.

### Actual

https://github.com/JoshuaKGoldberg/eslint-plugin-package-json/pull/993/files#r2027963553 shows that no such merging is done now.

### Additional Info

🎁
