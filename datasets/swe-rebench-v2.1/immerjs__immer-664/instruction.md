clear Map produces incorrect patches
## 🐛 Bug Report

clear Map produce incorrect patches

## Link to repro

codebox link: https://codesandbox.io/s/immer-sandbox-forked-zz8le

### immer source code
https://github.com/immerjs/immer/blob/bf90358c1bfedf0afb6e3bb016d6e6233b96e3ac/src/plugins/mapset.ts#L112
[HIDDEN]

https://github.com/immerjs/immer/blob/bf90358c1bfedf0afb6e3bb016d6e6233b96e3ac/src/plugins/patches.ts#L121-L143

is this by design? or a bug.

## To Reproduce

just run the  codesanbox link  above

## Observed behavior

`changes` is a empty array.

## Expected behavior

`changes` is `[{ type: 'Remove', path: ['t2', 't'] }]`

## Environment

We only accept bug reports against the latest Immer version.

- **Immer version:**
- [x] I filed this report against the _latest_ version of Immer
- [x] Occurs with `setUseProxies(true)`
- [ ] Occurs with `setUseProxies(false)` (ES5 only)
