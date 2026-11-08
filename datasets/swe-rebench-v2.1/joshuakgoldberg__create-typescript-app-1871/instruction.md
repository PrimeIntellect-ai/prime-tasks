🐛 Bug: package.json bin has unnecessary ./ prefix
### Bug Report Checklist

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

`package.json`'s `bin` entry can be a path like `bin/index.js`. There doesn't need to be a `./` at the beginning.

### Actual

https://github.com/JoshuaKGoldberg/create-typescript-app/blob/91cb22b271d63b5e3324c9f17715ce6ae4480c6a/package.json#L16

### Additional Info

I bet this could be linted for...

💖

### Additional contract requirements

The leading `./` should be omitted from path values in `package.json` and generated commands, not just the `bin` entry. In particular:

- The generated `package.json`'s `main` field should be `lib/index.js`, not `./lib/index.js`.
- Generated Node run commands should be `node lib/index.js`, not `node ./lib/index.js`.
- The repository's own `package.json` should use `bin/index.js`, and its `initialize` script should use `tsx bin/index.js`.
