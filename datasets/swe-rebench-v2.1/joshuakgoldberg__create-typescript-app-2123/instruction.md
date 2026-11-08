🐛 Bug: `blockPrettier` should also add `runBefore` Addon to scripts creation
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

If `blockPrettier` receives a `runBefore` Addon, it should be run before the created formatting script run:

https://github.com/JoshuaKGoldberg/create-typescript-app/blob/702a313987d17503eb4e032fc194d814eace7759/src/blocks/blockPrettier.ts#L107-L112

### Actual

It is not, per https://github.com/JoshuaKGoldberg/prettier-plugin-curly/pull/630/files#r2026901442.

### Additional Info

🎁
