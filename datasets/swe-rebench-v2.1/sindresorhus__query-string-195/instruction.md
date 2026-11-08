parse with option `parseNumbers: true` cause unexpected behavior
When an incomplete param are passed like `search=` the result is unexpected.

*case*
```js
const queryString = require('query-string'); // 6.8.1
const queryObject = queryString.parse('search=', { parseNumbers: true });
console.log(queryObject);
```

*received result*
```js
{ search: 0 }
```


*expected result*
```js
{ search: '' }; // or
{ }
```
