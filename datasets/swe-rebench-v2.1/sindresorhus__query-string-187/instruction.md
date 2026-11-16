TypeError when both parseBooleans and parseNumbers are enabled
Repro:
```js
const queryString = require('query-string');

queryString.parse(
  'num=1.23&bool=false', { parseNumbers: true, parseBooleans: true }
);
```
Results in error
```
/home/user/project/node_modules/query-string/index.js:209
                if (options.parseBooleans && value !== null && (value.toLowerCase() === 'true' || value.toLowerCase() === 'false')) {
                                                                      ^

TypeError: value.toLowerCase is not a function
```

Using query-string 6.8.0 and node 10.16.0
