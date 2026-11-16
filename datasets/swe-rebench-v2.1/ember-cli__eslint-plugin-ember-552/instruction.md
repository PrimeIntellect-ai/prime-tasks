New Octane Rule: `no-classic-classes`
Pulled from https://github.com/ember-cli/eslint-plugin-ember/issues/533 which proposes a new set of rules for Octane related best practices

Disallow "classic" classes preferring use of native JS classes

```js
// ### Good
export default class MyComponent extends Component {
  ...
}

// This mixin usage should be okay
export default class MyService extends Service.extends(Evented) {
  ...
}

// ### Bad
export default Component.extend({
  ...
});
```

If anyone would like to implement this please comment that you'll take it and work away.

### Additional contract requirements

- The rule is published as a rule module at `lib/rules/no-classic-classes.js`, exporting an ESLint rule object with a `create(context)` function.
- The module exports a constant named `ERROR_MESSAGE_NO_CLASSIC_CLASSES` whose value is the message text used for the reported diagnostic.
- The diagnostic is reported on the `CallExpression` node of the `.extend(...)` call.
- Only classes imported from the `@ember/` namespace are reported; `.extend(...)` calls on classes imported from other libraries are not reported.
