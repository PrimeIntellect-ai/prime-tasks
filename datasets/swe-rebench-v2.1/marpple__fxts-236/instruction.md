Change `reduce` behavior, When there are two arguments for `reduce`, and the first iterator value is done:true

### suggestion
If there are three arguments for `reduce`, there is no issue.
In the case of two arguments for `reduce` and the first iterator value is done:true, I think it should throw an error

### why?
When there are two arguments for reduce, and the first iterator value is done:true, it creates an ambiguous situation regarding the return value.
If we choose to pass `undefined` in this case, the return type should also reflect the potential presence of `undefined` type ex) `T | undefined`

### other case
This behavior also applies to `Array.prototype.reduce`, where the same error will occur.
<img width="476" alt="image" src="https://github.com/marpple/FxTS/assets/10924072/6769f488-c41c-4e7a-9217-4c62b11c6d71">

Also, for Iterator Helpers `reduce`, in the mentioned scenario, a TypeError should be raised   in https://tc39.es/proposal-iterator-helpers/#sec-iteratorprototype.reduce.

### Additional contract requirements

- `reduce` also supports an asynchronous iterable as its second argument (the two-argument, no-seed form). When that asynchronous iterable yields no values, the returned promise rejects with an error rather than resolving to `undefined`.
