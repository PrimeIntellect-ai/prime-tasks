🐛 Bug: All Contributors table not created in setup mode
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

When running `npx create-typescript-app@beta` on a new repository, a `## Contributors` README section with a contributors table should be created.

### Actual

It isn't right now because there are no existing detected contributors.

https://github.com/JoshuaKGoldberg/create-typescript-app/blob/cec96c0fcbc65a8391e1b4b3a9cc11c090733944/src/blocks/blockAllContributors.ts#L25-L27

### Additional Info

Previously solved in 1.x: https://github.com/JoshuaKGoldberg/create-typescript-app/issues/676

🎁

### Additional contract requirements

- In setup mode, when `.all-contributorsrc` cannot be read, the base's `contributors` option resolves to the fallback contributor (the current GitHub user), so that the generated README's `## Contributors` section is created.
