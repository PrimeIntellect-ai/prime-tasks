`fetch(...) instanceof Response` fails after installGlobals()
### What version of Remix are you using?

1.19

### Are all your remix dependencies & dev-dependencies using the same version?

- [X] Yes

### Steps to Reproduce

Many libraries depend `resp instanceof Response` to return true; https://github.com/panva/oauth4webapi/blob/170f44e2f7c7da60feb8a654871c56fc0a741e6b/src/index.ts#L1513 is one of such a library. However, after Remix patches the global `fetch` instance, this no longer holds.

I've  tested this with the following three scenarios:

1. vanilla environment in node 20 (works)
2. remix-run/web-fetch (works)
3. remix-run/node (doesn't work)

```
{
  // correct behavior
  console.log((await fetch("http://example.com")) instanceof Response);
}
{
  // also correct behavior
  const i = await import("@remix-run/web-fetch");
  console.log((await i.fetch("http://example.com")) instanceof i.Response);
}
{
  // incorrect behavior; fails.
  const j = await import("@remix-run/node");
  console.log((await j.fetch("http://example.com")) instanceof j.Response);
}
```

The last one is important, as this is the version of globals that's installed via `installGlobals`.

### Expected Behavior

`(await fetch(...)) instanceof Response` should return `true` for fetch and Response exposed by `remix-run/node`.

### Actual Behavior

as the exposed types from `remix-run/node` is `NodeResponse`, the `instanceof` fails.


### ❓ Question

[HIDDEN]
fetch() doesn't return correct Response type
### What version of Remix are you using?

1.7.2

### Steps to Reproduce

Inside the remix project try

```javascript
const a = await fetch('https://google.com')
console.log('a instanceof Response: ', a instanceof Response) // -> false
```

This probably has to do with this commit:
https://github.com/remix-run/remix/commit/25b4c83b10c5bc4d84ea81407e7de1a0e4f43df4#diff-87ec1c3c130fe3481b9f1c542b1d8a53548882d33c73c68b894fd442d606afc0

A current workaround I found thanks to @milamer is to include
```javascript
import { Response } from '@remix-run/web-fetch'
```
in the file.

### Expected Behavior

instanceof Response should be true

### Actual Behavior

instanceof Response is false

### Additional contract requirements

- Values created by the `Request` and `Response` exports from `@remix-run/node`, including values returned by their `clone()` methods, must pass `instanceof` checks against the corresponding exports from `@remix-run/web-fetch`.
- A response returned by `fetch` from `@remix-run/node` must pass `instanceof` checks against the `Response` exports from both packages. After `installGlobals()`, a response returned by global `fetch` must also pass an `instanceof` check against global `Response`.
