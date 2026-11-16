Binary and octal number literals are not transpiled if base prefix is uppercase
Both `0B` and `0O' are [valid](https://tc39.github.io/ecma262/#sec-literals-numeric-literals) base prefixes. Example:
```js
0B01100 === 0O14
```
