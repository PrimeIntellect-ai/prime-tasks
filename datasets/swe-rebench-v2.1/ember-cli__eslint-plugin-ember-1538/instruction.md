False positives with `no-array-prototype-extensions` rule
Further to #1534 there are additional false positives when this rule is run against [ember-file-upload](https://github.com/adopted-ember-addons/ember-file-upload/runs/7440106845?check_suite_focus=true).

- `.clear()` on a `Set` (probably on a Map, too)
- `RSVP.reject()`

If I have time tomorrow I'll open a PR to address.
