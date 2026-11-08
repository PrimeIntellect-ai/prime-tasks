`ember try:reset` with workspaces
I've tried running `ember try:reset` within a monorepo with yarn workspaces and I'm seeing the following error

```
TypeError: Cannot read property 'map' of undefined
/node_modules/ember-try/lib/dependency-manager-adapters/workspace.js:90:43
/node_modules/ember-try/lib/utils/scenario-manager.js:40:25
...
```

It looks like `this._packageAdapters` is `undefined`?

https://github.com/ember-cli/ember-try/blob/aa4e3fff85b538f3b1aa77b00af0add6bc7d6f94/lib/dependency-manager-adapters/workspace.js#L88-L90

It looks like the package adapters are initialised in `setup()`

https://github.com/ember-cli/ember-try/blob/aa4e3fff85b538f3b1aa77b00af0add6bc7d6f94/lib/dependency-manager-adapters/workspace.js#L52-L60

In the tests `setup()` is run before `cleanup()`, so either the tests are assuming `setup()` is run first and it isn't, [HIDDEN]

https://github.com/ember-cli/ember-try/blob/aa4e3fff85b538f3b1aa77b00af0add6bc7d6f94/test/dependency-manager-adapters/workspace-adapter-test.js#L210-L219

I can put together a PR, but I'm still figuring out what order things run in..

### Additional contract requirements

- For Yarn workspaces, `ember try:reset` must succeed when setup has not run and restore the backed-up workspace `package.json` and dependency files.
