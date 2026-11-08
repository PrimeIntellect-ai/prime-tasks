'else if' clauses cannot be used as program return value?
Running the following webppl program:
```js
if (true) {
    0;
} else if (true) {
    1;
}
```
results in the following error from the webppl compiler:
```
/Users/dritchie/Git/webppl-fork/src/syntax.js:94
  if (nodes.length === 0) {
           ^

TypeError: Cannot read property 'length' of undefined
    at returnify (/Users/dritchie/Git/webppl-fork/src/syntax.js:94:12)
    at Array.<anonymous> (/Users/dritchie/Git/webppl-fork/src/syntax.js:112:62)
    at Array.<anonymous> (/Users/dritchie/Git/webppl-fork/src/syntax.js:30:27)
    at match (/Users/dritchie/Git/webppl-fork/src/syntax.js:47:27)
    at returnify (/Users/dritchie/Git/webppl-fork/src/syntax.js:98:22)
    at thunkify (/Users/dritchie/Git/webppl-fork/src/syntax.js:152:32)
    at /Users/dritchie/Git/webppl-fork/node_modules/lodash/lodash.js:5157:35
    at /Users/dritchie/Git/webppl-fork/node_modules/lodash/lodash.js:5157:35
    at _compile (/Users/dritchie/Git/webppl-fork/src/main.js:189:7)
    at Object.timeif (/Users/dritchie/Git/webppl-fork/src/util.js:270:37)
```
The program runs fine if the `else if` clause is removed, or if an `else` clause is used instead.
