🐛 Bug: Remove the old eslint.useFlatConfig from VS Code settings
### Bug Report Checklist

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

The `vscode-eslint` extension has supported ESLint flat config by default for a while. There's no need to include its old `esilnt.useFlatConfig` setting.

### Actual

It's still in `.vscode/settings.json`.

### Additional Info

Splitting this out of #1670.

💖
