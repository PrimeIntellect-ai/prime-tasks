Question: can i override a node's prefix via criteria ?
I would like to change the prefix or the href for specific nodes

### Summary

- I'm perfectly fine with how things work for code under version control and can add the URL to my gitlab instance in the configuration file under the `prefix` option BUT I would like to be able to link to node packages when the dependency type is npm

### Environment

<!--- Include as many details about the environment - when relevant for this issue.
  --->

- Version used: 14.1.1
- Node version: 18.17.0
- Operating System and version: alpine node
- Link to your project: <private>

### Additional contract requirements

- Add a public function `getURLForModule(pModule, pPrefix?)` exported from `src/report/utl/index.mjs`.
- `pModule` is a module/dependency object with a `source` string and an optional `dependencyTypes` array of strings.
- When `pModule.dependencyTypes` includes `"core"`, the function returns `https://nodejs.org/api/<corePackage>.html`, where `<corePackage>` is the first path segment of `pModule.source`.
- When `pModule.dependencyTypes` includes an entry that starts with `"npm"`, the function returns `https://www.npmjs.com/package/<packageName>`, where `<packageName>` is the package name from `pModule.source` (e.g. `node_modules/lodash/yadda/yadda.js` yields `lodash`, and `node_modules/@org/beep/index.js` yields `@org/beep`); when `pModule.source` is not under a `node_modules` directory the package name is empty.
- Otherwise, when a protocol-based `pPrefix` (e.g. one starting with `https://`) is provided, the function returns the prefix concatenated with `pModule.source`.
- Otherwise the function returns `pModule.source` unchanged.
- The DOT report links each module to the URL returned for it.
