default param value of " " is trimmed to an empty string ""
In the [doctrine demo](http://eslint.org/doctrine/demo/) try:
```
     * @param {string} [chars='     '] Foo.
```
Then in the dev console of the demo:
```js
var result = doctrine.parse($('#code').val(), { sloppy: true, unwrap: true });
```
You'll see the `result.tags[0]['default']` is `"''"` instead of `"'   '"`.

### Additional contract requirements

- Whitespace inside a quoted string default value is preserved exactly as written, including when the default value consists only of whitespace.
