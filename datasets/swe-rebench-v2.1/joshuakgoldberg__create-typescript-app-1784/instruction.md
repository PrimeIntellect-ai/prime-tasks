🐛 Bug: Unnecessary default values in .all-contributorsrc files
### Bug Report Checklist

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

For config files like `.all-contributorsrc`, only settings that change from defaults should be declared. Anything that's `===` the default should be omitted.

### Actual

I'm pretty sure there are some redundant additions in the current [`.allcontributorsrc` per the docs](https://allcontributors.org/docs/en/bot/configuration). I'm looking at at least:

* `commmit`
* `commitConvention`
* `commitType` _(which doesn't exist on the docs?)_

### Additional Info

💖

### Additional contract requirements

- Serialize generated `.all-contributorsrc` content as compact JSON, with properties ordered as `badgeTemplate`, `contributors`, `contributorsSortAlphabetically`, `projectName`, and `projectOwner`.
