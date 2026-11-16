Edge-case crashes & false-positives in no-statement-after-end with unreachable statements
The path analysis logic in `no-statement-after-end` doesn't properly handle unreachable statements, sometimes causing crashes or false-positives.

In `eslint` (tested in v6 and v7), `CodePathSegment`s end when encountering e.g. `return` or `throw`. Unreachable statements after that point don't appear to be in any `CodePathSegment`. This can cause `no-statement-after-end` to crash when trying to analyze unreachable statements in the global scope or to treat unreachable statements in one path as reachable statements in the next outermost path.

Example of a crash:
```javascript
const test = require('ava');

throw new Error('make some unreachable code');

1; // <-- triggers a crash
```

Example of a false positive:
```javascript
const test = require('ava');

test.cb(t => {
  function newCodePath() {
    throw new Error('make some unreachable code');
    // Now we're in the outer scope, according to the rule
    t.end();
  }

  // Now the rule thinks we've ended.
  1; // <-- triggers a report
});
```

This came up while writing tests for avajs/ava#1424.

This is unlikely to affect many users, since triggering it requires very odd and/or obviously incorrect code.

I'm working on a PR to fix this presently.
