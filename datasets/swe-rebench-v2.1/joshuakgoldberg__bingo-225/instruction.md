🐛 Bug: Inputs aren't told of offline mode
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/bingo/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

When `--offline` is true, input contexts should have that.

### Actual

Right now they don't:

https://github.com/JoshuaKGoldberg/create/blob/293e610b7353a63811a1c513c621e6ab31c0f756/packages/bingo/src/contexts/createSystemContext.ts#L30

Systems don't have an `offline` property.

### Additional Info

💝
