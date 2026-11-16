d3.medianIndex / d3.quantileIndex?
I suggest to also have a function d3.medianIndex(). E.g. it could return an array

- with one element: the index of the corresponding element - in case the array.length is uneven
- with two elements: the indices of the elements from which the mean was taken - in case the array.length is even

### Additional contract requirements

Add a public function `medianIndex(values, valueof)` exported from the package entry point `src/index.js` (available as `d3.medianIndex`). It accepts an iterable of numbers (or objects) and an optional accessor function invoked as `(d, i, values)` that returns a numeric value for each element. It returns the zero-based index of the element to the left of the statistical median, or `undefined` for an empty input. The returned index is the element that would be selected by `quantileIndex(values, 0.5, valueof)`.

Add a public function `quantileIndex(values, p, valueof)` exported from the package entry point `src/index.js` (available as `d3.quantileIndex`). It accepts an iterable of numbers (or objects), a number `p` in the range `[0, 1]`, and an optional accessor function invoked as `(d, i, values)` that returns a numeric value for each element. It returns the zero-based index of the element to the left of the `p`-quantile, or `undefined` for an empty input. For `p <= 0` it returns the index of the minimum value; for `p >= 1` it returns the index of the maximum value.
