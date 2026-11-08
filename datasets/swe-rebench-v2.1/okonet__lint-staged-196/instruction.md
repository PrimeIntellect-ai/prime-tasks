Support commands which throw error on `--` argument
Using certain tools (e.g. Flow v0.48.0: `flow focus-check`) will not run correctly if they don't understand/expect an argument `--`.

**Steps to reproduce**
1. `git init`
1. `npm init -y`
1. `yarn add lint-staged flow-bin@0.48.0`
1. `flow init`
1. `.lintstagedrc`:
    ```json
    {
      "*.js": ["flow focus-check"]
    }
    ```
1. `index.js`:
    ```js
    // @flow
    ```
1. `git add .`
1. `lint-staged`

**Actual result**
The `flow focus-check` command will fail via `lint-staged`

**Expected result**
The `flow focus-check` command should pass, like it does when being run externally like: `flow focus-check index.js`

### Additional contract requirements

- For non-npm commands, pass matched file paths without an intervening `--`; for example, `git add` must receive `['add', 'test.js']`.
