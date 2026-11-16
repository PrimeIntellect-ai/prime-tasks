Fails to read ESLint settings if packages haven't been installed
### 🐛 Bug Report

-   `tslint-to-eslint-config` version: 0.6.0
-   ESLint version: N/A
-   Node version: N/A

#### Actual Behavior

Logging the `eslint` loaded in `findOriginalConfigurations` gives:

```
 Error: Command failed: eslint --print-config "./.eslintrc.js"
  Error: Failed to load parser '@typescript-eslint/parser' declared in '.eslintrc.js': Cannot find module '@typescript-eslint/parser'
  Require stack:
  - C:\Code\sample-tslint-to-eslint-comment\.eslintrc.js
      at Function.Module._resolveFilename (internal/modules/cjs/loader.js:610:15)
      at Function.resolve (internal/modules/cjs/helpers.js:21:19)
      at Object.resolve (C:\Users\Dioge\AppData\Roaming\npm\node_modules\eslint\lib\shared\relative-module-resolver.js:44:50)
      at ConfigArrayFactory._loadParser (C:\Users\Dioge\AppData\Roaming\npm\node_modules\eslint\lib\cli-engine\config-array-factory.js:870:45)
      at ConfigArrayFactory._normalizeObjectConfigDataBody (C:\Users\Dioge\AppData\Roaming\npm\node_modules\eslint\lib\cli-engine\config-array-factory.js:665:32)
      at _normalizeObjectConfigDataBody.next (<anonymous>)
      at ConfigArrayFactory._normalizeObjectConfigData (C:\Users\Dioge\AppData\Roaming\npm\node_modules\eslint\lib\cli-engine\config-array-factory.js:596:20)
      at _normalizeObjectConfigData.next (<anonymous>)
      at createConfigArray (C:\Users\Dioge\AppData\Roaming\npm\node_modules\eslint\lib\cli-engine\config-array-factory.js:340:25)
      at ConfigArrayFactory.loadInDirectory (C:\Users\Dioge\AppData\Roaming\npm\node_modules\eslint\lib\cli-engine\config-array-factory.js:433:16)
```

#### Expected Behavior

If there already exists an ESLint file, its packages may be required to determine which output rules are necessary (for example, in #412).

#### Reproduction

The second time `tslint-to-eslint-config` is run, it'll try to read the already-generated `.eslintrc.js`, and fail.

```
git clone https://github.com/KingDarBoja/sample-tslint-to-eslint-comment
cd sample-tslint-to-eslint-comment
tslint-to-eslint-config
tslint-to-eslint-config
```

### Additional contract requirements

When reading an existing ESLint configuration fails because a required package is not installed, the tool must report a configuration error (`ResultStatus.ConfigurationError`) instead of ignoring the failure.
