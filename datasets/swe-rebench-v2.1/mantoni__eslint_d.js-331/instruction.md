Specify path to eslint
Hello, thank you for your work on this project!

From the README:

>  If eslint is found in the current working directories node_modules folder, then this version of eslint is going to be used. Otherwise, the version of eslint that ships with eslint_d is used as a fallback.

Is there a way to specify the path to where `eslint` can be found?

We have many repos, all with the same ESLint configuration and rules.

Thus, we have a centralized repo that contains `node_modules/` with `eslint` and the custom rules.

Therefore, each project won't have a `node_modules/`  directory with `eslint`, and we don't want to fallback to the version of `eslint` that ships with `eslint_d`.

### Additional contract requirements

- Honor `ESLINT_D_ROOT` as the root directory containing the desired `node_modules/eslint` installation. When set, use that installation instead of falling back to the bundled ESLint.
