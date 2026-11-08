Globals configuration is unintuitive
Previous issues: https://github.com/eslint/eslint/issues/4734, https://github.com/eslint/eslint/issues/5765

# Background

Currently (ESLint v4.17.0), the `globals` value in a config file allows a user to configure globals for their project. The configuration looks like this, where each global is given a boolean value:

```json
{
  "globals": {
    "Foo": true,
    "Bar": false,
    "baz": false
  }
}
```

Similarly, a boolean value can be used in a `/* global */` comment directive to enable globals for a file:

```js
/* global Foo: true, Bar: false, baz: false */
```

A value of `true` indicates that a global is allowed to be rewritten, and a value of `false` indicates that a global is read-only. This behavior is inherited from JSHint and JSLint.

# Problem

There are a few disadvantages to the current behavior:

* Globals from an inherited config file cannot be turned off; they can only be reconfigured to `true` (rewritable) and `false` (read-only). This will make it more complex to enable a set of globals by default in the future (e.g. when we start supporting ES6 by default), because users will not be able to disable the globals.
* The correlation between `true`/`false` and "rewritable"/"read-only" is somewhat arbitrary, which makes it confusing to users. Anecdotally, I had been on the ESLint team for almost a year before I learned that `/* global Foo: false */` would make `Foo` read-only. (I had previously thought that it would turn off `Foo`.)

The root cause of these problems is that there are three possible states of a global ("not present", "present but read-only", and "present and writable") but we only allow them to be configured with a boolean field.

# Proposal

We should start allowing string values for globals. The possible values are (bikesheddable):

* `readonly` to indicate that a global is read-only (same as `false`)
* `writable` to indicate that a global is writable (same as `true`)
* `off` to indicate that a global is not present

To encourage people to use the new forms, we should deprecate the use of `true` and `false` for configuring globals. (However, for backwards compatibility, `true` and `false` would continue to be supported without a warning for the foreseeable future.)

### Additional contract requirements

The exact string values accepted for a global are `readable` (read-only, equivalent to `false`), `writeable` (writable, equivalent to `true`), and `off` (the global is not present). These are the final names for the states described in the proposal above.

The `ConfigOps` object exported from `lib/config/config-ops.js` must provide a public method `normalizeConfigGlobal(configuredValue)` that returns the canonical string for a global's state: `"readable"`, `"writeable"`, or `"off"`. It accepts `"readable"`, `"writeable"`, `"off"`, the booleans `true` and `false`, the strings `"true"` and `"false"`, and `null`; `null` is treated as `"readable"`, and any other value is treated as `"writeable"`.

The `ConfigCommentParser` class exported from `lib/util/config-comment-parser.js` must provide a public method `parseStringConfig(string, comment)` that returns an object mapping each identifier found in the comment text to `{ value, comment }`, where `value` is the literal string following the identifier's colon, or `null` when no value is given, and `comment` is the comment node passed in.
