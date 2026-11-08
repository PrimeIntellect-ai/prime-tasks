to_json() on a nested data structure containing undefined should not fail
**Describe the bug**

When calling `to_json` on an object like `{foo: undefined}`, it should result in `{}` and not panic.  Here are some various behaviors (demo's using Node) which it would be good to follow:

```
> JSON.stringify({foo: undefined, bar: 1})
'{"bar":1}'
> JSON.stringify(undefined)
undefined
> JSON.stringify([1,2,undefined,4])
'[1,2,null,4]'
```

For context, I'm building a 3rd-party plugin system for [Yaak](https://yaak.app) using Boa and users may return a nested data structure that contain `undefined` values.

**To Reproduce**

Return an object from the JS context and call `to_json` on it.

```javascript
export function callMe() {
  return { foo: undefined };
}
```

**Expected behavior**

The value should serialize to `{}` and not throw `not yet implemented: undefined to JSON`.

**Build environment (please complete the following information):**

- OS: macOS
- Version: 14
- Target triple: `aarch64-apple-darwin`
- Rustc version: `rustc 1.77.2 (25ef9e3d8 2024-04-09)`

**Additional context**

The current workaround is to return `JSON.parse(JSON.stringify(objectContainingUndefineds))`. However, as I'm using Boa to build a plugin system, I wouldn't expect users to have to do this themselves.

Another potential workaround is to recursively crawl the `JSValue` and remove undefined values from all the objects and arrays.

Thanks for taking the time to look into this!
