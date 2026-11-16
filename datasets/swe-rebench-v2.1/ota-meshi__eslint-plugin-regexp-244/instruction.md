`no-invisible-character`: false positive on space in `RegExp` constructor
```js
RegExp(' ') // => Unexpected invisible character. Use ' ' instead  regexp/no-invisible-character
```
