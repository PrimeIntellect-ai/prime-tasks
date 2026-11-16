🐛 Bug: `no-redundant-files` crashes when `files` contains a wildcard and `main` field is present
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/eslint-plugin-package-json/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

Rule does not crash.

### Actual

`no-redundant-files` crashes when `files` contains a wildcard like `*.d.ts` and `main` field is present.

Minimal reproduction: https://stackblitz.com/edit/vitejs-vite-cczf3mgu

Real-world example: I'm testing my ESLint config on various public repositories, and I found this rule crashing on [this package.json](https://github.com/h3js/crossws/blob/main/package.json).

### Additional Info

Full error message:

```
Oops! Something went wrong! :(

ESLint: 9.27.0

SyntaxError: Invalid regular expression: /^(./)?*.d.ts$/i: Nothing to repeat
Occurred while linting C:\**\package.json:1
Rule: "package-json/no-redundant-files"
    at new RegExp (<anonymous>)
    at getCachedLocalFileRegex (C:\**\node_modules\.pnpm\eslint-plugin-package-json@_94d8e15049f2dddc0262660eae0dce2c\node_modules\eslint-plugin-package-json\lib\rules\no-redundant-files.js:40:13)
```

### Additional contract requirements

- Wildcard patterns in `files` must not cause `no-redundant-files` to report a redundant entry, even when a pattern matches a path named by `main` or `bin`.
