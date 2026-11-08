one-variable-per-declaration should output ruleArguments: ["never"]
# 🐛 Bug Report

-   `tslint-to-eslint-config` version: 0.2.9
-   ESLint version: 5.16.0
-   Node version: 12.X

#### Actual Behavior

`one-variable-per-declaration` outputs no rule arguments.

#### Expected Behavior

TSLint's `one-variable-per-declaration` is a subset of ESLint's `one-var`. `one-var` allows either style while `one-variable-per-declaration` only allows the `"never"` style.

#### Reproduction

`tslint.json`:
```json
{
    "rules": {
        "one-variable-per-declaration": true
    }
}
```
