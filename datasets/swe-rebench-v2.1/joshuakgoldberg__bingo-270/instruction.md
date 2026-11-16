🐛 Bug: Stratum templates should have access to options.prefix: string
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/bingo/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

All Stratum Templates have a `prefix` option automatically added. Blocks should therefore also have visibility into which preset is being run. This can be useful for, say, README.md blocks describing the block.

### Actual

No such `options.prefix` is available to Stratum Blocks right now.

### Additional Info

💝

### Additional contract requirements

The option automatically added to every Stratum Template's options, and made visible to Blocks, is named `preset` (a `string`). Blocks read it as `options.preset`. The `prefix` name used in the issue title and Expected section above refers to this same `preset` option.
