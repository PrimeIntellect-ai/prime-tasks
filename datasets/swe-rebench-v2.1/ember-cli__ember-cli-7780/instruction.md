make lint:js run `eslint .` plus .eslintignore
https://github.com/ember-cli/ember-cli/pull/7769#issuecomment-382450832

```js
    "lint:js": "eslint ./*.js app blueprints config lib server tests",
```

```js
    "lint:js": "eslint .",
```

cc @rwjblue @dfreeman

### Additional contract requirements

Generated application and addon projects should keep `lint:js` as a root-wide `eslint .` command. Its `.eslintignore` policy should prevent linting blueprint template sources (`blueprints/*/files/`), vendor files, generated output (`dist/` and `tmp/`), installed Bower dependencies, coverage output, and Ember Try temporary dependencies. The usual automatic ignoring of `node_modules` does not need an override.
