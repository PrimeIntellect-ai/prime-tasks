Don't report an error if .vscode/settings.json doesn't exist
### 🐛 Bug Report

-   `tslint-to-eslint-config` version: 0.4.0
-   ESLint version: N/A
-   Node version: N/A

#### Actual Behavior

```
λ npx tslint-to-eslint-config
❌ 1 error running tslint-to-eslint: ❌
Error: ENOENT: no such file or directory, open 'path\to\dir\.vscode\settings.json'
```

#### Expected Behavior

If the project doesn't have the file, don't complain.

#### Reproduction

In a new empty directory:

```
npx eslint --init
npx tslint-to-eslint-config
```

### Additional contract requirements

- `findEditorConfiguration(dependencies, specifiedConfigPath)` is exported from `src/input/findEditorConfiguration.ts`. Its second argument is the editor configuration path supplied by the user, or `undefined` when none was supplied.
- `FindEditorConfigurationDependencies` (exported from `src/input/findEditorConfiguration.ts`) includes a `fileSystem` dependency exposing `fileExists(path: string): Promise<boolean>`, alongside the existing `importer`.
- When `specifiedConfigPath` is `undefined` and the default VS Code settings file does not exist, `findEditorConfiguration` resolves to `undefined`.
- When a file is explicitly requested but does not exist, `findEditorConfiguration` resolves to an object `{ configPath: string, result: Error }`.
- When a file exists and is successfully parsed, `findEditorConfiguration` resolves to an object `{ configPath: string, result: DeepPartial<EditorConfiguration> }`.
- When the importer returns an Error, `findEditorConfiguration` resolves to an object `{ configPath: string, result: Error }` containing that error.
