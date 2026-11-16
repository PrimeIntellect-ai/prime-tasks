🐛 Bug: Label setups misses existing prefixed labels
### Bug Report Checklist

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/template-typescript-node-package/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

When a label such as `area: documentation` already exists in the repo, `hydrateRepositoryLabels` > `getExistingEquivalentLabel` should find that as an existing label.

### Actual

Because of the fun `.replace` logic, existing prefixed labels are actually missed...

### Additional Info

_No response_
