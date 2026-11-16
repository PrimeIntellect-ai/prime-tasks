When ImmerJS processes objects containing Symbol keys, the Symbols become Proxies.
## 🙋‍♂ Question

Hello everyone,

I recently started using ImmerJS and encountered a challenging issue. In my data structure, there is a property with a key as Symbol, which is only used for querying purposes and will not be modified when using ImmerJS. Specifically, I try to query and modify certain data through `v[S1].id`.

However, when outputting the result in the console, I noticed that although the corresponding value was successfully modified, strangely my Symbol key `S1` was converted into a Proxy object. This has left me feeling very confused and frustrated.

Could you please let me know if this is a known bug or behavior caused by some boundary conditions? If anyone can provide an explanation or point to relevant documentation/discussion links, I would greatly appreciate it. Thank you all!

![image](https://github.com/immerjs/immer/assets/32004925/7546a9fc-a394-425c-a8c7-52cb3a730e27)


## Link to repro

~~Please provide a [CodeSandbox demo](https://codesandbox.io/s/immer-sandbox-6wijw) to clarify your question if possible. Typically, questions without minimal codesandbox demo won't be answered.~~

## Environment

We only accept questions against the latest Immer version.

- **Immer version:**
- [x] Occurs with `setUseProxies(true)`
- [ ] Occurs with `setUseProxies(false)` (ES5 only)

version: `"immer": "^10.0.2"`

### Additional contract requirements

- When a recipe reads an object-valued property keyed by a Symbol while modifying another property, the produced result must retain a usable value at that Symbol property, not a revoked proxy.
