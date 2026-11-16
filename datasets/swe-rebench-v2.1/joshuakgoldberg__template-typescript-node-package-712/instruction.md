🐛 Bug: npx all-contributors should always be npx -y all-contributors-cli
### Bug Report Checklist

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/template-typescript-node-package/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

Commands that want to run all-contributors on the CLI should:

* `npx -y` so that it installs if needed (otherwise it hangs!)
* use `all-contributors-cli` specifically (otherwise it might no-op)

### Actual

Some places do 0 or 1 of those. 😞

### Additional Info

_No response_
