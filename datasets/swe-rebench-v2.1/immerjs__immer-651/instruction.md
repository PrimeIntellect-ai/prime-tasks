Error when working with immutable arrays with modified slice() method (`seamless-immutable`)
## 🐛 Bug Report

First of all, thanks for the great tool! I'm working on a large project that has previously used [seamless-immutable](https://github.com/rtfeldman/seamless-immutable) for managing the Redux state. I would like to use `immer` for new code but it seems that `immer` fails when it tries to shallow-copy an array with an overridden `slice()`. The overridden `slice()` produces a new readonly array which is not what `immer` expects.

[HIDDEN] I think many would benefit from this kind of compatibility. Will be happy to make a PR.

## Link to repro

https://codesandbox.io/s/immer-sandbox-j7ke0

## To Reproduce

Steps to reproduce the behavior: see the error in the sandbox when used in combination with `seamless-immutable`.

## Observed behavior

An error: `"Cannot assign to read only property '0' of object '[object Array]'"`

## Expected behavior

Producing a result as designed.

## Environment

We only accept bug reports against the latest Immer version.

- **Immer version:**
- [x] I filed this report against the _latest_ version of Immer
- [x] Occurs with `setUseProxies(true)`
- [x] Occurs with `setUseProxies(false)` (ES5 only)

### Additional contract requirements

- Updating a draft that contains an array with an overridden `slice()` method that returns a read-only array must succeed and preserve the intended update.
