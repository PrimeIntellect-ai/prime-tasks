False positives with `no-array-prototype-extensions` rule
[no-array-prototype-extensions](https://github.com/ember-cli/eslint-plugin-ember/blob/master/docs/rules/no-array-prototype-extensions.md)

False positives with these common non-array classes:

* `window.localStorage.clear();`
* `Promise.reject();`
* `Promise.reject('foo');`

Please comment on this issue with any other examples you notice.

Potential mitigations:

* We could assume capitalized variables like `Promise` are not arrays as they are more-likely to be classes based on naming convention
* We could ignore known globals like `window` / known variables like `window.localStorage`

CC: @smilland
