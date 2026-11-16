🚀 Feature: Infer tsconfig.json entries from disk
### Feature Request Checklist

- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Overview

Running `npx create-typescript-app` on a repo with existing `tsconfig.json` customizations should read those in as Addons to `blockTypeScript`. That way `create-typescript-app.config.*` files won't need to explicitly describe them under `refinements`.

### Additional Info

https://github.com/JoshuaKGoldberg/package-json-validator/pull/178/files#diff-5b778358ef07c9914c10021cf98855c355bb26724b4a16956a714515b556f750R68-R74 is an example of `compilerOptions` being specified.

🎁

### Additional contract requirements

- `blockTypeScript` reads the project's existing `tsconfig.json` when running its `intake`, so its `compilerOptions` are picked up as Addons without needing to be listed under `refinements`.
- The `intake` accepts an object with a `files` property mapping file paths to arrays of file-content strings.
- The `intake` returns `undefined` when `tsconfig.json` is absent, when its content parses to a falsy value, or when it does not contain a `compilerOptions` field.
- When `tsconfig.json` contains a `compilerOptions` field, the `intake` returns an object with a `compilerOptions` property containing those options.
