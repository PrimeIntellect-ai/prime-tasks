Appending to array using patch inserts element at beginning of array instead of the end
## 🐛 Bug Report

When using the `applyPatches` feature of immer with a patch that should append an element to the end of an array, the element is instead inserted at the beginning of the array.

## Link to repro

Using the [example from the JSON Patch RFC](https://datatracker.ietf.org/doc/html/rfc6902/#appendix-A.16):

>    An example target JSON document:
>
>    { "foo": ["bar"] }
>
>    A JSON Patch document:
>
>    [
>      { "op": "add", "path": "/foo/-", "value": ["abc", "def"] }
>    ]
>
>    The resulting JSON document:
>
>    { "foo": ["bar", ["abc", "def"]] }

Doing so with immer instead creates the state:

```
//  { "foo": [ ["abc", "def"], "bar"]}
```

See https://codesandbox.io/s/immer-patch-append-ordering-repro-xi4d6 for a running version.

## Expected behavior

The element should be at the end of the array, not the beginning.

## Environment

- **Immer version:** 9.0.6
- [x] I filed this report against the _latest_ version of Immer
- [ ] Occurs with `setUseProxies(true)` n/a
- [ ] Occurs with `setUseProxies(false)` (ES5 only) n/a
