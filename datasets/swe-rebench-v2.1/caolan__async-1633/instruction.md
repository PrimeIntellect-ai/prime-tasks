Feature request: reflect() should return values even when there is error
I have a function that will always return a "fallback" value to the callback, even if there's an error. I would really like reflect() / reflectAll() to capture this value.

For example:

```
function myFunc(callback){
    return callback('my error, 'my fallback value')
}

async.parallel(reflectAll({
   myval: myFunc
}), function(err, r){
    // r.myval.error = 'my error'
    // r.myval.value = 'my fallback value'
});
```

### Additional contract requirements

- `async.reflect(fn)` is a public function. It wraps a Node-style function `fn` and returns a new function whose callback is always invoked with `null` as its first argument and a result object as its second argument.
- The result object has an `error` property when the wrapped function reports an error, and a `value` property when it reports a result. When the wrapped function reports both an error and a result value, the result object has both `error` and `value`.
- When the wrapped function reports an error and invokes its callback with a result argument whose value is `undefined`, the result object has both `error` and `value: undefined`.
- When the wrapped function reports only an error without a result argument, the result object has only `error`.
- A single result value is stored directly in `value`; multiple result values are stored as an array in `value`.
- `async.reflectAll(tasks)` is a public function that accepts an object of tasks and returns a new object in which every task is replaced by its reflected version, so the object can be run with `async.parallel` or `async.series`.
