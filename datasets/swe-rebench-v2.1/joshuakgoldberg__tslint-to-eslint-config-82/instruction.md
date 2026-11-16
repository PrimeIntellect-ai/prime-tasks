Wrap exec paths to configurations [HIDDEN]
### 🐛 Bug Report

-   `tslint-to-eslint-config` version: 0.1.7
-   ESLint version: N/A
-   Node version: N/A

#### Actual Behavior

If the path to a configuration file provided as a CLI has a space, the internal `exec` call will treat the portions of the path after the space as extra arguments. That's a crash.

#### Expected Behavior

Don't do that, please.

#### Reproduction

```shell
tslint-to-eslint-config --eslint "./path with spaces/.eslintrc.js"
```

### Additional contract requirements

- When a configuration file path supplied through the CLI contains spaces, it must be handled as one path rather than split into extra arguments, and the command must not crash as a result.
