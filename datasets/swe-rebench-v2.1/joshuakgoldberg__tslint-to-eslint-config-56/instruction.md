Error: No merger for multiple output object-shorthand rule configurations
### 🐛 Bug Report

-   `tslint-to-eslint-config` version: 0.1.5
-   ESLint version: N/A
-   Node version: 12.X

```
object-literal-shorthand threw an error during conversion: Error: No merger for multiple output object-shorthand rule configurations.
    at exports.convertRules (C:\Users\Dioge\AppData\Roaming\npm-cache\_npx\2708\node_modules\tslint-to-eslint-config\src\rules\convertRules.js:39:67)
    at exports.convertConfig (C:\Users\Dioge\AppData\Roaming\npm-cache\_npx\2708\node_modules\tslint-to-eslint-config\src\conversion\convertConfig.js:9:48)
    at processTicksAndRejections (internal/process/task_queues.js:88:5)
    at async Object.exports.runCli (C:\Users\Dioge\AppData\Roaming\npm-cache\_npx\2708\node_modules\tslint-to-eslint-config\src\cli\runCli.js:23:18)
    at async Object.exports.main (C:\Users\Dioge\AppData\Roaming\npm-cache\_npx\2708\node_modules\tslint-to-eslint-config\src\cli\main.js:51:30).
```

### Additional contract requirements

Converting a TSLint configuration whose enabled rules produce multiple `object-shorthand` outputs must complete without reporting a no-merger error.
