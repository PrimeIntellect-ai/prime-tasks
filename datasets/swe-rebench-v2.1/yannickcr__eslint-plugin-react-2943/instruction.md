Warning: React version not specified when used with monorepo
I looked through the code for [version.js](https://github.com/yannickcr/eslint-plugin-react/blob/master/lib/util/version.js) and the [version test](https://github.com/yannickcr/eslint-plugin-react/blob/master/tests/util/version.js) so I believe this is a valid issue.

I am running eslint from a monorepo I've set up with lerna. One of the packages in the monorepo using react so I've only installed react-specific eslint plugins in that package. ie `eslint-plugin-react`, `eslint-plugin-react-hooks` etc

Using eslints [overrides feature](https://eslint.org/docs/user-guide/configuring#configuration-cascading-and-hierarchy) and running an `eslint` command from the _root_ (`./`) works picking up and overriding the root configuration when it finds a `eslintrc` in a sub package, however, when I've set my react version to `detect` from the react projects `.eslintrc` it throws this warning.

```bash
Warning: React version was set to "detect" in eslint-plugin-react settings, but the "react" package is not installed. Assuming latest React version for linting.
```

`react` _is_ installed and included in _that_ packages `/react-foo/package.json`. But in order to prevent this warning I would need to install `react` at the root package of the monorepo which isn't correct or desired.

Here is an example project hierarchy with the `.eslintrc` config overrides:

```bash
./
├── package.json            # react is not installed in this package
├── .eslintrc               # root lint config
├── packages/
|   └── react-foo/
|   |   ├── package.json    # react installed
|   |   ├── .eslintrc       # react-specific lint overrides
|   |   └── src/
|   |       └──  ...
|   └── not-react-foo/
|       ├── package.json
|       └── src/
|           └── ...
└── ...
```

[HIDDEN]

### Additional contract requirements

- When React version is set to `detect`, recognize the React version installed in the package associated with the file being linted, even when ESLint is launched from the monorepo root. Do not treat React as missing or issue the fallback warning when it is installed in that package.
