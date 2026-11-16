Tweak autofix for `sortBy` in `no-array-prototype-extensions` rule
Follow-up to https://github.com/ember-cli/eslint-plugin-ember/pull/1621/files.

before:

```js
"something.sortBy('abc')",
```

after (current):

```js
import { get } from '@ember/object';
import { compare } from '@ember/utils';

something.sort((a, b) => {
  for (const key of ['abc']) {
    const compareValue = compare(get(a, key), get(b, key));
    if (compareValue) {
      return compareValue;
    }
  }
  return 0;
});
```

after (desired):

```js
import { get } from '@ember/object';
import { compare } from '@ember/utils';

something.sort((a, b) => {
  const key = 'abc';
  const compareValue = compare(get(a, key), get(b, key));
  if (compareValue) {
    return compareValue;
  }
  return 0;
});

```

We can avoid the for-of loop if there is only one sort key.

CC: @tgvrssanthosh

### Additional contract requirements

- For `something.sortBy(getKey())`, the autofix must evaluate `getKey()` once per comparator invocation and use the resulting key to compare both items.
