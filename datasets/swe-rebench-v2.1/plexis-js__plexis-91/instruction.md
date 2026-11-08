Feature: `compare / compareLikeHuman / naturalCompare`
For most cases, humans do not sort text as machines do.

```javascript
["A friend", 'Boo', "another one"].sort()
// => ["A friend", "Boo", "another one"] 😬
```

Let's fix that :)

```javascript
/**
 * @description Compares input text as humans do.
 * @param {String} first
 * @param {String} second
 * @returns {Integer}
 * @example
 * compare('', '') // => 0
 * compare('A', 'a') // => 1
 * compare('A', 'b') // => 1
 * compare('A woman', 'a woman') // => 1
 * compare('b', 'B') // => -1
 * compare('C', 'b') // => -1
 * compare('Qux20', 'Qux5') // => -1
 * compare('Qux10', 'Qux11') // => 1
 */
```


**Aliases**

```javascript
import compare from '@plexis/compare';
import {compare, compareLikeHuman, naturalCompare} from 'plexis';
```

### Additional contract requirements

- In the `plexis` export-name list, `compare`, `compareLikeHuman`, and `naturalCompare` must appear in that order, immediately after `__esModule` and immediately before `compose`.
