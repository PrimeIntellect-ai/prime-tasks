Rule proposal: forbid top level before / after hooks
Those should be only used in a describe block

### Additional contract requirements

- The rule is provided by the module `lib/rules/no-top-level-hooks.js` and is exposed by the plugin under the name `no-top-level-hooks`.
- When a hook is used outside of a test suite, the reported message has the form: Unexpected use of Mocha `<hook>` hook outside of a test suite, where `<hook>` is the name of the hook (`before`, `after`, `beforeEach` or `afterEach`).
