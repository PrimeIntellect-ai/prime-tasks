🐛 Bug: `--exclude-lint-md` does not exclude extension from `extensions.json`
### Bug Report Checklist

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

Using the `--exclude-lint-md` flag I would expect `"DavidAnson.vscode-markdownlint",` to not be included in `extensions.json`.

### Actual

But it is - probably because of this code: https://github.com/JoshuaKGoldberg/create-typescript-app/blob/0ff914cb7d87b79dcc153dce59a2de992899f914/src/steps/writing/creation/dotVSCode.ts#L9

Is this intentional?

### Additional Info

_No response_
