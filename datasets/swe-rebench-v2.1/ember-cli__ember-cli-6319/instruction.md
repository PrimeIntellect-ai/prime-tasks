Installing addons from blueprint fails: "Could not find addon"
When running `addAddonsToProject` in a blueprint:

```
installing ember-cli-zesty-app-base
  identical testem.js
  install addons ember-cli-eslint@^1.7.0, ember-cli-template-lint@^0.4.12, ember-concurrency@^0.7.8, ember-test-selectors@^0.0.3
Installed packages for tooling via npm.
Install failed. Could not find addon with name: ember-cli-eslint@^1.7.0
```

We have an Ember addon for installing other addons that is currently running into issues. The `afterInstall` hook in the blueprint looks a like this:

```js
  afterInstall: function() {
    var blueprint = this;
    var project = this.project;

    return blueprint.addAddonsToProject({
      packages: [
        { name: 'ember-cli-eslint', target: '^1.7.0' },
        { name: 'ember-cli-template-lint', target: '^0.4.12' },
        { name: 'ember-concurrency', target: '^0.7.8' },
        { name: 'ember-test-selectors', target: '^0.0.3' }
      ]
    }).then(function() {
      return blueprint.addPackagesToProject([
        { name: 'babel-eslint', target: '^6.1.2' },
        { name: 'ember-cli-deploy', target: '^0.6.4' },
      ])
    })
```

I can reproduce the issue with [this pared down addon](https://github.com/binhums/bug-add-addons-to-project).

This looks similar to #5880, but I believe it is distinct.

Verified against master, I have a potential fix incoming.

---

Output from `ember version --verbose && npm --version`:
```
ember-cli: 2.8.0
http_parser: 2.5.2
node: 4.4.5
v8: 4.5.103.35
uv: 1.8.0
zlib: 1.2.8
ares: 1.10.1-DEV
icu: 56.1
modules: 46
openssl: 1.0.2h
os: darwin x64
2.15.5
```

### Additional contract requirements

- `AddonInstallTask` is exported from `lib/tasks/addon-install`. Its constructor accepts an options object providing `ui`, `project`, and `NpmInstallTask` collaborators, and returns an instance whose `run` method can be invoked.
- `AddonInstallTask.run(options)` accepts an options object that may contain a `blueprintOptions` object with optional boolean `save` and `saveDev` properties.
- Addons installed by default are saved as development dependencies. When the blueprint requests saving as a regular dependency, addons are saved as regular dependencies instead.
- `run` returns a Promise that resolves after the npm install completes and the project's addons have been re-loaded.
