Using the same object in bumpFiles and packageFiles causes an error
**Describe the bug**
**Current behavior**

Using a config file like this:
```js
// .versionrc.js
const pom = {
  filename: 'pom.xml',
  updater: './path/to/custom-pom-updater'
}

module.exports = {
  bumpFiles: [pom],
  packageFiles: [pom]
}
```

Causes this error [HIDDEN]:
```
The "path" argument must be of type string. Received an instance of Object
```

**Expected behavior**
Using the same object twice should not cause an error.

**Environment**
- `standard-version` version(s): v8.0.2, master
- Node/npm version: all
- OS: all

### Additional contract requirements

- When the same object is used in both `packageFiles` and `bumpFiles`, the operation must not call `console.warn`.
