reshape()
I think it might be useful to have a `reshape()` function that accepts a matrix and a list of dimensions, and formats the matrix to fit the specified dimensions. `resize()` does this already, but it doesn't preserve all of the elements.

```javascript
var A = [1, 2, 3, 4, 5, 6, 7, 8, 9];
A.resize([3, 3]);
/* => [[1, 0, 0],
       [2, 0, 0],
       [3, 0, 0]] */
A.reshape([3, 3]);
/* => [[1, 2, 3],
       [4, 5, 6],
       [7, 8, 9]] */
```

Thoughts? I can start working on it and submit a PR if this sounds appealing.

### Additional contract requirements

- Add a public function `math.reshape(x, sizes)`. `x` may be an array or a matrix; `sizes` is a one-dimensional array of dimension lengths. It returns a newly created reshaped array (for array input) or a matrix of the same kind as `x` (for matrix input), and does not modify `x`.
- Add a public method `reshape(size, copy)` on `DenseMatrix`. It reshapes the matrix to `size`. By default it reshapes in place and returns the same matrix instance; when `copy` is `true` it returns a reshaped copy and leaves the original matrix unchanged.
- `Matrix.prototype.reshape` throws an error, and `ImmutableDenseMatrix.prototype.reshape` throws an immutability error.
- Add a public function `reshape(array, sizes)` in the module `lib/utils/array` that returns a new array reshaped to `sizes` and does not modify `array`.
- The dimension list must contain only non-negative integers whose product equals the number of elements in the input. A zero-sized shape is valid when it matches an empty input.
- Non-integer dimension values passed to `math.reshape` are rejected with a `TypeError`. A dimension product that does not match the number of elements is rejected with a `DimensionError`. The array utility rejects non-array arguments with a `TypeError`.
