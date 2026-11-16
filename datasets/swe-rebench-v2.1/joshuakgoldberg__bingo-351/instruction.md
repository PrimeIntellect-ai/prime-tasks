🐛 Bug: Writing file system should not always use Prettier
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/bingo/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

Templates should have full control over how their files are written. Bingo should not hardcode writing files formatted with Prettier or any other formatter.

### Actual

I think I'd done this for convenience a long time ago:

https://github.com/JoshuaKGoldberg/bingo/blob/293e610b7353a63811a1c513c621e6ab31c0f756/packages/bingo/src/runners/applyFilesToSystem.ts#L14-L24

### Additional Info

Causes https://github.com/JoshuaKGoldberg/create-typescript-app/issues/2177.

💝
