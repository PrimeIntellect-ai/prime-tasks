TypeScript configuration files can't have comments
### 🐛 Bug Report

-   `tslint-to-eslint-config` version: 0.1.8
-   ESLint version: N/A
-   Node version: N/A

#### Actual Behavior

If you've put non-JSON things in your `tsconfig.json`, such as comments, `tslint-to-eslint-config --typescript tsconfig.json` won't load the file. [HIDDEN]

#### Expected Behavior

TypeScript supports comments. We should too!

#### Reproduction

1. Create a `tsconfig.json` with comments in it
2. Run `tslint-to-eslint-config --typescript tsconfig.json`

### Additional contract requirements

- Loading a TypeScript configuration containing TypeScript-supported comments must succeed, and its settings must be available to the tool.
