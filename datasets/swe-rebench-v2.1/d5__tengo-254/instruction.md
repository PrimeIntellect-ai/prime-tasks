builtin function splice
JS `splice` function looks like [this](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Array/splice)
```js
let arrDeletedItems = array.splice(start[, deleteCount[, item1[, item2[, ...]]]])
```
I can implement it like this for tengo
```golang
deleted_items := splice(array, start[, delete_count[, item1[, item2[, ...]]]])
```
if `delete_count` is not provided, JS deletes the array items starting from the `start` to the end. If `delete_count` is provided, after deletion (if greater than 0), item1, item2, etc. are inserted to the original array. If `delete_count` is 0 and items are provided then it inserts the items to the array starting from `start` index and nothing deleted from the array. It appends, deletes and inserts with the same function.
What do you think?

### Additional contract requirements

- The builtin is registered under the name `splice` and is invoked as
  `splice(array, start, delete_count, item1, item2, ...)`.
- The first argument must be an array; `start` and `delete_count` must be
  integers.
- Calling `splice` with no arguments reports `ErrWrongNumArguments`. An
  argument of the wrong type reports `ErrInvalidArgumentType` naming the
  argument position (`first`, `second`, or `third`).
- A negative `start`, a `start` greater than the length of the array, or a
  negative `delete_count` reports `ErrIndexOutOfBounds`.
- When `delete_count` is larger than the number of items from `start` to the
  end of the array, only the available items are removed; the count is
  clamped to the end of the array and this is not an error.
- `splice` returns the removed items as a new array (empty when nothing is
  removed) and modifies the original array in place.
