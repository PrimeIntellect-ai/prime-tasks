False positive of `no-callback-in-promise` in `7.2.0`
In many different cases. Example:
```js
'use strict';
var call = require('../internals/function-call');

module.exports = function (record, fn, ITERATOR_INSTEAD_OF_RECORD) {
  var iterator = ITERATOR_INSTEAD_OF_RECORD ? record : record.iterator;
  var next = record.next;
  var step, result;
  while (!(step = call(next, iterator)).done) { // 8:24  error  Avoid calling back inside of a promise  promise/no-callback-in-promise
    result = fn(step.value);
    if (result !== undefined) return result;
  }
};
```
