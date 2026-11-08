SyntaxError: Unexpected token {
When using transcludeStringSync and there are multiple parse errors the Error handling errors...

```
SyntaxError: Unexpected token {
    at Object.parse (native)
    at Object.transcludeStringSync (.../node_modules/hercule/lib/hercule.js:127:33)
```

When logging the error before it's rethrown it contains:
```
{"errno":-2,"code":"ENOENT","syscall":"open","path":"somepath","msg":"Could not read file"}{"errno":-2,"code":"ENOENT","syscall":"open","path":"someotherpatht","msg":"Could not read file"}
```

### Additional contract requirements

When `transcludeStringSync` encounters multiple failing links, it must report a transclusion error rather than throw a JSON-parsing `SyntaxError` while handling the errors.
