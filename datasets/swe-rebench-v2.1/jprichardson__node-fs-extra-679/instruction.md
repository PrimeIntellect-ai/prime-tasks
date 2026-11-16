[8.0.0] RangeError: Maximum call stack size exceeded at moveSync
<!-- First ensure you installed the latest version of fs-extra -->
<!-- If your bug still exists please fill out the following information if it applies to your issue: -->
- **Operating System:**
Windows [Version 10.0.17763.475]
- **Node.js version:**
v11.14.0
- **`fs-extra` version:**
v8.0.0

In the v7.0.1 is working fine!

```js
// Move
paths.forEach(path => (
  fs.moveSync(`${src}/${path}`, `${dest}${applyConfig(path, config)}`, { overwrite: true })
));
```

`(node:5924) UnhandledPromiseRejectionWarning: RangeError: Maximum call stack size exceeded
    at isPathSeparator (path.js:38:25)
    at Object.resolve (path.js:169:13)
    at Object.toNamespacedPath (path.js:555:32)
    at Object.statSync (fs.js:869:41)
    at checkParentPathsSync (C:\Users\johne\Documents\Elaniin Tech Company\elaniin-cli\node_modules\fs-extra\lib\util\stat.js:143:21)
    at checkParentPathsSync (C:\Users\johne\Documents\Elaniin Tech Company\elaniin-cli\node_modules\fs-extra\lib\util\stat.js:154:10)
    at checkParentPathsSync (C:\Users\johne\Documents\Elaniin Tech Company\elaniin-cli\node_modules\fs-extra\lib\util\stat.js:154:10)
    at checkParentPathsSync (C:\Users\johne\Documents\Elaniin Tech Company\elaniin-cli\node_modules\fs-extra\lib\util\stat.js:154:10)
    at checkParentPathsSync (C:\Users\johne\Documents\Elaniin Tech Company\elaniin-cli\node_modules\fs-extra\lib\util\stat.js:154:10)
    at checkParentPathsSync (C:\Users\johne\Documents\Elaniin Tech Company\elaniin-cli\node_modules\fs-extra\lib\util\stat.js:154:10)
    at checkParentPathsSync (C:\Users\johne\Documents\Elaniin Tech Company\elaniin-cli\node_modules\fs-extra\lib\util\stat.js:154:10)
    at checkParentPathsSync (C:\Users\johne\Documents\Elaniin Tech Company\elaniin-cli\node_modules\fs-extra\lib\util\stat.js:154:10)
    at checkParentPathsSync (C:\Users\johne\Documents\Elaniin Tech Company\elaniin-cli\node_modules\fs-extra\lib\util\stat.js:154:10)
    at checkParentPathsSync (C:\Users\johne\Documents\Elaniin Tech Company\elaniin-cli\node_modules\fs-extra\lib\util\stat.js:154:10)
    at checkParentPathsSync (C:\Users\johne\Documents\Elaniin Tech Company\elaniin-cli\node_modules\fs-extra\lib\util\stat.js:154:10)
    at checkParentPathsSync (C:\Users\johne\Documents\Elaniin Tech Company\elaniin-cli\node_modules\fs-extra\lib\util\stat.js:154:10)`
