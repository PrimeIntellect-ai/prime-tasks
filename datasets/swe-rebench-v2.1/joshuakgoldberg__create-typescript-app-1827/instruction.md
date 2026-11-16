🐛 Bug: Default usage receives undefined repository
### Bug Report Checklist

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

When creating a new repo with `npx create typescript-app` without an explicit `--repository`, the inferred `usage` option should factor in whatever `repository` option is prompted.

### Actual

It's being printed as `undefined`.

### Additional Info

💖

### Additional contract requirements

- `createOptionDefaults(promptedOptions?)` in `src/shared/options/createOptionDefaults/index.ts` exposes a `repository()` method that resolves to the first defined value among `promptedOptions.repository`, the Git remote name, the package name, and `promptedOptions.directory`.
- `readDefaultsFromReadme(readme, repository)` in `src/shared/options/createOptionDefaults/readDefaultsFromReadme.ts` accepts a `readme` function that resolves to the README text and a `repository` function that resolves to the repository name (or `undefined`). It returns an object exposing `logo()`, `title()`, and `usage()` methods.
- `logo()` resolves to the first image's source and, when available, its dimensions, or `undefined` when no suitable image is found.
- `title()` resolves to the text of the first Markdown (`# ...`) or HTML (`<h1>...</h1>`) heading, or `undefined` when no heading exists.
- `usage()` resolves to the usage section extracted from the README when one is present; otherwise it resolves to a sample snippet that uses the resolved repository name. When the repository resolves to `test-repository`, the sample snippet is exactly:

```shell
npm i test-repository
```
```ts
import { greet } from "test-repository";

greet("Hello, world! 💖");
```
