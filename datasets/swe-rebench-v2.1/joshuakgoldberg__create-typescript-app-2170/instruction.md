🚀 Feature: Infer tsup.config.ts entries from disk
### Feature Request Checklist

- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Overview

Running `npx create-typescript-app` on a repo with existing `tsup.config.ts` customizations should read those in as Addons to `blockTSup`. That way `create-typescript-app.config.*` files won't need to explicitly describe them under `refinements`.

### Additional Info

https://github.com/JoshuaKGoldberg/package-json-validator/pull/178/files#diff-5b778358ef07c9914c10021cf98855c355bb26724b4a16956a714515b556f750R63-R67 is an example of `format` being specified.

🎁

### Additional contract requirements

- Add a public function `intakeFileDefineConfig(files: IntakeDirectory, filePath: (string | string[])[]): Record<string, unknown> | undefined` in `src/blocks/intake/intakeFileDefineConfig.ts`. It reads the config file at `filePath` from `files`, extracts the object literal passed to a `defineConfig(...)` call, parses it as JSON5, and returns the resulting plain object. It returns `undefined` when the file is missing, does not contain a valid `defineConfig` call, or its contents cannot be parsed.
- `blockTSup` gains an `intake` that reads `tsup.config.ts` and returns an object with the config's `entry` array and its other TSup properties, or `undefined` when the file is missing or does not contain a valid `defineConfig` call.
