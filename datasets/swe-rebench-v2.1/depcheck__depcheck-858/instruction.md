Short name for Jest `testEnvironment` doesn't seem to be recognised
### Bug Description

Jest special supports short names for runners and watch plugins, but not for the test environment https://github.com/depcheck/depcheck/blob/77fe0e2d092bdc8b97b65e37955f59be8a436d19/src/special/jest.js#L69-L75

### Code snippets

Where the dependency is used:

```
// jest.config.js
testEnvironment: 'jsdom',
```

Where the dependency is listed in package.json:

```
// devDependencies
"jest-environment-jsdom": "^29.6.3",
```

### Versions

- `node -v`: 18.17.0
- `npm -v`: 9.6.7
- `depcheck --version`: 1.4.7

### Extra info

Any extra info you want to include. Thank you for the bug report!

BONUS POINTS: If you wish to help us debug further, the `depcheck --json` option will show more information. Check [here in the README](https://github.com/depcheck/depcheck#example) for documentation on json output.
