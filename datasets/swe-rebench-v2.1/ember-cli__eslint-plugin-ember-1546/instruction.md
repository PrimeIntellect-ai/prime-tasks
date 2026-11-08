False positives with `no-array-prototype-extensions` rule
Further to #1534 there are additional false positives when this rule is run against [ember-file-upload](https://github.com/adopted-ember-addons/ember-file-upload/runs/7440106845?check_suite_focus=true).

- `.clear()` on a `Set` (probably on a Map, too)
- `RSVP.reject()`

If I have time tomorrow I'll open a PR to address.

### Additional contract requirements

The `no-array-prototype-extensions` rule must not report the following expressions as array prototype extensions:

- `RSVP.reject()`, `RSVP.Promise.reject()`, `Ember.RSVP.reject()`, and `Ember.RSVP.Promise.reject()`.
- `.clear()` called on a `Set` or `Map` instance, for example `const foo = new Set(); foo.clear();`.
- `this.reject()` and `this.clear()`.
- `sessionStorage?.clear()`.


- - `Promise.reject()` and `Promise.reject("some reason")`.
