The result resolved by 7.0.0 no longer includes package.json.
It breaks oxc-node: https://github.com/oxc-project/oxc-node/pull/116

In 6.0.0, the [`compiled.js`](https://github.com/oxc-project/oxc-node/blob/main/packages/integrate-module/src/index.ts#L14) was resolved: `Resolution { path: "/Users/brooklyn/workspace/github/oxc-node/packages/integrate-module-bundler/src/compiled.js", query: None, fragment: None, package_json: Some("/Users/brooklyn/workspace/github/oxc-node/packages/integrate-module-bundler/package.json") }`

In 7.0.0, the result is: `Resolution { path: "/Users/brooklyn/workspace/github/oxc-node/packages/integrate-module/src/compiled.js", query: None, fragment: None, package_json: None }`

Without a package.json, I can't determine whether a .js file is CommonJS or ESM.
