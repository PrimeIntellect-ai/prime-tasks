New Rule: require-fetch-import
Using `fetch()` without importing it causes the browser to use the native, non-wrapped `window.fetch()`. This is generally fine, but makes testing harder because this non-wrapped version does not have a built-in test waiter. Because of this it is generally better to use [ember-fetch](https://github.com/ember-cli/ember-fetch/) and explicitly `import fetch from 'fetch'`.

The new rule should look for `fetch()` calls and warn about them if there is no corresponding import.

### Additional contract requirements

- The rule is provided by a module at `lib/rules/require-fetch-import.js` and is registered in the plugin's rule list under the name `require-fetch-import`.
- Each `fetch()` call that has no corresponding import is reported with the exact message: `Explicitly import \`fetch\` instead of using \`window.fetch\``.
- The rule module exports a constant named `ERROR_MESSAGE` whose value is exactly that message string.
