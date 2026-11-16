Disallow noop `setupOnerror` in before/beforeEach
Right now nothing prevents engineers to setup noop error handler in before/beforeEach which will swallow all rejection and errors in the module. We should not allow to use noop setupOnerror in before/beforeEach since it could mask errors/rejections in tests unintentionally.

### Additional contract requirements

- The rule is exposed as a module at `lib/rules/no-noop-setup-on-error-in-before.js` and registered in `lib/index.js` under the rule name `no-noop-setup-on-error-in-before`.
- The rule is autofixable: its fix removes the no-op `setupOnerror(...)` call expression together with its trailing semicolon, leaving the surrounding source otherwise unchanged.
