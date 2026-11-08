"Fill labels" produces invalid code on function calls with arguments that don't use their labels
Using the "Fill labels" code action on a function call that has labeled arguments being called without the label will incorrectly add the label at the end, breaking the arity in some cases.

```gleam
list.fold(0, over: [1, 2, 3], with: fn(total, item) { total + item })
```
turns into
```gleam
list.fold(0, over: [1, 2, 3], with: fn(total, item) { total + item }, from: todo)
```
which is invalid and, promptly, raises an error.

The fix should be simple, because this doesn't happen for filling labels in records.

One option would be to just not offer the code action in this case (like it behaves for records). However, it would be extra nice if it filled in the label in the correct position, but, alas, it would also be extra work...
