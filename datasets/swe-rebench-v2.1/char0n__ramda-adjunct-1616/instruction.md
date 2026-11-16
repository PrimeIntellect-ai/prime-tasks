catchP
**Is your feature request related to a problem? Please describe.**

Functional alternative for `Promise.catch`

**Describe the solution you'd like**
```js
const promise = Promise.reject(3);
RA.catchP(console.dir, promise); //=> outputs 3
```
Possible implementation
```js
[HIDDEN]
```

**Describe alternatives you've considered**
--

**Additional context**
[Promise.prototype.catch](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise/catch)

### Additional contract requirements

- `catchP` is a public function exported from the package as `RA.catchP`.
- `catchP(onRejected, promise)` takes a rejection handler `onRejected` and a `Promise`, and returns a `Promise`.
- `catchP` supports currying: `catchP(onRejected)(promise)` behaves the same as `catchP(onRejected, promise)`.
- If the input promise fulfills, the returned promise resolves with the original fulfillment value.
- If the input promise rejects, the returned promise resolves with the value returned by `onRejected`.
- `onRejected` may return a value or a Promise of a value; the returned promise resolves with the handler's eventual result.
- If `onRejected` throws, the returned promise rejects with that error.
- Supplying a thenable or a non-thenable value (anything that is not a genuine `Promise`) throws a synchronous `TypeError`.
