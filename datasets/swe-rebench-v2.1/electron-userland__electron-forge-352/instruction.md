When running "start", app does not start when app version is not present
**Steps to reproduce**: in a working project, delete the "version" field in package.json.
**Steps to reproduce II**: import an existing project wich has no version field in package.json.

**Stack trace**:
```
Exception has occurred: TypeError
TypeError: Error processing argument at index 0, conversion failure from undefined
    at main (d:\dev\joint_examples\node_modules\electron-prebuilt-compile\src\es6-init.js:37:7)
    at Object.<anonymous> (d:\dev\joint_examples\node_modules\electron-prebuilt-compile\src\es6-init.js:48:1)
    at Object.<anonymous> (d:\dev\joint_examples\node_modules\electron-prebuilt-compile\lib\es6-init.js:61:3)
    at Module._compile (module.js:571:32)
    at Object.Module._extensions..js (module.js:580:10)
    at Module.load (module.js:488:32)
    at tryModuleLoad (module.js:447:12)
    at Function.Module._load (module.js:439:3)
    at loadApplicationPackage (d:\dev\joint_examples\node_modules\electron-prebuilt-compile\node_modules\electron\dist\resources\default_app.asar\main.js:283:12)
    at Object.<anonymous> (d:\dev\joint_examples\node_modules\electron-prebuilt-compile\node_modules\electron\dist\resources\default_app.asar\main.js:325:5)
```

### Additional contract requirements

When `start` is given a project whose `package.json` has no `version`, it must fail before spawning Electron and provide a clear diagnostic identifying the missing version. It must not leave the failure to Electron's downstream conversion error.
