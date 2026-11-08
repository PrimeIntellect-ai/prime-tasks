RangeError: path should be a `path.relative()`d string when saving the user stylesheet (`styles.less`) in Atom with Prettier on Save enabled
<!--
Before you post an issue, please ensure that your issue is not with the
[prettier](https://github.com/prettier/prettier) or
[prettier-eslint](https://github.com/prettier/prettier-eslint) packages. This is just the
atom plugin that calls these packages under the hood.

Describe your issue here with as many details as possible
-->

<!--
Paste the output of the `Prettier: Debug` command below.
Protip: you can use a <details> tag to hide or show really large elements.

For example:
<details>
  A really long text
</details>
-->

When saving the user stylesheet (`styles.less`) in Atom with Prettier on Save enabled, this error pops up:

```
RangeError: path should be a `path.relative()`d string, but got "/Users/sompylasar/.atom/styles.less"
    at throwError (/Users/sompylasar/.atom/packages/prettier-atom/node_modules/ignore/index.js:354:9)
    at checkPath (/Users/sompylasar/.atom/packages/prettier-atom/node_modules/ignore/index.js:375:12)
    at Ignore._test (/Users/sompylasar/.atom/packages/prettier-atom/node_modules/ignore/index.js:483:5)
    at Ignore.ignores (/Users/sompylasar/.atom/packages/prettier-atom/node_modules/ignore/index.js:518:17)
    at someGlobsMatchFilePath (/Users/sompylasar/.atom/packages/prettier-atom/dist/helpers/general.js:10:96)
    at _.flow.filePath (/Users/sompylasar/.atom/packages/prettier-atom/dist/formatOnSave/shouldFormatOnSave.js:30:101)
    at /Users/sompylasar/.atom/packages/prettier-atom/node_modules/lodash/lodash.min.js:49:144
    at n (/Users/sompylasar/.atom/packages/prettier-atom/node_modules/lodash/lodash.min.js:5:89)
    at /Users/sompylasar/.atom/packages/prettier-atom/node_modules/lodash/lodash.min.js:51:79
    at h (/Users/sompylasar/.atom/packages/prettier-atom/node_modules/lodash/lodash.min.js:7:166)
    at /Users/sompylasar/.atom/packages/prettier-atom/node_modules/lodash/lodash.min.js:51:56
    at n (/Users/sompylasar/.atom/packages/prettier-atom/node_modules/lodash/lodash.min.js:5:89)
    at /Users/sompylasar/.atom/packages/prettier-atom/node_modules/lodash/lodash.min.js:63:257
    at n (/Users/sompylasar/.atom/packages/prettier-atom/node_modules/lodash/lodash.min.js:5:89)
    at /Users/sompylasar/.atom/packages/prettier-atom/node_modules/lodash/lodash.min.js:51:79
    at u (/Users/sompylasar/.atom/packages/prettier-atom/node_modules/lodash/lodash.min.js:5:521)
    at /Users/sompylasar/.atom/packages/prettier-atom/node_modules/lodash/lodash.min.js:51:56
    at n (/Users/sompylasar/.atom/packages/prettier-atom/node_modules/lodash/lodash.min.js:5:89)
    at /Users/sompylasar/.atom/packages/prettier-atom/node_modules/lodash/lodash.min.js:63:257
    at n (/Users/sompylasar/.atom/packages/prettier-atom/node_modules/lodash/lodash.min.js:5:89)
    at /Users/sompylasar/.atom/packages/prettier-atom/node_modules/lodash/lodash.min.js:97:406
    at n (/Users/sompylasar/.atom/packages/prettier-atom/node_modules/lodash/lodash.min.js:5:89)
    at /Users/sompylasar/.atom/packages/prettier-atom/node_modules/lodash/lodash.min.js:63:257
    at /Users/sompylasar/.atom/packages/prettier-atom/node_modules/lodash/lodash.min.js:49:144
    at attemptWithErrorNotification (/Users/sompylasar/.atom/packages/prettier-atom/dist/formatOnSave/index.js:14:84)
    at /Users/sompylasar/.atom/packages/prettier-atom/dist/atomInterface/index.js:59:13
    at Generator.next (<anonymous>)
    at step (/Users/sompylasar/.atom/packages/autocomplete-flow/node_modules/babel-runtime/helpers/asyncToGenerator.js:17:30)
    at /Users/sompylasar/.atom/packages/autocomplete-flow/node_modules/babel-runtime/helpers/asyncToGenerator.js:35:14
    at new Promise (<anonymous>)
    at new F (/Users/sompylasar/.atom/packages/autocomplete-flow/node_modules/core-js/library/modules/_export.js:36:28)
    at /Users/sompylasar/.atom/packages/autocomplete-flow/node_modules/babel-runtime/helpers/asyncToGenerator.js:14:12
    at attemptWithErrorNotification (/Users/sompylasar/.atom/packages/prettier-atom/dist/atomInterface/index.js:67:17)
    at safeFormatOnSaveIfAppropriate (/Users/sompylasar/.atom/packages/prettier-atom/dist/formatOnSave/index.js:14:49)
    at /Users/sompylasar/.atom/packages/prettier-atom/dist/main.js:38:23
    at Generator.next (<anonymous>)
    at step (/Users/sompylasar/.atom/packages/autocomplete-flow/node_modules/babel-runtime/helpers/asyncToGenerator.js:17:30)
    at /Users/sompylasar/.atom/packages/autocomplete-flow/node_modules/babel-runtime/helpers/asyncToGenerator.js:35:14
    at new Promise (<anonymous>)
    at new F (/Users/sompylasar/.atom/packages/autocomplete-flow/node_modules/core-js/library/modules/_export.js:36:28)
    at /Users/sompylasar/.atom/packages/autocomplete-flow/node_modules/babel-runtime/helpers/asyncToGenerator.js:14:12
    at lazyFormatOnSave (/Users/sompylasar/.atom/packages/prettier-atom/dist/main.js:42:17)
    at subscriptions.add.editor.getBuffer.onWillSave (/Users/sompylasar/.atom/packages/prettier-atom/dist/main.js:111:119)
    at Function.simpleDispatch (/Applications/Atom.app/Contents/Resources/app/static/<embedded>:11:1190583)
    at /Applications/Atom.app/Contents/Resources/app/static/<embedded>:11:1192208
    at Array.map (<anonymous>)
    at Emitter.emitAsync (/Applications/Atom.app/Contents/Resources/app/static/<embedded>:11:1192171)
    at TextBuffer.saveTo (/Applications/Atom.app/Contents/Resources/app/static/<embedded>:11:496823)
```

`Prettier: Debug`
```
Atom version: 1.33.0
prettier-atom version: 0.56.0
prettier: bundled
prettier version: 1.15.2
prettier-eslint version: 8.8.2
prettier-atom configuration: {
  "formatOnSaveOptions": {
    "enabled": true,
    "excludedGlobs": [
      "*.json"
    ],
    "jsonScopes": [
      "source.json-"
    ],
    "showInStatusBar": true,
    "respectEslintignore": true,
    "whitelistedGlobs": [],
    "isDisabledIfNotInPackageJson": false,
    "isDisabledIfNoConfigFile": false
  },
  "prettierOptions": {
    "printWidth": 120,
    "singleQuote": true,
    "trailingComma": "all"
  },
  "useEslint": false,
  "useStylelint": false,
  "prettierEslintOptions": {
    "prettierLast": false
  }
}
```

### Additional contract requirements

- When Prettier on Save is enabled, saving a file whose Atom project-relative path is absolute must not raise the `RangeError` caused by passing an absolute path to glob matching.
