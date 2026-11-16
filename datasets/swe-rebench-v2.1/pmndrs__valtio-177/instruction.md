Immer-like patches
Hi. Any chance this library could support something like immer patches? It would be an efficient mechanism to implement undo history and distribute state changes (e.g. via websocket), since only state deltas are stored.

Something similar was mentioned here https://github.com/pmndrs/valtio/issues/89.

Immer patches for references https://immerjs.github.io/immer/patches/.

### Additional contract requirements

- Add a public function `subscribe(proxyObject, callback, notifyInSync?)` exported from the package root (`src/index.ts`). It returns an unsubscribe function that detaches the listener when called. `callback` receives an array of operation descriptors describing the mutations performed since the previous notification. Each descriptor is one of:
  - `['set', path, value, previousValue]`
  - `['delete', path, previousValue]`
  - `['resolve', path, value]`
  - `['reject', path, error]`
  where `path` is an array of the string or symbol keys leading to the mutated property, including nested paths.
- Add a public function `subscribeKey(proxyObject, key, callback, notifyInSync?)` exported from `src/utils.ts`. It returns an unsubscribe function. `callback` is invoked with the new value of `key` when that property changes, and only when the value is actually different.
- For both functions, when `notifyInSync` is `true` the notification is delivered synchronously with the mutation; otherwise it is deferred.
