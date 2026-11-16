🐛 Bug: package.json removes existing peerDependencies, peerDependenciesMeta
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

`npx create-typescript-app` on a repo that has those properties in its `package.json` should preserve those properties.

### Actual

Running on https://github.com/JoshuaKGoldberg/eslint-fix-utils/tree/83793cf033a859933e691f51e03a79e8d3e81e7c removes them, for some reason.

### Additional Info

🎁
