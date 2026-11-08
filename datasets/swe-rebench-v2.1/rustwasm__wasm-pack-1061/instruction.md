Add type = "module" in package.json to support nodejs in bundler mode
## 💡 Feature description

When you build using the default "bundler" mode, it can *almost* run directly from nodejs, using nodejs's built in ESM support.

Unfortunately, the created package.json file is missing `"type": "module"`. Adding this to the created package.json not only fixes some bundler issues, but also makes nodejs understand the created package too:

foo.js:

```javascript
import {greet} from 'my_module'
greet()
```

```
$ node --experimental-wasm-modules foo.js
(node:414396) ExperimentalWarning: Importing Web Assembly modules is an experimental feature. This feature could change at any time
(Use `node --trace-warnings ...` to show where the warning was created)
Hello world!
```

### Additional contract requirements

- When building in the default "bundler" mode, the generated `package.json` must declare the package as an ES module by including `"type": "module"`.
- When building in the default "bundler" mode, the generated `package.json` must expose the entry-point JavaScript file through the `"main"` field, replacing the previous `"module"` field.
