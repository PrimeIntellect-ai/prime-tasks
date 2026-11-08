New Octane Rule: `no-classic-components`
Pulled from https://github.com/ember-cli/eslint-plugin-ember/issues/533 which proposes a new set of rules for Octane related best practices

Disallow usage of the `@ember/component` base class. Use `@glimmer/component` instead.

```js
// ### Good
import Component from '@glimmer/component'

// ### Bad
import Component from '@ember/component'
```

If anyone would like to implement this please comment that you'll take it and work away.
