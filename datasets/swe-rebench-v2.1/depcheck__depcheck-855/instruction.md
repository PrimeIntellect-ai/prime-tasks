Handle array `extends` in tsconfig
### Bug Description

The TSConfig parser pushes the whole `extends` value https://github.com/depcheck/depcheck/blob/77fe0e2d092bdc8b97b65e37955f59be8a436d19/src/parser/tsconfig.js#L24-L26

[HIDDEN]

### Code snippets

Where the dependency is used:

```
// a tsconfig.json file for a part of the project
{
  "extends": ["../../tsconfig.defaults.json", "@tsconfig/create-react-app"],
  ...
}
```

Where the dependency is listed in package.json:

```
    // dependencies
    "@tsconfig/create-react-app": "^1.0.3",
```

### Versions

- `node -v`: 18.17.0
- `npm -v`: 9.6.7
- `depcheck --version`: 1.4.7

### Extra info

Any extra info you want to include. Thank you for the bug report!

BONUS POINTS: If you wish to help us debug further, the `depcheck --json` option will show more information. Check [here in the README](https://github.com/depcheck/depcheck#example) for documentation on json output.

### Additional contract requirements

- When a TSConfig `extends` value is an array, each entry must be recognized independently as a dependency used by that TSConfig.
