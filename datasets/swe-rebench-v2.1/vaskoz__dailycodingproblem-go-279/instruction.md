Day 134
Good morning! Here's your coding interview problem for today.

This problem was asked by Facebook.

You have a large array with most of the elements as zero.

Use a more space-efficient data structure, SparseArray, that implements the same interface:
```
init(arr, size): initialize with the original large array and size.
set(i, val): updates index at i with val.
get(i): gets the value at index i.
```

### Additional contract requirements

In this Go package, `NewSparseArray(arr []int) *SparseArray` initializes the structure from the slice. `Set(i, val int) error` updates an index, and `Get(i int) (int, error)` returns its value. The value behavior applies to valid indexes; no particular error behavior is required.
