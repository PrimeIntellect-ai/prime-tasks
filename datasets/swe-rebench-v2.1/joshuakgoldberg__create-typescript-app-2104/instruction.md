🐛 Bug: `blockTypeScript` should print `compilerOptions` in alphabetical order
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

If a user provides explicit `compilerOption` Addons to `blockTypeScript`, then they should be merged in with existing compiler options in alphabetical order.

### Actual

https://github.com/JoshuaKGoldberg/package-json-validator/pull/178/files#diff-b55cdbef4907b7045f32cc5360d48d262cca5f94062e353089f189f4460039e0 shows that a provided `rewriteRelativeImportExtensions` is being placed at the end - after `t*` options.

### Additional Info

🎁
